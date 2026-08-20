#!/bin/bash
# v0.7 (Block 5 skeleton, №1): ONE arm-state — the startup refusal on DRY_RUN=true + REAL fence
# unit (addendum §2.3 [rev3/№1]). After Block 5 there are two arm-states (DRY_RUN in the env +
# WHICH fence unit file is installed); the deadly combination is DRY_RUN=true + the REAL fence
# unit — the fence can stop a LIVE validator while the operator believes the system inert.
# Resolution = the project rule (ambiguity → inert + page): refuse to start + CRITICAL.
#
# Drives the REAL shipped code two ways (the test_timing_fatal idiom — subshell seam cuts):
#   (A)  _enforce_one_arm_state directly, _fence_unit_state mocked per case, BOTH daemons:
#        true+real → exit 1 + FATAL + CRITICAL alert naming BOTH alignment paths ("failover arm"
#        and "DRY_RUN=false"); false+real → silent proceed (armed, normal); true+page-only →
#        silent proceed (soak, normal); true+none → silent proceed (today's world — structurally
#        inert); false+page-only → WARN (v0.6.x behavior, §2.3 third row), proceeds.
#   (B)  the REAL startup_checks region of BOTH daemons (the uniq_run idiom: prerequisite mocks +
#        a sentinel exit 99 just PAST the №1 check region — standby: enforce_crossnode_timing_safety;
#        primary: load_state) — proves the CALL SITE is wired, not just the function.
#   (C)  byte-identity of the shared [one-arm-state] block across the daemons (extract_twin).
#   (D)  the REAL _fence_unit_state classifier over temp unit paths: none / real / page-only /
#        BOTH-present → real (the fail-toward-refusal branch).
#   (E)  inert-today: with the shipped canonical /etc paths (no mock) the answer on every test
#        host is `none`, and the shared block contains ZERO systemctl invocations (hot-path purity).
#
# RED (captured pre-implementation to red-block5-skeleton.log): the check does not exist at
# 9dff74f — (A)/(C)/(D)/(E) fail loudly (function absent / empty extraction) and (B) shows
# true+real REACHING THE SENTINEL (99): startup proceeds where it must refuse.
#
# harness: tests/lib/harness.sh — ok/bad+banners, paths, extract_twin. The subshell drivers and
# their mock blocks stay local (per-case _fence_unit_state mocks are the point of the suite).

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

RES_DIR=$(mktemp -d)
trap 'rm -rf "$RES_DIR"' EXIT

# ── (A) arm_fn <daemon> <DRY_RUN> <fence-state> — drive the REAL _enforce_one_arm_state ─────────
# Sourced up to MAIN LOOP; _fence_unit_state mocked; observables land in $RES_DIR files:
#   rc (exit code of the check), warn / err / alert (captured sink texts).
arm_fn() {
  local daemon="$1" dr="$2" fus="$3"
  rm -f "$RES_DIR/rc" "$RES_DIR/warn" "$RES_DIR/err" "$RES_DIR/alert"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$daemon" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    STAKED_PUBKEY="S1"; TG_ENABLED=false
    log(){ :;}; log_info(){ :;}
    log_warn(){ printf '%s\n' "$*" >> "$RES_DIR/warn"; }
    log_error(){ printf '%s\n' "$*" >> "$RES_DIR/err"; }
    alert(){ printf '%s :: %s\n' "$3" "$1" >> "$RES_DIR/alert"; }
    alert_warn(){ :;}; alert_info(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
    DRY_RUN="$dr"
    _FUS_MOCK="$fus"
    _fence_unit_state(){ echo "$_FUS_MOCK"; }
    ( _enforce_one_arm_state ) >/dev/null 2>&1
    echo "$?" > "$RES_DIR/rc"
  ) >/dev/null 2>&1
  cat "$RES_DIR/rc" 2>/dev/null
}

