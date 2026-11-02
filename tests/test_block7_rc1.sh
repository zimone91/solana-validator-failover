#!/bin/bash
# v0.7 Block 7, trimmed for rc1 (TASK-BLOCK7-RC1.md): what the ARMED pair and the mainnet monitor-only phase still need. One suite, one section per item;
# each item is written red first on the AG-3 tip (c8989c1) and has its own mutants (mutate()).
#   (B7.1) _validator_pid is the validator, never an admin-client child of the daemon (set-identity / authorized-voter / contact-info / monitor / exit /
#          wait-for-restart-window): the unit's MainPID first, pgrep only as the fallback with the admin clients excluded - primary, standby, the fence
#          script and the arm ceremony (the last two are byte-identical copies of one function)
#   (B7.2) one instance per role: flock -n on "$STATE_DIR/.<role>.lock" at startup, before the first identity read; the second instance exits 3 with
#          one log line and one page SECOND INSTANCE REFUSED
#   (B7.3) the state file is written atomically (tmp + mv in the same directory, 0600); a torn file on load is one WARN, never an abort, and never a
#          lost lockout
#   (B7.4) fail-closed polarity at the two remaining AG stops: the primary's switch_to_staked and the standby's _prewarm_voter_add ask a positive
#          predicate (`if ! _ag_..._allowed`), so an undefined predicate withholds
#   (B7.5) DRY_RUN page storms: one dry page per ALERT_THROTTLE per reason (the primary's dry demote and the self-fence's dry pages), the standby's
#          cooldown / lockout WARN at most once per 60 s
# B7.6 (the version constant) is pinned in the `facts` job of .github/workflows/ci.yml, not here.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, mutate(), extract_region, load_seam.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Block 7 trimmed for rc1: the validator pid, one instance per role, an atomic state file, fail-closed AG stops, quiet DRY_RUN (v0.7)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/b7.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cut_src() { local f="$WORK/seam.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$$.$RANDOM"; sed -n '1,/MAIN LOOP/p' "$1" > "$f"; printf '%s' "$f"; }
STK="StakedPubkey111111111111111111111111111111"
UNS="UnstakedPubkey1111111111111111111111111111"

# ── (0) the anchors every section below stands on ──────────────────────────────────────────────────────────────────────
echo ""; echo "─── (0) the daemons and the scripts the sections read are all there and parse ───"
b7_missing=""
for f in "$PRIMARY" "$STANDBY" "$HARNESS_DIR/systemd/failover-fence.sh" "$HARNESS_DIR/failover-arm.sh"; do
    [[ -f "$f" ]] || b7_missing="$b7_missing $(basename "$f")"
done
[[ -z "$b7_missing" ]] && ok "(0) both daemons, the fence script and the arm ceremony are present" || bad "(0) missing:$b7_missing"

