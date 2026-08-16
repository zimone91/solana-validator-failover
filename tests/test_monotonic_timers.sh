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

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$PRIMARY" && -f "$STANDBY" ]] || { echo "  ❌ scripts not found"; exit 1; }
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
  log(){ :; }; log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
  alert(){ :; }; alert_info(){ :; }; alert_warn(){ :; }; send_telegram(){ return 0; }; send_webhook(){ :; }
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
  log(){ :; }; log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
  alert(){ :; }; alert_info(){ :; }; alert_warn(){ :; }; send_telegram(){ return 0; }; send_webhook(){ :; }
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

echo "============================================="
echo "  Monotonic SAFETY timers (v0.7 Block 3)"
echo "============================================="

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
  P_DEF=$(sed -n "/^${FN}()/,/^}/p" "$PRIMARY")
  S_DEF=$(sed -n "/^${FN}()/,/^}/p" "$STANDBY")
  if [[ -n "$P_DEF" && "$P_DEF" == "$S_DEF" ]]; then
      ok "(d) ${FN}() present in BOTH daemons and BYTE-IDENTICAL ($(printf '%s\n' "$P_DEF" | wc -l | tr -d ' ') lines)"
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

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
