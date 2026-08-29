#!/bin/bash
# v0.7 (Block 6.2): THE G2 VERIFIED-DEMOTE PROOF PROVIDER (DESIGN-v0.7-ADDENDUM §2.4 +
# [rev3/№2], BLOCK6-PLAN §2, TASK-block62 D1–D5).
# COST MODEL under test: the worst outcome is DOUBLE-SIGN — the spare taking while the holder is
# alive. G2 is a PROOF provider: every ambiguity must answer cannot-determine or not-proven,
# NEVER proven; a forged/degenerate environment (cached RPC, replayed snapshots, one provider
# behind two names) must never mint a proven verdict. The gate stays UNWIRED into any take path
# (wiring is 6.4) — this suite exercises the provider through the gate's registry only.
#
# PRE-IMPL REDS (observed against 4c6ca1a BEFORE any Block-6.2 code, logged to the task
# scratchpad block62-preimpl-reds.log): grep census 0 hits for _g2_/G2_DELTA/G2_VANTAGE/
# G2_CLOCK_BUDGET/g2-provider in ALL six shipped scripts; armed+spare drive: _g2_step /
# _g2_register / _g2_provider rc=127 command-not-found; armed+spare+configured
# require_relinquish_proof → REFUSE rc 1 with MEASURED providers registered=0; the PAIRED
# startup line still claimed "no proof provider is registered in this build"; zero G2 knobs in
# env templates/wizards/docs; ci wall-clock pins 20/21 with daemons at 20/21.
#
# SECTIONS:
#   (1) registration + the vantage distinctness tripwire (startup, armed): defaults grounded in
#       the EXISTING tiers (A=TIER2_RPC, B=TIER3_RPC); identical URL / same host → CRITICAL page
#       + permanently cannot-determine; registration latch; unconfigured = silent no-registration;
#       and (C1 item 4, FLAGGED) the SHARED-VANTAGE degradation warn when the vantages ARE the
#       vote-liveness tiers — measured per pair, a WARN not a page, provider still registered,
#       with an off-tier control that must stay silent; the arm's URL-normalizer mirror (1j)
#   (2) the full state machine: baseline → T1(both vantages) → 60s hold → T2 → PROVEN; verdict
#       shape field-by-field against the stamps THIS RUNNER drove (observed_at = the T2 mono
#       stamp; observation_id carries gen+T1/T2; the freshness triple EQUALS dump_freshness's
#       seam values); require_relinquish_proof returns 0 with the verdict (the gate-level
#       acceptance path's FIRST real exerciser); the PAIRED posture line prints the MEASURED
#       registry; episode close → full reset → the gate refuses again
#   (3) the case table: no baseline → cannot; T1 one-vantage → cannot (retry); T1 absent →
#       not-proven; vantage unreachable → cannot (1 bounded read, no cascade); endpoint mismatch
#       → not-proven naming the foreign endpoint; mid-hold absence → NOT-PROVEN + full reset;
#       T2 absence → NOT-PROVEN + reset; proven verdict past PROOF_MAX_AGE → WITHDRAWN + re-arm
#   (4) detector reds (each refused LIVE, each accepted on ITS neutered mutant):
#       [rev3/№2] payload-advance — the RATIFIED control: a byte-identical cached pair (per-
#       vantage method-cache: distinct vantages, live clock) ACCEPTED as proof on the mutant;
#       cross-vantage identity (MY-1) — one source behind two names accepted on its mutant;
#       snapshot freshness (MY-2) — a replayed pair (advance present, cluster time 60s in the
#       past) accepted on its mutant; the ±25s boundary INCLUSIVE (25 passes, 26 refused, both
#       directions); getBlockTime is content-addressed (the request carries the vantage's OWN
#       slot — asserted from the live request log)
#   (5) D3 MULTILAYER RULE (the 6.1 lesson, mandatory): the full-frozen forgery under each
#       single neuter falls through to a SURVIVING layer (observed by the refusing layer's
#       reason, not assumed); ALL detector layers neutered at once → the forged acceptance red
#       RESTORED (the layer set is complete — no hidden guard); the replay forgery is owned
#       SOLELY by the freshness layer (its single neuter restores that red — named in SAFETY.md)
#   (6) boundedness + pets: live event ORDER census (every read immediately petted; at most one
#       bounded batch per step: 2 reads t1/t2, 1 hold/baseline, 0 proven) + the static census of
#       the region (4 curl sites == 4 per-op pet sites; zero sleep sites) — N-is-all, BOTH
#       censuses
#   (7) structural inertness census: un-armed → zero events/reads/state; armor-forced control
#       leaks (proves (7a) observes the armor); primary (holder) daemon armed → zero (role
#       adapter; _g2_incident_active never active there); unconfigured armed spare → zero
#   (8) constants census: G2_CLOCK_BUDGET/G2_DELTA assigned ONLY at the ONE derivation site per
#       daemon (broadened spellings, the proof-gate (11) idiom); zero sites in every other
#       shipped script; injection red on evading spellings; the budget→DELTA/compare COUPLING
#       moves together (mutant) with the decoupled control red
#   (9) twin byte-parity ([g2-provider] extract+cmp; [proof-gate] still identical after the 6.2
#       posture edits); call sites wired (main-loop _g2_step per daemon; _g2_register inside
#       _proof_startup_check); the region's ONE wall-clock line (the ci.yml pin bump 20→21/21→22)
#
# MUTATION COVERAGE (HARNESS.md discipline), all via mutate() (loud on no-op): the №2 advance
# compare (4b — the ratified control), the cross-vantage compare (4d), the freshness clamp (4f),
# the all-layers control (5d), the coupling double mutant (8d), the census injections (8b), the
# armor shim-force (7b). NAMED SURVIVORS: refusal texts are asserted by content, not mutation;
# the per-daemon role/incident adapters are exercised behaviorally ((7c): a one-line flip is a
# twin-visible diff outside the parity block); the tripwire host-compare is driven with real
# same-host inputs, not mutated.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "G2 verified-demote proof provider (v0.7 Block 6.2)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/g262.XXXXXX")
T0=100000            # mono origin (never 0 — 0 collides with the 0-sentinels under test)
EP="1.2.3.4:8001"    # the holder's staked gossip endpoint (the baseline anchor in every fixture)

harness_clock_shims
harness_silence_sinks

# the arm/daemon crc mechanics for PAIRED-posture fixtures (extracted from the STANDBY's own
# [proof-gate] helper — never a reimplementation; test_proof_gate (3a) proves all copies equal)
_crc_def=$(grep -m1 '^_pairing_crc()' "$STANDBY")
if [[ -z "$_crc_def" ]]; then
    bad "harness: cannot extract _pairing_crc from the standby daemon"
else
    eval "$_crc_def"
fi
mk_token() {   # $1=gen $2=w $3=b $4=fence $5=host → full token line on stdout
    local p="v0.7|gen=$1|watchdog=$2|relinquish_bound=$3|fence=$4|host=$5"
    printf '%s|%s\n' "$p" "$(_pairing_crc "$p")"
}

# ── drive_g2 <daemon> <case-fn> — the seam drive ────────────────────────────────────────────────
# Env knobs consumed from the caller's environment (all optional):
#   ARMED=0        un-armed drive (default armed)
#   G2PK=...       PRIMARY_UNSTAKED_PUBKEY override ("" = unconfigured; default UPK1)
#   VA/VB=...      explicit G2_VANTAGE_A/B (default unset → the daemon defaults from the tiers)
# The curl stub serves per-vantage fixtures from shell vars the case fn mutates between steps:
#   CN_A/CN_B      getClusterNodes bodies      A_DOWN/B_DOWN=1  vantage unreachable (rc 7)
#   SLOT_A/SLOT_B  getSlot results             BT_OFF_A/BT_OFF_B  getBlockTime = now + offset
# Every request is logged to $EV ("read <vantage> <method>[ slot=N]"), every pet as "pet" — the
# boundedness census reads THIS live order, never a reconstruction.
drive_g2() {
    local script="$1" fn="$2"
    (
        set +e
        _SIM_NOW=$T0
        EV=$(mktemp "$WORK/ev.XXXXXX")
        PROOF_STATE_DIR=$(mktemp -d "$WORK/ps.XXXXXX")
        load_seam "$script"
        STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1
        ALERT_THROTTLE=600
        TAKEOVER_DELAY=60
        TIER2_RPC="http://a.mock"; TIER3_RPC="http://b.mock"
        PRIMARY_UNSTAKED_PUBKEY="${G2PK-UPK1}"
        [[ -n "${VA:-}" ]] && G2_VANTAGE_A="$VA"
        [[ -n "${VB:-}" ]] && G2_VANTAGE_B="$VB"
        if [[ "${ARMED:-1}" == "1" ]]; then NOTIFY_SOCKET="$WORK/n.sock"; WATCHDOG_USEC=30000000; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        PAGES=0; PAGE_TITLES=""; LASTPAGE=""; WARNCT=0; LASTWARN=""; INFOCT=0; LASTINFO=""; AWCT=0; LASTAW=""
        alert() { PAGES=$((PAGES+1)); PAGE_TITLES="$PAGE_TITLES;$3"; LASTPAGE="$1"; }
        alert_warn() { AWCT=$((AWCT+1)); LASTAW="$1"; }
        alert_info() { :; }
        log_warn() { LASTWARN="$*"; WARNCT=$((WARNCT+1)); }
        log_info() { LASTINFO="$*"; INFOCT=$((INFOCT+1)); }
        log_error() { :; }
        _watchdog_pet() { echo "pet" >> "$EV"; }
        CN_A=""; CN_B=""; SLOT_A=1000; SLOT_B=2000; BT_OFF_A=0; BT_OFF_B=0; A_DOWN=0; B_DOWN=0
        # Block 6.2 panel fix round: the snapshot is now ONE JSON-RPC BATCH POST carrying
        # [getSlot(confirmed) id=A, getClusterNodes id=B]. The stub answers it as the real
        # endpoint does (design record verify-rpc-batch-and-churn.md, private tree): a 2-element
        # ARRAY echoing the ids the DAEMON chose — never ids the test invented.
        # SLOT_RATE_*: the vantage's confirmed head advances rate x elapsed sim seconds from its
        # base. 2 is a little under mainnet's ~2.5 slots/s and comfortably over the floor; 0 is a
        # FROZEN/replayed head (the slot-advance red).
        SLOT_RATE_A=2; SLOT_RATE_B=2
        # RAW_*: verbatim batch-response override (the batch-shape / id-echo reds). @IDA@/@IDB@/
        # @SLOT@ are substituted with what the DAEMON actually sent/what the stub actually served.
        RAW_A=""; RAW_B=""; BT_RAW_A=""; BT_RAW_B=""
        _slot_of() { if [[ "$1" == "A" ]]; then echo $(( SLOT_A + (_SIM_NOW - T0) * SLOT_RATE_A )); else echo $(( SLOT_B + (_SIM_NOW - T0) * SLOT_RATE_B )); fi; }
        curl() {
            local url="" d="" v p ida idb src nodes sl raw
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == "-d" ]]; then d="$2"; shift 2
                elif [[ "$1" == http* ]]; then url="$1"; shift
                else shift
                fi
            done
            v="A"; [[ "$url" == "${G2_VANTAGE_B:-http://b.mock}" ]] && v="B"
            if [[ "$v" == "A" && "$A_DOWN" == "1" ]]; then echo "read $v down" >> "$EV"; return 7; fi
            if [[ "$v" == "B" && "$B_DOWN" == "1" ]]; then echo "read $v down" >> "$EV"; return 7; fi
            case "$d" in
                "["*)
                    ida=${d#*\"id\":}; ida=${ida%%,*}
                    idb=${d##*\"id\":}; idb=${idb%%,*}
                    sl=$(_slot_of "$v")
                    echo "read $v batch slot=$sl ids=$ida,$idb" >> "$EV"
                    if [[ "$v" == "A" ]]; then raw="$RAW_A"; src="$CN_A"; else raw="$RAW_B"; src="$CN_B"; fi
                    if [[ -n "$raw" ]]; then
                        printf '%s' "$raw" | sed "s/@IDA@/$ida/g; s/@IDB@/$idb/g; s/@SLOT@/$sl/g"
                        return 0
                    fi
                    nodes=$(printf '%s' "$src" | jq -c '.result' 2>/dev/null)
                    [[ -z "$nodes" ]] && nodes=null
                    printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":%s}]' "$ida" "$sl" "$idb" "$nodes"
                    ;;
                *getClusterNodes*)
                    echo "read $v cn" >> "$EV"
                    if [[ "$v" == "A" ]]; then printf '%s' "$CN_A"; else printf '%s' "$CN_B"; fi
                    ;;
                *getBlockTime*)
                    p=${d#*'"params":['}; p=${p%%']'*}
                    ida=${d#*\"id\":}; ida=${ida%%,*}
                    echo "read $v bt slot=$p" >> "$EV"
                    if [[ "$v" == "A" ]]; then raw="$BT_RAW_A"; else raw="$BT_RAW_B"; fi
                    if [[ -n "$raw" ]]; then printf '%s' "$raw" | sed "s/@IDC@/$ida/g"; return 0; fi
                    if [[ "$v" == "A" ]]; then printf '{"jsonrpc":"2.0","id":%s,"result":%s}' "$ida" "$(( _SIM_NOW + BT_OFF_A ))"; else printf '{"jsonrpc":"2.0","id":%s,"result":%s}' "$ida" "$(( _SIM_NOW + BT_OFF_B ))"; fi
                    ;;
                *)
                    echo "read $v other" >> "$EV"
                    return 7
                    ;;
            esac
            return 0
        }
        # fixture builders: S1@EP is always present (the ~48h-lingering staked entry); the churn
        # entry differs per tag so live payloads ADVANCE byte-wise like real mainnet gossip.
        cn_present()   { printf '{"result":[{"pubkey":"S1","gossip":"%s"},{"pubkey":"UPK1","gossip":"%s"},{"pubkey":"churn%s","gossip":"9.9.9.9:1"}]}' "$EP" "$EP" "$1"; }
        cn_absent()    { printf '{"result":[{"pubkey":"S1","gossip":"%s"},{"pubkey":"churn%s","gossip":"9.9.9.9:1"}]}' "$EP" "$1"; }
        cn_misplaced() { printf '{"result":[{"pubkey":"S1","gossip":"%s"},{"pubkey":"UPK1","gossip":"5.6.7.8:9"},{"pubkey":"churn%s","gossip":"9.9.9.9:1"}]}' "$EP" "$1"; }
        # the watched key listed TWICE — elsewhere FIRST, at the baseline endpoint SECOND (the
        # multi-endpoint topology the shipped `head -1` presence test read as ABSENT: G2-N2)
        cn_multi_elsewhere_first() { printf '{"result":[{"pubkey":"S1","gossip":"%s"},{"pubkey":"UPK1","gossip":"9.9.9.9:1"},{"pubkey":"UPK1","gossip":"%s"},{"pubkey":"churn%s","gossip":"8.8.8.8:2"}]}' "$EP" "$EP" "$1"; }
        # a STORED batch answer replayed verbatim: fixed ids (7/8) that no live request ever asks
        # for, a frozen slot and a frozen node table. @-markers are NOT used, so the stub cannot
        # rewrite the ids — that is the point of the fixture.
        raw_stored_batch() { printf '[{"jsonrpc":"2.0","id":7,"result":424242},{"jsonrpc":"2.0","id":8,"result":[{"pubkey":"S1","gossip":"%s"},{"pubkey":"UPK1","gossip":"%s"},{"pubkey":"churn%s","gossip":"9.9.9.9:1"}]}]' "$EP" "$EP" "$1"; }
        # a NON-batch answer: one plain getClusterNodes response object (a provider that does not
        # implement batching, or an intermediary that split our batch)
        raw_batch_nodes() { printf '[{"jsonrpc":"2.0","id":@IDA@,"result":@SLOT@},{"jsonrpc":"2.0","id":@IDB@,%s}]' "$1"; }
        raw_single_object() { printf '{"jsonrpc":"2.0","id":@IDB@,"result":[{"pubkey":"S1","gossip":"%s"},{"pubkey":"UPK1","gossip":"%s"}]}' "$EP" "$EP"; }
        # reach_hold: register + baseline + open incident + T1 on both vantages → state=hold.
        # Advances _SIM_NOW by 2 per read step (>= the pace floor).
        reach_hold() {
            _g2_register
            FIRST_DELINQUENT_TIME=0
            CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
            _g2_step                                   # idle: baseline capture
            FIRST_DELINQUENT_TIME=$_SIM_NOW
            CN_A=$(cn_present t1a); CN_B=$(cn_present t1b)
            _g2_step                                   # idle → arm (t1a)
            _SIM_NOW=$(( _SIM_NOW + 2 )); T1A_TS=$_SIM_NOW; _g2_step   # t1a → t1b
            _SIM_NOW=$(( _SIM_NOW + 2 )); T1B_TS=$_SIM_NOW; _g2_step   # t1b → hold
        }
        "$fn"
    )
}

