#!/bin/bash
# v0.7 (Block 6.1): PROOF-GATE SKELETON + PAIRING-TOKEN INTAKE AT THE SPARE ARM (BLOCK6-PLAN
# §0/§1/§5, reviewer conditions [6.0-COND-1..4] folded in).
# COST MODEL under test: Block 6's worst outcome is DOUBLE-SIGN — every ambiguity must fail
# toward NOT-TAKING and toward REFUSING to arm. The gate is NOT wired into any take path in
# this slice (wiring is 6.4): functions exist, are unit-tested here, and are inert everywhere
# today — armed-gated + role-gated, census-asserted below (not prose).
#
# PRE-IMPL REDS (observed against 31caa3c BEFORE any Block-6.1 code, logged to the task
# scratchpad block61-preimpl-reds.log): armed harness + no token → ZERO scream/standing line
# (the entrypoints did not exist: 2x command-not-found per daemon); gate census: 0 hits for
# require_relinquish_proof/_proof_age_edge_check/_derive_proof_floors/_pairing_crc/
# MARGIN_ELAPSED/N_HEAD/PROOF_MAX_AGE/elapsed_floor in both daemons; failover-arm.sh: 0 hits
# for ARM_PAIRING_TOKEN/REFUSE[P5/pairing-token.
#
# PANEL FIX ROUND (Block 6.1 re-audit; reds observed on 340996d, logged to the task scratchpad
# reds/): the token W/B bounds were unvalidated and elapsed_floor=W+B+MARGIN had no overflow
# guard, so a forged huge-W token stored as PAIRED and derived a NEGATIVE floor logged as a
# healthy PAIRED spare (BLOCKER L-1); the edge check accepted a future-dated observed_at (L-2);
# zero-stake verify accepted a degenerate empty getVoteAccounts as VERIFIED (L-3); the constants
# census missed prefixed/arithmetic spellings (FND-1). This suite now adds, red-first: the arm
# intake W/B ceiling + zero-floor (1h/1i/1j), the daemon derivation convergence backstop (4d) with
# its neuter-control (5c), the future-age clamp (10g/10h), the degenerate zero-stake refusal
# (2d/2e), and the broadened census with a widened injection control (11/11b).
#
# ARM SIDE (P5, failover-arm.sh — full ceremony runs, every root at mktemp, actuators stubbed):
#   (1a) valid fence=real token → arm green, stored ATOMICALLY (regular file, exact line),
#        P5 log announces gen+bounds, end-of-summary PAIRED line
#   (1b) crc flip → REFUSE[P5-token-crc] + re-copy fix, nothing stored
#   (1c) bound 61 vs delay 60 → REFUSE[P5-bound], text shows MEASURED 61s/60s + BOTH fix
#        commands (raise spare delay / re-arm holder tighter)
#   (1d) fence=page-only → arm PROCEEDS + elapsed-attestation-REFUSED line + loud summary
#   (1e) no token → arm PROCEEDS + §2.7 unpaired posture + end-of-summary UNPAIRED warning
#   (1f) directory at the store path → REFUSE[P5-store] (the A10 mv-swallow discipline)
#   (1g) primary-role arm + stray ARM_PAIRING_TOKEN → announced IGNORED (holder generates)
#   (1n) (Block 6.3.1 D5) a SYMLINKED state directory → REFUSE[STATE-dir-symlink] before the token is
#        stored (the daemon's R-SYM rule mirrored at the arm; the full P0 matrix is test_arm_ceremony (16))
#   (2)  zero-stake (§2.4, per entry, N-is-all): (2a) all entries zero/absent → green with a
#        VERIFIED line PER entry (live census = list length); (2b) one staked among clean →
#        REFUSE[P5-staked-unstaked] with the ~48 h CRDS extended_timeout reason + MEASURED
#        stake, after the clean entry verified; (2c) RPC down → REFUSE with the manual
#        getVoteAccounts command + retry-when-reachable fix
#   (2n–2q) C1 shared vantage: the G2 vantages measured against TIER2_RPC/TIER3_RPC — matched
#        pairs named with the comparison that matched (URL / host / resolved address set), the
#        consequence and the fix printed, RE-STATED at the end of the summary (before the pairing
#        posture, which stays last), never a refusal; (2p) the off-tier control must stay silent
#   (3)  parity: (3a) _pairing_crc BYTE-IDENTICAL across failover-arm.sh + BOTH daemons
#        (extract+cmp; count==1 per file); (3b) a token emitted by the SHIPPED holder arm
#        round-trips through the SHIPPED spare intake (green + stored); (3c) same payload →
#        same crc through the DAEMON's own helper (emission↔daemon-parse mechanical tie)
# DAEMON SIDE ([proof-gate] twin block, source-to-MAIN-LOOP seam, clock-stubbed):
#   (4)  armed + valid token → _derive_proof_floors: elapsed_floor=100, N_HEAD=22 (6.3.1: τ budgeted —
#        (MARGIN_ELAPSED − 1) × 5 / 2; 25 before), MARGIN_ELAPSED=10 (values read from the SAME shell)
#   (5)  COUPLING [6.0-COND-3]: MARGIN_ELAPSED 10→20 mutant → elapsed_floor=110 AND N_HEAD=47
#        move TOGETHER; control (5b): coupling additionally broken (static N_HEAD) → the
#        together-assertion goes RED (observed on the double mutant)
#   (6)  §2.7 loud unpaired [6.0-COND-4]: armed+no token → (a) CRITICAL page at EVERY start
#        (2 drives → 2 pages, unthrottled) AND (b) the standing line at every interval (2
#        calls → 2 identical lines); invalid + page-only tokens land the same posture with
#        their reasons; call sites wired: startup_checks + the ♥ Heartbeat surface (grep,
#        both daemons); (6e) scream-neutered mutant → 0 pages (control red observed)
#   (7)  un-armed: ALL entrypoints → rc 0, ZERO pages/logs/state (event census); (7b)
#        _watchdog_active forced open → the same drive LEAKS events (proves (7) observes the
#        gate, the provisioning-accident class); primary daemon armed (holder role) → zero
#        pages (role adapter)
#   (8)  gate: zero providers registered → REFUSE rc 1, text shows MEASURED providers
#        registered=0 + §2.7 posture; the minted verdict is STRUCTURED and carries the
#        Block-3 triple FROM the seam (fields == dump_freshness's, the sole reader) with
#        observed_at=0
#   (9)  bypass lever: armed+ALLOW_UNFENCED_TAKEOVER=true → rc 2 (DISTINCT outcome), verdict
#        proven=bypassed, per-take PROOF GATE BYPASSED page fired AT the gate; startup scream
#        PROOF GATE BYPASS ARMED at every armed start; un-armed + lever → nothing
#   (10) _proof_age_edge_check [6.0-COND-2]: fresh (age 50=PROOF_MAX_AGE) → pass; stale (51)
#        → refuse with MEASURED 51s vs REQUIRED <= 50s; observed_at=0/absent → refuse (no
#        0-sentinel arithmetic); un-armed → inert; (10e) edge-neutered mutant → stale verdict
#        passes (control red observed); the D4 arithmetic comment (R_worst = 36 s, = 50 s)
#        present at the check in BOTH daemons
#   (11) constants census (N-is-all for constants, allowlist style): elapsed_floor /
#        MARGIN_ELAPSED / N_HEAD / PROOF_MAX_AGE / ELAPSED_HEAD_GAP_MAX (the fifth: 6.3 fix round 2,
#        R3) / ELAPSED_RATE_MIN_SPAN and OWN_HEAD_H (the sixth and seventh: Block 6.3.1, D4) assigned
#        ONLY at the derivation sites (7 allowlisted lines per daemon; zero assignments in any other
#        shipped script); (11b) injection control: every evading spelling, the new names included →
#        census red observed
#   (12) twin: [proof-gate] extract+cmp BYTE-IDENTICAL across both daemons (the [fence-rot]
#        ritual)
#
# MUTATION COVERAGE (HARNESS.md discipline), all via mutate() (loud on no-op): the unpaired
# startup scream (6e), the arm's crc verification (1b-ctrl: flipped token ARMS on the mutant),
# the MARGIN→floor/N_HEAD coupling (5b double mutant), the edge-check age compare (10e), the
# constants census by injection (11b), the _watchdog_active armor (7b, shim-forced). NAMED
# SURVIVORS: refusal FIX texts are asserted by content, not mutation; the role adapters are
# exercised behaviorally (7-primary) not mutated — flipping one is a twin-visible one-line
# diff outside the parity block.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
BASH_BIN="${BASH:-/bin/bash}"
ARM="$HARNESS_DIR/failover-arm.sh"

title_banner "proof-gate skeleton + pairing-token intake (v0.7 Block 6.1)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pg61.XXXXXX")
T0=100000            # mono origin (never 0 — 0 collides with the 0-sentinels under test)

# ════════════════════════════════════════════════════════════════════════════════════════════
#  ARM-SIDE FIXTURE (the test_arm_ceremony pattern: stub actuators + TOOLDIR real tools;
#  every ARM_* root at mktemp — the hard boundary; no real systemctl can ever run)
# ════════════════════════════════════════════════════════════════════════════════════════════
STUB_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/pg61-stubs.XXXXXX")
STUB_DIR="$STUB_PARENT/stubs"
mkdir -p "$STUB_DIR"

cat > "$STUB_DIR/systemctl" <<'STUB'
#!/bin/sh
echo "systemctl $*" >> "$EVENTS"
case "$*" in
    daemon-reload) exit 0 ;;
    cat\ *)
        if [ -f "$MOCK_DIR/unitfile" ]; then cat "$MOCK_DIR/unitfile"; exit 0; fi
        exit 1 ;;
    start\ solana-failover-arm-probe.service)
        if [ -f "$MOCK_DIR/probe.fires" ]; then touch "$FENCE_MARKER_DIR/arm-probe.fired"; fi
        exit 0 ;;
    reset-failed*) exit 0 ;;
    enable\ *) exit 0 ;;
    is-active\ *) echo inactive; exit 3 ;;
    is-enabled\ *) echo not-found; exit 1 ;;
