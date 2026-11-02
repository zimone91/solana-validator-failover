#!/bin/bash
# v0.7 (AG-3.1 / 3.2 / 3.3): THE ARMED COLD TAKE UNDER ALPENGLOW - opt-in (AG_ARMED_TAKE=true), standby only.
# AG-1 made the take path a page: in Alpenglow mode FO never takes the staked identity (tests/test_ag_take.sh). AG-3 adds the one opt-in that does, and this suite
# is its proof. The stop at take_staked_identity is `if ! _ag_take_allowed` (fail-closed: an undefined predicate withholds). _ag_take_allowed returns 0 iff AG_ARMED_TAKE is the
# LITERAL `true` AND the readiness margin holds IN THIS CALL (_ag_take_ready: the spare's finalized slot - its root under Alpenglow - minus the holder's frozen lastVote, the baseline
# the vote-liveness gate accepted, is >= AG_TAKE_MARGIN_SLOTS). The take is then voter-first: `authorized-voter add` (closes G4), then `set-identity` with the cold flag (the vote-history requirement switched off).
# What the margin guards (DESIGN-AG 2.3 (ii)): an EMPTY vote history starts the new holder's votes at its own root; a holder that kept voting until its own fence fired
# (<= ~34 s at 5 slots/s = 170 slots + 8 of understatement, rounded up to 200) must be below that floor, or the two would vote the same slots.
#   (1) the default is NOT armed: the stop withholds exactly as AG-1 - one page, zero admin calls, no readiness read; only the literal true arms (TRUE / 1 / yes / 'true ' do not)
#   (2) armed, margin ok: the admin argv in order - `authorized-voter add <key>`, then `set-identity <cold flag> <key>`; ONE read between the stop and the first admin call
#       (A8: the veto's, stubbed here, then the margin's); the TOOK page carries the cold-take fields and the vote-history class; the class is logged before and after
#   (3) the voter add answers `already present`: the take goes on;   (4)(5) any other failure and a timeout: no set-identity, a BLOCKED page, the cooldown stamped
#   (6)-(8) the margin: the boundary (== K takes, K-1 holds), a holder ahead of the spare, finalized unavailable / not an integer, holder lastVote unavailable, an unusable knob - all HOLD, one page
#   (9) polarity: an undefined _ag_take_allowed withholds;   (10) DRY_RUN + armed: the margin is evaluated, the dry page names the cold take, a margin hold pages the hold
#   (11) startup: only the literal true arms (one warning for any other non-empty value); the armed spare says so in the log;   (12) AG_TAKE_MARGIN_SLOTS below 150 refuses to start
#   (13) the banner and the LIVE MODE line print only what is true;   (14) the retained path under harness_ag_off and the fdctl branch are unchanged
#   (15) CONTROLS (mutate()): the default flipped, >= to >, the operands swapped, the flag removed, the order swapped, a voter failure ignored, `already present` not accepted, the polarity opened,
#        the literal not required, a failed finalized read ignored, the dry title lost, the TOOK fields dropped, a second read in the window - each turns its case red
#   (16) the REAL chain (attempt_takeover -> the liveness gate -> the take): the margin reads the baseline the gate accepted; a held take is decided again at the next decision point
# RED ON THE BASE (4c6bbc5 + this suite): the symbols _ag_take_allowed / _ag_take_ready / AG_ARMED_TAKE do not exist there; the stop is `if _ag_mode` (always withheld), so every armed case is red.
#
# harness: tests/lib/harness.sh - load_seam, harness_clock_shims, harness_stub_dir, harness_ag_off, field, mutate, ok/bad+banners.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
title_banner "Armed cold take under Alpenglow: the arm switch, the readiness margin, the voter-first take (v0.7 AG-3.1-3.3)"

T0=100000
DELAY=60
MININT=10
SPAN=40
WORK=$(mktemp -d "${TMPDIR:-/tmp}/agt.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/ledger-absent" "$WORK/ledger-present"
printf 'vote-history-bytes' > "$WORK/ledger-present/vote_history-S1.bin"
FLAG="do-not-require""-vote-history"   # assembled: this file does not name it either
role_of() { basename "$1" | sed 's/solana-\(.*\)-failover.sh/\1/'; }
evn() { printf '%s\n' "$1" | grep -c "^EV: $2"; }          # evn <out> <regex> - how many events match
evl() { printf '%s\n' "$1" | grep "^EV: $2" | head -1; }  # evl <out> <regex> - the first such event

# ── fixtures: the VAT batch answer (the AG-1.4 request shape: ids 1 / 2 / 3) ────────────────────────────────
ent() { printf '{"votePubkey":"V1","nodePubkey":"S1","activatedStake":%s,"epochVoteAccount":%s,"commission":0,"lastVote":100,"rootSlot":90,"epochCredits":[[1,1,0]]}' "$1" "$2"; }
epi() { printf '{"jsonrpc":"2.0","id":%s,"result":{"absoluteSlot":%s,"blockHeight":1,"epoch":%s,"slotIndex":%s,"slotsInEpoch":432000,"transactionCount":1}}' "$1" "$(( $2 * 432000 + $3 ))" "$2" "$3"; }
vat_body() { printf '[%s,{"jsonrpc":"2.0","id":2,"result":{"current":%s,"delinquent":%s}},%s]' "$(epi 1 1074 200000)" "$1" "$2" "$(epi 3 1074 200000)"; }

# ── the LOCAL_RPC every world reads (every request is logged: READ <LOCAL|EXT> <what>) ──────────────────────
# getSlot{confirmed}: the head, advancing 4 slots/s; the own-view veto batch per OVMODE (pass = the holder delinquent in the confirmed view);
# the AG page's reads per HMODE (getHealth), VMODE (getVersion), VATMODE (the VAT batch), AMODE (getAccountInfo); AGDOWN=1 fails exactly those.
ag_curl() {
    local url="" d="" src what off hc m ida idb
    while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac; done
    src=EXT; [[ "$url" == "$LOCAL_RPC" ]] && src=LOCAL
    what=other
    case "$d" in
        *getEpochInfo*)    what=vat ;;
        "["*)              what=veto ;;
        *getHealth*)       what=getHealth ;;
        *getVersion*)      what=getVersion ;;
        *getAccountInfo*)  what=getAccountInfo ;;
        *getSlot*finalized*) what=getSlotFinal ;;
        *getSlot*)         what=getSlot ;;
    esac
    printf 'READ %s %s\n' "$src" "$what" >> "$_EVT_FILE"
    [[ "$src" == "LOCAL" ]] || return 7
    case "$what" in vat|getHealth|getVersion|getAccountInfo|getSlotFinal) [[ -n "${AGDOWN:-}" ]] && return 7 ;; esac
    off=$(( _SIM_NOW - T0 )); hc=$(( 800000 + 4 * off ))
    case "$what" in
        getSlot)      printf '{"jsonrpc":"2.0","id":1,"result":%s}' "$hc" ;;
        getSlotFinal)   # the node's finalized slot (= its root under Alpenglow): $OWN when the world pins it, else the head - 32; FIN=down fails the read, FIN=garbage answers a non-integer
            case "${FIN:-ok}" in
                down)    return 7 ;;
                garbage) printf '{"jsonrpc":"2.0","id":1,"result":"soon"}' ;;
                *)       printf '{"jsonrpc":"2.0","id":1,"result":%s}' "${OWN:-$(( hc - 32 ))}" ;;
            esac ;;
        veto)
            m="${OVMODE:-pass}"
            [[ "$m" == "down" ]] && return 7
            ida=${d#*\"id\":}; ida=${ida%%,*}; idb=${d##*\"id\":}; idb=${idb%%,*}
            if [[ "$m" == "voting" ]]; then
                printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]}}]' "$ida" "$hc" "$idb" "$(( hc - 1 ))"
            else
                printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":{"current":[],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":5000}]}}]' "$ida" "$hc" "$idb"
            fi ;;
        getHealth)
            case "${HMODE:-ok}" in
                ok)      printf '{"jsonrpc":"2.0","result":"ok","id":1}' ;;
                behind)  printf '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by 42 slots","data":{"numSlotsBehind":42}},"id":1}' ;;
                unknown) printf '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is unhealthy","data":{"numSlotsBehind":null}},"id":1}' ;;
                *)       printf 'not json' ;;
            esac ;;
        getVersion)
            case "${VMODE:-ok}" in
                ok)  printf '{"jsonrpc":"2.0","result":{"solana-core":"4.4.0","feature-set":1},"id":1}' ;;
                low) printf '{"jsonrpc":"2.0","result":{"solana-core":"4.3.2","feature-set":1},"id":1}' ;;
                *)   printf '{"jsonrpc":"2.0","result":{},"id":1}' ;;
            esac ;;
        vat)
            case "${VATMODE:-admitted}" in
                admitted)    vat_body "[$(ent 5000000000 true)]" '[]' ;;
                notadmitted) vat_body '[]' "[$(ent 5000000000 false)]" ;;
                *)           vat_body '[]' '[]' ;;
            esac ;;
        getAccountInfo)
            case "${AMODE:-full}" in
                full) printf '{"jsonrpc":"2.0","result":{"value":{"lamports":123456789,"data":{"parsed":{"info":{"blsPubkeyCompressed":"abc","pendingDelegatorRewards":5}}}}},"id":1}' ;;
                *)    printf '{"jsonrpc":"2.0","result":{"value":{"lamports":123456789,"data":{"parsed":{"info":{}}}}},"id":1}' ;;
            esac ;;
        *) return 7 ;;
    esac
    return 0
}


