#!/bin/bash
# failover-fence.sh (v0.7 Block 5.1) — the REAL fence body, dispatched by
# solana-failover-fence.service when the monitor unit reaches terminal `failed` (first missed
# watchdog pet). Installed only by the `failover arm` ceremony at the v0.7 rollout
# (upgrade-then-arm, release checklist); repo-tracked and CI-linted as a shippable artifact —
# NOTHING in this repository installs it anywhere.
#
# Failure-direction rule (every branch below labels its direction): toward stop/page, NEVER
# toward silently-staked. Marker direction: claim MORE fencing than proven, never less.
#
# VALIDATOR_TYPE=frankendancer is STOP-ONLY in v0.7 (a named limitation — reviewer-packet item):
# _read_identity and _startup_phase_evidence are agave-CLI-only, the fence's no-network rule
# below bans the daemons' fd identity read (a localhost curl getIdentity) like any other network
# call, and no fdctl demote rung exists here. So on an fd box EVERY real-fence dispatch takes
# the stop path: full validator stop + fenced-stopped + HOLD (operator-owned recovery) — and a
# stopped node never re-advertises the unstaked flip, so the spare's G2 verified-demote proof
# cannot form. See systemd/README.md (same statement, operator-facing).
#
# bash 3.2-safe; same interpreter discipline as the daemons (no namerefs, no assoc arrays, no
# backslash continuation inside [[ ]]).

# bash 5.2+ patsub_replacement guard — the v0.6.10 alert-death class (see the daemons' header).
shopt -u patsub_replacement 2>/dev/null || true

# ── config (env via the unit's EnvironmentFile; every default overridable) ──────────────────────
# §2.2: the outcome markers the restarted monitor reads (slice 5.2 consumes; this script only
# WRITES). Only TWO outcome values exist (fenced-stopped / fenced-demoted) — inventing a third
# would silently grow the monitor's state machine. (The page-only twin's `fenced-page-only`
# marker is the ONE deliberate exception — §2.3/TASK Deliverable 2: written by a DIFFERENT
# script in the un-armed state, and the twin never restarts the monitor, so it is not an input
# to the two-outcome state machine — but it CAN sit in FENCE_MARKER_DIR; slice 5.2 must ignore
# it, not choke on it.) One file per outcome in FENCE_MARKER_DIR
# (content: ISO timestamp + reason; atomic tmp+mv). Direction on an unprovable stop: the fence
# claims MORE fencing than proven, never less — a wedged/unverifiable stop still writes
# fenced-stopped (+ exit 1): the monitor's HOLD path treats the marker as authoritative, which
# parks the node in the conservative state (no watchdog re-arm, one CRITICAL page, operator owns
# recovery) instead of resuming as if nothing were fenced.
FENCE_MARKER_DIR="${FENCE_MARKER_DIR:-/var/lib/solana-failover}"
MONITOR_UNIT="${MONITOR_UNIT:-solana-failover-monitor.service}"
SETIDENTITY_TIMEOUT="${SETIDENTITY_TIMEOUT:-15}"
case "$SETIDENTITY_TIMEOUT" in ''|*[!0-9]*) SETIDENTITY_TIMEOUT=15 ;; esac

# [rev3/№5] The sustained re-poll window is an EMPIRICAL FLOOR, not a derived constant: the
# admin server's delivered-but-unanswered request lifetime is not derivable from source with
# confidence. Block 10 sets this constant BY MEASUREMENT (delayed-request scenario); PROVISIONAL
# until that lands (per §3a.3: time constants are derived or explicitly labeled empirical, never
# silently asserted).
FENCE_REPOLL_SECS="${FENCE_REPOLL_SECS:-5}"
case "$FENCE_REPOLL_SECS" in ''|*[!0-9]*) FENCE_REPOLL_SECS=5 ;; esac
[[ "$FENCE_REPOLL_SECS" -lt 1 ]] && FENCE_REPOLL_SECS=1   # 0 would skip the verify entirely — floor at 1

# H2 delayed-re-verify window (same numeric-guard idiom: garbage → the shipped default).
HARD_STOP_REVERIFY_SECS="${HARD_STOP_REVERIFY_SECS:-15}"
case "$HARD_STOP_REVERIFY_SECS" in ''|*[!0-9]*) HARD_STOP_REVERIFY_SECS=15 ;; esac

# §2.5 ladder-state trackers (see _ladder_proc_gone_ok). ACCEPTED means issued AND rc 0 — a
# merely-ISSUED set-identity earns no proc-gone excuse (the panel's b2: a FAILED set-identity
# with the process gone must go to the stop-fallback, not claim a demote).
_FENCE_SETID_ACCEPTED=""
_FENCE_PROC_GONE=""

# stderr, deliberately: several callers run inside $(…) capture (e.g. the identity read), and a
# stdout page would be swallowed into the captured value instead of reaching the journal. The
# unit routes StandardError=journal.
_fence_log() { printf '[failover-fence] %s\n' "$*" >&2; }

