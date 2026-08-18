#!/bin/bash
# v0.7 (pre-Block-4, №9): ALPENGLOW FEATURE-GATE TRIPWIRE. 4.2.1 ships the entire votor/BLS
# machinery dormant, runtime-gated on the on-chain `alpenglow` feature. On activation:
# set-identity demands a vote-history file by default (a direct hit on the no-tower-transfer
# design) and the lastVote observation model needs re-derivation — so the moment the gate shows
# pending/active the operator MUST be paged (re-run the 4.2 audit; Blocks 5–6 constants freeze).
# Read-only observability; page-only; the probe lives at the TOP of the main loop, never inside a
# takeover/recovery/verdict path.
#
# Harness: source-to-`# MAIN LOOP` seam of the standby (and the primary for byte-parity + a
# behavior spot check), mono/date shims, `_alpenglow_gate_fetch` shadowed (scriptable per-call
# word/rc through an event file — the daemon calls it in a $() subshell), alert_warn/log shadows
# capturing text, save_state shadowed to record calls. Drives the REAL `_alpenglow_gate_check`.
# Cases:
#   (1) inactive → (next check) pending: exactly ONE page, text contains "ALPENGLOW" and
#       "4.2 audit"; state persisted (save_state called with pending recorded)
#   (2) pending → active: one CRITICAL page (see 13); active stable: silent
#   (3) inactive stable across many checks: zero pages
#   (4) unknown (fetch rc 1): zero pages while streak < 4, WARN-level failure logs,
#       `_alpenglow_gate_state` unchanged, no save_state call (fetches still counted — the case
#       must not pass vacuously pre-implementation)
#   (5) knob 0: zero fetches. Drift announcer (drift_out idiom): 0 → DISABLES wording;
#       12 → laxer; default 6 → silent
#   (6) fresh-boot first check immediate: T0=50, first cycle probes (no cadence wait —
#       the 0-sentinel/monotonic lesson)
#   (7) cadence: HOURS=6 → second probe only after +21600 s (fetch calls counted over a
#       driven timeline)
#   (8) BYTE-IDENTITY: `_alpenglow_gate_fetch` + `_alpenglow_gate_check` identical across
#       daemons (sed-extract + compare, the test_act_then_alert case-7 idiom)
#   (9) PERMANENT REVERT-CONTROL: `_alpenglow_gate_check(){ :; }` shadowed → scenario-1
#       pages = 0 (documents the parent daemon; proves case 1 bites)
#  (10) WIRING (structural, the test_config_drift (g) precedent): both daemons call
#       `_alpenglow_gate_check` in the main loop (after the MAIN LOOP banner) and log the
#       armed/DISABLED tripwire line right after startup_checks
#  (11) BLIND STREAK (reviewer fix A): 4 consecutive probe failures page ("a safety mechanism
#       whose failure mode is silence" — the slice-4 lesson), repeat per ALERT_THROTTLE, reset
#       silently on success
#  (12) RETRY FLOOR (reviewer fix B): a failed probe retries on a 900 s floor; only a SUCCESSFUL
#       probe holds the full cadence (the _last_confirm_attempt form)
#  (13) CRITICAL ACTIVE (reviewer, accepted): pending → alert_warn (epoch-boundary slack);
#       active → CRITICAL alert, the UNKNOWN-IDENTITY channel (promote path inert = same class)
#  (14) FIX C (structural): alpenglow_fast_leader_handover named in code with the source-verified
#       reason it is not watched (one usage, replay_stage.rs:1611, subordinate to the main
#       migration status; gates neither set-identity nor observation)
# RED (two rounds, both captured): (i) scratchpad red-preblock4.log — cases 1-3, 4 (fetch count),
# 5 (drift wordings), 6, 7, 8, 10 FAIL against the 94d64a6 daemons (helpers absent); the pages=0
# halves of (4)/(9) are green-by-vacuum there, which is why (4) also pins the fetch count.
# (ii) scratchpad red-tripwire-fixes.log — the reviewer-fix cases against the first-cut tripwire:
# (4b) warn level, (11a/11b) retry floor + blind streak, (12a) transient cost, (13a/13b) CRITICAL
# active, (14 both daemons) companion-gate justification — 8 FAILs, green after the fixes.

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
PRIMARY="$DIR/solana-primary-failover.sh"
[[ -f "$STANDBY" && -f "$PRIMARY" ]] || { echo "  ❌ scripts not found"; exit 1; }

