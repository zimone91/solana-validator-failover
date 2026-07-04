#!/bin/bash
# v0.6.9 (H3): the self-fence baseline must survive a monitor restart. Runs the REAL shipped
# save_state / load_state / check_self_fence_isolation across a simulated restart (two subshells
# sharing one STATE_FILE, fake clock), for BOTH daemons (the standby got the port via H1).
#   (P-a) save mid-stall → restart → still-frozen slot INHERITS the clock: the fence fires on the
#         first post-restart evaluation (no fresh 30s wait)
#   (P-b) save mid-stall → restart → slot ADVANCED while we were down → clears instantly (no fire)
#   (P-c) stale save (> STATE_MAX_AGE_SECS) → discarded wholesale (fresh timers, no restore log)
#   (P-d) no-answer continuity: persisted silence + still silent at startup → backdated → fires
#   (P-e) STAKED + unreachable at startup → the REAL wait-loop seam pages 🚨 exactly once and keeps
#         the heartbeat watchdog pinging
#   (P-f) NON-VACUOUS CONTROL (same-inputs/knob-flipped): STATE_MAX_AGE_SECS=0 → nothing restores →
#         the P-a inputs do NOT fire immediately (the old disarmed-after-restart behavior returns)
#   (P-g) v0.6.9 (B4): the age==0 boundary — a same-second restart with max=900 restores+fires, but
#         max=0 is a HARD disable (restores NOTHING) — closes the '0 = never restore' off-by-one

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$PRIMARY" && -f "$STANDBY" ]] || { echo "  ❌ scripts not found"; exit 1; }
T0=1700000000

# Phase 1 (the "pre-restart" daemon): establish a STAKED baseline at T0, observe the stall until
# T0+$2, save, and exit — leaving STATE_FILE behind.   $1=script $2=save_offset $3=mode(slot|noanswer)
phase1() {
  local script="$1" save_off="$2" mode="$3" sfile="$4"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; LOCAL_RPC="http://mock-local"
    TG_ENABLED=false; DRY_RUN=false; CURRENT_IDENTITY="S1"
    STATE_DIR="$(dirname "$sfile")"; STATE_FILE="$sfile"; STATE_MAX_AGE_SECS=900
    SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_MAX_BEHIND=0
    SELF_FENCE_VOTE_LAG_SLOTS=0; SELF_FENCE_VOTE_LAG_SECS=0
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }; sleep(){ :; }
    send_telegram(){ return 0; }; send_webhook(){ :; }; alert(){ :; }; alert_warn(){ :; }; alert_info(){ :; }
    _SIM_NOW=$T0
    date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
    _M="slot"
    curl(){ local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
            case "$d" in *getSlot*) [[ "$_M" == "noanswer" ]] && return 7; printf '{"result":100000}'; return 0 ;;
                         *getHealth*) printf '{"result":"ok"}'; return 0 ;; esac; return 7; }
    check_self_fence_isolation >/dev/null                       # baseline at T0 (slot answers)
    if [[ "$mode" == "noanswer" ]]; then
        _M="noanswer"
        _SIM_NOW=$(( T0 + 5 )); check_self_fence_isolation >/dev/null   # silence starts (since=T0+5)
    fi
    _SIM_NOW=$(( T0 + save_off ))
    [[ "$mode" == "slot" ]] || check_self_fence_isolation >/dev/null    # keep the silence timer honest
    save_state
  )
}

