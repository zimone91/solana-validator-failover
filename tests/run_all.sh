#!/bin/bash
# v0.6.9: full test-suite gate. Runs on bash 3.2 (macOS test box) AND bash 4+/5 (Linux deploy target).
# Two stages:
#   1. PARSE gate — `bash -n` on every suite AND tests/lib/*.sh (the harness library is outside the
#      test_*.sh glob and would otherwise ship unparsed on 3.2). A `case … )` inside a $( ) command
#      substitution (etc.) parses on bash 4+ but FAILS on bash 3.2; without this gate such a break
#      silently skipped a whole suite there (v0.6.9 B3: test_collision_detector.sh, 34/35 as 35/35).
#   2. RUN gate — execute every suite; a non-zero exit fails the gate.
# Also `bash -n` the four shipped scripts. Exit non-zero on any parse or run failure.
set +e
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2
PKG="$(cd .. && pwd)"

echo "bash: $(bash --version | head -1)"
echo "═══ (1) PARSE gate: bash -n on scripts + harness lib + all suites ═══"
parse_fail=0
for s in "$PKG"/solana-primary-failover.sh "$PKG"/solana-standby-failover.sh \
         "$PKG"/deploy-failover.sh "$PKG"/deploy-failover-standby.sh; do
    if bash -n "$s" 2>/dev/null; then echo "  ok    $(basename "$s")"; else echo "  PARSE-FAIL $(basename "$s")"; parse_fail=$((parse_fail+1)); fi
done
for t in lib/*.sh test_*.sh; do
    if bash -n "$t" 2>/dev/null; then :; else echo "  PARSE-FAIL $t"; parse_fail=$((parse_fail+1)); fi
done
[[ $parse_fail -eq 0 ]] && echo "  all suites parse-clean" || echo "  $parse_fail parse failure(s)"

echo ""
echo "═══ (2) RUN gate: execute every suite ═══"
# A vanished/misnamed suite must FAIL this gate, not silently shrink it (bump when adding a suite).
EXPECTED_SUITES=44
run_pass=0; run_fail=0; failed=""
_suite_out=$(mktemp)
for t in test_*.sh; do
    # Cross-check printed FAILs against the exit code: a suite that prints ❌ but exits 0 (a broken
    # tail, a stray exit 0) must count as FAILED, not pass silently.
    # v0.7 (4.3): the grep is BARE ❌ — the contract is "❌ is reserved for failures in suite
    # output"; a suite reporting non-failures must use a different marker (the v058 🐞 precedent).
    # Named so after the reviewer found the old "❌ FAIL" literal made v058 an exception-by-phrasing.
    if bash "$t" > "$_suite_out" 2>&1; then
        if grep -q "❌" "$_suite_out"; then
            run_fail=$((run_fail+1)); failed="$failed $t(printed-FAIL-but-exit-0)"
        else
            run_pass=$((run_pass+1))
        fi
    else
        run_fail=$((run_fail+1)); failed="$failed $t"
    fi
done
rm -f "$_suite_out"
echo "  suites: $run_pass passed, $run_fail failed"
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
total=$(( parse_fail + run_fail + count_fail + solereader_fail ))
if [[ $total -eq 0 ]]; then
    echo "═══ GREEN — $run_pass/$run_pass suites, parse-clean on $(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1) ═══"
    exit 0
else
    echo "═══ NOT GREEN — $parse_fail parse fail(s), $run_fail run fail(s), $solereader_fail sole-reader fail(s) ═══"
    exit 1
fi