# ── harness: drive the REAL _alpenglow_gate_check over a scripted fetch sequence + timeline ────
#   $1=script  $2=ALPENGLOW_GATE_CHECK_HOURS  $3=fetch sequence (space-separated words; "rc1" =
#   return 1/unknown; the Nth check consumes the Nth word, past-the-end = rc1)  $4=timeline
#   (space-separated mono instants; one _alpenglow_gate_check call each)  $5=1 → shadow
#   _alpenglow_gate_check(){ :; } AFTER sourcing (case 9)  $6=pre-seeded _alpenglow_gate_state
# Echoes: pages=N|fetches=N|state=S|saves=N|saved=<,-joined states at save>|text=<first page>
ap_run() {
  local script="$1" hours="$2" seq="$3" timeline="$4" shadow="${5:-0}" init="${6:-}"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    ALPENGLOW_GATE_CHECK_HOURS="$hours"
    [[ -n "$init" ]] && _alpenglow_gate_state="$init"
    _SEQ_STR="$seq"
    EVT=$(mktemp); export _AP_EVT="$EVT"
    trap 'rm -f "$EVT"' EXIT
    _SIM_NOW=0
    date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
    mono_now(){ echo "$_SIM_NOW"; }
    WARNLOGS=0
    log(){ :; }; log_info(){ :; }; log_error(){ :; }
    log_warn(){ case "$*" in *"[alpenglow]"*) WARNLOGS=$((WARNLOGS+1)) ;; esac; }
    PAGES=0; PTEXT=""; BLIND=0; BTEXT=""
    alert_warn(){
        case "$1" in
            *"TRIPWIRE BLIND"*) BLIND=$((BLIND+1)); [[ -z "$BTEXT" ]] && BTEXT="${1//$'\n'/ }" ;;
            *) PAGES=$((PAGES+1)); [[ -z "$PTEXT" ]] && PTEXT="${1//$'\n'/ }" ;;
        esac
        return 0
    }
    CRIT=0; CTEXT=""
    alert(){ CRIT=$((CRIT+1)); [[ -z "$CTEXT" ]] && CTEXT="${1//$'\n'/ } ${3:-}"; return 0; }
    alert_info(){ :; }; send_telegram(){ return 0; }; send_webhook(){ :; }
    SAVES=0; SAVED=""
    save_state(){ SAVES=$((SAVES+1)); SAVED="${SAVED:+$SAVED,}${_alpenglow_gate_state:-none}"; return 0; }
    # The daemon calls the fetch seam in a $() subshell → sequence via the shared event file
    # (the test_act_then_alert SAMPLE-counter idiom).
    _alpenglow_gate_fetch(){
        local n w
        n=$(( $(grep -c 'F' "$_AP_EVT" 2>/dev/null) + 1 ))
        echo "F" >> "$_AP_EVT"
        w=$(printf '%s\n' "$_SEQ_STR" | tr ' ' '\n' | sed -n "${n}p")
        [[ -z "$w" || "$w" == "rc1" ]] && return 1
        echo "$w"; return 0
    }
    if [[ "$shadow" == "1" ]]; then _alpenglow_gate_check(){ :; }; fi
    local t
    for t in $timeline; do
        _SIM_NOW="$t"
        _alpenglow_gate_check
    done
    printf 'pages=%s|blind=%s|crit=%s|warnlogs=%s|fetches=%s|state=%s|saves=%s|saved=%s|text=%s|btext=%s|ctext=%s\n' \
        "$PAGES" "$BLIND" "$CRIT" "$WARNLOGS" "$(grep -c 'F' "$EVT" 2>/dev/null)" \
        "${_alpenglow_gate_state:-none}" "$SAVES" "${SAVED:-none}" "${PTEXT:0:200}" \
        "${BTEXT:0:140}" "${CTEXT:0:200}"
  )
}
field(){ printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

# drift_out idiom (test_config_drift): recorded [config-drift] output of the REAL announcer
ap_drift() {
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
echo "  Alpenglow feature-gate tripwire (v0.7 pre-Block-4, №9)"
echo "============================================="

# ── (1) inactive → pending: ONE page, the re-audit instruction, state persisted ────────────────
echo ""; echo "─── (1) inactive → (next check) pending → exactly one page + persisted ───"
out=$(ap_run "$STANDBY" 6 "inactive pending" "100 21700")
if [[ "$(field "$out" pages)" == "1" ]]; then
    ok "(1a) exactly one page on the inactive→pending transition"
else
    bad "(1a) expected 1 page, got '$(field "$out" pages)' ($out)"
fi
txt=$(field "$out" text)
[[ "$txt" == *"ALPENGLOW"* && "$txt" == *"4.2 audit"* ]] \
    && ok "(1b) page names ALPENGLOW and the 4.2 audit re-run" \
    || bad "(1b) page text incomplete: '$txt'"
[[ "$(field "$out" state)" == "pending" && "$(field "$out" saved)" == *"pending"* ]] \
    && ok "(1c) state=pending and save_state was called with pending recorded (saved=$(field "$out" saved))" \
    || bad "(1c) pending not persisted (state=$(field "$out" state) saved=$(field "$out" saved))"

# ── (2) pending → active: one page; active stable: silent ──────────────────────────────────────
echo ""; echo "─── (2) pending → active pages once; stable active is silent ───"
out=$(ap_run "$STANDBY" 6 "active active active" "100 21700 43300" 0 "pending")
if [[ "$(field "$out" crit)" == "1" && "$(field "$out" pages)" == "0" && "$(field "$out" state)" == "active" ]]; then
    ok "(2a) pending→active = one CRITICAL page (reviewer's escalation: promote path may be inert), then active-stable silent (crit=1 over 3 checks, no alert_warn)"
else
    bad "(2a) wrong ($out)"
fi
txt=$(field "$out" ctext)
[[ "$txt" == *"ACTIVE"* && "$txt" == *"was pending"* ]] \
    && ok "(2b) the CRITICAL page names the transition (ACTIVE, was pending)" \
    || bad "(2b) transition not named: '$txt'"

# ── (3) inactive stable: zero pages ────────────────────────────────────────────────────────────
echo ""; echo "─── (3) inactive stable across many checks → zero pages ───"
out=$(ap_run "$STANDBY" 6 "inactive inactive inactive inactive" "100 21700 43300 64900")
[[ "$(field "$out" pages)" == "0" && "$(field "$out" state)" == "inactive" && "$(field "$out" fetches)" == "4" ]] \
    && ok "(3) 4 checks all inactive → zero pages, state=inactive, 4 fetches" \
    || bad "(3) wrong ($out)"

# ── (4) unknown (rc 1): never pages, never overwrites, no save ─────────────────────────────────
echo ""; echo "─── (4) unknown never pages and never overwrites the persisted state ───"
out=$(ap_run "$STANDBY" 6 "rc1 rc1" "100 21700" 0 "inactive")
[[ "$(field "$out" pages)" == "0" && "$(field "$out" blind)" == "0" && "$(field "$out" state)" == "inactive" && "$(field "$out" saves)" == "0" && "$(field "$out" fetches)" == "2" ]] \
    && ok "(4a) two unknown probes: 0 pages (streak < 4), state stays 'inactive', 0 saves, 2 fetches" \
    || bad "(4a) wrong ($out)"
[[ "$(field "$out" warnlogs)" == "2" ]] \
    && ok "(4b) each probe failure logs at WARN level (the operator's warn scan sees tripwire blindness)" \
    || bad "(4b) warn-level failure logs: $(field "$out" warnlogs) (want 2) — probe failure is quieter than warn"

# ── (5) knob 0 = off; drift announcer wordings ─────────────────────────────────────────────────
echo ""; echo "─── (5) ALPENGLOW_GATE_CHECK_HOURS=0 → off (zero fetches) + drift-announced ───"
out=$(ap_run "$STANDBY" 0 "inactive" "100 21700 999999")
[[ "$(field "$out" fetches)" == "0" && "$(field "$out" pages)" == "0" ]] \
    && ok "(5a) knob 0 → zero fetches, zero pages over 3 cycles" \
    || bad "(5a) knob 0 still probed ($out)"
d=$(ap_drift "$STANDBY" 'ALPENGLOW_GATE_CHECK_HOURS=0')
[[ "$d" == *"ALPENGLOW_GATE_CHECK_HOURS=0 DISABLES"* ]] \
    && ok "(5b) drift announcer: 0 → DISABLES wording (laxest)" \
    || bad "(5b) 0 not announced as DISABLES: '$d'"
d=$(ap_drift "$STANDBY" 'ALPENGLOW_GATE_CHECK_HOURS=12')
[[ "$d" == *"ALPENGLOW_GATE_CHECK_HOURS=12 is laxer than this version's default 6"* ]] \
    && ok "(5c) drift announcer: 12 → generic laxer-than-default-6 line" \
    || bad "(5c) 12 not announced: '$d'"
d=$(ap_drift "$STANDBY")
[[ "$d" != *"ALPENGLOW"* ]] \
    && ok "(5d) default 6 → silent (no ALPENGLOW drift line)" \
    || bad "(5d) default announced: '$d'"

# ── (6) fresh-boot first check immediate ───────────────────────────────────────────────────────
echo ""; echo "─── (6) T0=50 (fresh boot): the FIRST cycle probes — no cadence wait ───"
out=$(ap_run "$STANDBY" 6 "inactive" "50")
[[ "$(field "$out" fetches)" == "1" ]] \
    && ok "(6) first check ran immediately at mono t=50 (0-sentinel/monotonic lesson)" \
    || bad "(6) first check did not run at t=50 ($out)"

# ── (7) cadence: second probe only after +21600 s ──────────────────────────────────────────────
echo ""; echo "─── (7) HOURS=6: probes at t=100 and then not again before t=100+21600 ───"
out=$(ap_run "$STANDBY" 6 "inactive inactive inactive" "100 5000 15000 21699 21700")
[[ "$(field "$out" fetches)" == "2" ]] \
    && ok "(7) exactly 2 fetches over 5 cycles (t=100 and t=21700; 21699 still inside the window)" \
    || bad "(7) cadence wrong — fetches=$(field "$out" fetches) ($out)"

# ── (8) BYTE-IDENTITY across daemons ───────────────────────────────────────────────────────────
echo ""; echo "─── (8) helpers byte-identical across daemons ───"
P_F=$(sed -n '/^_alpenglow_gate_fetch() {/,/^}$/p' "$PRIMARY")
S_F=$(sed -n '/^_alpenglow_gate_fetch() {/,/^}$/p' "$STANDBY")
if [[ -n "$P_F" && "$P_F" == "$S_F" ]]; then
    ok "(8a) _alpenglow_gate_fetch body byte-identical ($(printf '%s\n' "$P_F" | wc -l | tr -d ' ') lines)"
else
    bad "(8a) _alpenglow_gate_fetch missing or DIVERGED between the daemons"
fi
P_C=$(sed -n '/^_alpenglow_gate_check() {/,/^}$/p' "$PRIMARY")
S_C=$(sed -n '/^_alpenglow_gate_check() {/,/^}$/p' "$STANDBY")
if [[ -n "$P_C" && "$P_C" == "$S_C" ]]; then
    ok "(8b) _alpenglow_gate_check body byte-identical ($(printf '%s\n' "$P_C" | wc -l | tr -d ' ') lines)"
else
    bad "(8b) _alpenglow_gate_check missing or DIVERGED between the daemons"
fi

# primary behavior spot check (scenario 1 through the PRIMARY seam)
out=$(ap_run "$PRIMARY" 6 "inactive pending" "100 21700")
[[ "$(field "$out" pages)" == "1" && "$(field "$out" state)" == "pending" && "$(field "$out" saved)" == *"pending"* ]] \
    && ok "(8c) PRIMARY twin: inactive→pending pages once and persists (behavior parity)" \
    || bad "(8c) PRIMARY twin wrong ($out)"

# ── (9) PERMANENT REVERT-CONTROL ───────────────────────────────────────────────────────────────
echo ""; echo "─── (9) revert-control: _alpenglow_gate_check(){ :; } → scenario-1 pages = 0 ───"
out=$(ap_run "$STANDBY" 6 "inactive pending" "100 21700" 1)
[[ "$(field "$out" pages)" == "0" && "$(field "$out" fetches)" == "0" ]] \
    && ok "(9) neutered check → 0 pages/0 fetches (documents the parent daemon; case 1 bites)" \
    || bad "(9) revert-control leaked ($out)"

# ── (10) wiring: main-loop call site + startup visibility line (both daemons) ──────────────────
echo ""; echo "─── (10) structural: call at the top of each main loop + armed line at startup ───"
for scr in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$scr")
    below=$(sed -n '/^# ========================= MAIN LOOP/,$p' "$scr")
    [[ "$below" == *"_alpenglow_gate_check"* ]] \
        && ok "(10a:$name) main loop calls _alpenglow_gate_check" \
        || bad "(10a:$name) no _alpenglow_gate_check call after the MAIN LOOP banner"
    [[ "$below" == *"tripwire armed: probing the feature gate every"* && "$below" == *"tripwire DISABLED"* ]] \
        && ok "(10b:$name) startup visibility line present (armed + DISABLED wordings)" \
        || bad "(10b:$name) startup tripwire visibility line missing"
done

# ── (11) BLIND STREAK (fix A): persistent probe failure pages at streak 4, repeats per throttle ─
#     Success at 100 → full cadence to 21700; failures then retry on the 900 s floor:
#     21700(s1) 22600(s2) 23500(s3) 24400(s4→page) 25300(s5→page, throttle 600 < 900 elapsed);
#     recovery at 26200 resets the streak silently.
echo ""; echo "─── (11) tripwire blindness pages at 4 consecutive failures, repeats, resets on success ───"
out=$(ap_run "$STANDBY" 6 "inactive rc1 rc1 rc1 rc1 rc1 inactive" "100 21700 22600 23500 24400 25300 26200")
[[ "$(field "$out" fetches)" == "7" ]] \
    && ok "(11a) all seven instants probed — failures retry on the 900 s floor, not the 6 h cadence" \
    || bad "(11a) fetches=$(field "$out" fetches) (want 7) — the retry floor is missing ($out)"
[[ "$(field "$out" blind)" == "2" && "$(field "$out" btext)" == *"consecutive"* ]] \
    && ok "(11b) BLIND page fires exactly at streak 4 and repeats per ALERT_THROTTLE (2 pages, none earlier)" \
    || bad "(11b) blind pages=$(field "$out" blind) (want 2) btext='$(field "$out" btext)'"
[[ "$(field "$out" pages)" == "0" && "$(field "$out" state)" == "inactive" ]] \
    && ok "(11c) no transition page, state intact; the success at the end resets the streak silently" \
    || bad "(11c) pages=$(field "$out" pages) state=$(field "$out" state) ($out)"

# ── (12) RETRY FLOOR vs FULL CADENCE (fix B): failure retries ~15 min; success waits the full 6 h ─
echo ""; echo "─── (12) a transient failure costs ~15 min, not 6 h; success keeps the 6 h cadence ───"
out=$(ap_run "$STANDBY" 6 "rc1 inactive" "100 1000 1900")
[[ "$(field "$out" fetches)" == "2" ]] \
    && ok "(12a) failure at t=100 → re-probe allowed at t=1000 (900 s floor); the success then holds the full cadence (t=1900 skipped)" \
    || bad "(12a) fetches=$(field "$out" fetches) (want 2) — transient failure cost the full cadence or the floor leaks ($out)"
out=$(ap_run "$STANDBY" 6 "inactive inactive" "100 1000 21700")
[[ "$(field "$out" fetches)" == "2" ]] \
    && ok "(12b) success at t=100 → next probe only at t=21700 (full 6 h; t=1000 skipped)" \
    || bad "(12b) fetches=$(field "$out" fetches) (want 2) ($out)"

# ── (13) ACTIVE escalates to the CRITICAL channel (reviewer, non-blocking accepted) ────────────
#     pending has epoch-boundary slack → alert_warn is right; ACTIVE means set-identity starts
#     failing by default = the tool's promote path is inert — the UNKNOWN IDENTITY class, the
#     UNKNOWN IDENTITY channel (alert, queued CRITICAL).
echo ""; echo "─── (13) pending pages WARN; active pages CRITICAL (the UNKNOWN-IDENTITY channel) ───"
out=$(ap_run "$STANDBY" 6 "pending active" "100 21700")
[[ "$(field "$out" pages)" == "1" && "$(field "$out" crit)" == "1" ]] \
    && ok "(13a) pending → one alert_warn; active → one CRITICAL alert (not a second alert_warn)" \
    || bad "(13a) pages=$(field "$out" pages) crit=$(field "$out" crit) (want 1/1) ($out)"
[[ "$(field "$out" ctext)" == *"ALPENGLOW"* && "$(field "$out" ctext)" == *"vote-history"* ]] \
    && ok "(13b) the CRITICAL page names the failure mode (set-identity / vote-history file)" \
    || bad "(13b) CRITICAL text: '$(field "$out" ctext)'"
[[ "$(field "$out" state)" == "active" && "$(field "$out" saved)" == *"active"* ]] \
    && ok "(13c) active persisted" \
    || bad "(13c) state=$(field "$out" state) saved=$(field "$out" saved)"

# ── (14) FIX C (structural): the companion gate is named and its exclusion justified in code ───
echo ""; echo "─── (14) alpenglow_fast_leader_handover: watched-or-justified, in the code itself ───"
for scr in "$STANDBY" "$PRIMARY"; do
    name=$(basename "$scr")
    [[ "$(cat "$scr")" == *"FLHoAWBDjNh6zwmJ5i1NKK4KyD8otAiv7XxvmnFnVnKH"* && "$(cat "$scr")" == *"deliberately NOT watched"* && "$(cat "$scr")" == *"replay_stage.rs"* ]] \
        && ok "(14:$name) the companion gate is named with the source-verified reason it is not watched" \
        || bad "(14:$name) companion-gate decision missing from the code (reviewer: a tripwire watching one of two sibling gates must say why)"
done

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