# ── the armed-take worlds ─────────────────────────────────────────────────────────────────────────────────
# The LOCAL_RPC of every world is ag_curl above: getSlot{finalized} is what the readiness margin reads (and the page's own read) - $OWN when a world pins it, FIN=down fails the call (rc 7),
# FIN=garbage answers a non-integer. Each request logs READ <LOCAL|EXT> <what>; the curl BINARY (NET CURLBIN) is the net guard.
ag3_stubs() {   # ag3_stubs <dir> - the curl BINARY (net guard) and the admin CLIs; the voter add answers per ADD=ok|present|fail (the other calls exit 0); EVERY call is logged with its full argv
    cat > "$1/curl" <<'EOS'
#!/bin/sh
printf 'NET CURLBIN %s\n' "$*" | cut -c1-120 >> "$_EVT_FILE"
exit 7
EOS
    cat > "$1/agave-validator" <<'EOS'
#!/bin/sh
printf 'ADMIN agave-validator %s\n' "$*" | cut -c1-200 >> "$_EVT_FILE"
case "$*" in
    *"authorized-voter add"*)
        case "${ADD:-ok}" in
            present) echo "Error: authorized voter already present"; exit 1 ;;
            fail)    echo "Error: admin rpc unreachable"; exit 1 ;;
        esac ;;
esac
exit 0
EOS
    cat > "$1/fdctl" <<'EOS'
#!/bin/sh
printf 'ADMIN fdctl %s\n' "$*" | cut -c1-200 >> "$_EVT_FILE"
exit 0
EOS
    chmod +x "$1/curl" "$1/agave-validator" "$1/fdctl"
    harness_stub_dir "$1"
}
# at_world <script> [knob=value …] - the REAL take_staked_identity of the standby, called once, with the three gates before the stop stubbed open (the gate chain is the other suites' subject; this suite's subject is the
# stop that follows it). Knobs: ARMED (AG_ARMED_TAKE value, default false), MARGIN (AG_TAKE_MARGIN_SLOTS), OWN (the node's finalized slot), HOLDER (the episode's _liveness_first_vote; "" = none), FIN=ok|down|garbage,
# ADD=ok|present|fail|timeout (the voter add), DRY_RUN, VALIDATOR_TYPE, AGMODE=real|off (off = harness_ag_off, the retained path), UNDEF=1 (_ag_take_allowed removed), VH=absent|present, KP=ok|empty.
# Prints: EV: <event> lines (ADMIN / PAGE / READ / NET / LOG / SAVE / HOOK), RC=<take rc>, STATE=ltt=<LAST_TAKEOVER_TIME>.
at_world() {
    local script="$1"; shift
    (
    set +e
    load_seam "$script"
    EVT=$(mktemp); export _EVT_FILE="$EVT"
    STUB=$(mktemp -d); ag3_stubs "$STUB"; PATH="$STUB:$PATH"
    KPF=$(mktemp); echo '[1]' > "$KPF"
    trap 'rm -f "$KPF" "$EVT"; rm -rf "$STUB"' EXIT
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; STAKED_KEYPAIR="$KPF"
    LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"; CONFIG_TOML="$WORK/config.toml"
    SOLANA_PATH="$STUB"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
    DRY_RUN=false; TG_ENABLED=false; MIN_VALIDATOR_VERSION=4.4.0; PREWARM_VOTER_ADD=false
    local ARMED=default MARGIN=default OWN=800000 HOLDER=799000 FIN=ok AGMODE=real UNDEF="" VH=absent KP=ok kv
    export ADD=ok
    OVMODE=pass; HMODE=ok; VMODE=ok; VATMODE=admitted; AMODE=full; AGDOWN=""
    for kv in "$@"; do eval "$kv"; done
    export ADD
    [[ "$ARMED" != "default" ]] && AG_ARMED_TAKE="$ARMED"; [[ "$MARGIN" != "default" ]] && AG_TAKE_MARGIN_SLOTS="$MARGIN"   # "default" = the value the sourced daemon ships (a flipped shipped default is seen)
    LEDGER_PATH="$WORK/ledger-$VH"
    [[ "$KP" == "empty" ]] && : > "$KPF"
    [[ "$AGMODE" == "off" ]] && HARNESS_AG_REAL=0 harness_ag_off
    [[ -n "$UNDEF" ]] && unset -f _ag_take_allowed
    harness_clock_shims
    _SIM_NOW=$(( T0 + 100 ))
    log(){ :;}; log_error(){ :;}
    log_info(){ case "$1" in *"[ag]"*|*"[take]"*|*"[vote-history]"*|"add-voter:"*|"set-identity:"*) printf 'LOG %s\n' "${1:0:230}" >> "$_EVT_FILE" ;; esac; }
    log_warn(){ case "$1" in *"[ag]"*|*"[take]"*|*"[vote-history]"*) printf 'LOG %s\n' "${1:0:230}" >> "$_EVT_FILE" ;; esac; }
    send_telegram(){ local t="${1//$'\n'/ ⏎ }"; printf 'PAGE %s\n' "$t" >> "$_EVT_FILE"; return 0; }
    send_webhook(){ printf 'HOOK %s\n' "${3:-}" >> "$_EVT_FILE"; return 0; }
    save_state(){ printf 'SAVE\n' >> "$_EVT_FILE"; }; sleep(){ :;}
    get_local_identity(){ echo "$STAKED_PUBKEY"; }
    timeout(){ [[ "$1" == "-k" ]] && shift 2; shift; if [[ "$ADD" == "timeout" && "$*" == *"authorized-voter add"* ]]; then "$@" >/dev/null 2>&1; return 124; fi; "$@"; }
    curl(){ ag_curl "$@"; }
    _own_head_sample(){ :; }; _fresh_proof_recheck(){ return 0; }; _own_view_veto(){ return 0; }
    window_reset(){ :; }; _selffence_reset(){ :; }
    FIRST_DELINQUENT_TIME=$T0; LAST_TAKEOVER_TIME=0; STAT_TAKEOVERS=0; CURRENT_IDENTITY="U1"
    _liveness_first_vote="$HOLDER"; _liveness_first_tip=900000; _liveness_first_ts=$(( T0 + 40 )); _liveness_first_provider="T2"
    take_staked_identity "Delinquent test reason"
    printf 'RC=%s\n' "$?" >> "$_EVT_FILE"
    sed 's/^/EV: /' "$EVT"
    printf 'STATE=ltt=%s\n' "$LAST_TAKEOVER_TIME"
    )
}
admin_n() { evn "$1" 'ADMIN'; }
admin_ln() { printf '%s\n' "$1" | grep '^EV: ADMIN' | sed 's/^EV: ADMIN agave-validator //' | cut -c1-160; }   # the admin calls, one argv per line (without the leading --ledger <path>)
admin_args() { admin_ln "$1" | sed 's#^--ledger [^ ]* ##'; }
rc_of() { printf '%s\n' "$1" | grep '^EV: RC=' | sed 's/^EV: RC=//'; }
page_n() { evn "$1" 'PAGE'; }
page_head() { printf '%s\n' "$1" | grep -m1 '^EV: PAGE ' | sed 's/^EV: PAGE [^<]*<b>//; s/<\/b>.*//'; }
reads_before_admin() { printf '%s\n' "$1" | awk '/^EV: ADMIN/ { exit } /^EV: READ / { n++ } END { print n + 0 }'; }
pages_before_admin() { printf '%s\n' "$1" | awk '/^EV: ADMIN/ { exit } /^EV: PAGE / { n++ } END { print n + 0 }'; }
KEY_RE='/tmp/tmp\.[A-Za-z0-9]*|/var/folders/[^ ]*|/private/[^ ]*|/tmp/[^ ]*'
sub_key() { sed -E "s#($KEY_RE)#<key>#g"; }   # the temp keypair path, as <key>
EXPECT_ORDER=$'authorized-voter add <key>\nset-identity --'"$FLAG"' <key>'