# ── (B) startup-region drivers (the uniq_run idiom from test_timing_fatal) ──────────────────────
# Echo the exit code: 1 = the №1 refusal fired; 99 = reached the sentinel PAST the check region.
arm_startup_standby() {  # $1=DRY_RUN $2=fence-state
  local res; res=$(mktemp)
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  VALIDATOR_TYPE=agave
  SP=$(mktemp -d); : > "$SP/agave-validator"; : > "$SP/solana-keygen"; SOLANA_PATH="$SP"
  STAKED_KEYPAIR=/x; UNSTAKED_KEYPAIR=/y; STAKED_PUBKEY_OVERRIDE=""; VOTE_PUBKEY="V1"
  DELINQUENCY_WINDOW_SIZE=10; DELINQUENCY_WINDOW_THRESHOLD=7
  VOTE_LIVENESS_VERIFY=true; VOTE_LIVENESS_EPSILON=0; VOTE_LIVENESS_MIN_INTERVAL=10
  GIVE_BACK_MODE=manual; WITNESS_FASTPATH=false; PRIMARY_UNSTAKED_PUBKEY=""
  detect_ledger_path(){ LEDGER_PATH=/tmp/led; }
  get_validator_args(){ echo ""; }                     # no --identity → startup-identity check skipped
  validate_keypair_file(){ [[ "$1" == "$STAKED_KEYPAIR" ]] && echo "STAKEDPK" || echo "UNSTAKEDPK"; }
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}; alert(){ :;}; alert_warn(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  validate_numeric_config(){ :; }
  announce_config_drift(){ :; }
  enforce_crossnode_timing_safety(){ exit 99; }        # sentinel: just PAST the №1 check region
  DRY_RUN="$1"; _FUS_MOCK="$2"
  _fence_unit_state(){ echo "$_FUS_MOCK"; }
  exit(){ printf '%s' "$1" > "$res"; rm -rf "$SP"; command exit "$1"; }
  startup_checks >/dev/null 2>&1 </dev/null
  ) >/dev/null 2>&1
  cat "$res" 2>/dev/null; rm -f "$res"
}

arm_startup_primary() {  # $1=DRY_RUN $2=fence-state
  local res; res=$(mktemp)
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
  # shellcheck disable=SC1090
  source "$SRC"; rm -f "$SRC"
  VALIDATOR_TYPE=agave
  SP=$(mktemp -d); : > "$SP/agave-validator"; : > "$SP/solana-keygen"; SOLANA_PATH="$SP"
  STAKED_KEYPAIR=/x; UNSTAKED_KEYPAIR=/y
  RECOVERY_MODE=manual; SETIDENTITY_TIMEOUT=8; PRIMARY_SELF_FENCE=false
  DELINQUENCY_WINDOW_SIZE=10; DELINQUENCY_WINDOW_THRESHOLD=7
  TIER2_RPC=""; TIER3_RPC=""                            # M8 vantage warn short-circuits on empty
  detect_ledger_path(){ LEDGER_PATH=/tmp/led; }
  detect_tower_base(){ :; }
  get_validator_args(){ echo ""; }                     # no --identity → startup-identity check skipped
  validate_keypair_file(){ [[ "$1" == "$STAKED_KEYPAIR" ]] && echo "STAKEDPK" || echo "UNSTAKEDPK"; }
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}; alert(){ :;}; alert_warn(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  validate_numeric_config(){ :; }
  announce_config_drift(){ :; }
  load_state(){ exit 99; }                             # sentinel: just PAST the №1 check region
  DRY_RUN="$1"; _FUS_MOCK="$2"
  _fence_unit_state(){ echo "$_FUS_MOCK"; }
  exit(){ printf '%s' "$1" > "$res"; rm -rf "$SP"; command exit "$1"; }
  startup_checks >/dev/null 2>&1 </dev/null
  ) >/dev/null 2>&1
  cat "$res" 2>/dev/null; rm -f "$res"
}

# ── (D) fus_probe <real?> <pageonly?> — the REAL classifier over temp unit paths ────────────────
fus_probe() {
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    D=$(mktemp -d)
    FENCE_UNIT_REAL="$D/solana-failover-fence.service"
    FENCE_UNIT_PAGE_ONLY="$D/solana-failover-fence-page-only.service"
    [[ "$1" == "1" ]] && : > "$FENCE_UNIT_REAL"
    [[ "$2" == "1" ]] && : > "$FENCE_UNIT_PAGE_ONLY"
    _fence_unit_state
    rm -rf "$D"
  ) 2>/dev/null
}