# ── (1) registration + the vantage distinctness tripwire ────────────────────────────────────────
echo ""; echo "─── (1) registration: tier-grounded defaults; tripwire pages + permanent cannot; latch ───"

case_register() {
    _g2_register
    _g2_register   # latch: a second call must not double-register
    echo "reg=$_g2_registered|prov=$_proof_providers|labels=$_proof_provider_labels|dis=${_g2_disabled:-}|va=$G2_VANTAGE_A|vb=$G2_VANTAGE_B|pages=$PAGES|warnct=$WARNCT|lastwarn=$LASTWARN|lastinfo=$LASTINFO"
}
r=$(drive_g2 "$STANDBY" case_register | tail -1)
if [[ "$(field "$r" reg)" == "1" && "$(field "$r" prov)" == "_g2_provider" && "$(field "$r" labels)" == "verified-demote" && -z "$(field "$r" dis)" ]] \
   && [[ "$(field "$r" va)" == "http://a.mock" && "$(field "$r" vb)" == "http://b.mock" && "$(field "$r" pages)" == "0" ]] \
   && [[ "$(field "$r" lastinfo)" == *"registered: verified-demote"* && "$(field "$r" lastinfo)" == *"DELTA=60s (30s CRDS bound + 25s clock budget + 5s purge/rounding)"* ]]; then
    ok "(1a) armed spare + configured → registered ONCE (latch holds on the double call), vantages defaulted from the EXISTING tiers (A=TIER2_RPC B=TIER3_RPC), no page, the log names DELTA's derivation"
else
    bad "(1a) $r"
fi
r=$(VA="http://same.mock/x" VB="http://same.mock/x" drive_g2 "$STANDBY" case_register | tail -1)
if [[ "$(field "$r" dis)" == *"G2_VANTAGE_A == G2_VANTAGE_B"* && "$(field "$r" pages)" == "1" && "$(field "$r" reg)" == "1" && "$(field "$r" prov)" == "_g2_provider" ]]; then
    ok "(1b) identical vantage URLs → CRITICAL page + G2 disabled (permanently cannot-determine this run); still registered so the gate sees the cannot verdict"
else
    bad "(1b) $r"
fi
r=$(VA="http://one.mock/key1" VB="http://one.mock/key2" drive_g2 "$STANDBY" case_register | tail -1)
if [[ "$(field "$r" dis)" == *"share one host 'one.mock'"* && "$(field "$r" pages)" == "1" ]]; then
    ok "(1c) distinct URLs on ONE host (two API keys, one provider) → tripwire fires on the HOST compare (one failure domain)"
else
    bad "(1c) $r"
fi
case_register_notiers() {
    TIER2_RPC=""
    unset G2_VANTAGE_A
    _g2_register
    echo "reg=$_g2_registered|dis=${_g2_disabled:-}|pages=$PAGES"
}
r=$(drive_g2 "$STANDBY" case_register_notiers | tail -1)
if [[ "$(field "$r" dis)" == *"fewer than two vantages"* && "$(field "$r" pages)" == "1" ]]; then
    ok "(1d) only one vantage resolvable → tripwire class (fewer than two) → page + disabled"
else
    bad "(1d) $r"
fi
case_disabled_verdict() {
    _g2_register
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    : > "$EV"
    _g2_step; _g2_step
    local v; v=$(_g2_provider)
    echo "reads=$(grep -c '^read' "$EV")|proven=$(_proof_field "$v" proven)|gst=$(_proof_field "$v" g2_state)|greason=$(_proof_field "$v" g2_reason)"
}
r=$(VA="http://same.mock/x" VB="http://same.mock/x" drive_g2 "$STANDBY" case_disabled_verdict | tail -1)
if [[ "$(field "$r" reads)" == "0" && "$(field "$r" proven)" == "cannot" && "$(field "$r" gst)" == "disabled" && "$(field "$r" greason)" == *"tripwire"* ]]; then
    ok "(1e) disabled G2 under an open incident: ZERO reads, the provider answers proven=cannot g2_state=disabled naming the tripwire — permanent cannot-determine, never silent absence"
else
    bad "(1e) $r"
fi

# (1h)/(1i) the SHARED-VANTAGE degradation warn (reviewer condition C1 item 4 — FLAGGED for
# ratification). On the DEFAULT config the daemon derives its vantages FROM TIER2_RPC/TIER3_RPC,
# which are exactly the endpoints every liveness reader iterates — so G2 and vote-liveness rest on
# one pair of boxes and the proof gate's additivity does not hold. Degraded, never disabled: the
# provider must still register and still answer. URL-level only by design (no DNS in the daemon).
r=$(drive_g2 "$STANDBY" case_register | tail -1)
if [[ "$(field "$r" warnct)" == "1" && "$(field "$r" lastwarn)" == *"SHARED VANTAGE (degraded, not disabled)"* ]] \
   && [[ "$(field "$r" lastwarn)" == *"G2_VANTAGE_A == TIER2_RPC by identical normalized URL"* ]] \
   && [[ "$(field "$r" lastwarn)" == *"G2_VANTAGE_B == TIER3_RPC by identical normalized URL"* ]] \
   && [[ "$(field "$r" lastwarn)" == *"BOTH halves of the double-sign condition"* && "$(field "$r" lastwarn)" == *"does NOT hold on this host"* ]] \
   && [[ "$(field "$r" lastwarn)" == *"third endpoint in a SEPARATE failure domain"* && "$(field "$r" pages)" == "0" ]] \
   && [[ "$(field "$r" reg)" == "1" && -z "$(field "$r" dis)" ]]; then
    ok "(1h) DEFAULT (tier-derived) vantages → ONE startup log_warn naming the MEASURED overlap per pair ('G2_VANTAGE_A == TIER2_RPC by identical normalized URL', same for B/TIER3), the consequence (one compromised vantage supplies BOTH halves of the double-sign condition; additivity does NOT hold) and the fix (a third endpoint in a separate failure domain) — a WARN, not a page (pages=0), and the provider stays REGISTERED and enabled: degraded, never disabled"
else
    bad "(1h) $r"
fi
# CONTROL: the SAME rig with the vantages pointed away from both tiers must stay SILENT — so (1h)
# observes the tier compare itself, not an unconditional warn.
r=$(VA="http://third.example/x" VB="http://fourth.example/y" drive_g2 "$STANDBY" case_register | tail -1)
if [[ "$(field "$r" warnct)" == "0" && "$(field "$r" reg)" == "1" && -z "$(field "$r" dis)" ]]; then
    ok "(1i) CONTROL: vantages pinned OFF the tiers (third.example / fourth.example vs TIER2 a.mock / TIER3 b.mock) → ZERO warns on the same rig — (1h)'s warn observes the vantage-vs-tier compare, not an unconditional line"
else
    bad "(1i) off-tier vantages still warned: $r"
fi

# (1f)/(1g) the vantage-host parse (L3-N2, panel fix round). The shipped `%%:*` cut truncated a
# bracketed IPv6 literal at its first colon, so ANY two IPv6 vantages collapsed to host "[" and
# tripped the same-host tripwire with a FALSE reason. The table below is driven through the REAL
# function on THIS interpreter, and the arm ceremony's mirror copy is driven through the SAME
# table — a silent drift between the two is a red, not a review item.
G2_URL_TABLE="https://a.example.com:8443/v1/key?x=1 http://b.io b.io:80/path https://x.y.z/? http://[::1]:8899/k https://[2001:db8::2]:443/rpc"
case_hosts() {
    local u out=""
    for u in $G2_URL_TABLE; do out="$out,$(_g2_url_host "$u")"; done
    out="$out,$(_g2_url_host "")"
    echo "table=${out#,}"
}
r=$(drive_g2 "$STANDBY" case_hosts | tail -1)
WANT_HOSTS="a.example.com,b.io,b.io,x.y.z,[::1],[2001:db8::2],"
if [[ "$(field "$r" table)" == "$WANT_HOSTS" ]]; then
    ok "(1f) _g2_url_host on this interpreter: $(field "$r" table) — bracketed IPv6 literals keep their brackets and lose only the port, so two distinct IPv6 vantages no longer collapse to host '[' and no longer trip the same-host tripwire with a false 'one failure domain' reason (L3-N2 red closed)"
