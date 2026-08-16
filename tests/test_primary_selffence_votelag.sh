#!/bin/bash
# v0.6.7 (N6 + rc.3 N8/N9): PRIMARY own-vote-lag self-fence. Drives the SHIPPED check_self_fence_isolation
# on an egress-only timeline (LOCAL confirmed slot ADVANCES, so the frozen-slot/no-answer checks stay
# blind) and asserts the own-vote-lag sub-check (3). v0.6.7 N8: lag is now own lastVote vs the SAME-PAYLOAD
# cluster-max lastVote from ONE LOCAL getVoteAccounts {commitment:"processed"} (no cross-call/cross-
# commitment skew). N9: the tracker re-arms only AFTER a successful demote (failed demote retries).
#   (VL-e)  DRY_RUN + sustained lag                          → log only, no swap (REAL switch_to_unstaked)
#   (VL-a)  baseline + lag > SLOTS sustained >= SECS         → self-fence + URGENT alert, demote FIRST (N2)
#   (VL-b)  lag <= SLOTS (own tracks cluster-max)            → NO fence; sets healthy baseline, clears timer
#   (VL-c)  baseline + over threshold, timer not tripped     → NO fence; timer armed
#   (VL-d)  NO baseline + over threshold                     → NO fence, timer NOT started (fresh/catch-up)
#   (VL-f)  own lastVote UNREADABLE                          → NO fence (held)
#   (VL-g)  ZERO external (T2/T3) calls                      → LOCAL signal only
#   (N8-healthy) own tracks cluster-max for many cycles      → NEVER false-fires
#   (N8-skew)    own ~36 behind the CONFIRMED tip but ~3 behind the PROCESSED cluster-max → NO fire;
#                non-vacuous: revert the lag source (cluster_max→slot) and it DOES fire (the old bug)
#   (N9-retry)   demote FAILS                                → timer stays armed, re-attempts next cycle
#   (N9-storm)   demote SUCCEEDS (incl. DRY_RUN)             → reset-after → fires once, no re-fire storm

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
[[ -f "$PRIMARY" ]] || { echo "  ❌ primary not found at $PRIMARY"; exit 1; }

SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"; rm -f "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock

STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_NOANSWER_SECS=0
SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20
TG_ENABLED=false
log_info()  { echo "      [INFO] $*"; }
log_warn()  { echo "      [WARN] $*"; }
send_telegram() { return 0; }
send_webhook()  { :; }

# curl mock: getSlot = LOCAL confirmed tip; getVoteAccounts {processed} = a cluster reference voter at
# _CLUSTER_MAX plus our own account at _OWN_LV (in current|delinquent per _OWN_ARRAY, or absent when
# _OWN_PRESENT=0). LOCAL only — any external (T2/T3) call is a bug. vlag = cluster_max - own_lv.
_ext_calls=0
_LOCAL_SLOT=100000
_CLUSTER_MAX=100000    # max lastVote across the processed getVoteAccounts payload (other voters)
_OWN_LV=99995          # our own vote account lastVote
_OWN_PRESENT=1         # 0 = own account absent from getVoteAccounts (unreadable)
_OWN_ARRAY=current     # current | delinquent
_va_json() {
    local cur='{"votePubkey":"ClusterVoter11111111111111111111111111","lastVote":'"$_CLUSTER_MAX"'}' del=''
    if [[ "$_OWN_PRESENT" -eq 1 ]]; then
        local own='{"votePubkey":"'"$VOTE_PUBKEY"'","lastVote":'"$_OWN_LV"'}'
        if [[ "$_OWN_ARRAY" == "delinquent" ]]; then del="$own"; else cur="$cur,$own"; fi
    fi
    printf '{"jsonrpc":"2.0","result":{"current":[%s],"delinquent":[%s]},"id":1}' "$cur" "$del"
}
curl() {
    local data="" url=""
    while [[ $# -gt 0 ]]; do case "$1" in -d) data="$2"; shift 2; continue ;; http*) url="$1" ;; esac; shift; done
    case "$url" in "$TIER2_RPC"|"$TIER3_RPC") _ext_calls=$((_ext_calls+1)) ;; esac
    case "$data" in
        *getVoteAccounts*) _va_json; return 0 ;;
        *getSlot*)   [[ -z "$_LOCAL_SLOT" ]] && return 7; printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$_LOCAL_SLOT"; return 0 ;;
        *getHealth*) printf '{"jsonrpc":"2.0","result":"ok","id":1}'; return 0 ;;
    esac
    return 7
}
NOW() { date +%s; }
adv() { _last_confirmed_slot=$(( _LOCAL_SLOT - 50 )); _last_confirmed_advance_ts=$(NOW); }   # slot advancing → check (1) clears

