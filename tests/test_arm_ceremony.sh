#!/bin/bash
# v0.7 (Block 5.3): the `failover arm` CEREMONY — failover-arm.sh driven as a SUBPROCESS behind a
# mock PATH, with EVERY root env-overridden into mktemp. HARD BOUNDARY (doubled for this slice —
# this suite tests the INSTALLER of the fence, whose execution happens only at the v0.7 rollout):
# every actuator is a stub (`systemctl`, `timeout`, `sleep`, `flock`, `socat`, `pgrep`); NO test
# writes /etc or /run/systemd or invokes a real systemd — all five roots (ARM_SYSTEMD_DIR,
# ARM_RUNTIME_DIR, ARM_INSTALL_DIR, FENCE_MARKER_DIR, ARM_STATE_DIR) point at mktemp in every
# run; case (B) is the in-suite grep-proof.
#
# Scenario PATH (fix round 2, reviewer blocker): "$STUB_DIR:$TOOLDIR" and NOTHING ELSE — the
# old scheme appended /usr/bin:/bin, which made every DELETION stub (STUB_NOSOCAT, STUB_NOFLOCK)
# vacuous exactly where the tool exists (every real validator host): `command -v socat` found
# /usr/bin/socat and (2a)/(2b) ARMED with a printed token where REFUSE[P2-socat] was expected —
# observed red on a tool-bearing machine (docker bash:5.2 + socat/flock/util-linux; the
# reviewer's exact failure, 83/85). TOOLDIR carries symlinks to the REAL host binaries for the
# arm's NON-ACTUATOR external commands only; deleting a tool = it is in NEITHER dir; the
# actuators live ONLY in the stub dirs. (B6)/(B7) are the standing non-vacuity tripwires.
#
# Cases (TASK-block53 + the 5.3 panel fix round TASK-block53-fixes):
#   (1)  P1 self-v0.7: (a) installed daemon WITHOUT the patsub guard → refuse + upgrade-then-arm
#        fix text; (b) NO daemon installed → refuse + install-first fix; (e) guard ONLY in a
#        comment → refuse (comment-stripped grep — panel A1); (f–i) WATCHDOG CAPABILITY gate:
#        a v0.6.10-shaped daemon (guard, zero petting) → REFUSE[P1-capability] naming the trap
#        (READY-less monitor → fence on a healthy validator), thresholds live, OK-line scoped
#   (2)  P2 socat absent (in NEITHER stub dir NOR TOOLDIR — real deletion, non-vacuous on
#        tool-bearing hosts) → refuse + the exact install command; no fallback offered
#   (3)  P3 flock: (a) busybox flock (-w unsupported) → the reviewer's WARN verbatim + PROCEED
#        (asserted NOT refuse); (c) flock absent entirely → its own WARN + proceed — now
#        exercised UNCONDITIONALLY on both legs (deletion is real under the TOOLDIR scheme)
#   (4)  P4 unit --identity (the 5.1 proc-gone residual, discharged at arm):
#        (a) mismatch + real intent → refuse + fix names --identity and the unstaked path;
#        (b) mismatch + page-only intent → WARN + proceed; (c) frankendancer → stop-only posture
#        WARN + skip + proceed; (d) match + real intent → precondition passes;
#        (e) VALIDATOR_UNIT unset → the fence's cgroup detection locates the unit (reuse proven
#        behaviorally); (f) multi-line ExecStart (backslash continuations) parsed;
#        (h–o) the KEY, not the path string (panel A8): symlink-to-STAKED → refuse with the
#        derived pubkey + resolved target; keygen unavailable / UNSTAKED_PUBKEY unset →
#        REFUSE[P4-unverifiable] + manual keygen command + the documented dangerous override
#        ARM_ACCEPT_UNVERIFIED_IDENTITY=1 (arms with a LOUD WARN; never covers a PROVEN
#        mismatch); page-only needs none of it; multiple --identity → LAST wins, said aloud
#   (5)  P5 one-arm-state announcement: real vs page-only, printed with the §2.3 why
#   (6)  probe success flow ORDER: reload → start → READY-pet line → marker line → cleanup;
#        probe pair rendered from the REAL skels (snapshot at start-time asserts Type=notify,
#        WatchdogSec=2s, OnFailure=probe-fence, socat READY pet; probe-fence = /bin/touch marker);
#        transient units REMOVED after + second reload; (6f) stale marker FILE announced +
#        removed, probe re-proves
#   (7)  probe timeout (no marker) → refuse + guidance (NotifyAccess / systemd version / socat)
#        + cleanup still performed + NO install happened; (7d) stale marker + DEAD wiring →
#        cleaned then refused (panel M-A killed); (7e/7f) DIRECTORY at the marker path →
#        REFUSE[PROBE-marker-stale] + clean-by-hand fix, no rm -rf anywhere in the arm
#   (8)  probe start fails (READY pet never landed) → refuse naming the §2.6 self-test
#   (9)  install: exactly ONE fence unit (real) + stale page-only sibling REMOVED + monitor
#        rendered with the role daemon + role env (no <role> placeholder left) + fence bodies
#        placed into ARM_INSTALL_DIR + enable monitor recorded + validator unit NEVER
#        started/restarted/stopped + post-verify agreement line; (9b) standby role via ARM_ROLE;
#        (9c) both env files without ARM_ROLE → refuse; (9e2) the enable claim is SCOPED to the
#        Block-5 unit set; (9i) '&'/'\'/'|' paths render BYTE-EXACT (structural replace, no
#        sed — panel A3/A13/A14/A15) + post-render content verification; (9j) directory at a
#        render dest → REFUSE[RENDER-dest] (panel A6); (9k) un-removable sibling + REAL intent
#        → REFUSE[INSTALL-sibling] (panel A2)
#   (10) DRY_RUN flip re-arm re-aligns: real → page-only, sibling removed, gen bumped
#   (11) pairing token: exact v0.7 shape, gen bump across runs, crc re-computed and verified,
#        printed before the completion line; (11c) gen persistence failure → REFUSES to complete
#        (exit 1, no token line, no ARMED line); (11e) directory at the gen file → verify-after-
#        mv refuses (panel A10); (11f) the bump runs under flock -w 5 (panel A12)
#   (12) verify gate: un-removable stale sibling (directory) → render→verify refuse
#   (15) legacy-monitor retirement (fix round 2, reviewer blocker): the wizards' pre-fence
#        units (solana-failover.service / solana-failover-standby.service — N-is-all by grep
#        over both wizards) are stop+disable+VERIFY retired BEFORE the new enable; stop
#        failure / verify disagreement → REFUSE[INSTALL-legacy] + manual commands, no enable,
#        no token; absent → zero legacy stop/disable events (both names still PROBED);
#        the unit FILE stays on disk (operator cleanup, said aloud)
#   (16) P0 state directory (Block 6.3.1 D5 — the daemon's R-SYM rule mirrored): a symlinked
#        ARM_STATE_DIR, a symlinked ancestor, every non-resolved spelling (trailing '/', '//', '/./',
#        '/../', relative) and a FILE at the path → REFUSE[STATE-dir-*] before any write or install;
#        a missing directory is created and passes; placement; arm ↔ daemon agreement on 7 spellings
#   (13) reuse parity: _validator_pid + _detect_validator_unit BYTE-IDENTICAL arm ↔ fence
#   (14) bash -n + shellcheck (if installed)
#   (B)  boundary grep-proof: canonical /etc + /run/systemd paths untouched by the whole run;
#        stub systemctl shadows any real one; arm's only /etc//run defaults live in the
#        ARM_*_DIR:- expansions; no systemd-run anywhere; (B6)/(B7) deletion-stub non-vacuity
#        (socat/flock resolve NOWHERE under the deletion PATHs, even on tool-bearing hosts)
#   (M)  mutation controls (each refuse-gate neutered → its case would go RED): M1 patsub, M2
#        socat, M3 identity, M4 probe-marker, M5 verify, M6 pre-probe stale clean (panel M-A),
#        M7 capability, M8 unverifiable-identity, M9 sibling, M10 render-verify tripwire,
#        M11 legacy-retire (neutered → the dual-monitor arm completes, observed), M12 P0
#        state-dir symlink (neutered → the gen counter lands through the link, observed).
#        Survivors named at the end.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
ARM="$HARNESS_DIR/failover-arm.sh"
FENCE="$HARNESS_DIR/systemd/failover-fence.sh"
SKEL_DIR="$HARNESS_DIR/systemd"
BASH_BIN="${BASH:-/bin/bash}"

# ── stub PATHs (four variants; every stub records into $EVENTS) ─────────────────────────────────
STUB_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/arm-stubs.XXXXXX")
STUB_DIR="$STUB_PARENT/full"
STUB_NOSOCAT="$STUB_PARENT/nosocat"
STUB_BUSYFLOCK="$STUB_PARENT/busyflock"
STUB_NOFLOCK="$STUB_PARENT/noflock"
mkdir -p "$STUB_DIR" "$STUB_NOSOCAT" "$STUB_BUSYFLOCK" "$STUB_NOFLOCK"

cat > "$STUB_DIR/systemctl" <<'STUB'
#!/bin/sh
echo "systemctl $*" >> "$EVENTS"
case "$*" in
    daemon-reload)
        rc=$(cat "$MOCK_DIR/rc.reload" 2>/dev/null); exit "${rc:-0}" ;;
    cat\ *)
        if [ -f "$MOCK_DIR/unitfile" ]; then cat "$MOCK_DIR/unitfile"; exit 0; fi
        exit 1 ;;
    start\ solana-failover-arm-probe.service)
        # snapshot the runtime dir AT START TIME (the transient pair is cleaned afterwards)
        rm -rf "$MOCK_DIR/runtime.at-start"
        cp -R "$ARM_RUNTIME_DIR" "$MOCK_DIR/runtime.at-start" 2>/dev/null
        rc=$(cat "$MOCK_DIR/rc.probestart" 2>/dev/null); rc=${rc:-0}
        # rc 0 = READY landed (Type=notify start returns at READY — the socat self-test); the
        # OnFailure marker then appears only when the scenario says the wiring works.
        if [ "$rc" = "0" ] && [ -f "$MOCK_DIR/probe.fires" ]; then
            touch "$FENCE_MARKER_DIR/arm-probe.fired"
        fi
        exit "$rc" ;;
    reset-failed*) exit 0 ;;
    enable\ *)
        rc=$(cat "$MOCK_DIR/rc.enable" 2>/dev/null); exit "${rc:-0}" ;;
    stop\ *)
        # legacy-monitor retirement (15): per-unit rc via rc.stop.<unit>; success clears the
        # active flag UNLESS stopnoop.<unit> exists (the verify-disagreement scenario: rc 0,
        # nothing actually stopped). $2 is the unit — NOT ${*#stop }: prefix-removal on $*
        # applies per positional parameter in sh, leaving the verb in place (found red here).
        u="$2"
        rc=$(cat "$MOCK_DIR/rc.stop.$u" 2>/dev/null); rc=${rc:-0}
        if [ "$rc" = "0" ] && [ ! -f "$MOCK_DIR/stopnoop.$u" ]; then rm -f "$MOCK_DIR/active.$u"; fi
        exit "$rc" ;;
    disable\ *)
        u="$2"
        rc=$(cat "$MOCK_DIR/rc.disable.$u" 2>/dev/null); rc=${rc:-0}
        if [ "$rc" = "0" ] && [ ! -f "$MOCK_DIR/disablenoop.$u" ]; then rm -f "$MOCK_DIR/enabled.$u"; fi
        exit "$rc" ;;
    is-active\ *)
        u="$2"
        if [ -f "$MOCK_DIR/active.$u" ]; then echo active; exit 0; fi
        echo inactive; exit 3 ;;
    is-enabled\ *)
        u="$2"
        if [ -f "$MOCK_DIR/enabled.$u" ]; then echo enabled; exit 0; fi
        echo not-found; exit 1 ;;
esac
exit 0
STUB

cat > "$STUB_DIR/timeout" <<'STUB'
#!/bin/sh
# shim for the bounded-call idiom `timeout -k K DUR cmd…` (same named assumption as the fence
# suite: a future bare `timeout DUR cmd…` would mis-parse here and go red LOUDLY, not silently).
shift 3
cmd="$1"; shift
exec "$cmd" "$@"
STUB

cat > "$STUB_DIR/pgrep" <<'STUB'
#!/bin/sh
echo "pgrep $*" >> "$EVENTS"
p=$(cat "$MOCK_DIR/proc" 2>/dev/null)
if [ "$p" = "1" ]; then echo 2147483647; exit 0; fi
exit 1
STUB

printf '#!/bin/sh\nexit 0\n' > "$STUB_DIR/sleep"
printf '#!/bin/sh\necho "socat $*" >> "$EVENTS"\nexit 0\n' > "$STUB_DIR/socat"
printf '#!/bin/sh\necho "flock $*" >> "$EVENTS"\nexit 0\n' > "$STUB_DIR/flock"

