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
#       cooldown (LAST_TAKEOVER_TIME unchanged — abort is a withdrawn verdict, not a failed take); (2i) fix round 4:
#       at VOTE_LIVENESS_EPSILON 2 a +2 advance proceeds and a +3 advance aborts VOTING; (2j) an advance whose
#       reference did not advance aborts VOTING, not stale (life signs before the tip guard); (2k) fix round 5: at
#       EPSILON 2 a stale reference, a -1 and a -2 answer and +2 on a stale reference each abort (stale / backwards)
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
#   (7) BYTE-IDENTITY: _fresh_proof_recheck identical across daemons AND to the 6.3 build's body (fix round 3,
#       U1: restored exactly — cksum pinned); (7c) its DECISION per (pinned vantage, each tier's answer), all 72
#       cells in BOTH arrival orders plus a time axis (TIER2 hanging while the holder resumes) and 256 cells at
#       VOTE_LIVENESS_EPSILON 2 (+2 / +3 advances, a stale reference, -1 / -2, +2 on a stale reference), on both daemons,
#       against the 6.3 rule (one sampler call: TIER2, TIER3 only on its failure), with three controls — both
#       tiers read at once (the serialized-vs-concurrent control), fix round 1's pinned-first order, and the first
#       line to arrive deciding (an order-dependent parse)
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
#       stop (tiers lagging: TLAG; each layer alone and both neutered); fix round 3 (U2): (14f) fix round 2's
#       recovery-stuck page REMOVED — no page in a completing recovery, none in the failed-over state (CONTVOTE);
#       fix round 4: every sender recorded (alert_warn, alert, alert_info, and — fix round 5 — the transport, send_telegram
#       and send_webhook), the failed-over worlds run one ALERT_THROTTLE
#       further (t2100), the one-shot 'ACTIVELY VOTING elsewhere' page when this node's own view misses the advance
#       (LFREEZE), and (14g) RECOVERY_MODE=manual through the main loop's real dispatch — no pass, no take
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
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=${SIM_EPS:-0}   # fix round 4: SIM_EPS (the ≤ v0.6.10 installers wrote 2)
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
              advance2)  printf '5002 %s T2\n' $(( 900000 + off )); return 0 ;;   # fix round 4 (TS3-RC-MUTANTS): +2 / +3 at SIM_EPS 2
              advance3)  printf '5003 %s T2\n' $(( 900000 + off )); return 0 ;;
              advstale)  printf '5001 900000 T2\n'; return 0 ;;                  # fix round 4: the vote advanced, the reference did NOT
              adv2stale) printf '5002 900000 T2\n'; return 0 ;;                  # fix round 5 (T4-EPS2-BRANCHES): +2 at SIM_EPS 2 with a stale reference
              backwards2) printf '4998 %s T2\n' $(( 900000 + off )); return 0 ;;  # fix round 5: -2 (within epsilon 2, still backwards)
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
# behind the chain (their every view at t − TLAG); LOCAL is never behind. CONTVOTE=1 (fix round 3, U2): the staked
# account is voted at every slot — the failed-over state, the STANDBY holding the identity. LFREEZE=<t> (fix round 4, RM-2): this node's OWN
# view (LOCAL_RPC) frozen at chain time t. DISPATCH=<mode> (fix round 4): each cycle runs the main loop's REAL RECOVERY_MODE dispatch
# with that mode instead of attempt_safe_recovery. The loop: attempt_safe_recovery every CI s (default 3);
# every sleep — the recovery ladder's, switch_to_staked's — advances the clock; LAST_SWITCH_TIME = T0.
# Events: PASS-START t= (a recovery-eligible pass), TAKE-ENTER t=, VETO <kind> t=, CLEAR age= (the veto's
# baseline age), MUTATE t=, PAGE <kind> t= (every page, through any sender — fix round 3, U2: veto | blocked (ACTIVELY VOTING
# elsewhere) | standby (STANDBY has staked) | stuck (fix round 2's removed page, by its text) | other). WSCRIPT: a mutant primary.
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
  # every page, by kind (fix round 3, U2) — through ANY sender (fix round 4, the delta panel 3's TS3-14F-SENDER: red first on the
  # removed stuck page re-added through alert and through alert_info; fix round 5, the delta panel 4's T4-14F-TRANSPORT: through
  # send_telegram directly, the way the primary's signal handler and flush_pending_alerts send): alert_warn, alert, alert_info,
  # send_telegram and send_webhook each record
  _page(){ local k=other; case "$*" in *"VETOED"*) k=veto ;; *"ACTIVELY VOTING"*) k=blocked ;; *"STANDBY has staked"*) k=standby ;; *"NOT completing"*) k=stuck ;; *"RECOVERED TO STAKED"*) k=recovered ;; esac; printf 'PAGE %s t=%s\n' "$k" $(( _SIM_NOW - T0 )) >> "$_EVT_FILE"; }
  alert_warn(){ _page "$@"; }; alert(){ _page "$@"; }; alert_info(){ _page "$@"; }; send_telegram(){ _page "$@"; return 0; }; send_webhook(){ _page "$@"; }
  save_state(){ :;}
  sleep(){ local _s="${1%%.*}"; case "$_s" in ''|*[!0-9]*) _s=0 ;; esac; _SIM_NOW=$(( _SIM_NOW + _s )); export _SIM_NOW; }
  get_local_identity(){ echo "$STAKED_PUBKEY"; }
  timeout(){ [[ "$1" == "-k" ]] && shift 2; shift; "$@"; }
  _slot(){ echo $(( 900000 + $1 * ${RATE_N:-1} / ${RATE_D:-1} )); }
  _lv_in(){   # the staked account's lastVote as a bank at slot $1 shows it
      local b=$1 v s
      s=$(_slot "${TV:-0}"); v=$(( s - 1 )); [[ "${CONTVOTE:-0}" == "1" ]] && v=$(( b - 1 ))   # CONTVOTE: voted at every slot (fix round 3, U2)
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
      [[ "$src" == LOCAL && -n "${LFREEZE:-}" && $t -gt $LFREEZE ]] && { t=$LFREEZE; h=$(_slot "$t"); }   # LFREEZE (fix round 4, RM-2 — the removals lens's knob): this node's own view frozen at LFREEZE
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
  # DISPATCH=<mode> (fix round 4 — TS3-14F-SENDER: the one knob that runs RECOVERY_MODE=manual): each cycle runs the main loop's REAL
  # UNSTAKED-branch dispatch (extracted verbatim below as _chain_dispatch) with RECOVERY_MODE=<mode>, not attempt_safe_recovery
  [[ -n "${DISPATCH:-}" ]] && { RECOVERY_MODE="$DISPATCH"; eval "_chain_dispatch() {
$_CHAIN_DISPATCH
}"; }
  while [[ $(( _SIM_NOW - T0 )) -le ${HZ:-400} ]]; do
      if [[ -n "${DISPATCH:-}" ]]; then _chain_dispatch >/dev/null 2>&1; else attempt_safe_recovery >/dev/null 2>&1; fi
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
# (2i)/(2j) fix round 4 (the delta panel 3's TS3-RC-MUTANTS — every other sim and world here runs at VOTE_LIVENESS_EPSILON 0 with
# a fresh reference): at EPSILON 2 (what the ≤ v0.6.10 installers wrote; the drift check warns about it) a +2 advance at the re-check is
# within epsilon and the take proceeds, a +3 advance is VOTING; and an advance whose reference did NOT advance is VOTING, not stale
# (the body tests life signs before the tip guard, deliberately)
out=$(SIM_EPS=2 sim_sb advance2 false 0); ev2=$(evline "$out"); st2=$(stline "$out")
out=$(SIM_EPS=2 sim_sb advance3 false 0); ev3=$(evline "$out"); st3=$(stline "$out")
if [[ "$ev2" == *MUTATE* && "$(field "$st2" rc)" == "0" && "$ev3" != *MUTATE* && "$(field "$st3" rc)" == "1" && "$(field "$st3" lla)" == "60" && "$(field "$st3" lfv)" == "5003" && "$ev3" == *"VOTED (+3 slots)"* ]]; then
    ok "(2i) VOTE_LIVENESS_EPSILON 2: +2 slots at the re-check is within epsilon → the take proceeds (MUTATE, rc 0); +3 → VOTING abort (no MUTATE, rc 1, the re-anchor at t0+60, the pair re-based to 5003, the page names +3) — a doubled epsilon would take the +3 holder"
else
    bad "(2i) EPSILON 2: +2 rc=$(field "$st2" rc) mutate=$([[ "$ev2" == *MUTATE* ]] && echo yes || echo no) :: +3 rc=$(field "$st3" rc) lla=$(field "$st3" lla) lfv=$(field "$st3" lfv) mutate=$([[ "$ev3" == *MUTATE* ]] && echo yes || echo no)"
fi
out=$(sim_sb advstale false 0); ev=$(evline "$out"); st=$(stline "$out")
if [[ "$ev" != *MUTATE* && "$(field "$st" rc)" == "1" && "$(field "$st" lla)" == "60" && "$(field "$st" lfv)" == "5001" && "$ev" == *"VOTED (+1 slots)"* && "$ev" != *"external view is stale"* ]]; then
    ok "(2j) an advanced vote with a reference that did NOT advance since the pin → VOTING abort (the re-anchor at t0+60, the pair re-based to 5001), not a stale abort — life signs before the tip guard; a VOTING that needed a fresh reference would read it stale and never re-anchor"
else
    bad "(2j) advstale: rc=$(field "$st" rc) lla=$(field "$st" lla) lfv=$(field "$st" lfv) mutate=$([[ "$ev" == *MUTATE* ]] && echo yes || echo no): $(printf '%s' "$ev" | tr ';' '\n' | grep -m2 'ABORTED' | tr '\n' ' ' | cut -c1-200)"
fi
# (2k) fix round 5 (the delta panel 4's T4-EPS2-BRANCHES — every EPSILON-2 cell before this decided only down / frozen / +2 / +3):
# at VOTE_LIVENESS_EPSILON 2 a stale reference (lastVote unchanged), a -1 and a -2 answer and +2 on a stale reference each ABORT —
# stale, backwards, backwards, stale — never within epsilon (red first on its RS1: the tip guard skipped for an advance within
# epsilon — the +2 stale answer proceeds; RB1: backwards tolerated within epsilon — -1 / -2 proceed)
k2_ok=1; k2_rows=""
for _k in "stale|external view is stale" "backwards|went backwards" "backwards2|went backwards" "adv2stale|external view is stale"; do
    out=$(SIM_EPS=2 sim_sb "${_k%%|*}" false 0); ev=$(evline "$out"); st=$(stline "$out")
    if [[ "$ev" != *MUTATE* && "$(field "$st" rc)" == "1" && "$ev" == *"${_k#*|}"* && "$(field "$st" ltt)" == "0" ]]; then k2_rows="$k2_rows ${_k%%|*}:abort"
    else k2_ok=0; k2_rows="$k2_rows ${_k%%|*}:rc=$(field "$st" rc),mutate=$([[ "$ev" == *MUTATE* ]] && echo yes || echo no)[$(printf '%s' "$ev" | tr ';' '\n' | grep -m1 'ABORTED' | cut -c1-120)]"; fi
done
if [[ $k2_ok -eq 1 ]]; then
    ok "(2k) VOTE_LIVENESS_EPSILON 2: a stale reference, a -1 and a -2 answer and +2 on a stale reference at the re-check each ABORT (stale / backwards / backwards / stale — no MUTATE, rc 1, no cooldown):$k2_rows — within epsilon is never a pass when the reference is stale or the vote went backwards"
else
    bad "(2k) EPSILON 2 abort kinds:$k2_rows"
fi

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
echo ""; echo "─── (7) _fresh_proof_recheck byte-identical in both daemons — and the 6.3 build's body, exactly ───"
extract_twin '^_fresh_proof_recheck() {' '^}$'
P_R=$TWIN_P; S_R=$TWIN_S
# 6.3.1 fix round 3 (U1 — the delta panels' DL-1, LB-1, LB-2): the body is the 6.3 build's (and the first 6.3.1
# build's), RESTORED EXACTLY — pinned by its cksum (of the function text as extracted here). Fix rounds 1 and 2 each
# changed its read order (the pinned vantage first; both tiers at once) and each lost an abort this body has; a change
# to it must re-derive the (7c) table below and the worlds that pinned the restoration (test_own_view (7f)).
RC_REF_CKSUM="2009870427 4189"
_rc_ck=$(printf '%s\n' "$S_R" | cksum | awk '{print $1" "$2}')
_rc_tr=$(cat "$STANDBY" "$PRIMARY" | grep -c '^_recheck_tier_read() {')
[[ -n "$P_R" && "$P_R" == "$S_R" && "$_rc_ck" == "$RC_REF_CKSUM" && "$_rc_tr" == "0" ]] \
    && ok "(7) _fresh_proof_recheck body BYTE-IDENTICAL in both daemons ($(printf '%s\n' "$P_R" | wc -l | tr -d ' ') lines) and to the 6.3 build's body (cksum $_rc_ck — fix round 3 restored it exactly: ONE sampler call, TIER2 then TIER3 only on its failure); fix round 2's per-tier branch _recheck_tier_read is gone from both daemons" \
    || bad "(7) _fresh_proof_recheck: twins equal=$([[ "$P_R" == "$S_R" ]] && echo yes || echo NO) cksum=$_rc_ck (want the 6.3 build's $RC_REF_CKSUM) _recheck_tier_read definitions=$_rc_tr"

# ── (7c) the re-check's DECISION: every cell, both arrival orders, and a time axis — fix round 3, U1 ──────────
# The rule is the 6.3 build's body ((7): restored exactly): ONE sampler call — TIER2, and TIER3 only when TIER2 yields
# no usable answer — and the decision on that ONE answer: advanced past the pin → VOTING; backwards → abort; from a
# tier other than the pin's → a provider flip; its reference not advanced → stale; frozen on the pinned tier →
# proceed; no answer → blind. dec_rule computes every cell from that rule (and, for the controls, from the rule with
# the other SELECTION — TIER3's answer first). The table runs BOTH daemons' real _fresh_proof_recheck over every (pin
# T2/T3 × each tier down / frozen / advanced / advanced with a stale reference / backwards / stale) cell in BOTH ARRIVAL ORDERS (the delta panel 2's
# T10-ORDER: fix round 2's table always saw TIER2's line first, so a parse that stops at the pinned answer passed
# DL-1's own cell): the shadow sampler reads TIER2 then TIER3 inside ONE call when both URLs are set, as the real one
# does, and when a caller reads ONE tier per call (a URL blanked — two concurrent branches, or one tier after the
# other) it holds that call's answer until the other tier's read has ENDED (T2FIRST: TIER3's waits for TIER2; T3FIRST:
# TIER2's waits for TIER3; bounded 5 s — a caller that never reads the other tier concurrently pays it once). And a
# TIME AXIS (the delta panel 2's T6-SERIAL and LB-1): TIER2 HANGS (no answer; read alone, its read ends only after
# TIER3's), TIER3 RESUMES (the holder's vote shows ADVANCED once TIER2's read has ended — the holder resumed during
# TIER2's timeout): the 6.3 body reads TIER3 after TIER2's failure and aborts VOTING; a re-check that reads TIER3
# before TIER2's read ends — at once, or pinned-first — decides on the frozen answer. Real waits are bounded polls of
# /bin/sleep (never `command sleep`: bash 3.2 execs a `command <utility>` in an async subshell — the delta panel 2's
# LB-4 / T10 note). CONTROLS (mutate(), loud on a no-op), each must break the table exactly where its rule differs:
#   c7c-conc   both tiers read AT ONCE with the 6.3 body's selection (TIER2's answer when it has one) — the
#              SERIALIZED-vs-CONCURRENT control: every static cell identical, exactly the time-axis RESUMES cells broken
#   c7c-r1     fix round 1's pinned-first order — exactly the pinned-TIER3 cells where TIER3's answer decides otherwise
#              (DL-1's and LB-2's among them) and the pinned-TIER3 RESUMES cell
#   c7c-first  both at once, the FIRST line to arrive decides — nothing broken when TIER2 answers first, exactly the
#              TIER3-selection cells when TIER3 answers first (a table that never varies the order passes it)
# FIX ROUND 4 (the delta panel 3's TS3-RC-MUTANTS — red first on its two decision-line mutants of the restored body, EPSILON ×2 and
# "VOTING needs a fresh reference"): the table's kinds gain ADVSTALE — the holder's vote advanced while the reference did
# NOT (VOTING must win: the body tests life signs BEFORE the tip guard, deliberately) — and an EPSILON-2 sub-table runs the same
# body at VOTE_LIVENESS_EPSILON 2 (what the ≤ v0.6.10 installers wrote) over advances of +2 (within epsilon: not VOTING) and +3
# (VOTING); every other cell runs at EPSILON 0 with a +10 advance and a fresh reference, where both mutants decide alike.
# FIX ROUND 5 (the delta panel 4's T4-EPS2-BRANCHES — red first on its RS1, the tip guard skipped for an advance within epsilon, and
# RB1, backwards tolerated within epsilon: both passed every cell here and failed only (7)'s cksum): the EPSILON-2 sub-table also
# decides a stale reference, -1, -2 and +2 on a stale reference — each an abort at epsilon 2 (stale / back / back / stale).
echo ""; echo "─── (7c) the re-check's decision: every cell in both arrival orders + the time axis, both daemons = the 6.3 rule; three controls; EPSILON 2 ───"
dec_table() {   # $1 = daemon, $2 = the orders ("T2FIRST T3FIRST HANG"), [$3 = the static kinds, $4 = VOTE_LIVENESS_EPSILON] → one line per cell: "<order> <pin> <T2 kind> <T3 kind> <rc> <outcome>"
  (
    set +e
    load_seam "$1" >/dev/null 2>&1
    harness_clock_shims; _SIM_NOW=$(( T0 + 100 ))
    log(){ :;}; log_info(){ :;}; log_error(){ :;}; _recheck_abort_alert(){ :;}; _note_blind_cycle(){ :;}
    log_warn(){ _DL="$*"; }
    VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_EPSILON=${4:-0}; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
    _DM=$(mktemp -d "${TMPDIR:-/tmp}/ata-7c.XXXXXX")
    _dwait() { local i=0; while [[ ! -e "$_DM/$1" && $i -lt 100 ]]; do /bin/sleep 0.05; i=$((i + 1)); done; }
    _dans() {   # $1 = kind, $2 = tier label → the sampler's line for that tier (nothing: down / hang)
        case "$1" in
            frozen) echo "5000 900100 $2" ;; advanced) echo "5010 900100 $2" ;; backwards) echo "4990 900100 $2" ;;
            stale) echo "5000 900000 $2" ;; advstale) echo "5010 900000 $2" ;;   # fix round 4: the vote advanced, the reference did not
            adv2) echo "5002 900100 $2" ;; adv3) echo "5003 900100 $2" ;;       # fix round 4: the EPSILON-2 sub-table's +2 / +3
            back1) echo "4999 900100 $2" ;; back2) echo "4998 900100 $2" ;; adv2stale) echo "5002 900000 $2" ;;   # fix round 5: -1 / -2 / +2 on a stale reference
            resumes) if [[ -e "$_DM/T2.done" ]]; then echo "5010 900100 $2"; else echo "5000 900100 $2"; fi ;;
            *) return 1 ;;
        esac
    }
    _dtier() {   # $1 = tier, $2 = kind, $3 = 1 when this call reads that tier ALONE (the other URL blanked)
        local _o _r
        if [[ "$3" == "1" ]]; then
            case "$1:$_DO:$2" in T2:HANG:hang|T2:T3FIRST:*) _dwait T3.done ;; T3:T2FIRST:*) _dwait T2.done ;; esac
        fi
        _o=$(_dans "$2" "$1"); _r=$?
        : > "$_DM/$1.done"
        [[ $_r -eq 0 ]] && echo "$_o"
        return $_r
    }
    get_staked_liveness_sample(){
        local _one=0; [[ -z "$TIER2_RPC" || -z "$TIER3_RPC" ]] && _one=1
        if [[ -n "$TIER2_RPC" ]] && _dtier T2 "$_DK2" "$_one"; then return 0; fi
        if [[ -n "$TIER3_RPC" ]] && _dtier T3 "$_DK3" "$_one"; then return 0; fi
        return 1
    }
    local _pin _k2 _k3 _drc _dout _k2s _k3s
    for _DO in $2; do
      case "$_DO" in HANG) _k2s="hang"; _k3s="resumes frozen" ;; *) _k2s="${3:-down frozen advanced advstale backwards stale}"; _k3s="$_k2s" ;; esac
      for _pin in T2 T3; do for _k2 in $_k2s; do for _k3 in $_k3s; do
          rm -f "$_DM/T2.done" "$_DM/T3.done"
          _liveness_first_vote=5000; _liveness_first_tip=900000; _liveness_first_provider="$_pin"; _liveness_first_ts=$T0
          _DK2="$_k2"; _DK3="$_k3"; _DL=""
          _fresh_proof_recheck >/dev/null 2>&1; _drc=$?
          case "$_DL" in
              *"staked vote ADVANCED"*) _dout=voting ;; *"provider flipped"*) _dout=flip ;; *"no usable sample"*) _dout=blind ;;
              *"did not advance"*) _dout=stale ;; *"went backwards"*) _dout=back ;; *) _dout=proceed ;;
          esac
          echo "$_DO $_pin $_k2 $_k3 $_drc $_dout"
      done; done; done
    done
    rm -rf "$_DM"
  )
}
dec_rule() {   # dec_rule <selection T2|T3> <pin> <T2 kind> <T3 kind> [<reader: SEQ|EARLY>] [<epsilon>] → "<rc> <outcome>"
    local sel="$1" pin="$2" k2="$3" k3="$4" rdr="${5:-SEQ}" eps="${6:-0}" a="" at="" d=0 tipadv=1
    [[ "$k2" == "hang" ]] && k2=down
    if [[ "$k3" == "resumes" ]]; then if [[ "$rdr" == "SEQ" ]]; then k3=advanced; else k3=frozen; fi; fi   # read after TIER2's end (the 6.3 body), or before / at once
    _duse() { case "$1" in frozen|advanced|advstale|adv2|adv3|adv2stale|backwards|back1|back2|stale) return 0 ;; *) return 1 ;; esac; }
    if [[ "$sel" == "T2" ]]; then
        if _duse "$k2"; then a=$k2; at=T2; elif _duse "$k3"; then a=$k3; at=T3; fi
    else
        if _duse "$k3"; then a=$k3; at=T3; elif _duse "$k2"; then a=$k2; at=T2; fi
    fi
    case "$a" in advanced|advstale) d=10 ;; adv2|adv2stale) d=2 ;; adv3) d=3 ;; backwards) d=-10 ;; back1) d=-1 ;; back2) d=-2 ;; esac   # the answer's vote against the pin (5000)
    case "$a" in stale|advstale|adv2stale) tipadv=0 ;; esac                                     # its reference not advanced since the pin
    if [[ -z "$a" ]]; then echo "1 blind"
    elif [[ $d -gt $eps ]]; then echo "1 voting"                  # life signs first — before the tip guard (the body's order)
    elif [[ $d -lt 0 ]]; then echo "1 back"
    elif [[ "$at" != "$pin" ]]; then echo "1 flip"
    elif [[ $tipadv -eq 0 ]]; then echo "1 stale"
    else echo "0 proceed"; fi
}
_d7c_conc=$(mktemp "${TMPDIR:-/tmp}/ata-7c-conc.XXXXXX"); _d7c_r1=$(mktemp "${TMPDIR:-/tmp}/ata-7c-r1.XXXXXX"); _d7c_first=$(mktemp "${TMPDIR:-/tmp}/ata-7c-first.XXXXXX")
RC_LINE='/^_fresh_proof_recheck() {/,/^}/s/^    s=\$(get_staked_liveness_sample) || s=""$/'
mutate "$STANDBY" "${RC_LINE}    s=\$( { TIER3_RPC=\"\" get_staked_liveness_sample \& TIER2_RPC=\"\" get_staked_liveness_sample \& wait; } | sort -k3,3 | head -1) || s=\"\"/" "$_d7c_conc"
mutate "$STANDBY" "${RC_LINE}    s=\$( { TIER3_RPC=\"\" get_staked_liveness_sample \& TIER2_RPC=\"\" get_staked_liveness_sample \& wait; } | head -1) || s=\"\"/" "$_d7c_first"
# fix round 1's order, the triple's name spliced in by @LFP@ (run_all's stage (3): no suite dereferences it in its text)
_d7c_r1_sed=$(cat <<'EOS'
/^_fresh_proof_recheck() {/,/^}/s/^    s=\$(get_staked_liveness_sample) || s=""$/    if [[ "${@LFP@:-}" == "T3" \&\& -n "$TIER2_RPC" \&\& -n "$TIER3_RPC" \&\& "$TIER2_RPC" != "$TIER3_RPC" ]]; then s=$(TIER2_RPC="" get_staked_liveness_sample) || s=$(TIER3_RPC="" get_staked_liveness_sample) || s=""; else s=$(get_staked_liveness_sample) || s=""; fi/
EOS
)
mutate "$STANDBY" "${_d7c_r1_sed//@LFP@/_liveness_first_provider}" "$_d7c_r1"
_tp=$(dec_table "$PRIMARY" "T2FIRST T3FIRST HANG"); _ts=$(dec_table "$STANDBY" "T2FIRST T3FIRST HANG")
_te2p=$(dec_table "$PRIMARY" "T2FIRST T3FIRST" "down frozen adv2 adv3 stale back1 back2 adv2stale" 2); _te2s=$(dec_table "$STANDBY" "T2FIRST T3FIRST" "down frozen adv2 adv3 stale back1 back2 adv2stale" 2)   # fix round 4: EPSILON 2 (fix round 5: + stale, -1, -2, +2 stale)
_tc=$(dec_table "$_d7c_conc" "T3FIRST HANG"); _tr1=$(dec_table "$_d7c_r1" "T3FIRST HANG"); _tf=$(dec_table "$_d7c_first" "T2FIRST T3FIRST")
rm -f "$_d7c_conc" "$_d7c_r1" "$_d7c_first"
dec_ok=1; dec_diff=""; dec_n=0; conc_bad=""; r1_bad=""; first_bad=""; conc_want=""; r1_want=""; first_want=""
while read -r _o _pin _k2 _k3 _rc _out; do
    [[ -n "$_o" ]] || continue
    dec_n=$((dec_n + 1))
    _w=$(dec_rule T2 "$_pin" "$_k2" "$_k3" SEQ)
    [[ "$_rc $_out" == "$_w" ]] || { dec_ok=0; dec_diff="$dec_diff [standby $_o pin $_pin T2=$_k2 T3=$_k3: '$_rc $_out' want '$_w']"; }
