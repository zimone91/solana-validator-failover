#!/bin/bash
# v0.6.8 (B1): the DEMOTE set-identity is bounded and, on a wedged admin socket (timeout), escalates to a
# HARD STOP so the staked identity provably stops voting. The PROMOTE path is bounded but FAIL-SAFE (never
# kills). And the frozen / no-answer / getHealth self-fence sub-checks adopt the N9 retry discipline
# (reset the timer ONLY after a confirmed demote; a failed demote stays armed and retries).
#   (B1-a) agave demote set-identity TIMES OUT          → hard stop (systemctl+kill), HARD STOP alert, rc 0
#   (B1-b) agave demote remove-all TIMES OUT            → hard stop at once (socket wedged), rc 0
#   (B1-c) timeout + SELF_FENCE_HARD_STOP=false         → NO kill, "NO HARD STOP" alert, rc 1 (gap left open)
#   (B1-d) demote succeeds (no timeout)                 → flips to UNSTAKED, rc 0, NO kill, NO hard-stop alert
#   (B1-e) DRY_RUN demote                               → rc 0, identity unchanged, NO timeout/kill path
#   (B1-f) PROMOTE (switch_to_staked) set-identity hangs → FAIL-SAFE: NO kill, rc 1 (stays not-staked)
#   (B1-g) frozen-slot   demote FAILS → timer stays armed (retries); SUCCEEDS → reset (no re-fire)
#   (B1-h) no-answer     demote FAILS → timer stays armed (retries); SUCCEEDS → reset
#   (B1-i) getHealth     demote FAILS → timer stays armed (retries); SUCCEEDS → reset

# B1-a..e call the REAL switch_to_unstaked (sourced below); the retry-discipline block later defines a
# mock that shadows it — shellcheck can't see the sourced def and flags SC2218 (used-before-defined).
# shellcheck disable=SC2218
#
# harness: tests/lib/harness.sh — ok/bad+banners, paths. Cut + sink subset + `date +%s` clock stay local.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"; rm -f "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock

# --- fixtures ---
STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
SOLANA_PATH="/mock"; LEDGER_PATH="/mock/ledger"; CONFIG_TOML="/mock/cfg.toml"
VALIDATOR_TYPE="agave"; VALIDATOR_SERVICE="solana"
SETIDENTITY_TIMEOUT=15; SELF_FENCE_HARD_STOP=true
ALERT_THROTTLE=0; RECOVERY_COOLDOWN=0; LAST_SWITCH_TIME=0; STAT_SWITCHES=0
TG_ENABLED=false
KP_STAKED=$(mktemp); echo '[1,2,3]' > "$KP_STAKED"; STAKED_KEYPAIR="$KP_STAKED"
KP_UNSTAKED=$(mktemp); echo '[4,5,6]' > "$KP_UNSTAKED"; UNSTAKED_KEYPAIR="$KP_UNSTAKED"
trap 'rm -f "$KP_STAKED" "$KP_UNSTAKED"' EXIT

log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
send_telegram() { return 0; }
send_webhook()  { :; }
save_state() { :; }
sleep() { :; }                                   # skip the real 1s post-switch sleep
get_tower_path() { echo "/nonexistent-tower-$$"; }   # so the [[ -f ]] rm is skipped

# alert capture
_alert_status=""; _alert_calls=0
alert() { _alert_calls=$((_alert_calls+1)); _alert_status="$3"; }

# hard-stop observability: model the validator process. pgrep returns a pid while ALIVE; kill clears it
# (unless _proc_immortal=1 → models a process that survives SIGKILL). v0.6.8 (S4): hard_stop now VERIFIES.
_kills=0; _proc_alive=1; _proc_immortal=0
pgrep() { [[ $_proc_alive -eq 1 ]] && echo "12345"; return 0; }
kill()  { _kills=$((_kills+1)); [[ ${_proc_immortal:-0} -eq 1 ]] || _proc_alive=0; return 0; }

# timeout mock: drives the rc of the wrapped admin-socket call by inspecting the command.
# _RC_SETID / _RC_REMOVE / _RC_SYSTEMCTL = 0 (ok) or 124/137 (timed out / killed). everything else = ok.
_RC_SETID=0; _RC_REMOVE=0; _RC_SYSTEMCTL=0
timeout() {
    shift                                          # drop the -k flag (next token is its arg / seconds)
    case "$*" in
        *set-identity*"$UNSTAKED_KEYPAIR"*) return $_RC_SETID ;;
        *set-identity*"$STAKED_KEYPAIR"*)   return $_RC_SETID ;;
        *remove-all*)                       return $_RC_REMOVE ;;
        *systemctl*)                        return $_RC_SYSTEMCTL ;;
        *)                                  return 0 ;;     # authorized-voter add, etc.
    esac
}
# get_local_identity result after a switch (success path re-reads it)
_IDENT_AFTER="$UNSTAKED_PUBKEY"
get_local_identity() { echo "$_IDENT_AFTER"; }

