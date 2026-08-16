#!/bin/bash
# v0.7 (Block 3, slice 2): liveness PROVIDER PINNING (AUDIT-5 A2). The paired liveness samples used
# to discard WHICH provider answered: sample #1 from a fresh Tier-2, T2 hiccups, sample #2 falls
# through to a Tier-3 lagging ~29 slots → a live holder's advance collapses to Δ≈1 ≤ ε → false
# FROZEN → the spare takes under a live holder (double-sign). The fix pins the pair to the vantage
# that served sample #1 and voids ONLY the FROZEN verdict on a mismatch (re-pin + "cannot
# determine"); life signs (Δ > ε) stand on any provider mix. Drives the REAL shipped sampler +
# fence (source-to-MAIN-LOOP seam, URL-aware curl mock, controllable mono clock):
#   (a)  THE MEASURED A2 SCENARIO: T2 first sample, T2 dies, lagging-T3 second sample → mismatch
#        re-pins (min-rule baseline, current tip, fresh interval clock, new pin) and returns 2 —
#        no verdict, no take
#   (a2) NON-VACUOUS CONTROL (old code simulated: the pin forged equal — i.e. provider identity
#        discarded): the SAME numbers return 1 (FROZEN) — the double-sign verdict the pin kills
#   (b)  CONVERGENCE (reviewer req 1): after (a)'s re-pin to T3, a T3/T3 pair on a genuinely frozen
#        holder reads FROZEN after EXACTLY one VOTE_LIVENESS_MIN_INTERVAL — the block is not
#        eternal, and the pre-interval probe neither renders a verdict nor disturbs the re-pin
#   (c)  B2 MIN RULE (reviewer req 2): a burst observed before the flip stays remembered
#        (baseline = min(old, cur), NOT the naive adoption) → the next pair reads VOTING
#   (c2) CONTROL: the naive re-pin (baseline := current) reads FROZEN — the reopened B2 hole, proven
#   (d)  ASYMMETRY (reviewer req 3): Δ > ε across a T2→T3 flip → VOTING immediately (no re-pin),
#        and through the real attempt_takeover the N3 anchor (LAST_LIVENESS_ACTIVE_TIME) re-anchors
#   (e)  episode resets clear the pin (window_reset; the attempt_takeover prefetch pins the new
#        episode; the main-loop inline clear carries the provider field — textual, past the seam)
#   (f)  PRIMARY twin: the rpc-recovery fence re-pins/converges identically; reset_recovery_liveness
#        clears the pin
#   (g)  twin parity: the new pinning hunks are BYTE-IDENTICAL across both daemons

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
PRIMARY="$DIR/solana-primary-failover.sh"
[[ -f "$STANDBY" && -f "$PRIMARY" ]] || { echo "  ❌ scripts not found"; exit 1; }

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
rm -f "$SRC"

# Controllable SAFETY clock (house style: test_monotonic_timers / test_n3_takeover_anchor).
_SIM_NOW=100000
mono_now() { echo "$_SIM_NOW"; }

VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
VOTE_LIVENESS_EPSILON=2
VOTE_LIVENESS_MIN_INTERVAL=10
log_info()  { :; }
log_warn()  { :; }

# URL-aware curl mock: T2 and T3 are SEPARATE vantages with independent lastVote/tip views and
# independent up/down state, so the REAL get_staked_liveness_sample does the tier fallthrough and
# the tier labeling itself. Payload shape as in test_vote_liveness (staked account + a cluster
# account whose lastVote is the cluster-wide MAX = the freshness reference).
_T2_UP=1; _T2_LV=1000; _T2_TIP=100000
_T3_UP=1; _T3_LV=1000; _T3_TIP=100000
_payload() {   # $1 = staked lastVote, $2 = cluster tip
    printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"%s","lastVote":%s},{"votePubkey":"ClusterVote111","lastVote":%s}],"delinquent":[]},"id":1}' \
        "$VOTE_PUBKEY" "$1" "$2"
}
curl() {
    local a url=""
    for a in "$@"; do
        [[ "$a" == http* ]] && url="$a"
    done
    if [[ "$url" == *mock-t2* ]]; then
        [[ "$_T2_UP" == "1" ]] || return 7
        _payload "$_T2_LV" "$_T2_TIP"; return 0
    elif [[ "$url" == *mock-t3* ]]; then
        [[ "$_T3_UP" == "1" ]] || return 7
        _payload "$_T3_LV" "$_T3_TIP"; return 0
    fi
    return 7
}

