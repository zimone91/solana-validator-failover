#!/bin/bash
# v0.6.8 (S1, Audit-2 fix): inter-spare stagger is now COMPUTED + ENFORCED, not docs-only. A spare's
# effective fast-take floor = max(FASTPATH_STAGGER_SECS, TAKEOVER_DELAY - STANDBY_TAKEOVER_DELAY), so a
# BACKUP cannot fast-take ahead of the STANDBY even with the default FASTPATH_STAGGER_SECS=0. Bad/absent
# STANDBY_TAKEOVER_DELAY ⇒ fail-closed (fast-path disabled, the v0.6.7 timer governs).
#   (C-standby) STANDBY (delay 60, STD 60)           → floor 0,  enabled
#   (C-backup)  BACKUP  (delay 90, STD 60)           → floor 30, enabled
#   (C-extra)   BACKUP + FASTPATH_STAGGER_SECS=45    → floor 45 (max)
#   (C-empty)   STANDBY_TAKEOVER_DELAY empty         → DISABLED (fail-closed)
#   (C-nonnum)  STANDBY_TAKEOVER_DELAY=abc           → DISABLED
#   (C-gt)      STANDBY_TAKEOVER_DELAY > TAKEOVER_DELAY → DISABLED
#   (FB-backup-zero) F-B: BACKUP, floor 0, first-spare=false → DISABLED (fail-closed)
#   (FB-standby-zero) F-B: same delays, first-spare=true     → enabled (role flag is load-bearing)
#   (FB-backup-ok)   F-B: BACKUP, positive stagger           → enabled (no opt-in needed)
#   (G-standby) gate: STANDBY floor 0   → fast-takes at elapsed 0/5/30
#   (G-backup)  gate: BACKUP  floor 30  → does NOT fast-take at 0/5; fast-takes at 30
#   (G-control) NON-VACUOUS: BACKUP with floor 0 (enforcement reverted) → fast-takes at 0
#   (G-disabled) _fastpath_disabled set → no fast-take regardless of elapsed

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
# shellcheck disable=SC1090
source "$SRC"; rm -f "$SRC"
log_info() { :; }; log_warn() { :; }; log_error() { :; }; alert_warn() { :; }

echo "============================================="
echo "  Option A stagger enforcement (v0.6.8 S1)"
echo "============================================="

echo ""; echo "─── _fastpath_compute_stagger ───"
FASTPATH_STAGGER_SECS=0; WITNESS_FASTPATH_FIRST_SPARE=false   # F-B: BACKUP-role default; the STANDBY opts in below
# C-standby is the FIRST spare → needs WITNESS_FASTPATH_FIRST_SPARE=true to keep its (legitimate) floor 0
TAKEOVER_DELAY=60; STANDBY_TAKEOVER_DELAY=60; WITNESS_FASTPATH_FIRST_SPARE=true; _fastpath_compute_stagger; rc=$?
[[ $rc -eq 0 && $_fastpath_stagger_floor -eq 0 && -z "$_fastpath_disabled" ]] \
    && ok "(C-standby) STANDBY (60/60, first-spare) → floor 0, enabled" || bad "(C-standby) floor=$_fastpath_stagger_floor disabled='$_fastpath_disabled' rc=$rc"
WITNESS_FASTPATH_FIRST_SPARE=false
TAKEOVER_DELAY=90; STANDBY_TAKEOVER_DELAY=60; _fastpath_compute_stagger; rc=$?
[[ $rc -eq 0 && $_fastpath_stagger_floor -eq 30 && -z "$_fastpath_disabled" ]] \
    && ok "(C-backup) BACKUP (90/60) → floor 30, enabled" || bad "(C-backup) floor=$_fastpath_stagger_floor disabled='$_fastpath_disabled' rc=$rc"
