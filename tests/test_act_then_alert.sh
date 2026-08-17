#!/bin/bash
# v0.7 (Block 3, slice 5): ACT-THEN-ALERT (A8) + fresh-proof re-check. The reviewer's pre-registered
# conditions (slice 3.5): (1) immediately before set-identity a FRESH re-check — arithmetic on the
# existing pinned baseline PLUS one short re-sample, not a gate-cycle re-run; (2) re-check yielding
# VOTING or cannot-determine → ABORT, not proceed; (3) ZERO network calls between the re-check and
# set-identity (no alert, no network log, no gossip advisory). Extends the demote path's "safety
# action FIRST" rule (N2) to the take path.
#
# Harness: source-to-`# MAIN LOOP` seam of each daemon (the test_standby_take_timeout /
# test_standby_take_reset real-take idiom — mocks ONLY at the I/O boundary). An ordered EVENT LOG
# (append-only temp file) is written by:
#   SAMPLE <n>  — the shadowed get_staked_liveness_sample (scriptable per-call return values;
#                 the re-check call is identified by _IN_TAKE, set by a thin wrapper that
#                 delegates to the REAL take/switch body via declare -f rename)
#   NET <text>  — shadowed send_telegram / send_webhook (every alert surface)
#   ST8 …       — state snapshot taken AT alert time (proves state writes precede the alert)
#   MUTATE      — a REAL stub `agave-validator` binary on SOLANA_PATH logs set-identity calls
#   TAKE-ENTER / TAKE-EXIT rc=N — the wrapper brackets
#   LOG <text>  — log_warn lines emitted while inside the take (message-content guard)
# Cases (standby unless said otherwise):
#   (1) ORDER-PROCEED end-to-end: REAL attempt_takeover to a successful take — no NET before
#       MUTATE (the 🔍 pre-take alert is gone), a re-check SAMPLE between TAKE-ENTER and MUTATE,
#       NET (TOOK STAKED) only AFTER MUTATE
#   (2) FRESH-VOTING ABORT: frozen for the gate samples, ADVANCED (+1) at the re-check → NO
#       MUTATE, rc 1, LAST_LIVENESS_ACTIVE_TIME == re-check instant, pair re-based to the fresh
#       cur, _liveness_obs_since == re-check instant, abort alert AFTER the state writes, and NO
#       cooldown (LAST_TAKEOVER_TIME unchanged — abort is a withdrawn verdict, not a failed take)
#   (3) FRESH-BLIND ABORT: sampler empty at the re-check → NO MUTATE, _last_blind_end == re-check
#       instant (countdown re-anchored), abort alert
#   (4) FRESH-FLIP ABORT: re-check answered by the other tier → NO MUTATE, min-rule re-pin, abort
#       alert; the log/alert names the OLD→NEW vantage (T2→T3 — guards the capture-before-re-pin
#       ordering)
#   (5) DRY_RUN MIRROR: DRY_RUN + scenario 2 → NO "[DRY RUN] WOULD TAKE" (the abort happened
#       first, so a live daemon would not have taken — a WOULD TAKE here is a false report);
#       DRY_RUN + all-frozen → WOULD TAKE fires, no MUTATE ever
#   (6) PRIMARY TWIN: ORDER-PROCEED and FRESH-VOTING ABORT through the REAL attempt_safe_recovery
#       → switch_to_staked (test_primary_recovery_liveness Part-1 idiom, RECOVERY_CHECKS=1)
#   (7) BYTE-IDENTITY: _fresh_proof_recheck body identical across daemons
#   (8) PERMANENT REVERT-CONTROL: scenario 2 with _fresh_proof_recheck(){ return 0; } shadowed →
#       MUTATE HAPPENS despite the fresh VOTING sample — documents the parent's behavior and
#       proves case 2 bites
#   (9) FRESH-BACKWARDS ABORT / (10) FRESH-STALE-TIP ABORT: kill coverage for the two remaining
#       abort branches (added after slice-5 mutation testing found them unexercised)
#   (11) RE-ANCHOR CONSUMED (behavioral): after a fresh-VOTING abort the take lands at exactly
#       abort+TAKEOVER_DELAY — the re-anchor is consumed by the countdown, not merely written
#   (12) ABORT-ALERT THROTTLE: a vantage flipping at EVERY re-check aborts forever — the abort
#       page must throttle per ALERT_THROTTLE (first immediate), while the starvation page still
#       fires — no per-≈20s page storm
# RED (captured before the slice-5 daemon changes): cases 1–7 fail — the order case sees NET (🔍)
# before MUTATE and no re-check SAMPLE; the abort cases see MUTATE despite fresh VOTING; (7) has no
# helper to compare. (9)/(10) were observed red by MUTATION (branch neutered → red) after landing;
# (12) was observed red against the unthrottled first cut (≥50 pages over 2000s).

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
PRIMARY="$DIR/solana-primary-failover.sh"
[[ -f "$STANDBY" && -f "$PRIMARY" ]] || { echo "  ❌ scripts not found"; exit 1; }

