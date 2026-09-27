#!/bin/bash
# failover-arm.sh (v0.7 Block 5.3) — the `failover arm` CEREMONY: the installer of the fence.
#
# SHIPPABLE, NOT EXECUTED HERE: this script is repo-tracked, in SHA256SUMS, shellcheck'd, and
# parse-gated — but its EXECUTION happens only at the v0.7 rollout (upgrade-then-arm, per host,
# release checklist). NOTHING in this repository runs it; its tests drive it with EVERY root
# below pointed at mktemp and every actuator stubbed (tests/test_arm_ceremony.sh).
#
# Structure (TASK-block53 / addendum §2.1-rev2.1, §2.3, §2.6):
#   preconditions → probe → install → verify → token
#   0. state directory (Block 6.3.1 D5): ARM_STATE_DIR — where the spare stores the pairing token
#      and the holder its config-generation counter — must be its own resolved path (the spare
#      daemon's R-SYM rule mirrored: a token whose directory is reached through a symlink never
#      proves); REFUSE[STATE-dir-spelling] / REFUSE[STATE-dir-symlink] / REFUSE[STATE-dir-missing] before
#      anything is created, written or installed (6.3.1 fix round 1: the spelling first, then the nearest
#      existing ancestor — a refused path is never left created on disk)
#   1. self v0.7 check (patsub guard in the installed daemons — the rev3.2 release condition,
#      self-enforced: the ceremony IS the upgrade-then-arm checkpoint)
#   2. socat present (§2.6: the SOLE armed transport in v0.7 — refuse, never fall back)
#   3. flock -w support probe (reviewer, 5.2 GO: busybox flock is DETECTED AT ARM and said
#      aloud, not discovered at the first dispatch — WARN, not refuse)
#   4. unit --identity verification (the 5.1 proc-gone residual, discharged HERE: the
#      fenced-demoted outcome's soundness rests on the validator unit's ExecStart carrying the
#      UNSTAKED identity — an invariant the fence cannot verify; the arm must)
#   5. one-arm-state alignment (§2.3: arm-state IS which fence unit is installed; DRY_RUN in
#      the env file decides WHICH unit this run installs, printed with the why)
#   probe: the §2.1-rev2.1 condition-1 end-to-end PROBE — a transient Type=notify pair rendered
#      into ARM_RUNTIME_DIR (tmpfs — ephemeral by construction), physically demonstrating
#      stopped-petting → watchdog fires → `failed` → OnFailure dispatches ON THIS HOST before
#      any armed state exists. The one READY pet that starts it IS the §2.6 socat self-test.
#   install: fence bodies into ARM_INSTALL_DIR (the ceremony is the ONLY placer), monitor unit
#      + exactly ONE fence unit rendered into ARM_SYSTEMD_DIR (page-only XOR real per DRY_RUN —
#      the stale sibling is removed: the arm is the alignment mechanism), daemon-reload,
#      RETIRE the legacy monitor unit(s) — stop + disable + VERIFY solana-failover.service /
#      solana-failover-standby.service, the units the legacy deploy wizards write and enable;
#      supersession is an ACTION this ceremony performs, never a plan — then enable the
#      monitor (the ONLY `systemctl enable` of a BLOCK-5 unit; no other script references the
#      Block-5 unit names).
#      The validator unit is NEVER started/restarted/stopped by this script.
#   verify: a _fence_unit_state-equivalent re-read must agree with the DRY_RUN intent
#      (render→verify, not render→hope).
#   token: bump the persisted config-generation counter and print the pairing token — the arm
#      REFUSES to complete without printing it (§2.1-rev2.1 condition 2: "re-pair every spare"
#      is ceremony, not advice; spare-side consumption is Block 6).
#
# Every precondition failure REFUSES with the exact fix printed (REFUSE[<gate>] + FIX: lines).
#
# bash 3.2-safe; same interpreter discipline as the daemons (no namerefs, no assoc arrays, no
# backslash continuation inside [[ ]]).

# bash 5.2+ patsub_replacement guard — the v0.6.10 alert-death class (see the daemons' header).
shopt -u patsub_replacement 2>/dev/null || true

# ── roots (env-overridable, EVERY path: the test seam AND the hard boundary — tests point all
#    of these at mktemp; the defaults below are the ONLY places the canonical paths appear) ─────
ARM_SYSTEMD_DIR="${ARM_SYSTEMD_DIR:-/etc/systemd/system}"
ARM_RUNTIME_DIR="${ARM_RUNTIME_DIR:-/run/systemd/system}"
ARM_INSTALL_DIR="${ARM_INSTALL_DIR:-/opt/solana-failover}"
FENCE_MARKER_DIR="${FENCE_MARKER_DIR:-/var/lib/solana-failover}"
ARM_STATE_DIR="${ARM_STATE_DIR:-/var/lib/solana-failover}"
ARM_PROBE_WAIT="${ARM_PROBE_WAIT:-15}"   # bounded marker wait, ~15 s per §2.1-rev2.1
case "$ARM_PROBE_WAIT" in ''|*[!0-9]*) ARM_PROBE_WAIT=15 ;; esac

# the release tree this ceremony runs from (skels + fence bodies sit beside this script)
_ARM_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKEL_DIR="$_ARM_SRC_DIR/systemd"

# unit names — the two canonical fence paths below ARM_SYSTEMD_DIR are byte-aligned with the
# daemons' [one-arm-state] FENCE_UNIT_REAL/FENCE_UNIT_PAGE_ONLY classifier paths (§2.3).
MONITOR_UNIT_NAME="solana-failover-monitor.service"
FENCE_UNIT_REAL_NAME="solana-failover-fence.service"
FENCE_UNIT_PAGE_NAME="solana-failover-fence-page-only.service"
PROBE_UNIT_NAME="solana-failover-arm-probe.service"
PROBE_FENCE_NAME="solana-failover-arm-probe-fence.service"
PROBE_MARKER=""            # set at probe time: $FENCE_MARKER_DIR/arm-probe.fired (name pinned
                           # by tests/test_arm_ceremony.sh's systemctl stub — change together)

_arm_log()  { printf '[failover-arm] %s\n' "$*"; }
_arm_warn() { printf '[failover-arm] WARN: %s\n' "$*"; }

_ARM_PROBE_RENDERED=""

# Refuse-to-arm: EVERY precondition/gate failure lands here — WHY + the exact FIX + exit 1.
# The first argument is a stable gate id (the suite's mutation controls neuter individual call
# sites by id — keep each call on one line).
_arm_refuse() {
    _arm_cleanup_probe
    printf '[failover-arm] REFUSE[%s]: %s\n' "$1" "$2"
    printf '[failover-arm] FIX: %s\n' "$3"
    printf '[failover-arm] NOT ARMED (exit 1).\n'
    exit 1
}

# ── validator process + unit discovery — BYTE-IDENTICAL to systemd/failover-fence.sh (asserted
#    by test_arm_ceremony (13): reuse, not reinvention; FENCE_PROC_ROOT is the same test seam) ──
_validator_pid() {
    local p; p=$(pgrep -x agave-validator 2>/dev/null | head -1)
    [[ -z "$p" && "$VALIDATOR_TYPE" == "frankendancer" ]] && p=$(pgrep -x fdctl 2>/dev/null | head -1)
    [[ -z "$p" ]] && p=$(pgrep -x solana-validator 2>/dev/null | head -1)
    printf '%s' "$p"
}

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

# ── role + env file (the ceremony arms ONE role per host) ───────────────────────────────────────
_arm_detect_role_env() {
    local _p="$ARM_INSTALL_DIR/failover.env" _s="$ARM_INSTALL_DIR/failover-standby.env"
    if [[ -n "${ARM_ROLE:-}" ]]; then
        case "$ARM_ROLE" in
            primary) ARM_ENV_BASE="failover.env" ;;
            standby) ARM_ENV_BASE="failover-standby.env" ;;
            *) _arm_refuse "ROLE-invalid" "ARM_ROLE='$ARM_ROLE' is neither 'primary' nor 'standby'" "set ARM_ROLE=primary or ARM_ROLE=standby (or unset it and let the installed env file decide), then re-run 'failover arm'" ;;
        esac
    elif [[ -f "$_p" && -f "$_s" ]]; then
        _arm_refuse "ROLE-ambiguous" "both $_p and $_s exist — the role cannot be inferred, and the monitor unit must name exactly one daemon" "set ARM_ROLE=primary or ARM_ROLE=standby explicitly, then re-run 'failover arm'"
    elif [[ -f "$_p" ]]; then ARM_ROLE="primary"; ARM_ENV_BASE="failover.env"
    elif [[ -f "$_s" ]]; then ARM_ROLE="standby"; ARM_ENV_BASE="failover-standby.env"
    else
        _arm_refuse "ENV-missing" "no env file found under $ARM_INSTALL_DIR (failover.env / failover-standby.env)" "install v0.7 first (deploy-failover.sh on a primary, deploy-failover-standby.sh on a standby — upgrade-then-arm, per host, no exceptions), then re-run 'failover arm'"
    fi
    ARM_ENV_FILE="$ARM_INSTALL_DIR/$ARM_ENV_BASE"
    [[ -f "$ARM_ENV_FILE" ]] || _arm_refuse "ENV-missing" "env file $ARM_ENV_FILE does not exist for role '$ARM_ROLE'" "install v0.7 first for this role (deploy-failover*.sh writes the env), then re-run 'failover arm'"
    [[ -f "$ARM_INSTALL_DIR/solana-${ARM_ROLE}-failover.sh" ]] || _arm_refuse "ROLE-daemon-missing" "role '$ARM_ROLE' but $ARM_INSTALL_DIR/solana-${ARM_ROLE}-failover.sh is not installed" "install v0.7 first for this role (deploy-failover*.sh places the daemon), then re-run 'failover arm'"
    # "$BASH" (the running interpreter's own path), not bare `bash`: the deploy-image class
    # where no `bash` sits on the minimal PATH (the bash:5.2 CI image has no /bin/bash —
    # found red on the Linux leg, exactly like the fence suite's BASH_BIN note).
    "${BASH:-bash}" -n "$ARM_ENV_FILE" 2>/dev/null || _arm_refuse "ENV-syntax" "$ARM_ENV_FILE does not parse (bash -n failed)" "fix the env file's syntax (bash -n $ARM_ENV_FILE shows the line), then re-run 'failover arm'"
    # Source the env (DRY_RUN, VALIDATOR_TYPE, UNSTAKED_KEYPAIR, VALIDATOR_UNIT, the timing
    # claims for the token). The ARM_* roots are the ceremony's own seam — snapshot and restore
    # them so an env file can never re-point where this run writes.
    local _r1="$ARM_SYSTEMD_DIR" _r2="$ARM_RUNTIME_DIR" _r3="$ARM_INSTALL_DIR" _r4="$FENCE_MARKER_DIR" _r5="$ARM_STATE_DIR" _r6="$ARM_PROBE_WAIT"
    # shellcheck disable=SC1090
    . "$ARM_ENV_FILE"
    ARM_SYSTEMD_DIR="$_r1"; ARM_RUNTIME_DIR="$_r2"; ARM_INSTALL_DIR="$_r3"; FENCE_MARKER_DIR="$_r4"; ARM_STATE_DIR="$_r5"; ARM_PROBE_WAIT="$_r6"
    VALIDATOR_TYPE="${VALIDATOR_TYPE:-agave}"
    # token inputs (the standby env carries these; the daemons' shipped defaults otherwise)
    EXPECTED_PRIMARY_SELF_FENCE_SECS="${EXPECTED_PRIMARY_SELF_FENCE_SECS:-30}"
    case "$EXPECTED_PRIMARY_SELF_FENCE_SECS" in ''|*[!0-9]*) EXPECTED_PRIMARY_SELF_FENCE_SECS=30 ;; esac
    SELF_FENCE_MARGIN_SECS="${SELF_FENCE_MARGIN_SECS:-30}"
    case "$SELF_FENCE_MARGIN_SECS" in ''|*[!0-9]*) SELF_FENCE_MARGIN_SECS=30 ;; esac
    # §2.3 intent: DRY_RUN=false → REAL; anything else (true, unset, garbage) → PAGE-ONLY —
    # ambiguity fails toward inert, announced in precondition 5.
    if [[ "${DRY_RUN:-}" == "false" ]]; then ARM_INTENT="real"; else ARM_INTENT="page-only"; fi
    _arm_log "role: $ARM_ROLE (env: $ARM_ENV_FILE)"
}

