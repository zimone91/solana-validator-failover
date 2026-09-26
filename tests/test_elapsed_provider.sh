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
#        withdrawn at the reporter, episode close / the STAKED-branch reset → dropped; 6.3 fix round:
#        (3k) M1 the token swapped under a DORMANT verdict (rm / page-only / garbage / larger-bound
#        re-pair / same-bound re-pair / a raised bound under the same gen) → the gate refuses AT ONCE,
#        zero network; (3l) N4 an IMPROVING token mid-episode → no retroactive mint (the silence
#        restarts at its adoption); (3m) M7 a vantage re-pin under a standing verdict → withdrawn (the
#        served triple never disagrees with dump_freshness); (3n) M4 non-canonical integers
#        ("0009999", 2^64+N) at the provider → blind / cannot, never arithmetic, plus the ONE
#        validator's boundary table
#   (4)  the head reference: commitment=processed read from the live request log; the head is read
#        AFTER the payload (live order); the default-commitment mutant is wrong BOTH ways (a live
#        view permanently blind AND a 40-slot lagged view accepted)
#   (5)  D3 MULTILAYER (mandatory): (5a)–(5d) the SEAM-REGRESSION defense line — the old forged-silence
#        archetype (a seam state the current writers cannot produce) vs each single neuter, the
#        progressive chain, and ALL FOUR step layers neutered → forged PROVEN; (5e)–(5h) the REACHABLE
#        post-blindness state (the real _note_blind_cycle, then an evaluation before re-observation):
#        [elapsed-blind] and [elapsed-seam] each neutered alone → the other refuses; both → [elapsed-
#        floor]'s serve-time half withdraws; all three → the forged acceptance at the GATE reappears
#   (6)  COUPLING [pre-registration (b)]: MARGIN_ELAPSED 10→20 moves the floor AND N_HEAD and the
#        provider's behavior follows (measured both ways); a decoupled static-N_HEAD control
#   (7)  inertness census: un-armed / holder / unpaired → zero events; the armor-forced control leaks
#   (8)  boundedness + pets: live event order + the static region census (N-is-all, both censuses)
#   (9)  constants: the region assigns none of the four derived names; the N_HEAD condition comment
#        still sits at the derivation site in both daemons
#   (10) twins + call sites: [elapsed-provider] byte-identical; [proof-gate] and [g2-provider] still
#        identical; call-site census per daemon
#   (11) D0 — the executed input map, on the REAL standby main loop (a FILE-BACKED clock since the 6.3
#        fix round, so reads take time; the slot rate an explicit knob): the per-cycle own-bank entry
#        gate and the take cycle's read order, with the shipped gossip advisory too; the timing race
#        incl. the REAL provider under the 6.4 emulation, and re-measured at the MEASURED mainnet rate
#        (3.7 slots/s — (11b-rate)); the intermittent holder; the partitioned spare — fully cut off,
#        on a minority fork (the vote bank frozen within ~8 votes) with and without the
#        supermajority's gossip — and the lagging spare, armed and not; then the DOCUMENTED
#        RESIDUALS (11i)–(11n): partitioned after the pin together with co-frozen tiers, the latency
#        term Σ, an honest lagging tier, the armed intermittent holder, LOCAL_HEALTH_MAX_BEHIND > 128,
#        forged G2 on shared vantages — each a MEASURED fact that docs/SAFETY.md states, so the text
#        cannot drift from the mechanism silently; each residual says which remedy flips it
#   (12) the 6.3 fix round's mechanism reds, re-run green: M2 (post-read silence starts — the F2
#        world), M3 (observed_at = the answering read's own stamp; the tail), M4 (non-canonical input
#        through the REAL loop), M5 (an aborted loop exits non-zero; SIGTERM still 0), M6 (the MEASURED
#        inter-pet gap), M8 (the paired-but-unregistered status line), N2 (only a STAMPED blindness
#        restarts the silence clock — (12h))
#
# MUTATION COVERAGE (HARNESS.md discipline), all via mutate() (loud on no-op): the step layers of (5)
# alone and chained, [elapsed-seam] (5f), the head compare boundary (3b-ctl), the head commitment
# (4b), the MARGIN_ELAPSED coupling + its decoupled control (6), the armor shim-force (7b), the
# validator reverted to the pre-fix shape (12e), the Tier-1/MDS pets removed (12f). One what-if
# mutant lives in the (11) world instead, with its own loud apply-check: the own-bank read's
# commitment (11f)/(11g) — the controls showing which way the shipped finalized default cuts.
# NAMED SURVIVORS (6.3 panel CC-7 — redundant defenses a single-guard mutant does NOT turn red, each
# because another enumerated guard refuses the same input first; listed so "every guard is killed"
# stays a measured claim): the episode check in _elapsed_verdict_why (the step drops the verdict at
# episode close before any reporter call can see it — (3j)); the step's and the reporter's
# armed/role/registered gates (the gate registry is empty on those hosts — (7)); the elapsed_floor-
# and PROOF_MAX_AGE-unusable cases (_derive_proof_floors never yields an unusable floor that
# classifies ok; PROOF_MAX_AGE is assigned after the env source); the head curl-rc check (a failed
# read's empty body fails the canonical-integer check next); the numeric-sample and empty-tier checks
# (the ONE sampler already applies the same validator and always labels its tier). Refusal texts are
# asserted by content; the per-daemon adapters are exercised behaviorally (7c/7d).
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
                if [[ "$comm" == "processed" ]]; then printf '{"jsonrpc":"2.0","result":%s,"id":1}' "${HEADSTR:-$HEAD}"; else printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(( HEAD - 32 ))"; fi
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
if [[ "$(field "$r" a1)" == "yes" && "$(field "$r" p)" == "no" && "$(field "$r" r)" == *"the seam moved under the verdict: freshness triple (vantage/observed_since/blind_until) T2/${T0}/0 at the mint, now T2/$(( T0 + 110 ))/0"* && "$(field "$r" grc)" == "1" && "$(field "$r" vl)" == "0" ]]; then
    ok "(3i) the seam moves under a minted verdict (observed life re-pins the span) → the reporter answers withdrawn AT ONCE naming the freshness triple at the mint and now (the gate refuses, rc 1) and the next step drops the verdict — a proof never outlives the silence it measured"
else
    bad "(3i) $r"
fi

# (3k) M1 (6.3 fix round — F4 = INT-1): the token swapped under a DORMANT verdict. Pre-fix red (de21927):
# all five served proven=yes, gate rc 0, zero reads, until the age withdrawal at +51.
case_tokswap() {   # $SWAP: rm | page-only | garbage | bigger | regen | samegen
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step; local a1="$_elapsed_answer"
    case "$SWAP" in
        rm)        rm -f "$PROOF_STATE_DIR/pairing-token" ;;
        page-only) printf '%s\n' "$(mk_token 7 30 60 page-only holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;
        garbage)   printf 'not a token\n' > "$PROOF_STATE_DIR/pairing-token" ;;
        bigger)    printf '%s\n' "$(mk_token 8 30 120 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;   # a larger-bound re-pair (floor 160)
        regen)     printf '%s\n' "$(mk_token 8 30 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;    # a same-bound re-pair: a NEW gen, floor still 100
        samegen)   printf '%s\n' "$(mk_token 7 30 120 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;   # a hand-edited token: gen kept, bound raised (floor 160)
    esac
    : > "$EV"
    _SIM_NOW=$(( T0 + 110 ))
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    _elapsed_step
    echo "a1=$a1|p=$(_proof_field "$v" proven)|r=$(_proof_field "$v" elapsed_reason)|grc=$grc|a2=$_elapsed_answer|r2=$_elapsed_reason|vl=${#_elapsed_verdict}|reads=$(reads_of "$EV")"
}
k_ok=1; k_rows=""
for probe in "rm:token no longer classifies ok at the derivation site" "page-only:token no longer classifies ok at the derivation site" "garbage:token no longer classifies ok at the derivation site" \
             "bigger:the stored token changed under the verdict: gen=8 in force now, the verdict rests on gen=7" "regen:the stored token changed under the verdict: gen=8 in force now, the verdict rests on gen=7" \
             "samegen:the re-derived elapsed_floor 160s exceeds the 100s of silence the verdict was minted on"; do
    sw="${probe%%:*}"; want="${probe#*:}"
    r=$(SWAP=$sw drive_ep "$STANDBY" case_tokswap | tail -1)
    if [[ "$(field "$r" a1)" == "yes" && "$(field "$r" p)" == "no" && "$(field "$r" r)" == "withdrawn: ${want}"* && "$(field "$r" grc)" == "1" ]] \
       && [[ "$(field "$r" a2)" == "cannot" && "$(field "$r" r2)" == "withdrawn: ${want}"* && "$(field "$r" vl)" == "0" && "$(field "$r" reads)" == "0" ]]; then
        k_rows="$k_rows $sw"
    else
        k_ok=0; bad "(3k) swap '$sw' under a dormant verdict → $r"
    fi
done
[[ $k_ok -eq 1 ]] && ok "(3k) M1 — the stored token swapped 10 s after the mint, under a DORMANT verdict —$k_rows — the reporter re-classifies at the ONE derivation site and answers withdrawn AT ONCE with the measured reason (rot → 'no longer classifies ok'; a re-pair → 'gen=8 in force now, the verdict rests on gen=7'; a raised bound on the same gen → 'the re-derived elapsed_floor 160s exceeds the 100s of silence the verdict was minted on'), the gate refuses (rc 1), the dormant step drops the verdict — ZERO network reads (dormant is zero-NETWORK; the token re-read is local). Pre-fix: served proven=yes, gate rc 0, until +51 s"

# (3l) N4: a token that IMPROVES mid-episode never mints retroactively. Pre-fix red: yes at +121 with since=T0.
case_improve() {
    printf '%s\n' "$(mk_token 8 30 120 real holder1)" > "$PROOF_STATE_DIR/pairing-token"   # floor 160
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 120 )); _elapsed_step; local a1="$_elapsed_answer" r1="$_elapsed_reason"
    printf '%s\n' "$(mk_token 9 30 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token"   # re-paired to floor 100 mid-episode
    _SIM_NOW=$(( T0 + 121 )); _elapsed_step; local a2="$_elapsed_answer" r2="$_elapsed_reason" i2="$LASTINFO"
    _SIM_NOW=$(( T0 + 220 )); _elapsed_step; local a3="$_elapsed_answer" r3="$_elapsed_reason"
    _SIM_NOW=$(( T0 + 221 )); _elapsed_step; local a4="$_elapsed_answer"
    local v; v=$(_elapsed_provider)
    echo "a1=$a1|r1=$r1|a2=$a2|r2=$r2|i2=$i2|a3=$a3|r3=$r3|a4=$a4|oid=$(_proof_field "$v" observation_id)"
}
r=$(drive_ep "$STANDBY" case_improve | tail -1)
if [[ "$(field "$r" a1)" == "no" && "$(field "$r" r1)" == *"observed silence 120s < elapsed_floor 160s"* ]] \
   && [[ "$(field "$r" a2)" == "no" && "$(field "$r" r2)" == *"the token now in force (gen 9) was adopted 0s ago"* && "$(field "$r" i2)" == *"token gen=9 adopted at mono $(( T0 + 121 ))"* ]] \
   && [[ "$(field "$r" a3)" == "no" && "$(field "$r" r3)" == *"adopted 99s ago"* && "$(field "$r" a4)" == "yes" && "$(field "$r" oid)" == "elapsed:gen=9:since=$(( T0 + 121 )):floor=100" ]]; then
    ok "(3l) N4 — a token that IMPROVES mid-episode (gen 8 floor 160 → gen 9 floor 100 at +121, 121 s into the silence) does NOT mint retroactively: the provider stamps the new gen's adoption (mono +121, logged) and measures the floor from it — no at +121 ('adopted 0s ago') and at +220 ('99s ago'), PROVEN only at +221 with since=+121 in the observation_id. Pre-fix: PROVEN at +121 with since=+0 (the 120 s counted under the old token)"
else
    bad "(3l) $r"
fi

# (3m) M7 (N6): a vantage re-pin under a standing verdict. Pre-fix red: served proven=yes vantage=T2 while
# the seam's vantage was T3, gate rc 0.
case_repin() {
    reg; prime_seam 0 none
    VOTE_LIVENESS_MIN_INTERVAL=10
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step; local a1="$_elapsed_answer"
    T2_DOWN=1; _SIM_NOW=$(( T0 + 105 ))
    staked_is_actively_voting; local lrc=$?                     # the take path's REAL gate: T3 answers → provider flip → re-pin
    local fr; fr=$(dump_freshness)
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    echo "a1=$a1|lrc=$lrc|s_vant=$(field "$fr" vantage)|p=$(_proof_field "$v" proven)|v_vant=$(_proof_field "$v" vantage)|r=$(_proof_field "$v" elapsed_reason)|grc=$grc"
}
r=$(drive_ep "$STANDBY" case_repin | tail -1)
if [[ "$(field "$r" a1)" == "yes" && "$(field "$r" lrc)" == "2" && "$(field "$r" s_vant)" == "T3" ]] \
   && [[ "$(field "$r" p)" == "no" && "$(field "$r" v_vant)" == "T3" && "$(field "$r" r)" == *"freshness triple (vantage/observed_since/blind_until) T2/${T0}/0 at the mint, now T3/${T0}/0"* && "$(field "$r" grc)" == "1" ]]; then
    ok "(3m) M7 — a vantage re-pin under a standing verdict (T2 down: the REAL vote-liveness gate reads T3 and re-pins the pair to it, rc 2) WITHDRAWS the verdict: the reporter serves proven=no naming the triple T2/…→T3/… and the vantage it serves is the seam's own (T3 = dump_freshness), the gate refuses (rc 1). Pre-fix: served proven=yes vantage=T2 against a T3 seam, gate rc 0"
