#!/bin/bash
# v0.6.7: installer guardrails (deploy-prompt UX only). Verifies the standby deploy's below-recommended
# TAKEOVER_DELAY nudge and the REC_* single-source-of-truth by EXTRACTING the testable seam (the REC_*
# definitions + warn_if_below_rec_takeover_delay) from deploy-failover-standby.sh and exercising it
# directly — then checks the calm "why" notes and the hardcoded-value coupling comments are present in
# both deploy scripts AND both env templates. (The interactive deploy flow needs root + a live
# validator, so it can't run headless; the seam is the unit-testable slice.)

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_STANDBY="$DIR/deploy-failover-standby.sh"
DEPLOY_PRIMARY="$DIR/deploy-failover.sh"
ENV_STANDBY="$DIR/failover-standby.env.example"
ENV_PRIMARY="$DIR/failover.env.example"
for f in "$DEPLOY_STANDBY" "$DEPLOY_PRIMARY" "$ENV_STANDBY" "$ENV_PRIMARY"; do
  [[ -f "$f" ]] || { echo "  ❌ missing $f"; exit 1; }
done

echo "============================================="
echo "  Installer guardrails (v0.6.7)"
echo "============================================="
echo ""

# ── Source the testable seam: the REC_* block + warn fn, from "^REC_EXPECTED..." to the fn's "^}". ──
RED=$'\033[0;31m'; NC=$'\033[0m'   # the warn fn references these (defined at the top of the deploy script)
eval "$(sed -n '/^REC_EXPECTED_PRIMARY_SELF_FENCE_SECS=/,/^}$/p' "$DEPLOY_STANDBY")"

echo "─── REC_* single source of truth ───"
# (1) REC_TAKEOVER_DELAY is DERIVED from EXPECTED + MARGIN (not a hardcoded 60), and equals 60 by default.
if [[ -n "$REC_TAKEOVER_DELAY" ]] \
   && [[ $REC_TAKEOVER_DELAY -eq $(( REC_EXPECTED_PRIMARY_SELF_FENCE_SECS + REC_SELF_FENCE_MARGIN_SECS )) ]] \
   && [[ $REC_TAKEOVER_DELAY -eq 60 ]]; then
  ok "(1) REC_TAKEOVER_DELAY=${REC_TAKEOVER_DELAY} = EXPECTED(${REC_EXPECTED_PRIMARY_SELF_FENCE_SECS}) + MARGIN(${REC_SELF_FENCE_MARGIN_SECS})"
else
  bad "(1) REC_TAKEOVER_DELAY not derived correctly (got '${REC_TAKEOVER_DELAY}')"
fi

# (2) the warn function is even defined (the extraction worked)
type warn_if_below_rec_takeover_delay >/dev/null 2>&1 \
  && ok "(2) warn_if_below_rec_takeover_delay extracted + sourced" \
  || { bad "(2) warn fn not found — seam extraction failed"; echo "  RESULTS: $PASS passed, $FAIL failed"; exit 1; }

echo ""
echo "─── below-recommended RED nudge (TAKEOVER_DELAY only) ───"
# (3) below REC → prints a RED line that names the recommended floor + double-sign, and returns 1.
out=$(warn_if_below_rec_takeover_delay 40 "$REC_TAKEOVER_DELAY"); rc=$?
if [[ $rc -eq 1 && "$out" == *"below the recommended ${REC_TAKEOVER_DELAY}s"* && "$out" == *"double-sign"* && "$out" == *$'\033[0;31m'* ]]; then
  ok "(3) value 40 < REC → RED nudge printed (rc=1)"
else
  bad "(3) value 40 did not produce the RED nudge (rc=$rc, out='${out}')"
fi

# (4) at REC → silent, returns 0 (a default-accepting operator sees nothing extra).
out=$(warn_if_below_rec_takeover_delay "$REC_TAKEOVER_DELAY" "$REC_TAKEOVER_DELAY"); rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && ok "(4) value == REC (${REC_TAKEOVER_DELAY}) → silent (rc=0)" \
  || bad "(4) value == REC was not silent (rc=$rc, out='${out}')"

# (5) above REC → silent, returns 0.
out=$(warn_if_below_rec_takeover_delay 120 "$REC_TAKEOVER_DELAY"); rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && ok "(5) value 120 > REC → silent (rc=0)" \
  || bad "(5) value 120 was not silent (rc=$rc, out='${out}')"

# (6) STRICT boundary (non-vacuous): 59 warns, 60 is silent → the threshold is exactly "< REC".
o59=$(warn_if_below_rec_takeover_delay 59 60); r59=$?
o60=$(warn_if_below_rec_takeover_delay 60 60); r60=$?
[[ $r59 -eq 1 && -n "$o59" && $r60 -eq 0 && -z "$o60" ]] \
  && ok "(6) boundary: 59 warns, 60 silent (strict < REC) — non-vacuous" \
  || bad "(6) boundary wrong (59: rc=$r59 out='${o59}' | 60: rc=$r60 out='${o60}')"

