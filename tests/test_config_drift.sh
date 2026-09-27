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
#   (h) LOCAL_HEALTH_MAX_BEHIND (Block 6.3.1 D5): the 6.3 M9 announce BECAME a clamp — effective =
#       min(configured, 128), > 128 WARNs, < 128 behaves as 128 at agave's default distance (three bands,
#       at startup and at the Tier-1 comparison); the clamp lives outside the announce-only section
#   (g) CONTROL (non-vacuous): neuter the announce path → (a) records ZERO lines (the suite's
#       assertions genuinely depend on the shipped code); plus the startup call-site exists in both
#       daemons AFTER validate_numeric_config and BEFORE the main loop
# NOT asserted (by design, spec'd): unset-vs-set-to-default — indistinguishable after sourcing and
# equal-to-default is silent either way. PRIMARY_SELF_FENCE / STANDBY_SELF_FENCE /
# VOTE_LIVENESS_VERIFY are excluded from the table (fatal-or-page elsewhere).

# harness: tests/lib/harness.sh — ok/bad+banners, paths, drift_out (byte-kept in the lib),
# extract_twin (the f5/f6 parity extractions cannot silently compare two empties). The (g1)
# neutered-announce control's inline cut stays local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
count_drift() { printf '%s\n' "$1" | grep -c '\[config-drift\]'; }

title_banner "Safety-config drift announcement (v0.7 Block 3 slice 3.5)"

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
if extract_twin '^_drift_check() {' '^}$' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(f5) _drift_check body byte-identical in both daemons ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)"
else
    bad "(f5) _drift_check missing or DIVERGED between the daemons"
fi
if extract_twin 'config-drift\] shared safety-knob table' 'config-drift\] end shared table' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(f6) shared knob table byte-identical in both daemons ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)"
else
    bad "(f6) shared knob table missing or DIVERGED between the daemons"
fi
# The role tables carry exactly their own daemon's knobs.
grep -A4 'config-drift\] role-specific' "$PRIMARY" | grep -q 'RECOVERY_DELAY 300 high' \
    && ok "(f7) PRIMARY role table carries RECOVERY_DELAY (default 300, higher-stricter)" \
    || bad "(f7) PRIMARY role table lacks RECOVERY_DELAY"
S_ROLE=$(grep -A4 'config-drift\] role-specific' "$STANDBY")
if [[ "$S_ROLE" == *"SELF_FENCE_RETAKE_COOLDOWN 600 high"* && "$S_ROLE" == *"EXPECTED_PRIMARY_SELF_FENCE_SECS 30 high"* && "$S_ROLE" == *"SELF_FENCE_MARGIN_SECS 30 high"* && "$S_ROLE" == *"TAKEOVER_STARVATION_ALERT_SECS 300 low0"* ]]; then
    ok "(f8) STANDBY role table carries RETAKE_COOLDOWN/EXPECTED/MARGIN (higher-stricter) + STARVATION_ALERT (lower-stricter, 0 disables)"
else
    bad "(f8) STANDBY role table incomplete"
fi

