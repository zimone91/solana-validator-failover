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
# AG-3.8 - THE HUNG HOLDER'S RUNG, in the same world (an X cycle = the identity read fails; it lasts 11 s: XREAD=8 s of failed read + the 3 s sleep):
#   (13) identity unreadable 55 s + LOCAL getSlot silent + lastVote frozen while the cluster tip advances -> _selffence_hard_stop exactly once
#        ("holder unreachable 55s, local RPC silent, lastVote frozen"), then the 'HOLDER HUNG — HARD STOP' page (act, then alert); a confirmed stop latches
#   (14) lastVote grows -> no stop, ONE throttled 'HOLDER UNREACHABLE — not stopped (lastVote grows ...)' page
#   (15) no external answer / LOCAL getSlot answers (and then no second external read) / a restarted process / a busy unit / a stale or backwards view /
#        no process at the first cycle -> no stop, a page with its own reason; (15b) a provider flip re-baselines, the next cycle decides
#   (16) the identity reads again -> the episode is over (a stamp kept across it would stop the validator)
#   (17) DRY_RUN -> the dry page once per ALERT_THROTTLE, no stop, no admin call
#   (18) a ladder that did not confirm is retried only after ALERT_THROTTLE; an unstaked node is never sampled; N = the knob fires (>=)
#   (19) HOLDER_UNREACHABLE_STOP_SECS=29 refuses to start   (20) _validator_pid: the unit's MainPID (canonical, > 1, alive) first, pgrep after
#   (21) structure: _hung_check in the unreachable branch before the display, _hung_reset right after the readable identity; the standby has none of it
# RED ON THE BASE (aa49329 + this suite): no _hung_check, so no hung holder is ever stopped, a 29 s knob is accepted, _validator_pid ignores MainPID.
#   (23) THE RUNG'S TIMELINE (claim = check for the figures in SAFETY and the knob comment; AG-3.6d): the REAL main loop, _hung_check and _selffence_hard_stop over a FILE clock, the mocked
#        calls running to their own bounds (curl -m, timeout T + K): the clock reads 0 / 12 / 23 / 34 s (the first unreadable cycle also takes the baseline read), the default knob decides
#        on the 4th reading and the validator is dead 48 to 51 s after the hang (fast branch), 50 to 53 s / 70 to 73 s (normal ladder, stop 2 s / wedged); knobs 13..23 decide at 23;
#        Frankendancer (5 s RPC read): 0 / 9 / 17 / 25 / 33, dead 44 to 47 s; the external read's cost moves it second for second.
# (23) is NOT red on the base: it pins what the code already does (the texts of AG-3.6b had the clock 0 / 11 / 22 / 33 and 49 to 55 s / 70 to 75 s, from a world in which the external read
# costs nothing); its red is its seven mutants - a bound moved in the code moves the timeline.
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
gap_world() {   # gap_world <script> <plan> [VAR=val ...] -> the events, one per line: CYCLE k / IDENT x / INET / SELFFENCE / COLLISION / TIER1 / WINDOW_RESET / DEMOTE <reason> / PAGE <status> / ADMIN <argv> / LOG[W] <gap line> / SLEEP n / GRACE n / (AG-3.8) WPAGE <alert_warn text> / TXT <alert text> / SAMPLE / LOCALSLOT / HARDSTOP <why>
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
        EV=$(mktemp); export EV; trap 'rm -rf "$EV" "$EV.bin" "$EV.sc"' EXIT
        mkdir -p "$EV.bin"; printf '#!/bin/sh\necho "ADMIN $*" >> "%s"\nexit 0\n' "$EV" > "$EV.bin/agave-validator"; chmod +x "$EV.bin/agave-validator"
        SOLANA_PATH="$EV.bin"
        ev() { printf '%s\n' "$*" >> "$EV"; }
        read -r -a PLAN <<< "$plan"
        IDX=0
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; UNSTAKED_KEYPAIR="$EV"; LEDGER_PATH="$EV.ledger"; VALIDATOR_TYPE=agave
        TG_ENABLED=false; DRY_RUN=false; ALERT_THROTTLE=600; PRIMARY_SELF_FENCE=true; CHECK_INTERVAL=3; TURBO_INTERVAL=1; _current_interval=3
        CONNECTIVITY_RETRIES=99; MAX_VOTE_LATENCY=0; DELINQUENCY_RETRIES=1; STARTUP_GRACE=30; RECOVERY_MODE=manual; SETIDENTITY_TIMEOUT=15
        _SIM_NOW=1700000000; DEMOTE_FAILS=0; _dcalls=0
        T_BASE=1700000000; XREAD=0; LVMODE=down; SLOTMODE=silent; PIDMODE=same; STARTMODE=old; UNITBUSY=""; HS_RC=0   # AG-3.8 (AG-3.8d: STARTMODE): an unreadable cycle costs XREAD s more; the external lastVote / local RPC / pid / unit worlds
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
        log_info() { case "$1" in *"[gap]"*|*"[hung]"*) ev "LOG $1" ;; esac; }; log_warn() { case "$1" in *"[gap]"*|*"[hung]"*) ev "LOGW $1" ;; esac; }; log_error() { :; }
        alert() { ev "PAGE $3"; ev "TXT ${1:0:600}"; return 0; }; alert_info() { :; }; alert_warn() { ev "WPAGE ${1:0:600}"; }
        get_local_identity() { ev "IDENT $(tok_id)"; case "$(tok_id)" in S) echo "$STAKED_PUBKEY" ;; U) echo "$UNSTAKED_PUBKEY" ;; *) return 0 ;; esac; }
        check_internet() { ev INET; tok_has i && return 1; return 0; }
        check_self_fence_isolation() { ev SELFFENCE; tok_has f && return 0; return 1; }
        check_identity_collision() { ev COLLISION; return 0; }
        tier1_check_delinquency() { ev TIER1; return 1; }
        tier1_get_vote_latency() { tok_has l && echo 99 || echo 1; }
        verify_latency_tiered() { return 0; }
        _vat_hold() { return 1; }
        _validator_pid() { case "$PIDMODE" in none) ;; changed) if [[ $_SIM_NOW -ge $(( T_BASE + 30 )) ]]; then printf '5555'; else printf '4242'; fi ;; *) printf '4242' ;; esac; }
        _proc_start_secs() {   # AG-3.8d: the validator process's start, seconds since boot: old = long before the last readable read; new = 2 s after it; at_read = in the same second as it; sec_before = 1 s before it; future = later than now; none = unreadable; new_then_old = new for the first episode, old after
            local n
            case "$STARTMODE" in
                old)          printf '%s' $(( T_BASE - 5000 )) ;;
                new)          printf '%s' $(( T_BASE + 2 )) ;;
                at_read)      printf '%s' "$T_BASE" ;;
                sec_before)   printf '%s' $(( T_BASE - 1 )) ;;
                future)       printf '%s' $(( _SIM_NOW + 100 )) ;;
                new_then_old) echo x >> "$EV.sc"; n=$(wc -l < "$EV.sc"); if [[ $n -le 1 ]]; then printf '%s' $(( T_BASE + 2 )); else printf '%s' $(( T_BASE - 5000 )); fi ;;
                *)            ;;
            esac
        }
        _hung_unit_busy() { [[ -n "$UNITBUSY" ]] || return 1; printf '%s' "$UNITBUSY"; return 0; }
        _hung_local_slot() { ev LOCALSLOT; [[ "$SLOTMODE" == "answers" ]] && printf '123456789'; return 0; }
        get_staked_liveness_sample() {   # the external vote-account read: lastVote / the same payload's cluster tip / the provider tier
            ev SAMPLE
            local d=$(( _SIM_NOW - T_BASE )) tier=T2
            case "$LVMODE" in
                frozen)  printf '5000 %s %s\n' $(( 9000 + d )) "$tier" ;;
                growing) printf '%s %s %s\n' $(( 5000 + 2 * d )) $(( 9000 + d )) "$tier" ;;
                stale)   printf '5000 9000 %s\n' "$tier" ;;
                back)    printf '%s %s %s\n' $(( 5000 - d )) $(( 9000 + d )) "$tier" ;;
                flip)    [[ $d -ge 30 ]] && tier=T3; printf '5000 %s %s\n' $(( 9000 + d )) "$tier" ;;
                *)       return 1 ;;
            esac
        }
        _selffence_hard_stop() { ev "HARDSTOP $1"; _hs_branch="${HS_BRANCH:-normal ladder (process state S)}"; return $HS_RC; }
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
            [[ "$(tok_id)" == "X" ]] && _SIM_NOW=$(( _SIM_NOW + XREAD ))   # the failed identity read (the real one times out at 8 s) is time the cycle took
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
# The standby carries no stamp, no latch, no demote and never assigns or expands the knob. It NAMES the knob in text - the other half of the pairing rule (AG-3.1b: the comments,
# the armed start-up refusal and the unarmed warning say "the holder's HOLDER_GAP_DEMOTE_SECS + 30") - so a mention is not a use.
sb_gap_use() { grep -c -E '_cycle_end_ts|_gap_latch|_gap_demote|^[[:space:]]*(export[[:space:]]+)?HOLDER_GAP_DEMOTE_SECS=|\$\{?HOLDER_GAP_DEMOTE_SECS' "$1"; }
sb_gap_clean() { [[ "$(sb_gap_use "$1")" == "0" ]]; }
sb_gap_clean "$STANDBY" \
    && ok "(11b) the gap rule is the holder's: the standby carries no stamp, no latch, no demote and never assigns or expands the knob (it only NAMES the pairing rule: comments, the armed refusal, the unarmed warning)" || bad "(11b) the standby uses the holder's gap mechanism: $(sb_gap_use "$STANDBY") line(s)"

