#!/bin/bash
# v0.7 (Block 3, slice 4): BLINDNESS-IS-LIFE (AUDIT-5 S-3 + A9a). Time the externals could not be
# observed must count as if the holder was VOTING — the takeover/recovery countdown only counts
# OBSERVED silence, and blindness restarts the N3 ANCHOR (not merely the sample pair).
#
# MEASURED (AUDIT-5): S-3 — both external RPCs down across the takeover delay → the first liveness
# sample is never pinned; on recovery the pair renders FROZEN one VOTE_LIVENESS_MIN_INTERVAL later
# and the take fires ~15s after the holder's last (unobservable) vote — the 60s window collapses to
# ~15s. A9a — an episode whose first attempt_takeover call already has elapsed >= TAKEOVER_DELAY
# (flaky LOCAL RPC delaying the window fill) pinned its first sample only via the fence → the
# verdict pair was just MIN_INTERVAL apart → measured take at t0+10s.
#
# Drives the REAL shipped attempt_takeover / attempt_safe_recovery / staked_is_actively_voting
# (source-to-MAIN-LOOP seam, mono_now/date shims, controllable sampler/confirm mocks). Controls
# simulate the pre-slice-4 parent by neutering the _note_blind_cycle seam and/or setting
# VOTE_LIVENESS_MIN_SPAN=0 (a supported config) — each control is observed RED (the measured
# collapse reproduced) so every assertion provably bites.
#   (a)  THE MEASURED S-3: blind [t0, t0+90) through the whole delay; recovery at T=t0+90 →
#        WITH the fix: take at exactly (last observed blind cycle)+TAKEOVER_DELAY = t0+149, never
#        before T+DELAY-1; CONTROL (parent): take at T+MIN_INTERVAL = t0+100 — the collapse.
#   (b)  BEFORE-FIRST-SAMPLE (the reviewer's explicit case, probed inside (a)'s run): through the
#        end of blindness ZERO samples were ever pinned (no verdict of any kind was structurally
#        possible: every fence path without a pinned pair returns 2), no take, the window intact —
#        and the FULL countdown then runs from the end of blindness with zero prior observations.
#   (c)  MID-COUNTDOWN BLIND GAP: healthy pin at t0, externals die at t0+55, recover at t0+80 →
#        take no earlier than the observed blindness end + DELAY (c1); a vote that landed DURING
#        the gap is seen at the first post-gap read → VOTING → N3 re-anchor → take a full DELAY
#        later (c2 — life punches through; blindness delays only the take, never the LIVE verdict);
#        CONTROL (parent): take at the recovery instant (t0+80) — the gap never re-anchored.
#   (d)  NO blindness → take at exactly anchor+TAKEOVER_DELAY, timing IDENTICAL to the simulated
#        parent — the live-tested-path regression guard (this one matters most).
#   (e)  A9a: first call with elapsed >= DELAY → the first sample is pinned THAT cycle (the hoisted
#        capture); with the span floor the frozen verdict defers to span >= VOTE_LIVENESS_MIN_SPAN
#        (take at t0+40, exact); CONTROL (floor=0 = parent verdict timing): take at t0+10 — the
#        measured A9a reproduced.
#   (f)  span-floor no-op on the normal path (zero added delay vs floor=0) + floor=0 disables and
#        the config-drift announcer says so by name (both daemons).
#   (g)  PRIMARY twin: rpc-recovery blind stretch → the FULL RECOVERY_DELAY re-elapses from the
#        last observed blind cycle (+ pin + floor ⇒ re-take at t0+160); CONTROL (parent): re-take
#        at recovery+MIN_INTERVAL (t0+100) — the forbidden post-blind MIN_INTERVAL pair; the
#        slice-4 hunks are BYTE-IDENTICAL across the daemons.
#   (h)  FLIP-STARVATION 20s (slice-4 rework): provider alternates T2/T3 every 20s (inside
#        (MIN_INTERVAL, MIN_SPAN)) over a dead holder → the EPISODIC observation-span floor takes
#        at t0+70 (pin T2@0; flip re-pin @60→T3; same-T3 pair @70: frozen, span 70-0=70 >= 40);
#        CONTROL (oldfloor — the REPLACED pair-pinned floor, a permanent revert-control): NEVER
#        takes (the span clock re-bases with every flip and never reaches 40 — measured, reviewer
#        2026-08-17; never shipped).
#   (i)  FLIP-STARVATION 35s: episodic floor takes at t0+80 (pin T2@0; flip @60→T3; flip @70→T2;
#        same-T2 pair @80: span 80 >= 40); oldfloor CONTROL: NEVER.
#
# NOTE on granularity: "the end of blindness" is the last OBSERVED blind cycle. A cycle that
# attempts no observation (deep inside a countdown) is not blind — a pinned pair spanning such a
# stretch still proves silence because lastVote is monotonic on-chain (the (c) cases exercise
# exactly this: the un-probed [55,60) stretch is covered by the t0-pinned pair).

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
PRIMARY="$DIR/solana-primary-failover.sh"
[[ -f "$STANDBY" && -f "$PRIMARY" ]] || { echo "  ❌ scripts not found"; exit 1; }