done <<< "$_ts"
[[ "$_tp" == "$_ts" ]] || { dec_ok=0; dec_diff="$dec_diff [primary's table differs from the standby's: $(diff <(printf '%s\n' "$_ts") <(printf '%s\n' "$_tp") | grep '^[<>]' | head -4 | tr '\n' ' ')]"; }
# each control's broken cells, and the cells its rule says it must break
while read -r _o _pin _k2 _k3 _rc _out; do
    [[ -n "$_o" ]] || continue
    [[ "$_rc $_out" == "$(dec_rule T2 "$_pin" "$_k2" "$_k3" SEQ)" ]] || conc_bad="$conc_bad $_o:$_pin:$_k2/$_k3"
    [[ "$(dec_rule T2 "$_pin" "$_k2" "$_k3" EARLY)" == "$(dec_rule T2 "$_pin" "$_k2" "$_k3" SEQ)" ]] || conc_want="$conc_want $_o:$_pin:$_k2/$_k3"
done <<< "$_tc"
while read -r _o _pin _k2 _k3 _rc _out; do
    [[ -n "$_o" ]] || continue
    [[ "$_rc $_out" == "$(dec_rule T2 "$_pin" "$_k2" "$_k3" SEQ)" ]] || r1_bad="$r1_bad $_o:$_pin:$_k2/$_k3"
    if [[ "$_pin" == "T3" ]]; then [[ "$(dec_rule T3 "$_pin" "$_k2" "$_k3" EARLY)" == "$(dec_rule T2 "$_pin" "$_k2" "$_k3" SEQ)" ]] || r1_want="$r1_want $_o:$_pin:$_k2/$_k3"; fi
