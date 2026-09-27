#!/bin/bash
# v0.7 (Block 6.3.1): OWN-VIEW HARDENING. The reviewer's principle for the slice: TRIGGER on the slow
# reliable view (finalized), VETO on the fast one (confirmed). The detection reads stay on `finalized`,
# now SPELLED OUT; the spare's OWN bank (LOCAL_RPC — the one stream no TIER2/TIER3 intermediary can
# splice) becomes a veto at every take, and watchdog-elapsed gains a rate layer on the spare's own head.
# Drives the REAL shipped code (source-to-MAIN-LOOP seam; the REAL main loop through test_elapsed_provider's
# world() driver, extracted verbatim — never a copy). Cost model: the worst outcome is DOUBLE-SIGN, so
# every ambiguity on the spare fails toward NOT taking.
#   (0) D0.2 N-is-all — the TAKE-path census, by structure: every set-identity token in the shipped set is
#       pinned by file, function and kind, the take functions' arguments are the STAKED key's literal and
#       every other one the UNSTAKED key's; each take runs _fresh_proof_recheck, then _own_view_veto, BEFORE
#       its DRY_RUN branch; the veto is called nowhere else; (0a-ctl) the panel's evasions E0–E5, red
#   (1) D1 — explicit commitments: (1a) every RPC curl body in both daemons is a literal the census PARSES
#       (jq), and every getVoteAccounts/getSlot request names params[0].commitment; (1b) the site table
#       (function, method, commitment) is pinned — the detection reads say finalized; (1c) control: a body
#       stripped of its commitment → (1a) red; (1c-T5) the panel's evasions C0–C4, red; (1d) ZERO
#       behavior change (D0.1: agave's default IS finalized): every detection read of both daemons under a
#       commitment-aware stub decides identically on the shipped tree and on the D1-reverted tree, and a
#       confirmed-mutant control decides differently (the stub can tell); (1e) the same on the REAL loop
#   (2) D2 — own-bank "holder voting" restarts the countdown: the D0 race (red on the 6.3 build: taken
#       t113→t125 un-armed, minted/taken t159→t171 armed) holds now; no take for a full TAKEOVER_DELAY
#       (no mint for a full floor) after the last own-bank voting cycle; the reset at EVERY episode-close
#       site (N-is-all census by structure — every write of an episode variable — with the panel's evasions
#       X0–X2, + behavior); the FLICKERING own bank's availability cost, measured under
#       both presets, with the starvation page
#   (3) D3 — the ONE bounded local veto read: (3a) the predicate table on the REAL _own_view_veto, both
#       daemons; (3b) the twin; (3c) the A8 census by structure — the region's reads, the take segment's
#       permitted statements and its fall-through's network-free closure, the panel's evasions A1–A7 red —
#       and (3c-text) the rule text at every statement of it in every shipped text; (3d) state before alert, throttle,
#       no cooldown; (3e) the controls: veto neutered alone → the D2/D4 worlds TAKE; each guard alone
#       holds its own world; veto + re-check neutered → the all-neutered control takes
#   (4) D4 — the spare's own head: (4b) advancing NOW (red on the 6.3 build: a spare cut off after the
#       episode opened was taken over on the timer path); the exposure below OWN_HEAD_H measured and
#       pinned as the named residual; (4e) [elapsed-rate] (red on the 6.3 build: an own head at 2.0
#       slots/s minted) with the healthy-rate before/after numbers
#   (5) D5 — the holder's latency demote reads its payload FIRST (red on the 6.3 build: reference first)
#   (6) D6 — the cross-node invariant table's spare columns (the holder column: test_d6_holder + docs/SAFETY.md)
#   (7) FIX ROUND 1 (the panel on the 6.3.1 build), each red first on the panel's own worlds: (7a) R1 — an
#       own-bank lastVote ADVANCE inside the episode is holder voting and the veto's agave-current rule (L1),
#       with each layer alone and both neutered, the current rule's slow-cluster cost and a world it alone
#       holds; (7b) R2 — a failed MAX_DELINQUENT_SLOTS reference is not holder-voting evidence (AV-2); (7c)
#       R3 — a baseline at every veto on slow take cycles (AV-3/AV-6: healthy holds, starvation; all R3 layers
#       neutered together → every red back) and (7c-age) the measured baseline ages with the one residual
#       cell; (7d) L4 — the fast path never skips D2's timer; (7e) L3 — Tier-1 is the node's own health verdict
# The A8 rule these cases enforce, as every site states it since 6.3.1: between the fresh re-check's
# return-0 and set-identity — no network, no alerts; one bounded local veto read allowed.
#
# harness: tests/lib/harness.sh — load_seam, harness_clock_shims/harness_silence_sinks, field,
# dump_freshness (the sole reader of the freshness triple), extract_twin, mutate, ok/bad+banners.
# The REAL-loop worlds of (2)–(6) run CONCURRENTLY (one background subshell per world, each with its own
# file clock, temp dir and event log; the seam-cut cache is warmed first) — the results are identical to a
# sequential run; only the wall time differs.

set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Own-view hardening (v0.7 Block 6.3.1)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ov631.XXXXXX")
WORK=$(cd -P -- "$WORK" && pwd -P)   # the provider refuses a token directory that is not its own resolved path (R-SYM)
T0=100000
HEAD0=900000
harness_clock_shims
harness_silence_sinks
_crc_def=$(grep -m1 '^_pairing_crc()' "$STANDBY")
if [[ -z "$_crc_def" ]]; then bad "harness: cannot extract _pairing_crc from the standby daemon"; else eval "$_crc_def"; fi
mk_token() { local p="v0.7|gen=$1|watchdog=$2|relinquish_bound=$3|fence=$4|host=$5"; printf '%s|%s\n' "$p" "$(_pairing_crc "$p")"; }
# the REAL main-loop world driver, extracted VERBATIM from test_elapsed_provider (one driver, not a copy)
_world_def=$(sed -n '/^world() {/,/^}$/p' "$HARNESS_DIR/tests/test_elapsed_provider.sh")
if [[ -z "$_world_def" ]]; then bad "harness: cannot extract world() from test_elapsed_provider.sh"; else eval "$_world_def"; fi
code_of() { sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[[:space:]].*$//' ${1:+"$1"}; }   # comment-stripped (whole-line and trailing ' # ' comments); no file → stdin
fn_body() { awk -v f="$2" '$0 ~ "^"f"\\(\\) *\\{" {p=1} p {print} p && /^\}/ {exit}' "$1"; }

# ── (0) D0.2 — the TAKE-path census (N-is-all) ─────────────────────────────────────────────────────
echo ""; echo "─── (0) D0.2: every set-identity to the STAKED key — the take paths, and the guards on each ───"
SHIPPED="$HARNESS_DIR/install.sh $PRIMARY $STANDBY $HARNESS_DIR/deploy-failover.sh $HARNESS_DIR/deploy-failover-standby.sh $HARNESS_DIR/failover-arm.sh $HARNESS_DIR/systemd/failover-fence.sh $HARNESS_DIR/systemd/failover-fence-page-only.sh"
# 6.3.1 fix round 1 (R6 — the panel's T3: the census keyed on the "$STAKED_KEYPAIR" spelling and skipped log_-prefixed
# lines, so a wrapper function, a keypair variable, "${STAKED_KEYPAIR}", a line continuation or a log_warn …; timeout …
# set-identity line all evaded it). STRUCTURE, not spelling: EVERY 'set-identity' token in the comment-stripped shipped
# set, attributed to its enclosing function (a one-line function ends on its own line) and split into COMMAND tokens
# (outside any quoted string — an invocation word) and TEXT tokens (inside a string: a log line, a hint), pinned as a
# whole — a new token anywhere, in any spelling, is red; then every COMMAND token's argument must be literally
# "$STAKED_KEYPAIR" inside the two take functions and "$UNSTAKED_KEYPAIR" everywhere else. (0a-ctl) runs the panel's
# own evasions E0–E5 through both layers; the dynamic half is test_act_then_alert (15): every staked set-identity in
# that suite's sims follows the veto's read.
setid_scan() {   # $1=file [$2=args] → "<fn>:<commands>/<texts> …" per function holding a set-identity token; args → the bad COMMAND arguments
    code_of "$1" | awk -v mode="${2:-count}" '
        /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $1; sub(/\(\).*/, "", fn); one = ($0 ~ /\}[[:space:]]*$/) }
        { line = $0; tot = gsub(/set-identity/, "&", line)
          if (tot > 0) {
              bare = $0; gsub(/"([^"\\]|\\.)*"/, "", bare); gsub(/\047[^\047]*\047/, "", bare); c = gsub(/set-identity/, "&", bare)
              f = (fn == "" ? "(top)" : fn); cmd[f] += c; txt[f] += tot - c; seen[f] = 1
              if (c > 0) {
                  arg = $0; sub(/.*set-identity[[:space:]]+(--config[[:space:]]+"\$CONFIG_TOML"[[:space:]]+)?/, "", arg); sub(/[[:space:]].*/, "", arg)
                  want = "\"$UNSTAKED_KEYPAIR\""; if (f == "switch_to_staked" || f == "take_staked_identity") want = "\"$STAKED_KEYPAIR\""
                  if (arg != want) badarg = badarg f "(arg " arg ", want " want ") "
              } } }
        /^\}/ || one { fn = "(top)"; one = 0 }
        END { if (mode == "args") printf "%s", badarg; else for (x in seen) printf "%s:%d/%d\n", x, cmd[x], txt[x] }' | { if [[ "${2:-count}" == "args" ]]; then cat; else sort | tr '\n' ' '; fi; }
}
setid_census() { local f s out=""; for f in "$@"; do s=$(setid_scan "$f"); [[ -n "$s" ]] && out="$out$(basename "$f")[$s]"; done; printf '%s' "$out"; }
setid_badargs() { local f out=""; for f in "$@"; do out="$out$(setid_scan "$f" args)"; done; printf '%s' "$out"; }
# ev_mut <src> <anchor (a fixed string, on a code line)> <before|after> <out-file> — a mutant copy with the block on
# stdin inserted at the FIRST non-comment line containing the anchor; rc 1 if the anchor was not found
ev_mut() {
    mkdir -p "$(dirname "$4")"; cat > "$4.ins"
    awk -v a="$2" -v w="$3" -v insf="$4.ins" 'BEGIN { while ((getline l < insf) > 0) blk = blk l "\n" }
        !done && $0 !~ /^[[:space:]]*#/ && index($0, a) { if (w == "before") printf "%s", blk; print; if (w == "after") printf "%s", blk; done = 1; next }
        { print } END { exit(done ? 0 : 1) }' "$1" > "$4"
}
ST_CENSUS="solana-primary-failover.sh[_alpenglow_gate_check:0/2 _selffence_hard_stop:0/3 announce_config_drift:0/1 switch_to_staked:2/3 switch_to_unstaked:2/3 ]solana-standby-failover.sh[_alpenglow_gate_check:0/2 announce_config_drift:0/1 give_back_identity:2/3 take_staked_identity:2/4 ]failover-arm.sh[_retire_legacy_monitors:0/2 ]failover-fence.sh[_admin_remove_all:0/1 _admin_set_identity_unstaked:1/2 _sustained_identity_repoll:0/1 main:0/2 ]"
take_sites=$(setid_census $SHIPPED); arg_bad=$(setid_badargs $SHIPPED)
if [[ "$take_sites" == "$ST_CENSUS" && -z "$arg_bad" ]]; then
    ok "(0a) N-is-all, by structure: EVERY set-identity token in the shipped set is pinned by file, function and kind (command/text) — the only COMMAND tokens are switch_to_staked's two (agave + fdctl — primary) and take_staked_identity's two (standby) to \"\$STAKED_KEYPAIR\", and switch_to_unstaked's, give_back_identity's and the fence's to \"\$UNSTAKED_KEYPAIR\"; nothing in install.sh / the deploy wizards / the arm can set an identity"
else
    bad "(0a) take-path census moved: census=[$take_sites] args:[$arg_bad]"
fi
# (0a-ctl) the panel's evasions (T3), each a new take function with no re-check and no veto, inserted into a copy of
# the standby: E0 plain; E1 a wrapper (_si_wrap "$STAKED_KEYPAIR"); E2 a keypair variable; E3 "${STAKED_KEYPAIR}";
# E4 a line continuation; E5 a log_warn-prefixed line. Each layer ALONE is red on each (the pinned table: a new
# function holds a COMMAND token; the argument rule: the token's argument is not the take functions' literal).
ec_rows=""; ec_ok=1
for e in E0 E1 E2 E3 E4 E5; do
    m="$WORK/t3-$e/solana-standby-failover.sh"
    case $e in
        E0) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_emergency_take0() {
    timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR" 2>&1
}
EOB
        ;;
        E1) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_si_wrap() {
    timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$1" 2>&1
}
_emergency_take1() {
    _si_wrap "$STAKED_KEYPAIR"
}
EOB
        ;;
        E2) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_emergency_take2() {
    local _kp="$STAKED_KEYPAIR"
    timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$_kp" 2>&1
}
EOB
        ;;
        E3) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_emergency_take3() {
    timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "${STAKED_KEYPAIR}" 2>&1
}
EOB
        ;;
        E4) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_emergency_take4() {
    timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity \
        "$STAKED_KEYPAIR" 2>&1
}
EOB
        ;;
        E5) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_emergency_take5() {
    log_warn "emergency take"; timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR" 2>&1
}
EOB
        ;;
    esac
    [[ $? -eq 0 ]] || { ec_ok=0; ec_rows="$ec_rows $e:not-inserted"; continue; }
    set_m=$(printf '%s\n' $SHIPPED | sed "s|^$STANDBY\$|$m|" | tr '\n' ' ')
    lt=green; [[ "$(setid_census $set_m)" != "$ST_CENSUS" ]] && lt=red
    la=green; [[ -n "$(setid_badargs $set_m)" ]] && la=red
    ec_rows="$ec_rows $e:table-$lt/args-$la"
    [[ "$lt" == "red" && "$la" == "red" ]] || ec_ok=0
done
if [[ $ec_ok -eq 1 ]]; then
    ok "(0a-ctl) the panel's T3 evasions, each inserted into a copy of the standby as a new take function without the re-check or the veto — every one is RED on BOTH layers alone:$ec_rows (the 6.3.1 census before fix round 1: E0 red, E1–E5 green)"
else
    bad "(0a-ctl) an evasion is green on a layer:$ec_rows"
fi
g_ok=1; g_rows=""
for pair in "$PRIMARY:switch_to_staked" "$STANDBY:take_staked_identity"; do
    f="${pair%%:*}"; fn="${pair##*:}"
    body=$(fn_body "$f" "$fn")
    rl=$(printf '%s\n' "$body" | grep -n '^[[:space:]]*_fresh_proof_recheck || return 1' | head -1 | cut -d: -f1)
    vl=$(printf '%s\n' "$body" | grep -n '^[[:space:]]*_own_view_veto || return 1' | head -1 | cut -d: -f1)
    dl=$(printf '%s\n' "$body" | grep -n 'if \[\[ "\$DRY_RUN" == "true" \]\]' | head -1 | cut -d: -f1)
    sl=$(printf '%s\n' "$body" | grep -n 'set-identity' | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1)
    vc=$(code_of "$f" | grep -c '_own_view_veto || return 1')
    if [[ -n "$rl" && -n "$vl" && -n "$dl" && -n "$sl" && $vl -eq $((rl + 1 + $(printf '%s\n' "$body" | sed -n "$((rl+1)),$((vl-1))p" | grep -c '^[[:space:]]*#'))) && $vl -lt $dl && $dl -lt $sl && "$vc" == "1" ]]; then
        g_rows="$g_rows $(basename "$f"):$fn(recheck l$rl → veto l$vl → DRY_RUN l$dl → set-identity l$sl)"
    else
        g_ok=0; bad "(0b) $(basename "$f") $fn: recheck=$rl veto=$vl dry=$dl setid=$sl veto-calls-in-file=$vc"
    fi
done
[[ $g_ok -eq 1 ]] && ok "(0b) on EVERY take path the veto is the statement right after the fresh re-check's return-0 (comments only between) and BEFORE the DRY_RUN branch (DRY_RUN mirrors the live decision), and it is called nowhere else in either daemon:$g_rows"
# the primary's other staked-going call is the pre-warm authorized-voter add (not a set-identity) — named
if code_of "$STANDBY" | grep -q 'authorized-voter add' && ! code_of "$STANDBY" | grep 'authorized-voter add' | grep -q 'set-identity'; then
    ok "(0c) named exclusions: the standby's PREWARM authorized-voter add (off by default, live-test-gated) is not a set-identity and never makes this node vote the staked identity; the fence scripts and the arm only ever move toward UNSTAKED"
else
    bad "(0c) the pre-warm exclusion no longer reads as stated"
fi

