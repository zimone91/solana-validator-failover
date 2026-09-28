#!/bin/bash
# v0.7 (Block 6.3.1 fix round 1, R5 — the panel's F1–F5, F9 and CC-8): the cross-node invariant table's HOLDER
# column (docs/SAFETY.md, 'The cross-node invariant'), MEASURED here and PINNED — before this suite the column
# was text only and nothing went red if it drifted (CC-8). t = 0 is the holder's LAST LANDED VOTE, the spare
# columns' convention (test_own_view (6)); the table carries the WORST read phase per cadence (the holder's
# latest fence is what faces the spare's earliest take), over CHECK_INTERVAL 1 / 3 / 5.
#
# Drives the REAL primary daemon: the REAL startup_checks (load_state, the tier tests, the identity wait,
# STARTUP_GRACE) and the REAL main loop (extracted verbatim, as test_elapsed_provider's world() does for the
# standby), under a FILE-backed mono clock (a stubbed read TAKES time) and a PHYSICAL model of the holder's
# LOCAL node in which t = 0 is its last landed vote. Only I/O is stubbed. The driver is the 6.3.1 panel's
# d6table lens driver, adopted verbatim (its knobs below), plus a job throttle.
#   MODE     frozen | egress | deadrefuse | deadhang | garbage | fullwedge | none   (the failure from t > 0)
#   CI       CHECK_INTERVAL (3 = the primary default)          GRACE   STARTUP_GRACE (30 = the default)
#   RATE_N/RATE_D  slot rate (5/2 = 2.5 slots/s; 37/10 = 3.7)
#   INST     "start:die start:die …" — monitor instances (offsets from t0; die -1 = runs to HORIZON). Each
#            instance is a FRESH process image (a new subshell that re-sources the seam); the state file (save_state
#            every cycle) and the clock carry over. The first instance's start offset sets the READ PHASE.
#   CORRUPT  sed expression applied to the state file between instance 1 and instance 2 (row (1)'s non-canonical slot)
#   TMODE    refuse (TIER2/TIER3 refuse at once; default) | hang (every tier read times out at its -m bound)
#   SLOWLOCAL <s>: every LOCAL JSON-RPC read answers <s> s late (below its -m bound: still an answer); SLOWLOCAL=b (fix
#            round 2, S4 — CK-3): every LOCAL read answers 1 s inside ITS OWN -m bound (the -m 10 reads at 9 s, the -m 5 at 4)
#   SLOWADMIN <s>: the admin socket answers in <s> s (contact-info's own bound is 8)
#   WEDGE=1  the demote's `authorized-voter remove-all` hangs to its SETIDENTITY_TIMEOUT (→ the hard stop); WEDGEK=1 it
#            needs its -k too (every *K knob: the call's bound + the daemon's OWN -k value, parsed from the call — fix round
#            4, the delta panel 3's TS3-D6-KBOUND; a call with no -k never returns); STOPHANG=1 the `systemctl stop` client
#            times out (STOPK=1: at its bound + its -k) and
#            the validator ignores SIGTERM (the daemon's own SIGKILL stops it) unless TERMOK=1 (PID 1 slow, the validator
#            honouring the daemon's SIGTERM); STOPSECS: how long a prompt `systemctl stop` takes. Fix round 2 (S4 — the
#            delta panel's CK-1): MASKHANG=1 the `systemctl mask --runtime` the hard stop runs after a FAILED stop (and
#            before the kill) times out at its 15 s bound (MASKK=1: + its -k), MASKSECS: how long a prompt one takes;
#            the other wedge order — RASECS=<s> remove-all ANSWERS after <s> s (RASECS=max: at SETIDENTITY_TIMEOUT − 1 from the
#            seam, the admin latency SLOWADMIN included — fix round 4), then SIWEDGE=1 the set-identity to unstaked hangs to
#            its SETIDENTITY_TIMEOUT (SIWEDGEK=1: + its -k)
#   HEALTHBEHIND=1 (frozen): the holder's blockstore still sees the cluster via gossip — getHealth reports behind
#   HORIZON  stop at this t
# Rows (each pinned to its range over the read phase per cadence — and, for the PHASE-SWEPT rows, over the
# collision check's 60 s phase too (fix round 2, S4 — the delta panel's T1-D6; see phase_set below):
#   (a) prompt I/O — dead local RPC (refusing / every read at its bound — phase-swept), frozen slot, egress-only (N6)
#       at 2.5 and 3.7 slots/s (its lag-threshold term included: SELF_FENCE_VOTE_LAG_SLOTS / rate), garbage answers,
#       getHealth behind (F9: never later than the frozen clock), a FULLY WEDGED validator with the monitor running
#       (F5: never)
#   (b) the restarts — row (1) (a corrupted slot restored, restart +30/+45/+63, grace 30 and 0 — F7's 45–60),
#       the PLAIN restart with a canonical state file (F1: the startup blind window, restart + the tier tests +
#       STARTUP_GRACE; its slow-tier-test form phase-swept), the un-armed unit's own crash (Restart=always,
#       RestartSec 10; its slow form phase-swept), (1)'s restart member
#   (c) the wedged demote → hard stop, EVERY daemon term (fix round 2, S4 — CK-1; fix round 3, U4 — CKB-1: the other
#       wedge order with every op at its -k bound; fix round 4, G2 — CC3-2: both orders at -k composed with the worst-case
#       column's own two I/O mixes and with the admin socket's latency alone — the latest over the MEASURED mixes, not a
#       maximum over every mix): trigger + the demote (remove-all to
#       SETIDENTITY_TIMEOUT (+ its -k 5), or remove-all answering and then the set-identity to unstaked to its bound
#       (+ 5)) + the systemctl stop bound (+ 5) + after a failed stop the `systemctl mask --runtime` bound (+ 5) + 2 s,
#       at SETIDENTITY_TIMEOUT = 15 (the default; the daemon only lower-bounds it, at 8); its slow-I/O forms phase-swept
#   (d) the WORST-CASE I/O column (F4): CHECK_INTERVAL 3, the tiers at their -m bounds, the admin socket at 7 s, every
#       LOCAL read at 4 s — every row phase-swept
# NOT COVERED (fix round 2, S4 — the delta panel's CK-3 and CK-9, stated rather than widened):
#   - the clock is INTEGER seconds and a cycle costs ZERO overhead beyond its stubbed reads and sleeps: a real
#     cycle costs a few hundred ms more (SAFETY's measured 3.12–3.33 s cycles at CHECK_INTERVAL 3), and a
#     millisecond model of the same loop lands the frozen fence at 30.3–36.1 s (CI 3) / 32.0–37.0 s (CI 5) against
#     this suite's 30–32 / 30–34 (the delta panel's executed model) — a margin under ~4 s below is not a margin;
#   - (d) is ONE sample I/O mix, not the maximum over mixes: with every LOCAL read 1 s inside ITS OWN -m bound
#     (SLOWLOCAL=b — the -m 10 reads at 9 s) the rows fence later (the (d′) rows below pin that second mix); the
#     wedged-demote row is composed with both mixes (c6 / c6′) and with their parts (c3i/c3j: the admin socket alone;
#     c5b/c5bh: the second mix's LOCAL reads with a prompt admin socket) — sample mixes too, and a slower admin socket or
#     LOCAL read is not monotonic here either (the (d′) forms fence EARLIER than the (d) forms);
#   - N7 (the fresh-start silent gap: real-systemd container runs, docs/SAFETY.md) and the internet-lost demote (by
#     reading — check_internet is stubbed) have no world here; every other row of the table is pinned here.
# MECHANISMS: none changed in fix rounds 1–2 — the options each crossing's finding lists go to the reviewer.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "D6 holder column: the holder's fence, from its last landed vote (v0.7 Block 6.3.1 fix rounds 1-4)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/d6h.XXXXXX"); WORK=$(cd -P -- "$WORK" && pwd -P)
T0=100000; HEAD0=900000
seam_cut "$PRIMARY" >/dev/null