title_banner "ONE arm-state: refuse DRY_RUN=true + REAL fence unit (v0.7 Block 5 skeleton, №1)"

echo ""; echo "─── (1) the deadly combination: DRY_RUN=true + real → FATAL, both daemons ───"
rc_p=$(arm_fn "$PRIMARY" true real)
[[ "$rc_p" == "1" ]] \
    && ok "(1a) PRIMARY: true+real → refuses (exit 1)" \
    || bad "(1a) PRIMARY true+real did not refuse (rc='$rc_p')"
grep -q "FATAL" "$RES_DIR/err" 2>/dev/null \
    && ok "(1b) PRIMARY: the refusal logs FATAL" \
    || bad "(1b) PRIMARY refusal missing the FATAL log_error"
rc_s=$(arm_fn "$STANDBY" true real)
[[ "$rc_s" == "1" ]] \
    && ok "(1c) STANDBY: true+real → refuses (exit 1)" \
    || bad "(1c) STANDBY true+real did not refuse (rc='$rc_s')"

echo ""; echo "─── (2) the CRITICAL page names BOTH alignment paths ───"
# (still holding the standby's capture from 1c — the byte-identity case (5) covers the twin)
if [[ -s "$RES_DIR/alert" ]] && grep -q "failover arm" "$RES_DIR/alert" && grep -q "DRY_RUN=false" "$RES_DIR/alert"; then
    ok "(2) CRITICAL alert fired and names both paths: re-run 'failover arm' AND set DRY_RUN=false"
else
    bad "(2) CRITICAL alert missing or does not name both alignment paths ($(cat "$RES_DIR/alert" 2>/dev/null))"
fi

echo ""; echo "─── (3) every other combination proceeds (rc 0) ───"
for d in "$PRIMARY" "$STANDBY"; do
    dn=$(basename "$d" | sed 's/solana-\(.*\)-failover.sh/\1/')
    rc=$(arm_fn "$d" false real)
    [[ "$rc" == "0" && ! -s "$RES_DIR/warn" && ! -s "$RES_DIR/err" && ! -s "$RES_DIR/alert" ]] \
        && ok "(3a-$dn) false+real (armed, normal) → silent proceed" \
        || bad "(3a-$dn) false+real wrong (rc='$rc' warn=$(cat "$RES_DIR/warn" 2>/dev/null))"
    rc=$(arm_fn "$d" true page-only)
    [[ "$rc" == "0" && ! -s "$RES_DIR/warn" && ! -s "$RES_DIR/err" && ! -s "$RES_DIR/alert" ]] \
        && ok "(3b-$dn) true+page-only (soak, normal) → silent proceed" \
        || bad "(3b-$dn) true+page-only wrong (rc='$rc')"
    rc=$(arm_fn "$d" true none)
    [[ "$rc" == "0" && ! -s "$RES_DIR/warn" && ! -s "$RES_DIR/err" && ! -s "$RES_DIR/alert" ]] \
        && ok "(3c-$dn) true+none (today's world) → silent proceed (structurally inert)" \
        || bad "(3c-$dn) true+none wrong (rc='$rc')"
    rc=$(arm_fn "$d" false none)
    [[ "$rc" == "0" && ! -s "$RES_DIR/warn" && ! -s "$RES_DIR/err" && ! -s "$RES_DIR/alert" ]] \
        && ok "(3d-$dn) false+none → silent proceed" \
        || bad "(3d-$dn) false+none wrong (rc='$rc')"
done

echo ""; echo "─── (4) false+page-only → WARN (the §2.3 third row: v0.6.x behavior), proceeds ───"
rc=$(arm_fn "$STANDBY" false page-only)
if [[ "$rc" == "0" ]] && grep -q "page-only" "$RES_DIR/warn" 2>/dev/null && grep -q "not fenced" "$RES_DIR/warn" 2>/dev/null; then
    ok "(4a) STANDBY false+page-only: proceeds (rc 0) with the not-fenced WARN"
else
    bad "(4a) STANDBY false+page-only wrong (rc='$rc' warn='$(cat "$RES_DIR/warn" 2>/dev/null)')"
fi
[[ ! -s "$RES_DIR/alert" && ! -s "$RES_DIR/err" ]] \
    && ok "(4b) the WARN row pages nothing and logs no error (not fatal by design)" \
    || bad "(4b) false+page-only escalated beyond WARN"
