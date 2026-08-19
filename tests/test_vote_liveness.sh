#!/bin/bash
# Unit test: staked_is_actively_voting() — v0.6.2 (C1) vote-liveness fence.
#   return 0 = voting (BLOCK)   1 = frozen/not voting (ALLOW)   2 = cannot determine (BLOCK)
# Sources the real functions and mocks curl to return a getVoteAccounts doc with a
# controllable lastVote for the staked vote account.
#
# v0.7 (Block 3, slice 3 / AUDIT-5 A3): the suite now runs on the SOURCED shipped default
# VOTE_LIVENESS_EPSILON=0 (ANY forward movement of lastVote is life — safe ONLY on the slice-2
# provider-pinned pair). The old Δ≤2→ALLOW assertions are FLIPPED to Δ2/Δ1→VOTING/BLOCK, each with
# a non-vacuous control (ε=2 set EXPLICITLY reproduces the old ALLOW — the knob still works; the
# DEFAULT is what changed), plus the measured A3 scenario: a live holder voting +1/window under a
# single honest provider never reads FROZEN at ε=0 (at ε=2 it did, and the spare took → double-sign).

# harness: tests/lib/harness.sh — ok/bad+banners, paths, extract_region (the section-6 validate-knob
# region: the sed range is byte-faithful to the old awk-with-exit — verified — and cannot silently
# extract empty). Cut + printing log shadows + `date +%s` clock stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock
rm -f "$SRC"

VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
TIER2_RPC="http://mock-t2"
TIER3_RPC="http://mock-t3"
# v0.7 (Block 3, slice 3): VOTE_LIVENESS_EPSILON deliberately NOT set here — the suite exercises the
# SOURCED shipped default (asserted = 0 in section 0 below). Controls set ε=2 explicitly.
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

title_banner "Vote-liveness fence unit tests (v0.6.2 C1 / v0.6.3 freshness guard / v0.7 slice-3 ε=0)"

# 0. v0.7 (Block 3, slice 3 / AUDIT-5 A3): the shipped DEFAULT epsilon must be 0 and must be the
#    value this suite runs on (sourced from the daemon, not set by the harness).
echo ""; echo "─── 0. shipped default ε=0 (sourced, not harness-set) ───"
[[ "$VOTE_LIVENESS_EPSILON" == "0" ]] \
  && ok "sourced shipped default VOTE_LIVENESS_EPSILON=0" \
  || bad "sourced default ε='$VOTE_LIVENESS_EPSILON' (want 0 — slice 3 regressed, or the harness overrode it)"

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

# 2b. v0.7 (Block 3, slice 3 / AUDIT-5 A3): FLIPPED assertions. Under the old default ε=2, Δ2 and
#     Δ1 read FROZEN → ALLOW (measured: the spare TOOK under a live holder advancing +1..+2 per
#     window). Under the shipped default ε=0, ANY forward movement is VOTING → BLOCK.
echo ""; echo "─── 2b. slice 3: Δ2 and Δ1 are now VOTING → BLOCK (default ε=0) ───"
reset_samples; _MOCK_LV=3000; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first_sample; _MOCK_LV=3002; _MOCK_TIP=500300   # +2: the OLD default called this frozen
staked_is_actively_voting; r=$?
[[ $r -eq 0 ]] && ok "Δ2 > ε=0 → VOTING → BLOCK (rc=0) — the old default's false-FROZEN, closed" || bad "Δ2 rc=$r (want 0 — a still-voting holder read FROZEN)"
reset_samples; _MOCK_LV=3100; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first_sample; _MOCK_LV=3101; _MOCK_TIP=500300   # +1: the minimal life sign
staked_is_actively_voting; r=$?
[[ $r -eq 0 ]] && ok "Δ1 > ε=0 → VOTING → BLOCK (rc=0) — ANY forward movement is life" || bad "Δ1 rc=$r (want 0)"