hinst() {   # $1 = start offset, $2 = death offset (-1: none) — one monitor process, start to death / fence / horizon
  (
    set +e
    load_seam "$PRIMARY"
    region=$(extract_region "$PRIMARY" '^while \$_running; do' '^done$') || { echo "hinst: region EMPTY" >> "$EV"; exit 3; }
    eval "run_loop() {
$region
}"
    _now() { local x; read -r x < "$CLK"; echo "$x"; }
    _adv() { local x; read -r x < "$CLK"; echo $(( x + $1 )) > "$CLK"; }
    _t() { local x; read -r x < "$CLK"; echo $(( x - T0 )); }
    [[ $(_now) -lt $(( T0 + $1 )) ]] && echo $(( T0 + $1 )) > "$CLK"
    echo "instance-start t=$(_t)" >> "$EV"
    DIE="$2"
    # ── config (after the seam: its defaults are the shipped ones; these are the harness values) ──
    STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; VOTE_PUBKEY=V1
    LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
    CHECK_INTERVAL=${CI:-3}; TURBO_INTERVAL=1; _current_interval=$CHECK_INTERVAL; STARTUP_GRACE=${GRACE:-30}
    DRY_RUN=false; RECOVERY_MODE=manual; PRIMARY_SELF_FENCE=true
    SOLANA_PATH="$W/bin"; LEDGER_PATH=/x; VALIDATOR_TYPE=agave
    STAKED_KEYPAIR="$W/staked.json"; UNSTAKED_KEYPAIR="$W/unstaked.json"
    STATE_DIR="$W/state"; STATE_FILE="$W/state/state-primary"; _DEFAULT_STATE_FILE="$W/none"
    FENCE_MARKER_DIR="$W/markers"; HEARTBEAT_INTERVAL=999999; HEARTBEAT_URL=""; ALERT_THROTTLE=600
    unset NOTIFY_SOCKET WATCHDOG_USEC
    # ── clock + sinks ──
    mono_now() { _now; }
    date() { if [[ "$1" == "+%s" ]]; then _now; return 0; fi; command date "$@"; }
    boot_id() { echo boot-A; }
    log() { :; }; log_info() { :; }; log_error() { case "$*" in *"[self-fence]"*|*HARD*) echo "sfe t=$(_t) ${*:0:170}" >> "$EV" ;; esac; }
    log_warn() { case "$*" in *">>> SWITCHING TO UNSTAKED"*|*"[self-fence]"*) echo "sfw t=$(_t) ${*:0:170}" >> "$EV" ;; esac; }
    alert() { :; }; alert_info() { :; }; alert_warn() { :; }; send_telegram() { :; }; send_webhook() { :; }
    rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _fence_rot_check() { :; }
    flush_pending_alerts() { :; }; _sd_notify() { :; }
    display_status() { echo "cycle t=$(_t) status=$1" >> "$EV"; }
    check_internet() { return 0; }
    detect_ledger_path() { :; }; detect_tower_base() { :; }; get_validator_args() { echo ""; }
    validate_keypair_file() { case "$1" in *unstaked*) echo U1 ;; *) echo S1 ;; esac; }
    _enforce_one_arm_state() { :; }; _rot_capture_intent() { :; }
    get_local_identity() {
        if [[ "${MODE:-none}" == "fullwedge" && $(_t) -gt 0 ]]; then _adv 8; return 0; fi   # admin socket wedged: contact-info times out at 8
        if [[ -n "${SLOWADMIN:-}" && $(_t) -gt 0 ]]; then if [[ $SLOWADMIN -ge 8 ]]; then _adv 8; return 0; fi; _adv "$SLOWADMIN"; fi   # a SLOW admin socket (answers in SLOWADMIN s; contact-info's own bound is 8)
        cat "$IDF"
    }
    _validator_pid() { [[ -e "$W/stopped" ]] && return 0; echo 4242; }
    kill() {   # the hard stop's direct kill: SIGKILL always stops it; SIGTERM only when the validator is not ignoring it (STOPHANG without TERMOK)
        if [[ "$1" == "-9" ]]; then echo "FENCE t=$(_t) kind=sigkill" >> "$EV"; : > "$W/stopped"; return 0; fi
        if [[ ( "${STOPHANG:-0}" != "1" || "${TERMOK:-0}" == "1" ) && "$1" =~ ^[0-9]+$ ]]; then echo "FENCE t=$(_t) kind=sigterm" >> "$EV"; : > "$W/stopped"; fi
        return 0
    }
    timeout() {
        # fix round 4 (the delta panel 3's TS3-D6-KBOUND): the daemon's OWN -k value is parsed and used — a call that needs
        # its kill (the *K knobs) takes bound + that value; with NO -k, timeout never kills a child that ignores SIGTERM, so the
        # call never returns (the clock jumps past any horizon: the row goes red) — a changed or dropped -k in the daemon moves
        # or reddens every row that needs the kill (red first on the panel's K1/K2/K3b).
        local kk="" bound
        [[ "$1" == "-k" ]] && { kk="$2"; shift 2; }
        bound="$1"; shift
        _tkill() {   # $1 = the event prefix + op — the kill path of a call that ignores SIGTERM
            if [[ -n "$kk" ]]; then _adv $(( bound + kk )); echo "$1 SIGKILLed at bound+$kk t=$(_t)" >> "$EV"
            else _adv 100000; echo "$1 NEVER killed (no -k) t=$(_t)" >> "$EV"; fi
        }
        case "$*" in
            *"authorized-voter remove-all"*)
                if [[ "${WEDGE:-0}" == "1" ]]; then
                    if [[ "${WEDGEK:-0}" == "1" ]]; then _tkill "wedge remove-all"; return 137; fi
                    _adv "$bound"; echo "wedge t=$(_t) remove-all timed out" >> "$EV"; return 124
                fi
                # fix round 2 (S4 — CK-1): remove-all ANSWERS, slowly (the set-identity-hang wedge order below). RASECS=max (fix round 4,
                # TS3-D6-KBOUND): its LATEST whole-second answer inside its bound, derived from the seam's SETIDENTITY_TIMEOUT — the answer
                # time, the admin socket's latency (SLOWADMIN, added below) included, is SETIDENTITY_TIMEOUT − 1 (14 s at the default)
                if [[ "${RASECS:-}" == "max" ]]; then _adv $(( SETIDENTITY_TIMEOUT - 1 - ${SLOWADMIN:-0} ))
                elif [[ -n "${RASECS:-}" ]]; then _adv "$RASECS"; fi
                [[ -n "${SLOWADMIN:-}" ]] && _adv "$SLOWADMIN"
                return 0 ;;
            *" set-identity $UNSTAKED_KEYPAIR"*)
                if [[ "${SIWEDGE:-0}" == "1" ]]; then   # fix round 2 (S4 — CK-1): the demote's SECOND admin call hangs (the other wedge order)
                    if [[ "${SIWEDGEK:-0}" == "1" ]]; then _tkill "wedge set-identity"; return 137; fi
                    _adv "$bound"; echo "wedge t=$(_t) set-identity timed out" >> "$EV"; return 124
                fi
                [[ -n "${SLOWADMIN:-}" ]] && _adv "$SLOWADMIN"; echo "FENCE t=$(_t) kind=demote" >> "$EV"; echo U1 > "$IDF"; return 0 ;;
            *"systemctl stop"*)
                if [[ "${STOPHANG:-0}" == "1" ]]; then
                    if [[ "${STOPK:-0}" == "1" ]]; then _tkill "stophang systemctl stop client"; return 137; fi
                    _adv "$bound"; echo "stophang t=$(_t) systemctl stop client timed out" >> "$EV"; return 124
                fi
                _adv "${STOPSECS:-0}"; echo "FENCE t=$(_t) kind=hardstop" >> "$EV"; : > "$W/stopped"; return 0 ;;
            *"systemctl mask"*)   # fix round 2 (S4 — CK-1): the hard stop masks the unit after a failed stop, BEFORE the kill
                if [[ "${MASKHANG:-0}" == "1" ]]; then
                    if [[ "${MASKK:-0}" == "1" ]]; then _tkill "maskhang systemctl mask"; return 137; fi
                    _adv "$bound"; echo "maskhang t=$(_t) systemctl mask timed out" >> "$EV"; return 124
                fi
                _adv "${MASKSECS:-0}"; return 0 ;;
        esac
        "$@"
    }
    sleep() {
        local s="${1%%.*}"; case "$s" in ''|*[!0-9]*) s=0 ;; esac
        _adv "$s"
        local t; t=$(_t)
        if [[ $t -ge ${HORIZON:-200} ]] || grep -q '^FENCE' "$EV" || { [[ $DIE -ge 0 && $t -ge $DIE ]]; }; then _running=false; fi
        return 0
    }
    # ── the holder's LOCAL node (t0 = 0 = its last landed vote) and the tiers ──
    _SN=${RATE_N:-5}; _SD=${RATE_D:-2}; _FL=$(( (32 * _SD + _SN - 1) / _SN ))
    _slot() { echo $(( HEAD0 + $1 * _SN / _SD )); }
    curl() {
        local url="" d="" mt=10 src t te m comm own oth bank vf
        while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; -m) mt="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac; done
        case "$url" in "$LOCAL_RPC") src=LOCAL ;; "$TIER2_RPC") src=T2 ;; "$TIER3_RPC") src=T3 ;; *) src=OTHER ;; esac
        case "$d" in *getHealth*) m=getHealth ;; *getVoteAccounts*) m=getVoteAccounts ;; *getSlot*) m=getSlot ;; *getClusterNodes*) m=getClusterNodes ;; *) m=other ;; esac
        comm=finalized; case "$d" in *'"commitment":"processed"'*) comm=processed ;; *'"commitment":"confirmed"'*) comm=confirmed ;; esac
        t=$(_t)
        echo "read $src $m $comm t=$t" >> "$EV"
        if [[ "$src" != "LOCAL" ]]; then
            if [[ "${TMODE:-refuse}" == "hang" ]]; then _adv "$mt"; return 28; fi
            return 7
        fi
        local mode="${MODE:-none}"; [[ $t -le 0 ]] && mode=none
        case "$mode" in
            deadrefuse|fullwedge) return 7 ;;
            deadhang) _adv "$mt"; return 28 ;;
        esac
        if [[ "${SLOWLOCAL:-}" == "b" && $t -gt 0 ]]; then   # fix round 2 (S4 — CK-3): every LOCAL read answers 1 s inside ITS OWN -m bound
            _adv $(( mt - 1 )); t=$(_t)
        elif [[ -n "${SLOWLOCAL:-}" && ${SLOWLOCAL:-0} -gt 0 && $t -gt 0 ]]; then
            if [[ $SLOWLOCAL -ge $mt ]]; then _adv "$mt"; return 28; fi
            _adv "$SLOWLOCAL"; t=$(_t)
        fi
        te=$t
        case "$mode" in frozen|garbage) [[ $te -gt 0 ]] && te=0 ;; esac
        own=$(( $(_slot "$te") - 1 )); oth=$own
        case "$mode" in egress) own=$(( $(_slot 0) - 1 )) ;; esac
        case "$m" in
            getSlot)
                if [[ "$mode" == "garbage" && "$comm" == "confirmed" ]]; then printf '{"jsonrpc":"2.0","result":"abc","id":1}'; return 0; fi
                case "$comm" in
                    confirmed) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(( $(_slot "$te") - 2 ))" ;;
                    processed) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(_slot "$te")" ;;
                    *) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(( $(_slot "$te") - 32 ))" ;;
                esac ;;
            getVoteAccounts)
                if [[ "$comm" == "processed" || "$comm" == "confirmed" ]]; then
                    printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s},{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]},"id":1}' "$oth" "$own"
                else
                    bank=$(( $(_slot "$te") - 32 ))
                    local tf=$(( te - _FL )); vf=$(( $(_slot "$tf") - 1 ))
                    [[ "$mode" == "egress" && $tf -gt 0 ]] && vf=$(( $(_slot 0) - 1 ))
                    if [[ $vf -lt $(( bank - 128 )) ]]; then
                        printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]},"id":1}' "$(( bank - 1 ))" "$vf"
                    else
                        printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s},{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]},"id":1}' "$(( bank - 1 ))" "$vf"
                    fi
                fi ;;
            getHealth)
                if [[ "$mode" == "frozen" && "${HEALTHBEHIND:-0}" == "1" && $t -gt 0 ]]; then
                    local nb=$(( $(_slot "$t") - $(_slot 0) ))
                    if [[ $nb -gt 128 ]]; then printf '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by %s slots","data":{"numSlotsBehind":%s}},"id":1}' "$nb" "$nb"; return 0; fi
                fi
                printf '{"jsonrpc":"2.0","result":"ok","id":1}' ;;
            getClusterNodes) printf '{"jsonrpc":"2.0","result":[{"pubkey":"S1","gossip":"1.2.3.4:8001"}],"id":1}' ;;
            *) return 7 ;;
        esac
        return 0
    }
    _running=true
    startup_checks >/dev/null 2>&1
    echo "startup-done t=$(_t) running=$_running lcs=${_last_confirmed_slot:-} rp=${_selffence_restore_pending:-0} nrp=${_selffence_noanswer_restore_pending:-0} vrp=${_selffence_votelag_restore_pending:-0}" >> "$EV"
    if [[ "$_running" == "true" ]]; then ( run_loop ) >/dev/null 2>"$W/loop.err.$1"; fi
    echo "instance-end t=$(_t)" >> "$EV"
  )
}

