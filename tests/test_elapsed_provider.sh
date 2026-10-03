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
#        validator's boundary table; 6.3 fix round 2 (R4): (3l-R4a–c) the adoption keyed on the FULL
#        token — a same-gen re-pair with a lower floor, a reporter-only flap (restored in place and by
#        tmp+mv), a same-gen token from another host under a dormant verdict; 6.3 fix round 4 (W3):
#        a SYMLINKED token never proves — target rewrites and a link re-pointed away and back all answer
#        cannot and the gate refuses (3l-R4b), and the posture/status lines say why (3l-R4d); 6.3 fix round 5
#        (R-SYM): a token whose DIRECTORY does not canonicalize to itself (PROOF_STATE_DIR reached through a
#        symlink) never proves either — the directory re-pointed away and back, or never moved: cannot on
#        the step, the startup posture and the status line (3l-R5a/b); the canonical-path control proves
#        as before, and a directory's contents swapped between two steps (a rename, a transient symlink, a
#        mount) is a DOCUMENTED RESIDUAL
#   (4)  the head reference: commitment=processed read from the live request log; the head is read
#        AFTER the payload (live order); the default-commitment mutant is wrong BOTH ways (a live
#        view permanently blind AND a 40-slot lagged view accepted)
#   (5)  D3 MULTILAYER (mandatory): (5a)–(5d) the SEAM-REGRESSION defense line — the old forged-silence
#        archetype (a seam state the current writers cannot produce) vs each single neuter, the
#        progressive chain, and ALL the step layers neutered → forged PROVEN; (5e)–(5h) the REACHABLE
#        post-blindness state (the real _note_blind_cycle, then an evaluation before re-observation):
#        [elapsed-blind] and [elapsed-seam] each neutered alone → the other refuses; both → [elapsed-
#        floor]'s serve-time half withdraws; all three → the forged acceptance at the GATE reappears;
#        (5i)–(5k) the GAP ARCHETYPE (6.3 fix round 2, R3): a lagging bank hidden by a 12 s payload→head
#        gap → [elapsed-gap] refuses; neutered alone → the forged acceptance at the gate reappears (its
#        own neuter control), [elapsed-head] the named survivor past the hidden amount; the in-sync
#        control blind either way; 6.3.1 (Block 6.3.1, D2/D4): [elapsed-rate] and [elapsed-own] join the
#        layer set, the single-neuter census and the all-neutered control, and each is load-bearing on its
#        own archetype with its own neuter control — (5m)/(5n) [elapsed-own] (the step and the serve
#        half), (5o) [elapsed-rate] (2.0 / 2.5 / 2.53 / 4.0 slots/s, no samples, a late anchor); on the
#        reachable state [elapsed-rate] is a new named survivor (5e-rate)
#   (6)  COUPLING [pre-registration (b)]: MARGIN_ELAPSED 10→20 moves the floor AND N_HEAD and the
#        provider's behavior follows (measured both ways); a decoupled static-N_HEAD control
#   (7)  inertness census: un-armed / holder / unpaired → zero events; the armor-forced control leaks
#   (8)  boundedness + pets: live event order + the static region census (N-is-all, both censuses)
#   (9)  constants: the region assigns none of the seven derived names; the N_HEAD condition comment
#        still sits at the derivation site in both daemons
#   (10) twins + call sites: [elapsed-provider] byte-identical; [proof-gate] and [g2-provider] still
#        identical; call-site census per daemon
#   (11) D0 — the executed input map, on the REAL standby main loop (a FILE-BACKED clock since the 6.3
#        fix round, so reads take time; the slot rate an explicit knob): the per-cycle own-bank entry
#        gate and the take cycle's read order, with the shipped gossip advisory too; the timing race
#        incl. the REAL provider under the 6.4 emulation, and re-measured at the MEASURED mainnet rate
#        (3.7 slots/s — (11b-rate)); the intermittent holder; the partitioned spare — fully cut off,
#        on a minority fork (the vote bank frozen within ~8 votes) with and without the
#        supermajority's gossip — and the lagging spare, armed and not; then the 6.3 DOCUMENTED
#        RESIDUALS (11i)–(11n): partitioned after the pin together with co-frozen tiers, the latency
#        term Σ, an honest lagging tier, the armed intermittent holder, LOCAL_HEALTH_MAX_BEHIND > 128,
#        forged G2 on shared vantages — each a MEASURED fact that docs/SAFETY.md states, so the text
#        cannot drift from the mechanism silently. Block 6.3.1 (the own-view hardening) landed the
#        remedies they named: (11a)–(11e) and (11i)–(11n) now assert the FLIPPED behavior, measured,
#        each quoting the 6.3-build number it replaces; what is left is measured where it lives — the
#        spare's own replay lag (11h), the veto's own pet on an armed unit (11j-Σ), and the exposure
#        below OWN_HEAD_H (test_own_view (4b-residual)). The armed rows whose mechanism is the silence
#        clock run with [elapsed-rate] neutered (at the world's 2.5 slots/s it abstains on every one of
#        them), each labelled, with the SHIPPED provider pinned beside each at a certified rate — 3.7
#        slots/s, where the rate layer passes and the layer under test decides (6.3.1 fix round 1, the
#        panel's T9: (11j), (12h) and (13a) had no shipped twin; (12d)'s loop-level no-mint was the rate
#        layer's abstention at 2.5, so it now runs at 3.7 with the M4-removed control)
#   (12) the 6.3 fix round's mechanism reds, re-run green: M2 (post-read silence starts — the F2
#        world), M3 → R1 (observed_at is the EVALUATION START again — fix round 2 reverted M3; the tail
#        census, measured: (12c)/(12c-tail)), M4 (non-canonical input through the REAL loop), M5 (an
#        aborted loop exits non-zero; SIGTERM still 0), M6 (the MEASURED inter-pet gap), M8 (the
#        paired-but-unregistered status line), N2 (only a STAMPED blindness restarts the silence clock
#        — (12h))
#   (13) 6.3 fix round 2's reds, re-run green: R1 through the REAL loop (the degraded-tier and W1 worlds
#        equal de21927 take-for-take), R2 (the own-bank MAX_DELINQUENT_SLOTS reference read FIRST; the
#        TIER2 census twin re-reads; the live-holder PETS=7 world), R3 (the head gap on the REAL loop),
#        R7 (M2 binds the span floor — later only), R8 (the cadence residual, DOCUMENTED — flips when the
#        episode-close rule becomes time-based)
#
# MUTATION COVERAGE (HARNESS.md discipline), all via mutate() (loud on no-op): the step layers of (5)
# alone and chained, [elapsed-seam] (5f), [elapsed-gap] (5j), [elapsed-own] (5m/5n), [elapsed-rate] (5o, and
# neutered where it would mask a silence-clock row: (11c)(11i)(11j)(11l)(12a)(12h)(13a)), the head compare boundary (3b-ctl), the head commitment
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
# 6.3 fix round 5 (R-SYM): the provider refuses a token whose directory does not canonicalize to itself, so
# every PROOF_STATE_DIR below is built on the RESOLVED path, as an operator's must be (macOS TMPDIR lies
# under /var → /private/var and ends in '/'; Linux /tmp is already canonical). (3l-R5) builds the
# non-canonical cases on purpose.
WORK=$(cd -P -- "$WORK" && pwd -P)
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
            comm=default; case "$d" in *'"commitment":"processed"'*) comm=processed ;; *'"commitment":"confirmed"'*) comm=confirmed ;; esac
            echo "read $src $m comm=$comm" >> "$EV"
            if [[ "$src" == "LOCAL" && "$m" == "slot" ]]; then
                [[ "$LOCAL_DOWN" == "1" ]] && return 7
                # fix round 2 (S2): the split read in _elapsed_step takes an [own-view] own-head sample (getSlot at
                # confirmed) between a TIER2 failure and TIER3 — it answers from the SYNTHETIC ring's own head (below),
                # so the one ring the rate layer reads stays one chain
                if [[ "$comm" == "confirmed" ]]; then printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(_ep_own_slot "$(mono_now)")"; return 0; fi
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
        # 6.3.1 (D4 e): [elapsed-rate] reads the [own-view] own-head ring (this spare's CONFIRMED head at two
        # TIMES), which only the main loop's _own_head_sample fills. The unit drive stands in for it with a
        # SYNTHETIC ring, written before every step — no read, no pet, so every read/pet census below is
        # untouched: one sample at each candidate silence start the step can compute (observed_since,
        # blind_until, the token adoption — the step's own adoption included — and the own-bank stamp) and
        # one at the step's instant, the confirmed head advancing at OWNRATE_NUM/OWNRATE_DEN slots/s
        # (default 4/1 — healthy and provably >= 2.5; 5/2 = exactly the assumed rate, which the abstaining
        # bound never certifies on a SMOOTH head — a hold at the anchor sample can: docs/SAFETY.md 'Slot
        # time'). OWNRING=off: no ring at all (the RATE UNPROVEN path). (12)/(13) drive
        # the REAL sampler through the REAL loop instead (world()).
        eval "$(declare -f _elapsed_step | sed '1s/_elapsed_step/_real_elapsed_step/')"
        _ep_own_slot() { echo $(( HEAD0 + ( $1 - T0 ) * ${OWNRATE_NUM:-4} / ${OWNRATE_DEN:-1} )); }
        _ep_own_ring() {
            local _n _c _cs="" _x _ring="" _fr
            _n=$(mono_now)
            [[ "${OWNRING:-on}" == "off" ]] && { _own_head_ring=""; return 0; }
            if [[ "${OWNRING:-on}" == "late" ]]; then   # only the last 20 s sampled: the anchor comes late (RATE SPAN SHORT)
                _own_head_ring="$(( _n - 20 )):$(( _n - 20 )):$(_ep_own_slot $(( _n - 20 ))) ${_n}:${_n}:$(_ep_own_slot "$_n")"; return 0
            fi
            _fr=$(dump_freshness)   # the freshness triple through its SOLE reader (run_all (3)), never a private dereference
            for _c in "$(field "$_fr" observed_since)" "$(field "$_fr" blind_until)" "${_elapsed_tok_since:-0}" "${_own_bank_active_time:-0}" "$_n"; do
                case "$_c" in ''|*[!0-9]*) continue ;; esac
                [[ $_c -ge $T0 && $_c -le $_n ]] && _cs="$_cs $_c"
            done
            for _x in $(printf '%s\n' $_cs | sort -n | uniq); do _ring="${_ring:+$_ring }${_x}:${_x}:$(_ep_own_slot "$_x")"; done
            _own_head_ring="$_ring"
        }
        _elapsed_step() { _ep_own_ring; _real_elapsed_step "$@"; }
        "$fn"
    )
}
reads_of() { grep -c '^read' "$1"; }

# a FILE-backed mono clock for ONE drive_ep case: T2/T3/LOCAL reads (and pets) then TAKE time inside $()
fileclock_on() {
    CLKF=$(mktemp "$WORK/clk.XXXXXX"); echo "$_SIM_NOW" > "$CLKF"
    mono_now() { local x; read -r x < "$CLKF"; echo "$x"; }
    _clk_adv() { local x; read -r x < "$CLKF"; echo $(( x + $1 )) > "$CLKF"; }
    eval "$(declare -f curl | sed '1s/^curl/_ep_curl/')"
    curl() {   # T2_DOWN/T3_DOWN: a timeout AT the -m bound; LAT_T3 / LAT_LOCAL: the answer that many s late
        # LAT_OHS (fix round 2, S2): the [own-view] own-head sample's LOCAL read (the one getSlot at confirmed
        # here) its own latency — default LAT_LOCAL; a row that puts the head read at ITS -m 5 bound puts the
        # sample at ITS -m 2 bound
        local args=("$@") i=0 mt=10 url="" ohs=0
        while [[ $i -lt ${#args[@]} ]]; do
            case "${args[$i]}" in -m) mt="${args[$((i+1))]}" ;; http*) url="${args[$i]}" ;; *'"commitment":"confirmed"'*) ohs=1 ;; esac
            i=$((i+1))
        done
        case "$url" in
            "$TIER2_RPC") [[ "$T2_DOWN" == "1" ]] && _clk_adv "$mt" ;;
            "$TIER3_RPC") if [[ "$T3_DOWN" == "1" ]]; then _clk_adv "$mt"; else _clk_adv "${LAT_T3:-0}"; fi ;;
            "$LOCAL_RPC") if [[ $ohs -eq 1 ]]; then _clk_adv "${LAT_OHS:-${LAT_LOCAL:-0}}"; else _clk_adv "${LAT_LOCAL:-0}"; fi ;;
        esac
        _ep_curl "$@"
    }
    _watchdog_pet() {   # PETSEQF: a FILE of per-pet costs consumed in order (the sampler pets inside $() — a variable would not carry back), then PETCOST
        echo "pet" >> "$EV"
        local c="${PETCOST:-0}"
        if [[ -n "${PETSEQF:-}" && -s "$PETSEQF" ]]; then read -r c < "$PETSEQF"; tail -n +2 "$PETSEQF" > "$PETSEQF.n"; mv "$PETSEQF.n" "$PETSEQF"; fi
        _clk_adv "$c"
    }
}

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
   && [[ "$(field "$r" info)" == *"registered: watchdog-elapsed — token gen=7 (watchdog=30s, relinquish_bound=60s, fence=real) → floor 100s of observed silence (W+B+MARGIN_ELAPSED = 30+60+10), head cross-check ±22 slots against this spare's own bank (LOCAL_RPC getSlot, commitment=processed)"* ]]; then
    ok "(1a) armed spare + valid fence=real token → registered, ONE info line printing the MEASURED derivation (gen 7, W 30 + B 60 + MARGIN 10 = floor 100 s, N_HEAD 22 = (MARGIN − 1) × 5/2 since 6.3.1 — τ budgeted, 25 before — the head's source and commitment) — values read from the ONE derivation site"
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
r=$(LAGS="21 22 23 40" drive_ep "$STANDBY" case_lag | tail -1)
if [[ "$(field "$r" probes)" == "21:yes 22:yes 23:blind 40:blind" && "$(field "$r" reason)" == *"LAGGED VIEW: the liveness payload's cluster-max lastVote $(( HEAD0 - 40 )) is 40 slots behind this spare's own head ${HEAD0}; REQUIRED: <= N_HEAD=22"* ]]; then
    ok "(3a) lagged fleet: view 21/22 slots behind this spare's bank → PROVEN (22 = N_HEAD since 6.3.1, inclusive), 23/40 → BLIND with the MEASURED lag — a lagged-but-answering fleet reads blind (wait), never frozen"
else
    bad "(3a) $r"
fi
r=$(LAGS="-22 -23 -90" drive_ep "$STANDBY" case_lag | tail -1)
if [[ "$(field "$r" probes)" == "-22:yes -23:blind -90:blind" && "$(field "$r" reason)" == *"STALE REFERENCE: this spare's own head ${HEAD0} is 90 slots behind the live payload's cluster-max $(( HEAD0 + 90 ))"* ]]; then
    ok "(3b) stale reference: this spare's own bank 22 slots behind the live view → PROVEN (inclusive), 23/90 behind → BLIND naming the stale reference — a lagging or cut-off bank cannot certify a view's freshness (the two-sided 'within')"
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
if [[ "$(field "$r" a)" == "blind" && "$(field "$r" r)" == *"yielded no usable sample"* && "$(field "$r" same)" == "1" && "$(field "$r" reads)" == "3" && "$(field "$r" pets)" == "3" ]]; then
    ok "(3f) the provider's own read unusable (T2 and T3 both down: the two bounded tier reads and, since fix round 2 (S2), an own-head sample between the TIER2 failure and TIER3 — 3 reads, 3 pets) → blind, proves nothing, and the seam is UNTOUCHED (dump_freshness identical before/after): the region writes nothing — no head read after a failed payload"
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

# (3l-R4) 6.3 fix round 2, R4 (FX-3): N4's adoption is keyed on the FULL token — its classified line AND the
# stored file's identity (inode, size, change time) — not on gen. Pre-fix red (f22d492): (a) a same-gen
# re-pair with a LOWER floor (gen 7 W30/B120 floor 160 → gen 7 W30/B60 floor 100 at +121) PROVEN at +121
# with since=+0, gate rc 0 — and the same from another host; (b) a flap seen ONLY by the reporter (the
# token garbage at +61, the same bytes restored before the next step) kept the old adoption: PROVEN at
# +100 on silence counted across the flap; (c) a same-gen token from another host with the same bounds
# swapped in under a DORMANT verdict: served proven=yes, gate rc 0.
# 6.3 fix round 3, S3 (P3-R4-1) keyed a symlinked token's TARGET (stat -L) — red on e917c04: a target flap
# PROVEN at +100 (the ident keyed the link). 6.3 fix round 4, W3 (P4-S3-REPOINT): that made a link
# re-pointed AWAY and BACK invisible at any spacing (red on 7ab7eca: PROVEN at +100, gate rc 0) — no single
# file identity sees both, so a symlinked token now answers cannot, loudly, in every mode.
case_samegen() {   # HOST2: the re-pair's host (default holder1)
    printf '%s\n' "$(mk_token 7 30 120 real holder1)" > "$PROOF_STATE_DIR/pairing-token"   # floor 160
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 120 )); _elapsed_step; local a1="$_elapsed_answer"
    printf '%s\n' "$(mk_token 7 30 60 real "${HOST2:-holder1}")" > "$PROOF_STATE_DIR/pairing-token"   # the SAME gen, floor 100
    _SIM_NOW=$(( T0 + 121 )); _elapsed_step; local a2="$_elapsed_answer" r2="$_elapsed_reason" i2="$LASTINFO"
    require_relinquish_proof; local g2=$?
    _SIM_NOW=$(( T0 + 220 )); _elapsed_step; local a3="$_elapsed_answer" r3="$_elapsed_reason"
    _SIM_NOW=$(( T0 + 221 )); _elapsed_step; local a4="$_elapsed_answer"
    local v; v=$(_elapsed_provider)
    echo "a1=$a1|a2=$a2|r2=$r2|i2=$i2|g2=$g2|a3=$a3|r3=$r3|a4=$a4|oid=$(_proof_field "$v" observation_id)"
}
sg_ok=1
for h in holder1 otherholder; do
    r=$(HOST2=$h drive_ep "$STANDBY" case_samegen | tail -1)
    if [[ "$(field "$r" a1)" == "no" && "$(field "$r" a2)" == "no" && "$(field "$r" r2)" == *"the token now in force (gen 7) was adopted 0s ago"* && "$(field "$r" i2)" == *"token gen=7 adopted at mono $(( T0 + 121 ))"* && "$(field "$r" g2)" == "1" ]] \
       && [[ "$(field "$r" a3)" == "no" && "$(field "$r" r3)" == *"adopted 99s ago"* && "$(field "$r" a4)" == "yes" && "$(field "$r" oid)" == "elapsed:gen=7:since=$(( T0 + 121 )):floor=100" ]]; then :; else sg_ok=0; bad "(3l-R4a) host=$h: $r"; fi
done
[[ $sg_ok -eq 1 ]] && ok "(3l-R4a) R4 — a SAME-GEN re-pair with a lower floor (gen 7 floor 160 → gen 7 floor 100 at +121, from the same host and from another) is a NEW adoption: no at +121 ('adopted 0s ago', gate rc 1) and at +220 ('99s ago'), PROVEN only at +221 with since=+121. Pre-fix: PROVEN at +121 with since=+0, gate rc 0 (the adoption was keyed on gen)"
case_flap() {   # MODE=inplace|mv — how the restore is written: in place (the same inode, a new change time) or tmp+mv (a new inode — the ceremony's own atomic write); symlink|symlink-mv — the stored token is a SYMLINK and the flap rewrites its TARGET, in place / by tmp+mv (fix round 3, S3); repoint — the stored token is a SYMLINK re-pointed AWAY (to a garbage file) and BACK, the target never written (fix round 4, W3 — P4-S3-REPOINT)
    local tf="$PROOF_STATE_DIR/pairing-token" good
    if [[ "${MODE:-inplace}" == symlink* || "${MODE:-inplace}" == repoint ]]; then
        mv "$tf" "$PROOF_STATE_DIR/token-target"; ln -s token-target "$tf"
        [[ "${MODE:-inplace}" == symlink* ]] && tf="$PROOF_STATE_DIR/token-target"
    fi
    reg; prime_seam 0 none
    good=$(cat "$tf")
    _SIM_NOW=$(( T0 + 60 )); _elapsed_step; local a60="$_elapsed_answer"
    if [[ "${MODE:-inplace}" == repoint ]]; then printf 'garbage\n' > "$PROOF_STATE_DIR/token-rotten"; ln -sfn token-rotten "$tf"; else printf 'garbage\n' > "$tf"; fi
    _SIM_NOW=$(( T0 + 61 )); local v1; v1=$(_elapsed_provider)            # ONLY the reporter (inside the gate's $()) sees the rot
    if [[ "${MODE:-inplace}" == repoint ]]; then ln -sfn token-target "$tf"
    elif [[ "${MODE:-inplace}" == *mv ]]; then printf '%s\n' "$good" > "$tf.tmp"; mv "$tf.tmp" "$tf"; else printf '%s\n' "$good" > "$tf"; fi
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step; local a100="$_elapsed_answer" r100="$_elapsed_reason"
    _SIM_NOW=$(( T0 + 199 )); _elapsed_step; local a199="$_elapsed_answer"
    _SIM_NOW=$(( T0 + 200 )); _elapsed_step; local a200="$_elapsed_answer" r200="$_elapsed_reason"
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local g200=$?
    echo "a60=$a60|rep61=$(_proof_field "$v1" proven)|a100=$a100|r100=$r100|a199=$a199|a200=$a200|r200=$r200|g200=$g200|oid=$(_proof_field "$v" observation_id)"
}
fl_ok=1; SYMWHY="the pairing token is a symlink — store it as a regular file, as \`failover arm\` does"
for m in inplace mv; do
    r=$(MODE=$m drive_ep "$STANDBY" case_flap | tail -1)
    if [[ "$(field "$r" a60)" == "no" && "$(field "$r" rep61)" == "no" && "$(field "$r" a100)" == "no" && "$(field "$r" r100)" == *"the token now in force (gen 7) was adopted 0s ago (mono $(( T0 + 100 )))"* ]] \
       && [[ "$(field "$r" a199)" == "no" && "$(field "$r" a200)" == "yes" && "$(field "$r" g200)" == "0" && "$(field "$r" oid)" == "elapsed:gen=7:since=$(( T0 + 100 )):floor=100" ]]; then :; else fl_ok=0; bad "(3l-R4b) restore=$m: $r"; fi
done
for sc in "$STANDBY"; do   # the spare posture: on the PRIMARY the provider never registers (_proof_role_is_spare) — its byte-identical copy is held by (10)
    for m in symlink symlink-mv repoint; do
        r=$(MODE=$m drive_ep "$sc" case_flap | tail -1)
        if [[ "$(field "$r" a60)" == "cannot" && "$(field "$r" rep61)" == "cannot" && "$(field "$r" a100)" == "cannot" && "$(field "$r" r100)" == "$SYMWHY"* ]] \
           && [[ "$(field "$r" a199)" == "cannot" && "$(field "$r" a200)" == "cannot" && "$(field "$r" r200)" == "$SYMWHY"* && "$(field "$r" g200)" == "1" && -z "$(field "$r" oid)" ]]; then :; else fl_ok=0; bad "(3l-R4b) $(basename "$sc") symlinked token, mode=$m: $r"; fi
    done