# solana-keygen mock (the P4 KEY verification, Block 5.3 fix round): `pubkey <path>` prints the
# FILE'S CONTENT as the pubkey — a deterministic content→pubkey map, so a symlink/mis-copied
# file at the configured path derives the pubkey of what the file ACTUALLY holds (the A8
# class). Reached via the env's SOLANA_PATH (absolute — not PATH lookup), never on the PATH.
cat > "$STUB_DIR/solana-keygen" <<'STUB'
#!/bin/sh
echo "keygen $*" >> "$EVENTS"
[ "$1" = "pubkey" ] || exit 2
[ -f "$2" ] || exit 1
tr -d '\n' < "$2"
STUB
chmod +x "$STUB_DIR"/*

# variants: no socat / busybox flock (errors on -w) / no flock
cp "$STUB_DIR"/* "$STUB_NOSOCAT/"; rm -f "$STUB_NOSOCAT/socat"
cp "$STUB_DIR"/* "$STUB_BUSYFLOCK/"
cat > "$STUB_BUSYFLOCK/flock" <<'STUB'
#!/bin/sh
echo "flock $*" >> "$EVENTS"
case "$*" in *-w*) echo "flock: unrecognized option: w" >&2; exit 1 ;; esac
exit 0
STUB
chmod +x "$STUB_BUSYFLOCK/flock"
cp "$STUB_DIR"/* "$STUB_NOFLOCK/"; rm -f "$STUB_NOFLOCK/flock"

# ── TOOLDIR: the provisioned REAL-tool dir (fix round 2, reviewer blocker) ──────────────────────
# The scenario PATH is "$STUB_DIR:$TOOLDIR" — the system path is NOT appended. TOOLDIR holds
# symlinks to the REAL host binaries for the arm's NON-ACTUATOR external commands, resolved via
# `command -v` on the HOST at suite start (works on the macOS leg and both docker legs alike).
# Deletion of a tool = it simply is not in either dir — non-vacuous on tool-bearing hosts, where
# the old appended-/usr/bin scheme let `command -v socat` escape the deletion stub (the observed
# (2a)/(2b) red: ARMED with a token where REFUSE[P2-socat] was expected).
#
# N-is-all — the arm's external commands, by comment-stripped grep over failover-arm.sh
# (2026-08-21): awk basename cat chmod cksum cp cut date dirname grep head hostname mkdir mv
# readlink rm sed tail; the /bin/sh stubs themselves add touch (systemctl stub's marker write)
# and tr (solana-keygen stub). Everything else the arm executes is a bash builtin (printf,
# command, exec, shopt, cd, pwd, [[ ]]), an absolute path ($BASH, $SOLANA_PATH/<keygen>), or an
# actuator that lives ONLY in the stub dirs (systemctl, timeout, sleep, pgrep, socat, flock).
# The REMOVAL tools (6.3.1 fix round 4 — the delta panel 3's TS3-16H-RMDIR): rm, rmdir and unlink are provisioned as
# LOGGING WRAPPERS with the host's real binary behind each (every call appended to $MOCK_DIR/rm.calls, then exec'd), not
# as bare symlinks — the arm uses only rm today; any removal it runs through PATH is REAL here as on a host (a re-added
# rmdir cleanup succeeds here too, instead of failing as "command not found"), and (16h) asserts that none ran during a
# P0 refusal.
TOOLDIR="$STUB_PARENT/tools"
mkdir -p "$TOOLDIR"
ARM_REAL_TOOLS="awk basename cat chmod cksum cp cut date dirname grep head hostname mkdir mv readlink rm rmdir sed tail touch tr unlink"
for _t in $ARM_REAL_TOOLS; do
    _tp=$(command -v "$_t" 2>/dev/null)
    if [[ -z "$_tp" || ! -x "$_tp" ]]; then
        echo "  ❌ FAIL: TOOLDIR provisioning: no real '$_t' on the host PATH — the suite cannot build its scenario PATH"
        exit 1
    fi
    case " rm rmdir unlink " in
        *" $_t "*)
            cat > "$TOOLDIR/$_t" <<EOS
#!/bin/sh
printf '%s %s\n' '$_t' "\$*" >> "\${MOCK_DIR:-/nonexistent}/rm.calls" 2>/dev/null
exec '$_tp' "\$@"
EOS
            chmod +x "$TOOLDIR/$_t" ;;
        *) ln -s "$_tp" "$TOOLDIR/$_t" ;;
    esac
done

# ── scenario plumbing ───────────────────────────────────────────────────────────────────────────
MOCK_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/arm-mocks.XXXXXX")
# v0.7 (Block 6.3.1 D5): the arm now REFUSES a state directory that is not its own resolved path
# (P0, the daemon's R-SYM rule mirrored) — so every mock root is spelled RESOLVED: macOS's TMPDIR sits
# under the /var -> /private/var symlink and ends in '/' (a '//' in the joined path)
MOCK_PARENT=$(CDPATH='' cd -P -- "$MOCK_PARENT" && pwd -P)
# a v0.7-SHAPED daemon fixture: patsub guard + the WATCHDOG CAPABILITY markers P1 requires
# (Block 5.3 fix round — the panel armed a v0.6.10 daemon: guard present, ZERO petting lines;
# P1 now requires _watchdog_active() + ≥1 READY=1 emission + ≥10 _watchdog_pet sites, all
# outside comments)
write_daemon() {
    {
        echo '#!/bin/bash'
        echo 'shopt -u patsub_replacement 2>/dev/null || true'
        echo '_watchdog_active() { [ -n "$WATCHDOG_USEC" ]; }'
        echo '_watchdog_pet() { _sd_notify "WATCHDOG=1"; }'
        echo '_sd_notify_ready() { _sd_notify "READY=1"; }'
        local _i=1
        while [ "$_i" -le 12 ]; do echo "op$_i() { _watchdog_pet; }"; _i=$((_i+1)); done
    } > "$1"
}
new_mock() {
    MOCK_DIR=$(mktemp -d "$MOCK_PARENT/m.XXXXXX")
    mkdir -p "$MOCK_DIR/etc-systemd" "$MOCK_DIR/run-systemd" "$MOCK_DIR/opt" \
             "$MOCK_DIR/markers" "$MOCK_DIR/state"
    EVENTS="$MOCK_DIR/events"; : > "$EVENTS"
    echo 0 > "$MOCK_DIR/proc"
    touch "$MOCK_DIR/probe.fires"          # default: the wiring works (probe marker appears)
    # default installed daemon (primary): v0.7-shaped (guard + watchdog capability)
    write_daemon "$MOCK_DIR/opt/solana-primary-failover.sh"
    # the UNSTAKED keypair file EXISTS and its content IS its mock pubkey (the keygen stub's
    # content→pubkey map); the env pins the same value as UNSTAKED_PUBKEY → P4's KEY check
    # passes on an honest host and fails when the file is a symlink/mis-copy (A8)
    printf 'UNSTAKEDPUBKEY42' > "$MOCK_DIR/opt/unstaked.json"
    write_env
    write_unitfile "--identity $MOCK_DIR/opt/unstaked.json"
}
# env-file fixture (later lines override earlier on source)
write_env() {
    {
        echo 'DRY_RUN=false'
        echo 'VALIDATOR_TYPE="agave"'
        echo "UNSTAKED_KEYPAIR=\"$MOCK_DIR/opt/unstaked.json\""
        echo 'UNSTAKED_PUBKEY="UNSTAKEDPUBKEY42"'
        echo "SOLANA_PATH=\"$STUB_DIR\""
        echo 'VALIDATOR_UNIT="sol-test.service"'
        echo 'EXPECTED_PRIMARY_SELF_FENCE_SECS=30'
        echo 'SELF_FENCE_MARGIN_SECS=30'
        local kv
        for kv in "$@"; do echo "$kv"; done
    } > "$MOCK_DIR/opt/failover.env"
}
write_unitfile() {   # $1 = the --identity clause (or empty for none)
    {
        echo '[Service]'
        echo "ExecStart=/usr/bin/agave-validator --ledger /l $1 --rpc-port 8899"
    } > "$MOCK_DIR/unitfile"
}
# run_arm [VAR=val …] — subprocess run, clean env, stub PATH, ALL roots in mktemp (the boundary).
run_arm() {
    local script="${ARM_OVERRIDE:-$ARM}"
    # The scenario PATH has exactly ONE construction site — this assignment; the env -i below
    # consumes it, and (B6)/(B7) assert against the value ACTUALLY used (snapshotted at the
    # deletion cases (2a)/(3c)), never a locally rebuilt copy (post-GO reviewer correction:
    # they re-appended /usr/bin:/bin here and the self-built tripwires stayed green while
    # (2a)/(2b)/(3c) went red — an assertion living apart from what it describes, the same
    # class as the T-b banner and the OnFailure blind comment). Residual, named: an edit that
    # bypasses the variable AT the env -i line below evades (B6)/(B7) — but lands red in
    # (2a)/(2b)/(3c) themselves on any tool-bearing host; the pair covers both edit sites.
    _LAST_ARM_PATH="${ARM_PATH:-$STUB_DIR}:$TOOLDIR"
    env -i PATH="$_LAST_ARM_PATH" \
        EVENTS="$EVENTS" MOCK_DIR="$MOCK_DIR" \
        ARM_SYSTEMD_DIR="$MOCK_DIR/etc-systemd" \
        ARM_RUNTIME_DIR="$MOCK_DIR/run-systemd" \
        ARM_INSTALL_DIR="${INSTALL_OVERRIDE:-$MOCK_DIR/opt}" \
        FENCE_MARKER_DIR="$MOCK_DIR/markers" \
        ARM_STATE_DIR="$MOCK_DIR/state" \
        "$@" "$BASH_BIN" "$script" > "$MOCK_DIR/out" 2>&1
    RC=$?
}
trace() {   # ordered token trace from the event log (pgrep/socat/flock noise dropped)
    local line tok out=""
    while IFS= read -r line; do
        tok=""
        case "$line" in
            "systemctl daemon-reload"*)  tok=reload ;;
            "systemctl cat"*)            tok=ident-cat ;;
            "systemctl start solana-failover-arm-probe.service") tok=start-probe ;;
            "systemctl reset-failed"*)   tok=reset ;;
            "systemctl enable"*)         tok=enable ;;
            # legacy-monitor retirement (15): the SANCTIONED stop/disable set — exactly the two
            # wizard unit names; anything else stopped/started/restarted is still FORBIDDEN
            # (the validator unit must never be touched). is-active/is-enabled probes are
            # read-only noise (asserted per-case via $EVENTS line numbers, not the trace).
            "systemctl stop solana-failover.service"|"systemctl stop solana-failover-standby.service") tok=legacy-stop ;;
            "systemctl disable solana-failover.service"|"systemctl disable solana-failover-standby.service") tok=legacy-disable ;;
            "systemctl start"*|"systemctl restart"*|"systemctl stop"*) tok=FORBIDDEN ;;
        esac
        [[ -n "$tok" ]] && out="${out}${out:+,}${tok}"
    done < "$EVENTS"
    printf '%s' "$out"
}
token_line() { grep '^v0\.7|gen=' "$MOCK_DIR/out" | tail -1; }

title_banner "failover arm ceremony (v0.7 Block 5.3) — preconditions, probe, install, verify, token"
EXPECT_HAPPY="ident-cat,reload,start-probe,reset,reload,reload,enable"

# ── (1) P1: self v0.7 check (patsub guard = the rev3.2 release condition, self-enforced) ────────
echo ""; echo "─── (1) P1: daemon without the patsub guard → refuse + upgrade-then-arm fix ───"
new_mock
printf '#!/bin/bash\necho v0.6.9 daemon, no guard\n' > "$MOCK_DIR/opt/solana-primary-failover.sh"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P1-patsub\]' "$MOCK_DIR/out" && grep -q 'patsub_replacement guard' "$MOCK_DIR/out"; then
    ok "(1a) refused: installed daemon lacks the patsub guard (host NOT on v0.7)"
else
    bad "(1a) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q 'upgrade-then-arm, per host, no exceptions' "$MOCK_DIR/out" && grep -q 'FIX:' "$MOCK_DIR/out"; then
    ok "(1b) the exact fix printed: upgrade this host to v0.7 FIRST (rev3.2 release condition wording)"
else
    bad "(1b) fix text missing: $(grep 'FIX' "$MOCK_DIR/out" 2>/dev/null)"
fi
if [[ ! -e "$MOCK_DIR/etc-systemd/solana-failover-monitor.service" ]] && ! ls "$MOCK_DIR/etc-systemd" 2>/dev/null | grep -q .; then
    ok "(1c) refusal installed NOTHING (ARM_SYSTEMD_DIR empty)"
else
    bad "(1c) units appeared despite refusal: $(ls "$MOCK_DIR/etc-systemd" 2>/dev/null)"
fi
new_mock
rm -f "$MOCK_DIR/opt/solana-primary-failover.sh"
run_arm ARM_ROLE=primary
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[' "$MOCK_DIR/out" && grep -qi 'install v0.7 first' "$MOCK_DIR/out"; then
    ok "(1d) no daemon installed → refuse + install-first fix"
else
    bad "(1d) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# Block 5.3 fix round (panel A1): a guard that lives only in a COMMENT is not code
new_mock
printf '#!/bin/bash\n# TODO port the guard: shopt -u patsub_replacement (not yet applied)\necho v0.6.9-ish daemon\n' > "$MOCK_DIR/opt/solana-primary-failover.sh"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P1-patsub\]' "$MOCK_DIR/out"; then
    ok "(1e) guard present ONLY in a comment → REFUSE[P1-patsub] (the grep is comment-stripped — A1 dead)"
else
    bad "(1e) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# Block 5.3 fix round (panel P1 BLOCKER): a v0.6.10-shaped daemon — REAL guard, ZERO watchdog
# capability. The installed monitor unit would never go READY → start timeout → the REAL fence
# fires on a HEALTHY validator; the probe cannot catch it (transient units, hardcoded pet).
new_mock
printf '#!/bin/bash\nshopt -u patsub_replacement 2>/dev/null || true\necho v0.6.10 daemon: guard present, no watchdog\n' > "$MOCK_DIR/opt/solana-primary-failover.sh"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P1-capability\]' "$MOCK_DIR/out" && grep -q 'pre-v0.7 daemon' "$MOCK_DIR/out" && grep -q 'never go READY' "$MOCK_DIR/out" && grep -qi 'HEALTHY validator' "$MOCK_DIR/out"; then
    ok "(1f) v0.6.10 daemon (guard, zero petting) → REFUSE[P1-capability] naming the trap (READY-less monitor → fence on a healthy validator)"
else
    bad "(1f) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# fix round 2 nit: the refusal prints THIS daemon's MEASURED counts against the REQUIRED floors
# and carries NO static shipped-daemon figures (the old "carry 7 and 35+" disagreed with the
# reviewer's count of the same daemons — illustrative numbers drift; measurements do not)
if grep -q 'MEASURED (this daemon, outside comments)' "$MOCK_DIR/out" && grep -q 'READY=1 lines: 0' "$MOCK_DIR/out" && grep -q '_watchdog_pet lines: 0' "$MOCK_DIR/out" && grep -q 'REQUIRED: ≥1, ≥1, ≥10' "$MOCK_DIR/out" && ! grep -q 'shipped v0.7 daemons carry' "$MOCK_DIR/out"; then
    ok "(1f2) the refusal prints MEASURED (0/0 here) vs REQUIRED (≥1/≥1/≥10) dynamically — no static shipped-daemon figures anywhere in the text"
else
    bad "(1f2) refuse text: $(grep 'REFUSE\[P1-capability\]' "$MOCK_DIR/out" 2>/dev/null | head -1 | cut -c1-220)"
fi
if [[ ! -e "$MOCK_DIR/etc-systemd/solana-failover-monitor.service" ]] && ! ls "$MOCK_DIR/etc-systemd" 2>/dev/null | grep -q .; then
    ok "(1g) the P1-capability refusal installed NOTHING"
else
    bad "(1g) units appeared despite refusal: $(ls "$MOCK_DIR/etc-systemd" 2>/dev/null)"
fi
# thresholds are LIVE, not decorative: capability def + READY present but < 10 pet sites
new_mock
{
    echo '#!/bin/bash'
    echo 'shopt -u patsub_replacement 2>/dev/null || true'
    echo '_watchdog_active() { [ -n "$WATCHDOG_USEC" ]; }'
    echo '_sd_notify "READY=1"'
    echo 'a() { _watchdog_pet; }'
    echo 'b() { _watchdog_pet; }'
} > "$MOCK_DIR/opt/solana-primary-failover.sh"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P1-capability\]' "$MOCK_DIR/out" && grep -q '_watchdog_pet lines: 2' "$MOCK_DIR/out"; then
    ok "(1h) capability THRESHOLDS live: only 2 _watchdog_pet sites (< 10) → REFUSE[P1-capability], and the text carries the measured 2"
else
    bad "(1h) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# claim=check: the P1 OK line claims exactly what was verified (guard = pages; capability = READY+pets)
new_mock
run_arm
if [[ "$RC" == "0" ]] && grep -q 'precondition 1 OK' "$MOCK_DIR/out" && grep 'precondition 1 OK' "$MOCK_DIR/out" | grep -q 'patsub guard' && grep 'precondition 1 OK' "$MOCK_DIR/out" | grep -q 'watchdog capability'; then
    ok "(1i) P1 OK line scopes its claim: patsub guard (pages) AND watchdog capability (READY + pets) both named"
else
    bad "(1i) rc=$RC P1 line: $(grep 'precondition 1' "$MOCK_DIR/out" 2>/dev/null)"
fi

# ── (2) P2: socat absent → refuse with the install command (SOLE armed transport, §2.6) ─────────
echo ""; echo "─── (2) P2: socat absent → refuse + exact install command, NO fallback ───"
new_mock
ARM_PATH="$STUB_NOSOCAT" run_arm
_SNAP_PATH_NOSOCAT="$_LAST_ARM_PATH"   # (B6) asserts THIS exact string — the PATH this run used
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P2-socat\]' "$MOCK_DIR/out" && grep -q 'apt-get install -y socat' "$MOCK_DIR/out"; then
    ok "(2a) refused: socat missing; the install command is the printed fix"
else
    bad "(2a) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q 'SOLE armed transport' "$MOCK_DIR/out"; then
    ok "(2b) refusal names socat as the SOLE armed transport (§2.6) — no fallback offered"
else
    bad "(2b) transport wording missing"
fi

# ── (3) P3: flock -w probe (reviewer, 5.2 GO) — WARN LOUDLY, do not refuse ──────────────────────
echo ""; echo "─── (3) P3: busybox flock → the exact WARN + PROCEED; absent flock → WARN + proceed ───"
new_mock
ARM_PATH="$STUB_BUSYFLOCK" run_arm
if [[ "$RC" == "0" ]] && grep -q 'flock has no -w on this host (busybox?)' "$MOCK_DIR/out" && grep -q 'loud lockless exit-1 path' "$MOCK_DIR/out"; then
    ok "(3a) busybox flock: the reviewer's WARN verbatim, said aloud AT ARM"
else
    bad "(3a) rc=$RC out: $(grep -i flock "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
if [[ -n "$(token_line)" ]]; then
    ok "(3b) …and the arm PROCEEDED to completion (WARN, not refuse — the v0.7 posture)"
else
    bad "(3b) arm did not complete under busybox flock (rc=$RC)"
fi
# flock-ABSENT branch — UNCONDITIONAL since fix round 2: under the TOOLDIR scheme deletion is
# real on every leg (flock is simply in NEITHER dir; a host /usr/bin/flock is unreachable —
# the old platform-conditional skip existed only because the appended system path made a real
# flock un-deletable on tool-bearing hosts).
new_mock
ARM_PATH="$STUB_NOFLOCK" run_arm
_SNAP_PATH_NOFLOCK="$_LAST_ARM_PATH"   # (B7) asserts THIS exact string — the PATH this run used
if [[ "$RC" == "0" ]] && grep -q 'WARN: flock not found' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
    ok "(3c) flock absent entirely (in NEITHER stub dir NOR TOOLDIR — exercised on BOTH legs now): its own WARN (no instance lock at all) + proceed"
else
    bad "(3c) rc=$RC out: $(grep -i flock "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi

# ── (4) P4: unit --identity verification (the 5.1 residual, discharged at arm) ──────────────────
echo ""; echo "─── (4) P4: --identity mismatch → real refused / page-only warned; fd posture; cgroup reuse ───"
new_mock
write_unitfile "--identity /somewhere/else/staked.json"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P4-identity\]' "$MOCK_DIR/out" && grep -q 'UNSOUND' "$MOCK_DIR/out"; then
    ok "(4a) mismatch + REAL intent → refused (fenced-demoted would be unsound under Restart=always)"
else
    bad "(4a) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q -- '--identity' "$MOCK_DIR/out" && grep -q "$MOCK_DIR/opt/unstaked.json" "$MOCK_DIR/out"; then
    ok "(4b) the fix names --identity and the configured UNSTAKED keypair path"
else
    bad "(4b) fix text: $(grep 'FIX' "$MOCK_DIR/out" 2>/dev/null)"
fi
new_mock
write_env 'DRY_RUN=true'
write_unitfile "--identity /somewhere/else/staked.json"
run_arm
if [[ "$RC" == "0" ]] && grep -q 'WARN: unit --identity verification FAILED' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
    ok "(4c) mismatch + PAGE-ONLY intent → WARN + proceed (nothing on that dispatch path can demote/stop)"
else
    bad "(4c) rc=$RC out: $(grep -i 'identity' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
new_mock
write_env 'VALIDATOR_TYPE="frankendancer"'
write_unitfile ""     # no --identity anywhere: the check must be SKIPPED, not failed
run_arm
if [[ "$RC" == "0" ]] && grep -q 'STOP-ONLY' "$MOCK_DIR/out" && grep -qi 'skipping the unit --identity verification' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
    ok "(4d) frankendancer → v0.7 stop-only posture WARN, check skipped, arm proceeds"
else
    bad "(4d) rc=$RC out: $(grep -i 'franken\|STOP-ONLY' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
new_mock
run_arm
if [[ "$RC" == "0" ]] && grep -q 'precondition 4 OK' "$MOCK_DIR/out" && grep -q 'systemctl cat sol-test.service' "$EVENTS"; then
    ok "(4e) match + real intent → precondition passes via systemctl cat on the configured unit"
else
    bad "(4e) rc=$RC out: $(grep -i 'precondition 4' "$MOCK_DIR/out" 2>/dev/null)"
fi
new_mock
grep -v VALIDATOR_UNIT "$MOCK_DIR/opt/failover.env" > "$MOCK_DIR/opt/failover.env.t" && mv "$MOCK_DIR/opt/failover.env.t" "$MOCK_DIR/opt/failover.env"
echo 1 > "$MOCK_DIR/proc"
mkdir -p "$MOCK_DIR/proc_root/2147483647"
printf '0::/system.slice/sol-cg.service/payload\n' > "$MOCK_DIR/proc_root/2147483647/cgroup"
write_unitfile "--identity /somewhere/else/staked.json"
run_arm FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
if [[ "$RC" == "1" ]] && grep -q 'systemctl cat sol-cg.service' "$EVENTS" && grep -q 'sol-cg.service' "$MOCK_DIR/out"; then
    ok "(4f) VALIDATOR_UNIT unset → the fence's cgroup detection located sol-cg.service (reuse, not reinvention) — and the mismatch still refused"
else
    bad "(4f) rc=$RC events: $(grep 'systemctl cat' "$EVENTS" 2>/dev/null) out: $(tail -2 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
new_mock
{
    echo '[Service]'
    echo 'ExecStart=/usr/bin/agave-validator \'
    echo '  --ledger /l \'
    printf '  --identity %s \\\n' "$MOCK_DIR/opt/unstaked.json"
    echo '  --rpc-port 8899'
} > "$MOCK_DIR/unitfile"
run_arm
if [[ "$RC" == "0" ]] && grep -q 'precondition 4 OK' "$MOCK_DIR/out"; then
    ok "(4g) multi-line ExecStart (backslash continuations) folded and verified"
else
    bad "(4g) rc=$RC out: $(grep -i 'identity' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
# ── Block 5.3 fix round: P4 verifies the KEY, not the path string (panel A8 BLOCKER) ──
# the double-sign P4 exists to prevent: unit names the configured PATH, but the path is a
# symlink to the STAKED key — after a fence demote, Restart=always returns the validator STAKED
new_mock
mkdir -p "$MOCK_DIR/keys"; printf 'STAKEDPUBKEY99' > "$MOCK_DIR/keys/STAKED.json"
rm -f "$MOCK_DIR/opt/unstaked.json"
ln -s "$MOCK_DIR/keys/STAKED.json" "$MOCK_DIR/opt/unstaked.json"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P4-identity\]' "$MOCK_DIR/out" && grep -q 'STAKEDPUBKEY99' "$MOCK_DIR/out" && grep -q 'UNSTAKEDPUBKEY42' "$MOCK_DIR/out"; then
    ok "(4h) symlink-to-STAKED at the configured path → REFUSE[P4-identity]: the KEY was derived (keygen) and mismatches UNSTAKED_PUBKEY (A8 dead)"
else
    bad "(4h) rc=$RC out: $(grep -i 'identity\|pubkey' "$MOCK_DIR/out" 2>/dev/null | head -3 | tr '\n' ' ')"
fi
if grep -q 'keys/STAKED.json' "$MOCK_DIR/out"; then
    # suffix-matched: macOS readlink -f canonicalizes /var → /private/var, so the resolved
    # path differs from $MOCK_DIR by that prefix — the assertion is that the TARGET is named
    ok "(4i) …and the refusal names the RESOLVED target (readlink), not just the configured path"
else
    bad "(4i) resolved path missing from: $(grep -i 'REFUSE\[P4' "$MOCK_DIR/out" 2>/dev/null | head -1)"
fi
# keygen unavailable + REAL intent → refuse with the manual command AND the dangerous override named
new_mock
mkdir -p "$MOCK_DIR/nobin"
write_env "SOLANA_PATH=\"$MOCK_DIR/nobin\""
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P4-unverifiable\]' "$MOCK_DIR/out" && grep -q 'solana-keygen pubkey' "$MOCK_DIR/out" && grep -q 'ARM_ACCEPT_UNVERIFIED_IDENTITY=1' "$MOCK_DIR/out"; then
    ok "(4j) keygen UNAVAILABLE + real intent → REFUSE[P4-unverifiable]: fix prints the manual keygen command + the documented dangerous override"
else
    bad "(4j) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# the override arms — but WARNS loudly that the KEY claim is unverified
new_mock
mkdir -p "$MOCK_DIR/nobin"
write_env "SOLANA_PATH=\"$MOCK_DIR/nobin\""
run_arm ARM_ACCEPT_UNVERIFIED_IDENTITY=1
if [[ "$RC" == "0" ]] && grep -q 'DANGEROUS' "$MOCK_DIR/out" && grep -q 'NOT verified' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
    ok "(4k) ARM_ACCEPT_UNVERIFIED_IDENTITY=1 → arm proceeds with a LOUD WARN that the KEY was NOT verified (only the path string was)"
else
    bad "(4k) rc=$RC out: $(grep -i 'danger\|unverif' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
# UNSTAKED_PUBKEY unset → nothing to verify the KEY against → unverifiable, not silently OK
new_mock
grep -v '^UNSTAKED_PUBKEY=' "$MOCK_DIR/opt/failover.env" > "$MOCK_DIR/opt/failover.env.t" && mv "$MOCK_DIR/opt/failover.env.t" "$MOCK_DIR/opt/failover.env"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P4-unverifiable\]' "$MOCK_DIR/out" && grep -q 'UNSTAKED_PUBKEY' "$MOCK_DIR/out"; then
    ok "(4l) UNSTAKED_PUBKEY unset + real intent → REFUSE[P4-unverifiable] (fix: derive it with the printed keygen command and set it)"
else
    bad "(4l) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# the override NEVER covers a PROVEN mismatch — it only bridges unverifiability
new_mock
mkdir -p "$MOCK_DIR/keys"; printf 'STAKEDPUBKEY99' > "$MOCK_DIR/keys/STAKED.json"
rm -f "$MOCK_DIR/opt/unstaked.json"
ln -s "$MOCK_DIR/keys/STAKED.json" "$MOCK_DIR/opt/unstaked.json"
run_arm ARM_ACCEPT_UNVERIFIED_IDENTITY=1
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[P4-identity\]' "$MOCK_DIR/out"; then
    ok "(4m) proven KEY mismatch + override=1 → STILL refused (the override bridges 'cannot verify', never 'verified WRONG')"
else
    bad "(4m) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# page-only arm needs NONE of this (unchanged WARN path — nothing on that dispatch can demote/stop)
new_mock
mkdir -p "$MOCK_DIR/nobin"
write_env 'DRY_RUN=true' "SOLANA_PATH=\"$MOCK_DIR/nobin\""
run_arm
if [[ "$RC" == "0" ]] && ! grep -q 'REFUSE\[P4-unverifiable\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
    ok "(4n) page-only + keygen unavailable → proceeds (page-only arm never needs keygen or the override)"
else
    bad "(4n) rc=$RC out: $(grep -i 'P4\|identity' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
# agave CLI semantics: with multiple --identity flags the LAST wins — parsed so, and SAID so
new_mock
{
    echo '[Service]'
    echo "ExecStart=/usr/bin/agave-validator --identity /somewhere/else/staked.json --ledger /l --identity $MOCK_DIR/opt/unstaked.json --rpc-port 8899"
} > "$MOCK_DIR/unitfile"
run_arm
if [[ "$RC" == "0" ]] && grep -q 'precondition 4 OK' "$MOCK_DIR/out" && grep -qi 'LAST' "$MOCK_DIR/out" && grep -qi 'multiple --identity' "$MOCK_DIR/out"; then
    ok "(4o) multiple --identity flags: the LAST one is verified (agave semantics) and the arm SAYS so"
else
    bad "(4o) rc=$RC out: $(grep -i 'identity' "$MOCK_DIR/out" 2>/dev/null | head -3 | tr '\n' ' ')"
fi

# ── (5) P5: the one-arm-state announcement (§2.3 — arm-state IS which unit) ─────────────────────
echo ""; echo "─── (5) P5: which fence unit will be installed, and why, printed ───"
new_mock
run_arm
if grep -q 'DRY_RUN=false' "$MOCK_DIR/out" && grep -q 'REAL fence unit' "$MOCK_DIR/out" && grep -q 'arm-state IS which fence unit is installed' "$MOCK_DIR/out"; then
    ok "(5a) real intent announced with the §2.3 why (re-run after flipping DRY_RUN re-aligns)"
else
    bad "(5a) out: $(grep -i 'arm-state' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
T5A_RC="$RC"
new_mock
write_env 'DRY_RUN=true'
run_arm
if grep -q 'PAGE-ONLY fence unit' "$MOCK_DIR/out" && [[ "$RC" == "0" ]]; then
    ok "(5b) page-only intent announced (DRY_RUN=true)"
else
    bad "(5b) rc=$RC out: $(grep -i 'arm-state' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi

# ── (6) the §2.1-rev2.1 end-to-end probe: flow order + real skels + cleanup ─────────────────────
echo ""; echo "─── (6) probe: reload → start → READY line → marker line → cleanup; rendered from the REAL skels ───"
new_mock
run_arm
t=$(trace)
if [[ "$RC" == "0" && "$t" == "$EXPECT_HAPPY" ]]; then
    ok "(6a) event order exactly: $EXPECT_HAPPY (probe reload → start → cleanup reload → install reload → enable)"
else
    bad "(6a) rc=$RC trace=$t (expected $EXPECT_HAPPY)"
fi
T6_TRACE="$t"; T6_RC="$RC"
# output-order: READY line before marker line before cleanup line
r_line=$(grep -n 'probe READY' "$MOCK_DIR/out" | head -1 | cut -d: -f1)
m_line=$(grep -n 'probe marker observed' "$MOCK_DIR/out" | head -1 | cut -d: -f1)
c_line=$(grep -n 'transient units cleaned' "$MOCK_DIR/out" | head -1 | cut -d: -f1)
if [[ -n "$r_line" && -n "$m_line" && -n "$c_line" && "$r_line" -lt "$m_line" && "$m_line" -lt "$c_line" ]]; then
    ok "(6b) READY-pet seen ($r_line) → marker ($m_line) → cleanup ($c_line): the §2.1-rev2.1 chain in order"
else
    bad "(6b) line order READY=$r_line marker=$m_line cleanup=$c_line"
fi
PSNAP="$MOCK_DIR/runtime.at-start"
if [[ -f "$PSNAP/solana-failover-arm-probe.service" && -f "$PSNAP/solana-failover-arm-probe-fence.service" ]]; then
    p_ok=1
    grep -q '^Type=notify' "$PSNAP/solana-failover-arm-probe.service" || p_ok=""
    grep -q '^WatchdogSec=2s' "$PSNAP/solana-failover-arm-probe.service" || p_ok=""
    grep -q '^OnFailure=solana-failover-arm-probe-fence.service' "$PSNAP/solana-failover-arm-probe.service" || p_ok=""
    grep -q 'READY=1' "$PSNAP/solana-failover-arm-probe.service" || p_ok=""
    grep -q 'socat' "$PSNAP/solana-failover-arm-probe.service" || p_ok=""
    grep -q '^NotifyAccess=all' "$PSNAP/solana-failover-arm-probe.service" || p_ok=""
    if [[ -n "$p_ok" ]]; then
        ok "(6c) probe unit rendered from the real skel: Type=notify + WatchdogSec=2s + OnFailure=probe-fence + one socat READY pet + NotifyAccess=all"
    else
        bad "(6c) probe unit content wrong: $(grep -E '^(Type|WatchdogSec|OnFailure|NotifyAccess|ExecStart)' "$PSNAP/solana-failover-arm-probe.service" 2>/dev/null | tr '\n' ' ')"
    fi
    if grep -q "^ExecStart=/bin/touch $MOCK_DIR/markers/arm-probe.fired" "$PSNAP/solana-failover-arm-probe-fence.service"; then
        ok "(6d) probe-fence's ONLY action: writing the marker (/bin/touch <marker>)"
    else
        bad "(6d) probe-fence ExecStart: $(grep '^ExecStart' "$PSNAP/solana-failover-arm-probe-fence.service" 2>/dev/null)"
    fi
else
    bad "(6c/6d) probe pair not present in the runtime dir at start time: $(ls "$PSNAP" 2>/dev/null)"
fi
if ! ls "$MOCK_DIR/run-systemd" 2>/dev/null | grep -q . && [[ ! -e "$MOCK_DIR/markers/arm-probe.fired" ]]; then
    ok "(6e) transient probe pair + marker CLEANED after the probe (ephemeral by construction)"
else
    bad "(6e) leftovers: $(ls "$MOCK_DIR/run-systemd" "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi
# Block 5.3 fix round: a stale marker from an INTERRUPTED previous ceremony (no trap covers
# Ctrl-C between the OnFailure touch and cleanup) is announced and removed; the probe still proves
new_mock
touch "$MOCK_DIR/markers/arm-probe.fired"
run_arm
if [[ "$RC" == "0" ]] && grep -qi 'stale probe marker' "$MOCK_DIR/out" && grep -q 'probe marker observed' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
    ok "(6f) stale marker FILE (interrupted ceremony) → announced + removed, probe re-proves, arm completes"
else
    bad "(6f) rc=$RC out: $(grep -i 'stale\|marker' "$MOCK_DIR/out" 2>/dev/null | head -3 | tr '\n' ' ')"
fi

# ── (7) probe timeout → refuse + guidance + cleanup + NO install ────────────────────────────────
echo ""; echo "─── (7) probe marker never appears → refuse, print what to check, clean up, install NOTHING ───"
new_mock
rm -f "$MOCK_DIR/probe.fires"
run_arm ARM_PROBE_WAIT=3
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[PROBE-marker\]' "$MOCK_DIR/out" && grep -q 'functionally dead' "$MOCK_DIR/out"; then
    ok "(7a) no marker within the bounded wait → refused to arm (the wiring is not proven)"
else
    bad "(7a) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q 'NotifyAccess' "$MOCK_DIR/out" && grep -qi 'systemd version' "$MOCK_DIR/out" && grep -qi 'socat' "$MOCK_DIR/out"; then
    ok "(7b) guidance names the checks: NotifyAccess? systemd version? socat?"
else
    bad "(7b) guidance: $(grep 'FIX' "$MOCK_DIR/out" 2>/dev/null)"
fi
if ! ls "$MOCK_DIR/run-systemd" 2>/dev/null | grep -q . && ! ls "$MOCK_DIR/etc-systemd" 2>/dev/null | grep -q .; then
    ok "(7c) transient pair cleaned on the refusal path too; NOTHING installed"
else
    bad "(7c) leftovers: run=$(ls "$MOCK_DIR/run-systemd" 2>/dev/null | tr '\n' ' ') etc=$(ls "$MOCK_DIR/etc-systemd" 2>/dev/null | tr '\n' ' ')"
fi
T7_RC="$RC"
# Block 5.3 fix round (panel M-A): stale marker file + wiring FUNCTIONALLY DEAD — the pre-probe
# cleanup is load-bearing: without it the stale file satisfies the wait and false-PROVES dead
# wiring. Committed code must clean, then refuse on the missing FRESH marker.
new_mock
touch "$MOCK_DIR/markers/arm-probe.fired"
rm -f "$MOCK_DIR/probe.fires"
run_arm ARM_PROBE_WAIT=3
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[PROBE-marker\]' "$MOCK_DIR/out"; then
    ok "(7d) stale marker + DEAD wiring → stale cleaned, wait sees NO fresh marker → REFUSE[PROBE-marker] (M-A dead: deleting the pre-probe rm turns this red)"
else
    bad "(7d) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# Block 5.3 fix round (panel A5): an UNREMOVABLE pre-existing path at the marker (a directory)
# would satisfy an existence wait over dead wiring — refuse BEFORE probing, clean-it fix text,
# and the ceremony never reaches for rm -rf.
new_mock
mkdir -p "$MOCK_DIR/markers/arm-probe.fired"
rm -f "$MOCK_DIR/probe.fires"
run_arm ARM_PROBE_WAIT=3
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[PROBE-marker-stale\]' "$MOCK_DIR/out" && grep -qi 'BY HAND' "$MOCK_DIR/out"; then
    ok "(7e) DIRECTORY at the marker path + dead wiring → REFUSE[PROBE-marker-stale] with clean-it-by-hand fix (A5 dead)"
else
    bad "(7e) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
if ! ls "$MOCK_DIR/etc-systemd" 2>/dev/null | grep -q . && ! grep 'rm -rf' "$ARM" | grep -v never | grep -q .; then
    ok "(7f) …nothing installed on that refusal, and failover-arm.sh contains NO rm -rf invocation (every textual mention is a 'never' promise)"
else
    bad "(7f) etc=$(ls "$MOCK_DIR/etc-systemd" 2>/dev/null | tr '\n' ' ') rm-rf-sites: $(grep 'rm -rf' "$ARM" 2>/dev/null | grep -v never | head -2 | tr '\n' ' ')"
fi

# ── (8) probe start fails: the READY pet never landed (§2.6 socat self-test) ────────────────────
echo ""; echo "─── (8) probe start rc 1 (no READY) → refuse naming the §2.6 pet self-test ───"
new_mock
echo 1 > "$MOCK_DIR/rc.probestart"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[PROBE-ready\]' "$MOCK_DIR/out" && grep -q "pet" "$MOCK_DIR/out"; then
    ok "(8) READY never landed → refused: 'refuse to arm if a pet doesn't land' (§2.6)"
else
    bad "(8) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi

# ── (9) install: ONE fence unit, sibling removed, role fill, bodies placed, enable, no validator touch ──
echo ""; echo "─── (9) install renders exactly ONE fence unit + removes the stale sibling + enables monitor ───"
new_mock
touch "$MOCK_DIR/etc-systemd/solana-failover-fence-page-only.service"   # stale sibling from a previous page-only arm
run_arm
if [[ "$RC" == "0" && -f "$MOCK_DIR/etc-systemd/solana-failover-fence.service" && ! -e "$MOCK_DIR/etc-systemd/solana-failover-fence-page-only.service" ]]; then
    ok "(9a) DRY_RUN=false: REAL fence unit installed, stale page-only sibling REMOVED (exactly ONE fence unit)"
else
    bad "(9a) rc=$RC etc: $(ls "$MOCK_DIR/etc-systemd" 2>/dev/null | tr '\n' ' ')"
fi
MON="$MOCK_DIR/etc-systemd/solana-failover-monitor.service"
if [[ -f "$MON" ]] && grep -q "^ExecStart=$MOCK_DIR/opt/solana-primary-failover.sh" "$MON" && grep -q "^EnvironmentFile=$MOCK_DIR/opt/failover.env" "$MON" && ! grep -v '^[[:space:]]*#' "$MON" | grep -q '<role>'; then
    ok "(9b) monitor rendered: role daemon + role env filled, no <role> placeholder left outside comments"
else
    bad "(9b) monitor: $(grep -E '^(ExecStart|EnvironmentFile)' "$MON" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q '^WatchdogSec=30' "$MON" && grep -q '^OnFailure=solana-failover-fence.service solana-failover-fence-page-only.service' "$MON" && head -1 "$MON" | grep -q '^# RENDERED'; then
    ok "(9c) monitor keeps the skel's load-bearing lines (WatchdogSec=30, both-unit OnFailure, R8 pair) under a RENDERED header"
else
    bad "(9c) monitor lines: $(grep -E '^(WatchdogSec|OnFailure)' "$MON" 2>/dev/null | tr '\n' ' ') head: $(head -1 "$MON" 2>/dev/null)"
fi
FUNIT="$MOCK_DIR/etc-systemd/solana-failover-fence.service"
if grep -q "^ExecStart=$MOCK_DIR/opt/failover-fence.sh" "$FUNIT" && [[ -x "$MOCK_DIR/opt/failover-fence.sh" && -x "$MOCK_DIR/opt/failover-fence-page-only.sh" ]]; then
    ok "(9d) fence unit points at the fence body the ceremony itself placed into ARM_INSTALL_DIR (both bodies, executable)"
else
    bad "(9d) fence ExecStart: $(grep '^ExecStart' "$FUNIT" 2>/dev/null) bodies: $(ls "$MOCK_DIR/opt" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q 'systemctl enable solana-failover-monitor.service' "$EVENTS" && [[ "$(trace)" != *FORBIDDEN* ]]; then
    ok "(9e) monitor ENABLED (the only enable of a Block-5 unit — the legacy deploy scripts enable the pre-fence solana-failover service); validator unit never started/restarted/stopped"
else
    bad "(9e) events: $(grep -E 'enable|start |restart|stop' "$EVENTS" 2>/dev/null | tr '\n' ' ')"
fi
# B3 (panel truth blocker): the printed claim is SCOPED — "only enable of a Block-5 unit",
# never "only enable in the project" (deploy-failover*.sh enable the legacy service today)
if grep -q 'only enable of a Block-5 unit' "$MOCK_DIR/out" && ! grep -q 'only enable in the project' "$MOCK_DIR/out"; then
    ok "(9e2) the arm-time log line scopes the enable claim to the Block-5 unit set (claims match reality)"
else
    bad "(9e2) enable claim: $(grep -i 'enable' "$MOCK_DIR/out" 2>/dev/null | tail -1)"
fi
if grep -q "verify: installed fence-unit classification 'real' agrees" "$MOCK_DIR/out"; then
    ok "(9f) post-install verify agreement line (render→verify, not render→hope)"
else
    bad "(9f) out: $(grep -i verify "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
T9_MOCK="$MOCK_DIR"
new_mock
write_daemon "$MOCK_DIR/opt/solana-standby-failover.sh"
cp "$MOCK_DIR/opt/failover.env" "$MOCK_DIR/opt/failover-standby.env"
run_arm ARM_ROLE=standby
MON="$MOCK_DIR/etc-systemd/solana-failover-monitor.service"
if [[ "$RC" == "0" ]] && grep -q "^ExecStart=$MOCK_DIR/opt/solana-standby-failover.sh" "$MON" && grep -q "^EnvironmentFile=$MOCK_DIR/opt/failover-standby.env" "$MON"; then
    ok "(9g) ARM_ROLE=standby: standby daemon + failover-standby.env rendered"
else
    bad "(9g) rc=$RC monitor: $(grep -E '^(ExecStart|EnvironmentFile)' "$MON" 2>/dev/null | tr '\n' ' ')"
fi
new_mock
write_daemon "$MOCK_DIR/opt/solana-standby-failover.sh"
cp "$MOCK_DIR/opt/failover.env" "$MOCK_DIR/opt/failover-standby.env"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[ROLE-ambiguous\]' "$MOCK_DIR/out" && grep -q 'ARM_ROLE=primary or ARM_ROLE=standby' "$MOCK_DIR/out"; then
    ok "(9h) both env files without ARM_ROLE → refuse + the exact fix"
else
    bad "(9h) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# ── Block 5.3 fix round: the renderer is STRUCTURAL (bash string replace, no sed) — panel
# A3 ('&' patsub/sed metachar), A14 (backslash), A15 ('|', the old delimiter refusal) all
# render BYTE-EXACT and the rendered content is VERIFIED (A13: garbage ExecStart can no
# longer pass the presence-only verify) ──
new_mock
WEIRD="$MOCK_DIR/o&b\\p|q"
mkdir -p "$WEIRD"
write_daemon "$WEIRD/solana-primary-failover.sh"
printf 'UNSTAKEDPUBKEY42' > "$WEIRD/unstaked.json"
{
    echo 'DRY_RUN=false'
    echo 'VALIDATOR_TYPE="agave"'
    echo "UNSTAKED_KEYPAIR=\"$WEIRD/unstaked.json\""
    echo 'UNSTAKED_PUBKEY="UNSTAKEDPUBKEY42"'
    echo "SOLANA_PATH=\"$STUB_DIR\""
    echo 'VALIDATOR_UNIT="sol-test.service"'
} > "$WEIRD/failover.env"
{
    echo '[Service]'
    echo "ExecStart=/usr/bin/agave-validator --ledger /l --identity $WEIRD/unstaked.json --rpc-port 8899"
} > "$MOCK_DIR/unitfile"
INSTALL_OVERRIDE="$WEIRD" run_arm
MON="$MOCK_DIR/etc-systemd/solana-failover-monitor.service"
if [[ "$RC" == "0" ]] && grep -qxF "ExecStart=$WEIRD/solana-primary-failover.sh" "$MON" && grep -qxF "EnvironmentFile=$WEIRD/failover.env" "$MON"; then
    ok "(9i) install dir with '&', '\\' and '|' → renders BYTE-EXACT (structural replace killed the sed metacharacter class: A3/A13/A14/A15 dead)"
else
    bad "(9i) rc=$RC monitor: $(grep -E '^(ExecStart|EnvironmentFile)' "$MON" 2>/dev/null | tr '\n' ' ') out: $(tail -2 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
if ! grep -v '^[[:space:]]*#' "$MON" 2>/dev/null | grep -q '<[a-z][a-z-]*>' && grep -qxF "ExecStart=$WEIRD/failover-fence.sh" "$MOCK_DIR/etc-systemd/solana-failover-fence.service"; then
    ok "(9i2) …and post-render verification held: no placeholder token outside comments, fence ExecStart byte-exact too"
else
    bad "(9i2) placeholders: $(grep -v '^[[:space:]]*#' "$MON" 2>/dev/null | grep '<' | head -2 | tr '\n' ' ') fence: $(grep '^ExecStart' "$MOCK_DIR/etc-systemd/solana-failover-fence.service" 2>/dev/null)"
fi
# panel A6: a DIRECTORY at a render destination swallows `mv` silently (mv-into-dir returns 0)
new_mock
mkdir -p "$MOCK_DIR/etc-systemd/solana-failover-monitor.service"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[RENDER-dest\]' "$MOCK_DIR/out" && grep -qi 'BY HAND' "$MOCK_DIR/out"; then
    ok "(9j) pre-existing DIRECTORY at the monitor unit path → REFUSE[RENDER-dest] + clean-it-by-hand fix (A6 dead)"
else
    bad "(9j) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# panel A2: un-removable stale PAGE-ONLY sibling under REAL intent → REFUSE (was WARN): the
# §2.3 one-unit invariant is violated on disk and real-wins classification would mask it
new_mock
mkdir -p "$MOCK_DIR/etc-systemd/solana-failover-fence-page-only.service"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[INSTALL-sibling\]' "$MOCK_DIR/out" && grep -q 'exactly ONE fence unit' "$MOCK_DIR/out"; then
    ok "(9k) stale page-only sibling that will NOT remove + REAL intent → REFUSE[INSTALL-sibling] (§2.3: both units on disk must not survive an arm — A2 dead)"
else
    bad "(9k) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi

# ── (10) DRY_RUN flip → re-arm re-aligns (the №1 refusal's designed resolution path) ────────────
echo ""; echo "─── (10) re-arm after flipping DRY_RUN: page-only replaces real, gen bumps ───"
MOCK_DIR="$T9_MOCK"; EVENTS="$MOCK_DIR/events"; : > "$EVENTS"
sed 's/^DRY_RUN=false/DRY_RUN=true/' "$MOCK_DIR/opt/failover.env" > "$MOCK_DIR/opt/failover.env.t" && mv "$MOCK_DIR/opt/failover.env.t" "$MOCK_DIR/opt/failover.env"
run_arm
if [[ "$RC" == "0" && -f "$MOCK_DIR/etc-systemd/solana-failover-fence-page-only.service" && ! -e "$MOCK_DIR/etc-systemd/solana-failover-fence.service" ]]; then
    ok "(10a) re-arm re-aligned: page-only installed, REAL unit removed (the arm is the alignment mechanism)"
else
    bad "(10a) rc=$RC etc: $(ls "$MOCK_DIR/etc-systemd" 2>/dev/null | tr '\n' ' ')"
fi
tok=$(token_line)
if [[ "$(cat "$MOCK_DIR/state/arm-generation" 2>/dev/null)" == "2" ]] && printf '%s\n' "$tok" | grep -q '|gen=2|' && printf '%s\n' "$tok" | grep -q '|fence=page-only|'; then
    ok "(10b) generation bumped 1→2 across the re-arm; token says fence=page-only"
else
    bad "(10b) gen=$(cat "$MOCK_DIR/state/arm-generation" 2>/dev/null) token=$tok"
fi
T10_TOKEN="$tok"

# ── (11) the pairing token (§2.1-rev2.1 conditions 2–3, v0.7 form) ──────────────────────────────
echo ""; echo "─── (11) token: exact shape, crc verifies, gen persisted, refusal when it cannot print ───"
new_mock
run_arm
tok=$(token_line)
if printf '%s\n' "$tok" | grep -qE '^v0\.7\|gen=1\|watchdog=30\|relinquish_bound=60\|fence=real\|host=[^|][^|]*\|[0-9][0-9]*$'; then
    ok "(11a) token shape exact: v0.7|gen=1|watchdog=30|relinquish_bound=60|fence=real|host=<h>|<crc>"
else
    bad "(11a) token: $tok"
fi
payload="${tok%|*}"; crc="${tok##*|}"
want=$(printf '%s' "$payload" | cksum | awk '{print $1}')
if [[ -n "$crc" && "$crc" == "$want" ]]; then
    ok "(11b) crc re-computed over the payload matches (integrity, not security)"
else
    bad "(11b) crc=$crc recomputed=$want payload=$payload"
fi
t_line=$(grep -n '^v0\.7|gen=' "$MOCK_DIR/out" | head -1 | cut -d: -f1)
a_line=$(grep -n 'ARMED (real)' "$MOCK_DIR/out" | head -1 | cut -d: -f1)
if [[ -n "$t_line" && -n "$a_line" && "$t_line" -lt "$a_line" ]]; then
    ok "(11c) token printed BEFORE the completion line — the arm cannot complete without it"
else
    bad "(11c) token line=$t_line ARMED line=$a_line"
fi
T11_TOKEN="$tok"
# (11d) the gen write fails → the arm REFUSES to complete. Root-proof sabotage of exactly ONE move: an
# `mv` wrapper (fronting the real one on this run's PATH) fails the move onto the gen counter and runs
# every other mv for real. (Until Block 6.3.1 the sabotage was a FILE at ARM_STATE_DIR; P0 now refuses
# that before anything is installed — (16e) — so the TOKEN-persist write branch gets its own sabotage.)
STUB_MVFAIL="$STUB_PARENT/mvfail"; mkdir -p "$STUB_MVFAIL"; cp "$STUB_DIR"/* "$STUB_MVFAIL/"
cat > "$STUB_MVFAIL/mv" <<STUB
#!/bin/sh
for a in "\$@"; do last="\$a"; done
case "\$last" in */arm-generation) echo "mv-sabotaged \$*" >> "\$EVENTS"; exit 1 ;; esac
exec "$TOOLDIR/mv" "\$@"
STUB
chmod +x "$STUB_MVFAIL/mv"
new_mock
ARM_PATH="$STUB_MVFAIL" run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[TOKEN-persist\]' "$MOCK_DIR/out" && grep -q 'could not persist the bumped config-generation counter' "$MOCK_DIR/out" && grep -q '^mv-sabotaged ' "$EVENTS" && [[ -z "$(token_line)" ]] && ! grep -q 'ceremony complete' "$MOCK_DIR/out"; then
    ok "(11d) token cannot persist (the gen move fails) → arm REFUSES to complete (exit 1, no token, no ARMED line; re-pair is ceremony)"