hworld() {
  (
    W=$(mktemp -d "$WORK/w.XXXXXX"); EV="$W/ev"; : > "$EV"; IDF="$W/id"; echo S1 > "$IDF"; CLK="$W/clk"
    mkdir -p "$W/bin" "$W/state" "$W/markers"; : > "$W/bin/agave-validator"; : > "$W/bin/solana-keygen"; chmod +x "$W/bin/"*
    printf '[1]' > "$W/staked.json"; printf '[2]' > "$W/unstaked.json"
    echo $(( T0 - 1000 )) > "$CLK"
    local i=0 spec st dd; INST="${INST:--100:-1}"
    for spec in ${INST//,/ }; do
        i=$((i + 1)); st=${spec%%:*}; dd=${spec##*:}
        if [[ $i -eq 2 && -n "${CORRUPT:-}" && -f "$W/state/state-primary" ]]; then sed -i.bak "$CORRUPT" "$W/state/state-primary"; echo "corrupted: $(grep '^SF_LAST_CONFIRMED_SLOT=\|^SF_ADVANCE_MONO=' "$W/state/state-primary" | tr '\n' ' ')" >> "$EV"; fi
        grep -q '^FENCE' "$EV" && break
        hinst "$st" "$dd"
    done
    local fence kind
    fence=$(grep -m1 '^FENCE' "$EV" | sed 's/^FENCE t=\([-0-9]*\).*/\1/'); kind=$(grep -m1 '^FENCE' "$EV" | sed 's/.*kind=//')
    local why; why=$(grep '^sfw' "$EV" | grep -m1 'switch to unstaked\|SWITCHING' | cut -c1-150)
    echo "fence=${fence:-never}|kind=${kind:-none}|why=${why}|starts=$(grep -c '^instance-start' "$EV")|cycles=$(grep -c '^cycle' "$EV")"
    [[ -n "${KEEPEV:-}" ]] && cp "$EV" "$KEEPEV"
    rm -rf "$W"
  )
}

PAR=${D6_PAR:-8}
hlaunch() {   # hlaunch <name> VAR=val … — one holder world in the background (at most PAR at once) → $WORK/r.<name>
    local n="$1"; shift
    while [[ $(jobs -rp | wc -l) -ge $PAR ]]; do command sleep 0.2; done
    ( for kv in "$@"; do export "$kv"; done; hworld 2>/dev/null | tail -1 > "$WORK/r.$n" ) &
}
hf() { local r; r=$(cat "$WORK/r.$1" 2>/dev/null); field "$r" fence; }
# span <prefix> <n> — "min-max" of the fences of <prefix>0 .. <prefix>(n-1) ("never" if every one is never;
# "MIXED" if some are and some are not)
span() {
    local p="$1" n="$2" i l=""
    for ((i = 0; i < n; i++)); do l="$l $i"; done
    # shellcheck disable=SC2086
    spans "$p" $l
}
# spans <prefix> <suffix…> — the same over <prefix><suffix> for each suffix (the phase-swept rows' offsets)
spans() {
    local p="$1" x v lo="" hi="" nv=0 n=0; shift
    for x in "$@"; do
        n=$((n + 1)); v=$(hf "$p$x")
        if [[ "$v" == "never" ]]; then nv=$((nv + 1)); continue; fi
        [[ "$v" =~ ^[0-9]+$ ]] || { echo "ERR($p$x='$v')"; return 0; }
        [[ -z "$lo" || $v -lt $lo ]] && lo=$v; [[ -z "$hi" || $v -gt $hi ]] && hi=$v
    done
    if [[ $nv -eq $n ]]; then echo never; elif [[ $nv -gt 0 ]]; then echo MIXED; elif [[ "$lo" == "$hi" ]]; then echo "$lo"; else echo "$lo-$hi"; fi
}
# ── the collision check's 60 s phase (fix round 2, S4 — the delta panel's T1-D6) ──────────────────────────
# The collision check runs every COLLISION_CHECK_INTERVAL (60 s) on the daemon's own schedule, so a row whose
# I/O includes a SLOW collision-check read (the tiers at their -m bounds, slow or dead LOCAL reads — the rows
# marked "phase-swept" below) fences at a time that depends on WHERE in that period the failure lands: its
# reads can delay the first read that sees the failure by up to ~25 s. Such a row is run over the phase:
#   D6_SWEEP=full   EVERY start offset -100..-159 (one full period; the first instance's start sets the phase)
#                   for every phase-swept row and cadence — N-is-all; ~1,700 worlds, minutes, not the gate's run
#   default         the read-phase set (-100 .. -100-(CI-1)) plus, per row and cadence, the full sweep's WORST
#                   offset and its two neighbours and its BEST offset (pinned below from a D6_SWEEP=full run) —
#                   so the pinned min–max is the full sweep's; a drift of the worst phase or of its value goes
#                   red; a NEW worst elsewhere in the period needs D6_SWEEP=full (run it after any change to the
#                   loop's schedule or its reads)
D6_SWEEP=${D6_SWEEP:-pinned}
phase_set() {   # phase_set <CI> <worst offset> <best offset> — the start offsets (positive) a phase-swept row runs at
    local ci="$1" w="$2" b="$3" o out=""
    if [[ "$D6_SWEEP" == "full" ]]; then for ((o = 100; o <= 159; o++)); do out="$out $o"; done; echo "$out"; return 0; fi
    for ((o = 100; o < 100 + ci; o++)); do out="$out $o"; done
    for o in "$b" $((w - 1)) "$w" $((w + 1)); do
        o=$(( (o - 100 + 60) % 60 + 100 ))   # one period: -99 is -159's phase
        [[ " $out " == *" $o "* ]] || out="$out $o"
    done
    echo "$out"
}
PH_ROWS=""   # "<name>|<CI>|<offsets>" per phase-swept row and cadence — spanp reads it back
# phlaunch <name> <CI> <worst> <best> <INST template, @ = the start offset> VAR=val … — a phase-swept row
phlaunch() {
    local n="$1" ci="$2" w="$3" b="$4" tmpl="$5" o offs; shift 5
    offs=$(phase_set "$ci" "$w" "$b")
    PH_ROWS="$PH_ROWS
${n}|${ci}|${offs}"
    for o in $offs; do hlaunch "${n}_${ci}_o$o" CI="$ci" "INST=${tmpl//@/-$o}" "$@"; done
}
spanp() {   # spanp <name> <CI> — the min-max of that phase-swept row over its offsets
    local l offs=""
    while IFS= read -r l; do [[ "${l%%|*}" == "$1" && "${l#*|}" == "$2|"* ]] && { offs="${l##*|}"; break; }; done <<EOF_PH
$PH_ROWS
EOF_PH
    local x sfx=""
    for x in $offs; do sfx="$sfx o$x"; done
    # shellcheck disable=SC2086
    spans "${1}_${2}_" $sfx
}
C_SLOT='CORRUPT=s/^SF_LAST_CONFIRMED_SLOT=.*/SF_LAST_CONFIRMED_SLOT=abc/'

# ── the worlds ─────────────────────────────────────────────────────────────────────────────────────────
for ci in 1 3 5; do
    for ((k = 0; k < ci; k++)); do
        st=$(( -100 - k ))
        hlaunch "dr_${ci}_$k"  MODE=deadrefuse CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "fz_${ci}_$k"  MODE=frozen CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "e25_${ci}_$k" MODE=egress CI=$ci RATE_N=5 RATE_D=2 INST=$st:-1 HORIZON=120
        hlaunch "e37_${ci}_$k" MODE=egress CI=$ci RATE_N=37 RATE_D=10 INST=$st:-1 HORIZON=120
        hlaunch "gb_${ci}_$k"  MODE=garbage CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "hb_${ci}_$k"  MODE=frozen HEALTHBEHIND=1 CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "fw_${ci}_$k"  MODE=fullwedge CI=$ci INST=$st:-1 HORIZON=300
        hlaunch "r1g0_30_${ci}_$k" MODE=frozen CI=$ci GRACE=0 INST=$st:25,30:-1 "$C_SLOT" HORIZON=260
        hlaunch "crash_${ci}_$k"  MODE=frozen CI=$ci INST=$st:$((29 + ci)),$((39 + ci)):-1 HORIZON=260
    done
done
for k in 0 1 2; do
    st=$(( -100 - k ))
    for R in 30 45 63; do
        hlaunch "r1g30_${R}_$k" MODE=frozen CI=3 GRACE=30 INST=$st:25,$R:-1 "$C_SLOT" HORIZON=260
        hlaunch "f1_${R}_$k"    MODE=frozen CI=3 GRACE=30 INST=$st:25,$R:-1 HORIZON=260
    done
    for R in 45 63; do hlaunch "r1g0_${R}_3_$k" MODE=frozen CI=3 GRACE=0 INST=$st:25,$R:-1 "$C_SLOT" HORIZON=260; done
done
# the phase-swept (a)/(b) rows (T1-D6): the worst / best start offset per cadence (or restart) from D6_SWEEP=full
phlaunch dh 1 128 100 "@:-1" MODE=deadhang HORIZON=120
phlaunch dh 3 126 101 "@:-1" MODE=deadhang HORIZON=120
phlaunch dh 5 120 104 "@:-1" MODE=deadhang HORIZON=120
phlaunch crashh 1 141 100 "@:30,40:-1" MODE=frozen TMODE=hang HORIZON=260
phlaunch crashh 3 145 135 "@:32,42:-1" MODE=frozen TMODE=hang HORIZON=260
phlaunch crashh 5 141 105 "@:34,44:-1" MODE=frozen TMODE=hang HORIZON=260
phlaunch f1h30 3 150 105 "@:25,30:-1" MODE=frozen GRACE=30 TMODE=hang HORIZON=260
phlaunch f1h45 3 150 100 "@:25,45:-1" MODE=frozen GRACE=30 TMODE=hang HORIZON=260
phlaunch f1h63 3 100 100 "@:25,63:-1" MODE=frozen GRACE=30 TMODE=hang HORIZON=260
# (1)'s restart member: a second restart 1 or 4 cycles into the first restarted instance, after a stop of 0 or 20 s
for R in 30 63; do
    i=0
    for cyc in 1 4; do for stop in 0 20; do for k in 0 1; do
        d2=$(( R + 30 + cyc * 3 ))
        hlaunch "rm${R}_$i" MODE=frozen CI=3 GRACE=30 INST=$(( -100 - k )):25,$R:$d2,$(( d2 + stop )):-1 "$C_SLOT" HORIZON=320
        i=$((i + 1))
    done; done; done
done
for ci in 3 5; do
    for ((k = 0; k < ci; k++)); do
        st=$(( -100 - k ))
        hlaunch "w_${ci}_$k"     MODE=frozen CI=$ci WEDGE=1 INST=$st:-1 HORIZON=200
        hlaunch "wk_${ci}_$k"    MODE=frozen CI=$ci WEDGE=1 WEDGEK=1 INST=$st:-1 HORIZON=200
        hlaunch "wkh_${ci}_$k"   MODE=frozen CI=$ci WEDGE=1 WEDGEK=1 STOPHANG=1 INST=$st:-1 HORIZON=200
        # fix round 2 (S4 — the delta panel's CK-1): the hard stop's `systemctl mask --runtime` (after the failed stop,
        # before the kill) and the other wedge order (remove-all answers, the set-identity to unstaked hangs)
        hlaunch "wm0_${ci}_$k"   MODE=frozen CI=$ci WEDGE=1 STOPHANG=1 MASKHANG=1 INST=$st:-1 HORIZON=200
        hlaunch "wkhm_${ci}_$k"  MODE=frozen CI=$ci WEDGE=1 WEDGEK=1 STOPHANG=1 MASKHANG=1 INST=$st:-1 HORIZON=200
        hlaunch "wkhmk_${ci}_$k" MODE=frozen CI=$ci WEDGE=1 WEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 INST=$st:-1 HORIZON=200
        hlaunch "wp_${ci}_$k"    MODE=frozen CI=$ci WEDGE=1 STOPHANG=1 MASKHANG=1 TERMOK=1 INST=$st:-1 HORIZON=200
        hlaunch "s7_${ci}_$k"    MODE=frozen CI=$ci RASECS=7 SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 INST=$st:-1 HORIZON=200
        hlaunch "s14_${ci}_$k"   MODE=frozen CI=$ci RASECS=max SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 INST=$st:-1 HORIZON=200
        hlaunch "s7m_${ci}_$k"   MODE=frozen CI=$ci RASECS=7 SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 MASKHANG=1 INST=$st:-1 HORIZON=200
        # fix round 3 (U4 — the delta panel 2's CKB-1): the other order with the stop and the mask at their -k bounds too,
        # remove-all answering after 14 s (SETIDENTITY_TIMEOUT − 1 — the latest answer on this integer clock; RASECS=max since
        # fix round 4 derives it from the seam's SETIDENTITY_TIMEOUT)
        hlaunch "s14k_${ci}_$k"  MODE=frozen CI=$ci RASECS=max SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 INST=$st:-1 HORIZON=200
    done
done
# the phase-swept (c) rows (T1-D6 — the tiers at their bounds, then every LOCAL read at 4 s): worst / best offsets
for ci in 3 5; do
    case $ci in 3) wT=113; bT=135; wL=138; bL=134 ;; 5) wT=111; bT=105; wL=111; bL=134 ;; esac
    phlaunch wkhT    $ci $wT $bT "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 TMODE=hang HORIZON=200
    phlaunch wkhTL   $ci $wL $bL "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 TMODE=hang SLOWLOCAL=4 HORIZON=260
    phlaunch wkhmT   $ci $wT $bT "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 MASKHANG=1 TMODE=hang HORIZON=260
    phlaunch wkhmTL  $ci $wL $bL "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 MASKHANG=1 TMODE=hang SLOWLOCAL=4 HORIZON=260
    phlaunch wkhmkT  $ci $wT $bT "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang HORIZON=260
    phlaunch wkhmkTL $ci $wL $bL "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang SLOWLOCAL=4 HORIZON=300
    # fix round 3 (U4 — CKB-1): the other wedge order with every op at its -k bound, in the same two slow-I/O forms (its
    # worst / best offsets are c4mk's / c5mk's: every value is theirs + 14 s — D6_SWEEP=full, fix round 3)
    phlaunch s14kT   $ci $wT $bT "@:-1" MODE=frozen RASECS=max SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang HORIZON=260
    phlaunch s14kTL  $ci $wL $bL "@:-1" MODE=frozen RASECS=max SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang SLOWLOCAL=4 HORIZON=300
    # fix round 4 (G2 — the delta panel 3's CC3-2): both wedge orders with every op at its -k bound, composed with the worst-case
    # column's OWN I/O mixes and with the admin socket's latency alone; worst / best offsets from D6_SWEEP=full (fix round 4)
    case $ci in 3) wD=113; bD=112; wB=113; bB=112; wA=100; bA=102 ;; 5) wD=111; bD=110; wB=111; bB=135; wA=101; bA=100 ;; esac
    phlaunch wkhmkA  $ci $wA $bA "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 SLOWADMIN=7 HORIZON=260
    phlaunch s14kA   $ci $wA $bA "@:-1" MODE=frozen RASECS=max SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 SLOWADMIN=7 HORIZON=260
    phlaunch wkhmkTb $ci $wB $bB "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang SLOWLOCAL=b HORIZON=320
    phlaunch s14kTb  $ci $wB $bB "@:-1" MODE=frozen RASECS=max SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang SLOWLOCAL=b HORIZON=320
    phlaunch wkhmkD  $ci $wD $bD "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 HORIZON=320
    phlaunch s14kD   $ci $wD $bD "@:-1" MODE=frozen RASECS=max SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 HORIZON=320
    phlaunch wkhmkDb $ci $wD $bD "@:-1" MODE=frozen WEDGE=1 WEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang SLOWADMIN=7 SLOWLOCAL=b HORIZON=320
    phlaunch s14kDb  $ci $wD $bD "@:-1" MODE=frozen RASECS=max SIWEDGE=1 SIWEDGEK=1 STOPHANG=1 STOPK=1 MASKHANG=1 MASKK=1 TMODE=hang SLOWADMIN=7 SLOWLOCAL=b HORIZON=320
