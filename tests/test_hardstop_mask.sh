#!/bin/bash
# v0.6.9 (H2): the hard-stop must survive Restart=always. When `systemctl stop` fails and the PID is
# killed directly, systemd restarts the validator after RestartSec - AFTER the old immediate verify
# passed - and it resurrects VOTING STAKED. The v0.6.9 fix was (a) `mask --runtime` before the kill and
# (b) a RE-verify of the down-state after HARD_STOP_REVERIFY_SECS.
# v0.7 rc1 F18: (a) is GONE. `mask --runtime` writes its /dev/null link under /run/systemd/system, and a
# unit file under /etc/systemd/system (where a validator's unit lives) takes precedence over it
# (systemd.unit(5), load path): measured on systemd 255, the masked unit stayed `loaded` with
# Restart=always and the validator was restarted 1.1 s after the SIGKILL. What protects a direct kill
# from Restart= is a REQUESTED STOP (the blocking `systemctl stop` of the ladder; `--no-block` on the
# primary's fast branch - tests/test_primary_gap_demote.sh (22)); (b) stays as the catch.
# The suite keeps its v0.6.9 name: it is the same suite (the manifest and the README count it), now pinning the absence.
# Drives the REAL _selffence_hard_stop (primary AND the H1 standby port) with mocks only at the I/O boundary
# (timeout, pgrep, kill, sleep).
#   (M-a) stop fails -> NO mask is attempted, the kill path runs (STOP, KILL); ONE success page whose text says
#         `systemctl start <unit>` and never mentions a mask
#   (M-b) resurrect during the re-verify window -> HARD STOP FAILED page (rc 1), even though the immediate verify
#         had passed; the page says `systemctl stop <unit>` (no mask)
#   (M-c) the stop request fails outright (rc 1: systemd unreachable) -> the kill still proceeds (never skipped),
#         the re-verify still guards
#   (M-d) clean stop (rc 0) -> NO mask attempted; the same plain success page
#   (M-e) NON-VACUOUS CONTROL: awk-strip the re-verify block from a patched copy -> the same resurrect inputs
#         return the OLD false-success (rc 0) - proves M-b bites
#   (M-f) standby port parity: resurrect fails loudly on the standby copy too; a failed stop ends in the same
#         single success page (title without '(unit masked)'), no mask event
#   (M-g) no input - stop rc 0 / 1 / 124, resurrect or not, process alive or not - makes EITHER ladder call
#         `systemctl mask`; the control that puts the call back turns it red
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, field, mutate_filter (the M-e awk-strip
# control cannot silently no-op). scenario()'s cut + sink/mocks stay local (capture subset).

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# Run _selffence_hard_stop from the given script copy in a fresh subshell.
#   $1=script  $2=RC_STOP  $3=resurrect(1/0)  $4=proc_alive_at_start(1/0)
# Echoes: rc=<rc>|status=<last alert status>|events=<ordered STOP,MASK,KILL...>|msg=<the last alert's text>
scenario() {
  local script="$1" rc_stop="$2" resurrect="$3" alive="$4"
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
    _STATUS=""; _MSG=""; alert(){ _MSG="$1"; _STATUS="$3"; }
    EV=$(mktemp); trap 'rm -f "$EV"' EXIT
    _PROC="$alive"; _RESURRECT="$resurrect"; _RC_STOP="$rc_stop"
    timeout(){
        case "$*" in
            *systemctl\ stop*) echo STOP >> "$EV"; return "$_RC_STOP" ;;
            *systemctl\ mask*) echo MASK >> "$EV"; return 0 ;;
        esac
        return 0
    }
    pgrep(){ [[ "$_PROC" == "1" ]] && echo 4242; return 0; }
    [[ -n "${SC_EXITWAIT:-}" ]] && HARD_STOP_EXIT_WAIT_SECS="$SC_EXITWAIT"   # rc1 F19: unset = the daemon's own default (15)
    # SC_TERM_IGNORED=1: SIGTERM does nothing (events TERM), only SIGKILL ends the process (events KILL9); SC_LAG=n: the pid stays visible for n more polls after the SIGKILL (rc1 F19)
    kill(){ if [[ "${SC_TERM_IGNORED:-0}" == "1" ]]; then if [[ "$1" == "-9" ]]; then echo KILL9 >> "$EV"; _PROC=0; echo "${SC_LAG:-0}" > "$EV.lag"; else echo TERM >> "$EV"; fi; return 0; fi; echo KILL >> "$EV"; _PROC=0; return 0; }
    pgrep(){ local n; if [[ -s "$EV.lag" ]]; then n=$(cat "$EV.lag"); if [[ $n -gt 0 ]]; then echo $((n - 1)) > "$EV.lag"; echo 4242; return 0; fi; fi; [[ "$_PROC" == "1" ]] && echo 4242; return 0; }
    sleep(){ echo "SLEEP $1" >> "$EV.all"; [[ "$1" == "$HARD_STOP_REVERIFY_SECS" && "$_RESURRECT" == "1" ]] && _PROC=1; :; }
    _selffence_hard_stop "test wedge"; rc=$?
    if [[ "${SC_OUT:-}" == "polls" ]]; then
        grep -c '^SLEEP 1$' "$EV.all" 2>/dev/null
    else
        printf 'rc=%s|status=%s|events=%s|msg=%s\n' "$rc" "$_STATUS" "$(tr '\n' ',' < "$EV")" "$_MSG"
    fi
    rm -f "$EV.all" "$EV.lag"
  )
}
title_banner "Hard-stop without a mask + delayed re-verify (v0.6.9 H2, v0.7 rc1 F18)"