# Phase 2 (the "restarted" daemon): load, then evaluate once at T0+$2 with the given slot answer.
# Echoes: fired=<0/1>|slot=<_last_confirmed_slot>|advts=<advance_ts>|nsince=<noanswer_since>|restored=<pending consumed?>
phase2() {
  local script="$1" now_off="$2" mode="$3" slotval="$4" sfile="$5" maxage="${6:-900}"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; LOCAL_RPC="http://mock-local"
    TG_ENABLED=false; DRY_RUN=false; CURRENT_IDENTITY="S1"
    STATE_DIR="$(dirname "$sfile")"; STATE_FILE="$sfile"; STATE_MAX_AGE_SECS="$maxage"
    SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_MAX_BEHIND=0
    SELF_FENCE_VOTE_LAG_SLOTS=0; SELF_FENCE_VOTE_LAG_SECS=0
    # primary knob name / standby knob name — set both so one scenario body drives either script
    PRIMARY_SELF_FENCE=true; STANDBY_SELF_FENCE=true
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }; sleep(){ :; }
    send_telegram(){ return 0; }; send_webhook(){ :; }; alert(){ :; }; alert_warn(){ :; }; alert_info(){ :; }
    _SIM_NOW=$(( T0 + now_off ))
    date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
    _M="$mode"; _SLOT="$slotval"
    curl(){ local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
            case "$d" in *getSlot*) [[ "$_M" == "noanswer" ]] && return 7; printf '{"result":%s}' "$_SLOT"; return 0 ;;
                         *getHealth*) printf '{"result":"ok"}'; return 0 ;; esac; return 7; }
    fired=0
    _demote_hook(){ fired=1; CURRENT_IDENTITY="U1"; return 0; }
    switch_to_unstaked(){ _demote_hook; }          # primary demote
    give_back_identity(){ _demote_hook; }          # standby demote (via _selffence_demote)
    save_state(){ :; }                             # phase 2 must not overwrite the fixture
    load_state
    restored_pending=$(( _selffence_restore_pending + _selffence_noanswer_restore_pending ))
    check_self_fence_isolation >/dev/null
    printf 'fired=%s|slot=%s|advts=%s|nsince=%s|pending=%s|role=%s\n' \
        "$fired" "${_last_confirmed_slot:-none}" "${_last_confirmed_advance_ts:-0}" \
        "${_selffence_noanswer_since:-0}" "$restored_pending" "${_persisted_role:-none}"
  )
}
field(){ printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

echo "============================================="
echo "  Self-fence baseline persistence (v0.6.9 H3)"
echo "============================================="

for SCRIPT in "$PRIMARY" "$STANDBY"; do
  NAME=$(basename "$SCRIPT" | sed 's/solana-\(.*\)-failover.sh/\1/' | tr '[:lower:]' '[:upper:]')
  TMPD=$(mktemp -d); SFILE="$TMPD/state-test"

  # ── (P-a) still-frozen slot inherits the clock ──────────────────────────────────────────────
  echo ""; echo "─── [$NAME] (P-a) frozen at save, STILL frozen after restart → fires immediately ───"
  phase1 "$SCRIPT" 20 slot "$SFILE"                       # baseline T0, frozen through T0+20, saved
  out=$(phase2 "$SCRIPT" 40 slot 100000 "$SFILE")         # restart at T0+40; slot unchanged
  if [[ "$(field "$out" fired)" == "1" && "$(field "$out" pending)" -ge 1 && "$(field "$out" role)" == "staked" ]]; then
      ok "[$NAME] (P-a) inherited stall clock → fenced on the FIRST post-restart read (no fresh 30s)"
  else
      bad "[$NAME] (P-a) did not inherit ($out)"
  fi

  # ── (P-b) advanced slot clears instantly ────────────────────────────────────────────────────
  echo "─── [$NAME] (P-b) slot ADVANCED while the monitor was down → clears, no fire ───"
  out=$(phase2 "$SCRIPT" 40 slot 100500 "$SFILE")
  if [[ "$(field "$out" fired)" == "0" && "$(field "$out" slot)" == "100500" && "$(field "$out" advts)" == "$(( T0 + 40 ))" ]]; then
      ok "[$NAME] (P-b) resumed validator cleared instantly (re-baselined at now)"
  else
      bad "[$NAME] (P-b) wrong ($out)"
  fi

  # ── (P-c) stale save discarded ──────────────────────────────────────────────────────────────
  echo "─── [$NAME] (P-c) save older than STATE_MAX_AGE_SECS → discarded (fresh timers) ───"
  out=$(phase2 "$SCRIPT" 2000 slot 100000 "$SFILE")       # age 1980 > 900
  if [[ "$(field "$out" fired)" == "0" && "$(field "$out" pending)" == "0" ]]; then
      ok "[$NAME] (P-c) stale baseline discarded — no instant false demote, timers restart"
  else
      bad "[$NAME] (P-c) stale state leaked ($out)"
  fi

  # ── (P-d) no-answer continuity ──────────────────────────────────────────────────────────────
  echo "─── [$NAME] (P-d) persisted silence + STILL silent at startup → backdated → fires ───"
  rm -f "$SFILE"
  phase1 "$SCRIPT" 20 noanswer "$SFILE"                   # silent since T0+5, saved at T0+20
  out=$(phase2 "$SCRIPT" 40 noanswer 0 "$SFILE")          # restart T0+40, RPC still silent → 35s >= 30
  if [[ "$(field "$out" fired)" == "1" ]]; then
      ok "[$NAME] (P-d) silence clock inherited across the restart → fence fired without a fresh 30s"
  else
      bad "[$NAME] (P-d) silence continuity lost ($out)"
  fi

  # ── (P-f) control: STATE_MAX_AGE_SECS=0 (restore disabled) → old disarmed behavior ──────────
  echo "─── [$NAME] (P-f) control: restore knob zeroed → same P-a inputs do NOT fire ───"
  rm -f "$SFILE"
  phase1 "$SCRIPT" 20 slot "$SFILE"
  out=$(phase2 "$SCRIPT" 40 slot 100000 "$SFILE" 0)       # STATE_MAX_AGE_SECS=0 → everything stale
  if [[ "$(field "$out" fired)" == "0" && "$(field "$out" pending)" == "0" ]]; then
      ok "[$NAME] (P-f) with restore disabled the fence is disarmed after restart → P-a is non-vacuous"
  else
      bad "[$NAME] (P-f) control fired anyway ($out)"
  fi

  # ── (P-g) v0.6.9 (B4): STATE_MAX_AGE_SECS=0 disables restore even at the age==0 boundary ───────
  # A persisted 40s stall (>= ISOLATION 30) saved at T0+40; a SAME-SECOND restart (now_off=40 → age 0).
  echo "─── [$NAME] (P-g) B4: age==0 boundary — max=900 restores (fires), max=0 disables (no fire) ───"
  rm -f "$SFILE"
  phase1 "$SCRIPT" 40 slot "$SFILE"                       # baseline frozen through T0+40, SAVE_TS=T0+40
  g1=$(phase2 "$SCRIPT" 40 slot 100000 "$SFILE" 900)      # age 0, max 900 → restores + backdate → fires
  g2=$(phase2 "$SCRIPT" 40 slot 100000 "$SFILE" 0)        # age 0, max 0  → B4 hard-disable → NO restore
  if [[ "$(field "$g1" fired)" == "1" && "$(field "$g1" pending)" -ge 1 ]]; then
      if [[ "$(field "$g2" fired)" == "0" && "$(field "$g2" pending)" == "0" ]]; then
          ok "[$NAME] (P-g) age==0: max=900 fires (baseline restored); max=0 restores NOTHING (0 = disabled)"
      else
          bad "[$NAME] (P-g) B4 boundary leaked: max=0 at age 0 still restored ($g2)"
      fi
  else
      bad "[$NAME] (P-g) setup wrong — age-0 max-900 did not fire ($g1)"
  fi
  rm -rf "$TMPD"
done

# ── (P-e) STAKED + unreachable startup page — the REAL wait-loop seam ─────────────────────────
echo ""; echo "─── (P-e) startup wait loop: persisted STAKED + unreachable → 🚨 once + watchdog pings ───"
run_waitloop() {   # $1=script $2=persisted_role → echoes "alerts=<n>|pings=<n>|hb_in_loop=<0/1>"
  local script="$1" role="$2"
  (
    set +e
    SEAM=$(mktemp)
    { echo 'startup_wait_seam() {'
      # primary says "# Wait for validator", standby "# Wait for local validator" — match both
      sed -n '/# Wait for.*validator/,/\[\[ "\$_running" != "true" \]\] \&\& exit 0/p' "$script"
      echo '}'
    } > "$SEAM"
    # shellcheck disable=SC1090
    source "$SEAM"; rm -f "$SEAM"
    STAKED_PUBKEY="S1"; _running=true; _persisted_role="$role"
    STARTUP_STAKED_UNREACHABLE_ALERT_SECS=60
    log_info(){ :; }; log_warn(){ :; }
    _SIM_NOW=1700000000
    date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
    _ALERTS=0; alert(){ [[ "$3" == *"UNREACHABLE WHILE STAKED"* ]] && _ALERTS=$((_ALERTS+1)); }
    _PINGS=0; heartbeat_ping(){ _PINGS=$((_PINGS+1)); }
    # NOTE: get_local_identity is called inside $(...) — a counter there would be lost in the subshell.
    # Key it off the fake clock instead (advanced by the mocked sleep in the PARENT shell): the
    # validator becomes reachable ~195s in, i.e. well past the 60s page threshold.
    get_local_identity(){ [[ $_SIM_NOW -ge 1700000195 ]] && echo "U1"; return 0; }
    sleep(){ _SIM_NOW=$(( _SIM_NOW + ${1:-5} )); :; }
    startup_wait_seam
    printf 'alerts=%s|pings=%s\n' "$_ALERTS" "$_PINGS"
  )
}
out=$(run_waitloop "$PRIMARY" staked)
if [[ "$(field "$out" alerts)" == "1" && "$(field "$out" pings)" -ge 1 ]]; then
    ok "(P-e1) PRIMARY: exactly ONE 🚨 UNREACHABLE WHILE STAKED page (~195s wait) + watchdog kept pinging ($out)"
else
    bad "(P-e1) wrong ($out)"
fi
out=$(run_waitloop "$PRIMARY" unstaked)
[[ "$(field "$out" alerts)" == "0" ]] \
    && ok "(P-e2) persisted role UNSTAKED → no page (the page keys on the persisted STAKED role)" \
    || bad "(P-e2) paged without a staked persisted role ($out)"
out=$(run_waitloop "$STANDBY" staked)
[[ "$(field "$out" alerts)" == "1" && "$(field "$out" pings)" -ge 1 ]] \
    && ok "(P-e3) STANDBY wait-loop port pages once + pings too ($out)" \
    || bad "(P-e3) standby wait loop wrong ($out)"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
