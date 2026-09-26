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
#        cooldown re-HELD in full from now, a SAVE_TS makes the save stale, per value the rest restores;
#        fix round 3, S2: a stall/silence/lag stamp restores as ANCIENT behind the first-read evidence, a
#        slot as 0 with the stall backdate pending past the reference read; fix round 4: W2 — a young stall
#        stamp over such a slot anchors at the restore instant; W4 — a same-boot stamp later than now is
#        ANCIENT; the startup never aborted
#   (f2) R5 + S2 fence timing: the REAL check_self_fence_isolation after load_state on a corrupted save,
#        at grace 0 and the shipped 30 — the holder still frozen / silent / lagging fences at the first
#        read that shows it (a non-canonical slot: at the first read at or after reference + 15 s that still
#        shows the slot not past the reference read — W2), a healthy one never, a paused healthy one never
#        (W2); the future-stamp and latch rows (W4)
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
# and says so; a non-canonical SAVE_TS makes the whole save stale (no restore); a non-canonical value is
# handled per value — the rest of the fresh save restores; no arithmetic on a raw persisted value. Fix
# round 3 (S2): a non-canonical stall / silence / lag STAMP restores as ANCIENT (1) behind H3's first-read
# evidence (its pending arms: rp:ra / np:rn / vp:rv below), and a non-canonical SLOT restores as 0 with
# the stall backdate pending past the reference read (rp=2 — fix round 4, W2: behind a 15 s live-evidence
# floor). The load runs as a startup-like TOP-LEVEL
# command (fake_startup), so an arithmetic abort that discards the rest of the startup command is
# observable (after=0). Same boot, restore at mono 100000, wall 200000 (a fresh SAVE_TS is 199990).
# Pre-fix red (f22d492): 0777 restored as "0777" (bash reads OCTAL 511 → the lockout silently expired);
# 0999 not restored ('value too great for base'); SAVE_TS=0999 and SF_ADVANCE_MONO=0999 aborted the rest
# of the startup command (after=0 — on an armed holder READY is never sent); the cooldown stamps 0999
# restored raw. Round-3 red (e917c04): a non-canonical stamp armed nothing (rp/np/vp 0 — its timer
# started fresh), and a non-canonical slot armed rp=1 against the restored 0, which every live slot passes.
# Round-4 red (7ab7eca): a YOUNG stall stamp over a non-canonical slot armed nothing (W2: now rp=2 anchored
# at the restore instant); a same-boot stamp LATER than now armed its raw value (a silence/lag clock read
# negative — never due) or nothing (the stall) (W4: now ANCIENT, 1).
r5_load() {   # $1=script, then the state lines → "<demote>|<cooldown>|<baseline slot>|<rp>:<ra>|<np>:<rn>|<vp>:<rv>|after=<0|1>|warns=<n>"
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
    printf '%s|%s|%s|%s:%s|%s:%s|%s:%s|after=%s|warns=%s\n' "$SELF_FENCE_DEMOTE_TIME" "$cd" "${_last_confirmed_slot:-none}" \
        "${_selffence_restore_pending:-0}" "${_selffence_restored_advance_ts:-0}" "${_selffence_noanswer_restore_pending:-0}" "${_selffence_restored_noanswer_since:-0}" \
        "${_selffence_votelag_restore_pending:-0}" "${_selffence_restored_votelag_since:-0}" "$_R5A" "$_R5W"
  )
  rm -rf "$td"
}
echo ""
echo "─── (f) R5 + S2: non-canonical persisted values → lockout/cooldown re-HELD in full; SAVE_TS stale; a stamp ANCIENT behind first-read evidence; a slot 0 with the backdate pending (the reference, then live evidence); startup never aborted ───"
f_ok=1; f_rows=""
f_case() {   # $1=label $2=want (prefix match through after=) $3=script, then the state lines
  local label="$1" want="$2" script="$3"; shift 3
  local got; got=$(r5_load "$script" "$@")
  if [[ "$got" == "$want"* && ( "$want" == *"after=1"* ) ]]; then f_rows="$f_rows $label"; else f_ok=0; bad "(f) $label: got '$got', want '$want…'"; fi
}
f_case "S:lockout=0777→held"    "100000|0|none|0:0|0:0|0:0|after=1"   "$STANDBY" "SELF_FENCE_DEMOTE_MONO=0777"
f_case "S:lockout=0999→held"    "100000|0|none|0:0|0:0|0:0|after=1"   "$STANDBY" "SELF_FENCE_DEMOTE_MONO=0999"
f_case "S:lockout=2^64+N→held"  "100000|0|none|0:0|0:0|0:0|after=1"   "$STANDBY" "SELF_FENCE_DEMOTE_MONO=18446744073709651606"
f_case "S:cooldown=0999→held"   "0|100000|none|0:0|0:0|0:0|after=1"   "$STANDBY" "LAST_TAKEOVER_MONO=0999"
f_case "S:SAVE_TS=0999→stale"   "99990|0|none|0:0|0:0|0:0|after=1"    "$STANDBY" "SELF_FENCE_DEMOTE_MONO=99990" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=0999"
f_case "S:ADVANCE=0999→ancient" "0|0|500|1:1|0:0|0:0|after=1"         "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=0999" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:NOANSWER=0777→ancient" "0|0|500|0:0|1:1|0:0|after=1"        "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=0777" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:VOTELAG=abc→ancient"  "0|0|500|0:0|0:0|1:1|after=1"         "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=abc" "SF_VOTELAG_BASELINE=1" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:SLOT=0999→0, reference then live evidence" "0|0|0|2:99000|0:0|0:0|after=1" "$STANDBY" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:HEALTHY=08→rest restored" "0|0|500|1:99000|0:0|0:0|after=1" "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "SF_VOTELAG_HEALTHY=08" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:canonical control"    "99990|0|500|1:99000|0:0|0:0|after=1" "$STANDBY" "SELF_FENCE_DEMOTE_MONO=99990" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:cooldown=0999→held"   "0|100000|none|0:0|0:0|0:0|after=1"   "$PRIMARY" "LAST_SWITCH_MONO=0999"
f_case "P:SAVE_TS=0999→stale"   "0|0|none|0:0|0:0|0:0|after=1"        "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=0999"
f_case "P:ADVANCE=0777→ancient" "0|0|500|1:1|0:0|0:0|after=1"         "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=0777" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:NOANSWER=2^64+N→ancient" "0|0|500|0:0|1:1|0:0|after=1"      "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=18446744073709651606" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:SLOT=0999→0, reference then live evidence" "0|0|0|2:99000|0:0|0:0|after=1" "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:canonical control"    "0|99990|500|1:99000|0:0|0:0|after=1" "$PRIMARY" "LAST_SWITCH_MONO=99990" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
# fix round 4: W2 — a YOUNG stall stamp (10 s) over a non-canonical slot arms pending 2 anchored at the RESTORE
# instant (100000), never at the stamp; the canonical-slot young stamp still arms nothing. W4 — a same-boot
# stamp LATER than now restores as ANCIENT (1); across a boot nothing is armed (as before).
f_case "S:SLOT=0999 young stall→anchor restore" "0|0|0|2:100000|0:0|0:0|after=1" "$STANDBY" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99990" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:young stall, canonical slot" "0|0|500|0:0|0:0|0:0|after=1"   "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99990" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:ADVANCE=future→ancient" "0|0|500|1:1|0:0|0:0|after=1"       "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=100500" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:NOANSWER=2^63-1→ancient" "0|0|500|0:0|1:1|0:0|after=1"      "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=9223372036854775807" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "S:VOTELAG=future→ancient" "0|0|500|0:0|0:0|1:1|after=1"       "$STANDBY" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=100500" "SF_VOTELAG_BASELINE=1" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:SLOT=0999 young stall→anchor restore" "0|0|0|2:100000|0:0|0:0|after=1" "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99990" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
f_case "P:NOANSWER=future→ancient" "0|0|500|0:0|1:1|0:0|after=1"      "$PRIMARY" "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=100500" "ROLE_AT_SAVE=staked" "SAVE_TS=199990"
[[ $f_ok -eq 1 ]] && ok "(f) R5 + S2 + W2 + W4 —$f_rows: a non-canonical lockout/cooldown stamp re-HOLDS IN FULL from the restore instant (100000, a WARN names it); a non-canonical SAVE_TS leaves the whole baseline unrestored (stale); a non-canonical stall / silence / lag STAMP — and (W4) a same-boot one LATER than now — restores as ANCIENT: its pending arms with the stamp 1, applied only on first-read evidence (see (f2)); a non-canonical SLOT restores as 0 with the stall backdate pending past the reference read (rp=2) — over a stall a window old the persisted stamp, over a YOUNG one (W2) the restore instant (100000); a non-canonical hysteresis streak is not restored while the rest of the fresh save is; the startup command always runs past load_state (after=1); canonical stamps restore verbatim. Pre-fix f22d492: 0777 → 'restored' as octal 511 (expired), 0999 → dropped, SAVE_TS/SF_ADVANCE 0999 → the rest of the startup command discarded. Pre-fix e917c04: a non-canonical stamp armed nothing, and the slot armed rp=1 against the restored 0 — every live slot passes it, so the backdate could never apply. Pre-fix 7ab7eca: a young stamp over a corrupted slot armed nothing (rp 0) and a future stamp armed its raw value (never due) or nothing (the stall)"