# ── (1) D1 — explicit commitments, census-enforced ─────────────────────────────────────────────────
echo ""; echo "─── (1) D1: every getVoteAccounts/getSlot body spells its commitment; the site table; zero behavior change ───"
# net_scan — every NETWORK primitive in a shell text on stdin (comment-stripped by the caller), one TAB-separated
# line each (6.3.1 fix round 1, R6 — the panel's T4/T5: the censuses matched spellings; this reads STRUCTURE):
#   CURL <fn> <url-word|(none)> <n-bodies> <the -d body EXPANDED for jq | !why it is not a literal>
#   NET  <fn> <word>        (wget nc ncat socat telnet ssh scp openssl solana dig nslookup as a command, or /dev/tcp|udp)
# A command word counts only in COMMAND context — unquoted, or inside $( ) / backticks nested anywhere — after a
# boundary (start, blank, ; | & ( ! { } /): 'curl' inside a string ("curl rc=…") is text, 'command curl',
# '$( curl' and '/usr/bin/curl' are invocations. Backslash-continued lines are joined first; a one-line function
# ends on its own line. A double-quoted body is unescaped; a whole-string ${var} becomes "__VAR__", a number-position
# ${var} (after : [ ,) becomes 0; a $( ), a backtick, a bare "$body", @file or two bodies is NOT a literal.
NETSCAN_AWK='
function isb(ch) { return (ch == "" || ch ~ /[ \t;|&(!{}\/]/) }
function argopt(wd,   l) {
    if (wd ~ /^--/) return (wd ~ /^--(max-time|request|header|data|data-raw|data-binary|data-ascii|data-urlencode|json|output|write-out|connect-timeout|user-agent|referer|user|config|upload-file|form|proxy|url|cookie|cookie-jar|range|retry|retry-delay|retry-max-time|resolve|cacert|cert|key)$/)
    if (wd ~ /^-[A-Za-z]+$/) { l = substr(wd, length(wd), 1); return (l ~ /[mXHdowAeuKTFxbcrzE]/) }
    return 0
}
function words(s, p,    n, sp, c, c2, w, inw, top) {
    NW = 0; n = length(s); sp = 0; w = ""; inw = 0
    while (p <= n) {
        c = substr(s, p, 1); c2 = substr(s, p, 2)
        top = (sp > 0) ? st[sp] : "C"
        if (top == "S") { w = w c; if (c == "\047") sp--; p++; continue }
        if (c == "\\") { w = w c2; inw = 1; p += 2; continue }
        if (top == "D") {
            if (c == "\"") { sp--; w = w c; p++; continue }
            if (c2 == "$(") { st[++sp] = "P"; w = w c2; p += 2; continue }
            if (c == "`") { st[++sp] = "B"; w = w c; p++; continue }
            w = w c; p++; continue
        }
        if (top == "B") { w = w c; if (c == "`") sp--; p++; continue }
        if (sp == 0 && (c == " " || c == "\t")) { if (inw) { W[++NW] = w; w = ""; inw = 0 } p++; continue }
        if (sp == 0 && (c == ";" || c == "|" || c == "&" || c == ")" || c == "<" || c == ">")) break
        if (c == "\047") { st[++sp] = "S"; w = w c; inw = 1; p++; continue }
        if (c == "\"") { st[++sp] = "D"; w = w c; inw = 1; p++; continue }
        if (c2 == "$(") { st[++sp] = "P"; w = w c2; inw = 1; p += 2; continue }
        if (c == "`") { st[++sp] = "B"; w = w c; inw = 1; p++; continue }
        if (top == "P" && c == "(") { st[++sp] = "P"; w = w c; p++; continue }
        if (top == "P" && c == ")") { sp--; w = w c; p++; continue }
        w = w c; inw = 1; p++
    }
    if (inw) W[++NW] = w
    return p
}
function expand(b,    inner, out, i, n, c, nm, prev, nxt, nc, j) {
    if (b ~ /^\047[^\047]*\047$/) return substr(b, 2, length(b) - 2)
    if (b !~ /^".*"$/) return "!unquoted-or-mixed body"
    inner = substr(b, 2, length(b) - 2)
    if (index(inner, "$(") || index(inner, "`")) return "!command substitution in the body"
    out = ""; n = length(inner); i = 1
    while (i <= n) {
        c = substr(inner, i, 1)
        if (c == "\\") { out = out substr(inner, i + 1, 1); i += 2; continue }
        if (c == "$") {
            if (substr(inner, i + 1, 1) == "{") { j = index(substr(inner, i), "}"); if (!j) return "!unterminated ${"; nm = substr(inner, i, j); i += j }
            else { nm = "$"; i++; while (i <= n && substr(inner, i, 1) ~ /[A-Za-z0-9_]/) { nm = nm substr(inner, i, 1); i++ } }
            if (nm !~ /^(\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*)$/) return "!parameter expansion " nm
            prev = out; sub(/[ \t]+$/, "", prev); prev = substr(prev, length(prev), 1)
            nxt = substr(inner, i); sub(/^[ \t]+/, "", nxt); nc = substr(nxt, 1, 1)
            if (prev == "\"" && substr(nxt, 1, 2) == "\\\"") out = out "__VAR__"
            else if ((prev == ":" || prev == "[" || prev == ",") && (nc == "," || nc == "]" || nc == "}")) out = out "0"
            else return "!a variable outside a whole JSON value: " nm
            continue
        }
        out = out c; i++
    }
    return out
}
function netword(s, p,    k, w) {
    for (k = 1; k <= NNW; k++) { w = NWD[k]; if (substr(s, p, length(w)) == w && substr(s, p + length(w), 1) ~ /[ \t]/) return w }
    return ""
}
BEGIN { NNW = split("wget nc ncat socat telnet ssh scp openssl solana dig nslookup", NWD, " ") }
{ if (cont != "") { $0 = cont $0; cont = "" } }
/\\$/ { cont = substr($0, 1, length($0) - 1) " "; next }
/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $1; sub(/\(\).*/, "", fn); one = ($0 ~ /\}[[:space:]]*$/) }
{
    F = (fn == "" ? "(top)" : fn)
    if ($0 ~ /\/dev\/(tcp|udp)\//) printf "NET\t%s\t/dev/tcp|udp\n", F
    s = $0; n = length(s); sp = 0; p = 1
    while (p <= n) {
        c = substr(s, p, 1); c2 = substr(s, p, 2); top = (sp > 0) ? st0[sp] : "C"
        if (top == "S") { if (c == "\047") sp--; p++; continue }
        if (c == "\\") { p += 2; continue }
        if (top == "D") { if (c == "\"") sp--; else if (c2 == "$(") { st0[++sp] = "P"; p++ } else if (c == "`") st0[++sp] = "B"; p++; continue }
        if (top == "B" && c == "`") { sp--; p++; continue }
        if (c == "\047") { st0[++sp] = "S"; p++; continue }
        if (c == "\"") { st0[++sp] = "D"; p++; continue }
        if (c2 == "$(") { st0[++sp] = "P"; p += 2; continue }
        if (c == "`") { st0[++sp] = "B"; p++; continue }
        if (top == "P" && c == ")") { sp--; p++; continue }
        if (isb(substr(s, p - 1, 1))) {
            if (substr(s, p, 4) == "curl" && substr(s, p + 4, 1) ~ /[ \t]/) {
                words(s, p + 4); url = ""; nb = 0; body = ""; k = 1
                while (k <= NW) {
                    wd = W[k]
                    if (wd ~ /^(-d|--data|--data-raw|--data-binary|--data-ascii|--data-urlencode|--json)$/) { nb++; body = W[k + 1]; k += 2; continue }
                    if (wd ~ /^-d./) { nb++; body = substr(wd, 3); k++; continue }
                    if (wd ~ /^--(data|data-raw|data-binary|data-ascii|json)=/) { nb++; body = wd; sub(/^[^=]*=/, "", body); k++; continue }
                    if (wd == "--url") { if (url == "") url = W[k + 1]; k += 2; continue }
                    if (wd ~ /^-/) { k += argopt(wd) ? 2 : 1; continue }
                    if (url == "") url = wd
                    k++
                }
                if (nb == 1) eb = expand(body); else if (nb == 0) eb = "!no body"; else eb = "!" nb " bodies"
                printf "CURL\t%s\t%s\t%d\t%s\n", F, (url == "" ? "(none)" : url), nb, eb
                p += 4; continue
            }
            w = netword(s, p)
            if (w != "") { printf "NET\t%s\t%s\n", F, w; p += length(w); continue }
        }
        p++
    }
}
/^\}/ || one { fn = "(top)"; one = 0 }
'
net_scan() { awk "$NETSCAN_AWK"; }
# the non-RPC endpoints (pages, pings) — every OTHER curl target counts as an RPC and its body must parse
NONRPC_URLS='"$WEBHOOK_URL" "$HEARTBEAT_URL" "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" "http://1.1.1.1" "http://8.8.8.8"'
RPC_JQ='(if type == "array" then . elif type == "object" then [.] else error("not a request") end)
  | if length == 0 then error("empty batch") else . end
  | map(if (.method | type) != "string" or .method == "__VAR__" then error("the method is not a literal") else . end)
  | . as $rs
  | [ $rs[] | select(.method == "getVoteAccounts" or .method == "getSlot")
      | (if (.params | type) == "array" and (.params[0] | type) == "object" then (.params[0].commitment // "NONE") else "NONE" end)
      | if . == "__VAR__" then error("the commitment is not a literal") elif type != "string" then "NONE" else . end ] as $cs
  | (if ($rs | length) > 1 then "batch[" + ([$rs[].method] | join(",")) + "]" else $rs[0].method end) as $label
  | "\($fn) \($label) \(if ($cs | length) == 0 then "-" elif ($cs | unique | length) == 1 then $cs[0] else "MIXED" end)"'
rpc_bodies() {   # $1=file → one line per RPC curl: "<fn> <method|batch[…]> <commitment|NONE|MIXED|->" or "<fn> UNPARSEABLE <url> <why>"
    local fn url nb body out
    code_of "$1" | net_scan | while IFS=$'\t' read -r kind fn url nb body; do
        [[ "$kind" == "CURL" ]] || continue
        case " $NONRPC_URLS " in *" $url "*) continue ;; esac
        if [[ "$body" == '!'* ]]; then printf '%s UNPARSEABLE %s %s\n' "$fn" "$url" "${body#!}"; continue; fi
        out=$(printf '%s' "$body" | jq -r --arg fn "$fn" "$RPC_JQ" 2>/dev/null) || out=""
        if [[ -n "$out" ]]; then printf '%s\n' "$out"; else printf '%s UNPARSEABLE %s %s\n' "$fn" "$url" "not a JSON-RPC request the census can parse"; fi
    done
}
census_bodies() { rpc_bodies "$1" | awk '$2 != "UNPARSEABLE" && $3 != "-"'; }   # the getVoteAccounts/getSlot bodies: "<fn> <method> <commitment>"
# the pinned table (allowlist): a new body, a moved commitment or a missing one is red here — the WHY per
# site lives in docs/SAFETY.md (the input table in 'Shared vantages') and the per-site daemon comments
P_TABLE="tier1_check_delinquency getVoteAccounts finalized
tier1_get_vote_latency getVoteAccounts finalized
tier1_get_vote_latency getSlot finalized
_check_rpc_delinquency getVoteAccounts finalized
verify_latency_tiered getVoteAccounts finalized
verify_latency_tiered getSlot finalized
_check_single_rpc getVoteAccounts finalized
get_staked_liveness_sample getVoteAccounts processed
_own_head_sample getSlot confirmed
_own_view_veto batch[getSlot,getVoteAccounts] confirmed
_g2_snap batch[getSlot,getClusterNodes] confirmed
_elapsed_step getSlot processed
check_self_fence_isolation getSlot confirmed
check_self_fence_isolation getVoteAccounts processed
startup_checks getSlot finalized
startup_checks getSlot finalized
startup_checks getSlot finalized"
S_TABLE="tier1_check_local_health getSlot finalized
local_check_delinquency getSlot finalized
local_check_delinquency getVoteAccounts finalized
_own_head_sample getSlot confirmed
_own_view_veto batch[getSlot,getVoteAccounts] confirmed
tier2_check_delinquency getVoteAccounts finalized
tier2_check_delinquency getSlot finalized
tier2_check_delinquency getVoteAccounts finalized
tier3_confirm_delinquency getVoteAccounts finalized
get_staked_liveness_sample getVoteAccounts processed
_g2_snap batch[getSlot,getClusterNodes] confirmed
_elapsed_step getSlot processed
check_self_fence_isolation getSlot confirmed
check_self_fence_isolation getVoteAccounts processed
startup_checks getSlot finalized
startup_checks getSlot finalized
startup_checks getSlot finalized"
# (1a) BY PARSE, not by spelling (6.3.1 fix round 1, R6 — the panel's T5: the census matched the literal
# "method":"getX" and found a commitment anywhere on the line, so JSON whitespace, a method in a variable, a
# jq-built body and a top-level "commitment" all passed): EVERY curl to an RPC endpoint in both daemons must carry
# ONE -d body that is a literal the census parses with jq, and every getVoteAccounts/getSlot request in it must name
# params[0].commitment (what agave reads — a top-level "commitment" is ignored there, so the default applies)
d1_scan() {   # $1=file → line 1 "rpc=<n> unparseable=<n> gva/slot=<n> without=<n>"; line 2 the offending bodies
    local all unp gv
    all=$(rpc_bodies "$1")
    unp=$(printf '%s\n' "$all" | grep ' UNPARSEABLE ')
    gv=$(printf '%s\n' "$all" | awk '$2 != "UNPARSEABLE" && $3 != "-"')
    printf 'rpc=%s unparseable=%s gva/slot=%s without=%s\n' "$(printf '%s\n' "$all" | grep -c .)" "$(printf '%s\n' "$unp" | grep -c .)" \
        "$(printf '%s\n' "$gv" | grep -c .)" "$(printf '%s\n' "$gv" | grep -cE ' (NONE|MIXED)$')"
    printf '%s\n' "$unp" "$(printf '%s\n' "$gv" | grep -E ' (NONE|MIXED)$')" | grep . | tr '\n' ';'
}
d1_green() { local s; s=$(d1_scan "$1" | head -1); [[ "$s" == *" unparseable=0 "* && "$s" == *" without=0" ]]; }
d1p=$(d1_scan "$PRIMARY"); d1s=$(d1_scan "$STANDBY")
if [[ "$(printf '%s\n' "$d1p" | head -1)" == "rpc=27 unparseable=0 gva/slot=17 without=0" && "$(printf '%s\n' "$d1s" | head -1)" == "rpc=29 unparseable=0 gva/slot=17 without=0" ]]; then
    ok "(1a) BY PARSE — every curl to an RPC endpoint in BOTH daemons carries one literal -d body the census parses with jq (primary 27, standby 29; the pages and pings excluded by name), and every getVoteAccounts/getSlot request in them names params[0].commitment (17 bodies each, zero without one)"
else
    bad "(1a) primary: $d1p :: standby: $d1s"
fi
pc=$(census_bodies "$PRIMARY"); sc=$(census_bodies "$STANDBY")
if [[ "$pc" == "$P_TABLE" && "$sc" == "$S_TABLE" ]]; then
    ok "(1b) the site table is pinned: DETECTION reads — the standby's local_check_delinquency reference + payload and the TIER2/TIER3 confirm payloads (tier2_check_delinquency, tier3_confirm_delinquency), the primary's tier1/latency/recovery reads — say finalized (their effective value before, by D0.1); the samplers and the elapsed head processed, the self-fence confirmed/processed, G2 confirmed — unchanged; the [own-view] reads confirmed (new)"
else
    bad "(1b) the site table moved — primary: $(diff <(printf '%s\n' "$P_TABLE") <(printf '%s\n' "$pc") | grep '^[<>]' | tr '\n' ';') standby: $(diff <(printf '%s\n' "$S_TABLE") <(printf '%s\n' "$sc") | grep '^[<>]' | tr '\n' ';')"
fi
# (1c) control: strip ONE detection body's commitment in a copy → the census goes red
if mutate "$STANDBY" '/^local_check_delinquency() {/,/^}/s/"method":"getVoteAccounts","params":\[{"commitment":"finalized"}\]}/"method":"getVoteAccounts"}/' "$WORK/d1-strip.sh"; then
    n=$(census_bodies "$WORK/d1-strip.sh" | grep -c ' NONE$')
    [[ "$n" == "1" ]] && ok "(1c) CONTROL: one detection body stripped of its commitment in a copy → the census finds exactly that body (NONE) — (1a) is red on it" \
                      || bad "(1c) control: stripped copy shows $n bodies without a commitment (want 1)"
fi
# (1c-T5) the panel's T5 evasions, each in a copy of the standby: C0 a new body without a commitment (the one the
# old census caught); C1 the same with JSON whitespace; C2 the method in a variable; C3 a jq-built body; C4 the
# self-fence getSlot's commitment moved to the TOP level (agave ignores it there — the default applies)
c5_rows=""; c5_ok=1
for c in C0 C1 C2 C3 C4; do
    m="$WORK/t5-$c/solana-standby-failover.sh"
    case $c in
        C0) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read0() {
    curl -s -m 5 "$TIER3_RPC" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null
}
EOB
        ;;
        C1) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read1() {
    curl -s -m 5 "$TIER3_RPC" -X POST -H "Content-Type: application/json" -d '{"jsonrpc": "2.0", "id": 1, "method": "getVoteAccounts"}' 2>/dev/null
}
EOB
        ;;
        C2) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read2() {
    local _m=getSlot
    curl -s -m 5 "$TIER3_RPC" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${_m}\"}" 2>/dev/null
}
EOB
        ;;
        C3) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read3() {
    curl -s -m 5 "$TIER3_RPC" -X POST -H "Content-Type: application/json" -d "$(jq -nc '{jsonrpc:"2.0",id:1,method:"getVoteAccounts"}')" 2>/dev/null
}
EOB
        ;;
        C4) mkdir -p "$(dirname "$m")"; mutate "$STANDBY" '/^check_self_fence_isolation() {/,/^}/s/"method":"getSlot","params":\[{"commitment":"confirmed"}\]}/"method":"getSlot","commitment":"confirmed"}/' "$m" ;;
    esac
    [[ $? -eq 0 ]] || { c5_ok=0; c5_rows="$c5_rows $c:not-applied"; continue; }
    if d1_green "$m"; then c5_ok=0; c5_rows="$c5_rows $c:GREEN"; else c5_rows="$c5_rows $c:red($(d1_scan "$m" | sed -n 2p | sed 's/;$//'))"; fi
done
if [[ $c5_ok -eq 1 ]]; then
    ok "(1c-T5) the panel's T5 evasions, each in a copy of the standby — every one RED:$c5_rows (the 6.3.1 census before fix round 1: C0 red, C1–C4 green)"
else
    bad "(1c-T5) an evasion is green:$c5_rows"
fi

# (1d) ZERO behavior change — the detection reads of both daemons, shipped vs D1-REVERTED (the explicit
# finalized removed from every body: exactly the 6.3 bytes), under a stub that serves each commitment
# its OWN view: default/finalized = F (the holder DELINQUENT, lastVote 1000, head 2000), confirmed = C and
# processed = P (the holder CURRENT). A read whose effective commitment moved would change its decision.
mutate "$STANDBY" 's/,"params":\[{"commitment":"finalized"}\]//g' "$WORK/s-d1rev.sh"
mutate "$PRIMARY" 's/,"params":\[{"commitment":"finalized"}\]//g' "$WORK/p-d1rev.sh"
mutate "$STANDBY" '/^local_check_delinquency() {/,/^}/s/"method":"getVoteAccounts","params":\[{"commitment":"finalized"}\]}/"method":"getVoteAccounts","params":[{"commitment":"confirmed"}]}/' "$WORK/s-conf.sh"
d1_drive() {   # $1=script $2=calls → one line per call: "<call> rc=<rc> out=<stdout> log=<log lines>"
    (
        set +e
        _SIM_NOW=$T0
        load_seam "$1"
        STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; LOCAL_RPC="http://local.mock"; TIER2_RPC="http://t2.mock"; TIER3_RPC="http://t3.mock"
        _watchdog_pet(){ :; }; alert_info(){ :; }; alert_warn(){ :; }; alert(){ :; }
        LOGF=$(mktemp "$WORK/d1log.XXXXXX")   # the calls run inside $(): their log lines come back through a file
        log_info(){ printf '%s;' "$*" >> "$LOGF"; }; log_warn(){ printf 'W:%s;' "$*" >> "$LOGF"; }
        curl(){
            local d="" c=F
            while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; *) shift ;; esac; done
            case "$d" in *'"commitment":"confirmed"'*) c=C ;; *'"commitment":"processed"'*) c=P ;; esac
            case "$d" in
                *getHealth*) printf '{"jsonrpc":"2.0","result":"ok","id":1}' ;;
                *getSlot*) case $c in F) printf '{"jsonrpc":"2.0","result":2000,"id":1}' ;; C) printf '{"jsonrpc":"2.0","result":2030,"id":1}' ;; P) printf '{"jsonrpc":"2.0","result":2040,"id":1}' ;; esac ;;
                *getVoteAccounts*)
                    case $c in
                        F) if [[ "${FVIEW:-list}" == "lat" ]]; then   # the holder CURRENT but 20 behind the finalized head: delinquent only by the MAX_DELINQUENT_SLOTS=15 latency test
                               printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":1999},{"votePubkey":"V1","nodePubkey":"S1","lastVote":1980}],"delinquent":[]},"id":1}'
                           else printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":1999}],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":1000}]},"id":1}'; fi ;;
                        *) printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"OTHER","nodePubkey":"X","lastVote":2029},{"votePubkey":"V1","nodePubkey":"S1","lastVote":2028}],"delinquent":[]},"id":1}' ;;
                    esac ;;
                *) return 7 ;;
            esac
            return 0
        }
        local call out rc
        for call in $2; do
            : > "$LOGF"; MAX_DELINQUENT_SLOTS=0; MAX_VOTE_LATENCY=15; FVIEW=list
            case "$call" in *@15) MAX_DELINQUENT_SLOTS=15; FVIEW=lat ;; esac
            out=$(eval "${call%@*}" 2>/dev/null); rc=$?
            printf '%s rc=%s out=%s log=%s\n' "$call" "$rc" "$out" "$(cat "$LOGF")"
        done
        rm -f "$LOGF"
    )
}
S_CALLS="local_check_delinquency local_check_delinquency@15 tier2_check_delinquency tier2_check_delinquency@15 tier3_confirm_delinquency tier1_check_local_health"
P_CALLS="tier1_check_delinquency tier1_get_vote_latency _check_rpc_delinquency verify_latency_tiered _check_single_rpc"
s_new=$(d1_drive "$STANDBY" "$S_CALLS"); s_rev=$(d1_drive "$WORK/s-d1rev.sh" "$S_CALLS")
p_new=$(d1_drive "$PRIMARY" "$P_CALLS"); p_rev=$(d1_drive "$WORK/p-d1rev.sh" "$P_CALLS")
s_conf=$(d1_drive "$WORK/s-conf.sh" "$S_CALLS")
if [[ -n "$s_new" && "$s_new" == "$s_rev" && -n "$p_new" && "$p_new" == "$p_rev" && $(printf '%s\n' "$s_new" | grep -c 'rc=0') -ge 4 ]]; then
    ok "(1d) ZERO behavior change (D0.1: agave's default commitment IS finalized — solana-commitment-config's #[default] Finalized, rpc.rs bank() unwrap_or_default): the standby's 6 detection drives and the primary's 5 decide byte-identically (rc, output, log) on the shipped tree and on the D1-reverted 6.3 bytes, under a stub that serves finalized, confirmed and processed DIFFERENT views — the stub serves a request WITHOUT a commitment the finalized view, i.e. D0.1 is built into it: this row shows that no detection read moved to another commitment; the neutrality itself rests on the agave source (6.3.1 fix round 1, the panel's CC-9)"
