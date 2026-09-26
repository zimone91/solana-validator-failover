#!/bin/bash
# v0.6.7: installer guardrails (deploy-prompt UX only). Verifies the standby deploy's below-recommended
# TAKEOVER_DELAY nudge and the REC_* single-source-of-truth by EXTRACTING the testable seam (the REC_*
# definitions + warn_if_below_rec_takeover_delay) from deploy-failover-standby.sh and exercising it
# directly — then checks the calm "why" notes and the hardcoded-value coupling comments are present in
# both deploy scripts AND both env templates. (The interactive deploy flow needs root + a live
# validator, so it can't run headless; the seam is the unit-testable slice.)

# harness: tests/lib/harness.sh — ok/bad+banners, paths, extract_region (the daemon M6 seam — sed
# byte-faithful to the old awk-with-exit, verified — and the 7 installer-file anchors against
# deploy-*.sh: none can silently extract empty). The grep-appended prompt lines stay greps.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
DEPLOY_STANDBY="$HARNESS_DIR/deploy-failover-standby.sh"
DEPLOY_PRIMARY="$HARNESS_DIR/deploy-failover.sh"
ENV_STANDBY="$HARNESS_DIR/failover-standby.env.example"
ENV_PRIMARY="$HARNESS_DIR/failover.env.example"
for f in "$DEPLOY_STANDBY" "$DEPLOY_PRIMARY" "$ENV_STANDBY" "$ENV_PRIMARY"; do
  [[ -f "$f" ]] || { echo "  ❌ missing $f"; exit 1; }
done

title_banner "Installer guardrails (v0.6.7)"
echo ""

# ── Source the testable seam: the REC_* block + warn fn, from "^REC_EXPECTED..." to the fn's "^}". ──
RED=$'\033[0;31m'; NC=$'\033[0m'   # the warn fn references these (defined at the top of the deploy script)
_rec_seam=$(extract_region "$DEPLOY_STANDBY" '^REC_EXPECTED_PRIMARY_SELF_FENCE_SECS=' '^}$') || bad "REC_* seam extraction came back EMPTY"
eval "$_rec_seam"

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
grep -qF "gives the PRIMARY its worst-case self-fence time plus a cross-node margin" "$DEPLOY_STANDBY" \
  && ok "(7) TAKEOVER_DELAY why-note present (timing-based wording)" \
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
STANDBY_SCRIPT="$STANDBY"

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
  extract_region "$STANDBY_SCRIPT" '# v0\.6\.9 (M6): GIVE_BACK_MODE=auto' '^    fi$' > "$SEAM"
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
  extract_region "$DEPLOY_STANDBY" '^offer_start_service() {' '^}$' > "$SEAM"
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
  extract_region "$DEPLOY_STANDBY" '# v0\.6\.9 (M8): Tier 2 and Tier 3 must be DISTINCT' '^done$' > "$SEAM"
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
echo "─── re-run keeps the configured role (sticky FAILOVER_ROLE default) ───"
# BEHAVIORAL via the ask_choice seam + the SHIPPED role-prompt line. On a re-run the wizard sources
# the existing env first, so FAILOVER_ROLE holds this node's real role; pressing Enter must keep it.
# A hard-coded "STANDBY" default converted a BACKUP into a second STANDBY on the documented upgrade
# path — both spares then take in the same second (double-sign). Control: revert the role prompt's
# default to a bare "STANDBY" → (20) fails.
s2_drive() {  # $1 = FAILOVER_ROLE as loaded from an existing env ('' = fresh install)
  set +e
  SEAM=$(mktemp)
  extract_region "$DEPLOY_STANDBY" '^ask_choice() {' '^}$' > "$SEAM"
  grep '^ask_choice "Server role"' "$DEPLOY_STANDBY" >> "$SEAM"
  BOLD=""; NC=""
  warn(){ :; }
  FAILOVER_ROLE="$1"
  TAKEOVER_DELAY="$2"
  # shellcheck disable=SC1090
  source "$SEAM" <<< "" >/dev/null    # simulated operator: press Enter (accept the default)
  rm -f "$SEAM"
  printf 'role=%s' "$REPLY"
}
s2_backup=$(s2_drive "BACKUP" "")
[[ "$s2_backup" == "role=BACKUP" ]] \
  && ok "(20) re-run on a BACKUP: Enter keeps BACKUP ($s2_backup)" \
  || bad "(20) re-run on a BACKUP: Enter changed the role ($s2_backup)"
