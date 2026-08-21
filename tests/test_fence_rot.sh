#!/bin/bash
# v0.7 (Block 5.4): FENCE-ROT DETECTION + FENCE_ROT_GRACE ESCALATION (§2.1-rev2.1 №2).
# The pairing token attests the holder's fence AT PAIRING TIME only — the spare cannot see
# post-pairing rot; the load is holder-side: the ARMED holder re-verifies its own EFFECTIVE
# fence properties each FENCE_ROT_CHECK_SECS and treats armed+staked+fence-broken as
# fence-worthy — behind an ESCALATION WINDOW (immediate CRITICAL page naming the exact broken
# element + exact fix; graceful self-demote only after FENCE_ROT_GRACE of PERSISTENT verified
# rot, and only while verifiably STAKED). Every demote-vs-page classification this suite
# asserts is container-verified on systemd 249 AND 255 — design record
# verify-rot-properties.md (private tree).
#
# Drives the REAL daemons' [fence-rot] twin block (source-to-MAIN-LOOP seam) with in-shell
# systemctl/timeout shims (every systemctl answer is a fixture file; every call event-logged —
# the provisioning-accident rules: no real systemctl ever runs).
#
# Cases:
#   (1)  structural inertness: un-armed sweep → ZERO systemctl events, zero pages, no clock
#        (event-log assert); armed cadence: repeats gated by FENCE_ROT_CHECK_SECS, FIRST sweep
#        immediate (0-sentinel)
#   (2)  per-property demote-class: masked / unit-file-gone / real→page-only / Restart=always /
#        OnFailure-missing / bad-setting → CRITICAL page naming the EXACT element + EXACT fix
#        command, demote clock armed (the firing signal's OWN anchor > 0)
#   (3)  page-class (NO demote clock): WatchdogSec config drift (systemctl cat vs env) /
#        StartLimitIntervalUSec≠0 / both-units XOR / monitor unit not loadable (the STUB-VALUE
#        trap: not-found answers Restart=no + OnFailure= — must NOT read as demote-class, and
#        must NOT read as S3/S4 positive-clean either)
#   (4)  first page IMMEDIATE on fresh boot — all three page families' 0-sentinel guards
#        (rot 4a/4b; page-class 4c/4d; cannot-verify 4e/4f — the TV-3 unkilled-mutant fix):
#        positives at T0=100, controls mutate each guard → the first page throttle-swallowed
#   (5)  throttle: persistent rot pages at first + per ALERT_THROTTLE, not a storm (control:
#        throttle line deleted → storm observed)
#   (6)  episodic reset MEASURED: rot → heal (resolution + fresh window) → re-rot → demote only
#        after a FULL new grace (control: the S2 positive-clean reset neutered → stale-anchor
#        EARLY demote, measured offsets printed)
#   (7)  expiry: staked → the EXISTING demote path invoked (REAL switch_to_unstaked /
#        give_back_identity; stub records set-identity; reason names spare-takeover);
#        unstaked → NO demote + one info; identity unreadable → NO demote + paging continues,
#        demote lands on the next READABLE sweep (a no-attempt sweep never arms the retry
#        throttle)
#   (8)  never-instant control: grace check neutered → instant demote observed (red); restored
#        → demote ONLY after FENCE_ROT_GRACE
#   (9)  cannot-verify: systemctl wedged → NOT rot (no page, no clock); page only after streak
#        4 (throttled, first-immediate at threshold); a SUCCEEDED read in the same sweep still
#        classifies; cv sweeps neither heal nor extend an open window
#   (10) DRY_RUN bait at the mutation site (defense-in-depth layer 2; layer 1 = the №1 startup
#        refusal, asserted structurally): forced expiry+staked under DRY_RUN=true → ZERO
#        admin-socket mutations AND the [DRY RUN] branch OBSERVED (title captured + asserted —
#        av==0 alone cannot distinguish guard-held from chain-never-reached; TV-5 fix)
#   (11) twin extraction: [fence-rot] BYTE-IDENTICAL across both daemons; the D3 no-double-sign
#        reasoning lives AT the grace check (comment assert)
#   (12) per-op pets: every bounded read petted — BOTH censuses: live event order across
#        healthy + rot + EXPIRY sweeps (the expiry identity-read path order-checked live —
#        TV-2 fix) AND source call sites with the widened stray set ($(timeout…systemctl
#        beside the funnel + command-position forms); P1 floors still pass on grown daemons
#   (13) N-is-all ALLOWLIST census (TV-1 fix — the old spelling-grep failed OPEN for
#        `if systemctl …`): every systemctl-bearing line is a string mention by mechanism or
#        one of exactly 4 enumerated sites (in-block funnel, 2 hard-stop actuators, the
#        REPORTED unbounded ExecStart fallback)
#   (14) inertness control: _watchdog_active forced open → un-armed sweep leaks systemctl
#        events — (1)'s zero-count genuinely observes the gate
#   (15) knob validation: FENCE_ROT_GRACE floor max(600, ALERT_THROTTLE) with both reasons in
#        the error text; FENCE_ROT_CHECK_SECS floor 10; drift announcer (raised = laxer, both
#        knobs; defaults silent)
#   (16) intent-capture wired in startup (call-site grep, both daemons)
#   (17) PER-SIGNAL anchors (the ROT-DEMOTE-1 BLOCKER fix, panel timelines measured): a heal
#        positively seen on a signal's own read closes ITS window under blind siblings (17a
#        both daemons, deterministic dropped-key trigger; red was demotes=[3000], fixed
#        demotes=[4800] + ONE resolution); within-group S1-clean/S2-blind split (17b — why
#        per-SIGNAL, not per-read-group); preserved 9d continuous-rot semantics (17c);
#        M-signal never-positively-clean holds its anchor (17d); stale-anchor control (17e —
#        the panel numbers return); expiry demote-attempt throttle first-immediate then
#        per-ALERT_THROTTLE with suppression warns (17f, control 17g), keypair-blocked
#        adapter pages on BOTH daemons at attempt cadence (17h standby — the previously
#        SILENT branch, 17i primary)
#   (18) classifier-arm captures via the precap hook (ROT-INT-1): intent=none → demote-class,
#        FULL grace, no runtime heal, page carries the drop-in-won't-clear clause
#        (ROT-DEMOTE-2); page-only + real-appears → №1-at-runtime page-class, no clock;
#        page-only + gone → page-class, no clock
#
# MUTATION COVERAGE (HARNESS.md discipline): killed here — the grace check (8-ctrl), the S2
# positive-clean reset (6-ctrl + 17e: the stale-anchor/panel-numbers control), the rot re-page
# throttle (5-ctrl), the rot first-immediate guard (4b), the page-class first-immediate guard
# (4d), the cv first-immediate guard (4f), the demote-retry throttle guard (17g), the
# _watchdog_active gate (14-ctrl). All via mutate() (loud on no-op). NAMED SURVIVORS: the
# per-element fix-command STRINGS are asserted by content, not mutation; the cv-streak
# threshold constant (4) is asserted by offset, its mutant (3 or 5) would shift (9a)/(4e)'s
# page offset — count-visible, not separately mutated; the S1/S3/S4 clean-resets follow the
# S2 mutation's killed pattern through the SAME four-line uniform rule and are exercised
# behaviorally by (17b)/(17d)/(18) — S2's is the one the episodic heal path runs through.
#
# PRE-IMPL VACUITY CENSUS (TV-4 fix; measured, not remembered — re-run the suite against the
# parent-commit daemons to re-derive): at the Block 5.4 land, 7 cases passed against the
# pre-5.4 daemons — (10a), (10b), (12c), (13) BOTH rows, (15c), (15g) — not the 6 the first
# record claimed (13-PRIMARY was red only in the first miscalibrated red run, see the (13)
# war story). After THIS panel-fix round the set shrinks to 4 — (10b), (12c), (15c), (15g):
# (10a) now requires the [DRY RUN] title the parent never emits, and (13) now requires the
# in-block funnel the parent does not have. Pairings: 10a↔7b (same drive, DRY_RUN flipped,
# av>=1), 10b↔test_one_arm_state (behavioral refusal drives), 12c↔12a/12b, 15c↔15a/b/d,
# 15g↔15e/f.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
BASH_BIN="${BASH:-/bin/bash}"

title_banner "Fence rot detection + FENCE_ROT_GRACE escalation (v0.7 Block 5.4)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/rot54.XXXXXX")
T0=100000            # mono origin (never 0 — 0 collides with the 0-sentinels under test)

new_mock() {
    MOCK_DIR=$(mktemp -d "$WORK/m.XXXXXX")
    EV="$MOCK_DIR/events"; : > "$EV"
    mkdir -p "$MOCK_DIR/units"
    export MOCK_DIR EV
    # healthy armed-real defaults (each case drifts what it needs)
    : > "$MOCK_DIR/units/solana-failover-fence.service"
    printf 'loaded\n' > "$MOCK_DIR/show.fence"
    printf 'LoadState=loaded\nRestart=no\nOnFailure=solana-failover-fence.service solana-failover-fence-page-only.service\nStartLimitIntervalUSec=0\n' > "$MOCK_DIR/show.mon"
    printf '# /etc/systemd/system/solana-failover-monitor.service\n[Service]\nWatchdogSec=30\n' > "$MOCK_DIR/cat.mon"
    printf 'S1\n' > "$MOCK_DIR/identity"
}
ev_grep()  { grep -c "$1" "$EV" 2>/dev/null | tr -d '[:space:]'; }