else
    bad "(3m) $r"
fi

# (3n) M4 (INT-4/N7) at the provider: non-canonical integers are unusable, never arithmetic. Pre-fix red:
# "0009999" aborted the whole case (no output line — 'value too great for base'); 2^64+HEAD minted PROVEN.
case_noncanon() {   # $NC: lv | head0 | headwrap
    reg; prime_seam 0 none
    case "$NC" in
        lv)       LV='"0009999"' ;;                                     # the holder's lastVote as a JSON STRING
        head0)    HEADSTR='"0009999"' ;;                                # the spare's own head, zero-padded (the view stays HEAD0-based)
        headwrap) HEADSTR=18446744073710451616 ;;                       # 2^64 + HEAD0: a plain JSON number (jq prints it verbatim)
    esac
    : > "$EV"; _SIM_NOW=$(( T0 + 150 )); _elapsed_step
    echo "a=$_elapsed_answer|r=$_elapsed_reason|after=reached"
}
n_ok=1; n_rows=""
for probe in "lv:blind:yielded no usable sample" "head0:cannot:no usable independent head" "headwrap:cannot:no usable independent head"; do
    nc="${probe%%:*}"; rest="${probe#*:}"; wa="${rest%%:*}"; wr="${rest#*:}"
    r=$(NC=$nc drive_ep "$STANDBY" case_noncanon 2>"$WORK/nc.err" | tail -1)
    if [[ "$(field "$r" after)" == "reached" && "$(field "$r" a)" == "$wa" && "$(field "$r" r)" == *"$wr"* ]]; then n_rows="$n_rows $nc→$wa"; else n_ok=0; bad "(3n) '$nc' → '${r:-NO OUTPUT (the case aborted)}' stderr: $(tr '\n' ' ' < "$WORK/nc.err" | cut -c1-220)"; fi
done
[[ $n_ok -eq 1 ]] && ok "(3n) M4 — non-canonical integers at the provider land unusable and the evaluation COMPLETES:$n_rows (a zero-padded lastVote the sampler rejects; a zero-padded or 2^64+N own head refused before any arithmetic). Pre-fix: '0009999' aborted the evaluation mid-arithmetic ('value too great for base' — the whole enclosing command dies) and 2^64+HEAD wrapped to HEAD and MINTED"
case_canon_table() {
    local out="" x
    for x in 0 5000 922337203685477580 9223372036854775807 00 01 0009999 9223372036854775808 9999999999999999999 10000000000000000000 18446744073710451616 -1 "" " 5" "5 " 1e3 5000.0 0x10; do
        if _canon_uint "$x"; then out="$out[$x]=1"; else out="$out[$x]=0"; fi
    done
    echo "t=$out"
}
r=$(drive_ep "$STANDBY" case_canon_table 2>/dev/null | tail -1)
want='t=[0]=1[5000]=1[922337203685477580]=1[9223372036854775807]=1[00]=0[01]=0[0009999]=0[9223372036854775808]=0[9999999999999999999]=0[10000000000000000000]=0[18446744073710451616]=0[-1]=0[]=0[ 5]=0[5 ]=0[1e3]=0[5000.0]=0[0x10]=0'
if [[ "$r" == "$want" ]] && cmp -s <(sed -n '/^_canon_uint() {/,/^}/p' "$STANDBY") <(sed -n '/^_canon_uint() {/,/^}/p' "$PRIMARY") && [[ -n "$(sed -n '/^_canon_uint() {/,/^}/p' "$STANDBY")" ]]; then
    ok "(3n-table) the ONE validator _canon_uint (BYTE-IDENTICAL in both daemons): accepts 0 / 5000 / 2^63-1 (the 19-digit ceiling), refuses every leading zero, 2^63, 19-digit 9s, 20-digit values, 2^64+N, a sign, the empty string, padding, exponent/decimal/hex forms"
else
    bad "(3n-table) got '$r'"
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
echo ""; echo "─── (5) multilayer: the seam-regression line (5a–5d) and the REACHABLE post-blindness state (5e–5h) ───"
# (5a)–(5d) THE SEAM-REGRESSION DEFENSE LINE — the old archetype, kept deliberately: every step layer
# refuses it on its own. A planted short-floor token (W10+B20+M10 = 40 < TAKEOVER_DELAY 60 → does not
# classify ok), 30 s of observed silence (< even that 40 s floor), a blind interval that ended 20 s ago
# on a seam whose observed span did NOT restart at it (the pre-slice-4 seam state — a primed fixture
# write the CURRENT seam writers cannot produce: _note_blind_cycle zeroes observed_since), and a view
# lagging 40 slots (> N_HEAD 25). It measures the defense in depth a seam regression would lean on.
# [elapsed-floor] is ONE layer with two halves (6.3 fix round, M1): the silence >= elapsed_floor at the
# mint, and — at every serve — the re-derived floor never above the silence the verdict was minted on.
case_archetype() {
    _proof_startup_check >/dev/null 2>&1
    prime_seam 70 80
    VIEWLAG=40
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step
    local v; v=$(_elapsed_provider)
    echo "reg=$_elapsed_registered|a=$_elapsed_answer|r=$_elapsed_reason|why=${_proof_floor_why:-}|proven=$(_proof_field "$v" proven)|vr=$(_proof_field "$v" elapsed_reason)|vlen=${#v}"
}
layer_of() {   # the NAMED layer that refused, from the captured record (the step first, then the reporter)
    local r="$1" x
    if [[ "$(field "$r" reg)" == "0" ]]; then echo "token"; return; fi
    x="$(field "$r" r)"; [[ "$(field "$r" a)" == "yes" ]] && x="$(field "$r" vr)"
    [[ "$(field "$r" a)" == "yes" && "$(field "$r" proven)" == "yes" ]] && { echo "NONE(proven)"; return; }
    case "$x" in
        *"blindness ended"*|*"no continuous observation"*) echo "blind" ;;
        *"observed silence"*"< elapsed_floor"*|*"exceeds the"*"of silence the verdict was minted on"*) echo "floor" ;;
        *"LAGGED VIEW"*|*"STALE REFERENCE"*) echo "head" ;;
        *"the seam moved under the verdict"*) echo "seam" ;;
        *"token no longer classifies ok"*|*"stored token changed"*) echo "token" ;;
        *) echo "other:$x" ;;
    esac
}
M_TOKEN='s/_derive_proof_floors || {/_derive_proof_floors; true || {/g'
M_BLIND1='s/if \[\[ \$_es_since -le 0 \]\]; then/if [[ 1 -eq 2 ]]; then/'
M_BLIND2='s/if \[\[ \$_es_blind -gt 0 && /if [[ 1 -eq 2 \&\& /'
M_FLOOR1='s/if \[\[ \$(( _es_now - _es_since )) -lt \$elapsed_floor \]\]; then/if [[ 1 -eq 2 ]]; then/'
M_FLOOR2='s/if \[\[ \$elapsed_floor -gt \$_elapsed_mint_silence \]\]; then/if [[ 1 -eq 2 ]]; then/'
M_HEAD='s/-gt \$N_HEAD \]\]; then/-gt 999999999 ]]; then/g'
M_SEAM1='s/^    if \[\[ \$_evw_since -le 0 \]\]; then/    if [[ 1 -eq 2 ]]; then/'
M_SEAM2='s/^    if \[\[ "\$_evw_triple" != "\$_elapsed_triple" \]\]; then/    if [[ 1 -eq 2 ]]; then/'
r=$(TOK=lowfloor drive_ep "$STANDBY" case_archetype | tail -1)
if [[ "$(layer_of "$r")" == "token" && "$(field "$r" why)" == *"SHORTER than the un-armed timer path"* && "$(field "$r" vlen)" == "0" ]]; then
    ok "(5a) LIVE seam-regression archetype → refused by [elapsed-token] FIRST (not registered: the derivation site's own reason — floor 40 s SHORTER than the un-armed timer path); the provider does not exist on this host"
else
    bad "(5a) $r"
fi
mutate "$STANDBY" "$M_TOKEN" "$WORK/n-token.sh"
mutate "$STANDBY" "$M_BLIND1" "$WORK/n-blind-a.sh" && mutate "$WORK/n-blind-a.sh" "$M_BLIND2" "$WORK/n-blind.sh"
mutate "$STANDBY" "$M_FLOOR1" "$WORK/n-floor-a.sh" && mutate "$WORK/n-floor-a.sh" "$M_FLOOR2" "$WORK/n-floor.sh"
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
[[ $s_ok -eq 1 ]] && ok "(5b) each step layer neutered ALONE, the seam-regression archetype still refused by a NAMED surviving layer:$s_rows — one neutered layer never reopens the hole"
mutate "$WORK/n-token.sh" "$M_BLIND1" "$WORK/c1a.sh" && mutate "$WORK/c1a.sh" "$M_BLIND2" "$WORK/c-tb.sh"
mutate "$WORK/c-tb.sh" "$M_FLOOR1" "$WORK/c-tbf-a.sh" && mutate "$WORK/c-tbf-a.sh" "$M_FLOOR2" "$WORK/c-tbf.sh"
mutate "$WORK/c-tbf.sh" "$M_HEAD" "$WORK/c-all.sh"
r1=$(TOK=lowfloor drive_ep "$WORK/n-token.sh" case_archetype | tail -1)
r2=$(TOK=lowfloor drive_ep "$WORK/c-tb.sh" case_archetype | tail -1)
r3=$(TOK=lowfloor drive_ep "$WORK/c-tbf.sh" case_archetype | tail -1)
r4=$(TOK=lowfloor drive_ep "$WORK/c-all.sh" case_archetype | tail -1)
if [[ "$(layer_of "$r1")" == "blind" && "$(layer_of "$r2")" == "floor" && "$(layer_of "$r3")" == "head" ]] \
   && [[ "$(field "$r1" r)" == *"blindness ended 20s ago"* && "$(field "$r2" r)" == *"observed silence 30s < elapsed_floor 40s"* && "$(field "$r3" r)" == *"40 slots behind this spare's own head"* ]]; then
    ok "(5c) the chain, each kill reason captured: token neutered → [elapsed-blind] ('blindness ended 20s ago'); +blind → [elapsed-floor] ('observed silence 30s < elapsed_floor 40s'); +floor → [elapsed-head] ('40 slots behind this spare's own head') — every step layer refuses the archetype on its own"
else
    bad "(5c) r1=$(layer_of "$r1") r2=$(layer_of "$r2") r3=$(layer_of "$r3") :: $r3"
fi
if [[ "$(field "$r4" a)" == "yes" && "$(field "$r4" proven)" == "yes" ]]; then
    ok "(5d) [elapsed-token]/[elapsed-blind]/[elapsed-floor] (both halves)/[elapsed-head] ALL neutered → the seam-regression archetype MINTS and is SERVED PROVEN (forged acceptance RESTORED): no hidden guard on this line ([elapsed-seam] does not see it — the archetype's seam never moves after the mint; (5e)–(5h) is where that layer is load-bearing)"
else
    bad "(5d) all-neutered mutant did not restore the forged acceptance: $r4"
fi
# (5e)–(5h) THE REACHABLE POST-BLINDNESS STATE (6.3 fix round, T1 — panel CC-2): pinned and observed
# since T0, the REAL seam writer stamps a blind cycle at +5 (observed_since → 0, the pin KEPT), and the
# provider evaluates at +6 — before any re-observation. Registered 200 s earlier, so the N4 adoption
# floor stays out of the way and the layers below are what refuse. [elapsed-seam] = the reporter's
# serve-time seam checks (an observed span must stand under the verdict; the served triple is the seam's).
case_reachable() {
    _SIM_NOW=$(( T0 - 200 )); _proof_startup_check >/dev/null 2>&1
    prime_seam 0 none
    _SIM_NOW=$(( T0 + 5 )); _note_blind_cycle "$_SIM_NOW"
    local fr; fr=$(dump_freshness)
    _SIM_NOW=$(( T0 + 6 )); _elapsed_step
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    _proof_age_edge_check; local erc=$?
    echo "reg=$_elapsed_registered|a=$_elapsed_answer|r=$_elapsed_reason|proven=$(_proof_field "$v" proven)|vr=$(_proof_field "$v" elapsed_reason)|oid=$(_proof_field "$v" observation_id)|grc=$grc|erc=$erc|s_since=$(field "$fr" observed_since)|s_blind=$(field "$fr" blind_until)|s_vant=$(field "$fr" vantage)"
}
r=$(drive_ep "$STANDBY" case_reachable | tail -1)
if [[ "$(field "$r" s_since)" == "0" && "$(field "$r" s_blind)" == "$(( T0 + 5 ))" && "$(field "$r" s_vant)" == "T2" ]] \
   && [[ "$(field "$r" a)" == "blind" && "$(field "$r" r)" == *"no continuous observation"* && "$(field "$r" grc)" == "1" && "$(layer_of "$r")" == "blind" ]]; then
    ok "(5e) LIVE, the REACHABLE state: after the real _note_blind_cycle (observed_since=0, blind_until=+5, the pin still T2) an evaluation 1 s later answers blind ('no continuous observation') and the gate refuses — [elapsed-blind] holds it"
