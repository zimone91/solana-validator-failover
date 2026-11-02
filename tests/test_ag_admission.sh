#!/bin/bash
# v0.7 (AG-1.4): VAT ADMISSION (G7). Under Alpenglow a vote account counts only if it is in the epoch's VAT-filtered stake set (A11):
# getVoteAccounts' epochVoteAccount is membership in the CURRENT epoch's epoch stakes. A staked holder that was not admitted has
# activatedStake > 0 and epochVoteAccount false: its votes are not counted, it LOOKS like a dead holder, and a demote would change nothing.
# AG-1.4 reads that flag (LOCAL, finalized, one bounded batch with the epoch on both sides) and
#   - withholds every VOTE-BASED holder demote while the flag is positively false (the own-vote lag N6 in both daemons; on a PRIMARY also the
#     vote latency and the 3-tier delinquency) and pages instead - "NOT IN THE EPOCH'S VOTE SET";
#   - leaves the PARTITION triggers (frozen slot, silent LOCAL RPC, getHealth behind, lost internet) alone: they never ask;
#   - gives the AG page (AG-1.2) a one-line admission field with the reason class and its named limits.
# TRIGGER CLASSES (every holder-side demote, both daemons):  frozen confirmed slot - partition;  silent LOCAL RPC - partition;  getHealth behind
# > N - partition;  lost internet (primary) - partition;  N6 own-vote lag - VOTE-BASED (guarded);  vote latency > MAX_VOTE_LATENCY (primary,
# 3-tier) - VOTE-BASED (guarded);  delinquency (primary, 3-tier) - VOTE-BASED (guarded);  fence-rot graceful demote - fence integrity, not a vote.
#   (1) _vat_read over a shadowed LOCAL curl: admitted / not admitted / unstaked / boundary / unknown (an ABSENT entry is unknown, never "not
#       admitted" - the trap of keepUnstakedDelinquents), the request (one batch: getEpochInfo, getVoteAccounts, getEpochInfo; commitment
#       finalized; keepUnstakedDelinquents; LOCAL only), and the schedule of the next read
#   (2) _vat_cycle: the first call reads, then only on the schedule (an epoch change; <= every 10 min while not admitted/unknown); a state change is logged
#   (3) _vat_hold: withhold on a positive "not in the vote set" (one page, throttled), proceed on admitted / unknown / boundary; a withhold
#       verdict stands 120 s, then it is read again; the page carries the reason class (BLS key, stake, balance) and the named limits
#   (4) the REAL holder demotes: N6 in both daemons (the flag x list table: false holds and true demotes in BOTH the current and the delinquent list -
#       the pair (4a)/(4b) alone confounded the flag with the list), and the primary's vote-latency and delinquency triggers (the real main-loop region)
#   (5) CENSUS by bash's parse: every vote-based demote call is preceded by _vat_hold, in both daemons - and no partition trigger is
#   (6) CONTROLS (mutate()): a missing entry read as not admitted, an inverted flag, admission read from the list instead of the flag (the old
#       pair stays green under it, the 2x2 table does not), a boundary ignored, a guard that never withholds, a page that repeats, a stale verdict
#       that never expires, an N6 / latency / delinquency site with its guard removed
# RED ON THE BASE (AG-1.5 tree + this suite): the functions do not exist and a holder whose own-vote lag fires while epochVoteAccount is
# false DEMOTES; after the change: no demote, one page; the same world with epochVoteAccount true still demotes.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, field, mutate, extract_region, bp_parse / BP_AWK_LIB.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "VAT admission: the vote-set flag, the demote guard and the page (v0.7 AG-1.4)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/aga.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cut_src() { local f="$WORK/seam.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$$.$RANDOM"; sed -n '1,/MAIN LOOP/p' "$1" > "$f"; printf '%s' "$f"; }
role_of() { basename "$1" | sed 's/solana-\(.*\)-failover.sh/\1/'; }
VOTE="VotePubkey1111111111111111111111111111111"
STAKED="StakedPubkey111111111111111111111111111111"