# ══ B7.1 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.1 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.2 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.2 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.3 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.3 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.4 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ── (B7.4) fail-closed polarity at the two remaining Alpenglow stops ──────────────────────────────────────────────────
echo ""; echo "─── (B7.4) the primary's re-take stop and the standby's pre-warm stop ask a positive predicate: an undefined predicate withholds ───"
# AG-3.1 gave the standby's TAKE this shape (`if ! _ag_take_allowed`); AG-1's form, `if _ag_mode; then <withhold>; fi`, lets an UNDEFINED predicate (rc 127) fall through to the mutation. Two such stops were left:
# the primary's switch_to_staked and the standby's _prewarm_voter_add. Both predicates are "never" in rc1; `_ag_mode` itself stays as the facts job pins it (unconditional `return 0`).
b74_pr_world() {   # b74_pr_world <script> <shadow|unset|ship> -> "rc=<switch_to_staked's rc>|withheld=<n>|admin=<n>|keypair=<n>": the primary's re-take, every gate before the stop mocked open
    local script="$1" mode="$2" src; src=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        EVF=$(mktemp); trap 'rm -f "$EVF"' EXIT
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; STAKED_KEYPAIR="$EVF.missing"; DRY_RUN=false; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15; TG_ENABLED=false
        _own_head_sample() { :; }; _fresh_proof_recheck() { return 0; }; _own_view_veto() { return 0; }
        mono_now() { echo 1000; }; save_state() { :; }; log_info() { :; }; log_warn() { :; }; log_error() { :; }; _watchdog_pet() { :; }
        _ag_take_withheld() { echo W >> "$EVF"; }
        alert() { case "$3" in *"keypair problem"*) echo K >> "$EVF" ;; esac; return 0; }
        timeout() { echo A >> "$EVF"; return 0; }
        case "$mode" in
            unset)  unset -f _ag_primary_retake_allowed ;;
            shadow) _ag_primary_retake_allowed() { return 0; } ;;
        esac
        switch_to_staked "recovery test"; rc=$?
        printf 'rc=%s|withheld=%s|admin=%s|keypair=%s' "$rc" "$(grep -c '^W$' "$EVF")" "$(grep -c '^A$' "$EVF")" "$(grep -c '^K$' "$EVF")"
    )
}
b74_sb_world() {   # b74_sb_world <script> <shadow|unset|ship> -> "admin=<n>": the standby's pre-warm with PREWARM_VOTER_ADD=true and DRY_RUN=false
    local script="$1" mode="$2" src; src=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        EVF=$(mktemp); trap 'rm -f "$EVF"' EXIT
        STAKED_PUBKEY="$STK"; STAKED_KEYPAIR="$EVF.kp"; DRY_RUN=false; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15; SOLANA_PATH="$EVF.bin"; LEDGER_PATH="$EVF.ledger"
        PREWARM_VOTER_ADD=true; _prewarm_done=0; _ag_pv_logged=0
        log_info() { :; }; log_warn() { :; }; log_error() { :; }; _watchdog_pet() { :; }
        timeout() { echo A >> "$EVF"; return 0; }
        case "$mode" in
            unset)  unset -f _ag_prewarm_allowed ;;
            shadow) _ag_prewarm_allowed() { return 0; } ;;
        esac
        _prewarm_voter_add; printf 'admin=%s' "$(grep -c '^A$' "$EVF")"
    )
}
p_b74_pr_closed() { [[ "$(b74_pr_world "$1" ship)" == "rc=1|withheld=1|admin=0|keypair=0" && "$(b74_pr_world "$1" unset)" == "rc=1|withheld=1|admin=0|keypair=0" ]]; }
p_b74_pr_open_when_allowed() { [[ "$(b74_pr_world "$1" shadow)" == "rc=1|withheld=0|admin=0|keypair=1" ]]; }
p_b74_sb_closed() { [[ "$(b74_sb_world "$1" ship)" == "admin=0" && "$(b74_sb_world "$1" unset)" == "admin=0" ]]; }
p_b74_sb_open_when_allowed() { [[ "$(b74_sb_world "$1" shadow)" == "admin=1" ]]; }
if p_b74_pr_closed "$PRIMARY" && p_b74_pr_open_when_allowed "$PRIMARY"; then
    ok "(B7.4a) primary switch_to_staked: as shipped, and with the predicate UNDEFINED (unset -f _ag_primary_retake_allowed), the re-take is withheld - rc 1, ONE _ag_take_withheld, no keypair test, no admin call; with the predicate shadowed to 'allowed' the stop is not what stops it (the next gate, the keypair test, answers)"
else
    bad "(B7.4a) primary stop: shipped=[$(b74_pr_world "$PRIMARY" ship)] undefined=[$(b74_pr_world "$PRIMARY" unset)] allowed=[$(b74_pr_world "$PRIMARY" shadow)]"
fi
if p_b74_sb_closed "$STANDBY" && p_b74_sb_open_when_allowed "$STANDBY"; then
    ok "(B7.4b) standby _prewarm_voter_add (PREWARM_VOTER_ADD=true, live): as shipped, and with _ag_prewarm_allowed UNDEFINED, ZERO admin calls; with the predicate shadowed to 'allowed' the add is issued once - the predicate is the gate"
else
    bad "(B7.4b) standby pre-warm: shipped=[$(b74_sb_world "$STANDBY" ship)] undefined=[$(b74_sb_world "$STANDBY" unset)] allowed=[$(b74_sb_world "$STANDBY" shadow)]"
