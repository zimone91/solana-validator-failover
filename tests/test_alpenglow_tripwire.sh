#!/bin/bash
# v0.7 (AG-1.1): ALPENGLOW FEATURE-GATE TRIPWIRE — the right id, the real shape, a REPORT ONLY.
# History: pre-Block-4 №9 built it against agave 4.2.1 (a1penGLz8Vm2QHYB3JPefBiU4BY3Z6JkW2k3Scw5GWP, a `jsonParsed`
# parse, pages "re-run the 4.2 audit"); on 2026-11-01 the account the id names did not exist on any cluster, the real
# id A1pengvuM6JEcyNuTnMqepBKhwHE3N6PmUrdATGawhJS (agave v4.4.0 and jito v4.4.0-jito feature-set/src/lib.rs:1286)
# answers base64 even under jsonParsed, and every public cluster read `active` (DESIGN-AG §1.2). AG-1.1:
#   - the fetch asks `encoding: base64` for the real id and classifies the answer: active (owner Feature111…, tag 1 +
#     the activation slot, u64 little-endian), pending (tag 0), absent (`value: null`); anything else — wrong owner,
#     short data, tag > 1, a JSON-RPC error, non-JSON — tries the next tier, both unusable = unknown (rc 1);
#   - the tripwire only REPORTS: the first determination `active` is a log line and a status line, no page; pending,
#     absent or a change away from active pages once per process run ("the configured RPC may not serve the cluster
#     this node validates; AG mode stays on"); the BLIND page after 4 failed probes stays;
#   - AG mode (`_ag_mode`, the [ag] block) is NOT decided by the tripwire: it returns 0 unconditionally.
# Harness: source-to-`# MAIN LOOP` seam of the standby (and the primary for byte-parity + a behavior spot check),
# mono/date shims. Two layers: (A) the REAL `_alpenglow_gate_fetch` over a shadowed `curl` (the fixtures, incl. the
# live answers of 2026-11-01), (B) the REAL `_alpenglow_gate_check` over a shadowed fetch seam (the state machine).
# Cases:
#   (1)  first determination active: no page, a log line, persisted, the status line
#   (2)  pending: ONE page (names the state, the tier, "may not serve", "AG mode stays on"), persisted
#   (3)  absent: ONE page
#   (4)  active → absent: ONE page; one page per RUN however many non-active readings follow
#   (5)  active stable: silent; a later change INTO active is silent
#   (6)  unknown (fetch rc 1): zero pages while streak < 4, WARN logs, state unchanged, no save
#   (7)  knob 0: zero fetches; drift wordings
#   (8)  fresh-boot first check immediate; cadence
#   (9)  byte-identity of the whole tripwire + [ag] region across the daemons; primary behavior spot check
#  (10)  revert-control; (11) wiring (main loop, startup line, heartbeat status line)
#  (12)  blind streak; (13) retry floor
#  (14)  the tripwire sends NO critical page, whatever it reads
#  (15)  the companion gate is named with its 4.4.0 reason
#  (16)  FETCH FIXTURES through the real fetch: the live mainnet / testnet / devnet answers, absent, pending, tag 2,
#        short data, wrong owner (falls to the next tier), errors, non-JSON, jsonParsed shape, trailing bytes, a slot with
#        high bytes; the request asks base64 for the real id (RED on the 6ce2d93/fd4ee8c base: the parsed.info check
#        fails on both tiers → rc 1, and `value: null` reads "inactive")
#  (17)  end to end: the live mainnet answer → the real check → active, no page, persisted
#  (18)  `_ag_mode`: unconditional (hostile environment, bash's parse of the body), and its mutant control
#  (19)  CONTROLS for the fetch (mutate()): big-endian slot, a wrong '/' sextet, no owner check, tag >= 1 as active,
#        value:null not absent, tag 0 not pending, a jsonParsed request — each misreads the fixture that guards it