# ══ AG-3.8: THE HUNG HOLDER'S RUNG ════════════════════════════════════════════════════════════════════════════════════════
# A validator that is alive but mute keeps the staked identity; its admin socket answers nothing, so the identity read fails on every cycle and
# the unreachable branch used to only page. _hung_check (the unreachable branch) hard-stops it through _selffence_hard_stop once the identity
# has been unreadable for HOLDER_UNREACHABLE_STOP_SECS AND it is the same process AND LOCAL getSlot is silent AND the vote account's lastVote
# (one external read) has not moved while the cluster tip did. Every doubt is a page, never a kill. The world: PLAN "S X X ..." - an X cycle
# is 11 s long (XREAD=8 s of failed identity read + the 3 s sleep), so the stamp is at the first X, N = 11 k, and the first evaluating cycle
# is the fourth X (N=33 >= 30). LVMODE / SLOTMODE / PIDMODE / UNITBUSY / HS_RC / HS_BRANCH set what the external read, the local RPC, the pid,
# the unit and the ladder do.
PL9="S X X X X X X X X"
hs_n() { n_of "$1" '^HARDSTOP'; }
wp_n() { printf '%s\n' "$1" | grep -c -F 'WPAGE HOLDER UNREACHABLE — not stopped ('; }
reason_kept() { [[ "$(hs_n "$1")" == "0" && "$(printf '%s\n' "$1" | grep -c -F "WPAGE HOLDER UNREACHABLE — not stopped ($2")" == "1" && "$(n_of "$1" '^ADMIN')" == "0" ]]; }

# ── (13) the hung holder is hard-stopped, once, and the page comes after the stop ─────────────────────────────────────────
echo ""; echo "─── (13) identity unreadable 33 s + LOCAL getSlot silent + lastVote frozen while the tip advances -> ONE hard stop, then the page ───"
ev13=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen)
p_hung_stop() {
    local e="$1" i_hs i_pg
    [[ "$(hs_n "$e")" == "1" && "$(n_of "$(cyc "$e" 4)" '^HARDSTOP holder unreachable 33s, local RPC silent, lastVote frozen$')" == "1" \
       && "$(n_of "$e" '^PAGE HOLDER HUNG — HARD STOP 🚨$')" == "1" && "$(wp_n "$e")" == "0" \
       && "$(n_of "$e" '^ADMIN')" == "0" && "$(n_of "$e" '^DEMOTE')" == "0" && "$(n_of "$(cyc "$e" 1)" '^SAMPLE')" == "1" && "$(n_of "$e" '^SAMPLE')" == "2" ]] || return 1
    i_hs=$(printf '%s\n' "$e" | grep -n '^HARDSTOP' | head -1 | cut -d: -f1); i_pg=$(printf '%s\n' "$e" | grep -n '^PAGE HOLDER HUNG' | head -1 | cut -d: -f1)
    [[ -n "$i_hs" && -n "$i_pg" && $i_hs -lt $i_pg ]]
}
t13=$(printf '%s\n' "$ev13" | grep '^TXT Hung holder: ')
if p_hung_stop "$ev13" && [[ "$t13" == *"the identity has been unreadable for 33s (validator pid 4242), LOCAL getSlot is silent, and lastVote 5000 has not moved for 33s while the cluster tip advanced (9003 to 9036)"* && "$t13" == *"confirmed DOWN"* ]]; then
    ok "(13) 11 s cycles: the stamp and the first lastVote sample on the first unreadable cycle, the decision on the fourth (N=33 >= 30): _selffence_hard_stop gets 'holder unreachable 33s, local RPC silent, lastVote frozen' exactly once, THEN the 'HOLDER HUNG — HARD STOP 🚨' page names the three facts and 'confirmed DOWN'; no admin call, no demote; the cycles after it are quiet (the confirmed stop latches), no 'not stopped' page"
else
    bad "(13) hung holder: hardstops=$(hs_n "$ev13") pages=$(n_of "$ev13" '^PAGE HOLDER HUNG') wpages=$(wp_n "$ev13") samples=$(n_of "$ev13" '^SAMPLE') :: $(printf '%s' "$ev13" | grep -E '^(HARDSTOP|PAGE|WPAGE|TXT)' | tr '\n' ';' | cut -c1-300)"
fi
ev13f=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen "HS_BRANCH='fast: process state T, blocking systemctl stop skipped (stop requested with --no-block)'")
p_branch_named() { printf '%s\n' "$1" | grep -q -F 'Ladder branch: fast: process state T, blocking systemctl stop skipped (stop requested with --no-block).'; }
if p_branch_named "$ev13f" && printf '%s\n' "$t13" | grep -q -F 'Ladder branch: normal ladder (process state S).'; then
    ok "(13b) the page names the branch the ladder took: 'Ladder branch: fast: process state T, blocking systemctl stop skipped (stop requested with --no-block).' when the ladder reports the fast branch, 'Ladder branch: normal ladder (process state S).' when it reports the normal one"
else
    bad "(13b) branch in the page: fast=[$(printf '%s' "$ev13f" | grep '^TXT Hung holder' | cut -c1-80)...] normal=[$(printf '%s' "$t13" | cut -c180-330)]"
fi

# ── (14) lastVote GROWS -> nothing is stopped; ONE page per ALERT_THROTTLE ────────────────────────────────────────────────
echo ""; echo "─── (14) a voting validator with a mute admin socket is not touched: lastVote grows -> no stop, a throttled page ───"
ev14=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=growing); ev14t=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=growing ALERT_THROTTLE=20)
p_growing_kept() { reason_kept "$1" 'lastVote grows'; }
if p_growing_kept "$ev14" && [[ "$(wp_n "$ev14t")" == "3" && "$(hs_n "$ev14t")" == "0" ]]; then
    ok "(14) lastVote 5006 -> 5072 between the baseline and the decision: HARDSTOP 0, exactly ONE 'HOLDER UNREACHABLE — not stopped (lastVote grows (...)' page over the five evaluating cycles at ALERT_THROTTLE=600; at ALERT_THROTTLE=20 the same world pages again 22 s later, twice (3 pages) - the page is paced by the throttle, not once-only"
else
    bad "(14) growing: hardstops=$(hs_n "$ev14") wpages=$(wp_n "$ev14") throttled(20) wpages=$(wp_n "$ev14t") :: $(printf '%s' "$ev14" | grep -E '^(HARDSTOP|WPAGE)' | tr '\n' ';' | cut -c1-260)"
fi

# ── (15) every other doubt is a page too ─────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (15) no external answer / the local RPC answers / a restarted process / a busy unit / a stale or inconsistent view -> never a stop ───"
p_down_kept() { reason_kept "$1" 'no external RPC answered the vote-account read'; }
p_answers_kept() { reason_kept "$1" 'LOCAL getSlot answers (slot 123456789)' && [[ "$(n_of "$1" '^SAMPLE')" == "1" ]]; }
p_restart_kept() { reason_kept "$1" 'the validator process changed (pid 4242 to 5555): it restarted, it is not hung'; }
p_busy_kept() { reason_kept "$1" 'the validator unit is deactivating (a start or stop is in progress)'; }
p_stale_kept() { reason_kept "$1" 'the external view did not advance (cluster tip 9000)'; }
p_back_kept() { reason_kept "$1" 'lastVote went backwards'; }
p_nopid_kept() { reason_kept "$1" 'no validator process was found at the first unreadable cycle'; }
p15_ok=1; p15_rows=""
for row in "down:p_down_kept:LVMODE=down" "answers:p_answers_kept:LVMODE=frozen SLOTMODE=answers" "restarted:p_restart_kept:LVMODE=frozen PIDMODE=changed" \
           "busy-unit:p_busy_kept:LVMODE=frozen UNITBUSY=deactivating" "stale-view:p_stale_kept:LVMODE=stale" "backwards:p_back_kept:LVMODE=back" "no-process:p_nopid_kept:LVMODE=frozen PIDMODE=none"; do
    lab=${row%%:*}; rest=${row#*:}; pred=${rest%%:*}; vars=${rest#*:}
    # shellcheck disable=SC2086
    e15=$(gap_world "$PRIMARY" "$PL9" XREAD=8 $vars)
    if "$pred" "$e15"; then p15_rows="$p15_rows $lab"; else p15_ok=0; p15_rows="$p15_rows $lab:[hardstops=$(hs_n "$e15") wpages=$(wp_n "$e15") $(printf '%s' "$e15" | grep -E '^WPAGE' | head -1 | cut -c1-110)]"; fi
done
[[ $p15_ok -eq 1 ]] && ok "(15) each of these worlds keeps the validator alive and pages once with its own reason:$p15_rows (and when LOCAL getSlot answers there is NO second external read)" || bad "(15) a doubt still stops or pages wrongly:$p15_rows"
e15f=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=flip)
if [[ "$(hs_n "$e15f")" == "1" && "$(n_of "$(cyc "$e15f" 5)" '^HARDSTOP holder unreachable 44s')" == "1" && "$(printf '%s\n' "$e15f" | grep -c -F 'WPAGE HOLDER UNREACHABLE — not stopped (the answering RPC changed (T2 to T3)')" == "1" ]]; then
    ok "(15b) the answering provider changed between the baseline and the decision (T2 -> T3): no stop on that cycle (two providers' samples are not compared), the sample just read becomes the baseline, and the NEXT cycle (same provider, 11 s later) proves the freeze and stops"
else
    bad "(15b) provider flip: hardstops=$(hs_n "$e15f") :: $(printf '%s' "$e15f" | grep -E '^(HARDSTOP|WPAGE)' | tr '\n' ';' | cut -c1-260)"
fi

# ── (16) the identity reads again -> the clock is gone ──────────────────────────────────────────────────────────────────
echo ""; echo "─── (16) the identity reads again on the fourth cycle (33 s): the episode is over; the next one counts from its own first cycle ───"
ev16=$(gap_world "$PRIMARY" "S X X X S X X X" XREAD=8 LVMODE=frozen)
p_readable_again() { [[ "$(hs_n "$1")" == "0" && "$(wp_n "$1")" == "0" && "$(n_of "$1" '^SAMPLE')" == "2" ]]; }
if p_readable_again "$ev16"; then
    ok "(16) 3 unreadable cycles (N up to 22), 1 readable, 3 unreadable: no decision at all (the second episode reaches N=22), two baselines were taken (one per episode) - a stamp kept across the readable cycle would have stopped the validator on the first cycle after it (N=36)"
else
    bad "(16) reset: hardstops=$(hs_n "$ev16") samples=$(n_of "$ev16" '^SAMPLE') :: $(printf '%s' "$ev16" | grep -E '^(HARDSTOP|WPAGE|SAMPLE)' | tr '\n' ';' | cut -c1-200)"
fi

# ── (17) DRY_RUN ───────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (17) DRY_RUN: the dry page once per ALERT_THROTTLE, no stop, no admin call ───"
ev17=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen DRY_RUN=true); ev17t=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen DRY_RUN=true ALERT_THROTTLE=20)
p_dry_kept() { [[ "$(hs_n "$1")" == "0" && "$(n_of "$1" '^ADMIN')" == "0" && "$(n_of "$1" '^PAGE \[DRY RUN\] WOULD HARD-STOP the hung validator$')" == "1" && "$(n_of "$1" '^PAGE HOLDER HUNG')" == "0" ]]; }
if p_dry_kept "$ev17" && [[ "$(n_of "$ev17t" '^PAGE \[DRY RUN\] WOULD HARD-STOP the hung validator$')" == "3" && "$(hs_n "$ev17t")" == "0" ]]; then
    ok "(17) DRY_RUN=true with every fact holding: _selffence_hard_stop is never called, no admin call, ONE '[DRY RUN] WOULD HARD-STOP the hung validator' page over the five evaluating cycles (three at ALERT_THROTTLE=20) and no 'HOLDER HUNG' page"