# ── fixtures: the batch answer of [getEpochInfo, getVoteAccounts, getEpochInfo] ────────────────────
ent() { printf '{"votePubkey":"%s","nodePubkey":"Node1","activatedStake":%s,"epochVoteAccount":%s,"commission":0,"lastVote":100,"rootSlot":90,"epochCredits":[[1,1,0]]}' "$VOTE" "$1" "$2"; }
epi() { printf '{"jsonrpc":"2.0","id":%s,"result":{"absoluteSlot":%s,"blockHeight":1,"epoch":%s,"slotIndex":%s,"slotsInEpoch":432000,"transactionCount":1}}' "$1" "$(( $2 * 432000 + $3 ))" "$2" "$3"; }
vat_body() {   # vat_body <epoch1> <epoch3> <current-array> <delinquent-array> [slotIndex]
    local si="${5:-200000}"
    printf '[%s,{"jsonrpc":"2.0","id":2,"result":{"current":%s,"delinquent":%s}},%s]' "$(epi 1 "$1" "$si")" "$3" "$4" "$(epi 3 "$2" "$si")"
}
B_ADMITTED="$(vat_body 1074 1074 "[$(ent 5000000000 true)]" '[]')"
B_NOTADM_DELINQ="$(vat_body 1074 1074 '[]' "[$(ent 5000000000 false)]")"
B_NOTADM_CURRENT="$(vat_body 1074 1074 "[$(ent 5000000000 false)]" '[]')"
B_ADMITTED_DELINQ="$(vat_body 1074 1074 '[]' "[$(ent 5000000000 true)]")"   # the flag TRUE in the delinquent list: with B_NOTADM_CURRENT the 2x2 of flag x list
B_UNSTAKED="$(vat_body 1074 1074 '[]' "[$(ent 0 false)]")"
B_BOUNDARY="$(vat_body 1074 1075 "[$(ent 5000000000 true)]" '[]')"
B_ABSENT="$(vat_body 1074 1074 '[]' '[]')"
B_TWO="$(vat_body 1074 1074 "[$(ent 5000000000 true),$(ent 5000000000 true)]" '[]')"
B_NOFLAG="$(vat_body 1074 1074 "[{\"votePubkey\":\"$VOTE\",\"activatedStake\":5000000000}]" '[]')"
B_NOSTAKE="$(vat_body 1074 1074 "[{\"votePubkey\":\"$VOTE\",\"epochVoteAccount\":false}]" '[]')"
B_OTHER="$(vat_body 1074 1074 "[{\"votePubkey\":\"Other111\",\"activatedStake\":5,\"epochVoteAccount\":false,\"lastVote\":1}]" '[]')"
B_VOTES_ERR="[$(epi 1 1074 200000),{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32602,\"message\":\"Invalid params\"}},$(epi 3 1074 200000)]"
B_EPOCH_ERR="[{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32005,\"message\":\"Node is unhealthy\"}},{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"current\":[$(ent 5 true)],\"delinquent\":[]}},$(epi 3 1074 1)]"
B_REORDERED="[$(epi 3 1074 200000),$(printf '{"jsonrpc":"2.0","id":2,"result":{"current":[%s],"delinquent":[]}}' "$(ent 5000000000 true)"),$(epi 1 1074 200000)]"
B_LATE="$(vat_body 1074 1074 "[$(ent 5000000000 true)]" '[]' 431900)"
B_NOTADM_LATE="$(vat_body 1074 1074 '[]' "[$(ent 5000000000 false)]" 431000)"

# ── (1) _vat_read ─────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) _vat_read over a shadowed LOCAL curl: the flag, the epoch on both sides, the schedule ───"
vr_run() {   # vr_run <script> <body|RC7|EMPTY> [VAR=val …] → state=…|stake=…|epoch=…|left=…|why=…|calls=…|next=…|req=…
    local script="$1" body="$2" cs kv; shift 2
    cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"; VOTE_PUBKEY="$VOTE"
        _NOW=1000; mono_now() { echo "$_NOW"; }
        for kv in "$@"; do eval "$kv"; done
        CF=$(mktemp); trap 'rm -f "$CF"' EXIT
        _watchdog_pet() { :; }; log_info() { :; }; log_warn() { :; }
        curl() {
            local url="" data=""
            while [[ $# -gt 0 ]]; do case "$1" in -d) data="$2"; shift 2; continue ;; http*) url="$1" ;; esac; shift; done
            echo "$url $data" >> "$CF"
            case "$body" in RC7) return 7 ;; EMPTY) return 0 ;; esac
            printf '%s' "$body"; return 0
        }
        _vat_read
        printf 'state=%s|stake=%s|epoch=%s|left=%s|why=%s|calls=%s|next=%s|req=%s\n' "$_vat_state" "$_vat_stake" "$_vat_epoch" "$_vat_left" "$_vat_why" \
            "$(wc -l < "$CF" | tr -d ' ')" "$(( _vat_next_ts - _vat_read_ts ))" "$(head -1 "$CF")"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    out=$(vr_run "$scr" "$B_ADMITTED")
    [[ "$(field "$out" state)" == "admitted" && "$(field "$out" stake)" == "5000000000" && "$(field "$out" epoch)" == "1074" && "$(field "$out" left)" == "232000" && "$(field "$out" calls)" == "1" ]] \
        && ok "(1a:$n) in the vote set → admitted (stake 5000000000, epoch 1074, 232000 slots left), ONE call" || bad "(1a:$n) admitted misread ($out)"
    req=$(field "$out" req)
    [[ "$req" == "http://mock-local [{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getEpochInfo\",\"params\":[{\"commitment\":\"finalized\"}]},{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"getVoteAccounts\",\"params\":[{\"votePubkey\":\"$VOTE\",\"commitment\":\"finalized\",\"keepUnstakedDelinquents\":true}]},{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"getEpochInfo\",\"params\":[{\"commitment\":\"finalized\"}]}]" ]] \
        && ok "(1b:$n) the request: ONE batch to LOCAL_RPC only - getEpochInfo, getVoteAccounts{votePubkey, finalized, keepUnstakedDelinquents:true}, getEpochInfo" || bad "(1b:$n) request wrong ($req)"
    out=$(vr_run "$scr" "$B_NOTADM_DELINQ")
    [[ "$(field "$out" state)" == "notadmitted" && "$(field "$out" stake)" == "5000000000" ]] \
        && ok "(1c:$n) flag false with stake > 0, found in the delinquent list → notadmitted" || bad "(1c:$n) notadmitted(delinquent) misread ($out)"
    out=$(vr_run "$scr" "$B_NOTADM_CURRENT"); [[ "$(field "$out" state)" == "notadmitted" ]] && ok "(1d:$n) the same in the current list → notadmitted" || bad "(1d:$n) misread ($out)"
    out=$(vr_run "$scr" "$B_UNSTAKED")
    [[ "$(field "$out" state)" == "unstaked" && "$(field "$out" stake)" == "0" ]] && ok "(1e:$n) flag false with activatedStake 0 → unstaked" || bad "(1e:$n) unstaked misread ($out)"
    out=$(vr_run "$scr" "$B_BOUNDARY")
    [[ "$(field "$out" state)" == "boundary" && "$(field "$out" why)" == *"1074 -> 1075"* && -z "$(field "$out" stake)" ]] \
        && ok "(1f:$n) the two getEpochInfo calls disagree (1074 / 1075) → boundary: the flag stays unknown this time" || bad "(1f:$n) boundary misread ($out)"
    chk_unknown() { local out; out=$(vr_run "$scr" "$3"); [[ "$(field "$out" state)" == "unknown" && "$(field "$out" why)" == *"$2"* ]] || bad "(1g:$n:$1) not unknown/$2 ($out)"; }
    chk_unknown absent entries=0 "$B_ABSENT"; chk_unknown two entries=2 "$B_TWO"; chk_unknown noflag no-flag "$B_NOFLAG"; chk_unknown nostake no-stake "$B_NOSTAKE"
    chk_unknown other entries=0 "$B_OTHER"; chk_unknown votes-error no-vote-accounts "$B_VOTES_ERR"; chk_unknown epoch-error no-epoch-info "$B_EPOCH_ERR"
    ok "(1g:$n) an ABSENT entry (the empty filtered answer), a second entry, a missing flag, a missing stake, another account's entry, a JSON-RPC error for the votes or the epoch → unknown - never notadmitted, never unstaked"
    for fx in "object:{\"jsonrpc\":\"2.0\",\"result\":1}" "html:<html>502</html>" "empty:EMPTY" "transport:RC7"; do
        out=$(vr_run "$scr" "${fx#*:}"); [[ "$(field "$out" state)" == "unknown" ]] || bad "(1h:$n:${fx%%:*}) not unknown ($out)"
    done
    ok "(1h:$n) a non-batch answer, non-JSON, an empty answer and a transport failure → unknown"
    out=$(vr_run "$scr" "$B_REORDERED"); [[ "$(field "$out" state)" == "admitted" && "$(field "$out" epoch)" == "1074" ]] \
        && ok "(1i:$n) the answers are matched by id: a reordered batch reads the same" || bad "(1i:$n) reordered batch misread ($out)"
    out=$(vr_run "$scr" "$B_ADMITTED" 'VOTE_PUBKEY=')
    [[ "$(field "$out" state)" == "unknown" && "$(field "$out" why)" == "no VOTE_PUBKEY" && "$(field "$out" calls)" == "0" ]] \
        && ok "(1j:$n) no VOTE_PUBKEY → unknown, ZERO reads" || bad "(1j:$n) no-pubkey misread ($out)"
    nx1=$(field "$(vr_run "$scr" "$B_ADMITTED")" next); nx2=$(field "$(vr_run "$scr" "$B_LATE")" next); nx3=$(field "$(vr_run "$scr" "$B_NOTADM_DELINQ")" next)
    nx4=$(field "$(vr_run "$scr" "$B_NOTADM_LATE")" next); nx5=$(field "$(vr_run "$scr" "$B_ABSENT")" next); nx6=$(field "$(vr_run "$scr" "$B_BOUNDARY")" next)
    [[ "$nx1" == "46400" && "$nx2" == "30" && "$nx3" == "600" && "$nx4" == "200" && "$nx5" == "600" && "$nx6" == "600" ]] \
        && ok "(1k:$n) the schedule: admitted with 232000 slots left → +46400 s (the earliest the epoch can end, 5 slots/s); with 100 left → the 30 s floor; not admitted → +600 s, or the boundary if sooner (+200); unknown / boundary → +600 s" \
        || bad "(1k:$n) schedule: $nx1 $nx2 $nx3 $nx4 $nx5 $nx6"
done

# ── (2) _vat_cycle ────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (2) _vat_cycle: the first call reads, then only on the schedule; a state change is logged ───"
vc_run() {   # vc_run <script> <t:body>… → calls=…|logs=…|state=…
    local script="$1" cs e; shift
    cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; VOTE_PUBKEY="$VOTE"; LG=""; CF=$(mktemp); trap 'rm -f "$CF"' EXIT
        _NOW=1000; mono_now() { echo "$_NOW"; }
        _watchdog_pet() { :; }; log_info() { LG="$LG ‖ I:$*"; }; log_warn() { LG="$LG ‖ W:$*"; }
        curl() { echo C >> "$CF"; case "$_BODY" in RC7) return 7 ;; esac; printf '%s' "$_BODY"; return 0; }
        for e in "$@"; do _NOW="${e%%:*}"; _BODY="${e#*:}"; _vat_cycle; done
        printf 'calls=%s|state=%s|logs=%s\n' "$(wc -l < "$CF" | tr -d ' ')" "$_vat_state" "$LG"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    out=$(vc_run "$scr" "1000:$B_ADMITTED" "1010:$B_ADMITTED" "40000:$B_ADMITTED" "47399:$B_ADMITTED" "47400:$B_ADMITTED")
    [[ "$(field "$out" calls)" == "2" ]] && ok "(2a:$n) admitted: the first call reads; nothing until the earliest possible epoch end (+46400 s); one read there" || bad "(2a:$n) cadence ($out)"
    out=$(vc_run "$scr" "1000:$B_ADMITTED" "47400:$B_NOTADM_DELINQ")
    [[ "$(field "$out" state)" == "notadmitted" && "$(field "$out" logs)" == *"W:[vat] vote account $VOTE is NOT IN the epoch 1074 vote set (notadmitted; activated stake 5000000000 lamports)"* ]] \
        && ok "(2b:$n) the first cycle after the epoch end reads not admitted and logs the change as a WARNING (no page here: the demote guard and the AG page carry it)" || bad "(2b:$n) change not logged ($out)"
    out=$(vc_run "$scr" "1000:$B_NOTADM_DELINQ" "1100:$B_NOTADM_DELINQ" "1599:$B_NOTADM_DELINQ" "1600:$B_NOTADM_DELINQ" "2300:$B_NOTADM_DELINQ" "2200:$B_NOTADM_DELINQ")
    [[ "$(field "$out" calls)" == "3" ]] && ok "(2c:$n) not admitted: re-read at most every 10 minutes (reads at 1000, 1600, 2300 - not on every cycle)" || bad "(2c:$n) not-admitted cadence ($out)"
    out=$(vc_run "$scr" "1000:RC7" "1300:RC7" "1600:$B_ADMITTED")
    [[ "$(field "$out" calls)" == "2" && "$(field "$out" state)" == "admitted" && "$(field "$out" logs)" == *"reads unknown (no answer from LOCAL_RPC)"*"IS in the epoch"* || "$(field "$out" logs)" == *"is IN the epoch 1074 vote set"* ]] \
        && ok "(2d:$n) unknown (no answer yet): the next read waits the 10 minutes too (1300 skipped, 1600 reads and the node reads admitted), both changes logged" || bad "(2d:$n) unknown cadence ($out)"
done

# ── (3) _vat_hold ─────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (3) _vat_hold: withhold on a positive 'not in the vote set'; proceed on everything else ───"
vh_run() {   # vh_run <script> <body> [t:body …] → one record per call: rc/pages/reads/page text; the first call reads <body> at t=1000
    local script="$1" body="$2" cs e out=""; shift 2
    cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; VOTE_PUBKEY="$VOTE"; STAKED_PUBKEY="$STAKED"; ALERT_THROTTLE=600
        PG=0; PT=""; PS=""; PP=""; CF=$(mktemp); trap 'rm -f "$CF"' EXIT
        _NOW=1000; mono_now() { echo "$_NOW"; }
        _watchdog_pet() { :; }; log_info() { :; }; log_warn() { :; }
        alert() { PG=$((PG + 1)); [[ -z "$PT" ]] && PT="$1" && PS="$3" && PP="$2"; return 0; }
        curl() {
            local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
            case "$d" in
                '['*)           echo C >> "$CF"; case "$_BODY" in RC7) return 7 ;; esac; printf '%s' "$_BODY" ;;
                *getAccountInfo*) printf '%s' "${_ACCT:-}" ;;
                *)              return 7 ;;
            esac
            return 0
        }
        _BODY="$body"
        _vat_hold "own-vote lag 100 for 25s"; rc=$?
        out="rc=$rc,pages=$PG,reads=$(wc -l < "$CF" | tr -d ' ')"
        for e in "$@"; do _NOW="${e%%:*}"; _BODY="${e#*:}"; _vat_hold "own-vote lag 100 for 25s"; rc=$?; out="$out;rc=$rc,pages=$PG,reads=$(wc -l < "$CF" | tr -d ' ')"; done
        printf 'seq=%s|ptext=%s|pstatus=%s|ppub=%s\n' "$out" "$PT" "$PS" "$PP"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    out=$(vh_run "$scr" "$B_NOTADM_DELINQ")
    [[ "$(field "$out" seq)" == "rc=0,pages=1,reads=1" && "$(field "$out" pstatus)" == "NOT IN THE EPOCH'S VOTE SET 🚨" && "$(field "$out" ppub)" == "$STAKED" \
       && "$(field "$out" ptext)" == "own-vote lag 100 for 25s would have demoted this node, but its vote account $VOTE is NOT IN THE EPOCH'S VOTE SET: its votes are not counted"* ]] \
        && ok "(3a:$n) not admitted → rc 0 (WITHHOLD), exactly one page (status \"NOT IN THE EPOCH'S VOTE SET 🚨\", the trigger named), one fresh read" || bad "(3a:$n) withhold misread ($out)"
    [[ "$(field "$out" ptext)" == *"NOT ADMITTED (epoch 1074: activated stake 5000000000 lamports but epochVoteAccount false - votes are not counted)"* \
       && "$(field "$out" ptext)" == *"reason: unavailable (this node jsonParsed has no blsPubkeyCompressed"* || "$(field "$out" ptext)" == *"reason: unavailable (no answer"* ]] \
        && ok "(3b:$n) the page carries the admission line and the reason class (a field the answer lacks is named as a LIMIT, never a value), and the named limits" || bad "(3b:$n) page text ($(field "$out" ptext))"
    [[ "$(field "$out" ptext)" == *"top 2000 by stake (the cut is not checked - LIMIT)"* && "$(field "$out" ptext)" == *"rent(V4) + one epoch's VAT (0.8 SOL per epoch on mainnet's 200 ms row"* ]] \
        && ok "(3c:$n) the top-2000 cut is a named LIMIT; the VAT amount is stated with its row, not read" || bad "(3c:$n) limits not named"
    out=$(vh_run "$scr" "$B_NOTADM_DELINQ" "1010:$B_NOTADM_DELINQ" "1100:$B_ADMITTED")
    [[ "$(field "$out" seq)" == "rc=0,pages=1,reads=1;rc=0,pages=1,reads=1;rc=0,pages=1,reads=1" ]] \
        && ok "(3d:$n) a second and third call inside 120 s: still withheld, NO new read (the verdict stands), NO second page (ALERT_THROTTLE)" || bad "(3d:$n) cache/throttle ($out)"
    out=$(vh_run "$scr" "$B_NOTADM_DELINQ" "1130:$B_ADMITTED")
    [[ "$(field "$out" seq)" == "rc=0,pages=1,reads=1;rc=1,pages=1,reads=2" ]] \
        && ok "(3e:$n) at +130 s the verdict has expired: read FRESH, the node is admitted now → rc 1 (the demote proceeds), no page" || bad "(3e:$n) stale verdict ($out)"
    out=$(vh_run "$scr" "$B_NOTADM_DELINQ" "1130:$B_NOTADM_DELINQ" "1650:$B_NOTADM_DELINQ")
    [[ "$(field "$out" seq)" == "rc=0,pages=1,reads=1;rc=0,pages=1,reads=2;rc=0,pages=2,reads=3" ]] \
        && ok "(3f:$n) still withheld after the verdict expired and after ALERT_THROTTLE (600 s): re-read, and the page repeats once" || bad "(3f:$n) repeat ($out)"
    for fx in "admitted:$B_ADMITTED" "boundary:$B_BOUNDARY" "absent:$B_ABSENT" "transport:RC7" "votes-error:$B_VOTES_ERR"; do
        out=$(vh_run "$scr" "${fx#*:}"); [[ "$(field "$out" seq)" == "rc=1,pages=0,reads=1" ]] || bad "(3g:$n:${fx%%:*}) not proceed ($out)"
    done
    ok "(3g:$n) admitted, boundary, an absent entry, a transport failure and a votes error → rc 1, NO page: the demote proceeds as ever (unknown never suppresses)"
    out=$(vh_run "$scr" "$B_UNSTAKED"); [[ "$(field "$out" seq)" == "rc=0,pages=1,reads=1" && "$(field "$out" ptext)" == *"NOT ADMITTED (epoch 1074: activated stake 0 - no stake to count)"* ]] \
        && ok "(3h:$n) activatedStake 0 → withheld too, the page says there is no stake to count" || bad "(3h:$n) unstaked ($out)"
done
# the reason class
rs_run() {   # rs_run <script> <getAccountInfo body|RC7> → _vat_reason's text
    local script="$1" body="$2" cs; cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; VOTE_PUBKEY="$VOTE"; _watchdog_pet() { :; }
        curl() { case "$body" in RC7) return 7 ;; esac; printf '%s' "$body"; return 0; }
        _vat_reason
    )
}
rl_run() {   # rl_run <script> <getAccountInfo body> → CLEAN, or LEAK when _vat_reason (called in THIS shell: an assignment in a $(...) would die with it) leaves a variable named r behind
    local script="$1" body="$2" cs; cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; VOTE_PUBKEY="$VOTE"; _watchdog_pet() { :; }
        curl() { printf '%s' "$body"; return 0; }
        unset r
        _vat_reason > /dev/null
        if [[ -n "${r+set}" ]]; then echo LEAK; else echo CLEAN; fi
    )
}
ACCT() { printf '{"jsonrpc":"2.0","result":{"context":{"slot":1},"value":{"lamports":%s,"owner":"Vote111111111111111111111111111111111111111","data":{"program":"vote","parsed":{"type":"vote","info":{%s}},"space":3762},"executable":false}},"id":1}' "$1" "$2"; }
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    t=$(rs_run "$scr" "$(ACCT 700000000 '"blsPubkeyCompressed":"abcd","pendingDelegatorRewards":"12345","nodePubkey":"N"')")
    [[ "$t" == "vote account balance 700000000 lamports; BLS key present; pending delegator rewards 12345 lamports" ]] \
        && ok "(3i:$n) a 4.4.0-shaped answer: the balance, the BLS key present, the pending delegator rewards" || bad "(3i:$n) reason ($t)"
    t=$(rs_run "$scr" "$(ACCT 700000000 '"blsPubkeyCompressed":null,"pendingDelegatorRewards":"0"')")
    [[ "$t" == *"BLS key ABSENT (no BLS key: the filter drops the account)"* ]] && ok "(3j:$n) a null BLS key reads ABSENT - reason 1 of the filter" || bad "(3j:$n) null BLS ($t)"
    t=$(rs_run "$scr" "$(ACCT 5 '"nodePubkey":"N"')")
    [[ "$t" == *"BLS key unavailable (this node jsonParsed has no blsPubkeyCompressed field - LIMIT)"* && "$t" == *"pending delegator rewards unavailable (field absent - LIMIT)"* ]] \
        && ok "(3k:$n) an older node's answer (no BLS field, no pending rewards): both named as LIMITs, no value invented" || bad "(3k:$n) older shape ($t)"
    t=$(rs_run "$scr" RC7); [[ "$t" == "unavailable (no answer from LOCAL_RPC getAccountInfo)" ]] && ok "(3l:$n) no answer → unavailable (...), the page still goes out" || bad "(3l:$n) no answer ($t)"
    t=$(rs_run "$scr" '{"jsonrpc":"2.0","result":{"value":null},"id":1}'); [[ "$t" == "unavailable (no account in the answer)" ]] && ok "(3m:$n) no account → unavailable (no account in the answer)" || bad "(3m:$n) null account ($t)"
    t=$(rs_run "$scr" 'this is not json'); [[ "$t" == "unavailable (the answer could not be read)" ]] && ok "(3n:$n) an answer jq cannot parse → unavailable (the answer could not be read), the page still goes out" || bad "(3n:$n) unparsable answer ($t)"
    t=$(rl_run "$scr" 'this is not json'); [[ "$t" == "CLEAN" ]] && ok "(3o:$n) _vat_reason called in the daemon's own shell (not in a \$(...)) leaves no variable r behind when jq fails: the fallback assigns the function's local _r" || bad "(3o:$n) _vat_reason leaked a global variable r on an unparsable answer ($t)"