# harness: tests/lib/harness.sh — ok/bad+banners, paths, field, harness_clock_shims, drift_out, mutate, extract_twin.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# ── (B) harness: drive the REAL _alpenglow_gate_check over a scripted fetch sequence + timeline ──
#   $1=script  $2=ALPENGLOW_GATE_CHECK_HOURS  $3=fetch sequence (space-separated words; "rc1" = return 1/unknown; a bare
#   state word active|pending|absent expands to the seam's line "<state> <slot> T2" — slot 459648000 for active, 0
#   otherwise; "state:slot:tier" is explicit; the Nth check consumes the Nth word, past-the-end = rc1)  $4=timeline
#   (space-separated mono instants; one _alpenglow_gate_check call each)  $5=1 → shadow _alpenglow_gate_check(){ :; }
#   AFTER sourcing (case 10)  $6=pre-seeded _alpenglow_gate_state
# Echoes: pages=N|blind=N|crit=N|warnlogs=N|fetches=N|state=S|saves=N|saved=<,-joined states at save>|paged=N|
#         text=<first page>|btext=<first blind page>|ctext=<first critical>|loginfo=<alpenglow info lines>|stat=<status line>
ap_run() {
  local script="$1" hours="$2" seq="$3" timeline="$4" shadow="${5:-0}" init="${6:-}"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    ALPENGLOW_GATE_CHECK_HOURS="$hours"
    [[ -n "$init" ]] && _alpenglow_gate_state="$init"
    _SEQ_STR="$seq"
    EVT=$(mktemp); export _AP_EVT="$EVT"
    trap 'rm -f "$EVT"' EXIT
    _SIM_NOW=0
    harness_clock_shims
    WARNLOGS=0; LOGI=""; STATL=""
    log(){ :; }; log_error(){ :; }
    log_info(){ case "$*" in *"[alpenglow] tripwire:"*) STATL="${*//|//}" ;; *"[alpenglow]"*) LOGI="${LOGI:+$LOGI ¦ }${*//|//}" ;; esac; }
    log_warn(){ case "$*" in *"[alpenglow]"*) WARNLOGS=$((WARNLOGS+1)) ;; esac; }
    PAGES=0; PTEXT=""; BLIND=0; BTEXT=""
    alert_warn(){
        case "$1" in
            *"TRIPWIRE BLIND"*) BLIND=$((BLIND+1)); [[ -z "$BTEXT" ]] && BTEXT="${1//$'\n'/ }" ;;
            *) PAGES=$((PAGES+1)); [[ -z "$PTEXT" ]] && PTEXT="${1//$'\n'/ }" ;;
        esac
        return 0
    }
    CRIT=0; CTEXT=""
    alert(){ CRIT=$((CRIT+1)); [[ -z "$CTEXT" ]] && CTEXT="${1//$'\n'/ } ${3:-}"; return 0; }
    alert_info(){ :; }; send_telegram(){ return 0; }; send_webhook(){ :; }
    SAVES=0; SAVED=""
    save_state(){ SAVES=$((SAVES+1)); SAVED="${SAVED:+$SAVED,}${_alpenglow_gate_state:-none}"; return 0; }
    # The daemon calls the fetch seam in a $() subshell → sequence via the shared event file
    # (the test_act_then_alert SAMPLE-counter idiom).
    _alpenglow_gate_fetch(){
        local n w
        n=$(( $(grep -c 'F' "$_AP_EVT" 2>/dev/null) + 1 ))
        echo "F" >> "$_AP_EVT"
        w=$(printf '%s\n' "$_SEQ_STR" | tr ' ' '\n' | sed -n "${n}p")
        [[ -z "$w" || "$w" == "rc1" ]] && return 1
        case "$w" in
            *:*:*) echo "${w%%:*} $(echo "$w" | cut -d: -f2) ${w##*:}" ;;
            active) echo "active 459648000 T2" ;;
            *) echo "$w 0 T2" ;;
        esac
        return 0
    }
    if [[ "$shadow" == "1" ]]; then _alpenglow_gate_check(){ :; }; fi
    local t
    for t in $timeline; do
        _SIM_NOW="$t"
        _alpenglow_gate_check
    done
    _alpenglow_status_line 2>/dev/null
    printf 'pages=%s|blind=%s|crit=%s|warnlogs=%s|fetches=%s|state=%s|saves=%s|saved=%s|paged=%s|text=%s|btext=%s|ctext=%s|loginfo=%s|stat=%s\n' \
        "$PAGES" "$BLIND" "$CRIT" "$WARNLOGS" "$(grep -c 'F' "$EVT" 2>/dev/null)" \
        "${_alpenglow_gate_state:-none}" "$SAVES" "${SAVED:-none}" "${_alpenglow_paged:-0}" "${PTEXT:0:240}" \
        "${BTEXT:0:140}" "${CTEXT:0:200}" "${LOGI:0:300}" "${STATL:0:240}"
  )
}

# ── (A) harness: the REAL _alpenglow_gate_fetch over a shadowed curl ──
#   fx_run <script> <answer-1> [<answer-2>] — call n of curl prints answer n ("RC7" = transport failure, rc 7, no output;
#   "EMPTY" = rc 0, no output). Echoes: rc=<fetch rc>|out=<its stdout>|calls=<curl calls>|req1=<first call: url + body>
fx_run() {
  local script="$1"; shift
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
    BF=$(mktemp); REQ=$(mktemp); EVTF=$(mktemp); trap 'rm -f "$BF" "$REQ" "$EVTF"' EXIT
    local b; for b in "$@"; do printf '%s\n' "$b" >> "$BF"; done
    _watchdog_pet(){ :; }
    curl(){
        local data="" url="" n body
        while [[ $# -gt 0 ]]; do case "$1" in -d) data="$2"; shift 2; continue ;; http*) url="$1" ;; esac; shift; done
        echo C >> "$EVTF"
        n=$(grep -c 'C' "$EVTF")
        printf '%s %s\n' "$url" "$data" >> "$REQ"
        body=$(sed -n "${n}p" "$BF")
        case "$body" in RC7) return 7 ;; EMPTY|"") return 0 ;; esac
        printf '%s\n' "$body"
        return 0
    }
    out=$(_alpenglow_gate_fetch); rc=$?
    printf 'rc=%s|out=%s|calls=%s|req1=%s\n' "$rc" "$out" "$(grep -c 'C' "$EVTF")" "$(head -1 "$REQ")"
  )
}
# fx_body <base64 data> [<owner>] — a getAccountInfo answer shaped exactly like the live ones of 2026-11-01
fx_body() {
    printf '{"jsonrpc":"2.0","result":{"context":{"apiVersion":"4.4.0","slot":459430646},"value":{"data":["%s","base64"],"executable":false,"lamports":695960,"owner":"%s","rentEpoch":18446744073709551615,"space":9}},"id":1}' \
        "$1" "${2:-Feature111111111111111111111111111111111111}"
}
# the live answers, byte for byte (public RPC, getAccountInfo{encoding: base64}, 2026-11-01; apiVersion as served)
LIVE_MAINNET='{"jsonrpc":"2.0","result":{"context":{"apiVersion":"4.3.2","slot":464237272},"value":{"data":["AQCsZRsAAAAA","base64"],"executable":false,"lamports":12932462,"owner":"Feature111111111111111111111111111111111111","rentEpoch":18446744073709551615,"space":9}},"id":1}'
LIVE_TESTNET='{"jsonrpc":"2.0","result":{"context":{"apiVersion":"4.4.0","slot":459430646},"value":{"data":["AeBdgBoAAAAA","base64"],"executable":false,"lamports":695960,"owner":"Feature111111111111111111111111111111111111","rentEpoch":18446744073709551615,"space":9}},"id":1}'
LIVE_DEVNET='{"jsonrpc":"2.0","result":{"context":{"apiVersion":"4.4.0-beta.1","slot":517624287},"value":{"data":["AYCgDB4AAAAA","base64"],"executable":false,"lamports":695960,"owner":"Feature111111111111111111111111111111111111","rentEpoch":18446744073709551615,"space":9}},"id":1}'
NULL_VALUE='{"jsonrpc":"2.0","result":{"context":{"apiVersion":"4.4.0","slot":459430646},"value":null},"id":1}'
RPC_ERROR='{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is unhealthy","data":{"numSlotsBehind":null}},"id":1}'
# synthetic payloads (bincode Option<u64>, 9 bytes unless stated)
B64_PENDING='AAAAAAAAAAAA'       # nine zero bytes: what the activation transaction allocates
B64_TAG2='AgCsZRsAAAAA'          # tag 2: not an Option<u64>
B64_SHORT4='AQCsZQ=='            # four bytes
B64_SHORT8='AQCsZRsAAAA='        # eight bytes
B64_TEN='AQCsZRsAAAAA/w=='            # tag 1 + the mainnet slot + one trailing byte (readers tolerate trailing bytes)
B64_FFFF='Af////8AAAAA'          # tag 1 + slot 4294967295: every high byte of the low word set
SYSTEM_PROGRAM='11111111111111111111111111111111'
ID_NEW='A1pengvuM6JEcyNuTnMqepBKhwHE3N6PmUrdATGawhJS'
ID_OLD='a1penGLz8Vm2QHYB3JPefBiU4BY3Z6JkW2k3Scw5GWP'