done
# (d) — every row phase-swept (T1-D6; before fix round 2: 8 offsets 10 s apart, which missed the worst of four of the seven
# rows — frozen, dead-refusing, dead-at-bound, tiers-only; garbage and both N6 rows already had theirs: the delta panel 2's CKB-7)
phlaunch iofz  3 113 112 "@:-1" MODE=frozen TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 HORIZON=200
phlaunch iodr  3 112 102 "@:-1" MODE=deadrefuse TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 HORIZON=200
phlaunch iodh  3 112 102 "@:-1" MODE=deadhang TMODE=hang SLOWADMIN=7 HORIZON=200
phlaunch iogb  3 100 134 "@:-1" MODE=garbage TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 HORIZON=200
phlaunch ioe25 3 100 134 "@:-1" MODE=egress RATE_N=5 RATE_D=2 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 HORIZON=200
phlaunch ioe37 3 100 134 "@:-1" MODE=egress RATE_N=37 RATE_D=10 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 HORIZON=200
phlaunch iot   3 113 135 "@:-1" MODE=frozen TMODE=hang HORIZON=200
# (d′) the SECOND I/O mix (fix round 2, S4 — the delta panel's CK-3 b): every LOCAL read 1 s inside ITS OWN -m bound
phlaunch bfz   3 113 112 "@:-1" MODE=frozen TMODE=hang SLOWADMIN=7 SLOWLOCAL=b HORIZON=260
phlaunch bdr   3 112 102 "@:-1" MODE=deadrefuse TMODE=hang SLOWADMIN=7 SLOWLOCAL=b HORIZON=260
phlaunch bgb   3 100 134 "@:-1" MODE=garbage TMODE=hang SLOWADMIN=7 SLOWLOCAL=b HORIZON=260
phlaunch be25  3 112 134 "@:-1" MODE=egress RATE_N=5 RATE_D=2 TMODE=hang SLOWADMIN=7 SLOWLOCAL=b HORIZON=260
phlaunch be37  3 112 134 "@:-1" MODE=egress RATE_N=37 RATE_D=10 TMODE=hang SLOWADMIN=7 SLOWLOCAL=b HORIZON=260
wait