else
    bad "(17) dry run: hardstops=$(hs_n "$ev17") admin=$(n_of "$ev17" '^ADMIN') dry=$(n_of "$ev17" '^PAGE \[DRY RUN\]') hung=$(n_of "$ev17" '^PAGE HOLDER HUNG') throttled=$(n_of "$ev17t" '^PAGE \[DRY RUN\]')"
fi

# ── (18) a failed ladder is retried only after ALERT_THROTTLE; an unstaked node is left alone; the boundary is >= ──────────
echo ""; echo "─── (18) a stop that did not confirm waits ALERT_THROTTLE for its retry; an unstaked node is never sampled; N = the knob fires (>=) ───"
ev18=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen HS_RC=1); ev18t=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen HS_RC=1 ALERT_THROTTLE=20)
p_failed_once() { [[ "$(hs_n "$1")" == "1" && "$(n_of "$1" '^PAGE HOLDER HUNG — HARD STOP 🚨$')" == "1" ]] && printf '%s\n' "$1" | grep -q '^TXT Hung holder: .*did NOT confirm the validator down'; }
if p_failed_once "$ev18" && [[ "$(hs_n "$ev18t")" == "3" ]]; then
    ok "(18a) the ladder returns 1: ONE attempt over the five evaluating cycles and one page that says 'did NOT confirm the validator down' (the PRIMARY SELF-FENCE pages are the ladder's own); at ALERT_THROTTLE=20 the retries come 22 s apart (3 attempts)"
else
    bad "(18a) failed ladder: attempts=$(hs_n "$ev18") pages=$(n_of "$ev18" '^PAGE HOLDER HUNG') throttled attempts=$(hs_n "$ev18t")"
fi
ev18u=$(gap_world "$PRIMARY" "U X X X X X X X X" XREAD=8 LVMODE=frozen)
p_unstaked_quiet() { [[ "$(hs_n "$1")" == "0" && "$(n_of "$1" '^SAMPLE')" == "0" && "$(wp_n "$1")" == "0" ]]; }
if p_unstaked_quiet "$ev18u"; then
    ok "(18b) a node last seen UNSTAKED whose identity stops reading: no sample, no stop, no page from the rung (nothing staked is held)"
else
    bad "(18b) unstaked: hardstops=$(hs_n "$ev18u") samples=$(n_of "$ev18u" '^SAMPLE') wpages=$(wp_n "$ev18u")"
fi
ev18b=$(gap_world "$PRIMARY" "$PL9" XREAD=10 LVMODE=frozen HOLDER_UNREACHABLE_STOP_SECS=39)
p_boundary_hung() { [[ "$(hs_n "$1")" == "1" && "$(n_of "$(cyc "$1" 4)" '^HARDSTOP holder unreachable 39s,')" == "1" ]]; }
if p_boundary_hung "$ev18b"; then
    ok "(18c) 13 s cycles and HOLDER_UNREACHABLE_STOP_SECS=39: the stop comes on the fourth unreadable cycle, at N=39 exactly - the rule is >="
else
    bad "(18c) boundary: hardstops=$(hs_n "$ev18b") :: $(printf '%s' "$ev18b" | grep -E '^HARDSTOP' | tr '\n' ';' | cut -c1-200)"
fi

# ── (19) startup: the knob has a floor of 20 ───────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (19) startup: HOLDER_UNREACHABLE_STOP_SECS has a floor of 20 ───"
h_def=$(rc_of "$PRIMARY"); h_19=$(rc_of "$PRIMARY" 'HOLDER_UNREACHABLE_STOP_SECS=19'); h_20=$(rc_of "$PRIMARY" 'HOLDER_UNREACHABLE_STOP_SECS=20'); h_abc=$(rc_of "$PRIMARY" 'HOLDER_UNREACHABLE_STOP_SECS=abc')
if [[ "$h_def" == "0" && "$h_19" == "1" && "$h_20" == "0" && "$h_abc" == "1" ]]; then
    ok "(19) the default 30 passes, 20 passes, 19 refuses to start, 'abc' refuses to start"
else
    bad "(19) knob: default=$h_def 19=$h_19 20=$h_20 abc=$h_abc"
fi
p_hung19_refused() { [[ "$(rc_of "$1" 'HOLDER_UNREACHABLE_STOP_SECS=19')" == "1" ]]; }

# ── (20) the ladder's pid: the unit's MainPID first ────────────────────────────────────────────────────────────────────
echo ""; echo "─── (20) _validator_pid: the unit's MainPID (canonical, > 1, alive) first, pgrep as the fallback ───"
vp_run() {   # vp_run <script> <what systemctl show prints> <what pgrep prints> -> the pid _validator_pid answers
    local script="$1" mp="$2" pg="$3" src; src=$(cut_src "$script")
    (
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        timeout() { shift; "$@"; }
        systemctl() { printf '%s\n' "$mp"; }
        pgrep() { [[ -n "$pg" ]] && printf '%s\n' "$pg"; return 0; }
        VALIDATOR_TYPE=agave
        _validator_pid
    )
}
vp1=$(vp_run "$PRIMARY" "$$" 7777); vp2=$(vp_run "$PRIMARY" 0 7777); vp3=$(vp_run "$PRIMARY" 2147483000 7777); vp4=$(vp_run "$PRIMARY" abc 7777); vp5=$(vp_run "$PRIMARY" "" ""); vp6=$(vp_run "$PRIMARY" "007" 7777)
p_vp_pref() { [[ "$(vp_run "$1" "$$" 7777)" == "$$" ]]; }
p_vp_alive() { [[ "$(vp_run "$1" 2147483000 7777)" == "7777" ]]; }
if [[ "$vp1" == "$$" && "$vp2" == "7777" && "$vp3" == "7777" && "$vp4" == "7777" && "$vp5" == "" && "$vp6" == "7777" ]]; then
    ok "(20) a live MainPID wins over pgrep's pid; MainPID 0, a dead MainPID, a non-numeric one and a non-canonical one ('007') fall back to pgrep; nothing anywhere -> empty"
else
    bad "(20) _validator_pid: live=$vp1 zero=$vp2 dead=$vp3 abc=$vp4 none='$vp5' 007=$vp6"
fi

# ── (21) structure ────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (21) structure by text: _hung_check sits in the unreachable branch before the display; _hung_reset after the readable identity; the standby has none of it ───"
hung_struct_why() {
    local f="$1" why="" lp l_z l_hc l_ds l_sl l_rs l_ok l_gd
    lp=$(loop_code "$f"); [[ -n "$lp" ]] || { printf 'no-loop-region'; return; }
    [[ "$(printf '%s\n' "$lp" | grep -cE '^[[:space:]]*_hung_check')" == "1" && "$(printf '%s\n' "$lp" | grep -cE '^[[:space:]]*_hung_reset')" == "1" ]] || why="$why check-or-reset-not-called-once"
    l_z=$(printf '%s\n' "$lp" | grep -n 'if \[\[ -z "$CURRENT_IDENTITY" \]\]; then' | head -1 | cut -d: -f1)
    l_hc=$(printf '%s\n' "$lp" | grep -n -E '^[[:space:]]*_hung_check' | head -1 | cut -d: -f1)
    l_ds=$(printf '%s\n' "$lp" | grep -n 'display_status "N/A"' | head -1 | cut -d: -f1)
    l_sl=$(printf '%s\n' "$lp" | grep -n '_cycle_sleep "$CHECK_INTERVAL"' | head -1 | cut -d: -f1)
    l_rs=$(printf '%s\n' "$lp" | grep -n -E '^[[:space:]]*_hung_reset' | head -1 | cut -d: -f1)
    l_ok=$(printf '%s\n' "$lp" | grep -n '^    _last_unreachable_alert=0' | head -1 | cut -d: -f1)
    l_gd=$(printf '%s\n' "$lp" | grep -n -E '^[[:space:]]*_gap_demote' | head -1 | cut -d: -f1)
    [[ -n "$l_z" && -n "$l_hc" && -n "$l_ds" && -n "$l_sl" && -n "$l_rs" && -n "$l_ok" && -n "$l_gd" ]] || { printf '%s anchors-missing' "$why"; return; }
    [[ $l_z -lt $l_hc && $l_hc -lt $l_ds && $l_ds -lt $l_sl ]] || why="$why check-not-inside-the-unreachable-branch-before-the-display"
    [[ $l_ok -lt $l_rs && $l_rs -lt $l_gd ]] || why="$why reset-not-right-after-the-readable-identity"
    printf '%s' "$why"
}
hung_struct_ok() { [[ -z "$(hung_struct_why "$1")" ]]; }
w21=$(hung_struct_why "$PRIMARY")
[[ -z "$w21" ]] && ok "(21) _hung_check is called once, inside the unreachable branch after the identity read failed and before display_status and the cycle sleep; _hung_reset once, right after _last_unreachable_alert=0 and before _gap_demote" || bad "(21) structure:$w21"
[[ "$(grep -c '_hung_\|^HOLDER_UNREACHABLE_STOP_SECS=' "$STANDBY")" == "0" ]] \
    && ok "(21b) the hung-holder rung is the holder's: the standby carries neither its state nor the knob's definition (its texts may name the knob)" || bad "(21b) the standby carries the hung-holder rung"