# NO NETWORK anywhere in this script — pages are journal lines only; the restarted monitor's
# channels deliver them (slice 5.2). A fence that waits on Telegram is a fence that can hang
# mid-demote: the demote/stop path must never sit behind a curl timeout. The journal line
# survives for the operator either way.
_fence_page()      { _fence_log "PAGE[CRITICAL]: $*"; }
_fence_page_info() { _fence_log "PAGE[INFO]: $*"; }

# ── process + unit discovery ────────────────────────────────────────────────────────────────────

# The daemons' _validator_pid idiom (v0.6.9 H1/S4): pid of the running validator, any client,
# or empty if none is running.
_validator_pid() {
    local p; p=$(pgrep -x agave-validator 2>/dev/null | head -1)
    [[ -z "$p" && "$VALIDATOR_TYPE" == "frankendancer" ]] && p=$(pgrep -x fdctl 2>/dev/null | head -1)
    [[ -z "$p" ]] && p=$(pgrep -x solana-validator 2>/dev/null | head -1)
    printf '%s' "$p"
}

# VALIDATOR_UNIT from the validator process's cgroup (/proc/<pid>/cgroup) — kills the hard-coded
# solana.service (a box named sol.service would make a name-guessing stop a silent no-op;
# addendum §1). Configured VALIDATOR_UNIT wins if set; detection is the default. Deliberately NO
# fallback to the daemons' VALIDATOR_SERVICE: its default ("solana") is exactly the guess this
# function exists to kill. No unit determinable → rc 1: the stop-fallback CANNOT stop and says
# so (claim-more direction there), rather than stopping a guessed name that silently no-ops.
_detect_validator_unit() {
    if [[ -n "${VALIDATOR_UNIT:-}" ]]; then printf '%s\n' "$VALIDATOR_UNIT"; return 0; fi
    local pid cg unit
    pid=$(_validator_pid)
    [[ -z "$pid" ]] && return 1
    cg="${FENCE_PROC_ROOT:-/proc}/$pid/cgroup"   # FENCE_PROC_ROOT: test seam only (fixture /proc)
    [[ -r "$cg" ]] || return 1
    # cgroup v2: the single line `0::/system.slice/<unit>/…`
    unit=$(awk -F/ '/^0::/ { for (i = 1; i <= NF; i++) if ($i ~ /\.service$/) { print $i; exit } }' "$cg" 2>/dev/null)
    if [[ -z "$unit" ]]; then
        # cgroup v1 fallback: the `systemd:` hierarchy line
        unit=$(awk -F/ '/systemd:/ { for (i = 1; i <= NF; i++) if ($i ~ /\.service$/) { print $i; exit } }' "$cg" 2>/dev/null)
    fi
    [[ -z "$unit" ]] && return 1
    printf '%s\n' "$unit"
}

# §5 per-op watchdog pet — BELT on top of the unit's derived TimeoutStartSec SUSPENDERS (the
# fence unit skeleton carries the worst-case arithmetic): one wedged admin call must not
# silently eat the whole fence budget, so each rung extends the oneshot's start budget by the
# RUNG'S OWN bound ($1, seconds; defaults to SETIDENTITY_TIMEOUT; +10 s margin) via
# EXTEND_TIMEOUT_USEC (systemd ≥ 236; a datagram to $NOTIFY_SOCKET — the same socat transport
# as the monitor's pets, a unix socket write, not network; the unit's NotifyAccess=all is what
# makes PID 1 accept a datagram from this short-lived socat child at all — without it the pet
# is discarded). Missing socket/socat → no-op. Failure direction, honestly: a missing/discarded
# pet can cut the fence short mid-ladder if the budget is undersized (PID 1 kills the oneshot →
# unit `failed`, NO marker, NO monitor restart, and no OnFailure chain exists for the fence
# itself — a silent half-fence); the unit's derived TimeoutStartSec is the bound that prevents
# that, and the pets only buy slow-but-progressing rungs more room. NOT "never staked" — the
# §2.5 delivered-but-unanswered window a cut fence leaves open is exactly why the derived
# budget must dominate the worst case.
_fence_pet() {
    [[ -z "${NOTIFY_SOCKET:-}" ]] && return 0
    command -v socat >/dev/null 2>&1 || return 0
    local bound usec
    bound="${1:-$SETIDENTITY_TIMEOUT}"
    case "$bound" in ''|*[!0-9]*) bound="$SETIDENTITY_TIMEOUT" ;; esac
    usec=$(( (bound + 10) * 1000000 ))
    case "$NOTIFY_SOCKET" in
        @*) printf 'EXTEND_TIMEOUT_USEC=%s' "$usec" | timeout -k 2 3 socat -u - "ABSTRACT-SENDTO:${NOTIFY_SOCKET#@}" 2>/dev/null || true ;;
        *)  printf 'EXTEND_TIMEOUT_USEC=%s' "$usec" | timeout -k 2 3 socat -u - "UNIX-SENDTO:${NOTIFY_SOCKET}" 2>/dev/null || true ;;
    esac
    return 0
}

