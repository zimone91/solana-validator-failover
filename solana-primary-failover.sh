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
# Solana Primary Node Failover Protection v0.6.10 (THREE-TIER RPC)
# Combines: internet monitoring + 3-tier delinquency verification + safe recovery
#
# THREE-TIER VERIFICATION:
#   Tier 1 — LOCAL RPC (127.0.0.1:8899) : fast, every 3s, no rate limits
#   Tier 2 — ALCHEMY (paid, reliable)   : confirms Tier 1, only when triggered
#   Tier 3 — PUBLIC RPC (free, fallback) : final independent check
#
# FLOW:
#   Internet DOWN → switch immediately (can't vote anyway)
#   Tier 1 delinquent x5 → Tier 2 confirms? → Tier 3 confirms? → SWITCH
#   Tier 2 denies → false positive from local RPC, reset
#
# Run on PRIMARY node. For STANDBY use solana-standby-failover.sh
# ============================================================================

set +e

# ========================= CONFIG (defaults, overridden by failover.env) ======
# --- Node ---
NODE_NAME="MY_VALIDATOR"
VALIDATOR_TYPE="agave"                    # "agave" or "frankendancer"

# --- Paths ---
STAKED_KEYPAIR="/root/solana/mainnet-validator-keypair.json"
UNSTAKED_KEYPAIR="/root/solana/unstaked-identity.json"
SOLANA_PATH="$HOME/.local/share/solana/install/active_release/bin"
LEDGER_PATH=""                            # auto-detect from systemd if empty
TOWER_PATH=""                             # auto-detect from systemd if empty
CONFIG_TOML=""                            # for frankendancer only
VALIDATOR_SERVICE="solana"                # systemd unit name of the validator (ledger auto-detect fallback)

# --- Three-Tier RPC ---
LOCAL_RPC="http://127.0.0.1:8899"                                               # Tier 1: always available, fast
TIER2_RPC=""                                                                     # Tier 2: paid RPC (Alchemy/Helius/Triton)
TIER3_RPC="https://api.mainnet-beta.solana.com"                                  # Tier 3: free, rate-limited

# --- Thresholds ---
CHECK_INTERVAL=3                          # seconds between Tier 1 checks (normal mode)
TURBO_INTERVAL=1                          # seconds between checks (turbo: when delinquency detected)
CONNECTIVITY_TARGETS=("8.8.8.8" "1.1.1.1" "9.9.9.9")
CONNECTIVITY_TIMEOUT=1                    # seconds per ping
CONNECTIVITY_RETRIES=3                    # failed rounds before switch (3 x 3s = 9s)
MAX_VOTE_LATENCY=0                        # 0 = only delinquency, >0 = trigger on N slots behind
DELINQUENCY_RETRIES=5                     # Tier 1 confirmations before escalating to Tier 2
RECOVERY_COOLDOWN=120                     # seconds after switch before allowing switch-back
STARTUP_GRACE=30                          # seconds to wait after start

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

# --- Safety ---
# v0.5.9: DRY_RUN=true is the safe default. Live mode requires explicit DRY_RUN=false in env.
DRY_RUN=true
RECOVERY_MODE="manual"                    # "manual" | "auto" | "rpc"

# RPC recovery settings (only used in "rpc" mode)
VOTE_PUBKEY=""                            # vote account pubkey (REQUIRED for "rpc" mode)
RECOVERY_DELAY=300                        # seconds to wait AFTER going unstaked
RECOVERY_CHECKS=3                         # consecutive "safe" confirmations
RECOVERY_CHECK_INTERVAL=30                # seconds between recovery checks

# --- Vote-liveness fence for rpc-recovery (v0.6.3 Block 2) ---
# When RECOVERY_MODE=rpc, PRIMARY re-takes the staked identity ONLY if nobody is voting it. The
# authoritative signal is the same vote-liveness check the STANDBY/BACKUP takeover path uses
# (lastVote frozen over the interval, with the external cluster tip advancing), NOT gossip-IP
# inference. If the identity is being voted (the STANDBY holds it) recovery is refused. These
# knobs match the standby defaults; they are only consulted in rpc mode.
# v0.7 (Block 3, slice 3 / AUDIT-5 A3): EPSILON 2 → 0 — ANY forward movement of lastVote is life.
# DEPENDENCY: ε=0 PRESUMES the provider-pinned pair (slice 2) — only a same-vantage pair may render
# FROZEN. Do NOT raise ε to "fix" provider flapping — fix the provider, not the constant. Full
# rationale + measured cost (≈ +70s on a stray burst; no deadlock): the STANDBY twin's definition site.
VOTE_LIVENESS_EPSILON=0                   # lastVote must advance > this many slots to count as "voting" (0 = ANY advance)
VOTE_LIVENESS_MIN_INTERVAL=10             # min seconds between the two lastVote samples for a valid delta
# v0.7 (Block 3, slice 4) — OBSERVATION-SPAN FLOOR (RATIFIED by the reviewer, 2026-08-17). A
# FROZEN-based re-take must rest on at least this many seconds of OBSERVED span since the
# EPISODE's first successful observation (or since the end of the last blind cycle) — measured
# from _liveness_obs_since, NOT the re-basable pair pin — so a post-blind pair only one
# MIN_INTERVAL wide cannot clear the recovery fence. 0 = disabled (drift-announced). Full
# rationale + the correctness/convergence argument: _liveness_span_short (and the STANDBY twin's
# definition site). NOTE (reviewer): unlike the STANDBY (strict no-op on its live-tested path),
# on the PRIMARY this is NOT a no-op — the recovery delay branch deliberately resets the pair
# every cycle ("keep the sample fresh"), so the first observation lands only at eligibility and
# the floor adds up to (MIN_SPAN - MIN_INTERVAL) ≈ 30s of observation before an automatic
# re-take. Accepted: recovery is minutes-scale (RECOVERY_DELAY 300 + RECOVERY_CHECKS×30s) and
# the added wait fails toward NOT re-taking.
VOTE_LIVENESS_MIN_SPAN=40                 # min OBSERVED seconds this episode behind a FROZEN-based re-take (0 = off)

# --- PRIMARY self-fence / "vote lease" (v0.6.3 Block 3) ---
# Closes the residual partition case: a PRIMARY that is alive but ISOLATED from the supermajority
# (partition / severe DDoS where it can't confirm participation) looks dead to the cluster but
# keeps voting — then heals into a double-sign. The self-fence drops it to UNSTAKED *during* the
# partition, using LOCAL signals ONLY (never an external RPC), so it stops voting before the heal.
# Fail-safe: it can ONLY ever lead to switch_to_unstaked (the safe direction), and is disable-able.
PRIMARY_SELF_FENCE=true                   # master kill switch (false = disable the self-fence)
SELF_FENCE_ISOLATION_SECS=30              # LOCAL getSlot(confirmed) must advance within this window
SELF_FENCE_MAX_BEHIND=150                 # optional getHealth "behind by >N" demote (0 = off)
# v0.6.5 (F1): demote if the LOCAL getSlot(confirmed) is CONTINUOUSLY no-answer (silent) this many
# seconds while staked AND a confirmed-slot baseline already exists (never on fresh start). Closes
# the case where a silent LOCAL JSON-RPC kept the node staked while STANDBY could take over → heal
# double-sign. LOCAL signal only; safe direction only. 0 = disable this sub-check.
# v0.6.6 (N1): 60 → 30 (matches SELF_FENCE_ISOLATION_SECS) so the PRIMARY self-fence worst case is
# 30s — it relinquishes well before any spare's TAKEOVER_DELAY (default 60). The demote is fail-safe
# (→ UNSTAKED, stops voting), so an over-eager 30s costs availability, NOT a double-sign. 30s is more
# false-fire-prone than 60s (a healthy node's JSON-RPC can stall ~30s under load/compaction while the
# admin RPC still answers) — MEASURE local JSON-RPC stall frequency on testnet (see runbook) and nudge
# this (and the spare's TAKEOVER_DELAY with it) back up if too twitchy.
SELF_FENCE_NOANSWER_SECS=30
# v0.6.7 (N6): egress-only / "can I BE HEARD?" self-fence. The frozen-slot + no-answer checks above
# only catch "can I HEAR the cluster?" (inbound). An EGRESS-ONLY partition — we still RECEIVE blocks but
# our own votes don't propagate — leaves them BLIND: the LOCAL confirmed slot keeps advancing from
# inbound (no freeze, RPC answers) while our OWN staked vote stops landing on-chain. Demote when our own
# vote account (VOTE_PUBKEY) lastVote lags the same-payload cluster-max lastVote (both from ONE LOCAL
# getVoteAccounts at commitment=processed — v0.6.7 N8) by > SELF_FENCE_VOTE_LAG_SLOTS for
# >= SELF_FENCE_VOTE_LAG_SECS. LOCAL signal ONLY (never external — the egress is exactly what's broken);
# safe direction only. VOTE_PUBKEY is REQUIRED when these knobs are > 0 (v0.6.7 N7 — startup refuses a
# blank one). Either knob = 0 disables this sub-check. (Found live on testnet rc.1, 2026-06-29 — CHANGELOG.)
# Threshold sizing (cross-node margin, NOT just false-fire): the lag grows ~linearly at the slot rate
# (~2–2.5 slots/s), so demote ≈ SELF_FENCE_VOTE_LAG_SLOTS/rate + SELF_FENCE_VOTE_LAG_SECS. At 32 slots
# that is ~13s + 20s ≈ 33s — comfortably before even a worst-case fast spare (D=0: ~8s detect/window +
# TAKEOVER_DELAY 60s ≈ 68s), preserving the ≥30s cross-node margin so the PRIMARY always relinquishes
# first. 128 would demote at ~71–84s and LOSE that race. Still false-fire-safe: a healthy node's lag is
# single-digit slots and never sustains 32 for 20 continuous seconds. Keep in 24–48; the healthy soak
# (runbook) calibrates the final value.
SELF_FENCE_VOTE_LAG_SLOTS=32
SELF_FENCE_VOTE_LAG_SECS=20
# v0.6.8 (B2): N6 flap hysteresis — CONSECUTIVE healthy cycles (own vote within SLOTS of cluster-max)
# required before the accumulating sustain timer is cleared. Stops a flapping/intermittent egress (one
# vote burst per < SECS) from zeroing the timer every cycle so N6 never fires (wedged-but-alive hole).
# >= 2 (1/0 = no hysteresis); ~3 is safe and still clears promptly on genuine recovery.
SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
# v0.6.8 (B1): bound the demote/promote admin-socket calls. set-identity / authorized-voter run on the
# SAME admin RPC socket that get_local_identity wraps in `timeout 8` ("can hang indefinitely under heavy
# load or compacting ledger") — but the demote itself was UN-timeout'd, so a wedged socket could freeze
# the single-threaded loop mid-demote and silently re-open the very double-sign gap the self-fence closes.
# Bound them (>= the read path's 8s). On a DEMOTE (switch_to_unstaked) timeout, escalate (SELF_FENCE_HARD_STOP).
SETIDENTITY_TIMEOUT=15
# v0.6.8 (B1): when a DEMOTE set-identity wedges (times out), the self-fence still MUST guarantee the
# staked identity STOPS voting. Escalate to a hard stop of the validator (systemctl stop, then SIGTERM the
# PID) — the safe direction: a stopped validator cannot double-sign. Only on the demote path, only after a
# real timeout, never in DRY_RUN. false = alert only, do NOT stop (NOT recommended — leaves the gap open).
SELF_FENCE_HARD_STOP=true
# v0.6.9 (H2): a hard-stop must survive Restart=always. When systemctl stop did not cleanly succeed and
# the PID was killed directly, systemd restarts the validator after RestartSec (typically 10s) — AFTER the
# immediate down-verify passed — and it resurrects VOTING STAKED. Two-part fix: (a) mask the unit
# (--runtime, so a reboot clears it — fail toward recoverability) before escalating to SIGTERM/SIGKILL;
# (b) RE-verify the down-state after this many seconds (>= typical RestartSec). A resurrected process =
# HARD STOP FAILED (page, INTERVENE NOW). FAILURE DIRECTION: toward reporting failure / paging the
# operator — never a false "confirmed DOWN".
HARD_STOP_REVERIFY_SECS=15
# v0.6.9 (M5): collision detector — while STAKED, periodically compare where gossip says the staked
# pubkey lives (external T2/T3 view) against our OWN gossip endpoint (LOCAL view). Two consecutive
# mismatch strikes → 🚨 page (throttled by ALERT_THROTTLE). DETECTION-ONLY: it never demotes (see the
# reasoning block at check_identity_collision).
COLLISION_CHECK_INTERVAL=60

# --- Telegram ---
TG_ENABLED=true
TG_BOT_TOKEN=""
TG_CHAT_ID=""

# --- Webhook ---
WEBHOOK_URL=""
WEBHOOK_BODY=""

# --- Logging ---
LOG_FILE="/var/log/solana-failover.log"
LOG_MAX_SIZE=52428800

# --- State persistence (v0.6.1 F7; extended v0.6.9 H3/M10) ---
# Anti-flap timers + the self-fence baseline survive a failover-service restart (the unit is
# Restart=always). v0.6.9 (M10): role-specific default so colocated PRIMARY+SPARE daemons (lab) cannot
# clobber each other's state — H3 makes this file load-bearing. A legacy ".../state" file is migrated
# once at startup (see load_state).
STATE_DIR="/var/lib/solana-failover"
STATE_FILE="/var/lib/solana-failover/state-primary"
_DEFAULT_STATE_FILE="$STATE_FILE"   # v0.6.9 (B5): the shipped default, captured BEFORE the env is sourced,
                                    # so the M10 legacy migration fires ONLY on an unmodified default path
                                    # (an operator override — even one that keeps the -primary suffix — is
                                    # never touched, matching the documented invariant).
# v0.6.9 (H3): restore the persisted self-fence baseline ONLY when the save is fresher than this many
# seconds — a stale baseline must not fire an instant false demote after a long downtime. FAILURE
# DIRECTION: a discarded (stale) baseline = fresh timers = the fence re-arms from scratch (the pre-H3
# behavior); it can delay a demote but never fabricate one.
STATE_MAX_AGE_SECS=900
# v0.6.9 (H3): if the persisted state says we were STAKED and the startup "waiting for local validator"
# loop exceeds this many seconds, page 🚨 (PRIMARY UNREACHABLE WHILE STAKED semantics: the daemon cannot
# self-demote an unreachable validator; a spare may take over — intervene). Once per startup.
STARTUP_STAKED_UNREACHABLE_ALERT_SECS=60

# ========================= LOAD EXTERNAL CONFIG ===============================
CONFIG_FILE="$(dirname "$(readlink -f "$0")")/failover.env"
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
LAST_SWITCH_TIME=0
CONNECTIVITY_FAIL_COUNT=0
LATENCY_FAIL_COUNT=0
# shellcheck disable=SC2034  # reserved: set for diagnostics; not currently read
SCRIPT_START_TIME=$(date +%s)

# Sliding window for delinquency detection (replaces simple consecutive counter)
# "7 out of 10" instead of "5 consecutive" — survives brief recoveries during DDoS
_delinq_window=""                         # ring buffer: "0110111011"

# Adaptive interval
_turbo_mode=false
_current_interval=$CHECK_INTERVAL

_standby_alert_sent=""
_pending_alert=""
_unknown_identity_since=0                 # unknown-identity episode start (0 = classified)
_last_unknown_alert=0                     # re-page throttle inside an unknown-identity episode
_last_recovery_log=0
_recovery_confirm_count=0
_running=true
_cached_tower_base=""
_last_heartbeat=0
_last_hb_ping=0                           # v0.6.4: last external watchdog ping (own timer)
_last_known_identity=""                   # detect manual identity changes

# Vote-liveness sampling for rpc-recovery (v0.6.3 Block 2): first lastVote sample + its cluster-wide
# freshness reference (max lastVote from the same payload) + wall-clock timestamp. Mirrors the standby
# fence; reset on every switch / manual identity change / before recovery is eligible.
# v0.7 (Block 3, slice 2 / AUDIT-5 A2): also remember WHICH provider tier ("T2"/"T3") served each
# sample — a liveness pair is only comparable same-vantage (a lagging fallback provider can fake a
# FROZEN reading against a live holder). _liveness_first_provider pins the pair's vantage;
# _liveness_sample_provider is the sampler's per-call answer (mirrors the standby twin).
_liveness_first_vote=""
_liveness_first_tip=""
_liveness_first_ts=0
_liveness_first_provider=""
_liveness_sample_provider=""
# v0.7 (Block 3, slice 4 / AUDIT-5 S-3): mono time of the last recovery-path cycle on which NO
# external provider yielded a usable observation (liveness sampler empty on both tiers). Second
# input to the RECOVERY_DELAY anchor — see INVARIANT(blindness-is-life) in attempt_safe_recovery
# (full statement: the standby twin's _note_blind_cycle). 0 = no blind cycle observed; reset on
# every switch / manual identity change (episode boundaries), NOT in reset_recovery_liveness
# (that runs every delay cycle and must not erase the blind anchor it just created).
_last_blind_end=0
# v0.7 (Block 3, slice-4 rework): mono time of the EPISODE's first successful external observation
# (0 = none yet). Pinned by _note_observation on every successful sampler observation; reset ONLY
# by episode resets (every _last_blind_end=0 site), by blind cycles (_note_blind_cycle), and by
# the VOTING re-base (slice 5: staked_is_actively_voting's ADVANCED path and the fresh-proof
# re-check re-pin it to the verdict instant — observed LIFE restarts the observed-silence span) —
# NEVER by the non-verdict pair re-bases (tip-stall / backwards / provider flip), and NOT by
# reset_recovery_liveness (same rule as _last_blind_end). The observation-span floor measures
# from this, not the pair pin.
_liveness_obs_since=0
# v0.7 (Block 3, slice-4 rework): per-episode hold diagnostics — reset at every _last_blind_end=0
# site (episode boundaries), incremented in the byte-identical helpers. The counters feed the
# STANDBY's starvation page; on the PRIMARY they are kept only for helper byte-parity/diagnostics.
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

# Self-fence "vote lease" tracker (v0.6.3 Block 3): last LOCAL confirmed slot + the wall-clock time
# it last advanced. LOCAL signals only. Reset (re-armed) on every switch / manual identity change.
_last_confirmed_slot=""
_last_confirmed_advance_ts=0
# v0.6.5 (F1): wall-clock when the LOCAL getSlot(confirmed) FIRST went no-answer (silent) while a
# baseline exists; 0 = not currently silent. Demote after SELF_FENCE_NOANSWER_SECS of continuous
# silence. Cleared on any successful read and in _selffence_reset (switch / identity change).
_selffence_noanswer_since=0
# v0.6.7 (N6): own-vote-lag tracker. _since = wall-clock when our own lastVote FIRST lagged the LOCAL
# confirmed tip past SELF_FENCE_VOTE_LAG_SLOTS (0 = not currently lagging). _baseline is set once we've
# seen a HEALTHY own-vote reading (lag within threshold) — so a fresh start / catching-up node (lagging
# from the start, no healthy baseline yet) never arms. Both cleared in _selffence_reset (switch / id change).
_selffence_votelag_since=0
_selffence_votelag_baseline=""
# v0.6.9 (H3): restart-continuity restore hooks. load_state stashes the persisted stall/silence/lag
# timestamps here and arms a pending flag; check_self_fence_isolation consumes the flag on its FIRST
# post-restart evidence read: if the stall/silence/lag is provably CONTINUOUS (slot still not past the
# persisted baseline / RPC still silent / lag still over threshold) the timer is BACKDATED to the
# persisted value (fence can fire immediately); if the validator recovered, the flag is dropped and the
# timers run fresh. This is what keeps a daemon restart during a validator stall from disarming the
# fence, WITHOUT letting a stale save fire a false instant demote. All cleared in _selffence_reset.
_selffence_restore_pending=0
_selffence_restored_advance_ts=0
_selffence_noanswer_restore_pending=0
_selffence_restored_noanswer_since=0
_selffence_votelag_restore_pending=0
_selffence_restored_votelag_since=0
# v0.6.9 (H3): role recorded in the last persisted save ("staked"/"unstaked"/""), read by load_state.
# Drives the startup staked-but-unreachable page and gates the backdating above (only a STAKED save may
# inherit a stall clock).
_persisted_role=""
# v0.6.9 (M5): collision-detector state — consecutive non-self-endpoint strikes + throttle stamps.
_collision_strikes=0
_last_collision_check=0
_last_collision_alert=0
# v0.6.8 (B2): count of CONSECUTIVE healthy (vlag <= SLOTS) cycles. Hysteresis: the sustain timer
# (_since) is cleared only after SELF_FENCE_VOTE_LAG_RESET_CYCLES healthy cycles, so a single burst dip
# from a FLAPPING egress cannot wipe an accumulating timer (which would let N6 never fire). Cleared in
# _selffence_reset and reset to 0 the moment a cycle is over threshold.
_selffence_votelag_healthy=0

STAT_CHECKS=0
STAT_INET_FAILURES=0
STAT_SWITCHES=0
STAT_TIER2_CHECKS=0
STAT_TIER3_CHECKS=0
STAT_FALSE_POSITIVES=0

# Alert throttling
ALERT_THROTTLE=600                        # 10 minutes
_last_unreachable_alert=0
_last_switch_fail_alert=0                 # v0.6.0: throttle repeated failed-switch alerts

# ========================= SIGNAL HANDLING ====================================

cleanup() {
    _running=false
    log_info "Shutdown signal received. Stopping failover monitor..."
    send_telegram "🛑 Failover monitor stopped (signal received)" 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ========================= FUNCTIONS ==========================================

# --- Logging ---

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
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null) || return
        [[ $size -gt $LOG_MAX_SIZE ]] && mv "$LOG_FILE" "${LOG_FILE}.old" && log_info "Log rotated"
    fi
}

# --- Notifications ---

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
    _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
    if [[ $rc -ne 0 ]]; then log_warn "Telegram failed (curl rc=$rc)"; return 1; fi
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

    # Auto-detect ntfy.sh → use native headers (not JSON body)
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
    _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
}