T0=100000            # mono origin (never 0 — 0 collides with the "unset" sentinel)
DELAY=60             # TAKEOVER_DELAY / RECOVERY_DELAY under test (the shipped default)
MININT=10            # VOTE_LIVENESS_MIN_INTERVAL (shipped default)
SPAN=40              # VOTE_LIVENESS_MIN_SPAN (shipped slice-4 default — asserted below)

# ── STANDBY sim: run the REAL attempt_takeover over a timeline ──────────────────────────────────
#   $1 = mode: fix (shipped) | parent (_note_blind_cycle neutered + floor 0 = pre-slice-4)
#                            | nofloor (blind stamps live, floor 0)
#                            | oldfloor (the REPLACED span floor: span from the re-basable pair
#                              pin _liveness_first_ts — the slice-4 rework's permanent revert-control)
#   $2/$3 = blind window [start,end) offsets from t0 (-1 -1 = never blind)
#   $4 = FIRST_DELINQUENT_TIME offset from t0 (negative = window filled late, elapsed already big)
#   $5 = holder burst offset (lastVote 5000 → 5001 from this offset; -1 = frozen throughout)
#   $6 = horizon ; $7 = probe offset (-1 = none)
#   $8 = flip period: provider alternates T2/T3 every this many seconds (0 = single-T2, the
#        pre-(h)/(i) behavior — every older call site passes an explicit 0)
# Echoes: "<take_off|-1> <pin_ts_off|-1> <last_active_off|-1> <probe_pin> <probe_take> <probe_win>"
sim() {
  local mode="$1" bs="$2" be="$3" fd="$4" burst="$5" horizon="$6" probe="$7" flip="$8"
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; VOTE_PUBKEY="V1"
  TAKEOVER_DELAY=$DELAY; TAKEOVER_COOLDOWN=0; EXTERNAL_CONFIRM_THROTTLE=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0
  GOSSIP_VERIFY=false; DRY_RUN=false; WITNESS_FASTPATH=false
  date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
  mono_now() { echo "$_SIM_NOW"; }
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}
  alert(){ :;}; alert_info(){ :;}; alert_warn(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  save_state(){ :;}
  # External world: ONE switch controls both observation channels (both-tiers-down blindness).
  _EXT_UP=1
  confirm_delinquency_external(){ [[ "$_EXT_UP" == "1" ]] && return 0; return 2; }
  get_staked_liveness_sample(){
      [[ "$_EXT_UP" == "1" ]] || return 1
      local off=$(( _SIM_NOW - T0 )) v=5000 tier="T2"
      [[ $burst -ge 0 && $off -ge $burst ]] && v=5001
      [[ $flip -gt 0 && $(( (off / flip) % 2 )) -eq 1 ]] && tier="T3"   # (h)/(i): vantage alternates every $flip s
      printf '%s %s %s\n' "$v" "$(( 900000 + off ))" "$tier"   # cluster tip advances 1/s
  }
  case "$mode" in
      parent)  _note_blind_cycle(){ :; }; VOTE_LIVENESS_MIN_SPAN=0 ;;   # the pre-slice-4 daemon
      nofloor) VOTE_LIVENESS_MIN_SPAN=0 ;;                              # blind anchor live, floor off
      bigfloor) VOTE_LIVENESS_MIN_SPAN=100 ;;                           # (j): SPAN > DELAY drift — makes the blind-cycle obs_since reset observable
      oldfloor)   # the REPLACED floor body: span from the re-basable pair pin (permanent revert-control)
          _liveness_span_short() {
              local floor="${VOTE_LIVENESS_MIN_SPAN:-40}" span
              [[ "$floor" =~ ^[0-9]+$ ]] || floor=40
              floor=$((10#$floor))
              [[ $floor -gt 0 ]] || return 1
              [[ ${_liveness_first_ts:-0} -gt 0 ]] || return 1
              span=$(( $(mono_now) - _liveness_first_ts ))
              [[ $span -lt $floor ]] && return 0
              return 1
          } ;;
  esac
  FIRST_DELINQUENT_TIME=$(( T0 + fd )); LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0
  LAST_LIVENESS_ACTIVE_TIME=0; SELF_FENCE_DEMOTE_TIME=0
  _delinq_window="1111111111"; _turbo_mode=true; _takeover_alert_sent=""; _gossip_prefetched=false
  _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
  _last_blind_end=0
  _took=-1; take_staked_identity(){ _took=$(( _SIM_NOW - T0 )); return 0; }
  p_pin="na"; p_took="na"; p_win="na"
  local t off
  for ((t=0; t<=horizon; t++)); do
      _SIM_NOW=$(( T0 + t )); off=$t
      _EXT_UP=1; [[ $bs -ge 0 && $off -ge $bs && $off -lt $be ]] && _EXT_UP=0
      attempt_takeover >/dev/null 2>&1
      if [[ $off -eq $probe ]]; then
          p_pin="${_liveness_first_vote:-none}"; p_took=$_took; p_win="$_delinq_window"
      fi
      [[ $_took -ge 0 ]] && break
  done
  local pin=-1 la=-1
  [[ ${_liveness_first_ts:-0} -gt 0 ]] && pin=$(( _liveness_first_ts - T0 ))
  [[ ${LAST_LIVENESS_ACTIVE_TIME:-0} -gt 0 ]] && la=$(( LAST_LIVENESS_ACTIVE_TIME - T0 ))
  echo "$_took $pin $la $p_pin $p_took $p_win"
  )
}

