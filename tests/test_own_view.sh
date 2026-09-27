#!/bin/bash
# v0.7 (Block 6.3.1): OWN-VIEW HARDENING. The reviewer's principle for the slice: TRIGGER on the slow
# reliable view (finalized), VETO on the fast one (confirmed). The detection reads stay on `finalized`,
# now SPELLED OUT; the spare's OWN bank (LOCAL_RPC — the one stream no TIER2/TIER3 intermediary can
# splice) becomes a veto at every take, and watchdog-elapsed gains a rate layer on the spare's own head.
# Drives the REAL shipped code (source-to-MAIN-LOOP seam; the REAL main loop through test_elapsed_provider's
# world() driver, extracted verbatim — never a copy). Cost model: the worst outcome is DOUBLE-SIGN, so
# every ambiguity on the spare fails toward NOT taking.
#   (0) D0.2 N-is-all — the TAKE-path census: every set-identity to the STAKED key in the shipped set is in
#       take_staked_identity (standby) or switch_to_staked (primary), and each runs _fresh_proof_recheck,
#       then _own_view_veto, BEFORE its DRY_RUN branch; the veto is called nowhere else
#   (1) D1 — explicit commitments: (1a) every getVoteAccounts/getSlot body in both daemons carries one
#       (allowlist census); (1b) the site table (function, method, commitment) is pinned — the detection
#       reads say finalized; (1c) control: a body stripped of its commitment → (1a) red; (1d) ZERO
#       behavior change (D0.1: agave's default IS finalized): every detection read of both daemons under a
#       commitment-aware stub decides identically on the shipped tree and on the D1-reverted tree, and a
#       confirmed-mutant control decides differently (the stub can tell); (1e) the same on the REAL loop
#   (2) D2 — own-bank "holder voting" restarts the countdown: the D0 race (red on the 6.3 build: taken
#       t113→t125 un-armed, minted/taken t159→t171 armed) holds now; no take for a full TAKEOVER_DELAY
#       (no mint for a full floor) after the last own-bank voting cycle; the reset at EVERY episode-close
#       site (N-is-all census + behavior); the FLICKERING own bank's availability cost, measured under
#       both presets, with the starvation page
#   (3) D3 — the ONE bounded local veto read: (3a) the predicate table on the REAL _own_view_veto, both
#       daemons; (3b) the twin; (3c) the A8 census by exact spelling; (3d) state before alert, throttle,
#       no cooldown; (3e) the controls: veto neutered alone → the D2/D4 worlds TAKE; each guard alone
#       holds its own world; veto + re-check neutered → the all-neutered control takes
#   (4) D4 — the spare's own head: (4b) advancing NOW (red on the 6.3 build: a spare cut off after the
#       episode opened was taken over on the timer path); the exposure below OWN_HEAD_H measured and
#       pinned as the named residual; (4e) [elapsed-rate] (red on the 6.3 build: an own head at 2.0
#       slots/s minted) with the healthy-rate before/after numbers
#   (5) D5 — the holder's latency demote reads its payload FIRST (red on the 6.3 build: reference first)
#   (6) D6 — the cross-node invariant table's spare columns (the holder column: docs/SAFETY.md)
# The A8 rule these cases enforce, as every site states it since 6.3.1: between the fresh re-check's
# return-0 and set-identity — no network, no alerts; one bounded local veto read allowed.
#
# harness: tests/lib/harness.sh — load_seam, harness_clock_shims/harness_silence_sinks, field,
# dump_freshness (the sole reader of the freshness triple), extract_twin, mutate, ok/bad+banners.
# The REAL-loop worlds of (2)–(6) run CONCURRENTLY (one background subshell per world, each with its own
# file clock, temp dir and event log; the seam-cut cache is warmed first) — the results are identical to a
# sequential run; only the wall time differs.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Own-view hardening (v0.7 Block 6.3.1)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ov631.XXXXXX")
WORK=$(cd -P -- "$WORK" && pwd -P)   # the provider refuses a token directory that is not its own resolved path (R-SYM)
T0=100000
HEAD0=900000
harness_clock_shims
harness_silence_sinks
_crc_def=$(grep -m1 '^_pairing_crc()' "$STANDBY")
if [[ -z "$_crc_def" ]]; then bad "harness: cannot extract _pairing_crc from the standby daemon"; else eval "$_crc_def"; fi
mk_token() { local p="v0.7|gen=$1|watchdog=$2|relinquish_bound=$3|fence=$4|host=$5"; printf '%s|%s\n' "$p" "$(_pairing_crc "$p")"; }
# the REAL main-loop world driver, extracted VERBATIM from test_elapsed_provider (one driver, not a copy)
_world_def=$(sed -n '/^world() {/,/^}$/p' "$HARNESS_DIR/tests/test_elapsed_provider.sh")
if [[ -z "$_world_def" ]]; then bad "harness: cannot extract world() from test_elapsed_provider.sh"; else eval "$_world_def"; fi
code_of() { sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[[:space:]].*$//' "$1"; }   # comment-stripped (whole-line and trailing ' # ' comments)
fn_body() { awk -v f="$2" '$0 ~ "^"f"\\(\\) *\\{" {p=1} p {print} p && /^\}/ {exit}' "$1"; }

# ── (0) D0.2 — the TAKE-path census (N-is-all) ─────────────────────────────────────────────────────
echo ""; echo "─── (0) D0.2: every set-identity to the STAKED key — the take paths, and the guards on each ───"
SHIPPED="$HARNESS_DIR/install.sh $PRIMARY $STANDBY $HARNESS_DIR/deploy-failover.sh $HARNESS_DIR/deploy-failover-standby.sh $HARNESS_DIR/failover-arm.sh $HARNESS_DIR/systemd/failover-fence.sh $HARNESS_DIR/systemd/failover-fence-page-only.sh"
take_sites=""
for f in $SHIPPED; do
    # a set-identity CALL (not an echo'd hint, not a comment) naming the STAKED key — the only way a node can
    # start voting the staked identity; attributed to its enclosing function
    s=$(code_of "$f" | awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {fn=$1; sub(/\(\).*/,"",fn)} /^\}/ {fn="(top)"}
        /set-identity/ && /\$STAKED_KEYPAIR/ && !/UNSTAKED_KEYPAIR/ && !/^[[:space:]]*(echo|printf|log_|_arm_log|_arm_warn)/ {print fn}' | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')
    [[ -n "$s" ]] && take_sites="$take_sites$(basename "$f")[$s]"
done
if [[ "$take_sites" == "solana-primary-failover.sh[switch_to_staked:2 ]solana-standby-failover.sh[take_staked_identity:2 ]" ]]; then
    ok "(0a) N-is-all: the ONLY set-identity-to-STAKED calls in the shipped set are switch_to_staked's two (agave + fdctl — primary) and take_staked_identity's two (standby); nothing in install.sh / the deploy wizards / the arm / the fence scripts can take"
else
    bad "(0a) take-path census moved: $take_sites"
fi
g_ok=1; g_rows=""
for pair in "$PRIMARY:switch_to_staked" "$STANDBY:take_staked_identity"; do
    f="${pair%%:*}"; fn="${pair##*:}"
    body=$(fn_body "$f" "$fn")
    rl=$(printf '%s\n' "$body" | grep -n '^[[:space:]]*_fresh_proof_recheck || return 1' | head -1 | cut -d: -f1)
    vl=$(printf '%s\n' "$body" | grep -n '^[[:space:]]*_own_view_veto || return 1' | head -1 | cut -d: -f1)
    dl=$(printf '%s\n' "$body" | grep -n 'if \[\[ "\$DRY_RUN" == "true" \]\]' | head -1 | cut -d: -f1)
    sl=$(printf '%s\n' "$body" | grep -n 'set-identity' | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1)
    vc=$(code_of "$f" | grep -c '_own_view_veto || return 1')
    if [[ -n "$rl" && -n "$vl" && -n "$dl" && -n "$sl" && $vl -eq $((rl + 1 + $(printf '%s\n' "$body" | sed -n "$((rl+1)),$((vl-1))p" | grep -c '^[[:space:]]*#'))) && $vl -lt $dl && $dl -lt $sl && "$vc" == "1" ]]; then
        g_rows="$g_rows $(basename "$f"):$fn(recheck l$rl → veto l$vl → DRY_RUN l$dl → set-identity l$sl)"
    else
        g_ok=0; bad "(0b) $(basename "$f") $fn: recheck=$rl veto=$vl dry=$dl setid=$sl veto-calls-in-file=$vc"
    fi
done
[[ $g_ok -eq 1 ]] && ok "(0b) on EVERY take path the veto is the statement right after the fresh re-check's return-0 (comments only between) and BEFORE the DRY_RUN branch (DRY_RUN mirrors the live decision), and it is called nowhere else in either daemon:$g_rows"
# the primary's other staked-going call is the pre-warm authorized-voter add (not a set-identity) — named
if code_of "$STANDBY" | grep -q 'authorized-voter add' && ! code_of "$STANDBY" | grep 'authorized-voter add' | grep -q 'set-identity'; then
    ok "(0c) named exclusions: the standby's PREWARM authorized-voter add (off by default, live-test-gated) is not a set-identity and never makes this node vote the staked identity; the fence scripts and the arm only ever move toward UNSTAKED"
else
    bad "(0c) the pre-warm exclusion no longer reads as stated"
