#!/bin/bash
# v0.6.8 (Option A): gossip identity-flip fast-path. Two layers:
#   peer_has_relinquished — the POSITIVE relinquish detector (A2 pubkey-pinned + absent→present transition,
#     A4 manual-recovery gate, A6 >=2 vantage points). Fail-closed everywhere.
#   attempt_takeover early-exit — the flip skips ONLY the timer; Gate 2 (external-confirm) and Gate 3
#     (vote-liveness==frozen) STILL run (A1, A5). No flip / off ⇒ the exact v0.6.7 wait (pure OR fallback).
#   (P-off/unset/manual) fail-closed preconditions                  → never fires
#   (P-1rpc)   only one RPC responds (A6)                            → never fires
#   (P-absent) unstaked absent on both                               → no fire; records the absent transition
#   (P-noedge) present but never seen absent this episode            → no fire (no transition)
#   (P-1van)   present on only ONE vantage                           → no fire (need both)
#   (P-neigh)  a DIFFERENT (neighbor) pubkey present                 → no fire (matches configured pubkey only)
#   (P-confirm/fire) present on both after absent, N consecutive     → FIRES once it reaches CONFIRM_SAMPLES
#   (FA-holder) F-A: watched key at the STAKED endpoint              → FIRES (the holder relinquished)
#   (FA-nonholder) F-A: watched key at a DIFFERENT endpoint          → NO fire (non-holder peer ignored)
#   (FA-absent) F-A: staked identity absent from gossip              → NO fire (cannot anchor → timer)
#   (FA-control) F-A non-vacuous: strip the endpoint check           → the non-holder flip FIRES (bug returns)
#   (I-cd)     flip + liveness cannot-determine(2)  [HEADLINE]       → NO takeover
#   (I-frozen) flip + liveness frozen(1) + confirm delinquent        → TAKES
#   (I-voting) flip + liveness voting(0)                             → NO takeover + N3 re-anchor
#   (I-noflip) no flip, elapsed<delay                               → wait (gates NOT reached)
#   (I-stagger) flip but elapsed < FASTPATH_STAGGER_SECS (BACKUP)    → no fast-take (stagger preserved)
#   (I-off)    WITNESS_FASTPATH=false                                → pure v0.6.7 wait

# The P-* cases call the REAL peer_has_relinquished (sourced below); the I-* block later mocks it. The
# linter can't see the sourced def and flags SC2218 (used-before-defined) — a false positive, disabled:
# shellcheck disable=SC2218
set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$STANDBY" ]] || { echo "  ❌ standby not found"; exit 1; }
SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"; rm -f "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock

STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
PRIMARY_UNSTAKED_PUBKEY="UnstakedHolder1111111111111111111111111111"
NEIGHBOR_PUBKEY="NeighborNode11111111111111111111111111111"
TIER2_RPC="http://t2"; TIER3_RPC="http://t3"
log_info() { :; }; log_warn() { :; }; log_error() { :; }