# ── PRIMARY sim: run the REAL attempt_safe_recovery over a timeline ─────────────────────────────
#   $1 = mode (fix|parent) ; $2/$3 = blind window [start,end) ; $4 = horizon
# Echoes the re-take (switch_to_staked) offset from t0, or -1.
prim_sim() {
  local mode="$1" bs="$2" be="$3" horizon="$4"
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; VOTE_PUBKEY="V1"
  RECOVERY_DELAY=$DELAY; RECOVERY_CHECKS=1; RECOVERY_CHECK_INTERVAL=0
  VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0
  date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
  mono_now() { echo "$_SIM_NOW"; }
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}
  alert(){ :;}; alert_info(){ :;}; alert_warn(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  save_state(){ :;}; sleep(){ :;}
  tier1_check_delinquency(){ return 1; }         # local: no longer delinquent
  _check_rpc_delinquency(){ return 1; }          # tier2: no longer delinquent
  check_standby_has_identity(){ return 1; }      # gossip corroboration: nobody else visible
  _EXT_UP=1
  get_staked_liveness_sample(){
      [[ "$_EXT_UP" == "1" ]] || return 1
      local off=$(( _SIM_NOW - T0 ))
      printf '%s %s %s\n' "5000" "$(( 900000 + off ))" "T2"   # holder frozen; tip advances
  }
  case "$mode" in
      parent) _note_blind_cycle(){ :; }; VOTE_LIVENESS_MIN_SPAN=0 ;;
  esac
  LAST_SWITCH_TIME=$T0; _last_recovery_log=0; _recovery_confirm_count=0; _standby_alert_sent=""
  _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
  _last_blind_end=0
  _rec=-1; switch_to_staked(){ _rec=$(( _SIM_NOW - T0 )); return 0; }
  local t off
  for ((t=0; t<=horizon; t++)); do
      _SIM_NOW=$(( T0 + t )); off=$t
      _EXT_UP=1; [[ $bs -ge 0 && $off -ge $bs && $off -lt $be ]] && _EXT_UP=0
      attempt_safe_recovery >/dev/null 2>&1
      [[ $_rec -ge 0 ]] && break
  done
  echo "$_rec"
  )
}