# ── (22) the ladder's FAST branch: a stopped (T) or uninterruptible (D) process skips the BLOCKING `systemctl stop`; rc1 F18: it asks for the stop with --no-block right before the SIGKILL; no ladder masks the unit ─────────────────────
echo ""; echo "─── (22) the real _selffence_hard_stop: state T or D -> systemctl stop --no-block, the unit's ActiveState read, SIGKILL, verify (no blocking stop, no SIGTERM, no mask); any other or unreadable state -> the normal ladder (stop, SIGTERM, SIGKILL; no mask) ───"
ladder_world() {   # ladder_world <script> <process state letter or empty> <rc of systemctl stop> [resurrect 1] [rc of stop --no-block, 0] [what the ActiveState read prints, deactivating] [out: line|msg|log|all|nb] -> rc=<rc>|branch=<_hs_branch>|status=<the last alert's status>|events=<STOP/STOPNB/SHOW/MASK/TERM/KILL9 in order>   (msg: the last alert's text; log: the INFO/WARN lines; all: the events with the sleeps; nb: the argv of the stop request)
    local script="$1" st="$2" rc_stop="$3" resurrect="${4:-0}" rc_nb="${5:-0}" as="${6-deactivating}" out="${7:-line}"
    (
        set +e
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VALIDATOR_TYPE="agave"; VALIDATOR_SERVICE="solana"
        SELF_FENCE_HARD_STOP=true; HARD_STOP_REVERIFY_SECS=7; TG_ENABLED=false
        EV=$(mktemp); trap 'rm -f "$EV" "$EV.dead" "$EV.log" "$EV.all" "$EV.nb"' EXIT
        log_info(){ echo "I $*" >> "$EV.log"; }; log_warn(){ echo "W $*" >> "$EV.log"; }; log_error(){ :; }; send_telegram(){ return 0; }; send_webhook(){ :; }; _watchdog_pet(){ :; }
        _STATUS=""; _MSG=""; alert(){ _MSG="$1"; _STATUS="$3"; }
        _PROC=1
        timeout(){   # runs in a $( ) subshell: "the stop worked" is a file, not a variable
            case "$*" in
                *systemctl\ stop\ --no-block*) echo STOPNB >> "$EV"; echo STOPNB >> "$EV.all"; echo "$*" >> "$EV.nb"; return "$rc_nb" ;;
                *systemctl\ stop*) echo STOP >> "$EV"; echo STOP >> "$EV.all"; [[ "$rc_stop" == "0" ]] && : > "$EV.dead"; return "$rc_stop" ;;
                *systemctl\ mask*) echo MASK >> "$EV"; echo MASK >> "$EV.all"; return 0 ;;
                *systemctl\ show*ActiveState*) echo SHOW >> "$EV"; echo SHOW >> "$EV.all"; printf '%s' "$as"; return 0 ;;
            esac
            return 0
        }
        pgrep(){ [[ "$_PROC" == "1" && ! -e "$EV.dead" ]] && echo 4242; return 0; }
        _proc_state(){ printf '%s' "$st"; }
        kill(){ if [[ "$1" == "-9" ]]; then echo KILL9 >> "$EV"; echo KILL9 >> "$EV.all"; _PROC=0; else echo TERM >> "$EV"; echo TERM >> "$EV.all"; fi; return 0; }   # SIGTERM is ignored: only SIGKILL ends the process
        sleep(){ echo "SLEEP $1" >> "$EV.all"; [[ "$1" == "$HARD_STOP_REVERIFY_SECS" && "$resurrect" == "1" ]] && _PROC=1; :; }
        _selffence_hard_stop "test wedge"; rc=$?
        case "$out" in
            msg) printf '%s' "$_MSG" ;;
            log) cat "$EV.log" 2>/dev/null ;;
            all) tr '\n' ',' < "$EV.all" ;;
            nb)  cat "$EV.nb" 2>/dev/null ;;
            *)   printf 'rc=%s|branch=%s|status=%s|events=%s\n' "$rc" "$_hs_branch" "$_STATUS" "$(tr '\n' ',' < "$EV")" ;;
        esac
    )
}
NB_BR="fast: process state T, blocking systemctl stop skipped (stop requested with --no-block)"
FAST_T="rc=0|branch=$NB_BR|status=PRIMARY SELF-FENCE — HARD STOP ✅|events=STOPNB,SHOW,KILL9,"
FAST_D="rc=0|branch=${NB_BR/state T/state D}|status=PRIMARY SELF-FENCE — HARD STOP ✅|events=STOPNB,SHOW,KILL9,"
NORM_S="rc=0|branch=normal ladder (process state S)|status=PRIMARY SELF-FENCE — HARD STOP ✅|events=STOP,TERM,KILL9,"
NORM_U="rc=0|branch=normal ladder (process state unknown)|status=PRIMARY SELF-FENCE — HARD STOP ✅|events=STOP,TERM,KILL9,"
p_fast_T() { [[ "$(ladder_world "$1" T 1)" == "$FAST_T" ]]; }
p_fast_D() { [[ "$(ladder_world "$1" D 1)" == "$FAST_D" ]]; }
p_normal_S() { [[ "$(ladder_world "$1" S 1)" == "$NORM_S" ]]; }
p_normal_unreadable() { [[ "$(ladder_world "$1" "" 1)" == "$NORM_U" ]]; }
p_fast_verified() { [[ "$(ladder_world "$1" T 1 1)" == "rc=1|branch=$NB_BR|status=PRIMARY SELF-FENCE — HARD STOP FAILED 🚨|events=STOPNB,SHOW,KILL9," ]]; }
l_t=$(ladder_world "$PRIMARY" T 1); l_d=$(ladder_world "$PRIMARY" D 1)
if [[ "$l_t" == "$FAST_T" && "$l_d" == "$FAST_D" ]]; then
    ok "(22a) state T and state D: NO blocking systemctl stop, NO SIGTERM and NO mask - the events are exactly 'STOPNB,SHOW,KILL9' (systemctl stop --no-block, the ActiveState read, then SIGKILL), rc 0, the branch reads 'fast: process state T|D, blocking systemctl stop skipped (stop requested with --no-block)', ONE ✅ page title (no '(unit masked)')"
else
    bad "(22a) fast branch: T=[$l_t] D=[$l_d]"
fi
l_s=$(ladder_world "$PRIMARY" S 1); l_s0=$(ladder_world "$PRIMARY" S 0); l_u=$(ladder_world "$PRIMARY" "" 1); l_r=$(ladder_world "$PRIMARY" R 1); l_tt=$(ladder_world "$PRIMARY" t 1); l_z=$(ladder_world "$PRIMARY" Z 1)
if [[ "$l_s" == "$NORM_S" && "$l_s0" == "rc=0|branch=normal ladder (process state S)|status=PRIMARY SELF-FENCE — HARD STOP ✅|events=STOP," && "$l_u" == "$NORM_U" \
      && "$l_r" == "${NORM_S//state S/state R}" && "$l_tt" == "${NORM_S//state S/state t}" && "$l_z" == "${NORM_S//state S/state Z}" ]]; then
    ok "(22b) state S (stop fails): STOP, TERM, KILL9 - the old order without the mask (v0.6.9 masked between STOP and TERM; rc1 F18 measured that mask inert and dropped it); state S with a clean stop: STOP only; an unreadable state, R, a tracing stop (t) and Z: the same normal ladder - the failure direction is the existing ladder, never a skipped stop"
else
    bad "(22b) normal ladder: S=[$l_s] S0=[$l_s0] unreadable=[$l_u] R=[$l_r] t=[$l_tt] Z=[$l_z]"
fi
if p_fast_verified "$PRIMARY"; then
    ok "(22c) the fast branch still re-verifies: a validator that is back after HARD_STOP_REVERIFY_SECS makes the stop FAIL (rc 1, 'HARD STOP FAILED' page) - the fast branch skips the blocking stop, not the proof"
else
    bad "(22c) fast branch + resurrect: $(ladder_world "$PRIMARY" T 1 1)"
fi
ps_t=$(printf 'Name:\tagave-validator\nUmask:\t0022\nState:\tT (stopped)\nTgid:\t1\n'); ps_d=$(printf 'State:\tD (disk sleep)\n'); ps_s=$(printf 'State:\tS (sleeping)\n')
ps_run() {   # ps_run <script> <the status file's text, or "-" for no file> <pid argument> -> what _proc_state answers (PROC_ROOT stands in for /proc)
    local script="$1" txt="$2" arg="$3" src d; src=$(cut_src "$script"); d=$(mktemp -d)
    (
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        if [[ "$txt" != "-" ]]; then mkdir -p "$d/4242"; printf '%s\n' "$txt" > "$d/4242/status"; fi
        PROC_ROOT="$d"; _proc_state "$arg"
    ); rm -rf "$d"
}
pr1=$(ps_run "$PRIMARY" "$ps_t" 4242); pr2=$(ps_run "$PRIMARY" "$ps_d" 4242); pr3=$(ps_run "$PRIMARY" "$ps_s" 4242); pr4=$(ps_run "$PRIMARY" "-" 4242); pr5=$(ps_run "$PRIMARY" "$ps_t" abc); pr6=$(ps_run "$PRIMARY" "no state line here" 4242)
p_proc_state() { [[ "$(ps_run "$1" "$ps_t" 4242)" == "T" ]]; }
if [[ "$pr1" == "T" && "$pr2" == "D" && "$pr3" == "S" && "$pr4" == "" && "$pr5" == "" && "$pr6" == "" ]]; then
    ok "(22d) _proc_state reads the letter after 'State:' in /proc/<pid>/status (T, D, S); a missing file, a non-numeric pid and a file without a State line answer nothing (so the ladder takes the normal branch)"
else
    bad "(22d) _proc_state: T=[$pr1] D=[$pr2] S=[$pr3] missing=[$pr4] abc=[$pr5] noline=[$pr6]"
fi


# (22e) rc1 F18: the stop request comes BEFORE the SIGKILL and nothing sleeps between them (the whole point: a queued stop job is what Restart= respects, and the process must not get time to be restarted or to flush); the sleeps are the verify's 1 s and the re-verify's HARD_STOP_REVERIFY_SECS
a_t=$(ladder_world "$PRIMARY" T 1 0 0 deactivating all); a_d=$(ladder_world "$PRIMARY" D 1 0 0 deactivating all); a_s=$(ladder_world "$PRIMARY" S 1 0 0 deactivating all)
nb_t=$(ladder_world "$PRIMARY" T 1 0 0 deactivating nb); nb_d=$(ladder_world "$PRIMARY" D 1 0 0 deactivating nb)
if [[ "$a_t" == "STOPNB,SHOW,KILL9,SLEEP 1,SLEEP 7," && "$a_d" == "STOPNB,SHOW,KILL9,SLEEP 1,SLEEP 7," && "$a_s" == "STOP,TERM,SLEEP 2,KILL9,SLEEP 1,SLEEP 7," \
      && "$nb_t" == "-k 5 15 systemctl stop --no-block solana" && "$nb_d" == "$nb_t" ]]; then
    ok "(22e) the fast branch (T and D) runs 'timeout -k 5 15 systemctl stop --no-block solana' (the validator's unit), the ActiveState read and then SIGKILL back to back - no sleep between the request and the kill; the normal ladder is STOP, TERM, 2 s, KILL9, 1 s, the re-verify - no mask call in either"
else
    bad "(22e) order: T=[$a_t] D=[$a_d] S=[$a_s] request argv: T=[$nb_t] D=[$nb_d]"
fi
# (22f) the ActiveState read only RECORDS: deactivating / inactive / failed -> one INFO line; anything else (active, activating, nothing readable) -> exactly one WARN line; a stop request that failed -> one WARN line and no read; the kill proceeds in every case
f_ok=1; f_why=""
for as in deactivating inactive failed; do
    lg=$(ladder_world "$PRIMARY" T 1 0 0 "$as" log); ev=$(ladder_world "$PRIMARY" T 1 0 0 "$as")
    if [[ "$(printf '%s\n' "$lg" | grep -c -F "I [self-fence] unit solana reads ActiveState=$as after the stop request")" != "1" || "$(printf '%s\n' "$lg" | grep -c '^W .*ActiveState')" != "0" \
          || "$(printf '%s\n' "$lg" | grep -c -F 'I [self-fence] systemctl stop --no-block solana: rc 0')" != "1" || "$ev" != "$FAST_T" ]]; then f_ok=0; f_why="$f_why [$as: $(printf '%s' "$lg" | tr '\n' ';' | cut -c1-300)]"; fi