# ── (f2) R5 + S2 fence timing: the REAL check_self_fence_isolation after load_state on a corrupted save ─
# Same boot, persisted role staked, SAVE_TS fresh; SELF_FENCE_ISOLATION/NOANSWER/VOTE_LAG_SECS = 30,
# VOTE_LAG_SLOTS 10; the check runs every 5 s from the restore (mono 100000) — or, with R5_GRACE=<s>, from
# the end of a startup grace that long (the shipped STARTUP_GRACE is 30) — with the LOCAL node frozen
# (confirmed slot stuck at 500), silent (getSlot never answers), lagging (slot advancing from 600, own
# lastVote 100 behind the cluster max) or healthy (slot advancing from 600, own vote current). Echoes the
# fire time in seconds after the restore, or "never" (125 s horizon after the grace). Rows 1–6 are round
# 2's (MEASURED there on f22d492 and on the whole-snapshot variant); the rest are fix round 3's S2 rows,
# red on e917c04, where a non-canonical stamp started its timer fresh and a non-canonical slot's backdate
# could never apply: silent NOANSWER=0777 30 → 0 s (grace 30: 60 → 30), lagging VOTELAG=0777 30 → 0
# (60 → 30), frozen ADVANCE=0777 30 → 0, frozen SLOT=0999 over a canonical 1000 s stall 30 → 5 (grace 30:
# 60 → 35 — the second read decided; f22d492's 30 there was its octal misread, which fenced the HEALTHY
# holder at 30 as well). Fix round 4 moves that row to 15 / 45 (W2: the decision waits 15 s of live evidence
# past the reference read — round 3's second-read decision fenced a PAUSED HEALTHY holder, the C F C / C D C
# / C S F C rows, at 5 / 5 / 10 s; grace 30: 35 / 35 / 40) and adds the young-stamp member (60 → 45 at grace
# 30), the future-stamp and latch rows (W4; every tree before: never) and the absent-latch residual. Every
# healthy row: never, on this tree. mode "seq" + R5_SEQ: per-read letters (C advances, F holds, D answers 5
# below the last advance, S silent; the last repeats), the own vote current.
r5_fence() {   # $1=script $2=mode, then the state lines → "fire=<s>|never"   (R5_GRACE: seconds before the first check)
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
          [[ "$mode" == "silent" || "${_R5L:-}" == "S" ]] && return 7
          [[ "$mode" == "frozen" ]] && s=500
          [[ -n "${_R5S:-}" ]] && s=$_R5S
          printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$s" ;;
        *getVoteAccounts*)
          own=$s; [[ "$mode" == "lag" ]] && own=$(( s - 100 ))
          printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"V1","lastVote":%s},{"votePubkey":"X","lastVote":%s}],"delinquent":[]},"id":1}' "$own" "$s" ;;
        *) return 7 ;;
      esac
    }
    load_state >/dev/null 2>&1
    _R5M=$(( _R5M + ${R5_GRACE:-0} ))   # the startup grace between the restore and the first check
    local i _R5C=0 _R5L="" _R5S=""
    for (( i = 0; i < 25; i++ )); do
      if [[ -n "${R5_SEQ:-}" ]]; then   # fix round 4: per-read letters (the last repeats) — C advances 8 slots, F holds, D answers 5 below the last advance, S is silent
        _R5L=${R5_SEQ:$(( i < ${#R5_SEQ} ? i : ${#R5_SEQ} - 1 )):1}
        case "$_R5L" in C) _R5C=$(( _R5C + 8 )); _R5S=$(( 600 + _R5C )) ;; F) _R5S=$(( 600 + _R5C )) ;; D) _R5S=$(( 595 + _R5C )) ;; esac
      fi
      check_self_fence_isolation >/dev/null 2>&1
      [[ -n "$_R5F" ]] && break
      _R5M=$(( _R5M + 5 ))
    done
    echo "fire=${_R5F:-never}"
  )
  rm -rf "$td"
}
echo ""
echo "─── (f2) R5 + S2 fence timing: the REAL self-fence after load_state on a corrupted save (both daemons, grace 0 and 30) ───"
f2_ok=1; f2_rows=""
f2_case() {   # $1=label $2=want (exact) $3=mode $4=grace, then the state lines — runs BOTH daemons
  local label="$1" want="$2" mode="$3" gr="$4"; shift 4
  local sc got
  for sc in "$STANDBY" "$PRIMARY"; do
    got=$(R5_GRACE="$gr" r5_fence "$sc" "$mode" "$@" "ROLE_AT_SAVE=staked" "SAVE_TS=199990")
    if [[ "$got" != "fire=$want" ]]; then f2_ok=0; bad "(f2) $label grace=$gr [$(basename "$sc")]: got '$got', want 'fire=$want'"; fi
  done
  f2_rows="$f2_rows $label${gr:+ (grace $gr)}→$want;"
}
f2_case "frozen canonical 1000s"         0     frozen  "" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000"
f2_case "frozen HEALTHY=007"             0     frozen  "" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=99000" "SF_VOTELAG_HEALTHY=007"
f2_case "silent NOANSWER=0999"           0     silent  "" "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=0999"
f2_case "silent SLOT=0500 noanswer-10s"  20    silent  "" "SF_LAST_CONFIRMED_SLOT=0500" "SF_NOANSWER_MONO=99990"
f2_case "lag HEALTHY=08 1000s"           0     lag     "" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000" "SF_VOTELAG_BASELINE=1" "SF_VOTELAG_HEALTHY=08"
f2_case "healthy SLOT=07777"             never healthy "" "SF_LAST_CONFIRMED_SLOT=07777" "SF_ADVANCE_MONO=99000"
f2_case "frozen ADVANCE=0777"            0     frozen  "" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=0777"
f2_case "silent NOANSWER=0777"           30    silent  30 "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=0777"
f2_case "lag VOTELAG=0777"               0     lag     "" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=0777" "SF_VOTELAG_BASELINE=1"
f2_case "lag VOTELAG=0777"               30    lag     30 "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=0777" "SF_VOTELAG_BASELINE=1"
f2_case "frozen SLOT=0999 stall 1000s"   15    frozen  "" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000"
f2_case "frozen SLOT=0999 stall 1000s"   45    frozen  30 "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000"
f2_case "healthy SLOT=0999 stall 1000s"  never healthy 30 "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000"
f2_case "healthy ADVANCE=0777"           never healthy 30 "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=0777"
f2_case "healthy NOANSWER=0777"          never healthy 30 "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=0777"
f2_case "healthy VOTELAG=0777"           never healthy 30 "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=0777" "SF_VOTELAG_BASELINE=1"
# fix round 4, W2 (H4-RP2-HEALTHY-PAUSE): the unknown slot's decision waits SELFFENCE_RESTORE_CONFIRM_SECS
# (15 s) past the reference read — a HEALTHY holder whose confirmed slot pauses (C F C: one frozen read; C D C:
# one read 5 below; C S F C: a silent read, then the pause) is never fenced (7ab7eca: 5 / 5 / 10 s, grace 30:
# 35 / 35 / 40 s — backdated to the persisted stall); a still-frozen one fences at the first read at or after
# reference + 15 s (the rows above, at this harness's 5 s cadence: 15 / 45 s — up to one CHECK_INTERVAL more
# at a cadence that does not divide 15: 51 / 21 s at 7, the final panel's cadence grid, fix round 5). The
# YOUNG-stamp member (a stall stamp 10 s old — under one window — over a corrupted slot): the frozen clock
# anchors at the restore instant behind the same floor, so it fences at the first read at or after
# max(reference + 15 s, restore + SELF_FENCE_ISOLATION_SECS) — grace 30: 45 s (7ab7eca and e917c04 60: the
# first answer restarted the clock), grace 0: 30 s (unchanged: restore + 30, not reference + 15); its
# healthy pause never.
R5_SEQ=CFC  f2_case "pause C F C SLOT=0999 stall 1000s"   never seq 30 "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000"
R5_SEQ=CFC  f2_case "pause C F C SLOT=0999 stall 1000s"   never seq "" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99000"
R5_SEQ=CDC  f2_case "pause C D C SLOT=abc stall 1000s"    never seq 30 "SF_LAST_CONFIRMED_SLOT=abc" "SF_ADVANCE_MONO=99000"
R5_SEQ=CDC  f2_case "pause C D C SLOT=abc stall 1000s"    never seq "" "SF_LAST_CONFIRMED_SLOT=abc" "SF_ADVANCE_MONO=99000"
R5_SEQ=CSFC f2_case "pause C S F C SLOT=0400000000 xyz"   never seq 30 "SF_LAST_CONFIRMED_SLOT=0400000000" "SF_ADVANCE_MONO=xyz"
R5_SEQ=CSFC f2_case "pause C S F C SLOT=0400000000 xyz"   never seq "" "SF_LAST_CONFIRMED_SLOT=0400000000" "SF_ADVANCE_MONO=xyz"
f2_case "frozen SLOT=0999 young stall 10s"              45    frozen  30 "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99990"
f2_case "frozen SLOT=0999 young stall 10s"              30    frozen  "" "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99990"
R5_SEQ=CFC  f2_case "pause C F C SLOT=0999 young 10s"   never seq 30 "SF_LAST_CONFIRMED_SLOT=0999" "SF_ADVANCE_MONO=99990"
# fix round 4, W4 (H4-CORRUPT-NEVER): a same-boot stamp LATER than now is corrupted → ANCIENT (as S2); a
# PRESENT vote-lag baseline latch other than 0 restores SET. Pre-fix red (every tree: de21927, f22d492,
# e917c04, 7ab7eca): the silence / lag clock read negative — never; the frozen stamp armed nothing — 30 s
# from the restore; the latch stayed unset — N6 never armed on a holder lagging across the restore.
f2_case "silent NOANSWER=+500s (future)"                0     silent  "" "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=100500"
f2_case "silent NOANSWER=2^63-1"                        30    silent  30 "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=9223372036854775807"
f2_case "lag VOTELAG=+500s (future)"                    0     lag     "" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=100500" "SF_VOTELAG_BASELINE=1"
f2_case "lag VOTELAG=2^63-1"                            30    lag     30 "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=9223372036854775807" "SF_VOTELAG_BASELINE=1"
f2_case "frozen ADVANCE=+500s (future)"                 0     frozen  "" "SF_LAST_CONFIRMED_SLOT=500" "SF_ADVANCE_MONO=100500"
f2_case "lag BASELINE=abc stall 1000s"                  0     lag     "" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000" "SF_VOTELAG_BASELINE=abc"
f2_case "lag BASELINE=0777 stall 1000s"                 30    lag     30 "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000" "SF_VOTELAG_BASELINE=0777"
f2_case "lag BASELINE=01 stall 1000s"                   0     lag     "" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000" "SF_VOTELAG_BASELINE=01"
f2_case "lag BASELINE=2^63-1 stall 1000s"               0     lag     "" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000" "SF_VOTELAG_BASELINE=9223372036854775807"
f2_case "lag BASELINE=2^64+100 stall 1000s"             0     lag     "" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000" "SF_VOTELAG_BASELINE=18446744073709551716"
f2_case "healthy NOANSWER=+500s (future)"               never healthy 30 "SF_LAST_CONFIRMED_SLOT=500" "SF_NOANSWER_MONO=100500"
f2_case "healthy BASELINE=abc stall 1000s"              never healthy 30 "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000" "SF_VOTELAG_BASELINE=abc"
# NAMED RESIDUAL (W4 scope): an ABSENT latch key stays unset — N6's fresh-start rule (no healthy baseline → do
# not arm): a holder lagging continuously across such a restore is never fenced through N6 (every tree).
f2_case "lag BASELINE absent stall 1000s (RESIDUAL)"    never lag     "" "SF_LAST_CONFIRMED_SLOT=500" "SF_VOTELAG_MONO=99000"
# (f3) fix round 4, W2: SELFFENCE_RESTORE_CONFIRM_SECS lives at ONE derivation site — N-is-all over every
# shipped script: exactly one assignment per daemon (=15), inside a derivation block BYTE-IDENTICAL in both
# (from its "W2 — H4-RP2-HEALTHY-PAUSE" header to the assignment), placed AFTER the env source (a constant,
# not an operator knob), and assigned nowhere else (env templates, deploy scripts, the arm, the fences).
f3_ok=1; f3_why=""
for sc in "$STANDBY" "$PRIMARY"; do
  n=$(grep -cE '(^|[^_A-Za-z])SELFFENCE_RESTORE_CONFIRM_SECS[[:space:]]*=' "$sc")
  [[ "$n" == "1" ]] || { f3_ok=0; f3_why="$f3_why $(basename "$sc"):assignments=$n"; }
  grep -q '^SELFFENCE_RESTORE_CONFIRM_SECS=15$' "$sc" || { f3_ok=0; f3_why="$f3_why $(basename "$sc"):value"; }
  a=$(grep -n '^SELFFENCE_RESTORE_CONFIRM_SECS=15$' "$sc" | cut -d: -f1); e=$(grep -n '^    source "\$CONFIG_FILE"' "$sc" | head -1 | cut -d: -f1)
  [[ -n "$a" && -n "$e" && $a -gt $e ]] || { f3_ok=0; f3_why="$f3_why $(basename "$sc"):not-after-env-source($a/$e)"; }