title_banner "Alpenglow feature-gate tripwire (v0.7 AG-1.1: report only)"

# ── (16) FETCH FIXTURES — RED on the base: the live mainnet answer reads unknown there (rc 1), value:null reads "inactive" ──
echo ""; echo "─── (16) the REAL fetch over the live answers and the synthetic shapes ───"
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(basename "$scr" | sed 's/solana-\(.*\)-failover.sh/\1/')
    out=$(fx_run "$scr" "$LIVE_MAINNET")
    [[ "$(field "$out" rc)" == "0" && "$(field "$out" out)" == "active 459648000 T2" && "$(field "$out" calls)" == "1" ]] \
        && ok "(16a:$n) the live MAINNET answer (tag 1, slot 459,648,000, owner Feature111…) → 'active 459648000 T2' from the first tier, one call" \
        || bad "(16a:$n) mainnet answer misread ($out)"
    out=$(fx_run "$scr" "$LIVE_TESTNET"); [[ "$(field "$out" out)" == "active 444620256 T2" ]] \
        && ok "(16b:$n) the live TESTNET answer → active 444620256" || bad "(16b:$n) testnet misread ($out)"
    out=$(fx_run "$scr" "$LIVE_DEVNET");  [[ "$(field "$out" out)" == "active 504144000 T2" ]] \
        && ok "(16b2:$n) the live DEVNET answer → active 504144000" || bad "(16b2:$n) devnet misread ($out)"
    out=$(fx_run "$scr" "$NULL_VALUE")
    [[ "$(field "$out" rc)" == "0" && "$(field "$out" out)" == "absent 0 T2" ]] \
        && ok "(16c:$n) value:null → 'absent 0 T2' (the base printed 'inactive')" \
        || bad "(16c:$n) value:null misread ($out)"
    out=$(fx_run "$scr" "$(fx_body "$B64_PENDING")")
    [[ "$(field "$out" out)" == "pending 0 T2" ]] \
        && ok "(16d:$n) tag 0 (nine zero bytes) → 'pending 0 T2'" || bad "(16d:$n) pending misread ($out)"
    out=$(fx_run "$scr" "$(fx_body "$B64_TEN")")
    [[ "$(field "$out" out)" == "active 459648000 T2" ]] \
        && ok "(16e:$n) ten bytes (tag 1 + slot + a trailing byte) → active: the readers tolerate trailing bytes" || bad "(16e:$n) ten bytes misread ($out)"
    out=$(fx_run "$scr" "$(fx_body "$B64_FFFF")")
    [[ "$(field "$out" out)" == "active 4294967295 T2" ]] \
        && ok "(16f:$n) a slot whose low-word bytes are all 0xff → 4294967295 (arithmetic decode, bytes >= 0x80 intact)" || bad "(16f:$n) high bytes misread ($out)"
    # unusable shapes: tier 2 unusable → tier 3 asked → both unusable = rc 1
    for fx in "tag2:$(fx_body "$B64_TAG2")" "short4:$(fx_body "$B64_SHORT4")" "short8:$(fx_body "$B64_SHORT8")" \
              "wrongowner:$(fx_body 'AQCsZRsAAAAA' "$SYSTEM_PROGRAM")" "rpcerror:$RPC_ERROR" "notjson:<html>502 Bad Gateway</html>" \
              "empty:EMPTY" "transport:RC7" \
              "parsedshape:{\"jsonrpc\":\"2.0\",\"result\":{\"context\":{\"slot\":1},\"value\":{\"data\":{\"parsed\":{\"info\":{\"activatedAt\":459648000}}},\"owner\":\"Feature111111111111111111111111111111111111\"}},\"id\":1}"; do
        out=$(fx_run "$scr" "${fx#*:}" "${fx#*:}")
        [[ "$(field "$out" rc)" == "1" && -z "$(field "$out" out)" && "$(field "$out" calls)" == "2" ]] \
            && ok "(16g:$n:${fx%%:*}) unusable on both tiers → rc 1, nothing printed, both tiers asked" \
            || bad "(16g:$n:${fx%%:*}) not 'unknown' ($out)"
    done
    out=$(fx_run "$scr" "$(fx_body "$B64_TAG2")" "$LIVE_MAINNET")
    [[ "$(field "$out" rc)" == "0" && "$(field "$out" out)" == "active 459648000 T3" && "$(field "$out" calls)" == "2" ]] \
        && ok "(16h:$n) tier 2 unusable (tag 2), tier 3 answers → 'active 459648000 T3' (the tier is named)" \
        || bad "(16h:$n) fall-through to tier 3 wrong ($out)"
    out=$(fx_run "$scr" "$(fx_body 'AQCsZRsAAAAA' "$SYSTEM_PROGRAM")" "$NULL_VALUE")
    [[ "$(field "$out" out)" == "absent 0 T3" ]] \
        && ok "(16i:$n) a wrong-owner answer on tier 2 is NOT 'present': tier 3's value:null decides → absent via T3" \
        || bad "(16i:$n) wrong owner treated as an answer ($out)"
    out=$(fx_run "$scr" "$LIVE_MAINNET")
    req=$(field "$out" req1)
    [[ "$req" == *"$ID_NEW"* && "$req" == *'"encoding":"base64"'* && "$req" != *jsonParsed* && "$req" != *"$ID_OLD"* && "$req" == *'"method":"getAccountInfo"'* ]] \
        && ok "(16j:$n) the request names the REAL id $ID_NEW and asks encoding base64 (not jsonParsed, not the 4.2.1 id)" \
        || bad "(16j:$n) request wrong ($req)"