rc=$(arm_fn "$PRIMARY" false page-only)
[[ "$rc" == "0" ]] && grep -q "page-only" "$RES_DIR/warn" 2>/dev/null \
    && ok "(4c) PRIMARY false+page-only: proceeds with the WARN" \
    || bad "(4c) PRIMARY false+page-only wrong (rc='$rc')"

echo ""; echo "─── (5) shared block byte-identical across the daemons ───"
if extract_twin 'one-arm-state\] shared classifier' 'one-arm-state\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(5) [one-arm-state] block byte-identical in both daemons ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)"
else
    bad "(5) [one-arm-state] block differs between the daemons (twin drift — the S-1 blocker class)"
fi

echo ""; echo "─── (6) the REAL classifier: none / real / page-only / BOTH-present → real ───"
[[ "$(fus_probe 0 0)" == "none" ]] \
    && ok "(6a) neither unit file → none" \
    || bad "(6a) empty dir classified '$(fus_probe 0 0)' (want none)"
[[ "$(fus_probe 1 0)" == "real" ]] \
    && ok "(6b) real unit file only → real" \
    || bad "(6b) real-only classified '$(fus_probe 1 0)' (want real)"
[[ "$(fus_probe 0 1)" == "page-only" ]] \
    && ok "(6c) page-only unit file only → page-only" \
    || bad "(6c) page-only-only classified '$(fus_probe 0 1)' (want page-only)"
[[ "$(fus_probe 1 1)" == "real" ]] \
    && ok "(6d) BOTH present → real (ambiguity fails TOWARD the refusal, §2.3 — never toward page-only)" \
    || bad "(6d) both-present classified '$(fus_probe 1 1)' (want real — the fail-toward-refusal branch)"

echo ""; echo "─── (7) startup-region wiring: the REAL startup_checks refuses / proceeds at the call site ───"
r=$(arm_startup_standby true real)
[[ "$r" == "1" ]] \
    && ok "(7a) STANDBY startup_checks: true+real → REFUSED (exit 1) at the shipped call site" \
    || bad "(7a) STANDBY startup_checks true+real proceeded (got '$r'; 99 = reached the sentinel past the check)"
r=$(arm_startup_standby true none)
[[ "$r" == "99" ]] \
    && ok "(7b) STANDBY startup_checks: true+none → proceeds past the check to the sentinel (99)" \
    || bad "(7b) STANDBY startup_checks true+none wrong (got '$r')"
r=$(arm_startup_primary true real)
[[ "$r" == "1" ]] \
    && ok "(7c) PRIMARY startup_checks: true+real → REFUSED (exit 1) at the shipped call site" \
    || bad "(7c) PRIMARY startup_checks true+real proceeded (got '$r'; 99 = reached the sentinel past the check)"
r=$(arm_startup_primary true none)
[[ "$r" == "99" ]] \
    && ok "(7d) PRIMARY startup_checks: true+none → proceeds past the check to the sentinel (99)" \
    || bad "(7d) PRIMARY startup_checks true+none wrong (got '$r')"

echo ""; echo "─── (8) hot-path purity + inert today ───"
# The shared block must classify by pure file tests: a hung systemctl must never wedge startup,
# and the block runs on bash 3.2 + macOS in every harness. (The daemons' OTHER systemctl sites —
# hard-stop/mask — are outside this block and untouched.) Comment lines are stripped first: the
# block's own comments NAME systemctl to forbid it — only executable lines count.
if [[ -n "$TWIN_P" ]] && ! printf '%s\n' "$TWIN_P" | grep -v '^[[:space:]]*#' | grep -q "systemctl"; then
    ok "(8a) zero systemctl invocations on the block's executable lines (pure test -e classification)"
else
    bad "(8a) the [one-arm-state] block invokes systemctl on an executable line (or was not extracted)"
fi
# With the SHIPPED canonical /etc/systemd/system paths (no mock, no override): no test host has a
# fence unit installed — the answer is `none`, i.e. the №1 refusal is structurally inert today.
inert=$(
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    _fence_unit_state
  ) 2>/dev/null
)
[[ "$inert" == "none" ]] \
    && ok "(8b) shipped canonical paths on THIS host → none (every host today: the refusal is inert)" \
    || bad "(8b) shipped-path classification on this host: '$inert' (want none — is a fence unit installed here?!)"