done
for as in active activating ""; do
    lg=$(ladder_world "$PRIMARY" T 1 0 0 "$as" log); ev=$(ladder_world "$PRIMARY" T 1 0 0 "$as"); shown="${as:-unreadable}"
    if [[ "$(printf '%s\n' "$lg" | grep -c -F "W [self-fence] unit solana reads ActiveState='$shown' after the stop request (expected deactivating, inactive or failed)")" != "1" || "$(printf '%s\n' "$lg" | grep -c '^W .*ActiveState')" != "1" \
          || "$ev" != "$FAST_T" ]]; then f_ok=0; f_why="$f_why [${as:-empty}: $(printf '%s' "$lg" | tr '\n' ';' | cut -c1-300) :: $ev]"; fi
done
lg=$(ladder_world "$PRIMARY" T 1 0 124 deactivating log); ev=$(ladder_world "$PRIMARY" T 1 0 124 deactivating)
if [[ "$(printf '%s\n' "$lg" | grep -c -F 'W [self-fence] systemctl stop --no-block failed (rc 124)')" != "1" || "$(printf '%s\n' "$lg" | grep -c 'ActiveState')" != "0" \
      || "$ev" != "rc=0|branch=$NB_BR|status=PRIMARY SELF-FENCE — HARD STOP ✅|events=STOPNB,KILL9," ]]; then f_ok=0; f_why="$f_why [rc124: $(printf '%s' "$lg" | tr '\n' ';' | cut -c1-300) :: $ev]"; fi
if [[ $f_ok -eq 1 ]]; then
    ok "(22f) the stop request's rc is logged (INFO 'systemctl stop --no-block solana: rc 0'); the unit's ActiveState after it: deactivating / inactive / failed = one INFO line, active / activating / unreadable = exactly one WARN line, a failed request = one WARN line and no read - and the SIGKILL, the verify and the ✅ follow in every case (the re-verify is the catch)"
else
    bad "(22f) ActiveState / request-rc logging:$f_why"
fi
# (22g) the pages: ONE ✅ page (the same text on every path - no '(unit masked)' title), it says how to recover (systemctl start, on the UNSTAKED identity, Restart= does not apply) and mentions no mask; the resurrected-validator page says 'systemctl stop <unit>'
m_f=$(ladder_world "$PRIMARY" T 1 0 0 deactivating msg); m_n=$(ladder_world "$PRIMARY" S 1 0 0 deactivating msg); m_c=$(ladder_world "$PRIMARY" S 0 0 0 deactivating msg)
m_rf=$(ladder_world "$PRIMARY" T 1 1 0 deactivating msg); m_rn=$(ladder_world "$PRIMARY" S 1 1 0 deactivating msg)
p_pages() {   # the five pages, read by the caller
    [[ "$m_f" == "$m_n" && "$m_n" == "$m_c" && "$m_f" == *"confirmed DOWN (re-verified after 7s). The unit is stopped by a requested stop (Restart= does not apply): recover with 'systemctl start solana' on the UNSTAKED identity after confirming no spare holds the staked identity"* \
      && "$m_rf" == *"INTERVENE NOW (systemctl stop solana)."* && "$m_rn" == *"INTERVENE NOW (systemctl stop solana)."* \
      && -z "$(printf '%s\n%s\n%s\n%s\n%s' "$m_f" "$m_n" "$m_c" "$m_rf" "$m_rn" | grep -i 'mask')" ]]
}
if p_pages; then
    ok "(22g) one ✅ page on every path (fast, normal with a failed stop, normal with a clean stop): 'The unit is stopped by a requested stop (Restart= does not apply): recover with systemctl start solana on the UNSTAKED identity after confirming no spare holds the staked identity'; the resurrected-validator page says 'INTERVENE NOW (systemctl stop solana).'; none of the five mentions a mask"
else
    bad "(22g) pages: fast=[$m_f] normal=[$m_n] clean=[$m_c] resurrect-fast=[$m_rf] resurrect-normal=[$m_rn]"
fi
# (22h) structure: neither ladder's CODE mentions a mask (v0.6.9's step and its flag, mask_out / mask_rc / masked, are gone from both daemons)
p_no_mask_code() { [[ "$(sed -n '/^_selffence_hard_stop() {/,/^}/p' "$1" | grep -v '^[[:space:]]*#' | grep -ci 'mask')" == "0" ]]; }
if p_no_mask_code "$PRIMARY" && p_no_mask_code "$STANDBY"; then
    ok "(22h) no 'mask' in the code of either daemon's _selffence_hard_stop (comment lines excluded): the step, its variables and both '(unit masked)' pages are gone"
else
    bad "(22h) a mask survives in a ladder: primary=$(sed -n '/^_selffence_hard_stop() {/,/^}/p' "$PRIMARY" | grep -v '^[[:space:]]*#' | grep -ci 'mask') standby=$(sed -n '/^_selffence_hard_stop() {/,/^}/p' "$STANDBY" | grep -v '^[[:space:]]*#' | grep -ci 'mask')"
fi


# ── (23) the rung's TIMELINE, from the code: the real loop and the real ladder over a simulated clock (the figures in SAFETY and in the knob comment are claims; this is their check) ──
echo ""; echo "─── (23) the rung's timeline: the real main loop and the real ladder over a file clock - the clock reads 0 / 12 / 23 / 34 s, the validator is dead 48 to 51 s after the hang (fast branch), 70 to 73 s (normal ladder, stop wedged) ───"
rung_timeline() {   # rung_timeline <script> <knob> <phi> <fast|healthy|wedged> <external read s> [agave|frankendancer] -> "stamp=<s after the hang> n=<the decision's clock> start=<the ladder starts, s after the hang> down=<the validator is dead, s after the hang>"
    local script="$1" knob="$2" phi="$3" ladder="$4" sample="${5:-1}" vt="${6:-agave}" cs region
    cs=$(cut_src "$script"); region=$(extract_region "$script" '^while \$_running; do' '^done$') || { echo "NO-REGION"; return 0; }
    (
        set +e
        EVF=$(mktemp); CLK=$(mktemp); echo 1000 > "$CLK"; rm -f "$CLK.dead"; export EVF CLK   # 1000: the clock never reads 0 (a 0 stamp means unset)
        trap 'rm -f "$EVF" "$CLK" "$CLK.dead"' EXIT
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        eval "run_loop() {
$region
}"
        # the clock is a FILE: every bounded call below advances it by what the real call would take, so the $( ) subshells of the loop count too
        mono_now() { cat "$CLK"; }
        adv() { echo $(( $(cat "$CLK") + $1 )) > "$CLK"; }
        ev() { printf '%s\n' "$*" >> "$EVF"; }
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; UNSTAKED_KEYPAIR="$EVF"; LEDGER_PATH="$EVF.ledger"; VALIDATOR_TYPE="$vt"; VALIDATOR_SERVICE=solana
        LOCAL_RPC="http://127.0.0.1:8899"; SOLANA_PATH="$EVF.bin"
        TG_ENABLED=false; DRY_RUN=false; ALERT_THROTTLE=600; PRIMARY_SELF_FENCE=true      # CHECK_INTERVAL, TURBO_INTERVAL, SETIDENTITY_TIMEOUT, HARD_STOP_REVERIFY_SECS: the shipped defaults
        CONNECTIVITY_RETRIES=99; MAX_VOTE_LATENCY=0; DELINQUENCY_RETRIES=1; STARTUP_GRACE=30; RECOVERY_MODE=manual
        HOLDER_UNREACHABLE_STOP_SECS="$knob"; SELF_FENCE_HARD_STOP=true
        CYCLE=0; _last_heartbeat=$(date +%s); HEARTBEAT_INTERVAL=2000000000; _last_known_identity="$STK"
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _version_startup_check() { :; }; _vat_cycle() { :; }; _fence_rot_check() { :; }; _g2_step() { :; }; _elapsed_step() { :; }
        flush_pending_alerts() { :; }; display_status() { :; }; save_state() { :; }; _watchdog_pet() { :; }; send_telegram() { return 0; }; send_webhook() { :; }
        log_info() { :; }; log_error() { :; }
        log_warn() { case "$1" in *"[hung] the validator's identity is unreadable while STAKED"*) ev "STAMP $(mono_now)" ;; esac; }
        alert() { return 0; }; alert_info() { :; }; alert_warn() { :; }
        check_internet() { return 0; }; check_self_fence_isolation() { return 1; }; check_identity_collision() { return 0; }; tier1_check_delinquency() { return 1; }
        tier1_get_vote_latency() { echo 1; }; verify_latency_tiered() { return 0; }; _vat_hold() { return 1; }
        window_push() { :; }; window_count() { echo 0; }; window_triggered() { return 1; }; window_mostly_clear() { return 1; }; window_reset() { :; }
        switch_to_unstaked() { return 0; }
        # the shipped calls, over the mocked world: curl and timeout run to their own -m / T bound (a SIGSTOPped validator accepts the connection and never answers)
        curl() { local m=0; while [[ $# -gt 0 ]]; do case "$1" in -m) m="$2"; shift ;; esac; shift; done; adv "$m"; return 28; }
        timeout() {   # timeout [-k K] T cmd... - K is the kill grace: a command that ignores TERM runs T + K s
            local k=0 t
            [[ "$1" == "-k" ]] && { k="$2"; shift 2; }
            t="$1"; shift
            case "$*" in
                *contact-info*) adv "$t"; return 124 ;;   # the admin socket of a hung validator: the read runs into its bound
                *systemctl\ stop\ --no-block*) return 0 ;;   # rc1 F18: the fast branch's stop request returns at once (the host's own work counted as zero, like the rest of the model)
                *systemctl\ stop*)
                    case "$ladder" in
                        healthy) adv 2; echo "$(mono_now)" > "$CLK.dead"; return 0 ;;   # the stop takes 2 s and works
                        *)       adv $(( t + k )); return 124 ;;                       # wedged: the bound, then the kill grace
                    esac ;;
            esac
            return 0
        }
        _hung_local_slot_real=$(declare -f _hung_local_slot | sed '1s/_hung_local_slot/_hung_local_slot_real/'); eval "$_hung_local_slot_real"
        _hung_local_slot() { ev "SLOT $(mono_now)"; _hung_local_slot_real; }
        get_staked_liveness_sample() { local d; adv "$sample"; d=$(mono_now); printf '5000 %s T2\n' $(( 9000 + d )); }   # the external read: lastVote frozen, the tip advancing
        eval "$(declare -f get_local_identity | sed '1s/get_local_identity/_gli_real/')"
        get_local_identity() { if [[ $CYCLE -eq 0 ]]; then echo "$STAKED_PUBKEY"; else _gli_real; fi; }   # cycle 0 is healthy; then the hang: the read runs into its bound
        case "$ladder" in fast) PSTATE=T ;; *) PSTATE=S ;; esac
        _proc_state() { printf '%s' "$PSTATE"; }
        _proc_start_secs() { printf '%s' 1; }   # the validator has been running since long before the last readable read (AG-3.8d)
        pgrep() { [[ -e "$CLK.dead" ]] || echo 4242; return 0; }
        kill() { if [[ "$1" == "-9" ]]; then echo "$(mono_now)" > "$CLK.dead"; fi; return 0; }   # a hung process ignores TERM; only SIGKILL ends it
        sleep() { adv "$1"; }
        eval "$(declare -f _selffence_hard_stop | sed '1s/_selffence_hard_stop/_orig_hs/')"
        _selffence_hard_stop() { ev "LADDER_START $(mono_now)"; _orig_hs "$@"; local rc=$?; ev "LADDER_END $(mono_now) rc=$rc"; return $rc; }
        _watchdog_sleep() { adv "$1"; CYCLE=$(( CYCLE + 1 )); [[ -e "$CLK.dead" && $(cat "$CLK") -ge $(cat "$CLK.dead") ]] && _running=false; [[ $CYCLE -gt 40 ]] && _running=false; }
        _current_interval=$CHECK_INTERVAL
        # the hang H is PHI s before the first cycle that finds it: cycle 0 is healthy and ends with its sleep, cycle 1 starts at CHECK_INTERVAL
        local t1=$CHECK_INTERVAL H stamp slot lad down
        H=$(( 1000 + t1 - phi ))
        _running=true; run_loop
        stamp=$(grep '^STAMP' "$EVF" | head -1 | cut -d' ' -f2); slot=$(grep '^SLOT' "$EVF" | head -1 | cut -d' ' -f2); lad=$(grep '^LADDER_START' "$EVF" | head -1 | cut -d' ' -f2)
        down=$(cat "$CLK.dead" 2>/dev/null)
        if [[ -n "$stamp" && -n "$slot" && -n "$lad" && -n "$down" ]]; then
            printf 'stamp=%s n=%s start=%s down=%s\n' $(( stamp - H )) $(( slot - stamp )) $(( lad - H )) $(( down - H ))
        else
            printf 'NO-DECISION stamp=[%s] slot=[%s] ladder=[%s] down=[%s]\n' "$stamp" "$slot" "$lad" "$down"
        fi
    )
}
tl_ok=1; tl_bad=""
tl_expect() {   # tl_expect <expected line> <script> <rung_timeline args...>
    local want="$1" got; shift
    got=$(rung_timeline "$@")
    [[ "$got" == "$want" ]] || { tl_ok=0; tl_bad="$tl_bad [$* -> $got, want $want]"; }
}
# (23a) the default knob 30 on the fast branch (state T): the hang lands 0..3 s before a cycle starts; the first failed read ends 8..11 s after it; the clock reads 0 / 12 / 23 / 34 (the first cycle also takes the 1 s baseline read)
for phi in 0 1 2 3; do tl_expect "stamp=$((8 + phi)) n=34 start=$((48 + phi)) down=$((48 + phi))" "$PRIMARY" 30 $phi fast 1; done
if [[ $tl_ok -eq 1 ]]; then
    ok "(23a) HOLDER_UNREACHABLE_STOP_SECS=30, a stopped validator (state T), the hang 0..3 s before a cycle: the first failed identity read ends 8 to 11 s after the hang, the rung decides on the 4th reading (n=34, the clock 0 / 12 / 23 / 34), and the validator is dead 48 to 51 s after the hang (the fast branch kills at once)"