done
c=$(grep -c "^ALPENGLOW_FEATURE_ID=\"$ID_NEW\"" "$PRIMARY" "$STANDBY" | tr '\n' ' ')
[[ "$c" == *"solana-primary-failover.sh:1"* && "$c" == *"solana-standby-failover.sh:1"* ]] \
    && ok "(16k) both daemons default ALPENGLOW_FEATURE_ID to the real id (the facts job pins it to the agave and jito tags)" \
    || bad "(16k) ALPENGLOW_FEATURE_ID default: $c"
[[ "$(grep -c "$ID_OLD" "$PRIMARY" "$STANDBY" | tr '\n' ' ')" == *":0"*":0"* ]] \
    && ok "(16l) the 4.2.1 id occurs in neither daemon" || bad "(16l) the old id is still in a daemon"

# ── (17) end to end: the live mainnet answer through the real fetch AND the real check ────────────
echo ""; echo "─── (17) the live mainnet answer → the real check: active, no page, persisted ───"
e2e() {   # e2e <script> <answer…> → the check's record, with the REAL fetch under a shadowed curl
  local script="$1"; shift
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC" 2>/dev/null; rm -f "$SRC"
    TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"; ALPENGLOW_GATE_CHECK_HOURS=6
    BF=$(mktemp); EVTF=$(mktemp); trap 'rm -f "$BF" "$EVTF"' EXIT
    local b; for b in "$@"; do printf '%s\n' "$b" >> "$BF"; done
    _SIM_NOW=100; harness_clock_shims
    _watchdog_pet(){ :; }; log(){ :; }; log_error(){ :; }; log_info(){ :; }; log_warn(){ :; }; alert_info(){ :; }; send_telegram(){ return 0; }; send_webhook(){ :; }
    P=0; C=0; S=0
    alert_warn(){ P=$((P+1)); return 0; }; alert(){ C=$((C+1)); return 0; }; save_state(){ S=$((S+1)); return 0; }
    curl(){ local n; echo C >> "$EVTF"; n=$(grep -c 'C' "$EVTF"); sed -n "${n}p" "$BF"; return 0; }
    _alpenglow_gate_check
    printf 'pages=%s|crit=%s|state=%s|saves=%s|slot=%s|tier=%s\n' "$P" "$C" "${_alpenglow_gate_state:-none}" "$S" "${_alpenglow_gate_slot:-}" "${_alpenglow_gate_tier:-}"
  )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(basename "$scr" | sed 's/solana-\(.*\)-failover.sh/\1/')
    out=$(e2e "$scr" "$LIVE_MAINNET")
    [[ "$(field "$out" pages)" == "0" && "$(field "$out" crit)" == "0" && "$(field "$out" state)" == "active" && "$(field "$out" saves)" == "1" && "$(field "$out" slot)" == "459648000" && "$(field "$out" tier)" == "T2" ]] \
        && ok "(17a:$n) the live mainnet answer → state active, slot 459648000 via T2, ZERO pages, persisted once" \
        || bad "(17a:$n) wrong ($out)"
    out=$(e2e "$scr" "$NULL_VALUE")
    [[ "$(field "$out" pages)" == "1" && "$(field "$out" state)" == "absent" ]] \
        && ok "(17b:$n) value:null → absent: ONE page, state absent" || bad "(17b:$n) wrong ($out)"
    out=$(e2e "$scr" "$(fx_body "$B64_PENDING")")
    [[ "$(field "$out" pages)" == "1" && "$(field "$out" state)" == "pending" ]] \
        && ok "(17c:$n) tag 0 → pending: ONE page, state pending" || bad "(17c:$n) wrong ($out)"
done

# ── (1) first determination active: no page ──────────────────────────────────────────────────────
echo ""; echo "─── (1) first determination active → no page; a log line; persisted; the status line ───"
out=$(ap_run "$STANDBY" 6 "active" "100")
[[ "$(field "$out" pages)" == "0" && "$(field "$out" crit)" == "0" && "$(field "$out" blind)" == "0" ]] \
    && ok "(1a) active as the first determination → zero pages (no alert_warn, no CRITICAL alert)" \
    || bad "(1a) paged on active ($out)"
[[ "$(field "$out" loginfo)" == *"ACTIVE since slot 459648000 via T2"* && "$(field "$out" loginfo)" == *"no page"* ]] \
    && ok "(1b) it is a log line naming the activation slot and the tier" || bad "(1b) log line: '$(field "$out" loginfo)'"
