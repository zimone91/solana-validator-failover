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
#   SLOWLOCAL <s>: every LOCAL JSON-RPC read answers <s> s late (below its -m bound: still an answer)
#   SLOWADMIN <s>: the admin socket answers in <s> s (contact-info's own bound is 8)
#   WEDGE=1  the demote's `authorized-voter remove-all` hangs to its SETIDENTITY_TIMEOUT (→ the hard stop); WEDGEK=1 it
#            needs its -k 5 too; STOPHANG=1 the `systemctl stop` client times out and the validator ignores SIGTERM
#            (the daemon's own SIGKILL stops it); STOPSECS: how long a prompt `systemctl stop` takes
#   HEALTHBEHIND=1 (frozen): the holder's blockstore still sees the cluster via gossip — getHealth reports behind
#   HORIZON  stop at this t
# Rows (each pinned to its measured worst phase per cadence, and its range):
#   (a) prompt I/O — dead local RPC (refusing / every read at its bound), frozen slot, egress-only (N6) at 2.5 and
#       3.7 slots/s (its lag-threshold term included: SELF_FENCE_VOTE_LAG_SLOTS / rate), garbage answers, getHealth
#       behind (F9: never later than the frozen clock), a FULLY WEDGED validator with the monitor running (F5: never)
#   (b) the restarts — row (1) (a corrupted slot restored, restart +30/+45/+63, grace 30 and 0 — F7's 45–60),
#       the PLAIN restart with a canonical state file (F1: the startup blind window, restart + the tier tests +
#       STARTUP_GRACE), the un-armed unit's own crash (Restart=always, RestartSec 10), (1)'s restart member
#   (c) the wedged demote → hard stop (F3: trigger + SETIDENTITY_TIMEOUT + 5 + the systemctl bound + 2)
#   (d) the WORST-CASE I/O column (F4): CHECK_INTERVAL 3, the tiers at their -m bounds, the admin socket at 7 s, every
#       LOCAL read at 4 s — over the collision check's 60 s schedule
# MECHANISMS: none changed this round (R5) — the options each crossing's finding lists go to the reviewer.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "D6 holder column: the holder's fence, from its last landed vote (v0.7 Block 6.3.1 fix round 1)"

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
    kill() {   # the hard stop's direct kill: SIGKILL always stops it; SIGTERM only when the validator is not ignoring it (STOPHANG)
        if [[ "$1" == "-9" ]]; then echo "FENCE t=$(_t) kind=sigkill" >> "$EV"; : > "$W/stopped"; return 0; fi
        if [[ "${STOPHANG:-0}" != "1" && "$1" =~ ^[0-9]+$ ]]; then echo "FENCE t=$(_t) kind=sigterm" >> "$EV"; : > "$W/stopped"; fi
        return 0
    }
    timeout() {
        [[ "$1" == "-k" ]] && shift 2
        local bound="$1"; shift
        case "$*" in
            *"authorized-voter remove-all"*)
                if [[ "${WEDGE:-0}" == "1" ]]; then
                    if [[ "${WEDGEK:-0}" == "1" ]]; then _adv $(( bound + 5 )); echo "wedge t=$(_t) remove-all SIGKILLed at bound+5" >> "$EV"; return 137; fi
                    _adv "$bound"; echo "wedge t=$(_t) remove-all timed out" >> "$EV"; return 124
                fi
                [[ -n "${SLOWADMIN:-}" ]] && _adv "$SLOWADMIN"
                return 0 ;;
            *" set-identity $UNSTAKED_KEYPAIR"*) [[ -n "${SLOWADMIN:-}" ]] && _adv "$SLOWADMIN"; echo "FENCE t=$(_t) kind=demote" >> "$EV"; echo U1 > "$IDF"; return 0 ;;
            *"systemctl stop"*)
                if [[ "${STOPHANG:-0}" == "1" ]]; then _adv "$bound"; echo "stophang t=$(_t) systemctl stop client timed out" >> "$EV"; return 124; fi
                _adv "${STOPSECS:-0}"; echo "FENCE t=$(_t) kind=hardstop" >> "$EV"; : > "$W/stopped"; return 0 ;;
            *"systemctl mask"*) return 0 ;;
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
        if [[ -n "${SLOWLOCAL:-}" && ${SLOWLOCAL:-0} -gt 0 && $t -gt 0 ]]; then
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
    local p="$1" n="$2" i v lo="" hi="" nv=0
    for ((i = 0; i < n; i++)); do
        v=$(hf "$p$i")
        if [[ "$v" == "never" ]]; then nv=$((nv + 1)); continue; fi
        [[ "$v" =~ ^[0-9]+$ ]] || { echo "ERR($p$i='$v')"; return 0; }
        [[ -z "$lo" || $v -lt $lo ]] && lo=$v; [[ -z "$hi" || $v -gt $hi ]] && hi=$v
    done
    if [[ $nv -eq $n ]]; then echo never; elif [[ $nv -gt 0 ]]; then echo MIXED; elif [[ "$lo" == "$hi" ]]; then echo "$lo"; else echo "$lo-$hi"; fi
}
C_SLOT='CORRUPT=s/^SF_LAST_CONFIRMED_SLOT=.*/SF_LAST_CONFIRMED_SLOT=abc/'