T0=100000            # mono origin (never 0 — 0 collides with the "unset" sentinel)
DELAY=60             # TAKEOVER_DELAY / RECOVERY_DELAY (shipped default)
MININT=10            # VOTE_LIVENESS_MIN_INTERVAL (shipped default)
SPAN=40              # VOTE_LIVENESS_MIN_SPAN (shipped default)

# ── STANDBY sim: REAL attempt_takeover → REAL take_staked_identity over a timeline ─────────────
#   $1 = re-check mode: what the sampler returns while _IN_TAKE=1
#        (frozen | advance | blind | flip)   — outside the take it is always frozen-consistent
#   $2 = DRY_RUN (true|false)
#   $3 = shadow (1 = _fresh_proof_recheck(){ return 0; } shadowed AFTER sourcing — case 8)
# Echoes: EVENTS=<;-joined ordered event log>  and  STATE=<k=v|…> (offsets relative to T0).
sim_sb() {
  local rmode="$1" dry="$2" shadow="$3" hz="${4:-0}"   # hz>0 = drive-through: keep cycling past aborts, stop on MUTATE (or horizon)
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  _RMODE="$rmode"
  EVT=$(mktemp); export _EVT_FILE="$EVT"
  STUB=$(mktemp -d)
  cat > "$STUB/agave-validator" <<'EOS'
#!/bin/sh
case "$*" in *set-identity*) echo "MUTATE" >> "$_EVT_FILE" ;; esac
exit 0
EOS
  chmod +x "$STUB/agave-validator"
  KP=$(mktemp); echo '[1]' > "$KP"; STAKED_KEYPAIR="$KP"
  trap 'rm -f "$KP" "$EVT"; rm -rf "$STUB"' EXIT
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
  SOLANA_PATH="$STUB"; LEDGER_PATH="/mock/ledger"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
  TAKEOVER_DELAY=$DELAY; TAKEOVER_COOLDOWN=0; EXTERNAL_CONFIRM_THROTTLE=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0
  VOTE_LIVENESS_MIN_SPAN=$SPAN
  GOSSIP_VERIFY=false; WITNESS_FASTPATH=false; DRY_RUN="$dry"; TG_ENABLED=false
  date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
  mono_now() { echo "$_SIM_NOW"; }
  log(){ :;}; log_info(){ :;}; log_error(){ :;}
  log_warn(){ if [[ ${_IN_TAKE:-0} -eq 1 ]]; then local t="${1//$'\n'/ }"; printf 'LOG %s\n' "${t:0:120}" >> "$_EVT_FILE"; fi; }
  send_telegram(){
      local t="${1//$'\n'/ }"
      printf 'NET %s\n' "${t:0:120}" >> "$_EVT_FILE"
      printf 'ST8 lla=%s lfv=%s obs=%s\n' "$LAST_LIVENESS_ACTIVE_TIME" "$_liveness_first_vote" "$_liveness_obs_since" >> "$_EVT_FILE"
      return 0
  }
  send_webhook(){ local t="${1//$'\n'/ }"; printf 'NET %s\n' "${t:0:120}" >> "$_EVT_FILE"; return 0; }
  save_state(){ :;}; sleep(){ :;}
  get_local_identity(){ echo "$STAKED_PUBKEY"; }
  timeout(){ shift 3; "$@"; }   # drop `-k 5 $SETIDENTITY_TIMEOUT`, run the (stub) binary for real
  confirm_delinquency_external(){ return 0; }
  # Sampler shadow: ordered event + scriptable per-call value. Runs in a $() subshell, so it can
  # READ _IN_TAKE/_RMODE but must log through the file. Outside the take: frozen-consistent
  # (lastVote 5000 pinned, cluster tip advancing 1/s, single vantage T2).
  get_staked_liveness_sample(){
      local n; n=$(( $(grep -c '^SAMPLE' "$_EVT_FILE" 2>/dev/null) + 1 ))
      printf 'SAMPLE %s\n' "$n" >> "$_EVT_FILE"
      local off=$(( _SIM_NOW - T0 ))
      if [[ "$_RMODE" == "advance-sticky" ]]; then
          # (11): the holder voted ONCE between the gate verdict and the action, then died at 5001 —
          # the burst is visible from the first take attempt onward (in-take AND every later sample).
          if [[ ${_IN_TAKE:-0} -eq 1 ]] || grep -q '^TAKE-ENTER' "$_EVT_FILE" 2>/dev/null; then
              printf '5001 %s T2\n' $(( 900000 + off )); return 0
          fi
          printf '5000 %s T2\n' $(( 900000 + off )); return 0
      fi
      if [[ ${_IN_TAKE:-0} -eq 1 ]]; then
          case "$_RMODE" in
              blind)     return 1 ;;
              advance)   printf '5001 %s T2\n' $(( 900000 + off )); return 0 ;;
              flip)      printf '5000 %s T3\n' $(( 900000 + off )); return 0 ;;
              backwards) printf '4999 %s T2\n' $(( 900000 + off )); return 0 ;;
              stale)     printf '5000 900000 T2\n'; return 0 ;;   # tip == the pinned tip (t0) → view stale
          esac
      fi
      printf '5000 %s T2\n' $(( 900000 + off )); return 0
  }
  # Case 8: the permanent revert-control — a no-op re-check reproduces the parent's behavior.
  if [[ "$shadow" == "1" ]]; then _fresh_proof_recheck(){ return 0; }; fi
  # Wrapper: brackets the REAL body (renamed via declare -f) so the event log can see the take
  # window and the sampler can identify the re-check call. The real shipped body runs unmodified.
  eval "$(declare -f take_staked_identity | sed '1s/^take_staked_identity/_real_take_staked_identity/')"
  _take_rc=99
  take_staked_identity(){
      printf 'TAKE-ENTER\n' >> "$_EVT_FILE"
      _IN_TAKE=1
      _real_take_staked_identity "$@"; _take_rc=$?
      _IN_TAKE=0
      printf 'TAKE-EXIT rc=%s\n' "$_take_rc" >> "$_EVT_FILE"
      return $_take_rc
  }
  # Episode state: window triggered, delinquent since T0, pin primed by the prefetch at cycle 0.
  FIRST_DELINQUENT_TIME=$T0; LAST_TAKEOVER_TIME=0; LAST_LIVENESS_ACTIVE_TIME=0
  SELF_FENCE_DEMOTE_TIME=0; _last_lockout_log=0; _last_confirm_attempt=0
  _delinq_window="1111111111"; _turbo_mode=true; _takeover_alert_sent=""; _gossip_prefetched=false
  _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
  _last_blind_end=0; _liveness_obs_since=0
  local t stopmark='^TAKE-ENTER'
  if [[ $hz -gt 0 ]]; then stopmark='^MUTATE'; else hz=$(( DELAY + 5 )); fi
  for ((t=0; t<=hz; t++)); do
      _SIM_NOW=$(( T0 + t ))
      attempt_takeover >/dev/null 2>&1
      grep -q "$stopmark" "$EVT" && break
  done
  local mutoff=-1
  grep -q '^MUTATE' "$EVT" && mutoff=$(( _SIM_NOW - T0 ))   # the loop breaks on the MUTATE tick
  local lla=$LAST_LIVENESS_ACTIVE_TIME lfts=$_liveness_first_ts obs=$_liveness_obs_since blind=$_last_blind_end
  [[ $lla   -gt 0 ]] && lla=$((   lla - T0 ))
  [[ $lfts  -gt 0 ]] && lfts=$((  lfts - T0 ))
  [[ $obs   -gt 0 ]] && obs=$((   obs - T0 ))
  [[ $blind -gt 0 ]] && blind=$(( blind - T0 ))
  printf 'EVENTS=%s\n' "$(tr '\n' ';' < "$EVT")"
  printf 'STATE=rc=%s|lla=%s|lfv=%s|lftip=%s|lfts=%s|lfp=%s|obs=%s|blind=%s|ltt=%s|mutoff=%s\n' \
      "$_take_rc" "$lla" "$_liveness_first_vote" "$_liveness_first_tip" "$lfts" \
      "$_liveness_first_provider" "$obs" "$blind" "$LAST_TAKEOVER_TIME" "$mutoff"
  )
}