fi

# ── (1) D1 — explicit commitments, census-enforced ─────────────────────────────────────────────────
echo ""; echo "─── (1) D1: every getVoteAccounts/getSlot body spells its commitment; the site table; zero behavior change ───"
census_bodies() {   # $1=file → one line per getVoteAccounts/getSlot request body: "<fn> <method> <commitment|NONE>"
    code_of "$1" | awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {fn=$1; sub(/\(\).*/,"",fn)} /^\}/ {fn="(top)"}
      /"method":"getVoteAccounts"|"method":"getSlot"|\\"method\\":\\"getVoteAccounts\\"|\\"method\\":\\"getSlot\\"/ {
        line=$0; c="NONE"
        if (line ~ /commitment[\\"]*:[\\"]*processed/) c="processed"; else if (line ~ /commitment[\\"]*:[\\"]*confirmed/) c="confirmed"; else if (line ~ /commitment[\\"]*:[\\"]*finalized/) c="finalized"
        m="getSlot"; if (line ~ /getVoteAccounts/) m="getVoteAccounts"
        if (line ~ /getVoteAccounts/ && line ~ /getSlot/) m="batch[getSlot,getVoteAccounts]"; else if (line ~ /getClusterNodes/) m="batch[getSlot,getClusterNodes]"
        printf "%s %s %s\n", fn, m, c }'
}
# the pinned table (allowlist): a new body, a moved commitment or a missing one is red here — the WHY per
# site lives in docs/SAFETY.md ('Which view each read uses') and the per-site daemon comments
P_TABLE="tier1_check_delinquency getVoteAccounts finalized
tier1_get_vote_latency getVoteAccounts finalized
tier1_get_vote_latency getSlot finalized
_check_rpc_delinquency getVoteAccounts finalized
verify_latency_tiered getVoteAccounts finalized
verify_latency_tiered getSlot finalized
_check_single_rpc getVoteAccounts finalized
get_staked_liveness_sample getVoteAccounts processed
_own_head_sample getSlot confirmed
_own_view_veto batch[getSlot,getVoteAccounts] confirmed
_g2_snap batch[getSlot,getClusterNodes] confirmed
_elapsed_step getSlot processed
check_self_fence_isolation getSlot confirmed
check_self_fence_isolation getVoteAccounts processed
startup_checks getSlot finalized
startup_checks getSlot finalized
startup_checks getSlot finalized"
S_TABLE="tier1_check_local_health getSlot finalized
local_check_delinquency getSlot finalized
local_check_delinquency getVoteAccounts finalized
_own_head_sample getSlot confirmed
_own_view_veto batch[getSlot,getVoteAccounts] confirmed
tier2_check_delinquency getVoteAccounts finalized
tier2_check_delinquency getSlot finalized
tier2_check_delinquency getVoteAccounts finalized
tier3_confirm_delinquency getVoteAccounts finalized
get_staked_liveness_sample getVoteAccounts processed
_g2_snap batch[getSlot,getClusterNodes] confirmed
_elapsed_step getSlot processed
check_self_fence_isolation getSlot confirmed
check_self_fence_isolation getVoteAccounts processed
startup_checks getSlot finalized
startup_checks getSlot finalized
startup_checks getSlot finalized"
pc=$(census_bodies "$PRIMARY"); sc=$(census_bodies "$STANDBY")
pn=$(printf '%s\n' "$pc" | grep -c ' NONE$'); sn=$(printf '%s\n' "$sc" | grep -c ' NONE$')
if [[ "$pn" == "0" && "$sn" == "0" && $(printf '%s\n' "$pc" | grep -c .) -eq 17 && $(printf '%s\n' "$sc" | grep -c .) -eq 17 ]]; then
    ok "(1a) every getVoteAccounts/getSlot request body in BOTH daemons carries an explicit commitment (17 bodies each, zero without one)"
else
    bad "(1a) bodies without a commitment: primary=$pn standby=$sn — $(printf '%s\n' "$pc" "$sc" | grep ' NONE$' | tr '\n' ';')"
fi
if [[ "$pc" == "$P_TABLE" && "$sc" == "$S_TABLE" ]]; then
    ok "(1b) the site table is pinned: DETECTION reads — the standby's local_check_delinquency reference + payload and the TIER2/TIER3 confirm payloads (tier2_check_delinquency, tier3_confirm_delinquency), the primary's tier1/latency/recovery reads — say finalized (their effective value before, by D0.1); the samplers and the elapsed head processed, the self-fence confirmed/processed, G2 confirmed — unchanged; the [own-view] reads confirmed (new)"
else
    bad "(1b) the site table moved — primary: $(diff <(printf '%s\n' "$P_TABLE") <(printf '%s\n' "$pc") | grep '^[<>]' | tr '\n' ';') standby: $(diff <(printf '%s\n' "$S_TABLE") <(printf '%s\n' "$sc") | grep '^[<>]' | tr '\n' ';')"
fi
# (1c) control: strip ONE detection body's commitment in a copy → the census goes red
if mutate "$STANDBY" '/^local_check_delinquency() {/,/^}/s/"method":"getVoteAccounts","params":\[{"commitment":"finalized"}\]}/"method":"getVoteAccounts"}/' "$WORK/d1-strip.sh"; then
    n=$(census_bodies "$WORK/d1-strip.sh" | grep -c ' NONE$')
    [[ "$n" == "1" ]] && ok "(1c) CONTROL: one detection body stripped of its commitment in a copy → the census finds exactly that body (NONE) — (1a) is red on it" \
                      || bad "(1c) control: stripped copy shows $n bodies without a commitment (want 1)"
fi

# (1d) ZERO behavior change — the detection reads of both daemons, shipped vs D1-REVERTED (the explicit
# finalized removed from every body: exactly the 6.3 bytes), under a stub that serves each commitment
# its OWN view: default/finalized = F (the holder DELINQUENT, lastVote 1000, head 2000), confirmed = C and
# processed = P (the holder CURRENT). A read whose effective commitment moved would change its decision.
mutate "$STANDBY" 's/,"params":\[{"commitment":"finalized"}\]//g' "$WORK/s-d1rev.sh"
mutate "$PRIMARY" 's/,"params":\[{"commitment":"finalized"}\]//g' "$WORK/p-d1rev.sh"
mutate "$STANDBY" '/^local_check_delinquency() {/,/^}/s/"method":"getVoteAccounts","params":\[{"commitment":"finalized"}\]}/"method":"getVoteAccounts","params":[{"commitment":"confirmed"}]}/' "$WORK/s-conf.sh"
d1_drive() {   # $1=script $2=calls → one line per call: "<call> rc=<rc> out=<stdout> log=<log lines>"
    (
        set +e
        _SIM_NOW=$T0
        load_seam "$1"
        STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
        _watchdog_pet(){ :; }; alert_info(){ :; }; alert_warn(){ :; }; alert(){ :; }
        LOGF=$(mktemp "$WORK/d1log.XXXXXX")   # the calls run inside $(): their log lines come back through a file
        log_info(){ printf '%s;' "$*" >> "$LOGF"; }; log_warn(){ printf 'W:%s;' "$*" >> "$LOGF"; }
        curl(){
            local d="" c=F
            while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; *) shift ;; esac; done
            case "$d" in *'"commitment":"confirmed"'*) c=C ;; *'"commitment":"processed"'*) c=P ;; esac
            case "$d" in
                *getHealth*) printf '{"jsonrpc":"2.0","result":"ok","id":1}' ;;
                *getSlot*) case $c in F) printf '{"jsonrpc":"2.0","result":2000,"id":1}' ;; C) printf '{"jsonrpc":"2.0","result":2030,"id":1}' ;; P) printf '{"jsonrpc":"2.0","result":2040,"id":1}' ;; esac ;;
                *getVoteAccounts*)
                    case $c in
                        F) if [[ "${FVIEW:-list}" == "lat" ]]; then   # the holder CURRENT but 20 behind the finalized head: delinquent only by the MAX_DELINQUENT_SLOTS=15 latency test
                               printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":1999},{"votePubkey":"V1","nodePubkey":"S1","lastVote":1980}],"delinquent":[]},"id":1}'
                           else printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":1999}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":1000}]},"id":1}'; fi ;;
                        *) printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":2029},{"votePubkey":"V1","nodePubkey":"S1","lastVote":2028}],"delinquent":[]},"id":1}' ;;
                    esac ;;
                *) return 7 ;;
            esac
            return 0
        }
        local call out rc
        for call in $2; do
            : > "$LOGF"; MAX_DELINQUENT_SLOTS=0; MAX_VOTE_LATENCY=15; FVIEW=list
            case "$call" in *@15) MAX_DELINQUENT_SLOTS=15; FVIEW=lat ;; esac
            out=$(eval "${call%@*}" 2>/dev/null); rc=$?
            printf '%s rc=%s out=%s log=%s\n' "$call" "$rc" "$out" "$(cat "$LOGF")"
        done
        rm -f "$LOGF"
    )
}
S_CALLS="local_check_delinquency local_check_delinquency@15 tier2_check_delinquency tier2_check_delinquency@15 tier3_confirm_delinquency tier1_check_local_health"
P_CALLS="tier1_check_delinquency tier1_get_vote_latency _check_rpc_delinquency verify_latency_tiered _check_single_rpc"
s_new=$(d1_drive "$STANDBY" "$S_CALLS"); s_rev=$(d1_drive "$WORK/s-d1rev.sh" "$S_CALLS")
p_new=$(d1_drive "$PRIMARY" "$P_CALLS"); p_rev=$(d1_drive "$WORK/p-d1rev.sh" "$P_CALLS")
s_conf=$(d1_drive "$WORK/s-conf.sh" "$S_CALLS")
if [[ -n "$s_new" && "$s_new" == "$s_rev" && -n "$p_new" && "$p_new" == "$p_rev" && $(printf '%s\n' "$s_new" | grep -c 'rc=0') -ge 4 ]]; then
    ok "(1d) ZERO behavior change (D0.1: agave's default commitment IS finalized — solana-commitment-config's #[default] Finalized, rpc.rs bank() unwrap_or_default): the standby's 6 detection drives and the primary's 5 decide byte-identically (rc, output, log) on the shipped tree and on the D1-reverted 6.3 bytes, under a stub that serves finalized, confirmed and processed DIFFERENT views"
