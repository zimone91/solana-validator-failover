#!/bin/bash
# v0.7 (Block 3, slice 5): ACT-THEN-ALERT (A8) + fresh-proof re-check. The reviewer's pre-registered
# conditions (slice 3.5): (1) immediately before set-identity a FRESH re-check — arithmetic on the
# existing pinned baseline PLUS one short re-sample, not a gate-cycle re-run; (2) re-check yielding
# VOTING or cannot-determine → ABORT, not proceed; (3) between the re-check and set-identity: no
# network, no alerts; one bounded local veto read allowed (the rule as it stands since Block 6.3.1 —
# the one read is the own-view veto's single LOCAL_RPC batch, curl -m 2; before 6.3.1 the rule
# admitted zero network calls). Extends the demote path's "safety action FIRST" rule (N2) to the
# take path.
#
# harness: tests/lib/harness.sh — load_seam, harness_clock_shims, field, dump_freshness (the sole
# reader of the freshness triple), extract_twin, ok/bad+banners. An ordered EVENT LOG
# (append-only temp file) is written by:
#   SAMPLE <n>  — the shadowed get_staked_liveness_sample (scriptable per-call return values;
#                 the re-check call is identified by _IN_TAKE, set by a thin wrapper that
#                 delegates to the REAL take/switch body via declare -f rename)
#   NET <text>  — shadowed send_telegram / send_webhook (every alert surface)
#   ST8 …       — state snapshot taken AT alert time (proves state writes precede the alert)
#   MUTATE      — a REAL stub `agave-validator` binary on SOLANA_PATH logs set-identity calls
#   TAKE-ENTER / TAKE-EXIT rc=N — the wrapper brackets
#   LOG <text>  — log_warn lines emitted while inside the take (message-content guard)
#   READ <LOCAL|EXT> <what> — the shadowed curl (6.3.1): every HTTP request, in order — the A8 census
#                 counts them between the re-check SAMPLE and MUTATE (exactly ONE: READ LOCAL batch,
#                 the own-view veto). The LOCAL answers: the confirmed head advancing 4 slots/s; the
#                 veto batch per OVMODE — pass (default: the holder DELINQUENT in the confirmed view at
#                 lastVote 5000 = the own-bank maximum) | voting (not delinquent) | voting-once (voting on
#                 the first batch only) | down (the batch read fails, rc 7). Each sim cycle takes the
#                 main loop's own-head sample and own-bank note (the standby's per-cycle [own-view]
#                 callers; the primary's recovery path takes its own)
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
#   (7) BYTE-IDENTITY: _fresh_proof_recheck (and its _recheck_tier_read) identical across daemons; (7c) its
#       DECISION per (pinned vantage, each tier's answer), all 50 cells on both daemons, against the rule (fix
#       round 2, S1: both tiers read at once, a life sign in ANY answer aborts), with three controls — fix round
#       1's schedule, the TIER2-first call of the builds before it, the other tier's life sign ignored
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
#   (13) THE OWN-VIEW VETO at the A8 edge (Block 6.3.1, D3): (1e)/(5b)/(6e) — ONE LOCAL read (the
#       veto batch) between the re-check SAMPLE and MUTATE / WOULD TAKE, zero NET, zero other reads;
#       (13a) a VOTING veto → no MUTATE, rc 1, _own_bank_active_time stamped BEFORE the alert (the
#       ST8 snapshot), no cooldown; (13b) a failed veto read → no MUTATE, the blind stamp re-anchors;
#       (13c) DRY_RUN mirrors the veto (no WOULD TAKE); (13d) a voting-once veto's re-anchor is
#       CONSUMED (the take lands at veto + TAKEOVER_DELAY); (13e) the veto page throttles (the (12)
#       idiom) while the starvation page still fires
#   (14) the primary's recovery path on ONE chain model (sim_chain): the RECOVERY_DELAY band, the named
#       default-config cost, a VOTING/BLIND veto re-elapsing the full delay (the M12 / blind-anchor mutants);
#       fix round 2: (14d)/(14e) the delta panel's T5-UNPINNED lines — the delay tail's samples, the R1 pass
#       stop (tiers lagging: TLAG; each layer alone and both neutered) — and (14f) DAV-6's stuck page (red first)
#   (15) the DYNAMIC halves of the take-path and A8 censuses (fix round 1, the panel's T3/T4): every STAKED
#       set-identity in this suite's sims followed the veto's read with nothing but log lines between (the
#       agave-validator stub audits each), and a logging curl FIRST in PATH saw no curl-binary call; controls:
#       the veto call deleted → red; the panel's A1 (`command curl` after the veto) → caught, red, never sent
# RED (captured before the slice-5 daemon changes): cases 1–7 fail — the order case sees NET (🔍)
# before MUTATE and no re-check SAMPLE; the abort cases see MUTATE despite fresh VOTING; (7) has no
# helper to compare. (9)/(10) were observed red by MUTATION (branch neutered → red) after landing;
# (12) was observed red against the unthrottled first cut (≥50 pages over 2000s).

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

T0=100000            # mono origin (never 0 — 0 collides with the "unset" sentinel)
DELAY=60             # TAKEOVER_DELAY / RECOVERY_DELAY (shipped default)
MININT=10            # VOTE_LIVENESS_MIN_INTERVAL (shipped default)
SPAN=40              # VOTE_LIVENESS_MIN_SPAN (shipped default)

# ── ov_curl_shim — the LOCAL_RPC the [own-view] region reads (6.3.1); installed inside each sim ────
# Every curl is logged READ <LOCAL|EXT> <what> in order (the A8 census). LOCAL getSlot = the confirmed
# head (800000 + 4 slots/s — advancing); the veto batch per OVMODE (see the header); EXT → rc 7.
ov_curl_shim() {
  LOCAL_RPC="http://local.mock"
  curl(){
      local url="" d="" src what ida idb off hc m
      while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac; done
      src=EXT; [[ "$url" == "$LOCAL_RPC" ]] && src=LOCAL
      what=other; case "$d" in "["*) what=batch ;; *getSlot*) what=getSlot ;; *getVoteAccounts*) what=getVoteAccounts ;; esac
      printf 'READ %s %s\n' "$src" "$what" >> "$_EVT_FILE"
      [[ "$src" == "LOCAL" ]] || return 7
      off=$(( _SIM_NOW - T0 )); hc=$(( 800000 + 4 * off ))
      case "$what" in
          getSlot) printf '{"jsonrpc":"2.0","id":1,"result":%s}' "$hc"; return 0 ;;
          batch)
              m="${OVMODE:-pass}"
              if [[ "$m" == "voting-once" ]]; then
                  if [[ $(grep -c '^READ LOCAL batch' "$_EVT_FILE") -le 1 ]]; then m=voting; else m=pass; fi
              fi
              [[ "$m" == "down" ]] && return 7
              ida=${d#*\"id\":}; ida=${ida%%,*}; idb=${d##*\"id\":}; idb=${idb%%,*}
              if [[ "$m" == "voting" ]]; then
                  printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]}}]' "$ida" "$hc" "$idb" "$(( hc - 1 ))"
              else
                  printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":{"current":[],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":5000}]}}]' "$ida" "$hc" "$idb"
              fi
              return 0 ;;
      esac
      return 7
  }
}

# a8_between <events> <end-marker-glob> — the reads/NETs between the LAST re-check SAMPLE before the
# end marker and the marker itself: "local=<n> batch=<n> other=<n> net=<n>"
a8_between() {
  local ev="$1" endm="$2" pre seg
  pre="${ev%%"$endm"*}"
  [[ "$pre" == "$ev" ]] && { echo "local=- batch=- other=- net=- (no end marker)"; return 0; }
  seg="${pre##*SAMPLE }"; seg="${seg#*;}"
  printf 'local=%s batch=%s other=%s net=%s\n' \
      "$(printf '%s' "$seg" | tr ';' '\n' | grep -c '^READ LOCAL')" \
      "$(printf '%s' "$seg" | tr ';' '\n' | grep -c '^READ LOCAL batch$')" \
      "$(printf '%s' "$seg" | tr ';' '\n' | grep -c '^READ EXT')" \
      "$(printf '%s' "$seg" | tr ';' '\n' | grep -c '^NET')"
}

