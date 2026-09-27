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
#   (F1d) successful CANONICAL read                          → clears the no-answer timer (garbage does not: S1)
# v0.6.6 (N2) demote-before-alert ordering:
#   (N2)  no-answer fire → switch_to_unstaked runs BEFORE any external alert (notifiers mocked to
#         sleep): 0 notifier calls complete before the demote, 0 added latency. A negative control
#         replays the old alert-first order to prove the measurement is non-vacuous (observes 2).
# v0.7 Block 6.3 fix round 2 (R6a–c): a non-canonical LOCAL value → the fencing condition; fix round 3
# (S1a–b): a garbage slot is no canonical answer — the no-answer clock (and a restored backdate) keeps
# running through it, in the loop and across a restore; fix round 4 (W1a–b): a garbage-slot cycle adds
# own-vote-lag (N6) evidence and never removes it — its healthy vote reading neither counts toward the B2
# reset nor consumes the restored backdate.
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
        *getVoteAccounts*) [[ -z "${_LOCAL_GVA:-}" ]] && return 7; printf '%s' "$_LOCAL_GVA"; return 0 ;;   # (R6) only when a case sets it
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

# (F1d) a successful CANONICAL read clears a running no-answer timer (a present non-canonical answer does not —
# the S1 rows below; DEPLOYMENT-MANUAL: only a canonical answer resets it)
prep
_selffence_noanswer_since=$(( $(NOW) - 30 )); _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1050
check_self_fence_isolation; rc=$?
[[ "$_selffence_noanswer_since" -eq 0 && "$_fence_calls" -eq 0 ]] \
    && ok "(F1d) a successful CANONICAL slot read clears the no-answer timer (a present non-canonical answer does not — S1 below)" \
    || bad "(F1d) successful read did not reset the no-answer timer (since=$_selffence_noanswer_since calls=$_fence_calls)"

