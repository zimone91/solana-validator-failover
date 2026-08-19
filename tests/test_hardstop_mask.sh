#!/bin/bash
# v0.6.9 (H2): the hard-stop must survive Restart=always. When `systemctl stop` fails and the PID is
# killed directly, systemd restarts the validator after RestartSec — AFTER the old immediate verify
# passed — and it resurrects VOTING STAKED. Fix: (a) mask --runtime before escalating to the kill,
# (b) RE-verify the down-state after HARD_STOP_REVERIFY_SECS. Drives the REAL _selffence_hard_stop
# (primary AND the H1 standby port) with mocks only at the I/O boundary (timeout, pgrep, kill, sleep).
#   (M-a) stop fails → mask attempted BEFORE the kill; success page says "unit masked" + names
#         `systemctl unmask --runtime`
#   (M-b) resurrect during the re-verify window → HARD STOP FAILED page (rc 1), even though the
#         immediate verify had passed
#   (M-c) mask itself fails → the kill still proceeds (never skipped), re-verify still guards
#   (M-d) clean stop (rc 0) → NO mask attempted; plain ✅ (no mask wording)
#   (M-e) NON-VACUOUS CONTROL: awk-strip the mask + re-verify blocks from a patched copy → the same
#         resurrect inputs return the OLD false-✅ (rc 0) — proves M-b bites
#   (M-f) standby port parity: the same resurrect scenario fails loudly on the standby copy too
#
# harness: tests/lib/harness.sh — ok/bad+banners, paths, field, mutate_filter (the M-e awk-strip
# control cannot silently no-op). scenario()'s cut + sink/mocks stay local (capture subset).

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# Run _selffence_hard_stop from the given script copy in a fresh subshell.
#   $1=script  $2=RC_STOP  $3=RC_MASK  $4=resurrect(1/0)  $5=proc_alive_at_start(1/0)
# Echoes: rc=<rc>|status=<last alert status>|events=<ordered STOP,MASK,KILL...>
scenario() {
  local script="$1" rc_stop="$2" rc_mask="$3" resurrect="$4" alive="$5"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VALIDATOR_TYPE="agave"; VALIDATOR_SERVICE="solana"
    SELF_FENCE_HARD_STOP=true; HARD_STOP_REVERIFY_SECS=7   # unique value so the sleep mock can key on it
    TG_ENABLED=false
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    send_telegram(){ return 0; }; send_webhook(){ :; }
    _STATUS=""; alert(){ _STATUS="$3"; }
    EV=$(mktemp); trap 'rm -f "$EV"' EXIT
    _PROC="$alive"; _RESURRECT="$resurrect"; _RC_STOP="$rc_stop"; _RC_MASK="$rc_mask"
    timeout(){
        case "$*" in
            *systemctl\ stop*) echo STOP >> "$EV"; return "$_RC_STOP" ;;
            *systemctl\ mask*) echo MASK >> "$EV"; return "$_RC_MASK" ;;
        esac
        return 0
    }
    pgrep(){ [[ "$_PROC" == "1" ]] && echo 4242; return 0; }
    kill(){ echo KILL >> "$EV"; _PROC=0; return 0; }
    sleep(){ [[ "$1" == "$HARD_STOP_REVERIFY_SECS" && "$_RESURRECT" == "1" ]] && _PROC=1; :; }
    _selffence_hard_stop "test wedge"; rc=$?
    printf 'rc=%s|status=%s|events=%s\n' "$rc" "$_STATUS" "$(tr '\n' ',' < "$EV")"
  )
}
title_banner "Hard-stop mask + delayed re-verify (v0.6.9 H2)"

# ── (M-a) stop fails → mask BEFORE kill; ✅ page says masked + unmask command ─────────────────
echo ""; echo "─── (M-a) systemctl stop fails → mask --runtime BEFORE the kill; masked ✅ page ───"
out=$(scenario "$PRIMARY" 124 0 0 1)
ev=$(field "$out" events)
if [[ "$(field "$out" rc)" == "0" && "$ev" == "STOP,MASK,KILL,"* \
      && "$out" == *"unit masked"* ]]; then
    ok "(M-a) order STOP→MASK→KILL and the ✅ page names the mask (events=$ev)"
