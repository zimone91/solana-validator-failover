#!/bin/bash
# Unit test: staked_is_actively_voting() — v0.6.2 (C1) vote-liveness fence.
#   return 0 = voting (BLOCK)   1 = frozen/not voting (ALLOW)   2 = cannot determine (BLOCK)
# Sources the real functions and mocks curl to return a getVoteAccounts doc with a
# controllable lastVote for the staked vote account.

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

VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
TIER2_RPC="http://mock-t2"
TIER3_RPC="http://mock-t3"
VOTE_LIVENESS_EPSILON=2
VOTE_LIVENESS_MIN_INTERVAL=10

log_info()  { echo "      [INFO] $*"; }
log_warn()  { echo "      [WARN] $*"; }

# Mock curl: a single getVoteAccounts doc carrying TWO vote accounts —
#   the staked account with lastVote=$_MOCK_LV, and a second "cluster" account with
#   lastVote=$_MOCK_TIP. The v0.6.3 freshness reference is the cluster-wide MAX lastVote computed
#   from THIS payload, so $_MOCK_TIP (kept >> $_MOCK_LV) is that reference. Empty $_MOCK_LV simulates
#   both external RPCs being unreachable. Each scenario bumps $_MOCK_TIP before the second sample so
#   the reference advances (a fresh view); leaving it unchanged simulates a stale/cached view.
_MOCK_LV=100
_MOCK_TIP=500000
curl() {
    [[ -z "$_MOCK_LV" ]] && return 7
    printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"%s","lastVote":%s},{"votePubkey":"ClusterVote111","lastVote":%s}],"delinquent":[]},"id":1}' \
        "$VOTE_PUBKEY" "$_MOCK_LV" "${_MOCK_TIP:-0}"
    return 0
}

reset_samples() { _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; }
age_first_sample() { _liveness_first_ts=$(( $(date +%s) - VOTE_LIVENESS_MIN_INTERVAL - 5 )); }  # force interval elapsed

echo "============================================="
echo "  Vote-liveness fence unit tests (v0.6.2 C1 / v0.6.3 freshness guard)"
echo "============================================="

# 1. lastVote ADVANCING across samples → BLOCK
echo ""; echo "─── 1. lastVote advancing → BLOCK ───"
reset_samples; _MOCK_LV=1000; _MOCK_TIP=500000
staked_is_actively_voting; r=$?
[[ $r -eq 2 ]] && ok "first sample recorded, returns 2 (needs a second)" || bad "first call rc=$r (want 2)"
age_first_sample; _MOCK_LV=1050; _MOCK_TIP=500300   # +50 slots (> epsilon), tip advanced
staked_is_actively_voting; r=$?
[[ $r -eq 0 ]] && ok "advanced 50 slots → holder voting → BLOCK (rc=0)" || bad "advancing rc=$r (want 0)"

# 2. lastVote FROZEN across samples (tip advancing) → ALLOW
echo ""; echo "─── 2. lastVote frozen + tip advancing → ALLOW ───"
reset_samples; _MOCK_LV=2000; _MOCK_TIP=500000
staked_is_actively_voting >/dev/null
age_first_sample; _MOCK_LV=2000; _MOCK_TIP=500300   # lastVote unchanged, tip advanced
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "frozen (Δ0) with fresh RPC → not voting → ALLOW (rc=1)" || bad "frozen rc=$r (want 1)"

reset_samples; _MOCK_LV=3000; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first_sample; _MOCK_LV=3002; _MOCK_TIP=500300   # +2 == epsilon, not strictly greater; tip advanced
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "Δ2 (== epsilon, not >) → frozen → ALLOW (rc=1)" || bad "Δepsilon rc=$r (want 1)"

# 3. EXTERNAL RPC UNAVAILABLE → BLOCK
echo ""; echo "─── 3. external RPC unavailable → BLOCK ───"
reset_samples; _MOCK_LV=""
staked_is_actively_voting; r=$?
[[ $r -eq 2 ]] && ok "externals down → cannot determine → BLOCK (rc=2)" || bad "externals-down rc=$r (want 2)"