echo "============================================="
echo "  PRIMARY own-vote-lag self-fence (v0.6.7 N6/N8/N9)"
echo "============================================="

# ── (VL-e) FIRST with the REAL switch_to_unstaked → verify DRY_RUN log-only ───────────────────
echo ""; echo "─── (VL-e) DRY_RUN + sustained lag → log only, no swap (real switch_to_unstaked) ───"
DRY_RUN=true; CURRENT_IDENTITY="$STAKED_PUBKEY"
_CLUSTER_MAX=100100; _OWN_LV=100000; _OWN_ARRAY=delinquent; _LOCAL_SLOT=100100; adv   # lag = 100 > 32
_selffence_votelag_baseline=1; _selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 5 ))
out=$(check_self_fence_isolation 2>&1); rc=$?
echo "$out" | grep -qi "DRY RUN" && [[ $rc -eq 0 && "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] \
    && ok "(VL-e) DRY_RUN vote-lag self-fence logged 'would switch', identity unchanged (no swap)" \
    || bad "(VL-e) DRY_RUN did not log-only (rc=$rc identity=$CURRENT_IDENTITY)"

# ── Mock switch_to_unstaked + alert to observe fence decisions and the demote-before-alert order ──
_fence_calls=0; _fence_reason=""; _alert_calls=0; _alert_status=""; _before_alert=-1
switch_to_unstaked() { _fence_calls=$((_fence_calls+1)); _fence_reason="$1"; _before_alert=$_alert_calls; CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
alert() { _alert_calls=$((_alert_calls+1)); _alert_status="$3"; }
prep() { _fence_calls=0; _fence_reason=""; _alert_calls=0; _before_alert=-1; CURRENT_IDENTITY="$STAKED_PUBKEY"; DRY_RUN=false; _OWN_PRESENT=1; _OWN_ARRAY=current; }

echo ""; echo "─── (VL-a) baseline + lag > SLOTS sustained >= SECS → self-fence + alert (demote FIRST) ───"
prep; _CLUSTER_MAX=100100; _OWN_LV=100000; _OWN_ARRAY=delinquent; _LOCAL_SLOT=100100; adv   # lag 100 > 32
_selffence_votelag_baseline=1; _selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 5 ))
check_self_fence_isolation; rc=$?
[[ $rc -eq 0 && "$_fence_calls" -eq 1 && "$_alert_calls" -ge 1 && "$_before_alert" -eq 0 ]] \
    && ok "(VL-a) sustained lag → switch_to_unstaked + urgent alert, demote BEFORE alert (N2 order)" \
    || bad "(VL-a) did not fence/alert/order correctly (rc=$rc calls=$_fence_calls alerts=$_alert_calls before=$_before_alert)"

echo ""; echo "─── (VL-b) lag <= SLOTS (own tracks cluster-max) → NO fence; healthy baseline set, timer cleared ───"
prep; _CLUSTER_MAX=100000; _OWN_LV=99995; _LOCAL_SLOT=100000; adv   # lag 5 <= 32
_selffence_votelag_baseline=""; _selffence_votelag_since=0
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 && "$_selffence_votelag_baseline" == "1" && "$_selffence_votelag_since" -eq 0 ]] \
    && ok "(VL-b) healthy lag → no fence; baseline established, timer 0" \
    || bad "(VL-b) misbehaved (rc=$rc calls=$_fence_calls baseline=$_selffence_votelag_baseline since=$_selffence_votelag_since)"

