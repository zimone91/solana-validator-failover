#!/bin/bash
# v0.7 (Block 3, slice-4 rework): TAKEOVER STARVATION PAGE. A starving episode is SILENT: every
# hold path that moves the anchor (blindness re-anchor, provider flip, span-floor hold) keeps
# elapsed < TAKEOVER_DELAY, and the delay-branch early return in attempt_takeover fires BEFORE the
# single alert_warn in the fence_reason block. MEASURED (reviewer, 2026-08-17): dead holder + both
# externals blinking one cycle every <=55s = NO take in an hour and ZERO pages. The fix pages —
# _maybe_starvation_page, called as the FIRST statement of attempt_takeover, held-time measured
# from FIRST_DELINQUENT_TIME (NEVER takeover_anchor — the anchor is exactly what starvation moves),
# repeating per ALERT_THROTTLE, page-only. Standby-only by design (the primary's recovery path
# legitimately holds forever post-failover under manual switch-back).
#
# Drives the REAL shipped attempt_takeover (source-to-MAIN-LOOP seam of the STANDBY daemon, the
# test_blindness_is_life sim idiom: mono_now/date shims, alert shadows, controllable mocks).
# Blinking externals: BOTH observation channels down for exactly one cycle every 50s
# (_EXT_UP=0 iff off % 50 == 0), dead holder, single provider T2, FIRST_DELINQUENT_TIME=T0,
# ALERT_THROTTLE=600, attempt_takeover driven once per simulated second.
#   (1) THE MEASURED SILENCE: no take over 3600s (took=-1) AND starvation pages at exactly
#       t0+300, +900, +1500, +2100, +2700, +3300 (6 pages, first at +300), each carrying the
#       episode counters ("blind cycles=").
#   (2) NOT LATCHED: preset _takeover_alert_sent=1 → the t0+300 page still fires (the fence
#       latch covers the one-shot fence alert; starvation must keep paging).
#   (3) INDEPENDENCE: over the same run as (1) the fence alert ("Delinquent but fence not clear")
#       fires at most once (its latch) while starvation pages keep repeating — two separate latches.
#   (4) RESOLUTION: after >=1 page, externals recover and confirm_delinquency_external returns 1
#       (false positive) → attempt_takeover calls window_reset → exactly one alert_info containing
#       "starvation over", _starvation_paged cleared, _last_starvation_alert=0. The main-loop
#       delinquency-cleared branch ALSO calls _starvation_note_close, but that branch lives BELOW
#       the source-to-seam cut and cannot be driven here — asserted by static grep instead.
#   (5) PERMANENT REVERT-CONTROL: same scenario as (1) with _maybe_starvation_page(){ :; } shadowed
#       → 0 pages — documents the parent's measured silence and proves (1)'s assertions bite.
#   (6) KNOB OFF: TAKEOVER_STARVATION_ALERT_SECS=0 → 0 pages. Drift announcer: value 0 announces
#       DISABLES, value 600 announces laxer-than-default, default 300 announces nothing.

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$STANDBY" ]] || { echo "  ❌ script not found"; exit 1; }

T0=100000            # mono origin (never 0 — 0 collides with the "unset" sentinel)
DELAY=60             # TAKEOVER_DELAY under test (the shipped default)