# 4. samples too close in time → BLOCK (need a real interval for a reliable delta)
echo ""; echo "─── 4. samples too close in time → BLOCK ───"
reset_samples; _MOCK_LV=4000; _MOCK_TIP=500000
staked_is_actively_voting >/dev/null      # first sample, ts = now
_MOCK_LV=4100; _MOCK_TIP=500300           # advanced, but elapsed ~0 < MIN_INTERVAL
staked_is_actively_voting; r=$?
[[ $r -eq 2 ]] && ok "interval < MIN_INTERVAL → wait → BLOCK (rc=2)" || bad "too-soon rc=$r (want 2)"

# 5. holder voted early then DIED (frozen now) → self-corrects to ALLOW after a re-based interval
echo ""; echo "─── 5. holder voted then froze → self-corrects to ALLOW ───"
reset_samples; _MOCK_LV=5000; _MOCK_TIP=500000
staked_is_actively_voting >/dev/null      # first=5000
age_first_sample; _MOCK_LV=5200; _MOCK_TIP=500300   # voted +200 during delay → BLOCK + re-base
staked_is_actively_voting; r=$?
[[ $r -eq 0 ]] && ok "still-advancing seen → BLOCK + re-base (rc=0)" || bad "rebase step rc=$r (want 0)"
age_first_sample; _MOCK_LV=5200; _MOCK_TIP=500600   # now frozen since re-base; tip still advancing
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "frozen after re-base → ALLOW (no permanent false block) (rc=1)" || bad "self-correct rc=$r (want 1)"

# 5b. RPC-FRESHNESS GUARD (v0.6.3): lastVote frozen BUT the external tip did NOT advance →
#     the RPC is stalled/cached, the "frozen" reading is meaningless → cannot determine → BLOCK.
#     This is the stalled/cached-RPC false-freeze → false-ALLOW double-sign hole. Non-vacuous:
#     removing the tip guard makes this return 1 (ALLOW) and the test fails.
echo ""; echo "─── 5b. external tip STALLED (cached RPC) → cannot determine → BLOCK ───"
reset_samples; _MOCK_LV=6000; _MOCK_TIP=600000
staked_is_actively_voting >/dev/null      # first sample lastVote=6000 tip=600000
age_first_sample; _MOCK_LV=6000; _MOCK_TIP=600000   # BOTH frozen — RPC not advancing
staked_is_actively_voting; r=$?
[[ $r -eq 2 ]] && ok "frozen lastVote + NON-advancing tip → cannot determine → BLOCK (rc=2), not false ALLOW" || bad "stalled-tip rc=$r (want 2 — false ALLOW risk!)"

# 6. startup config validation — a typo'd EPSILON/MIN_INTERVAL must NOT silently disable the
#    fence; the real shipped validation block must reject it at startup (exit 1).
echo ""; echo "─── 6. startup rejects bad vote-liveness config (real shipped lines) ───"
extract_cfg() { awk '/v0.6.2 \(C1\): validate the vote-liveness knobs/{p=1} p{print} /Bad vote-liveness config/{exit}' "$STANDBY"; }
run_cfg() {   # eps, interval → exit code of the shipped validation block
    local f; f=$(mktemp)
    { echo 'log_error(){ echo "      [ERR ] $*"; }'
      printf "VOTE_LIVENESS_EPSILON='%s'\n" "$1"
      printf "VOTE_LIVENESS_MIN_INTERVAL='%s'\n" "$2"
      extract_cfg
      echo 'exit 0'
    } > "$f"
    bash "$f"; local rc=$?; rm -f "$f"; return $rc
}
run_cfg 2 10;       [[ $? -eq 0 ]] && ok "valid 2/10 accepted"                  || bad "valid 2/10 rejected"
run_cfg 200000 10;  [[ $? -eq 1 ]] && ok "huge EPSILON typo exits 1"            || bad "huge epsilon not rejected"
run_cfg 08 10;      [[ $? -eq 0 ]] && ok "leading-zero EPSILON (08) octal-safe" || bad "08 epsilon wrongly rejected"
run_cfg 2 4;        [[ $? -eq 1 ]] && ok "MIN_INTERVAL<5 exits 1"               || bad "tiny interval not rejected"
run_cfg 10 10;      [[ $? -eq 1 ]] && ok "MIN_INTERVAL not > EPSILON exits 1"   || bad "interval<=epsilon not rejected"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
