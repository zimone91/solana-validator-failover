#!/bin/bash
# v0.6.9 (M8): TIER2/TIER3 vantage-independence. Identical URLs silently void A6 ("two vantages") and
# the liveness fence's fallback independence — nothing compared them before. Drives the REAL shipped
# startup seam (extracted from startup_checks) and the REAL peer_has_relinquished.
#   (V-a) equal tiers → warn + alert_warn on BOTH daemons (normalized: trailing '/' trimmed)
#   (V-b) standby + WITNESS_FASTPATH=true + ALL A-knobs set → fast-path forced DISABLED (fail-closed):
#         the seam sets _fastpath_disabled AND the real peer_has_relinquished then refuses a
#         fully-corroborated flip
#   (V-c) CONTROL (same inputs, distinct tiers): no warn, _fastpath_disabled stays empty → ARMED
#         (peer_has_relinquished fires on the same corroborated flip) — proves V-b bites
#   (V-d) one tier empty → no warn (single-provider users keep working, loudly elsewhere)

# harness: tests/lib/harness.sh — ok/bad+banners, paths, field, extract_region (the M8 seam: the
# sed range is byte-faithful to the old awk-with-exit — verified — and cannot silently source empty).
# run_seam's cut + capture shims stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# Run the shipped M8 seam (marker comment → its closing 4-space fi) with the given tiers.
# For the standby, then run the REAL peer_has_relinquished against a fully-passing flip.
#   $1=script $2=T2 $3=T3 $4=fastpath(true/false)
run_seam() {
  local script="$1" t2="$2" t3="$3" fp="$4"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
    TIER2_RPC="$t2"; TIER3_RPC="$t3"; TG_ENABLED=false
    WITNESS_FASTPATH="$fp"; PRIMARY_UNSTAKED_PUBKEY="PeerUnstaked11111111111111111111111111111"
    FASTPATH_PEER_RECOVERY_MANUAL=true; FASTPATH_CONFIRM_SAMPLES=1; FASTPATH_STAGGER_SECS=0
    STANDBY_TAKEOVER_DELAY=60; TAKEOVER_DELAY=60; WITNESS_FASTPATH_FIRST_SPARE=true
    _fastpath_disabled=""; _fastpath_absent_seen=1; _fastpath_confirm=0
    log_info(){ :; }; log_error(){ :; }
    W=0; log_warn(){ [[ "$*" == *"single vantage"* ]] && W=$((W+1)); }
    AW=0; alert_warn(){ [[ "$*" == *"single vantage"* ]] && AW=$((AW+1)); }
    # arm the stagger exactly like startup does (so V-c's ARMED path is genuine)
    [[ "$fp" == "true" ]] && _fastpath_compute_stagger >/dev/null 2>&1
    # extract + run the shipped M8 block (marker → first closing 4-space fi)
    SEAM=$(mktemp)
    extract_region "$script" '# v0\.6\.9 (M8): TIER2\/TIER3 vantage-independence' '^    fi$' > "$SEAM" || { echo "seam-empty"; exit 1; }
    # shellcheck disable=SC1090
    source "$SEAM"; rm -f "$SEAM"
    fired=-1
    if [[ "$script" == *standby* && "$fp" == "true" ]]; then
        # REAL peer_has_relinquished with a fully-corroborated flip on BOTH vantages
        curl(){ local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
                [[ "$d" == *getClusterNodes* ]] || return 7
                printf '{"result":[{"pubkey":"S1","gossip":"5.5.5.5:8001"},{"pubkey":"PeerUnstaked11111111111111111111111111111","gossip":"5.5.5.5:8001"}]}'
                return 0; }
        peer_has_relinquished >/dev/null 2>&1; fired=$?
    fi
    printf 'warn=%s|alertwarn=%s|disabled=%s|fired=%s\n' "$W" "$AW" "${_fastpath_disabled:-NONE}" "$fired"
  )
}
title_banner "TIER2/TIER3 vantage-independence (v0.6.9 M8)"

echo ""; echo "─── (V-a) equal tiers (incl. trailing-slash) → warn on both daemons ───"
out=$(run_seam "$PRIMARY" "https://rpc.example.com/v1" "https://rpc.example.com/v1/" false)
[[ "$(field "$out" warn)" -ge 1 && "$(field "$out" alertwarn)" -ge 1 ]] \
    && ok "(V-a1) PRIMARY warns + alert_warns on normalized-equal tiers ($out)" \
    || bad "(V-a1) primary did not warn ($out)"
out=$(run_seam "$STANDBY" "https://rpc.example.com" "https://rpc.example.com/" false)
[[ "$(field "$out" warn)" -ge 1 ]] \
    && ok "(V-a2) STANDBY warns on normalized-equal tiers ($out)" \
    || bad "(V-a2) standby did not warn ($out)"

echo ""; echo "─── (V-b) standby: equal tiers + full A-config → fast-path DISABLED (fail-closed) ───"
out=$(run_seam "$STANDBY" "https://rpc.example.com" "https://rpc.example.com" true)
if [[ "$(field "$out" disabled)" != "NONE" && "$(field "$out" fired)" == "1" ]]; then
    ok "(V-b) _fastpath_disabled set AND the real peer_has_relinquished refused a fully-corroborated flip ($out)"
else
    bad "(V-b) fast-path not fail-closed ($out)"
fi

echo ""; echo "─── (V-c) CONTROL: distinct tiers, same everything else → ARMED (fires) ───"
out=$(run_seam "$STANDBY" "http://mock-t2" "http://mock-t3" true)
if [[ "$(field "$out" warn)" == "0" && "$(field "$out" disabled)" == "NONE" && "$(field "$out" fired)" == "0" ]]; then
    ok "(V-c) distinct tiers: no warn, fast-path ARMED, the same flip FIRES → V-b is non-vacuous ($out)"
else
    bad "(V-c) control wrong ($out)"
fi

echo ""; echo "─── (V-d) one tier empty → no warn ───"
out=$(run_seam "$PRIMARY" "" "https://api.mainnet-beta.solana.com" false)
[[ "$(field "$out" warn)" == "0" ]] \
    && ok "(V-d) empty TIER2 → the comparison is skipped (single-provider setups unchanged)" \
    || bad "(V-d) warned on an empty tier ($out)"

results_banner