# ── (M-a) stop fails -> no mask; the kill runs; one success page: 'systemctl start', no mask ───
echo ""; echo "─── (M-a) systemctl stop fails -> NO mask, the kill path runs; one success page that names 'systemctl start' ───"
out=$(scenario "$PRIMARY" 124 0 1)
ev=$(field "$out" events)
if [[ "$(field "$out" rc)" == "0" && "$ev" == "STOP,KILL," && "$(field "$out" status)" == "PRIMARY SELF-FENCE — HARD STOP ✅" \
      && "$(field "$out" msg)" == *"recover with 'systemctl start solana' on the UNSTAKED identity"* && -z "$(printf '%s' "$out" | grep -i 'mask')" ]]; then
    ok "(M-a) order STOP -> KILL, no MASK; the ✅ title is plain and the page names 'systemctl start solana' (events=$ev)"
else
    bad "(M-a) wrong: $out"
fi
# the same one page when the stop worked: no variant
out2=$(scenario "$PRIMARY" 0 0 1)
[[ "$(field "$out2" msg)" == "$(field "$out" msg)" && "$(field "$out2" status)" == "$(field "$out" status)" ]] \
    && ok "(M-a2) the page is the same text whether the stop worked or failed (no '(unit masked)' variant)" \
    || bad "(M-a2) two different success pages: failed-stop=[$(field "$out" msg)] clean-stop=[$(field "$out2" msg)]"

# ── (M-b) resurrect during re-verify -> FAILED (immediate verify alone would have passed) ─────
echo ""; echo "─── (M-b) process resurrects within the re-verify window -> HARD STOP FAILED, rc 1; the page says 'systemctl stop' ───"
out=$(scenario "$PRIMARY" 124 1 1)
if [[ "$(field "$out" rc)" == "1" && "$(field "$out" status)" == *"HARD STOP FAILED"* && "$(field "$out" msg)" == *"INTERVENE NOW (systemctl stop solana)."* && -z "$(printf '%s' "$out" | grep -i 'mask')" ]]; then
    ok "(M-b) resurrect caught by the delayed re-verify -> FAILED page, rc 1, 'INTERVENE NOW (systemctl stop solana).'"
else
    bad "(M-b) wrong: $out"
fi

# ── (M-c) the stop request fails outright -> the kill still proceeds ───────────────────────────
echo ""; echo "─── (M-c) systemctl stop fails outright (rc 1: systemd unreachable) -> kill path NOT skipped ───"
out=$(scenario "$PRIMARY" 1 0 1)
ev=$(field "$out" events)
if [[ "$ev" == "STOP,KILL," && "$(field "$out" rc)" == "0" && "$(field "$out" status)" == "PRIMARY SELF-FENCE — HARD STOP ✅" ]]; then
    ok "(M-c) the failed stop request did not skip the kill: STOP -> KILL, success page (events=$ev)"
else
    bad "(M-c) wrong: $out"
fi