# ── in-shell shims (registered for re-application after every load_seam) ────────────────────────
# timeout: `-k K DUR cmd…` and `DUR cmd…`; socat pipelines pass through to the sd: logger;
# systemctl calls can be wedged (rc 124, op never runs) — globally or for the monitor-show read
# only (wedge.mon — the (9c) split-sweep case).
rot_shims() {
    timeout() {
        case "$*" in
            *socat*) if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@" ;;
            *systemctl*)
                if [ -f "$MOCK_DIR/wedge.all" ]; then echo "sc:WEDGED $*" >> "$EV"; return 124; fi
                if [ -f "$MOCK_DIR/wedge.mon" ]; then
                    case "$*" in *LoadState,Restart*) echo "sc:WEDGED $*" >> "$EV"; return 124 ;; esac
                fi
                if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@" ;;
            *) if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@" ;;
        esac
    }
    systemctl() {
        echo "sc:$*" >> "$EV"
        local _rc
        case "$*" in
            show*-p\ LoadState\ --value*)
                cat "$MOCK_DIR/show.fence" 2>/dev/null
                _rc=$(cat "$MOCK_DIR/rc.fence" 2>/dev/null); return "${_rc:-0}" ;;
            show*LoadState,Restart*)
                cat "$MOCK_DIR/show.mon" 2>/dev/null
                _rc=$(cat "$MOCK_DIR/rc.mon" 2>/dev/null); return "${_rc:-0}" ;;
            cat*)
                cat "$MOCK_DIR/cat.mon" 2>/dev/null
                _rc=$(cat "$MOCK_DIR/rc.cat" 2>/dev/null); return "${_rc:-0}" ;;
        esac
        return 0
    }
    socat() { local _p; _p=$(cat); _p="${_p//$'\n'/|}"; printf 'sd:%s\n' "$_p" >> "$EV"; return 0; }
    _harness_register rot_shims
}
harness_clock_shims
harness_silence_sinks
rot_shims

# ── the sim driver: run the REAL _fence_rot_check over a timeline ───────────────────────────────
#   $1=daemon $2=horizon(s) $3=scenario fn (called per step with the offset; mutates fixtures)
#   $4=armed(0/1) $5=identity mode (file|seq) $6=real demote (0=stub records op:demote, 1=REAL
#      wrapper + REAL switch path with admin ops event-logged) $7=DRY_RUN ("" = false)
# Steps are 20 s (cadence 60 gates the sweeps themselves). Echoes a k=v| summary.
drive_rot() {
    local script="$1" horizon="$2" scen="$3" armed="$4" idmode="$5" realdemote="$6" dry="$7"
    (
        set +e
        _SIM_NOW=$T0
        load_seam "$script"
        FENCE_UNIT_REAL="$MOCK_DIR/units/solana-failover-fence.service"
        FENCE_UNIT_PAGE_ONLY="$MOCK_DIR/units/solana-failover-fence-page-only.service"
        STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1
        ALERT_THROTTLE=600; FENCE_ROT_CHECK_SECS=60; FENCE_ROT_GRACE=1800
        DRY_RUN="${dry:-false}"
        if [[ "$armed" == "1" ]]; then NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        # alert captures: offsets recorded relative to T0. The [DRY RUN] and BLOCKED arms are
        # the ROT-INT-3/TV-5 fix: (10a)'s header claims the adapter's DRY-RUN branch is
        # OBSERVED, so the title must be captured and asserted, not discarded by the catch-all;
        # the BLOCKED arm carries the adapter-blocked pages of the (17) retry-throttle cases.
        ROTP=""; DRIFTP=""; CVP=""; INFOS=0; RESOLVES=0; NOTED=0; DEMOTES=""; DEMOTE_TEXT=""
        DRYP=""; KPBP=""; RETRYW=0
        alert() {
            case "$3" in
                *"FENCE ROT"*)   ROTP="$ROTP $(( _SIM_NOW - T0 ))"; ROT_LAST_MSG="$1" ;;
                *"FENCE CONFIG DRIFT"*) DRIFTP="$DRIFTP $(( _SIM_NOW - T0 ))"; DRIFT_LAST_MSG="$1" ;;
                *"DRY RUN"*)     DRYP="$DRYP $(( _SIM_NOW - T0 ))" ;;
                *"BLOCKED — keypair problem"*) KPBP="$KPBP $(( _SIM_NOW - T0 ))" ;;
                *) : ;;
            esac
        }
        alert_warn() { case "$*" in *"FENCE-ROT SWEEP BLIND"*) CVP="$CVP $(( _SIM_NOW - T0 ))" ;; esac; }
        alert_info() {
            INFOS=$((INFOS+1))
            case "$*" in
                *"fence rot resolved"*|*"rot resolved"*) RESOLVES=$((RESOLVES+1)) ;;
                *"already unstaked"*|*"nothing to protect"*) NOTED=$((NOTED+1)) ;;
            esac
        }
        log_warn() { case "$*" in *"demote retry throttled"*) RETRYW=$((RETRYW+1)) ;; esac; }
        get_local_identity() { head -1 "$MOCK_DIR/identity" 2>/dev/null; }
        if [[ "$realdemote" == "0" ]]; then
            # the stub demote FLIPS the identity fixture like the real path does — without it
            # a still-staked next sweep would (correctly) retry the demote and the offsets blur
            _rot_graceful_demote() { DEMOTES="$DEMOTES $(( _SIM_NOW - T0 ))"; DEMOTE_TEXT="$1"; echo "op:demote" >> "$EV"; printf 'U1\n' > "$MOCK_DIR/identity"; return 0; }
        else
            # REAL wrapper + REAL demote path: the daemons wrap every admin op in `timeout`, so
            # the shim below intercepts them all and event-logs; set-identity flips the identity
            # fixture to U1, so the REAL post-switch verify re-read takes the success branch.
            SOLANA_PATH=/mock; LEDGER_PATH=/x; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15
            UNSTAKED_KEYPAIR="$MOCK_DIR/uk.json"; printf '[1]' > "$MOCK_DIR/uk.json"
            timeout() {
                case "$*" in
                    *socat*) if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@" ;;
                    *agave-validator*remove-all*) echo "av:remove-all" >> "$EV"; return 0 ;;
                    *agave-validator*set-identity*) echo "av:set-identity $*" >> "$EV"; printf 'U1\n' > "$MOCK_DIR/identity"; return 0 ;;
                    *agave-validator*) echo "av:other $*" >> "$EV"; return 0 ;;
                    *systemctl*)
                        if [ -f "$MOCK_DIR/wedge.all" ]; then echo "sc:WEDGED $*" >> "$EV"; return 124; fi
                        if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@" ;;
                    *) if [ "$1" = "-k" ]; then shift 3; else shift 1; fi; "$@" ;;
                esac
            }
            get_tower_path() { echo "$MOCK_DIR/tower"; }
            save_state() { :; }
            sleep() { :; }
            DEMOTES=""; DEMOTE_TEXT=""
        fi
        heartbeat_ping() { :; }
        save_state() { :; }
        "$scen" precap 2>/dev/null   # ROT-INT-1 pre-capture hook: shape unit files BEFORE the intent capture (the (18) classifier-arm cases; scens without a precap arm no-op)
        _rot_capture_intent   # the startup anchor (the real call site is startup_checks — case (16)); BEFORE the scenario drifts the fixtures
        "$scen" init 2>/dev/null
        local t=0
        while [[ $t -le $horizon ]]; do
            _SIM_NOW=$(( T0 + t ))
            "$scen" "$t"
            _fence_rot_check
            t=$(( t + 20 ))
        done
        # REAL-demote runs record via the alert titles of the switch path itself.
        # since = the OLDEST nonzero per-signal anchor (read from the daemon globals via the
        # daemon's own _rot_oldest — 0 when no window is open); a1..a4 are the raw anchors.
        printf 'rot=[%s]|drift=[%s]|cv=[%s]|demotes=[%s]|resolves=%s|noted=%s|since=%s|a1=%s|a2=%s|a3=%s|a4=%s|dry=[%s]|kpb=[%s]|retryw=%s|sc=%s|scwedge=%s|pets=%s|rotmsg=%s|driftmsg=%s|demotetext=%s\n' \
            "${ROTP# }" "${DRIFTP# }" "${CVP# }" "${DEMOTES# }" "$RESOLVES" "$NOTED" \
            "$(_rot_oldest "${_rot_s1_since:-0}" "${_rot_s2_since:-0}" "${_rot_s3_since:-0}" "${_rot_s4_since:-0}")" \
            "${_rot_s1_since:-unset}" "${_rot_s2_since:-unset}" "${_rot_s3_since:-unset}" "${_rot_s4_since:-unset}" \
            "${DRYP# }" "${KPBP# }" "$RETRYW" \
            "$(ev_grep '^sc:')" "$(ev_grep '^sc:WEDGED')" "$(ev_grep '^sd:WATCHDOG=1')" \
            "$(printf '%s' "${ROT_LAST_MSG:-}" | tr '|' '/' | head -c 600)" \
            "$(printf '%s' "${DRIFT_LAST_MSG:-}" | tr '|' '/' | head -c 600)" \
            "$(printf '%s' "${DEMOTE_TEXT:-}" | tr '|' '/' | head -c 600)"
    )
}

