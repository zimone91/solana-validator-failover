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
    if [[ -s "${_HARNESS_NETLOG:-}" ]]; then   # the net guard (below): named, never silent
        echo "  net-guard: $(grep -c . "$_HARNESS_NETLOG") curl-binary call(s) intercepted — answered rc 7, none sent (first: $(head -1 "$_HARNESS_NETLOG" | cut -c1-100))"
    fi
    if [[ -s "${_HARNESS_NETCLIENT_LOG:-}" ]]; then   # a network client other than curl was reached: a FAIL, never a note
        bad "net-guard: $(grep -c . "$_HARNESS_NETCLIENT_LOG") network-client call(s) reached the guard — failed, none sent (first: $(head -3 "$_HARNESS_NETCLIENT_LOG" | tr '\t\n' ' ;' | cut -c1-160))"
    fi
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

# ── seam_cut <script> — the source-to-MAIN-LOOP cut, cached per (basename, mtime, size) ─────────
# Echoes the path of the cached cut file. The cache lives in a per-process mktemp dir (parallel
# suites never share it; subshells of ONE suite do — the cut re-read ~200 KB per call before).
# The cache file is read-only shared state: NEVER edit it in place — mutation controls copy first
# (see mutate()).
# The size component closes the same-second collision: a file rewritten with different content
# within one mtime second would otherwise key to the same cache entry and serve a STALE cut.
_HARNESS_TMP=$(mktemp -d)

# ── the net guard (v0.7 Block 6.3.1 fix round 1 — the panel's T10, N-is-all over the suites) ───────────
# A directory FIRST in PATH for every suite that sources this harness, holding a stand-in for every network client a
# suite could reach through PATH:
#   - curl ANSWERS rc 7 (connection refused — what an unanswered LOCAL read returns) and logs the call. The suites shadow
#     the daemons' reads as shell FUNCTIONS, so only an unshadowed caller (or `command curl`) reaches a curl BINARY — and on
#     a host with a validator RPC on 127.0.0.1:8899 it would query that live node (with the port filtered, each call would
#     wait out its -m bound). Answered, a suite behaves as it did where nothing listens; results_banner names the count.
#     Enumerated with a logging curl first in PATH over every suite: 12 suites' own-head samples (the [own-view] sampler,
#     unshadowed there) reached 127.0.0.1:8899 this way; test_act_then_alert (15) holds its own sims to zero with a
#     sim-level logger.
#   - every other client, HARNESS_NET_CLIENTS below, FAILS (rc 2) and logs the call to the client log — a suite that
#     reaches one FAILS (results_banner), and tests/run_all.sh FAILS the gate naming the suite and the call (run_all
#     passes each suite its own log as HARNESS_NETGUARD_LOG, and puts the same failing clients — curl failing too — first
#     in PATH for every suite, test_v058_regression included, which does not source this harness). Each stand-in has
#     its log path written into it, so a child started with `env -i` still logs.
# Left out, on purpose: socat (the daemons' sd_notify datagrams go to a UNIX socket, and the fence and arm suites run it
# so) and the interpreters (perl, python3, python, ruby, node: test_primary_self_fence reads a millisecond clock through
# perl, test_arm_ceremony finds python3 and perl through PATH and provisions them to its scenarios as removal tools — an
# interpreter's socket cannot be told apart from its local use by a wrapper).
# LIMIT (named): the guard is PATH-based — `curl`, `command curl`, `ping` reach it; an absolute path (/usr/bin/curl,
# /sbin/ping), a PATH a suite builds without this directory (the arm suites' `env -i PATH="$STUB_DIR:$TOOLDIR"`
# scenarios), a client outside the list and an interpreter's socket do not.
HARNESS_NET_CLIENTS="ping ping6 nc ncat netcat wget dig host nslookup drill getent ssh scp sftp telnet traceroute tftp ftp whois nmap openssl rsync git"
mkdir -p "$_HARNESS_TMP/netguard"
_HARNESS_NETLOG="$_HARNESS_TMP/netguard/log"; export _HARNESS_NETLOG
_HARNESS_NETCLIENT_LOG="${HARNESS_NETGUARD_LOG:-$_HARNESS_TMP/netguard/clients.log}"
case "$_HARNESS_NETLOG$_HARNESS_NETCLIENT_LOG" in *"'"*) echo "  ❌ FAIL: net guard: a log path holds a quote: $_HARNESS_NETCLIENT_LOG"; exit 1 ;; esac
cat > "$_HARNESS_TMP/netguard/curl" <<EOS
#!/bin/sh
printf '%s\n' "\$*" >> '$_HARNESS_NETLOG'
exit 7
EOS
for _hc in $HARNESS_NET_CLIENTS; do
    cat > "$_HARNESS_TMP/netguard/$_hc" <<EOS
#!/bin/sh
printf '%s\t%s\n' '$_hc' "\$*" >> '$_HARNESS_NETCLIENT_LOG'
exit 2
EOS
done
chmod +x "$_HARNESS_TMP/netguard/"*
PATH="$_HARNESS_TMP/netguard:$PATH"; export PATH
seam_cut() {
    local script="$1" mt sz cache
    [[ -f "$script" ]] || { echo "  ❌ FAIL: seam_cut: no such script: $script" >&2; return 1; }
    # mtime: GNU/busybox `stat -c %Y` FIRST — on busybox (the bash:5.2 CI image) `stat -f %m`
    # does not fail, it prints multi-line FILESYSTEM status (found red on Linux, 2026-08-19);
    # macOS/BSD stat has no -c and falls through to -f %m.
    mt=$(stat -c %Y "$script" 2>/dev/null || stat -f %m "$script" 2>/dev/null)
    case "$mt" in *[!0-9]*) mt="" ;; esac   # anything non-numeric → no mtime key (cache still per-process)
    sz=$(wc -c < "$script" 2>/dev/null | tr -d '[:space:]')   # BSD wc pads with spaces
    case "$sz" in *[!0-9]*) sz="" ;; esac   # numeric-validated like mtime
    cache="$_HARNESS_TMP/$(basename "$script").${mt:-0}.${sz:-0}.cut"
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

