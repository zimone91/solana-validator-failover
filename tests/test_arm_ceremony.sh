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
#   (13) reuse parity: _validator_pid + _detect_validator_unit BYTE-IDENTICAL arm ↔ fence
#   (14) bash -n + shellcheck (if installed)
#   (B)  boundary grep-proof: canonical /etc + /run/systemd paths untouched by the whole run;
#        stub systemctl shadows any real one; arm's only /etc//run defaults live in the
#        ARM_*_DIR:- expansions; no systemd-run anywhere; (B6)/(B7) deletion-stub non-vacuity
#        (socat/flock resolve NOWHERE under the deletion PATHs, even on tool-bearing hosts)
#   (M)  mutation controls (each refuse-gate neutered → its case would go RED): M1 patsub, M2
#        socat, M3 identity, M4 probe-marker, M5 verify, M6 pre-probe stale clean (panel M-A),
#        M7 capability, M8 unverifiable-identity, M9 sibling, M10 render-verify tripwire,
#        M11 legacy-retire (neutered → the dual-monitor arm completes, observed).
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
TOOLDIR="$STUB_PARENT/tools"
mkdir -p "$TOOLDIR"
ARM_REAL_TOOLS="awk basename cat chmod cksum cp cut date dirname grep head hostname mkdir mv readlink rm sed tail touch tr"
for _t in $ARM_REAL_TOOLS; do
    _tp=$(command -v "$_t" 2>/dev/null)
    if [[ -z "$_tp" || ! -x "$_tp" ]]; then
        echo "  ❌ FAIL: TOOLDIR provisioning: no real '$_t' on the host PATH — the suite cannot build its scenario PATH"
        exit 1
    fi
    ln -s "$_tp" "$TOOLDIR/$_t"
done

# ── scenario plumbing ───────────────────────────────────────────────────────────────────────────
MOCK_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/arm-mocks.XXXXXX")
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
new_mock
rm -rf "$MOCK_DIR/state"; : > "$MOCK_DIR/state"      # ARM_STATE_DIR is a FILE → gen write must fail (root-proof sabotage)
run_arm
if [[ "$RC" == "1" ]] && grep -q 'REFUSE\[TOKEN-persist\]' "$MOCK_DIR/out" && [[ -z "$(token_line)" ]] && ! grep -q 'ceremony complete' "$MOCK_DIR/out"; then
    ok "(11d) token cannot persist → arm REFUSES to complete (exit 1, no token, no ARMED line; re-pair is ceremony)"
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