esac
exit 0
STUB
cat > "$STUB_DIR/timeout" <<'STUB'
#!/bin/sh
shift 3
cmd="$1"; shift
exec "$cmd" "$@"
STUB
printf '#!/bin/sh\nexit 1\n' > "$STUB_DIR/pgrep"
printf '#!/bin/sh\nexit 0\n' > "$STUB_DIR/sleep"
printf '#!/bin/sh\necho "socat $*" >> "$EVENTS"\nexit 0\n' > "$STUB_DIR/socat"
printf '#!/bin/sh\necho "flock $*" >> "$EVENTS"\nexit 0\n' > "$STUB_DIR/flock"
# content→pubkey map (the P4 KEY check): `pubkey <path>` prints the file's content
cat > "$STUB_DIR/solana-keygen" <<'STUB'
#!/bin/sh
[ "$1" = "pubkey" ] || exit 2
[ -f "$2" ] || exit 1
tr -d '\n' < "$2"
STUB
# curl: the P5 zero-stake seam AND the P6 batch-probe seam. rpc.down = unreachable (rc 7, no
# output). A request body starting with '[' is the P6 [getSlot,getClusterNodes] BATCH → served
# from batch.json with @IDA@/@IDB@ replaced by the ids the ARM actually sent (never ids the test
# invented); batch.down makes only the batch unreachable. Everything else is the P5 getVoteAccounts
# read → rpc.json.
cat > "$STUB_DIR/curl" <<'STUB'
#!/bin/sh
echo "curl $*" >> "$EVENTS"
[ -f "$MOCK_DIR/rpc.down" ] && exit 7
body=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then body="$2"; shift 2; else shift; fi
done
case "$body" in
    "["*)
        [ -f "$MOCK_DIR/batch.down" ] && exit 7
        ida=${body#*\"id\":}; ida=${ida%%,*}
        idb=${body##*\"id\":}; idb=${idb%%,*}
        sed "s/@IDA@/$ida/g; s/@IDB@/$idb/g" "$MOCK_DIR/batch.json" 2>/dev/null
        ;;
    *)  cat "$MOCK_DIR/rpc.json" 2>/dev/null ;;
esac
exit 0
STUB
# getent: the P6 resolver seam — `getent hosts <h>` prints $MOCK_DIR/dns.<h> (one "ADDR name" row
# per line), rc 2 when the file is absent (an unresolvable name)
cat > "$STUB_DIR/getent" <<'STUB'
#!/bin/sh
[ "$1" = "hosts" ] || exit 2
[ -f "$MOCK_DIR/dns.$2" ] || exit 2
cat "$MOCK_DIR/dns.$2"
exit 0
STUB
chmod 755 "$STUB_DIR"/*

# TOOLDIR: symlinks to the REAL host binaries for the arm's non-actuator externals (the
# test_arm_ceremony N-is-all list + jq for the P5 zero-stake parse). PATH = STUB:TOOLDIR only.
TOOLDIR="$STUB_PARENT/tools"
mkdir -p "$TOOLDIR"
PG_REAL_TOOLS="awk basename cat chmod cksum cp cut date dirname grep head hostname mkdir mv readlink rm sed sort tail touch tr jq"
for _t in $PG_REAL_TOOLS; do
    _tp=$(command -v "$_t" 2>/dev/null)
    if [[ -z "$_tp" || ! -x "$_tp" ]]; then
        echo "  ❌ FAIL: TOOLDIR provisioning: no real '$_t' on the host PATH"
        exit 1
    fi
    ln -s "$_tp" "$TOOLDIR/$_t"
done

MOCK_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/pg61-mocks.XXXXXX")
# v0.7 (Block 6.3.1 D5): the arm now REFUSES a state directory that is not its own resolved path
# (P0, the daemon's R-SYM rule mirrored) — so every mock root is spelled RESOLVED: macOS's TMPDIR sits
# under the /var -> /private/var symlink and ends in '/' (a '//' in the joined path)
MOCK_PARENT=$(CDPATH='' cd -P -- "$MOCK_PARENT" && pwd -P)
write_daemon() {   # v0.7-shaped daemon fixture (P1: patsub guard + watchdog capability)
    {
        echo '#!/bin/bash'
        echo 'shopt -u patsub_replacement 2>/dev/null || true'
        echo '_watchdog_active() { [ -n "$WATCHDOG_USEC" ]; }'
        echo '_watchdog_pet() { _sd_notify "WATCHDOG=1"; }'
        echo '_sd_notify_ready() { _sd_notify "READY=1"; }'
        # fixture mirror of the daemons' SINGLE derivation-site assignment — the arm's P5
        # floor-minimum check READS this line from the installed role daemon (never re-declares
        # it); case (1m) deletes it to exercise the cannot-verify refusal
        echo 'MARGIN_ELAPSED=10'
        local _i=1
        while [ "$_i" -le 12 ]; do echo "op$_i() { _watchdog_pet; }"; _i=$((_i+1)); done
    } > "$1"
}
# new_mock <role>: standby (the spare posture) or primary (the holder)
new_mock() {
    local role="${1:-standby}"
    MOCK_DIR=$(mktemp -d "$MOCK_PARENT/m.XXXXXX")
    mkdir -p "$MOCK_DIR/etc-systemd" "$MOCK_DIR/run-systemd" "$MOCK_DIR/opt" \
             "$MOCK_DIR/markers" "$MOCK_DIR/state"
    EVENTS="$MOCK_DIR/events"; : > "$EVENTS"
    touch "$MOCK_DIR/probe.fires"
    write_daemon "$MOCK_DIR/opt/solana-${role}-failover.sh"
    printf 'UNSTAKEDPUBKEY42' > "$MOCK_DIR/opt/unstaked.json"
    { echo '[Service]'; echo "ExecStart=/usr/bin/agave-validator --ledger /l --identity $MOCK_DIR/opt/unstaked.json --rpc-port 8899"; } > "$MOCK_DIR/unitfile"
    # healthy-cluster RPC fixture: PKCLEAN present with zero stake; PKSTAKED carries stake
    printf '%s\n' '{"jsonrpc":"2.0","result":{"current":[{"nodePubkey":"PKCLEAN","votePubkey":"V1","activatedStake":0,"lastVote":100}],"delinquent":[{"nodePubkey":"PKSTAKED","votePubkey":"V2","activatedStake":123456789,"lastVote":50}]},"id":1}' > "$MOCK_DIR/rpc.json"
    # P6 fixtures: a healthy batch answer (2-element array echoing the arm's own ids) and two
    # vantage hostnames on DISTINCT addresses
    printf '%s\n' '[{"jsonrpc":"2.0","id":@IDA@,"result":442455002},{"jsonrpc":"2.0","id":@IDB@,"result":[{"pubkey":"N1","gossip":"1.1.1.1:8001"},{"pubkey":"N2","gossip":"2.2.2.2:8001"}]}]' > "$MOCK_DIR/batch.json"
    printf '%s\n' '203.0.113.10 t2.mock' > "$MOCK_DIR/dns.t2.mock"
    printf '%s\n' '198.51.100.20 t3.mock' > "$MOCK_DIR/dns.t3.mock"
    if [[ "$role" == "standby" ]]; then write_env_standby; else write_env_primary; fi
}
write_env_standby() {   # extra KEY=VAL lines append (later lines override on source)
    {
        echo 'DRY_RUN=false'
        echo 'VALIDATOR_TYPE="agave"'
        echo "UNSTAKED_KEYPAIR=\"$MOCK_DIR/opt/unstaked.json\""
        echo 'UNSTAKED_PUBKEY="UNSTAKEDPUBKEY42"'
        echo "SOLANA_PATH=\"$STUB_DIR\""
        echo 'VALIDATOR_UNIT="sol-test.service"'
        echo 'EXPECTED_PRIMARY_SELF_FENCE_SECS=30'
        echo 'SELF_FENCE_MARGIN_SECS=30'
        echo 'TAKEOVER_DELAY=60'
        echo 'TIER2_RPC="http://t2.mock"'
        echo 'TIER3_RPC="http://t3.mock"'
        echo 'PRIMARY_UNSTAKED_PUBKEY=""'
        local kv
        for kv in "$@"; do echo "$kv"; done
    } > "$MOCK_DIR/opt/failover-standby.env"
}
write_env_primary() {
    {
        echo 'DRY_RUN=false'
        echo 'VALIDATOR_TYPE="agave"'
        echo "UNSTAKED_KEYPAIR=\"$MOCK_DIR/opt/unstaked.json\""
        echo 'UNSTAKED_PUBKEY="UNSTAKEDPUBKEY42"'
        echo "SOLANA_PATH=\"$STUB_DIR\""
        echo 'VALIDATOR_UNIT="sol-test.service"'
        echo 'EXPECTED_PRIMARY_SELF_FENCE_SECS=30'
        echo 'SELF_FENCE_MARGIN_SECS=30'
        local kv
        for kv in "$@"; do echo "$kv"; done
    } > "$MOCK_DIR/opt/failover.env"
}
run_arm() {   # [VAR=val …] — subprocess, clean env, stub PATH, every root at mktemp
    local script="${ARM_OVERRIDE:-$ARM}"
    env -i PATH="$STUB_DIR:$TOOLDIR" \
        EVENTS="$EVENTS" MOCK_DIR="$MOCK_DIR" \
        ARM_SYSTEMD_DIR="$MOCK_DIR/etc-systemd" \
        ARM_RUNTIME_DIR="$MOCK_DIR/run-systemd" \
        ARM_INSTALL_DIR="$MOCK_DIR/opt" \
        FENCE_MARKER_DIR="$MOCK_DIR/markers" \
        ARM_STATE_DIR="$MOCK_DIR/state" \
        "$@" "$BASH_BIN" "$script" > "$MOCK_DIR/out" 2>&1
    RC=$?
}
out_has()  { grep -q "$1" "$MOCK_DIR/out"; }
token_line() { grep '^v0\.7|gen=' "$MOCK_DIR/out" | tail -1; }

# the arm's OWN crc mechanics, extracted and eval'd (input-crafting uses the runner's actual
# algorithm, never a parallel reconstruction; (3a) separately proves all three copies identical)
_crc_def=$(grep -m1 '^_pairing_crc()' "$ARM")
if [[ -z "$_crc_def" ]]; then
    bad "harness: cannot extract _pairing_crc from failover-arm.sh"
else
    eval "$_crc_def"
fi
mk_token() {   # $1=gen $2=w $3=b $4=fence $5=host → full token line on stdout
    local p="v0.7|gen=$1|watchdog=$2|relinquish_bound=$3|fence=$4|host=$5"
    printf '%s|%s\n' "$p" "$(_pairing_crc "$p")"
}

# ── (1) P5 token intake at the spare arm ────────────────────────────────────────────────────────
echo ""; echo "─── (1) P5 intake: valid / crc-flip / bound / page-only / none / store / role scope ───"

TOK_OK=$(mk_token 7 30 60 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_OK"
stored=$(cat "$MOCK_DIR/state/pairing-token" 2>/dev/null)
if [[ "$RC" == "0" && -f "$MOCK_DIR/state/pairing-token" && "$stored" == "$TOK_OK" ]] && out_has 'precondition P5: pairing token VERIFIED and stored (gen=7, watchdog=30s, relinquish_bound=60s, fence=real' && out_has 'pairing summary: PAIRED'; then
    ok "(1a) valid token → arm green; stored ATOMICALLY as a regular file holding the exact line; P5 announces gen+bounds; end-of-summary PAIRED"
else
    bad "(1a) rc=$RC stored='$stored' tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# crc flip: last field +1
_crc="${TOK_OK##*|}"; TOK_FLIP="${TOK_OK%|*}|$((_crc + 1))"
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_FLIP"
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-token-crc\]' && out_has 're-copy the FULL token line' && [[ ! -e "$MOCK_DIR/state/pairing-token" ]] && ! out_has 'ceremony complete'; then
    ok "(1b) crc flip → REFUSE[P5-token-crc] + re-copy fix; nothing stored; arm did not complete"
else
    bad "(1b) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (1b-ctrl) crc verification NEUTERED in an arm copy → the SAME flipped token is ACCEPTED and
# STORED at P5 (the control's red). The mutant copy sits in $WORK with no systemd/ skels beside
# it, so the ceremony still dies later at the probe render — deliberately NOT asserted here:
# the control observes the P5 acceptance, which is the check under mutation.
mutate "$ARM" '/_pairing_crc "$payload")" != "$crc"/d' "$WORK/arm-nocrc.sh"
new_mock standby
ARM_OVERRIDE="$WORK/arm-nocrc.sh" run_arm ARM_PAIRING_TOKEN="$TOK_FLIP"
if out_has 'pairing token VERIFIED and stored' && [[ "$(cat "$MOCK_DIR/state/pairing-token" 2>/dev/null)" == "$TOK_FLIP" ]]; then
    ok "(1b-ctrl) crc check neutered → the SAME flipped token is accepted AND stored (red observed: (1b) is green because the check exists)"
else
    bad "(1b-ctrl) mutant did not accept the flipped token (rc=$RC) — (1b) may be passing for another reason: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

TOK_B61=$(mk_token 8 30 61 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_B61"
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-bound\]' && out_has 'MEASURED: relinquish_bound=61s' && out_has 'TAKEOVER_DELAY=60s' && out_has "sed -i 's/^TAKEOVER_DELAY=" && out_has 'EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS' && out_has 'double-sign'; then
    ok "(1c) bound 61 vs delay 60 → REFUSE[P5-bound]: MEASURED 61s/60s, the G2 double-sign reason, BOTH fix commands"
else
    bad "(1c) rc=$RC tail: $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (1h) BLOCKER (panel L-1): forged crc-valid tokens with a huge watchdog (near 2^63, and two
# smaller huge values) — on 340996d each ARMED green + stored + 'pairing summary: PAIRED'. The
# W ceiling closes the elapsed_floor=W+B+MARGIN overflow: REFUSE[P5-bound], nothing stored.
for _wv in 9223372036854775800 2147483647 9999999999; do
    TOK_HW=$(mk_token 7 "$_wv" 60 real holder1)
    new_mock standby
    run_arm ARM_PAIRING_TOKEN="$TOK_HW"
    if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-bound\]' && out_has "MEASURED: watchdog=${_wv}s" && out_has 'PAIRING_BOUND_MAX' && [[ ! -e "$MOCK_DIR/state/pairing-token" ]] && ! out_has 'pairing summary: PAIRED'; then
        ok "(1h) forged watchdog=${_wv} → REFUSE[P5-bound] (MEASURED watchdog vs PAIRING_BOUND_MAX); nothing stored, no PAIRED summary (was an accepted+stored PAIRED pairing before the ceiling)"
    else
        bad "(1h) W=${_wv} rc=$RC stored=$([[ -e "$MOCK_DIR/state/pairing-token" ]] && echo yes || echo no) tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
    fi
done

# (1i) ceiling boundary: watchdog=3601 (PAIRING_BOUND_MAX+1) REFUSES; watchdog=3600 (== the max)
# is a valid-shape pairing (accepted + stored). MEASURED, never a static figure.
TOK_WOVER=$(mk_token 7 3601 60 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_WOVER"
b_over=0; [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-bound\]' && out_has 'MEASURED: watchdog=3601s' && [[ ! -e "$MOCK_DIR/state/pairing-token" ]] && b_over=1
TOK_WMAX=$(mk_token 7 3600 60 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_WMAX"
b_max=0; [[ "$RC" == "0" && "$(cat "$MOCK_DIR/state/pairing-token" 2>/dev/null)" == "$TOK_WMAX" ]] && out_has 'pairing summary: PAIRED' && b_max=1
if [[ "$b_over" == "1" && "$b_max" == "1" ]]; then
    ok "(1i) ceiling boundary: watchdog=3601 → REFUSE[P5-bound]; watchdog=3600 (== PAIRING_BOUND_MAX, inclusive) → accepted + stored PAIRED"
else
    bad "(1i) over=$b_over max=$b_max"
fi

# (1j) zero-floor: watchdog=0 and relinquish_bound=0 each REFUSE[P5-bound] (a 0 floor is one a
# spare would clear with ZERO proven silence — fail toward NOT-arming). Both were stored PAIRED before.
TOK_W0=$(mk_token 7 0 60 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_W0"
z_w=0; [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-bound\]' && out_has 'MEASURED: watchdog=0s' && [[ ! -e "$MOCK_DIR/state/pairing-token" ]] && z_w=1
TOK_B0=$(mk_token 7 30 0 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_B0"
z_b=0; [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-bound\]' && out_has 'MEASURED: relinquish_bound=0s' && [[ ! -e "$MOCK_DIR/state/pairing-token" ]] && z_b=1
if [[ "$z_w" == "1" && "$z_b" == "1" ]]; then
    ok "(1j) watchdog=0 AND relinquish_bound=0 each → REFUSE[P5-bound] (zero-floor excluded), nothing stored"
else
    bad "(1j) z_w=$z_w z_b=$z_b"
fi

# (1k) floor-vs-timer MINIMUM (6.1 reviewer condition — the mirror of the B<=delay refusal, the
# same check from the other end): a crc-valid, IN-CEILING token from a misconfigured holder
# (W=10/B=20 — an ordinary wrong setup, not a forgery: the holder's drift announcer would warn,
# but the spare must refuse to pair) derives floor 40 < TAKEOVER_DELAY=60. Arming must never
# make the spare FASTER to take than not-arming. Red observed on 390527d: both tokens below
# armed PAIRED with the short floor.
TOK_LOW=$(mk_token 9 10 20 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_LOW"
lo_rc=$RC; lo_stored=$([[ -e "$MOCK_DIR/state/pairing-token" ]] && echo yes || echo no)
lo_ok=0
if [[ "$lo_rc" == "1" && "$lo_stored" == "no" ]] && out_has 'REFUSE\[P5-floor\]' && out_has 'MEASURED: floor=40s' && out_has 'TAKEOVER_DELAY=60' && out_has 'FASTER to take than not-arming' && out_has 'EITHER re-arm the holder' && ! out_has 'pairing summary: PAIRED'; then lo_ok=1; fi
TOK_TINY=$(mk_token 9 1 1 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_TINY"
ti_ok=0
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-floor\]' && out_has 'MEASURED: floor=12s'; then ti_ok=1; fi
if [[ $lo_ok -eq 1 && $ti_ok -eq 1 ]]; then
    ok "(1k) short-floor tokens (W10/B20→40s; W1/B1→12s) vs TAKEOVER_DELAY=60 → REFUSE[P5-floor] with MEASURED floor + the arming-never-faster principle + BOTH fix commands; nothing stored, no PAIRED"
else
    bad "(1k) lo_rc=$lo_rc lo_stored=$lo_stored lo_ok=$lo_ok ti_ok=$ti_ok tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (1l) boundary is INCLUSIVE: floor == TAKEOVER_DELAY pairs (W25/B25 → 25+25+10 = 60 == 60);
# the shipped 30/60 → 100 case is (1a). Preservation case, green before AND after the fix.
TOK_EDGE=$(mk_token 9 25 25 real holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_EDGE"
if [[ "$RC" == "0" ]] && out_has 'pairing summary: PAIRED' && [[ "$(cat "$MOCK_DIR/state/pairing-token" 2>/dev/null)" == "$TOK_EDGE" ]]; then
    ok "(1l) boundary floor==TAKEOVER_DELAY (60==60) → accepted + stored PAIRED (inclusive >=, mirroring the inclusive ceiling boundary (1i))"
else
    bad "(1l) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (1m) MARGIN unreadable from the installed role daemon → cannot-verify at ceremony → REFUSE
# (the P1-idiom read is load-bearing: the arm never re-declares MARGIN_ELAPSED — one derivation
# site, no drift vector, and the constants census stays exact — so an unreadable line must
# REFUSE, never default).
new_mock standby
grep -v '^MARGIN_ELAPSED=' "$MOCK_DIR/opt/solana-standby-failover.sh" > "$MOCK_DIR/opt/d.tmp" && mv "$MOCK_DIR/opt/d.tmp" "$MOCK_DIR/opt/solana-standby-failover.sh"
run_arm ARM_PAIRING_TOKEN="$TOK_OK"
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-floor\]' && out_has 'cannot READ MARGIN_ELAPSED'; then
    ok "(1m) MARGIN_ELAPSED unreadable from the installed daemon → REFUSE[P5-floor] (cannot-verify at ceremony fails toward refusing; the arm reads the daemon's single derivation site, never re-declares)"
else
    bad "(1m) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

TOK_PO=$(mk_token 9 30 60 page-only holder1)
new_mock standby
run_arm ARM_PAIRING_TOKEN="$TOK_PO"
if [[ "$RC" == "0" && "$(cat "$MOCK_DIR/state/pairing-token" 2>/dev/null)" == "$TOK_PO" ]] && out_has 'fence=page-only RELINQUISHES NOTHING' && out_has 'attestation is REFUSED' && out_has 'pairing summary: token stored but fence=page-only'; then
    ok "(1d) fence=page-only → arm PROCEEDS (token stored) + elapsed attestation REFUSED + loud §2.7 posture in the summary"
else
    bad "(1d) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

new_mock standby
run_arm
if [[ "$RC" == "0" ]] && out_has 'precondition P5: NO pairing token' && out_has 'pairing summary: UNPAIRED SPARE' && out_has 'verified-demote ONLY' && [[ ! -e "$MOCK_DIR/state/pairing-token" ]]; then
    ok "(1e) no token → arm PROCEEDS into the §2.7 unpaired posture + end-of-summary UNPAIRED warning (never silent)"
else
    bad "(1e) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

new_mock standby
mkdir -p "$MOCK_DIR/state/pairing-token"     # directory at the store path: mv swallows, verify must catch
run_arm ARM_PAIRING_TOKEN="$TOK_OK"
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-store\]' && ! out_has 'ceremony complete'; then
    ok "(1f) directory at the pairing-token path → REFUSE[P5-store] (tmp+mv+VERIFY — the 5.3 gen-counter discipline)"
else
    bad "(1f) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

new_mock primary
run_arm ARM_PAIRING_TOKEN="$TOK_OK"
if [[ "$RC" == "0" ]] && out_has "ARM_PAIRING_TOKEN is set on a 'primary' arm — IGNORED" && [[ ! -e "$MOCK_DIR/state/pairing-token" ]]; then
    ok "(1g) primary-role arm + stray ARM_PAIRING_TOKEN → announced IGNORED (the holder GENERATES tokens); nothing stored"
else
    bad "(1g) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (1n) Block 6.3.1 D5 — the arm REFUSES a symlinked state directory BEFORE the token is stored (the
# daemon's R-SYM rule mirrored: a token stored through a symlinked directory never proves on this
# spare). Pre-fix red (the 6.3 build): the token was accepted and stored THROUGH the link — PAIRED.
new_mock standby
mkdir -p "$MOCK_DIR/real-state"; rm -rf "$MOCK_DIR/state"; ln -s "$MOCK_DIR/real-state" "$MOCK_DIR/state"
run_arm ARM_PAIRING_TOKEN="$TOK_OK"
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[STATE-dir-symlink\]' && out_has 'NEVER proves on the spare' && [[ ! -e "$MOCK_DIR/real-state/pairing-token" ]] && ! out_has 'pairing summary: PAIRED' && ! out_has 'ceremony complete'; then
    ok "(1n) spare arm, valid token, SYMLINKED state directory → REFUSE[STATE-dir-symlink] (a token stored through it never proves — the daemon's R-SYM rule); nothing stored through the link, no PAIRED summary"
else
    bad "(1n) rc=$RC stored=$([[ -e "$MOCK_DIR/real-state/pairing-token" ]] && echo yes || echo no) tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# ── (2) zero-stake verification (§2.4 arm condition; per entry, N-is-all) ───────────────────────
echo ""; echo "─── (2) zero-stake verify: clean multi-entry / one staked among clean / RPC down ───"

new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN PKABSENT"'
run_arm
v_clean=$(grep -c "zero-stake VERIFIED for PRIMARY_UNSTAKED_PUBKEY entry" "$MOCK_DIR/out")
if [[ "$RC" == "0" && "$v_clean" == "2" ]] && out_has "entry 'PKCLEAN'" && out_has "entry 'PKABSENT'" && out_has 'entries verified: 2'; then
    ok "(2a) multi-entry, all zero/absent → green with a VERIFIED line PER entry (live census: 2/2; absence = zero)"
else
    bad "(2a) rc=$RC verified-lines=$v_clean tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN PKSTAKED"'
run_arm
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-staked-unstaked\]' && out_has "entry 'PKSTAKED' carries ACTIVATED STAKE" && out_has 'activatedStake=123456789' && out_has '48 h CRDS extended_timeout' && out_has "15 s/30 s expiry math" && out_has "zero-stake VERIFIED for PRIMARY_UNSTAKED_PUBKEY entry 'PKCLEAN'"; then
    ok "(2b) one staked among clean → REFUSE with the CRDS mechanical reason + MEASURED stake (clean entry verified first: the check runs PER entry)"
else
    bad "(2b) rc=$RC tail: $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
touch "$MOCK_DIR/rpc.down"
run_arm
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-staked-unstaked\]' && out_has 'cannot VERIFY zero stake' && out_has 'verify by hand' && out_has 'getVoteAccounts' && out_has "RETRY 'failover arm' when an RPC is reachable"; then
    ok "(2c) RPC unreachable → REFUSE (cannot-verify at CEREMONY time) + manual verification command + retry-when-reachable fix"
else
    bad "(2c) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (2d) degenerate/empty getVoteAccounts (panel L-3): a structurally-incomplete body (no populated
# .result.current[]) is cannot-verify, NOT proof of zero stake → REFUSE (both bodies were
# 'zero-stake VERIFIED' on 340996d). A healthy mainnet-beta getVoteAccounts ALWAYS populates current.
_deg=0
for _body in '{"jsonrpc":"2.0","result":{},"id":1}' '{"jsonrpc":"2.0","result":{"current":[],"delinquent":[]},"id":1}'; do
    new_mock standby
    write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
    printf '%s\n' "$_body" > "$MOCK_DIR/rpc.json"
    run_arm
    if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P5-staked-unstaked\]' && out_has 'structurally incomplete' && ! out_has 'zero-stake VERIFIED'; then
        _deg=$((_deg + 1))
    else
        bad "(2d) body='$_body' rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
    fi
done
[[ "$_deg" == "2" ]] && ok "(2d) both degenerate bodies ({} and current:[]/delinquent:[]) → REFUSE[P5-staked-unstaked] (cannot-verify: no populated current[]); neither accepted as zero-stake"

# (2e) preservation: the real-shape zero (populated current, key absent) and the staked/delinquent
# catch are UNCHANGED by the structural gate — re-observe the true-zero path still VERIFIES.
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
run_arm
if [[ "$RC" == "0" ]] && out_has "zero-stake VERIFIED for PRIMARY_UNSTAKED_PUBKEY entry 'PKCLEAN'"; then
    ok "(2e) real-shape zero (populated current with the key absent) still VERIFIED — the structural gate preserves the true-zero case"
else
    bad "(2e) rc=$RC tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# ── (2f)–(2q) precondition P6: the G2 vantage ceremony (Block 6.2 panel fix round + C1) ─────────
echo ""; echo "─── (2f–2q) P6: batch capability + resolved distinctness (REFUSE[P6-*]) + shared-vantage degradation ───"

# (2f) the green path, and the PROOF that P6 actually ran (its MEASURED lines, not a silent pass)
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
run_arm
if [[ "$RC" == "0" ]] && out_has 'G2 vantage A BATCH VERIFIED' && out_has 'G2 vantage B BATCH VERIFIED' \
   && out_has 'confirmed slot 442455002, 2 cluster nodes in the same response' \
   && out_has 'RESOLVED DISTINCTNESS verified via getent' && out_has '203.0.113.10' && out_has '198.51.100.20'; then
    ok "(2f) P6 green: BOTH vantages answered the [getSlot,getClusterNodes] batch as a 2-element array echoing the arm's OWN ids, and the log prints the MEASURED evidence (slot 442455002, 2 cluster nodes, resolved 203.0.113.10 vs 198.51.100.20) — never a silent pass"
else
    bad "(2f) rc=$RC tail: $(tail -5 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (2g) a vantage that cannot batch: it answers with ONE object (no batching, or a proxy that
# split the batch). G2's whole freshness binding is impossible there → REFUSE with the shape.
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
printf '%s\n' '{"jsonrpc":"2.0","id":@IDB@,"result":[{"pubkey":"N1","gossip":"1.1.1.1:8001"}]}' > "$MOCK_DIR/batch.json"
run_arm
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P6-batch\]' && out_has 'cannot serve a JSON-RPC BATCH' \
   && out_has "response shape 'object'" && out_has 'REQUIRED: a 2-element ARRAY' \
   && out_has 'supports JSON-RPC batching' && out_has 'verify by hand'; then
    ok "(2g) a vantage answering the batch with ONE object → REFUSE[P6-batch] naming the MEASURED shape ('object') and the exact fix (point the vantage at a batching provider / remove the proxy), with a by-hand verification command"
else
    bad "(2g) rc=$RC tail: $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (2h) an intermediary that rewrites ids: the array shape is right, the echo is not — and the
# echo is exactly what makes a replayed answer detectable at run time.
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
printf '%s\n' '[{"jsonrpc":"2.0","id":7,"result":442455002},{"jsonrpc":"2.0","id":8,"result":[{"pubkey":"N1","gossip":"1.1.1.1:8001"}]}]' > "$MOCK_DIR/batch.json"
run_arm
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P6-batch\]' && out_has "response shape 'array/2'" && out_has 'ids echoed \[7,8\]'; then
    ok "(2h) an answer of the right SHAPE whose members echo foreign ids (7,8) → REFUSE[P6-batch] printing both the shape and the MEASURED id echo against the ids this arm sent — id matching, not array position, is what the daemon relies on"
else
    bad "(2h) rc=$RC tail: $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (2i) unreachable vantage at ceremony time → refuse (cannot-verify fails toward not arming)
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
touch "$MOCK_DIR/batch.down"
run_arm
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P6-batch\]' && out_has 'did not answer the batch probe' && out_has 'curl rc=7'; then
    ok "(2i) vantage unreachable for the batch probe → REFUSE[P6-batch] with the MEASURED curl rc — cannot-verify at CEREMONY time fails toward refusing (an unreachable vantage is silent unavailability during an incident)"
else
    bad "(2i) rc=$RC tail: $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (2j) THE CNAME CASE: two distinct hostnames, ONE address. The daemon's URL/host tripwire cannot
# see this and the run-time cross-vantage byte compare does not catch a source that varies
# per-request (executed panel finding) — so it is refused HERE, where it is checkable.
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
printf '%s\n' '203.0.113.10 t2.mock' > "$MOCK_DIR/dns.t2.mock"
printf '%s\n' '203.0.113.10 t3.mock' > "$MOCK_DIR/dns.t3.mock"
run_arm
if [[ "$RC" == "1" ]] && out_has 'REFUSE\[P6-vantage\]' && out_has 'resolve to the SAME address set' \
   && out_has '203.0.113.10' && out_has 'ONE witness wearing two names' && out_has 'DIFFERENT failure domains'; then
    ok "(2j) two distinct vantage HOSTNAMES resolving to ONE address (the CNAME/anycast case) → REFUSE[P6-vantage] naming the MEASURED address set and the exact fix — the case the daemon's name-level tripwire is blind to"
else
    bad "(2j) rc=$RC tail: $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (2k) CONTROL for (2j): the ONLY difference is one address byte. Same rig, distinct addresses →
# green. So (2j)'s refusal observes the address compare, not some other precondition.
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
printf '%s\n' '203.0.113.10 t2.mock' > "$MOCK_DIR/dns.t2.mock"
printf '%s\n' '203.0.113.11 t3.mock' > "$MOCK_DIR/dns.t3.mock"
run_arm
if [[ "$RC" == "0" ]] && out_has 'RESOLVED DISTINCTNESS verified' && ! out_has 'REFUSE\[P6-vantage\]'; then
    ok "(2k) CONTROL: the SAME rig with the addresses differing in one byte (…10 vs …11) arms green — (2j) refuses on the address compare itself, not on an unrelated gate"
else
    bad "(2k) rc=$RC tail: $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (2l) unresolvable name → loud WARN, recorded, NOT a refusal (a broken resolver proves nothing
# about distinctness; refusing there would block arming on a transient DNS fault)
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
rm -f "$MOCK_DIR/dns.t3.mock"
run_arm
if [[ "$RC" == "0" ]] && out_has 'WARN: precondition P6' && out_has 'did not RESOLVE via getent' \
   && out_has 'unresolved' && out_has 'stays UNCHECKED for this arm' && ! out_has 'REFUSE\[P6'; then
    ok "(2l) an unresolvable vantage hostname → loud WARN naming the MEASURED resolution result and that the CNAME case stays unchecked; the arm PROCEEDS (the one named exception to P6's fail-toward-refusing rule)"
else
    bad "(2l) rc=$RC tail: $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# ── (2n)–(2q) C1: G2 vantages vs the vote-liveness tiers — a DEGRADATION, never a refusal ───────
# The daemons' liveness readers iterate `for rpc in "$TIER2_RPC" "$TIER3_RPC"` and _g2_register
# DEFAULTS the vantages to exactly those, so on the default config one compromised vantage supplies
# BOTH halves of the double-sign condition (a false G2 proof AND a false-frozen vote observation)
# and the proof gate's additivity does not hold. Most operators run exactly two RPCs — refusing
# would be sabotage — so this is measured, named loudly, re-stated at the end of the summary, and
# armed anyway.
#
# (2n) the DEFAULT config (no G2_VANTAGE_* set): the vantages ARE the tiers.
new_mock standby
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"'
run_arm
if [[ "$RC" == "0" ]] && out_has 'WARN: precondition P6 — DEGRADED, NOT REFUSED' \
   && out_has "G2_VANTAGE_A (host 't2.mock') == TIER2_RPC (host 't2.mock') by identical URL" \
   && out_has "G2_VANTAGE_B (host 't3.mock') == TIER3_RPC (host 't3.mock') by identical URL" \
   && out_has 'resolved-address compares via getent on every pair' \
   && out_has 'G2 and vote-liveness SHARE VANTAGES: one compromised vantage supplies BOTH halves of the double-sign condition' \
   && out_has "additivity does NOT hold" && out_has 'residual 2' \
   && out_has 'THIRD endpoint in a SEPARATE FAILURE DOMAIN' && out_has 'G2_VANTAGE_A and/or G2_VANTAGE_B' \
   && out_has "That restores additivity for verified-demote ONLY: watchdog-elapsed's silence and the vote-FROZEN observation stay one TIER2/TIER3 input on every host" \
   && ! out_has 'REFUSE\[P6'; then
    ok "(2n) DEFAULT config (vantages derived from the tiers) → a LOUD, MEASURED degradation: each matching pair named with the comparison that matched ('by identical URL'), the comparisons this host could make named ('resolved-address compares via getent on every pair'), the consequence stated (one compromised vantage supplies BOTH halves; additivity does NOT hold; SAFETY residual 2), and the way back named with the env keys and the file, SCOPED to verified-demote (6.3 fix round, X2: watchdog-elapsed's silence stays one TIER2/TIER3 input on every host) — and the arm still COMPLETES (rc 0, no REFUSE)"
else
    bad "(2n) rc=$RC tail: $(grep -c 'precondition P6' "$MOCK_DIR/out") P6 lines; $(tail -4 "$MOCK_DIR/out" | tr '\n' ' ')"
fi
# (2o) the same degradation is RE-STATED at the end of the summary, after the ARMED line, so it
# survives a long transcript — and the pairing posture still comes last (§2.7 (c)).
armed_ln=$(grep -n 'ARMED (' "$MOCK_DIR/out" | tail -1 | cut -d: -f1)
g2sum_ln=$(grep -n 'G2 vantage summary — G2 and vote-liveness SHARE VANTAGES' "$MOCK_DIR/out" | tail -1 | cut -d: -f1)
pair_ln=$(grep -n 'pairing summary:' "$MOCK_DIR/out" | tail -1 | cut -d: -f1)
if [[ -n "$armed_ln" && -n "$g2sum_ln" && -n "$pair_ln" ]] && [[ "$armed_ln" -lt "$g2sum_ln" && "$g2sum_ln" -lt "$pair_ln" ]] \
   && out_has 'G2 vantage summary — G2 and vote-liveness SHARE VANTAGES' && out_has 'separate failure domain' \
   && out_has "This spare is armed; the proof gate is not wired into any take path in this build" \
   && out_has "that restores additivity for verified-demote ONLY: watchdog-elapsed's silence and the vote-FROZEN observation stay one TIER2/TIER3 input on every host"; then
    ok "(2o) the degradation is re-stated in the END-OF-SUMMARY, in order: ARMED (line $armed_ln) → G2 vantage summary (line $g2sum_ln) → pairing posture (line $pair_ln, still LAST per §2.7 (c)) — it cannot scroll away with the rest of the ceremony; its remedy SCOPED to verified-demote and the gate stated as NOT wired (6.3 fix round, X2/X4)"
else
    bad "(2o) summary ordering: armed=$armed_ln g2=$g2sum_ln pairing=$pair_ln"
fi
# (2p) CONTROL: the SAME rig with the vantages pinned OFF both tiers (a third and fourth provider,
# each with its own address) → the MEASURED no-overlap line, no degradation, no end-of-summary
# warn. Without this, (2n) would be green for an unconditional warn.
new_mock standby
printf '%s\n' '192.0.2.30 t4.mock' > "$MOCK_DIR/dns.t4.mock"
printf '%s\n' '192.0.2.40 t5.mock' > "$MOCK_DIR/dns.t5.mock"
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"' 'G2_VANTAGE_A="http://t4.mock"' 'G2_VANTAGE_B="http://t5.mock"'
run_arm
if [[ "$RC" == "0" ]] && out_has 'G2 vantages are SEPARATE from the vote-liveness tiers' \
   && out_has "no G2 vantage matched TIER2_RPC (host 't2.mock') or TIER3_RPC (host 't3.mock')" \
   && out_has "additivity HOLDS on this host for verified-demote" \
   && out_has "It does NOT extend to watchdog-elapsed, on any host: its silence and the vote-FROZEN observation are the same TIER2/TIER3 input" \
   && ! out_has 'DEGRADED, NOT REFUSED' && ! out_has 'G2 vantage summary'; then
    ok "(2p) CONTROL: vantages pinned off both tiers (t4.mock/t5.mock vs TIER2 t2.mock / TIER3 t3.mock) → the MEASURED no-overlap line naming both tiers, 'additivity HOLDS' SCOPED to verified-demote with watchdog-elapsed named as the path it does NOT cover on any host (Block 6.3: its silence and the vote-FROZEN observation are one TIER2/TIER3 input — docs/SAFETY.md 'Shared vantages'), and ZERO degradation output (no P6 warn, no end-of-summary line) — (2n) observes the vantage-vs-tier compare, not an unconditional warning"
else
    bad "(2p) rc=$RC tail: $(tail -5 "$MOCK_DIR/out" | tr '\n' ' ')"
fi
# (2q) the compare is not URL-only: two DIFFERENT hostnames landing on the tier's address set is
# still one failure domain. The resolver seam supplies the collision, and the notice must name the
# comparison that actually matched — 'same resolved address set', not 'identical URL'.
new_mock standby
printf '%s\n' '203.0.113.10 t6.mock' > "$MOCK_DIR/dns.t6.mock"     # == dns.t2.mock's address
printf '%s\n' '192.0.2.40 t5.mock'   > "$MOCK_DIR/dns.t5.mock"
write_env_standby 'PRIMARY_UNSTAKED_PUBKEY="PKCLEAN"' 'G2_VANTAGE_A="http://t6.mock"' 'G2_VANTAGE_B="http://t5.mock"'
run_arm
if [[ "$RC" == "0" ]] && out_has 'DEGRADED, NOT REFUSED' \
   && out_has "G2_VANTAGE_A (host 't6.mock') == TIER2_RPC (host 't2.mock') by same resolved address set \[203.0.113.10\]" \
   && ! out_has 'by identical URL' && ! out_has "TIER3_RPC (host 't3.mock') by"; then
    ok "(2q) a vantage on a DIFFERENT hostname that resolves to TIER2_RPC's address → still degraded, and the notice names the comparison that MATCHED ('by same resolved address set [203.0.113.10]', not 'by identical URL') for that pair only — the URL compare alone would have missed this one"
else
    bad "(2q) rc=$RC tail: $(grep 'DEGRADED' "$MOCK_DIR/out" | head -1)"
fi

# (2m) scope: a holder (primary-role) arm and a spare with no PRIMARY_UNSTAKED_PUBKEY must run
# ZERO P6 probes — G2 does not exist on either, so a probe there would be ceremony theatre.
new_mock primary
run_arm
p6_pri=$(grep -c 'precondition P6' "$MOCK_DIR/out")
new_mock standby
run_arm
p6_unconf=$(grep -c 'precondition P6: PRIMARY_UNSTAKED_PUBKEY is empty' "$MOCK_DIR/out")
p6_probe=$(grep -c 'BATCH VERIFIED\|RESOLVED DISTINCTNESS' "$MOCK_DIR/out")
if [[ "$p6_pri" == "0" && "$p6_unconf" == "1" && "$p6_probe" == "0" ]]; then
    ok "(2m) scope: a HOLDER arm runs no P6 at all (0 lines); a spare with PRIMARY_UNSTAKED_PUBKEY empty announces the SKIP once and runs zero probes — P6 exists exactly where G2 registers"
else
    bad "(2m) primary P6 lines=$p6_pri unconfigured-skip=$p6_unconf probes-run=$p6_probe"
fi

# ── (3) emission↔intake parity (the 5.3 mechanics, never a reimplementation) ────────────────────
echo ""; echo "─── (3) parity: _pairing_crc 3-way cmp; shipped-arm token round-trips; same payload→same crc ───"

crc_arm=$(grep -m1 '^_pairing_crc()' "$ARM")
crc_pri=$(grep -m1 '^_pairing_crc()' "$PRIMARY")
crc_sby=$(grep -m1 '^_pairing_crc()' "$STANDBY")
n_arm=$(grep -c '^_pairing_crc()' "$ARM"); n_pri=$(grep -c '^_pairing_crc()' "$PRIMARY"); n_sby=$(grep -c '^_pairing_crc()' "$STANDBY")
if [[ -n "$crc_arm" && "$crc_arm" == "$crc_pri" && "$crc_arm" == "$crc_sby" && "$n_arm$n_pri$n_sby" == "111" ]]; then
    ok "(3a) _pairing_crc BYTE-IDENTICAL across failover-arm.sh + both daemons (exactly one definition each)"
else
    bad "(3a) defs differ or counts wrong (counts=$n_arm/$n_pri/$n_sby): arm='$crc_arm' pri='$crc_pri' sby='$crc_sby'"
fi

new_mock primary
run_arm
TOK_EMITTED=$(token_line)
if [[ "$RC" == "0" && -n "$TOK_EMITTED" ]]; then
    new_mock standby
    run_arm ARM_PAIRING_TOKEN="$TOK_EMITTED"
    if [[ "$RC" == "0" && "$(cat "$MOCK_DIR/state/pairing-token" 2>/dev/null)" == "$TOK_EMITTED" ]] && out_has 'pairing token VERIFIED and stored'; then
        ok "(3b) a token emitted by the SHIPPED holder arm round-trips through the SHIPPED spare intake (accepted + stored byte-exact)"
    else
        bad "(3b) intake rejected the shipped arm's own token: rc=$RC tok='$TOK_EMITTED' tail: $(tail -3 "$MOCK_DIR/out" | tr '\n' ' ')"
    fi
else
    bad "(3b) holder arm did not emit a token (rc=$RC)"
fi

# same payload → same crc through the STANDBY DAEMON's own helper (subshell-eval'd from the twin block)
crc_daemon_computed=$( _pg_line=$(grep -m1 '^_pairing_crc()' "$STANDBY"); eval "$_pg_line"; _pairing_crc "${TOK_EMITTED%|*}" )
if [[ -n "$TOK_EMITTED" && "$crc_daemon_computed" == "${TOK_EMITTED##*|}" ]]; then
    ok "(3c) same payload → same crc via the daemon's [proof-gate] helper (emission↔daemon-parse mechanically tied: ${TOK_EMITTED##*|})"
else
    bad "(3c) daemon-computed crc '$crc_daemon_computed' != emitted '${TOK_EMITTED##*|}'"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════
#  DAEMON SIDE — the [proof-gate] twin block (source-to-MAIN-LOOP seam, clock-stubbed)
# ════════════════════════════════════════════════════════════════════════════════════════════
harness_clock_shims
harness_silence_sinks

# drive_gate <daemon> <armed 0/1> <lever ""|true> <token none|ok|invalid|page-only|b61> <case-fn>
# Runs the REAL block in a subshell; captures pages/warn/info; echoes the case fn's k=v| record.
drive_gate() {
    local script="$1" armed="$2" lever="$3" tokmode="$4" fn="$5"
    (
        set +e
        _SIM_NOW=$T0
        PROOF_STATE_DIR=$(mktemp -d "$WORK/ps.XXXXXX")
        load_seam "$script"
        STAKED_PUBKEY=S1; UNSTAKED_PUBKEY=U1
        ALERT_THROTTLE=600
        TAKEOVER_DELAY=60   # the un-armed timer path — the floor-minimum backstop compares against it; case (4g) unsets it
        if [[ "$armed" == "1" ]]; then NOTIFY_SOCKET="$PROOF_STATE_DIR/n.sock"; WATCHDOG_USEC=30000000; else unset NOTIFY_SOCKET; unset WATCHDOG_USEC; fi
        ALLOW_UNFENCED_TAKEOVER="${lever:-false}"
        case "$tokmode" in
            ok)        printf '%s\n' "$(mk_token 7 30 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;
            page-only) printf '%s\n' "$(mk_token 7 30 60 page-only holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;
            invalid)   printf 'v0.7|gen=7|watchdog=30|relinquish_bound=60|fence=real|host=h|999\n' > "$PROOF_STATE_DIR/pairing-token" ;;
            b61)       printf '%s\n' "$(mk_token 8 30 61 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;
            wrapw)     printf '%s\n' "$(mk_token 7 9223372036854775800 60 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;   # crc-valid, W near 2^63 → floor W+B+MARGIN wraps NEGATIVE (planted on disk, bypassing the arm ceiling)
            lowfloor)  printf '%s\n' "$(mk_token 9 10 20 real holder1)" > "$PROOF_STATE_DIR/pairing-token" ;;   # crc-valid, in-ceiling, honest-looking — floor 10+20+10=40 < TAKEOVER_DELAY=60 (the reviewer's misconfigured-holder table; planted on disk, bypassing the intake floor-minimum)
            none)      : ;;
        esac
        PAGES=0; PAGE_TITLES=""; LASTPAGE=""; WARNCT=0; LASTWARN=""; INFOCT=0; LASTINFO=""; SLINES=0
        alert() { PAGES=$((PAGES+1)); PAGE_TITLES="$PAGE_TITLES;$3"; LASTPAGE="$1"; }
        alert_warn() { WARNCT=$((WARNCT+1)); }
        alert_info() { :; }
        log_warn() { LASTWARN="$*"; WARNCT=$((WARNCT+1)); }
        log_info() { LASTINFO="$*"; INFOCT=$((INFOCT+1)); case "$*" in "[proof-gate] proof providers:"*) SLINES=$((SLINES+1)) ;; esac; }
        log_error() { :; }
        "$fn"
    )
}

# ── (4)+(5) floors derived + the coupling ───────────────────────────────────────────────────────
echo ""; echo "─── (4)(5) derivation site: floors from the token; MARGIN↔N_HEAD coupled by derivation ───"

case_floors() {
    _derive_proof_floors; local rc=$?
    echo "rc=$rc|floor=${elapsed_floor:-unset}|nhead=${N_HEAD:-unset}|margin=${MARGIN_ELAPSED:-unset}|gen=${_proof_token_gen:-unset}"
}
r=$(drive_gate "$STANDBY" 1 "" ok case_floors | tail -1)
if [[ "$(field "$r" rc)" == "0" && "$(field "$r" floor)" == "100" && "$(field "$r" nhead)" == "22" && "$(field "$r" margin)" == "10" && "$(field "$r" gen)" == "7" ]]; then
    ok "(4) armed + valid token → elapsed_floor=100 (W30+B60+MARGIN10), N_HEAD=22 ((MARGIN−1)×5/2 — τ budgeted, 6.3.1), MARGIN_ELAPSED=10 — read from the deriving shell"
else
    bad "(4) $r"
fi
r=$(drive_gate "$STANDBY" 1 "" none case_floors | tail -1)
if [[ "$(field "$r" rc)" == "1" && "$(field "$r" floor)" == "unset" ]]; then
    ok "(4b) armed + NO token → _derive_proof_floors rc 1, floors NOT derived (no attested bounds → no elapsed floor)"
else
    bad "(4b) $r"
fi
r=$(drive_gate "$STANDBY" 0 "" ok case_floors | tail -1)
if [[ "$(field "$r" rc)" == "0" && "$(field "$r" floor)" == "unset" ]]; then
    ok "(4c) un-armed → derivation inert (rc 0, nothing derived): the armor line, not the token, gates the floors"
else
    bad "(4c) $r"
fi

# (4d) BLOCKER backstop [6.0-COND-1] (panel L-1): a crc-valid token whose watchdog wraps the floor
# (W near 2^63), planted DIRECTLY on disk so it bypasses the arm intake ceiling. The derivation-
# site convergence assert must reject it: _derive_proof_floors returns non-zero (INVALID) and
# _proof_startup_check screams the §2.7 CRITICAL page naming the non-converging floor — NEVER the
# PAIRED line. On 340996d this logged 'armed spare PAIRED … elapsed_floor=-9223372036854775746s'
# with pages=0. Defense in depth: this is correct regardless of the arm ceiling.
case_floors_and_start() {
    _derive_proof_floors; local rc=$?
    local floor="${elapsed_floor:-unset}"
    _proof_startup_check
    echo "drc=$rc|floor=$floor|pages=$PAGES|titles=$PAGE_TITLES|lastpage=$LASTPAGE|lastinfo=$LASTINFO"
}
r=$(drive_gate "$STANDBY" 1 "" wrapw case_floors_and_start | tail -1)
if [[ "$(field "$r" drc)" == "1" && "$(field "$r" floor)" == -* ]] \
   && [[ "$(field "$r" pages)" == "1" && "$(field "$r" titles)" == *"ARMED SPARE NOT ATTESTED 🚨"* ]] \
   && [[ "$(field "$r" lastpage)" == *"did not converge"* ]] \
   && [[ "$(field "$r" lastinfo)" != *"armed spare PAIRED"* ]]; then
    ok "(4d) planted wrapping-W token (bypasses intake) → _derive_proof_floors INVALID (rc 1, floor=$(field "$r" floor)) + §2.7 CRITICAL page naming the non-converging floor; NO PAIRED line (the on-disk backstop, independent of the arm ceiling)"
else
    bad "(4d) $r"
fi

# (4f) floor-vs-timer MINIMUM backstop (6.1 reviewer condition; defense in depth like (4d)): a
# crc-valid in-ceiling short-floor token planted ON DISK (bypassing the intake refusal (1k)) —
# the twin derivation must classify the pairing INVALID (floor 40 < TAKEOVER_DELAY=60) and the
# §2.7 CRITICAL page must name SHORTER, never PAIRED. Red observed on 390527d: drc=0 floor=40
# with the healthy PAIRED line.
r=$(drive_gate "$STANDBY" 1 "" lowfloor case_floors_and_start | tail -1)
if [[ "$(field "$r" drc)" == "1" && "$(field "$r" floor)" == "40" ]] \
   && [[ "$(field "$r" pages)" == "1" && "$(field "$r" titles)" == *"ARMED SPARE NOT ATTESTED 🚨"* ]] \
   && [[ "$(field "$r" lastpage)" == *"SHORTER than the un-armed timer path"* ]] \
   && [[ "$(field "$r" lastinfo)" != *"armed spare PAIRED"* ]]; then
    ok "(4f) planted short-floor token (bypasses intake) → derivation INVALID (rc 1, floor=40 < delay=60) + §2.7 CRITICAL naming SHORTER; NO PAIRED line — arming never makes the spare faster than not-arming, by construction at BOTH layers"
else
    bad "(4f) $r"
fi

# (4g) TAKEOVER_DELAY unset/non-numeric in the daemon env → the floor minimum is UNCHECKABLE →
# cannot-verify → invalid floor (fail toward NOT-TAKING; on the holder-role daemon this stays
# inert data — the §2.7 consumer is role-gated).
case_floors_nodelay() {
    unset TAKEOVER_DELAY
    _derive_proof_floors; local rc=$?
    echo "rc=$rc|floor=${elapsed_floor:-unset}|why=${_proof_floor_why:-}"
}
r=$(drive_gate "$STANDBY" 1 "" ok case_floors_nodelay | tail -1)
if [[ "$(field "$r" rc)" == "1" && "$(field "$r" why)" == *"TAKEOVER_DELAY"* ]]; then
    ok "(4g) TAKEOVER_DELAY unset → derivation INVALID (cannot-verify the floor minimum fails toward NOT-TAKING), why names the missing delay"
else
    bad "(4g) $r"
fi

# (5) coupling: MARGIN_ELAPSED 10→20 mutant → floor AND N_HEAD move TOGETHER
mutate "$STANDBY" 's/^    MARGIN_ELAPSED=10$/    MARGIN_ELAPSED=20/' "$WORK/margin20.sh"
r=$(drive_gate "$WORK/margin20.sh" 1 "" ok case_floors | tail -1)
if [[ "$(field "$r" floor)" == "110" && "$(field "$r" nhead)" == "47" ]]; then
    ok "(5) MARGIN_ELAPSED 10→20 → elapsed_floor 110 AND N_HEAD 47 move TOGETHER (coupled at the derivation site, [6.0-COND-3])"
else
    bad "(5) $r (a static N_HEAD is exactly the red this asserts against)"
fi
# (5b) control: coupling ADDITIONALLY broken (N_HEAD static) → the together-assertion goes red
mutate "$WORK/margin20.sh" 's|(MARGIN_ELAPSED - 1) \* 5 / 2|22|' "$WORK/coupling-broken.sh"
r=$(drive_gate "$WORK/coupling-broken.sh" 1 "" ok case_floors | tail -1)
if [[ "$(field "$r" floor)" == "110" && "$(field "$r" nhead)" == "22" ]]; then
    ok "(5b) coupling broken (static N_HEAD) → floor 110 with N_HEAD 22: (5)'s together-assertion observed RED on the mutant"
else
    bad "(5b) double mutant gave: $r — the coupling control cannot be trusted"
fi
# (5c) control, REFRAMED at the 6.1 floor-minimum round (an interaction the round itself
# surfaced): with the floor-vs-timer backstop in place, neutering the convergence assert ALONE
# no longer restores the PAIRED red — every reachable overflow wraps NEGATIVE (a bash-parseable
# W cannot push W+B+MARGIN past 2^64 into positive territory), and a negative floor is always
# < TAKEOVER_DELAY, so the SECOND layer catches it. That shadowing is defense-in-depth WORKING,
# and (5c) now observes it; (5c2) neuters BOTH layers and restores the 340996d PAIRED red —
# proving the two layers are the COMPLETE guard set (no hidden third guard, and no gap).
mutate "$STANDBY" 's/^    if \[\[ \$elapsed_floor -le 0 .*then$/    if false; then/' "$WORK/noconv.sh"
r=$(drive_gate "$WORK/noconv.sh" 1 "" wrapw case_floors_and_start | tail -1)
if [[ "$(field "$r" drc)" == "1" && "$(field "$r" floor)" == -* && "$(field "$r" lastpage)" == *"SHORTER than the un-armed timer path"* && "$(field "$r" lastinfo)" != *"armed spare PAIRED"* ]]; then
    ok "(5c) convergence-assert neutered → the wrapping-W token is STILL refused by the floor-minimum layer (negative floor < delay, why=SHORTER): defense-in-depth observed — one neutered layer does not reopen the hole"
else
    bad "(5c) single-neuter did not fall through to the floor-minimum layer: $r"
fi
# (5c2) BOTH layers neutered → the 340996d red restored (negative floor, healthy PAIRED, no page)
mutate "$WORK/noconv.sh" 's/\$elapsed_floor -lt \$((10#\$_pdf_delay))/$elapsed_floor -lt -9223372036854775807/' "$WORK/noconv2.sh"
r=$(drive_gate "$WORK/noconv2.sh" 1 "" wrapw case_floors_and_start | tail -1)
if [[ "$(field "$r" drc)" == "0" && "$(field "$r" floor)" == -* && "$(field "$r" lastinfo)" == *"armed spare PAIRED"* && "$(field "$r" titles)" != *"ARMED SPARE NOT ATTESTED"* ]]; then
    ok "(5c2) BOTH layers neutered → wrapping-W derives rc 0 with a NEGATIVE floor ($(field "$r" floor)) and logs 'armed spare PAIRED' (no §2.7 page): the 340996d red restored — the two layers are the complete guard set"
else
    bad "(5c2) double mutant did not restore the negative-floor PAIRED red: $r"
fi

# (5f) control: the INTAKE floor-minimum neutered → the short-floor token arms PAIRED (the 390527d
# red restored on the mutant — (1k) genuinely observes the intake comparison)
mutate "$ARM" 's/if \[\[ \$_p5_floor -lt \$delay \]\]; then/if [[ $_p5_floor -lt 0 ]]; then/' "$WORK/arm-nofloor.sh"
new_mock standby
ARM_OVERRIDE="$WORK/arm-nofloor.sh" run_arm ARM_PAIRING_TOKEN="$TOK_LOW"
# the (1b-ctrl) pattern: the $WORK mutant has no skels beside it, so the ceremony dies later at
# the probe render — the control asserts the P5-LEVEL escape (token accepted+stored, no floor
# refusal), which is exactly what (1k) guards
if [[ "$(cat "$MOCK_DIR/state/pairing-token" 2>/dev/null)" == "$TOK_LOW" ]] && out_has 'precondition P5: pairing token VERIFIED and stored' && ! out_has 'REFUSE\[P5-floor\]'; then
    ok "(5f) CONTROL: intake floor-minimum neutered → the W10/B20 token is ACCEPTED+STORED at P5 with no floor refusal (red restored; (1k) observes the live comparison, not a parallel one)"
else
    bad "(5f) mutant did not restore the short-floor P5 escape: rc=$RC stored='$(cat "$MOCK_DIR/state/pairing-token" 2>/dev/null)' tail: $(tail -2 "$MOCK_DIR/out" | tr '\n' ' ')"
fi

# (5g) control: the twin BACKSTOP floor-minimum neutered → the planted short-floor token derives
# a healthy PAIRED line (the (4f) red restored on the mutant)
mutate "$STANDBY" 's/\$elapsed_floor -lt \$((10#\$_pdf_delay))/$elapsed_floor -lt 0/' "$WORK/standby-nofloor.sh"
r=$(drive_gate "$WORK/standby-nofloor.sh" 1 "" lowfloor case_floors_and_start | tail -1)
if [[ "$(field "$r" drc)" == "0" && "$(field "$r" floor)" == "40" && "$(field "$r" lastinfo)" == *"armed spare PAIRED"* ]]; then
    ok "(5g) CONTROL: backstop floor-minimum neutered → planted W10/B20 derives PAIRED with floor=40 (red restored; (4f) observes the live backstop)"
else
    bad "(5g) mutant did not restore the backstop red: $r"
fi

# ── (6) the §2.7 loud unpaired state ────────────────────────────────────────────────────────────
echo ""; echo "─── (6) loud unpaired: every-start CRITICAL page + standing heartbeat line, wired call sites ───"

case_two_starts() {
    _proof_startup_check
    _proof_startup_check
    echo "pages=$PAGES|titles=$PAGE_TITLES|lastpage=$LASTPAGE"
}
r=$(drive_gate "$STANDBY" 1 "" none case_two_starts | tail -1)
tt=$(field "$r" titles)
lp=$(field "$r" lastpage)
if [[ "$(field "$r" pages)" == "2" ]] && [[ "$tt" == ";ARMED SPARE NOT ATTESTED 🚨;ARMED SPARE NOT ATTESTED 🚨" ]] && [[ "$lp" == "proof providers: NONE — no provider can prove here — holder not attested"* && "$lp" == *"silence-based take disabled"* && "$lp" == *"arm prints the token"* ]]; then
    ok "(6a) armed spare, no token → CRITICAL page at EVERY start (2 drives → 2 pages, unthrottled) with the §2.7 wording, printing the MEASURED registry: G2 unconfigured here → 'proof providers: NONE — no provider can prove here' (6.3 fix round, X4 — the remembered 'verified-demote ONLY' was false on this config)"
else
    bad "(6a) $r"
fi
case_two_starts_g2() {   # the same unpaired spare WITH G2 configured (its unstaked pubkey + the default vantages)
    PRIMARY_UNSTAKED_PUBKEY=UPK1; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
    case_two_starts
}
r=$(drive_gate "$STANDBY" 1 "" none case_two_starts_g2 | tail -1)
if [[ "$(field "$r" pages)" == "2" && "$(field "$r" lastpage)" == "proof providers: verified-demote ONLY — holder not attested"* ]]; then
    ok "(6a-g2) the same unpaired spare with G2 configured → the page prints 'proof providers: verified-demote ONLY' — the registry as MEASURED, not a remembered phrase"
else
    bad "(6a-g2) $r"
fi
r=$(drive_gate "$STANDBY" 1 "" invalid case_two_starts | tail -1)
if [[ "$(field "$r" pages)" == "2" && "$(field "$r" lastpage)" == *"invalid (crc/shape)"* ]]; then
    ok "(6b) invalid stored token → same every-start scream, reason named (crc/shape)"
else
    bad "(6b) $r"
fi
r=$(drive_gate "$STANDBY" 1 "" page-only case_two_starts | tail -1)
if [[ "$(field "$r" pages)" == "2" && "$(field "$r" lastpage)" == *"page-only relinquishes nothing"* ]]; then
    ok "(6c) fence=page-only token → SAME posture for the time path (page-only relinquishes nothing), screamed at every start"
else
    bad "(6c) $r"
fi
case_status_lines() {
    _proof_status_line
    _proof_status_line
    echo "slines=$SLINES|last=$LASTINFO"
}
r=$(drive_gate "$STANDBY" 1 "" none case_status_lines | tail -1)
if [[ "$(field "$r" slines)" == "2" && "$(field "$r" last)" == *"proof providers: NONE — no provider can prove here — holder not attested"* && "$(field "$r" last)" == *"silence-based take disabled"* ]]; then
    ok "(6d) standing line at every interval (2 calls → 2 identical §2.7 lines on the status surface, the MEASURED registry: NONE with G2 unconfigured)"
else
    bad "(6d) $r"
fi
# (6e) control: the startup scream neutered → zero pages (red observed on the mutant)
mutate "$STANDBY" '/alert "proof providers: \$(_proof_unpaired_registry) — holder not attested (/d' "$WORK/noscream.sh"
r=$(drive_gate "$WORK/noscream.sh" 1 "" none case_two_starts | tail -1)
if [[ "$(field "$r" pages)" == "0" ]]; then
    ok "(6e) scream-neutered mutant → 0 pages: (6a) is green because the page line exists (control red observed)"
else
    bad "(6e) mutant still paged: $r"
fi
# call sites actually wired (grep, both daemons — the fence-rot (16) pattern)
w1=$(grep -c '^    _proof_startup_check' "$STANDBY"); w2=$(grep -c '^    _proof_startup_check' "$PRIMARY")
w3=$(grep -c '_proof_status_line   #' "$STANDBY");    w4=$(grep -c '_proof_status_line   #' "$PRIMARY")
hb1=$(grep -A2 '♥ Heartbeat:' "$STANDBY" | grep -c '_proof_status_line')
hb2=$(grep -A2 '♥ Heartbeat:' "$PRIMARY" | grep -c '_proof_status_line')
if [[ "$w1$w2$w3$w4" == "1111" && "$hb1" == "1" && "$hb2" == "1" ]]; then
    ok "(6f) call sites wired: _proof_startup_check in startup_checks and _proof_status_line at the ♥ Heartbeat surface — BOTH daemons (the v0.6.4 status-log cadence)"
else
    bad "(6f) wiring counts: startup=$w1/$w2 status=$w3/$w4 heartbeat-adjacent=$hb1/$hb2"
fi

# ── (7) structural inertness (census, not prose) ────────────────────────────────────────────────
echo ""; echo "─── (7) inertness census: un-armed zero events; armor-forced control leaks; holder role silent ───"

case_all_entrypoints() {
    _proof_startup_check
    _proof_status_line
    require_relinquish_proof; local g=$?
    _proof_age_edge_check;    local e=$?
    _derive_proof_floors;     local d=$?
    echo "g=$g|e=$e|d=$d|pages=$PAGES|warnct=$WARNCT|infoct=$INFOCT|slines=$SLINES|floor=${elapsed_floor:-unset}"
}
r=$(drive_gate "$STANDBY" 0 "" none case_all_entrypoints | tail -1)
if [[ "$(field "$r" g)$(field "$r" e)$(field "$r" d)" == "000" && "$(field "$r" pages)" == "0" && "$(field "$r" warnct)" == "0" && "$(field "$r" infoct)" == "0" && "$(field "$r" floor)" == "unset" ]]; then
    ok "(7a) UN-ARMED: every entrypoint rc 0, ZERO pages/warns/infos/state — the gate does not exist behaviorally (v0.6.x unchanged)"
else
    bad "(7a) $r"
fi
case_armor_forced() {
    _watchdog_active() { return 0; }     # the (14)-class control: force the armor open
    case_all_entrypoints
}
r=$(drive_gate "$STANDBY" 0 "" none case_armor_forced | tail -1)
if [[ "$(field "$r" pages)" != "0" || "$(field "$r" warnct)" != "0" ]]; then
    ok "(7b) _watchdog_active forced open → the SAME un-armed drive leaks events (pages=$(field "$r" pages) warns=$(field "$r" warnct)): (7a)'s zero genuinely observes the armor"
else
    bad "(7b) armor-forced drive still silent: $r — (7a) proves nothing"
fi
r=$(drive_gate "$PRIMARY" 1 "" none case_all_entrypoints | tail -1)
if [[ "$(field "$r" g)$(field "$r" e)" == "00" && "$(field "$r" pages)" == "0" && "$(field "$r" slines)" == "0" ]]; then
    ok "(7c) PRIMARY (holder) daemon ARMED with no token → zero pages/lines, gate rc 0: the role adapter scopes the spare posture (a healthy armed holder must never scream 'unpaired')"
else
    bad "(7c) $r"
fi

# ── (8) the gate with zero providers: structured refusal fed from the seam ──────────────────────
echo ""; echo "─── (8) gate refuse: MEASURED providers=0; verdict is the structured record, triple from the seam ───"

case_gate_refuse() {
    _liveness_first_provider="T2"       # priming WRITES (fixtures may write; only dump_freshness reads)
    _liveness_obs_since=424242
    _last_blind_end=99
    require_relinquish_proof; local rc=$?
    local fr; fr=$(dump_freshness)
    echo "rc=$rc|warn=$LASTWARN|v_proven=$(_proof_field "$_proof_last_verdict" proven)|v_prov=$(_proof_field "$_proof_last_verdict" provider)|v_vant=$(_proof_field "$_proof_last_verdict" vantage)|v_since=$(_proof_field "$_proof_last_verdict" obs_since)|v_blind=$(_proof_field "$_proof_last_verdict" blind_until)|v_obs=$(_proof_field "$_proof_last_verdict" observed_at)|s_vant=$(field "$fr" vantage)|s_since=$(field "$fr" observed_since)|s_blind=$(field "$fr" blind_until)"
}
r=$(drive_gate "$STANDBY" 1 "" none case_gate_refuse | tail -1)
wv=$(field "$r" warn)
if [[ "$(field "$r" rc)" == "1" && "$(field "$r" v_proven)" == "no" && "$(field "$r" v_prov)" == "none" && "$(field "$r" v_obs)" == "0" ]] \
   && [[ "$(field "$r" v_vant)" == "$(field "$r" s_vant)" && "$(field "$r" v_since)" == "$(field "$r" s_since)" && "$(field "$r" v_blind)" == "$(field "$r" s_blind)" && "$(field "$r" v_since)" == "424242" ]] \
   && [[ "$wv" == *"MEASURED: providers registered=0"* && "$wv" == *"proof providers: NONE — no provider can prove here — holder not attested"* ]]; then
    ok "(8) zero providers → REFUSE rc 1 (MEASURED registered=0; the §2.7 posture prints the MEASURED registry — NONE here); the minted verdict carries the Block-3 triple EQUAL to dump_freshness's seam values, observed_at=0"
else
    bad "(8) $r"
fi
case_gate_refuse_paired() {
    require_relinquish_proof; local rc=$?
    echo "rc=$rc|warn=$LASTWARN"
}
r=$(drive_gate "$STANDBY" 1 "" ok case_gate_refuse_paired | tail -1)
if [[ "$(field "$r" rc)" == "1" && "$(field "$r" warn)" == *"holder attested (token gen=7) but no registered provider proved relinquish"* ]]; then
    ok "(8b) PAIRED spare, zero providers → still REFUSES, with the factual posture (claim=check: the §2.7 'not attested' line is reserved for the unpaired state)"
else
    bad "(8b) $r"
fi

# ── (9) the bypass lever: distinct outcome + both scream halves ─────────────────────────────────
echo ""; echo "─── (9) ALLOW_UNFENCED_TAKEOVER: rc 2 + per-take scream at the gate; every-start scream; un-armed silent ───"

case_bypass() {
    require_relinquish_proof; local rc=$?
    echo "rc=$rc|pages=$PAGES|titles=$PAGE_TITLES|v_proven=$(_proof_field "$_proof_last_verdict" proven)|v_obs=$(_proof_field "$_proof_last_verdict" observed_at)"
}
r=$(drive_gate "$STANDBY" 1 true none case_bypass | tail -1)
if [[ "$(field "$r" rc)" == "2" && "$(field "$r" v_proven)" == "bypassed" && "$(field "$r" pages)" == "1" && "$(field "$r" titles)" == *"PROOF GATE BYPASSED 🚨"* && "$(field "$r" v_obs)" == "$T0" ]]; then
    ok "(9a) lever true at the gate → DISTINCT rc 2, verdict proven=bypassed, per-take CRITICAL scream fired AT the gate (6.4 inherits the scream point)"
else
    bad "(9a) $r"
fi
r=$(drive_gate "$STANDBY" 1 true none case_two_starts | tail -1)
if [[ "$(field "$r" pages)" == "4" && "$(field "$r" titles)" == *"PROOF GATE BYPASS ARMED 🚨"* ]]; then
    ok "(9b) lever true at startup → PROOF GATE BYPASS ARMED page at EVERY armed start (2 starts → 2 bypass + 2 unpaired pages)"
else
    bad "(9b) $r"
fi
r=$(drive_gate "$STANDBY" 0 true none case_bypass | tail -1)
if [[ "$(field "$r" rc)" == "0" && "$(field "$r" pages)" == "0" ]]; then
    ok "(9c) lever true UN-ARMED → nothing (armor first): the lever alone cannot conjure gate behavior on an un-armed host"
else
    bad "(9c) $r"
fi

# ── (10) the mutation-edge age check ────────────────────────────────────────────────────────────
echo ""; echo "─── (10) _proof_age_edge_check: fresh/stale/absent; clock-stubbed; comment carries the D4 numbers ───"

case_edge() {   # $1 = observed_at value to plant; clock sits at T0+60
    _proof_last_verdict="proven=yes|provider=test|observation_id=obs1|vantage=T2|obs_since=1|blind_until=0|observed_at=$1"
    _SIM_NOW=$((T0 + 60))
    _proof_age_edge_check; local rc=$?
    echo "rc=$rc|warn=$LASTWARN"
}
case_edge_fresh()  { case_edge $((T0 + 10)); }   # age 50 == PROOF_MAX_AGE → pass
case_edge_stale()  { case_edge $((T0 + 9));  }   # age 51 → refuse
case_edge_absent() { case_edge 0; }
case_edge_future()     { case_edge $((T0 + 100)); }   # observed_at ahead of the clock (now=T0+60) → age -40 → refuse
case_edge_hugefuture() { case_edge 99999999999; }     # far-future stamp → refuse
r=$(drive_gate "$STANDBY" 1 "" ok case_edge_fresh | tail -1)
if [[ "$(field "$r" rc)" == "0" ]]; then
    ok "(10a) verdict age 50s (== PROOF_MAX_AGE) at the edge → accepted (the budget the D4 arithmetic derived)"
else
    bad "(10a) $r"
fi
r=$(drive_gate "$STANDBY" 1 "" ok case_edge_stale | tail -1)
if [[ "$(field "$r" rc)" == "1" && "$(field "$r" warn)" == *"MEASURED: verdict age 51s"* && "$(field "$r" warn)" == *"REQUIRED: <= 50s"* ]]; then
    ok "(10b) verdict age 51s → REFUSED with MEASURED 51s vs REQUIRED <= 50s (never a static figure)"
else
    bad "(10b) $r"
fi
r=$(drive_gate "$STANDBY" 1 "" ok case_edge_absent | tail -1)
if [[ "$(field "$r" rc)" == "1" && "$(field "$r" warn)" == *"no usable observed_at"* ]]; then
    ok "(10c) observed_at=0 → REFUSED outright (a proof with no read behind it is absent; no 0-sentinel arithmetic)"
else
    bad "(10c) $r"
fi
# (10g)(10h) future-dated verdict (panel L-2): observed_at AHEAD of the spare's mono clock → a
# NEGATIVE age → REFUSE (rc 0 ACCEPT on 340996d). A verdict from the future is impossible, not
# fresh — the symmetric clamp closes the 0-sentinel rule on the negative side too.
r=$(drive_gate "$STANDBY" 1 "" ok case_edge_future | tail -1)
if [[ "$(field "$r" rc)" == "1" && "$(field "$r" warn)" == *"in the FUTURE"* && "$(field "$r" warn)" == *"REQUIRED: age >= 0"* ]]; then
    ok "(10g) verdict observed_at in the future (age < 0) → REFUSE with the MEASURED negative age (was accepted as 'fresh' before the clamp)"
else
    bad "(10g) $r"
fi
r=$(drive_gate "$STANDBY" 1 "" ok case_edge_hugefuture | tail -1)
if [[ "$(field "$r" rc)" == "1" && "$(field "$r" warn)" == *"in the FUTURE"* ]]; then
    ok "(10h) far-future observed_at → REFUSE (the clamp bounds age below as well as above)"
else
    bad "(10h) $r"
fi
r=$(drive_gate "$STANDBY" 0 "" ok case_edge_stale | tail -1)
if [[ "$(field "$r" rc)" == "0" ]]; then
    ok "(10d) un-armed edge check → inert rc 0 (zero behavior change on today's hosts)"
else
    bad "(10d) $r"
fi
# (10e) control: age compare neutered → the SAME stale verdict passes (red observed)
mutate "$STANDBY" 's/-le $PROOF_MAX_AGE/-le 999999/' "$WORK/noedge.sh"
r=$(drive_gate "$WORK/noedge.sh" 1 "" ok case_edge_stale | tail -1)
if [[ "$(field "$r" rc)" == "0" ]]; then
    ok "(10e) edge-check-neutered mutant → stale verdict PASSES (red observed: (10b) is green because the compare exists)"
else
    bad "(10e) mutant still refused: $r"
fi
# the D4 arithmetic lives AT the check, in BOTH daemons (comment assert)
d4a=$(grep -c 'R_worst = 36 s' "$STANDBY"); d4b=$(grep -c 'PROOF_MAX_AGE = 36 + 3 + 11' "$STANDBY")
d4c=$(grep -c 'R_worst = 36 s' "$PRIMARY"); d4d=$(grep -c 'PROOF_MAX_AGE = 36 + 3 + 11' "$PRIMARY")
if [[ "$d4a$d4b$d4c$d4d" == "1111" ]]; then
    ok "(10f) the derived arithmetic (R_worst = 36 s; PROOF_MAX_AGE = 36 + 3 + 11 = 50 s) is stated AT _proof_age_edge_check in both daemons"
else
    bad "(10f) comment census: $d4a/$d4b/$d4c/$d4d"
fi

# ── (11) constants census: N-is-all for the derived names, allowlist style ──────────────────────
echo ""; echo "─── (11) constants census: elapsed_floor/MARGIN_ELAPSED/N_HEAD/PROOF_MAX_AGE/ELAPSED_HEAD_GAP_MAX/ELAPSED_RATE_MIN_SPAN/OWN_HEAD_H only at the derivation sites ───"

census_constants() {   # $1=file → rc 0 iff EXACTLY the 7 allowlisted assignment lines exist
    local f="$1" lines n
    # (panel FND-1) BROADENED beyond the bare '^\s*NAME=' form: also catch the prefixed spellings
    # (local|declare|export|readonly, including attribute flags like `declare -i`) and arithmetic-
    # context assignments ((( NAME= , $(( NAME= , spaces allowed around =) — the natural drift forms
    # a future helper would introduce (a `local N_HEAD=` recompute, an arithmetic reassign), which
    # the old regex missed (6-of-8 spellings evaded, panel-executed). The string-context occurrence
    # in the PAIRED log line (→ elapsed_floor=${elapsed_floor}s, N_HEAD=…) is deliberately NOT
    # matched: it is neither at a line-start assignment position, nor keyword-prefixed, nor inside
    # (( — so honest daemons still count EXACTLY 7 (asserted below; 4 before 6.3 fix round 2 added
    # ELAPSED_HEAD_GAP_MAX, R3; 5 before Block 6.3.1 added ELAPSED_RATE_MIN_SPAN and OWN_HEAD_H, D4),
    # while every evading spelling now goes RED (11b widened to match).
    lines=$(grep -nE '(^[[:space:]]*((local|declare|export|readonly)[[:space:]]+([-][[:alnum:]]+[[:space:]]+)*)?(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE|ELAPSED_HEAD_GAP_MAX|ELAPSED_RATE_MIN_SPAN|OWN_HEAD_H)=)|(\(\([[:space:]]*(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE|ELAPSED_HEAD_GAP_MAX|ELAPSED_RATE_MIN_SPAN|OWN_HEAD_H)[[:space:]]*=)' "$f")
    n=$(printf '%s\n' "$lines" | grep -c .)
    [[ "$n" == "7" ]] || { CENSUS_FAIL="count=$n: $(printf '%s' "$lines" | tr '\n' ' ')"; return 1; }
    printf '%s\n' "$lines" | grep -q 'MARGIN_ELAPSED=10$'                                            || { CENSUS_FAIL="margin line"; return 1; }
    printf '%s\n' "$lines" | grep -q 'elapsed_floor=\$(( _proof_token_w + _proof_token_b + MARGIN_ELAPSED ))' || { CENSUS_FAIL="floor line"; return 1; }
    printf '%s\n' "$lines" | grep -q 'N_HEAD=\$(( (MARGIN_ELAPSED - 1) \* 5 / 2 ))'                  || { CENSUS_FAIL="nhead line"; return 1; }
    printf '%s\n' "$lines" | grep -q 'PROOF_MAX_AGE=50$'                                             || { CENSUS_FAIL="age line"; return 1; }
    printf '%s\n' "$lines" | grep -q 'ELAPSED_HEAD_GAP_MAX=1$'                                       || { CENSUS_FAIL="head-gap line"; return 1; }
    printf '%s\n' "$lines" | grep -q 'ELAPSED_RATE_MIN_SPAN=24$'                                     || { CENSUS_FAIL="rate-span line"; return 1; }
    printf '%s\n' "$lines" | grep -qE 'OWN_HEAD_H=16[[:space:]]'                                     || { CENSUS_FAIL="own-head line"; return 1; }
    return 0
}
c_ok=1
for d in "$STANDBY" "$PRIMARY"; do
    census_constants "$d" || { c_ok=0; bad "(11) census failed on $(basename "$d"): $CENSUS_FAIL"; }
done
# no OTHER shipped script assigns any of the census's names (the whole shipped set)
others=0
for f in "$HARNESS_DIR/install.sh" "$HARNESS_DIR/failover-arm.sh" "$HARNESS_DIR/deploy-failover.sh" "$HARNESS_DIR/deploy-failover-standby.sh" "$HARNESS_DIR/systemd/failover-fence.sh" "$HARNESS_DIR/systemd/failover-fence-page-only.sh"; do
    n=$(grep -cE '(^[[:space:]]*((local|declare|export|readonly)[[:space:]]+([-][[:alnum:]]+[[:space:]]+)*)?(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE|ELAPSED_HEAD_GAP_MAX|ELAPSED_RATE_MIN_SPAN|OWN_HEAD_H)=)|(\(\([[:space:]]*(elapsed_floor|MARGIN_ELAPSED|N_HEAD|PROOF_MAX_AGE|ELAPSED_HEAD_GAP_MAX|ELAPSED_RATE_MIN_SPAN|OWN_HEAD_H)[[:space:]]*=)' "$f" 2>/dev/null)
    [[ "$n" == "0" ]] || { others=1; bad "(11) $(basename "$f") re-declares a derived constant ($n sites)"; }
done
if [[ $c_ok -eq 1 && $others -eq 0 ]]; then
    ok "(11) census: the 7 names are assigned EXACTLY at the derivation-site allowlist in each daemon (ELAPSED_HEAD_GAP_MAX=1 — 6.3 fix round 2, R3; ELAPSED_RATE_MIN_SPAN=24 and OWN_HEAD_H=16 — 6.3.1, D4); zero assignments anywhere else in the shipped set"
fi
# (11b) injection control: a stray re-declaration must be census-visible in EVERY spelling the
# (11) label claims to cover (panel FND-1 — the old control exercised ONLY the bare top-level
# form, so its red-capability was narrower than the claim). Each spelling is appended alone to a
# fresh copy and must drive the census RED; the bare form is kept and the prefixed/arithmetic
# forms (which evaded the old regex, panel-executed) are added.
inj_ct=0; inj_red=0; inj_miss=""
for spell in 'N_HEAD=7' 'local N_HEAD=7' 'declare -i N_HEAD=7' 'export PROOF_MAX_AGE=9' 'readonly elapsed_floor=5' ': $(( N_HEAD=7 ))' '(( PROOF_MAX_AGE = 9 ))' 'ELAPSED_HEAD_GAP_MAX=12' 'local ELAPSED_HEAD_GAP_MAX=12' '(( ELAPSED_HEAD_GAP_MAX = 12 ))' 'ELAPSED_RATE_MIN_SPAN=5' 'local ELAPSED_RATE_MIN_SPAN=5' 'OWN_HEAD_H=99' '(( OWN_HEAD_H = 99 ))'; do
    inj_ct=$((inj_ct + 1))
    cp "$STANDBY" "$WORK/inject.sh"; printf '\n%s\n' "$spell" >> "$WORK/inject.sh"
    if census_constants "$WORK/inject.sh"; then
        inj_miss="$inj_miss [$spell]"
    else
        inj_red=$((inj_red + 1))
    fi
done
if [[ "$inj_red" == "$inj_ct" ]]; then
    ok "(11b) census RED on ALL $inj_ct evading spellings (bare + local + declare -i + export + readonly + two arithmetic forms, the fifth name bare / local / arithmetic, and the 6.3.1 names bare / local / arithmetic): the control's red-capability matches the (11) claim's breadth"
else
    bad "(11b) $((inj_ct - inj_red))/$inj_ct spellings EVADED the broadened census:$inj_miss"
fi

# ── (12) twin byte-parity (the [fence-rot] extract+cmp ritual) ──────────────────────────────────
echo ""; echo "─── (12) twin: [proof-gate] byte-identical across both daemons ───"
if extract_twin '\[proof-gate\] spare-side relinquish-proof gate skeleton' '\[proof-gate\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(12) [proof-gate] block BYTE-IDENTICAL in both daemons ($(printf '%s' "$TWIN_P" | wc -c | tr -d ' ') bytes)"
else
    bad "(12) [proof-gate] twin blocks differ (primary=${#TWIN_P}B standby=${#TWIN_S}B)"
fi

rm -rf "$WORK" "$STUB_PARENT" "$MOCK_PARENT"
results_banner