reset_obs() { _alert_status=""; _alert_calls=0; _kills=0; _proc_alive=1; _proc_immortal=0; _RC_SETID=0; _RC_REMOVE=0; _RC_SYSTEMCTL=0; CURRENT_IDENTITY="$STAKED_PUBKEY"; DRY_RUN=false; SELF_FENCE_HARD_STOP=true; }

title_banner "PRIMARY demote timeout + hard stop + retry discipline (v0.6.8 B1)"

# ── (B1-a) set-identity to unstaked times out → HARD STOP ─────────────────────────────────────
echo ""; echo "─── (B1-a) demote set-identity TIMES OUT → systemctl stop + kill, HARD STOP alert, rc 0 ───"
reset_obs; _RC_SETID=124
switch_to_unstaked "test: set-identity hang"; rc=$?
[[ $rc -eq 0 && "$_alert_status" == *"HARD STOP"* && "$_alert_status" != *"NO HARD STOP"* && $_kills -ge 1 ]] \
    && ok "(B1-a) wedged demote → hard-stopped (kill=$_kills), 'HARD STOP' alert, rc 0 (votes provably halted)" \
    || bad "(B1-a) did not hard-stop (rc=$rc status='$_alert_status' kills=$_kills)"

# ── (B1-b) remove-all times out → escalate immediately ────────────────────────────────────────
echo ""; echo "─── (B1-b) demote remove-all TIMES OUT → hard stop at once (socket wedged), rc 0 ───"
reset_obs; _RC_REMOVE=124; _RC_SETID=0
switch_to_unstaked "test: remove-all hang"; rc=$?
[[ $rc -eq 0 && "$_alert_status" == *"HARD STOP"* && $_kills -ge 1 ]] \
    && ok "(B1-b) remove-all hang → hard-stopped before set-identity (kill=$_kills), rc 0" \
    || bad "(B1-b) did not escalate on remove-all hang (rc=$rc status='$_alert_status' kills=$_kills)"

# ── (B1-c) hard-stop disabled → NO kill, leaves the gap (URGENT page) ─────────────────────────
echo ""; echo "─── (B1-c) timeout + SELF_FENCE_HARD_STOP=false → NO kill, 'NO HARD STOP' alert, rc 1 ───"
reset_obs; _RC_SETID=124; SELF_FENCE_HARD_STOP=false
switch_to_unstaked "test: hang, hard-stop off"; rc=$?
[[ $rc -eq 1 && "$_alert_status" == *"NO HARD STOP"* && $_kills -eq 0 ]] \
    && ok "(B1-c) hard-stop off → no kill, 'NO HARD STOP' urgent page, rc 1 (operator must intervene)" \
    || bad "(B1-c) misbehaved (rc=$rc status='$_alert_status' kills=$_kills)"

# ── (B1-d) normal demote (no timeout) → flips to unstaked, no kill ────────────────────────────
echo ""; echo "─── (B1-d) demote succeeds (no timeout) → flips UNSTAKED, rc 0, NO kill, NO hard-stop alert ───"
reset_obs; _IDENT_AFTER="$UNSTAKED_PUBKEY"
switch_to_unstaked "test: clean demote"; rc=$?
[[ $rc -eq 0 && "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" && $_kills -eq 0 && "$_alert_status" != *"HARD STOP"* ]] \
    && ok "(B1-d) clean demote → identity=UNSTAKED, rc 0, no kill, no hard-stop (normal path untouched)" \
    || bad "(B1-d) misbehaved (rc=$rc identity=$CURRENT_IDENTITY kills=$_kills status='$_alert_status')"

# ── (B1-e) DRY_RUN never reaches the timeout/kill path ────────────────────────────────────────
echo ""; echo "─── (B1-e) DRY_RUN demote → rc 0, identity unchanged, no timeout/kill path ───"
reset_obs; DRY_RUN=true; _RC_SETID=124   # even if it WOULD time out, DRY_RUN returns before the real path
switch_to_unstaked "test: dry"; rc=$?
[[ $rc -eq 0 && "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" && $_kills -eq 0 ]] \
    && ok "(B1-e) DRY_RUN → 'would switch', identity unchanged, no kill (timeout/escalation never reached)" \
    || bad "(B1-e) DRY_RUN touched the real path (rc=$rc identity=$CURRENT_IDENTITY kills=$_kills)"