s2_fresh=$(s2_drive "" "")
[[ "$s2_fresh" == "role=STANDBY" ]] \
  && ok "(21) fresh install (no existing env): Enter defaults to STANDBY ($s2_fresh)" \
  || bad "(21) fresh install default wrong ($s2_fresh)"
# ≤v0.6.8 envs never wrote FAILOVER_ROLE — the role hint must fall back to the loaded
# TAKEOVER_DELAY (120+ ⇒ BACKUP). Control: revert the hint to a bare STANDBY → (21b) fails.
s2_hint=$(s2_drive "" "120")
[[ "$s2_hint" == "role=BACKUP" ]] \
  && ok "(21b) ≤0.6.8 BACKUP env (no FAILOVER_ROLE, delay 120): Enter keeps BACKUP ($s2_hint)" \
  || bad "(21b) ≤0.6.8 BACKUP env: hint wrong ($s2_hint)"
s2_hint60=$(s2_drive "" "60")
[[ "$s2_hint60" == "role=STANDBY" ]] \
  && ok "(21c) ≤0.6.8 STANDBY env (delay 60): Enter keeps STANDBY ($s2_hint60)" \
  || bad "(21c) ≤0.6.8 STANDBY env: hint wrong ($s2_hint60)"

# Same hazard class, one prompt later: a BACKUP re-run must keep its configured
# STANDBY_TAKEOVER_DELAY (it feeds the take-visibility floor). Control: revert the prompt's
# default to a bare "60" -> (22) fails.
s2b_drive() {  # $1 = STANDBY_TAKEOVER_DELAY as loaded from an existing env
  set +e
  SEAM=$(mktemp)
  extract_region "$DEPLOY_STANDBY" '^ask() {' '^}$' > "$SEAM"
  extract_region "$DEPLOY_STANDBY" '^ask_numeric() {' '^}$' >> "$SEAM"
  grep 'ask_numeric "STANDBY.s TAKEOVER_DELAY' "$DEPLOY_STANDBY" >> "$SEAM"
  BOLD=""; NC=""
  warn(){ :; }
  STANDBY_TAKEOVER_DELAY="$1"
  # shellcheck disable=SC1090
  source "$SEAM" <<< "" >/dev/null
  rm -f "$SEAM"
  printf 'std=%s' "$REPLY"
}
s2b_keep=$(s2b_drive "90")
[[ "$s2b_keep" == "std=90" ]] \
  && ok "(22) BACKUP re-run: Enter keeps STANDBY_TAKEOVER_DELAY=90 ($s2b_keep)" \
  || bad "(22) BACKUP re-run: Enter changed STANDBY_TAKEOVER_DELAY ($s2b_keep)"
s2b_fresh=$(s2b_drive "")
[[ "$s2b_fresh" == "std=60" ]] \
  && ok "(23) fresh BACKUP (no existing env): Enter defaults to 60 ($s2b_fresh)" \
  || bad "(23) fresh BACKUP default wrong ($s2b_fresh)"

echo ""
echo "─── re-run keeps a custom (non-ntfy) webhook (H-B sticky ntfy default) ───"
# The ntfy-enable prompt must default to "false" when a custom Slack/Discord webhook is already
# configured, so one Enter can't replace it with a fresh unsubscribed ntfy channel (alerts to the
# void). Control: revert the default to a bare "true" -> (24) fails.
_hb_default() {  # mirrors the shipped default computation for a given WEBHOOK_URL ($1)
  local d="true"
  WEBHOOK_URL="$1"
  [[ -n "${WEBHOOK_URL:-}" && "$WEBHOOK_URL" != *"ntfy.sh"* ]] && d="false"
  printf '%s' "$d"
}
for SC in "$DEPLOY_STANDBY" "$DEPLOY_PRIMARY"; do
  L=$(basename "$SC")
  # the shipped line must compute the default from WEBHOOK_URL, not hard-code "true"
  if grep -qF 'ask_choice "Enable ntfy.sh push (optional)" "$_ntfy_default"' "$SC"      && grep -qF '[[ -n "${WEBHOOK_URL:-}" && "$WEBHOOK_URL" != *"ntfy.sh"* ]] && _ntfy_default="false"' "$SC"; then
    d_custom=$(_hb_default "https://hooks.slack.com/x" "$SC")
    d_fresh=$(_hb_default "" "$SC")
    d_ntfy=$(_hb_default "https://ntfy.sh/chan" "$SC")
    [[ "$d_custom" == "false" && "$d_fresh" == "true" && "$d_ntfy" == "true" ]]       && ok "(24 $L) ntfy default: custom webhook->false, fresh->true, ntfy->true"       || bad "(24 $L) ntfy default logic wrong (custom=$d_custom fresh=$d_fresh ntfy=$d_ntfy)"
  else
    bad "(24 $L) ntfy-enable prompt is not sticky against a custom webhook (hard-coded default)"
  fi
