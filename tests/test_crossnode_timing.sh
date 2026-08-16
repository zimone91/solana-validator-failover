#!/bin/bash
# v0.6.6 (N1): composed CROSS-NODE timing safety test. Drives the REAL shipped PRIMARY
# check_self_fence_isolation and the REAL shipped STANDBY attempt_takeover on ONE simulated timeline
# (t0 = "PRIMARY stops participating") with the SHIPPED defaults (read from the scripts, not
# hardcoded), and asserts the anti-double-sign invariant:
#
#   the PRIMARY self-demotes STRICTLY BEFORE any spare would take the staked identity, with margin.
#
# Worst case (the auditor's): the delinquency head-start D is mocked to 0 (both clocks start at t0),
# the PRIMARY takes its SLOWEST self-fence path, and the STANDBY's external-confirm / liveness / take
# are otherwise instant — so the binding terms are exactly the config timers.
#
# Also asserts the new startup warning (check_crossnode_timing_safety) fires for an unsafe config and
# is silent for the shipped one. Non-vacuous: re-running the STANDBY sim with the OLD fast preset
# (TAKEOVER_DELAY=20) collapses the no-overlap assertion (the spare takes before the PRIMARY demotes).
#
# Method = the project's source-seam pattern: each node's script is sourced (truncated at MAIN LOOP)
# in its own subshell with date() -> a simulated clock and curl / notifiers mocked. No script edits.

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$PRIMARY" && -f "$STANDBY" ]] || { echo "  ❌ scripts not found"; exit 1; }
T0=1700000000   # non-zero clock origin (0 collides with the "timer unset" sentinel)

# ── REAL PRIMARY self-fence: echo "<noanswer_fire> <frozen_fire> <isolation_secs> <noanswer_secs>" ──
# (offsets from t0 at which the SHIPPED check_self_fence_isolation calls switch_to_unstaked)
sim_primary() { (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"; source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; LOCAL_RPC="http://mock"
  PRIMARY_SELF_FENCE=true; DRY_RUN=false; TG_ENABLED=false; SELF_FENCE_MAX_BEHIND=0
  date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
  mono_now() { date +%s; }   # v0.7 (Block 3): thread the fake clock into the mono helper
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}; alert(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  fired=-1
  switch_to_unstaked(){ fired=$(( _SIM_NOW - T0 )); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
  run_path() {   # $1 = noanswer | frozen ; sets `fired` (dynamic scope) to the fire offset
    _MODE="$1"; fired=-1; CURRENT_IDENTITY="$STAKED_PUBKEY"
    curl(){ local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue;}; shift; done
            case "$d" in *getSlot*) [[ "$_MODE" == noanswer ]] && return 7; printf '{"result":5000}'; return 0;; esac; return 7; }
    _last_confirmed_slot=5000; _last_confirmed_advance_ts=$T0; _selffence_noanswer_since=0   # healthy until t0, then isolated
    local t; for ((t=T0; t<=T0+200; t++)); do _SIM_NOW=$t; check_self_fence_isolation; [[ $fired -ge 0 ]] && break; done
  }
  run_path noanswer; na=$fired
  run_path frozen;   fr=$fired
  echo "$na $fr $SELF_FENCE_ISOLATION_SECS $SELF_FENCE_NOANSWER_SECS"
) ; }

# ── REAL STANDBY attempt_takeover: echo the take offset from t0 (D=0, fence clears as fast as possible) ──
sim_standby() {  # $1 = TAKEOVER_DELAY to use ; $2 = delinquency-detection onset from t0 (default 0 = D=0 worst case)
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"; source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; VOTE_PUBKEY="V1"
  TAKEOVER_DELAY="$1"; TAKEOVER_COOLDOWN=0; EXTERNAL_CONFIRM_THROTTLE=0
  GOSSIP_VERIFY=false; DRY_RUN=false
  date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
  mono_now() { date +%s; }   # v0.7 (Block 3): thread the fake clock into the mono helper
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}; alert(){ :;}; alert_info(){ :;}; alert_warn(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  confirm_delinquency_external(){ return 0; }                              # externally CONFIRMED delinquent
  get_staked_liveness_sample(){ echo "5000 $(( 100000 + _SIM_NOW - T0 ))"; }  # staked vote FROZEN, cluster tip ADVANCING
  took=-1
  take_staked_identity(){ took=$(( _SIM_NOW - T0 )); return 0; }
  FIRST_DELINQUENT_TIME=$(( T0 + ${2:-0} )); LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0   # D = $2 (default 0): when the spare first sees delinquency
  _delinq_window="1111111111"   # window already 7/10-triggered (the main loop gates attempt_takeover on this)
  _gossip_prefetched=false; _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _takeover_alert_sent=""
  local t; for ((t=T0; t<=T0+300; t++)); do _SIM_NOW=$t; attempt_takeover; [[ $took -ge 0 ]] && break; done
  echo "$took"
) ; }