# Single-instance guard: systemd serializes its own dispatches, but a manual fence run during a
# live incident is plausible, and a concurrent twin interleaving with the ladder can make the
# proc-gone excuse lie (the panel's twin-interleave trace). flock -n on a lock file in
# FENCE_MARKER_DIR: the LOSER logs + exits 0 WITHOUT acting — the lock holder owns the incident
# (direction: one actor, loudly; never two actors mutating one node). `flock` absent (the macOS
# dev/test harness) → skip with no lock: every Linux deploy host ships flock (util-linux).
_acquire_instance_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    mkdir -p "$FENCE_MARKER_DIR" 2>/dev/null || true
    # NO stderr suppression on this exec: redirections on a bare `exec` are PERMANENT for the
    # whole script — a `2>/dev/null` here would silence every page/log line that follows (found
    # red on the Linux leg). An open failure printing to the journal is the loud direction
    # anyway; on failure, proceed without the lock (fencing beats single-instance purity).
    exec 9>"$FENCE_MARKER_DIR/.fence.lock" || return 0
    # (reviewer, 5.1 GO fix): -n gave the holder an UNBOUNDED veto — the only unbounded wait in a
    # script where every external call is bounded, and the only exit that neither restarted the
    # monitor nor could deliver its page (journal-only, monitor dead at OnFailure dispatch).
    # Clean concurrency resolves by WAITING: every ladder rung is bounded, a real twin finishes
    # far inside FENCE_LOCK_WAIT and the idempotent verdict paths handle the already-fenced
    # state. Expiry is therefore NOT concurrency — it is a STUCK holder (bash in D-state, cgroup
    # freeze: the external calls are bounded, the process itself is not). Not acting is the
    # double-sign direction; the ladder is idempotent by construction and its one destructive
    # step is bounded → page + restart the monitor + FENCE WITHOUT the lock, and force the final
    # exit to 1 (_fence_exit) so the unit lands in `failed` and is visible in systemctl --failed.
    if ! flock -w "${FENCE_LOCK_WAIT:-30}" 9; then
        _fence_page "instance lock still held after ${FENCE_LOCK_WAIT:-30}s — the holder is STUCK (not concurrency: every rung is bounded); fencing WITHOUT the lock; this unit will exit failed for visibility"
        _restart_monitor || _fence_page "monitor restart enqueue failed on the stuck-lock path — intervene"
        _FENCE_LOCKLESS=1
    fi
    return 0
}

# (reviewer, 5.1 GO fix): every outcome exit goes through here. On the stuck-lock (lockless)
# path even a SUCCESSFUL outcome exits 1 — the unit must land in `failed` and show in
# systemctl --failed, because a fence that had to bypass its own instance lock is an anomaly
# the operator must see even when the fencing itself worked.
_fence_exit() {
    if [[ -n "${_FENCE_LOCKLESS:-}" && "$1" == "0" ]]; then
        _fence_log "outcome successful but the instance lock was bypassed — exiting 1 for visibility"
        exit 1
    fi
    exit "$1"
}

# B1 marker freshness = SAME BOOT. Boot epoch = now − uptime, uptime via
# ${FENCE_PROC_ROOT:-/proc}/uptime (the same test seam as the cgroup read); a marker whose mtime
# predates this boot (with a 60 s slack TOWARD stale) is from a PREVIOUS boot — the validator
# was restarted since it was written, so nothing the marker claims about "stopped" still holds.
# rc 0 = FRESH (same boot); rc 1 = STALE. Unreadable/garbage uptime, epoch, or mtime → STALE.
# Direction (the panel's B1 blocker): honoring a stale marker is the double-sign hole — a
# staked, votable node left unfenced, unmonitored, its CRITICAL page journal-only; proceeding
# on a genuinely-stopped node is idempotent-harmless (the stop path re-verifies a gone process
# and re-writes the same marker).
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