done

# ── (4) the real holder demotes ───────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) the REAL holder demotes: N6 (both daemons), the primary's vote latency and delinquency ───"
n6_run() {   # n6_run <script> <vat body|RC7> <cycles> → fenced=…|pages=…|vatreads=…|status=…  (the lag is sustained past SELF_FENCE_VOTE_LAG_SECS before the first cycle)
    local script="$1" body="$2" cycles="$3" cs i; cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; STAKED_PUBKEY="$STAKED"; UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"; VOTE_PUBKEY="$VOTE"
        SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_MAX_BEHIND=0
        SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3; ALERT_THROTTLE=600
        TG_ENABLED=false; DRY_RUN=false; CURRENT_IDENTITY="$STAKED"
        _SIM_NOW=1700000000; mono_now() { echo "$_SIM_NOW"; }; date() { [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
        _watchdog_pet() { :; }; log_info() { :; }; log_warn() { :; }; log_error() { :; }; send_telegram() { return 0; }; send_webhook() { :; }; save_state() { :; }
        FC=0; PG=0; PS=""; CF=$(mktemp); trap 'rm -f "$CF"' EXIT
        alert() { PG=$((PG + 1)); PS="$PS ‖ $3"; return 0; }
        switch_to_unstaked() { FC=$((FC + 1)); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
        _selffence_demote() { FC=$((FC + 1)); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
        _SLOT=100000
        curl() {
            local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
            case "$d" in
                '['*)             echo C >> "$CF"; case "$body" in RC7) return 7 ;; esac; printf '%s' "$body" ;;
                *getAccountInfo*) return 7 ;;
                *getSlot*)        printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$_SLOT" ;;
                *getVoteAccounts*) printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"Cluster111","lastVote":%s},{"votePubkey":"%s","lastVote":%s}],"delinquent":[]},"id":1}' "$((_SLOT + 100))" "$VOTE" "$_SLOT" ;;
                *)                return 7 ;;
            esac
            return 0
        }
        _selffence_reset
        _selffence_votelag_baseline=1; _selffence_votelag_healthy=0; _selffence_votelag_since=$(( _SIM_NOW - SELF_FENCE_VOTE_LAG_SECS - 5 ))
        _last_confirmed_slot=$(( _SLOT - 50 )); _last_confirmed_advance_ts=$_SIM_NOW
        for ((i = 0; i < cycles; i++)); do
            _SLOT=$((_SLOT + 10)); _last_confirmed_slot=$(( _SLOT - 5 )); _last_confirmed_advance_ts=$_SIM_NOW
            check_self_fence_isolation; _rc=$?
            _SIM_NOW=$((_SIM_NOW + 3))
        done
        printf 'fenced=%s|pages=%s|vatreads=%s|status=%s|rc=%s\n' "$FC" "$PG" "$(wc -l < "$CF" | tr -d ' ')" "$PS" "$_rc"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    out=$(n6_run "$scr" "$B_NOTADM_DELINQ" 4)
    [[ "$(field "$out" fenced)" == "0" && "$(field "$out" pages)" == "1" && "$(field "$out" status)" == " ‖ NOT IN THE EPOCH'S VOTE SET 🚨" && "$(field "$out" vatreads)" == "1" && "$(field "$out" rc)" == "1" ]] \
        && ok "(4a:$n) N6 sustained past SELF_FENCE_VOTE_LAG_SECS while epochVoteAccount is FALSE: NO demote over 4 cycles, ONE page, ONE read (the verdict stands)" || bad "(4a:$n) N6 not withheld ($out)"
    out=$(n6_run "$scr" "$B_ADMITTED" 1)
    [[ "$(field "$out" fenced)" == "1" && "$(field "$out" status)" != *"VOTE SET"* && "$(field "$out" rc)" == "0" ]] \
        && ok "(4b:$n) CONTROL WORLD: the same lag with epochVoteAccount TRUE still demotes at once, no VAT page" || bad "(4b:$n) admitted control ($out)"
    out=$(n6_run "$scr" RC7 1)
    [[ "$(field "$out" fenced)" == "1" && "$(field "$out" status)" != *"VOTE SET"* ]] \
        && ok "(4c:$n) the VAT read fails (unknown): the demote proceeds - unknown never suppresses a demote" || bad "(4c:$n) unknown control ($out)"
    out=$(n6_run "$scr" "$B_ABSENT" 1)
    [[ "$(field "$out" fenced)" == "1" ]] && ok "(4d:$n) an empty filtered answer (no entry) is unknown: the demote proceeds" || bad "(4d:$n) absent control ($out)"
    # the 2x2 of flag x list: (4a) false/delinquent and (4b) true/current differ in BOTH; (4g) false/current is (4b) with only the flag flipped, (4h) true/delinquent is (4a) with only the flag flipped
    out=$(n6_run "$scr" "$B_NOTADM_CURRENT" 4)
    [[ "$(field "$out" fenced)" == "0" && "$(field "$out" pages)" == "1" && "$(field "$out" status)" == " ‖ NOT IN THE EPOCH'S VOTE SET 🚨" && "$(field "$out" vatreads)" == "1" && "$(field "$out" rc)" == "1" ]] \
        && ok "(4g:$n) the account sits in the CURRENT list (as in (4b)) and epochVoteAccount is FALSE: NO demote over 4 cycles, ONE page, ONE read - admission is the flag, not the list" || bad "(4g:$n) flag false in current ($out)"
    out=$(n6_run "$scr" "$B_ADMITTED_DELINQ" 1)
    [[ "$(field "$out" fenced)" == "1" && "$(field "$out" status)" != *"VOTE SET"* && "$(field "$out" rc)" == "0" ]] \
        && ok "(4h:$n) the account sits in the DELINQUENT list (as in (4a)) and epochVoteAccount is TRUE: the demote proceeds at once, no VAT page" || bad "(4h:$n) flag true in delinquent ($out)"
