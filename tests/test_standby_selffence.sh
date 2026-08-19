#!/bin/bash
# v0.6.9 (H1): self-fence for the PROMOTED STANDBY. Drives the REAL ported functions on a simulated
# clock, with mocks ONLY at the I/O boundary (curl, timeout, pgrep/kill, notifiers).
# harness: tests/lib/harness.sh — load_seam, harness_clock_shims, ok/bad+banners (this suite's sink
# subset + alert capture stay local). The demote path runs the REAL bounded give_back_identity.
#   (H1-a) frozen confirmed slot fires at >= SELF_FENCE_ISOLATION_SECS (30) — not before
#   (H1-b) no-answer fires ONLY with a baseline (fresh start never arms); with baseline fires at >= 30s
#   (H1-c) N6 sustained + B2 hysteresis: 1 healthy dip does NOT clear; K consecutive healthy clears;
#          the flap (old timer + dip + over-threshold) FIRES
#   (H1-d) the demote calls the REAL bounded give-back → identity flips to our own unstaked +
#          🚨 "STANDBY SELF-FENCE — SWITCHED TO UNSTAKED" page + SELF_FENCE_DEMOTE_TIME armed +
#          takeover episode state reset
#   (H1-e) RE-TAKE LOCKOUT: post-fence, the REAL attempt_takeover refuses (all other gates green)
#          until SELF_FENCE_RETAKE_COOLDOWN elapses; after expiry the take proceeds
#   (H1-f) NON-VACUOUS CONTROL: with the fence knobs zeroed/disabled (same inputs), the old
#          "hold forever unfenced" behavior returns — no demote, still staked
#   (H1-g) structural: the shipped MAIN LOOP STAKED branch dispatches check_self_fence_isolation
#          under STANDBY_SELF_FENCE (v0.6.8 baseline had zero check_self_fence references)

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
V068="$HARNESS_DIR/../../0.6.8/failover-v0.6.8/solana-standby-failover.sh"

load_seam "$STANDBY"

# --- fixtures / I/O-boundary mocks ---
STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
SOLANA_PATH="/mock"; LEDGER_PATH="/mock/ledger"; VALIDATOR_TYPE="agave"; VALIDATOR_SERVICE="solana"
STANDBY_SELF_FENCE=true
SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_MAX_BEHIND=0
SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
SETIDENTITY_TIMEOUT=15; SELF_FENCE_HARD_STOP=true; HARD_STOP_REVERIFY_SECS=0
SELF_FENCE_RETAKE_COOLDOWN=600; COLLISION_CHECK_INTERVAL=60; ALERT_THROTTLE=600
TG_ENABLED=false; DRY_RUN=false
KP_UNSTAKED=$(mktemp); echo '[4,5,6]' > "$KP_UNSTAKED"; UNSTAKED_KEYPAIR="$KP_UNSTAKED"
KP_STAKED=$(mktemp); echo '[1,2,3]' > "$KP_STAKED"; STAKED_KEYPAIR="$KP_STAKED"
_ID_FILE=$(mktemp)
trap 'rm -f "$KP_UNSTAKED" "$KP_STAKED" "$_ID_FILE"' EXIT

log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
send_telegram(){ return 0; }; send_webhook(){ :; }
save_state(){ :; }   # persistence exercised in test_baseline_persistence.sh
sleep(){ :; }        # simulated clock only (see date below)
_SIM_NOW=1700000000
harness_clock_shims

# alert capture (all pages routed here)
_alert_log=""
alert(){ _alert_log+="|$3"; }
alert_info(){ :; }; alert_warn(){ :; }

# identity: file-backed so the timeout mock (runs in $()-subshells) can flip it
get_local_identity(){ cat "$_ID_FILE"; }
# timeout mock — the ONLY path give_back's admin calls go through. rc-0 set-identity applies the flip.
_RC_SETID=0; _RC_REMOVE=0
timeout(){
    case "$*" in
        *set-identity*"$UNSTAKED_KEYPAIR"*) [[ $_RC_SETID -eq 0 ]] && echo "$UNSTAKED_PUBKEY" > "$_ID_FILE"; return $_RC_SETID ;;
        *remove-all*)                       return $_RC_REMOVE ;;
        *systemctl*)                        return 0 ;;
    esac
    return 0
}
pgrep(){ return 1; }; kill(){ return 0; }

