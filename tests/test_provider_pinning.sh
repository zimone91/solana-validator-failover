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
#
# v0.7 (Block 3, slice 3 / AUDIT-5 A3) — ε=0 on the now-pinned pair (this suite hosts the cases that
# need the fake mono clock + the real attempt_takeover):
#   (h)  THE MEASURED COST CASE: dead holder fixed at slot X, one stray +1 burst observed exactly at
#        decision time → VOTING verdict + N3 re-anchor; the pair re-renders FROZEN and the take
#        COMPLETES at anchor+TAKEOVER_DELAY — cost vs the no-burst baseline within the AUDIT-5
#        "≈ +70 s" envelope [TAKEOVER_DELAY, TAKEOVER_DELAY+VOTE_LIVENESS_MIN_INTERVAL]; no deadlock
#   (h5) the "+ one VOTE_LIVENESS_MIN_INTERVAL" component made visible: after a VOTING re-base the
#        pair re-renders FROZEN in EXACTLY one interval (rc 0 → 2(too-soon) → 1)
#   (i)  convergence sanity at ε=0: a dead node's lastVote is a FIXED NUMBER every provider
#        converges to → FROZEN renders normally, even across a provider flip (one extra interval)

# harness: tests/lib/harness.sh — ok/bad+banners, paths, extract_twin (the g1/g2 parity hunks
# cannot silently compare two empties), field+dump_freshness (4.3: every read of the pin goes
# through the sole reader — `field "$(dump_freshness)" vantage`; priming WRITES stay direct).
# The mono-only clock (no date interceptor — not the pair), log subset, prim_sim's cut stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

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
# v0.7 (Block 3, slice 3): ε=2 here is EXPLICIT, not the shipped default (now 0 — asserted in
# test_vote_liveness). The A2 scenarios below need Δ1 ≤ ε to be a frozen-candidate so the pair
# actually reaches the pin comparison; at the shipped ε=0 the same Δ1 is already VOTING — that
# closure is section (h)/(i)'s and test_vote_liveness 2b–2d's subject.
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

title_banner "Liveness provider pinning (v0.7 Block 3 slice 2 / AUDIT-5 A2)"

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
pin=$(field "$(dump_freshness)" vantage)
[[ $r -eq 2 && "$pin" == "T2" ]] \
    && ok "(a0) first sample captured AND pinned to T2 (rc=2, pin=$pin)" \
    || bad "(a0) first sample rc=$r pin='$pin' (want rc=2 pin=T2)"

_SIM_NOW=100012                       # 12s later (> MIN_INTERVAL)
_T2_UP=0                              # T2 hiccups exactly at sample #2 — needs no misconfiguration
_T3_LV=1001; _T3_TIP=100001           # T3 lags 29 slots: true 1030/100030 reads as 1001/100001
staked_is_actively_voting; r=$?
[[ $r -eq 2 ]] && ok "(a1) provider flip on a frozen-candidate → rc=2 (cannot determine, no take)" \
               || bad "(a1) rc=$r (want 2) — a mixed pair rendered a verdict"
