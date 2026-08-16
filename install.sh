#!/bin/sh
# Solana Validator Failover — bootstrap installer.
#
#   sh -c "$(curl -sSfL https://zim.one/failover/v0.6.10)"   # pinned (recommended)
#   sh -c "$(curl -sSfL https://zim.one/failover)"          # latest
#
# Downloads the deploy wizard + its daemon for the requested version, verifies them against the
# version's SHA256SUMS manifest, then runs the wizard. The wizard is interactive and starts in
# DRY_RUN — it changes nothing until you review the logs and arm it.
# Non-interactive: set FAILOVER_ROLE=primary|standby (+ optional FAILOVER_VERSION=vX.Y.Z).
#
# WHAT THE CHECKSUM VERIFICATION DOES AND DOES NOT GIVE YOU (honestly):
#   It protects against a corrupted or truncated download, a tampering mirror/CDN, and a partially
#   applied tag. It does NOT protect against a compromise of the repository itself or of zim.one —
#   the manifest travels through the same channel as the files. The anchor outside that channel is
#   the signed release tag: verify it with `git tag -v` against the maintainer key published at
#   zim.one (see SECURITY.md). Verification failure ABORTS the install — there is no
#   continue-without-verification path.
#
# This tool hot-swaps your validator's STAKED identity between machines. Read it before you run it:
#   https://github.com/zimone91/solana-validator-failover
set -eu

REPO="https://raw.githubusercontent.com/zimone91/solana-validator-failover"
VERSION="${FAILOVER_VERSION:-v0.6.10}"   # the Cloudflare route injects the version from the URL path
ROLE="${FAILOVER_ROLE:-}"
# Versions published before the SHA256SUMS manifest existed (no manifest at their tags):
PRECHECKSUM_VERSIONS="v0.6.9 v0.6.10"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v bash >/dev/null 2>&1 || die "bash is required (the failover scripts are bash)"

sha256_of() {  # portable: GNU sha256sum or BSD/macOS shasum
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else die "neither sha256sum nor shasum found — cannot verify downloads"
  fi
}

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

# --- verify against the version's SHA256SUMS manifest (fail-closed) ---
if curl -sSfL "$REPO/$VERSION/SHA256SUMS" -o "$DIR/SHA256SUMS" 2>/dev/null && [ -s "$DIR/SHA256SUMS" ]; then
  for f in "$DEPLOY" "$DAEMON"; do
    want=$(grep "  $f\$" "$DIR/SHA256SUMS" | cut -d' ' -f1)
    [ -n "$want" ] || die "SHA256SUMS for $VERSION does not list $f — refusing to install"
    got=$(sha256_of "$DIR/$f")
    if [ "$got" != "$want" ]; then
      printf 'error: CHECKSUM MISMATCH for %s\n' "$f" >&2
      printf '  expected: %s\n  got:      %s\n' "$want" "$got" >&2
      printf '  The downloaded file is not the file the release manifest describes. NOT installing.\n' >&2
      printf '  This can be a corrupted download or something worse — retry once; if it persists,\n' >&2
      printf '  report it (see SECURITY.md in the repository).\n' >&2
      exit 1
    fi
    printf '  checksum OK: %s\n' "$f"
  done
else
  case " $PRECHECKSUM_VERSIONS " in
    *" $VERSION "*)
      printf '\n  WARNING: %s predates the SHA256SUMS manifest — downloads verified by syntax only.\n' "$VERSION"
      printf '  Newer releases are checksum-verified; consider installing the latest version.\n\n' ;;
    *) die "no SHA256SUMS manifest found for $VERSION — refusing to install unverified files" ;;
  esac
fi

# --- run the wizard (needs root; starts in DRY_RUN) ---
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"
printf '\n  launching the %s installer (interactive; DRY_RUN first) ...\n\n' "$ROLE"
$SUDO bash "$DIR/$DEPLOY"
