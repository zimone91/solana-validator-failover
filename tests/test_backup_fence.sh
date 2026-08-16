#!/bin/bash
# BACKUP-role fence integration (v0.6.2 C2). BACKUP ships GOSSIP_VERIFY=false (gossip would
# false-block on a crashed STANDBY's stale entry), so the ONLY fence is vote-liveness. This
# test drives the real attempt_takeover with BACKUP config:
#   - a live holder still voting the staked identity  → BACKUP BLOCKED
#   - a dead holder (frozen lastVote)                 → BACKUP takes over after the delay
#   - liveness unavailable (externals down)           → BACKUP BLOCKED (invariant 3)

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$STANDBY" ]] || { echo "  ❌ standby not found at $STANDBY"; exit 1; }

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock
rm -f "$SRC"

# BACKUP config: gossip OFF, vote-liveness ON.
GOSSIP_VERIFY=false
VOTE_LIVENESS_VERIFY=true
VOTE_LIVENESS_EPSILON=2
VOTE_LIVENESS_MIN_INTERVAL=10
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
TIER2_RPC="http://mock-t2"
TG_ENABLED=false
DELINQUENCY_WINDOW_SIZE=10
DELINQUENCY_WINDOW_THRESHOLD=7
TAKEOVER_DELAY=120
TAKEOVER_COOLDOWN=120
EXTERNAL_CONFIRM_THROTTLE=12
ALERT_THROTTLE=600
_last_t2_alert=0

log_info()  { :; }
log_warn()  { :; }
alert_info() { :; }
alert_warn() { :; }   # v0.6.4: fence-not-clear warning routes via alert_warn

# External delinquency confirmation: confirmed (so we reach the fence).
tier2_check_delinquency()  { return 0; }
tier3_confirm_delinquency() { return 0; }
# Vote-liveness data source (mock the helper directly): "<lastVote> <tip>"; _MOCK_LV=""=externals down.
# v0.6.3: _MOCK_TIP advances so the RPC-freshness guard passes (its own test is test_vote_liveness).
_MOCK_LV=0
_MOCK_TIP=900000
get_staked_liveness_sample() { [[ -z "$_MOCK_LV" ]] && return 1; printf '%s %s\n' "$_MOCK_LV" "$_MOCK_TIP"; }
# Observe takeover without touching identity.
_took=0
take_staked_identity() { _took=1; return 0; }

# Prime a triggered, delay-passed episode with a back-dated liveness first sample (= $1).
prime() {
    LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _takeover_alert_sent=""
    _delinq_window="1111111111"; _turbo_mode=true
    FIRST_DELINQUENT_TIME=$(( $(date +%s) - TAKEOVER_DELAY - 40 ))    # delay already served
    LAST_LIVENESS_ACTIVE_TIME=0   # v0.6.7 (N3): fresh episode — daemon resets this in window_reset / main loop
    _liveness_first_vote="$1"; _liveness_first_tip=1; _liveness_first_ts=$(( $(date +%s) - VOTE_LIVENESS_MIN_INTERVAL - 20 ))
    _took=0
}

echo "============================================="
echo "  BACKUP-role vote-liveness fence (v0.6.2 C2)"
echo "============================================="

echo ""; echo "─── A. live holder still voting → BACKUP BLOCKED ───"
prime 1000; _MOCK_LV=1090            # +90 slots (> epsilon)
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 0 ]] && ok "BACKUP did NOT take over while holder is voting (rc=$rc)" \
                     || bad "BACKUP took the identity while it was actively voting — double-sign!"

echo ""; echo "─── B. dead holder (frozen lastVote) → BACKUP takes over ───"
prime 2000; _MOCK_LV=2000            # frozen
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 1 ]] && ok "BACKUP took over after delay once the holder stopped voting (rc=$rc)" \
                     || bad "BACKUP failed to take over a dead holder (_took=$_took rc=$rc)"

echo ""; echo "─── C. liveness unavailable (externals down) → BACKUP BLOCKED ───"
prime 3000; _MOCK_LV=""              # get_staked_last_vote → unavailable
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 0 ]] && ok "BACKUP did NOT take over when liveness is unknown (rc=$rc)" \
                     || bad "BACKUP took over with undetermined liveness — invariant 3 violated!"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