done
[[ $fl_ok -eq 1 ]] && ok "(3l-R4b) R4 — a token flap seen ONLY by the reporter (garbage at +61 inside the gate's \$(), the SAME bytes restored before the next step — in place, and by tmp+mv) is a NEW adoption at the next step: no at +100 ('adopted 0s ago (mono +100)') and +199, PROVEN only at +200 with since=+100, gate rc 0 — the reporter cannot clear anything from its subshell, so the key carries the stored file's identity and the rewrite counts. Fix round 4 (W3 — P4-S3-REPOINT): a SYMLINKED token never proves — its target rewritten in place / by tmp+mv, or the link re-pointed AWAY and BACK with the target never written: cannot at +60 (the reporter at +61 too), +100, +199 and +200 ('$SYMWHY'), no verdict, the gate refuses (rc 1) — on the spare posture (the PRIMARY's copy of the region is byte-identical, (10); the provider never registers there). Pre-fix: f22d492 PROVEN at +100 in every mode; e917c04 PROVEN at +100 in the target-rewrite modes (its stat keyed the link); 7ab7eca PROVEN at +100 in the re-point mode (its stat -L keyed the target, so the re-point was invisible) and at +200 in the target-rewrite modes"
# (3l-R4d) fix round 4, W3: the posture/status surface says WHY the registered provider cannot prove —
# the startup PAIRED posture and the every-interval status line name the symlink; the regular-file
# control prints neither.
case_symposture() {   # SYM=1: the stored token is a symlink to a valid token file
    if [[ "${SYM:-0}" == "1" ]]; then mv "$PROOF_STATE_DIR/pairing-token" "$PROOF_STATE_DIR/token-target"; ln -s token-target "$PROOF_STATE_DIR/pairing-token"; fi
    WARNCT=0; LASTWARN=""
    _proof_startup_check
    local w1="$LASTWARN" n1=$WARNCT
    WARNCT=0; LASTWARN=""
    _proof_status_line
    echo "reg=$_elapsed_registered|w1=$w1|n1=$n1|w2=$LASTWARN|n2=$WARNCT"
}
sp_ok=1
for sc in "$STANDBY"; do   # the spare posture (see (3l-R4b))
    r=$(SYM=1 drive_ep "$sc" case_symposture | tail -1)
    [[ "$(field "$r" reg)" == "1" && "$(field "$r" n1)" == "1" && "$(field "$r" w1)" == *"armed spare PAIRED, but watchdog-elapsed CANNOT prove: $SYMWHY"* && "$(field "$r" n2)" == "1" && "$(field "$r" w2)" == *"paired (token gen=7), but watchdog-elapsed CANNOT prove: $SYMWHY"* ]] || { sp_ok=0; bad "(3l-R4d) $(basename "$sc") symlinked: $r"; }
    r=$(SYM=0 drive_ep "$sc" case_symposture | tail -1)
    [[ "$(field "$r" reg)" == "1" && "$(field "$r" n1)" == "0" && "$(field "$r" n2)" == "0" ]] || { sp_ok=0; bad "(3l-R4d) $(basename "$sc") regular-file control: $r"; }
done
[[ $sp_ok -eq 1 ]] && ok "(3l-R4d) W3 — with a symlinked token the registered spare says WHY watchdog-elapsed cannot prove, on both surfaces: the startup posture ('armed spare PAIRED, but watchdog-elapsed CANNOT prove: $SYMWHY …') and the every-interval status line ('paired (token gen=7), but watchdog-elapsed CANNOT prove: …'); a regular-file token prints neither (zero WARNs). Pre-fix: both silent — the PAIRED line alone"
# (3l-R5a) 6.3 fix round 5, R-SYM (P5T-ANCESTOR-SYMLINK): W3 refused a symlink only at the token path's
# FINAL component. A symlinked STATE DIRECTORY re-pointed away (to a garbage token's directory — no evaluation
# observes it: before a mint the reporter serves the cached step answer) and back before the next step is the same blindness one level
# up: the token file under it keeps its inode, size and change time, so the full key never changes. Pre-fix
# red (every earlier tree — de21927, f22d492, e917c04, 7ab7eca, 02c8e54, measured in fix round 5; the final
# panel found it on the last three): PROVEN at +100 with since=+0, gate rc 0 — and a symlinked directory
# that never moves proves like a canonical one. Now a token whose directory does not canonicalize to itself
# (cd -P / pwd -P of PROOF_STATE_DIR differs from PROOF_STATE_DIR as configured) answers cannot on every
# step, the reporter too, with the loud reason; the gate refuses. Controls: the canonical path proves at
# +100 exactly as before; and a directory's contents swapped away and back between two steps (here by RENAME;
# a transient symlink or a mount behave the same) — nothing canonicalizes differently at a step — still proves at +100 with since=+0 on every tree: a DOCUMENTED RESIDUAL (the
# token file's identity is all the key sees; flips if the key ever covers the directory's own identity — not
# this round).
case_dirflap() {   # DMODE=flap (a symlink re-pointed away and back) | static (a symlink that never moves) | rename (the real directory swapped by mv, away and back) | regular (the canonical path, no flap)
    local real="$PROOF_STATE_DIR" m="${DMODE:-flap}"
    mkdir -p "$real-B"; printf 'garbage\n' > "$real-B/pairing-token"
    if [[ "$m" == flap || "$m" == static ]]; then ln -s "$real" "$real-psd"; PROOF_STATE_DIR="$real-psd"; fi
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 60 )); _elapsed_step; local a60="$_elapsed_answer"
    case "$m" in
        flap)   ln -sfn "$real-B" "$real-psd" ;;
        rename) mv "$real" "$real-A"; mv "$real-B" "$real" ;;
    esac
    _SIM_NOW=$(( T0 + 61 )); local v1; v1=$(_elapsed_provider)            # ONLY the reporter (inside the gate's $()) sees it
    case "$m" in
        flap)   ln -sfn "$real" "$real-psd" ;;
        rename) mv "$real" "$real-B"; mv "$real-A" "$real" ;;
    esac
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step; local a100="$_elapsed_answer" r100="$_elapsed_reason"
    _SIM_NOW=$(( T0 + 199 )); _elapsed_step; local a199="$_elapsed_answer"
    _SIM_NOW=$(( T0 + 200 )); _elapsed_step; local a200="$_elapsed_answer" r200="$_elapsed_reason"
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local g200=$?
    echo "a60=$a60|rep61=$(_proof_field "$v1" proven)|rep61r=$(_proof_field "$v1" elapsed_reason)|a100=$a100|r100=$r100|a199=$a199|a200=$a200|r200=$r200|g200=$g200|oid=$(_proof_field "$v" observation_id)"
}
df_ok=1; DIRWHY="the pairing token's directory is reached through a symlink — point PROOF_STATE_DIR at the resolved path"
for m in flap static; do
    r=$(DMODE=$m drive_ep "$STANDBY" case_dirflap | tail -1)
    if [[ "$(field "$r" a60)" == "cannot" && "$(field "$r" rep61)" == "cannot" && "$(field "$r" rep61r)" == "$DIRWHY"* && "$(field "$r" a100)" == "cannot" && "$(field "$r" r100)" == "$DIRWHY"* ]] \
       && [[ "$(field "$r" a199)" == "cannot" && "$(field "$r" a200)" == "cannot" && "$(field "$r" r200)" == "$DIRWHY"* && "$(field "$r" g200)" == "1" && -z "$(field "$r" oid)" ]]; then :; else df_ok=0; bad "(3l-R5a) symlinked state directory, mode=$m: $r"; fi
done
for m in regular rename; do
    r=$(DMODE=$m drive_ep "$STANDBY" case_dirflap | tail -1)
    if [[ "$(field "$r" a60)" == "no" && "$(field "$r" rep61)" == "no" && "$(field "$r" a100)" == "yes" && "$(field "$r" a200)" == "yes" && "$(field "$r" g200)" == "0" && "$(field "$r" oid)" == "elapsed:gen=7:since=${T0}:floor=100" ]]; then :; else df_ok=0; bad "(3l-R5a) control/residual mode=$m: $r"; fi
done
[[ $df_ok -eq 1 ]] && ok "(3l-R5a) R-SYM — a token whose DIRECTORY is reached through a symlink never proves: PROOF_STATE_DIR a symlink to the real directory, re-pointed AWAY to a garbage token's directory (no evaluation observes it — before a mint the reporter serves the cached step answer) and BACK before +100, or never moved: cannot at +60 (the reporter at +61 too), +100, +199 and +200 ('$DIRWHY …'), no verdict, the gate refuses (rc 1) — the spare posture (the PRIMARY's copy is byte-identical, (10)). Controls, equal before and after: the canonical path proves at +100 (since=+0, re-minted at +200, gate rc 0); a directory's contents swapped away and back between two steps (here by RENAME) proves the same — DOCUMENTED RESIDUAL: the key sees the token file's identity only. Pre-fix (every earlier tree, de21927 through 02c8e54): the re-pointed and the static symlinked directory PROVEN at +100 with since=+0, gate rc 0"
# (3l-R5b) R-SYM on the posture/status surface: the SAME reason path as W3 — the startup PAIRED posture and
# the every-interval status line name the symlinked directory; the canonical-path control prints neither.
case_dirposture() {   # DSYM=1: PROOF_STATE_DIR is a symlink to the real directory (the token itself a regular file)
    if [[ "${DSYM:-0}" == "1" ]]; then ln -s "$PROOF_STATE_DIR" "$PROOF_STATE_DIR-psd"; PROOF_STATE_DIR="$PROOF_STATE_DIR-psd"; fi
    WARNCT=0; LASTWARN=""
    _proof_startup_check
    local w1="$LASTWARN" n1=$WARNCT
    WARNCT=0; LASTWARN=""
    _proof_status_line
    echo "reg=$_elapsed_registered|w1=$w1|n1=$n1|w2=$LASTWARN|n2=$WARNCT"
}
dp_ok=1
r=$(DSYM=1 drive_ep "$STANDBY" case_dirposture | tail -1)
[[ "$(field "$r" reg)" == "1" && "$(field "$r" n1)" == "1" && "$(field "$r" w1)" == *"armed spare PAIRED, but watchdog-elapsed CANNOT prove: $DIRWHY"* && "$(field "$r" n2)" == "1" && "$(field "$r" w2)" == *"paired (token gen=7), but watchdog-elapsed CANNOT prove: $DIRWHY"* ]] || { dp_ok=0; bad "(3l-R5b) symlinked state directory: $r"; }
r=$(DSYM=0 drive_ep "$STANDBY" case_dirposture | tail -1)
[[ "$(field "$r" reg)" == "1" && "$(field "$r" n1)" == "0" && "$(field "$r" n2)" == "0" ]] || { dp_ok=0; bad "(3l-R5b) canonical-path control: $r"; }
[[ $dp_ok -eq 1 ]] && ok "(3l-R5b) R-SYM — a registered spare whose PROOF_STATE_DIR is a symlink says WHY watchdog-elapsed cannot prove, on both surfaces, through W3's reason path: the startup posture ('armed spare PAIRED, but watchdog-elapsed CANNOT prove: $DIRWHY …') and the every-interval status line ('paired (token gen=7), but watchdog-elapsed CANNOT prove: …'); the canonical path prints neither (zero WARNs). Pre-fix (02c8e54): both silent — the PAIRED line alone"
case_samegen_dormant() {
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step; local a1="$_elapsed_answer"
    printf '%s\n' "$(mk_token 7 30 60 real otherholder)" > "$PROOF_STATE_DIR/pairing-token"   # the same gen and bounds, another host
    _SIM_NOW=$(( T0 + 110 )); local v; v=$(_elapsed_provider)
    require_relinquish_proof; local g=$?
    _elapsed_step; local a2="$_elapsed_answer" r2="$_elapsed_reason"
    echo "a1=$a1|served=$(_proof_field "$v" proven)|vr=$(_proof_field "$v" elapsed_reason)|gate=$g|a2=$a2|r2=$r2"
}
r=$(drive_ep "$STANDBY" case_samegen_dormant | tail -1)
if [[ "$(field "$r" a1)" == "yes" && "$(field "$r" served)" == "no" && "$(field "$r" vr)" == *"the stored token changed under the verdict: the same gen=7, but not the token it was minted under"* && "$(field "$r" gate)" == "1" ]] \
   && [[ "$(field "$r" a2)" == "cannot" && "$(field "$r" r2)" == "withdrawn: the stored token changed under the verdict"* ]]; then
    ok "(3l-R4c) R4 — a same-gen token from ANOTHER host with the same bounds swapped in under a DORMANT verdict: the reporter serves proven=no ('the stored token changed under the verdict: the same gen=7, but not the token it was minted under'), the gate refuses (rc 1), and the next step withdraws it and clears the adoption. Pre-fix: served proven=yes, gate rc 0"
else
    bad "(3l-R4c) $r"
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
# lagging 40 slots (> N_HEAD 22). It measures the defense in depth a seam regression would lean on.
# 6.3.1 adds two layers to the set: [elapsed-rate] (this spare's own confirmed head must PROVE >= 2.5
# slots/s over the silence span — the archetype's span, 20 s since its blind_until, is under
# ELAPSED_RATE_MIN_SPAN: it refuses on its own line once the head is neutered) and [elapsed-own] (an
# own-bank "holder voting" observation restarts the silence — not engaged by this archetype; its own
# archetype and neuter control are (5m)/(5n), the rate layer's (5o)).
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
        *"HEAD GAP"*) echo "gap" ;;
        *"the seam moved under the verdict"*) echo "seam" ;;
        *"RATE SPAN SHORT"*|*"SLOW OWN HEAD"*|*"RATE UNPROVEN"*) echo "rate" ;;
        *"the own bank showed the holder VOTING"*) echo "own" ;;
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
M_GAP='s/if \[\[ \$(( _es_hd - _es_pay )) -gt \$ELAPSED_HEAD_GAP_MAX \]\]; then/if [[ 1 -eq 2 ]]; then/'
# 6.3.1: [elapsed-rate] deleted whole (from its comment header to the mint site); [elapsed-own]'s two halves
# (the step's silence start / floor, and the reporter's serve-time check)
M_RATE='/^    # \[elapsed-rate\] (6.3.1, D4 e)/,/the verdict-minting site (every layer passed)/{/the verdict-minting site (every layer passed)/!d;}'
M_OWN1='s/_es_own="\${_own_bank_active_time:-0}"$/_es_own=0/'
M_OWN2='s/if \[\[ \${_own_bank_active_time:-0} -gt \$_elapsed_since \]\]; then/if [[ 1 -eq 2 ]]; then/'
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
mutate "$STANDBY" "$M_GAP" "$WORK/n-gap.sh"
mutate "$STANDBY" "$M_RATE" "$WORK/n-rate.sh"
mutate "$STANDBY" "$M_OWN1" "$WORK/n-own-a.sh" && mutate "$WORK/n-own-a.sh" "$M_OWN2" "$WORK/n-own.sh"
s_ok=1; s_rows=""
for n in token blind floor head gap rate own; do
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
mutate "$WORK/c-tbf.sh" "$M_HEAD" "$WORK/c-tbfh-a.sh" && mutate "$WORK/c-tbfh-a.sh" "$M_GAP" "$WORK/c-tbfh.sh"
mutate "$WORK/c-tbfh.sh" "$M_RATE" "$WORK/c-all-a.sh" && mutate "$WORK/c-all-a.sh" "$M_OWN1" "$WORK/c-all-b.sh" && mutate "$WORK/c-all-b.sh" "$M_OWN2" "$WORK/c-all.sh"
r1=$(TOK=lowfloor drive_ep "$WORK/n-token.sh" case_archetype | tail -1)
r2=$(TOK=lowfloor drive_ep "$WORK/c-tb.sh" case_archetype | tail -1)
r3=$(TOK=lowfloor drive_ep "$WORK/c-tbf.sh" case_archetype | tail -1)
r3h=$(TOK=lowfloor drive_ep "$WORK/c-tbfh.sh" case_archetype | tail -1)
r4=$(TOK=lowfloor drive_ep "$WORK/c-all.sh" case_archetype | tail -1)
if [[ "$(layer_of "$r1")" == "blind" && "$(layer_of "$r2")" == "floor" && "$(layer_of "$r3")" == "head" && "$(layer_of "$r3h")" == "rate" ]] \
   && [[ "$(field "$r1" r)" == *"blindness ended 20s ago"* && "$(field "$r2" r)" == *"observed silence 30s < elapsed_floor 40s"* && "$(field "$r3" r)" == *"40 slots behind this spare's own head"* && "$(field "$r3h" r)" == "RATE SPAN SHORT: the own-head samples span 20s"* ]]; then
    ok "(5c) the chain, each kill reason captured: token neutered → [elapsed-blind] ('blindness ended 20s ago'); +blind → [elapsed-floor] ('observed silence 30s < elapsed_floor 40s'); +floor → [elapsed-head] ('40 slots behind this spare's own head'); +head/gap → [elapsed-rate] (6.3.1: 'RATE SPAN SHORT: the own-head samples span 20s' — the silence since blind_until is too short to certify a rate) — every step layer refuses the archetype on its own"
else
    bad "(5c) r1=$(layer_of "$r1") r2=$(layer_of "$r2") r3=$(layer_of "$r3") r3h=$(layer_of "$r3h") :: $r3h"
fi
if [[ "$(field "$r4" a)" == "yes" && "$(field "$r4" proven)" == "yes" ]]; then
    ok "(5d) [elapsed-token]/[elapsed-blind]/[elapsed-floor] (both halves)/[elapsed-head]/[elapsed-gap]/[elapsed-rate]/[elapsed-own] (both halves) ALL neutered → the seam-regression archetype MINTS and is SERVED PROVEN (forged acceptance RESTORED): no hidden guard on this line ([elapsed-seam] does not see it — the archetype's seam never moves after the mint; (5e)–(5h) is where that layer is load-bearing; [elapsed-gap] does not see it either — the archetype's reads take no time; (5i)–(5k) is where it is; [elapsed-own]'s archetype is (5m)/(5n))"
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
# 6.3.1: [elapsed-rate] refuses the reachable state at the STEP on its own line — the silence since blind_until
# is 1 s, far under ELAPSED_RATE_MIN_SPAN (5e-rate) — so (5f)–(5h) run with it neutered too, to reach the
# serve-time layers they exist for (the rate layer is load-bearing on its own archetype, (5o))
rbr=$(drive_ep "$WORK/n-blind.sh" case_reachable | tail -1)
if [[ "$(field "$rbr" a)" == "blind" && "$(layer_of "$rbr")" == "rate" && "$(field "$rbr" r)" == "RATE SPAN SHORT: the own-head samples span 1s"* && "$(field "$rbr" grc)" == "1" ]]; then
    ok "(5e-rate) a NAMED SURVIVOR added by 6.3.1: [elapsed-blind] neutered ALONE on the reachable state → [elapsed-rate] refuses at the step ('RATE SPAN SHORT: the own-head samples span 1s' — no rate is certifiable over the 1 s since blind_until), gate rc 1"
else
    bad "(5e-rate) blind-neutered=$rbr"
fi
mutate "$WORK/n-blind.sh" "$M_RATE" "$WORK/n-blind-r.sh"
mutate "$STANDBY" "$M_SEAM1" "$WORK/s-seam-a.sh" && mutate "$WORK/s-seam-a.sh" "$M_SEAM2" "$WORK/s-seam.sh"
mutate "$WORK/n-blind-r.sh" "$M_SEAM1" "$WORK/s-bs-a.sh" && mutate "$WORK/s-bs-a.sh" "$M_SEAM2" "$WORK/s-bs.sh"
mutate "$WORK/s-bs.sh" "$M_FLOOR2" "$WORK/s-bsf.sh"
rb=$(drive_ep "$WORK/n-blind-r.sh" case_reachable | tail -1)
rs=$(drive_ep "$WORK/s-seam.sh" case_reachable | tail -1)
rbs=$(drive_ep "$WORK/s-bs.sh" case_reachable | tail -1)
rall=$(drive_ep "$WORK/s-bsf.sh" case_reachable | tail -1)
if [[ "$(field "$rb" a)" == "yes" && "$(layer_of "$rb")" == "seam" && "$(field "$rb" vr)" == *"no observed span now (observed_since=0"* && "$(field "$rb" grc)" == "1" ]] \
   && [[ "$(layer_of "$rs")" == "blind" && "$(field "$rs" grc)" == "1" ]]; then
    ok "(5f) each neutered ALONE on the reachable state ([elapsed-rate] out of the way throughout — (5e-rate)): [elapsed-blind] gone → the step MINTS ('1s of observed silence' since blind_until) and [elapsed-seam] withdraws it at the reporter ('no observed span now (observed_since=0 …)'), gate rc 1; [elapsed-seam] gone → [elapsed-blind] still refuses at the step, gate rc 1 — the reporter's check is a NAMED layer with its own neuter control"
else
    bad "(5f) blind-neutered=$rb :: seam-neutered=$rs"
fi
if [[ "$(field "$rbs" a)" == "yes" && "$(layer_of "$rbs")" == "floor" && "$(field "$rbs" vr)" == *"the re-derived elapsed_floor 100s exceeds the 1s of silence the verdict was minted on"* && "$(field "$rbs" grc)" == "1" ]]; then
    ok "(5g) [elapsed-blind] AND [elapsed-seam] neutered → a THIRD named layer still refuses: [elapsed-floor]'s serve-time half ('the re-derived elapsed_floor 100s exceeds the 1s of silence the verdict was minted on' — the 6.3 fix round's M1 re-check), gate rc 1"
else
    bad "(5g) blind+seam-neutered=$rbs"
fi
if [[ "$(field "$rall" a)" == "yes" && "$(field "$rall" proven)" == "yes" && "$(field "$rall" grc)" == "0" && "$(field "$rall" erc)" == "0" && "$(field "$rall" oid)" == "elapsed:gen=7:since=$(( T0 + 5 )):floor=100" ]]; then
    ok "(5h) all three neutered ([elapsed-blind] + [elapsed-seam] + [elapsed-floor]'s serve half, with [elapsed-rate]) → the FORGED ACCEPTANCE AT THE GATE reappears: require_relinquish_proof rc 0 and _proof_age_edge_check rc 0 on observation_id since=+5 — 1 s after a stamped blindness. The enumerated set is complete over the reachable state"
else
    bad "(5h) all-neutered reachable mutant did not restore the forged acceptance: $rall"
fi

