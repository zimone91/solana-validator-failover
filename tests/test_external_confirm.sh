#!/bin/bash
# Test: confirm_delinquency_external — three-valued contract (v0.6.1 F2)
#
#   0 = confirmed delinquent
#   1 = externals responded NOT delinquent (real false positive)
#   2 = could not confirm (any unreachable/invalid)  [NEW in v0.6.1; was folded into 1]
#
# v0.6.1: this test now SOURCES the real function from the shipped script (truncated
# before the MAIN LOOP) instead of carrying an embedded copy. The old copy-based test is
# exactly why F1/F2 passed CI while the shipped code was broken.

# harness: tests/lib/harness.sh — counters+banners, paths. run_test's own PASS-format echoes stay
# (they carry the expected/got detail); the printing log/alert shadows and the cut stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# Source functions only — everything up to the MAIN LOOP banner (no startup_checks, no loop).
SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
rm -f "$SRC"

# Make logging visible and keep alerts offline (no Telegram/webhook).
log_info()   { echo "      [INFO] $*"; }
log_warn()   { echo "      [WARN] $*"; }
alert_info() { echo "      [ALERT] $*"; }
alert_warn() { echo "      [ALERT] $*"; }   # v0.6.4: TIER2/emergency warnings route via alert_warn

# Mocks for the external tier checks (the unit under test calls these).
tier2_check_delinquency()  { return 2; }   # unreachable
tier3_confirm_delinquency() { return 2; }  # unreachable

TIER2_RPC="http://t2"
ALERT_THROTTLE=600
_last_t2_alert=0

run_test() {
    local desc="$1" expected="$2"
    echo ""
    echo "─── $desc ───"
    confirm_delinquency_external
    local actual=$?
    if [[ $actual -eq $expected ]]; then
        echo "  ✅ PASS (expected=$expected, got=$actual)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

title_banner "Test: confirm_delinquency_external (v0.6.1)"

# v0.6.1: both external RPCs down → "could not confirm" → 2 (HOLD), NOT 1 (false positive).
unset ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN
run_test "1. Default (unset) → CANNOT CONFIRM (hold) when T2+T3 down" 2

ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN=false
run_test "2. Explicit false → CANNOT CONFIRM (hold) when T2+T3 down" 2

# v0.6.5 (F3): the flag is DEPRECATED and IGNORED — it could never force a takeover (the
# authoritative vote-liveness fence also needs T2/T3), so both-externals-down always HOLDs (2).
ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN=true
run_test "3. Deprecated flag=true is IGNORED → still HOLD (2) when T2+T3 down (F3)" 2

# T2 confirms delinquent
ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN=false
tier2_check_delinquency() { return 0; }
run_test "4. T2 confirms delinquent (regardless of flag) → ALLOW" 0

# T2 denies (real false positive)
tier2_check_delinquency() { return 1; }
run_test "5. T2 denies (false positive) → reset (1) regardless of flag" 1

# T2 unreachable, T3 confirms
tier2_check_delinquency() { return 2; }
tier3_confirm_delinquency() { return 0; }
run_test "6. T2 down + T3 confirms → ALLOW" 0

# T2 unreachable, T3 denies
tier3_confirm_delinquency() { return 1; }
run_test "7. T2 down + T3 denies (false positive) → reset (1)" 1

results_banner
