#!/bin/bash
# v0.7 (AG-1.2): AG MODE ON EVERY TAKE PATH (G1, G2, G10). In Alpenglow mode FO never takes the staked identity automatically:
#   - take_staked_identity (standby) and switch_to_staked (primary, RECOVERY_MODE=rpc) return 1 right after the own-view veto - before the
#     DRY_RUN branch, the keypair test and every admin-socket call (set-identity, authorized-voter, fdctl) - and page ONCE per episode
#     ("TAKEOVER WITHHELD" / "RECOVERY WITHHELD"), carrying every field the operator needs; the page repeats at most once per ALERT_THROTTLE
#     while the same episode lasts, and again after the episode closes (_own_view_reset clears the marker at EVERY episode-close site);
#   - _prewarm_voter_add (the delay window - it runs BEFORE the take path and its veto) returns first, before the PREWARM_VOTER_ADD gate;
#   - the daemons say at startup that PREWARM_VOTER_ADD=true / RECOVERY_MODE=rpc cannot act in Alpenglow mode (the daemon still starts);
#   - the standby says at startup, in the log only, that a MAX_DELINQUENT_SLOTS of 1..23 is below the Alpenglow preset 24 (no page, the daemon still starts);
#   - the agave flag that switches the vote-history requirement off is named in no shipped script but the standby's ONE armed set-identity (AG-3.3; tests/test_ag_armed_take.sh).
# EVERY GATE BEFORE THE STOP RUNS AS TODAY (the episode, the delay, the external confirm, the fence, the fresh re-check, the veto): the page means
# "every gate FO has said the take would happen now" - a gate that holds produces NO AG page.
# The worlds are the act-then-alert idiom (tests/test_act_then_alert.sh): the REAL attempt_takeover -> take_staked_identity and the REAL
# attempt_safe_recovery -> switch_to_staked over a simulated clock, an ordered event log (ADMIN = any call of the agave-validator / fdctl stubs,
# PAGE = a Telegram message, READ = a LOCAL request, LOG = an [ag] / [prewarm] log line) and a logging curl binary first in PATH.
# THIS suite runs the REAL _ag_mode (AGMODE=real); the world "AGMODE=off" is the retained path the OTHER suites test (tests/lib/harness.sh
# harness_ag_off) - the pair shows that the shadow matters: the same world takes in one and pages in the other.
#   (1) STANDBY, every gate open: ZERO admin calls, ONE page, every field (and the shadowed world: the take happens)
#   (2) the page's fields over their states: getHealth behind / UNKNOWN, version below, VAT not admitted, a failed read, the history file present
#   (3) the stop's place: DRY_RUN, a missing keypair, frankendancer - none reached; a holding gate (a voting veto, an aborting re-check) - no AG page
#   (4) the episode: one page, the decision points spaced by the cooldown, a repeat after ALERT_THROTTLE, a new page after the episode closes
#   (5) PRIMARY (RECOVERY_MODE=rpc): the same, role "primary"; the stamp spaces the passes
#   (6) _prewarm_voter_add: no admin call, one log line, _prewarm_reset never armed; the shadowed world adds - and DRY_RUN with and without the shadow
#   (7) the startup warnings, and the standby's drift note for a MAX_DELINQUENT_SLOTS below the preset (log only; 6 controls)
#   (8) STRUCTURE by bash's text: the stop's place in each take function, the prewarm's first statement, the marker's three writers, the page's
#       reads (LOCAL, curl -m 3, one spelling), the cold flag named once in the standby only, the shadow census of the other suites
#   (9) CONTROLS (mutate()): each stop removed, the marker never cleared, a page at every decision point, the stop after the DRY_RUN branch /
#       the keypair test, no pacing stamp, a dropped page field
# RED ON THE BASE (the AG-1.4 tree + this suite): the real take_staked_identity and switch_to_staked, every gate open, call set-identity and
# authorized-voter add, the prewarm adds the staked voter, and there is no page; after the change: zero admin calls and one page.
#
# harness: tests/lib/harness.sh - load_seam, harness_clock_shims, harness_stub_dir, harness_ag_off, field, mutate, ok/bad+banners.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
title_banner "AG mode on every take path: the stops, the page, the episode (v0.7 AG-1.2)"

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
        getSlotFinal) printf '{"jsonrpc":"2.0","id":1,"result":%s}' "$(( hc - 32 ))" ;;
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
ag_stubs() {   # ag_stubs <dir> - a curl BINARY that logs and fails (the net guard), and the admin CLIs that log EVERY call
    cat > "$1/curl" <<'EOS'
#!/bin/sh
printf 'NET CURLBIN %s\n' "$*" | cut -c1-120 >> "$_EVT_FILE"
exit 7
EOS
    cat > "$1/agave-validator" <<'EOS'
#!/bin/sh
printf 'ADMIN agave-validator %s\n' "$*" | cut -c1-160 >> "$_EVT_FILE"
exit 0
EOS
    cat > "$1/fdctl" <<'EOS'
#!/bin/sh
printf 'ADMIN fdctl %s\n' "$*" | cut -c1-160 >> "$_EVT_FILE"
exit 0
EOS
    chmod +x "$1/curl" "$1/agave-validator" "$1/fdctl"
    harness_stub_dir "$1"
}