else
    bad "(5e) $r"
fi
mutate "$STANDBY" "$M_SEAM1" "$WORK/s-seam-a.sh" && mutate "$WORK/s-seam-a.sh" "$M_SEAM2" "$WORK/s-seam.sh"
mutate "$WORK/n-blind.sh" "$M_SEAM1" "$WORK/s-bs-a.sh" && mutate "$WORK/s-bs-a.sh" "$M_SEAM2" "$WORK/s-bs.sh"
mutate "$WORK/s-bs.sh" "$M_FLOOR2" "$WORK/s-bsf.sh"
rb=$(drive_ep "$WORK/n-blind.sh" case_reachable | tail -1)
rs=$(drive_ep "$WORK/s-seam.sh" case_reachable | tail -1)
rbs=$(drive_ep "$WORK/s-bs.sh" case_reachable | tail -1)
rall=$(drive_ep "$WORK/s-bsf.sh" case_reachable | tail -1)
if [[ "$(field "$rb" a)" == "yes" && "$(layer_of "$rb")" == "seam" && "$(field "$rb" vr)" == *"no observed span now (observed_since=0"* && "$(field "$rb" grc)" == "1" ]] \
   && [[ "$(layer_of "$rs")" == "blind" && "$(field "$rs" grc)" == "1" ]]; then
    ok "(5f) each neutered ALONE on the reachable state: [elapsed-blind] gone → the step MINTS ('1s of observed silence' since blind_until) and [elapsed-seam] withdraws it at the reporter ('no observed span now (observed_since=0 …)'), gate rc 1; [elapsed-seam] gone → [elapsed-blind] still refuses at the step, gate rc 1 — the reporter's check is a NAMED layer with its own neuter control"
else
    bad "(5f) blind-neutered=$rb :: seam-neutered=$rs"
fi
if [[ "$(field "$rbs" a)" == "yes" && "$(layer_of "$rbs")" == "floor" && "$(field "$rbs" vr)" == *"the re-derived elapsed_floor 100s exceeds the 1s of silence the verdict was minted on"* && "$(field "$rbs" grc)" == "1" ]]; then
    ok "(5g) [elapsed-blind] AND [elapsed-seam] neutered → a THIRD named layer still refuses: [elapsed-floor]'s serve-time half ('the re-derived elapsed_floor 100s exceeds the 1s of silence the verdict was minted on' — the 6.3 fix round's M1 re-check), gate rc 1"
else
    bad "(5g) blind+seam-neutered=$rbs"
fi
if [[ "$(field "$rall" a)" == "yes" && "$(field "$rall" proven)" == "yes" && "$(field "$rall" grc)" == "0" && "$(field "$rall" erc)" == "0" && "$(field "$rall" oid)" == "elapsed:gen=7:since=$(( T0 + 5 )):floor=100" ]]; then
    ok "(5h) all three neutered ([elapsed-blind] + [elapsed-seam] + [elapsed-floor]'s serve half) → the FORGED ACCEPTANCE AT THE GATE reappears: require_relinquish_proof rc 0 and _proof_age_edge_check rc 0 on observation_id since=+5 — 1 s after a stamped blindness. The enumerated set is complete over the reachable state"
else
    bad "(5h) all-neutered reachable mutant did not restore the forged acceptance: $rall"
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
d1=$(SIL=105 VL=1 drive_ep "$WORK/m20-decoupled.sh" case_couple | tail -1)
d2=$(SIL=115 VL=40 drive_ep "$WORK/m20-decoupled.sh" case_couple | tail -1)
together_6a() {   # (6a)'s assertion as a predicate over (base1, mutant1, base2, mutant2)
    [[ "$(field "$1" floor)/$(field "$1" nhead)" == "100/25" && "$(field "$2" floor)/$(field "$2" nhead)" == "110/50" ]] \
    && [[ "$(field "$1" a)" == "yes" && "$(field "$2" a)" == "no" && "$(field "$2" r)" == *"observed silence 105s < elapsed_floor 110s"* ]] \
    && [[ "$(field "$3" a)" == "blind" && "$(field "$4" a)" == "yes" ]]
}
if together_6a "$b1" "$m1" "$b2" "$m2"; then
    ok "(6a) MARGIN_ELAPSED 10→20 → floor 100→110 AND N_HEAD 25→50, and the provider follows BOTH, measured: 105 s of silence proves on the shipped build and does NOT on the mutant ('105s < 110s'); a 40-slot lagged view is blind on the shipped build and proves on the mutant — tolerance and floor rise TOGETHER (the only sanctioned response to vantages failing the cross-check)"
else
    bad "(6a) base1=$b1 mut1=$m1 base2=$b2 mut2=$m2"
fi
if [[ "$(field "$d2" floor)/$(field "$d2" nhead)" == "110/25" && "$(field "$d2" a)" == "blind" ]] && ! together_6a "$b1" "$d1" "$b2" "$d2"; then
    ok "(6b) CONTROL: the coupling additionally broken (N_HEAD static at 25 while MARGIN is 20) → floor 110 with N_HEAD 25, the 40-slot view stays blind, and (6a)'s together-predicate EVALUATED on this double mutant is FALSE (observed, not inferred)"
else
    bad "(6b) decoupled mutant gave: $d1 :: $d2 (together-predicate must be false on it)"
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
[[ $b_ok -eq 1 && "$alt" == "ok" ]] && ok "(8a) live census: reads per step = below-floor 0 / mint 2 / dormant-proven 0 / blind evaluation 2 / paced 0 (the ${_ELAPSED_READ_PACE_SECS:-2} s pace); reads == pets in every step and no two reads adjacent in the live log (each read is followed by a pet before the next read)"
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
else
    bad "(8b) EMPTY [elapsed-provider] region extraction — the static census would be vacuous"
fi