# The spare's EARLIEST take / mint the rows are held against (the minimum over read phase and CHECK_INTERVAL
# 1 / 3 / 5 — pinned in test_own_view (6)): un-armed MAX_DELINQUENT_SLOTS=15 73 s (3.7 slots/s) / 79 s (2.5);
# =0 104 s / 125 s; the armed watchdog-elapsed MINT 119 s / 150 s at 3.7, 125 s / 170 s at 2.525 (at exactly 2.5 none
# on a SMOOTH head — an anchor hold mints at 126 / 171 s: docs/SAFETY.md 'Slot time', the slow-cluster residual).
SP15=73; SP15B=79; SP0=104; SP0B=125; MINT15=119; MINT0=150
xnote() {   # xnote <worst fence> — the crossings a holder fence at <worst> makes against the spare columns
    local w="$1" o=""
    [[ "$w" == "never" ]] && { echo "CROSSES every spare column (never fenced)"; return 0; }
    [[ $w -ge $SP15 ]] && o="$o ${SP15}s-spare(+$((w - SP15)))"
    [[ $w -ge $SP15B ]] && o="$o ${SP15B}s(+$((w - SP15B)))"
    [[ $w -ge $SP0 ]] && o="$o ${SP0}s(+$((w - SP0)))"
    [[ $w -ge $SP0B ]] && o="$o ${SP0B}s(+$((w - SP0B)))"
    [[ $w -ge $MINT15 ]] && o="$o mint${MINT15}s(+$((w - MINT15)))"
    [[ $w -ge $MINT0 ]] && o="$o mint${MINT0}s(+$((w - MINT0)))"
    if [[ -z "$o" ]]; then echo "holds (margin $((SP15 - w)) s against the fastest spare)"; else echo "CROSSES:$o"; fi
}
row() {   # row <id> <label> <want…> — compare "<cadence spans>" with the pinned value; ok/bad
    local id="$1" label="$2" want="$3" got="$4" worst="$5"
    if [[ "$got" == "$want" ]]; then ok "($id) $label: $got s — worst $worst s: $(xnote "$worst")"; else bad "($id) $label: got '$got', pinned '$want'"; fi
}

