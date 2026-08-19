#!/bin/bash
# v0.6.3 (Block 3): PRIMARY self-fence ("vote lease"). Drives the SHIPPED check_self_fence_isolation
# and asserts the acceptance matrix:
#   (a) LOCAL confirmed slot frozen >= ISOLATION_SECS        → self-fence (switch_to_unstaked)
#   (b) external RPC down / any external state               → NO self-fence (it makes ZERO external
#                                                              calls — LOCAL signals only)
#   (c) LOCAL confirmed slot advancing                       → NO self-fence
#   (d) brief LOCAL RPC no-answer (< NOANSWER threshold)     → NO self-fence (validator-unreachable path)
#   (e) DRY_RUN                                              → log only, no swap (REAL switch_to_unstaked)
#   plus the optional getHealth "behind > N" demote, and getHealth no-answer → no fence.
# v0.6.5 (F1) no-answer isolation timer (SELF_FENCE_NOANSWER_SECS):
#   (e2)  DRY_RUN + continuous no-answer >= threshold        → log only, no swap (REAL switch)
#   (F1a) baseline + CONTINUOUS no-answer >= threshold       → self-fence + URGENT alert FIRST
#   (F1b) baseline + brief no-answer (< threshold)           → NO self-fence (timer armed, not tripped)
#   (F1c) NO baseline + no-answer                            → NO self-fence, timer NOT started
#   (F1d) successful read                                    → clears the no-answer timer
# v0.6.6 (N2) demote-before-alert ordering:
#   (N2)  no-answer fire → switch_to_unstaked runs BEFORE any external alert (notifiers mocked to
#         sleep): 0 notifier calls complete before the demote, 0 added latency. A negative control
#         replays the old alert-first order to prove the measurement is non-vacuous (observes 2).
# Non-vacuous: (a) fires only because the frozen-slot timer trips; (F1a) only because the no-answer
# timer trips; (c)/(d)/(F1b)/(F1c) prove it does NOT fire when advancing, briefly silent, or fresh.

# harness: tests/lib/harness.sh — ok/bad+banners, paths. Cut + printing log shadows + `date +%s`
# clock + the N2 subshell's sink block stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock
rm -f "$SRC"

STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=0
TG_ENABLED=false
log_info()  { echo "      [INFO] $*"; }
log_warn()  { echo "      [WARN] $*"; }
send_telegram() { return 0; }
send_webhook()  { :; }

# curl mock: the self-fence must only ever touch LOCAL_RPC. Any external (T2/T3) call is a bug.
_ext_calls=0
_LOCAL_SLOT=1000
_LOCAL_HEALTH='{"jsonrpc":"2.0","result":"ok","id":1}'
curl() {
    local data="" url=""
    while [[ $# -gt 0 ]]; do case "$1" in -d) data="$2"; shift 2; continue ;; http*) url="$1" ;; esac; shift; done
    case "$url" in "$TIER2_RPC"|"$TIER3_RPC") _ext_calls=$((_ext_calls+1)) ;; esac
    case "$data" in
        *getSlot*)   [[ -z "$_LOCAL_SLOT"   ]] && return 7; printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$_LOCAL_SLOT"; return 0 ;;
        *getHealth*) [[ -z "$_LOCAL_HEALTH" ]] && return 7; printf '%s' "$_LOCAL_HEALTH"; return 0 ;;
    esac
    return 7
}

title_banner "PRIMARY self-fence (v0.6.3 Block 3)"