done

echo ""
echo "─── re-run keeps lock-step-tuned EXPECTED/MARGIN (H-A sticky) ───"
# A deployment that raised the PRIMARY self-fence and every spare's EXPECTED in lock-step must not have
# EXPECTED/MARGIN silently reset to REC_*=30 on a wizard re-run. Control: revert to =$REC_* -> (25) fails.
grep -qF 'CFG_EXPECTED_PRIMARY_SELF_FENCE_SECS=${EXPECTED_PRIMARY_SELF_FENCE_SECS:-$REC_EXPECTED_PRIMARY_SELF_FENCE_SECS}' "$DEPLOY_STANDBY"   && grep -qF 'CFG_SELF_FENCE_MARGIN_SECS=${SELF_FENCE_MARGIN_SECS:-$REC_SELF_FENCE_MARGIN_SECS}' "$DEPLOY_STANDBY"   && ok "(25) standby: EXPECTED/MARGIN sticky from loaded env (lock-step tuning survives re-run)"   || bad "(25) standby: EXPECTED/MARGIN hard-reset to REC_* on re-run (sticky bug)"

# Sticky must not be silent about BELOW-safe values: drive the shipped sticky+warn seam with a
# hand-lowered env and assert the RED warning fires while the values are preserved; with values
# at/above REC assert silence. Control: revert the warning block → (26a) fails.
ha_drive() {  # $1=EXPECTED $2=MARGIN from a loaded env
  set +e
  SEAM=$(mktemp)
  extract_region "$DEPLOY_STANDBY" '^CFG_EXPECTED_PRIMARY_SELF_FENCE_SECS=' '^fi$' > "$SEAM"
  RED=""; NC=""
  REC_EXPECTED_PRIMARY_SELF_FENCE_SECS=30; REC_SELF_FENCE_MARGIN_SECS=30
  EXPECTED_PRIMARY_SELF_FENCE_SECS="$1"; SELF_FENCE_MARGIN_SECS="$2"
  CAP=$(mktemp)
  # shellcheck disable=SC1090
  source "$SEAM" > "$CAP" 2>&1      # in THIS shell so CFG_* survive; warning text captured to CAP
  out=$(cat "$CAP")
  rm -f "$SEAM" "$CAP"
  printf 'exp=%s|marg=%s|warned=%s' "$CFG_EXPECTED_PRIMARY_SELF_FENCE_SECS" "$CFG_SELF_FENCE_MARGIN_SECS" "$([[ "$out" == *"BELOW the shipped safe values"* ]] && echo yes || echo no)"
}
ha_low=$(ha_drive "20" "10")
[[ "$ha_low" == "exp=20|marg=10|warned=yes" ]] \
  && ok "(26a) lowered EXPECTED/MARGIN kept but warned in RED ($ha_low)" \
  || bad "(26a) lowered EXPECTED/MARGIN not warned or not preserved ($ha_low)"
ha_ok=$(ha_drive "45" "30")
[[ "$ha_ok" == "exp=45|marg=30|warned=no" ]] \
  && ok "(26b) raised EXPECTED kept, no warning ($ha_ok)" \
  || bad "(26b) raised values mishandled ($ha_ok)"
ha_junk=$(ha_drive "abc" "10")
[[ "$ha_junk" == "exp=30|marg=10|warned=yes" ]] \
  && ok "(26c) non-numeric EXPECTED reset to safe 30; low MARGIN still warned ($ha_junk)" \
  || bad "(26c) non-numeric handling wrong ($ha_junk)"

