#!/bin/bash
# v0.7 (Block 6.3): THE WATCHDOG-ELAPSED (ATTESTED TIME) PROOF PROVIDER (BLOCK6-PLAN §3/§0 + its two
# §5 pre-registrations; DESIGN-v0.7-ADDENDUM §2.1 + the §2.4 re-adopted independent-head item;
# TASK-block63 D0–D4).
# COST MODEL under test: the worst outcome is DOUBLE-SIGN — the spare taking while the holder is alive
# — and time is the weakest evidence kind, so every ambiguity must answer blind / no / cannot, NEVER
# proven. The gate stays UNWIRED into any take path (6.4): this suite drives the provider through the
# gate's registry only, and the D0 section's proof-gated take is an EMULATION of 6.4's documented
# placement, labelled as such, never shipped wiring.
#
# PRE-IMPL REDS (observed against the PRISTINE 84253ac tree before any 6.3 code, logged to the task
# scratchpad reds/block63-preimpl-reds.log): grep census 0 hits for _elapsed_ / [elapsed-provider] /
# _elapsed_provider / the "watchdog-elapsed" registry label in all six shipped scripts; on an
# armed+paired spare _elapsed_register/_elapsed_step/_elapsed_provider/_elapsed_reset rc=127; after
# _proof_startup_check with a valid token the registry held '_g2_provider'/'verified-demote' (or
# NONE with G2 unconfigured) and the PAIRED line printed exactly that; a paired spare with an open
# episode and 150 s of observed silence got require_relinquish_proof rc 1 (no provider).
#
# SECTIONS:
#   (1)  registration: ONLY a token that classifies ok at _derive_proof_floors registers (latch, the
#        MEASURED log, the PAIRED line prints the measured registry); none / page-only / invalid /
#        short-floor / overflowing tokens register NOTHING and emit NOTHING (the §2.7 posture is the
#        gate's loud part, not the provider's)
#   (2)  the mint: below floor → no (zero network reads); at the floor with the head inside ±N_HEAD →
#        PROVEN; verdict field-by-field against THIS runner's stamps; the triple == dump_freshness;
#        the gate accepts (rc 0) and the mutation-edge age check composes
#   (3)  the case table: lagged fleet → BLIND (boundary inclusive both sides), stale reference →
#        BLIND, blind interval mid-silence (the REAL seam writer) → the clock restarts, vote advance
#        (the REAL fence re-pin) → reset, token rot after registration → cannot, own read unusable →
#        blind and the seam UNTOUCHED, vantage flip / backwards / no pin / head unreachable → cannot,
#        aged verdict → dormant then WITHDRAWN and re-minted, the seam moving under a verdict →
#        withdrawn at the reporter, episode close / the STAKED-branch reset → dropped
#   (4)  the head reference: commitment=processed read from the live request log; the head is read
#        AFTER the payload (live order); the default-commitment mutant is wrong BOTH ways (a live
#        view permanently blind AND a 40-slot lagged view accepted)
#   (5)  D3 MULTILAYER (mandatory): the forged-silence archetype vs each single neuter (a NAMED
#        surviving layer refuses), the progressive chain, and ALL FOUR neutered → forged PROVEN
#   (6)  COUPLING [pre-registration (b)]: MARGIN_ELAPSED 10→20 moves the floor AND N_HEAD and the
#        provider's behavior follows (measured both ways); a decoupled static-N_HEAD control goes red
#   (7)  inertness census: un-armed / holder / unpaired → zero events; the armor-forced control leaks
#   (8)  boundedness + pets: live event order + the static region census (N-is-all, both censuses)
#   (9)  constants: the region assigns none of the four derived names; the N_HEAD condition comment
#        still sits at the derivation site in both daemons
#   (10) twins + call sites: [elapsed-provider] byte-identical; [proof-gate] and [g2-provider] still
#        identical; call-site census per daemon
#   (11) D0 — the executed input map, on the REAL standby main loop (the per-cycle own-bank entry
#        gate and the take cycle's read order, with the shipped gossip advisory too; the timing race
#        incl. the REAL provider under the 6.4 emulation; the intermittent holder; the partitioned
#        spare — fully cut off, on a minority fork with and without the supermajority's gossip — and
#        the lagging spare, armed and not) — each a MEASURED fact that docs/SAFETY.md states, so the
#        text cannot drift from the mechanism silently
#
# MUTATION COVERAGE (HARNESS.md discipline), all via mutate() (loud on no-op): the four layers of
# (5) alone and chained, the head compare boundary (3b-ctl), the head commitment (4b), the
# MARGIN_ELAPSED coupling + its decoupled control (6), the armor shim-force (7b). One what-if
# mutant lives in the (11) world instead, with its own loud apply-check: the own-bank read at
# commitment=processed (11f)/(11g) — the control showing which way the shipped finalized default
# cuts. NAMED SURVIVORS: refusal texts are asserted by content; the per-daemon adapters are
# exercised behaviorally (7c/7d).
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "watchdog-elapsed proof provider (v0.7 Block 6.3)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ep63.XXXXXX")
T0=100000            # mono origin (never 0 — 0 collides with the 0-sentinels under test)
HEAD0=900000         # the cluster head at T0 (slots; 2.5 slots/s where a world advances it)

harness_clock_shims
harness_silence_sinks

# the arm/daemon crc mechanics for token fixtures (extracted from the STANDBY's own [proof-gate]
# helper — never a reimplementation; test_proof_gate (3a) proves every copy equal)
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

# ── drive_ep <daemon> <case-fn> — the unit-level seam drive ────────────────────────────────────
# Env knobs from the caller (all optional): ARMED=0 (un-armed), TOK=ok|none|page-only|invalid|
# lowfloor|wrapw (default ok), G2PK (PRIMARY_UNSTAKED_PUBKEY; default "" = G2 unconfigured so the
# elapsed provider is the one under test).
# The curl stub serves (every request logged to $EV as "read <src> <method> comm=<c>", every pet as
# "pet" — the censuses read THIS live order):
#   LOCAL getSlot    HEAD at commitment=processed; HEAD-32 without one (the RPC default, finalized)
#   T2/T3 getVoteAccounts  the holder V1 at LV (delinquent list), one other validator at
#                    HEAD-VIEWLAG — so the payload's cluster-max = HEAD-VIEWLAG exactly
#   LOCAL_DOWN / T2_DOWN / T3_DOWN = 1 → rc 7 (unreachable)
drive_ep() {
    local script="$1" fn="$2"
    (
        set +e
        _SIM_NOW=$T0
        EV=$(mktemp "$WORK/ev.XXXXXX")
        PROOF_STATE_DIR=$(mktemp -d "$WORK/ps.XXXXXX")
        load_seam "$script"
        STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; VOTE_PUBKEY=V1
        ALERT_THROTTLE=600; TAKEOVER_DELAY=60; VOTE_LIVENESS_EPSILON=0
        LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
        PRIMARY_UNSTAKED_PUBKEY="${G2PK:-}"
        if [[ "${ARMED:-1}" == "1" ]]; then NOTIFY_SOCKET="$WORK/n.sock"; WATCHDOG_USEC=30000000; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        case "${TOK:-ok}" in
            ok)        printf '%s\n' "$(mk_token 7 30 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;
            page-only) printf '%s\n' "$(mk_token 7 30 60 page-only holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;
            invalid)   printf 'v0.7|gen=7|watchdog=30|relinquish_bound=60|fence=real|host=h|999\n' > "$PROOF_STATE_DIR/pairing-token" ;;
            lowfloor)  printf '%s\n' "$(mk_token 9 10 20 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;   # floor 10+20+10=40 < TAKEOVER_DELAY 60: a planted token that bypassed intake
            wrapw)     printf '%s\n' "$(mk_token 7 9223372036854775800 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;
            none)      : ;;
        esac
        PAGES=0; LASTPAGE=""; WARNCT=0; LASTWARN=""; INFOCT=0; LASTINFO=""; AWCT=0
        alert() { PAGES=$((PAGES+1)); LASTPAGE="$1"; echo "event page" >> "$EV"; }
        alert_warn() { AWCT=$((AWCT+1)); echo "event alert_warn" >> "$EV"; }
        alert_info() { echo "event alert_info" >> "$EV"; }
        log_warn() { LASTWARN="$*"; WARNCT=$((WARNCT+1)); echo "event log_warn" >> "$EV"; }
        log_info() { LASTINFO="$*"; INFOCT=$((INFOCT+1)); echo "event log_info" >> "$EV"; }
        log_error() { echo "event log_error" >> "$EV"; }
        _watchdog_pet() { echo "pet" >> "$EV"; }
        HEAD=$HEAD0; VIEWLAG=1; LV=5000; LOCAL_DOWN=0; T2_DOWN=0; T3_DOWN=0
        curl() {
            local url="" d="" src m comm
            while [[ $# -gt 0 ]]; do
                case "$1" in -d) d="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac
            done
            case "$url" in "$LOCAL_RPC") src=LOCAL ;; "$TIER2_RPC") src=T2 ;; "$TIER3_RPC") src=T3 ;; *) src=OTHER ;; esac
            case "$d" in *getVoteAccounts*) m=gva ;; *getSlot*) m=slot ;; *) m=other ;; esac
            comm=default; case "$d" in *'"commitment":"processed"'*) comm=processed ;; esac
            echo "read $src $m comm=$comm" >> "$EV"
            if [[ "$src" == "LOCAL" && "$m" == "slot" ]]; then
                [[ "$LOCAL_DOWN" == "1" ]] && return 7
                if [[ "$comm" == "processed" ]]; then printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$HEAD"; else printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(( HEAD - 32 ))"; fi
                return 0
            fi
            if [[ ( "$src" == "T2" || "$src" == "T3" ) && "$m" == "gva" ]]; then
                [[ "$src" == "T2" && "$T2_DOWN" == "1" ]] && return 7
                [[ "$src" == "T3" && "$T3_DOWN" == "1" ]] && return 7
                printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]},"id":1}' "$(( HEAD - VIEWLAG ))" "$LV"
                return 0
            fi
            return 7
        }
        # prime_seam <obs_since-offset> <blind_until-offset|none> — fixture WRITES of the Block-3 seam
        # (the sole-reader rule governs reads; priming writes stay): an open episode pinned to T2 with
        # baseline LV, observed since T0+<offset>
        prime_seam() {
            FIRST_DELINQUENT_TIME=$(( T0 - 10 ))
            _liveness_first_provider="T2"; _liveness_first_vote="$LV"; _liveness_first_tip=$(( HEAD - 40 )); _liveness_first_ts=$(( T0 + $1 ))
            _liveness_obs_since=$(( T0 + $1 ))
            if [[ "$2" == "none" ]]; then _last_blind_end=0; else _last_blind_end=$(( T0 + $2 )); fi
        }
        reg() { _proof_startup_check >/dev/null 2>&1; }   # the REAL registration path (G2 stays unregistered: G2PK empty)
        "$fn"
    )
}
reads_of() { grep -c '^read' "$1"; }