echo "============================================="
echo "  Cross-node fail-over timing (v0.6.6 N1)"
echo "============================================="

# Read the SHIPPED standby knobs (defaults from the config block) + the real warning function.
SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"; source "$SRC"; rm -f "$SRC"
SHIPPED_TAKEOVER_DELAY="$TAKEOVER_DELAY"
SHIPPED_EXPECTED="$EXPECTED_PRIMARY_SELF_FENCE_SECS"
SHIPPED_MARGIN="$SELF_FENCE_MARGIN_SECS"

read -r P_NA P_FR P_ISO P_NOANS <<<"$(sim_primary)"
P_WORST=$(( P_NA > P_FR ? P_NA : P_FR ))
S_TAKE=$(sim_standby "$SHIPPED_TAKEOVER_DELAY")
GAP=$(( S_TAKE - P_WORST ))

echo ""
echo "─── shipped defaults: PRIMARY self-fence iso=${P_ISO}s/noans=${P_NOANS}s ; STANDBY TAKEOVER_DELAY=${SHIPPED_TAKEOVER_DELAY}s, EXPECTED=${SHIPPED_EXPECTED}s, margin=${SHIPPED_MARGIN}s ───"
echo "    PRIMARY self-demote: no-answer t0+${P_NA}s, frozen t0+${P_FR}s (worst t0+${P_WORST}s)"
echo "    STANDBY take staked: t0+${S_TAKE}s (D=0) ; gap=${GAP}s"

# (1) the core no-overlap-with-margin invariant on the REAL functions + SHIPPED defaults
[[ $P_WORST -lt $S_TAKE && $GAP -ge $SHIPPED_MARGIN ]] \
    && ok "(1) PRIMARY self-demotes strictly before STANDBY takes (gap ${GAP}s >= margin ${SHIPPED_MARGIN}s) — no overlap" \
    || bad "(1) overlap/insufficient margin: worst=${P_WORST}s take=${S_TAKE}s gap=${GAP}s margin=${SHIPPED_MARGIN}s"

# (2) the config invariant holds on the shipped values, and EXPECTED covers the PRIMARY's real worst case
[[ $SHIPPED_TAKEOVER_DELAY -ge $(( SHIPPED_EXPECTED + SHIPPED_MARGIN )) ]] \
    && ok "(2) shipped TAKEOVER_DELAY ${SHIPPED_TAKEOVER_DELAY}s >= EXPECTED ${SHIPPED_EXPECTED}s + margin ${SHIPPED_MARGIN}s" \
    || bad "(2) shipped TAKEOVER_DELAY ${SHIPPED_TAKEOVER_DELAY}s < EXPECTED+margin"
P_REAL_WORST=$(( P_ISO > P_NOANS ? P_ISO : P_NOANS ))
[[ $SHIPPED_EXPECTED -ge $P_REAL_WORST ]] \
    && ok "(2b) STANDBY EXPECTED_PRIMARY_SELF_FENCE_SECS ${SHIPPED_EXPECTED}s >= PRIMARY worst self-fence timer ${P_REAL_WORST}s (scripts in sync)" \
    || bad "(2b) EXPECTED ${SHIPPED_EXPECTED}s < PRIMARY worst self-fence timer ${P_REAL_WORST}s — cross-script drift!"