# curl mock: getSlot(confirmed) → $_LOCAL_SLOT (or silence when _MODE=noanswer);
# getVoteAccounts(LOCAL, processed) → own lastVote $_OWN_LV vs cluster-max $_CLUSTER_MAX.
_MODE="slot"; _LOCAL_SLOT=100000; _OWN_LV=99995; _CLUSTER_MAX=100000
curl(){
    local data=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { data="$2"; shift 2; continue; }; shift; done
    case "$data" in
        *getSlot*)   [[ "$_MODE" == "noanswer" ]] && return 7; printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$_LOCAL_SLOT"; return 0 ;;
        *getHealth*) printf '{"jsonrpc":"2.0","result":"ok","id":1}'; return 0 ;;
        *getVoteAccounts*)
            printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"Cluster111","lastVote":%s},{"votePubkey":"%s","lastVote":%s}],"delinquent":[]},"id":1}' \
                "$_CLUSTER_MAX" "$VOTE_PUBKEY" "$_OWN_LV"; return 0 ;;
    esac
    return 7
}

reset_all(){
    echo "$STAKED_PUBKEY" > "$_ID_FILE"; CURRENT_IDENTITY="$STAKED_PUBKEY"
    _alert_log=""; _RC_SETID=0; _RC_REMOVE=0; _MODE="slot"
    SELF_FENCE_DEMOTE_TIME=0; _last_lockout_log=0
    _selffence_reset; _delinq_window=""
    STANDBY_SELF_FENCE=true
    SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_MAX_BEHIND=0
    SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
}
# keep the frozen-slot path quiet while exercising N6 (slot advancing → healthy)
adv(){ _last_confirmed_slot=$(( _LOCAL_SLOT - 50 )); _last_confirmed_advance_ts=$_SIM_NOW; }

title_banner "STANDBY self-fence for the promoted holder (v0.6.9 H1)"

# ── (H1-a) frozen slot: fires at >= 30s, not before ──────────────────────────────────────────
echo ""; echo "─── (H1-a) frozen confirmed slot → demote at >= ${SELF_FENCE_ISOLATION_SECS}s (not before) ───"
reset_all; _SIM_NOW=1700000000
check_self_fence_isolation >/dev/null; rc0=$?           # baseline established
_SIM_NOW=$(( 1700000000 + 29 )); check_self_fence_isolation >/dev/null; rc29=$?
early_fired=$_alert_log
_SIM_NOW=$(( 1700000000 + 31 )); check_self_fence_isolation >/dev/null; rc31=$?
[[ $rc0 -eq 1 && $rc29 -eq 1 && -z "$early_fired" && $rc31 -eq 0 && "$_alert_log" == *"STANDBY SELF-FENCE — SWITCHED TO UNSTAKED"* ]] \
    && ok "(H1-a) held at 29s, fenced at 31s with the SWITCHED TO UNSTAKED page" \
    || bad "(H1-a) wrong (rc0=$rc0 rc29=$rc29 rc31=$rc31 alerts='$_alert_log')"

# ── (H1-d) the demote used the REAL give-back: identity flipped + episode reset + lockout armed ─
echo ""; echo "─── (H1-d) demote = REAL bounded give-back: identity flips, lockout + episode reset ───"
[[ "$(cat "$_ID_FILE")" == "$UNSTAKED_PUBKEY" && "$_alert_log" == *"GAVE BACK — unstaked ✅"* ]] \
    && ok "(H1-d1) real give_back_identity ran (identity=UNSTAKED, GAVE BACK ✅ page)" \
    || bad "(H1-d1) give-back not exercised (id=$(cat "$_ID_FILE") alerts='$_alert_log')"
[[ ${SELF_FENCE_DEMOTE_TIME:-0} -eq $(( 1700000000 + 31 )) && -z "$_delinq_window" && -z "$_last_confirmed_slot" ]] \
    && ok "(H1-d2) SELF_FENCE_DEMOTE_TIME armed at the demote instant; window + fence trackers reset" \
    || bad "(H1-d2) lockout/episode state wrong (t=$SELF_FENCE_DEMOTE_TIME window='$_delinq_window' slot='$_last_confirmed_slot')"

