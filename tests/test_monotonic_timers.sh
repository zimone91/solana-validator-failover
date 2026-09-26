#!/bin/bash
# v0.7 (Block 3, slice 1): SAFETY timers must run on the MONOTONIC clock (mono_now), not the
# steppable wall clock. AUDIT-5 MEASURED that a single chronyd makestep forward instantly matured
# the takeover delay / defeated the vote-liveness fence, and a backward step disarmed the holder
# self-fence. Drives the REAL shipped functions (source-to-MAIN-LOOP seam) under a controllable
# mono clock while the WALL clock steps mid-scenario:
#   (a)  +3600s wall step during the takeover delay → the delay does NOT mature early
#   (a2) NON-VACUOUS CONTROL (the old code, simulated by shadowing mono_now to the stepped wall
#        clock): the SAME scenario matures instantly at the step → (a)'s assertion bites
#   (b)  -3600s wall step during the standby holder self-fence frozen-slot sustain → still fires
#        on time (a backward step must not stall the mono-driven sustain)
#   (b2) CONTROL (wall-driven): the backward step disarms the fence for the whole horizon
#   (c)  boot-id restore semantics (real save_state/load_state, two-subshell idiom): same BOOT_ID →
#        SELF_FENCE_DEMOTE_TIME / cooldowns restore VERBATIM; different BOOT_ID (and the pre-v0.7
#        no-BOOT_ID state file) → restored stamp == the restore-time mono_now (lockout re-HELD in
#        full — never smaller, never toward expired); primary LAST_SWITCH_TIME twin included
#   (d)  helper sanity: mono_now/boot_id exist in BOTH daemons BYTE-IDENTICALLY (diff the extracted
#        definitions); on a no-/proc/uptime box mono_now falls back to `date +%s`; on Linux it
#        reads /proc/uptime (numeric, non-decreasing)
#   (e)  rollback safety: the legacy keys carry WALL values (dual-write)
#   (f)  6.3 fix round 2, R5: NON-CANONICAL persisted values (a hand edit or corruption) — a lockout/
#        cooldown re-HELD in full from now, a SAVE_TS makes the save stale, a baseline value is not
#        restored (per value; a slot restores as 0), the startup never aborted
#   (f2) R5 fence timing: the REAL check_self_fence_isolation after load_state on a corrupted save —
#        every fence the pre-fix tree had, kept; one documented residual (an octal-valid stall stamp)
# harness: tests/lib/harness.sh — ok/bad+banners, paths, harness_silence_sinks ONLY (this suite
# TESTS the clock: its dual _WALL_NOW/_MONO_NOW shims, seam cuts and parity checks stay local).

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
MONO0=5000           # mono origin — deliberately far from the wall origin so a cross-clock leak is loud
WALL0=1700000000     # wall origin
DELAY=60             # TAKEOVER_DELAY under test
ISO=30               # SELF_FENCE_ISOLATION_SECS under test

# ── (a) takeover delay vs a +3600s wall step ────────────────────────────────────────────────────
# $1 = "mono" (the shipped code: safety on mono_now) | "wall" (the OLD code simulated: mono_now
# shadowed to the stepped wall clock). Echoes the take offset from t0 in TRUE seconds, or -1.
sim_take() {
  local clock="$1"
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
  TAKEOVER_DELAY=$DELAY; TAKEOVER_COOLDOWN=0; EXTERNAL_CONFIRM_THROTTLE=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=10; VOTE_LIVENESS_EPSILON=2
  GOSSIP_VERIFY=false; DRY_RUN=false; WITNESS_FASTPATH=false
  harness_silence_sinks
  save_state(){ :; }
  date(){ [[ "$1" == "+%s" ]] && { echo "$_WALL_NOW"; return 0; }; command date "$@"; }
  if [[ "$clock" == "mono" ]]; then
      mono_now(){ echo "$_MONO_NOW"; }        # the shipped separation: safety reads the mono counter
  else
      mono_now(){ date +%s; }                 # OLD-code control: safety reads the (stepped) wall clock
  fi
  confirm_delinquency_external(){ return 0; }                          # externally CONFIRMED delinquent
  # frozen holder: staked lastVote constant; cluster tip advances with TRUE time (clock-independent)
  get_staked_liveness_sample(){ echo "5000 $(( 100000 + _TICK ))"; }
  took=-1; take_staked_identity(){ took=$_TICK; return 0; }
  _MONO_NOW=$MONO0; _WALL_NOW=$WALL0; _TICK=0
  FIRST_DELINQUENT_TIME=$(mono_now)   # primed via the run's SAFETY clock at t0 (as the main loop stamps it)
  LAST_LIVENESS_ACTIVE_TIME=0; LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0; SELF_FENCE_DEMOTE_TIME=0
  _delinq_window="1111111111"; _takeover_alert_sent=""
  _gossip_prefetched=false; _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0
  local t; for ((t=0; t<=120; t++)); do
      _TICK=$t
      _MONO_NOW=$(( MONO0 + t ))
      _WALL_NOW=$(( WALL0 + t )); [[ $t -ge 10 ]] && _WALL_NOW=$(( _WALL_NOW + 3600 ))   # +1h step at t=10
      attempt_takeover
      [[ $took -ge 0 ]] && break
  done
  echo "$took"
  )
}

