#!/bin/bash
# v0.7 (Block 5.2): MONITOR-SIDE FENCE INTEGRATION — the native-systemd-watchdog transport
# (per-op pets), READY gating + pre-READY live extension, §2.2 fence-marker consumption
# (HOLD / stale / demoted lifecycle), the part-D dispatch damper, and the №8 pre-warm lever.
# Drives the REAL daemons' new helpers (source-to-MAIN-LOOP seam), the REAL startup wait-loop
# region, a REAL main-loop cycle region, and the REAL fence script (subprocess) — with
# NOTIFY_SOCKET/WATCHDOG_USEC fixtures and a socat stub that event-logs every datagram.
#
# STRUCTURAL-INERTNESS CONTRACT (the load-bearing assertion set): a host running the daemon
# OUTSIDE the systemd unit (no NOTIFY_SOCKET/WATCHDOG_USEC — every host today, every other
# suite) sees ZERO behavior change: zero datagrams, zero startup probes, monolithic sleeps,
# and no marker action when no fence marker exists.
#
# Cases:
#   (1)  inertness: no NOTIFY_SOCKET → zero socat events across helpers + wait-loop + a full
#        simulated cycle; no marker → _consume_fence_markers is a no-op
#   (2)  READY gate on pets: pet before READY = nothing; READY then pet = WATCHDOG=1 (+MAINPID)
#   (3)  wait-loop: EXTEND (60000000) per confirmed-in-startup iteration; READY only after the
#        FIRST successful identity read; no WATCHDOG=1 before READY  [both daemons]
#   (4)  wait-loop: evidence lapses (or process gone) → EXTEND stops + the not-extending warn
#   (5)  cycle: pet after the identity read + ONE end-of-cycle pet; wedged op → no pet after
#        the op's start (the no-pet-mid-op invariant); mutation control: end-of-cycle pet
#        deleted → count drops (the assert is non-vacuous)
#   (6)  _watchdog_sleep: active → 10s chunks + a pet per completed chunk; inactive → one
#        plain sleep, zero datagrams
#   (7)  HOLD: same-boot fenced-stopped → CRITICAL page + re-page per ALERT_THROTTLE, READY +
#        pets (the documented B1 exception), zero monitoring logic, operator clears → exit 0
#   (8)  stale (pre-boot) fenced-stopped → warn + page once + normal monitoring (no HOLD)
#   (9)  fenced-demoted (any age) → noted at startup, marker cleared on the FIRST clean cycle;
#        fenced-page-only is ignored
#   (10) part D — two consecutive fence dispatch cycles: pass 1 (startup evidence) restarts the
#        monitor with NO stop; the daemon then refuses to extend (no evidence); pass 2 takes
#        the STOP path (fenced-stopped) → the loop terminates
#   (11) №8 pre-warm: default-off = ZERO admin calls; enabled = ONE add per episode; reset
#        hygiene = remove-all ONLY when not holding staked; DRY_RUN issues nothing; drift
#        announce (LIVE-TEST-GATED wording); call-site + primary-absence structural checks
#   (12) byte-identity: the [watchdog] block PRIMARY↔STANDBY; _marker_same_boot and
#        _startup_phase_evidence DAEMON↔FENCE (all three copies byte-equal)
#   (13) zero-inertness grep-proof: no watchdog-transport token (socat/NOTIFY_SOCKET/
#        WATCHDOG_USEC/READY=1/WATCHDOG=1/EXTEND_TIMEOUT_USEC) in CODE outside the [watchdog]
#        block; the activation-gate mutant control (gate forced open → datagrams leak)
#   (14) structural pins (the CI-pin idiom, stored here): end-of-cycle pet CALL-line counts and
#        the TOTAL `_watchdog_pet` call-site count per daemon — a mutant that deletes/neuters a
#        pet call while keeping its comment trips a count; long sleeps via _watchdog_sleep
#   (15) HOLD-1 (fix round): fatal-inducing config + same-boot fenced-stopped marker → HOLD is
#        entered (marker consumption precedes EVERY fatal gate), no exit-1 loop  [both daemons]
#   (16) FF-B1/FF-B2 (fix round): the wedged demote paths and the unreachable-tier paths PET
#        their completed (timed-out) ops — event-order asserted around the real functions
#   (17) FF-B3/HOLD-B1 (fix round): armed cycle at CHECK_INTERVAL=45 → the inter-cycle sleep is
#        CHUNKED (pets continue through it); un-armed stays one monolithic sleep
#   (18) FF-1/FF-4 (fix round): wait-loop EXTEND re-sent immediately after the H3 alert (the
#        72 s panel trace closes to ≤ 46 s); armed-only throttled "still in startup" re-page
#
# MUTATION COVERAGE (HARNESS.md discipline — killed or the survivor NAMED):
#   killed here: the end-of-cycle pet line (5-ctrl + the (14) call-count pins), the
#   _watchdog_active gate (13-ctrl), the EXTEND value (asserted byte-exact in (3)), the READY
#   gate on pets ((2) + (3)), the _watchdog_sleep chunking ((6) chunk log + (17)), the HOLD
#   re-page throttle ((7) SIM-advance), the first-clean-cycle marker clear ((9b) standby, (9d)
#   primary), monitoring logic inside HOLD ((7)'s bait stubs — the panel's M6 mutant class),
#   a pre-warm call leaking outside the takeover-delay window ((11l) — the panel's M11x class),
#   per-op pet DELETION anywhere ((14b/14c) total call-site pins: grep -cE
#   '^[[:space:]]*_watchdog_pet\b' minus the function definition — count-changing mutants trip).
#   NAMED SURVIVORS (deliberate, not oversights): the per-op `_watchdog_pet` one-liners inside
#   individual tier/admin helpers are not individually BEHAVIORALLY killed — the cycle seam
#   stubs those helpers, so replacing one call's semantics (not its line) stays green here; and
#   a future EARLY-RETURN/BRANCH inserted BEFORE an existing pet line is count-stable and
#   behaviorally dead on that path (the FF-B1 class this fix round closed for every current
#   site — (16) kills the known sites; the guard for NEW sites is the A3 derivation comment's
#   completion rule + review discipline). Likewise the HOLD loop's heartbeat_ping call
#   (observability only).
#
# RED-LOG PROVENANCE (fix round): the archived scratchpad red-block52.log predates the FINAL
# committed revision of this suite (the wedge driver's inner subshell and the (7) UNREACHABLE
# sentinel moved after capture). The panel re-ran the COMMITTED suite against pristine d7150ec
# and reproduced the IDENTICAL per-case outcome set (11 passed / 34 failed, same case ids;
# byte diff confined to bash error line numbers ±6, the (5b) summary, and the (7) sentinel
# relocation) — red-first discipline holds on outcomes, not bytes. The fix round's own reds
# are archived as red-block52-fixround.log (this suite vs the pre-fix daemons).

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
FENCE="$HARNESS_DIR/systemd/failover-fence.sh"
BASH_BIN="${BASH:-/bin/bash}"

title_banner "Monitor-side fence integration (v0.7 Block 5.2) — pets, READY/EXTEND, markers, №8"

# ── shared fixtures ─────────────────────────────────────────────────────────────────────────────
WORK=$(mktemp -d "${TMPDIR:-/tmp}/wd52.XXXXXX")
STUB_DIR="$WORK/stubs"; mkdir -p "$STUB_DIR"

# agave-validator FILE stub (subprocess — the daemons invoke "$SOLANA_PATH/agave-validator").
# identity.seq: one line per contact-info call, sticky-last; FAIL/empty = unreadable.
# monitor.seq: one line per `monitor` probe call, sticky-last; START = startup-phase output.
cat > "$STUB_DIR/agave-validator" <<'STUB'
#!/bin/sh
_pop() {
    f="$MOCK_DIR/$1"
    [ -f "$f" ] || { echo ""; return; }
    head -1 "$f"
    n=$(wc -l < "$f")
    if [ "$n" -gt 1 ]; then tail -n +2 "$f" > "$f.t" && mv "$f.t" "$f"; fi
}
case "$*" in
    *contact-info*)
        echo "av:contact-info" >> "$EV"
        line=$(_pop identity.seq)
        case "$line" in ""|FAIL) exit 1 ;; esac
        echo "Identity: $line"; exit 0 ;;
    *monitor*)
        echo "av:probe" >> "$EV"
        line=$(_pop monitor.seq)
        if [ "$line" = "START" ]; then echo "Validator startup: LoadingLedger (starting)"; else echo "Processed Slot: 1234"; fi
        exit 0 ;;
    *authorized-voter*remove-all*) echo "av:remove-all" >> "$EV"; exit 0 ;;
    *authorized-voter*add*)        echo "av:add" >> "$EV"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/agave-validator"