# ── (1) registration ───────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) registration: ONLY a token that classifies ok registers; everything else is silent ───"

case_register() {
    _proof_startup_check
    local paired="$LASTINFO"
    _elapsed_register; _elapsed_register   # the latch: repeated calls must not double-register
    echo "reg=$_elapsed_registered|fns=$_proof_providers|labels=$_proof_provider_labels|paired=$paired|pages=$PAGES|reads=$(reads_of "$EV")"
}
case_register_log() {
    : > "$EV"; INFOCT=0
    _elapsed_register
    echo "reg=$_elapsed_registered|info=$LASTINFO|infos=$INFOCT"
}
r=$(drive_ep "$STANDBY" case_register_log | tail -1)
if [[ "$(field "$r" reg)" == "1" && "$(field "$r" infos)" == "1" ]] \
   && [[ "$(field "$r" info)" == *"registered: watchdog-elapsed — token gen=7 (watchdog=30s, relinquish_bound=60s, fence=real) → floor 100s of observed silence (W+B+MARGIN_ELAPSED = 30+60+10), head cross-check ±25 slots against this spare's own bank (LOCAL_RPC getSlot, commitment=processed)"* ]]; then
    ok "(1a) armed spare + valid fence=real token → registered, ONE info line printing the MEASURED derivation (gen 7, W 30 + B 60 + MARGIN 10 = floor 100 s, N_HEAD 25, the head's source and commitment) — values read from the ONE derivation site"
else
    bad "(1a) $r"
fi
r=$(drive_ep "$STANDBY" case_register | tail -1)
if [[ "$(field "$r" reg)" == "1" && "$(field "$r" fns)" == "_elapsed_provider" && "$(field "$r" labels)" == "watchdog-elapsed" ]] \
   && [[ "$(field "$r" paired)" == *"armed spare PAIRED"* && "$(field "$r" paired)" == *"proof providers registered: watchdog-elapsed;"* && "$(field "$r" pages)" == "0" && "$(field "$r" reads)" == "0" ]]; then
    ok "(1b) through the REAL _proof_startup_check: registered ONCE (the latch holds across two extra calls), the registry is exactly '_elapsed_provider'/'watchdog-elapsed', the PAIRED line prints the MEASURED registry ('proof providers registered: watchdog-elapsed;' — pre-impl red: 'NONE'), zero pages, zero reads"
else
    bad "(1b) $r"
fi
r=$(G2PK="UPK1" drive_ep "$STANDBY" case_register | tail -1)
if [[ "$(field "$r" labels)" == "verified-demote watchdog-elapsed" && "$(field "$r" fns)" == "_g2_provider _elapsed_provider" && "$(field "$r" paired)" == *"proof providers registered: verified-demote watchdog-elapsed;"* ]]; then
    ok "(1c) G2 configured too → the registry lists BOTH providers in registration order and the PAIRED line prints 'verified-demote watchdog-elapsed' — measured, never a remembered claim (pre-impl red: 'verified-demote' alone)"
else
    bad "(1c) $r"
fi
case_noreg() {
    _elapsed_register; _elapsed_step
    local v; v=$(_elapsed_provider)
    echo "reg=$_elapsed_registered|fns=${_proof_providers:-}|vlen=${#v}|ev=$(grep -c . "$EV")|why=${_proof_floor_why:-}"
}
nr_ok=1; nr_rows=""
for tk in none page-only invalid lowfloor wrapw; do
    r=$(TOK=$tk drive_ep "$STANDBY" case_noreg | tail -1)
    if [[ "$(field "$r" reg)" == "0" && -z "$(field "$r" fns)" && "$(field "$r" vlen)" == "0" && "$(field "$r" ev)" == "0" ]]; then
        nr_rows="$nr_rows $tk"
    else
        nr_ok=0; bad "(1d) token '$tk' → $r"
    fi
done
[[ $nr_ok -eq 1 ]] && ok "(1d) tokens that do NOT classify ok at the derivation site —$nr_rows — register NOTHING: registry empty, provider prints nothing, ZERO events (logs/pages/reads) from the provider; the §2.7 scream stays the gate's job (test_proof_gate (6))"

# ── (2) the mint ───────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (2) below floor → no (zero network reads); at floor + head inside ±N_HEAD → PROVEN; verdict vs the runner's stamps ───"

case_mint() {
    reg
    prime_seam 0 none
    : > "$EV"
    _SIM_NOW=$(( T0 + 99 )); _elapsed_step
    local a99="$_elapsed_answer" r99="$_elapsed_reason" reads99; reads99=$(reads_of "$EV")
    _SIM_NOW=$(( T0 + 100 )); MINT_TS=$_SIM_NOW; _elapsed_step
    local reads100; reads100=$(reads_of "$EV")
    local pw="$LASTWARN" v; v=$(_elapsed_provider)
    local fr; fr=$(dump_freshness)
    require_relinquish_proof; local grc=$?
    local acc="$LASTINFO"
    _proof_age_edge_check; local erc=$?
    echo "a99=$a99|r99=$r99|reads99=$reads99|reads100=$reads100|mint=$MINT_TS|proven=$(_proof_field "$v" proven)|prov=$(_proof_field "$v" provider)|oid=$(_proof_field "$v" observation_id)|vant=$(_proof_field "$v" vantage)|since=$(_proof_field "$v" obs_since)|blind=$(_proof_field "$v" blind_until)|oat=$(_proof_field "$v" observed_at)|s_vant=$(field "$fr" vantage)|s_since=$(field "$fr" observed_since)|s_blind=$(field "$fr" blind_until)|grc=$grc|acc=$acc|erc=$erc|pw=$pw"
}
r=$(drive_ep "$STANDBY" case_mint | tail -1)
mint=$(field "$r" mint)
if [[ "$(field "$r" a99)" == "no" && "$(field "$r" r99)" == "observed silence 99s < elapsed_floor 100s (W+B+MARGIN_ELAPSED; observed_since=$T0)" && "$(field "$r" reads99)" == "0" ]]; then
    ok "(2a) 99 s of observed silence (one under the floor) → proven=no with the MEASURED silence and floor, ZERO network reads — no RPC is touched below the floor (only the local token re-classification runs)"
else
    bad "(2a) $r"
fi
if [[ "$(field "$r" proven)" == "yes" && "$(field "$r" prov)" == "watchdog-elapsed" && "$(field "$r" reads100)" == "2" ]] \
   && [[ "$(field "$r" oid)" == "elapsed:gen=7:since=${T0}:floor=100" && "$(field "$r" oat)" == "$mint" ]] \
   && [[ "$(field "$r" vant)" == "$(field "$r" s_vant)" && "$(field "$r" since)" == "$(field "$r" s_since)" && "$(field "$r" blind)" == "$(field "$r" s_blind)" && "$(field "$r" vant)" == "T2" ]]; then
    ok "(2b) at exactly the floor (100 s, the inclusive boundary) with the payload 1 slot behind the head → PROVEN after exactly 2 reads (the liveness payload + the head); verdict field-by-field: provider=watchdog-elapsed, observation_id=elapsed:gen=7:since=${T0}:floor=100 (token gen + the silence start + the floor), observed_at=${mint} (THIS runner's stamp at the read), the freshness triple == dump_freshness's seam values"
else
    bad "(2b) $r"
fi
if [[ "$(field "$r" grc)" == "0" && "$(field "$r" acc)" == *"relinquish proof ACCEPTED — provider=watchdog-elapsed observation=elapsed:gen=7:since=${T0}:floor=100"* && "$(field "$r" erc)" == "0" ]] \
   && [[ "$(field "$r" pw)" == *"watchdog-elapsed PROVEN (token gen=7): 100s of observed silence on vantage T2"* && "$(field "$r" pw)" == *"1 slots behind this spare's own head"* ]]; then
    ok "(2c) require_relinquish_proof rc 0 with the ACCEPTED line naming provider + observation_id (pre-impl red: rc 1, providers registered=0); _proof_age_edge_check rc 0 on it; the mint's PROVEN warn carries the MEASURED silence and head lag"
else
    bad "(2c) grc=$(field "$r" grc) erc=$(field "$r" erc) acc=$(field "$r" acc) pw=$(field "$r" pw)"
fi

# ── (3) the case table ─────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (3) case table: lag/stale-ref/blindness/life/token-rot/own-blind/pin/age/seam-moved/close ───"

case_lag() {   # $LAGS: space list of view lags (slots; negative = this spare's bank behind the view)
    reg; prime_seam 0 none
    local out="" l
    for l in $LAGS; do
        _elapsed_reset "probe"; _elapsed_last_read_ts=0
        VIEWLAG=$l; _SIM_NOW=$(( T0 + 120 )); _elapsed_step
        out="$out $l:$_elapsed_answer"
    done
    echo "probes=${out# }|reason=$_elapsed_reason"
}
r=$(LAGS="24 25 26 40" drive_ep "$STANDBY" case_lag | tail -1)
if [[ "$(field "$r" probes)" == "24:yes 25:yes 26:blind 40:blind" && "$(field "$r" reason)" == *"LAGGED VIEW: the liveness payload's cluster-max lastVote $(( HEAD0 - 40 )) is 40 slots behind this spare's own head ${HEAD0}; REQUIRED: <= N_HEAD=25"* ]]; then
    ok "(3a) lagged fleet: view 24/25 slots behind this spare's bank → PROVEN (25 = N_HEAD, inclusive), 26/40 → BLIND with the MEASURED lag — a lagged-but-answering fleet reads blind (wait), never frozen"
else
    bad "(3a) $r"
