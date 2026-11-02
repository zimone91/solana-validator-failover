#!/bin/bash
# v0.7 (AG-3.4): THE HOLDER'S GAP RULE. A frozen host (VM pause, live migration, suspend) resumes the staked validator and this
# monitor together. With the armed take (AG-3) a spare may have taken the identity during the freeze, so the holder must demote
# BEFORE it votes - not one cycle later, and not only if the RPC happens to answer. The primary stamps the END of every cycle
# (_cycle_sleep, the one sleep that ends a cycle on every path) and latches a gap >= HOLDER_GAP_DEMOTE_SECS at the first statement
# of the next one (_gap_latch); right after the identity read (_gap_demote) a latched gap on a STAKED node calls switch_to_unstaked
# BEFORE check_internet, the manual-change detection and the self-fence. This suite drives the REAL main-loop region of the shipped
# primary (the pl_run / drive-cycle technique): every cycle of a PLAN runs through the real text with the clock, the identity read,
# the internet check, the fence and the demote mocked and an ordered event log recording what the cycle did.
#   PLAN = space-separated cycles; a cycle is <id><flags>[+<freeze>]: id S staked / U unstaked / X identity unreadable; flags i = the
#   internet check fails, f = the self-fence fires, l = the vote-latency escalation fires; +N = the host is frozen N more seconds
#   during that cycle's END-of-cycle sleep (the next cycle starts N seconds late).
#   (1) no stamp (first cycle / restarted monitor) -> no fire, however large the clock
#   (2) gap < bound -> no fire; the boundary: gap = bound-1 holds, gap = bound fires (>=)
#   (3) gap >= bound + STAKED -> switch_to_unstaked is the FIRST decision of the wake cycle, before check_internet and the self-fence; the
#       reason names the gap; exactly one demote; the cycles around it are quiet
#   (4) gap >= bound + UNSTAKED at the wake -> one INFO line, no demote; the pending gap is cleared (a later STAKED cycle does not fire)
#   (5) DRY_RUN -> the REAL switch_to_unstaked pages "[DRY RUN] WOULD SWITCH TO UNSTAKED", zero admin calls, and the stamp still refreshes
#   (6) the stamp refreshes on EVERY cycle-ending path: the unreachable, internet, self-fence and latency `continue` paths (a cycle pair of
#       20 s freezes on each path then a normal cycle -> no fire)
#   (7) startup: HOLDER_GAP_DEMOTE_SECS < 20 refuses to start, and so does a gap that does not clear the longer of CHECK_INTERVAL /
#       TURBO_INTERVAL by 17 s (the default 30 passes; a non-numeric value is refused)
#   (8) a FAILED demote stays pending and is retried on the next cycle (the gap is a one-shot signal; the demote must not be)
#   (9) a gap seen on a cycle whose identity read fails is not lost: the demote fires on the next readable STAKED cycle
#   (10) the mid-cycle manual-change grace (STARTUP_GRACE) is not a gap: it sits inside a cycle
#   (11) STRUCTURE by text: five _cycle_sleep sites and ONE raw _watchdog_sleep (the grace) in the loop; the stamp precedes the sleep; the
#        latch is the first statement, the demote sits between the identity read and check_internet
#   (12) CONTROLS (mutate()): every mutant of the rule turns its case red
# RED ON THE BASE (4c6bbc5 + this suite): no _cycle_sleep / _gap_latch / _gap_demote / HOLDER_GAP_DEMOTE_SECS exist, so the demote never
# fires on a gap, a 29 s knob is accepted, the census finds no site; after the change they hold.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, mutate(), extract_region.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "The holder's gap rule: a frozen host's wake demotes a staked holder first (v0.7 AG-3.4)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gap.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cut_src() { local f="$WORK/seam.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$$.$RANDOM"; sed -n '1,/MAIN LOOP/p' "$1" > "$f"; printf '%s' "$f"; }
STK="StakedPubkey111111111111111111111111111111"
UNS="UnstakedPubkey1111111111111111111111111111"

