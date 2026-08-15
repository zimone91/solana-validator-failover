#!/bin/sh
# Solana Validator Failover — bootstrap installer.
#
#   sh -c "$(curl -sSfL https://zim.one/failover/v0.6.10)"   # pinned (recommended)
#   sh -c "$(curl -sSfL https://zim.one/failover)"          # latest
#
# Downloads the deploy wizard + its daemon for the requested version, then runs the wizard.
# The wizard is interactive and starts in DRY_RUN — it changes nothing until you review the logs
# and arm it. Non-interactive: set FAILOVER_ROLE=primary|standby (+ optional FAILOVER_VERSION=vX.Y.Z).
#
# This tool hot-swaps your validator's STAKED identity between machines. Read it before you run it:
#   https://github.com/zimone91/solana-validator-failover
set -eu

REPO="https://raw.githubusercontent.com/zimone91/solana-validator-failover"
VERSION="${FAILOVER_VERSION:-v0.6.10}"   # the Cloudflare route injects the version from the URL path
ROLE="${FAILOVER_ROLE:-}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v bash >/dev/null 2>&1 || die "bash is required (the failover scripts are bash)"

printf '\n  Solana Validator Failover  ·  %s  ·  zim.one\n\n' "$VERSION"

# --- role ---
if [ -z "$ROLE" ]; then
  [ -t 0 ] || die "no TTY — run: FAILOVER_ROLE=primary|standby sh -c \"\$(curl -sSfL https://zim.one/failover/$VERSION)\""
  printf '  Which role is THIS server?\n'
  printf '    1) PRIMARY  — your staked node\n'
  printf '    2) STANDBY  — hot spare (or BACKUP)\n'
  printf '  Choose [1/2]: '
  read -r ans || die "aborted"
  case "$ans" in
    1|p|P|primary|PRIMARY) ROLE=primary ;;
    2|s|S|standby|STANDBY) ROLE=standby ;;
    *) die "invalid choice: '$ans'" ;;
  esac
fi
case "$ROLE" in
  primary) DEPLOY=deploy-failover.sh;         DAEMON=solana-primary-failover.sh ;;
  standby) DEPLOY=deploy-failover-standby.sh; DAEMON=solana-standby-failover.sh ;;
  *) die "FAILOVER_ROLE must be 'primary' or 'standby' (got '$ROLE')" ;;
esac

# --- fetch the pair (deploy wizard + its daemon) for this version ---
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT INT TERM
for f in "$DEPLOY" "$DAEMON"; do
  printf '  fetching %s (%s) ...\n' "$f" "$VERSION"
  curl -sSfL "$REPO/$VERSION/$f" -o "$DIR/$f" || die "download failed: $f — does version $VERSION exist?"
  [ -s "$DIR/$f" ] || die "empty download: $f"
  bash -n "$DIR/$f" || die "integrity check failed (corrupt download?): $f"
done

# --- run the wizard (needs root; starts in DRY_RUN) ---
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"
printf '\n  launching the %s installer (interactive; DRY_RUN first) ...\n\n' "$ROLE"
$SUDO bash "$DIR/$DEPLOY"