done
# the primary's main-loop triggers: the REAL STAKED branch of the loop (the drive_cycle_primary technique)
pl_run() {   # pl_run <trigger latency|delinq> <vat body> → fenced=…|pages=…|reasons=…
    local trig="$1" body="$2" cs region; cs=$(cut_src "$PRIMARY")
    region=$(extract_region "$PRIMARY" '^while \$_running; do' '^done$') || { echo "region=EMPTY"; return 0; }
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        eval "run_cycle() {
$region
}"
        LOCAL_RPC="http://mock-local"; STAKED_PUBKEY="$STAKED"; UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"; VOTE_PUBKEY="$VOTE"
        TG_ENABLED=false; DRY_RUN=false; ALERT_THROTTLE=600; PRIMARY_SELF_FENCE=false; CHECK_INTERVAL=1; _current_interval=1; DELINQUENCY_RETRIES=1; DELINQUENCY_WINDOW_SIZE=1; DELINQUENCY_WINDOW_THRESHOLD=1
        MAX_VOTE_LATENCY=0; [[ "$trig" == "latency" ]] && MAX_VOTE_LATENCY=10
        _SIM_NOW=1700000000; mono_now() { echo "$_SIM_NOW"; }
        CF=$(mktemp); trap 'rm -f "$CF"' EXIT; FC=0; PG=0; RS=""
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _version_startup_check() { :; }; _vat_cycle() { :; }; _fence_rot_check() { :; }; _g2_step() { :; }; _elapsed_step() { :; }
        flush_pending_alerts() { :; }; display_status() { :; }; save_state() { :; }; check_identity_collision() { return 0; }; check_internet() { return 0; }
        _watchdog_pet() { :; }; log_info() { :; }; log_warn() { :; }; log_error() { :; }; send_telegram() { return 0; }; send_webhook() { :; }; alert_info() { :; }; alert_warn() { :; }
        alert() { PG=$((PG + 1)); return 0; }
        get_local_identity() { echo "$STAKED_PUBKEY"; }
        _last_known_identity="$STAKED_PUBKEY"; _unknown_identity_since=0; _last_heartbeat=$_SIM_NOW; HEARTBEAT_INTERVAL=2000000000   # the loop's heartbeat reads the REAL clock (date +%s): a withheld demote now falls through to it, and its ping loop must not run
        tier1_get_vote_latency() { echo 99; }; verify_latency_tiered() { return 0; }
        tier1_check_delinquency() { [[ "$trig" == "delinq" ]]; }; verify_delinquency_tiered() { return 0; }
        window_push() { :; }; window_count() { echo 1; }; window_triggered() { return 0; }; window_reset() { :; }; window_mostly_clear() { return 1; }
        switch_to_unstaked() { FC=$((FC + 1)); RS="$RS ‖ $1"; return 0; }
        _watchdog_sleep() { _running=false; }; sleep() { _running=false; }
        curl() {
            local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
            case "$d" in '['*) echo C >> "$CF"; case "$body" in RC7) return 7 ;; esac; printf '%s' "$body" ;; *) return 7 ;; esac
            return 0
        }
        _running=true; run_cycle
        printf 'fenced=%s|pages=%s|reasons=%s|vatreads=%s\n' "$FC" "$PG" "$RS" "$(wc -l < "$CF" | tr -d ' ')"
    )
}
for trig in latency delinq; do
    out=$(pl_run "$trig" "$B_NOTADM_DELINQ")
    [[ "$(field "$out" fenced)" == "0" && "$(field "$out" pages)" == "1" && "$(field "$out" vatreads)" == "1" ]] \
        && ok "(4e:$trig) PRIMARY: the 3-tier $trig trigger fires while epochVoteAccount is FALSE: NO demote, ONE page" || bad "(4e:$trig) trigger not withheld ($out)"
    out=$(pl_run "$trig" "$B_ADMITTED")
    [[ "$(field "$out" fenced)" == "1" && "$(field "$out" pages)" == "0" && "$(field "$out" reasons)" == *"3-tier confirmed"* ]] \
        && ok "(4f:$trig) CONTROL WORLD: the same trigger with epochVoteAccount TRUE demotes ($(field "$out" reasons))" || bad "(4f:$trig) admitted control ($out)"