pin=$(field "$(dump_freshness)" vantage)
[[ "$pin" == "T3" ]] \
    && ok "(a1) re-pinned to the answering provider (pin=T3)" \
    || bad "(a1) pin='$pin' (want T3)"
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
pin=$(field "$(dump_freshness)" vantage)
[[ $r -eq 2 && "$_liveness_first_ts" == "100012" && "$pin" == "T3" ]] \
    && ok "(b1) pre-interval probe: rc=2 and the re-pin undisturbed (ts=100012 pin=T3)" \
    || bad "(b1) rc=$r ts=$_liveness_first_ts pin=$pin (want 2/100012/T3)"
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
pin=$(field "$(dump_freshness)" vantage)
[[ "$pin" == "T3" && "$_liveness_first_vote" == "3100" ]] \
    && ok "(d1) VOTING re-base adopted the current sample and its pin (base=3100 pin=T3)" \
    || bad "(d1) post-VOTING state wrong (base=$_liveness_first_vote pin=$pin)"

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
pin=$(field "$(dump_freshness)" vantage)
[[ -z "$pin" && -z "$_liveness_first_vote" ]] \
    && ok "(e1) window_reset cleared the provider pin with the sample" \
    || bad "(e1) stale pin survived window_reset (pin='$pin')"

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
pin=$(field "$(dump_freshness)" vantage)
[[ $_took -eq 0 && "$_liveness_first_vote" == "7000" && "$pin" == "T2" && "$_liveness_first_ts" == "500000" ]] \
    && ok "(e2) prefetch captured AND pinned the first sample (vote=7000 pin=T2 ts=500000)" \
    || bad "(e2) prefetch state wrong (vote=$_liveness_first_vote pin='$pin' ts=$_liveness_first_ts took=$_took)"

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
    pin0="$(field "$(dump_freshness)" vantage)"
    _SIM_NOW=100012; _T2_UP=0; _T3_LV=1001; _T3_TIP=100001    # the measured A2 pair
    staked_is_actively_voting >/dev/null; rc1=$?
    pin1="$(field "$(dump_freshness)" vantage)"; base1="$_liveness_first_vote"
    _SIM_NOW=100022; _T3_LV=1001; _T3_TIP=100012              # T3/T3, genuinely frozen holder
    staked_is_actively_voting >/dev/null; rc2=$?
    reset_recovery_liveness
    pinreset="$(field "$(dump_freshness)" vantage)"
    printf 'rc0=%s pin0=%s rc1=%s pin1=%s base1=%s rc2=%s pinreset=%s\n' \
        "$rc0" "$pin0" "$rc1" "$pin1" "$base1" "$rc2" "${pinreset:-EMPTY}"
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
if extract_twin 'AUDIT-5 A2): PROVIDER PIN' '^    fi$' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(g1) PROVIDER PIN block byte-identical in both daemons ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)"
else
    bad "(g1) PROVIDER PIN block missing or DIVERGED between the daemons"
fi
if extract_twin 're-base here is LOWER-ONLY' 'return 2' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(g2) tip-guard lower-only re-base hunk byte-identical in both daemons ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)"
else
    bad "(g2) tip-guard lower-only hunk missing or DIVERGED between the daemons"
fi

