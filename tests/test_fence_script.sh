#!/bin/bash
# v0.7 (Block 5.1 + panel fix round): the fence script PROPER — systemd/failover-fence.sh driven
# as a SUBPROCESS behind a mock PATH. Every actuator is a stub: agave-validator (scriptable
# per-call rc/identity via plan files — the take_timeout idiom, subprocess form), systemctl
# (records + scriptable rc), pgrep (process model via a static proc file OR a per-call
# proc.seq), timeout/sleep shims. NO REAL systemctl CALL CAN RUN: every scenario executes with
# PATH="$STUB_DIR:…" and the fence invokes bare `systemctl` (never a path), always wrapped in
# `timeout` — whose shim exec's back into the stub PATH.
# KILL-BUILTIN CONTAINMENT (single, named): `kill` is a bash BUILTIN — the stub PATH cannot
# intercept it, so the kill INVOCATIONS themselves are STRUCTURALLY UNOBSERVABLE here: a mutant
# deleting just the `kill`/`kill -9` lines stays GREEN (verified by execution — the recorded
# coverage hole, not an oversight; testing those lines needs a kill seam in the fence,
# deliberately not added). Scenario (18)'s per-call proc.seq ledger DOES pin the surrounding
# pid-read structure — a wholesale deletion of the fallback rungs trips it — but never the kills.
# The ONE containment for the kill calls is the stub pgrep pid 2147483647 (> every real pid
# ceiling: Linux PID_MAX_LIMIT 4194304, macOS kern.maxproc ~16000; still a valid pid_t) — every
# kill hits ESRCH, so no real process can ever receive a signal from a test run.
# An ordered EVENT LOG ($EVENTS, appended by every stub) proves sequences, not just call counts.
#
# Cases (TASK-block51 + TASK-block51-fixes):
#   (1)  happy demote: exact ladder order, fenced-demoted, NO stop; reason counts the reads
#   (2)  wedged set-identity → stop-fallback, cgroup-DETECTED unit; (2b) stop wedged →
#        fenced-stopped ANYWAY + exit 1 (claim-more)
#   (3)  re-poll sees staked again (stale write landed) → stop-fallback
#   (4)  already unstaked → fenced-demoted, ZERO admin mutations
#   (5)  §2.2 third branch → restart-monitor only; the restart is an ENQUEUE (--no-block)
#   (6)  unreadable, no startup evidence → stop path
#   (7)  breaker: (7a) FRESH fenced-stopped → refuse + restart-monitor; (7b) fenced-demoted →
#        re-run allowed (the asymmetry)
#   (8)  unit detection: env wins; cgroup v2 + v1; neither → no stop + exit 1
#   (9)  page-only twin: marker + ZERO mutation events + structural grep
#   (10) ladder-order mutation control (swap → RED)
#   (11) bash -n + shellcheck
#   (12) B1: STALE fenced-stopped (pre-boot mtime) → breaker ignored, fences normally, stale page
#   (13) B1: uptime unreadable → treated STALE
#   (14) B1-note: set-identity FAILED + proc gone → NOT excused → stop
#   (15) B1-note: ACCEPTED set-identity + proc gone → fenced-demoted, DISTINCT honest reason
#   (16) re-poll unreadable + process ALIVE → stop (panel mutant X5's killer)
#   (17) stop-UNCONFIRMED: stop rc≠0 + no process ever seen → LOUDEST page + exit 1 (X2's killer)
#   (18) Restart=always resurrection via proc.seq → delayed re-verify catches it (X1's killer)
#   (19) remove-all failures: first wedged → stop; BARRIER wedged NOT excused by proc-gone (X4's killer)
#   (20) UNSTAKED_KEYPAIR missing → guard fires before the admin call → stop (X6's killer)
#   (21) shipped-default repoll (NO env override) = 5 reads; floor clamp 0→1
#   (22) B2: restart enqueue failure → page; enqueue-ok-slow-READY → NO false page
#   (23) twin/flock: held instance lock → second fence exits 0 without acting (skip if no flock)
#   (24) marker precedence: a demote outcome NEVER overwrites fenced-stopped
#   (25) startup-evidence word anchor: "restarting" is NOT startup evidence

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
FENCE="$HARNESS_DIR/systemd/failover-fence.sh"
PAGEONLY="$HARNESS_DIR/systemd/failover-fence-page-only.sh"
[[ -f "$FENCE" ]] || { echo "  ❌ FAIL: fence script not found: $FENCE"; exit 1; }
# The SUITE's own interpreter drives the subprocess — /bin/bash on the macOS 3.2 leg, the
# image's bash on the Linux 5.2 leg (the bash:5.2 image has NO /bin/bash — found red there).
BASH_BIN="${BASH:-/bin/bash}"

# ── the mock PATH (stubs record into $EVENTS; behavior scripted via $MOCK_DIR plan files) ───────
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fence-stubs.XXXXXX")

cat > "$STUB_DIR/agave-validator" <<'STUB'
#!/bin/sh
echo "agave-validator $*" >> "$EVENTS"
_pop() {  # print line 1 of plan file $1, consume it unless it is the last line (sticky-last)
    f="$MOCK_DIR/$1"
    [ -f "$f" ] || { echo ""; return; }
    head -1 "$f"
    n=$(wc -l < "$f")
    if [ "$n" -gt 1 ]; then tail -n +2 "$f" > "$f.t" && mv "$f.t" "$f"; fi
}
case "$*" in
    *contact-info*)
        line=$(_pop identity.seq)
        case "$line" in ""|FAIL) exit 1 ;; esac
        echo "Identity: $line"; exit 0 ;;
    *remove-all*)
        rc=$(_pop rc.remove); exit "${rc:-0}" ;;
    *set-identity*)
        rc=$(_pop rc.setid); exit "${rc:-0}" ;;
    *monitor*)
        [ -f "$MOCK_DIR/monitor.out" ] && cat "$MOCK_DIR/monitor.out"
        exit 0 ;;
esac
exit 0
STUB