# ── precondition 0: the state directory is its own resolved path (Block 6.3.1 D5) ───────────────
# The spare daemon's R-SYM rule (6.3 fix round 5), MIRRORED at the arm: a pairing token whose
# directory is reached through a symlink never proves on the spare — watchdog-elapsed keys the token
# file's identity, and a DIRECTORY re-pointed away and back leaves that file untouched, so the daemon
# refuses to count any silence under it (_elapsed_tok_ident / _elapsed_tok_symlink_why). The arm
# therefore REFUSES to write into (spare: pairing-token; holder: arm-generation) a state directory
# that does not canonicalize to itself — the daemon's exact test: `cd -P` + `pwd -P` of ARM_STATE_DIR
# must equal ARM_STATE_DIR as configured (a symlink anywhere on the path, or any spelling that is not
# the resolved path: a trailing '/', an internal '//', '.', '..', a relative path; a LEADING '//' is
# kept by pwd -P as its own root and passes, as in the daemon). Every refusal comes BEFORE anything is
# created (6.3.1 fix round 1, R7 — the panel's CC-7: the check used to mkdir -p first, so a refused
# spelling or a path under a symlinked ancestor was left CREATED on disk; measured, 'rel/state' and a
# trailing '/' both refused as "symlink" with dir_created=yes):
#   (a) the SPELLING, lexically, with no filesystem access — absolute, no trailing '/', no '//' past a
#       leading one, no '.' or '..' component → REFUSE[STATE-dir-spelling] (its own code: nothing on the
#       filesystem is wrong, the value is);
#   (b) the NEAREST EXISTING ancestor (the directory itself when it exists), canonicalized with the
#       daemon's `cd -P` + `pwd -P`: a symlink on that existing prefix → REFUSE[STATE-dir-symlink]; an
#       existing component that cannot be entered as a directory (a FILE, no permission) →
#       REFUSE[STATE-dir-missing];
#   (c) only then the missing tail is created (mkdir -p — what P3/P5/the token already did) and the WHOLE
#       path is re-checked with the daemon's exact line (a race that swaps a symlink in between is still
#       refused, as before; (16g) asserts the line is the daemon's, character for character).
# Runs before P3 (the first write into the directory). NOT closed (named in docs/SAFETY.md's threat
# model): a local root that RENAME-swaps the directory's contents away and back between two daemon steps.
_state_dir_spelling_ok() {   # $1 = a path; 0 iff it is spelled as `pwd -P` prints a directory with no symlink on its path
    local _p="$1" _b
    case "$_p" in /*) ;; *) return 1 ;; esac        # relative
    [[ "$_p" == "/" || "$_p" == "//" ]] && return 0
    _b="${_p#/}"; [[ "$_b" == /* ]] && _b="${_b#/}"  # one extra leading '/' — a leading '//' is its own root to pwd -P (Linux), as in the daemon
    case "$_b" in /*|*/|*//*) return 1 ;; esac       # three or more leading '/', a trailing '/', an internal '//'
    case "/$_b/" in */./*|*/../*) return 1 ;; esac   # a '.' or '..' component
    return 0
}
_pre_state_dir_check() {
    local _sd_p _anc="$ARM_STATE_DIR" _tail="" _anc_p _cand
    # (a) the spelling — before any filesystem access
    if ! _state_dir_spelling_ok "$ARM_STATE_DIR"; then
        _arm_refuse "STATE-dir-spelling" "ARM_STATE_DIR=$ARM_STATE_DIR is not spelled as a resolved path (a relative path, a trailing '/', an internal '//', or a '.'/'..' component) — the spare daemon compares PROOF_STATE_DIR with its own \`pwd -P\` spelling, and a pairing token stored under any other spelling NEVER proves (the daemon's R-SYM rule); nothing was created" "spell ARM_STATE_DIR as the directory's absolute resolved path (e.g. ARM_STATE_DIR=/var/lib/solana-failover — no trailing '/', no '//', '.' or '..'), set the spare daemon's PROOF_STATE_DIR to the same value, then re-run 'failover arm'"
    fi
    # (b) the nearest existing ancestor (a dangling symlink counts as existing — it IS a symlink on the path)
    while [[ ! -e "$_anc" && ! -L "$_anc" ]]; do
        _tail="/${_anc##*/}$_tail"; _anc="${_anc%/*}"
        [[ -z "$_anc" ]] && _anc="/"
    done
    # a leading '//' is its own root to pwd -P on Linux (the daemon keeps it) — a walk that reached the root keeps it too
    [[ "$_anc" == "/" && "$ARM_STATE_DIR" == //* && "$ARM_STATE_DIR" != ///* ]] && _anc="//"
    if [[ -L "$_anc" && ! -e "$_anc" ]]; then
        _arm_refuse "STATE-dir-symlink" "ARM_STATE_DIR=$ARM_STATE_DIR is reached through a dangling symlink ($_anc) — a pairing token stored through a symlink NEVER proves on the spare (the daemon's R-SYM rule); nothing was created" "replace the symlink $_anc with a real directory (BY HAND) or point ARM_STATE_DIR at a real path, set the spare daemon's PROOF_STATE_DIR to the same value, then re-run 'failover arm'"
    fi
    _anc_p=$(CDPATH='' cd -P -- "$_anc" 2>/dev/null && pwd -P)
    if [[ -z "$_anc_p" ]]; then
        _arm_refuse "STATE-dir-missing" "ARM_STATE_DIR=$ARM_STATE_DIR cannot be created or entered as a directory ($_anc exists but cannot be entered as one) — the pairing token (spare) and the config-generation counter (holder) are stored there; nothing was created" "make $ARM_STATE_DIR a real, writable directory (remove whatever non-directory sits at that path BY HAND, then: mkdir -p $ARM_STATE_DIR), then re-run 'failover arm'"
    fi
    if [[ -z "$_tail" ]]; then _cand="$_anc_p"; else _cand="${_anc_p%/}$_tail"; fi
    if [[ "$_cand" != "$ARM_STATE_DIR" ]]; then
        _arm_refuse "STATE-dir-symlink" "ARM_STATE_DIR=$ARM_STATE_DIR is not its own resolved path (it resolves to $_cand: a symlink on the path) — a pairing token stored through it NEVER proves on the spare (the daemon's R-SYM rule: a directory re-pointed away and back is invisible to the token file's identity, so watchdog-elapsed counts no silence under it); nothing was created" "point ARM_STATE_DIR at the resolved path — ARM_STATE_DIR=$_cand — and set the spare daemon's PROOF_STATE_DIR to the same value (or replace the symlink with a real directory at $ARM_STATE_DIR), then re-run 'failover arm'"
    fi
    # (c) create the missing tail, then the daemon's exact check on the whole path
    mkdir -p "$ARM_STATE_DIR" 2>/dev/null
    _sd_p=$(CDPATH='' cd -P -- "$ARM_STATE_DIR" 2>/dev/null && pwd -P)
    if [[ -z "$_sd_p" ]]; then
        _arm_refuse "STATE-dir-missing" "ARM_STATE_DIR=$ARM_STATE_DIR cannot be created or entered as a directory — the pairing token (spare) and the config-generation counter (holder) are stored there" "make $ARM_STATE_DIR a real, writable directory (remove whatever non-directory sits at that path BY HAND, then: mkdir -p $ARM_STATE_DIR), then re-run 'failover arm'"
    fi
    if [[ "$_sd_p" != "$ARM_STATE_DIR" ]]; then
        _arm_refuse "STATE-dir-symlink" "ARM_STATE_DIR=$ARM_STATE_DIR is not its own resolved path (it resolves to $_sd_p: a symlink on the path, or a spelling that is not the resolved path — a trailing '/', '//', '.', '..', a relative path) — a pairing token stored through it NEVER proves on the spare (the daemon's R-SYM rule: a directory re-pointed away and back is invisible to the token file's identity, so watchdog-elapsed counts no silence under it)" "point ARM_STATE_DIR at the resolved path — ARM_STATE_DIR=$_sd_p — and set the spare daemon's PROOF_STATE_DIR to the same value (or replace the symlink with a real directory at $ARM_STATE_DIR), then re-run 'failover arm'"
    fi
    _arm_log "precondition 0 OK: the state directory $ARM_STATE_DIR is its own resolved path (the daemon's R-SYM rule — a pairing token stored here can prove)"
}

# ── precondition 1: self v0.7 check (rev3.2 release condition, self-enforced at arm) ────────────
# TWO gates per installed daemon, each with its own refusal (5.3 panel fix round):
#   (a) the patsub guard — scoped to what it proves: PAGES survive bash 5.2 (the v0.6.10
#       alert-death class). It does NOT prove the daemon can drive the armed monitor unit.
#   (b) WATCHDOG CAPABILITY — the [watchdog] block's load-bearing markers. The trap this
#       closes is exactly v0.6.10: guard present but no watchdog capability = a pre-v0.7
#       daemon; the monitor unit would never go READY and the fence would fire on a HEALTHY
#       validator (Type=notify start times out → `failed` → OnFailure → the REAL fence). The
#       §2.1-rev2.1 probe cannot catch it: the probe pair is transient with a hardcoded socat
#       pet — it proves the HOST wiring, never the installed daemon's behavior.
# Both greps run COMMENT-STRIPPED: a guard or capability that lives only in a comment is not
# code (the panel's A1 daemon). Gated at: the _watchdog_active() definition present AND ≥1
# READY=1 line AND ≥10 _watchdog_pet lines. The refusal prints the failing daemon's MEASURED
# counts against these REQUIRED floors — no static shipped-daemon figures anywhere in the text
# (fix round 2 nit: such figures drift, and the same daemons count differently under different
# comment-stripping conventions; the gate's own measurement is the only number worth printing).
_pre_v07_check() {
    local _found=0 _d _code _ready _pets _def
    for _d in "$ARM_INSTALL_DIR/solana-primary-failover.sh" "$ARM_INSTALL_DIR/solana-standby-failover.sh"; do
        [[ -f "$_d" ]] || continue
        _found=1
        _code=$(grep -v '^[[:space:]]*#' "$_d" 2>/dev/null)
        if ! printf '%s\n' "$_code" | grep -q 'shopt -u patsub'; then
            _arm_refuse "P1-patsub" "installed daemon $_d lacks the bash-5.2 patsub_replacement guard (outside comments) — this host is not even on v0.6.10 (pre-v0.6.10 daemons on bash 5.2 silently fail to deliver CRITICAL pages: the alert-death class, and the fence's semantics is 'does not act, loudly')" "upgrade this host to v0.7 FIRST (re-run the v0.7 deploy for this role), then re-run 'failover arm' — the release order is upgrade-then-arm, per host, no exceptions (rev3.2 release condition; the ceremony IS the checkpoint)"
        fi
        _ready=$(printf '%s\n' "$_code" | grep -c 'READY=1')
        _pets=$(printf '%s\n' "$_code" | grep -c '_watchdog_pet')
        _def=$(printf '%s\n' "$_code" | grep -c '_watchdog_active()')
        if [[ "$_def" -lt 1 || "$_ready" -lt 1 || "$_pets" -lt 10 ]]; then
            _arm_refuse "P1-capability" "installed daemon $_d carries the patsub guard but NOT the v0.7 watchdog capability — MEASURED (this daemon, outside comments): _watchdog_active() definitions: $_def, READY=1 lines: $_ready, _watchdog_pet lines: $_pets; REQUIRED: ≥1, ≥1, ≥10. Guard present but no watchdog capability = a pre-v0.7 daemon (v0.6.10 is exactly this): the armed monitor unit would never go READY → start timeout → terminal failed → the REAL fence fires on a HEALTHY validator — and the probe cannot catch it (transient units, hardcoded pet)" "upgrade this host to v0.7 FIRST (re-run the v0.7 deploy for this role), then re-run 'failover arm' — upgrade-then-arm, per host, no exceptions (the ceremony IS the checkpoint)"
        fi
    done
    if [[ $_found -eq 0 ]]; then
        _arm_refuse "P1-none-installed" "no failover daemon is installed under $ARM_INSTALL_DIR" "install v0.7 first (deploy-failover.sh / deploy-failover-standby.sh), then re-run 'failover arm' — upgrade-then-arm, per host, no exceptions"
    fi
    _arm_log "precondition 1 OK: installed daemon(s) carry the patsub guard (pages survive bash 5.2) AND the v0.7 watchdog capability (_watchdog_active + READY=1 + ≥10 pet sites: the armed monitor can go READY and keep petting) — v0.7 is on this host (upgrade-then-arm holds)"
}

# ── precondition 2: socat (§2.6 — the SOLE armed transport in v0.7; NO fallback) ────────────────
_pre_socat_check() {
    if ! command -v socat >/dev/null 2>&1; then
        _arm_refuse "P2-socat" "socat not found — socat unit-datagrams to \$NOTIFY_SOCKET are the SOLE armed transport in v0.7 (§2.6); there is deliberately NO fallback in armed mode (systemd-notify is monitoring-only below systemd 257: the attribution race)" "install it now:  apt-get update && apt-get install -y socat   — then re-run 'failover arm'"
    fi
    _arm_log "precondition 2 OK: socat present (the sole armed transport, §2.6)"
}

# ── precondition 3: flock -w support (reviewer, 5.2 GO: detect busybox flock AT ARM and say it
#    aloud — the fence's instance lock uses `flock -w`, and busybox flock errors on -w, sending
#    every dispatch down the loud lockless exit-1 path). WARN LOUDLY, do not refuse. ────────────
_pre_flock_check() {
    if ! command -v flock >/dev/null 2>&1; then
        _arm_warn "flock not found on this host: every fence dispatch will run with NO instance lock (the fence skips locking when flock is absent) — real validator hosts carry util-linux; consider installing it."
        return 0
    fi
    mkdir -p "$ARM_STATE_DIR" 2>/dev/null
    if ( exec 9>"$ARM_STATE_DIR/.arm-flock-probe" && flock -w 0 9 ) 2>/dev/null; then
        _arm_log "precondition 3 OK: flock supports -w (util-linux) — the fence's bounded-wait instance lock works here"
    else
        _arm_warn "flock has no -w on this host (busybox?): every fence dispatch will take the loud lockless exit-1 path — real validator hosts carry util-linux; consider installing it."
    fi
    rm -f "$ARM_STATE_DIR/.arm-flock-probe" 2>/dev/null
    return 0
}

# fold systemd unit backslash-continuation lines into single lines (portable awk — the real
# agave units ship multi-line ExecStart)
_fold_execstart() { awk '{ if (sub(/\\$/, "")) { printf "%s", $0 } else { print } }'; }

# ── precondition 4: unit --identity verification (the 5.1 proc-gone residual, discharged) ───────
# The fenced-demoted outcome is sound ONLY if the validator unit's ExecStart carries
# --identity <UNSTAKED keypair>: fence-issued set-identity can make the process exit, and under
# Restart=always the unit returns the validator on WHATEVER identity its --identity names — an
# invariant the fence cannot verify at dispatch time (its marker text names this). The ARM
# verifies BOTH (5.3 panel fix round, A8):
#   1. the PATH: the unit's --identity names the configured UNSTAKED_KEYPAIR string, and
#   2. the KEY: the file actually AT that path (readlink-resolved) derives — via the host's
#      own keygen — the pubkey the env declares as UNSTAKED_PUBKEY. A symlink or mis-copied
#      file at the right path with the STAKED key inside passes 1 and IS the double-sign P4
#      exists to prevent; only 2 catches it.
# Verdicts: PROVEN WRONG (path or key mismatch) → refuse the REAL arm, no override exists.
# UNVERIFIABLE (keygen missing, pubkey underivable, UNSTAKED_PUBKEY unset) → refuse the REAL
# arm too, with the manual verification command printed and one documented dangerous override:
# ARM_ACCEPT_UNVERIFIED_IDENTITY=1 (arms with a LOUD WARN naming exactly what was NOT
# verified). Page-only arm needs none of this — WARN + proceed, unchanged.
_pre_identity_check() {
    local reason="" unver="" unit="" unit_text execline got nid resolved pub kg
    if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
        _arm_warn "VALIDATOR_TYPE=frankendancer — v0.7 fencing is STOP-ONLY on this box (no fd demote rung; this check is agave-form): skipping the unit --identity verification, because the fenced-demoted outcome it protects does not exist here (every real-fence dispatch takes the stop path — see systemd/README.md). Arming this box means accepting stop-only fencing."
        return 0
    fi
    if ! unit=$(_detect_validator_unit); then
        reason="cannot locate the validator unit (no VALIDATOR_UNIT configured and none detectable from a running validator's cgroup)"
    else
        unit_text=$(timeout -k 5 10 systemctl cat "$unit" 2>/dev/null)
        if [[ -z "$unit_text" ]]; then
            reason="systemctl cat $unit returned nothing — cannot read the unit file"
        else
            execline=$(printf '%s\n' "$unit_text" | _fold_execstart | grep '^ExecStart=' | tail -1)
            # agave CLI semantics: with the flag repeated, the LAST --identity wins — the greedy
            # `.*` anchors the extraction to the LAST occurrence, deliberately matching that.
            got=$(printf '%s\n' "$execline" | sed -n 's/.*--identity[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')
            nid=$(printf '%s\n' "$execline" | grep -o -- '--identity' | grep -c .)
            [[ "$nid" -gt 1 ]] && _arm_log "note: unit $unit ExecStart carries multiple --identity flags ($nid) — the LAST one governs (agave CLI semantics) and is the one verified here"
            if [[ -z "$execline" ]]; then
                reason="unit $unit has no ExecStart line readable via systemctl cat"
            elif [[ -z "$got" ]]; then
                reason="unit $unit ExecStart carries NO --identity argument (if it launches a wrapper script, the arm cannot see inside it — v0.7 verifies the agave form only)"
            elif [[ -z "${UNSTAKED_KEYPAIR:-}" ]]; then
                reason="UNSTAKED_KEYPAIR is not set in $ARM_ENV_FILE — nothing to verify --identity against"
            elif [[ "$got" != "$UNSTAKED_KEYPAIR" ]]; then
                reason="unit $unit ExecStart --identity is '$got', NOT the configured UNSTAKED keypair '$UNSTAKED_KEYPAIR'"
            else
                # the PATH matches — now verify the KEY behind it (A8: symlink/mis-copy)
                resolved=$(readlink -f "$got" 2>/dev/null); [[ -z "$resolved" ]] && resolved="$got"
                pub=""
                for kg in solana-keygen agave-keygen; do
                    if [[ -n "${SOLANA_PATH:-}" && -x "$SOLANA_PATH/$kg" ]]; then
                        pub=$(timeout -k 5 10 "$SOLANA_PATH/$kg" pubkey "$resolved" 2>/dev/null)
                        [[ -n "$pub" ]] && break
                    fi
                done
                if [[ -z "$pub" ]]; then
                    unver="cannot derive the pubkey of the key file at '$got' (resolved: '$resolved') — no runnable solana-keygen/agave-keygen under SOLANA_PATH='${SOLANA_PATH:-unset}', or the derivation failed"
                elif [[ -z "${UNSTAKED_PUBKEY:-}" ]]; then
                    unver="UNSTAKED_PUBKEY is not set in $ARM_ENV_FILE — the key file derives pubkey '$pub' but there is no declared UNSTAKED pubkey to verify it against"
                elif [[ "$pub" != "$UNSTAKED_PUBKEY" ]]; then
                    reason="the KEY at '$got' (resolved: '$resolved') derives pubkey '$pub', NOT the env's UNSTAKED_PUBKEY '$UNSTAKED_PUBKEY' — the path string matches but its CONTENT is a different key (a symlink or mis-copied file: the exact double-sign P4 exists to prevent)"
                fi
            fi
        fi
    fi
    if [[ -z "$reason" && -z "$unver" ]]; then
        _arm_log "precondition 4 OK: unit ${unit} ExecStart --identity == the configured UNSTAKED keypair ($UNSTAKED_KEYPAIR) AND the key file behind it (resolved: $resolved) derives the declared UNSTAKED_PUBKEY ($UNSTAKED_PUBKEY) — path AND key verified: the fenced-demoted outcome is sound (verified at arm since 5.3; the fence cannot verify this at dispatch)"
        return 0
    fi
    if [[ -n "$reason" ]]; then
        # PROVEN WRONG — no override covers this branch, deliberately.
        if [[ "$ARM_INTENT" == "real" ]]; then
            _arm_refuse "P4-identity" "unit --identity verification FAILED: $reason. Arming the REAL fence would be UNSOUND: after a fence demote with the process gone, Restart=always returns the validator on whatever identity the unit's --identity names (the 5.1 proc-gone residual — the fence cannot verify this invariant; the arm must)" "make the validator unit's ExecStart start the validator with --identity ${UNSTAKED_KEYPAIR:-<set UNSTAKED_KEYPAIR in $ARM_ENV_FILE first>} (the UNSTAKED keypair, verified as a real file holding the UNSTAKED key), run systemctl daemon-reload, then re-run 'failover arm'"
        fi
        _arm_warn "unit --identity verification FAILED: $reason. PAGE-ONLY arm proceeds (nothing on the page-only dispatch path can demote or stop a validator) — but FIX THIS before arming the REAL fence (DRY_RUN=false)."
        return 0
    fi
    # UNVERIFIABLE — refusable with a documented dangerous override (never for PROVEN WRONG).
    if [[ "$ARM_INTENT" == "real" ]]; then
        if [[ "${ARM_ACCEPT_UNVERIFIED_IDENTITY:-}" == "1" ]]; then
            _arm_warn "DANGEROUS: ARM_ACCEPT_UNVERIFIED_IDENTITY=1 — proceeding although the unit's --identity KEY was NOT verified ($unver). Only the PATH STRING was verified. If the file behind it holds the STAKED key, a fence demote followed by Restart=always brings the validator back STAKED — the double-sign P4 exists to prevent. Verify by hand: ${SOLANA_PATH:-<SOLANA_PATH>}/solana-keygen pubkey $got"
            return 0
        fi
        _arm_refuse "P4-unverifiable" "unit --identity KEY verification is UNVERIFIABLE on this host: $unver. The path string matched, but P4's soundness claim is about the KEY the unit restarts on — unverified is refused, not assumed (claims never exceed checks)" "verify by hand: run  ${SOLANA_PATH:-<SOLANA_PATH>}/solana-keygen pubkey ${got:-$UNSTAKED_KEYPAIR}  and set UNSTAKED_PUBKEY=<that pubkey> in $ARM_ENV_FILE, then re-run 'failover arm'. If this host genuinely cannot derive pubkeys, the DANGEROUS documented override is: ARM_ACCEPT_UNVERIFIED_IDENTITY=1 failover arm — it arms with the KEY unverified and says so loudly"
    fi
    _arm_warn "unit --identity KEY verification unavailable: $unver. PAGE-ONLY arm proceeds (nothing on the page-only dispatch path can demote or stop a validator; no override needed) — but make it verifiable before arming the REAL fence (DRY_RUN=false)."
    return 0
}

# ── precondition 5: one-arm-state alignment announcement (§2.3 [rev3/№1]) ───────────────────────
_announce_arm_state() {
    if [[ "$ARM_INTENT" == "real" ]]; then
        _arm_log "precondition 5: DRY_RUN=false → the REAL fence unit ($FENCE_UNIT_REAL_NAME) will be installed. Why: arm-state IS which fence unit is installed (§2.3 — structural, never an env flag); re-running 'failover arm' after flipping DRY_RUN re-aligns the two states — the №1 startup refusal's designed resolution path."
    else
        if [[ "${DRY_RUN:-}" != "true" ]]; then
            _arm_warn "DRY_RUN='${DRY_RUN:-unset}' is neither 'true' nor 'false' — ambiguity fails toward inert (§2.3): treating as page-only."
        fi
        _arm_log "precondition 5: DRY_RUN=${DRY_RUN:-unset} → the PAGE-ONLY fence unit ($FENCE_UNIT_PAGE_NAME) will be installed. Why: arm-state IS which fence unit is installed (§2.3 — structural, never an env flag); re-running 'failover arm' after flipping DRY_RUN re-aligns the two states — the №1 startup refusal's designed resolution path."
    fi
}

# ── precondition P5: pairing-token intake + zero-stake verification at the SPARE arm ────────────
# v0.7 (Block 6.1, BLOCK6-PLAN §1): the operator hands THIS spare the holder's pairing token
# line via ARM_PAIRING_TOKEN (env — ceremony-friendly and testable; the holder's arm prints the
# line as its last act, see _arm_token). NUMBERING NOTE: the §2.3 alignment announcement above
# kept its historical "precondition 5" label; THIS gate is P5 per BLOCK6-PLAN §1 (refusal ids
# REFUSE[P5-*]) — do not renumber either.
# ROLE SCOPE, derived from the ceremony's own role detection (not guesswork): intake runs on
# ARM_ROLE=standby (the spare posture — the daemon that consumes the token); a primary-role arm
# GENERATES tokens (_arm_token) and never consumes one — a stray ARM_PAIRING_TOKEN there is
# announced and ignored, never a silent default. The zero-stake verification (§2.4 G2 arm
# condition, deferred from 5.4) scopes on the ENV: it runs for EACH space-separated entry of
# PRIMARY_UNSTAKED_PUBKEY (the spare's G2/fast-path holder-key inputs; empty = nothing to
# verify, announced — N-is-all over the list).
# COST MODEL (Block 6, binding): the worst outcome is DOUBLE-SIGN — every ambiguity below fails
# toward REFUSING to arm; cannot-verify at CEREMONY time is a refusal with the manual command
# printed, never a shrug (this inverts nothing here: an arm refusal costs a re-run, not a vote).

# crc helper — BYTE-PARITY with the daemons' [proof-gate] copy (test_proof_gate cmp's all three
# files): the 5.3 token emission's exact crc mechanics (`cksum | awk`; INTEGRITY against
# copy/paste truncation, NOT security — anyone can recompute it). _arm_token below emits
# THROUGH this same helper, so intake and emission cannot drift (the S-1 twin class).
_pairing_crc() { printf '%s' "$1" | cksum 2>/dev/null | awk '{print $1}'; }
# one k=v field from the |-separated token line (the house `field` idiom)
_pairing_field() { printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

# PAIRING_BOUND_MAX — the intake ceiling on BOTH token bounds (watchdog W and relinquish_bound B),
# in seconds. REVIEWER-TUNABLE. Derivation: a WatchdogSec or a holder relinquish bound beyond ONE
# HOUR is definitionally not a fast self-fence (the whole G2/elapsed premise is a tight fence
# measured in tens of seconds), so a value above it is a corrupted or forged token, not a real
# pairing. 3600 also sits ~15 orders of magnitude below the 2^63 signed-int wrap, so once BOTH W
# and B are held in [1, PAIRING_BOUND_MAX] the daemon's elapsed_floor = W+B+MARGIN_ELAPSED cannot
# overflow (worst case ~7210) — overflow is STRUCTURALLY impossible here, not merely unlikely. The
# daemon still keeps an independent convergence backstop at its derivation site (defense in depth:
# a token planted straight on disk or fed from a future env source bypasses THIS gate).
PAIRING_BOUND_MAX=3600

_ARM_PAIR_SUMMARY=""   # set by _pre_pairing_intake; _arm_pairing_summary prints it at the end
_ARM_G2_SHARED=""      # set by _pre_g2_tier_overlap (C1): the MEASURED vantage/tier overlap list ("" = none); _arm_g2_summary re-states it at the end

_pre_pairing_intake() {
    local tokf="$ARM_STATE_DIR/pairing-token" tok src="" crc payload gen w b fence thost tmp delay shape_ok=1 _p5_margin _p5_floor
    if [[ "$ARM_ROLE" != "standby" ]]; then
        [[ -n "${ARM_PAIRING_TOKEN:-}" ]] && _arm_warn "ARM_PAIRING_TOKEN is set on a '${ARM_ROLE}' arm — IGNORED: the holder GENERATES pairing tokens (this ceremony prints one below); only a spare (standby-role) arm consumes one (Block 6.1 P5)."
        return 0
    fi
    tok="${ARM_PAIRING_TOKEN:-}"
    if [[ -n "$tok" ]]; then
        src="ARM_PAIRING_TOKEN (handed this run)"
    elif [[ -f "$tokf" ]]; then
        tok=$(head -1 "$tokf" 2>/dev/null)
        src="stored at $tokf (a previous pairing — re-validated at every arm, §2.1 condition 3)"
    fi
    if [[ -z "$tok" ]]; then
        _ARM_PAIR_SUMMARY="unpaired"
        _arm_log "precondition P5: NO pairing token (ARM_PAIRING_TOKEN unset; nothing stored at $tokf) — the arm PROCEEDS; the ARMED daemon runs the §2.7 UNPAIRED posture (proof providers: verified-demote ONLY where G2 is configured — PRIMARY_UNSTAKED_PUBKEY set — else NONE, the page prints the measured registry; silence-based take disabled; CRITICAL page at every daemon start). See the end-of-summary warning."
        _pre_zero_stake_verify
        return 0
    fi
    # shape + crc — the 5.3 emission's exact shape (never changed silently; the grep-consumers
    # rule): v0.7|gen=<N>|watchdog=<W>|relinquish_bound=<B>|fence=<real|page-only>|host=<H>|<crc>
    case "$tok" in "v0.7|gen="*) : ;; *) shape_ok=0 ;; esac
    crc="${tok##*|}"; payload="${tok%|*}"
    case "$crc" in ''|*[!0-9]*) shape_ok=0 ;; esac
    if [[ $shape_ok -eq 1 && "$(_pairing_crc "$payload")" != "$crc" ]]; then shape_ok=0; fi
    gen=""; w=""; b=""; fence=""; thost=""
    if [[ $shape_ok -eq 1 ]]; then
        gen=$(_pairing_field "$tok" gen); w=$(_pairing_field "$tok" watchdog)
        b=$(_pairing_field "$tok" relinquish_bound); fence=$(_pairing_field "$tok" fence)
        thost=$(_pairing_field "$tok" host)
        case "$gen" in ''|*[!0-9]*) shape_ok=0 ;; esac
        case "$w"   in ''|*[!0-9]*) shape_ok=0 ;; esac
        case "$b"   in ''|*[!0-9]*) shape_ok=0 ;; esac
        case "$fence" in real|page-only) : ;; *) shape_ok=0 ;; esac
        [[ -n "$thost" ]] || shape_ok=0
    fi
    if [[ $shape_ok -ne 1 ]]; then
        case "$src" in
            "ARM_PAIRING_TOKEN"*)
                _arm_refuse "P5-token-crc" "the handed pairing token fails crc/shape verification (token: '$tok') — a truncated or hand-edited copy/paste is the usual cause; the crc is cksum over the payload before the last field (INTEGRITY, not security)" "re-copy the FULL token line from the holder's 'failover arm' output (one line, seven |-fields ending in the numeric crc) into ARM_PAIRING_TOKEN and re-run this arm; if the holder's output is lost, re-run 'failover arm' on the holder (it refuses to complete without printing a fresh token) and pair with THAT line"
            ;;
            *)
                # a rotted STORED token with no fresh one handed: proceed UNPAIRED, loudly —
                # the file is left in place (the armed daemon's classifier reads it invalid and
                # screams the same §2.7 posture; deleting operator evidence is not this gate's job).
                _ARM_PAIR_SUMMARY="stored-invalid"
                _arm_warn "precondition P5: the STORED pairing token at $tokf fails crc/shape re-validation (disk rot or a hand edit) — treating this spare as UNPAIRED (file left in place; the ARMED daemon classifies it invalid and pages the §2.7 posture at every start). Re-pair: copy the holder's token line into ARM_PAIRING_TOKEN and re-run this arm."
                _pre_zero_stake_verify
                return 0
            ;;
        esac
    fi
    gen=$((10#$gen)); w=$((10#$w)); b=$((10#$b))   # octal-safe normalization (the F6 idiom)
    # bounds ceiling + zero-floor (Block 6.1, panel L-1) — the double-sign refusal, mirrored onto
    # W: watchdog(W) and relinquish_bound(B) must EACH sit in [1, PAIRING_BOUND_MAX]. The intake's
    # only prior numeric gate was B-vs-delay; W was unbounded, and elapsed_floor = W+B+MARGIN wraps
    # past 2^63 for a huge W — a forged/degenerate token then derives a NEGATIVE floor the 6.3
    # predicate reads as "any silence proves relinquish" (the exact double-sign), while a 0 bound
    # derives a floor a spare clears with ZERO proven silence. Bounding BOTH here makes the wrap
    # structurally impossible (PAIRING_BOUND_MAX) AND excludes the zero floor. Reuse the P5-bound id
    # (same class); a rejected token is an INVALID pairing (REFUSE), never stored as PAIRED.
    if [[ $w -lt 1 || $w -gt $PAIRING_BOUND_MAX ]]; then
        _arm_refuse "P5-bound" "token watchdog is out of range — MEASURED: watchdog=${w}s; REQUIRED: 1 <= watchdog <= ${PAIRING_BOUND_MAX}s (PAIRING_BOUND_MAX). A watchdog of 0 or above an hour is not a fast self-fence: the spare's silence-based elapsed floor derives from watchdog + relinquish_bound, so an out-of-range watchdog yields an UNSOUND floor (0 → a floor cleared with no proven silence; huge → arithmetic overflow to a negative/non-converging floor). This is a corrupted or forged token, not a valid pairing. No override exists for this refusal" "re-arm the HOLDER (its WatchdogSec is read from the installed monitor unit at arm time) and re-pair this spare with the FRESH token it prints; if the line was hand-edited or truncated, re-copy the full token line"
    fi
    if [[ $b -lt 1 || $b -gt $PAIRING_BOUND_MAX ]]; then
        _arm_refuse "P5-bound" "token relinquish_bound is out of range — MEASURED: relinquish_bound=${b}s; REQUIRED: 1 <= relinquish_bound <= ${PAIRING_BOUND_MAX}s (PAIRING_BOUND_MAX). A relinquish_bound of 0 or above an hour is not a fast fence: the spare's elapsed floor derives from watchdog + relinquish_bound, so an out-of-range bound yields an UNSOUND floor (0 → no proven-silence floor; huge → a non-converging/overflowing floor). Corrupted or forged token, not a valid pairing. No override exists for this refusal" "re-arm the HOLDER with a sane EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS (their sum is this bound) and re-pair this spare with the FRESH token; if the line was hand-edited or truncated, re-copy the full token line"
    fi
    # bound-vs-delay consistency — the double-sign refusal; NO override exists, deliberately:
    # a spare whose TAKEOVER_DELAY < the holder's worst-case relinquish bound can take BEFORE
    # the holder's relinquish completes (the exact overlap G2/N1 exist to prevent).
    delay="${TAKEOVER_DELAY:-}"
    case "$delay" in ''|*[!0-9]*)
        _arm_refuse "P5-bound" "cannot check the token's relinquish_bound against this spare's takeover delay: TAKEOVER_DELAY='${delay:-unset}' in $ARM_ENV_FILE is not numeric (cannot-verify at ceremony time fails toward refusing)" "set TAKEOVER_DELAY to this spare's real takeover delay (seconds) in $ARM_ENV_FILE, then re-run 'failover arm'"
    ;; esac
    delay=$((10#$delay))
    if [[ $b -gt $delay ]]; then
        _arm_refuse "P5-bound" "token relinquish_bound EXCEEDS this spare's takeover delay — MEASURED: relinquish_bound=${b}s (the holder's worst-case relinquish, from the token) vs TAKEOVER_DELAY=${delay}s (this spare); REQUIRED: relinquish_bound <= TAKEOVER_DELAY. This spare could take BEFORE the holder's worst-case relinquish completes — the exact double-sign G2 exists to prevent. No override exists for this refusal" "EITHER raise this spare's delay to >= ${b}s:  sed -i 's/^TAKEOVER_DELAY=.*/TAKEOVER_DELAY=${b}/' $ARM_ENV_FILE  and re-run 'failover arm' here — OR re-arm the holder with a tighter bound: lower its EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS so their sum is <= ${delay}, re-run 'failover arm' THERE, and pair this spare with the NEW token"
    fi
    # floor-vs-timer MINIMUM (6.1 reviewer condition — the mirror of the B<=delay refusal above,
    # the same check from the other end: one bound from above, one from below): arming must
    # never make the spare FASTER to take than not-arming. watchdog-elapsed stands on time —
    # the WEAKEST of the three evidence kinds — so its floor (W+B+MARGIN_ELAPSED) must be >=
    # the un-armed timer path's TAKEOVER_DELAY BY CONSTRUCTION, not by presumption ("the longer
    # chain" was an assumption; this refusal and the twin _derive_proof_floors backstop make it
    # true). A short floor is an ordinary MISCONFIGURED holder (WatchdogSec=10 + a 10+10
    # self-fence pair), not a forgery — the holder's drift announcer warns there, and the spare
    # must refuse to pair HERE. MARGIN_ELAPSED is READ from the installed role daemon's single
    # derivation site (comment-stripped, the P1 idiom) — never re-declared in this script: one
    # source of truth, no drift vector, the constants census stays exact; an unreadable margin
    # is cannot-verify at ceremony time and REFUSES. This validation is ARM-TIME: if the
    # installed daemon is upgraded after arming and its MARGIN changes, this check goes stale —
    # deliberately fine: the twin _derive_proof_floors backstop re-derives the floor with the
    # daemon's OWN margin at EVERY start, so the drift is caught at the next restart, never
    # ridden silently (do not hunt for a hole here).
    _p5_margin=$(grep -v '^[[:space:]]*#' "$ARM_INSTALL_DIR/solana-${ARM_ROLE}-failover.sh" 2>/dev/null | grep -m1 -E '^[[:space:]]*MARGIN_ELAPSED=' | cut -d= -f2- | sed 's/#.*//' | tr -d '[:space:]')
    case "$_p5_margin" in ''|*[!0-9]*)
        _arm_refuse "P5-floor" "cannot READ MARGIN_ELAPSED from the installed role daemon ($ARM_INSTALL_DIR/solana-${ARM_ROLE}-failover.sh) — the elapsed-floor minimum cannot be checked (cannot-verify at ceremony time fails toward refusing; got '${_p5_margin:-nothing}')" "install the v0.7 role daemon (it carries the single MARGIN_ELAPSED derivation site), then re-run 'failover arm'"
    ;; esac
    _p5_margin=$((10#$_p5_margin))
    if [[ $_p5_margin -lt 1 || $_p5_margin -gt $PAIRING_BOUND_MAX ]]; then
        _arm_refuse "P5-floor" "MARGIN_ELAPSED read from the installed daemon is out of range — MEASURED: ${_p5_margin}; REQUIRED: 1..${PAIRING_BOUND_MAX} (the token-bounds ceiling class)" "the installed daemon is doctored or corrupted — reinstall the v0.7 daemon, then re-run 'failover arm'"
    fi
    _p5_floor=$(( w + b + _p5_margin ))
    if [[ $_p5_floor -lt $delay ]]; then
        _arm_refuse "P5-floor" "the token-derived watchdog-elapsed floor is SHORTER than this spare's un-armed timer path — MEASURED: floor=${_p5_floor}s (watchdog=${w}s + relinquish_bound=${b}s + MARGIN_ELAPSED=${_p5_margin}s) vs TAKEOVER_DELAY=${delay}s; REQUIRED: floor >= TAKEOVER_DELAY. Arming must never make the spare FASTER to take than not-arming — watchdog-elapsed stands on time, the weakest evidence kind, so its floor must dominate the timer path (the mirror of the relinquish_bound<=TAKEOVER_DELAY refusal above). No override exists for this refusal" "EITHER re-arm the holder with larger bounds so watchdog+relinquish_bound >= $(( delay - _p5_margin ))s (the token carries $(( w + b ))s), re-run 'failover arm' THERE, and pair this spare with the NEW token — OR lower this spare's TAKEOVER_DELAY into [${b}, ${_p5_floor}]:  sed -i 's/^TAKEOVER_DELAY=.*/TAKEOVER_DELAY=${_p5_floor}/' $ARM_ENV_FILE  and re-run 'failover arm' here (keep TAKEOVER_DELAY >= relinquish_bound=${b}s — the refusal above)"
    fi
    # store ATOMICALLY (tmp+mv+verify — the 5.3 gen-counter discipline, incl. the A10
    # directory-swallows-mv trap: stored is only real if a REGULAR FILE now holds the line)
    mkdir -p "$ARM_STATE_DIR" 2>/dev/null
    tmp="$tokf.tmp.$$"
    if printf '%s\n' "$tok" > "$tmp" 2>/dev/null && mv -f "$tmp" "$tokf" 2>/dev/null; then :; else
        rm -f "$tmp" 2>/dev/null
        _arm_refuse "P5-store" "could not store the pairing token at $tokf (write or move failed)" "make $ARM_STATE_DIR writable, then re-run 'failover arm' with the same ARM_PAIRING_TOKEN"
    fi
    if [[ ! -f "$tokf" ]] || [[ "$(head -1 "$tokf" 2>/dev/null)" != "$tok" ]]; then
        _arm_refuse "P5-store" "the pairing token did not persist: $tokf is not a regular file holding the token line after the write (a pre-existing directory at that path swallows the mv while reporting success)" "inspect $tokf, clean it BY HAND (this script never uses rm -rf), then re-run 'failover arm' with the same ARM_PAIRING_TOKEN"
    fi
    if [[ "$fence" == "page-only" ]]; then
        _ARM_PAIR_SUMMARY="page-only gen=$gen watchdog=${w}s relinquish_bound=${b}s holder=$thost"
        _arm_log "precondition P5: pairing token VERIFIED and stored (gen=$gen, watchdog=${w}s, relinquish_bound=${b}s, fence=page-only, holder=$thost; source: $src) — but fence=page-only RELINQUISHES NOTHING (it pages): elapsed (silence-based) attestation is REFUSED, and the ARMED daemon runs the §2.7 posture (proof providers: verified-demote ONLY where G2 is configured, else NONE) until the holder is re-armed with the REAL fence and re-paired."
    else
        _ARM_PAIR_SUMMARY="paired gen=$gen watchdog=${w}s relinquish_bound=${b}s holder=$thost"
        _arm_log "precondition P5: pairing token VERIFIED and stored (gen=$gen, watchdog=${w}s, relinquish_bound=${b}s, fence=real, holder=$thost; source: $src) — the ARMED daemon derives its watchdog-elapsed floor from these bounds at its ONE derivation site (W+B+MARGIN_ELAPSED). A re-armed holder prints a NEW token: re-pair this spare on every holder arm (ceremony, not advice)."
    fi
    _pre_zero_stake_verify
    return 0
}

# zero-stake verification (§2.4 G2 arm condition): for EACH PRIMARY_UNSTAKED_PUBKEY entry, a
# bounded (curl -m 10 class) getVoteAccounts read proving the pubkey carries ZERO activated
# stake — no vote account lists it as nodePubkey with activatedStake > 0; ABSENCE = zero. WHY
# this refuses (the mechanical reason, printed too): a staked "unstaked" key's gossip values
# are STAKED-ORIGIN — they inherit the ~48 h CRDS extended_timeout (max(15 s, epoch_duration))
# instead of the 15 s unstaked expiry, so its ContactInfo entry can linger for DAYS after the
# publisher dies, silently breaking G2's 15 s/30 s expiry math (a present entry would no longer
# prove a LIVE publisher holds the key). Arm-time-only network; the daemons never run this.
_pre_zero_stake_verify() {
    local _zs_pk _zs_rpc _zs_resp _zs_n _zs_amt _zs_ok _zs_manual _zs_done=0
    if [[ -z "${PRIMARY_UNSTAKED_PUBKEY:-}" ]]; then
        _arm_log "precondition P5: PRIMARY_UNSTAKED_PUBKEY is empty in $ARM_ENV_FILE — zero-stake verification SKIPPED: nothing to verify (the G2/fast-path holder-key inputs are absent on this arm; scope derived from the env, §2.4)"
        return 0
    fi
    command -v curl >/dev/null 2>&1 || _arm_refuse "P5-staked-unstaked" "cannot verify zero stake for PRIMARY_UNSTAKED_PUBKEY: curl is not installed (the check is a bounded getVoteAccounts read; cannot-verify at CEREMONY time fails toward refusing)" "install curl, then re-run 'failover arm'"
    command -v jq   >/dev/null 2>&1 || _arm_refuse "P5-staked-unstaked" "cannot verify zero stake for PRIMARY_UNSTAKED_PUBKEY: jq is not installed (the getVoteAccounts answer is JSON; cannot-verify at CEREMONY time fails toward refusing)" "install jq, then re-run 'failover arm'"
    # shellcheck disable=SC2086
    for _zs_pk in $PRIMARY_UNSTAKED_PUBKEY; do
        _zs_ok=""; _zs_n=""
        for _zs_rpc in "${TIER2_RPC:-}" "${TIER3_RPC:-}"; do
            [[ -z "$_zs_rpc" ]] && continue
            _zs_resp=$(curl -s -m 10 "$_zs_rpc" -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null)
            [[ -n "$_zs_resp" ]] || continue
            printf '%s' "$_zs_resp" | jq -e '.result' >/dev/null 2>&1 || continue
            # structural completeness (panel L-3): a healthy mainnet-beta getVoteAccounts ALWAYS
            # populates .result.current with thousands of vote accounts. An empty/absent/non-array
            # current (a cached or CDN-fronted HTTP-200 body, a truncated answer) carries NO
            # vote-account data, so "absence = zero" would be cannot-verify dressed as proof — the
            # exact degenerate-RPC vector this ceremony check must reject. Require current to be a
            # NON-EMPTY array AND delinquent an array before trusting absence; anything else is
            # cannot-verify → skip like an unusable answer (try the next RPC; the "no usable
            # answer" REFUSE below fires if none is usable), NEVER counted as zero-stake. This
            # preserves the true-zero case (a POPULATED current with the key absent) and the
            # delinquent-only-staked catch (the union is unchanged below).
            printf '%s' "$_zs_resp" | jq -e '((.result.current | type) == "array") and ((.result.current | length) > 0) and ((.result.delinquent | type) == "array")' >/dev/null 2>&1 || continue
            # DECISION value = the COUNT of vote accounts listing this pubkey as nodePubkey
            # with activatedStake > 0 (a small integer — robust against huge-lamport
            # formatting); the largest stake is fetched below for the refusal text only. A
            # string-typed activatedStake compares string>number = true in jq → counted as
            # staked → REFUSE: a mis-typed payload fails toward NOT arming, manual command printed.
            _zs_n=$(printf '%s' "$_zs_resp" | jq -r --arg pk "$_zs_pk" '[(.result.current + .result.delinquent)[]? | select(.nodePubkey == $pk) | select(.activatedStake > 0)] | length' 2>/dev/null)
            case "$_zs_n" in ''|*[!0-9]*) _zs_n=""; continue ;; esac
            _zs_ok="$_zs_rpc"
            break
        done
        _zs_manual="curl -s <RPC-URL> -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getVoteAccounts\"}' | jq '[(.result.current + .result.delinquent)[] | select(.nodePubkey == \"$_zs_pk\") | .activatedStake]'   (expect [] or all zeros)"
        if [[ -z "$_zs_ok" ]]; then
            _arm_refuse "P5-staked-unstaked" "cannot VERIFY zero stake for PRIMARY_UNSTAKED_PUBKEY entry '$_zs_pk': no external RPC gave a usable getVoteAccounts answer (TIER2_RPC='${TIER2_RPC:-unset}', TIER3_RPC='${TIER3_RPC:-unset}' — unreachable, unparseable, or structurally incomplete: no populated .result.current[] vote-account list, which a healthy mainnet-beta RPC always returns). Cannot-verify at CEREMONY time fails toward refusing (§2.4)" "verify by hand:  $_zs_manual  — then fix the RPC endpoints/reachability in $ARM_ENV_FILE and RETRY 'failover arm' when an RPC is reachable"
        fi
        if [[ "$_zs_n" != "0" ]]; then
            _zs_amt=$(printf '%s' "$_zs_resp" | jq -r --arg pk "$_zs_pk" '[(.result.current + .result.delinquent)[]? | select(.nodePubkey == $pk) | .activatedStake] | max // 0 | tostring' 2>/dev/null)
            _arm_refuse "P5-staked-unstaked" "PRIMARY_UNSTAKED_PUBKEY entry '$_zs_pk' carries ACTIVATED STAKE — MEASURED: ${_zs_n} vote account(s) list it as nodePubkey with activatedStake > 0 (largest activatedStake=${_zs_amt} lamports, via ${_zs_ok}); REQUIRED: 0. A staked \"unstaked\" key's gossip values are STAKED-ORIGIN: they inherit the ~48 h CRDS extended_timeout (max(15 s, epoch_duration)) instead of the 15 s unstaked expiry, so its ContactInfo entry can linger for DAYS after its publisher dies — silently breaking G2's 15 s/30 s expiry math (a present entry would no longer prove a LIVE publisher holds the key)" "point this entry at the holder's genuinely UNSTAKED identity (zero activated stake) in $ARM_ENV_FILE — or de-stake that key and wait for the deactivation to land (epoch boundary) — then re-run 'failover arm'"
        fi
        _zs_done=$((_zs_done + 1))
        _arm_log "precondition P5: zero-stake VERIFIED for PRIMARY_UNSTAKED_PUBKEY entry '$_zs_pk' via ${_zs_ok} (getVoteAccounts: no vote account lists it as nodePubkey with activatedStake > 0; absence = zero)"
    done
    _arm_log "precondition P5: zero-stake verification complete — entries verified: ${_zs_done} (per entry, N-is-all over the space-separated list)"
    return 0
}

