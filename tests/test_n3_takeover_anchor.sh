#!/bin/bash
# v0.6.7 (N3): the takeover delay must be anchored to the holder's LAST OBSERVED vote, not to
# first-delinquent. Drives the REAL shipped STANDBY attempt_takeover on a simulated timeline where the
# staked holder is delinquent BUT keeps voting (so the delay is consumed during the voting episode),
# then goes silent — and asserts the spare waits the FULL TAKEOVER_DELAY from the moment of ACTUAL
# silence, so the PRIMARY's self-fence (~30s) always completes first → no cross-node double-stake.
#
# Non-vacuous control: reverting the anchor to first-delinquent-only (sed: "now - takeover_anchor" ->
# "now - FIRST_DELINQUENT_TIME", i.e. the v0.6.6 line) makes the spare take ~one liveness interval
# after silence (overlap) — which the (1) assertion then FAILS to confirm. (4) asserts that collapse.
#
# harness: tests/lib/harness.sh — harness_clock_shims, harness_silence_sinks, ok/bad+banners
# (the sim's cut+source stays local: its revert mode sed-mutates the cut — moves onto mutate() in 4.2).

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
T0=1700000000        # non-zero clock origin (0 collides with the "timer unset" sentinel)
DELAY=60             # TAKEOVER_DELAY under test
FREEZE=100           # holder votes [t0, t0+FREEZE), then is silent — t0+FREEZE = ACTUAL silence
PRIMARY_FENCE=30     # PRIMARY self-fence worst case after silence (EXPECTED_PRIMARY_SELF_FENCE_SECS)

# Run the REAL attempt_takeover over the timeline.
#   $1 = "revert" to neuter the N3 anchor (back to first-delinquent-only), else "keep"
#   $2 = "vote"   : holder votes until t0+FREEZE then freezes (the N3 episode)
#        "silent" : holder already frozen from t0 (the NORMAL failover case)
# Echoes: "<take_offset_from_t0> <last_liveness_active_offset_or_-1>"
sim() {
  local mode_anchor="$1" mode_live="$2"
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
  if [[ "$mode_anchor" == "revert" ]]; then
    sed 's/now - takeover_anchor/now - FIRST_DELINQUENT_TIME/' "$SRC" > "$SRC.r" && mv "$SRC.r" "$SRC"
  fi
  source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; VOTE_PUBKEY="V1"
  TAKEOVER_DELAY="$DELAY"; TAKEOVER_COOLDOWN=0; EXTERNAL_CONFIRM_THROTTLE=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=10; VOTE_LIVENESS_EPSILON=2
  GOSSIP_VERIFY=false; DRY_RUN=false
  harness_clock_shims
  harness_silence_sinks
  confirm_delinquency_external(){ return 0; }                 # externally CONFIRMED delinquent
  if [[ "$mode_live" == "silent" ]]; then
    # FROZEN from t0: staked lastVote constant, cluster tip advancing → liveness never "active".
    get_staked_liveness_sample(){ echo "5000 $(( 100000 + _SIM_NOW - T0 ))"; }
  else
    # VOTING until t0+FREEZE (lastVote advances 1/s), then frozen; cluster tip always advancing.
    get_staked_liveness_sample(){
      local off=$(( _SIM_NOW - T0 )) v
      if [[ $off -lt $FREEZE ]]; then v=$(( 5000 + off )); else v=$(( 5000 + FREEZE )); fi
      echo "$v $(( 100000 + off ))"
    }
  fi
  took=-1; take_staked_identity(){ took=$(( _SIM_NOW - T0 )); return 0; }
  FIRST_DELINQUENT_TIME=$T0; LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0   # D=0: delinquency known at t0
  LAST_LIVENESS_ACTIVE_TIME=0
  _delinq_window="1111111111"   # window already 7/10-triggered (the main loop gates on this)
  _gossip_prefetched=false; _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _takeover_alert_sent=""
  local t; for ((t=T0; t<=T0+400; t++)); do _SIM_NOW=$t; attempt_takeover; [[ $took -ge 0 ]] && break; done
  local la=-1; [[ ${LAST_LIVENESS_ACTIVE_TIME:-0} -gt 0 ]] && la=$(( LAST_LIVENESS_ACTIVE_TIME - T0 ))
  echo "$took $la"
  ) ;
}