# ── (a) prompt I/O ─────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (a) the holder's fence from its last landed vote, prompt I/O, CHECK_INTERVAL 1 / 3 / 5 over every read phase ───"
g() { printf '%s / %s / %s' "$(span "${1}_1_" 1)" "$(span "${1}_3_" 3)" "$(span "${1}_5_" 5)"; }
gp() { printf '%s / %s / %s' "$(spanp "$1" 1)" "$(spanp "$1" 3)" "$(spanp "$1" 5)"; }   # a phase-swept row
row a1 "dead local RPC, refusing (the no-answer clock; admin socket answering)" "31 / 31-33 / 31-35" "$(g dr)" 35
row a2 "dead local RPC, every LOCAL read at its -m bound (phase-swept — the collision check's LOCAL read at its bound too; before fix round 2 pinned at the read phases only: 38 / 42-44 / 46-50)" "38-43 / 42-49 / 46-55" "$(gp dh)" 55
row a3 "frozen slot (the frozen clock)" "30 / 30-32 / 30-34" "$(g fz)" 34
row a4 "egress-only at 2.5 slots/s (N6: SELF_FENCE_VOTE_LAG_SLOTS / rate to cross the 32-slot lag, then its 20 s clock)" "34 / 35-37 / 34-38" "$(g e25)" 38
row a5 "egress-only at 3.7 slots/s (N6)" "29 / 30-32 / 29-33" "$(g e37)" 33
row a6 "garbage answers (a non-canonical slot)" "30 / 28-30 / 26-30" "$(g gb)" 30
if [[ "$(g hb)" == "$(g fz)" ]]; then
    ok "(a7) F9 — getHealth reporting behind (a minority-gossip partition: the blockstore still sees the cluster) fences exactly as the frozen clock ($(g hb) s): its own path (SELF_FENCE_MAX_BEHIND, 150 slots past agave's 128) needs ~60 s at 2.5 slots/s, so it is never the later one — not a crossing; the internet-lost demote (CONNECTIVITY_RETRIES failed rounds) likewise fires no later than these rows (by reading: the harness stubs check_internet)"