done <<< "$_tr1"
while read -r _o _pin _k2 _k3 _rc _out; do
    [[ -n "$_o" ]] || continue
    [[ "$_rc $_out" == "$(dec_rule T2 "$_pin" "$_k2" "$_k3" SEQ)" ]] || first_bad="$first_bad $_o:$_pin:$_k2/$_k3"
    _sel=T2; [[ "$_o" == "T3FIRST" ]] && _sel=T3
    [[ "$(dec_rule "$_sel" "$_pin" "$_k2" "$_k3" EARLY)" == "$(dec_rule T2 "$_pin" "$_k2" "$_k3" SEQ)" ]] || first_want="$first_want $_o:$_pin:$_k2/$_k3"
done <<< "$_tf"
_nc=$(printf '%s' "$conc_bad" | wc -w | tr -d ' '); _nr=$(printf '%s' "$r1_bad" | wc -w | tr -d ' '); _nf=$(printf '%s' "$first_bad" | wc -w | tr -d ' ')
# fix round 4 (TS3-RC-MUTANTS): the EPSILON-2 sub-table against the same rule at epsilon 2, both daemons alike; and the cells that make
# each new kind bite — ADVSTALE → VOTING (a mutant that asks for a fresh reference before VOTING reads it stale), +2 within epsilon
# 2 → proceed and +3 → VOTING (a mutant that doubles epsilon proceeds on +3)
e2_ok=1; e2_n=0; e2_diff=""
while read -r _o _pin _k2 _k3 _rc _out; do
    [[ -n "$_o" ]] || continue
    e2_n=$((e2_n + 1))
    _w=$(dec_rule T2 "$_pin" "$_k2" "$_k3" SEQ 2)
    [[ "$_rc $_out" == "$_w" ]] || { e2_ok=0; e2_diff="$e2_diff [standby EPSILON 2 $_o pin $_pin T2=$_k2 T3=$_k3: '$_rc $_out' want '$_w']"; }