# ── (b) holder self-fence frozen-slot sustain vs a -3600s wall step ─────────────────────────────
# Same clock modes. Echoes the fence-fire offset from t0 in TRUE seconds, or -1 (never fired).
sim_fence() {
  local clock="$1"
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; LOCAL_RPC="http://mock-local"
  STANDBY_SELF_FENCE=true; SELF_FENCE_ISOLATION_SECS=$ISO; SELF_FENCE_NOANSWER_SECS=30
  SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_VOTE_LAG_SLOTS=0; SELF_FENCE_VOTE_LAG_SECS=0
  DRY_RUN=false; CURRENT_IDENTITY="S1"
  harness_silence_sinks
  save_state(){ :; }; sleep(){ :; }
  date(){ [[ "$1" == "+%s" ]] && { echo "$_WALL_NOW"; return 0; }; command date "$@"; }
  if [[ "$clock" == "mono" ]]; then
      mono_now(){ echo "$_MONO_NOW"; }
  else
      mono_now(){ date +%s; }                 # OLD-code control: the fence timer rides the wall clock
  fi
  # LOCAL getSlot(confirmed) answers a CONSTANT slot — the frozen-slot signal
  curl(){ local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
          case "$d" in *getSlot*) printf '{"result":100000}'; return 0 ;; esac; return 7; }
  FENCED_AT=-1; give_back_identity(){ FENCED_AT=$_TICK; CURRENT_IDENTITY="U1"; return 0; }
  _MONO_NOW=$MONO0; _WALL_NOW=$WALL0; _TICK=0
  local t; for ((t=0; t<=120; t++)); do
      _TICK=$t
      _MONO_NOW=$(( MONO0 + t ))
      _WALL_NOW=$(( WALL0 + t )); [[ $t -ge 10 ]] && _WALL_NOW=$(( _WALL_NOW - 3600 ))   # -1h step at t=10
      check_self_fence_isolation >/dev/null
      [[ $FENCED_AT -ge 0 ]] && break
  done
  echo "$FENCED_AT"
  )
}

# ── (c) boot-id restore semantics (REAL save_state/load_state, two-subshell idiom) ──────────────
# Phase 1: save under boot $1 at mono $2 with the given stamps. $3=script $4=state_file
save_phase() {
  local boot="$1" mono="$2" script="$3" sfile="$4"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; CURRENT_IDENTITY="U1"
    STATE_DIR="$(dirname "$sfile")"; STATE_FILE="$sfile"
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    boot_id(){ echo "$boot"; }; mono_now(){ echo "$mono"; }
    SELF_FENCE_DEMOTE_TIME=4000; LAST_TAKEOVER_TIME=4200; LAST_SWITCH_TIME=4100
    save_state
  )
}
# Phase 2: load under boot $1 at mono $2; echoes "<SELF_FENCE_DEMOTE_TIME>|<cooldown var>"
load_phase() {
  local boot="$1" mono="$2" script="$3" sfile="$4" key="$5"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"
    STATE_DIR="$(dirname "$sfile")"; STATE_FILE="$sfile"; STATE_MAX_AGE_SECS=900
    PRIMARY_SELF_FENCE=true; STANDBY_SELF_FENCE=true
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    boot_id(){ echo "$boot"; }; mono_now(){ echo "$mono"; }
    load_state
    printf '%s|%s\n' "${SELF_FENCE_DEMOTE_TIME:-unset}" "${!key}"
  )
}