else
    bad "(1f) host table: got '$(field "$r" table)' want '$WANT_HOSTS'"
fi
# the arm's mirror, extracted from the SHIPPED ceremony and driven over the same table
_p6_def=$(awk '/^_p6_url_host\(\) \{/,/^\}/' "$HARNESS_DIR/failover-arm.sh")
if [[ -z "$_p6_def" ]]; then
    bad "(1g) failover-arm.sh carries no _p6_url_host mirror (the P6 resolution check cannot parse vantage hosts)"
else
    arm_table=$( eval "$_p6_def"; out=""; for u in $G2_URL_TABLE; do out="$out,$(_p6_url_host "$u")"; done; printf '%s,' "${out#,}" )
    if [[ "$arm_table" == "$WANT_HOSTS" ]]; then
        ok "(1g) failover-arm.sh's _p6_url_host mirror produces the IDENTICAL table ($arm_table) — the P6 resolved-distinctness check parses vantage hosts exactly as the daemon's tripwire does; a drift between the copies is red here"
    else
        bad "(1g) arm mirror table: got '$arm_table' want '$WANT_HOSTS'"
    fi
fi
# (1j) the arm's _p6_norm_url mirror of the daemons' _norm_rpc_url (C1: the shared-vantage compare
# runs on BOTH sides and must normalize identically, or the arm and the daemon disagree about what
# "the same URL" is). Same ritual as (1f)/(1g): one table, both implementations, byte compare.
G2_NORM_TABLE="https://a.example.com:8443/v1/key?x=1 http://b.io/ http://b.io// http://c.io/path/ https://x.y.z"
_pn_def=$(awk '/^_p6_norm_url\(\) \{/,/^\}/' "$HARNESS_DIR/failover-arm.sh"); [[ -z "$_pn_def" ]] && _pn_def=$(grep -m1 '^_p6_norm_url()' "$HARNESS_DIR/failover-arm.sh")
_dn_def=$(grep -m1 '^_norm_rpc_url()' "$STANDBY")
if [[ -z "$_pn_def" || -z "$_dn_def" ]]; then
    bad "(1j) cannot extract _p6_norm_url (arm) and/or _norm_rpc_url (standby daemon)"
else
    arm_norm=$( eval "$_pn_def"; out=""; for u in $G2_NORM_TABLE; do out="$out,$(_p6_norm_url "$u")"; done; printf '%s' "${out#,}" )
    dmn_norm=$( eval "$_dn_def"; out=""; for u in $G2_NORM_TABLE; do out="$out,$(_norm_rpc_url "$u")"; done; printf '%s' "${out#,}" )
    if [[ -n "$arm_norm" && "$arm_norm" == "$dmn_norm" ]]; then
        ok "(1j) failover-arm.sh's _p6_norm_url and the daemon's _norm_rpc_url produce the IDENTICAL table ($arm_norm) — the arm's shared-vantage compare and the daemon's normalize URLs the same way; a drift between the copies is red here"
    else
        bad "(1j) norm-url drift: arm='$arm_norm' daemon='$dmn_norm'"
    fi
fi

# ── (2) the full state machine → PROVEN → the gate accepts ──────────────────────────────────────
echo ""; echo "─── (2) baseline→T1→hold→T2→PROVEN; verdict field-by-field; gate rc 0 (first real acceptance) ───"

case_happy() {
    printf '%s\n' "$(mk_token 7 30 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token"
    _liveness_first_provider="T2"; _liveness_obs_since=424242; _last_blind_end=99   # priming WRITES (only dump_freshness reads)
    reach_hold
    local hold_state="$_g2_state" hold_ep="$_g2_staked_endpoint" hold_reason="$_g2_reason"
    _SIM_NOW=$(( _SIM_NOW + 10 )); _g2_step                     # one mid-hold poll (present)
    local poll_reason="$_g2_reason"
    _SIM_NOW=$(( _SIM_NOW + 50 )); _g2_step                     # >= T1B+60 → t2a scheduled
    local t2_sched="$_g2_state"
    CN_A=$(cn_present t2a); CN_B=$(cn_present t2b)              # payloads ADVANCED per vantage
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step                      # t2a → t2b
    _SIM_NOW=$(( _SIM_NOW + 2 )); T2_TS=$_SIM_NOW; _g2_step     # t2b → proven
    local proven_warn="$LASTWARN"                               # the PROVEN log fires AT the mint
    local v; v=$(_g2_provider)
    require_relinquish_proof; local grc=$?
    local acc_info="$LASTINFO"                                  # the gate's ACCEPTED line, before later infos overwrite
    local fr; fr=$(dump_freshness)
    _proof_age_edge_check; local erc=$?
    local paired_line=""
    _proof_startup_check
    paired_line="$LASTINFO"
    FIRST_DELINQUENT_TIME=0
    _g2_step                                                    # episode close → reset
    local after_state="$_g2_state" after_info="$LASTINFO"
    require_relinquish_proof; local grc2=$?
    echo "hold=$hold_state|ep=$hold_ep|hreason=$hold_reason|preason=$poll_reason|t2s=$t2_sched|st=$_g2_state:proven-was|proven=$(_proof_field "$v" proven)|prov=$(_proof_field "$v" provider)|oid=$(_proof_field "$v" observation_id)|vant=$(_proof_field "$v" vantage)|since=$(_proof_field "$v" obs_since)|blind=$(_proof_field "$v" blind_until)|oat=$(_proof_field "$v" observed_at)|t1a=$T1A_TS|t1b=$T1B_TS|t2=$T2_TS|grc=$grc|erc=$erc|s_vant=$(field "$fr" vantage)|s_since=$(field "$fr" observed_since)|s_blind=$(field "$fr" blind_until)|pw=$proven_warn|acc=$acc_info|paired=$paired_line|after=$after_state|ainfo=$after_info|grc2=$grc2"
}
r=$(drive_g2 "$STANDBY" case_happy | tail -1)
t1a=$(field "$r" t1a); t1b=$(field "$r" t1b); t2=$(field "$r" t2)
if [[ "$(field "$r" hold)" == "hold" && "$(field "$r" ep)" == "$EP" && "$(field "$r" hreason)" == "hold 0s/60s — T1 stamps A=${t1a} B=${t1b}" ]] \
   && [[ "$(field "$r" preason)" == "hold 10s/60s" && "$(field "$r" t2s)" == "t2a" ]] \
   && [[ "$(field "$r" proven)" == "yes" && "$(field "$r" prov)" == "verified-demote" ]] \
   && [[ "$(field "$r" oid)" == "g2:gen=1:t1=${t1a}:t2=${t2}" && "$(field "$r" oat)" == "$t2" ]] \
   && [[ "$(field "$r" vant)" == "$(field "$r" s_vant)" && "$(field "$r" since)" == "$(field "$r" s_since)" && "$(field "$r" blind)" == "$(field "$r" s_blind)" && "$(field "$r" since)" == "424242" ]]; then
    ok "(2a) the machine reached PROVEN through baseline→T1→hold(60s, measured 'hold 10s/60s' mid-way)→T2; verdict field-by-field: proven=yes, provider=verified-demote, observation_id=g2:gen=1:t1=${t1a}:t2=${t2} (the runner's OWN stamps), observed_at = the T2 mono stamp, freshness triple == dump_freshness's seam values"
else
    bad "(2a) $r"
fi
if [[ "$(field "$r" grc)" == "0" && "$(field "$r" pw)" == *"verified-demote PROVEN"* && "$(field "$r" pw)" == *"held $(( t2 - t1a ))s (A) / $(( t2 - t1b ))s (B) >= 60s"* ]] \
   && [[ "$(field "$r" acc)" == *"relinquish proof ACCEPTED"* && "$(field "$r" acc)" == *"provider=verified-demote"* && "$(field "$r" acc)" == *"observation=g2:gen=1:t1=${t1a}:t2=${t2}"* ]]; then
    ok "(2b) require_relinquish_proof rc 0 with the ACCEPTED line naming provider + observation_id; the mint's PROVEN warn shows the MEASURED per-vantage holds ($(( t2 - t1a ))s/$(( t2 - t1b ))s >= 60s, from the runner's own stamps) — the gate-level acceptance path's FIRST real exerciser (pre-impl red: rc 1, providers registered=0)"
else
    bad "(2b) grc=$(field "$r" grc) pw=$(field "$r" pw) acc=$(field "$r" acc)"
fi
if [[ "$(field "$r" erc)" == "0" ]]; then
    ok "(2c) _proof_age_edge_check rc 0 on the fresh verdict (age = now − T2 read ≤ PROOF_MAX_AGE) — the 6.4 mutation-edge consumer composes without modification"
else
    bad "(2c) erc=$(field "$r" erc)"
fi
if [[ "$(field "$r" paired)" == *"armed spare PAIRED"* && "$(field "$r" paired)" == *"proof providers registered: verified-demote"* ]]; then
    ok "(2d) the PAIRED posture line prints the MEASURED registry ('proof providers registered: verified-demote') — the 6.1 'no proof provider is registered in this build' claim retired (claim=check)"
else
    bad "(2d) paired=$(field "$r" paired)"
fi
if [[ "$(field "$r" after)" == "idle" && "$(field "$r" ainfo)" == *"episode closed"* && "$(field "$r" grc2)" == "1" ]]; then
    ok "(2e) episode close → full reset (state idle, verdict dropped) → the gate REFUSES again (a proof never outlives its episode)"
else
    bad "(2e) after=$(field "$r" after) ainfo=$(field "$r" ainfo) grc2=$(field "$r" grc2)"
fi

# ── (3) the case table ──────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (3) case table: no-baseline/one-vantage/absent/unreachable/mismatch/mid-hold/T2-absence/age ───"

case_no_baseline() {
    _g2_register
    # registration-time warns are subtracted out: on the DEFAULT (tier-derived) vantages this rig
    # uses, _g2_register now emits the C1 shared-vantage degradation warn. The claim under test is
    # "the no-baseline warn fires ONCE PER EPISODE", so the counter must measure the EPISODE.
    local w0=$WARNCT
    FIRST_DELINQUENT_TIME=$_SIM_NOW     # incident opens with NO pre-incident cycle
    : > "$EV"
    _g2_step; local w1=$(( WARNCT - w0 ))
    _g2_step; local w2=$(( WARNCT - w0 ))
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)|warn=$LASTWARN|w1=$w1|w2=$w2|reads=$(grep -c '^read' "$EV")"
}
r=$(drive_g2 "$STANDBY" case_no_baseline | tail -1)
if [[ "$(field "$r" st)" == "idle" && "$(field "$r" proven)" == "cannot" && "$(field "$r" greason)" == *"no baseline captured pre-incident"* ]] \
   && [[ "$(field "$r" warn)" == *"NO baseline endpoint was captured pre-incident"* && "$(field "$r" w1)" == "1" && "$(field "$r" w2)" == "1" && "$(field "$r" reads)" == "0" ]]; then
    ok "(3a) no baseline ever captured → cannot-determine (the endpoint match is load-bearing; a mid-episode start must not trust fresh anchors), warned ONCE per episode, zero reads"
else
    bad "(3a) $r"
fi
case_one_vantage_t1() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    CN_A=$(cn_present t1a); CN_B=$(cn_absent t1b)   # present on A only
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1a (A ok)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1b: B absent → cannot, retry pair
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$STANDBY" case_one_vantage_t1 | tail -1)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" proven)" == "cannot" && "$(field "$r" greason)" == *"ABSENT on B at T1"* && "$(field "$r" greason)" == *"one-vantage view"* ]]; then
    ok "(3b) present on ONE vantage at T1 → cannot-determine (blind-ish), the whole T1 pair re-samples (no splice of a half-witnessed world)"
else
    bad "(3b) $r"
fi
case_absent_t1() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1a: absent
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$STANDBY" case_absent_t1 | tail -1)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" proven)" == "no" && "$(field "$r" greason)" == *"ABSENT at ${EP} on vantage A"* ]]; then
    ok "(3c) entry absent at T1 → NOT-PROVEN (proven=no), machine keeps trying while the episode is open"
else
    bad "(3c) $r"
fi
case_unreachable() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    _g2_step
    A_DOWN=1
    : > "$EV"
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1a: A unreachable
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)|reads=$(grep -c '^read' "$EV")|pets=$(grep -c '^pet' "$EV")"
}
r=$(drive_g2 "$STANDBY" case_unreachable | tail -1)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" proven)" == "cannot" && "$(field "$r" greason)" == *"snapshot batch unreachable (curl rc=7)"* ]] \
   && [[ "$(field "$r" reads)" == "1" && "$(field "$r" pets)" == "1" ]]; then
    ok "(3d) vantage unreachable → cannot-determine after exactly ONE bounded read (+1 pet: a timeout return IS completion) — no read cascade on a dead vantage"