cat > "$STUB_DIR/systemctl" <<'STUB'
#!/bin/sh
echo "systemctl $*" >> "$EVENTS"
case "$*" in
    stop\ *)
        rc=$(cat "$MOCK_DIR/rc.stop" 2>/dev/null); rc=${rc:-0}
        # a clean stop takes the process down unless the scenario pins it up
        if [ "$rc" = "0" ] && [ ! -f "$MOCK_DIR/stop.leaves.proc" ]; then echo 0 > "$MOCK_DIR/proc"; fi
        exit "$rc" ;;
    is-active*)
        rc=$(cat "$MOCK_DIR/rc.isactive" 2>/dev/null); exit "${rc:-0}" ;;
    restart*)
        rc=$(cat "$MOCK_DIR/rc.restart" 2>/dev/null); rc=${rc:-0}
        # B2 slow-READY model: restart.slowready pins a Type=notify monitor whose READY is
        # minutes away (first identity read mid-replay) — a job-BLOCKING restart (no
        # --no-block) times out exactly as real `timeout` reports it (rc 124), while an
        # ENQUEUE (--no-block) returns 0 immediately: the job proceeds, the wait does not.
        if [ -f "$MOCK_DIR/restart.slowready" ] && [ "$rc" = "0" ]; then
            case "$*" in *--no-block*) ;; *) rc=124 ;; esac
        fi
        exit "$rc" ;;
esac
exit 0
STUB

cat > "$STUB_DIR/pgrep" <<'STUB'
#!/bin/sh
echo "pgrep $*" >> "$EVENTS"
# Process model, two forms:
#   proc.seq — one line per pgrep INVOCATION, sticky-last (the resurrection seam: state can
#              flip mid-run). NOTE the fence's _validator_pid() costs ONE pgrep call when the
#              process is found (agave-validator) and TWO when it is not (agave-validator then
#              solana-validator) — sequence lines count INVOCATIONS, not _validator_pid calls.
#   proc     — static 1/0 (the systemctl stop stub flips it on a clean stop).
if [ -f "$MOCK_DIR/proc.seq" ]; then
    p=$(head -1 "$MOCK_DIR/proc.seq")
    n=$(wc -l < "$MOCK_DIR/proc.seq")
    if [ "$n" -gt 1 ]; then tail -n +2 "$MOCK_DIR/proc.seq" > "$MOCK_DIR/proc.seq.t" && mv "$MOCK_DIR/proc.seq.t" "$MOCK_DIR/proc.seq"; fi
else
    p=$(cat "$MOCK_DIR/proc" 2>/dev/null)
fi
if [ "$p" = "1" ]; then echo 2147483647; exit 0; fi
exit 1
STUB

cat > "$STUB_DIR/timeout" <<'STUB'
#!/bin/sh
# shim for the bounded-call idiom `timeout -k K DUR cmd…`: run cmd… and pass its rc through —
# a plan-file rc of 124/137 IS the wedge, exactly as real timeout would report it.
# ASSUMPTION (named): `shift 3` hard-codes the `-k K DUR` shape. Every timeout call site in the
# fence conforms today; a future bare `timeout DUR cmd…` would be mis-parsed here and exec the
# duration as a command → rc 127 → trace mismatch → this suite goes red LOUDLY, not silently.
shift 3
cmd="$1"; shift
case "$cmd" in
    */agave-validator|agave-validator) exec agave-validator "$@" ;;
esac
exec "$cmd" "$@"
STUB

printf '#!/bin/sh\nexit 0\n' > "$STUB_DIR/sleep"
chmod +x "$STUB_DIR/agave-validator" "$STUB_DIR/systemctl" "$STUB_DIR/pgrep" "$STUB_DIR/timeout" "$STUB_DIR/sleep"

# ── scenario plumbing ───────────────────────────────────────────────────────────────────────────
# All per-scenario mock dirs live under ONE parent, removed at the end (tmp hygiene — the old
# per-scenario mktemp dirs leaked).
MOCK_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/fence-mocks.XXXXXX")
new_mock() {
    MOCK_DIR=$(mktemp -d "$MOCK_PARENT/m.XXXXXX")
    mkdir -p "$MOCK_DIR/markers"
    EVENTS="$MOCK_DIR/events"; : > "$EVENTS"
    echo 1 > "$MOCK_DIR/proc"
    echo '[9,9]' > "$MOCK_DIR/unstaked.json"
}
# run_script <script> [VAR=val …] — subprocess run, clean env, stub PATH. RC + $MOCK_DIR/out.
# ${REPOLL_ENV-…} is DELIBERATELY unquoted: REPOLL_ENV unset → the suite default
# FENCE_REPOLL_SECS=3; REPOLL_ENV="" → NO repoll var in the child env at all (case 21a — the
# shipped default must be exercised, not the suite's speed override); REPOLL_ENV=VAR=val → that.
run_script() {
    local script="$1"; shift
    env -i PATH="$STUB_DIR:/usr/bin:/bin" \
        EVENTS="$EVENTS" MOCK_DIR="$MOCK_DIR" \
        FENCE_MARKER_DIR="$MOCK_DIR/markers" \
        SOLANA_PATH=/mock LEDGER_PATH=/mock/ledger \
        UNSTAKED_PUBKEY=U1 UNSTAKED_KEYPAIR="$MOCK_DIR/unstaked.json" \
        SETIDENTITY_TIMEOUT=15 ${REPOLL_ENV-FENCE_REPOLL_SECS=3} \
        MONITOR_UNIT=solana-failover-monitor.service \
        "$@" "$BASH_BIN" "$script" > "$MOCK_DIR/out" 2>&1
    RC=$?
}
trace() {   # ordered token trace from the event log (pgrep/sleep noise dropped)
    local line tok out=""
    while IFS= read -r line; do
        tok=""
        case "$line" in
            "systemctl stop"*)      tok=stop ;;
            "systemctl mask"*)      tok=mask ;;
            "systemctl restart"*)   tok=restart-monitor ;;
            "systemctl is-active"*) tok=is-active ;;
            pgrep*)                 tok="" ;;
            *contact-info*)         tok=read-id ;;
            *remove-all*)           tok=remove-all ;;
            *set-identity*)         tok=set-identity ;;
            *" monitor")            tok=probe ;;
        esac
        [[ -n "$tok" ]] && out="${out}${out:+,}${tok}"
    done < "$EVENTS"
    printf '%s' "$out"
}
marker_ok() {   # marker $1 exists AND opens with an ISO-8601 UTC stamp + a reason
    local f="$MOCK_DIR/markers/$1"
    [[ -f "$f" ]] || return 1
    head -1 "$f" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z .'
}
# the cgroup fixture: $1=cgroup file content → FENCE_PROC_ROOT dir with the stub pid's file
cg_fixture() {
    mkdir -p "$MOCK_DIR/proc_root/2147483647"
    printf '%s\n' "$1" > "$MOCK_DIR/proc_root/2147483647/cgroup"
}
# B1 freshness fixture: $1 = uptime seconds → ${FENCE_PROC_ROOT}/uptime (boot epoch = now − $1).
# Marker mtimes: `touch -t 202001010000` = provably PRE-BOOT (2020 ≪ any current boot epoch);
# a marker just written (mtime now) with a LARGE uptime (boot long ago) = provably SAME BOOT.
up_fixture() {
    mkdir -p "$MOCK_DIR/proc_root"
    printf '%s.00 0.00\n' "$1" > "$MOCK_DIR/proc_root/uptime"
}

