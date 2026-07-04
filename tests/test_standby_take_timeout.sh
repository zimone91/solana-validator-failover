#!/bin/bash
# v0.6.9 (H4): B1 parity on the standby switch paths. take_staked_identity / give_back_identity used to
# call set-identity / authorized-voter UNBOUNDED — a wedged admin socket at the takeover instant froze
# the loop mid-take. Drives the REAL shipped functions with `timeout` mocked at the I/O boundary.
#   (T-a) take set-identity times out (rc 124) but APPLIED → success + TOOK STAKED ✅ + ⚠️ wedged warn
#   (T-b) take times out and NOT applied → TAKEOVER FAILED ❌, episode state INTACT (N9), no kill
#   (T-c) voter-add times out after a good set-identity → success + ⚠️ "voting may not start" warn
#   (T-d) give-back times out, identity still staked → 🚨 HOLDER MAY STILL BE VOTING page + escalation
#         (hard-stop attempted when enabled; NO HARD STOP page when disabled)
#   (T-e) give-back times out but APPLIED → success-with-warn (GAVE BACK ✅ + ⚠️)
#   (T-f) NON-VACUOUS CONTROL: sed-strip the H4 `timeout -k 5 "$SETIDENTITY_TIMEOUT"` bound from a
#         patched copy → the wedge detection disappears (no ⚠️ wedged warn on the same inputs) —
#         proves T-a/T-c observe the fix, not an accident
#   (T-g) structural: v0.6.8 baseline had ZERO bounded calls in take/give-back

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
V068="$DIR/../../0.6.8/failover-v0.6.8/solana-standby-failover.sh"
[[ -f "$STANDBY" ]] || { echo "  ❌ standby script not found"; exit 1; }