fi
r=$(LAGS="-25 -26 -90" drive_ep "$STANDBY" case_lag | tail -1)
if [[ "$(field "$r" probes)" == "-25:yes -26:blind -90:blind" && "$(field "$r" reason)" == *"STALE REFERENCE: this spare's own head ${HEAD0} is 90 slots behind the live payload's cluster-max $(( HEAD0 + 90 ))"* ]]; then
    ok "(3b) stale reference: this spare's own bank 25 slots behind the live view → PROVEN (inclusive), 26/90 behind → BLIND naming the stale reference — a lagging or cut-off bank cannot certify a view's freshness (the two-sided 'within')"
else
    bad "(3b) $r"
fi
mutate "$STANDBY" 's/-gt \$N_HEAD \]\]; then/-gt 999999999 ]]; then/g' "$WORK/nohead.sh"
r=$(LAGS="40 -90" drive_ep "$WORK/nohead.sh" case_lag | tail -1)
if [[ "$(field "$r" probes)" == "40:yes -90:yes" ]]; then
    ok "(3b-ctl) CONTROL: both head compares neutered → the 40-slot lagged view AND the 90-slot stale reference MINT PROVEN on the mutant — (3a)/(3b) are green because the compares exist"
else
    bad "(3b-ctl) head-neutered mutant did not accept: $r"
fi

case_blind_mid() {   # a REAL stamped blindness mid-silence, through the seam's own writer
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 60 )); _note_blind_cycle "$_SIM_NOW"      # the Block-3 seam writer (what the fence calls on a blind cycle)
    _SIM_NOW=$(( T0 + 65 )); _note_observation "$_SIM_NOW"      # the next successful sample re-pins the observed span
    local fr1; fr1=$(dump_freshness)
    _SIM_NOW=$(( T0 + 120 )); _elapsed_step                       # 120 s since the ORIGINAL start, 55 s since the re-pin
    local a120="$_elapsed_answer" r120="$_elapsed_reason"
    _SIM_NOW=$(( T0 + 164 )); _elapsed_step; local a164="$_elapsed_answer" r164="$_elapsed_reason"
    _SIM_NOW=$(( T0 + 165 )); _elapsed_step; local a165="$_elapsed_answer"
    local v; v=$(_elapsed_provider)
    echo "s_since=$(field "$fr1" observed_since)|s_blind=$(field "$fr1" blind_until)|a120=$a120|r120=$r120|a164=$a164|r164=$r164|a165=$a165|oid=$(_proof_field "$v" observation_id)"
}
r=$(drive_ep "$STANDBY" case_blind_mid | tail -1)
if [[ "$(field "$r" s_since)" == "$(( T0 + 65 ))" && "$(field "$r" s_blind)" == "$(( T0 + 60 ))" ]] \
   && [[ "$(field "$r" a120)" == "blind" && "$(field "$r" r120)" == *"blindness ended 60s ago"* && "$(field "$r" a164)" == "no" && "$(field "$r" r164)" == *"observed silence 99s < elapsed_floor 100s"* && "$(field "$r" a165)" == "yes" ]] \
   && [[ "$(field "$r" oid)" == "elapsed:gen=7:since=$(( T0 + 65 )):floor=100" ]]; then
    ok "(3c) a blind cycle stamped at +60 by the REAL seam writer (_note_blind_cycle) and the span re-pinned at +65: at +120 (120 s after the ORIGINAL start) the provider answers blind ('blindness ended 60s ago') — the clock did NOT run through the blindness; at +164 the floor layer measures 99 s since the re-pin (no), and the floor is met at exactly +165 with the verdict naming since=+65"
else
    bad "(3c) $r"
fi

case_life() {   # vote advance mid-silence: the provider's own read sees it; the REAL fence re-pin resets the clock
    reg; prime_seam 0 none
    VOTE_LIVENESS_MIN_INTERVAL=10; _liveness_first_tip=$(( HEAD - 40 ))
    LV=5003
    _SIM_NOW=$(( T0 + 120 )); _elapsed_step
    local a1="$_elapsed_answer" r1="$_elapsed_reason" fr0; fr0=$(dump_freshness)
    staked_is_actively_voting; local lrc=$?                    # the take path's REAL vote-liveness gate
    local fr1; fr1=$(dump_freshness)
    _SIM_NOW=$(( T0 + 121 )); _elapsed_last_read_ts=0; _elapsed_step
    local a2="$_elapsed_answer" r2="$_elapsed_reason"
    _SIM_NOW=$(( T0 + 220 )); _elapsed_step; local a3="$_elapsed_answer"
    echo "a1=$a1|r1=$r1|since0=$(field "$fr0" observed_since)|lrc=$lrc|since1=$(field "$fr1" observed_since)|a2=$a2|r2=$r2|a3=$a3"
}
r=$(drive_ep "$STANDBY" case_life | tail -1)
if [[ "$(field "$r" a1)" == "no" && "$(field "$r" r1)" == *"LIFE: the holder's staked lastVote is 5003, 3 slots past the episode baseline 5000"* && "$(field "$r" since0)" == "$T0" ]] \
   && [[ "$(field "$r" lrc)" == "0" && "$(field "$r" since1)" == "$(( T0 + 120 ))" && "$(field "$r" a2)" == "no" && "$(field "$r" r2)" == *"observed silence 1s < elapsed_floor 100s"* && "$(field "$r" a3)" == "yes" ]]; then
    ok "(3d) vote advance mid-silence: the provider's own read sees lastVote 5003 vs baseline 5000 → no (LIFE, measured) WITHOUT touching the seam (observed_since still +0); the take path's REAL vote-liveness gate then reads VOTING and re-pins the span at +120 → the provider's clock RESTARTS (1 s at +121), and a full floor later (+220) it proves again"
else
    bad "(3d) $r"
fi

case_tokrot() {   # the token rots on disk AFTER registration
    reg; prime_seam 0 none
    printf 'v0.7|gen=7|watchdog=30|relinquish_bound=60|fence=real|host=h|1\n' > "$PROOF_STATE_DIR/pairing-token"
    : > "$EV"; _SIM_NOW=$(( T0 + 150 )); _elapsed_step
    echo "reg=$_elapsed_registered|a=$_elapsed_answer|r=$_elapsed_reason|reads=$(reads_of "$EV")"
}
r=$(drive_ep "$STANDBY" case_tokrot | tail -1)
if [[ "$(field "$r" reg)" == "1" && "$(field "$r" a)" == "cannot" && "$(field "$r" r)" == *"token no longer classifies ok at the derivation site"* && "$(field "$r" reads)" == "0" ]]; then
    ok "(3e) a token that rots on disk AFTER registration → cannot at the next evaluation (re-classified at the ONE derivation site every time), zero network reads — registration is config, not a standing licence"
else
    bad "(3e) $r"
fi

case_ownblind() {   # both tiers unreachable for the provider's OWN read
    reg; prime_seam 0 none
    T2_DOWN=1; T3_DOWN=1
    local fr0; fr0=$(dump_freshness)
    : > "$EV"; _SIM_NOW=$(( T0 + 150 )); _elapsed_step
    local fr1; fr1=$(dump_freshness)
    echo "a=$_elapsed_answer|r=$_elapsed_reason|same=$([[ "$fr0" == "$fr1" ]] && echo 1 || echo 0)|reads=$(reads_of "$EV")|pets=$(grep -c '^pet' "$EV")"
}
r=$(drive_ep "$STANDBY" case_ownblind | tail -1)
if [[ "$(field "$r" a)" == "blind" && "$(field "$r" r)" == *"yielded no usable sample"* && "$(field "$r" same)" == "1" && "$(field "$r" reads)" == "2" && "$(field "$r" pets)" == "2" ]]; then
    ok "(3f) the provider's own read unusable (T2 and T3 both down: 2 bounded reads, 2 pets) → blind, proves nothing, and the seam is UNTOUCHED (dump_freshness identical before/after): the region writes nothing — no head read after a failed payload"
else
    bad "(3f) $r"
fi

case_cannot() {   # $CASE selects the degenerate observation
    reg; prime_seam 0 none
    case "$CASE" in
        flip)     T2_DOWN=1 ;;                                  # T3 answers → vantage T3 vs the T2 pin
        backward) LV=4990 ;;
        nopin)    _liveness_first_vote="" ;;
        headdown) LOCAL_DOWN=1 ;;
    esac
    : > "$EV"; _SIM_NOW=$(( T0 + 150 )); _elapsed_step
    echo "a=$_elapsed_answer|r=$_elapsed_reason"
}
c_ok=1; c_rows=""
for probe in "flip:vantage 'T3' but the episode is pinned to 'T2'" "backward:went BACKWARDS (4990 < episode baseline 5000)" "nopin:no episode baseline pinned" "headdown:no usable independent head from this spare's own bank"; do
    cs="${probe%%:*}"; want="${probe#*:}"
    r=$(CASE=$cs drive_ep "$STANDBY" case_cannot | tail -1)
    if [[ "$(field "$r" a)" == "cannot" && "$(field "$r" r)" == *"$want"* ]]; then c_rows="$c_rows $cs"; else c_ok=0; bad "(3g) $cs → $r"; fi
done
[[ $c_ok -eq 1 ]] && ok "(3g) degenerate observations each land cannot with a MEASURED reason —$c_rows: a vantage flip (the Block-3 pin: same-vantage only), a lastVote going backwards, no pinned baseline, the independent head unreachable — never proven"