else
    bad "(1d) the D1 revert changed a decision — standby: $(diff <(printf '%s\n' "$s_new") <(printf '%s\n' "$s_rev") | grep '^[<>]' | head -2 | tr '\n' ';') primary: $(diff <(printf '%s\n' "$p_new") <(printf '%s\n' "$p_rev") | grep '^[<>]' | head -2 | tr '\n' ';')"
fi
if [[ -n "$s_conf" && "$s_conf" != "$s_new" && "$(printf '%s\n' "$s_new" | head -1)" == *"rc=0"* && "$(printf '%s\n' "$s_conf" | head -1)" != *"rc=0"* ]]; then
    ok "(1d-ctl) CONTROL: the same drive with ONE detection read moved to confirmed (a what-if mutant) decides DIFFERENTLY (local_check_delinquency: delinquent → not) — the stub can tell the views apart, so (1d)'s equality is not vacuous"
else
    bad "(1d-ctl) the confirmed mutant decided the same — (1d) may be vacuous: $(printf '%s\n' "$s_conf" | head -1)"
fi

# ── (3) D3 — the ONE bounded local veto read: the predicate table on the REAL _own_view_veto ────────
echo ""; echo "─── (3) D3: the veto's predicate table (both daemons), the twin, the A8 census, state/throttle/no-cooldown ───"
# vcase <daemon> — ONE call of the REAL _own_view_veto on the seam. Knobs (env): BATCH = the batch answer
# with @A@/@B@ standing for the ids the veto sent (BATCHRC = curl rc, default 0); RING = the own-head
# samples "pre:post:slot" as OFFSETS from T0 (the main loop's _own_head_sample writes them); OBMAX = the
# own-bank max ("" = none); MDSV = MAX_DELINQUENT_SLOTS; NOW = the veto's instant (offset). Prints
# rc|kind|oba|bl|alerts|curls|pets|order|m|url|body|warn — kind from the log line; oba/bl the state
# after (offsets; bl via dump_freshness, the sole reader of the triple).
vcase() {
    (
        set +e
        _SIM_NOW=$T0
        load_seam "$1"
        STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; LOCAL_RPC="http://local.mock"; ALERT_THROTTLE=600
        EVF=$(mktemp "$WORK/vev.XXXXXX")
        log_warn(){ printf 'WARN %s\n' "$*" >> "$EVF"; }; log_info(){ printf 'INFO %s\n' "$*" >> "$EVF"; }
        alert_warn(){ printf 'ALERT oba=%s bl=%s %s\n' "${_own_bank_active_time:-0}" "$(field "$(dump_freshness)" blind_until)" "$1" >> "$EVF"; }
        _watchdog_pet(){ printf 'PET\n' >> "$EVF"; }
        curl(){
            local d="" m="" u="" a b
            while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; -m) m="$2"; shift 2 ;; http*) u="$1"; shift ;; *) shift ;; esac; done
            printf 'CURL m=%s url=%s body=%s\n' "$m" "$u" "$d" >> "$EVF"
            a=${d#*\"id\":}; a=${a%%,*}; b=${d##*\"id\":}; b=${b%%,*}
            [[ -n "${BATCHRC:-}" && "${BATCHRC:-0}" != "0" ]] && return "$BATCHRC"
            local out="${BATCH//@A@/$a}"; out="${out//@B@/$b}"
            printf '%s' "$out"
            return 0
        }
        local e r=""
        for e in ${RING:-}; do r="${r:+$r }$(( T0 + ${e%%:*} )):$(( T0 + $(printf '%s' "$e" | cut -d: -f2) )):${e##*:}"; done
        _own_head_ring="$r"; _own_bank_max_vote="${OBMAX-5000}"; MAX_DELINQUENT_SLOTS="${MDSV:-0}"
        _SIM_NOW=$(( T0 + ${NOW:-110} ))
        _own_view_veto; local rc=$?
        local kind=pass
        grep -q 'VETO (holder voting)' "$EVF" && kind=voting
        grep -q 'VETO (blind)' "$EVF" && kind=blind
        local oba=${_own_bank_active_time:-0} bl; bl=$(field "$(dump_freshness)" blind_until)
        [[ $oba -gt 0 ]] && oba=$(( oba - T0 )); [[ ${bl:-0} -gt 0 ]] && bl=$(( bl - T0 ))
        printf 'rc=%s|kind=%s|oba=%s|bl=%s|alerts=%s|curls=%s|pets=%s|order=%s|m=%s|url=%s|warn=%s|body=%s\n' "$rc" "$kind" "$oba" "${bl:-0}" \
            "$(grep -c '^ALERT' "$EVF")" "$(grep -c '^CURL' "$EVF")" "$(grep -c '^PET' "$EVF")" \
            "$(grep -oE '^(CURL|PET|WARN|INFO|ALERT)' "$EVF" | tr '\n' ',')" "$(grep -m1 '^CURL' "$EVF" | sed 's/^CURL m=\([^ ]*\).*/\1/')" \
            "$(grep -m1 '^CURL' "$EVF" | sed 's/.* url=\([^ ]*\) .*/\1/')" "$(grep -m1 -E '^(WARN|INFO)' "$EVF" | cut -c1-240)" "$(grep -m1 '^CURL' "$EVF" | sed 's/.* body=//')"
        rm -f "$EVF"
    )
}
SL='{"jsonrpc":"2.0","id":@A@,"result":900225}'
GD='{"jsonrpc":"2.0","id":@B@,"result":{"current":[],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":5000}]}}'
GC='{"jsonrpc":"2.0","id":@B@,"result":{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":900224}],"delinquent":[]}}'
RING1="100:100:900200"
# name | env assignments | expected kind | expected rc — the veto predicate table ([ov-read] [ov-head] [ov-delinq] [ov-max])
VTABLE="pass-healthy|BATCH=[$SL,$GD]|pass|0
pass-members-swapped (matched by id, never by position)|BATCH=[$GD,$SL]|pass|0
read-timeout (curl rc 28 at the 2 s bound)|BATCH=[$SL,$GD] BATCHRC=28|blind|1
read-refused (rc 7)|BATCH=[$SL,$GD] BATCHRC=7|blind|1
empty-body|BATCH=|blind|1
not-an-array|BATCH={\"jsonrpc\":\"2.0\",\"id\":1,\"result\":900225}|blind|1
one-member|BATCH=[$SL]|blind|1
three-members|BATCH=[$SL,$GD,$SL]|blind|1
ids-not-ours (a stale / replayed answer)|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":900225},{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"current\":[],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5000}]}}]|blind|1
slot-id-twice|BATCH=[$SL,$SL]|blind|1
slot-leading-zero|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":\"0900225\"},$GD]|blind|1
slot-2^64-wrap|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":18446744073710451841},$GD]|blind|1
slot-negative|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":-5},$GD]|blind|1
gva-error-member|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"error\":{\"code\":-32000,\"message\":\"x\"}}]|blind|1
gva-result-not-an-object|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":[1,2]}]|blind|1
holder-absent|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[],\"delinquent\":[]}}]|blind|1
holder-twice|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5000}],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5000}]}}]|blind|1
lastvote-null|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":null}]}}]|blind|1
lastvote-string-leading-zero|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":\"05000\"}]}}]|blind|1
holder-NOT-delinquent (current in the confirmed view)|BATCH=[$SL,$GC]|voting|1
delinquent-by-nodePubkey-leg (same predicate as local_check_delinquency)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5000}],\"delinquent\":[{\"votePubkey\":\"V9\",\"nodePubkey\":\"S1\",\"lastVote\":4000}]}}]|pass|0
MDS15-current-latency-20 (delinquent by latency)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":900205}],\"delinquent\":[]}}] MDSV=15 OBMAX=900205|pass|0
MDS15-current-latency-15 (NOT above the threshold)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":900210}],\"delinquent\":[]}}] MDSV=15 OBMAX=900210|voting|1
MDS-non-canonical → no latency test (fewer delinquent verdicts)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":900205}],\"delinquent\":[]}}] MDSV=abc OBMAX=900205|voting|1
lastVote-above-own-bank-max (it voted since)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5001}]}}]|voting|1
lastVote-equal-own-bank-max|BATCH=[$SL,$GD] OBMAX=5000|pass|0
own-bank-max-unset (no baseline)|BATCH=[$SL,$GD] OBMAX=|blind|1
no-own-head-sample|BATCH=[$SL,$GD] RING=|blind|1
own-head-sample-too-old (17 s > OWN_HEAD_H 16)|BATCH=[$SL,$GD] RING=93:93:900200|blind|1
own-head-sample-exactly-16s|BATCH=[$SL,$GD] RING=94:94:900200|pass|0
own-head-NOT-advanced (= the baseline)|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":900200},$GD]|blind|1
own-head-advanced-by-1|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":900201},$GD]|pass|0
baseline-is-the-OLDEST-in-window (a newer sample does not count)|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":900180},$GD] RING=90:90:900100_95:95:900150_105:105:900220|pass|0
oldest-in-window-not-exceeded|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":900150},$GD] RING=90:90:900100_95:95:900150_105:105:900220|blind|1"
for d in "$PRIMARY" "$STANDBY"; do
    vt_ok=1; vt_n=0; vt_bad=""
    while IFS='|' read -r name envs want wrc; do
        [[ -z "$name" ]] && continue
        vt_n=$((vt_n + 1))
        r=$(
            set -f   # the JSON answers carry [ ] — never glob them
            unset BATCH BATCHRC RING OBMAX MDSV NOW
            RING="$RING1"; OBMAX=5000
            for kv in $envs; do
                k="${kv%%=*}"; v="${kv#*=}"; v="${v//_/ }"
                [[ "$k" == "BATCH" ]] && v="${kv#BATCH=}"
                eval "$k=\"\$v\""
            done
            [[ "$envs" == *"RING="* && -z "$RING" ]] && RING=""
            vcase "$d" | tail -1
        )
        if [[ "$(field "$r" kind)" == "$want" && "$(field "$r" rc)" == "$wrc" ]]; then :; else vt_ok=0; vt_bad="$vt_bad [$name: want $want/$wrc got $(field "$r" kind)/$(field "$r" rc) — $(field "$r" warn)]"; fi
    done <<< "$VTABLE"
    if [[ $vt_ok -eq 1 ]]; then
        ok "(3a) $(basename "$d"): the veto predicate table — $vt_n rows, each on the REAL _own_view_veto: PASS only on a well-formed 2-member batch matched BY ID, a canonical confirmed slot ABOVE the oldest own-head sample within OWN_HEAD_H, the holder listed exactly once, DELINQUENT by the same predicate as local_check_delinquency (votePubkey/nodePubkey membership, or latency > MAX_DELINQUENT_SLOTS), its lastVote <= the own-bank max; every read failure / shape / id / non-canonical value / missing baseline → BLIND; not delinquent / voted since → VOTING"
    else
        bad "(3a) $(basename "$d") predicate table:$vt_bad"
    fi