# ── (e) FIRST, with the REAL switch_to_unstaked, to verify the DRY_RUN log-only behavior ──────
echo ""; echo "─── (e) DRY_RUN → log only, no swap (real switch_to_unstaked) ───"
DRY_RUN=true; CURRENT_IDENTITY="$STAKED_PUBKEY"
_LOCAL_SLOT=2000; _last_confirmed_slot=2000; _last_confirmed_advance_ts=$(( $(date +%s) - SELF_FENCE_ISOLATION_SECS - 5 ))
out=$(check_self_fence_isolation 2>&1); rc=$?
echo "$out" | grep -q "DRY RUN" && [[ $rc -eq 0 && "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] \
    && ok "(e) DRY_RUN self-fence logged 'would switch', identity unchanged (no swap)" \
    || bad "(e) DRY_RUN did not log-only (rc=$rc identity=$CURRENT_IDENTITY)"

# ── (e2) F1: DRY_RUN + continuous no-answer >= threshold → log only, no swap (real switch) ─────
echo ""; echo "─── (e2) F1: DRY_RUN no-answer >= threshold → log only, no swap ───"
DRY_RUN=true; CURRENT_IDENTITY="$STAKED_PUBKEY"; SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_NOANSWER_SECS=60
_LOCAL_SLOT=""; _last_confirmed_slot=1000
_selffence_noanswer_since=$(( $(date +%s) - SELF_FENCE_NOANSWER_SECS - 5 ))
out=$(check_self_fence_isolation 2>&1); rc=$?
echo "$out" | grep -q "DRY RUN" && [[ $rc -eq 0 && "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]] \
    && ok "(e2) F1 DRY_RUN no-answer self-fence logged 'would switch', identity unchanged (no swap)" \
    || bad "(e2) F1 DRY_RUN no-answer did not log-only (rc=$rc identity=$CURRENT_IDENTITY)"

# ── Now mock switch_to_unstaked to observe fence decisions; LIVE mode ─────────────────────────
_fence_calls=0; _fence_reason=""
switch_to_unstaked() { _fence_calls=$((_fence_calls+1)); _fence_reason="$1"; CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
prep() { _fence_calls=0; _fence_reason=""; CURRENT_IDENTITY="$STAKED_PUBKEY"; DRY_RUN=false; SELF_FENCE_MAX_BEHIND=0; }
NOW() { date +%s; }

echo ""; echo "─── (a) confirmed slot frozen >= ISOLATION_SECS → self-fence ───"
prep; _LOCAL_SLOT=1000; _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - SELF_FENCE_ISOLATION_SECS - 5 ))
check_self_fence_isolation; rc=$?
[[ $rc -eq 0 && "$_fence_calls" -eq 1 ]] && ok "frozen ${SELF_FENCE_ISOLATION_SECS}s+ → switch_to_unstaked (reason: ${_fence_reason:0:40}...)" \
                                         || bad "(a) did not self-fence (rc=$rc calls=$_fence_calls)"

echo ""; echo "─── (c) confirmed slot advancing → NO self-fence ───"
prep; _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - SELF_FENCE_ISOLATION_SECS - 5 )); _LOCAL_SLOT=1050
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 && "$_last_confirmed_slot" == "1050" ]] \
    && ok "advancing slot → no fence, tracker advanced to 1050" \
    || bad "(c) misbehaved (rc=$rc calls=$_fence_calls slot=$_last_confirmed_slot)"

echo ""; echo "─── (d) LOCAL RPC unreachable (getSlot no answer) → NO self-fence ───"
prep; _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - SELF_FENCE_ISOLATION_SECS - 5 )); _LOCAL_SLOT=""
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 ]] && ok "local getSlot no answer → unreachable path, NO self-fence" \
                                         || bad "(d) self-fenced on an unreachable local RPC (rc=$rc calls=$_fence_calls)"

echo ""; echo "─── (b) external RPC never queried by the self-fence (LOCAL signals only) ───"
prep; _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1010
check_self_fence_isolation >/dev/null
[[ "$_ext_calls" -eq 0 ]] && ok "self-fence made ZERO external (T2/T3) calls across all cases → an external outage can never trigger it" \
                          || bad "(b) self-fence touched an external RPC ${_ext_calls}x — external state could trigger it!"

# ── Optional getHealth "behind > N" demote ───────────────────────────────────────────────────
echo ""; echo "─── getHealth behind > MAX_BEHIND (slot advancing) → self-fence ───"
prep; SELF_FENCE_MAX_BEHIND=150
_last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1050   # advancing → getSlot path clear
_LOCAL_HEALTH='{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by 200 slots","data":{"numSlotsBehind":200}},"id":1}'
check_self_fence_isolation; rc=$?
[[ $rc -eq 0 && "$_fence_calls" -eq 1 ]] && ok "getHealth behind 200 > 150 → self-fence (faster partial-partition)" \
                                         || bad "getHealth demote did not fire (rc=$rc calls=$_fence_calls)"

echo ""; echo "─── getHealth no answer (slot advancing) → NO self-fence ───"
prep; SELF_FENCE_MAX_BEHIND=150
_last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1050; _LOCAL_HEALTH=""
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 ]] && ok "getHealth no answer → unreachable, NO self-fence" \
                                         || bad "getHealth no-answer self-fenced (rc=$rc calls=$_fence_calls)"

# ── (F1) no-answer isolation timer — mocked switch_to_unstaked + a recording alert ─────────────
echo ""; echo "─── F1: no-answer isolation timer (SELF_FENCE_NOANSWER_SECS) ───"
_alert_calls=0; _alert_status=""
alert() { _alert_calls=$((_alert_calls+1)); _alert_status="$3"; }   # urgent pre-alert recorder
SELF_FENCE_NOANSWER_SECS=60

# (F1a) baseline + continuous no-answer >= threshold → self-fence + urgent alert FIRST
prep; _alert_calls=0
_LOCAL_SLOT=""; _last_confirmed_slot=1000; _selffence_noanswer_since=$(( $(NOW) - SELF_FENCE_NOANSWER_SECS - 5 ))
check_self_fence_isolation; rc=$?
[[ $rc -eq 0 && "$_fence_calls" -eq 1 && "$_alert_calls" -ge 1 ]] \
    && ok "(F1a) continuous no-answer ${SELF_FENCE_NOANSWER_SECS}s+ → switch_to_unstaked + urgent alert (${_alert_status:0:34})" \
    || bad "(F1a) did not self-fence/alert on continuous no-answer (rc=$rc calls=$_fence_calls alerts=$_alert_calls)"