title_banner "FENCE script proper (v0.7 Block 5.1 + panel fixes) — ladder, verdict, markers, breaker freshness"
EXPECT_HAPPY="read-id,remove-all,set-identity,remove-all,read-id,read-id,read-id,restart-monitor"

# ── (1) HAPPY DEMOTE ───────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) happy demote: staked → ladder order exact, fenced-demoted, NO stop ───"
new_mock
printf 'S1\nU1\n' > "$MOCK_DIR/identity.seq"    # verdict read: staked; every re-poll: unstaked
run_script "$FENCE"
t=$(trace)
if [[ "$RC" == "0" && "$t" == "$EXPECT_HAPPY" ]]; then
    ok "(1) event order exactly: $EXPECT_HAPPY (3 re-polls at FENCE_REPOLL_SECS=3); exit 0"
else
    bad "(1) rc=$RC trace=$t (expected $EXPECT_HAPPY)"
fi
if marker_ok fenced-demoted && [[ ! -f "$MOCK_DIR/markers/fenced-stopped" ]] && ! grep -q "systemctl stop" "$EVENTS"; then
    ok "(1) marker fenced-demoted (ISO stamp + reason), no fenced-stopped, zero systemctl stop"
else
    bad "(1) marker/stop wrong: $(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' '); events: $(cat "$EVENTS")"
fi
if grep -q "verified by 3 sustained unstaked reads" "$MOCK_DIR/markers/fenced-demoted"; then
    ok "(1c) marker reason counts the ACTUAL verified reads (truthful claim, no overclaim)"
else
    bad "(1c) marker: $(cat "$MOCK_DIR/markers/fenced-demoted" 2>/dev/null)"
fi
T1_TRACE="$t"; T1_RC="$RC"

# ── (2) WEDGED set-identity → stop-fallback with the DETECTED unit ─────────────────────────────
echo ""; echo "─── (2) set-identity rc 124 → stop-fallback: cgroup-v2-detected unit, fenced-stopped, exit 0 ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
cg_fixture '0::/system.slice/sol-detected.service/payload'
run_script "$FENCE" FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,set-identity,stop,restart-monitor" ]]; then
    ok "(2) wedge → stop-fallback, order read-id,remove-all,set-identity,stop,restart-monitor; exit 0"
else
    bad "(2) rc=$RC trace=$t"
fi
if grep -q "systemctl stop sol-detected.service" "$EVENTS" && marker_ok fenced-stopped; then
    ok "(2) stop used the cgroup-DETECTED unit (sol-detected.service) and wrote fenced-stopped"
else
    bad "(2) unit/marker wrong; events: $(cat "$EVENTS")"
fi
T2_TRACE="$t"; T2_RC="$RC"

# ── (2b) the stop itself wedged/unverifiable → fenced-stopped ANYWAY + exit 1 ──────────────────
echo ""; echo "─── (2b) stop rc 124 + process survives → fenced-stopped ANYWAY, exit 1 (claim-more direction) ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
echo 124 > "$MOCK_DIR/rc.stop"
touch "$MOCK_DIR/stop.leaves.proc"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
if [[ "$RC" == "1" ]] && marker_ok fenced-stopped && grep -q "systemctl mask --runtime sol-test.service" "$EVENTS"; then
    ok "(2b) unverifiable stop: mask --runtime attempted, marker fenced-stopped written anyway, exit 1"
else
    bad "(2b) rc=$RC markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ') events: $(cat "$EVENTS")"
fi

# ── (3) re-poll sees staked again (stale write landed) → stop-fallback ─────────────────────────
echo ""; echo "─── (3) stale write lands mid-window: re-poll reads staked → stop-fallback ───"
new_mock
printf 'S1\nU1\nS1\n' > "$MOCK_DIR/identity.seq"   # verdict: staked; poll1: unstaked; poll2: STAKED AGAIN
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,set-identity,remove-all,read-id,read-id,stop,restart-monitor" ]]; then
    ok "(3) 2nd re-poll read staked → ladder aborted into stop-fallback (the barrier's whole point)"
else
    bad "(3) rc=$RC trace=$t"
fi
if marker_ok fenced-stopped && [[ ! -f "$MOCK_DIR/markers/fenced-demoted" ]]; then
    ok "(3) outcome is fenced-stopped, never fenced-demoted, on a failed sustained window"
else
    bad "(3) markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi
T3_TRACE="$t"; T3_RC="$RC"

# ── (4) already unstaked → fenced-demoted, ZERO admin mutations ────────────────────────────────
echo ""; echo "─── (4) verdict (b): already unstaked → marker only, zero admin mutations, exit 0 ───"
new_mock
printf 'U1\n' > "$MOCK_DIR/identity.seq"
run_script "$FENCE"
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,restart-monitor" ]] && marker_ok fenced-demoted; then
    ok "(4) one read, marker fenced-demoted, restart-monitor — no set-identity/remove-all/stop"