done
# (3b) the twin: the [own-view] region is BYTE-IDENTICAL in both daemons
if extract_twin '\[own-view\] the spare' '\[own-view\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(3b) [own-view] region BYTE-IDENTICAL in both daemons ($(printf '%s' "$TWIN_P" | wc -c | tr -d ' ') bytes: _own_view_reset, _own_bank_note, _own_head_sample, _own_veto_alert, _own_view_veto, OWN_HEAD_H)"
else
    bad "(3b) [own-view] twin blocks differ (primary=${#TWIN_P}B standby=${#TWIN_S}B)"
fi
# (3c) the A8 census BY EXACT SPELLING: the region reads the network in exactly two places — the own-head
# sample and the veto — each ONE curl to LOCAL_RPC with -m 2; the veto's is THE one read the rule admits:
# a [getSlot{confirmed}, getVoteAccounts{confirmed, votePubkey}] batch with fresh ids
VETO_CURL='curl -s -m 2 "$LOCAL_RPC" -X POST -H "Content-Type: application/json" -d "[{\"jsonrpc\":\"2.0\",\"id\":${_ovv_ida},\"method\":\"getSlot\",\"params\":[{\"commitment\":\"confirmed\"}]},{\"jsonrpc\":\"2.0\",\"id\":${_ovv_idb},\"method\":\"getVoteAccounts\",\"params\":[{\"commitment\":\"confirmed\",\"votePubkey\":\"${VOTE_PUBKEY}\"}]}]" 2>/dev/null'
SAMPLE_CURL='curl -s -m 2 "$LOCAL_RPC" -X POST -H "Content-Type: application/json" -d '"'"'{"jsonrpc":"2.0","id":1,"method":"getSlot","params":[{"commitment":"confirmed"}]}'"'"' 2>/dev/null'
a8_ok=1; a8_why=""
for d in "$PRIMARY" "$STANDBY"; do
    reg=$(sed -n '/\[own-view\] the spare/,/\[own-view\] end shared block/p' "$d" | sed -e 's/^[[:space:]]*#.*$//')
    vb=$(fn_body "$d" _own_view_veto | sed -e 's/^[[:space:]]*#.*$//')
    # a curl INVOCATION is '$(curl ' (a "curl rc=" inside a message string is not one)
    [[ "$(printf '%s\n' "$reg" | grep -c '\$(curl ')" == "2" ]] || { a8_ok=0; a8_why="$a8_why $(basename "$d"): region curl count $(printf '%s\n' "$reg" | grep -c '\$(curl ')"; }
    [[ "$(printf '%s\n' "$vb" | grep -cF "\$($VETO_CURL)")" == "1" && "$(printf '%s\n' "$vb" | grep -c '\$(curl ')" == "1" ]] || { a8_ok=0; a8_why="$a8_why $(basename "$d"): the veto's read is not EXACTLY the admitted spelling"; }
    [[ "$(fn_body "$d" _own_head_sample | grep -cF "$SAMPLE_CURL")" == "1" ]] || { a8_ok=0; a8_why="$a8_why $(basename "$d"): the own-head sample's read spelling moved"; }
    # alerts only on the VETO path: every _own_veto_alert call in the veto sits AFTER its clear-path 'return 0'
    rz=$(printf '%s\n' "$vb" | grep -n '^[[:space:]]*return 0$' | head -1 | cut -d: -f1)
    fa=$(printf '%s\n' "$vb" | grep -n '_own_veto_alert ' | head -1 | cut -d: -f1)
    [[ -n "$rz" && -n "$fa" && $fa -gt $rz ]] || { a8_ok=0; a8_why="$a8_why $(basename "$d"): an alert precedes the clear-path return (rz=$rz alert=$fa)"; }
    # between the re-check's return-0 and set-identity in the take function: no curl, no alert, no send, no
    # sampler, no gossip — only the veto (the dynamic census: test_act_then_alert (1e)/(5b)/(6e))
    tf=take_staked_identity; [[ "$d" == "$PRIMARY" ]] && tf=switch_to_staked
    seg=$(fn_body "$d" "$tf" | sed -e 's/^[[:space:]]*#.*$//' | awk '/_fresh_proof_recheck \|\| return 1/ {p=1; next} p && /set-identity/ {exit} p {print}')
    bad_calls=$(printf '%s\n' "$seg" | grep -nE '\$\(curl |alert[a-z_]* |send_telegram|send_webhook|get_staked_liveness_sample|check_primary_dropped_identity|_g2_|getClusterNodes' | grep -v 'alert "\$reason"' | tr '\n' ' ')
    # the DRY_RUN branch's own alert ("[DRY RUN] WOULD TAKE") and the keypair-missing page are the live
    # decision's REPORTS, not inputs — they fire only on the far side of the veto; set-identity follows them
    [[ -z "$bad_calls" ]] || { a8_ok=0; a8_why="$a8_why $(basename "$d") $tf: network/alert calls between the re-check and set-identity: $bad_calls"; }
done
if [[ $a8_ok -eq 1 ]]; then
    ok "(3c) the A8 census by EXACT spelling, both daemons: the [own-view] region reads the network in exactly TWO places (the own-head sample and the veto), each ONE curl -m 2 to LOCAL_RPC; the veto's read is exactly the admitted [getSlot{confirmed}, getVoteAccounts{confirmed, votePubkey}] batch; its alerts sit only on the veto path (after the clear return); between each take path's re-check return-0 and set-identity there is no other curl, alert, send, sampler or gossip call"
else
    bad "(3c) A8 census:$a8_why"
fi
# the rule text: every site that STATES the A8 rule states it exactly (daemons, SAFETY, CHANGELOG, test headers)
RULE="no network, no alerts; one bounded local veto read allowed"
rt_ok=1; rt_why=""
for f in "$PRIMARY" "$STANDBY" "$HARNESS_DIR/docs/SAFETY.md" "$HARNESS_DIR/CHANGELOG.md" "$HARNESS_DIR/tests/test_act_then_alert.sh" "$HARNESS_DIR/tests/test_own_view.sh"; do
    n=$(tr '\n' ' ' < "$f" | sed 's/[[:space:]#]\{1,\}/ /g' | grep -o "$RULE" | wc -l | tr -d ' ')
    [[ "$n" -ge 1 ]] || { rt_ok=0; rt_why="$rt_why $(basename "$f"):0"; }
done
stale=$(grep -n -E 'ZERO network calls|between the re-check and set-identity — ZERO|ZERO NETWORK AFTER A RETURN-0|zero network between the fresh re-check' "$PRIMARY" "$STANDBY" "$HARNESS_DIR/docs/SAFETY.md" 2>/dev/null | head -3 | tr '\n' ' ')
if [[ $rt_ok -eq 1 && -z "$stale" ]]; then
    ok "(3c-text) the A8 rule reads exactly '$RULE' in both daemons, SAFETY, CHANGELOG and the test headers; no site still states the pre-6.3.1 'zero network' rule"