# (5i)–(5k) THE GAP ARCHETYPE (6.3 fix round 2, R3 — FX-2): this spare's own bank trails the chain by
# BANKLAG slots, the tiers serve the LIVE view (the chain advances 2.5 slots/s on a file clock; every
# answer reflects the chain at the instant it is SERVED), and the head read lands 12 s after the payload
# (the house bound-counting: the payload's pet 7 s, then the head read at its curl -m 5 bound and its own
# 7 s pet). The bank moves 30 slots while the gap runs, so a bank 50 slots behind the live view reads 19
# behind — inside N_HEAD (25 then; 22 since 6.3.1): the head compare alone cannot see it. [elapsed-gap]
# refuses on its own line.
# Pre-fix red (f22d492): BANKLAG=50 MINTED and the gate accepted (rc 0); BANKLAG=0 answered LAGGED VIEW.
case_gap() {   # BANKLAG (slots)
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); fileclock_on
    eval "$(declare -f _ep_curl | sed '1s/^_ep_curl/_ep_curl0/')"
    _ep_curl() {   # the chain at the instant the answer is served (after the read's latency); LOCAL = the chain − BANKLAG
        local a u="" c; for a in "$@"; do case "$a" in http*) u="$a" ;; esac; done
        read -r c < "$CLKF"
        HEAD=$(( HEAD0 + (c - T0) * 5 / 2 )); VIEWLAG=1
        [[ "$u" == "$LOCAL_RPC" ]] && HEAD=$(( HEAD - BANKLAG ))
        _ep_curl0 "$@"
    }
    LAT_LOCAL=5; PETCOST=7
    _elapsed_step
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    echo "reg=$_elapsed_registered|a=$_elapsed_answer|r=$_elapsed_reason|proven=$(_proof_field "$v" proven)|vr=$(_proof_field "$v" elapsed_reason)|grc=$grc"
}
g50=$(BANKLAG=50 drive_ep "$STANDBY" case_gap | tail -1)
if [[ "$(field "$g50" a)" == "blind" && "$(layer_of "$g50")" == "gap" && "$(field "$g50" r)" == "HEAD GAP: the head read landed 12s after the payload read"* && "$(field "$g50" grc)" == "1" ]]; then
    ok "(5i) LIVE, the gap archetype (this bank 50 slots behind the live view, the head read landing 12 s after the payload): [elapsed-gap] refuses ('HEAD GAP: the head read landed 12s after the payload read'), blind, gate rc 1. Pre-fix: MINTED, gate rc 0 — the 30 slots the bank moved during the gap hid 30 of its 50-slot lag"
else
    bad "(5i) $g50"
fi
g50n=$(BANKLAG=50 drive_ep "$WORK/n-gap.sh" case_gap | tail -1)
g60n=$(BANKLAG=60 drive_ep "$WORK/n-gap.sh" case_gap | tail -1)
if [[ "$(field "$g50n" a)" == "yes" && "$(field "$g50n" proven)" == "yes" && "$(field "$g50n" grc)" == "0" ]] \
   && [[ "$(field "$g60n" a)" == "blind" && "$(layer_of "$g60n")" == "head" && "$(field "$g60n" r)" == *"STALE REFERENCE"*"29 slots behind"* ]]; then
    ok "(5j) [elapsed-gap] neutered ALONE → the gap archetype MINTS and the gate accepts (rc 0): a bank 50 slots behind the live view certified fresh — the layer is load-bearing (its own neuter control; [elapsed-head] passes the 19 slots it SEES). Beyond the hidden amount the head layer is the named survivor: 60 slots behind → STALE REFERENCE (29 slots seen), blind"
else
    bad "(5j) gap-neutered@50=$g50n :: gap-neutered@60=$g60n"
fi
g0=$(BANKLAG=0 drive_ep "$STANDBY" case_gap | tail -1)
g0n=$(BANKLAG=0 drive_ep "$WORK/n-gap.sh" case_gap | tail -1)
if [[ "$(layer_of "$g0")" == "gap" && "$(field "$g0" grc)" == "1" && "$(layer_of "$g0n")" == "head" && "$(field "$g0n" r)" == *"LAGGED VIEW"*"31 slots behind"* && "$(field "$g0n" grc)" == "1" ]]; then
    ok "(5k) the IN-SYNC control (this bank on the chain, the same 12 s gap): HEAD GAP, blind; [elapsed-gap] neutered → LAGGED VIEW (the live view reads 31 slots behind the bank that moved during the gap), blind — no mint either way (pre-fix: LAGGED VIEW)"
else
    bad "(5k) live=$g0 :: gap-neutered=$g0n"
fi
# (5l) DOCUMENTED RESIDUAL (6.3 fix round 3, S5 — pinned in fix round 4, P4-S5-NOPIN): what [elapsed-gap]
# does NOT bound — the payload's own snapshot → delivery. The TIER2 payload is computed at its REQUEST and
# delivered 9 s later (inside its curl -m 10), every pet free, the head read instant: the STAMPED gap is 0 s,
# so the head compare measures this bank against a view 9 s older than its arrival — at 2.5 slots/s a hidden
# lag of 22 slots on top of N_HEAD 22 (25 before 6.3.1). The snapshot-at-delivery control (the same 9 s
# latency) hides nothing.
# RESIDUAL — this flips when the sampler stamps BEFORE its call and the gap is measured from the payload's
# REQUEST (the request-stamped variant, deferred with the gate's wiring, 6.4).
case_snap() {   # BANKLAG (slots); SNAPREQ=1: the view is the chain at the REQUEST, 0: at the delivery
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); fileclock_on
    eval "$(declare -f _ep_curl | sed '1s/^_ep_curl/_ep_curl0/')"
    _ep_curl() {
        local a u="" c; for a in "$@"; do case "$a" in http*) u="$a" ;; esac; done
        read -r c < "$CLKF"
        HEAD=$(( HEAD0 + (c - T0) * 5 / 2 )); VIEWLAG=0
        if [[ "$u" == "$TIER2_RPC" ]]; then
            _clk_adv 9   # the answer lands 9 s after its request...
            [[ "${SNAPREQ:-1}" == "1" ]] || { read -r c < "$CLKF"; HEAD=$(( HEAD0 + (c - T0) * 5 / 2 )); }   # ...its view from the request (1) or the delivery (0)
        fi
        [[ "$u" == "$LOCAL_RPC" ]] && HEAD=$(( HEAD - BANKLAG ))
        _ep_curl0 "$@"
    }
    PETCOST=0; LAT_LOCAL=0
    _elapsed_step
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    echo "a=$_elapsed_answer|r=$_elapsed_reason|proven=$(_proof_field "$v" proven)|grc=$grc"
}
s44=$(BANKLAG=44 SNAPREQ=1 drive_ep "$STANDBY" case_snap | tail -1)
s45=$(BANKLAG=45 SNAPREQ=1 drive_ep "$STANDBY" case_snap | tail -1)
c22=$(BANKLAG=22 SNAPREQ=0 drive_ep "$STANDBY" case_snap | tail -1)
c23=$(BANKLAG=23 SNAPREQ=0 drive_ep "$STANDBY" case_snap | tail -1)
if [[ "$(field "$s44" a)" == "yes" && "$(field "$s44" proven)" == "yes" && "$(field "$s44" grc)" == "0" && "$(field "$s44" r)" == *"head read 0s after the payload"* ]] \
   && [[ "$(field "$s45" a)" == "blind" && "$(field "$s45" r)" == *"STALE REFERENCE"* ]] \
   && [[ "$(field "$c22" a)" == "yes" && "$(field "$c23" a)" == "blind" && "$(field "$c23" r)" == *"STALE REFERENCE"* ]]; then
    ok "(5l) DOCUMENTED RESIDUAL — the payload SNAPSHOTTED AT ITS REQUEST and delivered 9 s later (free pets, an instant head; the stamped gap 0 s): watchdog-elapsed MINTS and the gate accepts with this bank 44 slots behind the live chain (= N_HEAD 22 + 22 hidden at 2.5 slots/s — the snapshot→delivery term docs/SAFETY.md names, up to rate x its curl -m 10; 47 = 25 + 22 before 6.3.1), 45 → STALE REFERENCE; the snapshot-at-DELIVERY control mints only up to N_HEAD (22 mints, 23 → STALE REFERENCE). Flips when the gap is measured from the payload request (6.4)"
else
    bad "(5l) snap-at-request 44=$s44 :: 45=$s45 :: snap-at-delivery 22=$c22 :: 23=$c23"
fi

# (5m)–(5o) 6.3.1's two layers, each on its OWN archetype with its own neuter control (the layer-set census
# above lists them; this is where each is load-bearing).
# (5m) [elapsed-own], step half — the own bank showed the holder VOTING at +50 (the main loop's D2 stamp — a
# fixture write of _own_bank_active_time, as the loop writes it on a LOCAL not-delinquent cycle in an open
# episode) inside a silence the tiers observed since T0; the evaluation at +120 and at +150.
case_own_step() {
    reg; prime_seam 0 none
    _own_bank_active_time=$(( T0 + 50 ))
    _SIM_NOW=$(( T0 + 120 )); _elapsed_step
    local a1="$_elapsed_answer" r1="$_elapsed_reason" v1; v1=$(_elapsed_provider)
    require_relinquish_proof; local g1=$?
    _SIM_NOW=$(( T0 + 150 )); _elapsed_step
    local v2; v2=$(_elapsed_provider)
    echo "a1=$a1|r1=$r1|p1=$(_proof_field "$v1" proven)|g1=$g1|a2=$_elapsed_answer|oid2=$(_proof_field "$v2" observation_id)"
}
ro=$(drive_ep "$STANDBY" case_own_step | tail -1)
ron=$(drive_ep "$WORK/n-own.sh" case_own_step | tail -1)
if [[ "$(field "$ro" a1)" == "no" && "$(field "$ro" r1)" == "the own bank showed the holder VOTING 70s ago (mono $(( T0 + 50 ))) < elapsed_floor 100s"* && "$(field "$ro" g1)" == "1" ]] \
   && [[ "$(field "$ro" a2)" == "yes" && "$(field "$ro" oid2)" == "elapsed:gen=7:since=$(( T0 + 50 )):floor=100" ]] \
   && [[ "$(field "$ron" a1)" == "yes" && "$(field "$ron" p1)" == "yes" && "$(field "$ron" g1)" == "0" ]]; then
    ok "(5m) [elapsed-own] (6.3.1 D2 ii), the step half: the tiers observe the holder silent since T0, the own bank showed it VOTING at +50 → at +120 the provider answers no ('the own bank showed the holder VOTING 70s ago … < elapsed_floor 100s'), gate rc 1; the floor is met from the own-bank stamp, at +150 (observation_id since=+50). NEUTER CONTROL: [elapsed-own] neutered (both halves) → MINTS at +120 and the gate ACCEPTS (rc 0) — a proof minted on a silence span that contains an own-bank voting observation"
else
    bad "(5m) shipped=$ro :: own-neutered=$ron"
fi
# (5n) [elapsed-own], serve half — the verdict minted at +100 (no own-bank stamp), then the own bank shows the
# holder VOTING at +105 (after the mint): the gate at +106
case_own_serve() {
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step
    local a0="$_elapsed_answer"
    _own_bank_active_time=$(( T0 + 105 ))
    _SIM_NOW=$(( T0 + 106 ))
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    echo "a0=$a0|proven=$(_proof_field "$v" proven)|vr=$(_proof_field "$v" elapsed_reason)|grc=$grc"
}
mutate "$STANDBY" "$M_OWN2" "$WORK/n-own2.sh"
rs1=$(drive_ep "$STANDBY" case_own_serve | tail -1)
rs2=$(drive_ep "$WORK/n-own2.sh" case_own_serve | tail -1)
if [[ "$(field "$rs1" a0)" == "yes" && "$(field "$rs1" proven)" == "no" && "$(field "$rs1" vr)" == "withdrawn: the own bank showed the holder VOTING at mono $(( T0 + 105 )), after the silence the verdict rests on began ($T0)"* && "$(field "$rs1" grc)" == "1" ]] \
   && [[ "$(field "$rs2" proven)" == "yes" && "$(field "$rs2" grc)" == "0" ]]; then
    ok "(5n) [elapsed-own], the serve half: a verdict minted at +100, then the own bank shows the holder VOTING at +105 → at +106 the reporter WITHDRAWS it ('the own bank showed the holder VOTING at mono +105, after the silence the verdict rests on began'), gate rc 1. NEUTER CONTROL: the serve half neutered → served PROVEN, the gate ACCEPTS (rc 0)"
else
    bad "(5n) shipped=$rs1 :: serve-neutered=$rs2"
fi
# (5o) [elapsed-rate] (6.3.1 D4 e) — this spare's own confirmed head at two TIMES must PROVE >= 2.5 slots/s over
# the silence span (2·Δslot >= 5·(Δt+1), Δt >= ELAPSED_RATE_MIN_SPAN): 100 s of silence at +100, the own head
# (the synthetic ring — the main loop's _own_head_sample through the REAL loop is test_own_view (4e)) at
# OWNRATE slots/s; no samples at all; samples only in the last 20 s
case_rate() {
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 100 )); _elapsed_step
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    echo "a=$_elapsed_answer|r=$_elapsed_reason|proven=$(_proof_field "$v" proven)|grc=$grc"
}
q20=$(OWNRATE_NUM=2 OWNRATE_DEN=1 drive_ep "$STANDBY" case_rate | tail -1)
q25=$(OWNRATE_NUM=5 OWNRATE_DEN=2 drive_ep "$STANDBY" case_rate | tail -1)
q253=$(OWNRATE_NUM=253 OWNRATE_DEN=100 drive_ep "$STANDBY" case_rate | tail -1)
q40=$(drive_ep "$STANDBY" case_rate | tail -1)
qoff=$(OWNRING=off drive_ep "$STANDBY" case_rate | tail -1)
qlate=$(OWNRING=late drive_ep "$STANDBY" case_rate | tail -1)
q20n=$(OWNRATE_NUM=2 OWNRATE_DEN=1 drive_ep "$WORK/n-rate.sh" case_rate | tail -1)
if [[ "$(field "$q20" a)" == "blind" && "$(field "$q20" r)" == "SLOW OWN HEAD: this spare's confirmed head advanced 200 slots in 100s"*">= 253 slots"* && "$(field "$q20" grc)" == "1" ]] \
   && [[ "$(field "$q25" a)" == "blind" && "$(field "$q25" r)" == "SLOW OWN HEAD: this spare's confirmed head advanced 250 slots in 100s"* ]] \
   && [[ "$(field "$q253" a)" == "yes" && "$(field "$q40" a)" == "yes" && "$(field "$q40" r)" == *"own head 400 slots in 100s (span average >= 2.5 slots/s)"* ]] \
   && [[ "$(field "$qoff" a)" == "blind" && "$(field "$qoff" r)" == "RATE UNPROVEN: no own-head sample"* && "$(field "$qlate" a)" == "blind" && "$(field "$qlate" r)" == "RATE SPAN SHORT: the own-head samples span 20s"* ]] \
   && [[ "$(field "$q20n" a)" == "yes" && "$(field "$q20n" proven)" == "yes" && "$(field "$q20n" grc)" == "0" ]]; then
    ok "(5o) [elapsed-rate]: 100 s of silence with this spare's own head at 2.0 slots/s → SLOW OWN HEAD, blind ('200 slots in 100s' — REQUIRED >= 253), gate rc 1; at exactly the assumed 2.5 → blind too (250 < 253: the abstaining bound never certifies a SMOOTH head at the assumed rate itself — the finding test_own_view (4e) measures on the REAL loop; a hold at the anchor sample can, docs/SAFETY.md 'Slot time'); 2.53 → PROVEN (253); 4.0 → PROVEN ('own head 400 slots in 100s'); no own-head sample → RATE UNPROVEN; samples only in the last 20 s → RATE SPAN SHORT. NEUTER CONTROL: [elapsed-rate] neutered → the 2.0-slots/s silence MINTS and the gate ACCEPTS (rc 0) — N_HEAD's 22 slots are 11 s there, past MARGIN_ELAPSED − 1"
else
    bad "(5o) 2.0=$q20 :: 2.5=$q25 :: 2.53=$q253 :: 4.0=$q40 :: off=$qoff :: late=$qlate :: rate-neutered@2.0=$q20n"
fi
# (5o-fresh) the rate layer's FRESHNESS guard — the newest own-head sample must be no older than OWN_HEAD_H (6.3.1 fix
# round 1, R6 — the panel's T7: the guard neutered, mutant M09, stayed green in every suite). The REAL _elapsed_step
# twice: at +1 the rate anchor is captured from the ring {T0}; at +100 the ring holds only +54..+70 (the own-head
# sampler failed for the last 30 s — the real ring keeps the good samples it has), a healthy 4 slots/s throughout.
case_stale() {
    reg; prime_seam 0 none
    _SIM_NOW=$(( T0 + 1 )); _own_head_ring="$T0:$T0:$(_ep_own_slot "$T0")"; _real_elapsed_step
    local r="" x v grc
    for x in 54 58 62 66 70; do r="$r $((T0 + x)):$((T0 + x)):$(_ep_own_slot $((T0 + x)))"; done
    _SIM_NOW=$(( T0 + 100 )); _own_head_ring="${r# }"; _real_elapsed_step
    v=$(_elapsed_provider); require_relinquish_proof; grc=$?
    echo "a=$_elapsed_answer|r=$_elapsed_reason|proven=$(_proof_field "$v" proven)|grc=$grc"
}
M_FRESH='s/^    if \[\[ \$(( _es_now - _es_lpost )) -gt \$OWN_HEAD_H \]\]; then$/    if false; then/'
mutate "$STANDBY" "$M_FRESH" "$WORK/n-fresh.sh"
qst=$(drive_ep "$STANDBY" case_stale | tail -1)
qstn=$(drive_ep "$WORK/n-fresh.sh" case_stale | tail -1)
if [[ "$(field "$qst" a)" == "blind" && "$(field "$qst" r)" == "RATE UNPROVEN: the newest own-head sample is 30s old (> OWN_HEAD_H=16)"* && "$(field "$qst" grc)" == "1" ]] \
   && [[ "$(field "$qstn" a)" == "yes" && "$(field "$qstn" proven)" == "yes" && "$(field "$qstn" grc)" == "0" ]]; then
    ok "(5o-fresh) [elapsed-rate]'s freshness guard: the own-head sampler silent for the last 30 s (the ring's newest sample +70 at the +100 evaluation) → RATE UNPROVEN ('the newest own-head sample is 30s old'), blind, gate rc 1. NEUTER CONTROL (the panel's surviving mutant M09): the guard neutered → the rate is 'proven' over +0..+70 and the gate ACCEPTS (rc 0) — a rate that cannot be measured up to now no longer mints"
else
    bad "(5o-fresh) shipped=$qst :: guard-neutered=$qstn"
fi

# ── (6) coupling ───────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) coupling [pre-registration (b)]: MARGIN_ELAPSED moves floor AND N_HEAD; the provider follows ───"
case_couple() {   # $SIL silence (s), $VL view lag (slots)
    reg; prime_seam 0 none
    VIEWLAG=$VL; _SIM_NOW=$(( T0 + SIL )); _elapsed_step
    echo "floor=$elapsed_floor|nhead=$N_HEAD|a=$_elapsed_answer|r=$_elapsed_reason"
}
mutate "$STANDBY" 's/^    MARGIN_ELAPSED=10$/    MARGIN_ELAPSED=20/' "$WORK/m20.sh"
mutate "$WORK/m20.sh" 's|N_HEAD=$(( (MARGIN_ELAPSED - 1) \* 5 / 2 ))|N_HEAD=22|' "$WORK/m20-decoupled.sh"
b1=$(SIL=105 VL=1 drive_ep "$STANDBY" case_couple | tail -1);  m1=$(SIL=105 VL=1 drive_ep "$WORK/m20.sh" case_couple | tail -1)
b2=$(SIL=115 VL=40 drive_ep "$STANDBY" case_couple | tail -1); m2=$(SIL=115 VL=40 drive_ep "$WORK/m20.sh" case_couple | tail -1)
d1=$(SIL=105 VL=1 drive_ep "$WORK/m20-decoupled.sh" case_couple | tail -1)
d2=$(SIL=115 VL=40 drive_ep "$WORK/m20-decoupled.sh" case_couple | tail -1)
together_6a() {   # (6a)'s assertion as a predicate over (base1, mutant1, base2, mutant2)
    [[ "$(field "$1" floor)/$(field "$1" nhead)" == "100/22" && "$(field "$2" floor)/$(field "$2" nhead)" == "110/47" ]] \
    && [[ "$(field "$1" a)" == "yes" && "$(field "$2" a)" == "no" && "$(field "$2" r)" == *"observed silence 105s < elapsed_floor 110s"* ]] \
    && [[ "$(field "$3" a)" == "blind" && "$(field "$4" a)" == "yes" ]]
}
if together_6a "$b1" "$m1" "$b2" "$m2"; then
    ok "(6a) MARGIN_ELAPSED 10→20 → floor 100→110 AND N_HEAD 22→47 (= (MARGIN − 1) × 5/2, τ budgeted since 6.3.1), and the provider follows BOTH, measured: 105 s of silence proves on the shipped build and does NOT on the mutant ('105s < 110s'); a 40-slot lagged view is blind on the shipped build and proves on the mutant — tolerance and floor rise TOGETHER (the only sanctioned response to vantages failing the cross-check)"
else
    bad "(6a) base1=$b1 mut1=$m1 base2=$b2 mut2=$m2"
fi
if [[ "$(field "$d2" floor)/$(field "$d2" nhead)" == "110/22" && "$(field "$d2" a)" == "blind" ]] && ! together_6a "$b1" "$d1" "$b2" "$d2"; then
    ok "(6b) CONTROL: the coupling additionally broken (N_HEAD static at 22 while MARGIN is 20) → floor 110 with N_HEAD 22, the 40-slot view stays blind, and (6a)'s together-predicate EVALUATED on this double mutant is FALSE (observed, not inferred)"
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
[[ $un_ok -eq 1 ]] && ok "(7e) ARMED spare, UNPAIRED (none / page-only / invalid token) → zero provider events on register+step+provider — the silence-based provider never mints over an unattested holder, by construction, not by a check that could be skipped (that proof conditions a take only once 6.4 wires the gate)"

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
    n_ohs=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -c '_own_head_sample')   # fix round 2 (S2): the split's own-head sample
    n_pet=$(printf '%s\n' "$REGION" | grep -c '^[[:space:]]*_watchdog_pet\b')
    n_sleep=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -c '\bsleep\b')
    n_wall=$(printf '%s\n' "$REGION" | grep -c 'date +%s')
    n_patsub=$(printf '%s\n' "$REGION" | grep -cE '\$\{[A-Za-z_0-9]+//')
    n_seamw=$(printf '%s\n' "$REGION" | grep -v '^[[:space:]]*#' | grep -cE '(_liveness_obs_since|_last_blind_end|_liveness_first_[a-z]+|LAST_LIVENESS_ACTIVE_TIME)=|_note_blind_cycle|_note_observation')
    if [[ "$n_curl" == "1" && "$n_curl_any" == "1" && "$n_samp" == "2" && "$n_ohs" == "1" && "$n_pet" == "1" && "$n_sleep" == "0" && "$n_wall" == "0" && "$n_patsub" == "0" && "$n_seamw" == "0" ]]; then
        ok "(8b) static region census: ONE own read site (the head, curl -m 5) == ONE per-op pet site; the sampler on TWO lines, one of which runs (fix round 2, S2: with distinct tiers one tier per call, an own-head sample — its ONE site here, a LOCAL read with its own pet — between a TIER2 failure and TIER3; otherwise the one call — the sampler pets its own reads), ZERO sleep, ZERO wall-clock (mono only — the ci wall-clock pins do not move), ZERO patsub, ZERO seam writes (no _note_blind_cycle/_note_observation, no triple/pin/anchor assignment) — the region only READS the seam"
    else
        bad "(8b) region census: curl-m5=$n_curl curl-invocations=$n_curl_any sampler-lines=$n_samp own-head-samples=$n_ohs pet=$n_pet sleep=$n_sleep wall=$n_wall patsub=$n_patsub seamwrites=$n_seamw"
    fi
else
    bad "(8b) EMPTY [elapsed-provider] region extraction — the static census would be vacuous"
fi

