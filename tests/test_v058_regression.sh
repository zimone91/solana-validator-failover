#!/bin/bash
# Regression test: показывает что v0.5.8 действительно содержал split-brain баг
# Эта функция — копия из v0.5.8 (DO NOT USE!).

set +e

STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
GOSSIP_VERIFY=true
TIER2_RPC="http://mock-tier2:9999"
TIER3_RPC="http://mock-tier3:9999"

PASS=0; FAIL=0

MOCKDIR=$(mktemp -d /tmp/gossip-old-XXXXXX)
trap "rm -rf $MOCKDIR" EXIT

log_info()  { echo "      [INFO] $*"; }
log_warn()  { echo "      [WARN] $*"; }

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

set_mock() {
    local key
    key=$(echo -n "$1" | md5sum | cut -d' ' -f1)
    echo "$2" > "$MOCKDIR/$key"
}
clear_mocks() { rm -f "$MOCKDIR"/*; }

# ============================================================================
# OLD v0.5.8 FUNCTION (BUGGY!) - copy as-is from original solana-standby-failover.sh
# ============================================================================
check_primary_dropped_identity_OLD() {
    [[ "$GOSSIP_VERIFY" != "true" ]] && { log_info "Gossip verify disabled"; return 1; }

    for rpc in "$TIER2_RPC" "$TIER3_RPC"; do
        local cluster_info
        cluster_info=$(curl -s -m 15 "$rpc" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getClusterNodes"}' 2>/dev/null) || continue

        local staked_gossip_ip
        staked_gossip_ip=$(echo "$cluster_info" | jq -r \
            --arg pubkey "$STAKED_PUBKEY" \
            '.result[]? | select(.pubkey == $pubkey) | .gossip // empty' 2>/dev/null | cut -d: -f1)

        if [[ -z "$staked_gossip_ip" ]]; then
            log_info "[gossip via $rpc] Staked identity NOT in gossip — PRIMARY dropped it"
            continue
        fi

        local our_gossip_ip
        our_gossip_ip=$(echo "$cluster_info" | jq -r \
            --arg pubkey "$UNSTAKED_PUBKEY" \
            '.result[]? | select(.pubkey == $pubkey) | .gossip // empty' 2>/dev/null | cut -d: -f1)

        if [[ -n "$our_gossip_ip" && "$staked_gossip_ip" == "$our_gossip_ip" ]]; then
            log_info "[gossip] Staked gossip = our IP — we had it already"
            return 1
        fi

        log_warn "[gossip] Staked still on $staked_gossip_ip (PRIMARY active) — DON'T take"
        return 0   # ← THE BUG: returns 0 (success) when PRIMARY is active!
    done

    log_info "[gossip] No RPC showed PRIMARY active — safe to take"
    return 1   # ← also wrong — returns 1 (block) when actually safe
}

# Caller uses: check_primary_dropped_identity_OLD && gossip_clear=true
# Bash: && triggers when return 0 → success.
# So: PRIMARY active → return 0 → gossip_clear=true → TAKEOVER → SPLIT-BRAIN!

ACTIVE='{"jsonrpc":"2.0","result":[{"pubkey":"StakedPubkey111111111111111111111111111111","gossip":"10.0.0.1:8001"},{"pubkey":"UnstakedPubkey1111111111111111111111111111","gossip":"10.0.0.2:8001"}],"id":1}'
DROPPED='{"jsonrpc":"2.0","result":[{"pubkey":"UnstakedPubkey1111111111111111111111111111","gossip":"10.0.0.2:8001"}],"id":1}'

echo "==============================================="
echo "  REGRESSION TEST: v0.5.8 buggy function"
echo "  (demonstrates split-brain risk)"
echo "==============================================="

check_caller_simulation() {
    local desc="$1" expected_outcome="$2"
    echo ""
    echo "─── $desc ───"
    local gossip_clear=false
    check_primary_dropped_identity_OLD && gossip_clear=true
    local rc=$?
    echo "  function returned: $rc"
    echo "  gossip_clear:      $gossip_clear"
    if [[ "$gossip_clear" == "true" ]]; then
        echo "  → caller behavior: TAKEOVER ALLOWED"
        if [[ "$expected_outcome" == "takeover-allowed-but-WRONG" ]]; then
            echo "  ❌ BUG CONFIRMED: takeover allowed when PRIMARY still has identity!"
            FAIL=$((FAIL + 1))
        else
            PASS=$((PASS + 1))
        fi
    else
        echo "  → caller behavior: TAKEOVER BLOCKED"
        if [[ "$expected_outcome" == "takeover-blocked-but-WRONG" ]]; then
            echo "  ❌ BUG CONFIRMED: takeover blocked when PRIMARY actually dropped!"
            FAIL=$((FAIL + 1))
        else
            PASS=$((PASS + 1))
        fi
    fi
}

clear_mocks; set_mock "$TIER2_RPC" "$ACTIVE"; set_mock "$TIER3_RPC" "$ACTIVE"
check_caller_simulation \
    "BUG #1: PRIMARY active → caller would TAKEOVER (split-brain!)" \
    "takeover-allowed-but-WRONG"

clear_mocks; set_mock "$TIER2_RPC" "$DROPPED"; set_mock "$TIER3_RPC" "$DROPPED"
check_caller_simulation \
    "BUG #2: PRIMARY actually dropped → caller would BLOCK (failover broken!)" \
    "takeover-blocked-but-WRONG"

echo ""
echo "==============================================="
echo "  v0.5.8 confirmed buggy: $FAIL bugs reproduced"
echo "==============================================="
[[ $FAIL -ge 2 ]] && {
    echo ""
    echo "  ✅ This proves the audit was correct."
    echo "  ✅ v0.5.9 fix addresses both bugs (see test_gossip_semantics.sh)."
    exit 0
}
exit 1