case_age() {
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step; local m1=$_SIM_NOW a1="$_elapsed_answer"
    : > "$EV"
    _SIM_NOW=$(( T0 + 150 )); _elapsed_step; local a2="$_elapsed_answer" rd2; rd2=$(reads_of "$EV")
    local v2; v2=$(_elapsed_provider)
    _SIM_NOW=$(( T0 + 151 )); local v3; v3=$(_elapsed_provider)
    _elapsed_step; local a3="$_elapsed_answer" r3="$_elapsed_reason" i3="$LASTINFO"
    _SIM_NOW=$(( T0 + 153 )); _elapsed_step; local a4="$_elapsed_answer"
    local v4; v4=$(_elapsed_provider)
    echo "a1=$a1|m1=$m1|a2=$a2|rd2=$rd2|oat2=$(_proof_field "$v2" observed_at)|p3=$(_proof_field "$v3" proven)|r3v=$(_proof_field "$v3" elapsed_reason)|a3=$a3|r3=$r3|i3=$i3|a4=$a4|oat4=$(_proof_field "$v4" observed_at)"
}
r=$(drive_ep "$STANDBY" case_age | tail -1)
if [[ "$(field "$r" a1)" == "yes" && "$(field "$r" a2)" == "yes" && "$(field "$r" rd2)" == "0" && "$(field "$r" oat2)" == "$(field "$r" m1)" ]] \
   && [[ "$(field "$r" p3)" == "no" && "$(field "$r" r3v)" == "withdrawn: aged 51s > PROOF_MAX_AGE=50s" ]] \
   && [[ "$(field "$r" a3)" == "cannot" && "$(field "$r" r3)" == "withdrawn: aged 51s > PROOF_MAX_AGE=50s" && "$(field "$r" i3)" == *"WITHDRAWN (aged 51s > PROOF_MAX_AGE=50s)"* ]] \
   && [[ "$(field "$r" a4)" == "yes" && "$(field "$r" oat4)" == "$(( T0 + 153 ))" ]]; then
    ok "(3h) a minted verdict is DORMANT (zero network reads at age 50 = PROOF_MAX_AGE, still served with its original observed_at), at age 51 the reporter already answers withdrawn and the step WITHDRAWS it (never extended), and the next evaluation re-mints with a FRESH observed_at (+153)"
else
    bad "(3h) $r"
fi

case_seam_moved() {   # a minted verdict, then the seam moves (observed life re-pins the span)
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step; local a1="$_elapsed_answer"
    _SIM_NOW=$(( T0 + 110 )); _liveness_obs_since=$_SIM_NOW   # what a VOTING verdict writes (fixture write of the seam)
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    _elapsed_step
    echo "a1=$a1|p=$(_proof_field "$v" proven)|r=$(_proof_field "$v" elapsed_reason)|grc=$grc|a2=$_elapsed_answer|vl=${#_elapsed_verdict}"
}
r=$(drive_ep "$STANDBY" case_seam_moved | tail -1)
if [[ "$(field "$r" a1)" == "yes" && "$(field "$r" p)" == "no" && "$(field "$r" r)" == *"the seam moved under the verdict: silence start $T0 at the mint, now $(( T0 + 110 ))"* && "$(field "$r" grc)" == "1" && "$(field "$r" vl)" == "0" ]]; then
    ok "(3i) the seam moves under a minted verdict (observed life re-pins the span) → the reporter answers withdrawn AT ONCE (the gate refuses, rc 1) and the next step drops the verdict — a proof never outlives the silence it measured"
else
    bad "(3i) $r"
fi

case_close() {
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step; local a1="$_elapsed_answer"
    FIRST_DELINQUENT_TIME=0; _elapsed_step
    local a2="$_elapsed_answer" vl2=${#_elapsed_verdict} i2="$LASTINFO"
    prime_seam 0 none; _SIM_NOW=$(( T0 + 102 )); _elapsed_step; local a3="$_elapsed_answer"
    _elapsed_reset "spare is STAKED — episode closed (a silence verdict must never span our own staked tenure)"
    echo "a1=$a1|a2=$a2|vl2=$vl2|i2=$i2|a3=$a3|a4=$_elapsed_answer|vl4=${#_elapsed_verdict}"
}
r=$(drive_ep "$STANDBY" case_close | tail -1)
if [[ "$(field "$r" a1)" == "yes" && "$(field "$r" a2)" == "cannot" && "$(field "$r" vl2)" == "0" && "$(field "$r" i2)" == *"episode closed — proven verdict"* ]] \
   && [[ "$(field "$r" a3)" == "yes" && "$(field "$r" a4)" == "cannot" && "$(field "$r" vl4)" == "0" ]]; then
    ok "(3j) episode close → the verdict is dropped (logged); the STAKED-branch _elapsed_reset drops it too (its call site is censused at (10c))"
else
    bad "(3j) $r"
fi

# ── (4) the head reference ─────────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) head: commitment=processed from the live log; read AFTER the payload; the default-commitment mutant is wrong both ways ───"

case_order() {
    reg; prime_seam 0 none
    : > "$EV"; _SIM_NOW=$(( T0 + 100 )); _elapsed_step
    echo "a=$_elapsed_answer|ev=$EV"
}
r=$(drive_ep "$STANDBY" case_order | tail -1)
EVF=$(field "$r" ev)
if [[ "$(field "$r" a)" == "yes" && -s "$EVF" ]]; then
    got=$(grep -E '^(read|pet)' "$EVF" | tr '\n' ';')
    if [[ "$got" == "read T2 gva comm=processed;pet;read LOCAL slot comm=processed;pet;" ]]; then
        ok "(4a) live order of a minting evaluation: T2 getVoteAccounts(processed) → pet → LOCAL getSlot(commitment=processed) → pet — the payload first, the independent head AFTER it, every read petted; the head request carries commitment=processed (read back from the live request log)"
    else
        bad "(4a) live order: $got"
    fi
else
    bad "(4a) drive: $r"
fi
mutate "$STANDBY" 's/"method":"getSlot","params":\[{"commitment":"processed"}\]}/"method":"getSlot"}/' "$WORK/headfin.sh"
r=$(LAGS="1 40" drive_ep "$WORK/headfin.sh" case_lag | tail -1)
if [[ "$(field "$r" probes)" == "1:blind 40:yes" ]]; then
    ok "(4b) CONTROL: the head read at the RPC default commitment (finalized, 32 slots behind) is wrong BOTH ways, measured on the mutant — an honest view 1 slot behind the true head reads BLIND (it sits 31 slots 'ahead' of a finalized head), and a view 40 slots behind is ACCEPTED (it measures 8) — commitment=processed is load-bearing"
else
    bad "(4b) default-commitment mutant: $r"
fi

# ── (5) D3 multilayer ──────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (5) multilayer: forged-silence archetype vs each single neuter; the chain; ALL FOUR neutered → forged PROVEN ───"
# THE ARCHETYPE (every layer refuses it on its own): a planted short-floor token (W10+B20+M10 = 40 <
# TAKEOVER_DELAY 60 → does not classify ok), 30 s of observed silence (< even that 40 s floor), a
# blind interval that ended 20 s ago on a seam whose observed span did NOT restart at it (the
# pre-slice-4 seam state — a primed fixture write), and a view lagging 40 slots (> N_HEAD 25).
case_archetype() {
    _proof_startup_check >/dev/null 2>&1
    prime_seam 70 80
    VIEWLAG=40
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step
    local v; v=$(_elapsed_provider)
    echo "reg=$_elapsed_registered|a=$_elapsed_answer|r=$_elapsed_reason|why=${_proof_floor_why:-}|proven=$(_proof_field "$v" proven)|vlen=${#v}"
}
layer_of() {   # the NAMED layer that refused, from the captured record
    local r="$1"
    if [[ "$(field "$r" reg)" == "0" ]]; then echo "token"; return; fi
    case "$(field "$r" r)" in
        *"blindness ended"*|*"no continuous observation"*) echo "blind" ;;
        *"observed silence"*"< elapsed_floor"*) echo "floor" ;;
        *"LAGGED VIEW"*|*"STALE REFERENCE"*) echo "head" ;;
        proven*) echo "NONE(proven)" ;;
        *) echo "other:$(field "$r" r)" ;;
    esac
}
M_TOKEN='s/_derive_proof_floors || {/_derive_proof_floors; true || {/g'
M_BLIND1='s/if \[\[ \$_es_since -le 0 \]\]; then/if [[ 1 -eq 2 ]]; then/'
M_BLIND2='s/if \[\[ \$_es_blind -gt 0 && /if [[ 1 -eq 2 \&\& /'
M_FLOOR='s/if \[\[ \$(( _es_now - _es_since )) -lt \$elapsed_floor \]\]; then/if [[ 1 -eq 2 ]]; then/'
M_HEAD='s/-gt \$N_HEAD \]\]; then/-gt 999999999 ]]; then/g'
r=$(TOK=lowfloor drive_ep "$STANDBY" case_archetype | tail -1)
if [[ "$(layer_of "$r")" == "token" && "$(field "$r" why)" == *"SHORTER than the un-armed timer path"* && "$(field "$r" vlen)" == "0" ]]; then
    ok "(5a) LIVE archetype → refused by [elapsed-token] FIRST (not registered: the derivation site's own reason — floor 40 s SHORTER than the un-armed timer path); the provider does not exist on this host"
else
    bad "(5a) $r"
fi
mutate "$STANDBY" "$M_TOKEN" "$WORK/n-token.sh"
mutate "$STANDBY" "$M_BLIND1" "$WORK/n-blind-a.sh" && mutate "$WORK/n-blind-a.sh" "$M_BLIND2" "$WORK/n-blind.sh"
mutate "$STANDBY" "$M_FLOOR" "$WORK/n-floor.sh"
mutate "$STANDBY" "$M_HEAD" "$WORK/n-head.sh"
s_ok=1; s_rows=""
for n in token blind floor head; do
    r=$(TOK=lowfloor drive_ep "$WORK/n-$n.sh" case_archetype | tail -1)
    got=$(layer_of "$r")
    if [[ "$got" != "NONE(proven)" && "$got" != "$n" && "$got" != other:* ]]; then
        s_rows="$s_rows $n→$got"
    else
        s_ok=0; bad "(5b) [elapsed-$n] neutered ALONE → '$got' (want a DIFFERENT, named layer): $r"
    fi
done
[[ $s_ok -eq 1 ]] && ok "(5b) each layer neutered ALONE, the archetype still refused by a NAMED surviving layer:$s_rows — one neutered layer never reopens the hole"
mutate "$WORK/n-token.sh" "$M_BLIND1" "$WORK/c1a.sh" && mutate "$WORK/c1a.sh" "$M_BLIND2" "$WORK/c-tb.sh"
mutate "$WORK/c-tb.sh" "$M_FLOOR" "$WORK/c-tbf.sh"
mutate "$WORK/c-tbf.sh" "$M_HEAD" "$WORK/c-all.sh"
r1=$(TOK=lowfloor drive_ep "$WORK/n-token.sh" case_archetype | tail -1)
r2=$(TOK=lowfloor drive_ep "$WORK/c-tb.sh" case_archetype | tail -1)
r3=$(TOK=lowfloor drive_ep "$WORK/c-tbf.sh" case_archetype | tail -1)
r4=$(TOK=lowfloor drive_ep "$WORK/c-all.sh" case_archetype | tail -1)
if [[ "$(layer_of "$r1")" == "blind" && "$(layer_of "$r2")" == "floor" && "$(layer_of "$r3")" == "head" ]] \
   && [[ "$(field "$r1" r)" == *"blindness ended 20s ago"* && "$(field "$r2" r)" == *"observed silence 30s < elapsed_floor 40s"* && "$(field "$r3" r)" == *"40 slots behind this spare's own head"* ]]; then
    ok "(5c) the chain, each kill reason captured: token neutered → [elapsed-blind] ('blindness ended 20s ago'); +blind → [elapsed-floor] ('observed silence 30s < elapsed_floor 40s'); +floor → [elapsed-head] ('40 slots behind this spare's own head') — every layer refuses the archetype on its own"
