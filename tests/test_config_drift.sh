#!/bin/bash
# v0.7 (Block 3, slice 3.5): safety-config DRIFT ANNOUNCEMENT. An env written by an older installer
# (≤ v0.6.10 wrote VOTE_LIVENESS_EPSILON=2) silently overrides a newer daemon's stricter default
# after an in-place upgrade — "we shipped ε=0" and "the fleet runs ε=0" are different claims. The
# daemons now compare the critical safety knobs' EFFECTIVE values against THIS version's shipped
# defaults at startup and log_warn ONE [config-drift] line per knob overridden in the LESS STRICT
# direction (never fatal, never overriding, never invisible). Drives the REAL shipped
# announce_config_drift/_drift_check (source-to-MAIN-LOOP seam, log_warn recorder):
#   (a) THE MOTIVATING CASE: VOTE_LIVENESS_EPSILON=2 on the STANDBY → exactly one [config-drift]
#       line naming the knob, env value 2, this version's default 0, and the align instruction
#   (b) STRICTER values (MIN_INTERVAL=20, RETAKE_COOLDOWN=900, ISOLATION=10) → silent
#   (c) equal-to-default → silent; multiple drifted knobs → one line each
#   (d) SELF_FENCE_NOANSWER_SECS=0 → 0 disables the sub-check entirely = the LAXEST value,
#       announced with DISTINCT wording (not the generic "laxer than"); nonzero-laxer (60) generic
#   (e) SELF_FENCE_HARD_STOP=false → announced (true-is-stricter); empty = runtime-true → silent
#   (f) PRIMARY twin: RECOVERY_DELAY=60 → announced; role separation (each daemon checks only its
#       own role knobs); the helper + shared table BYTE-IDENTICAL across daemons except the
#       role-specific knob tables (structural, like test_provider_pinning's (g))
#   (g) CONTROL (non-vacuous): neuter the announce path → (a) records ZERO lines (the suite's
#       assertions genuinely depend on the shipped code); plus the startup call-site exists in both
#       daemons AFTER validate_numeric_config and BEFORE the main loop
# NOT asserted (by design, spec'd): unset-vs-set-to-default — indistinguishable after sourcing and
# equal-to-default is silent either way. PRIMARY_SELF_FENCE / STANDBY_SELF_FENCE /
# VOTE_LIVENESS_VERIFY are excluded from the table (fatal-or-page elsewhere).

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$PRIMARY" && -f "$STANDBY" ]] || { echo "  ❌ scripts not found"; exit 1; }

# Recorded [config-drift] output of the REAL announce_config_drift under the given VAR=val
# overrides. Sources the shipped script up to the MAIN LOOP marker (defaults + functions, no loop),
# then records log_warn verbatim on stdout. log_info/log_error silenced.
drift_out() {  # $1=script ; rest=VAR=val overrides
    local script="$1"; shift
    (
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        log_info(){ :; }; log_error(){ :; }
        log_warn(){ printf '%s\n' "$*"; }
        for kv in "$@"; do eval "$kv"; done
        announce_config_drift
    )
}
count_drift() { printf '%s\n' "$1" | grep -c '\[config-drift\]'; }

echo "============================================="
echo "  Safety-config drift announcement (v0.7 Block 3 slice 3.5)"
echo "============================================="

# ── (a) THE MOTIVATING CASE: a ≤ v0.6.10 env's VOTE_LIVENESS_EPSILON=2 on the standby ───────────
echo ""; echo "─── (a) VOTE_LIVENESS_EPSILON=2 (the ≤ v0.6.10 PRIMARY installer env (the standby case here is synthetic — old standby wizards never wrote the knob)) → exactly one announce ───"
out=$(drift_out "$STANDBY" 'VOTE_LIVENESS_EPSILON=2')
n=$(count_drift "$out")
[[ "$n" == "1" ]] && ok "(a1) exactly one [config-drift] line (got $n)" \
                  || bad "(a1) expected exactly 1 [config-drift] line, got $n: $out"
[[ "$out" == *"VOTE_LIVENESS_EPSILON=2"* ]] && ok "(a2) names the knob and the env value (VOTE_LIVENESS_EPSILON=2)" \
                                            || bad "(a2) knob/env value missing: $out"
[[ "$out" == *"default 0"* ]] && ok "(a3) states this version's default (0)" \
                              || bad "(a3) default 0 not stated: $out"
if [[ "$out" == *"align: set VOTE_LIVENESS_EPSILON=0 in"* && "$out" == *"failover-standby.env"* && "$out" == *"(or delete the line) and restart"* ]]; then
    ok "(a4) align instruction: set to default in the env file (or delete the line) and restart"