new_mock() {
    MOCK_DIR=$(mktemp -d "$WORK/m.XXXXXX")
    EV="$MOCK_DIR/events"; : > "$EV"
    mkdir -p "$MOCK_DIR/markers" "$MOCK_DIR/proc_root"
    export MOCK_DIR EV
}
up_fixture() { printf '%s.00 0.00\n' "$1" > "$MOCK_DIR/proc_root/uptime"; }
ev_grep()  { grep -c "$1" "$EV" 2>/dev/null | tr -d '[:space:]'; }
ev_line()  { grep -n "$1" "$EV" 2>/dev/null | head -1 | cut -d: -f1; }
ev_lastline() { grep -n "$1" "$EV" 2>/dev/null | tail -1 | cut -d: -f1; }

# In-shell shims, re-applied after every load_seam. timeout handles BOTH call shapes in the
# daemons: `timeout -k K DUR cmd…` and `timeout DUR cmd…` (get_local_identity).
wd_shims() {
    timeout() { if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@"; }
    socat() { local _p; _p=$(cat); _p="${_p//$'\n'/|}"; printf 'sd:%s\n' "$_p" >> "$EV"; return 0; }
    pgrep() { local _p; _p=$(cat "$MOCK_DIR/proc" 2>/dev/null); [ "$_p" = "1" ] && { echo 424242; return 0; }; return 1; }
    _harness_register wd_shims
}
harness_clock_shims
harness_silence_sinks
wd_shims

# ── drivers (each runs in a $() SUBSHELL and echoes a k=v| summary — counters stay in this shell) ──

# helpers driver: $1=daemon $2=armed(0/1) → summary of direct-helper behavior
drive_helpers() {
    local script="$1" armed="$2"
    (
        set +e
        _SIM_NOW=1700000000
        load_seam "$script"
        SLEPT=""
        sleep() { SLEPT="$SLEPT $1"; }
        if [[ "$armed" == "1" ]]; then NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        _watchdog_pet                       # pre-READY: must send nothing even when armed
        pre_ready_sd=$(ev_grep '^sd:')
        _watchdog_ready
        ready_sd=$(ev_grep '^sd:READY=1')
        _watchdog_pet
        pet_sd=$(ev_grep '^sd:WATCHDOG=1')
        mainpid_ok=1
        if [[ "$armed" == "1" ]]; then grep -q '^sd:.*|MAINPID=' "$EV" || mainpid_ok=0; fi
        _watchdog_extend_startup
        ext_sd=$(ev_grep '^sd:EXTEND_TIMEOUT_USEC=60000000')
        SLEPT=""
        _watchdog_sleep 25
        chunks="$SLEPT"
        # inert marker consumption: no marker dir at all
        FENCE_MARKER_DIR="$MOCK_DIR/no-such-dir"
        _fence_demoted_pending=0
        _consume_fence_markers; cfm_rc=$?
        printf 'pre=%s|ready=%s|pet=%s|ext=%s|mainpid=%s|chunks=%s|cfm=%s|pending=%s|total=%s\n' \
            "$pre_ready_sd" "$ready_sd" "$pet_sd" "$ext_sd" "$mainpid_ok" "${chunks# }" "$cfm_rc" "$_fence_demoted_pending" "$(ev_grep '^sd:')"
    )
}

# wait-loop driver: $1=daemon $2=armed $3=identity-plan $4=monitor-plan $5=proc(0/1)
# The REAL region between the wait banner and the READY call, wrapped in a function.
drive_waitloop() {
    local script="$1" armed="$2" idplan="$3" monplan="$4" proc="$5"
    (
        set +e
        _SIM_NOW=1700000000
        load_seam "$script"
        region=$(extract_region "$script" '# Wait for.*validator' 'READY=1 strictly after') || { echo "region=EMPTY"; exit 0; }
        eval "startup_wait_seam() {
$region
}"
        printf '%b' "$idplan"  > "$MOCK_DIR/identity.seq"
        printf '%b' "$monplan" > "$MOCK_DIR/monitor.seq"
        echo "$proc" > "$MOCK_DIR/proc"
        SOLANA_PATH="$STUB_DIR"; LEDGER_PATH="/x"; VALIDATOR_TYPE="agave"
        STAKED_PUBKEY=S1; _persisted_role=""; STARTUP_STAKED_UNREACHABLE_ALERT_SECS=180
        _running=true; CURRENT_IDENTITY=""
        heartbeat_ping() { :; }
        _W=0
        log_warn() { case "$*" in *"NOT extending"*) echo "warn:not-extending" >> "$EV" ;; esac; }
        sleep() { _SIM_NOW=$(( _SIM_NOW + 5 )); _W=$(( _W + 1 )); [[ $_W -ge 6 ]] && _running=false; }
        if [[ "$armed" == "1" ]]; then NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        # inner subshell: the never-ready path exits 0 via the region's own `exit` — the summary
        # below must still print (all counts come from the event log)
        ( startup_wait_seam ); rc=$?
        W_WARNS=$(ev_grep 'warn:not-extending')
        ready_n=$(ev_grep '^sd:READY=1')
        ext_n=$(ev_grep '^sd:EXTEND_TIMEOUT_USEC=60000000')
        wd_n=$(ev_grep '^sd:WATCHDOG=1')
        probe_n=$(ev_grep '^av:probe')
        last_read=$(ev_lastline '^av:contact-info'); ready_at=$(ev_line '^sd:READY=1')
        order=ok
        if [[ -n "$ready_at" ]]; then
            [[ -n "$last_read" && $ready_at -gt $last_read ]] || order=bad
            first_wd=$(ev_line '^sd:WATCHDOG=1')
            [[ -n "$first_wd" && $first_wd -lt $ready_at ]] && order=bad
        fi
        printf 'rc=%s|ready=%s|ext=%s|wd=%s|probes=%s|warns=%s|order=%s\n' \
            "$rc" "$ready_n" "$ext_n" "$wd_n" "$probe_n" "$W_WARNS" "$order"
    )
}

# cycle driver: the REAL standby main-loop region, ops stubbed as event-logging no-ops.
# $1=script $2=armed $3=wedge(0/1) $4=pending-demoted(0/1)
# $5=interval override (optional: sets CHECK_INTERVAL + _current_interval — the cycle-tail
#    sleep length, for the (17) chunking cases)  $6=prewarm knob (optional, for (11l))
drive_cycle() {
    local script="$1" armed="$2" wedge="$3" pending="$4" interval="$5" prewarm="$6"
    (
        set +e
        _SIM_NOW=1700000000
        load_seam "$script"
        region=$(extract_region "$script" '^while \$_running; do' '^done$') || { echo "region=EMPTY"; exit 0; }
        eval "run_cycle() {
$region
}"
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }
        flush_pending_alerts() { :; }; display_status() { :; }; save_state() { :; }
        window_push() { :; }; window_mostly_clear() { return 1; }
        get_local_identity() { echo "U1"; }
        tier1_check_local_health() { echo "op:t1" >> "$EV"; return 0; }
        if [[ "$wedge" == "1" ]]; then
            local_check_delinquency() { echo "op:ld-start" >> "$EV"; exit 99; }
        else
            local_check_delinquency() { echo "op:ld" >> "$EV"; return 1; }
        fi
        UNSTAKED_PUBKEY=U1; STAKED_PUBKEY=S1
        _last_heartbeat=$_SIM_NOW; _unknown_identity_since=0
        FENCE_MARKER_DIR="$MOCK_DIR/markers"
        # (11l) fixture: a REAL (stub-backed) _prewarm_voter_add so a call leaked outside the
        # takeover-delay window (the M11x mutant class) is observable as an av:add event.
        SOLANA_PATH="$STUB_DIR"; LEDGER_PATH="/x"; VALIDATOR_TYPE="agave"
        SETIDENTITY_TIMEOUT=15; STAKED_KEYPAIR="$MOCK_DIR/staked.json"; printf '[1]' > "$MOCK_DIR/staked.json"
        DRY_RUN=false; _prewarm_done=0
        [[ -n "$prewarm" ]] && PREWARM_VOTER_ADD="$prewarm"
        if [[ "$pending" == "1" ]]; then
            _fence_demoted_pending=1
            printf 'old demote outcome\n' > "$MOCK_DIR/markers/fenced-demoted"
        else
            _fence_demoted_pending=0
        fi
        SLEPT=""
        sleep() { SLEPT="$SLEPT $1"; _running=false; }
        if [[ -n "$interval" ]]; then CHECK_INTERVAL="$interval"; _current_interval="$interval"; fi
        if [[ "$armed" == "1" ]]; then NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        if [[ "$wedge" == "1" ]]; then
            # the wedged op exits the shell it runs in — inner subshell so the summary still prints
            ( _running=true; run_cycle ); rc=$?
        else
            _running=true
            run_cycle
            rc=$?
        fi
        wd_n=$(ev_grep '^sd:WATCHDOG=1')
        total=$(wc -l < "$EV" | tr -d '[:space:]')
        lastpet=0
        [[ -n "$(ev_lastline '^sd:WATCHDOG=1')" && "$(ev_lastline '^sd:WATCHDOG=1')" == "$total" ]] && lastpet=1
        after_wedge=0
        wl=$(ev_line 'op:ld-start')
        if [[ -n "$wl" ]]; then
            aw=$(ev_lastline '^sd:WATCHDOG=1')
            [[ -n "$aw" && $aw -gt $wl ]] && after_wedge=1
        fi
        mk=0; [[ -e "$MOCK_DIR/markers/fenced-demoted" ]] && mk=1
        printf 'rc=%s|wd=%s|lastpet=%s|afterwedge=%s|marker=%s|pending=%s|slept=%s|adds=%s\n' \
            "$rc" "$wd_n" "$lastpet" "$after_wedge" "$mk" "${_fence_demoted_pending:-?}" "${SLEPT# }" "$(ev_grep '^av:add')"
    )
}