else
    bad "(5c) r1=$(layer_of "$r1") r2=$(layer_of "$r2") r3=$(layer_of "$r3") :: $r3"
fi
if [[ "$(field "$r4" a)" == "yes" && "$(field "$r4" proven)" == "yes" ]]; then
    ok "(5d) ALL FOUR layers neutered → the forged-silence archetype MINTS PROVEN (forged acceptance RESTORED): the enumerated set [elapsed-token]/[elapsed-blind]/[elapsed-floor]/[elapsed-head] is complete over this acceptance — no hidden guard, no gap"
else
    bad "(5d) all-neutered mutant did not restore the forged acceptance: $r4"
fi

# ── (6) coupling ───────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) coupling [pre-registration (b)]: MARGIN_ELAPSED moves floor AND N_HEAD; the provider follows ───"
case_couple() {   # $SIL silence (s), $VL view lag (slots)
    reg; prime_seam 0 none
    VIEWLAG=$VL; _SIM_NOW=$(( T0 + SIL )); _elapsed_step
    echo "floor=$elapsed_floor|nhead=$N_HEAD|a=$_elapsed_answer|r=$_elapsed_reason"
}
mutate "$STANDBY" 's/^    MARGIN_ELAPSED=10$/    MARGIN_ELAPSED=20/' "$WORK/m20.sh"
mutate "$WORK/m20.sh" 's|N_HEAD=$(( MARGIN_ELAPSED \* 5 / 2 ))|N_HEAD=25|' "$WORK/m20-decoupled.sh"
b1=$(SIL=105 VL=1 drive_ep "$STANDBY" case_couple | tail -1);  m1=$(SIL=105 VL=1 drive_ep "$WORK/m20.sh" case_couple | tail -1)
b2=$(SIL=115 VL=40 drive_ep "$STANDBY" case_couple | tail -1); m2=$(SIL=115 VL=40 drive_ep "$WORK/m20.sh" case_couple | tail -1)
d2=$(SIL=115 VL=40 drive_ep "$WORK/m20-decoupled.sh" case_couple | tail -1)
if [[ "$(field "$b1" floor)/$(field "$b1" nhead)" == "100/25" && "$(field "$m1" floor)/$(field "$m1" nhead)" == "110/50" ]] \
   && [[ "$(field "$b1" a)" == "yes" && "$(field "$m1" a)" == "no" && "$(field "$m1" r)" == *"observed silence 105s < elapsed_floor 110s"* ]] \
   && [[ "$(field "$b2" a)" == "blind" && "$(field "$m2" a)" == "yes" ]]; then
    ok "(6a) MARGIN_ELAPSED 10→20 → floor 100→110 AND N_HEAD 25→50, and the provider follows BOTH, measured: 105 s of silence proves on the shipped build and does NOT on the mutant ('105s < 110s'); a 40-slot lagged view is blind on the shipped build and proves on the mutant — tolerance and floor rise TOGETHER (the only sanctioned response to vantages failing the cross-check)"
else
    bad "(6a) base1=$b1 mut1=$m1 base2=$b2 mut2=$m2"
fi
if [[ "$(field "$d2" floor)/$(field "$d2" nhead)" == "110/25" && "$(field "$d2" a)" == "blind" ]]; then
    ok "(6b) CONTROL: the coupling additionally broken (N_HEAD static at 25 while MARGIN is 20) → floor 110 with N_HEAD 25 and the 40-slot view stays blind — (6a)'s together-assertion observed RED on the double mutant"
else
    bad "(6b) decoupled mutant gave: $d2"
fi

# ── (7) inertness ──────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (7) inertness: un-armed zero; armor-forced leaks; holder zero; unpaired zero ───"
case_inert() {
    prime_seam 0 none; _SIM_NOW=$(( T0 + 150 ))
    _elapsed_register; _elapsed_step; _elapsed_step
    local v; v=$(_elapsed_provider)
    _elapsed_reset "x"
    echo "reg=$_elapsed_registered|fns=${_proof_providers:-}|ev=$(grep -c . "$EV")|vlen=${#v}"
}
r=$(ARMED=0 drive_ep "$STANDBY" case_inert | tail -1)
if [[ "$(field "$r" reg)" == "0" && -z "$(field "$r" fns)" && "$(field "$r" ev)" == "0" && "$(field "$r" vlen)" == "0" ]]; then
    ok "(7a) UN-ARMED, valid token, open incident, 150 s of primed silence: register+step×2+provider+reset → ZERO events (no read, no pet, no log, no page), empty registry, the provider prints nothing — v0.6.x unchanged"
else
    bad "(7a) $r"
fi
case_inert_forced() { _watchdog_active() { return 0; }; case_inert; }
r=$(ARMED=0 drive_ep "$STANDBY" case_inert_forced | tail -1)
if [[ "$(field "$r" reg)" == "1" && "$(field "$r" ev)" != "0" && "$(field "$r" vlen)" != "0" ]]; then
    ok "(7b) CONTROL: _watchdog_active forced open on the SAME un-armed drive → it LEAKS ($(field "$r" ev) events, registered, a verdict printed): (7a)'s zeros observe the armor, not an accident"
else
    bad "(7b) armor-forced drive still inert: $r"
fi
r=$(drive_ep "$PRIMARY" case_inert | tail -1)
if [[ "$(field "$r" reg)" == "0" && "$(field "$r" ev)" == "0" && "$(field "$r" vlen)" == "0" ]]; then
    ok "(7c) PRIMARY (holder) daemon ARMED with a valid token → zero events: the role adapter scopes the provider to the spare (a holder must never prove its own silence)"
else
    bad "(7c) $r"
fi
case_adapter() { FIRST_DELINQUENT_TIME=$T0; if _elapsed_incident_active; then echo "active=1"; else echo "active=0"; fi; }
ra=$(drive_ep "$PRIMARY" case_adapter | tail -1); rb=$(drive_ep "$STANDBY" case_adapter | tail -1)
if [[ "$(field "$ra" active)" == "0" && "$(field "$rb" active)" == "1" ]]; then
    ok "(7d) _elapsed_incident_active: primary NEVER active, standby active on FIRST_DELINQUENT_TIME>0"
else
    bad "(7d) primary=$ra standby=$rb"
fi
un_ok=1
for tk in none page-only invalid; do
    r=$(TOK=$tk drive_ep "$STANDBY" case_inert | tail -1)
    [[ "$(field "$r" reg)" == "0" && "$(field "$r" ev)" == "0" && "$(field "$r" vlen)" == "0" ]] || { un_ok=0; bad "(7e) $tk: $r"; }
done
[[ $un_ok -eq 1 ]] && ok "(7e) ARMED spare, UNPAIRED (none / page-only / invalid token) → zero provider events on register+step+provider — silence-based take is disabled by construction, not by a check that could be skipped"

# ── (8) boundedness + pets ─────────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) boundedness: live read/pet census per step; static region census ───"
case_bounded() {
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 50 ));  echo "mark below" >> "$EV"; _elapsed_step
    _SIM_NOW=$(( T0 + 100 )); echo "mark mint" >> "$EV";  _elapsed_step
    _SIM_NOW=$(( T0 + 120 )); echo "mark dormant" >> "$EV"; _elapsed_step
    VIEWLAG=40; _elapsed_reset "probe"
    _SIM_NOW=$(( T0 + 130 )); echo "mark blind" >> "$EV"; _elapsed_step
    _SIM_NOW=$(( T0 + 131 )); echo "mark paced" >> "$EV"; _elapsed_step
    echo "ev=$EV"
}
r=$(drive_ep "$STANDBY" case_bounded | tail -1)
EVF=$(field "$r" ev)
seg() { awk -v m="mark $1" 'found && /^mark /{exit} found{print} $0==m{found=1}' "$EVF"; }
b_ok=1
for probe in "below:0" "mint:2" "dormant:0" "blind:2" "paced:0"; do
    pn="${probe%%:*}"; want="${probe##*:}"
    gr=$(seg "$pn" | grep -c '^read'); gp=$(seg "$pn" | grep -c '^pet')
    [[ "$gr" == "$want" && "$gp" == "$want" ]] || { b_ok=0; bad "(8a) step '$pn': reads=$gr pets=$gp (want $want/$want)"; }
done
alt=$(awk '/^read/{if(p=="read"){print "VIOLATION"; exit}} {p=($0 ~ /^read/)?"read":"other"} END{print "ok"}' "$EVF" | tail -1)
[[ $b_ok -eq 1 && "$alt" == "ok" ]] && ok "(8a) live census: reads per step = below-floor 0 / mint 2 / dormant-proven 0 / blind evaluation 2 / paced 0 (the ${_ELAPSED_READ_PACE_SECS:-2} s pace), every read IMMEDIATELY petted (strict alternation in the live log)"
[[ "$alt" != "ok" ]] && bad "(8a) a read was not followed by its pet"
REGION=$(extract_region "$STANDBY" '\[elapsed-provider\] watchdog-elapsed (attested time) proof provider' '\[elapsed-provider\] end shared block')
if [[ -n "$REGION" ]]; then
    n_curl=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -c 'curl -s -m 5')
    n_curl_any=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -c '$(curl ')
    n_samp=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -c 'get_staked_liveness_sample)')
    n_pet=$(printf '%s\n' "$REGION" | grep -c '^[[:space:]]*_watchdog_pet\b')
    n_sleep=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -c '\bsleep\b')
    n_wall=$(printf '%s\n' "$REGION" | grep -c 'date +%s')
    n_patsub=$(printf '%s\n' "$REGION" | grep -cE '\$\{[A-Za-z_0-9]+//')
    n_seamw=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -cE '(_liveness_obs_since|_last_blind_end|_liveness_first_[a-z]+|LAST_LIVENESS_ACTIVE_TIME)=|_note_blind_cycle|_note_observation')
    if [[ "$n_curl" == "1" && "$n_curl_any" == "1" && "$n_samp" == "1" && "$n_pet" == "1" && "$n_sleep" == "0" && "$n_wall" == "0" && "$n_patsub" == "0" && "$n_seamw" == "0" ]]; then
        ok "(8b) static region census: ONE own read site (the head, curl -m 5) == ONE per-op pet site, ONE sampler call (it pets its own reads), ZERO sleep, ZERO wall-clock (mono only — the ci wall-clock pins do not move), ZERO patsub, ZERO seam writes (no _note_blind_cycle/_note_observation, no triple/pin/anchor assignment) — the region only READS the seam"
    else
        bad "(8b) region census: curl-m5=$n_curl curl-invocations=$n_curl_any sampler=$n_samp pet=$n_pet sleep=$n_sleep wall=$n_wall patsub=$n_patsub seamwrites=$n_seamw"
    fi