# ── (27) the generated env's heredocs must never EXECUTE anything but their own value expansions ──
# ENVEOF is UNQUOTED by design (it expands ${CFG_*} and $(_envq …)), so ANY other expansion in one of its
# lines — a bare backtick, a $( … ), a $(( … )) or $[ … ], a bare $NAME/${NAME} — is evaluated at deploy
# time, as root: Block 6.2's G2-vantage comment ran `failover arm` on every standby deploy until Block 6.3
# escaped it (the house form is the escaped \` / \$). Two layers (6.3 fix round, T4 — panel INT-3; hardened
# in fix round 2, R9 — panel P2-INERT-1/2; and in fix round 3, S4 — panel CC2-1 / P3-R9-1):
#   CENSUS  every body of a heredoc whose opener line ENDS in an unquoted `<< TAG`, in BOTH deploy scripts
#           (today exactly the two ENVEOF bodies — the SERVICEEOF bodies are quoted). First, a line ending
#           in an ODD run of backslashes is joined with the next one, as bash's unquoted heredoc removes the
#           backslash-newline — the delimiter line included (a joined line is never the delimiter: the
#           body goes on). Then the escaped PAIRS are deleted left to right — every \\ pair FIRST (in the
#           heredoc it is one literal backslash, and the $( after it EXPANDS), then the escaped \$ and \` —
#           and the ALLOWLIST (the header's $(date -u +"%F %T UTC"); $(_envq "${CFG_X}"); ${CFG_X}). What
#           remains must carry ZERO $( / $(( / $[ / bare $[A-Za-z_{0-9@*#?!$-] / backticks: parameter,
#           command and arithmetic expansion — the expansions bash performs in an unquoted heredoc.
#   RENDER  ONLY a script whose census is 0 is rendered at all (a flagged line is never evaluated), and
#           then RESTRICTED: `env -i PATH=<canary> TMPDIR=<temp> bash -r`, run with its CWD in the temp dir
#           and `enable -n history kill ulimit suspend` as its first line — the write/kill-capable builtins
#           restricted bash still allows (measured on 3.2.57 and 5.2.37: `history -w` writes any path on 3.2
#           and a bare name into the CWD on 5.2, `kill` signals any process, `ulimit` sets the render's own
#           limits, and on 5.2 `suspend -f` stops the render's whole process group — the test run with it;
#           a restricted shell refuses to re-enable one, `builtin` no longer finds it, and the bare name
#           falls to the canary PATH or is 'not found'). The CANARY PATH: every command it knows RECORDS its argv into a
#           log whose path is baked into the canary when it is created (never read from the environment);
#           any other command is 'not found' on stderr. No '/' in a command name, no output redirection
#           (the OUTER shell captures stdout into the temp file). The only recorded command may be the
#           header's `date -u +%F %T UTC`, stderr must be empty, and the escaped comment text must survive
#           literally: a forbidden form FAILS LOUDLY on stderr or is RECORDED instead of executing.
#           A builtin with no output side effect ($(true), $[1+1]) is invisible to the render — the census
#           holds it.
# Scope of the PASS: these two mechanisms over the ENVEOF heredocs of the two deploy scripts. The render
# is the second layer for a spelling the census would miss, and it is proven only against the forms
# (27-ctl) / (27-ctl-r) execute — an absolute-path command, an output redirection, `history -w`, `kill`, a
# per-command `CANARY_LOG=` — not as a general sandbox. Not a proof about any other file, nor about a
# heredoc opened any other way (`<<-TAG`, or a tag that does not end its line).
hd_census() {   # $1 = deploy script → prints the count of NON-allowlisted expansions; hits on stderr
  awk '!inh && /<<[[:space:]]*[A-Za-z_]+[[:space:]]*$/ { tag=$NF; sub(/^<</, "", tag); inh=1; cont=""; next }
       inh && cont == "" && $0 == tag { inh=0; next }
       inh {
         line=cont $0; cont=""
         t=line; while (t ~ /\\$/) t=substr(t, 1, length(t) - 1)
         if ((length(line) - length(t)) % 2 == 1) { cont=substr(line, 1, length(line) - 1); next }   # backslash-newline: joins the NEXT line (S4)
         raw=line
         gsub(/\\\\/, "", line)                          # escaped PAIRS left to right: every \\ first (R9)
         gsub(/\\[$]/, "", line); gsub(/\\`/, "", line)
         gsub(/[$][(]date -u [+]"%F %T UTC"[)]/, "", line)
         gsub(/[$][(]_envq "[$][{]CFG_[A-Z0-9_]+[}]"[)]/, "", line)
         gsub(/[$][{]CFG_[A-Z0-9_]+[}]/, "", line)
         if (line ~ /[$][(A-Za-z_{0-9@*#?!$-]/ || line ~ /[$]\[/ || line ~ /`/) { n++; print "HIT l" NR ": " raw > "/dev/stderr" }
       }
       END { if (cont != "") { n++; print "HIT l" NR ": a backslash-newline at the end of the file" > "/dev/stderr" }; print n+0 }' "$1"
}
hd_render() {   # $1 = deploy script, $2 = its env path in the opener → "err=<stderr>|rec=<recorded cmds>|out=<rendered file>"
  local f="$1" envp="$2" d s e
  d=$(mktemp -d)
  mkdir -p "$d/canary"
  # S4 (fix round 3): the rec-log path is BAKED into the canary here — never read from the environment
  # (a per-command `CANARY_LOG=<path> date` re-pointed it outside the temp dir: measured on 3.2 and 5.2)
  printf '#!/bin/sh\nn=${0##*/}\nprintf "%%s %%s\\n" "$n" "$*" >> '"'%s'"'\n[ "$n" = date ] && printf "2026-01-01 00:00:00 UTC\\n"\nexit 0\n' "$d/rec.log" > "$d/canary/.rec"
  chmod +x "$d/canary/.rec"
  for c in date failover solana agave-validator fdctl systemctl journalctl curl jq cat sed awk grep hostname id whoami uname ls rm env sh bash true false echo printf sleep kill touch mkdir chmod chown tee head tail tr cut sort uniq wc xargs find ssh scp getent nproc timeout install cp mv ln readlink dirname basename stat; do
    ln -s .rec "$d/canary/$c"
  done
  s=$(grep -n "^cat > ${envp} << ENVEOF\$" "$f" | cut -d: -f1)
  e=""; [[ -n "$s" ]] && e=$(awk -v s="$s" 'NR > s && /^ENVEOF$/ { print NR; exit }' "$f")
  if [[ -z "$s" || -z "$e" ]]; then echo "err=(no ENVEOF heredoc for ${envp})|rec=|out="; rm -rf "$d"; return; fi
  {
    echo 'enable -n history kill ulimit suspend'   # S4: the write/kill-capable builtins rbash still allows; it refuses to re-enable one
    echo '_envq(){ printf "%q" "$1"; }'
    echo "while IFS= read -r _l || [[ -n \"\$_l\" ]]; do printf '%s\\n' \"\$_l\"; done << ENVEOF"
    sed -n "$(( s + 1 )),${e}p" "$f"
  } > "$d/render.sh"
  local err rec
  # RESTRICTED (6.3 fix round 2, R9): a clean env, the canary PATH only, bash -r — no '/' in a command
  # name, no output redirection; THIS shell captures the render's stdout into the temp file. S4: the
  # render's CWD is the temp dir too (a bare-name write lands inside it)
  ( cd "$d" && env -i PATH="$d/canary" TMPDIR="$d" "${BASH:-/bin/bash}" -r "$d/render.sh" ) > "$d/env" 2> "$d/err"
  err=$(tr '\n' ' ' < "$d/err")
  rec=$(tr '\n' ';' < "$d/rec.log" 2>/dev/null)
  cp "$d/env" "$WORKDIR_27/$(basename "$f").env" 2>/dev/null
  echo "err=${err}|rec=${rec}|out=$WORKDIR_27/$(basename "$f").env"
  rm -rf "$d"
}
hd_guard() {   # $1 = standby deploy, $2 = primary deploy → "ok" or the MEASURED reason it is not
  local cs cp rs rp why=""
  cs=$(hd_census "$1" 2>/dev/null); cp=$(hd_census "$2" 2>/dev/null)
  [[ "$cs" == "0" ]] || why="$why census(standby)=$cs"
  [[ "$cp" == "0" ]] || why="$why census(primary)=$cp"
  # R9: a script is rendered ONLY when its census is 0 — a flagged heredoc line is never evaluated
  if [[ "$cs" == "0" ]]; then
    rs=$(hd_render "$1" /opt/solana-failover/failover-standby.env)
    [[ -z "$(field "$rs" err)" ]] || why="$why render-stderr(standby)='$(field "$rs" err | cut -c1-120)'"
    [[ "$(field "$rs" rec)" == "date -u +%F %T UTC;" ]] || why="$why executed(standby)='$(field "$rs" rec)'"
    grep -qF -- '`failover arm` probes both' "$(field "$rs" out)" 2>/dev/null || why="$why standby-comment-text-lost"
  else
    why="$why render(standby)=NOT-RUN"
  fi
  if [[ "$cp" == "0" ]]; then
    rp=$(hd_render "$2" /opt/solana-failover/failover.env)
    [[ -z "$(field "$rp" err)" ]] || why="$why render-stderr(primary)='$(field "$rp" err | cut -c1-120)'"
    [[ "$(field "$rp" rec)" == "date -u +%F %T UTC;" ]] || why="$why executed(primary)='$(field "$rp" rec)'"
    grep -qF -- 'wraps in `timeout 8`' "$(field "$rp" out)" 2>/dev/null || why="$why primary-comment-text-lost"
    grep -qF -- 'SOLANA_PATH="$HOME/.local/share/solana/install/active_release/bin"' "$(field "$rp" out)" 2>/dev/null || why="$why primary-SOLANA_PATH-expanded"
  else
    why="$why render(primary)=NOT-RUN"
  fi
  echo "${why:-ok}"
}
WORKDIR_27=$(mktemp -d)
g=$(hd_guard "$DEPLOY_STANDBY" "$DEPLOY_PRIMARY")
if [[ "$g" == "ok" ]]; then
  ok "(27) the ENVEOF heredocs of BOTH deploy scripts: ZERO non-allowlisted \$( / \$(( / \$[ / \$NAME / \${ / backtick in any line, after joining backslash-newline continuations and removing escaped pairs left to right (census) — so no heredoc line expands anything at deploy time beyond the CFG values and the allowlisted header date / _envq; and — rendered only because the census is 0 — both render RESTRICTED (env -i, a canary PATH with a baked log, bash -r, CWD and TMPDIR in the temp dir, history / kill / ulimit / suspend disabled) with ZERO stderr, exactly ONE executed command each (the header's date), the escaped comment text and \\\$HOME intact"