reset_ep() { _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""; }

echo "============================================="
echo "  Liveness provider pinning (v0.7 Block 3 slice 2 / AUDIT-5 A2)"
echo "============================================="

# ── (a) THE MEASURED A2 SCENARIO ────────────────────────────────────────────────────────────────
# Holder voting SLOWLY (+30 slots over the window, cluster advances +30). Sample #1 from a fresh
# T2 (lastVote=1000 tip=100000). T2 dies. Sample #2 falls through to a T3 lagging 29 slots: its
# view shows lastVote=1001 tip=100001 → Δvote=1 ≤ ε=2 AND Δtip=+1 > 0 (the freshness guard is
# blind to the flip) — the pre-fix code called this FROZEN against a live holder.
echo ""; echo "─── (a) measured A2: T2-fresh / T3-lagging pair → re-pin, no verdict ───"
reset_ep
_SIM_NOW=100000
_T2_UP=1; _T2_LV=1000; _T2_TIP=100000
staked_is_actively_voting >/dev/null; r=$?
[[ $r -eq 2 && "$_liveness_first_provider" == "T2" ]] \
    && ok "(a0) first sample captured AND pinned to T2 (rc=2, pin=$_liveness_first_provider)" \
    || bad "(a0) first sample rc=$r pin='$_liveness_first_provider' (want rc=2 pin=T2)"

_SIM_NOW=100012                       # 12s later (> MIN_INTERVAL)
_T2_UP=0                              # T2 hiccups exactly at sample #2 — needs no misconfiguration
_T3_LV=1001; _T3_TIP=100001           # T3 lags 29 slots: true 1030/100030 reads as 1001/100001
staked_is_actively_voting; r=$?
[[ $r -eq 2 ]] && ok "(a1) provider flip on a frozen-candidate → rc=2 (cannot determine, no take)" \
               || bad "(a1) rc=$r (want 2) — a mixed pair rendered a verdict"
[[ "$_liveness_first_provider" == "T3" ]] \
    && ok "(a1) re-pinned to the answering provider (pin=T3)" \
    || bad "(a1) pin='$_liveness_first_provider' (want T3)"
[[ "$_liveness_first_vote" == "1000" ]] \
    && ok "(a1) baseline kept at min(1000,1001)=1000 (min rule)" \
    || bad "(a1) baseline='$_liveness_first_vote' (want 1000)"
[[ "$_liveness_first_tip" == "100001" && "$_liveness_first_ts" == "100012" ]] \
    && ok "(a1) tip baseline := current T3 tip, interval clock restarted (tip=$_liveness_first_tip ts=$_liveness_first_ts)" \
    || bad "(a1) tip/ts wrong (tip=$_liveness_first_tip ts=$_liveness_first_ts, want 100001/100012)"

# (a2) NON-VACUOUS CONTROL: simulate the OLD code (provider identity discarded → the stored pin can
# never disagree with the second sample). Identical numbers → FROZEN (rc=1): the false-ALLOW
# double-sign verdict that (a1) kills.
echo ""; echo "─── (a2) CONTROL: old code (pin forged equal) → the same pair reads FROZEN ───"
reset_ep
_SIM_NOW=100000
_T2_UP=1; _T2_LV=1000; _T2_TIP=100000
staked_is_actively_voting >/dev/null
_liveness_first_provider="T3"         # OLD-code simulation: no provider memory → mismatch invisible
_SIM_NOW=100012; _T2_UP=0; _T3_LV=1001; _T3_TIP=100001
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "(a2) control bites: without the pin the pair reads FROZEN (rc=1) → the spare would take under a LIVE holder" \
               || bad "(a2) control rc=$r (want 1) — the scenario no longer exercises the A2 hole"