title_banner "Monotonic SAFETY timers (v0.7 Block 3)"

echo ""
echo "─── (a) takeover delay vs a +3600s wall step at t=10 (delay ${DELAY}s) ───"
TAKE_MONO=$(sim_take mono)
TAKE_WALL=$(sim_take wall)
echo "    mono-clock code: take at t0+${TAKE_MONO}s | wall-clock control: take at t0+${TAKE_WALL}s"
if [[ $TAKE_MONO -ge $DELAY ]]; then
    ok "(a) wall step ignored — the delay matured only after the FULL ${DELAY}s of true time (t0+${TAKE_MONO}s)"
else
    bad "(a) delay matured EARLY at t0+${TAKE_MONO}s (< ${DELAY}s) — a wall step still reaches a safety timer"
fi
if [[ $TAKE_MONO -ge 0 && $TAKE_MONO -le $(( DELAY + 2 )) ]]; then
    ok "(a1) availability intact — the take still fires promptly once truly matured (t0+${TAKE_MONO}s)"
else
    bad "(a1) take never fired / fired late (t0+${TAKE_MONO}s) — the mono migration over-blocked"
fi
if [[ $TAKE_WALL -ge 0 && $TAKE_WALL -lt $DELAY ]]; then
    ok "(a2) NON-VACUOUS control: wall-clock timing matures instantly at the step (t0+${TAKE_WALL}s < ${DELAY}s) — (a) bites"
else
    bad "(a2) control did not mature early (t0+${TAKE_WALL}s) — the scenario no longer exercises the step"
fi

echo ""
echo "─── (b) holder self-fence frozen-slot sustain (${ISO}s) vs a -3600s wall step at t=10 ───"
FENCE_MONO=$(sim_fence mono)
FENCE_WALL=$(sim_fence wall)
echo "    mono-clock code: fence at t0+${FENCE_MONO}s | wall-clock control: fence at t0+${FENCE_WALL}s (-1 = never in 120s)"
if [[ $FENCE_MONO -ge $ISO && $FENCE_MONO -le $(( ISO + 1 )) ]]; then
    ok "(b) backward wall step ignored — fence fired on time at t0+${FENCE_MONO}s (sustain ${ISO}s)"
else
    bad "(b) fence mistimed (t0+${FENCE_MONO}s, expected ~${ISO}s) — the sustain still reads a steppable clock"
fi
if [[ $FENCE_WALL -eq -1 ]]; then
    ok "(b2) NON-VACUOUS control: wall-clock timing is DISARMED by the backward step (no fire in 120s) — (b) bites"
else
    bad "(b2) control fired at t0+${FENCE_WALL}s despite the backward step — the scenario no longer exercises it"
fi

echo ""
echo "─── (c) boot-id restore semantics (same boot verbatim / different boot re-HELD) ───"
for SCRIPT in "$STANDBY" "$PRIMARY"; do
  # The H1.3 re-take lockout (SELF_FENCE_DEMOTE_TIME) exists only on the STANDBY; the PRIMARY's
  # persisted safety stamp is LAST_SWITCH_TIME (recovery delay/cooldown) — expect "unset" there.
  if [[ "$SCRIPT" == "$STANDBY" ]]; then NAME=STANDBY; KEY=LAST_TAKEOVER_TIME; SAME_WANT="4000|4200"; HELD2="777|777"; HELD3="888|888"
  else NAME=PRIMARY; KEY=LAST_SWITCH_TIME; SAME_WANT="unset|4100"; HELD2="unset|777"; HELD3="unset|888"; fi
  TMPD=$(mktemp -d); SFILE="$TMPD/state-test"
  save_phase "boot-A" 5000 "$SCRIPT" "$SFILE"

  out=$(load_phase "boot-A" 6000 "$SCRIPT" "$SFILE" "$KEY")
  if [[ "$out" == "$SAME_WANT" ]]; then
      ok "[$NAME] (c1) SAME boot: stamps restored VERBATIM ($out)"
  else
      bad "[$NAME] (c1) same-boot restore wrong (got '$out', want '$SAME_WANT')"
  fi

  out=$(load_phase "boot-B" 777 "$SCRIPT" "$SFILE" "$KEY")
  if [[ "$out" == "$HELD2" ]]; then
      ok "[$NAME] (c2) DIFFERENT boot: stamps re-stamped to the restore-time mono_now (777) — lockout/cooldown re-HELD in full, never smaller"
  else
      bad "[$NAME] (c2) different-boot restore wrong (got '$out', want '$HELD2' == restore-time mono_now)"
  fi

  # pre-v0.7 state file (no BOOT_ID line) → must read as DIFFERENT boot → re-held (safe direction)
  grep -v '^BOOT_ID=' "$SFILE" > "$SFILE.old" && mv "$SFILE.old" "$SFILE"
  out=$(load_phase "boot-A" 888 "$SCRIPT" "$SFILE" "$KEY")
  if [[ "$out" == "$HELD3" ]]; then
      ok "[$NAME] (c3) pre-v0.7 state file (no BOOT_ID): treated as different boot → re-HELD (888)"
  else
      bad "[$NAME] (c3) old-format restore wrong (got '$out', want '$HELD3')"
  fi
  rm -rf "$TMPD"
