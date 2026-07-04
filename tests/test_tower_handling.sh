#!/bin/bash
# Static regression test for v0.6.0 tower handling.
# Asserts on the REAL scripts (no mock curl) — locks in the --require-tower removal.
#   - staked set-identity must NOT use --require-tower (it would break takeover/recovery here)
#   - staked set-identity must use the path-as-argument form
#   - PRIMARY must still DELETE the staked tower on switch-to-unstaked
#   - both scripts must pass `bash -n`
set +e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
STANDBY="$DIR/solana-standby-failover.sh"

PASS=0; FAIL=0

assert_absent() {   # desc, ERE pattern, file
    if grep -Eq "$2" "$3"; then echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1));
    else echo "  ✅ PASS: $1"; PASS=$((PASS+1)); fi
}
assert_present() {  # desc, fixed string, file
    if grep -Fq "$2" "$3"; then echo "  ✅ PASS: $1"; PASS=$((PASS+1));
    else echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); fi
}

echo "============================================="
echo "  Tower-handling static tests (v0.6.0)"
echo "============================================="

[[ -f "$PRIMARY" ]] || { echo "  ❌ FAIL: primary script not found at $PRIMARY"; exit 1; }
[[ -f "$STANDBY" ]] || { echo "  ❌ FAIL: standby script not found at $STANDBY"; exit 1; }

echo ""
echo "─── 1. No '--require-tower' on the set-identity command ───"
# Match only the actual command line (has agave-validator); our explanatory comments
# mention --require-tower but never on a line that also runs agave-validator.
assert_absent "PRIMARY: set-identity has no --require-tower" 'agave-validator.*set-identity --require-tower' "$PRIMARY"
assert_absent "STANDBY: set-identity has no --require-tower" 'agave-validator.*set-identity --require-tower' "$STANDBY"

echo ""
echo "─── 2. Staked set-identity uses path-as-argument ───"
assert_present 'PRIMARY: set-identity "$STAKED_KEYPAIR"' 'set-identity "$STAKED_KEYPAIR"' "$PRIMARY"
assert_present 'STANDBY: set-identity "$STAKED_KEYPAIR"' 'set-identity "$STAKED_KEYPAIR"' "$STANDBY"

echo ""
echo "─── 3. PRIMARY still deletes the staked tower on switch-to-unstaked ───"
assert_present 'PRIMARY: rm -f "$tower_file"' 'rm -f "$tower_file"' "$PRIMARY"
assert_present 'PRIMARY: tower file name tower-1_9-<pubkey>.bin' 'tower-1_9-${STAKED_PUBKEY}.bin' "$PRIMARY"

echo ""
echo "─── 4. Scripts pass bash -n ───"
if bash -n "$PRIMARY" 2>/dev/null; then echo "  ✅ PASS: PRIMARY syntax"; PASS=$((PASS+1)); else echo "  ❌ FAIL: PRIMARY syntax"; FAIL=$((FAIL+1)); fi
if bash -n "$STANDBY" 2>/dev/null; then echo "  ✅ PASS: STANDBY syntax"; PASS=$((PASS+1)); else echo "  ❌ FAIL: STANDBY syntax"; FAIL=$((FAIL+1)); fi

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