# ── (b) CONVERGENCE (reviewer req 1): the re-pinned pair renders a verdict in ONE interval ──────
# Continue from (a1)'s state: pinned T3 @ ts=100012, baseline=1000, tip=100001. The holder is now
# genuinely frozen (T3 view stays 1001 while the cluster tip advances).
echo ""; echo "─── (b) convergence after re-pin: exactly ONE extra MIN_INTERVAL, not eternal ───"
reset_ep
_SIM_NOW=100000; _T2_UP=1; _T2_LV=1000; _T2_TIP=100000
staked_is_actively_voting >/dev/null                     # pin T2
_SIM_NOW=100012; _T2_UP=0; _T3_LV=1001; _T3_TIP=100001
staked_is_actively_voting >/dev/null                     # mismatch → re-pin T3 @100012
_SIM_NOW=100021; _T3_LV=1001; _T3_TIP=100010             # 9s after re-pin: too soon
staked_is_actively_voting; r=$?
[[ $r -eq 2 && "$_liveness_first_ts" == "100012" && "$_liveness_first_provider" == "T3" ]] \
    && ok "(b1) pre-interval probe: rc=2 and the re-pin undisturbed (ts=100012 pin=T3)" \
    || bad "(b1) rc=$r ts=$_liveness_first_ts pin=$_liveness_first_provider (want 2/100012/T3)"
_SIM_NOW=100022; _T3_LV=1001; _T3_TIP=100012             # exactly MIN_INTERVAL after the re-pin
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "(b2) same-provider pair converges: FROZEN (rc=1) at re-pin + exactly ${VOTE_LIVENESS_MIN_INTERVAL}s — worst case ONE extra interval per flip" \
               || bad "(b2) rc=$r (want 1) — the re-pin blocked longer than one interval (eternal-block risk)"

# ── (c) B2 MIN RULE (reviewer req 2): a pre-flip burst must stay remembered ─────────────────────
# ε=49 for this scenario so the burst (+49) is a frozen-candidate at the mismatch moment (Δ ≤ ε →
# the pin check is reached), while one more slot (+50) exceeds ε on the NEXT pair iff the baseline
# kept the episode minimum.
echo ""; echo "─── (c) min rule: re-pin never raises the episode vote baseline ───"
VOTE_LIVENESS_EPSILON=49
reset_ep
_SIM_NOW=200000; _T2_UP=1; _T2_LV=1000; _T2_TIP=100000
staked_is_actively_voting >/dev/null                     # pin T2, baseline 1000
_SIM_NOW=200012; _T2_UP=0
_T3_LV=1049; _T3_TIP=100040                              # wedged holder BURSTED +49; T3 shows it
staked_is_actively_voting; r=$?
[[ $r -eq 2 && "$_liveness_first_vote" == "1000" ]] \
    && ok "(c1) mismatch re-pin kept baseline=1000 = min(1000,1049) (rc=2)" \
    || bad "(c1) rc=$r baseline='$_liveness_first_vote' (want rc=2 baseline=1000 — burst forgotten?)"
_SIM_NOW=200024; _T3_LV=1050; _T3_TIP=100080
staked_is_actively_voting; r=$?
[[ $r -eq 0 ]] && ok "(c1) next pair: Δ=50 > ε=49 → VOTING (rc=0) — the burst is remembered and (in the daemon) re-anchors N3" \
               || bad "(c1) rc=$r (want 0) — the burst was lost across the re-pin"

# (c2) CONTROL: the naive re-pin (baseline := the current, higher lastVote) — the next pair reads
# FROZEN: the reopened B2 hole (take ~25s after the holder's last observed vote), proven.
reset_ep
_liveness_first_vote=1049; _liveness_first_tip=100040; _liveness_first_ts=200012; _liveness_first_provider="T3"
_SIM_NOW=200024; _T2_UP=0; _T3_LV=1050; _T3_TIP=100080
staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "(c2) control bites: naive re-pin (baseline:=1049) → Δ=1 ≤ ε → FROZEN (rc=1) — the B2 hole the min rule closes" \
               || bad "(c2) control rc=$r (want 1) — the scenario no longer exercises the naive-re-pin hole"
VOTE_LIVENESS_EPSILON=2

# ── (d) ASYMMETRY (reviewer req 3): a life sign stands on ANY provider mix ──────────────────────
echo ""; echo "─── (d) life signs are provider-independent: mixed pair with Δ > ε → VOTING ───"
reset_ep
_SIM_NOW=300000; _T2_UP=1; _T2_LV=3000; _T2_TIP=300000
staked_is_actively_voting >/dev/null                     # pin T2
_SIM_NOW=300012; _T2_UP=0; _T3_LV=3100; _T3_TIP=300100   # even the lagging vantage saw votes
staked_is_actively_voting; r=$?
[[ $r -eq 0 ]] && ok "(d1) T2→T3 flip with Δ=100 > ε → immediate VOTING (rc=0), no re-pin detour" \
               || bad "(d1) rc=$r (want 0) — a provider flip blocked a LIFE SIGN"