done

echo ""
echo "─── (d) helper sanity: byte-identical twins + platform behavior ───"
for FN in mono_now boot_id; do
  if extract_twin "^${FN}()" '^}' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
      ok "(d) ${FN}() present in BOTH daemons and BYTE-IDENTICAL ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)"
  else
      bad "(d) ${FN}() missing or DIVERGED between the daemons (twin-drift)"
  fi
done
d_out=$(
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC" >/dev/null 2>&1; rm -f "$SRC"
  if [[ -r /proc/uptime ]]; then
      a=$(mono_now); b=$(mono_now)
      [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && $b -ge $a ]] && echo "linux-ok" || echo "linux-bad a=$a b=$b"
  else
      date(){ [[ "$1" == "+%s" ]] && { echo 424242; return 0; }; command date "$@"; }
      [[ "$(mono_now)" == "424242" ]] && echo "fallback-ok" || echo "fallback-bad $(mono_now)"
  fi
)
case "$d_out" in
  linux-ok)    ok "(d2) /proc/uptime present: mono_now is numeric and non-decreasing" ;;
  fallback-ok) ok "(d2) no /proc/uptime (harness): mono_now falls back to date +%s (drove it through the date mock)" ;;
  *)           bad "(d2) mono_now platform behavior wrong ($d_out)" ;;
esac