# §5 crash-loop breaker — the first thing main() runs after config load + the instance lock. A
# fence that re-enters after a COMPLETED stop must refuse to act twice: a crash-looping fence
# re-running the stop path forever is a mutation loop, and acting twice on a completed stop can
# only fight the operator's recovery. FRESHNESS-GATED (panel B1): only a SAME-BOOT marker earns
# the refusal — a marker surviving from a previous boot proves the operator restarted the
# validator (possibly staked, for switchback) and must not shield a genuine new incident.
_crash_loop_guard() {
    local m="$FENCE_MARKER_DIR/fenced-stopped"
    if [[ -e "$m" ]]; then
        if _marker_same_boot "$m"; then
            # (re-panel DS-1): the same-boot mtime is a PROXY for "still fenced" — it cannot see
            # the IN-boot recovery path (operator unmask+start → a running, possibly staked node
            # with a same-boot marker). Refusing blind would export this guard's double-sign
            # safety to the 5.2 HOLD invariant silently. Self-sufficiency: one proc check —
            # a RUNNING validator means the stop did not hold (or recovery is underway), and the
            # normal verdict flow handles every identity case correctly; refuse-to-act-twice
            # applies only to a node that is provably DOWN. This also collapses the backward-NTP
            # future-mtime amplifier (a mis-FRESH marker still cannot shield a running node).
            # _validator_pid pipes through head → its rc is head's rc (0 even when nothing was
            # found); the ALIVE test is a NON-EMPTY pid, never the rc.
            if [[ -n "$(_validator_pid 2>/dev/null)" ]]; then
                _fence_log "WARN: same-boot fenced-stopped marker but a validator process is RUNNING — the stop did not hold or recovery is underway; fencing normally"
                _fence_page "same-boot fenced-stopped marker present but a validator process is RUNNING — ignoring the breaker, fencing normally"
            else
            _fence_page "fence re-entered after a completed stop (marker $m) — refusing to act twice; operator owns recovery"
            # The monitor is DEAD in `failed` at OnFailure dispatch, and _fence_page is
            # journal-only — restarting the monitor into HOLD is what actually DELIVERS the
            # CRITICAL page and keeps the node monitored (the panel's two amplifiers, both
            # closed here; every other exit path already restarts it).
            _restart_monitor || _fence_page "monitor restart enqueue failed after the refuse-to-act-twice verdict — node UNMONITORED next to a stopped validator; intervene"
            _fence_exit 0
            fi
        fi
        # STALE: pre-boot marker → WARN + page + PROCEED into the normal verdict flow.
        # Deliberately NOT deleted here: if this run completes, its outcome write refreshes or
        # supersedes it (see _write_marker); if this run dies mid-flight, the stale marker is
        # still only ignorable state — deleting first would destroy evidence before acting.
        _fence_log "WARN: fenced-stopped marker predates this boot — treating as stale"
        _fence_page "stale fenced-stopped marker from a previous boot ($m) — ignoring the breaker, fencing normally"
    fi
    # ASYMMETRY, deliberate: a pre-existing fenced-demoted does NOT block a re-run — the §2.2
    # demoted path re-verifies cheaply and idempotently (an already-unstaked node is one bounded
    # read + a marker refresh; a re-staked node getting re-demoted is the fence doing its job).
    # fenced-stopped blocks because the stop path is the destructive, non-idempotent one.
    return 0
}

# ── bounded admin-socket reads (the daemons' get_local_identity class) ──────────────────────────

# Bounded identity read; echoes the current identity pubkey. Empty/failed output = unreadable
# (rc 1) — the §2.2 verdict in main() decides the direction. agave admin CLI only in v0.7: on a
# frankendancer box this read fails → the verdict falls toward the stop path (safe direction),
# never toward assuming an identity.
_read_identity() {
    local out
    out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" contact-info 2>/dev/null | grep Identity | awk '{print $2}')
    [[ -z "$out" ]] && return 1
    printf '%s\n' "$out"
    return 0
}

# Bounded `systemctl is-active` on the DETECTED unit — the only read-only systemctl the fence
# performs. No unit determinable → rc 1 (no activity evidence; the caller falls toward stop).
_validator_unit_active() {
    local unit
    unit=$(_detect_validator_unit) || return 1
    timeout -k 5 10 systemctl is-active --quiet "$unit" 2>/dev/null
}

# §2.2 third-branch evidence: the admin socket / health answering "starting". Probe: a bounded
# `agave-validator monitor` snapshot — during startup it reports the admin socket's
# start-progress phase ("Validator startup: …"); a READY validator prints slot status instead.
# rc 0 ONLY on a positive startup token in the output; the probe's exit code is deliberately
# ignored (timeout cutting off a streaming monitor is expected). Absence of evidence is NOT
# evidence of startup. The token set is EMPIRICAL — Block 10's E2E validates it against the
# deploy agave version on real hosts.
_startup_phase_evidence() {
    local out
    out=$(timeout -k 5 8 "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" monitor 2>&1)
    # Word-anchored: 'restarting' contains 'starting' and is READY-node noise, NOT startup
    # evidence (the false-positive direction on this branch is 'do not fence'). With -i the
    # [^a-z] class is case-insensitive too, so 'Restarting' is equally excluded.
    printf '%s' "$out" | grep -qiE '(^|[^a-z])(starting|startup)'
}

# ── the §2.5 ladder ops (bounded, H4/B1 idiom: timeout -k 5, wedge = rc 124/137) ────────────────

