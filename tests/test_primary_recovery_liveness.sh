#!/bin/bash
# v0.6.3 (Block 2): PRIMARY rpc-recovery vote-liveness parity. Two parts, both on the SHIPPED
# primary code:
#   Part 1 — the ported staked_is_actively_voting behaves (advancing→BLOCK, frozen+fresh-tip→clear,
#            stalled-tip→cannot-determine). Mirrors the standby fence.
#   Part 2 — attempt_safe_recovery GATES on it: identity actively voted (liveness advancing) →
#            recovery does NOT re-take, even if gossip looks clear. Frozen + gossip clear → re-takes.
#            Frozen + gossip says STANDBY has it → still aborts (gossip corroboration).
# Non-vacuous: Part 2 case C (re-take) only passes because the gate lets a frozen holder through,
# while cases A/D prove an advancing/undetermined holder is refused.

# v0.6.5 (F6): Part 1 below drives the SHIPPED staked_is_actively_voting (sourced from the primary
# script, so shellcheck cannot see its definition); Part 2 then deliberately OVERRIDES it with a mock
# defined further down. SC2218 "used before defined" is therefore a false positive for this whole file.
# shellcheck disable=SC2218
#
# harness: tests/lib/harness.sh — ok/bad+banners, paths. Cut + sink subset + `date +%s` clock stay local.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock
rm -f "$SRC"

VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
VOTE_LIVENESS_EPSILON=2; VOTE_LIVENESS_MIN_INTERVAL=10
log_info()  { :; }
log_warn()  { :; }
alert_info() { :; }
alert_warn() { :; }   # v0.6.4: recovery-blocked warning routes via alert_warn

title_banner "PRIMARY rpc-recovery liveness fence (v0.6.3 Block 2)"

# ── Part 1: the ported staked_is_actively_voting ─────────────────────────────────────────────
echo ""; echo "─── Part 1: ported staked_is_actively_voting ───"
# Single getVoteAccounts doc with the staked account (lastVote=$_MOCK_LV) + a cluster account
# (lastVote=$_MOCK_TIP). The v0.6.3 freshness reference is the cluster-wide MAX lastVote from this
# same payload, so $_MOCK_TIP is that reference (kept >> $_MOCK_LV).
_MOCK_LV=100; _MOCK_TIP=500000
curl() {
    [[ -z "$_MOCK_LV" ]] && return 7
    printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"%s","lastVote":%s},{"votePubkey":"ClusterVote111","lastVote":%s}],"delinquent":[]},"id":1}' \
        "$VOTE_PUBKEY" "$_MOCK_LV" "${_MOCK_TIP:-0}"; return 0
}
reset_samples() { _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; }
age_first()     { _liveness_first_ts=$(( $(date +%s) - VOTE_LIVENESS_MIN_INTERVAL - 5 )); }

reset_samples; _MOCK_LV=1000; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first; _MOCK_LV=1050; _MOCK_TIP=500300; staked_is_actively_voting; r=$?
[[ $r -eq 0 ]] && ok "advancing lastVote (tip fresh) → VOTING → BLOCK (rc=0)" || bad "advancing rc=$r (want 0)"

reset_samples; _MOCK_LV=2000; _MOCK_TIP=500000; staked_is_actively_voting >/dev/null
age_first; _MOCK_LV=2000; _MOCK_TIP=500300; staked_is_actively_voting; r=$?
[[ $r -eq 1 ]] && ok "frozen lastVote + tip advancing → not voting → clear (rc=1)" || bad "frozen rc=$r (want 1)"

reset_samples; _MOCK_LV=3000; _MOCK_TIP=600000; staked_is_actively_voting >/dev/null
age_first; _MOCK_LV=3000; _MOCK_TIP=600000; staked_is_actively_voting; r=$?
[[ $r -eq 2 ]] && ok "stalled external tip → cannot determine → BLOCK (rc=2)" || bad "stalled-tip rc=$r (want 2)"

unset -f curl

# ── Part 2: attempt_safe_recovery gates on the liveness verdict ──────────────────────────────
echo ""; echo "─── Part 2: attempt_safe_recovery gating ───"
LAST_SWITCH_TIME=0; RECOVERY_DELAY=0; RECOVERY_CHECKS=1; RECOVERY_CHECK_INTERVAL=0
STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
tier1_check_delinquency()  { return 1; }                 # local: not delinquent
_check_rpc_delinquency()   { return 1; }                 # tier2: not delinquent
_LIVENESS_RC=1                                            # controllable verdict
staked_is_actively_voting() { return $_LIVENESS_RC; }
_GOSSIP_ABORT=1                                           # check_standby_has_identity: 0=abort,1=nobody else
check_standby_has_identity() { return $_GOSSIP_ABORT; }
_switched=0
switch_to_staked() { _switched=1; return 0; }

# v0.7 (B3 s4): the fence is MOCKED here, so no real pair exists — zero the first-sample stamp
# and the blind anchor (Part 1 state must not re-anchor Part 2's RECOVERY_DELAY). v0.7 (B3 s4
# rework): the span floor now skips on _liveness_obs_since=0 (the harness-mocked-fence carve-out)
# — zero that too (Part 1's REAL fence pinned it via _note_observation). The floor/blindness
# themselves are tested in test_blindness_is_life.
prep() { _recovery_confirm_count=0; _standby_alert_sent=""; _switched=0; _liveness_first_ts=0; _last_blind_end=0; _liveness_obs_since=0; }

# A. liveness ADVANCING + gossip CLEAR → must NOT re-take (the headline acceptance).
prep; _LIVENESS_RC=0; _GOSSIP_ABORT=1
attempt_safe_recovery >/dev/null
[[ "$_switched" -eq 0 ]] && ok "A. liveness advancing → recovery refused even with clear gossip" \
                        || bad "A. PRIMARY re-took staked while it was actively voted — double-sign!"

# B. liveness FROZEN + gossip says STANDBY has it → still aborts (corroboration).
prep; _LIVENESS_RC=1; _GOSSIP_ABORT=0
attempt_safe_recovery >/dev/null
[[ "$_switched" -eq 0 ]] && ok "B. gossip shows STANDBY holds it → recovery aborts (corroboration)" \
                        || bad "B. recovery proceeded despite gossip showing a holder"

# C. liveness FROZEN + gossip CLEAR → recovery proceeds.
prep; _LIVENESS_RC=1; _GOSSIP_ABORT=1
attempt_safe_recovery >/dev/null
[[ "$_switched" -eq 1 ]] && ok "C. frozen holder + gossip clear → recovery re-takes" \
                        || bad "C. recovery did not re-take a genuinely-dead holder (_switched=$_switched)"

# D. liveness CANNOT-DETERMINE + gossip CLEAR → must NOT re-take (fail closed).
prep; _LIVENESS_RC=2; _GOSSIP_ABORT=1
attempt_safe_recovery >/dev/null
[[ "$_switched" -eq 0 ]] && ok "D. undetermined liveness → recovery refused (fail closed)" \
                        || bad "D. recovery re-took with undetermined liveness — invariant 3 violated!"

results_banner