else
    bad "(4) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi

# ── (5) §2.2 third branch: unreadable + alive + startup evidence → NO stop, NO marker ──────────
echo ""; echo "─── (5) unreadable + unit active + startup evidence → restart-monitor only ───"
new_mock
printf 'FAIL\n' > "$MOCK_DIR/identity.seq"
printf 'Ledger location: /mock/ledger\nValidator startup: LoadingLedger (starting)\n' > "$MOCK_DIR/monitor.out"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,is-active,probe,restart-monitor" ]]; then
    ok "(5) third branch: probe saw startup evidence → monitor restarted, NO stop"
else
    bad "(5) rc=$RC trace=$t"
fi
if [[ ! -f "$MOCK_DIR/markers/fenced-stopped" && ! -f "$MOCK_DIR/markers/fenced-demoted" ]]; then
    ok "(5) deliberately NO marker: not a fence outcome (pre-READY belongs to the live extension)"
else
    bad "(5) marker written: $(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q "systemctl restart --no-block solana-failover-monitor.service" "$EVENTS"; then
    ok "(5c) the monitor restart is an ENQUEUE (--no-block): READY is minutes away mid-replay; a killed blocking wait is not a canceled job"
else
    bad "(5c) restart event: $(grep 'systemctl restart' "$EVENTS" 2>/dev/null)"
fi

# ── (6) unreadable, NO startup evidence → stop path ────────────────────────────────────────────
echo ""; echo "─── (6) unreadable, probe shows no startup token → fail toward stop ───"
new_mock
printf 'FAIL\n' > "$MOCK_DIR/identity.seq"
printf 'Processed Slot: 12345\n' > "$MOCK_DIR/monitor.out"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,is-active,probe,stop,restart-monitor" ]] && marker_ok fenced-stopped; then
    ok "(6) no positive startup evidence → stopped + verified + fenced-stopped (absence ≠ evidence)"
else
    bad "(6) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi

# ── (7) crash-loop breaker (freshness-gated since the panel fix round) ─────────────────────────
echo ""; echo "─── (7) breaker: FRESH fenced-stopped → refuse + monitor restarted; demoted → re-run ───"
new_mock
printf 'S1\nU1\n' > "$MOCK_DIR/identity.seq"
echo 0 > "$MOCK_DIR/proc"                           # (re-panel DS-1): refusal requires a DOWN node — a live process makes the fence proceed (case 28)
up_fixture 30000                                    # boot long ago; the marker below is mtime NOW = same boot
printf '%s refusal fixture\n' "2026-08-20T00:00:00Z" > "$MOCK_DIR/markers/fenced-stopped"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
t=$(trace)
if [[ "$RC" == "0" && "$t" == *"restart-monitor"* && "$t" != *"remove-all"* ]] && grep -q "refusing to act twice" "$MOCK_DIR/out"; then
    ok "(7a) FRESH fenced-stopped + DOWN node → refused (no ladder, no stop) AND the dead monitor was restarted (page delivery + HOLD)"
else
    bad "(7a) rc=$RC trace=$t out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
new_mock
printf 'S1\nU1\n' > "$MOCK_DIR/identity.seq"
printf '%s rerun fixture\n' "2026-08-20T00:00:00Z" > "$MOCK_DIR/markers/fenced-demoted"
run_script "$FENCE"
t=$(trace)
if [[ "$RC" == "0" && "$t" == "$EXPECT_HAPPY" ]] && grep -q "ladder verified" "$MOCK_DIR/markers/fenced-demoted"; then
    ok "(7b) fenced-demoted present → re-run ALLOWED: full ladder ran, marker refreshed (the asymmetry)"
else
    bad "(7b) rc=$RC trace=$t marker: $(cat "$MOCK_DIR/markers/fenced-demoted" 2>/dev/null)"
fi

# ── (8) unit detection ─────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) VALIDATOR_UNIT env wins over cgroup; v1 fallback parse; neither → no stop + exit 1 ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
cg_fixture '0::/system.slice/sol-detected.service/payload'
run_script "$FENCE" FENCE_PROC_ROOT="$MOCK_DIR/proc_root" VALIDATOR_UNIT=env-wins.service
if grep -q "systemctl stop env-wins.service" "$EVENTS" && ! grep -q "sol-detected" "$EVENTS"; then
    ok "(8a) configured VALIDATOR_UNIT beat the cgroup detection"
else
    bad "(8a) events: $(cat "$EVENTS")"
fi
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
cg_fixture '1:name=systemd:/system.slice/sol-v1.service'
run_script "$FENCE" FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
if grep -q "systemctl stop sol-v1.service" "$EVENTS"; then
    ok "(8b) cgroup v1 fallback (systemd: line) parsed the unit"
else
    bad "(8b) events: $(cat "$EVENTS")"
fi
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
mkdir -p "$MOCK_DIR/proc_root"          # pid dir absent: detection finds nothing
run_script "$FENCE" FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
if [[ "$RC" == "1" ]] && marker_ok fenced-stopped && ! grep -q "systemctl stop" "$EVENTS"; then
    ok "(8c) no unit determinable → NO stop attempted, fenced-stopped claimed anyway, exit 1"
else
    bad "(8c) rc=$RC markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ') events: $(cat "$EVENTS")"
fi

# ── (9) the page-only twin (§2.3 structural DRY_RUN) ───────────────────────────────────────────
echo ""; echo "─── (9) page-only: marker fenced-page-only, zero admin/systemctl events, structural grep ───"
if [[ -f "$PAGEONLY" ]]; then
    new_mock
    printf 'S1\nU1\n' > "$MOCK_DIR/identity.seq"    # bait: a staked identity it must never touch
    run_script "$PAGEONLY"
    if [[ "$RC" == "0" && ! -s "$EVENTS" ]] && marker_ok fenced-page-only; then
        ok "(9a) page-only run: marker fenced-page-only + empty event log (no admin socket, no systemctl)"
    else
        bad "(9a) rc=$RC events: $(cat "$EVENTS") markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
    fi
    # structural: no mutation token on any NON-comment line (the Block-10 DRY_RUN sweep's grep)
    if grep -vE '^[[:space:]]*#' "$PAGEONLY" | grep -qE 'systemctl|set-identity|authorized-voter|pgrep|kill|mask'; then
        bad "(9b) mutation token found outside comments in $(basename "$PAGEONLY")"
    else
        ok "(9b) structural: zero mutation tokens (systemctl/set-identity/authorized-voter/pgrep/kill/mask) outside comments"
    fi