# ── sim: run the REAL attempt_takeover over a timeline with blinking externals ──────────────────
#   $1 = horizon (seconds)
#   $2 = blink stop: blinking (one blind cycle every 50s) applies only while off <= this; -1 = forever
#   $3 = false-positive start: confirm_delinquency_external returns 1 from this off on; -1 = never
#   $4 = preset _takeover_alert_sent=1 before the run (0/1)
#   $5 = neuter _maybe_starvation_page (0/1) — the pre-rework parent's silence
#   $6 = TAKEOVER_STARVATION_ALERT_SECS override ("" = shipped default)
# Echoes: "<took|-1>|<page offsets>|<fence_count>|<resolve_count>|<paged|EMPTY>|<lastal|NA>|<text_ok>"
sim() {
  local horizon="$1" blinkstop="$2" fpfrom="$3" latched="$4" neuter="$5" knob="$6"
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  STAKED_PUBKEY="S1"; VOTE_PUBKEY="V1"
  TAKEOVER_DELAY=$DELAY; TAKEOVER_COOLDOWN=0; EXTERNAL_CONFIRM_THROTTLE=0
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=10; VOTE_LIVENESS_EPSILON=0
  GOSSIP_VERIFY=false; DRY_RUN=false; WITNESS_FASTPATH=false
  ALERT_THROTTLE=600
  [[ -n "$knob" ]] && TAKEOVER_STARVATION_ALERT_SECS="$knob"
  date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
  mono_now() { echo "$_SIM_NOW"; }
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}
  alert(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  save_state(){ :;}
  _starv_offs=""; _fence_count=0; _resolve_count=0; _text_ok=1
  alert_warn(){
      case "$*" in
          *"TAKEOVER STARVATION"*)
              _starv_offs="$_starv_offs $(( _SIM_NOW - T0 ))"
              case "$*" in *"blind cycles="*) : ;; *) _text_ok=0 ;; esac ;;
          *"Delinquent but fence not clear"*) _fence_count=$((_fence_count+1)) ;;
      esac
  }
  alert_info(){ case "$*" in *"starvation over"*) _resolve_count=$((_resolve_count+1)) ;; esac; }
  # External world: ONE switch controls both observation channels (both-tiers-down blindness).
  _EXT_UP=1
  confirm_delinquency_external(){
      [[ "$_EXT_UP" == "1" ]] || return 2
      [[ $fpfrom -ge 0 && $(( _SIM_NOW - T0 )) -ge $fpfrom ]] && return 1
      return 0
  }
  get_staked_liveness_sample(){      # dead holder, single vantage T2, cluster tip advances 1/s
      [[ "$_EXT_UP" == "1" ]] || return 1
      printf '%s %s %s\n' "5000" "$(( 900000 + _SIM_NOW - T0 ))" "T2"
  }
  [[ "$neuter" == "1" ]] && _maybe_starvation_page(){ :; }   # the pre-rework parent: no page path at all
  FIRST_DELINQUENT_TIME=$T0; LAST_TAKEOVER_TIME=0; _last_confirm_attempt=0
  LAST_LIVENESS_ACTIVE_TIME=0; SELF_FENCE_DEMOTE_TIME=0
  _delinq_window="1111111111"; _turbo_mode=true; _gossip_prefetched=false
  _takeover_alert_sent=""; [[ "$latched" == "1" ]] && _takeover_alert_sent=1
  _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
  _last_blind_end=0
  _took=-1; take_staked_identity(){ _took=$(( _SIM_NOW - T0 )); return 0; }
  local t off
  for ((t=0; t<=horizon; t++)); do
      _SIM_NOW=$(( T0 + t )); off=$t
      _EXT_UP=1
      if [[ $(( off % 50 )) -eq 0 ]]; then
          if [[ $blinkstop -lt 0 || $off -le $blinkstop ]]; then _EXT_UP=0; fi
      fi
      attempt_takeover >/dev/null 2>&1
      [[ $_took -ge 0 ]] && break
  done
  echo "${_took}|${_starv_offs}|${_fence_count}|${_resolve_count}|${_starvation_paged:-EMPTY}|${_last_starvation_alert:-NA}|${_text_ok}"
  )
}

# ── drift-announcer probe (as in test_blindness_is_life / test_config_drift) ────────────────────
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
echo "  Takeover starvation page (v0.7 Block 3 slice-4 rework)"
echo "============================================="

# ── (1)+(3) the measured silence scenario: blink forever, 3600s ─────────────────────────────────
echo ""; echo "─── (1) blink 1 cycle/50s over a dead holder, 3600s: no take, pages every ALERT_THROTTLE ───"
_simout=$(sim 3600 -1 -1 0 0 '')   # captured FIRST: a here-string $(…) would run the sourced daemon under IFS='|'
IFS='|' read -r R_TOOK R_OFFS R_FENCE R_RESOLVE R_PAGED R_LASTAL R_TEXT <<<"$_simout"
echo "    took=${R_TOOK} pages=[${R_OFFS} ] fence_alerts=${R_FENCE}"
[[ "$R_TOOK" == "-1" ]] \
    && ok "(1a) NO take over 3600s — the anchor moves every blink (elapsed never reaches TAKEOVER_DELAY)" \
    || bad "(1a) took t0+${R_TOOK}s — the scenario no longer starves the takeover"
