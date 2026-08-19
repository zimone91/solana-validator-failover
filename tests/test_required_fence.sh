#!/bin/bash
# v0.6.3 (Block 1): vote-liveness is REQUIRED. Two guarantees, both proven here against the
# SHIPPED standby code (sourced functions + the real startup validation lines):
#   A) STARTUP refuses to run with VOTE_LIVENESS_VERIFY=false unless ALLOW_UNFENCED_TAKEOVER=true.
#   B) RUNTIME attempt_takeover does NOT take over with liveness off and no override (cannot
#      determine → BLOCK); with the explicit override it proceeds UNFENCED.
# Closes the old "both fences off → silent unfenced takeover with only a warning" hole.

# harness: tests/lib/harness.sh — ok/bad+banners, paths. extract_req KEEPS its awk (the region must
# EXCLUDE its end line — `load_state` would execute under a sed range, so sed is not byte-faithful);
# it gains the loud-empty check below instead (the extract_region contract without the sed form).

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock
rm -f "$SRC"

log_info()  { :; }
log_warn()  { :; }
alert_info() { :; }
alert_warn() { :; }   # v0.6.4: fence-not-clear warning routes via alert_warn

title_banner "Vote-liveness REQUIRED fence (v0.6.3 Block 1)"

# ── A. Startup validation (run the SHIPPED lines standalone) ─────────────────────────────────
echo ""; echo "─── A. startup refuses VOTE_LIVENESS_VERIFY=false without override ───"
extract_req() { awk '/REQUIRED — it is the authoritative split-brain fence/{p=1} /load_state   # v0.6.1/{p=0} p{print}' "$STANDBY"; }
# loud-empty guard (harness extract_region contract; the awk itself stays — see header):
[[ -n "$(extract_req)" ]] || { echo "  ❌ FAIL: extract_req: EMPTY extraction (startup-validation anchors moved) — run_req would exercise nothing"; FAIL=$((FAIL+1)); }
run_req() {   # VOTE_LIVENESS_VERIFY, ALLOW_UNFENCED_TAKEOVER → exit code of the shipped block
    local f; f=$(mktemp)
    { echo 'log_error(){ echo "      [ERR ] $*"; }'; echo 'log_warn(){ echo "      [WARN] $*"; }'
      printf "VOTE_LIVENESS_VERIFY='%s'\n" "$1"
      printf "ALLOW_UNFENCED_TAKEOVER='%s'\n" "$2"
      extract_req
      echo 'exit 0'
    } > "$f"
    bash "$f" >/dev/null 2>&1; local rc=$?; rm -f "$f"; return $rc
}
run_req true  false; [[ $? -eq 0 ]] && ok "liveness ON → starts"                                 || bad "liveness ON wrongly refused"
run_req false false; [[ $? -eq 1 ]] && ok "liveness OFF + no override → REFUSES to start (exit 1)" || bad "liveness OFF started UNFENCED — hole reopened!"
run_req false "";    [[ $? -eq 1 ]] && ok "liveness OFF + override unset → REFUSES to start"        || bad "liveness OFF (unset override) started unfenced"
run_req false true;  [[ $? -eq 0 ]] && ok "liveness OFF + explicit override → starts (unfenced)"    || bad "explicit override did not permit start"

# ── B. Runtime fence in attempt_takeover ─────────────────────────────────────────────────────
# Reach the fence: window triggered, delay served, external confirm = delinquent, gossip off.
GOSSIP_VERIFY=false
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
TIER2_RPC="http://mock-t2"; TG_ENABLED=false
DELINQUENCY_WINDOW_SIZE=10; DELINQUENCY_WINDOW_THRESHOLD=7
TAKEOVER_DELAY=20; TAKEOVER_COOLDOWN=120; EXTERNAL_CONFIRM_THROTTLE=12; ALERT_THROTTLE=600
_last_t2_alert=0
tier2_check_delinquency()  { return 0; }
tier3_confirm_delinquency() { return 0; }
_took=0
take_staked_identity() { _took=1; return 0; }
prime() {
    LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _takeover_alert_sent=""
    _delinq_window="1111111111"; _turbo_mode=true
    FIRST_DELINQUENT_TIME=$(( $(date +%s) - TAKEOVER_DELAY - 40 ))
    _took=0
}

echo ""; echo "─── B1. liveness OFF + no override → NO takeover (cannot determine → BLOCK) ───"
VOTE_LIVENESS_VERIFY=false; ALLOW_UNFENCED_TAKEOVER=false; prime
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 0 ]] && ok "unfenced takeover refused at runtime (rc=$rc)" \
                     || bad "took over with NO fence and no override — invariant violated!"

echo ""; echo "─── B2. liveness OFF + ALLOW_UNFENCED_TAKEOVER=true → takeover proceeds (UNFENCED) ───"
VOTE_LIVENESS_VERIFY=false; ALLOW_UNFENCED_TAKEOVER=true; prime
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 1 ]] && ok "explicit override permits the (dangerous) unfenced takeover (rc=$rc)" \
                     || bad "override set but takeover still blocked (_took=$_took rc=$rc)"

results_banner