# ── (9) constants ──────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) constants: the region assigns none of the derived names; the N_HEAD condition stays at its site ───"
CONST_RE='(^[[:space:]]*((local|declare|export|readonly)[[:space:]]+([-][[:alnum:]]+[[:space:]]+)*)?(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE|ELAPSED_HEAD_GAP_MAX|ELAPSED_RATE_MIN_SPAN|OWN_HEAD_H)=)|(\(\([[:space:]]*(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE|ELAPSED_HEAD_GAP_MAX|ELAPSED_RATE_MIN_SPAN|OWN_HEAD_H)[[:space:]]*=)'
k_ok=1
for d in "$STANDBY" "$PRIMARY"; do
    rg=$(extract_region "$d" '\[elapsed-provider\] watchdog-elapsed (attested time) proof provider' '\[elapsed-provider\] end shared block')
    [[ -n "$rg" ]] || { k_ok=0; bad "(9a) $(basename "$d"): EMPTY [elapsed-provider] region extraction — the constants census would be vacuous"; }
    n=$(printf '%s\n' "$rg" | grep -cE "$CONST_RE")
    [[ "$n" == "0" ]] || { k_ok=0; bad "(9a) $(basename "$d"): the region assigns a derived constant ($n sites)"; }
    df=$(sed -n '/^_derive_proof_floors() {/,/^}/p' "$d")
    printf '%s' "$df" | grep -q 'N_HEAD may$' && printf '%s' "$df" | grep -q 'NOT be loosened alone' || { k_ok=0; bad "(9a) $(basename "$d"): the N_HEAD condition comment left the derivation site"; }
done
[[ $k_ok -eq 1 ]] && ok "(9a) the [elapsed-provider] region assigns NONE of elapsed_floor/MARGIN_ELAPSED/N_HEAD/PROOF_MAX_AGE/ELAPSED_HEAD_GAP_MAX/ELAPSED_RATE_MIN_SPAN/OWN_HEAD_H (the test_proof_gate (11) broadened spellings; the fifth name is 6.3 fix round 2's R3 bound, the sixth 6.3.1's rate-span floor from the same derivation site, the seventh [own-view]'s constant — the rate layer READS both) in either daemon, and the pre-registered N_HEAD condition comment still sits inside _derive_proof_floors in both — the provider READS the one site"

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
# slots/s on 2026-09-26, docs/SAFETY.md 'Slot time'). EVERY seconds figure in (11)
# and (12) is at 2.5 slots/s unless a case names another rate. The boundaries in SLOTS: the own bank's
# delinquency rule 128; finalized = processed − 32 (a landed vote reaches the finalized bank ceil(32 /
# rate) s later — 13 s at 2.5/s); getHealth's distance 128; N_HEAD 22 (25 before 6.3.1); the minority
# vote-bank FREEZE 8. 6.3.1 (the own-view hardening) FLIPPED most of this section's D0 findings and
# residuals: each check below asserts the behavior MEASURED NOW and names the 6.3-build number it
# replaces; the D0 world family is the same, extended with the own-view veto's LOCAL batch read (logged
# as "read LOCAL batch") and the flicker / starvation knobs (test_own_view drives those).
# THE HOLDER: its last vote before the episode lands at t=0; it votes again from RESUME (-1 never) until
# STOP (-1 forever); each landed vote trails the head by HLAGS slots (default 0).
# THE SPARE'S OWN NODE (LOCAL_RPC), from verified agave v4.2.1 facts only: processed = the tower's last
# VOTABLE bank (replay_stage handle_votable_bank → update_commitment_cache; commitment_service slot =
# that bank); finalized = processed − 32; confirmed = the optimistically confirmed bank (processed − 2
# here); getVoteAccounts/getSlot at the commitment the request carries (none → the RPC default,
# finalized — every daemon body spells its commitment out since 6.3.1, D1; "finalized" and none are
# served alike, as agave does); agave's 128-slot delinquency rule; getHealth exactly as rpc_health.rs computes it (the
# node's own optimistic slot vs the latest optimistic slot its OWN blockstore observed via replay +
# gossip, distance DIST — default 128). CUT=<t> CUTMODE:
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
# protocol-aware 'afterconfirm' delays from the external-confirm read (a getVoteAccounts at the default
# commitment — "finalized", spelled out since 6.3.1) to the end of that cycle (D0-LAT); CURLMAX=1 every read takes its full -m bound; PETS=<s>
# every pet costs <s> (armed; the house counting is 7) and its completion is logged; HOLDCOOL=1 holds
# the take on the cooldown (a pet-gap world). ARMED=1: paired (gen 7, W30 B60 → floor 100 s); GATE=1
# the 6.4-placement EMULATION below; POSTTAKE=1 the loop runs on after the mutation (the STAKED
# branch: H1). HOSTILE=lv0 the tiers serve the holder's lastVote as the JSON STRING "0009999";
# HOSTILE=headwrap the spare's processed getSlot answers 2^64 + the true head (M4).
# 6.3 FIX ROUND 2 (the delta panel's differential knobs, ported verbatim from its driver so the round's
# reds run here): CKI/TI/TCD = CHECK_INTERVAL / TURBO_INTERVAL / TAKEOVER_COOLDOWN (defaults 5 / 1 / 120);
# VOTES=a:b[,c:d…] the holder votes in each window [a, b] (b < 0: forever) instead of RESUME/STOP;
# T2LAT / T3LAT_ALL / LOCLAT = every read of that source answers that many s late within [LATFROM,
# LATTO) (>= the read's -m bound: a timeout at the bound); T2BADFROM/T2BADTO TIER2 refuses instantly in
# that window; STALLFROM/STALLTO the tiers' view stalls then resumes live; SIFAIL=<n> the first n staked
# set-identity calls fail. The summary adds hvafter (does the holder vote at or after the mutation — the
# double-sign exposure), tsil, and egap_from/egap_cycles ([elapsed-gap]'s HEAD GAP answers, R3).
# 6.3.1 FIX ROUND 1: REFMODE=down|tmo|garb with REFFROM/REFTO — the own-bank MAX_DELINQUENT_SLOTS reference
# (local_check_delinquency's LOCAL finalized getSlot, alone) fails (the panel's AV-2 knob); the summary adds
# oa_first/oa_last/oa_n (R1's own-bank lastVote-ADVANCE stamps), ob_noev (R2's unstamped not-delinquent
# answers), ref_fails, and ob_vote_last (the last own-bank holder-voting observation of any kind: a positive
# current read, an advance, a VOTING veto — the protected window runs from it). And (R3/L3/L4): HOLDFROM/HOLDTO
# — the spare's own CONFIRMED head holds (does not advance) in [HOLDFROM, HOLDTO): a healthy hold, not a cut;
# the summary's ov_age/ov_ages are the own-view veto's baseline age at each CLEAR veto (from its log line);
# DIST=<n> the node's --health-check-slot-distance (getHealth's distance; default agave's 128 — the panel's
# L3 knob); FASTPATH=1 WITNESS_FASTPATH=true with the environment PRESENTING a corroborated flip once the
# episode is open (peer_has_relinquished answers yes — forgeable on shared vantages; the STANDBY role's
# stagger floor 0 — the panel's L4 knob).
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
        # T2URL (fix round 4 — the delta panel 3's removals-lens knob): set and empty = TIER2_RPC blanked (a single external tier)
        LOCAL_RPC="http://local.mock"; TIER2_RPC="${T2URL-http://t2.mock}"; TIER3_RPC="http://t3.mock"
        TAKEOVER_DELAY=60; TAKEOVER_COOLDOWN=${TCD:-120}; EXTERNAL_CONFIRM_THROTTLE=12
        MAX_DELINQUENT_SLOTS=${MDS:-0}; DRY_RUN=false; GOSSIP_VERIFY=${GV:-false}; WITNESS_FASTPATH=false
        if [[ "${FASTPATH:-0}" == "1" ]]; then   # the panel's L4 knob: a corroborated flip PRESENTED once the episode is open
            WITNESS_FASTPATH=true; _fastpath_disabled=""; _fastpath_stagger_floor=0
            peer_has_relinquished() { [[ ${FIRST_DELINQUENT_TIME:-0} -gt 0 ]]; }
        fi
        VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_EPSILON=0; VOTE_LIVENESS_MIN_INTERVAL=10; VOTE_LIVENESS_MIN_SPAN=40
        # LOCAL_HEALTH_MAX_BEHIND: the shipped default from the seam (printed as lhmb) unless LHMB overrides it
        [[ -n "${LHMB:-}" ]] && LOCAL_HEALTH_MAX_BEHIND=$LHMB
        SOLANA_PATH="$W"; LEDGER_PATH=/x; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15
        STAKED_KEYPAIR="$W/staked.json"; printf '[1]' > "$STAKED_KEYPAIR"; UNSTAKED_KEYPAIR="$W/unstaked.json"; printf '[2]' > "$UNSTAKED_KEYPAIR"
        CHECK_INTERVAL=${CKI:-5}; TURBO_INTERVAL=${TI:-1}; _current_interval=${CKI:-5}; HEARTBEAT_INTERVAL=999999; _last_heartbeat=$T0
        ALERT_THROTTLE=600; TAKEOVER_STARVATION_ALERT_SECS=${STARVE:-0}
        [[ "${HOLDCOOL:-0}" == "1" ]] && { LAST_TAKEOVER_TIME=$T0; TAKEOVER_COOLDOWN=999999; }
        # the FILE-BACKED mono clock (installed AFTER load_seam: its reshim re-applies the _SIM_NOW shims)
        # ONE shared clock: every stubbed read ADDS its latency (6.3.1 fix round 3, U1 — the delta panel 2's T6-SERIAL:
        # fix round 2 gave each branch of its concurrent re-check its own clock, keyed on the call stack, which made a
        # SERIALIZED re-check indistinguishable from the concurrent one; the re-check is the 6.3 build's one sampler
        # call again, and the harness sums, as it did before fix round 2)
        _now() { local x; read -r x < "$CLK"; echo "$x"; }
        _adv() { local x; read -r x < "$CLK"; echo $(( x + $1 )) > "$CLK"; }
        _t() { local x; read -r x < "$CLK"; echo $(( x - T0 )); }
        mono_now() { _now; }
        date() { if [[ "$1" == "+%s" ]]; then _now; return 0; fi; command date "$@"; }
        log() { :; }; log_error() { :; }
        log_info() { case "$*" in *"[liveness] staked vote frozen"*) echo "fence-frozen t=$(_t)" >> "$EV" ;; *"CONFIRMED delinquent"*) echo "confirm-ok t=$(_t)" >> "$EV" ;; esac; case "$*" in *"[own-view] veto read clear"*) local _a="${*##*baseline }"; _a="${_a#* (}"; _a="${_a%% s old*}"; echo "ov-clear t=$(_t) age=$_a" >> "$EV" ;; esac; }   # fix round 1 (R3): the veto's baseline age, from its clear line
        log_warn() {   # the mint INSTANT, from the provider's own PROVEN line; the H1 give-back reason; 6.3.1: the own-view veto and the D2 own-bank stamp
            case "$*" in
                *"watchdog-elapsed PROVEN"*) local _o="${*##*observed_at=}"; echo "elapsed-mint t=$(_t) oat=$(( ${_o%%;*} - T0 ))" >> "$EV" ;;
                *"[self-fence] LOCAL confirmed slot frozen"*) echo "h1-fence t=$(_t)" >> "$EV" ;;
                *"[own-view] VETO (holder voting)"*) echo "ov-veto t=$(_t) kind=voting" >> "$EV" ;;
                *"[own-view] VETO (blind)"*) echo "ov-veto t=$(_t) kind=blind" >> "$EV" ;;
                *"[own-bank] the holder reads NOT delinquent"*) echo "ob-current t=$(_t)" >> "$EV" ;;
                *"[own-bank] the holder's lastVote ADVANCED"*) echo "ob-advance t=$(_t)" >> "$EV" ;;                  # 6.3.1 fix round 1 (R1): an own-bank lastVote rise = holder voting
                *"[own-bank] a not-delinquent own-bank answer with NO positive basis"*) echo "ob-noev t=$(_t)" >> "$EV" ;;   # fix round 1 (R2): a skipped latency test, not stamped
                *"fresh re-check: staked vote ADVANCED"*) echo "rc-voting t=$(_t)" >> "$EV" ;;   # fix round 2 (S1): the re-check's outcome (the delta panel's driver lines)
                *"fresh re-check: provider flipped"*) echo "rc-flip t=$(_t)" >> "$EV" ;;
                *"fresh re-check: no usable sample"*) echo "rc-blind t=$(_t)" >> "$EV" ;;
                *"fresh re-check: cluster reference did not advance"*) echo "rc-stale t=$(_t)" >> "$EV" ;;
                *"fresh re-check: lastVote went backwards"*) echo "rc-back t=$(_t)" >> "$EV" ;;
                *"[liveness] staked vote ADVANCED"*) echo "fence-voting t=$(_t)" >> "$EV" ;;
            esac
            case "$*" in *"[own-view] VETO"*) local _w="${*#*: }"; echo "ov-why t=$(_t) ${_w:0:240}" >> "$EV" ;; esac   # fix round 2 (S2): the veto's reason
        }
        alert() { :; }; alert_info() { :; }; send_telegram() { :; }; send_webhook() { :; }
        alert_warn() { case "$1" in *"TAKEOVER STARVATION"*) echo "starve-page t=$(_t)" >> "$EV" ;; *"Take VETOED"*) echo "veto-page t=$(_t)" >> "$EV" ;; esac; }   # 6.3.1 (D2-cost): the starvation page, when STARVE enables it
        rotate_log() { :; }; heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _fence_rot_check() { :; }
        flush_pending_alerts() { :; }; save_state() { :; }; _sd_notify() { :; }
        get_local_identity() { cat "$IDF"; }
        display_status() {
            rm -f "$W/spl"
            local ek=none
            case "${_elapsed_reason:-}" in "STALE REFERENCE"*) ek=stale ;; "LAGGED VIEW"*) ek=lag ;; "HEAD GAP"*) ek=gap ;; "SLOW OWN HEAD"*) ek=slow ;; "RATE"*) ek=rate ;; esac
            echo "cycle t=$(_t) status=$1 fdt=${FIRST_DELINQUENT_TIME} ea=${_elapsed_answer:-na} ek=$ek fh=${_ep_floor_holds:-0}" >> "$EV"
        }
        # LCOMM what-if mutants of the own-bank detection read (6.3.1: its commitment is SPELLED OUT —
        # "finalized", D1 — so the mutant rewrites that word; each applies loudly or the world aborts)
        case "${LCOMM:-default}" in
            processed)
                eval "$(declare -f local_check_delinquency | sed 's/"method":"getVoteAccounts","params":\[{"commitment":"finalized"}\]}/"method":"getVoteAccounts","params":[{"commitment":"processed"}]}/')"
                declare -f local_check_delinquency | grep -qF '"getVoteAccounts","params":[{"commitment":"processed"}]' || { echo "world: the LCOMM=processed what-if mutant did not apply"; exit 1; } ;;
            confirmed)
                eval "$(declare -f local_check_delinquency | sed -e 's/"method":"getVoteAccounts","params":\[{"commitment":"finalized"}\]}/"method":"getVoteAccounts","params":[{"commitment":"confirmed"}]}/' -e 's/"method":"getSlot","params":\[{"commitment":"finalized"}\]}/"method":"getSlot","params":[{"commitment":"confirmed"}]}/')"
                declare -f local_check_delinquency | grep -qF '"getVoteAccounts","params":[{"commitment":"confirmed"}]' || { echo "world: the LCOMM=confirmed what-if mutant did not apply"; exit 1; } ;;
        esac
        eval "$(declare -f attempt_takeover | sed '1s/attempt_takeover/_real_attempt_takeover/')"
        attempt_takeover() { echo "attempt t=$(_t)" >> "$EV"; _real_attempt_takeover; }
        timeout() {
            [[ "$1" == "-k" ]] && shift 2
            shift
            case "$*" in
                *" set-identity $UNSTAKED_KEYPAIR"*) echo "GIVEBACK t=$(_t)" >> "$EV"; echo U1 > "$IDF"; return 0 ;;
                *" set-identity "*)
                    # 6.3 fix round 2 (the delta panel's knob): SIFAIL=<n> — the first n staked set-identity calls FAIL (admin socket refuses; identity unchanged)
                    if [[ ${SIFAIL:-0} -gt 0 ]] && [[ $(grep -c '^SIFAILED' "$EV") -lt ${SIFAIL:-0} ]]; then echo "SIFAILED t=$(_t)" >> "$EV"; return 1; fi
                    echo "MUTATION t=$(_t)" >> "$EV"; echo S1 > "$IDF"; return 0 ;;
                *"authorized-voter"*) return 0 ;;
            esac
            "$@"
        }
        _SN=${SLOT_NUM:-5}; _SD=${SLOT_DEN:-2}; _FL=$(( (32 * _SD + _SN - 1) / _SN ))   # finalized visibility lag = ceil(32 slots / rate)
        _slot() { echo $(( HEAD0 + $1 * _SN / _SD )); }
        _hv() {   # the holder's latest landed vote time <= $1
            local at="$1" r="${RESUME:--1}" s="${STOP:--1}" lv=0 iv a b c
            if [[ -n "${VOTES:-}" ]]; then
                for iv in ${VOTES//,/ }; do a=${iv%%:*}; b=${iv##*:}; if [[ $at -ge $a ]]; then c=$at; [[ $b -ge 0 && $c -gt $b ]] && c=$b; [[ $c -gt $lv ]] && lv=$c; fi; done
                echo "$lv"; return 0
            fi
            if [[ $r -ge 0 && $at -ge $r ]]; then lv=$at; [[ $s -ge 0 && $lv -gt $s ]] && lv=$s; fi
            echo "$lv"
        }
        _hvs() { echo $(( $(_slot "$(_hv "$1")") - ${HLAGS:-0} )); }   # ... as a slot (trailing the head by HLAGS)
        _gvaf() {   # 6.3.1: $1=bank $2=holder lastVote → the votePubkey-FILTERED getVoteAccounts RESULT (the holder alone), the same rule as _gva
            if [[ $2 -lt $(( $1 - 128 )) ]]; then printf '{"current":[],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}]}' "$2"
            else printf '{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]}' "$2"; fi
        }
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
            [[ "$src" == "LOCAL" && "$mm" == "batch" ]] && m=batch   # 6.3.1: the own-view veto's [getSlot, getVoteAccounts] batch — logged as its own read, never as the own-bank payload
            comm=default; case "$d" in *'"commitment":"processed"'*) comm=processed ;; *'"commitment":"confirmed"'*) comm=confirmed ;; esac   # "finalized" (spelled out since 6.3.1) and none = default: agave's default IS finalized
            t=$(_t)
            echo "read $src $m t=$t" >> "$EV"
            # ── latency (the file clock) ──
            if [[ "$src" == "T2" && "${T2DOWN:-0}" == "1" ]]; then _adv "$mt"; echo "timeout T2 +${mt}" >> "$EV"; return 28; fi
            # 6.3 fix round 2 (the delta panel's knob): T2BADFROM/T2BADTO — TIER2 refuses INSTANTLY (rc 7, no latency) in that window
            if [[ "$src" == "T2" && $t -ge ${T2BADFROM:--1} && $t -lt ${T2BADTO:--1} ]]; then echo "t2bad" >> "$EV"; return 7; fi
            # 6.3 fix round 2 (the delta panel's knobs): T2LAT/T3LAT_ALL/LOCLAT = every read of that source answers that many s late (>= its -m bound: a timeout at the bound), within [LATFROM, LATTO)
            if [[ $t -ge ${LATFROM:-0} && $t -lt ${LATTO:-999999} ]]; then
                local _gl=0
                case "$src" in T2) _gl=${T2LAT:-0} ;; T3) _gl=${T3LAT_ALL:-0} ;; LOCAL) _gl=${LOCLAT:-0} ;; esac
                if [[ "$mm" == "getClusterNodes" ]] && { [[ "${GCNONLYADV:-0}" != "1" ]] || [[ " ${FUNCNAME[*]} " == *" check_primary_dropped_identity "* ]]; }; then   # fix round 2 (S2): the gossip reads' own latency
                    case "$src" in T2) [[ -n "${GCNLAT_T2:-}" ]] && _gl=$GCNLAT_T2 ;; T3) [[ -n "${GCNLAT_T3:-}" ]] && _gl=$GCNLAT_T3 ;; esac
                fi
                if [[ $_gl -gt 0 ]]; then
                    if [[ $_gl -ge $mt ]]; then _adv "$mt"; echo "timeout $src +${mt}" >> "$EV"; return 28; fi
                    _adv "$_gl"; echo "late $src +${_gl}" >> "$EV"
                fi
            fi
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
                # 6.3.1: VETODOWN=1 — the own-view veto's batch read fails (connection refused, no latency)
                if [[ "$m" == "batch" && "${VETODOWN:-0}" == "1" ]]; then echo "vetodown t=$t" >> "$EV"; return 7; fi
                # 6.3.1 fix round 1 (R2 — the panel's AV-2 knob, ported from its verifier): REFMODE=down|tmo|garb
                # fails ONLY local_check_delinquency's LOCAL finalized getSlot (the MAX_DELINQUENT_SLOTS reference —
                # FUNCNAME, so Tier-1's log-only getSlot is untouched) in [REFFROM, REFTO): down = refused (rc 7,
                # no latency); tmo = a timeout at its -m bound; garb = a JSON-RPC error body
                if [[ -n "${REFMODE:-}" && "$m" == "getSlot" && "$comm" == "default" && " ${FUNCNAME[*]} " == *" local_check_delinquency "* && $t -ge ${REFFROM:--1} && $t -lt ${REFTO:--1} ]]; then
                    echo "ref-fail t=$t mode=$REFMODE" >> "$EV"
                    case "$REFMODE" in
                        down) return 7 ;;
                        tmo) _adv "$mt"; return 28 ;;
                        garb) printf '%s' '{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"},"id":1}'; return 0 ;;
                    esac
                fi
                # the spare's own node at t: hp/hf/hc = processed/finalized/confirmed head, vp/vf/vc = the
                # holder's lastVote in those banks, mo = own optimistic slot, oo = the latest optimistic
                # slot its blockstore observed (getHealth's two sides)
                local mode="${CUTMODE:-none}" c="${CUT:--1}" lag="${LAG:-0}" fz
                [[ $c -lt 0 || $t -le $c ]] && mode=none
                case "$mode" in
                    none) te=$(( t - lag )); hp=$(_slot "$te"); hf=$(( hp - 32 )); hc=$(( hp - 2 ))
                          if [[ -n "${HOLDFROM:-}" && $t -ge $HOLDFROM && $t -lt ${HOLDTO:-0} ]]; then hc=$(( $(_slot "$(( HOLDFROM - lag ))") - 2 )); fi   # fix round 1 (R3): a healthy confirmed-head HOLD
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
                # 6.3.1 (D2-cost): FLICKER=<P> — every P-th second the own node's FINALIZED view (the detection
                # reads: the MAX_DELINQUENT_SLOTS reference and the own-bank payload) answers from a STALE bank,
                # 15 s after the holder's latest landed vote (the holder reads current there under both presets:
                # 37 slots < 128, latency 5 < 15); confirmed/processed stay live. A flickering own bank.
                if [[ -n "${FLICKER:-}" && "$comm" == "default" && ( "$m" == "getSlot" || "$m" == "getVoteAccounts" ) ]] && [[ $(( t % FLICKER )) -eq 0 ]]; then
                    local _fte; _fte=$(( $(_hv "$t") + 15 )); hf=$(( $(_slot "$_fte") - 32 )); vf=$(_hvs $(( _fte - _FL )))
                    echo "flicker t=$t" >> "$EV"
                fi
                case "$m" in
                    batch)   # 6.3.1: the own-view veto — [getSlot{confirmed}, getVoteAccounts{confirmed, votePubkey}], ids echoed
                        ida=${d#*\"id\":}; ida=${ida%%,*}; idb=${d##*\"id\":}; idb=${idb%%,*}
                        printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":%s}]' "$ida" "$hc" "$idb" "$(_gvaf "$hc" "$vc")" ;;
                    getHealth)
                        if [[ $mo -ge $(( oo - ${DIST:-128} )) ]]; then printf '{"jsonrpc":"2.0","result":"ok","id":1}'; else printf '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by %s slots","data":{"numSlotsBehind":%s}},"id":1}' "$(( oo - mo ))" "$(( oo - mo ))"; fi ;;
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
            local tm="${TIERMODE:-splice}" ts bp bf hvp hvf fz _tl="${TLAG:-0}"
            case "$src" in T2) tm=${T2MODE:-$tm}; _tl=${T2TLAG:-$_tl} ;; T3) tm=${T3MODE:-$tm}; _tl=${T3TLAG:-$_tl} ;; esac   # fix round 2 (S1): per-tier modes
            # 6.3 fix round 2 (the delta panel's knob): STALLFROM/STALLTO — the tiers' view STALLS (served as of STALLFROM) and then resumes live
            if [[ $t -ge ${STALLFROM:--1} && $t -lt ${STALLTO:--1} ]]; then t=$STALLFROM; fi
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
                ts=$(( t - _tl ))
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
                    local _gcn=""; case "$src" in T2) _gcn=${GCN_T2:-${GCN:-}} ;; T3) _gcn=${GCN_T3:-${GCN:-}} ;; esac   # fix round 2 (S2)
                    case "$_gcn" in
                        staked) printf '{"jsonrpc":"2.0","result":[{"pubkey":"S1","gossip":"1.2.3.4:8001"},{"pubkey":"churn","gossip":"9.9.9.9:1"}],"id":1}'; return 0 ;;
                        absent) printf '{"jsonrpc":"2.0","result":[{"pubkey":"churn","gossip":"9.9.9.9:1"}],"id":1}'; return 0 ;;
                    esac
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
            # MEASUREMENT EMULATION of a Block 6.4 placement: the gate runs BEFORE take_staked_identity —
            # so before its first statement, the pre-take own-head sample, and before _fresh_proof_recheck.
            # (6.3.1 fix round 1, the panel's CC-10: this is the GATE-FIRST placement, not the one the
            # [proof-gate] span derivation recommends — after the pre-take sample; its acceptance→mutation
            # span is 58 s (41 s in fix rounds 1-2, whose re-check read one tier's worth; fix round 3 restored
            # the 6.3 build's one sequential call). Armed take and acceptance times in this suite
            # and in docs/SAFETY.md are measured HERE.) NOT shipped wiring: it exists in this suite only to
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
        egap_from=$(grep -m1 ' ek=gap' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/'); egap=$(grep -c ' ek=gap' "$EV")
        eslow_from=$(grep -m1 ' ek=slow' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/'); erate_from=$(grep -m1 ' ek=rate' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/')   # 6.3.1: [elapsed-rate]'s SLOW OWN HEAD / RATE… answers
        t1b=$(grep -m1 ' status=T1:BEHIND ' "$EV" | sed 's/^cycle t=\([0-9]*\).*/\1/')
        tco=$(awk '/^read LOCAL getVoteAccounts/{n=NR} /^MUTATION/{m=NR} END{print n+0, m+0}' "$EV")
        between=$(awk -v range="$tco" 'BEGIN{split(range,x," ")} NR>x[1] && NR<x[2] && /^read LOCAL/{c++} END{print c+0}' "$EV")
        order=$(awk -v range="$tco" 'BEGIN{split(range,x," ")} NR>=x[1] && NR<=x[2] && (/^read/ || /^attempt/ || /^gate-/ || /^MUTATION/) {sub(/ t=[0-9]+/,""); printf "%s;", $0}' "$EV")
        lastlocal=""; [[ -n "$mut" ]] && lastlocal=$(awk '/^read LOCAL getVoteAccounts/{l=$4} /^MUTATION/{print l; exit}' "$EV" | sed 's/t=//')
        voting=""; [[ -n "$mut" && ${RESUME:--1} -ge 0 && $mut -ge ${RESUME:--1} ]] && { if [[ ${STOP:--1} -lt 0 ]]; then voting=$(( mut - RESUME )); else voting="stopped@${STOP}"; fi; }
        petgap=$(awk '/^pet t=/{ split($2,a,"="); t=a[2]+0; if (seen && t-p > g) g=t-p; p=t; seen=1 } END{print g+0}' "$EV")
        # petgap_own (6.3 fix round 2): the widest gap between consecutive pets that spans the own-bank
        # payload read (LOCAL getVoteAccounts) — the segment the MAX_DELINQUENT_SLOTS reference joins
        petgap_own=$(awk '/^pet t=/{ split($2,a,"="); t=a[2]+0; if (seen && own && t-p > g) g=t-p; p=t; seen=1; own=0; next } /^read LOCAL getVoteAccounts/{ own=1 } END{print g+0}' "$EV")
        fholds=$(awk '/^cycle /{ for (i=1;i<=NF;i++) if ($i ~ /^fh=/) { split($i,a,"="); if (a[2]+0 > m) m=a[2]+0 } } END{print m+0}' "$EV")
        tsil=none; [[ -n "$mut" ]] && tsil=$(( mut - $(_hv "$mut") ))
        # hvafter: does the holder vote at or after the mutation (the double-sign exposure)?
        hvafter=na
        if [[ -n "$mut" ]]; then
            hvafter=0
            if [[ -n "${VOTES:-}" ]]; then
                for iv in ${VOTES//,/ }; do b=${iv##*:}; if [[ $b -lt 0 || $b -ge $mut ]]; then hvafter=1; fi; done
            elif [[ ${RESUME:--1} -ge 0 ]]; then
                if [[ ${STOP:--1} -lt 0 || ${STOP:--1} -ge $mut ]]; then hvafter=1; fi
            fi
        fi
        # 6.3.1: the own-view veto (first t:kind, count), the D2 own-bank stamps (first, last, count), the starvation page (first, count), flicker reads
        ovv=$(grep -m1 '^ov-veto ' "$EV" | sed 's/^ov-veto t=\([0-9]*\) kind=\(.*\)/\1:\2/'); ovn=$(grep -c '^ov-veto ' "$EV")
        obf=$(grep -m1 '^ob-current ' "$EV" | sed 's/.*t=//'); obl=$(grep '^ob-current ' "$EV" | tail -1 | sed 's/.*t=//'); obn=$(grep -c '^ob-current ' "$EV")
        # fix round 1: R1's advance stamps (first, last, count), R2's unstamped not-delinquent answers (count), the
        # reference failures (count), and ob_vote_last = the LAST own-bank holder-voting observation of any kind
        # (a positive current read, an advance, a VOTING veto) — the protected window runs from it
        oaf=$(grep -m1 '^ob-advance ' "$EV" | sed 's/.*t=//'); oal=$(grep '^ob-advance ' "$EV" | tail -1 | sed 's/.*t=//'); oan=$(grep -c '^ob-advance ' "$EV")
        onn=$(grep -c '^ob-noev ' "$EV"); rfn=$(grep -c '^ref-fail ' "$EV")
        ovl=$(awk '/^ob-current |^ob-advance |^ov-veto .*kind=voting/ { split($2,a,"="); if (a[2]+0 > m) m=a[2]+0 } END { if (m > 0) print m }' "$EV")
        stv=$(grep -m1 '^starve-page ' "$EV" | sed 's/.*t=//'); stn=$(grep -c '^starve-page ' "$EV"); flk=$(grep -c '^flicker ' "$EV")
        ovage=$(grep -m1 "^ov-clear " "$EV" | sed "s/.*age=//"); ovages=$(grep "^ov-clear " "$EV" | sed "s/.*age=//" | tr "\n" ",")
        echo "ov_age=${ovage:-none}|ov_ages=${ovages}|ov_veto=${ovv:-none}|ov_vetos=$ovn|ob_first=${obf:-none}|ob_last=${obl:-none}|ob_n=$obn|oa_first=${oaf:-none}|oa_last=${oal:-none}|oa_n=$oan|ob_noev=$onn|ref_fails=$rfn|ob_vote_last=${ovl:-none}|starve=${stv:-none}|starve_n=$stn|flickers=$flk|eslow_from=${eslow_from:-none}|erate_from=${erate_from:-none}|hvafter=$hvafter|tsil=$tsil|E=${E:-none}|veto=${veto:-none}|mutation=${mut:-none}|end=$_end|emint=${emint:-none}|eoat=${eoat:-none}|estale_cycles=$estale|estale_from=${estale_from:-none}|cycles_from_stale=$cyc_from|elag_from=${elag_from:-none}|egap_from=${egap_from:-none}|egap_cycles=$egap|t1_behind_from=${t1b:-never}|lhmb=${LOCAL_HEALTH_MAX_BEHIND:-unset}|local_reads_between=$between|own_read_before_mut=${lastlocal:-none}|holder_voting_at_mut=${voting:-no}|giveback=$(grep -m1 '^GIVEBACK' "$EV" | sed 's/.*t=//')|h1=$(grep -m1 '^h1-fence' "$EV" | sed 's/.*t=//')|petgap=$petgap|petgap_own=$petgap_own|pets=$(grep -c '^pet t=' "$EV")|floor_holds=$fholds|order=$order|gate=$(grep -m1 '^gate-accepted' "$EV" | sed 's/^gate-accepted //')"
        rm -rf "$W"
    )
}
# (11a)/(11b) the per-cycle own-bank entry gate and the timing race on today's timer path — FLIPPED by 6.3.1:
# the own view is now ALSO a mutation-edge condition (the veto's ONE bounded LOCAL read, after the re-check)
rdd=$(MDS=0 HORIZON=140 world | tail -1)
rddg=$(GV=true MDS=0 HORIZON=140 world | tail -1)
ra=$(MDS=0 RESUME=112 HORIZON=140 world | tail -1)
rb=$(MDS=0 RESUME=113 HORIZON=140 world | tail -1)
rb124=$(MDS=0 RESUME=124 HORIZON=140 world | tail -1)
rb125=$(MDS=0 RESUME=125 HORIZON=140 world | tail -1)
# the fresh re-check is the ONE sequential sampler call (fix round 3 restored the 6.3 build's: TIER2, TIER3 only on its
# failure — fix round 2's concurrent read, whose two lines landed in either order, was removed)
if [[ "$(field "$rdd" mutation)" == "125" && "$(field "$rdd" local_reads_between)" == "4" ]] \
   && [[ "$(field "$rdd" order)" == "read LOCAL getVoteAccounts;attempt;read LOCAL getSlot;read T2 getVoteAccounts;read LOCAL getSlot;read T2 getVoteAccounts;read LOCAL getSlot;read T2 getVoteAccounts;read LOCAL batch;MUTATION;" ]] \
   && [[ "$(field "$rddg" mutation)" == "125" && "$(field "$rddg" local_reads_between)" == "6" && "$(field "$rddg" order)" == "read LOCAL getVoteAccounts;attempt;read LOCAL getSlot;read T2 getVoteAccounts;read LOCAL getSlot;read T2 other;read LOCAL getSlot;read T3 other;read LOCAL getSlot;read T2 getVoteAccounts;read LOCAL getSlot;read T2 getVoteAccounts;read LOCAL batch;MUTATION;" ]]; then
    ok "(11a) MEASURED (6.3.1 — the D0 finding FLIPPED): the take cycle reads LOCAL getVoteAccounts (finalized — the trigger); attempt_takeover then reads an own-head sample (LOCAL getSlot, confirmed) before EACH of its external reads (fix round 1, R3: before the external confirm (TIER2) and before the fence's vote-FROZEN sample (TIER2)); the take function reads the pre-take own-head sample, the fresh re-check (the ONE sequential sampler call — TIER2 answering, so TIER2 alone; fix round 3 restored it) and the own-view VETO (the LOCAL [getSlot, getVoteAccounts] batch, confirmed) — the last read before set-identity is the spare's own bank: 4 LOCAL reads between the own-bank verdict and the mutation (6.3.1 before fix round 1: 2; the 6.3 build: 0); with GOSSIP_VERIFY=true the advisory's two reads join the cycle and each gets its own sample first (fix round 2, S2: 6; round 1: 5, one sample before the pair), the veto still last"
