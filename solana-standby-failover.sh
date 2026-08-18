#!/bin/bash

# bash 5.2+ made "&" special in ${var//pat/replacement} (patsub_replacement, ON by default): the
# replacement's "&" expands to the matched text, which silently corrupts _html_escape's "&lt;"/"&gt;"
# on Ubuntu 24.04 / Debian 12 — broken Telegram HTML = CRITICAL alerts silently failing to send.
# This codebase is written against bash-3.2 substitution semantics; restore them everywhere.
# (No-op error on bash < 5.2, hence the || true.)
shopt -u patsub_replacement 2>/dev/null || true

# Monotonic clock for every SAFETY duration. Wall clock (`date +%s`) is steppable — a single NTP
# makestep during an incident was measured to instantly mature the takeover delay, defeat the
# vote-liveness fence, and disarm the self-fence timers. /proc/uptime cannot step. Wall clock
# remains for logging/display only; no safety decision may compare wall-clock values.
# The test harness fallback (no /proc/uptime, e.g. the macOS test box) uses `date +%s`, which the
# suites already mock — a fake-clock suite therefore drives this helper through its `date` mock by
# shadowing `mono_now` (see tests). On the Linux deploy target /proc/uptime always exists.
mono_now() {
    local up
    if [[ -r /proc/uptime ]]; then
        read -r up _ < /proc/uptime
        up=${up%%.*}
        [[ $up -lt 1 ]] && up=1   # never emit 0: a 0 stamp means "unset" to the lockout/cooldown gates
        printf '%s' "$up"
    else
        date +%s
    fi
}

# Boot identity for the cross-reboot state semantics (see load_state): mono_now stamps are only
# comparable within the boot that wrote them. save_state records BOOT_ID next to every persisted
# safety stamp; load_state compares it to the current boot and fails restored lockouts/cooldowns
# toward HELD on any mismatch. Empty when unreadable (e.g. the macOS test harness).
boot_id() {
    local b=""
    if [[ -r /proc/sys/kernel/random/boot_id ]]; then
        read -r b _ < /proc/sys/kernel/random/boot_id
    fi
    printf '%s' "$b"
}

# Rollback safety (dual-write): the LEGACY state keys keep WALL-clock values so a daemon <= v0.6.10
# reading this file after a rollback computes correct elapsed times with its wall arithmetic — no
# "delete the state files first" operator step on the one path where nobody reads instructions.
# The *_MONO twins carry the authoritative monotonic stamps this daemon uses; load_state prefers
# them and never does arithmetic on the legacy keys. Derived per save as (wall_now - mono_elapsed),
# which self-corrects for wall steps between the event and the save. 0 stays 0 ("unset" must
# survive the conversion). _SAVE_W/_SAVE_M are sampled once per save_state call.
_m2w() {
    local m="$1"
    if [[ "$m" =~ ^[0-9]+$ ]] && [[ $m -gt 0 ]]; then
        printf '%s' $(( _SAVE_W - _SAVE_M + m ))
    else
        printf '0'
    fi
}

# ============================================================================
# Solana STANDBY Node Failover Protection v0.6.10 (THREE-TIER RPC)
# Runs on HOT SPARE node. Monitors via 3-tier RPC.
#
# THREE-TIER (STANDBY perspective):
#   LOCAL RPC    : detect staked identity delinquency (FREE, every cycle)
#   Tier 1 LOCAL : check OWN health (am I caught up? can I take over?)
#   Tier 2 PAID  : confirm delinquency (only when window triggered)
#   Tier 3 PUBLIC: fallback confirmation + gossip verify PRIMARY dropped
#
# FLOW:
#   LOCAL: staked delinquent? → yes → push to window → 7/10? → yes →
#   EXTERNAL CONFIRM (T2 or T3) → gossip check → TAKE OVER
#   Alchemy only called for confirmation (saves CU)
#
# ============================================================================

set +e

# ========================= CONFIG (defaults, overridden by failover-standby.env) ==
# --- Node ---
NODE_NAME="MY_VALIDATOR-STANDBY"
VALIDATOR_TYPE="agave"

# --- Paths ---
STAKED_KEYPAIR="/root/solana/mainnet-validator-keypair.json"
UNSTAKED_KEYPAIR="/root/solana/unstaked-standby.json"
SOLANA_PATH="$HOME/.local/share/solana/install/active_release/bin"
LEDGER_PATH=""
CONFIG_TOML=""
VALIDATOR_SERVICE="solana"                # systemd unit name of the validator (ledger auto-detect fallback)

# --- Three-Tier RPC ---
LOCAL_RPC="http://127.0.0.1:8899"                                               # Tier 1: own health check
TIER2_RPC=""                                                                     # Tier 2: paid RPC (Alchemy/Helius/Triton)
TIER3_RPC="https://api.mainnet-beta.solana.com"                                  # Tier 3: confirm + gossip

# --- Monitoring ---
VOTE_PUBKEY=""                            # vote account pubkey (REQUIRED!)
STAKED_PUBKEY_OVERRIDE=""                 # if set, skip deriving from keypair

# --- Thresholds ---
CHECK_INTERVAL=5                          # seconds between checks (normal mode)
TURBO_INTERVAL=1                          # seconds between checks (turbo: when delinquency detected)
# shellcheck disable=SC2034  # reserved: legacy var still written by deploy/env, kept for compat
DELINQUENCY_RETRIES=5                     # (legacy, used by deploy) replaced by sliding window
# shellcheck disable=SC2034  # reserved: config knob (STANDBY has no ping path; honored on PRIMARY)
CONNECTIVITY_TIMEOUT=2
STARTUP_GRACE=30
TAKEOVER_COOLDOWN=120
# v0.6.1 (F2): min seconds between external re-confirm attempts while a triggered
# window is "held" because T2+T3 are unreachable. Stops turbo (1s) from hammering
# dead external RPCs every cycle. The window is preserved across the throttle.
EXTERNAL_CONFIRM_THROTTLE=12

# How far behind = delinquent (0 = use RPC delinquent list as-is)
MAX_DELINQUENT_SLOTS=0

# --- Safety ---
# v0.5.9: DRY_RUN=true is the safe default. Live mode requires explicit DRY_RUN=false in env.
DRY_RUN=true
TAKEOVER_DELAY=60                         # seconds of confirmed delinquency before takeover
# v0.7 (Block 3, slice 4): page when a delinquency episode has been held >= this many seconds with
# no takeover (blindness re-anchors, provider flips and span-floor holds can hold the take
# SILENTLY — see _maybe_starvation_page). Repeats per ALERT_THROTTLE; 0 = off. Observability only —
# changes no verdict, triggers no action.
TAKEOVER_STARVATION_ALERT_SECS=300
GOSSIP_VERIFY=true                        # verify PRIMARY dropped via gossip
GIVE_BACK_MODE="manual"                   # "manual" = never auto give-back (the only implemented mode — v0.6.9 M6: "auto" is coerced to manual with a warning)

# --- STANDBY self-fence for the PROMOTED holder (v0.6.9 H1 — ported from the PRIMARY) ---
# After a takeover this node HOLDS and VOTES the staked identity — and inherits the PRIMARY's residual:
# a partitioned-but-voting promoted STANDBY + a BACKUP at TAKEOVER_DELAY=120s is the documented
# SPLIT-BRAIN-RESIDUAL scenario. While STAKED, watch LOCAL signals ONLY (an external-RPC outage must
# never trigger a demote) and give the identity back to our OWN unstaked key during the partition —
# before a heal can double-sign. Same signals, same knob names, same defaults as the PRIMARY:
# frozen confirmed slot / silent LOCAL RPC / N6 own-vote-lag (with B2 hysteresis) / optional getHealth.
# Fail-safe: it can ONLY ever lead to give_back_identity (the safe direction) + the re-take lockout.
STANDBY_SELF_FENCE=true                   # master kill switch (false = old v0.6.8 "hold unfenced" behavior)
SELF_FENCE_ISOLATION_SECS=30              # LOCAL getSlot(confirmed) must advance within this window
SELF_FENCE_MAX_BEHIND=150                 # optional LOCAL getHealth "behind by >N" demote (0 = off)
SELF_FENCE_NOANSWER_SECS=30               # continuous LOCAL no-answer while staked (baseline-armed; 0 = off)
SELF_FENCE_VOTE_LAG_SLOTS=32              # N6: own-vote lag past same-payload cluster-max (0 = off)
SELF_FENCE_VOTE_LAG_SECS=20               # N6: sustained seconds over threshold before demoting (0 = off)
SELF_FENCE_VOTE_LAG_RESET_CYCLES=3        # B2 hysteresis: consecutive healthy cycles to clear the sustain timer (>= 2)
# v0.6.9 (H4, B1 parity): bound every take/give-back admin-socket call (same socket get_local_identity
# wraps in `timeout 8`). On a GIVE-BACK (holder demote) timeout, escalate per SELF_FENCE_HARD_STOP; on a
# TAKE (spare promote) timeout, NEVER escalate — re-read what applied and fail toward NOT taking.
SETIDENTITY_TIMEOUT=15
# v0.6.9 (H1, B1 port): when a give-back (demote) wedges and the identity did not flip, hard-stop the
# validator (systemctl stop → mask --runtime → SIGTERM → SIGKILL, verified + re-verified per H2) so the
# staked identity provably stops voting. false = alert only (NOT recommended — leaves the gap open).
SELF_FENCE_HARD_STOP=true
# v0.6.9 (H2): re-verify the hard-stop after this many seconds (>= typical RestartSec) — a directly-
# killed validator under Restart=always resurrects VOTING STAKED after the immediate verify passed.
HARD_STOP_REVERIFY_SECS=15
# v0.6.9 (H1.3, safety-critical): post-self-fence RE-TAKE LOCKOUT. After a self-fence demote the staked
# vote account WILL look delinquent+frozen (WE were the voter and we stopped) — every normal takeover
# gate would pass and this node would re-take the identity it just dropped. attempt_takeover refuses
# until this many seconds elapse AND all normal gates (external confirm + vote-liveness) pass fresh.
# 0 disables the lockout (NOT recommended). FAILURE DIRECTION: toward NOT taking (availability loss).
SELF_FENCE_RETAKE_COOLDOWN=600
# v0.6.9 (M5): collision detector — while STAKED, compare gossip's view of the staked pubkey's endpoint
# (T2/T3) against our OWN (LOCAL). 2 consecutive mismatch strikes → 🚨 page. DETECTION-ONLY, never demotes.
COLLISION_CHECK_INTERVAL=60

# v0.6.5 (F3): ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN is DEPRECATED and ignored. It promised an
# emergency local-only takeover when both external RPCs are down, but the authoritative vote-liveness
# fence ALSO needs T2/T3 to sample lastVote — with both externals down it returns "cannot determine →
# BLOCK", so the takeover blocks regardless. The one explicit emergency local-only path is
# ALLOW_UNFENCED_TAKEOVER=true + VOTE_LIVENESS_VERIFY=false (which removes the split-brain fence). If
# the old knob is still set true in an env, startup_checks warns and the value is otherwise unused.

# --- Vote-liveness fence (v0.6.2 C1/N4; AUTHORITATIVE in v0.6.3 Block 1) ---
# The authoritative split-brain fence: is the staked vote account producing votes RIGHT NOW?
# Topology-independent — it does not care which IP/port holds the identity or how many servers
# exist, only whether SOMEONE is voting it. ALL roles (incl. BACKUP) use it. v0.6.3 makes this
# the SINGLE authoritative gate (gossip is advisory only — a staked pubkey's gossip entry persists
# ~48h in CRDS, so a stale entry must not block a takeover that liveness has cleared).
VOTE_LIVENESS_VERIFY=true
# v0.7 (Block 3, slice 3 / AUDIT-5 A3): EPSILON 2 → 0 — ANY forward movement of lastVote is life.
# Measured: at ε=2 a still-voting holder advancing +1..+2 slots over the window read FROZEN and the
# spare TOOK under a live holder (single honest RPC, zero clock skew); at ε=0 it never took.
# DEPENDENCY: ε=0 PRESUMES the provider-pinned pair (slice 2, staked_is_actively_voting) — only a
# same-vantage pair may render FROZEN, so cross-provider lag can no longer be absorbed by (or read
# as) vote movement. Do NOT raise ε to "fix" provider flapping: unpinned, ε=0 converts absorbed
# skew into false VOTING at one re-anchored TAKEOVER_DELAY per event (under strict provider
# alternation: 0 ALLOW verdicts out of 10) — fix the provider, not the constant. Accepted cost
# The same starvation regime exists INSIDE one pinned URL: a load-balanced pool alternating a
# fresh backend with one wedged pre-burst loops VOTING/rc2 forever at eps=0 (the pin cannot see
# intra-URL backends) — availability-only, pages, and the fix is the same: a stable vantage.
# Cost bounds, honestly: +[60,70]s is PER OBSERVATION (one converged flip); an unconverged flip
# can cost ~2x TAKEOVER_DELAY. The no-deadlock claim is the load-bearing one and holds
# universally: a dead node's lastVote is a fixed number every vantage converges to.
# (measured, AUDIT-5): a DEAD holder with one stray +1 burst observed at decision time takes
# ≈ +70s longer (one N3 re-anchor + one VOTE_LIVENESS_MIN_INTERVAL) and the takeover still
# completes — a dead node's lastVote is a fixed number every provider converges to, so ε=0 cannot
# deadlock.
VOTE_LIVENESS_EPSILON=0                   # lastVote must advance > this many slots to count as "voting" (0 = ANY advance)
VOTE_LIVENESS_MIN_INTERVAL=10             # min seconds between the two lastVote samples for a valid delta
# ── v0.7 (Block 3, slice 4) — OBSERVATION-SPAN FLOOR (RATIFIED by the reviewer, 2026-08-17) ────
# A FROZEN-based take must rest on at least this many seconds of OBSERVED span since the EPISODE's
# first successful external observation (or since the end of the last blind cycle) — measured from
# _liveness_obs_since, NOT the re-basable pair pin (see _liveness_span_short for the correctness
# argument and the non-convergent first cut's history). Closes the residual A9a/S-3 tail: a
# late-observed episode (first sample only pinned after the delay already elapsed) could otherwise
# reach the frozen verdict on a pair just VOTE_LIVENESS_MIN_INTERVAL (~10s) apart — violating the
# documented claim "only a holder landing ZERO votes for the ENTIRE delay reads frozen" (measured:
# take at t0+10s). 40 makes the NORMAL live-tested path a strict no-op (first sample ≈ window
# trigger t+15, take at t+66 → span ≈ 51s > 40) — only late-observation episodes wait. Floor not
# met → "cannot determine yet" (never a verdict). 0 = disabled (the config-drift table announces
# it). Revert = delete this knob + _liveness_span_short + its call-site hunks.
VOTE_LIVENESS_MIN_SPAN=40                 # min OBSERVED seconds this episode behind a FROZEN-based take (0 = off)
# Honest cost enumeration (verifier, slice 4): the "strict no-op" holds when the episode's first
# observation lands within ~20s of first-delinquency (live-tested ~15s; a slow window fill pays the
# difference, capped +30s). Pair re-bases (tip-stall, backwards, provider flip) do NOT restart the
# span — only blindness does (and blindness already re-anchors the whole countdown, so the floor is
# a strict no-op after it). All of it fails toward NOT taking.

# v0.6.3 (Block 1): vote-liveness is REQUIRED. With VOTE_LIVENESS_VERIFY=false the daemon refuses
# to start (and never takes over) UNLESS this dangerous override is explicitly set — there is then
# NO split-brain fence at all. Leave false. (Closes the old "both fences off → unfenced takeover".)
ALLOW_UNFENCED_TAKEOVER=false

# --- Cross-node fail-over timing safety (v0.6.6 N1) ---
# The PRIMARY must RELINQUISH the staked identity (its self-fence) BEFORE any spare can take it, or
# both hold staked across a partition heal → double-sign. This script cannot read the PRIMARY's
# config, so it SEMI-ENFORCES the rule: at startup it warns loudly (+ alert_warn) when
# TAKEOVER_DELAY < EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS. Keep these two in sync
# with the PRIMARY's self-fence: EXPECTED = the PRIMARY's WORST-case self-fence timer (the larger of
# its SELF_FENCE_ISOLATION_SECS / SELF_FENCE_NOANSWER_SECS — both default 30 in v0.6.6).
EXPECTED_PRIMARY_SELF_FENCE_SECS=30       # PRIMARY self-fence worst case (its larger self-fence timer)
SELF_FENCE_MARGIN_SECS=30                 # cross-node safety margin (loop granularity + set-identity + clock skew + headroom)
EXPECTED_PRIMARY_VOTE_LAG_SLOTS=32        # v0.6.8 (B2): MUST match the PRIMARY's SELF_FENCE_VOTE_LAG_SLOTS; startup asserts VOTE_LIVENESS_EPSILON <= this/4 (EPSILON << band; 0 = skip)
# v0.6.9 (M9): a cross-node timing violation (TAKEOVER_DELAY < EXPECTED + MARGIN) is now FATAL at
# startup — EXPECTED_PRIMARY_SELF_FENCE_SECS is an operator-typed claim with no runtime verification,
# so this one guard must bite. Set true ONLY for lab/testing (mirrors the ALLOW_UNFENCED double-opt-in).
# FAILURE DIRECTION: refuse-to-start — a spare that would take before the holder relinquishes is more
# dangerous than an unmonitored spare.
ALLOW_UNSAFE_TIMING=false

# --- v0.6.8 (Option A): gossip identity-flip fast-path (ADDITIVE; OFF by default; fail-closed) ---
# During the takeover countdown, if we POSITIVELY observe the holder's node now advertising its KNOWN
# unstaked identity in gossip (it self-fenced), skip the remaining timer and fall through to the SAME
# authoritative gates (external-confirm + vote-liveness==frozen). The flip skips ONLY the timer; it never
# bypasses a gate, and a non-flip cycle is the exact v0.6.7 path. Keys on the unstaked pubkey APPEARING
# (its ~15s CRDS TTL ⇒ a present entry is provably recent), NEVER on the staked entry vanishing (~48h linger).
WITNESS_FASTPATH=false                     # master switch (false = pure v0.6.7 timer behavior)
PRIMARY_UNSTAKED_PUBKEY=""                 # space-separated holder unstaked pubkey(s) to watch; empty ⇒ A disabled (fail-closed)
FASTPATH_CONFIRM_SAMPLES=2                 # consecutive corroborated cycles before firing (A2 stability)
FASTPATH_STAGGER_SECS=0                    # A3: extra per-node stagger floor (rarely needed — the node computes the required floor from STANDBY_TAKEOVER_DELAY below; this is only an additional minimum)
FASTPATH_PEER_RECOVERY_MANUAL=false        # A4: affirm ALL staked-capable peers run RECOVERY_MODE=manual (no auto re-stake). Fail-closed: A never fires unless true
# v0.6.8 (S1): the FIRST spare's (STANDBY's) TAKEOVER_DELAY. MUST be set the SAME on every spare = the
# STANDBY's TAKEOVER_DELAY. The node enforces an effective stagger = max(FASTPATH_STAGGER_SECS,
# TAKEOVER_DELAY - STANDBY_TAKEOVER_DELAY), so a BACKUP cannot fast-take ahead of the STANDBY even if
# FASTPATH_STAGGER_SECS is left 0. Empty / non-numeric / > TAKEOVER_DELAY ⇒ fast-path DISABLED (fail-closed).
STANDBY_TAKEOVER_DELAY=""
# v0.6.8 (F-B, Audit-2 r2): explicit FIRST-spare role. A ZERO stagger floor (STANDBY_TAKEOVER_DELAY >=
# TAKEOVER_DELAY) means "fast-take with no delay relative to the STANDBY" — correct ONLY for the one first
# spare (the STANDBY). There is no runtime role field, so a misconfigured BACKUP (e.g. an IaC template
# setting STANDBY_TAKEOVER_DELAY=TAKEOVER_DELAY uniformly) would inherit the same floor 0 and race the
# STANDBY into a two-spare take. Set true ONLY on the STANDBY; a BACKUP must keep it false AND set
# STANDBY_TAKEOVER_DELAY to the STANDBY's (smaller) delay. A zero floor without this true ⇒ DISABLED (fail-closed).
WITNESS_FASTPATH_FIRST_SPARE=false

# Local health: how many slots behind tip = unhealthy (skip takeover)
LOCAL_HEALTH_MAX_BEHIND=100               # if our node is >100 slots behind, don't take over

# --- Sliding window ---
DELINQUENCY_WINDOW_SIZE=10                # last N checks to consider
DELINQUENCY_WINDOW_THRESHOLD=7            # how many must be delinquent to trigger

# --- Heartbeat ---
HEARTBEAT_INTERVAL=600                    # periodic status log (seconds, 600 = 10 min)

# --- External heartbeat watchdog (v0.6.4, "dead-man's switch") ---
# Fire-and-forget liveness ping to an external alert-on-absence monitor (healthchecks.io /
# Uptime-Kuma push / cronitor / ntfy). Signals ONLY that THIS monitor process is alive and
# looping — independent of validator health. Empty = disabled. Give PRIMARY / STANDBY / BACKUP
# each a DISTINCT URL so the operator knows which node's monitor died.
HEARTBEAT_URL=""
HEARTBEAT_PING_INTERVAL=""                # ping cadence (s); empty → defaults to HEARTBEAT_INTERVAL

# --- Alpenglow feature-gate tripwire (v0.7 pre-Block-4, №9) ---
# v0.7 (pre-Block-4, №9): the on-chain feature gate that flips agave to Alpenglow/votor voting.
# Pubkey from agave v4.2.1 feature-set/src/lib.rs (`pub mod alpenglow`), verified 2026-08.
ALPENGLOW_FEATURE_ID="a1penGLz8Vm2QHYB3JPefBiU4BY3Z6JkW2k3Scw5GWP"
ALPENGLOW_GATE_CHECK_HOURS=6              # probe cadence (hours); 0 = off (drift-announced)

# --- Telegram ---
TG_ENABLED=true
TG_BOT_TOKEN=""
TG_CHAT_ID=""

# --- Webhook ---
WEBHOOK_URL=""
WEBHOOK_BODY=""

# --- Logging ---
LOG_FILE="/var/log/solana-failover-standby.log"
LOG_MAX_SIZE=52428800

# --- State persistence (v0.6.1 F7; extended v0.6.9 H3/M10) ---
# Anti-flap / anti-alert-storm timer + (v0.6.9) the promoted-holder self-fence baseline and the
# re-take lockout survive a failover-service restart (the unit is Restart=always). v0.6.9 (M10):
# role-specific default so colocated daemons (lab) cannot clobber each other's state — H3 makes this
# file load-bearing. A legacy ".../state" file is migrated once at startup (see load_state).
STATE_DIR="/var/lib/solana-failover"
STATE_FILE="/var/lib/solana-failover/state-standby"
_DEFAULT_STATE_FILE="$STATE_FILE"   # v0.6.9 (B5): the shipped default, captured BEFORE the env is sourced,
                                    # so the M10 legacy migration fires ONLY on an unmodified default path
                                    # (an operator override — even one that keeps the -standby suffix — is
                                    # never touched, matching the documented invariant).
# v0.6.9 (H3): restore the persisted self-fence baseline ONLY when the save is fresher than this many
# seconds — a stale baseline must not fire an instant false demote. FAILURE DIRECTION: discard on
# ambiguity → fresh timers (the pre-H3 behavior).
STATE_MAX_AGE_SECS=900
# v0.6.9 (H3): if the persisted state says we were STAKED (promoted holder) and the startup "waiting
# for local validator" loop exceeds this, page 🚨 once (the daemon cannot demote an unreachable
# validator; a spare may take over — intervene).
STARTUP_STAKED_UNREACHABLE_ALERT_SECS=60

# ========================= LOAD EXTERNAL CONFIG ===============================
CONFIG_FILE="$(dirname "$(readlink -f "$0")")/failover-standby.env"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# v0.6.4: heartbeat ping cadence defaults to the (possibly env-overridden) status-log interval.
# Coerce empty OR a non-numeric env typo (e.g. "off", "10s") back to the default, so a bad value
# can't be read as 0 in the throttle arithmetic and fire the ping every loop.
: "${HEARTBEAT_PING_INTERVAL:=$HEARTBEAT_INTERVAL}"
[[ "$HEARTBEAT_PING_INTERVAL" =~ ^[0-9]+$ ]] || HEARTBEAT_PING_INTERVAL=$HEARTBEAT_INTERVAL

# ========================= RUNTIME STATE ======================================
STAKED_PUBKEY=""
UNSTAKED_PUBKEY=""
CURRENT_IDENTITY=""
LAST_TAKEOVER_TIME=0
FIRST_DELINQUENT_TIME=0
# v0.6.7 (N3): last wall-clock time the staked holder was OBSERVED actively voting (vote-liveness
# returned "active"). The takeover delay is anchored to the LATER of this and FIRST_DELINQUENT_TIME,
# so the full delay re-elapses from the holder's last seen vote — a long "delinquent-but-still-voting"
# episode can no longer pre-consume the delay and let STANDBY take ~immediately once it goes silent.
LAST_LIVENESS_ACTIVE_TIME=0
_last_confirm_attempt=0                   # v0.6.1 (F2): last external-confirm timestamp (throttle)
# shellcheck disable=SC2034  # reserved: set for diagnostics; not currently read
SCRIPT_START_TIME=$(date +%s)

# Sliding window for delinquency detection
# "7 out of 10" — survives brief recoveries during DDoS flickering
_delinq_window=""

# Adaptive interval: turbo mode when delinquency detected
_turbo_mode=false
_current_interval=$CHECK_INTERVAL          # effective sleep interval (turbo changes this)

# Pre-fetched gossip result (opt #6)
_gossip_prefetched=false
_gossip_result=""

# Vote-liveness sampling (v0.6.2 C1): first lastVote sample + its wall-clock timestamp.
# v0.6.3 (Block 1): also remember a cluster-wide freshness reference (the MAX lastVote from the same
# getVoteAccounts payload) at the first sample, so the second sample can verify the RPC's view
# actually advanced (RPC-freshness guard: a stalled/cached/lagging payload serving a frozen lastVote
# across both samples would otherwise read as a false "frozen" → ALLOW).
# v0.7 (Block 3, slice 2 / AUDIT-5 A2): also remember WHICH provider tier ("T2"/"T3") served each
# sample. A liveness pair is only comparable same-vantage: a fresh-T2 first sample paired with a
# lagging-T3 second sample collapses a live holder's advance to ≤ EPSILON (false FROZEN → take under
# a live holder). _liveness_first_provider pins the pair's vantage; _liveness_sample_provider is the
# sampler's per-call answer (re-derived by $() callers from the sample's third field).
_liveness_first_vote=""
_liveness_first_tip=""
_liveness_first_ts=0
_liveness_first_provider=""
_liveness_sample_provider=""
# v0.7 (Block 3, slice 4 / AUDIT-5 S-3): mono time of the last take-path cycle on which NO external
# provider yielded a usable observation of the holder (liveness sampler empty on both tiers, or
# external confirm returned "cannot confirm"). Third input to the N3 takeover anchor — see
# INVARIANT(blindness-is-life) in attempt_takeover. 0 = no blind cycle observed this episode;
# reset with the episode (window_reset / the main-loop delinquency-cleared reset).
_last_blind_end=0
# v0.7 (Block 3, slice-4 rework): mono time of the EPISODE's first successful external observation
# (0 = none yet). Pinned by _note_observation on every successful sampler observation; reset ONLY
# by episode resets (every _last_blind_end=0 site), by blind cycles (_note_blind_cycle), and by
# the VOTING re-base (slice 5: staked_is_actively_voting's ADVANCED path and the fresh-proof
# re-check re-pin it to the verdict instant — observed LIFE restarts the observed-silence span) —
# NEVER by the non-verdict pair re-bases (tip-stall / backwards / provider flip). The
# observation-span floor measures from this, not the pair pin.
_liveness_obs_since=0
# v0.7 (Block 3, slice-4 rework): per-episode hold diagnostics for the starvation page — reset at
# every _last_blind_end=0 site (episode boundaries), incremented in the byte-identical helpers.
_ep_blind_cycles=0
_ep_provider_flips=0
_ep_floor_holds=0
# v0.7 (Block 3, slice 5): mono time of the last re-check abort page (0 = none yet). GLOBAL
# storm guard for _recheck_abort_alert — not episode state, never reset with the episode.
_recheck_abort_alert_ts=0
# v0.7 (pre-Block-4, №9): Alpenglow feature-gate tripwire state. _alpenglow_gate_state = last
# KNOWN on-chain gate state (inactive|pending|active; empty = never determined) — persisted by
# save_state, restored by load_state. _last_alpenglow_check = mono time of the last probe
# (0 = never → the FIRST check runs immediately, whatever the host uptime).
_alpenglow_gate_state=""
_last_alpenglow_check=0
# v0.7 (pre-Block-4, №9 fix A/B): probe-failure streak + blind-page throttle stamp. A failed
# probe retries on a short floor and pages once the streak says the blindness is not a blip.
_alpenglow_fail_streak=0
_last_alpenglow_blind_alert=0