else
    bad "(3c-text) rule text missing:$rt_why stale:$stale"
fi
# (3d) one request, its bound, its pet, fresh ids; state BEFORE the alert; throttle; no cooldown, no episode drop
vd() {   # a scripted SEQUENCE of veto calls on ONE seam: $1=daemon; VSEQ="<offset>:<pass|voting|blind> …"
    (
        set +e
        _SIM_NOW=$T0
        load_seam "$1"
        STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; LOCAL_RPC="http://local.mock"; ALERT_THROTTLE=600
        EVF=$(mktemp "$WORK/vd.XXXXXX")
        log_warn(){ :; }; log_info(){ :; }
        alert_warn(){ printf 'ALERT t=%s oba=%s bl=%s\n' "$(( _SIM_NOW - T0 ))" "${_own_bank_active_time:-0}" "$(field "$(dump_freshness)" blind_until)" >> "$EVF"; }
        _watchdog_pet(){ printf 'PET\n' >> "$EVF"; }
        _MODE=pass
        curl(){
            local d="" a b
            while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; *) shift ;; esac; done
            a=${d#*\"id\":}; a=${a%%,*}; b=${d##*\"id\":}; b=${b%%,*}
            printf 'CURL ids=%s,%s\n' "$a" "$b" >> "$EVF"
            [[ "$_MODE" == "blind" ]] && return 7
            if [[ "$_MODE" == "voting" ]]; then
                printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]}}]' "$a" "$(( 900300 + _SIM_NOW - T0 ))" "$b" "$(( 900299 + _SIM_NOW - T0 ))"
            else
                printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":{"current":[],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":5000}]}}]' "$a" "$(( 900300 + _SIM_NOW - T0 ))" "$b"
            fi
        }
        FIRST_DELINQUENT_TIME=$(( T0 - 30 )); _delinq_window="1111111111"; LAST_TAKEOVER_TIME=0; _own_bank_max_vote=5000
        local s off rcs=""
        for s in $VSEQ; do
            off="${s%%:*}"; _MODE="${s##*:}"; _SIM_NOW=$(( T0 + off ))
            _own_head_ring="$(( _SIM_NOW - 5 )):$(( _SIM_NOW - 5 )):900000"
            _own_view_veto; rcs="$rcs$?"
        done
        printf 'rcs=%s|alerts=%s|curls=%s|pets=%s|order=%s|ids=%s|fdt=%s|win=%s|ltt=%s|oba=%s\n' "$rcs" "$(grep '^ALERT' "$EVF" | sed 's/^ALERT //' | tr '\n' ';')" \
            "$(grep -c '^CURL' "$EVF")" "$(grep -c '^PET' "$EVF")" "$(grep -oE '^(CURL|PET|ALERT)' "$EVF" | tr '\n' ',')" "$(grep '^CURL' "$EVF" | sed 's/^CURL ids=//' | tr '\n' ';')" \
            "$(( FIRST_DELINQUENT_TIME - T0 ))" "$_delinq_window" "$LAST_TAKEOVER_TIME" "${_own_bank_active_time:-0}"
        rm -f "$EVF"
    )
}
for d in "$PRIMARY" "$STANDBY"; do
    r=$(VSEQ="10:voting 20:voting 30:blind 700:voting 710:pass" vd "$d" | tail -1)
    alerts=$(field "$r" alerts); ids=$(field "$r" ids)
    a1=${ids%%;*}; a1a=${a1%%,*}; a1b=${a1##*,}; rest=${ids#*;}; a2=${rest%%;*}; a2a=${a2%%,*}
    if [[ "$(field "$r" rcs)" == "11110" && "$(field "$r" curls)" == "5" && "$(field "$r" pets)" == "5" && "$(field "$r" order)" == "CURL,PET,ALERT,CURL,PET,CURL,PET,CURL,PET,ALERT,CURL,PET," \
          && "$alerts" == "t=10 oba=$((T0+10)) bl=0;t=700 oba=$((T0+700)) bl=$((T0+30));" && $a1b -eq $((a1a + 1)) && $a2a -eq $((a1a + 2)) \
          && "$(field "$r" fdt)" == "-30" && "$(field "$r" win)" == "1111111111" && "$(field "$r" ltt)" == "0" ]]; then
        ok "(3d) $(basename "$d"): each veto is ONE request then ONE pet (5 vetoes → 5 curls, 5 pets, pet right after each read); fresh ids per read (a, a+1; the next read a+2); the state write precedes the alert (the alert-time snapshot already shows oba / bl); the veto page is THROTTLED — t10 pages, t20 (voting) and t30 (blind) inside ALERT_THROTTLE do not, t700 pages again (the (12) idiom, one storm guard for both kinds); NO cooldown (LAST_TAKEOVER_TIME stays 0) and NO episode state dropped (FIRST_DELINQUENT_TIME, the window) — a withdrawn verdict, not a failed take"
    else
        bad "(3d) $(basename "$d"): $r"
    fi
done
# (3d-sample) _own_head_sample: ONE LOCAL getSlot{confirmed} + its pet; a canonical answer joins the ring
# as pre:post:slot; the ring keeps only samples no older than OWN_HEAD_H at the new sample's post
hs() {
    (
        set +e
        _SIM_NOW=$T0; load_seam "$1"; LOCAL_RPC="http://local.mock"
        EVF=$(mktemp "$WORK/hs.XXXXXX"); _watchdog_pet(){ printf 'PET\n' >> "$EVF"; }
        _ANS=900100
        curl(){ printf 'CURL\n' >> "$EVF"; [[ "$_ANS" == "RC7" ]] && return 7; printf '{"jsonrpc":"2.0","id":1,"result":%s}' "$_ANS"; }
        local s
        for s in $HSEQ; do _SIM_NOW=$(( T0 + ${s%%:*} )); _ANS="${s##*:}"; _own_head_sample; done
        local r="" e
        for e in $_own_head_ring; do r="$r $(( ${e%%:*} - T0 )):${e##*:}"; done
        printf 'ring=%s|curls=%s|pets=%s\n' "${r# }" "$(grep -c '^CURL' "$EVF")" "$(grep -c '^PET' "$EVF")"
        rm -f "$EVF"
    )
}
for d in "$PRIMARY" "$STANDBY"; do
    r=$(HSEQ="0:900100 5:900110 10:0900120 15:RC7 16:900140 20:900150 33:900180" hs "$d" | tail -1)
    if [[ "$(field "$r" ring)" == "20:900150 33:900180" && "$(field "$r" curls)" == "7" && "$(field "$r" pets)" == "7" ]]; then
        ok "(3d-sample) $(basename "$d"): _own_head_sample — one read + one pet per call (7/7), a non-canonical ('0900120') or failed (rc 7) answer is NO sample, and the ring keeps only samples within OWN_HEAD_H=16 s of the newest (at t33: t20, t33 — t0..t16 pruned)"
    else
        bad "(3d-sample) $(basename "$d"): $r"
    fi
done

# ── (2)–(6): the REAL standby main loop (test_elapsed_provider's world(), extracted verbatim above) ───
# The worlds are launched TOGETHER: each is its own subshell with its own file clock, temp dir and event
# log (the seam-cut cache is warmed first, so no two worlds race on it). Every expectation is the MEASURED
# outcome; the 6.3-build number an ok line quotes is the same world run against the 6.3 daemons (the red).
# The mutants (each applies loudly, or the suite is red):
mutate "$STANDBY" 's/^_own_view_veto() {$/_own_view_veto() { return 0/' "$WORK/s-noveto.sh"                       # [own-view] veto neutered
mutate "$STANDBY" 's/^_fresh_proof_recheck() {$/_fresh_proof_recheck() { return 0/' "$WORK/s-norecheck.sh"       # the A8 fresh re-check neutered
mutate "$WORK/s-noveto.sh" 's/^_fresh_proof_recheck() {$/_fresh_proof_recheck() { return 0/' "$WORK/s-noboth.sh"  # both
mutate "$STANDBY" '/^attempt_takeover() {/,/^}/s/if \[\[ \${_own_bank_active_time:-0} -gt \$takeover_anchor \]\]; then/if false; then/' "$WORK/s-nod2.sh"   # D2's anchor input dropped
mutate "$STANDBY" '/^    # \[elapsed-rate\] (6.3.1, D4 e)/,/the verdict-minting site (every layer passed)/{/the verdict-minting site (every layer passed)/!d;}' "$WORK/s-norate.sh"   # [elapsed-rate] deleted
mutate "$WORK/s-norate.sh" 's/_es_own="\${_own_bank_active_time:-0}"$/_es_own=0/' "$WORK/s-nrno-a.sh" \
  && mutate "$WORK/s-nrno-a.sh" 's/if \[\[ \${_own_bank_active_time:-0} -gt \$_elapsed_since \]\]; then/if [[ 1 -eq 2 ]]; then/' "$WORK/s-norate-noown.sh"   # + [elapsed-own] (both halves)
mutate "$STANDBY" '/^take_staked_identity() {/,/^}/s/^    _own_head_sample$/    : pre-take sample removed/' "$WORK/s-nopretake.sh"   # the pre-take own-head sample removed
for _s in "$STANDBY" "$WORK"/s-*.sh; do seam_cut "$_s" >/dev/null; done
wlaunch() {   # wlaunch <name> VAR=val … — one world() in the background → $WORK/wr.<name>
    local n="$1"; shift
    ( for kv in "$@"; do export "$kv"; done; world 2>/dev/null | tail -1 > "$WORK/wr.$n" ) &
}
wr() { cat "$WORK/wr.$1" 2>/dev/null; }
wf() { field "$(wr "$1")" "$2"; }
# (2) D2 — the D0 race (holder resumes at t113 / t159; its votes reach the spare's bank, the tiers spliced),
# the intermittent holder (one vote at t40, MAX_DELINQUENT_SLOTS=15), the flickering own bank
wlaunch race      MDS=0 RESUME=113 HORIZON=140
wlaunch racea     ARMED=1 GATE=1 MDS=0 RESUME=159 HORIZON=185
wlaunch inter     MDS=15 RESUME=40 STOP=40 HORIZON=130
wlaunch inter_nd2 WSCRIPT="$WORK/s-nod2.sh" MDS=15 RESUME=40 STOP=40 HORIZON=130
wlaunch inter_nv  WSCRIPT="$WORK/s-noveto.sh" MDS=15 RESUME=40 STOP=40 HORIZON=130
wlaunch intera    ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200
wlaunch intera_nr WSCRIPT="$WORK/s-norate.sh" ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200
wlaunch intera_no WSCRIPT="$WORK/s-norate-noown.sh" ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200
wlaunch flk30_0   FLICKER=30 MDS=0 STARVE=300 HORIZON=370
wlaunch flk30_15  FLICKER=30 MDS=15 STARVE=300 HORIZON=330
wlaunch flk61_0   FLICKER=61 MDS=0 STARVE=300 HORIZON=190
wlaunch flk61_15  FLICKER=61 MDS=15 STARVE=300 HORIZON=130
# (3e) the controls: honest tiers 5 s behind, TIER2 answering 3 s late from t120 (the take cycle's reads
# spread in time), the holder resuming INSIDE the take at t128 (after the vote-FROZEN gate's read, before
# the re-check's) or at t130 (after the re-check's view, before the veto's); and the D2/D4 worlds un-vetoed
for _m in ship noveto norecheck noboth; do
    _ws=""; [[ "$_m" != "ship" ]] && _ws="WSCRIPT=$WORK/s-$_m.sh"
    wlaunch "in128_$_m" $_ws TIERMODE=honest TLAG=5 MDS=0 T2LAT=3 LATFROM=120 RESUME=128 HORIZON=140
done
wlaunch in130_ship   TIERMODE=honest TLAG=5 MDS=0 T2LAT=3 LATFROM=120 RESUME=130 HORIZON=140
wlaunch in130_noveto WSCRIPT="$WORK/s-noveto.sh" TIERMODE=honest TLAG=5 MDS=0 T2LAT=3 LATFROM=120 RESUME=130 HORIZON=140
wlaunch race_nv   WSCRIPT="$WORK/s-noveto.sh" MDS=0 RESUME=113 HORIZON=140
wlaunch cut100_nv WSCRIPT="$WORK/s-noveto.sh" CUT=100 CUTMODE=full RESUME=101 MDS=0 HORIZON=140
# (4) D4 — the spare cut off AFTER the episode opened, on the TIMER path (un-armed); the exposure below
# OWN_HEAD_H; the slow-tier take cycles (the pre-take sample); the rate layer at 2.0 / 2.5 / 2.525 / 3.7 slots/s
wlaunch cut80     CUT=80 CUTMODE=full RESUME=90 MDS=0 HORIZON=140
wlaunch cut109    CUT=109 CUTMODE=full RESUME=110 MDS=0 HORIZON=140
wlaunch cut110    CUT=110 CUTMODE=full RESUME=111 MDS=0 HORIZON=140
wlaunch cut15_64  CUT=64 CUTMODE=full RESUME=65 MDS=15 HORIZON=100
wlaunch cut15_65  CUT=65 CUTMODE=full RESUME=66 MDS=15 HORIZON=100
wlaunch t2d       T2DOWN=1 MDS=0 HORIZON=200
wlaunch t2d_np    WSCRIPT="$WORK/s-nopretake.sh" T2DOWN=1 MDS=0 HORIZON=200
wlaunch t2d_l6    T2DOWN=1 T3LAT_ALL=6 MDS=0 HORIZON=260
wlaunch t2d_l7    T2DOWN=1 T3LAT_ALL=7 MDS=0 HORIZON=260
wlaunch ra20      ARMED=1 GATE=1 MDS=0 SLOT_NUM=2 SLOT_DEN=1 HORIZON=260
wlaunch ra25      ARMED=1 GATE=1 MDS=0 SLOT_NUM=5 SLOT_DEN=2 HORIZON=260
wlaunch ra2525    ARMED=1 GATE=1 MDS=0 SLOT_NUM=101 SLOT_DEN=40 HORIZON=260
wlaunch ra37      ARMED=1 GATE=1 MDS=0 SLOT_NUM=37 SLOT_DEN=10 HORIZON=260
wlaunch ru20      MDS=0 SLOT_NUM=2 SLOT_DEN=1 HORIZON=200
wlaunch ru25      MDS=0 SLOT_NUM=5 SLOT_DEN=2 HORIZON=200
wlaunch ru37      MDS=0 SLOT_NUM=37 SLOT_DEN=10 HORIZON=200
# (6) D6 — the spare columns at MAX_DELINQUENT_SLOTS=15 (the MDS=0 ones are ru25/ru37/ra25/ra37 above)
wlaunch u25_15    MDS=15 SLOT_NUM=5 SLOT_DEN=2 HORIZON=150
wlaunch u37_15    MDS=15 SLOT_NUM=37 SLOT_DEN=10 HORIZON=150
wlaunch a25_15    ARMED=1 GATE=1 MDS=15 SLOT_NUM=5 SLOT_DEN=2 HORIZON=260
wlaunch a37_15    ARMED=1 GATE=1 MDS=15 SLOT_NUM=37 SLOT_DEN=10 HORIZON=200
wait

# ── (2) D2 — own-bank "holder voting" restarts the countdown ────────────────────────────────────────
echo ""; echo "─── (2) D2: the own bank's 'holder voting' re-anchors the countdown and restarts watchdog-elapsed's silence; the resets; the flicker cost ───"
if [[ "$(wf race mutation)" == "none" && "$(wf race ov_veto)" == "125:voting" && "$(wf race ob_first)" == "126" && "$(wf race end)" == "horizon" \
      && "$(wf racea mutation)" == "none" && "$(wf racea emint)" == "none" && "$(wf racea ob_first)" == "172" ]]; then
    ok "(2a) RED FIRST — the D0 race (the tiers spliced, the holder resuming; the 6.3 build took it at t125 after 12 s of renewed voting un-armed, and minted + took at t171 armed): the holder resuming at t113 → the take cycle's veto reads it VOTING at t125 and the own bank shows it current from t126 on, re-anchoring every cycle — no take by t140; armed (t159) → no mint and no take by t185 (own bank current from t172)"
else
    bad "(2a) race=$(wr race) :: armed=$(wr racea)"
fi
if [[ "$(wf inter mutation)" == "119" && "$(wf inter ob_last)" == "59" && "$(wf inter ov_veto)" == "none" \
      && "$(wf inter_nv mutation)" == "119" && "$(wf inter_nd2 mutation)" == "80" && "$(wf inter_nd2 ob_last)" == "59" ]]; then
    ok "(2b) RED FIRST — no take for a full TAKEOVER_DELAY after the last own-bank voting cycle: the intermittent holder (one vote at t40, MAX_DELINQUENT_SLOTS=15; the 6.3 build took at t80 on the original anchor, 40 s after it) — the own bank shows it current t53–t59, and the take waits to t119 = t59 + 60; with the veto neutered still t119 (D2 alone holds it — the holder is silent at the take, the veto passes); with D2's anchor input dropped (attempt_takeover's fourth input) → t80 again: the anchor input is what moves it, attributable apart from LAST_LIVENESS_ACTIVE_TIME"
else
    bad "(2b) inter=$(wr inter) :: veto-neutered=$(wr inter_nv) :: D2-anchor-neutered=$(wr inter_nd2)"
fi
if [[ "$(wf intera_nr emint)" == "159" && "$(wf intera_nr mutation)" == "159" && "$(wf intera_nr gate)" == "t=159 prov=watchdog-elapsed" \
      && "$(wf intera_no emint)" == "126" && "$(wf intera_no mutation)" == "126" && "$(wf intera emint)" == "none" && "$(wf intera mutation)" == "none" ]]; then
    ok "(2b-armed) RED FIRST — no watchdog-elapsed mint for a full floor after the last own-bank voting cycle (D2 ii): the armed intermittent holder (the 6.3 build minted + took at t126, 86 s after a vote its own bank saw) with [elapsed-rate] neutered (it abstains at exactly 2.5 slots/s — (4e) — and would mask this) → the mint and the gated take at t159 = t59 + the 100 s floor; [elapsed-own] neutered too (both halves) → t126 again; the SHIPPED tree → no mint, no take by t200"
else
    bad "(2b-armed) rate-neutered=$(wr intera_nr) :: +own-neutered=$(wr intera_no) :: shipped=$(wr intera)"
fi
# (2c) the episode-close sites, N-is-all: every non-global '_ep_blind_cycles=0' (the Block-3 episode close) and
# the standby's STAKED-branch close is followed within 3 lines by _own_view_reset; then the reset's behavior
rc_ok=1; rc_rows=""
for d in "$PRIMARY" "$STANDBY"; do
    sites=$(awk '/^[[:space:]]+.*_ep_blind_cycles=0|^[[:space:]]+_elapsed_reset "spare is STAKED/ {print NR}' "$d")
    n=0; nr=0
    for l in $sites; do
        n=$((n + 1))
        sed -n "$l,$((l + 3))p" "$d" | grep -q '^[[:space:]]*_own_view_reset' && nr=$((nr + 1))
    done
    rc_rows="$rc_rows $(basename "$d"):$nr/$n"
    [[ $n -eq 3 && $nr -eq 3 ]] || rc_ok=0
done
calls_s=$(code_of "$STANDBY" | grep -cE '^[[:space:]]*_own_view_reset[[:space:]]*$'); calls_p=$(code_of "$PRIMARY" | grep -cE '^[[:space:]]*_own_view_reset[[:space:]]*$')   # call sites (the definition line excluded)
wrs=$(
    set +e; _SIM_NOW=$T0; load_seam "$STANDBY"
    _own_bank_active_time=$((T0 + 5)); _own_bank_max_vote=900123; _own_head_ring="$T0:$T0:900100"; FIRST_DELINQUENT_TIME=$((T0 - 30))
    window_reset
    printf 'oba=%s|max=%s|ring=%s|fdt=%s' "$_own_bank_active_time" "$_own_bank_max_vote" "$_own_head_ring" "$FIRST_DELINQUENT_TIME"
)
if [[ $rc_ok -eq 1 && "$calls_s" == "3" && "$calls_p" == "3" && "$wrs" == "oba=0|max=|ring=|fdt=0" ]]; then
    ok "(2c) N-is-all — every episode-close site resets the own-view state:$rc_rows (standby: window_reset, the mostly-clear branch, the STAKED-tenure close; primary: switch_to_unstaked's and switch_to_staked's successes and the manual identity change — the recovery episode's closes), and _own_view_reset is called nowhere else; behavior: window_reset on the REAL seam clears the own-bank stamp, the own-bank maximum and the own-head ring with the episode"
else
    bad "(2c) sites:$rc_rows calls standby=$calls_s primary=$calls_p window_reset → $wrs"
fi
if [[ "$(wf flk30_0 mutation)" == "none" && "$(wf flk30_0 starve)" == "365" && "$(wf flk30_0 E)" == "65" \
      && "$(wf flk30_15 mutation)" == "none" && "$(wf flk30_15 starve)" == "320" && "$(wf flk30_15 E)" == "20" \
      && "$(wf flk61_0 mutation)" == "182" && "$(wf flk61_0 ob_last)" == "122" && "$(wf flk61_15 mutation)" == "121" && "$(wf flk61_15 ob_last)" == "61" ]]; then
    ok "(2d) MEASURED AVAILABILITY COST (both presets) — a DEAD holder behind a FLICKERING own bank (its finalized view shows the holder current once every P s; the 6.3 build took at t125 / t80 whatever P): every not-delinquent answer restarts the countdown, so P = 30 s is NEVER taken — the starvation page fires at the episode's start + 300 s (t365 at MAX_DELINQUENT_SLOTS=0, t320 at 15) and the hold is loud; P = 61 s is taken one TAKEOVER_DELAY after the last flicker inside the episode (t182 = t122 + 60; t121 = t61 + 60). The line is P vs TAKEOVER_DELAY: a bank that flickers at least once per 60 s starves the takeover for as long as it flickers"
else
    bad "(2d) P30/MDS0=$(wr flk30_0) :: P30/MDS15=$(wr flk30_15) :: P61/MDS0=$(wr flk61_0) :: P61/MDS15=$(wr flk61_15)"
fi

# ── (3e) D3 — the controls: the veto bites; each guard alone holds; both neutered take ─────────────────
echo ""; echo "─── (3e) D3 controls: veto neutered alone → the D2/D4 worlds take; the re-check and the veto each alone hold; both neutered → the take ───"
if [[ "$(wf race_nv mutation)" == "125" && "$(wf race_nv hvafter)" == "1" && "$(wf cut100_nv mutation)" == "125" && "$(wf cut100_nv hvafter)" == "1" ]]; then
    ok "(3e-1) the veto neutered ALONE → the D2 world (the D0 race, resumed t113) and the D4 world (the spare cut off at t100) TAKE at t125 with the holder voting — as on the 6.3 build: the veto is what holds them at the take instant (the finalized own bank sees a t113 resumption only from t126)"
else
    bad "(3e-1) race veto-neutered=$(wr race_nv) :: cut veto-neutered=$(wr cut100_nv)"
fi
if [[ "$(wf in128_ship mutation)" == "none" && "$(wf in128_noveto mutation)" == "none" \
      && "$(wf in128_norecheck mutation)" == "none" && "$(wf in128_norecheck ov_veto)" == "131:voting" \
      && "$(wf in128_noboth mutation)" == "131" && "$(wf in128_noboth holder_voting_at_mut)" == "3" ]]; then
    ok "(3e-2) EACH ALONE HOLDS, the ALL-NEUTERED control takes — the holder resuming at t128 inside a take cycle stretched by a slow TIER2 (after the vote-FROZEN gate's read, before the re-check's): shipped → held (the re-check aborts first); the veto neutered → held by the re-check; the re-check neutered → held by the veto (VOTING at t131); BOTH neutered → the take MUTATES at t131 with the holder voting for 3 s"
else
    bad "(3e-2) shipped=$(wr in128_ship) :: noveto=$(wr in128_noveto) :: norecheck=$(wr in128_norecheck) :: noboth=$(wr in128_noboth)"
fi
if [[ "$(wf in130_ship mutation)" == "none" && "$(wf in130_ship ov_veto)" == "134:voting" && "$(wf in130_noveto mutation)" == "134" && "$(wf in130_noveto holder_voting_at_mut)" == "4" ]]; then
    ok "(3e-3) the veto's own window: the holder resuming at t130 — after the re-check's tier view (5 s behind), before the veto's read — is held ONLY by the veto (VOTING at t134); the veto neutered alone → taken at t134 with the holder voting for 4 s"
else
    bad "(3e-3) shipped=$(wr in130_ship) :: noveto=$(wr in130_noveto)"
fi

# ── (4) D4 — the spare's own head ─────────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) D4: (b) the own head advancing NOW at every take; the exposure below OWN_HEAD_H; the pre-take sample; (e) [elapsed-rate] ───"
if [[ "$(wf cut80 mutation)" == "none" && "$(wf cut80 ov_veto)" == "125:blind" && "$(wf cut109 mutation)" == "none" && "$(wf cut109 ov_veto)" == "125:blind" \
      && "$(wf cut15_64 mutation)" == "none" && "$(wf cut15_64 ov_veto)" == "80:blind" ]]; then
    ok "(4b) RED FIRST — the spare cut off AFTER the episode opened, on the TIMER path (the (11e) world: cut at t80 with the holder voting again from t90; the 6.3 build took at t125 — no spare-side gate, getHealth reads its own blockstore): the veto reads this spare's confirmed head NOT advancing past its sample of ≤ OWN_HEAD_H ago → BLIND at t125, no take; the same for a cut as late as t109 (MAX_DELINQUENT_SLOTS=0) and t64 (15)"
else
    bad "(4b) cut80=$(wr cut80) :: cut109=$(wr cut109) :: cut15@64=$(wr cut15_64)"
fi
if [[ "$(wf cut110 mutation)" == "125" && "$(wf cut110 hvafter)" == "1" && "$(wf cut110 ov_veto)" == "none" && "$(wf cut15_65 mutation)" == "80" && "$(wf cut15_65 hvafter)" == "1" ]]; then
    ok "(4b-residual) NAMED RESIDUAL — the exposure below OWN_HEAD_H, measured at its boundary: a cut at t110 (15 s before the t125 veto read; t65 before t80 at MAX_DELINQUENT_SLOTS=15) still passes — the confirmed head advanced from the oldest in-window sample up to the cut — and the take mutates with the holder voting (docs/SAFETY.md, 'The spare's own view'); one second earlier (t109 / t64) is BLIND (above)"
else
    bad "(4b-residual) cut110=$(wr cut110) :: cut15@65=$(wr cut15_65)"
fi
if [[ "$(wf t2d mutation)" == "150" && "$(wf t2d_np mutation)" == "none" && "$(wf t2d_np ov_veto)" == "150:blind" \
      && "$(wf t2d_l6 mutation)" == "168" && "$(wf t2d_l7 mutation)" == "none" && "$(wf t2d_l7 ov_veto)" == "171:blind" ]]; then
    ok "(4b-pretake) the PRE-TAKE own-head sample (take_staked_identity's head, before the re-check): a dead holder behind a dead TIER2 (every take-cycle read at its 10 s timeout) is taken at t150 — as on the 6.3 build; with that sample removed every veto is BLIND (the cycle's own sample is ~35 s old by the veto) and it is never taken. Its limit, measured: TIER2 down AND TIER3 answering 6 s late (a 16 s re-check) → taken at t168; 7 s late (17 s > OWN_HEAD_H) → every veto blind, no take (availability; the starvation page covers the hold)"
else
    bad "(4b-pretake) t2down=$(wr t2d) :: no-pretake=$(wr t2d_np) :: t3+6=$(wr t2d_l6) :: t3+7=$(wr t2d_l7)"
fi
oh_p=$(code_of "$PRIMARY" | grep -c '^OWN_HEAD_H=16 '); oh_s=$(code_of "$STANDBY" | grep -c '^OWN_HEAD_H=16 ')
oh_all=0; for _f in "$PRIMARY" "$STANDBY" "$HARNESS_DIR/install.sh" "$HARNESS_DIR/failover-arm.sh" "$HARNESS_DIR/deploy-failover.sh" "$HARNESS_DIR/deploy-failover-standby.sh"; do
    oh_all=$(( oh_all + $(code_of "$_f" | grep -cE '^[[:space:]]*((local|declare|export|readonly)[[:space:]]+([-][[:alnum:]]+[[:space:]]+)*)?OWN_HEAD_H=') ))   # ASSIGNMENT sites (a message naming OWN_HEAD_H=… is not one)
done
# the derivation, recomputed (x10 fixed point): the longest healthy hold of the confirmed head = 5 fully-skipped
# leader windows x 4 slots + 2 slots of confirmation jitter = 22 slots at the ASSUMED 2.5 slots/s; an age >= A
# puts the snapshots >= A - 2 - 2 - 1 s apart; the minimal A with (A - 5) > the hold, plus 2 s of sample spacing
hold10=$(( (5 * 4 + 2) * 10 * 2 / 5 )); a=0; while [[ $(( (a - 5) * 10 )) -le $hold10 ]]; do a=$((a + 1)); done
if [[ "$oh_p" == "1" && "$oh_s" == "1" && "$oh_all" == "2" && "$hold10" == "88" && $((a + 2)) -eq 16 ]]; then
    ok "(4c) OWN_HEAD_H = 16 s, derived on the page and recomputed here: a healthy confirmed head holds for at most 22 slots = 8.8 s at the assumed 2.5 slots/s; an age A puts the two snapshots at least A − 5 s apart (two 2 s read bounds + 1 s of mono_now truncation), so A = $a is the least with A − 5 > 8.8, + 2 s of sample spacing = 16 — assigned exactly once per daemon, inside [own-view] (the twin), and nowhere else in the shipped set"
else
    bad "(4c) OWN_HEAD_H census primary=$oh_p standby=$oh_s total=$oh_all; hold=$hold10 (x10) A=$a"
fi
if [[ "$(wf ra20 mutation)" == "none" && "$(wf ra20 emint)" == "none" && "$(wf ra25 emint)" == "none" && "$(wf ra25 mutation)" == "none" \
      && "$(wf ra2525 emint)" == "181" && "$(wf ra2525 mutation)" == "181" && "$(wf ra37 emint)" == "151" && "$(wf ra37 mutation)" == "151" \
      && "$(wf ru20 mutation)" == "145" && "$(wf ru25 mutation)" == "125" && "$(wf ru37 mutation)" == "105" ]]; then
    ok "(4e) RED FIRST — [elapsed-rate] (the spare's own confirmed head, ONE head at two TIMES): an own head at 2.0 slots/s MINTED on the 6.3 build (t191, the gated take with it) → no mint, no take by t260; the healthy rates, before → after: 2.5 slots/s t171 → NEVER (a FINDING: the abstaining bound 2·Δslot >= 5·(Δt+1) never certifies exactly the assumed rate), 2.525 t171 → t181 (one step later), 3.7 (mainnet, measured) t151 → t151 (unchanged); the un-armed timer path is untouched at every rate (t145 / t125 / t105)"
else
    bad "(4e) 2.0=$(wr ra20) :: 2.5=$(wr ra25) :: 2.525=$(wr ra2525) :: 3.7=$(wr ra37) :: un-armed 2.0/2.5/3.7=$(wf ru20 mutation)/$(wf ru25 mutation)/$(wf ru37 mutation)"
fi

# ── (5) D5 — the holder's latency demote reads its payload FIRST ──────────────────────────────────────
echo ""; echo "─── (5) D5: the holder's opt-in latency demote reads its payload FIRST (an ambiguity fails toward demoting) ───"
lat_drive() {   # $1=daemon → the REAL tier1_get_vote_latency, a holder voting EVERY slot (its lastVote = the finalized
    (           # head the instant the payload is served), every LOCAL read answering STALL s after its request
        set +e
        load_seam "$1"
        LCLK=$(mktemp "$WORK/lclk.XXXXXX"); echo "$T0" > "$LCLK"; LORD=$(mktemp "$WORK/lord.XXXXXX")
        _ln() { local x; read -r x < "$LCLK"; echo "$x"; }
        _la() { local x; read -r x < "$LCLK"; echo $(( x + $1 )) > "$LCLK"; }
        _lsl() { echo $(( HEAD0 + ($(_ln) - T0) * 5 / 2 - 32 )); }   # the finalized head now, at 2.5 slots/s
        STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; LOCAL_RPC="http://local.mock"; _watchdog_pet() { :; }
        curl() {
            local d=""; while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; *) shift ;; esac; done
            _la "${STALL:-0}"
            case "$d" in
                *getVoteAccounts*) printf 'gva;' >> "$LORD"; printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]},"id":1}' "$(_lsl)" ;;
                *getSlot*) printf 'slot;' >> "$LORD"; printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(_lsl)" ;;
                *) return 7 ;;
            esac
        }
        local lat; lat=$(tier1_get_vote_latency)
        echo "order=$(cat "$LORD")|lat=$lat"
    )
}
l0=$(STALL=0 lat_drive "$PRIMARY" | tail -1); l10=$(STALL=10 lat_drive "$PRIMARY" | tail -1)
s8=$(fn_body "$PRIMARY" tier1_get_vote_latency | head -1; n=$(grep -n '^tier1_get_vote_latency() {' "$PRIMARY" | cut -d: -f1); sed -n "$((n - 18)),$((n - 1))p" "$PRIMARY")
if [[ "$(field "$l0" order)" == "gva;slot;" && "$(field "$l0" lat)" == "0" && "$(field "$l10" order)" == "gva;slot;" && "$(field "$l10" lat)" == "25" ]] \
   && [[ "$s8" == *"This path is NOT part of the cross-node invariant"* && "$s8" == *"reads its PAYLOAD (getVoteAccounts) FIRST, then its REFERENCE"* ]]; then
    ok "(5) RED FIRST — the PRIMARY's tier1_get_vote_latency reads the payload (getVoteAccounts) FIRST, then the reference (getSlot): a holder voting every slot reads latency 0 with prompt reads and +25 slots when each read takes 10 s — a stall between the two can only make the holder look LESS current (demote sooner — the holder's side of the cost model); the 6.3 build read the reference first (slot;gva — the same stall read −25: more current, the demote up to a full loop cycle later). The S8 comment says so, and that this path is NOT part of the cross-node invariant (B bounds the self-fence only)"