alert() {
    local reason="$1" identity="$2" status="$3"
    log_warn "ALERT: $status — $reason (identity: $identity)"
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

# --- Keypair validation ---

validate_keypair_file() {
    local filepath="$1" label="$2"
    [[ ! -f "$filepath" ]] && { log_error "$label keypair not found: $filepath"; return 1; }
    [[ ! -s "$filepath" ]] && { log_error "$label keypair empty: $filepath"; return 1; }
    head -c 1 "$filepath" | grep -q '\[' || { log_error "$label keypair not valid JSON: $filepath"; return 1; }
    local pubkey
    pubkey=$("$SOLANA_PATH/solana-keygen" pubkey "$filepath" 2>/dev/null)
    [[ -z "$pubkey" ]] && { log_error "$label: cannot derive pubkey"; return 1; }
    echo "$pubkey"
}

# --- Connectivity ---

check_internet() {
    # OPT#8: Parallel pings — all targets at once, return on first success
    local pids=() tmpdir
    tmpdir=$(mktemp -d /tmp/failover-ping-XXXXXX 2>/dev/null) || {
        # v0.5.9: don't fall back to PID-based path (PID reuse after restart can leave stale $tmpdir/ok)
        log_warn "mktemp failed — fallback to single HTTP probe"
        curl -s -m 1 --head "http://1.1.1.1" &>/dev/null && return 0
        curl -s -m 1 --head "http://8.8.8.8" &>/dev/null && return 0
        return 1
    }

    for target in "${CONNECTIVITY_TARGETS[@]}"; do
        ( ping -c 1 -W "$CONNECTIVITY_TIMEOUT" "$target" &>/dev/null && touch "$tmpdir/ok" ) &   # v0.6.1 (N1): honor CONNECTIVITY_TIMEOUT
        pids+=($!)
    done

    # Wait up to 1.5s for any ping to succeed
    local waited=0
    while [[ $waited -lt 15 ]]; do
        [[ -f "$tmpdir/ok" ]] && { kill "${pids[@]}" 2>/dev/null; wait "${pids[@]}" 2>/dev/null; rm -rf "$tmpdir"; return 0; }
        sleep 0.1
        waited=$((waited + 1))
    done

    # Cleanup and final fallback
    kill "${pids[@]}" 2>/dev/null; wait "${pids[@]}" 2>/dev/null
    [[ -f "$tmpdir/ok" ]] && { rm -rf "$tmpdir"; return 0; }
    rm -rf "$tmpdir"

    # HTTP fallback
    curl -s -m 1 --head "http://1.1.1.1" &>/dev/null && return 0
    return 1
}

# --- Local validator ---

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
# Tracks last N checks instead of consecutive count.
# Survives brief recoveries during DDoS flickering.

# Push a result (1=delinquent, 0=ok) into the ring buffer
window_push() {
    _delinq_window="${_delinq_window}${1}"
    # Trim to window size
    local len=${#_delinq_window}
    if [[ $len -gt $DELINQUENCY_WINDOW_SIZE ]]; then
        _delinq_window="${_delinq_window:$((len - DELINQUENCY_WINDOW_SIZE))}"
    fi
}

# Count delinquent (1) entries in window
window_count() {
    local ones="${_delinq_window//0/}"
    echo "${#ones}"
}

# Check if threshold reached
window_triggered() {
    local count
    count=$(window_count)
    local total=${#_delinq_window}
    [[ $total -ge $DELINQUENCY_WINDOW_SIZE && $count -ge $DELINQUENCY_WINDOW_THRESHOLD ]]
}

# Reset window (after switch or recovery)
window_reset() {
    _delinq_window=""
    _turbo_mode=false
    _current_interval=$CHECK_INTERVAL
}

# Is window mostly clear? (fewer than 2 delinquent)
window_mostly_clear() {
    local count
    count=$(window_count)
    [[ $count -lt 2 ]]
}

# ========================= STATE PERSISTENCE (v0.6.1 F7) ======================
# Persist LAST_SWITCH_TIME so the RECOVERY_COOLDOWN / anti-flap window survives a
# service restart (Restart=always would otherwise zero it). We restore ONLY a
# genuine persisted value — we never initialize LAST_SWITCH_TIME to "now", which
# would enforce the cooldown right after a restart and block a legitimate switch.

# v0.6.9 (H3): fetch one numeric field from STATE_FILE (last occurrence wins; strict ^KEY=[0-9]+$ so a
# corrupt/partial line is silently ignored — restore only genuine values).
_state_get() { grep -E "^${1}=[0-9]+$" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2; }

load_state() {
    # v0.6.9 (M10): one-time migration of the legacy shared ".../state" file to the role-specific
    # default. Only when STATE_FILE still IS the role default (operator overrides are left alone),
    # the new file is absent, and the legacy file exists. Best-effort: a failed/missed migration is
    # benign (the H3 freshness gate simply restores nothing).
    # v0.6.9 (B5): gate on the EXACT shipped default (captured pre-env-source), not merely the -primary
    # suffix — so an operator override like /custom/state-primary is never migrated.
    local _legacy="${STATE_FILE%-primary}"
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
    # v0.7 (Block 3, dual-write): prefer the *_MONO twin; legacy = wall for rollback, >0-signal only.
    v=$(_state_get LAST_SWITCH_MONO)
    [[ -z "$v" ]] && { v=$(_state_get LAST_SWITCH_TIME); [[ -n "$v" && $v -gt 0 ]] && v=$_mono_now; }
    if [[ -n "$v" ]]; then
        # v0.7 (Block 3): different boot + a real (>0) stamp → the recovery delay/cooldown re-held in
        # full from now (see above). A 0 stamp ("no switch yet") restores as 0 — never invent a
        # cooldown that would block a legitimate first switch (the original F7 rule).
        [[ $_same_boot -eq 0 && $v -gt 0 ]] && v=$_mono_now
        LAST_SWITCH_TIME="$v"; log_info "State restored: LAST_SWITCH_TIME=$LAST_SWITCH_TIME"
    fi

    # v0.7 (pre-Block-4, №9): last KNOWN alpenglow gate state — a plain STRING, not a timer, so it
    # restores VERBATIM: no *_MONO twin (nothing does clock arithmetic on it — the boot-id rules
    # above are about mono stamps) and no freshness gate (a stale value at worst logs one already-
    # seen transition as unchanged; a garbled/absent line restores nothing). _state_get is
    # numeric-only, hence the enumerated grep (the ROLE_AT_SAVE idiom).
    v=$(grep -E '^ALPENGLOW_GATE_STATE=(inactive|pending|active)$' "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
    [[ -n "$v" ]] && _alpenglow_gate_state="$v"

    # v0.6.9 (H3): self-fence baseline continuity across a monitor restart. Restore-only-genuine +
    # FRESHNESS-GATED: a save older than STATE_MAX_AGE_SECS is discarded wholesale (a stale baseline
    # must not fire an instant false demote). Slot/latch VALUES restore verbatim; TIMESTAMPS restart at
    # "now" — EXCEPT that a persisted-STAKED stall/silence/lag arms a pending backdate which
    # check_self_fence_isolation applies only on positive first-read evidence that the condition is
    # CONTINUOUS. FAILURE DIRECTION: ambiguity discards state → fresh timers (pre-H3 behavior), never
    # an invented stall.
    local save_ts role now age
    save_ts=$(_state_get SAVE_TS)
    role=$(grep -E '^ROLE_AT_SAVE=(staked|unstaked)$' "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
    [[ -n "$role" ]] && _persisted_role="$role"   # read regardless of age: drives the startup staked-unreachable page (a long-dead monitor over a staked validator is exactly the case to page about)
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
    if [[ "$PRIMARY_SELF_FENCE" == "true" ]]; then
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
            # Persisted-STAKED + the stall already older than the window → arm the backdate: if the
            # first post-restart read shows the slot STILL not past the baseline, the stall is
            # continuous and inherits the persisted clock (fence can fire immediately).
            if [[ $_same_boot -eq 1 && "$role" == "staked" && -n "$pa" && $(( _mono_now - pa )) -ge $SELF_FENCE_ISOLATION_SECS ]]; then
                _selffence_restore_pending=1; _selffence_restored_advance_ts="$pa"
            fi
        fi
        # Same principle for the no-answer timer: we were STAKED and already silent at save → if the
        # LOCAL RPC is STILL silent at the first post-restart check, inherit the silence clock.
        if [[ $_same_boot -eq 1 && "$role" == "staked" && -n "$pn" && $pn -gt 0 ]]; then
            _selffence_noanswer_restore_pending=1; _selffence_restored_noanswer_since="$pn"
        fi
        # N6 own-vote-lag: the healthy-baseline latch + hysteresis streak restore verbatim; the sustain
        # timer restarts EXCEPT via the same evidence-gated backdate (still over threshold on first read).
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
    # v0.6.9 (H3): persist the self-fence baseline + the role at save + a save timestamp alongside the
    # v0.6.1 cooldown. Written on every state-relevant transition AND once per main-loop cycle (plain
    # atomic-enough overwrite — no fsync storm; the freshness gate tolerates a torn last write).
    local _role="unstaked"
    [[ -n "$STAKED_PUBKEY" && "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] && _role="staked"
    local _SAVE_W _SAVE_M
    _SAVE_W=$(date +%s); _SAVE_M=$(mono_now)
    {
        printf 'LAST_SWITCH_TIME=%s\n'              "$(_m2w "$LAST_SWITCH_TIME")"
        printf 'LAST_SWITCH_MONO=%s\n'              "${LAST_SWITCH_TIME:-0}"
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

# --- Tier 1: LOCAL RPC (fast, every CHECK_INTERVAL) ---

tier1_check_delinquency() {
    local vote_result _t1d_rc
    vote_result=$(curl -s -m 10 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)
    _t1d_rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above); fires on the curl-failure early-return too — no-op outside the armed unit
    [[ $_t1d_rc -ne 0 ]] && return 1

    local is_delinquent
    is_delinquent=$(echo "$vote_result" | jq -r \
        --arg pubkey "$STAKED_PUBKEY" \
        '.result.delinquent[]? | select(.nodePubkey == $pubkey) | .nodePubkey // empty' 2>/dev/null)
    [[ -n "$is_delinquent" ]]
}

tier1_get_vote_latency() {
    local slot_result vote_result current_slot last_vote _t1l_rc
    slot_result=$(curl -s -m 10 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null)
    _t1l_rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above); fires on the curl-failure early-return too — no-op outside the armed unit
    [[ $_t1l_rc -ne 0 ]] && { echo "-1"; return; }
    current_slot=$(echo "$slot_result" | jq -r '.result // empty' 2>/dev/null)

    vote_result=$(curl -s -m 10 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)
    _t1l_rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above); fires on the curl-failure early-return too — no-op outside the armed unit
    [[ $_t1l_rc -ne 0 ]] && { echo "-1"; return; }
    last_vote=$(echo "$vote_result" | jq -r \
        --arg pubkey "$STAKED_PUBKEY" \
        '(.result.current + .result.delinquent)[] | select(.nodePubkey == $pubkey) | .lastVote // empty' 2>/dev/null)

    if [[ -n "$current_slot" && -n "$last_vote" && "$current_slot" =~ ^[0-9]+$ && "$last_vote" =~ ^[0-9]+$ ]]; then
        echo $(( current_slot - last_vote ))
    else
        echo "-1"
    fi
}

# --- Tier 2/3: External RPC delinquency check ---
# Returns: 0 = delinquent, 1 = not delinquent, 2 = unreachable

_check_rpc_delinquency() {
    local rpc_url="$1" rpc_label="$2"

    local vote_result _crd_rc
    vote_result=$(curl -s -m 15 "$rpc_url" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)
    _crd_rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B2): bounded op completed (rc captured above — the pet must not clobber $?); fires on the UNREACHABLE path too — a completed 15 s curl timeout is a completed op — no-op outside the armed unit

    if [[ $_crd_rc -ne 0 || -z "$vote_result" ]]; then
        log_warn "[$rpc_label] unreachable"; return 2
    fi
    echo "$vote_result" | jq -e '.result' &>/dev/null || { log_warn "[$rpc_label] invalid response"; return 2; }

    # Check by nodePubkey
    local hit
    hit=$(echo "$vote_result" | jq -r \
        --arg pubkey "$STAKED_PUBKEY" \
        '.result.delinquent[]? | select(.nodePubkey == $pubkey) | .nodePubkey // empty' 2>/dev/null)
    if [[ -n "$hit" ]]; then log_info "[$rpc_label] DELINQUENT (nodePubkey)"; return 0; fi

    # Also check by votePubkey
    if [[ -n "$VOTE_PUBKEY" ]]; then
        hit=$(echo "$vote_result" | jq -r \
            --arg vote "$VOTE_PUBKEY" \
            '.result.delinquent[]? | select(.votePubkey == $vote) | .votePubkey // empty' 2>/dev/null)
        if [[ -n "$hit" ]]; then log_info "[$rpc_label] DELINQUENT (votePubkey)"; return 0; fi
    fi

    log_info "[$rpc_label] NOT delinquent"
    return 1
}

# --- Full three-tier verification ---
# Called ONLY when Tier 1 threshold reached
# Returns: 0 = confirmed (switch!), 1 = denied (false positive)

verify_delinquency_tiered() {
    log_info "─── THREE-TIER VERIFICATION ───"
    log_info "Tier 1 (LOCAL): confirmed delinquent (window: $(window_count)/${DELINQUENCY_WINDOW_SIZE})"

    # ---- Tier 2: ALCHEMY ----
    STAT_TIER2_CHECKS=$((STAT_TIER2_CHECKS + 1))
    log_info "Tier 2 (ALCHEMY): checking..."

    _check_rpc_delinquency "$TIER2_RPC" "TIER2"
    local tier2=$?

    if [[ $tier2 -eq 0 ]]; then
        # Tier 2 CONFIRMED → Tier 3 for extra confidence
        STAT_TIER3_CHECKS=$((STAT_TIER3_CHECKS + 1))
        log_info "Tier 3 (PUBLIC): final check..."

        _check_rpc_delinquency "$TIER3_RPC" "TIER3"
        local tier3=$?

        if [[ $tier3 -eq 0 ]]; then
            log_warn "✅ ALL 3 TIERS CONFIRMED DELINQUENT"
            alert_info "🔍 3-tier: LOCAL ✅ ALCHEMY ✅ PUBLIC ✅ → switching"
            return 0
        elif [[ $tier3 -eq 1 ]]; then
            log_warn "⚠️ TIER2 confirmed, TIER3 denied — trusting Alchemy"
            alert_info "🔍 3-tier: LOCAL ✅ ALCHEMY ✅ PUBLIC ❌ → switching (trusting Alchemy)"
            return 0
        else
            log_warn "⚠️ TIER2 confirmed, TIER3 unreachable — proceeding (2/3)"
            alert_info "🔍 3-tier: LOCAL ✅ ALCHEMY ✅ PUBLIC ⏳ → switching"
            return 0
        fi

    elif [[ $tier2 -eq 1 ]]; then
        # Tier 2 DENIED → FALSE POSITIVE
        STAT_FALSE_POSITIVES=$((STAT_FALSE_POSITIVES + 1))
        log_warn "❌ FALSE POSITIVE: Local delinquent but Alchemy says OK"
        alert_info "🔍 False positive! LOCAL delinquent × ALCHEMY says OK → reset"
        return 1

    else
        # Tier 2 UNREACHABLE → fall back to Tier 3
        log_warn "TIER2 unreachable — falling back to TIER3"
        STAT_TIER3_CHECKS=$((STAT_TIER3_CHECKS + 1))

        _check_rpc_delinquency "$TIER3_RPC" "TIER3"
        local tier3=$?

        if [[ $tier3 -eq 0 ]]; then
            log_warn "⚠️ TIER2 down, TIER3 confirmed — proceeding"
            alert_info "🔍 3-tier: LOCAL ✅ ALCHEMY ⏳ PUBLIC ✅ → switching"
            return 0
        elif [[ $tier3 -eq 1 ]]; then
            STAT_FALSE_POSITIVES=$((STAT_FALSE_POSITIVES + 1))
            log_warn "❌ FALSE POSITIVE: Local delinquent, Alchemy down, PUBLIC says OK"
            alert_info "🔍 False positive: LOCAL ✅ ALCHEMY ⏳ PUBLIC ❌ → reset"
            return 1
        else
            # BOTH external unreachable + local confirmed N times = real problem
            log_warn "⚠️ BOTH EXTERNAL RPCs DOWN + local confirmed $(window_count)x → proceeding"
            alert_info "🔍 3-tier: LOCAL ✅ ALCHEMY ⏳ PUBLIC ⏳ → external unreachable, switching"
            return 0
        fi
    fi
}

# --- Vote latency: tiered confirmation ---

verify_latency_tiered() {
    local local_latency="$1"
    log_info "─── LATENCY TIER CHECK ───"

    STAT_TIER2_CHECKS=$((STAT_TIER2_CHECKS + 1))
    local ext_result ext_current_slot ext_last_vote
    ext_result=$(curl -s -m 15 "$TIER2_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)
    local _t2rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed (rc captured above — the pet must not clobber $?) — no-op outside the armed unit

    if [[ $_t2rc -eq 0 && -n "$ext_result" ]]; then
        ext_current_slot=$(curl -s -m 10 "$TIER2_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
        _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit

        ext_last_vote=$(echo "$ext_result" | jq -r \
            --arg pubkey "$STAKED_PUBKEY" \
            '(.result.current + .result.delinquent)[] | select(.nodePubkey == $pubkey) | .lastVote // empty' 2>/dev/null)

        if [[ -n "$ext_current_slot" && -n "$ext_last_vote" && "$ext_current_slot" =~ ^[0-9]+$ && "$ext_last_vote" =~ ^[0-9]+$ ]]; then
            local ext_latency=$(( ext_current_slot - ext_last_vote ))
            log_info "Tier 2 (ALCHEMY): latency $ext_latency slots"

            if [[ $ext_latency -gt $MAX_VOTE_LATENCY ]]; then
                log_warn "Tier 2 CONFIRMED latency ($ext_latency > $MAX_VOTE_LATENCY)"
                alert_info "🔍 Latency: LOCAL ${local_latency}sl ALCHEMY ${ext_latency}sl > limit ${MAX_VOTE_LATENCY}"
                return 0
            else
                STAT_FALSE_POSITIVES=$((STAT_FALSE_POSITIVES + 1))
                log_warn "❌ Latency false positive: Local ${local_latency}sl, Alchemy ${ext_latency}sl (OK)"
                return 1
            fi
        fi
    fi

    log_warn "⚠️ Tier 2 unreachable for latency — trusting local (${DELINQUENCY_RETRIES}x confirmed)"
    return 0
}

# ========================= RECOVERY (uses tiered RPCs) ========================

_check_single_rpc() {
    local rpc_url="$1"

    local vote_info vote_node _csr_rc
    vote_info=$(curl -s -m 15 "$rpc_url" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)
    _csr_rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above); fires on the unreachable early-return too — no-op outside the armed unit
    [[ $_csr_rc -ne 0 ]] && { log_warn "RPC unreachable: $rpc_url"; return 0; }

    vote_node=$(echo "$vote_info" | jq -r \
        --arg vote "$VOTE_PUBKEY" \
        '(.result.current + .result.delinquent)[] | select(.votePubkey == $vote) | .nodePubkey // empty' 2>/dev/null)

    [[ -z "$vote_node" ]] && { log_warn "Vote account not found via $rpc_url"; return 0; }
    [[ "$vote_node" != "$STAKED_PUBKEY" ]] && { log_info "[$rpc_url] Different nodePubkey: $vote_node"; return 0; }

    # v0.6.2 (F3 parity): compare the FULL ip:port endpoint, not just the IP. The old
    # `cut -d: -f1` treated a STANDBY sharing our public egress IP on a different port as
    # "our own stale entry" -> "nobody else has it" -> PRIMARY re-takes while STANDBY still
    # holds/votes it -> double-sign. Now any non-self endpoint means another node has it ->
    # abort recovery. (Mirrors check_primary_dropped_identity in the standby script. NOTE:
    # rpc recovery does NOT yet have the vote-liveness fence — tracked for v0.6.3.)
    local cluster_info staked_gossip_ep
    cluster_info=$(curl -s -m 15 "$rpc_url" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null)
    _csr_rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above); fires on the failed early-return too — no-op outside the armed unit
    [[ $_csr_rc -ne 0 ]] && { log_warn "[$rpc_url] getClusterNodes failed"; return 0; }

    staked_gossip_ep=$(echo "$cluster_info" | jq -r \
        --arg pubkey "$STAKED_PUBKEY" \
        '.result[]? | select(.pubkey == $pubkey) | .gossip // empty' 2>/dev/null | head -1)

    [[ -z "$staked_gossip_ep" ]] && { log_warn "[$rpc_url] Staked not in gossip"; return 0; }

    local local_cluster our_gossip_ep
    local_cluster=$(curl -s -m 10 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null)
    _csr_rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above); fires on the failed early-return too — no-op outside the armed unit
    [[ $_csr_rc -ne 0 ]] && { log_warn "Local getClusterNodes failed"; return 0; }

    our_gossip_ep=$(echo "$local_cluster" | jq -r \
        --arg pubkey "$UNSTAKED_PUBKEY" \
        '.result[]? | select(.pubkey == $pubkey) | .gossip // empty' 2>/dev/null | head -1)

    [[ -z "$our_gossip_ep" ]] && { log_warn "Cannot determine our gossip endpoint"; return 0; }

    if [[ "$staked_gossip_ep" != "$our_gossip_ep" ]]; then
        log_info "[$rpc_url] Staked on $staked_gossip_ep, we on $our_gossip_ep → another node has it"; return 0
    else
        log_info "[$rpc_url] Staked gossip = our own endpoint ($staked_gossip_ep) → nobody else has it"; return 1
    fi
}

check_standby_has_identity() {
    [[ -z "$VOTE_PUBKEY" ]] && { log_warn "VOTE_PUBKEY not set"; return 0; }

    local safe_count=0 total=0
    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        total=$((total + 1))
        _check_single_rpc "$rpc" && { log_info "STANDBY has identity — aborting recovery"; return 0; }
        safe_count=$((safe_count + 1))
    done

    [[ $safe_count -eq $total ]] && { log_info "All RPCs: no other node has staked identity"; return 1; }
    return 0
}

# --- Vote-liveness fence for rpc-recovery (v0.6.3 Block 2) ---
# Ported from the STANDBY/BACKUP takeover path: is the staked vote account producing votes right
# now? Topology-independent — it does not care which IP/port holds the identity, only whether
# SOMEONE is voting it. PRIMARY re-takes only when this says "frozen" (nobody voting).

# Echo "<lastVote> <tip> <tier>" for the staked vote account AND the answering RPC's own cluster tip,
# both from the SAME external RPC (Tier2 → Tier3) at commitment=processed, plus the tier label
# ("T2"/"T3") of the provider that answered (v0.7 Block 3 slice 2 — see below). The tip is an
# RPC-freshness reference (a stalled/cached RPC returns a frozen tip → cannot determine). Fields
# 1–2 are unchanged from v0.6.3, so two-field consumers keep working.
get_staked_liveness_sample() {
    local rpc vote_result lv ref tier _gls_rc
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
        vote_result=$(curl -s -m 10 "$rpc" -X POST \
            -H "Content-Type: application/json" -H "Cache-Control: no-cache" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts","params":[{"commitment":"processed"}]}' 2>/dev/null)
        _gls_rc=$?
        _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above) — post-op placement covers EVERY exit (success return, parse-continue, final loop exit); no-op outside the armed unit
        [[ $_gls_rc -eq 0 ]] || continue
        echo "$vote_result" | jq -e '.result' &>/dev/null || continue
        lv=$(echo "$vote_result" | jq -r \
            --arg vote "$VOTE_PUBKEY" \
            '(.result.current + .result.delinquent)[]? | select(.votePubkey == $vote) | .lastVote // empty' 2>/dev/null | head -1)
        [[ -n "$lv" && "$lv" =~ ^[0-9]+$ ]] || continue
        # Cluster-wide freshness reference = MAX lastVote from the SAME payload (one atomic snapshot,
        # advances every slot). See the standby copy for why this beats a decoupled getSlot tip
        # (cross-RPC / asymmetric-cache false-ALLOW).
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
# Returns: 0 = actively voting (advanced > epsilon)        → BLOCK recovery
#          1 = not voting (frozen across the interval)      → recovery may proceed
#          2 = cannot determine (externals down / too soon / backwards / RPC view stale /
#              provider flip across the pair — re-pins, see below) → BLOCK
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

# Drop the recovery vote-liveness samples so the next recovery episode starts fresh.
reset_recovery_liveness() { _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""; }

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
    local rpc result activated _agf_rc
    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        [[ -z "$rpc" ]] && continue
        # the liveness sampler's curl idiom ("Cache-Control: no-cache" defeats HTTP/CDN caches)
        result=$(curl -s -m 10 "$rpc" -X POST \
            -H "Content-Type: application/json" -H "Cache-Control: no-cache" \
            -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getAccountInfo\",\"params\":[\"${ALPENGLOW_FEATURE_ID}\",{\"encoding\":\"jsonParsed\"}]}" 2>/dev/null)
        _agf_rc=$?
        _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above) — post-op placement covers EVERY exit (success return, parse-continue, final loop exit); no-op outside the armed unit
        [[ $_agf_rc -eq 0 ]] || continue
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


attempt_safe_recovery() {
    local now elapsed
    now=$(mono_now)   # v0.7 (Block 3): SAFETY clock (RECOVERY_DELAY gate)
    # v0.7 (Block 3, slice 4 / AUDIT-5 S-3): recovery anchor = max(LAST_SWITCH_TIME,
    # _last_blind_end) — INVARIANT(blindness-is-life), the standby N3-anchor rule applied to the
    # rpc-recovery countdown. A blind stretch (externals down while recovery was eligible) must
    # make the FULL RECOVERY_DELAY re-elapse from the END of the last observed blind cycle: without
    # it, the re-take could fire off a post-blind pair only VOTE_LIVENESS_MIN_INTERVAL wide — ~10s
    # of observed silence standing in for the whole delay. bash has no ternary → max via if.
    recovery_anchor=$LAST_SWITCH_TIME
    if [[ ${_last_blind_end:-0} -gt $recovery_anchor ]]; then
        recovery_anchor=$_last_blind_end
    fi
    elapsed=$(( now - recovery_anchor ))

    if [[ $elapsed -lt $RECOVERY_DELAY ]]; then
        if [[ $(( now - _last_recovery_log )) -ge 60 ]]; then
            log_info "Recovery delay: $(( RECOVERY_DELAY - elapsed ))s remaining"; _last_recovery_log=$now
        fi
        reset_recovery_liveness   # v0.6.3 (Block 2): keep the sample fresh until recovery is eligible
        return 1
    fi

    # Check via Tier 1 first (fast)
    if tier1_check_delinquency; then
        log_info "Still delinquent (Tier 1) — not recovering"; _recovery_confirm_count=0; return 1
    fi

    # Confirm via Tier 2 (Alchemy)
    _check_rpc_delinquency "$TIER2_RPC" "TIER2-recovery"
    [[ $? -eq 0 ]] && { log_info "Still delinquent (Tier 2) — not recovering"; _recovery_confirm_count=0; return 1; }

    # v0.6.3 (Block 2): AUTHORITATIVE recovery fence — re-take staked ONLY if nobody is voting it.
    # If the staked vote account is advancing, the STANDBY (or someone) holds and votes it →
    # re-taking would double-sign. "cannot determine" also blocks (fail closed, invariant 3). This
    # replaces gossip-IP inference as the decision; the gossip ip:port check below stays as
    # advisory corroboration (it can still abort, which is always the safe direction for recovery).
    staked_is_actively_voting; local rec_liveness=$?
    # ── v0.7 (Block 3, slice 4) hunk (RATIFIED, 2026-08-17) — observation-span floor: a FROZEN
    # verdict resting on < VOTE_LIVENESS_MIN_SPAN seconds of the EPISODE's observed span is
    # demoted to "cannot determine yet" (see _liveness_span_short). Revert = delete this hunk
    # (one line + comment).
    if [[ $rec_liveness -eq 1 ]] && _liveness_span_short; then rec_liveness=2; fi
    # ── end slice-4 floor hunk ──
    if [[ $rec_liveness -eq 0 ]]; then
        [[ -z "$_standby_alert_sent" ]] && {
            alert_warn "⚠️ Recovery blocked: staked identity is ACTIVELY VOTING elsewhere (the STANDBY holds it). Manual switch-back needed."
            _standby_alert_sent=1
        }
        log_warn "Recovery blocked: staked identity actively voting (vote-liveness) — not re-taking"
        _recovery_confirm_count=0; return 1
    elif [[ $rec_liveness -eq 2 ]]; then
        log_info "Recovery: vote-liveness cannot be determined yet — holding"
        _recovery_confirm_count=0; return 1
    fi

    # Check if STANDBY took it (gossip ip:port — advisory corroboration; aborting recovery is safe)
    if check_standby_has_identity; then
        [[ -z "$_standby_alert_sent" ]] && {
            alert_warn "⚠️ STANDBY has staked identity. Manual switch-back needed."
            _standby_alert_sent=1
        }
        _recovery_confirm_count=0; return 1
    fi

    _recovery_confirm_count=$((_recovery_confirm_count + 1))
    log_info "Recovery check PASSED ($_recovery_confirm_count/$RECOVERY_CHECKS)"

    if [[ $_recovery_confirm_count -lt $RECOVERY_CHECKS ]]; then
        _watchdog_sleep "$RECOVERY_CHECK_INTERVAL"; return 1   # v0.7 (Block 5.2): chunked under the armed unit (plain sleep otherwise)
    fi

    _recovery_confirm_count=0; _standby_alert_sent=""
    switch_to_staked "Safe recovery: ${RECOVERY_CHECKS}x confirmed via tiered RPC after ${RECOVERY_DELAY}s" || true
}

# ========================= IDENTITY SWITCHING =================================

get_tower_path() { echo "${_cached_tower_base}/tower-1_9-${STAKED_PUBKEY}.bin"; }

# v0.6.8 (S4): pid of the running validator (any client), or empty if none is running.
_validator_pid() {
    local p; p=$(pgrep -x agave-validator 2>/dev/null | head -1)
    [[ -z "$p" && "$VALIDATOR_TYPE" == "frankendancer" ]] && p=$(pgrep -x fdctl 2>/dev/null | head -1)
    [[ -z "$p" ]] && p=$(pgrep -x solana-validator 2>/dev/null | head -1)
    printf '%s' "$p"
}

# ── [one-arm-state] shared classifier + startup refusal — BYTE-IDENTICAL in both daemons (test_one_arm_state) ──
# v0.7 (Block 5 skeleton, №1): after Block 5 there are TWO arm-states — DRY_RUN in the env, and
# WHICH fence unit file is installed (§2.3: arm-state IS which unit — structural, never an env
# flag). The two canonical paths are written ONLY by the future `failover arm` ceremony; NOTHING
# in this repository installs them, so on every host today (and on the macOS harness) neither
# path exists, _fence_unit_state answers "none", and the refusal below is STRUCTURALLY INERT.
FENCE_UNIT_REAL="/etc/systemd/system/solana-failover-fence.service"
FENCE_UNIT_PAGE_ONLY="/etc/systemd/system/solana-failover-fence-page-only.service"

# Echoes one of none|page-only|real. Pure `test -e` file classification — NO systemctl on this
# path (it runs at every startup, on bash 3.2 + macOS in the harness, and a hung systemctl must
# never wedge startup). page-only wins ONLY if the real unit is absent; BOTH present = `real` —
# an ambiguous arm state must fail TOWARD the №1 refusal (§2.3: ambiguity → inert + page), never
# toward "page-only" while a unit that can actually stop a validator sits installed.
_fence_unit_state() {
    if [[ -e "$FENCE_UNIT_REAL" ]]; then
        echo "real"
    elif [[ -e "$FENCE_UNIT_PAGE_ONLY" ]]; then
        echo "page-only"
    else
        echo "none"
    fi
}

# v0.7 (Block 5 skeleton, №1): ONE arm-state, enforced at startup (§2.3 [rev3/№1]). The deadly
# combination is DRY_RUN=true + the REAL fence unit: the fence can stop a LIVE validator while
# the operator believes the system inert — and it arises from exactly the gesture README teaches
# (sed -i DRY_RUN back to true "to switch off for a while"). Project rule: ambiguity → inert +
# page — REFUSE to start (the №3/unstaked-uniqueness fatal class) + CRITICAL page (the
# UNKNOWN-IDENTITY channel) naming BOTH alignment paths. DRY_RUN=false + page-only fence is the
# §2.3 table's third row — v0.6.x behavior, explicitly acceptable: WARN, not fatal. Every other
# combination is silent (normal). Inert wherever no fence unit exists (every host today).
_enforce_one_arm_state() {
    local _fus
    _fus=$(_fence_unit_state)
    if [[ "$DRY_RUN" == "true" && "$_fus" == "real" ]]; then
        log_error "FATAL: DRY_RUN=true but the REAL fence unit is installed ($FENCE_UNIT_REAL) — the fence can stop a live validator while the operator believes the system inert. REFUSING TO START (ambiguity → inert + page, §2.3). Align the arm-states: re-run 'failover arm' to install the page-only fence, or set DRY_RUN=false if arming was intended."
        alert "DRY_RUN=true + REAL fence unit installed — the fence can STOP a live validator while the operator believes the system inert. REFUSING TO START until the arm-states align: re-run 'failover arm' to install the page-only fence, or set DRY_RUN=false if arming was intended." "${STAKED_PUBKEY:-unknown}" "ONE ARM-STATE VIOLATION — REFUSING TO START 🚨"
        # v0.7 (Block 5 skeleton, reviewer fix): this daemon EXITS below — the pending-alert queue
        # drains ONLY in the main loop we are refusing to enter, so an undelivered page would sit
        # queued FOREVER (the next start refuses and queues again), and the refusal would be MUTE
        # on exactly the entry-blocker hosts (bash 5.2 pre-v0.6.10: Telegram delivery itself
        # broken). One bounded retry, then the journal states the OUTCOME — on a refusing daemon
        # journalctl is the only durable record, and it must say whether the push happened, not
        # merely that it was attempted. (The starvation page and TRIPWIRE BLIND re-ring from the
        # RUNNING loop; this path gets one shot — hence the explicit delivery check.)
        if [[ -n "$_pending_alert" ]]; then
            sleep 2
            flush_pending_alerts
        fi
        # (reviewer split): an empty _pending_alert has TWO meanings — the page WENT, or there
        # was NOWHERE to send it. On a path where the journal is the only durable channel,
        # "delivered" must never cover "no channel existed"; and "recorded NOWHERE" must not lie
        # when a webhook is configured (a real, fire-and-forget channel — delivery unverified).
        if [[ -n "$_pending_alert" ]]; then
            log_error "CRITICAL page NOT delivered — queued, but this daemon refuses to start and will not drain the queue; journalctl is your only record of this refusal."
        elif [[ "$TG_ENABLED" == "true" && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
            log_error "CRITICAL page delivered — refusing to start."
        elif [[ -n "$WEBHOOK_URL" ]]; then
            log_error "CRITICAL page went to the webhook only (Telegram not configured; webhook delivery is fire-and-forget, unverified) — journalctl is the authoritative record of this refusal."
        else
            log_error "CRITICAL page had NO channel (Telegram and webhook both unconfigured) — this refusal is recorded NOWHERE but this journal."
        fi
        exit 1
    fi
    if [[ "$DRY_RUN" != "true" && "$_fus" == "page-only" ]]; then
        log_warn "⚠️ [one-arm-state] fence is page-only — v0.6.x behavior: the daemon can take identities but the holder is not fenced (§2.3 third row, acceptable). Re-run 'failover arm' to install the real fence when the fleet is ready."
    fi
    return 0
}
# ── [one-arm-state] end shared block ──

# ── [watchdog] monitor-side fence integration — BYTE-IDENTICAL in both daemons (test_monitor_fence_integration) ──
# v0.7 (Block 5.2): the native-systemd-watchdog transport + pre-READY live extension + §2.2
# fence-marker consumption (DESIGN-v0.7-ADDENDUM §2.2/§2.6, design-records/
# research-systemd-watchdog.md, systemd/failover-fence.sh). STRUCTURALLY INERT on today's hosts,
# by construction: every watchdog function below no-ops unless PID 1 itself exported
# NOTIFY_SOCKET AND WATCHDOG_USEC into our environment (only the Block-5 monitor unit —
# Type=notify + WatchdogSec — does that, and NOTHING in this repository installs it), and the
# marker consumer acts only when a fence outcome marker actually exists under FENCE_MARKER_DIR
# (only the real fence (5.1) writes those; nothing installs it either). A v0.6.9-style host —
# the daemon under the old Type=simple unit, or run by hand — sees ZERO behavior change: no
# datagram, no startup probe, no chunked sleep, no marker action beyond two [[ -e ]] tests on
# files that do not exist there. Asserted, not asserted-in-prose: the inertness cases plus the
# zero-inertness grep-proof (no socat/NOTIFY_SOCKET reference outside this block) live in
# test_monitor_fence_integration.sh.

# Fence marker directory — MUST match the fence script's default (systemd/failover-fence.sh):
# the fence WRITES the §2.2 outcome markers there; this block CONSUMES them.
FENCE_MARKER_DIR="${FENCE_MARKER_DIR:-/var/lib/solana-failover}"

_WATCHDOG_READY=0              # set once READY=1 went out; pets gate on it (the watchdog arms at READY)
_fence_demoted_pending=0       # §2.2: a fenced-demoted marker awaits its first-clean-cycle clear (main loop)
_sd_notify_socat_logged=0      # socat-missing logged once per process
_last_sd_notify_fail_log=0     # failed-send log throttle (mono clock)

# The single activation gate for every watchdog mechanism in this block: TRUE iff PID 1 started
# us as the Type=notify monitor unit with WatchdogSec set — systemd exports NOTIFY_SOCKET for
# Type=notify and WATCHDOG_USEC only under WatchdogSec=, so both non-empty ⇔ under the armed
# unit. Structurally inert outside it: today's hosts and the test harness never set these, so
# every consumer takes its first-line return 0.
_watchdog_active() {
    [[ -n "${NOTIFY_SOCKET:-}" && -n "${WATCHDOG_USEC:-}" ]]
}

# One sd_notify datagram to $NOTIFY_SOCKET via socat — the systemd research record's chosen
# armed transport, mirrored exactly (design-records/research-systemd-watchdog.md, assumption 1,
# "Recommended concrete pet call": printf '%s' "$1" | socat -t0 - UNIX-SENDTO:"$NOTIFY_SOCKET";
# the @-abstract case split mirrors the fence's _fence_pet — the record's could-not-verify
# item 3). socat is unavoidably a forked CHILD of this shell, so the datagram's SCM_CREDENTIALS
# are socat's own, not the daemon's — the record's fork-and-exit attribution race applies to it
# as an auxiliary process on every target (the pidfd fix is systemd ≥ 257; the fleet ships
# 249–255). Per the 5.2 spec the payload therefore carries the MainPID claim (MAINPID=$$ — the
# daemon IS the unit's main PID, and bash expands $$ to the ORIGINAL shell's PID even inside
# $()-subshells, so pets sent from captured helpers claim the right PID) and the monitor unit
# sets NotifyAccess=all (without it PID 1 discards datagrams from non-main senders outright).
# Honest residual: a datagram whose socat already exited can still be dropped by the race —
# absorbed by the pet cadence (see _watchdog_pet's derivation), never by retry; a unix-datagram
# send is kernel-local, not the network-loss class.
# Bounded (timeout -k 2 5) + fire-and-forget: the rc is NEVER fatal — the watchdog FIRING is
# the failure semantics; a failed send logs at most once per ALERT_THROTTLE. socat missing →
# log once, return 0: the arm ceremony (5.3) hard-requires socat, and a running daemon must not
# die over a transport gap — under the armed unit the missed pets fence it via PID 1, which is
# the designed direction.
_sd_notify() {
    local _sn_rc _sn_now
    if ! command -v socat >/dev/null 2>&1; then
        if [[ "${_sd_notify_socat_logged:-0}" -eq 0 ]]; then
            _sd_notify_socat_logged=1
            log_warn "[watchdog] socat not found — cannot send sd_notify datagrams; under the armed unit PID 1 will fence on the missed pets (the arm ceremony hard-requires socat)"
        fi
        return 0
    fi
    case "$NOTIFY_SOCKET" in
        @*) printf '%s\nMAINPID=%s' "$1" "$$" | timeout -k 2 5 socat -t0 - "ABSTRACT-SENDTO:${NOTIFY_SOCKET#@}" >/dev/null 2>&1 ;;
        *)  printf '%s\nMAINPID=%s' "$1" "$$" | timeout -k 2 5 socat -t0 - "UNIX-SENDTO:${NOTIFY_SOCKET}" >/dev/null 2>&1 ;;
    esac
    _sn_rc=$?
    if [[ $_sn_rc -ne 0 ]]; then
        _sn_now=$(mono_now)
        if [[ $(( _sn_now - ${_last_sd_notify_fail_log:-0} )) -ge ${ALERT_THROTTLE:-600} ]]; then
            _last_sd_notify_fail_log=$_sn_now
            log_warn "[watchdog] sd_notify send failed (rc $_sn_rc) — never fatal; if pets keep failing PID 1 fires the watchdog after WatchdogSec (that IS the failure semantics)"
        fi
    fi
    return 0
}

# §5 per-op / per-cycle pet (WATCHDOG=1). Gated on the activation gate AND on READY having gone
# out (the watchdog arms at READY; pre-READY the startup path speaks EXTEND_TIMEOUT_USEC — B1).
#
# The A3 arithmetic — WatchdogSec=30 vs the REAL cycle, derived from this tree's actual bounds:
#   - Normal steady cycle (worst-case BOUNDS, healthy path): identity read 8 (timeout 8) +
#     internet ≤ 3 + tier-1 reads ≤ 10–16 (curl -m 5/10 × 2–3) + the inter-cycle sleep
#     (chunked — see below; counted here at the 3–5 s DEFAULTS) ≈ 24–32 s of bound. Typical
#     wall time is 1–6 s, but the BOUND already reaches WatchdogSec — one pet per cycle is not
#     enough even before any incident.
#   - Opt-in latency path (PRIMARY only, MAX_VOTE_LATENCY>0; shipped default 0 = off):
#     tier1_get_vote_latency adds 2 × curl -m 10 = 20 s of bound to the healthy staked cycle
#     (~49 s total) — outside the steady range above but inside the invariant: each added read
#     carries its own per-op pet, so the ≈ 22 s max-gap claim below is unchanged.
#   - Incident-path cycles COMPOUND bounds: a tiered confirm (curl -m 15 × 2 + -m 10), a
#     demote/take ladder (2 × (SETIDENTITY_TIMEOUT 15 + kill-grace 5) = 40), a hard stop
#     (stop 20 + mask 20 + kill-grace 3 + re-verify 15) and each page (Telegram -m 10 +
#     webhook -m 10) stack past ~170 s of bound inside ONE cycle.
# Therefore, per the A3 rule (worst case ≫ 15 s): pets fire ADDITIONALLY after EVERY bounded
# network/admin op (≥ 5 s bound) COMPLETES on the main-loop paths, EVERY main-loop/HOLD sleep
# goes through _watchdog_sleep (≤ 10 s chunks + a pet per completed chunk under the armed
# unit — so ANY legal CHECK_INTERVAL/TURBO_INTERVAL value is safe; no interval ceiling exists
# or is needed, and nothing here depends on the 3–5 s defaults), and an end-of-cycle pet
# closes every loop iteration. Resulting max inter-pet gap = the single longest bounded op +
# glue = (SETIDENTITY_TIMEOUT 15 + kill-grace 5) + ~2 ≈ 22 s < WatchdogSec 30 — at ZERO
# datagram loss. Honest residual, named: across a maximal 20 s op the gap exceeds
# WatchdogSec/2, so ONE discarded datagram immediately before such an op can stretch the
# observed gap past 30 s → a false fence. The discard class is kernel-local (PID 1
# notify-socket pressure / the record's fork-exit attribution race), not network loss.
# WHY THIS RESIDUAL NEEDS NO FIX (reviewer, 5.2 GO — the full argument, so the next reader does
# not "fix" it): look at WHICH ops create the 20 s class. (a) A set-identity/remove-all that ran
# to its full timeout = a WEDGED ADMIN SOCKET — exactly the condition the watchdog exists to
# fence; (b) systemctl stop inside the hard-stop = a node this daemon is already deliberately
# stopping. In both, the "false" fence lands on a node already heading to the same outcome by
# another path. The ONLY branch where the fence's outcome diverges from the daemon's intent is a
# wedged set-identity on the TAKE path (the daemon says TAKEOVER FAILED, never kill) — and there
# the spare still holds its unstaked identity, so the cost is availability only, never a
# double-sign. That is why the residual is ACCEPTED rather than engineered away: the INVARIANT
# below forbids the wrong fix (timer pets); this paragraph is why no fix is needed at all. The
# two levers (SETIDENTITY_TIMEOUT down, WatchdogSec up) remain E2E-gate material (§3.4),
# measured there, never asserted here.
# INVARIANT (load-bearing): a pet fires ONLY after an op completes — NEVER between an op's
# start and its completion — so a wedged admin call/curl stops the pet stream at its start and
# PID 1 fires after WatchdogSec: wedge detection IS the pets' absence. Do not "fix" a slow path
# by petting on a timer. COMPLETION includes a timeout return: rc 124/137 means `timeout`
# RETURNED — the monitor is alive and remediating — so every wedged-op branch pets BEFORE it
# escalates (hard stop / give-back escalate / unreachable-tier return); only an op that has
# not yet returned withholds pets.
_watchdog_pet() {
    _watchdog_active || return 0
    [[ "${_WATCHDOG_READY:-0}" -eq 1 ]] || return 0
    _sd_notify "WATCHDOG=1"
    return 0
}

# B1 (§2.2): READY=1 — sent ONLY after the first successful identity read (the startup wait
# loop's exit), plus the ONE documented HOLD exception (_consume_fence_markers). Enables the
# pets: WATCHDOG=1 is meaningless before the watchdog arms at READY.
_watchdog_ready() {
    _watchdog_active || return 0
    _WATCHDOG_READY=1
    _sd_notify "READY=1"
    log_info "[watchdog] READY=1 sent (first successful identity read) — WatchdogSec armed; per-op pets active"
    return 0
}

# B1 live-extension datagram. 60 s = 2× the wait-loop iteration's worst-case bound, derived:
# get_local_identity ≤ 8 (its own timeout) + _validator_pid ≈ 0 + _startup_phase_evidence ≤ 13
# (timeout -k 5, run bound 8 s) + sleep 5 = 26 s → ×2 = 52 → rounded UP to 60 (µs on the wire).
# The alert term (FF-1, fix round): the one-time H3 staked-unreachable alert (Telegram -m 10 +
# webhook -m 10 = 20 s bound) rides INSIDE a wait-loop iteration and is NOT in the 26 s base —
# uncorrected, an alert iteration that immediately FOLLOWS a one-iteration evidence flap
# composes to a 72 s EXTEND→EXTEND gap (the executed panel trace). The wait loop therefore
# re-sends EXTEND immediately BEFORE and immediately AFTER the alert (extend-after-bounded-op,
# mirroring per-op pets; both sends stay evidence-gated like every extension): pre-alert gap ≤
# flap 26 + sleep 5 + identity 8 + evidence 13 = 52 s < 60 (the pure-flap arithmetic),
# post-alert gap ≤ alert 20 + evidence 13 = 33 s < 60. Two CONSECUTIVE no-evidence probes
# still expire the deadline — that is the design (part-D (b)/(c): persistent no-evidence must
# time out into the fence), not a gap.
# Direction of the rounding, named: a too-SHORT deadline false-fences a healthy replaying
# validator (the §2.2 reboot brick — the exact bug live extension replaces); a too-LONG one
# delays a wedged start's fence by ≤ ~34 s, once, bounded — because a non-confirming iteration
# sends NOTHING at all (the deadline then simply expires).
_watchdog_extend_startup() {
    _watchdog_active || return 0
    _sd_notify "EXTEND_TIMEOUT_USEC=60000000"
    return 0
}

# B1: one wait-loop iteration's extension decision — extend iff POSITIVELY confirmed in
# startup/replay (process alive AND start-progress evidence); otherwise warn and send nothing
# (the deadline then expires into the fence path — the wait-loop call site carries the full
# part-D loop analysis). A separate helper so the wait-loop region stays sourceable bare in
# older seams (test_baseline_persistence P-e).
_watchdog_extend_if_starting() {
    _watchdog_active || return 0
    if [[ -n "$(_validator_pid)" ]] && _startup_phase_evidence; then
        _watchdog_extend_startup
    else
        log_warn "[watchdog] validator not positively in startup/replay — NOT extending the start timeout (a wedged start must time out into the fence path — §2.2)"
    fi
    return 0
}

# Watchdog-aware sleep for EVERY daemon sleep that can reach WatchdogSec: the ≥ 15 s sites
# (STARTUP_GRACE ×3, the primary's RECOVERY_CHECK_INTERVAL, the hard-stop re-verify) AND every
# main-loop/HOLD inter-cycle sleep (FF-B3/HOLD-B1, fix round: CHECK_INTERVAL/TURBO_INTERVAL
# are validated min-only — any legal operator value must be safe under the armed unit, so the
# inter-cycle sleep is CHUNKED rather than ceilinged). Under the armed unit a monolithic sleep
# ≥ WatchdogSec (30) starves the watchdog and false-fences a healthy, deliberately-idle
# monitor — so chunk to ≤ 10 s with a pet after each COMPLETED chunk (a chunk is a completed
# bounded op; the no-pet-mid-op invariant holds). OUTSIDE the unit: one plain `sleep`,
# byte-for-byte the old behavior — structural inertness.
_watchdog_sleep() {
    local _ws_left="$1" _ws_chunk
    if ! _watchdog_active; then
        sleep "$_ws_left"
        return 0
    fi
    case "$_ws_left" in ''|*[!0-9]*) sleep "$_ws_left"; return 0 ;; esac   # non-integer (no caller today) → plain
    while [[ $_ws_left -gt 0 ]]; do
        _ws_chunk=10
        [[ $_ws_left -lt 10 ]] && _ws_chunk=$_ws_left
        sleep "$_ws_chunk"
        _ws_left=$(( _ws_left - _ws_chunk ))
        _watchdog_pet
    done
    return 0
}

# §2.2 startup-phase evidence — BYTE-IDENTICAL twin of the FENCE's copy (systemd/
# failover-fence.sh; test_monitor_fence_integration asserts daemon↔fence byte-parity). ONE
# evidence definition at BOTH ends is load-bearing: the part-D dispatch-loop termination
# argument (see the wait-loop comment) holds only because what makes this daemon stop extending
# is exactly what makes the fence's third branch take the stop path on its next dispatch.
# agave-CLI-only (like the fence's copy): on a frankendancer box this probe fails → no
# extension → a long fd replay under the armed unit times out into the fence — consistent with
# the fence's documented fd-stop-only limitation (its header + systemd/README.md).
_startup_phase_evidence() {
    local out
    out=$(timeout -k 5 8 "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" monitor 2>&1)
    # Word-anchored: 'restarting' contains 'starting' and is READY-node noise, NOT startup
    # evidence (the false-positive direction on this branch is 'do not fence'). With -i the
    # [^a-z] class is case-insensitive too, so 'Restarting' is equally excluded.
    printf '%s' "$out" | grep -qiE '(^|[^a-z])(starting|startup)'
}

# B1 marker freshness — BYTE-IDENTICAL twin of the FENCE's copy (systemd/failover-fence.sh;
# test_monitor_fence_integration asserts the daemon↔fence byte-parity — a future divergence is
# a suite-visible parity break, deliberately: same-boot semantics must mean the same thing at
# BOTH ends, or one end honors a marker the other ignores).
_marker_same_boot() {
    local f="$1" up now boot mt
    up=$(awk '{ print int($1) }' "${FENCE_PROC_ROOT:-/proc}/uptime" 2>/dev/null)
    case "$up" in ''|*[!0-9]*) return 1 ;; esac
    now=$(date +%s 2>/dev/null)
    case "$now" in ''|*[!0-9]*) return 1 ;; esac
    boot=$(( now - up ))
    mt=$(stat -c %Y "$f" 2>/dev/null)                              # GNU/busybox stat (deploy hosts)
    case "$mt" in ''|*[!0-9]*) mt=$(stat -f %m "$f" 2>/dev/null) ;; esac   # BSD stat (macOS harness)
    case "$mt" in ''|*[!0-9]*) return 1 ;; esac
    [[ "$mt" -lt $(( boot + 60 )) ]] && return 1
    return 0
}