# ── the worlds ─────────────────────────────────────────────────────────────────────────────────────────
for ci in 1 3 5; do
    for ((k = 0; k < ci; k++)); do
        st=$(( -100 - k ))
        hlaunch "dr_${ci}_$k"  MODE=deadrefuse CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "dh_${ci}_$k"  MODE=deadhang CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "fz_${ci}_$k"  MODE=frozen CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "e25_${ci}_$k" MODE=egress CI=$ci RATE_N=5 RATE_D=2 INST=$st:-1 HORIZON=120
        hlaunch "e37_${ci}_$k" MODE=egress CI=$ci RATE_N=37 RATE_D=10 INST=$st:-1 HORIZON=120
        hlaunch "gb_${ci}_$k"  MODE=garbage CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "hb_${ci}_$k"  MODE=frozen HEALTHBEHIND=1 CI=$ci INST=$st:-1 HORIZON=120
        hlaunch "fw_${ci}_$k"  MODE=fullwedge CI=$ci INST=$st:-1 HORIZON=300
        hlaunch "r1g0_30_${ci}_$k" MODE=frozen CI=$ci GRACE=0 INST=$st:25,30:-1 "$C_SLOT" HORIZON=260
        hlaunch "crash_${ci}_$k"  MODE=frozen CI=$ci INST=$st:$((29 + ci)),$((39 + ci)):-1 HORIZON=260
        hlaunch "crashh_${ci}_$k" MODE=frozen CI=$ci TMODE=hang INST=$st:$((29 + ci)),$((39 + ci)):-1 HORIZON=260
    done
done
for k in 0 1 2; do
    st=$(( -100 - k ))
    for R in 30 45 63; do
        hlaunch "r1g30_${R}_$k" MODE=frozen CI=3 GRACE=30 INST=$st:25,$R:-1 "$C_SLOT" HORIZON=260
        hlaunch "f1_${R}_$k"    MODE=frozen CI=3 GRACE=30 INST=$st:25,$R:-1 HORIZON=260
        hlaunch "f1h_${R}_$k"   MODE=frozen CI=3 GRACE=30 TMODE=hang INST=$st:25,$R:-1 HORIZON=260
    done
    for R in 45 63; do hlaunch "r1g0_${R}_3_$k" MODE=frozen CI=3 GRACE=0 INST=$st:25,$R:-1 "$C_SLOT" HORIZON=260; done
done
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
        hlaunch "wkhT_${ci}_$k"  MODE=frozen CI=$ci WEDGE=1 WEDGEK=1 STOPHANG=1 TMODE=hang INST=$st:-1 HORIZON=200
        hlaunch "wkhTL_${ci}_$k" MODE=frozen CI=$ci WEDGE=1 WEDGEK=1 STOPHANG=1 TMODE=hang SLOWLOCAL=4 INST=$st:-1 HORIZON=200
    done
done
i=0
for off in 100 101 102 110 120 130 140 150; do
    hlaunch "iofz_$i" MODE=frozen CI=3 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 INST=-$off:-1 HORIZON=200
    hlaunch "iodr_$i" MODE=deadrefuse CI=3 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 INST=-$off:-1 HORIZON=200
    hlaunch "iodh_$i" MODE=deadhang CI=3 TMODE=hang SLOWADMIN=7 INST=-$off:-1 HORIZON=200
    hlaunch "iogb_$i" MODE=garbage CI=3 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 INST=-$off:-1 HORIZON=200
    hlaunch "ioe25_$i" MODE=egress RATE_N=5 RATE_D=2 CI=3 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 INST=-$off:-1 HORIZON=200
    hlaunch "ioe37_$i" MODE=egress RATE_N=37 RATE_D=10 CI=3 TMODE=hang SLOWADMIN=7 SLOWLOCAL=4 INST=-$off:-1 HORIZON=200
    hlaunch "iot_$i" MODE=frozen CI=3 TMODE=hang INST=-$off:-1 HORIZON=200
    i=$((i + 1))
