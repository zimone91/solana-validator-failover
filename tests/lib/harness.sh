# shellcheck shell=bash
# tests/lib/harness.sh — shared seam-test harness (v0.7 Block 4.1; contract: BLOCK4-SEAM-MAP §3/§4).
#
# Sourceable library ONLY — deliberately not named test_*.sh (run_all.sh would execute it as a
# 45th suite and trip EXPECTED_SUITES). Suites source it first thing:
#
#     source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
#
# Path resolution: relative to the SUITE that sources it — ${BASH_SOURCE[1]} inside a sourced file
# is the sourcing script, so HARNESS_DIR = <suite dir>/.. (the repo root), exactly the DIR= block
# every suite carried. Fallback (library loaded not-from-a-suite): its own location, lib/../.. .
#
# Shim model (map §3.1 — the slice-1 Linux failure class): sourcing a daemon seam REDEFINES
# mono_now/log/alert/…, silently evicting any shims installed earlier in that shell. Therefore
# every harness shim installer REGISTERS itself in _HARNESS_SHIMS, and load_seam re-applies all
# registered installers after every source — a re-sourced seam gets its fake clock back without
# the suite remembering to. Suite-local capture shadows (an alert_warn that logs, etc.) are NOT
# registered here: install them after the harness installers; if your suite re-sources a seam in
# the SAME shell after installing captures, register your own installer via `harness_shim <fn>`
# so the reshim pass re-applies it too (registration order = re-application order).
# bash 3.2-safe throughout: no namerefs, no associative arrays.

# ── PASS/FAIL counters + banners (byte-compatible with every suite's current output) ────────────
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
title_banner() {
    echo "============================================="
    echo "  $1"
    echo "============================================="
}
results_banner() {   # prints the RESULTS banner, cleans the seam-cut cache, exits 0/1
    echo ""
    echo "============================================="
    echo "  RESULTS: $PASS passed, $FAIL failed"
    echo "============================================="
    [[ -n "$_HARNESS_TMP" ]] && rm -rf "$_HARNESS_TMP"
    [[ $FAIL -eq 0 ]] && exit 0 || exit 1
}

# ── repo/daemon path resolution + existence guard ───────────────────────────────────────────────
if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
    HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
else
    HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
PRIMARY="$HARNESS_DIR/solana-primary-failover.sh"
STANDBY="$HARNESS_DIR/solana-standby-failover.sh"
[[ -f "$PRIMARY" && -f "$STANDBY" ]] || { echo "  ❌ scripts not found"; exit 1; }

# ── seam_cut <script> — the source-to-MAIN-LOOP cut, cached per (basename, mtime) ───────────────
# Echoes the path of the cached cut file. The cache lives in a per-process mktemp dir (parallel
# suites never share it; subshells of ONE suite do — the cut re-read ~200 KB per call before).
# The cache file is read-only shared state: NEVER edit it in place — mutation controls copy first
# (see mutate()).
_HARNESS_TMP=$(mktemp -d)
seam_cut() {
    local script="$1" mt cache
    [[ -f "$script" ]] || { echo "  ❌ FAIL: seam_cut: no such script: $script" >&2; return 1; }
    # mtime: GNU/busybox `stat -c %Y` FIRST — on busybox (the bash:5.2 CI image) `stat -f %m`
    # does not fail, it prints multi-line FILESYSTEM status (found red on Linux, 2026-08-19);
    # macOS/BSD stat has no -c and falls through to -f %m.
    mt=$(stat -c %Y "$script" 2>/dev/null || stat -f %m "$script" 2>/dev/null)
    case "$mt" in *[!0-9]*) mt="" ;; esac   # anything non-numeric → no mtime key (cache still per-process)
    cache="$_HARNESS_TMP/$(basename "$script").${mt:-0}.cut"
    if [[ ! -s "$cache" ]]; then
        sed -n '1,/MAIN LOOP/p' "$script" > "$cache" || return 1
    fi
    printf '%s\n' "$cache"
}

# ── shim registry + load_seam <script> ──────────────────────────────────────────────────────────
_HARNESS_SHIMS=""
_harness_register() {   # idempotent: remember an installer fn for re-application after source
    case " $_HARNESS_SHIMS " in *" $1 "*) : ;; *) _HARNESS_SHIMS="$_HARNESS_SHIMS $1" ;; esac
}
harness_shim() {        # register a suite-local shim installer AND apply it now
    _harness_register "$1"
    "$1"
}
harness_reshim() {      # re-apply every registered installer (load_seam calls this after source)
    local _f
    for _f in $_HARNESS_SHIMS; do "$_f"; done
}
load_seam() {           # cut + source + automatic re-application of installed shims
    local _cut
    _cut=$(seam_cut "$1") || { echo "  ❌ FAIL: load_seam: seam_cut failed for $1"; FAIL=$((FAIL+1)); return 1; }
    # shellcheck disable=SC1090
    source "$_cut"
    harness_reshim
}