else
    bad "(1d) the D1 revert changed a decision — standby: $(diff <(printf '%s\n' "$s_new") <(printf '%s\n' "$s_rev") | grep '^[<>]' | head -2 | tr '\n' ';') primary: $(diff <(printf '%s\n' "$p_new") <(printf '%s\n' "$p_rev") | grep '^[<>]' | head -2 | tr '\n' ';')"
fi
if [[ -n "$s_conf" && "$s_conf" != "$s_new" && "$(printf '%s\n' "$s_new" | head -1)" == *"rc=0"* && "$(printf '%s\n' "$s_conf" | head -1)" != *"rc=0"* ]]; then
    ok "(1d-ctl) CONTROL: the same drive with ONE detection read moved to confirmed (a what-if mutant) decides DIFFERENTLY (local_check_delinquency: delinquent → not) — the stub can tell the views apart, so (1d)'s equality is not vacuous"
else
    bad "(1d-ctl) the confirmed mutant decided the same — (1d) may be vacuous: $(printf '%s\n' "$s_conf" | head -1)"
fi

# ── (3) D3 — the ONE bounded local veto read: the predicate table on the REAL _own_view_veto ────────
echo ""; echo "─── (3) D3: the veto's predicate table (both daemons), the twin, the A8 census, state/throttle/no-cooldown ───"
# vcase <daemon> — ONE call of the REAL _own_view_veto on the seam. Knobs (env): BATCH = the batch answer
# with @A@/@B@ standing for the ids the veto sent (BATCHRC = curl rc, default 0); RING = the own-head
# samples "pre:post:slot" as OFFSETS from T0 (the main loop's _own_head_sample writes them); OBMAX = the
# own-bank max ("" = none); MDSV = MAX_DELINQUENT_SLOTS; NOW = the veto's instant (offset). Prints
# rc|kind|oba|bl|alerts|curls|pets|order|m|url|body|warn — kind from the log line; oba/bl the state
# after (offsets; bl via dump_freshness, the sole reader of the triple).
vcase() {
    (
        set +e
        _SIM_NOW=$T0
        load_seam "$1"
        STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; LOCAL_RPC="http://local.mock"; ALERT_THROTTLE=600
        EVF=$(mktemp "$WORK/vev.XXXXXX")
        log_warn(){ printf 'WARN %s\n' "$*" >> "$EVF"; }; log_info(){ printf 'INFO %s\n' "$*" >> "$EVF"; }
        alert_warn(){ printf 'ALERT oba=%s bl=%s %s\n' "${_own_bank_active_time:-0}" "$(field "$(dump_freshness)" blind_until)" "$1" >> "$EVF"; }
        _watchdog_pet(){ printf 'PET\n' >> "$EVF"; }
        curl(){
            local d="" m="" u="" a b
            while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; -m) m="$2"; shift 2 ;; http*) u="$1"; shift ;; *) shift ;; esac; done
            printf 'CURL m=%s url=%s body=%s\n' "$m" "$u" "$d" >> "$EVF"
            a=${d#*\"id\":}; a=${a%%,*}; b=${d##*\"id\":}; b=${b%%,*}
            [[ -n "${BATCHRC:-}" && "${BATCHRC:-0}" != "0" ]] && return "$BATCHRC"
            local out="${BATCH//@A@/$a}"; out="${out//@B@/$b}"
            printf '%s' "$out"
            return 0
        }
        local e r=""
        for e in ${RING:-}; do r="${r:+$r }$(( T0 + ${e%%:*} )):$(( T0 + $(printf '%s' "$e" | cut -d: -f2) )):${e##*:}"; done
        _own_head_ring="$r"; _own_bank_max_vote="${OBMAX-5000}"; MAX_DELINQUENT_SLOTS="${MDSV:-0}"
        _SIM_NOW=$(( T0 + ${NOW:-110} ))
        _own_view_veto; local rc=$?
        local kind=pass
        grep -q 'VETO (holder voting)' "$EVF" && kind=voting
        grep -q 'VETO (blind)' "$EVF" && kind=blind
        local oba=${_own_bank_active_time:-0} bl; bl=$(field "$(dump_freshness)" blind_until)
        [[ $oba -gt 0 ]] && oba=$(( oba - T0 )); [[ ${bl:-0} -gt 0 ]] && bl=$(( bl - T0 ))
        printf 'rc=%s|kind=%s|oba=%s|bl=%s|alerts=%s|curls=%s|pets=%s|order=%s|m=%s|url=%s|warn=%s|body=%s\n' "$rc" "$kind" "$oba" "${bl:-0}" \
            "$(grep -c '^ALERT' "$EVF")" "$(grep -c '^CURL' "$EVF")" "$(grep -c '^PET' "$EVF")" \
            "$(grep -oE '^(CURL|PET|WARN|INFO|ALERT)' "$EVF" | tr '\n' ',')" "$(grep -m1 '^CURL' "$EVF" | sed 's/^CURL m=\([^ ]*\).*/\1/')" \
            "$(grep -m1 '^CURL' "$EVF" | sed 's/.* url=\([^ ]*\) .*/\1/')" "$(grep -m1 -E '^(WARN|INFO)' "$EVF" | cut -c1-240)" "$(grep -m1 '^CURL' "$EVF" | sed 's/.* body=//')"
        rm -f "$EVF"
    )
}
SL='{"jsonrpc":"2.0","id":@A@,"result":900225}'
GD='{"jsonrpc":"2.0","id":@B@,"result":{"current":[],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":5000}]}}'
GC='{"jsonrpc":"2.0","id":@B@,"result":{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":900224}],"delinquent":[]}}'
RING1="100:100:900200"
# name | env assignments | expected kind | expected rc — the veto predicate table ([ov-read] [ov-head] [ov-delinq] [ov-max])
VTABLE="pass-healthy|BATCH=[$SL,$GD]|pass|0
pass-members-swapped (matched by id, never by position)|BATCH=[$GD,$SL]|pass|0
read-timeout (curl rc 28 at the 2 s bound)|BATCH=[$SL,$GD] BATCHRC=28|blind|1
read-refused (rc 7)|BATCH=[$SL,$GD] BATCHRC=7|blind|1
empty-body|BATCH=|blind|1
not-an-array|BATCH={\"jsonrpc\":\"2.0\",\"id\":1,\"result\":900225}|blind|1
one-member|BATCH=[$SL]|blind|1
three-members|BATCH=[$SL,$GD,$SL]|blind|1
ids-not-ours (a stale / replayed answer)|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":900225},{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"current\":[],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5000}]}}]|blind|1
slot-id-twice|BATCH=[$SL,$SL]|blind|1
slot-leading-zero|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":\"0900225\"},$GD]|blind|1
slot-2^64-wrap|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":18446744073710451841},$GD]|blind|1
slot-negative|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":-5},$GD]|blind|1
gva-error-member|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"error\":{\"code\":-32000,\"message\":\"x\"}}]|blind|1
gva-result-not-an-object|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":[1,2]}]|blind|1
holder-absent|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[],\"delinquent\":[]}}]|blind|1
holder-twice|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5000}],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5000}]}}]|blind|1
lastvote-null|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":null}]}}]|blind|1
lastvote-string-leading-zero|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":\"05000\"}]}}]|blind|1
holder-NOT-delinquent (current in the confirmed view)|BATCH=[$SL,$GC]|voting|1
stray-nodePubkey-entry (cannot appear under the votePubkey filter; the holder's own account in current still decides — R1)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5000}],\"delinquent\":[{\"votePubkey\":\"V9\",\"nodePubkey\":\"S1\",\"lastVote\":4000}]}}]|voting|1
MDS15-in-current-latency-20 (R1 — the panel's L1: 20 slots behind is agave-current; the latency threshold no longer applies at the veto)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":900205}],\"delinquent\":[]}}] MDSV=15 OBMAX=900205|voting|1
MDS15-in-delinquent (agave's 128-slot rule, whatever MAX_DELINQUENT_SLOTS is)|BATCH=[$SL,$GD] MDSV=15|pass|0
MDS15-current-latency-15 (NOT above the threshold)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":900210}],\"delinquent\":[]}}] MDSV=15 OBMAX=900210|voting|1
MDS-non-canonical → no latency test (fewer delinquent verdicts)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":900205}],\"delinquent\":[]}}] MDSV=abc OBMAX=900205|voting|1
lastVote-above-own-bank-max (it voted since)|BATCH=[$SL,{\"jsonrpc\":\"2.0\",\"id\":@B@,\"result\":{\"current\":[],\"delinquent\":[{\"votePubkey\":\"V1\",\"nodePubkey\":\"S1\",\"lastVote\":5001}]}}]|voting|1
lastVote-equal-own-bank-max|BATCH=[$SL,$GD] OBMAX=5000|pass|0
own-bank-max-unset (no baseline)|BATCH=[$SL,$GD] OBMAX=|blind|1
no-own-head-sample|BATCH=[$SL,$GD] RING=|blind|1
own-head-sample-too-old (17 s > OWN_HEAD_H 16)|BATCH=[$SL,$GD] RING=93:93:900200|blind|1
own-head-sample-exactly-16s|BATCH=[$SL,$GD] RING=94:94:900200|pass|0
own-head-NOT-advanced (= the baseline)|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":900200},$GD]|blind|1
own-head-advanced-by-1|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":900201},$GD]|pass|0
baseline-is-the-OLDEST-in-window (a newer sample does not count)|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":900180},$GD] RING=90:90:900100_95:95:900150_105:105:900220|pass|0
oldest-in-window-not-exceeded|BATCH=[{\"jsonrpc\":\"2.0\",\"id\":@A@,\"result\":900150},$GD] RING=90:90:900100_95:95:900150_105:105:900220|blind|1"
for d in "$PRIMARY" "$STANDBY"; do
    vt_ok=1; vt_n=0; vt_bad=""
    while IFS='|' read -r name envs want wrc; do
        [[ -z "$name" ]] && continue
        vt_n=$((vt_n + 1))
        r=$(
            set -f   # the JSON answers carry [ ] — never glob them
            unset BATCH BATCHRC RING OBMAX MDSV NOW
            RING="$RING1"; OBMAX=5000
            for kv in $envs; do
                k="${kv%%=*}"; v="${kv#*=}"; v="${v//_/ }"
                [[ "$k" == "BATCH" ]] && v="${kv#BATCH=}"
                eval "$k=\"\$v\""
            done
            [[ "$envs" == *"RING="* && -z "$RING" ]] && RING=""
            vcase "$d" | tail -1
        )
        if [[ "$(field "$r" kind)" == "$want" && "$(field "$r" rc)" == "$wrc" ]]; then :; else vt_ok=0; vt_bad="$vt_bad [$name: want $want/$wrc got $(field "$r" kind)/$(field "$r" rc) — $(field "$r" warn)]"; fi
    done <<< "$VTABLE"
    if [[ $vt_ok -eq 1 ]]; then
        ok "(3a) $(basename "$d"): the veto predicate table — $vt_n rows, each on the REAL _own_view_veto: PASS only on a well-formed 2-member batch matched BY ID, a canonical confirmed slot ABOVE the oldest own-head sample within OWN_HEAD_H, the holder listed exactly once and in agave's DELINQUENT list of the confirmed view (the 128-slot rule, whatever MAX_DELINQUENT_SLOTS is — fix round 1, R1: in agave's current list is VOTING, the panel's L1), its lastVote <= the own-bank max; every read failure / shape / id / non-canonical value / missing baseline → BLIND; not delinquent / voted since → VOTING"
    else
        bad "(3a) $(basename "$d") predicate table:$vt_bad"
    fi
done
# (3b) the twin: the [own-view] region is BYTE-IDENTICAL in both daemons
if extract_twin '\[own-view\] the spare' '\[own-view\] end shared block' && [[ "$TWIN_P" == "$TWIN_S" ]]; then
    ok "(3b) [own-view] region BYTE-IDENTICAL in both daemons ($(printf '%s' "$TWIN_P" | wc -c | tr -d ' ') bytes: _own_view_reset, _own_bank_note, _own_head_sample, _own_veto_alert, _own_view_veto, OWN_HEAD_H)"
else
    bad "(3b) [own-view] twin blocks differ (primary=${#TWIN_P}B standby=${#TWIN_S}B)"
fi
# (3c) the A8 census — 6.3.1 fix round 1 (R6 — the panel's T4: the old census stopped at the FIRST set-identity,
# matched '$(curl ' by spelling and excluded 'alert "$reason"' lines by spelling, so 'command curl', /dev/tcp, a
# helper, '$( curl' and an 'alert "$reason" …' page after the veto all passed it). By STRUCTURE now:
# (i) the [own-view] region reads the network in exactly two places — the own-head sample and the veto — each ONE
# curl (net_scan: command context, any spelling) to LOCAL_RPC with -m 2; the veto's is THE one read the rule
# admits: a [getSlot{confirmed}, getVoteAccounts{confirmed, votePubkey}] batch with fresh ids, its spelling pinned;
# its alerts sit only after the clear-path return (the veto path)
VETO_CURL='curl -s -m 2 "$LOCAL_RPC" -X POST -H "Content-Type: application/json" -d "[{\"jsonrpc\":\"2.0\",\"id\":${_ovv_ida},\"method\":\"getSlot\",\"params\":[{\"commitment\":\"confirmed\"}]},{\"jsonrpc\":\"2.0\",\"id\":${_ovv_idb},\"method\":\"getVoteAccounts\",\"params\":[{\"commitment\":\"confirmed\",\"votePubkey\":\"${VOTE_PUBKEY}\"}]}]" 2>/dev/null'
SAMPLE_CURL='curl -s -m 2 "$LOCAL_RPC" -X POST -H "Content-Type: application/json" -d '"'"'{"jsonrpc":"2.0","id":1,"method":"getSlot","params":[{"commitment":"confirmed"}]}'"'"' 2>/dev/null'
a8_ok=1; a8_why=""
for d in "$PRIMARY" "$STANDBY"; do
    reg=$(sed -n '/\[own-view\] the spare/,/\[own-view\] end shared block/p' "$d" | code_of)
    vb=$(fn_body "$d" _own_view_veto | code_of)
    rn=$(printf '%s\n' "$reg" | net_scan)
    [[ "$(printf '%s\n' "$rn" | grep -c '^CURL')" == "2" && "$(printf '%s\n' "$rn" | grep -c '^NET')" == "0" && "$(printf '%s\n' "$rn" | grep '^CURL' | cut -f3 | sort -u)" == '"$LOCAL_RPC"' ]] \
        || { a8_ok=0; a8_why="$a8_why $(basename "$d"): region network [$(printf '%s\n' "$rn" | cut -f1-3 | tr '\n' ';')]"; }
    [[ "$(printf '%s\n' "$vb" | grep -cF "\$($VETO_CURL)")" == "1" && "$(printf '%s\n' "$vb" | net_scan | grep -c .)" == "1" ]] || { a8_ok=0; a8_why="$a8_why $(basename "$d"): the veto's read is not EXACTLY the admitted spelling"; }
    [[ "$(fn_body "$d" _own_head_sample | grep -cF "$SAMPLE_CURL")" == "1" ]] || { a8_ok=0; a8_why="$a8_why $(basename "$d"): the own-head sample's read spelling moved"; }
    rz=$(printf '%s\n' "$vb" | grep -n '^[[:space:]]*return 0$' | head -1 | cut -d: -f1)
    fa=$(printf '%s\n' "$vb" | grep -n '_own_veto_alert ' | head -1 | cut -d: -f1)
    [[ -n "$rz" && -n "$fa" && $fa -gt $rz ]] || { a8_ok=0; a8_why="$a8_why $(basename "$d"): an alert precedes the clear-path return (rz=$rz alert=$fa)"; }
done
if [[ $a8_ok -eq 1 ]]; then
    ok "(3c) the [own-view] region, both daemons: the network is read in exactly TWO places (the own-head sample and the veto), each ONE curl -m 2 to LOCAL_RPC (counted in command context, any spelling; no other network primitive); the veto's read is exactly the admitted [getSlot{confirmed}, getVoteAccounts{confirmed, votePubkey}] batch; its alerts sit only on the veto path (after the clear return)"
else
    bad "(3c) A8 census:$a8_why"
fi
# (3c-seg) the take paths, by structure. The SEGMENT — every statement after the re-check's '|| return 1' through
# the LAST set-identity command (the agave one; the first is frankendancer's) — must be exactly the permitted
# statements below, in order (an allowlist: layer 1). The FALL-THROUGH — the segment minus every RETURN-BRANCH
# (an if…fi without else/elif, or a && { … } block, whose last statement is a return: the DRY_RUN report and the
# keypair-missing page never reach set-identity) — and every daemon function it calls, transitively, hold NO
# network primitive (net_scan) except the notify socket's socat (_sd_notify: the watchdog pet, a local datagram)
# (layer 2); _own_view_veto — the one admitted read — is pinned by (3c). The A8 rule these enforce:
# no network, no alerts; one bounded local veto read allowed.
a8_segment() {   # $1=file $2=take fn → the segment, comment-stripped and trimmed, one statement line each
    fn_body "$1" "$2" | code_of | awk '
        { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "") }
        length($0) == 0 { next }
        !r && /^_fresh_proof_recheck \|\| return 1$/ { r = 1; next }
        r { L[++n] = $0; bare = $0; gsub(/"([^"\\]|\\.)*"/, "", bare); gsub(/\047[^\047]*\047/, "", bare); if (bare ~ /set-identity/) last = n }
        END { for (i = 1; i <= last; i++) print L[i] }'
}
a8_fallthrough() {   # stdin: a segment → the segment minus every return-branch (by structure)
    awk '
        function flush_to(d,   i) { for (i = 1; i <= NB[d]; i++) { if (d > 1) { NB[d-1]++; B[d-1, NB[d-1]] = B[d, i] } else print B[d, i] } NB[d] = 0 }
        BEGIN { d = 1; NB[1] = 0 }
        /^if .*; then$/ || /(&&|\|\|) \{$/ { d++; NB[d] = 0; K[d] = ($0 ~ /^if /) ? "if" : "br"; E[d] = 0; B[d, ++NB[d]] = $0; next }
        (/^else$/ || /^elif /) && d > 1 && K[d] == "if" { E[d] = 1; B[d, ++NB[d]] = $0; next }
        (/^fi$/ && d > 1 && K[d] == "if") || (/^\}$/ && d > 1 && K[d] == "br") {
            last = B[d, NB[d]]; B[d, ++NB[d]] = $0
            if (!E[d] && last ~ /(^|; *)return( [0-9]+)?$/) { NB[d] = 0; d--; next }
            flush_to(d); d--; next }
        { B[d, ++NB[d]] = $0 }
        END { while (d > 1) { flush_to(d); d-- } flush_to(1) }'
}
a8_closure() {   # $1=file $2=text → the daemon functions the text calls, transitively (one per line; _own_view_veto excluded)
    local f="$1" defs todo seen="" name more
    defs=" $(grep -o '^[A-Za-z_][A-Za-z0-9_]*() *{' "$f" | sed 's/() *{$//' | tr '\n' ' ') "
    todo=$(printf '%s\n' "$2" | tr -c 'A-Za-z0-9_' '\n' | grep -v '^$' | sort -u)
    while [[ -n "$todo" ]]; do
        more=""
        for name in $todo; do
            [[ "$name" == "_own_view_veto" ]] && continue
            case "$defs" in *" $name "*) ;; *) continue ;; esac
            case " $seen " in *" $name "*) continue ;; esac
            seen="$seen $name"
            more="$more $(fn_body "$f" "$name" | code_of | sed '1d' | tr -c 'A-Za-z0-9_' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
        done
        todo=$(printf '%s\n' $more | grep -v '^$' | sort -u)
    done
    printf '%s\n' $seen | sort
}
a8_net() {   # $1=file $2=fall-through → "<n> <kind> <fn> <word>" for every network primitive in it and its closure
    local c
    { printf '%s\n' "$2" | net_scan
      for c in $(a8_closure "$1" "$2"); do fn_body "$1" "$c" | code_of | net_scan; done; } | cut -f1-3 | sort | uniq -c | awk '{ $1 = $1; print }' | tr '\n' ';'
}
A8_NET_OK='3 NET _sd_notify socat;'   # the notify socket: 'command -v socat' + the two local datagram sends
SEG_S='
_own_view_veto || return 1
local reason="$1"
if [[ "$DRY_RUN" == "true" ]]; then
log_warn "[DRY RUN] Would TAKE staked — $reason"
alert "$reason" "$STAKED_PUBKEY" "[DRY RUN] WOULD TAKE STAKED"
LAST_TAKEOVER_TIME=$(mono_now); save_state
window_reset
return 0
fi
[[ ! -s "$STAKED_KEYPAIR" ]] && {
log_error "Staked keypair missing/empty"; alert "$reason" "N/A" "TAKEOVER BLOCKED"; return 1
}
log_warn ">>> TAKING STAKED IDENTITY — $reason"
local _rc take_wedged="" add_wedged=""
if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
timeout -k 5 "$SETIDENTITY_TIMEOUT" fdctl set-identity --config "$CONFIG_TOML" "$STAKED_KEYPAIR" --force 2>&1 | while IFS= read -r l; do log_info "fdctl: $l"; done
_rc=${PIPESTATUS[0]}
[[ $_rc -eq 124 || $_rc -eq 137 ]] && { take_wedged=1; log_warn "[take] fdctl set-identity timed out (${SETIDENTITY_TIMEOUT}s) — admin socket wedged; the re-read below decides what applied (fail toward NOT taking)"; }
_watchdog_pet
else
local out
out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR" 2>&1); _rc=$?
'
SEG_P='
_own_view_veto || return 1
[[ ! -s "$STAKED_KEYPAIR" ]] && {
log_error "Staked keypair missing/empty"
alert "$reason" "N/A" "RECOVERY BLOCKED — keypair problem"; return 1
}
if [[ "$DRY_RUN" == "true" ]]; then
log_info "[DRY RUN] Would recover to STAKED — $reason"
alert "$reason" "$STAKED_PUBKEY" "[DRY RUN] WOULD RECOVER TO STAKED"; return 0
fi
log_info ">>> RECOVERING TO STAKED — $reason"
if [[ "$VALIDATOR_TYPE" == "frankendancer" ]]; then
timeout -k 5 "$SETIDENTITY_TIMEOUT" fdctl set-identity --config "$CONFIG_TOML" "$STAKED_KEYPAIR" --force 2>&1 | while IFS= read -r l; do log_info "fdctl: $l"; done
[[ ${PIPESTATUS[0]} -eq 124 || ${PIPESTATUS[0]} -eq 137 ]] && log_warn "[recovery] fdctl set-identity to staked timed out (${SETIDENTITY_TIMEOUT}s) — promotion will read as failed (fail-safe: stays unstaked)"
_watchdog_pet
else
local out
out=$(timeout -k 5 "$SETIDENTITY_TIMEOUT" "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR" 2>&1); local _src=$?
'
a8_layers() {   # $1=file $2=take fn $3=pinned segment → "allow-<green|red>/net-<green|red>" + the evidence
    local seg ft net l1=green l2=green
    seg=$(a8_segment "$1" "$2"); ft=$(printf '%s\n' "$seg" | a8_fallthrough)
    [[ "$seg" == "$(printf '%s\n' "$3" | grep .)" ]] || l1=red
    net=$(a8_net "$1" "$ft"); [[ "$net" == "$A8_NET_OK" ]] || l2=red
    printf 'allow-%s/net-%s [%s]\n' "$l1" "$l2" "$net"
}
sg_p=$(a8_layers "$PRIMARY" switch_to_staked "$SEG_P"); sg_s=$(a8_layers "$STANDBY" take_staked_identity "$SEG_S")
if [[ "$sg_p" == "allow-green/net-green "* && "$sg_s" == "allow-green/net-green "* ]]; then
    ok "(3c-seg) both take paths, from the re-check's return-0 through the LAST set-identity: the statements are exactly the permitted ones in order (primary $(printf '%s\n' "$SEG_P" | grep -c .), standby $(printf '%s\n' "$SEG_S" | grep -c .)); the fall-through (the DRY_RUN report and the keypair page are return-branches, found by structure) and every daemon function it calls, transitively, hold no network primitive but the notify socket's socat — the rule: no network, no alerts; one bounded local veto read allowed"
else
    bad "(3c-seg) primary: $sg_p :: standby: $sg_s"
fi
# (3c-ctl) the panel's T4 evasions, each ONE line right after '_own_view_veto || return 1' in a copy of the standby
# (A2's helper defined above take_staked_identity): A1 'command curl' to TIER3; A2 a helper that curls; A5 a
# /dev/tcp exchange; A6 '$( curl'; A7 an 'alert "$reason" … TAKING STAKED NOW' page. Each layer ALONE is red on each.
# S1 (the structure rule itself): the DRY_RUN branch's 'return 0' deleted — no statement added, yet its page now
# falls through to set-identity, and layer 2 (structure) is red on it (layer 1 too: a permitted statement went missing).
a4_rows=""; a4_ok=1
for a in A1 A2 A5 A6 A7 S1; do
    m="$WORK/t4-$a/solana-standby-failover.sh"; rc=0
    case $a in
        A1) ev_mut "$STANDBY" "_own_view_veto || return 1" after "$m" <<'EOB' || rc=1
    command curl -s -m 1 "$TIER3_RPC" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' >/dev/null 2>&1
EOB
        ;;
        A2) ev_mut "$STANDBY" "take_staked_identity() {" before "$m.0" <<'EOB' || rc=1
_pre_take_ping() {
    curl -s -m 1 "$TIER3_RPC" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' >/dev/null 2>&1
}
EOB
            ev_mut "$m.0" "_own_view_veto || return 1" after "$m" <<'EOB' || rc=1
    _pre_take_ping
EOB
        ;;
        A5) ev_mut "$STANDBY" "_own_view_veto || return 1" after "$m" <<'EOB' || rc=1
    { exec 9<>/dev/tcp/127.0.0.1/8899 && printf "GET /health HTTP/1.0\r\n\r\n" >&9 && exec 9>&-; } 2>/dev/null || true