# ── drift-announcer probe (as in test_config_drift) ─────────────────────────────────────────────
drift_out() {  # $1=script ; rest=VAR=val overrides
    local script="$1"; shift
    (
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        log_info(){ :; }; log_error(){ :; }
        log_warn(){ printf '%s\n' "$*"; }
        for kv in "$@"; do eval "$kv"; done
        announce_config_drift
    )
}

echo "============================================="
echo "  Blindness-is-life (v0.7 Block 3 slice 4 / AUDIT-5 S-3 + A9a)"
echo "============================================="

# Sanity: the slice-4 knob ships as 40 in BOTH daemons (the sims below lean on the default).
grep -q '^VOTE_LIVENESS_MIN_SPAN=40' "$STANDBY" && grep -q '^VOTE_LIVENESS_MIN_SPAN=40' "$PRIMARY" \
    && ok "(0) VOTE_LIVENESS_MIN_SPAN ships as 40 in both daemons" \
    || bad "(0) shipped VOTE_LIVENESS_MIN_SPAN default is not 40 in both daemons"

# ── (a) THE MEASURED S-3 + (b) before-first-sample ──────────────────────────────────────────────
echo ""; echo "─── (a) measured S-3: blind [t0,t0+90) across the whole delay; recovery at T=t0+90 ───"
read -r A_TOOK A_PIN A_LA A_PPIN A_PTOOK A_PWIN <<<"$(sim fix    0 90 0 -1 300 89 0)"
read -r C_TOOK C_PIN C_LA _ _ _               <<<"$(sim parent 0 90 0 -1 300 -1 0)"
echo "    FIXED: take t0+${A_TOOK}s (pin t0+${A_PIN}s) | PARENT control: take t0+${C_TOOK}s"
[[ $A_TOOK -eq $(( 89 + DELAY )) ]] \
    && ok "(a1) take at exactly (last observed blind cycle t0+89s) + TAKEOVER_DELAY = t0+${A_TOOK}s — the anchor restarted, not just the pair" \
    || bad "(a1) take t0+${A_TOOK}s (want $(( 89 + DELAY ))) — blind end did not restart the N3 anchor"
[[ $A_TOOK -ge $(( 90 + DELAY - 1 )) ]] \
    && ok "(a2) no take before recovery+TAKEOVER_DELAY (t0+$(( 90 + DELAY ))s, ±1s cycle granularity) — the S-3 window collapse is closed" \
    || bad "(a2) took t0+${A_TOOK}s < recovery+delay — the liveness window still collapses"
[[ $C_TOOK -eq $(( 90 + MININT )) ]] \
    && ok "(a3) CONTROL RED: parent (blind stamps neutered, floor 0) takes at recovery+MIN_INTERVAL = t0+${C_TOOK}s — the MEASURED collapse reproduced, (a1)/(a2) bite" \
    || bad "(a3) parent control took t0+${C_TOOK}s (want $(( 90 + MININT ))) — the scenario no longer reproduces S-3"

echo ""; echo "─── (b) before-first-sample (the reviewer's case): zero observations during the delay ───"
[[ "$A_PPIN" == "none" ]] \
    && ok "(b1) probed at t0+89s (end of blindness): NO sample was ever pinned — with no pinned pair every fence path returns 2, so no verdict of ANY kind was possible" \
    || bad "(b1) a sample was pinned during total blindness (pin='$A_PPIN') — where did it observe?"
[[ "$A_PTOOK" == "-1" ]] \
    && ok "(b2) no take through the end of blindness" \
    || bad "(b2) took during blindness (t0+${A_PTOOK}s)"
[[ "$A_PWIN" == "1111111111" ]] \
    && ok "(b3) window intact through blindness (no false NOT-delinquent reset either)" \
    || bad "(b3) window changed during blindness ('$A_PWIN')"
