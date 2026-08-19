#!/bin/bash
# Unit test: v0.6.4 notification routing + external heartbeat watchdog.
#
# Sources the REAL functions from each script (up to the MAIN LOOP marker) and mocks `curl`
# (jq stays real — send_telegram pipes the mocked Telegram reply through it). Asserts:
#   - alert_info  -> Telegram only           (never ntfy/webhook)
#   - alert_warn  -> Telegram (⚠️) AND webhook at NON-urgent (high) priority
#   - alert       -> Telegram (🚨) AND webhook at URGENT priority; queues _pending_alert
#                    on a Telegram failure, and the webhook still fires
#   - heartbeat_ping: fires curl at cadence when HEARTBEAT_URL set; no-op (and timer untouched)
#                     when unset; throttled within the interval; fires again once it elapses;
#                     fire-and-forget — a FAILING ping URL does not change its success path.
#
# Both scripts carry their own copy of these functions, so the whole suite runs against each.

# Config vars below are read by the SOURCED functions (send_telegram / send_webhook /
# heartbeat_ping), which shellcheck can't see — silence the false "unused" reports.
# shellcheck disable=SC2034

# harness: tests/lib/harness.sh — ok/bad+banners, paths (DIR aliased: run_suite takes basenames so
# its banner line stays byte-identical). Recorders, curl mock and per-script cut stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

command -v jq >/dev/null 2>&1 || { echo "  ❌ jq is required for this test"; exit 1; }

DIR="$HARNESS_DIR"

# Per-call recorders. Files (not vars) because send_telegram calls curl inside $(...) (a subshell)
# and heartbeat_ping backgrounds curl with & — both lose plain-variable mutations.
TG_CALLS=$(mktemp); WH_CALLS=$(mktemp); HB_CALLS=$(mktemp)
reset_calls() { : > "$TG_CALLS"; : > "$WH_CALLS"; : > "$HB_CALLS"; }
n_tg() { wc -l < "$TG_CALLS" | tr -d ' '; }
n_wh() { wc -l < "$WH_CALLS" | tr -d ' '; }
n_hb() { wc -l < "$HB_CALLS" | tr -d ' '; }

