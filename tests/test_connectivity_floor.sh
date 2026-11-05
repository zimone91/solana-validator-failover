#!/bin/bash
# v0.7 (rc2 F22): THE INTERNET-LOST FLOOR. The primary demotes itself when check_internet fails CONNECTIVITY_RETRIES rounds in a row. A round is CHECK_INTERVAL + a fixed 1.5 s wait
# for the pings + a 1 s curl fallback (5.5 s measured on the testnet pair), so the old default of 3 demoted at about 10.5 to 17 s - under SELF_FENCE_ISOLATION_SECS (30 s), the isolation rung it is meant
# to sit beside. On the pair (S21, 2266130) a 20 s egress blip counted 1/3 at +6 s, 2/3 at +11 s and 3/3 at +17 s and demoted the holder; the egress was back at +20 s, the spare
# took the identity at +69 s, and the stake went about 70 s without a vote. With CONNECTIVITY_RETRIES=6 the same blip passed. The default is now 6, a value below the floor is announced
# once at startup ([config-drift], a WARN - never a refusal), the banner prints the computed time, and every text derived from the old figure says 24 to 34 s. The round the floor counts
# is CHECK_INTERVAL + 2: check_internet waits a FIXED 1.5 s for the pings and then runs a 1 s curl fallback, so CONNECTIVITY_TIMEOUT does not enter (a first draft summed it in: a 7 s timeout
# beside 3 rounds read 33 s while the demote stayed at 17 s).
#   (0)  the harness: the REAL main-loop region over a plan of cycles, with the REAL check_internet - only the network under it (ping, curl, sleep) is mocked
#   (a)  the default is 6 in the primary daemon and its template (one line each, none says 3), the primary wizard offers 6, the standby has no such knob anywhere
#   (b)  the startup warning, through the REAL announce_config_drift: CHECK_INTERVAL=3 CONNECTIVITY_TIMEOUT=1 CONNECTIVITY_RETRIES=3 -> ONE line naming the knob, "≈ 15s",
#        SELF_FENCE_ISOLATION_SECS=30s, "floor 30s" and the advice "set CONNECTIVITY_RETRIES >= 6 in <env> and restart" (no "delete the line": the default itself can be below the floor);
#        6 and 7 and the defaults -> none; the round is CHECK_INTERVAL + 2 (5 / 3 rounds -> 21 s, advice 5; 1 / 6 -> 18 s, advice 10; CONNECTIVITY_TIMEOUT=7 beside 3 rounds still 15 s) and the
#        advice is rounded UP; the floor is the knob's value (60 -> 30 s, advice 12); leading zeros are decimal;
#        garbage is the validator's to refuse (no line, no error); PRIMARY_SELF_FENCE=false has no isolation rung (no line); the standby has no such rule; the call changes nothing
#   (c)  the Internet-lost switch fires after exactly CONNECTIVITY_RETRIES failed rounds IN A ROW (6: at the sixth failing cycle, not before; 3 and 1 the same; a good round in
#        between starts the count again; an unstaked node never demotes through this path)
#   (d)  the banner prints the computed time: `Inet retries:      6 (≈ 30s to the Internet-lost demote; floor 30s)`; with the self-fence off there is no floor to print
#   (e)  no shipped text still carries the figure of 3 rounds (13.5-16.5 s, 13.5-30 s) - the daemons, both templates, both wizards, the manual and the README say 24 to 34 s
#   (f)  CONTROLS (mutate()): every mutant of the default, the rule, the round, the rounding, the gate, the switch and the texts turns its case red
# RED ON THE BASE (2266130 + this suite): no [config-drift] CONNECTIVITY_RETRIES line anywhere (grep count 0), the default is 3, the banner prints "Inet retries:      3", the wizard
# offers 3, and the texts still say 13.5-16.5 s. (c) is a regression guard: it is green on the base too - the switch itself does not change.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, mutate(), extract_region, drift_out.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "The Internet-lost floor: CONNECTIVITY_RETRIES stays at or above the isolation floor (v0.7 rc2 F22)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/icf.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cut_src() { local f="$WORK/seam.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$$.$RANDOM"; sed -n '1,/MAIN LOOP/p' "$1" > "$f"; printf '%s' "$f"; }
STK="StakedPubkey111111111111111111111111111111"
UNS="UnstakedPubkey1111111111111111111111111111"
ENV_P="$HARNESS_DIR/failover.env.example"; ENV_S="$HARNESS_DIR/failover-standby.env.example"
DEPLOY_P="$HARNESS_DIR/deploy-failover.sh"; DEPLOY_S="$HARNESS_DIR/deploy-failover-standby.sh"
MANUAL="$HARNESS_DIR/docs/DEPLOYMENT-MANUAL.md"; README="$HARNESS_DIR/README.md"
echo "  precondition: lines naming '[config-drift] CONNECTIVITY_RETRIES' in the daemon under test: $(grep -c 'config-drift\] CONNECTIVITY_RETRIES' "$PRIMARY") (the base, 2266130: 0); its default: $(sed -n 's/^CONNECTIVITY_RETRIES=\([0-9]*\).*$/\1/p' "$PRIMARY") (the base: 3)"