else
    bad "(11a) dead=$rdd :: gv-on=$rddg"
fi
if [[ "$(field "$ra" E)" == "65" && "$(field "$ra" veto)" == "125" && "$(field "$ra" mutation)" == "none" && "$(field "$rb" mutation)" == "none" && "$(field "$rb" ov_veto)" == "125:voting" ]] \
   && [[ "$(field "$rb124" mutation)" == "none" && "$(field "$rb124" ov_veto)" == "125:voting" && "$(field "$rb125" mutation)" == "125" && "$(field "$rb125" holder_voting_at_mut)" == "0" ]]; then
    ok "(11b) MEASURED timing race (splicer on TIER2/TIER3, the holder RESUMES voting and its votes reach the spare's bank; timer-path mutation scheduled at E+60 = t125) — FLIPPED: resumed at t112 → the finalized own bank reads it current at t125, no attempt; at t113 (the 6.3 build TOOK it at t125 after 12 s of voting) → the veto reads it VOTING in the confirmed view at t125 — held; the boundary moves to the veto's own view: resumed at t124 → vetoed, at t125 — the take's own second — taken (0 s of voting). The finalized lag (32 slots, 13 s) no longer decides; the confirmed view's (this world: 1 s) does"
else
    bad "(11b) resume112=$ra :: resume113=$rb :: resume124=$rb124 :: resume125=$rb125"
fi
# (11b-rate) the SAME race at the MEASURED mainnet rate (≈ 3.7 slots/s, 2026-09-26 — the slot-rate knob): the
# boundaries are facts in SLOTS; their seconds shrink with the rate (T3: every seconds figure names its rate)
rb37a=$(SLOT_NUM=37 SLOT_DEN=10 MDS=0 RESUME=96 HORIZON=160 world | tail -1)
rb37b=$(SLOT_NUM=37 SLOT_DEN=10 MDS=0 RESUME=97 HORIZON=160 world | tail -1)
rb37c=$(SLOT_NUM=37 SLOT_DEN=10 MDS=0 RESUME=104 HORIZON=160 world | tail -1)
rb37d=$(SLOT_NUM=37 SLOT_DEN=10 MDS=0 RESUME=105 HORIZON=160 world | tail -1)
if [[ "$(field "$rb37a" E)" == "45" && "$(field "$rb37a" veto)" == "105" && "$(field "$rb37a" mutation)" == "none" ]] \
   && [[ "$(field "$rb37b" mutation)" == "none" && "$(field "$rb37b" ov_veto)" == "105:voting" && "$(field "$rb37c" ov_veto)" == "105:voting" && "$(field "$rb37d" mutation)" == "105" && "$(field "$rb37d" holder_voting_at_mut)" == "0" ]]; then
    ok "(11b-rate) MEASURED at 3.7 slots/s: the episode opens at t45 (128 slots ≈ 35 s, not 51 s) and the timer path takes at t105; resumed at t96 → the finalized own bank holds it; at t97 (the 6.3 build: taken after 8 s) → vetoed VOTING at t105, and so is t104; at t105 → taken (0 s) — the same one-second veto boundary at the measured rate"
else
    bad "(11b-rate) r96=$rb37a :: r97=$rb37b :: r104=$rb37c :: r105=$rb37d"
fi
# (11c) the same race against the REAL watchdog-elapsed provider under the 6.4-placement emulation. At the
# world's 2.5 slots/s [elapsed-rate] abstains (its smooth head at the assumed rate is never certified — test_own_view (4e)), so
# the D0 question — does the proof mature before the own bank sees the resumption? — is asked of the
# provider with [elapsed-rate] neutered ($WORK/n-rate.sh, from (5)); the shipped provider mints nothing here.
rc1=$(WSCRIPT="$WORK/n-rate.sh" ARMED=1 GATE=1 MDS=0 RESUME=158 HORIZON=185 world | tail -1)
rc2=$(WSCRIPT="$WORK/n-rate.sh" ARMED=1 GATE=1 MDS=0 RESUME=159 HORIZON=185 world | tail -1)
rc2s=$(ARMED=1 GATE=1 MDS=0 RESUME=159 HORIZON=185 world | tail -1)
if [[ "$(field "$rc1" emint)" == "171" && "$(field "$rc1" veto)" == "171" && "$(field "$rc1" mutation)" == "none" ]] \
   && [[ "$(field "$rc2" emint)" == "171" && "$(field "$rc2" gate)" == "t=171 prov=watchdog-elapsed" && "$(field "$rc2" ov_veto)" == "171:voting" && "$(field "$rc2" mutation)" == "none" ]] \
   && [[ "$(field "$rc2s" emint)" == "none" && "$(field "$rc2s" eslow_from)" == "171" && "$(field "$rc2s" mutation)" == "none" ]]; then
    ok "(11c) MEASURED against the REAL provider (armed, paired, G2 unconfigured, the 6.4-placement EMULATION; [elapsed-rate] neutered — it abstains at this world's 2.5 slots/s): the provider mints at t171 (the first sample at t71 + the 100 s floor — the splicer's frozen view passes every layer); resumed at t158 → the finalized own bank holds it at t171; resumed at t159 (the 6.3 build: the gate accepted and the take MUTATED at t171, 12 s into the voting) → the gate accepts, and the own-view VETO reads the holder VOTING at t171 — held: the proof can still mature before the finalized own bank sees the resumption, the confirmed view at the mutation edge no longer can be passed. The SHIPPED provider: SLOW OWN HEAD from t171 — no mint at all at 2.5 slots/s"
else
    bad "(11c) rate-neutered resume158=$rc1 :: resume159=$rc2 :: shipped resume159=$rc2s"
fi
# (11d) the intermittent holder at the wizard's MAX_DELINQUENT_SLOTS=15
rd=$(MDS=15 RESUME=40 STOP=40 HORIZON=130 world | tail -1)
if [[ "$(field "$rd" E)" == "20" && "$(field "$rd" veto)" == "53" && "$(field "$rd" ob_first)" == "53" && "$(field "$rd" ob_last)" == "59" && "$(field "$rd" mutation)" == "119" ]]; then
    ok "(11d) MEASURED — FLIPPED by 6.3.1 (D2): the own-bank 'current' verdict now RE-ANCHORS the countdown: at MAX_DELINQUENT_SLOTS=15 ONE holder vote at t40 reaches the spare's bank (current t53–t59, 7 cycles — the window un-triggers but needs 9 to close the episode), and the take waits a full TAKEOVER_DELAY from the last of them: t119 = t59 + 60 (the 6.3 build: t80 on the ORIGINAL anchor, 40 s after a vote the spare's own bank saw)"
else
    bad "(11d) $rd"
fi
# (11e) the fully cut-off spare after the episode opened (agave getHealth reads ok: its blockstore learns nothing)
re1=$(MDS=0 RESUME=90 CUT=80 CUTMODE=full HORIZON=140 world | tail -1)
re2=$(ARMED=1 GATE=1 MDS=0 RESUME=90 CUT=80 CUTMODE=full HORIZON=200 world | tail -1)
if [[ "$(field "$re1" mutation)" == "none" && "$(field "$re1" ov_veto)" == "125:blind" && "$(field "$re2" mutation)" == "none" && "$(field "$re2" emint)" == "none" && "$(field "$re2" estale_from)" == "171" && "$(field "$re2" estale_cycles)" -gt 0 && "$(field "$re2" estale_cycles)" == "$(field "$re2" cycles_from_stale)" ]]; then
    ok "(11e) MEASURED — a spare FULLY cut off at t80 (after its own bank already showed the holder delinquent) keeps that frozen verdict, and agave's getHealth stays ok (its blockstore observes nothing new): FLIPPED by 6.3.1 (D4 b) on the timer path — the veto reads this spare's confirmed head NOT advancing past its own-head sample → BLIND at t125, no take (the 6.3 build took at t125 with the holder voting since t90 — no spare-side gate held; the exposure left below OWN_HEAD_H is test_own_view (4b-residual)); on the armed elapsed path the REAL provider refuses with STALE REFERENCE from t171 (the first evaluation its 100 s floor allows) on every one of the $(field "$re2" estale_cycles) remaining cycles to the horizon — its two-sided head compare sees the frozen own head fall > N_HEAD behind the live view — and no proof-gated take happens"
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
rh2b=$(MDS=0 RESUME=124 LAG=40 HORIZON=200 world | tail -1)
rh2c=$(MDS=0 RESUME=125 LAG=40 HORIZON=200 world | tail -1)
rh3=$(MDS=0 LAG=60 HORIZON=100 world | tail -1)
rh4=$(ARMED=1 GATE=1 MDS=0 LAG=40 HORIZON=230 world | tail -1)
if [[ "$(field "$rh1" E)" == "105" && "$(field "$rh1" mutation)" == "none" && "$(field "$rh2" mutation)" == "none" && "$(field "$rh2" ov_veto)" == "165:voting" && "$(field "$rh2" t1_behind_from)" == "never" ]] \
   && [[ "$(field "$rh2b" ov_veto)" == "165:voting" && "$(field "$rh2c" mutation)" == "165" && "$(field "$rh2c" holder_voting_at_mut)" == "40" ]] \
   && [[ "$(field "$rh3" t1_behind_from)" == "0" && "$(field "$rh3" E)" == "none" && "$(field "$rh3" mutation)" == "none" && "$(field "$rh3" lhmb)" == "128" ]] \
   && [[ "$(field "$rh4" mutation)" == "none" && "$(field "$rh4" emint)" == "none" && "$(field "$rh4" estale_from)" == "211" && "$(field "$rh4" estale_cycles)" -gt 0 && "$(field "$rh4" estale_cycles)" == "$(field "$rh4" cycles_from_stale)" ]]; then
    ok "(11h) MEASURED — a spare replaying 40 s (100 slots) behind passes Tier-1 (agave reads ok up to 128) and every own-view read lags with it: a holder resumed at t95 is held by the finalized own bank; t115 (the 6.3 build: taken at t165 after 50 s) and t124 are vetoed VOTING at t165 — the veto's confirmed view, 40 s behind, shows them; t125 is TAKEN at t165 after 40 s of voting — RESIDUAL (6.3.1, named in docs/SAFETY.md): the veto testifies about the chain as of this spare's own replay lag, up to the 128 slots getHealth admits at the take cycle's Tier-1 check (≈ 51 s at 2.5 slots/s, ≈ 35 s at 3.7); 60 s (150 slots) behind → Tier-1 BEHIND from t0, no episode (LOCAL_HEALTH_MAX_BEHIND=$(field "$rh3" lhmb): since 6.3.1 the default is agave's 128 and larger values are clamped to it — (11m)); ARMED at 40 s behind with a genuinely silent holder, watchdog-elapsed refuses STALE REFERENCE from its first evaluation (t211) on every cycle to the horizon — no take (availability: a spare more than N_HEAD behind cannot prove by time)"
else
    bad "(11h) lag40-resume95=$rh1 :: resume115=$rh2 :: resume124=$rh2b :: resume125=$rh2c :: lag60=$rh3 :: armed-lag40=$rh4"
fi