# ── precondition P6: the G2 vantage ceremony — batch capability + resolved distinctness ─────────
# v0.7 (Block 6.2 panel fix round, G2-B1.3 / G2-B2.2). TWO ceremony-time facts the daemon cannot
# establish for itself, both load-bearing for verified-demote:
#   (1) BATCH CAPABILITY. G2's soundness now rests on the freshness anchor riding in the SAME
#       response as the proof payload — one POST carrying [getSlot, getClusterNodes], matched by
#       id. Batching was verified by execution against mainnet-beta/agave 4.2.1 (design record
#       verify-rpc-batch-and-churn.md, private tree), but NOT against every paid provider, and a
#       JSON-RPC-aware intermediary may split batches. A vantage that cannot serve one makes G2
#       permanently cannot-determine at run time — silent unavailability. The ceremony refuses
#       instead, so the operator learns it here rather than during an incident.
#   (2) RESOLVED DISTINCTNESS. The daemon's startup tripwire sees only URLs and hostnames; the
#       CNAME/anycast case (two names, one address) is invisible to it and, per the executed
#       panel finding, the cross-vantage byte compare does NOT catch a single source that varies
#       anything per vantage. Resolution is checkable HERE, once, on a real host.
# SCOPE: spare (standby-role) arms with PRIMARY_UNSTAKED_PUBKEY configured — exactly the condition
# under which the daemon registers G2 at all. Bounded reads, arm-time only; the daemons never run
# this. COST MODEL: cannot-verify at ceremony time fails toward REFUSING (an arm refusal costs a
# re-run, not a vote) — with ONE named exception, unresolvable hostnames, which are a loud WARN:
# refusing there would make a temporarily broken resolver un-armable while proving nothing about
# distinctness. What this canNOT enforce, stated plainly: two genuinely different IPs belonging to
# ONE provider are indistinguishable from here and remain an OPERATOR responsibility.