echo ""
echo "─── calm why-notes present (standby deploy prompts) ───"
# (7) TAKEOVER_DELAY why-note
grep -qF "lets the PRIMARY step down before a spare takes over" "$DEPLOY_STANDBY" \
  && ok "(7) TAKEOVER_DELAY why-note present" \
  || bad "(7) TAKEOVER_DELAY why-note missing"

# (8) MAX_DELINQUENT_SLOTS why-note — and it carries NO danger framing (speed, not a double-sign value).
mln=$(grep -F "Recommended 15 — detects a stopped PRIMARY quickly" "$DEPLOY_STANDBY")
if [[ -n "$mln" && "$mln" != *'${RED}'* && "$mln" != *"double-sign"* ]]; then
  ok "(8) MAX_DELINQUENT_SLOTS why-note present, no danger framing"
else
  bad "(8) MAX_DELINQUENT_SLOTS note missing or wrongly framed as danger ('${mln}')"
fi

echo ""
echo "─── hardcoded self-fence coupling comments (both scripts + both env templates) ───"
COUP="Do NOT raise without raising every spare's EXPECTED_PRIMARY_SELF_FENCE_SECS and TAKEOVER_DELAY"
# v0.6.9 (B2): the floor comment wording became role-aware ("... >= floor ...").
FLOOR="Cross-node safety floor: a spare waits TAKEOVER_DELAY >= floor"
grep -qF "$COUP" "$DEPLOY_PRIMARY" && ok "(9) primary deploy: self-fence coupling comment" || bad "(9) primary deploy missing coupling comment"
grep -qF "$COUP" "$ENV_PRIMARY"    && ok "(10) primary env: self-fence coupling comment"    || bad "(10) primary env missing coupling comment"
grep -qF "$FLOOR" "$DEPLOY_STANDBY" && ok "(11) standby deploy: cross-node floor comment"     || bad "(11) standby deploy missing floor comment"
grep -qF "$FLOOR" "$ENV_STANDBY"    && ok "(12) standby env: cross-node floor comment"        || bad "(12) standby env missing floor comment"
# v0.6.9 (B2): FAILOVER_ROLE must be WRITTEN by the wizard (from CFG_ROLE) and DOCUMENTED in the env,
# so the daemon's role-aware timing floor is driven by a real config field (not derived-only).
grep -qF 'FAILOVER_ROLE=${CFG_ROLE}' "$DEPLOY_STANDBY" && ok "(11b) standby deploy: writes FAILOVER_ROLE" || bad "(11b) standby deploy does not write FAILOVER_ROLE"
grep -qE '^FAILOVER_ROLE=' "$ENV_STANDBY"              && ok "(12b) standby env: FAILOVER_ROLE present"   || bad "(12b) standby env missing FAILOVER_ROLE"

# ═══════════════════════ v0.6.9 (TASK-v0.6.9): M6 / M7 / M8 installer guardrails ═══════════════════════
STANDBY_SCRIPT="$DIR/solana-standby-failover.sh"

echo ""
echo "─── (M6) GIVE_BACK_MODE=auto trap removed ───"
# (13) the wizard no longer OFFERS "auto" (the old ask_choice with an "auto" option is gone).
if ! grep -qE 'ask_choice "Give-back mode".*"auto"' "$DEPLOY_STANDBY" && grep -q 'CFG_GIVE_BACK="manual"' "$DEPLOY_STANDBY"; then
  ok "(13) wizard offers only manual (informational line; CFG_GIVE_BACK pinned to manual)"
else
  bad "(13) wizard still offers GIVE_BACK_MODE=auto"
fi
# (14) BEHAVIORAL via the daemon seam: a hand-edited GIVE_BACK_MODE=auto is coerced to manual + warned.
m6_out=$(
  set +e
  SEAM=$(mktemp)
  awk '/# v0\.6\.9 \(M6\): GIVE_BACK_MODE=auto/ {p=1} p {print} p && /^    fi$/ {exit}' "$STANDBY_SCRIPT" > "$SEAM"
  W=0; log_warn(){ W=$((W+1)); }; alert_warn(){ W=$((W+1)); }
  GIVE_BACK_MODE="auto"
  # shellcheck disable=SC1090
  source "$SEAM"; rm -f "$SEAM"
  printf 'mode=%s|warns=%s' "$GIVE_BACK_MODE" "$W"
)
[[ "$m6_out" == "mode=manual|warns=2" ]] \
  && ok "(14) daemon seam: GIVE_BACK_MODE=auto → coerced to manual + log_warn + alert_warn ($m6_out)" \
  || bad "(14) auto not coerced/warned ($m6_out)"