# scenario helpers (fixture mutators; each is a function name passed to drive_rot)
scen_healthy()      { :; }
scen_masked()       { [[ "$1" == "init" ]] && printf 'masked\n' > "$MOCK_DIR/show.fence"; :; }
scen_gone()         { [[ "$1" == "init" ]] && rm -f "$MOCK_DIR/units/solana-failover-fence.service"; :; }
scen_pageonly()     { if [[ "$1" == "init" ]]; then rm -f "$MOCK_DIR/units/solana-failover-fence.service"; : > "$MOCK_DIR/units/solana-failover-fence-page-only.service"; fi; }
scen_restart()      { [[ "$1" == "init" ]] && printf 'LoadState=loaded\nRestart=always\nOnFailure=solana-failover-fence.service solana-failover-fence-page-only.service\nStartLimitIntervalUSec=0\n' > "$MOCK_DIR/show.mon"; :; }
scen_onfail()       { [[ "$1" == "init" ]] && printf 'LoadState=loaded\nRestart=no\nOnFailure=\nStartLimitIntervalUSec=0\n' > "$MOCK_DIR/show.mon"; :; }
scen_badsetting()   { [[ "$1" == "init" ]] && printf 'bad-setting\n' > "$MOCK_DIR/show.fence"; :; }
scen_wdrift()       { [[ "$1" == "init" ]] && printf '# unit\n[Service]\nWatchdogSec=30\n# drop-in\nWatchdogSec=1h\n' > "$MOCK_DIR/cat.mon"; :; }
scen_sli()          { [[ "$1" == "init" ]] && printf 'LoadState=loaded\nRestart=no\nOnFailure=solana-failover-fence.service solana-failover-fence-page-only.service\nStartLimitIntervalUSec=10s\n' > "$MOCK_DIR/show.mon"; :; }
scen_xor()          { [[ "$1" == "init" ]] && : > "$MOCK_DIR/units/solana-failover-fence-page-only.service"; :; }
scen_monstub()      { [[ "$1" == "init" ]] && printf 'LoadState=not-found\nRestart=no\nOnFailure=\nStartLimitIntervalUSec=10s\n' > "$MOCK_DIR/show.mon"; :; }
scen_wedge()        { [[ "$1" == "init" ]] && : > "$MOCK_DIR/wedge.all"; :; }
scen_wedge_mon()    { if [[ "$1" == "init" ]]; then : > "$MOCK_DIR/wedge.mon"; printf 'masked\n' > "$MOCK_DIR/show.fence"; fi; }
# episodic: rot [0,120) → healthy [120,240) → rot [240,∞)
scen_episodic() {
    case "$1" in
        init) printf 'masked\n' > "$MOCK_DIR/show.fence" ;;
        120)  printf 'loaded\n' > "$MOCK_DIR/show.fence" ;;
        240)  printf 'masked\n' > "$MOCK_DIR/show.fence" ;;
    esac
}
# rot forever + identity unreadable until t=1900 (then staked)
scen_unreadable() {
    case "$1" in
        init) printf 'masked\n' > "$MOCK_DIR/show.fence"; : > "$MOCK_DIR/identity" ;;
        1900) printf 'S1\n' > "$MOCK_DIR/identity" ;;
    esac
}
# window persistence across cv: rot [0,120] → wedge-all [140,400] → rot visible again
scen_rot_cv_rot() {
    case "$1" in
        init) printf 'masked\n' > "$MOCK_DIR/show.fence" ;;
        140)  : > "$MOCK_DIR/wedge.all" ;;
        400)  rm -f "$MOCK_DIR/wedge.all" ;;
    esac
}
# ── (17) scenarios — the ROT-DEMOTE-1 panel timeline family ─────────────────────────────────────
# (17a/b) the panel's executed blocker, DETERMINISTIC trigger: rot@0 → fence GENUINELY heals@60
# while the monitor-show read drops a requested key (rc 0, StartLimitIntervalUSec absent — the
# block's own §1 cv guard) on EVERY later sweep → fresh masked@3000 with the fence read clear.
scen_stale_dropkey() {
    case "$1" in
        init) printf 'masked\n' > "$MOCK_DIR/show.fence" ;;
        60)   printf 'loaded\n' > "$MOCK_DIR/show.fence"
              printf 'LoadState=loaded\nRestart=no\nOnFailure=solana-failover-fence.service solana-failover-fence-page-only.service\n' > "$MOCK_DIR/show.mon" ;;
        3000) printf 'masked\n' > "$MOCK_DIR/show.fence" ;;
    esac
}
# (17c) the WITHIN-GROUP split (the per-signal-not-per-group rationale, in reverse): S1 file
# GONE@0 → file restored@60 (S1 positively clean) while the fence-LoadState read is BLIND
# (rc 1) → fresh S2 masked@3000 with reads clear. A shared file+LoadState group anchor would
# still be t0 → instant; S2's own anchor is fresh → full grace.
scen_group_split() {
    case "$1" in
        init) rm -f "$MOCK_DIR/units/solana-failover-fence.service" ;;
        60)   : > "$MOCK_DIR/units/solana-failover-fence.service"; printf '1\n' > "$MOCK_DIR/rc.fence" ;;
        3000) rm -f "$MOCK_DIR/rc.fence"; printf 'masked\n' > "$MOCK_DIR/show.fence" ;;
    esac
}
# (17d) preserved 9d semantics: CONTINUOUS S2 rot across blindness (no positive clean ever) —
# rot verified [0,120] → every read wedged [140,1900] → verified again → demote at the FIRST
# verified-rot sweep past grace.
scen_rot_blind_rot() {
    case "$1" in
        init) printf 'masked\n' > "$MOCK_DIR/show.fence" ;;
        140)  : > "$MOCK_DIR/wedge.all" ;;
        1900) rm -f "$MOCK_DIR/wedge.all" ;;
    esac
}
# (17e) M-signal never-positively-clean: S3 rot@0 (Restart=always, verified) → the monitor
# read wedged from t=20 (S3 blind, fence read stays healthy) → re-verified rot@5000.
scen_s3_blind_hold() {
    case "$1" in
        init) printf 'LoadState=loaded\nRestart=always\nOnFailure=solana-failover-fence.service solana-failover-fence-page-only.service\nStartLimitIntervalUSec=0\n' > "$MOCK_DIR/show.mon" ;;
        20)   : > "$MOCK_DIR/wedge.mon" ;;
        5000) rm -f "$MOCK_DIR/wedge.mon" ;;
    esac
}
# (17i/j) masked forever + the demote adapter keypair-blocked (uk.json removed at init)
scen_masked_nokp() {
    case "$1" in
        init) printf 'masked\n' > "$MOCK_DIR/show.fence"; rm -f "$MOCK_DIR/uk.json" ;;
    esac
}
# ── (18) scenarios — the classifier-arm captures (ROT-INT-1: precap runs BEFORE intent capture)
# (18a) intent=none: fence unit removed while the daemon was down; a HEALTHY real unit dropped
# in at t=60 WITHOUT re-arm (the ROT-DEMOTE-2 operator gesture — must NOT clear the escalation)
scen_none_dropin() {
    case "$1" in
        precap) rm -f "$MOCK_DIR/units/solana-failover-fence.service" ;;
        60)     : > "$MOCK_DIR/units/solana-failover-fence.service" ;;
    esac
}
# (18b) page-only intent; a REAL unit appears at runtime (the №1 deadly combination at RUNTIME)
scen_pageonly_real_appears() {
    case "$1" in
        precap) rm -f "$MOCK_DIR/units/solana-failover-fence.service"; : > "$MOCK_DIR/units/solana-failover-fence-page-only.service" ;;
        100)    : > "$MOCK_DIR/units/solana-failover-fence.service" ;;
    esac
}
# (18c) page-only intent; the page-only unit vanishes at runtime
scen_pageonly_gone() {
    case "$1" in
        precap) rm -f "$MOCK_DIR/units/solana-failover-fence.service"; : > "$MOCK_DIR/units/solana-failover-fence-page-only.service" ;;
        100)    rm -f "$MOCK_DIR/units/solana-failover-fence-page-only.service" ;;
    esac
}

# ── (1) inertness + cadence ─────────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) un-armed → zero systemctl events; armed → first sweep immediate, cadence gates repeats ───"
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    new_mock
    out=$(drive_rot "$script" 100 scen_masked 0 file 0 "")
    if [[ "$(field "$out" sc)" == "0" && "$(field "$out" rot)" == "[]" && "$(field "$out" since)" == "0" ]]; then
        ok "(1a) $name: UN-ARMED with a masked fence → ZERO systemctl events, zero pages, no demote clock ($out)"
    else
        bad "(1a) $name: inertness broken: $out"
    fi
done
new_mock
out=$(drive_rot "$STANDBY" 100 scen_healthy 1 file 0 "")
# 6 steps (0..100 by 20) but cadence 60 → sweeps at 0 and 60 only → 2 sweeps × 3 reads = 6 sc
if [[ "$(field "$out" sc)" == "6" ]]; then
    ok "(1b) armed healthy: 2 sweeps over 100 s at FENCE_ROT_CHECK_SECS=60 (first immediate, repeats gated) → 6 systemctl reads ($out)"
else
    bad "(1b) cadence wrong (want 6 sc events = 2 sweeps × 3 reads): $out"
fi

# ── (2) demote-class per property ───────────────────────────────────────────────────────────────
echo ""; echo "─── (2) demote-class: exact element + exact fix command, clock armed ───"
new_mock
out=$(drive_rot "$STANDBY" 20 scen_masked 1 file 0 "")
if [[ "$(field "$out" rot)" == "[0]" && "$(field "$out" since)" != "0" && "$(field "$out" since)" != "unset" ]]; then
    ok "(2a) masked fence → CRITICAL page at the first sweep, demote clock armed (since=$(field "$out" since))"
else
    bad "(2a) masked fence not classified demote-class: $out"
fi
msg=$(field "$out" rotmsg)
if [[ "$msg" == *"masked"* && "$msg" == *"systemctl unmask solana-failover-fence.service"* && "$msg" == *"failover arm"* ]]; then
    ok "(2a2) page names the element (masked, measured LoadState) + the exact fix (unmask + re-run 'failover arm')"
else
    bad "(2a2) masked-fence page text wrong: $msg"