# host part of an RPC URL — MIRRORS the daemons' _g2_url_host, bracketed-IPv6 form included
# (test_g2_provider drives BOTH implementations over the same URL table and compares, so this copy
# cannot drift silently). Prefix/suffix expansion only; no external calls.
_p6_url_host() {
    local _p6u="$1"
    case "$_p6u" in *"://"*) _p6u="${_p6u#*://}" ;; esac
    _p6u="${_p6u%%/*}"; _p6u="${_p6u%%\?*}"
    case "$_p6u" in
        "["*) _p6u="${_p6u%%]*}]" ;;
        *)    _p6u="${_p6u%%:*}" ;;
    esac
    printf '%s' "$_p6u"
}

# _p6_resolver — the resolution tool actually available here, by availability, named in the log
# (no new hard dependency: "none" is a WARN path, never a refusal).
_p6_resolver() {
    if command -v getent >/dev/null 2>&1; then printf 'getent'
    elif command -v dig >/dev/null 2>&1; then printf 'dig'
    elif command -v host >/dev/null 2>&1; then printf 'host'
    else printf 'none'; fi
}

# normalized RPC URL — MIRRORS the daemons' _norm_rpc_url (trailing slashes stripped, nothing
# else: a URL may carry an API key, and this comparison must not be clever about it).
# test_g2_provider drives BOTH implementations over the same URL table, so this copy cannot drift.
_p6_norm_url() { local _p6n="$1"; while [[ "$_p6n" == */ ]]; do _p6n="${_p6n%/}"; done; printf '%s' "$_p6n"; }