done

# ── (5) census: every vote-based demote is guarded - and no partition trigger is ──────────────────
echo ""; echo "─── (5) census by bash's parse: the vote-based demote calls carry _vat_hold; the partition triggers do not ───"
VG_AWK="$BP_AWK_LIB"'
$1 == "L" { fn = $2; raw = $6; rn[fn]++; has[fn, rn[fn]] = (index(raw, "_vat_hold ") > 0)
    if (match(raw, /(^|[ ;{(|&])(switch_to_unstaked|_selffence_demote) "/)) {
        r = substr(raw, RSTART + RLENGTH); gsub(/^[$]?/, "", r)
        # an ASCII label per trigger class: a reason text may hold a non-ASCII character (a dash) that awks cut differently
        if (r ~ /^self-fence: own votes not landing/) cls = "own-vote-lag"
        else if (r ~ /^Latency /) cls = "vote-latency"
        else if (r ~ /^Delinquent/) cls = "delinquency"
        else if (r ~ /^self-fence: LOCAL RPC/) cls = "local-rpc-silent"
        else if (r ~ /^self-fence: local confirmed/) cls = "slot-frozen"
        else if (r ~ /^self-fence: local getHealth/) cls = "gethealth-behind"
        else if (r ~ /^Internet lost/) cls = "internet-lost"
        else if (fn == "_rot_graceful_demote") cls = "rot-graceful"
        else if (r ~ /^holder gap:/) cls = "holder-gap"
        else cls = "UNCLASSIFIED"
        g = has[fn, rn[fn]]; for (k = 1; k <= 6 && !g; k++) if (rn[fn] - k >= 1) g = has[fn, rn[fn] - k]
        row = sprintf("%s|%s|%d", fn, cls, g); T[row] = 1 } }
END { for (r in T) print r }'
vg_scan() {   # vg_scan <file> → the demote-call table, one "<function>|<trigger class>|<guarded 0/1>" row per call site, sorted
    local d="$WORK/p.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$RANDOM"; mkdir -p "$d"
    bp_parse "$1" "$d" && [[ -s "$d/lex" ]] || { echo "PARSE-FAIL:$(basename "$1")"; return 0; }
    awk -F'\t' "$VG_AWK" "$d/lex" | sort
}
VG_STANDBY='check_self_fence_isolation|gethealth-behind|0
check_self_fence_isolation|local-rpc-silent|0
check_self_fence_isolation|own-vote-lag|1
check_self_fence_isolation|slot-frozen|0'
VG_PRIMARY='(post)|delinquency|1
(post)|internet-lost|0
(post)|vote-latency|1
_gap_demote|holder-gap|0
_rot_graceful_demote|rot-graceful|0
check_self_fence_isolation|gethealth-behind|0
check_self_fence_isolation|local-rpc-silent|0
check_self_fence_isolation|own-vote-lag|1
check_self_fence_isolation|slot-frozen|0'
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); t=$(vg_scan "$scr"); want="$VG_STANDBY"; [[ "$n" == "primary" ]] && want="$VG_PRIMARY"
    want=$(printf '%s\n' "$want" | sort)
    [[ "$t" == "$want" ]] \
        && ok "(5a:$n) the demote call sites by bash's parse: the vote-based ones (own-vote lag$([[ $n == primary ]] && echo ', vote latency, delinquency')) are each behind _vat_hold; the partition triggers (frozen slot, silent LOCAL RPC, getHealth behind$([[ $n == primary ]] && echo ', lost internet')) and the fence-rot graceful demote$([[ $n == primary ]] && echo ' and the holder-gap demote (AG-3.4: a frozen host demotes first, it does not ask)') are not" \
        || bad "(5a:$n) demote-site census moved: $(printf '%s' "$t" | tr '\n' ';')"
done

# ── (6) CONTROLS ──────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) CONTROLS: every mutant must turn its case red ───"
ctl_read() {   # ctl_read <label> <sed expr> <body> <record field> — the mutant's _vat_read record differs from the real one in that field
    local label="$1" expr="$2" body="$3" f="$4" scr n m real mut
    for scr in "$STANDBY" "$PRIMARY"; do
        n=$(role_of "$scr"); m="$WORK/c-$label-$n.sh"
        if mutate "$scr" "$expr" "$m"; then
            real=$(vr_run "$scr" "$body"); mut=$(vr_run "$m" "$body")
            [[ "$(field "$real" "$f")" != "$(field "$mut" "$f")" ]] \
                && ok "(6:$label:$n) CONTROL: $f '$(field "$real" "$f" | cut -c1-40)' -> '$(field "$mut" "$f" | cut -c1-40)' with the mutant" || bad "(6:$label:$n) the control did not bite (real: $real :: mutant: $mut)"
        fi
    done
}
ctl_read absent-as-lapse 's/then "unknown entries=.*$/then "notadmitted 1 1 1"/' "$B_ABSENT" state
ctl_read inverted-flag 's/elif \$x.epochVoteAccount then "admitted /elif ($x.epochVoteAccount | not) then "admitted /' "$B_ADMITTED" state
ctl_read boundary-ignored 's/elif \$a.epoch != \$c.epoch then "boundary /elif false then "boundary /' "$B_BOUNDARY" state
ctl_read keep-unstaked-dropped 's/,\\"keepUnstakedDelinquents\\":true//' "$B_ADMITTED" req
ctl_read rate-constant 's/^_AG_SLOTS_PER_S_FAST=5$/_AG_SLOTS_PER_S_FAST=4/' "$B_ADMITTED" next   # AG-1.6: the schedule divides by the named fast-end constant, not by a literal
ctl_hold() {   # ctl_hold <label> <sed expr> <vh_run args…> — the mutant's call sequence differs from the real one
    local label="$1" expr="$2" scr n m real mut; shift 2
    for scr in "$STANDBY" "$PRIMARY"; do
        n=$(role_of "$scr"); m="$WORK/c-$label-$n.sh"
        if mutate "$scr" "$expr" "$m"; then
            real=$(vh_run "$scr" "$@"); mut=$(vh_run "$m" "$@")
            [[ "$(field "$real" seq)" != "$(field "$mut" seq)" ]] \
                && ok "(6:$label:$n) CONTROL: the sequence '$(field "$real" seq)' -> '$(field "$mut" seq)' with the mutant" || bad "(6:$label:$n) the control did not bite (real: $real :: mutant: $mut)"
        fi
    done
}
ctl_hold guard-proceeds 's/^            return 0 ;;$/            return 1 ;;/' "$B_NOTADM_DELINQ"
ctl_hold page-repeats 's/            if \[\[ ${_vat_page_ts:-0} -eq 0 || \$(( _now - _vat_page_ts )) -ge ${ALERT_THROTTLE:-600} \]\]; then/            if true; then/' "$B_NOTADM_DELINQ" "1010:$B_NOTADM_DELINQ"
ctl_hold verdict-never-expires 's/ && \[\[ ${_vat_read_ts:-0} -gt 0 && \$(( _now - _vat_read_ts )) -lt 120 \]\]; }; then/ \&\& true; }; then/' "$B_NOTADM_DELINQ" "1130:$B_ADMITTED"
ctl_hold always-reads 's/    if ! { \[\[ "$_vat_state" == "notadmitted" || "$_vat_state" == "unstaked" \]\]/    if ! { false/' "$B_NOTADM_DELINQ" "1010:$B_NOTADM_DELINQ"
# the guards removed from each site: the real world demotes under the lapse, and the demote-site table names the site
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); m="$WORK/c-n6guard-$n.sh"
    if mutate "$scr" 's/                    if _vat_hold "own-vote lag ${_sf_vshow} for ${vlsust}s"; then return 1; fi/                    :/' "$m"; then
        real=$(n6_run "$scr" "$B_NOTADM_DELINQ" 1); mut=$(n6_run "$m" "$B_NOTADM_DELINQ" 1)
        [[ "$(field "$real" fenced)" == "0" && "$(field "$mut" fenced)" == "1" && "$(vg_scan "$m")" != "$(vg_scan "$scr")" ]] \
            && ok "(6:n6-guard-removed:$n) CONTROL: with the N6 guard removed the lapse DEMOTES (fenced 0 -> 1) and the demote-site table moves" || bad "(6:n6-guard-removed:$n) the N6 control did not bite (real: $real :: mutant: $mut)"
    fi
done
# admission read from the LIST instead of the flag: the 2x2 table's off-diagonal worlds swap, the old pair (4a)/(4b) - whose fixtures agree in flag and list - does not move
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); m="$WORK/c-membership-$n.sh"
    if mutate "$scr" 's/elif \$x.epochVoteAccount then "admitted /elif (($v.current \/\/ []) | map(.votePubkey) | index($pk)) != null then "admitted /' "$m"; then
        g_real=$(n6_run "$scr" "$B_NOTADM_CURRENT" 4);  g_mut=$(n6_run "$m" "$B_NOTADM_CURRENT" 4)
        h_real=$(n6_run "$scr" "$B_ADMITTED_DELINQ" 1); h_mut=$(n6_run "$m" "$B_ADMITTED_DELINQ" 1)
        a_real=$(n6_run "$scr" "$B_NOTADM_DELINQ" 4);   a_mut=$(n6_run "$m" "$B_NOTADM_DELINQ" 4)
        b_real=$(n6_run "$scr" "$B_ADMITTED" 1);        b_mut=$(n6_run "$m" "$B_ADMITTED" 1)
        # held = no demote at all (fenced 0); demoted = at least one (the harness's cycles keep calling the demote stub, so the count is not always 1)
        [[ "$(field "$g_real" fenced)" == "0" && "$(field "$g_mut" fenced)" -ge 1 && "$(field "$h_real" fenced)" -ge 1 && "$(field "$h_mut" fenced)" == "0" \
           && "$(field "$a_mut" fenced)" == "$(field "$a_real" fenced)" && "$(field "$b_mut" fenced)" == "$(field "$b_real" fenced)" ]] \
            && ok "(6:membership-as-admission:$n) CONTROL: reading admission from the current list turns (4g) false/current from held to demoted and (4h) true/delinquent from demoted to held, while (4a)/(4b) do not move at all (fenced $(field "$a_real" fenced) and $(field "$b_real" fenced) with and without the mutant) - the confounded pair could not see it" \
            || bad "(6:membership-as-admission:$n) the control did not bite or the old pair moved ((4g) real=$(field "$g_real" fenced) mut=$(field "$g_mut" fenced); (4h) real=$(field "$h_real" fenced) mut=$(field "$h_mut" fenced); (4a) real=$(field "$a_real" fenced) mut=$(field "$a_mut" fenced); (4b) real=$(field "$b_real" fenced) mut=$(field "$b_mut" fenced))"
    fi