else
    bad "(3d) $r"
fi
case_mismatch() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    CN_A=$(cn_misplaced m1); CN_B=$(cn_misplaced m2)
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1a: entry at a FOREIGN endpoint
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$STANDBY" case_mismatch | tail -1)
if [[ "$(field "$r" proven)" == "no" && "$(field "$r" greason)" == *"DIFFERENT endpoint 5.6.7.8:9"* && "$(field "$r" greason)" == *"proves nothing about THIS box"* ]]; then
    ok "(3e) watched key at a DIFFERENT endpoint → NOT-PROVEN naming the foreign endpoint (a publisher elsewhere is not the proof — the endpoint match is load-bearing)"
else
    bad "(3e) $r"
fi
case_midhold_absence() {
    reach_hold
    CN_A=$(cn_absent gone1); CN_B=$(cn_absent gone2)
    _SIM_NOW=$(( _SIM_NOW + 10 )); _g2_step          # mid-hold poll observes ABSENT
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|gen=$_g2_gen|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)|warn=$LASTWARN|t1a_cleared=$_g2_t1_ts_a"
}
r=$(drive_g2 "$STANDBY" case_midhold_absence | tail -1)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" gen)" == "2" && "$(field "$r" proven)" == "no" ]] \
   && [[ "$(field "$r" greason)" == *"mid-hold"* && "$(field "$r" warn)" == *"flip-then-flip-back kill"* && "$(field "$r" t1a_cleared)" == "0" ]]; then
    ok "(3f) entry ABSENT mid-hold → NOT-PROVEN + FULL state reset (T1 stamps cleared, fresh gen 2) — the flip-then-flip-back kill observed on the live poll"
else
    bad "(3f) $r"
fi
case_t2_absence() {
    reach_hold
    _SIM_NOW=$(( _SIM_NOW + 60 )); _g2_step          # hold → t2a (>= G2_DELTA=60)
    CN_A=$(cn_absent gone1); CN_B=$(cn_absent gone2)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t2a: absent
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|gen=$_g2_gen|proven=$(_proof_field "$v" proven)|warn=$LASTWARN"
}
r=$(drive_g2 "$STANDBY" case_t2_absence | tail -1)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" gen)" == "2" && "$(field "$r" proven)" == "no" && "$(field "$r" warn)" == *"T2 absence on vantage A"* ]]; then
    ok "(3g) entry absent at T2 → NOT-PROVEN + full reset (the hold proved nothing without its second endpoint-anchored observation)"
else
    bad "(3g) $r"
fi
case_age_withdrawal() {
    reach_hold
    _SIM_NOW=$(( _SIM_NOW + 60 )); _g2_step
    CN_A=$(cn_present t2a); CN_B=$(cn_present t2b)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # proven
    local st1="$_g2_state"
    : > "$EV"
    _SIM_NOW=$(( _SIM_NOW + 30 )); _g2_step          # age 30 <= PROOF_MAX_AGE=50 → dormant
    local reads_dormant; reads_dormant=$(grep -c '^read' "$EV")
    local st2="$_g2_state"
    local wct_before=$INFOCT
    _SIM_NOW=$(( _SIM_NOW + 21 )); _g2_step          # age 51 > 50 → withdrawn + re-arm (2 infos)
    echo "st1=$st1|st2=$st2|dorm=$reads_dormant|st3=$_g2_state|gen=$_g2_gen|infos=$(( INFOCT - wct_before ))|info=$LASTINFO"
}
r=$(drive_g2 "$STANDBY" case_age_withdrawal | tail -1)
if [[ "$(field "$r" st1)" == "proven" && "$(field "$r" st2)" == "proven" && "$(field "$r" dorm)" == "0" ]] \
   && [[ "$(field "$r" st3)" == "t1a" && "$(field "$r" gen)" == "2" && "$(field "$r" infos)" == "2" && "$(field "$r" info)" == *"re-prove after verdict aged out"* ]]; then
    ok "(3h) proven is DORMANT (zero reads at age 30) and a verdict past PROOF_MAX_AGE=50 is WITHDRAWN + re-armed as gen 2 with the aged-out reason (2 info lines: withdrawal + arm) — never served, never extended"
else
    bad "(3h) $r"
fi

# (3i) presence scans ALL gossip values (G2-N2, panel fix round). RED as shipped: `head -1` took
# the FIRST entry for the watched key and, if that entry sat elsewhere, recorded "different
# endpoint" and answered not-proven while the REAL entry sat further down the same list. A false
# NEGATIVE — safe direction, availability only — but it suppresses a genuine proof, and it hit the
# mid-hold poll too, where it KILLS the attempt outright.
case_multi_endpoint() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    CN_A=$(cn_multi_elsewhere_first t1a); CN_B=$(cn_multi_elsewhere_first t1b)
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step                      # → hold
    local st_hold=$_g2_state
    _SIM_NOW=$(( _SIM_NOW + 10 )); _g2_step                     # mid-hold poll (the second head -1 site)
    local st_poll=$_g2_state gen_poll=$_g2_gen
    _SIM_NOW=$(( _SIM_NOW + 50 )); _g2_step                     # hold complete (10+50 >= 60) → t2a
    CN_A=$(cn_multi_elsewhere_first t2a); CN_B=$(cn_multi_elsewhere_first t2b)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    local v; v=$(_g2_provider)
    echo "sthold=$st_hold|stpoll=$st_poll|genpoll=$gen_poll|st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$STANDBY" case_multi_endpoint | tail -1)
if [[ "$(field "$r" sthold)" == "hold" && "$(field "$r" stpoll)" == "hold" && "$(field "$r" genpoll)" == "1" ]] \
   && [[ "$(field "$r" st)" == "proven" && "$(field "$r" proven)" == "yes" ]]; then
    ok "(3i) the watched key listed at a foreign endpoint FIRST and at the baseline endpoint SECOND → PROVEN: presence now scans ALL gossip values (T1, the mid-hold poll — which stayed in hold at gen 1 instead of firing a flip-back kill — and T2). 'different endpoint' is recorded only when NO entry matches"
else
    bad "(3i) $r"
fi
# CONTROL, red on the CURRENT mechanism: put the decision back on the FIRST entry (what head -1
# did) at BOTH presence sites and the same fixture must fail — otherwise (3i) is green for free.
mutate "$STANDBY" 's/index($ep) != null/(.[0] == $ep)/g' "$WORK/first-entry.sh"
r=$(drive_g2 "$WORK/first-entry.sh" case_multi_endpoint | tail -1)
if [[ "$(field "$r" proven)" != "yes" && "$(field "$r" greason)" == *"DIFFERENT endpoint 9.9.9.9:1"* ]]; then
    ok "(3j) CONTROL: decision put back on the FIRST entry (the shipped head -1 semantics) → the SAME topology reads as not-proven naming 9.9.9.9:1 — the false negative observed on the mutant, so (3i) measures the scan-all fix"
else
    bad "(3j) first-entry mutant did not reproduce the false negative: $r"
fi
# (3k) the episode must not span this spare's OWN staked tenure (L3-N1, panel fix round). The
# main loop calls _g2_reset at the STAKED-branch entry; here the reset's EFFECT is driven
# directly, and the call site itself is censused at (9d).
case_staked_interlude() {
    reach_hold
    local gen_hold=$_g2_gen t1a_hold=$_g2_t1_ts_a
    _SIM_NOW=$(( _SIM_NOW + 16 ))
    _g2_reset "spare is STAKED — episode closed (an attempt must never span our own staked tenure)"
    local st_after=$_g2_state t1a_after=$_g2_t1_ts_a verdict_after="$_g2_verdict"
    _SIM_NOW=$(( _SIM_NOW + 18 ))                       # the interlude ends: demoted again
    CN_A=$(cn_present r1a); CN_B=$(cn_present r1b)
    _g2_step                                            # idle + incident open → FRESH arm
    local st_resume=$_g2_state gen_resume=$_g2_gen t1a_resume=$_g2_t1_ts_a
    echo "genhold=$gen_hold|t1ahold=$t1a_hold|stafter=$st_after|t1aafter=$t1a_after|vlen=${#verdict_after}|stresume=$st_resume|genresume=$gen_resume|t1aresume=$t1a_resume"
}
r=$(drive_g2 "$STANDBY" case_staked_interlude | tail -1)
if [[ "$(field "$r" stafter)" == "idle" && "$(field "$r" t1aafter)" == "0" && "$(field "$r" vlen)" == "0" ]] \
   && [[ "$(field "$r" stresume)" == "t1a" && "$(field "$r" genresume)" == "2" && "$(field "$r" t1aresume)" == "0" ]]; then
    ok "(3k) a mid-hold attempt (gen $(field "$r" genhold), T1 stamped $(field "$r" t1ahold)) closed by the STAKED-branch reset drops state AND verdict; re-demotion starts a FRESH attempt (gen $(field "$r" genresume), T1 unset) instead of RESUMING the pre-interlude hold — an attempt can never span this spare's own staked tenure"
else
    bad "(3k) $r"
fi

# ── (4) detector reds — refused LIVE, accepted on the neutered mutant ───────────────────────────
echo ""; echo "─── (4) detectors: №2 cache (RATIFIED control) / cross-vantage / freshness+replay / boundary ───"

# fixtures as case fns (shared by live + mutant runs)
case_cached_pair() {   # per-vantage method-cache: distinct vantages, live clock, T2 bytes == T1 bytes
    reach_hold
    _SIM_NOW=$(( _SIM_NOW + 60 )); _g2_step
    CN_A=$(cn_present t1a); CN_B=$(cn_present t1b)   # SAME bytes as T1 (the cache serves storage)
    _SIM_NOW=$(( _SIM_NOW + 2 )); SPAN=$(( _SIM_NOW - T1A_TS )); _g2_step   # t2a: live detects HERE
    local mid_v mid_gen=$_g2_gen mid_aw="$LASTAW"
    mid_v=$(_g2_provider)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # mutant only: t2b → proven
    local v; v=$(_g2_provider)
    echo "midproven=$(_proof_field "$mid_v" proven)|midreason=$(_proof_field "$mid_v" g2_reason)|midgen=$mid_gen|span=$SPAN|lastaw=$mid_aw|st=$_g2_state|proven=$(_proof_field "$v" proven)|oat=$(_proof_field "$v" observed_at)"
}
r=$(drive_g2 "$STANDBY" case_cached_pair | tail -1)
span=$(field "$r" span)
if [[ "$(field "$r" midproven)" == "cannot" && "$(field "$r" midreason)" == *"BYTE-IDENTICAL across ${span}s"* && "$(field "$r" midreason)" == *"cache suspected"* ]] \
   && [[ "$(field "$r" midgen)" == "2" && "$(field "$r" lastaw)" == *"cache in front of the RPC"* && "$(field "$r" st)" != "proven" ]]; then
    ok "(4a) LIVE [rev3/№2]: byte-identical T1/T2 pair on a vantage (measured ${span}s apart — the runner's own span) → cannot-determine naming the cache + throttled page + re-arm — NEVER proven"
else
    bad "(4a) $r"
fi
mutate "$STANDBY" 's/"\$_g2_snap_hash" == "\$_g2_t1_hash_a"/1 -eq 2/; s/"\$_g2_snap_hash" == "\$_g2_t1_hash_b"/1 -eq 2/' "$WORK/no-advance.sh"
r=$(drive_g2 "$WORK/no-advance.sh" case_cached_pair | tail -1)
if [[ "$(field "$r" st)" == "proven" && "$(field "$r" proven)" == "yes" ]]; then
    ok "(4b) THE RATIFIED №2 CONTROL: advance detector neutered → the SAME byte-identical cached pair is ACCEPTED as proof (proven=yes, observed_at=$(field "$r" oat)) — the red the detector exists to kill, observed on the mutant"
else
    bad "(4b) №2-neutered mutant did not accept the cached pair: $r"
fi
case_crossvantage() {   # one cache behind two names: A and B serve the SAME bytes
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    CN_A=$(cn_present same); CN_B=$(cn_present same)
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1a
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1b: A==B → cannot (live)
    local st1="$_g2_state" aw1=$AWCT
    # second occurrence within the throttle window: page throttled, warn not
    CN_A=$(cn_present same2); CN_B=$(cn_present same2)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    local v; v=$(_g2_provider)
    echo "st1=$st1|st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)|aw1=$aw1|aw=$AWCT|warnct=$WARNCT|lastaw=$LASTAW"
}
r=$(drive_g2 "$STANDBY" case_crossvantage | tail -1)
if [[ "$(field "$r" st1)" == "t1a" && "$(field "$r" proven)" == "cannot" && "$(field "$r" greason)" == *"BYTE-IDENTICAL across vantages A and B"* ]] \
   && [[ "$(field "$r" aw1)" == "1" && "$(field "$r" aw)" == "1" && "$(field "$r" lastaw)" == *"one provider/cache behind two names"* ]]; then
    ok "(4c) LIVE cross-vantage [MY-1]: byte-identical payloads across the two vantages → cannot-determine + ONE throttled page across two occurrences (repeat inside ALERT_THROTTLE suppressed; per-event warns kept)"