[[ "$_liveness_first_provider" == "T3" && "$_liveness_first_vote" == "3100" ]] \
    && ok "(d1) VOTING re-base adopted the current sample and its pin (base=3100 pin=T3)" \
    || bad "(d1) post-VOTING state wrong (base=$_liveness_first_vote pin=$_liveness_first_provider)"

# (d2) through the REAL attempt_takeover: the VOTING verdict must re-anchor N3
# (LAST_LIVENESS_ACTIVE_TIME) — a mixed pair must never hide the holder's life sign from the anchor.
GOSSIP_VERIFY=false; VOTE_LIVENESS_VERIFY=true; WITNESS_FASTPATH=false; DRY_RUN=false
TAKEOVER_DELAY=20; TAKEOVER_COOLDOWN=120; EXTERNAL_CONFIRM_THROTTLE=12
DELINQUENCY_WINDOW_SIZE=10; DELINQUENCY_WINDOW_THRESHOLD=7
ALERT_THROTTLE=600; _last_t2_alert=0
SELF_FENCE_DEMOTE_TIME=0; _last_lockout_log=0
tier2_check_delinquency()  { return 0; }
tier3_confirm_delinquency() { return 0; }
alert_info() { :; }
alert_warn() { :; }
save_state() { :; }
_took=0
take_staked_identity() { _took=1; return 0; }

_SIM_NOW=400000
LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _takeover_alert_sent=""
_delinq_window="1111111111"; _turbo_mode=true
FIRST_DELINQUENT_TIME=$(( _SIM_NOW - TAKEOVER_DELAY - 40 ))
LAST_LIVENESS_ACTIVE_TIME=0
reset_ep
_liveness_first_vote=4000; _liveness_first_tip=1; _liveness_first_provider="T2"
_liveness_first_ts=$(( _SIM_NOW - VOTE_LIVENESS_MIN_INTERVAL - 20 ))
_T2_UP=0; _T3_UP=1; _T3_LV=4100; _T3_TIP=400100
_took=0
attempt_takeover >/dev/null
[[ $_took -eq 0 ]] && ok "(d2) attempt_takeover BLOCKED on the mixed-pair life sign (no take)" \
                   || bad "(d2) STANDBY took the identity while the holder was voting — double-sign!"
[[ "$LAST_LIVENESS_ACTIVE_TIME" == "400000" ]] \
    && ok "(d2) N3 anchor re-anchored (LAST_LIVENESS_ACTIVE_TIME=$LAST_LIVENESS_ACTIVE_TIME) — the full delay re-elapses from the observed vote" \
    || bad "(d2) N3 anchor not re-anchored (LAST_LIVENESS_ACTIVE_TIME=$LAST_LIVENESS_ACTIVE_TIME, want 400000)"

# ── (e) episode resets clear the pin; the prefetch pins the new episode ─────────────────────────
echo ""; echo "─── (e) episode lifecycle: resets clear the pin, prefetch re-pins ───"
_liveness_first_provider="T3"; _liveness_first_vote=123
window_reset
[[ -z "$_liveness_first_provider" && -z "$_liveness_first_vote" ]] \
    && ok "(e1) window_reset cleared the provider pin with the sample" \
    || bad "(e1) stale pin survived window_reset (pin='$_liveness_first_provider')"

# In-delay episode → the attempt_takeover PREFETCH must capture and pin the first sample.
_SIM_NOW=500000
LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _takeover_alert_sent=""
_delinq_window="1111111111"
FIRST_DELINQUENT_TIME=$(( _SIM_NOW - 5 ))               # 5s into a 20s delay
LAST_LIVENESS_ACTIVE_TIME=0
reset_ep
_T2_UP=1; _T2_LV=7000; _T2_TIP=700000
_took=0
attempt_takeover >/dev/null
[[ $_took -eq 0 && "$_liveness_first_vote" == "7000" && "$_liveness_first_provider" == "T2" && "$_liveness_first_ts" == "500000" ]] \
    && ok "(e2) prefetch captured AND pinned the first sample (vote=7000 pin=T2 ts=500000)" \
    || bad "(e2) prefetch state wrong (vote=$_liveness_first_vote pin='$_liveness_first_provider' ts=$_liveness_first_ts took=$_took)"