else
    bad "(9) page-only script missing: $PAGEONLY"
fi

# ── (10) ladder-order mutation control: the order assertion is load-bearing ────────────────────
echo ""; echo "─── (10) control: swap remove-all ↔ set-identity in a copy → order assertion goes RED ───"
SWAPPED="$_HARNESS_TMP/fence-swapped.sh"
mutate "$FENCE" 's/_admin_remove_all\(.*stop-fallback$\)/_SWAP_TMP_\1/; s/; _admin_set_identity_unstaked /; _admin_remove_all /; s/_SWAP_TMP_/_admin_set_identity_unstaked/' "$SWAPPED"
new_mock
printf 'S1\nU1\n' > "$MOCK_DIR/identity.seq"
run_script "$SWAPPED"
t=$(trace)
if [[ "$t" != "$EXPECT_HAPPY" && "$t" == read-id,set-identity,remove-all* ]]; then
    ok "(10) swapped copy trace ($t) fails the exact-order assertion → case (1) observes the demote order"
else
    bad "(10) control vacuous: trace=$t"
fi

# ── (11) byte-safety ───────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (11) bash -n + shellcheck (if installed) on both scripts ───"
if "$BASH_BIN" -n "$FENCE" 2>/dev/null && { [[ ! -f "$PAGEONLY" ]] || "$BASH_BIN" -n "$PAGEONLY" 2>/dev/null; }; then
    ok "(11a) bash -n clean under $("$BASH_BIN" --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1) (run_all's parse gate covers the 3.2 leg)"
else
    bad "(11a) bash -n failed"
fi
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -S error "$FENCE" "$PAGEONLY" >/dev/null 2>&1; then
        ok "(11b) shellcheck -S error clean"
    else
        bad "(11b) shellcheck -S error found issues"
    fi
else
    ok "(11b) shellcheck not installed here — CI's shellcheck job covers it (skipped)"
fi

# ── (12) B1: STALE fenced-stopped (pre-boot mtime) → breaker ignored, fences normally ──────────
echo ""; echo "─── (12) B1: stale fenced-stopped from a PREVIOUS boot → ignored + stale page + refreshed marker ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
up_fixture 100                                      # boot epoch ≈ now − 100
printf '%s stale fixture\n' "2020-01-01T00:00:00Z" > "$MOCK_DIR/markers/fenced-stopped"
touch -t 202001010000 "$MOCK_DIR/markers/fenced-stopped"   # mtime 2020 ≪ boot epoch → STALE
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,set-identity,stop,restart-monitor" ]] && grep -q "stale fenced-stopped marker from a previous boot" "$MOCK_DIR/out"; then
    ok "(12a) stale marker ignored: the fence ran the full verdict (wedge → stop) + paged the stale notice"
else
    bad "(12a) rc=$RC trace=$t out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q "demote ladder failed" "$MOCK_DIR/markers/fenced-stopped"; then
    ok "(12b) the outcome write REFRESHED the stopped marker (stale fixture text superseded)"
else
    bad "(12b) marker: $(cat "$MOCK_DIR/markers/fenced-stopped" 2>/dev/null)"
fi
T12_TRACE="$t"; T12_RC="$RC"

# ── (13) B1: uptime unreadable → freshness undecidable → treated STALE ─────────────────────────
echo ""; echo "─── (13) B1: uptime unreadable → marker treated STALE (fence proceeds) ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
mkdir -p "$MOCK_DIR/proc_root"                      # NO uptime file → freshness undecidable
printf '%s refusal fixture\n' "2026-08-20T00:00:00Z" > "$MOCK_DIR/markers/fenced-stopped"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,set-identity,stop,restart-monitor" ]] && grep -q "stale fenced-stopped marker" "$MOCK_DIR/out"; then
    ok "(13) undecidable freshness → STALE: honoring an unprovable marker is the double-sign hole; proceeding is idempotent-harmless"
else
    bad "(13) rc=$RC trace=$t out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi

# ── (14) B1-note: set-identity FAILED + process gone → NOT a demote outcome → stop ─────────────
echo ""; echo "─── (14) set-identity rc 1 + proc gone → NO proc-gone excuse (ACCEPTED required) → stop ───"
new_mock
printf 'S1\nFAIL\n' > "$MOCK_DIR/identity.seq"
echo 1 > "$MOCK_DIR/rc.setid"
echo 0 > "$MOCK_DIR/proc.seq"                       # process gone at every pgrep (sticky)
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,set-identity,stop,restart-monitor" ]] && marker_ok fenced-stopped && [[ ! -f "$MOCK_DIR/markers/fenced-demoted" ]]; then
    ok "(14) FAILED set-identity earns no excuse: stop-fallback (stop also cancels Restart=always), fenced-stopped, never fenced-demoted"
else
    bad "(14) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi

# ── (15) B1-note: ACCEPTED set-identity + mid-ladder exit → demote outcome, HONEST reason ──────
echo ""; echo "─── (15) ACCEPTED set-identity, process exits mid-ladder → fenced-demoted with the DISTINCT truthful reason ───"
new_mock
printf 'S1\nFAIL\n' > "$MOCK_DIR/identity.seq"
echo 0 > "$MOCK_DIR/proc.seq"
run_script "$FENCE"
if [[ "$RC" == "0" ]] && grep -q "ACCEPTED set-identity" "$MOCK_DIR/markers/fenced-demoted" && ! grep -q "ladder verified" "$MOCK_DIR/markers/fenced-demoted"; then
    ok "(15) reason names the ACCEPTED set-identity + the unit-identity invariant this script cannot verify — no false 'verified'"