# ── the net guard + the STAKED-MUTATE audit (6.3.1 fix round 1, R6 — the panel's T4 and T3) ─────────────
# Every sim puts a logging `curl` FIRST in PATH: the sims shadow curl as a shell FUNCTION, so only `command curl`,
# `env curl` or an exec'd curl reaches a curl BINARY — the logger records it as a NET event (in the sim's event log
# and the suite log) and fails it (rc 7): no request leaves a sim, and the A8 census sees it (the panel's A1 sent 5
# real requests to the public cluster through `command curl` and stayed green). The agave-validator stub AUDITS
# every set-identity to the STAKED keypair: the events since the last veto read (READ LOCAL batch — sim_chain's
# veto logs CLEAR), log lines aside — case (15) requires that list empty for every staked MUTATE in the suite.
_MUT_AUDIT=$(mktemp "${TMPDIR:-/tmp}/ata-mut.XXXXXX"); _CURLBIN_LOG=$(mktemp "${TMPDIR:-/tmp}/ata-curl.XXXXXX")
export _MUT_AUDIT _CURLBIN_LOG
sim_stubs() {   # $1=stub dir — writes the logging curl and the auditing agave-validator stub
  cat > "$1/curl" <<'EOS'
#!/bin/sh
printf 'NET CURLBIN %s\n' "$*" | cut -c1-160 >> "$_EVT_FILE"
printf '%s\n' "$*" >> "$_CURLBIN_LOG"
exit 7
EOS
  cat > "$1/agave-validator" <<'EOS'
#!/bin/sh
case "$*" in
  *set-identity*)
    case "$*" in *"set-identity $_STAKED_KP"*)
      awk -v m="${_VETO_MARK:-^READ LOCAL batch\$}" '$0 ~ m { s = 1; b = ""; next } s && !/^LOG / { b = b $0 ";" } END { printf "STAKED veto=%s between=[%s]\n", (s ? "yes" : "NO"), b }' "$_EVT_FILE" >> "$_MUT_AUDIT" ;;
    esac
    if [ -n "$_MUT_T" ]; then echo "MUTATE t=$(( _SIM_NOW - 100000 ))"; else echo "MUTATE"; fi >> "$_EVT_FILE" ;;
esac
exit 0
EOS
  chmod +x "$1/curl" "$1/agave-validator"
}

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
  load_seam "$STANDBY"
  _RMODE="$rmode"
  EVT=$(mktemp); export _EVT_FILE="$EVT"
  STUB=$(mktemp -d)
  sim_stubs "$STUB"; PATH="$STUB:$PATH"
  KP=$(mktemp); echo '[1]' > "$KP"; STAKED_KEYPAIR="$KP"; export _STAKED_KP="$KP"
  trap 'rm -f "$KP" "$EVT"; rm -rf "$STUB"' EXIT
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
  SOLANA_PATH="$STUB"; LEDGER_PATH="/mock/ledger"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
  TAKEOVER_DELAY=$DELAY; TAKEOVER_COOLDOWN=0; EXTERNAL_CONFIRM_THROTTLE=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0
  VOTE_LIVENESS_MIN_SPAN=$SPAN
  GOSSIP_VERIFY=false; WITNESS_FASTPATH=false; DRY_RUN="$dry"; TG_ENABLED=false
  harness_clock_shims
  log(){ :;}; log_info(){ :;}; log_error(){ :;}
  log_warn(){ if [[ ${_IN_TAKE:-0} -eq 1 ]]; then local t="${1//$'\n'/ }"; printf 'LOG %s\n' "${t:0:120}" >> "$_EVT_FILE"; fi; }
  send_telegram(){
      local t="${1//$'\n'/ }"
      printf 'NET %s\n' "${t:0:120}" >> "$_EVT_FILE"
      printf 'ST8 lla=%s lfv=%s obs=%s oba=%s bl=%s\n' "$LAST_LIVENESS_ACTIVE_TIME" "$_liveness_first_vote" "$(field "$(dump_freshness)" observed_since)" "${_own_bank_active_time:-0}" "$(field "$(dump_freshness)" blind_until)" >> "$_EVT_FILE"
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
  ov_curl_shim
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
      # 6.3.1: the standby main loop's per-cycle [own-view] callers in an open episode — the own-head sample
      # and the own-bank note (local_check_delinquency's holder lastVote: 5000, delinquent)
      _own_head_sample >/dev/null 2>&1; _own_bank_note 5000
      attempt_takeover >/dev/null 2>&1
      grep -q "$stopmark" "$EVT" && break
  done
  local mutoff=-1
  grep -q '^MUTATE' "$EVT" && mutoff=$(( _SIM_NOW - T0 ))   # the loop breaks on the MUTATE tick
  local lla=$LAST_LIVENESS_ACTIVE_TIME lfts=$_liveness_first_ts obs blind
  obs=$(field "$(dump_freshness)" observed_since); blind=$(field "$(dump_freshness)" blind_until)
  [[ $lla   -gt 0 ]] && lla=$((   lla - T0 ))
  [[ $lfts  -gt 0 ]] && lfts=$((  lfts - T0 ))
  [[ $obs   -gt 0 ]] && obs=$((   obs - T0 ))
  [[ $blind -gt 0 ]] && blind=$(( blind - T0 ))
  printf 'EVENTS=%s\n' "$(tr '\n' ';' < "$EVT")"
  local oba=${_own_bank_active_time:-0}; [[ $oba -gt 0 ]] && oba=$(( oba - T0 ))
  printf 'STATE=rc=%s|lla=%s|lfv=%s|lftip=%s|lfts=%s|lfp=%s|obs=%s|blind=%s|ltt=%s|mutoff=%s|oba=%s\n' \
      "$_take_rc" "$lla" "$_liveness_first_vote" "$_liveness_first_tip" "$lfts" \
      "$(field "$(dump_freshness)" vantage)" "$obs" "$blind" "$LAST_TAKEOVER_TIME" "$mutoff" "$oba"
  )
}