# §2.5 expected-and-benign — but ONLY after an ACCEPTED set-identity (issued AND rc 0):
# fence-issued set-identity <unstaked> can make the replay loop exit the process on tower-reload
# failure; under Restart=always the unit returns it governed by its --identity argument (an
# invariant this script cannot verify — the arm ceremony (5.3) must verify the unit's ExecStart
# carries the unstaked identity). Process-gone after an ACCEPTED set-identity is therefore a
# DEMOTE OUTCOME, not an error. A FAILED set-identity (rc != 0) earns NO excuse: nothing was
# provably applied, so proc-gone there is plain doubt → stop-fallback — and the stop path's
# systemctl stop also CANCELS the Restart=always resurrection this excuse would otherwise wave
# back in; its verify then finds the process gone → fenced-stopped, exit 0 — an honest claim.
# BEFORE set-identity there is no excuse either. (Same _validator_pid trust the shipped H2
# hard-stop's "confirmed DOWN" claim already relies on.)
_ladder_proc_gone_ok() {
    [[ -n "$_FENCE_SETID_ACCEPTED" ]] || return 1
    [[ -n "$(_validator_pid)" ]] && return 1
    _FENCE_PROC_GONE=1
    return 0
}

_admin_remove_all() {
    local out rc
    out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" authorized-voter remove-all 2>&1); rc=$?
    [[ -n "$out" ]] && _fence_log "remove-voter: $out"
    if [[ $rc -eq 124 || $rc -eq 137 ]]; then
        _fence_log "authorized-voter remove-all WEDGED (rc $rc after ${SETIDENTITY_TIMEOUT}s) — admin-socket doubt"
        return 1   # direction: doubt → stop-fallback
    fi
    if [[ $rc -ne 0 ]]; then
        if _ladder_proc_gone_ok; then
            _fence_log "remove-all failed (rc $rc) with the validator process GONE post-set-identity — §2.5 demote outcome; continuing"
            return 0
        fi
        return 1   # direction: doubt → stop-fallback
    fi
    return 0
}

_admin_set_identity_unstaked() {
    local out rc
    if [[ ! -s "${UNSTAKED_KEYPAIR:-}" ]]; then
        _fence_log "unstaked keypair missing/empty (${UNSTAKED_KEYPAIR:-unset}) — cannot demote"
        return 1   # direction: doubt → stop-fallback
    fi
    out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$UNSTAKED_KEYPAIR" 2>&1); rc=$?
    [[ -n "$out" ]] && _fence_log "set-identity: $out"
    if [[ $rc -eq 124 || $rc -eq 137 ]]; then
        _fence_log "set-identity WEDGED (rc $rc after ${SETIDENTITY_TIMEOUT}s) — admin-socket doubt"
        return 1   # direction: doubt → stop-fallback
    fi
    if [[ $rc -ne 0 ]]; then
        # FAILED set-identity: no proc-gone excuse here (ACCEPTED is never set on rc != 0 —
        # see _ladder_proc_gone_ok: nothing was provably applied, and the stop-fallback's
        # systemctl stop also cancels a Restart=always resurrection).
        return 1   # direction: doubt → stop-fallback
    fi
    _FENCE_SETID_ACCEPTED=1   # issued AND accepted (rc 0) — the §2.5 proc-gone excuse's gate
    return 0
}

# [rev3/№5] SUSTAINED identity re-poll over FENCE_REPOLL_SECS at ~1/s — NOT one read (a
# delivered-but-unanswered stale write can land after a single verify; the admin server's worker
# pool outlives the killed client). rc 0 ONLY if EVERY read in the window came back unstaked (or
# demote-consistent process-gone, §2.5 above).
_sustained_identity_repoll() {
    local i ident
    for (( i = 1; i <= FENCE_REPOLL_SECS; i++ )); do
        if ident=$(_read_identity); then
            if [[ -z "${UNSTAKED_PUBKEY:-}" || "$ident" != "$UNSTAKED_PUBKEY" ]]; then
                _fence_log "re-poll $i/$FENCE_REPOLL_SECS read '$ident' != unstaked — a stale write landed (the barrier's point)"
                return 1   # direction: doubt → stop-fallback
            fi
        else
            if _ladder_proc_gone_ok; then
                _fence_log "re-poll $i/$FENCE_REPOLL_SECS: identity unreadable, process GONE post-set-identity — §2.5 demote outcome"
            else
                _fence_log "re-poll $i/$FENCE_REPOLL_SECS: identity unreadable with the process alive"
                return 1   # direction: doubt → stop-fallback
            fi
        fi
        [[ $i -lt $FENCE_REPOLL_SECS ]] && sleep 1
    done
    return 0
}