# ── §2.2 marker consumption (Block 5.2 part C) ── called FIRST in startup_checks (HOLD-1, fix
# round) — after the env is loaded, BEFORE every fatal startup gate (binary/keypair/one-arm/
# numeric/vote-liveness) and the validator wait, deliberately:
#   - a fenced-STOPPED node's identity is unreadable forever, so the wait loop would spin and
#     the HOLD page would never fire if this ran later;
#   - ANY fatal startup refusal that precedes this call would, on a fenced node under the armed
#     unit, loop monitor-exit → `failed` → OnFailure → fence-breaker → restart-monitor →
#     exit… forever (unbounded: StartLimitIntervalSec=0), paging or journal-spamming each pass;
#     entering HOLD first parks the node loudly instead, and the operator's post-recovery
#     restart re-runs every gate against the recovered state. This function needs only
#     FENCE_MARKER_DIR + the alert channels (STAKED_PUBKEY is guarded with :-unknown), so
#     running it first is sound.
# The page-only twin's marker (fenced-page-only) is deliberately IGNORED (§2.3: written by a
# DIFFERENT script in the un-armed state — never an input to the two-outcome state machine).
# NO marker → two [[ -e ]] tests and return: zero behavior change (assertable, asserted).
_consume_fence_markers() {
    local _m_stop="$FENCE_MARKER_DIR/fenced-stopped" _m_dem="$FENCE_MARKER_DIR/fenced-demoted" _hold_now _last_hold_page _hold_iv
    if [[ -e "$_m_stop" ]]; then
        if _marker_same_boot "$_m_stop"; then
            # §2.2 HOLD: the fence stopped — or, claim-more, could not VERIFY it stopped — the
            # validator THIS boot. Run NO takeover/recovery/self-fence logic; page CRITICAL,
            # re-page through ALERT_THROTTLE, poll the marker, and KEEP PETTING: a HOLD monitor
            # is alive and looping, and not petting would re-fire the fence against an
            # already-fenced node in a loop.
            log_error "[fence-marker] fenced-stopped (same boot) — HOLD: no monitoring logic runs; awaiting operator ($(head -1 "$_m_stop" 2>/dev/null))"
            alert "fenced-stopped — awaiting operator; unmask+start ONLY after confirming no spare holds the identity; clear ${FENCE_MARKER_DIR}/fenced-stopped to resume" "${STAKED_PUBKEY:-unknown}" "FENCED (stopped) — MONITOR IN HOLD 🚨"
            # The ONE documented exception to the B1 READY gate (READY only after an identity
            # read): the validator here is INTENTIONALLY down, so an identity read can never
            # succeed — without READY the unit's start would time out → `failed` → OnFailure →
            # the fence dispatches again, forever. READY in HOLD claims only "the monitor is
            # up, parked"; it claims nothing about the validator.
            # This implemented HOLD (READY=1 + continuous pets + throttled re-page) SUPERSEDES
            # addendum §2.2's ORIGINAL wording ("no watchdog re-arm, one CRITICAL page,
            # quiet") — ratified in the Block 5.2 spec (part C1): the original wording IS the
            # start-timeout → `failed` → OnFailure → re-fence loop this exception prevents,
            # and a pre-READY operator-clear exit 0 would land as a Type=notify "protocol"
            # failure → OnFailure → the fence re-writes fenced-stopped, silently undoing the
            # operator's clear.
            if _watchdog_active; then
                _WATCHDOG_READY=1
                _sd_notify "READY=1"
            fi
            # HOLD runs BEFORE numeric validation (marker consumption precedes every fatal
            # gate — HOLD-1), so sanitize the loop interval locally: garbage → 5.
            _hold_iv="${CHECK_INTERVAL:-5}"
            case "$_hold_iv" in ''|*[!0-9]*) _hold_iv=5 ;; esac
            _last_hold_page=$(mono_now)
            while [[ -e "$_m_stop" ]]; do
                heartbeat_ping   # the dead-man's switch stays live — observability, not monitoring logic
                _watchdog_pet    # a missed pet here would re-dispatch the fence in a loop
                _hold_now=$(mono_now)
                if [[ $(( _hold_now - _last_hold_page )) -ge ${ALERT_THROTTLE:-600} ]]; then
                    _last_hold_page=$_hold_now
                    alert "fenced-stopped — STILL awaiting operator; unmask+start ONLY after confirming no spare holds the identity; clear ${FENCE_MARKER_DIR}/fenced-stopped to resume" "${STAKED_PUBKEY:-unknown}" "FENCED (stopped) — MONITOR IN HOLD 🚨"
                fi
                _watchdog_sleep "$_hold_iv"   # FF-B3/HOLD-B1 (fix round): chunked under the armed unit — a legal CHECK_INTERVAL ≥ ~28 s must not starve WatchdogSec inside HOLD (plain sleep un-armed)
            done
            # Marker cleared by the operator → EXIT 0, deliberately not continue: a fresh start
            # re-runs EVERY startup check (keys, one-arm state, timing gates, the validator
            # wait) against the RECOVERED state — resuming mid-startup here would carry checks
            # validated against the pre-fence world. The unit is Restart=no: restarting the
            # monitor is the operator's explicit recovery step, not PID 1's.
            log_info "[fence-marker] fenced-stopped cleared by the operator — exiting 0 for a clean restart (Restart=no: restart the monitor as part of recovery)"
            alert_info "✅ fenced-stopped marker cleared — monitor exiting; restart it (systemctl start) to resume monitoring with fresh startup checks"
            exit 0
        fi
        # STALE (pre-boot) stopped marker: the host rebooted since the fence wrote it — nothing
        # it claims about "stopped" still holds, and the fence's own breaker no longer honors
        # stale markers. Same-boot semantics, BOTH ends — an asymmetry here would let one end
        # honor what the other ignores. Page once, monitor normally. The file is deliberately
        # NOT deleted (operator evidence; the page says clearing it is safe).
        # HOLD-3 (fix round): re-check existence first — the marker can VANISH between the
        # [[ -e ]] above and the freshness stat (an operator's clear mid-check lands here via
        # _marker_same_boot's failed stat), and paging "stale marker present — clearing it is
        # safe" about a file that no longer exists would lie. Vanished → silent normal startup
        # (exactly what the clear intended).
        if [[ -e "$_m_stop" ]]; then
            log_warn "[fence-marker] STALE fenced-stopped marker (pre-boot mtime) — ignoring; monitoring normally (same-boot semantics, both ends)"
            alert_warn "⚠️ stale fenced-stopped marker from a previous boot under ${FENCE_MARKER_DIR} — clearing it is safe; monitoring normally"
        fi
    fi
    if [[ -e "$_m_dem" ]]; then
        # §2.2: fenced-demoted, ANY age — a demoted marker only ever means "the fence demoted a
        # running validator", and normal monitoring re-verifies the running state immediately,
        # so marker freshness adds nothing here. Demoted-holder monitoring IS the existing main
        # loop (the UNSTAKED branch); this block owns only the marker's LIFECYCLE — cleared by
        # the monitor on its FIRST CLEAN CYCLE (the §2.2 contract), i.e. the first main-loop
        # cycle whose identity read succeeds (the hunk after the unreachable check).
        log_info "[fence-marker] fenced-demoted present ($(head -1 "$_m_dem" 2>/dev/null)) — normal demoted-holder monitoring; marker clears on the first clean cycle (§2.2)"
        alert_info "ℹ️ fence outcome: fenced-demoted — the fence demoted the validator (running, unstaked); monitoring resumes, marker clears on the first clean cycle"
        _fence_demoted_pending=1
    fi
    return 0
}
# ── [watchdog] end shared block ──

# v0.7 (Block 6.1): the [proof-gate] role adapter — deliberately OUTSIDE the byte-identical
# block below (the _rot_graceful_demote pattern: role facts stay per-daemon, the shared block
# stays byte-identical). The PRIMARY daemon is the HOLDER posture: its arm GENERATES pairing
# tokens (failover-arm.sh prints one at every holder arm) and never consumes one, and it has no
# attempt_takeover take path for the gate to guard. SCOPE, precise (panel N1, claim=check): post-
# failover a DEMOTED primary runs unstaked/spare-postured and CAN re-take the staked identity via
# attempt_safe_recovery under RECOVERY_MODE=rpc — a live, frozen/silence-flavored re-take. That
# re-take is DELIBERATELY outside this gate's scope: it is fenced by the pre-existing Block-2
# vote-liveness "frozen" check (v0.6.3) on the operator-gated recovery ladder, NOT by the proof
# gate — a deliberate scoping decision, not an oversight, and the seam Block 6.4 must honor when it
# wires the gate (6.4 owns that wording). Every [proof-gate] entrypoint below therefore no-ops
# here — the §2.7 unpaired scream must never page a healthy holder.
_proof_role_is_spare() { return 1; }

# ── [proof-gate] spare-side relinquish-proof gate skeleton — BYTE-IDENTICAL in both daemons (test_proof_gate) ──
# v0.7 (Block 6.1, BLOCK6-PLAN §0/§5): the gate that will stand in front of the STAKED mutation
# on the ARMED spare. COST MODEL (reviewer condition 1, binding for the whole block): Block 6's
# worst outcome is DOUBLE-SIGN — the spare taking while the holder is alive — so every ambiguity
# below fails toward NOT-TAKING and toward REFUSING (the inverse of Block 5's availability-first
# calculus). NOT WIRED into any take path in this slice (wiring is 6.4, the Block-5 skeleton
# pattern): every function here exists, is unit-tested, and is INERT everywhere today —
# armed-gated (first-line `_watchdog_active || return 0`) AND role-gated (_proof_role_is_spare,
# the per-daemon adapter defined just above this block — the _rot_graceful_demote pattern), so
# un-armed hosts see ZERO behavior change (census-asserted in test_proof_gate, not prose).
# PER-PROVIDER FLOORS [6.0-COND-1]: the gate imposes NO floor of its own — a floor is a
# property of what each proof STANDS ON, so floors live in the providers (6.2 verified-demote:
# its own DELTA hold + post-proof re-sample, NOTHING of W+B — it stands on a positive
# observation that the demoted state is live NOW, the polarity inversion G2 exists for; 6.3
# watchdog-elapsed: the token-derived elapsed_floor — it stands on time, the WEAKEST of the
# three evidence kinds, its chain made longer BY CONSTRUCTION: elapsed_floor >= TAKEOVER_DELAY
# is REFUSED at intake and re-asserted in _derive_proof_floors — never presumed). A
# global floor would punish the stronger proof with the longer wait and would move the
# live-tested un-armed 60 s path; TAKEOVER_DELAY is untouched by the whole block — it stays the
# un-armed path's own constant.
PROOF_STATE_DIR="${PROOF_STATE_DIR:-/var/lib/solana-failover}"   # MUST match failover-arm.sh ARM_STATE_DIR (the spare arm stores pairing-token there — the FENCE_MARKER_DIR precedent: one canonical dir, env-overridable as the test seam)

_proof_providers=""          # registered proof-provider fns, space-separated (6.2 registers verified-demote, 6.3 watchdog-elapsed; a future holder→spare channel lands here without touching the gate). empty registry — the gate REFUSES (fail toward not-taking).
_proof_provider_labels=""    # human provider names parallel to the registry (registration appends both) — the PAIRED posture prints MEASURED registry content, never a remembered claim (v0.7 Block 6.2)
_proof_last_verdict=""       # the last structured verdict the gate consumed/minted — one k=v| line, never a boolean (§3a.1/[rev3/№7])
_proof_token_st=""           # _proof_token_scan result: none|invalid|page-only|ok
_proof_token_gen=""          # parsed token fields (valid only when _proof_token_st is ok/page-only)
_proof_token_w=""
_proof_token_b=""
_proof_token_fence=""
_proof_unpaired_why=""       # _proof_unpaired_scan result ("" = paired ok)
_proof_floor_why=""          # _derive_proof_floors failure reason ("" = floor converged); names the non-converging/overflowed floor for the §2.7 page

# crc helper — BYTE-PARITY with failover-arm.sh's _pairing_crc (test_proof_gate cmp's all three
# copies): the 5.3 token emission's exact mechanics (`cksum | awk`; INTEGRITY, not security).
# The arm EMITS through its copy and the intake VERIFIES through it; this copy re-verifies at
# every read. A reimplementation here would let parse and emit drift — the S-1 twin class.
_pairing_crc() { printf '%s' "$1" | cksum 2>/dev/null | awk '{print $1}'; }

# one k=v field from a |-separated record (token line or verdict record) — the house `field`
# idiom (tests/lib/harness.sh field() speaks the same shape).
_proof_field() { printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

# _proof_token_scan — classify the STORED pairing token into _proof_token_st (none | invalid |
# page-only | ok) and fill _proof_token_gen/_w/_b/_fence (variables, not echo: callers need the
# fields in THIS shell — a $()-captured classifier would strand them in a subshell). The token
# is the 5.3 emission's exact shape: v0.7|gen=N|watchdog=W|relinquish_bound=B|fence=F|host=H|crc.
# crc re-verified at EVERY scan (claim=check: the intake verified at store time, but a file can
# rot on disk like any other; an unverifiable token is an INVALID token → the loud unpaired
# posture, never a silently-derived floor). fence=page-only is a VALID pairing that buys
# NOTHING on the time path (page-only relinquishes nothing — it pages), classified apart so the
# posture text can say why.
_proof_token_scan() {
    local _pts_f="$PROOF_STATE_DIR/pairing-token" _pts_line _pts_crc _pts_payload _pts_gen _pts_w _pts_b _pts_fence
    _proof_token_st=""; _proof_token_gen=""; _proof_token_w=""; _proof_token_b=""; _proof_token_fence=""
    if [[ ! -f "$_pts_f" ]]; then _proof_token_st="none"; return 0; fi
    _pts_line=$(head -1 "$_pts_f" 2>/dev/null)
    case "$_pts_line" in "v0.7|gen="*) : ;; *) _proof_token_st="invalid"; return 0 ;; esac
    _pts_crc="${_pts_line##*|}"; _pts_payload="${_pts_line%|*}"
    case "$_pts_crc" in ''|*[!0-9]*) _proof_token_st="invalid"; return 0 ;; esac
    [[ "$(_pairing_crc "$_pts_payload")" == "$_pts_crc" ]] || { _proof_token_st="invalid"; return 0; }
    _pts_gen=$(_proof_field "$_pts_line" gen); _pts_w=$(_proof_field "$_pts_line" watchdog)
    _pts_b=$(_proof_field "$_pts_line" relinquish_bound); _pts_fence=$(_proof_field "$_pts_line" fence)
    case "$_pts_gen" in ''|*[!0-9]*) _proof_token_st="invalid"; return 0 ;; esac
    case "$_pts_w"   in ''|*[!0-9]*) _proof_token_st="invalid"; return 0 ;; esac
    case "$_pts_b"   in ''|*[!0-9]*) _proof_token_st="invalid"; return 0 ;; esac
    _proof_token_gen=$((10#$_pts_gen)); _proof_token_w=$((10#$_pts_w)); _proof_token_b=$((10#$_pts_b))
    _proof_token_fence="$_pts_fence"
    case "$_pts_fence" in
        real)      _proof_token_st="ok" ;;
        page-only) _proof_token_st="page-only" ;;
        *)         _proof_token_st="invalid" ;;
    esac
    return 0
}

# _proof_unpaired_scan — sets _proof_unpaired_why from a fresh token scan ("" = paired ok, i.e.
# a valid fence=real token). Everything else is the §2.7 unpaired posture, with the reason.
_proof_unpaired_scan() {
    _proof_token_scan
    case "$_proof_token_st" in
        ok)        _proof_unpaired_why="" ;;
        none)      _proof_unpaired_why="no pairing token stored" ;;
        page-only) _proof_unpaired_why="token fence=page-only — page-only relinquishes nothing" ;;
        *)         _proof_unpaired_why="stored pairing token invalid (crc/shape)" ;;
    esac
    return 0
}

# ── _derive_proof_floors — THE derivation site (§3a.3: derived, not configured) ────────────────
# ONE site per daemon (twin): NO other script re-declares elapsed_floor / MARGIN_ELAPSED /
# N_HEAD — test_proof_gate censuses the assignment sites (the N-is-all rule applied to
# constants, allowlist style). Armed-only and token-fed: the floors exist ONLY when a valid
# fence=real token is stored — the right to use time as proof is exactly what attestation buys
# (the condition-4 comment at the gate below). G2's DELTA does NOT live here — it is 6.2's,
# per-provider (a positive-observation hold; no W+B component).
_derive_proof_floors() {
    _watchdog_active || return 0
    _proof_token_scan
    _proof_floor_why=""
    [[ "$_proof_token_st" == "ok" ]] || { _proof_floor_why="no valid fence=real pairing token (state=${_proof_token_st})"; return 1; }
    # MARGIN_ELAPSED — the slack between the elapsed floor and W+B. It IS the staleness
    # allowance the independent-head cross-check enforces: the two are COUPLED BY DERIVATION
    # (N_HEAD below is computed FROM this value), so raising the staleness tolerance visibly
    # raises the floor — never one without the other.
    MARGIN_ELAPSED=10
    # elapsed_floor = W + B + MARGIN_ELAPSED (=100 at the shipped W=30/B=60): the
    # watchdog-elapsed provider's floor — silence measured on the spare's mono clock must reach
    # this before attested time counts as proof (provider lands in 6.3).
    elapsed_floor=$(( _proof_token_w + _proof_token_b + MARGIN_ELAPSED ))
    # N_HEAD [6.0-COND-3] — derived from what the cross-check GUARDS, never from B: a liveness
    # view lagging the true head by X seconds freezes the spare's last-seen-liveness stamp, so
    # measured silence OVERSTATES true silence by <= X; soundness of the elapsed floor needs
    # measured - X >= W + B, i.e. X <= MARGIN_ELAPSED. N_HEAD = slots(MARGIN_ELAPSED) =
    # 2.5 slots/s x MARGIN_ELAPSED (integer form *5/2; = 25 slots = 10 s today). Staleness
    # beyond the allowance reads as BLIND (wait) — availability, never safety.
    # [6.3 reviewer pre-registration, recorded here BEFORE anyone is under pressure] N_HEAD may
    # NOT be loosened alone. 25 slots is ~10 s of chain — tight for public RPC, and Block 10 may
    # well measure vantages failing this cross-check with takeovers starving. The correct response
    # is then to raise MARGIN_ELAPSED, which raises the elapsed floor WITH it through the line
    # below; relaxing N_HEAD on its own would buy availability by silently widening the staleness
    # a sound floor must exclude. The coupling IS the property this derivation exists for —
    # decoupling it under availability pressure is the most natural and the most wrong move.
    N_HEAD=$(( MARGIN_ELAPSED * 5 / 2 ))
    # convergence backstop [6.0-COND-1] (panel L-1): in honest arithmetic the floor W+B+MARGIN is
    # ALWAYS > 0 and >= W and >= B (W,B >= 0, MARGIN > 0), so a violation PROVES 64-bit integer
    # overflow — a token whose watchdog (or bound) is large enough that the sum wrapped past 2^63.
    # BOTH wrap directions are fatal and BOTH fail toward NOT-TAKING: a non-positive floor makes the
    # 6.3 predicate `measured_silence >= floor` true for ANY silence incl. 0 (take-on-no-silence,
    # the double-sign), and a floor that no longer dominates its own inputs is the "never converges
    # = broken gate" the plan pre-registered against. Correct REGARDLESS of the arm ceiling (defense
    # in depth): a token planted straight on disk, or fed from any future env source, that bypassed
    # intake still fails safe HERE. On failure the floor is INVALID → return non-zero;
    # _proof_startup_check routes to the §2.7 unpaired posture + a CRITICAL page that names the
    # non-converging floor, NEVER a healthy PAIRED line.
    if [[ $elapsed_floor -le 0 || $elapsed_floor -lt $_proof_token_w || $elapsed_floor -lt $_proof_token_b ]]; then
        _proof_floor_why="derived watchdog-elapsed floor ${elapsed_floor} did not converge (watchdog=${_proof_token_w}, relinquish_bound=${_proof_token_b}, margin ${MARGIN_ELAPSED}) — arithmetic overflow: the floor must be > 0 and >= watchdog and >= relinquish_bound"
        return 1
    fi
    # floor-vs-timer MINIMUM backstop (6.1 reviewer condition; defense in depth like the
    # convergence assert above — the intake refuses this pairing at P5, so reaching here means
    # the token bypassed intake, the daemon was re-configured after pairing, or a future feed
    # skipped the ceremony): arming must never make the spare FASTER to take than not-arming.
    # watchdog-elapsed stands on time — the WEAKEST of the three evidence kinds — so its floor
    # must be >= the un-armed timer path's TAKEOVER_DELAY by construction, not by presumption.
    # A non-numeric/unset TAKEOVER_DELAY is cannot-verify -> invalid floor (fail toward
    # NOT-TAKING; on the holder-role daemon the section-2.7 consumer is role-gated, so an
    # invalid floor stays inert data there).
    local _pdf_delay
    _pdf_delay="${TAKEOVER_DELAY:-}"
    case "$_pdf_delay" in ''|*[!0-9]*)
        _proof_floor_why="cannot check the elapsed floor against the un-armed timer path: TAKEOVER_DELAY='${_pdf_delay:-unset}' is not numeric (cannot-verify fails toward NOT-TAKING)"
        return 1
    ;; esac
    if [[ $elapsed_floor -lt $((10#$_pdf_delay)) ]]; then
        _proof_floor_why="derived elapsed_floor ${elapsed_floor}s is SHORTER than the un-armed timer path TAKEOVER_DELAY=${_pdf_delay}s (watchdog=${_proof_token_w}, relinquish_bound=${_proof_token_b}, margin ${MARGIN_ELAPSED}) — arming must never make the spare FASTER to take than not-arming; the intake refuses this pairing, so this token bypassed intake or the delay changed after pairing"
        return 1
    fi
    return 0
}

# ── require_relinquish_proof — the gate shell (BLOCK6-PLAN §0) ─────────────────────────────────
# THE CONDITION-4 COMMENT (at the gate, where the temptation lives): attestation buys exactly
# ONE thing — the RIGHT to use time as proof, at the bounds the token carries. The token is
# pairing METADATA, not holder state: it says the holder was ARMED with (watchdog,
# relinquish_bound, fence=real) at pairing generation N; it does NOT say the fence is alive NOW
# (rot is invisible to the spare by design, §2.1 — the holder self-enforces via [fence-rot]).
# The tempting shortcut — "we are paired, therefore the holder is v0.7, therefore its watchdog
# will fence it" — is CLOSED here: pairing speaks of configuration at generation N, never of
# what that box is doing now.
# Consumes/mints a STRUCTURED verdict, never a boolean (§3a.1/[rev3/№7]) — one k=v| line:
#   proven= provider= observation_id= vantage= obs_since= blind_until= observed_at=
# where vantage/obs_since/blind_until are the Block-3 freshness triple fed FROM the existing
# seam globals (_liveness_first_provider / _liveness_obs_since / _last_blind_end — NO second
# freshness system; suites read the triple ONLY via dump_freshness, the S-1 twin-drift rule)
# and observed_at is a MONO stamp of the LAST read the verdict rests on (0 = none).
# Returns: 0 = accepted proof — or the gate does not exist behaviorally (un-armed / non-spare:
# v0.6.x take semantics unchanged, zero new reads, zero new refusals); 1 = REFUSED (no accepted
# proof → no take); 2 = BYPASSED (ALLOW_UNFENCED_TAKEOVER=true, the existing double-opt-in
# lever) — a DISTINCT outcome so the 6.4 wiring inherits the per-take scream point without
# redesign: the CRITICAL page fires HERE at the bypass itself (§2.6 every-start-scream class;
# the every-START half lives in _proof_startup_check). 6.4 must case on 2 explicitly — a bare
# `|| return 1` would read bypassed as refused (safe direction, but not the lever's contract).
require_relinquish_proof() {
    _watchdog_active || return 0
    _proof_role_is_spare || return 0
    local _rrp_prov _rrp_v _rrp_n=0 _rrp_posture
    if [[ "${ALLOW_UNFENCED_TAKEOVER:-false}" == "true" ]]; then
        _proof_last_verdict="proven=bypassed|provider=operator-override|observation_id=|vantage=${_liveness_first_provider:-}|obs_since=${_liveness_obs_since:-0}|blind_until=${_last_blind_end:-0}|observed_at=$(mono_now)"
        alert "ALLOW_UNFENCED_TAKEOVER=true — this take BYPASSES the relinquish-proof gate (no proof the holder relinquished; double-sign risk). Unset the lever unless this is a deliberate, temporary override." "${STAKED_PUBKEY:-unknown}" "PROOF GATE BYPASSED 🚨"
        return 2
    fi
    for _rrp_prov in $_proof_providers; do
        _rrp_n=$((_rrp_n + 1))
        _rrp_v=$("$_rrp_prov") || _rrp_v=""
        [[ -n "$_rrp_v" ]] || continue
        _proof_last_verdict="$_rrp_v"
        if [[ "$(_proof_field "$_rrp_v" proven)" == "yes" ]]; then
            log_info "[proof-gate] relinquish proof ACCEPTED — provider=$(_proof_field "$_rrp_v" provider) observation=$(_proof_field "$_rrp_v" observation_id) (the freshness age bound is enforced at the MUTATION EDGE by _proof_age_edge_check, not here)"
            return 0
        fi
    done
    # no provider proved (today: zero providers are registered — the skeleton refuses).
    # claim=check on the posture text: the §2.7 line describes the UNPAIRED posture; a PAIRED
    # spare that merely lacks providers gets the factual variant instead.
    _proof_token_scan
    if [[ "$_proof_token_st" == "ok" ]]; then
        _rrp_posture="holder attested (token gen=${_proof_token_gen}) but no registered provider proved relinquish"
    else
        _rrp_posture="proof providers: verified-demote ONLY — holder not attested; silence-based take disabled — upgrade/pair the holder (arm prints the token)"
    fi
    _proof_last_verdict="proven=no|provider=none|observation_id=|vantage=${_liveness_first_provider:-}|obs_since=${_liveness_obs_since:-0}|blind_until=${_last_blind_end:-0}|observed_at=0"
    log_warn "[proof-gate] REFUSE: no accepted relinquish proof — MEASURED: providers registered=${_rrp_n}, proven verdicts=0; REQUIRED: >=1 accepted proof (fail toward NOT-TAKING). ${_rrp_posture}"
    return 1
}

# ── _proof_age_edge_check [6.0-COND-2] — verdict freshness enforced AT THE MUTATION EDGE ───────
# Designed to sit AFTER _fresh_proof_recheck, INSIDE the zero-network span, immediately before
# set-identity (wiring is 6.4) — a clock-only (mono) comparison, because the recheck itself
# reads the network and an acceptance-time check would leave the proof up to
# PROOF_MAX_AGE + R_worst old at set-identity.
#
# PROOF_MAX_AGE — DERIVED, not picked (the [6.0-COND-2] verdict→mutation arithmetic), from a
# census of EVERY read between verdict acceptance and set-identity in the CURRENT standby take
# path (attempt_takeover → take_staked_identity → _fresh_proof_recheck → mutation; the slice-5
# A8 census holds: zero network after the recheck's return-0):
#   R_worst — the edge-REACHABLE worst of the ONE read in the span, the recheck's sampler call
#   (get_staked_liveness_sample), under the ARMED unit (the gate only exists armed):
#       2 x curl -m 10                    = 20 s   (T2 full timeout + T3 slow SUCCESS; a
#                                                   both-timeout run ABORTS the recheck, so the
#                                                   edge is never reached on that path)
#       2 x per-op pet (timeout -k 2 5)   = 14 s   (5 s + 2 s kill-grace each, the house
#                                                   bound-counting)
#       parse/clock glue (3 jq + mono_now) =  2 s
#                                  R_worst = 36 s
#   acceptance_slack (gate-accept → recheck entry: tier_summary string glue; bounded ops
#   censused ZERO)                          =  3 s
#   margin (scheduler/load headroom, ~28 % of the 39 s worst reachable span, rounded to land
#   the budget on a round figure; rounding UP loosens the budget — the unsafe direction — by
#   < 1 s, absorbed by the composition below) = 11 s
#   PROOF_MAX_AGE = 36 + 3 + 11             = 50 s
# HEALTHY PATH (typical one-curl success ~1 s + glue): verdict age at the edge ≈ 2–4 s — ≥ 12x
# under the budget; the worst REACHABLE path (39 s) clears it by 11 s: convergence proven WITH
# margin (the slice-4 floor lesson — a bound right in meaning that never converges is a broken
# gate). NOTE (reviewer condition C2, claim=check): this number and G2's DELTA were briefly EQUAL
# (both 50) and the comment here said so — a numeric coincidence, never a derivation. G2_DELTA is
# now 60 (the research record's figure, restored once per-provider floors retired the timer-fit
# constraint) and the coincidence is gone. They remain DIFFERENT OBJECTS — a positive-observation
# hold DURATION vs a verdict STALENESS bound — and nothing here reads the other: no code path
# assumes any ordering between PROOF_MAX_AGE and G2_DELTA (the provider's own withdrawal compare
# below is age-vs-PROOF_MAX_AGE, never hold-vs-age). Do not unify them, and do not re-derive one
# from the other if they collide again.
# COMPOSITION (why age-check + recheck TOGETHER, not either alone): the recheck's staked-vote
# pin owns the flip-back-then-vote direction — a holder that re-takes and votes AFTER the
# verdict's last read lifts lastVote above the episode's pinned min-rule baseline and ABORTS at
# the final re-check; NO snapshot-based verdict can see that direction. The edge check owns the
# other axis: it bounds how stale the verdict's newest evidence may be at the mutation instant
# (the recheck cannot know what the verdict rested on). The pin bounds BEHAVIOR; the edge check
# bounds STALENESS — they compose, they do not merge (each system reads ONCE per decision; the
# recheck's staked-lastVote pin and the verdict's observation stay DIFFERENT OBJECTS).
PROOF_MAX_AGE=50
_proof_age_edge_check() {
    _watchdog_active || return 0
    _proof_role_is_spare || return 0
    local _pae_obs _pae_age
    _pae_obs=$(_proof_field "${_proof_last_verdict:-}" observed_at)
    # no 0-sentinel arithmetic (the reviewer's Block-3 class note): observed_at absent/0/garbage
    # means NO read backs the verdict — refuse outright, never compute now-0.
    case "$_pae_obs" in ''|0|*[!0-9]*)
        log_warn "[proof-gate] edge check REFUSE: the verdict carries no usable observed_at ('${_pae_obs:-}') — a proof with no read behind it is not fresh, it is absent (fail toward NOT-TAKING)"
        return 1
    ;; esac
    _pae_age=$(( $(mono_now) - _pae_obs ))
    # symmetric clamp (panel L-2): observed_at absent/0/garbage is refused above; the MIRROR case is
    # observed_at > mono_now (age < 0) — a verdict stamped AHEAD of this spare's mono clock. A verdict
    # from the future is not fresh, it is impossible (clock inversion / vantage skew); like the
    # 0-sentinel case it fails toward NOT-TAKING rather than reading "fresh". Closed now, before
    # 6.2/6.3 mint observed_at from independent network/vantage reads (the plan's own skew attacks).
    if [[ $_pae_age -lt 0 ]]; then
        log_warn "[proof-gate] edge check REFUSE: verdict observed_at is in the FUTURE — MEASURED: verdict age ${_pae_age}s (observed_at ahead of this spare's mono clock); REQUIRED: age >= 0. A proof from the future is impossible, not fresh (clock inversion / skew) — fail toward NOT-TAKING"
        return 1
    fi
    if [[ $_pae_age -le $PROOF_MAX_AGE ]]; then
        return 0
    fi
    log_warn "[proof-gate] edge check REFUSE: proof STALE at the mutation edge — MEASURED: verdict age ${_pae_age}s; REQUIRED: <= ${PROOF_MAX_AGE}s (PROOF_MAX_AGE, derived above). The take must re-prove (fail toward NOT-TAKING)"
    return 1
}

# ── the §2.7 LOUD unpaired state [6.0-COND-4] — every-start scream + standing status line ──────
# An armed spare with no (or invalid) pairing token — or a fence=page-only token, for the time
# path — can still take via verified-demote (6.2) but NEVER on silence, and that must SCREAM,
# not sit in a doc: (a) a CRITICAL page at EVERY daemon startup (the safety-page channel;
# called from startup_checks in both daemons — deliberately UNTHROTTLED across restarts, the
# §2.6 every-start-scream rule, same class as ALLOW_UNFENCED_TAKEOVER), and (b) a standing
# line on the periodic status surface (the v0.6.4 ♥ Heartbeat block — called from the main
# loop's heartbeat site, once per HEARTBEAT_INTERVAL, same wording every interval).
_proof_startup_check() {
    _watchdog_active || return 0
    _proof_role_is_spare || return 0
    if [[ "${ALLOW_UNFENCED_TAKEOVER:-false}" == "true" ]]; then
        # the 6.1 half of the lever integration: the every-START scream (the per-take half is
        # the gate's `bypassed` outcome above).
        alert "ALLOW_UNFENCED_TAKEOVER=true on an ARMED spare — every take will BYPASS the relinquish-proof gate (no proof the holder relinquished; double-sign risk). Unset the lever unless this is a deliberate, temporary override." "${STAKED_PUBKEY:-unknown}" "PROOF GATE BYPASS ARMED 🚨"
    fi
    _g2_register   # v0.7 (Block 6.2): register the verified-demote provider (armed+spare already gated above; self-gates on PRIMARY_UNSTAKED_PUBKEY + vantage config) BEFORE the posture lines below, so they print the real registry
    _proof_unpaired_scan
    if [[ -z "$_proof_unpaired_why" ]]; then
        if _derive_proof_floors; then
            log_info "[proof-gate] armed spare PAIRED: token gen=${_proof_token_gen} (watchdog=${_proof_token_w}s, relinquish_bound=${_proof_token_b}s, fence=real) → elapsed_floor=${elapsed_floor}s, N_HEAD=${N_HEAD} slots (proof providers registered: ${_proof_provider_labels:-NONE}; the gate is not wired into any take path)"
            return 0
        fi
        # a VALID-shape fence=real token whose floor did NOT converge (the overflow/wrap backstop
        # above): an INVALID pairing, not a healthy PAIRED spare — the §2.7 CRITICAL page, naming
        # the non-converging floor, NEVER the PAIRED line (fail toward NOT-TAKING).
        alert "armed spare pairing INVALID — ${_proof_floor_why}; a corrupted/forged, overflowing, or mis-bounded token is NOT a healthy pairing — silence-based take stays DISABLED. Re-arm the holder and re-pair this spare with a fresh token." "${STAKED_PUBKEY:-unknown}" "ARMED SPARE NOT ATTESTED 🚨"
        return 0
    fi
    alert "proof providers: verified-demote ONLY — holder not attested (${_proof_unpaired_why}); silence-based take disabled — upgrade/pair the holder (arm prints the token)" "${STAKED_PUBKEY:-unknown}" "ARMED SPARE NOT ATTESTED 🚨"
    return 0
}
_proof_status_line() {
    _watchdog_active || return 0
    _proof_role_is_spare || return 0
    _proof_unpaired_scan
    [[ -z "$_proof_unpaired_why" ]] && return 0
    log_info "[proof-gate] proof providers: verified-demote ONLY — holder not attested (${_proof_unpaired_why}); silence-based take disabled — upgrade/pair the holder (arm prints the token)"
    return 0
}
# ── [proof-gate] end shared block ──

# v0.7 (Block 6.2): the [g2-provider] incident adapter — per-daemon, deliberately OUTSIDE the
# byte-identical region below (the _proof_role_is_spare pattern). The PRIMARY daemon is the
# HOLDER posture: it has no takeover episode surface for G2 to key on, and every [g2-provider]
# entrypoint is already role-gated off by _proof_role_is_spare above. This adapter exists so the
# twin region parses identically in both daemons; it must never answer "active" here — G2 proving
# a relinquish TO the holder would be proving the wrong thing to the wrong box.
_g2_incident_active() { return 1; }

# ── [g2-provider] verified-demote (G2) proof provider — BYTE-IDENTICAL in both daemons (test_g2_provider) ──
# v0.7 (Block 6.2, DESIGN-v0.7-ADDENDUM §2.4 + [rev3/№2], BLOCK6-PLAN §2): the first REAL proof
# provider behind the [proof-gate] registry. COST MODEL (reviewer condition 1, binding): the worst
# outcome is DOUBLE-SIGN — the spare taking while the holder is alive — so G2 is a PROOF provider,
# not a detector: every ambiguity below answers cannot-determine or not-proven, NEVER proven. A
# forged or degenerate environment (cached RPC, replayed snapshots, one provider behind two names)
# must never mint a proven verdict; what it CAN cost is availability (G2 stays silent and the
# un-armed timer path governs — the gate is NOT wired into any take path in this slice; 6.4 wires).
#
# WHAT G2 PROVES (polarity, §2.4): the holder's UNSTAKED ContactInfo observed at the STAKED
# identity's exact gossip endpoint at T1 AND still present >= G2_DELTA later on the SAME two
# pinned vantages proves "the demoted state is live NOW" — a live publisher re-signs its unstaked
# ContactInfo every ~7.5 s and a stale (publisher-gone) entry cannot survive 30 s in a remote CRDS
# table (15 s unstaked-origin expiry + <= 15 s late re-insert bound, expiry on each vantage's own
# LOCAL wall clock — design record research-crds-staked-timeout.md, source-verified). A live
# publisher holding the unstaked key on THAT box means the box cannot sign staked votes (the vote
# gates). This is NOT "the flip happened once" — it is a positive, current observation, which is
# why G2's floor is its own DELTA hold and carries NOTHING of W+B ([6.0-COND-1], per-provider).
# WHAT G2 CANNOT SEE (D2 composition, stated again at the minting site): flip-back-then-vote after
# the T2 read — the recheck's staked-vote pin owns that direction at the mutation edge (6.4), and
# _proof_age_edge_check bounds this verdict's staleness there (observed_at = the T2 read).
#
# THE ANTI-FORGERY LAYER SET (enumerated so "complete guard set" stays a measured claim, not a
# remembered one — the D3 multilayer controls in test_g2_provider neuter each one ALONE and prove
# the fall-through, then neuter ALL of them and prove the forged acceptance comes back):
#   [g2-det-batch]         the snapshot answer must BE a 2-element JSON-RPC batch response
#   [g2-det-batch-id]      every member (and the getBlockTime read) must echo OUR fresh id
#   [g2-det-slot-advance]  the vantage's own confirmed head, batched INTO the proof-bearing
#                          response, must advance >= G2_SLOT_ADVANCE_FLOOR across the hold
#   [g2-det-clock]         getBlockTime(that batched slot) within ±G2_CLOCK_BUDGET of this clock
#   [g2-det-advance-a/-b]  the vantage's node table must not be byte-frozen across the hold
#   [g2-det-crossvantage]  the two vantages must not serve byte-identical node tables
# plus, at ceremony time only: REFUSE[P6-batch] (this vantage can serve the batch at all) and
# REFUSE[P6-vantage] (the two vantage names do not resolve to one address set).
# WHAT THE SET DOES NOT DEFEAT (named residual, design record verify-rpc-batch-and-churn.md §4,
# private tree; restated in SAFETY.md): an ACTIVE, PROTOCOL-AWARE intermediary that splits our
# batch, forwards getSlot to a live node and answers getClusterNodes from storage under our id.
# Binding the anchor raises the bar from passive cache / naive replay to that; it does not clear
# it, and no unsigned snapshot protocol can.
#
# EPISODE VS THE SPARE'S OWN STAKED TENURE (panel fix round, L3-N1): _g2_step is scoped to the
# spare posture, so a promoted spare stops stepping — but the half-run attempt and its T1 anchors
# merely PAUSED in memory. Executed: a manual set-identity interlude (staked at t=16, unstaked
# again at t=34) let the attempt RESUME and mint within seconds of re-demotion, on T1 stamps that
# predate the spare's own staked tenure, with every mid-hold poll of the gap skipped. The spare
# daemon therefore calls _g2_reset at its STAKED-branch entry (a per-daemon call site, censused in
# test_g2_provider (9d)).
# WHY THE RESUMED HOLD WAS NOT UNSOUND, recorded per claim=check — this is hygiene, not a forgery
# fix: the mint is T2-ANCHORED. Proven requires the unstaked entry PRESENT at a FRESH T2 read, and
# a stale entry cannot outlive the <= 30 s CRDS bound; a holder that re-staked during the gap
# stops re-signing it, so T2 comes back absent -> not-proven. Missed mid-hold polls remove EARLY
# kills, they never add evidence. Resetting anyway makes the invariant checkable without that
# argument: an attempt never spans the spare's own staked tenure.
#
# STRUCTURALLY INERT everywhere today: every entrypoint no-ops unless _watchdog_active AND
# _proof_role_is_spare AND registered (PRIMARY_UNSTAKED_PUBKEY configured) — zero reads, zero
# events, zero state on every un-armed host (census-asserted in test_g2_provider, not prose).
# A PER-CYCLE STATE MACHINE, never a blocking wait: _g2_step advances at most ONE bounded batch
# per main-loop cycle and NEVER sleeps (zero sleep sites in this region, census-asserted).
# Worst added gap per cycle (the A3-style bound census, all sites in this region — re-derived in
# the panel fix round: the JSON-RPC BATCH merges the old getSlot read into the getClusterNodes
# read, so a snapshot is now TWO reads, not three):
#     idle (baseline refresh, cadence-gated) : 1 x curl -m 5  + 1 pet (7 s)          = 12 s
#     t1a/t1b/t2a/t2b (batch + getBlockTime) : 2 x curl -m 5  + 2 pets               = 24 s
#     hold (cheap presence poll)             : 1 x curl -m 5  + 1 pet                = 12 s
#     proven / disabled / unregistered       : zero reads                            =  0 s
# Worst case 24 s — the same class as the existing per-cycle externals (confirm + liveness, two
# curl -m 10 each) and always in the SAFE direction: a slow G2 cycle can only make this spare see
# its own take gates LATER, never earlier. Each read is petted post-op (a timeout return IS
# completion — the FF-B1 rule); _G2_READ_PACE_SECS floors the read cadence so the 1 s turbo loop
# cannot hammer the vantages. G2 state is DELIBERATELY memory-only (never in save_state): a T1
# anchor restored into a restarted daemon would be exactly the stale-anchor class this house
# refuses — a restart mid-incident answers cannot-determine (no baseline) and the timer governs.

# [§2.4 derivation — the ONE declaration site; census-asserted, injection-red in the suite]
# G2_CLOCK_BUDGET: the vantage clock-error budget (seconds) — how far a vantage's view of cluster
# wall time may sit from this spare's wall clock in EITHER direction before its snapshots are
# untrustworthy for freshness. G2_DELTA derives FROM it, and the derivation is the project's own
# research record's (design-records/research-crds-staked-timeout.md:94 — "Minimal provably
# sufficient DELTA = 30s + max tolerated vantage clock error. Recommend DELTA = 60s (covers 30s
# bound + purge granularity + a generous 25s+ vantage clock-error budget)"):
#     30 s  provable CRDS bound: 15 s unstaked-origin expiry + <= 15 s late re-insert window
#   + 25 s  G2_CLOCK_BUDGET — the clock-error budget that record calls for; its :95 residual
#           ("both clocks being >25s wrong simultaneously") is stated AGAINST this number, so a
#           SMALLER budget widens that residual instead of narrowing it
#   +  5 s  purge granularity (the ~100 ms gossip-loop purge pass) + rounding margin
#   = 60 s  G2_DELTA
# WHY THIS NUMBER MOVED TWICE (recorded per claim=check; the same history is in docs/SAFETY.md):
# the record recommended 60/25 -> §2.4 deployed 50/20 for ONE stated reason, to fit the whole hold
# inside the 60 s un-armed timer -> [6.0-COND-1] then made proof floors PER-PROVIDER, so G2's floor
# is its own hold and never TAKEOVER_DELAY, which retired that reason -> back to the record's
# 60/25. THE COST, named: verified-demote's own branch answers ~10 s later than it did. The timer
# path is UNCHANGED, because the gate is ADDITIVE — it can only fail to block a take that the
# pre-existing logic already authorized, never cause one — so a later G2 answer is availability,
# never safety. G2's OWN floor [6.0-COND-1]: no W+B component — it stands on a positive
# observation (see the polarity comment above), and a global floor would punish the stronger proof
# with the longer wait. Kill-list at this number (§2.4): flip-then-flip-back dies by the <= 30 s
# CRDS expiry inside the 60 s hold plus the T2 absence check; correlated-fleet-lag dies because
# expiry is wall-clock-LOCAL on each vantage (a lagged replica still purges on time).
# WHAT THE BUDGET ACTUALLY BOUNDS (panel fix round, claim-check G2-N1 — the earlier wording said
# the freshness detector "consumes the SAME budget", which over-claimed): the ±budget compare
# below bounds the CHAIN-HEAD lag of a vantage's answer (getBlockTime of the slot it just served
# vs this spare's wall clock). CRDS purge, by contrast, fires on the vantage's LOCAL SYSTEM clock
# (research-crds-staked-timeout.md Q3) — a DIFFERENT physical clock, which the ±budget cannot
# see. The two are the same NUMBER by design (one budget for "how wrong may a vantage's sense of
# time be"), and mutating it moves both the hold and the compare (the N_HEAD/MARGIN_ELAPSED
# coupling pattern), but they are not the same MEASUREMENT. The slow-vantage-LOCAL-clock case is
# a named residual (SAFETY.md), caught — where it is caught at all — by the churn-vs-purge
# argument at the advance detector below, never by this compare.
G2_CLOCK_BUDGET=25
G2_DELTA=$(( 30 + G2_CLOCK_BUDGET + 5 ))
# G2_SLOT_ADVANCE_FLOOR (panel fix round, G2-B1 layer 2): the minimum number of slots a vantage's
# OWN confirmed head must advance between its T1 and its T2 snapshot before either snapshot may
# testify about NOW. DERIVATION, from DELTA and nothing else: mainnet nominal is ~2.5 slots/s
# (400 ms slots), so an honest vantage advances ~150 slots across a 60 s hold; the floor is set at
# ~1 slot/s x DELTA = 60 slots = 40 % of nominal, a deliberately loose tolerance so ordinary
# cluster slowdowns and per-vantage replay lag stay green. This layer trusts NO clock — not this
# spare's, not the cluster's — so it is the clock-free backstop for the ±budget compare above
# (G2-N1's spare-clock assumption). DIRECTION when the cluster genuinely stalls: advance < floor
# → cannot-determine → G2 stays silent and the un-armed timer path governs. Availability, never
# safety.
G2_SLOT_ADVANCE_FLOOR=$G2_DELTA
_G2_BASELINE_REFRESH_SECS=60   # idle-state baseline re-read cadence — availability-only (a stale endpoint fails toward not-proven, never toward proven; see _g2_step), so a plain constant like FENCE_ROT_CHECK_SECS's class, no env channel
_G2_READ_PACE_SECS=2           # minimum seconds between read-batches in the t1/hold/t2 states — bounds vantage load under the 1 s turbo loop; pacing only, never a proof input

_g2_registered=0               # registration latch (one registration per process)
_g2_disabled=""                # non-empty = the startup tripwire reason: G2 answers cannot-determine for this entire run (vantages not distinct / missing)
_g2_state="idle"               # idle | t1a | t1b | hold | t2a | t2b | proven (one state advance per _g2_step call, at most one read-batch)
_g2_gen=0                      # proof-attempt generation — incremented at every T1 arm; carried in observation_id so a verdict names WHICH attempt minted it
_g2_answer="cannot"            # the provider's current verdict class: cannot | no | yes (every ambiguity initializes and fails toward cannot)
_g2_reason="not yet evaluated" # MEASURED refusal/progress reason for the verdict record and logs (never a static figure)
_g2_staked_endpoint=""         # the BASELINE: ip:port of STAKED_PUBKEY's own gossip ContactInfo, captured PRE-INCIDENT
_g2_baseline_ts=0              # mono stamp of the last baseline refresh (0 = never captured)
_g2_nobl_warned=0              # once-per-episode latch for the no-baseline warn
_g2_t1_ts_a=0                  # per-vantage T1 mono stamps (per-vantage comparison, never cross)
_g2_t1_ts_b=0
_g2_t1_hash_a=""               # per-vantage T1 payload fingerprints (cksum crc-len of the getClusterNodes RESULT projection — see _g2_snap)
_g2_t1_hash_b=""
_g2_t1_slot_a=0                # per-vantage T1 confirmed slot, read from the SAME batched response as the T1 payload (0 = unset)
_g2_t1_slot_b=0
_g2_rid=0                      # JSON-RPC request-id counter (seeded mono at registration, +2 per snapshot): every batch carries ids never used before, and the echo MUST match — a replayed response is caught by its stale id alone
_g2_t2_hash_a=""               # vantage-A T2 fingerprint, held for the cross-vantage check at t2b
_g2_t2_slot_a=0                # vantage-A T2 batched slot, held for the PROVEN line's measured advance
_g2_t2_ts=0                    # mono stamp of the COMPLETED T2 read — the proven verdict's observed_at
_g2_verdict=""                 # the minted proven verdict record (stamps frozen at mint; ages via observed_at)
_g2_last_read_ts=0             # _G2_READ_PACE_SECS anchor (mono)
_g2_flip=0                     # alternates the baseline/hold-poll vantage so one dead vantage cannot monopolize the cheap reads
_g2_env_alert_ts=0             # throttle anchor for the environment-suspicion pages (cache / one-source / clock-skew)

# _g2_url_host — host part of an RPC URL (scheme/path/port stripped) for the distinctness tripwire.
# Prefix/suffix parameter expansion only — no pattern-substitution expansion (the CI facts job
# pins those lines per daemon: the bash-5.2 patsub_replacement class), no external calls.
# BRACKETED IPv6 (panel fix round, L3-N2): a naive `%%:*` cut truncates `[::1]:8899` to `[`, so
# ANY two bracketed-IPv6 vantages collapsed to the same host and tripped the same-host tripwire
# with a FALSE reason ("one failure domain") — safe direction (permanent cannot-determine) but a
# misleading page and G2 silently unavailable for the run. The bracket form is cut at the `]`.
_g2_url_host() {
    local _g2u="$1"
    case "$_g2u" in *"://"*) _g2u="${_g2u#*://}" ;; esac
    _g2u="${_g2u%%/*}"; _g2u="${_g2u%%\?*}"
    case "$_g2u" in
        "["*) _g2u="${_g2u%%]*}]" ;;   # [2001:db8::1]:8899 -> [2001:db8::1] (the literal IS the host)
        *)    _g2u="${_g2u%%:*}" ;;
    esac
    printf '%s' "$_g2u"
}