# ── PRIMARY sim: REAL attempt_safe_recovery → REAL switch_to_staked (Part-1 recovery idiom) ────
#   $1 = re-check mode while _IN_TAKE=1 (frozen | advance)
sim_pr() {
  local rmode="$1"
  (
  set +e
  load_seam "$PRIMARY"
  _RMODE="$rmode"
  EVT=$(mktemp); export _EVT_FILE="$EVT"
  STUB=$(mktemp -d)
  sim_stubs "$STUB"; PATH="$STUB:$PATH"
  KP=$(mktemp); echo '[1]' > "$KP"; STAKED_KEYPAIR="$KP"; export _STAKED_KP="$KP"
  trap 'rm -f "$KP" "$EVT"; rm -rf "$STUB"' EXIT
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
  SOLANA_PATH="$STUB"; LEDGER_PATH="/mock/ledger"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
  RECOVERY_DELAY=$DELAY; RECOVERY_CHECKS=1; RECOVERY_CHECK_INTERVAL=0; RECOVERY_COOLDOWN=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0
  VOTE_LIVENESS_MIN_SPAN=$SPAN
  DRY_RUN=false; TG_ENABLED=false
  harness_clock_shims
  log(){ :;}; log_info(){ :;}; log_error(){ :;}
  log_warn(){ if [[ ${_IN_TAKE:-0} -eq 1 ]]; then local t="${1//$'\n'/ }"; printf 'LOG %s\n' "${t:0:120}" >> "$_EVT_FILE"; fi; }
  send_telegram(){
      local t="${1//$'\n'/ }"
      printf 'NET %s\n' "${t:0:120}" >> "$_EVT_FILE"
      printf 'ST8 lla=%s lfv=%s obs=%s\n' "${LAST_LIVENESS_ACTIVE_TIME:-0}" "$_liveness_first_vote" "$(field "$(dump_freshness)" observed_since)" >> "$_EVT_FILE"
      return 0
  }
  send_webhook(){ local t="${1//$'\n'/ }"; printf 'NET %s\n' "${t:0:120}" >> "$_EVT_FILE"; return 0; }
  save_state(){ :;}; sleep(){ :;}
  get_local_identity(){ echo "$STAKED_PUBKEY"; }
  timeout(){ shift 3; "$@"; }
  tier1_check_delinquency(){ _t1_holder_lv=5000; return 1; }   # local: no longer delinquent (6.3.1: exposes the holder's lastVote as the real one does — the recovery path folds it into the own-bank maximum)
  ov_curl_shim
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

# ── sim_chain — the PRIMARY's recovery path on ONE chain model (6.3.1 fix round 1, R6 — the panel's L5/T8) ──
# Every view the recovery path reads comes from ONE chain: the head advances RATE_N/RATE_D slots/s from
# 900000 at T0; the staked vote account's votes land at the head of their second (a vote at t is for slot(t) − 1,
# landed in slot(t)): its last regular vote at TV (default 0 — the holder's demote), VOTE1=<t> one more vote
# (someone voted the staked identity once). LOCAL_RPC — the processed head slot(t), confirmed −2, finalized −32;
# getVoteAccounts at the commitment asked with agave's 128-slot current/delinquent partition (tier1's finalized
# read, the veto's filtered confirmed batch); getClusterNodes: this node (U1) at 1.2.3.4:8001. TIER2/TIER3 —
# HONEST, the same chain (processed for the liveness sampler, finalized for the tier-2 check and the gossip
# advisory's vote-account read; the staked identity S1 in gossip at OUR endpoint: nobody else holds it).
# OVDOWN=1: the veto's batch read fails (rc 7). TLAG=<s> (fix round 2 — T5-UNPINNED): TIER2/TIER3 honest but <s> s
# behind the chain (their every view at t − TLAG); LOCAL is never behind. The loop: attempt_safe_recovery every CI s (default 3);
# every sleep — the recovery ladder's, switch_to_staked's — advances the clock; LAST_SWITCH_TIME = T0.
# Events: PASS-START t= (a recovery-eligible pass), TAKE-ENTER t=, VETO <kind> t=, CLEAR age= (the veto's
# baseline age), MUTATE t=, STUCK-PAGE t= (fix round 2, DAV-6: RECOVERY_MODE=rpc not completing). WSCRIPT: a mutant primary.
sim_chain() {
  (
  set +e
  load_seam "${WSCRIPT:-$PRIMARY}"
  EVT=$(mktemp); export _EVT_FILE="$EVT"
  STUB=$(mktemp -d)
  sim_stubs "$STUB"; PATH="$STUB:$PATH"; export _MUT_T=1 _VETO_MARK='^CLEAR age='
  KP=$(mktemp); echo '[1]' > "$KP"; STAKED_KEYPAIR="$KP"; export _STAKED_KP="$KP"
  trap 'rm -f "$KP" "$EVT"; rm -rf "$STUB"' EXIT
  STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
  LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
  SOLANA_PATH="$STUB"; LEDGER_PATH="/mock/ledger"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
  RECOVERY_DELAY=${RD:-300}; RECOVERY_CHECKS=${RC:-3}; RECOVERY_CHECK_INTERVAL=${RI:-30}; RECOVERY_COOLDOWN=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=10; VOTE_LIVENESS_EPSILON=0; VOTE_LIVENESS_MIN_SPAN=40
  DRY_RUN=false; TG_ENABLED=false; ALERT_THROTTLE=600
  harness_clock_shims
  export _SIM_NOW
  log(){ :;}; log_error(){ :;}; log_warn(){ case "$*" in *"[own-view] VETO (holder voting)"*) printf 'VETO voting t=%s\n' $(( _SIM_NOW - T0 )) >> "$_EVT_FILE" ;; *"[own-view] VETO (blind)"*) printf 'VETO blind t=%s\n' $(( _SIM_NOW - T0 )) >> "$_EVT_FILE" ;; esac; }
  log_info(){ case "$*" in *"[own-view] veto read clear"*) local _a="${*##*baseline }"; _a="${_a#* (}"; _a="${_a%% s old*}"; printf 'CLEAR age=%s t=%s\n' "$_a" $(( _SIM_NOW - T0 )) >> "$_EVT_FILE" ;; esac; }
  alert(){ :;}; alert_info(){ :;}; send_telegram(){ return 0; }; send_webhook(){ :; }
  alert_warn(){ case "$*" in *"RECOVERY_MODE=rpc: eligible for"*) printf 'STUCK-PAGE t=%s\n' $(( _SIM_NOW - T0 )) >> "$_EVT_FILE" ;; esac; }   # fix round 2 (S5 — DAV-6): the stuck page
  save_state(){ :;}
  sleep(){ local _s="${1%%.*}"; case "$_s" in ''|*[!0-9]*) _s=0 ;; esac; _SIM_NOW=$(( _SIM_NOW + _s )); export _SIM_NOW; }
  get_local_identity(){ echo "$STAKED_PUBKEY"; }
  timeout(){ [[ "$1" == "-k" ]] && shift 2; shift; "$@"; }
  _slot(){ echo $(( 900000 + $1 * ${RATE_N:-1} / ${RATE_D:-1} )); }
  _lv_in(){   # the staked account's lastVote as a bank at slot $1 shows it
      local b=$1 v s
      s=$(_slot "${TV:-0}"); v=$(( s - 1 ))
      if [[ -n "${VOTE1:-}" ]]; then s=$(_slot "$VOTE1"); [[ $s -le $b ]] && v=$(( s - 1 )); fi
      echo "$v"
  }
  _gva(){   # $1 = bank slot, $2 = "all"|"filtered" → a getVoteAccounts result object
      local b=$1 lv acct part="current"; lv=$(_lv_in "$b")
      [[ $lv -le $(( b - 128 )) ]] && part="delinquent"
      acct="{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":$lv}"
      if [[ "$2" == "filtered" ]]; then
          if [[ "$part" == "current" ]]; then printf '{"current":[%s],"delinquent":[]}' "$acct"; else printf '{"current":[],"delinquent":[%s]}' "$acct"; fi
      elif [[ "$part" == "current" ]]; then printf '{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s},%s],"delinquent":[]}' $(( b - 1 )) "$acct"
      else printf '{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[%s]}' $(( b - 1 )) "$acct"; fi
  }
  curl(){
      local url="" d="" src what comm t h b ida idb
      while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac; done
      case "$url" in "$LOCAL_RPC") src=LOCAL ;; "$TIER2_RPC"|"$TIER3_RPC") src=EXT ;; *) return 7 ;; esac
      what=other; case "$d" in "["*) what=batch ;; *getSlot*) what=getSlot ;; *getVoteAccounts*) what=getVoteAccounts ;; *getClusterNodes*) what=getClusterNodes ;; esac
      comm=finalized; case "$d" in *'"commitment":"processed"'*) comm=processed ;; *'"commitment":"confirmed"'*) comm=confirmed ;; esac
      t=$(( _SIM_NOW - T0 )); [[ "$src" == EXT ]] && t=$(( t - ${TLAG:-0} )); h=$(_slot "$t")   # TLAG: TIER2/TIER3 honest but <TLAG> s behind (fix round 2, T5)
      case "$comm" in processed) b=$h ;; confirmed) b=$(( h - 2 )) ;; *) b=$(( h - 32 )) ;; esac
      case "$what" in
          getSlot) printf '{"jsonrpc":"2.0","id":1,"result":%s}' "$b" ;;
          getVoteAccounts) printf '{"jsonrpc":"2.0","id":1,"result":%s}' "$(_gva "$b" all)" ;;
          getClusterNodes) printf '{"jsonrpc":"2.0","id":1,"result":[{"pubkey":"S1","gossip":"1.2.3.4:8001"},{"pubkey":"U1","gossip":"1.2.3.4:8001"}]}' ;;
          batch)
              [[ "$src" == LOCAL && "${OVDOWN:-0}" != "1" ]] || return 7
              b=$(( h - 2 )); ida=${d#*\"id\":}; ida=${ida%%,*}; idb=${d##*\"id\":}; idb=${idb%%,*}
              printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":%s}]' "$ida" "$b" "$idb" "$(_gva "$b" filtered)" ;;
          *) return 7 ;;
      esac
      return 0
  }
  eval "$(declare -f switch_to_staked | sed '1s/^switch_to_staked/_real_switch_to_staked/')"
  switch_to_staked(){ printf 'TAKE-ENTER t=%s\n' $(( _SIM_NOW - T0 )) >> "$_EVT_FILE"; _real_switch_to_staked "$@"; }
  eval "$(declare -f tier1_check_delinquency | sed '1s/^tier1_check_delinquency/_real_tier1_check_delinquency/')"
  tier1_check_delinquency(){ printf 'PASS-START t=%s\n' $(( _SIM_NOW - T0 )) >> "$_EVT_FILE"; _real_tier1_check_delinquency; }   # the recovery pass's first read (a pass the anchor let through)
  _SIM_NOW=$T0; export _SIM_NOW
  LAST_SWITCH_TIME=$T0; _last_recovery_log=0; _recovery_confirm_count=0; _standby_alert_sent=""
  _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
  _last_blind_end=0; _liveness_obs_since=0; CURRENT_IDENTITY="U1"; _own_view_reset
  while [[ $(( _SIM_NOW - T0 )) -le ${HZ:-400} ]]; do
      attempt_safe_recovery >/dev/null 2>&1
      grep -q '^MUTATE' "$EVT" && break
      _SIM_NOW=$(( _SIM_NOW + ${CI:-3} )); export _SIM_NOW
  done
  printf 'EVENTS=%s\n' "$(tr '\n' ';' < "$EVT")"
  )
}
evline(){ printf '%s\n' "$1" | grep '^EVENTS=' | head -1 | cut -c8-; }
stline(){ printf '%s\n' "$1" | grep '^STATE='  | head -1 | cut -c7-; }