fi
new_mock
out=$(drive_rot "$STANDBY" 20 scen_gone 1 file 0 "")
msg=$(field "$out" rotmsg)
if [[ "$(field "$out" rot)" == "[0]" && "$msg" == *"GONE"* && "$msg" == *"solana-failover-fence.service"* && "$msg" == *"failover arm"* ]]; then
    ok "(2b) real fence unit file GONE → demote-class, page names the unit + 'failover arm' fix"
else
    bad "(2b) gone-file case wrong: $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 20 scen_pageonly 1 file 0 "")
msg=$(field "$out" rotmsg)
if [[ "$(field "$out" rot)" == "[0]" && "$msg" == *"page-only"* ]]; then
    ok "(2c) real→page-only at runtime → demote-class (the REAL fence is gone), page says so"
else
    bad "(2c) real→page-only case wrong: $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 20 scen_restart 1 file 0 "")
msg=$(field "$out" rotmsg)
if [[ "$(field "$out" rot)" == "[0]" && "$msg" == *"Restart=always"* && "$msg" == *"drop-in"* && "$msg" == *"daemon-reload"* ]]; then
    ok "(2d) monitor Restart=always → demote-class (fence never dispatches on the 249 floor), page carries the measured value + drop-in/daemon-reload fix"
else
    bad "(2d) Restart drift case wrong: $out (msg=$msg)"
fi
new_mock
out=$(drive_rot "$STANDBY" 20 scen_onfail 1 file 0 "")
msg=$(field "$out" rotmsg)
if [[ "$(field "$out" rot)" == "[0]" && "$msg" == *"OnFailure"* && "$msg" == *"failover arm"* ]]; then
    ok "(2e) monitor OnFailure no longer names the fence → demote-class + 'failover arm' fix"
else
    bad "(2e) OnFailure case wrong: $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 20 scen_badsetting 1 file 0 "")
msg=$(field "$out" rotmsg)
if [[ "$(field "$out" rot)" == "[0]" && "$msg" == *"bad-setting"* ]]; then
    ok "(2f) fence LoadState=bad-setting → demote-class, measured value in the page"
else
    bad "(2f) bad-setting case wrong: $out"
fi
new_mock
out=$(drive_rot "$PRIMARY" 20 scen_masked 1 file 0 "")
[[ "$(field "$out" rot)" == "[0]" ]] \
    && ok "(2g) PRIMARY: same masked-fence detection through its own twin copy" \
    || bad "(2g) primary masked-fence case wrong: $out"

# ── (3) page-class: no demote clock ─────────────────────────────────────────────────────────────
echo ""; echo "─── (3) page-class drift: CRITICAL page, NO demote clock ───"
new_mock
out=$(drive_rot "$STANDBY" 20 scen_wdrift 1 file 0 "")
msg=$(field "$out" driftmsg)
if [[ "$(field "$out" drift)" == "[0]" && "$(field "$out" since)" == "0" && "$(field "$out" rot)" == "[]" && "$msg" == *"WatchdogSec"* && "$msg" == *"1h"* && "$msg" == *"30"* ]]; then
    ok "(3a) WatchdogSec config drift (cat: 1h vs env 30 s) → page-class with BOTH measured values, no clock"
else
    bad "(3a) watchdog drift case wrong: $out (msg=$msg)"
fi
new_mock
out=$(drive_rot "$STANDBY" 20 scen_sli 1 file 0 "")
if [[ "$(field "$out" drift)" == "[0]" && "$(field "$out" since)" == "0" && "$(field "$out" driftmsg)" == *"StartLimitIntervalUSec"* ]]; then
    ok "(3b) StartLimitIntervalUSec=10s (R8 pair drift, Restart still no) → page-class, no clock (B3: dispatch intact now)"
else
    bad "(3b) StartLimit drift case wrong: $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 20 scen_xor 1 file 0 "")
if [[ "$(field "$out" drift)" == "[0]" && "$(field "$out" since)" == "0" ]]; then
    ok "(3c) BOTH fence unit files present (XOR violation, real loadable) → page-class, no clock"
else
    bad "(3c) XOR case wrong: $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 20 scen_monstub 1 file 0 "")
if [[ "$(field "$out" drift)" == "[0]" && "$(field "$out" rot)" == "[]" && "$(field "$out" since)" == "0" ]]; then
    ok "(3d) monitor unit NOT LOADED (stub answers Restart=no + OnFailure= empty) → page-class ONLY — the stub values did NOT misread as demote-class (the D1/D2 container trap)"
else
    bad "(3d) stub-value trap: not-loaded monitor misclassified: $out"
fi

# ── (4) first page immediate on fresh boot ──────────────────────────────────────────────────────
echo ""; echo "─── (4) fresh-boot (young uptime) first page immediate; control: guard broken → delayed ───"
new_mock
out=$(T0=100 drive_rot "$STANDBY" 20 scen_masked 1 file 0 "")
if [[ "$(field "$out" rot)" == "[0]" ]]; then
    ok "(4a) uptime 100 s (< ALERT_THROTTLE): first CRITICAL page fires at the FIRST rot sweep — the throttle gates repeats only"
else
    bad "(4a) fresh-boot first page delayed: $out"
fi
MUT4="$_HARNESS_TMP/standby-rot-firstpage.sh"
if mutate "$STANDBY" 's/_last_rot_page:-0} -gt 0/_last_rot_page:-0} -ge 0/' "$MUT4"; then
    new_mock
    out=$(T0=100 drive_rot "$MUT4" 20 scen_masked 1 file 0 "")
    if [[ "$(field "$out" rot)" == "[]" ]]; then
        ok "(4b) CONTROL: 0-sentinel guard broken (-gt→-ge) → the first page IS throttle-swallowed on a young-uptime host — (4a) genuinely observes the guard"
    else
        bad "(4b) control vacuous (mutant still paged immediately): $out"
    fi
fi
# TV-3 (panel fix): the page-class and cannot-verify FIRST pages carry the same 0-sentinel
# guards, but every earlier case ran them at T0=100000 where now-minus-0 already exceeds the
# throttle — both guards were UNKILLED mutants (executed: -ge flip and -eq -1 neuter both
# passed 50/50). Young-uptime positives + controls, mirroring (4a)/(4b):
new_mock
out=$(T0=100 drive_rot "$STANDBY" 20 scen_wdrift 1 file 0 "")
if [[ "$(field "$out" drift)" == "[0]" ]]; then
    ok "(4c) uptime 100 s: the FIRST page-class drift page fires at the first sweep (its 0-sentinel guard is load-bearing on young uptime)"
else
    bad "(4c) fresh-boot first page-class page delayed: $out"
fi
MUT4C="$_HARNESS_TMP/standby-rot-firstpageclass.sh"
if mutate "$STANDBY" 's/_last_rot_pageclass_page:-0} -gt 0/_last_rot_pageclass_page:-0} -ge 0/' "$MUT4C"; then
    new_mock
    out=$(T0=100 drive_rot "$MUT4C" 20 scen_wdrift 1 file 0 "")
    if [[ "$(field "$out" drift)" == "[]" ]]; then
        ok "(4d) CONTROL: page-class 0-sentinel broken (-gt→-ge) → the first CONFIG DRIFT page is throttle-swallowed at T0=100 — (4c) genuinely observes the guard"
    else
        bad "(4d) control vacuous (mutant still paged): $out"
    fi
fi
new_mock
out=$(T0=100 drive_rot "$STANDBY" 400 scen_wedge 1 file 0 "")
if [[ "$(field "$out" cv)" == "[180]" ]]; then
    ok "(4e) uptime 100 s: the FIRST blind page still fires exactly at streak 4 (t0+180) — the cv 0-sentinel is load-bearing on young uptime"
else
    bad "(4e) fresh-boot first cv page wrong (want cv=[180]): $out"
fi
MUT4E="$_HARNESS_TMP/standby-rot-firstcv.sh"
if mutate "$STANDBY" 's/_last_rot_cv_page:-0} -eq 0/_last_rot_cv_page:-0} -eq -1/' "$MUT4E"; then
    new_mock
    out=$(T0=100 drive_rot "$MUT4E" 400 scen_wedge 1 file 0 "")
    if [[ "$(field "$out" cv)" == "[]" ]]; then
        ok "(4f) CONTROL: cv 0-sentinel neutered (-eq 0 → -eq -1) → the first SWEEP-BLIND page is swallowed at T0=100 — (4e) genuinely observes the guard"
    else
        bad "(4f) control vacuous (mutant still paged): $out"
    fi
fi

# ── (5) throttle: persistent rot pages, not a storm ─────────────────────────────────────────────
echo ""; echo "─── (5) persistent rot 3600 s: first + per-ALERT_THROTTLE re-pages; control: storm ───"
new_mock
printf 'U1\n' > "$MOCK_DIR/identity"   # unstaked holder: expiry never demotes, paging continues
out=$(drive_rot "$STANDBY" 3600 scen_masked 1 file 0 "")
if [[ "$(field "$out" rot)" == "[0 600 1200 1800 2400 3000 3600]" && "$(field "$out" demotes)" == "[]" ]]; then
    ok "(5a) rot pages at exactly t0+0,600,…,3600 (7 pages; first immediate, then per ALERT_THROTTLE) and an UNSTAKED holder is never demoted"
else
    bad "(5a) throttle offsets wrong: $out"
fi
MUT5="$_HARNESS_TMP/standby-rot-storm.sh"
if mutate "$STANDBY" '/# rot re-page throttle/d' "$MUT5"; then
    new_mock
    printf 'U1\n' > "$MOCK_DIR/identity"
    out=$(drive_rot "$MUT5" 600 scen_masked 1 file 0 "")
    n=$(field "$out" rot); n=$(printf '%s' "$n" | tr ' ' '\n' | grep -c '[0-9]')
    if [[ "$n" -ge 8 ]]; then
        ok "(5b) CONTROL: throttle line deleted → $n pages in 600 s (a storm) — (5a)'s offsets genuinely observe the throttle"
    else
        bad "(5b) control vacuous (mutant still throttled, $n pages): $out"
    fi