else
    bad "(M-a) wrong: $out"
fi
# the page must name the exact unmask command (recovery step)
out2=$(scenario "$PRIMARY" 124 0 0 1)
[[ "$(field "$out2" status)" == *"unit masked"* ]] \
    && ok "(M-a2) status label carries the masked marker (PRIMARY SELF-FENCE — HARD STOP ✅ (unit masked))" \
    || bad "(M-a2) masked marker missing: $out2"

# ── (M-b) resurrect during re-verify → FAILED (immediate verify alone would have passed) ─────
echo ""; echo "─── (M-b) process resurrects within the re-verify window → HARD STOP FAILED, rc 1 ───"
out=$(scenario "$PRIMARY" 124 1 1 1)
if [[ "$(field "$out" rc)" == "1" && "$(field "$out" status)" == *"HARD STOP FAILED"* ]]; then
    ok "(M-b) resurrect caught by the delayed re-verify → FAILED page, rc 1"
else
    bad "(M-b) wrong: $out"
fi

# ── (M-c) mask fails → the kill still proceeds ────────────────────────────────────────────────
echo ""; echo "─── (M-c) mask fails (systemd wedged) → kill path NOT skipped ───"
out=$(scenario "$PRIMARY" 124 1 0 1)
ev=$(field "$out" events)
if [[ "$ev" == *"MASK"* && "$ev" == *"KILL"* && "$(field "$out" rc)" == "0" && "$(field "$out" status)" != *"unit masked"* ]]; then
    ok "(M-c) mask attempted+failed, kill proceeded, success WITHOUT the masked wording (events=$ev)"
else
    bad "(M-c) wrong: $out"
fi

# ── (M-d) clean stop → no mask attempted ──────────────────────────────────────────────────────
echo ""; echo "─── (M-d) systemctl stop succeeds → NO mask; plain ✅ ───"
out=$(scenario "$PRIMARY" 0 0 0 1)
ev=$(field "$out" events)
if [[ "$ev" != *"MASK"* && "$(field "$out" rc)" == "0" && "$(field "$out" status)" == *"HARD STOP ✅"* && "$(field "$out" status)" != *"masked"* ]]; then
    ok "(M-d) clean stop → mask never attempted, plain confirmed-down ✅ (events=$ev)"
else
    bad "(M-d) wrong: $out"
fi

# ── (M-e) NON-VACUOUS CONTROL: strip mask+re-verify → the old false-✅ returns ────────────────
echo ""; echo "─── (M-e) control: awk-strip the H2 blocks → same resurrect inputs report false ✅ ───"
PATCHED=$(mktemp)
mutate_filter "$PRIMARY" "$PATCHED" awk '
  /# v0\.6\.9 \(H2\): systemctl stop did NOT cleanly succeed/ {skip=1}
  /# v0\.6\.9 \(H2\): RE-verify after a Restart=always-scale delay/ {skip=1}
  skip && /^    fi$/ {skip=0; next}
  !skip {print}
'
out=$(scenario "$PATCHED" 124 1 1 1)
rm -f "$PATCHED"
if [[ "$(field "$out" rc)" == "0" && "$(field "$out" status)" == *"HARD STOP ✅"* ]]; then
    ok "(M-e) patched (pre-H2) copy reported ✅ on the resurrect inputs → M-b is non-vacuous"
else
    bad "(M-e) control did not revert to the old behavior: $out"
fi

# ── (M-f) the H1 standby port behaves identically ─────────────────────────────────────────────
echo ""; echo "─── (M-f) standby port parity: resurrect → FAILED; stop-fail → masked ✅ ───"
out=$(scenario "$STANDBY" 124 1 1 1)
outm=$(scenario "$STANDBY" 124 0 0 1)
if [[ "$(field "$out" rc)" == "1" && "$(field "$out" status)" == *"STANDBY SELF-FENCE — HARD STOP FAILED"* \
      && "$(field "$outm" rc)" == "0" && "$(field "$outm" status)" == *"unit masked"* ]]; then
    ok "(M-f) standby _selffence_hard_stop port: resurrect FAILED + masked ✅ both correct"
else
    bad "(M-f) standby port diverges: resurrect='$out' masked='$outm'"
fi

results_banner