# run one scenario in a fresh subshell against the given script copy; echo observables
#   $1=script  $2=op (take|giveback)  $3=RC_SETID  $4=RC_ADD  $5=RC_REMOVE  $6=applied(1/0)  $7=hardstop(true/false)
scenario() {
  local script="$1" op="$2" rc_setid="$3" rc_add="$4" rc_remove="$5" applied="$6" hardstop="$7"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
    SOLANA_PATH="/mock"; LEDGER_PATH="/mock/ledger"; VALIDATOR_TYPE="agave"; VALIDATOR_SERVICE="solana"
    SETIDENTITY_TIMEOUT=15; SELF_FENCE_HARD_STOP="$hardstop"; HARD_STOP_REVERIFY_SECS=0
    SELF_FENCE_RETAKE_COOLDOWN=600; TG_ENABLED=false; DRY_RUN=false; ALERT_THROTTLE=0
    KP_S=$(mktemp); echo '[1]' > "$KP_S"; STAKED_KEYPAIR="$KP_S"
    KP_U=$(mktemp); echo '[2]' > "$KP_U"; UNSTAKED_KEYPAIR="$KP_U"
    ID_FILE=$(mktemp)
    trap 'rm -f "$KP_S" "$KP_U" "$ID_FILE"' EXIT
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    send_telegram(){ return 0; }; send_webhook(){ :; }; save_state(){ :; }; sleep(){ :; }
    ALERTS=""; alert(){ ALERTS+="|$3"; }
    WARNS="";  alert_warn(){ WARNS+="|$1"; }
    alert_info(){ :; }
    KILLS=0; kill(){ KILLS=$((KILLS+1)); PROC=0; return 0; }
    PROC=1; pgrep(){ [[ $PROC -eq 1 ]] && echo 4242; return 0; }
    get_local_identity(){ cat "$ID_FILE"; }
    _RC_SETID="$rc_setid"; _RC_ADD="$rc_add"; _RC_REMOVE="$rc_remove"; _APPLIED="$applied"
    timeout(){
        case "$*" in
            *set-identity*"$STAKED_KEYPAIR"*)   [[ "$_APPLIED" == "1" ]] && echo "$STAKED_PUBKEY" > "$ID_FILE";   return "$_RC_SETID" ;;
            *set-identity*"$UNSTAKED_KEYPAIR"*) [[ "$_APPLIED" == "1" ]] && echo "$UNSTAKED_PUBKEY" > "$ID_FILE"; return "$_RC_SETID" ;;
            *authorized-voter\ add*)            return "$_RC_ADD" ;;
            *remove-all*)                       return "$_RC_REMOVE" ;;
            *systemctl*)                        return 0 ;;
        esac
        return 0
    }
    # episode state to verify N9 (must survive a FAILED take)
    _delinq_window="1111111111"; FIRST_DELINQUENT_TIME=12345; LAST_LIVENESS_ACTIVE_TIME=777
    _liveness_first_vote="9000"; LAST_TAKEOVER_TIME=0
    if [[ "$op" == "take" ]]; then
        echo "U1" > "$ID_FILE"; CURRENT_IDENTITY="U1"
        take_staked_identity "test"; rc=$?
    else
        echo "S1" > "$ID_FILE"; CURRENT_IDENTITY="S1"
        give_back_identity "test"; rc=$?
    fi
    printf 'rc=%s|alerts=%s|warns=%s|kills=%s|window=%s|first=%s|lla=%s|lfv=%s|ltt=%s|id=%s\n' \
        "$rc" "$ALERTS" "$WARNS" "$KILLS" "$_delinq_window" "$FIRST_DELINQUENT_TIME" \
        "$LAST_LIVENESS_ACTIVE_TIME" "$_liveness_first_vote" "$LAST_TAKEOVER_TIME" "$(cat "$ID_FILE")"
  )
}
field(){ printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

echo "============================================="
echo "  STANDBY take/give-back timeout handling (v0.6.9 H4)"
echo "============================================="

# ── (T-a) take wedged but APPLIED → success + warn ────────────────────────────────────────────
echo ""; echo "─── (T-a) take set-identity rc 124 but APPLIED → TOOK STAKED ✅ + ⚠️ wedged warn ───"
out=$(scenario "$STANDBY" take 124 0 0 1 true)
if [[ "$(field "$out" rc)" == "0" && "$out" == *"TOOK STAKED ✅"* && "$out" == *"admin socket wedged"* && "$(field "$out" kills)" == "0" ]]; then
    ok "(T-a) applied-despite-wedge → success, wedged ⚠️ page, no kill"
else
    bad "(T-a) wrong: $out"
fi

# ── (T-b) take wedged, NOT applied → TAKEOVER FAILED, episode intact (N9), no kill ────────────
echo ""; echo "─── (T-b) take rc 124, NOT applied → TAKEOVER FAILED ❌, episode state intact (N9) ───"
out=$(scenario "$STANDBY" take 124 124 0 0 true)
if [[ "$(field "$out" rc)" == "1" && "$out" == *"TAKEOVER FAILED ❌"* \
      && "$(field "$out" window)" == "1111111111" && "$(field "$out" first)" == "12345" \
      && "$(field "$out" lla)" == "777" && "$(field "$out" lfv)" == "9000" \
      && "$(field "$out" ltt)" != "0" && "$(field "$out" kills)" == "0" ]]; then
    ok "(T-b) failed take kept window/anchors/liveness sample armed, set the cooldown, never killed"
else
    bad "(T-b) wrong: $out"
fi

# ── (T-c) voter-add times out after a good take → success + 'voting may not start' warn ───────
echo ""; echo "─── (T-c) authorized-voter add rc 124 after a good set-identity → ✅ + ⚠️ ───"
out=$(scenario "$STANDBY" take 0 124 0 1 true)
if [[ "$(field "$out" rc)" == "0" && "$out" == *"TOOK STAKED ✅"* && "$out" == *"voting may not start"* ]]; then
    ok "(T-c) add-wedge → identity state stands, ⚠️ page says voting may not start"
else
    bad "(T-c) wrong: $out"
fi

# ── (T-d) give-back wedged, still staked → 🚨 page + escalation ───────────────────────────────
echo ""; echo "─── (T-d) give-back rc 124, identity STILL STAKED → 🚨 page + hard-stop escalation ───"
out=$(scenario "$STANDBY" giveback 124 0 0 0 true)
if [[ "$out" == *"HOLDER MAY STILL BE VOTING 🚨"* && "$(field "$out" kills)" -ge 1 && "$out" == *"HARD STOP"* ]]; then
    ok "(T-d1) still-staked page fired and the hard-stop escalation killed the validator"
else
    bad "(T-d1) wrong: $out"
fi
out=$(scenario "$STANDBY" giveback 124 0 0 0 false)
if [[ "$out" == *"HOLDER MAY STILL BE VOTING 🚨"* && "$out" == *"NO HARD STOP"* && "$(field "$out" kills)" == "0" ]]; then
    ok "(T-d2) hard-stop disabled → still-staked 🚨 + NO HARD STOP page, no kill (operator must act)"
else
    bad "(T-d2) wrong: $out"
fi

# ── (T-e) give-back wedged but APPLIED → success-with-warn ────────────────────────────────────
echo ""; echo "─── (T-e) give-back rc 124 but APPLIED → GAVE BACK ✅ + ⚠️ verify-health ───"
out=$(scenario "$STANDBY" giveback 124 0 0 1 true)
if [[ "$(field "$out" rc)" == "0" && "$out" == *"GAVE BACK — unstaked ✅"* && "$out" == *"verify node health"* && "$(field "$out" kills)" == "0" ]]; then
    ok "(T-e) applied-despite-wedge give-back → success + ⚠️, no kill"
else
    bad "(T-e) wrong: $out"
fi

# ── (T-f) NON-VACUOUS control: strip the bound → the wedge observables disappear ─────────────
echo ""; echo "─── (T-f) control: sed-strip 'timeout -k 5 \"\$SETIDENTITY_TIMEOUT\"' → no wedge detection ───"
PATCHED=$(mktemp)
sed 's/timeout -k 5 "\$SETIDENTITY_TIMEOUT" //g' "$STANDBY" > "$PATCHED"
# same T-a inputs — but with the bound stripped the CLI runs unwrapped: our `timeout` mock is never hit,
# so the rc-124 wedge can never be observed (the pre-H4 blindness). The take still "succeeds" via the
# re-read, but WITHOUT the ⚠️ wedged warn — the fix's observable vanishes → T-a is non-vacuous.
out=$(scenario "$PATCHED" take 124 0 0 1 true)
rm -f "$PATCHED"
if [[ "$out" != *"admin socket wedged"* ]]; then
    ok "(T-f) patched (unbounded) copy shows NO wedge detection on the same inputs → the H4 bound is load-bearing"
else
    bad "(T-f) patched copy still detected the wedge — control is vacuous: $out"
fi

# ── (T-g) structural: v0.6.8 take/give-back had zero bounded calls ────────────────────────────
echo ""; echo "─── (T-g) v0.6.8 baseline: unbounded take/give-back (the H4 gap) ───"
if [[ -f "$V068" ]]; then
    v8=$(sed -n '/^take_staked_identity/,/^}/p; /^give_back_identity/,/^}/p' "$V068" | grep -c 'timeout')
    [[ $v8 -eq 0 ]] && ok "(T-g) v0.6.8 take/give-back had 0 'timeout' bounds → H4 genuinely new" \
                    || bad "(T-g) v0.6.8 already bounded ($v8)"
else
    ok "(T-g) v0.6.8 baseline not present to compare (skipped)"
fi

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