EOB
        ;;
        A6) ev_mut "$STANDBY" "_own_view_veto || return 1" after "$m" <<'EOB' || rc=1
    _pt_out=$( curl -s -m 1 "$TIER3_RPC" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' 2>/dev/null )
EOB
        ;;
        A7) ev_mut "$STANDBY" "_own_view_veto || return 1" after "$m" <<'EOB' || rc=1
    alert "$reason" "$STAKED_PUBKEY" "TAKING STAKED NOW (pre-take page)"
EOB
        ;;
        S1) mkdir -p "$(dirname "$m")"
            awk '/^take_staked_identity\(\) \{/ {f = 1} f && /WOULD TAKE STAKED/ {w = 1} f && w && !done && /^[[:space:]]*return 0$/ {done = 1; next} {print} END {exit(done ? 0 : 1)}' "$STANDBY" > "$m" || rc=1 ;;
    esac
    [[ $rc -eq 0 ]] || { a4_ok=0; a4_rows="$a4_rows $a:not-applied"; continue; }
    r=$(a8_layers "$m" take_staked_identity "$SEG_S"); r=${r%% *}
    a4_rows="$a4_rows $a:$r"
    case $a in S1) [[ "$r" == *"net-red"* ]] || a4_ok=0 ;; *) [[ "$r" == "allow-red/net-red" ]] || a4_ok=0 ;; esac
done
if [[ $a4_ok -eq 1 ]]; then
    ok "(3c-ctl) the panel's T4 evasions, each one line after the veto in a copy of the standby — RED on BOTH layers alone:$a4_rows (the 6.3.1 census before fix round 1: A1 and A5 green on the static AND the dynamic census, A2/A6/A7 green on the static one); S1 — the DRY_RUN branch's return deleted, nothing added — is red on the structure layer: the branch's page now falls through to set-identity"
else
    bad "(3c-ctl) an evasion is green on a layer:$a4_rows"