else
    bad "(4c) $r"
fi
mutate "$STANDBY" 's/"\$_g2_t1_hash_a" == "\$_g2_snap_hash"/1 -eq 2/; s/"\$_g2_t2_hash_a" == "\$_g2_snap_hash"/1 -eq 2/' "$WORK/no-crossv.sh"
case_crossvantage_full() {   # A==B at T1 AND at T2, but T2 != T1 (advance passes), fresh clock
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    CN_A=$(cn_present same); CN_B=$(cn_present same)
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1b (mutant: passes → hold)
    _SIM_NOW=$(( _SIM_NOW + 60 )); _g2_step
    CN_A=$(cn_present same2); CN_B=$(cn_present same2)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)"
}
r=$(drive_g2 "$WORK/no-crossv.sh" case_crossvantage_full | tail -1)
if [[ "$(field "$r" st)" == "proven" && "$(field "$r" proven)" == "yes" ]]; then
    ok "(4d) CONTROL: cross-vantage detector neutered → the one-source-behind-two-names forgery is ACCEPTED (red observed: (4c) is green because the compare exists)"
else
    bad "(4d) cross-vantage-neutered mutant did not accept: $r"
fi
case_replayed_pair() {   # replay: per-vantage distinct, advance present, cluster time frozen 60s ago
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    BT_OFF_A=-60; BT_OFF_B=-60
    CN_A=$(cn_present r1a); CN_B=$(cn_present r1b)
    _g2_step
    : > "$EV"
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step           # t1a: skew -60 → cannot (live)
    local v; v=$(_g2_provider)
    # content-addressing, measured on the runner's OWN event log: the slot the stub served in
    # the BATCH line and the slot the daemon then asked getBlockTime about (never a figure the
    # assertion reconstructs — both are read back out of $EV)
    local batch_slot bt_slot
    batch_slot=$(grep -m1 '^read A batch ' "$EV" | sed 's/.*slot=\([0-9]*\) .*/\1/')
    bt_slot=$(grep -m1 '^read A bt slot=' "$EV" | sed 's/.*slot=//')
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)|bslot=$batch_slot|btslot=$bt_slot"
}
r=$(drive_g2 "$STANDBY" case_replayed_pair | tail -1)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" proven)" == "cannot" && "$(field "$r" greason)" == *"skew -60s outside ±25s"* ]] \
   && [[ -n "$(field "$r" bslot)" && "$(field "$r" bslot)" == "$(field "$r" btslot)" ]]; then
    ok "(4e) LIVE freshness [MY-2]: replayed snapshot (cluster time 60s in the past) → cannot-determine with the MEASURED skew; and the getBlockTime request carried EXACTLY the slot the BATCH returned alongside the proof payload (both read back from the live request log: batch slot=$(field "$r" bslot), getBlockTime slot=$(field "$r" btslot)) — the anchor is content-addressed to the body that carries the proof, not to a sibling request"
else
    bad "(4e) $r"
fi
case_boundary() {   # ±25 inclusive, ±26 refused — assert by whether t1a ADVANCES to t1b
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    _g2_step
    local out="" off st
    for off in -26 -25 25 26; do
        _g2_arm "boundary probe"
        BT_OFF_A=$off
        CN_A=$(cn_present "bp$off")
        _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
        st="refused"; [[ "$_g2_state" == "t1b" ]] && st="passed"
        out="$out $off:$st"
    done
    echo "probes=${out# }"
}
r=$(drive_g2 "$STANDBY" case_boundary | tail -1)
if [[ "$(field "$r" probes)" == "-26:refused -25:passed 25:passed 26:refused" ]]; then
    ok "(4f) clock-budget boundary: skew ±25s INCLUSIVE passes, ±26s refused — BOTH directions (past = replay, future = clock inversion), the inclusive-boundary convention this package uses everywhere (test_proof_gate (1i)/(1l))"
else
    bad "(4f) $r"
fi

# (3l) DEGENERATE CONTENT INSIDE A WELL-FORMED BATCH. The batch rewrite made the panel's original
# degenerate-body probes vacuous (they now die at [g2-det-batch] before their content is read), so
# the same class is re-established here against the CURRENT mechanism: the envelope is a valid
# 2-element array echoing our ids, and only the MEMBER CONTENT is degenerate. Every row must land
# cannot-determine or not-proven — never proven.
case_degen_member() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    RAW_A=$(raw_batch_nodes "$DEGEN_MEMBER"); [[ -n "${DEGEN_BT:-}" ]] && BT_RAW_A="$DEGEN_BT"
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)"
}
d_ok=1; d_n=0; d_reasons=""
# label :: member-of-the-batch :: optional getBlockTime override
for probe in \
  'empty-result-array::"result":[]::' \
  'member-has-no-result::"error":{"code":-32000,"message":"boom"}::' \
  'member-result-null::"result":null::' \
  'result-not-an-array::"result":"notanarray"::' \
  'entry-missing-gossip::"result":[{"pubkey":"UPK1"}]::' \
  'gossip-null::"result":[{"pubkey":"UPK1","gossip":null}]::' \
  'gossip-garbage::"result":[{"pubkey":"UPK1","gossip":"@@@garbage@@@"}]::' \
  'dup-pubkey-both-elsewhere::"result":[{"pubkey":"UPK1","gossip":"9.9.9.9:1"},{"pubkey":"UPK1","gossip":"7.7.7.7:2"}]::' \
  'blocktime-null::"result":[{"pubkey":"UPK1","gossip":"1.2.3.4:8001"}]::{"jsonrpc":"2.0","id":@IDC@,"result":null}' \
  'blocktime-string::"result":[{"pubkey":"UPK1","gossip":"1.2.3.4:8001"}]::{"jsonrpc":"2.0","id":@IDC@,"result":"soon"}' \
  'blocktime-error::"result":[{"pubkey":"UPK1","gossip":"1.2.3.4:8001"}]::{"jsonrpc":"2.0","id":@IDC@,"error":{"code":-32004,"message":"nope"}}' \
  'blocktime-foreign-id::"result":[{"pubkey":"UPK1","gossip":"1.2.3.4:8001"}]::{"jsonrpc":"2.0","id":999999,"result":100000}' \
  ; do
    lbl="${probe%%::*}"; rest="${probe#*::}"; mem="${rest%%::*}"; bt="${rest#*::}"
    d_n=$(( d_n + 1 ))
    r=$(DEGEN_MEMBER="$mem" DEGEN_BT="$bt" drive_g2 "$STANDBY" case_degen_member | tail -1)
    if [[ "$(field "$r" proven)" == "yes" ]]; then
        d_ok=0; bad "(3l) DEGEN[$lbl] MINTED PROVEN: $r"
    fi
    d_reasons="${d_reasons}$(field "$r" proven):$(field "$r" greason)
"
done
# NON-VACUITY CONTROL: the SAME rig with a HEALTHY member must advance past t1a. Without this,
# (3l) would be green for free if every row died on the rig instead of on its content.
r=$(DEGEN_MEMBER='"result":[{"pubkey":"UPK1","gossip":"1.2.3.4:8001"}]' DEGEN_BT="" drive_g2 "$STANDBY" case_degen_member | tail -1)
if [[ "$(field "$r" st)" != "t1b" ]]; then
    d_ok=0; bad "(3l) NON-VACUITY CONTROL FAILED: a healthy member in the same rig did not advance to t1b: $r"
fi
d_kinds=$(printf '%s' "$d_reasons" | sort -u | grep -c .)
[[ $d_ok -eq 1 ]] && ok "(3l) $d_n degenerate MEMBER contents inside a well-formed, correctly-id-echoed batch (empty/null/absent result, error member, non-array result, missing+null+garbage gossip, duplicate pubkey both elsewhere, and four bad getBlockTime answers incl. a foreign id echo) — every one lands cannot-determine or not-proven, NEVER proven. Re-established here because the batch rewrite made the pre-fix degenerate-body probes die at [g2-det-batch] before their content was ever parsed. Non-vacuity: a HEALTHY member in the SAME rig advances to t1b, and the $d_n rows die under ${d_kinds} DISTINCT measured reasons (not one blanket layer)"

# ── the B1 layers: batch shape, id echo, slot advance (panel fix round) ────────────────────────
# (4g) [g2-det-batch]: the snapshot answer must BE a batch response. A provider that does not
# implement JSON-RPC batching — or an intermediary that SPLITS our batch and answers only the
# getClusterNodes half — leaves the freshness anchor unbound to the payload, which is exactly the
# executed G2-B1 hole. Unbound = cannot-determine, never proven.
case_nonbatch() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    RAW_A=$(raw_single_object); RAW_B=$(raw_single_object)
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$STANDBY" case_nonbatch | tail -1)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" proven)" == "cannot" ]] \
   && [[ "$(field "$r" greason)" == *"did not answer the [getSlot,getClusterNodes] BATCH with a 2-element array"* ]]; then
    ok "(4g) LIVE [g2-det-batch]: a vantage answering the batch with ONE plain getClusterNodes object (no batching / a splitting proxy) → cannot-determine naming the unbound anchor — the freshness anchor must ride in the SAME response as the proof payload or nothing testifies"
else
    bad "(4g) $r"
fi
mutate "$STANDBY" 's/type == "array" and length == 2/type != "nosuchtype"/' "$WORK/no-shape.sh"
r=$(drive_g2 "$WORK/no-shape.sh" case_nonbatch | tail -1)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" proven)" == "cannot" ]] \
   && [[ "$(field "$r" greason)" == *"echoing our id="* ]]; then
    ok "(4h) CONTROL: shape check neutered → the same non-batch answer FALLS THROUGH to [g2-det-batch-id], which refuses it by the id echo (kill reason captured: '$(field "$r" greason)') — one neutered layer does not reopen the hole, and (4g) is green because the shape check exists"
else
    bad "(4h) shape-neutered mutant: $r"
fi
# (4i) [g2-det-batch-id]: a cache/replay serving a STORED batch answers with the ids it stored,
# not the fresh ones this process just sent. The echo alone kills it, before any content is read.
case_stale_ids() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    RAW_A=$(raw_stored_batch sA); RAW_B=$(raw_stored_batch sB)   # distinct bytes: cross-vantage stays silent
    CN_A=$(cn_present sA); CN_B=$(cn_present sB)                 # the cache serves the cheap hold poll too
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    local mid_state=$_g2_state mid_reason=$_g2_reason
    local i=0 kill="" gprev=$_g2_gen
    while [[ $i -lt 40 ]]; do
        _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
        [[ "$_g2_state" == "proven" ]] && break
        if [[ $_g2_gen -ne $gprev ]]; then kill="$_g2_reason"; break; fi
        i=$(( i + 1 ))
    done
    local v; v=$(_g2_provider)
    echo "midst=$mid_state|midreason=$mid_reason|st=$_g2_state|proven=$(_proof_field "$v" proven)|kill=$kill|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$STANDBY" case_stale_ids | tail -1)
if [[ "$(field "$r" midst)" == "t1a" && "$(field "$r" proven)" == "cannot" ]] \
   && [[ "$(field "$r" midreason)" == *"no usable getSlot member echoing our id="* ]]; then
    ok "(4i) LIVE [g2-det-batch-id]: a vantage replaying a STORED batch (ids 7/8, a frozen slot and a frozen node table) → cannot-determine at the FIRST read on the id echo alone ('$(field "$r" midreason)') — a passive cache cannot answer a request whose ids it has never seen"
else
    bad "(4i) $r"
fi
# CONTROL: neuter the FRESH-ID mechanism itself (reuse the very ids the replay stored). The echo
# check is untouched — this is what "the ids are fresh per request" is buying.
mutate "$STANDBY" 's/_g2_rid=$(( _g2_rid + 3 )); _g2s_ida=$_g2_rid; _g2s_idb=$(( _g2_rid + 1 )); _g2s_idc=$(( _g2_rid + 2 ))/_g2s_ida=7; _g2s_idb=8; _g2s_idc=9/' "$WORK/fixed-ids.sh"
r=$(drive_g2 "$WORK/fixed-ids.sh" case_stale_ids | tail -1)
if [[ "$(field "$r" midst)" == "t1b" && "$(field "$r" st)" != "proven" ]] \
   && [[ "$(field "$r" kill)" == *"confirmed head advanced only"* ]]; then
    ok "(4j) CONTROL: ids made static (7/8/9 — the ids the replay stored) → the SAME replay is now ACCEPTED past the echo (T1 advances) and falls through to [g2-det-slot-advance], which kills it: '$(field "$r" kill)'. Fresh ids are load-bearing, and the layer under them still holds"