TAKEOVER_DELAY=90; STANDBY_TAKEOVER_DELAY=60; FASTPATH_STAGGER_SECS=45; _fastpath_compute_stagger
[[ $_fastpath_stagger_floor -eq 45 ]] && ok "(C-extra) BACKUP + cfg stagger 45 → floor max(45,30)=45" || bad "(C-extra) floor=$_fastpath_stagger_floor"
FASTPATH_STAGGER_SECS=0
TAKEOVER_DELAY=60; STANDBY_TAKEOVER_DELAY=""; _fastpath_compute_stagger; rc=$?
[[ $rc -ne 0 && -n "$_fastpath_disabled" ]] && ok "(C-empty) empty STANDBY_TAKEOVER_DELAY → DISABLED (fail-closed)" || bad "(C-empty) not disabled (rc=$rc disabled='$_fastpath_disabled')"
TAKEOVER_DELAY=60; STANDBY_TAKEOVER_DELAY="abc"; _fastpath_compute_stagger; rc=$?
[[ $rc -ne 0 && -n "$_fastpath_disabled" ]] && ok "(C-nonnum) non-numeric → DISABLED" || bad "(C-nonnum) not disabled (rc=$rc)"
TAKEOVER_DELAY=60; STANDBY_TAKEOVER_DELAY=90; _fastpath_compute_stagger; rc=$?
[[ $rc -ne 0 && -n "$_fastpath_disabled" ]] && ok "(C-gt) STANDBY_TAKEOVER_DELAY(90) > TAKEOVER_DELAY(60) → DISABLED" || bad "(C-gt) not disabled (rc=$rc)"

echo ""; echo "─── F-B: explicit first-spare role gates a ZERO stagger floor ───"
# A misconfigured BACKUP (STANDBY_TAKEOVER_DELAY == its OWN TAKEOVER_DELAY ⇒ required 0) must NOT silently
# inherit floor 0 and race the STANDBY. Only the declared first spare (WITNESS_FASTPATH_FIRST_SPARE=true) may.
FASTPATH_STAGGER_SECS=0
# (FB-backup-zero) BACKUP, zero stagger, NOT first-spare → DISABLED (fail-closed + page)
TAKEOVER_DELAY=60; STANDBY_TAKEOVER_DELAY=60; WITNESS_FASTPATH_FIRST_SPARE=false; _fastpath_compute_stagger; rc=$?
[[ $rc -ne 0 && -n "$_fastpath_disabled" ]] \
    && ok "(FB-backup-zero) BACKUP with STANDBY_TAKEOVER_DELAY==own (floor 0) + first-spare=false → DISABLED" || bad "(FB-backup-zero) NOT disabled (rc=$rc disabled='$_fastpath_disabled')"
# (FB-standby-zero) SAME delays, but first-spare=true → enabled, floor 0 (the legitimate STANDBY). The only
# difference from FB-backup-zero is the role flag → proves the F-B gate is load-bearing (non-vacuous).
TAKEOVER_DELAY=60; STANDBY_TAKEOVER_DELAY=60; WITNESS_FASTPATH_FIRST_SPARE=true; _fastpath_compute_stagger; rc=$?
[[ $rc -eq 0 && $_fastpath_stagger_floor -eq 0 && -z "$_fastpath_disabled" ]] \
    && ok "(FB-standby-zero) SAME delays + first-spare=true → enabled, floor 0 (role flag is load-bearing)" || bad "(FB-standby-zero) not enabled (rc=$rc floor=$_fastpath_stagger_floor disabled='$_fastpath_disabled')"
# (FB-backup-ok) a correctly-configured BACKUP (positive stagger) needs no opt-in
TAKEOVER_DELAY=90; STANDBY_TAKEOVER_DELAY=60; WITNESS_FASTPATH_FIRST_SPARE=false; _fastpath_compute_stagger; rc=$?
[[ $rc -eq 0 && $_fastpath_stagger_floor -eq 30 && -z "$_fastpath_disabled" ]] \
    && ok "(FB-backup-ok) BACKUP with a correct smaller STANDBY_TAKEOVER_DELAY (floor 30) → enabled (no opt-in needed)" || bad "(FB-backup-ok) not enabled (rc=$rc floor=$_fastpath_stagger_floor)"