# (3) startup warning: silent at the shipped delay, fires below EXPECTED+margin
_warned=0; log_warn(){ :; }; alert_warn(){ _warned=1; }; log_info(){ :; }
EXPECTED_PRIMARY_SELF_FENCE_SECS="$SHIPPED_EXPECTED"; SELF_FENCE_MARGIN_SECS="$SHIPPED_MARGIN"
TAKEOVER_DELAY="$SHIPPED_TAKEOVER_DELAY"; _warned=0; check_crossnode_timing_safety; rc_safe=$?
[[ $rc_safe -eq 0 && $_warned -eq 0 ]] \
    && ok "(3) warning SILENT at shipped TAKEOVER_DELAY=${SHIPPED_TAKEOVER_DELAY}s" \
    || bad "(3) warning misbehaved at shipped delay (rc=$rc_safe warned=$_warned)"
TAKEOVER_DELAY=20; _warned=0; check_crossnode_timing_safety; rc_bad=$?
[[ $rc_bad -eq 1 && $_warned -eq 1 ]] \
    && ok "(3b) warning FIRES (+ alert_warn) at unsafe TAKEOVER_DELAY=20s" \
    || bad "(3b) warning did not fire at unsafe delay (rc=$rc_bad warned=$_warned)"

# (4) NON-VACUOUS: revert to the old fast preset (TAKEOVER_DELAY=20) → the spare takes BEFORE the
#     PRIMARY self-demotes → the (1) no-overlap assertion would FAIL.
S_TAKE_OLD=$(sim_standby 20)
GAP_OLD=$(( S_TAKE_OLD - P_WORST ))
echo ""
echo "─── non-vacuous control: OLD preset TAKEOVER_DELAY=20 → STANDBY take t0+${S_TAKE_OLD}s, gap ${GAP_OLD}s ───"
[[ ! ( $P_WORST -lt $S_TAKE_OLD && $GAP_OLD -ge $SHIPPED_MARGIN ) ]] \
    && ok "(4) with the old preset the no-overlap-with-margin assertion COLLAPSES (overlap [t0+${S_TAKE_OLD}s, t0+${P_WORST}s]) → test is non-vacuous" \
    || bad "(4) old preset did NOT produce overlap — test would be vacuous (take=${S_TAKE_OLD}s worst=${P_WORST}s)"

# ── (5) v0.6.7 (N6): EGRESS-ONLY case — own-vote-lag self-demote must beat a fast spare ──────────────
# Egress-only: the PRIMARY still RECEIVES blocks, so its LOCAL confirmed slot ADVANCES and getHealth reads
# fine — the frozen-slot/no-answer self-fence sub-checks are BLIND (this inverted the cross-node race live
# on rc.1). Only the v0.6.7 (N6) own-vote-lag check fires. Drive the REAL check_self_fence_isolation on a
# timeline where the tip advances ~RATE slots/s while our own lastVote is frozen (votes not landing), and
# require the demote to precede a CONSERVATIVE fast spare by the designed margin — measured against the
# fast spare (onset + TAKEOVER_DELAY), NOT merely the slow ~84s live run, so a fast spare can't invert it.
RATE_NUM=5; RATE_DEN=2   # ~2.5 slots/s (representative; own-vote lag = tip - own_lastVote grows at this rate)
SF_SLOTS=$(sed -n 's/^SELF_FENCE_VOTE_LAG_SLOTS=\([0-9][0-9]*\).*/\1/p' "$PRIMARY" | head -1)
SF_SECS=$(sed -n 's/^SELF_FENCE_VOTE_LAG_SECS=\([0-9][0-9]*\).*/\1/p' "$PRIMARY" | head -1)
SPARE_ONSET=8   # conservative fast-spare detect+window onset in egress-only (fast-detect ~6s @2.5sl/s + a window cycle)