# (F1b) baseline + brief no-answer (< threshold) → NO self-fence, timer armed
prep; _alert_calls=0
_LOCAL_SLOT=""; _last_confirmed_slot=1000; _selffence_noanswer_since=0
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 && "$_selffence_noanswer_since" -ne 0 && "$_alert_calls" -eq 0 ]] \
    && ok "(F1b) brief no-answer (<threshold) → no fence, timer armed (since=${_selffence_noanswer_since})" \
    || bad "(F1b) misbehaved on brief no-answer (rc=$rc calls=$_fence_calls since=$_selffence_noanswer_since alerts=$_alert_calls)"

# (F1c) NO baseline + no-answer → NO self-fence, timer NOT started (fresh start / catching up)
prep; _alert_calls=0
_LOCAL_SLOT=""; _last_confirmed_slot=""; _selffence_noanswer_since=0
check_self_fence_isolation; rc=$?
[[ $rc -eq 1 && "$_fence_calls" -eq 0 && "$_selffence_noanswer_since" -eq 0 && "$_alert_calls" -eq 0 ]] \
    && ok "(F1c) no baseline + no-answer → no fence, no timer (fresh start is not isolation)" \
    || bad "(F1c) started the timer / fenced without a baseline (rc=$rc calls=$_fence_calls since=$_selffence_noanswer_since)"

# (F1d) a successful read clears a running no-answer timer
prep
_selffence_noanswer_since=$(( $(NOW) - 30 )); _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1050
check_self_fence_isolation; rc=$?
[[ "$_selffence_noanswer_since" -eq 0 && "$_fence_calls" -eq 0 ]] \
    && ok "(F1d) successful slot read clears the no-answer timer" \
    || bad "(F1d) successful read did not reset the no-answer timer (since=$_selffence_noanswer_since calls=$_fence_calls)"

# ── (N2) v0.6.6: the demote runs BEFORE any external alert in the no-answer branch ─────────────
# Re-source fresh so alert() is the REAL shipped function (the F1 block above mocked it to a recorder).
# Mock the notifiers to SLEEP (endpoints hanging — the exact bad case) and assert switch_to_unstaked
# fires with ZERO notifier calls completed before it and ZERO added latency: the safety demote must
# never wait on notification I/O. A negative control replays the OLD (alert-first) order to prove the
# measurement is non-vacuous (it would observe 2 notifier calls before the demote).
echo ""; echo "─── (N2) no-answer branch: demote BEFORE external alert (notifiers mocked to sleep) ───"
_n2=$(
  set +e
  SRC2=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC2"; source "$SRC2"; rm -f "$SRC2"
  mono_now() { date +%s; }   # v0.7 (Block 3): re-sourced daemon redefines the helper — re-shim to the scenario clock
  STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
  UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
  LOCAL_RPC="http://mock-local"; DRY_RUN=false; CURRENT_IDENTITY="$STAKED_PUBKEY"
  SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=0
  TG_ENABLED=true; TG_BOT_TOKEN="x"; TG_CHAT_ID="y"; WEBHOOK_URL="http://hook"
  log(){ :; }; log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
  _notify_done=0
  send_telegram(){ sleep 1; _notify_done=$((_notify_done+1)); return 0; }   # endpoint hangs ~1s
  send_webhook(){  sleep 1; _notify_done=$((_notify_done+1)); }             # endpoint hangs ~1s
  _switch_called=0; _before=-1; _elapsed=-1
  switch_to_unstaked(){ _switch_called=1; _before=$_notify_done; _elapsed=$(( SECONDS - _t0 )); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
  curl(){ return 7; }   # LOCAL getSlot silent (no-answer)
  _last_confirmed_slot=1000; _selffence_noanswer_since=$(( $(date +%s) - SELF_FENCE_NOANSWER_SECS - 5 ))
  _t0=$SECONDS
  check_self_fence_isolation >/dev/null 2>&1; rc=$?
  echo "POS rc=$rc switch=$_switch_called before=$_before elapsed=$_elapsed"
  # negative control: replay the OLD alert-first order with the SAME mocks → expect before=2
  _notify_done=0; _switch_called=0; _before=-1; _t0=$SECONDS
  alert "x" "y" "z"; switch_to_unstaked "x"
  echo "NEG before=$_before"
)
_pos=$(sed -n 's/^POS //p' <<<"$_n2"); _neg=$(sed -n 's/^NEG //p' <<<"$_n2")
# shellcheck disable=SC2086
set -- $_pos; _rc="${1#rc=}"; _sw="${2#switch=}"; _bf="${3#before=}"; _el="${4#elapsed=}"
[[ "$_rc" -eq 0 && "$_sw" -eq 1 && "$_bf" -eq 0 && "$_el" -eq 0 ]] \
    && ok "(N2) demote ran before any external alert (notifiers-before-demote=0, added latency=0s)" \
    || bad "(N2) demote did not precede the alert / was delayed ($_pos)"
[[ "$_neg" == "before=2" ]] \
    && ok "(N2 control) old alert-first order is detectable (2 notifier calls precede the demote) → assertion non-vacuous" \
    || bad "(N2 control) negative control unexpected ($_neg)"

results_banner