# ── (B1-f) PROMOTE hang is FAIL-SAFE (no kill) ────────────────────────────────────────────────
echo ""; echo "─── (B1-f) switch_to_staked set-identity hangs → FAIL-SAFE: NO kill, rc 1 (stays not-staked) ───"
reset_obs; _RC_SETID=124; _IDENT_AFTER="$UNSTAKED_PUBKEY"   # promote 'fails' → re-read still unstaked
CURRENT_IDENTITY="$UNSTAKED_PUBKEY"
switch_to_staked "test: promote hang"; rc=$?
[[ $rc -eq 1 && $_kills -eq 0 && "$_alert_status" != *"HARD STOP"* ]] \
    && ok "(B1-f) promote hang → no kill, recovery reads failed (rc 1), node stays on safe unstaked identity" \
    || bad "(B1-f) promote path escalated/killed (rc=$rc kills=$_kills status='$_alert_status')"

# ════════ (S4) _selffence_hard_stop VERIFIES the stop before reporting success ════════
echo ""; echo "─── (S4-confirmed) systemctl ok + process dies → rc 0 (confirmed down) ───"
reset_obs; _proc_alive=1; _RC_SYSTEMCTL=0
_selffence_hard_stop "s4 confirmed"; rc=$?
[[ $rc -eq 0 && "$_alert_status" == *"HARD STOP"* && "$_alert_status" != *"FAILED"* && "$_alert_status" != *"UNCONFIRMED"* ]] \
    && ok "(S4-confirmed) validator confirmed down → rc 0 (HARD STOP ✅)" \
    || bad "(S4-confirmed) wrong (rc=$rc status='$_alert_status')"

echo ""; echo "─── (S4-survives) validator survives SIGTERM+SIGKILL → rc 1 (FAILED, keep retrying) ───"
reset_obs; _proc_alive=1; _proc_immortal=1; _RC_SYSTEMCTL=0
_selffence_hard_stop "s4 survives"; rc=$?
[[ $rc -eq 1 && "$_alert_status" == *"FAILED"* ]] \
    && ok "(S4-survives) process survives the kill → rc 1 (does NOT falsely report success)" \
    || bad "(S4-survives) reported success despite a live validator (rc=$rc status='$_alert_status')"

echo ""; echo "─── (S4-unconfirmed) systemctl fails + no validator process found → rc 1 (UNCONFIRMED) ───"
reset_obs; _proc_alive=0; _RC_SYSTEMCTL=124
_selffence_hard_stop "s4 unconfirmed"; rc=$?
[[ $rc -eq 1 && "$_alert_status" == *"UNCONFIRMED"* ]] \
    && ok "(S4-unconfirmed) systemctl failed AND no PID matched → rc 1 (stops nothing, does NOT claim success)" \
    || bad "(S4-unconfirmed) falsely reported success when nothing was stopped (rc=$rc status='$_alert_status')"

# ════════ retry discipline for frozen / no-answer / getHealth (drive check_self_fence_isolation) ════════
# Mock switch_to_unstaked to control success/failure and count calls (like the N9 test).
_sw_rc=0; _sw_calls=0
switch_to_unstaked() { _sw_calls=$((_sw_calls+1)); [[ $_sw_rc -eq 0 ]] && CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return $_sw_rc; }
DRY_RUN=false; CURRENT_IDENTITY="$STAKED_PUBKEY"

# curl mock for the sub-checks
_MODE="frozen"; _SLOT=100000
curl() {
    local data=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { data="$2"; shift 2; continue; }; shift; done
    case "$data" in
        *getSlot*)   [[ "$_MODE" == "noanswer" ]] && return 7; printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$_SLOT"; return 0 ;;
        *getHealth*) [[ "$_MODE" == "health" ]] && { printf '{"error":{"data":{"numSlotsBehind":999}}}'; return 0; }; printf '{"result":"ok"}'; return 0 ;;
        *getVoteAccounts*) printf '{"jsonrpc":"2.0","result":{"current":[],"delinquent":[]},"id":1}'; return 0 ;;
    esac
    return 7
}