else
    bad "(11d) rc=$RC token=$(token_line) out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# Block 5.3 fix round (panel A10): a DIRECTORY at the gen file — `mv` onto it returns 0 while
# relocating the tmp INSIDE it; persist is only real if genf is a REGULAR FILE holding the
# bumped value (verified after the mv, claim=check)
new_mock
mkdir -p "$MOCK_DIR/state/arm-generation"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[TOKEN-persist\]' "$MOCK_DIR/out" && [[ -z "$(token_line)" ]] && ! grep -q 'ceremony complete' "$MOCK_DIR/out"; then
    ok "(11e) DIRECTORY at the gen file → mv 'succeeds' but the verify-after-mv catches it → REFUSE[TOKEN-persist] (A10 dead)"
else
    bad "(11e) rc=$RC token=$(token_line) out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# Block 5.3 fix round (panel A12): concurrent arms raced read-increment-write — the bump now
# runs under `flock -w 5` on the state dir when flock exists (P3 already probed the posture).
# Residual (named in the arm): flock absent/busybox → unlocked, the P3 WARN says so.
new_mock
run_arm
if [[ "$RC" == "0" ]] && grep -q 'flock -w 5 9' "$EVENTS"; then
    ok "(11f) the generation bump takes the bounded state-dir lock (flock -w 5) when flock is present (A12 serialized; absent-flock residual is named)"