# primary cycle driver ((9d)/(17b), fix round): the REAL PRIMARY main-loop region — clean
# UNSTAKED manual-mode cycle. $1=armed $2=pending-demoted(0/1) $3=interval override (optional)
drive_cycle_primary() {
    local armed="$1" pending="$2" interval="$3"
    (
        set +e
        _SIM_NOW=1700000000
        load_seam "$PRIMARY"
        region=$(extract_region "$PRIMARY" '^while \$_running; do' '^done$') || { echo "region=EMPTY"; exit 0; }
        eval "run_cycle() {
$region
}"
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }
        flush_pending_alerts() { :; }; display_status() { :; }; save_state() { :; }
        window_push() { :; }; window_mostly_clear() { return 1; }
        check_internet() { echo "op:inet" >> "$EV"; return 0; }
        get_local_identity() { echo "U1"; }
        UNSTAKED_PUBKEY=U1; STAKED_PUBKEY=S1
        RECOVERY_MODE=manual
        _last_known_identity=U1; LAST_SWITCH_TIME=$_SIM_NOW
        _last_recovery_log=$_SIM_NOW; _last_heartbeat=$_SIM_NOW; _unknown_identity_since=0
        FENCE_MARKER_DIR="$MOCK_DIR/markers"
        if [[ "$pending" == "1" ]]; then
            _fence_demoted_pending=1
            printf 'old demote outcome\n' > "$MOCK_DIR/markers/fenced-demoted"
        else
            _fence_demoted_pending=0
        fi
        SLEPT=""
        sleep() { SLEPT="$SLEPT $1"; _running=false; }
        if [[ -n "$interval" ]]; then CHECK_INTERVAL="$interval"; _current_interval="$interval"; fi
        if [[ "$armed" == "1" ]]; then NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        _running=true
        run_cycle; rc=$?
        mk=0; [[ -e "$MOCK_DIR/markers/fenced-demoted" ]] && mk=1
        printf 'rc=%s|wd=%s|marker=%s|pending=%s|slept=%s\n' \
            "$rc" "$(ev_grep '^sd:WATCHDOG=1')" "$mk" "${_fence_demoted_pending:-?}" "${SLEPT# }"
    )
}

# marker-consumption driver (non-HOLD paths): $1=script $2=fixture (stale|demoted|pageonly|vanish)
drive_markers() {
    local script="$1" fixture="$2"
    (
        set +e
        _SIM_NOW=$(command date +%s)
        load_seam "$script"
        FENCE_MARKER_DIR="$MOCK_DIR/markers"
        FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
        _fence_demoted_pending=0
        WARNS=0; PAGES=0; INFOS=0
        log_warn() { case "$*" in *"STALE fenced-stopped"*) WARNS=$((WARNS+1)) ;; esac; }
        alert() { PAGES=$((PAGES+1)); }
        alert_warn() { case "$*" in *"stale fenced-stopped"*) PAGES=$((PAGES+1)) ;; esac; }
        alert_info() { INFOS=$((INFOS+1)); }
        case "$fixture" in
            stale)
                up_fixture 100
                printf '2020-01-01T00:00:00Z old\n' > "$MOCK_DIR/markers/fenced-stopped"
                touch -t 202001010000 "$MOCK_DIR/markers/fenced-stopped" ;;
            demoted)
                up_fixture 100
                printf '2020-01-01T00:00:00Z demoted\n' > "$MOCK_DIR/markers/fenced-demoted"
                touch -t 202001010000 "$MOCK_DIR/markers/fenced-demoted" ;;
            pageonly)
                up_fixture 30000
                printf 'page-only twin fired\n' > "$MOCK_DIR/markers/fenced-page-only" ;;
            vanish)
                # HOLD-3 (fix round): the operator clears the marker BETWEEN the [[ -e ]] test
                # and the freshness stat — modeled by a _marker_same_boot that deletes the file
                # and returns 1 (exactly what its failed stat path does on a vanished file).
                # Expected: SILENT normal startup — no stale warn, no stale page.
                up_fixture 30000
                printf 'now stopped\n' > "$MOCK_DIR/markers/fenced-stopped"
                _marker_same_boot() { rm -f "$1"; return 1; } ;;
        esac
        _consume_fence_markers; rc=$?
        stopped=0; [[ -e "$MOCK_DIR/markers/fenced-stopped" ]] && stopped=1
        pageonly=0; [[ -e "$MOCK_DIR/markers/fenced-page-only" ]] && pageonly=1
        printf 'rc=%s|warns=%s|pages=%s|infos=%s|pending=%s|stopped=%s|pageonly=%s\n' \
            "$rc" "$WARNS" "$PAGES" "$INFOS" "$_fence_demoted_pending" "$stopped" "$pageonly"
    )
}

# HOLD driver: same-boot fenced-stopped; the mocked sleep advances SIM past ALERT_THROTTLE and
# removes the marker on the 3rd iteration (the operator's clear).
# M6 fix (test-honesty, fix round): the monitoring/takeover ENTRYPOINTS are stubbed to LOG a
# bait event — case (7) asserts ZERO such events across the HOLD iterations, so re-enabling ANY
# monitoring logic inside the HOLD loop (the panel's M6 mutant: attempt_takeover /
# local_check_delinquency spliced into the while-loop) trips the case. The superset covers both
# daemons; defining a stub the script never had is harmless.
_HOLD_BAITS="attempt_takeover local_check_delinquency tier1_check_local_health
tier2_check_delinquency tier3_confirm_delinquency confirm_delinquency_external
take_staked_identity give_back_identity check_self_fence_isolation check_identity_collision
get_local_identity verify_delinquency_tiered verify_latency_tiered tier1_check_delinquency
tier1_get_vote_latency switch_to_unstaked switch_to_staked attempt_safe_recovery
check_standby_has_identity check_primary_dropped_identity staked_is_actively_voting
get_staked_liveness_sample peer_has_relinquished _prewarm_voter_add _check_rpc_delinquency
_check_single_rpc _selffence_hard_stop _selffence_demote curl systemctl"
drive_hold() {
    local script="$1"
    (
        set +e
        _SIM_NOW=$(command date +%s)
        load_seam "$script"
        FENCE_MARKER_DIR="$MOCK_DIR/markers"
        FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
        up_fixture 30000
        printf 'now stopped\n' > "$MOCK_DIR/markers/fenced-stopped"
        NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000
        STAKED_PUBKEY=S1; ALERT_THROTTLE=600; CHECK_INTERVAL=5
        alert() { printf 'A:%s\n' "$3" >> "$EV"; }
        alert_info() { printf 'AI:%s\n' "$1" >> "$EV"; }
        heartbeat_ping() { echo "hb" >> "$EV"; }
        for _bait in $_HOLD_BAITS; do
            eval "$_bait() { echo \"bait:$_bait\" >> \"\$EV\"; return 1; }"
        done
        _HN=0
        sleep() { _HN=$((_HN+1)); _SIM_NOW=$(( _SIM_NOW + 400 )); [[ $_HN -ge 3 ]] && rm -f "$MOCK_DIR/markers/fenced-stopped"; }
        _consume_fence_markers
        echo "UNREACHABLE" >> "$EV"     # exit 0 inside must terminate the subshell before this line
    )
    HOLD_RC=$?
}