# throttled environment-suspicion page (the _recheck_abort_alert idiom: first page immediate,
# repeats per ALERT_THROTTLE; per-event log_warn lines are never throttled). GLOBAL, not
# per-episode: it guards the operator channel — a cache-fronted vantage does not stop being
# cache-fronted when the episode resets.
_g2_env_alert() {
    if [[ ${_g2_env_alert_ts:-0} -gt 0 ]]; then
        [[ $(( $(mono_now) - _g2_env_alert_ts )) -ge ${ALERT_THROTTLE:-600} ]] || return 0
    fi
    _g2_env_alert_ts=$(mono_now)
    alert_warn "$1"
}

# _g2_reset <why> — drop the in-flight attempt AND the verdict, back to idle. The baseline and the
# generation counter survive (pre-incident state / attempt lineage); everything the PROOF stands on
# dies with the reset — a withdrawn verdict must never be re-servable.
_g2_reset() {
    _g2_state="idle"; _g2_answer="cannot"; _g2_reason="${1:-reset}"
    _g2_t1_ts_a=0; _g2_t1_ts_b=0; _g2_t1_hash_a=""; _g2_t1_hash_b=""
    _g2_t1_slot_a=0; _g2_t1_slot_b=0
    _g2_t2_hash_a=""; _g2_t2_slot_a=0; _g2_t2_ts=0; _g2_verdict=""; _g2_nobl_warned=0
    return 0
}

# _g2_arm <why> — start (or restart) a proof attempt: fresh generation, clean T1/T2 state, T1
# sampling begins next paced cycle. Every re-arm after a kill goes through here so observation_id
# can never mix stamps from two attempts. Deliberately does NOT touch _g2_answer/_g2_reason: a
# kill's not-proven verdict must stay reportable while the new attempt samples (only fresh
# evidence may change the answer).
_g2_arm() {
    _g2_gen=$(( _g2_gen + 1 ))
    _g2_t1_ts_a=0; _g2_t1_ts_b=0; _g2_t1_hash_a=""; _g2_t1_hash_b=""
    _g2_t1_slot_a=0; _g2_t1_slot_b=0
    _g2_t2_hash_a=""; _g2_t2_slot_a=0; _g2_t2_ts=0; _g2_verdict=""
    _g2_state="t1a"
    log_info "[g2-provider] proof attempt gen=${_g2_gen} armed (${1:-}) — T1 snapshot of both vantages begins (endpoint anchor ${_g2_staked_endpoint})"
    return 0
}

# _g2_snap <vantage-url> <label> — ONE bounded per-vantage snapshot: a JSON-RPC BATCH carrying the
# freshness anchor (the vantage's own confirmed slot) TOGETHER WITH the proof-bearing
# getClusterNodes payload, then that slot's cluster time via getBlockTime.
# Results via globals (this runs in the MAIN shell — a $()-captured helper would strand the state):
#   _g2_snap_ok        1 = every read answered and parsed (0 => cannot-determine, never absent)
#   _g2_snap_why       why ok=0 (measured)
#   _g2_snap_present   1 = a PRIMARY_UNSTAKED_PUBKEY entry sits at EXACTLY _g2_staked_endpoint
#   _g2_snap_misplaced non-empty = a watched entry was seen at a DIFFERENT endpoint (that endpoint)
#   _g2_snap_hash      fingerprint (cksum crc-len) of the getClusterNodes RESULT projection
#   _g2_snap_slot      the confirmed slot carried by the SAME response as the payload
#   _g2_snap_skew      vantage cluster-time minus this spare's wall clock, seconds (signed)
#   _g2_snap_fresh     1 = |skew| <= G2_CLOCK_BUDGET (inclusive both directions)
# Each curl is bounded (-m 5, the peer_has_relinquished gossip-read bound) and petted post-op — a
# timeout return IS completion (FF-B1). "Cache-Control: no-cache" rides every read (the C1 belt);
# G2 does NOT trust it — the detectors below are the proof, the header is politeness.
#
# WHY A BATCH (panel fix round, G2-B1 BLOCKER — the shipped v1 hole): the freshness anchor used to
# be its OWN HTTP request, so it validated a DIFFERENT object than the proof rested on. A vantage
# serving honest live getSlot/getBlockTime while replaying only the getClusterNodes body minted
# PROVEN (executed). One POST now carries BOTH, so the slot is CONTENT-ADDRESSED TO THE BODY that
# carries the proof: a replayed body arrives with ITS slot, whose block time is old (skew fails)
# and which does not advance across the hold (slot-advance fails). JSON-RPC batching verified by
# execution against mainnet-beta/agave 4.2.1 — design record verify-rpc-batch-and-churn.md
# (private tree): a [getSlot,getClusterNodes] batch returns a 2-element ARRAY with our ids
# preserved. Members are matched BY id, NEVER by position (JSON-RPC 2.0 permits any order), and
# the ids are fresh per request, so a naive cache replaying an older response is caught by the id
# echo alone. Any malformation — not an array, wrong length, missing/duplicated id, unparseable
# member — lands cannot-determine, never proven. The vantage's ability to serve the batch at all
# is verified at the ARM (REFUSE[P6-batch]); this is the run-time re-check.
# NAMED RESIDUAL (design record §4, restated in SAFETY.md): binding raises the bar from passive
# cache / naive replay to ACTIVE, PROTOCOL-AWARE tampering (an intermediary that splits the batch,
# forwards getSlot live and answers getClusterNodes from storage under our id). It does not defeat
# that, and G2 does not claim to.
_g2_snap() {
    local _g2s_url="$1" _g2s_label="$2" _g2s_body _g2s_rc _g2s_slot _g2s_bt _g2s_wall _g2s_pk _g2s_scan _g2s_askew _g2s_ida _g2s_idb _g2s_idc _g2s_nodes
    _g2_snap_ok=0; _g2_snap_why=""; _g2_snap_present=0; _g2_snap_misplaced=""
    _g2_snap_hash=""; _g2_snap_slot=0; _g2_snap_skew=0; _g2_snap_fresh=0
    # fresh ids, never reused in this process (mono-seeded at registration, +3 per snapshot: two
    # batch members plus the getBlockTime that follows)
    _g2_rid=$(( _g2_rid + 3 )); _g2s_ida=$_g2_rid; _g2s_idb=$(( _g2_rid + 1 )); _g2s_idc=$(( _g2_rid + 2 ))
    _g2s_body=$(curl -s -m 5 "$_g2s_url" -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d "[{\"jsonrpc\":\"2.0\",\"id\":${_g2s_ida},\"method\":\"getSlot\",\"params\":[{\"commitment\":\"confirmed\"}]},{\"jsonrpc\":\"2.0\",\"id\":${_g2s_idb},\"method\":\"getClusterNodes\"}]" 2>/dev/null)
    _g2s_rc=$?
    _watchdog_pet   # §5 per-op pet: bounded op completed (rc captured above); no-op outside the armed unit
    if [[ $_g2s_rc -ne 0 ]]; then
        _g2_snap_why="vantage ${_g2s_label} snapshot batch unreachable (curl rc=${_g2s_rc})"
        return 0
    fi
    # [g2-det-batch]: the answer MUST be a JSON-RPC batch response — a 2-element array. Anything
    # else (a single object, a split answer, an HTML error page, truncated JSON) means the anchor
    # is not bound to the payload, so nothing here may testify: cannot-determine.
    if ! printf '%s' "$_g2s_body" | jq -e 'type == "array" and length == 2' >/dev/null 2>&1; then
        _g2_snap_why="vantage ${_g2s_label} did not answer the [getSlot,getClusterNodes] BATCH with a 2-element array — the freshness anchor is not bound to the proof payload (batching unsupported, split by an intermediary, or unparseable), cannot-determine"
        return 0
    fi
    # [g2-det-batch-id]: match members BY OUR ID (never by position — JSON-RPC permits any order),
    # and require EXACTLY ONE member per id. A stale/replayed response carries stale ids and dies
    # here on the echo alone, before any content is looked at.
    _g2s_slot=$(printf '%s' "$_g2s_body" | jq -r --arg id "$_g2s_ida" '[.[] | select((.id|tostring) == $id)] | if length == 1 then (.[0].result // empty) else empty end' 2>/dev/null)
    case "$_g2s_slot" in ''|*[!0-9]*)
        _g2_snap_why="vantage ${_g2s_label} batch carried no usable getSlot member echoing our id=${_g2s_ida} ('${_g2s_slot}') — id mismatch (a replayed/cached response) or an unusable slot"
        return 0
    ;; esac
    _g2s_nodes=$(printf '%s' "$_g2s_body" | jq -c --arg id "$_g2s_idb" '[.[] | select((.id|tostring) == $id)] | if length == 1 then (.[0].result) else empty end' 2>/dev/null)
    if [[ -z "$_g2s_nodes" || "$_g2s_nodes" == "null" ]]; then
        _g2_snap_why="vantage ${_g2s_label} batch carried no usable getClusterNodes member echoing our id=${_g2s_idb} — id mismatch (a replayed/cached response), an error member, or no result"
        return 0
    fi
    _g2_snap_slot=$_g2s_slot
    # The fingerprint is over the getClusterNodes RESULT projection, canonicalised by jq -c — NOT
    # over the raw HTTP body. Deliberate: the raw body now carries OUR OWN per-request id, which
    # would make every body differ and render the advance / cross-vantage layers vacuous by our
    # own hand. What this hash witnesses is stated at the advance detector below.
    _g2_snap_hash=$(printf '%s' "$_g2s_nodes" | cksum 2>/dev/null | awk '{print $1 "-" $2}')
    # presence at EXACTLY the baseline endpoint. The endpoint match is LOAD-BEARING: it proves the
    # demoted state is live on THAT box (agave set-identity keeps ports, so a self-fenced holder
    # re-advertises its unstaked identity at exactly the endpoint its staked identity last used —
    # the F-A anchor, live-tested). A watched key present SOMEWHERE ELSE proves only that a
    # publisher exists elsewhere (a non-holder peer in a multi-node topology) — recorded in
    # _g2_snap_misplaced for the refusal text, NEVER counted as the proof.
    # ALL gossip values are scanned (panel fix round, G2-N2): present iff ANY entry for the watched
    # key sits at the baseline endpoint. The old `head -1` decided on the FIRST entry, so a
    # topology listing the key elsewhere-first read as not-proven while the real entry sat further
    # down — a false NEGATIVE (safe direction, availability only), fixed here.
    # shellcheck disable=SC2086
    for _g2s_pk in $PRIMARY_UNSTAKED_PUBKEY; do
        _g2s_scan=$(printf '%s' "$_g2s_nodes" | jq -r --arg pk "$_g2s_pk" --arg ep "$_g2_staked_endpoint" '[ .[]? | select(.pubkey == $pk) | .gossip // empty ] | (if (index($ep) != null) then "1" else "0" end) + " " + ((map(select(. != $ep)) | .[0]) // "")' 2>/dev/null)
        case "$_g2s_scan" in
            "1 "*) _g2_snap_present=1 ;;
            "0 "?*) [[ -z "$_g2_snap_misplaced" ]] && _g2_snap_misplaced="${_g2s_scan#0 }" ;;
        esac
        [[ $_g2_snap_present -eq 1 ]] && break
    done
    # freshness anchor [MY-2, snapshot-freshness vs the clock budget — reviewer-flagged addition]:
    # getClusterNodes carries NO wallclock field (RpcContactInfo: pubkey/gossip/rpc/version/…— the
    # §2.4 "wallclocks move constantly" is WHY live payloads churn, not a readable field), so the
    # snapshot's time signature is the chain head the vantage returned IN THE SAME RESPONSE as the
    # payload, resolved to cluster time by getBlockTime. getBlockTime is CONTENT-ADDRESSED by slot:
    # an honest answer about an old slot is an OLD time, so a body replayed together with its own
    # slot fails here. ASSUMES A CORRECT SPARE CLOCK (panel fix round, G2-N1): the compare's
    # reference is this host's wall clock, so a spare whose clock drifts by ~R seconds would
    # collapse the skew of an R-seconds-old replay toward 0. The clock-FREE backstop is the
    # slot-advance layer (G2_SLOT_ADVANCE_FLOOR, checked at T2) — it trusts neither clock.
    # Residual (named in SAFETY.md): an environment that actively FORGES fresh times for old slots
    # defeats this — no unsigned snapshot protocol can beat a full forger.
    # This read carries a fresh id too and REQUIRES the echo: every G2 request in this region is
    # id-bound, so no G2 answer can be a stored copy of an earlier one ([g2-det-batch-id]).
    _g2s_bt=$(curl -s -m 5 "$_g2s_url" -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d "{\"jsonrpc\":\"2.0\",\"id\":${_g2s_idc},\"method\":\"getBlockTime\",\"params\":[${_g2s_slot}]}" 2>/dev/null | jq -r --arg id "$_g2s_idc" 'if ((.id|tostring) == $id) then (.result // empty) else empty end' 2>/dev/null)
    _watchdog_pet   # §5 per-op pet: bounded op completed; no-op outside the armed unit
    case "$_g2s_bt" in ''|*[!0-9]*)
        _g2_snap_why="vantage ${_g2s_label} getBlockTime(${_g2s_slot}) gave no usable time echoing our id=${_g2s_idc} ('${_g2s_bt}')"
        return 0
    ;; esac
    # the daemons' ONE G2 wall-clock read (the mono rule stands everywhere else in this region):
    # cluster time is Unix wall time, so ONLY a wall-clock compare is meaningful here. Counted by
    # the CI facts job's per-daemon wall-clock line pin (.github/workflows/ci.yml) — this line IS
    # the Block-6.2 pin bump (primary 20->21, standby 21->22), updated with the pin's comment.
    _g2s_wall=$(date +%s)
    _g2_snap_skew=$(( _g2s_bt - _g2s_wall ))
    # both directions, INCLUSIVE at the budget (the (1i)/(1l) boundary convention): a snapshot
    # frozen in the past fails LOW (replay), one from the future fails HIGH (clock inversion) —
    # either way it cannot testify about NOW. [g2-det-clock]
    _g2s_askew=$_g2_snap_skew; [[ $_g2s_askew -lt 0 ]] && _g2s_askew=$(( 0 - _g2s_askew ))
    [[ $_g2s_askew -le $G2_CLOCK_BUDGET ]] && _g2_snap_fresh=1
    _g2_snap_ok=1
    return 0
}

# _g2_register — called from _proof_startup_check (armed + spare role already gated there).
# Registration is what makes G2 exist at all: unconfigured (no PRIMARY_UNSTAKED_PUBKEY) spares
# get NO provider, zero events, zero reads — the same structural-inertness bar as un-armed.
_g2_register() {
    _watchdog_active || return 0
    _proof_role_is_spare || return 0
    [[ "$_g2_registered" == "0" ]] || return 0
    [[ -n "${PRIMARY_UNSTAKED_PUBKEY:-}" ]] || return 0   # nothing to watch — silent by design (the §2.7 posture line carries the registry state)
    # vantage pinning: env knobs first, else the EXISTING distinct tiers (TIER2 = paid provider,
    # TIER3 = public RPC — distinct failure domains the wizards already enforce and startup
    # already checks; G2 inherits that grounding instead of inventing a third pair of URLs).
    G2_VANTAGE_A="${G2_VANTAGE_A:-${TIER2_RPC:-}}"
    G2_VANTAGE_B="${G2_VANTAGE_B:-${TIER3_RPC:-}}"
    # the vantage distinctness tripwire (startup, armed): identical URLs or one shared host make
    # "present on BOTH vantages" a single witness wearing two names — G2 is then permanently
    # cannot-determine for this run (fail toward not-taking; a CRITICAL page names the fix). The
    # deeper CNAME/IP-level case cannot be seen from here — it belongs to the Block-6 panel and,
    # where it matters (a shared cache serving shared bytes), to the cross-vantage detector below.
    if [[ -z "$G2_VANTAGE_A" || -z "$G2_VANTAGE_B" ]]; then
        _g2_disabled="fewer than two vantages configured (A='${G2_VANTAGE_A:-}' B='${G2_VANTAGE_B:-}')"
    elif [[ "$(_norm_rpc_url "$G2_VANTAGE_A")" == "$(_norm_rpc_url "$G2_VANTAGE_B")" ]]; then
        _g2_disabled="G2_VANTAGE_A == G2_VANTAGE_B (one vantage wearing two names)"
    elif [[ -n "$(_g2_url_host "$G2_VANTAGE_A")" && "$(_g2_url_host "$G2_VANTAGE_A")" == "$(_g2_url_host "$G2_VANTAGE_B")" ]]; then
        _g2_disabled="G2 vantages share one host '$(_g2_url_host "$G2_VANTAGE_A")' — one failure domain"
    fi
    # SHARED VANTAGE with the vote-liveness tiers (reviewer condition C1, item 4 — FLAGGED FOR
    # RATIFICATION: mine, not the reviewer's words). The arm ceremony owns the loud version and the
    # fix text; this exists because the arm is a ONE-TIME ceremony while this daemon runs forever,
    # and the operator reading a running spare's log deserves the same statement. A log_warn, never
    # a page: the condition is a CONFIG property, constant for the whole run, so §2.7's "loud, not
    # documentary" class is a warn — paging it at every start would train the operator to ignore
    # pages. URL-LEVEL ONLY, deliberately: the daemon performs NO DNS (a resolver call is an
    # unbounded external read inside the monitor loop, and resolution belongs to arm time, where
    # REFUSE[P6-vantage] and the arm's overlap notice both do it). A shared vantage hiding behind
    # two hostnames is therefore INVISIBLE here and visible at the arm — said plainly in the text.
    local _g2r_pair _g2r_vl _g2r_tl _g2r_u _g2r_t _g2r_h _g2r_shared=""
    for _g2r_pair in A:2 A:3 B:2 B:3; do
        _g2r_vl="${_g2r_pair%%:*}"; _g2r_tl="${_g2r_pair##*:}"
        if [[ "$_g2r_vl" == "A" ]]; then _g2r_u="$G2_VANTAGE_A"; else _g2r_u="$G2_VANTAGE_B"; fi
        if [[ "$_g2r_tl" == "2" ]]; then _g2r_t="${TIER2_RPC:-}"; else _g2r_t="${TIER3_RPC:-}"; fi
        [[ -n "$_g2r_u" && -n "$_g2r_t" ]] || continue
        _g2r_h=$(_g2_url_host "$_g2r_u")
        if [[ "$(_norm_rpc_url "$_g2r_u")" == "$(_norm_rpc_url "$_g2r_t")" ]]; then
            _g2r_shared="${_g2r_shared:+$_g2r_shared; }G2_VANTAGE_${_g2r_vl} == TIER${_g2r_tl}_RPC by identical normalized URL"
        elif [[ -n "$_g2r_h" && "$_g2r_h" == "$(_g2_url_host "$_g2r_t")" ]]; then
            _g2r_shared="${_g2r_shared:+$_g2r_shared; }G2_VANTAGE_${_g2r_vl} == TIER${_g2r_tl}_RPC by same host '${_g2r_h}'"
        fi
    done
    if [[ -n "$_g2r_shared" ]]; then
        log_warn "[g2-provider] SHARED VANTAGE (degraded, not disabled): G2 and vote-liveness SHARE VANTAGES: one compromised vantage supplies BOTH halves of the double-sign condition — a false verified-demote proof AND a false-frozen vote observation — so the proof gate's additivity does NOT hold on this host. MEASURED: ${_g2r_shared} — by normalized-URL and host compare only (this daemon does no DNS; the arm ceremony resolves). The liveness readers iterate TIER2_RPC then TIER3_RPC (docs/SAFETY.md, verified-demote residual 2). Fix: point G2_VANTAGE_A/G2_VANTAGE_B at a third endpoint in a SEPARATE failure domain, then re-run 'failover arm'"
    fi
    if [[ -n "$_g2_disabled" ]]; then
        _g2_answer="cannot"; _g2_reason="vantage tripwire: ${_g2_disabled}"
        alert "G2 verified-demote vantages are NOT distinct — ${_g2_disabled}. verified-demote is permanently cannot-determine for this run (fail toward NOT-TAKING). Fix G2_VANTAGE_A/G2_VANTAGE_B (or TIER2_RPC/TIER3_RPC) to two bank-bearing RPC providers in DISTINCT failure domains." "${STAKED_PUBKEY:-unknown}" "G2 VANTAGES NOT DISTINCT 🚨"
    else
        _g2_answer="cannot"; _g2_reason="registered — no baseline yet"
    fi
    _proof_providers="${_proof_providers:+$_proof_providers }_g2_provider"
    _proof_provider_labels="${_proof_provider_labels:+$_proof_provider_labels }verified-demote"
    _g2_registered=1
    _g2_rid=$(mono_now)   # request-id seed: a restarted daemon starts ABOVE its own previous ids (mono is boot-monotonic), so no run can be answered with the previous run's stored responses
    log_info "[g2-provider] registered: verified-demote — vantage A host=$(_g2_url_host "$G2_VANTAGE_A") B host=$(_g2_url_host "$G2_VANTAGE_B") (URLs withheld from logs: they may carry keys), watching ${PRIMARY_UNSTAKED_PUBKEY} at the holder's staked endpoint, DELTA=${G2_DELTA}s (30s CRDS bound + ${G2_CLOCK_BUDGET}s clock budget + 5s purge/rounding)${_g2_disabled:+ — DISABLED: ${_g2_disabled}}"
    return 0
}