# _p6_share_kind <url-x> <url-y> <host-x> <host-y> <addrs-x> <addrs-y> — the STRONGEST overlap
# actually MEASURED between two endpoints, on stdout ("" = no overlap found by any comparison this
# host could make). Ordered strongest-first so the notice names the comparison that matched, never
# a generic resemblance. Address sets may be empty (no resolver / unresolvable) — that comparison
# is then simply not made, and the caller says so.
_p6_share_kind() {
    if [[ -n "$1" && "$(_p6_norm_url "$1")" == "$(_p6_norm_url "$2")" ]]; then printf 'identical URL'; return 0; fi
    if [[ -n "$3" && "$3" == "$4" ]]; then printf "same host '%s'" "$3"; return 0; fi
    if [[ -n "$5" && "$5" == "$6" ]]; then printf 'same resolved address set [%s]' "$5"; return 0; fi
    return 0
}

# _p6_resolve <host> <tool> — sorted, de-duplicated address set on stdout (empty = unresolvable).
# A literal address (v4 or bracketed v6) resolves to itself — nothing to look up.
_p6_resolve() {
    local _p6h="$1" _p6t="$2"
    case "$_p6h" in
        "["*"]") printf '%s\n' "${_p6h%]}" | sed 's/^\[//' ; return 0 ;;
        *[!0-9.]*) : ;;
        *) printf '%s\n' "$_p6h"; return 0 ;;
    esac
    case "$_p6t" in
        getent) timeout -k 5 10 getent hosts "$_p6h" 2>/dev/null | awk '{print $1}' | sort -u ;;
        dig)    timeout -k 5 10 dig +short "$_p6h" 2>/dev/null | grep -E '^[0-9a-fA-F.:]+$' | sort -u ;;
        host)   timeout -k 5 10 host "$_p6h" 2>/dev/null | awk '/has (IPv6 )?address/{print $NF}' | sort -u ;;
        *)      : ;;
    esac
}

_pre_g2_vantage_probe() {
    local _p6_va _p6_vb _p6_url _p6_lab _p6_id _p6_resp _p6_rc _p6_shape _p6_ids _p6_slot _p6_n
    local _p6_tool _p6_ha _p6_hb _p6_seed
    local _p6_aa="" _p6_ab=""      # empty = that side was never resolved (no resolver / no answer)
    [[ "$ARM_ROLE" == "standby" ]] || return 0
    if [[ -z "${PRIMARY_UNSTAKED_PUBKEY:-}" ]]; then
        _arm_log "precondition P6: PRIMARY_UNSTAKED_PUBKEY is empty in $ARM_ENV_FILE — G2 vantage ceremony SKIPPED: the armed daemon registers no verified-demote provider (nothing to probe; scope derived from the env, §2.4)"
        return 0
    fi
    # the daemon's own vantage derivation, mirrored: env knobs first, else the existing tiers
    _p6_va="${G2_VANTAGE_A:-${TIER2_RPC:-}}"
    _p6_vb="${G2_VANTAGE_B:-${TIER3_RPC:-}}"
    if [[ -z "$_p6_va" || -z "$_p6_vb" ]]; then
        _arm_warn "precondition P6: fewer than two G2 vantages configured (A='${_p6_va:-}' B='${_p6_vb:-}') — the ARMED daemon's startup tripwire will DISABLE verified-demote for the whole run and page CRITICAL, so this spare arms with NO proof provider and only the un-armed timer path. Set G2_VANTAGE_A/G2_VANTAGE_B (or TIER2_RPC/TIER3_RPC) to two bank-bearing RPC providers in DISTINCT failure domains in $ARM_ENV_FILE and re-run 'failover arm'."
        return 0
    fi
    command -v curl >/dev/null 2>&1 || _arm_refuse "P6-batch" "cannot verify G2 vantage batch capability: curl is not installed (the probe is one bounded JSON-RPC read per vantage; cannot-verify at CEREMONY time fails toward refusing)" "install curl, then re-run 'failover arm'"
    command -v jq   >/dev/null 2>&1 || _arm_refuse "P6-batch" "cannot verify G2 vantage batch capability: jq is not installed (the batch answer is JSON; cannot-verify at CEREMONY time fails toward refusing)" "install jq, then re-run 'failover arm'"
    # (1) batch probe, per vantage. Ids are process-derived and distinct per request, exactly as
    # the daemon does it — the echo is part of what is being verified.
    _p6_seed=$$
    for _p6_lab in A B; do
        if [[ "$_p6_lab" == "A" ]]; then _p6_url="$_p6_va"; else _p6_url="$_p6_vb"; fi
        _p6_seed=$(( _p6_seed + 2 )); _p6_id=$_p6_seed
        _p6_resp=$(curl -s -m 10 "$_p6_url" -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d "[{\"jsonrpc\":\"2.0\",\"id\":${_p6_id},\"method\":\"getSlot\",\"params\":[{\"commitment\":\"confirmed\"}]},{\"jsonrpc\":\"2.0\",\"id\":$(( _p6_id + 1 )),\"method\":\"getClusterNodes\"}]" 2>/dev/null)
        _p6_rc=$?
        if [[ $_p6_rc -ne 0 || -z "$_p6_resp" ]]; then
            _arm_refuse "P6-batch" "G2 vantage ${_p6_lab} did not answer the batch probe — MEASURED: curl rc=${_p6_rc}, ${#_p6_resp} bytes returned from '${_p6_url}'; REQUIRED: a JSON-RPC batch response. Cannot-verify at CEREMONY time fails toward refusing (§2.4): an unreachable vantage makes verified-demote permanently cannot-determine at run time, which is silent unavailability during an incident" "fix reachability for this endpoint (or point G2_VANTAGE_${_p6_lab} at a reachable bank-bearing RPC) in $ARM_ENV_FILE, then re-run 'failover arm'"
        fi
        _p6_shape=$(printf '%s' "$_p6_resp" | jq -r 'if type == "array" then "array/" + (length|tostring) else type end' 2>/dev/null)
        [[ -n "$_p6_shape" ]] || _p6_shape="unparseable"
        _p6_ids=$(printf '%s' "$_p6_resp" | jq -r '[.[]? | .id | tostring] | join(",")' 2>/dev/null)
        _p6_slot=$(printf '%s' "$_p6_resp" | jq -r --arg id "$_p6_id" '[.[]? | select((.id|tostring) == $id)] | if length == 1 then (.[0].result // empty) else empty end' 2>/dev/null)
        _p6_n=$(printf '%s' "$_p6_resp" | jq -r --arg id "$(( _p6_id + 1 ))" '[.[]? | select((.id|tostring) == $id)] | if length == 1 then ((.[0].result // empty) | length) else empty end' 2>/dev/null)
        case "$_p6_slot" in ''|*[!0-9]*) _p6_slot="" ;; esac
        case "$_p6_n"    in ''|*[!0-9]*) _p6_n="" ;; esac
        if [[ "$_p6_shape" != "array/2" || -z "$_p6_slot" || -z "$_p6_n" ]]; then
            _arm_refuse "P6-batch" "G2 vantage ${_p6_lab} cannot serve a JSON-RPC BATCH — MEASURED: response shape '${_p6_shape}', ids echoed [${_p6_ids:-none}] for our ids [${_p6_id},$(( _p6_id + 1 ))], getSlot result '${_p6_slot:-none}', getClusterNodes entries '${_p6_n:-none}'; REQUIRED: a 2-element ARRAY whose members echo BOTH of our ids and carry usable results. verified-demote binds its freshness anchor INTO the proof-bearing response by batching [getSlot, getClusterNodes] in ONE POST — without batching that binding is impossible and G2 would answer cannot-determine forever (silent unavailability). Cannot-verify at CEREMONY time fails toward refusing" "point G2_VANTAGE_${_p6_lab} in $ARM_ENV_FILE at an RPC provider that supports JSON-RPC batching (mainnet-beta/agave answers this batch with a 2-element array — verify by hand:  curl -s <RPC-URL> -X POST -H 'Content-Type: application/json' -d '[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getSlot\",\"params\":[{\"commitment\":\"confirmed\"}]},{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"getClusterNodes\"}]' | jq 'type, length'   — expect \"array\" then 2), or remove the caching/proxy layer in front of it, then re-run 'failover arm'"
        fi
        _arm_log "precondition P6: G2 vantage ${_p6_lab} BATCH VERIFIED — MEASURED: array/2, our ids [${_p6_id},$(( _p6_id + 1 ))] echoed back, confirmed slot ${_p6_slot}, ${_p6_n} cluster nodes in the same response (the freshness anchor can be bound to the proof payload)"
    done
    # (2) resolved distinctness. Unresolvable is a WARN (see the scope note above), identical
    # address sets are a REFUSE — that is the literal CNAME-to-one-address case. The WARN branches
    # no longer RETURN: step (3) below must run on every reachable spare arm, resolver or not (it
    # degrades to URL/host comparisons and SAYS which comparisons it was able to make).
    _p6_tool=$(_p6_resolver)
    _p6_ha=$(_p6_url_host "$_p6_va"); _p6_hb=$(_p6_url_host "$_p6_vb")
    if [[ "$_p6_tool" == "none" ]]; then
        _arm_warn "precondition P6: no resolver tool on this host (looked for getent, dig, host) — the G2 vantages' RESOLVED distinctness could NOT be checked (hosts '${_p6_ha}' and '${_p6_hb}'). Recorded, not refused: the daemon's URL/hostname tripwire still runs, but two names pointing at ONE address would go unnoticed. Install one of getent/dig/host and re-run 'failover arm' to get this checked."
    else
        _p6_aa=$(_p6_resolve "$_p6_ha" "$_p6_tool" | tr '\n' ' '); _p6_aa="${_p6_aa% }"
        _p6_ab=$(_p6_resolve "$_p6_hb" "$_p6_tool" | tr '\n' ' '); _p6_ab="${_p6_ab% }"
        if [[ -z "$_p6_aa" || -z "$_p6_ab" ]]; then
            _arm_warn "precondition P6: a G2 vantage hostname did not RESOLVE via ${_p6_tool} — MEASURED: '${_p6_ha}' -> [${_p6_aa:-unresolved}], '${_p6_hb}' -> [${_p6_ab:-unresolved}]. Recorded, not refused (a broken resolver proves nothing about distinctness, and refusing here would block arming on a transient DNS fault) — but the CNAME/anycast case stays UNCHECKED for this arm. Fix resolution and re-run 'failover arm' to get it checked."
        elif [[ "$_p6_aa" == "$_p6_ab" ]]; then
            _arm_refuse "P6-vantage" "the two G2 vantages resolve to the SAME address set — MEASURED (via ${_p6_tool}): '${_p6_ha}' -> [${_p6_aa}], '${_p6_hb}' -> [${_p6_ab}]; REQUIRED: different addresses. They are ONE witness wearing two names: 'present on BOTH vantages' would be a single observation counted twice, and the run-time cross-vantage byte compare does NOT catch a source that varies anything per request (executed panel finding). verified-demote's whole premise is two INDEPENDENT views" "point G2_VANTAGE_A and G2_VANTAGE_B in $ARM_ENV_FILE at two RPC providers in DIFFERENT failure domains (different operators, not two names or two API keys for one), then re-run 'failover arm'"
        else
            _arm_log "precondition P6: G2 vantage RESOLVED DISTINCTNESS verified via ${_p6_tool} — MEASURED: '${_p6_ha}' -> [${_p6_aa}], '${_p6_hb}' -> [${_p6_ab}] (different address sets). NOTE, and it is the operator's to own: different addresses belonging to ONE provider are indistinguishable from here — this check kills the CNAME/anycast-to-one-address case, not shared ownership"
        fi
    fi
    # (3) SHARED VANTAGE with the vote-liveness tiers (reviewer condition C1) — a DEGRADATION
    # NOTICE, never a refusal, by explicit instruction: the daemon DEFAULTS G2_VANTAGE_A/B to
    # TIER2_RPC/TIER3_RPC and most operators run exactly two RPCs, so refusing here would be
    # sabotage. It is loud and RECORDED because on such a host the B3 severity statement stops
    # meaning anything (see _pre_g2_tier_overlap).
    _pre_g2_tier_overlap "$_p6_va" "$_p6_vb" "$_p6_ha" "$_p6_hb" "$_p6_aa" "$_p6_ab" "$_p6_tool"
    return 0
}