else
    bad "(23a) the default rung timeline moved:$tl_bad"
fi
# (23b) the normal ladder: a stop that works in 2 s, and a stop that is wedged for its whole bound (timeout -k 5 15 = 20 s, then the 2 s after SIGTERM before SIGKILL)
tl_ok=1; tl_bad=""
for phi in 0 3; do
    tl_expect "stamp=$((8 + phi)) n=34 start=$((48 + phi)) down=$((50 + phi))" "$PRIMARY" 30 $phi healthy 1
    tl_expect "stamp=$((8 + phi)) n=34 start=$((48 + phi)) down=$((70 + phi))" "$PRIMARY" 30 $phi wedged 1
done
if [[ $tl_ok -eq 1 ]]; then
    ok "(23b) the normal ladder (state S): the validator is dead 50 to 53 s after the hang when 'systemctl stop' returns after 2 s, 70 to 73 s when it is wedged for its whole bound (15 s + 5 s kill grace, then SIGTERM, 2 s, SIGKILL)"
else
    bad "(23b) the normal ladder's timeline moved:$tl_bad"
fi
# (23c) the clock is quantised: every knob from 13 to 23 acts on the 3rd reading (n=23), every knob from 24 to 34 on the 4th (n=34)
tl_ok=1; tl_bad=""
for k in 13 20 22 23; do tl_expect "stamp=8 n=23 start=37 down=37" "$PRIMARY" $k 0 fast 1; done
for k in 24 30 34; do tl_expect "stamp=8 n=34 start=48 down=48" "$PRIMARY" $k 0 fast 1; done
tl_expect "stamp=8 n=45 start=59 down=59" "$PRIMARY" 35 0 fast 1
if [[ $tl_ok -eq 1 ]]; then
    ok "(23c) the rung's clock moves in whole readings: a knob of 13, 20, 22 or 23 decides at n=23 (the 20 floor is in the same band as 13), 24 to 34 at n=34, 35 at n=45"
else
    bad "(23c) the quantisation moved:$tl_bad"
fi
# (23d) Frankendancer: the identity read is an RPC bounded at 5 s, so the cycles are 8 s apart: the clock reads 0 / 9 / 17 / 25 / 33
tl_ok=1; tl_bad=""
for phi in 0 3; do
    tl_expect "stamp=$((5 + phi)) n=33 start=$((44 + phi)) down=$((44 + phi))" "$PRIMARY" 30 $phi fast 1 frankendancer
    tl_expect "stamp=$((5 + phi)) n=33 start=$((44 + phi)) down=$((66 + phi))" "$PRIMARY" 30 $phi wedged 1 frankendancer
done
tl_expect "stamp=5 n=25 start=36 down=36" "$PRIMARY" 22 0 fast 1 frankendancer
if [[ $tl_ok -eq 1 ]]; then
    ok "(23d) Frankendancer (the identity read is a 5 s RPC): the clock reads 0 / 9 / 17 / 25 / 33, the default knob decides at n=33 and the validator is dead 44 to 47 s after the hang (fast), 66 to 69 s (stop wedged); a knob of 22 decides at n=25"
else
    bad "(23d) the Frankendancer timeline moved:$tl_bad"
fi
# (23e) the external read of the vote account is the one figure the code cannot bound by itself (two providers, a network): every second it takes beyond 1 s moves the whole timeline by a second
tl_ok=1; tl_bad=""
tl_expect "stamp=8 n=33 start=46 down=46" "$PRIMARY" 30 0 fast 0
tl_expect "stamp=8 n=35 start=50 down=50" "$PRIMARY" 30 0 fast 2
if [[ $tl_ok -eq 1 ]]; then
    ok "(23e) the external read's cost moves the numbers (the figure the texts call 'about 1 s'): free = n=33, dead 46 s after the hang; 2 s = n=35, dead 50 s"
else
    bad "(23e) the external-read sensitivity moved:$tl_bad"
fi
p_timeline_all() {   # p_timeline_all <script> - one case from each of (23a)-(23d): the mutants of the figures' sources (the bounds in the code) turn it red
    local s="$1"
    [[ "$(rung_timeline "$s" 30 0 fast 1)" == "stamp=8 n=34 start=48 down=48" ]] \
      && [[ "$(rung_timeline "$s" 30 3 healthy 1)" == "stamp=11 n=34 start=51 down=53" ]] \
      && [[ "$(rung_timeline "$s" 30 0 wedged 1)" == "stamp=8 n=34 start=48 down=70" ]] \
      && [[ "$(rung_timeline "$s" 22 0 fast 1)" == "stamp=8 n=23 start=37 down=37" ]] \
      && [[ "$(rung_timeline "$s" 30 3 fast 1 frankendancer)" == "stamp=8 n=33 start=47 down=47" ]]
}


# ── (24) AG-3.8d: a validator that RESTARTED since the last readable identity read is not hung ──────────────────────────────────
echo ""; echo "─── (24) a restarted validator (its process started at or after the last readable identity read) is never stopped by the rung; an unreadable start time is a doubt, not a verdict ───"
# The class (AG-3.8's limit, §13.9 of the package): crash -> systemd restarts the unit on the unstaked identity -> the new process loads its ledger for minutes (identity unreadable, LOCAL RPC silent,
# lastVote frozen). The pid taken at the first unreadable cycle IS the new process, so "the process changed during the episode" never fires - the start time against the last readable read does.
p_restart_not_hung() {   # no stop, no rung page, no external or local read, no admin call; ONE INFO line says why
    local e="$1"
    [[ "$(hs_n "$e")" == "0" && "$(wp_n "$e")" == "0" && "$(n_of "$e" '^PAGE HOLDER')" == "0" && "$(n_of "$e" '^SAMPLE')" == "0" && "$(n_of "$e" '^LOCALSLOT')" == "0" && "$(n_of "$e" '^ADMIN')" == "0" \
       && "$(printf '%s\n' "$e" | grep -c -F 'LOG [hung] validator restarted (new process, pid 4242, started 2 s after the last readable identity read) - not hung')" == "1" ]]
}
p_cannot_tell() { reason_kept "$1" 'cannot tell a hung validator from a restarted one'; }
ev24a=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen STARTMODE=new)
ev24a_long=$(gap_world "$PRIMARY" "S X X X X X X X X X X X X X X X X X X X" XREAD=8 LVMODE=frozen STARTMODE=new)
if p_restart_not_hung "$ev24a" && p_restart_not_hung "$ev24a_long"; then
    ok "(24a) the process started 2 s after the last readable read (a restart): over 8 unreadable cycles - and over 19, far past the knob - NO hard stop, NO external or local read, NO rung page, and exactly ONE INFO line 'validator restarted (new process, pid 4242, started 2 s after the last readable identity read) - not hung'"
