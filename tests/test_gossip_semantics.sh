#!/bin/bash
# Unit test: check_primary_dropped_identity() — v0.6.2 contract.
#   return 0 = gossip clear (safe to consider)   return 1 = BLOCK
#
# v0.6.2: SOURCES the real function from the shipped script (no embedded copy) so it
# tracks the C3/F3 rework: full ip:port comparison, and only a GENUINE self endpoint
# match is "us". Keeps the v0.5.9 invariant "a present (non-self) holder → BLOCK".

# harness: tests/lib/harness.sh — counters+banners, paths. run_test's own PASS-format echoes, the
# md5-keyed curl dispatcher, printing log shadows and the cut stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# Source functions only (up to the MAIN LOOP banner — no startup_checks, no loop).
SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
rm -f "$SRC"

# Fixtures — set AFTER sourcing (the script resets these at load time).
STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
GOSSIP_VERIFY=true
TIER2_RPC="http://mock-tier2:9999"
TIER3_RPC="http://mock-tier3:9999"

# Visible logging.
log_info()  { echo "      [INFO] $*"; }
log_warn()  { echo "      [WARN] $*"; }

# curl mock keyed by URL.
MOCKDIR=$(mktemp -d /tmp/gossip-test-XXXXXX)
trap "rm -rf $MOCKDIR" EXIT
curl() {
    local url=""
    for arg in "$@"; do
        case "$arg" in http*) url="$arg"; break ;; esac
    done
    local key
    key=$(echo -n "$url" | md5sum | cut -d' ' -f1)
    [[ -f "$MOCKDIR/$key" ]] && { cat "$MOCKDIR/$key"; return 0; }
    return 7
}
export -f curl
export MOCKDIR
set_mock()  { local key; key=$(echo -n "$1" | md5sum | cut -d' ' -f1); echo "$2" > "$MOCKDIR/$key"; }
clear_mocks() { rm -f "$MOCKDIR"/*; }

run_test() {
    local desc="$1" expected="$2"
    echo ""
    echo "─── TEST: $desc ───"
    check_primary_dropped_identity
    local actual=$?
    if [[ $actual -eq $expected ]]; then
        echo "  ✅ PASS (expected=$expected, got=$actual)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

# PRIMARY live on a DIFFERENT endpoint than ours.
ACTIVE='{"jsonrpc":"2.0","result":[{"pubkey":"StakedPubkey111111111111111111111111111111","gossip":"10.0.0.1:8001"},{"pubkey":"UnstakedPubkey1111111111111111111111111111","gossip":"10.0.0.2:8001"}],"id":1}'
# Staked dropped from gossip; only our unstaked + an unrelated node remain.
DROPPED='{"jsonrpc":"2.0","result":[{"pubkey":"UnstakedPubkey1111111111111111111111111111","gossip":"10.0.0.2:8001"},{"pubkey":"OtherValidator1111111111111111111111111111","gossip":"10.0.0.99:8001"}],"id":1}'
# Staked endpoint == our OWN full endpoint → stale self entry (we held it before).
STALE='{"jsonrpc":"2.0","result":[{"pubkey":"StakedPubkey111111111111111111111111111111","gossip":"10.0.0.2:8001"},{"pubkey":"UnstakedPubkey1111111111111111111111111111","gossip":"10.0.0.2:8001"}],"id":1}'
INVALID='{"jsonrpc":"2.0","error":{"code":-32600,"message":"x"},"id":1}'

title_banner "Gossip semantics unit tests (v0.6.2)"

clear_mocks; set_mock "$TIER2_RPC" "$ACTIVE"; set_mock "$TIER3_RPC" "$ACTIVE"
run_test "1. PRIMARY active (non-self endpoint) on T2+T3 → BLOCK" 1

clear_mocks; set_mock "$TIER2_RPC" "$DROPPED"; set_mock "$TIER3_RPC" "$DROPPED"
run_test "2. Staked dropped from T2+T3 → ALLOW" 0

clear_mocks; set_mock "$TIER2_RPC" "$STALE"; set_mock "$TIER3_RPC" "$STALE"
run_test "3. Staked == our OWN endpoint (genuine self/stale) → ALLOW" 0

clear_mocks
run_test "4. Both unreachable → fail-safe BLOCK" 1

clear_mocks; set_mock "$TIER2_RPC" "$INVALID"; set_mock "$TIER3_RPC" "$INVALID"
run_test "5. Invalid JSON → BLOCK" 1

clear_mocks; set_mock "$TIER3_RPC" "$DROPPED"
run_test "6. T2 down, T3 confirms dropped → ALLOW" 0

clear_mocks; set_mock "$TIER3_RPC" "$ACTIVE"
run_test "7. T2 down, T3 shows active holder → BLOCK" 1

clear_mocks; GOSSIP_VERIFY=false
run_test "8. GOSSIP_VERIFY=false → ALLOW (gossip skipped)" 0
GOSSIP_VERIFY=true

clear_mocks; set_mock "$TIER2_RPC" "$ACTIVE"; set_mock "$TIER3_RPC" "$DROPPED"
run_test "9. T2 active / T3 dropped (conservative) → BLOCK" 1

clear_mocks; set_mock "$TIER2_RPC" "$DROPPED"; set_mock "$TIER3_RPC" "$ACTIVE"
run_test "10. T2 dropped / T3 active (conservative) → BLOCK" 1

results_banner
