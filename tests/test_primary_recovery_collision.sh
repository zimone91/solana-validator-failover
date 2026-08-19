#!/bin/bash
# F3 parity for the PRIMARY rpc-recovery path (v0.6.2). When RECOVERY_MODE=rpc, PRIMARY
# re-takes the staked identity only if check_standby_has_identity / _check_single_rpc decides
# "nobody else has it". The old IP-only `cut -d: -f1` would mistake a STANDBY sharing our
# public egress IP on a different port for our own stale entry -> "nobody else" -> PRIMARY
# re-takes while STANDBY still holds/votes -> double-sign. v0.6.2 compares full ip:port, so
# recovery must ABORT for the shared-IP/different-port case. Mirrors test_gossip_ip_collision.
# Sources the real PRIMARY functions.
#
# _check_single_rpc return contract: 0 = another node has it (ABORT recovery); 1 = nobody else.

# harness: tests/lib/harness.sh — ok/bad+banners, paths. Cut + printing log shadows + curl mock stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
rm -f "$SRC"

STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
TIER2_RPC="http://mock-t2"
TIER3_RPC="http://mock-t3"
LOCAL_RPC="http://mock-local"

log_info()  { echo "      [INFO] $*"; }
log_warn()  { echo "      [WARN] $*"; }

# Vote account: the shared staked identity is the nodePubkey for VOTE_PUBKEY.
VOTE_ACCTS="{\"jsonrpc\":\"2.0\",\"result\":{\"current\":[{\"votePubkey\":\"$VOTE_PUBKEY\",\"nodePubkey\":\"$STAKED_PUBKEY\",\"lastVote\":100}],\"delinquent\":[]},\"id\":1}"
# External cluster view: a holder advertises the staked identity at 10.0.0.5:8001.
EXT_CLUSTER="{\"jsonrpc\":\"2.0\",\"result\":[{\"pubkey\":\"$STAKED_PUBKEY\",\"gossip\":\"10.0.0.5:8001\"}],\"id\":1}"
# Our (PRIMARY) local view of our own UNSTAKED endpoint — same IP, different port.
LOCAL_CLUSTER="{\"jsonrpc\":\"2.0\",\"result\":[{\"pubkey\":\"$UNSTAKED_PUBKEY\",\"gossip\":\"10.0.0.5:8101\"}],\"id\":1}"

# Mock curl: dispatch on the JSON-RPC method in the -d payload, and (for getClusterNodes) on URL.
curl() {
    local data="" url=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) data="$2"; shift 2; continue ;;
            http*) url="$1" ;;
        esac
        shift
    done
    case "$data" in
        *getVoteAccounts*) printf '%s' "$VOTE_ACCTS"; return 0 ;;
        *getClusterNodes*)
            if [[ "$url" == "$LOCAL_RPC" ]]; then printf '%s' "$LOCAL_CLUSTER"; else printf '%s' "$EXT_CLUSTER"; fi
            return 0 ;;
    esac
    return 7
}

title_banner "F3 parity: PRIMARY rpc-recovery collision"

echo ""; echo "─── shared IP / different port → recovery must ABORT ───"
_check_single_rpc "$TIER2_RPC"; rc=$?
[[ $rc -eq 0 ]] && ok "_check_single_rpc → another node has it, ABORT recovery (rc=0)" \
               || bad "recovery would proceed despite a holder on a shared IP — double-sign (rc=$rc)"

# Wrapper: check_standby_has_identity must report "STANDBY has identity" (return 0 = abort).
check_standby_has_identity; rc=$?
[[ $rc -eq 0 ]] && ok "check_standby_has_identity → aborts recovery (rc=0)" \
               || bad "check_standby_has_identity allowed recovery (rc=$rc)"

# Demonstrate the old IP-only heuristic WOULD have allowed recovery (the bug).
ip_only_verdict() {
    local s o
    s=$(printf '%s' "$EXT_CLUSTER"   | jq -r --arg p "$STAKED_PUBKEY"   '.result[]?|select(.pubkey==$p)|.gossip//empty'|cut -d: -f1)
    o=$(printf '%s' "$LOCAL_CLUSTER" | jq -r --arg p "$UNSTAKED_PUBKEY" '.result[]?|select(.pubkey==$p)|.gossip//empty'|cut -d: -f1)
    [[ "$s" == "$o" ]] && echo "RECOVER" || echo "ABORT"
}
echo ""
[[ "$(ip_only_verdict)" == "RECOVER" ]] && ok "(context) old IP-only heuristic WOULD have recovered — fix is meaningful" \
                                        || bad "expected old IP-only heuristic to recover (test setup wrong)"

echo ""; echo "─── genuine self endpoint (stale ours, exact ip:port) → nobody else, recovery OK ───"
LOCAL_CLUSTER="{\"jsonrpc\":\"2.0\",\"result\":[{\"pubkey\":\"$UNSTAKED_PUBKEY\",\"gossip\":\"10.0.0.5:8001\"}],\"id\":1}"  # our endpoint == staked endpoint
_check_single_rpc "$TIER2_RPC"; rc=$?
[[ $rc -eq 1 ]] && ok "staked == our own exact endpoint → nobody else has it (rc=1)" \
               || bad "genuine self endpoint wrongly aborted recovery (rc=$rc)"

results_banner