fi

# ── (9) constants ──────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) constants: the region assigns none of the derived names; the N_HEAD condition stays at its site ───"
CONST_RE='(^[[:space:]]*((local|declare|export|readonly)[[:space:]]+([-][[:alnum:]]+[[:space:]]+)*)?(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE)=)|(\(\([[:space:]]*(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE)[[:space:]]*=)'
k_ok=1
for d in "$STANDBY" "$PRIMARY"; do
    rg=$(extract_region "$d" '\[elapsed-provider\] watchdog-elapsed (attested time) proof provider' '\[elapsed-provider\] end shared block')
    n=$(printf '%s\n' "$rg" | grep -cE "$CONST_RE")
    [[ "$n" == "0" ]] || { k_ok=0; bad "(9a) $(basename "$d"): the region assigns a derived constant ($n sites)"; }
    df=$(sed -n '/^_derive_proof_floors() {/,/^}/p' "$d")
    printf '%s' "$df" | grep -q 'N_HEAD may$' && printf '%s' "$df" | grep -q 'NOT be loosened alone' || { k_ok=0; bad "(9a) $(basename "$d"): the N_HEAD condition comment left the derivation site"; }
done
[[ $k_ok -eq 1 ]] && ok "(9a) the [elapsed-provider] region assigns NONE of elapsed_floor/MARGIN_ELAPSED/N_HEAD/PROOF_MAX_AGE (the test_proof_gate (11) broadened spellings) in either daemon, and the pre-registered N_HEAD condition comment still sits inside _derive_proof_floors in both — the provider READS the one site"

# ── (10) twins + call sites ────────────────────────────────────────────────────────────────────
echo ""; echo "─── (10) twins byte-identical; call-site census ───"
if extract_twin '\[elapsed-provider\] watchdog-elapsed (attested time) proof provider' '\[elapsed-provider\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(10a) [elapsed-provider] region BYTE-IDENTICAL in both daemons ($(printf '%s' "$TWIN_P" | wc -c | tr -d ' ') bytes)"
else
    bad "(10a) [elapsed-provider] twin regions differ (primary=${#TWIN_P}B standby=${#TWIN_S}B)"
fi
tw_ok=1
extract_twin '\[proof-gate\] spare-side relinquish-proof gate skeleton' '\[proof-gate\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]] || { tw_ok=0; bad "(10b) [proof-gate] twins differ"; }
extract_twin '\[g2-provider\] verified-demote (G2) proof provider' '\[g2-provider\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]] || { tw_ok=0; bad "(10b) [g2-provider] twins differ"; }
[[ $tw_ok -eq 1 ]] && ok "(10b) [proof-gate] (with the new registration line) and [g2-provider] still BYTE-IDENTICAL in both daemons"
w_s=$(grep -c '^        _elapsed_step   #' "$STANDBY"); w_p=$(grep -c '^    _elapsed_step   #' "$PRIMARY")
w_r=$(grep -c '^    _elapsed_register   #' "$STANDBY"); w_rp=$(grep -c '^    _elapsed_register   #' "$PRIMARY")
# placement: inside the standby UNSTAKED branch, AFTER the Tier-1 gate's `_last_behind_alert=0`, BEFORE local_check_delinquency
place=$(awk '/UNSTAKED \(normal\): 3-tier monitoring/{u=1} u && /^        _last_behind_alert=0$/{t=1} u && t && /^        _elapsed_step   #/{print "ok"; exit} u && /^        local_check_delinquency$/{print "late"; exit}' "$STANDBY")
st_reset=$(awk '/^    elif \[\[ "\$CURRENT_IDENTITY" == "\$STAKED_PUBKEY" \]\]; then/{f=1} f && /^    (elif|else|fi)\b/ && !/STAKED_PUBKEY/{f=0} f' "$STANDBY" | grep -cE '^[[:space:]]*_elapsed_reset "spare is STAKED')
o_pri=$(sed "/\[elapsed-provider\] watchdog-elapsed (attested time) proof provider/,/\[elapsed-provider\] end shared block/d" "$PRIMARY" | grep -cE '^[[:space:]]*_elapsed_(step|register|reset|provider)\b')
o_sby=$(sed "/\[elapsed-provider\] watchdog-elapsed (attested time) proof provider/,/\[elapsed-provider\] end shared block/d" "$STANDBY" | grep -cE '^[[:space:]]*_elapsed_(step|register|reset|provider)\b')
if [[ "$w_s$w_p$w_r$w_rp" == "1111" && "$place" == "ok" && "$st_reset" == "1" && "$o_pri" == "2" && "$o_sby" == "3" ]]; then
    ok "(10c) call sites: ONE _elapsed_step per main loop (standby inside the UNSTAKED branch AFTER the Tier-1 gate and BEFORE local_check_delinquency; primary at the role-inert loop top), ONE _elapsed_register inside _proof_startup_check per daemon, ONE STAKED-branch _elapsed_reset on the standby — outside-region census primary 2 / standby 3; a new site moves this pin in the same diff"
else
    bad "(10c) step=$w_s/$w_p register=$w_r/$w_rp placement=$place staked-reset=$st_reset outside-region primary=$o_pri (pin 2) standby=$o_sby (pin 3)"
fi

