#!/bin/bash
# STANDBY-role fence integration (v0.6.2 C2 -> v0.6.3 Block 1). STANDBY runs GOSSIP_VERIFY=true
# AND VOTE_LIVENESS_VERIFY=true, but in v0.6.3 vote-liveness is the SINGLE AUTHORITATIVE gate and
# gossip is ADVISORY (logs/corroborates, never blocks — a staked pubkey lingers ~48h in CRDS, so a
# stale entry must not stall a legitimate takeover). Drives the real attempt_takeover (real
# staked_is_actively_voting, mocked gossip) and asserts:
#   gossip clear  + holder LIVE      -> BLOCK   (liveness fences; the case a silent removal breaks)
#   gossip clear  + holder FROZEN    -> take over
#   gossip clear  + liveness UNKNOWN -> BLOCK   (invariant 3, fail closed)
#   gossip BLOCKS + holder FROZEN    -> TAKE OVER  (v0.6.3 change: a stale gossip entry no longer
#                                                   blocks; v0.6.2 would have BLOCKED here)
#   gossip BLOCKS + holder LIVE      -> BLOCK   ("active holder -> BLOCK" invariant kept; liveness)

# harness: tests/lib/harness.sh — ok/bad+banners, paths. Sink subset + cut + `date +%s` clock stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SRC=$(mktemp)
sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"
mono_now() { date +%s; }   # v0.7 (Block 3): tests prime timers via `date +%s` — keep the mono helper on the same clock
rm -f "$SRC"

# STANDBY config: BOTH fences on.
GOSSIP_VERIFY=true
VOTE_LIVENESS_VERIFY=true
VOTE_LIVENESS_EPSILON=2
VOTE_LIVENESS_MIN_INTERVAL=10
VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
TIER2_RPC="http://mock-t2"
TG_ENABLED=false
DELINQUENCY_WINDOW_SIZE=10
DELINQUENCY_WINDOW_THRESHOLD=7
TAKEOVER_DELAY=20
TAKEOVER_COOLDOWN=120
EXTERNAL_CONFIRM_THROTTLE=12
ALERT_THROTTLE=600
_last_t2_alert=0

log_info()  { :; }
log_warn()  { :; }
alert_info() { :; }
alert_warn() { :; }   # v0.6.4: fence-not-clear warning routes via alert_warn

# External delinquency confirmation: confirmed (reach the fence).
tier2_check_delinquency()  { return 0; }
tier3_confirm_delinquency() { return 0; }
# Gossip verdict is controllable; vote-liveness stays REAL (fed via get_staked_liveness_sample).
# v0.6.3: the sample is "<lastVote> <tip>"; _MOCK_TIP advances so the freshness guard passes
# (prime sets the first tip low). The freshness guard itself is unit-tested in test_vote_liveness.
_GOSSIP_RC=0
check_primary_dropped_identity() { return $_GOSSIP_RC; }
_MOCK_LV=0
_MOCK_TIP=900000
get_staked_liveness_sample() { [[ -z "$_MOCK_LV" ]] && return 1; printf '%s %s\n' "$_MOCK_LV" "$_MOCK_TIP"; }
_took=0
take_staked_identity() { _took=1; return 0; }

prime() {   # triggered + delay-served episode, with a back-dated liveness first sample = $1
    LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _takeover_alert_sent=""
    _delinq_window="1111111111"; _turbo_mode=true
    FIRST_DELINQUENT_TIME=$(( $(date +%s) - TAKEOVER_DELAY - 40 ))
    LAST_LIVENESS_ACTIVE_TIME=0   # v0.6.7 (N3): fresh episode — daemon resets this in window_reset / main loop
    _last_blind_end=0             # v0.7 (B3 s4): fresh episode — a prior case's blind stamp (e.g. case 3's externals-down) must not re-anchor this one
    # v0.7 (B3 s4): back-dated past VOTE_LIVENESS_MIN_SPAN too (was MIN_INTERVAL+20) — this suite
    # tests the fence verdicts, not the slice-4 observation-span floor (test_blindness_is_life).
    # v0.7 (B3 s4 rework): the floor now measures the EPISODE's observed span (_liveness_obs_since,
    # re-pinned by _note_observation) — prime it alongside the pair (observation began at the pin).
    _liveness_first_vote="$1"; _liveness_first_tip=1; _liveness_first_ts=$(( $(date +%s) - VOTE_LIVENESS_MIN_INTERVAL - VOTE_LIVENESS_MIN_SPAN - 20 ))
    _liveness_obs_since=$_liveness_first_ts
    _took=0
}

title_banner "STANDBY fence: vote-liveness authoritative, gossip advisory (v0.6.3)"

echo ""; echo "─── 1. gossip CLEAR + holder LIVE → BLOCK (liveness must fence) ───"
_GOSSIP_RC=0; prime 1000; _MOCK_LV=1090
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 0 ]] && ok "live holder blocked despite clear gossip (rc=$rc)" \
                     || bad "STANDBY took the identity while it was voting — double-sign!"

echo ""; echo "─── 2. gossip CLEAR + holder FROZEN → take over ───"
_GOSSIP_RC=0; prime 2000; _MOCK_LV=2000
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 1 ]] && ok "liveness frozen + gossip clear → took over (rc=$rc)" \
                     || bad "STANDBY failed to take over a dead holder (_took=$_took rc=$rc)"

echo ""; echo "─── 3. gossip CLEAR + liveness UNKNOWN → BLOCK (invariant 3) ───"
_GOSSIP_RC=0; prime 3000; _MOCK_LV=""
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 0 ]] && ok "undetermined liveness blocked even with clear gossip (rc=$rc)" \
                     || bad "STANDBY took over with undetermined liveness — invariant 3 violated!"

echo ""; echo "─── 4. gossip BLOCKS (stale entry) + holder FROZEN → TAKE OVER (v0.6.3: gossip advisory) ───"
# A persisting ~48h-stale staked entry at the old PRIMARY endpoint (gossip 'present', _GOSSIP_RC=1)
# must NOT block when liveness shows the holder is frozen. v0.6.2 would have BLOCKED here.
_GOSSIP_RC=1; prime 4000; _MOCK_LV=4000
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 1 ]] && ok "stale gossip entry no longer blocks a frozen-holder takeover (rc=$rc)" \
                     || bad "stale gossip entry still blocked takeover — v0.6.3 fence not applied (_took=$_took rc=$rc)"

echo ""; echo "─── 5. gossip BLOCKS + holder LIVE → BLOCK (active holder → BLOCK invariant kept) ───"
# Even with the gossip entry present, the decisive fact is that the holder is VOTING → liveness BLOCKs.
_GOSSIP_RC=1; prime 5000; _MOCK_LV=5090
attempt_takeover >/dev/null; rc=$?
[[ "$_took" -eq 0 ]] && ok "active (voting) holder blocked regardless of gossip (rc=$rc)" \
                     || bad "STANDBY took the identity while it was voting — double-sign!"

results_banner