echo ""
echo "─── (e) rollback safety by construction: legacy keys carry WALL values ───"
# A daemon <= v0.6.10 reading a v0.7 state file uses wall arithmetic on the LEGACY keys. Dual-write
# must therefore keep those keys wall-recent: for a lockout stamped "now", an old daemon computes
# (wall_now - legacy) ~ 0 << 600 => lockout ACTIVE after a rollback, with NO operator step.
# Control: revert dual-write (legacy key = raw mono) => on a real-uptime host the legacy value is
# tiny => (wall_now - legacy) = huge => lockout read as long-expired => (e1) fails.
_e=$(
  set +e
  SRC_E=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC_E"; source "$SRC_E"; rm -f "$SRC_E"
  log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
  TMPD=$(mktemp -d); STATE_DIR="$TMPD"; STATE_FILE="$TMPD/state-standby"
  STAKED_PUBKEY="S"; CURRENT_IDENTITY="U"
  SELF_FENCE_DEMOTE_TIME=$(mono_now)          # lockout stamped "now" in the daemon's own clock
  LAST_TAKEOVER_TIME=$(mono_now)
  save_state
  _w=$(date +%s)
  _leg=$(grep '^SELF_FENCE_DEMOTE_TIME=' "$STATE_FILE" | cut -d= -f2)
  _mono=$(grep '^SELF_FENCE_DEMOTE_MONO=' "$STATE_FILE" | cut -d= -f2)
  _legt=$(grep '^LAST_TAKEOVER_TIME=' "$STATE_FILE" | cut -d= -f2)
  # zero must survive the conversion (0 = "no lockout" — an invented cooldown would block a first take)
  SELF_FENCE_DEMOTE_TIME=0; LAST_TAKEOVER_TIME=0
  save_state
  _leg0=$(grep '^SELF_FENCE_DEMOTE_TIME=' "$STATE_FILE" | cut -d= -f2)
  rm -rf "$TMPD"
  printf 'age=%s tage=%s mono=%s zero=%s' "$(( _w - _leg ))" "$(( _w - _legt ))" "$_mono" "$_leg0"
)
_age=${_e#age=}; _age=${_age%% *}
_tage=${_e#*tage=}; _tage=${_tage%% *}
_zero=${_e##*zero=}
if [[ "$_age" -ge 0 && "$_age" -lt 60 && "$_tage" -ge 0 && "$_tage" -lt 60 ]]; then
  ok "(e1) legacy lockout/cooldown keys are wall-recent (old-daemon view: elapsed ${_age}s < 600s => ACTIVE) [$_e]"
else
  bad "(e1) legacy keys not wall-recent — a rolled-back daemon would misread the lockout ($_e)"
fi
[[ "$_zero" == "0" ]] \
  && ok "(e2) zero stamp survives the wall conversion (no invented cooldown)" \
  || bad "(e2) zero became '$_zero' — an invented cooldown would block a legitimate first takeover"

# ── (f) 6.3 fix round 2, R5 (P2-INERT-4): NON-CANONICAL persisted values ──────────────────────────
# load_state reads every persisted number through _state_get → the ONE canonical-integer validator. A
# LOCKOUT/COOLDOWN present but non-canonical re-holds IN FULL from now (the cross-boot rule's direction)
# and says so; a non-canonical SAVE_TS makes the whole save stale (no restore); a non-canonical baseline
# value is not restored — per value, the rest of the fresh save restores (a slot restores as 0: a baseline
# existed, its value is unknown); no arithmetic on a raw persisted value. The load runs as a startup-like TOP-LEVEL command (fake_startup), so an
# arithmetic abort that discards the rest of the startup command is observable (after=0). Same boot,
# restore at mono 100000, wall 200000 (a fresh SAVE_TS is 199990).
# Pre-fix red (f22d492): 0777 restored as "0777" (bash reads OCTAL 511 → the lockout silently expired);
# 0999 not restored ('value too great for base'); SAVE_TS=0999 and SF_ADVANCE_MONO=0999 aborted the rest
# of the startup command (after=0 — on an armed holder READY is never sent); the cooldown stamps 0999
# restored raw.
r5_load() {   # $1=script, then the state lines → "<demote>|<cooldown>|<baseline slot>|<restore_pending>|after=<0|1>|warns=<n>"
  local script="$1"; shift
  local td; td=$(mktemp -d)
  printf '%s\n' "$@" "BOOT_ID=boot-A" > "$td/state-test"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"
    STATE_DIR="$td"; STATE_FILE="$td/state-test"; _DEFAULT_STATE_FILE="$td/none"; STATE_MAX_AGE_SECS=600
    PRIMARY_SELF_FENCE=true; STANDBY_SELF_FENCE=true
    _R5W=0; log_info(){ :; }; log_warn(){ _R5W=$(( _R5W + 1 )); }; log_error(){ :; }
    boot_id(){ echo "boot-A"; }; mono_now(){ echo 100000; }
    date(){ if [[ "$1" == "+%s" ]]; then echo 200000; return 0; fi; command date "$@"; }
    SELF_FENCE_DEMOTE_TIME=0; LAST_TAKEOVER_TIME=0; LAST_SWITCH_TIME=0; _last_confirmed_slot=""; _selffence_restore_pending=0
    _R5A=0
    fake_startup() { load_state; _R5A=1; }
    fake_startup 2>/dev/null
    local cd="$LAST_TAKEOVER_TIME"; [[ "$script" == "$PRIMARY" ]] && cd="$LAST_SWITCH_TIME"
    printf '%s|%s|%s|%s|after=%s|warns=%s\n' "$SELF_FENCE_DEMOTE_TIME" "$cd" "${_last_confirmed_slot:-none}" "${_selffence_restore_pending:-0}" "$_R5A" "$_R5W"
  )
  rm -rf "$td"
}
echo ""
echo "─── (f) R5: non-canonical persisted values → lockout/cooldown re-HELD in full; SAVE_TS stale; a baseline value not restored; startup never aborted ───"
f_ok=1; f_rows=""
f_case() {   # $1=label $2=want (prefix match on the first four fields + after) $3=script, then the state lines
  local label="$1" want="$2" script="$3"; shift 3
  local got; got=$(r5_load "$script" "$@")
  if [[ "$got" == "$want"* && ( "$want" == *"after=1"* ) ]]; then f_rows="$f_rows $label"; else f_ok=0; bad "(f) $label: got '$got', want '$want…'"; fi
}
f_case "S:lockout=0777→held"    "100000|0|none|0|after=1"   "$STANDBY" "SELF_FENCE_DEMOTE_MONO=0777"
f_case "S:lockout=0999→held"    "100000|0|none|0|after=1"   "$STANDBY" "SELF_FENCE_DEMOTE_MONO=0999"
f_case "S:lockout=2^64+N→held"  "100000|0|none|0|after=1"   "$STANDBY" "SELF_FENCE_DEMOTE_MONO=18446744073709651606"
f_case "S:cooldown=0999→held"   "0|100000|none|0|after=1"   "$STANDBY" "LAST_TAKEOVER_MONO=0999"
f_case "S:SAVE_TS=0999→stale"   "99990|0|none|0|after=1"    "$STANDBY" "SELF_FENCE_DEMOTE_MONO=99990" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=0999"
f_case "S:SF_ADVANCE=0999→unrestored" "0|0|500|0|after=1"  "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=0999" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:SLOT=0999→0"          "0|0|0|1|after=1"           "$STANDBY" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:HEALTHY=08→rest restored" "0|0|500|1|after=1"     "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "SF_VOTELAG_HEALTHY=08" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:canonical control"    "99990|0|500|1|after=1"     "$STANDBY" "SELF_FENCE_DEMOTE_MONO=99990" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:cooldown=0999→held"   "0|100000|none|0|after=1"   "$PRIMARY" "LAST_SWITCH_MONO=0999"
f_case "P:SAVE_TS=0999→stale"   "0|0|none|0|after=1"        "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=0999"
f_case "P:SF_ADVANCE=0777→unrestored" "0|0|500|0|after=1"  "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=0777" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:SLOT=0999→0"          "0|0|0|1|after=1"           "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:canonical control"    "0|99990|500|1|after=1"     "$PRIMARY" "LAST_SWITCH_MONO=99990" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
[[ $f_ok -eq 1 ]] && ok "(f) R5 —$f_rows: a non-canonical lockout/cooldown stamp re-HOLDS IN FULL from the restore instant (100000, a WARN names it), a non-canonical SAVE_TS leaves the whole baseline unrestored (stale), a non-canonical baseline value is not restored while the rest of the fresh save is (a slot restores as 0: every live slot is past it, and the advance backdate still arms), and the startup command always runs past load_state (after=1); canonical stamps restore verbatim. Pre-fix: 0777 → 'restored' as octal 511 (expired), 0999 → dropped, SAVE_TS/SF_ADVANCE 0999 → the rest of the startup command discarded"

# ── (f2) R5 fence timing: the REAL check_self_fence_isolation after load_state on a corrupted save ────
# Same boot, persisted role staked, SAVE_TS fresh; SELF_FENCE_ISOLATION/NOANSWER/VOTE_LAG_SECS = 30,
# VOTE_LAG_SLOTS 10; the check runs every 5 s from the restore (mono 100000) with the LOCAL node frozen
# (confirmed slot stuck at 500), silent (getSlot never answers), lagging (slot advancing from 600, own
# lastVote 100 behind the cluster max) or healthy (slot advancing from 600, own vote current). Echoes the
# fire time in seconds after the restore, or "never" (125 s horizon). MEASURED on the pre-fix tree
# (f22d492) and on the whole-snapshot variant this round first wrote: row 1 is the canonical control;
# on rows 2–5 the whole-snapshot variant fenced LATER or NEVER (30 s / never / never / never) and
# f22d492 fenced as this tree does; on the last two rows f22d492 misread a leading-zero value.
r5_fence() {   # $1=script $2=mode, then the state lines → "fire=<s>|never"
  local script="$1" mode="$2"; shift 2
  local td; td=$(mktemp -d)
  printf '%s\n' "$@" "BOOT_ID=boot-A" > "$td/state-test"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; LOCAL_RPC="http://local.invalid"
    STATE_DIR="$td"; STATE_FILE="$td/state-test"; _DEFAULT_STATE_FILE="$td/none"; STATE_MAX_AGE_SECS=600
    PRIMARY_SELF_FENCE=true; STANDBY_SELF_FENCE=true
    SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_MAX_BEHIND=0
    SELF_FENCE_VOTE_LAG_SLOTS=10; SELF_FENCE_VOTE_LAG_SECS=30; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }; alert(){ :; }
    boot_id(){ echo "boot-A"; }
    _R5M=100000; mono_now(){ echo "$_R5M"; }
    date(){ if [[ "$1" == "+%s" ]]; then echo 200000; return 0; fi; command date "$@"; }
    _watchdog_pet(){ :; }
    _R5F=""
    _selffence_demote(){ _R5F=$(( _R5M - 100000 )); return 0; }
    switch_to_unstaked(){ _R5F=$(( _R5M - 100000 )); return 0; }
    curl(){
      local d="" s own
      while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
      s=$(( 600 + _R5M - 100000 ))
      case "$d" in
        *getSlot*)
          [[ "$mode" == "silent" ]] && return 7
          [[ "$mode" == "frozen" ]] && s=500
          printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$s" ;;
        *getVoteAccounts*)
          own=$s; [[ "$mode" == "lag" ]] && own=$(( s - 100 ))
          printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"V1","lastVote":%s},{"votePubkey":"X","lastVote":%s}],"delinquent":[]},"id":1}' "$own" "$s" ;;
        *) return 7 ;;
      esac
    }
    load_state >/dev/null 2>&1
    local i
    for (( i = 0; i < 25; i++ )); do
      check_self_fence_isolation >/dev/null 2>&1
      [[ -n "$_R5F" ]] && break
      _R5M=$(( _R5M + 5 ))
    done
    echo "fire=${_R5F:-never}"
  )
  rm -rf "$td"
}
echo ""
echo "─── (f2) R5 fence timing: the REAL self-fence after load_state on a corrupted save (both daemons) ───"
f2_ok=1; f2_rows=""
f2_case() {   # $1=label $2=want (exact) $3=mode, then the state lines — runs BOTH daemons
  local label="$1" want="$2" mode="$3"; shift 3
  local sc got
  for sc in "$STANDBY" "$PRIMARY"; do
    got=$(r5_fence "$sc" "$mode" "$@" "ROLE_AT_SAVE=staked" "SAVE_TS=199990")
    if [[ "$got" != "fire=$want" ]]; then f2_ok=0; bad "(f2) $label [$(basename "$sc")]: got '$got', want 'fire=$want'"; fi
  done
  f2_rows="$f2_rows $label→$want;"
}
f2_case "frozen canonical 1000s"         0     frozen "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000"
f2_case "frozen HEALTHY=007"             0     frozen "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "SF_VOTELAG_HEALTHY=007"
f2_case "silent NOANSWER=0999"           30    silent "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=0999"
f2_case "silent SLOT=0500 noanswer-10s"  20    silent "SF_LAST_CONFIRMED_SLOT=0500" "SF_NOANSWER_MONO=99990"
f2_case "lag HEALTHY=08 1000s"           0     lag    "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000" "SF_VOTELAG_BASELINE=1" "SF_VOTELAG_HEALTHY=08"
f2_case "healthy SLOT=07777"             never healthy "SF_LAST_CONFIRMED_SLOT=07777" "SF_ADVANCE_MONO=99000"
f2_case "frozen ADVANCE=0777 (residual)" 30    frozen "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=0777"
[[ $f2_ok -eq 1 ]] && ok "(f2) R5 fence timing, both daemons —$f2_rows per-value restore keeps every fence the pre-fix tree had (the whole-snapshot variant: 30 s / never / never / never where rows 2–5 fence at 0 / 30 / 20 / 0 s); a healthy holder with a non-canonical slot is not fenced (pre-fix: fenced at 0 s — '07777' read as octal 4095, above the live slot). DOCUMENTED RESIDUAL (reviewer to ratify): a non-canonical stall/silence/lag STAMP starts its timer fresh — frozen + SF_ADVANCE_MONO=0777 fences at 30 s where the pre-fix tree fenced at 0 s by reading '0777' as octal 511, an ancient stall (the same for SF_NOANSWER_MONO / SF_VOTELAG_MONO=0777: 0 → 30 s); the stamp's true age is unknown and it is no longer read"

results_banner