fi
# (3c-text) the A8 rule TEXT — 6.3.1 fix round 1 (R6 — the panel's CC-4: the old check read six files for ONE copy
# of the rule and grepped four fixed stale phrasings in three of them). EVERY shipped text — the daemons, the arm,
# the fence scripts, install.sh, the wizards, the env templates, README/CHANGELOG/SECURITY, docs/*.md (the dated
# audit and evidence records under docs/audits and docs/evidence are frozen history, excluded by directory),
# systemd/, the CI workflow, tests/ — is read for STATEMENTS of the window rule: a 3-line window that names the
# window (the fresh re-check or its return … and set-identity) AND makes a no/zero/only/never claim about network,
# reads, I/O, calls or alerts. Each statement must carry the exact rule within ±2 lines — the rule:
# no network, no alerts; one bounded local veto read allowed.
RULE="no network, no alerts; one bounded local veto read allowed"
A8TEXT_AWK='
function norm(s) { gsub(/[#*`>|]/, " ", s); gsub(/[[:space:]]+/, " ", s); return s }
BEGIN { WIN = "(re-?che" "ck|return-0|return 0)"; SI = "set-ide" "ntity"; CLAIM = "(^|[^a-z])(zero|no|never|nothing|only|without)[^a-z][^.;]{0,24}(network|read|i/o|alert|curl|call)" }
{ L[NR] = norm($0) }
END {
    for (i = 1; i <= NR; i++) {
        w = L[i] " " L[i+1] " " L[i+2]; lw = tolower(w)
        if (lw !~ WIN || lw !~ SI || lw !~ CLAIM) continue
        if (i <= last + 2) continue
        last = i; ctx = ""
        for (j = i - 2; j <= i + 4; j++) if (j >= 1 && j <= NR) ctx = ctx " " L[j]
        gsub(/[[:space:]]+/, " ", ctx)
        printf "%s:%d %s\n", FN, i, (index(ctx, RULE) ? "RULE" : "STALE")
    }
}'
a8_text() {   # files… → one line per rule statement: "<file>:<line> RULE|STALE"
    local f
    for f in "$@"; do awk -v RULE="$RULE" -v FN="${f#"$HARNESS_DIR"/}" "$A8TEXT_AWK" "$f"; done
}
A8TEXT_FILES=$(ls "$HARNESS_DIR"/*.md "$HARNESS_DIR"/*.sh "$HARNESS_DIR"/*.env.example "$HARNESS_DIR"/docs/*.md "$HARNESS_DIR"/systemd/* \
    "$HARNESS_DIR"/.github/workflows/*.yml "$HARNESS_DIR"/tests/*.sh "$HARNESS_DIR"/tests/*.md "$HARNESS_DIR"/tests/lib/*.sh 2>/dev/null)
a8t=$(a8_text $A8TEXT_FILES)
nst=$(printf '%s\n' "$a8t" | grep -c ' STALE$'); nru=$(printf '%s\n' "$a8t" | grep -c ' RULE$'); nfi=$(printf '%s\n' "$A8TEXT_FILES" | grep -c .)
# the controls: the panel's three stale restatements, each appended to a copy of its file
# (the mutation word is assembled — SI — so these control lines do not read as statements themselves)
k_rows=""; k_ok=1; SI="set-ide""ntity"
for k in K1 K2 K3; do
    case $k in
        K1) src="$STANDBY"; line="# A8: between the fresh re-check and $SI there is zero network I/O — no read of any kind may run there." ;;
        K2) src="$HARNESS_DIR/docs/SAFETY.md"; line="The act-then-alert rule: **zero network** between the re-check and \`$SI\`." ;;
        K3) src="$HARNESS_DIR/CHANGELOG.md"; line="- A8: ZERO network calls between the re-check and $SI." ;;
    esac
    km="$WORK/cc4-$k/$(basename "$src")"; mkdir -p "$(dirname "$km")"
    { cat "$src"; printf '\n%s\n' "$line"; } > "$km"
    if a8_text "$km" | grep -q ' STALE$'; then k_rows="$k_rows $k:red"; else k_rows="$k_rows $k:GREEN"; k_ok=0; fi
done
if [[ "$nst" == "0" && $nru -ge 10 && $nfi -ge 60 && $k_ok -eq 1 ]]; then
    ok "(3c-text) every statement of the re-check → set-identity window in $nfi shipped texts ($nru of them) carries the exact rule — '$RULE'; no stale restatement anywhere. CONTROLS — the panel's three stale restatements, each appended to a copy of its file (the standby, SAFETY, CHANGELOG):$k_rows (the 6.3.1 census before fix round 1: all three green)"
else
    bad "(3c-text) files=$nfi rule-statements=$nru stale=$nst [$(printf '%s\n' "$a8t" | grep ' STALE$' | tr '\n' ' ')] controls:$k_rows"
fi
# (3d) one request, its bound, its pet, fresh ids; state BEFORE the alert; throttle; no cooldown, no episode drop
vd() {   # a scripted SEQUENCE of veto calls on ONE seam: $1=daemon; VSEQ="<offset>:<pass|voting|blind> …"
    (
        set +e
        _SIM_NOW=$T0
        load_seam "$1"
        STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; LOCAL_RPC="http://local.mock"; ALERT_THROTTLE=600
        EVF=$(mktemp "$WORK/vd.XXXXXX")
        log_warn(){ :; }; log_info(){ :; }
        alert_warn(){ printf 'ALERT t=%s oba=%s bl=%s\n' "$(( _SIM_NOW - T0 ))" "${_own_bank_active_time:-0}" "$(field "$(dump_freshness)" blind_until)" >> "$EVF"; }
        _watchdog_pet(){ printf 'PET\n' >> "$EVF"; }
        _MODE=pass
        curl(){
            local d="" a b
            while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; *) shift ;; esac; done
            a=${d#*\"id\":}; a=${a%%,*}; b=${d##*\"id\":}; b=${b%%,*}
            printf 'CURL ids=%s,%s\n' "$a" "$b" >> "$EVF"
            [[ "$_MODE" == "blind" ]] && return 7
            if [[ "$_MODE" == "voting" ]]; then
                printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]}}]' "$a" "$(( 900300 + _SIM_NOW - T0 ))" "$b" "$(( 900299 + _SIM_NOW - T0 ))"
            else
                printf '[{"jsonrpc":"2.0","id":%s,"result":%s},{"jsonrpc":"2.0","id":%s,"result":{"current":[],"delinquent":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":5000}]}}]' "$a" "$(( 900300 + _SIM_NOW - T0 ))" "$b"
            fi
        }
        FIRST_DELINQUENT_TIME=$(( T0 - 30 )); _delinq_window="1111111111"; LAST_TAKEOVER_TIME=0; _own_bank_max_vote=5000
        local s off rcs=""
        for s in $VSEQ; do
            off="${s%%:*}"; _MODE="${s##*:}"; _SIM_NOW=$(( T0 + off ))
            _own_head_ring="$(( _SIM_NOW - 5 )):$(( _SIM_NOW - 5 )):900000"
            _own_view_veto; rcs="$rcs$?"
        done
        printf 'rcs=%s|alerts=%s|curls=%s|pets=%s|order=%s|ids=%s|fdt=%s|win=%s|ltt=%s|oba=%s\n' "$rcs" "$(grep '^ALERT' "$EVF" | sed 's/^ALERT //' | tr '\n' ';')" \
            "$(grep -c '^CURL' "$EVF")" "$(grep -c '^PET' "$EVF")" "$(grep -oE '^(CURL|PET|ALERT)' "$EVF" | tr '\n' ',')" "$(grep '^CURL' "$EVF" | sed 's/^CURL ids=//' | tr '\n' ';')" \
            "$(( FIRST_DELINQUENT_TIME - T0 ))" "$_delinq_window" "$LAST_TAKEOVER_TIME" "${_own_bank_active_time:-0}"
        rm -f "$EVF"
    )
}
for d in "$PRIMARY" "$STANDBY"; do
    r=$(VSEQ="10:voting 20:voting 30:blind 700:voting 710:pass" vd "$d" | tail -1)
    alerts=$(field "$r" alerts); ids=$(field "$r" ids)
    a1=${ids%%;*}; a1a=${a1%%,*}; a1b=${a1##*,}; rest=${ids#*;}; a2=${rest%%;*}; a2a=${a2%%,*}
    if [[ "$(field "$r" rcs)" == "11110" && "$(field "$r" curls)" == "5" && "$(field "$r" pets)" == "5" && "$(field "$r" order)" == "CURL,PET,ALERT,CURL,PET,CURL,PET,CURL,PET,ALERT,CURL,PET," \
          && "$alerts" == "t=10 oba=$((T0+10)) bl=0;t=700 oba=$((T0+700)) bl=$((T0+30));" && $a1b -eq $((a1a + 1)) && $a2a -eq $((a1a + 2)) \
          && "$(field "$r" fdt)" == "-30" && "$(field "$r" win)" == "1111111111" && "$(field "$r" ltt)" == "0" ]]; then
        ok "(3d) $(basename "$d"): each veto is ONE request then ONE pet (5 vetoes → 5 curls, 5 pets, pet right after each read); fresh ids per read (a, a+1; the next read a+2); the state write precedes the alert (the alert-time snapshot already shows oba / bl); the veto page is THROTTLED — t10 pages, t20 (voting) and t30 (blind) inside ALERT_THROTTLE do not, t700 pages again (the (12) idiom, one storm guard for both kinds); NO cooldown (LAST_TAKEOVER_TIME stays 0) and NO episode state dropped (FIRST_DELINQUENT_TIME, the window) — a withdrawn verdict, not a failed take"
    else
        bad "(3d) $(basename "$d"): $r"
    fi
done
# (3d-sample) _own_head_sample: ONE LOCAL getSlot{confirmed} + its pet; a canonical answer joins the ring
# as pre:post:slot; the ring keeps only samples no older than OWN_HEAD_H at the new sample's post
hs() {
    (
        set +e
        _SIM_NOW=$T0; load_seam "$1"; LOCAL_RPC="http://local.mock"
        EVF=$(mktemp "$WORK/hs.XXXXXX"); _watchdog_pet(){ printf 'PET\n' >> "$EVF"; }
        _ANS=900100
        curl(){ printf 'CURL\n' >> "$EVF"; [[ "$_ANS" == "RC7" ]] && return 7; printf '{"jsonrpc":"2.0","id":1,"result":%s}' "$_ANS"; }
        local s
        for s in $HSEQ; do _SIM_NOW=$(( T0 + ${s%%:*} )); _ANS="${s##*:}"; _own_head_sample; done
        local r="" e
        for e in $_own_head_ring; do r="$r $(( ${e%%:*} - T0 )):${e##*:}"; done
        printf 'ring=%s|curls=%s|pets=%s\n' "${r# }" "$(grep -c '^CURL' "$EVF")" "$(grep -c '^PET' "$EVF")"
        rm -f "$EVF"
    )
}
for d in "$PRIMARY" "$STANDBY"; do
    r=$(HSEQ="0:900100 5:900110 10:0900120 15:RC7 16:900140 20:900150 33:900180" hs "$d" | tail -1)
    if [[ "$(field "$r" ring)" == "20:900150 33:900180" && "$(field "$r" curls)" == "7" && "$(field "$r" pets)" == "7" ]]; then
        ok "(3d-sample) $(basename "$d"): _own_head_sample — one read + one pet per call (7/7), a non-canonical ('0900120') or failed (rc 7) answer is NO sample, and the ring keeps only samples within OWN_HEAD_H=16 s of the newest (at t33: t20, t33 — t0..t16 pruned)"
    else
        bad "(3d-sample) $(basename "$d"): $r"
    fi
done

# ── (2)–(6): the REAL standby main loop (test_elapsed_provider's world(), extracted verbatim above) ───
# The worlds are launched TOGETHER: each is its own subshell with its own file clock, temp dir and event
# log (the seam-cut cache is warmed first, so no two worlds race on it). Every expectation is the MEASURED
# outcome; the 6.3-build number an ok line quotes is the same world run against the 6.3 daemons (the red).
# The mutants (each applies loudly, or the suite is red):
mutate "$STANDBY" 's/^_own_view_veto() {$/_own_view_veto() { return 0/' "$WORK/s-noveto.sh"                       # [own-view] veto neutered
mutate "$STANDBY" 's/^_fresh_proof_recheck() {$/_fresh_proof_recheck() { return 0/' "$WORK/s-norecheck.sh"       # the A8 fresh re-check neutered
mutate "$WORK/s-noveto.sh" 's/^_fresh_proof_recheck() {$/_fresh_proof_recheck() { return 0/' "$WORK/s-noboth.sh"  # both
mutate "$STANDBY" '/^attempt_takeover() {/,/^}/s/if \[\[ \${_own_bank_active_time:-0} -gt \$takeover_anchor \]\]; then/if false; then/' "$WORK/s-nod2.sh"   # D2's anchor input dropped
mutate "$STANDBY" '/^    # \[elapsed-rate\] (6.3.1, D4 e)/,/the verdict-minting site (every layer passed)/{/the verdict-minting site (every layer passed)/!d;}' "$WORK/s-norate.sh"   # [elapsed-rate] deleted
mutate "$WORK/s-norate.sh" 's/_es_own="\${_own_bank_active_time:-0}"$/_es_own=0/' "$WORK/s-nrno-a.sh" \
  && mutate "$WORK/s-nrno-a.sh" 's/if \[\[ \${_own_bank_active_time:-0} -gt \$_elapsed_since \]\]; then/if [[ 1 -eq 2 ]]; then/' "$WORK/s-norate-noown.sh"   # + [elapsed-own] (both halves)
mutate "$STANDBY" '/^take_staked_identity() {/,/^}/s/^    _own_head_sample$/    : pre-take sample removed/' "$WORK/s-nopretake.sh"   # the pre-take own-head sample removed
# fix round 1 (each layer alone, then all layers of a multilayer gate together — the all-neutered control):
M_ADV='s/^    if _canon_uint "\${_own_bank_max_vote:-}" && \[\[ \$1 -gt \$_own_bank_max_vote \]\]; then$/    if false; then/'
M_CUR='s/^        if \[\[ \$_ovv_ic -ge 1 \]\]; then$/        if false; then/'
mutate "$STANDBY" "$M_ADV" "$WORK/s-noadv.sh"                                                        # R1: the own-bank lastVote ADVANCE stamp neutered
mutate "$STANDBY" "$M_CUR" "$WORK/s-nocur.sh"                                                        # R1: [ov-delinq]'s agave-current rule neutered
mutate "$WORK/s-noadv.sh" "$M_CUR" "$WORK/s-noadvcur.sh"                                             # R1: both
mutate "$WORK/s-nod2.sh" "$M_CUR" "$WORK/s-nod2cur.sh"                                               # D2's anchor input + the current rule
mutate "$STANDBY" 's/^        \[\[ \${_own_bank_active_time:-0} -gt 0 \]\] && _fp_d2_left=.*$/        : L4 D2 hold removed/' "$WORK/s-nofpd2.sh"   # L4: the fast path's D2 hold neutered
mutate "$WORK/s-nofpd2.sh" "$M_CUR" "$WORK/s-nofpd2cur.sh"                                           # L4: + the current rule (every layer that stops that take)
mutate "$STANDBY" '/^attempt_takeover() {/,/^}/s/^    _own_head_sample$/    : r3 sample removed/' "$WORK/s-r3a.sh" \
  && mutate "$WORK/s-r3a.sh" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 1, R3).*$/\1: r3 sample removed/' "$WORK/s-r3b.sh" \
  && mutate "$WORK/s-r3b.sh" 's/^    if \[\[ -n "\$TIER2_RPC" && -n "\$TIER3_RPC" && "\$TIER2_RPC" != "\$TIER3_RPC" \]\]; then$/    if false; then/' "$WORK/s-r3c.sh" \
  && mutate "$WORK/s-r3c.sh" 's/^    if \[\[ "[$]{_liveness_first_provider:-}" == "T3" && -n "\$TIER2_RPC" .*; then$/    if false; then/' "$WORK/s-nor3.sh"   # R3: EVERY layer (the take-path samples, the fence's split, the pinned-first re-check) — the all-neutered control
rm -f "$WORK/s-r3a.sh" "$WORK/s-r3b.sh" "$WORK/s-r3c.sh" "$WORK/s-nrno-a.sh"
for _s in "$STANDBY" "$WORK"/s-*.sh; do seam_cut "$_s" >/dev/null; done
wlaunch() {   # wlaunch <name> VAR=val … — one world() in the background (at most OV_PAR at once) → $WORK/wr.<name>
    local n="$1"; shift
    while [[ $(jobs -rp | wc -l) -ge ${OV_PAR:-16} ]]; do command sleep 0.2; done
    ( for kv in "$@"; do export "$kv"; done; world 2>/dev/null | tail -1 > "$WORK/wr.$n" ) &
}
wr() { cat "$WORK/wr.$1" 2>/dev/null; }
wf() { field "$(wr "$1")" "$2"; }
# (2) D2 — the D0 race (holder resumes at t113 / t159; its votes reach the spare's bank, the tiers spliced),
# the intermittent holder (one vote at t40, MAX_DELINQUENT_SLOTS=15), the flickering own bank
wlaunch race      MDS=0 RESUME=113 HORIZON=140
wlaunch racea     ARMED=1 GATE=1 MDS=0 RESUME=159 HORIZON=185
wlaunch racea37   ARMED=1 GATE=1 MDS=0 RESUME=139 HORIZON=185 SLOT_NUM=37 SLOT_DEN=10
wlaunch racea37b  ARMED=1 GATE=1 MDS=0 RESUME=145 HORIZON=185 SLOT_NUM=37 SLOT_DEN=10
wlaunch inter     MDS=15 RESUME=40 STOP=40 HORIZON=130
wlaunch inter_nd2 WSCRIPT="$WORK/s-nod2.sh" MDS=15 RESUME=40 STOP=40 HORIZON=130
wlaunch inter_nv  WSCRIPT="$WORK/s-noveto.sh" MDS=15 RESUME=40 STOP=40 HORIZON=130
wlaunch intera    ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200
wlaunch intera_nr WSCRIPT="$WORK/s-norate.sh" ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200
wlaunch intera_no WSCRIPT="$WORK/s-norate-noown.sh" ARMED=1 GATE=1 MDS=15 RESUME=40 STOP=40 HORIZON=200
wlaunch flk30_0   FLICKER=30 MDS=0 STARVE=300 HORIZON=370
wlaunch flk30_15  FLICKER=30 MDS=15 STARVE=300 HORIZON=330
wlaunch flk61_0   FLICKER=61 MDS=0 STARVE=300 HORIZON=190
wlaunch flk61_15  FLICKER=61 MDS=15 STARVE=300 HORIZON=130
# (3e) the controls: honest tiers 5 s behind, TIER2 answering 3 s late from t120 (the take cycle's reads
# spread in time), the holder resuming INSIDE the take at t128 (after the vote-FROZEN gate's read, before
# the re-check's) or at t130 (after the re-check's view, before the veto's); and the D2/D4 worlds un-vetoed
for _m in ship noveto norecheck noboth; do
    _ws=""; [[ "$_m" != "ship" ]] && _ws="WSCRIPT=$WORK/s-$_m.sh"
    wlaunch "in128_$_m" $_ws TIERMODE=honest TLAG=5 MDS=0 T2LAT=3 LATFROM=120 RESUME=128 HORIZON=140
done
wlaunch in130_ship   TIERMODE=honest TLAG=5 MDS=0 T2LAT=3 LATFROM=120 RESUME=130 HORIZON=140
wlaunch in130_noveto WSCRIPT="$WORK/s-noveto.sh" TIERMODE=honest TLAG=5 MDS=0 T2LAT=3 LATFROM=120 RESUME=130 HORIZON=140
wlaunch race_nv   WSCRIPT="$WORK/s-noveto.sh" MDS=0 RESUME=113 HORIZON=140
wlaunch cut100_nv WSCRIPT="$WORK/s-noveto.sh" CUT=100 CUTMODE=full RESUME=101 MDS=0 HORIZON=140
# (4) D4 — the spare cut off AFTER the episode opened, on the TIMER path (un-armed); the exposure below
# OWN_HEAD_H; the slow-tier take cycles (the pre-take sample); the rate layer at 2.0 / 2.5 / 2.525 / 3.7 slots/s
wlaunch cut80     CUT=80 CUTMODE=full RESUME=90 MDS=0 HORIZON=140
wlaunch cut109    CUT=109 CUTMODE=full RESUME=110 MDS=0 HORIZON=140
wlaunch cut110    CUT=110 CUTMODE=full RESUME=111 MDS=0 HORIZON=140
wlaunch cut15_64  CUT=64 CUTMODE=full RESUME=65 MDS=15 HORIZON=100
wlaunch cut15_65  CUT=65 CUTMODE=full RESUME=66 MDS=15 HORIZON=100
wlaunch t2d       T2DOWN=1 MDS=0 HORIZON=200
wlaunch t2d_np    WSCRIPT="$WORK/s-nopretake.sh" T2DOWN=1 MDS=0 HORIZON=200
wlaunch t2d_l6    T2DOWN=1 T3LAT_ALL=6 MDS=0 HORIZON=260
wlaunch t2d_l7    T2DOWN=1 T3LAT_ALL=7 MDS=0 HORIZON=260
wlaunch ra20      ARMED=1 GATE=1 MDS=0 SLOT_NUM=2 SLOT_DEN=1 HORIZON=260
wlaunch ra25      ARMED=1 GATE=1 MDS=0 SLOT_NUM=5 SLOT_DEN=2 HORIZON=260
wlaunch ra2525    ARMED=1 GATE=1 MDS=0 SLOT_NUM=101 SLOT_DEN=40 HORIZON=260
wlaunch ra37      ARMED=1 GATE=1 MDS=0 SLOT_NUM=37 SLOT_DEN=10 HORIZON=260
wlaunch ru20      MDS=0 SLOT_NUM=2 SLOT_DEN=1 HORIZON=200
wlaunch ru25      MDS=0 SLOT_NUM=5 SLOT_DEN=2 HORIZON=200
wlaunch ru37      MDS=0 SLOT_NUM=37 SLOT_DEN=10 HORIZON=200
# (6) D6 — the spare columns at MAX_DELINQUENT_SLOTS=15 (the MDS=0 ones are ru25/ru37/ra25/ra37 above)
wlaunch u25_15    MDS=15 SLOT_NUM=5 SLOT_DEN=2 HORIZON=150
wlaunch u37_15    MDS=15 SLOT_NUM=37 SLOT_DEN=10 HORIZON=150
wlaunch a25_15    ARMED=1 GATE=1 MDS=15 SLOT_NUM=5 SLOT_DEN=2 HORIZON=260
wlaunch a37_15    ARMED=1 GATE=1 MDS=15 SLOT_NUM=37 SLOT_DEN=10 HORIZON=200
# fix round 1 (R4 — the panel's CC-5/F6): the spare's EARLIEST take / mint is the MINIMUM over the read phase (the
# holder's last vote at t = 0..CI−1 of the spare's grid) and CHECK_INTERVAL 1 / 3 / 5 — not the one phase above
for _mds in 15 0; do for _r in 25 37; do
    case $_r in 25) _sn=5; _sd=2 ;; 37) _sn=37; _sd=10 ;; esac
    for _ci in 1 3 5; do for ((_k = 0; _k < _ci; _k++)); do
        wlaunch "swu_${_mds}_${_r}_${_ci}_$_k" MDS=$_mds SLOT_NUM=$_sn SLOT_DEN=$_sd CI=$_ci VOTES=0:$_k HORIZON=150
        [[ $_r == 37 ]] && wlaunch "swa_${_mds}_${_r}_${_ci}_$_k" ARMED=1 GATE=1 MDS=$_mds SLOT_NUM=$_sn SLOT_DEN=$_sd CI=$_ci VOTES=0:$_k HORIZON=190
    done; done
done; done
for _mds in 15 0; do for _ci in 1 5; do for ((_k = 0; _k < _ci; _k++)); do
    wlaunch "swa_${_mds}_2525_${_ci}_$_k" ARMED=1 GATE=1 MDS=$_mds SLOT_NUM=101 SLOT_DEN=40 CI=$_ci VOTES=0:$_k HORIZON=200
done; done; done
# (7) FIX ROUND 1 — R1 (the panel's L1 worlds, verbatim knobs; the verifier's labels): a holder voting INTO the
# open episode with each vote landing 20 slots behind (delinquent by MAX_DELINQUENT_SLOTS=15's latency test,
# agave-current), on-time votes whose not-delinquent window falls between two reads, armed, and resumes after
# the would-be take; the controls; the slow-cluster cost of the current rule and a world where it alone holds
wlaunch l1a       MDS=15 VOTES=0:0,40:50 HLAGS=20 HORIZON=220
wlaunch l1b25     MDS=15 VOTES=0:0,40:62 HLAGS=20 HORIZON=220
wlaunch l1b37     MDS=15 SLOT_NUM=37 SLOT_DEN=10 VOTES=0:0,40:61 HLAGS=20 HORIZON=220
wlaunch l1c       MDS=15 SLOT_NUM=37 SLOT_DEN=10 LOCLAT=1 VOTES=0:0,80:80 HORIZON=240
wlaunch l1d       ARMED=1 GATE=1 MDS=15 SLOT_NUM=37 SLOT_DEN=10 VOTES=0:0,40:62 HLAGS=20 HORIZON=240
wlaunch l1lag     MDS=15 HLAGS=20 VOTES=0:62 HORIZON=220
wlaunch l1e       MDS=15 HLAGS=20 VOTES=0:0,40:62,80:-1 HORIZON=220
wlaunch l1f       MDS=15 SLOT_NUM=37 SLOT_DEN=10 LOCLAT=1 VOTES=0:0,80:80,112:-1 HORIZON=240
wlaunch l1dres    ARMED=1 GATE=1 MDS=15 SLOT_NUM=37 SLOT_DEN=10 HLAGS=20 VOTES=0:0,40:62,125:-1 HORIZON=240
wlaunch l1d_noadv WSCRIPT="$WORK/s-noadv.sh" ARMED=1 GATE=1 MDS=15 SLOT_NUM=37 SLOT_DEN=10 VOTES=0:0,40:62 HLAGS=20 HORIZON=240
wlaunch l1a_noadv WSCRIPT="$WORK/s-noadv.sh" MDS=15 VOTES=0:0,40:50 HLAGS=20 HORIZON=220
wlaunch l1a_nocur WSCRIPT="$WORK/s-nocur.sh" MDS=15 VOTES=0:0,40:50 HLAGS=20 HORIZON=220
wlaunch l1a_nob   WSCRIPT="$WORK/s-noadvcur.sh" MDS=15 VOTES=0:0,40:50 HLAGS=20 HORIZON=220
wlaunch l1lag_nob WSCRIPT="$WORK/s-noadvcur.sh" MDS=15 HLAGS=20 VOTES=0:62 HORIZON=220
wlaunch l1d_nob   WSCRIPT="$WORK/s-noadvcur.sh" ARMED=1 GATE=1 MDS=15 SLOT_NUM=37 SLOT_DEN=10 VOTES=0:0,40:62 HLAGS=20 HORIZON=240
wlaunch l1e_nob   WSCRIPT="$WORK/s-noadvcur.sh" MDS=15 HLAGS=20 VOTES=0:0,40:62,80:-1 HORIZON=220
wlaunch inter_nd2cur WSCRIPT="$WORK/s-nod2cur.sh" MDS=15 RESUME=40 STOP=40 HORIZON=130
wlaunch sl12      MDS=15 SLOT_NUM=6 SLOT_DEN=5 HORIZON=260
wlaunch sl10      MDS=15 SLOT_NUM=1 SLOT_DEN=1 HORIZON=260
wlaunch sl135     MDS=15 SLOT_NUM=27 SLOT_DEN=20 HORIZON=260
wlaunch sl12r     MDS=15 SLOT_NUM=6 SLOT_DEN=5 VOTES=0:0,101:-1 HORIZON=260
wlaunch sl12r_nocur WSCRIPT="$WORK/s-nocur.sh" MDS=15 SLOT_NUM=6 SLOT_DEN=5 VOTES=0:0,101:-1 HORIZON=260
wlaunch sl12e     MDS=15 SLOT_NUM=6 SLOT_DEN=5 HLAGS=20 VOTES=0:0,40:62,150:-1 HORIZON=260
wlaunch sl12e_nocur WSCRIPT="$WORK/s-nocur.sh" MDS=15 SLOT_NUM=6 SLOT_DEN=5 HLAGS=20 VOTES=0:0,40:62,150:-1 HORIZON=260
# R2 (the panel's AV-2 knob: one failed own-bank MAX_DELINQUENT_SLOTS reference inside the open episode, a dead holder)
wlaunch r2down40  MDS=15 REFMODE=down REFFROM=40 REFTO=41 HORIZON=200
wlaunch r2down55  MDS=15 REFMODE=down REFFROM=55 REFTO=56 HORIZON=200
wlaunch r2tmo40   MDS=15 REFMODE=tmo REFFROM=40 REFTO=41 HORIZON=200
wlaunch r2garb40  MDS=15 REFMODE=garb REFFROM=40 REFTO=41 HORIZON=200
wlaunch r2always  MDS=15 REFMODE=down REFFROM=0 REFTO=9999 HORIZON=200
wlaunch r2wiz60   GV=true CI=3 MDS=15 REFMODE=down REFFROM=60 REFTO=61 HORIZON=200
wlaunch r2r37     SLOT_NUM=37 SLOT_DEN=10 MDS=15 REFMODE=down REFFROM=30 REFTO=31 HORIZON=200
wlaunch r2a37     ARMED=1 GATE=1 SLOT_NUM=37 SLOT_DEN=10 MDS=15 REFMODE=down REFFROM=40 REFTO=41 HORIZON=240
wlaunch r2mds0    MDS=0 REFMODE=down REFFROM=40 REFTO=41 HORIZON=200
# R3 (the panel's AV-3 worlds: the own confirmed head HOLDS, aligned with the veto, on slow take cycles; AV-6's
# starvation worlds; the baseline ages) — shipped, and every R3 layer neutered together
for _m in ship nor3; do
    _ws=""; [[ "$_m" != "ship" ]] && _ws="WSCRIPT=$WORK/s-$_m.sh"
    wlaunch "h5gv_$_m" $_ws GV=true T2LAT=5 HOLDFROM=140 HOLDTO=146 HORIZON=320
    wlaunch "h6_$_m"   $_ws T2LAT=6 HOLDFROM=136 HOLDTO=143 HORIZON=320
    wlaunch "h8_$_m"   $_ws T2LAT=8 HOLDFROM=138 HOLDTO=147 HORIZON=320
    wlaunch "hm15_$_m" $_ws T2LAT=7 MDS=15 HOLDFROM=92 HOLDTO=100 HORIZON=320
    wlaunch "hwiz_$_m" $_ws GV=true CI=3 T2LAT=6 MDS=15 HOLDFROM=98 HOLDTO=105 HORIZON=320
    wlaunch "hd0_$_m"  $_ws T2DOWN=1 T3LAT_ALL=0 HOLDFROM=140 HOLDTO=151 HORIZON=320
    wlaunch "d7_$_m"   $_ws T2DOWN=1 T3LAT_ALL=7 HORIZON=320
    wlaunch "m15d7_$_m" $_ws T2DOWN=1 T3LAT_ALL=7 MDS=15 HORIZON=320
done
wlaunch hd4_8     T2DOWN=1 T3LAT_ALL=4 HOLDFROM=144 HOLDTO=153 HORIZON=320
wlaunch hd4_7     T2DOWN=1 T3LAT_ALL=4 HOLDFROM=145 HOLDTO=153 HORIZON=320
for _x in 1 2 3 4 5 6 7 8 9; do wlaunch "age_t2_$_x" T2LAT=$_x HORIZON=320; done
wlaunch age_t2_5gv GV=true T2LAT=5 HORIZON=320
for _y in 1 2 3 4 5 6 8 9; do wlaunch "age_d_$_y" T2DOWN=1 T3LAT_ALL=$_y HORIZON=320; done
wlaunch x9np      WSCRIPT="$WORK/s-nopretake.sh" T2LAT=9 HORIZON=320
wlaunch d9np      WSCRIPT="$WORK/s-nopretake.sh" T2DOWN=1 T3LAT_ALL=9 HORIZON=320
# L4 (the panel's forged-flip world: WITNESS_FASTPATH with a PRESENTED flip, the intermittent holder) and L3 (a node
# run at --health-check-slot-distance 64, the spare replaying 44 s = 110 slots behind, the holder resuming at t130)
wlaunch fp        FASTPATH=1 MDS=15 VOTES=0:0,40:40 HORIZON=200
wlaunch fp_nod2   WSCRIPT="$WORK/s-nofpd2.sh" FASTPATH=1 MDS=15 VOTES=0:0,40:40 HORIZON=200
wlaunch fp_noall  WSCRIPT="$WORK/s-nofpd2cur.sh" FASTPATH=1 MDS=15 VOTES=0:0,40:40 HORIZON=200
wlaunch dist64    DIST=64 LAG=44 RESUME=130 MDS=0 HORIZON=200
wlaunch dist64r   DIST=64 LAG=44 RESUME=140 MDS=0 HORIZON=200
wait

# ── (2) D2 — own-bank "holder voting" restarts the countdown ────────────────────────────────────────
echo ""; echo "─── (2) D2: the own bank's 'holder voting' re-anchors the countdown and restarts watchdog-elapsed's silence; the resets; the flicker cost ───"
if [[ "$(wf race mutation)" == "none" && "$(wf race ov_veto)" == "125:voting" && "$(wf race ob_first)" == "126" && "$(wf race end)" == "horizon" \
      && "$(wf racea mutation)" == "none" && "$(wf racea emint)" == "none" && "$(wf racea ob_first)" == "172" && "$(wf racea eslow_from)" == "171" \
      && "$(wf racea37 mutation)" == "none" && "$(wf racea37 emint)" == "none" && "$(wf racea37 veto)" == "148" \
      && "$(wf racea37b emint)" == "151" && "$(wf racea37b mutation)" == "none" && "$(wf racea37b ov_veto)" == "151:voting" ]]; then
    ok "(2a) RED FIRST — the D0 race (the tiers spliced, the holder resuming; the 6.3 build took it at t125 after 12 s of renewed voting un-armed, and minted + took at t171 armed): the holder resuming at t113 → the take cycle's veto reads it VOTING at t125 and the own bank shows it current from t126 on, re-anchoring every cycle — no take by t140; armed (t159) → no mint and no take by t185 — at exactly 2.5 slots/s that no-mint is [elapsed-rate]'s abstention (SLOW OWN HEAD from t171; the own bank current from t172), not D2 (fix round 1 relabel, the panel's T9). At a certified 3.7 slots/s (that rate mints at t151): the holder resuming at t139 → the own bank stamps D2 at t148 and nothing mints by t185 (D2 holds on the SHIPPED provider); resuming at t145 → the provider mints at t151 and the edge veto reads the holder VOTING at t151 — no take"
else
    bad "(2a) race=$(wr race) :: armed=$(wr racea) :: armed-3.7-r139=$(wr racea37) :: armed-3.7-r145=$(wr racea37b)"
fi
if [[ "$(wf inter mutation)" == "119" && "$(wf inter ob_last)" == "59" && "$(wf inter ov_veto)" == "none" \
      && "$(wf inter_nv mutation)" == "119" && "$(wf inter_nd2 mutation)" == "93" && "$(wf inter_nd2 ov_veto)" == "80:voting" && "$(wf inter_nd2 ob_last)" == "59" \
      && "$(wf inter_nd2cur mutation)" == "80" && "$(wf inter_nd2cur ov_veto)" == "none" ]]; then
    ok "(2b) RED FIRST — no take for a full TAKEOVER_DELAY after the last own-bank voting cycle: the intermittent holder (one vote at t40, MAX_DELINQUENT_SLOTS=15; the 6.3 build took at t80 on the original anchor, 40 s after it) — the own bank shows it current t53–t59, and the take waits to t119 = t59 + 60; with the veto neutered still t119 (D2 alone holds it — the holder is silent at the take, the veto passes); with D2's anchor input dropped (attempt_takeover's fourth input) the veto's agave-current rule (fix round 1, R1) catches the holder VOTING from t80 (40 s = 100 slots after its vote, < 128) and the take lands at t93 (when it leaves agave's current list); with the anchor input AND the current rule dropped → t80 again: the anchor input is what moves it to t119, attributable apart from LAST_LIVENESS_ACTIVE_TIME"
else
    bad "(2b) inter=$(wr inter) :: veto-neutered=$(wr inter_nv) :: D2-anchor-neutered=$(wr inter_nd2) :: +current-rule-neutered=$(wr inter_nd2cur)"
fi
if [[ "$(wf intera_nr emint)" == "159" && "$(wf intera_nr mutation)" == "159" && "$(wf intera_nr gate)" == "t=159 prov=watchdog-elapsed" \
      && "$(wf intera_no emint)" == "126" && "$(wf intera_no mutation)" == "126" && "$(wf intera emint)" == "none" && "$(wf intera mutation)" == "none" ]]; then
    ok "(2b-armed) RED FIRST — no watchdog-elapsed mint for a full floor after the last own-bank voting cycle (D2 ii): the armed intermittent holder (the 6.3 build minted + took at t126, 86 s after a vote its own bank saw) with [elapsed-rate] neutered (it abstains at exactly 2.5 slots/s — (4e) — and would mask this) → the mint and the gated take at t159 = t59 + the 100 s floor; [elapsed-own] neutered too (both halves) → t126 again; the SHIPPED tree → no mint, no take by t200"
else
    bad "(2b-armed) rate-neutered=$(wr intera_nr) :: +own-neutered=$(wr intera_no) :: shipped=$(wr intera)"
fi
# (2c) the episode-close sites, N-is-all BY STRUCTURE — 6.3.1 fix round 1 (R6 — the panel's T6: the census keyed on
# an indented '_ep_blind_cycles=0', so a new close site without that spelling, or a column-0 one-liner, evaded it).
# Every WRITE of an episode variable (FIRST_DELINQUENT_TIME, _liveness_obs_since, _ep_blind_cycles) — any
# indentation, any spelling the census reads (VAR=…, VAR+=…, unset, (( … )), let / read / printf -v / declare /
# local / export) — is attributed to its function and the whole table is pinned; every ZERO write (0, "0", '0', "",
# '', $((0)), unset) is a CLOSE and must reach an _own_view_reset at its own indentation before its block ends —
# except the column-0 declarations and the blindness re-pin (_note_blind_cycle zeroes only the OBSERVED span; the
# episode goes on). The standby's STAKED-tenure close writes none of them and is named. Then the reset's behavior.
EP_AWK='
function kindof(v,   t) { t = v; sub(/[[:space:];&|)].*$/, "", t); return (t ~ /^(0|"0"|\0470\047|""|\047\047|\$\(\(0\)\))?$/) ? "zero" : "set" }
function emit(v, k) { printf "%s %s %s %d %d\n", (fn == "" ? (ind == 0 ? "(global)" : "(top)") : fn), v, k, NR, ind }
/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $1; sub(/\(\).*/, "", fn); one = ($0 ~ /\}[[:space:]]*$/) }
{
    ind = match($0, /[^[:space:]]/) ? RSTART - 1 : 0
    n = split("FIRST_DELINQUENT_TIME _liveness_obs_since _ep_blind_cycles", V, " ")
    for (i = 1; i <= n; i++) {
        v = V[i]; s = $0
        while (match(s, "(^|[^A-Za-z0-9_$])" v "[+]?=")) {
            rest = substr(s, RSTART + RLENGTH)
            if (substr(rest, 1, 1) != "=") emit(v, (substr(s, RSTART + RLENGTH - 2, 1) == "+") ? "set" : kindof(rest))
            s = rest
        }
        if (match($0, "(^|[;&|{(![:space:]])unset[[:space:]]+([^;&|]*[[:space:]])?" v "([[:space:];]|$)")) emit(v, "unset")
        if (match($0, "[(][(][^)]*" v "[[:space:]]*([-+*/%]?=[^=]|[+][+]|--)") || match($0, "([+][+]|--)" v) || match($0, "(^|[[:space:];&|])(let|read|printf[[:space:]]+-v|declare|local|typeset|export)[[:space:]]+([^;&|]*[[:space:]])?" v "([[:space:];=]|$)")) emit(v, "set")
    }
}
/^\}/ || one { fn = ""; one = 0 }'
ep_writes() { code_of "$1" | awk "$EP_AWK"; }   # "<fn> <var> <zero|set|unset> <line> <indent>"
ep_table() { ep_writes "$1" | awk '{ printf "%s:%s:%s ", $1, $2, $3 }'; }
ep_open_closes() {   # $1=file → the CLOSE writes that do not reach _own_view_reset inside their own block
    local f="$1" fn var kind line ind
    ep_writes "$f" | while read -r fn var kind line ind; do
        [[ "$kind" == "set" || "$fn" == "(global)" || "$fn" == "_note_blind_cycle" ]] && continue
        code_of "$f" | awk -v L="$line" -v I="$ind" '
            NR < L { next }
            NR == L { if ($0 ~ /;[[:space:]]*_own_view_reset([[:space:];}]|$)/) { found = 1; exit } if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{.*\}[[:space:]]*$/) exit; next }
            /^[[:space:]]*$/ { next }
            { ind = match($0, /[^[:space:]]/) ? RSTART - 1 : 0 }
            ind < I || /^\}/ { exit }
            ind == I && /^[[:space:]]*_own_view_reset[[:space:]]*$/ { found = 1; exit }
            END { exit(found ? 0 : 1) }' || printf '%s:%s@%s ' "$fn" "$var" "$line"
    done
}
EP_TABLE_P="(global):_liveness_obs_since:zero (global):_ep_blind_cycles:zero staked_is_actively_voting:_liveness_obs_since:set _note_blind_cycle:_liveness_obs_since:zero _note_blind_cycle:_ep_blind_cycles:set _note_observation:_liveness_obs_since:set _fresh_proof_recheck:_liveness_obs_since:set switch_to_unstaked:_liveness_obs_since:zero switch_to_unstaked:_ep_blind_cycles:zero switch_to_staked:_liveness_obs_since:zero switch_to_staked:_ep_blind_cycles:zero (top):_liveness_obs_since:zero (top):_ep_blind_cycles:zero "
EP_TABLE_S="(global):FIRST_DELINQUENT_TIME:zero (global):_liveness_obs_since:zero (global):_ep_blind_cycles:zero window_reset:FIRST_DELINQUENT_TIME:zero window_reset:_liveness_obs_since:zero window_reset:_ep_blind_cycles:zero _note_blind_cycle:_liveness_obs_since:zero _note_blind_cycle:_ep_blind_cycles:set _note_observation:_liveness_obs_since:set _fresh_proof_recheck:_liveness_obs_since:set staked_is_actively_voting:_liveness_obs_since:set (top):FIRST_DELINQUENT_TIME:set (top):FIRST_DELINQUENT_TIME:zero (top):_liveness_obs_since:zero (top):_ep_blind_cycles:zero "
staked_close() {   # $1=file → 1 if the STAKED-tenure close is followed by _own_view_reset at its indentation (the standby only)
    code_of "$1" | awk '/_elapsed_reset "spare is STAKED/ { i = match($0, /[^[:space:]]/); getline nx; if (nx ~ "^[[:space:]]{" i - 1 "}_own_view_reset[[:space:]]*$") ok = 1 } END { print ok + 0 }'
}
ep_verdict() {   # $1=primary $2=standby → "table-<green|red>/close-<green|red>" + the evidence
    local t=green c=green oc
    [[ "$(ep_table "$1")" == "$EP_TABLE_P" && "$(ep_table "$2")" == "$EP_TABLE_S" ]] || t=red
    oc="$(ep_open_closes "$1")$(ep_open_closes "$2")"
    [[ -z "$oc" && "$(staked_close "$2")" == "1" ]] || c=red
    printf 'table-%s/close-%s [%s]\n' "$t" "$c" "$oc"
}
calls_s=$(code_of "$STANDBY" | grep -cE '^[[:space:]]*_own_view_reset[[:space:]]*$'); calls_p=$(code_of "$PRIMARY" | grep -cE '^[[:space:]]*_own_view_reset[[:space:]]*$')   # call sites (the definition line excluded)
epv=$(ep_verdict "$PRIMARY" "$STANDBY")
nclose_p=$(ep_writes "$PRIMARY" | awk '$3 != "set" && $1 != "(global)" && $1 != "_note_blind_cycle"' | grep -c .); nclose_s=$(ep_writes "$STANDBY" | awk '$3 != "set" && $1 != "(global)" && $1 != "_note_blind_cycle"' | grep -c .)
wrs=$(
    set +e; _SIM_NOW=$T0; load_seam "$STANDBY"
    _own_bank_active_time=$((T0 + 5)); _own_bank_max_vote=900123; _own_head_ring="$T0:$T0:900100"; FIRST_DELINQUENT_TIME=$((T0 - 30))
    window_reset
    printf 'oba=%s|max=%s|ring=%s|fdt=%s' "$_own_bank_active_time" "$_own_bank_max_vote" "$_own_head_ring" "$FIRST_DELINQUENT_TIME"
)
# the controls: X0 the mostly-clear branch's _own_view_reset removed; X1 a new _abort_episode() that zeroes the
# episode without _ep_blind_cycles=0; X2 a column-0 one-liner that even spells _ep_blind_cycles=0 (the panel's own)
x_rows=""; x_ok=1
for x in X0 X1 X2; do
    m="$WORK/t6-$x/solana-standby-failover.sh"; rc=0
    case $x in
        X0) mkdir -p "$(dirname "$m")"; mutate "$STANDBY" 's/^\([[:space:]]*\)_own_view_reset   # v0\.7 (Block 6\.3\.1, D2\/D4): this branch closes the episode.*$/\1: removed/' "$m" || rc=1 ;;
        X1) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB' || rc=1
