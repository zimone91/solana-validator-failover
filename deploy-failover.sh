#!/bin/bash

# bash 5.2+ made "&" special in ${var//pat/replacement} (patsub_replacement, ON by default): the
# replacement's "&" expands to the matched text, which silently corrupts _html_escape's "&lt;"/"&gt;"
# on Ubuntu 24.04 / Debian 12 — broken Telegram HTML = CRITICAL alerts silently failing to send.
# This codebase is written against bash-3.2 substitution semantics; restore them everywhere.
# (No-op error on bash < 5.2, hence the || true.)
shopt -u patsub_replacement 2>/dev/null || true
# ============================================================================
# Solana PRIMARY Failover v0.6.9 — Interactive Deploy
# Run on PRIMARY node as root.
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  [OK]${NC} $1"; }
fail() { echo -e "${RED}  [FAIL]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}  [WARN]${NC} $1"; }
step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; sleep 1.5; }

# Prompt with default value. Usage: ask "Prompt" "default" → result in $REPLY
ask() {
    local prompt="$1" default="$2"
    if [[ -n "$default" ]]; then
        echo -ne "${BOLD}  $prompt${NC} [${default}]: "
    else
        echo -ne "${BOLD}  $prompt${NC}: "
    fi
    read -r REPLY
    [[ -z "$REPLY" ]] && REPLY="$default" || true
}

# Prompt with validation against allowed values
ask_choice() {
    local prompt="$1" default="$2"
    shift 2
    local choices=("$@")
    local choices_str
    choices_str=$(IFS=/; echo "${choices[*]}")
    while true; do
        if [[ -n "$default" ]]; then
            echo -ne "${BOLD}  $prompt${NC} (${choices_str}) [${default}]: "
        else
            echo -ne "${BOLD}  $prompt${NC} (${choices_str}): "
        fi
        read -r REPLY
        [[ -z "$REPLY" ]] && REPLY="$default"
        for c in "${choices[@]}"; do
            [[ "$REPLY" == "$c" ]] && return 0
        done
        warn "Invalid choice: '$REPLY'. Must be one of: ${choices_str}"
    done
}

# Prompt for path, validate file exists
ask_path() {
    local prompt="$1" default="$2" required="$3"
    while true; do
        ask "$prompt" "$default"
        if [[ -z "$REPLY" && "$required" == "true" ]]; then
            warn "This field is required"
            continue
        fi
        if [[ -n "$REPLY" && ! -f "$REPLY" ]]; then
            warn "File not found: $REPLY"
            echo -ne "  Continue anyway? (y/N): "
            read -r yn
            [[ "$yn" == "y" || "$yn" == "Y" ]] && break
            continue
        fi
        break
    done
}

