#!/bin/bash
# v0.6.9 (M9): cross-node timing violations are FATAL (opt-out). v0.6.6–v0.6.8 ran
# `check_crossnode_timing_safety || true` — a hand-edited TAKEOVER_DELAY=15 booted with only a warn.
# Drives the REAL shipped enforce_crossnode_timing_safety (sourced up to MAIN LOOP) in subshells.
#   (F-a) violating config (15 < 30+30) → exit 1 + 🚨 REFUSING TO START page
#   (F-b) ALLOW_UNSAFE_TIMING=true → proceeds (rc 0) with the warn path (alert_warn fired)
#   (F-c) compliant config → proceeds silently (rc 0, no alert/alert_warn)
#   (F-d)  v0.6.9 (B2) BACKUP role floor = max(120, STANDBY_TAKEOVER_DELAY+liveness+margin): 120 passes;
#          a hand-edited 70 (>= old STANDBY floor 60, < BACKUP 120) is now FATAL — closes the double-sign hole
#   (F-d2) BACKUP floor SCALES above 120 with a larger STANDBY delay (visibility-driven)
#   (F-d3) legacy config (no FAILOVER_ROLE) DERIVES BACKUP from STANDBY_TAKEOVER_DELAY < TAKEOVER_DELAY
#   (F-d4) explicit STANDBY keeps the small floor (the live prod first spare is not refused)
#   (F-e) NON-VACUOUS CONTROL: the shipped call site no longer carries `|| true`; the v0.6.8
#         baseline did (warn-only) — proves the escalation is new and wired
#   (U)   v0.7 (pre-Block-4, №3): unstaked-uniqueness startup refusal — drives the REAL standby
#         startup_checks (the test_primary_selffence_n7_votepubkey idiom: prerequisite mocks +
#         a validate_numeric_config sentinel exit 99 just past the refusal region):
#         (U-a) own UNSTAKED_PUBKEY == PRIMARY_UNSTAKED_PUBKEY → REFUSES (exit 1, shared-key
#               message); (U-b) distinct keys → passes to the sentinel; (U-c) empty
#               PRIMARY_UNSTAKED_PUBKEY → passes (nothing to compare); (U-d) own key ∈ a
#               MULTI-key PRIMARY_UNSTAKED_PUBKEY list → REFUSES (the reviewer's ∈ semantics —
#               PRIMARY_UNSTAKED_PUBKEY is space-separated)
#         RED (captured pre-implementation): U-a and U-d reach the sentinel (99) instead of
#         refusing — no daemon line compares the two variables at 94d64a6.

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
V068="$DIR/../../0.6.8/failover-v0.6.8/solana-standby-failover.sh"
[[ -f "$STANDBY" ]] || { echo "  ❌ standby script not found"; exit 1; }