# The main-loop inline episode-clear sits PAST the seam (unsourceable) — assert textually that it
# drops the provider pin together with the vote/tip sample.
if sed -n '/MAIN LOOP/,$p' "$STANDBY" | grep -q '_liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""'; then
    ok "(e3) main-loop delinquency-cleared reset also drops the provider pin (textual, past the seam)"
else
    bad "(e3) main-loop episode clear does NOT drop the provider pin — a stale pin could survive into the next episode"
fi

# ── (f) PRIMARY twin: the rpc-recovery fence re-pins and converges identically ──────────────────
echo ""; echo "─── (f) primary twin: rpc-recovery pairing through the (a)-shape ───"
prim_sim() {
    (
    set +e
    SRC2=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC2"
    # shellcheck disable=SC1090
    source "$SRC2"; rm -f "$SRC2"
    _SIM_NOW=100000
    mono_now() { echo "$_SIM_NOW"; }
    VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
    TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
    VOTE_LIVENESS_EPSILON=2; VOTE_LIVENESS_MIN_INTERVAL=10
    log_info() { :; }
    log_warn() { :; }
    # curl/_payload are inherited from the outer shell (the primary defines neither).
    _T2_UP=1; _T2_LV=1000; _T2_TIP=100000
    _T3_UP=1; _T3_LV=1000; _T3_TIP=100000
    _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
    staked_is_actively_voting >/dev/null; rc0=$?
    pin0="$_liveness_first_provider"
    _SIM_NOW=100012; _T2_UP=0; _T3_LV=1001; _T3_TIP=100001    # the measured A2 pair
    staked_is_actively_voting >/dev/null; rc1=$?
    pin1="$_liveness_first_provider"; base1="$_liveness_first_vote"
    _SIM_NOW=100022; _T3_LV=1001; _T3_TIP=100012              # T3/T3, genuinely frozen holder
    staked_is_actively_voting >/dev/null; rc2=$?
    reset_recovery_liveness
    printf 'rc0=%s pin0=%s rc1=%s pin1=%s base1=%s rc2=%s pinreset=%s\n' \
        "$rc0" "$pin0" "$rc1" "$pin1" "$base1" "$rc2" "${_liveness_first_provider:-EMPTY}"
    )
}
PRIM_OUT=$(prim_sim)
PRIM_WANT='rc0=2 pin0=T2 rc1=2 pin1=T3 base1=1000 rc2=1 pinreset=EMPTY'
echo "    primary: $PRIM_OUT"
if [[ "$PRIM_OUT" == "$PRIM_WANT" ]]; then
    ok "(f) primary fence: pin T2 → A2 pair re-pins (rc=2, pin=T3, baseline min=1000) → T3/T3 converges (rc=1) → reset clears the pin"
else
    bad "(f) primary twin diverged (got '$PRIM_OUT', want '$PRIM_WANT')"
fi

# ── (g) twin parity: the new pinning hunks must be BYTE-IDENTICAL across the daemons ────────────
echo ""; echo "─── (g) twin parity of the slice-2 hunks (this repo fights twin drift) ───"
P_PIN=$(sed -n '/AUDIT-5 A2): PROVIDER PIN/,/^    fi$/p' "$PRIMARY")
S_PIN=$(sed -n '/AUDIT-5 A2): PROVIDER PIN/,/^    fi$/p' "$STANDBY")
if [[ -n "$P_PIN" && "$P_PIN" == "$S_PIN" ]]; then
    ok "(g1) PROVIDER PIN block byte-identical in both daemons ($(printf '%s\n' "$P_PIN" | wc -l | tr -d ' ') lines)"
else
    bad "(g1) PROVIDER PIN block missing or DIVERGED between the daemons"
fi
P_MIN=$(sed -n '/re-base here is LOWER-ONLY/,/return 2/p' "$PRIMARY")
S_MIN=$(sed -n '/re-base here is LOWER-ONLY/,/return 2/p' "$STANDBY")
if [[ -n "$P_MIN" && "$P_MIN" == "$S_MIN" ]]; then
    ok "(g2) tip-guard lower-only re-base hunk byte-identical in both daemons ($(printf '%s\n' "$P_MIN" | wc -l | tr -d ' ') lines)"
else
    bad "(g2) tip-guard lower-only hunk missing or DIVERGED between the daemons"
fi

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