done <<< "$_te2s"
[[ "$_te2p" == "$_te2s" ]] || { e2_ok=0; e2_diff="$e2_diff [primary's EPSILON-2 table differs from the standby's: $(diff <(printf '%s\n' "$_te2s") <(printf '%s\n' "$_te2p") | grep '^[<>]' | head -4 | tr '\n' ' ')]"; }
_bite=$(printf '%s\n' "$_ts" | grep -c '^T2FIRST T2 advstale down 1 voting$'; printf '%s\n' "$_te2s" | grep -c '^T2FIRST T2 adv2 down 0 proceed$'; printf '%s\n' "$_te2s" | grep -c '^T2FIRST T2 adv3 down 1 voting$'; printf '%s\n' "$_te2s" | grep -c '^T3FIRST T3 down adv3 1 voting$'
       printf '%s\n' "$_te2s" | grep -c '^T2FIRST T2 stale down 1 stale$'; printf '%s\n' "$_te2s" | grep -c '^T2FIRST T2 back1 down 1 back$'; printf '%s\n' "$_te2s" | grep -c '^T2FIRST T2 back2 down 1 back$'; printf '%s\n' "$_te2s" | grep -c '^T2FIRST T2 adv2stale down 1 stale$')
_bite=$(printf '%s' "$_bite" | tr -d '\n')
if [[ $dec_ok -eq 1 && $dec_n -eq 148 && $e2_ok -eq 1 && $e2_n -eq 256 && "$_bite" == "11111111" && -n "$conc_bad" && "$conc_bad" == "$conc_want" && "$conc_bad" == " HANG:T2:hang/resumes HANG:T3:hang/resumes" \
      && -n "$r1_bad" && "$r1_bad" == "$r1_want" && " $r1_bad " == *" T3FIRST:T3:advanced/frozen "* && " $r1_bad " == *" T3FIRST:T3:frozen/frozen "* && " $r1_bad " == *" HANG:T3:hang/resumes "* \
      && -n "$first_bad" && "$first_bad" == "$first_want" && "$first_bad" != *"T2FIRST"* && " $first_bad " == *" T3FIRST:T3:advanced/frozen "* ]]; then
    ok "(7c) the re-check's DECISION, all $dec_n cells on BOTH daemons' real _fresh_proof_recheck — the 72 (pin T2/T3 × each tier down / frozen / advanced / advanced with a stale reference / backwards / stale) in BOTH arrival orders and the 4 time-axis cells — = the 6.3 rule (TIER2's answer, TIER3 only when TIER2 has none; advanced → VOTING, before the tip guard, so an advance with a stale reference is VOTING too; backwards → abort, another tier than the pin's → a flip, a stale reference → abort, frozen on the pin → proceed, none → blind), and at VOTE_LIVENESS_EPSILON 2 (the ≤ v0.6.10 installers' value) the $e2_n cells over down / frozen / +2 / +3 / stale / −1 / −2 / +2 on a stale reference = the same rule at epsilon 2 (+2 within it: proceeds on the pin; +3 → VOTING; a stale reference → stale, −1 / −2 → backwards, +2 on a stale reference → stale — fix round 5, the delta panel 4's T4-EPS2-BRANCHES) — fix round 4 (the delta panel 3's TS3-RC-MUTANTS: every earlier cell ran at epsilon 0 with a fresh reference, so a doubled epsilon and a VOTING that needs a fresh reference both passed): a TIER2 that recovered and shows the vote ADVANCED aborts VOTING in every order (DL-1), a recovered TIER2 answering frozen / backwards / stale aborts (a flip / back / flip — LB-2), and TIER2 HANGING while the holder resumes → TIER3 read after the timeout → VOTING (LB-1). CONTROLS, each broken exactly where its own rule differs: both tiers read AT ONCE with the 6.3 selection ($_nc cells:$conc_bad — the serialized-vs-concurrent control, every static cell identical: T6-SERIAL's cell); fix round 1's pinned-first order ($_nr cells, all pinned on TIER3 — DL-1's T2=advanced/T3=frozen and LB-2's frozen/frozen among them); the FIRST line to arrive deciding ($_nf cells, every one in the TIER3-first order and none when TIER2 answers first — T10-ORDER: a table that never varies the order passes it)"
