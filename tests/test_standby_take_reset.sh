#!/bin/bash
# v0.6.9 (B1): a FRESH standby takeover must re-arm the self-fence trackers (take_staked_identity now
# calls _selffence_reset, mirroring the primary's switch_to_staked). Without it, stale H3
# restore-pending flags armed by load_state from a PRIOR staked tenure survive — un-consumed while the
# node was unstaked — into the new take, and the freshly-promoted validator's NORMAL catch-up vote lag
# (> SELF_FENCE_VOTE_LAG_SLOTS) trips a BACKDATED self-fence demote + 600s re-take lockout, tearing
# down a legitimate failover. Drives the REAL take_staked_identity + check_self_fence_isolation with
# mocks ONLY at the I/O boundary.
#   (R-a) after a real take the votelag restore-pending flag + baseline + sustain timer are CLEARED
#   (R-b) with a stale flag armed, the first post-take self-fence cycle (catch-up lag) does NOT demote
#   (R-c) NON-VACUOUS CONTROL: on a copy with the B1 `_selffence_reset` line stripped from take, the
#         SAME inputs DO demote (the stale backdate fires) — proves the reset is load-bearing
#   (R-d) structural: v0.6.8 take_staked_identity had no self-fence reset (the whole self-fence is new)

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
V068="$DIR/../../0.6.8/failover-v0.6.8/solana-standby-failover.sh"
[[ -f "$STANDBY" ]] || { echo "  ❌ standby script not found"; exit 1; }