# startup-order driver ((15), fix round HOLD-1): fatal-inducing config (nonexistent
# SOLANA_PATH — the first fatal gate would exit 1) PLUS a same-boot fenced-stopped marker.
# Marker consumption must run FIRST: HOLD entered (pages), operator clear → exit 0 — never the
# fatal's exit 1 (which, under the armed unit, would loop through OnFailure → fence-breaker →
# restart → exit 1, forever).
drive_startup_order() {
    local script="$1"
    (
        set +e
        _SIM_NOW=$(command date +%s)
        load_seam "$script"
        FENCE_MARKER_DIR="$MOCK_DIR/markers"
        FENCE_PROC_ROOT="$MOCK_DIR/proc_root"
        up_fixture 30000
        printf 'now stopped\n' > "$MOCK_DIR/markers/fenced-stopped"
        SOLANA_PATH="/nonexistent-solana-path"; VALIDATOR_TYPE="agave"
        STAKED_PUBKEY=""; ALERT_THROTTLE=600; CHECK_INTERVAL=5
        alert() { printf 'A:%s\n' "$3" >> "$EV"; }
        alert_info() { printf 'AI:%s\n' "$1" >> "$EV"; }
        log_error() { case "$*" in *"not found"*) echo "FATAL-GATE" >> "$EV" ;; esac; }
        heartbeat_ping() { :; }
        _HN=0
        sleep() { _HN=$((_HN+1)); _SIM_NOW=$(( _SIM_NOW + 400 )); [[ $_HN -ge 3 ]] && rm -f "$MOCK_DIR/markers/fenced-stopped"; }
        ( startup_checks ) >/dev/null 2>&1
        rc=$?
        printf 'rc=%s|holdpages=%s|fatal=%s\n' "$rc" "$(ev_grep '^A:FENCED (stopped)')" "$(ev_grep 'FATAL-GATE')"
    )
}

# fence subprocess runner (part D) — trimmed from test_fence_script.sh (same stub semantics).
FSTUB="$WORK/fence-stubs"; mkdir -p "$FSTUB"
cat > "$FSTUB/agave-validator" <<'STUB'
#!/bin/sh
echo "agave-validator $*" >> "$EVENTS"
case "$*" in
    *contact-info*) exit 1 ;;
    *monitor*) [ -f "$FMOCK/monitor.out" ] && cat "$FMOCK/monitor.out"; exit 0 ;;
esac
exit 0
STUB
cat > "$FSTUB/systemctl" <<'STUB'
#!/bin/sh
echo "systemctl $*" >> "$EVENTS"
case "$*" in
    stop\ *) echo 0 > "$FMOCK/proc" ;;