[[ "$(field "$out" state)" == "active" && "$(field "$out" saved)" == "active" ]] \
    && ok "(1c) state=active, save_state called once with active recorded" || bad "(1c) state=$(field "$out" state) saved=$(field "$out" saved)"
[[ "$(field "$out" stat)" == *"tripwire: active since slot 459648000 via T2"* && "$(field "$out" stat)" == *"AG mode ON"* ]] \
    && ok "(1d) the status line says active since slot 459648000 via T2 and AG mode ON" || bad "(1d) status line: '$(field "$out" stat)'"

# ── (2)/(3)/(4) pending / absent / away from active: ONE page per run ────────────────────────────
echo ""; echo "─── (2) pending → exactly one page; (3) absent → one page; (4) away from active → one page, once per RUN ───"
out=$(ap_run "$STANDBY" 6 "pending" "100")
txt=$(field "$out" text)
if [[ "$(field "$out" pages)" == "1" && "$(field "$out" crit)" == "0" ]]; then
    ok "(2a) pending → exactly one alert_warn, no CRITICAL"
else
    bad "(2a) expected 1 warn page and no critical ($out)"
fi
[[ "$txt" == *"ALPENGLOW TRIPWIRE reads pending via T2"* && "$txt" == *"may not serve the cluster this node validates"* && "$txt" == *"AG mode stays on"* ]] \
    && ok "(2b) the page names the state and tier, says the configured RPC may not serve this cluster, and that AG mode stays on" \
    || bad "(2b) page text: '$txt'"
[[ "$txt" != *"4.2 audit"* && "$txt" != *"set-identity"* ]] \
    && ok "(2c) the 4.2-era text ('re-run the 4.2 audit', the set-identity warning) is gone" || bad "(2c) old wording survives: '$txt'"
[[ "$(field "$out" state)" == "pending" && "$(field "$out" saved)" == "pending" ]] \
    && ok "(2d) pending persisted" || bad "(2d) state=$(field "$out" state) saved=$(field "$out" saved)"
out=$(ap_run "$STANDBY" 6 "absent" "100")
[[ "$(field "$out" pages)" == "1" && "$(field "$out" text)" == *"reads absent via T2"* && "$(field "$out" state)" == "absent" ]] \
    && ok "(3) absent (value:null) as the first determination → one page naming 'absent'" || bad "(3) wrong ($out)"
out=$(ap_run "$STANDBY" 6 "absent" "100" 0 "active")
[[ "$(field "$out" pages)" == "1" && "$(field "$out" state)" == "absent" && "$(field "$out" saved)" == "absent" ]] \
    && ok "(4a) active → absent (a change away from active): one page, persisted" || bad "(4a) wrong ($out)"
out=$(ap_run "$STANDBY" 6 "pending absent pending absent" "100 21700 43300 64900")
[[ "$(field "$out" pages)" == "1" && "$(field "$out" paged)" == "1" && "$(field "$out" fetches)" == "4" ]] \
    && ok "(4b) four non-active readings in one run → ONE page in total (one page per process run)" || bad "(4b) wrong ($out)"
out=$(ap_run "$STANDBY" 6 "pending" "100" 0 "pending")
[[ "$(field "$out" pages)" == "1" && "$(field "$out" saves)" == "0" ]] \
    && ok "(4c) a restart that reads the SAME non-active state as the persisted one still pages once for this run (the standing condition), and saves nothing" || bad "(4c) wrong ($out)"

# ── (5) active stable: silent; a later change INTO active is silent ──────────────────────────────
echo ""; echo "─── (5) active stable across many checks → zero pages; pending → active is silent ───"
out=$(ap_run "$STANDBY" 6 "active active active active" "100 21700 43300 64900")
[[ "$(field "$out" pages)" == "0" && "$(field "$out" crit)" == "0" && "$(field "$out" state)" == "active" && "$(field "$out" fetches)" == "4" && "$(field "$out" saves)" == "1" ]] \
    && ok "(5a) 4 checks all active → zero pages, state=active, 4 fetches, one save (the first determination)" || bad "(5a) wrong ($out)"
out=$(ap_run "$STANDBY" 6 "active" "100" 0 "pending")
[[ "$(field "$out" pages)" == "0" && "$(field "$out" crit)" == "0" && "$(field "$out" state)" == "active" && "$(field "$out" saved)" == "active" ]] \
    && ok "(5b) pending → active (a later change INTO active): no page, persisted" || bad "(5b) wrong ($out)"

# ── (6) unknown (rc 1): never pages, never overwrites, no save ───────────────────────────────────
echo ""; echo "─── (6) unknown never pages and never overwrites the persisted state ───"
out=$(ap_run "$STANDBY" 6 "rc1 rc1" "100 21700" 0 "active")
[[ "$(field "$out" pages)" == "0" && "$(field "$out" blind)" == "0" && "$(field "$out" state)" == "active" && "$(field "$out" saves)" == "0" && "$(field "$out" fetches)" == "2" ]] \
    && ok "(6a) two unknown probes: 0 pages (streak < 4), state stays 'active', 0 saves, 2 fetches" \
    || bad "(6a) wrong ($out)"
[[ "$(field "$out" warnlogs)" == "2" ]] \
    && ok "(6b) each probe failure logs at WARN level (the operator's warn scan sees tripwire blindness)" \
    || bad "(6b) warn-level failure logs: $(field "$out" warnlogs) (want 2) — probe failure is quieter than warn"