echo ""; echo "─── (9) non-vacuous: both daemons CALL the check from startup (the F-e idiom) ───"
# Leading whitespace REQUIRED: the call inside startup_checks is indented; the function
# definition sits at column 0 and must not satisfy this check (a definition nobody calls).
cs_p=$(grep -c '^[[:space:]][[:space:]]*_enforce_one_arm_state' "$PRIMARY")
cs_s=$(grep -c '^[[:space:]][[:space:]]*_enforce_one_arm_state' "$STANDBY")
[[ "$cs_p" -ge 1 && "$cs_s" -ge 1 ]] \
    && ok "(9) shipped call sites present (primary=$cs_p standby=$cs_s)" \
    || bad "(9) call site missing (primary=$cs_p standby=$cs_s)"

# ── (D) refusal-page delivery outcome (reviewer fix, same push as the skeleton) ─────────────────
#    The refusing daemon EXITS before the main loop — the only place flush_pending_alerts runs —
#    so an undelivered CRITICAL page would sit queued forever (each next start refuses and queues
#    again). The fix: one bounded retry after the alert, then the journal states the OUTCOME
#    (delivered vs queued-into-a-queue-this-daemon-will-not-drain). Bites hardest on the
#    entry-blocker hosts (bash 5.2 pre-v0.6.10: Telegram delivery itself broken) — a mute refusal
#    there is the silent-failure class. Driver keeps the REAL alert() + flush_pending_alerts and
#    scripts send_telegram.
deliv_fn() {  # $1=daemon  $2=send_telegram rc (0=deliverable, 1=telegram down)
  rm -f "$RES_DIR/rc" "$RES_DIR/err" "$RES_DIR/tgcount"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$1" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    STAKED_PUBKEY="S1"
    log(){ :;}; log_info(){ :;}; log_warn(){ :;}
    log_error(){ printf '%s\n' "$*" >> "$RES_DIR/err"; }
    send_webhook(){ :;}; sleep(){ :;}
    _TG_RC="$2"
    send_telegram(){ echo x >> "$RES_DIR/tgcount"; return "$_TG_RC"; }
    DRY_RUN=true
    _fence_unit_state(){ echo "real"; }
    ( _enforce_one_arm_state ) >/dev/null 2>&1
    echo "$?" > "$RES_DIR/rc"
  ) >/dev/null 2>&1
}
echo ""; echo "─── (D) the refusal page checks its own delivery (journal states the outcome) ───"
for D in "$PRIMARY" "$STANDBY"; do
    dn=$(basename "$D" | sed 's/solana-\(.*\)-failover.sh/\1/')
    deliv_fn "$D" 0
    tg=$(wc -l < "$RES_DIR/tgcount" 2>/dev/null | tr -d ' ')
    [[ "$(cat "$RES_DIR/rc")" == "1" && "$tg" == "1" ]] && grep -q "delivered" "$RES_DIR/err" \
        && ok "(D1:$dn) telegram OK → still refuses (rc 1), one send, journal says the page was delivered" \
        || bad "(D1:$dn) delivered-outcome wrong (rc=$(cat "$RES_DIR/rc" 2>/dev/null) sends=$tg err='$(cat "$RES_DIR/err" 2>/dev/null | tr '\n' ';')')"
    deliv_fn "$D" 1
    tg=$(wc -l < "$RES_DIR/tgcount" 2>/dev/null | tr -d ' ')
    [[ "$(cat "$RES_DIR/rc")" == "1" && "$tg" == "2" ]] && grep -q "NOT delivered" "$RES_DIR/err" && grep -q "journalctl" "$RES_DIR/err" \
        && ok "(D2:$dn) telegram down → bounded retry (two sends), journal says NOT delivered + queue-never-drained + journalctl-is-your-record" \
        || bad "(D2:$dn) mute-refusal path (rc=$(cat "$RES_DIR/rc" 2>/dev/null) sends=$tg err='$(cat "$RES_DIR/err" 2>/dev/null | tr '\n' ';')')"
done

results_banner