echo ""
echo "─── (M7) start-the-service-you-stopped prompt ───"
# (15) BEHAVIORAL via the offer_start_service seam: non-interactive stdin → print-only, NO systemctl.
m7_out=$(
  set +e
  SEAM=$(mktemp)
  sed -n '/^offer_start_service() {/,/^}$/p' "$DEPLOY_STANDBY" > "$SEAM"
  BOLD=""; NC=""; YELLOW=""
  ok(){ :; }; warn(){ :; }
  SYS=0; systemctl(){ SYS=$((SYS+1)); return 0; }
  # shellcheck disable=SC1090
  source "$SEAM"; rm -f "$SEAM"
  out=$(offer_start_service "solana-failover-standby" "1" < /dev/null)
  printf 'sys=%s|says=%s' "$SYS" "$out"
)
if [[ "$m7_out" == "sys=0|"* && "$m7_out" == *"systemctl start solana-failover-standby"* ]]; then
  ok "(15) non-interactive stdin → print-only (no systemctl invoked), names the start command"
else
  bad "(15) non-tty behavior wrong ($m7_out)"
fi
# (16) STRUCTURAL (the interactive branch needs a real tty — asserted by shape, per TASK-v0.6.9 §Tests 9):
#      default-Y prompt, status --no-pager after start, enable offer, and the was-active capture at the stop step.
m7s=0
grep -q 'Start ${unit} now? (Y/n)' "$DEPLOY_STANDBY" && m7s=$((m7s+1))
# v0.6.9 (Phase A): the post-start display is now the cleaner is-active verification (ok "…running" /
# warn on failure) instead of dumping `systemctl status --no-pager -l | head` — assert the verification.
grep -q 'is-active --quiet "$unit"' "$DEPLOY_STANDBY" && m7s=$((m7s+1))
grep -q 'Enable ${unit} at boot? (Y/n)' "$DEPLOY_STANDBY" && m7s=$((m7s+1))
grep -q 'FAILOVER_WAS_ACTIVE=1' "$DEPLOY_STANDBY" && m7s=$((m7s+1))
grep -q 'offer_start_service "solana-failover-standby" "$FAILOVER_WAS_ACTIVE"' "$DEPLOY_STANDBY" && m7s=$((m7s+1))
[[ $m7s -eq 5 ]] && ok "(16) standby deploy: default-Y start prompt + status head + enable offer + was-active capture + end-of-deploy call (5/5)" \
                 || bad "(16) standby deploy M7 structure incomplete ($m7s/5)"
m7p=0
grep -q 'Start ${unit} now? (Y/n)' "$DEPLOY_PRIMARY" && m7p=$((m7p+1))
grep -q 'offer_start_service "solana-failover" "$FAILOVER_WAS_ACTIVE"' "$DEPLOY_PRIMARY" && m7p=$((m7p+1))
grep -q 'FAILOVER_WAS_ACTIVE=1' "$DEPLOY_PRIMARY" && m7p=$((m7p+1))
[[ $m7p -eq 3 ]] && ok "(17) primary deploy: M7 prompt + call + capture present (3/3)" \
                 || bad "(17) primary deploy M7 structure incomplete ($m7p/3)"

echo ""
echo "─── (M8) equal-tier re-prompt loop ───"
# (18) BEHAVIORAL via the seam: equal tiers → the shipped while-loop re-prompts (ask mocked at the
#      I/O boundary) until a distinct Tier 3 arrives; the warn names the single-vantage hazard.
m8_out=$(
  set +e
  SEAM=$(mktemp)
  sed -n '/# v0\.6\.9 (M8): Tier 2 and Tier 3 must be DISTINCT/,/^done$/p' "$DEPLOY_STANDBY" > "$SEAM"
  W=0; warn(){ W=$((W+1)); }
  _ANSWERS=("https://same.example.com" "https://other.example.com")
  _IDX=0
  ask(){ REPLY="${_ANSWERS[$_IDX]}"; _IDX=$((_IDX+1)); }
  CFG_TIER2_RPC="https://same.example.com"
  CFG_TIER3_RPC="https://same.example.com/"
  # shellcheck disable=SC1090
  source "$SEAM"; rm -f "$SEAM"
  printf 't3=%s|warns=%s' "$CFG_TIER3_RPC" "$W"
)
[[ "$m8_out" == "t3=https://other.example.com|warns=2" ]] \
  && ok "(18) equal (slash-normalized) tiers re-prompted twice until distinct ($m8_out)" \
  || bad "(18) re-prompt loop wrong ($m8_out)"
# (19) same loop present in the primary wizard.
grep -q '_norm_rpc_url "$CFG_TIER2_RPC"' "$DEPLOY_PRIMARY" && grep -qE 'while .*CFG_TIER2_RPC.*CFG_TIER3_RPC' "$DEPLOY_PRIMARY" \
  && ok "(19) primary wizard carries the same normalize-and-re-prompt loop" \
  || bad "(19) primary wizard missing the M8 loop"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
