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
    local vote_result
    vote_result=$(curl -s -m 10 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null) || return 1

    local is_delinquent
    is_delinquent=$(echo "$vote_result" | jq -r \
        --arg pubkey "$STAKED_PUBKEY" \
        '.result.delinquent[]? | select(.nodePubkey == $pubkey) | .nodePubkey // empty' 2>/dev/null)
    [[ -n "$is_delinquent" ]]
}

tier1_get_vote_latency() {
    local slot_result vote_result current_slot last_vote
    slot_result=$(curl -s -m 10 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null) || { echo "-1"; return; }
    current_slot=$(echo "$slot_result" | jq -r '.result // empty' 2>/dev/null)

    vote_result=$(curl -s -m 10 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null) || { echo "-1"; return; }
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

    local vote_result
    vote_result=$(curl -s -m 15 "$rpc_url" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)

    if [[ $? -ne 0 || -z "$vote_result" ]]; then
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

    if [[ $? -eq 0 && -n "$ext_result" ]]; then
        ext_current_slot=$(curl -s -m 10 "$TIER2_RPC" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)

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

    local vote_info vote_node
    vote_info=$(curl -s -m 15 "$rpc_url" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null) || {
        log_warn "RPC unreachable: $rpc_url"; return 0; }

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
        -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null) || {
        log_warn "[$rpc_url] getClusterNodes failed"; return 0; }

    staked_gossip_ep=$(echo "$cluster_info" | jq -r \
        --arg pubkey "$STAKED_PUBKEY" \
        '.result[]? | select(.pubkey == $pubkey) | .gossip // empty' 2>/dev/null | head -1)

    [[ -z "$staked_gossip_ep" ]] && { log_warn "[$rpc_url] Staked not in gossip"; return 0; }

    local local_cluster our_gossip_ep
    local_cluster=$(curl -s -m 10 "$LOCAL_RPC" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null) || {
        log_warn "Local getClusterNodes failed"; return 0; }

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
        vote_result=$(curl -s -m 10 "$rpc" -X POST \
            -H "Content-Type: application/json" -H "Cache-Control: no-cache" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts","params":[{"commitment":"processed"}]}' 2>/dev/null) || continue
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
    now2=$(mono_now)   # v0.7 (Block 3): SAFETY clock — the recovery fence's sample interval must not be steppable
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
        return 2
    fi

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

    # RPC-freshness guard: the cluster-wide reference (max lastVote from the SAME payload as cur)
    # MUST advance between samples; if not, the RPC's view is stale/cached/lagging and a "frozen"
    # staked lastVote is meaningless → cannot determine → BLOCK. (cur and the reference share one
    # atomic snapshot, so a stale view can't show a fresh reference with a stale cur.)
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
        [[ $cur -lt $_liveness_first_vote ]] && _liveness_first_vote="$cur"
        _liveness_first_tip="$tip"; _liveness_first_ts="$now2"; _liveness_first_provider="$prov"
        return 2
    fi

    # INVARIANT(baseline-rises-only-on-voting): the episode vote baseline may RISE only on a
    # VOTING verdict; every other re-base (tip-guard, backwards, provider re-pin) may only LOWER it.
    # Full statement + the structural soundness argument: the standby twin's frozen path.
    log_info "[liveness] staked vote frozen (Δ${delta} slots, tip +${tip_delta}, in ${elapsed}s) — holder not voting → clear"
    return 1
}

# Drop the recovery vote-liveness samples so the next recovery episode starts fresh.
reset_recovery_liveness() { _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""; }