WITNESS_FASTPATH_FIRST_SPARE=false

# ════════ gate integration: drive the real attempt_takeover with a per-node floor ════════
echo ""; echo "─── attempt_takeover gate respects the computed stagger floor ───"
_take_calls=0; _confirm_calls=0
peer_has_relinquished() { return 0; }            # flip present (S1 is about the stagger gate, not the detector)
confirm_delinquency_external() { _confirm_calls=$((_confirm_calls+1)); return 0; }
staked_is_actively_voting() { return 1; }        # frozen
take_staked_identity() { _take_calls=$((_take_calls+1)); return 0; }
window_count() { echo 7; }
get_staked_liveness_sample() { echo "100 200"; }
alert_info() { :; }; alert() { :; }
GOSSIP_VERIFY=false; VOTE_LIVENESS_VERIFY=true; DELINQUENCY_WINDOW_SIZE=10
TAKEOVER_COOLDOWN=300; EXTERNAL_CONFIRM_THROTTLE=10; _turbo_mode=false; WITNESS_FASTPATH=true; _fastpath_disabled=""
# drive attempt_takeover with elapsed=E and floor=F; echo whether a take happened
drive() {  # $1=elapsed $2=floor
    _take_calls=0; _confirm_calls=0; _fastpath_stagger_floor=$2; _fastpath_disabled=""
    TAKEOVER_DELAY=120   # large so we are always inside the countdown (the fast-path is what fires)
    FIRST_DELINQUENT_TIME=$(( $(date +%s) - $1 )); LAST_LIVENESS_ACTIVE_TIME=0
    LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; _liveness_first_vote="100"; _takeover_alert_sent=""
    attempt_takeover >/dev/null 2>&1
    echo "$_take_calls"
}
# STANDBY: floor 0 → fast-takes at 0/5/30
[[ "$(drive 0 0)" == "1" && "$(drive 5 0)" == "1" && "$(drive 30 0)" == "1" ]] \
    && ok "(G-standby) floor 0 → STANDBY fast-takes at elapsed 0/5/30" || bad "(G-standby) STANDBY did not fast-take (0:$(drive 0 0) 5:$(drive 5 0) 30:$(drive 30 0))"
# BACKUP: floor 30 → NO fast-take at 0/5; fast-take at 30
b0=$(drive 0 30); b5=$(drive 5 30); b30=$(drive 30 30)
[[ "$b0" == "0" && "$b5" == "0" && "$b30" == "1" ]] \
    && ok "(G-backup) floor 30 → BACKUP does NOT fast-take at 0/5, fast-takes at 30 (stagger preserved)" || bad "(G-backup) wrong (0:$b0 5:$b5 30:$b30)"
# NON-VACUOUS control: revert enforcement (floor 0 on the BACKUP) → it fast-takes at 0
[[ "$(drive 0 0)" == "1" ]] \
    && ok "(G-control) with the floor reverted to 0, the BACKUP fast-takes at elapsed 0 → the G-backup test bites" || bad "(G-control) control did not fast-take"
# disabled latch blocks regardless of elapsed
_disabled_take=$( _take_calls=0; _fastpath_stagger_floor=0; _fastpath_disabled="bad config"; TAKEOVER_DELAY=120
    FIRST_DELINQUENT_TIME=$(( $(date +%s) - 30 )); LAST_LIVENESS_ACTIVE_TIME=0; LAST_TAKEOVER_TIME=0
    _last_confirm_attempt=0; _liveness_first_vote="100"; _takeover_alert_sent=""
    attempt_takeover >/dev/null 2>&1; echo "$_take_calls" )
[[ "$_disabled_take" == "0" ]] && ok "(G-disabled) _fastpath_disabled set → no fast-take at any elapsed (fail-closed)" || bad "(G-disabled) fast-took while disabled ($_disabled_take)"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