fi

# ── (6) episodic reset MEASURED ─────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) rot→heal→re-rot: resolution + FRESH window; control: stale anchor demotes early ───"
new_mock
out=$(drive_rot "$STANDBY" 2100 scen_episodic 1 file 0 "")
if [[ "$(field "$out" resolves)" == "1" && "$(field "$out" demotes)" == "[2040]" ]]; then
    ok "(6a) MEASURED: rot@0 → heal@120 (one resolution info, window reset) → re-rot@240 → demote at t0+2040 = 240 + FULL grace 1800 (not at 1800)"
else
    bad "(6a) episodic reset wrong (want resolves=1 demotes=[2040]): $out"
fi
MUT6="$_HARNESS_TMP/standby-rot-staleanchor.sh"
# the stale-anchor control now targets the PER-SIGNAL clean-reset (the panel-fix mechanism):
# neutering S2's positive-clean reset (the line the episodic heal runs through) must revive
# the early fire. Substitution, not deletion — an emptied elif arm would be a parse error, and
# a parse-dead mutant is a vacuous control.
if mutate "$STANDBY" 's/_rot_s2_since=0   # S2 positive-clean reset.*/: # S2 positive-clean reset NEUTERED (stale-anchor control)/' "$MUT6"; then
    new_mock
    out=$(drive_rot "$MUT6" 2100 scen_episodic 1 file 0 "")
    d=$(field "$out" demotes)
    if [[ "$d" == "[1800]" ]]; then
        ok "(6b) CONTROL RED: S2 clean-reset neutered → STALE-ANCHOR demote at t0+1800 (grace minus the healed 240 s of history) — the measured early fire (6a) protects against"
    else
        bad "(6b) stale-anchor control wrong (want demotes=[1800]): $out"
    fi
fi

# ── (7) expiry outcomes ─────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (7) expiry: staked → REAL demote path; unstaked → no demote; unreadable → wait ───"
new_mock
out=$(drive_rot "$PRIMARY" 1900 scen_masked 1 file 1 "")
av_rm=$(ev_grep '^av:remove-all'); av_si=$(ev_grep '^av:set-identity')
if [[ "$av_rm" -ge 1 && "$av_si" -ge 1 ]]; then
    ok "(7a) PRIMARY expiry+staked: the EXISTING switch_to_unstaked path ran (remove-all=$av_rm set-identity=$av_si recorded) — no new mutation site"
else
    bad "(7a) primary demote path not driven (remove-all=$av_rm set-identity=$av_si): $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 1900 scen_masked 1 file 1 "")
av_rm=$(ev_grep '^av:remove-all'); av_si=$(ev_grep '^av:set-identity')
if [[ "$av_rm" -ge 1 && "$av_si" -ge 1 ]]; then
    ok "(7b) STANDBY expiry+staked: the EXISTING give_back_identity path ran (remove-all=$av_rm set-identity=$av_si)"
else
    bad "(7b) standby demote path not driven (remove-all=$av_rm set-identity=$av_si): $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 1900 scen_masked 1 file 0 "")
if [[ "$(field "$out" demotes)" == "[1800]" && "$(field "$out" demotetext)" == *"verified-demote proof"* && "$(field "$out" demotetext)" == *"healthy side"* ]]; then
    ok "(7c) demote at exactly t0+grace; the reason names the automatic-failover consequence (verified-demote proof / healthy side continues)"
else
    bad "(7c) demote timing/reason wrong: $out"
fi
new_mock
printf 'U1\n' > "$MOCK_DIR/identity"
out=$(drive_rot "$STANDBY" 1900 scen_masked 1 file 0 "")
if [[ "$(field "$out" demotes)" == "[]" && "$(field "$out" noted)" -ge 1 ]]; then
    ok "(7d) expiry + UNSTAKED → NO demote (nothing to protect), one info note"
else
    bad "(7d) unstaked expiry wrong: $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 2000 scen_unreadable 1 file 0 "")
r=$(field "$out" rot)
if [[ "$(field "$out" demotes)" == "[1920]" && "$r" == *"1800"* ]]; then
    ok "(7e) identity UNREADABLE at expiry → NO demote (a guess), paging continues; demote lands at t0+1920 — the first READABLE staked sweep"
else
    bad "(7e) unreadable-expiry handling wrong: $out"
fi

# ── (8) never-instant control ───────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) grace neutered → instant demote (red); shipped → only after FENCE_ROT_GRACE ───"
MUT8="$_HARNESS_TMP/standby-rot-instant.sh"
if mutate "$STANDBY" 's/-ge \$FENCE_ROT_GRACE ]]/-ge 0 ]]/' "$MUT8"; then
    new_mock
    out=$(drive_rot "$MUT8" 100 scen_masked 1 file 0 "")
    if [[ "$(field "$out" demotes)" == "[0]" ]]; then
        ok "(8a) CONTROL RED: grace check neutered → INSTANT demote at the first rot sweep — the never-instant contract is genuinely held by that check"
    else
        bad "(8a) instant-demote control vacuous: $out"
    fi
fi
new_mock
out=$(drive_rot "$STANDBY" 1900 scen_masked 1 file 0 "")
if [[ "$(field "$out" demotes)" == "[1800]" ]]; then
    ok "(8b) shipped: demote fires ONLY at t0+FENCE_ROT_GRACE of persistent verified rot (never instant)"
else
    bad "(8b) shipped demote timing wrong: $out"
fi

# ── (9) cannot-verify ───────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) systemctl wedged: NOT rot; page only at streak 4; succeeded reads still classify ───"
new_mock
out=$(drive_rot "$STANDBY" 400 scen_wedge 1 file 0 "")
if [[ "$(field "$out" rot)" == "[]" && "$(field "$out" since)" == "0" && "$(field "$out" cv)" == "[180]" ]]; then
    ok "(9a) all reads wedged (rc 124): zero rot pages, zero clock; ONE blind page exactly at streak 4 (t0+180, sweeps 0/60/120/180)"
else
    bad "(9a) cannot-verify handling wrong (want cv=[180], no rot): $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 3000 scen_wedge 1 file 0 "")
if [[ "$(field "$out" cv)" == "[180 780 1380 1980 2580]" && "$(field "$out" demotes)" == "[]" ]]; then
    ok "(9b) persistent blindness: re-page per ALERT_THROTTLE from the threshold, never a demote clock"
else
    bad "(9b) blind re-page offsets wrong: $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 200 scen_wedge_mon 1 file 0 "")
if [[ "$(field "$out" rot)" == "[0]" && "$(field "$out" since)" != "0" && "$(field "$out" scwedge)" -ge 1 ]]; then
    ok "(9c) SPLIT sweep: monitor read wedged (cv) but the fence read SUCCEEDED and shows masked → still classifies demote-class (succeeded reads classify normally)"
else
    bad "(9c) split-sweep classification wrong: $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 500 scen_rot_cv_rot 1 file 0 "")
if [[ "$(field "$out" resolves)" == "0" && "$(field "$out" since)" == "$(( T0 + 0 ))" ]]; then
    ok "(9d) cv sweeps neither HEAL nor re-anchor an open window: rot@0 → wedged sweeps → rot again — since stays t0 (no resolution during blindness)"
else
    bad "(9d) window not preserved across cv sweeps (since=$(field "$out" since), want $(( T0 + 0 ))): $out"
fi

# ── (10) DRY_RUN bait at the mutation site ──────────────────────────────────────────────────────
echo ""; echo "─── (10) DRY_RUN=true bait: zero admin mutations at the demote site; layer-1 refusal wired ───"
new_mock
out=$(drive_rot "$STANDBY" 1900 scen_masked 1 file 1 "true")
av_all=$(ev_grep '^av:')
dry_n=$(field "$out" dry); dry_n=$(printf '%s' "$dry_n" | tr -d '[]' | tr ' ' '\n' | grep -c '[0-9]')
if [[ "$av_all" == "0" && "$dry_n" -ge 1 ]]; then
    ok "(10a) forced expiry+staked under DRY_RUN=true → ZERO admin-socket events AND the [DRY RUN] adapter title OBSERVED ($dry_n at $(field "$out" dry)) — the expiry→adapter chain was reached and the structural guard, not a skipped chain, kept it inert (defense in depth; armed-real+DRY_RUN is refused at startup anyway)"
else
    bad "(10a) DRY_RUN bait wrong (av=$av_all dry-titles=$dry_n — av must be 0 AND the [DRY RUN] branch must be observed): $out"
fi
cs_p=$(grep -c '^[[:space:]][[:space:]]*_enforce_one_arm_state' "$PRIMARY")
cs_s=$(grep -c '^[[:space:]][[:space:]]*_enforce_one_arm_state' "$STANDBY")
[[ "$cs_p" -ge 1 && "$cs_s" -ge 1 ]] \
    && ok "(10b) layer 1 still wired: the №1 startup refusal call sites present (primary=$cs_p standby=$cs_s)" \
    || bad "(10b) №1 refusal call site missing (primary=$cs_p standby=$cs_s)"

# ── (11) twin + the D3 comment ──────────────────────────────────────────────────────────────────
echo ""; echo "─── (11) [fence-rot] byte-identical; the no-double-sign reasoning AT the grace check ───"
if extract_twin '\[fence-rot\] holder-side fence re-verification' '\[fence-rot\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(11a) [fence-rot] shared block BYTE-IDENTICAL in both daemons ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)"
else
    bad "(11a) [fence-rot] block missing or DIVERGED between the daemons"