echo ""; echo "─── (VL-c) baseline + lag > SLOTS but timer not tripped → NO fence; timer armed ───"
prep; _CLUSTER_MAX=100100; _OWN_LV=100000; _OWN_ARRAY=delinquent; _LOCAL_SLOT=100100; adv   # lag 100
_selffence_votelag_baseline=1; _selffence_votelag_since=0
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 && "$_selffence_votelag_since" -ne 0 ]] \
    && ok "(VL-c) over-threshold but < timer → no fence, timer armed (since=${_selffence_votelag_since})" \
    || bad "(VL-c) misbehaved (rc=$rc calls=$_fence_calls since=$_selffence_votelag_since)"

echo ""; echo "─── (VL-d) NO baseline + lag > SLOTS → NO fence, timer NOT started (fresh start / catch-up) ───"
prep; _CLUSTER_MAX=100100; _OWN_LV=100000; _OWN_ARRAY=delinquent; _LOCAL_SLOT=100100; adv   # lag 100
_selffence_votelag_baseline=""; _selffence_votelag_since=0
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 && "$_selffence_votelag_since" -eq 0 ]] \
    && ok "(VL-d) no baseline + lag → no fence, no timer (a catching-up node is not isolation)" \
    || bad "(VL-d) started the timer / fenced without a baseline (rc=$rc calls=$_fence_calls since=$_selffence_votelag_since)"

echo ""; echo "─── (VL-f) own lastVote UNREADABLE (sustained timer set) → NO fence (held) ───"
prep; _OWN_PRESENT=0; _CLUSTER_MAX=100100; _LOCAL_SLOT=100100; adv
_selffence_votelag_baseline=1; _selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 5 ))
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 ]] \
    && ok "(VL-f) unreadable own lastVote → no fence (a blip cannot fire on its own)" \
    || bad "(VL-f) fenced on an unreadable own vote (rc=$rc calls=$_fence_calls)"

echo ""; echo "─── (VL-g) the vote-lag check makes ZERO external (T2/T3) calls (LOCAL only) ───"
[[ "$_ext_calls" -eq 0 ]] \
    && ok "(VL-g) zero external calls across all cases → a broken egress / external outage can never trigger it" \
    || bad "(VL-g) the check touched an external RPC ${_ext_calls}x — external state could trigger it!"

# ── (N8) commitment/freshness: own tracks the cluster-max → no false-fire on a healthy node ────
echo ""; echo "─── (N8-healthy) own tracks cluster-max across many cycles → NEVER false-fires ───"
prep; _selffence_votelag_baseline=""; _selffence_votelag_since=0; _OWN_ARRAY=current
_n8_fired=0
for i in $(seq 0 40); do
    _CLUSTER_MAX=$(( 100000 + i*2 )); _OWN_LV=$(( _CLUSTER_MAX - 3 )); _LOCAL_SLOT=$(( _CLUSTER_MAX ))   # lag 3 every cycle
    adv; check_self_fence_isolation; [[ "$_fence_calls" -gt 0 ]] && { _n8_fired=1; break; }
done
[[ $_n8_fired -eq 0 ]] \
    && ok "(N8-healthy) own lastVote tracks cluster-max (lag 3) for 41 cycles → never false-fires" \
    || bad "(N8-healthy) false-fired on a healthy node (the commitment-mismatch bug)"

echo ""; echo "─── (N8-skew) own ~36 behind the CONFIRMED tip but ~3 behind the PROCESSED cluster-max → NO fire ───"
prep; _OWN_ARRAY=delinquent
_CLUSTER_MAX=100003; _OWN_LV=100000; _LOCAL_SLOT=100036; adv   # processed lag 3 (healthy); confirmed-tip lag 36 (the old skew)
_selffence_votelag_baseline=1; _selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 5 ))
check_self_fence_isolation; rc=$?
old_lag=$(( _LOCAL_SLOT - _OWN_LV ))   # what the rc.2 (confirmed-tip vs own) code computed
[[ $rc -eq 1 && "$_fence_calls" -eq 0 && $old_lag -gt $SELF_FENCE_VOTE_LAG_SLOTS ]] \
    && ok "(N8-skew) fixed code (processed cluster-max, lag 3) → NO fire, though the old confirmed-tip lag (${old_lag}) would trip >${SELF_FENCE_VOTE_LAG_SLOTS}" \
    || bad "(N8-skew) misbehaved (rc=$rc calls=$_fence_calls old_lag=$old_lag)"