# ── the world: the REAL loop region over a plan, an ordered event log ─────────────────────────────────────────────────
gap_world() {   # gap_world <script> <plan> [VAR=val ...] -> the events, one per line: CYCLE k / IDENT x / INET / SELFFENCE / COLLISION / TIER1 / WINDOW_RESET / DEMOTE <reason> / PAGE <status> / ADMIN <argv> / LOG[W] <gap line> / SLEEP n / GRACE n
    local script="$1" plan="$2" cs region; shift 2
    cs=$(cut_src "$script")
    region=$(extract_region "$script" '^while \$_running; do' '^done$') || { echo "NO-REGION"; return 0; }
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        eval "run_loop() {
$region
}"
        EV=$(mktemp); export EV; trap 'rm -rf "$EV" "$EV.bin"' EXIT
        mkdir -p "$EV.bin"; printf '#!/bin/bash\necho "ADMIN $*" >> "%s"\nexit 0\n' "$EV" > "$EV.bin/agave-validator"; chmod +x "$EV.bin/agave-validator"
        SOLANA_PATH="$EV.bin"
        ev() { printf '%s\n' "$*" >> "$EV"; }
        read -r -a PLAN <<< "$plan"
        IDX=0
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; UNSTAKED_KEYPAIR="$EV"; LEDGER_PATH="$EV.ledger"; VALIDATOR_TYPE=agave
        TG_ENABLED=false; DRY_RUN=false; ALERT_THROTTLE=600; PRIMARY_SELF_FENCE=true; CHECK_INTERVAL=3; TURBO_INTERVAL=1; _current_interval=3
        CONNECTIVITY_RETRIES=99; MAX_VOTE_LATENCY=0; DELINQUENCY_RETRIES=1; STARTUP_GRACE=30; RECOVERY_MODE=manual; SETIDENTITY_TIMEOUT=15
        _SIM_NOW=1700000000; DEMOTE_FAILS=0; _dcalls=0
        for kv in "$@"; do eval "$kv"; done
        [[ "$MAX_VOTE_LATENCY" == "0" && "$plan" == *l* ]] && MAX_VOTE_LATENCY=10
        mono_now() { echo "$_SIM_NOW"; }
        tok_id() { local t="${PLAN[$IDX]}"; printf '%s' "${t:0:1}"; }
        tok_has() { local t="${PLAN[$IDX]%%+*}"; [[ "${t:1}" == *"$1"* ]]; }
        tok_freeze() { local t="${PLAN[$IDX]}"; case "$t" in *+*) printf '%s' "${t##*+}" ;; *) printf '0' ;; esac; }
        _last_heartbeat=$(date +%s); HEARTBEAT_INTERVAL=2000000000
        case "$(tok_id)" in S) _last_known_identity="$STK" ;; U) _last_known_identity="$UNS" ;; *) _last_known_identity="$STK" ;; esac
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _version_startup_check() { :; }; _vat_cycle() { :; }; _fence_rot_check() { :; }; _g2_step() { :; }; _elapsed_step() { :; }
        flush_pending_alerts() { :; }; display_status() { :; }; save_state() { :; }; _watchdog_pet() { :; }; send_telegram() { return 0; }; send_webhook() { :; }
        log_info() { case "$1" in *"[gap]"*) ev "LOG $1" ;; esac; }; log_warn() { case "$1" in *"[gap]"*) ev "LOGW $1" ;; esac; }; log_error() { :; }
        alert() { ev "PAGE $3"; return 0; }; alert_info() { :; }; alert_warn() { :; }
        get_local_identity() { ev "IDENT $(tok_id)"; case "$(tok_id)" in S) echo "$STAKED_PUBKEY" ;; U) echo "$UNSTAKED_PUBKEY" ;; *) return 0 ;; esac; }
        check_internet() { ev INET; tok_has i && return 1; return 0; }
        check_self_fence_isolation() { ev SELFFENCE; tok_has f && return 0; return 1; }
        check_identity_collision() { ev COLLISION; return 0; }
        tier1_check_delinquency() { ev TIER1; return 1; }
        tier1_get_vote_latency() { tok_has l && echo 99 || echo 1; }
        verify_latency_tiered() { return 0; }
        _vat_hold() { return 1; }
        window_push() { :; }; window_count() { echo 0; }; window_triggered() { return 1; }; window_mostly_clear() { return 1; }; window_reset() { ev WINDOW_RESET; }
        if [[ "${REAL_DEMOTE:-0}" != "1" ]]; then
            switch_to_unstaked() { _dcalls=$((_dcalls + 1)); ev "DEMOTE $1"; [[ $_dcalls -le $DEMOTE_FAILS ]] && return 1; return 0; }
        fi
        _watchdog_sleep() {
            if [[ "$1" == "$STARTUP_GRACE" && "$1" != "$CHECK_INTERVAL" && "$1" != "$_current_interval" ]]; then
                ev "GRACE $1"; _SIM_NOW=$(( _SIM_NOW + $1 )); return 0   # the manual-change grace: a wait INSIDE a cycle, the cycle goes on
            fi
            ev "SLEEP $1"
            _SIM_NOW=$(( _SIM_NOW + $1 + $(tok_freeze) ))
            IDX=$(( IDX + 1 ))
            if [[ $IDX -ge ${#PLAN[@]} ]]; then _running=false; else ev "CYCLE $IDX"; fi
        }
        sleep() { :; }   # the loop ends through _watchdog_sleep (every cycle ends in it); the real demote's `sleep 1` must not end it
        ev "CYCLE 0"
        _running=true; run_loop
        cat "$EV"
    )
}
cyc() { printf '%s\n' "$1" | awk -v k="$2" '$1 == "CYCLE" { on = ($2 == k); next } on'; }                  # cyc <events> <k> -> the events of cycle k
decisions() { printf '%s\n' "$1" | grep -E '^(DEMOTE|INET|SELFFENCE|COLLISION|TIER1|WINDOW_RESET)'; }       # the cycle's decisions, in order
gap_demotes() { printf '%s\n' "$1" | grep -c '^DEMOTE holder gap:'; }                                       # how many gap demotes the run made
n_of() { printf '%s\n' "$1" | grep -c -E "$2"; }

# ── (1) no stamp -> no fire ───────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) no stamp (first cycle / restarted monitor) -> nothing, however large the clock ───"
ev1=$(gap_world "$PRIMARY" "S")
if [[ "$(gap_demotes "$ev1")" == "0" && "$(n_of "$ev1" '^IDENT S')" == "1" && "$(n_of "$ev1" '^SELFFENCE')" == "1" ]]; then
    ok "(1) one STAKED cycle on a clock of 1.7e9 s with no previous cycle: no gap demote, the cycle ran its normal checks (a missing stamp is not a gap of 'now - 0')"
else
    bad "(1) first cycle: $(printf '%s' "$ev1" | tr '\n' ';' | cut -c1-200)"
fi
p_no_stamp_guard() { [[ "$(gap_demotes "$1")" == "0" ]]; }

# ── (2) gap < bound -> no fire; the >= boundary ───────────────────────────────────────────────────────────────────────
echo ""; echo "─── (2) a gap below the bound holds; the boundary is >= ───"
ev2a=$(gap_world "$PRIMARY" "S+10 S"); ev2b=$(gap_world "$PRIMARY" "S+26 S"); ev2c=$(gap_world "$PRIMARY" "S+27 S")
if [[ "$(gap_demotes "$ev2a")" == "0" && "$(gap_demotes "$ev2b")" == "0" && "$(gap_demotes "$ev2c")" == "1" ]]; then
    ok "(2) HOLDER_GAP_DEMOTE_SECS=30, sleep 3: a 10 s freeze (gap 13) and a 26 s freeze (gap 29) do nothing; a 27 s freeze (gap 30 = the bound) fires - the rule is >="
else
    bad "(2) boundary: gap13=$(gap_demotes "$ev2a") gap29=$(gap_demotes "$ev2b") gap30=$(gap_demotes "$ev2c")"
fi
p_boundary() { [[ "$(gap_demotes "$1")" == "1" ]]; }

# ── (3) gap >= bound + STAKED: the demote is the first decision of the wake cycle ─────────────────────────────────────
echo ""; echo "─── (3) a staked holder that wakes after a freeze demotes BEFORE the internet check and the self-fence ───"
ev3=$(gap_world "$PRIMARY" "S S+100 S S"); c3_0=$(cyc "$ev3" 0); c3_1=$(cyc "$ev3" 1); c3_2=$(cyc "$ev3" 2); c3_3=$(cyc "$ev3" 3)
first3=$(decisions "$c3_2" | head -1)
if [[ "$(gap_demotes "$ev3")" == "1" && "$first3" == "DEMOTE holder gap: this monitor did not run for 103 s (host frozen or suspended)"* \
      && "$first3" == *"a spare may have taken the identity" && "$(gap_demotes "$c3_2")" == "1" \
      && "$(decisions "$c3_2" | sed -n 2p)" == "INET" && "$(decisions "$c3_2" | sed -n 3p)" == "SELFFENCE" \
      && "$(gap_demotes "$c3_0$c3_1$c3_3")" == "0" ]]; then
    ok "(3) after a 100 s freeze the wake cycle's decisions run DEMOTE, INET, SELFFENCE, ...: the gap demote ('holder gap: this monitor did not run for 103 s (host frozen or suspended) - a spare may have taken the identity') comes first; one demote in the run, the cycles before and after are quiet"
else
    bad "(3) wake cycle: first=[$first3] order=[$(decisions "$c3_2" | tr '\n' ',' | cut -c1-120)] demotes=$(gap_demotes "$ev3")"
fi
p_first_demote() { local c; c=$(cyc "$1" 2); [[ "$(gap_demotes "$1")" == "1" && "$(decisions "$c" | head -1)" == "DEMOTE holder gap:"* ]]; }
p_demote_once() { [[ "$(gap_demotes "$1")" == "1" ]]; }

# ── (4) gap >= bound + UNSTAKED at the wake ───────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) unstaked at the wake: an INFO line, no demote; the pending gap is cleared ───"
ev4=$(gap_world "$PRIMARY" "U U+100 U S")
if [[ "$(gap_demotes "$ev4")" == "0" && "$(n_of "$ev4" '^LOG \[gap\] this monitor did not run for 103s, but the identity is')" == "1" ]]; then
    ok "(4) a 100 s freeze on an UNSTAKED node: one '[gap] ... not the staked one - nothing to demote' INFO line and no demote, and the STAKED cycle that follows (a manual return) is not fired at"
else
    bad "(4) unstaked wake: demotes=$(gap_demotes "$ev4") infos=$(n_of "$ev4" '^LOG \[gap\]') :: $(printf '%s' "$ev4" | tr '\n' ';' | cut -c1-240)"
fi
p_unstaked_info() { [[ "$(gap_demotes "$1")" == "0" && "$(n_of "$1" '^LOG \[gap\] this monitor did not run')" == "1" ]]; }

# ── (5) DRY_RUN ───────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (5) DRY_RUN: the dry page through the real switch_to_unstaked, no admin call, the stamp still refreshes ───"
ev5=$(gap_world "$PRIMARY" "S S+100 S S S" DRY_RUN=true REAL_DEMOTE=1)
if [[ "$(n_of "$ev5" '^PAGE \[DRY RUN\] WOULD SWITCH TO UNSTAKED')" == "1" && "$(n_of "$ev5" '^ADMIN')" == "0" && "$(n_of "$(cyc "$ev5" 2)" '^PAGE \[DRY RUN\]')" == "1" ]]; then
    ok "(5) DRY_RUN + a 100 s freeze on a staked holder: exactly one '[DRY RUN] WOULD SWITCH TO UNSTAKED' page (on the wake cycle), ZERO admin-socket calls, and the two cycles after it are quiet (the stamp refreshed, the pending gap cleared)"
else
    bad "(5) dry run: pages=$(n_of "$ev5" '^PAGE') dry=$(n_of "$ev5" '^PAGE \[DRY RUN\]') admin=$(n_of "$ev5" '^ADMIN')"
fi
ev5l=$(gap_world "$PRIMARY" "S S+100 S" REAL_DEMOTE=1)
if [[ "$(n_of "$ev5l" '^ADMIN .*remove-all')" == "1" && "$(n_of "$ev5l" '^ADMIN .*set-identity')" == "1" ]]; then
    ok "(5b) the same world LIVE (DRY_RUN=false, real switch_to_unstaked over a recording admin stub): the wake cycle makes the demote's two admin calls (authorized-voter remove-all, then set-identity)"
else
    bad "(5b) live demote: $(printf '%s' "$ev5l" | grep '^ADMIN' | tr '\n' ';' | cut -c1-200)"
fi

# ── (6) the stamp refreshes on every cycle-ending path ────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) the end-of-cycle stamp is refreshed on the unreachable, internet, self-fence and latency paths (and the tail) ───"
p6_ok=1; p6_rows=""
for pair in "unreachable:S X+20 X+20 S" "internet:S Si+20 Si+20 S" "self-fence:S Sf+20 Sf+20 S" "latency:S Sl+20 Sl+20 S"; do
    lab=${pair%%:*}; plan=${pair#*:}
    e6=$(gap_world "$PRIMARY" "$plan")
    if [[ "$(gap_demotes "$e6")" == "0" && "$(n_of "$e6" '^CYCLE')" == "4" ]]; then p6_rows="$p6_rows $lab"; else p6_ok=0; p6_rows="$p6_rows $lab:[demotes=$(gap_demotes "$e6") cycles=$(n_of "$e6" '^CYCLE')]"; fi
done
[[ $p6_ok -eq 1 ]] && ok "(6) two 20 s-frozen cycles on each cycle-ending path then a normal cycle: no gap demote (each path stamps its own end; a path that did not would show the OLDER stamp and read 49 s):$p6_rows" || bad "(6) a path does not refresh the stamp:$p6_rows"
p_no_demote() { [[ "$(gap_demotes "$1")" == "0" ]]; }

# ── (7) startup validation ────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (7) startup: HOLDER_GAP_DEMOTE_SECS has a floor of 20 and must clear the cycle interval by 17 s ───"
rc_of() {  # rc_of <script> VAR=val... -> the exit status of validate_numeric_config under the overrides
    local script="$1"; shift
    (
        local src; src=$(cut_src "$script")
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
        for kv in "$@"; do eval "$kv"; done
        ( validate_numeric_config ) >/dev/null 2>&1
        echo $?
    )
}
r_def=$(rc_of "$PRIMARY"); r_19=$(rc_of "$PRIMARY" 'HOLDER_GAP_DEMOTE_SECS=19'); r_20=$(rc_of "$PRIMARY" 'HOLDER_GAP_DEMOTE_SECS=20'); r_abc=$(rc_of "$PRIMARY" 'HOLDER_GAP_DEMOTE_SECS=abc')
r_19fast=$(rc_of "$PRIMARY" 'HOLDER_GAP_DEMOTE_SECS=19' 'CHECK_INTERVAL=1' 'TURBO_INTERVAL=1'); r_ci14=$(rc_of "$PRIMARY" 'CHECK_INTERVAL=14'); r_ci13=$(rc_of "$PRIMARY" 'CHECK_INTERVAL=13')
r_ci14raised=$(rc_of "$PRIMARY" 'CHECK_INTERVAL=14' 'HOLDER_GAP_DEMOTE_SECS=31')
if [[ "$r_def" == "0" && "$r_19" == "1" && "$r_20" == "0" && "$r_abc" == "1" ]]; then
    ok "(7a) the default 30 passes, 20 passes, 19 refuses to start, 'abc' refuses to start"
else
    bad "(7a) knob: default=$r_def 19=$r_19 20=$r_20 abc=$r_abc"
fi
p_19_refused() { [[ "$(rc_of "$1" 'HOLDER_GAP_DEMOTE_SECS=19' 'CHECK_INTERVAL=1' 'TURBO_INTERVAL=1')" == "1" ]]; }
if [[ "$r_19fast" == "1" && "$r_ci14" == "1" && "$r_ci13" == "0" && "$r_ci14raised" == "0" ]]; then
    ok "(7b) the interval relation (17 + the longer interval): 19 is refused even at CHECK_INTERVAL=1 (the floor of 20), CHECK_INTERVAL=14 with the default 30 is refused (needs >= 31: every cycle would read as a freeze), 13 passes (needs 30), 14 with 31 passes"
else
    bad "(7b) relation: 19@1=$r_19fast ci14=$r_ci14 ci13=$r_ci13 ci14+31=$r_ci14raised"
fi
p_interval_relation() { [[ "$(rc_of "$1" 'CHECK_INTERVAL=14')" == "1" ]]; }

# ── (8) a failed demote is retried ────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) a failed demote stays pending and is retried on the next cycle ───"
ev8=$(gap_world "$PRIMARY" "S S+100 S S S" DEMOTE_FAILS=1)
if [[ "$(gap_demotes "$ev8")" == "2" && "$(gap_demotes "$(cyc "$ev8" 2)")" == "1" && "$(gap_demotes "$(cyc "$ev8" 3)")" == "1" && "$(gap_demotes "$(cyc "$ev8" 4)")" == "0" ]]; then
    ok "(8) the wake cycle's demote fails (rc 1): the next cycle demotes again (its gap is small - the retry is the pending flag, not the gap) and succeeds; the cycle after that is quiet"
else
    bad "(8) retry: per-cycle demotes=$(gap_demotes "$(cyc "$ev8" 2)")/$(gap_demotes "$(cyc "$ev8" 3)")/$(gap_demotes "$(cyc "$ev8" 4)") total=$(gap_demotes "$ev8")"
fi
p_retry() { [[ "$(gap_demotes "$1")" == "2" ]]; }

# ── (9) a gap on an unreadable-identity cycle is not lost ─────────────────────────────────────────────────────────────
echo ""; echo "─── (9) the gap seen on a cycle whose identity read fails is acted on at the next readable STAKED cycle ───"
ev9=$(gap_world "$PRIMARY" "S S+100 X S S")
if [[ "$(gap_demotes "$(cyc "$ev9" 2)")" == "0" && "$(gap_demotes "$(cyc "$ev9" 3)")" == "1" && "$(gap_demotes "$ev9")" == "1" \
      && "$(decisions "$(cyc "$ev9" 3)" | head -1)" == "DEMOTE holder gap: this monitor did not run for 103 s"* ]]; then
    ok "(9) 100 s freeze, the wake cycle cannot read the identity (no demote possible), the NEXT cycle reads STAKED and demotes first, naming the 103 s gap - although its own gap is 3 s"
else
    bad "(9) latch: wake=$(gap_demotes "$(cyc "$ev9" 2)") next=$(gap_demotes "$(cyc "$ev9" 3)") total=$(gap_demotes "$ev9")"
fi
p_latch_survives() { [[ "$(gap_demotes "$(cyc "$1" 3)")" == "1" ]]; }

# ── (10) the manual-change grace is inside a cycle ────────────────────────────────────────────────────────────────────
echo ""; echo "─── (10) the manual-change grace wait (STARTUP_GRACE) sits inside a cycle and is not a gap ───"
ev10=$(gap_world "$PRIMARY" "U S S" STARTUP_GRACE=60)
if [[ "$(n_of "$ev10" '^GRACE 60')" == "1" && "$(gap_demotes "$ev10")" == "0" && "$(n_of "$ev10" '^WINDOW_RESET')" == "1" ]]; then
    ok "(10) an operator's manual return to STAKED (the manual-change branch waits STARTUP_GRACE=60 s, longer than the bound, in the middle of the cycle): no gap demote on the next cycle - the stamp is taken at the END of the cycle"
else
    bad "(10) grace: grace=$(n_of "$ev10" '^GRACE') demotes=$(gap_demotes "$ev10") manual=$(n_of "$ev10" '^WINDOW_RESET')"
fi
p_grace_not_gap() { [[ "$(n_of "$1" '^GRACE 60')" == "1" && "$(gap_demotes "$1")" == "0" ]]; }

# ── (11) structure ────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (11) structure by text: the five cycle-ending sleeps, the stamp before the sleep, the latch first, the demote after the identity read ───"
loop_code() { extract_region "$1" '^while \$_running; do' '^done$' | grep -v '^[[:space:]]*#'; }
fn_code() { sed -n "/^$2() {/,/^}/p" "$1" | grep -v '^[[:space:]]*#'; }
struct_why() {   # struct_why <script> -> why the structure is wrong (empty = right)
    local f="$1" why="" lp n_cs n_ws l_latch l_ident l_dem l_inet l_sf lines
    lp=$(loop_code "$f"); [[ -n "$lp" ]] || { printf 'no-loop-region'; return; }
    n_cs=$(printf '%s\n' "$lp" | grep -cE '^[[:space:]]*_cycle_sleep "')
    n_ws=$(printf '%s\n' "$lp" | grep -cE '(^|[^_a-z])_watchdog_sleep "')
    [[ "$n_cs" == "5" ]] || why="$why cycle-sleeps-$n_cs-of-5"
    [[ "$n_ws" == "1" && "$(printf '%s\n' "$lp" | grep -c '_watchdog_sleep "\$STARTUP_GRACE"')" == "1" ]] || why="$why raw-watchdog-sleeps-$n_ws-want-only-the-grace"
    lines=$(printf '%s\n' "$lp" | grep -n -E '^[[:space:]]*_gap_latch|get_local_identity|^[[:space:]]*_gap_demote|check_internet|check_self_fence_isolation' | cut -c1-90)
    l_latch=$(printf '%s\n' "$lp" | grep -n -E '^[[:space:]]*_gap_latch' | head -1 | cut -d: -f1)
    l_ident=$(printf '%s\n' "$lp" | grep -n 'CURRENT_IDENTITY=$(get_local_identity' | head -1 | cut -d: -f1)
    l_dem=$(printf '%s\n' "$lp" | grep -n -E '^[[:space:]]*_gap_demote' | head -1 | cut -d: -f1)
    l_inet=$(printf '%s\n' "$lp" | grep -n 'if ! check_internet' | head -1 | cut -d: -f1)
    l_sf=$(printf '%s\n' "$lp" | grep -n 'if check_self_fence_isolation' | head -1 | cut -d: -f1)
    [[ "$(printf '%s\n' "$lp" | grep -cE '^[[:space:]]*_gap_latch')" == "1" && "$(printf '%s\n' "$lp" | grep -cE '^[[:space:]]*_gap_demote')" == "1" ]] || why="$why latch-or-demote-not-called-once"
    [[ -n "$l_latch" && -n "$l_ident" && -n "$l_dem" && -n "$l_inet" && -n "$l_sf" ]] || { printf '%s anchors-missing(%s)' "$why" "$lines"; return; }
    [[ $l_latch -lt $l_ident ]] || why="$why latch-not-before-the-identity-read"
    [[ $l_ident -lt $l_dem && $l_dem -lt $l_inet && $l_inet -lt $l_sf ]] || why="$why demote-not-between-the-identity-read-and-check_internet"
    local body; body=$(fn_code "$f" _cycle_sleep)
    [[ "$(printf '%s\n' "$body" | sed -n 2p)" == *'_cycle_end_ts=$(mono_now)'* && "$(printf '%s\n' "$body" | sed -n 3p)" == *'_watchdog_sleep "$@"'* ]] || why="$why stamp-not-before-the-sleep"
    printf '%s' "$why"
}
struct_ok() { [[ -z "$(struct_why "$1")" ]]; }
w11=$(struct_why "$PRIMARY")
[[ -z "$w11" ]] && ok "(11) the loop has five _cycle_sleep sites and ONE raw _watchdog_sleep (the STARTUP_GRACE wait inside the manual-change branch); _gap_latch is called once, before the identity read; _gap_demote once, after it and before check_internet and the self-fence; _cycle_sleep stamps, then sleeps" || bad "(11) structure:$w11"
# The standby carries no stamp and never assigns or expands the knob. It NAMES the knob in text - the other half of the pairing rule (AG-3.1b: the comments, the armed
# start-up refusal and the unarmed warning say "the holder's HOLDER_GAP_DEMOTE_SECS + 30") - so a mention is not a use.
sb_gap_use() { grep -c -E '_cycle_end_ts|^[[:space:]]*(export[[:space:]]+)?HOLDER_GAP_DEMOTE_SECS=|\$\{?HOLDER_GAP_DEMOTE_SECS' "$1"; }
sb_gap_clean() { [[ "$(sb_gap_use "$1")" == "0" ]]; }
sb_gap_clean "$STANDBY" \
    && ok "(11b) the gap rule is the holder's: the standby carries no stamp and never assigns or expands the knob (it names the knob in text: the pairing rule)" || bad "(11b) the standby uses the holder's gap rule: $(sb_gap_use "$STANDBY") line(s)"

# ── (12) controls ─────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (12) CONTROLS (mutate()): each mutant must turn its case red ───"
ctl_ok=1; ctl_rows=""
ctl() {   # ctl <label> <sed expr> <plan> <predicate> [VAR=val ...] - the predicate holds on the shipped script and FAILS on the mutant
    local label="$1" expr="$2" plan="$3" pred="$4" m="$WORK/mut-$1.sh" real mut rv mv; shift 4
    if ! mutate "$PRIMARY" "$expr" "$m"; then ctl_ok=0; ctl_rows="$ctl_rows $label:NOT-APPLIED"; return; fi
    real=$(gap_world "$PRIMARY" "$plan" "$@"); mut=$(gap_world "$m" "$plan" "$@")
    "$pred" "$real" && rv=y || rv=n; "$pred" "$mut" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then ctl_rows="$ctl_rows $label:red"; else ctl_ok=0; ctl_rows="$ctl_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
ctl_rc() {   # ctl_rc <label> <sed expr> <predicate over a script> - the predicate holds on the shipped script and FAILS on the mutant
    local label="$1" expr="$2" pred="$3" m="$WORK/mut-$1.sh" rv mv
    if ! mutate "$PRIMARY" "$expr" "$m"; then ctl_ok=0; ctl_rows="$ctl_rows $label:NOT-APPLIED"; return; fi
    "$pred" "$PRIMARY" && rv=y || rv=n; "$pred" "$m" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then ctl_rows="$ctl_rows $label:red"; else ctl_ok=0; ctl_rows="$ctl_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
ctl no-stamp-guard '/^    \[\[ \${_cycle_end_ts:-0} -gt 0 \]\] || return 0$/d' "S" p_no_stamp_guard
ctl gt-not-ge 's/\$_g -ge \$HOLDER_GAP_DEMOTE_SECS/$_g -gt $HOLDER_GAP_DEMOTE_SECS/' "S+27 S" p_boundary
ctl demote-below-internet '/^    _gap_demote   # v0.7 (AG-3.4)/d; s/^    CONNECTIVITY_FAIL_COUNT=0$/    CONNECTIVITY_FAIL_COUNT=0; _gap_demote/' "S S+100 S S" p_first_demote
ctl demote-after-self-fence '/^    _gap_demote   # v0.7 (AG-3.4)/d; s/^        check_identity_collision || true$/        check_identity_collision || true; _gap_demote/' "S S+100 S S" p_first_demote
ctl demote-never '/^    _gap_demote   # v0.7 (AG-3.4)/d' "S S+100 S S" p_demote_once
ctl unstaked-demotes '/^_gap_demote() {/,/^}/ s/^    if \[\[ "\$CURRENT_IDENTITY" == "\$STAKED_PUBKEY" \]\]; then$/    if true; then/' "U U+100 U S" p_unstaked_info
ctl stamp-unreachable 's/^        _cycle_sleep "\$CHECK_INTERVAL"   # FF-B3/        _watchdog_sleep "$CHECK_INTERVAL"   # FF-B3/' "S X+20 X+20 S" p_no_demote
ctl stamp-internet 's/^        _cycle_sleep "\$CHECK_INTERVAL"; continue/        _watchdog_sleep "$CHECK_INTERVAL"; continue/' "S Si+20 Si+20 S" p_no_demote
ctl stamp-self-fence 's/^                _cycle_sleep "\$_current_interval"; continue/                _watchdog_sleep "$_current_interval"; continue/' "S Sf+20 Sf+20 S" p_no_demote
ctl stamp-latency 's/^                        _cycle_sleep "\$_current_interval"; continue/                        _watchdog_sleep "$_current_interval"; continue/' "S Sl+20 Sl+20 S" p_no_demote
ctl stamp-tail 's/^    _cycle_sleep "\$_current_interval"   # FF-B3/    _watchdog_sleep "$_current_interval"   # FF-B3/' "S S+100 S S" p_demote_once
ctl stamp-at-cycle-start 's/^    _cycle_end_ts=\$(mono_now)$/    :/; s/^    _gap_latch   # v0.7 (AG-3.4): FIRST/    _gap_latch; _cycle_end_ts=$(mono_now)   # v0.7 (AG-3.4): FIRST/' "U S S" p_grace_not_gap STARTUP_GRACE=60
ctl latch-after-identity-read '/^    _gap_latch   # v0.7 (AG-3.4)/d; s/^    _gap_demote   # v0.7 (AG-3.4)/    _gap_latch; _gap_demote   # v0.7 (AG-3.4)/' "S S+100 X S S" p_latch_survives
ctl no-retry 's/^        if switch_to_unstaked \("holder gap: .*"\); then$/        switch_to_unstaked \1; if true; then/' "S S+100 S S S" p_retry DEMOTE_FAILS=1
ctl_rc no-floor 's/_validate_numeric HOLDER_GAP_DEMOTE_SECS 20 /_validate_numeric HOLDER_GAP_DEMOTE_SECS 0 /' p_19_refused
ctl_rc no-interval-relation 's/^    if \[\[ \$HOLDER_GAP_DEMOTE_SECS -lt \$_gap_floor \]\]; then$/    if false; then/' p_interval_relation
ctl_rc census-one-site-reverted 's/^        _cycle_sleep "\$CHECK_INTERVAL"; continue/        _watchdog_sleep "$CHECK_INTERVAL"; continue/' struct_ok
ctl_sb() {   # ctl_sb <label> <sed expr> - the standby predicate (sb_gap_clean) holds on the shipped script and FAILS on the mutant
    local label="$1" expr="$2" m="$WORK/mut-$1.sh" rv mv
    if ! mutate "$STANDBY" "$expr" "$m"; then ctl_ok=0; ctl_rows="$ctl_rows $label:NOT-APPLIED"; return; fi
    sb_gap_clean "$STANDBY" && rv=y || rv=n; sb_gap_clean "$m" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then ctl_rows="$ctl_rows $label:red"; else ctl_ok=0; ctl_rows="$ctl_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
ctl_sb sb-knob-assigned 's/^TAKEOVER_DELAY=90 /HOLDER_GAP_DEMOTE_SECS=45; TAKEOVER_DELAY=90 /'
ctl_sb sb-knob-expanded 's/^TAKEOVER_DELAY=90 /: "$HOLDER_GAP_DEMOTE_SECS"; TAKEOVER_DELAY=90 /'
ctl_sb sb-stamp 's/^TAKEOVER_DELAY=90 /_cycle_end_ts=0; TAKEOVER_DELAY=90 /'
[[ $ctl_ok -eq 1 ]] && ok "(12) every mutant of the rule turns its case red:$ctl_rows" || bad "(12) a control is not red (NOT-APPLIED = its sed matched nothing):$ctl_rows"

results_banner