fi
if [[ -n "$TWIN_P" ]] && printf '%s\n' "$TWIN_P" | grep -q 'cannot fire against a voting holder'; then
    ok "(11b) D3: the window-adds-no-double-sign reasoning lives AT the grace check (comment present in the block)"
else
    bad "(11b) D3 reasoning comment missing from the block"
fi

# ── (12) per-op pets, both censuses + P1 floors ─────────────────────────────────────────────────
echo ""; echo "─── (12) every bounded read petted (live order + source census); P1 floors on grown daemons ───"
new_mock
out=$( (
    set +e
    _SIM_NOW=$T0
    load_seam "$STANDBY"
    FENCE_UNIT_REAL="$MOCK_DIR/units/solana-failover-fence.service"
    FENCE_UNIT_PAGE_ONLY="$MOCK_DIR/units/solana-failover-fence-page-only.service"
    STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; ALERT_THROTTLE=600
    FENCE_ROT_CHECK_SECS=60; FENCE_ROT_GRACE=1800; DRY_RUN=false
    NOTIFY_SOCKET="$MOCK_DIR/notify.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1
    get_local_identity() { echo S1; }
    _fence_rot_check
    # TV-2 (panel fix): the live census used to cover ONLY the healthy sweep — a read added on
    # the expiry path ran on no order-checked sweep. Extend the SAME drive through one rot
    # sweep and one grace-expiry sweep so every reachable read path is order-checked live
    # (the demote wrapper is stubbed to an event: the sweep's reads are the census subject —
    # the adapters' own pets are (16) of the integration suite).
    _rot_graceful_demote() { echo "op:demote" >> "$EV"; }
    printf 'masked\n' > "$MOCK_DIR/show.fence"
    _SIM_NOW=$(( T0 + 60 ));        _fence_rot_check   # rot sweep: window opens
    _SIM_NOW=$(( T0 + 60 + 1800 )); _fence_rot_check   # expiry sweep: 3 reads + the identity read
    # live census: every sc: event must be followed by an sd:WATCHDOG=1 before the next sc:
    okorder=1; lastsc=""; n=0
    while IFS= read -r line; do
        n=$((n+1))
        # balanced (pattern) forms: bare `pattern)` inside $( ) fails the bash-3.2 parse gate
        case "$line" in
            (sc:*) if [[ -n "$lastsc" ]]; then okorder=0; fi; lastsc=$n ;;
            (sd:WATCHDOG=1*) lastsc="" ;;
        esac
    done < "$EV"
    [[ -n "$lastsc" ]] && okorder=0
    printf 'order=%s|sc=%s|pets=%s|opdem=%s\n' "$okorder" "$(ev_grep '^sc:')" "$(ev_grep '^sd:WATCHDOG=1')" "$(ev_grep '^op:demote')"
) )
if [[ "$(field "$out" order)" == "1" && "$(field "$out" sc)" == "9" && "$(field "$out" pets)" -ge 10 && "$(field "$out" opdem)" == "1" ]]; then
    ok "(12a) LIVE census across healthy + rot + EXPIRY sweeps: 9 systemctl reads, each followed by its pet before the next read; the expiry identity read petted (pets=$(field "$out" pets) ≥ 10) and the demote path reached ($out)"
else
    bad "(12a) live pet order wrong (want order=1 sc=9 pets>=10 opdem=1): $out"
fi
if extract_twin '\[fence-rot\] holder-side fence re-verification' '\[fence-rot\] end shared block'; then
    # invocation census (fix texts inside page STRINGS legitimately mention systemctl — count
    # COMMAND-position sites only): every read funnels through the ONE bounded _rot_sysread
    # line. TV-2 (panel fix): the stray set now also catches (a) `$(timeout … systemctl`
    # spellings BESIDE the funnel (a bounded-but-unfunneled read loses the structural per-op
    # pet — executed green pre-fix) and (b) the TV-1 command-position family (if/elif/while/
    # until/;/&&/|| systemctl).
    sc_funnel=$(printf '%s\n' "$TWIN_P" | grep -v '^[[:space:]]*#' | grep -c 'timeout -k 2 5 systemctl "\$@"')
    sc_stray=$(printf '%s\n' "$TWIN_P" | grep -v '^[[:space:]]*#' | grep -v 'timeout -k 2 5 systemctl "\$@"' | grep -cE '^[[:space:]]*systemctl |[^(]\$\(systemctl |=\$\(systemctl |\$\(timeout[^)]*systemctl |(^|;|&&|\|\||if |elif |while |until )[[:space:]]*systemctl ')
    pet_sites=$(printf '%s\n' "$TWIN_P" | grep -cE '^[[:space:]]*_watchdog_pet\b')
    if [[ "$sc_funnel" == "1" && "$sc_stray" == "0" && "$pet_sites" -ge 2 ]]; then
        ok "(12b) SOURCE census: ONE bounded funnel (timeout -k 2 5 systemctl \"\$@\") carries every read, zero stray command-position OR timeout-wrapped systemctl beside it; $pet_sites in-block pet call sites (the funnel's per-op pet + the expiry identity-read pet)"
    else
        bad "(12b) source census wrong (funnel=$sc_funnel stray=$sc_stray pets=$pet_sites)"
    fi
fi
p1_ok=1
for d in "$PRIMARY" "$STANDBY"; do
    pets=$(grep -cE '^[[:space:]]*_watchdog_pet\b' "$d")
    ready=$(grep -c 'READY=1' "$d")
    gate=$(grep -c '_watchdog_active()' "$d")
    [[ "$pets" -ge 10 && "$ready" -ge 1 && "$gate" -ge 1 ]] || p1_ok=0
done
[[ "$p1_ok" == "1" ]] \
    && ok "(12c) the arm's P1 capability floors (≥10 pet sites, ≥1 READY=1, _watchdog_active) still pass against BOTH grown daemons" \
    || bad "(12c) a grown daemon no longer meets the P1 capability floor"