else
  bad "(27) heredoc hazard:$g"
fi
# (27-ctl) the mutants the guard must each turn RED (panel INT-3: the old guard stayed green on the
# primary-heredoc and comment-line forms)
m27_ok=1; m27_rows=""
m27() {   # $1=label $2=which(s|p) $3=sed expr
  local ms="$DEPLOY_STANDBY" mp="$DEPLOY_PRIMARY" out
  if [[ "$2" == "s" ]]; then ms="$WORKDIR_27/mut-s.sh"; mutate "$DEPLOY_STANDBY" "$3" "$ms" || { m27_ok=0; return; }
  else mp="$WORKDIR_27/mut-p.sh"; mutate "$DEPLOY_PRIMARY" "$3" "$mp" || { m27_ok=0; return; }; fi
  out=$(hd_guard "$ms" "$mp")
  if [[ "$out" != "ok" ]]; then m27_rows="$m27_rows $1"; else m27_ok=0; bad "(27-ctl) mutant '$1' stayed GREEN"; fi
}
m27f() {   # $1=label $2=which(s|p) ; inserts the lines in $WORKDIR_27/payf after that heredoc's anchor comment (awk, no sed escaping)
  local label="$1" which="$2" src anchor tmp out
  if [[ "$which" == "s" ]]; then src="$DEPLOY_STANDBY"; anchor='# address — \`failover arm\` probes both'; else src="$DEPLOY_PRIMARY"; anchor='# wraps in \`timeout 8\`'; fi
  tmp="$WORKDIR_27/mutf-$which.sh"
  # anchor + payf via ENVIRON: awk's -v mangles a backslash before a backtick, but ENVIRON values are literal
  A="$anchor" PAYF="$WORKDIR_27/payf" awk '{ print } index($0, ENVIRON["A"]) == 1 && !done { done=1; while ((getline l < ENVIRON["PAYF"]) > 0) print l }' "$src" > "$tmp"
  if cmp -s "$src" "$tmp"; then m27_ok=0; bad "(27-ctl) m27f '$label': anchor not found (insert no-op)"; return; fi
  if [[ "$which" == "s" ]]; then out=$(hd_guard "$tmp" "$DEPLOY_PRIMARY"); else out=$(hd_guard "$DEPLOY_STANDBY" "$tmp"); fi
  if [[ "$out" != "ok" ]]; then m27_rows="$m27_rows $label"; else m27_ok=0; bad "(27-ctl) mutant '$label' stayed GREEN"; fi
}
m27 "p:backtick"        p 's/^# wraps in \\`timeout 8\\`/# wraps in `timeout 8`/'
m27 "p:\$(true)"        p 's/^# wraps in \\`timeout 8\\`/# wraps in $(true)/'
m27 "p:\$(failover arm)" p 's/^# wraps in \\`timeout 8\\`/# wraps in $(failover arm)/'
m27 "s:backtick"        s 's/^# address — \\`failover arm\\` probes both/# address — `failover arm` probes both/'
m27 "s:\$(true)"        s 's/^# address — \\`failover arm\\` probes both/# address — $(true) probes both/'
m27 "s:\$(failover arm)" s 's/^# address — \\`failover arm\\` probes both/# address — $(failover arm) probes both/'
m27 "p:comment \$TIER2_RPC"  p 's/^# wraps in \\`timeout 8\\`/# wraps in $TIER2_RPC \\`timeout 8\\`/'
m27 "s:comment \${LEDGER}"   s 's/^# address — \\`failover arm\\` probes both/# address ${LEDGER} — \\`failover arm\\` probes both/'
m27 "p:comment \$((1+1))"    p 's/^# wraps in \\`timeout 8\\`/# wraps in $((1+1)) \\`timeout 8\\`/'
m27 "s:comment \$HOME"       s 's/^# address — \\`failover arm\\` probes both/# address $HOME — \\`failover arm\\` probes both/'
m27 "p:value \$HOME unescaped" p 's|^SOLANA_PATH="\\$HOME/|SOLANA_PATH="$HOME/|'
# 6.3 fix round 2, R9 (panel P2-INERT-1): an escaped BACKSLASH before an expansion — '\\$(…)' is one
# literal backslash and a LIVE $(…) in the unquoted heredoc; the pre-fix census ate the second backslash
# as an escaped dollar and stayed GREEN
m27 "p:comment \\\\\$(true)"  p 's/^\(# wraps in \\`timeout 8\\`.*\)$/\1 \\\\$(true)/'
m27 "s:comment \\\\\$HOME"    s 's/^\(# address — \\`failover arm\\` probes both.*\)$/\1 \\\\$HOME/'
# (P2-INERT-2) the render must never execute an absolute path or write outside its temp dir: an
# absolute-path command and a builtin redirection in a comment line → RED, and neither file exists after
m27 "p:comment \$(/usr/bin/touch PWNED)"  p "s|^\\(# wraps in \\\\\`timeout 8\\\\\`.*\\)\$|\\1 \$(/usr/bin/touch $WORKDIR_27/PWNED)|"
m27 "s:comment \$(true > PWNED2)"         s "s|^\\(# address — \\\\\`failover arm\\\\\` probes both.*\\)\$|\\1 \$(true > $WORKDIR_27/PWNED2)|"
# S4 (fix round 3, panel CC2-1 / P3-R9-1): the two census blind spellings, and the render write/kill
# primitives. A "$\\"-then-newline continuation the pre-fix census scanned unjoined (its class had no
# leading backslash) and "$[...]" arithmetic its class omitted are now census-caught (census >= 1 →
# NOT-RUN); on the pre-fix tree the continuation also RAN its command at deploy time. The render-reachable
# forms carried in that continuation — a per-command CANARY_LOG= that re-points the recorder, an
# absolute-path "history -w", "kill" of a sentinel — are RED at the census, and the render (second layer)
# writes no file outside the temp dir and does not kill the sentinel.
sleep 600 >/dev/null 2>&1 & M27_SENT=$!
payf() { printf '%s\n' "$@" > "$WORKDIR_27/payf"; }
payf '$\' '(true) tl';                                       m27f "p:cont \$(true)"         p
payf 'costs $[1+1] s';                                         m27f "p:\$[1+1]"               p
payf '$[ CFG_TAKEOVER_DELAY = 0 ]';                            m27f "p:\$[ CFG rewrite ]"     p
payf '$\' "(CANARY_LOG=$WORKDIR_27/PWNED_canary date x) tl";  m27f "p:cont CANARY_LOG= date" p
payf '$\' "(history -w $WORKDIR_27/PWNED_hist) tl";           m27f "p:cont history -w abs"   p
payf '$\' "(kill -TERM $M27_SENT) tl";                        m27f "s:cont kill sentinel"    s
kill -0 "$M27_SENT" 2>/dev/null || { m27_ok=0; bad "(27-ctl) the sentinel was KILLED through the guard"; }
kill "$M27_SENT" 2>/dev/null
[[ -e "$WORKDIR_27/PWNED" || -e "$WORKDIR_27/PWNED2" || -e "$WORKDIR_27/PWNED_canary" || -e "$WORKDIR_27/PWNED_hist" ]] && { m27_ok=0; bad "(27-ctl) a PWNED file EXISTS after the guard ran: $(ls "$WORKDIR_27" | tr '\n' ' ')"; }
[[ $m27_ok -eq 1 ]] && ok "(27-ctl) every hazard mutant turns (27) RED —$m27_rows — a backtick / \$(true) / \$(failover arm) in EITHER heredoc, \$TIER2_RPC / \${LEDGER} / \$((1+1)) / \$HOME in a comment line, the escaped \\\$HOME value unescaped, an escaped backslash before \$(true) / \$HOME (pre-fix R9 census: GREEN), an absolute-path command / a builtin redirection in a comment line, and (fix round 3, S4) a \$\\-newline continuation before \$(true) / a re-pointed \$(CANARY_LOG=… date) / \$(history -w …) / \$(kill …), plus \$[1+1] and \$[ CFG rewrite ] (pre-fix census: GREEN, and the continuation RAN its command at deploy time) — with NO PWNED file outside the temp dir and the sentinel still alive (pre-fix guard: green on the primary-heredoc and comment-line forms)"
# (27-ctl-r) the RENDER layer on its own (the census bypassed — rendered directly): forbidden forms FAIL
# LOUDLY on stderr / are RECORDED, and create nothing outside the temp dir. Absolute path + redirection
# (pre-fix R9: both files created); and (fix round 3, S4) an absolute-path `history -w` (3.2 wrote it;
# blocked now by `enable -n history`), a `CANARY_LOG=<abs>` per-command re-point (both bashes wrote it;
# blocked now by the baked log path), and `kill` of a sentinel (both bashes killed it; blocked now by
# `enable -n kill`).
mutate "$DEPLOY_PRIMARY" "s|^# wraps in \\\\\`timeout 8\\\\\`|# wraps in \$(/usr/bin/touch $WORKDIR_27/PWNED3) \$(true > $WORKDIR_27/PWNED4) \\\\\`timeout 8\\\\\`|" "$WORKDIR_27/mut-r.sh"
rr=$(hd_render "$WORKDIR_27/mut-r.sh" /opt/solana-failover/failover.env)
if [[ "$(field "$rr" err)" == *"restricted: cannot specify"* && "$(field "$rr" err)" == *"restricted: cannot redirect output"* && ! -e "$WORKDIR_27/PWNED3" && ! -e "$WORKDIR_27/PWNED4" ]]; then
  ok "(27-ctl-r) the restricted render ALONE (census bypassed): \$(/usr/bin/touch …) and \$(true > …) fail LOUDLY on stderr ('restricted: cannot specify \`/' in command names', 'restricted: cannot redirect output') and create nothing — a spelling the census misses cannot run an absolute path or write outside the temp dir (pre-fix render: both files CREATED)"
