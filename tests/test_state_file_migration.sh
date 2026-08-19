#!/bin/bash
# v0.6.9 (M10): role-specific STATE_FILE defaults + one-time legacy migration. Both daemons used to
# default to the SAME /var/lib/solana-failover/state — colocated roles (lab) clobbered each other,
# and H3 makes the file load-bearing. Drives the REAL load_state with a temp STATE_DIR.
#   (S-a) legacy file present, new default absent → migrated once (mv), values restored, legacy gone
#   (S-b) second startup → no re-migration (idempotent no-op)
#   (S-c) new file already exists → legacy NOT touched (never clobber the newer role file)
#   (S-d) operator-overridden STATE_FILE (non-default, no suffix) → migration skipped entirely
#   (S-d2) v0.6.9 (B5): STATE_FILE ends in the role suffix but is NOT the shipped default → skipped
#          (control: revert B5's exact-default gate → the suffixed non-default path migrates and fails)
#   (S-e) role defaults DIFFER between the shipped daemons (state-primary vs state-standby)
#   (S-f) NON-VACUOUS: v0.6.8 defaults were IDENTICAL (.../state on both) — the clobber M10 fixes

# harness: tests/lib/harness.sh — ok/bad+banners, paths. run_load's cut + sink subset stay local.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
V068P="$HARNESS_DIR/../../0.6.8/failover-v0.6.8/solana-primary-failover.sh"
V068S="$HARNESS_DIR/../../0.6.8/failover-v0.6.8/solana-standby-failover.sh"

# run load_state from the given script with STATE_FILE=$2; echoes restored key var + file layout
run_load() {   # $1=script $2=state_file $3=key(LAST_SWITCH_TIME|LAST_TAKEOVER_TIME) $4=default_state_file(opt; =$2)
  local script="$1" sfile="$2" key="$3" dflt="${4:-$2}"
  (
    set +e
    SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
    # shellcheck disable=SC1090
    source "$SRC"; rm -f "$SRC"
    # v0.6.9 (B5): migration now fires only when STATE_FILE == the shipped default. Default the test's
    # "shipped default" to the temp STATE_FILE (so S-a/b/c exercise the migrate path); S-d2 overrides it
    # to a DIFFERENT default to prove a suffixed non-default override is NOT migrated.
    STATE_DIR="$(dirname "$sfile")"; STATE_FILE="$sfile"; _DEFAULT_STATE_FILE="$dflt"; STATE_MAX_AGE_SECS=900
    PRIMARY_SELF_FENCE=true; STANDBY_SELF_FENCE=true
    SELF_FENCE_ISOLATION_SECS=30
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    load_state
    printf 'val=%s\n' "${!key}"
  )
}

title_banner "Role-specific STATE_FILE + legacy migration (v0.6.9 M10)"