else
    bad "(4j) fixed-id mutant: $r"
fi
# (4k) [g2-det-slot-advance]: the clock-free layer. This vantage batches honestly and echoes our
# ids, its node table churns, and its cluster time matches this spare exactly — everything the
# clock-based layers test passes — but its confirmed head is FROZEN.
case_frozen_head() {
    SLOT_RATE_A=0; SLOT_RATE_B=0
    reach_hold
    _SIM_NOW=$(( _SIM_NOW + 60 )); _g2_step
    CN_A=$(cn_present t2a); CN_B=$(cn_present t2b)
    _SIM_NOW=$(( _SIM_NOW + 2 )); SPAN=$(( _SIM_NOW - T1A_TS )); _g2_step
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|gen=$_g2_gen|proven=$(_proof_field "$v" proven)|greason=$(_proof_field "$v" g2_reason)|span=$SPAN|lastaw=$LASTAW"
}
r=$(drive_g2 "$STANDBY" case_frozen_head | tail -1)
span=$(field "$r" span)
if [[ "$(field "$r" st)" == "t1a" && "$(field "$r" gen)" == "2" && "$(field "$r" proven)" == "cannot" ]] \
   && [[ "$(field "$r" greason)" == *"vantage A confirmed head advanced only 0 slots across ${span}s"* ]] \
   && [[ "$(field "$r" greason)" == *"REQUIRED: >= 60"* && "$(field "$r" lastaw)" == *"floor 60"* ]]; then
    ok "(4k) LIVE [g2-det-slot-advance]: a vantage that batches honestly, echoes our ids, churns its node table and reports cluster time EXACTLY matching this spare (skew 0 — every clock-based layer passes) but whose confirmed head is FROZEN → cannot-determine with the MEASURED advance (0 slots across ${span}s, floor 60). Same mechanism, same direction, for a genuinely stalled cluster: cannot-determine, never proven"
else
    bad "(4k) $r"
fi
mutate "$STANDBY" 's/-lt $G2_SLOT_ADVANCE_FLOOR/-lt 0/g' "$WORK/no-slotadv.sh"
r=$(drive_g2 "$WORK/no-slotadv.sh" case_frozen_head | tail -1)
if [[ "$(field "$r" st)" == "t2b" || "$(field "$r" st)" == "proven" ]]; then
    ok "(4l) CONTROL: slot-advance floor neutered → the frozen-head snapshot pair is ACCEPTED past T2-A (state '$(field "$r" st)'), the red the floor exists to kill observed on the mutant"
else
    bad "(4l) slot-advance-neutered mutant did not accept the frozen head: $r"
fi

# ── (5) D3 multilayer rule: fall-through per single neuter; all-neutered restores the forgery ───
echo ""; echo "─── (5) multilayer: full-frozen forgery vs each single neuter; ALL neutered → forged PROVEN ───"

case_full_frozen() {   # THE archetype forgery: one frozen snapshot served for everything —
                       # A==B, T2==T1, cluster time frozen 60s in the past. Drives until the
                       # FIRST decisive outcome: a kill (gen increment — the refusing layer's
                       # reason captured at that instant) or PROVEN (a mutant let it through);
                       # a transient-cannot that never kills (the freshness stay-and-retry) runs
                       # the loop out and leaves its reason on the verdict.
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    BT_OFF_A=-60; BT_OFF_B=-60
    CN_A=$(cn_present frozen); CN_B=$(cn_present frozen)
    _g2_step
    local i=0 kill="" gprev=$_g2_gen
    while [[ $i -lt 40 ]]; do
        _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
        [[ "$_g2_state" == "proven" ]] && break
        if [[ $_g2_gen -ne $gprev ]]; then kill="$_g2_reason"; break; fi
        i=$(( i + 1 ))
    done
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|kill=$kill|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$STANDBY" case_full_frozen | tail -1)
if [[ "$(field "$r" proven)" == "cannot" && "$(field "$r" greason)" == *"skew -60s"* ]]; then
    ok "(5a) LIVE full-frozen forgery (cached everything) → cannot-determine; the freshness layer refuses FIRST (its reason on the verdict)"
else
    bad "(5a) $r"
fi
mutate "$STANDBY" 's/\[\[ \$_g2s_askew -le \$G2_CLOCK_BUDGET \]\]/[[ 0 -le 1 ]]/' "$WORK/no-clock.sh"
r=$(drive_g2 "$WORK/no-clock.sh" case_full_frozen | tail -1)
if [[ "$(field "$r" st)" != "proven" && "$(field "$r" kill)" == *"BYTE-IDENTICAL across vantages"* ]]; then
    ok "(5b) freshness neutered ALONE → the forgery FALLS THROUGH to the cross-vantage layer (its reason captured at the kill) — overlap holds, one neutered layer does not reopen the hole"
else
    bad "(5b) $r"
fi
mutate "$WORK/no-clock.sh" 's/"\$_g2_t1_hash_a" == "\$_g2_snap_hash"/1 -eq 2/; s/"\$_g2_t2_hash_a" == "\$_g2_snap_hash"/1 -eq 2/' "$WORK/no-clock-crossv.sh"
r=$(drive_g2 "$WORK/no-clock-crossv.sh" case_full_frozen | tail -1)
if [[ "$(field "$r" st)" != "proven" && "$(field "$r" kill)" == *"cache suspected"* ]]; then
    ok "(5c) freshness+cross-vantage neutered → the forgery falls through to the [rev3/№2] advance layer (cache reason captured at the kill) — the last standing layer still refuses"
else
    bad "(5c) $r"
fi
mutate "$WORK/no-clock-crossv.sh" 's/"\$_g2_snap_hash" == "\$_g2_t1_hash_a"/1 -eq 2/; s/"\$_g2_snap_hash" == "\$_g2_t1_hash_b"/1 -eq 2/' "$WORK/no-all.sh"
r=$(drive_g2 "$WORK/no-all.sh" case_full_frozen | tail -1)
if [[ "$(field "$r" st)" == "proven" && "$(field "$r" proven)" == "yes" ]]; then
    ok "(5d) freshness + cross-vantage + node-table advance ALL neutered → the full-frozen forgery mints PROVEN (the forged-acceptance red RESTORED) — those three are the complete guard set over THIS forgery shape (frozen CONTENT from a vantage that batches honestly): no hidden guard, no gap. The transport-class layers ([g2-det-batch], [g2-det-batch-id], [g2-det-slot-advance]) are orthogonal and get their own archetype at (5f)–(5k)"
else
    bad "(5d) all-neutered mutant did not restore the forged acceptance: $r"
fi
case_replay_to_proven() {   # the replay forgery driven to completion (distinct + advancing bytes)
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    BT_OFF_A=-60; BT_OFF_B=-60
    CN_A=$(cn_present r1a); CN_B=$(cn_present r1b)
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 60 )); _g2_step
    CN_A=$(cn_present r2a); CN_B=$(cn_present r2b)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)"
}
r=$(drive_g2 "$WORK/no-clock.sh" case_replay_to_proven | tail -1)
if [[ "$(field "$r" st)" == "proven" && "$(field "$r" proven)" == "yes" ]]; then
    ok "(5e) freshness neutered ALONE + the REPLAY forgery (advance present, distinct vantages) → ACCEPTED: replay is owned SOLELY by the freshness layer — no overlap there, which is exactly why the layer exists (residual named in SAFETY.md)"
else
    bad "(5e) $r"
fi

# (5f)–(5k) THE SECOND ARCHETYPE (panel fix round): the CACHED VANTAGE — one stored batch answer
# served for everything, on BOTH vantages. Stored ids (7/8), a frozen confirmed head, a frozen
# node table, identical bytes A and B, and an honest OLD cluster time for that old slot
# (BT_OFF −60). This is the shape the executed G2-B1/B2 attacks used, upgraded to a vantage that
# at least SPEAKS batch. The COMPLETE anti-forgery layer set it must run is:
#     [g2-det-batch] shape · [g2-det-batch-id] id echo · [g2-det-clock] skew ·
#     [g2-det-crossvantage] · [g2-det-slot-advance] · [g2-det-advance-a/-b] node table
# [g2-det-batch] is not reachable from THIS archetype (a stored batch IS an array) — its own red
# and fall-through control are (4g)/(4h). The five below are neutered one at a time, each showing
# the fall-through WITH the surviving layer's captured kill reason, and then all five at once,
# which must restore the forged acceptance.
case_cached_replay() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    BT_OFF_A=-60; BT_OFF_B=-60
    RAW_A=$(raw_stored_batch same); RAW_B=$(raw_stored_batch same)
    CN_A=$(cn_present same); CN_B=$(cn_present same)
    _g2_step
    local i=0 kill="" gprev=$_g2_gen
    while [[ $i -lt 40 ]]; do
        _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
        [[ "$_g2_state" == "proven" ]] && break
        if [[ $_g2_gen -ne $gprev ]]; then kill="$_g2_reason"; break; fi
        i=$(( i + 1 ))
    done
    local v; v=$(_g2_provider)
    echo "st=$_g2_state|proven=$(_proof_field "$v" proven)|kill=$kill|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$STANDBY" case_cached_replay | tail -1)
if [[ "$(field "$r" st)" != "proven" && "$(field "$r" greason)" == *"echoing our id="* ]]; then
    ok "(5f) LIVE cached-vantage archetype (one stored batch for everything, both vantages) → cannot-determine; [g2-det-batch-id] refuses FIRST, on the id echo"
else
    bad "(5f) $r"
fi
mutate "$STANDBY" 's/_g2_rid=$(( _g2_rid + 3 )); _g2s_ida=$_g2_rid; _g2s_idb=$(( _g2_rid + 1 )); _g2s_idc=$(( _g2_rid + 2 ))/_g2s_ida=7; _g2s_idb=8; _g2s_idc=9/' "$WORK/c1.sh"
r=$(drive_g2 "$WORK/c1.sh" case_cached_replay | tail -1)
if [[ "$(field "$r" st)" != "proven" && "$(field "$r" greason)" == *"skew -60s outside ±25s"* ]]; then
    ok "(5g) id echo neutered ALONE → the archetype falls through to [g2-det-clock], which refuses on the MEASURED skew ('$(field "$r" greason)')"
else
    bad "(5g) $r"
fi
mutate "$WORK/c1.sh" 's/\[\[ \$_g2s_askew -le \$G2_CLOCK_BUDGET \]\]/[[ 0 -le 1 ]]/' "$WORK/c2.sh"
r=$(drive_g2 "$WORK/c2.sh" case_cached_replay | tail -1)
if [[ "$(field "$r" st)" != "proven" && "$(field "$r" kill)" == *"BYTE-IDENTICAL across vantages"* ]]; then
    ok "(5h) id echo + freshness neutered → falls through to [g2-det-crossvantage] (kill reason captured: one source behind two names)"
else
    bad "(5h) $r"
fi
mutate "$WORK/c2.sh" 's/"\$_g2_t1_hash_a" == "\$_g2_snap_hash"/1 -eq 2/; s/"\$_g2_t2_hash_a" == "\$_g2_snap_hash"/1 -eq 2/' "$WORK/c3.sh"
r=$(drive_g2 "$WORK/c3.sh" case_cached_replay | tail -1)
if [[ "$(field "$r" st)" != "proven" && "$(field "$r" kill)" == *"confirmed head advanced only 0 slots"* ]]; then
    ok "(5i) id echo + freshness + cross-vantage neutered → the archetype reaches T2 and falls through to [g2-det-slot-advance], the CLOCK-FREE layer, which kills it on the measured 0-slot advance"
else
    bad "(5i) $r"
fi
mutate "$WORK/c3.sh" 's/-lt $G2_SLOT_ADVANCE_FLOOR/-lt 0/g' "$WORK/c4.sh"
r=$(drive_g2 "$WORK/c4.sh" case_cached_replay | tail -1)
if [[ "$(field "$r" st)" != "proven" && "$(field "$r" kill)" == *"cache suspected"* ]]; then
    ok "(5j) id echo + freshness + cross-vantage + slot advance neutered → the LAST standing layer [g2-det-advance-a] still refuses (the frozen node table: '$(field "$r" kill)')"