# ── the FULL-CHAIN world: the REAL attempt_takeover (episode, delay, external confirm, vote liveness, fresh re-check, own-view veto) -> take_staked_identity over a timeline ──
# The AG-1 world (tests/test_ag_take.sh ag_sb) with the armed take's knobs: ARMED (AG_ARMED_TAKE), MARGIN (AG_TAKE_MARGIN_SLOTS), LV (the holder's frozen lastVote the liveness gate samples; the baseline
# _liveness_first_vote is built from it by the REAL gate), ADD (the voter add's answer: ok|present|fail), plus AGMODE=real|off, DRY_RUN, VALIDATOR_TYPE, KP=ok|empty, VH=absent|present, HZ (last second),
# CLOSE_AT="<t> …" (episode closes), COOLDOWN, THROTTLE, OVMODE, HMODE, VMODE, VATMODE, AMODE, AGDOWN, FIN, OWN, FRESH=advance.
ag3_sb() {
    local script="$1"; shift
    (
    set +e
    load_seam "$script"
    EVT=$(mktemp); export _EVT_FILE="$EVT"
    STUB=$(mktemp -d); ag3_stubs "$STUB"; PATH="$STUB:$PATH"
    KPF=$(mktemp); echo '[1]' > "$KPF"
    trap 'rm -f "$KPF" "$EVT"; rm -rf "$STUB"' EXIT
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; STAKED_KEYPAIR="$KPF"
    LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"; CONFIG_TOML="$WORK/config.toml"
    SOLANA_PATH="$STUB"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
    TAKEOVER_DELAY=$DELAY; EXTERNAL_CONFIRM_THROTTLE=0
    VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0; VOTE_LIVENESS_MIN_SPAN=$SPAN
    GOSSIP_VERIFY=false; WITNESS_FASTPATH=false; DRY_RUN=false; TG_ENABLED=false; PREWARM_VOTER_ADD=false; MIN_VALIDATOR_VERSION=4.4.0
    local AGMODE=real HZ=$(( DELAY + 5 )) COOLDOWN=120 THROTTLE=600 VH=absent KP=ok CLOSE_AT="" FRESH="" ARMED=default MARGIN=default LV=5000 ADD=ok kv
    OVMODE=pass; HMODE=ok; VMODE=ok; VATMODE=admitted; AMODE=full; AGDOWN=""
    for kv in "$@"; do eval "$kv"; done
    export ADD
    [[ "$ARMED" != "default" ]] && AG_ARMED_TAKE="$ARMED"; [[ "$MARGIN" != "default" ]] && AG_TAKE_MARGIN_SLOTS="$MARGIN"
    TAKEOVER_COOLDOWN=$COOLDOWN; ALERT_THROTTLE=$THROTTLE; LEDGER_PATH="$WORK/ledger-$VH"
    [[ "$KP" == "empty" ]] && : > "$KPF"
    [[ "$AGMODE" == "off" ]] && HARNESS_AG_REAL=0 harness_ag_off
    harness_clock_shims
    log(){ :;}; log_error(){ :;}
    log_info(){ case "$1" in *"[ag]"*|*"[prewarm]"*|*"[take]"*|*"[vote-history]"*) printf 'LOG %s\n' "${1:0:200}" >> "$_EVT_FILE" ;; esac; }
    log_warn(){ case "$1" in *"[ag]"*|*"[prewarm]"*|*"[take]"*|*"[vote-history]"*) printf 'LOG %s\n' "${1:0:200}" >> "$_EVT_FILE" ;; esac; }
    send_telegram(){ local t="${1//$'\n'/ ⏎ }"; printf 'PAGE %s\n' "$t" >> "$_EVT_FILE"; return 0; }
    send_webhook(){ printf 'HOOK %s\n' "${3:-}" >> "$_EVT_FILE"; return 0; }
    save_state(){ printf 'SAVE\n' >> "$_EVT_FILE"; }; sleep(){ :;}
    get_local_identity(){ echo "$STAKED_PUBKEY"; }
    timeout(){ [[ "$1" == "-k" ]] && shift 2; shift; "$@"; }
    confirm_delinquency_external(){ return 0; }
    get_staked_liveness_sample(){
        local off=$(( _SIM_NOW - T0 ))
        if [[ "$FRESH" == "advance" && ${_IN_TAKE:-0} -eq 1 ]]; then printf '5001 %s T2\n' $(( 900000 + off )); return 0; fi
        printf '%s %s T2\n' "$LV" $(( 900000 + off )); return 0
    }
    curl(){ ag_curl "$@"; }
    eval "$(declare -f take_staked_identity | sed '1s/^take_staked_identity/_real_take_staked_identity/')"
    take_staked_identity(){ printf 'TAKE-ENTER t=%s\n' $(( _SIM_NOW - T0 )) >> "$_EVT_FILE"; _IN_TAKE=1; _real_take_staked_identity "$@"; local _r=$?; _IN_TAKE=0; printf 'TAKE-EXIT rc=%s\n' "$_r" >> "$_EVT_FILE"; return $_r; }
    ag_episode() {   # a fresh episode, delinquent since $1 ($2=keep: the cooldown stamp survives, as it does in the daemon)
        FIRST_DELINQUENT_TIME=$1; [[ "$2" == "keep" ]] || LAST_TAKEOVER_TIME=0; LAST_LIVENESS_ACTIVE_TIME=0
        SELF_FENCE_DEMOTE_TIME=0; _last_lockout_log=0; _last_confirm_attempt=0
        _delinq_window="1111111111"; _turbo_mode=true; _takeover_alert_sent=""; _gossip_prefetched=false
        _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
        _last_blind_end=0; _liveness_obs_since=0
    }
    CURRENT_IDENTITY="U1"; ag_episode "$T0"
    local t closes=" $CLOSE_AT "
    for ((t = 0; t <= HZ; t++)); do
        _SIM_NOW=$(( T0 + t ))
        case "$closes" in *" $t "*) window_reset; printf 'CLOSE t=%s\n' "$t" >> "$_EVT_FILE"; ag_episode "$_SIM_NOW" keep ;; esac
        _own_head_sample >/dev/null 2>&1; _own_bank_note 5000
        attempt_takeover >/dev/null 2>&1
        grep -q '^ADMIN.* set-identity' "$EVT" && break
    done
    sed 's/^/EV: /' "$EVT"
    printf 'STATE=ltt=%s|pagets=%s|prewarm_done=%s|now=%s\n' "$LAST_TAKEOVER_TIME" "$_ag_page_ts" "${_prewarm_done:-0}" "$_SIM_NOW"
    )
}

