#!/bin/bash
# v0.6.7 (N7): the N6 egress-only self-fence reads our own vote account (VOTE_PUBKEY), but startup only
# required VOTE_PUBKEY for RECOVERY_MODE=rpc — so a DEFAULT (manual) config with VOTE_PUBKEY blank booted
# with N6 SILENTLY OFF (egress-only hole open). startup_checks now REFUSES to start (fatal) when
# PRIMARY_SELF_FENCE=true AND both N6 knobs > 0 AND VOTE_PUBKEY is empty — in ANY recovery mode.
#
# Drives the REAL startup_checks with its prerequisites mocked (validate_keypair_file, ledger/tower
# detection, validator args) and a sentinel `validate_numeric_config -> exit 99` placed just past the N7
# region (so we never reach the live RPC tier-test + the validator-wait loop). Asserts:
#   empty VOTE_PUBKEY + N6 armed (32/20)      → refuses: exit 1 with the N6/VOTE_PUBKEY message
#   VOTE_PUBKEY set + N6 armed                → passes the N6 gate (no such refusal; reaches the sentinel)
#   N6 disabled (SLOTS=0) + empty VOTE_PUBKEY → passes (N6 opt-out)

# harness: tests/lib/harness.sh — ok/bad+banners, paths. n7_run's cut + mock block stay local.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# Run the REAL startup_checks; echo "<exit_code>|<last log_error message>".
# $1=SELF_FENCE_VOTE_LAG_SLOTS  $2=SELF_FENCE_VOTE_LAG_SECS  $3=VOTE_PUBKEY  $4=PRIMARY_SELF_FENCE
n7_run() {
  local res; res=$(mktemp)
  (
  set +e
  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$PRIMARY" > "$SRC"; source "$SRC"; rm -f "$SRC"
  VALIDATOR_TYPE=agave; RECOVERY_MODE=manual
  SP=$(mktemp -d); : > "$SP/agave-validator"; : > "$SP/solana-keygen"; SOLANA_PATH="$SP"
  STAKED_KEYPAIR=/x; UNSTAKED_KEYPAIR=/y
  DELINQUENCY_WINDOW_SIZE=10; DELINQUENCY_WINDOW_THRESHOLD=7
  PRIMARY_SELF_FENCE="$4"
  SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=0; SELF_FENCE_NOANSWER_SECS=30
  SELF_FENCE_VOTE_LAG_SLOTS="$1"; SELF_FENCE_VOTE_LAG_SECS="$2"; VOTE_PUBKEY="$3"
  # prerequisite mocks (so startup_checks flows to the N7 region without spurious earlier exits)
  detect_ledger_path(){ LEDGER_PATH=/tmp/led; }; detect_tower_base(){ :; }
  get_validator_args(){ echo ""; }                     # no --identity → startup-identity check skipped
  validate_keypair_file(){ [[ "$1" == "$STAKED_KEYPAIR" ]] && echo "STAKEDPK" || echo "UNSTAKEDPK"; }   # distinct pubkeys (by path; runs in $())
  log(){ :;}; log_info(){ :;}; log_warn(){ :;}; alert(){ :;}; send_telegram(){ return 0;}; send_webhook(){ :;}
  validate_numeric_config(){ exit 99; }                # sentinel: reached past the N7 region cleanly
  _LAST_ERR=""; log_error(){ _LAST_ERR="$*"; }
  exit(){ printf '%s|%s' "$1" "$_LAST_ERR" > "$res"; rm -rf "$SP"; command exit "$1"; }
  startup_checks >/dev/null 2>&1 </dev/null
  ) >/dev/null 2>&1
  cat "$res"; rm -f "$res"
}

title_banner "N7: VOTE_PUBKEY required when N6 is armed"
echo ""

r=$(n7_run 32 20 "" true)            # N6 armed (32/20), VOTE_PUBKEY EMPTY
[[ "${r%%|*}" == "1" && "$r" == *"N6 egress-only self-fence"* ]] \
  && ok "(N7-refuse) empty VOTE_PUBKEY + N6 armed → startup REFUSES (exit 1): ${r#*|}" \
  || bad "(N7-refuse) did not refuse on empty VOTE_PUBKEY + N6 armed (got '$r')"

r=$(n7_run 32 20 "VotePubkey1111111111111111111111111111111" true)   # N6 armed, VOTE_PUBKEY SET
[[ "${r%%|*}" == "99" && "$r" != *"N6 egress-only self-fence"* ]] \
  && ok "(N7-set) VOTE_PUBKEY set + N6 armed → passes the N6 gate (reached the sentinel, no refusal)" \
  || bad "(N7-set) refused / failed even with VOTE_PUBKEY set (got '$r')"

r=$(n7_run 0 20 "" true)             # N6 DISABLED (SLOTS=0), VOTE_PUBKEY empty
[[ "${r%%|*}" == "99" && "$r" != *"N6 egress-only self-fence"* ]] \
  && ok "(N7-optout) N6 disabled (knob 0) + empty VOTE_PUBKEY → starts (N6 opt-out, no refusal)" \
  || bad "(N7-optout) refused on the N6 opt-out path (got '$r')"

results_banner