# ── the STANDBY world: the REAL attempt_takeover -> take_staked_identity (+ _prewarm_voter_add) over a timeline ──
# ag_sb <script> [knob=value …]: AGMODE=real|off, DRY_RUN, VALIDATOR_TYPE, KP=ok|empty, VH=absent|present, HZ (last second), CLOSE_AT="<t> …" (episode
# closes: the REAL window_reset, then a fresh episode), PREWARM_VOTER_ADD, COOLDOWN, THROTTLE, OVMODE, HMODE, VMODE, VATMODE, AMODE, AGDOWN, FRESH=advance.
ag_sb() {
    local script="$1"; shift
    (
    set +e
    load_seam "$script"
    EVT=$(mktemp); export _EVT_FILE="$EVT"
    STUB=$(mktemp -d); ag_stubs "$STUB"; PATH="$STUB:$PATH"
    KPF=$(mktemp); echo '[1]' > "$KPF"
    trap 'rm -f "$KPF" "$EVT"; rm -rf "$STUB"' EXIT
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; STAKED_KEYPAIR="$KPF"
    LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"; CONFIG_TOML="$WORK/config.toml"
    SOLANA_PATH="$STUB"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
    TAKEOVER_DELAY=$DELAY; EXTERNAL_CONFIRM_THROTTLE=0
    VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0; VOTE_LIVENESS_MIN_SPAN=$SPAN
    GOSSIP_VERIFY=false; WITNESS_FASTPATH=false; DRY_RUN=false; TG_ENABLED=false; PREWARM_VOTER_ADD=false; MIN_VALIDATOR_VERSION=4.4.0
    local AGMODE=real HZ=$(( DELAY + 5 )) COOLDOWN=120 THROTTLE=600 VH=absent KP=ok CLOSE_AT="" FRESH="" kv
    OVMODE=pass; HMODE=ok; VMODE=ok; VATMODE=admitted; AMODE=full; AGDOWN=""
    for kv in "$@"; do eval "$kv"; done
    TAKEOVER_COOLDOWN=$COOLDOWN; ALERT_THROTTLE=$THROTTLE; LEDGER_PATH="$WORK/ledger-$VH"
    [[ "$KP" == "empty" ]] && : > "$KPF"
    [[ "$AGMODE" == "off" ]] && HARNESS_AG_REAL=0 harness_ag_off
    harness_clock_shims
    log(){ :;}; log_error(){ :;}
    log_info(){ case "$1" in *"[ag]"*|*"[prewarm]"*) printf 'LOG %s\n' "${1:0:200}" >> "$_EVT_FILE" ;; esac; }
    log_warn(){ case "$1" in *"[ag]"*|*"[prewarm]"*) printf 'LOG %s\n' "${1:0:200}" >> "$_EVT_FILE" ;; esac; }
    send_telegram(){ local t="${1//$'\n'/ ⏎ }"; printf 'PAGE %s\n' "$t" >> "$_EVT_FILE"; return 0; }
    send_webhook(){ printf 'HOOK %s\n' "${3:-}" >> "$_EVT_FILE"; return 0; }
    save_state(){ printf 'SAVE\n' >> "$_EVT_FILE"; }; sleep(){ :;}
    get_local_identity(){ echo "$STAKED_PUBKEY"; }
    timeout(){ [[ "$1" == "-k" ]] && shift 2; shift; "$@"; }
    confirm_delinquency_external(){ return 0; }
    get_staked_liveness_sample(){
        local off=$(( _SIM_NOW - T0 ))
        if [[ "$FRESH" == "advance" && ${_IN_TAKE:-0} -eq 1 ]]; then printf '5001 %s T2\n' $(( 900000 + off )); return 0; fi
        printf '5000 %s T2\n' $(( 900000 + off )); return 0
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

# ── the PRIMARY world: the REAL attempt_safe_recovery -> switch_to_staked (RECOVERY_MODE=rpc) ───────────────────
# ag_pr <script> [knob=value …]: AGMODE, DRY_RUN, VALIDATOR_TYPE, KP, VH, HZ, CLOSE_AT, COOLDOWN (RECOVERY_COOLDOWN), THROTTLE, and the read knobs.
ag_pr() {
    local script="$1"; shift
    (
    set +e
    load_seam "$script"
    EVT=$(mktemp); export _EVT_FILE="$EVT"
    STUB=$(mktemp -d); ag_stubs "$STUB"; PATH="$STUB:$PATH"
    KPF=$(mktemp); echo '[1]' > "$KPF"
    trap 'rm -f "$KPF" "$EVT"; rm -rf "$STUB"' EXIT
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"; STAKED_KEYPAIR="$KPF"
    LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"; CONFIG_TOML="$WORK/config.toml"
    SOLANA_PATH="$STUB"; VALIDATOR_TYPE="agave"; SETIDENTITY_TIMEOUT=15
    RECOVERY_DELAY=$DELAY; RECOVERY_CHECKS=1; RECOVERY_CHECK_INTERVAL=0
    VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=$MININT; VOTE_LIVENESS_EPSILON=0; VOTE_LIVENESS_MIN_SPAN=$SPAN
    DRY_RUN=false; TG_ENABLED=false; MIN_VALIDATOR_VERSION=4.4.0
    local AGMODE=real HZ=$(( DELAY + SPAN + 5 )) COOLDOWN=30 THROTTLE=600 VH=absent KP=ok CLOSE_AT="" kv
    OVMODE=pass; HMODE=ok; VMODE=ok; VATMODE=admitted; AMODE=full; AGDOWN=""
    for kv in "$@"; do eval "$kv"; done
    RECOVERY_COOLDOWN=$COOLDOWN; ALERT_THROTTLE=$THROTTLE; LEDGER_PATH="$WORK/ledger-$VH"
    [[ "$KP" == "empty" ]] && : > "$KPF"
    [[ "$AGMODE" == "off" ]] && HARNESS_AG_REAL=0 harness_ag_off
    harness_clock_shims
    log(){ :;}; log_error(){ :;}
    log_info(){ case "$1" in *"[ag]"*) printf 'LOG %s\n' "${1:0:200}" >> "$_EVT_FILE" ;; esac; }
    log_warn(){ case "$1" in *"[ag]"*) printf 'LOG %s\n' "${1:0:200}" >> "$_EVT_FILE" ;; esac; }
    send_telegram(){ local t="${1//$'\n'/ ⏎ }"; printf 'PAGE %s\n' "$t" >> "$_EVT_FILE"; return 0; }
    send_webhook(){ printf 'HOOK %s\n' "${3:-}" >> "$_EVT_FILE"; return 0; }
    save_state(){ printf 'SAVE\n' >> "$_EVT_FILE"; }; sleep(){ :;}
    get_local_identity(){ echo "$STAKED_PUBKEY"; }
    timeout(){ [[ "$1" == "-k" ]] && shift 2; shift; "$@"; }
    tier1_check_delinquency(){ _t1_holder_lv=5000; return 1; }
    _check_rpc_delinquency(){ return 1; }
    check_standby_has_identity(){ return 1; }
    get_staked_liveness_sample(){ printf '5000 %s T2\n' $(( 900000 + _SIM_NOW - T0 )); return 0; }
    curl(){ ag_curl "$@"; }
    eval "$(declare -f switch_to_staked | sed '1s/^switch_to_staked/_real_switch_to_staked/')"
    switch_to_staked(){ printf 'TAKE-ENTER t=%s\n' $(( _SIM_NOW - T0 )) >> "$_EVT_FILE"; _real_switch_to_staked "$@"; local _r=$?; printf 'TAKE-EXIT rc=%s\n' "$_r" >> "$_EVT_FILE"; return $_r; }
    ag_episode() {
        _recovery_confirm_count=0; _standby_alert_sent=""; _last_recovery_log=0
        _liveness_first_vote=""; _liveness_first_tip=""; _liveness_first_ts=0; _liveness_first_provider=""
        _last_blind_end=0; _liveness_obs_since=0
    }
    CURRENT_IDENTITY="U1"; LAST_SWITCH_TIME=$(( T0 - 1000 )); ag_episode
    local t closes=" $CLOSE_AT "
    for ((t = 0; t <= HZ; t++)); do
        _SIM_NOW=$(( T0 + t ))
        case "$closes" in *" $t "*) _own_view_reset; printf 'CLOSE t=%s\n' "$t" >> "$_EVT_FILE"; ag_episode ;; esac   # the primary's episode-close sites (a demote, a recovery, a manual change) all call _own_view_reset
        _own_head_sample >/dev/null 2>&1
        attempt_safe_recovery >/dev/null 2>&1
        grep -q '^ADMIN.* set-identity' "$EVT" && break
    done
    sed 's/^/EV: /' "$EVT"
    printf 'STATE=lst=%s|pagets=%s|now=%s\n' "$LAST_SWITCH_TIME" "$_ag_page_ts" "$_SIM_NOW"
    )
}
page_of() { printf '%s\n' "$1" | grep -m1 '^EV: PAGE '; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
st() { printf '%s\n' "$1" | grep '^STATE=' | sed 's/^STATE=//'; }
agp() { evn "$1" 'PAGE .*WITHHELD'; }                                   # agp <out> - the AG pages
heads() { printf '%s\n' "$1" | grep '^EV: PAGE ' | sed 's/^EV: PAGE [^<]*<b>//; s/<\/b>.*//' | cut -c1-40 | tr '\n' ';'; }   # heads <out> - every page's status
dp() { evn "$1" 'LOG .*\[ag\] [a-z]*: take '; }   # dp <out> - the AG decision points (each logs one "[ag] <role>: take withheld|WITHHELD ..." line; the "[ag] armed take: held" line of AG-3 is the predicate's, not a decision point of its own)   # st <world output> - the STATE record, for field
miss=""

# ── (1) STANDBY, every gate open ──────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) STANDBY: every gate passes - zero admin calls, ONE page with every field; the shadowed world takes ───"
out=$(ag_sb "$STANDBY")
pg=$(page_of "$out")
if [[ "$(evn "$out" 'ADMIN')" == "0" && "$(evn "$out" 'PAGE')" == "1" && "$(evn "$out" 'TAKE-EXIT rc=1')" == "1" && "$(evn "$out" 'NET CURLBIN')" == "0" ]]; then
    ok "(1a) the real take path, all gates open: take_staked_identity returned 1 once; ZERO admin-socket calls of any kind (no set-identity, no authorized-voter, no fdctl); ONE page; no curl binary ran"
else
    bad "(1a) admin=$(evn "$out" 'ADMIN') pages=$(evn "$out" 'PAGE') exits=$(evn "$out" 'TAKE-EXIT rc=1') curlbin=$(evn "$out" 'NET CURLBIN') :: $(printf '%s\n' "$out" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-120 | head -4 | tr '\n' ';')"
fi
miss=""
for f in "TAKEOVER WITHHELD — Alpenglow mode" "Delinquent" "this spare is NOT ARMED (AG_ARMED_TAKE=false): nothing was done" \
         "Holder silent" "since the episode's first liveness sample (lastVote 5000, cluster tip 9000" "provider T2" \
         "finalized slot 80" "getHealth ok" "validator ok (version 4.4.0, minimum 4.4.0)" "VAT admission: admitted (epoch 1074" \
         "Vote history $WORK/ledger-absent/vote_history-S1.bin: absent" \
         "Operator path: warm swap - demote the old holder first, then move the vote history (docs/SAFETY.md, Alpenglow). A cold take is an operator decision; FO never makes it."; do
    has "$pg" "$f" || miss="$miss [$f]"
done
[[ -z "$miss" ]] && ok "(1b) the page carries: the status, the take path's own reason, the verdict, the holder's silence with the first sample's lastVote / cluster tip / provider, this node's finalized slot, the getHealth class, the version against the minimum, the VAT admission, the history-file class and the operator path" \
                 || bad "(1b) the page lacks:$miss :: $pg"
[[ "$(evn "$out" 'HOOK TAKEOVER WITHHELD')" == "1" && "$(evn "$out" 'LOG .*WITHHELD')" == "1" ]] \
    && ok "(1c) the webhook carries the same status; one [ag] WITHHELD log line" || bad "(1c) hook/log: $(printf '%s\n' "$out" | grep -E '^EV: (HOOK|LOG)' | cut -c1-120 | tr '\n' ';')"
[[ "$(field "$(st "$out")" ltt)" -gt 0 ]] \
    && ok "(1d) the take path stamped the cooldown (LAST_TAKEOVER_TIME=$(field "$(st "$out")" ltt)) - it spaces the decision points, the episode state is not reset" || bad "(1d) no cooldown stamp ($(st "$out"))"
sh_out=$(ag_sb "$STANDBY" AGMODE=off)
if [[ "$(evn "$sh_out" 'ADMIN agave-validator .*set-identity')" == "1" && "$(evn "$sh_out" 'ADMIN agave-validator .*authorized-voter add')" == "1" && "$(evn "$sh_out" 'PAGE')" -ge 1 && "$(evn "$sh_out" 'PAGE .*WITHHELD')" == "0" ]]; then
    ok "(1e) THE SAME WORLD WITH _ag_mode SHADOWED OFF (harness_ag_off - what every other suite runs): set-identity and authorized-voter add are called and the TOOK page goes out - the retained path is intact, and the shadow is what keeps the other suites meaningful"
else
    bad "(1e) shadowed world: $(printf '%s\n' "$sh_out" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-110 | head -5 | tr '\n' ';')"
fi
fd_out=$(ag_sb "$STANDBY" VALIDATOR_TYPE=frankendancer)
[[ "$(evn "$fd_out" 'ADMIN')" == "0" && "$(evn "$fd_out" 'PAGE .*WITHHELD')" == "1" ]] \
    && ok "(1f) VALIDATOR_TYPE=frankendancer: no fdctl call either - the stop is above both client branches" || bad "(1f) frankendancer: $(printf '%s\n' "$fd_out" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-110 | tr '\n' ';')"

# ── (2) the page's fields over their states ──────────────────────────────────────────────────────
echo ""; echo "─── (2) the page's fields: getHealth, version, VAT, a failed read, the history file ───"
chk_page() {   # chk_page <label> <substring> <ag_sb knobs…>
    local lab="$1" sub="$2" o; shift 2
    o=$(ag_sb "$STANDBY" "$@"); has "$(page_of "$o")" "$sub" && [[ "$(evn "$o" 'ADMIN')" == "0" ]] || bad "(2:$lab) the page lacks [$sub] :: $(page_of "$o" | cut -c1-600)"
}
chk_page health-behind "getHealth behind by 42 slots" HMODE=behind
chk_page health-unknown "getHealth UNKNOWN (agave answers Unknown while votor has seen no finalized slot" HMODE=unknown
chk_page health-garbage "getHealth unreadable (not a getHealth answer FO knows)" HMODE=garbage
chk_page version-low "validator not ready (version 4.3.2 is below the minimum 4.4.0)" VMODE=low
chk_page version-unreadable "validator not ready (the version is unreadable" VMODE=none
chk_page vat-notadmitted "NOT ADMITTED (epoch 1074: activated stake 5000000000 lamports but epochVoteAccount false" VATMODE=notadmitted
chk_page vat-lapse "the holder's silence is likely a VAT lapse, not a death" VATMODE=notadmitted
chk_page vat-reason "BLS key present; pending delegator rewards 5 lamports" VATMODE=notadmitted
chk_page vat-limit "this node jsonParsed has no blsPubkeyCompressed field - LIMIT" VATMODE=notadmitted AMODE=none
chk_page vat-unknown "VAT admission: unknown (entries=0" VATMODE=absent
chk_page history-present "vote_history-S1.bin: present (mtime=" VH=present
ok "(2a) over their states the page words each field: getHealth behind / UNKNOWN / unreadable, the version below the minimum / unreadable, the VAT admission not admitted (with the lapse sentence, the reason class and the LIMIT text of a missing field) / unknown, the history file present - and every one of those worlds made ZERO admin calls"
dn=$(ag_sb "$STANDBY" AGDOWN=1); pgd=$(page_of "$dn")
cnt=$(printf '%s' "$pgd" | grep -o 'unavailable (no answer from LOCAL_RPC)\|unreadable (no answer from LOCAL_RPC)\|unknown (no answer from LOCAL_RPC)' | wc -l | tr -d ' ')
if [[ "$(evn "$dn" 'PAGE')" == "1" && "$(evn "$dn" 'ADMIN')" == "0" && $cnt -ge 3 ]] && has "$pgd" "TAKEOVER WITHHELD" && has "$pgd" "Operator path: warm swap"; then
    ok "(2b) every page read fails (getSlot finalized, getHealth, getVersion, the VAT batch all rc 7): the page still goes out, $cnt fields (the slot, getHealth, the VAT admission) say 'no answer from LOCAL_RPC', the version says it is unreadable, and the verdict and the operator path are intact"
else
    bad "(2b) failed reads: pages=$(evn "$dn" 'PAGE') admin=$(evn "$dn" 'ADMIN') unavailable-fields=$cnt :: $(printf '%s' "$pgd" | cut -c1-500)"
fi
reads=$(printf '%s\n' "$out" | grep '^EV: READ' | sed 's/^EV: //' | sort | uniq -c | awk '{printf "%s×%s %s %s;", $1, $2, $3, $4}')
if [[ "$(evn "$out" 'READ EXT')" == "0" && "$(evn "$out" 'NET CURLBIN')" == "0" ]]; then
    ok "(2c) the page's reads are all LOCAL (no external request, no curl binary): $(printf '%s' "$reads" | cut -c1-200)"
else
    bad "(2c) a page read left the node: $reads"
fi

# ── (3) the stop's place: what it pre-empts, what holds before it ───────────────────────────────────
echo ""; echo "─── (3) the stop sits after the veto and before the DRY_RUN branch and the keypair test; a holding gate produces no AG page ───"
dr=$(ag_sb "$STANDBY" DRY_RUN=true)
[[ "$(evn "$dr" 'PAGE .*WITHHELD')" == "1" && "$(evn "$dr" 'PAGE .*WOULD TAKE')" == "0" && "$(evn "$dr" 'ADMIN')" == "0" ]] \
    && ok "(3a) DRY_RUN=true: the AG page, and NO '[DRY RUN] WOULD TAKE STAKED' - DRY_RUN mirrors the live decision, which is a withheld take" || bad "(3a) DRY_RUN: $(printf '%s\n' "$dr" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-110 | tr '\n' ';')"
dr_off=$(ag_sb "$STANDBY" DRY_RUN=true AGMODE=off)
[[ "$(evn "$dr_off" 'PAGE .*WOULD TAKE')" == "1" && "$(evn "$dr_off" 'ADMIN')" == "0" ]] \
    && ok "(3a') the shadowed DRY_RUN world reports WOULD TAKE and makes no admin call - the DRY_RUN guarantee the other suites hold" || bad "(3a') shadowed DRY_RUN: $(printf '%s\n' "$dr_off" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-110 | tr '\n' ';')"
ke=$(ag_sb "$STANDBY" KP=empty)
[[ "$(evn "$ke" 'PAGE .*WITHHELD')" == "1" && "$(evn "$ke" 'PAGE .*TAKEOVER BLOCKED')" == "0" && "$(evn "$ke" 'ADMIN')" == "0" ]] \
    && ok "(3b) an empty staked keypair: the AG page, no 'TAKEOVER BLOCKED' - the stop is above the keypair test" || bad "(3b) keypair: $(printf '%s\n' "$ke" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-110 | tr '\n' ';')"
ke_off=$(ag_sb "$STANDBY" KP=empty AGMODE=off)
[[ "$(evn "$ke_off" 'PAGE .*TAKEOVER BLOCKED')" -ge 1 && "$(evn "$ke_off" 'ADMIN')" == "0" ]] \
    && ok "(3b') the shadowed world blocks on the keypair with no admin call - the retained gate" || bad "(3b') shadowed keypair: $(printf '%s\n' "$ke_off" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-110 | tr '\n' ';')"
vo=$(ag_sb "$STANDBY" OVMODE=voting)
[[ "$(evn "$vo" 'PAGE .*WITHHELD')" == "0" && "$(evn "$vo" 'TAKE-EXIT rc=1')" -ge 1 && "$(evn "$vo" 'ADMIN')" == "0" ]] \
    && ok "(3c) a VOTING own-view veto holds the take BEFORE the stop: no AG page (the veto's own page, if any, is the existing one)" || bad "(3c) veto world: $(printf '%s\n' "$vo" | grep -E '^EV: (ADMIN|PAGE|TAKE)' | cut -c1-110 | tr '\n' ';')"
fr=$(ag_sb "$STANDBY" FRESH=advance)
[[ "$(evn "$fr" 'PAGE .*WITHHELD')" == "0" && "$(evn "$fr" 'ADMIN')" == "0" && "$(evn "$fr" 'PAGE .*ABORTED')" -ge 1 ]] \
    && ok "(3d) a fresh re-check that sees the holder VOTE aborts the take BEFORE the stop: the existing abort page, no AG page" || bad "(3d) fresh-recheck world: $(printf '%s\n' "$fr" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-110 | tr '\n' ';')"
nd=$(ag_sb "$STANDBY" HZ=$(( DELAY - 5 )))
[[ "$(evn "$nd" 'TAKE-ENTER')" == "0" && "$(evn "$nd" 'PAGE')" == "0" ]] \
    && ok "(3e) inside the takeover delay no take path is entered and nothing is paged - the gates before the stop run as they do today" || bad "(3e) delay world: $(printf '%s\n' "$nd" | grep -E '^EV: (TAKE|PAGE)' | cut -c1-110 | tr '\n' ';')"

# ── (4) the episode ───────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) one page per episode; decision points spaced by the cooldown; a repeat after ALERT_THROTTLE; a new page after the episode closes ───"
lg=$(ag_sb "$STANDBY" HZ=900)
np=$(agp "$lg"); nd=$(dp "$lg"); first=$(printf '%s\n' "$lg" | grep -m1 '^EV: TAKE-ENTER' | sed 's/.*t=//')
pt=$(printf '%s\n' "$lg" | awk '/^EV: TAKE-ENTER/ { sub(/.*t=/, ""); t = $0 } /^EV: PAGE .*WITHHELD/ { printf "%s ", t }' | sed 's/ $//')
if [[ "$np" == "2" && $nd -ge 6 && $nd -le 9 && "$(evn "$lg" 'ADMIN')" == "0" ]]; then
    ok "(4a) 900 s of one open episode: $nd decision points (the first at t=$first, then one per TAKEOVER_COOLDOWN 120 s), ZERO admin calls, exactly TWO AG pages (at the decision points t=$pt: the first, and the first one past ALERT_THROTTLE 600 s); every other decision point is a log line"
else
    bad "(4a) long episode: AG pages=$np decision-points=$nd admin=$(evn "$lg" 'ADMIN') (AG pages at decision points: $pt) all pages: $(heads "$lg")"
fi
cl=$(ag_sb "$STANDBY" HZ=400 CLOSE_AT="130")
np=$(agp "$cl"); pt=$(printf '%s\n' "$cl" | awk '/^EV: TAKE-ENTER/ { sub(/.*t=/, ""); t = $0 } /^EV: PAGE .*WITHHELD/ { printf "%s ", t }' | sed 's/ $//')
if [[ "$np" == "2" && "$(evn "$cl" 'ADMIN')" == "0" && "$(evn "$cl" 'CLOSE')" == "1" ]]; then
    ok "(4b) the episode CLOSES at t=130 (the real window_reset -> _own_view_reset) and a new one opens: the next decision point pages again at t=$pt - two pages in 400 s, far inside ALERT_THROTTLE - the marker ended with the episode"
else
    bad "(4b) episode close: AG pages=$np (at decision points $pt) admin=$(evn "$cl" 'ADMIN') all pages: $(heads "$cl")"
fi
nc=$(ag_sb "$STANDBY" HZ=400)
[[ "$(agp "$nc")" == "1" ]] && ok "(4b') the same 400 s WITHOUT the close: one AG page - the second page of (4b) is the close's doing" || bad "(4b') no-close control: AG pages=$(agp "$nc") all pages: $(heads "$nc")"
th=$(ag_sb "$STANDBY" HZ=500 THROTTLE=100 COOLDOWN=30)
[[ "$(agp "$th")" -ge 4 && "$(agp "$th")" -le 5 ]] && ok "(4c) ALERT_THROTTLE is the repeat interval: at THROTTLE=100 / COOLDOWN=30 the same open episode pages every ~100-120 s ($(agp "$th") AG pages in 500 s)" || bad "(4c) throttle knob: AG pages=$(agp "$th") all pages: $(heads "$th")"

# ── (5) PRIMARY ───────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (5) PRIMARY (RECOVERY_MODE=rpc): the same stop, role 'primary', the passes spaced by the stamp ───"
po=$(ag_pr "$PRIMARY"); ppg=$(page_of "$po")
if [[ "$(evn "$po" 'ADMIN')" == "0" && "$(evn "$po" 'PAGE')" == "1" && "$(evn "$po" 'TAKE-EXIT rc=1')" == "1" ]] && has "$ppg" "RECOVERY WITHHELD — Alpenglow mode" && has "$ppg" "Safe recovery:" \
   && has "$ppg" "Holder silent" && has "$ppg" "validator ok (version 4.4.0" && has "$ppg" "VAT admission: admitted" && has "$ppg" "Operator path: warm swap"; then
    ok "(5a) the real recovery pass, all gates open: switch_to_staked returned 1; ZERO admin calls; ONE page 'RECOVERY WITHHELD' with the recovery's own reason and the same fields"
else
    bad "(5a) primary: admin=$(evn "$po" 'ADMIN') pages=$(evn "$po" 'PAGE') :: $(printf '%s' "$ppg" | cut -c1-400)"
fi
po_off=$(ag_pr "$PRIMARY" AGMODE=off)
[[ "$(evn "$po_off" 'ADMIN agave-validator .*set-identity')" == "1" && "$(evn "$po_off" 'ADMIN agave-validator .*authorized-voter add')" == "1" ]] \
    && ok "(5a') the same world shadowed off re-takes: set-identity and authorized-voter add - the retained path is intact" || bad "(5a') shadowed primary: $(printf '%s\n' "$po_off" | grep -E '^EV: (ADMIN|PAGE)' | cut -c1-110 | tr '\n' ';')"
pdr=$(ag_pr "$PRIMARY" DRY_RUN=true); pke=$(ag_pr "$PRIMARY" KP=empty)
[[ "$(evn "$pdr" 'PAGE .*WITHHELD')" == "1" && "$(evn "$pdr" 'PAGE .*WOULD RECOVER')" == "0" && "$(evn "$pke" 'PAGE .*WITHHELD')" == "1" && "$(evn "$pke" 'PAGE .*RECOVERY BLOCKED')" == "0" && "$(evn "$pdr" 'ADMIN')$(evn "$pke" 'ADMIN')" == "00" ]] \
    && ok "(5b) DRY_RUN and an empty keypair: the AG page, no 'WOULD RECOVER' and no 'RECOVERY BLOCKED' - the stop is above both" || bad "(5b) primary DRY_RUN/keypair: $(printf '%s\n' "$pdr" | grep -E '^EV: PAGE' | cut -c1-90 | tr '\n' ';') :: $(printf '%s\n' "$pke" | grep -E '^EV: PAGE' | cut -c1-90 | tr '\n' ';')"
plg=$(ag_pr "$PRIMARY" HZ=900); nd=$(dp "$plg"); np=$(agp "$plg")
pt=$(printf '%s\n' "$plg" | awk '/^EV: TAKE-ENTER/ { sub(/.*t=/, ""); t = $0 } /^EV: PAGE .*WITHHELD/ { printf "%s ", t }' | sed 's/ $//')
if [[ "$np" == "2" && $nd -ge 5 && $nd -le $(( 900 / DELAY )) && "$(evn "$plg" 'ADMIN')" == "0" ]]; then
    ok "(5c) 900 s of one open recovery episode: $nd decision points (the stamp moves the recovery anchor: never more than one per RECOVERY_DELAY, here 60 s), ZERO admin calls, TWO AG pages (at t=$pt)"
else
    bad "(5c) primary long: AG pages=$np decision-points=$nd admin=$(evn "$plg" 'ADMIN') (AG pages at $pt) all pages: $(heads "$plg")"
fi
pcl=$(ag_pr "$PRIMARY" HZ=400 CLOSE_AT="150"); [[ "$(agp "$pcl")" == "2" && "$(evn "$pcl" 'ADMIN')" == "0" ]] \
    && ok "(5d) the recovery episode closes (_own_view_reset, the function every episode-close site calls) and reopens: the next pass pages again" || bad "(5d) primary close: AG pages=$(agp "$pcl") all pages: $(heads "$pcl")"

# ── (6) _prewarm_voter_add ────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) _prewarm_voter_add: the AG check is its first statement - no admin call, never armed ───"
pw=$(ag_sb "$STANDBY" PREWARM_VOTER_ADD=true HZ=$(( DELAY - 10 )))
if [[ "$(evn "$pw" 'ADMIN')" == "0" && "$(evn "$pw" 'LOG .*PREWARM_VOTER_ADD=true is inert')" == "1" && "$(field "$(st "$pw")" prewarm_done)" == "0" ]]; then
    ok "(6a) PREWARM_VOTER_ADD=true in the delay window: ZERO admin calls (no authorized-voter add), ONE inert log line over $(( DELAY - 10 )) cycles, _prewarm_done stays 0 (so _prewarm_reset is never armed)"
else
    bad "(6a) prewarm: $(printf '%s\n' "$pw" | grep -E '^EV: (ADMIN|LOG)|^STATE' | cut -c1-140 | tr '\n' ';')"
fi
pw_off=$(ag_sb "$STANDBY" PREWARM_VOTER_ADD=true AGMODE=off HZ=$(( DELAY - 10 )))
if [[ "$(evn "$pw_off" 'ADMIN agave-validator .*authorized-voter add')" == "1" && "$(field "$(st "$pw_off")" prewarm_done)" == "1" ]]; then
    ok "(6b) the same world shadowed off pre-warms: ONE 'authorized-voter add' (the retained lever), _prewarm_done=1"
else
    bad "(6b) shadowed prewarm: $(printf '%s\n' "$pw_off" | grep -E '^EV: (ADMIN|LOG)|^STATE' | cut -c1-140 | tr '\n' ';')"
fi
pw_np=$(ag_sb "$STANDBY" PREWARM_VOTER_ADD=false HZ=$(( DELAY - 10 )))
[[ "$(evn "$pw_np" 'LOG .*inert')" == "0" && "$(evn "$pw_np" 'ADMIN')" == "0" ]] \
    && ok "(6c) PREWARM_VOTER_ADD=false: no admin call and no inert line (the lever was off; the check does not talk)" || bad "(6c) prewarm off: $(printf '%s\n' "$pw_np" | grep -E '^EV: (ADMIN|LOG)' | cut -c1-110 | tr '\n' ';')"
pwd_real=$(ag_sb "$STANDBY" PREWARM_VOTER_ADD=true DRY_RUN=true HZ=$(( DELAY - 10 )))
pwd_off=$(ag_sb "$STANDBY" PREWARM_VOTER_ADD=true DRY_RUN=true AGMODE=off HZ=$(( DELAY - 10 )))
if [[ "$(evn "$pwd_real" 'ADMIN')" == "0" && "$(evn "$pwd_off" 'ADMIN')" == "0" && "$(evn "$pwd_real" 'LOG .*is inert')" == "1" && "$(evn "$pwd_off" 'LOG .*DRY RUN')" == "1" && "$(evn "$pwd_real" 'LOG .*DRY RUN')" == "0" ]]; then
    ok "(6d) THE GREEN-FOR-THE-WRONG-REASON PAIR: the DRY_RUN pre-warm world makes zero admin calls with and without the shadow - without it because AG mode stopped it ('is inert'), with it because DRY_RUN did ('[DRY RUN] would pre-warm'). An assertion of 'no admin call' cannot tell the two apart; the shadow keeps the existing DRY_RUN guarantee a test of DRY_RUN"
else
    bad "(6d) dry-run pair: real=[$(printf '%s\n' "$pwd_real" | grep -E '^EV: (ADMIN|LOG)' | cut -c1-90 | tr '\n' ';')] off=[$(printf '%s\n' "$pwd_off" | grep -E '^EV: (ADMIN|LOG)' | cut -c1-90 | tr '\n' ';')]"
fi

# ── (7) the startup warnings ──────────────────────────────────────────────────────────────────────
echo ""; echo "─── (7) startup: PREWARM_VOTER_ADD=true / RECOVERY_MODE=rpc say they cannot act in Alpenglow mode; a MAX_DELINQUENT_SLOTS below the preset is said once ───"
sw_run() {   # sw_run <script> <anchor> <var=val> <real|off> -> the number of warnings the ONE shipped statement prints
    local line; line=$(grep -F -m1 -e "$2" "$1")
    [[ -n "$line" ]] || { echo "NOSTMT"; return 0; }
    (
        set +e
        load_seam "$1"
        log_warn(){ printf 'WARN %s\n' "$1"; }
        eval "$3"
        [[ "$4" == "off" ]] && HARNESS_AG_REAL=0 harness_ag_off
        eval "$line"
    ) | grep -c '^WARN '
}
swp=$(sw_run "$STANDBY" 'INERT in Alpenglow mode' 'PREWARM_VOTER_ADD=true' real)
swp_f=$(sw_run "$STANDBY" 'INERT in Alpenglow mode' 'PREWARM_VOTER_ADD=false' real)
swp_o=$(sw_run "$STANDBY" 'INERT in Alpenglow mode' 'PREWARM_VOTER_ADD=true' off)
n_s=$(grep -c 'INERT in Alpenglow mode' "$STANDBY")
[[ "$swp" == "1" && "$swp_f" == "0" && "$swp_o" == "0" && "$n_s" == "1" ]] \
    && ok "(7a) standby: the ONE startup statement warns once for PREWARM_VOTER_ADD=true, never for false, and never when _ag_mode is shadowed off" || bad "(7a) standby startup warning: true=$swp false=$swp_f shadowed=$swp_o statements=$n_s"
swr=$(sw_run "$PRIMARY" 'cannot re-take in Alpenglow mode' 'RECOVERY_MODE=rpc' real)
swr_m=$(sw_run "$PRIMARY" 'cannot re-take in Alpenglow mode' 'RECOVERY_MODE=manual' real)
swr_o=$(sw_run "$PRIMARY" 'cannot re-take in Alpenglow mode' 'RECOVERY_MODE=rpc' off)
n_p=$(grep -c 'cannot re-take in Alpenglow mode' "$PRIMARY")
[[ "$swr" == "1" && "$swr_m" == "0" && "$swr_o" == "0" && "$n_p" == "1" ]] \
    && ok "(7b) primary: the ONE startup statement warns once for RECOVERY_MODE=rpc, never for manual, never when shadowed off - and the daemon does not refuse to start (a warning, no exit)" || bad "(7b) primary startup warning: rpc=$swr manual=$swr_m shadowed=$swr_o statements=$n_p"
sp_stmt=$(grep -F -m1 'cannot re-take in Alpenglow mode' "$PRIMARY"); ss_stmt=$(grep -F -m1 'INERT in Alpenglow mode' "$STANDBY")
[[ "$sp_stmt" != *"exit"* && "$ss_stmt" != *"exit"* && "$sp_stmt" != *"return"* ]] \
    && ok "(7c) neither statement exits or returns: an unmonitored primary is worse than one that cannot re-take" || bad "(7c) a startup statement can end the daemon: [$sp_stmt] [$ss_stmt]"

# The standby's drift note (AG-1 review round, Q4): an existing config keeps a MAX_DELINQUENT_SLOTS below the wizard's preset 24 - said once at start, LOG ONLY.
dn_run() {   # dn_run <script> <MAX_DELINQUENT_SLOTS> <real|off> -> the WARN / PAGE lines the ONE shipped function prints, and its return code (RC n)
    (
        set +e
        load_seam "$1"
        log_warn(){ printf 'WARN %s\n' "$1"; }
        alert(){ printf 'PAGE %s\n' "$1"; }
        alert_warn(){ printf 'PAGE %s\n' "$1"; }
        MAX_DELINQUENT_SLOTS="$2"
        [[ "$3" == "off" ]] && HARNESS_AG_REAL=0 harness_ag_off
        _delinq_drift_note
        echo "RC $?"
    ) 2>&1 | grep -E '^(WARN|PAGE|RC) '
}
dn_secs() { awk -v n="$1" 'BEGIN { printf "%.1f", n / 5 }'; }   # the seconds the text must carry, computed apart from the daemon: n slots at the fastest rate, 5 slots/s
dn_struct() {   # dn_struct <script> -> 0 when startup_checks calls the note exactly once, AFTER validate_numeric_config, and the function can neither exit, page nor fail
    local sc fb calls v_ln d_ln defs
    sc=$(sed -n '/^startup_checks() {/,/^}/p' "$1" | grep -v '^[[:space:]]*#')
    fb=$(sed -n '/^_delinq_drift_note() {/,/^}/p' "$1" | grep -v '^[[:space:]]*#')
    calls=$(printf '%s\n' "$sc" | grep -cE '^[[:space:]]*_delinq_drift_note([[:space:]]|$)')
    v_ln=$(printf '%s\n' "$sc" | grep -nE -m1 '^[[:space:]]*validate_numeric_config([[:space:]]|$)' | cut -d: -f1)
    d_ln=$(printf '%s\n' "$sc" | grep -nE -m1 '^[[:space:]]*_delinq_drift_note([[:space:]]|$)' | cut -d: -f1)
    defs=$(grep -c '^_delinq_drift_note() {' "$1")
    [[ "$calls" == "1" && "$defs" == "1" && -n "$v_ln" && -n "$d_ln" && "$v_ln" -lt "$d_ln" && -n "$fb" ]] || return 1
    [[ "$fb" != *"exit"* && "$fb" != *"alert"* && "$fb" != *"return 1"* ]]
}
dn_ok=1; dn_why=""; dn_rows=""
for n in 1 15 23; do
    o=$(dn_run "$STANDBY" "$n" real); s=$(dn_secs "$n"); w=$(printf '%s\n' "$o" | grep -m1 '^WARN ')
    if [[ "$(printf '%s\n' "$o" | grep -c '^WARN ')" == "1" && "$(printf '%s\n' "$o" | grep -c '^PAGE ')" == "0" && "$o" == *"RC 0"* \
          && "$w" == *"MAX_DELINQUENT_SLOTS=$n is below the Alpenglow preset 24"* && "$w" == *"a lag spike of ≥ $n slots (≈ $s s) counts as delinquency"* && "$w" == *"Log only"* ]]; then
        dn_rows="$dn_rows $n:warns(${s}s)"
    else
        dn_ok=0; dn_why="$dn_why $n:[$(printf '%s' "$o" | tr '\n' ';' | cut -c1-120)]"
    fi
done
for n in 0 24 25 100; do
    o=$(dn_run "$STANDBY" "$n" real)
    if [[ "$(printf '%s\n' "$o" | grep -c '^WARN ')" == "0" && "$o" == *"RC 0"* ]]; then dn_rows="$dn_rows $n:silent"; else dn_ok=0; dn_why="$dn_why $n:[$(printf '%s' "$o" | tr '\n' ';' | cut -c1-120)]"; fi
done
o=$(dn_run "$STANDBY" 15 off)
if [[ "$(printf '%s\n' "$o" | grep -c '^WARN ')" == "0" && "$o" == *"RC 0"* ]]; then dn_rows="$dn_rows 15-with-_ag_mode-shadowed-off:silent"; else dn_ok=0; dn_why="$dn_why 15-shadowed-off:[$(printf '%s' "$o" | tr '\n' ';' | cut -c1-120)]"; fi
[[ $dn_ok -eq 1 ]] && ok "(7d) the standby's MAX_DELINQUENT_SLOTS drift note: ONE log line for 1..23 (it names the value, the preset 24, the slots and the seconds computed apart as slots/5), nothing for 0 and for 24 and above, nothing when _ag_mode is shadowed off, never a page, rc 0:$dn_rows" \
    || bad "(7d) drift note:$dn_why"
if dn_struct "$STANDBY" && [[ "$(grep -c '_delinq_drift_note' "$PRIMARY")" == "0" ]]; then
    ok "(7e) startup_checks calls the note exactly once, after validate_numeric_config has normalized the knob; the function cannot exit, page or return 1; the primary has no such function (the knob exists in the standby only)"
else
    bad "(7e) drift note structure: standby=$(dn_struct "$STANDBY" && echo ok || echo BAD) primary mentions=$(grep -c '_delinq_drift_note' "$PRIMARY")"
fi
dn_mut() {   # dn_mut <label> <sed expr> <MAX_DELINQUENT_SLOTS> <real|off> -> the dn_run output of the MUTANT, or NOT-APPLIED when the expression changed nothing
    local m="$WORK/dn-$1.sh"
    mutate "$STANDBY" "$2" "$m" >/dev/null || { echo NOT-APPLIED; return 0; }
    dn_run "$m" "$3" "$4"
}
dn_cok=1; dn_c=""
o=$(dn_mut upper '/^_delinq_drift_note() {/,/^}/ s/ -lt \$_preset ]]/ -le $_preset ]]/' 24 real);      [[ "$o" == *"WARN "* ]]   && dn_c="$dn_c upper-bound-24-warns:red"   || { dn_cok=0; dn_c="$dn_c upper-bound:${o:0:12}"; }
o=$(dn_mut lower '/^_delinq_drift_note() {/,/^}/ s/ -ge 1 / -ge 0 /' 0 real);                          [[ "$o" == *"WARN "* ]]   && dn_c="$dn_c lower-bound-0-warns:red"    || { dn_cok=0; dn_c="$dn_c lower-bound:${o:0:12}"; }
o=$(dn_mut shadow '/^_delinq_drift_note() {/,/^}/ s/^    _ag_mode || return 0$/    :/' 15 off);             [[ "$o" == *"WARN "* ]]   && dn_c="$dn_c shadow-ignored:red"         || { dn_cok=0; dn_c="$dn_c shadow:${o:0:12}"; }
o=$(dn_mut preset '/^_delinq_drift_note() {/,/^}/ s/local _preset=24 /local _preset=15 /' 15 real);     [[ "$o" != *"WARN "* && "$o" != "NOT-APPLIED" ]] && dn_c="$dn_c preset-moved:red" || { dn_cok=0; dn_c="$dn_c preset:${o:0:12}"; }
o=$(dn_mut secs '/^_delinq_drift_note() {/,/^}/ s/MAX_DELINQUENT_SLOTS \* 10 \/ _AG_SLOTS_PER_S_FAST/MAX_DELINQUENT_SLOTS * 10 \/ 4/' 15 real); [[ "$o" == *"WARN "* && "$o" != *"(≈ 3.0 s)"* ]] && dn_c="$dn_c seconds-wrong:red" || { dn_cok=0; dn_c="$dn_c seconds:${o:0:12}"; }
o=$(dn_mut page '/^_delinq_drift_note() {/,/^}/ s/^    log_warn "/    alert "/' 15 real);                         [[ "$o" == *"PAGE "* ]]   && dn_c="$dn_c page-instead-of-log:red"  || { dn_cok=0; dn_c="$dn_c page:${o:0:12}"; }
m_nc="$WORK/dn-nocall.sh"
if mutate "$STANDBY" '/^startup_checks() {/,/^}/ s/^    _delinq_drift_note .*$/    :/' "$m_nc" >/dev/null && ! dn_struct "$m_nc"; then dn_c="$dn_c call-removed:red"; else dn_cok=0; dn_c="$dn_c call-removed:NOT-RED"; fi
[[ $dn_cok -eq 1 ]] && ok "(7f) controls: each mutant of the note turns its case red:$dn_c" || bad "(7f) a drift-note control is not red:$dn_c"

# ── (8) STRUCTURE ─────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) structure: the stop's place, the prewarm's first statement, the marker's writers, the page's reads, the flag, the shadow census ───"
fn_code() { sed -n "/^$2() {/,/^}/p" "$1" | grep -v '^[[:space:]]*#'; }   # fn_code <file> <fn> - the function's lines, comment lines gone
first_line() { grep -n -m1 -E -e "$2" <<< "$1" | cut -d: -f1; }              # first_line <text> <regex> - the line number of the first match ("" = none)
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); fn=take_staked_identity; [[ "$n" == "primary" ]] && fn=switch_to_staked
    body=$(fn_code "$scr" "$fn")
    # AG-3.1: the standby's stop asks the fail-closed predicate (`if ! _ag_take_allowed` - an undefined predicate withholds); B7.4: so does the primary's (`if ! _ag_primary_retake_allowed`)
    gre='^[[:space:]]*if ! _ag_primary_retake_allowed; then$'; gtxt="if ! _ag_primary_retake_allowed; then"; gwant='if!_ag_primary_retake_allowed;then'
    [[ "$n" == "standby" ]] && { gre='^[[:space:]]*if ! _ag_take_allowed; then$'; gtxt="if ! _ag_take_allowed; then"; gwant='if!_ag_take_allowed;then'; }
    lv=$(first_line "$body" '^[[:space:]]*_own_view_veto \|\| return 1$'); la=$(first_line "$body" "$gre")
    ld=$(first_line "$body" '"\$DRY_RUN" == "true"'); lk=$(first_line "$body" '-s "\$STAKED_KEYPAIR"'); ls=$(first_line "$body" '(timeout|fdctl|agave-validator).*set-identity')
    calls=$(grep -c '_ag_take_withheld "' <<< "$body")
    stamp=LAST_TAKEOVER_TIME; [[ "$n" == "primary" ]] && stamp=LAST_SWITCH_TIME
    want="${gwant}${stamp}=\$(mono_now);save_state_ag_take_withheld\"${n}\"\"\$reason\"return1fi"
    got=$(sed -n "${la},$(( la + 4 ))p" <<< "$body" | tr -d ' \n')
    if [[ -n "$lv" && -n "$la" && -n "$ld" && -n "$lk" && -n "$ls" && $lv -lt $la && $la -lt $ld && $la -lt $lk && $la -lt $ls && "$calls" == "1" && "$got" == "$want" ]]; then
        ok "(8a:$n) $fn: '$gtxt' stands after the veto (line $lv), before the DRY_RUN branch ($ld), the keypair test ($lk) and the first set-identity ($ls); its five lines are exactly the stamp, ONE _ag_take_withheld \"$n\" call and 'return 1'"
    else
        bad "(8a:$n) $fn order: veto=$lv ag=$la dry=$ld key=$lk set-identity=$ls calls=$calls got=[$got]"
    fi