# ── (7) knob 0 = off; drift announcer wordings ───────────────────────────────────────────────────
echo ""; echo "─── (7) ALPENGLOW_GATE_CHECK_HOURS=0 → off (zero fetches) + drift-announced ───"
out=$(ap_run "$STANDBY" 0 "active" "100 21700 999999")
[[ "$(field "$out" fetches)" == "0" && "$(field "$out" pages)" == "0" ]] \
    && ok "(7a) knob 0 → zero fetches, zero pages over 3 cycles" || bad "(7a) knob 0 still probed ($out)"
d=$(drift_out "$STANDBY" 'ALPENGLOW_GATE_CHECK_HOURS=0')
[[ "$d" == *"ALPENGLOW_GATE_CHECK_HOURS=0 DISABLES"* ]] \
    && ok "(7b) drift announcer: 0 → DISABLES wording (laxest)" || bad "(7b) 0 not announced as DISABLES: '$d'"
d=$(drift_out "$STANDBY" 'ALPENGLOW_GATE_CHECK_HOURS=12')
[[ "$d" == *"ALPENGLOW_GATE_CHECK_HOURS=12 is laxer than this version's default 6"* ]] \
    && ok "(7c) drift announcer: 12 → generic laxer-than-default-6 line" || bad "(7c) 12 not announced: '$d'"
d=$(drift_out "$STANDBY")
[[ "$d" != *"ALPENGLOW"* ]] \
    && ok "(7d) default 6 → silent (no ALPENGLOW drift line)" || bad "(7d) default announced: '$d'"
d=$(drift_out "$STANDBY" 'ALPENGLOW_GATE_CHECK_HOURS=0')
[[ "$d" != *"set-identity"* && "$d" != *"4.2 audit"* && "$d" == *"report"* ]] \
    && ok "(7e) the drift text says what the probe is now (a report on whether the RPC serves the cluster), not the 4.2 audit / set-identity warning" || bad "(7e) drift wording: '$d'"

# ── (8) fresh-boot first check immediate; cadence ────────────────────────────────────────────────
echo ""; echo "─── (8) T0=50 (fresh boot): the FIRST cycle probes — no cadence wait; HOURS=6 cadence ───"
out=$(ap_run "$STANDBY" 6 "active" "50")
[[ "$(field "$out" fetches)" == "1" ]] \
    && ok "(8a) first check ran immediately at mono t=50 (0-sentinel/monotonic lesson)" || bad "(8a) first check did not run at t=50 ($out)"
out=$(ap_run "$STANDBY" 6 "active active active" "100 5000 15000 21699 21700")
[[ "$(field "$out" fetches)" == "2" ]] \
    && ok "(8b) exactly 2 fetches over 5 cycles (t=100 and t=21700; 21699 still inside the window)" || bad "(8b) cadence wrong — fetches=$(field "$out" fetches) ($out)"

# ── (9) BYTE-IDENTITY of the whole region across daemons + behavior parity ───────────────────────
echo ""; echo "─── (9) the tripwire and the [ag] block are byte-identical across the daemons ───"
for fn in _alpenglow_gate_fetch _alpenglow_gate_check _alpenglow_status_line; do
    P_F=$(sed -n "/^$fn() {/,/^}\$/p" "$PRIMARY")
    S_F=$(sed -n "/^$fn() {/,/^}\$/p" "$STANDBY")
    if [[ -n "$P_F" && "$P_F" == "$S_F" ]]; then
        ok "(9a:$fn) body byte-identical ($(printf '%s\n' "$P_F" | wc -l | tr -d ' ') lines)"
    else
        bad "(9a:$fn) missing or DIVERGED between the daemons"
    fi
done
P_J=$(grep '^_AGF_JQ[+]*=' "$PRIMARY"); S_J=$(grep '^_AGF_JQ[+]*=' "$STANDBY")
[[ -n "$P_J" && "$P_J" == "$S_J" ]] && ok "(9b) the decoding jq program (_AGF_JQ: its single-line pieces) is byte-identical ($(printf '%s\n' "$P_J" | wc -l | tr -d ' ') lines)" || bad "(9b) _AGF_JQ missing or DIVERGED"
if extract_twin '^# ── \[ag\] shared block' '^# ── \[ag\] end shared block'; then
    [[ "$TWIN_P" == "$TWIN_S" ]] && ok "(9c) the [ag] shared block is byte-identical ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)" || bad "(9c) the [ag] block DIVERGED between the daemons"
fi
# the header holds LITERAL parentheses: in a sed BRE a bare ( ) is literal and \( \) is a group, so the anchor writes them bare
if extract_twin '^# ── v0\.7 (AG-1\.1) — ALPENGLOW FEATURE-GATE TRIPWIRE' '^# ── \[ag\] end shared block'; then
    [[ "$TWIN_P" == "$TWIN_S" ]] && ok "(9f) the WHOLE region (comments, the state globals, the three functions, the jq program, the [ag] block) is byte-identical ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)" || bad "(9f) the tripwire region DIVERGED between the daemons"
fi
out=$(ap_run "$PRIMARY" 6 "pending" "100")
[[ "$(field "$out" pages)" == "1" && "$(field "$out" state)" == "pending" && "$(field "$out" saved)" == *"pending"* ]] \
    && ok "(9d) PRIMARY twin: pending pages once and persists (behavior parity)" || bad "(9d) PRIMARY twin wrong ($out)"
out=$(ap_run "$PRIMARY" 6 "active" "100")
[[ "$(field "$out" pages)" == "0" && "$(field "$out" state)" == "active" ]] \
    && ok "(9e) PRIMARY twin: first determination active is silent" || bad "(9e) PRIMARY twin wrong ($out)"

# ── (10) PERMANENT REVERT-CONTROL ────────────────────────────────────────────────────────────────
echo ""; echo "─── (10) revert-control: _alpenglow_gate_check(){ :; } → the pending scenario pages 0 ───"
out=$(ap_run "$STANDBY" 6 "pending" "100" 1)
[[ "$(field "$out" pages)" == "0" && "$(field "$out" fetches)" == "0" ]] \
    && ok "(10) neutered check → 0 pages/0 fetches (documents the parent daemon; case 2 bites)" || bad "(10) revert-control leaked ($out)"