[[ $A_PIN -eq 90 ]] \
    && ok "(b4) first observation pinned at the first post-blindness cycle (t0+${A_PIN}s) → the FULL countdown ran from the end of blindness with zero prior observations" \
    || bad "(b4) first pin at t0+${A_PIN}s (want 90)"

# ── (c) mid-countdown blind gap ─────────────────────────────────────────────────────────────────
echo ""; echo "─── (c) healthy pin at t0, blind [t0+55,t0+80), then recovery ───"
read -r G_TOOK G_PIN G_LA _ _ _  <<<"$(sim fix    55 80 0 -1 300 -1 0)"
read -r G2_TOOK _ G2_LA _ _ _    <<<"$(sim fix    55 80 0 70 300 -1 0)"
read -r GC_TOOK _ _ _ _ _        <<<"$(sim parent 55 80 0 -1 300 -1 0)"
echo "    frozen holder: take t0+${G_TOOK}s | gap-vote holder: VOTING seen t0+${G2_LA}s, take t0+${G2_TOOK}s | parent control: take t0+${GC_TOOK}s"
# Blind cycles OBSERVED: the t0+60 confirm attempt (rc2) then per-cycle probes t0+61..79 → last = 79.
[[ $G_TOOK -eq $(( 79 + DELAY )) && $G_TOOK -ge $(( 80 + DELAY - 1 )) ]] \
    && ok "(c1) take at (last observed blind cycle t0+79s)+DELAY = t0+${G_TOOK}s >= blind end (t0+80s)+DELAY-1 — the gap restarted the countdown" \
    || bad "(c1) take t0+${G_TOOK}s (want $(( 79 + DELAY )), >= $(( 80 + DELAY - 1 ))) — the mid-countdown gap did not re-anchor"
[[ $G2_LA -eq $(( 79 + DELAY )) ]] \
    && ok "(c2) a vote landed DURING the gap is OBSERVED at the first post-gap read (t0+${G2_LA}s) → VOTING → N3 re-anchor — life punches through blindness (never delayed by floor/blindness)" \
    || bad "(c2) gap-vote not seen as VOTING at the first read (last-active t0+${G2_LA}s, want $(( 79 + DELAY )))"
[[ $G2_TOOK -eq $(( G2_LA + DELAY )) ]] \
    && ok "(c3) and the take waits the FULL delay from that observed life sign (t0+${G2_TOOK}s = last-active+${DELAY}s)" \
    || bad "(c3) take t0+${G2_TOOK}s (want $(( G2_LA + DELAY )))"
[[ $GC_TOOK -eq 80 ]] \
    && ok "(c4) CONTROL RED: parent takes at the recovery instant (t0+${GC_TOOK}s) — the gap never re-anchored, (c1) bites" \
    || bad "(c4) parent control took t0+${GC_TOOK}s (want 80) — the scenario no longer exercises the gap"

# ── (d) NO blindness → parent-identical timing (the live-tested-path regression guard) ──────────
echo ""; echo "─── (d) no blindness: byte-identical timing to the parent (matters most) ───"
read -r D_TOOK D_PIN D_LA _ _ _  <<<"$(sim fix     -1 -1 0 -1 200 -1 0)"
read -r DP_TOOK _ _ _ _ _        <<<"$(sim parent  -1 -1 0 -1 200 -1 0)"
read -r DN_TOOK _ _ _ _ _        <<<"$(sim nofloor -1 -1 0 -1 200 -1 0)"
echo "    fixed: t0+${D_TOOK}s | parent: t0+${DP_TOOK}s | floor-off: t0+${DN_TOOK}s"
[[ $D_TOOK -eq $DELAY && $D_LA -eq -1 ]] \
    && ok "(d1) take at exactly anchor+TAKEOVER_DELAY (t0+${D_TOOK}s), anchor inputs inert" \
    || bad "(d1) normal-path take t0+${D_TOOK}s (want ${DELAY}) / last-active ${D_LA} (want -1) — the live-tested path drifted"
[[ $D_TOOK -eq $DP_TOOK ]] \
    && ok "(d2) identical to the simulated parent (t0+${DP_TOOK}s) — zero timing change without blindness" \
    || bad "(d2) fixed t0+${D_TOOK}s vs parent t0+${DP_TOOK}s — slice 4 changed the blindness-free path"