[[ "$R_OFFS" == " 300 900 1500 2100 2700 3300" ]] \
    && ok "(1b) starvation pages at exactly t0+300, +900, +1500, +2100, +2700, +3300 (6 pages; first at threshold, then per ALERT_THROTTLE)" \
    || bad "(1b) page offsets [${R_OFFS} ] (want [ 300 900 1500 2100 2700 3300]) — the silence is not paged as specified"
[[ "$R_TEXT" == "1" && -n "$R_OFFS" ]] \
    && ok "(1c) every page carries the episode counters ('blind cycles=...')" \
    || bad "(1c) a page was missing the episode counters (text_ok=${R_TEXT}, offs=[${R_OFFS} ])"

# ── (2) not gated by the fence-alert latch ──────────────────────────────────────────────────────
echo ""; echo "─── (2) _takeover_alert_sent preset to 1: the starvation page still fires ───"
_simout=$(sim 350 -1 -1 1 0 '')   # captured FIRST: a here-string $(…) would run the sourced daemon under IFS='|'
IFS='|' read -r L_TOOK L_OFFS _ _ _ _ _ <<<"$_simout"
[[ "$L_OFFS" == " 300" ]] \
    && ok "(2) with the fence latch preset, the t0+300 page still fires — starvation is NOT gated by _takeover_alert_sent" \
    || bad "(2) preset latch suppressed/moved the page (offs=[${L_OFFS} ], want [ 300])"

# ── (3) independence of the two latches (same run as (1)) ───────────────────────────────────────
echo ""; echo "─── (3) fence alert at most once while starvation repeats (two separate latches) ───"
[[ "$R_FENCE" -le 1 ]] \
    && ok "(3) fence alert fired ${R_FENCE}x (<=1, its one-shot latch) while starvation paged 6x — separate latches" \
    || bad "(3) fence alert fired ${R_FENCE}x (>1) — the fence latch broke"

# ── (4) resolution: false positive ends the episode via window_reset ────────────────────────────
echo ""; echo "─── (4) after a page, externals recover + confirm says NOT delinquent → resolution notice ───"
_simout=$(sim 450 350 400 0 0 '')   # captured FIRST: a here-string $(…) would run the sourced daemon under IFS='|'
IFS='|' read -r S_TOOK S_OFFS _ S_RESOLVE S_PAGED S_LASTAL _ <<<"$_simout"
echo "    took=${S_TOOK} pages=[${S_OFFS} ] resolve_notices=${S_RESOLVE} paged='${S_PAGED}' last_alert=${S_LASTAL}"
[[ "$S_RESOLVE" == "1" && "$S_OFFS" == " 300" ]] \
    && ok "(4a) exactly one 'starvation over' alert_info after the false-positive window_reset (paged once at t0+300 first)" \
    || bad "(4a) resolve notices=${S_RESOLVE} (want 1) / pages=[${S_OFFS} ] (want [ 300])"
[[ "$S_PAGED" == "EMPTY" && "$S_LASTAL" == "0" ]] \
    && ok "(4b) _starvation_paged cleared and _last_starvation_alert=0 after the close" \
    || bad "(4b) paging state not cleared (paged='${S_PAGED}', last_alert=${S_LASTAL})"
# The main-loop delinquency-cleared branch is BELOW the source-to-seam cut and cannot be driven
# here — assert statically that it calls _starvation_note_close before its inline resets.
sed -n '/MAIN LOOP/,$p' "$STANDBY" | grep -q '_starvation_note_close "delinquency cleared"' \
    && ok "(4c) main-loop delinquency-cleared branch calls _starvation_note_close (static: branch is below the seam)" \
    || bad "(4c) main-loop delinquency-cleared branch does NOT call _starvation_note_close"