page_of() { printf '%s\n' "$1" | grep -m1 '^EV: PAGE '; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
st() { printf '%s\n' "$1" | grep '^STATE=' | sed 's/^STATE=//'; }

# ── (1) default: NOT armed - the stop withholds exactly as AG-1 ──────────────────────────────────────────
echo ""; echo "─── (1) default (AG_ARMED_TAKE=false): the stop withholds as in AG-1 - one page, zero admin calls, no readiness read ───"
out=$(at_world "$STANDBY")
if [[ "$(admin_n "$out")" == "0" && "$(page_n "$out")" == "1" && "$(rc_of "$out")" == "1" && "$(evn "$out" 'NET CURLBIN')" == "0" && "$(page_head "$out")" == "TAKEOVER WITHHELD — Alpenglow mode 🚨" ]]; then
    ok "(1a) unarmed, margin irrelevant: take_staked_identity returns 1, ZERO admin calls, ONE page titled 'TAKEOVER WITHHELD — Alpenglow mode 🚨', no curl binary"
else
    bad "(1a) unarmed: admin=$(admin_n "$out") pages=$(page_n "$out") rc=$(rc_of "$out") head=$(page_head "$out")"
fi
pg=$(printf '%s\n' "$out" | grep -m1 '^EV: PAGE ')
if has "$pg" "this spare is NOT ARMED (AG_ARMED_TAKE=false): nothing was done" && has "$pg" "every gate FO has said the take would happen now" && has "$pg" "A cold take is an operator decision; FO never makes it." && ! has "$pg" "ARMED, but"; then
    ok "(1b) the page says it plainly: 'this spare is NOT ARMED (AG_ARMED_TAKE=false): nothing was done' - the AG-1 operator-path sentence stays"
else
    bad "(1b) unarmed page text: $pg"
fi
[[ "$(evn "$out" 'READ LOCAL getSlotFinal')" == "1" && "$(evn "$out" 'LOG .*armed take: held (not armed')" == "1" ]] \
    && ok "(1c) NO readiness read when unarmed: the only getSlot{finalized} is the page's own (1), and one '[ag] armed take: held (not armed ...)' log line" || bad "(1c) reads=$(evn "$out" 'READ LOCAL getSlotFinal') log=$(evl "$out" 'LOG .*armed take')"
[[ "$(field "$(printf '%s\n' "$out" | grep '^STATE=' | sed 's/^STATE=//')" ltt)" -gt 0 ]] \
    && ok "(1d) the stop stamps the cooldown (LAST_TAKEOVER_TIME), as the AG-1 stop did" || bad "(1d) no cooldown stamp"
for v in TRUE 1 yes "true "; do
    o=$(at_world "$STANDBY" "ARMED='$v'")
    [[ "$(admin_n "$o")" == "0" && "$(page_head "$o")" == "TAKEOVER WITHHELD — Alpenglow mode 🚨" ]] || { bad "(1e) AG_ARMED_TAKE='$v' armed the take: admin=$(admin_n "$o")"; continue; }
done
ok "(1e) the predicate itself reads the LITERAL: AG_ARMED_TAKE=TRUE, 1, yes and 'true ' (trailing space) leave the take withheld even if no startup coercion ran"
dflt=$( (set +e; load_seam "$STANDBY"; printf '%s|%s|%s' "${AG_ARMED_TAKE-UNSET}" "${AG_TAKE_MARGIN_SLOTS-UNSET}" "${TAKEOVER_DELAY-UNSET}") )
[[ "$dflt" == "false|200|60" ]] && ok "(1f) the shipped defaults the worlds above read: AG_ARMED_TAKE=false, AG_TAKE_MARGIN_SLOTS=200, TAKEOVER_DELAY=60" || bad "(1f) shipped defaults (armed|margin|delay): $dflt"

# ── (2) armed + margin ok: voter first, then the cold set-identity ───────────────────────────────────────────
echo ""; echo "─── (2) armed, margin ok: authorized-voter add FIRST, then set-identity with the cold flag; TOOK page with the cold-take fields ───"
out=$(at_world "$STANDBY" ARMED=true)
got=$(admin_args "$out" | sub_key)
if [[ "$got" == "$EXPECT_ORDER" && "$(rc_of "$out")" == "0" && "$(page_head "$out")" == "TOOK STAKED ✅" && "$(page_n "$out")" == "1" ]]; then
    ok "(2a) the mock records, in this order: 'authorized-voter add <key>' then 'set-identity $FLAG <key>' - nothing else; rc 0; ONE page, 'TOOK STAKED ✅'"
else
    bad "(2a) armed take: calls=[$(printf '%s' "$got" | tr '\n' ';')] rc=$(rc_of "$out") head=$(page_head "$out") pages=$(page_n "$out")"
fi
if [[ "$(reads_before_admin "$out")" == "1" && "$(pages_before_admin "$out")" == "0" && "$(evn "$out" 'NET CURLBIN')" == "0" && "$(evn "$out" 'READ EXT')" == "0" ]] && has "$(evl "$out" 'READ LOCAL')" "getSlotFinal"; then
    ok "(2b) A8 for the armed path: between the stop and the first admin call exactly ONE read - the readiness margin's getSlot{finalized} on LOCAL_RPC - no alert, no external read, no curl binary"
else
    bad "(2b) reads before the first admin call=$(reads_before_admin "$out") pages before=$(pages_before_admin "$out") ext=$(evn "$out" 'READ EXT') net=$(evn "$out" 'NET CURLBIN')"
fi
tk=$(printf '%s\n' "$out" | grep -m1 '^EV: PAGE ')
if has "$tk" "cold take: empty history, floor = own root 800000; holder lastVote 799000; margin 1000 slots; vote history before the take: absent"; then
    ok "(2c) the TOOK page carries 'cold take: empty history, floor = own root 800000; holder lastVote 799000; margin 1000 slots; vote history before the take: absent'"
else
    bad "(2c) TOOK page: $tk"
fi
[[ "$(evn "$out" 'LOG .*armed take: allowed')" == "1" && "$(evn "$out" 'LOG .*\[vote-history\] before the cold take')" == "1" && "$(evn "$out" 'LOG .*\[vote-history\] after the cold take')" == "1" ]] \
    && ok "(2d) logs: one '[ag] armed take: allowed', and the history class before and after the take" || bad "(2d) logs: $(printf '%s\n' "$out" | grep '^EV: LOG' | cut -c1-90 | tr '\n' ';')"
pv=$(at_world "$STANDBY" ARMED=true VH=present | grep -m1 '^EV: PAGE ')
has "$pv" "vote history before the take: present (mtime=" && has "$pv" "size=18 sha256=" \
    && ok "(2e) with a vote-history file present the TOOK page reports its class (mtime, size 18, sha256) and the take goes on - the history is reported, never acted on" || bad "(2e) present history: $pv"

# ── (2f) the A8 census of the armed predicate (static, bash's own parse) ──────────────────────────────────────────────────────────
echo ""; echo "─── (2f) the armed predicate's closure: ONE LOCAL read, no alert, nothing else on the network ───"
pred_census() {   # pred_census <script> -> "NET <fn> <word> <n>" / "PAGE <fn> <word> <n>" for every network word and every page call in _ag_take_allowed and every daemon function it calls, transitively
    (
        set +e
        load_seam "$1"
        defs=" $(declare -F | awk '{print $3}' | tr '\n' ' ') "
        seen=" "; todo="_ag_take_allowed"
        while :; do
            set -- $todo; [[ $# -gt 0 ]] || break
            nxt=""
            for f in "$@"; do
                case "$seen" in *" $f "*) continue ;; esac
                seen="$seen$f "
                for w in $(declare -f "$f" 2>/dev/null | sed '1d' | tr -c 'A-Za-z0-9_' '\n' | sort -u); do
                    case "$defs" in *" $w "*) nxt="$nxt $w" ;; esac
                done
            done
            todo="$nxt"
        done
        for f in $seen; do
            b=$(declare -f "$f" 2>/dev/null); toks=$(printf '%s\n' "$b" | tr -c 'A-Za-z0-9_' '\n')
            for w in curl wget nc ncat socat ssh scp telnet dig nslookup ping; do
                n=$(printf '%s\n' "$toks" | grep -c -x "$w")
                if [[ "$w" == "curl" ]]; then [[ $n -gt 0 ]] && printf 'NET %s curl %s\n' "$f" "$n"   # a request is counted: a second one must show
                else [[ $n -gt 0 ]] && printf 'NET %s %s\n' "$f" "$w"; fi                       # any other client word: its presence is the finding (a log text may repeat it)
            done
            printf '%s\n' "$b" | grep -q '/dev/tcp\|/dev/udp' && printf 'NET %s dev-tcp-udp 1\n' "$f"
            for w in alert alert_warn alert_info send_telegram send_webhook; do
                n=$(printf '%s\n' "$toks" | grep -c -x "$w"); [[ $n -gt 0 ]] && printf 'PAGE %s %s %s\n' "$f" "$w" "$n"
            done
        done | sort
    )
}
PRED_OK=$'NET _ag_slot_final curl 1\nNET _sd_notify socat'   # the one LOCAL getSlot{finalized}; the notify socket (the watchdog pet: a local datagram) - the same allowance as tests/test_own_view.sh A8_NET_OK
pc=$(pred_census "$STANDBY")
rd_n=$( ( set +e; load_seam "$STANDBY"; declare -f _ag_take_ready | tr -c 'A-Za-z0-9_' '\n' | grep -c -x '_ag_slot_final' ) )
loc_n=$( ( set +e; load_seam "$STANDBY"; declare -f _ag_slot_final | grep -c 'curl -s -m 3 "\$LOCAL_RPC"' ) )
if [[ "$pc" == "$PRED_OK" && "$rd_n" == "1" && "$loc_n" == "1" ]]; then
    ok "(2f) _ag_take_allowed and everything it calls: ONE network word that is a request - the single 'curl -s -m 3 \"\$LOCAL_RPC\"' of _ag_slot_final (called once, by _ag_take_ready) - plus the watchdog's local datagram socket; no alert, no webhook, no other client, no /dev/tcp"
else
    bad "(2f) predicate closure: census=[$(printf '%s' "$pc" | tr '\n' ';')] slot-final calls in _ag_take_ready=$rd_n local-curl lines=$loc_n"
fi
pc_ok=1; pc_rows=""
mp() {   # mp <label> <sed expr> -> the census of a mutant of the standby
    local m="$WORK/pc-$1.sh"; mutate "$STANDBY" "$2" "$m" >/dev/null || { pc_ok=0; pc_rows="$pc_rows $1:not-applied"; return 1; }
    [[ "$(pred_census "$m")" != "$PRED_OK" ]] && pc_rows="$pc_rows $1:red" || { pc_ok=0; pc_rows="$pc_rows $1:GREEN"; }
}
mp second-read 's/^    _own=\$(_ag_slot_final)$/    _own=$(_ag_slot_final); command curl -s -m 1 "$TIER3_RPC" >\/dev\/null 2>\&1/'
mp page-in-predicate 's/^    _ag_lead=""; _ag_opnote=""$/    _ag_lead=""; _ag_opnote=""; alert_warn "armed"/'
mp external-read 's/^    _canon_uint "\${AG_TAKE_MARGIN_SLOTS:-}" || {/    wget -q -O - "$TIER2_RPC" >\/dev\/null 2>\&1; _canon_uint "${AG_TAKE_MARGIN_SLOTS:-}" || {/'
if [[ $pc_ok -eq 1 ]]; then ok "(2f-ctl) the census catches a second request in the margin read (a curl to TIER3), a page in the predicate and an external client:$pc_rows"; else bad "(2f-ctl) a mutant keeps the census green (GREEN) or did not apply:$pc_rows"; fi

# ── (3)-(5) the voter add: already present / failure / timeout ─────────────────────────────────────────────
echo ""; echo "─── (3)-(5) the voter add: 'already present' continues; any other failure and a timeout stop the take BEFORE set-identity ───"
out=$(at_world "$STANDBY" ARMED=true ADD=present)
if [[ "$(admin_args "$out" | sub_key)" == "$EXPECT_ORDER" && "$(rc_of "$out")" == "0" && "$(page_head "$out")" == "TOOK STAKED ✅" ]] && has "$(evl "$out" 'LOG .*already loaded')" "continuing to set-identity"; then
    ok "(3) the voter add answers rc 1 'already present': logged, and set-identity still runs (the same two calls in the same order, TOOK)"
else
    bad "(3) already present: calls=[$(admin_args "$out" | sub_key | tr '\n' ';')] rc=$(rc_of "$out") head=$(page_head "$out")"
fi
for md in fail timeout; do
    out=$(at_world "$STANDBY" ARMED=true ADD=$md)
    want_detail="admin rpc unreachable"; [[ "$md" == "timeout" ]] && want_detail="timed out"
    pg=$(printf '%s\n' "$out" | grep -m1 '^EV: PAGE ')
    if [[ "$(admin_args "$out" | sub_key)" == "authorized-voter add <key>" && "$(rc_of "$out")" == "1" && "$(page_n "$out")" == "1" && "$(page_head "$out")" == "TAKEOVER BLOCKED — authorized-voter add failed" \
          && "$(field "$(printf '%s\n' "$out" | grep '^STATE=' | sed 's/^STATE=//')" ltt)" -gt 0 ]] && has "$pg" "$want_detail" && has "$pg" "the identity change was NOT attempted"; then
        ok "(4:$md) the voter add ${md}s: NO set-identity (one admin call), ONE page 'TAKEOVER BLOCKED — authorized-voter add failed' naming '$want_detail', the cooldown stamped, rc 1"
    else
        bad "(4:$md) calls=[$(admin_args "$out" | sub_key | tr '\n' ';')] rc=$(rc_of "$out") pages=$(page_n "$out") head=$(page_head "$out") page=$pg"
    fi
done

# ── (6)-(8) the readiness margin: boundary, operands, unavailable reads ────────────────────────────────────────
echo ""; echo "─── (6)-(8) the readiness margin (own finalized - holder lastVote >= AG_TAKE_MARGIN_SLOTS): the boundary, and every unavailable input holds ───"
b_ok=$(at_world "$STANDBY" ARMED=true OWN=800000 HOLDER=799800 MARGIN=200)   # margin 200 == K
b_lo=$(at_world "$STANDBY" ARMED=true OWN=800000 HOLDER=799801 MARGIN=200)   # margin 199 < K
if [[ "$(admin_n "$b_ok")" == "2" && "$(rc_of "$b_ok")" == "0" && "$(admin_n "$b_lo")" == "0" && "$(rc_of "$b_lo")" == "1" ]]; then
    ok "(6a) THE BOUNDARY: margin 200 against AG_TAKE_MARGIN_SLOTS=200 takes (2 admin calls); margin 199 holds (0 admin calls)"
else
    bad "(6a) boundary: at-K admin=$(admin_n "$b_ok") rc=$(rc_of "$b_ok"); K-1 admin=$(admin_n "$b_lo") rc=$(rc_of "$b_lo")"
fi
pg=$(printf '%s\n' "$b_lo" | grep -m1 '^EV: PAGE ')
if [[ "$(page_n "$b_lo")" == "1" && "$(page_head "$b_lo")" == "TAKEOVER WITHHELD — Alpenglow mode 🚨" ]] && has "$pg" "ARMED, but the readiness margin held the take: own finalized 800000, holder lastVote 799801, margin 199 &lt; AG_TAKE_MARGIN_SLOTS=200: nothing was done" \
   && has "$pg" "This spare is armed: it takes by itself once the readiness margin clears" && [[ "$(evn "$b_lo" 'LOG .*armed take: held (margin 199 < 200)')" == "1" ]]; then
    ok "(6b) the hold pages ONCE ('TAKEOVER WITHHELD — Alpenglow mode 🚨') and names own finalized 800000, holder lastVote 799801, margin 199 < AG_TAKE_MARGIN_SLOTS=200; the operator-path sentence says the spare is armed; one '[ag] armed take: held (margin 199 < 200)'"
else
    bad "(6b) hold page: $pg"
fi
sw=$(at_world "$STANDBY" ARMED=true OWN=799000 HOLDER=800000 MARGIN=200)   # holder above own: a negative margin
if [[ "$(admin_n "$sw")" == "0" ]] && has "$(printf '%s\n' "$sw" | grep -m1 '^EV: PAGE ')" "margin -1000 &lt; AG_TAKE_MARGIN_SLOTS=200"; then
    ok "(6c) a holder AHEAD of the spare's root holds, with the signed margin (-1000) on the page"
else
    bad "(6c) negative margin: admin=$(admin_n "$sw") $(printf '%s\n' "$sw" | grep -m1 '^EV: PAGE ')"
fi
fd=$(at_world "$STANDBY" ARMED=true FIN=down)
if [[ "$(admin_n "$fd")" == "0" && "$(page_n "$fd")" == "1" ]] && has "$(printf '%s\n' "$fd" | grep -m1 '^EV: PAGE ')" "readiness margin held the take: finalized unavailable" && [[ "$(evn "$fd" 'LOG .*armed take: held (finalized unavailable')" == "1" ]]; then
    ok "(7a) own finalized slot unavailable (the LOCAL read fails): HOLD - zero admin calls, ONE page, reason 'finalized unavailable (...)'"
else
    bad "(7a) finalized down: admin=$(admin_n "$fd") $(printf '%s\n' "$fd" | grep -m1 '^EV: PAGE ')"
fi
fg=$(at_world "$STANDBY" ARMED=true FIN=garbage)
[[ "$(admin_n "$fg")" == "0" ]] && has "$(printf '%s\n' "$fg" | grep -m1 '^EV: PAGE ')" "finalized unavailable" \
    && ok "(7b) a finalized answer that is not a canonical integer holds the same way" || bad "(7b) garbage finalized: admin=$(admin_n "$fg")"
hn=$(at_world "$STANDBY" ARMED=true HOLDER=)
if [[ "$(admin_n "$hn")" == "0" && "$(page_n "$hn")" == "1" ]] && has "$(printf '%s\n' "$hn" | grep -m1 '^EV: PAGE ')" "readiness margin held the take: holder lastVote unavailable" && [[ "$(evn "$hn" 'LOG .*armed take: held (holder lastVote unavailable)')" == "1" ]]; then
    ok "(8) no liveness sample in the episode (_liveness_first_vote empty): HOLD - 'holder lastVote unavailable', zero admin calls"
else
    bad "(8) no holder lastVote: admin=$(admin_n "$hn") $(printf '%s\n' "$hn" | grep -m1 '^EV: PAGE ')"
fi
mu=$(at_world "$STANDBY" ARMED=true "MARGIN=abc")
[[ "$(admin_n "$mu")" == "0" ]] && has "$(printf '%s\n' "$mu" | grep -m1 '^EV: PAGE ')" "AG_TAKE_MARGIN_SLOTS unusable" \
    && ok "(8b) an unusable AG_TAKE_MARGIN_SLOTS at call time holds (fail-closed), whatever startup said" || bad "(8b) unusable margin knob: admin=$(admin_n "$mu")"

# ── (9) the polarity ─────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) polarity: an UNDEFINED _ag_take_allowed (rc 127) withholds - the stop fails CLOSED ───"
ud=$(at_world "$STANDBY" ARMED=true UNDEF=1)
if [[ "$(admin_n "$ud")" == "0" && "$(rc_of "$ud")" == "1" && "$(page_n "$ud")" == "1" && "$(page_head "$ud")" == "TAKEOVER WITHHELD — Alpenglow mode 🚨" ]]; then
    ok "(9) 'unset -f _ag_take_allowed' with the knob true: the take is withheld - one page, zero admin calls (the AG-1 form, 'if _ag_mode', fell THROUGH to the take when its predicate was undefined)"
else
    bad "(9) undefined predicate: admin=$(admin_n "$ud") rc=$(rc_of "$ud") pages=$(page_n "$ud")"
fi

# ── (10) DRY_RUN ─────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (10) DRY_RUN + armed: the margin is evaluated; a ready dry take pages 'WOULD TAKE STAKED (Alpenglow cold take)', a hold pages the hold ───"
dr=$(at_world "$STANDBY" ARMED=true DRY_RUN=true)
drp=$(printf '%s\n' "$dr" | grep -m1 '^EV: PAGE ')
if [[ "$(admin_n "$dr")" == "0" && "$(rc_of "$dr")" == "0" && "$(page_n "$dr")" == "1" && "$(page_head "$dr")" == "[DRY RUN] WOULD TAKE STAKED (Alpenglow cold take)" ]] \
   && has "$drp" "cold take: empty history, floor = own root 800000; holder lastVote 799000; margin 1000 slots; vote history before the take: absent" && [[ "$(evn "$dr" 'READ LOCAL getSlotFinal')" == "1" ]]; then
    ok "(10a) DRY_RUN + armed + margin ok: ZERO admin calls, ONE page '[DRY RUN] WOULD TAKE STAKED (Alpenglow cold take)' with the TOOK page's fields; the margin read happened (1)"
else
    bad "(10a) dry armed: admin=$(admin_n "$dr") rc=$(rc_of "$dr") head=$(page_head "$dr") page=$drp"
fi
dh=$(at_world "$STANDBY" ARMED=true DRY_RUN=true HOLDER=799900)
if [[ "$(admin_n "$dh")" == "0" && "$(rc_of "$dh")" == "1" && "$(page_head "$dh")" == "TAKEOVER WITHHELD — Alpenglow mode 🚨" ]] && has "$(printf '%s\n' "$dh" | grep -m1 '^EV: PAGE ')" "margin 100 &lt; AG_TAKE_MARGIN_SLOTS=200"; then
    ok "(10b) DRY_RUN + armed + margin 100 < 200: the HOLD is paged (TAKEOVER WITHHELD), not a dry take"
else
    bad "(10b) dry hold: admin=$(admin_n "$dh") rc=$(rc_of "$dh") head=$(page_head "$dh")"
fi
du=$(at_world "$STANDBY" DRY_RUN=true)
[[ "$(admin_n "$du")" == "0" && "$(page_head "$du")" == "TAKEOVER WITHHELD — Alpenglow mode 🚨" ]] \
    && ok "(10c) DRY_RUN + NOT armed: the AG-1 withheld page, no dry take" || bad "(10c) dry unarmed: head=$(page_head "$du")"

# ── (11) the startup coercion, (12) the margin floor ────────────────────────────────────────────────────────────────
echo ""; echo "─── (11)-(12) startup: only the literal true arms; a margin below 150 refuses to start ───"
co_stmt=$(grep -F -m1 -e 'is not exactly true or false' "$STANDBY")
co_run() {   # co_run <value> -> "<WARN count>|<AG_ARMED_TAKE after>"
    (
        set +e
        load_seam "$STANDBY"
        log_warn(){ printf 'WARN %s\n' "$1"; }
        AG_ARMED_TAKE="$1"
        eval "$co_stmt"
        printf 'AFTER=%s\n' "$AG_ARMED_TAKE"
    ) | awk '/^WARN /{w++} /^AFTER=/{a=substr($0,7)} END{printf "%d|%s", w+0, a}'
}
co_ok=1; co_why=""
for v in TRUE 1 yes "true "; do r=$(co_run "$v"); [[ "$r" == "1|false" ]] || { co_ok=0; co_why="$co_why [$v: $r]"; }; done
for v in true false ""; do r=$(co_run "$v"); [[ "$r" == "0|$v" ]] || { co_ok=0; co_why="$co_why [$v: $r]"; }; done
[[ -n "$co_stmt" && $co_ok -eq 1 ]] && ok "(11) the ONE startup statement: TRUE / 1 / yes / 'true ' warn once and leave the knob false; true, false and empty pass silently and unchanged" || bad "(11) startup coercion: stmt=[${co_stmt:0:60}]$co_why"
lw_stmt=$(grep -F -m1 -e 'this spare WILL take the staked identity by itself (cold take) when every gate says take' "$STANDBY")
lw_run() {   # lw_run <value> -> the number of WARN lines the armed-notice statement prints
    (
        set +e
        load_seam "$STANDBY"
        log_warn(){ printf 'WARN %s\n' "$1"; }
        AG_ARMED_TAKE="$1"; AG_TAKE_MARGIN_SLOTS=200
        eval "$lw_stmt"
    ) | grep -c '^WARN '
}
if [[ -n "$lw_stmt" && "$(lw_run true)" == "1" && "$(lw_run false)" == "0" ]]; then
    ok "(11b) armed, the daemon says so in the log at start: ONE warning 'this spare WILL take the staked identity by itself (cold take)'; unarmed says nothing"
else
    bad "(11b) armed notice: stmt=[${lw_stmt:0:60}] armed=$(lw_run true) unarmed=$(lw_run false)"
fi
pw_check() {   # pw_check <script> -> empty when the pairing floor behaves, else why not. ARMED + a delay below 60 refuses to start (DRY_RUN no exception); not armed only warns below 60
    local sc="$1" st su d why=""
    st=$(grep -F -m1 -e 'AG_ARMED_TAKE=true with TAKEOVER_DELAY=' "$sc"); su=$(grep -F -m1 -e 'this spare is not armed, so it only pages' "$sc")
    [[ -n "$st" && -n "$su" ]] || { printf 'statements missing'; return 0; }
    pw_rc() {   # pw_rc <armed> <delay> [dry_run] -> the exit status of the refusal statement
        # a statement that does not refuse falls through to the marker; one that exits does not - the list's own status (1 when its [[ ]] is false) says nothing
        ( set +e; load_seam "$sc"; log_error(){ :; }; AG_ARMED_TAKE="$1"; TAKEOVER_DELAY="$2"; DRY_RUN="${3:-false}"; n=$( ( eval "$st"; echo CONT ) 2>/dev/null | grep -c CONT ); [[ "$n" -eq 0 ]] && echo 1 || echo 0 ) | tail -1
    }
    pu_n() {    # pu_n <armed> <delay> -> the number of WARN lines the unarmed-floor statement prints
        ( set +e; load_seam "$sc"; log_warn(){ printf 'WARN %s\n' "$1"; }; AG_ARMED_TAKE="$1"; TAKEOVER_DELAY="$2"; eval "$su" ) | grep -c '^WARN '
    }
    for d in 30 45 59; do [[ "$(pw_rc true $d)" == "1" ]] || why="$why [armed $d: no refusal]"; done
    [[ "$(pw_rc true 59 true)" == "1" ]] || why="$why [armed 59 DRY_RUN=true: no refusal]"
    for d in 60 90 120; do [[ "$(pw_rc true $d)" == "0" ]] || why="$why [armed $d refused]"; done
    for d in 30 45 59; do [[ "$(pw_rc false $d)" == "0" ]] || why="$why [unarmed $d refused]"; [[ "$(pu_n false $d)" == "1" ]] || why="$why [unarmed $d: no warning]"; done
    for d in 60 90; do [[ "$(pu_n false $d)" == "0" ]] || why="$why [unarmed $d warned]"; done
    [[ "$(pu_n true 59)" == "0" ]] || why="$why [armed 59: the unarmed warning fired]"
    printf '%s' "$why"
}
pw_why=$(pw_check "$STANDBY")
[[ -z "$pw_why" ]] && ok "(11c) the pairing rule at startup: ARMED with TAKEOVER_DELAY 30, 45 or 59 (< the holder's default gap 30 + 30) REFUSES to start - DRY_RUN is no exception; 60, 90, 120 start; a spare that is NOT armed starts at any delay and warns once below 60" || bad "(11c) pairing floor:$pw_why"
pc_rows=""; pc_ok=1
for spec in "floor-55:s/\"\$TAKEOVER_DELAY\" -lt 60 \]\] \&\& { log_error \"AG_ARMED_TAKE=true/\"\$TAKEOVER_DELAY\" -lt 55 ]] \&\& { log_error \"AG_ARMED_TAKE=true/" \
            "no-exit:s/Armed cold take)\"; exit 1; }/Armed cold take)\"; : ; }/" \
            "dry-run-exempt:s/\[\[ \"\$AG_ARMED_TAKE\" == \"true\" \&\& \"\$TAKEOVER_DELAY\" -lt 60 \]\]/[[ \"\$AG_ARMED_TAKE\" == \"true\" \&\& \"\$DRY_RUN\" != \"true\" \&\& \"\$TAKEOVER_DELAY\" -lt 60 ]]/"; do
    lab="${spec%%:*}"; expr="${spec#*:}"; m="$WORK/pw-$lab.sh"
    if mutate "$STANDBY" "$expr" "$m" >/dev/null; then [[ -n "$(pw_check "$m")" ]] && pc_rows="$pc_rows $lab:red" || { pc_ok=0; pc_rows="$pc_rows $lab:GREEN"; }; else pc_ok=0; pc_rows="$pc_rows $lab:not-applied"; fi
done
[[ $pc_ok -eq 1 ]] && ok "(11c-ctl) the floor lowered to 55, the exit removed and a DRY_RUN exemption each turn (11c) red:$pc_rows" || bad "(11c-ctl) a mutant keeps (11c) green or did not apply:$pc_rows"
mg_stmt=$(grep -F -m1 -e '_validate_numeric AG_TAKE_MARGIN_SLOTS' "$STANDBY" | sed 's/^[[:space:]]*//; s/[[:space:]]*#.*$//')
mg_run() {   # mg_run <value> -> the exit status of the validator statement
    (
        set +e
        load_seam "$STANDBY"
        log_error(){ :; }
        AG_TAKE_MARGIN_SLOTS="$1"
        ( eval "$mg_stmt" ) >/dev/null 2>&1
        echo "$?"
    ) | tail -1
}
mg_ok=1; mg_why=""
for v in 149 0 abc ""; do r=$(mg_run "$v"); [[ "$r" == "1" ]] || { mg_ok=0; mg_why="$mg_why [$v: rc $r]"; }; done
for v in 150 200 0200; do r=$(mg_run "$v"); [[ "$r" == "0" ]] || { mg_ok=0; mg_why="$mg_why [$v: rc $r]"; }; done
[[ -n "$mg_stmt" && $mg_ok -eq 1 ]] && ok "(12) AG_TAKE_MARGIN_SLOTS: 149, 0, abc and empty refuse to start (exit 1); 150, 200 and 0200 pass - the floor is 150 slots, like the delay floor" || bad "(12) margin floor: stmt=[$mg_stmt]$mg_why"

# ── (13) banner and LIVE MODE ─────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (13) the banner and the LIVE MODE line print only what is true ───"
pair_ok() {   # pair_ok <armed needle> <unarmed needle> - the armed line sits right under `if [[ "$AG_ARMED_TAKE" == "true" ]]; then`, the unarmed one right under its `else`, a `fi` closes
    local a u
    a=$(grep -n -F -e "$1" "$STANDBY" | head -1 | cut -d: -f1); u=$(grep -n -F -e "$2" "$STANDBY" | head -1 | cut -d: -f1)
    [[ -n "$a" && -n "$u" && $u -eq $(( a + 2 )) ]] || return 1
    [[ "$(sed -n "$(( a - 1 ))p" "$STANDBY")" == *'if [[ "$AG_ARMED_TAKE" == "true" ]]; then'* ]] || return 1
    [[ "$(sed -n "$(( a + 1 ))p" "$STANDBY")" == *else* ]] || return 1
    [[ "$(sed -n "$(( u + 1 ))p" "$STANDBY")" == *fi* ]]
}
if pair_ok 'Mode:              ALPENGLOW, ARMED — this spare WILL take the staked identity by itself (cold take, ${_AG_COLD_FLAG}) when every gate says take and the readiness margin holds' \
           'Mode:              ALPENGLOW — this node NEVER takes the staked identity itself'; then
    ok "(13a) the startup banner: 'ALPENGLOW, ARMED — this spare WILL take the staked identity by itself (cold take, <flag>) when every gate says take and the readiness margin holds' stands only under 'if AG_ARMED_TAKE == true'; the AG-1 text ('this node NEVER takes') under 'else'"
else
    bad "(13a) banner structure: the armed text is not the if-branch, the AG-1 text the else-branch, of one if/else/fi"
fi
if pair_ok 'LIVE MODE — STANDBY will perform a real takeover' 'LIVE MODE — STANDBY will demote itself if it holds the staked identity; it never takes (not armed)'; then
    ok "(13b) the LIVE MODE line: 'STANDBY will perform a real takeover' only under 'if AG_ARMED_TAKE == true'; unarmed: 'STANDBY will demote itself if it holds the staked identity; it never takes (not armed)'"
else
    bad "(13b) LIVE MODE structure: the armed text is not the if-branch, the unarmed text the else-branch, of one if/else/fi"
fi

# ── (14) the other branches: the retained path and fdctl ────────────────────────────────────────────────────────────────
echo ""; echo "─── (14) the retained path (shadowed) and fdctl are unchanged ───"
rt=$(at_world "$STANDBY" AGMODE=off)
if [[ "$(admin_args "$rt" | sub_key)" == $'set-identity <key>\nauthorized-voter add <key>' && "$(rc_of "$rt")" == "0" && "$(reads_before_admin "$rt")" == "0" ]]; then
    ok "(14a) the SAME world under harness_ag_off (what every older suite runs): set-identity FIRST, then authorized-voter add, no cold flag, no readiness read - the retained path, byte for byte its old sequence"
else
    bad "(14a) retained: calls=[$(admin_args "$rt" | sub_key | tr '\n' ';')] rc=$(rc_of "$rt") reads=$(reads_before_admin "$rt")"
fi
fdx=$(at_world "$STANDBY" ARMED=true VALIDATOR_TYPE=frankendancer)
if [[ "$(admin_n "$fdx")" == "1" ]] && printf '%s\n' "$fdx" | grep -q '^EV: ADMIN fdctl set-identity ' && ! printf '%s\n' "$fdx" | grep -q "authorized-voter\|$FLAG"; then
    ok "(14b) armed + frankendancer: ONE fdctl set-identity ... --force, no authorized-voter call and no cold flag - the fdctl branch is unchanged"
else
    bad "(14b) frankendancer armed: $(printf '%s\n' "$fdx" | grep '^EV: ADMIN' | cut -c1-100 | tr '\n' ';')"
fi

# ── (15) CONTROLS: every mutant must turn its case red ────────────────────────────────────────────────────────────────────
echo ""; echo "─── (15) CONTROLS (mutate()): each mutant of the armed take turns its case red ───"
ctl_ok=1; ctl_rows=""
mw_state() { cat "$WORK/mw.state" 2>/dev/null; }
mw_label() { [[ "$(mw_state)" == "applied" ]] && echo GREEN || echo NOT-APPLIED; }   # GREEN = the mutant ran and the case did not bite; NOT-APPLIED = the sed expression matched nothing
mw() {   # mw <label> <sed expr> <at_world knobs…> -> the mutant world's output (rc 1 when the expression changed nothing)
    local lab="$1" expr="$2" m="$WORK/mut-$1.sh"; shift 2
    echo not-applied > "$WORK/mw.state"
    mutate "$STANDBY" "$expr" "$m" >/dev/null || return 1
    echo applied > "$WORK/mw.state"
    at_world "$m" "$@"
}
# 1 the shipped default flipped to armed / the shipped margin weakened: check (1) and the boundary (6a) read the SHIPPED values, so each turns red
c=$(mw default-armed 's/^AG_ARMED_TAKE=false$/AG_ARMED_TAKE=true/') && [[ "$(admin_n "$c")" -ge 1 ]] \
    && ctl_rows="$ctl_rows default-flipped:red" || { ctl_ok=0; ctl_rows="$ctl_rows default-flipped:$(mw_label)"; }
c=$(mw margin-default-weak 's/^AG_TAKE_MARGIN_SLOTS=200$/AG_TAKE_MARGIN_SLOTS=100/' ARMED=true OWN=800000 HOLDER=799801) && [[ "$(admin_n "$c")" -ge 1 ]] \
    && ctl_rows="$ctl_rows margin-default-weakened:red" || { ctl_ok=0; ctl_rows="$ctl_rows margin-default-weakened:$(mw_label)"; }
c=$(mw cmp-gt 's/^    \[\[ \$_ag_rdy_margin -ge \$AG_TAKE_MARGIN_SLOTS \]\]/    [[ $_ag_rdy_margin -gt $AG_TAKE_MARGIN_SLOTS ]]/' ARMED=true OWN=800000 HOLDER=799800 MARGIN=200) && [[ "$(admin_n "$c")" == "0" ]] \
    && ctl_rows="$ctl_rows margin-ge-to-gt:red" || { ctl_ok=0; ctl_rows="$ctl_rows margin-ge-to-gt:$(mw_label)"; }
c=$(mw swapped 's/^    _ag_rdy_margin=\$(( _own - _holder ))$/    _ag_rdy_margin=$(( _holder - _own ))/' ARMED=true) && [[ "$(admin_n "$c")" == "0" ]] \
    && ctl_rows="$ctl_rows operands-swapped:red" || { ctl_ok=0; ctl_rows="$ctl_rows operands-swapped:$(mw_label)"; }
c=$(mw noflag 's/ "\$_AG_COLD_FLAG" "\$STAKED_KEYPAIR"/ "$STAKED_KEYPAIR"/' ARMED=true) && [[ "$(admin_args "$c" | sub_key)" != "$EXPECT_ORDER" ]] \
    && ctl_rows="$ctl_rows flag-removed:red" || { ctl_ok=0; ctl_rows="$ctl_rows flag-removed:$(mw_label)"; }
c=$(mw order 's/authorized-voter add "\$STAKED_KEYPAIR" 2>&1); _rc=\$?$/@@V@@/;s/set-identity "\$_AG_COLD_FLAG" "\$STAKED_KEYPAIR" 2>&1); _rc=\$?$/authorized-voter add "$STAKED_KEYPAIR" 2>\&1); _rc=$?/;s/@@V@@/set-identity "$_AG_COLD_FLAG" "$STAKED_KEYPAIR" 2>\&1); _rc=$?/' ARMED=true) && [[ "$(admin_args "$c" | sub_key)" != "$EXPECT_ORDER" ]] \
    && ctl_rows="$ctl_rows order-swapped:red" || { ctl_ok=0; ctl_rows="$ctl_rows order-swapped:$(mw_label)"; }
c=$(mw nostop-on-fail 's/^                return 1$/                :/' ARMED=true ADD=fail) && [[ "$(admin_n "$c")" -ge 2 ]] \
    && ctl_rows="$ctl_rows voter-failure-ignored:red" || { ctl_ok=0; ctl_rows="$ctl_rows voter-failure-ignored:$(mw_label)"; }
c=$(mw present-refused 's/"\$out" != \*"already present"\*/"$out" != *"never-matches-this"*/' ARMED=true ADD=present) && [[ "$(admin_n "$c")" == "1" ]] \
    && ctl_rows="$ctl_rows already-present-refused:red" || { ctl_ok=0; ctl_rows="$ctl_rows already-present-refused:$(mw_label)"; }
c=$(mw any-failure-accepted 's/ || ( \$_rc -ne 0 && "\$out" != \*"already present"\* )//' ARMED=true ADD=fail) && [[ "$(admin_n "$c")" -ge 2 ]] \
    && ctl_rows="$ctl_rows any-voter-failure-accepted:red" || { ctl_ok=0; ctl_rows="$ctl_rows any-voter-failure-accepted:$(mw_label)"; }
c=$(mw polarity 's/^    if ! _ag_take_allowed; then$/    _ag_take_allowed; if [[ $? -eq 1 ]]; then/' ARMED=true UNDEF=1) && [[ "$(admin_n "$c")" -ge 1 ]] \
    && ctl_rows="$ctl_rows polarity-open:red" || { ctl_ok=0; ctl_rows="$ctl_rows polarity-open:$(mw_label)"; }
c=$(mw literal 's/^    if \[\[ "\${AG_ARMED_TAKE:-}" != "true" \]\]; then$/    if [[ "${AG_ARMED_TAKE:-}" == "false" ]]; then/' ARMED=yes) && [[ "$(admin_n "$c")" -ge 1 ]] \
    && ctl_rows="$ctl_rows literal-true-not-required:red" || { ctl_ok=0; ctl_rows="$ctl_rows literal-true-not-required:$(mw_label)"; }
c=$(mw finalized-fail-open 's/^    _canon_uint "\$_own" || { _ag_rdy_why="finalized \${_own}"; return 1; }$/    _canon_uint "$_own" || { _ag_rdy_why="finalized ${_own}"; return 0; }/' ARMED=true FIN=down) && [[ "$(admin_n "$c")" -ge 1 ]] \
    && ctl_rows="$ctl_rows finalized-failure-allows:red" || { ctl_ok=0; ctl_rows="$ctl_rows finalized-failure-allows:$(mw_label)"; }
c=$(mw holder-missing-open 's/^    _canon_uint "\$_holder" || { _ag_rdy_why="holder lastVote unavailable"; return 1; }$/    _canon_uint "$_holder" || { _ag_rdy_why="holder lastVote unavailable"; return 0; }/' ARMED=true HOLDER=) && [[ "$(admin_n "$c")" -ge 1 ]] \
    && ctl_rows="$ctl_rows holder-missing-allows:red" || { ctl_ok=0; ctl_rows="$ctl_rows holder-missing-allows:$(mw_label)"; }
c=$(mw nodry 's/^        if _ag_mode; then$/        if false; then/' ARMED=true DRY_RUN=true) && [[ "$(page_head "$c")" != "[DRY RUN] WOULD TAKE STAKED (Alpenglow cold take)" ]] \
    && ctl_rows="$ctl_rows dry-title-lost:red" || { ctl_ok=0; ctl_rows="$ctl_rows dry-title-lost:$(mw_label)"; }
c=$(mw nofields 's/ - \$(_ag_cold_take_fields "\$_ag_vh_before")" "\$STAKED_PUBKEY" "TOOK STAKED ✅"/" "$STAKED_PUBKEY" "TOOK STAKED ✅"/' ARMED=true) && ! has "$(printf '%s\n' "$c" | grep -m1 '^EV: PAGE ')" "cold take: empty history" \
    && ctl_rows="$ctl_rows took-fields-dropped:red" || { ctl_ok=0; ctl_rows="$ctl_rows took-fields-dropped:$(mw_label)"; }
c=$(mw margin-read-twice 's/^    _own=\$(_ag_slot_final)$/    _own=$(_ag_slot_final); _own=$(_ag_slot_final)/' ARMED=true) && [[ "$(reads_before_admin "$c")" != "1" ]] \
    && ctl_rows="$ctl_rows second-read-seen-by-A8-census:red" || { ctl_ok=0; ctl_rows="$ctl_rows second-read-seen-by-A8-census:$(mw_label)"; }
if [[ $ctl_ok -eq 1 ]]; then ok "(15) every mutant turns its case red:$ctl_rows"; else bad "(15) a control is not red (GREEN = the mutant ran and the case does not bite; NOT-APPLIED = the sed expression matched nothing):$ctl_rows"; fi

# ── (16) the REAL chain ─────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (16) the real chain (attempt_takeover -> the liveness gate -> take_staked_identity): the margin reads the baseline the gate accepted; a held take is decided again at the next decision point ───"
fc=$(ag3_sb "$STANDBY" ARMED=true)
fcp=$(printf '%s\n' "$fc" | grep -m1 '^EV: PAGE ')
if [[ "$(admin_n "$fc")" == "2" && "$(admin_args "$fc" | sub_key)" == "$EXPECT_ORDER" && "$(evn "$fc" 'TAKE-EXIT rc=0')" == "1" && "$(page_head "$fc")" == "TOOK STAKED ✅" && "$(page_n "$fc")" == "1" && "$(evn "$fc" 'NET CURLBIN')" == "0" && "$(evn "$fc" 'READ EXT')" == "0" ]] \
   && has "$fcp" "holder lastVote 5000;"; then
    ok "(16a) armed, every REAL gate open (episode, delay, liveness, the fresh proof, veto): 'authorized-voter add' then the cold 'set-identity', ONE page 'TOOK STAKED ✅' whose 'holder lastVote 5000' is the baseline the real liveness gate built from its own samples; no curl binary, no external read"
else
    bad "(16a) armed full chain: admin=$(admin_n "$fc") calls=[$(admin_args "$fc" | sub_key | tr '\n' ';')] exits=$(evn "$fc" 'TAKE-EXIT rc=0') pages=$(page_n "$fc") head=$(page_head "$fc") :: ${fcp:0:240}"
fi
own=$(printf '%s' "$fcp" | sed -n 's/.*floor = own root \([0-9][0-9]*\);.*/\1/p')
if [[ "$own" =~ ^[0-9]+$ ]]; then
    lvh=$(( own - 100 ))
    fh=$(ag3_sb "$STANDBY" ARMED=true LV=$lvh)
    fhp=$(printf '%s\n' "$fh" | grep -m1 '^EV: PAGE ')
    if [[ "$(admin_n "$fh")" == "0" && "$(page_n "$fh")" == "1" && "$(evn "$fh" 'TAKE-EXIT rc=1')" == "1" && "$(page_head "$fh")" == "TAKEOVER WITHHELD — Alpenglow mode 🚨" ]] \
       && has "$fhp" "ARMED, but the readiness margin held the take: own finalized ${own}, holder lastVote ${lvh}, margin 100 &lt; AG_TAKE_MARGIN_SLOTS=200: nothing was done"; then
        ok "(16b) the same chain with the holder's lastVote ${lvh} (100 slots under the spare's finalized ${own}): the real take path HOLDS - zero admin calls, ONE page naming own ${own} / holder ${lvh} / margin 100 < 200"
    else
        bad "(16b) margin hold in the real chain: admin=$(admin_n "$fh") pages=$(page_n "$fh") head=$(page_head "$fh") :: ${fhp:0:300}"
    fi
    fr=$(ag3_sb "$STANDBY" ARMED=true LV=$lvh HZ=200)
    frh=$(printf '%s\n' "$fr" | grep '^EV: PAGE ' | sed 's/^EV: PAGE [^<]*<b>//; s/<\/b>.*//' | tr '\n' ';')
    m2=$(printf '%s\n' "$fr" | grep '^EV: PAGE ' | tail -1 | sed -n 's/.*margin \([0-9][0-9]*\) slots; vote history.*/\1/p')
    if [[ "$(admin_n "$fr")" == "2" && "$(admin_args "$fr" | sub_key)" == "$EXPECT_ORDER" && "$frh" == "TAKEOVER WITHHELD — Alpenglow mode 🚨;TOOK STAKED ✅;" && "$m2" =~ ^[0-9]+$ ]] && [[ "$m2" -ge 200 && "$m2" -gt 100 ]]; then
        ok "(16c) the page's promise holds: ARMED and held at margin 100, the spare is not asked again - the next decision point (the cooldown later) finds the margin at ${m2} (>= 200, the holder's lastVote frozen while the spare's root advanced) and TAKES: pages '${frh}', the two admin calls in order"
    else
        bad "(16c) held then re-decided: admin=$(admin_n "$fr") pages=[$frh] margin-at-take=[$m2]"
    fi
else
    bad "(16b,c) the armed chain world gave no 'floor = own root <N>' to derive the held case from: ${fcp:0:240}"
fi
un=$(ag3_sb "$STANDBY" HZ=200)
if [[ "$(admin_n "$un")" == "0" && "$(evn "$un" 'PAGE')" -ge 1 ]]; then
    ok "(16d) the same chain NOT armed (the default), run twice as long: still zero admin calls - the margin is only ever asked when the knob is true"
else
    bad "(16d) unarmed chain, 200 s: admin=$(admin_n "$un") pages=$(evn "$un" 'PAGE')"
fi

results_banner