# ── (h) v0.7 slice 3 (AUDIT-5 A3): ε=0 — THE MEASURED COST CASE, on the real attempt_takeover ───
# Dead holder fixed at slot X; ONE stray +1 burst lands so it is first OBSERVED exactly at decision
# time (a vote in flight when the node died — a dead node's lastVote then stays fixed at X+1). At
# ε=0 that observation is a VOTING verdict → N3 re-anchor; the pair (re-based by the VOTING path)
# re-renders FROZEN and the take COMPLETES at exactly anchor+TAKEOVER_DELAY. Cost vs the no-burst
# baseline: within the AUDIT-5 "≈ +70 s" envelope — one N3 re-anchor (TAKEOVER_DELAY) plus at most
# one VOTE_LIVENESS_MIN_INTERVAL (on the clean simulated clock the interval component is absorbed
# inside the re-elapsed delay, so the cost realizes as exactly +TAKEOVER_DELAY; a real-world
# boundary interleave pushes it toward the +70 ceiling — measured, accepted, do NOT "fix"). Both
# bounds are asserted so neither a deadlock (no take) nor a cheaper-than-delay take (re-anchor
# bypassed) can pass.
echo ""; echo "─── (h) slice 3: dead holder + stray +1 burst at decision time → +[60,70]s, take completes ───"
VOTE_LIVENESS_EPSILON=0   # the slice-3 shipped default (this suite overrode it above for the A2 scenarios)
TAKEOVER_DELAY=60         # shipped default — the "≈ +70" magnitude is 60 (re-anchor) + 10 (interval)
_B_X=9000                 # the dead holder's fixed lastVote
b_sim() {   # $1 = "burst" | "clean"; echoes "<take_offset_from_T0> <anchor_offset_or_-1>"
  local mode="$1" t anchor_off
  reset_ep
  _B_T0=800000; FIRST_DELINQUENT_TIME=$_B_T0
  LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _takeover_alert_sent=""; _gossip_prefetched=false
  LAST_LIVENESS_ACTIVE_TIME=0; _delinq_window="1111111111"; _turbo_mode=true
  _T2_UP=1; _T3_UP=1
  _b_took=-1
  take_staked_identity() { _b_took=$(( _SIM_NOW - _B_T0 )); return 0; }
  for (( t=_B_T0; t<=_B_T0+300; t++ )); do
    _SIM_NOW=$t
    _T2_LV=$_B_X
    [[ "$mode" == "burst" && $t -ge $(( _B_T0 + TAKEOVER_DELAY )) ]] && _T2_LV=$(( _B_X + 1 ))
    _T2_TIP=$(( 900000 + t - _B_T0 ))    # cluster tip advances 1/s — fresh provider view throughout
    _T3_LV=$_T2_LV; _T3_TIP=$_T2_TIP     # (not consulted while T2 answers — same-provider run)
    attempt_takeover >/dev/null
    [[ $_b_took -ge 0 ]] && break
  done
  anchor_off=-1
  [[ ${LAST_LIVENESS_ACTIVE_TIME:-0} -gt 0 ]] && anchor_off=$(( LAST_LIVENESS_ACTIVE_TIME - _B_T0 ))
  echo "$_b_took $anchor_off"
}
read -r H_CLEAN H_CLEAN_A <<<"$(b_sim clean)"
read -r H_BURST H_BURST_A <<<"$(b_sim burst)"
H_COST=$(( H_BURST - H_CLEAN ))
echo "    timeline: no-burst take t0+${H_CLEAN}s (anchor ${H_CLEAN_A}) | burst take t0+${H_BURST}s (anchor t0+${H_BURST_A}s) | cost +${H_COST}s"
[[ $H_CLEAN -eq $TAKEOVER_DELAY && $H_CLEAN_A -eq -1 ]] \
    && ok "(h1) no-burst baseline: take at exactly first-delinquent+${TAKEOVER_DELAY}s, N3 anchor inert" \
    || bad "(h1) baseline drifted (take=${H_CLEAN} anchor=${H_CLEAN_A}, want ${TAKEOVER_DELAY}/-1)"
[[ $H_BURST_A -eq $TAKEOVER_DELAY ]] \
    && ok "(h2) the +1 burst observed at decision time is a VOTING verdict → N3 re-anchored to the observation instant (t0+${H_BURST_A}s)" \
    || bad "(h2) N3 not re-anchored at the burst observation (anchor=${H_BURST_A}, want ${TAKEOVER_DELAY}) — ε=0 missed a life sign"
[[ $H_BURST -ge 0 && $H_BURST -eq $(( H_BURST_A + TAKEOVER_DELAY )) ]] \
    && ok "(h3) take COMPLETES at exactly anchor+TAKEOVER_DELAY (t0+${H_BURST}s) — the pair re-rendered FROZEN; no deadlock" \
    || bad "(h3) take=${H_BURST} (want anchor+delay=$(( H_BURST_A + TAKEOVER_DELAY ))) — deadlock or premature take"
[[ $H_COST -ge $TAKEOVER_DELAY && $H_COST -le $(( TAKEOVER_DELAY + VOTE_LIVENESS_MIN_INTERVAL )) ]] \
    && ok "(h4) measured cost +${H_COST}s ∈ [${TAKEOVER_DELAY}, $(( TAKEOVER_DELAY + VOTE_LIVENESS_MIN_INTERVAL ))] — the AUDIT-5 ≈+70s envelope (one re-anchor + ≤ one interval)" \
    || bad "(h4) cost +${H_COST}s outside [${TAKEOVER_DELAY}, $(( TAKEOVER_DELAY + VOTE_LIVENESS_MIN_INTERVAL ))] — cheaper than one re-anchor (hole) or dearer than the measured expectation"