# ── (h) LOCAL_HEALTH_MAX_BEHIND: the 6.3 M9 announce BECAME THE CLAMP (Block 6.3.1 D5) ─────────────
# Effective value = min(configured, 128) — agave's DEFAULT --health-check-slot-distance (agave 4.2.1
# rpc_health.rs check(): "behind" only when MORE than the distance behind; validator json_rpc_config.rs
# default = DELINQUENT_VALIDATOR_SLOT_DISTANCE = 128). Three bands, at startup AND at the comparison:
#   > 128 → ONE loud [config-clamp] WARN naming the value, effective 128 (h1); Tier-1 refuses a spare
#           150 slots behind even at 200 (h4 — the comparison clamps too, startup or not)
#   = 128 → silent, 128 (h2)
#   < 128 → one info line: it BEHAVES AS 128 at agave's default distance (every 'behind' report there
#           is >= 129) — (h2), and the comparison: 'behind by 129' fails at 100 exactly as at 128, the
#           displayed max says so; only a SMALLER non-default distance ('behind by 100' reported) makes
#           the value below 128 the effective threshold (h5)
# The clamp mutates the knob, so it lives OUTSIDE announce_config_drift (INVARIANT(announce-only)) —
# (h3). Pre-fix red (the 6.3 build): 200 → a [config-drift] announce and the knob stays 200; Tier-1
# ADMITS a spare 150 slots behind at 200.
echo ""; echo "─── (h) LOCAL_HEALTH_MAX_BEHIND → CLAMPED to min(configured, 128) (6.3.1 D5; was the M9 announce) ───"
clamp_out() {   # $1=script $2=value → the clamp's log lines, then "eff=<value after the clamp>"
    (
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$1" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        log_info(){ printf 'INFO %s\n' "$*"; }; log_error(){ :; }
        log_warn(){ printf 'WARN %s\n' "$*"; }
        LOCAL_HEALTH_MAX_BEHIND="$2"
        if declare -F _clamp_local_health_max_behind >/dev/null; then _clamp_local_health_max_behind; else echo "NO-CLAMP-FUNCTION"; fi
        echo "eff=$LOCAL_HEALTH_MAX_BEHIND"
    )
}
out=$(clamp_out "$STANDBY" 200)
if [[ "$(printf '%s\n' "$out" | grep -c '^WARN \[config-clamp\]')" == "1" && "$out" == *"LOCAL_HEALTH_MAX_BEHIND=200 CLAMPED to 128"* && "$out" == *"effective = min(configured, 128)"* \
      && "$out" == *"ADMIT a spare up to 200 slots behind"* && "$out" == *"set LOCAL_HEALTH_MAX_BEHIND=128"* && "$out" == *"eff=128" ]]; then
    ok "(h1) LOCAL_HEALTH_MAX_BEHIND=200 → ONE loud [config-clamp] WARN (the value, CLAMPED to 128, why it would widen Tier-1, how to align) and the EFFECTIVE value is 128"
else
    bad "(h1) got: $out"
fi
o128=$(clamp_out "$STANDBY" 128); o100=$(clamp_out "$STANDBY" 100); o129=$(clamp_out "$STANDBY" 129); o0=$(clamp_out "$STANDBY" 0)
if [[ "$o128" == "eff=128" && "$o129" == *"CLAMPED to 128"* && "$o129" == *"eff=128" \
      && "$(printf '%s\n' "$o100" | grep -c '^INFO \[config\] LOCAL_HEALTH_MAX_BEHIND=100 behaves as 128 at agave')" == "1" && "$o100" != *WARN* && "$o100" == *"eff=100" \
      && "$o0" == *"LOCAL_HEALTH_MAX_BEHIND=0 behaves as 128"* && "$o0" == *"eff=0" ]]; then
    ok "(h2) bands: 128 → silent, 128; 129 → clamped to 128; 100 and 0 → one INFO line each saying it BEHAVES AS 128 at agave's default distance (no WARN; the knob keeps its value — min(configured,128))"
else
    bad "(h2) 128='$o128' 129='$o129' 100='$o100' 0='$o0'"
fi
# (h3) the announce-only invariant: announce_config_drift neither mentions nor mutates the knob; the
# clamp call sits in startup right after validate_numeric_config, BEFORE announce_config_drift
outd=$(drift_out "$STANDBY" 'LOCAL_HEALTH_MAX_BEHIND=200')
acd=$(awk '/^announce_config_drift\(\) \{/,/^\}/' "$STANDBY")
cl_ln=$(grep -n '^[[:space:]]*_clamp_local_health_max_behind[[:space:]]*#' "$STANDBY" | head -1 | cut -d: -f1)
vnc_ln=$(grep -n '^[[:space:]]*validate_numeric_config[[:space:]]*#' "$STANDBY" | head -1 | cut -d: -f1)
acd_ln=$(grep -n '^[[:space:]]*announce_config_drift[[:space:]]*#' "$STANDBY" | head -1 | cut -d: -f1)
if [[ -z "$outd" && -n "$acd" && "$(printf '%s\n' "$acd" | grep -v '^[[:space:]]*#' | grep -c 'LOCAL_HEALTH_MAX_BEHIND')" == "0" \
      && -n "$cl_ln" && -n "$vnc_ln" && -n "$acd_ln" && $cl_ln -eq $((vnc_ln + 1)) && $cl_ln -lt $acd_ln ]]; then
    ok "(h3) announce_config_drift stays announce-only (no LOCAL_HEALTH_MAX_BEHIND code in it; 200 → no [config-drift] line); the clamp is called in startup right after validate_numeric_config (l$vnc_ln → l$cl_ln), before announce_config_drift (l$acd_ln)"
