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

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
command -v jq >/dev/null 2>&1 || { echo "  ❌ jq required for this test"; exit 1; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

    rm -f "$TGCAP" "$WHCAP"
    unset -f curl
}

echo "============================================="
echo "  v0.6.5 (F5) notification/payload escaping"
echo "============================================="
run_suite "solana-primary-failover.sh" "PRIMARY"
run_suite "solana-standby-failover.sh" "STANDBY"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