else
    bad "(7c) re-check decision table (cells=$dec_n; EPSILON 2 cells=$e2_n, the bite cells advstale/+2/+3/+3/stale/-1/-2/+2stale=$_bite want 11111111):$dec_diff$e2_diff | controls: conc=[$conc_bad] (want [$conc_want]) r1=[$r1_bad] (want [$r1_want]) first=[$first_bad] (want [$first_want])"
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
# fix round 2 (T5-UNPINNED — lines that survived deletion in every suite):
mutate "$PRIMARY" 's/^\(        \[\[ \$(( RECOVERY_DELAY - elapsed )) -le \$OWN_HEAD_H \]\] && \)_own_head_sample$/\1: deleted/' "$W14/p-notail.sh"   # the delay tail's own-head sample
mutate "$PRIMARY" 's/^        if \[\[ \$_ovv_ic -ge 1 \]\]; then$/        if false; then/' "$W14/p-nocur.sh"                                           # the veto's agave-current rule (R1)
mutate "$PRIMARY" 's/^    if \[\[ \${_own_bank_advanced:-0} -eq 1 \]\]; then$/    if false; then/' "$W14/p-nostop.sh"                                 # the R1 pass stop
mutate "$W14/p-nocur.sh" 's/^    if \[\[ \${_own_bank_advanced:-0} -eq 1 \]\]; then$/    if false; then/' "$W14/p-noboth.sh"                             # both (the all-neutered control)
for _s in "$PRIMARY" "$W14/p-m12.sh" "$W14/p-mblind.sh" "$W14/p-notail.sh" "$W14/p-nocur.sh" "$W14/p-nostop.sh" "$W14/p-noboth.sh"; do seam_cut "$_s" >/dev/null; done
# the main loop's UNSTAKED-branch RECOVERY_MODE dispatch, verbatim (fix round 4 — (14g) runs it; loud when the anchor moves)
_CHAIN_DISPATCH=$(extract_region "$PRIMARY" '^        if \[\[ "\$RECOVERY_MODE" == "manual" \]\]; then$' '^        fi$') || bad "(14g) harness: the RECOVERY_MODE dispatch region was not found in the primary"
export _CHAIN_DISPATCH
c14() { local n="$1"; shift; ( for kv in "$@"; do export "$kv"; done; sim_chain 2>/dev/null | grep '^EVENTS=' | cut -c8- > "$W14/$n" ) & }
c14 rd10 RD=10 HZ=250; c14 rd20 RD=20 HZ=250; c14 rd40 RD=40 HZ=250; c14 rd45 RD=45 HZ=250; c14 rd50 RD=50 HZ=250
c14 def0 RATE_N=5 RATE_D=2 HZ=420; c14 sb280 RATE_N=5 RATE_D=2 TV=280 HZ=520; c14 sb280rc1 RATE_N=5 RATE_D=2 TV=280 RC=1 RI=0 HZ=520
c14 t8 RC=1 RI=0 RD=60 HZ=260; c14 t8m12 WSCRIPT="$W14/p-m12.sh" RC=1 RI=0 RD=60 HZ=260
c14 bl OVDOWN=1 RC=1 RI=0 RD=60 HZ=260; c14 blm WSCRIPT="$W14/p-mblind.sh" OVDOWN=1 RC=1 RI=0 RD=60 HZ=260
c14 tail RATE_N=4 RATE_D=5 RC=1 RI=0 RD=60 HZ=320; c14 tailn WSCRIPT="$W14/p-notail.sh" RATE_N=4 RATE_D=5 RC=1 RI=0 RD=60 HZ=320
c14 r1s RC=1 RI=0 RD=20 VOTE1=30 TLAG=45 HZ=200; c14 r1snc WSCRIPT="$W14/p-nocur.sh" RC=1 RI=0 RD=20 VOTE1=30 TLAG=45 HZ=200
c14 r1sns WSCRIPT="$W14/p-nostop.sh" RC=1 RI=0 RD=20 VOTE1=30 TLAG=45 HZ=200; c14 r1snb WSCRIPT="$W14/p-noboth.sh" RC=1 RI=0 RD=20 VOTE1=30 TLAG=45 HZ=200
c14 st10 TV=280 HZ=800; c14 st0 RATE_N=5 RATE_D=2 HZ=800; c14 fo25 RATE_N=5 RATE_D=2 CONTVOTE=1 HZ=2100; c14 fo10 CONTVOTE=1 HZ=2100
c14 man20 DISPATCH=manual RD=20 HZ=400; c14 manfo DISPATCH=manual RATE_N=5 RATE_D=2 CONTVOTE=1 HZ=700; c14 disp20 DISPATCH=rpc RD=20 HZ=250   # fix round 4: (14g)
c14 fofz RATE_N=5 RATE_D=2 CONTVOTE=1 LFREEZE=250 HZ=700   # fix round 4 (RM-2): the failed-over state with this node's own view frozen at t250
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
# (14f) fix round 3 (U2 — the delta panel 2's AV2-4 / AV2-5 / CKB-5): fix round 2's recovery-stuck page is REMOVED. It
# paged recoveries that then complete — this section's own (14d) (paged t162, recovered t174) and (14e) (paged t81,
# recovered t162) — and, every ALERT_THROTTLE forever, the ordinary failed-over state (the STANDBY holding and voting
# the staked identity: t732, t1332, …). What stands is fix round 1's behavior, named in docs/SAFETY.md: an rpc recovery
# the veto band keeps from completing is not paged beyond its veto's own throttled page, and in the failed-over state
# the pass ends at the own bank's lastVote advance (R1) before the fence, so the 6.3 build's one-shot 'ACTIVELY VOTING
# elsewhere' page (t312) is not sent either. RECOVERY_MODE=manual (the default) runs none of this.
_nostuck=1; for _w in rd10 rd20 rd40 rd45 rd50 def0 sb280 sb280rc1 t8 bl tail r1s st10 st0 fo25 fo10 fofz man20 manfo disp20; do [[ "$(e14 "$_w")" == *"PAGE stuck"* ]] && _nostuck=0; done
_pg() { e14 "$1" | tr ';' '\n' | grep '^PAGE ' | tr '\n' ';'; }
if [[ $_nostuck -eq 1 && "$(grep -c 'NOT completing\|_recovery_stuck_page' "$PRIMARY")" == "0" \
      && "$(mut14 tail)" == "174" && "$(mut14 r1s)" == "162" && "$(_pg tail)" != *"PAGE stuck"* \
      && "$(mut14 st10)" == "none" && "$(e14 st10)" == *"VETO voting t=408"* && "$(_pg st10)" == "PAGE veto t=408;" && "$(mut14 st0)" == "none" && -z "$(_pg st0)" \
      && "$(mut14 fo25)" == "none" && -z "$(_pg fo25)" && "$(mut14 fo10)" == "none" && -z "$(_pg fo10)" \
      && "$(mut14 fofz)" == "none" && "$(_pg fofz)" == "PAGE blocked t=312;" ]]; then
    ok "(14f) fix round 3 (U2 — the delta panel 2's AV2-4/AV2-5/CKB-5): fix round 2's recovery-stuck page is REMOVED (its text and function are gone from the primary) — it paged (14d)'s recovery at t162 before it completed at t174, (14e)'s at t81 before t162, and the failed-over state at t732 and every ALERT_THROTTLE after; now no world here pages 'NOT completing': (14d) recovered t174 and (14e) t162 with no such page; the RECOVERY_MODE=rpc residual stands as fix round 1 left it and is named in docs/SAFETY.md — the defaults at 1.0 slots/s with the last vote at t280 read VOTING at t408 (one tick before the band) and never recover by t800 (its one page: the veto's own at t408), and at 2.5 slots/s tier1 reads the account delinquent from t300 — never recovered, no page; the FAILED-OVER state (CONTVOTE — the STANDBY voting the identity) at 2.5 and 1.0 slots/s: never re-taken and NO page by t2100 — one ALERT_THROTTLE past the removed page's second firing, every sender recorded (alert_warn, alert, alert_info — fix round 4, the delta panel 3's TS3-14F-SENDER — and the transport, send_telegram and send_webhook — fix round 5, the delta panel 4's T4-14F-TRANSPORT) — the 6.3 build's one-shot 'ACTIVELY VOTING elsewhere' page (t312) is not sent while this node's own bank sees the STANDBY voting: the own bank's advance ends the pass first (fix round 1's R1, named); with this node's own view frozen at t250 (it misses the advance) the pass reaches the fence and that page fires once, at t312. RECOVERY_MODE=manual, the default, runs none of this ((14g))"