# ── _g2_step — the per-cycle state machine advance (called from the main loop, spare posture;
#    "main loop" stays lowercase HERE: the test harness cuts each daemon at the first line
#    matching the uppercase marker — a premature match would truncate the seam mid-region) ──
# One call = at most one bounded read-batch, never a wait: DELTA elapses across CYCLES on the mono
# clock while the loop keeps doing its normal work. State map (each transition logged):
#   idle   no incident: refresh the baseline endpoint on cadence; on incident -> arm T1
#   t1a/t1b  T1 snapshot of vantage A then B (paced): present on BOTH at the baseline endpoint ->
#            hold; on ONE -> cannot-determine, retry (blind-ish); ABSENT (parsed, not there) ->
#            not-proven, re-arm; unreachable/stale-clock -> cannot-determine, retry
#   hold   until T2 >= T1+G2_DELTA (per vantage — gated on the LATER T1 stamp): one cheap
#          alternating presence poll per paced cycle; an OBSERVED absence -> NOT-PROVEN + full
#          reset (the flip-then-flip-back kill: a re-staked holder stops re-signing the unstaked
#          entry, CRDS purges it <= 30 s — inside the hold by derivation); an unreachable poll is
#          BLINDNESS, not absence — it kills nothing and proves nothing (T2 owns the proving)
#   t2a/t2b  T2 re-snapshot of the SAME pinned vantages (per-vantage comparison, never cross) +
#            every detector, slot-advance FIRST (the clock-free one); all pass -> mint proven;
#            else per-detector cannot/no
#   proven  dormant (zero reads): the verdict ages via observed_at; past PROOF_MAX_AGE it is
#           WITHDRAWN and the machine re-arms — a provider must never serve a verdict the
#           mutation edge would refuse anyway
_g2_step() {
    _watchdog_active || return 0
    _proof_role_is_spare || return 0
    [[ "$_g2_registered" == "1" ]] || return 0
    [[ -z "$_g2_disabled" ]] || return 0
    local _g2p_now _g2p_hold_a _g2p_hold_b _g2p_url _g2p_lab
    _g2p_now=$(mono_now)
    if ! _g2_incident_active; then
        [[ "$_g2_state" != "idle" ]] && { log_info "[g2-provider] episode closed — attempt gen=${_g2_gen} dropped (state ${_g2_state})"; _g2_reset "idle (no incident)"; }
        _g2_answer="cannot"; _g2_reason="idle (no incident)"
        # baseline capture/refresh — PRE-INCIDENT ONLY (§2.4 state 1): the endpoint is pinned from
        # the era the holder was healthy. It is not proof-critical in the dangerous direction: the
        # unstaked ContactInfo is CRDS-SIGNED by the unstaked key itself (no third party can
        # fabricate it — research-setidentity-gossip-semantics.md condition 4), so a wrong/forged
        # baseline endpoint can only make the real entry NOT match -> not-proven, never proven.
        if [[ $_g2_baseline_ts -eq 0 || $(( _g2p_now - _g2_baseline_ts )) -ge $_G2_BASELINE_REFRESH_SECS ]]; then
            _g2_flip=$(( 1 - _g2_flip ))
            if [[ $_g2_flip -eq 1 ]]; then _g2p_url="$G2_VANTAGE_A"; _g2p_lab="A"; else _g2p_url="$G2_VANTAGE_B"; _g2p_lab="B"; fi
            local _g2p_body _g2p_rc _g2p_ep
            _g2p_body=$(curl -s -m 5 "$_g2p_url" -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null)
            _g2p_rc=$?
            _watchdog_pet   # §5 per-op pet: bounded op completed (rc captured above); no-op outside the armed unit
            _g2_baseline_ts=$_g2p_now
            if [[ $_g2p_rc -eq 0 ]] && echo "$_g2p_body" | jq -e '.result' &>/dev/null; then
                _g2p_ep=$(echo "$_g2p_body" | jq -r --arg sp "$STAKED_PUBKEY" '.result[]? | select(.pubkey == $sp) | .gossip // empty' 2>/dev/null | head -1)
                if [[ -n "$_g2p_ep" && "$_g2p_ep" != "$_g2_staked_endpoint" ]]; then
                    log_info "[g2-provider] baseline: holder's STAKED ContactInfo at ${_g2p_ep} (vantage ${_g2p_lab}${_g2_staked_endpoint:+; was ${_g2_staked_endpoint}})"
                    _g2_staked_endpoint="$_g2p_ep"
                fi
                # staked entry absent on this read: KEEP the captured baseline — the staked entry
                # lingers ~48 h in CRDS, so visible-then-gone means vantage trouble, not a demote.
            fi
        fi
        return 0
    fi
    case "$_g2_state" in
        idle)
            if [[ -z "$_g2_staked_endpoint" ]]; then
                _g2_answer="cannot"; _g2_reason="no baseline captured pre-incident — endpoint anchor unknown"
                if [[ $_g2_nobl_warned -eq 0 ]]; then
                    _g2_nobl_warned=1
                    log_warn "[g2-provider] incident open but NO baseline endpoint was captured pre-incident (daemon started mid-episode?) — verified-demote answers cannot-determine for this episode; the timer path governs"
                fi
                return 0
            fi
            _g2_arm "incident open (the Option-A trigger surface: a suspected relinquish episode)"
            _g2_answer="cannot"; _g2_reason="attempt gen=${_g2_gen} armed — T1 sampling"
            ;;
        t1a|t2a)
            # pace guard (the _recheck_abort_alert 0-sentinel idiom: the FIRST read is never made
            # to wait; only repeats are paced)
            if [[ ${_g2_last_read_ts:-0} -gt 0 ]]; then
                [[ $(( _g2p_now - _g2_last_read_ts )) -lt $_G2_READ_PACE_SECS ]] && return 0
            fi
            _g2_last_read_ts=$_g2p_now
            _g2_snap "$G2_VANTAGE_A" "A"
            if [[ $_g2_snap_ok -ne 1 ]]; then
                _g2_answer="cannot"; _g2_reason="${_g2_snap_why} (${_g2_state})"
                return 0
            fi
            if [[ $_g2_snap_fresh -ne 1 ]]; then
                _g2_answer="cannot"; _g2_reason="vantage A cluster-time skew ${_g2_snap_skew}s outside ±${G2_CLOCK_BUDGET}s budget (${_g2_state}) — snapshot cannot testify about NOW (replay/frozen view)"
                log_warn "[g2-provider] ${_g2_reason}"
                _g2_env_alert "⚠️ G2 vantage A answers with cluster time ${_g2_snap_skew}s off this spare's clock (budget ±${G2_CLOCK_BUDGET}s) — replayed/frozen view or broken clock; verified-demote holds cannot-determine."
                return 0
            fi
            if [[ $_g2_snap_present -ne 1 ]]; then
                _g2_answer="no"; _g2_reason="unstaked entry ABSENT at ${_g2_staked_endpoint} on vantage A (${_g2_state})${_g2_snap_misplaced:+ — seen at DIFFERENT endpoint ${_g2_snap_misplaced}: a publisher elsewhere proves nothing about THIS box}"
                if [[ "$_g2_state" == "t2a" ]]; then
                    log_warn "[g2-provider] T2 absence on vantage A after $(( _g2p_now - _g2_t1_ts_a ))s of hold — NOT-PROVEN, full reset (flip-back kill): ${_g2_reason}"
                    _g2_arm "re-arm after T2 absence on A"
                fi
                return 0
            fi
            if [[ "$_g2_state" == "t1a" ]]; then
                _g2_t1_ts_a=$_g2p_now; _g2_t1_hash_a="$_g2_snap_hash"; _g2_t1_slot_a=$_g2_snap_slot
                _g2_state="t1b"; _g2_reason="T1 vantage A captured — sampling B"
            else
                # slot-advance, vantage A [g2-det-slot-advance] (panel fix round, G2-B1 layer 2):
                # the confirmed head this vantage returned IN THE SAME RESPONSE as the T2 payload
                # must be at least G2_SLOT_ADVANCE_FLOOR slots ahead of the one it returned with
                # its T1 payload. This is the anti-replay/anti-cache duty, moved here from the
                # whole-body compare below: a stored answer replays ITS slot, and a stored slot
                # does not advance. Clock-free — it trusts neither this spare's clock nor the
                # cluster's. A genuinely stalled cluster (or a vantage stuck in replay) advances
                # too little and lands cannot-determine: availability, never safety.
                if [[ $(( _g2_snap_slot - _g2_t1_slot_a )) -lt $G2_SLOT_ADVANCE_FLOOR ]]; then
                    _g2_answer="cannot"; _g2_reason="vantage A confirmed head advanced only $(( _g2_snap_slot - _g2_t1_slot_a )) slots across $(( _g2p_now - _g2_t1_ts_a ))s (T1 slot ${_g2_t1_slot_a} -> T2 slot ${_g2_snap_slot}); REQUIRED: >= ${G2_SLOT_ADVANCE_FLOOR} — a frozen/replayed head or a stalled cluster cannot testify about NOW, cannot-determine"
                    log_warn "[g2-provider] ${_g2_reason}"
                    _g2_env_alert "⚠️ G2 vantage A advanced only $(( _g2_snap_slot - _g2_t1_slot_a )) slots in $(( _g2p_now - _g2_t1_ts_a ))s (floor ${G2_SLOT_ADVANCE_FLOOR}) — a replayed/frozen chain head or a stalled cluster; verified-demote holds cannot-determine."
                    _g2_arm "re-arm after slot-advance floor on A"
                    return 0
                fi
                # node-table advance, vantage A [g2-det-advance-a]. WHAT THIS CATCHES, EXACTLY
                # (panel fix round, G2-B2 — the shipped v1 comment claimed more than the mechanism
                # delivers): the fingerprint is over the WHOLE getClusterNodes result, so identity
                # across the hold catches a TOTALLY FROZEN response — a naive whole-payload cache.
                # It does NOT prove the unstaked-at-endpoint entry was re-observed live: on real
                # mainnet the body churns constantly (measured: three consecutive reads differ in
                # size — verify-rpc-batch-and-churn.md, private tree), so a frozen proof entry
                # riding on other nodes' churn passes this compare. That case is owned by the
                # slot-advance layer above, not here. Hashing the proof projection instead would
                # NOT help: in the honest case the projection is IDENTICAL at T1 and T2 — that
                # identity IS the hold being proven.
                # WHY BYTE-DISTINCTNESS STILL MATTERS (the physical argument, B2.3): a single
                # source that KEEPS the stale unstaked entry across the whole G2_DELTA hold must
                # either FREEZE its CRDS table — a local clock slow enough to reject fresh gossip
                # stops the body churning, and this layer plus the cross-vantage compare fire — or
                # genuinely re-sign it, which means a LIVE publisher, i.e. the true proof. That
                # churn-vs-purge tension is what this layer is really buying. A future maintainer
                # relaxing it is removing that, not removing a redundant cksum.
                if [[ "$_g2_snap_hash" == "$_g2_t1_hash_a" ]]; then
                    _g2_answer="cannot"; _g2_reason="vantage A payload BYTE-IDENTICAL across $(( _g2p_now - _g2_t1_ts_a ))s (fingerprint ${_g2_snap_hash}) — cache suspected, cannot-determine"
                    log_warn "[g2-provider] ${_g2_reason}"
                    _g2_env_alert "⚠️ G2 vantage A served a byte-identical getClusterNodes payload $(( _g2p_now - _g2_t1_ts_a ))s apart — a cache in front of the RPC; verified-demote holds cannot-determine. Pin a non-cached vantage."
                    _g2_arm "re-arm after cache suspicion on A"
                    return 0
                fi
                _g2_t2_hash_a="$_g2_snap_hash"; _g2_t2_slot_a=$_g2_snap_slot
                _g2_state="t2b"; _g2_reason="T2 vantage A verified — sampling B"
            fi
            ;;
        t1b|t2b)
            if [[ ${_g2_last_read_ts:-0} -gt 0 ]]; then
                [[ $(( _g2p_now - _g2_last_read_ts )) -lt $_G2_READ_PACE_SECS ]] && return 0
            fi
            _g2_last_read_ts=$_g2p_now
            _g2_snap "$G2_VANTAGE_B" "B"
            if [[ $_g2_snap_ok -ne 1 ]]; then
                _g2_answer="cannot"; _g2_reason="${_g2_snap_why} (${_g2_state})"
                return 0
            fi
            if [[ $_g2_snap_fresh -ne 1 ]]; then
                _g2_answer="cannot"; _g2_reason="vantage B cluster-time skew ${_g2_snap_skew}s outside ±${G2_CLOCK_BUDGET}s budget (${_g2_state}) — snapshot cannot testify about NOW (replay/frozen view)"
                log_warn "[g2-provider] ${_g2_reason}"
                _g2_env_alert "⚠️ G2 vantage B answers with cluster time ${_g2_snap_skew}s off this spare's clock (budget ±${G2_CLOCK_BUDGET}s) — replayed/frozen view or broken clock; verified-demote holds cannot-determine."
                return 0
            fi
            if [[ $_g2_snap_present -ne 1 ]]; then
                if [[ "$_g2_state" == "t1b" ]]; then
                    # present on ONE vantage only — a half-witnessed world is blind-ish, not proof
                    # and not disproof: cannot-determine, and the whole T1 pair re-samples (the two
                    # T1 reads must be near-contemporaneous or the "both vantages" claim is a splice).
                    _g2_answer="cannot"; _g2_reason="unstaked entry on vantage A but ABSENT on B at T1${_g2_snap_misplaced:+ (B sees it at ${_g2_snap_misplaced})} — one-vantage view, retrying the T1 pair"
                    _g2_state="t1a"
                else
                    _g2_answer="no"; _g2_reason="unstaked entry ABSENT at ${_g2_staked_endpoint} on vantage B at T2${_g2_snap_misplaced:+ — seen at DIFFERENT endpoint ${_g2_snap_misplaced}}"
                    log_warn "[g2-provider] T2 absence on vantage B after $(( _g2p_now - _g2_t1_ts_b ))s of hold — NOT-PROVEN, full reset (flip-back kill): ${_g2_reason}"
                    _g2_arm "re-arm after T2 absence on B"
                fi
                return 0
            fi
            # cross-vantage identity [MY-1, reviewer-flagged addition] [g2-det-crossvantage]: two
            # DISTINCT bank-bearing vantages each hold a private CRDS table and serialize it in
            # their own iteration order — byte-identical node tables from both are not
            # "agreement", they are ONE source wearing two names.
            # WHAT THIS CATCHES, EXACTLY (panel fix round, G2-B2 — the shipped v1 comment claimed
            # more): byte-identity across vantages catches a shared source that serves the SAME
            # bytes to both. It does NOT catch one source that varies anything per vantage (a
            # request-id echo, a re-serialization, an injected nonce) — that was executed and
            # minted. Byte-distinctness is therefore NECESSARY, NOT SUFFICIENT, for "two failure
            # domains". The enforceable part of that requirement lives at the ARM: identical URLs
            # / identical hostnames (the startup tripwire below) and identical RESOLVED ADDRESS
            # SETS (REFUSE[P6-vantage]). Two genuinely different IPs belonging to one provider
            # remain an OPERATOR responsibility — stated plainly here and in the manual, not
            # pretended away.
            if [[ "$_g2_state" == "t1b" && -n "$_g2_t1_hash_a" && "$_g2_t1_hash_a" == "$_g2_snap_hash" ]]; then
                _g2_answer="cannot"; _g2_reason="T1 payloads BYTE-IDENTICAL across vantages A and B (fingerprint ${_g2_snap_hash}) — one source suspected behind two names"
                log_warn "[g2-provider] ${_g2_reason}"
                _g2_env_alert "⚠️ G2 vantages A and B served BYTE-IDENTICAL getClusterNodes payloads — they are likely one provider/cache behind two names (no independent corroboration); verified-demote holds cannot-determine. Use two genuinely distinct providers."
                _g2_arm "re-arm after cross-vantage identity at T1"
                return 0
            fi
            if [[ "$_g2_state" == "t2b" && -n "$_g2_t2_hash_a" && "$_g2_t2_hash_a" == "$_g2_snap_hash" ]]; then
                _g2_answer="cannot"; _g2_reason="T2 payloads BYTE-IDENTICAL across vantages A and B (fingerprint ${_g2_snap_hash}) — one source suspected behind two names"
                log_warn "[g2-provider] ${_g2_reason}"
                _g2_env_alert "⚠️ G2 vantages A and B served BYTE-IDENTICAL getClusterNodes payloads — they are likely one provider/cache behind two names (no independent corroboration); verified-demote holds cannot-determine. Use two genuinely distinct providers."
                _g2_arm "re-arm after cross-vantage identity at T2"
                return 0
            fi
            if [[ "$_g2_state" == "t1b" ]]; then
                _g2_t1_ts_b=$_g2p_now; _g2_t1_hash_b="$_g2_snap_hash"; _g2_t1_slot_b=$_g2_snap_slot
                _g2_state="hold"
                _g2_answer="cannot"; _g2_reason="hold 0s/${G2_DELTA}s — T1 stamps A=${_g2_t1_ts_a} B=${_g2_t1_ts_b}"
                log_info "[g2-provider] T1 complete gen=${_g2_gen}: unstaked entry at ${_g2_staked_endpoint} on BOTH vantages (stamps A=${_g2_t1_ts_a} B=${_g2_t1_ts_b}, batched slots A=${_g2_t1_slot_a} B=${_g2_t1_slot_b}) — holding ${G2_DELTA}s"
            else
                # slot-advance, vantage B [g2-det-slot-advance] (same mechanism as A)
                if [[ $(( _g2_snap_slot - _g2_t1_slot_b )) -lt $G2_SLOT_ADVANCE_FLOOR ]]; then
                    _g2_answer="cannot"; _g2_reason="vantage B confirmed head advanced only $(( _g2_snap_slot - _g2_t1_slot_b )) slots across $(( _g2p_now - _g2_t1_ts_b ))s (T1 slot ${_g2_t1_slot_b} -> T2 slot ${_g2_snap_slot}); REQUIRED: >= ${G2_SLOT_ADVANCE_FLOOR} — a frozen/replayed head or a stalled cluster cannot testify about NOW, cannot-determine"
                    log_warn "[g2-provider] ${_g2_reason}"
                    _g2_env_alert "⚠️ G2 vantage B advanced only $(( _g2_snap_slot - _g2_t1_slot_b )) slots in $(( _g2p_now - _g2_t1_ts_b ))s (floor ${G2_SLOT_ADVANCE_FLOOR}) — a replayed/frozen chain head or a stalled cluster; verified-demote holds cannot-determine."
                    _g2_arm "re-arm after slot-advance floor on B"
                    return 0
                fi
                # node-table advance, vantage B [g2-det-advance-b] (same mechanism and the same
                # narrowed claim as A: a TOTALLY frozen response, not a re-observed proof entry)
                if [[ "$_g2_snap_hash" == "$_g2_t1_hash_b" ]]; then
                    _g2_answer="cannot"; _g2_reason="vantage B payload BYTE-IDENTICAL across $(( _g2p_now - _g2_t1_ts_b ))s (fingerprint ${_g2_snap_hash}) — cache suspected, cannot-determine"
                    log_warn "[g2-provider] ${_g2_reason}"
                    _g2_env_alert "⚠️ G2 vantage B served a byte-identical getClusterNodes payload $(( _g2p_now - _g2_t1_ts_b ))s apart — a cache in front of the RPC; verified-demote holds cannot-determine. Pin a non-cached vantage."
                    _g2_arm "re-arm after cache suspicion on B"
                    return 0
                fi
                # ── the verdict-minting site (all detectors passed on both vantages) ──
                # D2 COMPOSITION (the D4-arithmetic class, stated where the verdict is born): this
                # snapshot pair CANNOT see flip-back-then-vote after this read — the recheck's
                # staked-vote pin (_fresh_proof_recheck) owns that direction at the mutation edge
                # (6.4 wiring), and _proof_age_edge_check bounds THIS verdict's staleness there:
                # observed_at below is the T2 read stamp, so the edge check measures exactly the
                # window this proof has been aging. Different objects — the pin bounds BEHAVIOR,
                # the edge bounds STALENESS — they compose, they never merge.
                # SEVERITY OF A FALSE PROOF (panel fix round, B3 — verified by reading BLOCK6-PLAN
                # §5 and §6.4 before stating it): the gate is an ADDITIONAL requirement placed IN
                # FRONT of the staked mutation, never a trigger for one. The pre-existing,
                # live-tested v0.6.x path — delinquency detection, the vote-frozen observation and
                # _fresh_proof_recheck — must still pass on its own. So a false PROVEN here cannot
                # BY ITSELF cause a take; it can only fail to BLOCK a take that logic already
                # authorized. A double-sign therefore needs BOTH a false G2 proof AND a
                # false-frozen vote observation of a holder that is in fact alive and voting.
                _g2_t2_ts=$_g2p_now
                _g2p_hold_a=$(( _g2_t2_ts - _g2_t1_ts_a )); _g2p_hold_b=$(( _g2_t2_ts - _g2_t1_ts_b ))
                _g2_verdict="proven=yes|provider=verified-demote|observation_id=g2:gen=${_g2_gen}:t1=${_g2_t1_ts_a}:t2=${_g2_t2_ts}|vantage=${_liveness_first_provider:-}|obs_since=${_liveness_obs_since:-0}|blind_until=${_last_blind_end:-0}|observed_at=${_g2_t2_ts}"
                _g2_state="proven"; _g2_answer="yes"
                _g2_reason="proven gen=${_g2_gen}: held ${_g2p_hold_a}s(A)/${_g2p_hold_b}s(B) >= ${G2_DELTA}s"
                log_warn "[g2-provider] verified-demote PROVEN gen=${_g2_gen}: holder's unstaked identity at ${_g2_staked_endpoint} held ${_g2p_hold_a}s (A) / ${_g2p_hold_b}s (B) >= ${G2_DELTA}s on both pinned vantages, confirmed heads advanced $(( _g2_t2_slot_a - _g2_t1_slot_a )) (A) / $(( _g2_snap_slot - _g2_t1_slot_b )) (B) slots >= ${G2_SLOT_ADVANCE_FLOOR} with each slot batched INTO the response carrying the proof, node tables advanced per vantage, cross-vantage distinct, cluster-time within ±${G2_CLOCK_BUDGET}s — the demoted state is live NOW (observed_at=${_g2_t2_ts}; the gate is not wired into any take path in this build)"
            fi
            ;;
        hold)
            if [[ $(( _g2p_now - _g2_t1_ts_b )) -ge $G2_DELTA ]]; then
                _g2_state="t2a"
                _g2_reason="hold complete ($(( _g2p_now - _g2_t1_ts_b ))s >= ${G2_DELTA}s) — T2 re-snapshot"
                return 0
            fi
            _g2_answer="cannot"; _g2_reason="hold $(( _g2p_now - _g2_t1_ts_b ))s/${G2_DELTA}s"
            if [[ ${_g2_last_read_ts:-0} -gt 0 ]]; then
                [[ $(( _g2p_now - _g2_last_read_ts )) -lt $_G2_READ_PACE_SECS ]] && return 0
            fi
            _g2_last_read_ts=$_g2p_now
            _g2_flip=$(( 1 - _g2_flip ))
            if [[ $_g2_flip -eq 1 ]]; then _g2p_url="$G2_VANTAGE_A"; _g2p_lab="A"; else _g2p_url="$G2_VANTAGE_B"; _g2p_lab="B"; fi
            local _g2p_body2 _g2p_rc2 _g2p_pk2 _g2p_ep2 _g2p_seen2
            _g2p_body2=$(curl -s -m 5 "$_g2p_url" -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null)
            _g2p_rc2=$?
            _watchdog_pet   # §5 per-op pet: bounded op completed (rc captured above); no-op outside the armed unit
            if [[ $_g2p_rc2 -ne 0 ]] || ! echo "$_g2p_body2" | jq -e '.result' &>/dev/null; then
                return 0   # blind poll: unreachable is NOT absence — it kills nothing and proves nothing (T2 owns the proving)
            fi
            _g2p_seen2=0
            # ALL gossip values scanned, same rule as _g2_snap (panel fix round, G2-N2): present
            # iff ANY entry for the watched key sits at the baseline endpoint. `head -1` here made
            # an elsewhere-first ordering read as a mid-hold ABSENCE, which KILLS the attempt —
            # the same false negative as the T1/T2 site, and louder.
            # shellcheck disable=SC2086
            for _g2p_pk2 in $PRIMARY_UNSTAKED_PUBKEY; do
                _g2p_ep2=$(echo "$_g2p_body2" | jq -r --arg pk "$_g2p_pk2" --arg ep "$_g2_staked_endpoint" '[ .result[]? | select(.pubkey == $pk) | .gossip // empty ] | if (index($ep) != null) then "1" else "0" end' 2>/dev/null)
                [[ "$_g2p_ep2" == "1" ]] && { _g2p_seen2=1; break; }
            done
            if [[ $_g2p_seen2 -ne 1 ]]; then
                _g2_answer="no"; _g2_reason="unstaked entry ABSENT at ${_g2_staked_endpoint} on vantage ${_g2p_lab} mid-hold ($(( _g2p_now - _g2_t1_ts_b ))s in) — flip-back"
                log_warn "[g2-provider] mid-hold absence on vantage ${_g2p_lab} — NOT-PROVEN, full reset (the flip-then-flip-back kill): ${_g2_reason}"
                _g2_arm "re-arm after mid-hold absence"
            fi
            ;;
        proven)
            # dormant (zero reads): staleness is the mutation edge's job [6.0-COND-2]. But a
            # verdict older than PROOF_MAX_AGE would be refused there anyway — serving it is
            # noise, so it is WITHDRAWN and the machine re-proves from a fresh T1 (a withdrawal,
            # never an extension: nothing here can make old evidence younger).
            case "${PROOF_MAX_AGE:-}" in ''|*[!0-9]*) : ;; *)
                if [[ $(( _g2p_now - _g2_t2_ts )) -gt $PROOF_MAX_AGE ]]; then
                    log_info "[g2-provider] proven verdict gen=${_g2_gen} aged $(( _g2p_now - _g2_t2_ts ))s > PROOF_MAX_AGE=${PROOF_MAX_AGE}s — WITHDRAWN; re-proving from a fresh T1"
                    _g2_arm "re-prove after verdict aged out"
                fi
            ;; esac
            ;;
    esac
    return 0
}

# ── _g2_provider — the registered provider fn (consumed by require_relinquish_proof) ──────────
# The gate runs providers in a $() SUBSHELL, so this is a pure STATE REPORTER: zero network, zero
# writes (a write here would be stranded in the subshell), one structured verdict line on stdout.
# proven=yes is served ONLY from the minted verdict record (stamps frozen at T2); every other
# state answers its measured cannot/no with the reason — never a boolean, never a default-yes.
_g2_provider() {
    _watchdog_active || return 0
    _proof_role_is_spare || return 0
    [[ "$_g2_registered" == "1" ]] || return 0
    if [[ -n "$_g2_disabled" ]]; then
        printf 'proven=cannot|provider=verified-demote|observation_id=|vantage=%s|obs_since=%s|blind_until=%s|observed_at=0|g2_state=disabled|g2_reason=%s\n' "${_liveness_first_provider:-}" "${_liveness_obs_since:-0}" "${_last_blind_end:-0}" "vantage tripwire: ${_g2_disabled}"
        return 0
    fi
    if [[ "$_g2_state" == "proven" && -n "$_g2_verdict" ]]; then
        printf '%s\n' "$_g2_verdict"
        return 0
    fi
    printf 'proven=%s|provider=verified-demote|observation_id=|vantage=%s|obs_since=%s|blind_until=%s|observed_at=0|g2_state=%s|g2_reason=%s\n' "$_g2_answer" "${_liveness_first_provider:-}" "${_liveness_obs_since:-0}" "${_last_blind_end:-0}" "$_g2_state" "$_g2_reason"
    return 0
}
# ── [g2-provider] end shared block ──

# ── [fence-rot] holder-side fence re-verification + FENCE_ROT_GRACE escalation — BYTE-IDENTICAL in both daemons (test_fence_rot) ──
# v0.7 (Block 5.4, §2.1-rev2.1 №2): the pairing token attests the holder's fence AT PAIRING
# TIME only — the spare cannot see post-pairing rot (unit masked, a drop-in re-adding
# Restart=, disarm); there is no channel, by design (DESIGN-v0.7-ADDENDUM §2.1). The load is
# holder-side: while ARMED, this block re-verifies OUR OWN effective fence properties once per
# FENCE_ROT_CHECK_SECS and treats armed+staked+fence-broken as fence-worthy — behind an
# ESCALATION WINDOW, never an instant action: one systemd typo must not take down a healthy
# production validator faster than a human can read a page.
# STRUCTURALLY INERT outside the armed unit: every entrypoint no-ops unless _watchdog_active()
# — on today's hosts and in every harness that is zero systemctl calls, zero pages, zero state
# (asserted by event log in test_fence_rot (1)/(14), not by this prose).
# Every systemd fact used below is container-VERIFIED on systemd 249 (the fleet floor) AND 255
# — design record verify-rot-properties.md (private tree); rows cited inline. claim=check: a
# property read must SUCCEED and show a state whose fence-kill is verified before anything arms
# the demote clock — cannot-verify is NOT rot (the CLI is not the enforcement plane: PID 1
# enforces WatchdogSec/OnFailure regardless of whether systemctl answers us).
FENCE_ROT_CHECK_SECS="${FENCE_ROT_CHECK_SECS:-60}"   # armed sweep cadence (validated >= 10; raising it is drift-announced — rot is seen later)
FENCE_ROT_GRACE="${FENCE_ROT_GRACE:-1800}"           # verified-rot window before the graceful self-demote (validated >= max(600, ALERT_THROTTLE) — see validate_numeric_config)
ROT_MONITOR_UNIT="solana-failover-monitor.service"   # the armed monitor unit — MUST match failover-arm.sh MONITOR_UNIT_NAME (the ceremony's only monitor name); plain constant like FENCE_UNIT_REAL: no env channel, no drift vector

_rot_intent=""               # fence intent captured at startup under the armed unit ("" = never captured)
# PER-SIGNAL escalation anchors (panel fix round, ROT-DEMOTE-1 BLOCKER) — mono stamps,
# 0-sentinels: each is the FIRST verified detection of ITS OWN signal's current contiguous rot
# episode. WHY per-SIGNAL, not one shared anchor (the shipped v1 hole) and not per-read-GROUP:
# a shared anchor conflates "when THIS rot began" with "when ANY rot was last seen" — a fence
# that GENUINELY healed (LoadState read succeeded, answered loaded) under a blind sibling
# monitor read kept the ancient anchor alive, so a FRESH masked read 50 min later demoted with
# 0 s of the 1800 s grace (executed on both daemons: demotes=[3000] where [4800] is correct —
# the ratified "never an instant action" contract broken). Group-level anchors reopen the same
# hole one level down: file-GONE @t0 (S1), file restored @t0+60 (S1 positively clean) while the
# LoadState read is blind, fresh MASKED @t0+3000 (S2) — a shared F-group anchor would still be
# t0 → instant demote; S2's OWN anchor is fresh → full grace. Deliberately NOT persisted: a
# daemon restart re-opens FRESH windows, which can only DELAY the demote, never fabricate one
# (the H3 fresh-timer rule).
_rot_s1_since=0              # S1 file-classification (which fence unit files exist vs the captured intent)
_rot_s2_since=0              # S2 fence LoadState (masked / not-found / bad-setting)
_rot_s3_since=0              # S3 monitor Restart (≠ no)
_rot_s4_since=0              # S4 monitor OnFailure (no longer naming the armed fence)
_last_rot_page=0             # demote-class CRITICAL re-page throttle stamp (repeats only)
_last_rot_sweep=0            # sweep cadence stamp (repeats only — the first armed sweep is immediate)
_rot_pageclass_paged=0       # a page-class drift page went out this drift episode (drives the one resolution info)
_last_rot_pageclass_page=0   # page-class re-page throttle stamp
_rot_cv_streak=0             # consecutive sweeps with >= 1 failed/unparseable systemctl read
_last_rot_cv_page=0          # cannot-verify blind-page throttle stamp (the alpenglow blind-streak pattern)
_rot_unstaked_noted=0        # expiry-while-unstaked info sent once per episode
_last_rot_demote_try=0       # expiry demote-ATTEMPT throttle stamp (ROT-INT-2), 0-sentinel — see the expiry branch

# Startup anchor: WHICH fence the arm ceremony installed is this run's INTENT — captured once,
# from startup_checks, under the armed unit. Capturing lazily at the first sweep instead would
# bless a deletion that happened between startup and that sweep as "intent"; the lazy call in
# the sweep below is a fallback for partial harness drives only. real→none / real→page-only AT
# RUNTIME then classify as "the fence is GONE". Armed with intent `none` is rot-from-startup:
# the ceremony never installs the monitor unit without a fence, so an armed monitor with no
# fence unit means the fence was removed while this daemon was down (the missing-unit dispatch
# death is verify-onfailure-missing-unit.md — enqueue ignored, fence never runs).
_rot_capture_intent() {
    _watchdog_active || return 0
    _rot_intent=$(_fence_unit_state)
    log_info "[fence-rot] armed — fence intent at startup: ${_rot_intent} (sweep every ${FENCE_ROT_CHECK_SECS}s, escalation grace ${FENCE_ROT_GRACE}s)"
    return 0
}

# The ONE bounded systemctl read funnel — every sweep read goes through here, so every read is
# timeout-bounded AND petted structurally (a future read added through the funnel cannot forget
# its pet). Pet-gap worst case, derived (the A3 style): a full sweep is 3 reads × (5 s + 2 s
# kill-grace) = 21 s of BOUND plus the expiry identity read (8 s, its own timeout) ≈ 29 s of
# bound — but the pet fires after EACH op completes, so the largest unpetted span the sweep can
# add is ONE op's bound + glue ≈ 7–8 s, far under WatchdogSec 30 and under the daemon-wide
# ≈ 22 s A3 worst case (the single longest admin op), which therefore still governs. The pet
# runs inside the $()-capture subshell: WATCHDOG=1 datagrams are fire-and-forget and $$ still
# expands to the daemon's own PID there (the [watchdog] MAINPID note), so attribution holds.
_rot_sysread() {
    local _rs_out _rs_rc
    _rs_out=$(timeout -k 2 5 systemctl "$@" 2>/dev/null); _rs_rc=$?
    _watchdog_pet   # §5 per-op pet (Block 5.4): bounded systemctl read completed — a timeout return IS completion (`timeout` returned; the monitor is alive) — no-op outside the armed unit
    printf '%s' "$_rs_out"
    return $_rs_rc
}