# ── (5) permanent revert-control: the parent's silence ──────────────────────────────────────────
echo ""; echo "─── (5) _maybe_starvation_page neutered (the pre-rework parent): zero pages in 3600s ───"
_simout=$(sim 3600 -1 -1 0 1 '')   # captured FIRST: a here-string $(…) would run the sourced daemon under IFS='|'
IFS='|' read -r N_TOOK N_OFFS _ _ _ _ _ <<<"$_simout"
[[ "$N_TOOK" == "-1" && -z "$N_OFFS" ]] \
    && ok "(5) CONTROL: neutered page path → no take AND zero pages over the full hour — the parent's measured silence; (1)'s assertions bite" \
    || bad "(5) control broke (took=${N_TOOK}, offs=[${N_OFFS} ]) — the scenario no longer documents the silence"

# ── (6) knob off + drift announcer ──────────────────────────────────────────────────────────────
echo ""; echo "─── (6) TAKEOVER_STARVATION_ALERT_SECS=0 disables; the drift announcer says so ───"
_simout=$(sim 900 -1 -1 0 0 0)   # captured FIRST: a here-string $(…) would run the sourced daemon under IFS='|'
IFS='|' read -r K_TOOK K_OFFS _ _ _ _ _ <<<"$_simout"
[[ "$K_TOOK" == "-1" && -z "$K_OFFS" ]] \
    && ok "(6a) knob 0 → zero pages (starvation paging off; the hold itself is unchanged)" \
    || bad "(6a) knob 0 still paged (took=${K_TOOK}, offs=[${K_OFFS} ])"
out=$(drift_out "$STANDBY" 'TAKEOVER_STARVATION_ALERT_SECS=0')
n=$(printf '%s\n' "$out" | grep -c '\[config-drift\]')
[[ "$n" == "1" && "$out" == *"TAKEOVER_STARVATION_ALERT_SECS=0 DISABLES"* ]] \
    && ok "(6b) drift announcer: value 0 → one [config-drift] line with the DISABLES wording" \
    || bad "(6b) value 0 announce wrong ($n lines): $out"
out=$(drift_out "$STANDBY" 'TAKEOVER_STARVATION_ALERT_SECS=600')
n=$(printf '%s\n' "$out" | grep -c '\[config-drift\]')
[[ "$n" == "1" && "$out" == *"TAKEOVER_STARVATION_ALERT_SECS=600 is laxer than this version's default 300"* ]] \
    && ok "(6c) drift announcer: value 600 → laxer-than-default (pages later = laxer)" \
    || bad "(6c) value 600 announce wrong ($n lines): $out"
out=$(drift_out "$STANDBY")
[[ -z "$out" ]] \
    && ok "(6d) default 300 announces nothing (no startup noise)" \
    || bad "(6d) defaults produced drift output: $out"

# ── (7) fresh-boot host: the FIRST page must not wait out the throttle ──────────────────────────
#    mono_now is boot-relative. With _last_starvation_alert initialized to 0, an unguarded
#    "now - last >= ALERT_THROTTLE" gate silently delays the FIRST page on a host whose uptime is
#    still < ALERT_THROTTLE (found by the slice-4 rework verifier): episode at uptime 50s → held
#    hits 300 at uptime 350, but 350-0 < 600 → first page slips to uptime 600 (t0+550). The
#    throttle must gate REPEATS only. T0=50 override simulates the freshly booted host.
echo ""; echo "─── (7) episode starts at uptime 50s: first page at t0+300, not delayed by the throttle ───"
_simout=$(T0=50 sim 600 -1 -1 0 0 '')   # captured FIRST: a here-string $(…) would run the sourced daemon under IFS='|'
IFS='|' read -r F_TOOK F_OFFS _ _ _ _ _ <<<"$_simout"
echo "    took=${F_TOOK} pages=[${F_OFFS} ]"
[[ "$F_OFFS" == " 300" ]] \
    && ok "(7) fresh-boot first page at exactly t0+300 (held>=threshold alone gates the FIRST page; the throttle gates repeats)" \
    || bad "(7) fresh-boot page offsets [${F_OFFS} ] (want [ 300]) — the throttle gate swallowed the first page on a young-uptime host"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
