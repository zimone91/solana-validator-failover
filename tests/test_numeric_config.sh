#!/bin/bash
# v0.6.5 (F4): startup numeric-config validation. Sources the SHIPPED validate_numeric_config /
# _validate_numeric from each script (up to the MAIN LOOP marker) and asserts:
#   - a non-numeric knob is REJECTED at startup (exit 1) — bash arithmetic would otherwise read it
#     as 0, collapsing a delay/interval/threshold
#   - a below-minimum value is rejected
#   - a leading-zero value is normalized via 10# (octal-safe)
#   - STANDBY: TAKEOVER_DELAY < VOTE_LIVENESS_MIN_INTERVAL is rejected with vote-liveness ON, but
#     allowed with it OFF (the explicit unfenced emergency path)
#   - a fully-valid default config passes (exit 0)
# Non-vacuous: revert validate_numeric_config (no-op) → the rejection cases return 0 and FAIL.

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
STANDBY="$DIR/solana-standby-failover.sh"

# Exit code of validate_numeric_config under the given VAR=val overrides. The inner ( ) contains the
# `exit 1` a bad knob triggers, so the outer command substitution still reaches `echo $?`.
rc_of() {  # $1=script ; rest=VAR=val overrides
    local script="$1"; shift
    (
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
        for kv in "$@"; do eval "$kv"; done
        ( validate_numeric_config ) >/dev/null 2>&1
        echo $?
    )
}
# Normalized value of $2 after a successful validation under the given overrides.
norm_of() {  # $1=script $2=varname ; rest=overrides
    local script="$1" var="$2"; shift 2
    (
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
        for kv in "$@"; do eval "$kv"; done
        validate_numeric_config >/dev/null 2>&1
        echo "${!var}"
    )
}

echo "============================================="
echo "  F4: numeric config validation"
echo "============================================="

# --- valid defaults pass ---
[[ "$(rc_of "$PRIMARY")" == "0" ]] && ok "PRIMARY: default config passes" || bad "PRIMARY: default config rejected"
[[ "$(rc_of "$STANDBY")" == "0" ]] && ok "STANDBY: default config passes" || bad "STANDBY: default config rejected"

# --- non-numeric rejected (the headline F4 acceptance) ---
[[ "$(rc_of "$PRIMARY" 'CHECK_INTERVAL=abc')" == "1" ]] && ok "PRIMARY: non-numeric CHECK_INTERVAL rejected" || bad "PRIMARY: non-numeric CHECK_INTERVAL accepted (would read as 0)"
[[ "$(rc_of "$STANDBY" 'TAKEOVER_DELAY=abc')" == "1" ]] && ok "STANDBY: non-numeric TAKEOVER_DELAY rejected" || bad "STANDBY: non-numeric TAKEOVER_DELAY accepted (would read as 0)"
[[ "$(rc_of "$STANDBY" 'MAX_DELINQUENT_SLOTS=10s')" == "1" ]] && ok "STANDBY: non-numeric MAX_DELINQUENT_SLOTS ('10s') rejected" || bad "STANDBY: '10s' accepted"

# --- below-min rejected ---
[[ "$(rc_of "$PRIMARY" 'CHECK_INTERVAL=0')" == "1" ]] && ok "PRIMARY: CHECK_INTERVAL=0 (< min 1) rejected" || bad "PRIMARY: CHECK_INTERVAL=0 accepted"
[[ "$(rc_of "$STANDBY" 'CHECK_INTERVAL=0')" == "1" ]] && ok "STANDBY: CHECK_INTERVAL=0 (< min 1) rejected" || bad "STANDBY: CHECK_INTERVAL=0 accepted"

# --- leading-zero normalized (octal-safe) ---
[[ "$(norm_of "$PRIMARY" CHECK_INTERVAL 'CHECK_INTERVAL=08')" == "8" ]] && ok "PRIMARY: leading-zero CHECK_INTERVAL 08 → 8" || bad "PRIMARY: 08 not normalized"
[[ "$(norm_of "$STANDBY" TAKEOVER_DELAY 'TAKEOVER_DELAY=030')" == "30" ]] && ok "STANDBY: leading-zero TAKEOVER_DELAY 030 → 30" || bad "STANDBY: 030 not normalized"

# --- cross-knob: TAKEOVER_DELAY >= VOTE_LIVENESS_MIN_INTERVAL (with vote-liveness on) ---
[[ "$(rc_of "$STANDBY" 'VOTE_LIVENESS_VERIFY=true' 'VOTE_LIVENESS_MIN_INTERVAL=10' 'TAKEOVER_DELAY=5')" == "1" ]] \
    && ok "STANDBY: TAKEOVER_DELAY(5) < MIN_INTERVAL(10) rejected (liveness on)" \
    || bad "STANDBY: short TAKEOVER_DELAY accepted while liveness on"
[[ "$(rc_of "$STANDBY" 'VOTE_LIVENESS_VERIFY=false' 'ALLOW_UNFENCED_TAKEOVER=true' 'VOTE_LIVENESS_MIN_INTERVAL=10' 'TAKEOVER_DELAY=5')" == "0" ]] \
    && ok "STANDBY: short TAKEOVER_DELAY allowed when vote-liveness OFF (emergency path)" \
    || bad "STANDBY: short TAKEOVER_DELAY blocked even unfenced"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