# ── (11i)–(11n) the 6.3 DOCUMENTED RESIDUALS (6.3 fix round, T3): each asserted the MEASURED behavior and
# named the remedy that flips it. 6.3.1 landed those remedies (the own-view veto with its advancing-head
# check, the own-bank re-anchor, [elapsed-rate], the LOCAL_HEALTH_MAX_BEHIND clamp): each case below now
# asserts the FLIPPED behavior, measured, and quotes the 6.3-build numbers it replaces; what is still left
# is named where it is measured (test_own_view (4b-residual), (11h) here, docs/SAFETY.md).
#
# (11i) the spare partitioned AFTER the episode opened, together with its tiers (co-frozen). THE MODEL,
# reconciling the panel (F1 / CC-1 / D0-P2 / D0-LAG): on a partition side holding < 2/3 the tower fails its
# depth-8 threshold within ~8 votes, so the spare's processed (= VOTE) bank stops ~8 slots past the cut and
# the co-partitioned tiers' max lastVote stops with it (their side stops voting too); none of the holder's
# majority votes arrive. F1 minted against a LIVE splicer only because the pre-fix world kept the minority
# processed head advancing forever; against a live view the physical spare reads STALE REFERENCE (ri4).
# FLIPPED by 6.3.1 on BOTH paths (the remedies this case named — the own-head advance and the own-bank
# confirmed-head progress floor — are the veto's check (b) and [elapsed-rate]): the timer path's veto reads
# the frozen confirmed head not advancing (blind); armed, [elapsed-rate] answers SLOW OWN HEAD (0 slots/s),
# and with it neutered the veto still refuses the minted proof's take — two refusals on ONE input (this spare's own
# confirmed head), not two independent ones (6.3.1 fix round 1, the panel's CC-6(c); fix round 2, CK-4).
ri1=$(TIERMODE=cofrozen CUT=80 CUTMODE=minority RESUME=90 MDS=0 HORIZON=200 world | tail -1)
ri2=$(TIERMODE=cofrozen CUT=80 CUTMODE=minority RESUME=90 MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
ri2n=$(WSCRIPT="$WORK/n-rate.sh" TIERMODE=cofrozen CUT=80 CUTMODE=minority RESUME=90 MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
ri3=$(TIERMODE=cofrozen CUT=80 CUTMODE=minority MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
ri4=$(CUT=80 CUTMODE=minority RESUME=90 MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
ri5=$(TIERMODE=cofrozen CUT=66 CUTMODE=minority RESUME=90 MDS=0 HORIZON=200 world | tail -1)
ri6=$(TIERMODE=cofrozen CUT=66 CUTMODE=minority RESUME=90 MDS=0 ARMED=1 GATE=1 HORIZON=200 world | tail -1)
if [[ "$(field "$ri1" E)" == "65" && "$(field "$ri1" mutation)" == "none" && "$(field "$ri1" ov_veto)" == "125:blind" ]] \
   && [[ "$(field "$ri2" emint)" == "none" && "$(field "$ri2" eslow_from)" == "171" && "$(field "$ri2" mutation)" == "none" ]] \
   && [[ "$(field "$ri2n" emint)" == "171" && "$(field "$ri2n" gate)" == "t=171 prov=watchdog-elapsed" && "$(field "$ri2n" ov_veto)" == "171:blind" && "$(field "$ri2n" mutation)" == "none" ]] \
   && [[ "$(field "$ri3" mutation)" == "none" && "$(field "$ri3" eslow_from)" == "171" ]] \
   && [[ "$(field "$ri4" mutation)" == "none" && "$(field "$ri4" emint)" == "none" && "$(field "$ri4" estale_from)" == "171" && "$(field "$ri4" estale_cycles)" -gt 0 && "$(field "$ri4" estale_cycles)" == "$(field "$ri4" cycles_from_stale)" ]] \
   && [[ "$(field "$ri5" mutation)" == "none" && "$(field "$ri6" emint)" == "none" && "$(field "$ri6" mutation)" == "none" ]]; then
    ok "(11i) FLIPPED (MEASURED) — the spare and its tiers partitioned together at t80, AFTER the episode opened (E=65) and after the pin (t71), the holder voting on the majority from t90: un-armed the veto reads the frozen confirmed head NOT advancing → BLIND at t125, no take (the 6.3 build: taken at t125, 35 s into the voting); ARMED, [elapsed-rate] answers SLOW OWN HEAD from t171 — no mint (the 6.3 build MINTED at t171 and took 81 s into the voting); with [elapsed-rate] neutered the proof mints at t171 and the gate accepts it, and the veto refuses the take (BLIND) — two refusals on ONE input (the own confirmed head — not independent); a DEAD holder behind the same partition is no longer taken either (availability, correctly: a partitioned spare cannot testify). Against a LIVE view (the splicer) STALE REFERENCE from t171 as before; tiers frozen BEFORE the pin (t66): held on both paths (the tip guard), and armed no mint now (SLOW OWN HEAD)"
else
    bad "(11i) unarmed=$ri1 :: armed=$ri2 :: armed-rate-neutered=$ri2n :: armed-dead=$ri3 :: armed-liveview=$ri4 :: prepin-unarmed=$ri5 :: prepin-armed=$ri6"
fi
# (11j) the LATENCY term Σ (D0-LAT): the splicer answers every tier read of the take cycle at (curl -m) − 1 s,
# from the external-confirm read on (a protocol-aware choice — that read carries no commitment), legal
# within every bound. The own bank is read ONCE, at the take cycle's start.
# FLIPPED by 6.3.1 (D3 — the mutation-edge own-bank re-read this case named, (c-after), is the own-view veto):
# the take cycle's tier latency no longer stretches the exposure — the veto reads the spare's own bank AFTER
# every tier read, and a holder voting by then is seen in the confirmed view. Fix round 1 (R3) re-pinned the
# TIER2-blackholed pair: the re-check asked the pinned vantage (TIER3) first — one read, not a TIER2 timeout
# plus TIER3 — so the pre-take sample was 9 s old at the veto instead of 19+ (r113 vetoed VOTING at t172; a
# DEAD holder taken at t172; before fix round 1: BLIND at t182, never taken). Fix round 2 (S1) read both tiers
# AT ONCE (the pinned-first order skipped a recovered TIER2 showing the holder voting — the delta panel's DL-1):
# the wall time was the blackholed TIER2's 10 s, the sample 10 s old — r113 vetoed at t173, the dead holder
# taken at t173. Fix round 3 (U1) REMOVED that concurrent read (the delta panel 2's LB-1/LB-2 — it took a voting
# holder) and restored the 6.3 build's one sequential call: TIER2's 10 s timeout, then TIER3's 9 s — the pre-take
# sample is 19+ s old at the veto again: r113 vetoed BLIND at t182, the dead holder NEVER taken (the returning
# AV-6 residual: an intermediary that controls latency can starve the take — docs/SAFETY.md).
rj1=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm MDS=0 RESUME=112 HORIZON=200 world | tail -1)
rj2=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm MDS=0 RESUME=113 HORIZON=200 world | tail -1)
rj2b=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm MDS=0 RESUME=146 HORIZON=200 world | tail -1)
rj2c=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm MDS=0 RESUME=147 HORIZON=200 world | tail -1)
rj3=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm GV=true MDS=0 RESUME=113 HORIZON=220 world | tail -1)
rj4=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm T2DOWN=1 MDS=0 RESUME=113 HORIZON=260 world | tail -1)
rj4d=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm T2DOWN=1 MDS=0 HORIZON=300 world | tail -1)
rj6=$(WSCRIPT="$WORK/n-rate.sh" SPLICE_DELAY=max SPLICE_SEL=afterconfirm ARMED=1 GATE=1 MDS=0 RESUME=169 HORIZON=260 world | tail -1)
# the SHIPPED twin (T9) at a certified 3.7 slots/s — the rate layer passes, the edge veto decides
rj6s=$(SLOT_NUM=37 SLOT_DEN=10 SPLICE_DELAY=max SPLICE_SEL=afterconfirm ARMED=1 GATE=1 MDS=0 RESUME=169 HORIZON=260 world | tail -1)
rj6sd=$(SLOT_NUM=37 SLOT_DEN=10 SPLICE_DELAY=max SPLICE_SEL=afterconfirm ARMED=1 GATE=1 MDS=0 HORIZON=260 world | tail -1)
if [[ "$(field "$rj1" veto)" == "125" && "$(field "$rj1" mutation)" == "none" ]] \
   && [[ "$(field "$rj2" mutation)" == "none" && "$(field "$rj2" ov_veto)" == "147:voting" && "$(field "$rj2b" ov_veto)" == "147:voting" && "$(field "$rj2c" mutation)" == "147" && "$(field "$rj2c" holder_voting_at_mut)" == "0" ]] \
   && [[ "$(field "$rj3" mutation)" == "none" && "$(field "$rj3" ov_veto)" == "175:voting" && "$(field "$rj4" mutation)" == "none" && "$(field "$rj4" ov_veto)" == "182:blind" ]] \
   && [[ "$(field "$rj4d" mutation)" == "none" && "$(field "$rj4d" ov_veto)" == "182:blind" && "$(field "$rj4d" end)" == "horizon" ]] \
   && [[ "$(field "$rj6" emint)" == "181" && "$(field "$rj6" mutation)" == "none" && "$(field "$rj6" ov_veto)" == "203:voting" ]] \
   && [[ "$(field "$rj6s" emint)" == "161" && "$(field "$rj6s" mutation)" == "none" && "$(field "$rj6s" ov_veto)" == "183:voting" && "$(field "$rj6sd" mutation)" == "183" ]]; then
    ok "(11j) FLIPPED (MEASURED) — the intermediary controls LATENCY (every take-cycle tier read at its curl -m − 1 s): the take still lands at t147 (Σ = 22 s after the own-bank read at t125), but the veto at t147 reads the spare's own bank LAST — r113 is vetoed VOTING (the 6.3 build: taken at t147 after 34 s), and so is r146; only a holder resuming at the take's own second (r147) is taken (0 s). GOSSIP_VERIFY=true → vetoed at t175 (was taken 62 s in); TIER2 blackholed → the re-check is the ONE sequential call (fix round 3 restored it: TIER2's 10 s timeout, then TIER3's 9 s), the pre-take own-head sample is 19+ s old at the veto → r113 vetoed BLIND at t182 (as 6.3.1 before fix round 1; the 6.3 build: taken 69 s in), and a DEAD holder behind that latency is NEVER taken, every veto BLIND to the horizon — the RETURNING residual (AV-6's class, named in docs/SAFETY.md: an intermediary that controls latency can starve the take; fix round 1 took it at t172 by skipping TIER2 — DL-1's regression — and fix round 2 at t173 by the concurrent read — LB-1's; both removed). ARMED ([elapsed-rate] neutered — it abstains at 2.5 slots/s): the proof mints at t181, r169 is vetoed at t203 (was taken 34 s in); the SHIPPED provider at a certified 3.7 slots/s mints at t161 and r169 (resumed inside the tier-slowed take cycle) is vetoed VOTING at the edge at t183, where a dead holder is taken"
else
    bad "(11j) r112=$rj1 :: r113=$rj2 :: r146=$rj2b :: r147=$rj2c :: gv=$rj3 :: t2down=$rj4 :: t2down-dead=$rj4d :: armed-r169=$rj6 :: shipped-3.7-r169=$rj6s :: shipped-3.7-dead=$rj6sd"
fi
# (11j-Σ) 6.3 fix round 5 (P5T-SIGMA50-UNPINNED) pinned the ARMED Σ that docs/SAFETY.md (Finding 1) stated —
# "Σ = 50 s: 22 s of reads + 28 s of pets" (an armed unit, every pet 7 s, the timer path, the splicer
# answering every take-cycle tier read at its curl -m − 1 s): the own bank read at t489, the mutation at t539,
# a holder resumed at t477 taken 62 s into its voting. FLIPPED by 6.3.1: Σ no longer measures the exposure.
# (i) The SAME world now never takes at all — not even a dead holder: every take's pre-take own-head sample
# is 23 s old by the veto read (its own 7 s pet + the re-check's 9 s read + 7 s pet > OWN_HEAD_H 16) → BLIND
# (availability at the house bound-counting; on a real host a pet is milliseconds). (ii) The armed exposure
# that IS left, measured with pets at 7 s and tiers answering at once: the veto read's own pet — the one op
# between the veto's snapshot and set-identity. A dead holder is taken at t609 (the veto read at t602); a
# holder resuming at t601 is vetoed VOTING, at t602 taken at t609 after 7 s. Fix round 1 (R3) re-pinned the
# times, not the shape: each take cycle now carries an own-head sample before each external read, each with
# its own 7 s pet here — the first attempt (span-floor held, as before) runs 14 s longer and so does the take
# cycle (6.3.1 before fix round 1: veto read t574, take t581; the splicer world's first BLIND at t616, now
# t553 — the samples carry the first attempt's fence verdict past the span floor). Fix round 2 (S2) adds the
# liveness probe's own-head sample — one more 7 s pet per take attempt here: the veto read t609, the take t616
# (fix round 1: t602 / t609), a holder resuming at t608 vetoed VOTING, at t609 taken after 7 s; the splicer
# world's first BLIND t560 (fix round 1: t553). Fix round 2's concurrent re-check read TIER3 beside TIER2 with its
# pet overlapping TIER2's (no time added); fix round 3's restored one sequential call reads TIER2 alone here (it
# answers) — the same times.
rjs1=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm ARMED=1 GATE=0 PETS=7 MDS=0 RESUME=477 HORIZON=600 world | tail -1)
rjsd=$(SPLICE_DELAY=max SPLICE_SEL=afterconfirm ARMED=1 GATE=0 PETS=7 MDS=0 HORIZON=700 world | tail -1)
rp7d=$(ARMED=1 GATE=0 PETS=7 MDS=0 HORIZON=700 KEEPEV="$WORK/ev.p7" world | tail -1)
rp08=$(ARMED=1 GATE=0 PETS=7 MDS=0 RESUME=608 HORIZON=700 world | tail -1)
rp09=$(ARMED=1 GATE=0 PETS=7 MDS=0 RESUME=609 HORIZON=700 world | tail -1)
vt=$(grep '^read LOCAL batch' "$WORK/ev.p7" 2>/dev/null | tail -1 | sed 's/.*t=//')
if [[ "$(field "$rjs1" mutation)" == "none" && "$(field "$rjsd" mutation)" == "none" && "$(field "$rjsd" ov_veto)" == "560:blind" ]] \
   && [[ "$(field "$rp7d" mutation)" == "616" && "$vt" == "609" && "$(field "$rp7d" order)" == *"read LOCAL batch;MUTATION;" ]] \
   && [[ "$(field "$rp08" mutation)" == "none" && "$(field "$rp08" ov_veto)" == "616:voting" && "$(field "$rp09" mutation)" == "616" && "$(field "$rp09" holder_voting_at_mut)" == "7" ]]; then
    ok "(11j-Σ) FLIPPED (MEASURED) — the armed Σ world (every pet 7 s, the splicer at curl -m − 1 s): the holder resumed at t477 is NOT taken (the 6.3 build: t539, 62 s into its voting — Σ = 50 s), and neither is a DEAD holder: every veto BLIND (first at t560 — the pre-take sample 23 s old at the house bound-counting: its 7 s pet + the re-check's 9 s read (TIER2's — the one sequential call) + 7 s pet; availability, named in docs/SAFETY.md). The armed exposure left is the veto's own pet: with 7 s pets and prompt tiers the veto reads at t609 and the take lands at t616 (fix round 1: t602 / t609; 6.3.1 before fix round 1: t574 / t581 — the per-read samples cost a 7 s pet each at this house bound-counting, milliseconds on a host); a holder resuming at t608 is vetoed VOTING, at t609 taken after 7 s — Σ (was 50 s) is now at most one pet (+ the confirmed view's own lag)"
else
    bad "(11j-Σ) r477=$rjs1 :: dead=$rjsd :: pets7-dead=$rp7d (veto read t=${vt:-?}) :: r608=$rp08 :: r609=$rp09"
fi
# (11k) an HONEST tier lagging but advancing (D0-LAG, the TLAG rows) — replaces the incoherent "partitioned
# together, live tip" premise: TIER2/TIER3 serve the TRUE chain TLAG seconds late; no adversary.
# FLIPPED by 6.3.1: the mutation-edge own-bank re-read (c-after) landed — the own-view veto.
rk1=$(TIERMODE=honest TLAG=40 MDS=0 RESUME=112 HORIZON=200 world | tail -1)
rk2=$(TIERMODE=honest TLAG=40 MDS=0 RESUME=113 HORIZON=200 world | tail -1)
rk3=$(TIERMODE=honest TLAG=10 MDS=0 RESUME=115 HORIZON=200 world | tail -1)
rk4=$(TIERMODE=honest TLAG=10 MDS=0 RESUME=116 HORIZON=200 world | tail -1)
rk5=$(TIERMODE=honest MDS=0 HORIZON=200 world | tail -1)
rk6=$(TIERMODE=honest TLAG=40 MDS=0 ARMED=1 GATE=1 HORIZON=260 world | tail -1)
if [[ "$(field "$rk1" mutation)" == "none" && "$(field "$rk1" veto)" == "125" && "$(field "$rk2" mutation)" == "none" && "$(field "$rk2" ov_veto)" == "125:voting" ]] \
   && [[ "$(field "$rk3" mutation)" == "none" && "$(field "$rk4" mutation)" == "none" && "$(field "$rk4" ov_veto)" == "125:voting" && "$(field "$rk5" mutation)" == "125" ]] \
   && [[ "$(field "$rk6" mutation)" == "none" && "$(field "$rk6" emint)" == "none" && "$(field "$rk6" elag_from)" == "171" ]]; then
    ok "(11k) FLIPPED (MEASURED) — an HONEST tier 40 s behind (still advancing), no adversary, an un-armed install: r112 held by the finalized own bank at t125; r113 (the 6.3 build: taken at t125 after 12 s) is vetoed VOTING at t125 by the confirmed own view; 10 s behind: r115 caught by the tiers, r116 (was taken after 9 s) vetoed VOTING; the honest dead-holder control still takes at t125. ARMED at 40 s behind watchdog-elapsed reads LAGGED VIEW from t171 on (lag > N_HEAD = 22 slots, 8.8 s at 2.5 slots/s) — no mint, no take"
else
    bad "(11k) tlag40-r112=$rk1 :: tlag40-r113=$rk2 :: tlag10-r115=$rk3 :: tlag10-r116=$rk4 :: dead=$rk5 :: armed=$rk6"
fi
# (11l) the ARMED intermittent holder (D0-INTERMIT-ARMED): MAX_DELINQUENT_SLOTS=15, ONE holder vote at t40
# that reaches the spare's own bank (current t53–t59), the splicer on the tiers.
# FLIPPED by 6.3.1 (D2 ii — the own-bank 'current' verdict restarts the span, (b')): measured with [elapsed-rate]
# neutered (it abstains at this world's 2.5 slots/s and would mask it); the shipped provider mints nothing here.
rl1=$(WSCRIPT="$WORK/n-rate.sh" ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200 world | tail -1)
rl1s=$(ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200 world | tail -1)
if [[ "$(field "$rl1" veto)" == "53" && "$(field "$rl1" ob_last)" == "59" && "$(field "$rl1" emint)" == "159" && "$(field "$rl1" mutation)" == "159" && "$(field "$rl1" gate)" == "t=159 prov=watchdog-elapsed" ]] \
   && [[ "$(field "$rl1s" emint)" == "none" && "$(field "$rl1s" mutation)" == "none" ]]; then
    ok "(11l) FLIPPED (MEASURED) — armed, the intermittent holder: the own bank reads the t40 vote current t53–t59, and every such read restarts watchdog-elapsed's silence ([elapsed-own]): with [elapsed-rate] neutered the proof mints at t159 = t59 + the 100 s floor and the gated take mutates then — 119 s after the vote the spare's own bank saw (the 6.3 build minted at t126, 86 s after it: '100 s of silence' overstated by 14 s); the SHIPPED provider mints nothing here (SLOW OWN HEAD at 2.5 slots/s)"
else
    bad "(11l) rate-neutered=$rl1 :: shipped=$rl1s"
fi
# (11m) LOCAL_HEALTH_MAX_BEHIND > 128 (CC-4 = D0-LHMB): a spare 60 s (150 slots) behind, the holder resuming at t150.
# FLIPPED by 6.3.1 (D5 — the clamp this case named): 200 is clamped to the node's own health-check distance (128
# here); since its fix round 1 (L3) every "behind" report is not ready — the knob enters no decision.
rm1=$(LAG=60 LHMB=200 RESUME=150 MDS=0 HORIZON=260 world | tail -1)
rm2=$(LAG=60 LHMB=128 RESUME=150 MDS=0 HORIZON=260 world | tail -1)
rm3=$(LAG=60 RESUME=150 MDS=0 HORIZON=260 world | tail -1)
if [[ "$(field "$rm1" lhmb)" == "200" && "$(field "$rm1" t1_behind_from)" == "0" && "$(field "$rm1" E)" == "none" && "$(field "$rm1" mutation)" == "none" ]] \
   && [[ "$(field "$rm2" t1_behind_from)" == "0" && "$(field "$rm2" mutation)" == "none" && "$(field "$rm3" lhmb)" == "128" && "$(field "$rm3" t1_behind_from)" == "0" && "$(field "$rm3" mutation)" == "none" ]]; then
    ok "(11m) FLIPPED (MEASURED) — LOCAL_HEALTH_MAX_BEHIND=200 is CLAMPED to the node's health-check distance, agave's 128 here (the M9 announce became the clamp; its bands: test_config_drift (h)): the spare 150 slots behind is Tier-1 BEHIND from t0, no episode, no take (the 6.3 build: Tier-1 passed it, the episode opened at t125 and the take mutated at t185, 35 s into the holder's voting); 128 and the new default 128 the same"
else
    bad "(11m) lhmb200=$rm1 :: lhmb128=$rm2 :: default=$rm3"
fi
# (11n) P1b with a FORGED G2 on the default (shared) vantages (D0-P1B): the spare fully cut off at t80, the
# holder voting from t90, the intermediary forging the unstaked-identity flip once the episode is open.
# FLIPPED by 6.3.1 (D4 b — the own-head advance this case named, at the take on every path): P1b's take is
# refused by the veto (this spare's confirmed head is not advancing), the forged-G2 take included.
rn1=$(MDS=0 RESUME=90 CUT=80 CUTMODE=full HORIZON=200 world | tail -1)
rn2=$(ARMED=1 GATE=1 G2FORGE=1 MDS=0 RESUME=90 CUT=80 CUTMODE=full HORIZON=200 world | tail -1)
rn3=$(ARMED=1 GATE=1 G2FORGE=1 MDS=0 RESUME=90 CUT=80 CUTMODE=full POSTTAKE=1 HORIZON=220 world | tail -1)
rn4=$(MDS=0 CUT=30 CUTMODE=full HORIZON=200 world | tail -1)
if [[ "$(field "$rn1" mutation)" == "none" && "$(field "$rn1" ov_veto)" == "125:blind" ]] \
   && [[ "$(field "$rn2" mutation)" == "none" && "$(field "$rn2" gate)" == "t=132 prov=verified-demote" && "$(field "$rn2" ov_veto)" == "132:blind" ]] \
   && [[ "$(field "$rn3" mutation)" == "none" && "$(field "$rn3" giveback)" == "" ]] \
   && [[ "$(field "$rn4" E)" == "none" && "$(field "$rn4" mutation)" == "none" ]]; then
    ok "(11n) FLIPPED (MEASURED) — P1b: the cut-off spare's veto reads its own confirmed head NOT advancing → BLIND at t125, no take (the 6.3 build: taken at t125, the holder voting 35 s); ARMED with G2 on the default (shared) vantages the forged flip still PROVES verified-demote and the gate accepts it at t132 — and the veto refuses the take (BLIND; the 6.3 build took it, the holder voting 42 s, and the promoted spare's H1 gave it back only at t168); nothing to give back now. P1a (cut at t30, BEFORE any episode, the holder dead): no episode ever opens — a silent availability loss, no page (unchanged)"