title_banner "Act-then-alert + fresh-proof re-check (v0.7 Block 3 slice 5)"

# ── (1) ORDER-PROCEED (standby, end-to-end) ─────────────────────────────────────────────────────
echo ""; echo "─── (1) ORDER-PROCEED: real attempt_takeover to a successful take ───"
out=$(sim_sb frozen false 0)
ev=$(evline "$out"); st=$(stline "$out")
echo "    trace: $ev"
if [[ "$ev" == *MUTATE* ]]; then
    pre="${ev%%MUTATE*}"; post="${ev#*MUTATE}"; seg="${pre#*TAKE-ENTER}"
    [[ "$pre" != *"NET"* ]] \
        && ok "(1a) ZERO NET before MUTATE — no 🔍 pre-take alert; between the re-check and set-identity: no network, no alerts; one bounded local veto read allowed (condition 3)" \
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
    a8=$(a8_between "$ev" "MUTATE")
    [[ "$a8" == "local=1 batch=1 other=0 net=0" ]] \
        && ok "(1e) A8 census (6.3.1): between the re-check SAMPLE and MUTATE exactly ONE read — READ LOCAL batch, the own-view veto — and zero NET, zero other reads (no network, no alerts; one bounded local veto read allowed)" \
        || bad "(1e) A8 census between the re-check SAMPLE and MUTATE: $a8 (want local=1 batch=1 other=0 net=0)"
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
a8=$(a8_between "$ev" "LOG [DRY RUN] Would TAKE")
if [[ "$ev" == *"WOULD TAKE"* && "$ev" != *MUTATE* && "$a8" == "local=1 batch=1 other=0 net=0" ]]; then
    ok "(5b) DRY_RUN + all-frozen → WOULD TAKE fires, and no MUTATE ever (dry run never touches the binary); A8 census (6.3.1): ONE read — the veto's READ LOCAL batch — between the re-check SAMPLE and the WOULD TAKE, zero NET (the veto runs BEFORE the DRY_RUN branch)"
else
    bad "(5b) DRY_RUN frozen path wrong (A8 census: $a8): $ev"
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
    a8=$(a8_between "$ev" "MUTATE")
    [[ "$a8" == "local=1 batch=1 other=0 net=0" ]] \
        && ok "(6e) A8 census on the PRIMARY twin (6.3.1): ONE read — the veto's READ LOCAL batch — between the re-check SAMPLE and MUTATE, zero NET" \
        || bad "(6e) A8 census on the recovery path: $a8"
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
extract_twin '^_fresh_proof_recheck() {' '^}$'
P_R=$TWIN_P; S_R=$TWIN_S
extract_twin '^_recheck_tier_read() {' '^}$'   # fix round 2 (S1): the re-check's per-tier branch
P_T=$TWIN_P; S_T=$TWIN_S
[[ -n "$P_R" && "$P_R" == "$S_R" && -n "$P_T" && "$P_T" == "$S_T" ]] \
    && ok "(7) _fresh_proof_recheck body BYTE-IDENTICAL in both daemons ($(printf '%s\n' "$P_R" | wc -l | tr -d ' ') lines), and its per-tier branch _recheck_tier_read ($(printf '%s\n' "$P_T" | wc -l | tr -d ' ') lines)" \
    || bad "(7) _fresh_proof_recheck / _recheck_tier_read missing or DIVERGED between the daemons"