# ── PRIMARY sim: REAL attempt_safe_recovery → REAL switch_to_staked (Part-1 recovery idiom) ────
#   $1 = re-check mode while _IN_TAKE=1 (frozen | advance)
sim_pr() {
  local rmode="$1"
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  _RMODE="$rmode"
  EVT=$(mktemp); export _EVT_FILE="$EVT"
  STUB=$(mktemp -d)
  cat > "$STUB/agave-validator" <<'EOS'
#!/bin/sh
case "$*" in *set-identity*) echo "MUTATE" >> "$_EVT_FILE" ;; esac
exit 0
EOS
  chmod +x "$STUB/agave-validator"
  KP=$(mktemp); echo '[1]' > "$KP"; STAKED_KEYPAIR="$KP"
  trap 'rm -f "$KP" "$EVT"; rm -rf "$STUB"' EXIT
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
  SOLANA_PATH="$STUB"; LEDGER_PATH="/mock/ledger"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
  RECOVERY_DELAY=$DELAY; RECOVERY_CHECKS=1; RECOVERY_CHECK_INTERVAL=0; RECOVERY_COOLDOWN=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0
  VOTE_LIVENESS_MIN_SPAN=$SPAN
  DRY_RUN=false; TG_ENABLED=false
  date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
  mono_now() { echo "$_SIM_NOW"; }
  log(){ :;}; log_info(){ :;}; log_error(){ :;}
  log_warn(){ if [[ ${_IN_TAKE:-0} -eq 1 ]]; then local t="${1//$'\n'/ }"; printf 'LOG %s\n' "${t:0:120}" >> "$_EVT_FILE"; fi; }
  send_telegram(){
      local t="${1//$'\n'/ }"
      printf 'NET %s\n' "${t:0:120}" >> "$_EVT_FILE"
      printf 'ST8 lla=%s lfv=%s obs=%s\n' "${LAST_LIVENESS_ACTIVE_TIME:-0}" "$_liveness_first_vote" "$_liveness_obs_since" >> "$_EVT_FILE"
      return 0
  }
  send_webhook(){ local t="${1//$'\n'/ }"; printf 'NET %s\n' "${t:0:120}" >> "$_EVT_FILE"; return 0; }
  save_state(){ :;}; sleep(){ :;}
  get_local_identity(){ echo "$STAKED_PUBKEY"; }
  timeout(){ shift 3; "$@"; }
  tier1_check_delinquency(){ return 1; }       # local: no longer delinquent
  _check_rpc_delinquency(){ return 1; }        # tier2: no longer delinquent
  check_standby_has_identity(){ return 1; }    # gossip advisory: nobody else visible (runs BEFORE switch_to_staked)
  get_staked_liveness_sample(){
      local n; n=$(( $(grep -c '^SAMPLE' "$_EVT_FILE" 2>/dev/null) + 1 ))
      printf 'SAMPLE %s\n' "$n" >> "$_EVT_FILE"
      local off=$(( _SIM_NOW - T0 ))
      if [[ ${_IN_TAKE:-0} -eq 1 && "$_RMODE" == "advance" ]]; then
          printf '5001 %s T2\n' $(( 900000 + off )); return 0
      fi
      printf '5000 %s T2\n' $(( 900000 + off )); return 0
  }
  eval "$(declare -f switch_to_staked | sed '1s/^switch_to_staked/_real_switch_to_staked/')"
  _take_rc=99
  switch_to_staked(){
      printf 'TAKE-ENTER\n' >> "$_EVT_FILE"
      _IN_TAKE=1
      _real_switch_to_staked "$@"; _take_rc=$?
      _IN_TAKE=0
      printf 'TAKE-EXIT rc=%s\n' "$_take_rc" >> "$_EVT_FILE"
      return $_take_rc
  }
  LAST_SWITCH_TIME=$T0; _last_recovery_log=0; _recovery_confirm_count=0; _standby_alert_sent=""
  _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
  _last_blind_end=0; _liveness_obs_since=0; CURRENT_IDENTITY="U1"
  local t
  for ((t=0; t<=DELAY+SPAN+5; t++)); do
      _SIM_NOW=$(( T0 + t ))
      attempt_safe_recovery >/dev/null 2>&1
      grep -q '^TAKE-ENTER' "$EVT" && break
  done
  printf 'EVENTS=%s\n' "$(tr '\n' ';' < "$EVT")"
  printf 'STATE=rc=%s|lfv=%s\n' "$_take_rc" "$_liveness_first_vote"
  )
}