# ── (M-d) clean stop -> no mask attempted ─────────────────────────────────────────────────────
echo ""; echo "─── (M-d) systemctl stop succeeds -> NO mask; plain ✅ ───"
out=$(scenario "$PRIMARY" 0 0 1)
ev=$(field "$out" events)
if [[ "$ev" != *"MASK"* && "$(field "$out" rc)" == "0" && "$(field "$out" status)" == *"HARD STOP ✅"* && "$(field "$out" status)" != *"masked"* ]]; then
    ok "(M-d) clean stop -> mask never attempted, plain confirmed-down ✅ (events=$ev)"
else
    bad "(M-d) wrong: $out"
fi

# ── (M-e) NON-VACUOUS CONTROL: strip the re-verify -> the old false-success returns ────────────
echo ""; echo "─── (M-e) control: awk-strip the H2 re-verify block -> same resurrect inputs report a false ✅ ───"
PATCHED=$(mktemp)
mutate_filter "$PRIMARY" "$PATCHED" awk '
  /# v0\.6\.9 \(H2\): RE-verify after a Restart=always-scale delay/ {skip=1}
  skip && /^    fi$/ {skip=0; next}
  !skip {print}
'
out=$(scenario "$PATCHED" 124 1 1)
rm -f "$PATCHED"
if [[ "$(field "$out" rc)" == "0" && "$(field "$out" status)" == *"HARD STOP ✅"* ]]; then
    ok "(M-e) patched (no re-verify) copy reported ✅ on the resurrect inputs -> M-b is non-vacuous"
else
    bad "(M-e) control did not revert to the old behavior: $out"
fi

# ── (M-f) the H1 standby port behaves the same ────────────────────────────────────────────────
echo ""; echo "─── (M-f) standby port parity: resurrect -> FAILED; stop fails -> the same single ✅ page, no mask ───"
out=$(scenario "$STANDBY" 124 1 1)
outm=$(scenario "$STANDBY" 124 0 1)
outc=$(scenario "$STANDBY" 0 0 1)
if [[ "$(field "$out" rc)" == "1" && "$(field "$out" status)" == *"STANDBY SELF-FENCE — HARD STOP FAILED"* && "$(field "$out" msg)" == *"INTERVENE NOW (systemctl stop solana)."* \
      && "$(field "$outm" rc)" == "0" && "$(field "$outm" status)" == "STANDBY SELF-FENCE — HARD STOP ✅" && "$(field "$outm" events)" == "STOP,KILL," \
      && "$(field "$outm" msg)" == *"recover with 'systemctl start solana' on the UNSTAKED identity"* && "$(field "$outm" msg)" == "$(field "$outc" msg)" \
      && -z "$(printf '%s\n%s\n%s' "$out" "$outm" "$outc" | grep -i 'mask')" ]]; then
    ok "(M-f) standby _selffence_hard_stop port: resurrect FAILED ('systemctl stop'), a failed and a clean stop end in the same single ✅ page ('systemctl start'), no mask anywhere"
else
    bad "(M-f) standby port diverges: resurrect='$out' failed-stop='$outm' clean-stop='$outc'"
fi

# ── (M-g) no input makes either ladder call `systemctl mask`; the control puts the call back ──
echo ""; echo "─── (M-g) neither ladder ever calls systemctl mask, whatever the inputs; control: the call put back is caught ───"
mask_seen() {   # mask_seen <script> -> the number of scenarios (of 12) in which a MASK event was recorded
    local script="$1" n=0 rs res al o
    for rs in 0 1 124; do for res in 0 1; do for al in 0 1; do
        o=$(scenario "$script" "$rs" "$res" "$al"); [[ "$(field "$o" events)" == *MASK* ]] && n=$((n + 1))
    done; done; done
    printf '%s' "$n"
}
PM=$(mktemp); SM=$(mktemp)
MASK_BACK='s/^    # Fallback (non-systemd \/ stuck unit): SIGTERM the validator PID, then SIGKILL if it ignores it\.$/    [[ $sc_rc -ne 0 ]] \&\& timeout -k 5 15 systemctl mask --runtime "${VALIDATOR_SERVICE:-solana}"/'
if mutate "$PRIMARY" "$MASK_BACK" "$PM" && mutate "$STANDBY" "$MASK_BACK" "$SM"; then
    p0=$(mask_seen "$PRIMARY"); s0=$(mask_seen "$STANDBY"); p1=$(mask_seen "$PM"); s1=$(mask_seen "$SM")
    if [[ "$p0" == "0" && "$s0" == "0" && "$p1" -gt 0 && "$s1" -gt 0 ]]; then
        ok "(M-g) 12 input combinations x 2 ladders: no MASK event from the shipped ladders (primary $p0, standby $s0); the control that puts 'systemctl mask --runtime' back after a failed stop is seen (primary $p1, standby $s1 of 12)"
    else
        bad "(M-g) mask events: shipped primary=$p0 standby=$s0; control primary=$p1 standby=$s1 (want 0 0, >0 >0)"
    fi