else
    bad "(a4) align instruction incomplete: $out"
fi

# ── (b) STRICTER values are silent ───────────────────────────────────────────────────────────────
echo ""; echo "─── (b) stricter-than-default values → silent ───"
out=$(drift_out "$STANDBY" 'VOTE_LIVENESS_MIN_INTERVAL=20' 'SELF_FENCE_RETAKE_COOLDOWN=900' 'SELF_FENCE_ISOLATION_SECS=10' 'SELF_FENCE_MARGIN_SECS=60')
n=$(count_drift "$out")
[[ "$n" == "0" && -z "$out" ]] && ok "(b1) MIN_INTERVAL=20 / RETAKE_COOLDOWN=900 / ISOLATION=10 / MARGIN=60 all stricter → silent" \
                               || bad "(b1) stricter values announced ($n lines): $out"

# ── (c) equal-to-default silent; multiple drifted knobs → one line each ──────────────────────────
echo ""; echo "─── (c) equal = silent; multiple drifts = one line each ───"
out=$(drift_out "$STANDBY")
[[ -z "$out" ]] && ok "(c1) untouched defaults (= equal-to-default for every knob) → fully silent" \
                || bad "(c1) defaults produced output: $out"
out=$(drift_out "$STANDBY" 'VOTE_LIVENESS_EPSILON=0' 'SELF_FENCE_ISOLATION_SECS=30' 'SELF_FENCE_HARD_STOP=true' 'SELF_FENCE_RETAKE_COOLDOWN=600')
[[ -z "$out" ]] && ok "(c2) explicitly set EQUAL to defaults → silent (set-to-default ≡ unset by design)" \
                || bad "(c2) equal-to-default announced: $out"
out=$(drift_out "$STANDBY" 'VOTE_LIVENESS_EPSILON=3' 'SELF_FENCE_ISOLATION_SECS=60' 'SELF_FENCE_MARGIN_SECS=10')
n=$(count_drift "$out")
if [[ "$n" == "3" && "$out" == *"VOTE_LIVENESS_EPSILON=3"* && "$out" == *"SELF_FENCE_ISOLATION_SECS=60"* && "$out" == *"SELF_FENCE_MARGIN_SECS=10"* ]]; then
    ok "(c3) three drifted knobs → three lines, each naming its knob"
else
    bad "(c3) expected 3 lines naming the 3 knobs, got $n: $out"
fi

# ── (d) NOANSWER=0 special case: 0 = sub-check disabled = the LAXEST value ───────────────────────
echo ""; echo "─── (d) SELF_FENCE_NOANSWER_SECS=0 → announced as DISABLED (laxest), distinct wording ───"
out=$(drift_out "$STANDBY" 'SELF_FENCE_NOANSWER_SECS=0')
n=$(count_drift "$out")
if [[ "$n" == "1" && "$out" == *"SELF_FENCE_NOANSWER_SECS=0 DISABLES"* && "$out" == *"LAXEST"* && "$out" == *"default: 30"* ]]; then
    ok "(d1) NOANSWER=0 → one line, DISABLES + LAXEST wording, default 30 named"
else
    bad "(d1) NOANSWER=0 wording wrong ($n lines): $out"
fi
[[ "$out" != *"is laxer than this version's default"* ]] \
    && ok "(d2) 0-case wording is DISTINCT from the generic laxer-than line" \
    || bad "(d2) 0-case fell through to the generic wording: $out"
[[ "$out" == *"align: set SELF_FENCE_NOANSWER_SECS=30 in"* ]] \
    && ok "(d3) 0-case still carries the align instruction (=30)" \
    || bad "(d3) 0-case align instruction missing: $out"
# v0.7 slice-3.5 amend: VOTE_LAG_SLOTS/SECS=0 ALSO disable their fence (code: arming requires -gt 0)
# — under plain "low" a 0 read as stricter and stayed SILENT; they are low0 now. Control: revert
# either knob's direction to "low" → (d4)/(d5) fail.
out=$(drift_out "$STANDBY" 'SELF_FENCE_VOTE_LAG_SLOTS=0')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"SELF_FENCE_VOTE_LAG_SLOTS=0 DISABLES"* ]] \
    && ok "(d4) VOTE_LAG_SLOTS=0 → announced as DISABLED/laxest (was silent-as-stricter)" \
    || bad "(d4) VOTE_LAG_SLOTS=0 wrong ($n lines): $out"
out=$(drift_out "$STANDBY" 'SELF_FENCE_VOTE_LAG_SECS=0')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"SELF_FENCE_VOTE_LAG_SECS=0 DISABLES"* ]] \
    && ok "(d5) VOTE_LAG_SECS=0 → announced as DISABLED/laxest" \
    || bad "(d5) VOTE_LAG_SECS=0 wrong ($n lines): $out"