# Non-vacuous: revert the lag SOURCE (cluster_max → slot, the rc.2 form) and confirm it FIRES on this data.
_n8rev=$(
  set +e
  SRC2=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" | sed 's/cluster_max - own_lv/slot - own_lv/' > "$SRC2"; source "$SRC2"; rm -f "$SRC2"
  mono_now() { date +%s; }   # v0.7 (Block 3): re-sourced daemon redefines the helper — re-shim to the scenario clock
  STAKED_PUBKEY="S"; UNSTAKED_PUBKEY="U"; VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
  LOCAL_RPC="http://mock"; DRY_RUN=false; CURRENT_IDENTITY="$STAKED_PUBKEY"; TG_ENABLED=false
  SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_NOANSWER_SECS=0
  SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20
  log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}; alert(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  # if/elif (not case) — a case pattern's ')' inside $(...) command substitution trips bash 3.2.
  curl(){ local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue;}; shift; done
    if [[ "$d" == *getVoteAccounts* ]]; then printf '{"result":{"current":[{"votePubkey":"X","lastVote":100003}],"delinquent":[{"votePubkey":"VotePubkey1111111111111111111111111111111","lastVote":100000}]}}'; return 0
    elif [[ "$d" == *getSlot* ]]; then printf '{"result":100036}'; return 0
    elif [[ "$d" == *getHealth* ]]; then printf '{"result":"ok"}'; return 0
    fi; return 7; }
  _c=0; switch_to_unstaked(){ _c=1; CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
  _last_confirmed_slot=99986; _last_confirmed_advance_ts=$(date +%s)
  _selffence_votelag_baseline=1; _selffence_votelag_since=$(( $(date +%s) - 25 ))
  check_self_fence_isolation >/dev/null 2>&1
  echo "$_c"
)
[[ "$_n8rev" == "1" ]] \
    && ok "(N8-skew control) reverting the lag source to the confirmed-tip (slot − own) DOES fire on the same data → the N8 test is non-vacuous" \
    || bad "(N8-skew control) reverted code did not fire (got '${_n8rev}') — test would be vacuous"

# ── (N9) failed demote must RETRY; success/DRY_RUN must NOT re-fire storm ──────────────────────
echo ""; echo "─── (N9-retry) demote FAILS → timer stays armed → re-attempts next cycle ───"
_failcalls=0
switch_to_unstaked() { _failcalls=$((_failcalls+1)); return 1; }   # demote FAILS (node stays staked)
prep_n9() { CURRENT_IDENTITY="$STAKED_PUBKEY"; DRY_RUN=false; _OWN_PRESENT=1; _OWN_ARRAY=delinquent; _CLUSTER_MAX=100100; _OWN_LV=100000; _LOCAL_SLOT=100100; adv; }
_selffence_votelag_baseline=1; _selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 5 ))
prep_n9; check_self_fence_isolation    # cycle 1: fire → switch FAILS → timer NOT reset
prep_n9; check_self_fence_isolation    # cycle 2: lag still > threshold, timer still armed → fire again
[[ "$_failcalls" -ge 2 ]] \
    && ok "(N9-retry) failed demote keeps the timer armed → re-attempts ($_failcalls switch calls over 2 cycles, not one-and-done)" \
    || bad "(N9-retry) failed demote did not retry ($_failcalls calls)"

echo ""; echo "─── (N9-storm) demote SUCCEEDS (incl. DRY_RUN) → reset-after → fires once, no re-fire storm ───"
_okcalls=0
switch_to_unstaked() { _okcalls=$((_okcalls+1)); return 0; }   # demote SUCCEEDS (DRY_RUN logs + returns 0)
_selffence_votelag_baseline=1; _selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 5 ))
prep_n9; check_self_fence_isolation    # cycle 1: fire → switch OK → _selffence_reset (baseline cleared)
prep_n9; check_self_fence_isolation    # cycle 2: lag > threshold but baseline="" → no re-arm → no fire
prep_n9; check_self_fence_isolation    # cycle 3: same → no fire
[[ "$_okcalls" -eq 1 ]] \
    && ok "(N9-storm) successful/DRY_RUN demote resets-after → fires once, no re-fire storm ($_okcalls call over 3 cycles)" \
    || bad "(N9-storm) re-fire storm or no fire ($_okcalls calls)"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