_abort_episode() {
    FIRST_DELINQUENT_TIME=0; _delinq_window=""; _liveness_first_vote=""; _liveness_obs_since=0
}
EOB
        ;;
        X2) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB' || rc=1
_abort_episode2() { FIRST_DELINQUENT_TIME=0; _delinq_window=""; _liveness_obs_since=0; _ep_blind_cycles=0; _ep_provider_flips=0; }
EOB
        ;;
    esac
    [[ $rc -eq 0 ]] || { x_ok=0; x_rows="$x_rows $x:not-applied"; continue; }
    r=$(ep_verdict "$PRIMARY" "$m"); r=${r%% *}
    x_rows="$x_rows $x:$r"
    case $x in X0) [[ "$r" == *"close-red" ]] || x_ok=0 ;; *) [[ "$r" == "table-red/close-red" ]] || x_ok=0 ;; esac
done
if [[ "$epv" == "table-green/close-green "* && "$calls_s" == "3" && "$calls_p" == "3" && "$wrs" == "oba=0|max=|ring=|fdt=0" && $x_ok -eq 1 ]]; then
    ok "(2c) N-is-all BY STRUCTURE — every write of an episode variable in both daemons is pinned by function and kind, and every CLOSE write (primary $nclose_p, at switch_to_unstaked's and switch_to_staked's successes and the manual identity change; standby $nclose_s, at window_reset and the mostly-clear branch) reaches _own_view_reset inside its own block; the standby's STAKED-tenure close too; _own_view_reset is called nowhere else (3 + 3); behavior: window_reset on the REAL seam clears the own-bank stamp, the own-bank maximum and the own-head ring with the episode. CONTROLS (the panel's T6):$x_rows (the 6.3.1 census before fix round 1: X0 red, X1 and X2 green)"