# ── _pre_g2_tier_overlap <va> <vb> <host-a> <host-b> <addrs-a> <addrs-b> <resolver-tool> ────────
# C1, the honesty statement made true. The B3 severity claim — "a double-sign needs BOTH a false
# G2 proof AND a false-frozen vote observation" — is formally true but MEANINGLESS when G2's
# vantages ARE the vote-liveness tiers, which is the DEFAULT config: _g2_register defaults
# G2_VANTAGE_A/B to TIER2_RPC/TIER3_RPC, and every liveness reader in the daemons iterates
# `for rpc in "$TIER2_RPC" "$TIER3_RPC"`. One protocol-aware intermediary in front of that single
# endpoint supplies BOTH halves: it splices getSlot/getClusterNodes into a false verified-demote
# proof, and it proxies the tip live while freezing the staked account's lastVote into a
# false-frozen vote observation. The tip-guard catches only a freeze AT OR BEFORE the pinned first
# sample (it compares against that pinned tip and the frozen path never re-bases it) — a naive freeze
# that begins after the pin passes it (6.3 panel F3); an active one is the same "passive closed,
# active open" boundary G2 already draws honestly (SAFETY.md residual 2).
# So: measure it, name it, print the way back — and arm anyway.
# Every pair is compared strongest-first (normalized URL, then host, then resolved address set)
# and the OUTPUT NAMES THE COMPARISON THAT MATCHED. The no-overlap line is printed too, with the
# comparisons this host could actually make, so a clean result is never a silent pass.
_pre_g2_tier_overlap() {
    local _p6o_va="$1" _p6o_vb="$2" _p6o_ha="$3" _p6o_hb="$4" _p6o_aa="$5" _p6o_ab="$6" _p6o_tool="$7"
    local _p6o_h2 _p6o_h3 _p6o_a2 _p6o_a3 _p6o_hits="" _p6o_k _p6o_pair _p6o_vl _p6o_tl
    local _p6o_vu _p6o_vh _p6o_vaddr _p6o_tu _p6o_th _p6o_taddr _p6o_how
    _p6o_h2=$(_p6_url_host "${TIER2_RPC:-}"); _p6o_h3=$(_p6_url_host "${TIER3_RPC:-}")
    _p6o_a2=""; _p6o_a3=""
    if [[ "$_p6o_tool" != "none" ]]; then
        if [[ -n "$_p6o_h2" ]]; then _p6o_a2=$(_p6_resolve "$_p6o_h2" "$_p6o_tool" | tr '\n' ' '); _p6o_a2="${_p6o_a2% }"; fi
        if [[ -n "$_p6o_h3" ]]; then _p6o_a3=$(_p6_resolve "$_p6o_h3" "$_p6o_tool" | tr '\n' ' '); _p6o_a3="${_p6o_a3% }"; fi
    fi
    for _p6o_pair in A:2 A:3 B:2 B:3; do
        _p6o_vl="${_p6o_pair%%:*}"; _p6o_tl="${_p6o_pair##*:}"
        if [[ "$_p6o_vl" == "A" ]]; then _p6o_vu="$_p6o_va"; _p6o_vh="$_p6o_ha"; _p6o_vaddr="$_p6o_aa"
        else                             _p6o_vu="$_p6o_vb"; _p6o_vh="$_p6o_hb"; _p6o_vaddr="$_p6o_ab"; fi
        if [[ "$_p6o_tl" == "2" ]]; then _p6o_tu="${TIER2_RPC:-}"; _p6o_th="$_p6o_h2"; _p6o_taddr="$_p6o_a2"
        else                             _p6o_tu="${TIER3_RPC:-}"; _p6o_th="$_p6o_h3"; _p6o_taddr="$_p6o_a3"; fi
        [[ -n "$_p6o_tu" ]] || continue
        _p6o_k=$(_p6_share_kind "$_p6o_vu" "$_p6o_tu" "$_p6o_vh" "$_p6o_th" "$_p6o_vaddr" "$_p6o_taddr")
        if [[ -n "$_p6o_k" ]]; then
            _p6o_hits="${_p6o_hits:+$_p6o_hits; }G2_VANTAGE_${_p6o_vl} (host '${_p6o_vh}') == TIER${_p6o_tl}_RPC (host '${_p6o_th}') by ${_p6o_k}"
        fi
    done
    # which comparisons this host was ABLE to make — so "no overlap" never over-claims
    if [[ "$_p6o_tool" == "none" ]]; then
        _p6o_how="normalized-URL and host compares ONLY — no resolver on this host, so the resolved-address compare was NOT made"
    elif [[ -z "$_p6o_aa" || -z "$_p6o_ab" || ( -n "${TIER2_RPC:-}" && -z "$_p6o_a2" ) || ( -n "${TIER3_RPC:-}" && -z "$_p6o_a3" ) ]]; then
        _p6o_how="normalized-URL and host compares, plus resolved-address compares via ${_p6o_tool} only where BOTH sides resolved (at least one name did not resolve: that comparison is INCOMPLETE)"
    else
        _p6o_how="normalized-URL and host compares, plus resolved-address compares via ${_p6o_tool} on every pair"
    fi
    if [[ -z "$_p6o_hits" ]]; then
        _ARM_G2_SHARED=""
        _arm_log "precondition P6: G2 vantages are SEPARATE from the vote-liveness tiers — MEASURED (${_p6o_how}): no G2 vantage matched TIER2_RPC (host '${_p6o_h2}') or TIER3_RPC (host '${_p6o_h3}'). The proof gate's additivity HOLDS on this host for verified-demote: a double-sign through G2 needs a false G2 proof AND a false-frozen vote observation, and those two rest on different endpoints. It does NOT extend to watchdog-elapsed, on any host: its silence and the vote-FROZEN observation are the same TIER2/TIER3 input — attested time, not a second witness (docs/SAFETY.md, 'Shared vantages')"
        return 0
    fi
    _ARM_G2_SHARED="$_p6o_hits"
    _arm_warn "precondition P6 — DEGRADED, NOT REFUSED: G2 and vote-liveness SHARE VANTAGES: one compromised vantage supplies BOTH halves of the double-sign condition — a false verified-demote proof AND a false-frozen vote observation — so the proof gate's additivity does NOT hold on this host. MEASURED (${_p6o_how}): ${_p6o_hits}. The daemons' liveness readers iterate TIER2_RPC then TIER3_RPC, so the same protocol-aware intermediary can splice getSlot/getClusterNodes into the false proof AND proxy the tip live while freezing the staked account's lastVote into the false-frozen observation; docs/SAFETY.md residual 2 (an active, protocol-aware intermediary) is NOT bounded by that composition. Not refused, deliberately: most operators run exactly two RPCs and refusing would leave this spare un-armed. THE WAY BACK: point G2_VANTAGE_A and/or G2_VANTAGE_B in $ARM_ENV_FILE at a THIRD endpoint in a SEPARATE FAILURE DOMAIN — a different operator, not another hostname or another API key for one you already use — then re-run 'failover arm'. That restores additivity for verified-demote ONLY: watchdog-elapsed's silence and the vote-FROZEN observation stay one TIER2/TIER3 input on every host (docs/SAFETY.md, 'Shared vantages')."
    return 0
}

# end-of-summary G2 vantage posture (C1): the degradation must survive a long arm transcript, so
# the MEASURED overlap is re-stated on the final screen next to the pairing state. Silent when the
# vantages are separate (the green case already printed its own MEASURED line at P6) and on any arm
# where P6 never ran (holder role, or a spare with no PRIMARY_UNSTAKED_PUBKEY) — those leave
# _ARM_G2_SHARED empty. Printed BEFORE the pairing posture, which stays last by §2.7 (c).
_arm_g2_summary() {
    [[ -n "$_ARM_G2_SHARED" ]] || return 0
    _arm_warn "G2 vantage summary — G2 and vote-liveness SHARE VANTAGES: one compromised vantage supplies BOTH halves of the double-sign condition — a false verified-demote proof AND a false-frozen vote observation — so the proof gate's additivity does NOT hold on this host. MEASURED: ${_ARM_G2_SHARED}. This spare is armed; the proof gate is not wired into any take path in this build (docs/SAFETY.md, 'Verified-demote (G2)' residual 2). Fix by pointing G2_VANTAGE_A/G2_VANTAGE_B in $ARM_ENV_FILE at a third endpoint in a separate failure domain, then re-run 'failover arm' — that restores additivity for verified-demote ONLY: watchdog-elapsed's silence and the vote-FROZEN observation stay one TIER2/TIER3 input on every host (docs/SAFETY.md, 'Shared vantages')."
    return 0
}

# end-of-summary pairing posture (§2.7 (c) [6.0-COND-4]): printed LAST — after the ARMED
# completion line — so the operator's final screen carries the pairing state; never a silent
# default. Empty summary = a primary-role arm (no intake ran).
_arm_pairing_summary() {
    case "$_ARM_PAIR_SUMMARY" in
        "") : ;;
        paired*)
            _arm_log "pairing summary: PAIRED (${_ARM_PAIR_SUMMARY}) — re-pair on EVERY holder re-arm: a re-armed holder prints a NEW token and this spare's stored bounds go stale (the stale-bound residual, docs/SAFETY.md); the holder's arm refuses to complete without printing it."
        ;;
        page-only*)
            _arm_warn "pairing summary: token stored but fence=page-only (${_ARM_PAIR_SUMMARY}) — page-only relinquishes NOTHING: elapsed (silence-based) attestation REFUSED; the ARMED daemon runs the §2.7 posture (proof providers: verified-demote ONLY where G2 is configured, else NONE — holder not attested) and pages it at every start. Re-arm the holder with DRY_RUN=false (the REAL fence), then re-pair this spare with the new token."
        ;;
        *)
            _arm_warn "pairing summary: UNPAIRED SPARE — no valid pairing token stored: the ARMED daemon runs proof providers verified-demote ONLY where G2 is configured (PRIMARY_UNSTAKED_PUBKEY set), else NONE (holder not attested; silence-based take disabled) and pages CRITICAL at every start until paired. Pair: run 'failover arm' on the HOLDER first (upgrade order: holder first), copy the token line it prints, then re-run this arm with ARM_PAIRING_TOKEN='<that line>'."
        ;;
    esac
    return 0
}