_running=true
_last_status_log=0
_takeover_alert_sent=""
# v0.7 (Block 3, slice-4 rework): takeover-starvation paging state (see _maybe_starvation_page).
# Deliberately SEPARATE from _takeover_alert_sent — that latch covers the one-shot fence alert;
# starvation must keep paging (throttled by ALERT_THROTTLE).
_last_starvation_alert=0                  # mono time of the last starvation page (0 = none)
_starvation_paged=""                      # non-empty = this episode paged starvation (close notice on episode end)
# v0.6.9 (H1): promoted-holder self-fence trackers (byte-for-byte semantics of the PRIMARY's; see the
# STANDBY SELF-FENCE section). All re-armed by _selffence_reset (demote / manual change / startup).
_last_confirmed_slot=""
_last_confirmed_advance_ts=0
_selffence_noanswer_since=0
_selffence_votelag_since=0
_selffence_votelag_baseline=""
_selffence_votelag_healthy=0
# v0.6.9 (H3): restart-continuity restore hooks (see load_state / check_self_fence_isolation): the
# persisted stall/silence/lag clocks are inherited ONLY on positive first-read evidence that the
# condition is continuous; ambiguity drops them (fresh timers — never an invented stall).
_selffence_restore_pending=0
_selffence_restored_advance_ts=0
_selffence_noanswer_restore_pending=0
_selffence_restored_noanswer_since=0
_selffence_votelag_restore_pending=0
_selffence_restored_votelag_since=0
_persisted_role=""                        # role recorded in the last persisted save ("staked"/"unstaked"/"")
# v0.6.9 (H1.3): wall-clock of the last SELF-FENCE demote (0 = none). Gates attempt_takeover for
# SELF_FENCE_RETAKE_COOLDOWN seconds; persisted (a Restart=always monitor restart must not clear the
# lockout — the fenced vote account still looks delinquent, and re-taking it is the exact hazard).
SELF_FENCE_DEMOTE_TIME=0
_last_lockout_log=0                       # throttle for the lockout log line (turbo would spam it)
_last_known_identity=""                   # v0.6.9 (H1): last successfully-read identity (drives the staked-unreachable URGENT page)
# v0.6.9 (M5): collision-detector state — consecutive non-self-endpoint strikes + throttle stamps.
_collision_strikes=0
_last_collision_check=0
_last_collision_alert=0
# v0.6.8 (Option A): gossip identity-flip fast-path state (per-episode; reset in window_reset).
_fastpath_absent_seen=0                   # A2: observed the holder's unstaked pubkey ABSENT at least once this episode
_fastpath_confirm=0                       # A2: consecutive cycles the flip was corroborated on >=2 vantage points
# v0.6.8 (S1): config-derived at startup (NOT per-episode — do NOT reset in window_reset).
_fastpath_stagger_floor=0                 # effective stagger = max(FASTPATH_STAGGER_SECS, TAKEOVER_DELAY - STANDBY_TAKEOVER_DELAY)
_fastpath_disabled=""                     # non-empty reason ⇒ fast-path is fail-closed OFF (bad stagger config)
_last_heartbeat=0
_last_hb_ping=0                           # v0.6.4: last external watchdog ping (own timer)
_pending_alert=""                         # v0.6.1 (N3): retry a critical alert if Telegram blips
_unknown_identity_since=0                 # unknown-identity episode start (0 = classified)
_last_unknown_alert=0                     # re-page throttle inside an unknown-identity episode

STAT_CHECKS=0
STAT_DELINQUENT_SEEN=0
STAT_TAKEOVERS=0
STAT_TIER1_HEALTH=0
STAT_LOCAL_DELINQ=0
STAT_TIER2_CHECKS=0
STAT_TIER3_CHECKS=0

# Alert throttling (seconds between repeated alerts)
ALERT_THROTTLE=600                        # 10 minutes
_last_unreachable_alert=0
_last_behind_alert=0
_last_t2_alert=0                          # Alchemy health alert

# ========================= SIGNAL HANDLING ====================================

cleanup() {
    _running=false
    log_info "Shutdown signal received."
    send_telegram "🛑 STANDBY failover stopped (signal)" 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ========================= FUNCTIONS ==========================================

log() {
    local level="$1"; shift
    local msg; msg="[$(date -u +"%F %T")] [$level] $*"   # split decl/assign (SC2155)
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    [[ -t 1 ]] && echo "$msg" || true
}
log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }

rotate_log() {
    [[ -f "$LOG_FILE" ]] || return
    local size; size=$(stat -c%s "$LOG_FILE" 2>/dev/null) || return
    [[ $size -gt $LOG_MAX_SIZE ]] && mv "$LOG_FILE" "${LOG_FILE}.old" && log_info "Log rotated"
}

# v0.6.5 (F5): escape helpers for notification payloads. A raw & / < / > / " / newline in a dynamic
# field (NODE_NAME, switch reason, identity, status) could otherwise break Telegram HTML parsing,
# split an HTTP header, or emit invalid webhook JSON → a CRITICAL alert SILENTLY fails to send.
_html_escape() { local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }
# Strip <tag> markup for PLAINTEXT sinks (the log); Telegram (parse_mode=HTML) still gets the tagged
# form. Single left-to-right pass: a "<" opens a tag only when a ">" follows with no other "<" in
# between, so comparison text like "lag (> 32)" or "delta < 5" passes through verbatim. The previous
# strip-and-rejoin loop DIVERGED when a bare ">" preceded a real <tag> (the string GREW each round and
# the monitor hung inside a log call — and a hung monitor never self-fences). This form provably
# terminates: every iteration consumes at least one character of the remainder.
_strip_html() {
    local rest="$1" out="" seg body
    while [[ "$rest" == *"<"*">"* ]]; do
        seg="${rest%%<*}"          # text before the next "<"
        rest="${rest#*<}"          # consume that "<"
        body="${rest%%>*}"         # candidate tag body, up to the next ">"
        if [[ "$body" == *"<"* ]]; then
            out="$out$seg<"        # another "<" arrives before any ">": that "<" was literal text
        else
            rest="${rest#*>}"      # real tag: drop its body and the closing ">"
            out="$out$seg"
        fi
    done
    printf '%s' "$out$rest"
}
_header_sanitize() { printf '%s' "$1" | tr -d '\000-\037\177'; }   # strip CR/LF/control for HTTP headers
_json_escape_inner() {   # value escaped for embedding INSIDE a JSON string (no surrounding quotes)
    local q; q=$(printf '%s' "$1" | jq -Rsa .); q="${q%\"}"; q="${q#\"}"; printf '%s' "$q"
}

send_telegram() {
    [[ "$TG_ENABLED" != "true" ]] && return 0
    [[ -z "$TG_BOT_TOKEN" || -z "$TG_CHAT_ID" ]] && return 0

    # v0.6.5 (F5): HTML-escape the NODE_NAME prefix (callers escape the dynamic fields inside $1).
    local msg="[$(_html_escape "$NODE_NAME")] $1"
    local result
    # v0.6.5 (F5): --data-urlencode the text/chat_id so a raw '&' or newline in a field can't truncate
    # the form body (a bare '&' under -d starts a new form field → the message is silently cut off).
    result=$(curl -s -m 10 -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=$TG_CHAT_ID" --data-urlencode "text=$msg" -d parse_mode="HTML" 2>&1)
    local rc=$?
    [[ $rc -ne 0 ]] && { log_warn "Telegram failed (curl $rc)"; return 1; }
    echo "$result" | jq -e '.ok' &>/dev/null || { log_warn "Telegram API error"; return 1; }
    return 0
}

# v0.6.4: optional 4th arg = level. "critical" (default) → urgent ntfy priority (switch/takeover
# alerts — unchanged). "WARN" → high priority (warning-level events). The identity suffix is
# omitted when no identity is supplied (warnings pass none); for critical alerts (identity always
# set) the emitted payload is byte-identical to pre-v0.6.4.
send_webhook() {
    [[ -z "$WEBHOOK_URL" ]] && return
    local reason="$1" identity="$2" status="$3" level="${4:-critical}"

    local priority="urgent"
    [[ "$level" == "WARN" ]] && priority="high"

    if [[ "$WEBHOOK_URL" == *"ntfy"* ]]; then
        local detail="$reason"
        [[ -n "$identity" ]] && detail="$reason | Identity: ${identity:0:16}..."
        # v0.6.5 (F5): the ntfy Title is an HTTP HEADER — strip CR/LF/control chars from NODE_NAME and
        # status so a newline in either can't split the header / drop the alert.
        curl -s -m 10 -X POST "$WEBHOOK_URL" \
            -H "Title: [$(_header_sanitize "$NODE_NAME")] $(_header_sanitize "$status")" \
            -H "Priority: $priority" \
            -H "Tags: warning" \
            -d "$detail" >/dev/null 2>&1 || true
    elif [[ -n "$WEBHOOK_BODY" ]]; then
        # v0.6.5 (F5): JSON-escape the substituted values so a quote/newline/backslash in a field
        # can't break the operator's JSON template.
        local body="$WEBHOOK_BODY" er ei es
        er=$(_json_escape_inner "$reason"); ei=$(_json_escape_inner "$identity"); es=$(_json_escape_inner "$status")
        body="${body//\{reason\}/$er}"; body="${body//\{identity\}/$ei}"; body="${body//\{status\}/$es}"
        curl -s -m 10 -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" -d "$body" >/dev/null 2>&1 || true
    else
        # v0.6.5 (F5): build the JSON with jq -n --arg so any &/</>/"/newline in the fields yields
        # valid JSON (string interpolation could emit a malformed body the receiver silently drops).
        local jtext body
        if [[ -n "$identity" ]]; then
            jtext="[$NODE_NAME] $status: $reason | Identity: $identity"
        else
            jtext="[$NODE_NAME] $status: $reason"
        fi
        body=$(jq -nc --arg text "$jtext" '{text: $text}')
        curl -s -m 10 -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" -d "$body" >/dev/null 2>&1 || true
    fi
}

alert() {
    local reason="$1" identity="$2" status="$3"
    log_warn "ALERT: $status — $reason (identity: $identity)"
    # v0.6.1 (N3): if Telegram is momentarily down (a blip at the instant of takeover could lose the
    # critical "STANDBY TOOK STAKED" alert), stash it and re-send next cycle.
    # v0.6.5 (F5): HTML-escape the dynamic fields before building the parse_mode=HTML message; use real
    # newlines (send_telegram --data-urlencode encodes them) so the alert can't silently fail to parse.
    local msg
    msg=$(printf '🚨 <b>%s</b>\nReason: %s\nIdentity: <code>%s</code>' \
        "$(_html_escape "$status")" "$(_html_escape "$reason")" "$(_html_escape "$identity")")
    if ! send_telegram "$msg"; then
        _pending_alert="$msg"
    fi
    send_webhook "$reason" "$identity" "$status"
}

alert_info() { local msg="$1"; log_info "$(_strip_html "$msg")"; send_telegram "ℹ️ $msg"; }

# v0.6.4: warning-level events — log_warn + Telegram (⚠️) + ntfy/webhook at high (non-urgent)
# priority. Middle tier between alert() (🚨 critical switch/takeover, urgent on both) and
# alert_info() (ℹ️ Telegram-only). Does NOT queue _pending_alert (reserved for critical alerts).
alert_warn() { local msg="$1"; log_warn "$msg"; send_telegram "⚠️ $msg"; send_webhook "$msg" "" "WARN" "WARN"; }

# v0.6.1 (N3): re-send a stored alert once Telegram is reachable again.
flush_pending_alerts() {
    [[ -n "$_pending_alert" ]] && send_telegram "$_pending_alert" && _pending_alert=""
}

# v0.6.4: external heartbeat watchdog ("dead-man's switch"). See HEARTBEAT_URL in CONFIG.
# Fire-and-forget: time-bounded (-m 10), backgrounded, and never blocks or aborts the loop;
# throttled by HEARTBEAT_PING_INTERVAL; a no-op when HEARTBEAT_URL is empty. Scope is narrow —
# "this monitor is alive and looping", NOT "everything is healthy". Fires in DRY_RUN too.
heartbeat_ping() {
    [[ -z "$HEARTBEAT_URL" ]] && return 0
    local now; now=$(date +%s)
    [[ $(( now - _last_hb_ping )) -ge $HEARTBEAT_PING_INTERVAL ]] || return 0
    _last_hb_ping=$now
    curl -fsS -m 10 "$HEARTBEAT_URL" >/dev/null 2>&1 &
    return 0
}

validate_keypair_file() {
    local filepath="$1" label="$2"
    [[ ! -f "$filepath" ]] && { log_error "$label keypair not found: $filepath"; return 1; }
    [[ ! -s "$filepath" ]] && { log_error "$label keypair empty: $filepath"; return 1; }
    head -c 1 "$filepath" | grep -q '\[' || { log_error "$label not valid JSON: $filepath"; return 1; }
    local pubkey
    pubkey=$("$SOLANA_PATH/solana-keygen" pubkey "$filepath" 2>/dev/null)
    [[ -z "$pubkey" ]] && { log_error "$label: cannot derive pubkey"; return 1; }
    echo "$pubkey"
}

get_local_identity() {
    if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
        curl -s -m 5 "$LOCAL_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getIdentity"}' 2>/dev/null \
            | jq -r '.result.identity // empty' 2>/dev/null
    else
        # v0.5.9: hard timeout — contact-info uses admin RPC socket and can hang
        # indefinitely when validator is under heavy load or compacting ledger.
        timeout 8 "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" contact-info 2>/dev/null \
            | grep Identity | awk '{print $2}'
    fi
}

# ========================= SLIDING WINDOW =====================================