else
    bad "(15) rc=$RC marker: $(cat "$MOCK_DIR/markers/fenced-demoted" 2>/dev/null)"
fi

# ── (16) re-poll unreadable + process ALIVE → abort → stop (panel mutant X5's killer) ──────────
echo ""; echo "─── (16) re-poll unreadable with the process ALIVE → the window was NOT verified → stop ───"
new_mock
printf 'S1\nU1\nFAIL\n' > "$MOCK_DIR/identity.seq"   # poll2 unreadable; process stays alive
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,set-identity,remove-all,read-id,read-id,stop,restart-monitor" ]] && marker_ok fenced-stopped && [[ ! -f "$MOCK_DIR/markers/fenced-demoted" ]]; then
    ok "(16) unreadable re-poll + live process → abort to stop; fenced-demoted never claimed on an unverified window"
else
    bad "(16) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi

# ── (17) stop-UNCONFIRMED → LOUDEST page + exit 1 (panel mutant X2's killer) ───────────────────
echo ""; echo "─── (17) stop rc≠0 AND no process ever discoverable → 'may STILL BE VOTING' + exit 1 ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
echo 124 > "$MOCK_DIR/rc.stop"
echo 0 > "$MOCK_DIR/proc"                            # no validator process ever seen (comm-name miss class)
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
if [[ "$RC" == "1" ]] && grep -q "STILL BE VOTING" "$MOCK_DIR/out" && marker_ok fenced-stopped; then
    ok "(17) zero stop evidence → LOUDEST page + exit 1 + claim-more marker (never 'STOPPED+verified' on nothing)"
else
    bad "(17) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi

# ── (18) Restart=always resurrection → delayed re-verify (panel mutant X1's killer) ────────────
echo ""; echo "─── (18) proc.seq flips back ALIVE after the immediate verify → delayed re-verify escalates ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.setid"
# pgrep ledger: post-stop check (2 calls: gone,gone) + immediate verify (2: gone,gone) +
# delayed re-verify (1st call: ALIVE) — sticky thereafter.
printf '0\n0\n0\n0\n1\n' > "$MOCK_DIR/proc.seq"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
if [[ "$RC" == "1" ]] && grep -q "RESURRECTED" "$MOCK_DIR/out" && marker_ok fenced-stopped; then
    ok "(18) resurrection within the re-verify window caught → escalation (exit 1, claim-more marker, loudest page)"
else
    bad "(18) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
T18_RC="$RC"

# ── (19) remove-all failures (panel mutant X4's killer) ────────────────────────────────────────
echo ""; echo "─── (19) wedged FIRST remove-all → stop; wedged BARRIER remove-all NOT excused by proc-gone ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 124 > "$MOCK_DIR/rc.remove"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,stop,restart-monitor" ]] && marker_ok fenced-stopped; then
    ok "(19a) FIRST remove-all wedged (process alive) → straight to stop-fallback, no set-identity attempted"
else
    bad "(19a) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi
new_mock
printf 'S1\nFAIL\n' > "$MOCK_DIR/identity.seq"
printf '0\n124\n' > "$MOCK_DIR/rc.remove"            # first remove-all ok; BARRIER wedged
echo 0 > "$MOCK_DIR/proc.seq"                        # process gone post-set-identity (the dangerous combo)
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,set-identity,remove-all,stop,restart-monitor" ]] && marker_ok fenced-stopped && [[ ! -f "$MOCK_DIR/markers/fenced-demoted" ]]; then
    ok "(19b) WEDGED barrier remove-all is NOT excused by post-set-identity proc-gone → stop, never fenced-demoted"
else
    bad "(19b) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi

# ── (20) UNSTAKED_KEYPAIR guard (panel mutant X6's killer) ─────────────────────────────────────
echo ""; echo "─── (20) UNSTAKED_KEYPAIR missing → guard fires BEFORE the admin call → stop path ───"
new_mock
printf 'S1\nU1\n' > "$MOCK_DIR/identity.seq"         # bait: were set-identity attempted, re-polls would read unstaked
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service UNSTAKED_KEYPAIR="$MOCK_DIR/no-such-keypair.json"
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,stop,restart-monitor" ]] && marker_ok fenced-stopped && grep -q "unstaked keypair missing/empty" "$MOCK_DIR/out"; then
    ok "(20) missing keypair → no set-identity issued, stop path taken (guard observed, not vacuous)"
else
    bad "(20) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi

# ── (21) shipped-default repoll + floor clamp ──────────────────────────────────────────────────
echo ""; echo "─── (21) NO env override → 5 re-polls (the shipped default); FENCE_REPOLL_SECS=0 → floored to 1 ───"
new_mock
printf 'S1\nU1\n' > "$MOCK_DIR/identity.seq"
REPOLL_ENV=""
run_script "$FENCE"
unset REPOLL_ENV
t=$(trace)
EXPECT_HAPPY5="read-id,remove-all,set-identity,remove-all,read-id,read-id,read-id,read-id,read-id,restart-monitor"
if [[ "$RC" == "0" && "$t" == "$EXPECT_HAPPY5" ]] && grep -q "verified by 5 sustained unstaked reads" "$MOCK_DIR/markers/fenced-demoted"; then
    ok "(21a) shipped default exercised: 5 re-polls, marker reason counts them (a default regression cannot pass silently)"
else
    bad "(21a) rc=$RC trace=$t marker: $(cat "$MOCK_DIR/markers/fenced-demoted" 2>/dev/null)"
fi
T21_TRACE="$t"; T21_RC="$RC"
new_mock
printf 'S1\nU1\n' > "$MOCK_DIR/identity.seq"
REPOLL_ENV="FENCE_REPOLL_SECS=0"
run_script "$FENCE"
unset REPOLL_ENV
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,remove-all,set-identity,remove-all,read-id,restart-monitor" ]]; then
    ok "(21b) FENCE_REPOLL_SECS=0 floors to 1 — the sustained verify never disappears entirely"
else
    bad "(21b) rc=$RC trace=$t"
fi