else
    bad "(5j) $r"
fi
mutate "$WORK/c4.sh" 's/"\$_g2_snap_hash" == "\$_g2_t1_hash_a"/1 -eq 2/; s/"\$_g2_snap_hash" == "\$_g2_t1_hash_b"/1 -eq 2/' "$WORK/c5.sh"
r=$(drive_g2 "$WORK/c5.sh" case_cached_replay | tail -1)
if [[ "$(field "$r" st)" == "proven" && "$(field "$r" proven)" == "yes" ]]; then
    ok "(5k) ALL FIVE reachable anti-forgery layers neutered at once → the cached-vantage archetype mints PROVEN (forged acceptance RESTORED). With [g2-det-batch] at (4g)/(4h), the enumerated set is complete over this acceptance: every single neuter above fell through to a NAMED surviving layer, and only removing all of them reopens the hole"
else
    bad "(5k) all-neutered mutant did not restore the forged acceptance: $r"
fi

# ── (6) boundedness + pets: live order census + static region census (N-is-all, both) ───────────
echo ""; echo "─── (6) boundedness: every read petted in live order; per-step read caps; zero sleeps ───"

case_bounded() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    echo "mark idle" >> "$EV";   _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    CN_A=$(cn_present t1a); CN_B=$(cn_present t1b)
    echo "mark arm" >> "$EV";    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); echo "mark t1a" >> "$EV"; _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); echo "mark t1b" >> "$EV"; _g2_step
    _SIM_NOW=$(( _SIM_NOW + 10 )); echo "mark hold" >> "$EV"; _g2_step
    _SIM_NOW=$(( _SIM_NOW + 50 )); echo "mark sched" >> "$EV"; _g2_step
    CN_A=$(cn_present t2a); CN_B=$(cn_present t2b)
    _SIM_NOW=$(( _SIM_NOW + 2 )); echo "mark t2a" >> "$EV"; _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); echo "mark t2b" >> "$EV"; _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); echo "mark proven" >> "$EV"; _g2_step
    echo "ev=$EV|st=$_g2_state"
}
r=$(drive_g2 "$STANDBY" case_bounded | tail -1)
EVF=$(field "$r" ev)
if [[ "$(field "$r" st)" == "proven" && -s "$EVF" ]]; then
    seg() {   # events between "mark $1" and the next mark
        awk -v m="mark $1" 'found && /^mark /{exit} found{print} $0==m{found=1}' "$EVF"
    }
    b_ok=1
    for probe in "idle:1" "arm:0" "t1a:2" "t1b:2" "hold:1" "sched:0" "t2a:2" "t2b:2" "proven:0"; do
        pn="${probe%%:*}"; want="${probe##*:}"
        got_r=$(seg "$pn" | grep -c '^read'); got_p=$(seg "$pn" | grep -c '^pet')
        if [[ "$got_r" != "$want" || "$got_p" != "$want" ]]; then
            b_ok=0; bad "(6a) step '$pn': reads=$got_r pets=$got_p (want $want/$want)"
        fi
    done
    # strict alternation: every read line is IMMEDIATELY followed by its pet (live order, no batch-then-pet)
    alt_ok=$(awk '/^read/{if(p=="read"){print "VIOLATION"; exit}} {p=($0 ~ /^read/)?"read":"other"} END{print "ok"}' "$EVF" | tail -1)
    if [[ $b_ok -eq 1 && "$alt_ok" == "ok" ]]; then
        ok "(6a) live event-order census: reads per step = idle 1 / arm 0 / T1 2+2 / hold-poll 1 / schedule 0 / T2 2+2 / proven 0 — RE-MEASURED for the batch (the snapshot's getSlot rides INSIDE the getClusterNodes POST, so a snapshot is 2 reads, not 3); every read IMMEDIATELY petted (strict alternation in the live log; a timeout return pets too, (3d))"
    elif [[ "$alt_ok" != "ok" ]]; then
        bad "(6a) a read was not followed by its pet (live order violation)"
    fi
else
    bad "(6a) drive failed: $r"
fi
# static census of the region (the N-is-all second census): 4 curl sites, 4 per-op pet sites,
# zero sleep invocations, exactly ONE wall-clock line (the ci pin's subject). RE-DERIVED in the
# 6.2 panel fix round: the snapshot batch merged the old separate getSlot read into the
# getClusterNodes read, so the region lost one curl site and its pet (5→4 each) — the pet pins in
# test_monitor_fence_integration (14b) moved with it, in this same diff.
REGION=$(extract_region "$STANDBY" '\[g2-provider\] verified-demote (G2) proof provider' '\[g2-provider\] end shared block')
if [[ -n "$REGION" ]]; then
    n_curl=$(printf '%s\n' "$REGION" | grep -c 'curl -s -m 5')
    n_pet=$(printf '%s\n' "$REGION" | grep -c '^[[:space:]]*_watchdog_pet\b')
    n_sleep=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -c '\bsleep\b')
    n_wall=$(printf '%s\n' "$REGION" | grep -c 'date +%s')
    n_m10=$(printf '%s\n' "$REGION" | grep -c 'curl -s -m 10')
    if [[ "$n_curl" == "4" && "$n_pet" == "4" && "$n_sleep" == "0" && "$n_wall" == "1" && "$n_m10" == "0" ]]; then
        ok "(6b) static region census: 4 bounded read sites (all curl -m 5, none unbounded/-m 10) == 4 per-op pet sites; ZERO sleep invocations (the state machine never blocks for DELTA); exactly ONE wall-clock line — still the ci.yml wall-clock pin's whole subject (the batch removed a READ, not a clock read: the pin does NOT move)"
    else
        bad "(6b) region census: curl=$n_curl pet=$n_pet sleep=$n_sleep wall=$n_wall m10=$n_m10"
    fi
fi

# ── (7) structural inertness census ─────────────────────────────────────────────────────────────
echo ""; echo "─── (7) inertness: un-armed zero; armor-forced leaks; holder role zero; unconfigured zero ───"

case_inert() {
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    CN_A=$(cn_present x); CN_B=$(cn_present x)
    _g2_register
    _g2_step; _g2_step
    local v; v=$(_g2_provider)
    echo "reg=$_g2_registered|prov=${_proof_providers:-}|reads=$(grep -c '^read' "$EV")|pages=$PAGES|warnct=$WARNCT|infoct=$INFOCT|st=$_g2_state|vlen=${#v}"
}
r=$(ARMED=0 drive_g2 "$STANDBY" case_inert | tail -1)
if [[ "$(field "$r" reg)" == "0" && -z "$(field "$r" prov)" && "$(field "$r" reads)" == "0" ]] \
   && [[ "$(field "$r" pages)$(field "$r" warnct)$(field "$r" infoct)" == "000" && "$(field "$r" st)" == "idle" && "$(field "$r" vlen)" == "0" ]]; then
    ok "(7a) UN-ARMED: register+step+provider under an open incident → ZERO reads/pages/logs/registry/state, provider prints NOTHING — the provider does not exist behaviorally (v0.6.x unchanged)"
else
    bad "(7a) $r"
fi
case_inert_forced() {
    _watchdog_active() { return 0; }    # the armor-forced control (the (7b) class)
    case_inert
}
r=$(ARMED=0 drive_g2 "$STANDBY" case_inert_forced | tail -1)
if [[ "$(field "$r" reg)" == "1" && "$(field "$r" warnct)" != "0" && "$(field "$r" infoct)" != "0" && "$(field "$r" vlen)" != "0" ]]; then
    ok "(7b) _watchdog_active forced open → the SAME un-armed drive LEAKS events (registered, info+warn logged, provider answers ${#r}B): (7a)'s zeros genuinely observe the armor, not an accident of config (the step stops at the no-baseline refusal — reads stay 0 for the RIGHT reason, itself asserted in (3a))"
else
    bad "(7b) armor-forced drive still inert: $r — (7a) proves nothing"
fi
r=$(drive_g2 "$PRIMARY" case_inert | tail -1)
if [[ "$(field "$r" reg)" == "0" && "$(field "$r" reads)" == "0" && "$(field "$r" pages)$(field "$r" warnct)$(field "$r" infoct)" == "000" && "$(field "$r" vlen)" == "0" ]]; then
    ok "(7c) PRIMARY (holder) daemon ARMED → zero everything: the role adapter scopes G2 to the spare posture (a healthy armed holder must never run relinquish proofs against itself)"
else
    bad "(7c) $r"
fi
case_incident_adapter() {
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    if _g2_incident_active; then echo "active=1"; else echo "active=0"; fi
}
r=$(drive_g2 "$PRIMARY" case_incident_adapter | tail -1)
r2=$(drive_g2 "$STANDBY" case_incident_adapter | tail -1)
if [[ "$(field "$r" active)" == "0" && "$(field "$r2" active)" == "1" ]]; then
    ok "(7d) _g2_incident_active adapters: primary NEVER active (no episode surface on the holder), standby active on FIRST_DELINQUENT_TIME>0 (the Option-A trigger surface)"
else
    bad "(7d) primary=$(field "$r" active) standby=$(field "$r2" active)"
fi
r=$(G2PK="" drive_g2 "$STANDBY" case_inert | tail -1)
if [[ "$(field "$r" reg)" == "0" && -z "$(field "$r" prov)" && "$(field "$r" reads)" == "0" && "$(field "$r" pages)$(field "$r" warnct)$(field "$r" infoct)" == "000" && "$(field "$r" vlen)" == "0" ]]; then
    ok "(7e) ARMED spare, NO PRIMARY_UNSTAKED_PUBKEY → zero G2 events (nothing to watch = no provider, silently; the posture line carries the registry state)"
else
    bad "(7e) $r"
fi
case_posture_none() {
    printf '%s\n' "$(mk_token 7 30 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token"
    _proof_startup_check
    echo "info=$LASTINFO"
}
r=$(G2PK="" drive_g2 "$STANDBY" case_posture_none | tail -1)
if [[ "$(field "$r" info)" == *"armed spare PAIRED"* && "$(field "$r" info)" == *"proof providers registered: NONE"* ]]; then
    ok "(7f) PAIRED + unconfigured G2 → the posture line says 'proof providers registered: NONE' (measured, claim=check — never the old static text)"
else
    bad "(7f) $r"
fi

# ── (8) constants census + the budget→DELTA coupling ────────────────────────────────────────────
echo ""; echo "─── (8) census: G2_CLOCK_BUDGET/G2_DELTA at ONE site; injection reds; coupling moves together ───"

# THREE constants since the panel fix round: G2_SLOT_ADVANCE_FLOOR joined the derivation site
# (the clock-free anti-replay floor, derived FROM G2_DELTA — one site, one chain).
G2_CONST_RE='(^[[:space:]]*((local|declare|export|readonly)[[:space:]]+([-][[:alnum:]]+[[:space:]]+)*)?(G2_DELTA|G2_CLOCK_BUDGET|G2_SLOT_ADVANCE_FLOOR)=)|(\(\([[:space:]]*(G2_DELTA|G2_CLOCK_BUDGET|G2_SLOT_ADVANCE_FLOOR)[[:space:]]*=)'
census_g2() {   # $1=file → rc 0 iff EXACTLY the three allowlisted assignment lines exist
    local f="$1" lines n
    lines=$(grep -nE "$G2_CONST_RE" "$f")
    n=$(printf '%s\n' "$lines" | grep -c .)
    [[ "$n" == "3" ]] || { CENSUS_FAIL="count=$n: $(printf '%s' "$lines" | tr '\n' ' ')"; return 1; }
    printf '%s\n' "$lines" | grep -q 'G2_CLOCK_BUDGET=25$'                       || { CENSUS_FAIL="budget line"; return 1; }
    printf '%s\n' "$lines" | grep -q 'G2_DELTA=\$(( 30 + G2_CLOCK_BUDGET + 5 ))' || { CENSUS_FAIL="delta line"; return 1; }
    printf '%s\n' "$lines" | grep -q 'G2_SLOT_ADVANCE_FLOOR=\$G2_DELTA$'     || { CENSUS_FAIL="slot-advance floor line"; return 1; }
    return 0
}
c_ok=1
for d in "$STANDBY" "$PRIMARY"; do
    census_g2 "$d" || { c_ok=0; bad "(8a) census failed on $(basename "$d"): $CENSUS_FAIL"; }
done
others=0
for f in "$HARNESS_DIR/install.sh" "$HARNESS_DIR/failover-arm.sh" "$HARNESS_DIR/deploy-failover.sh" "$HARNESS_DIR/deploy-failover-standby.sh" "$HARNESS_DIR/systemd/failover-fence.sh" "$HARNESS_DIR/systemd/failover-fence-page-only.sh"; do
    n=$(grep -cE "$G2_CONST_RE" "$f" 2>/dev/null)
    [[ "$n" == "0" ]] || { others=1; bad "(8a) $(basename "$f") re-declares a G2 constant ($n sites)"; }
