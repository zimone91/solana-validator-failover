#!/bin/bash
# Unknown-identity must PAGE, not WARN. Confirmed in production 2026-08-10 23:20 (mainnet standby):
# during a manual failback the validator briefly ran on a different unstaked key; the daemon's
# "Unknown identity" state disables the ENTIRE protection stack (no takeover, no self-fence, no
# collision detector) and reported it only as a throttle-buried log_warn — the spare sat dark during
# the exact operation where it mattered most. This suite drives the SHIPPED main-loop seams (sed-
# extracted by their comment anchors, the installer-guardrails idiom) and asserts:
#   (1) entering Unknown → an immediate 🚨 critical alert (not a warn);
#   (2) persisting within ALERT_THROTTLE → no page spam (log only);
#   (3) persisting past ALERT_THROTTLE → re-page;
#   (4) identity classifying again → recovery notice + episode reset.
# Non-vacuous: revert the branch to the old `log_warn "Unknown identity: …"` one-liner → the seam
# anchor vanishes → (0) fails; the alert counts also collapse.

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDBY="$DIR/solana-standby-failover.sh"
[[ -f "$STANDBY" ]] || { echo "  ❌ missing $STANDBY"; exit 1; }

echo "============================================="
echo "  Unknown-identity critical paging"
echo "============================================="
echo ""

# ── Extract the two shipped seams by their comment anchors ──
UNK_SEAM=$(mktemp); REC_SEAM=$(mktemp)
sed -n '/# An identity that is neither/,/display_status "UNKNOWN"/p' "$STANDBY" > "$UNK_SEAM"
sed -n '/# Recovery from an UNKNOWN-identity episode/,/^    fi$/p' "$STANDBY" > "$REC_SEAM"

if [[ -s "$UNK_SEAM" ]] && grep -q 'alert ' "$UNK_SEAM"; then
  ok "(0) unknown-identity seam present and carries a critical alert call"
else
  bad "(0) seam missing or alert-less — branch reverted to the silent log_warn?"
  echo "  RESULTS: $PASS passed, $FAIL failed"; rm -f "$UNK_SEAM" "$REC_SEAM"; exit 1
fi

# ── Harness: mock time + sinks, drive the seam like the main loop would ──
_SIM_NOW=1000000
date() { [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
ALERTS=0; LAST_ALERT_REASON=""; LAST_ALERT_STATUS=""
alert() { ALERTS=$((ALERTS+1)); LAST_ALERT_REASON="$1"; LAST_ALERT_STATUS="$3"; }
INFOS=0; alert_info() { INFOS=$((INFOS+1)); }
WARNS=0; log_warn() { WARNS=$((WARNS+1)); }
display_status() { :; }
ALERT_THROTTLE=600
CURRENT_IDENTITY="2MXepp63arq2AZmCv2dKSmB4ytZTJPyrKgt8HSKRUDES"
UNSTAKED_PUBKEY="UnstakedPubkey11111111111111111111111111111"
STAKED_PUBKEY="StakedPubkey1111111111111111111111111111111"
_unknown_identity_since=0; _last_unknown_alert=0

# (1) entry → immediate critical page
# shellcheck disable=SC1090
source "$UNK_SEAM"
if [[ $ALERTS -eq 1 && "$LAST_ALERT_STATUS" == *"PROTECTION OFFLINE"* && $_unknown_identity_since -eq $_SIM_NOW ]]; then
  ok "(1) entering Unknown pages immediately (status '$LAST_ALERT_STATUS')"
else
  bad "(1) entry not paged (alerts=$ALERTS status='$LAST_ALERT_STATUS' since=$_unknown_identity_since)"
fi

# (2) persists 30s later → no page spam, log only
_SIM_NOW=$(( _SIM_NOW + 30 ))
source "$UNK_SEAM"
[[ $ALERTS -eq 1 && $WARNS -ge 1 ]] \
  && ok "(2) within throttle: no re-page (alerts still $ALERTS), warn logged" \
  || bad "(2) throttle broken (alerts=$ALERTS warns=$WARNS)"

# (3) persists past ALERT_THROTTLE → re-page with duration
_SIM_NOW=$(( _SIM_NOW + 601 ))
source "$UNK_SEAM"
[[ $ALERTS -eq 2 && "$LAST_ALERT_REASON" == *"persists"* ]] \
  && ok "(3) past throttle: re-paged with persistence note" \
  || bad "(3) re-page missing (alerts=$ALERTS reason='$LAST_ALERT_REASON')"

# (4) identity classifies again → recovery notice + reset (drive the recovery seam)
CURRENT_IDENTITY="$UNSTAKED_PUBKEY"
# shellcheck disable=SC1090
source "$REC_SEAM"
[[ $INFOS -eq 1 && $_unknown_identity_since -eq 0 && $_last_unknown_alert -eq 0 ]] \
  && ok "(4) recovery: info notice sent, episode reset" \
  || bad "(4) recovery wrong (infos=$INFOS since=$_unknown_identity_since last=$_last_unknown_alert)"

# (4b) recovery seam is a no-op when there was no episode
INFOS=0
source "$REC_SEAM"
[[ $INFOS -eq 0 ]] \
  && ok "(4b) no episode → recovery seam silent" \
  || bad "(4b) spurious recovery notice (infos=$INFOS)"

rm -f "$UNK_SEAM" "$REC_SEAM"
unset -f date

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
