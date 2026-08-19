#!/bin/bash
# F3 regression: a *different* node that shares our public egress IP on a different port
# must NOT be mistaken for our own stale entry. Classic case: PRIMARY live on IP:8001,
# STANDBY (us) on IP:8101 behind the same NAT/egress IP.
#
# v0.6.1 compared only the IP (cut -d: -f1): IP==IP → "stale/safe" → fence bypass →
# DOUBLE-SIGN. v0.6.2 (C3) compares the full ip:port → different endpoint → BLOCK.
# Sources the real check_primary_dropped_identity so it tests shipped code.

# harness: tests/lib/harness.sh — ok/bad+banners, paths. The md5-keyed curl dispatcher + printing
# log shadows + cut stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
rm -f "$SRC"

STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
GOSSIP_VERIFY=true
TIER2_RPC="http://mock-tier2:9999"
TIER3_RPC="http://mock-tier3:9999"

log_info()  { echo "      [INFO] $*"; }
log_warn()  { echo "      [WARN] $*"; }

MOCKDIR=$(mktemp -d /tmp/gossip-coll-XXXXXX)
trap "rm -rf $MOCKDIR" EXIT
curl() {
    local url=""
    for arg in "$@"; do case "$arg" in http*) url="$arg"; break ;; esac; done
    local key; key=$(echo -n "$url" | md5sum | cut -d' ' -f1)
    [[ -f "$MOCKDIR/$key" ]] && { cat "$MOCKDIR/$key"; return 0; }
    return 7
}
export -f curl; export MOCKDIR
set_mock()  { local key; key=$(echo -n "$1" | md5sum | cut -d' ' -f1); echo "$2" > "$MOCKDIR/$key"; }
clear_mocks() { rm -f "$MOCKDIR"/*; }

title_banner "F3: shared-IP / different-port collision"

# Live PRIMARY (staked) on 10.0.0.5:8001; we (unstaked STANDBY) on 10.0.0.5:8101 — same IP.
COLLISION='{"jsonrpc":"2.0","result":[{"pubkey":"StakedPubkey111111111111111111111111111111","gossip":"10.0.0.5:8001"},{"pubkey":"UnstakedPubkey1111111111111111111111111111","gossip":"10.0.0.5:8101"}],"id":1}'

clear_mocks; set_mock "$TIER2_RPC" "$COLLISION"; set_mock "$TIER3_RPC" "$COLLISION"
check_primary_dropped_identity; rc=$?
echo ""
[[ $rc -eq 1 ]] && ok "shared-IP / different-port live holder → BLOCK (rc=$rc)" \
                || bad "fence did NOT block the F3 collision (rc=$rc) — double-sign risk"

# Demonstrate the v0.6.1 bug is real: an IP-only comparison would FALSELY ALLOW this mock.
ip_only_verdict() {
    local staked_ip our_ip
    staked_ip=$(echo "$COLLISION" | jq -r --arg p "$STAKED_PUBKEY"   '.result[]?|select(.pubkey==$p)|.gossip//empty'|cut -d: -f1)
    our_ip=$(echo "$COLLISION"    | jq -r --arg p "$UNSTAKED_PUBKEY" '.result[]?|select(.pubkey==$p)|.gossip//empty'|cut -d: -f1)
    [[ "$staked_ip" == "$our_ip" ]] && echo "ALLOW" || echo "BLOCK"
}
echo ""
[[ "$(ip_only_verdict)" == "ALLOW" ]] && ok "(context) old IP-only heuristic WOULD have allowed it — fix is meaningful" \
                                      || bad "expected the old IP-only heuristic to allow (test setup wrong)"

# True self entry (staked stale on our EXACT endpoint) must still be recognized as us → ALLOW.
SELF='{"jsonrpc":"2.0","result":[{"pubkey":"StakedPubkey111111111111111111111111111111","gossip":"10.0.0.5:8101"},{"pubkey":"UnstakedPubkey1111111111111111111111111111","gossip":"10.0.0.5:8101"}],"id":1}'
clear_mocks; set_mock "$TIER2_RPC" "$SELF"; set_mock "$TIER3_RPC" "$SELF"
check_primary_dropped_identity; rc=$?
echo ""
[[ $rc -eq 0 ]] && ok "genuine self endpoint (exact ip:port match) → ALLOW (rc=$rc)" \
                || bad "genuine self match wrongly blocked (rc=$rc)"

results_banner