else
  bad "(27-ctl-r) err='$(field "$rr" err | cut -c1-200)' files=$(ls "$WORKDIR_27" | tr '\n' ' ')"
fi
# S4 render-only: the write/kill builtins the pre-fix render allowed. Each carried as a bare `$(…)` the
# census WOULD flag — but rendered directly here (census bypassed) to prove the render itself now stops it.
r_ok=1; r_rows=""
sleep 600 >/dev/null 2>&1 & RR_SENT=$!
rcheck() {   # $1=label $2=payload-in-a-comment $3=path-that-must-not-appear ("" = none)
  mutate "$DEPLOY_PRIMARY" "s|^# wraps in \\\\\`timeout 8\\\\\`|# wraps in $2 \\\\\`timeout 8\\\\\`|" "$WORKDIR_27/mut-rs.sh" || { r_ok=0; return; }
  hd_render "$WORKDIR_27/mut-rs.sh" /opt/solana-failover/failover.env >/dev/null
  if [[ -n "$3" && -e "$3" ]]; then r_ok=0; bad "(27-ctl-r) $1 WROTE $3"; else r_rows="$r_rows $1"; fi
}
rcheck "history -w abs"      "\$(history -w $WORKDIR_27/PWNED_r_hist)"                 "$WORKDIR_27/PWNED_r_hist"
rcheck "CANARY_LOG= repoint" "\$(CANARY_LOG=$WORKDIR_27/PWNED_r_canary date x)"        "$WORKDIR_27/PWNED_r_canary"
rcheck "kill sentinel"       "\$(kill -TERM $RR_SENT)"                                 ""
kill -0 "$RR_SENT" 2>/dev/null || { r_ok=0; bad "(27-ctl-r) the render KILLED the sentinel"; }
kill "$RR_SENT" 2>/dev/null
[[ $r_ok -eq 1 ]] && ok "(27-ctl-r/S4) the restricted render ALONE also stops the builtin write/kill primitives —$r_rows — with its CWD/TMPDIR inside the temp dir, the rec-log path baked into each canary, and history / kill / ulimit / suspend disabled: no file outside the temp dir, the sentinel alive (pre-fix render: history -w wrote on 3.2, the CANARY_LOG re-point wrote on both bashes, kill killed on both)"
rm -rf "$WORKDIR_27"

results_banner