# verifier follow-up: MAX_BEHIND also 0-disables (arming -gt 0) AND is higher-laxer — both ways
# were silent before this entry. Control: drop the table line → (d7)/(d8) fail.
out=$(drift_out "$STANDBY" 'SELF_FENCE_MAX_BEHIND=0')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"SELF_FENCE_MAX_BEHIND=0 DISABLES"* ]] \
    && ok "(d7) MAX_BEHIND=0 → announced as DISABLED/laxest" \
    || bad "(d7) MAX_BEHIND=0 wrong ($n lines): $out"
out=$(drift_out "$STANDBY" 'SELF_FENCE_MAX_BEHIND=1000')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"SELF_FENCE_MAX_BEHIND=1000 is laxer"* ]] \
    && ok "(d8) MAX_BEHIND=1000 → generic laxer line (higher tolerates more behind)" \
    || bad "(d8) MAX_BEHIND=1000 wrong ($n lines): $out"
# reviewer (slice-3.5 GO): a high-direction knob whose 0 DISABLES a protection must say so by name —
# "laxer than default" and "DISABLES the re-take lockout" trigger different operator reactions, and
# the one startup line is the only channel. Control: revert high0→high in the table → (d9) fails.
out=$(drift_out "$STANDBY" 'SELF_FENCE_RETAKE_COOLDOWN=0')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"SELF_FENCE_RETAKE_COOLDOWN=0 DISABLES"* ]] \
    && ok "(d9) RETAKE_COOLDOWN=0 → announced as DISABLED/laxest (not generic)" \
    || bad "(d9) RETAKE_COOLDOWN=0 wrong ($n lines): $out"
out=$(drift_out "$STANDBY" 'SELF_FENCE_RETAKE_COOLDOWN=120')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"SELF_FENCE_RETAKE_COOLDOWN=120 is laxer"* ]] \
    && ok "(d10) RETAKE_COOLDOWN=120 (nonzero-laxer) → generic wording" \
    || bad "(d10) RETAKE_COOLDOWN=120 wrong ($n lines): $out"
out=$(drift_out "$STANDBY" 'SELF_FENCE_NOANSWER_SECS=60')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"SELF_FENCE_NOANSWER_SECS=60 is laxer than this version's default 30"* ]] \
    && ok "(d6) NOANSWER=60 (nonzero-laxer) → generic wording" \
    || bad "(d6) NOANSWER=60 not announced generically ($n lines): $out"

# ── (e) SELF_FENCE_HARD_STOP=false (true-is-stricter boolean) ────────────────────────────────────
echo ""; echo "─── (e) SELF_FENCE_HARD_STOP=false → announced ───"
out=$(drift_out "$STANDBY" 'SELF_FENCE_HARD_STOP=false')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"SELF_FENCE_HARD_STOP=false is laxer than this version's default true"* ]] \
    && ok "(e1) HARD_STOP=false → one line, default true named" \
    || bad "(e1) HARD_STOP=false not announced ($n lines): $out"
out=$(drift_out "$STANDBY" 'SELF_FENCE_HARD_STOP=""')
[[ -z "$out" ]] && ok "(e2) HARD_STOP empty → silent (runtime gates read \${KNOB:-true} → empty behaves strict)" \
                || bad "(e2) empty HARD_STOP announced: $out"

# ── (f) PRIMARY twin + role separation + structural twin parity ──────────────────────────────────
echo ""; echo "─── (f) primary twin: RECOVERY_DELAY=60 announced; helpers byte-identical ───"
out=$(drift_out "$PRIMARY" 'RECOVERY_DELAY=60')
n=$(count_drift "$out")
if [[ "$n" == "1" && "$out" == *"RECOVERY_DELAY=60 is laxer than this version's default 300"* && "$out" == *"failover.env"* ]]; then
    ok "(f1) PRIMARY: RECOVERY_DELAY=60 → one line, default 300, names failover.env"
else
    bad "(f1) PRIMARY RECOVERY_DELAY=60 wrong ($n lines): $out"
fi
out=$(drift_out "$PRIMARY" 'VOTE_LIVENESS_EPSILON=2')
n=$(count_drift "$out")
[[ "$n" == "1" && "$out" == *"VOTE_LIVENESS_EPSILON=2"* ]] \
    && ok "(f2) PRIMARY shares the BOTH-daemons table (EPSILON=2 announced there too)" \
    || bad "(f2) PRIMARY EPSILON=2 not announced ($n lines): $out"