sim_primary_egress() {  # $1 = SELF_FENCE_VOTE_LAG_SLOTS (0 = N6 disabled, for the non-vacuous control)
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"; source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; LOCAL_RPC="http://mock"
  PRIMARY_SELF_FENCE=true; DRY_RUN=false; TG_ENABLED=false
  SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_NOANSWER_SECS=0
  SELF_FENCE_VOTE_LAG_SLOTS="$1"; SELF_FENCE_VOTE_LAG_SECS="$SF_SECS"
  date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
  mono_now() { date +%s; }   # v0.7 (Block 3): thread the fake clock into the mono helper
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}; alert(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  S0=100000; OWN_LV=$(( S0 - 2 ))   # our own vote FROZEN at the last landed slot; the cluster advances from S0
  # v0.6.7 (N8): getVoteAccounts {processed} returns the cluster-max (another voter, ADVANCING) + our own
  # (FROZEN). N6 now lags own vs the same-payload cluster-max (not the getSlot tip). getSlot still advances
  # (inbound OK) so the frozen-slot check (1) clears and we reach the own-vote-lag check (3).
  curl(){ local d="" adv; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue;}; shift; done
    adv=$(( S0 + (_SIM_NOW - T0) * RATE_NUM / RATE_DEN ))
    case "$d" in
      *getVoteAccounts*) printf '{"result":{"current":[{"votePubkey":"CLUSTER","lastVote":%s}],"delinquent":[{"votePubkey":"V1","lastVote":%s}]}}' "$adv" "$OWN_LV"; return 0;;
      *getSlot*)         printf '{"result":%s}' "$adv"; return 0;;   # tip ADVANCES (inbound OK)
      *getHealth*)       printf '{"result":"ok"}'; return 0;;
    esac; return 7; }
  fired=-1
  switch_to_unstaked(){ fired=$(( _SIM_NOW - T0 )); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
  CURRENT_IDENTITY="$STAKED_PUBKEY"; _selffence_reset
  local t; for ((t=T0; t<=T0+200; t++)); do _SIM_NOW=$t; check_self_fence_isolation; [[ $fired -ge 0 ]] && break; done
  echo "$fired"
  ) ; }

P_EGRESS=$(sim_primary_egress "$SF_SLOTS")                 # WITH the N6 fix
P_EGRESS_OFF=$(sim_primary_egress 0)                       # non-vacuous control: N6 disabled
S_TAKE_EGRESS=$(sim_standby "$SHIPPED_TAKEOVER_DELAY" "$SPARE_ONSET")   # fast spare: FIRST_DELINQUENT = t0 + onset
EG_MARGIN=$(( S_TAKE_EGRESS - P_EGRESS ))
echo ""
echo "─── (5) egress-only (N6): tip advancing ~${RATE_NUM}/${RATE_DEN} slots/s, own vote frozen ; SELF_FENCE_VOTE_LAG=${SF_SLOTS}sl/${SF_SECS}s ───"
echo "    PRIMARY own-vote-lag self-demote: t0+${P_EGRESS}s ; conservative fast spare take: t0+${S_TAKE_EGRESS}s (onset ${SPARE_ONSET}s + TAKEOVER_DELAY ${SHIPPED_TAKEOVER_DELAY}s) ; margin ${EG_MARGIN}s"
[[ $P_EGRESS -ge 0 && $P_EGRESS -lt $S_TAKE_EGRESS && $EG_MARGIN -ge $SHIPPED_MARGIN ]] \
    && ok "(5) egress-only: PRIMARY self-demotes (t0+${P_EGRESS}s) BEFORE the fast spare (t0+${S_TAKE_EGRESS}s) with margin ${EG_MARGIN}s >= ${SHIPPED_MARGIN}s — inversion fixed" \
    || bad "(5) egress-only inversion / thin margin: demote=${P_EGRESS}s spare=${S_TAKE_EGRESS}s margin=${EG_MARGIN}s (need >= ${SHIPPED_MARGIN}s)"

# (5b) NON-VACUOUS: disable N6 → the PRIMARY NEVER self-demotes in egress-only (slot advances + RPC answers
#      → (1)/(2) blind) → the spare overtakes it → exactly the inversion measured live on rc.1.
[[ $P_EGRESS_OFF -lt 0 ]] \
    && ok "(5b) with N6 DISABLED the PRIMARY never self-demotes in egress-only (no fire in 200s) → spare inverts → (5) is non-vacuous" \
    || bad "(5b) N6-disabled control unexpectedly self-demoted at t0+${P_EGRESS_OFF}s — control invalid"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
