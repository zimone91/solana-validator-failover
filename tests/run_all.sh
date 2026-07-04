#!/bin/bash
# v0.6.9: full test-suite gate. Runs on bash 3.2 (macOS test box) AND bash 4+/5 (Linux deploy target).
# Two stages:
#   1. PARSE gate — `bash -n` on every suite. A `case … )` inside a $( ) command substitution (etc.)
#      parses on bash 4+ but FAILS on bash 3.2; without this gate such a break silently skipped a whole
#      suite there (v0.6.9 B3 was exactly that: test_collision_detector.sh, 34/35 masquerading as 35/35).
#   2. RUN gate — execute every suite; a non-zero exit fails the gate.
# Also `bash -n` the four shipped scripts. Exit non-zero on any parse or run failure.
set +e
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2
PKG="$(cd .. && pwd)"

echo "bash: $(bash --version | head -1)"
echo "═══ (1) PARSE gate: bash -n on scripts + all suites ═══"
parse_fail=0
for s in "$PKG"/solana-primary-failover.sh "$PKG"/solana-standby-failover.sh \
         "$PKG"/deploy-failover.sh "$PKG"/deploy-failover-standby.sh; do
    if bash -n "$s" 2>/dev/null; then echo "  ok    $(basename "$s")"; else echo "  PARSE-FAIL $(basename "$s")"; parse_fail=$((parse_fail+1)); fi
done
for t in test_*.sh; do
    if bash -n "$t" 2>/dev/null; then :; else echo "  PARSE-FAIL $t"; parse_fail=$((parse_fail+1)); fi
done
[[ $parse_fail -eq 0 ]] && echo "  all suites parse-clean" || echo "  $parse_fail parse failure(s)"

echo ""
echo "═══ (2) RUN gate: execute every suite ═══"
run_pass=0; run_fail=0; failed=""
for t in test_*.sh; do
    if bash "$t" >/dev/null 2>&1; then run_pass=$((run_pass+1)); else run_fail=$((run_fail+1)); failed="$failed $t"; fi
done
echo "  suites: $run_pass passed, $run_fail failed"
[[ -n "$failed" ]] && echo "  FAILED:$failed"

echo ""
total=$(( parse_fail + run_fail ))
if [[ $total -eq 0 ]]; then
    echo "═══ GREEN — $run_pass/$run_pass suites, parse-clean on $(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1) ═══"
    exit 0
else
    echo "═══ NOT GREEN — $parse_fail parse fail(s), $run_fail run fail(s) ═══"
    exit 1
fi