# ── (7c) the re-check's DECISION per (pinned vantage, what each tier answers) — fix round 2, S1 ──────────
# The rule (fix round 2, S1 — the delta panel's DL-1): with two distinct tiers the re-check reads BOTH at once;
# a life sign (lastVote past the pin) in ANY answer aborts as VOTING; with none, the take rests ONLY on the pinned
# vantage's own answer (backwards / a stale reference abort, a frozen one proceeds); the pinned vantage silent,
# the other tier's answer aborts (backwards, or a provider flip); nothing usable → the blind abort. The whole
# table, cell by cell, on BOTH daemons' REAL _fresh_proof_recheck: each tier answers down / frozen (lastVote = the
# pin, its reference advanced) / advanced (+10) / backwards (−10) / stale (frozen with the reference NOT advanced),
# the expected outcome COMPUTED from the rule above — the sampler shadow answers per tier and honours the blanked
# URL of each branch, as the real one does. Fix round 1's re-check (the pinned vantage first, the other only when
# it failed) took in the cell "pinned on TIER3, TIER2 back and showing the holder VOTING" (DL-1, measured on the
# real loop 21-34 s into the holder's voting); every build before it read TIER2 first and never read TIER3 while
# TIER2 answered, so it proceeded in "pinned on TIER2, TIER2 frozen, TIER3 showing the holder VOTING". CONTROLS
# (mutate(), loud on a no-op): the read schedule replaced by fix round 1's (m7c-r1: pinned first, the other tier
# only on a failure) and by the builds' before it (m7c-t2: one two-tier call, TIER2 first) — each must break the
# table in the cells named; the other tier's life sign ignored (m7c-obs) must break exactly fix round 1's six.
echo ""; echo "─── (7c) the re-check's decision per (pinned vantage, each tier's answer): both daemons + three schedule/selection controls ───"
dec_table() {   # $1 = daemon → one line per cell: "<pin> <T2 kind> <T3 kind> <rc> <outcome>" (the seam loaded ONCE)
  (
    set +e
    load_seam "$1" >/dev/null 2>&1
    harness_clock_shims; _SIM_NOW=$(( T0 + 100 ))
    log(){ :;}; log_info(){ :;}; log_error(){ :;}; _recheck_abort_alert(){ :;}; _note_blind_cycle(){ :;}
    log_warn(){ _DL="$*"; }
    VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_EPSILON=0; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
    _dans() {   # $1 = kind, $2 = tier label → the sampler's line (or nothing: down)
        case "$1" in
            frozen) echo "5000 900100 $2" ;; advanced) echo "5010 900100 $2" ;; backwards) echo "4990 900100 $2" ;;
            stale) echo "5000 900000 $2" ;; *) return 1 ;;
        esac
    }
    get_staked_liveness_sample(){
        if [[ -n "$TIER2_RPC" ]] && _dans "$_DK2" T2; then return 0; fi
        if [[ -n "$TIER3_RPC" ]] && _dans "$_DK3" T3; then return 0; fi
        return 1
    }
    local _pin _k2 _k3 _drc _dout
    for _pin in T2 T3; do
      for _k2 in down frozen advanced backwards stale; do
        for _k3 in down frozen advanced backwards stale; do
          _liveness_first_vote=5000; _liveness_first_tip=900000; _liveness_first_provider="$_pin"; _liveness_first_ts=$T0
          _DK2="$_k2"; _DK3="$_k3"; _DL=""
          _fresh_proof_recheck >/dev/null 2>&1; _drc=$?
          case "$_DL" in
              *"staked vote ADVANCED"*) _dout=voting ;; *"provider flipped"*) _dout=flip ;; *"no usable sample"*) _dout=blind ;;
              *"did not advance"*) _dout=stale ;; *"went backwards"*) _dout=back ;; *) _dout=proceed ;;
          esac
          echo "$_pin $_k2 $_k3 $_drc $_dout"
        done
      done
    done
  )
}
dec_want() {   # the rule → "<rc> <outcome>" for pin $1, TIER2 kind $2, TIER3 kind $3
    local pin="$1" k2="$2" k3="$3" kp ko
    if [[ "$k2" == "advanced" || "$k3" == "advanced" ]]; then echo "1 voting"; return; fi
    if [[ "$pin" == "T2" ]]; then kp="$k2"; ko="$k3"; else kp="$k3"; ko="$k2"; fi
    case "$kp" in
        frozen) echo "0 proceed"; return ;; backwards) echo "1 back"; return ;; stale) echo "1 stale"; return ;;
    esac
    case "$ko" in frozen|stale) echo "1 flip" ;; backwards) echo "1 back" ;; *) echo "1 blind" ;; esac
}
_d7c_r1=$(mktemp "${TMPDIR:-/tmp}/ata-7c-r1.XXXXXX"); _d7c_t2=$(mktemp "${TMPDIR:-/tmp}/ata-7c-t2.XXXXXX"); _d7c_ob=$(mktemp "${TMPDIR:-/tmp}/ata-7c-ob.XXXXXX")
# round 1's order, spelled without the triple's name after a '$' in this file (run_all's stage (3): a suite never
# dereferences the freshness triple — the name is spliced in by @LFP@, the mutant reads it as round 1 did)
_d7c_r1_sed=$(cat <<'EOS'
/^_fresh_proof_recheck() {/,/^}/s/^        s=\$(_recheck_tier_read T2 & _recheck_tier_read T3 & wait)$/        if [[ "${@LFP@:-}" == "T3" ]]; then s=$(_recheck_tier_read T3) || s=$(_recheck_tier_read T2) || s=""; else s=$(_recheck_tier_read T2) || s=$(_recheck_tier_read T3) || s=""; fi/
EOS
)
mutate "$STANDBY" "${_d7c_r1_sed//@LFP@/_liveness_first_provider}" "$_d7c_r1"
mutate "$STANDBY" '/^_fresh_proof_recheck() {/,/^}/s/^        s=\$(_recheck_tier_read T2 & _recheck_tier_read T3 & wait)$/        s=$(get_staked_liveness_sample) || s=""/' "$_d7c_t2"
mutate "$STANDBY" '/^_fresh_proof_recheck() {/,/^}/s/^    if \[\[ -z "\$cur" \&\& \$noa -eq 1 \]\]; then$/    if false; then/' "$_d7c_ob"
dec_ok=1; dec_diff=""; dec_n=0; r1_cells=""; t2_cells=""; ob_cells=""
_tp=$(dec_table "$PRIMARY"); _ts=$(dec_table "$STANDBY"); _tr1=$(dec_table "$_d7c_r1"); _tt2=$(dec_table "$_d7c_t2"); _tob=$(dec_table "$_d7c_ob")
_dcell() { printf '%s\n' "$1" | awk -v p="$2" -v a="$3" -v b="$4" '$1==p && $2==a && $3==b { print $4 " " $5 }'; }
for _pin in T2 T3; do
  for _k2 in down frozen advanced backwards stale; do
    for _k3 in down frozen advanced backwards stale; do
      dec_n=$((dec_n + 1))
      _w=$(dec_want "$_pin" "$_k2" "$_k3")
      _dp=$(_dcell "$_tp" "$_pin" "$_k2" "$_k3"); _ds=$(_dcell "$_ts" "$_pin" "$_k2" "$_k3")
      [[ "$_dp" == "$_w" && "$_ds" == "$_w" ]] || { dec_ok=0; dec_diff="$dec_diff [pin $_pin T2=$_k2 T3=$_k3: primary='$_dp' standby='$_ds' want='$_w']"; }
      [[ "$(_dcell "$_tr1" "$_pin" "$_k2" "$_k3")" == "$_w" ]] || r1_cells="$r1_cells $_pin:$_k2/$_k3"
      [[ "$(_dcell "$_tt2" "$_pin" "$_k2" "$_k3")" == "$_w" ]] || t2_cells="$t2_cells $_pin:$_k2/$_k3"
      [[ "$(_dcell "$_tob" "$_pin" "$_k2" "$_k3")" == "$_w" ]] || ob_cells="$ob_cells $_pin:$_k2/$_k3"
    done
  done
done
rm -f "$_d7c_r1" "$_d7c_t2" "$_d7c_ob"
# the controls' broken cells, named: fix round 1's schedule loses exactly the life signs of a tier read only on a
# failure (pinned T3: TIER2 advanced with TIER3 answering; pinned T2: TIER3 advanced with TIER2 answering); the
# TIER2-first call loses TIER3's life signs whenever TIER2 answers (and misreads the pinned-T3 cells TIER2 answers);
# ignoring the other tier's life sign loses the same six cells (a silent pinned vantage still hands the other
# tier's answer to the fallback, whose advance still aborts)
_want_r1=" T2:frozen/advanced T2:backwards/advanced T2:stale/advanced T3:advanced/frozen T3:advanced/backwards T3:advanced/stale"
_r1_ok=0; [[ "$r1_cells" == "$_want_r1" ]] && _r1_ok=1
_t2_has=1; for _c in T2:frozen/advanced T2:backwards/advanced T2:stale/advanced T3:frozen/frozen T3:backwards/frozen; do [[ " $t2_cells " == *" $_c "* ]] || _t2_has=0; done
_ob_has=0; [[ "$ob_cells" == "$_want_r1" ]] && _ob_has=1   # the same six: a pinned vantage that is silent hands the other answer to the fallback selection, which still reads its advance
if [[ $dec_ok -eq 1 && $dec_n -eq 50 && $_r1_ok -eq 1 && $_t2_has -eq 1 && $_ob_has -eq 1 ]]; then
    ok "(7c) the re-check's DECISION, all $dec_n cells (pin T2/T3 x each tier down / frozen / advanced / backwards / stale) on BOTH daemons' real _fresh_proof_recheck = the rule: a life sign in ANY answer → VOTING abort; else the pinned vantage's own answer (frozen → proceed; backwards / stale → abort); pinned vantage silent → the other tier's answer aborts (flip / backwards); nothing → blind. CONTROLS, each breaks the table where it must: fix round 1's schedule (pinned first, the other only on a failure) in exactly$r1_cells (the lost VOTING aborts — DL-1 and its pinned-T2 mirror); the builds' before it (one call, TIER2 first) in ${t2_cells# } (TIER3 unread while TIER2 answers: its life signs lost in the pinned-T2 cells — the cells every earlier build took — and each pinned-T3 cell TIER2 answers decided on TIER2's answer); the other tier's life sign ignored in the same six"
else
    bad "(7c) re-check decision table (cells=$dec_n):$dec_diff | controls: r1=[$r1_cells] (want [$_want_r1]) t2-first=[$t2_cells] (has-all=$_t2_has) obs-ignored=[$ob_cells] (has-all=$_ob_has)"
fi

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