# ── stop + verify (the daemons' H2 discipline, _selffence_hard_stop port) ───────────────────────
# stop → mask --runtime on stop failure (Restart=always must not resurrect a staked voter) →
# SIGTERM → SIGKILL → verify + delayed re-verify. rc 0 ONLY when the validator is provably DOWN.
_stop_validator() {
    local unit sc_out sc_rc mask_out mask_rc pid pid_found=""
    if ! unit=$(_detect_validator_unit); then
        # No configured VALIDATOR_UNIT and no cgroup-detectable unit: a stop against a GUESSED
        # name that silently no-ops is exactly the failure the detection seam kills — so no
        # guess, no stop. The caller claims fenced-stopped anyway + exits 1 (claim-more).
        _fence_page "stop-fallback CANNOT stop: no VALIDATOR_UNIT configured and no unit detectable from the validator cgroup — stop the validator BY HAND NOW"
        return 1
    fi
    _fence_pet 15   # stop rung's own bound (the timeout below); the stop path pets too — a
                    # budget cut mid-stop would be the skeleton's named silent half-fence
    sc_out=$(timeout -k 5 15 systemctl stop "$unit" 2>&1); sc_rc=$?
    [[ -n "$sc_out" ]] && _fence_log "systemctl stop $unit: $sc_out"
    if [[ $sc_rc -ne 0 ]]; then
        # H2: mask (--runtime — a reboot clears it; fail toward recoverability) BEFORE the kill,
        # so Restart=always cannot resurrect it voting staked after the immediate verify. A
        # failed mask never skips the kill. Direction: extra stopping power only.
        _fence_pet 15   # mask rung's own bound
        mask_out=$(timeout -k 5 15 systemctl mask --runtime "$unit" 2>&1); mask_rc=$?
        [[ -n "$mask_out" ]] && _fence_log "systemctl mask --runtime $unit: $mask_out"
        [[ $mask_rc -ne 0 ]] && _fence_log "mask --runtime failed (rc $mask_rc) — continuing with the kill path; the delayed re-verify catches a resurrect"
    fi
    # Fallback (non-systemd path wedged / stuck unit): SIGTERM, then SIGKILL if ignored.
    # One pet for the whole tail: kill-grace sleeps (3 s) + verify pgreps + the delayed
    # re-verify window below — this tail's own bound.
    _fence_pet $(( HARD_STOP_REVERIFY_SECS + 10 ))
    pid=$(_validator_pid)
    if [[ -n "$pid" ]]; then
        pid_found=1
        kill "$pid" 2>/dev/null || true
        sleep 2
        pid=$(_validator_pid)
    fi
    if [[ -n "$pid" ]]; then
        kill -9 "$pid" 2>/dev/null || true
        sleep 1
    fi
    # VERIFY (bounded pgrep re-checks): success ONLY on provably-down.
    pid=$(_validator_pid)
    if [[ -n "$pid" ]]; then
        _fence_log "stop UNVERIFIED — validator pid $pid still running after systemctl stop + SIGKILL"
        return 1   # direction: caller pages LOUDEST, claims fenced-stopped, exits 1
    fi
    if [[ $sc_rc -ne 0 && -z "$pid_found" ]]; then
        _fence_log "stop UNCONFIRMED — systemctl stop failed (rc $sc_rc) and no known validator process found; cannot confirm voting stopped"
        return 1   # direction: caller pages LOUDEST, claims fenced-stopped, exits 1
    fi
    # Delayed re-verify against a Restart=always resurrection: a directly-killed process can
    # pass the immediate check and come back voting staked after RestartSec.
    sleep "$HARD_STOP_REVERIFY_SECS"
    pid=$(_validator_pid)
    if [[ -n "$pid" ]]; then
        _fence_log "stop FAILED — validator RESURRECTED (pid $pid) within ${HARD_STOP_REVERIFY_SECS}s (Restart=always)"
        return 1   # direction: caller pages LOUDEST, claims fenced-stopped, exits 1
    fi
    return 0
}

# §2.2: restarting the monitor is the fence's LAST act in every outcome — the restarted monitor
# reads the marker and enters HOLD (fenced-stopped) or demoted monitoring (fenced-demoted).
# --no-block, load-bearing (panel B2): the monitor is Type=notify with READY gated on its FIRST
# successful identity read — on a replaying node READY is legitimately MINUTES away, so a
# job-blocking restart under the 15 s bound deterministically hit rc 124 there, and a killed
# systemctl WAIT is not a canceled JOB: the restart proceeds while rc claims failure — that rc
# fed a false CRITICAL "UNMONITORED; intervene" on a healthy node, in exactly the window the
# third branch exists to protect. With --no-block the bounded call covers the ENQUEUE only;
# rc means enqueue outcome, and callers page only when the enqueue itself failed.
_restart_monitor() {
    local out rc
    out=$(timeout -k 5 15 systemctl restart --no-block "$MONITOR_UNIT" 2>&1); rc=$?
    [[ -n "$out" ]] && _fence_log "systemctl restart --no-block $MONITOR_UNIT: $out"
    [[ $rc -eq 0 ]]
}