# ── (11) wiring: main-loop call site + startup visibility line + the heartbeat status line (both daemons) ──
echo ""; echo "─── (11) structural: call at the top of each main loop, armed line at startup, status line on the heartbeat ───"
for scr in "$PRIMARY" "$STANDBY"; do
    name=$(basename "$scr")
    below=$(sed -n '/^# ========================= MAIN LOOP/,$p' "$scr")
    [[ "$below" == *"_alpenglow_gate_check"* ]] \
        && ok "(11a:$name) main loop calls _alpenglow_gate_check" || bad "(11a:$name) no _alpenglow_gate_check call after the MAIN LOOP banner"
    [[ "$below" == *"tripwire armed: probing the feature gate every"* && "$below" == *"tripwire DISABLED"* ]] \
        && ok "(11b:$name) startup visibility line present (armed + DISABLED wordings)" || bad "(11b:$name) startup tripwire visibility line missing"
    hb=$(grep -A3 '♥ Heartbeat:' "$scr" | grep -c '_alpenglow_status_line')
    [[ "$hb" == "1" ]] \
        && ok "(11c:$name) _alpenglow_status_line rides the ♥ Heartbeat block (the status line)" || bad "(11c:$name) the status line is not wired to the heartbeat ($hb)"
done

# ── (12) BLIND STREAK: persistent probe failure pages at streak 4, repeats per throttle ──────────
echo ""; echo "─── (12) tripwire blindness pages at 4 consecutive failures, repeats, resets on success ───"
out=$(ap_run "$STANDBY" 6 "active rc1 rc1 rc1 rc1 rc1 active" "100 21700 22600 23500 24400 25300 26200")
[[ "$(field "$out" fetches)" == "7" ]] \
    && ok "(12a) all seven instants probed — failures retry on the 900 s floor, not the 6 h cadence" || bad "(12a) fetches=$(field "$out" fetches) (want 7) ($out)"
[[ "$(field "$out" blind)" == "2" && "$(field "$out" btext)" == *"consecutive"* ]] \
    && ok "(12b) BLIND page fires exactly at streak 4 and repeats per ALERT_THROTTLE (2 pages, none earlier)" || bad "(12b) blind pages=$(field "$out" blind) (want 2) btext='$(field "$out" btext)'"
[[ "$(field "$out" pages)" == "0" && "$(field "$out" state)" == "active" ]] \
    && ok "(12c) no transition page, state intact; the success at the end resets the streak silently" || bad "(12c) pages=$(field "$out" pages) state=$(field "$out" state) ($out)"

# ── (13) RETRY FLOOR vs FULL CADENCE ─────────────────────────────────────────────────────────────
echo ""; echo "─── (13) a transient failure costs ~15 min, not 6 h; success keeps the 6 h cadence ───"
out=$(ap_run "$STANDBY" 6 "rc1 active" "100 1000 1900")
[[ "$(field "$out" fetches)" == "2" ]] \
    && ok "(13a) failure at t=100 → re-probe allowed at t=1000 (900 s floor); the success then holds the full cadence (t=1900 skipped)" || bad "(13a) fetches=$(field "$out" fetches) (want 2) ($out)"
out=$(ap_run "$STANDBY" 6 "active active" "100 1000 21700")
[[ "$(field "$out" fetches)" == "2" ]] \
    && ok "(13b) success at t=100 → next probe only at t=21700 (full 6 h; t=1000 skipped)" || bad "(13b) fetches=$(field "$out" fetches) (want 2) ($out)"

# ── (14) the tripwire sends no CRITICAL page, whatever it reads ──────────────────────────────────
echo ""; echo "─── (14) no reading of the gate is critical: AG mode does not depend on it ───"
out=$(ap_run "$STANDBY" 6 "pending active absent active" "100 21700 43300 64900")
[[ "$(field "$out" crit)" == "0" && "$(field "$out" pages)" == "1" ]] \
    && ok "(14a) pending → active → absent → active: no CRITICAL alert at all, one warn page for the run" || bad "(14a) crit=$(field "$out" crit) pages=$(field "$out" pages) ($out)"
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(basename "$scr")
    nal=$(sed -n '/^_alpenglow_gate_check() {/,/^}$/p' "$scr" | grep -cE '^[[:space:]]*alert "')
    [[ "$nal" == "0" ]] \
        && ok "(14b:$n) _alpenglow_gate_check contains no CRITICAL 'alert' call" || bad "(14b:$n) a CRITICAL alert call is back in the tripwire ($nal)"
done

# ── (15) the companion gate: named, with its 4.4.0 reason ────────────────────────────────────────
echo ""; echo "─── (15) alpenglow_fast_leader_handover: watched-or-justified, in the code itself ───"
for scr in "$STANDBY" "$PRIMARY"; do
    name=$(basename "$scr")
    t=$(cat "$scr")
    [[ "$t" == *"FastLeaderHandover11111111111111111111111111"* && "$t" == *"deliberately NOT watched"* && "$t" == *"core/src/replay_stage.rs:1651"* && "$t" == *"block_component_processor.rs:422"* ]] \
        && ok "(15:$name) the companion gate is named (4.4.0 id, its four read sites) with the reason it is not watched" \
        || bad "(15:$name) companion-gate decision missing or stale (a tripwire watching one of two sibling gates must say why)"
done