# Role separation: a knob outside a daemon's own table stays silent there.
out=$(drift_out "$PRIMARY" 'SELF_FENCE_RETAKE_COOLDOWN=0')
[[ -z "$out" ]] && ok "(f3) PRIMARY ignores the STANDBY-only RETAKE_COOLDOWN (role separation)" \
                || bad "(f3) PRIMARY announced a STANDBY-only knob: $out"
out=$(drift_out "$STANDBY" 'RECOVERY_DELAY=60')
[[ -z "$out" ]] && ok "(f4) STANDBY ignores the PRIMARY-only RECOVERY_DELAY (role separation)" \
                || bad "(f4) STANDBY announced a PRIMARY-only knob: $out"
# Structural twin parity (like test_provider_pinning (g)): the _drift_check body and the shared
# knob table must be BYTE-IDENTICAL across the daemons; only the role tables differ.
P_FN=$(sed -n '/^_drift_check() {/,/^}$/p' "$PRIMARY")
S_FN=$(sed -n '/^_drift_check() {/,/^}$/p' "$STANDBY")
if [[ -n "$P_FN" && "$P_FN" == "$S_FN" ]]; then
    ok "(f5) _drift_check body byte-identical in both daemons ($(printf '%s\n' "$P_FN" | wc -l | tr -d ' ') lines)"
else
    bad "(f5) _drift_check missing or DIVERGED between the daemons"
fi
P_TBL=$(sed -n '/config-drift\] shared safety-knob table/,/config-drift\] end shared table/p' "$PRIMARY")
S_TBL=$(sed -n '/config-drift\] shared safety-knob table/,/config-drift\] end shared table/p' "$STANDBY")
if [[ -n "$P_TBL" && "$P_TBL" == "$S_TBL" ]]; then
    ok "(f6) shared knob table byte-identical in both daemons ($(printf '%s\n' "$P_TBL" | wc -l | tr -d ' ') lines)"
else
    bad "(f6) shared knob table missing or DIVERGED between the daemons"
fi
# The role tables carry exactly their own daemon's knobs.
grep -A4 'config-drift\] role-specific' "$PRIMARY" | grep -q 'RECOVERY_DELAY 300 high' \
    && ok "(f7) PRIMARY role table carries RECOVERY_DELAY (default 300, higher-stricter)" \
    || bad "(f7) PRIMARY role table lacks RECOVERY_DELAY"
S_ROLE=$(grep -A4 'config-drift\] role-specific' "$STANDBY")
if [[ "$S_ROLE" == *"SELF_FENCE_RETAKE_COOLDOWN 600 high"* && "$S_ROLE" == *"EXPECTED_PRIMARY_SELF_FENCE_SECS 30 high"* && "$S_ROLE" == *"SELF_FENCE_MARGIN_SECS 30 high"* ]]; then
    ok "(f8) STANDBY role table carries RETAKE_COOLDOWN/EXPECTED/MARGIN (all higher-stricter)"
else
    bad "(f8) STANDBY role table incomplete"
fi

# ── (g) CONTROL (non-vacuous) + the startup call-site ────────────────────────────────────────────
echo ""; echo "─── (g) control: neutered announce → (a) records nothing; call-site placement ───"
out=$(
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$STANDBY" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    log_info(){ :; }; log_error(){ :; }
    log_warn(){ printf '%s\n' "$*"; }
    VOTE_LIVENESS_EPSILON=2
    announce_config_drift(){ :; }   # the announce call removed/neutered — the pre-slice-3.5 daemon
    announce_config_drift
)
n=$(count_drift "$out")
[[ "$n" == "0" ]] && ok "(g1) neutered announce → ZERO [config-drift] lines — (a1) would FAIL, suite is non-vacuous" \
                  || bad "(g1) neutered announce still produced output: $out"
# The call must actually sit in startup: after validate_numeric_config, before the MAIN LOOP.
for script in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$script")
    call_ln=$(grep -n '^[[:space:]]*announce_config_drift[[:space:]]*#' "$script" | head -1 | cut -d: -f1)
    vnc_ln=$(grep -n '^[[:space:]]*validate_numeric_config[[:space:]]*#' "$script" | head -1 | cut -d: -f1)
    loop_ln=$(grep -n 'MAIN LOOP' "$script" | head -1 | cut -d: -f1)
    if [[ -n "$call_ln" && -n "$vnc_ln" && -n "$loop_ln" && $call_ln -gt $vnc_ln && $call_ln -lt $loop_ln ]]; then
        ok "(g2) $name: announce_config_drift called in startup AFTER validate_numeric_config (l$vnc_ln < l$call_ln < MAIN LOOP l$loop_ln)"
    else
        bad "(g2) $name: call-site missing or misplaced (call=$call_ln validate=$vnc_ln loop=$loop_ln)"
    fi
done

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