else
    bad "(2c) $epv calls standby=$calls_s primary=$calls_p window_reset → $wrs controls:$x_rows"
fi
if [[ "$(wf flk30_0 mutation)" == "none" && "$(wf flk30_0 starve)" == "365" && "$(wf flk30_0 E)" == "65" \
      && "$(wf flk30_15 mutation)" == "none" && "$(wf flk30_15 starve)" == "320" && "$(wf flk30_15 E)" == "20" \
      && "$(wf flk61_0 mutation)" == "182" && "$(wf flk61_0 ob_last)" == "122" && "$(wf flk61_15 mutation)" == "121" && "$(wf flk61_15 ob_last)" == "61" ]]; then
    ok "(2d) MEASURED AVAILABILITY COST (both presets) — a DEAD holder behind a FLICKERING own bank (its finalized view shows the holder current once every P s; the 6.3 build took at t125 / t80 whatever P): every not-delinquent answer restarts the countdown, so P = 30 s is NEVER taken — the starvation page fires at the episode's start + 300 s (t365 at MAX_DELINQUENT_SLOTS=0, t320 at 15) and the hold is loud; P = 61 s is taken one TAKEOVER_DELAY after the last flicker inside the episode (t182 = t122 + 60; t121 = t61 + 60). The line is P vs TAKEOVER_DELAY: a bank that flickers at least once per 60 s starves the takeover for as long as it flickers"
else
    bad "(2d) P30/MDS0=$(wr flk30_0) :: P30/MDS15=$(wr flk30_15) :: P61/MDS0=$(wr flk61_0) :: P61/MDS15=$(wr flk61_15)"
fi

# ── (3e) D3 — the controls: the veto bites; each guard alone holds; both neutered take ─────────────────
echo ""; echo "─── (3e) D3 controls: veto neutered alone → the D2/D4 worlds take; the re-check and the veto each alone hold; both neutered → the take ───"
if [[ "$(wf race_nv mutation)" == "125" && "$(wf race_nv hvafter)" == "1" && "$(wf cut100_nv mutation)" == "125" && "$(wf cut100_nv hvafter)" == "1" ]]; then
    ok "(3e-1) the veto neutered ALONE → the D2 world (the D0 race, resumed t113) and the D4 world (the spare cut off at t100) TAKE at t125 with the holder voting — as on the 6.3 build: the veto is what holds them at the take instant (the finalized own bank sees a t113 resumption only from t126)"
else
    bad "(3e-1) race veto-neutered=$(wr race_nv) :: cut veto-neutered=$(wr cut100_nv)"
fi
if [[ "$(wf in128_ship mutation)" == "none" && "$(wf in128_noveto mutation)" == "none" \
      && "$(wf in128_norecheck mutation)" == "none" && "$(wf in128_norecheck ov_veto)" == "131:voting" \
      && "$(wf in128_noboth mutation)" == "131" && "$(wf in128_noboth holder_voting_at_mut)" == "3" ]]; then
    ok "(3e-2) EACH ALONE HOLDS, the ALL-NEUTERED control takes — the holder resuming at t128 inside a take cycle stretched by a slow TIER2 (after the vote-FROZEN gate's read, before the re-check's): shipped → held (the re-check aborts first); the veto neutered → held by the re-check; the re-check neutered → held by the veto (VOTING at t131); BOTH neutered → the take MUTATES at t131 with the holder voting for 3 s"
else
    bad "(3e-2) shipped=$(wr in128_ship) :: noveto=$(wr in128_noveto) :: norecheck=$(wr in128_norecheck) :: noboth=$(wr in128_noboth)"
fi
if [[ "$(wf in130_ship mutation)" == "none" && "$(wf in130_ship ov_veto)" == "134:voting" && "$(wf in130_noveto mutation)" == "134" && "$(wf in130_noveto holder_voting_at_mut)" == "4" ]]; then
    ok "(3e-3) the veto's own window: the holder resuming at t130 — after the re-check's tier view (5 s behind), before the veto's read — is held ONLY by the veto (VOTING at t134); the veto neutered alone → taken at t134 with the holder voting for 4 s"
else
    bad "(3e-3) shipped=$(wr in130_ship) :: noveto=$(wr in130_noveto)"
fi

# ── (4) D4 — the spare's own head ─────────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) D4: (b) the own head advancing NOW at every take; the exposure below OWN_HEAD_H; the pre-take sample; (e) [elapsed-rate] ───"
if [[ "$(wf cut80 mutation)" == "none" && "$(wf cut80 ov_veto)" == "125:blind" && "$(wf cut109 mutation)" == "none" && "$(wf cut109 ov_veto)" == "125:blind" \
      && "$(wf cut15_64 mutation)" == "none" && "$(wf cut15_64 ov_veto)" == "80:blind" ]]; then
    ok "(4b) RED FIRST — the spare cut off AFTER the episode opened, on the TIMER path (the (11e) world: cut at t80 with the holder voting again from t90; the 6.3 build took at t125 — no spare-side gate, getHealth reads its own blockstore): the veto reads this spare's confirmed head NOT advancing past its sample of ≤ OWN_HEAD_H ago → BLIND at t125, no take; the same for a cut as late as t109 (MAX_DELINQUENT_SLOTS=0) and t64 (15)"
else
    bad "(4b) cut80=$(wr cut80) :: cut109=$(wr cut109) :: cut15@64=$(wr cut15_64)"
fi
if [[ "$(wf cut110 mutation)" == "125" && "$(wf cut110 hvafter)" == "1" && "$(wf cut110 ov_veto)" == "none" && "$(wf cut15_65 mutation)" == "80" && "$(wf cut15_65 hvafter)" == "1" ]]; then
    ok "(4b-residual) NAMED RESIDUAL — the exposure below OWN_HEAD_H, measured at its boundary: a cut at t110 (15 s before the t125 veto read; t65 before t80 at MAX_DELINQUENT_SLOTS=15) still passes — the confirmed head advanced from the oldest in-window sample up to the cut — and the take mutates with the holder voting (docs/SAFETY.md, 'The spare's own view'); one second earlier (t109 / t64) is BLIND (above)"
else
    bad "(4b-residual) cut110=$(wr cut110) :: cut15@65=$(wr cut15_65)"
fi
if [[ "$(wf t2d mutation)" == "140" && "$(wf t2d_np mutation)" == "140" && "$(wf t2d_l6 mutation)" == "158" && "$(wf t2d_l7 mutation)" == "161" \
      && "$(wf x9np mutation)" == "none" && "$(wf x9np ov_veto)" == "148:blind" && "$(wf d9np mutation)" == "none" && "$(wf d9np ov_veto)" == "167:blind" \
      && "$(wf age_t2_9 mutation)" == "148" && "$(wf age_t2_9 ov_age)" == "9" && "$(wf age_d_9 mutation)" == "167" && "$(wf age_d_9 ov_age)" == "9" ]]; then
    ok "(4b-pretake) the PRE-TAKE own-head sample (take_staked_identity's head, before the re-check), after fix round 1 (R3): a dead holder behind a dead TIER2 is taken at t140 with or without it (the samples R3 added before each external read of the take cycle hold the baseline; 6.3.1 as first shipped: t150, and never without it); TIER2 down + TIER3 6 s / 7 s late → t158 / t161 (first shipped: t168 / NEVER — every veto blind). It is still load-bearing where ONE read spans the re-check's own window: TIER2 answering in 9 s (the fence's read and the re-check's, each 9 s) → the baseline is this sample (9 s old), taken t148; removed → every veto BLIND, never taken; the same at TIER2 down + TIER3 9 s (t167 / never)"
else
    bad "(4b-pretake) t2down=$(wr t2d) :: no-pretake=$(wr t2d_np) :: t3+6=$(wr t2d_l6) :: t3+7=$(wr t2d_l7) :: t2@9 no-pretake=$(wr x9np) :: t2down+t3@9 no-pretake=$(wr d9np)"
fi
oh_p=$(code_of "$PRIMARY" | grep -c '^OWN_HEAD_H=16 '); oh_s=$(code_of "$STANDBY" | grep -c '^OWN_HEAD_H=16 ')
oh_all=0; for _f in "$PRIMARY" "$STANDBY" "$HARNESS_DIR/install.sh" "$HARNESS_DIR/failover-arm.sh" "$HARNESS_DIR/deploy-failover.sh" "$HARNESS_DIR/deploy-failover-standby.sh"; do
    oh_all=$(( oh_all + $(code_of "$_f" | grep -cE '^[[:space:]]*((local|declare|export|readonly)[[:space:]]+([-][[:alnum:]]+[[:space:]]+)*)?OWN_HEAD_H=') ))   # ASSIGNMENT sites (a message naming OWN_HEAD_H=… is not one)
done
# the derivation, recomputed (x10 fixed point): the longest healthy hold of the confirmed head = 5 fully-skipped
# leader windows x 4 slots + 2 slots of confirmation jitter = 22 slots at the ASSUMED 2.5 slots/s; an age >= A
# puts the snapshots >= A - 2 - 2 - 1 s apart; the minimal A with (A - 5) > the hold, plus 2 s of sample spacing
hold10=$(( (5 * 4 + 2) * 10 * 2 / 5 )); a=0; while [[ $(( (a - 5) * 10 )) -le $hold10 ]]; do a=$((a + 1)); done
if [[ "$oh_p" == "1" && "$oh_s" == "1" && "$oh_all" == "2" && "$hold10" == "88" && $((a + 2)) -eq 16 ]]; then
    ok "(4c) OWN_HEAD_H = 16 s, derived on the page and recomputed here: a healthy confirmed head holds for at most 22 slots = 8.8 s at the assumed 2.5 slots/s; an age A puts the two snapshots at least A − 5 s apart (two 2 s read bounds + 1 s of mono_now truncation), so A = $a is the least with A − 5 > 8.8, + 2 s of sample spacing = 16 — assigned exactly once per daemon, inside [own-view] (the twin), and nowhere else in the shipped set"
else
    bad "(4c) OWN_HEAD_H census primary=$oh_p standby=$oh_s total=$oh_all; hold=$hold10 (x10) A=$a"
fi
if [[ "$(wf ra20 mutation)" == "none" && "$(wf ra20 emint)" == "none" && "$(wf ra25 emint)" == "none" && "$(wf ra25 mutation)" == "none" \
      && "$(wf ra2525 emint)" == "181" && "$(wf ra2525 mutation)" == "181" && "$(wf ra37 emint)" == "151" && "$(wf ra37 mutation)" == "151" \
      && "$(wf ru20 mutation)" == "145" && "$(wf ru25 mutation)" == "125" && "$(wf ru37 mutation)" == "105" ]]; then
    ok "(4e) RED FIRST — [elapsed-rate] (the spare's own confirmed head, ONE head at two TIMES): an own head at 2.0 slots/s MINTED on the 6.3 build (t191, the gated take with it) → no mint, no take by t260; the healthy rates, before → after: 2.5 slots/s t171 → NEVER (a FINDING: the abstaining bound 2·Δslot >= 5·(Δt+1) never certifies a SMOOTH head at exactly the assumed rate; a 10-slot extra confirmation hold around the anchor sample does — docs/SAFETY.md 'Slot time'), 2.525 t171 → t181 (one step later), 3.7 (mainnet, measured) t151 → t151 (unchanged); the un-armed timer path is untouched at every rate (t145 / t125 / t105)"
else
    bad "(4e) 2.0=$(wr ra20) :: 2.5=$(wr ra25) :: 2.525=$(wr ra2525) :: 3.7=$(wr ra37) :: un-armed 2.0/2.5/3.7=$(wf ru20 mutation)/$(wf ru25 mutation)/$(wf ru37 mutation)"
fi

# ── (5) D5 — the holder's latency demote reads its payload FIRST ──────────────────────────────────────
echo ""; echo "─── (5) D5: the holder's opt-in latency demote reads its payload FIRST (an ambiguity fails toward demoting) ───"
lat_drive() {   # $1=daemon → the REAL tier1_get_vote_latency, a holder voting EVERY slot (its lastVote = the finalized
    (           # head the instant the payload is served), every LOCAL read answering STALL s after its request
        set +e
        load_seam "$1"
        LCLK=$(mktemp "$WORK/lclk.XXXXXX"); echo "$T0" > "$LCLK"; LORD=$(mktemp "$WORK/lord.XXXXXX")
        _ln() { local x; read -r x < "$LCLK"; echo "$x"; }
        _la() { local x; read -r x < "$LCLK"; echo $(( x + $1 )) > "$LCLK"; }
        _lsl() { echo $(( HEAD0 + ($(_ln) - T0) * 5 / 2 - 32 )); }   # the finalized head now, at 2.5 slots/s
        STAKED_PUBKEY=S1; VOTE_PUBKEY=V1; LOCAL_RPC="http://local.mock"; _watchdog_pet() { :; }
        curl() {
            local d=""; while [[ $# -gt 0 ]]; do case "$1" in -d) d="$2"; shift 2 ;; *) shift ;; esac; done
            _la "${STALL:-0}"
            case "$d" in
                *getVoteAccounts*) printf 'gva;' >> "$LORD"; printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"V1","nodePubkey":"S1","lastVote":%s}],"delinquent":[]},"id":1}' "$(_lsl)" ;;
                *getSlot*) printf 'slot;' >> "$LORD"; printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$(_lsl)" ;;
                *) return 7 ;;
            esac
        }
        local lat; lat=$(tier1_get_vote_latency)
        echo "order=$(cat "$LORD")|lat=$lat"
    )
}
l0=$(STALL=0 lat_drive "$PRIMARY" | tail -1); l10=$(STALL=10 lat_drive "$PRIMARY" | tail -1)
s8=$(fn_body "$PRIMARY" tier1_get_vote_latency | head -1; n=$(grep -n '^tier1_get_vote_latency() {' "$PRIMARY" | cut -d: -f1); sed -n "$((n - 18)),$((n - 1))p" "$PRIMARY")
if [[ "$(field "$l0" order)" == "gva;slot;" && "$(field "$l0" lat)" == "0" && "$(field "$l10" order)" == "gva;slot;" && "$(field "$l10" lat)" == "25" ]] \
   && [[ "$s8" == *"This path is NOT part of the cross-node invariant"* && "$s8" == *"reads its PAYLOAD (getVoteAccounts) FIRST, then its REFERENCE"* ]]; then
    ok "(5) RED FIRST — the PRIMARY's tier1_get_vote_latency reads the payload (getVoteAccounts) FIRST, then the reference (getSlot): a holder voting every slot reads latency 0 with prompt reads and +25 slots when each read takes 10 s — a stall between the two can only make the holder look LESS current (demote sooner — the holder's side of the cost model); the 6.3 build read the reference first (slot;gva — the same stall read −25: more current, the demote up to a full loop cycle later). The S8 comment says so, and that this path is NOT part of the cross-node invariant (B bounds the self-fence only)"
else
    bad "(5) prompt=$l0 :: stalled=$l10 :: S8 comment present=$([[ "$s8" == *"This path is NOT part of the cross-node invariant"* ]] && echo yes || echo no)"
fi

# ── (6) D6 — the cross-node invariant table's SPARE columns ───────────────────────────────────────────
echo ""; echo "─── (6) D6: the spare's earliest take (un-armed timer) and earliest mint (armed watchdog-elapsed) from the holder's last vote ───"
# t=0 = the holder's last vote; a dead holder; the splicer tiers; both detect presets (MAX_DELINQUENT_SLOTS 0 —
# the daemon/template default — and 15, the wizard's); 2.5 slots/s (the assumed rate) and 3.7 (mainnet,
# measured). The armed column is the provider's earliest MINT (the gate is wired only in 6.4 — the world's
# GATE=1 emulation takes on it). The holder's fence column and the crossings: docs/SAFETY.md, 'The cross-node
# invariant'.
if [[ "$(wf ru25 mutation)" == "125" && "$(wf ru37 mutation)" == "105" && "$(wf u25_15 mutation)" == "80" && "$(wf u37_15 mutation)" == "75" ]] \
   && [[ "$(wf ra25 emint)" == "none" && "$(wf ra37 emint)" == "151" && "$(wf a25_15 emint)" == "none" && "$(wf a37_15 emint)" == "121" ]]; then
    ok "(6) the D6 spare columns at the world's default read phase (the holder's last vote on the spare's 5 s grid): un-armed take t125 / t105 at MAX_DELINQUENT_SLOTS=0 and t80 / t75 at 15 (2.5 / 3.7 slots/s — unchanged from the 6.3 build and by fix round 1); armed watchdog-elapsed MINT never / t151 at 0 and never / t121 at 15 (the 6.3 build: t171 / t151 and t126 / t121 — at exactly the assumed 2.5 slots/s [elapsed-rate] never certifies the worlds' smooth head, (4e)). The EARLIEST is (6-min)"
else
    bad "(6) un-armed 2.5/3.7 @0=$(wf ru25 mutation)/$(wf ru37 mutation) @15=$(wf u25_15 mutation)/$(wf u37_15 mutation) :: armed mint 2.5/3.7 @0=$(wf ra25 emint)/$(wf ra37 emint) @15=$(wf a25_15 emint)/$(wf a37_15 emint)"