# ── (9) constants ──────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) constants: the region assigns none of the derived names; the N_HEAD condition stays at its site ───"
CONST_RE='(^[[:space:]]*((local|declare|export|readonly)[[:space:]]+([-][[:alnum:]]+[[:space:]]+)*)?(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE)=)|(\(\([[:space:]]*(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE)[[:space:]]*=)'
k_ok=1
for d in "$STANDBY" "$PRIMARY"; do
    rg=$(extract_region "$d" '\[elapsed-provider\] watchdog-elapsed (attested time) proof provider' '\[elapsed-provider\] end shared block')
    [[ -n "$rg" ]] || { k_ok=0; bad "(9a) $(basename "$d"): EMPTY [elapsed-provider] region extraction — the constants census would be vacuous"; }
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
# The world (the D0 driver, ported). Every decision function is REAL (tier1, local_check_delinquency,
# window_*, attempt_takeover, confirm/tier2/tier3, staked_is_actively_voting, the sampler,
# take_staked_identity, _fresh_proof_recheck, check_self_fence_isolation and — armed — _elapsed_step and
# the G2 provider). Only I/O is stubbed. 6.3 fix round: the mono clock is FILE-BACKED, so a stubbed read
# running inside $() can TAKE time (latency, timeouts, pet cost) and the time it takes is seen by every
# stamp the daemon takes after it.
# SLOT RATE (T3 — an explicit knob): head slot(t) = HEAD0 + t x SLOT_NUM/SLOT_DEN, default 5/2 = 2.5
# slots/s (400 ms slots — the rate every seconds figure in this build ASSUMES; mainnet MEASURED ~3.7
# slots/s on 2026-09-26, design-records/mainnet-slot-time-2026-09-26.md). EVERY seconds figure in (11)
# and (12) is at 2.5 slots/s unless a case names another rate. The boundaries in SLOTS: the own bank's
# delinquency rule 128; finalized = processed − 32 (a landed vote reaches the finalized bank ceil(32 /
# rate) s later — 13 s at 2.5/s); getHealth's distance 128; N_HEAD 25; the minority vote-bank FREEZE 8.
# THE HOLDER: its last vote before the episode lands at t=0; it votes again from RESUME (-1 never) until
# STOP (-1 forever); each landed vote trails the head by HLAGS slots (default 0).
# THE SPARE'S OWN NODE (LOCAL_RPC), from verified agave v4.2.1 facts only: processed = the tower's last
# VOTABLE bank (replay_stage handle_votable_bank → update_commitment_cache; commitment_service slot =
# that bank); finalized = processed − 32; confirmed = the optimistically confirmed bank (processed − 2
# here); getVoteAccounts/getSlot at the commitment the request carries (none → the RPC default,
# finalized); agave's 128-slot delinquency rule; getHealth exactly as rpc_health.rs computes it (the
# node's own optimistic slot vs the latest optimistic slot its OWN blockstore observed via replay +
# gossip, distance 128). CUT=<t> CUTMODE:
#     full            from t the spare hears nothing (every bank and its blockstore freeze)
#     minority        from t the spare is on a MINORITY side: none of the holder's (majority) votes land
#                     in its banks, nothing new is optimistically confirmed or finalized there (no 2/3),
#                     and its processed (VOTE) bank advances FREEZE slots (default 8 — the tower's
#                     depth-8 2/3 threshold, VOTE_THRESHOLD_DEPTH; ~3 s at 2.5/s) and then FREEZES; gossip cut
#     minority-gossip the same, but the supermajority's gossip votes still reach the spare, so its
#                     blockstore's latest optimistic slot keeps advancing (getHealth's cluster side)
#   (6.3 fix round — D0-P2: the pre-fix world advanced the minority processed head FOREVER, which agave
#   does not do; its "processed would take at t145" counterfactual came from that and is dropped — (11f).)
#   LAG=<s>: the spare replays <s> seconds behind the chain (its blockstore still observes the cluster's
#   optimistic slot on time). LCOMM=processed|confirmed: WHAT-IF MUTANTS (never shipped) of the own-bank
#   read's commitment — controls that show which way the shipped default cuts. LHMB: an operator's
#   LOCAL_HEALTH_MAX_BEHIND (unset = the shipped default from the seam, printed as lhmb).
# TIERMODE — what TIER2/TIER3 serve (the premise under test, not an assumption about who is lying):
#     splice (default) ONE active intermediary: the head proxied LIVE, the holder served FROZEN at its
#                     pre-episode vote and delinquent
#     honest          the TRUE chain as of t − TLAG (default 0) at the commitment asked — an HONEST tier,
#                     lagging but advancing when TLAG > 0 (D0-LAG)
#     cofrozen        honest until CUT, then partitioned TOGETHER with the spare (the minority side's
#                     view: its max lastVote freezes FREEZE slots past the cut exactly like the spare's
#                     vote bank; none of the holder's majority votes arrive)
#   G2FORGE=1 (armed): G2 configured on the DEFAULT (shared) vantages and the intermediary forges the
#   holder's unstaked-identity flip once the episode is open (D0-P1B).
# DOWNFROM/DOWNTO: both tiers refuse every read in [DOWNFROM, DOWNTO) (an outage, no latency).
# LATENCY through the file clock: T2DOWN=1 T2 times out at its -m bound; SLOWFROM/SLOWTO/T3LAT: the
# sampler's T2 reads (commitment=processed) in [SLOWFROM, SLOWTO) time out at their -m bound and its T3
# reads answer T3LAT s late (the F2 slow-observing read, any TIERMODE); SPLICE_DELAY=max|<s> with
# SPLICE_SEL=all|afterconfirm (from SPLICE_FROM): tier answers delayed to (-m − 1) s or <s> — the
# protocol-aware 'afterconfirm' delays from the external-confirm read (a getVoteAccounts WITHOUT a
# commitment) to the end of that cycle (D0-LAT); CURLMAX=1 every read takes its full -m bound; PETS=<s>
# every pet costs <s> (armed; the house counting is 7) and its completion is logged; HOLDCOOL=1 holds
# the take on the cooldown (a pet-gap world). ARMED=1: paired (gen 7, W30 B60 → floor 100 s); GATE=1
# the 6.4-placement EMULATION below; POSTTAKE=1 the loop runs on after the mutation (the STAKED
# branch: H1). HOSTILE=lv0 the tiers serve the holder's lastVote as the JSON STRING "0009999";
# HOSTILE=headwrap the spare's processed getSlot answers 2^64 + the true head (M4).
world() {   # prints one k=v| summary line
    (
        set +e
        W=$(mktemp -d "$WORK/w.XXXXXX"); EV="$W/ev"; : > "$EV"; IDF="$W/id"; echo U1 > "$IDF"
        CLK="$W/clk"; echo "$T0" > "$CLK"
        PROOF_STATE_DIR="$W/ps"; mkdir -p "$PROOF_STATE_DIR"
        _ws="${WSCRIPT:-$STANDBY}"   # WSCRIPT: a mutant standby (the (12f) pet controls); default the shipped one
        load_seam "$_ws"
        region=$(extract_region "$_ws" '^while \$_running; do' '^done$') || { echo "region=EMPTY"; exit 1; }
        eval "run_loop() {
$region
}"
        STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; VOTE_PUBKEY=V1; PRIMARY_UNSTAKED_PUBKEY=""
        LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
        TAKEOVER_DELAY=60; TAKEOVER_COOLDOWN=120; EXTERNAL_CONFIRM_THROTTLE=12
        MAX_DELINQUENT_SLOTS=${MDS:-0}; DRY_RUN=false; GOSSIP_VERIFY=${GV:-false}; WITNESS_FASTPATH=false
        VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_EPSILON=0; VOTE_LIVENESS_MIN_INTERVAL=10; VOTE_LIVENESS_MIN_SPAN=40
        # LOCAL_HEALTH_MAX_BEHIND: the shipped default from the seam (printed as lhmb) unless LHMB overrides it
        [[ -n "${LHMB:-}" ]] && LOCAL_HEALTH_MAX_BEHIND=$LHMB
        SOLANA_PATH="$W"; LEDGER_PATH=/x; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15
        STAKED_KEYPAIR="$W/staked.json"; printf '[1]' > "$STAKED_KEYPAIR"; UNSTAKED_KEYPAIR="$W/unstaked.json"; printf '[2]' > "$UNSTAKED_KEYPAIR"
        CHECK_INTERVAL=5; TURBO_INTERVAL=1; _current_interval=5; HEARTBEAT_INTERVAL=999999; _last_heartbeat=$T0
        ALERT_THROTTLE=600; TAKEOVER_STARVATION_ALERT_SECS=0
        [[ "${HOLDCOOL:-0}" == "1" ]] && { LAST_TAKEOVER_TIME=$T0; TAKEOVER_COOLDOWN=999999; }
        # the FILE-BACKED mono clock (installed AFTER load_seam: its reshim re-applies the _SIM_NOW shims)
        _now() { local x; read -r x < "$CLK"; echo "$x"; }
        _adv() { local x; read -r x < "$CLK"; echo $(( x + $1 )) > "$CLK"; }
        _t() { local x; read -r x < "$CLK"; echo $(( x - T0 )); }
        mono_now() { _now; }
        date() { if [[ "$1" == "+%s" ]]; then _now; return 0; fi; command date "$@"; }
        log() { :; }; log_info() { :; }; log_error() { :; }
        log_warn() {   # the mint INSTANT, from the provider's own PROVEN line; the H1 give-back reason
            case "$*" in
                *"watchdog-elapsed PROVEN"*) local _o="${*##*observed_at=}"; echo "elapsed-mint t=$(_t) oat=$(( ${_o%%;*} - T0 ))" >> "$EV" ;;
                *"[self-fence] LOCAL confirmed slot frozen"*) echo "h1-fence t=$(_t)" >> "$EV" ;;
            esac
        }
        alert() { :; }; alert_warn() { :; }; alert_info() { :; }; send_telegram() { :; }; send_webhook() { :; }
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _fence_rot_check() { :; }
        flush_pending_alerts() { :; }; save_state() { :; }; _sd_notify() { :; }
        get_local_identity() { cat "$IDF"; }
        display_status() {
            rm -f "$W/spl"
            local ek=none
            case "${_elapsed_reason:-}" in "STALE REFERENCE"*) ek=stale ;; "LAGGED VIEW"*) ek=lag ;; esac
            echo "cycle t=$(_t) status=$1 fdt=${FIRST_DELINQUENT_TIME} ea=${_elapsed_answer:-na} ek=$ek fh=${_ep_floor_holds:-0}" >> "$EV"
        }
        case "${LCOMM:-default}" in
            processed)
                eval "$(declare -f local_check_delinquency | sed 's/"method":"getVoteAccounts"}/"method":"getVoteAccounts","params":[{"commitment":"processed"}]}/')"
                declare -f local_check_delinquency | grep -qF '"getVoteAccounts","params":[{"commitment":"processed"}]' || { echo "world: the LCOMM=processed what-if mutant did not apply"; exit 1; } ;;
            confirmed)
                eval "$(declare -f local_check_delinquency | sed -e 's/"method":"getVoteAccounts"}/"method":"getVoteAccounts","params":[{"commitment":"confirmed"}]}/' -e 's/"method":"getSlot"}/"method":"getSlot","params":[{"commitment":"confirmed"}]}/')"
                declare -f local_check_delinquency | grep -qF '"getVoteAccounts","params":[{"commitment":"confirmed"}]' || { echo "world: the LCOMM=confirmed what-if mutant did not apply"; exit 1; } ;;
        esac
        eval "$(declare -f attempt_takeover | sed '1s/attempt_takeover/_real_attempt_takeover/')"
        attempt_takeover() { echo "attempt t=$(_t)" >> "$EV"; _real_attempt_takeover; }
        timeout() {
            [[ "$1" == "-k" ]] && shift 2
            shift
            case "$*" in
                *" set-identity $UNSTAKED_KEYPAIR"*) echo "GIVEBACK t=$(_t)" >> "$EV"; echo U1 > "$IDF"; return 0 ;;
                *" set-identity "*) echo "MUTATION t=$(_t)" >> "$EV"; echo S1 > "$IDF"; return 0 ;;
                *"authorized-voter"*) return 0 ;;
            esac
            "$@"
        }
        _SN=${SLOT_NUM:-5}; _SD=${SLOT_DEN:-2}; _FL=$(( (32 * _SD + _SN - 1) / _SN ))   # finalized visibility lag = ceil(32 slots / rate)
        _slot() { echo $(( HEAD0 + $1 * _SN / _SD )); }
        _hv() {   # the holder's latest landed vote time <= $1
            local at="$1" r="${RESUME:--1}" s="${STOP:--1}" lv=0
            if [[ $r -ge 0 && $at -ge $r ]]; then lv=$at; [[ $s -ge 0 && $lv -gt $s ]] && lv=$s; fi
            echo "$lv"
        }
        _hvs() { echo $(( $(_slot "$(_hv "$1")") - ${HLAGS:-0} )); }   # ... as a slot (trailing the head by HLAGS)
        _gva() {   # $1=bank $2=holder lastVote → a getVoteAccounts body under agave's 128-slot rule (the world's '<')
            if [[ $2 -lt $(( $1 - 128 )) ]]; then
                printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]},"id":1}' "$(( $1 - 1 ))" "$2"
            else
                printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s},{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]},"id":1}' "$(( $1 - 1 ))" "$2"
            fi
        }
        curl() {
            local url="" d="" src m mm t te hp hf hc vp vf vc comm vh vv mo oo mt=10 dly=0 ida idb nodes
            while [[ $# -gt 0 ]]; do
                case "$1" in -d) d="$2"; shift 2 ;; -m) mt="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac
            done
            case "$url" in "$LOCAL_RPC") src=LOCAL ;; "$TIER2_RPC") src=T2 ;; "$TIER3_RPC") src=T3 ;; *) src=OTHER ;; esac
            case "$d" in *getHealth*) m=getHealth ;; *getVoteAccounts*) m=getVoteAccounts ;; *getSlot*) m=getSlot ;; *) m=other ;; esac
            case "$d" in "["*) mm=batch ;; *getClusterNodes*) mm=getClusterNodes ;; *getBlockTime*) mm=getBlockTime ;; *) mm=$m ;; esac
            comm=default; case "$d" in *'"commitment":"processed"'*) comm=processed ;; *'"commitment":"confirmed"'*) comm=confirmed ;; esac
            t=$(_t)
            echo "read $src $m t=$t" >> "$EV"
            # ── latency (the file clock) ──
            if [[ "$src" == "T2" && "${T2DOWN:-0}" == "1" ]]; then _adv "$mt"; echo "timeout T2 +${mt}" >> "$EV"; return 28; fi
            if [[ ( "$src" == "T2" || "$src" == "T3" ) && $t -ge ${DOWNFROM:--1} && $t -lt ${DOWNTO:--1} ]]; then echo "down $src" >> "$EV"; return 7; fi
            if [[ "$comm" == "processed" && ( "$src" == "T2" || "$src" == "T3" ) ]]; then   # the sampler's reads (SLOWFROM/SLOWTO/T3LAT)
                if [[ "$src" == "T2" && $t -ge ${SLOWFROM:--1} && $t -lt ${SLOWTO:--1} ]]; then _adv "$mt"; echo "timeout T2 +${mt}" >> "$EV"; return 28; fi
                if [[ "$src" == "T3" && $t -ge ${SLOWFROM:--1} && $t -lt $(( ${SLOWTO:--1} + mt + 1 )) && ${T3LAT:-0} -gt 0 ]]; then _adv "$T3LAT"; echo "late T3 +${T3LAT}" >> "$EV"; fi
            fi
            if [[ ( "$src" == "T2" || "$src" == "T3" ) && -n "${SPLICE_DELAY:-}" ]]; then
                case "$SPLICE_DELAY" in max) dly=$(( mt - 1 )) ;; *) dly=$SPLICE_DELAY; [[ $dly -gt $(( mt - 1 )) ]] && dly=$(( mt - 1 )) ;; esac
                local _sel=0
                case "${SPLICE_SEL:-all}" in
                    all) [[ $t -ge ${SPLICE_FROM:-0} ]] && _sel=1 ;;
                    afterconfirm)
                        if [[ "$m" == "getVoteAccounts" && "$comm" == "default" && $t -ge ${SPLICE_FROM:-0} ]]; then : > "$W/spl"; _sel=1
                        elif [[ -e "$W/spl" ]]; then _sel=1; fi ;;
                esac
                if [[ $dly -gt 0 && $_sel -eq 1 ]]; then _adv "$dly"; echo "late $src +${dly}" >> "$EV"; fi
            fi
            [[ "${CURLMAX:-0}" == "1" ]] && _adv "$mt"
            t=$(_t)   # the answer reflects the chain at the instant it is served
            if [[ "$src" == "LOCAL" ]]; then
                # the spare's own node at t: hp/hf/hc = processed/finalized/confirmed head, vp/vf/vc = the
                # holder's lastVote in those banks, mo = own optimistic slot, oo = the latest optimistic
                # slot its blockstore observed (getHealth's two sides)
                local mode="${CUTMODE:-none}" c="${CUT:--1}" lag="${LAG:-0}" fz
                [[ $c -lt 0 || $t -le $c ]] && mode=none
                case "$mode" in
                    none) te=$(( t - lag )); hp=$(_slot "$te"); hf=$(( hp - 32 )); hc=$(( hp - 2 ))
                          vp=$(_hvs "$te"); vf=$(_hvs $(( te - _FL ))); vc=$(_hvs $(( te - 1 )))
                          mo=$hc; oo=$(( $(_slot "$t") - 2 )) ;;
                    full) te=$(( c - lag )); hp=$(_slot "$te"); hf=$(( hp - 32 )); hc=$(( hp - 2 ))
                          vp=$(_hvs "$te"); vf=$(_hvs $(( te - _FL ))); vc=$(_hvs $(( te - 1 )))
                          mo=$hc; oo=$(( $(_slot "$c") - 2 )) ;;
                    minority|minority-gossip)
                          hp=$(_slot "$t"); fz=$(( $(_slot "$c") + ${FREEZE:-8} )); [[ $hp -gt $fz ]] && hp=$fz
                          hf=$(( $(_slot "$c") - 32 )); hc=$(( $(_slot "$c") - 2 ))
                          vp=$(_hvs "$c"); vf=$(_hvs $(( c - _FL ))); vc=$(_hvs $(( c - 1 )))
                          mo=$hc; oo=$mo
                          [[ "$mode" == "minority-gossip" ]] && oo=$(( $(_slot "$t") - 2 )) ;;
                    *) return 7 ;;
                esac
                case "$m" in
                    getHealth)
                        if [[ $mo -ge $(( oo - 128 )) ]]; then printf '{"jsonrpc":"2.0","result":"ok","id":1}'; else printf '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by %s slots","data":{"numSlotsBehind":%s}},"id":1}' "$(( oo - mo ))" "$(( oo - mo ))"; fi ;;
                    getSlot)
                        case "$comm" in
                            processed) if [[ "${HOSTILE:-}" == "headwrap" ]]; then printf '{"jsonrpc":"2.0","result":18446744073%09d,"id":1}' "$(( 709551616 + hp ))"; else printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$hp"; fi ;;
                            confirmed) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$hc" ;;
                            *) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$hf" ;;
                        esac ;;
                    getVoteAccounts)
                        case "$comm" in processed) vh=$hp; vv=$vp ;; confirmed) vh=$hc; vv=$vc ;; *) vh=$hf; vv=$vf ;; esac
                        _gva "$vh" "$vv" ;;
                    *) return 7 ;;
                esac
                return 0
            fi
            # ── TIER2/TIER3 ──
            local tm="${TIERMODE:-splice}" ts bp bf hvp hvf fz
            if [[ "$tm" == "splice" ]]; then
                case "$mm" in
                    getVoteAccounts)
                        if [[ "${HOSTILE:-}" == "lv0" ]]; then
                            printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":"0009999"}]},"id":1}' "$(( $(_slot "$t") - 1 ))"
                        else
                            printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]},"id":1}' "$(( $(_slot "$t") - 1 ))" "$(_slot 0)"
                        fi
                        return 0 ;;
                    getSlot) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(_slot "$t")"; return 0 ;;
                esac
            else
                ts=$(( t - ${TLAG:-0} ))
                if [[ "$tm" == "cofrozen" && ${CUT:--1} -ge 0 && $t -gt ${CUT:--1} ]]; then
                    bp=$(_slot "$t"); fz=$(( $(_slot "$CUT") + ${FREEZE:-8} )); [[ $bp -gt $fz ]] && bp=$fz
                    bf=$(( $(_slot "$CUT") - 32 )); hvp=$(_hvs "$CUT"); hvf=$(_hvs $(( CUT - _FL )))
                else
                    bp=$(_slot "$ts"); bf=$(( bp - 32 )); hvp=$(_hvs "$ts"); hvf=$(_hvs $(( ts - _FL )))
                fi
                case "$mm" in
                    getVoteAccounts) if [[ "$comm" == "processed" ]]; then _gva "$bp" "$hvp"; else _gva "$bf" "$hvf"; fi; return 0 ;;
                    getSlot) if [[ "$comm" == "processed" ]]; then printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$bp"; else printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$bf"; fi; return 0 ;;
                esac
            fi
            # G2's reads (D0-P1B): the gossip table, the [getSlot, getClusterNodes] batch, getBlockTime
            local ep="1.2.3.4:8001" flip=0
            [[ "${G2FORGE:-0}" == "1" && ${FIRST_DELINQUENT_TIME:-0} -gt 0 ]] && flip=1
            case "$mm" in
                getClusterNodes)
                    [[ "${G2FORGE:-0}" == "1" ]] || return 7
                    if [[ $flip -eq 1 ]]; then nodes=$(printf '[{"pubkey":"S1","gossip":"%s"},{"pubkey":"UPK1","gossip":"%s"},{"pubkey":"churn%s%s","gossip":"9.9.9.9:1"}]' "$ep" "$ep" "$src" "$t")
                    else nodes=$(printf '[{"pubkey":"S1","gossip":"%s"},{"pubkey":"churn%s%s","gossip":"9.9.9.9:1"}]' "$ep" "$src" "$t"); fi
                    printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$nodes" ;;
                batch)
                    [[ "${G2FORGE:-0}" == "1" ]] || return 7
                    ida=${d#*\"id\":}; ida=${ida%%,*}; idb=${d##*\"id\":}; idb=${idb%%,*}
                    if [[ $flip -eq 1 ]]; then nodes=$(printf '[{"pubkey":"S1","gossip":"%s"},{"pubkey":"UPK1","gossip":"%s"},{"pubkey":"churn%s%s","gossip":"9.9.9.9:1"}]' "$ep" "$ep" "$src" "$t")
                    else nodes=$(printf '[{"pubkey":"S1","gossip":"%s"},{"pubkey":"churn%s%s","gossip":"9.9.9.9:1"}]' "$ep" "$src" "$t"); fi
                    printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":%s}]' "$ida" "$(( $(_slot "$t") - 2 ))" "$idb" "$nodes" ;;
                getBlockTime)
                    [[ "${G2FORGE:-0}" == "1" ]] || return 7
                    ida=${d#*\"id\":}; ida=${ida%%,*}
                    printf '{"jsonrpc":"2.0","id":%s,"result":%s}' "$ida" "$(_now)" ;;
                *) return 7 ;;
            esac
            return 0
        }
        if [[ "${ARMED:-0}" == "1" ]]; then
            NOTIFY_SOCKET="$W/n.sock"; WATCHDOG_USEC=30000000; _WATCHDOG_READY=1
            _watchdog_pet() { [[ ${PETS:-0} -gt 0 ]] && _adv "$PETS"; echo "pet t=$(_t)" >> "$EV"; return 0; }
            [[ "${G2FORGE:-0}" == "1" ]] && PRIMARY_UNSTAKED_PUBKEY=UPK1
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
                require_relinquish_proof || { echo "gate-refused t=$(_t)" >> "$EV"; return 1; }
                echo "gate-accepted t=$(_t) prov=$(_proof_field "$_proof_last_verdict" provider)" >> "$EV"
                _real_take_staked_identity "$@"
            }
        fi
        sleep() {   # every main-loop/HOLD sleep (the REAL _watchdog_sleep chunks + pets through it)
            _adv "${1%%.*}"
            if [[ $(_t) -ge ${HORIZON:-200} ]] || { [[ "${POSTTAKE:-0}" != "1" ]] && grep -q '^MUTATION' "$EV"; }; then _running=false; fi
            return 0
        }
        _running=true
        # the loop runs in its OWN subshell: a bash expansion error (M4's class) discards the whole enclosing
        # command — here that subshell — so the world survives to report it (the marker is then missing)
        ( run_loop; echo "loop-returned" >> "$EV" ) 2>"$W/loop.err"
        _end=horizon
        if ! grep -q '^loop-returned' "$EV"; then _end="aborted@t$(_t):$(tr '\n' ' ' < "$W/loop.err" | sed 's/.*line \([0-9]*\): /line \1: /' | cut -c1-80)"
        elif grep -q '^MUTATION' "$EV" && [[ "${POSTTAKE:-0}" != "1" ]]; then _end=mutation; fi
        [[ -n "${KEEPEV:-}" ]] && cp "$EV" "$KEEPEV"
        E=$(grep -m1 ' status=DELINQ ' "$EV" | sed 's/.* fdt=\([0-9]*\).*/\1/'); [[ -n "$E" ]] && E=$(( E - T0 ))
        mut=$(grep -m1 '^MUTATION' "$EV" | sed 's/.*t=//')
        veto=""; [[ ${RESUME:--1} -ge 0 && -n "$E" ]] && veto=$(awk -v r="${RESUME}" -v e="$E" '/^cycle / { split($2,a,"="); t=a[2]+0; if (t>=r && t>e && $3=="status=OK") { print t; exit } }' "$EV")
        emint=$(grep -m1 '^elapsed-mint ' "$EV" | sed 's/^elapsed-mint t=\([0-9]*\).*/\1/')
        eoat=$(grep -m1 '^elapsed-mint ' "$EV" | sed 's/.* oat=//')
        estale=$(grep -c ' ek=stale' "$EV")
        estale_from=$(grep -m1 ' ek=stale' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/')
        cyc_from=0; [[ -n "$estale_from" ]] && cyc_from=$(awk -v f="$estale_from" '/^cycle / { split($2,a,"="); if (a[2]+0 >= f) c++ } END { print c+0 }' "$EV")
        elag_from=$(grep -m1 ' ek=lag' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/')
        t1b=$(grep -m1 ' status=T1:BEHIND ' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/')
        tco=$(awk '/^read LOCAL getVoteAccounts/{n=NR} /^MUTATION/{m=NR} END{print n+0, m+0}' "$EV")
        between=$(awk -v range="$tco" 'BEGIN{split(range,x," ")} NR>x[1] && NR<x[2] && /^read LOCAL/{c++} END{print c+0}' "$EV")
        order=$(awk -v range="$tco" 'BEGIN{split(range,x," ")} NR>=x[1] && NR<=x[2] && (/^read/ || /^attempt/ || /^gate-/ || /^MUTATION/) {sub(/ t=[0-9]+/,""); printf "%s;", $0}' "$EV")
        lastlocal=""; [[ -n "$mut" ]] && lastlocal=$(awk '/^read LOCAL getVoteAccounts/{l=$4} /^MUTATION/{print l; exit}' "$EV" | sed 's/t=//')
        voting=""; [[ -n "$mut" && ${RESUME:--1} -ge 0 && $mut -ge ${RESUME:--1} ]] && { if [[ ${STOP:--1} -lt 0 ]]; then voting=$(( mut - RESUME )); else voting="stopped@${STOP}"; fi; }
        petgap=$(awk '/^pet t=/{ split($2,a,"="); t=a[2]+0; if (seen && t-p > g) g=t-p; p=t; seen=1 } END{print g+0}' "$EV")
        fholds=$(awk '/^cycle /{ for (i=1;i<=NF;i++) if ($i ~ /^fh=/) { split($i,a,"="); if (a[2]+0 > m) m=a[2]+0 } } END{print m+0}' "$EV")
        echo "E=${E:-none}|veto=${veto:-none}|mutation=${mut:-none}|end=$_end|emint=${emint:-none}|eoat=${eoat:-none}|estale_cycles=$estale|estale_from=${estale_from:-none}|cycles_from_stale=$cyc_from|elag_from=${elag_from:-none}|t1_behind_from=${t1b:-never}|lhmb=${LOCAL_HEALTH_MAX_BEHIND:-unset}|local_reads_between=$between|own_read_before_mut=${lastlocal:-none}|holder_voting_at_mut=${voting:-no}|giveback=$(grep -m1 '^GIVEBACK' "$EV" | sed 's/.*t=//')|h1=$(grep -m1 '^h1-fence' "$EV" | sed 's/.*t=//')|petgap=$petgap|pets=$(grep -c '^pet t=' "$EV")|floor_holds=$fholds|order=$order|gate=$(grep -m1 '^gate-accepted' "$EV" | sed 's/^gate-accepted //')"
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
# (11b-rate) the SAME race at the MEASURED mainnet rate (≈ 3.7 slots/s, 2026-09-26 — the slot-rate knob): the
# boundaries are facts in SLOTS; their seconds shrink with the rate (T3: every seconds figure names its rate)
rb37a=$(SLOT_NUM=37 SLOT_DEN=10 MDS=0 RESUME=96 HORIZON=160 world | tail -1)
rb37b=$(SLOT_NUM=37 SLOT_DEN=10 MDS=0 RESUME=97 HORIZON=160 world | tail -1)
if [[ "$(field "$rb37a" E)" == "45" && "$(field "$rb37a" veto)" == "105" && "$(field "$rb37a" mutation)" == "none" ]] \
   && [[ "$(field "$rb37b" mutation)" == "105" && "$(field "$rb37b" holder_voting_at_mut)" == "8" ]]; then
    ok "(11b-rate) MEASURED at 3.7 slots/s: the episode opens at t45 (128 slots ≈ 35 s, not 51 s) and the timer path takes at t105; resumed at t96 → vetoed, at t97 → taken after 8 s — the veto boundary is the finalized lag, 32 slots (≈ 9 s here, ≈ 13 s at 2.5/s)"
else
    bad "(11b-rate) r96=$rb37a :: r97=$rb37b"
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
# (11f) P2: a spare on a MINORITY fork from t30 (the holder alive and voting on the majority throughout) —
# the physical model (6.3 fix round, D0-P2): processed is the tower's VOTE bank and freezes within ~8 votes
rf1=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority HORIZON=200 world | tail -1)
rf2=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority LCOMM=processed HORIZON=160 world | tail -1)
rf3=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority LCOMM=confirmed HORIZON=160 world | tail -1)
if [[ "$(field "$rf1" E)" == "none" && "$(field "$rf1" mutation)" == "none" && "$(field "$rf1" t1_behind_from)" == "never" ]] \
   && [[ "$(field "$rf2" E)" == "none" && "$(field "$rf2" mutation)" == "none" && "$(field "$rf3" E)" == "none" && "$(field "$rf3" mutation)" == "none" ]]; then
    ok "(11f) MEASURED — a spare on a MINORITY fork from t30 (none of the holder's votes land there, gossip cut): getHealth stays ok (no new optimistic slot anywhere it can see), and the SHIPPED own-bank read at finalized holds (a minority fork does not finalize: the holder stays current, no episode, no take); the what-if reads at processed and at confirmed hold TOO — processed is the tower's vote bank, frozen within ~8 votes of the fork (agave replay_stage handle_votable_bank → update_commitment_cache), confirmed needs 2/3. (6.3 fix round, D0-P2: the pre-fix world advanced the minority processed head forever, and its 'processed would take at t145' counterfactual came from that — dropped.) A fork that PRECEDES the episode is held on every commitment; one that begins AFTER it is (11i)"
