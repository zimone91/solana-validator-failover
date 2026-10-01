#!/bin/bash
# v0.6.9: full test-suite gate. Runs on bash 3.2 (macOS test box) AND bash 4+/5 (Linux deploy target).
# Two stages:
#   1. PARSE gate — `bash -n` on every suite AND tests/lib/*.sh and tests/strace-hermetic.sh (the harness
#      library and the CI strace job's script are outside the test_*.sh glob and would otherwise ship
#      unparsed on 3.2). A `case … )` inside a $( ) command substitution (etc.) parses on bash 4+ but
#      FAILS on bash 3.2; without this gate such a break silently skipped a whole suite there (v0.6.9
#      B3: test_collision_detector.sh, 34/35 as 35/35).
#   2. RUN gate — execute every suite; a non-zero exit fails the gate, and so does a suite still running at the
#      PER-SUITE TIME CAP (RUN_ALL_SUITE_CAP, below): it is killed and named, so a hang is a red in an hour, not a job
#      that runs to its timeout. Each suite runs behind the NET GUARD's failing,
#      logging network-client stand-ins, first in PATH; stage (4) fails the gate when any suite reached one of them
#      through PATH (named with its calls; the harness's own curl stand-in — the suites' RPC mock — logs only to its
#      suite's banner, never here). Network clients reached through PATH are caught by this stage (4) on every leg; at
#      the syscall level, tests/strace-hermetic.sh (CI's strace-hermetic job, ubuntu-24.04) fails on any inet socket
#      of the whole run. What stage (4) cannot see is listed at the stage (the LIMIT); the strace job sees any of those
#      that opens a socket.
#      The suites read no environment variable GitHub's runner sets (CI, GITHUB_*, RUNNER_*: CI's facts job checks it):
#      GitHub sets CI=true in every job, and a suite whose knob was named CI read `true` as 0 in its arithmetic.
# Also `bash -n` the eight shipped scripts (v0.7 Block 5.1 promotes the two fence scripts into
# this explicit list — shippable artifacts, installed only by the `failover arm` ceremony;
# install.sh joined at the Block-5.1 panel fix round — a pre-existing gap: it was in SHA256SUMS
# but in neither parse nor shellcheck list; Block 5.3 adds failover-arm.sh — the ceremony
# itself, shippable, EXECUTED only at the v0.7 rollout). Exit non-zero on any parse or run failure.
set +e
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2
PKG="$(cd .. && pwd)"

# 5.3 panel fix round: every dispatch below is "${BASH:-bash}" — the interpreter RUNNING this
# gate, never a PATH-resolved bare `bash` (the interpreter-drift class: a runner image whose
# PATH fronts a newer bash would silently parse/execute the suites on an interpreter the
# fingerprint never saw). The banner prints the SAME interpreter the gate dispatches.
echo "bash: $("${BASH:-bash}" --version | head -1)"
echo "═══ (1) PARSE gate: bash -n on scripts + harness lib + all suites ═══"
parse_fail=0
for s in "$PKG"/install.sh "$PKG"/solana-primary-failover.sh "$PKG"/solana-standby-failover.sh \
         "$PKG"/deploy-failover.sh "$PKG"/deploy-failover-standby.sh "$PKG"/failover-arm.sh \
         "$PKG"/systemd/failover-fence.sh "$PKG"/systemd/failover-fence-page-only.sh; do
    if "${BASH:-bash}" -n "$s" 2>/dev/null; then echo "  ok    $(basename "$s")"; else echo "  PARSE-FAIL $(basename "$s")"; parse_fail=$((parse_fail+1)); fi