done
for trig in latency delinq; do
    m="$WORK/c-pl-$trig.sh"
    if [[ "$trig" == "latency" ]]; then ex='s/_vat_hold "vote latency ${vote_latency}sl > ${MAX_VOTE_LATENCY}sl (3-tier confirmed)" || //'; else ex='s/_vat_hold "delinquency (3-tier confirmed, window ${w_count}\/${DELINQUENCY_WINDOW_SIZE})" || //'; fi
    if mutate "$PRIMARY" "$ex" "$m"; then
        PRIMARY_SAVE="$PRIMARY"; PRIMARY="$m"; mut=$(pl_run "$trig" "$B_NOTADM_DELINQ"); PRIMARY="$PRIMARY_SAVE"
        [[ "$(field "$mut" fenced)" == "1" && "$(vg_scan "$m")" != "$(vg_scan "$PRIMARY")" ]] \
            && ok "(6:$trig-guard-removed) CONTROL: with the guard removed the primary's $trig trigger DEMOTES under the lapse and the demote-site table moves" || bad "(6:$trig-guard-removed) the control did not bite ($mut)"
    fi
done
# a guard on a PARTITION trigger moves the table too (lost internet must never ask)
m="$WORK/c-census-inet.sh"
if mutate "$PRIMARY" 's/^\( *\)switch_to_unstaked "Internet lost/\1_vat_hold "x" || switch_to_unstaked "Internet lost/' "$m"; then
    [[ "$(vg_scan "$m")" != "$(vg_scan "$PRIMARY")" ]] && ok "(6:guarded-partition-trigger) CONTROL: a _vat_hold put in front of the lost-internet demote moves the demote-site table" || bad "(6:guarded-partition-trigger) the census did not see a guarded partition trigger"
fi
# ... and so must the holder-gap demote (AG-3.4): a host that was frozen demotes first, it never asks the vote-account read
m="$WORK/c-census-gap.sh"
if mutate "$PRIMARY" 's/^\( *\)if switch_to_unstaked "holder gap:/\1if _vat_hold "x" || switch_to_unstaked "holder gap:/' "$m"; then
    [[ "$(vg_scan "$m")" != "$(vg_scan "$PRIMARY")" ]] && ok "(6:guarded-gap-demote) CONTROL: a _vat_hold put in front of the holder-gap demote moves the demote-site table" || bad "(6:guarded-gap-demote) the census did not see a guarded gap demote"
fi

results_banner
