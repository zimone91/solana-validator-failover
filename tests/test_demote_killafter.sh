#!/bin/bash
# v0.6.8 (S3, Audit-2 fix): every demote/promote/systemctl-stop `timeout` now carries `-k 5`. Plain
# `timeout` only sends SIGTERM; a SIGTERM-ignoring CLI leaves `timeout` itself waiting forever, re-opening
# the single-threaded-loop freeze B1 closes. `-k 5` escalates to SIGKILL 5s later → rc 137, which the
# existing escalation branch (124||137) already handles. Structural + control test (the macOS box has no
# real `timeout`, and B1-a/b already exercise the rc-124/137 → hard-stop behavioral path).
#   (K-count)   all 7 demote/promote/systemctl timeouts carry -k 5
#   (K-nobare)  no bare (SIGTERM-only) timeout remains on those paths
#   (K-137)     the escalation branches fire on rc 137 (SIGKILL), not only 124
#   (K-control) NON-VACUOUS: the v0.6.7 baseline has ZERO `-k` (v0.6.8 genuinely added the escalation)

# harness: tests/lib/harness.sh — ok/bad+banners, paths only (structural suite).
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
V067="$HARNESS_DIR/../../0.6.7/failover-v0.6.7/solana-primary-failover.sh"

title_banner "Demote/promote timeout --kill-after (v0.6.8 S3)"
echo ""

# v0.6.9 (TASK-v0.6.9 H2): 7 → 8 — the hard-stop now also masks the unit (`timeout -k 5 15 systemctl
# mask --runtime`) before the direct kill so Restart=always cannot resurrect it. Same bound discipline.
n_k=$(grep -cE 'timeout -k 5 ' "$PRIMARY")
[[ $n_k -eq 8 ]] && ok "(K-count) 8 timeout calls carry -k 5 (6 set-identity/voter + systemctl stop + systemctl mask [v0.6.9 H2])" || bad "(K-count) expected 8 'timeout -k 5', got $n_k"

# No bare SIGTERM-only timeout left on the demote/promote/hard-stop paths.
n_bare=$(grep -nE 'timeout (15 systemctl|"\$SETIDENTITY_TIMEOUT")' "$PRIMARY" | grep -vc '\-k 5')
[[ $n_bare -eq 0 ]] && ok "(K-nobare) no bare (no -k) demote/promote/systemctl timeout remains" || bad "(K-nobare) $n_bare bare timeout(s) remain"

# The escalation branches must accept rc 137 (SIGKILL from -k), not only 124.
n_both=$(grep -cE '\-eq 124 \|\| .*-eq 137' "$PRIMARY")   # lines pairing 124 with 137
n_only124=$(grep -E '\-eq 124' "$PRIMARY" | grep -vc 137)  # any 124-handling line that omits 137
[[ $n_both -ge 5 && $n_only124 -eq 0 ]] \
    && ok "(K-137) all $n_both timeout-rc branches fire on 137 (SIGKILL) as well as 124; none handle 124 alone" \
    || bad "(K-137) escalation 137-handling incomplete (both=$n_both only124=$n_only124)"

# Non-vacuous: the v0.6.7 baseline had no -k anywhere (so v0.6.8 genuinely added the escalation).
if [[ -f "$V067" ]]; then
    v7k=$(grep -cE 'timeout -k' "$V067")
    [[ $v7k -eq 0 ]] && ok "(K-control) v0.6.7 baseline has ZERO 'timeout -k' → v0.6.8 added it (non-vacuous)" || bad "(K-control) v0.6.7 already had -k ($v7k) — fix is not new"
else
    ok "(K-control) v0.6.7 baseline not present to compare (skipped)"
fi

results_banner