else
    bad "(M-g) the control's sed did not apply to a daemon (mutate reported it)"
fi
rm -f "$PM" "$SM"


# ── (M-h) rc1 F19: the exit wait - after the SIGKILL the ladder polls once per second, up to HARD_STOP_EXIT_WAIT_SECS (15) - in BOTH ladders ─────────────────────────
echo ""; echo "─── (M-h) the killed process is gone only at the 4th poll -> confirmed (rc 0); alive at the bound -> HARD STOP FAILED; the standby ladder too ───"
polls() { SC_OUT=polls "$@"; }
h_ok=1; h_why=""
for sc in "$PRIMARY" "$STANDBY"; do
    nm=$(basename "$sc")
    late=$(SC_TERM_IGNORED=1 SC_LAG=3 scenario "$sc" 124 0 1); lp=$(SC_TERM_IGNORED=1 SC_LAG=3 polls scenario "$sc" 124 0 1)
    dead=$(SC_TERM_IGNORED=1 SC_LAG=99 scenario "$sc" 124 0 1); dp=$(SC_TERM_IGNORED=1 SC_LAG=99 polls scenario "$sc" 124 0 1)
    four=$(SC_TERM_IGNORED=1 SC_LAG=99 SC_EXITWAIT=4 polls scenario "$sc" 124 0 1)
    if [[ "$(field "$late" rc)" != "0" || "$(field "$late" status)" != *"HARD STOP ✅" || "$lp" != "4" || "$(field "$late" events)" != "STOP,TERM,KILL9," \
          || "$(field "$dead" rc)" != "1" || "$(field "$dead" status)" != *"HARD STOP FAILED"* || "$dp" != "15" || "$(field "$dead" msg)" != *"still running (pid 4242) 15s after SIGKILL"* || "$four" != "4" ]]; then
        h_ok=0; h_why="$h_why [$nm: late=($late) polls=$lp dead=($dead) polls=$dp four=$four]"
    fi
done
if [[ $h_ok -eq 1 ]]; then
    ok "(M-h) both ladders: the pid visible for 3 polls after the SIGKILL and gone at the 4th -> rc 0 and the ✅ page (4 polls); alive at the bound -> rc 1, HARD STOP FAILED ('still running (pid 4242) 15s after SIGKILL'), 15 polls; HARD_STOP_EXIT_WAIT_SECS=4 -> 4 polls"
else
    bad "(M-h) exit wait:$h_why"
fi
# (M-i) CONTROL: the old single read 1 s after the kill (the loop cut to one poll) turns (M-h) red in both ladders
PM=$(mktemp); SM=$(mktemp)
ONE_POLL='s/^            \[\[ -z "\$pid" || \$_hs_i -ge \$_hs_w \]\] && break$/            break/'
if mutate "$PRIMARY" "$ONE_POLL" "$PM" && mutate "$STANDBY" "$ONE_POLL" "$SM"; then
    pl=$(SC_TERM_IGNORED=1 SC_LAG=3 scenario "$PM" 124 0 1); sl=$(SC_TERM_IGNORED=1 SC_LAG=3 scenario "$SM" 124 0 1)
    if [[ "$(field "$pl" rc)" == "1" && "$(field "$pl" status)" == *"HARD STOP FAILED"* && "$(field "$sl" rc)" == "1" && "$(field "$sl" status)" == *"HARD STOP FAILED"* ]]; then
        ok "(M-i) control: a ladder that reads once, 1 s after the SIGKILL (the old verify), calls the 3-polls-late process FAILED in both daemons - (M-h) bites"
    else
        bad "(M-i) control did not revert to the old verify: primary=($pl) standby=($sl)"
    fi
else
    bad "(M-i) the control's sed did not apply to a daemon (mutate reported it)"
fi
rm -f "$PM" "$SM"

results_banner