# Oldest (smallest) NONZERO mono stamp among the args — 0 when none is set. Serves the rot
# page's "persisting Xs" (oldest anchor among currently-FIRING signals — exactly "≥ 1 firing
# signal whose OWN window is that old") and the resolution's "resolved after Xs" (oldest anchor
# open before the healing sweep). Plain positional args, no arrays (bash 3.2); pure — safe
# under $() capture.
_rot_oldest() {
    local _ro_min=0 _ro_v
    for _ro_v in "$@"; do
        [[ "${_ro_v:-0}" -gt 0 ]] || continue
        if [[ $_ro_min -eq 0 || "$_ro_v" -lt $_ro_min ]]; then _ro_min=$_ro_v; fi
    done
    printf '%s' "$_ro_min"
    return 0
}

# The sweep. Classification (claim=check — never demote on a guess):
#   demote-class = a read SUCCEEDED and shows a state whose fence-kill is container-VERIFIED
#                  (record rows: file gone / masked / bad-setting → OnFailure enqueue refused;
#                  Restart≠no → on systemd 249, the fleet floor, the fence NEVER dispatches —
#                  watchdog-kill cycling included; OnFailure not naming the fence → only listed
#                  units are ever enqueued) → opens/extends the escalation window.
#   page-class   = verified drift that does NOT kill the fence now (WatchdogSec config drift —
#                  the RUNNING watchdog is reload-immune, record §2; StartLimitIntervalUSec≠0
#                  with Restart=no — single failure still reaches terminal failed + dispatch;
#                  both-units XOR; monitor unit not loadable — its other keys are STUBS, record
#                  §1, and must never be classified) → CRITICAL page, NO demote clock.
#   cannot-verify = systemctl timed out/errored or a requested key was silently dropped (rc 0!
#                  — record §1): NOT rot; page only after a 4-sweep streak; reads that DID
#                  succeed in the same sweep still classify normally; a blind sweep neither
#                  heals nor extends an open window (blindness must not close what it cannot see).
# Every demote-class signal is tracked per-sweep as one of THREE states feeding its own anchor
# (the uniform rule at the anchor-update section below): FIRING (verified rot), POSITIVELY
# CLEAN (a read SUCCEEDED and showed the healthy value), or BLIND (failed/absent/stub read —
# neither of the others). Signals: S1 = the file classification vs intent; S2 = fence
# LoadState; S3/S4 = monitor Restart / OnFailure (both from the one monitor-show read, but
# anchored separately — see the per-SIGNAL rationale at the anchor declarations).
_fence_rot_check() {
    _watchdog_active || return 0
    local _rot_now _fus_now _rot_read_unit _rot_expect_unit _rot_ls _rot_rc _rot_out _rot_line
    local _rot_found="" _rot_drift="" _rot_cv=0 _rot_lethal=0
    local _rot_s1_rot=0 _rot_s1_clean=0 _rot_s2_rot=0 _rot_s2_clean=0
    local _rot_s3_rot=0 _rot_s3_clean=0 _rot_s4_rot=0 _rot_s4_clean=0
    local _rot_prev_open=0 _rot_prev_oldest=0 _rot_open_since _rot_a1 _rot_a2 _rot_a3 _rot_a4
    local _rot_mon_ls="" _rot_mon_restart="" _rot_mon_onfail="" _rot_mon_sli="" _rot_seen_onfail=0
    local _rot_wd_cfg _rot_wd_env _rot_val _rot_id _rot_page_due _rot_remaining
    _rot_now=$(mono_now)   # mono clock only — the daemons are the monotonic-clock domain (CI pins the wall-clock site count)
    if [[ ${_last_rot_sweep:-0} -gt 0 ]]; then
        [[ $(( _rot_now - _last_rot_sweep )) -lt ${FENCE_ROT_CHECK_SECS:-60} ]] && return 0
    fi
    _last_rot_sweep=$_rot_now
    [[ -z "$_rot_intent" ]] && _rot_capture_intent
    [[ "$_rot_intent" == "real" || "$_rot_intent" == "none" ]] && _rot_lethal=1   # page-only intent has no REAL fence to lose — its drifts are page-class
    case "$_rot_intent" in
        real)      _rot_expect_unit="${FENCE_UNIT_REAL##*/}" ;;
        page-only) _rot_expect_unit="${FENCE_UNIT_PAGE_ONLY##*/}" ;;
        *)         _rot_expect_unit="" ;;
    esac
    # pre-sweep episode snapshot: drives the ONE-resolution-per-episode rule and the resolved-
    # after text (the anchors themselves may be reset by this sweep's positive cleans below)
    _rot_prev_oldest=$(_rot_oldest "${_rot_s1_since:-0}" "${_rot_s2_since:-0}" "${_rot_s3_since:-0}" "${_rot_s4_since:-0}")
    [[ ${_rot_prev_oldest:-0} -gt 0 ]] && _rot_prev_open=1

    # (1) which fence unit files exist NOW — the pure-file classifier re-run (always
    # verifiable, so S1 is never blind under a lethal intent: it FIRES on the demote-class
    # mismatches below and is POSITIVELY CLEAN when the classification matches the intent).
    _fus_now=$(_fence_unit_state)
    case "$_rot_intent" in
        real)
            if [[ "$_fus_now" == "none" ]]; then
                _rot_s1_rot=1
                _rot_found="${_rot_found}; REAL fence unit file GONE (${FENCE_UNIT_REAL}) — fix: re-run 'failover arm'"
            elif [[ "$_fus_now" == "page-only" ]]; then
                _rot_s1_rot=1
                _rot_found="${_rot_found}; REAL fence unit replaced by page-only at runtime (the mutating fence is gone) — fix: re-run 'failover arm'"
            else
                _rot_s1_clean=1   # classification real matches intent real — the stale XOR sibling below is page-class drift, not an S1 demote signal
                if [[ -e "$FENCE_UNIT_PAGE_ONLY" ]]; then
                    _rot_drift="${_rot_drift}; BOTH fence unit files present (XOR violation — an arm-ceremony bug state; real dominates dispatch) — fix: re-run 'failover arm' to remove the stale sibling"
                fi
            fi
            ;;
        none)
            # rot-from-startup: NO positive clean exists by construction — a fence unit file
            # re-created at runtime does not re-decide the startup intent, so S1's anchor
            # persists and the demote lands at t(armed-start)+grace (lens-B-verified; the page
            # says so explicitly below).
            _rot_s1_rot=1
            _rot_found="${_rot_found}; armed monitor with NO fence unit installed (intent at startup: none — the fence was removed while the daemon was down) — fix: re-run 'failover arm', then restart the monitor unit (a fence unit file re-created WITHOUT re-running 'failover arm' + restarting the monitor will NOT clear this escalation — intent was captured none at startup)"
            ;;
        *)
            if [[ "$_fus_now" == "none" ]]; then
                _rot_drift="${_rot_drift}; page-only fence unit file GONE (${FENCE_UNIT_PAGE_ONLY}) — fix: re-run 'failover arm'"
            elif [[ "$_fus_now" == "real" ]]; then
                _rot_drift="${_rot_drift}; REAL fence unit appeared under a run armed page-only (the №1 deadly combination arising at RUNTIME — the startup check saw page-only) — fix: re-run 'failover arm', or restart this daemon so the №1 startup refusal re-decides"
            else
                _rot_s1_clean=1   # page-only present under page-only intent (no lethal fence to lose — S1 cannot fire here; the clean keeps the uniform rule total)
            fi
            ;;
    esac

    # (2) the installed fence unit's LoadState — the read that sees what the file test cannot:
    # the real mask shape is the /etc unit file REPLACED by a /dev/null symlink (plain
    # `systemctl mask` refuses on /etc-resident units and mask --runtime is precedence-shadowed
    # — record §4), and `test -e` on that symlink is TRUE. Detection is by VALUE, not rc
    # (missing unit: LoadState=not-found with rc 0 — record §1).
    # S2 is BLIND when there is no file to read (_fus_now=none — S1 carries that state) and
    # when the read fails/answers empty; ONLY a succeeded read answering `loaded` is the
    # positive clean that closes S2's window (a verified error/merged state is page-class
    # drift, not clean: it did not show the healthy value).
    if [[ "$_fus_now" != "none" ]]; then
        if [[ "$_fus_now" == "real" ]]; then _rot_read_unit="${FENCE_UNIT_REAL##*/}"; else _rot_read_unit="${FENCE_UNIT_PAGE_ONLY##*/}"; fi
        _rot_ls=$(_rot_sysread show "$_rot_read_unit" -p LoadState --value); _rot_rc=$?
        if [[ $_rot_rc -ne 0 || -z "$_rot_ls" ]]; then
            _rot_cv=1
        else
            case "$_rot_ls" in
                loaded) _rot_s2_clean=1 ;;
                masked)
                    if [[ $_rot_lethal -eq 1 ]]; then
                        _rot_s2_rot=1
                        _rot_found="${_rot_found}; fence unit ${_rot_read_unit} LoadState=masked (the unit file is a /dev/null mask; OnFailure enqueue is refused — dispatch dead) — fix: systemctl unmask ${_rot_read_unit} && re-run 'failover arm'"
                    else
                        _rot_drift="${_rot_drift}; page-only fence unit LoadState=masked — fix: systemctl unmask ${_rot_read_unit} && re-run 'failover arm'"
                    fi
                    ;;
                not-found|bad-setting)
                    if [[ $_rot_lethal -eq 1 ]]; then
                        _rot_s2_rot=1
                        _rot_found="${_rot_found}; fence unit ${_rot_read_unit} LoadState=${_rot_ls} (unloadable — OnFailure enqueue is refused, dispatch dead) — fix: repair the unit file and systemctl daemon-reload, or re-run 'failover arm'"
                    else
                        _rot_drift="${_rot_drift}; page-only fence unit LoadState=${_rot_ls} — fix: repair the unit file and systemctl daemon-reload, or re-run 'failover arm'"
                    fi
                    ;;
                *)
                    # error/merged/stub: verified drift, kill-NOW unproven in the container —
                    # the claim=check split says page, never demote (record §3, last row)
                    _rot_drift="${_rot_drift}; fence unit ${_rot_read_unit} LoadState=${_rot_ls} (non-loaded state whose dispatch-kill is UNVERIFIED) — fix: systemctl daemon-reload + inspect, or re-run 'failover arm'"
                    ;;
            esac
        fi
    fi

    # (3) the monitor unit's dispatch contract: Restart must be `no`, OnFailure must name the
    # armed fence, the R8 pair's StartLimitIntervalUSec must be 0. Parsed k=v and
    # order-independent — property order AND the OnFailure list order are UNSTABLE across
    # identical reads (record §1), so the fence check is word-CONTAINMENT, never equality.
    _rot_out=$(_rot_sysread show "$ROT_MONITOR_UNIT" -p LoadState,Restart,OnFailure,StartLimitIntervalUSec); _rot_rc=$?
    if [[ $_rot_rc -ne 0 || -z "$_rot_out" ]]; then
        _rot_cv=1   # whole-read failure: S3 and S4 both BLIND — their anchors are left untouched
    else
        while IFS= read -r _rot_line; do
            case "$_rot_line" in
                (LoadState=*) _rot_mon_ls="${_rot_line#LoadState=}" ;;
                (Restart=*) _rot_mon_restart="${_rot_line#Restart=}" ;;
                (OnFailure=*) _rot_mon_onfail="${_rot_line#OnFailure=}"; _rot_seen_onfail=1 ;;
                (StartLimitIntervalUSec=*) _rot_mon_sli="${_rot_line#StartLimitIntervalUSec=}" ;;
            esac
        done <<< "$_rot_out"
        if [[ -z "$_rot_mon_ls" || -z "$_rot_mon_restart" || $_rot_seen_onfail -eq 0 || -z "$_rot_mon_sli" ]]; then
            # a requested key ABSENT from the output: systemctl silently drops unknown/renamed
            # property names with rc 0 (record §1) — that is cannot-verify, never "OK": S3/S4
            # BLIND (this exact shape once blocked every heal forever — the ROT-DEMOTE-1 red)
            _rot_cv=1
        elif [[ "$_rot_mon_ls" != "loaded" ]]; then
            # THE STUB TRAP (record §1): a not-loaded unit answers Restart=no + OnFailure= —
            # healthy-looking AND rot-looking stubs at once; classifying them would be acting
            # on fabricated values. Verified drift (the monitor unit itself is not loadable —
            # next start impossible/altered), kill-NOW unverified → page-class, and the
            # sibling keys are dropped unclassified: S3/S4 go BLIND here, not clean, not rot —
            # a stub Restart=no must never close S3's open window.
            _rot_drift="${_rot_drift}; monitor unit ${ROT_MONITOR_UNIT} LoadState=${_rot_mon_ls} (unit not loadable — its other properties are stubs; next start impossible from this state; current-run dispatch unverified) — fix: re-run 'failover arm'"
        else
            if [[ "$_rot_mon_restart" != "no" ]]; then
                if [[ $_rot_lethal -eq 1 ]]; then
                    _rot_s3_rot=1
                    _rot_found="${_rot_found}; monitor Restart=${_rot_mon_restart} (must be no: with our StartLimitIntervalSec=0 the unit NEVER reaches terminal failed on systemd 249 — watchdog kills included — so the fence NEVER dispatches; on 255 it re-dispatches per restart iteration, outside the verified one-hop contract) — fix: remove the drop-in re-adding Restart= (systemctl cat ${ROT_MONITOR_UNIT} shows its path) and systemctl daemon-reload, or re-run 'failover arm'"
                else
                    _rot_drift="${_rot_drift}; monitor Restart=${_rot_mon_restart} (must be no — the R8 pair) — fix: remove the drop-in and systemctl daemon-reload"
                fi
            else
                _rot_s3_clean=1   # read succeeded, monitor loaded (stubs excluded above), Restart=no — the positive clean
            fi
            if [[ -n "$_rot_expect_unit" ]]; then
                case " $_rot_mon_onfail " in
                    (*" $_rot_expect_unit "*) _rot_s4_clean=1 ;;   # containment on a loaded monitor's real value — the positive clean
                    (*)
                        if [[ $_rot_lethal -eq 1 ]]; then
                            _rot_s4_rot=1
                            _rot_found="${_rot_found}; monitor OnFailure no longer names ${_rot_expect_unit} (now: '${_rot_mon_onfail}') — only listed units are ever enqueued, so the fence NEVER dispatches — fix: re-run 'failover arm'"
                        else
                            _rot_drift="${_rot_drift}; monitor OnFailure no longer names ${_rot_expect_unit} (now: '${_rot_mon_onfail}') — fix: re-run 'failover arm'"
                        fi
                        ;;
                esac
            fi
            if [[ "$_rot_mon_sli" != "0" ]]; then
                _rot_drift="${_rot_drift}; monitor StartLimitIntervalUSec=${_rot_mon_sli} (the R8 pair wants 0; with Restart=no a single failure still reaches terminal failed + dispatch — record §3 — but repeated fence-driven restarts can now hit the start limit) — fix: remove the drop-in and systemctl daemon-reload, or re-run 'failover arm'"
            fi
            # (4) WatchdogSec CONFIG for the NEXT start vs what THIS run was armed with. The
            # show-side WatchdogUSec property is RUNTIME-ONLY (infinity while stopped, frozen
            # at the started value while running — record §2), so comparing it to our env would
            # be vacuous; the config truth is `systemctl cat` (unit file + drop-ins, file-fresh
            # even before daemon-reload), last WatchdogSec= line governing. The arm renders
            # integer seconds — any other spelling is itself post-arm editing. The RUNNING
            # watchdog is reload-immune (record §2), so this drift is next-start attestation
            # rot: page-class, never a demote clock.
            _rot_out=$(_rot_sysread cat "$ROT_MONITOR_UNIT"); _rot_rc=$?
            if [[ $_rot_rc -ne 0 ]]; then
                _rot_cv=1
            else
                _rot_wd_cfg=$(printf '%s\n' "$_rot_out" | grep '^WatchdogSec=' | tail -1 | cut -d= -f2)
                case "${WATCHDOG_USEC:-}" in
                    (''|*[!0-9]*) _rot_drift="${_rot_drift}; WATCHDOG_USEC env is non-numeric ('${WATCHDOG_USEC:-}') — cannot attest the armed watchdog value" ;;
                    (*)
                        _rot_wd_env=$(( WATCHDOG_USEC / 1000000 ))
                        _rot_val="${_rot_wd_cfg%s}"
                        if [[ -z "$_rot_wd_cfg" ]]; then
                            _rot_drift="${_rot_drift}; WatchdogSec absent from the monitor unit config (the NEXT start would run UNWATCHDOGGED — the fence would never fire on that tenure) — fix: re-run 'failover arm'"
                        elif [[ "$_rot_val" =~ ^[0-9]+$ ]] && [[ $(( WATCHDOG_USEC % 1000000 )) -eq 0 && $((10#$_rot_val)) -eq $_rot_wd_env ]]; then
                            :
                        else
                            _rot_drift="${_rot_drift}; monitor WatchdogSec config is now '${_rot_wd_cfg}' but this run was armed with ${_rot_wd_env}s (WATCHDOG_USEC=${WATCHDOG_USEC}) — next-start attestation drift; the pairing token attested the armed value — fix: re-run 'failover arm' (re-render + re-pair)"
                        fi
                        ;;
                esac
            fi
        fi
    fi

    # cannot-verify streak — the alpenglow blind-streak pattern: WARN every blind sweep, page
    # only once the streak says it is not a blip (4 sweeps), throttled, first page immediate at
    # the threshold; NEVER a demote clock.
    if [[ $_rot_cv -eq 1 ]]; then
        _rot_cv_streak=$(( ${_rot_cv_streak:-0} + 1 ))
        log_warn "[fence-rot] systemctl read failed/unparseable this sweep (streak ${_rot_cv_streak}) — cannot-verify is NOT rot; reads that succeeded still classified"
        if [[ ${_rot_cv_streak} -ge 4 ]]; then
            if [[ ${_last_rot_cv_page:-0} -eq 0 || $(( _rot_now - _last_rot_cv_page )) -ge ${ALERT_THROTTLE:-600} ]]; then
                _last_rot_cv_page=$_rot_now
                alert_warn "⚠️ FENCE-ROT SWEEP BLIND: ${_rot_cv_streak} consecutive sweeps could not verify the fence properties (systemctl failing/timing out). NOT rot — no demote clock (PID 1 enforces the fence regardless of the CLI) — but the armed holder is flying without its rot re-verification. Check systemd/D-Bus health."
            fi
        fi
    else
        _rot_cv_streak=0
    fi

    # ── per-signal anchor update — the UNIFORM rule (ROT-DEMOTE-1): a signal FIRING this sweep
    # sets its OWN anchor iff 0; a signal POSITIVELY CLEAN this sweep resets its anchor to 0; a
    # BLIND signal leaves its anchor untouched (blindness must not close what it cannot see).
    # The preserved 9d semantics falls out: a continuously-rotted signal across blind sweeps
    # still demotes at the FIRST verified rot past grace, because no positive clean ever
    # intervened — while a signal that WAS positively seen healthy gets a fresh window for any
    # later re-rot, regardless of what its siblings' reads were doing (the panel's executed
    # instant-demote hole). Four plain variables, no arrays — bash 3.2.
    if [[ $_rot_s1_rot -eq 1 ]]; then
        [[ ${_rot_s1_since:-0} -eq 0 ]] && _rot_s1_since=$_rot_now
    elif [[ $_rot_s1_clean -eq 1 ]]; then
        _rot_s1_since=0   # S1 positive-clean reset: the file classification matches the intent again
    fi
    if [[ $_rot_s2_rot -eq 1 ]]; then
        [[ ${_rot_s2_since:-0} -eq 0 ]] && _rot_s2_since=$_rot_now
    elif [[ $_rot_s2_clean -eq 1 ]]; then
        _rot_s2_since=0   # S2 positive-clean reset: the LoadState read SUCCEEDED and answered loaded — this line closing S2's window on POSITIVE evidence (never on blindness) is what test_fence_rot (6)/(17) measure; neutering it is the stale-anchor control
    fi
    if [[ $_rot_s3_rot -eq 1 ]]; then
        [[ ${_rot_s3_since:-0} -eq 0 ]] && _rot_s3_since=$_rot_now
    elif [[ $_rot_s3_clean -eq 1 ]]; then
        _rot_s3_since=0   # S3 positive-clean reset: loaded monitor answered Restart=no
    fi
    if [[ $_rot_s4_rot -eq 1 ]]; then
        [[ ${_rot_s4_since:-0} -eq 0 ]] && _rot_s4_since=$_rot_now
    elif [[ $_rot_s4_clean -eq 1 ]]; then
        _rot_s4_since=0   # S4 positive-clean reset: loaded monitor's OnFailure names the armed fence
    fi

    if [[ -n "$_rot_found" ]]; then
        _rot_found="${_rot_found#; }"
        if [[ $_rot_prev_open -eq 0 ]]; then
            log_warn "[fence-rot] VERIFIED fence-kill drift — escalation window OPENED (grace ${FENCE_ROT_GRACE}s): ${_rot_found}"
        fi
        # the page's "persisting Xs / demote in Ys" and the expiry test key on the OLDEST
        # anchor among signals FIRING THIS SWEEP — i.e. "≥ 1 currently-verified rot whose OWN
        # window is ≥ grace old"; a signal merely blind right now contributes nothing.
        _rot_a1=0; [[ $_rot_s1_rot -eq 1 ]] && _rot_a1=${_rot_s1_since:-0}
        _rot_a2=0; [[ $_rot_s2_rot -eq 1 ]] && _rot_a2=${_rot_s2_since:-0}
        _rot_a3=0; [[ $_rot_s3_rot -eq 1 ]] && _rot_a3=${_rot_s3_since:-0}
        _rot_a4=0; [[ $_rot_s4_rot -eq 1 ]] && _rot_a4=${_rot_s4_since:-0}
        _rot_open_since=$(_rot_oldest "$_rot_a1" "$_rot_a2" "$_rot_a3" "$_rot_a4")
        [[ ${_rot_open_since:-0} -eq 0 ]] && _rot_open_since=$_rot_now   # unreachable (a firing signal always has its anchor set above) — belt: an empty read here must fail toward a FULL fresh window, never toward instant
        _rot_remaining=$(( FENCE_ROT_GRACE - (_rot_now - _rot_open_since) ))
        [[ $_rot_remaining -lt 0 ]] && _rot_remaining=0
        _rot_page_due=1
        [[ ${_last_rot_page:-0} -gt 0 && $(( _rot_now - _last_rot_page )) -lt ${ALERT_THROTTLE:-600} ]] && _rot_page_due=0   # rot re-page throttle (repeats only — the 0-sentinel first page is IMMEDIATE: on a young-uptime host an unguarded now-minus-0 gate would silently delay it)
        if [[ $_rot_page_due -eq 1 ]]; then
            _last_rot_page=$_rot_now
            alert "FENCE ROT (verified): ${_rot_found}. Persisting $(( _rot_now - _rot_open_since ))s; graceful self-demote in ${_rot_remaining}s unless fixed (escalation window — never instant)." "${STAKED_PUBKEY:-unknown}" "FENCE ROT — ARMED HOLDER 🚨"
        fi
        # §2.1-rev2.1 №2 / D3 — WHY THIS WINDOW DOES NOT REOPEN DOUBLE-SIGN (the reasoning lives
        # AT the check, not in docs only): during the grace the holder is VOTING and PAGING —
        # the spare's silence-based path (watchdog-elapsed) cannot fire against a voting holder,
        # so the window adds no double-sign exposure; if the grace expires, the demote below is
        # the GRACEFUL path the spare consumes via verified-demote proof — an automatic failover
        # to the healthy side.
        if [[ $(( _rot_now - _rot_open_since )) -ge $FENCE_ROT_GRACE ]]; then
            # ROT-INT-2 demote-attempt throttle, AT the rot call site (the adapters are not
            # reworked): the FIRST attempt at expiry is immediate; while an attempt leaves this
            # node staked (adapter blocked/DRY_RUN/wedged), re-attempts fire once per
            # ALERT_THROTTLE — the adapters page internally per attempt, and per-sweep retries
            # were 60 CRITICALs/hour during an incident already ≥ 30 min old and continuously
            # paged (the throttle doctrine). The verified-STAKED identity gate below runs per
            # ATTEMPT, unchanged — a throttled sweep attempts nothing, so it reads nothing.
            if [[ ${_last_rot_demote_try:-0} -gt 0 && $(( _rot_now - _last_rot_demote_try )) -lt ${ALERT_THROTTLE:-600} ]]; then
                log_warn "[fence-rot] demote retry throttled — last attempt $(( _rot_now - _last_rot_demote_try ))s ago, next at ${ALERT_THROTTLE:-600}s (rot pages continue; the identity re-verify runs per attempt)"
            else
                _rot_id=$(get_local_identity 2>/dev/null) || true
                _watchdog_pet   # §5 per-op pet (Block 5.4): bounded identity read completed (8 s own timeout) — no-op outside the armed unit
                if [[ -n "$STAKED_PUBKEY" && "$_rot_id" == "$STAKED_PUBKEY" ]]; then
                    # act-then-alert: the demote path performs the safety action FIRST and carries
                    # its own alerting; the reason below IS the demote page's text.
                    _last_rot_demote_try=$_rot_now
                    _rot_graceful_demote "Fence rot persisted ${FENCE_ROT_GRACE}s while ARMED+STAKED: ${_rot_found}. Graceful demote — the spare takes over via the verified-demote proof; the healthy side continues."
                elif [[ -n "$UNSTAKED_PUBKEY" && "$_rot_id" == "$UNSTAKED_PUBKEY" ]]; then
                    if [[ ${_rot_unstaked_noted:-0} -eq 0 ]]; then
                        _rot_unstaked_noted=1
                        alert_info "ℹ️ fence-rot grace expired but this node is already unstaked — nothing to protect, NO demote; fix the fence (pages continue per throttle)"
                    fi
                else
                    # unreadable/unclassifiable identity: demoting on that would be a GUESS — keep
                    # paging, re-check next sweep (the demote needs a VERIFIED staked read; a
                    # no-attempt sweep does not arm the retry throttle — the demote lands on the
                    # next READABLE staked sweep, not one throttle later)
                    log_warn "[fence-rot] grace expired but the local identity is unreadable/unclassifiable ('${_rot_id:-}') — NOT demoting on a guess; paging continues, re-checking next sweep"
                fi
            fi
        fi
    elif [[ ${_rot_s1_since:-0} -eq 0 && ${_rot_s2_since:-0} -eq 0 && ${_rot_s3_since:-0} -eq 0 && ${_rot_s4_since:-0} -eq 0 ]]; then
        # nothing firing AND no window still open: every previously-open window was closed by
        # a POSITIVE clean read on its own signal (an anchor a blind signal holds keeps this
        # arm unreached — no resolution during blindness, exactly the 9d contract)
        if [[ $_rot_prev_open -eq 1 ]]; then
            alert_info "✅ fence rot resolved after $(( _rot_now - _rot_prev_oldest ))s — every open demote-class window closed by a positive clean read on its own signal; escalation window closed"
            _last_rot_page=0; _rot_unstaked_noted=0; _last_rot_demote_try=0   # rot heal: the episode ENDS here — EPISODIC (the anchor-trap class): stale state would let a later re-rot demote at grace-minus-history or swallow its first page; test_fence_rot (6) measures the fresh window, its control the stale-anchor early fire
        fi
    fi

    if [[ -n "$_rot_drift" ]]; then
        _rot_drift="${_rot_drift#; }"
        _rot_page_due=1
        [[ ${_last_rot_pageclass_page:-0} -gt 0 && $(( _rot_now - _last_rot_pageclass_page )) -lt ${ALERT_THROTTLE:-600} ]] && _rot_page_due=0   # page-class re-page throttle (repeats only)
        if [[ $_rot_page_due -eq 1 ]]; then
            _last_rot_pageclass_page=$_rot_now
            _rot_pageclass_paged=1
            alert "FENCE CONFIG DRIFT (verified; does NOT kill the fence now — no demote clock): ${_rot_drift}" "${STAKED_PUBKEY:-unknown}" "FENCE CONFIG DRIFT (armed) 🚨"
        fi
    elif [[ $_rot_cv -eq 0 && ${_rot_pageclass_paged:-0} -eq 1 ]]; then
        _rot_pageclass_paged=0; _last_rot_pageclass_page=0
        alert_info "✅ fence config drift cleared — page-class properties back at the armed baseline"
    fi
    return 0
}
# ── [fence-rot] end shared block ──

# v0.7 (Block 5.4): the [fence-rot] escalation's demote — deliberately OUTSIDE the
# byte-identical block: each daemon reuses its OWN existing set-identity-to-unstaked path (no
# new mutation site — the spare consumes the resulting flip/proof exactly as it consumes any
# graceful demote). The reused function carries the standard DRY_RUN mutation guard, the
# keypair check and the wedge/hard-stop escalation — the rot path adds NO second mutation
# surface (defense in depth: armed-real + DRY_RUN=true is already refused at startup by
# _enforce_one_arm_state; test_fence_rot (10) baits both layers).
_rot_graceful_demote() { switch_to_unstaked "$1"; }

# v0.6.8 (B1): the demote admin-socket call wedged (timed out). The self-fence's contract is that the
# staked identity STOPS voting even when set-identity cannot run — so escalate to a HARD STOP of the
# validator process (the safe direction: a dead validator cannot double-sign). Gated by SELF_FENCE_HARD_STOP.
# Never reached in DRY_RUN (switch_to_unstaked returns before the real path).
# v0.6.8 (S4): VERIFY the stop before reporting success — a false "stopped" would make the caller reset its
# timer and stop retrying while the node may still be staked-and-voting. Returns 0 ONLY when the validator
# is confirmed DOWN; returns 1 if hard-stop is disabled, if the validator survives SIGKILL, or if nothing
# was provably stopped (systemctl failed AND no known validator process found) — caller keeps retrying/paging.
_selffence_hard_stop() {
    local why="$1"
    if [[ "${SELF_FENCE_HARD_STOP:-true}" != "true" ]]; then
        log_error "[self-fence] demote wedged ($why); SELF_FENCE_HARD_STOP!=true — NOT stopping the validator; the STAKED identity may STILL BE VOTING"
        alert "Demote set-identity wedged ($why); hard-stop disabled — the staked identity may still be voting. INTERVENE NOW (stop the validator)." "$STAKED_PUBKEY" "PRIMARY SELF-FENCE WEDGED — NO HARD STOP 🚨"
        return 1
    fi
    log_error "[self-fence] demote wedged ($why) — HARD-STOPPING the validator so the staked identity stops voting"
    local sc_out sc_rc pid_found="" pid masked="" mask_out mask_rc
    sc_out=$(timeout -k 5 15 systemctl stop "${VALIDATOR_SERVICE:-solana}" 2>&1); sc_rc=$?
    [[ -n "$sc_out" ]] && log_info "systemctl stop: $sc_out"
    _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
    # v0.6.9 (H2): systemctl stop did NOT cleanly succeed → the unit is still Restart=always, so a
    # direct SIGTERM/SIGKILL below would be undone by systemd after RestartSec (the validator resurrects
    # VOTING STAKED after the immediate verify passed). Mask the unit FIRST — --runtime so a reboot
    # clears the mask (fail toward recoverability). A failed mask never skips the kill (the delayed
    # re-verify below catches a resurrect either way). FAILURE DIRECTION: extra stopping power only —
    # masking can never keep a validator voting.
    if [[ $sc_rc -ne 0 ]]; then
        mask_out=$(timeout -k 5 15 systemctl mask --runtime "${VALIDATOR_SERVICE:-solana}" 2>&1); mask_rc=$?
        [[ -n "$mask_out" ]] && log_info "systemctl mask --runtime: $mask_out"
        _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
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
    # VERIFY (S4): only report success if the validator is provably down.
    if [[ -n "$pid" ]]; then
        log_error "[self-fence] HARD STOP FAILED — validator pid $pid still running after systemctl stop + SIGKILL; keeping the fence armed to retry"
        alert "Hard-stop FAILED ($why) — validator still running (pid $pid) after systemctl stop + SIGKILL; the staked identity may still vote. INTERVENE NOW." "$STAKED_PUBKEY" "PRIMARY SELF-FENCE — HARD STOP FAILED 🚨"
        return 1
    fi
    if [[ $sc_rc -ne 0 && -z "$pid_found" ]]; then
        log_error "[self-fence] HARD STOP UNCONFIRMED — systemctl stop failed (rc $sc_rc) and no known validator process found; cannot confirm voting stopped"
        alert "Hard-stop UNCONFIRMED ($why) — systemctl stop failed and no agave-validator/fdctl/solana-validator process found; cannot confirm the staked identity stopped voting. INTERVENE NOW." "$STAKED_PUBKEY" "PRIMARY SELF-FENCE — HARD STOP UNCONFIRMED 🚨"
        return 1
    fi
    # v0.6.9 (H2): RE-verify after a Restart=always-scale delay. The immediate check above races
    # systemd's RestartSec (typically 10s): a directly-killed process can pass the immediate check and
    # be resurrected VOTING STAKED seconds later. Wait >= RestartSec and re-run the down-check; a
    # process that came back = HARD STOP FAILED (never a false ✅). FAILURE DIRECTION: toward reporting
    # failure / paging — the extra wait only delays the success page, never the stop itself.
    _watchdog_sleep "${HARD_STOP_REVERIFY_SECS:-15}"   # v0.7 (Block 5.2): chunked under the armed unit — an env-raised re-verify window must not starve WatchdogSec (plain sleep otherwise)
    pid=$(_validator_pid)
    if [[ -n "$pid" ]]; then
        log_error "[self-fence] HARD STOP FAILED — validator RESURRECTED (pid $pid) within ${HARD_STOP_REVERIFY_SECS:-15}s (Restart=always); keeping the fence armed to retry"
        alert "Hard-stop FAILED ($why) — the validator was stopped but RESURRECTED (pid $pid, Restart=always) within ${HARD_STOP_REVERIFY_SECS:-15}s; it may be voting staked again. INTERVENE NOW (systemctl mask --runtime ${VALIDATOR_SERVICE:-solana}; then stop it)." "$STAKED_PUBKEY" "PRIMARY SELF-FENCE — HARD STOP FAILED 🚨"
        return 1
    fi
    # v0.6.9 (H2): the ✅ page names the mask state + the exact unmask command for recovery.
    if [[ -n "$masked" ]]; then
        alert "Demote set-identity wedged ($why); HARD-STOPPED the validator — confirmed DOWN (re-verified after ${HARD_STOP_REVERIFY_SECS:-15}s). Unit ${VALIDATOR_SERVICE:-solana} is MASKED (--runtime): recover with 'systemctl unmask --runtime ${VALIDATOR_SERVICE:-solana}' before restarting (scp tower, restart on the unstaked identity, confirm the spare took over)." "$STAKED_PUBKEY" "PRIMARY SELF-FENCE — HARD STOP ✅ (unit masked)"
    else
        alert "Demote set-identity wedged ($why); HARD-STOPPED the validator — confirmed DOWN (re-verified after ${HARD_STOP_REVERIFY_SECS:-15}s). Node is down; recover manually (scp tower, restart on the unstaked identity, confirm the spare took over)." "$STAKED_PUBKEY" "PRIMARY SELF-FENCE — HARD STOP ✅"
    fi
    return 0
}

switch_to_unstaked() {
    local reason="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would switch to UNSTAKED — $reason"
        alert "$reason" "$UNSTAKED_PUBKEY" "[DRY RUN] WOULD SWITCH TO UNSTAKED"; return 0
    fi

    [[ ! -s "$UNSTAKED_KEYPAIR" ]] && {
        log_error "Unstaked keypair missing/empty: $UNSTAKED_KEYPAIR"
        alert "$reason" "N/A" "SWITCH BLOCKED — keypair problem"; return 1
    }

    log_warn ">>> SWITCHING TO UNSTAKED — $reason"

    local _rc
    if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
        # v0.6.8 (B1): bound the admin-socket call; on a hang escalate to a hard stop (safe direction).
        timeout -k 5 "$SETIDENTITY_TIMEOUT" fdctl set-identity --config "$CONFIG_TOML" "$UNSTAKED_KEYPAIR" --force 2>&1 | while IFS= read -r l; do log_info "fdctl: $l"; done
        _rc=${PIPESTATUS[0]}
        _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1): bounded op completed — a TIMED-OUT op (rc 124/137) IS completed (`timeout` returned; the monitor is alive), so the pet fires BEFORE the wedge branch below — no-op outside the armed unit
        if [[ $_rc -eq 124 || $_rc -eq 137 ]]; then
            _selffence_hard_stop "fdctl set-identity to unstaked timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged"; return $?
        fi
    else
        local out
        # v0.6.8 (B1): bound remove-all; a hang here means the admin socket is wedged → escalate at once
        # (set-identity below would hang the same way).
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" authorized-voter remove-all 2>&1); _rc=$?
        _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1): bounded op completed — a TIMED-OUT op (rc 124/137) IS completed (`timeout` returned; the monitor is alive), so the pet fires BEFORE the wedge branch below — no-op outside the armed unit
        [[ -n "$out" ]] && log_info "remove-voter: $out"
        if [[ $_rc -eq 124 || $_rc -eq 137 ]]; then
            _selffence_hard_stop "authorized-voter remove-all timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged"; return $?
        fi

        local tower_file; tower_file=$(get_tower_path)
        [[ -f "$tower_file" ]] && { rm -f "$tower_file"; log_info "Removed tower: $tower_file"; }

        # v0.5.9: path-as-argument (official Anza failover API)
        # v0.6.8 (B1): bound set-identity; on a hang escalate to a hard stop so voting provably stops.
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$UNSTAKED_KEYPAIR" 2>&1); _rc=$?
        _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1): bounded op completed — a TIMED-OUT op (rc 124/137) IS completed (`timeout` returned; the monitor is alive), so the pet fires BEFORE the wedge branch below — no-op outside the armed unit
        [[ -n "$out" ]] && log_info "set-identity: $out"
        if [[ $_rc -eq 124 || $_rc -eq 137 ]]; then
            _selffence_hard_stop "set-identity to unstaked timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged"; return $?
        fi
    fi

    sleep 1    # v0.5.9: reduced from 2s
    CURRENT_IDENTITY=$(get_local_identity) || true
    if [[ "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" ]]; then
        LAST_SWITCH_TIME=$(mono_now); STAT_SWITCHES=$((STAT_SWITCHES + 1)); save_state   # v0.6.1 (F7)
        _recovery_confirm_count=0; _standby_alert_sent=""; _last_switch_fail_alert=0; window_reset
        reset_recovery_liveness; _selffence_reset   # v0.6.3 (Block 2/3): fresh trackers after the switch
        _last_blind_end=0   # v0.7 (B3 s4): fresh recovery episode — no observed blind cycle yet
        _liveness_obs_since=0; _ep_blind_cycles=0; _ep_provider_flips=0; _ep_floor_holds=0   # v0.7 (B3 s4 rework): observed span + episode diagnostics reset with the episode
        alert "$reason" "$UNSTAKED_PUBKEY" "SWITCHED TO UNSTAKED ✅"; return 0
    else
        # v0.6.0: throttle repeated failure alerts — the internet-lost path retries every cycle.
        local now_f; now_f=$(date +%s)
        if [[ $(( now_f - _last_switch_fail_alert )) -ge $ALERT_THROTTLE ]]; then
            alert "$reason" "${CURRENT_IDENTITY:-unknown}" "SWITCH TO UNSTAKED FAILED ❌"
            _last_switch_fail_alert=$now_f
        else
            log_error "Switch to UNSTAKED still failing (alert throttled) — identity=${CURRENT_IDENTITY:-unknown}"
        fi
        return 1
    fi
}