# ── (22) B2: enqueue semantics of the monitor restart ──────────────────────────────────────────
echo ""; echo "─── (22) restart ENQUEUE failure → page; enqueue-ok + slow READY → NO false page ───"
new_mock
printf 'FAIL\n' > "$MOCK_DIR/identity.seq"
printf 'Validator startup: LoadingLedger (starting)\n' > "$MOCK_DIR/monitor.out"
echo 1 > "$MOCK_DIR/rc.restart"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
if [[ "$RC" == "0" ]] && grep -q "UNMONITORED; intervene" "$MOCK_DIR/out"; then
    ok "(22a) the enqueue itself failed → the UNMONITORED page fires (that failure is real, not a READY wait)"
else
    bad "(22a) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi
new_mock
printf 'FAIL\n' > "$MOCK_DIR/identity.seq"
printf 'Validator startup: LoadingLedger (starting)\n' > "$MOCK_DIR/monitor.out"
touch "$MOCK_DIR/restart.slowready"                  # READY minutes away: blocking restart would rc 124
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
if [[ "$RC" == "0" ]] && ! grep -q "UNMONITORED" "$MOCK_DIR/out" && grep -q "systemctl restart --no-block" "$EVENTS"; then
    ok "(22b) slow-READY monitor: --no-block enqueue rc 0 → NO false 'UNMONITORED; intervene' on a healthy replaying node (the B2 blocker)"
else
    bad "(22b) rc=$RC out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ') restart events: $(grep 'systemctl restart' "$EVENTS" 2>/dev/null)"
fi
T22_RC="$RC"

# ── (23) instance lock (reviewer, 5.1 GO fix): bounded wait; a STUCK holder never blocks the fence ──
#     -n gave the holder an UNBOUNDED veto: a wedged holder (bash in D-state, cgroup freeze — the
#     external calls are bounded, the process itself is not) meant NO fence, monitor left dead,
#     page journal-only. Now: flock -w FENCE_LOCK_WAIT (default 30 — every ladder rung is bounded,
#     a real twin finishes far inside it); expiry = a stuck holder, not concurrency → page +
#     restart-monitor + FENCE WITHOUT the lock + final exit forced to 1 (unit lands in `failed`,
#     visible in systemctl --failed). Clean concurrency resolves by WAITING: the twin releases,
#     we acquire, and the idempotent verdict paths handle the already-fenced state.
echo ""; echo "─── (23) lock: clean concurrency waits; a stuck holder is overridden loudly ───"
if command -v flock >/dev/null 2>&1; then
    # (23a) clean concurrency: holder releases after ~1s → fence WAITS, acquires, proceeds.
    new_mock
    printf 'S1\nU1\nU1\nU1\nU1\nU1\nU1\n' > "$MOCK_DIR/identity.seq"
    ( exec 8>"$MOCK_DIR/markers/.fence.lock"; flock -n 8; sleep 1; exec 8>&- ) &
    _holder=$!
    sleep 0.2
    run_script "$FENCE" VALIDATOR_UNIT=sol-test.service FENCE_LOCK_WAIT=10 FENCE_REPOLL_SECS=3
    wait "$_holder" 2>/dev/null
    t=$(trace)
    if [[ "$RC" == "0" && "$t" == *"remove-all"* && -e "$MOCK_DIR/markers/fenced-demoted" ]]; then
        ok "(23a) holder released → the fence WAITED, acquired, and ran the ladder (clean concurrency = waiting, not surrender)"
    else
        bad "(23a) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
    fi
    # (23b) STUCK holder: never releases within the wait → page + restart-monitor + lockless
    #       fence + exit 1 even though the demote SUCCEEDED (visibility over tidiness).
    new_mock
    printf 'S1\nU1\nU1\nU1\nU1\nU1\nU1\n' > "$MOCK_DIR/identity.seq"
    ( exec 8>"$MOCK_DIR/markers/.fence.lock"; flock -n 8; sleep 60 ) &
    _holder=$!
    sleep 0.2
    run_script "$FENCE" VALIDATOR_UNIT=sol-test.service FENCE_LOCK_WAIT=1 FENCE_REPOLL_SECS=3
    kill "$_holder" 2>/dev/null; wait "$_holder" 2>/dev/null
    t=$(trace)
    if [[ "$RC" == "1" && "$t" == *"remove-all"* && "$t" == *"restart-monitor"* && -e "$MOCK_DIR/markers/fenced-demoted" ]] && grep -q "STUCK" "$MOCK_DIR/out"; then
        ok "(23b) stuck holder: paged + monitor restarted + fenced WITHOUT the lock + exit 1 (unit visible in --failed) — the holder's veto is bounded"
    else
        bad "(23b) rc=$RC trace=$t out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
    fi
else
    ok "(23) flock not installed here (macOS harness) — skipped; the Linux CI leg runs it (every Linux deploy host has flock)"
fi

# ── (31) structural: the stopped-marker/breaker liveness COUPLING is named at the WRITE site ───
#     (reviewer, 5.1 GO): fenced-stopped may be written on an UNVERIFIED stop (claim-more) — safe
#     ONLY because the breaker verifies process-liveness before honoring the marker. The link
#     must be named where the marker is written, not only in the breaker, or a future "redundant
#     check" cleanup turns the marker into a shield for a RUNNING node.
echo ""; echo "─── (31) write-site comment names the liveness-check coupling ───"
if sed -n '/^_write_marker()/,/^}/p' "$FENCE" | grep -q "liveness" && sed -n '/^_write_marker()/,/^}/p' "$FENCE" | grep -qi "shield"; then
    ok "(31) _write_marker names the breaker-liveness coupling (removing the liveness check would turn claim-more into a shield for a running node)"
else
    bad "(31) the coupling is named only on the breaker side — _write_marker's comment must carry it too"
fi