# Arm a stale votelag restore-pending (as load_state would from a prior staked tenure), do a REAL take,
# then run the first self-fence cycle with a fresh catch-up lag. Echoes: take rc, the votelag flags
# captured right AFTER the take (before the self-fence cycle), and whether a demote fired.
run_b1() {   # $1=script
  local script="$1"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
    LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
    SOLANA_PATH="/mock"; LEDGER_PATH="/mock/ledger"; VALIDATOR_TYPE="agave"; VALIDATOR_SERVICE="solana"
    STANDBY_SELF_FENCE=true
    SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_MAX_BEHIND=0
    SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
    SETIDENTITY_TIMEOUT=15; SELF_FENCE_HARD_STOP=true; HARD_STOP_REVERIFY_SECS=0
    SELF_FENCE_RETAKE_COOLDOWN=600; COLLISION_CHECK_INTERVAL=60; ALERT_THROTTLE=600
    TG_ENABLED=false; DRY_RUN=false
    KP_S=$(mktemp); echo '[1]' > "$KP_S"; STAKED_KEYPAIR="$KP_S"
    KP_U=$(mktemp); echo '[2]' > "$KP_U"; UNSTAKED_KEYPAIR="$KP_U"
    ID_FILE=$(mktemp)
    trap 'rm -f "$KP_S" "$KP_U" "$ID_FILE"' EXIT
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    send_telegram(){ return 0; }; send_webhook(){ :; }; save_state(){ :; }; sleep(){ :; }
    _alert=""; alert(){ _alert+="|$3"; }
    alert_warn(){ :; }; alert_info(){ :; }
    pgrep(){ return 1; }; kill(){ return 0; }
    get_local_identity(){ cat "$ID_FILE"; }
    _SIM_NOW=1700000000
    date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
    # admin-socket mock: set-identity applies the matching pubkey (take → S1, give-back → U1) so the
    # demote's REAL give_back_identity can complete when the (control) misfire path exercises it.
    timeout(){
        case "$*" in
            *set-identity*"$STAKED_KEYPAIR"*)   echo "$STAKED_PUBKEY" > "$ID_FILE"; return 0 ;;
            *set-identity*"$UNSTAKED_KEYPAIR"*) echo "$UNSTAKED_PUBKEY" > "$ID_FILE"; return 0 ;;
            *authorized-voter\ add*)            return 0 ;;
            *remove-all*)                       return 0 ;;
            *systemctl*)                        return 0 ;;
        esac
        return 0
    }
    # self-fence curl mock: getSlot advancing (frozen path stays HEALTHY so ONLY N6 is under test);
    # getVoteAccounts shows the freshly-promoted node's own lastVote 100 slots behind cluster-max
    # (> SELF_FENCE_VOTE_LAG_SLOTS=32) — the NORMAL catch-up lag right after a takeover.
    _LOCAL_SLOT=100000; _OWN_LV=99900; _CLUSTER_MAX=100000
    curl(){
        local data=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { data="$2"; shift 2; continue; }; shift; done
        case "$data" in
            *getSlot*)   printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$_LOCAL_SLOT"; return 0 ;;
            *getHealth*) printf '{"jsonrpc":"2.0","result":"ok","id":1}'; return 0 ;;
            *getVoteAccounts*)
                printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"C1","lastVote":%s},{"votePubkey":"%s","lastVote":%s}],"delinquent":[]},"id":1}' \
                    "$_CLUSTER_MAX" "$VOTE_PUBKEY" "$_OWN_LV"; return 0 ;;
        esac
        return 7
    }

    # ── ARM the stale H3 votelag restore-pending, exactly as load_state would from a prior tenure ──
    echo "$UNSTAKED_PUBKEY" > "$ID_FILE"; CURRENT_IDENTITY="$UNSTAKED_PUBKEY"
    _selffence_votelag_restore_pending=1
    _selffence_votelag_baseline=1
    _selffence_restored_votelag_since=$(( _SIM_NOW - 400 ))   # stale sustain start: 400s ago
    _last_confirmed_slot=""; _last_confirmed_advance_ts=$_SIM_NOW
    _selffence_votelag_since=0; _selffence_votelag_healthy=0
    _selffence_restore_pending=0; _selffence_noanswer_restore_pending=0
    _delinq_window="1111111111"; FIRST_DELINQUENT_TIME=123; LAST_LIVENESS_ACTIVE_TIME=456; LAST_TAKEOVER_TIME=0

    # ── the FRESH, legitimate takeover ──
    take_staked_identity "b1-test" >/dev/null 2>&1; take_rc=$?
    flags="pend=${_selffence_votelag_restore_pending:-x}|since=${_selffence_votelag_since:-x}|base=${_selffence_votelag_baseline:-EMPTY}"

    # ── first self-fence cycle(s) of the new tenure (frozen path healthy → isolate N6 catch-up lag) ──
    _last_confirmed_slot=$(( _LOCAL_SLOT - 10 )); _last_confirmed_advance_ts=$_SIM_NOW
    check_self_fence_isolation >/dev/null 2>&1
    _SIM_NOW=$(( _SIM_NOW + 1 )); check_self_fence_isolation >/dev/null 2>&1
    demoted=no; [[ "$_alert" == *"SWITCHED TO UNSTAKED"* ]] && demoted=yes

    printf 'take_rc=%s|%s|demoted=%s|id=%s\n' "$take_rc" "$flags" "$demoted" "$(cat "$ID_FILE")"
  )
}
field(){ printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

echo "============================================="
echo "  STANDBY take → self-fence reset (v0.6.9 B1)"
echo "============================================="

echo ""; echo "─── (R-a)/(R-b) real take clears the stale votelag flags → no spurious self-fence ───"
out=$(run_b1 "$STANDBY")
if [[ "$(field "$out" take_rc)" == "0" && "$(field "$out" id)" == "S1" ]]; then
    if [[ "$(field "$out" pend)" == "0" && "$(field "$out" since)" == "0" && "$(field "$out" base)" == "EMPTY" ]]; then
        ok "(R-a) take_staked_identity re-armed the self-fence trackers (pend=0, since=0, baseline cleared)"
    else
        bad "(R-a) stale votelag flags survived the take: $out"
    fi
    if [[ "$(field "$out" demoted)" == "no" ]]; then
        ok "(R-b) first post-take self-fence cycle with catch-up lag did NOT demote (still staked)"
    else
        bad "(R-b) a fresh legitimate takeover self-fenced on benign catch-up lag: $out"
    fi
else
    bad "(R-a/R-b) take did not apply as expected: $out"
fi

echo ""; echo "─── (R-c) NON-VACUOUS control: strip B1's reset from take → the stale backdate FIRES ───"
PATCHED=$(mktemp)
sed '/_selffence_reset   # v0.6.9 (B1): a FRESH staked tenure/d' "$STANDBY" > "$PATCHED"
# sanity: the strip must have removed exactly the take-path reset (definition + demote reset stay)
stripped=$(grep -c '_selffence_reset' "$PATCHED"); orig=$(grep -c '_selffence_reset' "$STANDBY")
out=$(run_b1 "$PATCHED"); rm -f "$PATCHED"
if [[ $(( orig - stripped )) -eq 1 && "$(field "$out" demoted)" == "yes" && "$(field "$out" base)" == "1" ]]; then
    ok "(R-c) without take's _selffence_reset the stale flag survives and DOES demote → the fix is load-bearing"
else
    bad "(R-c) control vacuous/miswired (removed=$(( orig - stripped )) demoted=$(field "$out" demoted) base=$(field "$out" base))"
fi

echo ""; echo "─── (R-d) structural: v0.6.8 take_staked_identity had no self-fence reset ───"
if [[ -f "$V068" ]]; then
    v8=$(sed -n '/^take_staked_identity/,/^}/p' "$V068" | grep -c '_selffence_reset')
    [[ $v8 -eq 0 ]] && ok "(R-d) v0.6.8 take had 0 _selffence_reset (no promoted-holder self-fence yet) → B1 genuinely new" \
                    || bad "(R-d) v0.6.8 take unexpectedly resets ($v8)"
else
    ok "(R-d) v0.6.8 baseline not present to compare (skipped)"
fi

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