# ── (e) A9a: late-triggering episode (first call already past the delay) ────────────────────────
echo ""; echo "─── (e) A9a: first attempt_takeover call with elapsed=70s >= TAKEOVER_DELAY ───"
read -r E_TOOK E_PIN _ E_PPIN E_PTOOK _ <<<"$(sim fix     -1 -1 -70 -1 100 0 0)"
read -r EC_TOOK _ _ _ _ _               <<<"$(sim nofloor -1 -1 -70 -1 100 0 0)"
echo "    fixed: pin at cycle 0, take t0+${E_TOOK}s | floor-off control: take t0+${EC_TOOK}s"
[[ "$E_PPIN" == "5000" && $E_PIN -eq 0 ]] \
    && ok "(e1) first sample pinned on the VERY FIRST take-path cycle (probe: vote=$E_PPIN, ts=t0) even though the delay branch never ran — the hoisted A9a capture" \
    || bad "(e1) first cycle did not pin (probe='$E_PPIN', pin ts offset=$E_PIN) — the capture is still delay-branch-only"
[[ "$E_PTOOK" == "-1" && $E_TOOK -eq $SPAN ]] \
    && ok "(e2) frozen verdict deferred until span >= VOTE_LIVENESS_MIN_SPAN: take at exactly t0+${E_TOOK}s (=${SPAN}s of observed silence)" \
    || bad "(e2) take t0+${E_TOOK}s (want ${SPAN}) — the span floor did not gate the late-observed episode"
[[ $EC_TOOK -eq $MININT ]] \
    && ok "(e3) CONTROL RED: floor=0 (the parent's verdict timing) takes at t0+${EC_TOOK}s — the MEASURED A9a ~t0+10s take reproduced, (e2) bites" \
    || bad "(e3) floor-off control took t0+${EC_TOOK}s (want ${MININT}) — the scenario no longer reproduces A9a"

# ── (f) span-floor no-op on the normal path + floor=0 disables (drift-announced) ────────────────
echo ""; echo "─── (f) floor: normal-path no-op; 0 disables and the drift announcer says so ───"
[[ $D_TOOK -eq $DN_TOOK ]] \
    && ok "(f1) normal path: floor 40 vs floor 0 take at the SAME instant (t0+${D_TOOK}s) — the floor is a strict no-op there (span ≈ ${DELAY}s > ${SPAN}s)" \
    || bad "(f1) floor added delay on the normal path (40: t0+${D_TOOK}s vs 0: t0+${DN_TOOK}s)"
out=$(drift_out "$STANDBY" 'VOTE_LIVENESS_MIN_SPAN=0')
n=$(printf '%s\n' "$out" | grep -c '\[config-drift\]')
[[ "$n" == "1" && "$out" == *"VOTE_LIVENESS_MIN_SPAN=0 DISABLES"* ]] \
    && ok "(f2) STANDBY: MIN_SPAN=0 → one [config-drift] line with the DISABLES wording" \
    || bad "(f2) STANDBY MIN_SPAN=0 announce wrong ($n lines): $out"
out=$(drift_out "$PRIMARY" 'VOTE_LIVENESS_MIN_SPAN=0')
n=$(printf '%s\n' "$out" | grep -c '\[config-drift\]')
[[ "$n" == "1" && "$out" == *"VOTE_LIVENESS_MIN_SPAN=0 DISABLES"* ]] \
    && ok "(f3) PRIMARY: MIN_SPAN=0 → one [config-drift] line with the DISABLES wording (shared table)" \
    || bad "(f3) PRIMARY MIN_SPAN=0 announce wrong ($n lines): $out"
out=$(drift_out "$STANDBY")
[[ -z "$out" ]] \
    && ok "(f4) untouched defaults stay fully silent (MIN_SPAN=40 added no startup noise)" \
    || bad "(f4) defaults now produce drift output: $out"