# ── skel renderer: header-discipline check → RENDERED header + line replacements → atomic mv
#    → content verification ────────────────────────────────────────────────────────────────────
# Every skel carries the 3-line SKELETON paragraph + a bare '#' on line 4 (the repo's header
# discipline); the renderer replaces exactly that with a RENDERED stamp and keeps the rest of
# the unit's comments on-host. $3/$4 empty = keep the skel's line.
#
# 5.3 panel fix round: the replacement is STRUCTURAL — bash string tests + printf per line,
# never sed. The sed metacharacter class ('&' expanding the match under patsub_replacement's
# sed cousin, '\', the delimiter itself) disappears by construction, so paths containing
# '&', '\' or '|' render byte-exact and the old RENDER-delim refusal is gone WITH the sed
# (panel A3/A14/A15). After the mv the rendered file is VERIFIED: requested ExecStart/
# EnvironmentFile present byte-exact and no placeholder token left outside comments — a
# garbage render can no longer arm (panel A13); a pre-existing DIRECTORY at the destination
# is refused BEFORE rendering, because `mv` onto a directory relocates the tmp INTO it and
# returns 0 (panel A6).
_render_skel() {
    local skel="$1" dest="$2" exec_rep="$3" env_rep="$4" l1 l4 tmp line
    [[ -f "$skel" ]] || _arm_refuse "RENDER-skel-missing" "template $skel not found next to failover-arm.sh" "run 'failover arm' from an intact v0.7 release tree (systemd/*.skel must sit beside it)"
    l1=$(sed -n '1p' "$skel"); l4=$(sed -n '4p' "$skel")
    case "$l1" in "# SKELETON"*) : ;; *) _arm_refuse "RENDER-header" "$(basename "$skel") line 1 is not the SKELETON header — the skel header discipline changed under this renderer" "update _render_skel in failover-arm.sh together with the header change (they are one contract)" ;; esac
    [[ "$l4" == "#" ]] || _arm_refuse "RENDER-header" "$(basename "$skel") line 4 is not the bare '#' header separator — the skel header discipline changed under this renderer" "update _render_skel in failover-arm.sh together with the header change (they are one contract)"
    if [[ -e "$dest" && ! -f "$dest" ]]; then
        _arm_refuse "RENDER-dest" "a pre-existing non-regular path sits at the render destination $dest (a directory?) — 'mv' onto it would relocate the rendered unit INSIDE it and report success while the unit path stays wrong" "inspect $dest and remove it BY HAND (this script never uses rm -rf), then re-run 'failover arm'"
    fi
    tmp="$dest.tmp.$$"
    {
        printf '# RENDERED by the `failover arm` ceremony (failover-arm.sh, v0.7 Block 5.3) from %s\n' "$(basename "$skel")"
        # wall-clock BY DESIGN (the ci.yml facts sentence's arm site): a human-readable render
        # STAMP, not a timer — the monotonic-timer rule pins the daemons, not stamps.
        printf '# on %s — do NOT edit by hand: re-running `failover arm` overwrites this file, and\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
        printf '# arm-state IS which fence unit is installed (§2.3). Re-align via `failover arm`.\n'
        printf '#\n'
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ -n "$exec_rep" && "$line" == ExecStart=* ]]; then
                printf 'ExecStart=%s\n' "$exec_rep"
            elif [[ -n "$env_rep" && "$line" == EnvironmentFile=* ]]; then
                printf 'EnvironmentFile=%s\n' "$env_rep"
            else
                printf '%s\n' "$line"
            fi
        done < <(tail -n +5 "$skel")
    } > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; _arm_refuse "RENDER-write" "cannot write the rendered unit at $tmp" "check permissions on $(dirname "$dest"), then re-run 'failover arm'"; }
    mv -f "$tmp" "$dest" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; _arm_refuse "RENDER-write" "cannot move the rendered unit into place at $dest" "check permissions on $(dirname "$dest"), then re-run 'failover arm'"; }
    # content verification (render→verify at the FILE level; the arm-state verify is separate):
    # what was requested is what is on disk — byte-exact lines, and no placeholder survived.
    [[ -f "$dest" ]] || _arm_refuse "RENDER-verify" "the rendered unit is not a regular file at $dest after the move" "inspect $dest, clean it BY HAND (never rm -rf), then re-run 'failover arm'"
    if [[ -n "$exec_rep" ]] && ! grep -qxF "ExecStart=$exec_rep" "$dest" 2>/dev/null; then
        _arm_refuse "RENDER-verify" "rendered $dest does not carry the requested line byte-exact: 'ExecStart=$exec_rep' — the renderer and the on-disk unit disagree; arming would install a unit that does not run what the ceremony claims" "inspect $dest, then re-run 'failover arm' from an intact release tree"
    fi
    if [[ -n "$env_rep" ]] && ! grep -qxF "EnvironmentFile=$env_rep" "$dest" 2>/dev/null; then
        _arm_refuse "RENDER-verify" "rendered $dest does not carry the requested line byte-exact: 'EnvironmentFile=$env_rep'" "inspect $dest, then re-run 'failover arm' from an intact release tree"
    fi
    if grep -v '^[[:space:]]*#' "$dest" 2>/dev/null | grep -q '<[a-z][a-z-]*>'; then
        _arm_refuse "RENDER-verify" "rendered $dest still carries a skeleton placeholder token outside comments — the unit is uninstallable as rendered" "re-run 'failover arm' from an intact v0.7 release tree; if this repeats, the skel and the renderer have drifted (they are one contract)"
    fi
}

# ── the §2.1-rev2.1 end-to-end probe (condition 1 verbatim) + §2.6 socat self-test ──────────────
_arm_cleanup_probe() {
    [[ -n "$_ARM_PROBE_RENDERED" ]] || return 0
    _ARM_PROBE_RENDERED=""
    timeout -k 5 10 systemctl reset-failed "$PROBE_UNIT_NAME" >/dev/null 2>&1 || true
    rm -f "$ARM_RUNTIME_DIR/$PROBE_UNIT_NAME" "$ARM_RUNTIME_DIR/$PROBE_FENCE_NAME" 2>/dev/null
    rm -f "$PROBE_MARKER" 2>/dev/null
    timeout -k 5 15 systemctl daemon-reload >/dev/null 2>&1 || _arm_warn "daemon-reload failed during probe cleanup — run systemctl daemon-reload by hand"
    _arm_log "probe: transient units cleaned + daemon reloaded"
    return 0
}

_arm_probe() {
    PROBE_MARKER="$FENCE_MARKER_DIR/arm-probe.fired"
    mkdir -p "$FENCE_MARKER_DIR" "$ARM_RUNTIME_DIR" 2>/dev/null
    # 5.3 panel fix round (M-A): the pre-probe stale clean is LOAD-BEARING. FENCE_MARKER_DIR is
    # persistent and this script carries no trap — a ceremony interrupted between the OnFailure
    # touch and cleanup (Ctrl-C in the ~15 s wait, power loss) leaves the marker for the next
    # run, which would then false-PROVE functionally dead wiring. Announce + remove a stale
    # FILE; anything that survives rm -f (a directory — panel A5) REFUSES: probe markers are
    # file-typed everywhere below ([[ -f ]], never -e), and the ceremony never reaches for rm -rf.
    if [[ -e "$PROBE_MARKER" || -L "$PROBE_MARKER" ]]; then
        [[ -f "$PROBE_MARKER" ]] && _arm_warn "stale probe marker $PROBE_MARKER pre-exists (an interrupted previous ceremony?) — removing it before the probe so only THIS run's dispatch can satisfy the wait"
        rm -f "$PROBE_MARKER" 2>/dev/null   # M-A pre-probe stale clean
    fi
    if [[ -e "$PROBE_MARKER" || -L "$PROBE_MARKER" ]]; then
        _arm_refuse "PROBE-marker-stale" "a pre-existing path at $PROBE_MARKER cannot be removed (a directory?) — while ANY path sits at the marker the probe cannot distinguish live dispatch from leftovers, so the wiring proof would be vacuous" "inspect $PROBE_MARKER and clean it BY HAND (this script never uses rm -rf), then re-run 'failover arm'"
    fi
    _arm_log "probe: rendering the transient probe pair into $ARM_RUNTIME_DIR (ephemeral by construction — §2.1-rev2.1 condition 1)"
    _ARM_PROBE_RENDERED=1
    _render_skel "$_SKEL_DIR/$PROBE_FENCE_NAME.skel" "$ARM_RUNTIME_DIR/$PROBE_FENCE_NAME" "/bin/touch $PROBE_MARKER" ""
    _render_skel "$_SKEL_DIR/$PROBE_UNIT_NAME.skel" "$ARM_RUNTIME_DIR/$PROBE_UNIT_NAME" "" ""
    timeout -k 5 15 systemctl daemon-reload >/dev/null 2>&1 || _arm_refuse "PROBE-reload" "systemctl daemon-reload failed after rendering the probe pair" "run systemctl daemon-reload by hand and read journalctl -xe, then re-run 'failover arm'"
    # Type=notify start: rc 0 ⇔ READY landed ⇔ ONE socat pet crossed the transport — THIS IS
    # ALSO THE SOCAT SELF-TEST (§2.6: refuse to arm if a pet doesn't land).
    if ! timeout -k 5 30 systemctl start "$PROBE_UNIT_NAME" >/dev/null 2>&1; then
        _arm_refuse "PROBE-ready" "the probe unit did not reach READY — the one socat pet did NOT land (§2.6 self-test: refuse to arm if a pet doesn't land; the transport is broken end-to-end on this host)" "check: socat installed and runnable? NotifyAccess=all on the probe unit as loaded (systemctl show $PROBE_UNIT_NAME -p NotifyAccess)? systemd version new enough to pass \$NOTIFY_SOCKET (>= 236)? journalctl -u $PROBE_UNIT_NAME — then re-run 'failover arm'"
    fi
    _arm_log "probe READY — the one socat pet landed: transport proven end-to-end on this host (§2.6 self-test); the probe now deliberately never pets again"
    local _i=1
    while [[ $_i -le $ARM_PROBE_WAIT ]]; do
        [[ -f "$PROBE_MARKER" ]] && break
        sleep 1
        _i=$((_i + 1))
    done
    if [[ ! -f "$PROBE_MARKER" ]]; then
        _arm_refuse "PROBE-marker" "the OnFailure marker did not appear within ${ARM_PROBE_WAIT}s — stopped-petting did NOT dispatch the probe fence on this host: the wiring is 'syntactically valid, functionally dead', exactly the class this probe exists to catch (§2.1-rev2.1)" "check: NotifyAccess=all on the probe unit as loaded? systemd version (WatchdogSec/OnFailure semantics)? socat present for the pet? journalctl -u $PROBE_UNIT_NAME -u $PROBE_FENCE_NAME — fix the wiring, then re-run 'failover arm'"
    fi
    _arm_log "probe marker observed — stopped-petting → watchdog fired → terminal failed → OnFailure dispatched: wiring PROVEN on this host (§2.1-rev2.1 condition 1)"
    _arm_cleanup_probe
}

# ── legacy-monitor retirement (5.3 fix round 2, reviewer blocker) ───────────────────────────────
# "Exactly ONE" applies to the MONITOR exactly as §2.3 applies it to the fence unit. The legacy
# deploy wizards install and enable the pre-fence Restart=always services — the FULL name set,
# N-is-all by grep over both wizards (every '*.service' they write or enable, 2026-08-21):
#   deploy-failover.sh         → solana-failover.service          (write 669; start/enable 780)
#   deploy-failover-standby.sh → solana-failover-standby.service  (write 907; start/enable 1042)
# (their `solana.service` mentions are the VALIDATOR unit — referenced, never written/enabled as
# a monitor; it is NOT in this set and the arm never touches it). Leaving one of these RUNNING
# beside the Block-5 monitor puts TWO monitor daemons on one host: same env file, same state
# file, both free to call set-identity; per-process H1.3/self-fence state over a shared disk
# stamp → one demotes, the other re-takes inside the lockout — a dual actor created at exactly
# the moment the ceremony exists to make safe. The retirement is a CEREMONY step run BEFORE the
# new monitor is enabled (same class as the stale fence-sibling removal). A daemon-side
# single-instance flock is the WRONG fix and is deliberately absent: a Type=notify monitor
# losing that race never goes READY → start timeout → terminal `failed` → OnFailure → a REAL
# fence on a HEALTHY validator (the reviewer traced this; do not add one).
LEGACY_MONITOR_UNITS="solana-failover.service solana-failover-standby.service"
_retire_legacy_monitors() {
    local u present state
    for u in $LEGACY_MONITOR_UNITS; do
        present=""
        [[ -e "$ARM_SYSTEMD_DIR/$u" ]] && present="unit file present"
        if [[ -z "$present" ]] && timeout -k 5 10 systemctl is-active "$u" >/dev/null 2>&1; then present="unit active"; fi
        if [[ -z "$present" ]]; then case "$(timeout -k 5 10 systemctl is-enabled "$u" 2>/dev/null)" in enabled*) present="unit enabled" ;; esac; fi
        [[ -z "$present" ]] && continue
        _arm_log "install: legacy monitor $u detected ($present) — retiring it BEFORE the Block-5 monitor is enabled (two monitor daemons on one host share the env + state file and race set-identity: one demotes, the other re-takes inside the lockout)"
        if ! timeout -k 10 30 systemctl stop "$u" >/dev/null 2>&1; then
            _arm_refuse "INSTALL-legacy" "systemctl stop $u failed — the legacy monitor is still running, and enabling the Block-5 monitor beside it would put TWO monitor daemons on this host (same env, same state file, both free to call set-identity)" "by hand:  systemctl stop $u && systemctl disable $u  — verify with  systemctl is-active $u  (expect inactive) and  systemctl is-enabled $u  (expect disabled/not-found), then re-run 'failover arm'"
        fi
        if ! timeout -k 5 15 systemctl disable "$u" >/dev/null 2>&1; then
            _arm_refuse "INSTALL-legacy" "systemctl disable $u failed — the stopped legacy monitor would return at the next boot beside the Block-5 monitor" "by hand:  systemctl disable $u  — verify with  systemctl is-enabled $u  (expect disabled/not-found), then re-run 'failover arm'"
        fi
        # VERIFY (claims never exceed checks): a stop/disable that returned 0 but changed
        # nothing (a respawned unit, an alias, a broken systemd) must refuse HERE, not arm.
        if timeout -k 5 10 systemctl is-active "$u" >/dev/null 2>&1; then
            _arm_refuse "INSTALL-legacy" "verify disagreement: systemctl stop $u returned success but is-active still reports the unit ACTIVE — the retirement did not actually happen, and completing the arm would enable a second monitor beside a running one" "by hand:  systemctl stop $u ; systemctl is-active $u  until it reports inactive (find and kill the process if it respawns), then  systemctl disable $u , then re-run 'failover arm'"
        fi
        state=$(timeout -k 5 10 systemctl is-enabled "$u" 2>/dev/null)
        case "$state" in enabled*)
            _arm_refuse "INSTALL-legacy" "verify disagreement: systemctl disable $u returned success but is-enabled still reports '$state' — the legacy monitor would return at the next boot" "by hand:  systemctl disable $u ; systemctl is-enabled $u  until it reports disabled/not-found, then re-run 'failover arm'"
        ;; esac
        _arm_log "legacy monitor retired: $u — the Block-5 monitor replaces it (stopped + disabled + VERIFIED via is-active/is-enabled; the unit FILE stays on disk — deleting it is the operator's cleanup, not the ceremony's)"
    done
}