else
    bad "(11n) p1b-unarmed=$rn1 :: g2forge=$rn2 :: posttake=$rn3 :: p1a=$rn4"
fi

# ── (12) the 6.3 fix round's mechanism reds, re-run green ──────────────────────────────────────
echo ""; echo "─── (12) fix round 1: M2 post-read starts / M3 → R1 observed_at (the evaluation start again) + the tail / M4 through the loop / M5 exit code / M6 pet gap / M8 status ───"
# (12a) M2 (F2) — the silence START stamped AFTER the read that established it. The world: honest tiers,
# MAX_DELINQUENT_SLOTS=15, a holder ALIVE (each vote landing 20 slots behind the head — delinquent to the
# spare, under its own 32-slot vote-lag fence) until STOP; the Gate-3 read at t135 hits one T2 timeout
# (curl -m 10) and T3 answers T3LAT s late carrying the holder's last votes. Pre-fix red (de21927):
# T3LAT=5 STOP=149 → the proof-gated take at t235 = 86 s after the holder's last vote (< W+B = 90);
# T3LAT=1 STOP=145 → t235 = 90 s; the slow-PIN world (the prefetch pin at t71 taking 19 s) → mint t171.
# 6.3.1: the armed rows run with [elapsed-rate] neutered ($WORK/n-rate.sh, from (5)) — at the world's 2.5
# slots/s it abstains on every one of them (a smooth head at the assumed rate is never certified), which would mask the M2
# mechanism these rows measure; (12a-rate) pins that the SHIPPED provider mints none of them.
# 6.3.1 fix round 1 (R1): an own-bank lastVote ADVANCE inside the open episode now stamps D2. In these worlds
# the holder votes (20 slots late) INTO the episode, so the countdown re-anchors on every advance through t162
# (the holder's last vote reaching this node's finalized bank) and the slow read at t135 never lands on a take
# path. The three M2 rows therefore run with BOTH [elapsed-rate] and the R1 advance stamp neutered
# ($WORK/n-rate-adv.sh — the silence clock alone, as the rows were written); (12a-r1) pins the shipped stamp
# in the same worlds and re-measures M2 where the take path now reads.
M_ADV='s/^    if _canon_uint "\${_own_bank_max_vote:-}" && \[\[ \$1 -gt \$_own_bank_max_vote \]\]; then$/    if false; then/'
mutate "$WORK/n-rate.sh" "$M_ADV" "$WORK/n-rate-adv.sh"
ra1=$(WSCRIPT="$WORK/n-rate-adv.sh" TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=149 SLOWFROM=135 SLOWTO=136 T3LAT=5 ARMED=1 GATE=1 HORIZON=330 world | tail -1)
ra2=$(WSCRIPT="$WORK/n-rate-adv.sh" TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=145 SLOWFROM=135 SLOWTO=136 T3LAT=1 ARMED=1 GATE=1 HORIZON=330 world | tail -1)
ra3=$(WSCRIPT="$WORK/n-rate-adv.sh" TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=134 ARMED=1 GATE=1 HORIZON=330 world | tail -1)
ra4=$(WSCRIPT="$WORK/n-rate.sh" SLOWFROM=71 SLOWTO=72 T3LAT=9 MDS=0 ARMED=1 GATE=1 HORIZON=260 world | tail -1)
ra5=$(SLOWFROM=71 SLOWTO=72 T3LAT=9 MDS=0 HORIZON=200 world | tail -1)
sil1=$(( $(field "$ra1" mutation) - 149 )); sil2=$(( $(field "$ra2" mutation) - 145 )); sil3=$(( $(field "$ra3" mutation) - 134 ))
if [[ "$(field "$ra1" emint)" == "250" && "$(field "$ra1" gate)" == "t=250 prov=watchdog-elapsed" && $sil1 -ge 100 ]] \
   && [[ "$(field "$ra2" emint)" == "246" && $sil2 -ge 100 && "$(field "$ra3" mutation)" == "235" && $sil3 -ge 100 ]]; then
    ok "(12a) M2 ([elapsed-rate] and the R1 advance stamp neutered) — F2's slow-observing read (one T2 timeout on the Gate-3 read at t135, T3 answering 5 s late with the holder's last votes; the holder silent after t149): the VOTING re-pin now stamps the ANSWER's arrival (t150), so watchdog-elapsed mints and the proof-gated take lands at t250 — ${sil1} s after the holder's last vote (>= W+B+MARGIN_ELAPSED = 100); T3LAT=1/STOP=145 → t246 (${sil2} s); the no-slow-read control is unchanged at t235 (${sil3} s). Pre-fix: t235 in the first two = 86 s and 90 s (< / = W+B = 90)"
else
    bad "(12a) t3lat5=$ra1 :: t3lat1=$ra2 :: control=$ra3"
fi
rr1=$(WSCRIPT="$WORK/n-rate.sh" TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=149 SLOWFROM=135 SLOWTO=136 T3LAT=5 ARMED=1 GATE=1 HORIZON=380 world | tail -1)
rr2=$(WSCRIPT="$WORK/n-rate.sh" TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=149 SLOWFROM=222 SLOWTO=223 T3LAT=5 ARMED=1 GATE=1 HORIZON=380 world | tail -1)
if [[ "$(field "$rr1" oa_last)" == "162" && "$(field "$rr1" emint)" == "322" && "$(field "$rr1" mutation)" == "322" && "$(field "$rr1" hvafter)" == "0" ]] \
   && [[ "$(field "$rr2" oa_last)" == "162" && "$(field "$rr2" emint)" == "337" && "$(field "$rr2" mutation)" == "337" ]]; then
    ok "(12a-r1) the SHIPPED R1 advance stamp in the (12a) world ([elapsed-rate] neutered): the own bank's lastVote advances re-anchor the countdown through t162 (the holder's last vote, t149, reaching this node's finalized bank), so the slow read at t135 never lands on a take path; the first take cycle (t222 = t162 + TAKEOVER_DELAY) finds the TIER2/TIER3 fence's pin (taken while the holder still voted) behind → a VOTING re-pin and a second full delay, and the mint lands 100 s after that re-pin: t322 = $(( $(field "$rr1" mutation) - 149 )) s after the holder's last vote (6.3.1 as first shipped: t250 = 101 s). NAMED COST: two re-anchors in series for a holder that voted late into the episode. M2 on the shipped stamp: the same slow read moved onto that re-pin (T2 timeout + T3 5 s at t222) → the silence starts at the ANSWER's arrival (t237) and the mint lands at t337"
else
    bad "(12a-r1) shipped-stamp F2=$rr1 :: slow re-pin=$rr2"
fi
if [[ "$(field "$ra4" emint)" == "190" && "$(field "$ra4" mutation)" == "190" && "$(field "$ra5" mutation)" == "135" && "$(field "$ra5" floor_holds)" == "0" ]]; then
    ok "(12a-pin) M2 ([elapsed-rate] neutered) at the attempt_takeover PREFETCH PIN (the pin read at t71 costs a T2 timeout + 9 s of T3 latency): the observed-span start is the answer's arrival (t90), so the provider mints at t190 (pre-fix t171 — the 19 s the read took counted as observed silence); the un-armed take in THIS world is unchanged at t135 with zero span-floor holds — only because its pin lands on T3 and the take cycle's T2 sample flips provider (the 10 s re-pin wait covers the floor). Elsewhere M2 DOES make the span floor bind where it did not — always later: (13e)"
else
    bad "(12a-pin) armed=$ra4 :: unarmed=$ra5"
fi
ra1s=$(TIERMODE=honest HLAGS=20 MDS=15 RESUME=0 STOP=149 SLOWFROM=135 SLOWTO=136 T3LAT=5 ARMED=1 GATE=1 HORIZON=330 world | tail -1)
ra4s=$(SLOWFROM=71 SLOWTO=72 T3LAT=9 MDS=0 ARMED=1 GATE=1 HORIZON=260 world | tail -1)
if [[ "$(field "$ra1s" emint)" == "none" && "$(field "$ra1s" mutation)" == "none" && "$(field "$ra4s" emint)" == "none" && "$(field "$ra4s" mutation)" == "none" ]]; then
    ok "(12a-rate) the SHIPPED provider in the same worlds (2.5 slots/s): no mint, no proof-gated take in either — [elapsed-rate] abstains at exactly the assumed rate (test_own_view (4e)); the M2 rows above measure the silence clock with that layer out of the way"
else
    bad "(12a-rate) shipped F2=$ra1s :: shipped pin=$ra4s"
fi

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

# (12c) R1 (6.3 fix round 2 — REG-A): observed_at is the EVALUATION START again. Fix round 1's M3 stamped
# the answering read's own pre-read stamp instead — up to one T2 timeout LATER — and so the edge admitted
# a verdict the evaluation-start stamp refuses: a loosening, reverted. A file clock: T2 times out at its
# 10 s bound, T3 answers 10 s late, the own-bank head is local and instant, pets free. Pre-fix red
# (f22d492): observed_at=+160 (T3's pre-read stamp), 49 s old at the edge after 6.1's 39 s → ACCEPTED.
case_r1() {
    reg; prime_seam 0 none
    _liveness_first_provider="T3"                                          # the episode pinned to T3 (a T2-down episode) — fixture write
    _SIM_NOW=$(( T0 + 150 )); fileclock_on
    T2_DOWN=1; LAT_T3=10; LAT_LOCAL=0; PETCOST=0
    _elapsed_step
    local mint; mint=$(cat "$CLKF")
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    _clk_adv 39                                                            # 6.1's census: acceptance slack 3 + recheck R_worst 36
    local ew=""; log_warn() { ew="$*"; }
    _proof_age_edge_check; local erc=$?
    echo "a=$_elapsed_answer|oat=$(_proof_field "$v" observed_at)|mint=$mint|grc=$grc|erc=$erc|ew=$ew"
}
r=$(drive_ep "$STANDBY" case_r1 | tail -1)
if [[ "$(field "$r" a)" == "yes" && "$(field "$r" oat)" == "$(( T0 + 150 ))" && "$(field "$r" mint)" == "$(( T0 + 170 ))" && "$(field "$r" grc)" == "0" ]] \
   && [[ "$(field "$r" erc)" == "1" && "$(field "$r" ew)" == *"verdict age 59s"* ]]; then
    ok "(12c) R1 — observed_at is the EVALUATION START (+150), not the answering read's pre-read stamp: T2 timing out (10 s) and T3 answering 10 s late mint at +170; after 6.1's acceptance slack + recheck R_worst (39 s) the edge check REFUSES it (verdict age 59 s > PROOF_MAX_AGE 50). Pre-fix (M3): observed_at=+160, age 49 s → ACCEPTED — the loosening R1 reverts"
else
    bad "(12c) $r"
fi
# (12c-tail) the TAIL census at the house bound-counting (a pet = 7 s; PETSEQF sets each pet in order):
# the sampler's two pets 7 s, T2 timing out (10 s), T3 at its 10 s bound. The head read's own op + pet
# decide: within ELAPSED_HEAD_GAP_MAX (a 1 s pet) the worst MINTING evaluation; at its full bound (curl
# -m 5 + a 7 s pet) the worst evaluation — which R3 turns into HEAD GAP, blind. Pre-fix red (f22d492):
# the full-bound evaluation MINTED at +196 (observed_at +167). Fix round 2 (S2): the split read takes an
# [own-view] own-head sample between TIER2's failure and TIER3 — at the house bound-counting its read at
# ITS -m 2 bound + a 7 s pet: 9 s more tail in both rows (the minting row +185 -> +194, the full-bound
# row's clock +196 -> +205; the gap layer does not see it — the sample precedes the payload read).
case_r1tail() {   # HEADLAT / HEADPET: the head read's latency and its own pet (s)
    reg; prime_seam 0 none
    _liveness_first_provider="T3"
    _SIM_NOW=$(( T0 + 150 )); fileclock_on
    T2_DOWN=1; LAT_T3=10; LAT_LOCAL=${HEADLAT:-0}; LAT_OHS=2
    PETSEQF="$WORK/petseq.$HEADLAT.$HEADPET"; printf '7\n7\n7\n%s\n' "$HEADPET" > "$PETSEQF"   # TIER2's pet, the S2 own-head sample's (fix round 2), TIER3's, the head read's
    _elapsed_step
    local mint; mint=$(cat "$CLKF")
    local v; v=$(_elapsed_provider)
    require_relinquish_proof; local grc=$?
    _clk_adv 39
    local ew=""; log_warn() { ew="$*"; }
    _proof_age_edge_check; local erc=$?
    echo "a=$_elapsed_answer|r=$_elapsed_reason|oat=$(_proof_field "$v" observed_at)|mint=$mint|grc=$grc|erc=$erc|ew=$ew"
}
rt1=$(HEADLAT=0 HEADPET=1 drive_ep "$STANDBY" case_r1tail | tail -1)
rt2=$(HEADLAT=5 HEADPET=7 drive_ep "$STANDBY" case_r1tail | tail -1)
if [[ "$(field "$rt1" a)" == "yes" && "$(field "$rt1" oat)" == "$(( T0 + 150 ))" && "$(field "$rt1" mint)" == "$(( T0 + 194 ))" && "$(field "$rt1" grc)" == "0" && "$(field "$rt1" erc)" == "1" && "$(field "$rt1" ew)" == *"verdict age 83s"* ]] \
   && [[ "$(field "$rt2" a)" == "blind" && "$(field "$rt2" r)" == "HEAD GAP: the head read landed 12s after the payload read"* && "$(field "$rt2" mint)" == "$(( T0 + 205 ))" ]]; then
    ok "(12c-tail) the tail from observed_at to the mint, MEASURED on the file clock at the house bound-counting: the worst MINTING evaluation (the head read + its pet inside ELAPSED_HEAD_GAP_MAX) mints at +194 — TAIL 44 s (fix round 2's own-head sample in the split read, its -m 2 bound + a 7 s pet: 35 s before) — the gate accepts it at the mint, and the edge refuses it (age 83 s > 50); the worst evaluation (the head read at its curl -m 5 bound + a 7 s pet: 55 s end to end, 46 s before fix round 2) no longer mints — HEAD GAP 12 s, blind. THE ELAPSED PROVIDER'S WORST EVALUATION DOES NOT CONVERGE UNDER PROOF_MAX_AGE (region comment + the PROOF_MAX_AGE derivation site; 6.4 decides). Pre-fix: the 46 s evaluation MINTED at +196"
else
    bad "(12c-tail) minting=$rt1 :: full-bound=$rt2"
fi

# (12d) M4 (INT-4/N7) through the REAL main loop. Pre-fix red: the zero-padded lastVote ABORTS the loop at
# t125 ('value too great for base' in staked_is_actively_voting); 2^64 + the head WRAPS and the provider
# mints PROVEN and the proof-gated take mutates at t171.
# 6.3.1 fix round 1 (T9): at the world's 2.5 slots/s [elapsed-rate] abstains (SLOW OWN HEAD from t171), so the
# headwrap row's no-mint no longer proved the M4 validator — it runs at a certified 3.7 slots/s now, beside the
# control with the head validator removed (it must mint)
rd1=$(HOSTILE=lv0 MDS=0 HORIZON=200 world | tail -1)
rd2=$(SLOT_NUM=37 SLOT_DEN=10 HOSTILE=headwrap ARMED=1 GATE=1 MDS=0 HORIZON=200 world | tail -1)
mutate "$STANDBY" 's/^    if ! _canon_uint "\$_es_head"; then   # M4/    if false; then   # M4/' "$WORK/m4-head.sh"
rd2m=$(WSCRIPT="$WORK/m4-head.sh" SLOT_NUM=37 SLOT_DEN=10 HOSTILE=headwrap ARMED=1 GATE=1 MDS=0 HORIZON=200 world | tail -1)
if [[ "$(field "$rd1" end)" == "horizon" && "$(field "$rd1" mutation)" == "none" && "$(field "$rd1" E)" == "65" ]] \
   && [[ "$(field "$rd2" end)" == "horizon" && "$(field "$rd2" emint)" == "none" && "$(field "$rd2" mutation)" == "none" ]] \
   && [[ "$(field "$rd2m" emint)" == "151" && "$(field "$rd2m" mutation)" == "151" ]]; then
    ok "(12d) M4 through the REAL loop: TIER2/TIER3 serving the holder's lastVote as the string \"0009999\" → the loop runs to the horizon (every sample unusable → blind, no take — fails toward NOT taking); the spare's own processed head served as 2^64 + head → the provider never mints (no usable head), no proof-gated take — at a certified 3.7 slots/s, where the rate layer passes; CONTROL: the M4 head validator removed → the wrapped head mints and takes at t151 (at 2.5 the rate layer's abstention hid it: no mint either way). Pre-fix: the loop ABORTED at t125; the wrapped head minted and took at t171"
else
    bad "(12d) lv0=$rd1 :: headwrap-3.7=$rd2 :: M4-removed-3.7=$rd2m"
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
# ping answers (rc 0): the connected world. The primary's REAL check_internet (its parallel pings and wait loop) and the
# heartbeat's ping summary run; only the network under them is stubbed (6.3.1 fix round 6 — the delta panel 5's CLM5-3:
# unstubbed, each run of this suite ran the host's ping at 8.8.8.8 / 1.1.1.1 / 9.9.9.9 — 126 times when every ping
# fails, 135 when every one answers — and the path the loop took, connected or NO INET, depended on the host's
# network). A function, so the pings' ( … ) & subshells inherit it.
ping() { return 0; }
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
# Pre-fix red (de21927): 20 s at MAX_DELINQUENT_SLOTS 0 and 15 (getSlot curl -m 3 unpetted + the next T2
# read + a pet). Since 6.3 fix round 2 (R2) the MAX_DELINQUENT_SLOTS reference is read FIRST in the own-
# bank check, so it no longer precedes the prefetch sampler's T2 read: it precedes the own-bank payload
# (curl -m 5). The MDS=15 world is a holder that stopped (the MDS reference runs on every own-bank read
# now; a live lagging holder no longer opens an episode here — R2's own effect).
mutate "$STANDBY" '/per-op pet after THIS read too/,/^        _watchdog_pet$/{/^        _watchdog_pet$/d;}' "$WORK/no-t1pet.sh"
mutate "$STANDBY" '/^        _watchdog_pet   # v0.7 (Block 6.3 fix round, M6.s class/d' "$WORK/no-mdspet.sh"
# 6.3.1: inside an open episode the [own-view] own-head sample (LOCAL getSlot curl -m 2 + its pet) now runs
# between Tier-1 and the provider's evaluation, so it separates the Tier-1 read from the sampler's T2 read too:
# the Tier-1 pet alone is no longer the only separator there — the control removes both
mutate "$WORK/no-t1pet.sh" '/^_own_head_sample() {/,/^}/{/^    _watchdog_pet/d;}' "$WORK/no-t1ohspet.sh"
rf0=$(ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=0 HORIZON=900 world | tail -1)
rf15=$(ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=15 HORIZON=900 world | tail -1)
rfc0=$(WSCRIPT="$WORK/no-t1pet.sh" ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=0 HORIZON=900 world | tail -1)
rfc0b=$(WSCRIPT="$WORK/no-t1ohspet.sh" ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=0 HORIZON=900 world | tail -1)
rfc15=$(WSCRIPT="$WORK/no-mdspet.sh" ARMED=1 HOLDCOOL=1 T2DOWN=1 CURLMAX=1 PETS=7 MDS=15 HORIZON=900 world | tail -1)
if [[ "$(field "$rf0" petgap)" == "17" && "$(field "$rf15" petgap)" == "17" && "$(field "$rf0" egap_from)" != "none" && "$(field "$rf15" egap_from)" != "none" ]] \
   && [[ "$(field "$rf15" petgap_own)" == "12" && "$(field "$rfc0" petgap)" == "17" && "$(field "$rfc0b" petgap)" == "22" && "$(field "$rfc15" petgap)" == "17" && "$(field "$rfc15" petgap_own)" == "15" ]]; then
    ok "(12f) M6 — MEASURED max gap between consecutive pets through the armed standby loop (watchdog-elapsed evaluating through its head read; T2 failing; every read at its full -m bound; every pet 7 s): 17 s at MAX_DELINQUENT_SLOTS 0 and at 15 = one op + one pet < WatchdogSec 30; across the own-bank read at 15: 12 s. CONTROLS: the Tier-1 getSlot pet removed → still 17 s at 0 (6.3.1: the own-head sample's read + pet now follows Tier-1 in an open episode); the Tier-1 pet AND the own-head sample's pet removed → 22 s (3 + 2 + the T2 read's 10 + a 7 s pet — both pets load-bearing together); the MDS reference pet removed → the own-bank segment 15 s (the reference stacks with the payload read: 3 + 5 + a 7 s pet) while the max stays 17 s. Pre-fix (the 6.3 build as first reviewed): 20 s at both presets"
else
    bad "(12f) mds0=$rf0 :: mds15=$rf15 :: no-t1pet@0=$rfc0 :: no-t1pet+no-sample-pet@0=$rfc0b :: no-mdspet@15=$rfc15"
fi

