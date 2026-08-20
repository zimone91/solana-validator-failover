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
    crc=$(printf '%s' "$payload" | cksum 2>/dev/null | awk '{print $1}')
    case "$crc" in ''|*[!0-9]*) _arm_refuse "TOKEN-crc" "cksum failed — cannot produce the token's integrity field" "ensure coreutils/busybox cksum is on PATH, then re-run 'failover arm'" ;; esac
    _arm_log "pairing token (§2.1-rev2.1 conditions 2–3 — hand this line to EVERY spare; re-pair on every arm; Block-6 spares validate freshness at their own arm):"
    printf '%s|%s\n' "$payload" "$crc"
}

# ── main: preconditions → probe → install → verify → token ──────────────────────────────────────
main() {
    _arm_log "failover arm — the v0.7 Block 5.3 ceremony (preconditions → probe → install → verify → token)"
    _arm_detect_role_env
    _pre_v07_check
    _pre_socat_check
    _pre_flock_check
    _pre_identity_check
    _announce_arm_state
    _arm_probe
    _arm_install
    _arm_verify
    _arm_token
    _arm_log "ARMED ($ARM_INTENT): ceremony complete — the pairing token above goes to EVERY spare (re-pair is ceremony, not advice)."
}

main "$@"