else
    bad "(11f) shipped=$rf1 processed-whatif=$rf2 confirmed-whatif=$rf3"
fi
# (11g) P2 with the supermajority's gossip still arriving: the blockstore keeps learning optimistic slots
rg1=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority-gossip HORIZON=160 world | tail -1)
rg2=$(MDS=0 RESUME=0 CUT=30 CUTMODE=minority-gossip LCOMM=processed HORIZON=160 world | tail -1)
if [[ "$(field "$rg1" t1_behind_from)" == "85" && "$(field "$rg1" mutation)" == "none" && "$(field "$rg2" t1_behind_from)" == "85" && "$(field "$rg2" E)" == "none" && "$(field "$rg2" mutation)" == "none" ]]; then
    ok "(11g) MEASURED — the same minority fork but with the supermajority's gossip votes still reaching the spare: getHealth reports it behind from t85 (its blockstore's optimistic slot runs 128+ slots ahead of its own — 51.2 s at 2.5 slots/s) and Tier-1 holds from then on, under the shipped read AND under the processed what-if (which never reads the holder delinquent on the frozen vote bank anyway)"
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
    ok "(11h) MEASURED — a spare replaying 40 s (100 slots) behind passes Tier-1 (agave reads ok up to 128) and the own-bank veto's reaction grows by the lag: a holder resumed at t95 is vetoed, one resumed at t115 is taken over at t165 after 50 s of voting; 60 s (150 slots) behind → Tier-1 BEHIND from t0, no episode (the shipped LOCAL_HEALTH_MAX_BEHIND=$(field "$rh3" lhmb) is below agave's default distance 128, so its within-tolerance branch can never admit an agave 'behind' report — every such report is > 128; a value ABOVE 128 widens it — (11m)); ARMED at 40 s behind with a genuinely silent holder, watchdog-elapsed refuses STALE REFERENCE from its first evaluation (t211) on every cycle to the horizon — no take (availability: a spare more than N_HEAD behind cannot prove by time)"