done
if [[ $c_ok -eq 1 && $others -eq 0 ]]; then
    ok "(8a) census: G2_CLOCK_BUDGET=25, G2_DELTA=\$(( 30 + G2_CLOCK_BUDGET + 5 )) and G2_SLOT_ADVANCE_FLOOR=\$G2_DELTA assigned EXACTLY once per daemon (broadened spellings), zero sites in every other shipped script — the research record's own 60/25 (research-crds-staked-timeout.md:94), restored once per-provider floors retired the 60 s-timer fit"
fi
inj_ct=0; inj_red=0; inj_miss=""
for spell in 'G2_DELTA=10' 'local G2_CLOCK_BUDGET=5' 'declare -i G2_DELTA=9' 'export G2_CLOCK_BUDGET=7' ': $(( G2_DELTA=7 ))' '(( G2_CLOCK_BUDGET = 9 ))' 'G2_SLOT_ADVANCE_FLOOR=1' 'readonly G2_SLOT_ADVANCE_FLOOR=2'; do
    inj_ct=$((inj_ct + 1))
    cp "$STANDBY" "$WORK/inject.sh"; printf '\n%s\n' "$spell" >> "$WORK/inject.sh"
    if census_g2 "$WORK/inject.sh"; then
        inj_miss="$inj_miss [$spell]"
    else
        inj_red=$((inj_red + 1))
    fi
done
if [[ "$inj_red" == "$inj_ct" ]]; then
    ok "(8b) census RED on ALL $inj_ct evading spellings (bare + local + declare -i + export + two arithmetic forms) — the control's red-capability matches the claim's breadth"
else
    bad "(8b) $((inj_ct - inj_red))/$inj_ct spellings EVADED the census:$inj_miss"
fi
# (8c) coupling: G2_CLOCK_BUDGET 25→35 → G2_DELTA becomes 30+35+5=70 AND the freshness compare
# widens — TOGETHER. The probe skew is −30s: REFUSED on the shipped budget (25) and PASSING on the
# mutant (35), so "the compare widened" is measured on BOTH runs, not asserted from one.
mutate "$STANDBY" 's/^G2_CLOCK_BUDGET=25$/G2_CLOCK_BUDGET=35/' "$WORK/budget35.sh"
case_coupling() {
    _g2_register
    FIRST_DELINQUENT_TIME=0
    CN_A=$(cn_absent b1); CN_B=$(cn_absent b2)
    _g2_step
    FIRST_DELINQUENT_TIME=$_SIM_NOW
    BT_OFF_A=-30
    CN_A=$(cn_present c1)
    _g2_step
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    echo "delta=$G2_DELTA|st=$_g2_state"
}
rbase=$(drive_g2 "$STANDBY" case_coupling | tail -1)
r=$(drive_g2 "$WORK/budget35.sh" case_coupling | tail -1)
if [[ "$(field "$rbase" delta)" == "60" && "$(field "$rbase" st)" == "t1a" ]] \
   && [[ "$(field "$r" delta)" == "70" && "$(field "$r" st)" == "t1b" ]]; then
    ok "(8c) budget 25→35 mutant: G2_DELTA moves $(field "$rbase" delta)→$(field "$r" delta) AND the SAME −30s skew that the shipped build REFUSES (state stayed $(field "$rbase" st)) now passes the compare (state $(field "$r" st)) — the budget and the hold move TOGETHER (coupled at the ONE derivation site, the N_HEAD/MARGIN pattern)"
else
    bad "(8c) base='$rbase' mutant='$r' (a static DELTA or a hardcoded compare is exactly the red this asserts against)"
fi
mutate "$WORK/budget35.sh" 's/^G2_DELTA=\$(( 30 + G2_CLOCK_BUDGET + 5 ))$/G2_DELTA=60/' "$WORK/decoupled.sh"
r=$(drive_g2 "$WORK/decoupled.sh" case_coupling | tail -1)
if [[ "$(field "$r" delta)" == "60" && "$(field "$r" st)" == "t1b" ]]; then
    ok "(8d) CONTROL: coupling additionally broken (static G2_DELTA=60) → budget=35 widens the compare (the −30s skew passes) while DELTA stays 60: (8c)'s together-assertion observed RED on the double mutant"
else
    bad "(8d) decoupled mutant gave: $r — the coupling control cannot be trusted"
fi

# (8e) the slot-advance floor is DERIVED, not a second free number: the budget mutant must move
# G2_SLOT_ADVANCE_FLOOR with G2_DELTA (one site, one chain), and the floor is what the refusal
# text actually prints — measured off the mutant, not recalled.
case_floor_coupling() {
    SLOT_RATE_A=0; SLOT_RATE_B=0     # frozen head → the floor's own refusal, whatever the floor is
    reach_hold
    _SIM_NOW=$(( _SIM_NOW + 80 )); _g2_step   # > the LARGEST DELTA driven here (the budget-35 mutant's 70) + margin: both mutants complete the hold, so the assertion measures the FLOOR, never the hold boundary
    CN_A=$(cn_present t2a); CN_B=$(cn_present t2b)
    _SIM_NOW=$(( _SIM_NOW + 2 )); _g2_step
    local v; v=$(_g2_provider)
    echo "floor=$G2_SLOT_ADVANCE_FLOOR|delta=$G2_DELTA|st=$_g2_state|greason=$(_proof_field "$v" g2_reason)"
}
r=$(drive_g2 "$WORK/budget35.sh" case_floor_coupling | tail -1)
r2=$(drive_g2 "$WORK/decoupled.sh" case_floor_coupling | tail -1)
if [[ "$(field "$r" floor)" == "70" && "$(field "$r" delta)" == "70" && "$(field "$r" greason)" == *"REQUIRED: >= 70"* ]] \
   && [[ "$(field "$r2" floor)" == "60" && "$(field "$r2" delta)" == "60" && "$(field "$r2" greason)" == *"REQUIRED: >= 60"* ]]; then
    ok "(8e) the slot-advance floor is DERIVED: on the budget 25→35 mutant it moves to $(field "$r" floor) with G2_DELTA=$(field "$r" delta) and the refusal PRINTS the moved value ('REQUIRED: >= 70'); on the decoupled mutant (budget 35 but a static G2_DELTA=60) the floor is $(field "$r2" floor) and prints 'REQUIRED: >= 60' — it tracks DELTA, not the budget, and never becomes a second free number"
else
    bad "(8e) budget35='$r' decoupled='$r2'"
fi

# ── (9) twin byte-parity + wiring + the wall-clock pin subject ──────────────────────────────────
echo ""; echo "─── (9) twin: [g2-provider] + [proof-gate] byte-identical; call sites wired; ci pin subject ───"

if extract_twin '\[g2-provider\] verified-demote (G2) proof provider' '\[g2-provider\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(9a) [g2-provider] region BYTE-IDENTICAL in both daemons ($(printf '%s' "$TWIN_P" | wc -c | tr -d ' ') bytes)"
else
    bad "(9a) [g2-provider] twin regions differ (primary=${#TWIN_P}B standby=${#TWIN_S}B)"
fi
if extract_twin '\[proof-gate\] spare-side relinquish-proof gate skeleton' '\[proof-gate\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(9b) [proof-gate] block STILL byte-identical after the 6.2 registry/posture edits"
else
    bad "(9b) [proof-gate] twin blocks differ after the 6.2 edits (primary=${#TWIN_P}B standby=${#TWIN_S}B)"
fi
w1=$(grep -c '_g2_step   #' "$STANDBY"); w2=$(grep -c '_g2_step   #' "$PRIMARY")
w3=$(grep -c '^    _g2_register   #' "$STANDBY"); w4=$(grep -c '^    _g2_register   #' "$PRIMARY")
w5=$(awk '/UNSTAKED \(normal\): 3-tier monitoring/{found=1} found && /_g2_step/{print; exit}' "$STANDBY" | grep -c '_g2_step')
if [[ "$w1$w2$w3$w4" == "1111" && "$w5" == "1" ]]; then
    ok "(9c) call sites wired: ONE _g2_step per main loop (standby inside the UNSTAKED branch — a promoted holder stops stepping; primary at loop top, role-inert) and ONE _g2_register inside _proof_startup_check per daemon"
else
    bad "(9c) wiring counts: step=$w1/$w2 register=$w3/$w4 unstaked-branch=$w5"
fi

# (9d) OUTSIDE-REGION executable G2 sites, per daemon (N-is-all, the census the inertness lens
# ran by hand): every call to a [g2-provider] entrypoint that lives outside the byte-identical
# region. Primary 2 (_g2_register in _proof_startup_check, the role-inert loop-top _g2_step);
# standby 3 (+ the STAKED-branch _g2_reset added in the panel fix round for L3-N1). A new site is
# a review-stop: it moves this pin in the same diff.
o_pri=$(sed "/\[g2-provider\] verified-demote (G2) proof provider/,/\[g2-provider\] end shared block/d" "$PRIMARY" | grep -cE '^[[:space:]]*_g2_(step|register|reset)\b')
o_sby=$(sed "/\[g2-provider\] verified-demote (G2) proof provider/,/\[g2-provider\] end shared block/d" "$STANDBY" | grep -cE '^[[:space:]]*_g2_(step|register|reset)\b')
# the reset must sit in the STAKED branch, between it and the next identity branch
staked_reset=$(awk '/^    elif \[\[ "\$CURRENT_IDENTITY" == "\$STAKED_PUBKEY" \]\]; then/{f=1} f && /^    (elif|else|fi)\b/ && !/STAKED_PUBKEY/{f=0} f' "$STANDBY" | grep -cE '^[[:space:]]*_g2_reset "spare is STAKED')
if [[ "$o_pri" == "2" && "$o_sby" == "3" && "$staked_reset" == "1" ]]; then
    ok "(9d) outside-region G2 call-site census: primary 2 (_g2_register + the role-inert loop-top _g2_step), standby 3 (+ the STAKED-branch _g2_reset, asserted to sit INSIDE that branch) — the L3-N1 episode close is wired exactly once, on the spare only"
else
    bad "(9d) outside-region G2 sites: primary=$o_pri (pin 2) standby=$o_sby (pin 3) staked-branch reset=$staked_reset (pin 1)"
fi

# ── (9e) the shared-vantage STANDING CONDITION reads word-identically everywhere ────────────────
# Reviewer ratification of the daemon WARN (6.2): "стоячее условие узнаётся по формулировке" — the
# operator who meets the phrase at the ceremony must find THAT phrase by grep in the logs a month
# later. The sentence is therefore ONE literal at four sites (arm P6, arm end-of-summary, the twin
# daemon WARN, SAFETY.md); each site keeps its own MEASURED clause and fix text around it. Guarded
# duplication needs a parity assert (the _pairing_crc / _p6_url_host precedent): a reworded copy
# must go RED, not silently break the grep. grep -F, never a regex — the sentence carries em
# dashes and an apostrophe.
CANON="G2 and vote-liveness SHARE VANTAGES: one compromised vantage supplies BOTH halves of the double-sign condition — a false verified-demote proof AND a false-frozen vote observation — so the proof gate's additivity does NOT hold on this host."
_CANON_ARM="$HARNESS_DIR/failover-arm.sh"   # this suite drives the daemons; the arm path is not otherwise needed here
c_arm=$(grep -Fc "$CANON" "$_CANON_ARM" 2>/dev/null | tr -d '[:space:]')
c_pri=$(grep -Fc "$CANON" "$PRIMARY" 2>/dev/null | tr -d '[:space:]')
c_sby=$(grep -Fc "$CANON" "$STANDBY" 2>/dev/null | tr -d '[:space:]')
c_saf=$(grep -Fc "$CANON" "$HARNESS_DIR/docs/SAFETY.md" 2>/dev/null | tr -d '[:space:]')
if [[ "$c_arm" == "2" && "$c_pri" == "1" && "$c_sby" == "1" && "$c_saf" == "1" ]]; then
    ok "(9e) the standing condition is WORD-IDENTICAL at all four operator-facing sites: failover-arm.sh ×2 (P6 + end-of-summary), both daemons ×1 (the twin WARN), docs/SAFETY.md ×1 — one grep finds every one"
else
    bad "(9e) standing-condition drift: arm=$c_arm (want 2) primary=$c_pri standby=$c_sby SAFETY=$c_saf (want 1 each) — a reworded copy breaks the operator's grep"
fi

rm -rf "$WORK"
results_banner