else
    bad "(h3) drift='$outd' clamp=$cl_ln validate=$vnc_ln announce=$acd_ln code-mentions=$(printf '%s\n' "$acd" | grep -v '^[[:space:]]*#' | grep -c 'LOCAL_HEALTH_MAX_BEHIND')"
fi
# (h4)/(h5) the comparison itself — tier1_check_local_health under a getHealth stub answering
# 'behind by N' (no startup run: the comparison must clamp on its own)
t1_out() {   # $1=script $2=LOCAL_HEALTH_MAX_BEHIND $3=numSlotsBehind → "rc=<0 ready|1 not> | <log>"
    (
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$1" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        _L=""; log_info(){ _L="$_L|$*"; }; log_warn(){ _L="$_L|$*"; }; log_error(){ :; }; _watchdog_pet(){ :; }
        LOCAL_RPC="http://local.mock"; LOCAL_HEALTH_MAX_BEHIND="$2"; _N="$3"
        curl(){ printf '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by %s slots","data":{"numSlotsBehind":%s}},"id":1}' "$_N" "$_N"; }
        tier1_check_local_health; echo "rc=$? $_L"
    )
}
r200=$(t1_out "$STANDBY" 200 150); r128=$(t1_out "$STANDBY" 128 150)
if [[ "$r200" == "rc=1 "* && "$r200" == *"150 slots behind (max: 128) — not ready"* && "$r128" == "rc=1 "* ]]; then
    ok "(h4) the comparison clamps too: agave 'behind by 150' at LOCAL_HEALTH_MAX_BEHIND=200 → NOT ready (max: 128), exactly as at 128 — no path widens Tier-1 past agave's default distance (pre-fix: ready at 200)"
else
    bad "(h4) 200→'$r200' 128→'$r128'"
fi
r100a=$(t1_out "$STANDBY" 100 129); r100b=$(t1_out "$STANDBY" 100 100); r100c=$(t1_out "$STANDBY" 100 101)
if [[ "$r100a" == "rc=1 "* && "$r100a" == *"129 slots behind (max: 100 — behaves as 128 at agave's default health-check distance) — not ready"* \
      && "$r100b" == "rc=0 "* && "$r100c" == "rc=1 "* ]]; then
    ok "(h5) below 128: 'behind by 129' (the smallest report agave's DEFAULT distance can make) fails at 100 exactly as at 128 and the log says it behaves as 128; only a SMALLER non-default distance's report ('behind by 100' vs 101) meets the configured 100 as its threshold"
else
    bad "(h5) 129@100='$r100a' 100@100='$r100b' 101@100='$r100c'"
fi
if ! grep -q '_clamp_local_health_max_behind\|LOCAL_HEALTH_MAX_BEHIND' "$PRIMARY"; then
    ok "(h6) the PRIMARY (no Tier-1 takeover gate) carries neither the knob nor the clamp — the knob is the spare's"
else
    bad "(h6) the primary mentions LOCAL_HEALTH_MAX_BEHIND / the clamp"
fi
# (h7) every displayed max states the real threshold: the shipped default IS 128, the env template and
# the wizard default say 128, and the startup display has the three band lines
if grep -q '^LOCAL_HEALTH_MAX_BEHIND=128$' "$STANDBY" && grep -q '^LOCAL_HEALTH_MAX_BEHIND=128$' "$HARNESS_DIR/failover-standby.env.example" \
      && grep -q 'LOCAL_HEALTH_MAX_BEHIND:-128}' "$HARNESS_DIR/deploy-failover-standby.sh" \
      && grep -q 'Health max behind: 128 slots (CLAMPED from' "$STANDBY" && grep -q 'Health max behind: 128 slots effective at agave' "$STANDBY"; then
    ok "(h7) the default states the real threshold everywhere: daemon, env template and wizard default = 128; the startup display prints 'CLAMPED from N' / '128 effective (configured N behaves as 128)'"
else
    bad "(h7) a displayed default/max does not state 128"
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

results_banner