evline(){ printf '%s\n' "$1" | grep '^EVENTS=' | head -1 | cut -c8-; }
stline(){ printf '%s\n' "$1" | grep '^STATE='  | head -1 | cut -c7-; }
field(){ printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

echo "============================================="
echo "  Act-then-alert + fresh-proof re-check (v0.7 Block 3 slice 5)"
echo "============================================="

# ── (1) ORDER-PROCEED (standby, end-to-end) ─────────────────────────────────────────────────────
echo ""; echo "─── (1) ORDER-PROCEED: real attempt_takeover to a successful take ───"
out=$(sim_sb frozen false 0)
ev=$(evline "$out"); st=$(stline "$out")
echo "    trace: $ev"
if [[ "$ev" == *MUTATE* ]]; then
    pre="${ev%%MUTATE*}"; post="${ev#*MUTATE}"; seg="${pre#*TAKE-ENTER}"
    [[ "$pre" != *"NET"* ]] \
        && ok "(1a) ZERO NET before MUTATE — no 🔍 pre-take alert, nothing between the Gate-3 verdict / re-check and set-identity (condition 3)" \
        || bad "(1a) a NET event precedes MUTATE: $pre"
    [[ "$seg" == *"SAMPLE"* ]] \
        && ok "(1b) a fresh re-check SAMPLE sits between TAKE-ENTER and MUTATE (condition 1)" \
        || bad "(1b) no re-check SAMPLE inside the take window: $seg"
    [[ "$post" == *"NET"* && "$post" == *"TOOK STAKED"* ]] \
        && ok "(1c) NET (TOOK STAKED) only AFTER MUTATE — act, then alert" \
        || bad "(1c) no post-MUTATE TOOK STAKED alert: $post"
    [[ "$(field "$st" rc)" == "0" ]] \
        && ok "(1d) take succeeded (rc 0)" \
        || bad "(1d) take rc=$(field "$st" rc)"
else
    bad "(1) no MUTATE at all — the take never happened: $ev"
fi

# ── (2) FRESH-VOTING ABORT ──────────────────────────────────────────────────────────────────────
echo ""; echo "─── (2) FRESH-VOTING ABORT: +1 slot at the re-check → abort, no cooldown ───"
out=$(sim_sb advance false 0)
ev=$(evline "$out"); st=$(stline "$out")
[[ "$ev" != *MUTATE* ]] \
    && ok "(2a) NO MUTATE — the holder voted between the verdict and the action; the take aborted (condition 2)" \
    || bad "(2a) MUTATE happened despite a fresh VOTING sample: $ev"
[[ "$(field "$st" rc)" == "1" ]] \
    && ok "(2b) take returned 1 (abort)" \
    || bad "(2b) take rc=$(field "$st" rc) (want 1)"
[[ "$(field "$st" lla)" == "60" ]] \
    && ok "(2c) LAST_LIVENESS_ACTIVE_TIME == the re-check instant (t0+60) — the full delay re-elapses (N3)" \
    || bad "(2c) lla=$(field "$st" lla) (want 60)"
[[ "$(field "$st" lfv)" == "5001" && "$(field "$st" lfts)" == "60" ]] \
    && ok "(2d) pair re-based to the fresh cur (vote=5001, ts=t0+60) — mirrors the VOTING path" \
    || bad "(2d) pair not re-based (lfv=$(field "$st" lfv) lfts=$(field "$st" lfts))"
[[ "$(field "$st" obs)" == "60" ]] \
    && ok "(2e) _liveness_obs_since == the re-check instant — observed LIFE restarts the observed span" \
    || bad "(2e) obs=$(field "$st" obs) (want 60)"
[[ "$ev" == *"Take ABORTED"* && "$ev" == *"VOTED"* ]] \
    && ok "(2f) abort alert_warn fired (names the fresh vote)" \
    || bad "(2f) no abort alert in: $ev"
[[ "$ev" == *"ST8 lla=$((T0+60)) lfv=5001 obs=$((T0+60))"* ]] \
    && ok "(2g) the alert-time state snapshot already shows the re-base — the alert fired AFTER the decision + state writes" \
    || bad "(2g) alert fired before the state writes (no post-write ST8): $ev"
[[ "$(field "$st" ltt)" == "0" ]] \
    && ok "(2h) NO cooldown set (LAST_TAKEOVER_TIME unchanged) — abort is a withdrawn verdict, not a failed take" \
    || bad "(2h) a cooldown was set on abort (ltt=$(field "$st" ltt))"

# ── (3) FRESH-BLIND ABORT ───────────────────────────────────────────────────────────────────────
echo ""; echo "─── (3) FRESH-BLIND ABORT: sampler empty at the re-check ───"
out=$(sim_sb blind false 0)
ev=$(evline "$out"); st=$(stline "$out")
[[ "$ev" != *MUTATE* ]] \
    && ok "(3a) NO MUTATE — cannot determine at the re-check aborts (condition 2, fail closed)" \
    || bad "(3a) MUTATE happened on a blind re-check: $ev"
[[ "$(field "$st" blind)" == "60" ]] \
    && ok "(3b) _last_blind_end == the re-check instant (t0+60) — the countdown re-anchored (blindness-is-life)" \
    || bad "(3b) blind=$(field "$st" blind) (want 60)"
[[ "$ev" == *"Take ABORTED"* && "$ev" == *"no usable sample"* ]] \
    && ok "(3c) abort alert fired (cannot determine)" \
    || bad "(3c) no blind-abort alert in: $ev"
[[ "$(field "$st" rc)" == "1" && "$(field "$st" ltt)" == "0" ]] \
    && ok "(3d) rc 1, no cooldown" \
    || bad "(3d) rc=$(field "$st" rc) ltt=$(field "$st" ltt)"

# ── (4) FRESH-FLIP ABORT ────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) FRESH-FLIP ABORT: the other tier answers the re-check ───"
out=$(sim_sb flip false 0)
ev=$(evline "$out"); st=$(stline "$out")
[[ "$ev" != *MUTATE* ]] \
    && ok "(4a) NO MUTATE — a vantage flip at the re-check is not same-vantage comparable → abort" \
    || bad "(4a) MUTATE happened on a flipped re-check: $ev"
[[ "$(field "$st" lfp)" == "T3" && "$(field "$st" lfts)" == "60" && "$(field "$st" lfv)" == "5000" ]] \
    && ok "(4b) min-rule re-pin to the new vantage (prov=T3, ts=t0+60, vote stays 5000)" \
    || bad "(4b) re-pin wrong (lfp=$(field "$st" lfp) lfts=$(field "$st" lfts) lfv=$(field "$st" lfv))"
[[ "$ev" == *"Take ABORTED"* ]] \
    && ok "(4c) abort alert fired" \
    || bad "(4c) no flip-abort alert in: $ev"
[[ "$ev" == *"T2→T3"* ]] \
    && ok "(4d) the flip log/alert names the OLD→NEW vantage (T2→T3) — the old value was captured BEFORE the re-pin" \
    || bad "(4d) old→new vantage not named correctly (the sketch's read-after-write bug?): $ev"
[[ "$(field "$st" rc)" == "1" && "$(field "$st" ltt)" == "0" ]] \
    && ok "(4e) rc 1, no cooldown" \
    || bad "(4e) rc=$(field "$st" rc) ltt=$(field "$st" ltt)"

# ── (5) DRY_RUN MIRROR ──────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (5) DRY_RUN mirrors the live decision ───"
out=$(sim_sb advance true 0)
ev=$(evline "$out"); st=$(stline "$out")
if [[ "$ev" != *"WOULD TAKE"* && "$ev" == *"Take ABORTED"* ]]; then
    ok "(5a) DRY_RUN + fresh VOTING → NO '[DRY RUN] WOULD TAKE' (a live daemon would have aborted — a WOULD TAKE would be a false report); abort alert fired instead"
else
    bad "(5a) DRY_RUN did not mirror the abort: $ev"
fi
out=$(sim_sb frozen true 0)
ev=$(evline "$out")
if [[ "$ev" == *"WOULD TAKE"* && "$ev" != *MUTATE* ]]; then
    ok "(5b) DRY_RUN + all-frozen → WOULD TAKE fires, and no MUTATE ever (dry run never touches the binary)"
else
    bad "(5b) DRY_RUN frozen path wrong: $ev"
fi

# ── (6) PRIMARY TWIN ────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) PRIMARY twin: real attempt_safe_recovery → switch_to_staked ───"
out=$(sim_pr frozen)
ev=$(evline "$out"); st=$(stline "$out")
echo "    trace: $ev"
if [[ "$ev" == *MUTATE* ]]; then
    pre="${ev%%MUTATE*}"; post="${ev#*MUTATE}"; seg="${pre#*TAKE-ENTER}"
    [[ "$pre" != *"NET"* ]] \
        && ok "(6a) ZERO NET before MUTATE on the recovery path (the gossip advisory ran before switch_to_staked)" \
        || bad "(6a) a NET event precedes MUTATE: $pre"
    [[ "$seg" == *"SAMPLE"* ]] \
        && ok "(6b) re-check SAMPLE between TAKE-ENTER and MUTATE" \
        || bad "(6b) no re-check SAMPLE inside the switch window: $seg"
    [[ "$post" == *"NET"* && "$post" == *"RECOVERED TO STAKED"* ]] \
        && ok "(6c) NET (RECOVERED TO STAKED) only AFTER MUTATE" \
        || bad "(6c) no post-MUTATE recovery alert: $post"
else
    bad "(6a-c) no MUTATE — the recovery switch never happened: $ev"
fi
out=$(sim_pr advance)
ev=$(evline "$out"); st=$(stline "$out")
[[ "$ev" != *MUTATE* && "$(field "$st" rc)" == "1" ]] \
    && ok "(6d) fresh VOTING at the recovery re-check → NO MUTATE, rc 1 (twin abort)" \
    || bad "(6d) recovery mutated despite fresh VOTING (rc=$(field "$st" rc)): $ev"

# ── (7) BYTE-IDENTITY across daemons ────────────────────────────────────────────────────────────
echo ""; echo "─── (7) _fresh_proof_recheck byte-identical in both daemons ───"
P_R=$(sed -n '/^_fresh_proof_recheck() {/,/^}$/p' "$PRIMARY")
S_R=$(sed -n '/^_fresh_proof_recheck() {/,/^}$/p' "$STANDBY")
[[ -n "$P_R" && "$P_R" == "$S_R" ]] \
    && ok "(7) _fresh_proof_recheck body BYTE-IDENTICAL in both daemons ($(printf '%s\n' "$P_R" | wc -l | tr -d ' ') lines)" \
    || bad "(7) _fresh_proof_recheck missing or DIVERGED between the daemons"

# ── (8) PERMANENT REVERT-CONTROL ────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) revert-control: _fresh_proof_recheck(){ return 0; } → the parent's behavior ───"
out=$(sim_sb advance false 1)
ev=$(evline "$out")
[[ "$ev" == *MUTATE* ]] \
    && ok "(8) with the re-check shadowed to a no-op, MUTATE HAPPENS despite the fresh VOTING sample — the parent's behavior; case 2 provably bites" \
    || bad "(8) no MUTATE even with the re-check neutered — case 2 is vacuous: $ev"

# ── (9) FRESH-BACKWARDS ABORT ─────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) FRESH-BACKWARDS ABORT: lastVote below the pin at the re-check ───"
out=$(sim_sb backwards false 0)
ev=$(evline "$out"); st=$(stline "$out")
[[ "$ev" != *MUTATE* && "$(field "$st" rc)" == "1" ]] \
    && ok "(9a) NO MUTATE, rc 1 — an inconsistent (backwards) view at the re-check aborts (fail closed)" \
    || bad "(9a) backwards re-check did not abort (rc=$(field "$st" rc)): $ev"
[[ "$(field "$st" lfv)" == "4999" && "$(field "$st" lfts)" == "60" && "$(field "$st" lla)" == "0" ]] \
    && ok "(9b) pair re-based to the fresh cur (4999@60) with NO liveness re-anchor — mirrors the fence's backwards path" \
    || bad "(9b) state after backwards abort: lfv=$(field "$st" lfv) lfts=$(field "$st" lfts) lla=$(field "$st" lla)"

# ── (10) FRESH-STALE-TIP ABORT ────────────────────────────────────────────────────────────
echo ""; echo "─── (10) FRESH-STALE-TIP ABORT: cluster reference frozen since the pin ───"
out=$(sim_sb stale false 0)
ev=$(evline "$out"); st=$(stline "$out")
[[ "$ev" != *MUTATE* && "$(field "$st" rc)" == "1" ]] \
    && ok "(10a) NO MUTATE, rc 1 — a stale external view at the re-check aborts (fail closed)" \
    || bad "(10a) stale-tip re-check did not abort (rc=$(field "$st" rc)): $ev"
[[ "$(field "$st" lfv)" == "5000" && "$(field "$st" lftip)" == "900000" && "$(field "$st" lfts)" == "60" ]] \
    && ok "(10b) min-rule re-pin (vote kept, tip adopted, clock restarted) — mirrors the fence's tip-stall path" \
    || bad "(10b) state after stale abort: lfv=$(field "$st" lfv) lftip=$(field "$st" lftip) lfts=$(field "$st" lfts)"

# ── (11) RE-ANCHOR CONSUMED (behavioral) ──────────────────────────────────────────────────
echo ""; echo "─── (11) RE-ANCHOR CONSUMED: after a VOTING abort the take lands at abort+DELAY exactly ───"
out=$(sim_sb advance-sticky false 0 200)
ev=$(evline "$out")
enters=$(printf '%s' "$ev" | grep -o 'TAKE-ENTER' | grep -c . )
st=$(stline "$out")
[[ "$enters" == "2" ]] \
    && ok "(11a) exactly two take attempts — the first aborted on the fresh vote, the second proceeded" \
    || bad "(11a) take attempts: $enters (want 2): $ev"
[[ "$ev" == *MUTATE* && "$(field "$st" rc)" == "0" && "$(field "$st" mutoff)" == "120" ]] \
    && ok "(11b) MUTATE at t0+120 = abort(60) + TAKEOVER_DELAY(60) — the abort's re-anchor was CONSUMED by the countdown (behavior, not just a state write)" \
    || bad "(11b) mutate offset $(field "$st" mutoff) (want 120), rc=$(field "$st" rc): $ev"

# ── (12) ABORT-ALERT THROTTLE ─────────────────────────────────────────────────────────────────
echo ""; echo "─── (12) ABORT-ALERT THROTTLE: flip at every re-check for 2000s — pages throttle, never storm ───"
out=$(sim_sb flip false 0 2000)
ev=$(evline "$out")
# each alert_warn produces TWO NET lines (telegram + webhook shadows) — count pages, not lines
aborts=$(( $(printf '%s' "$ev" | grep -o 'Take ABORTED' | grep -c . ) / 2 ))
starv=$(( $(printf '%s' "$ev" | grep -o 'TAKEOVER STARVATION' | grep -c . ) / 2 ))
echo "    abort pages=$aborts starvation pages=$starv"
[[ "$ev" != *MUTATE* ]] \
    && ok "(12a) NO take over 2000s of per-re-check flips (every attempt aborts — fail closed holds)" \
    || bad "(12a) a MUTATE landed under permanent re-check flips: $ev"
[[ "$aborts" -ge 3 && "$aborts" -le 6 ]] \
    && ok "(12b) abort pages throttled: $aborts over 2000s (first immediate, repeats per ALERT_THROTTLE=600) — no per-cycle storm" \
    || bad "(12b) abort pages=$aborts over 2000s (want 3..6) — the abort page storms (or went silent)"
[[ "$starv" -ge 2 ]] \
    && ok "(12c) the starvation page still fires alongside ($starv pages) — a re-check-starved episode is loud" \
    || bad "(12c) starvation pages=$starv (want >=2) — re-check starvation went quiet"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