# ── (H1-b) no-answer: never without a baseline; fires with one ────────────────────────────────
echo ""; echo "─── (H1-b) no-answer arms ONLY with a baseline; fires at >= ${SELF_FENCE_NOANSWER_SECS}s ───"
reset_all; _MODE="noanswer"; _SIM_NOW=1700010000
for i in 0 10 20 40 80; do _SIM_NOW=$(( 1700010000 + i )); check_self_fence_isolation >/dev/null; done
nobase_alerts="$_alert_log"
[[ -z "$nobase_alerts" && "$(cat "$_ID_FILE")" == "$STAKED_PUBKEY" ]] \
    && ok "(H1-b1) 80s of silence on a FRESH start (no baseline) → no fence (validator-unreachable path)" \
    || bad "(H1-b1) fenced without a baseline (alerts='$nobase_alerts')"
reset_all; _MODE="slot"; _SIM_NOW=1700020000
check_self_fence_isolation >/dev/null                    # baseline
_MODE="noanswer"
_SIM_NOW=$(( 1700020000 + 5 ));  check_self_fence_isolation >/dev/null; rc_arm=$?   # silence starts
_SIM_NOW=$(( 1700020000 + 20 )); check_self_fence_isolation >/dev/null; rc_mid=$?
_SIM_NOW=$(( 1700020000 + 40 )); check_self_fence_isolation >/dev/null; rc_fire=$?  # 35s silent >= 30
[[ $rc_arm -eq 1 && $rc_mid -eq 1 && $rc_fire -eq 0 && "$_alert_log" == *"SWITCHED TO UNSTAKED"* ]] \
    && ok "(H1-b2) with a baseline the silence timer armed and fenced at ~35s" \
    || bad "(H1-b2) wrong (arm=$rc_arm mid=$rc_mid fire=$rc_fire alerts='$_alert_log')"

# ── (H1-c) N6 + B2 hysteresis on the standby port ─────────────────────────────────────────────
echo ""; echo "─── (H1-c) N6 own-vote-lag: dip does not clear; K clears; flap fires ───"
reset_all; _SIM_NOW=1700030000
healthy(){ _CLUSTER_MAX=100000; _OWN_LV=99995; _LOCAL_SLOT=100000; adv; }   # vlag 5  <= 32
overthr(){ _CLUSTER_MAX=100100; _OWN_LV=100000; _LOCAL_SLOT=100100; adv; }  # vlag 100 > 32
_selffence_votelag_baseline=1; _selffence_votelag_healthy=0
armed=$(( _SIM_NOW - 10 )); _selffence_votelag_since=$armed
healthy; check_self_fence_isolation >/dev/null
[[ "$_selffence_votelag_since" -eq "$armed" && "$_selffence_votelag_healthy" -eq 1 ]] \
    && ok "(H1-c1) ONE healthy dip kept the sustain timer armed (healthy=1 < K)" \
    || bad "(H1-c1) dip wiped the timer (since=$_selffence_votelag_since healthy=$_selffence_votelag_healthy)"
for _ in 1 2 3; do healthy; check_self_fence_isolation >/dev/null; done
[[ "$_selffence_votelag_since" -eq 0 ]] \
    && ok "(H1-c2) K=${SELF_FENCE_VOTE_LAG_RESET_CYCLES} consecutive healthy cycles cleared the timer" \
    || bad "(H1-c2) K healthy did not clear (since=$_selffence_votelag_since)"
_alert_log=""; echo "$STAKED_PUBKEY" > "$_ID_FILE"; CURRENT_IDENTITY="$STAKED_PUBKEY"
_selffence_votelag_baseline=1; _selffence_votelag_healthy=0
_selffence_votelag_since=$(( _SIM_NOW - SELF_FENCE_VOTE_LAG_SECS - 5 ))   # sustained past SECS
healthy; check_self_fence_isolation >/dev/null    # the flap dip
overthr; check_self_fence_isolation >/dev/null    # over threshold again → fires
[[ "$_alert_log" == *"SWITCHED TO UNSTAKED"* ]] \
    && ok "(H1-c3) flap (old timer + 1 dip + over-threshold) FIRED the standby N6 fence" \
    || bad "(H1-c3) flap evaded N6 (alerts='$_alert_log')"