done
f3_blk() { awk '/W2 — H4-RP2-HEALTHY-PAUSE\): the unknown-slot restore/{on=1} on{print} on && /^SELFFENCE_RESTORE_CONFIRM_SECS=/{exit}' "$1"; }
[[ -n "$(f3_blk "$STANDBY")" && "$(f3_blk "$STANDBY")" == "$(f3_blk "$PRIMARY")" ]] || { f3_ok=0; f3_why="$f3_why derivation-blocks-differ"; }
for f in "$HARNESS_DIR"/failover.env.example "$HARNESS_DIR"/failover-standby.env.example "$HARNESS_DIR"/deploy-failover.sh "$HARNESS_DIR"/deploy-failover-standby.sh "$HARNESS_DIR"/failover-arm.sh "$HARNESS_DIR"/install.sh "$HARNESS_DIR"/systemd/failover-fence.sh "$HARNESS_DIR"/systemd/failover-fence-page-only.sh; do
  [[ -f "$f" ]] || { f3_ok=0; f3_why="$f3_why missing:$(basename "$f")"; continue; }
  grep -q 'SELFFENCE_RESTORE_CONFIRM_SECS' "$f" && { f3_ok=0; f3_why="$f3_why named-in:$(basename "$f")"; }
done
[[ $f3_ok -eq 1 ]] && ok "(f3) W2 — SELFFENCE_RESTORE_CONFIRM_SECS=15 is assigned exactly ONCE per daemon, after the env source (a constant, not a knob), inside a derivation block byte-identical in both daemons, and named in no other shipped script" \
  || bad "(f3) the floor's one derivation site:$f3_why"