# ── (13) THE OWN-VIEW VETO at the A8 edge (Block 6.3.1, D3) ─────────────────────────────────────
echo ""; echo "─── (13) the own-view veto: voting / failed read / DRY_RUN mirror / re-anchor consumed / page throttle ───"
out=$(OVMODE=voting sim_sb frozen false 0)
ev=$(evline "$out"); st=$(stline "$out")
if [[ "$ev" != *MUTATE* && "$(field "$st" rc)" == "1" && "$(field "$st" oba)" == "60" && "$(field "$st" ltt)" == "0" \
      && "$ev" == *"Take VETOED by this spare's own view"* && "$ev" == *"ST8 lla=0 lfv=5000 obs=$T0 oba=$((T0+60))"* \
      && "$(a8_between "$ev" "LOG [own-view] VETO")" == "local=1 batch=1 other=0 net=0" ]]; then
    ok "(13a) VOTING veto (the holder NOT delinquent in the confirmed view) → NO MUTATE, rc 1; _own_bank_active_time = the veto read (t0+60) is written BEFORE the alert (the alert-time ST8 already shows it); NO cooldown (a withdrawn verdict, not a failed take)"
else
    bad "(13a) rc=$(field "$st" rc) oba=$(field "$st" oba) ltt=$(field "$st" ltt): $ev"
fi
out=$(OVMODE=down sim_sb frozen false 0)
ev=$(evline "$out"); st=$(stline "$out")
if [[ "$ev" != *MUTATE* && "$(field "$st" rc)" == "1" && "$(field "$st" blind)" == "60" && "$(field "$st" oba)" == "0" && "$(field "$st" ltt)" == "0" \
      && "$ev" == *"it could not testify"* && "$ev" == *"oba=0 bl=$((T0+60))"* ]]; then
    ok "(13b) the veto read FAILS (rc 7) → NO MUTATE, rc 1; a BLIND veto: _last_blind_end = the read (t0+60) — the re-check's blind-abort semantics — written BEFORE the alert; no own-bank stamp, no cooldown"
else
    bad "(13b) rc=$(field "$st" rc) blind=$(field "$st" blind) oba=$(field "$st" oba): $ev"
fi
out=$(OVMODE=voting sim_sb frozen true 0)
ev=$(evline "$out")
if [[ "$ev" != *"WOULD TAKE"* && "$ev" == *"Take VETOED"* ]]; then
    ok "(13c) DRY_RUN + a VOTING veto → NO '[DRY RUN] WOULD TAKE' (the veto sits BEFORE the DRY_RUN branch: DRY_RUN mirrors the live decision)"
else
    bad "(13c) DRY_RUN did not mirror the veto: $ev"
fi
out=$(OVMODE=voting-once sim_sb frozen false 0 200)
ev=$(evline "$out"); st=$(stline "$out")
enters=$(printf '%s' "$ev" | grep -o 'TAKE-ENTER' | grep -c . )
if [[ "$enters" == "2" && "$ev" == *MUTATE* && "$(field "$st" rc)" == "0" && "$(field "$st" mutoff)" == "120" ]]; then
    ok "(13d) a VOTING veto at t0+60 (once) → the take lands at t0+120 = veto + TAKEOVER_DELAY: the own-bank stamp is an anchor input CONSUMED by the countdown (D2), two take attempts"
else
    bad "(13d) enters=$enters mutoff=$(field "$st" mutoff) rc=$(field "$st" rc): $ev"
fi
out=$(OVMODE=down sim_sb frozen false 0 2000)
ev=$(evline "$out")
vpages=$(( $(printf '%s' "$ev" | grep -o 'Take VETOED' | grep -c . ) / 2 ))
starv=$(( $(printf '%s' "$ev" | grep -o 'TAKEOVER STARVATION' | grep -c . ) / 2 ))
vetos=$(printf '%s' "$ev" | tr ';' '\n' | grep -c '^LOG \[own-view\] VETO (blind)')
echo "    veto pages=$vpages over $vetos vetoes; starvation pages=$starv"
if [[ "$ev" != *MUTATE* && "$vetos" -ge 20 && "$vpages" -ge 3 && "$vpages" -le 6 && "$starv" -ge 2 ]]; then
    ok "(13e) a veto read failing for 2000 s: NO take; $vetos vetoes, the veto page THROTTLED to $vpages (first immediate, repeats per ALERT_THROTTLE=600 — the (12) idiom) while the starvation page still fires ($starv)"
else
    bad "(13e) mutate=$([[ "$ev" == *MUTATE* ]] && echo yes || echo no) vetoes=$vetos pages=$vpages starv=$starv"
fi

# ── (14) the PRIMARY's recovery veto on ONE chain model (6.3.1 fix round 1, R6 — the panel's L5 and T8) ─────────
# (6) and (13) drive switch_to_staked's veto in a world no node can produce (tier1's finalized view calls the staked
# account NOT delinquent at lastVote 5000 while the veto's confirmed view at 800000+ calls it delinquent — L5). Here
# every view comes from ONE chain (sim_chain): tier1 NEEDS the account not-delinquent in the FINALIZED view (lastVote
# > finalized − 128) and the veto needs it delinquent in the CONFIRMED view (lastVote <= confirmed − 128; confirmed =
# finalized + 30) — so the take pass can pass only while its instant is 128 to 158 slots after the account's last
# vote: a 30-slot band (30 s at 1.0 slots/s, 12 s at 2.5, 8 s at 3.7), every earlier recovery pass inside tier1's
# window too.
echo ""; echo "─── (14) the recovery path's own-view veto on ONE chain model: the band it can pass in; a VOTING / BLIND veto re-elapses RECOVERY_DELAY ───"
W14=$(mktemp -d "${TMPDIR:-/tmp}/aa14.XXXXXX")
mutate "$PRIMARY" '/^attempt_safe_recovery() {/,/^}/s/if \[\[ \${_own_bank_active_time:-0} -gt \$recovery_anchor \]\]; then/if false; then/' "$W14/p-m12.sh"   # the panel's M12: the own-bank anchor input dropped
mutate "$PRIMARY" '/^attempt_safe_recovery() {/,/^}/s/if \[\[ [$]{_last_blind_end:-0} -gt \$recovery_anchor \]\]; then/if false; then/' "$W14/p-mblind.sh"   # the blind anchor input dropped
# fix round 2 (T5-UNPINNED — lines that survived deletion in every suite; DAV-6 — the recovery that cannot complete):
mutate "$PRIMARY" 's/^\(        \[\[ \$(( RECOVERY_DELAY - elapsed )) -le \$OWN_HEAD_H \]\] && \)_own_head_sample$/\1: deleted/' "$W14/p-notail.sh"   # the delay tail's own-head sample
mutate "$PRIMARY" 's/^        if \[\[ \$_ovv_ic -ge 1 \]\]; then$/        if false; then/' "$W14/p-nocur.sh"                                           # the veto's agave-current rule (R1)
mutate "$PRIMARY" 's/^    if \[\[ \${_own_bank_advanced:-0} -eq 1 \]\]; then$/    if false; then/' "$W14/p-nostop.sh"                                 # the R1 pass stop
mutate "$W14/p-nocur.sh" 's/^    if \[\[ \${_own_bank_advanced:-0} -eq 1 \]\]; then$/    if false; then/' "$W14/p-noboth.sh"                             # both (the all-neutered control)
mutate "$PRIMARY" 's/^    _recovery_stuck_page "\$now"   # .*$/    : stuck page removed/' "$W14/p-nostuck.sh"                                       # DAV-6's page
for _s in "$PRIMARY" "$W14/p-m12.sh" "$W14/p-mblind.sh" "$W14/p-notail.sh" "$W14/p-nocur.sh" "$W14/p-nostop.sh" "$W14/p-noboth.sh" "$W14/p-nostuck.sh"; do seam_cut "$_s" >/dev/null; done
c14() { local n="$1"; shift; ( for kv in "$@"; do export "$kv"; done; sim_chain 2>/dev/null | grep '^EVENTS=' | cut -c8- > "$W14/$n" ) & }
c14 rd10 RD=10 HZ=250; c14 rd20 RD=20 HZ=250; c14 rd40 RD=40 HZ=250; c14 rd45 RD=45 HZ=250; c14 rd50 RD=50 HZ=250
c14 def0 RATE_N=5 RATE_D=2 HZ=420; c14 sb280 RATE_N=5 RATE_D=2 TV=280 HZ=520; c14 sb280rc1 RATE_N=5 RATE_D=2 TV=280 RC=1 RI=0 HZ=520
c14 t8 RC=1 RI=0 RD=60 HZ=260; c14 t8m12 WSCRIPT="$W14/p-m12.sh" RC=1 RI=0 RD=60 HZ=260
c14 bl OVDOWN=1 RC=1 RI=0 RD=60 HZ=260; c14 blm WSCRIPT="$W14/p-mblind.sh" OVDOWN=1 RC=1 RI=0 RD=60 HZ=260
c14 tail RATE_N=4 RATE_D=5 RC=1 RI=0 RD=60 HZ=320; c14 tailn WSCRIPT="$W14/p-notail.sh" RATE_N=4 RATE_D=5 RC=1 RI=0 RD=60 HZ=320
c14 r1s RC=1 RI=0 RD=20 VOTE1=30 TLAG=45 HZ=200; c14 r1snc WSCRIPT="$W14/p-nocur.sh" RC=1 RI=0 RD=20 VOTE1=30 TLAG=45 HZ=200
c14 r1sns WSCRIPT="$W14/p-nostop.sh" RC=1 RI=0 RD=20 VOTE1=30 TLAG=45 HZ=200; c14 r1snb WSCRIPT="$W14/p-noboth.sh" RC=1 RI=0 RD=20 VOTE1=30 TLAG=45 HZ=200
c14 st10 TV=280 HZ=800; c14 st10n WSCRIPT="$W14/p-nostuck.sh" TV=280 HZ=800; c14 st0 RATE_N=5 RATE_D=2 HZ=800
wait
e14() { cat "$W14/$1" 2>/dev/null; }
mut14() { local e; e=$(e14 "$1"); e="${e#*MUTATE t=}"; [[ "$e" == "$(e14 "$1")" ]] && { echo none; return 0; }; echo "${e%%;*}"; }
after14() { local e t; e=$(e14 "$1"); for t in $(printf '%s' "$e" | tr ';' '\n' | sed -n 's/^PASS-START t=//p'); do [[ $t -gt $2 ]] && { echo "$t"; return 0; }; done; echo none; }   # the first recovery pass after t=$2
if [[ "$(mut14 rd20)" == "129" && "$(e14 rd20)" == *"CLEAR age=15 t=129"* && "$(mut14 rd40)" == "150" && "$(mut14 rd45)" == "153" \
      && "$(mut14 rd10)" == "none" && "$(e14 rd10)" == *"VETO voting t=120"* && "$(mut14 rd50)" == "none" && "$(e14 rd50)" != *"TAKE-ENTER"* ]]; then
    ok "(14a) L5 — THE BAND, measured on one chain (1.0 slots/s; the staked account last voted at t0; RECOVERY_CHECKS 3 × 30 s, CHECK_INTERVAL 3): RECOVERY_DELAY 20 / 40 / 45 → recovered at t129 / t150 / t153 (the take pass inside [t128+, t159): the veto CLEAR with a 15 s baseline — the ladder sleep's own-head samples, R3); RECOVERY_DELAY 10 → the take pass at t120 (before the band: the account still in agave's current list) → VOTING veto, never recovered by t250; RECOVERY_DELAY 50 → the take pass at t159, tier1 reads the account delinquent → never. The window is the take instant 128–158 slots after the last vote"