# ── clock shims (the two byte-identical shims of the sim family) ────────────────────────────────
# Simulated clock: the suite drives _SIM_NOW; `date +%s` and mono_now both read it (the daemons
# thread every timer through one of the two). test_monotonic_timers deliberately does NOT use
# this — it TESTS the clock separation and keeps its own dual _WALL_NOW/_MONO_NOW shims local.
harness_clock_shims() {
    date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
    mono_now(){ echo "$_SIM_NOW"; }
    _harness_register harness_clock_shims
}

# ── silent sinks (the L1 layer: every log/alert/notify egress swallowed) ────────────────────────
# Suites that CAPTURE a sink (event-log shadows) define their capture AFTER this call — the
# capture overrides the silent body (and see the shim-model note above about re-sourcing).
harness_silence_sinks() {
    log(){ :;}; log_info(){ :;}; log_warn(){ :;}; log_error(){ :;}
    alert(){ :;}; alert_info(){ :;}; alert_warn(){ :;}
    send_telegram(){ return 0;}; send_webhook(){ :;}
    _harness_register harness_silence_sinks
}

# ── field <record> <name> — read one k=v field from a |-separated record ────────────────────────
field(){ printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

# ── drift_out <script> [VAR=val …] — the config-drift announcer probe (byte-kept from the suites) ─
drift_out() {  # $1=script ; rest=VAR=val overrides
    local script="$1"; shift
    (
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        log_info(){ :; }; log_error(){ :; }
        log_warn(){ printf '%s\n' "$*"; }
        for kv in "$@"; do eval "$kv"; done
        announce_config_drift
    )
}

# ── mutate <file> <sed-expr> <out> — a mutation control that CANNOT silently no-op (map §3.2) ───
# Applies the sed expression and FAILS the suite loudly if the output is byte-identical to the
# input: a mutation control whose pattern no longer matches the daemon text would otherwise stay
# green for the wrong reason. (Main consumers migrate in 4.2; landed now per the map.)
mutate() {
    local in="$1" expr="$2" out="$3"
    sed "$expr" "$in" > "$out" || { echo "  ❌ FAIL: mutate: sed failed: $expr"; FAIL=$((FAIL+1)); return 1; }
    if cmp -s "$in" "$out"; then
        echo "  ❌ FAIL: mutate: expression changed NOTHING (control would be green-for-the-wrong-reason): $expr on $(basename "$in")"
        FAIL=$((FAIL+1))
        return 1
    fi
    return 0
}

# ── extract_twin <start-regex> <end-regex> — byte-parity extraction from BOTH daemons (map §3.3) ─
# Sets TWIN_P / TWIN_S to `sed -n "/start/,/end/p"` over PRIMARY / STANDBY (always freshly
# assigned — never stale) and FAILS the suite loudly if either side extracted nothing: an anchored
# sed that matches nothing would otherwise compare two empty strings — green for the wrong reason.
extract_twin() {
    local start="$1" end="$2"
    TWIN_P=$(sed -n "/$start/,/$end/p" "$PRIMARY")
    TWIN_S=$(sed -n "/$start/,/$end/p" "$STANDBY")
    if [[ -z "$TWIN_P" || -z "$TWIN_S" ]]; then
        echo "  ❌ FAIL: extract_twin: EMPTY extraction (primary=${#TWIN_P}B standby=${#TWIN_S}B) for anchor: $start"
        FAIL=$((FAIL+1))
        return 1
    fi
    return 0
}

# ── dump_freshness — the SOLE sanctioned reader of the freshness triple (map §3.4, 4.0 GO cond.) ─
# One line of named fields read from the daemon globals in THIS shell (state lives here after
# load_seam — this is NOT for $() subshell mocks). Suites read fields via:
#     $(field "$(dump_freshness)" observed_since)
# and never touch _liveness_first_provider / _liveness_obs_since / _last_blind_end directly
# (priming WRITES in fixtures stay). Empty-safe: numerics default 0, vantage/pair strings empty.
dump_freshness() {
    printf 'vantage=%s|observed_since=%s|blind_until=%s|pair_vote=%s|pair_tip=%s|pair_ts=%s|pair_prov=%s|lla=%s\n' \
        "${_liveness_first_provider:-}" \
        "${_liveness_obs_since:-0}" \
        "${_last_blind_end:-0}" \
        "${_liveness_first_vote:-}" \
        "${_liveness_first_tip:-}" \
        "${_liveness_first_ts:-0}" \
        "${_liveness_first_provider:-}" \
        "${LAST_LIVENESS_ACTIVE_TIME:-0}"
}
