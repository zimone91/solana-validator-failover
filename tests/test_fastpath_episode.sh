#!/bin/bash
# v0.6.8 (S2, Audit-2 fix): the fast-path A2 episode state (_fastpath_absent_seen / _fastpath_confirm)
# must be reset at EVERY episode end, not only in window_reset. Audit-2 found the organic
# delinquency-clear path (FIRST_DELINQUENT_TIME=0; _takeover_alert_sent="") did NOT reset it, so a
# leaked _fastpath_absent_seen=1 satisfied the absent→present transition in the NEXT episode without a
# fresh absent observation. Fix: reset it at that site too.
#   (LEAK-danger) _fastpath_absent_seen=1 leaked + present-on-both → fires WITHOUT a fresh absent (the risk)
#   (RESET-safe)  _fastpath_absent_seen=0 (reset) + present-on-both → does NOT fire (transition required)
#   (SITE)        both episode-end sites (window_reset AND the organic clear) reset the fast-path state

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"; rm -f "$SRC"
log_info() { :; }; log_warn() { :; }; log_error() { :; }

STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
PRIMARY_UNSTAKED_PUBKEY="UnstakedHolder1111111111111111111111111111"
TIER2_RPC="http://t2"; TIER3_RPC="http://t3"
WITNESS_FASTPATH=true; FASTPATH_PEER_RECOVERY_MANUAL=true; FASTPATH_CONFIRM_SAMPLES=2; _fastpath_disabled=""
_STAKED_EP="10.0.0.1:8001"                                            # holder endpoint (F-A anchor)
_T2_PK="$PRIMARY_UNSTAKED_PUBKEY"; _T3_PK="$PRIMARY_UNSTAKED_PUBKEY"   # holder's unstaked present on both, at the staked endpoint
curl() {
    local url="" data=""
    while [[ $# -gt 0 ]]; do case "$1" in -d) data="$2"; shift 2; continue ;; http*) url="$1" ;; esac; shift; done
    local pk; [[ "$url" == "$TIER2_RPC" ]] && pk=$_T2_PK || pk=$_T3_PK
    # F-A: the watched unstaked pubkey AND the staked identity are advertised at the SAME endpoint (a real
    # holder flip), so the absent→present transition is what the leak/reset cases turn on (not the anchor).
    [[ "$data" == *getClusterNodes* ]] && { printf '{"result":[{"pubkey":"%s","gossip":"%s"},{"pubkey":"%s","gossip":"%s"}]}' "$STAKED_PUBKEY" "$_STAKED_EP" "$pk" "$_STAKED_EP"; return 0; }
    return 7
}

echo "============================================="
echo "  Option A episode-state reset (v0.6.8 S2)"
echo "============================================="

echo ""; echo "─── behavioral: the absent-latch is load-bearing ───"
# LEAK danger: if _fastpath_absent_seen=1 survives into a new episode, present-on-both fires with NO fresh absent
_fastpath_absent_seen=1; _fastpath_confirm=0
peer_has_relinquished >/dev/null; peer_has_relinquished; rc=$?
[[ $rc -eq 0 ]] \
    && ok "(LEAK-danger) a leaked _fastpath_absent_seen=1 lets present-on-both fire WITHOUT a fresh absent → why S2 matters" \
    || bad "(LEAK-danger) expected the leak to fire (rc=$rc) — test premise wrong"
# RESET safe: with the episode state cleared (as the fix does at episode end), the same present-on-both does NOT fire
_fastpath_absent_seen=0; _fastpath_confirm=0
peer_has_relinquished >/dev/null; peer_has_relinquished; rc=$?
[[ $rc -ne 0 ]] \
    && ok "(RESET-safe) after the episode reset, present-on-both does NOT fire (a fresh absent→present transition is required)" \
    || bad "(RESET-safe) fired without a fresh absent (rc=$rc) — the reset is not protecting the transition"

echo ""; echo "─── structural: BOTH episode-end sites reset the fast-path state ───"
# window_reset resets it
sed -n '/^window_reset() {/,/^}/p' "$STANDBY" | grep -q '_fastpath_absent_seen=0' \
    && ok "(SITE-window) window_reset() resets _fastpath_absent_seen" || bad "(SITE-window) window_reset does NOT reset the fast-path state"
# the organic delinquency-clear path (the block that sets FIRST_DELINQUENT_TIME=0; _takeover_alert_sent="")
# resets it within the same block (the S2 fix)
awk '/FIRST_DELINQUENT_TIME=0; _takeover_alert_sent=""/{f=1} f{print} /_gossip_prefetched=false; _gossip_result=""/{if(f)exit}' "$STANDBY" | grep -q '_fastpath_absent_seen=0' \
    && ok "(SITE-organic) the organic delinquency-clear path resets _fastpath_absent_seen (S2 fix present)" \
    || bad "(SITE-organic) the organic clear path does NOT reset the fast-path state — S2 leak still open"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