# ── (g) PRIMARY twin: rpc-recovery blindness + byte-parity of the slice-4 hunks ─────────────────
echo ""; echo "─── (g) primary twin: blind [t0+60,t0+90) while recovery is eligible ───"
P_REC=$(prim_sim fix    60 90 400)
P_CTL=$(prim_sim parent 60 90 400)
echo "    fixed: re-take t0+${P_REC}s | parent control: re-take t0+${P_CTL}s"
# Blind observed at t0+60 (the one eligible-phase probe before the anchor restarts) → full
# RECOVERY_DELAY re-elapses to t0+120, pair pinned there, span floor to t0+160.
[[ $P_REC -eq $(( 60 + DELAY + SPAN )) && $P_REC -ge $(( 60 + DELAY )) ]] \
    && ok "(g1) re-take at t0+${P_REC}s = blind(60s)+RECOVERY_DELAY(${DELAY}s)+span floor(${SPAN}s) — never off a post-blind MIN_INTERVAL pair" \
    || bad "(g1) re-take t0+${P_REC}s (want $(( 60 + DELAY + SPAN ))) — the recovery anchor/floor did not hold"
[[ $P_CTL -eq $(( 90 + MININT )) ]] \
    && ok "(g2) CONTROL RED: parent re-takes at recovery+MIN_INTERVAL (t0+${P_CTL}s) — exactly the post-blind pair the twin rule forbids, (g1) bites" \
    || bad "(g2) parent control re-took at t0+${P_CTL}s (want $(( 90 + MININT ))) — the scenario no longer exercises the twin hole"
P_B=$(sed -n '/AUDIT-5 S-3) — blind-cycle stamp/,/^}$/p' "$PRIMARY")
S_B=$(sed -n '/AUDIT-5 S-3) — blind-cycle stamp/,/^}$/p' "$STANDBY")
[[ -n "$P_B" && "$P_B" == "$S_B" ]] \
    && ok "(g3) _note_blind_cycle block BYTE-IDENTICAL in both daemons ($(printf '%s\n' "$P_B" | wc -l | tr -d ' ') lines)" \
    || bad "(g3) blind-cycle block missing or DIVERGED between the daemons"
# The anchor must hit the HELPER-block header (ends "…2026-08-17;"), not the knob comment's
# ratified line (ends "…2026-08-17)…") — the trailing semicolon disambiguates.
P_F=$(sed -n '/OBSERVATION-SPAN FLOOR (RATIFIED by the reviewer, 2026-08-17;/,/^}$/p' "$PRIMARY")
S_F=$(sed -n '/OBSERVATION-SPAN FLOOR (RATIFIED by the reviewer, 2026-08-17;/,/^}$/p' "$STANDBY")
[[ -n "$P_F" && "$P_F" == "$S_F" && "$P_F" == *"_liveness_obs_since"* ]] \
    && ok "(g4) _liveness_span_short block (ratified header + episodic body) BYTE-IDENTICAL in both daemons ($(printf '%s\n' "$P_F" | wc -l | tr -d ' ') lines)" \
    || bad "(g4) span-floor block missing, not episodic, or DIVERGED between the daemons"
P_O=$(sed -n '/^_note_observation() {/,/^}$/p' "$PRIMARY")
S_O=$(sed -n '/^_note_observation() {/,/^}$/p' "$STANDBY")
[[ -n "$P_O" && "$P_O" == "$S_O" ]] \
    && ok "(g6) _note_observation body BYTE-IDENTICAL in both daemons ($(printf '%s\n' "$P_O" | wc -l | tr -d ' ') lines)" \
    || bad "(g6) _note_observation missing or DIVERGED between the daemons"
P_U=$(sed -n '/unavailable (externals down)/,/return 2/p' "$PRIMARY" | head -4)
S_U=$(sed -n '/unavailable (externals down)/,/return 2/p' "$STANDBY" | head -4)
[[ -n "$P_U" && "$P_U" == "$S_U" && "$P_U" == *"_note_blind_cycle"* ]] \
    && ok "(g5) the fence's unavailable-branch blind stamp BYTE-IDENTICAL in both daemons" \
    || bad "(g5) fence blind-stamp hunk missing or DIVERGED between the daemons"

