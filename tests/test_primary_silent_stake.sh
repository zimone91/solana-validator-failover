#!/bin/bash
# v0.7 (rc2 F21): THE SILENT STAKE. An UNSTAKED primary whose spare's host is dead leaves the staked identity with nobody voting it; in Alpenglow mode the primary
# never takes it back, so the only thing FO can give the operator is a page - and there was none (S18b on the testnet pair, 2266130: 420 s in RECOVERY_MODE=manual
# and 720 s in rpc without one page). The UNSTAKED branch of the main loop now calls _silent_stake_cycle BEFORE the RECOVERY_MODE dispatch: it reads the staked vote
# account's public lastVote and the cluster tip (get_staked_liveness_sample) once per VOTE_LIVENESS_MIN_INTERVAL, and pages `STAKED IDENTITY SILENT 🚨` once the
# lastVote has been frozen for SILENT_STAKE_PAGE_SECS while the tip advanced. Monitor-only. This suite drives the REAL main-loop region of the shipped primary (the
# gap_world / pl_run technique): every cycle of a PLAN runs through the real text, with the clock, the identity read, the internet check and the liveness reader
# mocked, and an ordered event log "T=<offset> <what>" recording what the cycle did.
#   PLAN = space-separated cycles, 5 s apart (CHECK_INTERVAL=5, VOTE_LIVENESS_MIN_INTERVAL=10, so the reader is called at offsets 0, 10, 20, ...): S staked / U
#   unstaked / K an identity that is neither; a trailing `a` marks an identity change made by the daemon itself (LAST_SWITCH_TIME is stamped: not a manual change);
#   X:N = N copies. SCHED = the staked vote account as the providers show it, one entry "<from offset>|<lastVote>|<tip>|<tier>" per change: lastVote is a number,
#   `grow` (5000 + 2 per second) or `down` (no provider answers); tip is `adv` (9000 + 2 per second), `const` (9000) or `fix<N>` (stays at N); tier T2 / T3.
#   (0)  the world runs the real loop (a sanity check of this suite's own harness)
#   (a)  frozen lastVote for SILENT_STAKE_PAGE_SECS (90): ONE page, status `STAKED IDENTITY SILENT 🚨`, the span in the text ("frozen for 90s", the lastVote, the tip);
#        the first read at which the span is >= the knob (offset 100: the first frozen pair is at 10); a knob one second longer pages nothing in the same run
#   (b)  the episode persists: a second page only after ALERT_THROTTLE (120: offsets 100 and 220; the default 600: one page)
#   (c)  the votes resume: ONE INFO line "votes again ... after 120s", the anchor and the page state cleared; a new freeze is a new episode and pages at once, inside
#        the old throttle (offsets 100 and 260 with ALERT_THROTTLE 600)
#   (d)  RECOVERY_MODE=manual and rpc both page (the rpc pass returns at its first gate, "Still delinquent (Tier 1) - not recovering", and must not suppress it)
#   (e)  a STAKED cycle never samples and clears the episode (a staked-only plan: no read, no page; a staked cycle between two unstaked stretches restarts the span: 150 not 100;
#        (e3) and forgets the episode's start: the next resume counts 70 s, not 120)
#   (f)  startup: SILENT_STAKE_PAGE_SECS has a floor of 30 (29, abc and empty refuse to start; 30 and 90 pass); the standby has no such knob; the drift table announces a
#        value below 90 (a failover that works would page) and above it (the page is late); 90 is silent
#   (g)  structure by text: one default (daemon, primary template, primary wizard), ONE call in the UNSTAKED arm before the RECOVERY_MODE dispatch, the resets in the
#        manual-change block and in the STAKED arm, no action in the code of the two functions (monitor-only by construction), nothing of it in the standby, the banner line
#   (h)  without VOTE_PUBKEY the page is off: no read, no page, and the banner says so
#   (i)  blind (no provider answers): no page, ONE WARN per ALERT_THROTTLE, the next read waits 30 s; an open episode is kept across blindness (the first readable frozen
#        read after 190 s pages)
#   (j)  a tip that does not advance (a cached view) - also one that froze AFTER the span started (j2: the baseline tip moves with every good read) -, (k) a lastVote that
#        goes backwards, (l) a change of provider: none is evidence of silence - no page; a provider change restarts an open span (offset 160, not 100), and the resume line
#        counts from the first frozen pair of the EPISODE (l2: 110 s after a change of provider, l3: 130 s after two spans)
#   (m)  a manual identity change is a new episode: the grace is not counted, the span restarts after it (215, not 115)
#   (n)  DRY_RUN pages the same as live (no action to simulate)
#   (o)  the take-path state (_liveness_*, _last_blind_end, _ep_*) is untouched by a whole episode
#   (p)  CONTROLS (mutate()): every mutant of the rule turns its case red
# RED ON THE BASE (2266130 + this suite): no _silent_stake_cycle, no SILENT_STAKE_PAGE_SECS: no page ever, the knob is accepted at any value, the census finds no call.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, mutate(), extract_region, drift_out.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "The silent stake: an unstaked primary pages when nobody votes the staked identity (v0.7 rc2 F21)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ssk.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cut_src() { local f="$WORK/seam.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$$.$RANDOM"; sed -n '1,/MAIN LOOP/p' "$1" > "$f"; printf '%s' "$f"; }
STK="StakedPubkey111111111111111111111111111111"
UNS="UnstakedPubkey1111111111111111111111111111"
UNK="SomeOtherIdentity11111111111111111111111111"
echo "  precondition: lines naming 'STAKED IDENTITY SILENT' in the daemon under test: $(grep -c 'STAKED IDENTITY SILENT' "$PRIMARY") (the base, 2266130: 0)"