# ── (18) _ag_mode: unconditional ─────────────────────────────────────────────────────────────────
echo ""; echo "─── (18) _ag_mode returns 0 (AG mode) unconditionally ───"
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(basename "$scr" | sed 's/solana-\(.*\)-failover.sh/\1/')
    r=$(
        set +e
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$scr" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        ALPENGLOW_GATE_CHECK_HOURS=0; _alpenglow_gate_state=pending; ALPENGLOW_FEATURE_ID=""; DRY_RUN=false; AG_MODE=0; ALPENGLOW_AG_MODE=0; STATE_FILE=/nonexistent
        _ag_mode; a=$?
        _alpenglow_gate_state=absent; ALPENGLOW_GATE_CHECK_HOURS=6; AG_MODE=1; _ag_mode; b=$?
        _alpenglow_gate_state=""; unset ALPENGLOW_GATE_CHECK_HOURS; _ag_mode; c=$?
        echo "$a$b$c"
    )
    [[ "$r" == "000" ]] \
        && ok "(18a:$n) _ag_mode → 0 with the tripwire off / pending / absent / undetermined and hostile AG_* variables" || bad "(18a:$n) _ag_mode answered '$r'"
    d=$(mktemp -d)
    if bp_parse "$scr" "$d"; then
        body=$(bp_bodies "$d" | awk -F'\t' '$1 == "_ag_mode" { print $2 }')
        nb=$(printf '%s' "$body" | tr '\001' '\n' | grep -vE '^[{}]? *$' | tr -d ' ')
        defs=$(awk '$1 == "_ag_mode"' "$d/names" | wc -l | tr -d ' ')
        [[ "$nb" == "return0" && "$defs" == "1" ]] \
            && ok "(18b:$n) bash's own parse: _ag_mode is defined exactly once and its whole body is 'return 0' — no variable, file or command can reach it" \
            || bad "(18b:$n) _ag_mode body per bash's parse: '$nb' (definitions: $defs)"
    else
        bad "(18b:$n) bp_parse could not parse the daemon"
    fi
    m="$d/mutant.sh"
    if mutate "$scr" 's/^_ag_mode() { return 0; }$/_ag_mode() { [[ -f \/tmp\/ag-off ]] \&\& return 1; return 0; }/' "$m"; then
        if bp_parse "$m" "$d/m"; then
            body=$(bp_bodies "$d/m" | awk -F'\t' '$1 == "_ag_mode" { print $2 }')
            nb=$(printf '%s' "$body" | tr '\001' '\n' | grep -vE '^[{}]? *$' | tr -d ' ')
            [[ "$nb" != "return0" ]] \
                && ok "(18c:$n) CONTROL: a mutant _ag_mode that a file can switch off is NOT 'return 0' on the same parse (the census bites)" \
                || bad "(18c:$n) the census did not see the mutant (body '$nb')"
        else
            bad "(18c:$n) bp_parse could not parse the mutant"
        fi
    fi
    rm -rf "$d"
done

# ── (19) CONTROLS for the fetch: a mutant of each decisive piece of the decode / the request misreads its fixture ──
echo ""; echo "─── (19) CONTROL: the (16) fixtures bite — each mutant of the decode or the request misreads one ───"
fx_ctl() {   # fx_ctl <label> <field> <right value> <sed expr> <answer…> — on each daemon the real fetch gives <right value> in <field>; its mutant does not
    local label="$1" fname="$2" right="$3" expr="$4" scr n m d out_ok out_m; shift 4
    for scr in "$STANDBY" "$PRIMARY"; do
        n=$(basename "$scr" | sed 's/solana-\(.*\)-failover.sh/\1/')
        d=$(mktemp -d); m="$d/mutant.sh"
        if mutate "$scr" "$expr" "$m"; then
            out_ok=$(fx_run "$scr" "$@"); out_m=$(fx_run "$m" "$@")
            [[ "$(field "$out_ok" "$fname")" == "$right" && "$(field "$out_m" "$fname")" != "$right" ]] \
                && ok "(19:$label:$n) CONTROL: the real fetch gives '$right'; the mutant gives '$(field "$out_m" "$fname")'" \
                || bad "(19:$label:$n) the control did not bite: real='$(field "$out_ok" "$fname")' mutant='$(field "$out_m" "$fname")' (want real='$right', mutant different)"
        fi
        rm -rf "$d"
    done
}
fx_ctl endian   out "active 459648000 T2" 's/reduce range(8; 0; -1) as \$i/reduce range(1; 9) as $i/' "$LIVE_MAINNET"
fx_ctl sextet   out "active 4294967295 T2" 's/elif \. == 47 then 63/elif . == 47 then 62/' "$(fx_body "$B64_FFFF")"
fx_ctl owner    out "absent 0 T3" '/\.result\.value\.owner != /d' "$(fx_body 'AQCsZRsAAAAA' "$SYSTEM_PROGRAM")" "$NULL_VALUE"
fx_ctl tag2     rc  "1" 's/elif \$y\[0\] == 1 then "active "/elif $y[0] >= 1 then "active "/' "$(fx_body "$B64_TAG2")" "$(fx_body "$B64_TAG2")"
fx_ctl nullval  out "absent 0 T2" 's/elif \.result\.value == null then "absent 0"/elif .result.value == null then "bad"/' "$NULL_VALUE"
fx_ctl pending  out "pending 0 T2" 's/if \$y\[0\] == 0 then "pending 0"/if $y[0] == 0 then "bad"/' "$(fx_body "$B64_PENDING")"
fx_ctl request  req1 "$(fx_run "$STANDBY" "$LIVE_MAINNET" | tr '|' '\n' | grep '^req1=' | cut -d= -f2-)" 's/\\"encoding\\":\\"base64\\"/\\"encoding\\":\\"jsonParsed\\"/' "$LIVE_MAINNET"

# the harness's banner (6.3.1 fix round 7 — the delta panel 6's H4): the same RESULTS lines, and a network client the
# net guard failed makes this suite FAIL standalone too, not only under run_all's stage (4)
results_banner