# (B1-g) frozen-slot: prep ONCE (v0.6.8 S5 — re-prepping between cycles hid a one-and-done revert). Two
# consecutive FAILED demotes must BOTH fire: a one-and-done reset would clear _last_confirmed_slot after
# cycle 1, so cycle 2 would only re-baseline (no fire) → _sw_calls=1. The N9 keep-armed fix → _sw_calls=2.
echo ""; echo "─── (B1-g) frozen-slot: prep-once, failed demote stays armed → fires on BOTH cycles (de-vacuumed) ───"
SELF_FENCE_NOANSWER_SECS=0; SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=0
SELF_FENCE_VOTE_LAG_SLOTS=0; SELF_FENCE_VOTE_LAG_SECS=0; _MODE="frozen"; _SLOT=100000
_sw_rc=1; _sw_calls=0
CURRENT_IDENTITY="$STAKED_PUBKEY"; _last_confirmed_slot=$_SLOT; _last_confirmed_advance_ts=$(( $(date +%s) - SELF_FENCE_ISOLATION_SECS - 5 ))   # prep ONCE
check_self_fence_isolation >/dev/null 2>&1   # cycle 1: frozen → fire → FAIL (no reset, tracker intact)
check_self_fence_isolation >/dev/null 2>&1   # cycle 2: STILL frozen (tracker survived the failed demote) → fire again
[[ $_sw_calls -eq 2 ]] \
    && ok "(B1-g) frozen: prep-once → failed demote stayed armed → fired on BOTH cycles (a one-and-done reset fires once)" \
    || bad "(B1-g) frozen retry discipline vacuous/broken (_sw_calls=$_sw_calls, expected 2)"
# success then resets the tracker (no re-fire next cycle)
_sw_rc=0; _sw_calls=0
CURRENT_IDENTITY="$STAKED_PUBKEY"; _last_confirmed_slot=$_SLOT; _last_confirmed_advance_ts=$(( $(date +%s) - SELF_FENCE_ISOLATION_SECS - 5 ))
check_self_fence_isolation >/dev/null 2>&1   # fire → SUCCESS → _selffence_reset clears _last_confirmed_slot
[[ $_sw_calls -eq 1 && -z "$_last_confirmed_slot" ]] \
    && ok "(B1-g) frozen: a SUCCESSFUL demote resets the tracker (no re-fire storm)" \
    || bad "(B1-g) frozen success-reset wrong (_sw_calls=$_sw_calls last_slot='$_last_confirmed_slot')"

# (B1-h) no-answer: getSlot silent, baseline present, timer old
echo ""; echo "─── (B1-h) no-answer demote FAILS → armed (retries); SUCCEEDS → reset ───"
SELF_FENCE_NOANSWER_SECS=30; _MODE="noanswer"
prep_na() { CURRENT_IDENTITY="$STAKED_PUBKEY"; _last_confirmed_slot=100000; _selffence_noanswer_since=$(( $(date +%s) - SELF_FENCE_NOANSWER_SECS - 5 )); }
_sw_rc=1; _sw_calls=0
prep_na; check_self_fence_isolation >/dev/null 2>&1
since_after_fail=$_selffence_noanswer_since
prep_na; check_self_fence_isolation >/dev/null 2>&1
na_fail=$_sw_calls
_sw_rc=0; _sw_calls=0
prep_na; check_self_fence_isolation >/dev/null 2>&1
[[ $na_fail -ge 2 && $_sw_calls -eq 1 && "$since_after_fail" -ne 0 && $_selffence_noanswer_since -eq 0 ]] \
    && ok "(B1-h) no-answer: failed demote kept the timer armed (since=$since_after_fail); success reset it to 0" \
    || bad "(B1-h) no-answer retry discipline wrong (fail=$na_fail ok=$_sw_calls since_fail=$since_after_fail since_now=$_selffence_noanswer_since)"

# (B1-i) getHealth is STATELESS (fires whenever behind > MAX), so "fires twice" cannot distinguish the N9
# discipline (v0.6.8 S5). Assert the REAL property instead: a FAILED getHealth demote must NOT wipe the
# frozen tracker. The old reset-before-switch cleared _last_confirmed_slot; the N9 fix leaves it intact.
echo ""; echo "─── (B1-i) getHealth: failed demote does NOT wipe the frozen tracker (de-vacuumed) ───"
SELF_FENCE_NOANSWER_SECS=0; SELF_FENCE_ISOLATION_SECS=999; SELF_FENCE_MAX_BEHIND=150; _MODE="health"; _SLOT=200000
_sw_rc=1; _sw_calls=0
CURRENT_IDENTITY="$STAKED_PUBKEY"; _last_confirmed_slot=$(( _SLOT - 100 )); _last_confirmed_advance_ts=$(date +%s)
check_self_fence_isolation >/dev/null 2>&1   # slot advances → reach getHealth → behind → fire → FAIL (no reset)
[[ $_sw_calls -ge 1 && "$_last_confirmed_slot" == "$_SLOT" ]] \
    && ok "(B1-i) getHealth: failed demote fired and LEFT the frozen tracker intact (_last_confirmed_slot=$_last_confirmed_slot; a premature reset would empty it)" \
    || bad "(B1-i) getHealth wiped the tracker on a failed demote (_sw_calls=$_sw_calls last_slot='$_last_confirmed_slot' want=$_SLOT)"

results_banner