# ── (13) N-is-all: ALLOWLIST census — every systemctl-bearing line accounted ────────────────────
echo ""; echo "─── (13) allowlist census: every systemctl line is a string mention or an enumerated site ───"
# TV-1 (panel fix): the OLD census grepped for known invocation SPELLINGS and failed OPEN — an
# injected `if systemctl is-active --quiet …` (and the && / || / while family) sailed through
# 50/50 (executed on both daemons). INVERTED to an allowlist: comment-strip, take EVERY line
# containing `systemctl`, subtract pure string-mention lines BY MECHANISM — remove quoted
# spans, cut the trailing comment, drop the line if the word is gone — EXCEPT that a
# `$( … systemctl` substitution keeps the line regardless (quoted command substitution
# EXECUTES). Unbalanced quotes err toward KEEPING a line: the census fails CLOSED. The
# remainder must equal the enumerated site list EXACTLY:
#   1 in-block bounded read FUNNEL (timeout -k 2 5 systemctl "$@") — the ONE sweep read path;
#   2 hard-stop ACTUATORS (`timeout -k 5 15 systemctl stop|mask --runtime`, the H2 path —
#     mutations, not property reads; they do not belong in the sweep);
#   1 startup-path fallback READ, get_validator_args's
#     `timeout -k 2 5 systemctl show ${VALIDATOR_SERVICE} -p ExecStart` — pre-existing, cached,
#     reached only when /proc/<pid>/cmdline is unreadable; NOT absorbed into the sweep (it reads
#     the VALIDATOR unit at startup, not the fence topology at runtime). BOUNDED at the 5.4
#     reviewer GO condition: unbounded, a wedged systemctl here blocked startup pre-READY under
#     the armed Type=notify unit — TimeoutStartSec → failed → OnFailure → real fence on a
#     healthy validator (case (19) pins the bound behaviorally; this census pins the spelling —
#     a revert to the bare read turns bounded_show 0 and goes red).
# (re-calibrated 2026-08-21 by grep, never memory — the war story stands: the first calibration
# of the old census guessed "standby only" for the ExecStart read and went red on the primary.)
rot_census() {   # $1=daemon → every non-comment line where systemctl survives quote-strip, or that opens a $( … systemctl substitution
    local _rc_line _rc_strip
    grep -v '^[[:space:]]*#' "$1" | grep 'systemctl' | while IFS= read -r _rc_line; do
        _rc_strip=$(printf '%s\n' "$_rc_line" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g" | sed 's/#.*//')
        case "$_rc_strip" in
            (*systemctl*) printf '%s\n' "$_rc_line"; continue ;;
        esac
        if printf '%s\n' "$_rc_line" | grep -qE '\$\([^)]*systemctl'; then printf '%s\n' "$_rc_line"; fi
    done
}
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    inv=$(rot_census "$script")
    n_inv=$(printf '%s\n' "$inv" | grep -c 'systemctl')
    funnel=$(printf '%s\n' "$inv" | grep -c 'timeout -k 2 5 systemctl "\$@"')
    hard=$(printf '%s\n' "$inv" | grep -cE 'systemctl (stop|mask) ')
    known_show=$(printf '%s\n' "$inv" | grep -c 'systemctl show "\${VALIDATOR_SERVICE')
    bounded_show=$(printf '%s\n' "$inv" | grep -c 'timeout -k 2 5 systemctl show "\${VALIDATOR_SERVICE')
    if [[ "$n_inv" == "4" && "$funnel" == "1" && "$hard" == "2" && "$known_show" == "1" && "$bounded_show" == "1" ]]; then
        ok "(13) $name: allowlist census EXACT — 4 systemctl-bearing invocation lines = the in-block funnel + 2 hard-stop actuators + 1 startup ExecStart read (BOUNDED since the 5.4 GO condition — the spelling is asserted, a bare revert goes red); every other systemctl line is a pure string mention"
    else
        bad "(13) $name: systemctl census moved (total=$n_inv want=4 funnel=$funnel hard=$hard known_show=$known_show bounded_show=$bounded_show) — REVIEW: $(printf '%s\n' "$inv" | head -5 | tr '\n' ' ')"
    fi
done

# ── (14) inertness gate control ─────────────────────────────────────────────────────────────────
echo ""; echo "─── (14) gate forced open → un-armed sweep leaks systemctl events (the (1) assert bites) ───"
MUT14="$_HARNESS_TMP/standby-rot-gateopen.sh"
if mutate "$STANDBY" 's/_watchdog_active() {/_watchdog_active() { return 0;/' "$MUT14"; then
    new_mock
    out=$(drive_rot "$MUT14" 20 scen_masked 0 file 0 "")
    if [[ "$(field "$out" sc)" -ge 1 ]]; then
        ok "(14) CONTROL: _watchdog_active forced open → $(field "$out" sc) systemctl events with NO NOTIFY_SOCKET — (1a)'s zero-count genuinely observes the gate"
    else
        bad "(14) control vacuous (open gate still ran zero reads): $out"
    fi
fi

# ── (15) knob validation + drift announcer ──────────────────────────────────────────────────────
echo ""; echo "─── (15) floors: FENCE_ROT_GRACE ≥ max(600, ALERT_THROTTLE) with both reasons; drift lines ───"
val_probe() {  # $1=daemon $2..=VAR=val overrides ; echoes "rc|err-text"
    local script="$1"; shift
    (
        set +e
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        log(){ :;}; log_info(){ :;}; log_warn(){ :;}
        ERR=""
        log_error(){ ERR="$ERR $*"; }
        alert(){ :;}; alert_warn(){ :;}; alert_info(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
        local kv
        for kv in "$@"; do eval "$kv"; done
        ( validate_numeric_config ) >/dev/null 2>&1
        rc=$?
        # re-run in THIS shell only to harvest the error text when it refuses
        if [[ $rc -ne 0 ]]; then
            exit(){ :; }
            validate_numeric_config >/dev/null 2>&1
        fi
        printf '%s|%s\n' "$rc" "$ERR"
    )
}
out=$(val_probe "$STANDBY" 'FENCE_ROT_GRACE=300')
rc="${out%%|*}"; err="${out#*|}"
if [[ "$rc" == "1" && "$err" == *"human"* && "$err" == *"re-page"* ]]; then
    ok "(15a) FENCE_ROT_GRACE=300 (< 600 floor) → fatal; the error names BOTH reasons (a human must be able to read a page; ≥1 re-page inside the grace)"
else
    bad "(15a) grace floor wrong (rc=$rc err=$err)"
fi
out=$(val_probe "$STANDBY" 'ALERT_THROTTLE=900' 'FENCE_ROT_GRACE=700')
rc="${out%%|*}"
[[ "$rc" == "1" ]] \
    && ok "(15b) FENCE_ROT_GRACE=700 < ALERT_THROTTLE=900 → fatal (floor = max(600, ALERT_THROTTLE))" \
    || bad "(15b) throttle-floor not enforced (rc=$rc)"
out=$(val_probe "$STANDBY" 'FENCE_ROT_GRACE=1800' 'FENCE_ROT_CHECK_SECS=60')
rc="${out%%|*}"
[[ "$rc" == "0" ]] \
    && ok "(15c) defaults validate clean" \
    || bad "(15c) defaults refused (rc=$rc): $out"
out=$(val_probe "$STANDBY" 'FENCE_ROT_CHECK_SECS=5')
rc="${out%%|*}"
[[ "$rc" == "1" ]] \
    && ok "(15d) FENCE_ROT_CHECK_SECS=5 (< 10) → fatal" \
    || bad "(15d) check-cadence floor not enforced (rc=$rc)"
d_out=$(drift_out "$STANDBY" 'FENCE_ROT_GRACE=3600')
if [[ "$(printf '%s\n' "$d_out" | grep -c '\[config-drift\]')" == "1" && "$d_out" == *"FENCE_ROT_GRACE=3600"* ]]; then
    ok "(15e) drift announcer: FENCE_ROT_GRACE raised → one laxer-than-default line"
else
    bad "(15e) grace drift announce wrong: $d_out"
fi
d_out=$(drift_out "$PRIMARY" 'FENCE_ROT_CHECK_SECS=600')
if [[ "$(printf '%s\n' "$d_out" | grep -c '\[config-drift\]')" == "1" ]]; then
    ok "(15f) drift announcer (primary): FENCE_ROT_CHECK_SECS raised → one line (shared table)"
else
    bad "(15f) cadence drift announce wrong: $d_out"
fi
d_out=$(drift_out "$STANDBY")
[[ -z "$d_out" ]] \
    && ok "(15g) defaults announce nothing" \
    || bad "(15g) defaults produced drift output: $d_out"

# ── startup wiring: intent captured at startup under the armed unit ────────────────────────────
echo ""; echo "─── (16) _rot_capture_intent wired in startup (call-site grep, both daemons) ───"
cs_p=$(grep -c '^[[:space:]][[:space:]]*_rot_capture_intent' "$PRIMARY")
cs_s=$(grep -c '^[[:space:]][[:space:]]*_rot_capture_intent' "$STANDBY")
[[ "$cs_p" -ge 1 && "$cs_s" -ge 1 ]] \
    && ok "(16) intent-capture call sites present in startup (primary=$cs_p standby=$cs_s)" \
    || bad "(16) _rot_capture_intent not called from startup (primary=$cs_p standby=$cs_s)"

# ── (17) per-signal anchors (ROT-DEMOTE-1 BLOCKER fix) — the panel timelines, MEASURED ─────────
echo ""; echo "─── (17) a heal seen on a signal's OWN read closes ITS window even under blind siblings ───"
# RED on the pre-fix daemons (logged, both daemons, deterministic dropped-key trigger):
# rot=[0 3000]|demotes=[3000]|resolves=0 — the ancient t0 anchor survived a GENUINE fence heal
# because the all-or-nothing verify gate discarded the positive LoadState=loaded evidence; the
# fresh masked read at t=3000 demoted with 0 s of the 1800 s grace (contract: never instant).
for script in "$STANDBY" "$PRIMARY"; do
    name=$(basename "$script")
    new_mock
    out=$(drive_rot "$script" 5000 scen_stale_dropkey 1 file 0 "")
    if [[ "$(field "$out" demotes)" == "[4800]" && "$(field "$out" resolves)" == "1" ]]; then
        ok "(17a) $name: rot@0 → GENUINE heal@60 under a dropped-key-blind monitor read → ONE resolution; fresh rot@3000 gets its OWN FULL grace → demote at 4800, never 3000"
    else
        bad "(17a) $name: stale-anchor hole (want demotes=[4800] resolves=1): $out"
    fi
done
new_mock
out=$(drive_rot "$STANDBY" 5000 scen_group_split 1 file 0 "")
if [[ "$(field "$out" demotes)" == "[4800]" && "$(field "$out" resolves)" == "1" ]]; then
    ok "(17b) WITHIN-GROUP: S1 file-GONE@0 → file restored@60 (S1 clean) while the S2 LoadState read is BLIND → fresh S2 rot@3000 demotes at 4800 — a shared file+LoadState group anchor would fire at 3000 (why the anchors are per-SIGNAL, not per-read-group)"
else
    bad "(17b) within-group split wrong (want demotes=[4800] resolves=1): $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 2100 scen_rot_blind_rot 1 file 0 "")
if [[ "$(field "$out" demotes)" == "[1920]" && "$(field "$out" resolves)" == "0" ]]; then
    ok "(17c) PRESERVED 9d semantics: continuous S2 rot across blind sweeps (no positive clean ever) → no resolution, anchor held → demote at the FIRST verified-rot sweep past grace (1920)"
else
    bad "(17c) 9d semantics broken (want demotes=[1920] resolves=0): $out"
fi
# (17d) the distinction from (17a): there the fence WAS positively seen healthy (loaded read
# succeeded) so its window closed; here S3 is rot@0 then only ever BLIND — no positive clean
# ever intervened, so the anchor legitimately survives ~80 min of blindness and the re-verified
# rot demotes at once (grace long since served). Blindness must not close what it cannot see.
new_mock
out=$(drive_rot "$STANDBY" 5200 scen_s3_blind_hold 1 file 0 "")
if [[ "$(field "$out" demotes)" == "[5040]" && "$(field "$out" resolves)" == "0" ]]; then
    ok "(17d) M-signal never-positively-clean: S3 rot@0 → monitor read blind thereafter → re-verified rot@5040 demotes immediately (anchor held: NO positive clean ever seen — the deliberate contrast with (17a)'s closed window)"
else
    bad "(17d) never-clean hold wrong (want demotes=[5040] resolves=0): $out"
fi
MUT17="$_HARNESS_TMP/standby-rot-s2reset.sh"
if mutate "$STANDBY" 's/_rot_s2_since=0   # S2 positive-clean reset.*/: # S2 positive-clean reset NEUTERED (stale-anchor control)/' "$MUT17"; then
    new_mock
    out=$(drive_rot "$MUT17" 5000 scen_stale_dropkey 1 file 0 "")
    if [[ "$(field "$out" demotes)" == "[3000]" && "$(field "$out" resolves)" == "0" ]]; then
        ok "(17e) CONTROL RED: S2 clean-reset neutered → the exact panel numbers return (demotes=[3000], 0 s grace for the fresh rot, no resolution) — (17a) genuinely observes the per-signal reset"
    else
        bad "(17e) control vacuous (want the panel's demotes=[3000] resolves=0): $out"
    fi
fi

echo ""; echo "─── (17f–j) expiry demote-attempt throttle (ROT-INT-2) + adapter-blocked parity pages ───"
# RED on the pre-fix daemons (logged): dry=[1800 1860 1920 … 5400] — 61 adapter CRITICALs in
# 3600 s (one per 60 s sweep, forever); the standby's keypair-blocked branch alerted NOTHING.
new_mock
out=$(drive_rot "$STANDBY" 5400 scen_masked 1 file 1 "true")
if [[ "$(field "$out" dry)" == "[1800 2400 3000 3600 4200 4800 5400]" && "$(field "$out" retryw)" == "54" ]]; then
    ok "(17f) staked-forever expiry (DRY_RUN adapter): FIRST attempt at expiry immediate (1800), re-attempts once per ALERT_THROTTLE (2400…5400 = 7 attempts, not 61) with a throttled-suppression warn per skipped sweep (54)"
else
    bad "(17f) demote-retry throttle wrong (want dry=[1800 2400 3000 3600 4200 4800 5400] retryw=54): $out"
fi
MUT17F="$_HARNESS_TMP/standby-rot-retrystorm.sh"
if mutate "$STANDBY" 's/_last_rot_demote_try:-0} -gt 0/_last_rot_demote_try:-0} -lt 0/' "$MUT17F"; then
    new_mock
    out=$(drive_rot "$MUT17F" 3000 scen_masked 1 file 1 "true")
    n=$(field "$out" dry); n=$(printf '%s' "$n" | tr -d '[]' | tr ' ' '\n' | grep -c '[0-9]')
    if [[ "$n" -ge 20 ]]; then
        ok "(17g) CONTROL RED: retry-throttle guard neutered → $n adapter pages in 1200 s past expiry (the 60 s storm returns) — (17f) genuinely observes the throttle"
    else
        bad "(17g) control vacuous (mutant still throttled, $n pages): $out"
    fi
fi
new_mock
out=$(drive_rot "$STANDBY" 3000 scen_masked_nokp 1 file 1 "")
if [[ "$(field "$out" kpb)" == "[1800 2400 3000]" && "$(field "$out" demotes)" == "[]" ]]; then
    ok "(17h) STANDBY keypair-blocked demote: give_back_identity now PAGES (GIVE BACK BLOCKED — keypair problem) — parity with the primary's SWITCH BLOCKED, throttled to attempt cadence (was: silent log_error only)"
else
    bad "(17h) standby keypair-blocked page missing/wrong (want kpb=[1800 2400 3000]): $out"
fi
new_mock
out=$(drive_rot "$PRIMARY" 3000 scen_masked_nokp 1 file 1 "")
if [[ "$(field "$out" kpb)" == "[1800 2400 3000]" ]]; then
    ok "(17i) PRIMARY keypair-blocked demote: SWITCH BLOCKED pages now land at attempt cadence (1800, 2400, 3000 — was one per 60 s sweep)"
else
    bad "(17i) primary keypair-blocked throttle wrong (want kpb=[1800 2400 3000]): $out"
fi

# ── (18) classifier-arm captures (ROT-INT-1) — precap shapes files BEFORE intent capture ───────
echo ""; echo "─── (18) intent=none demote-class at full grace; page-only drifts are page-class, no clock ───"
new_mock
out=$(drive_rot "$STANDBY" 1900 scen_none_dropin 1 file 0 "")
msg=$(field "$out" rotmsg)
if [[ "$(field "$out" rot)" == "[0 600 1200 1800]" && "$(field "$out" demotes)" == "[1800]" && "$(field "$out" resolves)" == "0" && "$msg" == *"intent at startup: none"* && "$msg" == *"will NOT clear this escalation"* ]]; then
    ok "(18a) intent=none (fence removed while the daemon was down): demote-class from startup, FULL grace held (demote at 1800, never instant), NO runtime heal from the healthy unit dropped in at t=60 — and the page SAYS a bare file drop-in will not clear it (ROT-DEMOTE-2)"
else
    bad "(18a) intent=none arm wrong (want rot=[0 600 1200 1800] demotes=[1800] resolves=0 + the drop-in clause): $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 1400 scen_pageonly_real_appears 1 file 0 "")
msg=$(field "$out" driftmsg)
if [[ "$(field "$out" rot)" == "[]" && "$(field "$out" since)" == "0" && "$(field "$out" drift)" == "[120 720 1320]" && "$msg" == *"№1 deadly combination arising at RUNTIME"* ]]; then
    ok "(18b) page-only intent + REAL unit appears at runtime: page-class №1-at-runtime drift (named in the page), NO demote clock ever"
else
    bad "(18b) page-only→real arm wrong (want drift=[120 720 1320], no clock): $out"
fi
new_mock
out=$(drive_rot "$STANDBY" 1400 scen_pageonly_gone 1 file 0 "")
if [[ "$(field "$out" rot)" == "[]" && "$(field "$out" since)" == "0" && "$(field "$out" drift)" == "[120 720 1320]" && "$(field "$out" driftmsg)" == *"page-only fence unit file GONE"* ]]; then
    ok "(18c) page-only intent + unit GONE at runtime: page-class GONE drift, NO demote clock"
else
    bad "(18c) page-only-gone arm wrong (want drift=[120 720 1320], no clock): $out"
fi

# ── (19) the startup ExecStart fallback is BOUNDED (reviewer GO condition, 5.4 push) ────────────
echo ""; echo "─── (19) get_validator_args systemctl fallback: wedged CLI must return through the timeout layer, never hang ───"
# Pre-Block-5 the unbounded `systemctl show … -p ExecStart` was harmless: the daemon hangs,
# Restart=always, nobody dies. Under the ARMED Type=notify unit it is the P1-capability trap from
# the other side: a wedged systemctl HERE blocks startup pre-READY → TimeoutStartSec expires →
# `failed` → OnFailure → the REAL fence fires on a HEALTHY validator. The sweep's own doctrine
# ("systemctl silent = cannot-verify, the CLI is not the enforcement plane, no clock") must hold
# at BOTH sites — one rule, two call sites, one behavior. Mechanics follow the suite's standing
# wedge convention (rot_shims): the timeout layer models the real bound (a wedged systemctl
# returns rc 124, the op never runs); a BARE systemctl call bypasses that layer and hangs — which
# is exactly the unbounded reality this case pins. Red observed on the pre-fix daemons: the bare
# call hung past the 8 s deadline on both.
run_case19() {   # $1 = daemon path
    local _c19_name _c19_snip _c19_drv _c19_done _c19_ev _c19_pid _c19_waited
    _c19_name=$(basename "$1")
    _c19_snip="$_HARNESS_TMP/gva-$_c19_name.snip"
    _c19_drv="$_HARNESS_TMP/gva-$_c19_name.drv"
    _c19_done="$_HARNESS_TMP/gva-$_c19_name.done"
    _c19_ev="$_HARNESS_TMP/gva-$_c19_name.ev"
    # the cache var + get_validator_args, verbatim from the shipped daemon (first ^} closes it)
    sed -n '/^_validator_args_cache=""/,/^}/p' "$1" > "$_c19_snip"
    if ! grep -q 'get_validator_args()' "$_c19_snip"; then
        bad "(19) $_c19_name: extraction anchor moved — get_validator_args not captured (cannot-silently-no-op)"
        return
    fi
    {
        printf 'timeout() { case "$*" in *systemctl*) echo "t:BOUNDED $*" >> "%s"; return 124 ;; *) shift; "$@" ;; esac; }\n' "$_c19_ev"
        printf 'systemctl() { echo "sc:BARE-HANG" >> "%s"; sleep 60; }\n' "$_c19_ev"
        printf 'pgrep() { return 1; }\n'
        printf 'VALIDATOR_SERVICE=sol-test.service\n'
        cat "$_c19_snip"
        printf 'get_validator_args >/dev/null 2>&1\n'
        printf ': > "%s"\n' "$_c19_done"
    } > "$_c19_drv"
    rm -f "$_c19_done" "$_c19_ev"
    "$BASH_BIN" "$_c19_drv" &
    _c19_pid=$!
    _c19_waited=0
    while [[ $_c19_waited -lt 8 ]]; do
        [[ -f "$_c19_done" ]] && break
        sleep 1; _c19_waited=$((_c19_waited+1))
    done
    if [[ -f "$_c19_done" ]] && grep -q 't:BOUNDED' "$_c19_ev" 2>/dev/null && ! grep -q 'sc:BARE-HANG' "$_c19_ev" 2>/dev/null; then
        ok "(19) $_c19_name: startup ExecStart fallback returned through the timeout layer in ${_c19_waited}s (<8s), zero bare calls — a wedged CLI can no longer ride TimeoutStartSec into the fence"
    else
        kill "$_c19_pid" 2>/dev/null   # the orphaned sleep exits on its own; nothing waits on it
        bad "(19) $_c19_name: startup fallback UNBOUNDED or bypassing the timeout layer (done=$([[ -f "$_c19_done" ]] && echo yes || echo no) after ${_c19_waited}s; ev: $(tr '\n' ' ' < "$_c19_ev" 2>/dev/null))"
    fi
    wait "$_c19_pid" 2>/dev/null
}
run_case19 "$PRIMARY"
run_case19 "$STANDBY"

# raw-data traces for the report
echo ""
echo "  (report) episodic table: $(new_mock; drive_rot "$STANDBY" 2100 scen_episodic 1 file 0 "" | cut -c1-160)"
echo "  (report) panel timeline (fixed): $(new_mock; drive_rot "$STANDBY" 5000 scen_stale_dropkey 1 file 0 "" | cut -c1-160)"
echo "  (report) armed healthy sweep: $(new_mock; drive_rot "$STANDBY" 100 scen_healthy 1 file 0 "" | cut -c1-160)"

rm -rf "$WORK"
results_banner