else
    bad "(11f) rc=$RC flock events: $(grep flock "$EVENTS" 2>/dev/null | tr '\n' ' ')"
fi

# ── (12) verify gate: un-removable stale sibling → render→verify refuse ─────────────────────────
echo ""; echo "─── (12) stale REAL sibling that will not remove (a directory) → post-install verify refuses ───"
new_mock
write_env 'DRY_RUN=true'
mkdir -p "$MOCK_DIR/etc-systemd/solana-failover-fence.service"   # rm -f cannot remove a directory
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[VERIFY-mismatch\]' "$MOCK_DIR/out" && grep -q 'render→verify' "$MOCK_DIR/out"; then
    ok "(12) classification 'real' vs intent 'page-only' → refused (render→verify caught the failed removal)"
else
    bad "(12) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi

# ── (15) legacy-monitor retirement (fix round 2, reviewer blocker) ──────────────────────────────
# Red observed first (tool-bearing docker, OLD arm): legacy solana-failover.service present +
# ACTIVE + ENABLED → the ceremony completed a full REAL arm (token printed, new monitor enabled)
# with ZERO legacy stop/disable events — two Restart=always monitor daemons on one host, same
# env + state file, racing set-identity (scratchpad/red-block53-round2.log). The fix is a
# ceremony step, NOT a daemon-side flock (a notify monitor losing that race never goes READY →
# start timeout → OnFailure → a REAL fence on a healthy validator — the reviewer's trace).
echo ""; echo "─── (15) legacy monitor: stop+disable+VERIFY before the new enable; refuse on failure; absent → untouched ───"
new_mock
printf '[Service]\nExecStart=/opt/solana-failover/solana-primary-failover.sh\nRestart=always\n' > "$MOCK_DIR/etc-systemd/solana-failover.service"
touch "$MOCK_DIR/active.solana-failover.service" "$MOCK_DIR/enabled.solana-failover.service"
run_arm
t=$(trace)
if [[ "$RC" == "0" && "$t" == "ident-cat,reload,start-probe,reset,reload,reload,legacy-stop,legacy-disable,enable" ]] && [[ -n "$(token_line)" ]]; then
    ok "(15a) legacy unit present+active+enabled → stop → disable → THEN the new enable (exact trace), arm completes"