switch_to_staked() {
    local reason="$1"
    local now; now=$(mono_now)   # v0.7 (Block 3): SAFETY clock (RECOVERY_COOLDOWN gate)
    local elapsed=$(( now - LAST_SWITCH_TIME ))
    [[ $elapsed -lt $RECOVERY_COOLDOWN ]] && { log_info "Cooldown: $(( RECOVERY_COOLDOWN - elapsed ))s remaining"; return 1; }

    # v0.7 (Block 3, slice 5 / A8): FRESH-PROOF RE-CHECK — immediately after the cooldown gate,
    # before the keypair check and the DRY_RUN branch (same mirror rationale as the standby's
    # take_staked_identity: a DRY_RUN "WOULD RECOVER" that a live daemon would have aborted is a
    # false report). Condition (3) holds on this path too: the gossip advisory
    # (check_standby_has_identity) runs in attempt_safe_recovery BEFORE switch_to_staked, so after
    # a return-0 here nothing below touches the network before set-identity.
    _fresh_proof_recheck || return 1

    [[ ! -s "$STAKED_KEYPAIR" ]] && {
        log_error "Staked keypair missing/empty"
        alert "$reason" "N/A" "RECOVERY BLOCKED — keypair problem"; return 1
    }

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would recover to STAKED — $reason"
        alert "$reason" "$STAKED_PUBKEY" "[DRY RUN] WOULD RECOVER TO STAKED"; return 0
    fi

    log_info ">>> RECOVERING TO STAKED — $reason"

    if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
        # v0.6.8 (B1): bound the call but FAIL-SAFE — a hung PROMOTE must NOT escalate/kill; it simply
        # reads as a failed recovery below (the node stays on its current safe unstaked identity).
        timeout -k 5 "$SETIDENTITY_TIMEOUT" fdctl set-identity --config "$CONFIG_TOML" "$STAKED_KEYPAIR" --force 2>&1 | while IFS= read -r l; do log_info "fdctl: $l"; done
        [[ ${PIPESTATUS[0]} -eq 124 || ${PIPESTATUS[0]} -eq 137 ]] && log_warn "[recovery] fdctl set-identity to staked timed out (${SETIDENTITY_TIMEOUT}s) — promotion will read as failed (fail-safe: stays unstaked)"
        _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
    else
        local out
        # v0.6.0: NO --require-tower — split-brain safety is gossip-based and towers aren't
        # transferred between nodes, so a rebuilt tower is the safe path. --require-tower would
        # also block recovery (the tower was deleted going unstaked). Manual switchback scp's it first.
        # v0.6.8 (B1): bound but fail-safe (no escalation on the promote path).
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR" 2>&1); local _src=$?
        [[ -n "$out" ]] && log_info "set-identity: $out"
        [[ $_src -eq 124 || $_src -eq 137 ]] && log_warn "[recovery] set-identity to staked timed out (${SETIDENTITY_TIMEOUT}s) — promotion will read as failed (fail-safe: stays unstaked)"
        _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" authorized-voter add "$STAKED_KEYPAIR" 2>&1) || true
        [[ -n "$out" ]] && log_info "add-voter: $out"
        _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
    fi

    sleep 1    # v0.5.9: reduced from 2s
    CURRENT_IDENTITY=$(get_local_identity) || true
    if [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]]; then
        LAST_SWITCH_TIME=$(mono_now); STAT_SWITCHES=$((STAT_SWITCHES + 1)); save_state   # v0.6.1 (F7)
        _recovery_confirm_count=0; window_reset; reset_recovery_liveness; _selffence_reset   # v0.6.3 (Block 2/3)
        _last_blind_end=0   # v0.7 (B3 s4): recovery episode over — drop the blind anchor with it
        _liveness_obs_since=0; _ep_blind_cycles=0; _ep_provider_flips=0; _ep_floor_holds=0   # v0.7 (B3 s4 rework): observed span + episode diagnostics end with the episode
        alert "$reason" "$STAKED_PUBKEY" "RECOVERED TO STAKED ✅"; return 0
    else
        alert "$reason" "${CURRENT_IDENTITY:-unknown}" "RECOVERY FAILED ❌"; return 1
    fi
}

# ========================= PRIMARY SELF-FENCE (v0.6.3 Block 3) =================
# "Vote lease": while STAKED, the node must keep seeing the supermajority confirm its slots. If the
# LOCAL confirmed tip stops advancing, the node is isolated/partitioned and must DROP ITSELF to
# unstaked so it stops voting *during* the partition (before a heal turns it into a double-sign).
#
# HARD RULES (see TASK Block 3):
#   - Fires ONLY when CURRENT_IDENTITY == STAKED (the caller gates this).
#   - LOCAL signals ONLY. No external (T2/T3) RPC may ever trigger a self-fence.
#   - A LOCAL RPC that DOESN'T ANSWER is the existing "validator unreachable" pause path, NOT
#     isolation — only a *successful* getSlot(confirmed) that is NOT advancing counts.
#   - It may ONLY ever lead to switch_to_unstaked (the safe direction). Disable with PRIMARY_SELF_FENCE.
#   - Respects DRY_RUN (switch_to_unstaked logs "would switch", does not swap).
# Returns 0 if it self-fenced (caller should display + sleep + continue), 1 otherwise.

# Re-arm the self-fence tracker (after any switch / identity change / startup).
# v0.6.9 (H3): also drop any pending restart-continuity restore — after a switch/identity change the
# persisted pre-restart clocks are no longer about the CURRENT staked tenure (stale inheritance could
# fire a false demote on the next tenure).
_selffence_reset() { _last_confirmed_slot=""; _last_confirmed_advance_ts=$(mono_now); _selffence_noanswer_since=0; _selffence_votelag_since=0; _selffence_votelag_baseline=""; _selffence_votelag_healthy=0; _selffence_restore_pending=0; _selffence_noanswer_restore_pending=0; _selffence_votelag_restore_pending=0; _collision_strikes=0; _last_collision_check=0; }   # v0.6.7 (N6) + v0.6.8 (B2): re-arm the own-vote-lag tracker incl. the hysteresis counter; v0.6.9 (S-6): also clear the collision-detector flap streak per staked tenure

check_self_fence_isolation() {
    local now slot frozen health_result behind silent own_sample own_lv cluster_max vlag vlsust
    now=$(mono_now)   # v0.7 (Block 3): SAFETY clock — a backward wall step must not disarm the fence timers

    # (1) LOCAL confirmed-slot advancement — the authoritative isolation signal.
    slot=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot","params":[{"commitment":"confirmed"}]}' 2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null)
    _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit

    if [[ -z "$slot" || ! "$slot" =~ ^[0-9]+$ ]]; then
        # LOCAL RPC did not answer getSlot. A BRIEF gap is the existing "validator unreachable" pause
        # path, NOT isolation. But a CONTINUOUSLY silent LOCAL JSON-RPC while we still hold staked
        # (admin RPC up, so the main loop stays in the STAKED branch) is itself an isolation signal —
        # the node may be partitioned/wedged yet still voting, and STANDBY can confirm delinquency +
        # frozen liveness and take over → double-sign on heal. (v0.6.5 F1) Time the silence and demote
        # once it persists; LOCAL signal only; never on a fresh start (no baseline yet).
        if [[ "${SELF_FENCE_NOANSWER_SECS:-0}" =~ ^[0-9]+$ && $SELF_FENCE_NOANSWER_SECS -gt 0 && -n "$_last_confirmed_slot" ]]; then
            # v0.6.9 (H3): restart continuity — we were STAKED and already silent when the persisted
            # save was written, and the LOCAL RPC is STILL silent on this first post-restart check →
            # the silence is continuous; inherit the persisted silence clock (fence keeps its arming).
            # Positive evidence only (an answering RPC below drops the pending flag instead).
            if [[ ${_selffence_noanswer_restore_pending:-0} -eq 1 ]]; then
                _selffence_noanswer_restore_pending=0
                _selffence_noanswer_since=$_selffence_restored_noanswer_since
                log_warn "[self-fence] LOCAL RPC still silent across the monitor restart — no-answer timer backdated to the persisted start ($(( now - _selffence_noanswer_since ))s ago) (v0.6.9 H3)"
            fi
            [[ $_selffence_noanswer_since -eq 0 ]] && _selffence_noanswer_since=$now   # first silent cycle
            silent=$(( now - _selffence_noanswer_since ))
            if [[ $silent -ge $SELF_FENCE_NOANSWER_SECS ]]; then
                log_warn "[self-fence] LOCAL getSlot(confirmed) silent ${silent}s (>= ${SELF_FENCE_NOANSWER_SECS}s) while staked — isolated → switch to unstaked"
                # v0.6.6 (N2): do the safety action FIRST. The demote must never wait on notification
                # I/O — send_telegram + send_webhook are each curl -m 10 (up to ~20s combined if the
                # endpoints hang, exactly when the network is already in trouble), which would delay
                # the demote and shrink the cross-node margin (N1). switch_to_unstaked already pages on
                # success (SWITCHED TO UNSTAKED ✅) and failure (SWITCH TO UNSTAKED FAILED ❌) with the
                # reason, so no operator page is lost; the self-fence-specific page is emitted AFTER.
                # v0.6.8 (B1): N9-style retry discipline — re-arm (reset) ONLY after a confirmed demote
                # (incl. DRY_RUN's logged success, so DRY_RUN still does not re-fire); a FAILED demote keeps
                # the timer armed to retry next cycle instead of wiping the no-answer timer before the switch ran.
                if switch_to_unstaked "self-fence: LOCAL RPC silent ${silent}s while staked — isolated"; then
                    _selffence_reset
                    alert "LOCAL JSON-RPC silent ${silent}s while staked — node isolated; demoting to unstaked before a heal can double-sign" "$STAKED_PUBKEY" "PRIMARY SELF-FENCE — LOCAL RPC SILENT 🚨"
                else
                    log_warn "[self-fence] no-answer demote FAILED — keeping the timer armed to retry next cycle"
                fi
                return 0
            fi
            log_info "[self-fence] LOCAL getSlot(confirmed) no answer (${silent}s/${SELF_FENCE_NOANSWER_SECS}s) while staked — counting toward no-answer isolation"
            return 1
        fi
        # No-answer sub-check disabled (0/off) or no baseline yet (fresh start / catching up) → this is
        # the existing validator-unreachable pause path (the main loop handles it), NOT isolation.
        log_warn "[self-fence] LOCAL getSlot(confirmed) no answer — treating as validator-unreachable, NOT isolation"
        return 1
    fi
    # Got a numeric slot — a successful read clears the no-answer isolation timer (v0.6.5 F1).
    _selffence_noanswer_since=0
    _selffence_noanswer_restore_pending=0   # v0.6.9 (H3): the RPC answered → the persisted silence is NOT continuous; drop the pending backdate

    # v0.6.9 (H3): restart continuity for the frozen-slot signal. First successful read after a restore:
    # if the confirmed slot has NOT advanced past the persisted baseline, the stall is CONTINUOUS —
    # backdate the advance clock to the persisted value so the fence can fire immediately instead of
    # waiting a fresh SELF_FENCE_ISOLATION_SECS. A validator that resumed advancing clears instantly
    # (the pending flag is simply dropped; the normal advance path below re-baselines).
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
            log_warn "[self-fence] LOCAL confirmed slot frozen at $slot for ${frozen}s (>= ${SELF_FENCE_ISOLATION_SECS}s) — ISOLATED from supermajority → switch to unstaked"
            # v0.6.8 (B1): reset ONLY after a confirmed demote (N9 discipline); a failed demote retries.
            if switch_to_unstaked "self-fence: local confirmed slot frozen ${frozen}s — isolated from supermajority"; then
                _selffence_reset
            else
                log_warn "[self-fence] frozen-slot demote FAILED — keeping the timer armed to retry next cycle"
            fi
            return 0
        fi
        log_info "[self-fence] LOCAL confirmed slot not advancing (${frozen}s/${SELF_FENCE_ISOLATION_SECS}s) at $slot"
    fi

    # (2) Optional: LOCAL getHealth "behind by >N" — faster partial-partition detection. LOCAL only;
    # a non-answer is the unreachable path (ignored), never isolation.
    if [[ "${SELF_FENCE_MAX_BEHIND:-0}" =~ ^[0-9]+$ && $SELF_FENCE_MAX_BEHIND -gt 0 ]]; then
        health_result=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' 2>/dev/null)
        _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
        if [[ -n "$health_result" ]]; then
            behind=$(echo "$health_result" | jq -r '.error.data.numSlotsBehind // empty' 2>/dev/null)
            if [[ "$behind" =~ ^[0-9]+$ && $behind -gt $SELF_FENCE_MAX_BEHIND ]]; then
                log_warn "[self-fence] LOCAL getHealth behind by ${behind} slots (> ${SELF_FENCE_MAX_BEHIND}) — partial partition → switch to unstaked"
                # v0.6.8 (B1): reset ONLY after a confirmed demote (N9 discipline); a failed demote retries.
                if switch_to_unstaked "self-fence: local getHealth behind ${behind} slots (> ${SELF_FENCE_MAX_BEHIND}) — isolated from supermajority"; then
                    _selffence_reset
                else
                    log_warn "[self-fence] getHealth demote FAILED — keeping the timer armed to retry next cycle"
                fi
                return 0
            fi
        fi
    fi

    # (3) v0.6.7 (N6): OWN-VOTE-LAG — the "can I BE HEARD?" twin of (1)/(2). (1)/(2) only catch "can I
    #     HEAR the cluster?" (inbound). An EGRESS-ONLY partition leaves inbound flowing — $slot keeps
    #     advancing (so the frozen-slot check above never fires) and getHealth reads ~0-behind — while
    #     our OWN staked vote stops landing on-chain.
    #     v0.6.7 (N8): read our own lastVote AND the cluster-max lastVote from ONE LOCAL getVoteAccounts
    #     at commitment=processed (the same freshness pattern as get_staked_liveness_sample) and lag
    #     against the SAME-PAYLOAD cluster-max — "am I behind the other voters?" — so there is NO
    #     cross-call / cross-commitment skew. (The old code lagged a finalized own-vote against the
    #     confirmed $slot tip → a structural ~32-slot lag on a HEALTHY node → false demote.) LOCAL only —
    #     NEVER reads T2/T3 (the egress to them is exactly what's broken). Safe direction only.
    if [[ -n "$VOTE_PUBKEY" \
          && "${SELF_FENCE_VOTE_LAG_SLOTS:-0}" =~ ^[0-9]+$ && $SELF_FENCE_VOTE_LAG_SLOTS -gt 0 \
          && "${SELF_FENCE_VOTE_LAG_SECS:-0}" =~ ^[0-9]+$ && $SELF_FENCE_VOTE_LAG_SECS -gt 0 ]]; then
        own_sample=$(curl -s -m 5 "$LOCAL_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts","params":[{"commitment":"processed"}]}' 2>/dev/null)
        _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
        own_lv=$(echo "$own_sample" | jq -r --arg vote "$VOTE_PUBKEY" '(.result.current + .result.delinquent)[]? | select(.votePubkey == $vote) | .lastVote // empty' 2>/dev/null | head -1)
        # Cluster-wide freshness reference = MAX lastVote from the SAME payload (advances every slot).
        cluster_max=$(echo "$own_sample" | jq -r '[(.result.current + .result.delinquent)[]? | .lastVote] | map(numbers) | max // empty' 2>/dev/null)
        if [[ -n "$own_lv" && "$own_lv" =~ ^[0-9]+$ && -n "$cluster_max" && "$cluster_max" =~ ^[0-9]+$ ]]; then
            vlag=$(( cluster_max - own_lv )); [[ $vlag -lt 0 ]] && vlag=0
            # v0.6.9 (H3): restart continuity for N6 — on the first successful own-vote read after a
            # restore, a lag STILL over threshold (with the restored healthy baseline) is a continuous
            # episode → inherit the persisted sustain clock. A recovered lag simply drops the flag.
            if [[ ${_selffence_votelag_restore_pending:-0} -eq 1 ]]; then
                _selffence_votelag_restore_pending=0
                if [[ $vlag -gt $SELF_FENCE_VOTE_LAG_SLOTS && -n "$_selffence_votelag_baseline" ]]; then
                    _selffence_votelag_since=$_selffence_restored_votelag_since
                    log_warn "[self-fence] own-vote lag still over threshold (${vlag} slots) across the monitor restart — sustain timer backdated $(( now - _selffence_votelag_since ))s (v0.6.9 H3)"
                fi
            fi
            if [[ $vlag -le $SELF_FENCE_VOTE_LAG_SLOTS ]]; then
                # Voting normally (own tracks cluster-max) → establishes the healthy baseline.
                _selffence_votelag_baseline=1
                # v0.6.8 (B2): HYSTERESIS. A SINGLE sub-threshold cycle must NOT wipe an accumulating
                # sustain timer — a FLAPPING/intermittent egress that lands one vote burst per < SECS would
                # otherwise zero the timer every cycle and N6 would NEVER fire (the wedged-but-alive hole,
                # Audit-1 B2). Clear the timer only after SELF_FENCE_VOTE_LAG_RESET_CYCLES *consecutive*
                # healthy cycles, so the demote is "sustained-DOMINANT", not "sustained-contiguous".
                [[ $_selffence_votelag_healthy -lt $SELF_FENCE_VOTE_LAG_RESET_CYCLES ]] && _selffence_votelag_healthy=$(( _selffence_votelag_healthy + 1 ))
                [[ $_selffence_votelag_healthy -ge $SELF_FENCE_VOTE_LAG_RESET_CYCLES ]] && _selffence_votelag_since=0
            elif [[ -n "$_selffence_votelag_baseline" ]]; then
                # Over threshold AND we've seen a healthy baseline (not fresh-start/catch-up) → time it.
                _selffence_votelag_healthy=0   # v0.6.8 (B2): the healthy streak broke → restart the hysteresis count
                [[ $_selffence_votelag_since -eq 0 ]] && _selffence_votelag_since=$now
                vlsust=$(( now - _selffence_votelag_since ))
                if [[ $vlsust -ge $SELF_FENCE_VOTE_LAG_SECS ]]; then
                    log_warn "[self-fence] OWN vote lagging cluster-max by ${vlag} slots (> ${SELF_FENCE_VOTE_LAG_SLOTS}) for ${vlsust}s (>= ${SELF_FENCE_VOTE_LAG_SECS}s) while staked — votes not landing (egress isolation) → switch to unstaked"
                    # v0.6.6 (N2) ordering: safety action FIRST, alert AFTER (never wait on notifier I/O).
                    # v0.6.7 (N9): re-arm the tracker ONLY after a SUCCESSFUL demote (switch_to_unstaked
                    # returns 0, incl. DRY_RUN's logged success) — so DRY_RUN does not re-fire every cycle,
                    # AND a FAILED demote leaves the timer/baseline armed so the next cycle re-attempts
                    # (never one-and-done). switch_to_unstaked already re-arms via _selffence_reset on a
                    # real success and emits a throttled FAILED page, so failure needs no extra alert here.
                    if switch_to_unstaked "self-fence: own votes not landing (lag ${vlag} slots, ${vlsust}s) — egress isolation"; then
                        _selffence_reset
                        alert "OWN staked vote not landing — lagged cluster-max ${vlag} slots for ${vlsust}s while staked (egress-only isolation); demoting to unstaked before a heal can double-sign" "$STAKED_PUBKEY" "PRIMARY SELF-FENCE — VOTES NOT LANDING 🚨"
                    else
                        log_warn "[self-fence] vote-lag demote FAILED — still staked; keeping the timer armed to retry next cycle"
                    fi
                    return 0
                fi
                log_info "[self-fence] OWN vote lag ${vlag} slots (> ${SELF_FENCE_VOTE_LAG_SLOTS}) sustained ${vlsust}s/${SELF_FENCE_VOTE_LAG_SECS}s — counting toward egress-isolation self-fence"
            fi
            # else: over threshold but NO healthy baseline yet (fresh start / catching up) → do not arm.
        fi
        # own/cluster lastVote unreadable (account absent / brief LOCAL RPC blip) → cannot compute lag this
        # cycle; HOLD the timer as-is (a blip must not cancel a real growing lag, and cannot fire on its
        # own — the demote path requires a readable over-threshold lag). The unreachable path stays the loop's.
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
    _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
    if [[ -z "$own_ep" ]]; then
        log_info "[collision] cannot read our own gossip endpoint (LOCAL) — cannot compare this cycle (strikes held at ${_collision_strikes})"
        return 0
    fi

    # External vantages (T2 → T3): where does the cluster say the staked pubkey lives?
    local rpc cluster_info ext_ep mismatch_ep="" saw_self="" _cic_rc
    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        [[ -z "$rpc" ]] && continue
        cluster_info=$(curl -s -m 10 "$rpc" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null)
        _cic_rc=$?
        _watchdog_pet   # §5 per-op pet (Block 5.2/FF-B1 N-audit): bounded op completed (rc captured above) — post-op placement covers EVERY exit (mismatch break-out, parse-continue, final loop exit); no-op outside the armed unit
        [[ $_cic_rc -eq 0 ]] || continue
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
    # v0.7 (Block 5.4, reviewer GO condition): BOUNDED with the _rot_sysread idiom. Pre-Block-5
    # an unbounded read here was harmless (daemon hangs, Restart=always, nobody dies); under the
    # ARMED Type=notify unit it is the P1-capability trap from the other side — a wedged
    # systemctl HERE blocks startup pre-READY → TimeoutStartSec expires → `failed` → OnFailure →
    # the REAL fence fires on a HEALTHY validator. One doctrine, both call sites: the CLI is not
    # the enforcement plane and gets no clock — bounded, the empty-args path below already
    # handles the miss (explicit "set X in failover.env" refusals, not a hang). test_fence_rot
    # (19) pins the bound behaviorally; the (13) allowlist census pins the spelling.
    [[ -z "$args" ]] && args=$(timeout -k 2 5 systemctl show "${VALIDATOR_SERVICE:-solana}" -p ExecStart --value 2>/dev/null)
    _validator_args_cache="$args"
    printf '%s' "$args"
}

# Extract a flag value (handles "--flag val" and "--flag=val") from the validator argv.
_extract_arg() { sed -nE "s/.*$1[[:space:]=]+([^[:space:]]+).*/\1/p" <<<"$2" | head -1; }

detect_ledger_path() {
    [[ -n "$LEDGER_PATH" ]] && return
    LEDGER_PATH=$(_extract_arg '--ledger' "$(get_validator_args)")
    [[ -z "$LEDGER_PATH" ]] && { log_error "Cannot auto-detect ledger — set LEDGER_PATH in failover.env"; exit 1; }
    log_info "Ledger: $LEDGER_PATH (auto-detected)"
}