else
    bad "(24a) restarted validator: hardstops=$(hs_n "$ev24a") samples=$(n_of "$ev24a" '^SAMPLE') wpages=$(wp_n "$ev24a") info=$(printf '%s' "$ev24a" | grep -c 'validator restarted') (long: hardstops=$(hs_n "$ev24a_long") info=$(printf '%s' "$ev24a_long" | grep -c 'validator restarted')) :: $(printf '%s' "$ev24a" | grep -E '^(HARDSTOP|WPAGE|LOG)' | tr '\n' ';' | cut -c1-260)"
fi
ev24h=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen STARTMODE=old)
ev24s=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen STARTMODE=sec_before)
if p_hung_stop "$ev24h" && p_hung_stop "$ev24s" && [[ "$(printf '%s' "$ev24h$ev24s" | grep -c 'validator restarted')" == "0" ]]; then
    ok "(24b) the same process (started long before the last readable read, and 1 s before it): the rung works exactly as before - ONE hard stop at N=33, the page after it, no 'restarted' line"
else
    bad "(24b) same process: old: hardstops=$(hs_n "$ev24h") / 1 s before: hardstops=$(hs_n "$ev24s") :: $(printf '%s' "$ev24s" | grep -E '^(HARDSTOP|WPAGE|LOG)' | tr '\n' ';' | cut -c1-200)"
fi
ev24e=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen STARTMODE=at_read)
p_at_read_restarted() { [[ "$(printf '%s\n' "$1" | grep -c -F 'LOG [hung] validator restarted (new process, pid 4242, started 0 s after the last readable identity read) - not hung')" == "1" && "$(hs_n "$1")" == "0" && "$(wp_n "$1")" == "0" ]]; }
if p_at_read_restarted "$ev24e"; then
    ok "(24c) the boundary: a process that started in the SAME second as the last readable read counts as restarted (>=): no stop, one INFO line ('started 0 s after') - the doubt goes the way that cannot kill a booting validator"
else
    bad "(24c) boundary: hardstops=$(hs_n "$ev24e") :: $(printf '%s' "$ev24e" | grep -E '^(HARDSTOP|WPAGE|LOG)' | tr '\n' ';' | cut -c1-240)"
fi
ev24u=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen STARTMODE=none)
ev24f=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen STARTMODE=future)
ev24ud=$(gap_world "$PRIMARY" "$PL9" XREAD=8 LVMODE=frozen STARTMODE=none DRY_RUN=true)
if p_cannot_tell "$ev24u" && p_cannot_tell "$ev24f" && [[ "$(hs_n "$ev24ud")" == "0" && "$(printf '%s\n' "$ev24ud" | grep -c -F 'WPAGE HOLDER UNREACHABLE — not stopped (cannot tell a hung validator from a restarted one')" == "1" && "$(n_of "$ev24ud" '^PAGE .*WOULD HARD-STOP')" == "0" ]]; then
    ok "(24d) the start time is unreadable (no stat file, or a time LATER than now - impossible): NO stop, ONE throttled 'HOLDER UNREACHABLE — not stopped (cannot tell a hung validator from a restarted one: the start time of pid 4242 is unreadable)' page; under DRY_RUN the same page and no 'WOULD HARD-STOP' page"
else
    bad "(24d) unreadable start: none: hardstops=$(hs_n "$ev24u") wpages=$(wp_n "$ev24u") / future: hardstops=$(hs_n "$ev24f") wpages=$(wp_n "$ev24f") / dry: $(printf '%s' "$ev24ud" | grep -E '^(HARDSTOP|WPAGE|PAGE)' | tr '\n' ';' | cut -c1-240)"
fi
ev24r=$(gap_world "$PRIMARY" "S X X X S X X X X X X X X" XREAD=8 LVMODE=frozen STARTMODE=new_then_old)
if [[ "$(printf '%s\n' "$ev24r" | grep -c -F 'LOG [hung] validator restarted')" == "1" && "$(hs_n "$ev24r")" == "1" && "$(n_of "$ev24r" '^PAGE HOLDER HUNG — HARD STOP 🚨$')" == "1" ]]; then
    ok "(24e) the restart closes only ITS episode: the identity reads again (the rung is re-armed and the read time moves), a later hang of the SAME unit - a process that started before that read - is stopped once, as before"
else
    bad "(24e) restart then hang: restarted-lines=$(printf '%s' "$ev24r" | grep -c 'validator restarted') hardstops=$(hs_n "$ev24r") :: $(printf '%s' "$ev24r" | grep -E '^(HARDSTOP|WPAGE|LOG)' | tr '\n' ';' | cut -c1-260)"
fi
# the real _proc_start_secs over a fixture /proc: field 22 of the stat line (ticks since boot) / CLK_TCK
mk_stat() {   # mk_stat <comm> <starttime ticks> -> a /proc/<pid>/stat line (52 fields; the 22nd is the start time)
    printf '4242 (%s) S 1 4242 4242 0 -1 4194560 100 0 0 0 1234 56 0 0 20 0 80 0 %s 123456789 4500 18446744073709551615 1 1 0 0 0 0 0 4096 0 0 0 0 17 3 0 0 0 0 0 0 0 0 0 0 0 0 0' "$1" "$2"
}
ps_start() {   # ps_start <script> <stat line, or "-" for no file> <pid argument> [100|250|garbage|none: what getconf CLK_TCK answers] -> what _proc_start_secs prints
    local script="$1" txt="$2" arg="$3" hz="${4:-100}" src d; src=$(cut_src "$script"); d=$(mktemp -d)
    (
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        if [[ "$txt" != "-" ]]; then mkdir -p "$d/4242"; printf '%s\n' "$txt" > "$d/4242/stat"; fi
        case "$hz" in garbage) getconf() { printf 'lots'; } ;; none) getconf() { return 1; } ;; *) getconf() { printf '%s' "$hz"; } ;; esac
        PROC_ROOT="$d"; _proc_start_secs "$arg" 2>/dev/null
    ); rm -rf "$d"
}
p_start_parse() {   # the shipped parser, one case each
    local s="$1"
    [[ "$(ps_start "$s" "$(mk_stat agave-validator 987654)" 4242)" == "9876" \
       && "$(ps_start "$s" "$(mk_stat 'agave (validator) x' 987654)" 4242)" == "9876" \
       && "$(ps_start "$s" "$(mk_stat agave-validator 987654)" 4242 250)" == "3950" \
       && "$(ps_start "$s" "$(mk_stat agave-validator 987654)" 4242 garbage)" == "9876" \
       && "$(ps_start "$s" "$(mk_stat agave-validator 987654)" 4242 none)" == "9876" ]]
}
p_start_empty() {   # unreadable or malformed: prints nothing
    local s="$1"
    [[ -z "$(ps_start "$s" "-" 4242)" && -z "$(ps_start "$s" "$(mk_stat agave-validator 987654)" abc)" && -z "$(ps_start "$s" "4242 (agave-validator) S 1 4242" 4242)" \
       && -z "$(ps_start "$s" "$(mk_stat agave-validator 12x4)" 4242)" && -z "$(ps_start "$s" "no parenthesis at all in this line" 4242)" ]]
}
if p_start_parse "$PRIMARY" && p_start_empty "$PRIMARY"; then
    ok "(24f) _proc_start_secs reads the 22nd field of /proc/<pid>/stat over CLK_TCK (987654 ticks = 9876 s at 100, 3950 s at 250; getconf answering garbage or nothing = 100), even when comm holds spaces and parentheses; a missing file, a non-numeric pid, a short line, a non-numeric start time and a line without a parenthesis print nothing"
else
    bad "(24f) _proc_start_secs: plain=[$(ps_start "$PRIMARY" "$(mk_stat agave-validator 987654)" 4242)] parens=[$(ps_start "$PRIMARY" "$(mk_stat 'agave (validator) x' 987654)" 4242)] hz250=[$(ps_start "$PRIMARY" "$(mk_stat agave-validator 987654)" 4242 250)] garbage=[$(ps_start "$PRIMARY" "$(mk_stat agave-validator 987654)" 4242 garbage)] nofile=[$(ps_start "$PRIMARY" "-" 4242)] short=[$(ps_start "$PRIMARY" "4242 (agave-validator) S 1 4242" 4242)]"
fi
p_reset_stamps() { local lp; lp=$(sed -n '/^_hung_reset() {/,/^}/p' "$1"); [[ "$(printf '%s\n' "$lp" | grep -c -F '_hung_read_ts=$(mono_now)')" == "1" ]]; }
p_sb_none() { [[ "$(grep -c -E '_proc_start_secs|_hung_read_ts|_hung_start' "$STANDBY")" == "0" ]]; }
if p_reset_stamps "$PRIMARY" && p_sb_none; then
    ok "(24g) structure: _hung_reset stamps the time of the last readable identity read ('_hung_read_ts=\$(mono_now)', once); the standby has no _proc_start_secs, no _hung_read_ts, no _hung_start"
else
    bad "(24g) structure: reset-stamps=$(p_reset_stamps "$PRIMARY" && echo yes || echo no) standby-clean=$(p_sb_none && echo yes || echo no)"