else
    bad "(14a) rd20=$(mut14 rd20) rd40=$(mut14 rd40) rd45=$(mut14 rd45) rd10=$(mut14 rd10) rd50=$(mut14 rd50) :: $(e14 rd10 | tr ';' '\n' | grep -v '^PASS-START' | tr '\n' ';')"
fi
if [[ "$(mut14 def0)" == "none" && "$(e14 def0)" != *"TAKE-ENTER"* && "$(mut14 sb280)" == "none" && "$(e14 sb280)" != *"TAKE-ENTER"* \
      && "$(mut14 sb280rc1)" == "342" && "$(e14 sb280rc1)" == *"CLEAR age=15 t=342"* ]]; then
    ok "(14a-def) NAMED COST (L5) — at the shipped defaults (RECOVERY_DELAY 300, RECOVERY_CHECKS 3 × 30 s, the 40 s span floor) and 2.5 slots/s, RECOVERY_MODE=rpc completes on NEITHER world: the account last voted at the demote (t0) → tier1 reads it delinquent from the first eligible pass (t300), never recovered; a spare that voted it until t280 and died → the 3-pass ladder outlasts tier1's not-delinquent window (64 s at 2.5 slots/s), never recovered. RECOVERY_CHECKS=1 → recovered at t342 (the take pass inside the 12 s band). The default RECOVERY_MODE=manual is untouched; rpc recovery needs a slow cluster (below ~1.5 slots/s with the default ladder) or one short check"
else
    bad "(14a-def) def0=$(mut14 def0) sb280=$(mut14 sb280) sb280rc1=$(mut14 sb280rc1): $(e14 sb280rc1 | tr ';' '\n' | grep -v '^PASS-START' | tr '\n' ';')"
fi
if [[ "$(e14 t8)" == *"VETO voting t=102"* && "$(after14 t8 102)" == "162" && "$(mut14 t8)" == "none" \
      && "$(e14 t8m12)" == *"VETO voting t=102"* && "$(after14 t8m12 102)" == "105" && "$(mut14 t8m12)" == "129" ]]; then
    ok "(14b) T8 — a VOTING veto on the recovery path re-elapses the full RECOVERY_DELAY (RECOVERY_CHECKS=1, RECOVERY_DELAY 60, 1.0 slots/s): the take pass at t102 reads the account in agave's current list → VOTING, the next recovery pass is at t162 = t102 + 60 (and tier1 then reads it delinquent — never recovered). NEUTER CONTROL (the panel's surviving mutant M12 — the own-bank anchor input dropped): passes resume at t105, vetoed every cycle until the account leaves the current list, and it is re-taken at t129 — 27 s after a VOTING veto"
else
    bad "(14b) shipped: next pass=$(after14 t8 102) mut=$(mut14 t8) :: M12: next pass=$(after14 t8m12 102) mut=$(mut14 t8m12)"
fi
if [[ "$(e14 bl)" == *"VETO blind t=102"* && "$(after14 bl 102)" == "162" && "$(e14 blm)" == *"VETO blind t=102"* && "$(after14 blm 102)" == "105" ]]; then
    ok "(14c) a BLIND veto on the recovery path (the veto's read fails) re-elapses the full RECOVERY_DELAY: BLIND at t102, the next recovery pass at t162 (the blind anchor, INVARIANT(blindness-is-life)); the blind anchor input dropped → passes resume at t105. The per-veto cost on this path: a full RECOVERY_DELAY (300 s shipped) + the span floor + the ladder, and on the measured worlds tier1's window closes meanwhile"
else
    bad "(14c) shipped next pass=$(after14 bl 102) :: blind-anchor-neutered next pass=$(after14 blm 102)"
fi
if [[ "$(mut14 tail)" == "174" && "$(e14 tail)" == *"VETO voting t=102"*"CLEAR age=15 t=174"* && "$(mut14 tailn)" == "174" && "$(e14 tailn)" == *"CLEAR age=12 t=174"* ]]; then
    ok "(14d) T5-UNPINNED — the delay tail's own-head samples (fix round 1, R3), which no suite needed: RECOVERY_CHECKS=1, RECOVERY_DELAY 60, 0.8 slots/s — a VOTING veto at t102 re-elapses the delay and the take pass at t174 (12 s after the re-elapsed delay: the pin's 10 s interval) finds a 15 s baseline — a delay-tail sample; deleted → 12 s (the first eligible pass's). The line's reason as fix round 1's comment gave it (a first eligible pass that is ALSO the take pass) cannot occur — the pin resets through every delay, so a take pass is >= VOTE_LIVENESS_MIN_INTERVAL after eligibility — the samples it adds still set the baseline whenever the take pass comes within OWN_HEAD_H of eligibility (the comment now says so)"