# ── install: fence bodies + monitor unit + exactly ONE fence unit + enable ──────────────────────
_arm_install() {
    local role_daemon="$ARM_INSTALL_DIR/solana-${ARM_ROLE}-failover.sh" s tmp
    # fence BODIES: the release artifact ships them; the CEREMONY is the only thing that ever
    # places them on a host (systemd/README.md's boundary). Both bodies are placed — which UNIT
    # exists is the arm state (§2.3); a body with no unit is dispatched by nothing.
    for s in failover-fence.sh failover-fence-page-only.sh; do
        [[ -f "$_SKEL_DIR/$s" ]] || _arm_refuse "INSTALL-body-missing" "$_SKEL_DIR/$s not found next to failover-arm.sh" "run 'failover arm' from an intact v0.7 release tree"
        tmp="$ARM_INSTALL_DIR/$s.tmp.$$"
        if cp "$_SKEL_DIR/$s" "$tmp" 2>/dev/null && chmod 755 "$tmp" 2>/dev/null && mv -f "$tmp" "$ARM_INSTALL_DIR/$s" 2>/dev/null; then :; else
            rm -f "$tmp" 2>/dev/null
            _arm_refuse "INSTALL-body" "could not place $s into $ARM_INSTALL_DIR" "check permissions on $ARM_INSTALL_DIR, then re-run 'failover arm'"
        fi
    done
    _arm_log "install: fence bodies placed into $ARM_INSTALL_DIR (failover-fence.sh + failover-fence-page-only.sh — the ceremony is the only placer)"
    # monitor unit: fill <role> + the role env (the unit itself stays IMMUTABLE across arm
    # states — arm-state lives entirely in which fence unit exists, §2.3)
    _render_skel "$_SKEL_DIR/$MONITOR_UNIT_NAME.skel" "$ARM_SYSTEMD_DIR/$MONITOR_UNIT_NAME" "$role_daemon" "$ARM_INSTALL_DIR/$ARM_ENV_BASE"
    _arm_log "install: monitor unit rendered → $ARM_SYSTEMD_DIR/$MONITOR_UNIT_NAME (role: $ARM_ROLE)"
    # exactly ONE fence unit — page-only XOR real per DRY_RUN; the arm is the alignment mechanism
    local want_name drop_name
    if [[ "$ARM_INTENT" == "real" ]]; then
        want_name="$FENCE_UNIT_REAL_NAME"; drop_name="$FENCE_UNIT_PAGE_NAME"
        _render_skel "$_SKEL_DIR/$FENCE_UNIT_REAL_NAME.skel" "$ARM_SYSTEMD_DIR/$want_name" "$ARM_INSTALL_DIR/failover-fence.sh" "$ARM_INSTALL_DIR/$ARM_ENV_BASE"
    else
        want_name="$FENCE_UNIT_PAGE_NAME"; drop_name="$FENCE_UNIT_REAL_NAME"
        _render_skel "$_SKEL_DIR/$FENCE_UNIT_PAGE_NAME.skel" "$ARM_SYSTEMD_DIR/$want_name" "$ARM_INSTALL_DIR/failover-fence-page-only.sh" "$ARM_INSTALL_DIR/$ARM_ENV_BASE"
    fi
    if [[ -e "$ARM_SYSTEMD_DIR/$drop_name" ]]; then
        if rm -f "$ARM_SYSTEMD_DIR/$drop_name" 2>/dev/null && [[ ! -e "$ARM_SYSTEMD_DIR/$drop_name" ]]; then
            _arm_log "install: removed stale sibling $drop_name — the arm is the ALIGNMENT mechanism (§2.3: exactly ONE fence unit)"
        elif [[ "$ARM_INTENT" == "real" ]]; then
            # 5.3 panel fix round (A2): under REAL intent a surviving sibling means BOTH fence
            # units on disk — a §2.3 one-unit violation the real-wins classifier would MASK
            # (post-install verify reads 'real' and agrees). Refuse; never WARN-and-arm.
            _arm_refuse "INSTALL-sibling" "the stale sibling $ARM_SYSTEMD_DIR/$drop_name cannot be removed (a directory?) — completing the arm would leave BOTH fence units on disk, violating §2.3 (exactly ONE fence unit IS the arm state), and real-wins classification would hide it from the post-install verify" "inspect $ARM_SYSTEMD_DIR/$drop_name and remove it BY HAND (this script never uses rm -rf), systemctl daemon-reload, then re-run 'failover arm'"
        else
            # page-only intent + a stuck REAL sibling: the classifier reads 'real' ≠ intent
            # 'page-only' → the post-install verify below REFUSES (always, not 'if') — the №1
            # refusal path. The WARN here only narrates why that refusal is about to happen.
            _arm_warn "could not remove the stale sibling $drop_name — it still classifies as the arm state (real wins), so the post-install verify below will refuse"
        fi
    fi
    _arm_log "install: exactly ONE fence unit → $ARM_SYSTEMD_DIR/$want_name"
    timeout -k 5 15 systemctl daemon-reload >/dev/null 2>&1 || _arm_refuse "INSTALL-reload" "systemctl daemon-reload failed after installing the units" "run systemctl daemon-reload by hand and read journalctl -xe, then re-run 'failover arm'"
    # Legacy-monitor retirement runs BEFORE the enable below — on any failure it REFUSES, the
    # new monitor is never enabled, and no token prints (see _retire_legacy_monitors' header
    # for the N-is-all name-set derivation and why a daemon-side flock is the wrong fix).
    _retire_legacy_monitors
    # The ONLY `systemctl enable` of a BLOCK-5 unit — the legacy deploy wizards enable the
    # pre-fence services (deploy-failover.sh:669/780 solana-failover.service,
    # deploy-failover-standby.sh:907/1042 solana-failover-standby.service), and THIS ceremony
    # has just RETIRED any of them it found (stop+disable+verify above): supersession is an
    # ACTION the arm performs, not a rollout plan. No other script references the Block-5 unit
    # names (the functional Block-5 boundary, held by grep). The validator unit is NEVER
    # started, restarted, or stopped by this script — arming must not touch a possibly-voting
    # process.
    timeout -k 5 15 systemctl enable "$MONITOR_UNIT_NAME" >/dev/null 2>&1 || _arm_refuse "INSTALL-enable" "systemctl enable $MONITOR_UNIT_NAME failed" "read journalctl -xe, enable by hand (systemctl enable $MONITOR_UNIT_NAME), then re-run 'failover arm' to verify + re-pair"
    _arm_log "install: monitor enabled (the only enable of a Block-5 unit — the legacy deploy wizards' pre-fence services are RETIRED by this ceremony when present, an action performed above, not a plan). The validator unit was NOT touched."
}

# ── post-install verify: _fence_unit_state-equivalent re-read (render→verify) ───────────────────
# The daemons' [one-arm-state] classifier semantics, re-rooted at ARM_SYSTEMD_DIR: real wins
# when both exist (ambiguity fails toward the №1 refusal), matching _fence_unit_state exactly.
_arm_fence_unit_state() {
    if [[ -e "$ARM_SYSTEMD_DIR/$FENCE_UNIT_REAL_NAME" ]]; then
        echo "real"
    elif [[ -e "$ARM_SYSTEMD_DIR/$FENCE_UNIT_PAGE_NAME" ]]; then
        echo "page-only"
    else
        echo "none"
    fi
}
_arm_verify() {
    local got; got=$(_arm_fence_unit_state)
    if [[ "$got" != "$ARM_INTENT" ]]; then
        _arm_refuse "VERIFY-mismatch" "post-install classification is '$got' but the DRY_RUN intent is '$ARM_INTENT' (render→verify, not render→hope; a stale sibling that would not remove is the usual cause)" "inspect $ARM_SYSTEMD_DIR (ls solana-failover-fence*), remove the wrong unit by hand, systemctl daemon-reload, then re-run 'failover arm'"
    fi
    _arm_log "verify: installed fence-unit classification '$got' agrees with the DRY_RUN intent (render→verify, not render→hope)"
}

# ── pairing token (§2.1-rev2.1 conditions 2–3, v0.7 form) ───────────────────────────────────────
# FORMAT — the grep-consumers rule applies: spare-side consumption is Block 6, and Block-6
# spares will parse THIS exact shape; never change a field silently:
#   v0.7|gen=<N>|watchdog=<WatchdogSec>|relinquish_bound=<EXPECTED_PRIMARY_SELF_FENCE_SECS+SELF_FENCE_MARGIN_SECS>|fence=<real|page-only>|host=<hostname>|<crc>
# crc = `cksum` of the payload before the last field — INTEGRITY (against copy/paste
# truncation), NOT security: anyone can recompute it; it authenticates nothing.
_arm_token() {
    local genf="$ARM_STATE_DIR/arm-generation" gen tmp watchdog bound payload crc host _locked=""
    mkdir -p "$ARM_STATE_DIR" 2>/dev/null
    # 5.3 panel fix round (A12): the read-increment-write below runs under a bounded flock on a
    # state-dir lockfile when flock exists (P3 already probed and announced the flock posture).
    # NAMED RESIDUAL: with flock absent or -w-less (busybox — WARNed loudly at P3), two
    # simultaneous ceremonies can still race to the same generation; the arm is an operator
    # ceremony, not a daemon path, and the P3 WARN is the posture statement for such hosts.
    if command -v flock >/dev/null 2>&1; then
        if ( exec 9>"$ARM_STATE_DIR/.arm-generation.lock" ) 2>/dev/null; then
            exec 9>"$ARM_STATE_DIR/.arm-generation.lock"
            if flock -w 5 9 2>/dev/null; then
                _locked=1
            else
                _arm_warn "could not take the arm-generation lock within 5s — proceeding UNLOCKED (a concurrent 'failover arm' may collide on the generation; re-run to be sure the printed gen is unique)"
            fi
        fi
    fi
    gen=$(cat "$genf" 2>/dev/null)
    case "$gen" in
        ''|*[!0-9]*)
            [[ -e "$genf" ]] && _arm_warn "arm-generation file held garbage — resetting to 0 before the bump"
            gen=0 ;;
    esac
    gen=$((gen + 1))
    tmp="$genf.tmp.$$"
    if printf '%s\n' "$gen" > "$tmp" 2>/dev/null && mv -f "$tmp" "$genf" 2>/dev/null; then :; else
        rm -f "$tmp" 2>/dev/null
        _arm_refuse "TOKEN-persist" "could not persist the bumped config-generation counter at $genf — the units ARE installed, but the arm REFUSES to complete without printing a fresh pairing token ('re-pair every spare' is ceremony, §2.1-rev2.1 condition 2)" "make $ARM_STATE_DIR writable, then RE-RUN 'failover arm' to completion (the re-run re-bumps the generation and prints the token)"
    fi
    # 5.3 panel fix round (A10): `mv` onto a pre-existing DIRECTORY at $genf returns 0 while
    # relocating the tmp INSIDE it — persist is only real if the counter is now a REGULAR FILE
    # holding exactly the bumped value (verify after the mv; the claim never exceeds the check).
    if [[ ! -f "$genf" ]] || [[ "$(cat "$genf" 2>/dev/null)" != "$gen" ]]; then
        _arm_refuse "TOKEN-persist" "the config-generation counter did not persist: $genf is not a regular file holding $gen after the write (a pre-existing directory at that path swallows the mv while reporting success)" "inspect $genf, clean it BY HAND (this script never uses rm -rf), make $ARM_STATE_DIR writable, then RE-RUN 'failover arm' to completion"
    fi
    [[ -n "$_locked" ]] && exec 9>&-
    # read the attested properties from the INSTALLED unit (verify, not assume)
    watchdog=$(grep '^WatchdogSec=' "$ARM_SYSTEMD_DIR/$MONITOR_UNIT_NAME" 2>/dev/null | head -1 | cut -d= -f2)
    [[ -n "$watchdog" ]] || _arm_refuse "TOKEN-watchdog" "cannot read WatchdogSec= from the installed monitor unit at $ARM_SYSTEMD_DIR/$MONITOR_UNIT_NAME — the token must attest the INSTALLED value, not a guess" "inspect the monitor unit (was it edited?), re-run 'failover arm'"
    bound=$((EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS))
    host=$(hostname 2>/dev/null); host="${host:-unknown-host}"
    payload="v0.7|gen=$gen|watchdog=$watchdog|relinquish_bound=$bound|fence=$ARM_INTENT|host=$host"
    # v0.7 (Block 6.1): the crc is emitted THROUGH the same _pairing_crc helper the P5 intake
    # verifies with (and the daemons' [proof-gate] twin copy re-verifies with) — one algorithm,
    # structurally incapable of emit↔intake drift (test_proof_gate round-trips a shipped-arm
    # token through the shipped intake and cmp's the helper across all three files).
    crc=$(_pairing_crc "$payload")
    case "$crc" in ''|*[!0-9]*) _arm_refuse "TOKEN-crc" "cksum failed — cannot produce the token's integrity field" "ensure coreutils/busybox cksum is on PATH, then re-run 'failover arm'" ;; esac
    _arm_log "pairing token (§2.1-rev2.1 conditions 2–3 — hand this line to EVERY spare; re-pair on every arm; Block-6 spares validate freshness at their own arm):"
    printf '%s|%s\n' "$payload" "$crc"
}

# ── main: preconditions → probe → install → verify → token ──────────────────────────────────────
main() {
    _arm_log "failover arm — the v0.7 Block 5.3 ceremony (preconditions → probe → install → verify → token)"
    _arm_detect_role_env
    _pre_state_dir_check      # P0 (Block 6.3.1 D5): ARM_STATE_DIR must be its own resolved path (the daemon's R-SYM rule mirrored) — REFUSE[STATE-dir-*] before any write or install
    _pre_v07_check
    _pre_socat_check
    _pre_flock_check
    _pre_identity_check
    _announce_arm_state
    _pre_pairing_intake       # P5 (Block 6.1): pairing-token intake + zero-stake verification — spare (standby-role) arms only; REFUSE[P5-*] on crc/shape, bound-vs-delay, staked-"unstaked"/cannot-verify
    _pre_g2_vantage_probe     # P6 (Block 6.2 panel fix round): G2 vantage batch capability + resolved distinctness — spare arms with PRIMARY_UNSTAKED_PUBKEY only; REFUSE[P6-batch] / REFUSE[P6-vantage]
    _arm_probe
    _arm_install
    _arm_verify
    _arm_token
    _arm_log "ARMED ($ARM_INTENT): ceremony complete — the pairing token above goes to EVERY spare (re-pair is ceremony, not advice)."
    _arm_g2_summary           # (Block 6.2 C1): the shared-vantage DEGRADATION, re-stated on the final screen (silent when the vantages are separate)
    _arm_pairing_summary      # (Block 6.1): §2.7 (c) — the pairing posture is the LAST thing on the operator's screen (spare arms only)
}

main "$@"