done
for t in lib/*.sh strace-hermetic.sh test_*.sh; do
    if "${BASH:-bash}" -n "$t" 2>/dev/null; then :; else echo "  PARSE-FAIL $t"; parse_fail=$((parse_fail+1)); fi
done
[[ $parse_fail -eq 0 ]] && echo "  all suites parse-clean" || echo "  $parse_fail parse failure(s)"

echo ""
echo "═══ (2) RUN gate: execute every suite ═══"
# A vanished/misnamed suite must FAIL this gate, not silently shrink it (bump when adding a suite).
EXPECTED_SUITES=54
# The PER-SUITE TIME CAP (6.3.1 fix round 8 — the delta panel 7's CIP-1: GitHub's CI=true froze two suites' simulated
# clocks, and each would have held its job to the job's timeout, 6 h by default). Each suite runs in its own process group
# (set -m around the launch) under a watchdog: a suite still running RUN_ALL_SUITE_CAP seconds after it started is KILLED
# — its whole process group, SIGTERM and SIGKILL 5 s later — and FAILS this stage, named ("KILLED at the per-suite cap").
# The default, 3600 s, is 2.4x the slowest suite measured on the slowest leg (test_own_view: 1,502 s on one docker vCPU,
# bash 5.2) and 1.8x that suite under the strace job (the whole run under strace -f measured 1.3x the plain run); every
# leg prints each suite's wall time and its three slowest against the cap. Override for a slower machine:
# RUN_ALL_SUITE_CAP=<seconds>.
RUN_ALL_SUITE_CAP=${RUN_ALL_SUITE_CAP:-3600}
case "$RUN_ALL_SUITE_CAP" in ''|*[!0-9]*|0) echo "  RUN_ALL_SUITE_CAP must be a positive number of seconds (got '$RUN_ALL_SUITE_CAP')"; exit 2 ;; esac
run_pass=0; run_fail=0; failed=""
_suite_out=$(mktemp); _ra_times=$(mktemp); _ra_pid=""; _ra_wd=""
_ra_abort() {   # run_all itself interrupted: the running suite is in its own process group — stop it too
    [[ -n "$_ra_wd" ]] && kill "$_ra_wd" 2>/dev/null
    [[ -n "$_ra_pid" ]] && kill -TERM -- "-$_ra_pid" 2>/dev/null
    echo "  run_all interrupted ($1): the running suite's process group was stopped — NOT GREEN"
    exit 2
}
trap '_ra_abort INT' INT; trap '_ra_abort TERM' TERM; trap '_ra_abort HUP' HUP
# The NET GUARD's gate (6.3.1 fix round 6 — the delta panel 5's CLM5-3: a suite ran the host's ping 126–135 times a run
# while the texts said no suite reaches the network). Every suite runs with a directory of FAILING (rc 2), LOGGING
# stand-ins FIRST in PATH — curl and every client of tests/lib/harness.sh's HARNESS_NET_CLIENTS (one list, read from
# there) — made for that suite alone, its log's path written into each stand-in; HARNESS_NETGUARD_LOG names the same log
# for the harness, whose own client stand-ins (first in a suite that sources it) write there too — its curl stand-in does
# not: it answers rc 7 and is counted only in the suite's RESULTS banner (the suites' RPC mock, by design). So a child
# that keeps a guard directory on its PATH — `env -i PATH="$PATH" …` included — still logs, to its own suite's log. Each
# log is read right after its suite and AGAIN after the last suite (a child that outlived its suite and called later is
# named with that suite); the stand-ins are removed only after that final read. A suite whose log is not empty FAILS
# stage (4), named with its calls; a setup failure fails it with its own reason, named with the suite: no client list, a
# stand-in or a log not written, or — checked after each suite and again at the final read — a suite's log, its stand-in
# directory or one of its stand-ins GONE (a suite that deleted them; after that a client it ran went to the host's own).
# LIMIT, named — stage (4) does not see: bash's /dev/tcp and /dev/udp redirections; `command -p <client>` (the default
# PATH); a plain `env -i` child (the libc or bash default PATH — only `env -i PATH=…` keeps the guard); an absolute path;
# a PATH a suite builds without the guard; a call made after the final read; an interpreter's own socket; socat (left out
# on purpose — the notify socket is a UNIX socket); a client not on the list; a suite that TRUNCATES its own log or
# rewrites a stand-in (deliberate: the calls a stand-in logged were failed by it, nothing was sent, but this stage cannot
# name them). The strace job (tests/strace-hermetic.sh; CI's strace-hermetic job, ubuntu-24.04) sees each of these that
# opens a socket, whatever opened it; a real client reached past a rewritten stand-in is its REAL exec.
# Each stand-in directory is written to HARNESS_STUB_DIRS_LOG when that is set (the strace job sets it): the job counts a
# listed client's exec from a directory on that list as a stand-in's, from anywhere else outside the system directories
# as REAL.
_ra_net=$(mktemp -d)
_ra_clients=$(sed -n 's/^HARNESS_NET_CLIENTS="\(.*\)"$/\1/p' lib/harness.sh)
net_fail=0; netfailed=""; net_setup=""; _ra_tampered=""
[[ -n "$_ra_clients" ]] || net_setup="$net_setup [no HARNESS_NET_CLIENTS list readable in lib/harness.sh — the guard would hold curl alone]"
case "$_ra_net" in *"'"*|"") net_setup="$net_setup [the guard directory's path is empty or holds a quote: '$_ra_net']" ;; esac
_ra_guard() {   # _ra_guard <suite> — its stand-in directory, $_ra_net/<suite>.bin: every client failing, logging to <suite>'s log
    local _c _d="$_ra_net/$1.bin"
    mkdir -p "$_d" || return 1
    for _c in curl $_ra_clients; do
        cat > "$_d/$_c" <<EOS || return 1
#!/bin/sh
printf '%s\t%s\n' '$_c' "\$*" >> '$_ra_net/$1.log'
exit 2
EOS
        chmod +x "$_d/$_c" || return 1
    done
    [[ -z "${HARNESS_STUB_DIRS_LOG:-}" ]] || printf '%s\n' "$_d" >> "$HARNESS_STUB_DIRS_LOG" || return 1
}
_ra_gone() {    # _ra_gone <suite> — what of its guard is gone ("" when its log, its directory and every stand-in exist)
    local _c _g=""
    [[ -f "$_ra_net/$1.log" ]] || _g="$_g its guard log,"
    if [[ -d "$_ra_net/$1.bin" ]]; then
        for _c in curl $_ra_clients; do [[ -f "$_ra_net/$1.bin/$_c" && -x "$_ra_net/$1.bin/$_c" ]] || _g="$_g its stand-in $_c,"; done
    else _g="$_g its stand-in directory,"; fi
    printf '%s' "${_g%,}"
}
# Every diagnostic line carries the NAME of the suite that produced it (reviewer, 6.2 GO nit): an
# untagged "tail: …" line is unattached in a log of 51 suites — a grep by suite name misses it and
# reads as "the diagnostics did not fire" (the reviewer nearly reported exactly that). printf, not
# sed, so no suite name can ever act as a sed metacharacter.
_diag_tag() {   # $1 = label, $2 = suite name; stdin = the lines to tag
    local _dl
    while IFS= read -r _dl; do printf '      %s [%s]: %s\n' "$1" "$2" "$_dl"; done
}
for t in test_*.sh; do
    # Cross-check printed FAILs against the exit code: a suite that prints ❌ but exits 0 (a broken
    # tail, a stray exit 0) must count as FAILED, not pass silently.
    # v0.7 (4.3): the grep is BARE ❌ — the contract is "❌ is reserved for failures in suite
    # output"; a suite reporting non-failures must use a different marker (the v058 🐞 precedent).
    # Named so after the reviewer found the old "❌ FAIL" literal made v058 an exception-by-phrasing.
    _ra_log="$_ra_net/$t.log"
    { : > "$_ra_log" && _ra_guard "$t"; } || net_setup="$net_setup [$t: its stand-ins or its log could not be written]"
    _ra_s0=$SECONDS
    set -m   # the suite, and then its watchdog, each in its OWN process group: a kill reaches every process it started
    HARNESS_NETGUARD_LOG="$_ra_log" PATH="$_ra_net/$t.bin:$PATH" "${BASH:-bash}" "$t" > "$_suite_out" 2>&1 < /dev/null &
    _ra_pid=$!
    ( trap - INT TERM HUP
      while (( SECONDS - _ra_s0 < RUN_ALL_SUITE_CAP )); do kill -0 "$_ra_pid" 2>/dev/null || exit 0; sleep 1; done
      kill -0 "$_ra_pid" 2>/dev/null || exit 0
      : > "$_ra_net/$t.killed"; kill -TERM -- "-$_ra_pid" 2>/dev/null; sleep 5; kill -KILL -- "-$_ra_pid" 2>/dev/null ) &
    _ra_wd=$!
    set +m
    wait "$_ra_pid"; _suite_rc=$?
    kill -- "-$_ra_wd" 2>/dev/null; wait "$_ra_wd" 2>/dev/null; _ra_wd=""; _ra_pid=""
    printf '%s %s\n' "$(( SECONDS - _ra_s0 ))" "$t" >> "$_ra_times"
    if [[ -f "$_ra_net/$t.killed" ]]; then
        run_fail=$((run_fail+1)); failed="$failed $t(KILLED-at-the-${RUN_ALL_SUITE_CAP}s-cap)"
        echo "      KILLED at the per-suite cap: still running ${RUN_ALL_SUITE_CAP} s after it started (RUN_ALL_SUITE_CAP) — a hang, or a machine that needs a larger cap [$t]"
        grep "❌" "$_suite_out" 2>/dev/null | head -3 | _diag_tag "offending" "$t"
        tail -5 "$_suite_out" 2>/dev/null | _diag_tag "tail" "$t"
    elif [[ $_suite_rc -eq 0 ]]; then
        if grep -q "❌" "$_suite_out"; then
            run_fail=$((run_fail+1)); failed="$failed $t(printed-FAIL-but-exit-0)"
            # v0.7 (4.4, reviewer): print the offending line(s) — diagnosis, not just detection.
            # The daemons under test ALSO print ❌ (e.g. "❌ FALSE POSITIVE" on healthy detector
            # paths — the full site list: tests/HARNESS.md); if the lines below are captured
            # DAEMON output, the fix is to stub that suite's log/alert sinks — NEVER to suppress
            # the suite's own output.
            grep "❌" "$_suite_out" | head -3 | _diag_tag "offending" "$t"
        else
            run_pass=$((run_pass+1))
        fi
    else
        run_fail=$((run_fail+1)); failed="$failed $t"
        # v0.7 (Block 6.2, reviewer): SYMMETRIC diagnosis. The 4.4 fix printed the offending
        # lines only in the twin branch above (printed-FAIL-but-exit-0); a plain non-zero exit
        # recorded a bare NAME, and $_suite_out — ONE reusable temp file — was overwritten by the
        # next suite, so a one-off failure left nothing to analyse (the reviewer hit exactly that:
        # 1 run fail in 5 full runs, unreproducible, the suite unnameable from the log). Print the
        # rc, the ❌ lines if any, and the tail — a suite that dies mid-run (set -e, a syntax
        # error, a crash) prints no ❌ at all and its LAST lines carry the reason.
        echo "      exit rc=$_suite_rc [$t]"
        grep "❌" "$_suite_out" 2>/dev/null | head -3 | _diag_tag "offending" "$t"
        tail -5 "$_suite_out" 2>/dev/null | _diag_tag "tail" "$t"
    fi
    _ra_g=$(_ra_gone "$t")
    [[ -z "$_ra_g" ]] || { net_setup="$net_setup [$t:$_ra_g — gone after the suite (it deleted them; a client it ran after that went to the host's own)]"; _ra_tampered="${_ra_tampered:-} $t"; }
    _ra_n=$(grep -c . "$_ra_log" 2>/dev/null); echo "${_ra_n:-0}" > "$_ra_net/$t.seen"
    if [[ ${_ra_n:-0} -gt 0 ]]; then
        net_fail=$((net_fail+1)); netfailed="$netfailed $t"
        echo "      NET-GUARD [$t]: $_ra_n network-client call(s), each failed by the guard (none sent):"
        tr '\t' ' ' < "$_ra_log" | sort | uniq -c | sort -rn | head -5 | _diag_tag "net" "$t"
    fi
done
trap - INT TERM HUP
rm -f "$_suite_out"
echo "  suites: $run_pass passed, $run_fail failed"
echo "  slowest: $(sort -rn "$_ra_times" | head -3 | awk '{ printf "%s%s %d s", (NR > 1 ? ", " : ""), $2, $1 }') — the per-suite cap is ${RUN_ALL_SUITE_CAP} s"
echo "  per-suite wall seconds: $(sort -k2 "$_ra_times" | awk '{ printf "%s%s %d", (NR > 1 ? ", " : ""), $2, $1 }')"
rm -f "$_ra_times"
[[ -n "$failed" ]] && echo "  FAILED:$failed"
count_fail=0
if [[ $(( run_pass + run_fail )) -ne $EXPECTED_SUITES ]]; then
    echo "  SUITE COUNT MISMATCH: ran $(( run_pass + run_fail )), manifest says $EXPECTED_SUITES — a suite is missing or unregistered"
    count_fail=1
fi

echo ""
echo "═══ (3) sole-reader check: the freshness triple is read only via dump_freshness ═══"
# Map §3.4 (the 4.0 GO condition), mechanical since 4.3: dump_freshness() in tests/lib/harness.sh
# is the SOLE reader of _liveness_first_provider / _liveness_obs_since / _last_blind_end — suites
# read named fields via `field "$(dump_freshness)" <name>` (priming WRITES in fixtures stay).
# A $-dereference in a suite is a private parser of the triple = twin-drift inside the test bed
# (the S-1 blocker class). Runs on both interpreters and locally (CI facts is Linux-only).
solereader_fail=0
if grep -n -E '[$][{]?(_liveness_first_provider|_liveness_obs_since|_last_blind_end)' test_*.sh; then
    echo "  SOLE-READER VIOLATION (sites above): suites must not dereference the freshness triple —"
    echo "  dump_freshness (tests/lib/harness.sh) is its only reader: field \"\$(dump_freshness)\" <vantage|observed_since|blind_until>"
    solereader_fail=1
else
    echo "  clean: no suite dereferences the triple outside tests/lib/harness.sh"
fi

echo ""
echo "═══ (4) net-guard gate: no suite reached a network client through PATH ═══"
# the FINAL READ, after the last suite: every suite's log again — a call a child made after its suite's own check (it
# outlived the suite) is named with that suite; only then are the stand-ins removed
for t in test_*.sh; do
    if [[ " ${_ra_tampered:-} " != *" $t "* ]]; then
        _ra_g=$(_ra_gone "$t")
        [[ -z "$_ra_g" ]] || net_setup="$net_setup [$t:$_ra_g — gone at the final read (a child that outlived the suite deleted them)]"
    fi
    _ra_n=$(grep -c . "$_ra_net/$t.log" 2>/dev/null); _ra_s=$(cat "$_ra_net/$t.seen" 2>/dev/null)
    [[ ${_ra_n:-0} -gt ${_ra_s:-0} ]] || continue
    [[ " $netfailed " == *" $t "* ]] || { net_fail=$((net_fail+1)); netfailed="$netfailed $t"; }
    echo "      NET-GUARD [$t]: $(( _ra_n - ${_ra_s:-0} )) network-client call(s) logged after the suite's own check — a child that outlived it:"
    tail -n $(( _ra_n - ${_ra_s:-0} )) "$_ra_net/$t.log" | tr '\t' ' ' | sort | uniq -c | sort -rn | head -5 | _diag_tag "late" "$t"
done
rm -rf "$_ra_net"
net_setup_fail=0
if [[ -n "$net_setup" ]]; then
    net_setup_fail=1
    echo "  NET-GUARD SETUP FAILED:$net_setup — this stage cannot vouch for the run"
fi
if [[ $net_fail -eq 0 && $net_setup_fail -eq 0 ]]; then
    echo "  clean: every suite's guard log is empty — read after each suite and again after the last (curl + $(printf '%s' "$_ra_clients" | wc -w | tr -d ' ') clients failing and logged, first in PATH)"
elif [[ $net_fail -gt 0 ]]; then
    echo "  NET-GUARD VIOLATION:$netfailed — each reached a network client through PATH (the calls are listed under the suite above); stub it in the suite's world"
fi

echo ""
total=$(( parse_fail + run_fail + count_fail + solereader_fail + net_fail + net_setup_fail ))
if [[ $total -eq 0 ]]; then
    echo "═══ GREEN — $run_pass/$run_pass suites, parse-clean on $("${BASH:-bash}" --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1), no network client reached through PATH ═══"
    exit 0
else
    echo "═══ NOT GREEN — $parse_fail parse fail(s), $run_fail run fail(s), $solereader_fail sole-reader fail(s), $net_fail net-guard fail(s)$([[ $net_setup_fail -eq 0 ]] || echo ", net-guard setup FAILED") ═══"
    exit 1
fi