esac
exit 0
STUB
cat > "$FSTUB/pgrep" <<'STUB'
#!/bin/sh
p=$(cat "$FMOCK/proc" 2>/dev/null)
if [ "$p" = "1" ]; then echo 2147483647; exit 0; fi
exit 1
STUB
cat > "$FSTUB/timeout" <<'STUB'
#!/bin/sh
shift 3
cmd="$1"; shift
case "$cmd" in */agave-validator|agave-validator) exec agave-validator "$@" ;; esac
exec "$cmd" "$@"
STUB
printf '#!/bin/sh\nexit 0\n' > "$FSTUB/sleep"
chmod +x "$FSTUB"/*
run_fence() {   # $1..: extra env — needs FMOCK + EVENTS prepared
    env -i PATH="$FSTUB:/usr/bin:/bin" \
        EVENTS="$EVENTS" FMOCK="$FMOCK" \
        FENCE_MARKER_DIR="$FMOCK/markers" \
        SOLANA_PATH=/mock LEDGER_PATH=/mock/ledger \
        UNSTAKED_PUBKEY=U1 UNSTAKED_KEYPAIR="$FMOCK/unstaked.json" \
        SETIDENTITY_TIMEOUT=15 FENCE_REPOLL_SECS=1 \
        MONITOR_UNIT=solana-failover-monitor.service VALIDATOR_UNIT=sol-test.service \
        "$@" "$BASH_BIN" "$FENCE" > "$FMOCK/out" 2>&1
    FRC=$?
}

# prewarm driver: $1=knob $2=dry $3=identity $4=action (add|add2|reset|reset2)
drive_prewarm() {
    local knob="$1" dry="$2" ident="$3" action="$4"
    (
        set +e
        _SIM_NOW=1700000000
        load_seam "$STANDBY"
        SOLANA_PATH="$STUB_DIR"; LEDGER_PATH="/x"; VALIDATOR_TYPE="agave"
        SETIDENTITY_TIMEOUT=15; STAKED_KEYPAIR="$MOCK_DIR/staked.json"; printf '[1]' > "$MOCK_DIR/staked.json"
        STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; CURRENT_IDENTITY="$ident"
        PREWARM_VOTER_ADD="$knob"; DRY_RUN="$dry"; _prewarm_done=0
        case "$action" in
            add)   _prewarm_voter_add ;;
            add2)  _prewarm_voter_add; _prewarm_voter_add ;;
            reset) _prewarm_voter_add; _prewarm_reset ;;
            reset2) _prewarm_voter_add; _prewarm_reset; _prewarm_reset ;;
        esac
        printf 'adds=%s|removes=%s|done=%s\n' "$(ev_grep '^av:add')" "$(ev_grep '^av:remove-all')" "${_prewarm_done:-?}"
    )
}

# ── (1) inertness ───────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) structural inertness: no NOTIFY_SOCKET → zero datagrams anywhere ───"
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    new_mock
    out=$(drive_helpers "$script" 0)
    if [[ "$(field "$out" total)" == "0" && "$(field "$out" chunks)" == "25" && "$(field "$out" cfm)" == "0" && "$(field "$out" pending)" == "0" ]]; then
        ok "(1a) $name: helpers un-armed → 0 datagrams, one MONOLITHIC sleep 25, marker no-op ($out)"
    else
        bad "(1a) $name: inertness broken: $out"
    fi
    new_mock
    out=$(drive_waitloop "$script" 0 'FAIL\nFAIL\nU1\n' 'START\n' 1)
    if [[ "$(field "$out" ready)" == "0" && "$(field "$out" ext)" == "0" && "$(field "$out" wd)" == "0" && "$(field "$out" probes)" == "0" ]]; then
        ok "(1b) $name: wait-loop un-armed → 0 datagrams AND 0 startup probes (the probe is inside the gate)"
    else
        bad "(1b) $name: wait-loop not inert: $out"
    fi
done
new_mock
out=$(drive_cycle "$STANDBY" 0 0 0)
[[ "$(field "$out" wd)" == "0" ]] \
    && ok "(1c) full simulated cycle un-armed → zero datagrams ($out)" \
    || bad "(1c) cycle not inert: $out"

# ── (2) READY gate on pets ──────────────────────────────────────────────────────────────────────
echo ""; echo "─── (2) armed helpers: no pet before READY; READY then pet; MAINPID claim present ───"
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    new_mock
    out=$(drive_helpers "$script" 1)
    if [[ "$(field "$out" pre)" == "0" && "$(field "$out" ready)" == "1" && "$(field "$out" pet)" -ge 1 && "$(field "$out" ext)" == "1" && "$(field "$out" mainpid)" == "1" ]]; then
        ok "(2) $name: pre-READY pet silent, READY=1 once, WATCHDOG=1 after, EXTEND=60000000, MAINPID claimed ($out)"
    else
        bad "(2) $name: helper protocol wrong: $out"
    fi
done

# ── (3) wait-loop READY/EXTEND ──────────────────────────────────────────────────────────────────
echo ""; echo "─── (3) armed wait-loop: EXTEND per confirmed iteration, READY only after the first read ───"
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    new_mock
    out=$(drive_waitloop "$script" 1 'FAIL\nFAIL\nU1\n' 'START\n' 1)
    if [[ "$(field "$out" ready)" == "1" && "$(field "$out" ext)" == "2" && "$(field "$out" order)" == "ok" ]]; then
        ok "(3) $name: 2 failed reads → 2 EXTENDs; READY exactly once, AFTER the successful read, no WATCHDOG before it ($out)"
    else
        bad "(3) $name: READY/EXTEND protocol wrong: $out"
    fi
done

# ── (4) EXTEND stops when the evidence lapses ───────────────────────────────────────────────────
echo ""; echo "─── (4) evidence lapses → no more EXTENDs + the not-extending warn (the fence path opens) ───"
new_mock
out=$(drive_waitloop "$STANDBY" 1 'FAIL\n' 'START\nSTART\nPLAIN\n' 1)
if [[ "$(field "$out" ext)" == "2" && "$(field "$out" ready)" == "0" && "$(field "$out" warns)" -ge 1 ]]; then
    ok "(4a) evidence held 2 iterations → exactly 2 EXTENDs, then none; not-extending warned; no READY ($out)"
else
    bad "(4a) lapse handling wrong: $out"
fi
new_mock
out=$(drive_waitloop "$STANDBY" 1 'FAIL\n' 'START\n' 0)
if [[ "$(field "$out" ext)" == "0" && "$(field "$out" warns)" -ge 1 ]]; then
    ok "(4b) process GONE → zero EXTENDs even with a startup-looking probe (evidence = alive AND starting)"
else
    bad "(4b) process-gone still extended: $out"
fi

# ── (5) cycle pets ──────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (5) armed cycle: pet after the identity read + end-of-cycle pet; wedge stops pets ───"
new_mock
out=$(drive_cycle "$STANDBY" 1 0 0)
if [[ "$(field "$out" wd)" == "3" && "$(field "$out" lastpet)" == "1" ]]; then
    ok "(5a) completed cycle: exactly 3 pets (post-identity-read + end-of-cycle + the chunked inter-cycle sleep's chunk pet), the LAST event is a pet ($out)"
else
    bad "(5a) cycle pet count/order wrong: $out"
fi
new_mock
out=$(drive_cycle "$STANDBY" 1 1 0)
if [[ "$(field "$out" rc)" == "99" && "$(field "$out" wd)" == "1" && "$(field "$out" afterwedge)" == "0" ]]; then
    ok "(5b) wedged op: the cycle died inside the op → NO pet at/after the op's start (wedge detection = the pets' absence)"
else
    bad "(5b) wedged-op pets wrong: $out"
fi
MUT="$_HARNESS_TMP/standby-nopet.sh"
if mutate "$STANDBY" '/§5 end-of-cycle pet/d' "$MUT"; then
    new_mock
    out=$(drive_cycle "$MUT" 1 0 0)
    if [[ "$(field "$out" wd)" == "2" ]]; then
        ok "(5c) CONTROL: end-of-cycle pet deleted → count drops 3→2 — (5a) genuinely observes that line"
    else
        bad "(5c) control vacuous (mutant still petted): $out"
    fi
fi

# ── (6) _watchdog_sleep chunking ────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) _watchdog_sleep: armed → 10s chunks + pet per chunk; un-armed covered in (1a) ───"
new_mock
out=$(drive_helpers "$STANDBY" 1)
if [[ "$(field "$out" chunks)" == "10 10 5" ]]; then
    ok "(6) armed _watchdog_sleep 25 → chunks '10 10 5' (a pet after each completed chunk; never mid-sleep)"
else
    bad "(6) chunking wrong: $out"
fi

# ── (7) HOLD ────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (7) same-boot fenced-stopped → HOLD: page + re-page, READY + pets, operator clear → exit 0 ───"
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    new_mock
    drive_hold "$script"
    pages=$(ev_grep '^A:FENCED (stopped)')
    ready_n=$(ev_grep '^sd:READY=1')
    wd_n=$(ev_grep '^sd:WATCHDOG=1')
    exits=$(ev_grep '^AI:')
    unreach=$(ev_grep 'UNREACHABLE')
    baits=$(ev_grep '^bait:')
    if [[ "$HOLD_RC" == "0" && "$pages" == "2" && "$ready_n" == "1" && "$wd_n" -ge 3 && "$exits" == "1" && "$unreach" == "0" && "$baits" == "0" ]]; then
        ok "(7) $name: HOLD paged 2x (initial + throttled re-page), READY once + $wd_n pets, ZERO monitoring-logic bait events across the loop (M6 guard), exit 0 on the operator's clear"
    else
        bad "(7) $name: HOLD wrong (rc=$HOLD_RC pages=$pages ready=$ready_n wd=$wd_n exits=$exits unreach=$unreach baits=$baits$([[ ${baits:-0} != 0 ]] && echo " — first: $(grep '^bait:' "$EV" | head -1)"))"
    fi
done

# ── (8) stale marker ────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) STALE (pre-boot) fenced-stopped → warn + page once, NO hold, file kept ───"
new_mock
out=$(drive_markers "$STANDBY" stale)
if [[ "$(field "$out" rc)" == "0" && "$(field "$out" warns)" == "1" && "$(field "$out" pages)" -ge 1 && "$(field "$out" stopped)" == "1" && "$(field "$out" pending)" == "0" ]]; then
    ok "(8) stale marker: returned (no HOLD, no exit), warned + paged once, marker file KEPT (operator evidence) ($out)"
else
    bad "(8) stale marker handling wrong: $out"
fi
new_mock
out=$(drive_markers "$STANDBY" vanish)
if [[ "$(field "$out" rc)" == "0" && "$(field "$out" warns)" == "0" && "$(field "$out" pages)" == "0" && "$(field "$out" stopped)" == "0" ]]; then
    ok "(8b) HOLD-3: marker VANISHED between the existence test and the freshness stat (operator clear mid-check) → SILENT normal startup — no stale warn, no stale page ($out)"
else
    bad "(8b) vanished-marker race still pages a 'stale marker present' notice about a nonexistent file: $out"
fi

# ── (9) demoted-marker lifecycle ────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) fenced-demoted (any age) → noted; cleared on the FIRST clean cycle; page-only ignored ───"
new_mock
out=$(drive_markers "$STANDBY" demoted)
if [[ "$(field "$out" rc)" == "0" && "$(field "$out" pending)" == "1" && "$(field "$out" infos)" == "1" ]]; then
    ok "(9a) startup: demoted marker (2020 mtime — ANY age) noted, alert_info once, pending flag set ($out)"
else
    bad "(9a) demoted-at-startup wrong: $out"
fi
new_mock
out=$(drive_cycle "$STANDBY" 0 0 1)
if [[ "$(field "$out" marker)" == "0" && "$(field "$out" pending)" == "0" ]]; then
    ok "(9b) first CLEAN cycle: fenced-demoted marker removed + pending flag cleared (§2.2 contract)"
else
    bad "(9b) first-clean-cycle clear failed: $out"
fi
new_mock
out=$(drive_markers "$STANDBY" pageonly)
if [[ "$(field "$out" rc)" == "0" && "$(field "$out" pages)" == "0" && "$(field "$out" infos)" == "0" && "$(field "$out" pending)" == "0" && "$(field "$out" pageonly)" == "1" ]]; then
    ok "(9c) fenced-page-only IGNORED (not an input to the two-outcome state machine; file untouched)"
else
    bad "(9c) page-only marker not ignored: $out"
fi
new_mock
out=$(drive_cycle_primary 0 1)
if [[ "$(field "$out" marker)" == "0" && "$(field "$out" pending)" == "0" ]]; then
    ok "(9d) PRIMARY first CLEAN cycle: fenced-demoted marker removed + pending flag cleared (the panel's M7-primary mutant — the primary's clear hunk is outside the byte-parity block, so (9b) alone never covered it)"
else
    bad "(9d) primary first-clean-cycle clear failed: $out"
fi

# ── (10) part D: two consecutive dispatch cycles terminate ──────────────────────────────────────
echo ""; echo "─── (10) part D: dispatch 1 (evidence) = no stop; extend refused between; dispatch 2 = STOP ───"
FMOCK=$(mktemp -d "$WORK/f.XXXXXX"); mkdir -p "$FMOCK/markers"; EVENTS="$FMOCK/events"; : > "$EVENTS"
echo 1 > "$FMOCK/proc"; echo '[9,9]' > "$FMOCK/unstaked.json"
printf 'Validator startup: LoadingLedger (starting)\n' > "$FMOCK/monitor.out"
run_fence
d1_stop=$(grep -c 'systemctl stop' "$EVENTS" | tr -d '[:space:]')
d1_restart=$(grep -c 'systemctl restart' "$EVENTS" | tr -d '[:space:]')
if [[ "$FRC" == "0" && "$d1_stop" == "0" && "$d1_restart" == "1" && ! -e "$FMOCK/markers/fenced-stopped" ]]; then
    ok "(10a) dispatch 1: third branch (unreadable + startup evidence) → monitor restarted, NO stop, NO marker"
else
    bad "(10a) dispatch 1 wrong: rc=$FRC stop=$d1_stop restart=$d1_restart"
fi
new_mock
out=$(drive_waitloop "$STANDBY" 1 'FAIL\n' 'PLAIN\n' 1)
if [[ "$(field "$out" ext)" == "0" && "$(field "$out" warns)" -ge 1 ]]; then
    ok "(10b) restarted monitor, same evidence definition: NO extension (identity failing, no startup evidence) → the start TIMES OUT into dispatch 2"
else
    bad "(10b) monitor extended without evidence: $out"
fi
: > "$EVENTS"
printf 'Processed Slot: 1234\n' > "$FMOCK/monitor.out"
echo 1 > "$FMOCK/proc"
run_fence
d2_stop=$(grep -c 'systemctl stop' "$EVENTS" | tr -d '[:space:]')
if [[ "$d2_stop" -ge 1 && -e "$FMOCK/markers/fenced-stopped" ]]; then
    ok "(10c) dispatch 2: NO startup evidence → the STOP path (fenced-stopped) — the loop TERMINATES on the second pass"
else
    bad "(10c) dispatch 2 did not stop: rc=$FRC stop=$d2_stop markers=$(ls "$FMOCK/markers" 2>/dev/null | tr '\n' ' ')"
fi

# ── (11) №8 pre-warm lever ──────────────────────────────────────────────────────────────────────
echo ""; echo "─── (11) №8: default-off zero calls; once per episode; reset hygiene; DRY_RUN; drift wording ───"
new_mock
out=$(drive_prewarm "false" false U1 add)
[[ "$(field "$out" adds)" == "0" && "$(field "$out" removes)" == "0" ]] \
    && ok "(11a) default-off (false): ZERO admin calls ($out)" \
    || bad "(11a) default-off issued calls: $out"
new_mock
out=$(drive_prewarm "" false U1 add)
[[ "$(field "$out" adds)" == "0" ]] \
    && ok "(11b) unset knob behaves false: zero calls ($out)" \
    || bad "(11b) unset knob issued calls: $out"
new_mock
out=$(drive_prewarm true false U1 add2)
[[ "$(field "$out" adds)" == "1" ]] \
    && ok "(11c) enabled: authorized-voter add issued exactly ONCE per episode (second call same episode = no-op)" \
    || bad "(11c) per-episode add wrong: $out"
new_mock
out=$(drive_prewarm true false U1 reset)
[[ "$(field "$out" adds)" == "1" && "$(field "$out" removes)" == "1" && "$(field "$out" done)" == "0" ]] \
    && ok "(11d) episode reset while UNSTAKED: remove-all hygiene fired once, episode flag cleared ($out)" \
    || bad "(11d) reset hygiene wrong: $out"
new_mock
out=$(drive_prewarm true false S1 reset)
[[ "$(field "$out" removes)" == "0" && "$(field "$out" done)" == "0" ]] \
    && ok "(11e) episode reset while HOLDING STAKED: NO remove-all (would stop live voting; give-back owns that lifecycle)" \
    || bad "(11e) reset removed a live voter: $out"
new_mock
out=$(drive_prewarm true true U1 add)
[[ "$(field "$out" adds)" == "0" && "$(field "$out" removes)" == "0" ]] \
    && ok "(11f) DRY_RUN: enabled lever issues NOTHING (§2.3: zero admin-socket mutations)" \
    || bad "(11f) DRY_RUN issued calls: $out"
d_out=$(drift_out "$STANDBY" 'PREWARM_VOTER_ADD=true')
if [[ "$(printf '%s\n' "$d_out" | grep -c '\[config-drift\]')" == "1" && "$d_out" == *"LIVE-TEST-GATED"* && "$d_out" == *"testnet on-chain observation window"* ]]; then
    ok "(11g) drift announce: PREWARM_VOTER_ADD=true → one line with the LIVE-TEST-GATED wording"
else
    bad "(11g) drift announce wrong: $d_out"
fi
d_out=$(drift_out "$STANDBY" 'PREWARM_VOTER_ADD=false')
[[ -z "$d_out" ]] \
    && ok "(11h) drift announce: explicit false (the default) is silent" \
    || bad "(11h) default announced: $d_out"
delay_region=$(sed -n '/Takeover delay:/,/fast-path early-exit/p' "$STANDBY")
if printf '%s\n' "$delay_region" | grep -q '_prewarm_voter_add'; then
    ok "(11i) call-site: _prewarm_voter_add sits INSIDE the takeover delay window (before the fast-path check)"
else
    bad "(11i) _prewarm_voter_add not called in the delay branch"
fi
if grep -q '_prewarm_reset' <<< "$(sed -n '/^window_reset() {/,/^}$/p' "$STANDBY")" && [[ "$(grep -c '_prewarm_reset' "$STANDBY")" -ge 3 ]]; then
    ok "(11j) reset sites: window_reset + the delinquency-cleared inline block both call _prewarm_reset"
else
    bad "(11j) _prewarm_reset sites missing ($(grep -c '_prewarm_reset' "$STANDBY") refs)"
fi
if ! grep -q '_prewarm' "$PRIMARY"; then
    ok "(11k) PRIMARY carries NO prewarm machinery (STANDBY-only lever)"
else
    bad "(11k) prewarm text leaked into the primary"
fi
new_mock
out=$(drive_cycle "$STANDBY" 0 0 0 "" true)
if [[ "$(field "$out" adds)" == "0" ]]; then
    ok "(11l) M11x guard: a FULL non-delay cycle with the lever ON issues ZERO authorized-voter adds — a _prewarm_voter_add call leaked outside the takeover-delay window (the panel's surviving M11x mutant) trips this"
else
    bad "(11l) pre-warm call escaped the takeover-delay window: $out"
fi

# ── (12) byte-identity ──────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (12) twins: [watchdog] block P↔S; _marker_same_boot + _startup_phase_evidence daemon↔fence ───"
if extract_twin '\[watchdog\] monitor-side fence integration' '\[watchdog\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(12a) [watchdog] shared block BYTE-IDENTICAL in both daemons ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)"
else
    bad "(12a) [watchdog] block missing or DIVERGED between the daemons"
fi
F_MSB=$(extract_region "$FENCE"   '^_marker_same_boot() {' '^}$')
P_MSB=$(extract_region "$PRIMARY" '^_marker_same_boot() {' '^}$')
S_MSB=$(extract_region "$STANDBY" '^_marker_same_boot() {' '^}$')
if [[ -n "$F_MSB" && "$F_MSB" == "$P_MSB" && "$F_MSB" == "$S_MSB" ]]; then
    ok "(12b) _marker_same_boot BYTE-IDENTICAL across fence + both daemons (same-boot semantics, ALL ends)"
else
    bad "(12b) _marker_same_boot diverged (fence=${#F_MSB}B primary=${#P_MSB}B standby=${#S_MSB}B)"
fi
F_SPE=$(extract_region "$FENCE"   '^_startup_phase_evidence() {' '^}$')
P_SPE=$(extract_region "$PRIMARY" '^_startup_phase_evidence() {' '^}$')
S_SPE=$(extract_region "$STANDBY" '^_startup_phase_evidence() {' '^}$')
if [[ -n "$F_SPE" && "$F_SPE" == "$P_SPE" && "$F_SPE" == "$S_SPE" ]]; then
    ok "(12c) _startup_phase_evidence BYTE-IDENTICAL across fence + both daemons (ONE evidence definition — the part-D termination argument rests on it)"
else
    bad "(12c) _startup_phase_evidence diverged (fence=${#F_SPE}B primary=${#P_SPE}B standby=${#S_SPE}B)"
fi

# ── (13) zero-inertness grep-proof + gate mutant ────────────────────────────────────────────────
echo ""; echo "─── (13) no watchdog-transport token in CODE outside the [watchdog] block; the gate mutant leaks ───"
# Widened pattern (inertness nit, fix round): the old socat|NOTIFY_SOCKET grep was narrower
# than the inertness contract — a future ungated WATCHDOG_USEC / payload-string reference
# outside the block would have passed unnoticed. Trailing comments are stripped first (the
# wait-loop/HOLD comments legitimately NAME these tokens; the contract is about CODE).
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    leaks=$(sed '/\[watchdog\] monitor-side fence integration/,/\[watchdog\] end shared block/d' "$script" \
        | sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[[:space:]].*$//' \
        | grep -nE 'socat|NOTIFY_SOCKET|WATCHDOG_USEC|READY=1|WATCHDOG=1|EXTEND_TIMEOUT_USEC')
    if [[ -z "$leaks" ]]; then
        ok "(13a) $name: zero socat/NOTIFY_SOCKET/WATCHDOG_USEC/READY=1/WATCHDOG=1/EXTEND_TIMEOUT_USEC code references outside the [watchdog] block"
    else
        bad "(13a) $name: transport token in code outside the gated block: $(printf '%s' "$leaks" | head -2 | tr '\n' ' ')"
    fi
done
MUTG="$_HARNESS_TMP/standby-gate-open.sh"
if mutate "$STANDBY" 's/_watchdog_active() {/_watchdog_active() { return 0;/' "$MUTG"; then
    new_mock
    out=$( (
        set +e
        _SIM_NOW=1700000000
        load_seam "$MUTG"
        unset NOTIFY_SOCKET; unset WATCHDOG_USEC
        _WATCHDOG_READY=1
        _watchdog_pet
        printf 'sd=%s\n' "$(ev_grep '^sd:')"
    ) )
    if [[ "$(field "$out" sd)" -ge 1 ]]; then
        ok "(13b) CONTROL: gate forced open → a datagram leaks with NO NOTIFY_SOCKET — (1)'s zero-count genuinely observes the gate"
    else
        bad "(13b) control vacuous (open gate still sent nothing): $out"
    fi
fi

# ── structural: pet CALL-count pins (CI-pin idiom) + sleeps routed via _watchdog_sleep ─────────
echo ""; echo "─── (14) structural pins: pet CALL counts (comments don't count) + sleep routing ───"
# (14a) END-OF-CYCLE pet CALL lines (the M1 class, fix round): the grep matches the CALL —
# `^[[:space:]]*_watchdog_pet[[:space:]]+# §5 end-of-cycle pet` — so a mutant that neuters the
# call while keeping the comment (`:   # §5 end-of-cycle pet…`) drops the count and trips here
# (the old comment-text grep could not see that). Pins: primary 5, standby 4.
p_pets=$(grep -cE '^[[:space:]]*_watchdog_pet[[:space:]]+# §5 end-of-cycle pet' "$PRIMARY")
s_pets=$(grep -cE '^[[:space:]]*_watchdog_pet[[:space:]]+# §5 end-of-cycle pet' "$STANDBY")
[[ "$p_pets" == "5" && "$s_pets" == "4" ]] \
    && ok "(14a) end-of-cycle pet CALL lines: primary 5, standby 4 (every sleep/continue + the tail; call+comment on one line)" \
    || bad "(14a) end-of-cycle pet CALL lines wrong (primary=$p_pets standby=$s_pets — a call deleted/neutered under its comment, or an unpinned new site)"
# (14b) TOTAL `_watchdog_pet` call sites per daemon (the CI-pin idiom, stored in the suite):
# pattern `^[[:space:]]*_watchdog_pet\b` counts call lines PLUS the one function-definition
# line — pins are therefore calls+1. Deleting or `:`-neutering ANY pet call line (the per-op
# one-liner class included) moves the count → red. A count change is a review-stop: a
# legitimate new/removed site updates this pin in the same diff, with the A3 derivation
# re-checked. Pins: primary 35 (34 calls + def), standby 36 (35 calls + def; the +1 over the
# primary is _giveback_wedged_escalate's identity-re-read pet, FF-B1 fix round).
p_total=$(grep -cE '^[[:space:]]*_watchdog_pet\b' "$PRIMARY")
s_total=$(grep -cE '^[[:space:]]*_watchdog_pet\b' "$STANDBY")
[[ "$p_total" == "35" && "$s_total" == "36" ]] \
    && ok "(14b) total pet call-site pins: primary 34 calls (+def=35), standby 35 calls (+def=36) — deletion of any pet line trips this" \
    || bad "(14b) total pet call-site count moved (primary=$p_total pinned 35, standby=$s_total pinned 36) — a pet line was added/deleted; re-derive the A3 arithmetic and move the pin in the same diff"
if ! grep -qE '^[[:space:]]*sleep "\$STARTUP_GRACE"' "$PRIMARY" && ! grep -qE '^[[:space:]]*sleep "\$STARTUP_GRACE"' "$STANDBY" && ! grep -qE '^[[:space:]]*sleep "\$RECOVERY_CHECK_INTERVAL"' "$PRIMARY"; then
    ok "(14c) the >=15s sleeps (STARTUP_GRACE x3, RECOVERY_CHECK_INTERVAL, hard-stop re-verify) go through _watchdog_sleep"
else
    bad "(14c) a monolithic long sleep survives (would starve WatchdogSec=30 under the unit)"
fi
if ! grep -qE '^[[:space:]]*sleep "\$\{HARD_STOP_REVERIFY_SECS' "$PRIMARY" && ! grep -qE '^[[:space:]]*sleep "\$\{HARD_STOP_REVERIFY_SECS' "$STANDBY"; then
    ok "(14d) hard-stop re-verify wait chunked too (env-raised values must not starve the watchdog)"
else
    bad "(14d) hard-stop re-verify still a monolithic sleep"
fi
# (14e) FF-B3 structural: no plain inter-cycle sleep survives in either main loop / HOLD.
if ! grep -qE '^[[:space:]]*sleep "\$CHECK_INTERVAL"|^[[:space:]]*sleep "\$_current_interval"|^[[:space:]]*sleep "\$\{CHECK_INTERVAL' "$PRIMARY" \
   && ! grep -qE '^[[:space:]]*sleep "\$CHECK_INTERVAL"|^[[:space:]]*sleep "\$_current_interval"|^[[:space:]]*sleep "\$\{CHECK_INTERVAL' "$STANDBY"; then
    ok "(14e) every main-loop/HOLD inter-cycle sleep goes through _watchdog_sleep (FF-B3/HOLD-B1: any legal CHECK_INTERVAL/TURBO_INTERVAL is armed-safe)"
else
    bad "(14e) a plain inter-cycle sleep survives — a legal CHECK_INTERVAL >= ~28s starves WatchdogSec=30 under the armed unit"
fi

# ── (15) HOLD-1: marker consumption precedes EVERY fatal startup gate ──────────────────────────
echo ""; echo "─── (15) fatal-inducing config + same-boot marker → HOLD entered, no exit-1 loop ───"
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    new_mock
    out=$(drive_startup_order "$script")
    if [[ "$(field "$out" rc)" == "0" && "$(field "$out" holdpages)" -ge 1 && "$(field "$out" fatal)" == "0" ]]; then
        ok "(15) $name: fenced node + fatal config → HOLD first (paged, operator clear → exit 0); the fatal gate never ran ($out)"
    else
        bad "(15) $name: pre-marker fatal still wins → exit-1 → OnFailure → fence-breaker loop on a fenced node ($out)"
    fi
done

# ── (16) FF-B1/FF-B2: completed (timed-out) ops are petted before escalation/early return ──────
echo ""; echo "─── (16) wedged demote + unreachable tiers: pet AFTER the completed timed-out op ───"
new_mock
out=$( (
    set +e
    _SIM_NOW=1700000000
    load_seam "$PRIMARY"
    NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1
    DRY_RUN=false; VALIDATOR_TYPE=agave; SOLANA_PATH="$STUB_DIR"; LEDGER_PATH=/x
    UNSTAKED_KEYPAIR="$MOCK_DIR/uk.json"; printf '[1]' > "$MOCK_DIR/uk.json"
    STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; SETIDENTITY_TIMEOUT=15
    # admin ops wedge (rc 124); the _sd_notify socat pipeline passes through to the sd: logger
    timeout() { case "$*" in (*socat*) if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@" ;; (*) echo "op:wedge" >> "$EV"; return 124 ;; esac; }
    _selffence_hard_stop() { echo "op:hardstop" >> "$EV"; return 1; }
    get_tower_path() { echo "$MOCK_DIR/tower"; }
    switch_to_unstaked "FF-B1 probe"
    w=$(ev_line 'op:wedge'); h=$(ev_line 'op:hardstop'); p=$(ev_line '^sd:WATCHDOG=1')
    okr=0; [[ -n "$p" && -n "$w" && -n "$h" && $p -gt $w && $p -lt $h ]] && okr=1
    printf 'order=%s|wedge=%s|pet=%s|hard=%s\n' "$okr" "$w" "$p" "$h"
) )
[[ "$(field "$out" order)" == "1" ]] \
    && ok "(16a) PRIMARY switch_to_unstaked rc-124: pet lands AFTER the completed timed-out op and BEFORE _selffence_hard_stop (the 40 s pet-free stack is closed) ($out)" \
    || bad "(16a) primary wedged demote enters the hard stop without petting the completed op: $out"
new_mock
out=$( (
    set +e
    _SIM_NOW=1700000000
    load_seam "$STANDBY"
    NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1
    DRY_RUN=false; VALIDATOR_TYPE=agave; SOLANA_PATH="$STUB_DIR"; LEDGER_PATH=/x
    UNSTAKED_KEYPAIR="$MOCK_DIR/uk.json"; printf '[1]' > "$MOCK_DIR/uk.json"
    STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; SETIDENTITY_TIMEOUT=15
    # admin ops wedge (rc 124); the _sd_notify socat pipeline passes through to the sd: logger
    timeout() { case "$*" in (*socat*) if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@" ;; (*) echo "op:wedge" >> "$EV"; return 124 ;; esac; }
    _selffence_hard_stop() { echo "op:hardstop" >> "$EV"; return 1; }
    get_local_identity() { echo "op:idread" >> "$EV"; printf ''; }
    window_reset() { :; }
    give_back_identity "FF-B1 probe"
    w=$(ev_line 'op:wedge'); i=$(ev_line 'op:idread'); h=$(ev_line 'op:hardstop')
    p1=$(ev_line '^sd:WATCHDOG=1')
    p2=""
    if [[ -n "$i" ]]; then p2=$(grep -n '^sd:WATCHDOG=1' "$EV" | awk -F: -v i="$i" '$1 > i { print $1; exit }'); fi
    okr=0; [[ -n "$p1" && -n "$w" && -n "$i" && $p1 -gt $w && $p1 -lt $i ]] && okr=1
    okr2=0; [[ -n "$p2" && -n "$h" && $p2 -gt $i && $p2 -lt $h ]] && okr2=1
    printf 'order=%s|order2=%s|wedge=%s|idread=%s|hard=%s\n' "$okr" "$okr2" "$w" "$i" "$h"
) )
[[ "$(field "$out" order)" == "1" && "$(field "$out" order2)" == "1" ]] \
    && ok "(16b) STANDBY give-back rc-124: pet after the wedged op AND after the escalate's identity re-read, both BEFORE the hard stop (the 48 s pet-free stack is closed) ($out)" \
    || bad "(16b) standby wedged give-back/escalate runs pet-free: $out"
new_mock
out=$( (
    set +e
    _SIM_NOW=1700000000
    load_seam "$PRIMARY"
    NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1
    STAKED_PUBKEY=S1; VOTE_PUBKEY=""
    curl() { echo "op:curlfail" >> "$EV"; return 28; }
    _check_rpc_delinquency "http://t2" "TIER2"; rc=$?
    c=$(ev_line 'op:curlfail'); p=$(ev_line '^sd:WATCHDOG=1')
    okr=0; [[ -n "$p" && -n "$c" && $p -gt $c ]] && okr=1
    printf 'rc=%s|order=%s\n' "$rc" "$okr"
) )
[[ "$(field "$out" rc)" == "2" && "$(field "$out" order)" == "1" ]] \
    && ok "(16c) PRIMARY _check_rpc_delinquency unreachable path: rc 2 AND a pet after the completed curl (FF-B2: >=1 pet per completed 15 s curl) ($out)" \
    || bad "(16c) primary unreachable-tier path returns pet-free: $out"
new_mock
out=$( (
    set +e
    _SIM_NOW=1700000000
    load_seam "$STANDBY"
    NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1
    STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; MAX_DELINQUENT_SLOTS=0
    STAT_TIER2_CHECKS=0; STAT_TIER3_CHECKS=0; _turbo_mode=false
    TIER2_RPC="http://t2"; TIER3_RPC="http://t3"; LOCAL_RPC="http://l"
    curl() { echo "op:curlfail" >> "$EV"; return 28; }
    tier2_check_delinquency; r2=$?
    tier3_confirm_delinquency; r3=$?
    tier1_check_local_health; r1=$?
    local_check_delinquency; rl=$?
    pets=$(ev_grep '^sd:WATCHDOG=1'); curls=$(ev_grep 'op:curlfail')
    printf 'r2=%s|r3=%s|r1=%s|rl=%s|pets=%s|curls=%s\n' "$r2" "$r3" "$r1" "$rl" "$pets" "$curls"
) )
if [[ "$(field "$out" r2)" == "2" && "$(field "$out" r3)" == "2" && "$(field "$out" r1)" == "1" && "$(field "$out" rl)" == "2" && "$(field "$out" pets)" == "$(field "$out" curls)" && "$(field "$out" pets)" -ge 4 ]]; then
    ok "(16d) STANDBY tier2/tier3/tier1-health/local-delinq unreachable paths: rcs unchanged AND one pet per completed curl — the both-externals-hanging confirm has no >=30 s pet-free span ($out)"
else
    bad "(16d) a standby unreachable path returns pet-free (or an rc changed): $out"
fi

# ── (17) FF-B3/HOLD-B1: the inter-cycle sleep is chunked under the armed unit ──────────────────
echo ""; echo "─── (17) armed cycle at CHECK_INTERVAL=45: chunked sleep + pets through it; un-armed monolithic ───"
new_mock
out=$(drive_cycle "$STANDBY" 1 0 0 45)
if [[ "$(field "$out" slept)" == "10 10 10 10 5" && "$(field "$out" wd)" == "7" ]]; then
    ok "(17a) STANDBY armed, CHECK_INTERVAL=45: sleep chunked '10 10 10 10 5' + a pet per chunk (7 total) — the legal-interval starvation class is closed ($out)"
else
    bad "(17a) standby armed 45 s inter-cycle sleep not chunked (PID 1 would fence a HEALTHY node every cycle): $out"
fi
new_mock
out=$(drive_cycle_primary 1 0 45)
if [[ "$(field "$out" slept)" == "10 10 10 10 5" && "$(field "$out" wd)" == "7" ]]; then
    ok "(17b) PRIMARY armed, CHECK_INTERVAL=45: sleep chunked '10 10 10 10 5' + a pet per chunk (7 total) ($out)"
else
    bad "(17b) primary armed 45 s inter-cycle sleep not chunked: $out"
fi
new_mock
out=$(drive_cycle "$STANDBY" 0 0 0 45)
if [[ "$(field "$out" slept)" == "45" && "$(field "$out" wd)" == "0" ]]; then
    ok "(17c) un-armed control: ONE monolithic sleep 45, zero datagrams — structural inertness holds through the routing ($out)"
else
    bad "(17c) un-armed inter-cycle sleep behavior changed: $out"
fi

# ── (18) FF-1/FF-4: EXTEND after the H3 alert; armed-only startup re-page ──────────────────────
echo ""; echo "─── (18) wait loop: EXTEND re-sent after the H3 alert; throttled pre-READY re-page (armed only) ───"
drive_wait_alert() {   # $1=armed
    local armed="$1"
    (
        set +e
        _SIM_NOW=1700000000
        load_seam "$STANDBY"
        region=$(extract_region "$STANDBY" '# Wait for.*validator' 'READY=1 strictly after') || { echo "region=EMPTY"; exit 0; }
        eval "startup_wait_seam() {
$region
}"
        printf 'FAIL\nFAIL\nFAIL\nFAIL\nFAIL\nU1\n' > "$MOCK_DIR/identity.seq"
        printf 'START\n' > "$MOCK_DIR/monitor.seq"
        echo 1 > "$MOCK_DIR/proc"
        SOLANA_PATH="$STUB_DIR"; LEDGER_PATH="/x"; VALIDATOR_TYPE="agave"
        STAKED_PUBKEY=S1; _persisted_role="staked"; STARTUP_STAKED_UNREACHABLE_ALERT_SECS=1
        ALERT_THROTTLE=10
        _running=true; CURRENT_IDENTITY=""
        heartbeat_ping() { :; }
        alert() { echo "op:alert" >> "$EV"; }
        alert_warn() { case "$*" in *"still in startup"*) echo "op:repage" >> "$EV" ;; esac; }
        sleep() { _SIM_NOW=$(( _SIM_NOW + 5 )); }
        if [[ "$armed" == "1" ]]; then NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        ( startup_wait_seam )
        a=$(ev_line 'op:alert')
        nexte=""
        [[ -n "$a" ]] && nexte=$(grep -n '^sd:EXTEND_TIMEOUT_USEC=60000000' "$EV" | awk -F: -v a="$a" '$1 > a { print $1; exit }')
        nextread=""
        [[ -n "$a" ]] && nextread=$(grep -n '^av:contact-info' "$EV" | awk -F: -v a="$a" '$1 > a { print $1; exit }')
        immed=0
        if [[ -n "$nexte" ]]; then
            if [[ -z "$nextread" || $nexte -lt $nextread ]]; then immed=1; fi
        fi
        printf 'alerts=%s|ext=%s|immed=%s|repages=%s\n' \
            "$(ev_grep 'op:alert')" "$(ev_grep '^sd:EXTEND_TIMEOUT_USEC=60000000')" "$immed" "$(ev_grep 'op:repage')"
    )
}
new_mock
out=$(drive_wait_alert 1)
if [[ "$(field "$out" alerts)" == "1" && "$(field "$out" ext)" == "7" && "$(field "$out" immed)" == "1" && "$(field "$out" repages)" -ge 1 ]]; then
    ok "(18a) armed: H3 alert once; EXTEND re-sent BEFORE and AFTER it in the same iteration (5 evidence iterations → 7 EXTENDs; the 72 s flap+alert panel gap closes to <= 52/33 s); throttled 'still in startup' re-page fired ($out)"
else
    bad "(18a) alert-iteration EXTEND/re-page wrong (pristine sends 5 EXTENDs and 0 re-pages): $out"
fi
new_mock
out=$(drive_wait_alert 0)
if [[ "$(field "$out" ext)" == "0" && "$(field "$out" repages)" == "0" ]]; then
    ok "(18b) un-armed control: zero EXTENDs AND zero re-pages — the FF-4 re-page is armed-only (v0.6.9 hosts keep log-only waiting) ($out)"
else
    bad "(18b) FF-4 re-page leaked into un-armed behavior (inertness break): $out"
fi

# raw-data traces for the report
echo ""
echo "  (report) armed-cycle events:  $(new_mock; drive_cycle "$STANDBY" 1 0 0)"
echo "  (report) waitloop (standby):  $(new_mock; drive_waitloop "$STANDBY" 1 'FAIL\nFAIL\nU1\n' 'START\n' 1)"

rm -rf "$WORK"
results_banner