for SCRIPT in "$PRIMARY" "$STANDBY"; do
  if [[ "$SCRIPT" == "$PRIMARY" ]]; then ROLE=primary; KEY=LAST_SWITCH_TIME; else ROLE=standby; KEY=LAST_TAKEOVER_TIME; fi
  NAME=$(echo "$ROLE" | tr '[:lower:]' '[:upper:]')
  TMPD=$(mktemp -d)
  NEWF="$TMPD/state-$ROLE"; LEGACY="$TMPD/state"

  echo ""; echo "─── [$NAME] (S-a) legacy migrates once ───"
  # v0.7 (Block 3): stamp the fixture with the CURRENT boot id (empty on the macOS harness — the
  # no-/proc/uptime fallback then reads it as same-boot) so the persisted value restores VERBATIM;
  # cross-boot re-stamping is covered by test_monotonic_timers.sh, this suite tests the M10 migration.
  MKEY=LAST_TAKEOVER_MONO; [[ "$KEY" == "LAST_SWITCH_TIME" ]] && MKEY=LAST_SWITCH_MONO
  # v0.7 (Block 3 dual-write): the *_MONO twin makes the probe value restore verbatim (same-boot);
  # this suite tests the M10 MIGRATION mechanics — old-format re-hold semantics live in
  # test_monotonic_timers.sh, not here.
  printf '%s=4242\n%s=4242\nBOOT_ID=%s\n' "$KEY" "$MKEY" "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" > "$LEGACY"
  out=$(run_load "$SCRIPT" "$NEWF" "$KEY")
  if [[ "$out" == "val=4242" && -f "$NEWF" && ! -e "$LEGACY" ]]; then
      ok "[$NAME] (S-a) legacy → $(basename "$NEWF") migrated (mv), value restored (4242), legacy gone"
  else
      bad "[$NAME] (S-a) migration wrong (out=$out new=$([[ -f $NEWF ]] && echo y || echo n) legacy=$([[ -e $LEGACY ]] && echo y || echo n))"
  fi

  echo "─── [$NAME] (S-b) second startup: idempotent ───"
  out=$(run_load "$SCRIPT" "$NEWF" "$KEY")
  [[ "$out" == "val=4242" && ! -e "$LEGACY" ]] \
      && ok "[$NAME] (S-b) re-run restores from the migrated file; no legacy resurrection" \
      || bad "[$NAME] (S-b) not idempotent (out=$out)"

  echo "─── [$NAME] (S-c) new file exists → legacy untouched ───"
  printf '%s=9999\n' "$KEY" > "$LEGACY"          # a stale legacy re-appears
  out=$(run_load "$SCRIPT" "$NEWF" "$KEY")
  [[ "$out" == "val=4242" && -f "$LEGACY" ]] \
      && ok "[$NAME] (S-c) role file kept (4242), legacy left in place (never clobbered)" \
      || bad "[$NAME] (S-c) clobbered (out=$out legacy=$([[ -e $LEGACY ]] && echo y || echo n))"

  echo "─── [$NAME] (S-d) operator override → migration skipped ───"
  CUSTOM="$TMPD/my-custom-state"
  out=$(run_load "$SCRIPT" "$CUSTOM" "$KEY")
  [[ ! -e "$CUSTOM" && -f "$LEGACY" ]] \
      && ok "[$NAME] (S-d) non-default STATE_FILE: legacy untouched, nothing invented" \
      || bad "[$NAME] (S-d) touched files it should not have"

  echo "─── [$NAME] (S-d2) v0.6.9 (B5): suffixed but NON-default path → migration skipped ───"
  ALTD="$TMPD/alt"; mkdir -p "$ALTD"
  ALT_NEW="$ALTD/state-$ROLE"; ALT_LEGACY="$ALTD/state"
  printf '%s=7777\n' "$KEY" > "$ALT_LEGACY"
  # STATE_FILE ends in the role suffix but the shipped default is the /var/lib path → must NOT migrate.
  out=$(run_load "$SCRIPT" "$ALT_NEW" "$KEY" "/var/lib/solana-failover/state-$ROLE")
  [[ ! -e "$ALT_NEW" && -f "$ALT_LEGACY" ]] \
      && ok "[$NAME] (S-d2) operator ${ROLE}-suffixed override left untouched (exact-default gate holds)" \
      || bad "[$NAME] (S-d2) migrated a non-default suffixed path (B5 regression: out=$out new=$([[ -e $ALT_NEW ]] && echo y || echo n))"
  rm -rf "$TMPD"
done

echo ""; echo "─── (S-e) shipped defaults differ per role ───"
dp=$(grep -E '^STATE_FILE=' "$PRIMARY" | head -1)
ds=$(grep -E '^STATE_FILE=' "$STANDBY" | head -1)
if [[ "$dp" == *state-primary* && "$ds" == *state-standby* && "$dp" != "$ds" ]]; then
    ok "(S-e) primary default=$dp | standby default=$ds"
else
    bad "(S-e) defaults wrong (p='$dp' s='$ds')"
fi

echo ""; echo "─── (S-f) non-vacuous: v0.6.8 defaults were identical (the clobber) ───"
if [[ -f "$V068P" && -f "$V068S" ]]; then
    v8p=$(grep -E '^STATE_FILE=' "$V068P" | head -1); v8s=$(grep -E '^STATE_FILE=' "$V068S" | head -1)
    [[ "$v8p" == "$v8s" && "$v8p" == *'/state"'* ]] \
        && ok "(S-f) v0.6.8: both defaulted to '$v8p' → M10 genuinely changes behavior" \
        || bad "(S-f) v0.6.8 defaults unexpected (p='$v8p' s='$v8s')"
else
    ok "(S-f) v0.6.8 baseline not present to compare (skipped)"
fi

results_banner