# 2c. NON-VACUOUS CONTROLS: ε=2 set EXPLICITLY reproduces the old ALLOW on the SAME numbers — the
#     knob still works; what slice 3 changed is the DEFAULT.
echo ""; echo "─── 2c. CONTROLS: explicit ε=2 reproduces the old ALLOW (knob works; default changed) ───"
VOTE_LIVENESS_EPSILON=2
reset_samples; _MOCK_LV=3200; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first_sample; _MOCK_LV=3202; _MOCK_TIP=500300
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "control: ε=2 explicit, Δ2 (== ε, not >) → frozen → ALLOW (rc=1) — the old verdict reproduced" || bad "control Δ2 rc=$r (want 1 — the flip no longer exercises the old hole)"
reset_samples; _MOCK_LV=3300; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first_sample; _MOCK_LV=3301; _MOCK_TIP=500300
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "control: ε=2 explicit, Δ1 → frozen → ALLOW (rc=1) — the old verdict reproduced" || bad "control Δ1 rc=$r (want 1)"
VOTE_LIVENESS_EPSILON=0   # back to the shipped default (proven sourced in section 0)

# 2d. THE A3 MEASURED SCENARIO: a live holder voting SLOWLY — +1 slot per liveness window, single
#     honest provider, zero clock skew. At ε=0 EVERY window reads VOTING → BLOCK (the spare never
#     takes; measured: "at ε=0 it never took"). Control: the old default ε=2 reads the same holder
#     FROZEN → ALLOW — the measured false-FROZEN that TOOK under a live holder (double-sign).
echo ""; echo "─── 2d. A3 measured: holder advancing +1/window, single provider ───"
reset_samples; _MOCK_LV=9000; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first_sample; _MOCK_LV=9001; _MOCK_TIP=500300   # window 1: +1
staked_is_actively_voting; r1=$?
age_first_sample; _MOCK_LV=9002; _MOCK_TIP=500600   # window 2: +1 again (VOTING re-based to 9001)
staked_is_actively_voting; r2=$?
[[ $r1 -eq 0 && $r2 -eq 0 ]] \
  && ok "ε=0 default: +1/window reads VOTING → BLOCK on every window (rc=$r1,$r2) — the spare never takes" \
  || bad "ε=0 slow-voter rc=$r1,$r2 (want 0,0 — a live holder read FROZEN somewhere)"
VOTE_LIVENESS_EPSILON=2   # control: the old default on the same holder
reset_samples; _MOCK_LV=9100; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first_sample; _MOCK_LV=9101; _MOCK_TIP=500300   # +1 over the window
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "control: ε=2 reads the SAME +1/window holder FROZEN → ALLOW (rc=1) — the measured double-sign setup, reproduced" || bad "control rc=$r (want 1 — the A3 scenario no longer exercises the old hole)"
VOTE_LIVENESS_EPSILON=0   # back to the shipped default

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
extract_cfg() { extract_region "$STANDBY" 'v0.6.2 (C1): validate the vote-liveness knobs' 'Bad vote-liveness config'; }
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
run_cfg 0 10;       [[ $? -eq 0 ]] && ok "shipped default 0/10 accepted (EPSILON>=0)" || bad "shipped default 0/10 rejected"
run_cfg 2 10;       [[ $? -eq 0 ]] && ok "valid 2/10 accepted (hand-raised ε still allowed)" || bad "valid 2/10 rejected"
run_cfg 200000 10;  [[ $? -eq 1 ]] && ok "huge EPSILON typo exits 1"            || bad "huge epsilon not rejected"
run_cfg 08 10;      [[ $? -eq 0 ]] && ok "leading-zero EPSILON (08) octal-safe" || bad "08 epsilon wrongly rejected"
run_cfg 2 4;        [[ $? -eq 1 ]] && ok "MIN_INTERVAL<5 exits 1"               || bad "tiny interval not rejected"
run_cfg 10 10;      [[ $? -eq 1 ]] && ok "MIN_INTERVAL not > EPSILON exits 1"   || bad "interval<=epsilon not rejected"

results_banner