else
    bad "(15a) rc=$RC trace=$t (expected …,legacy-stop,legacy-disable,enable)"
fi
s_line=$(grep -n '^systemctl stop solana-failover.service$' "$EVENTS" | head -1 | cut -d: -f1)
d_line=$(grep -n '^systemctl disable solana-failover.service$' "$EVENTS" | head -1 | cut -d: -f1)
va_line=$(grep -n '^systemctl is-active solana-failover.service$' "$EVENTS" | tail -1 | cut -d: -f1)
ve_line=$(grep -n '^systemctl is-enabled solana-failover.service$' "$EVENTS" | tail -1 | cut -d: -f1)
e_line=$(grep -n '^systemctl enable solana-failover-monitor.service$' "$EVENTS" | head -1 | cut -d: -f1)
if [[ -n "$s_line" && -n "$d_line" && -n "$va_line" && -n "$ve_line" && -n "$e_line" && "$s_line" -lt "$d_line" && "$d_line" -lt "$va_line" && "$va_line" -lt "$ve_line" && "$ve_line" -lt "$e_line" ]]; then
    ok "(15b) the VERIFY re-reads (is-active, is-enabled) run AFTER stop+disable and BEFORE the new enable (events $s_line<$d_line<$va_line<$ve_line<$e_line)"
else
    bad "(15b) event order: stop=$s_line disable=$d_line is-active=$va_line is-enabled=$ve_line enable=$e_line"
fi
if grep -q 'legacy monitor retired: solana-failover.service — the Block-5 monitor replaces it' "$MOCK_DIR/out" && [[ -f "$MOCK_DIR/etc-systemd/solana-failover.service" ]] && grep -q "operator's cleanup" "$MOCK_DIR/out" && [[ ! -f "$MOCK_DIR/active.solana-failover.service" && ! -f "$MOCK_DIR/enabled.solana-failover.service" ]]; then
    ok "(15c) announce line verbatim; stopped+disabled per the stub state; the unit FILE stays on disk (deletion is the operator's cleanup, said aloud)"
else
    bad "(15c) out: $(grep -i 'legacy' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ') file=$([[ -f "$MOCK_DIR/etc-systemd/solana-failover.service" ]] && echo kept || echo GONE)"
fi
# the STANDBY wizard's unit name is in the retire set too (N-is-all over the derived name set) —
# detected via the is-active probe alone (no unit file), on a primary-role host
new_mock
touch "$MOCK_DIR/active.solana-failover-standby.service"
run_arm
if [[ "$RC" == "0" ]] && grep -q 'legacy monitor retired: solana-failover-standby.service' "$MOCK_DIR/out" && grep -q '^systemctl stop solana-failover-standby.service$' "$EVENTS" && [[ ! -f "$MOCK_DIR/active.solana-failover-standby.service" ]]; then
    ok "(15d) solana-failover-standby.service ACTIVE with no unit file → detected by the is-active probe, retired (the full wizard name set, role-independent)"
else
    bad "(15d) rc=$RC out: $(grep -i 'legacy' "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
# stop FAILS → refuse + the exact manual commands; the new monitor is NOT enabled, no token
new_mock
printf '[Service]\nRestart=always\n' > "$MOCK_DIR/etc-systemd/solana-failover.service"
touch "$MOCK_DIR/active.solana-failover.service" "$MOCK_DIR/enabled.solana-failover.service"
echo 1 > "$MOCK_DIR/rc.stop.solana-failover.service"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[INSTALL-legacy\]' "$MOCK_DIR/out" && grep -q 'systemctl stop solana-failover.service && systemctl disable solana-failover.service' "$MOCK_DIR/out" && [[ -z "$(token_line)" ]] && ! grep -q '^systemctl enable ' "$EVENTS"; then
    ok "(15e) stop fails → REFUSE[INSTALL-legacy] with the exact manual commands; new monitor NOT enabled, no token printed"
else
    bad "(15e) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ') enable-events: $(grep -c '^systemctl enable ' "$EVENTS")"
fi
# VERIFY disagreement: stop returns 0 but is-active still reports ACTIVE → refuse
new_mock
touch "$MOCK_DIR/active.solana-failover.service"
touch "$MOCK_DIR/stopnoop.solana-failover.service"
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[INSTALL-legacy\]' "$MOCK_DIR/out" && grep -q 'verify disagreement' "$MOCK_DIR/out" && [[ -z "$(token_line)" ]] && ! grep -q '^systemctl enable ' "$EVENTS"; then
    ok "(15f) stop rc 0 but is-active still ACTIVE → verify disagreement → refuse (claims never exceed checks); no enable, no token"
else
    bad "(15f) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
# absent → ZERO legacy stop/disable events and no retire narration (assert none) — while the
# detection PROBES still run for BOTH wizard names on every arm (N-is-all detection, alive)
new_mock
run_arm
if [[ "$RC" == "0" ]] && ! grep -E '^systemctl (stop|disable) ' "$EVENTS" | grep -q . && ! grep -q 'legacy monitor' "$MOCK_DIR/out"; then
    ok "(15g) no legacy unit anywhere → ZERO legacy stop/disable events, zero retire narration (asserted none)"
else
    bad "(15g) rc=$RC events: $(grep -E '^systemctl (stop|disable) ' "$EVENTS" 2>/dev/null | tr '\n' ' ') out: $(grep -i legacy "$MOCK_DIR/out" 2>/dev/null | head -2 | tr '\n' ' ')"
fi
if grep -q '^systemctl is-active solana-failover.service$' "$EVENTS" && grep -q '^systemctl is-active solana-failover-standby.service$' "$EVENTS"; then
    ok "(15h) …and BOTH wizard unit names were probed on that arm (detection is N-is-all over the derived set, every run)"
