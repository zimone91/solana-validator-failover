# shellcheck shell=bash
# tests/lib/fixtures.sh - synthetic identities for the suites (v0.7.0 F25). Sourceable library ONLY - deliberately not named test_*.sh.
#
# RULE: no real identity - the validator, vote-account or fee-payer address of a node or of a person - appears anywhere in this repository's tree. A suite that needs "some other identity" takes one
# from here. The key below was generated for this purpose (2026-11-08, offline: an ed25519 key pair, the public half base58-encoded, the private half never written to disk). A new literal of 43 or 44
# base58 characters under tests/, docs/ or in the top-level pages also needs a row in tests/fixtures-allowlist.txt; tests/test_no_real_identities.sh fails without it.
FX_IDENTITY_A="3tkCv6M4JwEDPYKcum4paeDamuYU6sdE822qx5C1n6ur"