# ── curl mock for getClusterNodes ──
# Each RPC may advertise: the STAKED identity's (lingering ~48h) entry at _STAKED_EP, and one non-staked
# pubkey (_Tx_PK) at endpoint _Tx_EP. F-A anchors the flip to the holder: a watched unstaked pubkey only
# counts when advertised at the SAME endpoint as the staked identity.
_STAKED_EP="10.0.0.1:8001"                    # the holder's gossip endpoint (staked identity's lingering entry)
_T2_UP=1; _T3_UP=1; _T2_PK=""; _T3_PK=""      # _Tx_PK = which non-staked pubkey that RPC advertises ("" = none)
_T2_EP="$_STAKED_EP"; _T3_EP="$_STAKED_EP"    # endpoint at which _Tx_PK is advertised (default = holder endpoint = a real flip)
_T2_STAKED=1; _T3_STAKED=1                    # whether the STAKED identity is present in gossip (F-A anchor; 0 ⇒ cannot anchor)
curl() {
    local url="" data=""
    while [[ $# -gt 0 ]]; do case "$1" in -d) data="$2"; shift 2; continue ;; http*) url="$1" ;; esac; shift; done
    local up pk ep st
    if [[ "$url" == "$TIER2_RPC" ]]; then up=$_T2_UP; pk=$_T2_PK; ep=$_T2_EP; st=$_T2_STAKED
    else up=$_T3_UP; pk=$_T3_PK; ep=$_T3_EP; st=$_T3_STAKED; fi
    [[ $up -eq 0 ]] && return 7
    if [[ "$data" == *getClusterNodes* ]]; then
        local entries='{"pubkey":"SomeOtherValidator","gossip":"9.9.9.9:8001"}'
        [[ $st -eq 1 ]] && entries="${entries},{\"pubkey\":\"${STAKED_PUBKEY}\",\"gossip\":\"${_STAKED_EP}\"}"
        [[ -n "$pk" ]]  && entries="${entries},{\"pubkey\":\"${pk}\",\"gossip\":\"${ep}\"}"
        printf '{"result":[%s]}' "$entries"
        return 0
    fi
    return 7
}
WITNESS_FASTPATH=true; FASTPATH_PEER_RECOVERY_MANUAL=true; FASTPATH_CONFIRM_SAMPLES=2
prep_p() { _fastpath_absent_seen=0; _fastpath_confirm=0; _T2_UP=1; _T3_UP=1; _T2_PK=""; _T3_PK=""; _T2_EP="$_STAKED_EP"; _T3_EP="$_STAKED_EP"; _T2_STAKED=1; _T3_STAKED=1; WITNESS_FASTPATH=true; PRIMARY_UNSTAKED_PUBKEY="UnstakedHolder1111111111111111111111111111"; FASTPATH_PEER_RECOVERY_MANUAL=true; }

echo "============================================="
echo "  Option A: peer_has_relinquished + attempt_takeover early-exit (v0.6.8)"
echo "============================================="

echo ""; echo "─── peer_has_relinquished — fail-closed preconditions ───"
prep_p; WITNESS_FASTPATH=false; peer_has_relinquished; [[ $? -ne 0 ]] && ok "(P-off) WITNESS_FASTPATH=false → no fire" || bad "(P-off) fired while off"
prep_p; PRIMARY_UNSTAKED_PUBKEY=""; peer_has_relinquished; [[ $? -ne 0 ]] && ok "(P-unset) no pubkey → no fire (fail-closed)" || bad "(P-unset) fired with no pubkey"
prep_p; FASTPATH_PEER_RECOVERY_MANUAL=false; _fastpath_absent_seen=1; _T2_PK="$PRIMARY_UNSTAKED_PUBKEY"; _T3_PK="$PRIMARY_UNSTAKED_PUBKEY"; peer_has_relinquished; [[ $? -ne 0 ]] && ok "(P-manual) recovery not affirmed manual → no fire (A4)" || bad "(P-manual) fired without manual-recovery affirmation"

echo ""; echo "─── peer_has_relinquished — A6 vantage points + A2 transition ───"
prep_p; _T3_UP=0; _T2_PK="$PRIMARY_UNSTAKED_PUBKEY"; _fastpath_absent_seen=1; peer_has_relinquished; [[ $? -ne 0 ]] && ok "(P-1rpc) only one RPC up → no fire (A6 needs 2 vantages)" || bad "(P-1rpc) fired on a single RPC"
prep_p; peer_has_relinquished; rc=$?; [[ $rc -ne 0 && $_fastpath_absent_seen -eq 1 ]] && ok "(P-absent) unstaked absent on both → no fire; absent transition recorded" || bad "(P-absent) wrong (rc=$rc absent=$_fastpath_absent_seen)"
prep_p; _T2_PK="$PRIMARY_UNSTAKED_PUBKEY"; _T3_PK="$PRIMARY_UNSTAKED_PUBKEY"; peer_has_relinquished; [[ $? -ne 0 ]] && ok "(P-noedge) present but never seen absent this episode → no fire (no transition)" || bad "(P-noedge) fired without an absent→present transition"
prep_p; _fastpath_absent_seen=1; _T2_PK="$PRIMARY_UNSTAKED_PUBKEY"; _T3_PK=""; peer_has_relinquished; [[ $? -ne 0 ]] && ok "(P-1van) present on only ONE vantage → no fire (need both)" || bad "(P-1van) fired on one vantage"
prep_p; _fastpath_absent_seen=1; _T2_PK="$NEIGHBOR_PUBKEY"; _T3_PK="$NEIGHBOR_PUBKEY"; peer_has_relinquished; [[ $? -ne 0 ]] && ok "(P-neigh) a different (neighbor) pubkey present → no fire (matches configured pubkey only)" || bad "(P-neigh) fired on a neighbor pubkey"

echo ""; echo "─── peer_has_relinquished — corroborated transition fires after N consecutive ───"
prep_p; _fastpath_absent_seen=1; _T2_PK="$PRIMARY_UNSTAKED_PUBKEY"; _T3_PK="$PRIMARY_UNSTAKED_PUBKEY"
peer_has_relinquished; rc1=$?; peer_has_relinquished; rc2=$?
[[ $rc1 -ne 0 && $rc2 -eq 0 && $_fastpath_confirm -ge $FASTPATH_CONFIRM_SAMPLES ]] \
    && ok "(P-fire) present on both after absent → confirm 1 (no fire) then 2 (FIRES) — N-consecutive corroboration" \
    || bad "(P-fire) wrong (rc1=$rc1 rc2=$rc2 confirm=$_fastpath_confirm)"
# multi-peer list: any configured unstaked pubkey matches
prep_p; PRIMARY_UNSTAKED_PUBKEY="PeerA1111111111111111111111111111111111111 UnstakedHolder1111111111111111111111111111"
_fastpath_absent_seen=1; _T2_PK="UnstakedHolder1111111111111111111111111111"; _T3_PK="UnstakedHolder1111111111111111111111111111"
peer_has_relinquished >/dev/null; peer_has_relinquished; [[ $? -eq 0 ]] && ok "(P-multi) space-separated peer list matches any configured unstaked pubkey" || bad "(P-multi) multi-peer match failed"
# a confirm gap (one vantage drops) resets the consecutive counter
prep_p; _fastpath_absent_seen=1; _T2_PK="$PRIMARY_UNSTAKED_PUBKEY"; _T3_PK="$PRIMARY_UNSTAKED_PUBKEY"
peer_has_relinquished >/dev/null; _T3_PK=""; peer_has_relinquished >/dev/null
[[ $_fastpath_confirm -eq 0 ]] && ok "(P-gap) a non-corroborated cycle resets the consecutive counter (must be contiguous)" || bad "(P-gap) counter not reset (confirm=$_fastpath_confirm)"

echo ""; echo "─── peer_has_relinquished — F-A: the flip is anchored to the HOLDER's gossip endpoint ───"
# 3-entry watch list (multi-peer topology). Only the entry advertised at the STAKED identity's endpoint
# (set-identity keeps ports) counts as the holder relinquishing; a watched peer at any other endpoint is a
# NON-holder and must NOT fast-fire (else a transient holder vote-pause + a non-holder flip → double-sign).
HOLDER_PK="UnstakedHolder1111111111111111111111111111"
WATCH3="PeerA1111111111111111111111111111111111111 ${HOLDER_PK} PeerC1111111111111111111111111111111111111"
OTHER_EP="10.9.9.9:8001"   # a NON-holder peer's endpoint (!= _STAKED_EP)

# (FA-holder) the HOLDER's watched key flips at the staked endpoint → FIRES after N consecutive
prep_p; PRIMARY_UNSTAKED_PUBKEY="$WATCH3"; _fastpath_absent_seen=1
_T2_PK="$HOLDER_PK"; _T3_PK="$HOLDER_PK"          # _Tx_EP defaults to _STAKED_EP ⇒ at the holder endpoint
peer_has_relinquished >/dev/null; peer_has_relinquished
[[ $? -eq 0 ]] && ok "(FA-holder) watched key at the STAKED endpoint → FIRES (the holder relinquished)" || bad "(FA-holder) holder-endpoint flip did not fire"

# (FA-nonholder) a watched (but non-holder) key flips at a DIFFERENT endpoint → NO fire
prep_p; PRIMARY_UNSTAKED_PUBKEY="$WATCH3"; _fastpath_absent_seen=1
_T2_PK="PeerA1111111111111111111111111111111111111"; _T3_PK="PeerA1111111111111111111111111111111111111"
_T2_EP="$OTHER_EP"; _T3_EP="$OTHER_EP"
peer_has_relinquished >/dev/null; peer_has_relinquished; rcn=$?
[[ $rcn -ne 0 && $_fastpath_confirm -eq 0 ]] && ok "(FA-nonholder) watched key at a DIFFERENT endpoint → NO fire (non-holder peer ignored)" || bad "(FA-nonholder) fast-fired on a non-holder peer (rc=$rcn confirm=$_fastpath_confirm)"

# (FA-absent) staked identity absent from gossip → cannot anchor → NO fast-take (timer governs)
prep_p; PRIMARY_UNSTAKED_PUBKEY="$WATCH3"; _fastpath_absent_seen=1
_T2_STAKED=0; _T3_STAKED=0; _T2_PK="$HOLDER_PK"; _T3_PK="$HOLDER_PK"   # holder key present, but staked unanchorable
peer_has_relinquished >/dev/null; peer_has_relinquished; rca=$?
[[ $rca -ne 0 && $_fastpath_confirm -eq 0 ]] && ok "(FA-absent) staked absent from gossip → NO fast-take (cannot anchor)" || bad "(FA-absent) fast-fired with no staked anchor (rc=$rca confirm=$_fastpath_confirm)"

# (FA-control) NON-VACUOUS: strip the endpoint equality from the REAL function (revert to pre-F-A "match
# any pubkey regardless of endpoint") → the FA-nonholder data now FIRES, proving the anchor is load-bearing.
_buggy_src=$(sed -n '/^peer_has_relinquished() {/,/^}/p' "$STANDBY" | sed 's/ && "\$pk_ep" == "\$staked_ep"//' | sed '1s/^peer_has_relinquished/peer_has_relinquished_noanchor/')
eval "$_buggy_src"
_fastpath_absent_seen=1; _fastpath_confirm=0
_T2_STAKED=1; _T3_STAKED=1; _T2_PK="PeerA1111111111111111111111111111111111111"; _T3_PK="PeerA1111111111111111111111111111111111111"
_T2_EP="$OTHER_EP"; _T3_EP="$OTHER_EP"; PRIMARY_UNSTAKED_PUBKEY="$WATCH3"
peer_has_relinquished_noanchor >/dev/null; peer_has_relinquished_noanchor
[[ $? -eq 0 ]] && ok "(FA-control) with the endpoint check stripped, the non-holder flip FIRES → FA-nonholder is non-vacuous" || bad "(FA-control) stripped variant did not fire — the FA-nonholder test may be vacuous"

# ════════ attempt_takeover early-exit integration ════════
echo ""; echo "─── attempt_takeover — the flip skips ONLY the timer; gates still run ───"
# Mocks for the gate functions; peer_has_relinquished is mocked here (its own logic is unit-tested above).
_FLIP=0; _CONFIRM=0; _LIVENESS=1; _take_calls=0; _confirm_calls=0
peer_has_relinquished() { return $_FLIP; }
confirm_delinquency_external() { _confirm_calls=$((_confirm_calls+1)); return $_CONFIRM; }
staked_is_actively_voting() { return $_LIVENESS; }
take_staked_identity() { _take_calls=$((_take_calls+1)); return 0; }
window_count() { echo 7; }
get_staked_liveness_sample() { echo "100 200"; }
alert_info() { :; }; alert_warn() { :; }; alert() { :; }
GOSSIP_VERIFY=false; VOTE_LIVENESS_VERIFY=true; TAKEOVER_DELAY=60; DELINQUENCY_WINDOW_SIZE=10
TAKEOVER_COOLDOWN=300; EXTERNAL_CONFIRM_THROTTLE=10; _turbo_mode=false
prep_i() {
    _take_calls=0; _confirm_calls=0; WITNESS_FASTPATH=true; FASTPATH_STAGGER_SECS=0
    _fastpath_stagger_floor=0; _fastpath_disabled=""   # v0.6.8 (S1): the gate uses the computed floor
    FIRST_DELINQUENT_TIME=$(( $(date +%s) - 5 )); LAST_LIVENESS_ACTIVE_TIME=0
    LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _liveness_first_vote="100"; _takeover_alert_sent=""
}

prep_i; _FLIP=0; _CONFIRM=0; _LIVENESS=2     # flip observed, externals delinquent, liveness CANNOT-DETERMINE
attempt_takeover; rc=$?
[[ $_take_calls -eq 0 && $rc -ne 0 ]] \
    && ok "(I-cd) HEADLINE: flip + liveness cannot-determine(2) → NO takeover (flip never bypasses the fence)" \
    || bad "(I-cd) took over on cannot-determine! (take=$_take_calls rc=$rc)"

prep_i; _FLIP=0; _CONFIRM=0; _LIVENESS=1     # flip + delinquent + frozen → take
attempt_takeover >/dev/null
[[ $_take_calls -eq 1 ]] \
    && ok "(I-frozen) flip + external-confirm + liveness frozen(1) → TAKES (timer skipped, gates passed)" \
    || bad "(I-frozen) did not take when all gates clear (take=$_take_calls)"

prep_i; _FLIP=0; _CONFIRM=0; _LIVENESS=0     # flip but holder STILL VOTING → block + re-anchor
attempt_takeover >/dev/null
[[ $_take_calls -eq 0 && $LAST_LIVENESS_ACTIVE_TIME -ne 0 ]] \
    && ok "(I-voting) flip + liveness voting(0) → NO takeover + N3 re-anchor (holder still voting wins)" \
    || bad "(I-voting) wrong (take=$_take_calls anchor=$LAST_LIVENESS_ACTIVE_TIME)"

prep_i; _FLIP=1; _CONFIRM=0; _LIVENESS=1     # NO flip, still inside the delay
attempt_takeover; rc=$?
[[ $_take_calls -eq 0 && $_confirm_calls -eq 0 && $rc -ne 0 ]] \
    && ok "(I-noflip) no flip + elapsed<delay → wait; gates NOT reached (pure OR fallback = v0.6.7)" \
    || bad "(I-noflip) wrong (take=$_take_calls confirm_calls=$_confirm_calls rc=$rc)"

prep_i; _FLIP=0; _CONFIRM=0; _LIVENESS=1; _fastpath_stagger_floor=120   # flip but below this node's computed stagger floor (S1)
attempt_takeover; rc=$?
[[ $_take_calls -eq 0 && $_confirm_calls -eq 0 && $rc -ne 0 ]] \
    && ok "(I-stagger) flip but elapsed(~5s) < _fastpath_stagger_floor(120) → no fast-take (BACKUP stagger preserved)" \
    || bad "(I-stagger) BACKUP fast-took ahead of its stagger floor (take=$_take_calls confirm=$_confirm_calls)"

prep_i; _FLIP=0; _CONFIRM=0; _LIVENESS=1; WITNESS_FASTPATH=false      # fast-path OFF
attempt_takeover; rc=$?
[[ $_take_calls -eq 0 && $_confirm_calls -eq 0 && $rc -ne 0 ]] \
    && ok "(I-off) WITNESS_FASTPATH=false → pure v0.6.7 wait (no early-exit, gates not reached)" \
    || bad "(I-off) early-exit fired while off (take=$_take_calls confirm=$_confirm_calls)"

# ════════ (S6) REAL peer_has_relinquished × REAL attempt_takeover (no detector mock) ════════
echo ""; echo "─── (S6) real flip detector + real attempt_takeover + liveness cannot-determine → NO takeover ───"
# Restore the REAL peer_has_relinquished (the I-* block mocked it); keep the real attempt_takeover + the
# P-* curl mock (getClusterNodes by _T2_PK/_T3_PK). Drive a real absent→present→fire build-up, then assert
# that even when the REAL detector fires, liveness=cannot-determine(2) blocks the take (the headline, but
# through the real detector this time).
# shellcheck disable=SC1090
eval "$(sed -n '/^peer_has_relinquished() {/,/^}/p' "$STANDBY")"
FASTPATH_CONFIRM_SAMPLES=2; FASTPATH_PEER_RECOVERY_MANUAL=true; _fastpath_disabled=""; _fastpath_stagger_floor=0
PRIMARY_UNSTAKED_PUBKEY="UnstakedHolder1111111111111111111111111111"
_CONFIRM=0; _LIVENESS=2                       # external delinquent; liveness CANNOT-DETERMINE
# NB: run attempt_takeover in the PARENT shell (NOT $(...)) so the real detector's absent→present state
# (_fastpath_absent_seen/_fastpath_confirm) persists across cycles.
WITNESS_FASTPATH=true; _T2_UP=1; _T3_UP=1; GOSSIP_VERIFY=false; TAKEOVER_DELAY=120
_T2_EP="$_STAKED_EP"; _T3_EP="$_STAKED_EP"; _T2_STAKED=1; _T3_STAKED=1   # F-A: holder present at the staked endpoint so the flip anchors
s6cycle() {  # set elapsed=5 inside the countdown, fresh liveness sample; runs in the PARENT
    _take_calls=0; FIRST_DELINQUENT_TIME=$(( $(date +%s) - 5 )); LAST_LIVENESS_ACTIVE_TIME=0
    LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _liveness_first_vote="100"; _takeover_alert_sent=""
    attempt_takeover >/dev/null 2>&1
}
_fastpath_absent_seen=0; _fastpath_confirm=0
_T2_PK=""; _T3_PK=""; s6cycle; t_absent=$_take_calls                                 # cycle 1: absent → records absent
_T2_PK="$PRIMARY_UNSTAKED_PUBKEY"; _T3_PK="$PRIMARY_UNSTAKED_PUBKEY"; s6cycle; t1=$_take_calls   # cycle 2: present, confirm=1
s6cycle; t2=$_take_calls                                                             # cycle 3: present, confirm=2 → detector FIRES
[[ "$t_absent" -eq 0 && "$t1" -eq 0 && "$t2" -eq 0 && $_fastpath_confirm -ge $FASTPATH_CONFIRM_SAMPLES ]] \
    && ok "(S6) real peer_has_relinquished fired (confirm=$_fastpath_confirm) through real attempt_takeover, yet liveness=cannot-determine → NO takeover (flip never bypasses Gate 3)" \
    || bad "(S6) wrong (absent:$t_absent c1:$t1 c2:$t2 confirm:$_fastpath_confirm) — a take occurred or the detector never fired"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
