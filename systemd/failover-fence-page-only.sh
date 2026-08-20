#!/bin/bash
# failover-fence-page-only.sh (v0.7 Block 5.1) — the PAGE-ONLY fence twin (§2.3 structural
# DRY_RUN), dispatched by solana-failover-fence-page-only.service when the monitor unit reaches
# terminal `failed`. Installed only by the `failover arm` ceremony at the v0.7 rollout
# (upgrade-then-arm, release checklist); repo-tracked and CI-linted as a shippable artifact —
# NOTHING in this repository installs it anywhere.
#
# ZERO MUTATIONS, STRUCTURAL: while THIS unit (and not the real one) is installed, a monitor
# failure can only produce a journal page + a marker. There is deliberately NO admin-socket
# call, NO unit-lifecycle call, NO signal, NO process probe anywhere in this file — the Block-10
# DRY_RUN sweep asserts that mechanically (grep: no mutation token outside comment lines), which
# is why this is a SEPARATE script and not a flag branch inside the real fence: inertness must
# be decidable from the installed files alone, never from a runtime flag branching inside the
# real fence's body (§2.3: a missing/corrupt env cannot flip inertness).
# The real fence restarts the monitor as its last act; this twin does not even do that — the
# restart would be a systemctl token, and the sweep's grep must stay empty. In the page-only arm
# state the monitor's recovery is the operator's move, prompted by the CRITICAL page below.
#
# bash 3.2-safe; same interpreter discipline as the daemons.

# bash 5.2+ patsub_replacement guard — the v0.6.10 alert-death class (see the daemons' header).
shopt -u patsub_replacement 2>/dev/null || true

FENCE_MARKER_DIR="${FENCE_MARKER_DIR:-/var/lib/solana-failover}"

# stderr → the unit's StandardError=journal (same rationale as the real fence: a page must
# never be swallowed by $(…) capture). No network here either — the page is the journal line.
_fence_log() { printf '[failover-fence-page-only] %s\n' "$*" >&2; }
_fence_page() { _fence_log "PAGE[CRITICAL]: $*"; }

_write_marker() {
    # $1 = fenced-page-only ; $2 = reason. Atomic tmp+mv, byte-same discipline as the real
    # fence's markers (content: ISO timestamp + reason).
    local tmp
    mkdir -p "$FENCE_MARKER_DIR" 2>/dev/null || true
    tmp="$FENCE_MARKER_DIR/.$1.tmp.$$"
    if printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$2" > "$tmp" 2>/dev/null && mv -f "$tmp" "$FENCE_MARKER_DIR/$1" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    _fence_page "could not write marker '$1' under $FENCE_MARKER_DIR — the journal line is the only record of this dispatch"
    return 0
}

main() {
    _write_marker fenced-page-only "monitor watchdog failure observed in the PAGE-ONLY arm state (§2.3); no action taken"
    _fence_page "monitor watchdog FAILED — PAGE-ONLY fence dispatched: nothing on this host's dispatch path can act on the validator (§2.3 structural DRY_RUN). Investigate the monitor and the validator NOW; run the failover arm ceremony to install the real fence if protection was intended."
    exit 0
}

main "$@"