fi


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
ctl_sb sb-knob-assigned 's/^AG_ARMED_TAKE=false/HOLDER_GAP_DEMOTE_SECS=45; AG_ARMED_TAKE=false/'
ctl_sb sb-knob-expanded 's/^AG_ARMED_TAKE=false/: "$HOLDER_GAP_DEMOTE_SECS"; AG_ARMED_TAKE=false/'
ctl_sb sb-stamp 's/^AG_ARMED_TAKE=false/_cycle_end_ts=0; AG_ARMED_TAKE=false/'
ctl_sb sb-latch 's/^AG_ARMED_TAKE=false/_gap_latch; AG_ARMED_TAKE=false/'
ctl_sb sb-demote 's/^AG_ARMED_TAKE=false/_gap_demote; AG_ARMED_TAKE=false/'
# AG-3.8: the hung-holder rung's mutants. HG limits a sed expression to _hung_check's body; every mutant must turn its case red
HG='/^_hung_check() {/,/^}/ '
LG='/^_selffence_hard_stop() {/,/^}/ '
ctl hung-not-wired '/^        _hung_check   # v0.7 (AG-3.8)/d' "$PL9" p_hung_stop XREAD=8 LVMODE=frozen
ctl hung-no-reset '/^    _hung_reset   # v0.7 (AG-3.8)/d' "S X X X S X X X" p_readable_again XREAD=8 LVMODE=frozen
ctl hung-gt-not-ge 's/if \[\[ \$n -lt \$HOLDER_UNREACHABLE_STOP_SECS \]\]; then/if [[ $n -le $HOLDER_UNREACHABLE_STOP_SECS ]]; then/' "$PL9" p_boundary_hung XREAD=10 LVMODE=frozen HOLDER_UNREACHABLE_STOP_SECS=39
ctl hung-baseline-not-taken "$HG"'s/^        if _hung_sample; then _hung_rebase "\$now"; fi$/        :/' "$PL9" p_hung_stop XREAD=8 LVMODE=frozen
ctl hung-no-growth-check "$HG"'s/-gt \${VOTE_LIVENESS_EPSILON:-0}/-gt 999999999/' "$PL9" p_growing_kept XREAD=8 LVMODE=growing
ctl hung-no-slot-check "$HG"'s/^            if \[\[ -n "\$slot" \]\]; then$/            if false; then/' "$PL9" p_answers_kept XREAD=8 LVMODE=frozen SLOTMODE=answers
ctl hung-down-is-frozen "$HG"'s/why="no external RPC answered the vote-account read"/why=""/' "$PL9" p_down_kept XREAD=8 LVMODE=down
ctl hung-no-pid-check "$HG"'s/^        elif \[\[ "\$pid1" != "\$_hung_pid0" \]\]; then$/        elif false; then/' "$PL9" p_restart_kept XREAD=8 LVMODE=frozen PIDMODE=changed
ctl hung-no-busy-check "$HG"'s/^    elif busy=\$(_hung_unit_busy); then$/    elif false; then/' "$PL9" p_busy_kept XREAD=8 LVMODE=frozen UNITBUSY=deactivating
ctl hung-no-tip-check "$HG"'s/^            elif \[\[ \$_hs_ref -le \$_hung_lv_tip \]\]; then$/            elif false; then/' "$PL9" p_stale_kept XREAD=8 LVMODE=stale
ctl hung-no-dry-guard "$HG"'s/^    if \[\[ "\$DRY_RUN" == "true" \]\]; then$/    if false; then/' "$PL9" p_dry_kept XREAD=8 LVMODE=frozen DRY_RUN=true
ctl hung-no-latch "$HG"'s/^        _hung_done=1$/        :/' "$PL9" p_hung_stop XREAD=8 LVMODE=frozen
ctl hung-no-throttle "$HG"'s/-ge \${ALERT_THROTTLE:-600} \]\]; then$/-ge 0 ]]; then/' "$PL9" p_growing_kept XREAD=8 LVMODE=growing
ctl hung-no-retry-wait "$HG"'s/^        _hung_try_ts=\$(mono_now)$/        :/' "$PL9" p_failed_once XREAD=8 LVMODE=frozen HS_RC=1
ctl hung-staked-only-dropped "$HG"'s/^    \[\[ "\$_last_known_identity" == "\$STAKED_PUBKEY" .* || return 0$/    [[ ${_hung_done:-0} -eq 0 ]] || return 0/' "U X X X X X X X X" p_unstaked_quiet XREAD=8 LVMODE=frozen
ctl hung-page-no-branch "$HG"'s/ Ladder branch: \${_hs_branch:-unknown}\.//' "$PL9" p_branch_named XREAD=8 LVMODE=frozen "HS_BRANCH='fast: process state T, blocking systemctl stop skipped (stop requested with --no-block)'"
ctl_rc hung-knob-floor 's/_validate_numeric HOLDER_UNREACHABLE_STOP_SECS 20 /_validate_numeric HOLDER_UNREACHABLE_STOP_SECS 0 /' p_hung19_refused
ctl_rc hung-struct-moved '/^        _hung_check   # v0.7 (AG-3.8)/d; s/^        display_status "N\/A"$/        display_status "N\/A"; _hung_check/' hung_struct_ok
ctl_rc vp-no-mainpid '/^_validator_pid() {/,/^}/ { /kill -0/d; }' p_vp_pref
ctl_rc vp-no-alive-check '/^_validator_pid() {/,/^}/ s/ && kill -0 "\$p" 2>\/dev\/null//' p_vp_alive
# the ladder's fast branch (AG-3.8): detection always true / removed / D forgotten / no mask / SIGTERM kept
ctl_rc fast-detects-always "$LG"'s/case "\$_hs_st" in T|D) _hs_fast=1;/case "$_hs_st" in *) _hs_fast=1;/' p_normal_S
ctl_rc fast-detects-always-u "$LG"'s/case "\$_hs_st" in T|D) _hs_fast=1;/case "$_hs_st" in *) _hs_fast=1;/' p_normal_unreadable
ctl_rc fast-detection-removed "$LG"'s/case "\$_hs_st" in T|D) _hs_fast=1;/case "$_hs_st" in Z) _hs_fast=1;/' p_fast_T
ctl_rc fast-D-forgotten "$LG"'s/case "\$_hs_st" in T|D) _hs_fast=1;/case "$_hs_st" in T) _hs_fast=1;/' p_fast_D
ctl_rc fast-no-stop-request "$LG"'{ /^            _hs_nb_out=\$(timeout -k 5 15 systemctl stop --no-block /d; }' p_fast_T
ctl_rc fast-kill-before-request "$LG"'s/^            _hs_nb_out=\$(timeout -k 5 15 systemctl stop --no-block /            kill -9 "$pid" 2>\/dev\/null; _hs_nb_out=$(timeout -k 5 15 systemctl stop --no-block /' p_fast_T
ctl_rc fast-state-read-dropped "$LG"'{ /^                _hs_as=\$(timeout 5 systemctl show -p ActiveState /d; }' p_fast_T
ctl_rc fast-mask-back "$LG"'s/^        sc_out=""; sc_rc=1$/        sc_out=""; sc_rc=1; timeout -k 5 15 systemctl mask --runtime "${VALIDATOR_SERVICE:-solana}"/' p_fast_T
ctl_rc normal-mask-back "$LG"'s/^    # Fallback (non-systemd \/ stuck unit): SIGTERM the validator PID, then SIGKILL if it ignores it\.$/    [[ $sc_rc -ne 0 ]] \&\& timeout -k 5 15 systemctl mask --runtime "${VALIDATOR_SERVICE:-solana}"/' p_normal_S
ctl_rc fast-keeps-sigterm "$LG"'s/^        if \[\[ -z "\$_hs_fast" \]\]; then .*$/        if true; then/' p_fast_T
ctl_rc fast-no-reverify "$LG"'s/^    _watchdog_sleep "\${HARD_STOP_REVERIFY_SECS:-15}".*$/    :/' p_fast_verified
ctl_rc proc-state-wrong-letter '/^_proc_state() {/,/^}/ s/\${_st:0:1}/${_st:2:1}/' p_proc_state
# the rung's timeline (23): the bounds the figures in the texts come from - a bound moved in the code moves the timeline, the case turns red
ctl_rc tl-local-read-3 '/^_hung_local_slot() {/,/^}/ s/-m 5/-m 3/' p_timeline_all
ctl_rc tl-identity-bound-6 's/timeout 8 "\$SOLANA_PATH\/agave-validator"/timeout 6 "$SOLANA_PATH\/agave-validator"/' p_timeline_all
ctl_rc tl-frankendancer-bound-3 '/^get_local_identity() {/,/^}/ s/curl -s -m 5/curl -s -m 3/' p_timeline_all
ctl_rc tl-stop-bound-10 "$LG"'s/timeout -k 5 15 systemctl stop/timeout -k 5 10 systemctl stop/' p_timeline_all
ctl_rc tl-term-grace-4 "$LG"'s/^            sleep 2; pid=\$(_validator_pid)/            sleep 4; pid=$(_validator_pid)/' p_timeline_all
ctl_rc tl-check-interval-5 's/^CHECK_INTERVAL=3 /CHECK_INTERVAL=5 /' p_timeline_all
ctl_rc tl-fast-branch-gone "$LG"'s/case "\$_hs_st" in T|D) _hs_fast=1;/case "$_hs_st" in Z) _hs_fast=1;/' p_timeline_all
# the restart guard (24): the comparison, its sign and boundary, the doubt, the future check, the stamp, the latch; the parser's field, comm, tick rate
ctl restart-guard-removed "$HG"'s/^        if \[\[ -n "\$_hung_start" && \$_hung_start -ge \$_hung_read_ts \]\]; then$/        if false; then/' "$PL9" p_restart_not_hung XREAD=8 LVMODE=frozen STARTMODE=new
ctl restart-sign-flipped "$HG"'s/\$_hung_start -ge \$_hung_read_ts/$_hung_start -lt $_hung_read_ts/' "$PL9" p_hung_stop XREAD=8 LVMODE=frozen STARTMODE=old
ctl restart-gt-not-ge "$HG"'s/\$_hung_start -ge \$_hung_read_ts/$_hung_start -gt $_hung_read_ts/' "$PL9" p_at_read_restarted XREAD=8 LVMODE=frozen STARTMODE=at_read
ctl restart-no-cannot-tell "$HG"'s/^    elif \[\[ -z "\$_hung_start" \]\]; then$/    elif false; then/' "$PL9" p_cannot_tell XREAD=8 LVMODE=frozen STARTMODE=none
ctl restart-future-allowed "$HG"'s/ && \[\[ \$_hung_start -le \$now \]\]; } || _hung_start=""/; } || _hung_start=""/' "$PL9" p_cannot_tell XREAD=8 LVMODE=frozen STARTMODE=future
ctl restart-no-read-stamp '/^_hung_reset() {/,/^}/ { /^    _hung_read_ts=\$(mono_now)$/d; }' "$PL9" p_hung_stop XREAD=8 LVMODE=frozen STARTMODE=old
ctl_rc restart-stamp-struct '/^_hung_reset() {/,/^}/ { /^    _hung_read_ts=\$(mono_now)$/d; }' p_reset_stamps
ctl restart-not-latched "$HG"'s/^            _hung_done=2; _hung_since=0; _hung_pid0=""$/            _hung_since=0; _hung_pid0=""/' "$PL9" p_restart_not_hung XREAD=8 LVMODE=frozen STARTMODE=new
ctl_rc start-wrong-field 's/_t="\${_a\[19\]:-}"/_t="${_a[18]:-}"/' p_start_parse
ctl_rc start-comm-greedy 's/_s="\${_s##\*) }"/_s="${_s#*) }"/' p_start_parse
ctl_rc start-hz-fallback-1 's/{ _canon_uint "\$_hz" && \[\[ \$_hz -ge 1 \]\]; } || _hz=100$/{ _canon_uint "$_hz" \&\& [[ $_hz -ge 1 ]]; } || _hz=1/' p_start_parse
ctl_rc start-hz-ignored 's/^    _hz=\$(getconf CLK_TCK 2>\/dev\/null)$/    _hz=100/' p_start_parse
[[ $ctl_ok -eq 1 ]] && ok "(12) every mutant of the rule turns its case red:$ctl_rows" || bad "(12) a control is not red (NOT-APPLIED = its sed matched nothing):$ctl_rows"

results_banner