# ── (R6) 6.3 fix round 2 (REG-D): a PRESENT but non-canonical LOCAL value fails toward the fence ─────
# The holder's own node answering garbage fails toward "nobody holds the stake": the fencing condition
# (frozen / behind / lagging) — never healthy, and never the no-answer path SELF_FENCE_NOANSWER_SECS=0
# disables. Pre-fix red (f22d492, M4 "unusable" = no answer): the slot "0001000" after 35 s without an
# advance → 'no answer — treating as validator-unreachable', NO fence; numSlotsBehind "0000300" → ignored,
# NO fence; an own lastVote "abc" → cannot determine (HOLD), NO fence. Canonical inputs: unchanged.
echo ""; echo "─── (R6) non-canonical LOCAL values → the fencing condition (frozen / behind / lagging) ───"
_r6_noans="$SELF_FENCE_NOANSWER_SECS"; SELF_FENCE_NOANSWER_SECS=0
prep; _LOCAL_SLOT='"0001000"'; _LOCAL_HEALTH='{"jsonrpc":"2.0","result":"ok","id":1}'
_last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - SELF_FENCE_ISOLATION_SECS - 5 ))
check_self_fence_isolation >/dev/null; rc=$?
r6a="$rc/$_fence_calls/$_fence_reason"
prep; _LOCAL_SLOT='"0001000"'; _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 ))
check_self_fence_isolation >/dev/null; rc=$?
r6a2="$rc/$_fence_calls/$_last_confirmed_slot"
if [[ "$r6a" == 0/1/*"frozen"* && "$r6a2" == "1/0/1000" ]]; then
    ok "(R6a) a NON-CANONICAL confirmed slot (the JSON string \"0001000\") with SELF_FENCE_NOANSWER_SECS=0 counts as NOT advancing: 35 s without an advance → self-fence (frozen); 5 s → not yet, and the tracker does NOT move (1000). Pre-fix: the no-answer path — NO fence at NOANSWER=0"
else
    bad "(R6a) 35s=$r6a :: 5s=$r6a2"
fi
prep; SELF_FENCE_MAX_BEHIND=150; _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1050
_LOCAL_HEALTH='{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind","data":{"numSlotsBehind":"0000300"}},"id":1}'
check_self_fence_isolation >/dev/null; rc=$?; r6b="$rc/$_fence_calls/$_fence_reason"
prep; SELF_FENCE_MAX_BEHIND=150; _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1050
_LOCAL_HEALTH='{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind","data":{"numSlotsBehind":100}},"id":1}'
check_self_fence_isolation >/dev/null; rc=$?; r6bc="$rc/$_fence_calls"
if [[ "$r6b" == 0/1/*"getHealth behind"* && "$r6bc" == "1/0" ]]; then
    ok "(R6b) a NON-CANONICAL numSlotsBehind (\"0000300\") counts as BEHIND → self-fence at once; the canonical control (100 <= 150) → no fence. Pre-fix: ignored, NO fence"
else
    bad "(R6b) garbage=$r6b :: canonical-100=$r6bc"
fi
_r6_vp="${VOTE_PUBKEY:-}"; VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
gva() { printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"Cluster111","lastVote":%s},{"votePubkey":"%s","lastVote":%s}],"delinquent":[]},"id":1}' "$2" "$VOTE_PUBKEY" "$1"; }
prep; _LOCAL_HEALTH='{"jsonrpc":"2.0","result":"ok","id":1}'
_selffence_votelag_baseline=1; _selffence_votelag_healthy=0; _selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 1 ))
_last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1050
_LOCAL_GVA=$(gva '"abc"' 100000)
check_self_fence_isolation >/dev/null; rc=$?; r6c="$rc/$_fence_calls/$_fence_reason"
prep; _selffence_votelag_baseline=1; _selffence_votelag_healthy=0; _selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 1 ))
_last_confirmed_slot=1000; _last_confirmed_advance_ts=$(( $(NOW) - 5 )); _LOCAL_SLOT=1050
_LOCAL_GVA=$(gva 99995 100000)
check_self_fence_isolation >/dev/null; rc=$?; r6cc="$rc/$_fence_calls"
_LOCAL_GVA=""; VOTE_PUBKEY="$_r6_vp"; SELF_FENCE_VOTE_LAG_SLOTS=0; SELF_FENCE_VOTE_LAG_SECS=0; _selffence_votelag_since=0; _selffence_votelag_baseline=""
SELF_FENCE_NOANSWER_SECS="$_r6_noans"; _LOCAL_SLOT=1000
if [[ "$r6c" == 0/1/*"own votes not landing"*"NON-CANONICAL"* && "$r6cc" == "1/0" ]]; then
    ok "(R6c) a NON-CANONICAL own lastVote (\"abc\") under a running N6 sustain timer counts as LAGGING → self-fence ('own votes not landing (lag a NON-CANONICAL lastVote …)'); the canonical control (lag 5) → no fence. Pre-fix: cannot determine (HOLD), NO fence"
else
    bad "(R6c) garbage=$r6c :: canonical-lag5=$r6cc"
fi

# ── (S1) 6.3 fix round 3 (H-R6-SILENCE): a garbage slot is NOT a canonical answer ───────────────────
# It keeps (or starts, or backdates from the restored start) the no-answer clock and fences when that clock
# is due, while its frozen clock runs too; only a canonical answer clears either. The REAL function on a
# fake clock (a subshell), 5 s cycles, NOANSWER 30, ISOLATION 30: C canonical advancing, G garbage, S
# silent (the last letter repeats). Pre-fix red (e917c04): 1..5 garbage cycles then silence fenced at
# 55/60/65/70/75 s where f22d492 fences at 50 (de21927: 50 text / 55..75 digits); a restored 20 s silence
# + 1 / 3 garbage reads fenced at 35 / 45 where f22d492 and de21927 fence at 10; a restored 25 s silence +
# steady garbage at 30 where f22d492 fences at 5.
s1_run() {   # $1 = letters, $2 = the garbage JSON token, $3 = restored silence age (s; "" = none) → the fence second, or never
  (
    _S1T=100000; _S1F=""
    mono_now() { echo "$_S1T"; }
    date() { if [[ "$1" == "+%s" ]]; then echo "$_S1T"; return 0; fi; command date "$@"; }
    switch_to_unstaked() { _S1F=$(( _S1T - 100000 )); return 0; }
    alert() { :; }; log_info() { :; }; log_warn() { :; }
    DRY_RUN=false; CURRENT_IDENTITY="$STAKED_PUBKEY"; SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_ISOLATION_SECS=30
    VOTE_PUBKEY=""; _LOCAL_GVA=""
    _selffence_reset
    if [[ -n "$3" ]]; then _last_confirmed_slot=400000000; _selffence_noanswer_restore_pending=1; _selffence_restored_noanswer_since=$(( _S1T - $3 )); fi
    local i L
    for (( i = 0; i < 40; i++ )); do
      L=${1:$(( i < ${#1} ? i : ${#1} - 1 )):1}
      case "$L" in C) _LOCAL_SLOT=$(( 400000000 + i * 12 )) ;; G) _LOCAL_SLOT="$2" ;; S) _LOCAL_SLOT="" ;; esac
      check_self_fence_isolation >/dev/null 2>&1
      [[ -n "$_S1F" ]] && { echo "$_S1F"; return; }
      _S1T=$(( _S1T + 5 ))
    done
    echo never
  )
}
echo ""; echo "─── (S1) garbage keeps the no-answer clock (in the loop and across a restore) ───"
s1_ok=1
for tok in '"abc"' '"0400000123"'; do
  for n in 1 2 3 4 5; do
    got=$(s1_run "CCCC$(printf "%${n}s" | tr ' ' G)S" "$tok" "")
    [[ "$got" == "50" ]] || { s1_ok=0; bad "(S1a) $n garbage cycle(s) $tok then silence: fence at $got, want 50"; }
  done
done
[[ $s1_ok -eq 1 ]] && ok "(S1a) 1..5 garbage cycles (\"abc\" and \"0400000123\") then silence fence at t50: the no-answer clock starts at the first garbage read (= f22d492; de21927 50 / 55..75). Pre-fix: 55/60/65/70/75"
r1=$(s1_run "GS" '"abc"' 20); r3=$(s1_run "GGGS" '"abc"' 20); rst=$(s1_run "G" '"abc"' 25)
if [[ "$r1" == "10" && "$r3" == "10" && "$rst" == "5" ]]; then
  ok "(S1b) across a restore: a restored 20 s silence + 1 / 3 garbage reads then silence → fence at t10 (= f22d492 and de21927; pre-fix 35 / 45 — the garbage dropped the restored backdate); a restored 25 s silence + STEADY garbage → fence at t5, the restored clock due on a garbage read (f22d492 t5; pre-fix and the panel's one-hunk mutant t30)"
else
  bad "(S1b) restored 20 s + 1 G → $r1 (want 10); + 3 G → $r3 (want 10); restored 25 s + steady G → $rst (want 5)"
fi

# ── (W1) 6.3 fix round 4 (H4-R6-VOTELAG): a garbage-slot cycle ADDS own-vote-lag evidence, never removes it ─
# The REAL function on a fake clock (a subshell), 3 s cycles (the primary's CHECK_INTERVAL), N6 at the
# shipped 32 slots / 20 s / RESET_CYCLES 3, ISOLATION and NOANSWER 30. Letters (the last repeats): C the
# slot advances, own vote current; L the slot advances, own vote 100 behind the same-payload cluster-max;
# G a garbage slot, own vote current; H a garbage slot, own vote lagging. Pre-fix red (7ab7eca; e917c04 the
# same — R6's fall-through): the G cycles' healthy readings reset the sustain timer and consumed the
# restored backdate — CCCCLGGGL 45, CCCCLGGGGL 48, CCCCLGGGLGGGL 57, CCCCLLLGGGL 51, (LLLGGG)x5 then L 123
# where de21927 and f22d492 fence at 33 / 33 / 36 / 33 / 33; restored lag 100 s + GL / GGL / GGGL at
# grace 0 → 24 / 27 / 30 where they fence at 3 / 6 / 9. Controls, identical on every tree: CCCCLHHHL 33,
# the canonical (LLLCCC)x4 then L 105.
w1_run() {   # $1 = letters, $2 = the garbage JSON token, $3 = restored lag age (s; "" = none) → the fence second, or never
  (
    _W1T=100000; _W1F=""
    mono_now() { echo "$_W1T"; }
    date() { if [[ "$1" == "+%s" ]]; then echo "$_W1T"; return 0; fi; command date "$@"; }
    switch_to_unstaked() { _W1F=$(( _W1T - 100000 )); return 0; }
    alert() { :; }; log_info() { :; }; log_warn() { :; }
    DRY_RUN=false; CURRENT_IDENTITY="$STAKED_PUBKEY"; SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_ISOLATION_SECS=30
    VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
    SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
    _selffence_reset
    if [[ -n "$3" ]]; then
      _last_confirmed_slot=400000000; _selffence_votelag_baseline=1; _selffence_votelag_healthy=0
      _selffence_votelag_restore_pending=1; _selffence_restored_votelag_since=$(( _W1T - $3 ))
    fi
    local i L cm own
    for (( i = 0; i < 60; i++ )); do
      L=${1:$(( i < ${#1} ? i : ${#1} - 1 )):1}
      cm=$(( 500000000 + i * 8 )); own=$(( cm - 1 ))
      case "$L" in
        C) _LOCAL_SLOT=$(( 400000000 + i * 8 )) ;;
        L) _LOCAL_SLOT=$(( 400000000 + i * 8 )); own=$(( cm - 100 )) ;;
        G) _LOCAL_SLOT="$2" ;;
        H) _LOCAL_SLOT="$2"; own=$(( cm - 100 )) ;;
      esac
      _LOCAL_GVA=$(printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"Cluster111","lastVote":%s},{"votePubkey":"%s","lastVote":%s}],"delinquent":[]},"id":1}' "$cm" "$VOTE_PUBKEY" "$own")
      check_self_fence_isolation >/dev/null 2>&1
      [[ -n "$_W1F" ]] && { echo "$_W1F"; return; }
      _W1T=$(( _W1T + 3 ))
    done
    echo never
  )
}
echo ""; echo "─── (W1) a garbage-slot cycle adds own-vote-lag (N6) evidence, never removes it ───"
w1_ok=1
for tok in '"abc"' '"0400000123"'; do
  for row in CCCCLGGGL:33 CCCCLGGGGL:33 CCCCLGGGLGGGL:36 CCCCLLLGGGL:33 CCCCLLLGGGLLLGGGLLLGGGLLLGGGLLLGGGL:33 CCCCLHHHL:33 CCCCLLLCCCLLLCCCLLLCCCLLLCCCL:105; do
    got=$(w1_run "${row%%:*}" "$tok" "")
    [[ "$got" == "${row##*:}" ]] || { w1_ok=0; bad "(W1a) ${row%%:*} $tok: fence at $got, want ${row##*:}"; }
  done
done
[[ $w1_ok -eq 1 ]] && ok "(W1a) in the loop, garbage \"abc\" and \"0400000123\" (3 s cycles): CCCCLGGGL → 33, CCCCLGGGGL → 33, CCCCLGGGLGGGL → 36, CCCCLLLGGGL → 33, (LLLGGG)x5 then L → 33 (= de21927 and f22d492; pre-fix 45 / 48 / 57 / 51 / 123), controls CCCCLHHHL → 33 and the canonical (LLLCCC)x4 then L → 105 (every tree)"
w1_ok=1
for row in GL:3 GGL:6 GGGL:9 HL:0; do
  got=$(w1_run "${row%%:*}" '"abc"' 100)
  [[ "$got" == "${row##*:}" ]] || { w1_ok=0; bad "(W1b) restored lag 100 s + ${row%%:*}: fence at $got, want ${row##*:}"; }
done
[[ $w1_ok -eq 1 ]] && ok "(W1b) across a restore (persisted lag 100 s, grace 0): GL → 3, GGL → 6, GGGL → 9 — the garbage cycles' healthy vote readings leave the restored backdate to the first lagging read (= de21927 and f22d492; pre-fix 24 / 27 / 30), control HL → 0 (every tree)"

# ── (N2) v0.6.6: the demote runs BEFORE any external alert in the no-answer branch ─────────────
# Re-source fresh so alert() is the REAL shipped function (the F1 block above mocked it to a recorder).
# Mock the notifiers to SLEEP (endpoints hanging — the exact bad case) and assert switch_to_unstaked
# fires with ZERO notifier calls completed before it and ZERO added latency: the safety demote must
# never wait on notification I/O. A negative control replays the OLD (alert-first) order to prove the
# measurement is non-vacuous (it would observe 2 notifier calls before the demote).
# 6.3.1 fix round 1 (R6 — N2 load-robustness): the latency is measured in MILLISECONDS (EPOCHREALTIME on bash >= 5,
# else perl's Time::HiRes — both present on the gate hosts; integer SECONDS only as the last resort) and bounded
# at 500 ms — the path measures 2–4 ms and ONE hanging notifier would add 1000 ms. The integer-second form
# (elapsed == 0) failed once under heavy load with the ORDER correct (elapsed=1: a SECONDS tick between the two
# reads). The property is unchanged: ZERO notifiers complete before the demote, and the demote waits on none.
_n2_ms() {   # a millisecond wall clock, or empty when none is available
    if [[ -n "${EPOCHREALTIME:-}" ]]; then local _u="${EPOCHREALTIME//[!0-9]/}"; echo $(( 10#$_u / 1000 )); return 0; fi
    perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000' 2>/dev/null
}
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
  switch_to_unstaked(){ _switch_called=1; _before=$_notify_done; _elapsed=$(( SECONDS - _t0 )); _m1=$(_n2_ms); [[ -n "$_m0" && -n "$_m1" ]] && _elapsed_ms=$(( _m1 - _m0 )); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
  curl(){ return 7; }   # LOCAL getSlot silent (no-answer)
  _last_confirmed_slot=1000; _selffence_noanswer_since=$(( $(date +%s) - SELF_FENCE_NOANSWER_SECS - 5 ))
  _elapsed_ms=""; _t0=$SECONDS; _m0=$(_n2_ms)
  check_self_fence_isolation >/dev/null 2>&1; rc=$?
  echo "POS rc=$rc switch=$_switch_called before=$_before elapsed=$_elapsed ms=${_elapsed_ms:-none}"
  # negative control: replay the OLD alert-first order with the SAME mocks → expect before=2
  _notify_done=0; _switch_called=0; _before=-1; _t0=$SECONDS
  alert "x" "y" "z"; switch_to_unstaked "x"
  echo "NEG before=$_before"
)
_pos=$(sed -n 's/^POS //p' <<<"$_n2"); _neg=$(sed -n 's/^NEG //p' <<<"$_n2")
# shellcheck disable=SC2086
set -- $_pos; _rc="${1#rc=}"; _sw="${2#switch=}"; _bf="${3#before=}"; _el="${4#elapsed=}"; _ms="${5#ms=}"
if [[ "$_ms" == "none" ]]; then _lat_ok=0; [[ "$_el" -le 1 ]] && _lat_ok=1; _lat="${_el} s (no ms clock on this host: integer SECONDS, a tick allowed)"
else _lat_ok=0; [[ "$_ms" -lt 500 ]] && _lat_ok=1; _lat="${_ms} ms (< 500; one hanging notifier = 1000)"; fi
[[ "$_rc" -eq 0 && "$_sw" -eq 1 && "$_bf" -eq 0 && $_lat_ok -eq 1 ]] \
    && ok "(N2) demote ran before any external alert (notifiers-before-demote=0, added latency ${_lat})" \
    || bad "(N2) demote did not precede the alert / was delayed ($_pos)"
[[ "$_neg" == "before=2" ]] \
    && ok "(N2 control) old alert-first order is detectable (2 notifier calls precede the demote) → assertion non-vacuous" \
    || bad "(N2 control) negative control unexpected ($_neg)"

results_banner