fi
# (6-min) the MINIMUM over the read phase and CHECK_INTERVAL: t is counted from the holder's LAST vote (tsil for the
# take; the mint instant minus the last vote for the armed provider)
swmin() {   # swmin <u|a> <mds> <rate> <cis…> → the minimum over every phase of every listed CHECK_INTERVAL ("none" if none)
    local kind="$1" mds="$2" r="$3" ci k v m="" w; shift 3
    for ci in "$@"; do for ((k = 0; k < ci; k++)); do
        w="sw${kind}_${mds}_${r}_${ci}_$k"
        if [[ "$kind" == "u" ]]; then v=$(wf "$w" tsil); else v=$(wf "$w" emint); [[ "$v" =~ ^[0-9]+$ ]] && v=$(( v - k )); fi
        [[ "$v" =~ ^[0-9]+$ ]] || continue
        [[ -z "$m" || $v -lt $m ]] && m=$v
    done; done
    echo "${m:-none}"
}
m_u15_25=$(swmin u 15 25 1 3 5); m_u15_37=$(swmin u 15 37 1 3 5); m_u0_25=$(swmin u 0 25 1 3 5); m_u0_37=$(swmin u 0 37 1 3 5)
m_a15_37=$(swmin a 15 37 1 3 5); m_a0_37=$(swmin a 0 37 1 3 5); m_a15_2525=$(swmin a 15 2525 1 5); m_a0_2525=$(swmin a 0 2525 1 5)
if [[ "$m_u15_25" == "79" && "$m_u15_37" == "73" && "$m_u0_25" == "125" && "$m_u0_37" == "104" && "$m_a15_37" == "119" && "$m_a0_37" == "150" && "$m_a15_2525" == "125" && "$m_a0_2525" == "170" ]]; then
    ok "(6-min) THE SPARE'S EARLIEST, measured as the minimum over the read phase and CHECK_INTERVAL 1 / 3 / 5 (the panel's CC-5/F6 — the default phase above is not the earliest): un-armed take 79 s / 73 s at MAX_DELINQUENT_SLOTS=15 and 125 s / 104 s at 0 (2.5 / 3.7 slots/s); armed watchdog-elapsed MINT 119 s at 15 and 150 s at 0 (3.7), 125 s and 170 s at 2.525 slots/s (CHECK_INTERVAL 1 / 5), never at exactly 2.5 — the numbers docs/SAFETY.md's D6 table holds the holder column (test_d6_holder) against"
else
    bad "(6-min) un-armed 15:2.5/3.7=$m_u15_25/$m_u15_37 0:2.5/3.7=$m_u0_25/$m_u0_37 :: mint 15/0 @3.7=$m_a15_37/$m_a0_37 @2.525=$m_a15_2525/$m_a0_2525"
fi

# ── (7) FIX ROUND 1 (the panel on the 6.3.1 build): R1 L1 / R2 AV-2 / R3 AV-3·AV-6 / L4 / L3 ──────────────
echo ""; echo "─── (7) fix round 1: an own-bank lastVote advance is holder voting (R1); a failed reference is not (R2); a baseline at every veto (R3); the fast path keeps D2 (L4); Tier-1 is the node's own health verdict (L3) ───"
# (7a) R1 — t=0 = the holder's LAST landed vote in each world; the protected window = the last own-bank
# holder-voting observation (ob_vote_last) + TAKEOVER_DELAY (+ the floor, armed). The 6.3.1-build numbers
# quoted are the same worlds on that build (the red): every one taken inside the window.
r1_ok=1; r1_why=""
r1_row() {   # r1_row <world> <want mutation> <want last own-bank advance> [armed]
    local w="$1" m="$2" oa="$3" a="${4:-}"
    [[ "$(wf "$w" mutation)" == "$m" && "$(wf "$w" oa_last)" == "$oa" && "$(wf "$w" hvafter)" == "0" ]] || { r1_ok=0; r1_why="$r1_why [$w: $(wr "$w" | cut -c1-200)]"; return 0; }
    if [[ -n "$a" ]]; then [[ "$(wf "$w" emint)" == "$m" && $m -ge $(( oa + 100 )) ]] || { r1_ok=0; r1_why="$r1_why [$w armed: emint=$(wf "$w" emint)]"; }
    else [[ $m -ge $(( oa + 60 )) ]] || { r1_ok=0; r1_why="$r1_why [$w inside the window: $m < $oa + 60]"; }; fi
}
r1_row l1a 123 63; r1_row l1b25 135 75; r1_row l1b37 130 70; r1_row l1c 154 90; r1_row l1d 171 71 armed; r1_row l1lag 135 75
for w in l1e l1f l1dres; do [[ "$(wf "$w" mutation)" == "none" && "$(wf "$w" emint)" == "none" ]] || { r1_ok=0; r1_why="$r1_why [$w taken: $(wr "$w" | cut -c1-200)]"; }; done
if [[ $r1_ok -eq 1 ]]; then
    ok "(7a) RED FIRST (R1 — the panel's L1, BLOCKER): at MAX_DELINQUENT_SLOTS=15 a holder voting INTO the open episode — each vote 20 slots late ('delinquent' by the latency test, agave-current), or on-time votes whose not-delinquent window falls between two reads — was folded into the own-bank maximum with no D2 stamp; the 6.3.1 build took (a) t75 (25 s after the last vote), (b) t75 / t70 at 2.5 / 3.7 slots/s (13 s / 9 s), (c) t108 (28 s), the lag-62 world t75 (13 s), and armed (d) minted + took t117 (55 s < W+B). Now each own-bank lastVote ADVANCE inside the episode stamps D2 and no take lands inside TAKEOVER_DELAY of the last one (no mint inside the floor, armed): (a) t123 = 63 + 60, (b) t135 / t130, (c) t154, lag-62 t135, (d) mint + take t171 = 71 + 100; the holder silent at every take (hvafter=0). Resuming after the would-be take — (e) 2.5 slots/s, (f) 3.7, (dres) armed: the 6.3.1 build took each (t75 / t108 / t117) with the holder voting at the mutation; now none is taken"
else
    bad "(7a) R1:$r1_why"
fi
if [[ "$(wf l1d_noadv emint)" == "117" && "$(wf l1d_noadv mutation)" == "117" && "$(wf l1a_noadv mutation)" == "135" && "$(wf l1a_noadv ov_veto)" == "75:voting" \
      && "$(wf l1a_nocur mutation)" == "123" && "$(wf l1a_nob mutation)" == "75" && "$(wf l1lag_nob mutation)" == "75" \
      && "$(wf l1d_nob mutation)" == "117" && "$(wf l1e_nob mutation)" == "75" && "$(wf l1e_nob hvafter)" == "1" ]]; then
    ok "(7a-ctl) the two R1 layers, each alone and together (the all-neutered control): the advance stamp neutered → the armed (d) world MINTS + TAKES at t117 again (the stamp is what restarts watchdog-elapsed's silence) while the un-armed (a) world is held by the veto's agave-current rule (VOTING t75, taken t135); the current rule neutered → (a) unchanged at t123 (the stamp holds it); BOTH neutered → every red restored: (a) t75, lag-62 t75, (d) t117, and (e) taken at t75 with the holder voting at the mutation"
else
    bad "(7a-ctl) d-noadv=$(wr l1d_noadv | cut -c1-160) :: a-noadv=$(wf l1a_noadv mutation)/$(wf l1a_noadv ov_veto) :: a-nocur=$(wf l1a_nocur mutation) :: a/lag/d/e-both=$(wf l1a_nob mutation)/$(wf l1lag_nob mutation)/$(wf l1d_nob mutation)/$(wf l1e_nob mutation):$(wf l1e_nob hvafter)"
fi
if [[ "$(wf sl12 mutation)" == "160" && "$(wf sl12 ov_veto)" == "100:voting" && "$(wf sl10 mutation)" == "170" && "$(wf sl10 ov_veto)" == "110:voting" \
      && "$(wf sl135 mutation)" == "100" && "$(wf sl135 ov_veto)" == "none" && "$(wf u25_15 mutation)" == "80" && "$(wf u37_15 mutation)" == "75" \
      && "$(wf sl12r mutation)" == "none" && "$(wf sl12r ov_veto)" == "100:voting" && "$(wf sl12r_nocur mutation)" == "100" && "$(wf sl12r_nocur hvafter)" == "1" \
      && "$(wf sl12e mutation)" == "none" && "$(wf sl12e_nocur mutation)" == "149" && "$(wf sl12e_nocur hvafter)" == "1" ]]; then
    ok "(7a-cost) NAMED COST of the agave-current rule (R1), MEASURED — a DEAD holder at MAX_DELINQUENT_SLOTS=15: unchanged at 2.5 and 3.7 slots/s (t80 / t75, the D6 rows) and at 1.35 slots/s (t100); below ~1.35 slots/s the dead holder is still inside agave's 128 slots at the first take, the veto reads it VOTING once and the take moves by one TAKEOVER_DELAY: 1.2 slots/s t100 → t160, 1.0 slots/s t110 → t170 (the 6.3.1 build: t100 / t110). What it buys there, measured: the same 1.2 slots/s holder RESUMING at t101 — the rule neutered takes at t100 with the holder voting at the mutation, shipped holds; and the (e)-shaped world at 1.2 slots/s (the holder back at t150) — neutered takes at t149 into the resume, shipped holds"
else
    bad "(7a-cost) 1.2=$(wf sl12 mutation)/$(wf sl12 ov_veto) 1.0=$(wf sl10 mutation)/$(wf sl10 ov_veto) 1.35=$(wf sl135 mutation) 2.5/3.7=$(wf u25_15 mutation)/$(wf u37_15 mutation) :: resume101 ship/nocur=$(wf sl12r mutation)/$(wf sl12r_nocur mutation):$(wf sl12r_nocur hvafter) :: e@1.2 ship/nocur=$(wf sl12e mutation)/$(wf sl12e_nocur mutation):$(wf sl12e_nocur hvafter)"
fi
# (7b) R2 — a failed / timed-out / garbage MAX_DELINQUENT_SLOTS reference inside the open episode: the 6.3 build's
# take times, and the log calls it no evidence (ob_noev), never "holder voting" (ob_n = the positive stamps)
r2_ok=1; r2_why=""
for spec in r2down40:80 r2down55:80 r2tmo40:80 r2garb40:80 r2wiz60:81 r2r37:75; do
    w=${spec%%:*}; m=${spec#*:}
    [[ "$(wf "$w" mutation)" == "$m" && "$(wf "$w" ob_n)" == "0" && "$(wf "$w" ob_noev)" == "1" && "$(wf "$w" ref_fails)" == "1" ]] || { r2_ok=0; r2_why="$r2_why [$w: $(wr "$w" | cut -c1-220)]"; }
done
[[ "$(wf r2a37 emint)" == "121" && "$(wf r2a37 mutation)" == "121" && "$(wf r2a37 ob_n)" == "0" ]] || { r2_ok=0; r2_why="$r2_why [r2a37: $(wr r2a37 | cut -c1-200)]"; }
[[ "$(wf r2always mutation)" == "125" && "$(wf r2always ob_n)" == "0" && "$(wf r2mds0 mutation)" == "125" ]] || { r2_ok=0; r2_why="$r2_why [always/mds0: $(wf r2always mutation)/$(wf r2mds0 mutation)]"; }
if [[ $r2_ok -eq 1 ]]; then
    ok "(7b) RED FIRST (R2 — the panel's AV-2, BLOCKER): at MAX_DELINQUENT_SLOTS=15 one failed LOCAL finalized reference (refused / a 10 s timeout / garbage) inside the open episode — the holder not yet listed — was stamped as own-bank 'holder voting' and restarted the countdown: the 6.3.1 build took t100 / t115 / t103 / t100 (a failure at t40 / t55 / t40 / t40), the wizard preset t120 (failure at t60), 3.7 slots/s t90, armed mint + take t140. Now only POSITIVE evidence stamps D2 and each world is back at the 6.3 build's time: t80 / t80 / t80 / t80, wizard t81, 3.7 t75, armed t121; the window still records the answer as not-delinquent (the 6.3 build's R2 rule), the log names it 'NO positive basis … NOT holder-voting evidence' (ob_noev=1, zero D2 stamps); a reference failing forever → t125 (MAX_DELINQUENT_SLOTS=0 timing, as on every tree); MAX_DELINQUENT_SLOTS=0 unaffected (t125)"
else
    bad "(7b) R2:$r2_why"
fi
# (7c) R3 — the veto's baseline on slow take cycles
r3_ok=1; r3_why=""
for spec in h5gv:145:15 h6:142:12 h8:146:16 hm15:99:14 hwiz:104:12 hd0:140:16; do
    w=${spec%%:*}; rest=${spec#*:}; m=${rest%%:*}; age=${rest#*:}
    [[ "$(wf "${w}_ship" mutation)" == "$m" && "$(wf "${w}_ship" ov_veto)" == "none" && "$(wf "${w}_ship" ov_age)" == "$age" ]] || { r3_ok=0; r3_why="$r3_why [${w}: $(wr "${w}_ship" | cut -c1-200)]"; }
    [[ "$(wf "${w}_nor3" ov_veto)" == *":blind" && $(wf "${w}_nor3" mutation) -ge $(( m + 60 )) ]] || { r3_ok=0; r3_why="$r3_why [${w} all-R3-neutered not blind: $(wr "${w}_nor3" | cut -c1-200)]"; }
done
[[ "$(wf d7_ship mutation)" == "161" && "$(wf m15d7_ship mutation)" == "116" && "$(wf d7_nor3 mutation)" == "none" && "$(wf d7_nor3 ov_veto)" == "171:blind" && "$(wf m15d7_nor3 mutation)" == "none" ]] || { r3_ok=0; r3_why="$r3_why [starvation: d7=$(wf d7_ship mutation)/$(wf d7_nor3 mutation) m15d7=$(wf m15d7_ship mutation)/$(wf m15d7_nor3 mutation)]"; }
if [[ $r3_ok -eq 1 ]]; then
    ok "(7c) RED FIRST (R3 — the panel's AV-3, BLOCKER, and AV-6): a HEALTHY confirmed-head hold inside the 22-slot budget, aligned with the veto, on a slow take cycle — the 6.3.1 build's baseline was the pre-take sample alone (as old as the re-check: 5–8 s here) → BLIND and +85..+93 s: GOSSIP_VERIFY on, TIER2 5 s, a 6 s hold t145 → t230; TIER2 6 s, a 7 s hold t142 → t229; TIER2 8 s, a 9 s hold (22 slots, the budget's edge) t146 → t239; MAX_DELINQUENT_SLOTS=15, TIER2 7 s, an 8 s hold t99 → t190; the wizard preset (TIER2 6 s, a 7 s hold) t104 → t195. With TIER2 down its baseline was 10 s (the re-check's TIER2 timeout), so only a hold BEYOND the budget vetoed there (11 s, 27 slots: BLIND at t150, taken t252), and TIER2 down + TIER3 7 s late was never taken (every veto blind; at MAX_DELINQUENT_SLOTS=15 too). Now own-head samples bracket every external read of the take cycle and the re-check asks the pinned vantage first: every world takes on time (t145 / t142 / t146 / t99 / t104 / t140) with baselines 15 / 12 / 16 / 14 / 12 / 16 s, and the starvation is gone (t161; t116 at 15). All R3 layers neutered together → every red back"
else
    bad "(7c) R3:$r3_why"
fi
a_ok=1; a_got=""
for spec in age_t2_1:16 age_t2_2:16 age_t2_3:16 age_t2_4:16 age_t2_5:16 age_t2_5gv:15 age_t2_6:12 age_t2_7:14 age_t2_8:16 age_t2_9:9 age_d_1:13 age_d_2:16 age_d_3:16 age_d_4:8 age_d_5:10 age_d_6:12 d7_ship:14 age_d_8:16 age_d_9:9; do
    w=${spec%%:*}; want=${spec#*:}; got=$(wf "$w" ov_age); a_got="$a_got $w=$got"
    [[ "$got" == "$want" && "$(wf "$w" ov_veto)" == "none" ]] || a_ok=0
done
if [[ $a_ok -eq 1 && "$(wf hd4_8 ov_veto)" == "152:blind" && "$(wf hd4_8 mutation)" == "254" && "$(wf hd4_7 mutation)" == "152" && "$(wf hd4_7 ov_veto)" == "none" ]]; then
    ok "(7c-age) the baseline age at the veto, MEASURED (the docs quote these): TIER2 answering in 1 / 2 / 3 / 4 / 5 s → 16 s (15 at 5 s with GOSSIP_VERIFY on), 6 → 12, 7 → 14, 8 → 16, 9 → 9 s; TIER2 down and TIER3 in 1 → 13, 2 → 16, 3 → 16, 4 → 8, 5 → 10, 6 → 12, 7 → 14, 8 → 16, 9 → 9 s — the oldest sample one-external-read spacing leaves inside OWN_HEAD_H. NAMED RESIDUAL (the one cell worse than the 6.3.1 build, whose re-check made the pre-take sample 14 s old there): TIER2 down + TIER3 4 s gives an 8 s baseline, and a veto-aligned hold of 8 s (20 slots, inside the 22-slot budget) is BLIND (t152 → taken t254; a 7 s hold passes, t152)"
else
    bad "(7c-age)$a_got :: hd4 8s-hold=$(wf hd4_8 mutation)/$(wf hd4_8 ov_veto) 7s-hold=$(wf hd4_7 mutation)/$(wf hd4_7 ov_veto)"
fi
# (7d) L4 — WITNESS_FASTPATH with a PRESENTED flip (forgeable on shared vantages): D2's timer is never skipped
if [[ "$(wf fp mutation)" == "119" && "$(wf fp ob_last)" == "59" && "$(wf fp_nod2 mutation)" == "93" && "$(wf fp_nod2 ov_veto)" == "66:voting" \
      && "$(wf fp_noall mutation)" == "66" && "$(wf fp_noall ov_veto)" == "none" ]]; then
    ok "(7d) RED FIRST (the panel's L4): with WITNESS_FASTPATH on and a corroborated flip PRESENTED once the episode opens (the intermittent holder, MAX_DELINQUENT_SLOTS=15; own bank current t53–t59), the 6.3.1 build took at t66 — the flip skipped the D2 timer, 7 s after the last own-bank voting cycle. Now the flip never skips D2's timer: t119 = t59 + TAKEOVER_DELAY (the D2 guarantee, as without the fast path). The layers: that hold neutered → the veto's agave-current rule (R1) catches it VOTING at t66, taken t93; both neutered → t66 again"
else
    bad "(7d) L4 fp=$(wf fp mutation)/$(wf fp ob_last) :: hold-neutered=$(wf fp_nod2 mutation)/$(wf fp_nod2 ov_veto) :: all-neutered=$(wf fp_noall mutation)"
fi
# (7e) L3 — Tier-1 at a node run with a smaller non-default --health-check-slot-distance
if [[ "$(wf dist64 mutation)" == "none" && "$(wf dist64 t1_behind_from)" == "0" && "$(wf dist64r mutation)" == "none" && "$(wf dist64r t1_behind_from)" == "0" ]]; then
    ok "(7e) RED FIRST (the panel's L3): a node run with --health-check-slot-distance 64, the spare replaying 44 s (110 slots) behind: agave reports it 'behind by 110'; the 6.3.1 build's 128 cap admitted it and took at t170 with the holder voting for 40 s (RESUME t130; 30 s at t140); the 6.3 build (default 100) held. Now every 'behind' report fails Tier-1 (the effective tolerance is min(configured, the node's own distance) — below every report): Tier-1 BEHIND from t0, no take — never looser than the 6.3 build at any distance (test_config_drift (h4)/(h5))"
else
    bad "(7e) L3 dist64=$(wr dist64 | cut -c1-200) :: resume140=$(wf dist64r mutation)"
fi

rm -rf "$WORK"
results_banner