else
    bad "(a7) getHealth-behind $(g hb) ≠ frozen $(g fz)"
fi
if [[ "$(g fw)" == "never / never / never" ]]; then
    ok "(a8) F5 — a FULLY WEDGED validator (admin socket unreadable: contact-info at its 8 s bound) with the monitor RUNNING: never fenced at any cadence or phase (horizon 300 s) — the loop takes the unreachable path, pages, never evaluates the self-fence; armed, its pets continue (by reading: the gap is ~8 s + CHECK_INTERVAL, under WatchdogSec 30), so OnFailure never fires either — a CROSSING of every spare column, armed or not"
else
    bad "(a8) fully wedged: $(g fw)"
fi

# ── (b) the restarts ───────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (b) the restarts: row (1)'s corrupted restore, the plain restart (F1), the un-armed crash, (1)'s restart member ───"
row b1 "row (1): a corrupted slot restored, restart +30 / +45 / +63, STARTUP_GRACE 30 (CHECK_INTERVAL 3, every phase)" "75 / 90 / 108" "$(span r1g30_30_ 3) / $(span r1g30_45_ 3) / $(span r1g30_63_ 3)" 108
row b2 "row (1), grace 0: restart +30 at CHECK_INTERVAL 1 / 3 / 5 (F7: 45 only when the persisted stall stamp is >= 30 s old at the restore, else 60)" "45 / 45-60 / 45-60" "$(span r1g0_30_1_ 1) / $(span r1g0_30_3_ 3) / $(span r1g0_30_5_ 5)" 60
row b3 "row (1), grace 0: restart +45 / +63 (CHECK_INTERVAL 3)" "60 / 78" "$(span r1g0_45_3_ 3) / $(span r1g0_63_3_ 3)" 78
row b4 "F1 — the PLAIN restart with a CANONICAL state file, +30 / +45 / +63 (the startup blind window: restart + the tier tests + STARTUP_GRACE)" "60 / 75 / 93" "$(span f1_30_ 3) / $(span f1_45_ 3) / $(span f1_63_ 3)" 93
row b5 "F1 with the startup tier tests at their -m bounds, +30 / +45 / +63 (phase-swept; at the read phases only: 83-85 / 95 / 113)" "80-97 / 95-97 / 113" "$(spanp f1h30 3) / $(spanp f1h45 3) / $(spanp f1h63 3)" 113
row b6 "F1 — the un-armed unit's own crash (Restart=always, RestartSec 10) 1 s before the fence would land, CHECK_INTERVAL 1 / 3 / 5 (the phases whose fence lands before the crash: 30–31)" "70 / 30-72 / 30-74" "$(g crash)" 74
row b7 "F1 — the same crash (at 29 + CHECK_INTERVAL s) with the tier tests at their bounds (phase-swept; at the read phases only: 90 / 92 / 31-94)" "90-100 / 30-102 / 30-104" "$(gp crashh)" 104
row b8 "(1)'s restart member: a second restart 1 or 4 cycles into the first restarted instance after a 0 or 20 s stop — first restart +30 / +63" "93-122 / 126-155" "$(span rm30_ 8) / $(span rm63_ 8)" 155