# ── the world: the REAL loop region over a plan, an ordered event log ────────────────────────────────────────────────────
ss_world() {   # ss_world <script> <plan> [VAR=val ...] -> the events, one per line: T=<offset> CYCLE k / SAMPLE / PAGE <status> / TXT <text> / LOG <line> / LOGW <line> / ATTEMPT / COLLISION / GRACE n / STATE <take-path state>
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
        EV=$(mktemp); export EV; trap 'rm -f "$EV"' EXIT
        T_BASE=1700000000; _SIM_NOW=$T_BASE
        ev() { printf 'T=%s %s\n' "$(( _SIM_NOW - T_BASE ))" "$*" >> "$EV"; }
        PLAN=(); IDX=0
        for t in $plan; do
            case "$t" in
                *:*) b="${t%%:*}"; n="${t##*:}"; k=0; while [[ $k -lt $n ]]; do PLAN+=("$b"); k=$((k + 1)); done ;;
                *)   PLAN+=("$t") ;;
            esac
        done
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; UNSTAKED_KEYPAIR="$EV"; LEDGER_PATH="$EV.ledger"; VALIDATOR_TYPE=agave; LOCAL_RPC="http://mock-local"
        TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"; VOTE_PUBKEY="VoteAccount11111111111111111111111111111"
        TG_ENABLED=false; DRY_RUN=false; ALERT_THROTTLE=600; PRIMARY_SELF_FENCE=true; CHECK_INTERVAL=5; TURBO_INTERVAL=1; _current_interval=5
        CONNECTIVITY_RETRIES=99; MAX_VOTE_LATENCY=0; DELINQUENCY_RETRIES=1; STARTUP_GRACE=30; RECOVERY_MODE=manual; SETIDENTITY_TIMEOUT=15
        VOTE_LIVENESS_MIN_INTERVAL=10; SILENT_STAKE_PAGE_SECS=90
        SCHED="0|5000|adv|T2"
        # sentinels of the recovery ladder's and the take path's state: a whole episode must leave them as they are
        _liveness_first_vote=111; _liveness_first_tip=222; _liveness_first_ts=333; _liveness_first_provider=T9; _last_blind_end=444; _liveness_obs_since=555
        _ep_blind_cycles=6; _ep_provider_flips=7; _ep_floor_holds=8
        for kv in "$@"; do eval "$kv"; done
        mono_now() { echo "$_SIM_NOW"; }
        tok_id() { local t="${PLAN[$IDX]}"; printf '%s' "${t:0:1}"; }
        tok_has() { local t="${PLAN[$IDX]}"; [[ "${t:1}" == *"$1"* ]]; }
        _last_heartbeat=$(date +%s); HEARTBEAT_INTERVAL=2000000000
        case "$(tok_id)" in S) _last_known_identity="$STK" ;; K) _last_known_identity="$UNK" ;; *) _last_known_identity="$UNS" ;; esac
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _version_startup_check() { :; }; _vat_cycle() { :; }; _fence_rot_check() { :; }; _g2_step() { :; }; _elapsed_step() { :; }
        flush_pending_alerts() { :; }; display_status() { :; }; save_state() { :; }; _watchdog_pet() { :; }; send_telegram() { return 0; }; send_webhook() { :; }
        log_info() { case "$1" in *"[silent-stake]"*|*"UNSTAKED. manual mode"*|*"Still delinquent (Tier 1)"*) ev "LOG $1" ;; esac; }
        log_warn() { case "$1" in *"[silent-stake]"*) ev "LOGW $1" ;; esac; }
        log_error() { :; }
        alert() { ev "PAGE $3"; ev "TXT ${1:0:700}"; return 0; }
        alert_info() { :; }; alert_warn() { :; }
        get_local_identity() { case "$(tok_id)" in S) echo "$STAKED_PUBKEY" ;; U) echo "$UNSTAKED_PUBKEY" ;; K) echo "$UNK" ;; *) return 0 ;; esac; }
        check_internet() { return 0; }
        check_self_fence_isolation() { return 1; }
        check_identity_collision() { ev COLLISION; return 0; }
        tier1_check_delinquency() { return 1; }
        tier1_get_vote_latency() { echo 1; }
        verify_latency_tiered() { return 0; }
        _vat_hold() { return 1; }
        window_push() { :; }; window_count() { echo 0; }; window_triggered() { return 1; }; window_mostly_clear() { return 1; }; window_reset() { :; }
        switch_to_unstaked() { ev "DEMOTE $1"; return 0; }
        switch_to_staked() { ev "SWITCH-TO-STAKED $1"; return 1; }
        attempt_safe_recovery() { ev ATTEMPT; log_info "Still delinquent (Tier 1) — not recovering"; return 1; }   # the rpc pass: it returns at its first gate, every cycle (S18b)
        get_staked_liveness_sample() {   # the external vote-account read: "<lastVote> <cluster tip> <tier>" - as the schedule shows the account at this offset
            ev SAMPLE
            local d=$(( _SIM_NOW - T_BASE )) e cur="" off lv tp tier lvv tip
            for e in $SCHED; do off="${e%%|*}"; [[ $d -ge $off ]] && cur="$e"; done
            [[ -n "$cur" ]] || return 1
            IFS='|' read -r off lv tp tier <<< "$cur"
            case "$lv" in down) return 1 ;; grow) lvv=$(( 5000 + 2 * d )) ;; *) lvv=$lv ;; esac
            case "$tp" in adv) tip=$(( 9000 + 2 * d )) ;; fix*) tip="${tp#fix}" ;; *) tip=9000 ;; esac
            printf '%s %s %s\n' "$lvv" "$tip" "$tier"
        }
        _watchdog_sleep() {
            if [[ "$1" == "$STARTUP_GRACE" && "$1" != "$CHECK_INTERVAL" && "$1" != "$_current_interval" ]]; then
                ev "GRACE $1"; _SIM_NOW=$(( _SIM_NOW + $1 )); return 0   # the manual-change grace: a wait INSIDE a cycle, the cycle goes on
            fi
            _SIM_NOW=$(( _SIM_NOW + $1 ))
            IDX=$(( IDX + 1 ))
            if [[ $IDX -ge ${#PLAN[@]} ]]; then _running=false; else ev "CYCLE $IDX"; tok_has a && LAST_SWITCH_TIME=$_SIM_NOW; fi   # an `a` cycle: the daemon itself changed the identity just now
        }
        sleep() { :; }
        ev "CYCLE 0"
        _running=true; run_loop
        ev "STATE ${_liveness_first_vote} ${_liveness_first_tip} ${_liveness_first_ts} ${_liveness_first_provider} ${_last_blind_end} ${_liveness_obs_since} ${_ep_blind_cycles} ${_ep_provider_flips} ${_ep_floor_holds}"
        cat "$EV"
    ) 2>/dev/null
}
page_ats()   { printf '%s\n' "$1" | sed -n 's/^T=\([0-9-]*\) PAGE STAKED IDENTITY SILENT.*$/\1/p' | tr '\n' ' ' | sed 's/ $//'; }   # the offsets of the silent-stake pages
sample_ats() { printf '%s\n' "$1" | sed -n 's/^T=\([0-9-]*\) SAMPLE$/\1/p' | tr '\n' ' ' | sed 's/ $//'; }
n_of()       { printf '%s\n' "$1" | grep -c -F -e "$2"; }
txt_first()  { printf '%s\n' "$1" | sed -n 's/^T=[0-9-]* TXT \(nobody is voting.*\)$/\1/p' | head -1; }
state_of()   { printf '%s\n' "$1" | sed -n 's/^T=[0-9-]* STATE \(.*\)$/\1/p' | head -1; }
PAGE_TXT_90="nobody is voting the staked identity: public lastVote 5000 frozen for 90s (tip 9200); this node is UNSTAKED and never takes in Alpenglow mode — check the holder (the spare's host) and start it, or move the identity by the warm swap (docs/SAFETY.md)"

# ── (0) the world runs the real loop ────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (0) the harness: the real loop over a plan of unstaked cycles ───"
ev0=$(ss_world "$PRIMARY" "U U U")
if [[ "$(n_of "$ev0" 'CYCLE')" == "3" && "$(n_of "$ev0" ' CYCLE 2')" == "1" ]]; then
    ok "(0) three unstaked cycles run through the real main-loop region (events: $(printf '%s' "$ev0" | tr '\n' ';' | cut -c1-100))"
else
    bad "(0) the world does not run: $(printf '%s' "$ev0" | tr '\n' ';' | cut -c1-200)"
fi

# ── (a) the page: once, at the knob, with the span in the text ────────────────────────────────────────────────────────────
echo ""; echo "─── (a) a lastVote frozen for SILENT_STAKE_PAGE_SECS pages once; one second short pages nothing ───"
ev_a=$(ss_world "$PRIMARY" "U:22"); ev_a91=$(ss_world "$PRIMARY" "U:22" SILENT_STAKE_PAGE_SECS=91)
if [[ "$(page_ats "$ev_a")" == "100" && "$(txt_first "$ev_a")" == "$PAGE_TXT_90" && "$(page_ats "$ev_a91")" == "" ]]; then
    ok "(a) reads at offsets 0 (baseline), 10 (the first frozen pair: the span starts), 20, ...: ONE page at offset 100 - the first read with a span of 90 (the read at 90 has 80) - with the status 'STAKED IDENTITY SILENT 🚨' and the text 'lastVote 5000 frozen for 90s (tip 9200)'; the same run with the knob at 91 pages nothing (the span at 100 is 90)"
else
    bad "(a) pages at [$(page_ats "$ev_a")] (want 100), text [$(txt_first "$ev_a" | cut -c1-120)], knob 91 pages at [$(page_ats "$ev_a91")] (want none)"
fi
p_page_100() { [[ "$(page_ats "$1")" == "100" ]]; }
p_page_none_at_91() { [[ "$(page_ats "$1")" == "" ]]; }

# ── (b) the throttle ───────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (b) a persisting silence pages again only after ALERT_THROTTLE ───"
ev_b=$(ss_world "$PRIMARY" "U:50" ALERT_THROTTLE=120); ev_b6=$(ss_world "$PRIMARY" "U:50")
if [[ "$(page_ats "$ev_b")" == "100 220" && "$(page_ats "$ev_b6")" == "100" ]]; then
    ok "(b) ALERT_THROTTLE 120: pages at 100 and 220 (the read at 210 is 110 s after the first: nothing; 220 is 120: the repeat); the default 600: ONE page in 245 s"
else
    bad "(b) throttle 120 pages at [$(page_ats "$ev_b")] (want '100 220'), default 600 at [$(page_ats "$ev_b6")] (want 100)"
fi
p_throttle_120() { [[ "$(page_ats "$1")" == "100 220" ]]; }

# ── (c) the votes resume ───────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (c) the votes resume: one INFO line, the episode is over; a new freeze pages at once ───"
SCHED_C="0|5000|adv|T2 130|grow|adv|T2 160|8000|adv|T2"
ev_c=$(ss_world "$PRIMARY" "U:60" "SCHED='$SCHED_C'")
if [[ "$(page_ats "$ev_c")" == "100 260" && "$(n_of "$ev_c" 'staked identity votes again (lastVote 5260) after 120s')" == "1" && "$(n_of "$ev_c" 'votes again')" == "1" && "$(n_of "$ev_c" 'did not move while the cluster tip did')" == "2" ]]; then
    ok "(c) frozen from 10, paged at 100; the read at 130 shows lastVote 5260: ONE line '[silent-stake] staked identity votes again (lastVote 5260) after 120s'; frozen again at 8000 from 170: a NEW episode, paged at 260 - 160 s after the first page, inside ALERT_THROTTLE 600 (the resume cleared the page state); two 'did not move' start lines, one per episode"
else
    bad "(c) pages [$(page_ats "$ev_c")] (want '100 260'), resume lines $(n_of "$ev_c" 'votes again') (want 1), start lines $(n_of "$ev_c" 'did not move while the cluster tip did') (want 2)"
fi
p_resume_pages() { [[ "$(page_ats "$1")" == "100 260" ]]; }

# ── (d) both recovery modes ────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (d) RECOVERY_MODE=manual and rpc both page - the rpc pass's 'Still delinquent' must not suppress it ───"
ev_dm=$(ss_world "$PRIMARY" "U:22" RECOVERY_MODE=manual); ev_dr=$(ss_world "$PRIMARY" "U:22" RECOVERY_MODE=rpc)
if [[ "$(page_ats "$ev_dm")" == "100" && "$(n_of "$ev_dm" 'ATTEMPT')" == "0" && "$(n_of "$ev_dm" 'UNSTAKED. manual mode')" == "1" \
      && "$(page_ats "$ev_dr")" == "100" && "$(n_of "$ev_dr" 'ATTEMPT')" == "22" && "$(n_of "$ev_dr" 'Still delinquent (Tier 1)')" == "22" && "$(n_of "$ev_dr" 'SWITCH-TO-STAKED')" == "0" ]]; then
    ok "(d) manual: the page at 100 beside the branch's own 'UNSTAKED. manual mode' line; rpc: the recovery pass ran on all 22 cycles and returned at its first gate ('Still delinquent (Tier 1)' 22 times), no re-take, and the page still came at 100"
else
    bad "(d) manual pages [$(page_ats "$ev_dm")] attempts $(n_of "$ev_dm" 'ATTEMPT'); rpc pages [$(page_ats "$ev_dr")] attempts $(n_of "$ev_dr" 'ATTEMPT') gate-lines $(n_of "$ev_dr" 'Still delinquent (Tier 1)')"
fi
p_rpc_pages() { [[ "$(page_ats "$1")" == "100" && "$(n_of "$1" 'ATTEMPT')" == "22" ]]; }

# ── (e) a staked cycle ───────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (e) STAKED: never a read, never a page; a staked cycle clears the episode ───"
ev_e1=$(ss_world "$PRIMARY" "S:30"); ev_e2=$(ss_world "$PRIMARY" "U:9 Sa Ua U:20")
if [[ "$(n_of "$ev_e1" 'SAMPLE')" == "0" && "$(page_ats "$ev_e1")" == "" && "$(n_of "$ev_e1" 'COLLISION')" == "30" ]]; then
    ok "(e1) 30 staked cycles (the staked branch ran: 30 collision checks) over a frozen vote account: no read, no page"
else
    bad "(e1) staked plan: samples=$(n_of "$ev_e1" 'SAMPLE') pages=[$(page_ats "$ev_e1")] collision-checks=$(n_of "$ev_e1" 'COLLISION')"
fi
if [[ "$(page_ats "$ev_e2")" == "150" && "$(n_of "$ev_e2" 'COLLISION')" == "1" ]]; then
    ok "(e2) nine unstaked cycles (span 30 at the last read), ONE staked cycle (the daemon's own change, no manual-change grace), then unstaked again: the span restarts - baseline at 50, first frozen pair 60, page at 150 (without the clear it would be 100)"
else
    bad "(e2) pages [$(page_ats "$ev_e2")] (want 150), staked-branch cycles $(n_of "$ev_e2" 'COLLISION') (want 1)"
fi
p_staked_clears() { [[ "$(page_ats "$1")" == "150" ]]; }
SCHED_E3="0|5000|adv|T2 130|grow|adv|T2"
ev_e3=$(ss_world "$PRIMARY" "U:9 Sa Ua U:20" "SCHED='$SCHED_E3'")
if [[ "$(n_of "$ev_e3" 'staked identity votes again (lastVote 5260) after 70s')" == "1" && "$(n_of "$ev_e3" 'did not move while the cluster tip did')" == "2" && "$(page_ats "$ev_e3")" == "" ]]; then
    ok "(e3) a first span from 10, a staked cycle at 45 (the whole episode cleared), unstaked again from 50 (baseline 50, first frozen pair 60), the votes rise at 130 (5260): ONE line 'votes again (lastVote 5260) after 70s' - from the SECOND episode's first frozen pair, not from the first one's (120 s); no page (the longest span is 60 s)"
else
    bad "(e3) episode start forgotten across a staked cycle: resume=[$(n_of "$ev_e3" 'staked identity votes again (lastVote 5260) after 70s')] (want 1) starts=$(n_of "$ev_e3" 'did not move while the cluster tip did') (want 2) pages=[$(page_ats "$ev_e3")]"
fi
p_reset_clears_first() { [[ "$(n_of "$1" 'staked identity votes again (lastVote 5260) after 70s')" == "1" ]]; }

# ── (f) startup ────────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (f) startup: SILENT_STAKE_PAGE_SECS has a floor of 30; the drift table announces a value other than 90 ───"
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
r_def=$(rc_of "$PRIMARY"); r_29=$(rc_of "$PRIMARY" 'SILENT_STAKE_PAGE_SECS=29'); r_30=$(rc_of "$PRIMARY" 'SILENT_STAKE_PAGE_SECS=30'); r_90=$(rc_of "$PRIMARY" 'SILENT_STAKE_PAGE_SECS=90')
r_abc=$(rc_of "$PRIMARY" 'SILENT_STAKE_PAGE_SECS=abc'); r_empty=$(rc_of "$PRIMARY" 'SILENT_STAKE_PAGE_SECS='); r_10=$(rc_of "$PRIMARY" 'SILENT_STAKE_PAGE_SECS=10'); r_s=$(rc_of "$STANDBY" 'SILENT_STAKE_PAGE_SECS=abc')
if [[ "$r_def" == "0" && "$r_30" == "0" && "$r_90" == "0" && "$r_29" == "1" && "$r_10" == "1" && "$r_abc" == "1" && "$r_empty" == "1" && "$r_s" == "0" ]]; then
    ok "(f1) the default passes, 30 and 90 pass, 29, 10, 'abc' and the empty value refuse to start; the standby has no such knob ('abc' there changes nothing)"
else
    bad "(f1) knob: default=$r_def 30=$r_30 90=$r_90 29=$r_29 10=$r_10 abc=$r_abc empty=$r_empty standby-abc=$r_s"
fi
p_floor_30() { [[ "$(rc_of "$1" 'SILENT_STAKE_PAGE_SECS=29')" == "1" && "$(rc_of "$1" 'SILENT_STAKE_PAGE_SECS=30')" == "0" ]]; }
dr60=$(drift_out "$PRIMARY" 'SILENT_STAKE_PAGE_SECS=60'); dr120=$(drift_out "$PRIMARY" 'SILENT_STAKE_PAGE_SECS=120'); dr90=$(drift_out "$PRIMARY" 'SILENT_STAKE_PAGE_SECS=90'); drs=$(drift_out "$STANDBY" 'SILENT_STAKE_PAGE_SECS=60')
if [[ "$(n_of "$dr60" '[config-drift]')" == "1" && "$dr60" == *"SILENT_STAKE_PAGE_SECS=60 is laxer than this version's default 90"* && "$dr60" == *"TAKEOVER_DELAY"* \
      && "$(n_of "$dr120" '[config-drift]')" == "1" && "$dr120" == *"SILENT_STAKE_PAGE_SECS=120 is laxer than this version's default 90"* && "$dr120" == *"delays the page"* \
      && "$(n_of "$dr90" '[config-drift]')" == "0" && "$(n_of "$drs" '[config-drift]')" == "0" ]]; then
    ok "(f2) 60: ONE [config-drift] line (laxer than 90; names the spare's TAKEOVER_DELAY: a failover that works would page); 120: ONE line (the page is late); 90: silent; the standby: silent"
else
    bad "(f2) drift: 60=[$dr60] 120=[$dr120] 90=[$dr90] standby=[$drs]"
fi
p_drift_both() { [[ "$(drift_out "$1" 'SILENT_STAKE_PAGE_SECS=60' | grep -c '\[config-drift\]')" == "1" && "$(drift_out "$1" 'SILENT_STAKE_PAGE_SECS=120' | grep -c '\[config-drift\]')" == "1" ]]; }
p_drift_low() { [[ "$(drift_out "$1" 'SILENT_STAKE_PAGE_SECS=60' | grep -c '\[config-drift\]')" == "1" ]]; }

# ── (g) structure by text ────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (g) structure: one default, one call in the UNSTAKED arm before the dispatch, the resets, no action, nothing in the standby, the banner ───"
loop_code() { extract_region "$1" '^while \$_running; do' '^done$' | grep -v '^[[:space:]]*#'; }
fn_code() { sed -n "/^$2() {/,/^}/p" "$1" | grep -v '^[[:space:]]*#'; }
defs_p=$(grep -c -E '^SILENT_STAKE_PAGE_SECS=90( |$)' "$PRIMARY"); defs_t=$(grep -c -E '^SILENT_STAKE_PAGE_SECS=90( |$)' "$HARNESS_DIR/failover.env.example"); defs_w=$(grep -c -E '^SILENT_STAKE_PAGE_SECS=90$' "$HARNESS_DIR/deploy-failover.sh")
defs_any=$(grep -c -E '^SILENT_STAKE_PAGE_SECS=' "$PRIMARY")
if [[ "$defs_p" == "1" && "$defs_any" == "1" && "$defs_t" == "1" && "$defs_w" == "1" ]]; then
    ok "(g1) SILENT_STAKE_PAGE_SECS=90 is assigned once in the daemon, once in the primary template and once in the primary wizard's env text"
else
    bad "(g1) defaults: daemon=$defs_p (any=$defs_any) template=$defs_t wizard=$defs_w"
fi
lc=$(loop_code "$PRIMARY")
n_call=$(printf '%s\n' "$lc" | grep -c -E '^[[:space:]]*_silent_stake_cycle( |$)'); n_rst=$(printf '%s\n' "$lc" | grep -c -E '^[[:space:]]*_silent_stake_reset( |$)')
l_arm=$(printf '%s\n' "$lc" | grep -n -x -F '    elif [[ "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" ]]; then' | head -1 | cut -d: -f1)
l_call=$(printf '%s\n' "$lc" | grep -n -E '^[[:space:]]*_silent_stake_cycle( |$)' | head -1 | cut -d: -f1)
l_disp=$(printf '%s\n' "$lc" | grep -n -x -F '        if [[ "$RECOVERY_MODE" == "manual" ]]; then' | head -1 | cut -d: -f1)
l_stk=$(printf '%s\n' "$lc" | grep -n -x -F '    if [[ "$CURRENT_IDENTITY" == "$STAKED_PUBKEY" ]]; then' | head -1 | cut -d: -f1)
l_rst1=$(printf '%s\n' "$lc" | grep -n -E '^[[:space:]]*_silent_stake_reset( |$)' | sed -n 1p | cut -d: -f1); l_rst2=$(printf '%s\n' "$lc" | grep -n -E '^[[:space:]]*_silent_stake_reset( |$)' | sed -n 2p | cut -d: -f1)
if [[ "$n_call" == "1" && -n "$l_arm" && -n "$l_call" && -n "$l_disp" && $l_arm -lt $l_call && $l_call -lt $l_disp && "$n_rst" == "2" && -n "$l_stk" && "$l_rst2" == "$((l_stk + 1))" && $l_rst1 -lt $l_stk ]]; then
    ok "(g2) the loop calls _silent_stake_cycle once, in the UNSTAKED arm (line $l_arm), before the RECOVERY_MODE dispatch (line $l_disp, the call at $l_call); _silent_stake_reset twice: in the manual-change block (line $l_rst1) and as the first statement of the STAKED arm (line $l_rst2, the arm opens at $l_stk)"
else
    bad "(g2) calls=$n_call resets=$n_rst arm=$l_arm call=$l_call dispatch=$l_disp staked-arm=$l_stk resets-at=$l_rst1,$l_rst2"
fi
p_one_call_before_dispatch() { local c l1 l2 l3; c=$(loop_code "$1"); l1=$(printf '%s\n' "$c" | grep -n -x -F '    elif [[ "$CURRENT_IDENTITY" == "$UNSTAKED_PUBKEY" ]]; then' | head -1 | cut -d: -f1); l2=$(printf '%s\n' "$c" | grep -n -E '^[[:space:]]*_silent_stake_cycle( |$)' | head -1 | cut -d: -f1); l3=$(printf '%s\n' "$c" | grep -n -x -F '        if [[ "$RECOVERY_MODE" == "manual" ]]; then' | head -1 | cut -d: -f1); [[ -n "$l1" && -n "$l2" && -n "$l3" && $l1 -lt $l2 && $l2 -lt $l3 ]] && [[ "$(printf '%s\n' "$c" | grep -c -E '^[[:space:]]*_silent_stake_cycle( |$)')" == "1" ]]; }
act_re='switch_to_|set-identity|systemctl|attempt_safe_recovery|_selffence|window_|reset_recovery_liveness|_liveness_first|_last_blind_end|_ep_[a-z]|save_state|_ag_take|_hung_'
fn_all() { fn_code "$1" _silent_stake_cycle; grep '^_silent_stake_reset() {' "$1"; }   # the reset is a one-line function: taken whole
act_c=$(fn_all "$PRIMARY" | grep -c -E "$act_re")
body_c=$(fn_all "$PRIMARY" | grep -c .)
if [[ "$act_c" == "0" && $body_c -gt 20 && "$(grep -c '^_silent_stake_cycle() {' "$PRIMARY")" == "1" && "$(grep -c '^_silent_stake_reset() {' "$PRIMARY")" == "1" ]]; then
    ok "(g3) monitor-only by construction: the $body_c code lines of _silent_stake_cycle and _silent_stake_reset name no demote, take, set-identity, systemctl, recovery-pass, self-fence, window or take-path state (and each is defined once)"
else
    bad "(g3) action tokens in the code: $act_c (body $body_c lines)"
fi
p_no_action() { local n; n=$(fn_all "$1" | grep -c -E "$act_re"); [[ "$n" == "0" ]]; }
if [[ "$(grep -c -E 'SILENT_STAKE|_silent_stake|STAKED IDENTITY SILENT|\[silent-stake\]' "$STANDBY")" == "0" ]]; then
    ok "(g4) the standby carries none of it (it is a holder after a take: its own rungs and the 'STANDBY UNREACHABLE WHILE STAKED' page)"
else
    bad "(g4) the standby daemon mentions the silent-stake machinery"
fi
banner_line=$(grep -F 'echo "  Silent-stake page:' "$PRIMARY" | head -1)
b_on=$( VOTE_PUBKEY="V1"; SILENT_STAKE_PAGE_SECS=90; eval "$banner_line" ); b_off=$( VOTE_PUBKEY=""; SILENT_STAKE_PAGE_SECS=90; eval "$banner_line" ); b_45=$( VOTE_PUBKEY="V1"; SILENT_STAKE_PAGE_SECS=45; eval "$banner_line" )
if [[ "$b_on" == "  Silent-stake page: 90s" && "$b_off" == "  Silent-stake page: off (VOTE_PUBKEY not set)" && "$b_45" == "  Silent-stake page: 45s" ]]; then
    ok "(g5) the start banner prints '  Silent-stake page: 90s' (the knob's value) and, without VOTE_PUBKEY, '  Silent-stake page: off (VOTE_PUBKEY not set)'"
else
    bad "(g5) banner: on=[$b_on] off=[$b_off] 45=[$b_45]"
fi
p_post_read_stamp() { local c l_read l_stamp; c=$(fn_code "$1" _silent_stake_cycle); l_read=$(printf '%s\n' "$c" | grep -n -F '_smp=$(get_staked_liveness_sample)' | head -1 | cut -d: -f1); l_stamp=$(printf '%s\n' "$c" | grep -n -E '^[[:space:]]*_now=\$\(mono_now\)' | sed -n 2p | cut -d: -f1); [[ -n "$l_read" && -n "$l_stamp" && $l_stamp -gt $l_read ]]; }
if p_post_read_stamp "$PRIMARY"; then
    ok "(g6) the clock is read again AFTER the vote-account read (a second _now=\$(mono_now) follows the get_staked_liveness_sample call): the span starts when the answer arrived, not before the read that took its time"
else
    bad "(g6) no second clock read after the vote-account read in _silent_stake_cycle"
fi
p_banner() { local bl o1 o2; bl=$(grep -F 'echo "  Silent-stake page:' "$1" | head -1); o1=$( VOTE_PUBKEY="V1"; SILENT_STAKE_PAGE_SECS=90; eval "$bl" ); o2=$( VOTE_PUBKEY=""; SILENT_STAKE_PAGE_SECS=90; eval "$bl" ); [[ "$o1" == "  Silent-stake page: 90s" && "$o2" == "  Silent-stake page: off (VOTE_PUBKEY not set)" ]]; }

# ── (h) without VOTE_PUBKEY ──────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (h) no VOTE_PUBKEY: the page is off (no read, no page) ───"
ev_h=$(ss_world "$PRIMARY" "U:22" VOTE_PUBKEY=)
if [[ "$(n_of "$ev_h" 'SAMPLE')" == "0" && "$(page_ats "$ev_h")" == "" && "$(n_of "$ev_h" 'CYCLE 21')" == "1" ]]; then
    ok "(h) with VOTE_PUBKEY empty the 22 unstaked cycles make no read of the vote account and no page"
else
    bad "(h) samples=$(n_of "$ev_h" 'SAMPLE') pages=[$(page_ats "$ev_h")]"
fi
p_off_without_vote() { [[ "$(n_of "$1" 'SAMPLE')" == "0" && "$(page_ats "$1")" == "" ]]; }

# ── (i) blindness ────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (i) blind: no page, one WARN per ALERT_THROTTLE, the next read waits 30 s; an open episode survives blindness ───"
ev_i=$(ss_world "$PRIMARY" "U:130" "SCHED='0|down|adv|T2'")
exp_s="0"; k=30; while [[ $k -le 630 ]]; do exp_s="$exp_s $k"; k=$((k + 30)); done
if [[ "$(page_ats "$ev_i")" == "" && "$(sample_ats "$ev_i")" == "$exp_s" && "$(n_of "$ev_i" 'LOGW [silent-stake] the staked vote account')" == "2" ]]; then
    ok "(i1) no provider answers for 645 s: no page; the reader is called every 30 s (offsets 0, 30, ... 630: 22 reads, not one per 10 s); the WARN '[silent-stake] the staked vote account ... could not be read' comes at 0 and again at 600 (ALERT_THROTTLE), twice in all"
else
    bad "(i1) blind: pages=[$(page_ats "$ev_i")] reads=[$(sample_ats "$ev_i" | cut -c1-80)...] warns=$(n_of "$ev_i" 'LOGW [silent-stake] the staked vote account')"
fi
p_blind_backoff() { [[ "$(sample_ats "$1")" == "$exp_s" ]]; }
ev_i2=$(ss_world "$PRIMARY" "U:60" "SCHED='0|5000|adv|T2 50|down|adv|T2 200|5000|adv|T2'")
if [[ "$(page_ats "$ev_i2")" == "200" && "$(txt_first "$ev_i2")" == *"frozen for 190s"* ]]; then
    ok "(i2) frozen from 10, blind from 50 to 199, readable again at 200 with the same lastVote and a tip that moved: the episode was kept, the page comes at the first readable read ('frozen for 190s') and not before"
else
    bad "(i2) blind inside an episode: pages=[$(page_ats "$ev_i2")] (want 200) text=[$(txt_first "$ev_i2" | cut -c1-110)]"
fi

# ── (j) (k) (l) not evidence ──────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (j) a view that does not advance, (k) a lastVote that goes backwards, (l) a change of provider ───"
ev_j=$(ss_world "$PRIMARY" "U:30" "SCHED='0|5000|const|T2'")
if [[ "$(page_ats "$ev_j")" == "" && "$(n_of "$ev_j" 'did not move while the cluster tip did')" == "0" ]]; then
    ok "(j) a cached view (the cluster tip stays 9000 across 150 s): no span starts, no page - the lastVote is frozen only in a view that is itself frozen"
else
    bad "(j) stale tip: pages=[$(page_ats "$ev_j")] span-starts=$(n_of "$ev_j" 'did not move while the cluster tip did')"
fi
p_stale_view() { [[ "$(page_ats "$1")" == "" && "$(n_of "$1" 'did not move while the cluster tip did')" == "0" ]]; }
SCHED_J2="0|5000|adv|T2 25|5000|fix9050|T2"
ev_j2=$(ss_world "$PRIMARY" "U:30" "SCHED='$SCHED_J2'")
if [[ "$(page_ats "$ev_j2")" == "" && "$(n_of "$ev_j2" 'did not move while the cluster tip did')" == "1" ]]; then
    ok "(j2) a view that freezes AFTER the span started (the tip 9000, 9020, 9040, 9050 at the reads 0, 10, 20, 30 and 9050 from then on, the lastVote 5000 throughout): the span starts at 10 and the reads at 10, 20 and 30 are fresh, the read at 40 and every later one repeats the tip of the one before: no verdict, no page (a baseline kept at the first read's 9000 would page at 100)"
else
    bad "(j2) a view that froze later: pages=[$(page_ats "$ev_j2")] (want none) span-starts=$(n_of "$ev_j2" 'did not move while the cluster tip did') (want 1)"
fi
p_view_froze_later() { [[ "$(page_ats "$1")" == "" && "$(n_of "$1" 'did not move while the cluster tip did')" == "1" ]]; }
ev_k=$(ss_world "$PRIMARY" "U:30" "SCHED='0|5000|adv|T2 5|4000|adv|T2'")
if [[ "$(page_ats "$ev_k")" == "" && "$(n_of "$ev_k" 'did not move while the cluster tip did')" == "0" ]]; then
    ok "(k) lastVote 5000, then 4000 at every later read (the tip advancing): an inconsistent view - no span starts, no page"
else
    bad "(k) backwards: pages=[$(page_ats "$ev_k")] span-starts=$(n_of "$ev_k" 'did not move while the cluster tip did')"
fi
ev_l=$(ss_world "$PRIMARY" "U:40" "SCHED='0|5000|adv|T2 55|5000|adv|T3'")
if [[ "$(page_ats "$ev_l")" == "160" && "$(n_of "$ev_l" 'the answering provider changed (T2 to T3)')" == "1" ]]; then
    ok "(l) frozen on T2 from 10; the provider is T3 from the read at 60: ONE line '(T2 to T3)', the baseline moves and the span restarts (first frozen T3 pair at 70) - the page comes at 160, not at 100"
else
    bad "(l) provider change: pages=[$(page_ats "$ev_l")] (want 160) change-lines=$(n_of "$ev_l" 'the answering provider changed (T2 to T3)')"
fi
p_flip_restarts() { [[ "$(page_ats "$1")" == "160" ]]; }
ev_l2=$(ss_world "$PRIMARY" "U:30" "SCHED='0|5000|adv|T2 105|grow|adv|T3'")
if [[ "$(page_ats "$ev_l2")" == "100" && "$(n_of "$ev_l2" 'staked identity votes again (lastVote 5240) after 110s')" == "1" && "$(n_of "$ev_l2" 'votes again')" == "1" ]]; then
    ok "(l2) paged at 100; the provider changes to T3 at 110 (the span restarts, lastVote 5220 on the new baseline); the votes are seen rising at 120 (5240): ONE line 'votes again (lastVote 5240) after 110s' - counted from the first frozen pair of the EPISODE (10), the change of provider having restarted the span"
else
    bad "(l2) flip then resume: pages=[$(page_ats "$ev_l2")] resume-lines=$(n_of "$ev_l2" 'votes again') (want 1, 'after 110s')"
fi
p_resume_after_flip() { [[ "$(n_of "$1" 'staked identity votes again (lastVote 5240) after 110s')" == "1" ]]; }
SCHED_L3="0|5000|adv|T2 105|5000|adv|T3 135|grow|adv|T3"
ev_l3=$(ss_world "$PRIMARY" "U:30" "SCHED='$SCHED_L3'")
if [[ "$(page_ats "$ev_l3")" == "100" && "$(n_of "$ev_l3" 'staked identity votes again (lastVote 5280) after 130s')" == "1" && "$(n_of "$ev_l3" 'votes again')" == "1" && "$(n_of "$ev_l3" 'did not move while the cluster tip did')" == "2" ]]; then
    ok "(l3) paged at 100; the provider changes to T3 at 110 with the same lastVote, a SECOND span starts at the first frozen T3 pair (120: two 'did not move' lines in all); the votes rise at 140 (5280): ONE line 'votes again (lastVote 5280) after 130s' - from the episode's first frozen pair (10), not from the second span (120: 20 s) and not from the page"
else
    bad "(l3) two spans in one episode: pages=[$(page_ats "$ev_l3")] resume=$(n_of "$ev_l3" 'votes again') (want 1, 'after 130s') starts=$(n_of "$ev_l3" 'did not move while the cluster tip did') (want 2)"
fi
p_resume_after_two_spans() { [[ "$(n_of "$1" 'staked identity votes again (lastVote 5280) after 130s')" == "1" && "$(n_of "$1" 'did not move while the cluster tip did')" == "2" ]]; }
p_back_none() { [[ "$(page_ats "$1")" == "" && "$(n_of "$1" 'did not move while the cluster tip did')" == "0" ]]; }

# ── (m) a manual identity change is a new episode ───────────────────────────────────────────────────────────────────────
echo ""; echo "─── (m) a manual identity change starts a new episode; the grace is not counted ───"
ev_m=$(ss_world "$PRIMARY" "U:10 K U:30")
if [[ "$(page_ats "$ev_m")" == "215" && "$(n_of "$ev_m" 'GRACE 30')" == "2" ]]; then
    ok "(m) frozen from 10; the identity becomes a stranger's at 50 and the node's own unstaked key again at 85 (two manual changes, two 30 s graces: the clock reads 115 after them): the state is cleared at each, the baseline is the read after the grace (115), the first frozen pair 125 - the page at 215, not at 115"
else
    bad "(m) manual change: pages=[$(page_ats "$ev_m")] (want 215) graces=$(n_of "$ev_m" 'GRACE 30') (want 2)"
fi
p_manual_new_episode() { [[ "$(page_ats "$1")" == "215" ]]; }

# ── (n) DRY_RUN ───────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (n) DRY_RUN pages the same as live: there is no action to simulate ───"
ev_n1=$(ss_world "$PRIMARY" "U:22" DRY_RUN=true); ev_n0=$(ss_world "$PRIMARY" "U:22" DRY_RUN=false)
if [[ "$(page_ats "$ev_n1")" == "100" && "$(txt_first "$ev_n1")" == "$(txt_first "$ev_n0")" && "$(page_ats "$ev_n0")" == "100" && "$(n_of "$ev_n1" 'DEMOTE')" == "0" && "$(n_of "$ev_n1" 'SWITCH-TO-STAKED')" == "0" ]]; then
    ok "(n) DRY_RUN=true: the same page at the same offset with the same text as DRY_RUN=false, and nothing was demoted or taken in either"
else
    bad "(n) dry: pages=[$(page_ats "$ev_n1")] live=[$(page_ats "$ev_n0")] text-equal=$([[ "$(txt_first "$ev_n1")" == "$(txt_first "$ev_n0")" ]] && echo yes || echo no)"
fi

# ── (o) the take path's state ───────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (o) a whole episode leaves the recovery ladder's and the take path's state alone ───"
ev_o=$(ss_world "$PRIMARY" "U:22")
if [[ "$(state_of "$ev_o")" == "111 222 333 T9 444 555 6 7 8" && "$(page_ats "$ev_o")" == "100" ]]; then
    ok "(o) after a run with a page: _liveness_first_* (111 222 333 T9), _last_blind_end 444, _liveness_obs_since 555 and _ep_* (6 7 8) are as they were set"
else
    bad "(o) state after the run: [$(state_of "$ev_o")] (want '111 222 333 T9 444 555 6 7 8')"
fi
p_state_untouched() { [[ "$(state_of "$1")" == "111 222 333 T9 444 555 6 7 8" ]]; }
p_never_acts() { [[ "$(n_of "$1" 'SWITCH-TO-STAKED')" == "0" && "$(n_of "$1" 'DEMOTE')" == "0" ]]; }
p_cadence_11() { [[ "$(n_of "$1" ' SAMPLE')" == "11" ]]; }
ev_cad=$(ss_world "$PRIMARY" "U:22")
if [[ "$(n_of "$ev_cad" ' SAMPLE')" == "11" && "$(sample_ats "$ev_cad")" == "0 10 20 30 40 50 60 70 80 90 100" ]]; then
    ok "(o2) the reader is called once per VOTE_LIVENESS_MIN_INTERVAL: 11 reads in 22 cycles of 5 s (offsets 0, 10, ... 100), not one per cycle"
else
    bad "(o2) cadence: reads at [$(sample_ats "$ev_cad")]"
fi

# ── (p) controls ──────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (p) CONTROLS (mutate()): each mutant must turn its case red ───"
ctl_ok=1; ctl_rows=""
ctl() {   # ctl <label> <sed expr> <plan> <predicate> [VAR=val ...] - the predicate holds on the shipped script and FAILS on the mutant
    local label="$1" expr="$2" plan="$3" pred="$4" m="$WORK/mut-$1.sh" real mut rv mv; shift 4
    if ! mutate "$PRIMARY" "$expr" "$m"; then ctl_ok=0; ctl_rows="$ctl_rows $label:NOT-APPLIED"; return; fi
    real=$(ss_world "$PRIMARY" "$plan" "$@"); mut=$(ss_world "$m" "$plan" "$@")
    "$pred" "$real" && rv=y || rv=n; "$pred" "$mut" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then ctl_rows="$ctl_rows $label:red"; else ctl_ok=0; ctl_rows="$ctl_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
ctl_rc() {   # ctl_rc <label> <sed expr> <predicate over a script> - the predicate holds on the shipped script and FAILS on the mutant
    local label="$1" expr="$2" pred="$3" m="$WORK/mut-$1.sh" rv mv
    if ! mutate "$PRIMARY" "$expr" "$m"; then ctl_ok=0; ctl_rows="$ctl_rows $label:NOT-APPLIED"; return; fi
    "$pred" "$PRIMARY" && rv=y || rv=n; "$pred" "$m" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then ctl_rows="$ctl_rows $label:red"; else ctl_ok=0; ctl_rows="$ctl_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
SS='/^_silent_stake_cycle() {/,/^}/'
ctl gt-not-ge "$SS"' s/if \[\[ \$_span -ge \${SILENT_STAKE_PAGE_SECS:-90} \]\]; then/if [[ $_span -gt ${SILENT_STAKE_PAGE_SECS:-90} ]]; then/' "U:22" p_page_100
ctl no-throttle "$SS"' s/^        if \[\[ \${_ss_page_ts:-0} -eq 0 || \$(( _now - _ss_page_ts )) -ge \${ALERT_THROTTLE:-600} \]\]; then$/        if true; then/' "U:50" p_throttle_120 ALERT_THROTTLE=120
ctl resume-keeps-page-state "$SS"' s/_ss_since=0; _ss_page_ts=0; _ss_first=0$/_ss_since=0; _ss_first=0/' "U:60" p_resume_pages "SCHED='$SCHED_C'"
ctl resume-keeps-span "$SS"' s/_ss_lv=\$_lv; _ss_tip=\$_tip; _ss_since=0; _ss_page_ts=0; _ss_first=0$/_ss_lv=$_lv; _ss_tip=$_tip; _ss_page_ts=0; _ss_first=0/' "U:60" p_resume_pages "SCHED='$SCHED_C'"
ctl gated-on-manual-mode 's/^        _silent_stake_cycle   # v0.7 (rc2 F21): monitor-only/        [[ "$RECOVERY_MODE" == "manual" ]] \&\& _silent_stake_cycle   # v0.7 (rc2 F21): monitor-only/' "U:22" p_rpc_pages RECOVERY_MODE=rpc
ctl no-staked-clear '/^        _silent_stake_reset   # v0.7 (rc2 F21): this node votes the stake/d' "U:9 Sa Ua U:20" p_staked_clears
ctl no-manual-clear '/^            _silent_stake_reset   # v0.7 (rc2 F21): a manual change/d' "U:10 K U:30" p_manual_new_episode
ctl no-vote-pubkey-guard "$SS"' { /^    \[\[ -n "\${VOTE_PUBKEY:-}" \]\] || return 0$/d; }' "U:22" p_off_without_vote VOTE_PUBKEY=
ctl read-every-cycle "$SS"' { /^    \[\[ \$_now -ge \${_ss_next_ts:-0} \]\] || return 0$/d; }' "U:22" p_cadence_11
ctl no-blind-backoff "$SS"' s/_ss_next_ts=\$(( _now + (_gap > 30 ? _gap : 30) ))/_ss_next_ts=$(( _now + _gap ))/' "U:130" p_blind_backoff "SCHED='0|down|adv|T2'"
ctl no-tip-guard "$SS"' { /^    \[\[ \$_tip -gt \$_ss_tip \]\] || return 0 /d; }' "U:30" p_stale_view "SCHED='0|5000|const|T2'"
ctl no-backwards-guard "$SS"' { /^    \[\[ \$_lv -ge \$_ss_lv \]\] || return 0 /d; }' "U:30" p_back_none "SCHED='0|5000|adv|T2 5|4000|adv|T2'"
ctl no-provider-pin "$SS"' s/^    if \[\[ "\$_tier" != "\$_ss_tier" \]\]; then$/    if false; then/' "U:40" p_flip_restarts "SCHED='0|5000|adv|T2 55|5000|adv|T3'"
ctl resume-line-needs-span "$SS"' s/^        if \[\[ \${_ss_first:-0} -gt 0 \]\]; then   # the silence counts.*$/        if [[ $_ss_since -gt 0 ]]; then/' "U:30" p_resume_after_flip "SCHED='0|5000|adv|T2 105|grow|adv|T3'"
ctl resume-counts-from-the-restart "$SS"' s/after \$(( _now - _ss_first ))s"/after $(( _now - _ss_since ))s"/' "U:30" p_resume_after_two_spans "SCHED='$SCHED_L3'"
ctl first-restarts-with-the-span "$SS"' s/^        \[\[ \${_ss_first:-0} -gt 0 \]\] || _ss_first=\$_now$/        _ss_first=$_now/' "U:30" p_resume_after_two_spans "SCHED='$SCHED_L3'"
ctl tip-baseline-is-the-first-read "$SS"' { /^    _ss_tip=\$_tip  *# the next read must advance past THIS one/d; }' "U:30" p_view_froze_later "SCHED='$SCHED_J2'"
ctl reset-forgets-the-episode-start 's/_ss_blind_ts=0; _ss_first=0; }$/_ss_blind_ts=0; }/' "U:9 Sa Ua U:20" p_reset_clears_first "SCHED='$SCHED_E3'"
ctl touches-take-state "$SS"' s/^    _ss_next_ts=\$(( _now + _gap ))$/    _ss_next_ts=$(( _now + _gap )); _liveness_first_vote=$_lv/' "U:22" p_state_untouched
ctl acts-on-it "$SS"' s/^    _ss_next_ts=\$(( _now + _gap ))$/    _ss_next_ts=$(( _now + _gap )); switch_to_staked "x"/' "U:22" p_never_acts
[[ $ctl_ok -eq 1 ]] && ok "(p1) every mutant of the evidence and page rules turns its case red:$ctl_rows" || bad "(p1) a control did not turn its case red:$ctl_rows"
ctl_ok=1; ctl_rows=""
ctl_rc acts-on-it-text "$SS"' s/^    _ss_next_ts=\$(( _now + _gap ))$/    _ss_next_ts=$(( _now + _gap )); switch_to_staked "x"/' p_no_action
ctl_rc floor-gone '/SILENT_STAKE_PAGE_SECS 30 /d' p_floor_30
ctl_rc drift-gone-low '/_drift_check SILENT_STAKE_PAGE_SECS 90 high /d' p_drift_low
ctl_rc drift-gone-high '/_drift_check SILENT_STAKE_PAGE_SECS 90 low /d' p_drift_both
ctl_rc call-after-dispatch 's/^        _silent_stake_cycle   # v0.7 (rc2 F21): monitor-only.*$/        :/
/^        if \[\[ "\$RECOVERY_MODE" == "manual" \]\]; then$/a\
            _silent_stake_cycle' p_one_call_before_dispatch
ctl_rc no-post-read-stamp "$SS"' { /^    _now=\$(mono_now)   # the span starts when the answer ARRIVED/d; }' p_post_read_stamp
ctl_rc banner-claims-on-without-vote 's/\$(\[ -n "\$VOTE_PUBKEY" \] && echo "\${SILENT_STAKE_PAGE_SECS}s" || echo "off (VOTE_PUBKEY not set)")/${SILENT_STAKE_PAGE_SECS}s/' p_banner
[[ $ctl_ok -eq 1 ]] && ok "(p2) the structure controls (an action in the monitor-only code, the floor, either drift line, the call moved behind the dispatch as a line of its own, a banner that says 'on' without VOTE_PUBKEY, an answer stamped before the read) turn their cases red:$ctl_rows" || bad "(p2) a structure control did not turn its case red:$ctl_rows"

results_banner