else
    bad "(15h) probes: $(grep 'is-active' "$EVENTS" 2>/dev/null | tr '\n' ' ')"
fi

# ── (16) P0: the state directory must be its own resolved path (Block 6.3.1 D5) ──────────────────
# The spare daemon's R-SYM rule (6.3 fix round 5) mirrored at the arm: a pairing token whose directory
# is reached through a symlink never proves (watchdog-elapsed keys the token FILE's identity; a
# directory re-pointed away and back leaves it untouched). The arm refuses to write (spare:
# pairing-token; holder: arm-generation) into a state directory that does not canonicalize to itself,
# BEFORE anything is written or installed. Pre-fix red (the 6.3 build): every case below ARMED —
# the symlinked directory got the gen counter (the token, on a spare) written THROUGH the link.
echo ""; echo "─── (16) P0: symlinked / non-canonical / non-directory ARM_STATE_DIR → REFUSE before any write or install ───"
p0_refused() {   # $1 = gate id; the refusal happened before ANY install step and printed no token
    [[ "$RC" == "1" ]] && grep -q "REFUSE\[$1\]" "$MOCK_DIR/out" && [[ -z "$(token_line)" ]] \
        && ! grep -q '^systemctl daemon-reload' "$EVENTS" && [[ -z "$(ls "$MOCK_DIR/etc-systemd" 2>/dev/null)" ]] \
        && ! grep -q 'precondition 1 OK' "$MOCK_DIR/out"
}
# Every P0 refusal below (16a)–(16e), (16g)'s refusals and (16h)'s own) also asserts that it REMOVED NOTHING, whatever the
# tool or its spelling (6.3.1 fix round 5 — the delta panel 4's T4-16H-CLOSURE): p0_snap lists every path the scenario
# made (find, not following links — the link itself, the dangling one too, each with its type) right before the run;
# p0_lost names any of them missing or of another type afterwards; p0_rmcalls names any rm / rmdir / unlink the arm ran
# through PATH (TOOLDIR's logging wrappers).
p0_snap() { : > "$MOCK_DIR/rm.calls"; find "$MOCK_DIR" -print 2>/dev/null | while IFS= read -r _p; do if [[ -L "$_p" ]]; then printf 'L %s\n' "$_p"; elif [[ -d "$_p" ]]; then printf 'D %s\n' "$_p"; else printf 'F %s\n' "$_p"; fi; done > "$MOCK_PARENT/p0.snap"; }
p0_lost() { local _t _p _l=""; while read -r _t _p; do case "$_t" in L) [[ -L "$_p" ]] ;; D) [[ -d "$_p" && ! -L "$_p" ]] ;; *) [[ -e "$_p" && ! -d "$_p" && ! -L "$_p" ]] ;; esac || _l="$_l ${_p#"$MOCK_DIR"/}"; done < "$MOCK_PARENT/p0.snap"; printf '%s' "$_l"; }
p0_rmcalls() { [[ -s "$MOCK_DIR/rm.calls" ]] && { printf ' [removal ran: %s]' "$(tr '\n' ';' < "$MOCK_DIR/rm.calls" | cut -c1-160)"; return 0; }; return 1; }
p0_kept() { [[ -z "$(p0_lost)" ]] && ! p0_rmcalls >/dev/null; }   # nothing the scenario made is gone, no removal ran
p0_why() { printf 'lost=[%s]%s' "$(p0_lost)" "$(p0_rmcalls)"; }
# (16a) the state directory itself is a symlink to a real directory
new_mock
mkdir -p "$MOCK_DIR/real-state"; rm -rf "$MOCK_DIR/state"; ln -s "$MOCK_DIR/real-state" "$MOCK_DIR/state"
p0_snap; run_arm
if p0_refused STATE-dir-symlink && grep -q "resolves to $MOCK_DIR/real-state" "$MOCK_DIR/out" && grep -q "FIX: point ARM_STATE_DIR at the resolved path — ARM_STATE_DIR=$MOCK_DIR/real-state" "$MOCK_DIR/out" \
      && [[ ! -e "$MOCK_DIR/real-state/arm-generation" ]] && p0_kept; then
    ok "(16a) ARM_STATE_DIR is a symlink → REFUSE[STATE-dir-symlink] naming the resolved path and the exact fix (ARM_STATE_DIR=<resolved> + the spare's PROOF_STATE_DIR), exit 1 before ANY install step; nothing written through the link, nothing removed (the link and its target stay)"
else
    bad "(16a) rc=$RC gen=$(ls "$MOCK_DIR/real-state" 2>/dev/null | tr '\n' ' ') $(p0_why) out: $(grep -E 'REFUSE|FIX' "$MOCK_DIR/out" | tr '\n' ' ' | cut -c1-400)"
fi
# (16b) a symlinked ANCESTOR (the directory itself is real)
new_mock
mkdir -p "$MOCK_DIR/real-anc/state"; ln -s "$MOCK_DIR/real-anc" "$MOCK_DIR/anc"
p0_snap; run_arm ARM_STATE_DIR="$MOCK_DIR/anc/state"
if p0_refused STATE-dir-symlink && grep -q "resolves to $MOCK_DIR/real-anc/state" "$MOCK_DIR/out" && p0_kept; then
    ok "(16b) a symlinked ANCESTOR (ARM_STATE_DIR=…/anc/state, anc → real-anc) → REFUSE[STATE-dir-symlink] — the whole path must resolve to itself, as in the daemon; nothing removed"
else
    bad "(16b) rc=$RC $(p0_why) out: $(grep -E 'REFUSE|precondition 0' "$MOCK_DIR/out" | tr '\n' ' ' | cut -c1-300)"
fi
# (16c) spellings that are not the resolved path — each refused (the daemon's list) with their OWN code,
# STATE-dir-spelling (6.3.1 fix round 1, R7 — the panel's CC-7: they were refused as "symlink" though
# none involves one); a LEADING '//' is kept by pwd -P as its own root on Linux (and dropped on macOS) —
# asserted only as "agrees with the daemon" in (16g)
sp_ct=0; sp_red=0; sp_miss=""
for sp in "$MOCK_DIR/state/" "$MOCK_DIR//state" "$MOCK_DIR/./state" "$MOCK_DIR/state/../state"; do
    sp_ct=$((sp_ct + 1)); new_mock
    p0_snap; run_arm ARM_STATE_DIR="$sp"
    if p0_refused STATE-dir-spelling && p0_kept; then sp_red=$((sp_red + 1)); else sp_miss="$sp_miss [$sp rc=$RC $(grep -o 'REFUSE\[[^]]*\]' "$MOCK_DIR/out" | head -1) $(p0_why)]"; fi
done
new_mock; p0_snap
( cd "$MOCK_DIR" && env -i PATH="$STUB_DIR:$TOOLDIR" EVENTS="$EVENTS" MOCK_DIR="$MOCK_DIR" ARM_SYSTEMD_DIR="$MOCK_DIR/etc-systemd" ARM_RUNTIME_DIR="$MOCK_DIR/run-systemd" ARM_INSTALL_DIR="$MOCK_DIR/opt" FENCE_MARKER_DIR="$MOCK_DIR/markers" ARM_STATE_DIR="state" "$BASH_BIN" "$ARM" > "$MOCK_DIR/out" 2>&1 ); RC=$?
sp_ct=$((sp_ct + 1)); if p0_refused STATE-dir-spelling && p0_kept; then sp_red=$((sp_red + 1)); else sp_miss="$sp_miss [relative rc=$RC $(grep -o 'REFUSE\[[^]]*\]' "$MOCK_DIR/out" | head -1) $(p0_why)]"; fi
if [[ "$sp_red" == "$sp_ct" ]]; then
    ok "(16c) every non-resolved spelling REFUSED[STATE-dir-spelling] ($sp_ct/$sp_ct: trailing '/', internal '//', '/./', '/../', a relative path) — the daemon's exact rule, its own code (nothing on the filesystem is wrong, the value is), before any install; nothing removed"
else
    bad "(16c) $((sp_ct - sp_red))/$sp_ct spellings not refused as STATE-dir-spelling:$sp_miss"
