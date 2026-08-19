#!/bin/bash
# v0.6.5 (F5): notification / env payload escaping. Sources the REAL notification functions from each
# script (up to the MAIN LOOP marker), mocks curl to capture the outgoing payload, and drives alert()
# / send_webhook() with a NODE_NAME / reason / status / identity containing & < > " and a newline.
# Asserts:
#   - Telegram (parse_mode=HTML): the dynamic fields + NODE_NAME prefix are HTML-escaped (& → &amp;,
#     < → &lt;, > → &gt;), so a raw "<c>" from the reason never reaches Telegram (which would break
#     entity parsing → the CRITICAL alert silently fails).
#   - Webhook default path: the JSON body is VALID (parses via jq) despite the special chars.
#   - ntfy Title header: NODE_NAME newlines/control chars are stripped (no HTTP header injection).
# Non-vacuous: revert _html_escape / the jq webhook build / _header_sanitize → these assertions fail.

# harness: tests/lib/harness.sh — ok/bad+banners, paths (DIR aliased: run_suite takes basenames so
# its banner line stays byte-identical). Capture curl mock + per-script cut stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
command -v jq >/dev/null 2>&1 || { echo "  ❌ jq required for this test"; exit 1; }

DIR="$HARNESS_DIR"

run_suite() {
    local SCRIPT="$1" LABEL="$2"
    echo ""; echo "─── $LABEL ($SCRIPT) ───"
    [[ -f "$DIR/$SCRIPT" ]] || { bad "$LABEL: script not found at $DIR/$SCRIPT"; return; }

    local SRC; SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$DIR/$SCRIPT" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"

    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    TG_ENABLED=true; TG_BOT_TOKEN="bot:tok"; TG_CHAT_ID="chat"; LOG_FILE=/dev/null; _pending_alert=""

    local TGCAP WHCAP; TGCAP=$(mktemp); WHCAP=$(mktemp)
    # Mock curl. Telegram: record the whole call on ONE line (newlines→spaces) so the multi-line text
    # is inspectable, and return an OK reply (send_telegram pipes it through jq). Webhook: record each
    # arg on its own line so we can pick the -d JSON body / the Title header.
    curl() {
        if [[ "$*" == *"api.telegram.org"* ]]; then
            printf '%s' "$*" | tr '\n' ' ' >> "$TGCAP"; printf '\n' >> "$TGCAP"
            echo '{"ok":true}'; return 0
        fi
        printf '%s\n' "$@" >> "$WHCAP"; return 0
    }

    # Special-char payloads: & < > " and (for the Title test) an embedded newline.
    local R='a&b<c>d"e' S='SW & <ok>' ID='IDENT&<>"'

    # ---- 1. Telegram HTML escaping (default-json webhook → no ntfy headers in the way) ----
    NODE_NAME='VAL & <x>'; WEBHOOK_URL="https://example.com/hook"; WEBHOOK_BODY=""
    : > "$TGCAP"; : > "$WHCAP"; alert "$R" "$ID" "$S"
    local tg; tg=$(cat "$TGCAP")
    [[ "$tg" == *'a&amp;b&lt;c&gt;d'* ]] && ok "$LABEL TG: reason HTML-escaped (&amp; &lt; &gt;)" \
        || bad "$LABEL TG: reason not escaped -> $tg"
    [[ "$tg" != *'<c>'* ]] && ok "$LABEL TG: raw '<c>' from reason absent (won't break HTML parse)" \
        || bad "$LABEL TG: raw '<c>' reached Telegram -> $tg"
    [[ "$tg" == *'VAL &amp; &lt;x&gt;'* ]] && ok "$LABEL TG: NODE_NAME prefix escaped" \
        || bad "$LABEL TG: NODE_NAME prefix not escaped -> $tg"

    # ---- 2. Webhook default path → VALID JSON despite special chars ----
    local body; body=$(grep '^{' "$WHCAP" | head -1)
    echo "$body" | jq -e . >/dev/null 2>&1 && ok "$LABEL webhook: default body is valid JSON ($body)" \
        || bad "$LABEL webhook: default body is INVALID JSON -> $body"
    [[ "$body" == *'IDENT'* ]] && ok "$LABEL webhook: identity carried into JSON" \
        || bad "$LABEL webhook: identity missing from JSON -> $body"

    # ---- 3. ntfy Title header: NODE_NAME newline/control chars stripped (no header injection) ----
    NODE_NAME=$'NN\nINJECT'; WEBHOOK_URL="https://ntfy.sh/test-channel"; WEBHOOK_BODY=""
    : > "$TGCAP"; : > "$WHCAP"; alert "$R" "$ID" "$S"
    local titleline; titleline=$(grep '^Title:' "$WHCAP" | head -1)
    [[ "$titleline" == *'NNINJECT'* ]] && ok "$LABEL ntfy: NODE_NAME newline stripped from Title header" \
        || bad "$LABEL ntfy: Title header not sanitized -> $titleline"

    # ---- 4. _strip_html: terminates and strips correctly when a bare '>' precedes a real <tag> ----
    # The pre-fix strip-and-rejoin loop DIVERGED on exactly this shape: each round re-glued a longer
    # string (measured: 41k chars in 13 rounds) and the monitor hung inside a log call — a hung
    # monitor never self-fences. Run under a kill-deadline so a regression FAILS instead of hanging
    # the suite. Control: revert _strip_html to the one-line strip-and-rejoin loop → (4a) fails.
    local SHCAP; SHCAP=$(mktemp)
    (
      {
        _strip_html 'lag (> 32) <code>x</code>'; printf '\n'
        _strip_html '<b>bold</b> plain';         printf '\n'
        _strip_html 'delta < 5';                 printf '\n'
        _strip_html 'x < 5 <b>bold</b>';         printf '\n'
      } > "$SHCAP"
    ) &
    local SHPID=$! SHTICKS=0
    while kill -0 "$SHPID" 2>/dev/null && [[ $SHTICKS -lt 50 ]]; do sleep 0.1; SHTICKS=$((SHTICKS+1)); done
    if kill -0 "$SHPID" 2>/dev/null; then
        kill -9 "$SHPID" 2>/dev/null; wait "$SHPID" 2>/dev/null
        bad "$LABEL _strip_html: DIVERGED (still running after 5s) on \"lag (> 32) <code>x</code>\""
    else
        wait "$SHPID" 2>/dev/null
        local sh1 sh2 sh3 sh4
        { read -r sh1; read -r sh2; read -r sh3; read -r sh4; } < "$SHCAP"
        [[ "$sh1" == 'lag (> 32) x' ]] && ok "$LABEL _strip_html (4a): '>' before tag terminates, tag stripped ('$sh1')" \
            || bad "$LABEL _strip_html (4a): wrong output for '>' before tag ('$sh1')"
        [[ "$sh2" == 'bold plain' ]] && ok "$LABEL _strip_html (4b): plain tags stripped" \
            || bad "$LABEL _strip_html (4b): plain tag strip broken ('$sh2')"
        [[ "$sh3" == 'delta < 5' && "$sh4" == 'x < 5 bold' ]] && ok "$LABEL _strip_html (4c): unmatched '<' kept as literal text" \
            || bad "$LABEL _strip_html (4c): literal '<' handling wrong ('$sh3' / '$sh4')"
    fi
    rm -f "$SHCAP"

    rm -f "$TGCAP" "$WHCAP"
    unset -f curl
}

title_banner "v0.6.5 (F5) notification/payload escaping"
run_suite "solana-primary-failover.sh" "PRIMARY"
run_suite "solana-standby-failover.sh" "STANDBY"

results_banner