else
    bad "(11h) lag40-resume95=$rh1 lag40-resume115=$rh2 lag60=$rh3 armed-lag40=$rh4"
fi

# ── (11i)–(11n) DOCUMENTED RESIDUALS (6.3 fix round, T3): each asserts the MEASURED behavior, and each says
# which remedy flips it. None is fixed in this round (the remedies are reviewed design changes).
#
# (11i) the spare partitioned AFTER the episode opened, together with its tiers (co-frozen). THE MODEL,
# reconciling the panel (F1 / CC-1 / D0-P2 / D0-LAG): on a partition side holding < 2/3 the tower fails its
# depth-8 threshold within ~8 votes, so the spare's processed (= VOTE) bank stops ~8 slots past the cut and
# the co-partitioned tiers' max lastVote stops with it (their side stops voting too); none of the holder's
# majority votes arrive. F1 minted against a LIVE splicer only because the pre-fix world kept the minority
# processed head advancing forever; against a live view the physical spare reads STALE REFERENCE (ri4).
# RESIDUAL — this flips when the Tier-1 own-head advance (e) lands (both paths: the vote bank stops at the
# fork); the armed path also when watchdog-elapsed's own-bank CONFIRMED-head progress floor lands.
ri1=$(TIERMODE=cofrozen CUT=80 CUTMODE=minority RESUME=90 MDS=0 HORIZON=200 world | tail -1)
ri2=$(TIERMODE=cofrozen CUT=80 CUTMODE=minority RESUME=90 MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
ri3=$(TIERMODE=cofrozen CUT=80 CUTMODE=minority MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
ri4=$(CUT=80 CUTMODE=minority RESUME=90 MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
ri5=$(TIERMODE=cofrozen CUT=66 CUTMODE=minority RESUME=90 MDS=0 HORIZON=200 world | tail -1)
ri6=$(TIERMODE=cofrozen CUT=66 CUTMODE=minority RESUME=90 MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
if [[ "$(field "$ri1" E)" == "65" && "$(field "$ri1" mutation)" == "125" && "$(field "$ri1" holder_voting_at_mut)" == "35" ]] \
   && [[ "$(field "$ri2" emint)" == "171" && "$(field "$ri2" mutation)" == "171" && "$(field "$ri2" gate)" == "t=171 prov=watchdog-elapsed" && "$(field "$ri2" holder_voting_at_mut)" == "81" ]] \
   && [[ "$(field "$ri3" mutation)" == "171" && "$(field "$ri3" gate)" == "t=171 prov=watchdog-elapsed" ]] \
   && [[ "$(field "$ri4" mutation)" == "none" && "$(field "$ri4" emint)" == "none" && "$(field "$ri4" estale_from)" == "171" && "$(field "$ri4" estale_cycles)" -gt 0 && "$(field "$ri4" estale_cycles)" == "$(field "$ri4" cycles_from_stale)" ]] \
   && [[ "$(field "$ri5" mutation)" == "none" && "$(field "$ri6" emint)" == "171" && "$(field "$ri6" mutation)" == "none" ]]; then
    ok "(11i) RESIDUAL (MEASURED) — the spare and its tiers partitioned together at t80, AFTER the episode opened (E=65) and after the pin (t71), the holder voting on the majority from t90: un-armed the take mutates at t125 (35 s into the holder's voting — the timer path has no gate here: the tiers' tip advanced past the pinned tip before it froze, so the tip guard passes); ARMED, watchdog-elapsed MINTS PROVEN at t171 (the frozen vote bank and the co-frozen view agree within N_HEAD) and the proof-gated take mutates at t171, 81 s into the holder's voting — indistinguishable from a DEAD holder (also t171). Against a LIVE view instead (the splicer) the same spare reads STALE REFERENCE from t171 on every cycle: no mint. Tiers that froze BEFORE the pin (cut t66): the tip guard holds the take on both paths (armed: the provider mints at t171, Gate 3 never reaches the gate) — the tip guard sees a freeze only AT OR BEFORE the pinned first sample"
else
    bad "(11i) unarmed=$ri1 :: armed=$ri2 :: armed-dead=$ri3 :: armed-liveview=$ri4 :: prepin-unarmed=$ri5 :: prepin-armed=$ri6"
fi
# (11j) the LATENCY term Σ (D0-LAT): the splicer answers every tier read of the take cycle at (curl -m) − 1 s,
# from the external-confirm read on (a protocol-aware choice — that read carries no commitment), legal
# within every bound. The own bank is read ONCE, at the take cycle's start.
# RESIDUAL — this flips when an own-bank re-read at the mutation edge (c-after) lands.
rj1=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm MDS=0 RESUME=112 HORIZON=200 world | tail -1)
rj2=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm MDS=0 RESUME=113 HORIZON=200 world | tail -1)
rj3=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm GV=true MDS=0 RESUME=113 HORIZON=220 world | tail -1)
rj4=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm T2DOWN=1 MDS=0 RESUME=113 HORIZON=260 world | tail -1)
rj5=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm ARMED=1 GATE=1 MDS=0 RESUME=166 HORIZON=260 world | tail -1)
rj6=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm ARMED=1 GATE=1 MDS=0 RESUME=169 HORIZON=260 world | tail -1)
if [[ "$(field "$rj1" veto)" == "125" && "$(field "$rj1" mutation)" == "none" ]] \
   && [[ "$(field "$rj2" mutation)" == "147" && "$(field "$rj2" own_read_before_mut)" == "125" && "$(field "$rj2" holder_voting_at_mut)" == "34" ]] \
   && [[ "$(field "$rj3" mutation)" == "175" && "$(field "$rj3" holder_voting_at_mut)" == "62" && "$(field "$rj4" mutation)" == "182" && "$(field "$rj4" holder_voting_at_mut)" == "69" ]] \
   && [[ "$(field "$rj5" mutation)" == "none" && "$(field "$rj6" emint)" == "181" && "$(field "$rj6" mutation)" == "203" && "$(field "$rj6" holder_voting_at_mut)" == "34" ]]; then
    ok "(11j) RESIDUAL (MEASURED) — the intermediary controls LATENCY: the veto boundary is unchanged (r112 vetoed at t125 — the own bank is read once, at the take cycle's start), but the mutation trails that read by Σ: r113 → mutation at t147, 34 s into the holder's voting (own bank read at t125; Σ = 22 s at GOSSIP_VERIFY=false); GOSSIP_VERIFY=true → t175 / 62 s (the advisory's two reads join Σ); T2 blackholed → t182 / 69 s. ARMED under the 6.4 emulation the provider mints at t181 and r169 is taken at t203 after 34 s (r166 is vetoed) — Σ applies to the proof-gated path too"
else
    bad "(11j) r112=$rj1 :: r113=$rj2 :: gv=$rj3 :: t2down=$rj4 :: armed-r166=$rj5 :: armed-r169=$rj6"
fi
# (11k) an HONEST tier lagging but advancing (D0-LAG, the TLAG rows) — replaces the incoherent "partitioned
# together, live tip" premise: TIER2/TIER3 serve the TRUE chain TLAG seconds late; no adversary.
# RESIDUAL — this flips when a Gate-3 head cross-check (f) or the mutation-edge own-bank re-read (c-after) lands.
rk1=$(TIERMODE=honest TLAG=40 MDS=0 RESUME=112 HORIZON=200 world | tail -1)
rk2=$(TIERMODE=honest TLAG=40 MDS=0 RESUME=113 HORIZON=200 world | tail -1)
rk3=$(TIERMODE=honest TLAG=10 MDS=0 RESUME=115 HORIZON=200 world | tail -1)
rk4=$(TIERMODE=honest TLAG=10 MDS=0 RESUME=116 HORIZON=200 world | tail -1)
rk5=$(TIERMODE=honest MDS=0 HORIZON=200 world | tail -1)
rk6=$(TIERMODE=honest TLAG=40 MDS=0 ARMED=1 GATE=1 HORIZON=260 world | tail -1)
if [[ "$(field "$rk1" mutation)" == "none" && "$(field "$rk1" veto)" == "125" && "$(field "$rk2" mutation)" == "125" && "$(field "$rk2" holder_voting_at_mut)" == "12" ]] \
   && [[ "$(field "$rk3" mutation)" == "none" && "$(field "$rk4" mutation)" == "125" && "$(field "$rk4" holder_voting_at_mut)" == "9" && "$(field "$rk5" mutation)" == "125" ]] \
   && [[ "$(field "$rk6" mutation)" == "none" && "$(field "$rk6" emint)" == "none" && "$(field "$rk6" elag_from)" == "171" ]]; then
    ok "(11k) RESIDUAL (MEASURED) — an HONEST tier 40 s behind (still advancing) reproduces the splicer race EXACTLY with no adversary on an un-armed install: r112 vetoed by the own bank at t125, r113 taken at t125 after 12 s of renewed voting; 10 s behind: r115 caught (the tiers see it by t125), r116 taken at t125 after 9 s; the honest dead-holder control takes at t125. ARMED at 40 s behind watchdog-elapsed reads LAGGED VIEW from t171 on (lag > N_HEAD = 25 slots, 10 s at 2.5 slots/s) — no mint, no take"
else
    bad "(11k) tlag40-r112=$rk1 :: tlag40-r113=$rk2 :: tlag10-r115=$rk3 :: tlag10-r116=$rk4 :: dead=$rk5 :: armed=$rk6"
fi
# (11l) the ARMED intermittent holder (D0-INTERMIT-ARMED): MAX_DELINQUENT_SLOTS=15, ONE holder vote at t40
# that reaches the spare's own bank (current t53–t59), the splicer on the tiers.
# RESIDUAL — this flips when the own-bank 'current' verdict restarts the span (b') or the co-witness (d) lands.
rl1=$(ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200 world | tail -1)
if [[ "$(field "$rl1" veto)" == "53" && "$(field "$rl1" emint)" == "126" && "$(field "$rl1" mutation)" == "126" && "$(field "$rl1" gate)" == "t=126 prov=watchdog-elapsed" ]]; then
    ok "(11l) RESIDUAL (MEASURED) — armed, the intermittent holder: the own bank reads the t40 vote current from t53, yet watchdog-elapsed mints PROVEN at t126 (its clock runs from the episode's first sample, t26, and never sees the vote the tiers withhold) and the proof-gated take mutates at t126 — 86 s after a vote the spare's OWN bank saw: the verdict's '100 s of silence' overstates the true silence by 14 s, more than MARGIN_ELAPSED (10 s)"
else
    bad "(11l) $rl1"
fi
# (11m) LOCAL_HEALTH_MAX_BEHIND > 128 (CC-4 = D0-LHMB): a spare 60 s (150 slots) behind, the holder resuming at t150.
# RESIDUAL — this flips when clamping LOCAL_HEALTH_MAX_BEHIND lands (this build ANNOUNCES it at startup: M9).
rm1=$(LAG=60 LHMB=200 RESUME=150 MDS=0 HORIZON=260 world | tail -1)
rm2=$(LAG=60 LHMB=128 RESUME=150 MDS=0 HORIZON=260 world | tail -1)
rm3=$(LAG=60 RESUME=150 MDS=0 HORIZON=260 world | tail -1)
if [[ "$(field "$rm1" lhmb)" == "200" && "$(field "$rm1" t1_behind_from)" == "never" && "$(field "$rm1" E)" == "125" && "$(field "$rm1" mutation)" == "185" && "$(field "$rm1" holder_voting_at_mut)" == "35" ]] \
   && [[ "$(field "$rm2" t1_behind_from)" == "0" && "$(field "$rm2" mutation)" == "none" && "$(field "$rm3" t1_behind_from)" == "0" && "$(field "$rm3" mutation)" == "none" ]]; then
    ok "(11m) RESIDUAL (MEASURED) — LOCAL_HEALTH_MAX_BEHIND=200 WIDENS Tier-1: a spare 150 slots behind (agave reports 'behind by ~150') passes it, the episode opens at t125 and the take mutates at t185, 35 s into the holder's renewed voting; at 128 and at the shipped 100 the same spare is Tier-1 BEHIND from t0 (no episode) — the knob is inert at <= 128 at agave's default distance and widens above it"
else
    bad "(11m) lhmb200=$rm1 :: lhmb128=$rm2 :: default=$rm3"
fi
# (11n) P1b with a FORGED G2 on the default (shared) vantages (D0-P1B): the spare fully cut off at t80, the
# holder voting from t90, the intermediary forging the unstaked-identity flip once the episode is open.
# RESIDUAL — this flips when the Tier-1 own-head advance (e) lands (P1b on every path, forged G2 included).
rn1=$(MDS=0 RESUME=90 CUT=80 CUTMODE=full HORIZON=200 world | tail -1)
rn2=$(ARMED=1 GATE=1 G2FORGE=1 MDS=0 RESUME=90 CUT=80 CUTMODE=full HORIZON=200 world | tail -1)
rn3=$(ARMED=1 GATE=1 G2FORGE=1 MDS=0 RESUME=90 CUT=80 CUTMODE=full POSTTAKE=1 HORIZON=220 world | tail -1)
rn4=$(MDS=0 CUT=30 CUTMODE=full HORIZON=200 world | tail -1)
if [[ "$(field "$rn1" mutation)" == "125" && "$(field "$rn1" holder_voting_at_mut)" == "35" ]] \
   && [[ "$(field "$rn2" mutation)" == "132" && "$(field "$rn2" gate)" == "t=132 prov=verified-demote" && "$(field "$rn2" holder_voting_at_mut)" == "42" ]] \
   && [[ "$(field "$rn3" mutation)" == "132" && "$(field "$rn3" h1)" == "168" && "$(field "$rn3" giveback)" == "168" ]] \
   && [[ "$(field "$rn4" E)" == "none" && "$(field "$rn4" mutation)" == "none" ]]; then
    ok "(11n) RESIDUAL (MEASURED) — P1b: un-armed the cut-off spare takes at t125 (the holder voting 35 s); ARMED with G2 on the default (shared) vantages the forged flip PROVES verified-demote and the gate accepts: take at t132, the holder voting 42 s; after the take the promoted spare's H1 self-fence (its LOCAL confirmed slot frozen >= 30 s) gives the identity back at t168 (36 s after the take). P1a (cut at t30, BEFORE any episode, the holder dead): no episode ever opens — a silent availability loss, no page"