# ── outcome marker (§2.2 — the only two values) ─────────────────────────────────────────────────
_write_marker() {
    # $1 = fenced-stopped | fenced-demoted ; $2 = reason. Atomic (tmp+mv in the same dir): the
    # restarted monitor must never read a half-written marker.
    # COUPLING, load-bearing (reviewer, 5.1 GO — named at BOTH ends): fenced-stopped may be
    # written on an UNVERIFIED stop (claim-more). That is safe ONLY because _crash_loop_guard
    # verifies process-LIVENESS before honoring this marker — remove that liveness check as
    # "redundant" and this marker becomes a shield for a RUNNING node.
    # Precedence = claim-more, enforced in this ONE write path: NEVER write fenced-demoted while
    # fenced-stopped exists (the stopped claim is the stronger, conservative one — slice 5.2's
    # HOLD treats it as authoritative), and a fenced-stopped write SUPERSEDES a demoted sibling
    # (removes it) — so the two markers can never coexist with the weaker one newer (the
    # panel's twin-interleave hazard).
    local tmp
    if [[ "$1" == "fenced-demoted" && -e "$FENCE_MARKER_DIR/fenced-stopped" ]]; then
        # (re-panel): claim-more applies to a SAME-BOOT stopped marker only. A STALE (pre-boot)
        # one describes a PREVIOUS incident — letting it gag a fresh demote outcome would page
        # "demoted, monitor restarting into demoted monitoring" while the on-disk marker still
        # says stopped, and the restarted monitor would HOLD a running-unstaked node.
        if _marker_same_boot "$FENCE_MARKER_DIR/fenced-stopped"; then
            _fence_log "same-boot stopped marker present — keeping the stronger claim (fenced-demoted not written)"
            return 0
        fi
        _fence_log "STALE (pre-boot) stopped marker superseded by this boot's demote outcome"
        rm -f "$FENCE_MARKER_DIR/fenced-stopped" 2>/dev/null
    fi
    mkdir -p "$FENCE_MARKER_DIR" 2>/dev/null || true
    tmp="$FENCE_MARKER_DIR/.$1.tmp.$$"
    if printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$2" > "$tmp" 2>/dev/null && mv -f "$tmp" "$FENCE_MARKER_DIR/$1" 2>/dev/null; then
        [[ "$1" == "fenced-stopped" ]] && rm -f "$FENCE_MARKER_DIR/fenced-demoted" 2>/dev/null
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    _fence_page "could not write marker '$1' under $FENCE_MARKER_DIR — restarted monitor will see NO marker (treat as unfenced: page-and-hold on its own evidence)"
    return 0
}

# ── §2.5 demote ladder (Lever 2) — order load-bearing ───────────────────────────────────────────
_demote_ladder() {
    # remove-all FIRST closes the one-vote window (reversing the first two ops reopens it —
    # source-verified demote order, addendum §0 TL;DR). Direction on EVERY failure: rc 1 → the
    # caller's stop-fallback. Never "assume it worked". Each pet carries the NEXT rung's own
    # bound (see _fence_pet — belt on the unit's derived TimeoutStartSec suspenders).
    local repoll_bound
    _fence_pet "$SETIDENTITY_TIMEOUT"; _admin_remove_all            || return 1   # direction: doubt → stop-fallback
    _fence_pet "$SETIDENTITY_TIMEOUT"; _admin_set_identity_unstaked || return 1   # direction: doubt → stop-fallback
    # Expected-and-benign from here on (§2.5, gated on the ACCEPTED set-identity above):
    # process-gone is a DEMOTE OUTCOME, not an error — see _ladder_proc_gone_ok.
    _fence_pet "$SETIDENTITY_TIMEOUT"; _admin_remove_all            || return 1   # the LATE-VOTER-ADD BARRIER (stale-write §2.5)
    # The repoll rung's REAL bound (the panel's ~104 s at shipped defaults), not the flat
    # per-op one: N bounded reads (each ≤ SETIDENTITY_TIMEOUT + 5 kill-grace) + N−1 sleeps.
    repoll_bound=$(( FENCE_REPOLL_SECS * (SETIDENTITY_TIMEOUT + 5) + FENCE_REPOLL_SECS - 1 ))
    _fence_pet "$repoll_bound"; _sustained_identity_repoll || return 1   # EMPIRICAL floor [rev3/№5]; any doubt → stop-fallback
    return 0
}

# ── stop-fallback (the terminal safe direction) ─────────────────────────────────────────────────
_stop_fallback() {
    local why="$1"
    if _stop_validator; then
        _write_marker fenced-stopped "$why"
        # §2.2: restarted monitor enters HOLD — no watchdog re-arm, one CRITICAL page, quiet.
        _fence_page "FENCED (stopped): $why — validator STOPPED+verified. Monitor restarting into HOLD; recover with unmask+start ONLY after confirming no spare holds the identity."
        _restart_monitor || _fence_page "monitor restart enqueue failed after fenced-stopped — node is DOWN and UNMONITORED; intervene now"
        _fence_exit 0
    fi
    # Even the stop failed/unverifiable: the marker is STILL fenced-stopped — claim MORE fencing
    # than proven, never less. The monitor's HOLD path treats the marker as authoritative, which
    # parks the node in the conservative state (no watchdog re-arm, no auto-recovery) while the
    # LOUDEST page + this unit's own `failed` state (exit 1) summon the operator. The monitor is
    # still restarted: live monitoring + its own self-fence paths are strictly safer than a dead
    # monitor next to a possibly-staked validator. Direction: page, never silently-staked.
    _write_marker fenced-stopped "$why (stop UNVERIFIED — claim-more direction; operator must confirm the validator is down)"
    _fence_page "FENCE FAILED: $why — could NOT verify the validator stopped; the staked identity may STILL BE VOTING. INTERVENE NOW (stop the validator by hand)."
    _restart_monitor || _fence_page "monitor restart enqueue ALSO failed — dead monitor next to a possibly-staked validator; intervene now"
    _fence_exit 1
}

