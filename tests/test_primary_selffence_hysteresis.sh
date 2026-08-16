#!/bin/bash
# v0.6.8 (B2): N6 own-vote-lag reset HYSTERESIS + the EPSILON<<band startup assert.
# The v0.6.7 N6 zeroed its sustain timer on a SINGLE sub-threshold cycle, so a flapping/intermittent
# egress that lands one vote burst per < SECS re-zeroed it every cycle and N6 NEVER fired (wedged-but-
# alive hole, Audit-1 B2). Now the timer is cleared only after SELF_FENCE_VOTE_LAG_RESET_CYCLES (>=2)
# CONSECUTIVE healthy cycles — "sustained-dominant", which a burst flap cannot dodge.
#   (H-a) armed timer + ONE healthy dip            → timer NOT cleared; healthy=1 (was: cleared)
#   (H-b) K consecutive healthy cycles             → timer cleared (since=0); healthy capped at K
#   (H-c) over-threshold cycle                      → healthy streak reset to 0 (timer stays armed)
#   (H-d) FLAP (old timer, 1 dip, then over-thresh) → FIRES (the single dip did not save the holder)
#   (H-e) NON-VACUOUS control: RESET_CYCLES=1       → same flap does NOT fire (old one-cycle-reset bug)
#   (H-f) genuine recovery (K healthy) then lag     → needs the full SECS again (no instant re-fire)
#   (EPS-pass) EPSILON=2,  band=32                  → validate_numeric_config OK
#   (EPS-fail) EPSILON=20, band=32                  → validate_numeric_config EXITS 1 (20*4 > 32)
#   (EPS-skip) band=0                               → assert skipped (rc 0) even with a large EPSILON

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$PRIMARY" && -f "$STANDBY" ]] || { echo "  ❌ scripts not found"; exit 1; }

SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"; rm -f "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock

STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_NOANSWER_SECS=0
SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
TG_ENABLED=false
log_info() { :; }; log_warn() { :; }; log_error() { :; }
send_telegram() { return 0; }; send_webhook() { :; }

_LOCAL_SLOT=100000; _CLUSTER_MAX=100000; _OWN_LV=99995; _OWN_PRESENT=1; _OWN_ARRAY=current
_va_json() {
    local cur='{"votePubkey":"ClusterVoter11111111111111111111111111","lastVote":'"$_CLUSTER_MAX"'}' del=''
    if [[ "$_OWN_PRESENT" -eq 1 ]]; then
        local own='{"votePubkey":"'"$VOTE_PUBKEY"'","lastVote":'"$_OWN_LV"'}'
        if [[ "$_OWN_ARRAY" == "delinquent" ]]; then del="$own"; else cur="$cur,$own"; fi
    fi
    printf '{"jsonrpc":"2.0","result":{"current":[%s],"delinquent":[%s]},"id":1}' "$cur" "$del"
}
curl() {
    local data=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { data="$2"; shift 2; continue; }; shift; done
    case "$data" in
        *getVoteAccounts*) _va_json; return 0 ;;
        *getSlot*)   printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$_LOCAL_SLOT"; return 0 ;;
        *getHealth*) printf '{"jsonrpc":"2.0","result":"ok","id":1}'; return 0 ;;
    esac
    return 7
}
NOW() { date +%s; }
adv() { _last_confirmed_slot=$(( _LOCAL_SLOT - 50 )); _last_confirmed_advance_ts=$(NOW); }   # slot advancing → frozen check clears