# ── extract_region <file> <start-regex> <end-regex> — loud single-file region extraction ────────
# `sed -n "/start/,/end/p"` over ONE file; echoes the extracted text on stdout. FAILS the suite
# loudly (❌ + FAIL counter + rc 1) when the extraction is EMPTY: an anchored sed whose anchor
# text moved would otherwise hand the caller an empty region — sourcing/eval'ing an empty string
# is a silent no-op seam, green for the wrong reason. The ❌ goes to stderr (stdout carries the
# region and is usually $()-captured); callers hold the suite-side red:
#     region=$(extract_region "$PRIMARY" 'start' 'end') || bad "…"; eval "$region"
extract_region() {
    local file="$1" start="$2" end="$3" _r
    [[ -f "$file" ]] || { echo "  ❌ FAIL: extract_region: no such file: $file" >&2; FAIL=$((FAIL+1)); return 1; }
    _r=$(sed -n "/$start/,/$end/p" "$file")
    if [[ -z "$_r" ]]; then
        echo "  ❌ FAIL: extract_region: EMPTY extraction (anchor matched nothing): $start on $(basename "$file")" >&2
        FAIL=$((FAIL+1))
        return 1
    fi
    printf '%s\n' "$_r"
    return 0
}

# ── mutate_filter <in> <out> <cmd…> — generic stdin→stdout filter form of mutate() (map §3.2) ───
# Runs `cmd… < in > out` (the awk-strip control class). FAILS the suite loudly (❌ + FAIL counter
# + rc 1) if the filter errored OR the output is byte-identical to the input: a filter whose
# marker text no longer matches the daemon would otherwise no-op silently and the control stays
# green for the wrong reason (the cannot-silently-no-op contract, same as mutate()).
mutate_filter() {
    local in="$1" out="$2"
    shift 2
    if ! "$@" < "$in" > "$out"; then
        echo "  ❌ FAIL: mutate_filter: filter failed: $1 on $(basename "$in")"
        FAIL=$((FAIL+1))
        return 1
    fi
    if cmp -s "$in" "$out"; then
        echo "  ❌ FAIL: mutate_filter: filter changed NOTHING (control would be green-for-the-wrong-reason): $1 on $(basename "$in")"
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

# ── bash's OWN parse — bp_parse / bp_exec / bp_bodies (v0.7 Block 6.3.1 fix round 5) ──────────────────────────────
# The structural censuses (test_own_view (0a) (0b) (0d) (1a) (7g) (7g-local), test_arm_ceremony (16h)) read bash's
# normalized print of a file instead of its source lines: bp_parse wraps the file in two functions — everything before
# the MAIN LOOP marker line, and everything after it (a file without the marker: all of it, and an empty second one) —
# sources that copy in `env -i bash` (definitions only: nothing in the file runs; no harness shim exists there) and
# takes `declare -f` of both.
# That print is bash's own parse: comments gone, one command per line, every nested definition printed on its own lines
# as `function NAME () `, a one-line body expanded, the `function` keyword and `NAME ( )` normalized — outside a command
# substitution: bash 3.2 prints a $( ) VERBATIM (its comments and a `function`-keyword definition inside it survive; the
# lexer drops such a comment itself), bash 5.2 re-prints it. BP_LEX_AWK reads THAT text (quoting, $( ), ${ }, $(( )),
# here-documents, case patterns, [[ ]]) as bash runs it: a $(( whose inner ( closes on ") )" — not "))" — is a command
# substitution holding a subshell, as bash reads it, and the body of an UNQUOTED here-document is lexed for the $( ),
# backticks, ${ } and $(( )) bash expands in it (a quoted delimiter's body stays text). Its TAB-separated records:
#   D <name> <depth> <sub> <line> <fn>   a function definition; depth 1 = the file level, 2+ = nested; sub=1 inside a
#                                        ( ) subshell or a substitution; <fn> = where it sits
#   E <name> <depth> <line>              that definition's closing brace
#   C <fn> <depth> <line> <n> <words> <ctx>  a simple command: n words joined by \034, each "<L|X><quote-removed>\035<raw>" —
#                                        L: no expansion in it; quote-removed: its quotes and backslashes deleted, so
#                                        'eval' ev''al \source "curl" cu''rl c\url read as eval source curl; <ctx> =
#                                        "<level>:<subshell>:<pre>:<post>" — level 1 = not inside a substitution (a
#                                        here-document body's $( ) is one), subshell = the ( ) depth there, pre = the
#                                        operator before it (&& || | |&, or empty at a statement's start), post = the one
#                                        after it (&& || | |& & ; ;; nl ) or empty)
#   K <fn> <depth> <line> <level> <subshell> <event> <id> <ctx>  the structure, in order: if then else fi, loop (while
#                                        until for select) do done, case arm arm-end esac, grp grp-end ({ }) — <id> the
#                                        compound command's number; <ctx> = the operator before an opening (a compound
#                                        that is the operand of && || | |&), an arm's pattern words (|-joined), an
#                                        arm-end's terminator
#   A <id>                               that compound command is followed by | |& or & — a pipeline element or a
#                                        background job (it runs in a subshell)
#   L <fn> <depth> <line> <code> <raw>   a logical line: <code> = quoted content blanked, a literal name-shaped word written
#                                        quote-removed, a $( ) / backticks inside a quoted span or a ${ } lifted out and
#                                        appended as " ; <its code view>", comments and case patterns dropped; <raw> = as
#                                        printed (TABs and newlines as blanks); an unquoted here-document body line with
#                                        a lifted $( ) gets an L of its own (<raw> empty: its H record holds the text)
#   H <fn> <depth> <line> <raw> <q>      a here-document body line; q = 1 behind a quoted delimiter (text), 0 unquoted
#   R <fn> <depth> <line> <kind> <raw>   kind "redir": a redirection target or a here-string; "pat": a case-pattern word
# <fn> is the innermost enclosing function: "(top)" = the file level before the marker, "(post)" = after it. The lexer
# still reads bash syntax — but bash's print of it, not an author's spelling. LIMIT, named: a command word assembled at
# run time ($x, "$cmd", $(…) as the command); code inside a STRING a command runs — eval, trap, mapfile -C, a shell's
# -c — which the lexer cannot read as code: the (0d) census flags eval anywhere and pins every trap / mapfile /
# readarray, and (7g) and (1a) flag a shell (bash / sh / dash / zsh / ksh) run as a command, directly or behind timeout /
# env / command / nohup / nice / setsid / xargs / exec (bpshell below) — no census flags a shell behind another wrapper
# (find -exec, sudo, flock -c) or code an interpreter runs from a string (awk's system(), perl -e, python3 -c); a
# here-document opened inside a here-document body's $( ) (read as that body's text); a nested backtick inside
# backticks; and aliases (expand_aliases is off in a script; the (0d) census flags alias and shopt by name).
BP_LEX_AWK='
function fnname(   n) { if (fsp == 0) return ""; n = fname[fsp]; if (wrap && fsp == 1) { if (n == "__bp_top__") return "(top)"; if (n == "__bp_post__") return "(post)" } return n }
function fndep() { return (wrap && fsp > 0) ? fsp - 1 : fsp }
function cstop(l) { return substr(cs[l], length(cs[l]), 1) }
function wstart(l) { if (!win[l]) { win[l] = 1; wst[l] = POS; wqr[l] = ""; wlit[l] = 1; wq[l] = 0; wcv[l] = ""; if (cmdn[l] == 0) { cln[l] = LNR; cvm[l] = length(cv[l]); cpre[l] = lop[l] } } }
function kev(l, ev, id, cx) { printf "K\t%s\t%d\t%d\t%d\t%d\t%s\t%s\t%s\n", fnname(), fndep(), LNR, l, pd[l], ev, id, cx }
function fopen(l, ev) { fid++; fk++; fsk[fk] = fid; kev(l, ev, fid, lop[l]); lop[l] = "" }
function fclose(l, ev,   id) { id = (fk > 0) ? fsk[fk] : 0; if (fk > 0) fk--; kev(l, ev, id, ""); pclose[l] = id }
function endword(l,   raw, disp, q) {
    if (!win[l]) return
    win[l] = 0
    raw = substr(LB, wst[l], POS - wst[l]); gsub(/[\t\n]/, " ", raw)
    q = wqr[l]; gsub(/[\t\n]/, " ", q)
    disp = (wlit[l] && wq[l] && q ~ "^[A-Za-z0-9_./@%+,:=-]+$") ? q : wcv[l]
    cv[l] = cv[l] disp
    if (cmdn[l] == 0 && wlit[l] && !wq[l] && q == "esac" && cstop(l) == "p") { cs[l] = substr(cs[l], 1, length(cs[l]) - 1); fclose(l, "esac"); return }
    if (cstop(l) == "p") { patraw[l] = patraw[l] (patraw[l] == "" ? "" : "|") raw; printf "R\t%s\t%d\t%d\tpat\t%s\n", fnname(), fndep(), LNR, raw; return }   # a case pattern word
    if (redir[l]) { redir[l] = 0; printf "R\t%s\t%d\t%d\tredir\t%s\n", fnname(), fndep(), LNR, raw; return }                      # the target of a redirection, a here-string
    if (cmdn[l] == 0 && wlit[l] && !wq[l] && q ~ /^(if|then|else|elif|fi|do|done|while|until|!|time)$/) {
        if (q == "if") fopen(l, "if"); else if (q == "while" || q == "until") fopen(l, "loop"); else if (q == "fi" || q == "done") fclose(l, q)
        else if (q != "!" && q != "time") kev(l, q, fsk[fk], "")
        return
    }
    if (cmdn[l] == 0 && wlit[l] && !wq[l] && (q == "for" || q == "select")) fopen(l, "loop")
    if (cmdn[l] == 0 && wlit[l] && !wq[l] && q == "case") fopen(l, "case")
    if (wlit[l] && !wq[l] && q == "[[") cond[l] = 1
    if (wlit[l] && !wq[l] && q == "]]") cond[l] = 0
    cmdw[l] = cmdw[l] (cmdn[l] ? "\034" : "") (wlit[l] ? "L" : "X") q "\035" raw
    cmdn[l]++
}
function endcmd(l, op,   first) {
    endword(l)
    if (cmdn[l] > 0) {
        printf "C\t%s\t%d\t%d\t%d\t%s\t%d:%d:%s:%s\n", fnname(), fndep(), cln[l], cmdn[l], cmdw[l], l, pd[l], cpre[l], op
        first = cmdw[l]; sub(/\035.*/, "", first)
        if (first == "Lcase") cs[l] = cs[l] "p"
        lop[l] = (op == "&&" || op == "||" || op == "|" || op == "|&") ? op : ""
    } else if (op == "&&" || op == "||" || op == "|" || op == "|&") lop[l] = op
    else if (op == ";" || op == "&" || op == ";;" || op == ";&" || op == ";;&") lop[l] = ""
    if (pclose[l] != "" && op != "") { if (op == "|" || op == "|&" || op == "&") printf "A\t%s\n", pclose[l]; pclose[l] = "" }
    cmdw[l] = ""; cmdn[l] = 0; cond[l] = 0; redir[l] = 0
}
function push(t, o) { sp++; ty[sp] = t; own[sp] = o; pb[sp] = 0; ap[sp] = 0 }
function pushc(closer, lf) {                                                                # a nested code level: $( ) ` ` <( )
    sp++; ty[sp] = "C"; cl[sp] = closer; lift[sp] = lf; pd[sp] = 0; cv[sp] = ""; cmdw[sp] = ""; cmdn[sp] = 0; win[sp] = 0
    cond[sp] = 0; redir[sp] = 0; cs[sp] = ""; defpend[sp] = ""; lop[sp] = ""; pclose[sp] = ""; patraw[sp] = ""
}
function popc(   l, inner, p) {
    l = sp; endcmd(l, ")"); inner = cv[l]; sp--; p = sp
    if (lift[l]) LIFTS = LIFTS " ; " inner
    else if (cl[l] == "`") wcv[p] = wcv[p] "`" inner "`"
    else wcv[p] = wcv[p] "$(" inner ")"
}
function inq(   k) { for (k = sp; k >= 1 && ty[k] != "C"; k--) if (ty[k] == "D" || ty[k] == "Q") return 1; return 0 }
function emitline(   raw, code) {
    raw = LB; gsub(/[\t\n]/, " ", raw); code = cv[1] LIFTS; gsub(/[\t\n]/, " ", code)
    printf "L\t%s\t%d\t%d\t%s\t%s\n", lfn, ldep, LN, code, raw
    LB = ""; LIFTS = ""; cv[1] = ""; started = 0
}
function isarith(p,   r, s, q, ch, dep, qs) {   # "$((" at column p of the current line: arithmetic when the ) that closes its inner ( is followed by ) (the rule of bash); else a command substitution holding a subshell
    r = LNR; s = LINES[r]; q = p + 3; dep = 0; qs = 0
    while (1) {
        if (q > length(s)) { r++; if (r > NLINES) return 1; s = LINES[r]; q = 1; continue }
        ch = substr(s, q, 1)
        if (qs == 1) { if (ch == "\047") qs = 0; q++; continue }
        if (qs == 2) { if (ch == "\\") { q += 2; continue } if (ch == "\"") qs = 0; q++; continue }
        if (ch == "\\") { q += 2; continue }
        if (ch == "\047") { qs = 1; q++; continue }
        if (ch == "\"") { qs = 2; q++; continue }
        if (ch == "(") { dep++; q++; continue }
        if (ch == ")") { if (dep > 0) { dep--; q++; continue } return (substr(s, q + 1, 1) == ")") }
        q++
    }
}
function scan(line) {
    n = length(line); i = 1
    while (i <= n + 1) {
        POS = off + i - 1
        c = (i <= n) ? substr(line, i, 1) : "\n"
        t = ty[sp]
        if (t == "S") {                                                                       # a single-quoted span
            o = own[sp]; k = index(substr(line, i), "\047")
            if (k == 0) { wqr[o] = wqr[o] substr(line, i) " "; i = n + 2; continue }
            wqr[o] = wqr[o] substr(line, i, k - 1); i += k; sp--
            if (ty[sp] == "C") wcv[o] = wcv[o] "\047"
            continue
        }
        if (t == "E") {                                                                       # an ANSI-C span
            o = own[sp]
            if (c == "\\") { wqr[o] = wqr[o] substr(line, i + 1, 1); i += 2; continue }
            if (c == "\047") { sp--; i++; if (ty[sp] == "C") wcv[o] = wcv[o] "\047"; continue }
            wqr[o] = wqr[o] (c == "\n" ? " " : c); i++; continue
        }
        if (t == "D" || t == "P" || t == "A" || t == "R" || t == "Q") {                        # "…", ${ }, $(( )), an array literal, an unquoted here-document body
            o = own[sp]
            if (t == "D" && match(substr(line, i), /^[^"\\$`]+/)) { wqr[o] = wqr[o] substr(line, i, RLENGTH); i += RLENGTH; continue }
            if (t == "Q" && match(substr(line, i), /^[^\\$`]+/)) { wqr[o] = wqr[o] substr(line, i, RLENGTH); i += RLENGTH; continue }
            if (c == "\n") { wqr[o] = wqr[o] " "; i++; continue }
            if (c == "\\") {
                d = substr(line, i + 1, 1); if (d == "") { i += 2; continue }
                if ((t == "D" && d !~ /["\\$`]/) || (t == "Q" && d !~ /[\\$`]/)) wqr[o] = wqr[o] "\\"
                wqr[o] = wqr[o] d; if (t != "D" && t != "Q") wlit[o] = 0; i += 2; continue
            }
            if (c == "\"" && t == "D") { sp--; i++; if (ty[sp] == "C") wcv[o] = wcv[o] "\""; continue }
            if (c == "\"" && t != "Q") { push("D", o); i++; continue }
            if (c == "\047" && t != "D" && t != "Q" && !(t == "P" && inq())) { push("S", o); wlit[o] = 0; i++; continue }
            if (c == "$" && substr(line, i + 1, 2) == "((" && isarith(i)) { push("A", o); wlit[o] = 0; wqr[o] = wqr[o] "$(())"; i += 3; continue }
            if (c == "$" && substr(line, i + 1, 1) == "(") { wlit[o] = 0; wqr[o] = wqr[o] "$()"; pushc(")", 1); i += 2; continue }
            if (c == "$" && substr(line, i + 1, 1) == "{") { push("P", o); wlit[o] = 0; wqr[o] = wqr[o] "${"; i += 2; continue }
            if (c == "`") { wlit[o] = 0; wqr[o] = wqr[o] "$()"; pushc("`", 1); i++; continue }
            if (c == "$") { wlit[o] = 0; wqr[o] = wqr[o] c; i++; continue }
            if (t == "P" && c == "{") pb[sp]++
            else if (t == "P" && c == "}") { if (pb[sp] > 0) pb[sp]--; else { wqr[o] = wqr[o] "}"; sp--; i++; continue } }
            else if (t == "A" && c == "(") ap[sp]++
            else if (t == "A" && c == ")") { if (ap[sp] > 0) ap[sp]--; else { sp--; i += (substr(line, i + 1, 1) == ")") ? 2 : 1; continue } }
            else if (t == "R" && c == ")") { sp--; i++; continue }
            if (t != "D" && t != "Q") wlit[o] = 0
            wqr[o] = wqr[o] c; i++; continue
        }
        # ── code ──
        l = sp
        if (cont && c == "\n") { cont = 0; i++; continue }
        if (c == "\n") {
            endword(l); endcmd(l, "nl")
            if (l == 1) { emitline(); if (nhd > 0) HD = 1; i++; continue }
            cv[l] = cv[l] " ; "; if (nhd > 0) HD = 1; i++; continue
        }
        if (c == "`" && cl[l] == "`") { popc(); i++; continue }
        if (c == " " || c == "\t") { endword(l); if (cv[l] != "" && substr(cv[l], length(cv[l]), 1) != " ") cv[l] = cv[l] " "; i++; continue }
        if (c == "#" && !win[l]) { i = n + 1; continue }                                       # a comment (only a 3.2 verbatim $( ) has one)
        if (cond[l] && c ~ /[()|&<>]/) { wstart(l); wqr[l] = wqr[l] c; wcv[l] = wcv[l] c; i++; continue }   # inside [[ ]]
        if (!win[l] && match(substr(line, i), /^[^ \t\047"\\$`#<>()|;&{}]+/)) {                     # a run of plain word characters
            wstart(l); s = substr(line, i, RLENGTH); wqr[l] = wqr[l] s; wcv[l] = wcv[l] s; i += RLENGTH; continue
        }
        if (win[l] && match(substr(line, i), /^[^ \t\047"\\$`<>()|;&]+/)) {
            s = substr(line, i, RLENGTH); wqr[l] = wqr[l] s; wcv[l] = wcv[l] s; i += RLENGTH; continue
        }
        if (c == "\\") {
            d = substr(line, i + 1, 1)
            if (d == "") { cont = 1; i++; continue }
            wstart(l); wqr[l] = wqr[l] d; wcv[l] = wcv[l] "\\" d; wq[l] = 1; i += 2; continue
        }
        if (c == "\047") { wstart(l); wq[l] = 1; wcv[l] = wcv[l] "\047"; push("S", l); i++; continue }
        if (c == "\"") { wstart(l); wq[l] = 1; wcv[l] = wcv[l] "\""; push("D", l); i++; continue }
        if (c == "$") {
            wstart(l); d = substr(line, i + 1, 1)
            if (d == "(" && substr(line, i + 2, 1) == "(" && isarith(i)) { wlit[l] = 0; wqr[l] = wqr[l] "$(())"; wcv[l] = wcv[l] "$(())"; push("A", l); i += 3; continue }
            if (d == "(") { wlit[l] = 0; wqr[l] = wqr[l] "$()"; pushc(")", 0); i += 2; continue }
            if (d == "{") { wlit[l] = 0; wqr[l] = wqr[l] "${"; wcv[l] = wcv[l] "${}"; push("P", l); i += 2; continue }
            if (d == "\047") { wq[l] = 1; wcv[l] = wcv[l] "$\047"; push("E", l); i += 2; continue }
            if (d == "\"") { wq[l] = 1; wcv[l] = wcv[l] "\""; push("D", l); i += 2; continue }
            if (match(substr(line, i + 1), /^[A-Za-z_][A-Za-z0-9_]*/)) { s = substr(line, i, RLENGTH + 1); wlit[l] = 0; wqr[l] = wqr[l] s; wcv[l] = wcv[l] s; i += RLENGTH + 1; continue }
            if (d != "" && index("0123456789#?$!@*-", d)) { wlit[l] = 0; wqr[l] = wqr[l] "$" d; wcv[l] = wcv[l] "$" d; i += 2; continue }
            wqr[l] = wqr[l] "$"; wcv[l] = wcv[l] "$"; i++; continue
        }
        if (c == "`") { wstart(l); wlit[l] = 0; wqr[l] = wqr[l] "$()"; pushc("`", 0); i++; continue }
        if (cstop(l) == "p" && c == "|") { endword(l); i++; continue }                          # the alternatives of a case pattern
        if ((c == "<" || c == ">") && substr(line, i + 1, 1) == "(") { wstart(l); wlit[l] = 0; wqr[l] = wqr[l] "$()"; pushc(")", 0); i += 2; continue }
        if (c == "<" || c == ">") {
            if (win[l] && wlit[l] && !wq[l] && wqr[l] ~ /^[0-9]+$/) { win[l] = 0; cv[l] = cv[l] wqr[l] }   # an fd number
            else endword(l)
            if (substr(line, i, 3) == "<<<") { cv[l] = cv[l] " <<< "; redir[l] = 1; i += 3; continue }
            if (substr(line, i, 2) == "<<") {                                                 # a here-document: read its delimiter (quoted: a literal body)
                i += 2; dash = 0; if (substr(line, i, 1) == "-") { dash = 1; i++ }
                while (substr(line, i, 1) == " ") i++
                dl = ""; dq = 0
                while (i <= n && substr(line, i, 1) !~ /[ ;&|<>)]/) {
                    ch = substr(line, i, 1)
                    if ((ch == "\047" || ch == "\"") && (k = index(substr(line, i + 1), ch))) { dq = 1; dl = dl substr(line, i + 1, k - 1); i += k + 1; continue }   # a quoted part, blanks included
                    if (ch == "\\") { dq = 1; dl = dl substr(line, i + 1, 1); i += 2; continue }
                    dl = dl ch; i++
                }
                if (!hqopen) { nhd++; hdelim[nhd] = dl; hdash[nhd] = dash; hdq[nhd] = dq }
                cv[l] = cv[l] " <<" dl " "; continue
            }
            op = c; i++; while (length(op) < 2 && substr(line, i, 1) ~ /[<>&|]/) { op = op substr(line, i, 1); i++ }
            cv[l] = cv[l] " " op " "
            if (op ~ /&$/ && substr(line, i, 1) ~ /[0-9-]/) { while (substr(line, i, 1) ~ /[0-9-]/) i++ }  # >&1 / >&- : no target word
            else redir[l] = 1
            continue
        }
        if (c == "&") {
            endword(l)
            if (substr(line, i + 1, 1) == ">") { i += 2; op = "&>"; if (substr(line, i, 1) == ">") { op = "&>>"; i++ } cv[l] = cv[l] " " op " "; redir[l] = 1; continue }
            if (substr(line, i + 1, 1) == "&") { endcmd(l, "&&"); cv[l] = cv[l] " && "; i += 2; continue }
            endcmd(l, "&"); cv[l] = cv[l] " & "; i++; continue
        }
        if (c == "|") {
            if (substr(line, i + 1, 1) == "|") { endcmd(l, "||"); cv[l] = cv[l] " || "; i += 2; continue }
            if (substr(line, i + 1, 1) == "&") { endcmd(l, "|&"); cv[l] = cv[l] " |& "; i += 2; continue }
            endcmd(l, "|"); cv[l] = cv[l] " | "; i++; continue
        }
        if (c == ";") {
            if (substr(line, i, 3) == ";;&") op = ";;&"; else if (substr(line, i, 2) == ";;" || substr(line, i, 2) == ";&") op = substr(line, i, 2); else op = ";"
            endcmd(l, op)
            i += length(op); cv[l] = cv[l] " " op " "
            if (op != ";" && cs[l] != "") { cs[l] = substr(cs[l], 1, length(cs[l]) - 1) "p"; kev(l, "arm-end", fsk[fk], op) }
            continue
        }
        if (c == "(") {
            if (win[l] && substr(wqr[l], length(wqr[l]), 1) == "=") { wlit[l] = 0; wqr[l] = wqr[l] "("; wcv[l] = wcv[l] "()"; push("R", l); i++; continue }
            endword(l)
            if (substr(line, i + 1, 1) == ")") {                                               # NAME () / function NAME () — a definition
                w = cmdw[l]; nm = ""
                if (cmdn[l] == 1) { nm = w; sub(/\035.*/, "", nm); nm = substr(nm, 2) }
                else if (cmdn[l] == 2 && w ~ /^Lfunction\035/) { nm = w; sub(/^[^\034]*\034/, "", nm); sub(/\035.*/, "", nm); nm = substr(nm, 2) }
                if (nm != "") {
                    printf "D\t%s\t%d\t%d\t%d\t%s\n", nm, fsp + 1 - (wrap ? 1 : 0), (pd[l] > 0 || l > 1) ? 1 : 0, LNR, fnname()
                    defpend[l] = nm; cmdw[l] = ""; cmdn[l] = 0; cv[l] = substr(cv[l], 1, cvm[l]) "function " nm " () "; i += 2; continue
                }
            }
            if (substr(line, i + 1, 1) == "(" && (cmdn[l] == 0 || cmdw[l] ~ /^Lfor\035/)) { wstart(l); wlit[l] = 0; wcv[l] = wcv[l] "(())"; push("A", l); i += 2; continue }
            endcmd(l, ""); pd[l]++; lop[l] = ""; cv[l] = cv[l] "( "; i++; continue
        }
        if (c == ")") {
            if (pd[l] > 0) { endcmd(l, ")"); pd[l]--; cv[l] = cv[l] " )"; i++; continue }
            if (cl[l] == ")") { popc(); i++; continue }
            if (cstop(l) == "p") {                                                             # the end of a case pattern: blanked
                endword(l); cv[l] = ""; cmdw[l] = ""; cmdn[l] = 0; cs[l] = substr(cs[l], 1, length(cs[l]) - 1) "b"
                kev(l, "arm", fsk[fk], patraw[l]); patraw[l] = ""; lop[l] = ""; i++; continue
            }
            endcmd(l, ")"); cv[l] = cv[l] " )"; i++; continue
        }
        if (c == "{" && !win[l] && (i == n || substr(line, i + 1, 1) == " ")) {                          # { — a group or a function body
            if (defpend[l] == "" && cmdn[l] == 2 && cmdw[l] ~ /^Lfunction\035/) {                    # function NAME { — the keyword form bash 3.2 keeps inside a verbatim $( )
                nm = cmdw[l]; sub(/^[^\034]*\034/, "", nm); sub(/\035.*/, "", nm); nm = substr(nm, 2)
                printf "D\t%s\t%d\t%d\t%d\t%s\n", nm, fsp + 1 - (wrap ? 1 : 0), (pd[l] > 0 || l > 1) ? 1 : 0, LNR, fnname()
                defpend[l] = nm; cmdw[l] = ""; cmdn[l] = 0; cv[l] = substr(cv[l], 1, cvm[l]) "function " nm " () "
            }
            endcmd(l, ""); bsp++
            if (defpend[l] != "") { fsp++; fname[fsp] = defpend[l]; fbs[fsp] = bsp; defpend[l] = ""; lfn = fnname(); ldep = fndep() }
            else { fopen(l, "grp"); grp[bsp] = 1 }
            cv[l] = cv[l] "{ "; i++; continue
        }
        if (c == "}" && !win[l] && (i == n || substr(line, i + 1, 1) ~ /[ ;)&|<>]/)) {                  # } — the end of a group or a body
            endcmd(l, "")
            if (fsp > 0 && fbs[fsp] == bsp) { printf "E\t%s\t%d\t%d\n", fname[fsp], fsp - (wrap ? 1 : 0), LNR; fsp-- }
            else if (grp[bsp]) { grp[bsp] = 0; fclose(l, "grp-end") }
            if (bsp > 0) bsp--
            cv[l] = cv[l] "}"; i++; continue
        }
        wstart(l); wqr[l] = wqr[l] c; wcv[l] = wcv[l] c; i++
    }
}
function lexline(line,   hl, hr) {
    if (HD) {                                                                                 # a here-document body line
        hl = line; if (hdash[1]) sub(/^\t+/, "", hl)
        if (hl == hdelim[1]) {
            if (hqopen) { sp = hqsp; hqopen = 0; LIFTS = hqlifts }                              # the body ends: back to the level of its command
            for (k = 1; k < nhd; k++) { hdelim[k] = hdelim[k + 1]; hdash[k] = hdash[k + 1]; hdq[k] = hdq[k + 1] }
            nhd--; if (nhd == 0) HD = 0; return
        }
        hr = line; gsub(/\t/, " ", hr); printf "H\t%s\t%d\t%d\t%s\t%d\n", fnname(), fndep(), LNR, hr, hdq[1]
        if (!hdq[1]) {                                                                        # UNQUOTED: bash expands its $( ), ` `, ${ } and $(( ))
            if (!hqopen) { hqsp = sp; hqlifts = LIFTS; LIFTS = ""; push("Q", sp); hqopen = 1 }
            hl = LB; LB = line; off = 1; scan(line); LB = hl
            if (ty[sp] == "Q" && LIFTS != "") { hl = LIFTS; gsub(/[\t\n]/, " ", hl); printf "L\t%s\t%d\t%d\t%s\t\n", fnname(), fndep(), LNR, hl; LIFTS = "" }
        }
        return
    }
    if (!started) { started = 1; LN = LNR; LB = ""; LIFTS = ""; lfn = fnname(); ldep = fndep() }
    if (LB == "") { off = 1; LB = line } else { off = length(LB) + 2; LB = LB "\n" line }
    scan(line)
}
BEGIN { sp = 1; ty[1] = "C"; cl[1] = ""; lift[1] = 0; pd[1] = 0; cv[1] = ""; cmdw[1] = ""; cmdn[1] = 0; win[1] = 0; cs[1] = ""; defpend[1] = ""
        lop[1] = ""; pclose[1] = ""; patraw[1] = ""; fsp = 0; bsp = 0; HD = 0; nhd = 0; started = 0; cont = 0; fid = 0; fk = 0; hqopen = 0 }
{ LINES[NR] = $0 }
END { NLINES = NR; for (LNR = 1; LNR <= NLINES; LNR++) lexline(LINES[LNR])
      if (started) { endcmd(1, "nl"); emitline() } }
'
# BP_AWK_LIB — functions every census prepends to its awk program over bp_parse's lex (fields TAB-separated):
#   bpq(w) / bpr(w) — a C-record word, quote-removed / raw; bplit(w) — 1 when it holds no expansion
#   bpcmd(n, W)     — the index of a command's effective word: past its assignments, a `time` keyword's -p / -- (the lexer
#                     drops the keyword itself, as it drops `!`), a builtin [--] and a command [-p] [--] prefix (0 for
#                     `command -v|-V …`, a lookup, and for a command of assignments only)
#   bpshell(n, W)   — the index of a SHELL the command runs (bash sh dash zsh ksh, any path prefix) as its effective word
#                     or behind timeout / env / nohup / nice / setsid / xargs / exec / command / builtin; 0 when none
BP_AWK_LIB='
function bpq(w) { sub(/\035.*/, "", w); return substr(w, 2) }
function bpr(w) { sub(/^[^\035]*\035/, "", w); return w }
function bplit(w) { return substr(w, 1, 1) == "L" }
function bpcmd(n, W,   k, q, lead) {
    lead = 1
    for (k = 1; k <= n; k++) {
        q = bpq(W[k])
        if (lead && (q == "-p" || q == "--")) continue
        lead = 0
        if (q ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/) continue
        if (q == "builtin") { if (k < n && bpq(W[k + 1]) == "--") k++; continue }
        if (q == "command") {
            while (k < n && bpq(W[k + 1]) ~ /^-[pvV]+$/) { if (bpq(W[k + 1]) ~ /[vV]/) return 0; k++ }
            if (k < n && bpq(W[k + 1]) == "--") k++
            continue
        }
        return k
    }
    return 0
}
function bpshell(n, W,   k, q, b) {
    k = bpcmd(n, W)
    while (k > 0 && k <= n) {
        if (!bplit(W[k])) return 0
        q = bpq(W[k]); b = q; sub(/.*\//, "", b)
        if (b ~ /^(bash|sh|dash|zsh|ksh)$/) return k
        if (b == "timeout") { k++; while (k <= n && bpq(W[k]) ~ /^-/) { if (bpq(W[k]) ~ /^(-k|-s|--kill-after|--signal)$/) k++; k++ } k++; continue }
        if (b == "env") { k++; while (k <= n && (bpq(W[k]) ~ /^-/ || bpq(W[k]) ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) { if (bpq(W[k]) ~ /^(-u|-C|-S|--unset|--chdir|--split-string)$/) k++; k++ } continue }
        if (b == "nice") { k++; while (k <= n && bpq(W[k]) ~ /^-/) { if (bpq(W[k]) == "-n") k++; k++ } continue }
        if (b == "xargs") { k++; while (k <= n && bpq(W[k]) ~ /^-/) { if (bpq(W[k]) ~ /^-[ILnPsdEa]$/) k++; k++ } continue }
        if (b == "nohup" || b == "setsid" || b == "exec" || b == "command" || b == "builtin") { k++; while (k <= n && bpq(W[k]) ~ /^-/) { if (b == "exec" && bpq(W[k]) == "-a") k++; k++ } continue }
        return 0
    }
    return 0
}
'
bp_parse() {   # bp_parse <file> <outdir> → <outdir>/print (bash's print of the wrapped copy), <outdir>/lex (BP_LEX_AWK over
               # it), <outdir>/names (the file-level definitions before the marker, print order); rc 1 (no lex) when bash
               # cannot parse it
    local _f="$1" _o="$2"
    mkdir -p "$_o" || return 1
    awk 'BEGIN { print "__bp_top__() {" } /^# =* MAIN LOOP =*$/ && !m { m = 1; print ":"; print "}"; print "__bp_post__() {"; next }
         { print } END { print ":"; print "}"; if (!m) { print "__bp_post__() {"; print ":"; print "}" } }' "$_f" > "$_o/wrap.sh" || return 1
    env -i PATH="$PATH" "${BASH:-bash}" -c 'source "$1" && declare -f __bp_top__ __bp_post__' _ "$_o/wrap.sh" > "$_o/print" 2> "$_o/print.err" || { : > "$_o/lex"; : > "$_o/names"; return 1; }
    [[ -s "$_o/print" ]] || { : > "$_o/lex"; : > "$_o/names"; return 1; }
    awk -v wrap=1 "$BP_LEX_AWK" "$_o/print" > "$_o/lex"
    awk -F'\t' '$1 == "D" && $3 == 1 && $6 == "(top)" { print $2 }' "$_o/lex" > "$_o/names"
}
bp_exec() {    # bp_exec <file> <outdir> → <outdir>/xnames + <outdir>/xbodies: `declare -F` / `declare -f` after `env -i bash`
               # SOURCES the executable head of the file (a daemon: its seam cut, up to the MAIN LOOP marker — run from
               # <outdir>, so its `source "$CONFIG_FILE"` finds no config; the arm and the fence scripts: every line but their
               # final `main "$@"`) — the functions its top-level code actually leaves defined. rc 1: no such head (install.sh,
               # the wizards — their top level acts; never run)
    local _f="$1" _o="$2"
    mkdir -p "$_o" || return 1
    if grep -q '^# =* MAIN LOOP =*$' "$_f"; then sed -n '1,/^# =* MAIN LOOP =*$/p' "$_f" > "$_o/head.sh"
    elif [[ "$(tail -1 "$_f")" == 'main "$@"' ]]; then sed '$d' "$_f" > "$_o/head.sh"
    else return 1; fi
    ( cd "$_o" && env -i PATH="$PATH" HOME="$_o" "${BASH:-bash}" -c 'source "$1" >/dev/null 2>&1 </dev/null; declare -F > "$2/xnames.raw"; declare -f > "$2/xbodies"' _ "$_o/head.sh" "$_o" ) || return 1
    sed 's/^declare -f //' "$_o/xnames.raw" > "$_o/xnames"
}
bp_xcheck() {  # bp_xcheck <file> <outdir> — after bp_parse into <outdir>: "" when bash, SOURCING the file's executable head
               # (bp_exec), leaves exactly the print's file-level definitions defined, each with its printed body; otherwise one
               # line per difference — EXEC-EXTRA / EXEC-MISSING / EXEC-BODY <name>; NO-HEAD for a file bp_exec never runs
    bp_exec "$1" "$2" || { echo "NO-HEAD"; return 0; }
    awk 'NR == FNR { a[$1] = 1; next } { b[$1] = 1; if (!($1 in a)) print "EXEC-EXTRA " $1 } END { for (n in a) if (!(n in b)) print "EXEC-MISSING " n }' "$2/names" "$2/xnames"
    bp_bodies "$2" > "$2/pbodies"; bp_bodies "$2" x > "$2/xb"
    awk -F'\t' 'NR == FNR { if ($1 in p) p[$1] = p[$1] "\002"; p[$1] = p[$1] $2; next } ($1 in p) && p[$1] != $2 { print "EXEC-BODY " $1 }' "$2/pbodies" "$2/xb"
}
bp_bodies() {  # bp_bodies <outdir> [x] → one line per function, "NAME<TAB>its body", every line of the body with its leading
               # blanks stripped (\001-joined): from <outdir>/print's file-level definitions, or with x from bp_exec's
               # <outdir>/xbodies — the two texts compared line for line (bash prints a nested definition with the
               # indentation of its depth, `function ` before the name and a ";" after the brace when more follows)
    if [[ "${2:-}" == "x" ]]; then
        awk '/^[^ \t]+ \(\) $/ { if (n != "") print n "\t" b; n = $1; b = ""; next } { l = $0; sub(/^[ \t]+/, "", l); b = b "\001" l } END { if (n != "") print n "\t" b }' "$1/xbodies"
    else
        awk -F'\t' 'NR == FNR { if ($1 == "D" && $3 == 1 && $6 == "(top)") s[$5] = $2; if ($1 == "E" && $3 == 1) e[$4] = 1; next }
             (FNR in s) { n = s[FNR]; b = ""; inb = 1; next }
             inb { l = $0; sub(/^[ \t]+/, "", l); if (FNR in e) { sub(/;$/, "", l); b = b "\001" l; print n "\t" b; inb = 0; next } b = b "\001" l }' "$1/lex" "$1/print"
    fi
}