# ── (24) marker precedence: claim-more binds SAME-BOOT stopped markers (stale → case 30) ──────
#     (re-panel availability note): a stale stopped marker gagging a fresh demote made the page
#     and the on-disk marker disagree — precedence now applies to same-boot markers only.
echo ""; echo "─── (24) demote outcome with a SAME-BOOT fenced-stopped → stronger claim kept, demoted NOT written ───"
new_mock
printf 'S1\nU1\nU1\nU1\nU1\nU1\nU1\n' > "$MOCK_DIR/identity.seq"
up_fixture 30000                                    # proc ALIVE (default) → the breaker stands aside (case 28) and the LADDER runs;
printf '%s same-boot fixture\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MOCK_DIR/markers/fenced-stopped"
run_script "$FENCE" FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
if [[ "$RC" == "0" && ! -f "$MOCK_DIR/markers/fenced-demoted" ]] && grep -q "keeping the stronger claim" "$MOCK_DIR/out" && grep -q "same-boot fixture" "$MOCK_DIR/markers/fenced-stopped"; then
    ok "(24) ladder succeeded but the SAME-BOOT stopped marker is sticky: demote write suppressed at the ONE write path (log pinned), stopped text intact"
else
    bad "(24) rc=$RC markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ') out: $(tail -2 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi

# ── (25) startup-evidence word anchor ──────────────────────────────────────────────────────────
echo ""; echo "─── (25) 'restarting' (READY-node noise) is NOT startup evidence → stop path ───"
new_mock
printf 'FAIL\n' > "$MOCK_DIR/identity.seq"
printf 'WARN: rpc thread pool restarting after panic\n' > "$MOCK_DIR/monitor.out"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service
t=$(trace)
if [[ "$RC" == "0" && "$t" == "read-id,is-active,probe,stop,restart-monitor" ]] && marker_ok fenced-stopped; then
    ok "(25) 'restarting' did not fake the third branch (word-anchored token) → fail toward stop held"
else
    bad "(25) rc=$RC trace=$t markers=$(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ')"
fi

# raw-data traces for the report
echo ""
echo "  trace (1):  rc=$T1_RC  $T1_TRACE"
echo "  trace (2):  rc=$T2_RC  $T2_TRACE"
echo "  trace (3):  rc=$T3_RC  $T3_TRACE"
echo "  trace (12): rc=$T12_RC  $T12_TRACE"
echo "  trace (18): rc=$T18_RC  (resurrection → exit 1)"
echo "  trace (21a): rc=$T21_RC  $T21_TRACE"
echo "  trace (22b): rc=$T22_RC  (slow-READY, no false page)"

# ── (28) DS-1 (re-panel): same-boot stopped marker + validator RUNNING → breaker must NOT hold ──
#     The same-boot proxy alone would export the breaker's double-sign safety to the unbuilt 5.2
#     HOLD invariant (in-boot recovery: operator unmask+start → staked node + same-boot marker →
#     old code refused with ZERO reads). Self-sufficiency: one proc check before refusing.
echo ""; echo "─── (28) same-boot fenced-stopped + process ALIVE → fence proceeds (no blind refusal) ───"
new_mock
printf 'S1\nS1\n' > "$MOCK_DIR/identity.seq"
echo 1 > "$MOCK_DIR/proc"
up_fixture 30000
printf '%s same-boot fixture\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MOCK_DIR/markers/fenced-stopped"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
t=$(trace)
if [[ "$t" == *"remove-all"* ]] && grep -q "process is RUNNING" "$MOCK_DIR/out"; then
    ok "(28) same-boot marker + live process → breaker stands aside, the ladder runs (self-sufficient, not coupled to 5.2 HOLD)"
else
    bad "(28) rc=$RC trace=$t out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi

# ── (29) breaker still holds when the node is genuinely down (same boot, proc GONE) ────────────
echo ""; echo "─── (29) same-boot fenced-stopped + process GONE → refuse-to-act-twice + monitor restart ───"
new_mock
printf 'S1\n' > "$MOCK_DIR/identity.seq"
echo 0 > "$MOCK_DIR/proc"
up_fixture 30000
printf '%s same-boot fixture\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MOCK_DIR/markers/fenced-stopped"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
t=$(trace)
if [[ "$RC" == "0" && "$t" == *"restart-monitor"* && "$t" != *"remove-all"* && "$t" != *",stop"* ]] && grep -q "refusing to act twice" "$MOCK_DIR/out"; then
    ok "(29) genuinely-stopped node: refusal + restart-monitor, zero ladder/stop actions"
else
    bad "(29) rc=$RC trace=$t out: $(tail -3 "$MOCK_DIR/out" 2>/dev/null | tr '\n' ' ')"
fi

# ── (30) STALE stopped marker must not gag a FRESH demote outcome (re-panel availability note) ──
#     Precedence claim-more applies to SAME-BOOT stopped markers; a STALE one is superseded —
#     otherwise the page says "demoted, monitor restarting into demoted monitoring" while the
#     on-disk marker still says stopped and the restarted monitor HOLDs a running-unstaked node.
echo ""; echo "─── (30) stale fenced-stopped + successful demote → fenced-demoted supersedes ───"
new_mock
printf 'S1\nU1\nU1\nU1\nU1\nU1\nU1\n' > "$MOCK_DIR/identity.seq"
echo 1 > "$MOCK_DIR/proc"
up_fixture 100
printf '%s stale fixture\n' "2020-01-01T00:00:00Z" > "$MOCK_DIR/markers/fenced-stopped"
touch -t 202001010000 "$MOCK_DIR/markers/fenced-stopped"
run_script "$FENCE" VALIDATOR_UNIT=sol-test.service FENCE_PROC_ROOT="$MOCK_DIR/proc_root" FENCE_REPOLL_SECS=3
if [[ "$RC" == "0" && -e "$MOCK_DIR/markers/fenced-demoted" && ! -e "$MOCK_DIR/markers/fenced-stopped" ]]; then
    ok "(30) fresh demote superseded the STALE stopped marker (marker and page now agree; same-boot stopped stays sticky per (24))"
else
    bad "(30) rc=$RC markers: $(ls "$MOCK_DIR/markers" 2>/dev/null | tr '\n' ' ') stopped: $(cat "$MOCK_DIR/markers/fenced-stopped" 2>/dev/null)"
fi


rm -rf "$STUB_DIR" "$MOCK_PARENT"

results_banner