# ── (11) D0 — the executed input map on the REAL standby main loop ─────────────────────────────
echo ""; echo "─── (11) D0: the own-bank veto, the timing race, the intermittent holder, the partitioned and lagging spare (MEASURED residuals) ───"
# The world (the D0 driver, ported): every decision function is REAL (tier1, local_check_delinquency,
# window_*, attempt_takeover, confirm/tier2/tier3, staked_is_actively_voting, the sampler,
# take_staked_identity, _fresh_proof_recheck, and — armed — _elapsed_step). Only I/O is stubbed.
#   head slot(t) = HEAD0 + 2.5/s; the holder's last vote before the episode at t=0, resuming at
#   RESUME (-1 never) until STOP (-1 forever); TIER2/TIER3 = ONE splicer: the head proxied LIVE, the
#   holder served FROZEN at slot(0) and delinquent. The spare's OWN node (LOCAL_RPC), from verified
#   facts only: getVoteAccounts/getSlot at the commitment the request carries (local_check_delinquency
#   sends none → the RPC default, finalized ≈ processed − 32 slots; a vote is in the finalized bank 13 s
#   after it lands), agave's 128-slot delinquency rule, and getHealth exactly as agave v4.2.1
#   rpc/src/rpc_health.rs computes it (the node's own replayed optimistic slot vs the latest optimistic
#   slot its OWN blockstore observed via replay + gossip, distance 128). The TIER2/TIER3 row is the
#   premise under test, not an assumption about who is lying: a splicer, OR tiers partitioned together
#   with the spare (they then HONESTLY serve a live tip and a silent holder) — either way the question
#   is what the spare's OWN surface (bank + health) does against a frozen view. CUT=<t> CUTMODE:
#     full            from t the spare hears nothing (its bank frozen, its blockstore learns nothing)
#     minority        from t the spare replays a MINORITY fork: processed keeps advancing but carries
#                     none of the holder's votes, and nothing new is optimistically confirmed or
#                     finalized there (no supermajority); gossip cut
#     minority-gossip the same, but the supermajority's gossip votes still reach the spare, so its
#                     blockstore's latest optimistic slot keeps advancing (getHealth's cluster side)
#   LAG=<s>: the spare replays <s> seconds behind the chain (its blockstore still observes the cluster's
#   optimistic slot on time). LCOMM=processed: a WHAT-IF MUTANT (never shipped) of the own-bank read's
#   commitment — the control that shows which way the shipped default cuts.
world() {   # knobs: MDS RESUME STOP CUT CUTMODE LAG LCOMM ARMED GATE HORIZON GV; prints one k=v| summary line
    (
        set +e
        _SIM_NOW=$T0
        W=$(mktemp -d "$WORK/w.XXXXXX"); EV="$W/ev"; : > "$EV"; IDF="$W/id"; echo U1 > "$IDF"
        PROOF_STATE_DIR="$W/ps"; mkdir -p "$PROOF_STATE_DIR"
        load_seam "$STANDBY"
        region=$(extract_region "$STANDBY" '^while \$_running; do' '^done$') || { echo "region=EMPTY"; exit 1; }
        eval "run_loop() {
$region
}"
        STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; VOTE_PUBKEY=V1; PRIMARY_UNSTAKED_PUBKEY=""
        LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
        TAKEOVER_DELAY=60; TAKEOVER_COOLDOWN=120; EXTERNAL_CONFIRM_THROTTLE=12
        MAX_DELINQUENT_SLOTS=${MDS:-0}; DRY_RUN=false; GOSSIP_VERIFY=${GV:-false}; WITNESS_FASTPATH=false
        VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_EPSILON=0; VOTE_LIVENESS_MIN_INTERVAL=10; VOTE_LIVENESS_MIN_SPAN=40
        # LOCAL_HEALTH_MAX_BEHIND: deliberately NOT set — the shipped default from the seam (printed as lhmb)
        SOLANA_PATH="$W"; LEDGER_PATH=/x; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15
        STAKED_KEYPAIR="$W/staked.json"; printf '[1]' > "$STAKED_KEYPAIR"
        CHECK_INTERVAL=5; TURBO_INTERVAL=1; _current_interval=5; HEARTBEAT_INTERVAL=999999; _last_heartbeat=$T0
        ALERT_THROTTLE=600; TAKEOVER_STARVATION_ALERT_SECS=0
        harness_clock_shims
        log() { :; }; log_info() { :; }; log_error() { :; }
        log_warn() { case "$*" in *"watchdog-elapsed PROVEN"*) echo "elapsed-mint t=$(( _SIM_NOW - T0 ))" >> "$EV" ;; esac; }   # the mint INSTANT, from the provider's own PROVEN line
        alert() { :; }; alert_warn() { :; }; alert_info() { :; }; send_telegram() { :; }; send_webhook() { :; }
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _fence_rot_check() { :; }
        flush_pending_alerts() { :; }; save_state() { :; }
        get_local_identity() { cat "$IDF"; }
        display_status() {
            local ek=none
            case "${_elapsed_reason:-}" in "STALE REFERENCE"*) ek=stale ;; "LAGGED VIEW"*) ek=lag ;; esac
            echo "cycle t=$(( _SIM_NOW - T0 )) status=$1 fdt=${FIRST_DELINQUENT_TIME} ea=${_elapsed_answer:-na} ek=$ek" >> "$EV"
        }
        if [[ "${LCOMM:-default}" == "processed" ]]; then
            eval "$(declare -f local_check_delinquency | sed 's/"method":"getVoteAccounts"}/"method":"getVoteAccounts","params":[{"commitment":"processed"}]}/')"
            declare -f local_check_delinquency | grep -qF '"getVoteAccounts","params":[{"commitment":"processed"}]' || { echo "world: the LCOMM what-if mutant did not apply"; exit 1; }
        fi
        eval "$(declare -f attempt_takeover | sed '1s/attempt_takeover/_real_attempt_takeover/')"
        attempt_takeover() { echo "attempt t=$(( _SIM_NOW - T0 ))" >> "$EV"; _real_attempt_takeover; }
        timeout() {
            [[ "$1" == "-k" ]] && shift 2
            shift
            case "$*" in
                *" set-identity "*) echo "MUTATION t=$(( _SIM_NOW - T0 ))" >> "$EV"; echo S1 > "$IDF"; return 0 ;;
                *"authorized-voter"*) return 0 ;;
            esac
            "$@"
        }
        _slot() { echo $(( HEAD0 + $1 * 5 / 2 )); }
        _hv() {   # the holder's latest landed vote time <= $1
            local at="$1" r="${RESUME:--1}" s="${STOP:--1}" lv=0
            if [[ $r -ge 0 && $at -ge $r ]]; then lv=$at; [[ $s -ge 0 && $lv -gt $s ]] && lv=$s; fi
            echo "$lv"
        }
        curl() {
            local url="" d="" src m t te hp comm vh vv mo oo
            while [[ $# -gt 0 ]]; do
                case "$1" in -d) d="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac
            done
            t=$(( _SIM_NOW - T0 ))
            case "$url" in "$LOCAL_RPC") src=LOCAL ;; "$TIER2_RPC") src=T2 ;; "$TIER3_RPC") src=T3 ;; *) src=OTHER ;; esac
            case "$d" in *getHealth*) m=getHealth ;; *getVoteAccounts*) m=getVoteAccounts ;; *getSlot*) m=getSlot ;; *) m=other ;; esac
            comm=default; case "$d" in *'"commitment":"processed"'*) comm=processed ;; esac
            echo "read $src $m t=$t" >> "$EV"
            if [[ "$src" == "LOCAL" ]]; then
                # the spare's own node at t: hp/hf = processed/finalized head, vp/vf = the holder's lastVote
                # in those banks, mo = own replayed optimistic slot, oo = the latest optimistic slot its
                # blockstore observed (getHealth's two sides)
                local mode="${CUTMODE:-none}" c="${CUT:--1}" lag="${LAG:-0}" hf vp vf
                [[ $c -lt 0 || $t -le $c ]] && mode=none
                case "$mode" in
                    none) te=$(( t - lag )); hp=$(_slot "$te"); hf=$(( hp - 32 ))
                          vp=$(_slot "$(_hv "$te")"); vf=$(_slot "$(_hv $(( te - 13 )))")
                          mo=$(( hp - 2 )); oo=$(( $(_slot "$t") - 2 )) ;;
                    full) te=$(( c - lag )); hp=$(_slot "$te"); hf=$(( hp - 32 ))
                          vp=$(_slot "$(_hv "$te")"); vf=$(_slot "$(_hv $(( te - 13 )))")
                          mo=$(( hp - 2 )); oo=$(( $(_slot "$c") - 2 )) ;;
                    minority|minority-gossip)
                          hp=$(_slot "$t"); hf=$(( $(_slot "$c") - 32 ))
                          vp=$(_slot "$(_hv "$c")"); vf=$(_slot "$(_hv $(( c - 13 )))")
                          mo=$(( $(_slot "$c") - 2 )); oo=$mo
                          [[ "$mode" == "minority-gossip" ]] && oo=$(( $(_slot "$t") - 2 )) ;;
                    *) return 7 ;;
                esac
                case "$m" in
                    getHealth)
                        if [[ $mo -ge $(( oo - 128 )) ]]; then printf '{"jsonrpc":"2.0","result":"ok","id":1}'; else printf '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by %s slots","data":{"numSlotsBehind":%s}},"id":1}' "$(( oo - mo ))" "$(( oo - mo ))"; fi ;;
                    getSlot)
                        if [[ "$comm" == "processed" ]]; then printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$hp"; else printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$hf"; fi ;;
                    getVoteAccounts)
                        if [[ "$comm" == "processed" ]]; then vh=$hp; vv=$vp; else vh=$hf; vv=$vf; fi
                        if [[ $vv -lt $(( vh - 128 )) ]]; then
                            printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]},"id":1}' "$(( vh - 1 ))" "$vv"
                        else
                            printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s},{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]},"id":1}' "$(( vh - 1 ))" "$vv"
                        fi ;;
                    *) return 7 ;;
                esac
                return 0
            fi
            case "$m" in
                getVoteAccounts) printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]},"id":1}' "$(( $(_slot "$t") - 1 ))" "$(_slot 0)" ;;
                getSlot) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(_slot "$t")" ;;
                *) return 7 ;;
            esac
            return 0
        }
        if [[ "${ARMED:-0}" == "1" ]]; then
            NOTIFY_SOCKET="$W/n.sock"; WATCHDOG_USEC=30000000
            _watchdog_pet() { :; }
            printf '%s\n' "$(mk_token 7 30 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token"
            _proof_startup_check
        else
            unset NOTIFY_SOCKET WATCHDOG_USEC
        fi
        if [[ "${GATE:-0}" == "1" ]]; then
            # MEASUREMENT EMULATION of Block 6.4's DOCUMENTED placement (BLOCK6-PLAN §5 6.4: the gate
            # in front of set-identity inside attempt_takeover, before _fresh_proof_recheck — the first
            # statement of take_staked_identity). NOT shipped wiring: it exists in this suite only to
            # measure when a proof-gated take would mutate.
            eval "$(declare -f take_staked_identity | sed '1s/take_staked_identity/_real_take_staked_identity/')"
            take_staked_identity() {
                require_relinquish_proof || { echo "gate-refused t=$(( _SIM_NOW - T0 ))" >> "$EV"; return 1; }
                echo "gate-accepted t=$(( _SIM_NOW - T0 )) prov=$(_proof_field "$_proof_last_verdict" provider)" >> "$EV"
                _real_take_staked_identity "$@"
            }
        fi
        _watchdog_sleep() {
            _SIM_NOW=$(( _SIM_NOW + $1 ))
            if [[ $(( _SIM_NOW - T0 )) -ge ${HORIZON:-200} ]] || grep -q '^MUTATION' "$EV"; then _running=false; fi
            return 0
        }
        sleep() { _SIM_NOW=$(( _SIM_NOW + ${1%%.*} )); return 0; }
        _running=true
        run_loop
        E=$(grep -m1 ' status=DELINQ ' "$EV" | sed 's/.* fdt=\([0-9]*\).*/\1/'); [[ -n "$E" ]] && E=$(( E - T0 ))
        mut=$(grep -m1 '^MUTATION' "$EV" | sed 's/.*t=//')
        veto=""; [[ ${RESUME:--1} -ge 0 && -n "$E" ]] && veto=$(awk -v r="${RESUME}" -v e="$E" '/^cycle / { split($2,a,"="); t=a[2]+0; if (t>=r && t>e && $3=="status=OK") { print t; exit } }' "$EV")
        emint=$(grep -m1 '^elapsed-mint ' "$EV" | sed 's/.*t=//')
        estale=$(grep -c ' ek=stale' "$EV")
        estale_from=$(grep -m1 ' ek=stale' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/')
        cyc_from=0; [[ -n "$estale_from" ]] && cyc_from=$(awk -v f="$estale_from" '/^cycle / { split($2,a,"="); if (a[2]+0 >= f) c++ } END { print c+0 }' "$EV")
        t1b=$(grep -m1 ' status=T1:BEHIND ' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/')
        tco=$(awk '/^read LOCAL getVoteAccounts/{n=NR} /^MUTATION/{m=NR} END{print n+0, m+0}' "$EV")
        between=$(awk -v range="$tco" 'BEGIN{split(range,x," ")} NR>x[1] && NR<x[2] && /^read LOCAL/{c++} END{print c+0}' "$EV")
        order=$(awk -v range="$tco" 'BEGIN{split(range,x," ")} NR>=x[1] && NR<=x[2] && (/^read/ || /^attempt/ || /^gate-/ || /^MUTATION/) {sub(/ t=[0-9]+/,""); printf "%s;", $0}' "$EV")
        echo "E=${E:-none}|veto=${veto:-none}|mutation=${mut:-none}|emint=${emint:-none}|estale_cycles=$estale|estale_from=${estale_from:-none}|cycles_from_stale=$cyc_from|t1_behind_from=${t1b:-never}|lhmb=${LOCAL_HEALTH_MAX_BEHIND:-unset}|local_reads_between=$between|order=$order|gate=$(grep -m1 '^gate-accepted' "$EV" | sed 's/^gate-accepted //')"
        rm -rf "$W"
    )
}
# (11a)/(11b) the per-cycle own-bank entry gate and the timing race on today's timer path
ra=$(MDS=0 RESUME=112 HORIZON=140 world | tail -1)
rb=$(MDS=0 RESUME=113 HORIZON=140 world | tail -1)
rbg=$(GV=true MDS=0 RESUME=113 HORIZON=140 world | tail -1)
if [[ "$(field "$rb" mutation)" == "125" && "$(field "$rb" local_reads_between)" == "0" ]] \
   && [[ "$(field "$rb" order)" == "read LOCAL getVoteAccounts;attempt;read T2 getVoteAccounts;read T2 getVoteAccounts;read T2 getVoteAccounts;MUTATION;" ]] \
   && [[ "$(field "$rbg" mutation)" == "125" && "$(field "$rbg" local_reads_between)" == "0" && "$(field "$rbg" order)" == *"read T2 other;"* ]]; then
    ok "(11a) MEASURED — the own-bank check is a PER-CYCLE entry gate but NOT a mutation-edge condition: the take cycle reads LOCAL getVoteAccounts, then attempt_takeover reads only TIER2 (external confirm, vote-FROZEN sample, fresh-proof recheck) and mutates — ZERO LOCAL reads between the own-bank verdict and set-identity; with the shipped GOSSIP_VERIFY=true the advisory gossip reads join the take cycle and they too ride the tiers (still ZERO LOCAL reads before the mutation)"