# ── the world: the REAL loop region over a plan, the REAL check_internet, a mocked network ───────────────────────────────────────
ic_world() {   # ic_world <script> <plan> [VAR=val ...] -> events, one per line: C=<cycle> FAILED (n/R) / DEMOTE <reason> / RECOVERED <text> / COLLISION
    local script="$1" plan="$2" cs region; shift 2
    cs=$(cut_src "$script")
    region=$(extract_region "$script" '^while \$_running; do' '^done$') || { echo "NO-REGION"; return 0; }
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        trap - TERM INT HUP   # a world is not the daemon: its cleanup trap is of no use to the subshells this world forks
        eval "run_loop() {
$region
}"
        # NO EXIT trap in this subshell, and the event file lives under $WORK (the suite's own EXIT trap removes it, and the last command below removes it earlier): the REAL check_internet forks one
        # `( ping ... ) &` per target and kills them at once (sleep is a no-op here), and a subshell killed right after its fork can run the EXIT trap it inherited from this shell - `rm -f "$EV"` then
        # deleted the events logged so far (the first GitHub CI run: counts [(9/6) (10/6)] for ten cycles). Measured on bash 5.2.21: 2,360-2,603 of 10,000 fork-and-kill rounds run the parent's EXIT
        # trap in a child, about 70 on 5.1.16, none on 3.2.57; this suite was red in 105 of 120 runs under load and green when quiet. (0b) pins that this function sets no trap.
        EV=$(mktemp "$WORK/ev.XXXXXX"); export EV
        T_BASE=1700000000; _SIM_NOW=$T_BASE
        ev() { printf 'C=%s %s\n' "$IDX" "$*" >> "$EV"; }
        PLAN=(); IDX=0
        for t in $plan; do
            case "$t" in
                *:*) b="${t%%:*}"; n="${t##*:}"; k=0; while [[ $k -lt $n ]]; do PLAN+=("$b"); k=$((k + 1)); done ;;
                *)   PLAN+=("$t") ;;
            esac
        done
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; UNSTAKED_KEYPAIR="$EV"; LEDGER_PATH="$EV.ledger"; VALIDATOR_TYPE=agave; LOCAL_RPC="http://mock-local"
        TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"; VOTE_PUBKEY=""
        TG_ENABLED=false; DRY_RUN=false; ALERT_THROTTLE=600; PRIMARY_SELF_FENCE=true; CHECK_INTERVAL=3; TURBO_INTERVAL=1; _current_interval=3
        MAX_VOTE_LATENCY=0; DELINQUENCY_RETRIES=1; STARTUP_GRACE=30; RECOVERY_MODE=manual; SETIDENTITY_TIMEOUT=15; CONNECTIVITY_RETRIES=6
        for kv in "$@"; do eval "$kv"; done
        mono_now() { echo "$_SIM_NOW"; }
        tok_id() { local t="${PLAN[$IDX]}"; printf '%s' "${t:0:1}"; }
        tok_has() { local t="${PLAN[$IDX]}"; [[ "${t:1}" == *"$1"* ]]; }
        _last_heartbeat=$(date +%s); HEARTBEAT_INTERVAL=2000000000
        case "$(tok_id)" in S) _last_known_identity="$STK" ;; *) _last_known_identity="$UNS" ;; esac
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _version_startup_check() { :; }; _vat_cycle() { :; }; _fence_rot_check() { :; }; _g2_step() { :; }; _elapsed_step() { :; }
        flush_pending_alerts() { :; }; display_status() { :; }; save_state() { :; }; _watchdog_pet() { :; }; send_telegram() { return 0; }; send_webhook() { :; }
        log_info() { :; }; log_error() { :; }
        log_warn() { case "$1" in "Internet FAILED"*) ev "FAILED ${1#Internet FAILED }" ;; esac; }
        alert() { :; }; alert_warn() { :; }
        alert_info() { case "$1" in *"PRIMARY internet recovered"*) ev "RECOVERED $1" ;; esac; }
        get_local_identity() { case "$(tok_id)" in S) echo "$STAKED_PUBKEY" ;; U) echo "$UNSTAKED_PUBKEY" ;; *) return 0 ;; esac; }
        check_self_fence_isolation() { return 1; }
        check_identity_collision() { ev COLLISION; return 0; }
        tier1_check_delinquency() { return 1; }
        tier1_get_vote_latency() { echo 1; }
        verify_latency_tiered() { return 0; }
        _vat_hold() { return 1; }
        window_push() { :; }; window_count() { echo 0; }; window_triggered() { return 1; }; window_mostly_clear() { return 1; }; window_reset() { :; }
        switch_to_unstaked() { ev "DEMOTE $1"; return 0; }
        switch_to_staked() { ev "SWITCH-TO-STAKED $1"; return 1; }
        attempt_safe_recovery() { return 1; }
        # the network under the REAL check_internet: the pings (functions, so the ( ... ) & subshells inherit them) and the curl fallback fail in a cycle flagged `i`, answer otherwise
        ping() { tok_has i && return 1; return 0; }
        curl() { tok_has i && return 7; return 0; }
        _watchdog_sleep() {
            _SIM_NOW=$(( _SIM_NOW + $1 ))
            IDX=$(( IDX + 1 ))
            if [[ $IDX -ge ${#PLAN[@]} ]]; then _running=false; else tok_has a && LAST_SWITCH_TIME=$_SIM_NOW; fi   # an `a` cycle: the daemon itself changed the identity just now
        }
        sleep() { :; }
        _running=true; run_loop
        cat "$EV"; rm -f "$EV"
    ) 2>/dev/null
}
demote_cycles() { printf '%s\n' "$1" | sed -n 's/^C=\([0-9]*\) DEMOTE .*$/\1/p' | tr '\n' ' ' | sed 's/ $//'; }
failed_seq()    { printf '%s\n' "$1" | sed -n 's/^C=[0-9]* FAILED \(.*\)$/\1/p' | tr '\n' ' ' | sed 's/ $//'; }
n_of()          { printf '%s\n' "$1" | grep -c -F -e "$2"; }
raw_ev()        { printf '%s' "$1" | tr '\n' ';' | cut -c1-420; }   # the raw event lines on one line - a red names what the world logged, not only the aggregate
count_drift()   { printf '%s\n' "$1" | grep -c '\[config-drift\] CONNECTIVITY_RETRIES'; }
drift_knob() {  # drift_knob <script> VAR=val... -> "rc=<announce_config_drift's status> retries=<the knob after it>" (the announcer must change nothing and refuse nothing)
    local script="$1"; shift
    (
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        log_info(){ :; }; log_error(){ :; }; log_warn(){ :; }
        for kv in "$@"; do eval "$kv"; done
        announce_config_drift; _rc=$?
        echo "rc=$_rc retries=$CONNECTIVITY_RETRIES"
    ) 2>&1
}

# ── (0) the world runs the real loop and the real check_internet ───────────────────────────────────────────────────────────────
echo ""; echo "─── (0) the harness: the real loop with the real check_internet over a mocked network ───"
ev0=$(ic_world "$PRIMARY" "S:3 Si:2 S")
if [[ "$(n_of "$ev0" 'COLLISION')" == "4" && "$(failed_seq "$ev0")" == "(1/6) (2/6)" && "$(n_of "$ev0" 'RECOVERED')" == "1" && "$(n_of "$ev0" 'recovered after 2 fail(s)')" == "1" && "$(demote_cycles "$ev0")" == "" ]]; then
    ok "(0) three good staked cycles, two cycles with every ping failing ('Internet FAILED (1/6)', '(2/6)'), one good cycle: the staked branch ran 4 times (the collision check), the failures were counted by the real check_internet, 'PRIMARY internet recovered after 2 fail(s)' came once, no demote"
else
    bad "(0) the world does not run: $(printf '%s' "$ev0" | tr '\n' ';' | cut -c1-300)"
fi
# (0b) the world sets no trap (the note in ic_world): a trap set in a subshell that forks can be run by a child killed right after its fork - the first CI run lost ten cycles' events to it. It resets the daemon's TERM/INT/HUP trap
_icw_body=$(sed -n '/^ic_world() {/,/^demote_cycles() {/p' "${BASH_SOURCE[0]}" | grep -v '^[[:space:]]*#')
_icw_set=$(printf '%s\n' "$_icw_body" | grep -c -E '(^|[;({]|&&|\|\|)[[:space:]]*trap[[:space:]]+[^-[:space:]]')   # a trap SET at a command position ("trap - ..." resets, and the word in a trailing comment is not a command)
_icw_reset=$(printf '%s\n' "$_icw_body" | grep -c -E '^[[:space:]]*trap - TERM INT HUP')
if [[ "$_icw_set" == "0" && "$_icw_reset" == "1" ]]; then
    ok "(0b) the world sets no trap in the subshell that runs the real check_internet (its ping subshells are killed at once; one killed in its first microseconds can run a trap it inherited - bash 5.2.21: 2,360-2,603 of 10,000 fork-and-kill rounds) and resets the daemon's TERM/INT/HUP trap right after sourcing it; its event file lives under the suite's own temp dir"
else
    bad "(0b) ic_world sets $_icw_set trap(s) and resets the daemon's signal trap $_icw_reset time(s) (want 0 and 1): a killed ping subshell can run an inherited trap and delete the event file in the middle of a run"
fi

# ── (a) the defaults ───────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (a) CONNECTIVITY_RETRIES is 6 in the primary daemon, its template and its wizard; the standby has no such knob ───"
p_default6()    { [[ "$(grep -c -E '^CONNECTIVITY_RETRIES=6( |$)' "$1")" == "1" && "$(grep -c -E '^CONNECTIVITY_RETRIES=[0-9]' "$1")" == "1" ]]; }
p_wiz_default6() { [[ "$(grep -c -F 'ask_numeric "Internet retries before switch (connectivity confirms)" "${CONNECTIVITY_RETRIES:-6}" 1' "$1")" == "1" && "$(grep -c -F 'CONNECTIVITY_RETRIES:-3' "$1")" == "0" ]]; }
n_standby=$(grep -c 'CONNECTIVITY_RETRIES' "$STANDBY" "$ENV_S" "$DEPLOY_S" | awk -F: '{s += $2} END {print s + 0}')
if p_default6 "$PRIMARY" && p_default6 "$ENV_P" && p_wiz_default6 "$DEPLOY_P" && [[ "$n_standby" == "0" ]]; then
    ok "(a) the daemon and the primary template carry exactly one CONNECTIVITY_RETRIES default each, 6; the primary wizard offers \${CONNECTIVITY_RETRIES:-6} and none says 3; the standby daemon, its template and its wizard never name the knob"
else
    bad "(a) defaults: daemon=$(grep -m1 -E '^CONNECTIVITY_RETRIES=' "$PRIMARY" | cut -c1-60) template=$(grep -m1 -E '^CONNECTIVITY_RETRIES=' "$ENV_P" | cut -c1-60) wizard=$(grep -c -F 'CONNECTIVITY_RETRIES:-6' "$DEPLOY_P") standby-mentions=$n_standby"
fi

# ── (b) the startup warning ──────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (b) startup: a value below the floor is announced once; at or above it, silence ───"
dr3=$(drift_out "$PRIMARY" 'CHECK_INTERVAL=3' 'CONNECTIVITY_TIMEOUT=1' 'CONNECTIVITY_RETRIES=3')
dr6=$(drift_out "$PRIMARY" 'CHECK_INTERVAL=3' 'CONNECTIVITY_TIMEOUT=1' 'CONNECTIVITY_RETRIES=6'); dr7=$(drift_out "$PRIMARY" 'CONNECTIVITY_RETRIES=7'); drd=$(drift_out "$PRIMARY")
p_warn_at_3() {
    local o; o=$(drift_out "$1" 'CHECK_INTERVAL=3' 'CONNECTIVITY_TIMEOUT=1' 'CONNECTIVITY_RETRIES=3')
    [[ "$(count_drift "$o")" == "1" && "$o" == *"[config-drift] CONNECTIVITY_RETRIES=3 fires the Internet-lost demote at ≈ 15s, below SELF_FENCE_ISOLATION_SECS=30s"* && "$o" == *"floor 30s"* \
       && "$o" == *"set CONNECTIVITY_RETRIES >= 6 in "* && "$o" == *" and restart" && "$o" != *"delete the line"* ]]
}
p_silent_at_floor() { [[ "$(count_drift "$(drift_out "$1" 'CHECK_INTERVAL=3' 'CONNECTIVITY_TIMEOUT=1' 'CONNECTIVITY_RETRIES=6')")" == "0" && "$(count_drift "$(drift_out "$1" 'CONNECTIVITY_RETRIES=7')")" == "0" && "$(count_drift "$(drift_out "$1")")" == "0" ]]; }
if p_warn_at_3 "$PRIMARY" && p_silent_at_floor "$PRIMARY"; then
    ok "(b1) CONNECTIVITY_RETRIES=3 at CHECK_INTERVAL 3 / timeout 1: ONE '[config-drift] CONNECTIVITY_RETRIES=3 fires the Internet-lost demote at ≈ 15s, below SELF_FENCE_ISOLATION_SECS=30s' line with 'floor 30s' and 'set CONNECTIVITY_RETRIES >= 6 in <env> and restart' (no 'delete the line'); 6 (30 s = the floor, not below it), 7 and the defaults: no line"
else
    bad "(b1) 3: [$(printf '%s' "$dr3" | cut -c1-260)] 6: $(count_drift "$dr6") line(s) 7: $(count_drift "$dr7") defaults: $(count_drift "$drd")"
fi
dr5=$(drift_out "$PRIMARY" 'CONNECTIVITY_RETRIES=5'); dr_a=$(drift_out "$PRIMARY" 'CHECK_INTERVAL=5' 'CONNECTIVITY_TIMEOUT=2' 'CONNECTIVITY_RETRIES=3'); dr_b=$(drift_out "$PRIMARY" 'CHECK_INTERVAL=1' 'CONNECTIVITY_TIMEOUT=1' 'CONNECTIVITY_RETRIES=6')
dr_ok=$(drift_out "$PRIMARY" 'CHECK_INTERVAL=5' 'CONNECTIVITY_TIMEOUT=2' 'CONNECTIVITY_RETRIES=5'); dr_t7=$(drift_out "$PRIMARY" 'CHECK_INTERVAL=3' 'CONNECTIVITY_TIMEOUT=7' 'CONNECTIVITY_RETRIES=3')
p_round_and_ceil() {
    local a b c d; a=$(drift_out "$1" 'CHECK_INTERVAL=5' 'CONNECTIVITY_TIMEOUT=2' 'CONNECTIVITY_RETRIES=3'); b=$(drift_out "$1" 'CHECK_INTERVAL=1' 'CONNECTIVITY_TIMEOUT=1' 'CONNECTIVITY_RETRIES=6'); c=$(drift_out "$1" 'CHECK_INTERVAL=5' 'CONNECTIVITY_TIMEOUT=2' 'CONNECTIVITY_RETRIES=5')
    d=$(drift_out "$1" 'CHECK_INTERVAL=3' 'CONNECTIVITY_TIMEOUT=7' 'CONNECTIVITY_RETRIES=3')
    [[ "$a" == *"CONNECTIVITY_RETRIES=3 fires the Internet-lost demote at ≈ 21s"* && "$a" == *"set CONNECTIVITY_RETRIES >= 5 in "* && "$b" == *"CONNECTIVITY_RETRIES=6 fires the Internet-lost demote at ≈ 18s"* && "$b" == *"set CONNECTIVITY_RETRIES >= 10 in "* \
       && "$(count_drift "$c")" == "0" && "$d" == *"CONNECTIVITY_RETRIES=3 fires the Internet-lost demote at ≈ 15s"* && "$d" == *"set CONNECTIVITY_RETRIES >= 6 in "* ]]
}
if p_round_and_ceil "$PRIMARY" && [[ "$dr5" == *"≈ 25s"* && "$dr5" == *">= 6 in "* ]]; then
    ok "(b2) the round is CHECK_INTERVAL + 2 (the fixed 1.5 s wait for the pings and the 1 s curl fallback; CONNECTIVITY_TIMEOUT enters no sum): at CHECK_INTERVAL 5, 3 rounds -> '≈ 21s', advice 5 (30 / 7 rounded UP; 5 rounds = 35 s are silent); at 1, 6 rounds -> '≈ 18s', advice 10; CONNECTIVITY_TIMEOUT=7 beside 3 rounds at CHECK_INTERVAL 3 is still '≈ 15s', advice 6; 5 rounds at the defaults -> '≈ 25s', advice 6"
else
    bad "(b2) round/advice: 5-2-3=[$(printf '%s' "$dr_a" | cut -c1-120)] 1-1-6=[$(printf '%s' "$dr_b" | cut -c1-120)] 5-2-5=$(count_drift "$dr_ok") line(s) 3-7-3=[$(printf '%s' "$dr_t7" | cut -c1-120)] 5@defaults=[$(printf '%s' "$dr5" | cut -c1-120)]"
fi
p_floor_value() { local o; o=$(drift_out "$1" 'SELF_FENCE_ISOLATION_SECS=60' 'CONNECTIVITY_RETRIES=6'); [[ "$o" == *"CONNECTIVITY_RETRIES=6 fires the Internet-lost demote at ≈ 30s, below SELF_FENCE_ISOLATION_SECS=60s"* && "$o" == *"floor 60s"* && "$o" == *"set CONNECTIVITY_RETRIES >= 12 in "* ]]; }
if p_floor_value "$PRIMARY"; then
    ok "(b3) the floor is the isolation knob's value: SELF_FENCE_ISOLATION_SECS=60 with the default 6 rounds -> '≈ 30s, below SELF_FENCE_ISOLATION_SECS=60s', 'floor 60s', advice 12"
else
    bad "(b3) floor value: [$(drift_out "$PRIMARY" 'SELF_FENCE_ISOLATION_SECS=60' 'CONNECTIVITY_RETRIES=6' | cut -c1-260)]"
fi
p_zero_garbage() {
    local z g; z=$(drift_out "$1" 'CHECK_INTERVAL=08' 'CONNECTIVITY_TIMEOUT=01' 'CONNECTIVITY_RETRIES=03' 2>&1); g=$(drift_out "$1" 'CONNECTIVITY_RETRIES=abc' 2>&1; drift_out "$1" 'CHECK_INTERVAL=' 2>&1; drift_out "$1" 'SELF_FENCE_ISOLATION_SECS=x' 2>&1)
    [[ -z "$z" && -z "$g" ]]
}
if p_zero_garbage "$PRIMARY"; then
    ok "(b4) leading zeros are decimal (CHECK_INTERVAL=08, timeout 01, rounds 03 -> 3 x 10 = 30 s: silent, no arithmetic error); garbage in any of the four knobs (abc, empty, x) is the validator's to refuse: no line, no error text"
else
    bad "(b4) zeros/garbage: zero=[$(drift_out "$PRIMARY" 'CHECK_INTERVAL=08' 'CONNECTIVITY_TIMEOUT=01' 'CONNECTIVITY_RETRIES=03' 2>&1 | cut -c1-200)] garbage=[$( (drift_out "$PRIMARY" 'CONNECTIVITY_RETRIES=abc' 2>&1; drift_out "$PRIMARY" 'CHECK_INTERVAL=' 2>&1) | cut -c1-200)]"
fi
p_fence_off() { [[ "$(count_drift "$(drift_out "$1" 'PRIMARY_SELF_FENCE=false' 'CONNECTIVITY_RETRIES=3')")" == "0" && "$(count_drift "$(drift_out "$1" 'PRIMARY_SELF_FENCE=true' 'CONNECTIVITY_RETRIES=3')")" == "1" ]]; }
if p_fence_off "$PRIMARY"; then
    ok "(b5) PRIMARY_SELF_FENCE=false has no isolation rung, so the Internet rule is the only one of the pair and advising a longer one would point the wrong way: no line (the same 3 rounds with the self-fence on: one line)"
else
    bad "(b5) self-fence off: $(count_drift "$(drift_out "$PRIMARY" 'PRIMARY_SELF_FENCE=false' 'CONNECTIVITY_RETRIES=3')") line(s), on: $(count_drift "$(drift_out "$PRIMARY" 'PRIMARY_SELF_FENCE=true' 'CONNECTIVITY_RETRIES=3')")"
fi
p_standby_none() { [[ "$(drift_out "$1" 'CONNECTIVITY_RETRIES=1' 'CONNECTIVITY_TIMEOUT=1' 'CHECK_INTERVAL=1' | grep -c 'CONNECTIVITY')" == "0" ]]; }
dk=$(drift_knob "$PRIMARY" 'CONNECTIVITY_RETRIES=3')
accode=$(sed -n '/^announce_config_drift() {/,/^}/p' "$PRIMARY" | sed -n '/the Internet-lost demote must not fire BELOW the isolation floor/,$p' | grep -v '^[[:space:]]*#')
if p_standby_none "$STANDBY" && [[ "$dk" == "rc=0 retries=3" ]] && ! printf '%s\n' "$accode" | grep -q -E '(^|[^a-zA-Z_])(exit|return [1-9]|printf -v)'; then
    ok "(b6) announce-only: after a warning the announcer returns 0 and the knob is still 3 (nothing refused, nothing clamped); the block has no exit, no non-zero return and no printf -v; the standby has no such rule (CONNECTIVITY_RETRIES=1 beside a 1 s cycle: no line)"
else
    bad "(b6) announce-only: standby-none=$(p_standby_none "$STANDBY" && echo y || echo n) probe=[$dk] block-actions=$(printf '%s\n' "$accode" | grep -c -E '(^|[^a-zA-Z_])(exit|return [1-9]|printf -v)')"
fi

# ── (c) the switch itself ──────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (c) the Internet-lost switch fires after exactly CONNECTIVITY_RETRIES failed rounds in a row ───"
REASON6="Internet lost (6x) — no tier verification needed"
ev_c1=$(ic_world "$PRIMARY" "Si:6 Ua"); ev_c2=$(ic_world "$PRIMARY" "Si:3 Ua" CONNECTIVITY_RETRIES=3); ev_c3=$(ic_world "$PRIMARY" "Si:5 S Si:5 S"); ev_c4=$(ic_world "$PRIMARY" "Ui:10"); ev_c5=$(ic_world "$PRIMARY" "Si Ua" CONNECTIVITY_RETRIES=1)
p_exact_six() { [[ "$(demote_cycles "$1")" == "5" && "$(failed_seq "$1")" == "(1/6) (2/6) (3/6) (4/6) (5/6) (6/6)" && "$(n_of "$1" "C=5 DEMOTE $REASON6")" == "1" ]]; }
p_reset_between() { [[ "$(demote_cycles "$1")" == "" && "$(failed_seq "$1")" == "(1/6) (2/6) (3/6) (4/6) (5/6) (1/6) (2/6) (3/6) (4/6) (5/6)" && "$(n_of "$1" 'RECOVERED')" == "2" ]]; }
p_unstaked_never() { [[ "$(demote_cycles "$1")" == "" && "$(failed_seq "$1")" == "(1/6) (2/6) (3/6) (4/6) (5/6) (6/6) (7/6) (8/6) (9/6) (10/6)" ]]; }
if p_exact_six "$ev_c1"; then
    ok "(c1) six cycles with every ping failing: 'Internet FAILED (1/6)' ... '(6/6)', ONE demote, at the sixth failing cycle (C=5) and not before - reason '$REASON6'"
else
    bad "(c1) six failing cycles: demotes at [$(demote_cycles "$ev_c1")] (want 5), counts [$(failed_seq "$ev_c1")], raw [$(raw_ev "$ev_c1")]"
fi
if [[ "$(demote_cycles "$ev_c2")" == "2" && "$(n_of "$ev_c2" 'C=2 DEMOTE Internet lost (3x)')" == "1" && "$(demote_cycles "$ev_c5")" == "0" && "$(n_of "$ev_c5" 'C=0 DEMOTE Internet lost (1x)')" == "1" ]]; then
    ok "(c2) the same switch at the other settings: CONNECTIVITY_RETRIES=3 demotes at the third failing cycle (C=2, 'Internet lost (3x)'), =1 at the first (C=0) - the knob is read, not a constant"
else
    bad "(c2) retries 3: demotes [$(demote_cycles "$ev_c2")] (want 2); retries 1: [$(demote_cycles "$ev_c5")] (want 0); raw [$(raw_ev "$ev_c2")] [$(raw_ev "$ev_c5")]"
fi
if p_reset_between "$ev_c3"; then
    ok "(c3) five failing cycles, one good one, five failing again: the count starts again at 1/6 after the good round ('PRIMARY internet recovered' twice) - no demote: the rounds must be IN A ROW"
else
    bad "(c3) interrupted run: demotes [$(demote_cycles "$ev_c3")] (want none), counts [$(failed_seq "$ev_c3")], recovered $(n_of "$ev_c3" 'RECOVERED'), raw [$(raw_ev "$ev_c3")]"
fi
if p_unstaked_never "$ev_c4"; then
    ok "(c4) an UNSTAKED node with no Internet for ten cycles counts to '(10/6)' and never demotes through this path (nothing to demote)"
else
    bad "(c4) unstaked: demotes [$(demote_cycles "$ev_c4")] (want none), counts [$(failed_seq "$ev_c4")], raw [$(raw_ev "$ev_c4")]"
fi

# ── (d) the banner ────────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (d) the start banner prints the computed time beside the knob ───"
p_banner_inet() {
    local bl o1 o2 o3; bl=$(grep -F 'echo "  Inet retries:' "$1" | head -1); [[ -n "$bl" ]] || return 1
    o1=$( CONNECTIVITY_RETRIES=6; CHECK_INTERVAL=3; CONNECTIVITY_TIMEOUT=1; SELF_FENCE_ISOLATION_SECS=30; PRIMARY_SELF_FENCE=true; eval "$bl" )
    o2=$( CONNECTIVITY_RETRIES=3; CHECK_INTERVAL=3; CONNECTIVITY_TIMEOUT=1; SELF_FENCE_ISOLATION_SECS=30; PRIMARY_SELF_FENCE=true; eval "$bl" )
    o3=$( CONNECTIVITY_RETRIES=6; CHECK_INTERVAL=3; CONNECTIVITY_TIMEOUT=1; SELF_FENCE_ISOLATION_SECS=30; PRIMARY_SELF_FENCE=false; eval "$bl" )
    [[ "$o1" == "  Inet retries:      6 (≈ 30s to the Internet-lost demote; floor 30s)" && "$o2" == "  Inet retries:      3 (≈ 15s to the Internet-lost demote; floor 30s)" \
       && "$o3" == "  Inet retries:      6 (≈ 30s to the Internet-lost demote; no isolation floor: self-fence off)" ]]
}
if p_banner_inet "$PRIMARY"; then
    ok "(d) 'Inet retries:      6 (≈ 30s to the Internet-lost demote; floor 30s)' at the defaults, '3 (≈ 15s ...; floor 30s)' for 3 rounds, and with the self-fence off '6 (≈ 30s ...; no isolation floor: self-fence off)' - the same arithmetic as the warning"
else
    bad "(d) banner: $( ( CONNECTIVITY_RETRIES=6; CHECK_INTERVAL=3; CONNECTIVITY_TIMEOUT=1; SELF_FENCE_ISOLATION_SECS=30; PRIMARY_SELF_FENCE=true; eval "$(grep -F 'echo "  Inet retries:' "$PRIMARY" | head -1)" ) 2>&1 | cut -c1-200)"
fi

# ── (e) no stale figure ────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (e) no shipped text carries the figure of 3 rounds any more ───"
STALE='13\.5(-|–)16\.5|13\.5(-|–)30|3 × 3s = 9s'
p_no_stale() { ! grep -q -E "$STALE" "$1"; }
stale_hits=""
for f in "$PRIMARY" "$STANDBY" "$ENV_P" "$ENV_S" "$DEPLOY_P" "$DEPLOY_S" "$MANUAL" "$README"; do p_no_stale "$f" || stale_hits="$stale_hits $(basename "$f")"; done
if [[ -z "$stale_hits" ]]; then
    ok "(e) '13.5-16.5 s', '13.5-30 s' and '3 × 3s = 9s' appear in none of the daemons, templates, wizards, the manual and the README (SAFETY.md and the CHANGELOG name the old figure as history)"
else
    bad "(e) stale figure still in:$stale_hits"
fi

# ── (f) controls ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (f) CONTROLS (mutate()): each mutant must turn its case red ───"
ctl_ok=1; ctl_rows=""
ctl_file() {   # ctl_file <label> <file> <sed expr> <predicate over a file> - the predicate holds on the shipped file and FAILS on the mutant
    local label="$1" file="$2" expr="$3" pred="$4" m="$WORK/mut-$1.$(basename "$2")" rv mv
    if ! mutate "$file" "$expr" "$m"; then ctl_ok=0; ctl_rows="$ctl_rows $label:NOT-APPLIED"; return; fi
    "$pred" "$file" && rv=y || rv=n; "$pred" "$m" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then ctl_rows="$ctl_rows $label:red"; else ctl_ok=0; ctl_rows="$ctl_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
ctl_world() {  # ctl_world <label> <sed expr> <plan> <predicate over events> [VAR=val ...] - the predicate holds on the shipped script's events and FAILS on the mutant's
    local label="$1" expr="$2" plan="$3" pred="$4" m="$WORK/mutw-$1.sh" real mut rv mv; shift 4
    if ! mutate "$PRIMARY" "$expr" "$m"; then ctl_ok=0; ctl_rows="$ctl_rows $label:NOT-APPLIED"; return; fi
    real=$(ic_world "$PRIMARY" "$plan" "$@"); mut=$(ic_world "$m" "$plan" "$@")
    "$pred" "$real" && rv=y || rv=n; "$pred" "$mut" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then ctl_rows="$ctl_rows $label:red"; else ctl_ok=0; ctl_rows="$ctl_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
ctl_file default-3-daemon "$PRIMARY" 's/^CONNECTIVITY_RETRIES=6 /CONNECTIVITY_RETRIES=3 /' p_default6
ctl_file default-3-template "$ENV_P" 's/^CONNECTIVITY_RETRIES=6 /CONNECTIVITY_RETRIES=3 /' p_default6
ctl_file default-3-wizard "$DEPLOY_P" 's/"\${CONNECTIVITY_RETRIES:-6}" 1/"${CONNECTIVITY_RETRIES:-3}" 1/' p_wiz_default6
ctl_file warn-gone "$PRIMARY" 's/^            log_warn "\[config-drift\] CONNECTIVITY_RETRIES=/            : "[config-drift] CONNECTIVITY_RETRIES=/' p_warn_at_3
ctl_file warns-at-the-floor "$PRIMARY" 's/-lt \$_ic_floor \]\]; then/-le $_ic_floor ]]; then/' p_silent_at_floor
ctl_file round-one-short "$PRIMARY" 's/_ic_round=\$(( 10#\$CHECK_INTERVAL + 2 ))/_ic_round=$(( 10#$CHECK_INTERVAL + 1 ))/' p_warn_at_3
ctl_file round-counts-the-timeout "$PRIMARY" 's/_ic_round=\$(( 10#\$CHECK_INTERVAL + 2 ))/_ic_round=$(( 10#$CHECK_INTERVAL + 10#$CONNECTIVITY_TIMEOUT + 1 ))/' p_round_and_ceil
ctl_file advice-rounded-down "$PRIMARY" 's/(_ic_floor + _ic_round - 1) \/ _ic_round/_ic_floor \/ _ic_round/' p_round_and_ceil
ctl_file floor-is-a-constant "$PRIMARY" 's/_ic_floor=\$((10#\$SELF_FENCE_ISOLATION_SECS))/_ic_floor=30/' p_floor_value
ctl_file octal "$PRIMARY" 's/_ic_round=\$(( 10#\$CHECK_INTERVAL + /_ic_round=$(( $CHECK_INTERVAL + /' p_zero_garbage
ctl_file garbage-guard-gone "$PRIMARY" 's/ && "\$CONNECTIVITY_RETRIES" =~ \^\[0-9\]+\$ && "\$CHECK_INTERVAL"/ \&\& "$CHECK_INTERVAL"/' p_zero_garbage
ctl_file no-self-fence-gate "$PRIMARY" 's/if \[\[ "\$PRIMARY_SELF_FENCE" == "true" && "\$CONNECTIVITY_RETRIES"/if [[ "$CONNECTIVITY_RETRIES"/' p_fence_off
ctl_file banner-without-seconds "$PRIMARY" 's/Inet retries:      \$CONNECTIVITY_RETRIES (≈ \$(( CONNECTIVITY_RETRIES \* (CHECK_INTERVAL + 2) ))s to the Internet-lost demote; /Inet retries:      $CONNECTIVITY_RETRIES (/' p_banner_inet
ctl_file banner-floor-always "$PRIMARY" 's/\$(\[\[ "\$PRIMARY_SELF_FENCE" == "true" \]\] && echo "floor \${SELF_FENCE_ISOLATION_SECS}s" || echo "no isolation floor: self-fence off")/floor ${SELF_FENCE_ISOLATION_SECS}s/' p_banner_inet
ctl_file stale-figure-in-the-standby "$STANDBY" 's/Internet-lost at 24 to 34 s since rc2 F22/Internet-lost at 13.5-16.5 s since rc2 F22/' p_no_stale
ctl_file stale-figure-in-the-manual "$MANUAL" 's/parallel pings fail 6x (`CONNECTIVITY_RETRIES`, rc2 F22 — it was 3) → switch to unstaked (24 to 34 s:/parallel pings fail 3x → switch to unstaked (13.5–16.5 s:/' p_no_stale
ctl_file stale-figure-in-the-template "$ENV_S" 's/Internet-lost 24-34s since rc2 F22/Internet-lost 13.5-16.5s since rc2 F22/' p_no_stale
ctl_world switch-one-late 's/CONNECTIVITY_FAIL_COUNT -ge \$CONNECTIVITY_RETRIES/CONNECTIVITY_FAIL_COUNT -gt $CONNECTIVITY_RETRIES/' "Si:6 Ua" p_exact_six
ctl_world switch-one-early 's/CONNECTIVITY_FAIL_COUNT -ge \$CONNECTIVITY_RETRIES/CONNECTIVITY_FAIL_COUNT -ge $((CONNECTIVITY_RETRIES - 1))/' "Si:6 Ua" p_exact_six
ctl_world count-not-reset 's/^    CONNECTIVITY_FAIL_COUNT=0$/    :/' "Si:5 S Si:5 S" p_reset_between
ctl_world switch-on-any-identity 's/CONNECTIVITY_FAIL_COUNT -ge \$CONNECTIVITY_RETRIES && "\$CURRENT_IDENTITY" == "\$STAKED_PUBKEY" \]\]; then/CONNECTIVITY_FAIL_COUNT -ge $CONNECTIVITY_RETRIES ]]; then/' "Ui:10" p_unstaked_never
[[ $ctl_ok -eq 1 ]] && ok "(f) every mutant turns its case red:$ctl_rows" || bad "(f) a control did not turn its case red:$ctl_rows"

results_banner