title_banner "N3 takeover-anchor (v0.6.7) — last-seen-voting"
echo ""
echo "─── timeline: FIRST_DELINQUENT at t0; holder VOTES [t0,t0+${FREEZE}s) then SILENT; TAKEOVER_DELAY=${DELAY}s ───"

read -r FIX_TAKE FIX_LA   <<<"$(sim keep   vote)"
read -r OLD_TAKE OLD_LA   <<<"$(sim revert vote)"
read -r NRM_TAKE NRM_LA   <<<"$(sim keep   silent)"

FIX_GAP=$(( FIX_TAKE - FREEZE ))   # seconds after ACTUAL silence that the spare takes
OLD_GAP=$(( OLD_TAKE - FREEZE ))
echo "    FIXED (N3 anchor):   take t0+${FIX_TAKE}s  → ${FIX_GAP}s after actual silence (last-active t0+${FIX_LA}s)"
echo "    REVERTED (v0.6.6):   take t0+${OLD_TAKE}s  → ${OLD_GAP}s after actual silence"
echo "    NORMAL (silent@t0):  take t0+${NRM_TAKE}s  (last-active offset ${NRM_LA})"
echo ""

# (1) CORE N3 invariant: after the holder's actual silence, the spare waits the FULL takeover delay.
[[ $FIX_TAKE -ge 0 && $FIX_GAP -ge $DELAY ]] \
  && ok "(1) FIXED waits the full delay from actual silence (${FIX_GAP}s >= TAKEOVER_DELAY ${DELAY}s)" \
  || bad "(1) FIXED took too soon after silence: gap=${FIX_GAP}s < ${DELAY}s (take t0+${FIX_TAKE}s)"

# (1b) the fix was actually EXERCISED: the holder was observed voting → the anchor moved off t0.
[[ $FIX_LA -gt 0 ]] \
  && ok "(1b) LAST_LIVENESS_ACTIVE_TIME advanced (t0+${FIX_LA}s) — anchor exercised, not vacuous" \
  || bad "(1b) LAST_LIVENESS_ACTIVE_TIME never set — the voting episode wasn't exercised"

# (2) cross-node consequence: PRIMARY self-fence (~${PRIMARY_FENCE}s after silence) completes BEFORE
#     the spare takes → no double-stake overlap.
[[ $FIX_GAP -gt $PRIMARY_FENCE ]] \
  && ok "(2) PRIMARY self-fence (~${PRIMARY_FENCE}s after silence) precedes the take (gap ${FIX_GAP}s) — no overlap" \
  || bad "(2) overlap risk: take is only ${FIX_GAP}s after silence, not clear of the ~${PRIMARY_FENCE}s self-fence"

# (3) NORMAL failover UNCHANGED: holder silent before STANDBY checks → liveness never active →
#     LAST_LIVENESS_ACTIVE_TIME stays 0 → takes at exactly FIRST_DELINQUENT + TAKEOVER_DELAY (as v0.6.6).
[[ $NRM_TAKE -eq $DELAY && $NRM_LA -eq -1 ]] \
  && ok "(3) NORMAL case unchanged: take at first-delinquent+${DELAY}s, anchor inert (LAST stayed 0)" \
  || bad "(3) NORMAL case drifted: take t0+${NRM_TAKE}s (expected ${DELAY}s), LAST offset ${NRM_LA} (expected -1)"

# (4) NON-VACUOUS: with the anchor reverted to first-delinquent-only, the spare takes BEFORE the full
#     delay re-elapses from silence (overlap) → the (1) invariant would FAIL. Proves the test bites.
[[ $OLD_TAKE -ge 0 && $OLD_GAP -lt $DELAY ]] \
  && ok "(4) REVERTED anchor takes only ${OLD_GAP}s after silence (< ${DELAY}s) → (1) collapses → non-vacuous" \
  || bad "(4) REVERTED anchor did NOT take early (gap=${OLD_GAP}s) — test would be vacuous"

results_banner