else
    bad "(11a) gv-off=$rb gv-on=$rbg"
fi
if [[ "$(field "$ra" E)" == "65" && "$(field "$ra" veto)" == "125" && "$(field "$ra" mutation)" == "none" && "$(field "$rb" veto)" == "none" && "$(field "$rb" mutation)" == "125" ]]; then
    ok "(11b) MEASURED timing race (splicer on TIER2/TIER3, the holder RESUMES voting and its votes reach the spare's bank; timer-path mutation scheduled at E+60 = t125): resumed at t112 → the own bank reads it current at t125 (13 s later: the finalized commitment's ~32-slot lag) and VETOES; resumed at t113 → the take MUTATES at t125 while the holder has been voting for 12 s. The veto wins only for a resumption >= ~13 s before the mutation (docs/SAFETY.md, the shared-input property)"
else
    bad "(11b) resume112=$ra resume113=$rb"
fi
# (11c) the same race against the REAL watchdog-elapsed provider under the 6.4-placement emulation
rc1=$(ARMED=1 GATE=1 MDS=0 RESUME=158 HORIZON=185 world | tail -1)
rc2=$(ARMED=1 GATE=1 MDS=0 RESUME=159 HORIZON=185 world | tail -1)
if [[ "$(field "$rc1" emint)" == "171" && "$(field "$rc1" veto)" == "171" && "$(field "$rc1" mutation)" == "none" ]] \
   && [[ "$(field "$rc2" emint)" == "171" && "$(field "$rc2" mutation)" == "171" && "$(field "$rc2" gate)" == "t=171 prov=watchdog-elapsed" ]]; then
    ok "(11c) MEASURED against the REAL provider (armed, paired, G2 unconfigured, the 6.4-placement EMULATION): the provider mints at t171 (the first sample at t71 + the 100 s floor — the splicer's frozen view passes every layer, the head proxied live); holder resumed at t158 → the own bank vetoes at t171, no take; resumed at t159 → the gate ACCEPTS watchdog-elapsed and the take mutates at t171, 12 s into the holder's renewed voting — the same 13 s boundary as the timer path in (11b): the proof CAN mature before the own bank sees the resumption, a DESIGN FINDING (reported, not fixed in 6.3)"
else
    bad "(11c) resume158=$rc1 resume159=$rc2"
fi
# (11d) the intermittent holder at the wizard's MAX_DELINQUENT_SLOTS=15
rd=$(MDS=15 RESUME=40 STOP=40 HORIZON=100 world | tail -1)
if [[ "$(field "$rd" E)" == "20" && "$(field "$rd" veto)" == "53" && "$(field "$rd" mutation)" == "80" ]]; then
    ok "(11d) MEASURED — the own-bank 'current' verdict never re-anchors the countdown: at MAX_DELINQUENT_SLOTS=15 ONE holder vote at t40 reaches the spare's bank (current from t53, 7 cycles — the window un-triggers but needs 9 to close the episode), and the take mutates at t80 on the ORIGINAL anchor, 40 s after a vote the spare's own bank saw (with honest TIER2/TIER3 the vote-FROZEN gate would re-anchor at it)"
else
    bad "(11d) $rd"
fi
# (11e) the fully cut-off spare after the episode opened (agave getHealth reads ok: its blockstore learns nothing)
re1=$(MDS=0 RESUME=90 CUT=80 CUTMODE=full HORIZON=140 world | tail -1)
re2=$(ARMED=1 GATE=1 MDS=0 RESUME=90 CUT=80 CUTMODE=full HORIZON=200 world | tail -1)
if [[ "$(field "$re1" mutation)" == "125" && "$(field "$re2" mutation)" == "none" && "$(field "$re2" emint)" == "none" && "$(field "$re2" estale_from)" == "171" && "$(field "$re2" estale_cycles)" -gt 0 && "$(field "$re2" estale_cycles)" == "$(field "$re2" cycles_from_stale)" ]]; then
    ok "(11e) MEASURED — a spare FULLY cut off at t80 (after its own bank already showed the holder delinquent) keeps that frozen verdict, and agave's getHealth stays ok (its blockstore observes nothing new): the timer path takes at t125 with the holder voting since t90 — NO spare-side gate holds (a finding); on the armed elapsed path the REAL provider refuses with STALE REFERENCE from t171 (the first evaluation its 100 s floor allows) on every one of the $(field "$re2" estale_cycles) remaining cycles to the horizon — its two-sided head compare sees the frozen own head fall > N_HEAD behind the live view — and no proof-gated take happens"
else
    bad "(11e) unarmed=$re1 armed=$re2"
fi
# (11f) P2: the spare's bank ADVANCES without the holder's votes (a minority fork from t30; the holder
# alive and voting on the majority throughout) — the commitment of the own-bank read decides it
rf1=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority HORIZON=200 world | tail -1)
rf2=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority LCOMM=processed HORIZON=160 world | tail -1)
if [[ "$(field "$rf1" E)" == "none" && "$(field "$rf1" mutation)" == "none" && "$(field "$rf1" t1_behind_from)" == "never" ]] \
   && [[ "$(field "$rf2" E)" == "85" && "$(field "$rf2" mutation)" == "145" && "$(field "$rf2" t1_behind_from)" == "never" ]]; then
    ok "(11f) MEASURED — a spare on a MINORITY fork from t30 (processed advancing without the holder's votes, gossip cut): getHealth stays ok (no new optimistic slot anywhere it can see), and the SHIPPED own-bank read at finalized holds (a minority fork does not finalize: the holder stays current, no episode, no take); CONTROL: the same read at processed (a what-if mutant) opens the episode at t85 and takes at t145 — the finalized default is load-bearing here, the flip side of its 13 s veto lag in (11b)"
else
    bad "(11f) shipped=$rf1 processed-whatif=$rf2"
fi
# (11g) P2 with the supermajority's gossip still arriving: the blockstore keeps learning optimistic slots
rg1=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority-gossip HORIZON=160 world | tail -1)
rg2=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority-gossip LCOMM=processed HORIZON=160 world | tail -1)
if [[ "$(field "$rg1" t1_behind_from)" == "85" && "$(field "$rg1" mutation)" == "none" && "$(field "$rg2" t1_behind_from)" == "85" && "$(field "$rg2" E)" == "none" && "$(field "$rg2" mutation)" == "none" ]]; then
    ok "(11g) MEASURED — the same minority fork but with the supermajority's gossip votes still reaching the spare: getHealth reports it behind from t85 (its blockstore's optimistic slot runs 128+ slots ahead of its own replayed one) and Tier-1 holds from then on — under the shipped read AND under the processed what-if that (11f) shows would otherwise take (there no episode ever opens: the delinquent verdict it would read from t82 on is never reached)"
else
    bad "(11g) shipped=$rg1 processed-whatif=$rg2"
fi
# (11h) P3: a LAGGING spare — getHealth compares against the spare's own blockstore (LOCAL only; the
# Tier-1 getSlot is logged, never compared with TIER2/TIER3): <= 128 slots behind reads ok
rh1=$(MDS=0 RESUME=95 LAG=40 HORIZON=200 world | tail -1)
rh2=$(MDS=0 RESUME=115 LAG=40 HORIZON=200 world | tail -1)
rh3=$(MDS=0 LAG=60 HORIZON=100 world | tail -1)
rh4=$(ARMED=1 GATE=1 MDS=0 LAG=40 HORIZON=230 world | tail -1)
if [[ "$(field "$rh1" E)" == "105" && "$(field "$rh1" mutation)" == "none" && "$(field "$rh2" mutation)" == "165" && "$(field "$rh2" t1_behind_from)" == "never" ]] \
   && [[ "$(field "$rh3" t1_behind_from)" == "0" && "$(field "$rh3" E)" == "none" && "$(field "$rh3" mutation)" == "none" && "$(field "$rh3" lhmb)" =~ ^[0-9]+$ && "$(field "$rh3" lhmb)" -lt 128 ]] \
   && [[ "$(field "$rh4" mutation)" == "none" && "$(field "$rh4" emint)" == "none" && "$(field "$rh4" estale_from)" == "211" && "$(field "$rh4" estale_cycles)" -gt 0 && "$(field "$rh4" estale_cycles)" == "$(field "$rh4" cycles_from_stale)" ]]; then
    ok "(11h) MEASURED — a spare replaying 40 s (100 slots) behind passes Tier-1 (agave reads ok up to 128) and the own-bank veto's reaction grows by the lag: a holder resumed at t95 is vetoed, one resumed at t115 is taken over at t165 after 50 s of voting; 60 s (150 slots) behind → Tier-1 BEHIND from t0, no episode (the shipped LOCAL_HEALTH_MAX_BEHIND=$(field "$rh3" lhmb) is below agave's default distance 128, so its within-tolerance branch can never admit an agave 'behind' report — every such report is > 128); ARMED at 40 s behind with a genuinely silent holder, watchdog-elapsed refuses STALE REFERENCE from its first evaluation (t211) on every cycle to the horizon — no take (availability: a spare more than N_HEAD behind cannot prove by time)"
else
    bad "(11h) lag40-resume95=$rh1 lag40-resume115=$rh2 lag60=$rh3 armed-lag40=$rh4"
fi

rm -rf "$WORK"
results_banner