# ── main: the §2.2 identity verdict (three branches) ────────────────────────────────────────────
main() {
    _acquire_instance_lock
    _crash_loop_guard

    local ident
    if ident=$(_read_identity); then
        # §2.2 verdict (b): ALREADY unstaked — marker + INFO page, ZERO admin mutations (the
        # crash-loop asymmetry above leans on this branch being cheap and idempotent). Any
        # OTHER readable identity — staked or unknown — is treated as the staked class and
        # demoted: never assume an unknown key is safe (direction: unknown → demote, not trust).
        if [[ -n "${UNSTAKED_PUBKEY:-}" && "$ident" == "$UNSTAKED_PUBKEY" ]]; then
            _write_marker fenced-demoted "fence found the node already demoted (identity $ident); no mutations issued"
            _fence_page_info "fence found the node already demoted ($ident) — no admin mutations; monitor restarting into demoted monitoring"
            _restart_monitor || _fence_page "monitor restart enqueue failed after fenced-demoted (already-demoted verdict) — demoted node UNMONITORED; intervene"
            _fence_exit 0
        fi
        _fence_log "identity readable ($ident) — Lever-2 demote ladder (§2.5)"
        if _demote_ladder; then
            # Two TRUTHFUL, DISTINCT reasons (panel B1-note): the proc-gone outcome did NOT
            # verify sustained-unstaked and must not claim it — what it proved is an ACCEPTED
            # set-identity followed by the process exiting mid-ladder; the RETURNED process's
            # identity is governed by the unit's --identity argument, an invariant this script
            # cannot verify (the arm ceremony (5.3) must verify the unit's ExecStart carries
            # the unstaked identity).
            if [[ -n "$_FENCE_PROC_GONE" ]]; then
                _write_marker fenced-demoted "monitor watchdog failure; validator process exited mid-ladder after an ACCEPTED set-identity (§2.5 demote outcome) — the returned process's identity is governed by the unit's --identity argument, an invariant this script cannot verify; the arm ceremony (5.3) must verify the unit's ExecStart carries the unstaked identity"
                _fence_page "FENCED (demoted): ACCEPTED set-identity, then the validator process exited mid-ladder (§2.5). If Restart=always returns it, its identity is whatever the unit's --identity argument names. Monitor restarting into demoted monitoring."
            else
                _write_marker fenced-demoted "monitor watchdog failure; ladder verified by $FENCE_REPOLL_SECS sustained unstaked reads"
                # §2.2: validator RUNNING, unstaked — restarted monitor enters normal
                # demoted-holder monitoring (READY on first read, watchdog re-armed, marker
                # cleared on first clean cycle); the running node keeps re-advertising the
                # flip (what the spare's G2 reads).
                _fence_page "FENCED (demoted): validator running UNSTAKED, verified over the sustained window. Monitor restarting into demoted monitoring."
            fi
            _restart_monitor || _fence_page "monitor restart enqueue failed after fenced-demoted — demoted node UNMONITORED; intervene"
            _fence_exit 0
        fi
        _stop_fallback "demote ladder failed/doubtful"           # direction: doubt → stop
    else
        if _validator_unit_active && _startup_phase_evidence; then
            # §2.2 THIRD BRANCH: unreadable BUT active WITH positive startup-phase evidence ⇒
            # page + restart monitor, NO stop (a healthy validator mid-replay must not be
            # fenced — the reboot-brick fix). Deliberately NO marker: this is not a fence
            # outcome; the pre-READY window belongs to the live extension (the restarted
            # monitor's EXTEND_TIMEOUT_USEC path per §2.2), not to the fence.
            # KNOWN LOOP, no breaker in 5.1 (named honestly): if the restarted monitor fails
            # again before READY (identity still unreadable), OnFailure dispatches this fence
            # again → fence → restart-monitor → monitor fails → fence → …. Per-cycle bound =
            # the monitor's own start pacing (its unit start timeout / pre-READY extension
            # cadence), so the loop is LOUD (a page every cycle) and nothing is ever stopped
            # by it. The dispatch-dampening breaker is slice-5.2 MONITOR-side work,
            # deliberately not a fence-side counter here.
            _fence_page "identity unreadable but validator ACTIVE with startup-phase evidence — NOT stopping (§2.2 third branch); restarting monitor into pre-READY extension"
            _restart_monitor || _fence_page "monitor restart enqueue failed on the third branch — validator in startup, UNMONITORED; intervene"
            _fence_exit 0
        fi
        # Unreadable with NO positive startup evidence: fail toward stop (§2.2 — the verdict for
        # unreadable-with-no-startup-evidence remains stop).
        _stop_fallback "identity unreadable, no startup-phase evidence"
    fi
}

main "$@"