done
pbody=$(fn_code "$STANDBY" _prewarm_voter_add); pfirst=$(printf '%s\n' "$pbody" | sed -n '2p')
[[ "$pfirst" == "    if ! _ag_prewarm_allowed; then" ]] && ok "(8b) _prewarm_voter_add: the first statement is 'if ! _ag_prewarm_allowed; then' (B7.4) - above the PREWARM_VOTER_ADD gate and every admin call" || bad "(8b) _prewarm_voter_add first statement: [$pfirst]"
mk_ok=1; mk_why=""
for scr in "$STANDBY" "$PRIMARY"; do
    w=$(grep -nE '^[[:space:]]*_ag_page_ts=' "$scr" | grep -v ':[[:space:]]*#' | sed 's/:.*//' | wc -l | tr -d ' ')
    in_reset=$(fn_code "$scr" _own_view_reset | grep -c '_ag_page_ts=0')
    in_take=$(fn_code "$scr" _ag_take_withheld | grep -c '_ag_page_ts=\$_now')
    [[ "$w" == "3" && "$in_reset" == "1" && "$in_take" == "1" ]] || { mk_ok=0; mk_why="$mk_why $(role_of "$scr"): writers=$w reset=$in_reset stamp=$in_take"; }
done
[[ $mk_ok -eq 1 ]] && ok "(8c) the AG page's episode marker _ag_page_ts has THREE writers in each daemon - its initial 0, the stamp in _ag_take_withheld, the clear in _own_view_reset (the function every episode-close site calls)" || bad "(8c) marker writers:$mk_why"
rd_ok=1; rd_why=""
for scr in "$STANDBY" "$PRIMARY"; do
    sb_=$(fn_code "$scr" _ag_slot_final); hb_=$(fn_code "$scr" _ag_health_text); tb=$(fn_code "$scr" _ag_take_withheld)
    [[ "$(grep -c 'curl' <<< "$sb_")" == "1" && "$sb_" == *'curl -s -m 3 "$LOCAL_RPC" -X POST'* && "$sb_" == *'"method":"getSlot","params":[{"commitment":"finalized"}]'* ]] || { rd_ok=0; rd_why="$rd_why $(role_of "$scr"): _ag_slot_final is not exactly one curl -m 3 getSlot{finalized} to LOCAL_RPC"; }
    [[ "$(grep -c 'curl' <<< "$hb_")" == "1" && "$hb_" == *'curl -s -m 3 "$LOCAL_RPC" -X POST'* && "$hb_" == *'"method":"getHealth"'* ]] || { rd_ok=0; rd_why="$rd_why $(role_of "$scr"): _ag_health_text is not exactly one curl -m 3 getHealth to LOCAL_RPC"; }
    [[ "$(grep -cE 'curl|wget|/dev/tcp|/dev/udp|\bnc\b|ssh |ping ' <<< "$tb")" == "0" ]] || { rd_ok=0; rd_why="$rd_why $(role_of "$scr"): _ag_take_withheld names a network primitive of its own"; }
    [[ "$(grep -c '_ag_slot_final' <<< "$tb")" == "1" && "$(grep -c '_ag_health_text' <<< "$tb")" == "1" ]] || { rd_ok=0; rd_why="$rd_why $(role_of "$scr"): _ag_take_withheld does not call each read helper exactly once"; }
