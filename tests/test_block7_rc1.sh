#!/bin/bash
# v0.7 Block 7, trimmed for rc1 (TASK-BLOCK7-RC1.md): what the ARMED pair and the mainnet monitor-only phase still need. One suite, one section per item;
# each item is written red first on the AG-3 tip (c8989c1) and has its own mutants (mutate()).
#   (B7.1) _validator_pid is the validator, never an admin-client child of the daemon (set-identity / authorized-voter / contact-info / monitor / exit /
#          wait-for-restart-window): the unit's MainPID first, pgrep only as the fallback with the admin clients excluded - primary, standby, the fence
#          script and the arm ceremony (the last two are byte-identical copies of one function)
#   (B7.2) one instance per role: flock -n on "$STATE_DIR/.<role>.lock" at startup, before the first identity read; the second instance exits 3 with
#          one log line and one page SECOND INSTANCE REFUSED
#   (B7.3) the state file is written atomically (tmp + mv in the same directory, 0600); a torn file on load is one WARN, never an abort, and never a
#          lost lockout
#   (B7.4) fail-closed polarity at the two remaining AG stops: the primary's switch_to_staked and the standby's _prewarm_voter_add ask a positive
#          predicate (`if ! _ag_..._allowed`), so an undefined predicate withholds
#   (B7.5) DRY_RUN page storms: one dry page per ALERT_THROTTLE per reason (the primary's dry demote and the self-fence's dry pages), the standby's
#          cooldown / lockout WARN at most once per 60 s
# B7.6 (the version constant) is pinned in the `facts` job of .github/workflows/ci.yml, not here.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, mutate(), extract_region, load_seam.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Block 7 trimmed for rc1: the validator pid, one instance per role, an atomic state file, fail-closed AG stops, quiet DRY_RUN (v0.7)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/b7.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cut_src() { local f="$WORK/seam.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$$.$RANDOM"; sed -n '1,/MAIN LOOP/p' "$1" > "$f"; printf '%s' "$f"; }
STK="StakedPubkey111111111111111111111111111111"
UNS="UnstakedPubkey1111111111111111111111111111"

# ── (0) the anchors every section below stands on ──────────────────────────────────────────────────────────────────────
echo ""; echo "─── (0) the daemons and the scripts the sections read are all there and parse ───"
b7_missing=""
for f in "$PRIMARY" "$STANDBY" "$HARNESS_DIR/systemd/failover-fence.sh" "$HARNESS_DIR/failover-arm.sh"; do
    [[ -f "$f" ]] || b7_missing="$b7_missing $(basename "$f")"
done
[[ -z "$b7_missing" ]] && ok "(0) both daemons, the fence script and the arm ceremony are present" || bad "(0) missing:$b7_missing"

# ══ B7.1 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.1 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.2 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.2 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.3 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.3 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.4 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.4 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.5 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.5 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

results_banner