# v0.6.5 (F4): prompt for a non-negative integer >= $3 (min); re-prompt on a non-numeric / too-small
# entry; normalize a leading-zero entry via 10# (so the env stores a plain decimal). Result in $REPLY.
ask_numeric() {
    local prompt="$1" default="$2" min="$3"
    while true; do
        ask "$prompt" "$default"
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && [[ $((10#$REPLY)) -ge $min ]]; then
            REPLY=$((10#$REPLY)); return 0
        fi
        warn "Must be an integer >= ${min} (got '$REPLY')"
    done
}

# v0.6.5 (F5): shell-quote a value for safe embedding in the generated env (sourced as root). Uses
# printf %q so a quote / backtick / $ / ; / space in a path / token / URL is escaped and can't break
# out of the assignment and execute as shell code. The output re-sources back to the exact value.
_envq() { printf '%q' "$1"; }

# v0.6.9 (M7): offer to start (and enable) the failover service at the end of a successful deploy.
# The installer STOPS a running failover service during the upgrade and previously only PRINTED the
# start command — an upgraded node whose operator walked away was left UNPROTECTED. Prompt default is
# Y (start). Non-interactive stdin → keep the old print-only behavior (never auto-start without a
# human: the operator must have seen the DRY_RUN/banner instructions). A function so it is
# unit-testable (tests/test_installer_guardrails.sh sources it). $1=unit, $2=non-empty if the unit was
# active before this deploy stopped it.
offer_start_service() {
    local unit="$1" was_active="$2" yn
    if [[ ! -t 0 ]]; then
        echo "  (non-interactive shell: start it yourself with: systemctl start ${unit})"
        return 0
    fi
    echo ""
    if [[ -n "$was_active" ]]; then
        echo -e "  ${YELLOW}${unit} was RUNNING before this deploy and was stopped for the upgrade — the node is currently UNPROTECTED.${NC}"
    fi
    echo -ne "${BOLD}  Start ${unit} now? (Y/n)${NC} [Y]: "
    read -r yn || yn=""   # EOF-safe under set -e (a Ctrl-D must not fail the finished deploy)
    if [[ "$yn" != "n" && "$yn" != "N" ]]; then
        if systemctl start "$unit"; then
            if systemctl is-active --quiet "$unit"; then
                ok "${unit} — running"
            else
                warn "${unit} started but is not active — check: journalctl -u ${unit} -n 50"
            fi
        else
            warn "systemctl start ${unit} failed — check: journalctl -u ${unit} -n 50"
        fi
    else
        warn "${unit} NOT started — the node is unprotected until you run: systemctl start ${unit}"
    fi
    if ! systemctl is-enabled "$unit" &>/dev/null; then
        echo -ne "${BOLD}  Enable ${unit} at boot? (Y/n)${NC} [Y]: "
        read -r yn || yn=""   # EOF-safe under set -e
        if [[ "$yn" != "n" && "$yn" != "N" ]]; then
            systemctl enable "$unit" &>/dev/null && ok "${unit} enabled at boot" || warn "systemctl enable ${unit} failed"
        fi
    fi
    return 0
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOLANA_PATH="$HOME/.local/share/solana/install/active_release/bin"

# v0.6.5 (F2): the staked-startup-identity check below HARD FAILS. Allow an explicit operator
# override via the env var or the --allow-staked-startup-identity flag.
ALLOW_STAKED_STARTUP_IDENTITY="${ALLOW_STAKED_STARTUP_IDENTITY:-false}"
for _arg in "$@"; do
    [[ "$_arg" == "--allow-staked-startup-identity" ]] && ALLOW_STAKED_STARTUP_IDENTITY=true
done

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}${CYAN}Solana Failover  ·  PRIMARY  ·  v0.6.10${NC}"
echo -e "  Automatic staked-identity hot-swap for Solana validators"
echo ""
echo -e "  ${DIM}Author:${NC}     zim.one  ·  https://zim.one"
echo -e "  ${DIM}Validator:${NC}  ${CYAN}2zykwzzo1pd3H2oSj5j5SRLTvmpa9Nr2S2Bh8tTVd5Tq${NC}"
echo -e "  ${DIM}Tested on:${NC}  agave & Jito-Solana  3.1.18 / 4.0.1 / 4.1.0"
echo -e "  ${DIM}Networks:${NC}   testnet · mainnet"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
sleep 2

# ========================= BASIC CHECKS =======================================

step "Pre-flight checks"

[[ $EUID -eq 0 ]] && ok "Running as root" || fail "Must run as root"
command -v jq &>/dev/null && ok "jq installed" || fail "jq not found. Run: apt install -y jq"
command -v curl &>/dev/null && ok "curl installed" || fail "curl not found"
[[ -f "$SOLANA_PATH/agave-validator" ]] && ok "agave-validator found" || fail "agave-validator not found"
[[ -f "$SOLANA_PATH/solana-keygen" ]] && ok "solana-keygen found" || fail "solana-keygen not found"
systemctl is-active solana &>/dev/null && ok "solana.service is active" || fail "solana.service is not running"

# v0.6.0: robust ledger detection — live process cmdline (untruncated), then systemd ExecStart.
LEDGER=""
_vpid=$(pgrep -x agave-validator 2>/dev/null | head -1 || true)
if [[ -n "$_vpid" && -r "/proc/$_vpid/cmdline" ]]; then
    LEDGER=$(tr '\0' ' ' < "/proc/$_vpid/cmdline" | sed -nE 's/.*--ledger[[:space:]=]+([^[:space:]]+).*/\1/p' | head -1)
fi
if [[ -z "$LEDGER" ]]; then
    LEDGER=$(systemctl show solana -p ExecStart --value 2>/dev/null | sed -nE 's/.*--ledger[[:space:]=]+([^[:space:]]+).*/\1/p' | head -1)
fi
[[ -n "$LEDGER" ]] && ok "Ledger: $LEDGER" || warn "Ledger not auto-detected (set LEDGER_PATH in env if needed)"

# Check for existing config
EXISTING_ENV=""
[[ -f /opt/solana-failover/failover.env ]] && EXISTING_ENV="/opt/solana-failover/failover.env"

if [[ -n "$EXISTING_ENV" ]]; then
    echo ""
    warn "Existing config found at $EXISTING_ENV"
    echo -ne "  Load existing values as defaults? (Y/n): "
    read -r yn
    if [[ "$yn" != "n" && "$yn" != "N" ]]; then
        # shellcheck disable=SC1090
        source "$EXISTING_ENV"
        ok "Loaded existing config"
    fi
fi

sleep 1

# ========================= INTERACTIVE CONFIG =================================

step "Configuration"
echo ""
echo -e "  ${BOLD}${CYAN}Press Enter to accept default values in [brackets].${NC}"
sleep 4
echo ""

# --- Node ---
# v0.6.5 (F5): restrict NODE_NAME to a safe charset so it can't break the env shell syntax, the
# Telegram HTML, or the ntfy Title header. Re-prompt until valid.
_NODE_NAME_RE='^[A-Za-z0-9 ._-]+$'
ask "Node name (shown in alerts)" "${NODE_NAME:-MY_VALIDATOR}"
CFG_NODE_NAME="$REPLY"
while ! [[ "$CFG_NODE_NAME" =~ $_NODE_NAME_RE ]]; do
    warn "Node name may contain only letters, digits, space, dot, underscore, hyphen (got '$CFG_NODE_NAME')"
    ask "Node name (shown in alerts)" "MY_VALIDATOR"
    CFG_NODE_NAME="$REPLY"
done

# v0.6.1 (F10): frankendancer is experimental — agave is the supported path for now.
echo -e "  ${DIM}agave and Jito-Solana are both supported (Jito runs on agave). frankendancer is experimental.${NC}"
ask_choice "Validator type" "${VALIDATOR_TYPE:-agave}" "agave" "frankendancer"
CFG_VALIDATOR_TYPE="$REPLY"

echo ""

# --- Keypairs ---
echo -e "  ${BOLD}${CYAN}Keypair paths${NC}"

ask_path "Staked keypair" "${STAKED_KEYPAIR:-/root/solana/mainnet-validator-keypair.json}" "true"
CFG_STAKED="$REPLY"

ask_path "Unstaked keypair" "${UNSTAKED_KEYPAIR:-/root/solana/unstaked-identity.json}" "true"
CFG_UNSTAKED="$REPLY"

# Validate and show pubkeys
if [[ -f "$CFG_STAKED" ]]; then
    STAKED_PUB=$("$SOLANA_PATH/solana-keygen" pubkey "$CFG_STAKED" 2>/dev/null) || true
    [[ -n "$STAKED_PUB" ]] && ok "Staked pubkey:   $STAKED_PUB"
fi
# v0.6.1 (F8): hard-fail if a pubkey can't be derived — otherwise the staked!=unstaked
# guard below is silently skipped and a misconfigured pair slips through.
[[ -z "${STAKED_PUB:-}" ]] && fail "cannot derive staked pubkey from $CFG_STAKED"
if [[ -f "$CFG_UNSTAKED" ]]; then
    UNSTAKED_PUB=$("$SOLANA_PATH/solana-keygen" pubkey "$CFG_UNSTAKED" 2>/dev/null) || true
    [[ -n "$UNSTAKED_PUB" ]] && ok "Unstaked pubkey: $UNSTAKED_PUB"
fi
[[ -z "${UNSTAKED_PUB:-}" ]] && fail "cannot derive unstaked pubkey from $CFG_UNSTAKED"
if [[ "$STAKED_PUB" == "$UNSTAKED_PUB" ]]; then
    fail "Staked and unstaked pubkeys are THE SAME!"
fi

# v0.6.1 (F5) / v0.6.5 (F2): the validator's startup --identity must be the UNSTAKED keypair so a
# solana.service restart fails safe to NOT voting. Parse the live cmdline (then systemd ExecStart)
# and — v0.6.5 — HARD FAIL (not just warn) if it resolves to the staked key, unless the operator
# explicitly acks with --allow-staked-startup-identity / ALLOW_STAKED_STARTUP_IDENTITY=true.
STARTUP_IDENTITY=""
if [[ -n "${_vpid:-}" && -r "/proc/$_vpid/cmdline" ]]; then
    STARTUP_IDENTITY=$(tr '\0' ' ' < "/proc/$_vpid/cmdline" | sed -nE 's/.*--identity[[:space:]=]+([^[:space:]]+).*/\1/p' | head -1)
fi
if [[ -z "$STARTUP_IDENTITY" ]]; then
    STARTUP_IDENTITY=$(systemctl show solana -p ExecStart --value 2>/dev/null | sed -nE 's/.*--identity[[:space:]=]+([^[:space:]]+).*/\1/p' | head -1)
fi
if [[ -n "$STARTUP_IDENTITY" && -f "$STARTUP_IDENTITY" ]]; then
    STARTUP_IDENTITY_PUB=$("$SOLANA_PATH/solana-keygen" pubkey "$STARTUP_IDENTITY" 2>/dev/null) || true
    if [[ "${STARTUP_IDENTITY_PUB:-}" == "$STAKED_PUB" ]]; then
        if [[ "$ALLOW_STAKED_STARTUP_IDENTITY" == "true" ]]; then
            warn "⚠️ Validator startup --identity is STAKED — proceeding ONLY because --allow-staked-startup-identity was given. A solana.service restart boots this node VOTING (double-sign-on-restart). Repoint the startup --identity to the UNSTAKED key (Anza identity.json symlink) ASAP."
        else
            fail "Validator startup --identity is the STAKED key: a solana.service restart would boot this node VOTING (double-sign-on-restart). Set the startup --identity to the UNSTAKED keypair (Anza identity.json symlink recommended), or re-run with --allow-staked-startup-identity to override."
        fi
    elif [[ -n "${STARTUP_IDENTITY_PUB:-}" ]]; then
        ok "Startup --identity is not the staked key — fail-safe"
    fi
fi

echo ""

# --- Three-Tier RPC ---
echo -e "  ${BOLD}${CYAN}RPC Configuration (LOCAL-first)${NC}"
echo -e "  ${DIM}Normal cycle uses LOCAL RPC only (free, fast).${NC}"
echo -e "  ${DIM}Paid/public RPCs called only for confirmation when a problem is detected.${NC}"
sleep 1
echo ""

ask "Tier 1 — Local RPC" "${LOCAL_RPC:-http://127.0.0.1:8899}"
CFG_LOCAL_RPC="$REPLY"

ask "Tier 2 — Paid RPC — any provider (e.g. Alchemy / Helius / Triton / QuikNode)" "${TIER2_RPC:-}"
CFG_TIER2_RPC="$REPLY"

ask "Tier 3 — Public RPC" "${TIER3_RPC:-https://api.mainnet-beta.solana.com}"
CFG_TIER3_RPC="$REPLY"

# v0.6.9 (M8): Tier 2 and Tier 3 must be DISTINCT providers — identical URLs silently void the
# two-vantage independence every tiered confirmation relies on. Re-prompt until distinct (or one empty).
_norm_rpc_url() { local u="$1"; while [[ "$u" == */ ]]; do u="${u%/}"; done; printf '%s' "$u"; }
while [[ -n "$CFG_TIER2_RPC" && -n "$CFG_TIER3_RPC" && "$(_norm_rpc_url "$CFG_TIER2_RPC")" == "$(_norm_rpc_url "$CFG_TIER3_RPC")" ]]; do
    warn "Tier 2 and Tier 3 are the SAME URL — that is a single vantage point; the confirmations would not be independent. Enter a DIFFERENT Tier 3 (or leave one empty)."
    ask "Tier 3 — Public RPC" "https://api.mainnet-beta.solana.com"
    CFG_TIER3_RPC="$REPLY"
done

echo ""

# --- Vote pubkey ---
echo -e "  ${BOLD}${CYAN}Vote account${NC}"
VOTE_AUTO=""
if [[ -f "/root/solana/vote-account-keypair.json" ]]; then
    VOTE_AUTO=$("$SOLANA_PATH/solana-keygen" pubkey "/root/solana/vote-account-keypair.json" 2>/dev/null) || true
fi
ask "Vote pubkey (auto-detected or paste)" "${VOTE_PUBKEY:-$VOTE_AUTO}"
CFG_VOTE_PUBKEY="$REPLY"
# v0.6.7 (N7): VOTE_PUBKEY is REQUIRED — the N6 egress-only self-fence (shipped ON via
# SELF_FENCE_VOTE_LAG_*) reads our own vote account's lastVote; without it the daemon refuses to start
# (a blank one would silently disable N6 and leave the egress-only hole open). Re-prompt until set.
# (To intentionally run without it, set SELF_FENCE_VOTE_LAG_SLOTS=0 in the generated env to disable N6.)
while [[ -z "$CFG_VOTE_PUBKEY" ]]; do
    warn "VOTE_PUBKEY is required for the N6 egress-only self-fence (and for rpc recovery) — paste your vote account pubkey."
    ask "Vote pubkey (auto-detected or paste)" "$VOTE_AUTO"
    CFG_VOTE_PUBKEY="$REPLY"
done

echo ""

# --- Thresholds ---
echo -e "  ${BOLD}${CYAN}Thresholds${NC}"

ask_numeric "Check interval — normal (seconds, poll cadence)" "${CHECK_INTERVAL:-3}" 1
CFG_CHECK_INTERVAL="$REPLY"

ask_numeric "Check interval — turbo (seconds, when delinquency detected)" "${TURBO_INTERVAL:-1}" 1
CFG_TURBO_INTERVAL="$REPLY"

ask_numeric "Internet retries before switch (connectivity confirms)" "${CONNECTIVITY_RETRIES:-3}" 1
CFG_CONN_RETRIES="$REPLY"

ask_numeric "Delinquency retries (Tier 1 confirm count)" "${DELINQUENCY_RETRIES:-5}" 1
CFG_DELINQ_RETRIES="$REPLY"

echo -e "  ${DIM}Advanced/optional — demote if OUR OWN vote falls this many slots behind. Leave 0 unless you know you need it.${NC}"
ask_numeric "Max own-vote latency before switch (slots, 0=off)" "${MAX_VOTE_LATENCY:-0}" 0
CFG_MAX_LATENCY="$REPLY"

echo ""
echo -e "  ${BOLD}${CYAN}Sliding window (DDoS protection)${NC}"
echo -e "  ${DIM}Instead of '5 consecutive fails' (which resets on a single OK),${NC}"
echo -e "  ${DIM}the window tracks the last N checks. If most are delinquent → switch.${NC}"
echo -e "  ${DIM}This catches DDoS flickering where the node goes down/up/down/up.${NC}"
echo ""
echo -e "  ${DIM}Example: window 10, threshold 7 → switch if 7 out of last 10 checks fail.${NC}"
echo -e "  ${DIM}Recommended: 10/7 (default). Lower threshold = more sensitive.${NC}"
sleep 1
echo ""

ask "Window size (last N checks tracked)" "${DELINQUENCY_WINDOW_SIZE:-10}"
CFG_WINDOW_SIZE="$REPLY"

ask "Window threshold (delinquent count to trigger)" "${DELINQUENCY_WINDOW_THRESHOLD:-7}"
CFG_WINDOW_THRESHOLD="$REPLY"

# v0.6.1 (F6): validate window bounds (1<=threshold<=size). threshold>size would
# silently disable failover; size=0 triggers on an empty window. Re-prompt until valid.
# Single-line [[ ]] (bash 3.2 rejects backslash continuation inside the brackets); the
# comparisons use $((10#…)) so a leading-zero entry (e.g. 08) isn't parsed as octal —
# bash 3.2 would otherwise error "value too great for base" and the loop would never exit.
while ! [[ "$CFG_WINDOW_SIZE" =~ ^[0-9]+$ && "$CFG_WINDOW_THRESHOLD" =~ ^[0-9]+$ && $((10#$CFG_WINDOW_THRESHOLD)) -ge 1 && $((10#$CFG_WINDOW_SIZE)) -ge $((10#$CFG_WINDOW_THRESHOLD)) ]]; do
    warn "Invalid window: require 1<=threshold<=size (got ${CFG_WINDOW_THRESHOLD}/${CFG_WINDOW_SIZE})"
    ask "Window size (last N checks)" "10"; CFG_WINDOW_SIZE="$REPLY"
    ask "Window threshold (how many delinquent to trigger)" "7"; CFG_WINDOW_THRESHOLD="$REPLY"
done
# Normalize to base-10 so a leading-zero entry is stored in the env as a plain decimal.
CFG_WINDOW_SIZE=$((10#$CFG_WINDOW_SIZE)); CFG_WINDOW_THRESHOLD=$((10#$CFG_WINDOW_THRESHOLD))

echo ""
echo -e "  ${BOLD}${CYAN}Heartbeat${NC} ${DIM}— periodic 'I'm alive' log entry with stats and ping results.${NC}"
ask_numeric "Heartbeat interval (seconds)" "${HEARTBEAT_INTERVAL:-60}" 1
CFG_HEARTBEAT="$REPLY"

echo ""

# --- Safety ---
echo -e "  ${BOLD}${CYAN}Safety${NC}"

ask_choice "DRY RUN mode" "${DRY_RUN:-true}" "true" "false"
CFG_DRY_RUN="$REPLY"

# v0.6.1 (F4): "auto" removed — it is a reserved future feature and the main script
# now hard-rejects RECOVERY_MODE=auto at startup. Offer only manual/rpc.
ask_choice "Recovery mode" "${RECOVERY_MODE:-manual}" "manual" "rpc"
CFG_RECOVERY_MODE="$REPLY"

echo ""

# --- Telegram ---
echo -e "  ${BOLD}${CYAN}Telegram notifications${NC} ${DIM}(optional)${NC}"

ask_choice "Enable Telegram (optional)" "${TG_ENABLED:-true}" "true" "false"
CFG_TG_ENABLED="$REPLY"

if [[ "$CFG_TG_ENABLED" == "true" ]]; then
    ask "Bot token (BOTID:BOTKEY)" "${TG_BOT_TOKEN:-}"
    CFG_TG_TOKEN="$REPLY"

    ask "Chat ID" "${TG_CHAT_ID:-}"
    CFG_TG_CHAT="$REPLY"
else
    CFG_TG_TOKEN=""
    CFG_TG_CHAT=""
fi

echo ""

# --- Webhook (ntfy.sh) ---
echo -e "  ${BOLD}${CYAN}Push notifications via ntfy.sh${NC} ${DIM}(optional)${NC}"
echo -e "  ${DIM}ntfy.sh is a free push service — no signup needed.${NC}"
echo -e "  ${DIM}A private channel will be auto-generated for you.${NC}"
sleep 1
echo ""

ask_choice "Enable ntfy.sh push (optional)" "true" "true" "false"
CFG_NTFY_ENABLED="$REPLY"

if [[ "$CFG_NTFY_ENABLED" == "true" ]]; then
    # Generate or reuse channel
    if [[ -n "${WEBHOOK_URL:-}" && "$WEBHOOK_URL" == *"ntfy.sh"* ]]; then
        NTFY_DEFAULT="$WEBHOOK_URL"
    else
        NTFY_RANDOM=$(openssl rand -hex 8 2>/dev/null) || NTFY_RANDOM=$(head -c 8 /dev/urandom | od -A n -t x1 | tr -d ' \n') || NTFY_RANDOM="$RANDOM$RANDOM"
        NTFY_DEFAULT="https://ntfy.sh/solana-failover-${NTFY_RANDOM}"
    fi

    echo -e "  ${DIM}The default channel URL is a randomly-generated private channel (nobody can guess it).${NC}"
    echo -e "  ${DIM}How ntfy works / self-hosting: https://docs.ntfy.sh/${NC}"
    ask "ntfy.sh channel URL" "$NTFY_DEFAULT"
    CFG_WEBHOOK_URL="$REPLY"

    # Send test push
    echo ""
    echo -e "  Sending test notification..."
    # shellcheck disable=SC2034  # output captured for potential debug; only the exit code is checked
    NTFY_TEST=$(curl -s -m 10 -X POST "$CFG_WEBHOOK_URL" \
        -H "Title: [${CFG_NODE_NAME}] Failover v0.6.9 — deploy test" \
        -H "Priority: urgent" \
        -H "Tags: white_check_mark" \
        -d "If you see this, ntfy.sh is working. Subscribe to this channel in the ntfy app." 2>&1)

    if [[ $? -eq 0 ]]; then
        ok "Test push sent to: $CFG_WEBHOOK_URL"
        echo ""
        echo -e "  ${BOLD}${CYAN}Get alerts on your phone${NC} ${DIM}(optional)${NC}"
        echo -e "    ${DIM}1.${NC}  Install the ntfy app  ${DIM}·${NC}  Android (Play Store) / iOS (App Store)"
        echo -e "    ${DIM}2.${NC}  Tap  +  →  Subscribe to topic"
        echo -e "    ${DIM}3.${NC}  Topic:  ${CYAN}${CFG_WEBHOOK_URL#https://ntfy.sh/}${NC}"
        echo -e "  ${DIM}You should already see the ✅ test message above.${NC}"
        echo ""
        echo -ne "${BOLD}  Press Enter when subscribed (or skip)...${NC}"
        read -r
    else
        warn "ntfy.sh test failed — check your network"
    fi
else
    CFG_WEBHOOK_URL=""
fi

# Generic webhook (Slack/Discord) — only if ntfy disabled
if [[ -z "$CFG_WEBHOOK_URL" ]]; then
    ask "Custom webhook URL (Slack/Discord, empty to skip)" "${WEBHOOK_URL:-}"
    CFG_WEBHOOK_URL="$REPLY"
fi

# --- External heartbeat watchdog (v0.6.4, "dead-man's switch") ---
echo ""
echo -e "  ${BOLD}${CYAN}External heartbeat watchdog${NC} ${DIM}(optional)${NC}"
echo -e "  ${DIM}This node pings an external monitor on a schedule. If the pings STOP — because this${NC}"
echo -e "  ${DIM}monitor process died, or the host or network dropped — the monitor pages you.${NC}"
echo -e "  ${DIM}It catches failures the Telegram/ntfy event alerts can't send (a dead node stays silent).${NC}"
echo -e "  ${DIM}Any alert-on-absence service works, e.g.:${NC}"
echo -e "    ${CYAN}healthchecks.io${NC}  ${DIM}·${NC}  ${CYAN}Uptime Kuma${NC}  ${DIM}·${NC}  ${CYAN}cronitor${NC}"
echo -e "  ${DIM}Use a DISTINCT URL per node (do NOT reuse the STANDBY's watchdog URL).${NC}"
sleep 1
ask "Heartbeat watchdog URL (this node only, empty to disable)" "${HEARTBEAT_URL:-}"
CFG_HEARTBEAT_URL="$REPLY"
CFG_HEARTBEAT_PING_INTERVAL=""
if [[ -n "$CFG_HEARTBEAT_URL" ]]; then
    ask "Heartbeat ping cadence (seconds, empty = same as status interval ${CFG_HEARTBEAT})" "${HEARTBEAT_PING_INTERVAL:-}"
    CFG_HEARTBEAT_PING_INTERVAL="$REPLY"
fi

sleep 1

# ========================= GENERATE CONFIG ====================================

step "Generating configuration"

# v0.6.9 (Phase A, 2j): simple staged progress dots so the step visibly does work (no new deps).
echo -ne "  Writing config"
for _dot in 1 2 3 4 5; do echo -n "."; sleep 0.3; done
echo ""

mkdir -p /opt/solana-failover

cat > /opt/solana-failover/failover.env << ENVEOF
# ============================================================================
# Solana PRIMARY Node Failover v0.6.9 (LOCAL-first, 3-Tier RPC)
# Generated by deploy script on $(date -u +"%F %T UTC")
# After changes: systemctl restart solana-failover
# ============================================================================

# --- Node ---
NODE_NAME=$(_envq "${CFG_NODE_NAME}")
VALIDATOR_TYPE=$(_envq "${CFG_VALIDATOR_TYPE}")

# --- Keypair paths ---
STAKED_KEYPAIR=$(_envq "${CFG_STAKED}")
UNSTAKED_KEYPAIR=$(_envq "${CFG_UNSTAKED}")
SOLANA_PATH="\$HOME/.local/share/solana/install/active_release/bin"
LEDGER_PATH=""

# --- Three-Tier RPC ---
LOCAL_RPC=$(_envq "${CFG_LOCAL_RPC}")
TIER2_RPC=$(_envq "${CFG_TIER2_RPC}")
TIER3_RPC=$(_envq "${CFG_TIER3_RPC}")

# --- Thresholds ---
CHECK_INTERVAL=${CFG_CHECK_INTERVAL}
TURBO_INTERVAL=${CFG_TURBO_INTERVAL}
CONNECTIVITY_RETRIES=${CFG_CONN_RETRIES}
DELINQUENCY_RETRIES=${CFG_DELINQ_RETRIES}
MAX_VOTE_LATENCY=${CFG_MAX_LATENCY}

# --- Sliding window (DDoS protection) ---
DELINQUENCY_WINDOW_SIZE=${CFG_WINDOW_SIZE}
DELINQUENCY_WINDOW_THRESHOLD=${CFG_WINDOW_THRESHOLD}
HEARTBEAT_INTERVAL=${CFG_HEARTBEAT}

# --- Safety ---
DRY_RUN=${CFG_DRY_RUN}
RECOVERY_MODE=$(_envq "${CFG_RECOVERY_MODE}")

# --- Recovery (only for RECOVERY_MODE="rpc") ---
VOTE_PUBKEY=$(_envq "${CFG_VOTE_PUBKEY}")
RECOVERY_DELAY=300
RECOVERY_CHECKS=3
RECOVERY_CHECK_INTERVAL=30

# v0.6.3 (Block 2): rpc-recovery vote-liveness fence (re-take only if nobody is voting the
# staked identity). Only consulted in RECOVERY_MODE="rpc".
VOTE_LIVENESS_EPSILON=2
VOTE_LIVENESS_MIN_INTERVAL=10

# --- PRIMARY self-fence / "vote lease" (v0.6.3 Block 3) ---
# Drop to UNSTAKED if isolated from the supermajority (LOCAL confirmed slot frozen), so the node
# stops voting during a partition before a heal can double-sign. LOCAL signals only; safe direction
# only. Set PRIMARY_SELF_FENCE=false to disable.
PRIMARY_SELF_FENCE=true
# 30s: PRIMARY drops the staked identity within ~30s of going silent so a spare can take over safely.
# Do NOT raise without raising every spare's EXPECTED_PRIMARY_SELF_FENCE_SECS and TAKEOVER_DELAY by the
# same amount (else the cross-node margin is lost → double-sign).
SELF_FENCE_ISOLATION_SECS=30
SELF_FENCE_MAX_BEHIND=150
# v0.6.5 (F1): demote if LOCAL getSlot(confirmed) is CONTINUOUSLY silent this many seconds while
# staked + a baseline exists (never on a fresh start). 0 = off.
# v0.6.6 (N1): 60 → 30 (PRIMARY relinquishes before any spare's TAKEOVER_DELAY=60). Fail-safe demote;
# more false-fire-prone than 60 — measure local RPC stalls on testnet and raise (with the spare's
# TAKEOVER_DELAY) if twitchy.
# Do NOT raise without raising every spare's EXPECTED_PRIMARY_SELF_FENCE_SECS and TAKEOVER_DELAY by the
# same amount (else the cross-node margin is lost → double-sign).
SELF_FENCE_NOANSWER_SECS=30
# v0.6.7 (N6): egress-only self-fence — "can I BE HEARD?" Demote when our OWN vote account (VOTE_PUBKEY)
# lastVote lags the same-payload cluster-max lastVote (both from one LOCAL getVoteAccounts at
# commitment=processed — v0.6.7 N8) by > SELF_FENCE_VOTE_LAG_SLOTS for >= SELF_FENCE_VOTE_LAG_SECS.
# Catches an egress-only partition (we still RECEIVE blocks — slot advances, getHealth fine — but our
# votes don't land), which the frozen-slot/no-answer checks above are blind to. LOCAL signal only; safe
# direction only. REQUIRES VOTE_PUBKEY (set above) — the daemon refuses to start with it blank while N6
# is armed. Sizing is cross-node margin: lag grows ~2–2.5 slots/s, so demote ≈ SLOTS/rate + SECS ≈ 33s at
# 32 slots — before a worst-case fast spare (~68s). Keep in 24–48 (healthy soak calibrates); too high
# re-opens the egress-only race. Either knob = 0 disables this sub-check.
SELF_FENCE_VOTE_LAG_SLOTS=32
SELF_FENCE_VOTE_LAG_SECS=20
# v0.6.8 (B2): N6 flap hysteresis — CONSECUTIVE healthy cycles (own vote within SLOTS of cluster-max)
# required before the accumulating sustain timer clears. Stops a flapping/intermittent egress (one vote
# burst per < SECS) from re-zeroing the timer every cycle so N6 never fires (the wedged-but-alive hole).
# >= 2 (1/0 = no hysteresis); 3 is the conservative default.
SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
# v0.6.8 (B1): bound the demote/promote set-identity admin-socket calls (the SAME socket get_local_identity
# wraps in \`timeout 8\` — "can hang under load/compaction"). An un-timeout'd demote could freeze the loop
# mid-demote and silently re-open the double-sign gap. >= 8. On a DEMOTE timeout the self-fence escalates
# (below). Uses \`timeout -k 5\` so a SIGTERM-ignoring CLI is SIGKILL'd rather than wedging the loop.
SETIDENTITY_TIMEOUT=15
# v0.6.8 (B1): when a DEMOTE set-identity wedges, hard-stop the validator (systemctl stop, then SIGTERM →
# SIGKILL) and VERIFY it stopped, so the staked identity provably stops voting (a stopped validator cannot
# double-sign). false = alert only, do NOT stop (NOT recommended — re-opens the gap). Never in DRY_RUN or
# on the recovery/promote path.
SELF_FENCE_HARD_STOP=true
# v0.6.9 (H2): when systemctl stop did not cleanly succeed, the unit is masked (--runtime; a reboot
# clears it) before the direct kill, and the down-state is RE-verified after this many seconds (>= the
# unit's RestartSec) so Restart=always cannot silently resurrect a staked-voting validator. Recovery:
# systemctl unmask --runtime solana (the ✅ page names it).
HARD_STOP_REVERIFY_SECS=15

# --- Collision detector (v0.6.9 M5) ---
# While STAKED: compare external gossip's endpoint for the staked pubkey vs our own; 2 consecutive
# mismatches → 🚨 page (throttled). DETECTION-ONLY — never demotes.
COLLISION_CHECK_INTERVAL=60

# --- State persistence (v0.6.9 H3/M10) ---
# Role-specific state file (.../state-primary; legacy .../state migrates once). Self-fence baseline is
# persisted every cycle; restored after a monitor restart only when fresher than STATE_MAX_AGE_SECS and
# only with first-read evidence the stall is continuous.
STATE_MAX_AGE_SECS=900
# Persisted-STAKED + validator unreachable this long at monitor startup → 🚨 page (once).
STARTUP_STAKED_UNREACHABLE_ALERT_SECS=60

# --- Telegram ---
TG_ENABLED=${CFG_TG_ENABLED}
TG_BOT_TOKEN=$(_envq "${CFG_TG_TOKEN}")
TG_CHAT_ID=$(_envq "${CFG_TG_CHAT}")

# --- Webhook ---
WEBHOOK_URL=$(_envq "${CFG_WEBHOOK_URL}")
WEBHOOK_BODY=""

# --- External heartbeat watchdog (v0.6.4, "dead-man's switch") ---
# Alert-on-absence monitor URL for THIS node; empty = off. Distinct URL per node.
HEARTBEAT_URL=$(_envq "${CFG_HEARTBEAT_URL}")
HEARTBEAT_PING_INTERVAL=$(_envq "${CFG_HEARTBEAT_PING_INTERVAL}")
ENVEOF

chmod 600 /opt/solana-failover/failover.env
ok "Config written: /opt/solana-failover/failover.env"

sleep 1

# ========================= COPY SCRIPT ========================================

step "Deploying script"

SCRIPT_FILE="$SCRIPT_DIR/solana-primary-failover.sh"
[[ -f "$SCRIPT_FILE" ]] || fail "solana-primary-failover.sh not found in $SCRIPT_DIR"

cp "$SCRIPT_FILE" /opt/solana-failover/
chmod +x /opt/solana-failover/solana-primary-failover.sh
ok "Script deployed"

bash -n /opt/solana-failover/solana-primary-failover.sh && ok "Script syntax OK" || fail "Syntax error!"
bash -n /opt/solana-failover/failover.env && ok "Config syntax OK" || fail "Config syntax error!"

sleep 1

# ========================= SYSTEMD ============================================

step "Creating systemd service"

cat > /etc/systemd/system/solana-failover.service << 'SERVICEEOF'
[Unit]
Description=Solana PRIMARY Node Failover Protection v0.6.10
After=solana.service
Wants=solana.service

[Service]
Type=simple
User=root
ExecStart=/opt/solana-failover/solana-primary-failover.sh
Restart=always
RestartSec=10
LimitNOFILE=1000000
TimeoutStopSec=15
KillSignal=SIGTERM
StandardOutput=journal
StandardError=journal
SyslogIdentifier=solana-failover

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
ok "Systemd service created"

# Stop old version
# v0.6.9 (M7): remember whether it was running — the end of the deploy offers to start it again.
FAILOVER_WAS_ACTIVE=""
systemctl is-active solana-failover &>/dev/null && { FAILOVER_WAS_ACTIVE=1; systemctl stop solana-failover; ok "Old service stopped (will offer to restart it at the end)"; }

sleep 1

# ========================= TEST CONNECTIVITY ==================================

step "Testing connectivity"

# Tier 1
T1=$(curl -s -m 5 "$CFG_LOCAL_RPC" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
[[ -n "$T1" ]] && ok "Tier 1 (Local):  slot $T1" || warn "Tier 1 (Local):  not ready"

# Tier 2
if [[ -n "$CFG_TIER2_RPC" ]]; then
    T2=$(curl -s -m 10 "$CFG_TIER2_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [[ -n "$T2" ]] && ok "Tier 2 (Paid):   slot $T2" || warn "Tier 2 (Paid):   unreachable"
else
    warn "Tier 2 (Paid):   not configured"
fi

# Tier 3
T3=$(curl -s -m 10 "$CFG_TIER3_RPC" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
[[ -n "$T3" ]] && ok "Tier 3 (Public): slot $T3" || warn "Tier 3 (Public): unreachable"

# Telegram test
if [[ "$CFG_TG_ENABLED" == "true" && -n "$CFG_TG_TOKEN" && -n "$CFG_TG_CHAT" ]]; then
    TG_RESULT=$(curl -s -m 10 -X POST "https://api.telegram.org/bot${CFG_TG_TOKEN}/sendMessage" \
        -d chat_id="$CFG_TG_CHAT" \
        -d text="[${CFG_NODE_NAME}] 🔧 Deploy complete — failover v0.6.9 ready" \
        -d parse_mode="HTML" 2>/dev/null) || true
    echo "$TG_RESULT" | jq -e '.ok' &>/dev/null && ok "Telegram: test message sent" || warn "Telegram: send failed"
fi

sleep 1

# ========================= SUMMARY ============================================

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}${GREEN}✓  DEPLOY COMPLETE${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}${CYAN}Files${NC}"
echo -e "    ${DIM}/opt/solana-failover/solana-primary-failover.sh${NC}"
echo -e "    ${DIM}/opt/solana-failover/failover.env${NC}"
echo -e "    ${DIM}/etc/systemd/system/solana-failover.service${NC}"
echo ""
echo -e "  ${BOLD}${CYAN}Config${NC}"
echo -e "    ${DIM}Node:${NC}         $CFG_NODE_NAME"
echo -e "    ${DIM}DRY_RUN:${NC}      $CFG_DRY_RUN"
echo -e "    ${DIM}Recovery:${NC}     $CFG_RECOVERY_MODE"
echo -e "    ${DIM}Vote pubkey:${NC}  ${CFG_VOTE_PUBKEY:-(not set)}"
echo -e "    ${DIM}Telegram:${NC}     $CFG_TG_ENABLED"
echo -e "    ${DIM}Webhook:${NC}      ${CFG_WEBHOOK_URL:-(not set)}"

sleep 2

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}${CYAN}NEXT STEPS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}1.${NC} Start the service:"
echo -e "     ${DIM}systemctl start solana-failover${NC}"
echo -e "     ${DIM}tail -f /var/log/solana-failover.log${NC}"
echo ""
sleep 1
echo -e "  ${BOLD}2.${NC} Test with a simulated outage (DRY RUN):"
echo -e "     ${DIM}iptables -I OUTPUT 1 ! -o lo -j DROP; sleep 40; iptables -D OUTPUT ! -o lo -j DROP${NC}"
echo ""
sleep 1
echo -e "  ${BOLD}3.${NC} When ready for production:"
echo -e "     ${DIM}sed -i 's/DRY_RUN=true/DRY_RUN=false/' /opt/solana-failover/failover.env${NC}"
echo -e "     ${DIM}systemctl restart solana-failover${NC}"
echo -e "     ${DIM}systemctl enable solana-failover${NC}"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"

# v0.6.9 (M7): don't leave an upgraded node unprotected — offer to start (and enable) right now.
offer_start_service "solana-failover" "$FAILOVER_WAS_ACTIVE"