fi
b74_fn_code() { sed -n "/^$2() {/,/^}/p" "$1" | grep -v '^[[:space:]]*#'; }
b74_shape_ok() {   # the stop's line, the predicate's one-line body, the facts pin of _ag_mode
    local pr_stop sb_first pp sp am_p am_s
    pr_stop=$(b74_fn_code "$PRIMARY" switch_to_staked | grep -c -x '    if ! _ag_primary_retake_allowed; then')
    sb_first=$(b74_fn_code "$STANDBY" _prewarm_voter_add | sed -n '2p')
    pp=$(grep -c -x '_ag_primary_retake_allowed() { return 1; }' "$PRIMARY"); sp=$(grep -c -x '_ag_prewarm_allowed() { return 1; }' "$STANDBY")
    am_p=$(grep -c -x '_ag_mode() { return 0; }' "$PRIMARY"); am_s=$(grep -c -x '_ag_mode() { return 0; }' "$STANDBY")
    [[ "$pr_stop" == "1" && "$sb_first" == "    if ! _ag_prewarm_allowed; then" && "$pp" == "1" && "$sp" == "1" && "$am_p" == "1" && "$am_s" == "1" ]]
}
if b74_shape_ok; then
    ok "(B7.4c) shapes: the primary's stop is 'if ! _ag_primary_retake_allowed; then' (once, in switch_to_staked), the standby's first statement is 'if ! _ag_prewarm_allowed; then'; both predicates are one line, 'return 1' (rc1: never); _ag_mode stays 'return 0' exactly once per daemon (the facts pin)"
else
    bad "(B7.4c) shapes: primary stop=$(b74_fn_code "$PRIMARY" switch_to_staked | grep -c -x '    if ! _ag_primary_retake_allowed; then') standby first=[$(b74_fn_code "$STANDBY" _prewarm_voter_add | sed -n '2p')] predicates=$(grep -c -x '_ag_primary_retake_allowed() { return 1; }' "$PRIMARY")/$(grep -c -x '_ag_prewarm_allowed() { return 1; }' "$STANDBY")"
fi
b74_ok=1; b74_rows=""
b74_ctl() {   # b74_ctl <label> <script> <sed expr> <predicate over a script>: holds on the shipped script, FAILS on the mutant
    local label="$1" script="$2" expr="$3" pred="$4" m="$WORK/b74-$1.sh" rv mv
    if ! mutate "$script" "$expr" "$m"; then b74_ok=0; b74_rows="$b74_rows $label:NOT-APPLIED"; return; fi
    "$pred" "$script" && rv=y || rv=n; "$pred" "$m" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then b74_rows="$b74_rows $label:red"; else b74_ok=0; b74_rows="$b74_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
b74_ctl pr-polarity-open "$PRIMARY" '/^switch_to_staked() {/,/^}/ s/^    if ! _ag_primary_retake_allowed; then$/    if _ag_primary_retake_allowed; then/' p_b74_pr_closed
b74_ctl pr-stop-removed "$PRIMARY" '/^switch_to_staked() {/,/^}/ s/^    if ! _ag_primary_retake_allowed; then$/    if false; then/' p_b74_pr_closed
b74_ctl pr-predicate-allows "$PRIMARY" 's/^_ag_primary_retake_allowed() { return 1; }$/_ag_primary_retake_allowed() { return 0; }/' p_b74_pr_closed
b74_ctl pr-gate-ignored "$PRIMARY" '/^switch_to_staked() {/,/^}/ s/^    if ! _ag_primary_retake_allowed; then$/    if true; then/' p_b74_pr_open_when_allowed
b74_ctl sb-polarity-open "$STANDBY" '/^_prewarm_voter_add() {/,/^}/ s/^    if ! _ag_prewarm_allowed; then$/    if _ag_prewarm_allowed; then/' p_b74_sb_closed
b74_ctl sb-stop-removed "$STANDBY" '/^_prewarm_voter_add() {/,/^}/ s/^    if ! _ag_prewarm_allowed; then$/    if false; then/' p_b74_sb_closed
b74_ctl sb-predicate-allows "$STANDBY" 's/^_ag_prewarm_allowed() { return 1; }$/_ag_prewarm_allowed() { return 0; }/' p_b74_sb_closed
b74_ctl sb-gate-ignored "$STANDBY" '/^_prewarm_voter_add() {/,/^}/ s/^    if ! _ag_prewarm_allowed; then$/    if true; then/' p_b74_sb_open_when_allowed
[[ $b74_ok -eq 1 ]] && ok "(B7.4d) CONTROLS: the polarity opened, the stop removed, a predicate that allows, a gate that ignores its predicate (always withholds) - each turns its case red:$b74_rows" || bad "(B7.4d) a control is not red:$b74_rows"
# ══ B7.4 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.5 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.5 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

results_banner