_fence_calls=0
switch_to_unstaked() { _fence_calls=$((_fence_calls+1)); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
alert() { :; }
healthy() { _CLUSTER_MAX=100000; _OWN_LV=99995; _LOCAL_SLOT=100000; adv; }      # vlag 5 <= 32
overthr() { _CLUSTER_MAX=100100; _OWN_LV=100000; _OWN_ARRAY=delinquent; _LOCAL_SLOT=100100; adv; }  # vlag 100 > 32

echo "============================================="
echo "  PRIMARY N6 reset hysteresis + EPSILON<<band assert (v0.6.8 B2)"
echo "============================================="

# ── (H-a) one healthy dip must NOT clear an armed timer ────────────────────────────────────────
echo ""; echo "─── (H-a) armed timer + ONE healthy dip → timer NOT cleared (healthy=1) ───"
DRY_RUN=false; CURRENT_IDENTITY="$STAKED_PUBKEY"; _fence_calls=0
_selffence_votelag_baseline=1; _selffence_votelag_healthy=0
armed=$(( $(NOW) - 10 )); _selffence_votelag_since=$armed     # armed, but vlsust < SECS so it won't fire
healthy; check_self_fence_isolation
[[ "$_selffence_votelag_since" -eq "$armed" && "$_selffence_votelag_healthy" -eq 1 && $_fence_calls -eq 0 ]] \
    && ok "(H-a) single healthy dip kept the timer armed (since unchanged), healthy=1 — no one-cycle wipe" \
    || bad "(H-a) timer wiped or wrong (since=$_selffence_votelag_since want=$armed healthy=$_selffence_votelag_healthy fired=$_fence_calls)"

# ── (H-b) K consecutive healthy cycles clear the timer ────────────────────────────────────────
echo ""; echo "─── (H-b) ${SELF_FENCE_VOTE_LAG_RESET_CYCLES} consecutive healthy cycles → timer cleared (since=0) ───"
_selffence_votelag_baseline=1; _selffence_votelag_healthy=0; _selffence_votelag_since=$(( $(NOW) - 10 ))
for _ in $(seq 1 "$SELF_FENCE_VOTE_LAG_RESET_CYCLES"); do healthy; check_self_fence_isolation; done
[[ "$_selffence_votelag_since" -eq 0 && "$_selffence_votelag_healthy" -eq "$SELF_FENCE_VOTE_LAG_RESET_CYCLES" ]] \
    && ok "(H-b) ${SELF_FENCE_VOTE_LAG_RESET_CYCLES} consecutive healthy → timer cleared, healthy capped at K" \
    || bad "(H-b) did not clear after K (since=$_selffence_votelag_since healthy=$_selffence_votelag_healthy)"

# ── (H-c) an over-threshold cycle breaks the healthy streak ───────────────────────────────────
echo ""; echo "─── (H-c) over-threshold cycle → healthy streak reset to 0 (timer stays armed) ───"
_fence_calls=0; _selffence_votelag_baseline=1; _selffence_votelag_healthy=2
_selffence_votelag_since=$(( $(NOW) ))     # recent → vlsust ~0 < SECS, will not fire
overthr; check_self_fence_isolation
[[ "$_selffence_votelag_healthy" -eq 0 && "$_selffence_votelag_since" -ne 0 && $_fence_calls -eq 0 ]] \
    && ok "(H-c) over-threshold reset the healthy streak to 0, timer still armed, no premature fire" \
    || bad "(H-c) wrong (healthy=$_selffence_votelag_healthy since=$_selffence_votelag_since fired=$_fence_calls)"

# ── (H-d) the FLAP fires under hysteresis (dip did not save the holder) ───────────────────────
echo ""; echo "─── (H-d) old timer + 1 healthy dip + over-threshold → FIRES (flap defeated) ───"
_fence_calls=0; _selffence_votelag_baseline=1; _selffence_votelag_healthy=0
_selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 5 ))   # already sustained >= SECS
healthy;  check_self_fence_isolation     # dip → healthy=1 (<3), since unchanged, no fire
overthr;  check_self_fence_isolation     # over threshold again → vlsust still >= SECS → FIRES
[[ $_fence_calls -ge 1 ]] \
    && ok "(H-d) flap fired N6 ($_fence_calls) — a single burst dip no longer resets the sustain timer" \
    || bad "(H-d) flap evaded N6 ($_fence_calls fires) — hysteresis not effective"