# (12g) M8 (INT-5) — paired while the monitor runs: the status line says so, loudly. Pre-fix red: silent.
case_m8() {
    _proof_startup_check >/dev/null 2>&1
    local reg0="$_elapsed_registered"
    printf '%s\n' "$(mk_token "${PG:-7}" "${PW:-30}" "${PB:-60}" real holder1)" > "$PROOF_STATE_DIR/pairing-token"
    WARNCT=0; LASTWARN=""; INFOCT=0; LASTINFO=""
    _proof_status_line
    echo "reg0=$reg0|reg=$_elapsed_registered|w=$LASTWARN|wn=$WARNCT|in=$INFOCT|labels=${_proof_provider_labels:-}"
}
r1=$(TOK=none drive_ep "$STANDBY" case_m8 | tail -1)
r2=$(TOK=none PG=9 PW=10 PB=20 drive_ep "$STANDBY" case_m8 | tail -1)
r2g=$(TOK=none PG=9 PW=10 PB=20 G2PK=UPK1 drive_ep "$STANDBY" case_m8 | tail -1)   # the same with G2 configured (verified-demote registers at startup)
r3=$(TOK=ok drive_ep "$STANDBY" case_m8 | tail -1)
# K4's negatives on the would-not-register warn (a K4 message; 6.3.1 fix round 8 — the delta panel 7's
# CHK7-K4-TESTS-PARTIAL-REGRESSION: the row matched a prefix and a suffix, so a claim inserted between them passed):
# no "disabled" outside the scoped "from the release that wires the gate, an invalidly paired spare's silence-based
# take is disabled", the clause counting only where it ends its sentence (a . ; or : next, or the end of the text: a claim
# tacked onto it — ", as it is in this release" — is the present tense) — the present-tense "silence-based take
# disabled", "stays DISABLED"; no "verified-demote only" or "verified-demote-only"; no "proof provider" or "proof
# providers"; every match ignoring case — and, with G2 configured (verified-demote registered), no "verified-demote" at all
m8_neg() {   # m8_neg <warn> [g2] — prints the violated negatives (test_proof_gate's k4_neg)
    local t="$1" v=""
    printf '%s\n' "$t" | sed -E "s/from the release that wires the gate, an invalidly paired spare's silence-based take is disabled([.;:]|\$)/\1/g" | grep -qi 'disabled' && v="$v tense"
    printf '%s\n' "$t" | grep -qiE 'verified-demote[- ]only' && v="$v vdonly"
    printf '%s\n' "$t" | grep -qi 'proof provider' && v="$v providers"
    [[ -n "${2:-}" ]] && printf '%s\n' "$t" | grep -qi 'verified-demote' && v="$v g2-named"
    printf '%s' "$v"
}
if [[ "$(field "$r1" reg0)" == "0" && "$(field "$r1" reg)" == "0" && "$(field "$r1" wn)" == "1" && "$(field "$r1" in)" == "0" ]] \
   && [[ "$(field "$r1" w)" == "[proof-gate] paired (token gen=7), but watchdog-elapsed is NOT registered — restart the monitor to register (registration runs at startup only; proof providers registered now: NONE)" ]] \
   && [[ "$(field "$r2" wn)" == "1" && "$(field "$r2" w)" == *"paired token present (gen=9), but watchdog-elapsed is NOT registered and would not register: "*"SHORTER than the un-armed timer path"* ]] \
   && [[ "$(field "$r2" w)" == *"— this release has no relinquish-proof gate (takes follow v0.6.x semantics, which the 6.3 re-check and the own-view veto can only hold); re-arm the holder and re-pair this spare: from the release that wires the gate, an invalidly paired spare's silence-based take is disabled" && -z "$(m8_neg "$(field "$r2" w)")" ]] \
   && [[ "$(field "$r2g" wn)" == "1" && " $(field "$r2g" labels) " == *" verified-demote "* && "$(field "$r2g" w)" == *"would not register: "*"SHORTER than the un-armed timer path"* && -z "$(m8_neg "$(field "$r2g" w)" g2)" ]] \
   && [[ "$(field "$r3" reg)" == "1" && "$(field "$r3" wn)" == "0" && "$(field "$r3" in)" == "0" ]]; then
    ok "(12g) M8 — an armed spare started UNPAIRED and paired while its monitor runs (no lazy registration in this build): the heartbeat status line WARNS 'paired (token gen=7), but watchdog-elapsed is NOT registered — restart the monitor to register (… registered now: NONE)'; a planted short-floor token is named instead ('would not register: … SHORTER than the un-armed timer path' — and that this release has no relinquish-proof gate: v0.6.x take semantics, an invalidly paired spare's silence-based take disabled from the release that wires the gate), that warn claiming no take disabled now, no 'verified-demote only' (or -only), no 'proof provider(s)', and with G2 configured (registered: $(field "$r2g" labels)) naming no provider; a spare registered at startup stays silent. Pre-fix: the unpaired line went quiet and NOTHING replaced it"
else
    bad "(12g) late-pair=$r1 :: late-lowfloor=$r2 :: late-lowfloor-g2=$r2g :: registered=$r3"
fi

# (12h) N2 (CC-6c) — what [elapsed-blind] means, measured: "no STAMPED blindness since the start". Blindness
# is stamped only where the take path TRIED to observe (a take-path cycle); an outage wholly inside the
# delay — where the take path attempts no read — is not stamped, and the silence clock runs through it
# (lastVote's on-chain monotonicity and the final same-vantage, head-checked read cover such stretches).
# ([elapsed-rate] neutered, as in (12a): at the world's 2.5 slots/s it would abstain on all three)
rh1=$(WSCRIPT="$WORK/n-rate.sh" DOWNFROM=80 DOWNTO=120 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
rh2=$(WSCRIPT="$WORK/n-rate.sh" DOWNFROM=100 DOWNTO=150 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
rh3=$(WSCRIPT="$WORK/n-rate.sh" DOWNFROM=140 DOWNTO=170 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
# the SHIPPED twins (T9) at a certified 3.7 slots/s (the chain runs faster, so the delay ends earlier: the
# inside-the-delay outage is t60–t100 there; no outage mints at t151)
rh0s=$(SLOT_NUM=37 SLOT_DEN=10 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
rh1s=$(SLOT_NUM=37 SLOT_DEN=10 DOWNFROM=60 DOWNTO=100 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
rh2s=$(SLOT_NUM=37 SLOT_DEN=10 DOWNFROM=100 DOWNTO=150 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
rh3s=$(SLOT_NUM=37 SLOT_DEN=10 DOWNFROM=140 DOWNTO=170 ARMED=1 GATE=1 MDS=0 HORIZON=300 world | tail -1)
if [[ "$(field "$rh1" emint)" == "171" && "$(field "$rh2" emint)" == "250" && "$(field "$rh3" emint)" == "270" ]] \
   && [[ "$(field "$rh0s" emint)" == "151" && "$(field "$rh1s" emint)" == "151" && "$(field "$rh2s" emint)" == "250" && "$(field "$rh3s" emint)" == "270" ]]; then
    ok "(12h) N2 ([elapsed-rate] neutered) — both tiers down t80–t120 (inside the delay: no observation attempted, nothing stamped) → the mint is unchanged at t171 (the clock ran through 40 s of UNSTAMPED blindness); outages overlapping take-path cycles (t100–t150, t140–t170) are stamped and restart it → mint at t250 / t270 (the outage's end + the 100 s floor). The SHIPPED provider at a certified 3.7 slots/s, the same rule: no outage → t151; t60–t100 (inside that rate's delay) → t151 unchanged; t100–t150 / t140–t170 → t250 / t270. [elapsed-blind] = no STAMPED blindness since the start (region comment + docs/SAFETY.md)"
else
    bad "(12h) inside-delay=$rh1 :: overlap1=$rh2 :: overlap2=$rh3 :: shipped-3.7: none=$(field "$rh0s" emint) inside=$(field "$rh1s" emint) overlap1=$(field "$rh2s" emint) overlap2=$(field "$rh3s" emint)"
fi

# ── (13) 6.3 fix round 2: the round's reds, re-run green — and its documented residual ─────────────────
echo ""; echo "─── (13) fix round 2: R1 observed_at (loop) / R2 own-bank MDS reference first / R3 head gap (loop) / R7 span floor / R8 cadence ───"
# (13a) R1 (REG-A) through the REAL loop under the 6.4-placement emulation. The shipped-defaults degraded
# world (GV=true MDS=0 CKI=5; TIER2 down, TIER3 answering 5 s late; the holder's one vote at t146) and the
# W1 world (TIER2 refusing to t160 then 10 s late, the first set-identity failing, the holder resuming at
# t320). Pre-fix red (f22d492): a proof-gated take at t441 in the first; t357 on a holder voting since
# t320 (hvafter=1) in the second. de21927 and the M3-only-revert control: no take / vetoed at t342.
# 6.3.1: the degraded world's mint is measured with [elapsed-rate] neutered (as in (12a)); the W1 world mints
# nothing that reaches its take either way.
r13a1=$(WSCRIPT="$WORK/n-rate.sh" ARMED=1 GATE=1 PETS=0 MDS=0 CKI=5 GV=true VOTES=146:146 T2DOWN=1 T3LAT_ALL=5 HORIZON=700 world | tail -1)
r13a2=$(ARMED=1 GATE=1 PETS=0 MDS=0 CKI=5 T2BADFROM=0 T2BADTO=160 T2LAT=10 LATFROM=160 SIFAIL=1 RESUME=320 HORIZON=500 world | tail -1)
r13a1s=$(SLOT_NUM=37 SLOT_DEN=10 ARMED=1 GATE=1 PETS=0 MDS=0 CKI=5 GV=true VOTES=146:146 T2DOWN=1 T3LAT_ALL=5 HORIZON=700 world | tail -1)   # the SHIPPED twin (T9), 3.7 slots/s
if [[ "$(field "$r13a1" mutation)" == "none" && "$(field "$r13a1" emint)" == "381" && "$(field "$r13a1s" emint)" == "212" && "$(field "$r13a1s" mutation)" == "none" ]] \
   && [[ "$(field "$r13a2" veto)" == "342" && "$(field "$r13a2" mutation)" == "none" ]]; then
    ok "(13a) R1 on the REAL loop: the shipped-defaults degraded world ([elapsed-rate] neutered) mints at t381 and the gate never accepts it — no take through t700 (the SHIPPED provider at a certified 3.7 slots/s: mints at t212, never accepted, no take); the W1 world vetoes at t342 — no take on the holder that resumed at t320. Both equal the 6.3 build as first reviewed and the M3-only-revert control take-for-take. Pre-fix (M3): a proof-gated take at t441; a take at t357 on a holder voting 37 s"
else
    bad "(13a) degraded=$r13a1 :: w1=$r13a2 :: degraded-shipped-3.7=$r13a1s"
fi
# (13b) R2 (FX-1): the own-bank MAX_DELINQUENT_SLOTS reference is read FIRST. A file clock, the REAL
# local_check_delinquency / tier2_check_delinquency; the holder votes EVERY slot (its lastVote = the
# finalized head the instant the payload is served), MAX_DELINQUENT_SLOTS=15, 2.5 slots/s; every pet
# costs PC s and the reference getSlot answers SL s late (the answer reflects the chain when served).
mds_unit() {   # $1=local|tier2 $2=PC $3=SL $4=holder lag (slots) [$5=down: every read times out at its -m bound]
    (
        set +e
        load_seam "$STANDBY"
        MCLK=$(mktemp "$WORK/mclk.XXXXXX"); echo "$T0" > "$MCLK"; MORD=$(mktemp "$WORK/mord.XXXXXX")
        _mn() { local x; read -r x < "$MCLK"; echo "$x"; }
        _ma() { local x; read -r x < "$MCLK"; echo $(( x + $1 )) > "$MCLK"; }
        mono_now() { _mn; }
        _msl() { echo $(( HEAD0 + ($1 - T0) * 5 / 2 - 32 )); }   # the finalized head at t
        MLOG=""; log_info() { MLOG="$*"; }; log_warn() { MLOG="$*"; }; log() { :; }
        VOTE_PUBKEY=V1; STAKED_PUBKEY=S1; LOCAL_RPC=http://local.mock; TIER2_RPC=http://t2.mock; MAX_DELINQUENT_SLOTS=15; _turbo_mode=true
        MPC="$2"; MSL="$3"; MHL="$4"; MDN="${5:-}"
        _watchdog_pet() { _ma "$MPC"; printf 'pet;' >> "$MORD"; }
        curl() {
            local d="" mt=5; while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; -m) mt="$2"; shift 2 ;; *) shift ;; esac; done
            # fix round 2 (S2): tier2_check_delinquency takes an [own-view] own-head sample (a LOCAL getSlot at
            # confirmed — the only confirmed getSlot here) between its payload, its reference and its re-read:
            # logged 'ohs', answered at once (a healthy loopback), its pet counted like every pet
            case "$d" in *getSlot*'"confirmed"'*) printf 'ohs;' >> "$MORD"; printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(( $(_msl "$(_mn)") + 30 ))"; return 0 ;; esac
            case "$d" in *getVoteAccounts*) printf 'gva;' >> "$MORD" ;; *getSlot*) printf 'slot;' >> "$MORD" ;; esac
            if [[ "$MDN" == "down" ]]; then _ma "$mt"; return 28; fi
            case "$d" in
                *getVoteAccounts*) printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":%s},{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]},"id":1}' "$(( $(_msl "$(_mn)") - 1 ))" "$(( $(_msl "$(_mn)") - MHL ))" ;;
                *getSlot*) _ma "$MSL"; printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(_msl "$(_mn)")" ;;
            esac
        }
        if [[ "$1" == "tier2" ]]; then tier2_check_delinquency; else local_check_delinquency; fi
        echo "rc=$?|order=$(cat "$MORD")|log=$MLOG"
    )
}
u1=$(mds_unit local 7 3 0); u2=$(mds_unit tier2 7 3 0)
c1=$(mds_unit local 0 3 40); c2=$(mds_unit tier2 0 3 40); d2=$(mds_unit tier2 7 0 0 down)
if [[ "$(field "$u1" rc)" == "1" && "$(field "$u1" order)" == "slot;pet;gva;pet;" && "$(field "$u2" rc)" == "1" && "$(field "$u2" order)" == "gva;pet;ohs;pet;slot;pet;ohs;pet;gva;pet;" ]] \
   && [[ "$(field "$c1" rc)" == "0" && "$(field "$c1" log)" == "[LOCAL] Latency 40 > 15 — treating as delinquent" && "$(field "$c2" rc)" == "0" && "$(field "$c2" log)" == "[TIER2] Latency 40 > 15 — treating as delinquent (lastVote re-read after the reference)" ]] \
   && [[ "$(field "$d2" rc)" == "2" && "$(field "$d2" order)" == "gva;pet;" ]]; then
    ok "(13b) R2, unit — a holder voting every slot, the reference 3 s late + a 7 s pet: LOCAL reads the reference FIRST (slot;pet;gva;pet) and the holder is current (rc 1); TIER2 keeps its op sequence and RE-READS the lastVote after the reference before a latency verdict can confirm (gva;pet;slot;pet;gva;pet — since fix round 2 (S2) with an own-head sample between each of the three reads: gva;pet;ohs;pet;slot;pet;ohs;pet;gva;pet) — current (rc 1). CONTROLS: a holder truly 40 slots behind still reads delinquent in both ('Latency 40 > 15'); TIER2 down keeps its exact pre-fix sequence (gva;pet → rc 2). Pre-fix: 'Latency 25 > 15 — treating as delinquent' in both"
else
    bad "(13b) local=$u1 :: tier2=$u2 :: lag40-local=$c1 :: lag40-tier2=$c2 :: t2down=$d2"
fi
r13b=$(ARMED=1 MDS=15 RESUME=0 PETS=7 HORIZON=600 world | tail -1)
if [[ "$(field "$r13b" E)" == "none" && "$(field "$r13b" mutation)" == "none" ]]; then
    ok "(13b-world) R2 on the REAL armed loop: MAX_DELINQUENT_SLOTS=15, a holder voting the whole time, every pet 7 s → no episode opens and nothing is taken through t600. Pre-fix: 'delinquent' every cycle from E=35 and the timer-path take MUTATED at t577 on the live holder (de21927: t423)"
else
    bad "(13b-world) $r13b"
fi
# (13c) R3 (FX-2) through the REAL loop: every read at its full -m bound (CURLMAX), every pet 7 s, the
# spare's own bank LAG s behind the chain (LAG=20 → 50 slots at 2.5/s; N_HEAD 22 — 25 when this row was written). Pre-fix red: LAG=20
# MINTED at t753 (the head read landing 12 s after the payload hid 30 of the 50 slots); LAG=0 (in sync)
# answered LAGGED VIEW from t794 — no mint either way there. 6.3.1: every open-episode cycle now also
# carries the own-head sample (curl -m 2 + a 7 s pet), so the first evaluation that reaches the head read
# lands later: t884 (was t794) — the horizon moves to 900 with it. Fix round 1 (R3) adds an own-head sample
# (a 2 s read + a 7 s pet here) before each take-cycle external read: the first take's fence verdict lands
# past the observation-span floor (no hold; the gate is evaluated and refuses), which re-phases the loop —
# the first HEAD GAP is now at t826 (6.3.1 before fix round 1: t884). No mint either way, as before. Fix
# round 2 (S2): the liveness probe's own-head sample (its 2 s read + a 7 s pet here) joins the first take
# attempt — the first HEAD GAP at t835.
r13c1=$(LAG=20 CURLMAX=1 PETS=7 ARMED=1 GATE=1 MDS=0 HORIZON=900 world | tail -1)
r13c2=$(LAG=0 CURLMAX=1 PETS=7 ARMED=1 GATE=1 MDS=0 HORIZON=900 world | tail -1)
if [[ "$(field "$r13c1" emint)" == "none" && "$(field "$r13c1" egap_from)" == "835" && "$(field "$r13c1" mutation)" == "none" ]] \
   && [[ "$(field "$r13c2" emint)" == "none" && "$(field "$r13c2" egap_from)" == "835" && "$(field "$r13c2" elag_from)" == "none" ]]; then
    ok "(13c) R3 on the REAL loop (every read at its bound, every pet 7 s): this bank 50 slots behind → HEAD GAP from t835, blind, no mint (pre-fix: MINTED at t753); in sync → HEAD GAP from t835 (pre-fix: LAGGED VIEW) — no mint either way (6.3.1 moved the first gap from t794 to t884: the own-head sample's read + pet join every open-episode cycle; fix round 1's per-read take-cycle samples re-phase it to t826, fix round 2's probe sample (9 s here) to t835)"
else
    bad "(13c) lag20=$r13c1 :: lag0=$r13c2"
fi
# (13e) R7 (REG-B): fix round 1's M2 (post-read silence starts) CAN make the span floor bind where it did
# not — only ever later. The binding world pinned as a differential: GV=true MDS=0 CKI=5, LOCAL reads 2 s,
# TIER2 9 s. The 6.3 build as first reviewed: MUTATION at t167 with zero span-floor holds. 6.3.1: every LOCAL read here answers at
# 2 s — the own-view veto's curl -m 2 bound — so the veto read times out: BLIND, no take at all (the named
# availability cost of the bound: a spare whose own node needs >= 2 s for a loopback read cannot testify).
# Fix round 1 (R3) re-phases this world: every own-head sample before a take-cycle external read ALSO
# times out at its 2 s bound (no sample — the veto then finds no baseline), and those 8 s carry the second
# attempt's fence verdict past the floor → zero holds, BLIND at t193 (6.3.1 before fix round 1: one hold,
# BLIND at t217). The floor's binding is re-witnessed at TIER2 6 s (one hold on both builds; BLIND at t215,
# before fix round 1 t199); at 1 s LOCAL reads the world takes at t169 (before: t165 — R3's four samples, 1 s each).
# Fix round 2 (S2) adds the probe's sample and one before EACH advisory read (GOSSIP_VERIFY on here), each
# timing out at its 2 s bound: TIER2 9 s → zero holds, BLIND at t201; at TIER2 5-9 s no hold binds any more
# (TIER2 6 s: BLIND at t189, zero holds), so the floor's binding is re-witnessed at TIER2 4 s (one hold on this
# build and on fix round 1: BLIND at t206, fix round 1 t196; one hold at TIER2 1-4 s, two at 0 s); at 1 s LOCAL
# reads the take lands at t168 (fix round 1: t169 — the longer probe cycle moves the 5 s attempt cadence so the
# take attempt starts 2 s earlier; a dead holder, the cadence phase of (13f)).
r13e=$(GV=true MDS=0 CKI=5 LOCLAT=2 T2LAT=9 HORIZON=260 world | tail -1)
r13e4=$(GV=true MDS=0 CKI=5 LOCLAT=2 T2LAT=4 HORIZON=320 world | tail -1)
r13e1=$(GV=true MDS=0 CKI=5 LOCLAT=1 T2LAT=9 HORIZON=260 world | tail -1)
if [[ "$(field "$r13e" mutation)" == "none" && "$(field "$r13e" floor_holds)" == "0" && "$(field "$r13e" ov_veto)" == "201:blind" ]] \
   && [[ "$(field "$r13e4" mutation)" == "none" && "$(field "$r13e4" floor_holds)" == "1" && "$(field "$r13e4" ov_veto)" == "206:blind" ]] \
   && [[ "$(field "$r13e1" mutation)" == "168" && "$(field "$r13e1" floor_holds)" == "0" ]]; then
    ok "(13e) R7 — M2 binds the observation-span floor where the 6.3 build as first reviewed did not (GV=true MDS=0 CKI=5, LOCAL reads 2 s, TIER2 9 s: that build t167 with zero holds; the 6.3 build: one hold, the take at t197). Since 6.3.1 the take never lands at 2 s LOCAL reads: the own-view veto's LOCAL read times out at its 2 s bound → BLIND (availability — a LOCAL answering in 2 s is at the bound). The per-read own-head samples time out there too and re-phase it: TIER2 9 s → zero holds, BLIND at t201 (fix round 1: t193; before it: one hold, t217); the floor's binding re-witnessed at TIER2 4 s → one hold, BLIND at t206 (fix round 1: t196; at TIER2 6 s fix round 2 holds no more: t189, zero holds); at 1 s LOCAL reads the take lands at t168 (fix round 1: t169; before it: t165 — the cadence phase). Later, never sooner"
else
    bad "(13e) t2lat9=$r13e :: t2lat4=$r13e4 :: loclat1=$r13e1"
fi
# (13f) R8 (REG-C) — DOCUMENTED RESIDUAL, not a defect of this round: the episode window CLOSES on CYCLE
# COUNT (7-of-10, 'mostly clear') while the own bank's visibility of a holder vote is TIME, so any
# cadence change (pets that cost time, CHECK_INTERVAL, read latency) re-phases vetoes and closes BOTH
# WAYS — de21927 included. The world: MDS=0 CKI=5 GV=false, the holder's one vote at t141, TIER2 10 s late
# during t73–t118, armed, the shipped (un-gated) path. FLIPS WHEN THE CLOSE RULE BECOMES TIME-BASED
# (a reviewed 6.4+ change; not in this round).
r8p0=$(ARMED=1 GATE=0 PETS=0 MDS=0 CKI=5 GV=false VOTES=141:141 T2LAT=10 LATFROM=73 LATTO=118 HORIZON=450 world | tail -1)
r8p1=$(ARMED=1 GATE=0 PETS=1 MDS=0 CKI=5 GV=false VOTES=141:141 T2LAT=10 LATFROM=73 LATTO=118 HORIZON=450 world | tail -1)
r8p2=$(ARMED=1 GATE=0 PETS=2 MDS=0 CKI=5 GV=false VOTES=141:141 T2LAT=10 LATFROM=73 LATTO=118 HORIZON=450 world | tail -1)
r8c4=$(ARMED=1 GATE=0 PETS=0 MDS=0 CKI=4 GV=false VOTES=141:141 T2LAT=10 LATFROM=73 LATTO=118 HORIZON=450 world | tail -1)
r8c6=$(ARMED=1 GATE=0 PETS=0 MDS=0 CKI=6 GV=false VOTES=141:141 T2LAT=10 LATFROM=73 LATTO=118 HORIZON=450 world | tail -1)
if [[ "$(field "$r8p0" mutation)" == "125" && "$(field "$r8p1" mutation)" == "271" && "$(field "$r8p2" mutation)" == "274" ]] \
   && [[ "$(field "$r8c4" mutation)" == "138" && "$(field "$r8c6" mutation)" == "126" ]]; then
    ok "(13f) R8 DOCUMENTED RESIDUAL (cadence, both ways): the same world takes at t125 with free pets, t271 with 1 s pets and t274 with 2 s pets (fix round 1: t125 / t270 / t272 — fix round 2's take-cycle samples, each with its pet, re-phased it; fix round 3's restored one sequential re-check leaves t271 / t274; 6.3.1 before fix round 1: t125 / t272 / t268 — fix round 1's per-read take-cycle samples and their pets re-phased it; the 6.3 build: t125 / t254 / t218 — 6.3.1's per-cycle own-head sample and its pet re-phased it; the 6.3 build as first reviewed: t125 / t152 / t284); CKI 4/5/6 with free pets → t138 / t125 / t126 on EVERY tree. The window closes on cycle count, the own bank sees a vote in time — flips when the close rule becomes time-based"
else
    bad "(13f) pets0=$r8p0 :: pets1=$r8p1 :: pets2=$r8p2 :: ci4=$r8c4 :: ci6=$r8c6"
fi

rm -rf "$WORK"
results_banner
