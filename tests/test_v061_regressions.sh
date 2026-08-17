#!/bin/bash
# v0.6.1 regression tests — exercise the SHIPPED standby/primary code, not copies.
#
#   F1  Tier 3 with a 429 / HTML / Cloudflare body → return 2 (unreachable), not 1.
#   F2  Full triggered window + both externals down → window PRESERVED after
#       attempt_takeover (no reset, turbo kept, no takeover).
#   F2  One external back + delinquent → takeover PROCEEDS (no re-accumulation).
#   F6  Bad window config (THRESHOLD>SIZE, SIZE=0) → startup validation exits 1.

set +e

PASS=0; FAIL=0
ok()   { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
PRIMARY="$DIR/solana-primary-failover.sh"
[[ -f "$STANDBY" ]] || { echo "  ❌ standby not found at $STANDBY"; exit 1; }
[[ -f "$PRIMARY" ]] || { echo "  ❌ primary not found at $PRIMARY"; exit 1; }

# Load standby functions only (everything up to the MAIN LOOP banner).
SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock
rm -f "$SRC"

# Offline, visible logging.
log_info()   { echo "      [INFO] $*"; }
log_warn()   { echo "      [WARN] $*"; }
log_error()  { echo "      [ERR ] $*"; }
alert_info() { echo "      [ALERT] $*"; }
alert_warn() { echo "      [ALERT] $*"; }   # v0.6.4: fence-not-clear warning routes via alert_warn

echo "============================================="
echo "  v0.6.1 regression tests"
echo "============================================="

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "─── F1: Tier 3 validates .result (429/HTML body → 2) ───"
TIER3_RPC="http://t3"
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"

# A 429 error body delivered with HTTP 200 (public-RPC throttle) — no .result key.
_BODY='{"error":{"code":429,"message":"Too Many Requests"}}'
curl() { printf '%s' "$_BODY"; return 0; }
tier3_confirm_delinquency; rc=$?
[[ $rc -eq 2 ]] && ok "429 JSON error body → 2 (got $rc)" || bad "429 body should be 2, got $rc"

_BODY='<html><head><title>1020</title></head><body>Cloudflare</body></html>'
tier3_confirm_delinquency; rc=$?
[[ $rc -eq 2 ]] && ok "HTML/Cloudflare body → 2 (got $rc)" || bad "HTML body should be 2, got $rc"

# Sanity: a real delinquent .result still returns 0 (no false negative from the guard).
_BODY='{"jsonrpc":"2.0","result":{"current":[],"delinquent":[{"votePubkey":"VotePubkey1111111111111111111111111111111","nodePubkey":"StakedPubkey111111111111111111111111111111"}]},"id":1}'
tier3_confirm_delinquency; rc=$?
[[ $rc -eq 0 ]] && ok "valid delinquent .result → 0 (got $rc)" || bad "valid delinquent should be 0, got $rc"
unset -f curl

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "─── F2: hold through both-down → throttle re-confirm → take over on recovery ───"
# Instrument the external tiers + gossip + takeover so we can assert throttle scope.
# tier2 is always queried first when TIER2_RPC is set, so its call count == confirm attempts.
_confirm_calls=0; _gossip_calls=0; _took=0
_T2RC=2; _T3RC=2; _GOSSIPRC=0          # _GOSSIPRC: 0=gossip clear(safe), 1=PRIMARY still in gossip(block)
tier2_check_delinquency()        { _confirm_calls=$((_confirm_calls+1)); return $_T2RC; }
tier3_confirm_delinquency()      { return $_T3RC; }
check_primary_dropped_identity() { _gossip_calls=$((_gossip_calls+1)); return $_GOSSIPRC; }
staked_is_actively_voting()      { return 1; }   # v0.6.2: neutralize the liveness fence (clear) — this test exercises the F2 throttle/window, not the fence
take_staked_identity()           { _took=1; return 0; }
# v0.7 (Block 3, slice 4): this section tests the F2 throttle/window mechanics in ISOLATION. The
# slice-4 blindness-is-life rule (a could-not-confirm cycle re-anchors the takeover countdown) and
# the observation-span floor would otherwise dominate these timelines — both have their own suite
# (test_blindness_is_life.sh). Neuter them here so the F2 assertions keep testing the throttle.
get_staked_liveness_sample()     { echo "100 200"; }   # the hoisted A9a capture always samples → never a blind cycle
_note_blind_cycle()              { :; }                # blind stamps off (pre-slice-4 anchor behavior)
VOTE_LIVENESS_MIN_SPAN=0                               # span floor off (episode spans here are synthetic)

DELINQUENCY_WINDOW_SIZE=10; DELINQUENCY_WINDOW_THRESHOLD=7
EXTERNAL_CONFIRM_THROTTLE=12; TAKEOVER_DELAY=60; TAKEOVER_COOLDOWN=120
ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN=false; GOSSIP_VERIFY=true
TIER2_RPC="http://t2"; LAST_TAKEOVER_TIME=0; TG_ENABLED=false
_delinq_window="1111111111"; _turbo_mode=true; _current_interval=1
FIRST_DELINQUENT_TIME=$(( $(date +%s) - 100 ))   # delay (60s) already served
_last_confirm_attempt=0; _takeover_alert_sent=""; _gossip_prefetched=false

# Step 1: both externals down (r==2) → HOLD, window preserved, throttle armed.
attempt_takeover; rc=$?
[[ "$_delinq_window" == "1111111111" ]] && ok "1) window preserved on both-down" || bad "window changed to [$_delinq_window]"
window_triggered && ok "1) window still triggered (no re-accumulation needed)" || bad "window no longer triggered"
[[ "$_turbo_mode" == "true" ]] && ok "1) turbo still on" || bad "turbo dropped"
[[ "$_took" -eq 0 ]] && ok "1) no takeover (held)" || bad "takeover despite both externals down"
[[ "$_confirm_calls" -eq 1 ]] && ok "1) external confirm attempted once" || bad "confirm calls=$_confirm_calls"
[[ "$_last_confirm_attempt" -gt 0 ]] && ok "1) throttle armed by r==2" || bad "throttle not armed on r==2"

# Step 2: externals come back (r==0) but throttle still active → re-confirm SKIPPED, still held.
_T2RC=0
attempt_takeover; rc=$?
[[ "$_confirm_calls" -eq 1 ]] && ok "2) throttled: external not re-queried within window" || bad "confirm calls=$_confirm_calls (throttle leaked)"
[[ "$_took" -eq 0 ]] && ok "2) no takeover while throttled" || bad "takeover during throttle"
[[ "$_delinq_window" == "1111111111" ]] && ok "2) window still preserved through throttle" || bad "window changed during throttle"

# Step 3: throttle expires → external confirms (r==0), gossip clear → takeover on the FULL window.
_last_confirm_attempt=$(( $(date +%s) - 20 ))    # older than EXTERNAL_CONFIRM_THROTTLE
_GOSSIPRC=0
attempt_takeover; rc=$?
[[ "$_confirm_calls" -eq 2 ]] && ok "3) external re-queried after throttle expiry" || bad "confirm calls=$_confirm_calls"
[[ "$_took" -eq 1 ]] && ok "3) takeover proceeded on the preserved window (no re-accumulation)" || bad "no takeover (_took=$_took rc=$rc)"

# Step 4 (throttle scoping, retargeted for v0.6.3): confirmed (r==0) but the AUTHORITATIVE
# vote-liveness fence blocks (cannot-determine) → the fence must be re-evaluated EVERY cycle. r==0
# must NOT arm the throttle, else a holder that stops voting is missed for ~12s. (v0.6.2 used gossip
# as the blocking fence here; gossip is now advisory, so we assert on the liveness fence instead.)
_confirm_calls=0; _liveness_calls=0; _took=0
_T2RC=0; _GOSSIPRC=0    # gossip advisory (clear); liveness is the fence under test
staked_is_actively_voting() { _liveness_calls=$((_liveness_calls+1)); return 2; }   # cannot determine → BLOCK
_last_confirm_attempt=0; _takeover_alert_sent=""; _gossip_prefetched=false
_delinq_window="1111111111"; _turbo_mode=true
FIRST_DELINQUENT_TIME=$(( $(date +%s) - 100 )); LAST_TAKEOVER_TIME=0
attempt_takeover >/dev/null; attempt_takeover >/dev/null   # two consecutive cycles
[[ "$_liveness_calls" -eq 2 ]] && ok "4) liveness re-checked every cycle when confirmed-but-blocked (r==0 not throttled)" || bad "liveness checked $_liveness_calls/2 times (throttle wrongly armed on r==0)"
[[ "$_took" -eq 0 ]] && ok "4) no takeover while vote-liveness cannot confirm frozen" || bad "takeover despite liveness block"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "─── F6: bad window config exits at startup validation (real shipped lines) ───"
# Extract the exact validation block from each script and run it standalone.
extract_f6() { awk '/DELINQUENCY_WINDOW_SIZE" =~/{p=1} p{print} /Bad window config: require/{exit}' "$1"; }

run_f6() {   # script, SIZE, THRESHOLD  → returns the block's exit code
    local f; f=$(mktemp)
    {
        echo 'log_error(){ echo "      [ERR ] $*"; }'
        printf "DELINQUENCY_WINDOW_SIZE='%s'\n" "$2"
        printf "DELINQUENCY_WINDOW_THRESHOLD='%s'\n" "$3"
        extract_f6 "$1"
        echo 'exit 0'
    } > "$f"
    bash "$f"; local rc=$?
    rm -f "$f"
    return $rc
}

for script in "$STANDBY" "$PRIMARY"; do
    name=$(basename "$script")
    run_f6 "$script" 10 7;  [[ $? -eq 0 ]] && ok "$name: valid 7/10 accepted" || bad "$name: valid 7/10 rejected"
    run_f6 "$script" 10 11; [[ $? -eq 1 ]] && ok "$name: THRESHOLD>SIZE (11/10) exits 1" || bad "$name: THRESHOLD>SIZE not rejected"
    run_f6 "$script" 0 0;   [[ $? -eq 1 ]] && ok "$name: SIZE=0 exits 1" || bad "$name: SIZE=0 not rejected"
    run_f6 "$script" 08 07; [[ $? -eq 0 ]] && ok "$name: leading-zero 08/07 accepted (no octal crash)" || bad "$name: 08/07 wrongly rejected (octal)"
done

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