# ── (h)/(i) provider-flip storms (slice-4 rework): the EPISODIC floor converges; the replaced
#    pair-pinned floor did NOT (measured, reviewer 2026-08-17: flip 20s/35s → NO take in 3600s).
#    Dead holder, no blindness, FIRST_DELINQUENT at t0, horizon 3600. ──────────────────────────────
echo ""; echo "─── (h) flip period 20s (inside (MIN_INTERVAL,MIN_SPAN)): episodic floor takes; old floor NEVER ───"
read -r H_TOOK _ _ _ _ _  <<<"$(sim fix      -1 -1 0 -1 3600 -1 20)"
read -r HO_TOOK _ _ _ _ _ <<<"$(sim oldfloor -1 -1 0 -1 3600 -1 20)"
echo "    episodic floor: take t0+${H_TOOK}s | oldfloor control: take t0+${HO_TOOK}s"
[[ $H_TOOK -eq 70 ]] \
    && ok "(h1) flip 20s: take at exactly t0+70s (pin T2@0; flip re-pin @60→T3; same-T3 pair @70: frozen, span 70-0=70 >= 40)" \
    || bad "(h1) flip 20s take t0+${H_TOOK}s (want 70) — the floor does not measure the EPISODE's observed span"
[[ "$HO_TOOK" == "-1" ]] \
    && ok "(h2) CONTROL RED (permanent revert-control): the REPLACED pair-pinned floor NEVER takes under 20s flips — the measured non-convergence reproduced, (h1) bites" \
    || bad "(h2) oldfloor control took t0+${HO_TOOK}s (want -1) — the control no longer reproduces the flip starvation"

echo ""; echo "─── (i) flip period 35s: episodic floor takes; old floor NEVER ───"
read -r I_TOOK _ _ _ _ _  <<<"$(sim fix      -1 -1 0 -1 3600 -1 35)"
read -r IO_TOOK _ _ _ _ _ <<<"$(sim oldfloor -1 -1 0 -1 3600 -1 35)"
echo "    episodic floor: take t0+${I_TOOK}s | oldfloor control: take t0+${IO_TOOK}s"
[[ $I_TOOK -eq 80 ]] \
    && ok "(i1) flip 35s: take at exactly t0+80s (pin T2@0; flip @60→T3; flip @70→T2; same-T2 pair @80: span 80 >= 40)" \
    || bad "(i1) flip 35s take t0+${I_TOOK}s (want 80) — the floor does not measure the EPISODE's observed span"
[[ "$IO_TOOK" == "-1" ]] \
    && ok "(i2) CONTROL RED (permanent revert-control): the replaced floor NEVER takes under 35s flips — (i1) bites" \
    || bad "(i2) oldfloor control took t0+${IO_TOOK}s (want -1) — the control no longer reproduces the flip starvation"


# ── (j) SPAN > DELAY drift: the blind-cycle obs_since reset is OBSERVABLE ───────────────────────
#    At shipped defaults the reset inside _note_blind_cycle is masked (the blind re-anchor's
#    DELAY=60 always exceeds the floor's 40), so no default-config case can go red if that line is
#    removed (found by mutation testing, verifier 2026-08-17). Under VOTE_LIVENESS_MIN_SPAN=100 (a
#    supported config) the floor outlives the re-anchored countdown and the reset becomes the
#    binding guard: blind [65,70) → obs_since re-pins at 70 → take at 70+100=170. Revert-control =
#    delete the `_liveness_obs_since=0` line from _note_blind_cycle → take at 129 (span counted
#    from the PRE-blind pin — the floor claims observation across a stretch nobody observed).
echo ""; echo "─── (j) floor 100 > delay 60: a blind gap must restart the OBSERVED span, not just the anchor ───"
read -r J_TOOK _ _ _ _ _ <<<"$(sim bigfloor 65 70 0 -1 400 -1 0)"
echo "    floor=100, blind [65,70): take t0+${J_TOOK}s"
[[ $J_TOOK -eq 170 ]] \
    && ok "(j1) take at exactly t0+170s = post-blind obs re-pin(70) + floor(100) — blindness restarts the observed span itself" \
    || bad "(j1) take t0+${J_TOOK}s (want 170; 129 = the span bridged the blind gap — the _note_blind_cycle obs_since reset is gone)"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