else
    bad "(11n) p1b-unarmed=$rn1 :: g2forge=$rn2 :: posttake=$rn3 :: p1a=$rn4"
fi

# ── (12) the 6.3 fix round's mechanism reds, re-run green ──────────────────────────────────────
echo ""; echo "─── (12) fix round 1: M2 post-read starts / M3 observed_at / M4 through the loop / M5 exit code / M6 pet gap / M8 status ───"
# (12a) M2 (F2) — the silence START stamped AFTER the read that established it. The world: honest tiers,
# MAX_DELINQUENT_SLOTS=15, a holder ALIVE (each vote landing 20 slots behind the head — delinquent to the
# spare, under its own 32-slot vote-lag fence) until STOP; the Gate-3 read at t135 hits one T2 timeout
# (curl -m 10) and T3 answers T3LAT s late carrying the holder's last votes. Pre-fix red (de21927):
# T3LAT=5 STOP=149 → the proof-gated take at t235 = 86 s after the holder's last vote (< W+B = 90);
# T3LAT=1 STOP=145 → t235 = 90 s; the slow-PIN world (the prefetch pin at t71 taking 19 s) → mint t171.
ra1=$(TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=149 SLOWFROM=135 SLOWTO=136 T3LAT=5 ARMED=1 GATE=1 HORIZON=330 world | tail -1)
ra2=$(TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=145 SLOWFROM=135 SLOWTO=136 T3LAT=1 ARMED=1 GATE=1 HORIZON=330 world | tail -1)
ra3=$(TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=134 ARMED=1 GATE=1 HORIZON=330 world | tail -1)
ra4=$(SLOWFROM=71 SLOWTO=72 T3LAT=9 MDS=0 ARMED=1 GATE=1 HORIZON=260 world | tail -1)
ra5=$(SLOWFROM=71 SLOWTO=72 T3LAT=9 MDS=0 HORIZON=200 world | tail -1)
sil1=$(( $(field "$ra1" mutation) - 149 )); sil2=$(( $(field "$ra2" mutation) - 145 )); sil3=$(( $(field "$ra3" mutation) - 134 ))
if [[ "$(field "$ra1" emint)" == "250" && "$(field "$ra1" gate)" == "t=250 prov=watchdog-elapsed" && $sil1 -ge 100 ]] \
   && [[ "$(field "$ra2" emint)" == "246" && $sil2 -ge 100 && "$(field "$ra3" mutation)" == "235" && $sil3 -ge 100 ]]; then
    ok "(12a) M2 — F2's slow-observing read (one T2 timeout on the Gate-3 read at t135, T3 answering 5 s late with the holder's last votes; the holder silent after t149): the VOTING re-pin now stamps the ANSWER's arrival (t150), so watchdog-elapsed mints and the proof-gated take lands at t250 — ${sil1} s after the holder's last vote (>= W+B+MARGIN_ELAPSED = 100); T3LAT=1/STOP=145 → t246 (${sil2} s); the no-slow-read control is unchanged at t235 (${sil3} s). Pre-fix: t235 in the first two = 86 s and 90 s (< / = W+B = 90)"
else
    bad "(12a) t3lat5=$ra1 :: t3lat1=$ra2 :: control=$ra3"
fi
if [[ "$(field "$ra4" emint)" == "190" && "$(field "$ra4" mutation)" == "190" && "$(field "$ra5" mutation)" == "135" && "$(field "$ra5" floor_holds)" == "0" ]]; then
    ok "(12a-pin) M2 at the attempt_takeover PREFETCH PIN (the pin read at t71 costs a T2 timeout + 9 s of T3 latency): the observed-span start is the answer's arrival (t90), so the provider mints at t190 (pre-fix t171 — the 19 s the read took counted as observed silence); the un-armed take in the same world is UNCHANGED at t135 with ZERO span-floor holds — M2 is conservative on the span floor and, measured, binds it nowhere new (see also the report's probe set)"
else
    bad "(12a-pin) armed=$ra4 :: unarmed=$ra5"
fi

# a FILE-backed mono clock for ONE drive_ep case: T2/T3/LOCAL reads (and pets) then TAKE time inside $()
fileclock_on() {
    CLKF=$(mktemp "$WORK/clk.XXXXXX"); echo "$_SIM_NOW" > "$CLKF"
    mono_now() { local x; read -r x < "$CLKF"; echo "$x"; }
    _clk_adv() { local x; read -r x < "$CLKF"; echo $(( x + $1 )) > "$CLKF"; }
    eval "$(declare -f curl | sed '1s/^curl/_ep_curl/')"
    curl() {   # T2_DOWN/T3_DOWN: a timeout AT the -m bound; LAT_T3 / LAT_LOCAL: the answer that many s late
        local args=("$@") i=0 mt=10 url=""
        while [[ $i -lt ${#args[@]} ]]; do
            case "${args[$i]}" in -m) mt="${args[$((i+1))]}" ;; http*) url="${args[$i]}" ;; esac
            i=$((i+1))
        done
        case "$url" in
            "$TIER2_RPC") [[ "$T2_DOWN" == "1" ]] && _clk_adv "$mt" ;;
            "$TIER3_RPC") if [[ "$T3_DOWN" == "1" ]]; then _clk_adv "$mt"; else _clk_adv "${LAT_T3:-0}"; fi ;;
            "$LOCAL_RPC") _clk_adv "${LAT_LOCAL:-0}" ;;
        esac
        _ep_curl "$@"
    }
    _watchdog_pet() { echo "pet" >> "$EV"; _clk_adv "${PETCOST:-0}"; }
}
# (12b) M2, unit: every span-STARTING stamp of the Block-3 twin helper is post-read. Pre-fix red:
# blind_until / observed_since / pair_ts all equal the PRE-read stamp (+50 / +70 / +70).
case_m2unit() {
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 50 )); fileclock_on
    T2_DOWN=1; T3_DOWN=1
    staked_is_actively_voting; local rc1=$?; local fr1; fr1=$(dump_freshness)     # both tiers time out: +10 +10
    T3_DOWN=0; LAT_T3=5; LV=5003
    staked_is_actively_voting; local rc2=$?; local fr2; fr2=$(dump_freshness)     # T2 times out, T3 answers 5 s late with LIFE
    echo "rc1=$rc1|b1=$(field "$fr1" blind_until)|s1=$(field "$fr1" observed_since)|rc2=$rc2|s2=$(field "$fr2" observed_since)|pts2=$(field "$fr2" pair_ts)|pv2=$(field "$fr2" pair_vote)|clk=$(cat "$CLKF")"
}
r=$(drive_ep "$STANDBY" case_m2unit | tail -1)
if [[ "$(field "$r" rc1)" == "2" && "$(field "$r" b1)" == "$(( T0 + 70 ))" && "$(field "$r" s1)" == "0" ]] \
   && [[ "$(field "$r" rc2)" == "0" && "$(field "$r" s2)" == "$(( T0 + 85 ))" && "$(field "$r" pts2)" == "$(( T0 + 85 ))" && "$(field "$r" pv2)" == "5003" ]]; then
    ok "(12b) M2, unit (the REAL staked_is_actively_voting, a file clock): both tiers timing out (read from +50, answered +70) stamp blind_until=+70 — the END of the blindness; T2 timing out and T3 answering LIFE 5 s late (read from +70, answered +85) re-pin observed_since=+85 AND the pair's first end pair_ts=+85 — never the pre-read +70. Pre-fix: +50 / +70 / +70"
else
    bad "(12b) $r"
fi

# (12c) M3 (CC-5) — observed_at = the ANSWERING read's own pre-read stamp. House bound-counting on a file
# clock: T2 times out at its 10 s bound, every pet costs 7 s, T3 answers at its 10 s bound, the head read
# takes its 5 s bound. Pre-fix red: observed_at = the evaluation start (+150) — 46 s old at the mint.
case_m3() {
    reg; prime_seam 0 none
    _liveness_first_provider="T3"                                          # the episode pinned to T3 (a T2-down episode) — fixture write
    _SIM_NOW=$(( T0 + 150 )); fileclock_on
    T2_DOWN=1; LAT_T3=10; LAT_LOCAL=5; PETCOST=7
    _elapsed_step
    local mint; mint=$(cat "$CLKF")
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    _clk_adv 39                                                            # 6.1's census: acceptance slack 3 + recheck R_worst 36
    local ew=""; log_warn() { ew="$*"; }
    _proof_age_edge_check; local erc=$?
    echo "a=$_elapsed_answer|oat=$(_proof_field "$v" observed_at)|mint=$mint|grc=$grc|erc=$erc|ew=$ew"
}
r=$(drive_ep "$STANDBY" case_m3 | tail -1)
oat=$(field "$r" oat); mint=$(field "$r" mint)
if [[ "$(field "$r" a)" == "yes" && "$oat" == "$(( T0 + 167 ))" && "$mint" == "$(( T0 + 196 ))" && "$(field "$r" grc)" == "0" ]] \
   && [[ "$(field "$r" erc)" == "1" && "$(field "$r" ew)" == *"verdict age 68s"* ]]; then
    ok "(12c) M3 — under the house bound-counting (T2 timeout 10 + pet 7, T3 at its 10 s bound, head 5 s, pets 7 s) the verdict's observed_at is the T3 read's OWN pre-read stamp (+167 — not the evaluation start +150); the mint lands at +196: TAIL from observed_at to the mint = $(( mint - oat )) s (+ ~2 s parse glue in the field = the region comment's 31 s). The gate accepts it at the mint; after 6.1's acceptance slack + recheck R_worst (39 s) the edge check REFUSES it (verdict age 68 s > PROOF_MAX_AGE 50) — PROOF_MAX_AGE does not cover this provider's worst case for 6.4 (recorded in the region comment; unchanged here). Pre-fix: observed_at=+150, 46 s old at the mint, 85 s at the edge"
else
    bad "(12c) $r"
fi

# (12d) M4 (INT-4/N7) through the REAL main loop. Pre-fix red: the zero-padded lastVote ABORTS the loop at
# t125 ('value too great for base' in staked_is_actively_voting); 2^64 + the head WRAPS and the provider
# mints PROVEN and the proof-gated take mutates at t171.
rd1=$(HOSTILE=lv0 MDS=0 HORIZON=200 world | tail -1)
rd2=$(HOSTILE=headwrap ARMED=1 GATE=1 MDS=0 HORIZON=200 world | tail -1)
if [[ "$(field "$rd1" end)" == "horizon" && "$(field "$rd1" mutation)" == "none" && "$(field "$rd1" E)" == "65" ]] \
   && [[ "$(field "$rd2" end)" == "horizon" && "$(field "$rd2" emint)" == "none" && "$(field "$rd2" mutation)" == "none" ]]; then
    ok "(12d) M4 through the REAL loop: TIER2/TIER3 serving the holder's lastVote as the string \"0009999\" → the loop runs to the horizon (every sample unusable → blind, no take — fails toward NOT taking); the spare's own processed head served as 2^64 + head → the provider never mints (no usable head), no proof-gated take. Pre-fix: the loop ABORTED at t125; the wrapped head minted and took at t171"
else
    bad "(12d) lv0=$rd1 :: headwrap=$rd2"
fi

# (12d-holder) M4's census, N-is-all, on the HOLDER: the primary's optional latency demote path compared a
# TIER2 lastVote guarded only by ^[0-9]+$ — "0009999" aborted the HOLDER's main loop (its self-fence dead
# with it). Now non-canonical = unusable = the function's existing "Tier 2 unreachable — trusting local"
# branch (the same as any other junk answer; a demote is never a double-sign). Pre-fix red: no output line.
case_holder_lat() {
    eval "$(declare -f curl | sed '1s/^curl/_ep_curl/')"
    curl() { case " $* " in *"$TIER2_RPC"*getSlot*) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$HEAD"; return 0 ;; esac; _ep_curl "$@"; }
    LV='"0009999"'; MAX_VOTE_LATENCY=10; DELINQUENCY_RETRIES=3
    verify_latency_tiered 50; local rc=$?
    echo "rc=$rc|warn=$LASTWARN|after=reached"
}
r=$(drive_ep "$PRIMARY" case_holder_lat 2>"$WORK/hl.err" | tail -1)
if [[ "$(field "$r" after)" == "reached" && "$(field "$r" rc)" == "0" && "$(field "$r" warn)" == *"Tier 2 unreachable for latency — trusting local"* ]]; then
    ok "(12d-holder) the HOLDER's latency path (verify_latency_tiered): TIER2 serving lastVote \"0009999\" is unusable — the function COMPLETES through its existing 'Tier 2 unreachable — trusting local' branch instead of aborting the holder's loop. Pre-fix: 'value too great for base', no output"