attempt_safe_recovery() {
    local now elapsed
    now=$(mono_now); elapsed=$(( now - LAST_SWITCH_TIME ))   # v0.7 (Block 3): SAFETY clock (RECOVERY_DELAY gate)

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
        sleep "$RECOVERY_CHECK_INTERVAL"; return 1
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
    # v0.6.9 (H2): systemctl stop did NOT cleanly succeed → the unit is still Restart=always, so a
    # direct SIGTERM/SIGKILL below would be undone by systemd after RestartSec (the validator resurrects
    # VOTING STAKED after the immediate verify passed). Mask the unit FIRST — --runtime so a reboot
    # clears the mask (fail toward recoverability). A failed mask never skips the kill (the delayed
    # re-verify below catches a resurrect either way). FAILURE DIRECTION: extra stopping power only —
    # masking can never keep a validator voting.
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
    sleep "${HARD_STOP_REVERIFY_SECS:-15}"
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
        if [[ $_rc -eq 124 || $_rc -eq 137 ]]; then
            _selffence_hard_stop "fdctl set-identity to unstaked timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged"; return $?
        fi
    else
        local out
        # v0.6.8 (B1): bound remove-all; a hang here means the admin socket is wedged → escalate at once
        # (set-identity below would hang the same way).
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" authorized-voter remove-all 2>&1); _rc=$?
        [[ -n "$out" ]] && log_info "remove-voter: $out"
        if [[ $_rc -eq 124 || $_rc -eq 137 ]]; then
            _selffence_hard_stop "authorized-voter remove-all timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged"; return $?
        fi

        local tower_file; tower_file=$(get_tower_path)
        [[ -f "$tower_file" ]] && { rm -f "$tower_file"; log_info "Removed tower: $tower_file"; }

        # v0.5.9: path-as-argument (official Anza failover API)
        # v0.6.8 (B1): bound set-identity; on a hang escalate to a hard stop so voting provably stops.
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$UNSTAKED_KEYPAIR" 2>&1); _rc=$?
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
    else
        local out
        # v0.6.0: NO --require-tower — split-brain safety is gossip-based and towers aren't
        # transferred between nodes, so a rebuilt tower is the safe path. --require-tower would
        # also block recovery (the tower was deleted going unstaked). Manual switchback scp's it first.
        # v0.6.8 (B1): bound but fail-safe (no escalation on the promote path).
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR" 2>&1); local _src=$?
        [[ -n "$out" ]] && log_info "set-identity: $out"
        [[ $_src -eq 124 || $_src -eq 137 ]] && log_warn "[recovery] set-identity to staked timed out (${SETIDENTITY_TIMEOUT}s) — promotion will read as failed (fail-safe: stays unstaked)"
        out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" authorized-voter add "$STAKED_KEYPAIR" 2>&1) || true
        [[ -n "$out" ]] && log_info "add-voter: $out"
    fi

    sleep 1    # v0.5.9: reduced from 2s
    CURRENT_IDENTITY=$(get_local_identity) || true
    if [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]]; then
        LAST_SWITCH_TIME=$(mono_now); STAT_SWITCHES=$((STAT_SWITCHES + 1)); save_state   # v0.6.1 (F7)
        _recovery_confirm_count=0; window_reset; reset_recovery_liveness; _selffence_reset   # v0.6.3 (Block 2/3)
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
    if [[ "$RECOVERY_MODE" == "rpc" ]]; then
        _validate_numeric RECOVERY_DELAY 0
        _validate_numeric RECOVERY_CHECKS 1
        _validate_numeric RECOVERY_CHECK_INTERVAL 0
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
    _drift_check SELF_FENCE_ISOLATION_SECS 30 low "an isolated holder keeps voting longer before self-fencing → erodes the relinquish-before-takeover margin"
    _drift_check SELF_FENCE_NOANSWER_SECS 30 low0 "a silent LOCAL RPC leaves the staked identity voting longer before the demote"
    _drift_check SELF_FENCE_VOTE_LAG_SLOTS 32 low0 "an egress-partitioned holder demotes later and can lose the relinquish-first race against a spare's takeover"
    _drift_check SELF_FENCE_VOTE_LAG_SECS 20 low0 "an egress-partitioned holder demotes later and can lose the relinquish-first race against a spare's takeover"
    _drift_check SELF_FENCE_MAX_BEHIND 150 low0 "a far-behind holder keeps its staked identity longer before the getHealth demote fires"
    _drift_check SELF_FENCE_HARD_STOP true bool "a wedged demote becomes alert-only — the staked identity can keep voting through it (the exact double-sign gap the hard-stop closes)"
    # ── [config-drift] end shared table ──
    # ── [config-drift] role-specific safety knobs ──
    _drift_check RECOVERY_DELAY 300 high "rpc-mode recovery re-takes the staked identity sooner after going unstaked — less settle time before an automatic re-take"
}

# ========================= STARTUP ============================================

startup_checks() {
    echo "============================================="
    echo " Solana PRIMARY Failover v0.6.10 (3-TIER RPC)"
    echo "============================================="

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
    local wc=0 _wait_start _wait_alerted=0
    _wait_start=$(date +%s)   # v0.6.9 (H3)
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
                log_warn "Persisted role STAKED + local validator unreachable ${STARTUP_STAKED_UNREACHABLE_ALERT_SECS}s+ at startup — sending URGENT alert"
                alert "PRIMARY was STAKED at last save + local validator unreachable since monitor startup (>${STARTUP_STAKED_UNREACHABLE_ALERT_SECS}s) — the daemon cannot self-demote; STANDBY may take over. Intervene (stop the validator or confirm the spare took over)." "$STAKED_PUBKEY" "PRIMARY UNREACHABLE WHILE STAKED 🚨"
                _wait_alerted=1
            fi
            sleep 5
        fi
    done
    [[ "$_running" != "true" ]] && exit 0

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
    [[ $STARTUP_GRACE -gt 0 ]] && { log_info "Grace: ${STARTUP_GRACE}s"; sleep "$STARTUP_GRACE"; }
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

while $_running; do
    STAT_CHECKS=$((STAT_CHECKS + 1))
    rotate_log
    heartbeat_ping   # v0.6.4: external watchdog ping — top of loop, before any `continue`

    CURRENT_IDENTITY=$(get_local_identity 2>/dev/null) || true
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
        sleep "$CHECK_INTERVAL"
        continue
    fi
    _last_unreachable_alert=0

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
            CONNECTIVITY_FAIL_COUNT=0
            LATENCY_FAIL_COUNT=0
            # Grace period — validator needs time to catch up and start voting
            log_info "Manual switch grace: ${STARTUP_GRACE}s (letting validator catch up)"
            sleep "$STARTUP_GRACE"
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
        display_status "NO INET"; sleep "$CHECK_INTERVAL"; continue
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
                display_status "SELF-FENCED"; sleep "$_current_interval"; continue
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
                        display_status "$latency_str"; sleep "$_current_interval"; continue
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
        _last_heartbeat=$now_hb
    fi

    save_state   # v0.6.9 (H3): persist the self-fence baseline every cycle (plain overwrite, no fsync) so a monitor restart mid-stall inherits the clock

    display_status "$latency_str"
    sleep "$_current_interval"
done

log_info "Main loop exited."