# ── (c) the wedged demote → hard stop (F3; fix round 2 S4 — the delta panel's CK-1) ─────────────────────
echo ""; echo "─── (c) F3/CK-1: the wedged demote → the hard stop, every daemon term; CHECK_INTERVAL 3 / 5 over every phase ───"
# The stop lands at: trigger + the demote (remove-all to SETIDENTITY_TIMEOUT, + its -k 5; or remove-all ANSWERING after
# r s and then the set-identity to unstaked to SETIDENTITY_TIMEOUT, + 5) + `systemctl stop` (15 s, + 5) + — only after a
# FAILED stop — `systemctl mask --runtime` (15 s, + 5) + SIGTERM, 2 s, SIGKILL. SETIDENTITY_TIMEOUT = 15 (the default;
# the daemon lower-bounds it at 8 and sets no upper bound — a larger value moves every fixed-r cell below by the
# difference, and the other order's LATEST (r up to SETIDENTITY_TIMEOUT − 1) by TWICE the difference: the timeout
# bounds both r and the set-identity after it — the delta panel 2's CKB-1). Its maximum at the default, every op at
# its -k bound: trigger + 14 + 20 + 20 + 20 + 2 = 76 s after the trigger (c3h), 14 s later than the first order's (c3c).
g35() { printf '%s / %s' "$(span "${1}_3_" 3)" "$(span "${1}_5_" 5)"; }
g35p() { printf '%s / %s' "$(spanp "$1" 3)" "$(spanp "$1" 5)"; }   # a phase-swept row
row c1 "remove-all at its 15 s bound, a prompt systemctl stop" "45-47 / 45-49" "$(g35 w)" 49
row c2 "… and the CLI needs its -k 5 (bound + 5)" "50-52 / 50-54" "$(g35 wk)" 54
row c3 "… and the systemctl stop client times out (15 s) with the validator ignoring SIGTERM (the daemon's SIGKILL, + 2 s) — a PROMPT mask" "67-69 / 67-71" "$(g35 wkh)" 71
row c3a "remove-all at its plain 15 s bound, the stop client AND the mask each at their 15 s bounds, SIGTERM ignored" "77-79 / 77-81" "$(g35 wm0)" 81
row c3b "c3 with the mask at its 15 s bound (fix round 1's row modelled the mask instant)" "82-84 / 82-86" "$(g35 wkhm)" 86
row c3c "every op at its -k bound (remove-all, stop, mask: each 15 + 5 s), SIGTERM ignored" "92-94 / 92-96" "$(g35 wkhmk)" 96
row c3d "PID 1 slow: the stop and the mask each at their 15 s bounds, the validator HONOURING the daemon's SIGTERM (remove-all at its plain bound)" "75-77 / 75-79" "$(g35 wp)" 79
row c3e "the OTHER wedge order: remove-all ANSWERS in 7 s (the worst-case column's admin latency), then the set-identity to unstaked hangs to its bound + 5; the stop client times out, SIGTERM ignored, a prompt mask" "74-76 / 74-78" "$(g35 s7)" 78
row c3f "… remove-all answering in 14 s" "81-83 / 81-85" "$(g35 s14)" 85
row c3g "… remove-all in 7 s and the mask at its 15 s bound" "89-91 / 89-93" "$(g35 s7m)" 93
row c3h "the other wedge order with EVERY op at its -k bound: remove-all answering in 14 s (SETIDENTITY_TIMEOUT − 1), the set-identity, the stop and the mask each at 15 + 5 s, SIGTERM ignored — the row's latest at prompt RPC I/O with a prompt admin socket (c3j: the admin socket at 7 s) (fix round 3, the delta panel 2's CKB-1)" "106-108 / 106-110" "$(g35 s14k)" 110
row c4 "c3 + the tiers at their -m bounds (the collision check's reads; phase-swept — at the read phases only: 70-72 / 68-72)" "67-89 / 67-91" "$(g35p wkhT)" 91
row c4m "c4 + the mask at its bound" "82-104 / 82-106" "$(g35p wkhmT)" 106
row c4mk "c4 with every op at its -k bound" "92-114 / 92-116" "$(g35p wkhmkT)" 116
row c5 "c4 + every LOCAL read at 4 s (phase-swept — at the read phases only: 85-87 / 87-91)" "80-106 / 84-135" "$(g35p wkhTL)" 135
row c5m "c5 + the mask at its bound" "95-121 / 99-150" "$(g35p wkhmTL)" 150
row c5mk "c5 with every op at its -k bound" "105-131 / 109-160" "$(g35p wkhmkTL)" 160
row c4h "c3h + the tiers at their -m bounds (phase-swept)" "106-128 / 106-130" "$(g35p s14kT)" 130
row c5h "c3h + the tiers at their bounds + every LOCAL read at 4 s (phase-swept)" "119-145 / 123-174" "$(g35p s14kTL)" 174
# fix round 4 (G2 — the delta panel 3's CC3-2): the row composed with the admin socket at 7 s alone and with the worst-case column's own
# I/O mixes, (d) and (d′) — both orders with every op at its -k bound, phase-swept; the latest over the measured mixes is c6h's 195 s:
row c3i "c3c with ONLY the admin socket at 7 s (the tiers and every LOCAL read prompt)" "92-101 / 98-109" "$(g35p wkhmkA)" 109
row c3j "c3h with ONLY the admin socket at 7 s (remove-all answering in 14 s, its 7 s latency included)" "106-115 / 112-123" "$(g35p s14kA)" 123
row c5b "c4mk + every LOCAL read 1 s inside its own -m bound (a prompt admin socket)" "98-169 / 97-175" "$(g35p wkhmkTb)" 175
row c5bh "c4h + every LOCAL read 1 s inside its own -m bound (a prompt admin socket)" "112-183 / 111-189" "$(g35p s14kTb)" 189
row c6 "the (d) mix — the tiers at their bounds, the admin socket at 7 s, every LOCAL read at 4 s — with c3c's ops" "100-175 / 102-181" "$(g35p wkhmkD)" 181
row c6h "the (d) mix with c3h's ops (remove-all answering in 14 s, its 7 s admin latency included) — the row's latest over the measured mixes" "114-189 / 116-195" "$(g35p s14kD)" 195
row "c6′" "the (d′) mix — the tiers at their bounds, the admin socket at 7 s, every LOCAL read 1 s inside its own -m bound — with c3c's ops" "105-135 / 107-139" "$(g35p wkhmkDb)" 139
row "c6′h" "the (d′) mix with c3h's ops" "119-149 / 121-153" "$(g35p s14kDb)" 153

# ── (d) the worst-case I/O column (F4; fix round 2 S4 — T1-D6: every row phase-swept) ──────────────────
echo ""; echo "─── (d) F4: the worst-case I/O column — CHECK_INTERVAL 3, the tiers at their bounds, the admin socket at 7 s, LOCAL reads at 4 s, over the collision check's 60 s phase ───"
row d1 "frozen slot (before fix round 2, 8 offsets: 76-120)" "52-127" "$(spanp iofz 3)" 127
row d2 "dead local RPC, refusing (8 offsets: 52-66)" "52-74" "$(spanp iodr 3)" 74
row d3 "dead local RPC, every LOCAL read at its bound (admin 7 s, tiers at their bounds; 8 offsets: 57-106)" "57-114" "$(spanp iodh 3)" 114
row d4 "garbage answers (8 offsets: 34-78)" "26-78" "$(spanp iogb 3)" 78
row d5 "egress-only at 2.5 slots/s (N6)" "60-86" "$(spanp ioe25 3)" 86
row d6 "egress-only at 3.7 slots/s (N6)" "60-84" "$(spanp ioe37 3)" 84
row d7 "frozen slot, the tiers at their bounds ONLY (prompt LOCAL and admin; 8 offsets: 31-47)" "30-52" "$(spanp iot 3)" 52
echo ""; echo "─── (d′) CK-3: the second I/O mix — every LOCAL read 1 s inside its OWN -m bound (the -m 10 reads at 9 s), admin 7 s, tiers at their bounds, phase-swept ───"
row "d′1" "frozen slot (non-monotonic in latency: a slower LOCAL read can reach the frozen read sooner)" "57-87" "$(spanp bfz 3)" 87
row "d′2" "dead local RPC, refusing" "52-74" "$(spanp bdr 3)" 74
row "d′3" "garbage answers" "26-83" "$(spanp bgb 3)" 83
row "d′4" "egress-only at 2.5 slots/s (N6)" "65-96" "$(spanp be25 3)" 96
row "d′5" "egress-only at 3.7 slots/s (N6)" "65-94" "$(spanp be37 3)" 94

rm -rf "$WORK"
results_banner