done
wait

# The spare's EARLIEST take / mint the rows are held against (the minimum over read phase and CHECK_INTERVAL
# 1 / 3 / 5 — pinned in test_own_view (6)): un-armed MAX_DELINQUENT_SLOTS=15 73 s (3.7 slots/s) / 79 s (2.5);
# =0 104 s / 125 s; the armed watchdog-elapsed MINT 119 s / 150 s at 3.7, 125 s / 170 s at 2.525 (never at 2.5).
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
row a1 "dead local RPC, refusing (the no-answer clock; admin socket answering)" "31 / 31-33 / 31-35" "$(g dr)" 35
row a2 "dead local RPC, every LOCAL read at its -m bound" "38 / 42-44 / 46-50" "$(g dh)" 50
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
row b5 "F1 with the startup tier tests at their -m bounds, +30 / +45 / +63" "83-85 / 95 / 113" "$(span f1h_30_ 3) / $(span f1h_45_ 3) / $(span f1h_63_ 3)" 113
row b6 "F1 — the un-armed unit's own crash (Restart=always, RestartSec 10) 1 s before the fence would land, CHECK_INTERVAL 1 / 3 / 5 (the phases whose fence lands before the crash: 30–31)" "70 / 30-72 / 30-74" "$(g crash)" 74
row b7 "F1 — the same crash with the tier tests at their bounds" "90 / 92 / 31-94" "$(g crashh)" 94
row b8 "(1)'s restart member: a second restart 1 or 4 cycles into the first restarted instance after a 0 or 20 s stop — first restart +30 / +63" "93-122 / 126-155" "$(span rm30_ 8) / $(span rm63_ 8)" 155

# ── (c) the wedged demote → hard stop (F3) ─────────────────────────────────────────────────────────────
echo ""; echo "─── (c) F3: the demote's remove-all hangs to SETIDENTITY_TIMEOUT → the hard stop; CHECK_INTERVAL 3 / 5 over every phase ───"
g35() { printf '%s / %s' "$(span "${1}_3_" 3)" "$(span "${1}_5_" 5)"; }
row c1 "remove-all at its 15 s bound, a prompt systemctl stop" "45-47 / 45-49" "$(g35 w)" 49
row c2 "… and the CLI needs its -k 5 (bound + 5)" "50-52 / 50-54" "$(g35 wk)" 54
row c3 "… and the systemctl stop client times out (15 s) with the validator ignoring SIGTERM (the daemon's SIGKILL, + 2 s)" "67-69 / 67-71" "$(g35 wkh)" 71
row c4 "… and the tiers at their -m bounds (the collision check's reads)" "70-72 / 68-72" "$(g35 wkhT)" 72
row c5 "… and every LOCAL read at 4 s" "85-87 / 87-91" "$(g35 wkhTL)" 91

# ── (d) the worst-case I/O column (F4) ─────────────────────────────────────────────────────────────────
echo ""; echo "─── (d) F4: the worst-case I/O column — CHECK_INTERVAL 3, the tiers at their bounds, the admin socket at 7 s, LOCAL reads at 4 s, over the collision check's 60 s schedule ───"
row d1 "frozen slot" "76-120" "$(span iofz_ 8)" 120
row d2 "dead local RPC, refusing" "52-66" "$(span iodr_ 8)" 66
row d3 "dead local RPC, every LOCAL read at its bound (admin 7 s, tiers at their bounds)" "57-106" "$(span iodh_ 8)" 106
row d4 "garbage answers" "34-78" "$(span iogb_ 8)" 78
row d5 "egress-only at 2.5 slots/s (N6)" "60-86" "$(span ioe25_ 8)" 86
row d6 "egress-only at 3.7 slots/s (N6)" "60-84" "$(span ioe37_ 8)" 84
row d7 "frozen slot, the tiers at their bounds ONLY (prompt LOCAL and admin)" "31-47" "$(span iot_ 8)" 47

rm -rf "$WORK"
results_banner