fi
# (16h) NOTHING IS CREATED by a refusal by spelling or by the existing ancestor (6.3.1 fix round 1, R7 — the panel's
# CC-7: P0 ran mkdir -p BEFORE canonicalizing, so every refused path below was left on disk — MEASURED red on the 6.3.1
# build: new1/sub, rel/state, s2, s3, s4 created under their refused spellings, and real/newsub and realanc/newsub
# created THROUGH the links). Each case: the refusal code, the refused directory (or its resolved target) absent
# afterwards, and NO removal command run (below).
# P0 REMOVES NOTHING — three halves, each able to go red (red first: the delta panel 3's TS3-16H-RMDIR mutants H1–H4,
# H6, H6b and the delta panel 4's T4-16H-CLOSURE mutants A1–A3):
#   - DYNAMIC: every P0 refusal ((16a)–(16e), (16g)'s refusals, each case here) leaves every path its scenario made in
#     place (p0_snap / p0_lost — the link, the dangling link, the file at ARM_STATE_DIR, the victim tree) and ran no rm /
#     rmdir / unlink through PATH (logging wrappers, the real binary behind each) — any removal on the exercised paths, by
#     any tool or spelling, is red;
#   - STATIC: reads bash's own parse of the arm (bp_parse — a `function`-keyword or one-line helper printed like any other)
#     and checks that P0 and every function it calls, transitively (_arm_cleanup_probe excepted — reached only through
#     _arm_refuse, and its first statement returns unless the probe was rendered, which happens after P0), with quotes and
#     backslashes deleted, hold no rm / rmdir / unlink word, in code or text; and that bash sourcing the arm (all but its
#     `main "$@"`) defines exactly the functions the parse lists;
#   - the RACE (the delta panel 3's RM-3): a symlink raced onto an intermediate component between the ancestor check and
#     mkdir -p makes mkdir -p create the tail INSIDE the link's target, and the post-mkdir check refuses
#     REFUSE[STATE-dir-symlink] — nothing under the link's target may be removed (the created tail included: it stays,
#     named in docs/SAFETY.md's local-host threat model), and the FIX line says to stop and investigate a link the operator
#     did not create before adopting its target.
# LIMIT, named: the static half reads the three words only (a removal through another tool — find -delete, mv away, an
# interpreter's unlink — or through a command word assembled at run time is the dynamic half's, on the exercised paths); a
# removal on a P0 path no case here takes, spelled past the three words, is not seen.
cr_ct=0; cr_ok=0; cr_miss=""
p0_nothing_created() {   # $1 = code, $2.. = paths that must NOT exist afterwards
    local _code="$1" _x; shift
    cr_ct=$((cr_ct + 1))
    if p0_refused "$_code"; then
        for _x in "$@"; do [[ -e "$_x" || -L "$_x" ]] && { cr_miss="$cr_miss [$_code: $_x CREATED]"; return 0; }; done
        p0_kept || { cr_miss="$cr_miss [$_code: $(p0_why)]"; return 0; }
        cr_ok=$((cr_ok + 1))
    else
        cr_miss="$cr_miss [$_code: rc=$RC $(grep -o 'REFUSE\[[^]]*\]' "$MOCK_DIR/out" | head -1)]"
    fi
}
new_mock; p0_snap; run_arm ARM_STATE_DIR="$MOCK_DIR/new1/sub/"; p0_nothing_created STATE-dir-spelling "$MOCK_DIR/new1"
new_mock; p0_snap; run_arm ARM_STATE_DIR="$MOCK_DIR/s2//x"; p0_nothing_created STATE-dir-spelling "$MOCK_DIR/s2"
new_mock; p0_snap; run_arm ARM_STATE_DIR="$MOCK_DIR/s3/./x"; p0_nothing_created STATE-dir-spelling "$MOCK_DIR/s3"
new_mock; p0_snap; run_arm ARM_STATE_DIR="$MOCK_DIR/s4/y/../x"; p0_nothing_created STATE-dir-spelling "$MOCK_DIR/s4"
new_mock; p0_snap
( cd "$MOCK_DIR" && env -i PATH="$STUB_DIR:$TOOLDIR" EVENTS="$EVENTS" MOCK_DIR="$MOCK_DIR" ARM_SYSTEMD_DIR="$MOCK_DIR/etc-systemd" ARM_RUNTIME_DIR="$MOCK_DIR/run-systemd" ARM_INSTALL_DIR="$MOCK_DIR/opt" FENCE_MARKER_DIR="$MOCK_DIR/markers" ARM_STATE_DIR="rel/state" "$BASH_BIN" "$ARM" > "$MOCK_DIR/out" 2>&1 ); RC=$?
p0_nothing_created STATE-dir-spelling "$MOCK_DIR/rel"
new_mock; mkdir -p "$MOCK_DIR/real"; ln -s "$MOCK_DIR/real" "$MOCK_DIR/lnk"
p0_snap; run_arm ARM_STATE_DIR="$MOCK_DIR/lnk/newsub"; p0_nothing_created STATE-dir-symlink "$MOCK_DIR/real/newsub"
new_mock; mkdir -p "$MOCK_DIR/realanc"; ln -s "$MOCK_DIR/realanc" "$MOCK_DIR/anc2"
p0_snap; run_arm ARM_STATE_DIR="$MOCK_DIR/anc2/newsub/deeper"; p0_nothing_created STATE-dir-symlink "$MOCK_DIR/realanc/newsub"
new_mock; ln -s "$MOCK_DIR/nowhere" "$MOCK_DIR/dangling"
p0_snap; run_arm ARM_STATE_DIR="$MOCK_DIR/dangling/state"; p0_nothing_created STATE-dir-symlink "$MOCK_DIR/nowhere"
# fix round 3 (U3 — the delta panel 2's LB-3): a mkdir -p that fails PARTWAY — a 300-character component (ENAMETOOLONG)
# under a missing parent — is refused STATE-dir-missing, the REFUSE line names the path and says that part of it may
# remain, and NOTHING is removed: fix round 2's cleanup (rmdir of the created tail) followed a symlink raced onto an
# intermediate component and removed empty directories in its target (a pre-existing one included), where SAFETY
# said nothing is removed through a symlink — removed; what the failed mkdir created stays (newdir), as in fix round 1
new_mock; _lp="$MOCK_DIR/newdir/$(printf 'x%.0s' {1..300})"; p0_snap; run_arm ARM_STATE_DIR="$_lp"
p0_partial_ok=0; p0_refused STATE-dir-missing && [[ -d "$MOCK_DIR/newdir" ]] && grep -qF "ARM_STATE_DIR=$_lp cannot be created" "$MOCK_DIR/out" && grep -q 'may have left part of that path on disk' "$MOCK_DIR/out" && p0_kept && p0_partial_ok=1
p0_partial_why="rc=$RC newdir=$([[ -d "$MOCK_DIR/newdir" ]] && echo kept || echo REMOVED) $(p0_why)"
# the RACE: a symlink appears on an intermediate component (anc/a → victim) just before P0's mkdir -p runs — a racing
# mkdir fronting the real one (the (11d) wrapper idiom); victim/b, victim/keep and victim/file exist beforehand
STUB_RACE="$STUB_PARENT/race"; mkdir -p "$STUB_RACE"; cp "$STUB_DIR"/* "$STUB_RACE/"
_real_ln=$(command -v ln)
cat > "$STUB_RACE/mkdir" <<STUB
#!/bin/sh
if [ "\$1" = "-p" ] && [ -n "\${RACE_LINK:-}" ] && [ ! -e "\$RACE_LINK" ] && [ ! -L "\$RACE_LINK" ]; then '$_real_ln' -s "\$RACE_TARGET" "\$RACE_LINK"; fi
exec "$TOOLDIR/mkdir" "\$@"
STUB
chmod +x "$STUB_RACE/mkdir"
new_mock; mkdir -p "$MOCK_DIR/anc" "$MOCK_DIR/victim/b" "$MOCK_DIR/victim/keep"; : > "$MOCK_DIR/victim/file"; p0_snap
ARM_PATH="$STUB_RACE" run_arm ARM_STATE_DIR="$MOCK_DIR/anc/a/b/state" RACE_LINK="$MOCK_DIR/anc/a" RACE_TARGET="$MOCK_DIR/victim"
p0_race_ok=0
p0_refused STATE-dir-symlink && [[ -L "$MOCK_DIR/anc/a" ]] && grep -q "resolves to $MOCK_DIR/victim/b/state" "$MOCK_DIR/out" \
  && grep -q "FIX: if you did not create that link, stop and investigate" "$MOCK_DIR/out" \
  && [[ -d "$MOCK_DIR/victim/b/state" && -d "$MOCK_DIR/victim/b" && -d "$MOCK_DIR/victim/keep" && -f "$MOCK_DIR/victim/file" ]] \
  && p0_kept && p0_race_ok=1
p0_race_why="rc=$RC link=$([[ -L "$MOCK_DIR/anc/a" ]] && echo yes || echo no) created-tail=$([[ -d "$MOCK_DIR/victim/b/state" ]] && echo kept || echo REMOVED) b=$([[ -d "$MOCK_DIR/victim/b" ]] && echo kept || echo REMOVED) keep=$([[ -d "$MOCK_DIR/victim/keep" ]] && echo kept || echo REMOVED) $(p0_why) :: $(grep -E 'REFUSE|FIX' "$MOCK_DIR/out" | tr '\n' ' ' | cut -c1-300)"
# the STATIC half, on bash's own parse of the arm: P0 and every function it calls, transitively — a call = a word of a body's
# code view naming a function the parse defines (a nested one too) — except _arm_cleanup_probe (see the header)
P0_BP="$MOCK_PARENT/bp-arm"; bp_parse "$ARM" "$P0_BP" || : > "$P0_BP/FAIL"
p0_all=$(awk -F'\t' '$1 == "D" && $3 >= 1 { print $2 }' "$P0_BP/lex" | sort -u)
p0_fns=" _pre_state_dir_check "; p0_todo="_pre_state_dir_check"
while [[ -n "$p0_todo" ]]; do
    _f="${p0_todo%% *}"; p0_todo="${p0_todo#"$_f"}"; p0_todo="${p0_todo# }"
    for _w in $(awk -F'\t' -v f="$_f" '$1 == "L" && $2 == f { print $5 }' "$P0_BP/lex" | tr -c 'A-Za-z0-9_\n' ' '); do
        [[ "$_w" == "$_f" || "$_w" == "_arm_cleanup_probe" || " $p0_fns " == *" $_w "* ]] && continue
        printf '%s\n' "$p0_all" | grep -qx "$_w" || continue
        p0_fns="$p0_fns$_w "; p0_todo="${p0_todo:+$p0_todo }$_w"
    done
done
p0_norm=$(awk -F'\t' -v fs="$p0_fns" 'BEGIN { n = split(fs, a, " "); for (i = 1; i <= n; i++) F[a[i]] } $1 == "L" && ($2 in F) { print $6 } $1 == "H" && ($2 in F) { print $5 }' "$P0_BP/lex" | tr -d "\\\\\"'" | grep -cE '(^|[^A-Za-z0-9_])(rm|rmdir|unlink)([^A-Za-z0-9_]|$)')
p0_xc=$([[ -f "$P0_BP/FAIL" ]] && echo PARSE-FAIL; bp_xcheck "$ARM" "$P0_BP" | tr '\n' ';')
if [[ "$cr_ok" == "$cr_ct" && $p0_partial_ok -eq 1 && $p0_race_ok -eq 1 && "$p0_norm" == "0" && " $p0_fns " == *" _arm_refuse "* && -z "$p0_xc" ]]; then
    ok "(16h) a refusal by spelling or by the existing ancestor creates NOTHING ($cr_ok/$cr_ct: trailing '/', '//', '/./', '/../' and a relative path under missing parents → STATE-dir-spelling; a symlinked ancestor with a missing leaf (one and two levels) and a DANGLING symlink ancestor → STATE-dir-symlink) — the nearest existing ancestor is checked before any mkdir; a mkdir failing PARTWAY (a 300-character component under a missing parent) → STATE-dir-missing naming the path and saying part of it may remain — what it created stays (newdir); a symlink RACED onto an intermediate component before P0's mkdir -p (anc/a → victim) → mkdir -p creates the tail inside the link's target, the post-mkdir check refuses STATE-dir-symlink naming the resolved path, the FIX line says to stop and investigate a link the operator did not create, and nothing under the target is removed. P0 REMOVES NOTHING: in every one of these refusals every path the scenario made is still there and no rm / rmdir / unlink ran (any tool, any spelling, on these paths); on bash's own parse, P0 and the functions it calls ($(printf '%s' "$p0_fns" | wc -w | tr -d ' '): P0,$(printf ' %s' $p0_fns | sed 's/ _pre_state_dir_check//')) hold no rm / rmdir / unlink word (quotes and backslashes deleted, any path prefix), and bash sourcing the arm defines exactly the parse's $(grep -c . "$P0_BP/names") functions"
else
    bad "(16h) $((cr_ct - cr_ok))/$cr_ct:$cr_miss :: partial-mkdir refused+named+kept=$p0_partial_ok [$p0_partial_why] :: race=$p0_race_ok [$p0_race_why] :: P0 remove words=$p0_norm over [$p0_fns] :: parse-vs-exec [$p0_xc]"
fi
# (16d) a missing directory under a resolved parent is CREATED, then passes (the arm's mkdir -p, as before)
new_mock
rm -rf "$MOCK_DIR/state"
run_arm
if [[ "$RC" == "0" && -d "$MOCK_DIR/state" && -f "$MOCK_DIR/state/arm-generation" ]] && grep -q "precondition 0 OK: the state directory $MOCK_DIR/state is its own resolved path" "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
    ok "(16d) a MISSING state directory under a resolved parent → created, P0 OK line, arm completes with the token (no availability cost for the fresh-host case)"
else
    bad "(16d) rc=$RC out: $(tail -2 "$MOCK_DIR/out" | tr '\n' ' ')"
fi
# (16e) a FILE at ARM_STATE_DIR → REFUSE[STATE-dir-missing] before anything is installed (it used to
# install the units and refuse only at the token — (11d)'s old sabotage)
new_mock
rm -rf "$MOCK_DIR/state"; : > "$MOCK_DIR/state"
p0_snap; run_arm
if p0_refused STATE-dir-missing && grep -q "remove whatever non-directory sits at that path BY HAND" "$MOCK_DIR/out" && p0_kept; then
    ok "(16e) a FILE at ARM_STATE_DIR → REFUSE[STATE-dir-missing] with the by-hand fix, BEFORE any unit is rendered (was: units installed, then REFUSE[TOKEN-persist]); the file stays — the arm removes nothing"
else
    bad "(16e) rc=$RC $(p0_why) out: $(grep -E 'REFUSE|FIX' "$MOCK_DIR/out" | tr '\n' ' ' | cut -c1-300)"
fi
# (16f) ORDER: P0 runs after the role/env detection (whose sourced env cannot re-point the roots) and
# before P1 and the first write into the directory (P3's flock probe)
p0_ln=$(grep -n '^[[:space:]]*_pre_state_dir_check[[:space:]]*#' "$ARM" | cut -d: -f1)
role_ln=$(grep -n '^[[:space:]]*_arm_detect_role_env$' "$ARM" | cut -d: -f1)
p1_ln=$(grep -n '^[[:space:]]*_pre_v07_check$' "$ARM" | cut -d: -f1)
p3_ln=$(grep -n '^[[:space:]]*_pre_flock_check$' "$ARM" | cut -d: -f1)
if [[ -n "$p0_ln" && -n "$role_ln" && -n "$p1_ln" && -n "$p3_ln" && $p0_ln -eq $((role_ln + 1)) && $p0_ln -lt $p1_ln && $p0_ln -lt $p3_ln ]]; then
    ok "(16f) main(): _pre_state_dir_check runs right after the role/env detection (l$role_ln → l$p0_ln), before P1 (l$p1_ln) and P3's first write (l$p3_ln)"
else
    bad "(16f) placement: role=$role_ln p0=$p0_ln p1=$p1_ln p3=$p3_ln"
fi
# (16g) MIRRORED, not re-invented: the arm's canonicalization is the daemon's, character for character
# (modulo the variable), and on every spelling above the daemon's own reason-printer agrees
arm_can=$(grep -o "CDPATH='' cd -P -- \"\$ARM_STATE_DIR\" 2>/dev/null && pwd -P" "$ARM" | head -1)
dmn_can=$(grep -o "CDPATH='' cd -P -- \"\$PROOF_STATE_DIR\" 2>/dev/null && pwd -P" "$HARNESS_DIR/solana-standby-failover.sh" | head -1)
why_def=$(awk '/^_elapsed_tok_symlink_why\(\) \{/,/^\}/' "$HARNESS_DIR/solana-standby-failover.sh")
agree=1; disagree=""
if [[ -n "$arm_can" && -n "$dmn_can" && "${arm_can//ARM_STATE_DIR/X}" == "${dmn_can//PROOF_STATE_DIR/X}" && -n "$why_def" ]]; then
    new_mock
    mkdir -p "$MOCK_DIR/real-state"; ln -s "$MOCK_DIR/real-state" "$MOCK_DIR/lnk"
    for sp in "$MOCK_DIR/state" "$MOCK_DIR/lnk" "$MOCK_DIR/state/" "$MOCK_DIR//state" "$MOCK_DIR/./state" "$MOCK_DIR/state/../state" "//$MOCK_DIR/state"; do
        d_says=$( eval "$why_def"; PROOF_STATE_DIR="$sp"; if _elapsed_tok_symlink_why >/dev/null; then echo refuse; else echo ok; fi )
        p0_snap; run_arm ARM_STATE_DIR="$sp"
        if grep -q 'REFUSE\[STATE-dir-' "$MOCK_DIR/out"; then a_says=refuse; else a_says=ok; fi
        [[ "$a_says" == "$d_says" ]] || { agree=0; disagree="$disagree [$sp arm=$a_says daemon=$d_says]"; }
        [[ "$a_says" != "refuse" ]] || p0_kept || { agree=0; disagree="$disagree [$sp refused but removed: $(p0_why)]"; }
        new_mock; mkdir -p "$MOCK_DIR/real-state"; ln -s "$MOCK_DIR/real-state" "$MOCK_DIR/lnk"
    done
else
    agree=0; disagree="the canonicalization lines differ or the daemon's reason-printer was not found (arm='$arm_can' daemon='$dmn_can')"
fi
if [[ $agree -eq 1 ]]; then
    ok "(16g) the arm's test IS the daemon's R-SYM test (same cd -P/pwd -P line) and they AGREE on all 7 spellings (resolved, symlink, trailing '/', '//', '/./', '/../', leading '//'); every refusal among them removed nothing"
else
    bad "(16g) arm and daemon disagree:$disagree"
fi

# ── (13) reuse parity: the unit-discovery helpers are BYTE-IDENTICAL arm ↔ fence ────────────────
echo ""; echo "─── (13) _validator_pid + _detect_validator_unit byte-parity (reuse, not reinvention) ───"
A_VP=$(extract_region "$ARM"   '^_validator_pid() {' '^}$')
F_VP=$(extract_region "$FENCE" '^_validator_pid() {' '^}$')
if [[ -n "$A_VP" && "$A_VP" == "$F_VP" ]]; then
    ok "(13a) _validator_pid BYTE-IDENTICAL arm ↔ fence"
else
    bad "(13a) _validator_pid diverged (arm=${#A_VP}B fence=${#F_VP}B)"
fi
A_DU=$(extract_region "$ARM"   '^_detect_validator_unit() {' '^}$')
F_DU=$(extract_region "$FENCE" '^_detect_validator_unit() {' '^}$')
if [[ -n "$A_DU" && "$A_DU" == "$F_DU" ]]; then
    ok "(13b) _detect_validator_unit BYTE-IDENTICAL arm ↔ fence (cgroup detection reused, not reinvented)"
else
    bad "(13b) _detect_validator_unit diverged (arm=${#A_DU}B fence=${#F_DU}B)"
fi

# ── (14) byte-safety ────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (14) bash -n + shellcheck (if installed) ───"
if "$BASH_BIN" -n "$ARM" 2>/dev/null; then
    ok "(14a) bash -n clean under $("$BASH_BIN" --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1) (run_all's parse gate covers the 3.2 leg)"
else
    bad "(14a) bash -n failed on failover-arm.sh"
fi
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -S error "$ARM" >/dev/null 2>&1; then
        ok "(14b) shellcheck -S error clean"
    else
        bad "(14b) shellcheck -S error found issues"
    fi
else
    ok "(14b) shellcheck not installed here — CI's shellcheck job covers it (skipped)"
fi

# ── (B) boundary grep-proof (the HARD BOUNDARY, doubled for this slice) ─────────────────────────
echo ""; echo "─── (B) boundary: canonical paths untouched; stubs shadow systemctl; no systemd-run ───"
b_ok=1
for p in /etc/systemd/system/solana-failover-monitor.service \
         /etc/systemd/system/solana-failover-fence.service \
         /etc/systemd/system/solana-failover-fence-page-only.service \
         /run/systemd/system/solana-failover-arm-probe.service \
         /run/systemd/system/solana-failover-arm-probe-fence.service; do
    [[ -e "$p" ]] && { b_ok=""; echo "      CANONICAL PATH EXISTS: $p"; }
done
if [[ -n "$b_ok" ]]; then
    ok "(B1) none of the five canonical unit paths exists after the full run (no /etc, no /run/systemd write)"
else
    bad "(B1) a canonical systemd path appeared — the boundary is breached"
fi
got=$(env -i PATH="$STUB_DIR:$TOOLDIR" /bin/sh -c 'command -v systemctl')
if [[ "$got" == "$STUB_DIR/systemctl" ]]; then
    ok "(B2) under the scenario PATH, systemctl resolves to the stub — no real systemd is reachable"
else
    bad "(B2) systemctl resolves to: $got"
fi
if grep -v '^[[:space:]]*#' "$ARM" | grep '/etc/systemd/system' | grep -v 'ARM_SYSTEMD_DIR:-/etc/systemd/system' | grep -q .; then
    bad "(B3) failover-arm.sh touches /etc/systemd/system outside the ARM_SYSTEMD_DIR default"
else
    ok "(B3) arm's only /etc/systemd/system is the ARM_SYSTEMD_DIR:- default expansion (env-overridable root)"
fi
if grep -v '^[[:space:]]*#' "$ARM" | grep '/run/systemd' | grep -v 'ARM_RUNTIME_DIR:-/run/systemd/system' | grep -q .; then
    bad "(B4) failover-arm.sh touches /run/systemd outside the ARM_RUNTIME_DIR default"
else
    ok "(B4) arm's only /run/systemd is the ARM_RUNTIME_DIR:- default expansion (env-overridable root)"
fi
if grep -q 'systemd-run' "$ARM" 2>/dev/null; then
    bad "(B5) failover-arm.sh invokes systemd-run (an unmocked actuator — the probe pair rides ARM_RUNTIME_DIR instead)"
else
    ok "(B5) no systemd-run anywhere in the arm (the transient pair is rendered into ARM_RUNTIME_DIR, per the task's §2.1-rev2.1 mechanism)"
fi
# (B6)/(B7): deletion-stub NON-VACUITY tripwires (fix round 2 — the reviewer's blocker class;
# post-GO reviewer correction: assert the runner's ACTUAL path, not a reconstruction).
# On a tool-bearing host (/usr/bin/socat, /usr/bin/flock installed) the OLD appended-system-path
# scheme resolved these anyway and the deletion controls were empty; under "$STUB:$TOOLDIR" they
# must resolve NOWHERE. The PATH asserted below is _LAST_ARM_PATH as snapshotted at the deletion
# cases — the exact string run_arm passed to env -i. The first cut of these tripwires REBUILT
# "$STUB_NOSOCAT:$TOOLDIR" locally: when the reviewer re-broke the runner (appending
# /usr/bin:/bin at the env -i site) the controls went red but the tripwires stayed green —
# guarding a form the runner no longer used. A missing snapshot is itself a failure (a deleted
# snapshot line must not turn the tripwire vacuous). These hold on tool-less machines trivially
# and on tool-bearing machines meaningfully — the suite carries its own proof that the (2)/(3c)
# reds cannot go vacuous again.
if [[ -z "$_SNAP_PATH_NOSOCAT" ]]; then
    bad "(B6) no snapshot: the (2a) deletion case never recorded _LAST_ARM_PATH — the tripwire has nothing real to assert"
else
    got=$(env -i PATH="$_SNAP_PATH_NOSOCAT" /bin/sh -c 'command -v socat' 2>/dev/null)
    if [[ -z "$got" ]]; then
        ok "(B6) deletion is real: under the no-socat PATH run_arm ACTUALLY used, socat resolves NOWHERE — even where /usr/bin/socat exists (the vacuous-control class, killed)"
    else
        bad "(B6) deletion stub VACUOUS: socat reachable under the runner's no-socat PATH → $got"
    fi
fi
if [[ -z "$_SNAP_PATH_NOFLOCK" ]]; then
    bad "(B7) no snapshot: the (3c) deletion case never recorded _LAST_ARM_PATH — the tripwire has nothing real to assert"
else
    got=$(env -i PATH="$_SNAP_PATH_NOFLOCK" /bin/sh -c 'command -v flock' 2>/dev/null)
    if [[ -z "$got" ]]; then
        ok "(B7) …and flock resolves NOWHERE under the no-flock PATH run_arm ACTUALLY used — (3c) is exercisable on BOTH legs, never platform-conditional"
    else
        bad "(B7) deletion stub VACUOUS: flock reachable under the runner's no-flock PATH → $got"
    fi
fi

# ── (M) mutation controls: each refuse-gate neutered → its case red ─────────────────────────────
echo ""; echo "─── (M) controls: neuter each refuse-gate in a copy → the guarded scenario escapes ───"
if [[ -f "$ARM" ]]; then
    # the mutant copy must still see the release tree beside it (_ARM_SRC_DIR is dirname of the
    # script): a systemd/ symlink in the mutant's dir keeps the skels + fence bodies reachable
    [[ -e "$_HARNESS_TMP/systemd" ]] || ln -s "$SKEL_DIR" "$_HARNESS_TMP/systemd"
    MUT="$_HARNESS_TMP/arm-mut.sh"
    # M1: patsub gate (fixture: watchdog-capable daemon WITHOUT the guard, so the neutered
    # patsub gate is the ONLY thing between it and an arm — P1-capability must not mask it)
    if mutate "$ARM" 's/^\( *\)_arm_refuse "P1-patsub"/\1: "P1-patsub"/' "$MUT"; then
        new_mock
        write_daemon "$MOCK_DIR/opt/solana-primary-failover.sh"
        grep -v 'shopt -u patsub' "$MOCK_DIR/opt/solana-primary-failover.sh" > "$MOCK_DIR/opt/d.t" && mv "$MOCK_DIR/opt/d.t" "$MOCK_DIR/opt/solana-primary-failover.sh"
        ARM_OVERRIDE="$MUT" run_arm
        if ! grep -q 'REFUSE\[P1-patsub\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
            ok "(M1) P1 gate neutered → un-upgraded host ARMS (case 1a observes a load-bearing gate)"
        else
            bad "(M1) control vacuous: rc=$RC out: $(tail -2 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
        fi
    fi
    # M2: socat gate
    if mutate "$ARM" 's/^\( *\)_arm_refuse "P2-socat"/\1: "P2-socat"/' "$MUT"; then
        new_mock
        ARM_OVERRIDE="$MUT" ARM_PATH="$STUB_NOSOCAT" run_arm
        if ! grep -q 'REFUSE\[P2-socat\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
            ok "(M2) P2 gate neutered → socat-less host ARMS (case 2 observes a load-bearing gate)"
        else
            bad "(M2) control vacuous: rc=$RC"
        fi
    fi
    # M3: identity gate
    if mutate "$ARM" 's/^\( *\)_arm_refuse "P4-identity"/\1: "P4-identity"/' "$MUT"; then
        new_mock
        write_unitfile "--identity /somewhere/else/staked.json"
        ARM_OVERRIDE="$MUT" run_arm
        if ! grep -q 'REFUSE\[P4-identity\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
            ok "(M3) P4 gate neutered → real fence ARMS over a mismatched --identity (case 4a observes a load-bearing gate)"
        else
            bad "(M3) control vacuous: rc=$RC"
        fi
    fi
    # M4: probe-marker gate
    if mutate "$ARM" 's/^\( *\)_arm_refuse "PROBE-marker"/\1: "PROBE-marker"/' "$MUT"; then
        new_mock
        rm -f "$MOCK_DIR/probe.fires"
        ARM_OVERRIDE="$MUT" run_arm ARM_PROBE_WAIT=2
        if ! grep -q 'REFUSE\[PROBE-marker\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
            ok "(M4) probe gate neutered → unproven wiring ARMS (case 7 observes a load-bearing gate)"
        else
            bad "(M4) control vacuous: rc=$RC"
        fi
    fi
    # M5: verify gate
    if mutate "$ARM" 's/^\( *\)_arm_refuse "VERIFY-mismatch"/\1: "VERIFY-mismatch"/' "$MUT"; then
        new_mock
        write_env 'DRY_RUN=true'
        mkdir -p "$MOCK_DIR/etc-systemd/solana-failover-fence.service"
        ARM_OVERRIDE="$MUT" run_arm
        if ! grep -q 'REFUSE\[VERIFY-mismatch\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
            ok "(M5) verify gate neutered → render→hope ships a two-unit host (case 12 observes a load-bearing gate)"
        else
            bad "(M5) control vacuous: rc=$RC"
        fi
    fi
    # M6 (panel M-A, killed): the pre-probe stale-marker clean is load-bearing — deleting the
    # rm flips case (7d)'s refusal (the stale path is then caught as UNREMOVABLE instead of
    # cleaned): observed, not assumed.
    if mutate "$ARM" 's/rm -f "\$PROBE_MARKER" 2>\/dev\/null *# M-A pre-probe stale clean/: # M-A rm neutered/' "$MUT"; then
        new_mock
        touch "$MOCK_DIR/markers/arm-probe.fired"
        rm -f "$MOCK_DIR/probe.fires"
        ARM_OVERRIDE="$MUT" run_arm ARM_PROBE_WAIT=2
        if ! grep -q 'REFUSE\[PROBE-marker\]' "$MOCK_DIR/out" && grep -q 'REFUSE\[PROBE-marker-stale\]' "$MOCK_DIR/out"; then
            ok "(M6) pre-probe stale clean neutered → case (7d)'s expected refusal vanishes (stale path detected as unremovable instead): the rm is load-bearing, observed (panel M-A dead)"
        else
            bad "(M6) control vacuous: rc=$RC out: $(tail -2 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
        fi
    fi
    # M7: capability gate
    if mutate "$ARM" 's/^\( *\)_arm_refuse "P1-capability"/\1: "P1-capability"/' "$MUT"; then
        new_mock
        printf '#!/bin/bash\nshopt -u patsub_replacement 2>/dev/null || true\necho v0.6.10 daemon\n' > "$MOCK_DIR/opt/solana-primary-failover.sh"
        ARM_OVERRIDE="$MUT" run_arm
        if ! grep -q 'REFUSE\[P1-capability\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
            ok "(M7) P1-capability gate neutered → a v0.6.10 host ARMS a READY-less monitor (case 1f observes a load-bearing gate)"
        else
            bad "(M7) control vacuous: rc=$RC"
        fi
    fi
    # M8: unverifiable-identity gate
    if mutate "$ARM" 's/^\( *\)_arm_refuse "P4-unverifiable"/\1: "P4-unverifiable"/' "$MUT"; then
        new_mock
        mkdir -p "$MOCK_DIR/nobin"
        write_env "SOLANA_PATH=\"$MOCK_DIR/nobin\""
        ARM_OVERRIDE="$MUT" run_arm
        if ! grep -q 'REFUSE\[P4-unverifiable\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]]; then
            ok "(M8) P4-unverifiable gate neutered → real fence ARMS with the KEY never verified (case 4j observes a load-bearing gate)"
        else
            bad "(M8) control vacuous: rc=$RC"
        fi
    fi
    # M9: sibling gate
    if mutate "$ARM" 's/^\( *\)_arm_refuse "INSTALL-sibling"/\1: "INSTALL-sibling"/' "$MUT"; then
        new_mock
        mkdir -p "$MOCK_DIR/etc-systemd/solana-failover-fence-page-only.service"
        ARM_OVERRIDE="$MUT" run_arm
        if ! grep -q 'REFUSE\[INSTALL-sibling\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" ]] && [[ -e "$MOCK_DIR/etc-systemd/solana-failover-fence.service" && -e "$MOCK_DIR/etc-systemd/solana-failover-fence-page-only.service" ]]; then
            ok "(M9) sibling gate neutered → ARMS with BOTH fence units on disk (the §2.3 violation case 9k exists to refuse)"
        else
            bad "(M9) control vacuous: rc=$RC etc: $(ls "$MOCK_DIR/etc-systemd" 2>/dev/null | tr '\n' ' ')"
        fi
    fi
    # M10: the render-verify TRIPWIRE — corrupt the renderer itself in a copy; the content
    # verification must catch it (the A13 class: a garbage ExecStart must never arm silently)
    if mutate "$ARM" 's/ExecStart=%s\\n/ExecStart=%s-CORRUPT\\n/' "$MUT"; then
        new_mock
        ARM_OVERRIDE="$MUT" run_arm
        if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[RENDER-verify\]' "$MOCK_DIR/out" && [[ -z "$(token_line)" ]]; then
            ok "(M10) renderer corrupted in a copy → REFUSE[RENDER-verify]: rendered content is VERIFIED against the request, never assumed (A13's class is a tripwire now)"
        else
            bad "(M10) control vacuous: rc=$RC out: $(tail -2 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
        fi
    fi
    # M11: the legacy-retire step (fix round 2 blocker) — neutered, the DUAL-MONITOR arm from
    # the observed red must reappear: ceremony completes, new monitor enabled, legacy monitor
    # STILL active+enabled, zero retire narration.
    if mutate "$ARM" 's/^\( *\)_retire_legacy_monitors$/\1: # retire neutered/' "$MUT"; then
        new_mock
        printf '[Service]\nRestart=always\n' > "$MOCK_DIR/etc-systemd/solana-failover.service"
        touch "$MOCK_DIR/active.solana-failover.service" "$MOCK_DIR/enabled.solana-failover.service"
        ARM_OVERRIDE="$MUT" run_arm
        if [[ -n "$(token_line)" ]] && [[ -f "$MOCK_DIR/active.solana-failover.service" && -f "$MOCK_DIR/enabled.solana-failover.service" ]] && grep -q '^systemctl enable solana-failover-monitor.service$' "$EVENTS" && ! grep -q 'legacy monitor retired' "$MOCK_DIR/out"; then
            ok "(M11) retire step neutered → the dual-monitor arm completes (token printed, new monitor enabled, legacy STILL active+enabled): case (15) observes a load-bearing step"
        else
            bad "(M11) control vacuous: rc=$RC token=$(token_line) legacy-active=$([[ -f "$MOCK_DIR/active.solana-failover.service" ]] && echo yes || echo no)"
        fi
    fi
    # M12 (Block 6.3.1 D5): the P0 symlinked-state-directory refusal — neutered, a symlinked
    # ARM_STATE_DIR ARMS and the gen counter lands THROUGH the link (the pre-6.3.1 behavior)
    if mutate "$ARM" 's/^\( *\)_arm_refuse "STATE-dir-symlink"/\1: "STATE-dir-symlink"/' "$MUT"; then
        new_mock
        mkdir -p "$MOCK_DIR/real-state"; rm -rf "$MOCK_DIR/state"; ln -s "$MOCK_DIR/real-state" "$MOCK_DIR/state"
        ARM_OVERRIDE="$MUT" run_arm
        if ! grep -q 'REFUSE\[STATE-dir-symlink\]' "$MOCK_DIR/out" && [[ -n "$(token_line)" && -f "$MOCK_DIR/real-state/arm-generation" ]]; then
            ok "(M12) P0 symlink refusal neutered → a symlinked state directory ARMS and the gen counter is written THROUGH the link (case 16a observes a load-bearing gate)"
        else
            bad "(M12) control vacuous: rc=$RC out: $(tail -2 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
        fi
    fi
    echo "  survivors (named, per HARNESS.md discipline): P3 flock and the P4 page-only/frankendancer/"
    echo "  override branches are WARN-not-refuse by design — asserted POSITIVELY in (3)/(4c)/(4d)/(4k),"
    echo "  no refuse to neuter; the P5 announcement is informational. The token-lock residual (flock"
    echo "  absent/busybox → unlocked bump) is named in the arm and WARNed at P3 — not a gate. The"
    echo "  legacy-retire detection PROBES (is-active/is-enabled per wizard name) are read-only and"
    echo "  asserted positively in (15h); the retire ACTIONS and refusals are gated (M11, 15e/15f)."
    echo "  No other refuse-gate is uncontrolled."
else
    bad "(M) failover-arm.sh missing — mutation controls cannot run"
fi

# raw-data traces for the report
echo ""
echo "  trace (6):  rc=$T6_RC  $T6_TRACE"
echo "  trace (7):  rc=$T7_RC  (probe timeout → refuse)"
echo "  token (11a): $T11_TOKEN"
echo "  token (10b): $T10_TOKEN"

rm -rf "$STUB_PARENT" "$MOCK_PARENT"

results_banner