else
    bad "(5) prompt=$l0 :: stalled=$l10 :: S8 comment present=$([[ "$s8" == *"This path is NOT part of the cross-node invariant"* ]] && echo yes || echo no)"
fi

# ── (6) D6 — the cross-node invariant table's SPARE columns ───────────────────────────────────────────
echo ""; echo "─── (6) D6: the spare's earliest take (un-armed timer) and earliest mint (armed watchdog-elapsed) from the holder's last vote ───"
# t=0 = the holder's last vote; a dead holder; the splicer tiers; both detect presets (MAX_DELINQUENT_SLOTS 0 —
# the daemon/template default — and 15, the wizard's); 2.5 slots/s (the assumed rate) and 3.7 (mainnet,
# measured). The armed column is the provider's earliest MINT (the gate is wired only in 6.4 — the world's
# GATE=1 emulation takes on it). The holder's fence column and the crossings: docs/SAFETY.md, 'The cross-node
# invariant'.
if [[ "$(wf ru25 mutation)" == "125" && "$(wf ru37 mutation)" == "105" && "$(wf u25_15 mutation)" == "80" && "$(wf u37_15 mutation)" == "75" ]] \
   && [[ "$(wf ra25 emint)" == "none" && "$(wf ra37 emint)" == "151" && "$(wf a25_15 emint)" == "none" && "$(wf a37_15 emint)" == "121" ]]; then
    ok "(6) the D6 spare columns, MEASURED: un-armed earliest take t125 / t105 at MAX_DELINQUENT_SLOTS=0 and t80 / t75 at 15 (2.5 / 3.7 slots/s — unchanged from the 6.3 build); armed watchdog-elapsed earliest MINT never / t151 at 0 and never / t121 at 15 (the 6.3 build: t171 / t151 and t126 / t121 — at exactly the assumed 2.5 slots/s [elapsed-rate] never certifies, (4e)). Against the holder's fence times these are the rows docs/SAFETY.md tabulates"
else
    bad "(6) un-armed 2.5/3.7 @0=$(wf ru25 mutation)/$(wf ru37 mutation) @15=$(wf u25_15 mutation)/$(wf u37_15 mutation) :: armed mint 2.5/3.7 @0=$(wf ra25 emint)/$(wf ra37 emint) @15=$(wf a25_15 emint)/$(wf a37_15 emint)"
fi

rm -rf "$WORK"
results_banner