# rc + observables of enforce_crossnode_timing_safety under the given knobs
#   $1=TAKEOVER_DELAY $2=EXPECTED $3=MARGIN $4=ALLOW_UNSAFE_TIMING
run_enforce() {
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; TG_ENABLED=false
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    send_telegram(){ return 0; }; send_webhook(){ :; }
    A=0; alert(){ A=$((A+1)); }
    W=0; alert_warn(){ W=$((W+1)); }
    TAKEOVER_DELAY="$1"; EXPECTED_PRIMARY_SELF_FENCE_SECS="$2"; SELF_FENCE_MARGIN_SECS="$3"; ALLOW_UNSAFE_TIMING="$4"
    # v0.6.9 (B2): role-aware floor inputs. $5=FAILOVER_ROLE (""=derive), $6=STANDBY_TAKEOVER_DELAY, $7=VOTE_LIVENESS_MIN_INTERVAL.
    FAILOVER_ROLE="${5:-}"; STANDBY_TAKEOVER_DELAY="${6:-}"; VOTE_LIVENESS_MIN_INTERVAL="${7:-10}"
    ( enforce_crossnode_timing_safety ) >/dev/null 2>&1   # inner () absorbs the exit 1
    rc=$?
    # the inner subshell hid the counters — re-run visible for observables when it does NOT exit
    A=0; W=0
    if [[ $rc -eq 0 ]]; then enforce_crossnode_timing_safety >/dev/null 2>&1; fi
    printf 'rc=%s|alerts=%s|warns=%s\n' "$rc" "$A" "$W"
  )
}
field(){ printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

echo "============================================="
echo "  Cross-node timing violations are FATAL (v0.6.9 M9)"
echo "============================================="

echo ""; echo "─── (F-a) violating config → exit 1 ───"
out=$(run_enforce 15 30 30 false)
[[ "$(field "$out" rc)" == "1" ]] \
    && ok "(F-a) TAKEOVER_DELAY=15 < 60 with ALLOW_UNSAFE_TIMING=false → refused to start (exit 1)" \
    || bad "(F-a) violation did not exit 1 ($out)"

echo ""; echo "─── (F-b) ALLOW_UNSAFE_TIMING=true → warn-and-continue ───"
out=$(run_enforce 15 30 30 true)
[[ "$(field "$out" rc)" == "0" && "$(field "$out" warns)" -ge 1 ]] \
    && ok "(F-b) override proceeds (rc 0) and the warn path fired (warns=$(field "$out" warns))" \
    || bad "(F-b) override wrong ($out)"

echo ""; echo "─── (F-c) compliant config → silent pass ───"
out=$(run_enforce 60 30 30 false)
[[ "$(field "$out" rc)" == "0" && "$(field "$out" alerts)" == "0" && "$(field "$out" warns)" == "0" ]] \
    && ok "(F-c) 60 >= 60 → rc 0, no alert, no warn" \
    || bad "(F-c) compliant config not silent ($out)"

echo ""; echo "─── (F-d) v0.6.9 (B2): BACKUP role floor = max(120, STANDBY_TAKEOVER_DELAY+liveness+margin) ───"
# A BACKUP (later spare) must outwait the STANDBY's take becoming externally visible, not just the
# PRIMARY self-fence. With STANDBY_TAKEOVER_DELAY=60, liveness=10, margin=30 → floor = max(120,100) = 120.
rc_ok=$(field "$(run_enforce 120 30 30 false BACKUP 60 10)" rc)       # 120 >= 120 → pass
rc_hole=$(field "$(run_enforce 70 30 30 false BACKUP 60 10)" rc)      # THE HOLE: 70 boots under the old
                                                                     # STANDBY formula (70>=60) but < the
                                                                     # BACKUP floor 120 → must now be fatal
[[ "$rc_ok" == "0" && "$rc_hole" == "1" ]] \
    && ok "(F-d) BACKUP: 120s passes; a hand-edited 70s (>= old STANDBY floor 60, < BACKUP 120) is now FATAL" \
    || bad "(F-d) BACKUP floor wrong (120→rc=$rc_ok, 70→rc=$rc_hole)"

echo ""; echo "─── (F-d2) BACKUP floor SCALES above 120 with a larger STANDBY delay ───"
# STANDBY_TAKEOVER_DELAY=100 → floor = max(120, 100+10+30=140) = 140.
rc_lo=$(field "$(run_enforce 130 30 30 false BACKUP 100 10)" rc)      # 130 < 140 → fatal
rc_hi=$(field "$(run_enforce 140 30 30 false BACKUP 100 10)" rc)      # 140 >= 140 → pass
[[ "$rc_lo" == "1" && "$rc_hi" == "0" ]] \
    && ok "(F-d2) BACKUP floor scales: 130<140 fatal, 140>=140 ok (visibility-driven, not fixed 120)" \
    || bad "(F-d2) BACKUP floor did not scale (130→rc=$rc_lo, 140→rc=$rc_hi)"

echo ""; echo "─── (F-d3) legacy config (no FAILOVER_ROLE) DERIVES BACKUP from a smaller STANDBY delay ───"
# No FAILOVER_ROLE, but STANDBY_TAKEOVER_DELAY=60 < our TAKEOVER_DELAY=70 → derived BACKUP → floor 120 → fatal.
rc_derive=$(field "$(run_enforce 70 30 30 false '' 60 10)" rc)
[[ "$rc_derive" == "1" ]] \
    && ok "(F-d3) derived BACKUP (STANDBY_TAKEOVER_DELAY 60 < 70) is fatal even without an explicit role" \
    || bad "(F-d3) derivation missed the BACKUP hole ($rc_derive)"

echo ""; echo "─── (F-d4) explicit STANDBY keeps the small floor (prod first-spare not broken) ───"
# FAILOVER_ROLE=STANDBY with TAKEOVER_DELAY=60 == its own delay → floor = EXPECTED+MARGIN = 60 → pass.
rc_std=$(field "$(run_enforce 60 30 30 false STANDBY 60 10)" rc)
[[ "$rc_std" == "0" ]] \
    && ok "(F-d4) explicit STANDBY, delay 60 → floor 60 → proceeds (live prod STANDBY unaffected)" \
    || bad "(F-d4) STANDBY floor regressed ($rc_std)"

echo ""; echo "─── (F-d5) Phase-B2 (F1): BACKUP floor ALSO includes the PRIMARY-self-fence term ───"
# A BACKUP must clear max(EXPECTED+margin, 120, std+liveness+margin). With EXPECTED=150,margin=30 the
# PRIMARY floor is 180 > 120; the B2 code dropped that term and BOOTED a BACKUP at 120 → double-sign
# with the PRIMARY. Revert Fix A (drop the EXPECTED+margin seed) → the first line goes rc0 (red).
rc_pf_lo=$(field "$(run_enforce 120 150 30 false BACKUP 60 10)" rc)   # 120 < 180 → now FATAL
rc_pf_ok=$(field "$(run_enforce 180 150 30 false BACKUP 60 10)" rc)   # 180 >= 180 → pass
[[ "$rc_pf_lo" == "1" && "$rc_pf_ok" == "0" ]] \
    && ok "(F-d5) BACKUP EXPECTED=150 → floor 180: 120 FATAL, 180 ok (PRIMARY-self-fence term restored)" \
    || bad "(F-d5) BACKUP dropped the PRIMARY floor (120→rc=$rc_pf_lo, 180→rc=$rc_pf_ok)"

echo ""; echo "─── (F-d6) Phase-B2 (S-2): a BACKUP with no positive STANDBY_TAKEOVER_DELAY REFUSES (fail-closed) ───"
# Simple-mode BACKUP left STANDBY_TAKEOVER_DELAY empty → the visibility floor is uncomputable → refuse,
# never boot with a guessed 0. With std set it proceeds normally.
rc_nostd=$(field "$(run_enforce 120 30 30 false BACKUP '' 10)" rc)    # empty std → FATAL
rc_wstd=$(field "$(run_enforce 120 30 30 false BACKUP 60 10)" rc)     # std=60 → floor 120 → pass
[[ "$rc_nostd" == "1" && "$rc_wstd" == "0" ]] \
    && ok "(F-d6) BACKUP missing STANDBY_TAKEOVER_DELAY refuses; with std=60 it proceeds" \
    || bad "(F-d6) missing-std handling wrong (''→rc=$rc_nostd, 60→rc=$rc_wstd)"

echo ""; echo "─── (F-d7) Phase-B2 (F2): FAILOVER_ROLE is normalized (lowercase/whitespace honored as the EXPLICIT role) ───"
# Use STANDBY_TAKEOVER_DELAY >= TAKEOVER_DELAY so the DERIVATION heuristic would leave a non-canonical
# role as STANDBY (loose floor 60 → boots). ONLY the trim+uppercase normalization makes 'backup' /
# ' BACKUP ' the explicit BACKUP → the stricter visibility floor. Revert Fix C → these boot (red).
rc_lc_lo=$(field "$(run_enforce 100 30 30 false 'backup' 200 10)" rc)    # norm→BACKUP, floor max(60,120,240)=240; 100<240 → FATAL
rc_ws_lo=$(field "$(run_enforce 100 30 30 false ' BACKUP ' 200 10)" rc)  # whitespace-trim→BACKUP; same 240 floor → FATAL
rc_lc_ok=$(field "$(run_enforce 300 30 30 false 'backup' 200 10)" rc)    # norm→BACKUP, floor 240; 300≥240 → pass
[[ "$rc_lc_lo" == "1" && "$rc_ws_lo" == "1" && "$rc_lc_ok" == "0" ]] \
    && ok "(F-d7) 'backup'/' BACKUP ' normalized to explicit BACKUP (derivation would've stayed STANDBY): 100 FATAL, 300 ok" \
    || bad "(F-d7) FAILOVER_ROLE normalization wrong (lc100→$rc_lc_lo ws100→$rc_ws_lo lc300→$rc_lc_ok)"

echo ""; echo "─── (F-d8) STANDBY path intact: role-less prod STANDBY@60 boots; STANDBY@50 refuses ───"
rc_rl60=$(field "$(run_enforce 60 30 30 false '' '' 10)" rc)         # role-less prod STANDBY → floor 60 → boots
rc_sb50=$(field "$(run_enforce 50 30 30 false STANDBY 50 10)" rc)    # STANDBY 50 < 60 → FATAL
[[ "$rc_rl60" == "0" && "$rc_sb50" == "1" ]] \
    && ok "(F-d8) role-less STANDBY@60 boots; STANDBY@50 refuses (prod path intact, floor still binds)" \
    || bad "(F-d8) STANDBY path regressed (rl60→rc=$rc_rl60, sb50→rc=$rc_sb50)"

echo ""; echo "─── (F-e) non-vacuous: the '|| true' call site is gone (v0.6.8 had it) ───"
now_true=$(grep -c 'check_crossnode_timing_safety || true' "$STANDBY")
now_enforce=$(grep -c '^\s*enforce_crossnode_timing_safety' "$STANDBY")
[[ $now_true -eq 0 && $now_enforce -ge 1 ]] \
    && ok "(F-e1) shipped startup calls enforce_crossnode_timing_safety; no '|| true' escape remains" \
    || bad "(F-e1) call-site wrong (||true=$now_true enforce=$now_enforce)"
if [[ -f "$V068" ]]; then
    v8=$(grep -c 'check_crossnode_timing_safety || true' "$V068")
    [[ $v8 -ge 1 ]] && ok "(F-e2) v0.6.8 baseline used '|| true' (warn-only) → the M9 escalation is new" \
                    || bad "(F-e2) v0.6.8 baseline unexpected ($v8)"
else
    ok "(F-e2) v0.6.8 baseline not present to compare (skipped)"
fi

# ── (U) v0.7 (pre-Block-4, №3): unstaked-uniqueness startup refusal ────────────────────────────
# Run the REAL standby startup_checks; echo "<exit_code>|<last log_error>". $1=PRIMARY_UNSTAKED_PUBKEY.
# The mocked validate_keypair_file yields STAKEDPK / UNSTAKEDPK (by path; runs in $()); the sentinel
# validate_numeric_config → exit 99 sits just PAST the pubkey-refusal region (reached = no refusal).
uniq_run() {
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
  GIVE_BACK_MODE=manual; WITNESS_FASTPATH=false
  PRIMARY_UNSTAKED_PUBKEY="$1"
  # prerequisite mocks (so startup_checks flows to the refusal region without spurious earlier exits)
  detect_ledger_path(){ LEDGER_PATH=/tmp/led; }
  get_validator_args(){ echo ""; }                     # no --identity → startup-identity check skipped
  validate_keypair_file(){ [[ "$1" == "$STAKED_KEYPAIR" ]] && echo "STAKEDPK" || echo "UNSTAKEDPK"; }
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; alert(){ :;}; alert_warn(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  validate_numeric_config(){ exit 99; }                # sentinel: reached past the refusal region cleanly
  _LAST_ERR=""; log_error(){ _LAST_ERR="$*"; }
  exit(){ printf '%s|%s' "$1" "$_LAST_ERR" > "$res"; rm -rf "$SP"; command exit "$1"; }
  startup_checks >/dev/null 2>&1 </dev/null
  ) >/dev/null 2>&1
  cat "$res"; rm -f "$res"
}

echo ""; echo "─── (U) №3: refuse to start when our own unstaked pubkey is a watched holder key ───"
r=$(uniq_run "UNSTAKEDPK")           # PRIMARY_UNSTAKED_PUBKEY == our own unstaked pubkey
[[ "${r%%|*}" == "1" && "$r" == *"shared unstaked"* ]] \
    && ok "(U-a) own key == PRIMARY_UNSTAKED_PUBKEY → startup REFUSES (exit 1): ${r#*|}" \
    || bad "(U-a) shared unstaked pubkey did not refuse (got '$r')"
r=$(uniq_run "SomeOtherHolderKey111")
[[ "${r%%|*}" == "99" && "$r" != *"shared unstaked"* ]] \
    && ok "(U-b) distinct keys → passes the refusal region (reached the sentinel)" \
    || bad "(U-b) distinct keys refused / failed (got '$r')"
r=$(uniq_run "")
[[ "${r%%|*}" == "99" ]] \
    && ok "(U-c) empty PRIMARY_UNSTAKED_PUBKEY → passes (nothing to compare)" \
    || bad "(U-c) empty watch list refused (got '$r')"
r=$(uniq_run "SomeOtherHolderKey111 UNSTAKEDPK")
[[ "${r%%|*}" == "1" && "$r" == *"shared unstaked"* ]] \
    && ok "(U-d) own key ∈ multi-key watch list → REFUSES (∈ semantics, space-separated list)" \
    || bad "(U-d) membership in a multi-key list did not refuse (got '$r')"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