# ── (H-e) NON-VACUOUS control: RESET_CYCLES=1 (old behavior) → flap evades ────────────────────
echo ""; echo "─── (H-e) control: SELF_FENCE_VOTE_LAG_RESET_CYCLES=1 (no hysteresis) → flap does NOT fire ───"
_fence_calls=0; SELF_FENCE_VOTE_LAG_RESET_CYCLES=1
_selffence_votelag_baseline=1; _selffence_votelag_healthy=0
_selffence_votelag_since=$(( $(NOW) - SELF_FENCE_VOTE_LAG_SECS - 5 ))
healthy;  check_self_fence_isolation     # dip → healthy=1 >= 1 → since CLEARED (old one-cycle reset)
overthr;  check_self_fence_isolation     # over threshold → since re-armed to now → vlsust ~0 → no fire
SELF_FENCE_VOTE_LAG_RESET_CYCLES=3       # restore
[[ $_fence_calls -eq 0 ]] \
    && ok "(H-e) with cycles=1 the flap re-zeroed the timer and N6 never fired → the H-d test is non-vacuous" \
    || bad "(H-e) control fired ($_fence_calls) — expected the old one-cycle reset to let the flap win"

# ── (H-f) genuine recovery: K healthy clears, then a fresh lag needs the FULL SECS again ───────
echo ""; echo "─── (H-f) genuine recovery (K healthy) then lag → no instant re-fire (full SECS required) ───"
_fence_calls=0; _selffence_votelag_baseline=1; _selffence_votelag_healthy=0
_selffence_votelag_since=$(( $(NOW) - 10 ))
for _ in $(seq 1 "$SELF_FENCE_VOTE_LAG_RESET_CYCLES"); do healthy; check_self_fence_isolation; done   # since→0
overthr; check_self_fence_isolation       # lag returns → timer re-armed at now → vlsust ~0 → no fire yet
[[ $_fence_calls -eq 0 && "$_selffence_votelag_since" -ne 0 ]] \
    && ok "(H-f) recovery cleared the timer; a fresh lag re-arms and must sustain the full SECS (no instant fire)" \
    || bad "(H-f) recovery/re-arm wrong (fired=$_fence_calls since=$_selffence_votelag_since)"

# ════════ EPSILON << band startup assert (standby validate_numeric_config) ════════
echo ""; echo "─── (EPS) VOTE_LIVENESS_EPSILON must be << EXPECTED_PRIMARY_VOTE_LAG_SLOTS (band/4) ───"
eps_validate() {   # run validate_numeric_config in a fresh subshell sourcing the standby; echo its rc
    local epsilon="$1" band="$2"
    (
        set +e
        S=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$S"
        # shellcheck disable=SC1090
        source "$S"; rm -f "$S"
        log_info() { :; }; log_warn() { :; }; log_error() { :; }
        VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_EPSILON="$epsilon"; EXPECTED_PRIMARY_VOTE_LAG_SLOTS="$band"
        validate_numeric_config
        echo "rc=$?"
    ) 2>/dev/null | grep -oE 'rc=[0-9]+' | tail -1
}
[[ "$(eps_validate 2 32)" == "rc=0" ]] \
    && ok "(EPS-pass) EPSILON=2, band=32 → validate OK (2*4=8 <= 32)" \
    || bad "(EPS-pass) EPSILON=2/band=32 was rejected (got $(eps_validate 2 32))"
[[ "$(eps_validate 20 32)" != "rc=0" ]] \
    && ok "(EPS-fail) EPSILON=20, band=32 → validate exits non-zero (20*4=80 > 32 → EPSILON not << band)" \
    || bad "(EPS-fail) EPSILON=20/band=32 was accepted — the assert did not fire"
[[ "$(eps_validate 20 0)" == "rc=0" ]] \
    && ok "(EPS-skip) band=0 → assert skipped (operator opt-out), rc 0 even with EPSILON=20" \
    || bad "(EPS-skip) band=0 did not skip the assert (got $(eps_validate 20 0))"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
