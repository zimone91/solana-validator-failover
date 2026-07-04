#!/bin/bash
# ============================================================================
# Solana STANDBY Failover v0.6.9 — Interactive Deploy
# Run on STANDBY node as root.
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

# v0.6.7: cross-node safety recommendations — SINGLE SOURCE OF TRUTH for the deploy-prompt guidance
# below AND the EXPECTED/MARGIN written to the generated env. REC_TAKEOVER_DELAY is DERIVED (not a
# hardcoded 60) so the why-note, the below-rec warning, the generated EXPECTED+MARGIN, and the daemon's
# check_crossnode_timing_safety all agree from one place. These mirror the PRIMARY's shipped self-fence
# worst case (EXPECTED) plus the cross-node margin; raising them requires raising the PRIMARY's
# SELF_FENCE_*_SECS in lock-step (see the EXPECTED/MARGIN comments where the env is generated).
REC_EXPECTED_PRIMARY_SELF_FENCE_SECS=30
REC_SELF_FENCE_MARGIN_SECS=30
REC_TAKEOVER_DELAY=$(( REC_EXPECTED_PRIMARY_SELF_FENCE_SECS + REC_SELF_FENCE_MARGIN_SECS ))

# v0.6.7: calm human nudge (NOT a hard-block — the N1 clamp below still forces the absolute floor) when
# the operator picks a takeover delay under the cross-node-safe floor. Prints a RED line and returns 1
# when it warns; prints nothing and returns 0 at/above REC. A function so it is unit-testable
# (tests/test_installer_guardrails.sh sources it).
warn_if_below_rec_takeover_delay() {
    local val="$1" rec="$2"
    if [[ "$val" =~ ^[0-9]+$ && $((10#$val)) -lt $rec ]]; then
        echo -e "  ${RED}⚠ ${val}s is below the recommended ${rec}s — values this low can let two nodes vote the same identity (double-sign). Keep ≥ ${rec}s unless you have a specific reason.${NC}"
        return 1
    fi
    return 0
}

# v0.6.9 (M7): offer to start (and enable) the failover service at the end of a successful deploy.
# The installer STOPS a running failover service during the upgrade and previously only PRINTED the
# start command — an upgraded node whose operator walked away was left UNPROTECTED. Prompt default is
# Y (start). Non-interactive stdin → keep the old print-only behavior (never auto-start without a
# human). A function so it is unit-testable (tests/test_installer_guardrails.sh sources it).
# $1=unit, $2=non-empty if the unit was active before this deploy stopped it.
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
echo -e "  ${BOLD}${CYAN}Solana Failover  ·  STANDBY / BACKUP  ·  v0.6.9${NC}"
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
[[ -f /opt/solana-failover/failover-standby.env ]] && EXISTING_ENV="/opt/solana-failover/failover-standby.env"

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

# ========================= ROLE SELECTION =====================================

step "Server role"
echo ""
echo -e "  ${BOLD}Choose the role for this server:${NC}"
echo ""
echo -e "  ${GREEN}STANDBY${NC}  — Hot spare. Takes over at ${REC_TAKEOVER_DELAY}s if PRIMARY fails (the PRIMARY"
echo -e "            self-fences at ~30s, plus a 30s cross-node safety margin = ${REC_TAKEOVER_DELAY}s)."
echo -e "            Use for your main backup server in a different DC."
echo ""
echo -e "  ${YELLOW}BACKUP${NC}   — Cold spare. Takes over at 120s, only if BOTH PRIMARY"
echo -e "            and STANDBY are down. Last line of defense."
echo ""
echo -e "  ${BOLD}${CYAN}Recommended 3-node setup:${NC}"
echo ""
echo -e "     ${GREEN}PRIMARY${NC}  ${DIM}──self-fence ~30s──►${NC}  ${GREEN}${BOLD}STANDBY${NC}  ${DIM}──60s──►${NC}  ${YELLOW}BACKUP${NC}"
echo -e "     ${DIM}holds staked, steps down       takes staked       takes staked${NC}"
echo -e "     ${DIM}                                                  (only if STANDBY${NC}"
echo -e "     ${DIM}                                                   is also down)${NC}"
echo ""

ask_choice "Server role" "STANDBY" "STANDBY" "BACKUP"
CFG_ROLE="$REPLY"

# v0.6.9 (Phase A): Simple vs Advanced install mode. Simple uses the verified-safe defaults and
# HIDES the four expert tuning prompts (fast-delinquency, gossip-verify, vote-liveness, Option A) —
# each is still WRITTEN to the .env at its safe default. Advanced exposes every option for tuning.
echo ""
echo -e "  ${BOLD}Install mode:${NC}"
echo -e "  ${GREEN}simple${NC}   — verified-safe defaults; hides expert tuning knobs (recommended)."
echo -e "  ${YELLOW}advanced${NC} — exposes every option (fast-delinquency, gossip/vote-liveness fences, Option A)."
ask_choice "Install mode" "simple" "simple" "advanced"
INSTALL_MODE="$REPLY"
if [[ "$INSTALL_MODE" == "advanced" ]]; then ADVANCED=true; else ADVANCED=false; fi

# Set recommended defaults based on role.
# v0.6.6 (N1): TAKEOVER_DELAY must be >= PRIMARY self-fence worst case (30) + margin (30) = 60 so the
# PRIMARY relinquishes BEFORE this spare can take (no cross-node double-stake). Fast-detect
# (MAX_DELINQUENT_SLOTS=15) shaves the delinquency head-start D — safe, because the invariant does NOT
# rely on D (the binding gate is still TAKEOVER_DELAY).
if [[ "$CFG_ROLE" == "STANDBY" ]]; then
    ROLE_TAKEOVER_DELAY=60
    ROLE_CHECK_INTERVAL=3
    ROLE_GOSSIP_VERIFY=true
    ROLE_MAX_DELINQ_SLOTS=15
    ROLE_NODE_SUFFIX="-STANDBY"
    ok "Role: STANDBY (safe-fast takeover, gossip verified)"
    echo ""
    echo -e "  ${CYAN}Preset: TAKEOVER_DELAY=60s, CHECK_INTERVAL=3s, GOSSIP_VERIFY=true, MAX_DELINQUENT_SLOTS=15${NC}"
else
    ROLE_TAKEOVER_DELAY=120
    ROLE_CHECK_INTERVAL=5
    ROLE_GOSSIP_VERIFY=false
    ROLE_MAX_DELINQ_SLOTS=15
    ROLE_NODE_SUFFIX="-BACKUP"
    ok "Role: BACKUP (delayed takeover, gossip OFF, vote-liveness fence ON)"
    echo ""
    echo -e "  ${CYAN}Preset: TAKEOVER_DELAY=120s, CHECK_INTERVAL=5s, GOSSIP_VERIFY=false, MAX_DELINQUENT_SLOTS=15${NC}"
    echo ""
    echo -e "  ${YELLOW}Why GOSSIP_VERIFY=false for BACKUP?${NC}"
    echo -e "  If STANDBY took identity and then crashed, gossip still shows staked on"
    echo -e "  STANDBY's endpoint for 5-10 min — gossip-verify ON would block BACKUP."
    echo -e "  So gossip is OFF, but ${BOLD}vote-liveness (v0.6.2) is ON${NC}: BACKUP takes over"
    echo -e "  only once the staked vote account stops advancing (the crashed STANDBY"
    echo -e "  is no longer voting). A real fence — no longer a blind takeover."
fi
echo ""

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
ask "Node name (shown in alerts)" "${NODE_NAME:-MY_VALIDATOR${ROLE_NODE_SUFFIX}}"
CFG_NODE_NAME="$REPLY"
while ! [[ "$CFG_NODE_NAME" =~ $_NODE_NAME_RE ]]; do
    warn "Node name may contain only letters, digits, space, dot, underscore, hyphen (got '$CFG_NODE_NAME')"
    ask "Node name (shown in alerts)" "MY_VALIDATOR${ROLE_NODE_SUFFIX}"
    CFG_NODE_NAME="$REPLY"
done

# v0.6.1 (F10): frankendancer is experimental — agave is the supported path for now.
echo -e "  ${DIM}agave and Jito-Solana are both supported (Jito runs on agave). frankendancer is experimental.${NC}"
ask_choice "Validator type" "${VALIDATOR_TYPE:-agave}" "agave" "frankendancer"
CFG_VALIDATOR_TYPE="$REPLY"

echo ""

# --- Keypairs ---
echo -e "  ${BOLD}${CYAN}Keypair paths${NC}"
echo -e "  ${YELLOW}STAKED${NC} = shared identity (same on PRIMARY and STANDBY)"
echo -e "  ${YELLOW}UNSTAKED${NC} = this node's own identity (MUST be unique!)"
echo ""

ask_path "Staked keypair (shared)" "${STAKED_KEYPAIR:-/root/solana/mainnet-validator-keypair.json}" "true"
CFG_STAKED="$REPLY"

ask_path "Unstaked keypair (this node)" "${UNSTAKED_KEYPAIR:-/root/solana/unstaked-standby.json}" "true"
CFG_UNSTAKED="$REPLY"

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

# v0.6.9 (M8): Tier 2 and Tier 3 must be DISTINCT providers — identical URLs silently void A6's
# two-vantage requirement and the liveness fence's fallback independence. Re-prompt until distinct
# (or one empty). The daemon also warns at startup and fail-closes the fast-path on equality.
_norm_rpc_url() { local u="$1"; while [[ "$u" == */ ]]; do u="${u%/}"; done; printf '%s' "$u"; }
while [[ -n "$CFG_TIER2_RPC" && -n "$CFG_TIER3_RPC" && "$(_norm_rpc_url "$CFG_TIER2_RPC")" == "$(_norm_rpc_url "$CFG_TIER3_RPC")" ]]; do
    warn "Tier 2 and Tier 3 are the SAME URL — that is a single vantage point; the two-vantage checks (A6, liveness fallback) would not be independent. Enter a DIFFERENT Tier 3 (or leave one empty)."
    ask "Tier 3 — Public RPC" "https://api.mainnet-beta.solana.com"
    CFG_TIER3_RPC="$REPLY"
done

echo ""

# --- Vote pubkey ---
echo -e "  ${BOLD}${CYAN}Vote account (REQUIRED for STANDBY)${NC}"
VOTE_AUTO=""
if [[ -f "/root/solana/vote-account-keypair.json" ]]; then
    VOTE_AUTO=$("$SOLANA_PATH/solana-keygen" pubkey "/root/solana/vote-account-keypair.json" 2>/dev/null) || true
fi
ask "Vote pubkey" "${VOTE_PUBKEY:-$VOTE_AUTO}"
CFG_VOTE_PUBKEY="$REPLY"
# v0.5.9: hard fail — main script requires VOTE_PUBKEY; better to fail early in deploy
[[ -z "$CFG_VOTE_PUBKEY" ]] && fail "VOTE_PUBKEY is required for STANDBY (auto-detected from /root/solana/vote-account-keypair.json or paste manually)"

echo ""

# --- Thresholds ---
echo -e "  ${BOLD}${CYAN}Thresholds${NC}"

ask_numeric "Check interval — normal (seconds, poll cadence)" "${CHECK_INTERVAL:-$ROLE_CHECK_INTERVAL}" 1
CFG_CHECK_INTERVAL="$REPLY"

ask_numeric "Check interval — turbo (seconds, when delinquency detected)" "${TURBO_INTERVAL:-1}" 1
CFG_TURBO_INTERVAL="$REPLY"

ask_numeric "Delinquency retries (legacy confirm count)" "${DELINQUENCY_RETRIES:-5}" 1
CFG_DELINQ_RETRIES="$REPLY"

# v0.6.7: calm one-line "why" + a RED nudge if the operator goes below the cross-node-safe floor.
echo -e "  ${CYAN}Recommended ${REC_TAKEOVER_DELAY}s — it lets the PRIMARY step down before a spare takes over, so two nodes never vote the same identity (double-sign).${NC}"
ask_numeric "Takeover delay (seconds of sustained delinquency)" "${TAKEOVER_DELAY:-$ROLE_TAKEOVER_DELAY}" 1
CFG_TAKEOVER_DELAY="$REPLY"
warn_if_below_rec_takeover_delay "$CFG_TAKEOVER_DELAY" "$REC_TAKEOVER_DELAY" || true   # nudge only (N1 clamp below enforces the floor)

ask_numeric "Local health max behind (slots; own-node lag tolerance)" "${LOCAL_HEALTH_MAX_BEHIND:-100}" 0
CFG_MAX_BEHIND="$REPLY"

echo ""
echo -e "  ${BOLD}${CYAN}Sliding window (DDoS protection)${NC}"
echo -e "  ${DIM}Instead of '5 consecutive fails' (which resets on a single OK),${NC}"
echo -e "  ${DIM}the window tracks the last N checks. If most are delinquent → takeover.${NC}"
echo -e "  ${DIM}This catches DDoS flickering where PRIMARY goes down/up/down/up.${NC}"
echo ""
echo -e "  ${DIM}Example: window 10, threshold 7 → takeover if 7 out of last 10 checks fail.${NC}"
echo -e "  ${DIM}Recommended: 10/7 (default). Lower threshold = more sensitive.${NC}"
sleep 1
echo ""

ask "Window size (last N checks tracked)" "${DELINQUENCY_WINDOW_SIZE:-10}"
CFG_WINDOW_SIZE="$REPLY"

ask "Window threshold (delinquent count to trigger)" "${DELINQUENCY_WINDOW_THRESHOLD:-7}"
CFG_WINDOW_THRESHOLD="$REPLY"

# v0.6.1 (F6): validate window bounds (1<=threshold<=size). threshold>size would
# silently disable takeover; size=0 triggers on an empty window. Re-prompt until valid.
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

# v0.6.9 (Phase A): expert knob — SHOWN only in advanced mode; simple uses the safe preset 15.
if [[ "$ADVANCED" == "true" ]]; then
echo ""
echo -e "  ${BOLD}Fast delinquency detection:${NC}"
echo -e "  By default, Solana RPC marks a validator 'delinquent' after ~150 slots (~60s)."
echo -e "  With this option, STANDBY checks lastVote directly — if it's N slots behind,"
echo -e "  it counts as delinquent immediately. Much faster detection."
echo -e "  ${YELLOW}Preset 15 (v0.6.6): shaves the detection head-start D. Safe — the cross-node${NC}"
echo -e "  ${YELLOW}timing invariant does NOT rely on D (the binding gate is TAKEOVER_DELAY). 0 = off.${NC}"
echo ""

# v0.6.7: why-note only — detection SPEED, not a double-sign value, so no danger warning either way.
echo -e "  ${CYAN}Recommended 15 — detects a stopped PRIMARY quickly without affecting safety; 0 disables fast-detect (slower failover).${NC}"
ask_numeric "Fast delinquency (slots behind, 0=off, 15=fast preset)" "${MAX_DELINQUENT_SLOTS:-$ROLE_MAX_DELINQ_SLOTS}" 0
CFG_MAX_DELINQ_SLOTS="$REPLY"
else
    CFG_MAX_DELINQ_SLOTS=15   # simple-mode safe default (verified preset)
fi

echo ""
echo -e "  ${BOLD}${CYAN}Heartbeat${NC} ${DIM}— periodic 'I'm alive' log entry with monitoring stats.${NC}"
ask_numeric "Heartbeat interval (seconds)" "${HEARTBEAT_INTERVAL:-60}" 1
CFG_HEARTBEAT="$REPLY"

echo ""

# --- Safety ---
echo -e "  ${BOLD}${CYAN}Safety${NC}"

ask_choice "DRY RUN mode" "${DRY_RUN:-true}" "true" "false"
CFG_DRY_RUN="$REPLY"

# v0.6.9 (Phase A): expert knob — SHOWN only in advanced mode; simple uses the role preset
# ($ROLE_GOSSIP_VERIFY: true for STANDBY, false for BACKUP per its documented gossip-linger rationale).
if [[ "$ADVANCED" == "true" ]]; then
    ask_choice "Gossip verification" "${GOSSIP_VERIFY:-$ROLE_GOSSIP_VERIFY}" "true" "false"
    CFG_GOSSIP_VERIFY="$REPLY"
else
    CFG_GOSSIP_VERIFY="$ROLE_GOSSIP_VERIFY"   # simple-mode safe default (role preset; STANDBY=true)
fi

# v0.6.2 (C2) / v0.6.3 (Block 1): the authoritative split-brain fence (is the staked vote account
# voting?). REQUIRED in v0.6.3 — the daemon refuses to start with it off unless an explicit unfenced
# override is accepted. Gossip is advisory only now (a staked pubkey lingers ~48h in gossip).
# v0.6.9 (Phase A): expert knob — SHOWN only in advanced mode; simple keeps the fence ON (safest+fastest).
CFG_ALLOW_UNFENCED=false
if [[ "$ADVANCED" == "true" ]]; then
    ask_choice "Vote-liveness fence (REQUIRED — leave ON)" "${VOTE_LIVENESS_VERIFY:-true}" "true" "false"
    CFG_VOTE_LIVENESS="$REPLY"
    if [[ "$CFG_VOTE_LIVENESS" != "true" ]]; then
        warn "Vote-liveness is the authoritative split-brain fence. With it OFF the daemon REFUSES to start"
        warn "unless you accept an UNFENCED takeover — there is then NO double-sign protection at all."
        ask_choice "Accept UNFENCED takeover (dangerous)?" "false" "false" "true"
        CFG_ALLOW_UNFENCED="$REPLY"
    fi
else
    CFG_VOTE_LIVENESS=true   # simple-mode safe default (authoritative split-brain fence ON)
fi

# v0.6.5 (F4): with vote-liveness ON, TAKEOVER_DELAY must be >= the liveness MIN_INTERVAL (the
# generated env uses the script default of 10s) so the second lastVote sample is reachable within the
# delay. Raise it with a warning rather than writing a config the daemon would refuse to start with.
if [[ "$CFG_VOTE_LIVENESS" == "true" && $((10#${CFG_TAKEOVER_DELAY})) -lt 10 ]]; then
    warn "TAKEOVER_DELAY=${CFG_TAKEOVER_DELAY}s < VOTE_LIVENESS_MIN_INTERVAL=10s — the liveness 2nd sample wouldn't be reachable in time; raising TAKEOVER_DELAY to 10s."
    CFG_TAKEOVER_DELAY=10
fi

# v0.6.6 (N1): cross-node timing safety — the current holder must relinquish staked BEFORE this spare
# can take, or both hold staked across a heal → double-sign. Raise TAKEOVER_DELAY (with a warning)
# rather than emit an unsafe config; the daemon also refuses to start below the floor.
# v0.6.7: derive from the REC_* single source of truth so the prompt note/warning above and this
# clamp use one set of numbers (REC_TAKEOVER_DELAY == EXPECTED + MARGIN).
CFG_EXPECTED_PRIMARY_SELF_FENCE_SECS=$REC_EXPECTED_PRIMARY_SELF_FENCE_SECS
CFG_SELF_FENCE_MARGIN_SECS=$REC_SELF_FENCE_MARGIN_SECS
# v0.6.9 (Phase-B2): a BACKUP's cross-node floor AND its Option-A stagger both need the STANDBY's
# TAKEOVER_DELAY. The daemon now REFUSES to start when a BACKUP has no positive STANDBY_TAKEOVER_DELAY
# (it cannot compute the take-visibility floor), so collect it in ALL modes — not only under Option A.
CFG_STANDBY_TAKEOVER_DELAY=""
if [[ "$CFG_ROLE" == "BACKUP" ]]; then
    echo -e "  ${YELLOW}A BACKUP takes over only AFTER the STANDBY has. Enter the STANDBY's TAKEOVER_DELAY${NC}"
    echo -e "  ${YELLOW}(NOT this BACKUP's) so this node waits until the STANDBY's take is externally visible${NC}"
    echo -e "  ${YELLOW}before it may take — otherwise two spares could take at once (double-sign).${NC}"
    ask_numeric "STANDBY's TAKEOVER_DELAY (seconds)" "60" 1
    CFG_STANDBY_TAKEOVER_DELAY="$REPLY"
fi
# The floor is ROLE-AWARE, mirroring the daemon's check_crossnode_timing_safety:
#   STANDBY → EXPECTED + margin ; BACKUP → max(EXPECTED + margin, 120, STANDBY_TAKEOVER_DELAY + 10 + margin)
# (10 = VOTE_LIVENESS_MIN_INTERVAL, the shipped default the generated env uses). Clamp CFG_TAKEOVER_DELAY
# up to that floor so a wizard config never boots below it (which the daemon would refuse to start on).
_xnode_min=$(( CFG_EXPECTED_PRIMARY_SELF_FENCE_SECS + CFG_SELF_FENCE_MARGIN_SECS ))
if [[ "$CFG_ROLE" == "BACKUP" ]]; then
    [[ 120 -gt $_xnode_min ]] && _xnode_min=120
    if [[ "$CFG_STANDBY_TAKEOVER_DELAY" =~ ^[0-9]+$ ]]; then
        _xnode_vis=$(( 10#$CFG_STANDBY_TAKEOVER_DELAY + 10 + CFG_SELF_FENCE_MARGIN_SECS ))
        [[ $_xnode_vis -gt $_xnode_min ]] && _xnode_min=$_xnode_vis
    fi
fi
if [[ $((10#${CFG_TAKEOVER_DELAY})) -lt $_xnode_min ]]; then
    warn "TAKEOVER_DELAY=${CFG_TAKEOVER_DELAY}s < ${CFG_ROLE} cross-node floor ${_xnode_min}s — the holder may still hold staked when this node takes it (DOUBLE-SIGN risk on heal). Raising TAKEOVER_DELAY to ${_xnode_min}s."
    CFG_TAKEOVER_DELAY=$_xnode_min
fi

# v0.6.9 (M6): "auto" removed from the menu — it was NEVER implemented by the daemon (the STAKED
# branch implements only "manual"), so offering it armed a silent no-op. Informational only; the
# daemon additionally coerces a hand-edited GIVE_BACK_MODE=auto to manual with a warning.
echo -e "  Give-back mode: ${BOLD}manual${NC} — the holder KEEPS the staked identity after a takeover until the operator"
echo -e "  gives it back (see the manual's 'Manual switch-back'). This is the only implemented mode."
CFG_GIVE_BACK="manual"

echo ""

# --- v0.6.8 (Option A): gossip identity-flip fast-path (advanced; OFF by default; fail-closed) ---
# v0.6.9 (Phase A): expert knob — SHOWN only in advanced mode; simple leaves Option A OFF (fail-closed).
CFG_PRIMARY_UNSTAKED_PUBKEY=""
# v0.6.9 (Phase-B2): CFG_STANDBY_TAKEOVER_DELAY is initialized + (for BACKUP) collected in the timing
# step above — do NOT reset it here, or a BACKUP's value would be lost.
CFG_FASTPATH_PEER_RECOVERY_MANUAL="false"
# F-B: the daemon allows a ZERO stagger floor (fast-take with no delay) ONLY for the declared first spare.
# Set it true on the STANDBY, false on every BACKUP — role is known here, so the operator can't fat-finger it.
CFG_WITNESS_FASTPATH_FIRST_SPARE="false"
if [[ "$ADVANCED" == "true" ]]; then
echo -e "  ${BOLD}Option A — gossip identity-flip fast-path (advanced; OFF by default):${NC}"
echo -e "  ${CYAN}Skips the takeover timer when this node POSITIVELY observes the holder advertise its${NC}"
echo -e "  ${CYAN}UNSTAKED identity in gossip (a graceful self-fence). Helps planned / no-answer failovers${NC}"
echo -e "  ${CYAN}(~85→~30-40s); does NOT help crash / egress-only (timer governs). It skips ONLY the timer —${NC}"
echo -e "  ${CYAN}the external-confirm and vote-liveness==frozen gates still run. REQUIRES: every staked-capable${NC}"
echo -e "  ${CYAN}peer runs RECOVERY_MODE=manual, and two external RPCs. Leave OFF unless you've read the${NC}"
echo -e "  ${CYAN}manual's 'Option A' section.${NC}"
ask_choice "Enable gossip identity-flip fast-path (Option A)?" "${WITNESS_FASTPATH:-false}" "false" "true"
CFG_WITNESS_FASTPATH="$REPLY"
else
    CFG_WITNESS_FASTPATH=false   # simple-mode safe default (Option A OFF; proven v0.6.7 timer governs)
fi
if [[ "$CFG_WITNESS_FASTPATH" == "true" ]]; then
    ask "Holder UNSTAKED pubkey(s) to watch (space-separated — the OTHER staked-capable node's unstaked identity)" "${PRIMARY_UNSTAKED_PUBKEY:-}"
    CFG_PRIMARY_UNSTAKED_PUBKEY="$REPLY"
    # STANDBY_TAKEOVER_DELAY = the FIRST spare's (STANDBY's) TAKEOVER_DELAY, set the SAME on every spare.
    # The node enforces stagger = max(FASTPATH_STAGGER_SECS, TAKEOVER_DELAY - STANDBY_TAKEOVER_DELAY).
    if [[ "$CFG_ROLE" == "STANDBY" ]]; then
        CFG_STANDBY_TAKEOVER_DELAY="$CFG_TAKEOVER_DELAY"
        CFG_WITNESS_FASTPATH_FIRST_SPARE="true"   # F-B: the STANDBY is the one node allowed a floor-0 fast-take
        ok "STANDBY_TAKEOVER_DELAY = this node's TAKEOVER_DELAY (${CFG_TAKEOVER_DELAY}s) → stagger floor 0 (first-spare)"
    else
        # v0.6.9 (Phase-B2): CFG_STANDBY_TAKEOVER_DELAY was already collected in the timing step above
        # (all modes) and drove the role-aware floor clamp. Reuse it for the Option-A stagger so this
        # BACKUP can NEVER fast-take ahead of the STANDBY (prevents a two-spare double-take).
        ok "BACKUP stagger uses STANDBY_TAKEOVER_DELAY=${CFG_STANDBY_TAKEOVER_DELAY}s (from the timing step)"
    fi
    echo -e "  ${YELLOW}Option A fires ONLY if every staked-capable peer runs RECOVERY_MODE=manual (no auto re-stake).${NC}"
    ask_choice "Confirm ALL staked-capable peers run RECOVERY_MODE=manual?" "false" "false" "true"
    CFG_FASTPATH_PEER_RECOVERY_MANUAL="$REPLY"
    if [[ -z "$CFG_PRIMARY_UNSTAKED_PUBKEY" || "$CFG_FASTPATH_PEER_RECOVERY_MANUAL" != "true" ]]; then
        warn "Fast-path will be DISABLED (fail-closed): missing unstaked pubkey and/or unconfirmed manual-recovery. The proven v0.6.7 timer governs until fixed."
    fi
    echo ""
fi

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
echo -e "  ${DIM}Use the same channel as PRIMARY for unified alerts.${NC}"
sleep 1
echo ""

ask_choice "Enable ntfy.sh push (optional)" "true" "true" "false"
CFG_NTFY_ENABLED="$REPLY"

if [[ "$CFG_NTFY_ENABLED" == "true" ]]; then
    if [[ -n "${WEBHOOK_URL:-}" && "$WEBHOOK_URL" == *"ntfy.sh"* ]]; then
        NTFY_DEFAULT="$WEBHOOK_URL"
    else
        NTFY_RANDOM=$(openssl rand -hex 8 2>/dev/null) || NTFY_RANDOM=$(head -c 8 /dev/urandom | od -A n -t x1 | tr -d ' \n') || NTFY_RANDOM="$RANDOM$RANDOM"
        NTFY_DEFAULT="https://ntfy.sh/solana-failover-${NTFY_RANDOM}"
    fi

    echo -e "  ${DIM}The default channel URL is a randomly-generated private channel (nobody can guess it).${NC}"
    echo -e "  ${DIM}How ntfy works / self-hosting: https://docs.ntfy.sh/${NC}"
    ask "ntfy.sh channel URL (same as PRIMARY!)" "$NTFY_DEFAULT"
    CFG_WEBHOOK_URL="$REPLY"

    echo ""
    echo -e "  Sending test notification..."
    # shellcheck disable=SC2034  # output captured for potential debug; only the exit code is checked
    NTFY_TEST=$(curl -s -m 10 -X POST "$CFG_WEBHOOK_URL" \
        -H "Title: [${CFG_NODE_NAME}] STANDBY Failover v0.6.9 — deploy test" \
        -H "Priority: urgent" \
        -H "Tags: white_check_mark" \
        -d "STANDBY node connected to this channel." 2>&1)

    if [[ $? -eq 0 ]]; then
        ok "Test push sent to: $CFG_WEBHOOK_URL"
        echo -e "  ${DIM}Same channel as PRIMARY — you're already subscribed on your phone (no action needed).${NC}"
    else
        warn "ntfy.sh test failed"
    fi
else
    CFG_WEBHOOK_URL=""
fi

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
echo -e "  ${DIM}Use a DISTINCT URL per node (do NOT reuse the PRIMARY's watchdog URL).${NC}"
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

cat > /opt/solana-failover/failover-standby.env << ENVEOF
# ============================================================================
# Solana ${CFG_ROLE} Node Failover v0.6.9 (LOCAL-first, 3-Tier RPC)
# Generated by deploy script on $(date -u +"%F %T UTC")
# Role: ${CFG_ROLE}
# After changes: systemctl restart solana-failover-standby
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

# --- Monitoring ---
VOTE_PUBKEY=$(_envq "${CFG_VOTE_PUBKEY}")

# --- Thresholds ---
CHECK_INTERVAL=${CFG_CHECK_INTERVAL}
TURBO_INTERVAL=${CFG_TURBO_INTERVAL}
DELINQUENCY_RETRIES=${CFG_DELINQ_RETRIES}
TAKEOVER_DELAY=${CFG_TAKEOVER_DELAY}
LOCAL_HEALTH_MAX_BEHIND=${CFG_MAX_BEHIND}

# --- Cross-node fail-over timing safety (v0.6.6 N1) ---
# Cross-node safety floor: a spare waits TAKEOVER_DELAY >= floor before taking, so the current holder
# always relinquishes first. EXPECTED must MATCH the PRIMARY's self-fence worst-case (the larger of its
# SELF_FENCE_ISOLATION_SECS/NOANSWER_SECS) — derive it from the PRIMARY config; do not tune
# independently. (The daemon re-checks this invariant at startup: check_crossnode_timing_safety.)
# v0.6.9 (B2): the floor is ROLE-AWARE. FAILOVER_ROLE tells the daemon whether this node is the STANDBY
# (first spare, floor = EXPECTED + MARGIN) or a BACKUP (later spare — floor = max(120,
# STANDBY_TAKEOVER_DELAY + VOTE_LIVENESS_MIN_INTERVAL + MARGIN), so it outwaits the STANDBY's take
# becoming externally visible and two spares can't both take → no double-sign). Do NOT hand-edit.
FAILOVER_ROLE=${CFG_ROLE}
EXPECTED_PRIMARY_SELF_FENCE_SECS=${CFG_EXPECTED_PRIMARY_SELF_FENCE_SECS}
SELF_FENCE_MARGIN_SECS=${CFG_SELF_FENCE_MARGIN_SECS}
# v0.6.9 (M9): a TAKEOVER_DELAY below EXPECTED + MARGIN is now FATAL at startup. true = old
# warn-and-continue — LAB/TESTING ONLY (double-sign risk on heal); never on a production spare.
ALLOW_UNSAFE_TIMING=false
# v0.6.8 (B2): MUST match the PRIMARY's SELF_FENCE_VOTE_LAG_SLOTS. Startup asserts VOTE_LIVENESS_EPSILON
# <= this/4 (EPSILON << band) so a holder still landing votes inside its own self-fence band is reliably
# seen here as "voting" → BLOCK (the coupling that keeps the wedged-but-alive case safe). 0 = skip.
EXPECTED_PRIMARY_VOTE_LAG_SLOTS=32

# --- Sliding window (DDoS protection) ---
DELINQUENCY_WINDOW_SIZE=${CFG_WINDOW_SIZE}
DELINQUENCY_WINDOW_THRESHOLD=${CFG_WINDOW_THRESHOLD}
MAX_DELINQUENT_SLOTS=${CFG_MAX_DELINQ_SLOTS}
HEARTBEAT_INTERVAL=${CFG_HEARTBEAT}

# --- Safety ---
DRY_RUN=${CFG_DRY_RUN}
GOSSIP_VERIFY=${CFG_GOSSIP_VERIFY}
VOTE_LIVENESS_VERIFY=${CFG_VOTE_LIVENESS}
ALLOW_UNFENCED_TAKEOVER=${CFG_ALLOW_UNFENCED}
GIVE_BACK_MODE=$(_envq "${CFG_GIVE_BACK}")

# --- STANDBY self-fence for the PROMOTED holder (v0.6.9 H1 — the PRIMARY self-fence, ported) ---
# After a takeover this node holds/votes the staked identity. While STAKED it watches LOCAL signals
# ONLY and gives the identity back to its OWN unstaked key when isolated (frozen confirmed slot /
# silent LOCAL RPC / N6 own-vote-lag / getHealth) — before a partition heal can double-sign. The
# holder-relinquishes-first invariant now covers the STANDBY→BACKUP hop (30s worst case + margin ≤
# the BACKUP's 120s). Demote is bounded (SETIDENTITY_TIMEOUT) with the hard-stop escalation; after a
# self-fence demote, re-taking is locked out for SELF_FENCE_RETAKE_COOLDOWN (our own fenced vote
# account looks delinquent — that is why we fenced). Defaults match the PRIMARY; keep them in sync.
STANDBY_SELF_FENCE=true
SELF_FENCE_ISOLATION_SECS=30
SELF_FENCE_MAX_BEHIND=150
SELF_FENCE_NOANSWER_SECS=30
SELF_FENCE_VOTE_LAG_SLOTS=32
SELF_FENCE_VOTE_LAG_SECS=20
SELF_FENCE_VOTE_LAG_RESET_CYCLES=3
SETIDENTITY_TIMEOUT=15
SELF_FENCE_HARD_STOP=true
HARD_STOP_REVERIFY_SECS=15
SELF_FENCE_RETAKE_COOLDOWN=600

# --- Collision detector (v0.6.9 M5) ---
# While STAKED: compare external gossip's endpoint for the staked pubkey vs our own; 2 consecutive
# mismatches → 🚨 page (throttled). DETECTION-ONLY — never demotes.
COLLISION_CHECK_INTERVAL=60

# --- State persistence (v0.6.9 H3/M10) ---
# Role-specific state file (.../state-standby; legacy .../state migrates once). Self-fence baseline +
# re-take lockout persist every cycle; the baseline restores only when fresher than STATE_MAX_AGE_SECS.
STATE_MAX_AGE_SECS=900
# Persisted-STAKED + validator unreachable this long at monitor startup → 🚨 page (once).
STARTUP_STAKED_UNREACHABLE_ALERT_SECS=60

# --- v0.6.8 (Option A): gossip identity-flip fast-path (ADDITIVE; OFF by default; fail-closed) ---
# Skips the remaining TAKEOVER_DELAY when this node POSITIVELY observes the holder advertising its KNOWN
# unstaked identity on BOTH external RPCs (after first seeing it absent). Skips ONLY the timer — the
# external-confirm + vote-liveness==frozen gates still run. Keys on the unstaked pubkey APPEARING (~15s
# CRDS TTL ⇒ recent), NEVER on the staked entry vanishing (~48h linger). REQUIRES all staked-capable peers
# on RECOVERY_MODE=manual + two external RPCs. PRIMARY_UNSTAKED_PUBKEY must NOT be the staked pubkey (fatal).
# STANDBY_TAKEOVER_DELAY = the STANDBY's TAKEOVER_DELAY, the SAME on every spare; the node enforces an
# effective stagger = max(FASTPATH_STAGGER_SECS, TAKEOVER_DELAY - STANDBY_TAKEOVER_DELAY) so a BACKUP can't
# fast-take ahead of the STANDBY. Empty pubkey / not-manual / empty-or-bad STANDBY_TAKEOVER_DELAY ⇒ DISABLED.
WITNESS_FASTPATH=${CFG_WITNESS_FASTPATH}
PRIMARY_UNSTAKED_PUBKEY=$(_envq "${CFG_PRIMARY_UNSTAKED_PUBKEY}")
FASTPATH_CONFIRM_SAMPLES=2
FASTPATH_STAGGER_SECS=0
FASTPATH_PEER_RECOVERY_MANUAL=${CFG_FASTPATH_PEER_RECOVERY_MANUAL}
STANDBY_TAKEOVER_DELAY=$(_envq "${CFG_STANDBY_TAKEOVER_DELAY}")
# F-B: TRUE only on the STANDBY (the one first spare allowed a zero stagger floor); FALSE on every BACKUP.
# A zero stagger floor without this true ⇒ fast-path DISABLED (fail-closed), so a misconfigured BACKUP
# can't silently race the STANDBY into a two-spare take.
WITNESS_FASTPATH_FIRST_SPARE=${CFG_WITNESS_FASTPATH_FIRST_SPARE}

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

chmod 600 /opt/solana-failover/failover-standby.env
ok "Config written: /opt/solana-failover/failover-standby.env"

sleep 1

# ========================= COPY SCRIPT ========================================

step "Deploying script"

SCRIPT_FILE="$SCRIPT_DIR/solana-standby-failover.sh"
[[ -f "$SCRIPT_FILE" ]] || fail "solana-standby-failover.sh not found in $SCRIPT_DIR"

cp "$SCRIPT_FILE" /opt/solana-failover/
chmod +x /opt/solana-failover/solana-standby-failover.sh
ok "Script deployed"

bash -n /opt/solana-failover/solana-standby-failover.sh && ok "Script syntax OK" || fail "Syntax error!"
bash -n /opt/solana-failover/failover-standby.env && ok "Config syntax OK" || fail "Config syntax error!"

sleep 1

# ========================= SYSTEMD ============================================

step "Creating systemd service"

cat > /etc/systemd/system/solana-failover-standby.service << 'SERVICEEOF'
[Unit]
Description=Solana STANDBY Node Failover Protection v0.6.9
After=solana.service
Wants=solana.service

[Service]
Type=simple
User=root
ExecStart=/opt/solana-failover/solana-standby-failover.sh
Restart=always
RestartSec=10
LimitNOFILE=1000000
TimeoutStopSec=15
KillSignal=SIGTERM
StandardOutput=journal
StandardError=journal
SyslogIdentifier=solana-failover-standby

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
ok "Systemd service created"

# v0.6.9 (M7): remember whether it was running — the end of the deploy offers to start it again.
FAILOVER_WAS_ACTIVE=""
systemctl is-active solana-failover-standby &>/dev/null && { FAILOVER_WAS_ACTIVE=1; systemctl stop solana-failover-standby; ok "Old service stopped (will offer to restart it at the end)"; }

sleep 1

# ========================= TEST CONNECTIVITY ==================================

step "Testing connectivity"

T1=$(curl -s -m 5 "$CFG_LOCAL_RPC" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
[[ -n "$T1" ]] && ok "Tier 1 (Local):  slot $T1" || warn "Tier 1 (Local):  not ready"

if [[ -n "$CFG_TIER2_RPC" ]]; then
    T2=$(curl -s -m 10 "$CFG_TIER2_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [[ -n "$T2" ]] && ok "Tier 2 (Paid):   slot $T2" || warn "Tier 2 (Paid):   unreachable"
else
    warn "Tier 2 (Paid):   not configured"
fi

T3=$(curl -s -m 10 "$CFG_TIER3_RPC" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
[[ -n "$T3" ]] && ok "Tier 3 (Public): slot $T3" || warn "Tier 3 (Public): unreachable"

# Current identity check
if [[ -n "$LEDGER" ]]; then
    CUR_ID=$("$SOLANA_PATH/agave-validator" --ledger "$LEDGER" contact-info 2>/dev/null | grep Identity | awk '{print $2}') || true
    if [[ -n "$CUR_ID" ]]; then
        if [[ "$CUR_ID" == "$UNSTAKED_PUB" ]]; then
            ok "Identity: UNSTAKED ($CUR_ID) — correct for STANDBY"
        elif [[ "$CUR_ID" == "$STAKED_PUB" ]]; then
            warn "Identity: STAKED — unusual for STANDBY at startup"
        else
            ok "Identity: $CUR_ID"
        fi
    fi
fi

# Telegram test
if [[ "$CFG_TG_ENABLED" == "true" && -n "$CFG_TG_TOKEN" && -n "$CFG_TG_CHAT" ]]; then
    TG_RESULT=$(curl -s -m 10 -X POST "https://api.telegram.org/bot${CFG_TG_TOKEN}/sendMessage" \
        -d chat_id="$CFG_TG_CHAT" \
        -d text="[${CFG_NODE_NAME}] 🔧 Deploy complete — STANDBY failover v0.6.9 ready" \
        -d parse_mode="HTML" 2>/dev/null) || true
    echo "$TG_RESULT" | jq -e '.ok' &>/dev/null && ok "Telegram: test message sent" || warn "Telegram: send failed"
fi

sleep 1

# ========================= SUMMARY ============================================

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}${GREEN}✓  ${CFG_ROLE} DEPLOY COMPLETE${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}${CYAN}Files${NC}"
echo -e "    ${DIM}/opt/solana-failover/solana-standby-failover.sh${NC}"
echo -e "    ${DIM}/opt/solana-failover/failover-standby.env${NC}"
echo -e "    ${DIM}/etc/systemd/system/solana-failover-standby.service${NC}"
echo ""
echo -e "  ${BOLD}${CYAN}Config${NC}"
echo -e "    ${DIM}Role:${NC}           $CFG_ROLE"
echo -e "    ${DIM}Node:${NC}           $CFG_NODE_NAME"
echo -e "    ${DIM}DRY_RUN:${NC}        $CFG_DRY_RUN"
echo -e "    ${DIM}Takeover delay:${NC} ${CFG_TAKEOVER_DELAY}s"
echo -e "    ${DIM}Gossip verify:${NC}  $CFG_GOSSIP_VERIFY"
echo -e "    ${DIM}Vote-liveness:${NC}  $CFG_VOTE_LIVENESS"
echo -e "    ${DIM}Give-back:${NC}      $CFG_GIVE_BACK"
echo -e "    ${DIM}Vote pubkey:${NC}    ${CFG_VOTE_PUBKEY:-(NOT SET!)}"
echo -e "    ${DIM}Telegram:${NC}       $CFG_TG_ENABLED"
echo -e "    ${DIM}Webhook:${NC}        ${CFG_WEBHOOK_URL:-(not set)}"

if [[ "$CFG_ROLE" == "BACKUP" ]]; then
    echo ""
    echo -e "  ${BOLD}${YELLOW}BACKUP NOTE${NC}"
    echo -e "    ${DIM}GOSSIP_VERIFY=$CFG_GOSSIP_VERIFY  VOTE_LIVENESS_VERIFY=$CFG_VOTE_LIVENESS  TAKEOVER_DELAY=${CFG_TAKEOVER_DELAY}s${NC}"
    echo -e "    ${DIM}BACKUP takes over only after BOTH PRIMARY and STANDBY stop voting the staked${NC}"
    echo -e "    ${DIM}identity (vote-liveness fence) AND ${CFG_TAKEOVER_DELAY}s elapse — a real fence,${NC}"
    echo -e "    ${DIM}not a blind takeover.${NC}"
fi

sleep 2

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}${CYAN}NEXT STEPS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}1.${NC} Start the service:"
echo -e "     ${DIM}systemctl start solana-failover-standby${NC}"
echo -e "     ${DIM}tail -f /var/log/solana-failover-standby.log${NC}"
echo ""
sleep 1
echo -e "  ${BOLD}2.${NC} Verify monitoring is working:"
echo -e "     ${DIM}[TIER1] Health OK — 0 slots behind${NC}"
echo -e "     ${DIM}[TIER2] NOT delinquent${NC}"
echo ""
sleep 1
echo -e "  ${BOLD}3.${NC} When ready for production:"
echo -e "     ${DIM}sed -i 's/DRY_RUN=true/DRY_RUN=false/' /opt/solana-failover/failover-standby.env${NC}"
echo -e "     ${DIM}systemctl restart solana-failover-standby${NC}"
echo -e "     ${DIM}systemctl enable solana-failover-standby${NC}"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"

# v0.6.9 (M7): don't leave an upgraded node unprotected — offer to start (and enable) right now.
offer_start_service "solana-failover-standby" "$FAILOVER_WAS_ACTIVE"