else
    bad "(12d-holder) '${r:-NO OUTPUT (aborted)}' stderr: $(tr '\n' ' ' < "$WORK/hl.err" | cut -c1-200)"
fi

# (12e) M5 — an aborted main loop exits NON-ZERO. The daemon's REAL loop + tail run as a script FILE (the
# loop is a top-level command there, exactly as in the daemon, so an expansion error discards only it).
# Pre-fix red: the aborted loop fell through to 'Main loop exited.' and exited 0 (armed unit: Restart=no,
# OnFailure fires only on 'failed' → no restart, no fence, no page).
m5_run() {   # $1=daemon $2=mode (inject|m4mut|horizon|sigterm) → "rc=<exit>|err=<the ERROR line>"
    local d="$1" mode="$2" drv cut lg ck pid rc
    drv=$(mktemp "$WORK/m5drv.XXXXXX"); lg=$(mktemp "$WORK/m5log.XXXXXX"); ck=$(mktemp "$WORK/m5clk.XXXXXX")
    cut=$(seam_cut "$d") || { echo "rc=CUT-FAILED"; return; }
    {
        echo 'set +e'
        echo "T0=$T0; HEAD0=$HEAD0; CLK='$ck'; LOG='$lg'; MODE='$mode'"
        echo 'echo "$T0" > "$CLK"'
        echo "source '$cut'"
        cat <<'M5STUBS'
_now() { local x; read -r x < "$CLK"; echo "$x"; }
_adv() { local x; read -r x < "$CLK"; echo $(( x + $1 )) > "$CLK"; }
mono_now() { _now; }
date() { if [[ "$1" == "+%s" ]]; then _now; return 0; fi; command date "$@"; }
log() { :; }; log_info() { echo "INFO $*" >> "$LOG"; }; log_warn() { :; }; log_error() { echo "ERROR $*" >> "$LOG"; }
alert() { :; }; alert_warn() { :; }; alert_info() { :; }; send_telegram() { :; }; send_webhook() { :; }
rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _fence_rot_check() { :; }
flush_pending_alerts() { :; }; save_state() { :; }; _sd_notify() { :; }
get_local_identity() { echo U1; }
STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1; VOTE_PUBKEY=V1; PRIMARY_UNSTAKED_PUBKEY=""
LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
TAKEOVER_DELAY=60; TAKEOVER_COOLDOWN=120; MAX_DELINQUENT_SLOTS=0; DRY_RUN=false; GOSSIP_VERIFY=false
VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_MIN_INTERVAL=10; CHECK_INTERVAL=5; TURBO_INTERVAL=1; _current_interval=5
HEARTBEAT_INTERVAL=999999; _last_heartbeat=$T0; TAKEOVER_STARVATION_ALERT_SECS=0; SOLANA_PATH=/nonexistent
unset NOTIFY_SOCKET WATCHDOG_USEC
_slot() { echo $(( HEAD0 + $1 * 5 / 2 )); }
curl() {   # the splicer world; lastVote as the string "0009999" in m4mut mode
    local url="" d="" t lv
    while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac; done
    t=$(( $(_now) - T0 )); lv=$(_slot 0); [[ "$MODE" == "m4mut" ]] && lv='"0009999"'
    case "$url|$d" in
        "$LOCAL_RPC|"*getHealth*) printf '{"jsonrpc":"2.0","result":"ok","id":1}' ;;
        "$LOCAL_RPC|"*getSlot*) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(( $(_slot "$t") - 32 ))" ;;
        "$LOCAL_RPC|"*getVoteAccounts*) printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]},"id":1}' "$(( $(_slot "$t") - 33 ))" "$(_slot 0)" ;;
        *"|"*getVoteAccounts*) printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]},"id":1}' "$(( $(_slot "$t") - 1 ))" "$lv" ;;
        *"|"*getSlot*) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(_slot "$t")" ;;
        *) return 7 ;;
    esac
    return 0
}
timeout() { [[ "$1" == "-k" ]] && shift 2; shift; case "$*" in *set-identity*|*authorized-voter*) return 0 ;; esac; "$@"; }
if [[ "$MODE" == "inject" ]]; then
    display_status() { local x=0009999; [[ $(( x - 1 )) -gt 0 ]]; }   # M4's class of expansion error, injected inside the loop
else
    display_status() { :; }
fi
[[ "$MODE" == "m4mut" ]] && _canon_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }   # the M4 MUTANT: the ONE validator reverted to the pre-fix shape
sleep() {
    if [[ "$MODE" == "sigterm" ]]; then command sleep 0.2; return 0; fi
    _adv "${1%%.*}"; [[ $(( $(_now) - T0 )) -ge 200 ]] && _running=false; return 0
}
_running=true
M5STUBS
        sed -n '/^while \$_running; do/,$p' "$d"
    } > "$drv"
    if [[ "$mode" == "sigterm" ]]; then
        "$BASH" "$drv" >/dev/null 2>&1 &
        pid=$!
        command sleep 1.5; kill -TERM "$pid" 2>/dev/null; wait "$pid"; rc=$?
    else
        "$BASH" "$drv" >/dev/null 2>&1; rc=$?
    fi
    echo "rc=$rc|err=$(grep -m1 '^ERROR Main loop ABORTED' "$lg" | cut -c1-90)|exited=$(grep -c 'Main loop exited' "$lg")|shutdown=$(grep -c 'Shutdown signal received' "$lg")"
}
m5_ok=1; m5_rows=""
for dd in "$STANDBY" "$PRIMARY"; do
    ri=$(m5_run "$dd" inject); rh=$(m5_run "$dd" horizon); rs=$(m5_run "$dd" sigterm)
    if [[ "$(field "$ri" rc)" == "1" && "$(field "$ri" err)" == "ERROR Main loop ABORTED without a shutdown request"* && "$(field "$ri" exited)" == "0" ]] \
       && [[ "$(field "$rh" rc)" == "0" && "$(field "$rh" exited)" == "1" && "$(field "$rs" rc)" == "0" && "$(field "$rs" shutdown)" == "1" ]]; then
        m5_rows="$m5_rows $(basename "$dd" .sh):abort→1,horizon→0,SIGTERM→0"
    else
        m5_ok=0; bad "(12e) $(basename "$dd"): inject=$ri :: horizon=$rh :: sigterm=$rs"
    fi
done
rm4=$(m5_run "$STANDBY" m4mut)
if [[ $m5_ok -eq 1 && "$(field "$rm4" rc)" == "1" && "$(field "$rm4" err)" == "ERROR Main loop ABORTED"* ]]; then
    ok "(12e) M5 — the REAL loop + tail run as a script file:$m5_rows; the M4 MUTANT (the validator reverted to ^[0-9]+\$) with TIER2 serving \"0009999\" aborts the standby loop through the real input path → exit 1 with the ERROR line (armed: Restart=no, OnFailure on 'failed' → the fence/page fires; v0.6.x Restart=always restarts it either way). Pre-fix: every abort fell through to 'Main loop exited.' → exit 0"
else
    [[ $m5_ok -eq 1 ]] && bad "(12e) m4-mutant: $rm4"
fi

# (12f) M6 (INT-2/CC-6a) — the MEASURED gap between consecutive pets, house bound-counting (every read at its
# full -m bound, every pet 7 s, T2 failing), the take held on the cooldown so watchdog-elapsed evaluates.
# Pre-fix red: 20 s at MAX_DELINQUENT_SLOTS 0 and 15 (getSlot curl -m 3 unpetted + the next T2 read + a pet).
mutate "$STANDBY" '/per-op pet after THIS read too/,/^        _watchdog_pet$/{/^        _watchdog_pet$/d;}' "$WORK/no-t1pet.sh"
mutate "$STANDBY" '/^        _watchdog_pet   # v0.7 (Block 6.3 fix round, M6.s class/d' "$WORK/no-mdspet.sh"
rf0=$(ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=0 HORIZON=900 world | tail -1)
# at MAX_DELINQUENT_SLOTS=15 the MDS getSlot runs only while the holder is not yet delinquent-LISTED, so that
# world keeps the holder alive and lagging (each vote 20 slots behind the head; honest tiers): the MDS read
# then precedes the pin's prefetch sampler read in the episode's first take-path cycle
rf15=$(ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=15 TIERMODE=honest RESUME=0 HLAGS=20 HORIZON=900 world | tail -1)
rfc0=$(WSCRIPT="$WORK/no-t1pet.sh" ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=0 HORIZON=900 world | tail -1)
rfc15=$(WSCRIPT="$WORK/no-mdspet.sh" ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=15 TIERMODE=honest RESUME=0 HLAGS=20 HORIZON=900 world | tail -1)
if [[ "$(field "$rf0" petgap)" == "17" && "$(field "$rf15" petgap)" == "17" && "$(field "$rf0" elag_from)" != "none" ]] \
   && [[ "$(field "$rfc0" petgap)" == "20" && "$(field "$rfc15" petgap)" == "20" ]]; then
    ok "(12f) M6 — MEASURED max gap between consecutive pets through the armed standby loop (watchdog-elapsed evaluating; T2 failing; every read at its full -m bound; every pet 7 s): 17 s at MAX_DELINQUENT_SLOTS 0 and at 15 = one op + one pet < WatchdogSec 30; CONTROLS: the Tier-1 getSlot pet removed → 20 s at 0; the MDS getSlot pet removed → 20 s at 15 — each pet is load-bearing (N-is-all). Pre-fix: 20 s at both"
else
    bad "(12f) mds0=$rf0 :: mds15=$rf15 :: no-t1pet@0=$rfc0 :: no-mdspet@15=$rfc15"
fi

# (12g) M8 (INT-5) — paired while the monitor runs: the status line says so, loudly. Pre-fix red: silent.
case_m8() {
    _proof_startup_check >/dev/null 2>&1
    local reg0="$_elapsed_registered"
    printf '%s\n' "$(mk_token "${PG:-7}" "${PW:-30}" "${PB:-60}" real holder1)" > "$PROOF_STATE_DIR/pairing-token"
    WARNCT=0; LASTWARN=""; INFOCT=0; LASTINFO=""
    _proof_status_line
    echo "reg0=$reg0|reg=$_elapsed_registered|w=$LASTWARN|wn=$WARNCT|in=$INFOCT"
}
r1=$(TOK=none drive_ep "$STANDBY" case_m8 | tail -1)
r2=$(TOK=none PG=9 PW=10 PB=20 drive_ep "$STANDBY" case_m8 | tail -1)
r3=$(TOK=ok drive_ep "$STANDBY" case_m8 | tail -1)
if [[ "$(field "$r1" reg0)" == "0" && "$(field "$r1" reg)" == "0" && "$(field "$r1" wn)" == "1" && "$(field "$r1" in)" == "0" ]] \
   && [[ "$(field "$r1" w)" == "[proof-gate] paired (token gen=7), but watchdog-elapsed is NOT registered — restart the monitor to register (registration runs at startup only; proof providers registered now: NONE)" ]] \
   && [[ "$(field "$r2" wn)" == "1" && "$(field "$r2" w)" == *"paired token present (gen=9), but watchdog-elapsed is NOT registered and would not register: "*"SHORTER than the un-armed timer path"* ]] \
   && [[ "$(field "$r3" reg)" == "1" && "$(field "$r3" wn)" == "0" && "$(field "$r3" in)" == "0" ]]; then
    ok "(12g) M8 — an armed spare started UNPAIRED and paired while its monitor runs (no lazy registration in this build): the heartbeat status line WARNS 'paired (token gen=7), but watchdog-elapsed is NOT registered — restart the monitor to register (… registered now: NONE)'; a planted short-floor token is named instead ('would not register: … SHORTER than the un-armed timer path'); a spare registered at startup stays silent. Pre-fix: the unpaired line went quiet and NOTHING replaced it"
else
    bad "(12g) late-pair=$r1 :: late-lowfloor=$r2 :: registered=$r3"
fi

# (12h) N2 (CC-6c) — what [elapsed-blind] means, measured: "no STAMPED blindness since the start". Blindness
# is stamped only where the take path TRIED to observe (a take-path cycle); an outage wholly inside the
# delay — where the take path attempts no read — is not stamped, and the silence clock runs through it
# (lastVote's on-chain monotonicity and the final same-vantage, head-checked read cover such stretches).
rh1=$(DOWNFROM=80 DOWNTO=120 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
rh2=$(DOWNFROM=100 DOWNTO=150 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
rh3=$(DOWNFROM=140 DOWNTO=170 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
if [[ "$(field "$rh1" emint)" == "171" && "$(field "$rh2" emint)" == "250" && "$(field "$rh3" emint)" == "270" ]]; then
    ok "(12h) N2 — both tiers down t80–t120 (inside the delay: no observation attempted, nothing stamped) → the mint is unchanged at t171 (the clock ran through 40 s of UNSTAMPED blindness); outages overlapping take-path cycles (t100–t150, t140–t170) are stamped and restart it → mint at t250 / t270 (the outage's end + the 100 s floor). [elapsed-blind] = no STAMPED blindness since the start (region comment + docs/SAFETY.md)"
else
    bad "(12h) inside-delay=$rh1 :: overlap1=$rh2 :: overlap2=$rh3"
fi

rm -rf "$WORK"
results_banner