else
    bad "(14d) delay tail: shipped=$(e14 tail | tr ';' '\n' | grep -v '^PASS-START' | tr '\n' ';') :: deleted=$(e14 tailn | tr ';' '\n' | grep -v '^PASS-START' | tr '\n' ';')"
fi
if [[ "$(mut14 r1s)" == "162" && "$(e14 r1s)" == *"VETO voting t=96"*"VETO voting t=129"* && "$(e14 r1s)" != *"TAKE-ENTER t=63"* && "$(mut14 r1snc)" == "96" \
      && "$(e14 r1sns)" == *"TAKE-ENTER t=63;VETO voting t=63"* && "$(mut14 r1sns)" == "162" && "$(mut14 r1snb)" == "63" ]]; then
    ok "(14e) T5-UNPINNED — the R1 pass stop (a stamped own-bank lastVote advance ends the pass before its external reads), which no suite needed: one vote of the staked identity at t30 (VOTE1) with TIER2/TIER3 45 s behind (the fence's pinned pair sees nothing), RECOVERY_CHECKS=1, RECOVERY_DELAY 20, 1.0 slots/s: shipped → the own bank sees the rise at t62 and the pass stops; the veto's agave-current rule holds t96 and t129 (VOTING); recovered t162 (132 s after the vote). Each layer alone, and both neutered: the pass stop neutered → the t63 take pass is held by the current rule (VOTING), recovered t162; the current rule neutered → the pass stop holds t63, taken t96 (66 s after the vote); BOTH neutered → taken t63, 33 s after someone voted the staked identity"
else
    bad "(14e) R1 stop: shipped=$(e14 r1s | tr ';' '\n' | grep -v '^PASS-START' | tr '\n' ';') :: stop-neutered=$(mut14 r1sns) current-neutered=$(mut14 r1snc) both=$(mut14 r1snb)"
fi
if [[ "$(e14 st10)" == *"VETO voting t=408"*"STUCK-PAGE t=732"* && "$(mut14 st10)" == "none" && "$(e14 st10n)" != *"STUCK-PAGE"* && "$(e14 st0)" == *"STUCK-PAGE t=732"* && "$(mut14 st0)" == "none" \
      && "$(e14 rd20)" != *"STUCK-PAGE"* && "$(e14 rd10)" == *"STUCK-PAGE t=180"* && "$(e14 t8)" == *"STUCK-PAGE t=162"* ]]; then
    ok "(14f) RED FIRST (fix round 2, S5 — the delta panel's DAV-6: RECOVERY_MODE=rpc named but SILENT): a recovery that cannot complete now pages — 'eligible for Ns and NOT completing (last hold: …)' — once it is still unstaked a clean recovery's time plus one veto's delay after its first eligible pass (RECOVERY_DELAY + VOTE_LIVENESS_MIN_SPAN + RECOVERY_CHECKS × RECOVERY_CHECK_INTERVAL: 430 s at the defaults), throttled per ALERT_THROTTLE: the shipped defaults at 1.0 slots/s with the last vote at t280 (the panel's def10 — VOTING one tick before the band at t408, never recovered) → the page at t732 (the page neutered → silent, as fix round 1 was); the shipped defaults at 2.5 slots/s (tier1 reads the account delinquent from t300) → t732; RECOVERY_DELAY 10 / 60 (VOTING vetoes, never recovered) → t180 / t162; a recovery that completes (RECOVERY_DELAY 20, recovered t129) → no page. PAGE-ONLY: no decision changed"
else
    bad "(14f) DAV-6: def10=$(e14 st10 | tr ';' '\n' | grep -v '^PASS-START' | tr '\n' ';') :: neutered=$(e14 st10n | tr ';' '\n' | grep -v '^PASS-START' | tr '\n' ';') :: 2.5=$(e14 st0 | tr ';' '\n' | grep -v '^PASS-START' | tr '\n' ';') :: rd20/rd10/t8 pages: $(e14 rd20 | grep -o 'STUCK-PAGE t=[0-9]*' | head -1)/$(e14 rd10 | grep -o 'STUCK-PAGE t=[0-9]*' | head -1)/$(e14 t8 | grep -o 'STUCK-PAGE t=[0-9]*' | head -1)"
fi
rm -rf "$W14"

# ── (15) the DYNAMIC halves of the take-path and A8 censuses (6.3.1 fix round 1, R6 — the panel's T3 and T4) ─────
echo ""; echo "─── (15) every STAKED set-identity in this suite's sims followed the veto's read; no curl binary ran ───"
nmut=$(grep -c '^STAKED ' "$_MUT_AUDIT"); nbad=$(grep -v '^STAKED veto=yes between=\[\]$' "$_MUT_AUDIT" | grep -c .); ncb=$(grep -c . "$_CURLBIN_LOG")
# the controls, each a mutant standby through the REAL sim_sb (their audit and curl log kept apart from the suite's):
#   V1 — the veto call deleted from take_staked_identity: the take lands with no veto read → the audit is red
#   V2 — the panel's A1 (`command curl` to TIER3 right after the veto): the logger catches the BINARY call — a NET
#        between the veto and MUTATE, so (1e)'s census and the audit are red — and no request left the sim
W15=$(mktemp -d "${TMPDIR:-/tmp}/ata15.XXXXXX")
mkdir -p "$W15/v1" "$W15/v2"
mutate "$STANDBY" '/^take_staked_identity() {/,/^}/{/^[[:space:]]*_own_view_veto || return 1$/d;}' "$W15/v1/solana-standby-failover.sh"
awk '!d && /^[[:space:]]*_own_view_veto \|\| return 1$/ { print; print "    command curl -s -m 1 \"$TIER3_RPC\" -X POST -H \"Content-Type: application/json\" -d '"'"'{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getHealth\"}'"'"' >/dev/null 2>&1"; d = 1; next } { print }' "$STANDBY" > "$W15/v2/solana-standby-failover.sh"
v1=$(_MUT_AUDIT="$W15/v1.audit" _CURLBIN_LOG="$W15/v1.curl" STANDBY="$W15/v1/solana-standby-failover.sh" sim_sb frozen false 0)
v2=$(_MUT_AUDIT="$W15/v2.audit" _CURLBIN_LOG="$W15/v2.curl" STANDBY="$W15/v2/solana-standby-failover.sh" sim_sb frozen false 0)
v2a8=$(a8_between "$(evline "$v2")" "MUTATE")
v1a=$(cat "$W15/v1.audit" 2>/dev/null); v2a=$(cat "$W15/v2.audit" 2>/dev/null); v2c=$(grep -c . "$W15/v2.curl" 2>/dev/null)
if [[ $nmut -ge 5 && "$nbad" == "0" && "$ncb" == "0" ]] \
   && [[ "$(evline "$v1")" == *MUTATE* && "$v1a" == "STAKED veto=NO between="* ]] \
   && [[ "$(evline "$v2")" == *"NET CURLBIN"*MUTATE* && "$v2a8" == *"net=1"* && "$v2a" == *"between=[NET CURLBIN "* && "$v2c" == "1" ]]; then
    ok "(15) DYNAMIC: every STAKED set-identity in this suite's sims ($nmut) followed the veto's read with nothing but log lines between, and the logging curl first in PATH saw no curl-binary call in the whole suite; CONTROLS on the REAL sim_sb — V1 the veto call deleted: the take lands with NO veto read → red; V2 the panel's A1 (command curl to TIER3 after the veto): the logger catches it between the veto and MUTATE (A8 census: $v2a8) → red, and the one call never left the sim (before fix round 1 it reached the public cluster and (1e) stayed green) — the rule: no network, no alerts; one bounded local veto read allowed"
else
    bad "(15) suite: staked-mutates=$nmut bad=$nbad curl-binary=$ncb [$(grep -v '^STAKED veto=yes between=\[\]$' "$_MUT_AUDIT" | head -2 | tr '\n' ' ')] :: V1: $v1a :: V2: a8=$v2a8 audit=$v2a curl=$v2c"
fi
rm -rf "$W15"; rm -f "$_MUT_AUDIT" "$_CURLBIN_LOG"

results_banner