detect_tower_base() {
    # v0.6.1 (N2): honor an explicit TOWER_PATH override (was declared but ignored).
    if [[ -n "$TOWER_PATH" ]]; then
        _cached_tower_base="$TOWER_PATH"
        log_info "Tower base: $_cached_tower_base (TOWER_PATH override)"
        return
    fi
    local t; t=$(_extract_arg '--tower' "$(get_validator_args)")
    _cached_tower_base="${t:-$LEDGER_PATH}"
    log_info "Tower base: $_cached_tower_base"
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

# Validate the timing/threshold knobs not already covered by the window / vote-liveness / self-fence
# relationship checks. rpc-recovery knobs are only meaningful (and only validated) in rpc mode.
validate_numeric_config() {
    _validate_numeric CHECK_INTERVAL 1
    _validate_numeric TURBO_INTERVAL 1
    _validate_numeric CONNECTIVITY_TIMEOUT 1
    _validate_numeric CONNECTIVITY_RETRIES 1
    _validate_numeric MAX_VOTE_LATENCY 0
    _validate_numeric DELINQUENCY_RETRIES 1
    _validate_numeric RECOVERY_COOLDOWN 0
    _validate_numeric STARTUP_GRACE 0
    _validate_numeric HEARTBEAT_INTERVAL 1
    _validate_numeric HEARTBEAT_PING_INTERVAL 1
    _validate_numeric LOG_MAX_SIZE 1
    _validate_numeric HARD_STOP_REVERIFY_SECS 0                # v0.6.9 (H2): hard-stop re-verify delay (0 = immediate re-check only)
    _validate_numeric COLLISION_CHECK_INTERVAL 1               # v0.6.9 (M5): collision-detector cadence
    _validate_numeric STATE_MAX_AGE_SECS 0                     # v0.6.9 (H3): baseline-restore freshness gate (0 = never restore)
    _validate_numeric STARTUP_STAKED_UNREACHABLE_ALERT_SECS 1  # v0.6.9 (H3): startup staked-unreachable page threshold
    _validate_numeric ALPENGLOW_GATE_CHECK_HOURS 0             # v0.7 (pre-Block-4, №9): tripwire probe cadence in hours (0 = off, drift-announced)
    _validate_numeric FENCE_ROT_CHECK_SECS 10                  # v0.7 (Block 5.4): armed fence-rot sweep cadence (floor 10; drift-announced)
    _validate_numeric FENCE_ROT_GRACE 0                         # v0.7 (Block 5.4): numeric shape first; the REAL floor is dynamic, just below
    # v0.7 (Block 5.4): FENCE_ROT_GRACE floor = max(600, ALERT_THROTTLE) — two reasons, both
    # load-bearing: a human must be able to read a page before an armed+staked holder
    # self-demotes over a systemd typo, and at least one CRITICAL re-page must land INSIDE the
    # grace (a grace shorter than the throttle would page once, then act in silence).
    local _rot_floor=600
    if [[ "${ALERT_THROTTLE:-600}" =~ ^[0-9]+$ && $((10#${ALERT_THROTTLE:-600})) -gt $_rot_floor ]]; then _rot_floor=$((10#${ALERT_THROTTLE:-600})); fi
    if [[ $FENCE_ROT_GRACE -lt $_rot_floor ]]; then
        log_error "Bad FENCE_ROT_GRACE: require an integer >= ${_rot_floor} (= max(600, ALERT_THROTTLE=${ALERT_THROTTLE:-600})) (got ${FENCE_ROT_GRACE}) — a human must be able to read a page before an armed+staked holder self-demotes, and at least one CRITICAL re-page must land inside the grace"
        exit 1
    fi
    if [[ "$RECOVERY_MODE" == "rpc" ]]; then
        _validate_numeric RECOVERY_DELAY 0
        _validate_numeric RECOVERY_CHECKS 1
        _validate_numeric RECOVERY_CHECK_INTERVAL 0
        _validate_numeric VOTE_LIVENESS_MIN_SPAN 0             # v0.7 (B3 s4, ratified): episodic observation-span floor behind a FROZEN re-take (0 = disabled, drift-announced)
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
# value behaves as true = strict = silent); boolf = false-is-stricter (laxer ONLY when
# explicitly "true" — the runtime gates read ${KNOB:-false}, so empty/absent is strict/silent;
# v0.7 Block 5.2 №8). Numeric-safe: a non-numeric value is SKIPPED here
# (startup validation elsewhere owns rejection — this must never add a second failure mode), and
# compared via 10# so a leading-zero value can't read as octal.
# №8 note (Block 5.2 fix round): the boolf branch below is PARITY-KEPT DEAD CODE in this
# PRIMARY — the only boolf caller class (PREWARM_VOTER_ADD, №8) is STANDBY-only, and the
# primary's drift table never passes "boolf". It stays because the _drift_check body is
# byte-parity-asserted across daemons (test_config_drift f5): twin discipline over dead-code
# purity. (This comment sits OUTSIDE the f5 extraction anchors, so parity holds.)
_drift_check() {
    local name="$1" def="$2" dir="$3" why="$4" val="${!1}" lax=0
    if [[ "$dir" == "bool" ]]; then
        [[ -n "$val" && "$val" != "true" ]] && lax=1
    elif [[ "$dir" == "boolf" ]]; then
        # v0.7 (Block 5.2, №8): false-is-stricter twin of bool — laxer ONLY when explicitly
        # "true" (the runtime gates read ${KNOB:-false}, so empty/absent behaves as false =
        # strict = silent).
        [[ "$val" == "true" ]] && lax=1
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
    _drift_check FENCE_ROT_CHECK_SECS 60 low "fence rot on an armed holder is detected later — the sweep re-verifies the effective fence properties on this cadence (§2.1-rev2.1 №2)"
    _drift_check FENCE_ROT_GRACE 1800 low "an armed+staked holder with a verifiably broken fence keeps voting longer before the graceful self-demote — the spare's watchdog-elapsed soundness rests on this holder-side self-enforcement (§2.1)"
    # ── [config-drift] end shared table ──
    # ── [config-drift] role-specific safety knobs ──
    _drift_check RECOVERY_DELAY 300 high "rpc-mode recovery re-takes the staked identity sooner after going unstaked — less settle time before an automatic re-take"
}

# ========================= STARTUP ============================================

startup_checks() {
    echo "============================================="
    echo " Solana PRIMARY Failover v0.6.10 (3-TIER RPC)"
    echo "============================================="

    _consume_fence_markers    # v0.7 (Block 5.2 §2.2 → fix round HOLD-1): FIRST — before EVERY fatal startup gate, so a fenced node parks in HOLD instead of looping a fatal exit-1 through OnFailure → fence-breaker → restart (see the function header); same-boot fenced-stopped → HOLD; stale → warn + monitor; fenced-demoted → note + clear on first clean cycle; inert when no marker exists (every host today)

    if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
        command -v fdctl &>/dev/null || { log_error "fdctl not found"; exit 1; }
        [[ -z "$CONFIG_TOML" ]] && { log_error "CONFIG_TOML required"; exit 1; }
    else
        [[ -f "$SOLANA_PATH/agave-validator" ]] || { log_error "agave-validator not found"; exit 1; }
        [[ -f "$SOLANA_PATH/solana-keygen" ]] || { log_error "solana-keygen not found"; exit 1; }
        detect_ledger_path; detect_tower_base
    fi
    command -v jq &>/dev/null || { log_error "jq required"; exit 1; }

    STAKED_PUBKEY=$(validate_keypair_file "$STAKED_KEYPAIR" "Staked") || exit 1
    UNSTAKED_PUBKEY=$(validate_keypair_file "$UNSTAKED_KEYPAIR" "Unstaked") || exit 1
    [[ "$STAKED_PUBKEY" == "$UNSTAKED_PUBKEY" ]] && { log_error "FATAL: Same pubkey!"; exit 1; }

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

    [[ "$RECOVERY_MODE" == "rpc" && -z "$VOTE_PUBKEY" ]] && { log_error "RECOVERY_MODE=rpc needs VOTE_PUBKEY"; exit 1; }
    # v0.6.3 (Block 2): rpc recovery now has the vote-liveness fence (it re-takes only when nobody
    # is voting the staked identity), in addition to the v0.6.2 full ip:port gossip corroboration.
    # 'manual' (operator-driven switch-back) remains the recommended default — the keep-the-warning
    # follow-up — because automatic re-take is inherently riskier than a human deciding to switch back.
    [[ "$RECOVERY_MODE" == "rpc" ]] && log_warn "⚠️ RECOVERY_MODE=rpc: automatic re-take, fenced by vote-liveness + gossip corroboration — 'manual' is still the safer default"
    # Validate the vote-liveness knobs (octal-safe; same discipline as F6/C1) — only meaningful in
    # rpc mode, where a typo'd EPSILON/MIN_INTERVAL would weaken the recovery fence.
    if [[ "$RECOVERY_MODE" == "rpc" ]]; then
        [[ "$VOTE_LIVENESS_EPSILON" =~ ^[0-9]+$ && "$VOTE_LIVENESS_MIN_INTERVAL" =~ ^[0-9]+$ && $((10#$VOTE_LIVENESS_MIN_INTERVAL)) -ge 5 && $((10#$VOTE_LIVENESS_MIN_INTERVAL)) -gt $((10#$VOTE_LIVENESS_EPSILON)) ]] \
          || { log_error "Bad vote-liveness config: require EPSILON>=0, MIN_INTERVAL>=5 and MIN_INTERVAL>EPSILON (got eps=${VOTE_LIVENESS_EPSILON} interval=${VOTE_LIVENESS_MIN_INTERVAL})"; exit 1; }
        VOTE_LIVENESS_EPSILON=$((10#$VOTE_LIVENESS_EPSILON)); VOTE_LIVENESS_MIN_INTERVAL=$((10#$VOTE_LIVENESS_MIN_INTERVAL))
    fi
    # v0.6.8 (B1): the demote/promote admin-socket timeout is used by switch_to_unstaked/_staked even with
    # the self-fence off (connectivity-lost path), so validate it unconditionally. >= the read path's 8s.
    [[ "$SETIDENTITY_TIMEOUT" =~ ^[0-9]+$ && $((10#$SETIDENTITY_TIMEOUT)) -ge 8 ]] \
      || { log_error "Bad SETIDENTITY_TIMEOUT: require an integer >= 8 seconds (got ${SETIDENTITY_TIMEOUT})"; exit 1; }
    SETIDENTITY_TIMEOUT=$((10#$SETIDENTITY_TIMEOUT))

    # v0.6.3 (Block 3): validate the self-fence knobs (octal-safe; only when the self-fence is on).
    # ISOLATION_SECS must be a sane positive window; MAX_BEHIND may be 0 (getHealth demote off).
    if [[ "$PRIMARY_SELF_FENCE" == "true" ]]; then
        [[ "$SELF_FENCE_ISOLATION_SECS" =~ ^[0-9]+$ && $((10#$SELF_FENCE_ISOLATION_SECS)) -ge 5 ]] \
          || { log_error "Bad SELF_FENCE_ISOLATION_SECS: require an integer >= 5 (got ${SELF_FENCE_ISOLATION_SECS})"; exit 1; }
        [[ "$SELF_FENCE_MAX_BEHIND" =~ ^[0-9]+$ ]] \
          || { log_error "Bad SELF_FENCE_MAX_BEHIND: require an integer >= 0 (0 = off) (got ${SELF_FENCE_MAX_BEHIND})"; exit 1; }
        # v0.6.5 (F1): no-answer isolation timer; may be 0 (off).
        [[ "$SELF_FENCE_NOANSWER_SECS" =~ ^[0-9]+$ ]] \
          || { log_error "Bad SELF_FENCE_NOANSWER_SECS: require an integer >= 0 (0 = off) (got ${SELF_FENCE_NOANSWER_SECS})"; exit 1; }
        SELF_FENCE_ISOLATION_SECS=$((10#$SELF_FENCE_ISOLATION_SECS)); SELF_FENCE_MAX_BEHIND=$((10#$SELF_FENCE_MAX_BEHIND))
        SELF_FENCE_NOANSWER_SECS=$((10#$SELF_FENCE_NOANSWER_SECS))
        # v0.6.7 (N6): own-vote-lag self-fence knobs; either may be 0 (off).
        [[ "$SELF_FENCE_VOTE_LAG_SLOTS" =~ ^[0-9]+$ ]] \
          || { log_error "Bad SELF_FENCE_VOTE_LAG_SLOTS: require an integer >= 0 (0 = off) (got ${SELF_FENCE_VOTE_LAG_SLOTS})"; exit 1; }
        [[ "$SELF_FENCE_VOTE_LAG_SECS" =~ ^[0-9]+$ ]] \
          || { log_error "Bad SELF_FENCE_VOTE_LAG_SECS: require an integer >= 0 (0 = off) (got ${SELF_FENCE_VOTE_LAG_SECS})"; exit 1; }
        SELF_FENCE_VOTE_LAG_SLOTS=$((10#$SELF_FENCE_VOTE_LAG_SLOTS)); SELF_FENCE_VOTE_LAG_SECS=$((10#$SELF_FENCE_VOTE_LAG_SECS))
        # v0.6.8 (B2): the N6 flap hysteresis needs >= 2 consecutive healthy cycles (1/0 = no hysteresis).
        [[ "$SELF_FENCE_VOTE_LAG_RESET_CYCLES" =~ ^[0-9]+$ && $((10#$SELF_FENCE_VOTE_LAG_RESET_CYCLES)) -ge 2 ]] \
          || { log_error "Bad SELF_FENCE_VOTE_LAG_RESET_CYCLES: require an integer >= 2 (1/0 disable the flap hysteresis) (got ${SELF_FENCE_VOTE_LAG_RESET_CYCLES})"; exit 1; }
        SELF_FENCE_VOTE_LAG_RESET_CYCLES=$((10#$SELF_FENCE_VOTE_LAG_RESET_CYCLES))
        # v0.6.7 (N7): the N6 own-vote-lag self-fence reads our OWN vote account (VOTE_PUBKEY) lastVote. It
        # is gated on a non-empty VOTE_PUBKEY, but startup otherwise only requires VOTE_PUBKEY for
        # RECOVERY_MODE=rpc — so a DEFAULT (manual) config with VOTE_PUBKEY blank would boot with N6
        # SILENTLY OFF, leaving the egress-only hole open. Require it whenever N6 is armed (both knobs > 0),
        # in ANY recovery mode. Fatal — a missing safety input must not boot half-fenced.
        if [[ $SELF_FENCE_VOTE_LAG_SLOTS -gt 0 && $SELF_FENCE_VOTE_LAG_SECS -gt 0 && -z "$VOTE_PUBKEY" ]]; then
            log_error "VOTE_PUBKEY is required for the N6 egress-only self-fence (own-vote-lag) but is empty — set VOTE_PUBKEY, or disable N6 by setting SELF_FENCE_VOTE_LAG_SLOTS=0 (or SELF_FENCE_VOTE_LAG_SECS=0)"
            exit 1
        fi
    fi
    # v0.6.1 (F4): RECOVERY_MODE=auto is a live double-sign path (PRIMARY re-takes staked
    # when LOCAL shows "not delinquent" — but the STANDBY is what keeps it non-delinquent).
    # Reserved for a future release; the code branch in the main loop is kept but disabled here.
    [[ "$RECOVERY_MODE" == "auto" ]] && { log_error "RECOVERY_MODE=auto is reserved for a future release — use manual or rpc"; exit 1; }

    # v0.6.1 (F6): validate sliding-window bounds. THRESHOLD>SIZE makes window_triggered
    # never fire (failover silently disabled); SIZE=0 would trigger on an empty window.
    # Single-line [[ ]] (bash 3.2 rejects backslash continuation inside the brackets); the
    # comparisons use $((10#…)) so a leading-zero value isn't parsed as octal (bash 3.2
    # would throw "value too great for base" on e.g. 08). Regex guards non-numeric first.
    [[ "$DELINQUENCY_WINDOW_SIZE" =~ ^[0-9]+$ && "$DELINQUENCY_WINDOW_THRESHOLD" =~ ^[0-9]+$ && $((10#$DELINQUENCY_WINDOW_THRESHOLD)) -ge 1 && $((10#$DELINQUENCY_WINDOW_SIZE)) -ge $((10#$DELINQUENCY_WINDOW_THRESHOLD)) ]] \
      || { log_error "Bad window config: require 1<=THRESHOLD<=SIZE (got ${DELINQUENCY_WINDOW_THRESHOLD}/${DELINQUENCY_WINDOW_SIZE})"; exit 1; }
    # Normalize to base-10 so later window arithmetic never misreads a leading-zero value.
    DELINQUENCY_WINDOW_SIZE=$((10#$DELINQUENCY_WINDOW_SIZE)); DELINQUENCY_WINDOW_THRESHOLD=$((10#$DELINQUENCY_WINDOW_THRESHOLD))

    validate_numeric_config   # v0.6.5 (F4): reject/normalize all remaining numeric knobs

    announce_config_drift     # v0.7 (Block 3, slice 3.5): env safety knobs laxer than THIS version's defaults — one line each (visibility, never force)

    _enforce_one_arm_state    # v0.7 (Block 5 skeleton, №1): refuse DRY_RUN=true + REAL fence unit — CRITICAL + exit 1; structurally inert while no fence unit exists (every host today). Runs AFTER marker consumption (fix round HOLD-1): on a fenced node this refusal must not preempt HOLD.
    _rot_capture_intent       # v0.7 (Block 5.4): fence-intent anchor for the rot sweep — armed-unit only (structurally inert on every host today); captured HERE, at startup, so runtime real→none / real→page-only is classifiable as "the fence is GONE" (a first-sweep capture would bless an early deletion as intent)
    _proof_startup_check      # v0.7 (Block 6.1, §2.7 [6.0-COND-4]): the LOUD unpaired/bypass state — CRITICAL page at EVERY armed-spare start (no/invalid/page-only pairing token, and the ALLOW_UNFENCED_TAKEOVER every-start scream); armed+spare only — a no-op on this HOLDER daemon (_proof_role_is_spare returns 1) and on every un-armed host

    # v0.6.9 (M8): TIER2/TIER3 vantage-independence. Identical URLs silently void every "two vantages"
    # assumption (A6, the liveness fence's fallback independence, the tiered confirmations). Warn loudly
    # — NOT fatal (existing single-provider users keep working, loudly). FAILURE DIRECTION: warn-only.
    if [[ -n "$TIER2_RPC" && -n "$TIER3_RPC" && "$(_norm_rpc_url "$TIER2_RPC")" == "$(_norm_rpc_url "$TIER3_RPC")" ]]; then
        log_warn "⚠️ TIER2_RPC == TIER3_RPC — single vantage point: every 'two independent vantages' assumption (tiered confirmation independence) is void. Use two DISTINCT providers."
        alert_warn "⚠️ TIER2_RPC == TIER3_RPC — single vantage point. The tiered confirmations are no longer independent; configure two distinct RPC providers."
    fi

    load_state   # v0.6.1 (F7): restore persisted cooldown timers (if any); v0.6.9 (H3/M10): + self-fence baseline / legacy-state migration

    # Test tiers
    log_info "Testing RPC tiers..."
    local slot
    slot=$(curl -s -m 5 "$LOCAL_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [[ -n "$slot" ]] && log_info "Tier 1 (LOCAL): OK (slot $slot)" || log_warn "Tier 1 (LOCAL): not ready yet"

    slot=$(curl -s -m 10 "$TIER2_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [[ -n "$slot" ]] && log_info "Tier 2 (ALCHEMY): OK (slot $slot)" || log_warn "Tier 2 (ALCHEMY): unreachable"

    slot=$(curl -s -m 10 "$TIER3_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [[ -n "$slot" ]] && log_info "Tier 3 (PUBLIC): OK (slot $slot)" || log_warn "Tier 3 (PUBLIC): unreachable"

    # Wait for validator
    log_info "Waiting for local validator..."
    CURRENT_IDENTITY=""
    local wc=0 _wait_start _wait_alerted=0 _wait_start_mono _wait_last_repage _wait_now_mono
    _wait_start=$(date +%s)   # v0.6.9 (H3)
    _wait_start_mono=$(mono_now); _wait_last_repage=$_wait_start_mono   # v0.7 (Block 5.2 fix round, FF-4): armed-only re-page cadence — mono clock (the HOLD re-page idiom; no new wall-clock site)
    while [[ -z "$CURRENT_IDENTITY" && "$_running" == "true" ]]; do
        heartbeat_ping   # v0.6.9 (H3): the dead-man's switch must not go dark while we wait here
        CURRENT_IDENTITY=$(get_local_identity 2>/dev/null) || true
        if [[ -z "$CURRENT_IDENTITY" ]]; then
            wc=$((wc+1)); [[ $((wc%10)) -eq 0 ]] && log_warn "Still waiting... ($wc)"
            # v0.6.9 (H3): the persisted state says we were STAKED and the validator has been
            # unreachable since monitor startup — the daemon cannot self-demote an unreachable
            # validator, and a spare may confirm delinquency and take over → page URGENT, once.
            # FAILURE DIRECTION: toward paging the operator (holder path); a false page costs one 🚨.
            if [[ $_wait_alerted -eq 0 && "$_persisted_role" == "staked" \
                  && $(( $(date +%s) - _wait_start )) -ge $STARTUP_STAKED_UNREACHABLE_ALERT_SECS ]]; then
                # v0.7 (Block 5.2 fix round, FF-1): the alert below is a bounded op (Telegram
                # -m 10 + webhook -m 10 = 20 s) — re-send EXTEND immediately BEFORE and AFTER
                # it (extend-after-bounded-op, mirroring per-op pets) so the alert term cannot
                # stretch an EXTEND→EXTEND gap past the 60 s deadline even when the alert
                # iteration immediately follows an evidence-flap iteration (the 72 s panel
                # trace; full arithmetic at _watchdog_extend_startup). Both sends stay
                # evidence-gated; no-ops outside the armed unit.
                _watchdog_extend_if_starting 2>/dev/null
                log_warn "Persisted role STAKED + local validator unreachable ${STARTUP_STAKED_UNREACHABLE_ALERT_SECS}s+ at startup — sending URGENT alert"
                alert "PRIMARY was STAKED at last save + local validator unreachable since monitor startup (>${STARTUP_STAKED_UNREACHABLE_ALERT_SECS}s) — the daemon cannot self-demote; STANDBY may take over. Intervene (stop the validator or confirm the spare took over)." "$STAKED_PUBKEY" "PRIMARY UNREACHABLE WHILE STAKED 🚨"
                _wait_alerted=1
                _watchdog_extend_if_starting 2>/dev/null
            fi
            # v0.7 (Block 5.2 fix round, FF-4): under the ARMED unit an honest
            # eternal-"starting" wait extends indefinitely with only the one-shot H3 page
            # above, while protection is dark (pre-READY; the external heartbeat stays
            # green). Re-page through ALERT_THROTTLE while the wait persists — loud, no
            # behavior change. Armed-only: un-armed hosts keep the v0.6.9 behavior (log
            # lines only) — structural inertness. Placed immediately BEFORE the
            # per-iteration extension gate so an extension lands right after this bounded
            # page (extend-after-bounded-op again).
            if _watchdog_active 2>/dev/null; then   # 2>/dev/null: the P-e bare seam sources this region without the helper — command-not-found must stay silent there (the _watchdog_extend_if_starting idiom)
                _wait_now_mono=$(mono_now)
                if [[ $(( _wait_now_mono - _wait_last_repage )) -ge ${ALERT_THROTTLE:-600} ]]; then
                    _wait_last_repage=$_wait_now_mono
                    alert_warn "⚠️ validator still in startup after $(( _wait_now_mono - _wait_start_mono ))s — monitor pre-READY: failover protection NOT yet active (start extending honestly while startup evidence holds)"
                fi
            fi
            # v0.7 (Block 5.2, B1/§2.2): pre-READY LIVE EXTENSION — replaces any static start-
            # timeout guess (the reboot brick: a replay longer than a guess fences a healthy
            # validator mid-replay). Extend ONLY on POSITIVE evidence that the validator is up
            # and in startup/replay: process alive (_validator_pid) AND the admin socket
            # answering start-progress (_startup_phase_evidence — the FENCE's own probe, twin
            # copy, so daemon and fence share ONE evidence definition). A wedged/GONE validator
            # sends NOTHING → PID 1 times the start out → `failed` → OnFailure → the fence's
            # §2.2 third branch handles it. That is the design, not an oversight.
            #
            # [Block 5.2 part D — the third-branch dispatch loop, ANALYZED] The fence's third
            # branch (identity unreadable + startup evidence) restarts this monitor and exits
            # 0; a wedged-identity node could loop fence→monitor→fence, unbounded in COUNT. The
            # damper is THIS gate, because both ends read the SAME probe (byte-identical twin):
            #   (a) evidence HOLDS steadily (genuine startup/replay): every iteration extends →
            #       the start never times out → NO further fence dispatch at all — the loop's
            #       dispatch count stops at the dispatch that started us.
            #   (b) evidence ABSENT steadily (wedged/gone validator — the part-D scenario): we
            #       stop extending → the start times out within one extension deadline (≤ 60 s
            #       after the LAST EXTEND sent; when NO extend was ever sent this start, the
            #       bound is the unit's TimeoutStartSec instead — pinned 90 s in the monitor
            #       skel, = the systemd default)
            #       → `failed` → OnFailure → the fence probes the SAME evidence, finds none →
            #       its STOP path (fenced-stopped → the next start parks in HOLD). TERMINATES
            #       on the second dispatch — driven as a two-dispatch test case.
            #   (c) evidence FLAPPING across dispatches: each loop iteration costs a full
            #       no-evidence extension deadline (≥ 60 s) plus a fence pass, and pages on
            #       both ends — RATE-BOUNDED and LOUD, never stops the validator by itself,
            #       and settles into (a) or (b) the moment the flap does. Deliberately NO
            #       counter for (c): a counter that force-stops on a flap would stop a
            #       validator on AMBIGUOUS evidence — the wrong direction. Named residual.
            # 2>/dev/null on the call: an older seam (test_baseline_persistence P-e) sources
            # this region bare, where the helper is undefined — command-not-found must stay
            # silent there (the helper's real output goes through log_*, never stderr).
            _watchdog_extend_if_starting 2>/dev/null
            sleep 5
        fi
    done
    [[ "$_running" != "true" ]] && exit 0

    _watchdog_ready   # v0.7 (Block 5.2, B1/§2.2): READY=1 strictly after the FIRST successful identity read — pre-READY the watchdog stays unarmed; no-op outside the unit

    echo ""
    echo "  Node:              $NODE_NAME"
    echo "  Staked:            $STAKED_PUBKEY"
    echo "  Unstaked:          $UNSTAKED_PUBKEY"
    echo "  Current:           $CURRENT_IDENTITY"
    echo "  ─── Three-Tier RPC ───"
    echo "  Tier 1 (LOCAL):    $LOCAL_RPC (every ${CHECK_INTERVAL}s / turbo: ${TURBO_INTERVAL}s)"
    echo "  Tier 2 (ALCHEMY):  ${TIER2_RPC:0:55}..."
    echo "  Tier 3 (PUBLIC):   $TIER3_RPC"
    echo "  ─── Thresholds ───"
    echo "  Delinq window:     ${DELINQUENCY_WINDOW_THRESHOLD}/${DELINQUENCY_WINDOW_SIZE} (trigger/window)"
    echo "  Vote latency:      $([ "$MAX_VOTE_LATENCY" -gt 0 ] && echo "${MAX_VOTE_LATENCY} slots" || echo "off")"
    echo "  Inet retries:      $CONNECTIVITY_RETRIES"
    echo "  Recovery:          $RECOVERY_MODE"
    if [[ "$PRIMARY_SELF_FENCE" == "true" ]]; then
        # v0.6.9 (H1): banner also shows the N6 vote-lag arming + the hard-stop state, mirrored on the standby.
        echo "  Self-fence:        on (isolation ${SELF_FENCE_ISOLATION_SECS}s; no-answer $([ "$SELF_FENCE_NOANSWER_SECS" -gt 0 ] && echo "${SELF_FENCE_NOANSWER_SECS}s" || echo "off"); vote-lag $([ "$SELF_FENCE_VOTE_LAG_SLOTS" -gt 0 ] && [ "$SELF_FENCE_VOTE_LAG_SECS" -gt 0 ] && echo "${SELF_FENCE_VOTE_LAG_SLOTS}sl/${SELF_FENCE_VOTE_LAG_SECS}s" || echo "off"); getHealth behind > $([ "$SELF_FENCE_MAX_BEHIND" -gt 0 ] && echo "${SELF_FENCE_MAX_BEHIND}" || echo "off"); hard-stop ${SELF_FENCE_HARD_STOP})"
    else
        echo "  Self-fence:        off"
    fi
    echo "  DRY RUN:           $DRY_RUN"
    echo ""
    [[ "$DRY_RUN" == "true" ]] && echo "  ⚠️  DRY RUN — no switches" && echo ""
    echo "============================================="

    log_info "Started. Identity: $CURRENT_IDENTITY"
    if [[ "$DRY_RUN" == "true" ]]; then
        alert_info "🚀 PRIMARY v0.6.9 started [DRY_RUN]. <code>${CURRENT_IDENTITY:0:8}...</code> | Mode: $RECOVERY_MODE"
    else
        log_warn "⚠️  ⚠️  ⚠️  LIVE MODE — failover will perform real identity switches  ⚠️  ⚠️  ⚠️"
        alert_info "🚀 PRIMARY v0.6.9 started [LIVE]. <code>${CURRENT_IDENTITY:0:8}...</code> | Mode: $RECOVERY_MODE"
    fi
    [[ $STARTUP_GRACE -gt 0 ]] && { log_info "Grace: ${STARTUP_GRACE}s"; _watchdog_sleep "$STARTUP_GRACE"; }   # v0.7 (Block 5.2): grace chunked under the armed unit (plain sleep otherwise)
}

display_status() {
    [[ ! -t 1 ]] && return
    local l; [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] && l="STAKED" || l="UNSTAKED"
    printf "\r[%s] %s | Chk:%d Sw:%d T2:%d FP:%d | %s   " \
        "$l" "${CURRENT_IDENTITY:0:8}..." "$STAT_CHECKS" "$STAT_SWITCHES" \
        "$STAT_TIER2_CHECKS" "$STAT_FALSE_POSITIVES" "$1"
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
    _fence_rot_check   # v0.7 (Block 5.4, §2.1-rev2.1 №2): armed holder-side fence re-verification — self-gates on _watchdog_active + cadence; bounded property reads + paging only, EXCEPT the grace-expiry graceful demote, which reuses the existing demote path (safety action first — act-then-alert holds inside it)
    _g2_step   # v0.7 (Block 6.2): the verified-demote (G2) per-cycle state-machine advance — a permanent no-op on this HOLDER daemon (_proof_role_is_spare returns 1, and _g2_incident_active never answers active); kept at the loop-top surface so the call sites stay symmetric with the standby (the _proof_status_line precedent)

    CURRENT_IDENTITY=$(get_local_identity 2>/dev/null) || true
    _watchdog_pet   # §5 per-op pet (Block 5.2): bounded op completed — no-op outside the armed unit
    if [[ -z "$CURRENT_IDENTITY" ]]; then
        now_ts=$(date +%s)
        if [[ $(( now_ts - _last_unreachable_alert )) -ge $ALERT_THROTTLE ]]; then
            # v0.6.5 (F1 sub-item): if the last-known identity was STAKED, the validator is fully
            # wedged (admin RPC down too) so the self-fence demote can't run — STANDBY may confirm
            # delinquency + frozen liveness and take over → double-sign on heal. Page URGENT, not warn.
            if [[ "$_last_known_identity" == "$STAKED_PUBKEY" ]]; then
                log_warn "Local validator unreachable while STAKED — sending URGENT alert"
                alert "PRIMARY staked + local validator unreachable — the daemon cannot self-demote; STANDBY may take over. Intervene (stop the validator or confirm STANDBY)." "$STAKED_PUBKEY" "PRIMARY UNREACHABLE WHILE STAKED 🚨"
            else
                log_warn "Local validator unreachable — sending alert"
                alert_warn "⚠️ PRIMARY local validator unreachable! Failover monitoring paused."
            fi
            _last_unreachable_alert=$now_ts
        else
            log_warn "Local validator unreachable"
        fi
        display_status "N/A"
        _watchdog_pet   # §5 end-of-cycle pet (Block 5.2): the cycle's last op returned — no-op outside the armed unit
        _watchdog_sleep "$CHECK_INTERVAL"   # FF-B3 (fix round): chunked under the armed unit — ANY legal interval is safe (plain sleep un-armed)
        continue
    fi
    _last_unreachable_alert=0

    # v0.7 (Block 5.2, §2.2): the FIRST CLEAN CYCLE (identity readable again) clears the
    # fence's fenced-demoted marker — this hunk owns only the marker's LIFECYCLE; the
    # demoted-holder monitoring itself is the existing branch logic below, unchanged.
    if [[ ${_fence_demoted_pending:-0} -eq 1 ]]; then
        rm -f "$FENCE_MARKER_DIR/fenced-demoted" 2>/dev/null
        _fence_demoted_pending=0
        log_info "[fence-marker] fenced-demoted cleared on the first clean cycle (§2.2 contract)"
    fi

    # ---- Detect manual identity changes (not by this script) ----
    if [[ -n "$_last_known_identity" && "$CURRENT_IDENTITY" != "$_last_known_identity" ]]; then
        # Identity changed since last check — was it us?
        now_manual=$(mono_now)   # v0.7 (Block 3): compared against LAST_SWITCH_TIME (a mono stamp) — a wall step must not mis-attribute a switch
        if [[ $(( now_manual - LAST_SWITCH_TIME )) -gt 10 ]]; then
            # Not our switch (too long ago) → someone did it manually
            log_warn "⚠️ Identity changed externally: ${_last_known_identity:0:8}→${CURRENT_IDENTITY:0:8} — resetting + grace"
            # v0.6.1 (B8): in manual recovery mode switch_to_staked never runs, so this detector
            # is the ONLY signal of an operator returning PRIMARY to staked. Make that explicit.
            if [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]]; then
                alert_info "✅ PRIMARY back on STAKED (manual): ${_last_known_identity:0:12}→${CURRENT_IDENTITY:0:12}. Grace ${STARTUP_GRACE}s."
            else
                alert_info "ℹ️ Manual identity change detected: ${_last_known_identity:0:12}→${CURRENT_IDENTITY:0:12}. Grace ${STARTUP_GRACE}s."
            fi
            window_reset
            reset_recovery_liveness; _selffence_reset   # v0.6.3 (Block 2/3): re-arm trackers after a manual change
            _last_blind_end=0   # v0.7 (B3 s4): manual change = new episode — drop the blind anchor
            _liveness_obs_since=0; _ep_blind_cycles=0; _ep_provider_flips=0; _ep_floor_holds=0   # v0.7 (B3 s4 rework): observed span + episode diagnostics reset with the episode
            CONNECTIVITY_FAIL_COUNT=0
            LATENCY_FAIL_COUNT=0
            # Grace period — validator needs time to catch up and start voting
            log_info "Manual switch grace: ${STARTUP_GRACE}s (letting validator catch up)"
            _watchdog_sleep "$STARTUP_GRACE"   # v0.7 (Block 5.2): chunked under the armed unit (plain sleep otherwise)
        fi
    fi
    _last_known_identity="$CURRENT_IDENTITY"

    # Recovery from an UNKNOWN-identity episode (paged below): announce once, re-arm the episode.
    if [[ $_unknown_identity_since -gt 0 && ( "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" || "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ) ]]; then
        alert_info "✅ Identity classified again after $(( $(date +%s) - _unknown_identity_since ))s UNKNOWN — protection active"
        _unknown_identity_since=0; _last_unknown_alert=0
    fi

    # ---- Internet check → immediate switch if down ----
    if ! check_internet; then
        CONNECTIVITY_FAIL_COUNT=$((CONNECTIVITY_FAIL_COUNT + 1))
        STAT_INET_FAILURES=$((STAT_INET_FAILURES + 1))
        log_warn "Internet FAILED ($CONNECTIVITY_FAIL_COUNT/$CONNECTIVITY_RETRIES)"

        if [[ $CONNECTIVITY_FAIL_COUNT -ge $CONNECTIVITY_RETRIES && "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]]; then
            switch_to_unstaked "Internet lost (${CONNECTIVITY_FAIL_COUNT}x) — no tier verification needed" || true
        fi
        display_status "NO INET"
        _watchdog_pet   # §5 end-of-cycle pet (Block 5.2): the cycle's last op returned — no-op outside the armed unit
        _watchdog_sleep "$CHECK_INTERVAL"; continue   # FF-B3 (fix round): chunked under the armed unit (plain sleep un-armed)
    fi

    [[ $CONNECTIVITY_FAIL_COUNT -gt 0 ]] && { alert_info "✅ PRIMARY internet recovered after $CONNECTIVITY_FAIL_COUNT fail(s)"; flush_pending_alerts; }
    CONNECTIVITY_FAIL_COUNT=0

    # ---- STAKED or UNSTAKED? ----
    latency_str="OK"

    if [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]]; then
        # ======== STAKED: Tier 1 local monitoring ========

        # v0.6.3 (Block 3): PRIMARY self-fence — isolation from the supermajority (LOCAL confirmed
        # slot frozen) drops us to unstaked BEFORE a partition heal can double-sign. LOCAL signals
        # only; checked first so isolation is acted on promptly. On fire it switches to unstaked and
        # the loop continues (next cycle takes the UNSTAKED branch), so it never double-fires with
        # the delinquency check below in the same cycle.
        if [[ "$PRIMARY_SELF_FENCE" == "true" ]]; then
            if check_self_fence_isolation; then
                display_status "SELF-FENCED"
                _watchdog_pet   # §5 end-of-cycle pet (Block 5.2): the cycle's last op returned — no-op outside the armed unit
                _watchdog_sleep "$_current_interval"; continue   # FF-B3 (fix round): chunked under the armed unit (plain sleep un-armed)
            fi
        fi

        # v0.6.9 (M5): collision detector — DETECTION-ONLY page when gossip shows the staked pubkey at a
        # non-self endpoint while we hold it (two-holder state nothing else can see). Never demotes;
        # self-throttled to COLLISION_CHECK_INTERVAL.
        check_identity_collision || true

        # Vote latency (Tier 1, optional)
        if [[ $MAX_VOTE_LATENCY -gt 0 ]]; then
            vote_latency=$(tier1_get_vote_latency) || true
            if [[ "${vote_latency:-}" == "-1" || -z "${vote_latency:-}" ]]; then
                latency_str="ERR"
            else
                latency_str="${vote_latency}sl"
                if [[ $vote_latency -gt $MAX_VOTE_LATENCY ]]; then
                    LATENCY_FAIL_COUNT=$((LATENCY_FAIL_COUNT + 1))
                    log_warn "Latency $vote_latency > $MAX_VOTE_LATENCY ($LATENCY_FAIL_COUNT/$DELINQUENCY_RETRIES)"
                    if [[ $LATENCY_FAIL_COUNT -ge $DELINQUENCY_RETRIES ]]; then
                        # === ESCALATE to Tier 2/3 ===
                        if verify_latency_tiered "$vote_latency"; then
                            switch_to_unstaked "Latency ${vote_latency}sl > ${MAX_VOTE_LATENCY}sl (3-tier confirmed)" || true
                        fi
                        LATENCY_FAIL_COUNT=0
                        display_status "$latency_str"
                        _watchdog_pet   # §5 end-of-cycle pet (Block 5.2): the cycle's last op returned — no-op outside the armed unit
                        _watchdog_sleep "$_current_interval"; continue   # FF-B3 (fix round): chunked under the armed unit (plain sleep un-armed)
                    fi
                else
                    LATENCY_FAIL_COUNT=0
                fi
            fi
        fi

        # Delinquency (Tier 1, fast + sliding window)
        if tier1_check_delinquency; then
            window_push 1

            # >>> OPT#1: Enter turbo mode on first delinquent
            if [[ "$_turbo_mode" != "true" ]]; then
                _turbo_mode=true
                _current_interval=$TURBO_INTERVAL
                log_info "⚡ TURBO MODE: check interval ${CHECK_INTERVAL}s → ${TURBO_INTERVAL}s"
            fi

            w_count=$(window_count)
            w_total=${#_delinq_window}
            log_warn "Tier 1: DELINQUENT (window: ${w_count}/${w_total}, trigger: ${DELINQUENCY_WINDOW_THRESHOLD}/${DELINQUENCY_WINDOW_SIZE})"
            latency_str="DELINQ"

            if window_triggered; then
                # === ESCALATE to Tier 2/3 ===
                if verify_delinquency_tiered; then
                    switch_to_unstaked "Delinquent — 3-tier confirmed (window: ${w_count}/${DELINQUENCY_WINDOW_SIZE})" || true
                fi
                window_reset
            fi
        else
            window_push 0
            # v0.6.9 (Phase A): per-cycle health line mirroring the STANDBY's log, so both daemons' logs
            # look the same. Reuses the confirmed slot the self-fence check ALREADY read this cycle
            # (line ~1334) — no extra RPC. Only logs on the healthy staked path.
            log_info "[TIER1] Health OK — slot ${_last_confirmed_slot:-unknown}"
            # Exit turbo when window is mostly clear
            if [[ "$_turbo_mode" == "true" ]] && window_mostly_clear; then
                _turbo_mode=false
                _current_interval=$CHECK_INTERVAL
                log_info "⚡ TURBO OFF: check interval → ${CHECK_INTERVAL}s"
            fi
        fi

    elif [[ "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" ]]; then
        # ======== UNSTAKED: recovery ========
        latency_str="UNSTK"
        if [[ "$RECOVERY_MODE" == "manual" ]]; then
            if [[ $(( $(date +%s) - _last_recovery_log )) -ge 60 ]]; then
                log_info "UNSTAKED. manual mode — waiting"; _last_recovery_log=$(date +%s)
            fi
        elif [[ "$RECOVERY_MODE" == "auto" ]]; then
            # v0.6.1 (F4): kept for a future release but unreachable — startup_checks rejects
            # RECOVERY_MODE=auto. Do NOT enable without the v0.6.2 vote-liveness gate.
            tier1_check_delinquency || switch_to_staked "Auto-recovery (local not delinquent)" || true
        elif [[ "$RECOVERY_MODE" == "rpc" ]]; then
            attempt_safe_recovery
        fi

    else
        # An identity that is neither the STAKED key nor this node's configured UNSTAKED key means we
        # do not understand this node's state. The binary dispatch used to classify this as UNSTAKED,
        # which is the DANGEROUS direction on the primary: (a) if the env/keypair drifted while the
        # validator actually holds the real staked key, the self-fence (STAKED-branch-only) never
        # arms — the ~30s relinquish timer every spare's 60s floor is budgeted against silently does
        # not exist; (b) under RECOVERY_MODE=rpc an unclassified node could attempt to TAKE the
        # staked identity. Same class as the 2026-08-10 standby incident (manual failback on a
        # different key). Rule here mirrors the standby: DO NOTHING (no recovery, no take) and PAGE
        # like the emergency it is — immediately on entry, re-paged through ALERT_THROTTLE while it
        # persists, with a recovery notice when the identity classifies again (above). Whether an
        # unclassified holder should self-fence is a v0.7 design question — acting on a node we do
        # not understand needs the observation seam, not a hotfix.
        latency_str="UNKNOWN"
        now_unk=$(date +%s)
        if [[ $_unknown_identity_since -eq 0 ]]; then
            _unknown_identity_since=$now_unk
            _last_unknown_alert=$now_unk
            alert "UNKNOWN IDENTITY — this node's failover protection is INERT (no self-fence, no recovery) until the identity matches its configured keys" "$CURRENT_IDENTITY" "🚨 PROTECTION OFFLINE"
        elif [[ $(( now_unk - _last_unknown_alert )) -ge $ALERT_THROTTLE ]]; then
            _last_unknown_alert=$now_unk
            alert "UNKNOWN IDENTITY persists ($(( (now_unk - _unknown_identity_since) / 60 ))m) — failover protection still INERT" "$CURRENT_IDENTITY" "🚨 PROTECTION OFFLINE"
        else
            log_warn "Unknown identity: $CURRENT_IDENTITY (protection inert — paged)"
        fi
        display_status "UNKNOWN"
    fi

    # --- Heartbeat: periodic status log ---
    now_hb=$(date +%s)
    if [[ $(( now_hb - _last_heartbeat )) -ge $HEARTBEAT_INTERVAL ]]; then
        id_label="STAKED"
        [[ "$CURRENT_IDENTITY" != "$STAKED_PUBKEY" ]] && id_label="UNSTAKED"

        # Quick ping summary
        ping_ok=""
        for t in "${CONNECTIVITY_TARGETS[@]}"; do
            ping -c 1 -W "$CONNECTIVITY_TIMEOUT" "$t" &>/dev/null && ping_ok+="${t}✓ " || ping_ok+="${t}✗ "   # v0.6.1 (N1)
        done

        log_info "♥ Heartbeat: ${id_label} | Internet: ${ping_ok}| Checks: $STAT_CHECKS | Switches: $STAT_SWITCHES | T2 calls: $STAT_TIER2_CHECKS | FP: $STAT_FALSE_POSITIVES | Window: [${_delinq_window:-empty}]"
        _proof_status_line   # v0.7 (Block 6.1, §2.7 (b)): the standing unpaired line — rides the v0.6.4 status-log cadence (this ♥ Heartbeat block, every HEARTBEAT_INTERVAL); a no-op on this HOLDER daemon (_proof_role_is_spare returns 1) and on every un-armed host — kept at the same surface in both daemons so the call sites stay symmetric
        _last_heartbeat=$now_hb
    fi

    save_state   # v0.6.9 (H3): persist the self-fence baseline every cycle (plain overwrite, no fsync) so a monitor restart mid-stall inherits the clock

    display_status "$latency_str"
    _watchdog_pet   # §5 end-of-cycle pet (Block 5.2): the cycle's last op returned — no-op outside the armed unit
    _watchdog_sleep "$_current_interval"   # FF-B3 (fix round): chunked under the armed unit — ANY legal interval is safe (plain sleep un-armed)
done

log_info "Main loop exited."