[[ $f2_ok -eq 1 ]] && ok "(f2) R5 + S2 + W2 + W4 fence timing, both daemons —$f2_rows a non-canonical stall / silence / lag stamp is ANCIENT behind the first read's evidence: the holder still frozen / silent / lagging fences at that read (pre-fix e917c04 started the timer fresh: 30 s, grace 30: 60 / 60 s), a healthy first read drops it (never); a non-canonical slot over a stall a window old keeps the backdate pending past the reference read until the slot has not moved for SELFFENCE_RESTORE_CONFIRM_SECS (15 s) — frozen fences at the first read at or after reference + 15 (at this harness's 5 s cadence: grace 0: 15 s, grace 30: 45 s; 7ab7eca 5 / 35, which fenced the PAUSED HEALTHY holder too; e917c04 30 / 60; f22d492 30 / 30 by misreading '0999', which fenced the HEALTHY holder at 30 too), a paused healthy holder never; a young stall stamp over a corrupted slot anchors at the restore instant (grace 30: 45 s; 7ab7eca / e917c04 60); a same-boot FUTURE stamp is ancient and a present latch other than 0 restores set (every tree before: never, or 30 s for the frozen stamp); an ABSENT latch stays unset (named residual, never); per-value restore keeps round 2's rows (the whole-snapshot variant fenced 30 s / never / never / never where rows 2–5 fence at 0 / 0 / 20 / 0 s here)"

results_banner