# (h5) the "+ one VOTE_LIVENESS_MIN_INTERVAL" component, made visible at the fence: after the
# VOTING re-base the pair re-renders its verdict in EXACTLY one interval (rc 0 → 2 too-soon → 1
# FROZEN) — this is the interval term of the measured +70, and (with (i)'s convergence) why a
# stray burst delays the take but can never wedge it.
echo ""; echo "─── (h5) after a VOTING re-base the pair re-renders FROZEN in exactly one MIN_INTERVAL ───"
reset_ep
_SIM_NOW=850000; _T2_UP=1; _T3_UP=1; _T2_LV=5000; _T2_TIP=910000
staked_is_actively_voting >/dev/null                      # first sample, pin T2
_SIM_NOW=850012; _T2_LV=5001; _T2_TIP=910012              # the stray burst: +1
staked_is_actively_voting >/dev/null; p0=$?
_SIM_NOW=850021; _T2_LV=5001; _T2_TIP=910021              # 9s after the re-base: too soon
staked_is_actively_voting >/dev/null; p1=$?
_SIM_NOW=850022; _T2_LV=5001; _T2_TIP=910022              # exactly MIN_INTERVAL after the re-base
staked_is_actively_voting >/dev/null; p2=$?
[[ $p0 -eq 0 && $p1 -eq 2 && $p2 -eq 1 ]] \
    && ok "(h5) rc sequence 0(VOTING re-base) → 2(9s: too soon) → 1(FROZEN at +${VOTE_LIVENESS_MIN_INTERVAL}s) — one interval, no wedge" \
    || bad "(h5) rc sequence $p0,$p1,$p2 (want 0,2,1) — the pair did not re-render in one MIN_INTERVAL"

# ── (i) slice 3 convergence sanity at ε=0: a dead node's lastVote is a FIXED NUMBER every provider
#       converges to — FROZEN renders normally, even across a provider flip (the flip costs one
#       extra interval via the re-pin, then the same fixed number renders the verdict; no deadlock).
echo ""; echo "─── (i) ε=0 convergence: all providers on the same fixed lastVote → FROZEN renders ───"
reset_ep
_SIM_NOW=870000; _T2_UP=1; _T3_UP=1
_T2_LV=7777; _T2_TIP=910000; _T3_LV=7777; _T3_TIP=909990   # both vantages: the SAME fixed number
staked_is_actively_voting >/dev/null                       # first sample, pin T2
_SIM_NOW=870012; _T2_LV=7777; _T2_TIP=910012
staked_is_actively_voting >/dev/null; c0=$?
[[ $c0 -eq 1 ]] \
    && ok "(i1) same-provider pair on the fixed number: Δ0 at ε=0 → FROZEN renders normally (rc=1)" \
    || bad "(i1) rc=$c0 (want 1) — ε=0 broke the plain frozen verdict"
_SIM_NOW=870024; _T2_UP=0; _T3_LV=7777; _T3_TIP=910020     # T2 dies; T3 reports the SAME fixed number
staked_is_actively_voting >/dev/null; c1=$?
pin=$(field "$(dump_freshness)" vantage)
[[ $c1 -eq 2 && "$pin" == "T3" && "$_liveness_first_vote" == "7777" ]] \
    && ok "(i2) provider flip re-pins (rc=2, pin=T3) and the min-rule baseline stays the fixed 7777" \
    || bad "(i2) rc=$c1 pin='$pin' base='$_liveness_first_vote' (want 2/T3/7777)"
_SIM_NOW=870034; _T3_LV=7777; _T3_TIP=910030               # one interval after the re-pin
staked_is_actively_voting >/dev/null; c2=$?
[[ $c2 -eq 1 ]] \
    && ok "(i3) re-pinned T3/T3 pair converges on the SAME number → FROZEN (rc=1) — ε=0 cannot deadlock" \
    || bad "(i3) rc=$c2 (want 1) — the fixed-number convergence argument failed"

results_banner