done
[[ $rd_ok -eq 1 ]] && ok "(8d) the page's own reads: _ag_slot_final (getSlot{finalized}) and _ag_health_text (getHealth) are each exactly one 'curl -s -m 3 \"\$LOCAL_RPC\"' with a literal body, and _ag_take_withheld names no network primitive - the version, the VAT and the history reads are the AG-1.5 / 1.4 / 1.3 helpers, censused in their own suites" || bad "(8d) page reads:$rd_why"
# AG-3.3: the cold flag is named in the STANDBY exactly once (the _AG_COLD_FLAG definition; the banner and the call use the variable), at the one set-identity of the armed path, and in no other shipped script or template
fl_s=$(grep -cF -e "$FLAG" "$STANDBY")
fl_other=$(cd "$HARNESS_DIR" && grep -lF -e "$FLAG" ./*.sh systemd/*.sh systemd/*.skel ./*.env.example 2>/dev/null | grep -v 'solana-standby-failover.sh$' | tr '\n' ' ')
fl_site=$(fn_code "$STANDBY" take_staked_identity | grep -c 'set-identity "\$_AG_COLD_FLAG" "\$STAKED_KEYPAIR"')
fl_def=$(grep -c '^_AG_COLD_FLAG="--'"$FLAG"'"' "$STANDBY")
[[ "$fl_s" == "1" && "$fl_def" == "1" && "$fl_site" == "1" && -z "$fl_other" ]] \
    && ok "(8e) the cold flag is named in the standby ONCE (the _AG_COLD_FLAG definition), used at the ONE armed set-identity of take_staked_identity, and in no other shipped script or template" || bad "(8e) cold flag census: standby lines=$fl_s definition=$fl_def armed-site=$fl_site other-files=[$fl_other]"

# the shadow census of the OTHER suites. The census method: the full suite run on a tree whose _ag_mode logs its REAL caller (the suite, the function), no suite shadowed; the
# pinned lists below are what it found. REAL reach of a take path (take_staked_identity / switch_to_staked) => the suite is SHADOWED (calls harness_ag_off at least once);
# reach of _prewarm_voter_add only => PREWARM_ONLY (the AG check is the function's first statement and the lever is never set, so it changes nothing: the suite text names
# PREWARM_VOTER_ADD nowhere); names a take function but reaches nothing => NOT_REACHED. A suite that is on no list may not name a take function at all.
SHADOWED="test_act_then_alert.sh test_elapsed_provider.sh test_monitor_fence_integration.sh test_own_view.sh test_primary_demote_timeout.sh test_standby_take_reset.sh test_standby_take_timeout.sh"
PREWARM_ONLY="test_blindness_is_life.sh test_crossnode_timing.sh test_fastpath.sh test_fastpath_stagger.sh test_monotonic_timers.sh test_n3_takeover_anchor.sh test_provider_pinning.sh test_takeover_starvation.sh"
NOT_REACHED="test_backup_fence.sh test_connectivity_floor.sh test_primary_recovery_liveness.sh test_primary_silent_stake.sh test_required_fence.sh test_standby_fence.sh test_standby_selffence.sh test_unknown_identity_alert.sh test_v061_regressions.sh"
sh_ok=1; sh_why=""; sh_rows=""; sh_n=0
for f in "$HARNESS_DIR"/tests/test_*.sh; do
    b=$(basename "$f")
    [[ "$b" == "test_ag_take.sh" || "$b" == "test_ag_armed_take.sh" || "$b" == "test_block7_rc1.sh" ]] && continue   # the suites whose worlds run the REAL predicates (AG-3: the armed take's suite joins; B7.4: so does Block 7's, which drives the two AG stops with every gate before them mocked open)
    mentions=$(grep -cE 'attempt_takeover|attempt_safe_recovery|take_staked_identity|switch_to_staked|_prewarm_voter_add' "$f")
    shadows=$(grep -c 'harness_ag_off' "$f")
    pva=$(grep -c 'PREWARM_VOTER_ADD' "$f")
    case " $SHADOWED " in
        *" $b "*) sh_n=$(( sh_n + 1 )); [[ $shadows -ge 1 ]] || { sh_ok=0; sh_why="$sh_why $b:no-shadow"; }; sh_rows="$sh_rows $b:$shadows"; continue ;;
    esac
    case " $PREWARM_ONLY " in
        *" $b "*) [[ $pva -eq 0 && $mentions -ge 1 ]] || { sh_ok=0; sh_why="$sh_why $b:prewarm-only-claim(pva=$pva,mentions=$mentions)"; }; continue ;;
    esac
    case " $NOT_REACHED " in
        *" $b "*) [[ $mentions -ge 1 ]] || { sh_ok=0; sh_why="$sh_why $b:not-reached-but-names-nothing"; }; continue ;;
    esac
    [[ $mentions -eq 0 && $shadows -eq 0 ]] || { sh_ok=0; sh_why="$sh_why $b:unlisted(mentions=$mentions,shadows=$shadows)"; }
done
[[ $sh_ok -eq 1 ]] && ok "(8f) SHADOW CENSUS: the $sh_n suites whose worlds reach a REAL take path each call harness_ag_off (call counts:$sh_rows); the $(printf '%s' "$PREWARM_ONLY" | wc -w | tr -d ' ') PREWARM_ONLY suites name the pre-warm lever nowhere (its AG check changes nothing there); the $(printf '%s' "$NOT_REACHED" | wc -w | tr -d ' ') NOT_REACHED suites name a take function and never reach one; no other suite names a take function or shadows" || bad "(8f) shadow census:$sh_why"

# ── (9) CONTROLS ──────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) CONTROLS (mutate()): every mutant must turn its case red ───"
ctl_ok=1; ctl_rows=""
mw_state() { cat "$WORK/mw.state" 2>/dev/null; }   # what the last mut_world did: applied | not-applied (the file survives the $(...) subshell the controls run it in)
mw_label() { [[ "$(mw_state)" == "applied" ]] && echo GREEN || echo NOT-APPLIED; }   # a control that is not red: GREEN = the mutant ran and the case did not bite; NOT-APPLIED = the sed expression matched nothing
mut_world() {   # mut_world <label> <standby|primary> <sed expr> [knob …] -> echo the mutant world's output (rc 1 if the mutation changed nothing)
    local lab="$1" role="$2" expr="$3" m="$WORK/mut-$1-$2.sh" src="$STANDBY"; shift 3
    [[ "$role" == "primary" ]] && src="$PRIMARY"
    echo not-applied > "$WORK/mw.state"
    mutate "$src" "$expr" "$m" || return 1
    echo applied > "$WORK/mw.state"
    if [[ "$role" == "primary" ]]; then ag_pr "$m" "$@"; else ag_sb "$m" "$@"; fi
}
c=$(mut_world sb-stop standby '/^take_staked_identity() {/,/^}/ s/^    if ! _ag_take_allowed; then$/    if false; then/') && [[ "$(evn "$c" 'ADMIN agave-validator .*set-identity')" -ge 1 && "$(evn "$c" 'PAGE .*WITHHELD')" == "0" ]] \
    && ctl_rows="$ctl_rows sb-stop:red" || { ctl_ok=0; ctl_rows="$ctl_rows sb-stop:$(mw_label)"; }
c=$(mut_world pr-stop primary '/^switch_to_staked() {/,/^}/ s/^    if ! _ag_primary_retake_allowed; then$/    if false; then/') && [[ "$(evn "$c" 'ADMIN agave-validator .*set-identity')" -ge 1 && "$(evn "$c" 'PAGE .*WITHHELD')" == "0" ]] \
    && ctl_rows="$ctl_rows pr-stop:red" || { ctl_ok=0; ctl_rows="$ctl_rows pr-stop:$(mw_label)"; }
c=$(mut_world prewarm standby '/^_prewarm_voter_add() {/,/^}/ s/^    if ! _ag_prewarm_allowed; then$/    if false; then/' PREWARM_VOTER_ADD=true HZ=$(( DELAY - 10 ))) && [[ "$(evn "$c" 'ADMIN agave-validator .*authorized-voter add')" == "1" ]] \
    && ctl_rows="$ctl_rows prewarm-stop:red" || { ctl_ok=0; ctl_rows="$ctl_rows prewarm-stop:$(mw_label)"; }
c=$(mut_world marker standby 's/^    _ag_page_ts=0   # v0\.7 (AG-1\.2).*$/    :/' HZ=400 CLOSE_AT="130") && [[ "$(agp "$c")" == "1" ]] \
    && ctl_rows="$ctl_rows marker-never-cleared:red" || { ctl_ok=0; ctl_rows="$ctl_rows marker-never-cleared:$(mw_label)"; }
c=$(mut_world throttle standby '/^_ag_take_withheld() {/,/^}/ s/ -lt \${ALERT_THROTTLE:-600} \]\]; then$/ -lt 0 ]]; then/' HZ=900) && [[ "$(agp "$c")" -ge 6 ]] \
    && ctl_rows="$ctl_rows page-every-decision:red" || { ctl_ok=0; ctl_rows="$ctl_rows page-every-decision:$(mw_label)"; }
c=$(mut_world after-dry standby '/^take_staked_identity() {/,/^}/ s/^    if ! _ag_take_allowed; then$/    if ! _ag_take_allowed \&\& [[ "$DRY_RUN" != "true" ]]; then/' DRY_RUN=true) && [[ "$(evn "$c" 'PAGE .*WOULD TAKE')" -ge 1 && "$(evn "$c" 'PAGE .*WITHHELD')" == "0" ]] \
    && ctl_rows="$ctl_rows stop-below-DRY_RUN:red" || { ctl_ok=0; ctl_rows="$ctl_rows stop-below-DRY_RUN:$(mw_label)"; }
c=$(mut_world after-key standby '/^take_staked_identity() {/,/^}/ s/^    if ! _ag_take_allowed; then$/    if ! _ag_take_allowed \&\& [[ -s "$STAKED_KEYPAIR" ]]; then/' KP=empty) && [[ "$(evn "$c" 'PAGE .*TAKEOVER BLOCKED')" -ge 1 && "$(evn "$c" 'PAGE .*WITHHELD')" == "0" ]] \
    && ctl_rows="$ctl_rows stop-below-keypair:red" || { ctl_ok=0; ctl_rows="$ctl_rows stop-below-keypair:$(mw_label)"; }
c=$(mut_world pr-after-dry primary '/^switch_to_staked() {/,/^}/ s/^    if ! _ag_primary_retake_allowed; then$/    if ! _ag_primary_retake_allowed \&\& [[ "$DRY_RUN" != "true" ]]; then/' DRY_RUN=true) && [[ "$(evn "$c" 'PAGE .*WOULD RECOVER')" -ge 1 && "$(evn "$c" 'PAGE .*WITHHELD')" == "0" ]] \
    && ctl_rows="$ctl_rows primary-stop-below-DRY_RUN:red" || { ctl_ok=0; ctl_rows="$ctl_rows primary-stop-below-DRY_RUN:$(mw_label)"; }
c=$(mut_world nostamp standby '/^take_staked_identity() {/,/^}/ s/^        LAST_TAKEOVER_TIME=\$(mono_now); save_state$/        :/' HZ=900) && [[ "$(dp "$c")" -ge 30 ]] \
    && ctl_rows="$ctl_rows no-pacing-stamp:red" || { ctl_ok=0; ctl_rows="$ctl_rows no-pacing-stamp:$(mw_label)"; }
c=$(mut_world nostamp-pr primary '/^switch_to_staked() {/,/^}/ s/^        LAST_SWITCH_TIME=\$(mono_now); save_state$/        :/' HZ=900) && [[ "$(dp "$c")" -ge 30 ]] \
    && ctl_rows="$ctl_rows primary-no-pacing-stamp:red" || { ctl_ok=0; ctl_rows="$ctl_rows primary-no-pacing-stamp:$(mw_label)"; }
c=$(mut_world nohist standby 's/^    _t="${_t} Vote history .*$/    :/') && ! has "$(page_of "$c")" "Vote history" \
    && ctl_rows="$ctl_rows history-field-dropped:red" || { ctl_ok=0; ctl_rows="$ctl_rows history-field-dropped:$(mw_label)"; }
c=$(mut_world nover standby 's/^    _t="${_t} This node: finalized slot ${_slot}; getHealth ${_health}; validator ${_ver}."$/    _t="${_t} This node: finalized slot ${_slot}; getHealth ${_health}."/') && ! has "$(page_of "$c")" "validator ok" \
    && ctl_rows="$ctl_rows version-field-dropped:red" || { ctl_ok=0; ctl_rows="$ctl_rows version-field-dropped:$(mw_label)"; }
c=$(mut_world noreset standby 's/^    _ag_page_ts=\$_now$/    :/' HZ=400) && [[ "$(agp "$c")" -ge 3 ]] \
    && ctl_rows="$ctl_rows marker-never-set:red" || { ctl_ok=0; ctl_rows="$ctl_rows marker-never-set:$(mw_label)"; }
if [[ $ctl_ok -eq 1 ]]; then
    ok "(9) every mutant turns its case red:$ctl_rows"
else
    bad "(9) a control is not red (GREEN = the mutant ran and the case does not bite; NOT-APPLIED = the sed expression matched nothing, so nothing was tested):$ctl_rows"
fi
# the labeller itself: an expression that matches nothing is NOT-APPLIED (never GREEN), one that applies is GREEN until the case turns red
c=$(mut_world self-none standby 's/^this line is in no daemon at all$/x/' HZ=5) && sc_rc=0 || sc_rc=1
sc_none=$(mw_label)
c=$(mut_world self-some standby 's/^_AG_SLOTS_PER_S_FAST=5$/_AG_SLOTS_PER_S_FAST=5   # applied/' HZ=5) && sc_rc2=0 || sc_rc2=1
sc_some=$(mw_label)
[[ $sc_rc -eq 1 && "$sc_none" == "NOT-APPLIED" && $sc_rc2 -eq 0 && "$sc_some" == "GREEN" ]] \
    && ok "(9z) the controls' labeller: an expression that matches nothing is labelled NOT-APPLIED (not GREEN), a mutant that ran is labelled GREEN until its case turns red" \
    || bad "(9z) labeller: no-match rc=$sc_rc label=$sc_none; applied rc=$sc_rc2 label=$sc_some"

results_banner