# ── (H1-e) re-take lockout on the REAL attempt_takeover ──────────────────────────────────────
echo ""; echo "─── (H1-e) post-fence re-take lockout: refuses until ${SELF_FENCE_RETAKE_COOLDOWN}s, then takes ───"
reset_all
T_FENCE=1700040000; SELF_FENCE_DEMOTE_TIME=$T_FENCE
echo "$UNSTAKED_PUBKEY" > "$_ID_FILE"; CURRENT_IDENTITY="$UNSTAKED_PUBKEY"
# every OTHER gate green: window triggered, delay served, confirm ok, liveness frozen, no cooldown
_delinq_window="1111111111"; TAKEOVER_DELAY=60; TAKEOVER_COOLDOWN=0; LAST_TAKEOVER_TIME=0
EXTERNAL_CONFIRM_THROTTLE=0; _last_confirm_attempt=0; GOSSIP_VERIFY=false
VOTE_LIVENESS_VERIFY=true; _takeover_alert_sent=""
LAST_LIVENESS_ACTIVE_TIME=0
confirm_delinquency_external(){ return 0; }
staked_is_actively_voting(){ return 1; }   # frozen → fence clear
# v0.7 (B3 s4): pre-pin a back-dated first sample so (a) the hoisted A9a capture never runs a real
# sampler here and (b) the observation-span floor is satisfied — this case tests the H1.3 lockout,
# not the slice-4 span floor (test_blindness_is_life owns that).
_liveness_first_vote=100; _liveness_first_tip=1; _liveness_first_ts=$(( T_FENCE + 100 )); _last_blind_end=0
_takes=0; take_staked_identity(){ _takes=$((_takes+1)); return 0; }
FIRST_DELINQUENT_TIME=$(( T_FENCE + 10 ))
_SIM_NOW=$(( T_FENCE + 300 ))   # inside the lockout, delay long served
attempt_takeover; rc_locked=$?
takes_locked=$_takes
_SIM_NOW=$(( T_FENCE + 601 ))   # lockout expired
attempt_takeover; rc_free=$?
[[ $rc_locked -eq 1 && $takes_locked -eq 0 && $_takes -eq 1 ]] \
    && ok "(H1-e) locked out at +300s (no take) → took at +601s once the cooldown expired and gates re-passed" \
    || bad "(H1-e) lockout wrong (locked rc=$rc_locked takes=$takes_locked; after rc=$rc_free takes=$_takes)"

# ── (H1-f) NON-VACUOUS control: knobs zeroed/disabled → old 'hold forever unfenced' returns ───
echo ""; echo "─── (H1-f) control: fence knobs zeroed (same frozen inputs) → NO demote (old behavior) ───"
reset_all; _SIM_NOW=1700050000
SELF_FENCE_NOANSWER_SECS=0; SELF_FENCE_VOTE_LAG_SLOTS=0; SELF_FENCE_VOTE_LAG_SECS=0
SELF_FENCE_ISOLATION_SECS=99999   # effectively off (same inputs as H1-a otherwise)
check_self_fence_isolation >/dev/null
_SIM_NOW=$(( 1700050000 + 120 )); check_self_fence_isolation >/dev/null; rc_ctl=$?
[[ $rc_ctl -eq 1 && -z "$_alert_log" && "$(cat "$_ID_FILE")" == "$STAKED_PUBKEY" ]] \
    && ok "(H1-f) 120s frozen with the knobs zeroed → still staked, no page (proves H1-a/b/c bite)" \
    || bad "(H1-f) control fenced anyway (rc=$rc_ctl alerts='$_alert_log')"

# ── (H1-g) structural: MAIN LOOP dispatch + v0.6.8 baseline had nothing ───────────────────────
echo ""; echo "─── (H1-g) shipped STAKED branch dispatches the fence; v0.6.8 had zero ───"
n_dispatch=$(sed -n '/MAIN LOOP/,$p' "$STANDBY" | grep -c 'check_self_fence_isolation')
[[ $n_dispatch -ge 1 ]] && grep -A8 '======== STAKED (took over)' "$STANDBY" | grep -q 'STANDBY_SELF_FENCE' \
    && ok "(H1-g1) main-loop STAKED branch gates check_self_fence_isolation on STANDBY_SELF_FENCE" \
    || bad "(H1-g1) dispatch missing/ungated (n=$n_dispatch)"
if [[ -f "$V068" ]]; then
    v8=$(grep -c 'check_self_fence' "$V068")
    [[ $v8 -eq 0 ]] && ok "(H1-g2) v0.6.8 baseline: 0 check_self_fence references → H1 genuinely new (non-vacuous)" \
                    || bad "(H1-g2) v0.6.8 already had a standby self-fence ($v8)"
else
    ok "(H1-g2) v0.6.8 baseline not present to compare (skipped)"
fi

results_banner