else
    bad "(14f) U2: stuck-page text/function sites=$(grep -c 'NOT completing\|_recovery_stuck_page' "$PRIMARY") no-stuck-page=$_nostuck :: tail=$(mut14 tail) $(_pg tail) :: r1s=$(mut14 r1s) :: def10=$(mut14 st10) [$(_pg st10)] :: 2.5=$(mut14 st0) [$(_pg st0)] :: failed-over 2.5=$(mut14 fo25) [$(_pg fo25)] 1.0=$(mut14 fo10) [$(_pg fo10)] :: own view frozen=$(mut14 fofz) [$(_pg fofz)]"
fi
# (14g) fix round 4 (the delta panel 3's TS3-14F-SENDER — every other sim_chain world calls attempt_safe_recovery directly, so none runs
# RECOVERY_MODE=manual): the main loop's REAL UNSTAKED-branch dispatch (extracted
# verbatim) under RECOVERY_MODE=manual — the rd20 world that rpc recovers at t129, and the failed-over state — never enters a recovery
# pass and never re-takes; the control, the same dispatch under RECOVERY_MODE=rpc, recovers at t129 (the dispatch reaches the path)
if [[ -n "$_CHAIN_DISPATCH" && "$(mut14 man20)" == "none" && "$(e14 man20)" != *"PASS-START"* && "$(e14 man20)" != *"TAKE-ENTER"* && -z "$(_pg man20)" \
      && "$(mut14 manfo)" == "none" && "$(e14 manfo)" != *"PASS-START"* && -z "$(_pg manfo)" && "$(mut14 disp20)" == "129" && "$(mut14 rd20)" == "129" ]]; then
    ok "(14g) RECOVERY_MODE=manual (the default) through the main loop's REAL recovery dispatch: no recovery pass, no take, no page — in the world rpc recovers at t129 (horizon t400) and in the failed-over state (t700); control: the same dispatch under RECOVERY_MODE=rpc recovers at t129, as the direct call does"
else
    bad "(14g) manual dispatch: man20=$(mut14 man20) passes=$(e14 man20 | tr ';' '\n' | grep -c '^PASS-START') [$(_pg man20)] :: manfo=$(mut14 manfo) [$(_pg manfo)] :: rpc control=$(mut14 disp20) direct=$(mut14 rd20) :: region=${#_CHAIN_DISPATCH}B"
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