run_suite() {
    local SCRIPT="$1" LABEL="$2"
    echo ""
    echo "─── $LABEL ($SCRIPT) ───"
    if [[ ! -f "$DIR/$SCRIPT" ]]; then bad "$LABEL: script not found at $DIR/$SCRIPT"; return; fi

    local SRC; SRC=$(mktemp)
    sed -n '1,/MAIN LOOP/p' "$DIR/$SCRIPT" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"
    rm -f "$SRC"

    # --- Notifications enabled but fully offline (everything routed through the mock curl) ---
    NODE_NAME="TESTNODE"
    TG_ENABLED=true; TG_BOT_TOKEN="bot:tok"; TG_CHAT_ID="chat"
    WEBHOOK_URL="https://ntfy.sh/test-channel"; WEBHOOK_BODY=""
    LOG_FILE=/dev/null
    _pending_alert=""
    _TG_FAIL=""; _HB_FAIL=""; _HB_SLEEP=""

    # Silence the real loggers (the functions under test are the curl-routing ones).
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }

    # Mock curl: classify the call by URL, record the FULL arg string, emulate the Telegram
    # JSON reply, and allow injected failures (_TG_FAIL / _HB_FAIL).
    curl() {
        local args="$*"
        # v0.6.5 (F5): alert() now puts REAL newlines in the Telegram text (--data-urlencode encodes
        # them on the wire). Collapse newlines so each curl call records as exactly ONE line and the
        # wc -l call counters stay accurate; the content is preserved on that line for the greps.
        args="${args//$'\n'/ }"
        if [[ "$args" == *"api.telegram.org"* ]]; then
            echo "$args" >> "$TG_CALLS"
            [[ -n "$_TG_FAIL" ]] && return 1
            echo '{"ok":true}'          # send_telegram pipes this through `jq -e .ok`
            return 0
        fi
        if [[ -n "$HEARTBEAT_URL" && "$args" == *"$HEARTBEAT_URL"* ]]; then
            [[ -n "$_HB_SLEEP" ]] && sleep "$_HB_SLEEP"   # simulate a slow/hung endpoint
            echo "$args" >> "$HB_CALLS"
            [[ -n "$_HB_FAIL" ]] && return 7
            return 0
        fi
        if [[ -n "$WEBHOOK_URL" && "$args" == *"$WEBHOOK_URL"* ]]; then
            echo "$args" >> "$WH_CALLS"
            return 0
        fi
        return 0
    }

    # ---- 1. alert_info -> Telegram only ----
    reset_calls; alert_info "info message"
    if [[ "$(n_tg)" == "1" && "$(n_wh)" == "0" ]]; then
        ok "$LABEL alert_info: Telegram only (tg=1 wh=0)"
    else
        bad "$LABEL alert_info: expected tg=1 wh=0, got tg=$(n_tg) wh=$(n_wh)"
    fi

    # ---- 2. alert_warn -> Telegram + webhook (high / non-urgent) ----
    reset_calls; alert_warn "warn message"
    if [[ "$(n_tg)" == "1" && "$(n_wh)" == "1" ]]; then
        ok "$LABEL alert_warn: Telegram + webhook (tg=1 wh=1)"
    else
        bad "$LABEL alert_warn: expected tg=1 wh=1, got tg=$(n_tg) wh=$(n_wh)"
    fi
    if grep -q "Priority: high" "$WH_CALLS"; then
        ok "$LABEL alert_warn: webhook priority=high (non-urgent)"
    else
        bad "$LABEL alert_warn: webhook missing 'Priority: high' -> $(cat "$WH_CALLS")"
    fi
    # warnings pass no identity → the webhook body must be identity-free
    if grep -q "Identity:" "$WH_CALLS"; then
        bad "$LABEL alert_warn: webhook body should NOT carry an identity -> $(cat "$WH_CALLS")"
    else
        ok "$LABEL alert_warn: webhook body is identity-free"
    fi

    # ---- 3. alert -> Telegram + webhook (urgent); no _pending on success ----
    reset_calls; _pending_alert=""; alert "reason text" "IDENTITY1234567890" "SWITCHED ✅"
    if [[ "$(n_tg)" == "1" && "$(n_wh)" == "1" ]]; then
        ok "$LABEL alert: Telegram + webhook (tg=1 wh=1)"
    else
        bad "$LABEL alert: expected tg=1 wh=1, got tg=$(n_tg) wh=$(n_wh)"
    fi
    if grep -q "Priority: urgent" "$WH_CALLS"; then
        ok "$LABEL alert: webhook priority=urgent"
    else
        bad "$LABEL alert: webhook missing 'Priority: urgent' -> $(cat "$WH_CALLS")"
    fi
    # NN#3 guard: the critical payload MUST carry the identity (byte-identical to pre-v0.6.4).
    # 'IDENTITY1234567890' truncates to 16 chars in the ntfy body -> 'Identity: IDENTITY12345678'.
    if grep -q "Identity: IDENTITY" "$WH_CALLS"; then
        ok "$LABEL alert: critical webhook body carries the identity"
    else
        bad "$LABEL alert: critical webhook body MISSING identity -> $(cat "$WH_CALLS")"
    fi
    if [[ -z "$_pending_alert" ]]; then
        ok "$LABEL alert: no _pending_alert queued on success"
    else
        bad "$LABEL alert: _pending_alert should be empty on success (got '$_pending_alert')"
    fi

    # ---- 4. alert with Telegram failing -> queues _pending_alert, webhook still fires ----
    reset_calls; _pending_alert=""; _TG_FAIL=1
    alert "reason2" "IDENT2" "SWITCH FAILED ❌"
    _TG_FAIL=""
    if [[ -n "$_pending_alert" ]]; then
        ok "$LABEL alert: queues _pending_alert on Telegram failure"
    else
        bad "$LABEL alert: _pending_alert NOT queued on Telegram failure"
    fi
    if [[ "$(n_wh)" == "1" ]]; then
        ok "$LABEL alert: webhook still fires when Telegram fails (wh=1)"
    else
        bad "$LABEL alert: webhook should fire even when Telegram fails (wh=$(n_wh))"
    fi

    # ---- 5. heartbeat_ping: no-op when HEARTBEAT_URL empty (and timer untouched) ----
    reset_calls; HEARTBEAT_URL=""; HEARTBEAT_PING_INTERVAL=600; _last_hb_ping=0
    heartbeat_ping; rc=$?; wait 2>/dev/null
    if [[ "$(n_hb)" == "0" && $rc -eq 0 && "$_last_hb_ping" == "0" ]]; then
        ok "$LABEL heartbeat: no-op when unset (hb=0 rc=0 timer untouched)"
    else
        bad "$LABEL heartbeat: expected no ping when unset (hb=$(n_hb) rc=$rc last=$_last_hb_ping)"
    fi

    # ---- 6. heartbeat_ping: fires at cadence when URL set + interval elapsed ----
    reset_calls; HEARTBEAT_URL="https://hc-ping.com/test-uuid"; HEARTBEAT_PING_INTERVAL=600; _last_hb_ping=0
    heartbeat_ping; rc=$?; wait 2>/dev/null
    if [[ "$(n_hb)" == "1" && $rc -eq 0 ]]; then
        ok "$LABEL heartbeat: fires when URL set + interval elapsed (hb=1 rc=0)"
    else
        bad "$LABEL heartbeat: expected one ping (hb=$(n_hb) rc=$rc)"
    fi
    if [[ "$_last_hb_ping" != "0" ]]; then
        ok "$LABEL heartbeat: advances _last_hb_ping after a ping"
    else
        bad "$LABEL heartbeat: _last_hb_ping not advanced after ping"
    fi

    # ---- 7. heartbeat_ping: throttled within the interval (immediate second call) ----
    reset_calls
    heartbeat_ping; wait 2>/dev/null
    if [[ "$(n_hb)" == "0" ]]; then
        ok "$LABEL heartbeat: throttled within interval (no extra ping)"
    else
        bad "$LABEL heartbeat: should be throttled within interval (hb=$(n_hb))"
    fi

    # ---- 8. heartbeat_ping: fires again once the interval has elapsed ----
    reset_calls; _last_hb_ping=0
    heartbeat_ping; wait 2>/dev/null
    if [[ "$(n_hb)" == "1" ]]; then
        ok "$LABEL heartbeat: fires again after interval elapsed"
    else
        bad "$LABEL heartbeat: should fire after interval elapsed (hb=$(n_hb))"
    fi

    # ---- 9. heartbeat_ping: fire-and-forget — a failing ping keeps the success path ----
    reset_calls; _last_hb_ping=0; _HB_FAIL=1
    heartbeat_ping; rc=$?; wait 2>/dev/null
    _HB_FAIL=""
    if [[ $rc -eq 0 && "$(n_hb)" == "1" ]]; then
        ok "$LABEL heartbeat: fire-and-forget (rc=0 despite failing ping; attempted=1)"
    else
        bad "$LABEL heartbeat: should return 0 despite a failing ping (rc=$rc hb=$(n_hb))"
    fi

    # ---- 10. heartbeat_ping: must NOT block the loop (backgrounding guard, NN#2) ----
    # Mock the endpoint as slow (2s). Because the real curl is backgrounded with &, heartbeat_ping
    # must return immediately; if the & were lost it would block ~2s. (1s date granularity → use 2s.)
    reset_calls; _last_hb_ping=0; _HB_SLEEP=2
    t0=$(date +%s); heartbeat_ping; t1=$(date +%s)
    _HB_SLEEP=""
    if [[ $(( t1 - t0 )) -lt 2 ]]; then
        ok "$LABEL heartbeat: non-blocking — returns before the slow ping completes ($(( t1 - t0 ))s)"
    else
        bad "$LABEL heartbeat: BLOCKED $(( t1 - t0 ))s on the ping (lost backgrounding?)"
    fi
    wait 2>/dev/null   # reap the slow background ping before leaving the suite
}

title_banner "v0.6.4 notification routing + heartbeat"
run_suite "solana-primary-failover.sh" "PRIMARY"
run_suite "solana-standby-failover.sh" "STANDBY"

rm -f "$TG_CALLS" "$WH_CALLS" "$HB_CALLS"

results_banner
