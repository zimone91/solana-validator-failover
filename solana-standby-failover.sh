#!/bin/bash

# bash 5.2+ made "&" special in ${var//pat/replacement} (patsub_replacement, ON by default): the
# replacement's "&" expands to the matched text, which silently corrupts _html_escape's "&lt;"/"&gt;"
# on Ubuntu 24.04 / Debian 12 — broken Telegram HTML = CRITICAL alerts silently failing to send.
# This codebase is written against bash-3.2 substitution semantics; restore them everywhere.
# (No-op error on bash < 5.2, hence the || true.)
shopt -u patsub_replacement 2>/dev/null || true

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
VOTE_LIVENESS_EPSILON=2                   # lastVote must advance > this many slots to count as "voting"
VOTE_LIVENESS_MIN_INTERVAL=10             # min seconds between the two lastVote samples for a valid delta

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
_liveness_first_vote=""
_liveness_first_tip=""
_liveness_first_ts=0

_running=true
_last_status_log=0
_takeover_alert_sent=""
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
    local v
    v=$(_state_get LAST_TAKEOVER_TIME)
    [[ -n "$v" ]] && { LAST_TAKEOVER_TIME="$v"; log_info "State restored: LAST_TAKEOVER_TIME=$LAST_TAKEOVER_TIME"; }
    # v0.6.9 (H1.3): restore the self-fence re-take lockout UNCONDITIONALLY (like LAST_TAKEOVER_TIME —
    # a stale value is benign: the cooldown has long expired; a fresh one MUST survive Restart=always,
    # else the monitor restart re-opens the take-back-what-we-just-fenced hazard). FAILURE DIRECTION:
    # restoring can only ever BLOCK a take, never cause one.
    v=$(_state_get SELF_FENCE_DEMOTE_TIME)
    [[ -n "$v" && $v -gt 0 ]] && { SELF_FENCE_DEMOTE_TIME="$v"; log_info "State restored: SELF_FENCE_DEMOTE_TIME=$SELF_FENCE_DEMOTE_TIME (re-take lockout survives the restart)"; }

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
        ps=$(_state_get SF_LAST_CONFIRMED_SLOT); pa=$(_state_get SF_LAST_CONFIRMED_ADVANCE_TS)
        pn=$(_state_get SF_NOANSWER_SINCE);      pv=$(_state_get SF_VOTELAG_SINCE)
        pb=$(_state_get SF_VOTELAG_BASELINE);    ph=$(_state_get SF_VOTELAG_HEALTHY)
        if [[ -n "$ps" ]]; then
            _last_confirmed_slot="$ps"; _last_confirmed_advance_ts=$now   # slot verbatim, timer restarts
            if [[ "$role" == "staked" && -n "$pa" && $(( now - pa )) -ge $SELF_FENCE_ISOLATION_SECS ]]; then
                _selffence_restore_pending=1; _selffence_restored_advance_ts="$pa"
            fi
        fi
        if [[ "$role" == "staked" && -n "$pn" && $pn -gt 0 ]]; then
            _selffence_noanswer_restore_pending=1; _selffence_restored_noanswer_since="$pn"
        fi
        [[ "$pb" == "1" ]] && _selffence_votelag_baseline=1
        [[ -n "$ph" ]] && _selffence_votelag_healthy=$((10#$ph))
        if [[ "$role" == "staked" && -n "$pv" && $pv -gt 0 ]]; then
            _selffence_votelag_restore_pending=1; _selffence_restored_votelag_since="$pv"
        fi
        log_info "State restored (age ${age}s <= ${STATE_MAX_AGE_SECS}s): self-fence baseline slot=${ps:-none} role=${role:-unknown} noanswer_since=${pn:-0} votelag_since=${pv:-0}"
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
    {
        printf 'LAST_TAKEOVER_TIME=%s\n'            "$LAST_TAKEOVER_TIME"
        printf 'SELF_FENCE_DEMOTE_TIME=%s\n'        "${SELF_FENCE_DEMOTE_TIME:-0}"
        printf 'SF_LAST_CONFIRMED_SLOT=%s\n'        "${_last_confirmed_slot:-}"
        printf 'SF_LAST_CONFIRMED_ADVANCE_TS=%s\n'  "${_last_confirmed_advance_ts:-0}"
        printf 'SF_NOANSWER_SINCE=%s\n'             "${_selffence_noanswer_since:-0}"
        printf 'SF_VOTELAG_SINCE=%s\n'              "${_selffence_votelag_since:-0}"
        printf 'SF_VOTELAG_BASELINE=%s\n'           "${_selffence_votelag_baseline:-0}"
        printf 'SF_VOTELAG_HEALTHY=%s\n'            "${_selffence_votelag_healthy:-0}"
        printf 'ROLE_AT_SAVE=%s\n'                  "$_role"
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

# --- Full takeover attempt (gates: window → delay → external confirm → gossip → take) ---
attempt_takeover() {
    now=$(date +%s)
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
        # v0.6.2 (C1/C2): capture the vote-liveness FIRST sample at delay start (all roles).
        # v0.6.3 (Block 1): capture the RPC-freshness reference tip alongside lastVote.
        if [[ "$VOTE_LIVENESS_VERIFY" == "true" && -z "$_liveness_first_vote" ]]; then
            local s0; s0=$(get_staked_liveness_sample) || s0=""
            if [[ -n "$s0" ]]; then
                _liveness_first_vote="${s0%% *}"; _liveness_first_tip="${s0##* }"; _liveness_first_ts="$now"
                log_info "[liveness prefetch] first sample lastVote=${_liveness_first_vote} tip=${_liveness_first_tip}"
            fi
        fi
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
        if [[ $liveness -eq 0 ]]; then
            fence_reason="staked identity is actively voting"
            # v0.6.7 (N3): holder is STILL voting → re-anchor the takeover delay to now, so the full
            # delay must re-elapse from this observation before STANDBY may take (see attempt_takeover
            # head). Only set on an "active" verdict — "frozen"/"cannot determine" must NOT push the
            # anchor, or the takeover could never fire.
            LAST_LIVENESS_ACTIVE_TIME=$(date +%s)
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

    alert_info "🔍 Takeover: $tier_summary"
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

# Echo "<lastVote> <ref>" for the staked vote account AND a cluster-wide freshness reference,
# BOTH read from the SAME getVoteAccounts payload, via external RPC (Tier2 → Tier3). Empty output
# + nonzero return when no external RPC can answer.
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
    local rpc vote_result lv ref
    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        [[ -z "$rpc" ]] && continue
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
        printf '%s %s\n' "$lv" "$ref"
        return 0
    done
    return 1
}

# Compare two lastVote samples separated by real time (>= VOTE_LIVENESS_MIN_INTERVAL).
# Returns: 0 = actively voting (advanced > epsilon)        → BLOCK takeover
#          1 = not voting (frozen across the interval)      → fence clear
#          2 = cannot determine (externals down / too soon / backwards / RPC tip stalled) → BLOCK
# The first sample is normally captured during the takeover delay (see attempt_takeover).
# Self-correcting: when advancement is seen the first sample is re-based to "now", so a holder
# that voted earlier and then died is detected as frozen after one MIN_INTERVAL rather than
# blocking forever.
staked_is_actively_voting() {
    local now2 sample cur tip elapsed delta tip_delta
    now2=$(date +%s)
    sample=$(get_staked_liveness_sample) || sample=""
    cur="${sample%% *}"; tip="${sample##* }"   # tip = cluster-wide max lastVote (freshness reference)
    if [[ -z "$sample" || ! "$cur" =~ ^[0-9]+$ || ! "$tip" =~ ^[0-9]+$ ]]; then
        log_warn "[liveness] staked lastVote/reference unavailable (externals down) — cannot determine"
        return 2
    fi

    # First sample not captured yet → record lastVote + reference tip and wait for a real interval.
    if [[ -z "$_liveness_first_vote" ]]; then
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now2"
        log_info "[liveness] first sample lastVote=$cur tip=$tip — need a second sample (~${VOTE_LIVENESS_MIN_INTERVAL}s)"
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
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now2"
        return 2
    fi

    delta=$(( cur - _liveness_first_vote ))
    if [[ $delta -gt $VOTE_LIVENESS_EPSILON ]]; then
        log_warn "[liveness] staked vote ADVANCED ${delta} slots in ${elapsed}s (tip +${tip_delta}) — holder is VOTING → BLOCK"
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now2"   # re-base for the next interval
        return 0
    fi
    if [[ $delta -lt 0 ]]; then
        log_warn "[liveness] lastVote went backwards (Δ${delta}) — inconsistent RPC view, cannot determine"
        _liveness_first_vote="$cur"; _liveness_first_tip="$tip"; _liveness_first_ts="$now2"
        return 2
    fi

    # v0.6.8 (B2): DOUBLE-SIGN-SAFETY INVARIANT — the FROZEN path deliberately does NOT re-base
    # _liveness_first_vote (only the ADVANCED/return-0 and backwards/return-2 paths above do). The first
    # sample stays PINNED for the whole takeover episode, so `delta` is measured against the episode start
    # over an ever-growing window: ANY vote burst that lifts the holder's lastVote > EPSILON above that pin
    # — at any point in the delay — trips return 0 (VOTING → BLOCK) and re-anchors the N3 countdown. This is
    # exactly what protects against the intermittent/flapping "wedged-but-alive" holder (Audit-1 B7): only a
    # holder that lands ZERO qualifying votes for the ENTIRE delay reads frozen. DO NOT refactor this to
    # re-base on the frozen path — a sliding per-interval window would re-open that double-sign hole.
    log_info "[liveness] staked vote frozen (Δ${delta} slots, tip +${tip_delta}, in ${elapsed}s) — holder not voting → clear"
    return 1
}

# ========================= IDENTITY SWITCHING =================================

take_staked_identity() {
    local reason="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would TAKE staked — $reason"
        alert "$reason" "$STAKED_PUBKEY" "[DRY RUN] WOULD TAKE STAKED"
        # v0.5.9: reset window + set cooldown to prevent alert spam every cycle
        LAST_TAKEOVER_TIME=$(date +%s); save_state   # v0.6.1 (F7)
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
        LAST_TAKEOVER_TIME=$(date +%s); STAT_TAKEOVERS=$((STAT_TAKEOVERS + 1)); save_state   # v0.6.1 (F7)
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
        LAST_TAKEOVER_TIME=$(date +%s); save_state   # v0.6.0: cooldown even on failure; v0.6.1 (F7): persist
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
_selffence_reset() { _last_confirmed_slot=""; _last_confirmed_advance_ts=$(date +%s); _selffence_noanswer_since=0; _selffence_votelag_since=0; _selffence_votelag_baseline=""; _selffence_votelag_healthy=0; _selffence_restore_pending=0; _selffence_noanswer_restore_pending=0; _selffence_votelag_restore_pending=0; _collision_strikes=0; _last_collision_check=0; }   # v0.6.9 (B1/S-6): also clear the collision-detector flap streak so each staked tenure debounces fresh

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
        SELF_FENCE_DEMOTE_TIME=$(date +%s)
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
    now=$(date +%s)

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
    _validate_numeric EXTERNAL_CONFIRM_THROTTLE 0
    _validate_numeric MAX_DELINQUENT_SLOTS 0
    _validate_numeric LOCAL_HEALTH_MAX_BEHIND 0
    _validate_numeric EXPECTED_PRIMARY_SELF_FENCE_SECS 0   # v0.6.6 (N1): cross-node timing safety
    _validate_numeric SELF_FENCE_MARGIN_SECS 0             # v0.6.6 (N1): cross-node timing safety
    _validate_numeric EXPECTED_PRIMARY_VOTE_LAG_SLOTS 0    # v0.6.8 (B2): reference for the EPSILON<<band assert
    _validate_numeric FASTPATH_CONFIRM_SAMPLES 1           # v0.6.8 (Option A): consecutive corroborated cycles
    _validate_numeric FASTPATH_STAGGER_SECS 0              # v0.6.8 (Option A): per-node stagger floor
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

while $_running; do
    STAT_CHECKS=$((STAT_CHECKS + 1))
    rotate_log
    heartbeat_ping   # v0.6.4: external watchdog ping — top of loop, before any `continue`

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
            [[ $FIRST_DELINQUENT_TIME -eq 0 ]] && FIRST_DELINQUENT_TIME=$(date +%s)

            # Enter turbo mode on first delinquent
            if [[ "$_turbo_mode" != "true" ]]; then
                _turbo_mode=true
                _current_interval=$TURBO_INTERVAL
                log_info "⚡ TURBO MODE: check interval ${CHECK_INTERVAL}s → ${TURBO_INTERVAL}s"
            fi

            now=$(date +%s)
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
                FIRST_DELINQUENT_TIME=0; _takeover_alert_sent=""
                LAST_LIVENESS_ACTIVE_TIME=0   # v0.6.7 (N3): reset with FIRST_DELINQUENT_TIME — fresh episode
                _fastpath_absent_seen=0; _fastpath_confirm=0   # v0.6.8 (S2): end the fast-path episode too, so the A2 absent→present transition cannot latch across the organic delinquency-clear into the next episode
                _gossip_prefetched=false; _gossip_result=""
                _last_confirm_attempt=0   # v0.6.1 (F2): fresh episode starts un-throttled
                _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0   # v0.6.2 (C1) / v0.6.3 (Block 1): drop stale sample + tip
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