window_push() {
    _delinq_window="${_delinq_window}${1}"
    local len=${#_delinq_window}
    if [[ $len -gt $DELINQUENCY_WINDOW_SIZE ]]; then
        _delinq_window="${_delinq_window:$((len - DELINQUENCY_WINDOW_SIZE))}"
    fi
}

window_count() {
    local ones="${_delinq_window//0/}"
    echo "${#ones}"
}

window_triggered() {
    local count
    count=$(window_count)
    local total=${#_delinq_window}
    [[ $total -ge $DELINQUENCY_WINDOW_SIZE && $count -ge $DELINQUENCY_WINDOW_THRESHOLD ]]
}

window_reset() {
    _starvation_note_close "window reset"   # v0.7 (B3 s4 rework): FIRST — reads FIRST_DELINQUENT_TIME before it is zeroed below
    _delinq_window=""
    FIRST_DELINQUENT_TIME=0
    LAST_LIVENESS_ACTIVE_TIME=0            # v0.6.7 (N3): reset with FIRST_DELINQUENT_TIME — fresh episode
    _turbo_mode=false
    _current_interval=$CHECK_INTERVAL
    _gossip_prefetched=false
    _gossip_result=""
    _last_confirm_attempt=0               # v0.6.1 (F2): fresh episode starts un-throttled
    _liveness_first_vote=""               # v0.6.2 (C1): drop stale vote-liveness sample
    _liveness_first_tip=""                # v0.6.3 (Block 1): drop stale RPC-freshness reference tip
    _liveness_first_ts=0
    _liveness_first_provider=""           # v0.7 (Block 3, slice 2): drop the provider pin with the sample
    _last_blind_end=0                     # v0.7 (Block 3, slice 4): fresh episode — no observed blind cycle yet
    _liveness_obs_since=0                 # v0.7 (B3 s4 rework): fresh episode — the observed span restarts
    _ep_blind_cycles=0; _ep_provider_flips=0; _ep_floor_holds=0   # v0.7 (B3 s4 rework): episode diagnostics reset with the episode
    _fastpath_absent_seen=0               # v0.6.8 (Option A, A5): fresh fast-path state per episode
    _fastpath_confirm=0                   # v0.6.8 (Option A): so a stale unstaked remnant cannot latch
}

# Is window mostly clear? (fewer than 2 delinquent in window)
window_mostly_clear() {
    local count
    count=$(window_count)
    [[ $count -lt 2 ]]
}

# ========================= STATE PERSISTENCE (v0.6.1 F7) ======================
# Persist LAST_TAKEOVER_TIME so the TAKEOVER_COOLDOWN (anti-alert-storm / anti-flap)
# survives a service restart (Restart=always would otherwise zero it). We restore
# ONLY a genuine persisted value — we never initialize LAST_TAKEOVER_TIME to "now",
# which would enforce the cooldown right after a restart and block a legitimate
# FIRST takeover during an incident.

# v0.6.9 (H3): fetch one numeric field from STATE_FILE (last occurrence wins; strict ^KEY=[0-9]+$ so a
# corrupt/partial line is silently ignored — restore only genuine values).
_state_get() { grep -E "^${1}=[0-9]+$" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2; }

load_state() {
    # v0.6.9 (M10): one-time migration of the legacy shared ".../state" file to the role-specific
    # default. Only when STATE_FILE still IS the role default (operator overrides are left alone),
    # the new file is absent, and the legacy file exists. Best-effort: a failed/missed migration is
    # benign (the H3 freshness gate simply restores nothing).
    # v0.6.9 (B5): gate on the EXACT shipped default (captured pre-env-source), not merely the -standby
    # suffix — so an operator override like /custom/state-standby is never migrated.
    local _legacy="${STATE_FILE%-standby}"
    if [[ "$STATE_FILE" == "$_DEFAULT_STATE_FILE" && "$_legacy" != "$STATE_FILE" && ! -e "$STATE_FILE" && -f "$_legacy" ]]; then
        if mv "$_legacy" "$STATE_FILE" 2>/dev/null; then
            log_info "State migrated (v0.6.9 M10, one-time): $_legacy → $STATE_FILE"
        else
            log_warn "State migration $_legacy → $STATE_FILE failed — starting with fresh state (benign)"
        fi
    fi
    [[ -r "$STATE_FILE" ]] || return 0
    # v0.7 (Block 3): cross-reboot semantics for the persisted MONOTONIC safety stamps. mono_now
    # values are only comparable within the boot that wrote them, so save_state records BOOT_ID and
    # this compares it to the current boot:
    #   - SAME boot (daemon restart): the restored stamps are valid — use them verbatim (as before).
    #   - DIFFERENT boot / no BOOT_ID line (pre-v0.7 state file): a LOCKOUT/COOLDOWN must fail
    #     toward HELD, never toward expired → re-stamp to mono_now so the FULL window re-elapses
    #     from this restore; the H3 stall-clock backdates are NOT armed (fresh timers — a fresh
    #     timer can only DELAY a demote, never fabricate one).
    #   - Harness fallback (BOTH boot-ids empty AND no /proc/uptime → mono_now IS `date +%s`):
    #     stamps stay comparable across restarts exactly as pre-v0.7 → treat as same-boot.
    local _mono_now _same_boot=0 _cur_boot _saved_boot
    _mono_now=$(mono_now)
    _cur_boot=$(boot_id)
    if [[ -z "$_cur_boot" && -r /proc/uptime ]]; then
        log_warn "boot_id unreadable on a monotonic host — cross-restart timer continuity is disabled: lockouts/cooldowns re-hold in full on every monitor restart (safe direction, but persistent)"
    fi
    if grep -q '^BOOT_ID=' "$STATE_FILE" 2>/dev/null; then
        _saved_boot=$(grep '^BOOT_ID=' "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2-)
        if [[ -n "$_cur_boot" && "$_saved_boot" == "$_cur_boot" ]]; then
            _same_boot=1
        elif [[ -z "$_saved_boot" && -z "$_cur_boot" && ! -r /proc/uptime ]]; then
            _same_boot=1   # harness fallback: mono_now == wall clock → values comparable
        fi
    fi
    local v
    # v0.7 (Block 3, dual-write): prefer the *_MONO twin; the legacy key now carries a WALL value
    # for rollback compatibility and is never used in mono arithmetic — on an old-format file
    # (no twin) it serves only as a >0 signal and the stamp re-holds from now.
    v=$(_state_get LAST_TAKEOVER_MONO)
    [[ -z "$v" ]] && { v=$(_state_get LAST_TAKEOVER_TIME); [[ -n "$v" && $v -gt 0 ]] && v=$_mono_now; }
    if [[ -n "$v" ]]; then
        # v0.7 (Block 3): different boot + a real (>0) stamp → cooldown re-held in full from now (see
        # above). A 0 stamp ("no takeover yet") restores as 0 — never invent a cooldown that would
        # block a legitimate FIRST takeover during an incident (the original F7 rule).
        [[ $_same_boot -eq 0 && $v -gt 0 ]] && v=$_mono_now
        LAST_TAKEOVER_TIME="$v"; log_info "State restored: LAST_TAKEOVER_TIME=$LAST_TAKEOVER_TIME"
    fi
    # v0.6.9 (H1.3): restore the self-fence re-take lockout UNCONDITIONALLY (like LAST_TAKEOVER_TIME —
    # a stale value is benign: the cooldown has long expired; a fresh one MUST survive Restart=always,
    # else the monitor restart re-opens the take-back-what-we-just-fenced hazard). FAILURE DIRECTION:
    # restoring can only ever BLOCK a take, never cause one.
    v=$(_state_get SELF_FENCE_DEMOTE_MONO)
    [[ -z "$v" ]] && { v=$(_state_get SELF_FENCE_DEMOTE_TIME); [[ -n "$v" && $v -gt 0 ]] && v=$_mono_now; }
    if [[ -n "$v" && $v -gt 0 ]]; then
        [[ $_same_boot -eq 0 ]] && v=$_mono_now   # v0.7 (Block 3): reboot → the FULL lockout re-elapses (fail toward HELD)
        SELF_FENCE_DEMOTE_TIME="$v"; log_info "State restored: SELF_FENCE_DEMOTE_TIME=$SELF_FENCE_DEMOTE_TIME (re-take lockout survives the restart)"
    fi

    # v0.7 (pre-Block-4, №9): last KNOWN alpenglow gate state — a plain STRING, not a timer, so it
    # restores VERBATIM: no *_MONO twin (nothing does clock arithmetic on it — the boot-id rules
    # above are about mono stamps) and no freshness gate (a stale value at worst logs one already-
    # seen transition as unchanged; a garbled/absent line restores nothing). _state_get is
    # numeric-only, hence the enumerated grep (the ROLE_AT_SAVE idiom).
    v=$(grep -E '^ALPENGLOW_GATE_STATE=(inactive|pending|active)$' "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
    [[ -n "$v" ]] && _alpenglow_gate_state="$v"

    # v0.6.9 (H3): promoted-holder self-fence baseline continuity across a monitor restart. Freshness-
    # gated (a save older than STATE_MAX_AGE_SECS is discarded — a stale baseline must not fire an
    # instant false demote). Slot/latch VALUES restore verbatim; TIMESTAMPS restart — EXCEPT that a
    # persisted-STAKED stall/silence/lag arms a pending backdate which check_self_fence_isolation
    # applies only on positive first-read evidence the condition is CONTINUOUS.
    local save_ts role now age
    save_ts=$(_state_get SAVE_TS)
    role=$(grep -E '^ROLE_AT_SAVE=(staked|unstaked)$' "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
    [[ -n "$role" ]] && _persisted_role="$role"   # read regardless of age: drives the startup staked-unreachable page
    [[ -n "$save_ts" ]] || return 0
    now=$(date +%s)
    age=$(( now - save_ts ))
    # v0.6.9 (B4): STATE_MAX_AGE_SECS=0 is a HARD disable (the documented "0 = never restore"); and the
    # freshness bound is EXCLUSIVE (>=) so a save exactly at the boundary — incl. a same-second age==0
    # restart under max==0 — is discarded, not restored. "Fresher than" means strictly younger.
    if [[ $STATE_MAX_AGE_SECS -eq 0 || $age -lt 0 || $age -ge $STATE_MAX_AGE_SECS ]]; then
        log_info "Persisted self-fence baseline NOT restored (age ${age}s, STATE_MAX_AGE_SECS=${STATE_MAX_AGE_SECS}s) — timers start fresh (H3 freshness gate; 0 = restore disabled)"
        return 0
    fi
    if [[ "$STANDBY_SELF_FENCE" == "true" ]]; then
        local ps pa pn pv pb ph
        ps=$(_state_get SF_LAST_CONFIRMED_SLOT); pa=$(_state_get SF_ADVANCE_MONO)
        pn=$(_state_get SF_NOANSWER_MONO);       pv=$(_state_get SF_VOTELAG_MONO)
        # Old-format fallback (no *_MONO twins): the legacy wall clocks cannot join mono arithmetic;
        # leave the pendings unarmed (timers restart fresh — can delay a demote, never invent one).
        [[ -z "$pa" ]] && pa=""
        [[ -z "$pn" ]] && pn=0
        [[ -z "$pv" ]] && pv=0
        pb=$(_state_get SF_VOTELAG_BASELINE);    ph=$(_state_get SF_VOTELAG_HEALTHY)
        # v0.7 (Block 3): the persisted stall/silence/lag clocks are mono_now stamps — the backdate
        # pendings arm ONLY within the same boot ($_same_boot). Across a reboot the stamps are from a
        # dead clock: timers restart fresh (a fresh timer can only DELAY a demote, never invent one).
        if [[ -n "$ps" ]]; then
            _last_confirmed_slot="$ps"; _last_confirmed_advance_ts=$_mono_now   # slot verbatim, timer restarts
            if [[ $_same_boot -eq 1 && "$role" == "staked" && -n "$pa" && $(( _mono_now - pa )) -ge $SELF_FENCE_ISOLATION_SECS ]]; then
                _selffence_restore_pending=1; _selffence_restored_advance_ts="$pa"
            fi
        fi
        if [[ $_same_boot -eq 1 && "$role" == "staked" && -n "$pn" && $pn -gt 0 ]]; then
            _selffence_noanswer_restore_pending=1; _selffence_restored_noanswer_since="$pn"
        fi
        [[ "$pb" == "1" ]] && _selffence_votelag_baseline=1
        [[ -n "$ph" ]] && _selffence_votelag_healthy=$((10#$ph))
        if [[ $_same_boot -eq 1 && "$role" == "staked" && -n "$pv" && $pv -gt 0 ]]; then
            _selffence_votelag_restore_pending=1; _selffence_restored_votelag_since="$pv"
        fi
        log_info "State restored (age ${age}s <= ${STATE_MAX_AGE_SECS}s): self-fence baseline slot=${ps:-none} role=${role:-unknown} noanswer_since=${pn:-0} votelag_since=${pv:-0} same_boot=${_same_boot}"
    fi
    return 0
}

save_state() {
    mkdir -p "$STATE_DIR" 2>/dev/null || { log_warn "Cannot create $STATE_DIR — state not persisted"; return 0; }
    # v0.6.9 (H3/H1.3): persist the self-fence baseline + the re-take lockout + the role at save + a
    # save timestamp alongside the v0.6.1 cooldown. Written on every state-relevant transition AND once
    # per main-loop cycle (plain overwrite — no fsync storm).
    local _role="unstaked"
    [[ -n "$STAKED_PUBKEY" && "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] && _role="staked"
    local _SAVE_W _SAVE_M
    _SAVE_W=$(date +%s); _SAVE_M=$(mono_now)
    {
        printf 'LAST_TAKEOVER_TIME=%s\n'            "$(_m2w "$LAST_TAKEOVER_TIME")"
        printf 'LAST_TAKEOVER_MONO=%s\n'            "${LAST_TAKEOVER_TIME:-0}"
        printf 'SELF_FENCE_DEMOTE_TIME=%s\n'        "$(_m2w "${SELF_FENCE_DEMOTE_TIME:-0}")"
        printf 'SELF_FENCE_DEMOTE_MONO=%s\n'        "${SELF_FENCE_DEMOTE_TIME:-0}"
        printf 'SF_LAST_CONFIRMED_SLOT=%s\n'        "${_last_confirmed_slot:-}"
        printf 'SF_LAST_CONFIRMED_ADVANCE_TS=%s\n'  "$(_m2w "${_last_confirmed_advance_ts:-0}")"
        printf 'SF_ADVANCE_MONO=%s\n'               "${_last_confirmed_advance_ts:-0}"
        printf 'SF_NOANSWER_SINCE=%s\n'             "$(_m2w "${_selffence_noanswer_since:-0}")"
        printf 'SF_NOANSWER_MONO=%s\n'              "${_selffence_noanswer_since:-0}"
        printf 'SF_VOTELAG_SINCE=%s\n'              "$(_m2w "${_selffence_votelag_since:-0}")"
        printf 'SF_VOTELAG_MONO=%s\n'               "${_selffence_votelag_since:-0}"
        printf 'SF_VOTELAG_BASELINE=%s\n'           "${_selffence_votelag_baseline:-0}"
        printf 'SF_VOTELAG_HEALTHY=%s\n'            "${_selffence_votelag_healthy:-0}"
        printf 'ALPENGLOW_GATE_STATE=%s\n'          "${_alpenglow_gate_state}"   # v0.7 (pre-Block-4, №9): a STRING, not a timer — no *_MONO twin needed (nothing does clock arithmetic on it)
        printf 'ROLE_AT_SAVE=%s\n'                  "$_role"
        printf 'BOOT_ID=%s\n'                       "$(boot_id)"   # v0.7 (Block 3): the persisted stamps above are mono_now values — only comparable within this boot (see load_state)
        printf 'SAVE_TS=%s\n'                       "$(date +%s)"
    } > "$STATE_FILE" 2>/dev/null \
        || { log_warn "Cannot write $STATE_FILE — state not persisted"; return 0; }
    chmod 600 "$STATE_FILE" 2>/dev/null || true
    return 0
}

# ========================= THREE-TIER RPC SYSTEM ==============================

# --- Tier 1: LOCAL health check ---
# STANDBY uses Tier 1 to check its OWN health: can I take over?
# 100% LOCAL — no external RPC calls (saves CU, avoids rate limits)
# getHealth already checks slot distance (--health-check-slot-distance, default 128)
# Returns: 0 = healthy (ready), 1 = unhealthy (not ready)

tier1_check_local_health() {
    STAT_TIER1_HEALTH=$((STAT_TIER1_HEALTH + 1))

    # 1. getHealth — checks if validator is caught up (uses --health-check-slot-distance)
    local health_result
    health_result=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' 2>/dev/null)

    if [[ $? -ne 0 || -z "$health_result" ]]; then
        log_warn "[TIER1] Local RPC unreachable — not ready to take over"
        return 1
    fi

    local health_status
    health_status=$(echo "$health_result" | jq -r '.result // empty' 2>/dev/null)

    if [[ "$health_status" == "ok" ]]; then
        # 2. Get local slot for logging (pure LOCAL, no external comparison)
        local our_slot
        our_slot=$(curl -s -m 3 "$LOCAL_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null \
            | jq -r '.result // empty' 2>/dev/null)
        log_info "[TIER1] Health OK — slot ${our_slot:-unknown}"
        return 0
    fi

    # getHealth returned error — validator behind or unhealthy
    local err_msg num_behind
    err_msg=$(echo "$health_result" | jq -r '.error.data.message // .error.message // "unknown"' 2>/dev/null)

    # Try structured field first (agave returns numSlotsBehind in data)
    num_behind=$(echo "$health_result" | jq -r '.error.data.numSlotsBehind // empty' 2>/dev/null)
    # Fallback: extract number from error message ("Node is behind by 150 slots")
    if [[ -z "$num_behind" || ! "$num_behind" =~ ^[0-9]+$ ]]; then
        num_behind=$(echo "$err_msg" | grep -oE '[0-9]+' | head -1) || true
    fi

    if [[ -n "$num_behind" && "$num_behind" =~ ^[0-9]+$ ]]; then
        if [[ $num_behind -le $LOCAL_HEALTH_MAX_BEHIND ]]; then
            # Behind but within tolerance — still OK to take over
            log_info "[TIER1] Health OK — ${num_behind} slots behind (max: $LOCAL_HEALTH_MAX_BEHIND)"
            return 0
        fi
        log_warn "[TIER1] ${num_behind} slots behind (max: $LOCAL_HEALTH_MAX_BEHIND) — not ready"
    else
        log_warn "[TIER1] Unhealthy: $err_msg — not ready"
    fi

    return 1
}

# --- LOCAL: Delinquency check via LOCAL RPC (FREE, every cycle) ---
# Replaces constant TIER2 polling. Alchemy only called for confirmation.
# Returns: 0 = delinquent, 1 = not delinquent, 2 = unreachable

local_check_delinquency() {
    STAT_LOCAL_DELINQ=$((STAT_LOCAL_DELINQ + 1))

    local vote_result
    vote_result=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)

    if [[ $? -ne 0 || -z "$vote_result" ]]; then
        return 2
    fi
    echo "$vote_result" | jq -e '.result' &>/dev/null || return 2

    # Check delinquent by votePubkey
    local is_delinquent
    is_delinquent=$(echo "$vote_result" | jq -r \
        --arg vote "$VOTE_PUBKEY" \
        '.result.delinquent[]? | select(.votePubkey == $vote) | .votePubkey // empty' 2>/dev/null)

    if [[ -n "$is_delinquent" ]]; then
        log_info "[LOCAL] Vote $VOTE_PUBKEY DELINQUENT"
        return 0
    fi

    # Check by nodePubkey
    is_delinquent=$(echo "$vote_result" | jq -r \
        --arg pubkey "$STAKED_PUBKEY" \
        '.result.delinquent[]? | select(.nodePubkey == $pubkey) | .nodePubkey // empty' 2>/dev/null)

    if [[ -n "$is_delinquent" ]]; then
        log_info "[LOCAL] Node $STAKED_PUBKEY DELINQUENT"
        return 0
    fi

    # Optional: fast detection via lastVote latency
    if [[ $MAX_DELINQUENT_SLOTS -gt 0 ]]; then
        local current_slot last_vote
        current_slot=$(curl -s -m 3 "$LOCAL_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null \
            | jq -r '.result // empty' 2>/dev/null)

        last_vote=$(echo "$vote_result" | jq -r \
            --arg vote "$VOTE_PUBKEY" \
            '(.result.current + .result.delinquent)[] | select(.votePubkey == $vote) | .lastVote // empty' 2>/dev/null)

        if [[ -n "$current_slot" && -n "$last_vote" && "$current_slot" =~ ^[0-9]+$ && "$last_vote" =~ ^[0-9]+$ ]]; then
            local latency=$(( current_slot - last_vote ))
            if [[ $latency -gt $MAX_DELINQUENT_SLOTS ]]; then
                log_info "[LOCAL] Latency $latency > $MAX_DELINQUENT_SLOTS — treating as delinquent"
                return 0
            fi
        fi
    fi

    return 1
}

# --- Confirm delinquency via external RPCs (TIER2/TIER3) ---
# Called ONLY when window triggered.
# v0.6.1 (F2): three-valued contract (was 0/1 only):
#   0 = confirmed delinquent                         → proceed to fence
#   1 = externals responded NOT delinquent (valid)   → real false positive → window_reset
#   2 = could not confirm (any unreachable/invalid)  → HOLD: keep window, retry next cycle
confirm_delinquency_external() {
    log_info "─── EXTERNAL CONFIRMATION ───"

    # Try Tier 2 first
    if [[ -n "$TIER2_RPC" ]]; then
        tier2_check_delinquency
        local t2=$?

        if [[ $t2 -eq 0 ]]; then
            log_info "[CONFIRM] Tier 2 CONFIRMED delinquent"
            return 0
        elif [[ $t2 -eq 1 ]]; then
            log_warn "[CONFIRM] Tier 2 says NOT delinquent — local false positive"
            return 1
        else
            # T2 unreachable — alert + fall through to T3
            now_ts=$(date +%s)
            if [[ $(( now_ts - _last_t2_alert )) -ge $ALERT_THROTTLE ]]; then
                alert_warn "⚠️ TIER2 (Alchemy) unreachable during takeover confirmation! Falling back to TIER3."
                _last_t2_alert=$now_ts
            fi
            log_warn "[CONFIRM] Tier 2 unreachable — trying Tier 3"
        fi
    fi

    # Tier 3 fallback/confirmation
    tier3_confirm_delinquency
    local t3=$?

    if [[ $t3 -eq 0 ]]; then
        log_info "[CONFIRM] Tier 3 CONFIRMED delinquent"
        return 0
    elif [[ $t3 -eq 1 ]]; then
        log_warn "[CONFIRM] Tier 3 says NOT delinquent — local false positive"
        return 1
    fi

    # Both unreachable → ALWAYS "could not confirm" → return 2 (HOLD). v0.6.1 (F2): NOT 1 (false
    # positive) — the caller keeps the window/turbo and retries; a single both-RPC-down cycle must not
    # wipe an already-triggered window. v0.6.5 (F3): the old ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN
    # "emergency" return-0 path is removed. It was ineffective: even when it forced external-confirm
    # to succeed, the authoritative vote-liveness fence still needs T2/T3 to sample lastVote, so a
    # both-externals-down takeover blocked anyway. The one real emergency local-only takeover is
    # ALLOW_UNFENCED_TAKEOVER=true + VOTE_LIVENESS_VERIFY=false (disables the split-brain fence).
    log_warn "[CONFIRM] ⚠️ BOTH T2 and T3 unreachable — cannot confirm, holding (emergency local-only takeover = ALLOW_UNFENCED_TAKEOVER=true + VOTE_LIVENESS_VERIFY=false)"
    return 2
}

# v0.6.8 (Option A): POSITIVE "holder relinquished" signal for the fast-path. Returns 0 ONLY when the
# holder's node is observed advertising its KNOWN unstaked identity in gossip — a positive self-fence
# action, corroborated. Fail-closed at every step (off / unset / not-affirmed-manual / single-RPC /
# unconfirmed → return 1, the timer governs). NEVER keys on the staked entry vanishing or its wallclock
# going stale (a staked CRDS entry lingers ~48h); only on the UNSTAKED pubkey APPEARING, whose ~15s CRDS
# TTL makes a present entry provably recent. Guards: A2 (positive, pubkey-pinned, absent→present
# transition, N-consecutive), A4 (peers must be manual-recovery), A6 (>=2 independent RPC vantage points).
# v0.6.8 (F-A, Audit-2 r2): the matched unstaked pubkey must be advertised at the HOLDER's gossip endpoint
# — the ip:port of the staked identity's own (lingering ~48h) CRDS entry. agave set-identity KEEPS PORTS,
# so a self-fenced holder re-advertises its unstaked identity at exactly the endpoint its staked identity
# last used. A watched key present at a DIFFERENT endpoint is a NON-holder peer (multi-node topology) and
# is IGNORED — only the CURRENT holder's unstaked-at-the-staked-endpoint qualifies, so the multi-peer
# watch-list is safe. Staked absent from gossip ⇒ cannot anchor ⇒ no fast-take (the timer governs). Without
# this anchor a non-holder peer's unstaked flip could skip the timer on an irrelevant signal and take on
# the liveness gate alone, re-opening the transient-vote-pause double-sign the TAKEOVER_DELAY+N3 anchor closes.
# v0.6.8 (S1): compute + ENFORCE the inter-spare stagger floor so STANDBY and BACKUP can't both fast-take
# on the same relinquish. A spare must wait at least (its TAKEOVER_DELAY - the STANDBY's TAKEOVER_DELAY)
# past detection before fast-taking, so the v0.6.7 timer serialization survives the timer skip. The node
# COMPUTES this from STANDBY_TAKEOVER_DELAY (set the same on every spare = the STANDBY's delay) and ENFORCES
# max(FASTPATH_STAGGER_SECS, required) — an operator cannot under-set it. Bad/absent config ⇒ fail-closed
# (sets _fastpath_disabled; the gate + peer_has_relinquished then never fast-take). Returns 1 if disabled.
_fastpath_compute_stagger() {
    _fastpath_disabled=""; _fastpath_stagger_floor=$FASTPATH_STAGGER_SECS
    if [[ ! "$STANDBY_TAKEOVER_DELAY" =~ ^[0-9]+$ ]]; then
        _fastpath_disabled="STANDBY_TAKEOVER_DELAY not set/numeric ('${STANDBY_TAKEOVER_DELAY}')"; return 1
    fi
    local std=$((10#$STANDBY_TAKEOVER_DELAY))
    if [[ $std -gt $TAKEOVER_DELAY ]]; then
        _fastpath_disabled="STANDBY_TAKEOVER_DELAY ($std) > this node's TAKEOVER_DELAY ($TAKEOVER_DELAY)"; return 1
    fi
    local required=$(( TAKEOVER_DELAY - std )); [[ $required -lt 0 ]] && required=0
    [[ $required -gt $_fastpath_stagger_floor ]] && _fastpath_stagger_floor=$required
    # F-B: a ZERO topology-derived stagger (STANDBY_TAKEOVER_DELAY >= TAKEOVER_DELAY ⇒ required==0) lets this
    # node fast-take with no delay relative to the STANDBY — correct ONLY for the declared first spare. With
    # no runtime role field, require an EXPLICIT opt-in so a misconfigured BACKUP can't silently inherit floor 0
    # and race the STANDBY into a two-spare take. (FASTPATH_STAGGER_SECS may still raise the floor, but a
    # required==0 on a non-first-spare means STANDBY_TAKEOVER_DELAY was mis-set — fail closed regardless.)
    if [[ $required -le 0 && "$WITNESS_FASTPATH_FIRST_SPARE" != "true" ]]; then
        _fastpath_disabled="zero stagger (STANDBY_TAKEOVER_DELAY ${std} >= TAKEOVER_DELAY ${TAKEOVER_DELAY}) but WITNESS_FASTPATH_FIRST_SPARE!=true — only the STANDBY (first spare) may fast-take with no stagger; on a BACKUP set WITNESS_FASTPATH_FIRST_SPARE=false and STANDBY_TAKEOVER_DELAY to the STANDBY's smaller delay"; return 1
    fi
    return 0
}

peer_has_relinquished() {
    [[ "$WITNESS_FASTPATH" == "true" ]] || return 1
    [[ -z "$_fastpath_disabled" ]] || return 1   # v0.6.8 (S1): fail-closed when the stagger config is bad
    [[ -n "$PRIMARY_UNSTAKED_PUBKEY" ]] || return 1
    [[ "$FASTPATH_PEER_RECOVERY_MANUAL" == "true" ]] || return 1   # A4: only when peers cannot auto re-stake
    local rpc info staked_ep pk pk_ep responders=0 vantages=0
    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        [[ -z "$rpc" ]] && continue
        info=$(curl -s -m 5 "$rpc" -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null) || continue
        echo "$info" | jq -e '.result' &>/dev/null || continue
        responders=$(( responders + 1 ))
        # F-A: ANCHOR to the HOLDER. Read the staked identity's gossip endpoint (its lingering ~48h CRDS
        # entry); a watched unstaked pubkey only counts when advertised at that SAME ip:port (set-identity
        # keeps ports). Staked not in gossip on this vantage ⇒ cannot anchor ⇒ skip (not a confirmed flip).
        staked_ep=$(echo "$info" | jq -r --arg sp "$STAKED_PUBKEY" '.result[]? | select(.pubkey == $sp) | .gossip // empty' 2>/dev/null | head -1)
        [[ -n "$staked_ep" ]] || continue
        # match ANY configured unstaked pubkey (space-separated list supports multi-peer topologies), but
        # ONLY when it is advertised at the holder's (staked) endpoint — a different endpoint = a non-holder peer.
        # shellcheck disable=SC2086
        for pk in $PRIMARY_UNSTAKED_PUBKEY; do
            pk_ep=$(echo "$info" | jq -r --arg pk "$pk" '.result[]? | select(.pubkey == $pk) | .gossip // empty' 2>/dev/null | head -1)
            [[ -n "$pk_ep" && "$pk_ep" == "$staked_ep" ]] && { vantages=$(( vantages + 1 )); break; }
        done
    done
    # A6: require >= 2 independent vantage points to have ANSWERED (single-RPC / co-partitioned view → no
    # fast-path; the timer governs). Fewer responders is NOT a relinquish signal.
    if [[ $responders -lt 2 ]]; then _fastpath_confirm=0; return 1; fi
    # A2: record the ABSENT side of the transition — the unstaked key is not (yet) advertised anywhere.
    if [[ $vantages -eq 0 ]]; then _fastpath_absent_seen=1; _fastpath_confirm=0; return 1; fi
    # Corroborated flip: present on BOTH responders (A6) AND we saw it absent earlier this episode (A2 edge,
    # so a stale remnant present from before the incident cannot latch). Require N consecutive such cycles.
    if [[ $vantages -ge 2 && $_fastpath_absent_seen -eq 1 ]]; then
        _fastpath_confirm=$(( _fastpath_confirm + 1 ))
        if [[ $_fastpath_confirm -ge $FASTPATH_CONFIRM_SAMPLES ]]; then
            log_warn "[fast-path] holder UNSTAKED identity present at the staked endpoint (${staked_ep}) on ${vantages} vantage(s) for ${_fastpath_confirm} consecutive checks (after a prior absent) — POSITIVE relinquish"
            return 0
        fi
        return 1
    fi
    # present on only one vantage, or never observed absent this episode → not a corroborated transition
    _fastpath_confirm=0
    return 1
}

# ── v0.7 (Block 3, slice 4 / AUDIT-5 S-3) — blind-cycle stamp (BYTE-IDENTICAL in both daemons) ──
# A BLIND cycle = an ACTIVE-episode cycle in which an external observation of the holder was
# ATTEMPTED and NO provider yielded a usable one: (a) the liveness sampler returned nothing usable
# (both tiers failed/invalid), or (b) external confirm returned 2 (cannot confirm — both externals
# down/invalid). Callers stamp it through this seam (tests neuter it to simulate the pre-slice-4
# daemon). A cycle that attempts no observation (e.g. deep inside the countdown) is NOT blind — a
# pinned pair spanning such a stretch still proves silence, because lastVote is monotonic on-chain.
# INVARIANT(blindness-is-life): time we could not observe the holder counts as if the holder was
# voting; the countdown only counts OBSERVED silence. The takeover/recovery anchor takes
# max(..., _last_blind_end), so the FULL countdown re-elapses from the END of the last observed
# blind cycle. Blindness that began BEFORE the first sample was ever pinned is the same rule with
# zero prior observations: nothing to "restart" — the full countdown starts over from the end of
# blindness. A VOTING observation still re-anchors exactly as before — blindness never delays the
# LIVE verdict, only the take.
_note_blind_cycle() {
    _last_blind_end="$1"
    _liveness_obs_since=0   # blindness = no observation — the episode's observed span re-pins at the next successful sample
    _ep_blind_cycles=$((_ep_blind_cycles + 1))   # episode diagnostics (starvation page)
    log_info "[blindness-is-life] no usable external observation this cycle — countdown re-anchored to the end of blindness (mono ${1})"
}

# ── v0.7 (Block 3, slice-4 rework) — first-observation pin (BYTE-IDENTICAL in both daemons) ────
# Pins the EPISODE's first successful external observation (mono time; only if currently 0).
# Re-pinned after blindness (_note_blind_cycle resets it to 0, so the next successful sample
# re-pins); NEVER touched by the pair re-bases (tip-stall, backwards, provider flip) — those
# re-base the PAIR's comparability, not "how long we have been observing".
_note_observation() {
    [[ ${_liveness_obs_since:-0} -gt 0 ]] || _liveness_obs_since="$1"
}

# ── v0.7 (Block 3, slice 4) — OBSERVATION-SPAN FLOOR (RATIFIED by the reviewer, 2026-08-17;
# BYTE-IDENTICAL in both daemons; revert = delete this function, its two one-line call-site hunks,
# the VOTE_LIVENESS_MIN_SPAN knob and its validation/drift-table lines).
# SEMANTICS: a FROZEN-based take must rest on >= VOTE_LIVENESS_MIN_SPAN seconds of OBSERVED span
# since the EPISODE's first successful observation (or since the end of the last blind cycle):
# span = mono_now - _liveness_obs_since — NOT the re-basable pair pin. Returns 0 (SHORT) → the
# caller demotes the FROZEN verdict to "cannot determine yet" (never a verdict). Floor 0 disables
# (the config-drift table announces it).
# CORRECTNESS (the reviewer's argument, stated exactly): INVARIANT(baseline-rises-only-on-voting)
# means every non-VOTING re-base only LOWERS _liveness_first_vote; so on a FROZEN verdict the
# baseline <= the minimum lastVote observed since the last VOTING verdict (episode start if none),
# and lastVote is monotonic on-chain — FROZEN therefore proves the holder never exceeded that
# minimum over that whole stretch — up to the last sample's snapshot staleness (an external
# view that ADVANCES but LAGS compresses the observed tail; the tip-guard checks advance, not
# rate — a pre-existing exposure the floor narrows but does not close). obs_since re-pins at
# every VOTING verdict (the ADVANCED path and the fresh-proof re-check both stamp it — v0.7
# slice 5), so [obs_since, now] IS the proven stretch at ANY config (the snapshot-staleness
# qualifier above stays). The prior caveat — "across an in-episode VOTING verdict obs_since is
# OLDER than the proven stretch" — is HISTORY (measured: SPAN=100 with one observed vote took at
# t0+120 before the re-pin, t0+160 after; inert at the shipped defaults, DELAY 60 > floor 40).
# CONVERGENCE: inside an unblinded stretch obs_since stays PINNED while the SPAN grows
# monotonically, so the floor is always eventually met; residual flip cost returns to the accepted "+1 MIN_INTERVAL per flip".
# HISTORY: the first cut measured span from the re-basable pair pin and did NOT converge under
# provider-flip periods inside (MIN_INTERVAL, MIN_SPAN) — measured flip 20s/35s: NO take in 3600s
# (reviewer, 2026-08-17; never shipped).
# SIDE EFFECT: obs_since resets on blind cycles, so after ANY blindness the floor is a strict
# no-op (the re-anchored countdown 60s > floor 40s and obs_since re-pins ~one cycle after
# blindness ends) — the floor bites exactly where it was built for (the late-observed A9a
# episode) and nowhere else.
# A zero obs_since returns 1 (not short): a real FROZEN verdict structurally implies a successful
# sample THIS cycle, which pinned obs_since via _note_observation — that state only occurs in
# harnesses that mock the fence, never in the shipped daemons.
_liveness_span_short() {
    local floor="${VOTE_LIVENESS_MIN_SPAN:-40}" span
    [[ "$floor" =~ ^[0-9]+$ ]] || floor=40
    floor=$((10#$floor))
    [[ $floor -gt 0 ]] || return 1
    [[ ${_liveness_obs_since:-0} -gt 0 ]] || return 1
    span=$(( $(mono_now) - _liveness_obs_since ))
    if [[ $span -lt $floor ]]; then
        _ep_floor_holds=$((_ep_floor_holds + 1))   # episode diagnostics (starvation page)
        log_info "[liveness] FROZEN pair but only ${span}s observed this episode (< span floor ${floor}s) — cannot determine yet"
        return 0
    fi
    return 1
}

# ── v0.7 (Block 3, slice 5) — ACT-THEN-ALERT FRESH-PROOF RE-CHECK (BYTE-IDENTICAL in both
# daemons). The reviewer's pre-registered conditions (pre-registered at slice 3.5, binding):
#   (1) immediately before set-identity — a FRESH re-check = arithmetic on existing data PLUS one
#       short re-sample, NOT a full gate-cycle re-run;
#   (2) a re-check yielding VOTING or cannot-determine → ABORT, not proceed;
#   (3) between the re-check and set-identity — ZERO network calls (no alert, no network log, no
#       gossip advisory).
# This extends the demote path's existing "safety action FIRST" rule (N2) to the take path: the
# gate verdict's proof was ~20s stale at the mutation (two curl -m 10 inside the sampler), and the
# pre-take 🔍 alert added more network latency AFTER the verdict, BEFORE the action.
# WHY ARITHMETIC-ON-PIN IS SOUND: the B2 invariant (the frozen path never re-bases —
# INVARIANT(baseline-rises-only-on-voting)) means _liveness_first_vote is the episode's min-rule
# baseline; one fresh cur against that pin is a valid verdict refresh REGARDLESS of the pin's age
# (a re-pinned pair can be as young as MIN_INTERVAL): lastVote is monotonic on-chain, so an
# advance past the min-rule baseline is always real, and a frozen read against it under-
# approximates the same-vantage delta — no MIN_INTERVAL wait is needed because the PAIR interval
# here is pin→now, not sample→sample. No confirm re-run, no gossip. Life signs are checked BEFORE
# the tip-freshness guard (deliberately inverted vs the fence's order): an advance cannot be
# invented even by a stale view, and both orders fail toward NOT taking on such a reading — this
# one re-anchors off a genuinely-observed on-chain value instead of discarding it.
# ABORT = VERDICT WITHDRAWN, NOT A FAILED TAKE: no cooldown is set, no episode state is dropped;
# the per-branch re-bases below leave exactly the state the corresponding
# staked_is_actively_voting paths would (including the flip diagnostics counter); pacing comes
# from the re-anchor (VOTING/blind) or the MIN_INTERVAL re-pin (flip/backwards/stale). On the
# PRIMARY the VOTING re-anchor variable is a dead store (that daemon's recovery anchor never
# reads it — same as its in-gate design): a VOTING abort there is paced by the observed-span
# floor + the recovery ladder (measured ~41s to a legitimate re-take); a BLIND abort re-anchors
# the FULL delay on both daemons. FAILURE DIRECTION: toward NOT taking.
# ZERO NETWORK AFTER A RETURN-0: the caller places this IMMEDIATELY before the mutation — nothing
# that touches the network may run between the "return 0" here and set-identity (condition 3).
# ABORT PAGES THROTTLE (storm guard): a vantage flipping at every re-check aborts every
# ~2×MIN_INTERVAL indefinitely (measured: 147 pages over 2000s unthrottled) — abort pages go
# through _recheck_abort_alert (first page immediate, repeats per ALERT_THROTTLE; the per-event
# log_warn lines are never throttled). The starvation page covers episode-level silence on its own.
# Branch ordering (a read-after-write bug in the spec's sketch, fixed here): decide → state writes
# (old values captured FIRST where the message needs them — the flip log must name OLD→NEW) →
# log_warn → alert_warn → return 1.
# NO 0-SENTINEL ARITHMETIC (the reviewer's Block-3 class note): now_r is only ever ASSIGNED into
# state here; no `now - 0`-style arithmetic on a 0-initialized mono timestamp is introduced.
# Returns 0 = proof refreshed → the mutation may proceed; 1 = ABORT.
# Storm guard for the abort pages (BYTE-IDENTICAL in both daemons): first page immediate — the
# throttle gates REPEATS only (the 0-sentinel/monotonic-clock lesson: a freshly booted host must
# never wait out the throttle for its FIRST page). Deliberately GLOBAL, not per-episode: it guards
# the operator channel, not episode state.
_recheck_abort_alert() {
    if [[ ${_recheck_abort_alert_ts:-0} -gt 0 ]]; then
        [[ $(( $(mono_now) - _recheck_abort_alert_ts )) -ge ${ALERT_THROTTLE:-600} ]] || return 0
    fi
    _recheck_abort_alert_ts=$(mono_now)
    alert_warn "$1"
}
_fresh_proof_recheck() {
    # Fence off (explicit operator override at startup) → nothing to re-check against.
    [[ "$VOTE_LIVENESS_VERIFY" == "true" ]] || return 0
    # No pinned baseline: a real FROZEN verdict structurally implies the pin (same carve-out and
    # justification as _liveness_span_short) — only harnesses that mock the fence reach here bare.
    [[ -n "$_liveness_first_vote" ]] || return 0
    local s rest cur tip prov now_r delta old_prov
    s=$(get_staked_liveness_sample) || s=""
    now_r=$(mono_now)
    cur="${s%% *}"; rest="${s#* }"; tip="${rest%% *}"
    prov=""; [[ "$rest" == *" "* ]] && prov="${rest##* }"
    if [[ -z "$s" || ! "$cur" =~ ^[0-9]+$ || ! "$tip" =~ ^[0-9]+$ ]]; then
        _note_blind_cycle "$now_r"
        log_warn "[act-then-alert] fresh re-check: no usable sample — cannot determine → ABORT (the blind stamp above re-anchors the countdown)"
        _recheck_abort_alert "⚠️ Take ABORTED at the final re-check: externals gave no usable sample (cannot determine). No action taken; the countdown re-anchored."
        return 1
    fi
    _note_observation "$now_r"
    delta=$(( cur - _liveness_first_vote ))
    if [[ $delta -gt ${VOTE_LIVENESS_EPSILON:-0} ]]; then
        LAST_LIVENESS_ACTIVE_TIME=$now_r   # STANDBY: N3 re-anchor input. PRIMARY: a DEAD STORE — its recovery anchor never reads this (kept for helper byte-identity; do NOT believe the primary re-anchors here — pacing there is the obs-floor + recovery ladder)
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now_r"; _liveness_first_provider="$prov"
        _liveness_obs_since="$now_r"
        log_warn "[act-then-alert] fresh re-check: staked vote ADVANCED ${delta} slots since the pin — holder is VOTING → ABORT"
        _recheck_abort_alert "⚠️ Take ABORTED at the final re-check: the holder VOTED (+${delta} slots) between the verdict and the action. No action taken; the take must re-qualify from this observation (STANDBY: the full delay re-elapses; PRIMARY: the observed-span floor + recovery ladder)."
        return 1
    fi
    if [[ $delta -lt 0 ]]; then
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now_r"; _liveness_first_provider="$prov"
        log_warn "[act-then-alert] fresh re-check: lastVote went backwards (Δ${delta}) — inconsistent view, cannot determine → ABORT"
        _recheck_abort_alert "⚠️ Take ABORTED at the final re-check: inconsistent external view (lastVote went backwards). No action taken."
        return 1
    fi
    if [[ "$prov" != "$_liveness_first_provider" ]]; then
        old_prov="$_liveness_first_provider"   # captured BEFORE the min-rule re-pin below overwrites it
        _ep_provider_flips=$((_ep_provider_flips + 1))   # episode diagnostics — same as the fence's flip path (starvation-page counter)
        [[ $cur -lt $_liveness_first_vote ]] && _liveness_first_vote="$cur"
        _liveness_first_tip="$tip"; _liveness_first_ts="$now_r"; _liveness_first_provider="$prov"
        log_warn "[act-then-alert] fresh re-check: provider flipped ${old_prov:-unknown}→${prov:-unknown} at the re-check — frozen reading not comparable → ABORT"
        _recheck_abort_alert "⚠️ Take ABORTED at the final re-check: the answering RPC vantage flipped (${old_prov:-unknown}→${prov:-unknown}); the frozen reading is not same-vantage comparable. No action taken."
        return 1
    fi
    if [[ $tip -le $_liveness_first_tip ]]; then
        [[ $cur -lt $_liveness_first_vote ]] && _liveness_first_vote="$cur"
        _liveness_first_tip="$tip"; _liveness_first_ts="$now_r"; _liveness_first_provider="$prov"
        log_warn "[act-then-alert] fresh re-check: cluster reference did not advance since the pin — view stale → ABORT"
        _recheck_abort_alert "⚠️ Take ABORTED at the final re-check: the external view is stale (cluster reference frozen since the pin). No action taken."
        return 1
    fi
    return 0
}

# ── v0.7 (pre-Block-4, №9) — ALPENGLOW FEATURE-GATE TRIPWIRE (BOTH daemons, BYTE-IDENTICAL) ────
# READ-ONLY observability; page-only (addendum §0b). agave 4.2.1 ships the votor/BLS machinery
# dormant behind the on-chain `alpenglow` feature: on activation set-identity demands a
# vote-history file by default and the whole lastVote observation model needs re-derivation — so
# the moment the gate shows pending/active the operator is paged (re-run the 4.2 audit; Blocks
# 5–6 constants freeze until it passes). Called once per cycle at the TOP of the main loop and
# NEVER inside a takeover/recovery/verdict path — the act-then-alert discipline (zero network
# between the fresh re-check and set-identity) is untouched: this network read is nowhere near a
# mutation.
# COMPANION GATE deliberately NOT watched — verified against source, not read (reviewer fix C):
# alpenglow_fast_leader_handover (FLHoAWBDjNh6zwmJ5i1NKK4KyD8otAiv7XxvmnFnVnKH, agave v4.2.1
# feature-set/src/lib.rs:1557) has exactly ONE usage on the safety-relevant paths —
# core/src/replay_stage.rs:1611 (alpenglow_handle_newly_frozen_banks), where it gates
# maybe_notify_of_optimistic_parent, a block-production leader-handover optimization — and it is
# additionally conditioned on migration_status.should_allow_block_markers(), i.e. it has effect
# only AFTER the main migration is already underway. It touches neither set-identity semantics
# nor vote gates nor lastVote observation — both assumptions this tripwire protects hang on the
# MAIN gate alone.
# _alpenglow_gate_fetch — the network seam (tests shadow THIS). One word on stdout + rc 0:
#   inactive (feature account absent), pending (parsed activatedAt null), active (activatedAt a
#   number). Unparsable/absent data or non-JSON → try the next tier; both tiers unusable → rc 1
#   (the caller treats that as "unknown").
_alpenglow_gate_fetch() {
    local rpc result activated
    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        [[ -z "$rpc" ]] && continue
        # the liveness sampler's curl idiom ("Cache-Control: no-cache" defeats HTTP/CDN caches)
        result=$(curl -s -m 10 "$rpc" -X POST \
            -H "Content-Type: application/json" -H "Cache-Control: no-cache" \
            -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getAccountInfo\",\"params\":[\"${ALPENGLOW_FEATURE_ID}\",{\"encoding\":\"jsonParsed\"}]}" 2>/dev/null) || continue
        echo "$result" | jq -e '.result' &>/dev/null || continue
        if echo "$result" | jq -e '.result.value == null' &>/dev/null; then echo "inactive"; return 0; fi
        echo "$result" | jq -e '.result.value.data.parsed.info | type == "object"' &>/dev/null || continue
        activated=$(echo "$result" | jq -r '.result.value.data.parsed.info.activatedAt' 2>/dev/null)
        if [[ "$activated" == "null" ]]; then echo "pending"; return 0; fi
        if [[ "$activated" =~ ^[0-9]+$ ]]; then echo "active"; return 0; fi
    done
    return 1
}
# _alpenglow_gate_check — cadence + state machine around the seam. Self-gates on
# ALPENGLOW_GATE_CHECK_HOURS (0 = off); the FIRST check runs immediately regardless of host
# uptime (the 0-sentinel/monotonic lesson — the same first-immediate pattern as
# _recheck_abort_alert: the cadence gates REPEATS only). UNKNOWN (rc 1) never pages and never
# overwrites the last KNOWN state.
_alpenglow_gate_check() {
    [[ "${ALPENGLOW_GATE_CHECK_HOURS:-0}" =~ ^[0-9]+$ && $((10#$ALPENGLOW_GATE_CHECK_HOURS)) -gt 0 ]] || return 0
    local now state prev _agc_wait
    now=$(mono_now)
    if [[ ${_last_alpenglow_check:-0} -gt 0 ]]; then
        # v0.7 (№9 fix B): the FULL cadence is earned only by a SUCCESSFUL probe; a failed one
        # retries on a 900 s floor (the _last_confirm_attempt form) — a transient failure must
        # not cost 6 h of gate blindness, and not stamping at all would re-create the slice-4
        # per-cycle probe-load problem.
        _agc_wait=$(( 10#$ALPENGLOW_GATE_CHECK_HOURS * 3600 ))
        [[ ${_alpenglow_fail_streak:-0} -gt 0 ]] && _agc_wait=900
        [[ $(( now - _last_alpenglow_check )) -lt $_agc_wait ]] && return 0
    fi
    _last_alpenglow_check=$now
    if ! state=$(_alpenglow_gate_fetch) || [[ -z "$state" ]]; then
        # v0.7 (№9 fix A) — the slice-4 lesson verbatim: a safety mechanism whose failure mode is
        # SILENCE is a dead gate that looks alive. Persistent fetch failure (provider dropped
        # getAccountInfo, the jsonParsed shape changed, both vantages rotated) must surface:
        # WARN-level on every failure (the operator's warn scan must see it), and a PAGE once the
        # streak says it is not a blip — 4 consecutive failures (~45–60 min at the 900 s retry
        # floor), repeating per ALERT_THROTTLE while the blindness persists; first page immediate
        # at the threshold (the 0-sentinel guard — the throttle gates repeats only).
        _alpenglow_fail_streak=$(( ${_alpenglow_fail_streak:-0} + 1 ))
        log_warn "[alpenglow] gate probe FAILED (streak ${_alpenglow_fail_streak}) — status UNKNOWN, keeping last known '${_alpenglow_gate_state:-none}'; retry in ~15m"
        if [[ ${_alpenglow_fail_streak} -ge 4 ]]; then
            if [[ ${_last_alpenglow_blind_alert:-0} -eq 0 || $(( now - _last_alpenglow_blind_alert )) -ge ${ALERT_THROTTLE:-600} ]]; then
                _last_alpenglow_blind_alert=$now
                alert_warn "⚠️ ALPENGLOW TRIPWIRE BLIND: ${_alpenglow_fail_streak} consecutive feature-gate probe failures — the gate could flip unseen. Check TIER2/TIER3 getAccountInfo availability (provider API change? both vantages rotated?)."
            fi
        fi
        return 0
    fi
    _alpenglow_fail_streak=0
    _last_alpenglow_blind_alert=0
    prev="$_alpenglow_gate_state"
    if [[ "$state" == "$prev" ]]; then
        log_info "[alpenglow] feature gate: ${state} (unchanged)"
        return 0
    fi
    if [[ "$state" == "pending" ]]; then
        log_warn "[alpenglow] FEATURE GATE TRANSITION: ${prev:-undetermined} → pending — paging (the 4.2 audit must re-run)"
        alert_warn "🚨 ALPENGLOW FEATURE GATE is now pending (was ${prev:-undetermined}). On activation set-identity requires a vote-history file by default and vote observation changes — re-run the 4.2 audit; Blocks 5–6 constants are frozen until it passes. See docs/SAFETY.md."
        _alpenglow_gate_state="pending"
        save_state
        return 0
    fi
    if [[ "$state" == "active" ]]; then
        # v0.7 (№9, reviewer): ACTIVE escalates to the CRITICAL channel (alert, queued — the
        # UNKNOWN-IDENTITY class and channel): set-identity now fails by default without a
        # vote-history file, i.e. this tool's promote path may be INERT. pending stays
        # alert_warn — there is epoch-boundary slack before activation.
        log_warn "[alpenglow] FEATURE GATE TRANSITION: ${prev:-undetermined} → ACTIVE — paging CRITICAL (promote path may be inert)"
        alert "ALPENGLOW FEATURE GATE ACTIVE (was ${prev:-undetermined}) — set-identity now requires a vote-history file by default: this tool's promote path can start FAILING (protection may be inert, the UNKNOWN-IDENTITY class). Re-run the 4.2 audit; Blocks 5–6 constants are frozen until it passes. See docs/SAFETY.md." "$ALPENGLOW_FEATURE_ID" "🚨 ALPENGLOW ACTIVE — RE-AUDIT REQUIRED"
        _alpenglow_gate_state="active"
        save_state
        return 0
    fi
    # → inactive from pending/active should not happen on-chain (a gate does not deactivate):
    # record it, no page. From empty it is simply the first determination.
    if [[ -z "$prev" ]]; then
        log_info "[alpenglow] feature gate: inactive (first determination)"
    else
        log_warn "[alpenglow] feature gate went ${prev} → inactive (unexpected reverse) — recorded, no page"
    fi
    _alpenglow_gate_state="inactive"
    save_state
    return 0
}

# ── v0.7 (Block 3, slice-4 rework) — TAKEOVER STARVATION PAGE (STANDBY ONLY; page-only) ────────
# A starving episode is SILENT: every hold path that moves the anchor (blindness re-anchor,
# provider flip, span-floor hold) keeps elapsed < TAKEOVER_DELAY, and the delay-branch early
# return in attempt_takeover fires BEFORE the single alert_warn in the fence_reason block —
# measured (reviewer, 2026-08-17): dead holder + both externals blinking one cycle every <=55s =
# NO take in an hour and ZERO pages. Called as the FIRST statement of attempt_takeover (before
# the H1.3 lockout), so it is reachable from EVERY hold path — the delay-branch early return
# included (that is where the measured silence lives).
# THE ANCHOR TRAP: held-time is measured from FIRST_DELINQUENT_TIME, NEVER from takeover_anchor —
# the anchor is exactly what starvation moves; an alarm anchored to it starves with the takeover.
# NOT gated by _takeover_alert_sent (that latch covers the one-shot fence alert; starvation must
# keep paging, throttled by ALERT_THROTTLE). Page-only: changes no verdict, triggers no action.
# Deliberately NOT on the primary's recovery path: post-failover the old primary sits unstaked
# indefinitely while the standby legitimately votes staked (manual switch-back is the documented
# path) — a symmetric recovery-starvation page would page forever in that healthy steady state.
_maybe_starvation_page() {
    local thr="${TAKEOVER_STARVATION_ALERT_SECS:-300}" now_s held
    [[ "$thr" =~ ^[0-9]+$ ]] || thr=300
    thr=$((10#$thr))
    [[ $thr -gt 0 ]] || return 0
    [[ ${FIRST_DELINQUENT_TIME:-0} -gt 0 ]] || return 0
    now_s=$(mono_now)
    held=$(( now_s - FIRST_DELINQUENT_TIME ))
    [[ $held -ge $thr ]] || return 0
    # The throttle gates REPEATS only. mono_now is boot-relative: on a freshly booted host
    # (uptime < ALERT_THROTTLE) an unguarded "now - 0" would silently delay the FIRST page
    # (measured: episode at uptime 50s → first page at held=550s instead of 300s).
    if [[ ${_last_starvation_alert:-0} -gt 0 ]]; then
        [[ $(( now_s - _last_starvation_alert )) -ge ${ALERT_THROTTLE:-600} ]] || return 0
    fi
    _last_starvation_alert=$now_s
    _starvation_paged=1
    alert_warn "⚠️ TAKEOVER STARVATION: holder delinquent ${held}s and the takeover is still held. This episode: blind cycles=${_ep_blind_cycles:-0}, provider flips=${_ep_provider_flips:-0}, span-floor holds=${_ep_floor_holds:-0}. Blindness re-anchors the countdown (blindness-is-life) — check TIER2/TIER3 RPC health and rate limits, and the holder itself; a post-self-fence re-take lockout also holds here (and is right to). Page-only: no action was taken."
}

# ── v0.7 (Block 3, slice-4 rework) — starvation resolution notice (STANDBY ONLY) ───────────────
# Called at every episode close — FIRST statement of window_reset (before FIRST_DELINQUENT_TIME is
# zeroed) and in the main-loop delinquency-cleared branch (which does not call window_reset): if
# this episode paged starvation, say it is over and how it ended; always drop the paging state.
_starvation_note_close() {
    if [[ -n "$_starvation_paged" && ${FIRST_DELINQUENT_TIME:-0} -gt 0 ]]; then
        alert_info "✅ Takeover starvation over — episode closed (${1}) after $(( $(mono_now) - FIRST_DELINQUENT_TIME ))s (blind=${_ep_blind_cycles:-0} flips=${_ep_provider_flips:-0} floor-holds=${_ep_floor_holds:-0})"
    fi
    _starvation_paged=""
    _last_starvation_alert=0
}

# --- Full takeover attempt (gates: window → delay → external confirm → gossip → take) ---
attempt_takeover() {
    now=$(mono_now)   # v0.7 (Block 3): SAFETY clock — feeds the H1.3 lockout, the N3 anchor, the cooldown and the confirm throttle
    _maybe_starvation_page   # v0.7 (B3 s4 rework): FIRST — before the H1.3 lockout, reachable from EVERY hold path (the delay-branch early return included: that is where the measured silence lives)
    # v0.6.9 (H1.3): post-self-fence RE-TAKE LOCKOUT — checked before everything else. After a
    # self-fence demote the staked vote account WILL look delinquent+frozen (WE were the voter and we
    # stopped): external-confirm and vote-liveness would both pass and this node would take back the
    # identity it fenced away, re-creating the isolated-holder state. Refuse until the cooldown
    # elapses; the episode state was reset at the demote, so every gate then re-evaluates FRESH.
    # FAILURE DIRECTION: toward NOT taking (availability loss, never a double-sign).
    if [[ ${SELF_FENCE_DEMOTE_TIME:-0} -gt 0 && $(( now - SELF_FENCE_DEMOTE_TIME )) -lt ${SELF_FENCE_RETAKE_COOLDOWN:-600} ]]; then
        if [[ $(( now - _last_lockout_log )) -ge 60 ]]; then
            log_warn "Re-take locked out after self-fence: $(( SELF_FENCE_RETAKE_COOLDOWN - (now - SELF_FENCE_DEMOTE_TIME) ))s remaining — we fenced OURSELVES; the delinquency we see is (likely) our own demote, not a dead holder"
            _last_lockout_log=$now
        fi
        return 1
    fi
    # v0.7 (Block 3, slice 4 / AUDIT-5 A9a): capture the vote-liveness FIRST sample on EVERY
    # take-path cycle where it is missing — not only inside the delay branch below (where it lived
    # through slice 3). A late-triggering episode (elapsed already >= TAKEOVER_DELAY on the very
    # first call — a flaky LOCAL RPC delaying the window fill reaches this with stock config) must
    # still build a real observation span; pinned only by the fence's own first-sample path, the
    # verdict pair ended up just VOTE_LIVENESS_MIN_INTERVAL apart (measured: take at t0+10s).
    # A cycle whose sampler yields nothing usable is a BLIND cycle (AUDIT-5 S-3) — stamped BEFORE
    # the anchor below is computed, so this very cycle's blindness already re-anchors. Once ANY
    # blind cycle was observed this episode (_last_blind_end > 0), keep probing even after the pin
    # (success leaves the pinned pair untouched — only the blind stamps stop), so the observed end
    # of blindness tracks the real one at take-path-cycle granularity.
    if [[ "$VOTE_LIVENESS_VERIFY" == "true" && ( -z "$_liveness_first_vote" || ${_last_blind_end:-0} -gt 0 ) ]]; then
        # Known cost (verifier, slice 4): once any blind cycle is seen this probe runs EVERY
        # take-path cycle — in turbo ~1 getVoteAccounts/s against Tier-2, and a rate-limited tier's
        # 429s parse as blind (mild self-reinforcement, mitigated by the T3 fallback). Safety does
        # not need per-cycle granularity (the pinned pair's monotonicity covers unprobed stretches);
        # a probe throttle here is sanctioned future work — reduce load, never weaken the stamps.
        local s0 s0rest; s0=$(get_staked_liveness_sample) || s0=""
        if [[ -z "$s0" ]]; then
            _note_blind_cycle "$now"   # v0.7 (B3 s4 / S-3): no provider yielded a sample — blind cycle
        else
            _note_observation "$now"   # v0.7 (B3 s4 rework): a successful sample with the pair already pinned must still note the observation (the episodic span floor measures from it)
            if [[ -z "$_liveness_first_vote" ]]; then
                # v0.7 (Block 3, slice 2 / AUDIT-5 A2): the sample is "<lastVote> <ref> <tier>"; $()
                # ran the sampler in a subshell, so re-derive _liveness_sample_provider from the
                # third field and PIN the pair to that vantage alongside the vote/tip capture (a
                # two-field sample — old mocks/consumers — yields an empty label).
                s0rest="${s0#* }"
                _liveness_first_vote="${s0%% *}"; _liveness_first_tip="${s0rest%% *}"; _liveness_first_ts="$now"
                _liveness_sample_provider=""; [[ "$s0rest" == *" "* ]] && _liveness_sample_provider="${s0rest##* }"
                _liveness_first_provider="$_liveness_sample_provider"
                log_info "[liveness prefetch] first sample lastVote=${_liveness_first_vote} tip=${_liveness_first_tip} provider=${_liveness_first_provider:-unknown}"
            fi
        fi
    fi
    # v0.6.7 (N3): anchor the takeover delay to the LATER of first-delinquent and last-seen-voting.
    # While a holder is delinquent BUT still voting, the liveness fence below records
    # LAST_LIVENESS_ACTIVE_TIME; measuring elapsed from max(FIRST_DELINQUENT_TIME, that) makes the
    # FULL delay re-elapse from the holder's last observed vote, so PRIMARY always gets its complete
    # self-fence window from the moment it actually goes silent (no cross-node double-stake overlap).
    # bash has no ternary → compute the max with an if. (Normal failover is unchanged: when the holder
    # is already silent before STANDBY checks, liveness never returns active, LAST_LIVENESS_ACTIVE_TIME
    # stays 0, and this falls back to FIRST_DELINQUENT_TIME exactly as v0.6.6.)
    takeover_anchor=$FIRST_DELINQUENT_TIME
    if [[ $LAST_LIVENESS_ACTIVE_TIME -gt $takeover_anchor ]]; then
        takeover_anchor=$LAST_LIVENESS_ACTIVE_TIME
    fi
    # v0.7 (Block 3, slice 4 / AUDIT-5 S-3): third anchor input — the END of the last observed
    # BLIND cycle. INVARIANT(blindness-is-life): time we could not observe the holder counts as if
    # the holder was voting; the countdown only counts OBSERVED silence. Both externals down across
    # the delay used to leave this anchor untouched: on recovery the pair rendered FROZEN just one
    # VOTE_LIVENESS_MIN_INTERVAL after the first post-recovery sample and the take fired ~15s after
    # the holder's last (unobservable) vote — the 60s liveness window collapsed to ~15s (measured).
    # This restarts the N3 ANCHOR, not merely the sample pair; blindness that began BEFORE the
    # first sample is the same rule with zero prior observations — the FULL countdown starts over
    # from the end of blindness. Never touched by a mere delay cycle (no observation attempted —
    # see _note_blind_cycle), so a blindness-free episode is byte-identical to the parent.
    if [[ ${_last_blind_end:-0} -gt $takeover_anchor ]]; then
        takeover_anchor=$_last_blind_end
    fi
    elapsed_since_first=$(( now - takeover_anchor ))
    w_count=$(window_count)

    # v0.6.0: cooldown gate — after any takeover attempt (especially a FAILED one) don't retry or
    # re-alert every cycle. Without this a failed takeover loops every 1s in turbo → alert storm.
    if [[ $LAST_TAKEOVER_TIME -gt 0 && $(( now - LAST_TAKEOVER_TIME )) -lt $TAKEOVER_COOLDOWN ]]; then
        log_warn "Takeover cooldown: $(( TAKEOVER_COOLDOWN - (now - LAST_TAKEOVER_TIME) ))s remaining since last attempt"
        return 1
    fi

    # Gate 1: already checked by caller (window_triggered)

    # Pre-fetch the fence inputs during the delay (gossip hint + vote-liveness first sample)
    if [[ $elapsed_since_first -lt $TAKEOVER_DELAY ]]; then
        remaining=$(( TAKEOVER_DELAY - elapsed_since_first ))
        log_info "Takeover delay: ${remaining}s remaining (pre-fetching fence inputs...)"
        if [[ "$_gossip_prefetched" != "true" && "$GOSSIP_VERIFY" == "true" ]]; then
            _gossip_result=""
            for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
                [[ -z "$rpc" ]] && continue
                cluster_info=$(curl -s -m 5 "$rpc" -X POST \
                    -H "Content-Type: application/json" \
                    -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null) || continue
                staked_ep=$(echo "$cluster_info" | jq -r \
                    --arg pubkey "$STAKED_PUBKEY" \
                    '.result[]? | select(.pubkey == $pubkey) | .gossip // empty' 2>/dev/null | head -1)
                if [[ -n "$staked_ep" ]]; then
                    _gossip_result="$staked_ep"
                    break
                fi
            done
            _gossip_prefetched=true
            [[ -z "$_gossip_result" ]] && log_info "[gossip prefetch] Staked NOT in gossip" \
                || log_info "[gossip prefetch] Staked on $_gossip_result"
        fi
        # v0.6.2 (C1/C2) → v0.7 (Block 3, slice 4 / AUDIT-5 A9a): the vote-liveness FIRST-sample
        # capture that lived here moved ABOVE the anchor computation, so it runs on EVERY take-path
        # cycle (a late-triggering episode skips this delay branch entirely and still must pin).
        # v0.6.8 (Option A): fast-path early-exit. If we POSITIVELY observe the holder relinquished (its
        # KNOWN unstaked identity freshly advertised on >=2 vantage points — peer_has_relinquished, A2/A4/A6)
        # AND we are past THIS node's stagger floor (A3), SKIP the remaining timer and fall through to the
        # authoritative gates below. The flip skips ONLY the timer — Gate 2 (external-confirm delinquent) and
        # Gate 3 (vote-liveness==frozen) STILL run, so A1 (take iff liveness frozen) and A5 (fresh live
        # re-sample) are enforced by construction. No flip (or off) ⇒ the exact v0.6.7 wait (pure OR fallback).
        if [[ "$WITNESS_FASTPATH" == "true" && -z "$_fastpath_disabled" ]] && [[ $elapsed_since_first -ge $_fastpath_stagger_floor ]] && peer_has_relinquished; then
            log_warn "[fast-path] holder relinquished (positive unstaked-identity flip, corroborated) — past the ${_fastpath_stagger_floor}s stagger floor; skipping ${remaining}s remaining delay; proceeding to authoritative external-confirm + liveness gates"
        else
            return 1  # delay not passed yet (no corroborated flip) → keep waiting (v0.6.7 behavior)
        fi
    fi

    # Gate 2: Delay passed → confirm via external RPCs.
    # v0.6.1 (F2): throttle re-confirm so a both-RPC-down "hold" state does not curl
    # T2+T3 every 1s in turbo. The throttle is armed ONLY by a could-not-confirm (r==2)
    # result below — a confirmed-but-waiting-on-gossip state (r==0) is NOT throttled, so it
    # keeps re-checking gossip every cycle (don't lag PRIMARY dropping from gossip).
    if [[ $_last_confirm_attempt -gt 0 && $(( now - _last_confirm_attempt )) -lt $EXTERNAL_CONFIRM_THROTTLE ]]; then
        log_info "External confirm throttled ($(( EXTERNAL_CONFIRM_THROTTLE - (now - _last_confirm_attempt) ))s) — holding window (${w_count}/${DELINQUENCY_WINDOW_SIZE})"
        return 1
    fi

    confirm_delinquency_external
    local confirm_result=$?

    # v0.6.1 (F2): three-valued result.
    #   1 = externals say NOT delinquent → real false positive → reset the window
    #   2 = could not confirm            → HOLD: keep window/turbo, arm throttle, retry
    #   0 = confirmed                    → fall through to the gossip gate (NOT throttled)
    if [[ $confirm_result -eq 1 ]]; then
        log_warn "External RPC says NOT delinquent — false positive, resetting window"
        window_reset
        return 1
    elif [[ $confirm_result -eq 2 ]]; then
        _last_confirm_attempt=$now   # arm throttle only for the both-RPC-down HOLD
        _note_blind_cycle "$now"     # v0.7 (B3 s4 / S-3): cannot confirm = no usable observation — blind cycle, the countdown re-anchors (INVARIANT(blindness-is-life))
        log_info "External RPC could not confirm — holding window (${w_count}/${DELINQUENCY_WINDOW_SIZE}), will retry"
        return 1
    fi

    # Gate 3: split-brain fence.
    # v0.6.3 (Block 1): vote-liveness is the SINGLE AUTHORITATIVE gate. A STAKED pubkey's gossip
    # ContactInfo persists in CRDS for ~48h (epoch-length timeout), so a stale "dropped-but-present"
    # entry is indistinguishable from a live holder via getClusterNodes — gossip therefore MUST NOT
    # block a takeover that liveness has already cleared (it could otherwise stall a legitimate
    # takeover for hours). Takeover proceeds iff external-confirm==delinquent AND vote-liveness==
    # frozen(1). "voting"(0) and "cannot determine"(2) both BLOCK (invariant 3, fail closed).
    # v0.5.9: the prefetch is a HINT only — liveness re-samples live here before taking.
    local fence_reason=""

    # (a) Gossip is ADVISORY only — it logs where the staked pubkey is seen / a self-match, and may
    #     corroborate, but its verdict NO LONGER gates takeover (a ~48h-stale entry must not block).
    if [[ "$GOSSIP_VERIFY" == "true" ]]; then
        _gossip_prefetched=false   # consume the prefetch hint; re-check live for the log line
        if check_primary_dropped_identity; then
            log_info "[fence] gossip advisory: no non-self staked holder seen (corroborates liveness)"
        else
            log_info "[fence] gossip advisory: staked still present in gossip (possibly a ~48h-stale CRDS entry) — NOT blocking; vote-liveness is authoritative"
        fi
    fi

    # (b) Vote-liveness — the authoritative, REQUIRED fence (all roles).
    if [[ "$VOTE_LIVENESS_VERIFY" == "true" ]]; then
        staked_is_actively_voting; local liveness=$?
        # ── v0.7 (Block 3, slice 4) hunk (RATIFIED, 2026-08-17) — observation-span floor: a
        # FROZEN verdict resting on < VOTE_LIVENESS_MIN_SPAN seconds of the EPISODE's observed
        # span is demoted to "cannot determine yet" (see _liveness_span_short). Strict no-op on
        # the normal live-tested path (span ≈ 51s at the take) and after any blindness; only
        # late-observation episodes wait. Revert = delete this hunk (one line + comment).
        if [[ $liveness -eq 1 ]] && _liveness_span_short; then liveness=2; fi
        # ── end slice-4 floor hunk ──
        if [[ $liveness -eq 0 ]]; then
            fence_reason="staked identity is actively voting"
            # v0.6.7 (N3): holder is STILL voting → re-anchor the takeover delay to now, so the full
            # delay must re-elapse from this observation before STANDBY may take (see attempt_takeover
            # head). Only set on an "active" verdict — "frozen"/"cannot determine" must NOT push the
            # anchor, or the takeover could never fire.
            LAST_LIVENESS_ACTIVE_TIME=$(mono_now)
        elif [[ $liveness -eq 2 ]]; then
            fence_reason="cannot determine vote-liveness yet"
        fi
    elif [[ "${ALLOW_UNFENCED_TAKEOVER:-false}" == "true" ]]; then
        # Dangerous, explicit operator override (startup also warns). No authoritative fence at all.
        log_warn "[fence] ⚠️ vote-liveness DISABLED and ALLOW_UNFENCED_TAKEOVER=true — UNFENCED takeover (operator override)"
    else
        # Required but disabled and no override → cannot determine → BLOCK (invariant 3). The daemon
        # normally refuses to start in this state (startup_checks); this is the belt-and-suspenders.
        fence_reason="vote-liveness required but VOTE_LIVENESS_VERIFY!=true (set ALLOW_UNFENCED_TAKEOVER=true to override)"
    fi

    if [[ -n "$fence_reason" ]]; then
        if [[ -z "$_takeover_alert_sent" ]]; then
            alert_warn "⚠️ Delinquent but fence not clear: ${fence_reason}. Waiting..."
            _takeover_alert_sent=1
        fi
        log_info "Fence not clear (${fence_reason}) — waiting"
        return 1
    fi

    # ALL GATES PASSED → TAKE OVER!
    tier_summary="T1:health✅ LOCAL:delinq✅(${w_count}/${DELINQUENCY_WINDOW_SIZE}) EXTERN:confirm✅"
    [[ "$GOSSIP_VERIFY" == "true" ]] && tier_summary+=" gossip:advisory"
    if [[ "$VOTE_LIVENESS_VERIFY" == "true" ]]; then tier_summary+=" liveness:frozen✅"; else tier_summary+=" liveness:OFF⚠️"; fi
    [[ "$_turbo_mode" == "true" ]] && tier_summary+=" ⚡turbo"

    # v0.7 (Block 3, slice 5 / A8): the pre-take `alert_info "🔍 Takeover: $tier_summary"` that
    # stood here is DELETED — a network call between the verdict and the mutation was exactly the
    # act-then-alert half the reviewer pre-registered against. The tier summary is NOT lost: it
    # travels verbatim inside `reason` ("Delinquent ${elapsed_since_first}s ($tier_summary)") into
    # the TOOK STAKED ✅ / WOULD TAKE / TAKEOVER FAILED alert.
    # ACCEPTED TRADEOFF (reviewer, 2026-08-18), a tradeoff and not a free win: the FIRST page about
    # a take now follows the mutation — a process death in the fraction of a second between them
    # leaves the take recorded only in the local log, unsent. Accepted because the alternative held
    # ~10s of blocking network BEFORE a safety-critical mutation on a proof already ~20s stale, and
    # a dead monitor is covered by the dead-man's switch.
    take_staked_identity "Delinquent ${elapsed_since_first}s ($tier_summary)" || true
    return 0
}

# --- Tier 2: ALCHEMY delinquency detection ---
# Returns: 0 = delinquent, 1 = not delinquent, 2 = unreachable

tier2_check_delinquency() {
    STAT_TIER2_CHECKS=$((STAT_TIER2_CHECKS + 1))

    # Adaptive timeout: 5s in turbo mode (network already confirmed), 15s normal
    local curl_timeout=15
    [[ "$_turbo_mode" == "true" ]] && curl_timeout=5

    local vote_result
    vote_result=$(curl -s -m "$curl_timeout" "$TIER2_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)

    if [[ $? -ne 0 || -z "$vote_result" ]]; then
        log_warn "[TIER2] Alchemy unreachable"
        return 2
    fi
    echo "$vote_result" | jq -e '.result' &>/dev/null || { log_warn "[TIER2] Invalid response"; return 2; }

    # Check delinquent by votePubkey
    local is_delinquent
    is_delinquent=$(echo "$vote_result" | jq -r \
        --arg vote "$VOTE_PUBKEY" \
        '.result.delinquent[]? | select(.votePubkey == $vote) | .votePubkey // empty' 2>/dev/null)

    if [[ -n "$is_delinquent" ]]; then
        log_info "[TIER2] Vote account $VOTE_PUBKEY DELINQUENT"
        return 0
    fi

    # Check by nodePubkey as fallback
    is_delinquent=$(echo "$vote_result" | jq -r \
        --arg pubkey "$STAKED_PUBKEY" \
        '.result.delinquent[]? | select(.nodePubkey == $pubkey) | .nodePubkey // empty' 2>/dev/null)

    if [[ -n "$is_delinquent" ]]; then
        log_info "[TIER2] Node $STAKED_PUBKEY DELINQUENT"
        return 0
    fi

    # Optional: custom latency threshold
    if [[ $MAX_DELINQUENT_SLOTS -gt 0 ]]; then
        local current_slot last_vote
        current_slot=$(curl -s -m "$curl_timeout" "$TIER2_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null \
            | jq -r '.result // empty' 2>/dev/null)

        last_vote=$(echo "$vote_result" | jq -r \
            --arg vote "$VOTE_PUBKEY" \
            '(.result.current + .result.delinquent)[] | select(.votePubkey == $vote) | .lastVote // empty' 2>/dev/null)

        if [[ -n "$current_slot" && -n "$last_vote" && "$current_slot" =~ ^[0-9]+$ && "$last_vote" =~ ^[0-9]+$ ]]; then
            local latency=$(( current_slot - last_vote ))
            if [[ $latency -gt $MAX_DELINQUENT_SLOTS ]]; then
                log_info "[TIER2] Latency $latency > $MAX_DELINQUENT_SLOTS — treating as delinquent"
                return 0
            fi
        fi
    fi

    log_info "[TIER2] NOT delinquent"
    return 1
}

# --- Tier 3: PUBLIC RPC confirmation + gossip verify ---
# Returns: 0 = confirmed delinquent, 1 = not delinquent, 2 = unreachable

tier3_confirm_delinquency() {
    STAT_TIER3_CHECKS=$((STAT_TIER3_CHECKS + 1))

    local vote_result
    vote_result=$(curl -s -m 15 "$TIER3_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)

    if [[ $? -ne 0 || -z "$vote_result" ]]; then
        log_warn "[TIER3] Public RPC unreachable"
        return 2
    fi
    # v0.6.1 (F1): validate .result like Tier 2 / LOCAL do. An HTTP-200 error body
    # (public-RPC 429, HTML, Cloudflare 1020) has no .result; without this guard it
    # was read as "NOT delinquent" (return 1) instead of "unreachable/ambiguous" (2).
    echo "$vote_result" | jq -e '.result' &>/dev/null || { log_warn "[TIER3] invalid response"; return 2; }

    local is_delinquent
    is_delinquent=$(echo "$vote_result" | jq -r \
        --arg vote "$VOTE_PUBKEY" \
        '.result.delinquent[]? | select(.votePubkey == $vote) | .votePubkey // empty' 2>/dev/null)

    if [[ -z "$is_delinquent" ]]; then
        # Also check by nodePubkey
        is_delinquent=$(echo "$vote_result" | jq -r \
            --arg pubkey "$STAKED_PUBKEY" \
            '.result.delinquent[]? | select(.nodePubkey == $pubkey) | .nodePubkey // empty' 2>/dev/null)
    fi

    if [[ -n "$is_delinquent" ]]; then
        log_info "[TIER3] Confirmed DELINQUENT"
        return 0
    fi

    log_info "[TIER3] NOT delinquent"
    return 1
}

# --- Gossip verification (uses Tier 2 or 3) ---
# v0.5.9: SEMANTICS FIXED (was inverted, could cause split-brain)
# v0.6.2 (C3/F3): compare the FULL ip:port endpoint, and only a GENUINE self match
# (the staked identity advertised on our OWN unstaked endpoint, i.e. a stale entry from
# when we held it) is treated as "us/safe". A staked endpoint on any OTHER endpoint —
# including a different node that happens to share our public IP on a different port —
# is a present holder → BLOCK. This is STANDBY defense-in-depth; the authoritative
# split-brain fence is now the vote-liveness check (staked_is_actively_voting).
# Returns: 0 = gossip clear (no non-self holder)   1 = a holder is present / cannot verify
#
# Note: with GOSSIP_VERIFY=false (e.g. BACKUP) this returns 0 (gossip skipped); the caller
# still gates on external confirmation, TAKEOVER_DELAY, and vote-liveness.

check_primary_dropped_identity() {
    [[ "$GOSSIP_VERIFY" != "true" ]] && { log_info "Gossip verify disabled — treating as safe"; return 0; }

    local any_rpc_responded=false

    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        [[ -z "$rpc" ]] && continue
        local cluster_info
        cluster_info=$(curl -s -m 15 "$rpc" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null) || continue
        echo "$cluster_info" | jq -e '.result' &>/dev/null || continue
        any_rpc_responded=true

        # Full ip:port endpoint (v0.6.2 C3: no cut -d: -f1 — port matters).
        local staked_gossip_ep
        staked_gossip_ep=$(echo "$cluster_info" | jq -r \
            --arg pubkey "$STAKED_PUBKEY" \
            '.result[]? | select(.pubkey == $pubkey) | .gossip // empty' 2>/dev/null | head -1)

        if [[ -z "$staked_gossip_ep" ]]; then
            log_info "[gossip via $rpc] Staked identity NOT in gossip — holder dropped it"
            continue
        fi

        # Staked IS in gossip — is it on OUR OWN endpoint (a stale entry from when WE held it)?
        local our_gossip_ep
        our_gossip_ep=$(echo "$cluster_info" | jq -r \
            --arg pubkey "$UNSTAKED_PUBKEY" \
            '.result[]? | select(.pubkey == $pubkey) | .gossip // empty' 2>/dev/null | head -1)

        if [[ -n "$our_gossip_ep" && "$staked_gossip_ep" == "$our_gossip_ep" ]]; then
            log_info "[gossip via $rpc] Staked endpoint = our own ($staked_gossip_ep) — stale self entry"
            continue
        fi

        # Non-self endpoint → a holder advertises the staked identity → BLOCK.
        log_warn "[gossip via $rpc] Staked on non-self endpoint $staked_gossip_ep — holder present, DON'T take"
        return 1
    done

    if [[ "$any_rpc_responded" != "true" ]]; then
        # All RPCs unreachable — cannot verify, fail-safe to BLOCK
        log_warn "[gossip] All external RPCs unreachable — cannot verify, BLOCKING takeover"
        return 1
    fi

    log_info "[gossip] No RPC showed a non-self staked holder — gossip clear"
    return 0
}

# --- Vote-liveness fence (v0.6.2 C1/N4) ---
# The topology-independent anti-double-sign signal: is the staked vote account producing
# votes right now? It does not care which IP/port holds the identity or how many servers
# exist — only whether SOMEONE is voting it. This is what actually prevents double-sign.

# Echo "<lastVote> <ref> <tier>" for the staked vote account AND a cluster-wide freshness reference,
# BOTH read from the SAME getVoteAccounts payload, via external RPC (Tier2 → Tier3), plus the tier
# label ("T2"/"T3") of the provider that answered (v0.7 Block 3 slice 2 — see below). Empty output
# + nonzero return when no external RPC can answer. Fields 1–2 are unchanged from v0.6.3, so
# two-field consumers keep working.
#
# v0.6.3 (Block 1):
#   - Sample at commitment=processed (research Q6/e): fresher and less bursty than the default
#     finalized commitment, which lags ~32+ slots and advances in bursts.
#   - The freshness reference is the cluster-wide MAX lastVote computed from the SAME payload (one
#     atomic bank snapshot), NOT a separate getSlot. This ties "is this RPC's view fresh?" to the
#     exact snapshot the staked lastVote came from: a stale/cached/lagging payload has a
#     non-advancing cluster-max, and (crucially) it cannot show a fresh cluster-max while the staked
#     lastVote is stale, because both come from one snapshot. A decoupled getSlot could be cached or
#     served by a different RPC than the vote read (cross-RPC fallthrough / asymmetric cache) and
#     mis-clear the fence (false-ALLOW). staked_is_actively_voting treats a non-advancing reference
#     across the interval as "RPC stalled/lagging → cannot determine → BLOCK".
get_staked_liveness_sample() {
    local rpc vote_result lv ref tier
    # v0.7 (Block 3, slice 2 / AUDIT-5 A2): label WHICH tier answered. A liveness pair is only
    # comparable same-vantage (a lagging fallback provider can collapse a live holder's advance to
    # ≤ EPSILON → false FROZEN), so the verdict logic must know when a pair mixed providers. The
    # label travels two ways: the global _liveness_sample_provider (set on every successful return)
    # and a THIRD stdout field after "<lastVote> <ref>" — $() callers run this function in a
    # subshell, so they re-derive the global from that field.
    _liveness_sample_provider=""
    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        [[ -z "$rpc" ]] && continue
        tier="T3"; [[ "$rpc" == "$TIER2_RPC" ]] && tier="T2"
        # v0.6.2 (C1): "Cache-Control: no-cache" defeats an HTTP/CDN cache in front of the RPC.
        vote_result=$(curl -s -m 10 "$rpc" -X POST \
            -H "Content-Type: application/json" -H "Cache-Control: no-cache" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts","params":[{"commitment":"processed"}]}' 2>/dev/null) || continue
        echo "$vote_result" | jq -e '.result' &>/dev/null || continue
        lv=$(echo "$vote_result" | jq -r \
            --arg vote "$VOTE_PUBKEY" \
            '(.result.current + .result.delinquent)[]? | select(.votePubkey == $vote) | .lastVote // empty' 2>/dev/null | head -1)
        [[ -n "$lv" && "$lv" =~ ^[0-9]+$ ]] || continue
        # Cluster-wide freshness reference = MAX lastVote in the SAME payload (advances every slot).
        ref=$(echo "$vote_result" | jq -r \
            '[(.result.current + .result.delinquent)[]? | .lastVote] | map(numbers) | max // empty' 2>/dev/null)
        [[ -n "$ref" && "$ref" =~ ^[0-9]+$ ]] || continue
        _liveness_sample_provider="$tier"
        printf '%s %s %s\n' "$lv" "$ref" "$tier"
        return 0
    done
    return 1
}

# Compare two lastVote samples separated by real time (>= VOTE_LIVENESS_MIN_INTERVAL).
# Returns: 0 = actively voting (advanced > epsilon)        → BLOCK takeover
#          1 = not voting (frozen across the interval)      → fence clear
#          2 = cannot determine (externals down / too soon / backwards / RPC tip stalled /
#              provider flip across the pair — re-pins, see below) → BLOCK
# The first sample is normally captured during the takeover delay (see attempt_takeover).
# Self-correcting: when advancement is seen the first sample is re-based to "now", so a holder
# that voted earlier and then died is detected as frozen after one MIN_INTERVAL rather than
# blocking forever.
staked_is_actively_voting() {
    local now2 sample rest cur tip prov elapsed delta tip_delta
    now2=$(mono_now)   # v0.7 (Block 3): SAFETY clock — the authoritative fence's sample interval must not be steppable
    sample=$(get_staked_liveness_sample) || sample=""
    cur="${sample%% *}"; rest="${sample#* }"; tip="${rest%% *}"   # tip = cluster-wide max lastVote (freshness reference)
    # v0.7 (Block 3, slice 2 / AUDIT-5 A2): third field = the answering tier ("T2"/"T3"). $() ran
    # the sampler in a subshell, so re-derive _liveness_sample_provider here; a two-field sample
    # (old mocks/consumers) yields an empty label and every pin comparison below degrades to
    # always-equal (pre-pinning behavior).
    prov=""; [[ "$rest" == *" "* ]] && prov="${rest##* }"
    _liveness_sample_provider="$prov"
    if [[ -z "$sample" || ! "$cur" =~ ^[0-9]+$ || ! "$tip" =~ ^[0-9]+$ ]]; then
        log_warn "[liveness] staked lastVote/reference unavailable (externals down) — cannot determine"
        _note_blind_cycle "$now2"   # v0.7 (B3 s4 / S-3): blind cycle — INVARIANT(blindness-is-life) re-anchors the countdown
        return 2
    fi
    _note_observation "$now2"   # v0.7 (B3 s4 rework): successful observation — pin the episode's observed-span start (no-op once pinned; re-pins after blindness)

    # First sample not captured yet → record lastVote + reference tip and wait for a real interval.
    if [[ -z "$_liveness_first_vote" ]]; then
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now2"
        _liveness_first_provider="$prov"   # v0.7 (Block 3, slice 2): pin the pair to this vantage
        log_info "[liveness] first sample lastVote=$cur tip=$tip provider=${prov:-unknown} — need a second sample (~${VOTE_LIVENESS_MIN_INTERVAL}s)"
        return 2
    fi

    elapsed=$(( now2 - _liveness_first_ts ))
    if [[ $elapsed -lt $VOTE_LIVENESS_MIN_INTERVAL ]]; then
        log_info "[liveness] only ${elapsed}s since first sample (<${VOTE_LIVENESS_MIN_INTERVAL}s) — waiting"
        return 2
    fi

    # v0.6.3 (Block 1): RPC-freshness guard. The cluster-wide reference (max lastVote from the SAME
    # payload as cur) MUST advance between the two samples; if it did not, the RPC's view is
    # stalled/cached/lagging and a "frozen" staked lastVote is meaningless (it could be a live holder
    # whose votes this stale view isn't reporting). Because cur and the reference come from one atomic
    # snapshot, a stale view cannot show a fresh reference with a stale cur. Fail closed: cannot
    # determine → BLOCK (never a false-frozen ALLOW). Re-base so the next interval is fresh.
    tip_delta=$(( tip - _liveness_first_tip ))
    if [[ $tip_delta -le 0 ]]; then
        log_warn "[liveness] cluster reference (max lastVote) did NOT advance (Δref=${tip_delta} in ${elapsed}s) — RPC view stale/lagging, cannot determine → BLOCK"
        # v0.7 (Block 3, slice 2 / AUDIT-5 A2): the re-base here is LOWER-ONLY for the vote baseline.
        # A provider flip can land on this path (a second vantage lagging ≥ the cluster's advance
        # reads ITS tip ≤ the pinned tip) while cur already carries a burst the old baseline
        # predates; adopting the higher cur would forget that burst — the same reopened-B2 hole the
        # provider re-pin's min rule closes below. Tip/clock/pin still re-base → next interval fresh.
        [[ $cur -lt $_liveness_first_vote ]] && _liveness_first_vote="$cur"
        _liveness_first_tip="$tip"; _liveness_first_ts="$now2"; _liveness_first_provider="$prov"
        return 2
    fi

    delta=$(( cur - _liveness_first_vote ))
    if [[ $delta -gt $VOTE_LIVENESS_EPSILON ]]; then
        log_warn "[liveness] staked vote ADVANCED ${delta} slots in ${elapsed}s (tip +${tip_delta}) — holder is VOTING → BLOCK"
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now2"; _liveness_first_provider="$prov"   # re-base for the next interval (pin follows)
        _liveness_obs_since="$now2"   # observed LIFE restarts the observed-silence span — the floor's claim becomes self-contained at ANY config (inert at defaults: the N3 re-anchor's DELAY 60 > floor 40)
        return 0
    fi
    if [[ $delta -lt 0 ]]; then
        log_warn "[liveness] lastVote went backwards (Δ${delta}) — inconsistent RPC view, cannot determine"
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now2"; _liveness_first_provider="$prov"
        return 2
    fi

    # v0.7 (Block 3, slice 2 / AUDIT-5 A2): PROVIDER PIN — a FROZEN verdict is valid only when both
    # samples of the pair came from the SAME vantage. A lagging fallback provider can UNDERCOUNT the
    # holder's votes (fresh-T2 first sample, T3 second sample ~29 slots behind → a live holder's
    # advance collapses to ≤ EPSILON) but can never INVENT them — so ONLY the frozen path needs this
    # check; the ADVANCED verdict above stands on any provider mix (life signs are evaluated BEFORE
    # this comparison). On a mismatch: re-pin the pair to the CURRENT vantage — LOWER-ONLY vote
    # baseline (min(old, cur): a burst observed before the flip must stay remembered), tip baseline
    # := the current tip (provider-coherent freshness guard going forward), interval clock restarted
    # — and return "cannot determine". NOT a permanent block: the next same-provider pair renders a
    # verdict; worst case one extra VOTE_LIVENESS_MIN_INTERVAL per provider flip.
    if [[ "$prov" != "$_liveness_first_provider" ]]; then
        log_warn "[liveness] provider flipped ${_liveness_first_provider:-unknown}→${prov:-unknown} across the pair — frozen reading not comparable, cannot determine → BLOCK; re-pinning to ${prov:-unknown}"
        _ep_provider_flips=$((_ep_provider_flips + 1))   # v0.7 (B3 s4 rework): episode diagnostics (starvation page); the re-pin does NOT touch _liveness_obs_since
        [[ $cur -lt $_liveness_first_vote ]] && _liveness_first_vote="$cur"
        _liveness_first_tip="$tip"; _liveness_first_ts="$now2"; _liveness_first_provider="$prov"
        return 2
    fi

    # v0.6.8 (B2): DOUBLE-SIGN-SAFETY INVARIANT — the FROZEN path deliberately does NOT re-base
    # _liveness_first_vote (only the ADVANCED/return-0 and backwards/return-2 paths above do). The first
    # sample stays PINNED for the whole episode, so `delta` is measured against the episode start
    # over an ever-growing window: ANY vote burst that lifts the holder's lastVote > EPSILON above that pin
    # — at any point in the delay — trips return 0 (VOTING → BLOCK) and re-anchors the countdown. This is
    # exactly what protects against the intermittent/flapping "wedged-but-alive" holder (Audit-1 B7): only a
    # holder that lands ZERO qualifying votes for the ENTIRE delay reads frozen. DO NOT refactor this to
    # re-base on the frozen path — a sliding per-interval window would re-open that double-sign hole.
    # INVARIANT(baseline-rises-only-on-voting): the episode vote baseline may RISE only on a
    # VOTING verdict. Every other re-base — tip-guard, backwards, provider re-pin — may only LOWER
    # it (the min rule). That is the whole rule; "why min here" reads from this line, not from
    # commit history.
    # Why it is sound, structurally (a property, not a case list — it survives refactoring):
    #   1. A lower baseline can only INFLATE delta = cur - baseline, pushing every reading toward
    #      VOTING (block) and never toward FROZEN (allow).
    #   2. A min-rule baseline UNDER-approximates the same-vantage baseline, so measured delta >=
    #      true same-vantage delta — a FROZEN reading (delta <= EPSILON) therefore implies the
    #      holder is frozen on the pinned vantage a fortiori.
    #   3. A mixed-provider pair structurally cannot reach this FROZEN return at all: every earlier
    #      exit (tip-guard, VOTING, backwards, provider mismatch) precedes it.
    # Violating this — e.g. a re-pin that ADOPTS the current (higher) lastVote, or a high-water-mark
    # pin — forgets a pre-flip vote burst and re-opens the double-sign hole this block guards
    # (measured: take ~25s after the last observed vote).
    log_info "[liveness] staked vote frozen (Δ${delta} slots, tip +${tip_delta}, in ${elapsed}s) — holder not voting → clear"
    return 1
}

# ========================= IDENTITY SWITCHING =================================

take_staked_identity() {
    # v0.7 (Block 3, slice 5 / A8): FRESH-PROOF RE-CHECK — the FIRST statement, before even the
    # DRY_RUN branch, so DRY_RUN mirrors the live decision (a DRY_RUN "WOULD TAKE" that a live
    # daemon would have aborted is a false report). After a return-0 here, the existing sequence
    # below — DRY_RUN branch / keypair `-s` test / `log_warn ">>> TAKING…"` / set-identity —
    # contains ZERO network calls before the mutation: condition (3) of the pre-registered
    # act-then-alert rule holds by construction.
    _fresh_proof_recheck || return 1
    local reason="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would TAKE staked — $reason"
        alert "$reason" "$STAKED_PUBKEY" "[DRY RUN] WOULD TAKE STAKED"
        # v0.5.9: reset window + set cooldown to prevent alert spam every cycle
        LAST_TAKEOVER_TIME=$(mono_now); save_state   # v0.6.1 (F7)
        window_reset
        return 0
    fi

    [[ ! -s "$STAKED_KEYPAIR" ]] && {
        log_error "Staked keypair missing/empty"; alert "$reason" "N/A" "TAKEOVER BLOCKED"; return 1
    }

    log_warn ">>> TAKING STAKED IDENTITY — $reason"

    # v0.6.9 (H4, B1 parity): every admin-socket call is bounded (the SAME socket get_local_identity
    # wraps in `timeout 8` — a wedged socket at the takeover instant froze the loop mid-take, possibly
    # AFTER the identity applied and BEFORE the TOOK STAKED page). On a timeout the re-read below
    # decides what actually applied. FAILURE DIRECTION on the spare's TAKE path: availability loss —
    # a not-applied take reads as TAKEOVER FAILED (episode state kept armed, N9), NEVER a kill.
    local _rc take_wedged="" add_wedged=""
    if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
        timeout -k 5 "$SETIDENTITY_TIMEOUT" fdctl set-identity --config "$CONFIG_TOML" "$STAKED_KEYPAIR" --force 2>&1 | while IFS= read -r l; do log_info "fdctl: $l"; done
        _rc=${PIPESTATUS[0]}
        [[ $_rc -eq 124 || $_rc -eq 137 ]] && { take_wedged=1; log_warn "[take] fdctl set-identity timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged; the re-read below decides what applied (fail toward NOT taking)"; }
    else
        local out
        # v0.6.0: NO --require-tower — STANDBY never has a saved tower for the staked identity
        # (towers aren't transferred), so --require-tower would block the very first takeover.
        # agave rebuilds the vote floor from the cluster; split-brain is gated by gossip above.
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR" 2>&1); _rc=$?
        [[ -n "$out" ]] && log_info "set-identity: $out"
        [[ $_rc -eq 124 || $_rc -eq 137 ]] && { take_wedged=1; log_warn "[take] set-identity timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged; the re-read below decides what applied (fail toward NOT taking)"; }
        # v0.6.9 (H4): the voter add is attempted even after a wedged set-identity — if the take DID
        # apply, voting needs the voter registered. Its own timeout is ⚠️-only; identity state stands.
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" authorized-voter add "$STAKED_KEYPAIR" 2>&1); _rc=$?
        [[ -n "$out" ]] && log_info "add-voter: $out"
        [[ $_rc -eq 124 || $_rc -eq 137 ]] && { add_wedged=1; log_warn "[take] authorized-voter add timed out (${SETIDENTITY_TIMEOUT}s) — voting may not start"; }
    fi

    sleep 1    # v0.5.9: reduced from 2s (agave-validator updates instantly)
    CURRENT_IDENTITY=$(get_local_identity) || true
    if [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]]; then
        LAST_TAKEOVER_TIME=$(mono_now); STAT_TAKEOVERS=$((STAT_TAKEOVERS + 1)); save_state   # v0.6.1 (F7)
        window_reset
        _selffence_reset   # v0.6.9 (B1): a FRESH staked tenure must start the self-fence trackers from
                           # scratch, mirroring the primary's switch_to_staked. Otherwise stale H3
                           # restore-pending flags (armed by load_state from a PRIOR staked tenure and
                           # never consumed while we were unstaked) survive into this take, and the
                           # freshly-promoted validator's normal catch-up lag can trip a backdated
                           # self-fence + 600s re-take lockout. (_selffence_reset also clears the
                           # collision-detector strike streak — fresh flap debounce for this tenure.)
                           # Fails toward: no spurious self-demote of a legitimate takeover.
        alert "$reason" "$STAKED_PUBKEY" "TOOK STAKED ✅"   # v0.6.4: role-agnostic (NODE_NAME prefix already identifies the node, incl. BACKUP)
        # v0.6.9 (H4): the take APPLIED but the admin socket wedged mid-take → success WITH a warning.
        [[ -n "$take_wedged" ]] && alert_warn "⚠️ Take applied but the admin socket wedged (timeout rc 124/137) during set-identity — verify node health."
        [[ -n "$add_wedged" ]] && alert_warn "⚠️ authorized-voter add timed out after the take — voting may not start; run 'agave-validator --ledger ${LEDGER_PATH} authorized-voter add <staked keypair>' manually."
        return 0
    else
        # v0.6.9 (H4): identity != staked or unreadable (incl. the wedged case) → TAKEOVER FAILED.
        # N9 discipline: the cooldown is set (anti alert-storm) but the takeover EPISODE state (window /
        # N3 anchors / liveness samples) is deliberately NOT reset, so the retry discipline still
        # applies. NEVER a hard-stop here — the spare's take path fails toward availability loss.
        LAST_TAKEOVER_TIME=$(mono_now); save_state   # v0.6.0: cooldown even on failure; v0.6.1 (F7): persist
        alert "$reason" "${CURRENT_IDENTITY:-unknown}" "TAKEOVER FAILED ❌"; return 1
    fi
}

# v0.6.9 (H4): a give-back (HOLDER demote) admin-socket call wedged (rc 124/137). Re-read the identity
# (bounded — get_local_identity carries its own timeout) to learn what actually applied:
#   - already unstaked → the demote landed before the wedge; proceed as success + ⚠️ verify-health page;
#   - still staked / unreadable → the holder may STILL BE VOTING → 🚨 page + escalate to the hard stop
#     (H1/B1 discipline, gated by SELF_FENCE_HARD_STOP — the H2 mask + re-verify port).
# FAILURE DIRECTION: a holder demote fails toward STOPPING the validator (a stopped validator cannot
# double-sign) — never toward silently staying staked.
_giveback_wedged_escalate() {
    local why="$1" reason="$2"
    CURRENT_IDENTITY=$(get_local_identity) || true
    if [[ -n "$UNSTAKED_PUBKEY" && "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" ]]; then
        log_warn "[give-back] $why — but the identity DID flip to unstaked; treating as success (verify node health)"
        window_reset
        alert "$reason (wedged-but-applied: $why)" "$UNSTAKED_PUBKEY" "GAVE BACK — unstaked ✅"
        alert_warn "⚠️ Give-back applied but the admin socket wedged ($why) — verify node health."
        return 0
    fi
    log_error "[give-back] $why — identity still '${CURRENT_IDENTITY:-unreadable}'; the staked holder may STILL BE VOTING"
    alert "Give-back wedged ($why) and the identity did not flip to unstaked — this node may still be voting the staked identity. Escalating per SELF_FENCE_HARD_STOP." "$STAKED_PUBKEY" "GIVE BACK WEDGED — HOLDER MAY STILL BE VOTING 🚨"
    _selffence_hard_stop "$why"
    return $?
}

give_back_identity() {
    local reason="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would give back — $reason"
        alert "$reason" "$UNSTAKED_PUBKEY" "[DRY RUN] WOULD GIVE BACK"; return 0
    fi

    [[ ! -s "$UNSTAKED_KEYPAIR" ]] && { log_error "Unstaked keypair missing"; return 1; }
    log_info ">>> GIVING BACK to unstaked — $reason"

    # v0.6.9 (H4, B1 parity): bound every admin-socket call; a wedge on this HOLDER-demote path
    # escalates (safe direction: the staked identity must provably stop voting). Mirrors the
    # primary's switch_to_unstaked.
    local _rc
    if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
        timeout -k 5 "$SETIDENTITY_TIMEOUT" fdctl set-identity --config "$CONFIG_TOML" "$UNSTAKED_KEYPAIR" --force 2>&1 | while IFS= read -r l; do log_info "fdctl: $l"; done
        _rc=${PIPESTATUS[0]}
        if [[ $_rc -eq 124 || $_rc -eq 137 ]]; then
            _giveback_wedged_escalate "fdctl set-identity to unstaked timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged" "$reason"; return $?
        fi
    else
        local out
        # v0.6.9 (H4): bound remove-all; a hang here means the admin socket is wedged (set-identity
        # below would hang the same way) → escalate at once.
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" authorized-voter remove-all 2>&1); _rc=$?
        [[ -n "$out" ]] && log_info "remove-voter: $out"
        if [[ $_rc -eq 124 || $_rc -eq 137 ]]; then
            _giveback_wedged_escalate "authorized-voter remove-all timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged" "$reason"; return $?
        fi
        # v0.5.9: path-as-argument (official Anza API)
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$UNSTAKED_KEYPAIR" 2>&1); _rc=$?
        [[ -n "$out" ]] && log_info "set-identity: $out"
        if [[ $_rc -eq 124 || $_rc -eq 137 ]]; then
            _giveback_wedged_escalate "set-identity to unstaked timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged" "$reason"; return $?
        fi
    fi

    sleep 1    # v0.5.9: reduced from 2s
    CURRENT_IDENTITY=$(get_local_identity) || true
    if [[ "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" ]]; then
        window_reset
        alert "$reason" "$UNSTAKED_PUBKEY" "GAVE BACK — unstaked ✅"; return 0
    else
        alert "$reason" "${CURRENT_IDENTITY:-unknown}" "GIVE BACK FAILED ❌"; return 1
    fi
}

# ========================= STANDBY SELF-FENCE (v0.6.9 H1) =======================
# Ported from the PRIMARY self-fence (v0.6.3 Block 3 → v0.6.8 B1/B2, function-for-function) for the
# PROMOTED holder. After a takeover this node holds and votes the staked identity — and inherits the
# PRIMARY's residual: a partitioned-but-voting promoted STANDBY + a BACKUP at TAKEOVER_DELAY=120s is
# the documented SPLIT-BRAIN-RESIDUAL scenario, previously with the shipped mitigation ABSENT here
# (the STAKED branch only logged "hold"). With H1 the N1 invariant ("the holder relinquishes before
# any spare takes") exists for the STANDBY→BACKUP hop too: worst-case self-fence 30s + margin ≤ 120s.
#
# HARD RULES (identical to the primary):
#   - Fires ONLY while CURRENT_IDENTITY == STAKED (the caller gates this).
#   - LOCAL signals ONLY. No external (T2/T3) RPC may ever trigger a self-fence — an external-RPC
#     outage must never demote a healthy holder. The N6 sub-check reads ONE LOCAL getVoteAccounts
#     (commitment=processed) — the same sampler shape as the liveness fence, but as on the primary the
#     DECISION input is own-vs-cluster lag, and "cannot determine" (unreadable own/cluster lastVote)
#     counts as healthy/no-signal: the holder self-fence needs POSITIVE local evidence; ambiguity
#     fails toward STAYING STAKED (no demote on garbage), while the take paths fail toward BLOCK.
#   - It may ONLY ever lead to give_back_identity → our OWN unstaked identity (the safe direction),
#     plus the H1.3 re-take lockout. Disable with STANDBY_SELF_FENCE=false.
#   - Respects DRY_RUN (give_back_identity logs "would give back", does not swap).
# Returns 0 if it self-fenced (caller should display + sleep + continue), 1 otherwise.

# v0.6.9 (H1, S4 port): pid of the running validator (any client), or empty if none is running.
_validator_pid() {
    local p; p=$(pgrep -x agave-validator 2>/dev/null | head -1)
    [[ -z "$p" && "$VALIDATOR_TYPE" == "frankendancer" ]] && p=$(pgrep -x fdctl 2>/dev/null | head -1)
    [[ -z "$p" ]] && p=$(pgrep -x solana-validator 2>/dev/null | head -1)
    printf '%s' "$p"
}

# v0.6.9 (H1, B1+S4 port incl. the H2 mask + re-verify): the give-back admin-socket call wedged and
# the identity did not flip — the self-fence's contract is that the staked identity STOPS voting even
# when set-identity cannot run, so escalate to a HARD STOP of the validator (the safe direction: a
# dead validator cannot double-sign). Gated by SELF_FENCE_HARD_STOP. Never reached in DRY_RUN
# (give_back_identity returns before the real path). Returns 0 ONLY when the validator is confirmed
# DOWN (immediate verify + H2 delayed re-verify); 1 otherwise (caller keeps retrying/paging).
_selffence_hard_stop() {
    local why="$1"
    if [[ "${SELF_FENCE_HARD_STOP:-true}" != "true" ]]; then
        log_error "[self-fence] demote wedged ($why); SELF_FENCE_HARD_STOP!=true — NOT stopping the validator; the STAKED identity may STILL BE VOTING"
        alert "Give-back wedged ($why); hard-stop disabled — the staked identity may still be voting. INTERVENE NOW (stop the validator)." "$STAKED_PUBKEY" "STANDBY SELF-FENCE WEDGED — NO HARD STOP 🚨"
        return 1
    fi
    log_error "[self-fence] demote wedged ($why) — HARD-STOPPING the validator so the staked identity stops voting"
    local sc_out sc_rc pid_found="" pid masked="" mask_out mask_rc
    sc_out=$(timeout -k 5 15 systemctl stop "${VALIDATOR_SERVICE:-solana}" 2>&1); sc_rc=$?
    [[ -n "$sc_out" ]] && log_info "systemctl stop: $sc_out"
    # v0.6.9 (H2): stop did NOT cleanly succeed → mask the unit (--runtime; a reboot clears it — fail
    # toward recoverability) BEFORE the direct kill, so Restart=always cannot resurrect it voting
    # staked after the immediate verify. A failed mask never skips the kill (the delayed re-verify
    # catches a resurrect either way). FAILURE DIRECTION: extra stopping power only.
    if [[ $sc_rc -ne 0 ]]; then
        mask_out=$(timeout -k 5 15 systemctl mask --runtime "${VALIDATOR_SERVICE:-solana}" 2>&1); mask_rc=$?
        [[ -n "$mask_out" ]] && log_info "systemctl mask --runtime: $mask_out"
        if [[ $mask_rc -eq 0 ]]; then
            masked=1
            log_warn "[self-fence] unit ${VALIDATOR_SERVICE:-solana} masked (--runtime) so Restart=always cannot resurrect it; unmask with: systemctl unmask --runtime ${VALIDATOR_SERVICE:-solana}"
        else
            log_warn "[self-fence] systemctl mask --runtime failed (rc $mask_rc) — continuing with the kill path; the delayed re-verify below will catch a Restart=always resurrect"
        fi
    fi
    # Fallback (non-systemd / stuck unit): SIGTERM the validator PID, then SIGKILL if it ignores it.
    pid=$(_validator_pid)
    if [[ -n "$pid" ]]; then
        pid_found=1; kill "$pid" 2>/dev/null || true; log_warn "[self-fence] sent SIGTERM to validator pid $pid"
        sleep 2; pid=$(_validator_pid)
    fi
    if [[ -n "$pid" ]]; then
        kill -9 "$pid" 2>/dev/null || true; log_warn "[self-fence] SIGTERM ignored — sent SIGKILL to validator pid $pid"
        sleep 1; pid=$(_validator_pid)
    fi
    # VERIFY (S4 port): only report success if the validator is provably down.
    if [[ -n "$pid" ]]; then
        log_error "[self-fence] HARD STOP FAILED — validator pid $pid still running after systemctl stop + SIGKILL; keeping the fence armed to retry"
        alert "Hard-stop FAILED ($why) — validator still running (pid $pid) after systemctl stop + SIGKILL; the staked identity may still vote. INTERVENE NOW." "$STAKED_PUBKEY" "STANDBY SELF-FENCE — HARD STOP FAILED 🚨"
        return 1
    fi
    if [[ $sc_rc -ne 0 && -z "$pid_found" ]]; then
        log_error "[self-fence] HARD STOP UNCONFIRMED — systemctl stop failed (rc $sc_rc) and no known validator process found; cannot confirm voting stopped"
        alert "Hard-stop UNCONFIRMED ($why) — systemctl stop failed and no agave-validator/fdctl/solana-validator process found; cannot confirm the staked identity stopped voting. INTERVENE NOW." "$STAKED_PUBKEY" "STANDBY SELF-FENCE — HARD STOP UNCONFIRMED 🚨"
        return 1
    fi
    # v0.6.9 (H2): RE-verify after a Restart=always-scale delay — a directly-killed process can pass
    # the immediate check and resurrect VOTING STAKED after RestartSec. FAILURE DIRECTION: toward
    # reporting failure / paging; the wait only delays the success page, never the stop.
    sleep "${HARD_STOP_REVERIFY_SECS:-15}"
    pid=$(_validator_pid)
    if [[ -n "$pid" ]]; then
        log_error "[self-fence] HARD STOP FAILED — validator RESURRECTED (pid $pid) within ${HARD_STOP_REVERIFY_SECS:-15}s (Restart=always); keeping the fence armed to retry"
        alert "Hard-stop FAILED ($why) — the validator was stopped but RESURRECTED (pid $pid, Restart=always) within ${HARD_STOP_REVERIFY_SECS:-15}s; it may be voting staked again. INTERVENE NOW (systemctl mask --runtime ${VALIDATOR_SERVICE:-solana}; then stop it)." "$STAKED_PUBKEY" "STANDBY SELF-FENCE — HARD STOP FAILED 🚨"
        return 1
    fi
    # v0.6.9 (H2): the ✅ page names the mask state + the exact unmask command for recovery.
    if [[ -n "$masked" ]]; then
        alert "Give-back wedged ($why); HARD-STOPPED the validator — confirmed DOWN (re-verified after ${HARD_STOP_REVERIFY_SECS:-15}s). Unit ${VALIDATOR_SERVICE:-solana} is MASKED (--runtime): recover with 'systemctl unmask --runtime ${VALIDATOR_SERVICE:-solana}' before restarting (restart on the unstaked identity, confirm a remaining spare took over)." "$STAKED_PUBKEY" "STANDBY SELF-FENCE — HARD STOP ✅ (unit masked)"
    else
        alert "Give-back wedged ($why); HARD-STOPPED the validator — confirmed DOWN (re-verified after ${HARD_STOP_REVERIFY_SECS:-15}s). Node is down; recover manually (restart on the unstaked identity, confirm a remaining spare took over)." "$STAKED_PUBKEY" "STANDBY SELF-FENCE — HARD STOP ✅"
    fi
    return 0
}

# Re-arm the self-fence tracker (after any demote / identity change / startup). Same fields as the
# primary, incl. the v0.6.9 (H3) pending-restore flags (a post-demote tenure must not inherit
# pre-restart clocks).
_selffence_reset() { _last_confirmed_slot=""; _last_confirmed_advance_ts=$(mono_now); _selffence_noanswer_since=0; _selffence_votelag_since=0; _selffence_votelag_baseline=""; _selffence_votelag_healthy=0; _selffence_restore_pending=0; _selffence_noanswer_restore_pending=0; _selffence_votelag_restore_pending=0; _collision_strikes=0; _last_collision_check=0; }   # v0.6.9 (B1/S-6): also clear the collision-detector flap streak so each staked tenure debounces fresh

# v0.6.9 (H1.3): the ONE demote path for every standby self-fence signal. Order per N2: safety action
# FIRST (give_back_identity — which itself pages GAVE BACK ✅ / FAILED / escalates via the hard stop),
# the self-fence page AFTER. On a CONFIRMED demote (incl. DRY_RUN's logged success, so DRY_RUN does
# not re-fire every cycle):
#   - re-arm the self-fence trackers (N9: ONLY on success — a FAILED demote keeps the timers armed so
#     the next cycle retries; never one-and-done);
#   - arm the RE-TAKE LOCKOUT (SELF_FENCE_DEMOTE_TIME) and PERSIST it — after this demote our own
#     vote account WILL look delinquent (that is exactly why we fenced), so the normal
#     delinquency→takeover path must not take the identity right back;
#   - reset the takeover EPISODE state (window, N3 anchors, fast-path episode, liveness samples) so
#     the eventual post-cooldown evaluation starts from scratch with fresh gates;
#   - page 🚨 STANDBY SELF-FENCE — SWITCHED TO UNSTAKED with the reason.
# FAILURE DIRECTION: holder demote fails toward unstaked/hard-stop/page; the lockout fails toward
# NOT re-taking.
_selffence_demote() {
    local reason="$1"
    if give_back_identity "$reason"; then
        _selffence_reset
        SELF_FENCE_DEMOTE_TIME=$(mono_now)
        window_reset            # fresh takeover episode: window + N3 anchors + fast-path + liveness samples + confirm throttle
        _takeover_alert_sent=""
        save_state              # persist the lockout — a Restart=always monitor restart must not clear it
        alert "$reason — self-fenced: switched to our own unstaked identity; re-take locked out for ${SELF_FENCE_RETAKE_COOLDOWN}s (the staked vote account will look delinquent because WE stopped voting it)" "$UNSTAKED_PUBKEY" "STANDBY SELF-FENCE — SWITCHED TO UNSTAKED 🚨"
        return 0
    fi
    log_warn "[self-fence] demote (give-back) FAILED — keeping the timer armed to retry next cycle"
    return 1
}

# v0.6.9 (H1): the PRIMARY's check_self_fence_isolation, ported body-for-body; the demote action is
# _selffence_demote (give-back + lockout) instead of switch_to_unstaked. Signals and their arming
# rules are byte-equivalent — see the primary for the full per-signal rationale (F1 no-answer,
# N6/N8 own-vote-lag, B2 hysteresis).
check_self_fence_isolation() {
    local now slot frozen health_result behind silent own_sample own_lv cluster_max vlag vlsust
    now=$(mono_now)   # v0.7 (Block 3): SAFETY clock — a backward wall step must not disarm the fence timers

    # (1) LOCAL confirmed-slot advancement — the authoritative isolation signal.
    slot=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot","params":[{"commitment":"confirmed"}]}' 2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null)

    if [[ -z "$slot" || ! "$slot" =~ ^[0-9]+$ ]]; then
        # A BRIEF LOCAL no-answer is the validator-unreachable pause path, NOT isolation. A CONTINUOUS
        # silence while we hold staked (admin RPC up, so the loop stays in the STAKED branch) IS an
        # isolation signal (v0.6.5 F1) — time it and demote once it persists; never on a fresh start
        # (no baseline yet).
        if [[ "${SELF_FENCE_NOANSWER_SECS:-0}" =~ ^[0-9]+$ && $SELF_FENCE_NOANSWER_SECS -gt 0 && -n "$_last_confirmed_slot" ]]; then
            # v0.6.9 (H3): restart continuity — still silent across the monitor restart → inherit the
            # persisted silence clock (positive evidence only; an answering RPC drops the flag below).
            if [[ ${_selffence_noanswer_restore_pending:-0} -eq 1 ]]; then
                _selffence_noanswer_restore_pending=0
                _selffence_noanswer_since=$_selffence_restored_noanswer_since
                log_warn "[self-fence] LOCAL RPC still silent across the monitor restart — no-answer timer backdated to the persisted start ($(( now - _selffence_noanswer_since ))s ago) (v0.6.9 H3)"
            fi
            [[ $_selffence_noanswer_since -eq 0 ]] && _selffence_noanswer_since=$now   # first silent cycle
            silent=$(( now - _selffence_noanswer_since ))
            if [[ $silent -ge $SELF_FENCE_NOANSWER_SECS ]]; then
                log_warn "[self-fence] LOCAL getSlot(confirmed) silent ${silent}s (>= ${SELF_FENCE_NOANSWER_SECS}s) while staked — isolated → give back to unstaked"
                # v0.6.6 (N2) ordering: the demote never waits on notifier I/O (_selffence_demote pages
                # AFTER give_back_identity). v0.6.8 (B1)/N9: re-arm ONLY on a confirmed demote.
                _selffence_demote "self-fence: LOCAL RPC silent ${silent}s while staked — isolated"
                return 0
            fi
            log_info "[self-fence] LOCAL getSlot(confirmed) no answer (${silent}s/${SELF_FENCE_NOANSWER_SECS}s) while staked — counting toward no-answer isolation"
            return 1
        fi
        log_warn "[self-fence] LOCAL getSlot(confirmed) no answer — treating as validator-unreachable, NOT isolation"
        return 1
    fi
    # Got a numeric slot — a successful read clears the no-answer isolation timer (v0.6.5 F1).
    _selffence_noanswer_since=0
    _selffence_noanswer_restore_pending=0   # v0.6.9 (H3): the RPC answered → the persisted silence is NOT continuous

    # v0.6.9 (H3): restart continuity for the frozen-slot signal — first successful read after a
    # restore: slot still not past the persisted baseline → the stall is CONTINUOUS → backdate the
    # advance clock (fence can fire immediately); a resumed validator clears instantly instead.
    if [[ ${_selffence_restore_pending:-0} -eq 1 ]]; then
        _selffence_restore_pending=0
        if [[ -n "$_last_confirmed_slot" && $slot -le $_last_confirmed_slot ]]; then
            _last_confirmed_advance_ts=$_selffence_restored_advance_ts
            log_warn "[self-fence] LOCAL confirmed slot still not past the persisted baseline ($slot <= $_last_confirmed_slot) across the monitor restart — stall treated as continuous; advance clock backdated $(( now - _last_confirmed_advance_ts ))s (v0.6.9 H3)"
        fi
    fi

    if [[ -z "$_last_confirmed_slot" ]]; then
        _last_confirmed_slot="$slot"; _last_confirmed_advance_ts="$now"
        log_info "[self-fence] tracking LOCAL confirmed slot from $slot"
    elif [[ $slot -gt $_last_confirmed_slot ]]; then
        _last_confirmed_slot="$slot"; _last_confirmed_advance_ts="$now"   # advancing → healthy
    else
        frozen=$(( now - _last_confirmed_advance_ts ))
        if [[ $frozen -ge $SELF_FENCE_ISOLATION_SECS ]]; then
            log_warn "[self-fence] LOCAL confirmed slot frozen at $slot for ${frozen}s (>= ${SELF_FENCE_ISOLATION_SECS}s) — ISOLATED from supermajority → give back to unstaked"
            _selffence_demote "self-fence: local confirmed slot frozen ${frozen}s — isolated from supermajority"
            return 0
        fi
        log_info "[self-fence] LOCAL confirmed slot not advancing (${frozen}s/${SELF_FENCE_ISOLATION_SECS}s) at $slot"
    fi

    # (2) Optional: LOCAL getHealth "behind by >N". LOCAL only; a non-answer is ignored, never isolation.
    if [[ "${SELF_FENCE_MAX_BEHIND:-0}" =~ ^[0-9]+$ && $SELF_FENCE_MAX_BEHIND -gt 0 ]]; then
        health_result=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' 2>/dev/null)
        if [[ -n "$health_result" ]]; then
            behind=$(echo "$health_result" | jq -r '.error.data.numSlotsBehind // empty' 2>/dev/null)
            if [[ "$behind" =~ ^[0-9]+$ && $behind -gt $SELF_FENCE_MAX_BEHIND ]]; then
                log_warn "[self-fence] LOCAL getHealth behind by ${behind} slots (> ${SELF_FENCE_MAX_BEHIND}) — partial partition → give back to unstaked"
                _selffence_demote "self-fence: local getHealth behind ${behind} slots (> ${SELF_FENCE_MAX_BEHIND}) — isolated from supermajority"
                return 0
            fi
        fi
    fi

    # (3) N6 own-vote-lag — "can I BE HEARD?" (egress-only partition). ONE LOCAL getVoteAccounts at
    #     commitment=processed (N8: own lastVote AND cluster-max from the SAME payload — no cross-call
    #     skew). LOCAL only — NEVER T2/T3 (the egress is exactly what's broken). VOTE_PUBKEY is
    #     mandatory on the standby, so this sub-check is armed whenever the SLOTS/SECS knobs are > 0.
    #     "Cannot determine" (own/cluster lastVote unreadable) = no-signal: HOLD the timer as-is —
    #     a blip must not cancel a real growing lag, and cannot fire on its own (demote only on a
    #     readable over-threshold lag = positive local evidence).
    if [[ -n "$VOTE_PUBKEY" \
          && "${SELF_FENCE_VOTE_LAG_SLOTS:-0}" =~ ^[0-9]+$ && $SELF_FENCE_VOTE_LAG_SLOTS -gt 0 \
          && "${SELF_FENCE_VOTE_LAG_SECS:-0}" =~ ^[0-9]+$ && $SELF_FENCE_VOTE_LAG_SECS -gt 0 ]]; then
        own_sample=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts","params":[{"commitment":"processed"}]}' 2>/dev/null)
        own_lv=$(echo "$own_sample" | jq -r --arg vote "$VOTE_PUBKEY" '(.result.current + .result.delinquent)[]? | select(.votePubkey == $vote) | .lastVote // empty' 2>/dev/null | head -1)
        cluster_max=$(echo "$own_sample" | jq -r '[(.result.current + .result.delinquent)[]? | .lastVote] | map(numbers) | max // empty' 2>/dev/null)
        if [[ -n "$own_lv" && "$own_lv" =~ ^[0-9]+$ && -n "$cluster_max" && "$cluster_max" =~ ^[0-9]+$ ]]; then
            vlag=$(( cluster_max - own_lv )); [[ $vlag -lt 0 ]] && vlag=0
            # v0.6.9 (H3): restart continuity for N6 — still over threshold on the first read after a
            # restore (with the restored healthy baseline) → inherit the persisted sustain clock.
            if [[ ${_selffence_votelag_restore_pending:-0} -eq 1 ]]; then
                _selffence_votelag_restore_pending=0
                if [[ $vlag -gt $SELF_FENCE_VOTE_LAG_SLOTS && -n "$_selffence_votelag_baseline" ]]; then
                    _selffence_votelag_since=$_selffence_restored_votelag_since
                    log_warn "[self-fence] own-vote lag still over threshold (${vlag} slots) across the monitor restart — sustain timer backdated $(( now - _selffence_votelag_since ))s (v0.6.9 H3)"
                fi
            fi
            if [[ $vlag -le $SELF_FENCE_VOTE_LAG_SLOTS ]]; then
                # Voting normally → healthy baseline; B2 hysteresis: clear the sustain timer only after
                # SELF_FENCE_VOTE_LAG_RESET_CYCLES CONSECUTIVE healthy cycles (a flapping egress must
                # not zero an accumulating timer with a single burst dip).
                _selffence_votelag_baseline=1
                [[ $_selffence_votelag_healthy -lt $SELF_FENCE_VOTE_LAG_RESET_CYCLES ]] && _selffence_votelag_healthy=$(( _selffence_votelag_healthy + 1 ))
                [[ $_selffence_votelag_healthy -ge $SELF_FENCE_VOTE_LAG_RESET_CYCLES ]] && _selffence_votelag_since=0
            elif [[ -n "$_selffence_votelag_baseline" ]]; then
                # Over threshold AND a healthy baseline exists (not fresh-start/catch-up) → time it.
                _selffence_votelag_healthy=0
                [[ $_selffence_votelag_since -eq 0 ]] && _selffence_votelag_since=$now
                vlsust=$(( now - _selffence_votelag_since ))
                if [[ $vlsust -ge $SELF_FENCE_VOTE_LAG_SECS ]]; then
                    log_warn "[self-fence] OWN vote lagging cluster-max by ${vlag} slots (> ${SELF_FENCE_VOTE_LAG_SLOTS}) for ${vlsust}s (>= ${SELF_FENCE_VOTE_LAG_SECS}s) while staked — votes not landing (egress isolation) → give back to unstaked"
                    _selffence_demote "self-fence: own votes not landing (lag ${vlag} slots, ${vlsust}s) — egress isolation"
                    return 0
                fi
                log_info "[self-fence] OWN vote lag ${vlag} slots (> ${SELF_FENCE_VOTE_LAG_SLOTS}) sustained ${vlsust}s/${SELF_FENCE_VOTE_LAG_SECS}s — counting toward egress-isolation self-fence"
            fi
            # else: over threshold but NO healthy baseline yet (fresh start / catching up) → do not arm.
        fi
        # own/cluster lastVote unreadable → cannot compute lag this cycle; HOLD the timer as-is
        # (fail toward staying staked — positive evidence only; see the header rules).
    fi

    return 1
}

# ========================= COLLISION DETECTOR (v0.6.9 M5) ======================
# DETECTION-ONLY: once two nodes hold the staked identity, none of the existing gates can see it —
# the holder reads "not delinquent" (the other node's votes land on the SAME vote account), N6 sees a
# fresh own lastVote (same account again), and the spare holds by design. This check pages the human;
# it must NEVER demote:
#   - Deciding the LOSER under a real collision is v0.7 (lease/witness) territory — an auto-demote
#     keyed on gossip would be a false-positive availability hazard, and a WRONG loser choice on both
#     nodes simultaneously is worse than the collision (both demote = full outage, or both re-take).
#   - Staked CRDS entries linger ~48h and flap under a genuine two-publisher fight, so the check
#     compares ENDPOINTS (full ip:port; presence alone means nothing) and requires 2 CONSECUTIVE
#     strikes before paging (gossip flap tolerance).
# FAILURE DIRECTION: ambiguity (any unreadable input) counts neither way — no page on garbage, no
# clearing of real evidence; a wrong page costs one 🚨 message, never an identity change.
check_identity_collision() {
    # Only while STAKED (caller gates too — belt and suspenders; a non-holder cannot collide).
    [[ -n "$STAKED_PUBKEY" && "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] || return 0
    local now; now=$(date +%s)
    [[ $(( now - _last_collision_check )) -ge ${COLLISION_CHECK_INTERVAL:-60} ]] || return 0
    _last_collision_check=$now

    # Our OWN gossip endpoint — the LOCAL view of our own (staked) entry. LOCAL is authoritative for
    # self (the node keeps re-publishing its own ContactInfo).
    local own_ep
    own_ep=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null \
        | jq -r --arg pk "$STAKED_PUBKEY" '.result[]? | select(.pubkey == $pk) | .gossip // empty' 2>/dev/null | head -1)
    if [[ -z "$own_ep" ]]; then
        log_info "[collision] cannot read our own gossip endpoint (LOCAL) — cannot compare this cycle (strikes held at ${_collision_strikes})"
        return 0
    fi

    # External vantages (T2 → T3): where does the cluster say the staked pubkey lives?
    local rpc cluster_info ext_ep mismatch_ep="" saw_self=""
    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        [[ -z "$rpc" ]] && continue
        cluster_info=$(curl -s -m 10 "$rpc" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null) || continue
        echo "$cluster_info" | jq -e '.result' &>/dev/null || continue
        ext_ep=$(echo "$cluster_info" | jq -r --arg pk "$STAKED_PUBKEY" '.result[]? | select(.pubkey == $pk) | .gossip // empty' 2>/dev/null | head -1)
        [[ -z "$ext_ep" ]] && continue
        if [[ "$ext_ep" != "$own_ep" ]]; then mismatch_ep="$ext_ep"; else saw_self=1; fi
    done

    if [[ -n "$mismatch_ep" ]]; then
        _collision_strikes=$(( _collision_strikes + 1 ))
        log_warn "[collision] staked identity advertised at NON-SELF endpoint ${mismatch_ep} (we are ${own_ep}) — strike ${_collision_strikes}/2"
        if [[ $_collision_strikes -ge 2 ]]; then
            _collision_strikes=2   # cap; keeps re-paging through the throttle while the condition persists
            if [[ $(( now - _last_collision_alert )) -ge $ALERT_THROTTLE ]]; then
                alert "Staked identity is advertised in gossip at ${mismatch_ep} while THIS node (${own_ep}) also holds it — two holders may be voting the same identity. NO automatic action taken (resolution is human — see the manual's 'Emergency: Split-Brain'). Verify which node should hold staked and demote the other NOW." "$STAKED_PUBKEY" "STAKED IDENTITY SEEN ELSEWHERE (possible collision) 🚨"
                _last_collision_alert=$now
            fi
        fi
    elif [[ -n "$saw_self" ]]; then
        # Positive self-match on an external vantage → genuinely clear; reset the strike streak.
        [[ $_collision_strikes -gt 0 ]] && log_info "[collision] external gossip shows our own endpoint again — strikes cleared"
        _collision_strikes=0
    else
        log_info "[collision] no external vantage answered with a staked entry — cannot compare this cycle (strikes held at ${_collision_strikes})"
    fi
    return 0
}

# ========================= AUTO-DETECT ========================================

# Full, untruncated validator argv. `systemctl status | grep` truncates long lines
# (validator command lines are huge) and misses flags hidden inside a wrapper ExecStart.
# Primary source: the live process cmdline via /proc (NUL-delimited, never truncated).
_validator_args_cache=""
get_validator_args() {
    [[ -n "$_validator_args_cache" ]] && { printf '%s' "$_validator_args_cache"; return; }
    local args="" pid=""
    pid=$(pgrep -x agave-validator 2>/dev/null | head -1)
    [[ -z "$pid" && "$VALIDATOR_TYPE" == "frankendancer" ]] && pid=$(pgrep -x fdctl 2>/dev/null | head -1)
    [[ -z "$pid" ]] && pid=$(pgrep -x solana-validator 2>/dev/null | head -1)
    if [[ -n "$pid" && -r "/proc/$pid/cmdline" ]]; then
        args=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    fi
    # Fallback: systemd unit ExecStart (full, but misses flags set inside a wrapper script).
    [[ -z "$args" ]] && args=$(systemctl show "${VALIDATOR_SERVICE:-solana}" -p ExecStart --value 2>/dev/null)
    _validator_args_cache="$args"
    printf '%s' "$args"
}

# Extract a flag value (handles "--flag val" and "--flag=val") from the validator argv.
_extract_arg() { sed -nE "s/.*$1[[:space:]=]+([^[:space:]]+).*/\1/p" <<<"$2" | head -1; }

detect_ledger_path() {
    [[ -n "$LEDGER_PATH" ]] && return
    LEDGER_PATH=$(_extract_arg '--ledger' "$(get_validator_args)")
    [[ -z "$LEDGER_PATH" ]] && { log_error "Cannot auto-detect ledger — set LEDGER_PATH in failover-standby.env"; exit 1; }
    log_info "Ledger: $LEDGER_PATH (auto-detected)"
}

# ========================= NUMERIC CONFIG VALIDATION (v0.6.5 F4) ===============
# Bash arithmetic treats a non-numeric value (e.g. "abc", "10s") as 0, which would silently collapse
# a delay/interval/threshold. Validate every numeric knob at startup: require ^[0-9]+$, normalize via
# 10# (so a leading-zero value isn't parsed as octal), and enforce a sane minimum — fail loudly
# otherwise. $1=var name, $2=min. Writes the normalized decimal back into the named variable.
_validate_numeric() {
    local name="$1" min="$2" val="${!1}"
    [[ "$val" =~ ^[0-9]+$ ]] || { log_error "Bad ${name}: require a non-negative integer (got '${val}')"; exit 1; }
    val=$((10#$val))
    [[ $val -ge $min ]] || { log_error "Bad ${name}: require an integer >= ${min} (got ${val})"; exit 1; }
    printf -v "$name" '%s' "$val"
}

# Validate the timing/threshold knobs not already covered by the window / vote-liveness relationship
# checks, then assert TAKEOVER_DELAY >= VOTE_LIVENESS_MIN_INTERVAL (with vote-liveness on) so the
# second lastVote sample is reachable within the delay. Assumes VOTE_LIVENESS_MIN_INTERVAL is already
# normalized (the vote-liveness block runs first).
validate_numeric_config() {
    _validate_numeric CHECK_INTERVAL 1
    _validate_numeric TURBO_INTERVAL 1
    _validate_numeric CONNECTIVITY_TIMEOUT 1
    _validate_numeric DELINQUENCY_RETRIES 1
    _validate_numeric TAKEOVER_DELAY 0
    _validate_numeric TAKEOVER_COOLDOWN 0
    _validate_numeric TAKEOVER_STARVATION_ALERT_SECS 0     # v0.7 (B3 s4 rework): starvation-page threshold (0 = off, drift-announced)
    _validate_numeric EXTERNAL_CONFIRM_THROTTLE 0
    _validate_numeric MAX_DELINQUENT_SLOTS 0
    _validate_numeric LOCAL_HEALTH_MAX_BEHIND 0
    _validate_numeric EXPECTED_PRIMARY_SELF_FENCE_SECS 0   # v0.6.6 (N1): cross-node timing safety
    _validate_numeric SELF_FENCE_MARGIN_SECS 0             # v0.6.6 (N1): cross-node timing safety
    _validate_numeric EXPECTED_PRIMARY_VOTE_LAG_SLOTS 0    # v0.6.8 (B2): reference for the EPSILON<<band assert
    _validate_numeric FASTPATH_CONFIRM_SAMPLES 1           # v0.6.8 (Option A): consecutive corroborated cycles
    _validate_numeric FASTPATH_STAGGER_SECS 0              # v0.6.8 (Option A): per-node stagger floor
    _validate_numeric VOTE_LIVENESS_MIN_SPAN 0             # v0.7 (B3 s4, ratified): episodic observation-span floor behind a FROZEN take (0 = disabled, drift-announced)
    _validate_numeric ALPENGLOW_GATE_CHECK_HOURS 0         # v0.7 (pre-Block-4, №9): tripwire probe cadence in hours (0 = off, drift-announced)
    _validate_numeric HEARTBEAT_INTERVAL 1
    _validate_numeric HEARTBEAT_PING_INTERVAL 1
    _validate_numeric LOG_MAX_SIZE 1
    if [[ "$VOTE_LIVENESS_VERIFY" == "true" && $TAKEOVER_DELAY -lt $VOTE_LIVENESS_MIN_INTERVAL ]]; then
        log_error "TAKEOVER_DELAY ($TAKEOVER_DELAY) must be >= VOTE_LIVENESS_MIN_INTERVAL ($VOTE_LIVENESS_MIN_INTERVAL) so the liveness 2nd sample is reachable within the takeover delay"
        exit 1
    fi
    # v0.6.8 (B2): EPSILON << PRIMARY self-fence band. The liveness "voting" threshold (EPSILON slots) must
    # sit far below the PRIMARY's SELF_FENCE_VOTE_LAG_SLOTS band, so a holder still landing votes inside its
    # own self-fence band is reliably seen here as "voting" → BLOCK (the coupling that keeps the
    # wedged-but-alive case safe — Audit-1 B7). Require EPSILON <= band/4. Skip when the reference is 0.
    if [[ "$VOTE_LIVENESS_VERIFY" == "true" && $EXPECTED_PRIMARY_VOTE_LAG_SLOTS -gt 0 && $(( VOTE_LIVENESS_EPSILON * 4 )) -gt $EXPECTED_PRIMARY_VOTE_LAG_SLOTS ]]; then
        log_error "VOTE_LIVENESS_EPSILON ($VOTE_LIVENESS_EPSILON) must be << the PRIMARY self-fence band EXPECTED_PRIMARY_VOTE_LAG_SLOTS ($EXPECTED_PRIMARY_VOTE_LAG_SLOTS) — require EPSILON <= band/4 so a still-voting holder reads as VOTING (anti wedged-but-alive). Lower EPSILON or raise the band."
        exit 1
    fi
    # v0.6.9 (H4/H1): the take/give-back admin-socket timeout is used even with the self-fence off, so
    # validate it unconditionally (>= the read path's 8s — same rule as the primary's B1).
    [[ "$SETIDENTITY_TIMEOUT" =~ ^[0-9]+$ && $((10#$SETIDENTITY_TIMEOUT)) -ge 8 ]] \
      || { log_error "Bad SETIDENTITY_TIMEOUT: require an integer >= 8 seconds (got ${SETIDENTITY_TIMEOUT})"; exit 1; }
    SETIDENTITY_TIMEOUT=$((10#$SETIDENTITY_TIMEOUT))
    _validate_numeric HARD_STOP_REVERIFY_SECS 0                # v0.6.9 (H2): hard-stop re-verify delay (0 = immediate re-check only)
    _validate_numeric SELF_FENCE_RETAKE_COOLDOWN 0             # v0.6.9 (H1.3): 0 = no re-take lockout (NOT recommended)
    _validate_numeric COLLISION_CHECK_INTERVAL 1               # v0.6.9 (M5): collision-detector cadence
    _validate_numeric STATE_MAX_AGE_SECS 0                     # v0.6.9 (H3): baseline-restore freshness gate (0 = never restore)
    _validate_numeric STARTUP_STAKED_UNREACHABLE_ALERT_SECS 1  # v0.6.9 (H3): startup staked-unreachable page threshold
    # v0.6.9 (H1): promoted-holder self-fence knobs (ported from the primary's startup validation;
    # placed here so the startup-seam extraction used by the test-suite stays minimal). Only checked
    # with the fence armed; a bad value must not boot half-fenced.
    if [[ "$STANDBY_SELF_FENCE" == "true" ]]; then
        [[ "$SELF_FENCE_ISOLATION_SECS" =~ ^[0-9]+$ && $((10#$SELF_FENCE_ISOLATION_SECS)) -ge 5 ]] \
          || { log_error "Bad SELF_FENCE_ISOLATION_SECS: require an integer >= 5 (got ${SELF_FENCE_ISOLATION_SECS})"; exit 1; }
        SELF_FENCE_ISOLATION_SECS=$((10#$SELF_FENCE_ISOLATION_SECS))
        _validate_numeric SELF_FENCE_MAX_BEHIND 0              # 0 = getHealth demote off
        _validate_numeric SELF_FENCE_NOANSWER_SECS 0           # 0 = no-answer sub-check off
        _validate_numeric SELF_FENCE_VOTE_LAG_SLOTS 0          # 0 = N6 off
        _validate_numeric SELF_FENCE_VOTE_LAG_SECS 0           # 0 = N6 off
        [[ "$SELF_FENCE_VOTE_LAG_RESET_CYCLES" =~ ^[0-9]+$ && $((10#$SELF_FENCE_VOTE_LAG_RESET_CYCLES)) -ge 2 ]] \
          || { log_error "Bad SELF_FENCE_VOTE_LAG_RESET_CYCLES: require an integer >= 2 (1/0 disable the flap hysteresis) (got ${SELF_FENCE_VOTE_LAG_RESET_CYCLES})"; exit 1; }
        SELF_FENCE_VOTE_LAG_RESET_CYCLES=$((10#$SELF_FENCE_VOTE_LAG_RESET_CYCLES))
    fi
}

# v0.6.9 (M8): normalize an RPC URL for the vantage-independence comparison (trim trailing slashes).
_norm_rpc_url() { local u="$1"; while [[ "$u" == */ ]]; do u="${u%/}"; done; printf '%s' "$u"; }

# ========================= SAFETY-CONFIG DRIFT ANNOUNCEMENT (v0.7 Block 3, slice 3.5) ==========
# "We shipped ε=0" and "the fleet runs ε=0" are DIFFERENT claims: an env written by an older
# installer (installers ≤ v0.6.10 wrote VOTE_LIVENESS_EPSILON=2) silently overrides a newer
# daemon's stricter default after an in-place upgrade — the same class as the Unknown-identity and
# sticky-default incidents: config silently diverging from THIS version's intent. The fix is
# VISIBILITY, not force: at every startup, compare the critical safety knobs' EFFECTIVE values
# against THIS version's shipped defaults and, when the env overrides one in the LESS STRICT
# direction, say so — one log_warn per drifted knob, naming the knob, the env value, this
# version's default, and how to align. NEVER fatal, NEVER silently overriding, just never
# invisible. Equal-to-default or STRICTER: silent. Unset: silent (after sourcing, "env set the
# default" and "env didn't set it" are indistinguishable — by design that doesn't matter here:
# equal is silent either way, and silence is the healthy state — no drift, no startup noise).
# INVARIANT(announce-only): this section may ONLY log_warn — it must never mutate a knob, never
# exit, and never gate a code path (forcing would silently break rollback and operator intent).
# EXCLUDED (already fatal-or-page elsewhere — do NOT duplicate): PRIMARY_SELF_FENCE /
# STANDBY_SELF_FENCE=false (loud unfenced warnings + banner) and VOTE_LIVENESS_VERIFY=false
# (refuses to start unless ALLOW_UNFENCED_TAKEOVER=true explicitly accepts it).
#
# One knob: $1=name, $2=THIS version's shipped default, $3=strictness direction, $4=one-line
# consequence of running laxer. Directions (bash-3.2-safe: NO associative arrays — a flat
# per-daemon call table below drives this): low = lower-is-stricter (laxer when value > default);
# high = higher-is-stricter (laxer when value < default); low0 = lower-is-stricter BUT 0 disables
# the sub-check entirely, so 0 is the LAXEST value (distinct wording); bool = true-is-stricter
# (laxer when set non-empty and not "true" — the runtime gates read ${KNOB:-true}, so an EMPTY
# value behaves as true = strict = silent). Numeric-safe: a non-numeric value is SKIPPED here
# (startup validation elsewhere owns rejection — this must never add a second failure mode), and
# compared via 10# so a leading-zero value can't read as octal.
_drift_check() {
    local name="$1" def="$2" dir="$3" why="$4" val="${!1}" lax=0
    if [[ "$dir" == "bool" ]]; then
        [[ -n "$val" && "$val" != "true" ]] && lax=1
    else
        [[ "$val" =~ ^[0-9]+$ ]] || return 0
        val=$((10#$val))
        case "$dir" in
            low)  [[ $val -gt $((10#$def)) ]] && lax=1 ;;
            high) [[ $val -lt $((10#$def)) ]] && lax=1 ;;
            low0) if [[ $val -eq 0 ]]; then lax=2; elif [[ $val -gt $((10#$def)) ]]; then lax=1; fi ;;
            high0) if [[ $val -eq 0 ]]; then lax=2; elif [[ $val -lt $((10#$def)) ]]; then lax=1; fi ;;
        esac
    fi
    if [[ $lax -eq 2 ]]; then
        log_warn "[config-drift] ${name}=0 DISABLES this sub-check entirely — the LAXEST possible setting (this version's default: ${def}) — ${why}; align: set ${name}=${def} in ${CONFIG_FILE} (or delete the line) and restart"
    elif [[ $lax -eq 1 ]]; then
        log_warn "[config-drift] ${name}=${val} is laxer than this version's default ${def} — ${why}; align: set ${name}=${def} in ${CONFIG_FILE} (or delete the line) and restart"
    fi
    return 0
}

# Called ONCE from startup_checks — AFTER the env is sourced and the numeric validation/
# normalization passes ran (a knob those passes reject never reaches here) and BEFORE any later
# startup gate can exit (e.g. the STANDBY's M9 cross-node timing enforcement): a laxer knob is
# announced even on a boot that then refuses, so the operator sees the drift next to the refusal.
announce_config_drift() {
    # ── [config-drift] shared safety-knob table — BYTE-IDENTICAL in both daemons (test_config_drift) ──
    _drift_check VOTE_LIVENESS_EPSILON 0 low "a still-voting holder advancing 1..ε slots reads FROZEN → a spare can take under a LIVE holder (double-sign)"
    _drift_check VOTE_LIVENESS_MIN_INTERVAL 10 high "a shorter sample pair gives a slow voter less time to show life → false FROZEN reads"
    _drift_check VOTE_LIVENESS_MIN_SPAN 40 high0 "a FROZEN-based take can rest on a shorter observed span this episode — a late-observed episode can take on ~one sample interval of observed silence"
    _drift_check SELF_FENCE_ISOLATION_SECS 30 low "an isolated holder keeps voting longer before self-fencing → erodes the relinquish-before-takeover margin"
    _drift_check SELF_FENCE_NOANSWER_SECS 30 low0 "a silent LOCAL RPC leaves the staked identity voting longer before the demote"
    _drift_check SELF_FENCE_VOTE_LAG_SLOTS 32 low0 "an egress-partitioned holder demotes later and can lose the relinquish-first race against a spare's takeover"
    _drift_check SELF_FENCE_VOTE_LAG_SECS 20 low0 "an egress-partitioned holder demotes later and can lose the relinquish-first race against a spare's takeover"
    _drift_check SELF_FENCE_MAX_BEHIND 150 low0 "a far-behind holder keeps its staked identity longer before the getHealth demote fires"
    _drift_check SELF_FENCE_HARD_STOP true bool "a wedged demote becomes alert-only — the staked identity can keep voting through it (the exact double-sign gap the hard-stop closes)"
    _drift_check ALPENGLOW_GATE_CHECK_HOURS 6 low0 "the Alpenglow activation tripwire probes less often — or never: on activation set-identity requires a vote-history file and the observation model changes; the 4.2 audit must re-run"
    # ── [config-drift] end shared table ──
    # ── [config-drift] role-specific safety knobs ──
    _drift_check SELF_FENCE_RETAKE_COOLDOWN 600 high0 "after a self-fence demote this node can re-take the identity it JUST dropped sooner (that account WILL look delinquent+frozen — every normal gate would pass)"
    _drift_check EXPECTED_PRIMARY_SELF_FENCE_SECS 30 high "understates the PRIMARY's relinquish worst case → the cross-node takeover-delay floor computes too low"
    _drift_check SELF_FENCE_MARGIN_SECS 30 high "shrinks the cross-node safety margin → the takeover-delay floor computes too low"
    _drift_check TAKEOVER_STARVATION_ALERT_SECS 300 low0 "a silently-held takeover episode (blindness/flip/floor holds) would page later — or never"
}

# v0.6.6 (N1): cross-node fail-over timing safety. The PRIMARY must self-fence (relinquish the staked
# identity) BEFORE any spare can take it; otherwise both hold staked across a partition heal →
# double-sign. This script cannot read the PRIMARY's config, so this is SEMI-enforcement: warn loudly
# (never fatal — refusing to start would leave the node unmonitored, the F2 philosophy) when this
# node's TAKEOVER_DELAY is not at least the PRIMARY self-fence worst case + the cross-node margin.
# Assumes the three knobs are already normalized to base-10 ints (validate_numeric_config ran first).
# Returns 0 if safe, 1 if unsafe (after emitting the warning + alert_warn).
check_crossnode_timing_safety() {
    # v0.6.9 (B2): ROLE-AWARE floor. A STANDBY (the FIRST spare) need only outwait the PRIMARY's
    # self-fence worst case (EXPECTED_PRIMARY_SELF_FENCE_SECS + margin). A BACKUP (a LATER spare) must
    # ALSO outwait the STANDBY's take becoming externally VISIBLE on T2/T3 — otherwise, when the STANDBY
    # takes at its own (smaller) delay, the BACKUP can confirm the SAME delinquency and TAKE before the
    # STANDBY's votes surface externally → two spares holding staked → DOUBLE-SIGN. A BACKUP must clear
    # ALL THREE floors (Phase-B2 F1): BACKUP floor = max(EXPECTED_PRIMARY_SELF_FENCE_SECS + margin,
    # Rule-2 120, STANDBY_TAKEOVER_DELAY + VOTE_LIVENESS_MIN_INTERVAL + SELF_FENCE_MARGIN_SECS). A BACKUP
    # with no positive STANDBY_TAKEOVER_DELAY REFUSES to start (Phase-B2 S-2) — the visibility term is
    # uncomputable, so fail closed rather than boot with a guessed 0 that could understate the floor.
    # Role comes from FAILOVER_ROLE (wizard-written, STANDBY|BACKUP); a legacy env WITHOUT it is DERIVED
    # as BACKUP iff STANDBY_TAKEOVER_DELAY is a smaller positive number than our own TAKEOVER_DELAY (a
    # first spare never outwaits a smaller peer). FAILURE DIRECTION: role AMBIGUITY → the less-strict
    # STANDBY floor, so a legitimate first spare is never falsely refused (fail toward availability); the
    # BACKUP branch itself fails toward the STRICTER floor (fail toward BLOCKING an early take).
    # v0.6.9 (Phase-B2 F2): normalize FAILOVER_ROLE (trim + uppercase) with a PORTABLE tr — a typo'd
    # 'backup' / ' BACKUP ' is honored as the explicit role, not silently derived. NO ${var^^} (bash 3.2
    # cannot parse it). An EMPTY role still falls to derivation (load-bearing: the role-less prod STANDBY
    # must keep booting).
    local _fr; _fr=$(printf '%s' "$FAILOVER_ROLE" | tr -d '[:space:]' | tr 'a-z' 'A-Z')
    _xnode_role="STANDBY"
    if [[ "$_fr" == "BACKUP" ]]; then
        _xnode_role="BACKUP"
    elif [[ "$_fr" != "STANDBY" ]]; then
        local _s=0 _t=0
        [[ "$STANDBY_TAKEOVER_DELAY" =~ ^[0-9]+$ ]] && _s=$((10#$STANDBY_TAKEOVER_DELAY))
        [[ "$TAKEOVER_DELAY" =~ ^[0-9]+$ ]] && _t=$((10#$TAKEOVER_DELAY))
        [[ $_s -gt 0 && $_s -lt $_t ]] && _xnode_role="BACKUP"
    fi
    if [[ "$_xnode_role" == "BACKUP" ]]; then
        # v0.6.9 (Phase-B2 S-2): a BACKUP CANNOT compute its take-visibility floor without the STANDBY's
        # delay. Fail CLOSED — refuse to start rather than boot with a guessed 0 (which would understate
        # the floor and could let the BACKUP take before the STANDBY's votes surface → two-spare
        # double-take). Routes through the same return-1 path enforce_ makes fatal (unless ALLOW_UNSAFE_TIMING).
        if [[ ! "$STANDBY_TAKEOVER_DELAY" =~ ^[0-9]+$ ]] || [[ $((10#$STANDBY_TAKEOVER_DELAY)) -le 0 ]]; then
            _xnode_need=$(( EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS )); [[ 120 -gt $_xnode_need ]] && _xnode_need=120
            _xnode_reason="BACKUP requires STANDBY_TAKEOVER_DELAY set to the STANDBY's TAKEOVER_DELAY — cannot compute the take-visibility floor without it. Set STANDBY_TAKEOVER_DELAY (or re-run the installer)."
            log_warn "⚠️  ⚠️  ⚠️  UNSAFE cross-node timing [BACKUP]: ${_xnode_reason}  ⚠️  ⚠️  ⚠️"
            alert_warn "⚠️ UNSAFE failover timing [BACKUP]: ${_xnode_reason}"
            return 1
        fi
        # v0.6.9 (Phase-B2 F1): a BACKUP must clear ALL THREE floors, not just STANDBY-visibility. The
        # PRIMARY-self-fence term (EXPECTED + margin) was dropped in B2 — a BACKUP that took before the
        # PRIMARY relinquished would double-sign with the PRIMARY. Floor = max(EXPECTED+margin, 120, vis).
        local _std=$((10#$STANDBY_TAKEOVER_DELAY))
        local _vis=$(( _std + VOTE_LIVENESS_MIN_INTERVAL + SELF_FENCE_MARGIN_SECS ))
        _xnode_need=$(( EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS ))
        [[ 120 -gt $_xnode_need ]] && _xnode_need=120
        [[ $_vis -gt $_xnode_need ]] && _xnode_need=$_vis
        _xnode_reason="BACKUP: max(PRIMARY self-fence ${EXPECTED_PRIMARY_SELF_FENCE_SECS}s + margin ${SELF_FENCE_MARGIN_SECS}s, Rule-2 120s, STANDBY take-visibility [STANDBY_TAKEOVER_DELAY ${_std}s + liveness ${VOTE_LIVENESS_MIN_INTERVAL}s + margin ${SELF_FENCE_MARGIN_SECS}s])"
    else
        _xnode_need=$(( EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS ))
        _xnode_reason="STANDBY: PRIMARY self-fence ${EXPECTED_PRIMARY_SELF_FENCE_SECS}s + margin ${SELF_FENCE_MARGIN_SECS}s"
    fi
    if [[ $TAKEOVER_DELAY -lt $_xnode_need ]]; then
        log_warn "⚠️  ⚠️  ⚠️  UNSAFE cross-node timing [${_xnode_role}]: TAKEOVER_DELAY=${TAKEOVER_DELAY}s < ${_xnode_need}s (${_xnode_reason}). A spare taking before the current holder's identity is externally relinquished → DOUBLE-SIGN on partition heal. Raise TAKEOVER_DELAY to >= ${_xnode_need}s.  ⚠️  ⚠️  ⚠️"
        alert_warn "⚠️ UNSAFE failover timing [${_xnode_role}]: TAKEOVER_DELAY=${TAKEOVER_DELAY}s < ${_xnode_need}s (${_xnode_reason}). Double-sign risk on heal — raise TAKEOVER_DELAY."
        return 1
    fi
    log_info "[cross-node] ${_xnode_role}: TAKEOVER_DELAY=${TAKEOVER_DELAY}s >= ${_xnode_need}s (${_xnode_reason}) — holder relinquishes before this node takes (safe)"
    return 0
}

# v0.6.9 (M9 + B2): cross-node timing violations are FATAL (opt-out). EXPECTED_PRIMARY_SELF_FENCE_SECS
# is an operator-typed claim with no runtime verification — this one guard is the only thing that can
# bite a hand-edited TAKEOVER_DELAY, so a violation now refuses to start, mirroring the ALLOW_UNFENCED
# double-opt-in pattern. The floor is ROLE-AWARE (B2): a BACKUP must outwait the STANDBY's take becoming
# externally visible, not just the PRIMARY's self-fence (see check_crossnode_timing_safety). The message
# text uses the floor/reason that check_ actually computed for THIS role. ALLOW_UNSAFE_TIMING=true
# (lab/testing ONLY) restores the old warn-and-continue.
# FAILURE DIRECTION: refuse-to-start — a spare that would take before the holder relinquishes is more
# dangerous than an unmonitored spare (the take is the dangerous direction; monitoring gaps only cost
# availability). The installers clamp to the safe floor, so wizard-generated configs never hit this.
enforce_crossnode_timing_safety() {
    if check_crossnode_timing_safety; then
        return 0
    fi
    if [[ "${ALLOW_UNSAFE_TIMING:-false}" == "true" ]]; then
        log_warn "⚠️ ALLOW_UNSAFE_TIMING=true — continuing DESPITE the unsafe cross-node timing above (lab/testing only; double-sign risk on heal)"
        alert_warn "⚠️ UNSAFE cross-node timing ACCEPTED via ALLOW_UNSAFE_TIMING=true [${_xnode_role}]: TAKEOVER_DELAY=${TAKEOVER_DELAY}s < ${_xnode_need}s. Lab/testing only."
        return 0
    fi
    log_error "UNSAFE cross-node timing is FATAL (v0.6.9 M9/B2) [${_xnode_role}]: TAKEOVER_DELAY=${TAKEOVER_DELAY}s < ${_xnode_need}s (${_xnode_reason}). Raise TAKEOVER_DELAY, or set ALLOW_UNSAFE_TIMING=true (lab/testing ONLY)."
    alert "TAKEOVER_DELAY=${TAKEOVER_DELAY}s < ${_xnode_need}s (${_xnode_reason}) — refusing to start (double-sign risk on heal). Raise TAKEOVER_DELAY or set ALLOW_UNSAFE_TIMING=true (lab only)." "$STAKED_PUBKEY" "UNSAFE CROSS-NODE TIMING — REFUSING TO START 🚨"
    exit 1
}

# ========================= STARTUP ============================================

startup_checks() {
    echo "============================================="
    echo " Solana STANDBY Failover v0.6.10 (3-TIER RPC)"
    echo "============================================="

    if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
        command -v fdctl &>/dev/null || { log_error "fdctl not found"; exit 1; }
        [[ -z "$CONFIG_TOML" ]] && { log_error "CONFIG_TOML required"; exit 1; }
    else
        [[ -f "$SOLANA_PATH/agave-validator" ]] || { log_error "agave-validator not found"; exit 1; }
        [[ -f "$SOLANA_PATH/solana-keygen" ]] || { log_error "solana-keygen not found"; exit 1; }
        detect_ledger_path
    fi
    command -v jq &>/dev/null || { log_error "jq required"; exit 1; }

    STAKED_PUBKEY=$(validate_keypair_file "$STAKED_KEYPAIR" "Staked") || exit 1
    UNSTAKED_PUBKEY=$(validate_keypair_file "$UNSTAKED_KEYPAIR" "Unstaked") || exit 1
    [[ -n "$STAKED_PUBKEY_OVERRIDE" ]] && { STAKED_PUBKEY="$STAKED_PUBKEY_OVERRIDE"; log_info "Staked pubkey override: $STAKED_PUBKEY"; }
    [[ "$STAKED_PUBKEY" == "$UNSTAKED_PUBKEY" ]] && { log_error "Same pubkeys!"; exit 1; }
    # v0.7 (pre-Block-4, №3): G2 (addendum §2.4) and the Option-A fast path both read "a live
    # publisher holds this unstaked key on box X" as "box X cannot sign staked votes" — sound only
    # while each unstaked key belongs to ONE host, so a shared key is refused here, same fatal
    # class as the staked==unstaked refusal above. PRIMARY_UNSTAKED_PUBKEY is space-separated →
    # membership, not whole-string equality.
    local _own_pk
    # shellcheck disable=SC2086
    for _own_pk in $PRIMARY_UNSTAKED_PUBKEY; do
        [[ "$UNSTAKED_PUBKEY" == "$_own_pk" ]] && { log_error "FATAL: our own UNSTAKED pubkey (${UNSTAKED_PUBKEY}) is listed in PRIMARY_UNSTAKED_PUBKEY — a shared unstaked pubkey across nodes breaks the relinquish-proof fence; each node needs its OWN unstaked keypair (README already requires it; now enforced)."; exit 1; }
    done
    [[ -z "$VOTE_PUBKEY" ]] && { log_error "VOTE_PUBKEY required"; exit 1; }

    # v0.6.5 (F2): the validator's STARTUP --identity must be the UNSTAKED keypair so a
    # solana.service restart (Restart=always) fails safe to NOT voting. If the running validator was
    # started on the STAKED key, a restart boots it VOTING even while demoted → double-sign-on-restart.
    # Page URGENT but do NOT refuse to start: refusing would leave the node unmonitored; a loud,
    # persistent alert is safer. (agave only — frankendancer takes its identity from CONFIG_TOML.)
    if [[ "$VALIDATOR_TYPE" != "frankendancer" ]]; then
        local startup_id_path startup_id_pub
        startup_id_path=$(_extract_arg '--identity' "$(get_validator_args)")
        if [[ -n "$startup_id_path" && -f "$startup_id_path" ]]; then
            startup_id_pub=$("$SOLANA_PATH/solana-keygen" pubkey "$startup_id_path" 2>/dev/null) || true
            if [[ -n "$startup_id_pub" && "$startup_id_pub" == "$STAKED_PUBKEY" ]]; then
                log_error "Validator startup --identity resolves to the STAKED key — a restart boots this node VOTING (double-sign-on-restart risk)"
                alert "Validator startup --identity is the STAKED key — a solana.service restart boots this node VOTING even while demoted (double-sign-on-restart). Fix the startup --identity to the unstaked key (Anza identity.json symlink recommended)." "$STAKED_PUBKEY" "STAKED STARTUP IDENTITY 🚨"
            fi
        fi
    fi

    # v0.6.1 (F6): validate sliding-window bounds. THRESHOLD>SIZE makes window_triggered
    # never fire (failover silently disabled); SIZE=0 would trigger on an empty window.
    # Single-line [[ ]] (bash 3.2 rejects backslash continuation inside the brackets); the
    # comparisons use $((10#…)) so a leading-zero value isn't parsed as octal (bash 3.2
    # would throw "value too great for base" on e.g. 08). Regex guards non-numeric first.
    [[ "$DELINQUENCY_WINDOW_SIZE" =~ ^[0-9]+$ && "$DELINQUENCY_WINDOW_THRESHOLD" =~ ^[0-9]+$ && $((10#$DELINQUENCY_WINDOW_THRESHOLD)) -ge 1 && $((10#$DELINQUENCY_WINDOW_SIZE)) -ge $((10#$DELINQUENCY_WINDOW_THRESHOLD)) ]] \
      || { log_error "Bad window config: require 1<=THRESHOLD<=SIZE (got ${DELINQUENCY_WINDOW_THRESHOLD}/${DELINQUENCY_WINDOW_SIZE})"; exit 1; }
    # Normalize to base-10 so later window arithmetic never misreads a leading-zero value.
    DELINQUENCY_WINDOW_SIZE=$((10#$DELINQUENCY_WINDOW_SIZE)); DELINQUENCY_WINDOW_THRESHOLD=$((10#$DELINQUENCY_WINDOW_THRESHOLD))

    # v0.6.2 (C1): validate the vote-liveness knobs — they gate the AUTHORITATIVE anti-double-sign
    # fence, so a typo here must not silently disable it. Octal-safe ($((10#…)), same as F6). Require
    # MIN_INTERVAL > EPSILON so that even at a conservative ~1 slot/s a voting holder advances past
    # EPSILON within the interval (else a live voter could be misread as "frozen" → false ALLOW).
    # MIN_INTERVAL >= 5 gives a sane floor; a huge EPSILON typo forces a huge MIN_INTERVAL, which
    # fails this check at startup rather than disabling the fence.
    [[ "$VOTE_LIVENESS_EPSILON" =~ ^[0-9]+$ && "$VOTE_LIVENESS_MIN_INTERVAL" =~ ^[0-9]+$ && $((10#$VOTE_LIVENESS_MIN_INTERVAL)) -ge 5 && $((10#$VOTE_LIVENESS_MIN_INTERVAL)) -gt $((10#$VOTE_LIVENESS_EPSILON)) ]] \
      || { log_error "Bad vote-liveness config: require EPSILON>=0, MIN_INTERVAL>=5 and MIN_INTERVAL>EPSILON (got eps=${VOTE_LIVENESS_EPSILON} interval=${VOTE_LIVENESS_MIN_INTERVAL})"; exit 1; }
    VOTE_LIVENESS_EPSILON=$((10#$VOTE_LIVENESS_EPSILON)); VOTE_LIVENESS_MIN_INTERVAL=$((10#$VOTE_LIVENESS_MIN_INTERVAL))

    # v0.6.3 (Block 1): vote-liveness is REQUIRED — it is the authoritative split-brain fence.
    # Refuse to start with it disabled unless the operator explicitly accepts an UNFENCED takeover
    # (ALLOW_UNFENCED_TAKEOVER=true). This closes the old "both fences off → silent unfenced
    # takeover with only a warning" hole. Mirrors the F4 auto-reject pattern (fail at startup, loud).
    if [[ "$VOTE_LIVENESS_VERIFY" != "true" ]]; then
        if [[ "${ALLOW_UNFENCED_TAKEOVER:-false}" == "true" ]]; then
            log_warn "⚠️  ⚠️  ⚠️  VOTE_LIVENESS_VERIFY=false AND ALLOW_UNFENCED_TAKEOVER=true — NO split-brain fence; takeover is UNFENCED (double-sign risk)  ⚠️  ⚠️  ⚠️"
        else
            log_error "VOTE_LIVENESS_VERIFY must be true (the authoritative split-brain fence). Refusing to start unfenced — set ALLOW_UNFENCED_TAKEOVER=true ONLY if you accept the double-sign risk."
            exit 1
        fi
    fi

    # v0.6.5 (F3): ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN is deprecated and ignored — it could never
    # deliver an emergency takeover (the authoritative vote-liveness fence also needs T2/T3 to sample
    # lastVote, so both-externals-down always blocks). Warn loudly if it is still set true in an env.
    if [[ "${ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN:-false}" == "true" ]]; then
        log_warn "⚠️ ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN is DEPRECATED and IGNORED (v0.6.5 F3): it cannot force a takeover while the vote-liveness fence needs external RPCs. For a genuine emergency local-only takeover use ALLOW_UNFENCED_TAKEOVER=true + VOTE_LIVENESS_VERIFY=false."
    fi

    # v0.6.9 (M6): GIVE_BACK_MODE=auto was offered by older installers but NEVER implemented — the
    # STAKED branch implements only "manual", so "auto" was a silent no-op the operator believed was
    # armed. Coerce to manual with a loud warning. FAILURE DIRECTION: manual = the holder HOLDS (the
    # documented safe behavior); never an unimplemented silent pathway.
    if [[ "$GIVE_BACK_MODE" == "auto" ]]; then
        log_warn "⚠️ GIVE_BACK_MODE=auto is not implemented — treated as manual (hold after takeover; operator-driven give-back). Fix the env to GIVE_BACK_MODE=\"manual\"."
        alert_warn "⚠️ GIVE_BACK_MODE=auto is not implemented — treated as manual."
        GIVE_BACK_MODE="manual"
    fi

    validate_numeric_config   # v0.6.5 (F4): reject/normalize all remaining numeric knobs + delay assert

    announce_config_drift     # v0.7 (Block 3, slice 3.5): env safety knobs laxer than THIS version's defaults — one line each (visibility, never force; BEFORE the M9 gate so drift is visible next to a timing refusal)

    enforce_crossnode_timing_safety   # v0.6.9 (M9): FATAL on an unsafe TAKEOVER_DELAY unless ALLOW_UNSAFE_TIMING=true (was warn-only in v0.6.6–v0.6.8)

    # v0.6.8 (Option A): validate the fast-path config. Fail-CLOSED (never fatal — F2: keep monitoring):
    # a misconfigured fast-path simply does not fire and the proven v0.6.7 timer governs. The ONE fatal
    # case is watching the STAKED pubkey (would fast-take on the holder's own staked entry = inversion).
    if [[ "$WITNESS_FASTPATH" == "true" ]]; then
        if [[ -z "$PRIMARY_UNSTAKED_PUBKEY" ]]; then
            log_warn "⚠️ WITNESS_FASTPATH=true but PRIMARY_UNSTAKED_PUBKEY is empty — fast-path DISABLED (fail-closed). Set the holder's unstaked pubkey(s) to enable."
        fi
        local _fp_pk
        # shellcheck disable=SC2086
        for _fp_pk in $PRIMARY_UNSTAKED_PUBKEY; do
            [[ "$_fp_pk" == "$STAKED_PUBKEY" ]] && { log_error "FATAL: PRIMARY_UNSTAKED_PUBKEY contains the STAKED pubkey — the fast-path would fast-take on the holder's own staked gossip entry (inversion). Watch the holder's UNSTAKED identity only."; exit 1; }
            [[ "$_fp_pk" =~ ^[1-9A-HJ-NP-Za-km-z]{32,44}$ ]] || log_warn "⚠️ PRIMARY_UNSTAKED_PUBKEY entry '${_fp_pk}' does not look like a base58 pubkey — fast-path will never match it."
        done
        if [[ "$FASTPATH_PEER_RECOVERY_MANUAL" != "true" ]]; then
            log_warn "⚠️ WITNESS_FASTPATH=true but FASTPATH_PEER_RECOVERY_MANUAL!=true — fast-path DISABLED (fail-closed, A4). Affirm ALL staked-capable peers run RECOVERY_MODE=manual, then set it true."
        fi
        if [[ -z "$TIER2_RPC" || -z "$TIER3_RPC" ]]; then
            log_warn "⚠️ WITNESS_FASTPATH needs TWO external RPC vantage points (TIER2 and TIER3) for anti-co-partition corroboration (A6); with one configured the fast-path will never fire."
        fi
        # v0.6.8 (S1): compute + ENFORCE the inter-spare stagger floor (fail-closed on bad config).
        if _fastpath_compute_stagger; then
            [[ $_fastpath_stagger_floor -gt $FASTPATH_STAGGER_SECS ]] && log_warn "[fast-path] effective stagger floor raised to ${_fastpath_stagger_floor}s (= TAKEOVER_DELAY ${TAKEOVER_DELAY} - STANDBY_TAKEOVER_DELAY ${STANDBY_TAKEOVER_DELAY}); configured FASTPATH_STAGGER_SECS=${FASTPATH_STAGGER_SECS} was below the required floor — a BACKUP cannot fast-take ahead of the STANDBY"
        else
            log_warn "⚠️ ${_fastpath_disabled} — fast-path DISABLED (fail-closed). Set STANDBY_TAKEOVER_DELAY to the STANDBY's TAKEOVER_DELAY on EVERY spare (STANDBY and BACKUP)."
            alert_warn "⚠️ Fast-path disabled: ${_fastpath_disabled}. Set STANDBY_TAKEOVER_DELAY = the STANDBY's TAKEOVER_DELAY on every spare."
        fi
    fi

    # v0.6.9 (M8): TIER2/TIER3 vantage-independence. Identical URLs silently void A6 ("two vantages")
    # and the liveness fence's fallback independence. Warn loudly — NOT fatal (single-provider users
    # keep working, loudly) — and force the fast-path OFF: A6 explicitly requires two DISTINCT
    # vantage points. FAILURE DIRECTION: fast-path fail-closed → the proven timer governs.
    if [[ -n "$TIER2_RPC" && -n "$TIER3_RPC" && "$(_norm_rpc_url "$TIER2_RPC")" == "$(_norm_rpc_url "$TIER3_RPC")" ]]; then
        log_warn "⚠️ TIER2_RPC == TIER3_RPC — single vantage point: A6 corroboration and the liveness fallback are no longer independent. Use two DISTINCT providers."
        alert_warn "⚠️ TIER2_RPC == TIER3_RPC — single vantage point. Configure two distinct RPC providers."
        if [[ "$WITNESS_FASTPATH" == "true" ]]; then
            _fastpath_disabled="TIER2_RPC == TIER3_RPC — single vantage (A6 requires two distinct vantage points)"
            log_warn "⚠️ ${_fastpath_disabled} — fast-path DISABLED (fail-closed)."
        fi
    fi

    load_state   # v0.6.1 (F7): restore persisted takeover-cooldown timer (if any); v0.6.9 (H3/H1.3/M10): + self-fence baseline / re-take lockout / legacy-state migration

    # Test tiers
    log_info "Testing RPC tiers..."
    local slot
    slot=$(curl -s -m 5 "$LOCAL_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [[ -n "$slot" ]] && log_info "Tier 1 (LOCAL): OK (slot $slot)" || log_warn "Tier 1 (LOCAL): not ready"

    slot=$(curl -s -m 10 "$TIER2_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [[ -n "$slot" ]] && log_info "Tier 2 (ALCHEMY): OK (slot $slot)" || log_warn "Tier 2 (ALCHEMY): unreachable"

    slot=$(curl -s -m 10 "$TIER3_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [[ -n "$slot" ]] && log_info "Tier 3 (PUBLIC): OK (slot $slot)" || log_warn "Tier 3 (PUBLIC): unreachable"

    # Wait for local validator
    log_info "Waiting for local validator..."
    CURRENT_IDENTITY=""
    local wc=0 _wait_start _wait_alerted=0
    _wait_start=$(date +%s)   # v0.6.9 (H3)
    while [[ -z "$CURRENT_IDENTITY" && "$_running" == "true" ]]; do
        heartbeat_ping   # v0.6.9 (H3): the dead-man's switch must not go dark while we wait here
        CURRENT_IDENTITY=$(get_local_identity 2>/dev/null) || true
        if [[ -z "$CURRENT_IDENTITY" ]]; then
            wc=$((wc+1)); [[ $((wc%10)) -eq 0 ]] && log_warn "Waiting... ($wc)"
            # v0.6.9 (H3): the persisted state says we were STAKED (promoted holder) and the validator
            # has been unreachable since monitor startup — the daemon cannot self-fence/demote, and a
            # BACKUP may confirm delinquency and take over → page URGENT, once. FAILURE DIRECTION:
            # toward paging the operator (holder path); a false page costs one 🚨.
            if [[ $_wait_alerted -eq 0 && "$_persisted_role" == "staked" \
                  && $(( $(date +%s) - _wait_start )) -ge $STARTUP_STAKED_UNREACHABLE_ALERT_SECS ]]; then
                log_warn "Persisted role STAKED + local validator unreachable ${STARTUP_STAKED_UNREACHABLE_ALERT_SECS}s+ at startup — sending URGENT alert"
                alert "STANDBY was STAKED (promoted holder) at last save + local validator unreachable since monitor startup (>${STARTUP_STAKED_UNREACHABLE_ALERT_SECS}s) — the daemon cannot self-fence/demote; a spare may take over. Intervene (stop the validator or confirm the spare took over)." "$STAKED_PUBKEY" "STANDBY UNREACHABLE WHILE STAKED 🚨"
                _wait_alerted=1
            fi
            sleep 5
        fi
    done
    [[ "$_running" != "true" ]] && exit 0

    echo ""
    echo "  Node:              $NODE_NAME"
    echo "  Role:              STANDBY (hot spare)"
    echo "  Staked:            $STAKED_PUBKEY"
    echo "  Unstaked:          $UNSTAKED_PUBKEY"
    echo "  Current:           $CURRENT_IDENTITY"
    echo "  Vote pubkey:       $VOTE_PUBKEY"
    echo "  ─── Three-Tier RPC ───"
    echo "  Tier 1 (LOCAL):    $LOCAL_RPC (own health, every ${CHECK_INTERVAL}s / turbo: ${TURBO_INTERVAL}s)"
    echo "  Tier 2 (ALCHEMY):  ${TIER2_RPC:0:55}..."
    echo "  Tier 3 (PUBLIC):   $TIER3_RPC"
    echo "  ─── Thresholds ───"
    echo "  Delinq window:     ${DELINQUENCY_WINDOW_THRESHOLD}/${DELINQUENCY_WINDOW_SIZE} (trigger/window)"
    echo "  Takeover delay:    ${TAKEOVER_DELAY}s (role ${_xnode_role:-STANDBY}; must be >= ${_xnode_need:-$(( EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS ))}s — ${_xnode_reason:-PRIMARY self-fence + margin})"   # v0.6.9 (B2): role-aware floor (set by enforce_crossnode_timing_safety above)
    echo "  Health max behind: $LOCAL_HEALTH_MAX_BEHIND slots"
    echo "  Gossip verify:     $GOSSIP_VERIFY (advisory only — logs/corroborates, never blocks)"
    if [[ "$WITNESS_FASTPATH" == "true" ]]; then
        local _fp_state="ARMED"
        { [[ -z "$PRIMARY_UNSTAKED_PUBKEY" ]] || [[ "$FASTPATH_PEER_RECOVERY_MANUAL" != "true" ]] || [[ -z "$TIER2_RPC" || -z "$TIER3_RPC" ]]; } && _fp_state="config-incomplete → DISABLED (fail-closed)"
        [[ -n "$_fastpath_disabled" ]] && _fp_state="DISABLED (fail-closed): ${_fastpath_disabled}"
        echo "  Fast-path (A):     ON [$_fp_state] watch='${PRIMARY_UNSTAKED_PUBKEY}' confirm=${FASTPATH_CONFIRM_SAMPLES} stagger-floor=${_fastpath_stagger_floor}s (cfg ${FASTPATH_STAGGER_SECS}s, STANDBY_TAKEOVER_DELAY=${STANDBY_TAKEOVER_DELAY:-unset}) first-spare=${WITNESS_FASTPATH_FIRST_SPARE} manual-recovery=${FASTPATH_PEER_RECOVERY_MANUAL} (skips the timer on a positive flip; gates unchanged)"
    else
        echo "  Fast-path (A):     off (pure v0.6.7 timer behavior)"
    fi
    echo "  Vote-liveness:     $VOTE_LIVENESS_VERIFY (AUTHORITATIVE; ε>${VOTE_LIVENESS_EPSILON} slots / ${VOTE_LIVENESS_MIN_INTERVAL}s)"
    [[ "$VOTE_LIVENESS_VERIFY" != "true" ]] && echo "  ⚠️  UNFENCED TAKEOVER (ALLOW_UNFENCED_TAKEOVER=true) — no split-brain fence"
    # v0.6.9 (H1): Self-fence banner line for the PROMOTED holder, mirroring the primary's (signals
    # armed + hard-stop state) so live-test banners can be checked side-by-side.
    if [[ "$STANDBY_SELF_FENCE" == "true" ]]; then
        echo "  Self-fence:        on (isolation ${SELF_FENCE_ISOLATION_SECS}s; no-answer $([ "$SELF_FENCE_NOANSWER_SECS" -gt 0 ] && echo "${SELF_FENCE_NOANSWER_SECS}s" || echo "off"); vote-lag $([ "$SELF_FENCE_VOTE_LAG_SLOTS" -gt 0 ] && [ "$SELF_FENCE_VOTE_LAG_SECS" -gt 0 ] && echo "${SELF_FENCE_VOTE_LAG_SLOTS}sl/${SELF_FENCE_VOTE_LAG_SECS}s" || echo "off"); getHealth behind > $([ "$SELF_FENCE_MAX_BEHIND" -gt 0 ] && echo "${SELF_FENCE_MAX_BEHIND}" || echo "off"); hard-stop ${SELF_FENCE_HARD_STOP}; re-take lockout ${SELF_FENCE_RETAKE_COOLDOWN}s)"
    else
        echo "  Self-fence:        off (promoted holder holds UNFENCED — pre-v0.6.9 behavior)"
    fi
    echo "  Give-back:         $GIVE_BACK_MODE"
    echo "  DRY RUN:           $DRY_RUN"
    echo ""

    [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] && echo "  ⚠️  WARNING: STANDBY running STAKED! Should be UNSTAKED." && echo ""
    [[ "$DRY_RUN" == "true" ]] && echo "  ⚠️  DRY RUN — no switches" && echo ""

    echo "============================================="

    log_info "STANDBY started. Identity: $CURRENT_IDENTITY"
    if [[ "$DRY_RUN" == "true" ]]; then
        alert_info "🚀 STANDBY v0.6.9 started [DRY_RUN]. <code>${CURRENT_IDENTITY:0:8}...</code>"
    else
        log_warn "⚠️  ⚠️  ⚠️  LIVE MODE — STANDBY will perform real takeover  ⚠️  ⚠️  ⚠️"
        alert_info "🚀 STANDBY v0.6.9 started [LIVE]. <code>${CURRENT_IDENTITY:0:8}...</code>"
    fi
    [[ $STARTUP_GRACE -gt 0 ]] && { log_info "Grace: ${STARTUP_GRACE}s"; sleep "$STARTUP_GRACE"; }
}

display_status() {
    [[ ! -t 1 ]] && return
    local l
    [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] && l="ACTIVE*" || l="STANDBY"
    printf "\r[%s] %s | Chk:%d T1:%d T2:%d T3:%d Takes:%d | %s   " \
        "$l" "${CURRENT_IDENTITY:0:8}..." \
        "$STAT_CHECKS" "$STAT_TIER1_HEALTH" "$STAT_TIER2_CHECKS" "$STAT_TIER3_CHECKS" \
        "$STAT_TAKEOVERS" "$1"
}

# ========================= MAIN LOOP =========================================

startup_checks

# v0.7 (pre-Block-4, №9): tripwire visibility — say at startup whether the gate probe is armed.
if [[ "${ALPENGLOW_GATE_CHECK_HOURS:-0}" =~ ^[0-9]+$ && $((10#$ALPENGLOW_GATE_CHECK_HOURS)) -gt 0 ]]; then
    log_info "[alpenglow] tripwire armed: probing the feature gate every ${ALPENGLOW_GATE_CHECK_HOURS}h"
else
    log_info "[alpenglow] tripwire DISABLED (ALPENGLOW_GATE_CHECK_HOURS=0)"
fi

while $_running; do
    STAT_CHECKS=$((STAT_CHECKS + 1))
    rotate_log
    heartbeat_ping   # v0.6.4: external watchdog ping — top of loop, before any `continue`
    _alpenglow_gate_check   # v0.7 (pre-Block-4, №9): read-only Alpenglow gate probe — self-gates on cadence; top of loop, NEVER inside a takeover/recovery/verdict path (act-then-alert untouched: this network read is nowhere near a mutation)

    CURRENT_IDENTITY=$(get_local_identity 2>/dev/null) || true
    if [[ -z "$CURRENT_IDENTITY" ]]; then
        now_ts=$(date +%s)
        if [[ $(( now_ts - _last_unreachable_alert )) -ge $ALERT_THROTTLE ]]; then
            # v0.6.9 (H1): if the last-known identity was STAKED (we are the promoted holder), the
            # validator is fully wedged (admin RPC down too) so the self-fence demote cannot run — a
            # spare may confirm delinquency + frozen liveness and take over → double-sign on heal.
            # Page URGENT, not warn (ported from the primary's F1 sub-item). FAILURE DIRECTION: page.
            if [[ -n "$STAKED_PUBKEY" && "$_last_known_identity" == "$STAKED_PUBKEY" ]]; then
                log_warn "Local validator unreachable while STAKED (promoted holder) — sending URGENT alert"
                alert "STANDBY holds staked + local validator unreachable — the daemon cannot self-fence/demote; a spare may take over. Intervene (stop the validator or confirm the spare took over)." "$STAKED_PUBKEY" "STANDBY UNREACHABLE WHILE STAKED 🚨"
            else
                log_warn "Local validator unreachable — sending alert"
                alert_warn "⚠️ STANDBY local validator unreachable! Cannot monitor or take over."
            fi
            _last_unreachable_alert=$now_ts
        else
            log_warn "Local validator unreachable"
        fi
        display_status "NO LOCAL"
        sleep "$CHECK_INTERVAL"
        continue
    fi
    _last_unreachable_alert=0
    _last_known_identity="$CURRENT_IDENTITY"   # v0.6.9 (H1): remembered for the staked-unreachable URGENT page above
    flush_pending_alerts   # v0.6.1 (N3): retry any alert that failed to send earlier

    # Recovery from an UNKNOWN-identity episode (paged below): announce once, re-arm the episode.
    if [[ $_unknown_identity_since -gt 0 && ( "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" || "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ) ]]; then
        alert_info "✅ Identity classified again after $(( $(date +%s) - _unknown_identity_since ))s UNKNOWN — protection active"
        _unknown_identity_since=0; _last_unknown_alert=0
    fi
    if [[ "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" ]]; then
        # ======== UNSTAKED (normal): 3-tier monitoring for takeover ========

        # --- Tier 1: Am I healthy enough to take over? ---
        if ! tier1_check_local_health; then
            # Our node isn't ready — alert with throttle
            now_ts=$(date +%s)
            if [[ $(( now_ts - _last_behind_alert )) -ge $ALERT_THROTTLE ]]; then
                alert_warn "⚠️ STANDBY node too far behind or unhealthy! Cannot take over if needed."
                _last_behind_alert=$now_ts
            fi
            display_status "T1:BEHIND"
            sleep "$CHECK_INTERVAL"
            continue
        fi
        _last_behind_alert=0

        # --- LOCAL: Is staked identity delinquent? (FREE, every cycle) ---
        local_check_delinquency
        local_result=$?

        if [[ $local_result -eq 0 ]]; then
            # DELINQUENT detected by LOCAL RPC
            STAT_DELINQUENT_SEEN=$((STAT_DELINQUENT_SEEN + 1))
            window_push 1
            [[ $FIRST_DELINQUENT_TIME -eq 0 ]] && FIRST_DELINQUENT_TIME=$(mono_now)   # v0.7 (Block 3): SAFETY clock (N3 anchor input)

            # Enter turbo mode on first delinquent
            if [[ "$_turbo_mode" != "true" ]]; then
                _turbo_mode=true
                _current_interval=$TURBO_INTERVAL
                log_info "⚡ TURBO MODE: check interval ${CHECK_INTERVAL}s → ${TURBO_INTERVAL}s"
            fi

            now=$(mono_now)   # v0.7 (Block 3): display elapsed, but it reads the MONO stamp — same clock or the number is garbage
            elapsed_since_first=$(( now - FIRST_DELINQUENT_TIME ))
            w_count=$(window_count)
            w_total=${#_delinq_window}

            log_warn "LOCAL: Delinquent! (window: ${w_count}/${w_total}, need: ${DELINQUENCY_WINDOW_THRESHOLD}/${DELINQUENCY_WINDOW_SIZE} | ${elapsed_since_first}s/${TAKEOVER_DELAY}s)"

            # When window triggered → attempt takeover (external confirmation + gossip + take)
            if window_triggered; then
                attempt_takeover
            fi

            display_status "DELINQ ${w_count}/${DELINQUENCY_WINDOW_SIZE}"

        elif [[ $local_result -eq 1 ]]; then
            # NOT delinquent
            window_push 0
            if window_mostly_clear; then
                [[ $FIRST_DELINQUENT_TIME -gt 0 ]] && alert_info "✅ STANDBY delinquency cleared (window mostly clear)"
                _starvation_note_close "delinquency cleared"   # v0.7 (B3 s4 rework): BEFORE the inline resets (this branch does not call window_reset)
                FIRST_DELINQUENT_TIME=0; _takeover_alert_sent=""
                LAST_LIVENESS_ACTIVE_TIME=0   # v0.6.7 (N3): reset with FIRST_DELINQUENT_TIME — fresh episode
                _fastpath_absent_seen=0; _fastpath_confirm=0   # v0.6.8 (S2): end the fast-path episode too, so the A2 absent→present transition cannot latch across the organic delinquency-clear into the next episode
                _gossip_prefetched=false; _gossip_result=""
                _last_confirm_attempt=0   # v0.6.1 (F2): fresh episode starts un-throttled
                _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""   # v0.6.2 (C1) / v0.6.3 (Block 1) / v0.7 (B3 s2): drop stale sample + tip + provider pin
                _last_blind_end=0   # v0.7 (B3 s4): episode over — drop the blind anchor with the episode
                _liveness_obs_since=0; _ep_blind_cycles=0; _ep_provider_flips=0; _ep_floor_holds=0   # v0.7 (B3 s4 rework): observed span + episode diagnostics end with the episode
                if [[ "$_turbo_mode" == "true" ]]; then
                    _turbo_mode=false
                    _current_interval=$CHECK_INTERVAL
                    log_info "⚡ TURBO OFF: check interval → ${CHECK_INTERVAL}s"
                fi
            fi
            display_status "OK"

        else
            # LOCAL RPC can't determine — don't push anything, just warn
            log_warn "LOCAL getVoteAccounts unreachable — skipping delinquency check"
            display_status "LOCAL ERR"
        fi

    elif [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]]; then
        # ======== STAKED (took over): self-fence, then hold or give back ========

        # v0.6.9 (H1): PROMOTED-holder self-fence — the primary's isolation checks (frozen confirmed
        # slot / silent LOCAL RPC / N6 own-vote-lag / getHealth), LOCAL signals only, demote =
        # give_back_identity + re-take lockout. Checked FIRST so isolation is acted on promptly; on a
        # fire the loop continues (next cycle takes the UNSTAKED branch — where the lockout gates
        # attempt_takeover).
        if [[ "$STANDBY_SELF_FENCE" == "true" ]]; then
            if check_self_fence_isolation; then
                display_status "SELF-FENCED"; sleep "$_current_interval"; continue
            fi
        fi

        # v0.6.9 (M5): collision detector — DETECTION-ONLY page when gossip shows the staked pubkey at
        # a non-self endpoint while we hold it. Never demotes; self-throttled to COLLISION_CHECK_INTERVAL.
        check_identity_collision || true

        if [[ "$GIVE_BACK_MODE" == "manual" ]]; then
            if [[ $(( $(date +%s) - _last_status_log )) -ge 60 ]]; then
                log_info "STAKED (took over). manual mode — hold (self-fence $([[ "$STANDBY_SELF_FENCE" == "true" ]] && echo armed || echo OFF))"
                _last_status_log=$(date +%s)
            fi
        fi
        display_status "ACTIVE"

    else
        # An identity that is neither this node's UNSTAKED key nor the STAKED key means the ENTIRE
        # protection stack is inert — no takeover logic, no self-fence, no collision detector — while
        # the operator most likely believes this spare is armed. Confirmed in production 2026-08-10:
        # a manual failback briefly brought the validator up on a different unstaked key and the
        # mainnet standby sat dark behind a WARN, during the exact operation where it mattered most.
        # This pages like the emergency it is: immediately on entry, re-paged through ALERT_THROTTLE
        # while it persists, with a recovery notice when the identity classifies again (above).
        now_unk=$(date +%s)
        if [[ $_unknown_identity_since -eq 0 ]]; then
            _unknown_identity_since=$now_unk
            _last_unknown_alert=$now_unk
            alert "UNKNOWN IDENTITY — this node's failover protection is INERT (no takeover, no self-fence) until the identity matches its configured keys" "$CURRENT_IDENTITY" "🚨 PROTECTION OFFLINE"
        elif [[ $(( now_unk - _last_unknown_alert )) -ge $ALERT_THROTTLE ]]; then
            _last_unknown_alert=$now_unk
            alert "UNKNOWN IDENTITY persists ($(( (now_unk - _unknown_identity_since) / 60 ))m) — failover protection still INERT" "$CURRENT_IDENTITY" "🚨 PROTECTION OFFLINE"
        else
            log_warn "Unknown identity: $CURRENT_IDENTITY (protection inert — paged)"
        fi
        display_status "UNKNOWN"
    fi

    # --- Heartbeat: periodic status summary ---
    now_hb=$(date +%s)
    if [[ $(( now_hb - _last_heartbeat )) -ge $HEARTBEAT_INTERVAL ]]; then
        id_label="STANDBY"
        [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] && id_label="ACTIVE*"

        log_info "♥ Heartbeat: ${id_label} | Checks: $STAT_CHECKS | LOCAL delinq: $STAT_LOCAL_DELINQ | Delinq seen: $STAT_DELINQUENT_SEEN | Takeovers: $STAT_TAKEOVERS | T2: $STAT_TIER2_CHECKS | T3: $STAT_TIER3_CHECKS | Window: [${_delinq_window:-empty}]"
        _last_heartbeat=$now_hb
    fi

    save_state   # v0.6.9 (H3): persist the self-fence baseline + lockout every cycle (plain overwrite) so a monitor restart mid-stall inherits the clock

    # Adaptive sleep: turbo=1s, normal=CHECK_INTERVAL
    sleep "$_current_interval"
done

log_info "Main loop exited."
