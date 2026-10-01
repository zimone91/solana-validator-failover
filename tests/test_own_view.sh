#!/bin/bash
# v0.7 (Block 6.3.1): OWN-VIEW HARDENING. The reviewer's principle for the slice: TRIGGER on the slow
# reliable view (finalized), VETO on the fast one (confirmed). The detection reads stay on `finalized`,
# now SPELLED OUT; the spare's OWN bank (LOCAL_RPC — the one stream no TIER2/TIER3 intermediary can
# splice) becomes a veto at every take, and watchdog-elapsed gains a rate layer on the spare's own head.
# Drives the REAL shipped code (source-to-MAIN-LOOP seam; the REAL main loop through test_elapsed_provider's
# world() driver, extracted verbatim — never a copy). Cost model: the worst outcome is DOUBLE-SIGN, so
# every ambiguity on the spare fails toward NOT taking.
#   (0) D0.2 N-is-all — the TAKE-path census, on bash's own parse (tests/lib's bp_parse: `declare -f` of the
#       sourced definitions): every set-identity COMMAND (its quote-removed command word) in the shipped set is
#       pinned by file, function and kind, the take functions' arguments are the STAKED key's literal and every
#       other one the UNSTAKED key's; (0b) each take runs `_fresh_proof_recheck || return 1`, then as its next
#       statement `_own_view_veto || return 1`, BEFORE its DRY_RUN branch and its first set-identity; no other
#       command in either daemon calls the veto; (0a-ctl) the panels' evasions E0–E7, red; (0d) every
#       function defined once, at file level, never after the MAIN LOOP marker, no eval, one source (STATIC:
#       bash's parse, cross-checked against what sourcing the file leaves defined), and the post-marker
#       prologue, EXECUTED UNMOCKED on the seam cut with fakes only at the process boundary, changes no
#       function, trap, shopt, set -o option, builtin or alias (DYNAMIC: top-level snapshots, once per gate
#       branch, both daemons); the panels' spellings as rows, red
#   (1) D1 — explicit commitments: (1a) every curl COMMAND of both daemons' parse that sends an RPC body sends a
#       literal the census PARSES (jq), and every getVoteAccounts/getSlot request names params[0].commitment;
#       (1b) the site table (function, method, commitment) is pinned — the detection reads say finalized; (1c)
#       control: a body stripped of its commitment → (1a) red; (1c-T5) the panels' evasions C0–C9, red; (1d) ZERO
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
#       R3 + fix round 2's S2 — a baseline at every veto on slow take cycles (AV-3: healthy holds; the delta
#       panel's DAV-1/CK-2: the gossip advisory's pair; every baseline layer neutered together → every red back;
#       AV-6's starvation is BACK since fix round 3 and pinned as the named residual) and (7c-age) the measured
#       baseline ages over the three matrix axes with the named residuals; (7c-r7) FIX ROUND 4 — residual 7's
#       cells, its threshold as a sum (every LOCAL read at 1 s; fix round 5: a TIER2 that fails LATE with an
#       unusable answer, not only a timeout) and its mitigations, each exact; (7d) L4 — the fast path never skips
#       D2's timer; (7e) L3 — Tier-1 is the node's own health verdict; (7f) FIX ROUND 3 — the fresh re-check is
#       the 6.3 build's one sequential call again (the delta panel's DL-1 worlds and the delta panel 2's LB-1 /
#       LB-2 worlds never taken; red on round 1's pinned-first order) and the MIRROR world, taken again, pinned
#       as the named residual; (7f-r6) FIX ROUND 4 — its exposure up to the spare's lag and the health-check
#       distance that bounds it at the take cycle's Tier-1 check, each exact; (7g) S2's census on bash's own parse — every external read of the
#       take cycle, wherever bash runs it, has an own-head sample before it that runs in the function's own shell
#       on every path (N-is-all, by structure: the call graph over every function the parse defines walked; no
#       shell run as a command; the samples no world can make load-bearing, and the limits, are named there);
#       (7g-local) every write of LOCAL_RPC pinned — the LOCAL rule trusts that name
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
# (0a) reads bash's own parse of every shipped script (tests/lib/harness.sh bp_parse: each file wrapped in functions,
# printed by `declare -f` — comments gone, one command per line, a one-line or `function`-keyword definition normalized,
# outside a $( ), which bash 3.2 prints verbatim) and checks: every COMMAND word whose quotes and backslashes removed
# read set-identity, and every set-identity inside a string (a log line, a hint — a TEXT token), attributed to the
# function that holds it, is pinned as a whole (a new
# token anywhere is red); every COMMAND token's argument is literally "$STAKED_KEYPAIR" inside the two take functions and
# "$UNSTAKED_KEYPAIR" everywhere else; and bash sourcing each script it can (the daemons' seams, the arm, the fence
# scripts) leaves exactly the functions the parse lists. LIMIT, named: a verb assembled at run time ("$verb", a variable)
# or handed to eval as a string is not a command word here; the dynamic half is test_act_then_alert (15) — every staked
# set-identity in that suite's sims follows the veto's read (its audited validator stub sees any spelling).
ovp() {   # ovp <file> → the directory holding bp_parse's print and lex of <file> (parsed once per path, size and mtime); FAIL in it when bp_parse refuses the file (bash cannot parse it, or bash 5.2 printed an if-condition here-document — its print.err says which)
    local _k _m
    _m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)
    _k="$WORK/bp/$(printf '%s' "$1" | cksum | cut -d' ' -f1).$(wc -c < "$1" | tr -d ' ').$_m"
    [[ -d "$_k" ]] || { bp_parse "$1" "$_k" || : > "$_k/FAIL"; }
    printf '%s' "$_k"
}
SETID_AWK="$BP_AWK_LIB"'
$1 == "C" { n = split($6, W, "\034")
    for (k = 1; k <= n; k++) {
        if (bpq(W[k]) != "set-identity") continue
        f = $2; cmd[f]++; seen[f] = 1; rr = bpr(W[k]); rcmd[f] += gsub(/set-identity/, "&", rr)
        j = k + 1; if (j < n && bpq(W[j]) == "--config" && bpr(W[j + 1]) == "\"$CONFIG_TOML\"") j += 2
        arg = (j <= n) ? bpr(W[j]) : "(none)"
        want = "\"$UNSTAKED_KEYPAIR\""; if (f == "switch_to_staked" || f == "take_staked_identity") want = "\"$STAKED_KEYPAIR\""
        if (arg != want) badarg = badarg f "(arg " arg ", want " want ") "
    } }
$1 == "L" { r = $6; t = gsub(/set-identity/, "&", r); if (t) { tot[$2] += t; seen[$2] = 1 } }
$1 == "H" { r = $5; t = gsub(/set-identity/, "&", r); if (t) { tot[$2] += t; seen[$2] = 1 } }
END { if (mode == "args") printf "%s", badarg; else for (x in seen) printf "%s:%d/%d\n", x, cmd[x], tot[x] - rcmd[x] }'
setid_scan() {   # $1=file [$2=args] → "<fn>:<commands>/<texts> …" per function holding a set-identity token (bash's parse); args → the bad COMMAND arguments
    local _d; _d=$(ovp "$1")
    [[ -f "$_d/FAIL" ]] && { printf 'PARSE-FAIL:%s ' "$(basename "$1")"; return 0; }
    awk -F'\t' -v mode="${2:-count}" "$SETID_AWK" "$_d/lex" | { if [[ "${2:-count}" == "args" ]]; then cat; else sort | tr '\n' ' '; fi; }
}
setid_census() { local f s out=""; for f in "$@"; do s=$(setid_scan "$f"); [[ -n "$s" ]] && out="$out$(basename "$f")[$s]"; done; printf '%s' "$out"; }
setid_badargs() { local f out=""; for f in "$@"; do out="$out$(setid_scan "$f" args)"; done; printf '%s' "$out"; }
setid_xcheck() { local f x out=""; for f in "$@"; do x=$(bp_xcheck "$f" "$(ovp "$f")" | grep -v '^NO-HEAD$' | tr '\n' ';'); [[ -n "$x" ]] && out="$out $(basename "$f"):[$x]"; done; printf '%s' "$out"; }
# ev_mut <src> <anchor (a fixed string, on a code line)> <before|after> <out-file> — a mutant copy with the block on
# stdin inserted at the FIRST non-comment line containing the anchor; rc 1 if the anchor was not found
ev_mut() {
    mkdir -p "$(dirname "$4")"; cat > "$4.ins"
    awk -v a="$2" -v w="$3" -v insf="$4.ins" 'BEGIN { while ((getline l < insf) > 0) blk = blk l "\n" }
        !done && $0 !~ /^[[:space:]]*#/ && index($0, a) { if (w == "before") printf "%s", blk; print; if (w == "after") printf "%s", blk; done = 1; next }
        { print } END { exit(done ? 0 : 1) }' "$1" > "$4"
}
ST_CENSUS="solana-primary-failover.sh[_alpenglow_gate_check:0/2 _selffence_hard_stop:0/3 announce_config_drift:0/1 switch_to_staked:2/3 switch_to_unstaked:2/3 ]solana-standby-failover.sh[_alpenglow_gate_check:0/2 announce_config_drift:0/1 give_back_identity:2/3 take_staked_identity:2/4 ]deploy-failover.sh[(top):0/2 ]failover-arm.sh[_retire_legacy_monitors:0/2 ]failover-fence.sh[_admin_remove_all:0/1 _admin_set_identity_unstaked:1/2 _sustained_identity_repoll:0/1 main:0/2 ]"
take_sites=$(setid_census $SHIPPED); arg_bad=$(setid_badargs $SHIPPED); st_xc=$(setid_xcheck $SHIPPED)
if [[ "$take_sites" == "$ST_CENSUS" && -z "$arg_bad" && -z "$st_xc" ]]; then
    ok "(0a) N-is-all, on bash's own parse of the eight shipped scripts: EVERY set-identity token is pinned by file, function and kind — a COMMAND word (its quotes and backslashes removed) or TEXT inside a string or a here-document (the primary wizard's two are its env template's comments) — the only COMMAND tokens are switch_to_staked's two (agave + fdctl — primary) and take_staked_identity's two (standby) to \"\$STAKED_KEYPAIR\", and switch_to_unstaked's, give_back_identity's and the fence's to \"\$UNSTAKED_KEYPAIR\"; nothing in install.sh / the deploy wizards / the arm can set an identity; bash sourcing the daemons' seams, the arm and the fence scripts leaves exactly the functions the parse lists, each with its printed body"
else
    bad "(0a) take-path census moved: census=[$take_sites] args:[$arg_bad] parse-vs-exec:[$st_xc]"
fi
# (0a-ctl) the panel's evasions (T3), each a new take function with no re-check and no veto, inserted into a copy of
# the standby: E0 plain; E1 a wrapper (_si_wrap "$STAKED_KEYPAIR"); E2 a keypair variable; E3 "${STAKED_KEYPAIR}";
# E4 a line continuation; E5 a log_warn-prefixed line; E6 the delta panel 4's (T4-LEXER-QUOTES, its verifier's
# extension): a take in rotate_log behind `log_info "take # 1";` (the source-line lexer cut it at the quoted ' # ': green
# on fix round 4's census); E7 (this round's) the same behind an apostrophe inside a string (red there too). Each layer
# ALONE is red on each (the pinned table: a new COMMAND token; the argument rule: the token's argument is not the take
# functions' literal).
ec_rows=""; ec_ok=1
for e in E0 E1 E2 E3 E4 E5 E6 E7; do
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
        E6) ev_mut "$STANDBY" "rotate_log() {" after "$m" <<'EOB'
    log_info "take # 1"; timeout 15 "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR"
EOB
        ;;
        E7) ev_mut "$STANDBY" "rotate_log() {" after "$m" <<'EOB'
    log_info "the spare's take"; timeout 15 "$SOLANA_PATH/agave-validator" --ledger "$LEDGER_PATH" set-identity "$STAKED_KEYPAIR"; : 'x'
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
    ok "(0a-ctl) the panel's T3 evasions, each inserted into a copy of the standby as a new take function without the re-check or the veto, and takes hidden in rotate_log behind a quoted ' # ' (E6, the delta panel 4's) or an apostrophe (E7) — every one is RED on BOTH layers alone:$ec_rows (the 6.3.1 census before fix round 1: E0 red, E1–E5 green; fix round 4's source-line census: E6 green, E7 red)"
else
    bad "(0a-ctl) an evasion is green on a layer:$ec_rows"
fi
# (0b) the guards' ORDER on each take path, on bash's own parse (6.3.1 fix round 6 — the delta panel 5's TS5-0B-NOT-ON-PARSE:
# it read source lines for one spelling, so a here-document no-op block around the re-check and the veto, or a second
# call spelled `if ! _own_view_veto`, passed). It walks the take function's own statements in order — the C records at
# its own level (not in a substitution or a subshell), with the STRUCTURE bash runs them in (the parse's K records) — and
# requires: `_fresh_proof_recheck || return 1`, then as the very next statement `_own_view_veto || return 1`, each a
# statement at the take function's structure depth 0 (not inside an if, a case, a loop, a { } group or a subshell — a
# guard there runs on some paths only), each guard's command the first of its statement (no && || | or |& before it:
# `true || _fresh_proof_recheck || return 1` never runs the re-check), neither guard negated by a `!` (the lexer's C
# record carries the negation flag: `! _own_view_veto || return 1` takes exactly when the veto refuses), and whose
# `return 1` is not followed by & | or |& (a background or pipeline return returns nothing); then the DRY_RUN branch's
# condition [[ "$DRY_RUN" == "true" ]], then the first set-identity command; and every command in the daemon whose
# effective command word is _own_view_veto (any function, level or spelling bash's print keeps — `if !`, `$( )`, a prefix
# assignment) is that one call. Rows ob1–ob5 (the delta panel 6's): the two guards inside a DRY_RUN-only if, an && { }
# group, a case arm, a while loop, and the veto's `|| return 1 &`; rows obn1–obn2 (the delta panel 7's
# CHK7-0B-NEGATION): `! _own_view_veto || return 1` and `! _fresh_proof_recheck || return 1`; rows obl1–obl2 (fix round
# 8's, found closing it): `true || _fresh_proof_recheck || return 1` and `: | _fresh_proof_recheck || return 1` — each
# red.
B0_AWK="$BP_AWK_LIB"'
$1 == "K" && $2 == fn && $5 == 1 && $6 == 0 { if ($7 == "if" || $7 == "loop" || $7 == "case" || $7 == "grp") dp++; else if ($7 == "fi" || $7 == "done" || $7 == "esac" || $7 == "grp-end") dp--; next }
$1 == "C" { n = split($6, W, "\034"); split($7, X, ":"); k = bpcmd(n, W); q = k ? bpq(W[k]) : ""
  if (q == "_own_view_veto") nv++
  if ($2 != fn || X[1] != 1 || X[2] != 0) next
  s++; Q[s] = q; P[s] = X[3]; O[s] = X[4]; NG[s] = X[5]; A[s] = (k && k < n) ? bpq(W[k + 1]) : ""; J[s] = ""; si[s] = 0; LN[s] = $4; DP[s] = dp + 0   # + 0: busybox awk copies an unset dp as the STRING "", which is not == 0
  for (j = 1; j <= n; j++) { J[s] = J[s] (j > 1 ? " " : "") bpq(W[j]); if (bpq(W[j]) == "set-identity") si[s] = 1 } }
END { for (i = 1; i <= s; i++) {
        g = (Q[i + 1] == "return" && P[i + 1] == "||" && A[i + 1] == "1" && O[i] == "||" && P[i] == "" && NG[i] == "" && DP[i] == 0 && DP[i + 1] == 0 && O[i + 1] != "&" && O[i + 1] != "|" && O[i + 1] != "|&")
        if (!r && Q[i] == "_fresh_proof_recheck" && g) r = i
        if (!v && Q[i] == "_own_view_veto" && g) v = i
        if (!d && J[i] == "[[ $DRY_RUN == true ]]") d = i
        if (!z && si[i]) z = i }
      printf "%d %d %d %d %d %s %s %s %s\n", r, v, d, z, nv + 0, LN[r], LN[v], LN[d], LN[z] }'
g_ok=1; g_rows=""
for pair in "$PRIMARY:switch_to_staked" "$STANDBY:take_staked_identity"; do
    f="${pair%%:*}"; fn="${pair##*:}"
    read -r rl vl dl sl vc rp vp dp sp_ < <(awk -F'\t' -v fn="$fn" "$B0_AWK" "$(ovp "$f")/lex")
    if [[ -n "$rl" && $rl -gt 0 && $vl -eq $((rl + 2)) && $dl -gt $vl && $sl -gt $dl && "$vc" == "1" ]]; then
        g_rows="$g_rows $(basename "$f"):$fn(recheck print l$rp → veto l$vp → DRY_RUN l$dp → set-identity l$sp_)"
    else
        g_ok=0; bad "(0b) $(basename "$f") $fn: statement recheck=$rl veto=$vl dry=$dl setid=$sl veto-calls-in-file=$vc"
    fi
done
# the rows ob1–ob5 (the delta panel 6's CEN6-0B-STRUCTURE — red first: each GREEN on fix round 6's (0b), which read the take
# function's statements as a flat list; (3c-seg) was red on each): the standby's re-check and veto inside a DRY_RUN-only if
# (ob1), an && { } group (ob2), a case arm (ob4), a while loop (ob5), and the veto's `|| return 1 &` (ob3); the rows
# obn1–obn2 (the delta panel 7's CHK7-0B-NEGATION — red first: each GREEN on fix round 7's (0b), whose lexer dropped the
# `!`): the veto negated (obn1), the re-check negated (obn2); the rows obl1–obl2 (fix round 8's — red first: each GREEN on
# fix round 7's (0b), which read a guard's command without the operator before it): the re-check behind `true ||` (obl1:
# it never runs) and as a pipeline's last command (obl2)
ob_mut() {   # ob_mut <name> <line before the re-check> <line after the veto> [<the veto's line replaced>] [<the re-check's line replaced>] — awk -v: \n separates lines
    awk -v b="$2" -v a="$3" -v r="${4:-}" -v rc="${5:-}" '$0 == "take_staked_identity() {" { inf = 1 }
        inf && !d1 && $0 == "    _fresh_proof_recheck || return 1" { if (b != "") print b; print (rc != "" ? rc : $0); d1 = 1; next }
        inf && d1 && !d2 && $0 == "    _own_view_veto || return 1" { print (r != "" ? r : $0); if (a != "") print a; d2 = 1; next }
        { print } END { exit((d1 && d2) ? 0 : 1) }' "$STANDBY" > "$WORK/s-0b-$1.sh"
}
ob_mut ob1 '    if [[ "$DRY_RUN" != "true" ]]; then' '    fi'
ob_mut ob2 '    [[ -z "${FAILOVER_SKIP_GUARDS:-}" ]] && {' '    }'
ob_mut ob3 '' '' '    _own_view_veto || return 1 &'
ob_mut ob4 '    case "$DRY_RUN" in\n    false)' '    ;;\n    esac'
ob_mut ob5 '    while true; do' '    break; done'
ob_mut obn1 '' '' '    ! _own_view_veto || return 1'
ob_mut obn2 '' '' '' '    ! _fresh_proof_recheck || return 1'
ob_mut obl1 '' '' '' '    true || _fresh_proof_recheck || return 1'
ob_mut obl2 '' '' '' '    : | _fresh_proof_recheck || return 1'
ob_rows=""; ob_ok=1
for _o in ob1 ob2 ob3 ob4 ob5 obn1 obn2 obl1 obl2; do
    [[ -s "$WORK/s-0b-$_o.sh" ]] && ! cmp -s "$STANDBY" "$WORK/s-0b-$_o.sh" || { ob_ok=0; ob_rows="$ob_rows $_o:NOT-BUILT"; continue; }
    read -r rl vl dl sl vc rp vp dp sp_ < <(awk -F'\t' -v fn=take_staked_identity "$B0_AWK" "$(ovp "$WORK/s-0b-$_o.sh")/lex")
    if [[ -n "$rl" && $rl -gt 0 && $vl -eq $((rl + 2)) && $dl -gt $vl && $sl -gt $dl && "$vc" == "1" ]]; then ob_ok=0; ob_rows="$ob_rows $_o:GREEN"; else ob_rows="$ob_rows $_o:red(recheck=$rl,veto=$vl)"; fi
done
[[ $ob_ok -eq 1 ]] || { g_ok=0; bad "(0b) a structure row is not red:$ob_rows"; }
[[ $g_ok -eq 1 ]] && ok "(0b) on bash's own parse, on EVERY take path the veto's '|| return 1' is the statement right after the fresh re-check's, each a statement at the take function's structure depth 0 (not inside an if, a case, a loop, a { } group or a subshell), each guard's command the first of its statement, neither guard negated by a '!', whose return is not followed by & | or |&, and both precede the DRY_RUN branch (DRY_RUN mirrors the live decision) and the first set-identity; every command of either daemon whose effective command word is _own_view_veto is that one call (primary 1, standby 1):$g_rows; rows ob1–ob5 (the guards in a DRY_RUN-only if, an && { } group, a case arm, a while loop, a backgrounded return) obn1–obn2 (the veto negated, the re-check negated) and obl1–obl2 (the re-check behind 'true ||', in a pipeline) each red:$ob_rows"
# the primary's other staked-going call is the pre-warm authorized-voter add (not a set-identity) — named
if code_of "$STANDBY" | grep -q 'authorized-voter add' && ! code_of "$STANDBY" | grep 'authorized-voter add' | grep -q 'set-identity'; then
    ok "(0c) named exclusions: the standby's PREWARM authorized-voter add (off by default, live-test-gated) is not a set-identity and never makes this node vote the staked identity; the fence scripts and the arm only ever move toward UNSTAKED"
else
    bad "(0c) the pre-warm exclusion no longer reads as stated"
fi

# (0d) redefinitions — every census above reads a function's text once, and every suite loads the daemon only up to the
# MAIN LOOP marker, so a later, nested or dynamic redefinition would neuter a safety function in production while every
# census and suite stayed green (the delta panels' sV1/sV2, T7-REDEF2, TS3-0D-EVASIONS, T4-0D-DYN-MOCKED, T4-LEXER-QUOTES).
# Two halves, both daemons.
# STATIC — reads bash's own parse of the whole daemon (tests/lib/harness.sh bp_parse; command words read with their
# quotes and backslashes removed, the effective one past assignments and a `time -p` / `builtin --` / `command -p --`
# prefix) and checks: every function is defined exactly once, at the file level, before the
# marker (a definition nested in a function, a subshell or a substitution, or anywhere after the marker, is red); bash
# SOURCING the seam leaves exactly those functions defined, each with its printed body (bp_xcheck — a redefinition by
# load-time code shows there); the word eval appears nowhere; exactly one source / . command (the operator's config),
# with exactly the four clock/validator helpers defined before it (for every other name the daemon's own definition
# replaces one the config makes; for those four the config, sourced at the local-host trust level — docs/SAFETY.md's
# threat model — has the last word, as it has over every knob); the shell-state commands (trap shopt set enable alias
# unalias unset mapfile readarray declare typeset hash) are exactly the pinned three, all at the file level (shopt -u
# patsub_replacement, set +e, the cleanup trap); and the marker is followed by exactly the pinned top-level statements.
# DYNAMIC — runs the REAL post-marker prologue (startup_checks and the alpenglow gate) in `env -i bash` on the seam
# sourced directly — no harness sink, no clock shim, no function mock: fakes only at the process boundary (curl, timeout,
# systemctl and pgrep first in PATH; agave-validator and solana-keygen in SOLANA_PATH; fixture keypairs; a temp LOG_FILE
# and state dirs; the daemon's own `source "$CONFIG_FILE"` reading a fixture config with Telegram, the webhook and the
# heartbeat unset) — and snapshots, at the TOP level of that shell (a function would hide the ERR and DEBUG traps), before
# and after: declare -F, declare -f, trap -p, shopt -p, set -o, enable -a, alias -p. Any difference is red. Once per
# branch of the gate; the real log() must have written the startup line (the run is not vacuous); the prologue is the text
# between the marker and the main loop's `while $_running; do` line (a comment after it included), and the run is under
# a watchdog: past RD_DYN_BOUND (120) seconds it is killed and red (TIMEOUT), never a hang.
# LIMIT, named: a command word assembled at run time ($x, "$cmd") or code handed as a string to a builtin the static
# half does not name; the dynamic half runs the prologue's clean-start path (VALIDATOR_TYPE=agave, no fence marker, no
# persisted state, unarmed). The rows below (RD_ROWS) are the delta panels' spellings, kept as regression rows.
REDEF_AWK="$BP_AWK_LIB"'
BEGIN { ns = 0; pre = ""; post = 0 }
$1 == "D" && $3 == 0 { if ($2 == "__bp_post__") post = 1; next }
$1 == "D" { n = $2; def[n]++
    if ($3 != 1 || $4 == 1) printf "NESTED-DEF %s (depth %d%s, print line %d)\n", n, $3, ($4 == 1 ? ", in a subshell or a substitution" : ""), $5
    if (post) printf "DEF-AFTER-MARKER %s (print line %d)\n", n, $5
    if ($3 == 1 && $6 == "(top)" && ns == 0) pre = pre n " " }
$1 == "C" { n = split($6, W, "\034"); k = bpcmd(n, W)
    for (j = 1; j <= n; j++) if (bplit(W[j]) && bpq(W[j]) == "eval") printf "EVAL %s (print line %d)\n", $2, $4
    if (k) { q = bpq(W[k])
        if (q == "source" || q == ".") { ns++; src = src $2 ":" $4 "," }
        if (q ~ /^(trap|shopt|set|enable|alias|unalias|unset|mapfile|readarray|declare|typeset|hash)$/) { a = ""; for (j = k + 1; j <= n; j++) a = a " " bpq(W[j]); st = st $2 ":" q a "|" } } }
$1 == "L" && $2 == "(post)" && $3 == 0 && substr($6, 1, 4) == "    " && substr($6, 5, 1) != " " { c = $5; sub(/^ +/, "", c); sub(/ +$/, "", c); top = top c "|" }
END { for (n in def) if (def[n] > 1) printf "DUPLICATE %s x%d\n", n, def[n]
      if (ns != 1) printf "SOURCE-COUNT %d (%s)\n", ns, src
      if (pre != "mono_now _canon_uint boot_id _m2w ") printf "DEFINED-BEFORE-THE-SOURCE %s\n", pre
      printf "STATE %s\nTOP %s\n", st, top }'
RD_STATE='(top):shopt -u patsub_replacement|(top):set +e|(top):trap cleanup SIGTERM SIGINT SIGHUP|'
RD_SHAPE='startup_checks ;|if [[ "" =~ ^[0-9]+$ && $(()) -gt 0 ]] ; then|else|fi ;|while $_running ; do|done ;|if [[ "" == true ]] ; then|fi ;|log_info "" ;|:|'
redef_census() {   # redef_census <daemon> → the static half's violations, one per line ("" = none; the pinned state and shape compared here)
    local _d _o
    _d=$(ovp "$1")
    [[ -f "$_d/FAIL" ]] && { echo "PARSE-FAIL $(head -c 160 "$_d/print.err" | tr '\n' ' ')"; return 0; }
    bp_xcheck "$1" "$_d"
    _o=$(awk -F'\t' "$REDEF_AWK" "$_d/lex")
    printf '%s\n' "$_o" | grep -v -e '^STATE ' -e '^TOP '
    [[ "$(printf '%s\n' "$_o" | sed -n 's/^STATE //p')" == "$RD_STATE" ]] || echo "STATE-MOVED [$(printf '%s\n' "$_o" | sed -n 's/^STATE //p')]"
    [[ "$(printf '%s\n' "$_o" | sed -n 's/^TOP //p')" == "$RD_SHAPE" ]] || echo "SHAPE-MOVED [$(printf '%s\n' "$_o" | sed -n 's/^TOP //p')]"
}
# the DYNAMIC half — the process boundary, written once; the fixture config per run
rd_fakes() {   # rd_fakes <dir> — the fake binaries, written ONCE per suite run (macOS assesses every new executable on its
               # first exec, ~0.25 s each): curl, timeout, systemctl, pgrep in <dir>/bin; agave-validator, solana-keygen in
               # <dir>/sp; each logs its call to $RD_CALLS (the run's own file)
    [[ -x "$1/sp/solana-keygen" ]] && return 0
    mkdir -p "$1/bin" "$1/sp"
    printf '#!/bin/sh\nprintf "curl %%s\\n" "$*" >> "${RD_CALLS:-/dev/null}"\nexit 7\n' > "$1/bin/curl"
    printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do case "$1" in -k|-s) shift 2 ;; -*) shift ;; *) break ;; esac; done\nshift\nexec "$@"\n' > "$1/bin/timeout"
    printf '#!/bin/sh\nprintf "systemctl %%s\\n" "$*" >> "${RD_CALLS:-/dev/null}"\nexit 1\n' > "$1/bin/systemctl"
    printf '#!/bin/sh\nexit 1\n' > "$1/bin/pgrep"
    printf '#!/bin/sh\nprintf "agave-validator %%s\\n" "$*" >> "${RD_CALLS:-/dev/null}"\ncase " $* " in *" contact-info "*) echo "Identity: UNSTAKEDPK1" ;; esac\nexit 0\n' > "$1/sp/agave-validator"
    printf '#!/bin/sh\n[ "$1" = pubkey ] || exit 1\ncase "$2" in *unstaked.json) echo UNSTAKEDPK1 ;; *staked.json) echo STAKEDPK1 ;; *) exit 1 ;; esac\n' > "$1/sp/solana-keygen"
    chmod +x "$1/bin/"* "$1/sp/"*
    harness_stub_dir "$1/bin"   # its curl: a stub of a listed client (the strace job counts its execs as a stub's)
}
rd_dyn() {   # rd_dyn <daemon> <ALPENGLOW_GATE_CHECK_HOURS> → "" when the REAL prologue changed nothing; else what changed: +NAME /
             # -NAME / ~NAME (a function appeared / vanished / changed), T: S: O: E: A: (a trap / shopt / set -o / enable / alias
             # line); EXIT=<rc> when it did not run through; QUIET when the real log() never wrote the startup line; TIMEOUT(<n>s)
             # when it ran past RD_DYN_BOUND (default 120) seconds and was killed
    local _w _cfg _rc _k _pid _wd
    _w=$(mktemp -d "$WORK/rdd.XXXXXX"); rd_fakes "$WORK/rdfake"; mkdir -p "$_w/state" "$_w/led"
    echo '[1,2,3]' > "$_w/staked.json"; echo '[4,5,6]' > "$_w/unstaked.json"
    _cfg=$(sed -n 's|^CONFIG_FILE=.*/\(failover[a-z-]*\.env\)"$|\1|p' "$1")
    cat > "$_w/${_cfg:-failover.env}" <<EOC
SOLANA_PATH="$WORK/rdfake/sp"; VALIDATOR_TYPE=agave; LEDGER_PATH="$_w/led"; STAKED_KEYPAIR="$_w/staked.json"; UNSTAKED_KEYPAIR="$_w/unstaked.json"
VOTE_PUBKEY=V1; PRIMARY_UNSTAKED_PUBKEY=PU1; LOCAL_RPC=http://local.mock; TIER2_RPC=http://t2.mock; TIER3_RPC=http://t3.mock
STATE_DIR="$_w/state"; STATE_FILE="$_w/state/state"; FENCE_MARKER_DIR="$_w/state"; PROOF_STATE_DIR="$_w/state"; LOG_FILE="$_w/daemon.log"
STARTUP_GRACE=0; DRY_RUN=false; TG_ENABLED=false; TG_BOT_TOKEN=""; TG_CHAT_ID=""; WEBHOOK_URL=""; HEARTBEAT_URL=""; ALPENGLOW_GATE_CHECK_HOURS=$2
EOC
    sed -n '1,/^# =* MAIN LOOP =*$/p' "$1" > "$_w/cut.sh"
    awk '/^# =* MAIN LOOP =*$/ { p = 1; next } /^while \$_running; do/ { exit } p' "$1" > "$_w/prologue.sh"   # unanchored: a comment after `do` still ends the prologue
    cat > "$_w/run.sh" <<'EOR'
source "$1/cut.sh" </dev/null >/dev/null 2>&1
declare -F > "$1/A.F"; declare -f > "$1/A.f"; trap -p > "$1/A.T"; shopt -p > "$1/A.S"; set -o > "$1/A.O"; enable -a > "$1/A.E"; alias -p > "$1/A.A"
source "$1/prologue.sh" </dev/null >/dev/null 2>&1
: > "$1/ran"
declare -F > "$1/B.F"; declare -f > "$1/B.f"; trap -p > "$1/B.T"; shopt -p > "$1/B.S"; set -o > "$1/B.O"; enable -a > "$1/B.E"; alias -p > "$1/B.A"
EOR
    # the child under a WATCHDOG (6.3.1 fix round 6 — the delta panel 5's TS5-0D-DYN-HANG: a prologue that took in the main
    # loop ran forever): past RD_DYN_BOUND seconds it is killed and the row reads TIMEOUT — red, never a hang
    ( cd "$_w" && exec env -i PATH="$WORK/rdfake/bin:$PATH" HOME="$_w" TMPDIR="$_w" RD_CALLS="$_w/calls" "${BASH:-bash}" "$_w/run.sh" "$_w" ) >/dev/null 2>&1 &
    _pid=$!
    ( _t=0; while [[ $_t -lt ${RD_DYN_BOUND:-120} ]] && kill -0 "$_pid" 2>/dev/null; do sleep 1; _t=$((_t + 1)); done
      kill -0 "$_pid" 2>/dev/null && { : > "$_w/timeout"; kill -KILL "$_pid" 2>/dev/null; } ) >/dev/null 2>&1 &
    _wd=$!
    wait "$_pid"; _rc=$?
    kill "$_wd" 2>/dev/null; wait "$_wd" 2>/dev/null
    [[ -f "$_w/timeout" ]] && { printf 'TIMEOUT(%ss) ' "${RD_DYN_BOUND:-120}"; return 0; }
    [[ -f "$_w/ran" ]] || { printf 'EXIT=%s ' "$_rc"; return 0; }
    grep -q 'tarted\. Identity: UNSTAKEDPK1' "$_w/daemon.log" 2>/dev/null || printf 'QUIET '
    awk -F'\t' 'NR == FNR { a[$1] = $2; next } { b[$1] = 1; if (!($1 in a)) printf "+%s ", $1; else if (a[$1] != $2) printf "~%s ", $1 }
                END { for (n in a) if (!(n in b)) printf "-%s ", n }' <(rd_fnsig "$_w/A.f") <(rd_fnsig "$_w/B.f")
    for _k in T S O E A; do cmp -s "$_w/A.$_k" "$_w/B.$_k" || printf '%s:[%s] ' "$_k" "$(diff "$_w/A.$_k" "$_w/B.$_k" | grep '^[<>]' | tr '\n' ';' | cut -c1-120)"; done
}
rd_fnsig() {   # rd_fnsig <declare -f dump> — one line per function: NAME<TAB>its whole text
    awk '/^[^[:space:]]+ \(\) ?$/ { if (n != "") print n "\t" b; n = $1; b = ""; next } { b = b "\001" $0 } END { if (n != "") print n "\t" b }' "$1"
}
rd_mut() {   # rd_mut <in> <out> <where> — the row text (stdin) inserted: head:F (first line of F's body), tail:F (its last),
             # before:F (column 0, above F), marker (right after the MAIN LOOP marker); rc 1 (and a FAIL) when nothing moved
    RD_T="$(cat)" awk -v w="$3" '
        BEGIN { k = w; sub(/:.*/, "", k); f = w; sub(/^[^:]*:?/, "", f); t = ENVIRON["RD_T"] }
        k == "marker" && !done && /^# =* MAIN LOOP =*$/ { print; print t; done = 1; next }
        !done && !inf && $0 == f "() {" && (k == "head" || k == "before" || k == "tail") {
            if (k == "before") { print t; print; done = 1; next }
            print; if (k == "head") { print t; done = 1 } else inf = 1; next }
        inf && /^}$/ { print t; print; inf = 0; done = 1; next }
        { print } END { exit(done ? 0 : 1) }' "$1" > "$2" && ! cmp -s "$1" "$2" || { bad "(0d) rd_mut: nothing inserted at $3 in $(basename "$1")"; return 1; }
}
rd_ok=1; rd_rows=""; rdd_rows=""
for _d in "$STANDBY" "$PRIMARY"; do
    _v=$(redef_census "$_d")
    [[ -z "$_v" ]] || { rd_ok=0; rd_rows="$rd_rows [$(basename "$_d"): $(printf '%s' "$_v" | tr '\n' ';')]"; }
    rd_rows="$rd_rows $(basename "$_d" .sh)=$(grep -c . "$(ovp "$_d")/names")-functions"
    for _g in 0 24; do
        _r=$(rd_dyn "$_d" "$_g"); rdd_rows="$rdd_rows $(basename "$_d" .sh)/gate=$_g:[${_r% }]"
        [[ -z "$_r" ]] || rd_ok=0
    done
done
# the red-first rows: "@NAME daemon(s|p) where expect" then the inserted text (to the next @); expect S = the static half
# red alone (the line never runs in the prologue), SD = both halves red, D = the dynamic half alone, GREEN = neither (a
# harmless spelling); X9 is SD on bash >= 4 and S on 3.2 (no mapfile); a second where (+where) inserts the next part (@@)
# as well. E1 / E7 and the two loop-line rows edit a line in place (sed, below). Fix round 6 (the delta panel 5): tp* / bi*
# — TS5-0D-BPCMD-PREFIX's `time -p` / `builtin --` prefixes (green on fix round 5's census); csfn — a `function NAME {`
# definition inside a $( ), which bash 3.2 prints verbatim (CLM5-8); whilecomment — a comment after the main loop's `do`,
# which hung the dynamic half (TS5-0D-DYN-HANG); whilesp — a loop line the prologue cut does not match: the dynamic half
# runs the main loop and its WATCHDOG (a 10 s bound for this row) kills it — TIMEOUT, red, never a hang.
cat > "$WORK/rdrows.txt" <<'EOF_RD'
@sV1 s marker SD
_own_view_veto() { return 0; }
@sV2 s head:startup_checks SD
    _own_view_veto() { return 0; }
@sV3 s before:_own_head_sample S
_fresh_proof_recheck() { return 0; }
@E1 s sed SD
@E2 s head:startup_checks SD
    true && _own_view_veto() { return 0; }
@E3 s head:startup_checks SD
    _own_view_veto() ( return 0 )
@E4 s head:startup_checks SD
    _own_view_veto() [[ 1 ]]
@E5 s before:_own_head_sample S
_own_view_veto() ( return 0 )
@E6 s head:startup_checks SD
    eval "_own_view_veto() { return 0; }"
@E7 s sed SD
@X28 s head:startup_checks SD
    _own_view_veto ( ) { return 0; }
@X28b s before:startup_checks S
_own_view_veto ( ) { return 0; }
@X1 s head:startup_checks SD
    function \
        _own_view_veto { return 0; }
@X2 s head:startup_checks SD
    _own_view_veto \
        () { return 0; }
@X23 s head:startup_checks SD
    if source /dev/stdin <<< '_own_view_veto() { return 0; }'; then :; fi
@X24 s head:startup_checks SD
    if true; then . /dev/stdin <<< '_own_view_veto() { return 0; }'; fi
@X25 s head:startup_checks SD
    ! source /dev/stdin <<< '_own_view_veto() { return 0; }'
@X26 s head:startup_checks SD
    "source" /dev/stdin <<< '_own_view_veto() { return 0; }'
@X6 s head:startup_checks SD
    \source /dev/stdin <<< '_own_view_veto() { return 0; }'
@X7 s head:startup_checks SD
    \. /dev/stdin <<< '_own_view_veto() { return 0; }'
@X27 s head:startup_checks SD
    \source /dev/stdin <<'EOS'
_own_view_veto \
() { return 0; }
EOS
@X3 s head:startup_checks SD
    'eval' "_own_view_veto() { return 0; }"
@X4 s head:startup_checks SD
    ev''al '_own_view_veto() { return 0; }'
@X5 s head:startup_checks SD
    trap '_own_view_veto() { return 0; }' DEBUG
@X9 s head:startup_checks X9
    mapfile -t -C '_own_view_veto() { return 0; }; :' -c 1 _x <<< x
@X11 s before:startup_checks+head:startup_checks SD
command_not_found_handle() { return 0; }
@@
    unset -f _own_view_veto
@m1 s head:log SD
    \source /dev/stdin <<< '_own_view_veto() { return 0; }'
@m2 s head:heartbeat_ping SD
    \source /dev/stdin <<< '_own_view_veto() { return 0; }'
@m3 s head:startup_checks SD
    trap '[[ ${STAT_CHECKS:-0} -gt 0 ]] && _own_view_veto() { return 0; }' ERR
@m4 s head:startup_checks SD
    shopt -s extdebug; trap '[[ "$BASH_COMMAND" != _own_view_veto ]]' DEBUG
@m5 s tail:startup_checks SD
    enable -n return
@m6 s head:detect_ledger_path SD
    \source /dev/stdin <<< '_own_view_veto() { return 0; }'
@m7 s head:log SD
    trap '_own_view_veto() { return 0; }' DEBUG
@m8 s head:heartbeat_ping SD
    'eval' "_own_view_veto() { return 0; }"
@apos s head:rotate_log S
    log_info "rotating the spare's log"; _own_view_veto() { printf '%s' ok >/dev/null; return 0; }
@hash s head:rotate_log S
    log_info "rotate #1"; _own_view_veto() { return 0; }
@p1 p head:log SD
    \source /dev/stdin <<< '_own_view_veto() { return 0; }'
@p2 p head:detect_tower_base SD
    \source /dev/stdin <<< '_own_view_veto() { return 0; }'
@tpsrc s head:rotate_log S
    time -p source /dev/stdin <<< '_own_view_veto() { return 0; }' 2>/dev/null
@tptrap s head:rotate_log S
    time -p trap '_own_view_veto() { return 0; }' DEBUG 2>/dev/null
@tpenable s head:rotate_log S
    time -p enable -n return 2>/dev/null
@tpunset s head:rotate_log S
    time -p unset -f _own_view_veto 2>/dev/null
@bisrc s head:rotate_log S
    builtin -- source /dev/stdin <<< '_own_view_veto() { return 0; }'
@bitrap s head:rotate_log S
    builtin -- trap '_own_view_veto() { return 0; }' DEBUG
@csfn s head:startup_checks S
    _x=$( function _own_view_veto { return 0; }; echo ok )
@whilecomment s sed GREEN
@whilesp s sed D
EOF_RD
awk -v w="$WORK" '/^@@$/ { f = f "b"; printf "" > f; next } /^@/ { f = w "/rdr_" substr($1, 2); printf "%s %s %s\n", $2, $3, $4 > (f ".meta"); printf "" > f; next } { print >> f }' "$WORK/rdrows.txt"
rdX_ok=1; rdX_rows=""
for _meta in $(ls "$WORK"/rdr_*.meta | sort); do
    _x=${_meta##*/rdr_}; _x=${_x%.meta}; read -r _dm _where _want < "$_meta"
    _src="$STANDBY"; [[ "$_dm" == "p" ]] && _src="$PRIMARY"; _m="$WORK/s-rdx-$_x.sh"
    case "$_x" in
        E1) mutate "$_src" 's/^\(    log_info "\[alpenglow\] tripwire armed: probing the feature gate every ${ALPENGLOW_GATE_CHECK_HOURS}h"\)$/\1; _own_view_veto() { return 0; }/' "$_m" ;;
        E7) mutate "$_src" 's/^\(if \[\[ "${ALPENGLOW_GATE_CHECK_HOURS:-0}" =~ ^\[0-9\]+\$ && \$((10#\$ALPENGLOW_GATE_CHECK_HOURS)) -gt 0 \]\]\); then$/\1 \&\& { _own_view_veto() { return 0; }; true; }; then/' "$_m" ;;
        whilecomment) mutate "$_src" 's/^while \$_running; do$/while $_running; do   # the main loop/' "$_m" ;;
        whilesp) mutate "$_src" 's/^while \$_running; do$/while $_running ; do/' "$_m" ;;
        *) if [[ "$_where" == *+* ]]; then rd_mut "$_src" "$_m.0" "${_where%%+*}" < "${_meta%.meta}" && rd_mut "$_m.0" "$_m" "${_where#*+}" < "${_meta%.meta}b"
           else rd_mut "$_src" "$_m" "$_where" < "${_meta%.meta}"; fi ;;
    esac || { rdX_ok=0; rdX_rows="$rdX_rows $_x=NOT-APPLIED"; continue; }
    _k=""; [[ -n "$(redef_census "$_m")" ]] && _k="S"
    _r=$(RD_DYN_BOUND=$([[ "$_x" == whilesp ]] && echo 10 || echo 120) rd_dyn "$_m" 24); [[ -n "$_r" ]] && _k="${_k}D"
    [[ "$_want" == "X9" ]] && { if [[ ${BASH_VERSINFO[0]} -ge 4 ]]; then _want=SD; else _want=S; fi; }
    rdX_rows="$rdX_rows $_x=${_k:-GREEN}"
    [[ "$_x" == whilesp && "$_r" != "TIMEOUT(10s) " ]] && _k="D-but-not-the-watchdog"
    [[ "${_k:-GREEN}" == "$_want" ]] || { rdX_ok=0; rdX_rows="$rdX_rows(want $_want: $(redef_census "$_m" | head -2 | tr '\n' ';' | cut -c1-120) ${_r:0:120})"; }
done
if [[ $rd_ok -eq 1 && $rdX_ok -eq 1 ]]; then
    ok "(0d) redefinitions on bash's own parse of each daemon — STATIC: every function defined exactly once, at the file level before the MAIN LOOP marker (none nested, in a subshell or a substitution, or after the marker), sourcing the seam leaves exactly those functions with their printed bodies, no eval word, one source (the config, after exactly mono_now _canon_uint boot_id _m2w), the file level's shell-state commands and the post-marker statements exactly the pinned ones:$rd_rows; DYNAMIC: the REAL prologue (startup_checks + the alpenglow gate) run unmocked on the seam in env -i bash with fakes at the process boundary only — declare -F / -f, trap -p, shopt -p, set -o, enable -a and alias -p unchanged at top level on both gate branches, the real log() wrote its startup line, the run under a 120 s watchdog:$rdd_rows. Not seen (the header): a command word assembled at run time, a string run by a builtin the static half does not name, the prologue's other start paths. Rows, the delta panels' spellings (S = the static half red, D = the dynamic half red, GREEN = a harmless spelling, whilesp = the watchdog's own TIMEOUT):$rdX_rows"
else
    bad "(0d) redefinitions:$rd_rows ::$rdd_rows :: rows:$rdX_rows"
fi

# ── (1) D1 — explicit commitments, census-enforced ─────────────────────────────────────────────────
echo ""; echo "─── (1) D1: every getVoteAccounts/getSlot body spells its commitment; the site table; zero behavior change ───"
# net_scan — every NETWORK primitive in a shell text on stdin (comment-stripped by the caller), one TAB-separated line
# each, for the [own-view] region census (3c) and the take segment's closure (3c-seg), which still read source text:
#   CURL <fn> <url-word|(none)> <n-bodies> <the -d body EXPANDED for jq | !why it is not a literal>
#   NET  <fn> <word>        (wget nc ncat socat telnet ssh scp openssl solana dig nslookup as a command, or /dev/tcp|udp)
# A command word counts only in COMMAND context — unquoted, or inside $( ) / backticks nested anywhere — after a
# boundary (start, blank, ; | & ( ! { } /). A double-quoted body is unescaped; a whole-string ${var} becomes "__VAR__",
# a number-position ${var} (after : [ ,) becomes 0; a $( ), a backtick, a bare "$body", @file or two bodies is NOT a
# literal (NS_FUNCS: the body and option rules, shared with (1a)'s reader of bash's parse, CURLS_AWK). LIMIT, named:
# the command word must be the unquoted, unescaped literal ("curl", \curl, cu''rl are not invocations to this scan),
# and a quoted string's apostrophe or ' # ' can hide the rest of a source line from it. The harness net guard
# intercepts `curl` / `command curl`, not an absolute /usr/bin/curl.
NS_FUNCS='
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
'
NETSCAN_AWK="$NS_FUNCS"'
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
# (1a)/(1b) read every curl COMMAND in bash's own parse of the daemon (bp_parse): a word whose quotes and backslashes
# removed read curl (or …/curl), in any function, the file level or after the marker — a command substitution, a
# $((cmd) ) and an unquoted here-document's $( ) / backticks included (bp_parse lexes them as the code bash runs); its
# URL word and -d body are its own words as printed. A SHELL run as a command is a request body this census cannot read:
# UNPARSEABLE (red; the daemons run none) — bp_parse's bpshell, found by the word, not by its wrappers, fail-closed: a
# literal word naming a shell (sh, bash, rbash, dash, ash, hush, zsh, ksh, ksh93, mksh, lksh, pdksh, oksh, posh, yash, csh,
# tcsh, fish by any path; busybox's sh / ash / hush / bash applet), whatever precedes it (timeout, env, nice --adjustment
# N, xargs --max-args N, stdbuf, sudo, find -exec …), unless the only words after it are --version or --help (nothing: its
# stdin; any option, a -c string, a script) — an env -S / --split-string string read as the words env splits it into, and
# sudo -s / -i (the user shell sudo runs) included. LIMIT, named: a curl whose command
# word is assembled at run time ("$c", a variable), a shell whose word is ("$SHELL -c"), a tool that runs a shell it picks
# itself (flock -c, su, script -c, chroot without a command), a string handed to eval / trap / mapfile -C (the (0d)
# census flags eval and pins every trap / mapfile), and code an interpreter runs from a string (awk's system(), perl -e,
# python3 -c).
CURLS_AWK="$BP_AWK_LIB$NS_FUNCS"'
$1 == "C" { n = split($6, W, "\034"); k = 0
    if (bpshell(n, W)) { printf "CURL\t%s\t(shell)\t0\t!a shell run as a command — its code is a string or a stream this census cannot read\n", $2; next }
    for (j = 1; j <= n; j++) { q = bpq(W[j]); if (bplit(W[j]) && (q == "curl" || q ~ /\/curl$/)) { k = j; break } }
    if (!k) next
    url = ""; nb = 0; body = ""
    for (j = k + 1; j <= n; j++) {
        q = bpq(W[j]); r = bpr(W[j])
        if (q ~ /^(-d|--data|--data-raw|--data-binary|--data-ascii|--data-urlencode|--json)$/) { nb++; body = bpr(W[j + 1]); j++; continue }
        if (q ~ /^-d./) { nb++; body = substr(r, 3); continue }
        if (q ~ /^--(data|data-raw|data-binary|data-ascii|json)=/) { nb++; body = r; sub(/^[^=]*=/, "", body); continue }
        if (q == "--url") { if (url == "") url = bpr(W[j + 1]); j++; continue }
        if (q ~ /^-/) { if (argopt(q)) j++; continue }
        if (url == "") url = r
    }
    if (nb == 1) eb = expand(body); else if (nb == 0) eb = "!no body"; else eb = "!" nb " bodies"
    printf "CURL\t%s\t%s\t%d\t%s\n", $2, (url == "" ? "(none)" : url), nb, eb
}'
rpc_bodies() {   # $1=file → one line per RPC curl (bash's parse): "<fn> <method|batch[…]> <commitment|NONE|MIXED|->" or "<fn> UNPARSEABLE <url> <why>"
    local fn url nb body out _d kind
    _d=$(ovp "$1")
    [[ -f "$_d/FAIL" ]] && { printf '(file) UNPARSEABLE (parse) bp_parse refused %s: %s\n' "$(basename "$1")" "$(head -c 160 "$_d/print.err" | tr '\n' ' ')"; return 0; }
    awk -F'\t' "$CURLS_AWK" "$_d/lex" | while IFS=$'\t' read -r kind fn url nb body; do
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
# (1a) reads every curl command of bash's own parse of both daemons (CURLS_AWK above) and checks: each one to an RPC
# endpoint carries ONE -d body that is a literal jq parses as a JSON-RPC request, and every getVoteAccounts/getSlot
# request in it names params[0].commitment (what agave reads — a top-level "commitment" is ignored there, so the default
# applies); the pages and pings are excluded by their URL words (NONRPC_URLS). LIMIT: CURLS_AWK's.
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
    ok "(1a) on bash's own parse of BOTH daemons (bp_parse), every curl COMMAND to an RPC endpoint — its command word read with quotes and backslashes removed, in any function, the file level or after the marker, a command substitution, a \$((cmd) ) and an unquoted here-document's \$( ) included — carries one literal -d body jq parses as a JSON-RPC request (primary 27, standby 29; the pages and pings excluded by their URL words), and every getVoteAccounts/getSlot request in them names params[0].commitment (17 bodies each, zero without one); no shell is run as a command (a literal shell word followed by anything but only --version / --help, whatever wraps it: its string, script or stream is unreadable — red); not seen: a curl or a shell whose command word is assembled at run time, a tool running its argument through a shell it names itself (flock -c), a string run by eval / trap / mapfile -C (the (0d) census's), code an interpreter runs from a string (awk's system(), perl -e, python3 -c)"
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
# self-fence getSlot's commitment moved to the TOP level (agave ignores it there — the default applies); and the delta
# panels 3/4's spellings of the curl itself (fix round 4's source-line census: C5 and C7–C9 green, C6 red): C5 behind a
# quoted ' # ' on its line, C6 behind an apostrophe inside a string, C7 "curl", C8 cu''rl, C9 c\url
c5_rows=""; c5_ok=1
for c in C0 C1 C2 C3 C4 C5 C6 C7 C8 C9; do
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
        C5) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read5() {
    log_info "fence # probe"; curl -s -m 5 "$TIER3_RPC" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null
}
EOB
        ;;
        C6) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read6() {
    log_info "the spare's probe"; curl -s -m 5 "$TIER3_RPC" -X POST -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null
}
EOB
        ;;
        C7) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read7() {
    "curl" -s -m 5 "$TIER3_RPC" -X POST -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null
}
EOB
        ;;
        C8) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read8() {
    cu''rl -s -m 5 "$TIER3_RPC" -X POST -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null
}
EOB
        ;;
        C9) ev_mut "$STANDBY" "take_staked_identity() {" before "$m" <<'EOB'
_extra_read9() {
    c\url -s -m 5 "$TIER3_RPC" -X POST -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts"}' 2>/dev/null
}
EOB
        ;;
    esac
    [[ $? -eq 0 ]] || { c5_ok=0; c5_rows="$c5_rows $c:not-applied"; continue; }
    if d1_green "$m"; then c5_ok=0; c5_rows="$c5_rows $c:GREEN"; else c5_rows="$c5_rows $c:red($(d1_scan "$m" | sed -n 2p | sed 's/;$//'))"; fi
done
if [[ $c5_ok -eq 1 ]]; then
    ok "(1c-T5) the panel's T5 evasions and the delta panels' curl spellings, each in a copy of the standby — every one RED:$c5_rows (the 6.3.1 census before fix round 1: C0 red, C1–C4 green; fix round 4's source-line census: C5 and C7–C9 green, C6 red)"
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
# LIMIT (fix round 2 — the delta panel's T4-EPTXT, stated, not hardened): a statement is found by its CLAIM WORDS —
# a restatement worded without them ("no RPC request of any kind", "zero HTTP traffic", "nothing is sent", "no
# outbound connection"), one naming the window differently ("the identity switch"), or one spread over more than
# three lines is not a statement to this scan; the check is on the rule's text where it is stated, not on every
# sentence about the window.
RULE="no network, no alerts; one bounded local veto read allowed"
A8TEXT_AWK='
function norm(s) { gsub(/[#*`>|]/, " ", s); gsub(/[[:space:]]+/, " ", s); return s }
BEGIN { WIN = "(re-?che" "ck|return-0|return 0)"; SI = "set-ide" "ntity"
        GAP = ""; for (k = 0; k < 24; k++) GAP = GAP "[^.;]?"   # up to 24 characters with no . or ; between — spelled out: mawk 1.3.4 panics compiling the {0,24} interval here
        CLAIM = "(^|[^a-z])(zero|no|never|nothing|only|without)[^a-z]" GAP "(network|read|i/o|alert|curl|call)" }
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
# the veto's BASELINE (fix rounds 1-2 — R3, S2): EVERY layer neutered together — the all-neutered control: every
# take-cycle own-head sample R3 and S2 added (attempt_takeover's Gate-2 sample, the R3- and S2-tagged ones) and every
# two-tier split (the fence's, the liveness probe's, the watchdog-elapsed step's) → 6.3.1 as first built (its re-check
# is the ONE sequential sampler call — fix round 3 restored it: nothing to neuter there)
mutate "$STANDBY" '/^attempt_takeover() {/,/^}/s/^    _own_head_sample$/    : r3 sample removed/' "$WORK/s-r3a.sh" \
  && mutate "$WORK/s-r3a.sh" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 1, R3).*$/\1: r3 sample removed/' "$WORK/s-r3b.sh" \
  && mutate "$WORK/s-r3b.sh" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 2, S2.*$/\1: s2 sample removed/' "$WORK/s-r3c.sh" \
  && mutate "$WORK/s-r3c.sh" 's/^\( *\)if \[\[ -n "\$TIER2_RPC" && -n "\$TIER3_RPC" && "\$TIER2_RPC" != "\$TIER3_RPC" \]\]; then$/\1if false; then/' "$WORK/s-nor3.sh"
# the re-check (fix round 3 — the delta panel 2's LB-1/LB-2/AV2-1: fix round 2's concurrent read REMOVED, the 6.3
# build's one sequential call restored): the control is fix round 1's PINNED-FIRST order (DL-1's regression — TIER3
# first when the pair is pinned there, TIER2 read only on its failure), spliced onto the restored line
# (the triple's name spliced in by @LFP@ — run_all's stage (3): no suite dereferences the freshness triple in its text)
PF_R1=$(cat <<'EOS'
    if [[ "${@LFP@:-}" == "T3" \&\& -n "$TIER2_RPC" \&\& -n "$TIER3_RPC" \&\& "$TIER2_RPC" != "$TIER3_RPC" ]]; then s=$(TIER2_RPC="" get_staked_liveness_sample) || s=$(TIER3_RPC="" get_staked_liveness_sample) || s=""; else s=$(get_staked_liveness_sample) || s=""; fi
EOS
)
mutate "$STANDBY" "s/^    s=\$(get_staked_liveness_sample) || s=\"\"\$/${PF_R1//@LFP@/_liveness_first_provider}/" "$WORK/s-pf.sh"
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
# holder's last vote at t = 0..CKI−1 of the spare's grid) and CHECK_INTERVAL 1 / 3 / 5 — not the one phase above
for _mds in 15 0; do for _r in 25 37; do
    case $_r in 25) _sn=5; _sd=2 ;; 37) _sn=37; _sd=10 ;; esac
    for _ci in 1 3 5; do for ((_k = 0; _k < _ci; _k++)); do
        wlaunch "swu_${_mds}_${_r}_${_ci}_$_k" MDS=$_mds SLOT_NUM=$_sn SLOT_DEN=$_sd CKI=$_ci VOTES=0:$_k HORIZON=150
        [[ $_r == 37 ]] && wlaunch "swa_${_mds}_${_r}_${_ci}_$_k" ARMED=1 GATE=1 MDS=$_mds SLOT_NUM=$_sn SLOT_DEN=$_sd CKI=$_ci VOTES=0:$_k HORIZON=190
    done; done
done; done
for _mds in 15 0; do for _ci in 1 3 5; do for ((_k = 0; _k < _ci; _k++)); do   # fix round 2 (CK-9): CHECK_INTERVAL 3 too
    wlaunch "swa_${_mds}_2525_${_ci}_$_k" ARMED=1 GATE=1 MDS=$_mds SLOT_NUM=101 SLOT_DEN=40 CKI=$_ci VOTES=0:$_k HORIZON=200
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
wlaunch r2wiz60   GV=true CKI=3 MDS=15 REFMODE=down REFFROM=60 REFTO=61 HORIZON=200
wlaunch r2r37     SLOT_NUM=37 SLOT_DEN=10 MDS=15 REFMODE=down REFFROM=30 REFTO=31 HORIZON=200
wlaunch r2a37     ARMED=1 GATE=1 SLOT_NUM=37 SLOT_DEN=10 MDS=15 REFMODE=down REFFROM=40 REFTO=41 HORIZON=240
wlaunch r2mds0    MDS=0 REFMODE=down REFFROM=40 REFTO=41 HORIZON=200
# R3 + S2 (the panel's AV-3 worlds: the own confirmed head HOLDS, aligned with the veto, on slow take cycles; AV-6's
# starvation worlds; the delta panel's DAV-1/CK-2 worlds — the gossip advisory's reads, TIER2's at its 15 s bound;
# the baseline ages) — shipped, and every baseline layer (R3, S2) neutered together
for _m in ship nor3; do
    _ws=""; [[ "$_m" != "ship" ]] && _ws="WSCRIPT=$WORK/s-$_m.sh"
    wlaunch "h5gv_$_m" $_ws GV=true T2LAT=5 HOLDFROM=140 HOLDTO=146 HORIZON=320
    wlaunch "h6_$_m"   $_ws T2LAT=6 HOLDFROM=136 HOLDTO=143 HORIZON=320
    wlaunch "h8_$_m"   $_ws T2LAT=8 HOLDFROM=138 HOLDTO=147 HORIZON=320
    wlaunch "hm15_$_m" $_ws T2LAT=7 MDS=15 HOLDFROM=92 HOLDTO=100 HORIZON=320
    wlaunch "hwiz_$_m" $_ws GV=true CKI=3 T2LAT=6 MDS=15 HOLDFROM=98 HOLDTO=105 HORIZON=320
    wlaunch "hd0_$_m"  $_ws T2DOWN=1 T3LAT_ALL=0 HOLDFROM=140 HOLDTO=151 HORIZON=320
    wlaunch "d7_$_m"   $_ws T2DOWN=1 T3LAT_ALL=7 STARVE=300 HORIZON=420
    wlaunch "m15d7_$_m" $_ws T2DOWN=1 T3LAT_ALL=7 MDS=15 STARVE=300 HORIZON=420
    wlaunch "gv15_$_m"  $_ws GV=true GCNLAT_T2=15 GCNLAT_T3=2 GCNONLYADV=1 STARVE=300 HORIZON=420
    wlaunch "gv15w_$_m" $_ws GV=true MDS=15 CKI=3 GCNLAT_T2=15 GCNLAT_T3=2 GCNONLYADV=1 STARVE=300 HORIZON=420
    wlaunch "c3g_$_m"   $_ws GV=true T2LAT=3 T3LAT_ALL=10 HORIZON=320
done
wlaunch hd4_8     T2DOWN=1 T3LAT_ALL=4 HOLDFROM=144 HOLDTO=153 HORIZON=320
# the RETURNING AV-6 starvation (fix round 3) at the shipped defaults (GOSSIP_VERIFY on, CHECK_INTERVAL 5) and the wizard preset
wlaunch d7gv      GV=true CKI=5 T2DOWN=1 T3LAT_ALL=7 STARVE=300 HORIZON=420
wlaunch d7wiz     GV=true CKI=3 MDS=15 T2DOWN=1 T3LAT_ALL=7 STARVE=300 HORIZON=420
wlaunch hd4_7     T2DOWN=1 T3LAT_ALL=4 HOLDFROM=145 HOLDTO=153 HORIZON=320
# fix round 4 (the delta panel 3's TS3-E-UNPINNED, G1): residual 7's cells docs/SAFETY.md states beyond the four above, its threshold as a
# SUM with every LOCAL read at 1 s (the pre-take sample's and the veto's own LOCAL reads are inside the baseline's age: TIER3 4 s is
# taken with the age at exactly 16, 5 and 6 s never), and the operator mitigations README names (TIER2 blanked; a TIER2 that refuses
# at once does not starve) — each pinned to the exact value measured on this build (the 6.3 build takes every starvation cell).
# Fix round 5 (the delta panel 4's CC4-1: TIER2's term is its time to FAILURE, not only a timeout): TIER2 answering an unusable
# (non-canonical) lastVote after 8 s, TIER3 honest after 9 s — never; 8 + 8 — taken, the baseline exactly 16 s old; every LOCAL
# read at 1 s, 8 + 7 — never (red first on the 6.3 build: t190 / t186 / t185, every one taken); and (the delta panel 4's
# CC4-3) the blanked-TIER2 mitigation at the shipped defaults (GOSSIP_VERIFY on), beside its GOSSIP_VERIFY-off rows
R7_CELLS='d6gv|mutation=189,ov_veto=none|GV=true CKI=5 T2DOWN=1 T3LAT_ALL=6 STARVE=300 HORIZON=420
d8gv|mutation=none,ov_veto=197:blind,starve=385|GV=true CKI=5 T2DOWN=1 T3LAT_ALL=8 STARVE=300 HORIZON=420
d9gv|mutation=none,ov_veto=201:blind,starve=368|GV=true CKI=5 T2DOWN=1 T3LAT_ALL=9 STARVE=300 HORIZON=420
d7gv37|mutation=none,ov_veto=173:blind,starve=352|GV=true CKI=5 T2DOWN=1 T3LAT_ALL=7 SLOT_NUM=37 SLOT_DEN=10 STARVE=300 HORIZON=420
d9wiz|mutation=none,ov_veto=157:blind,starve=324|GV=true CKI=3 MDS=15 T2DOWN=1 T3LAT_ALL=9 STARVE=300 HORIZON=420
h7gv|mutation=none,ov_veto=188:blind,starve=380|GV=true CKI=5 T2LAT=10 T3LAT_ALL=7 STARVE=300 HORIZON=420
l1d4|mutation=171,ov_age=16|LOCLAT=1 T2DOWN=1 T3LAT_ALL=4 STARVE=300 HORIZON=420
l1d5|mutation=none,ov_veto=175:blind,starve=380|LOCLAT=1 T2DOWN=1 T3LAT_ALL=5 STARVE=300 HORIZON=420
l1d6|mutation=none,ov_veto=179:blind,starve=371|LOCLAT=1 T2DOWN=1 T3LAT_ALL=6 STARVE=300 HORIZON=420
l1d4gv|mutation=193,ov_age=16|GV=true LOCLAT=1 T2DOWN=1 T3LAT_ALL=4 STARVE=300 HORIZON=420
l1d5gv|mutation=none,ov_veto=199:blind,starve=384|GV=true LOCLAT=1 T2DOWN=1 T3LAT_ALL=5 STARVE=300 HORIZON=420
l1d6gv|mutation=none,ov_veto=204:blind,starve=397|GV=true LOCLAT=1 T2DOWN=1 T3LAT_ALL=6 STARVE=300 HORIZON=420
t2u7|mutation=146,ov_veto=none|T2URL= T3LAT_ALL=7 HORIZON=320
t2u9|mutation=152,ov_veto=none|T2URL= T3LAT_ALL=9 HORIZON=320
t2u6l1|mutation=170,ov_veto=none|T2URL= LOCLAT=1 T3LAT_ALL=6 HORIZON=320
t2u7gv|mutation=153,ov_veto=none|GV=true T2URL= T3LAT_ALL=7 HORIZON=320
t2u9gv|mutation=161,ov_veto=none|GV=true T2URL= T3LAT_ALL=9 HORIZON=320
t2u6l1gv|mutation=159,ov_veto=none|GV=true T2URL= LOCLAT=1 T3LAT_ALL=6 HORIZON=320
t2r7gv|mutation=153,ov_veto=none|GV=true T2BADFROM=0 T2BADTO=99999 T3LAT_ALL=7 HORIZON=320
t2r9gv|mutation=161,ov_veto=none|GV=true T2BADFROM=0 T2BADTO=99999 T3LAT_ALL=9 HORIZON=320
lv8y9gv|mutation=none,ov_veto=190:blind,starve=366|GV=true CKI=5 HOSTILE=lv0 T3MODE=honest T2LAT=8 T3LAT_ALL=9 STARVE=300 HORIZON=420
lv8y8gv|mutation=186,ov_age=16|GV=true CKI=5 HOSTILE=lv0 T3MODE=honest T2LAT=8 T3LAT_ALL=8 STARVE=300 HORIZON=420
lv8y7l1gv|mutation=none,ov_veto=196:blind,starve=378|GV=true CKI=5 LOCLAT=1 HOSTILE=lv0 T3MODE=honest T2LAT=8 T3LAT_ALL=7 STARVE=300 HORIZON=420'
while IFS='|' read -r _n _w _k; do [[ -n "$_n" ]] || continue; wlaunch "r7_$_n" $_k </dev/null; done <<EOF_R7
$R7_CELLS
EOF_R7
# the matrix's youngest tier-answering cell since fix round 3 (TIER3 answering in 10 s, TIER2 4 s, GOSSIP_VERIFY on: 8 s) with an
# aligned 8 s hold (20 slots at 2.5 slots/s — inside the 22-slot budget) and a 7 s one
wlaunch cg4h8     GV=true T2LAT=4 T3LAT_ALL=10 HOLDFROM=143 HOLDTO=152 HORIZON=420
wlaunch cg4h7     GV=true T2LAT=4 T3LAT_ALL=10 HOLDFROM=144 HOLDTO=152 HORIZON=420
for _x in 1 2 3 4 5 6 7 8 9 10; do wlaunch "age_t2_$_x" T2LAT=$_x HORIZON=320; done
wlaunch age_t2_5gv GV=true T2LAT=5 HORIZON=320
for _y in 1 2 3 4 5 6 8 9; do wlaunch "age_d_$_y" T2DOWN=1 T3LAT_ALL=$_y HORIZON=320; done
for _x in 0 1 2 4 5 6 7 8 9; do wlaunch "age_cg_$_x" GV=true T2LAT=$_x T3LAT_ALL=10 HORIZON=320; done
for _x in 0 4 7; do wlaunch "age_c_$_x" T2LAT=$_x T3LAT_ALL=10 HORIZON=320; done
# the NAMED residual (fix round 2, S2): ONE gossip-advisory read of ~15 s (TIER3's, TIER2's answering) before prompt
# fence / re-check reads; TIER2 at 1 / 2 / 3 s — the ages, and a 4 s hold (10 slots) aligned with the TIER2-2 s veto
for _x in 1 2 3; do wlaunch "gadv_$_x" GV=true T2LAT=$_x GCNLAT_T3=15 GCNONLYADV=1 HORIZON=360; done
wlaunch gadv_2h4   GV=true T2LAT=2 GCNLAT_T3=15 GCNONLYADV=1 HOLDFROM=144 HOLDTO=149 HORIZON=360
wlaunch x9np      WSCRIPT="$WORK/s-nopretake.sh" T2LAT=9 HORIZON=320
wlaunch d9np      WSCRIPT="$WORK/s-nopretake.sh" T2DOWN=1 T3LAT_ALL=9 HORIZON=320
# (7f) the re-check's worlds (fix round 3 — U1): DL-1's (the delta panel's, verbatim knobs: the pair pinned on TIER3
# — TIER2 refusing at the fence — TIER2 recovering before the re-check and showing the holder's vote ADVANCED, the
# holder voting again from t140, the spare's own node and TIER3 40 s behind: (a) MDS 0, TIER3 1 s; (b) MDS 15, 3.7
# slots/s, 30 s behind, TIER3 2 s; (c) GOSSIP_VERIFY on; (d) TIER3 3 s), LB-1's (the delta panel 2's: TIER2 hanging at
# every read, TIER3 honest and prompt, the spare 40 / 30 s behind, the holder resuming at t181 / t121 (MDS 15, 3.7) /
# t196 (GOSSIP_VERIFY on)) and LB-2's (DL-1 (a) / (b) / (c) with TIER2 back but lagging 30 / 25 / 30 s) — shipped vs
# fix round 1's pinned-first order; the controls: TIER2 never recovering (DL-1 (a)), TIER2 back 38 s behind (no vantage
# shows the resumption before t178); LB-1's worlds shipped only, beside LB-1's dead holder (the pinned-first order
# takes them one second BEFORE the resumption — another class, not LB-1's)
for _m in ship pf; do
    _ws=""; [[ "$_m" != "ship" ]] && _ws="WSCRIPT=$WORK/s-$_m.sh"
    wlaunch "dl1a_$_m" $_ws MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=honest T2TLAG=0 T3MODE=honest T3TLAG=40 T2BADFROM=0 T2BADTO=167 T3LAT_ALL=1 HORIZON=260
    wlaunch "dl1b_$_m" $_ws MDS=15 SLOT_NUM=37 SLOT_DEN=10 LAG=30 VOTES=0:0,90:-1 T2MODE=honest T2TLAG=0 T3MODE=honest T3TLAG=30 T3LAT_ALL=2 T2BADFROM=0 T2BADTO=109 HORIZON=220
    wlaunch "dl1c_$_m" $_ws GV=true MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=honest T2TLAG=0 T3MODE=honest T3TLAG=40 T2BADFROM=0 T2BADTO=168 T3LAT_ALL=1 HORIZON=260
    wlaunch "dl1d_$_m" $_ws MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=honest T2TLAG=0 T2BADFROM=0 T2BADTO=170 T3LAT_ALL=3 HORIZON=300
    wlaunch "lb2a_$_m" $_ws MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=honest T2TLAG=30 T3MODE=honest T3TLAG=40 T2BADFROM=0 T2BADTO=167 T3LAT_ALL=1 HORIZON=260
    wlaunch "lb2b_$_m" $_ws MDS=15 SLOT_NUM=37 SLOT_DEN=10 LAG=30 VOTES=0:0,90:-1 T2MODE=honest T2TLAG=25 T3MODE=honest T3TLAG=30 T3LAT_ALL=2 T2BADFROM=0 T2BADTO=109 HORIZON=220
    wlaunch "lb2c_$_m" $_ws GV=true MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=honest T2TLAG=30 T3MODE=honest T3TLAG=40 T3LAT_ALL=1 T2BADFROM=0 T2BADTO=168 HORIZON=260
done
wlaunch lb1a      MDS=0 LAG=40 VOTES=0:0,181:-1 T2DOWN=1 T3MODE=honest T3TLAG=0 HORIZON=300
wlaunch lb1b      MDS=15 SLOT_NUM=37 SLOT_DEN=10 LAG=30 VOTES=0:0,121:-1 T2DOWN=1 T3MODE=honest T3TLAG=0 HORIZON=260
wlaunch lb1c      GV=true MDS=0 LAG=40 VOTES=0:0,196:-1 T2DOWN=1 T3MODE=honest T3TLAG=0 HORIZON=320
wlaunch dl1a_ctl  MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=honest T2TLAG=0 T3MODE=honest T3TLAG=40 T2BADFROM=0 T2BADTO=999 T3LAT_ALL=1 HORIZON=260
wlaunch lb2_38    MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=honest T2TLAG=38 T3MODE=honest T3TLAG=40 T2BADFROM=0 T2BADTO=167 T3LAT_ALL=1 HORIZON=260
wlaunch lb1dead   MDS=0 LAG=40 VOTES=0:0 T2DOWN=1 T3MODE=honest T3TLAG=0 HORIZON=300
# the MIRROR residual (pre-existing on the 6.3 build and the first 6.3.1 build; fix round 2's concurrent read closed it
# and was removed in fix round 3): the pair pinned on TIER2 while it splices or lags, TIER3 honest and showing the
# advance — the one sequential call never reads TIER3 while TIER2 answers; at the harness defaults and at the shipped
# defaults (GOSSIP_VERIFY on, CHECK_INTERVAL 5; 2.5 and 3.7 slots/s; the wizard preset); the dead-holder controls
for _mw in "symsp|MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=splice" "symlag|MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=honest T2TLAG=40" \
           "symsp15|MDS=15 SLOT_NUM=37 SLOT_DEN=10 LAG=30 VOTES=0:0,90:-1 T2MODE=splice" "symdead|MDS=0 LAG=40 VOTES=0:0 T2MODE=splice" \
           "mirdef|GV=true CKI=5 MDS=0 LAG=40 VOTES=0:0,140:-1 T2MODE=splice" "mirdef37|GV=true CKI=5 MDS=0 SLOT_NUM=37 SLOT_DEN=10 LAG=30 VOTES=0:0,120:-1 T2MODE=splice" \
           "mirwiz|GV=true MDS=15 CKI=3 LAG=40 VOTES=0:0,100:-1 T2MODE=splice" "mirwiz37|GV=true MDS=15 CKI=3 SLOT_NUM=37 SLOT_DEN=10 LAG=30 VOTES=0:0,90:-1 T2MODE=splice" \
           "mirwizdead|GV=true MDS=15 CKI=3 LAG=40 VOTES=0:0 T2MODE=splice"; do
    wlaunch "${_mw%%|*}" ${_mw#*|} T3MODE=honest T3TLAG=0 HORIZON=260
done
# fix round 4 (the delta panel 3's RM-4 / CC3-4): residual 6's exposure is up to the spare's lag, and the node's own
# --health-check-slot-distance bounds that lag at the take cycle's Tier-1 check (Tier-1 is the node's health verdict since
# 6.3.1; a lag that grows during a slow take cycle is not bounded by it) — the mirror world at the
# shipped defaults over the lag, the resumption instant and the distance: "name|fields|knobs"
R6_CELLS='r125|mutation=165,hvafter=1|LAG=40 VOTES=0:0,125:-1
r124|mutation=none,ov_veto=165:voting|LAG=40 VOTES=0:0,124:-1
l50|mutation=175,hvafter=1|LAG=50 VOTES=0:0,140:-1
l51r129|mutation=180,hvafter=1|LAG=51 VOTES=0:0,129:-1
l52|mutation=none,ov_veto=none|LAG=52 VOTES=0:0,140:-1
d64l25|mutation=150,hvafter=1|DIST=64 LAG=25 VOTES=0:0,140:-1
d64l25r125|mutation=150,hvafter=1|DIST=64 LAG=25 VOTES=0:0,125:-1
d64l26|mutation=none,ov_veto=none|DIST=64 LAG=26 VOTES=0:0,140:-1
d38l15|mutation=140,hvafter=1|DIST=38 LAG=15 VOTES=0:0,140:-1
d38l15r125|mutation=140,hvafter=1|DIST=38 LAG=15 VOTES=0:0,125:-1
d38l16|mutation=none,ov_veto=none|DIST=38 LAG=16 VOTES=0:0,140:-1'
while IFS='|' read -r _n _w _k; do [[ -n "$_n" ]] || continue; wlaunch "r6_$_n" GV=true CKI=5 MDS=0 T2MODE=splice T3MODE=honest T3TLAG=0 HORIZON=320 $_k </dev/null; done <<EOF_R6
$R6_CELLS
EOF_R6
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
# LIMIT (fix round 2 — the delta panel's T4-EPTXT, stated, not hardened): a write is found by the spellings above —
# an indexed write (FIRST_DELINQUENT_TIME[0]=0, which zeroes the scalar in bash), a quoted `unset "VAR"`, or
# `printf -v "$name"` over a variable holding the name closes an episode unseen (eval and `read <<<` are red); a
# new close site so spelled would need the behavior checks below to catch it.
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
if [[ "$(wf t2d mutation)" == "150" && "$(wf t2d_np mutation)" == "150" && "$(wf t2d_l6 mutation)" == "168" && "$(wf t2d_l7 mutation)" == "none" && "$(wf t2d_l7 ov_veto)" == "171:blind" \
      && "$(wf x9np mutation)" == "none" && "$(wf x9np ov_veto)" == "148:blind" && "$(wf d9np mutation)" == "none" && "$(wf d9np ov_veto)" == "177:blind" \
      && "$(wf age_t2_9 mutation)" == "148" && "$(wf age_t2_9 ov_age)" == "9" && "$(wf age_d_9 mutation)" == "none" && "$(wf age_d_9 ov_veto)" == "177:blind" ]]; then
    ok "(4b-pretake) the PRE-TAKE own-head sample (take_staked_identity's head, before the re-check), after fix round 3 (the re-check is the 6.3 build's one sequential call again): a dead holder behind a dead TIER2 is taken at t150 with or without it (the sample between the fence's TIER2 timeout and its TIER3 read is 10 s old at the veto); TIER2 down + TIER3 6 s late → t168 (fix round 2: t162; fix round 1: t158; the first 6.3.1 build: t168); 7 s late → NEVER, every veto BLIND (t171 on) — the RETURNING AV-6 starvation: the pre-take sample's LOCAL read, the re-check's TIER2 timeout and TIER3's read, and the veto's LOCAL read outlast OWN_HEAD_H with no sample allowed inside the span (fix round 2: t164; fix round 1: t161; the first 6.3.1 build: never). It is load-bearing where ONE read spans the re-check's own window: TIER2 answering in 9 s (the fence's read and the re-check's, each 9 s) → the baseline is this sample (9 s old), taken t148; removed → every veto BLIND, never taken. TIER2 down + TIER3 9 s: never, with it or without it (BLIND t177 — the starvation; fix round 2 took it at t168)"
else
    bad "(4b-pretake) t2down=$(wr t2d) :: no-pretake=$(wr t2d_np) :: t3+6=$(wr t2d_l6) :: t3+7=$(wr t2d_l7) :: t2@9 no-pretake=$(wr x9np) :: t2down+t3@9 no-pretake=$(wr d9np) :: t2@9=$(wf age_t2_9 mutation)/$(wf age_t2_9 ov_age) t2down+t3@9=$(wf age_d_9 mutation)/$(wf age_d_9 ov_age)"
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
m_a15_37=$(swmin a 15 37 1 3 5); m_a0_37=$(swmin a 0 37 1 3 5); m_a15_2525=$(swmin a 15 2525 1 3 5); m_a0_2525=$(swmin a 0 2525 1 3 5)
if [[ "$m_u15_25" == "79" && "$m_u15_37" == "73" && "$m_u0_25" == "125" && "$m_u0_37" == "104" && "$m_a15_37" == "119" && "$m_a0_37" == "150" && "$m_a15_2525" == "125" && "$m_a0_2525" == "170" ]]; then
    ok "(6-min) THE SPARE'S EARLIEST, measured as the minimum over the read phase and CHECK_INTERVAL 1 / 3 / 5 (the panel's CC-5/F6 — the default phase above is not the earliest): un-armed take 79 s / 73 s at MAX_DELINQUENT_SLOTS=15 and 125 s / 104 s at 0 (2.5 / 3.7 slots/s); armed watchdog-elapsed MINT 119 s at 15 and 150 s at 0 (3.7), 125 s and 170 s at 2.525 slots/s (CHECK_INTERVAL 1 / 3 / 5); at exactly 2.5 none on a SMOOTH head (not swept here — an anchor hold mints: 126 / 171 s, docs/SAFETY.md 'Slot time') — the numbers docs/SAFETY.md's D6 table holds the holder column (test_d6_holder) against"
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
r1_row l1a 123 63; r1_row l1b25 135 75; r1_row l1b37 130 70; r1_row l1c 155 91; r1_row l1d 171 71 armed; r1_row l1lag 135 75
for w in l1e l1f l1dres; do [[ "$(wf "$w" mutation)" == "none" && "$(wf "$w" emint)" == "none" ]] || { r1_ok=0; r1_why="$r1_why [$w taken: $(wr "$w" | cut -c1-200)]"; }; done
if [[ $r1_ok -eq 1 ]]; then
    ok "(7a) RED FIRST (R1 — the panel's L1, BLOCKER): at MAX_DELINQUENT_SLOTS=15 a holder voting INTO the open episode — each vote 20 slots late ('delinquent' by the latency test, agave-current), or on-time votes whose not-delinquent window falls between two reads — was folded into the own-bank maximum with no D2 stamp; the 6.3.1 build took (a) t75 (25 s after the last vote), (b) t75 / t70 at 2.5 / 3.7 slots/s (13 s / 9 s), (c) t108 (28 s), the lag-62 world t75 (13 s), and armed (d) minted + took t117 (55 s < W+B). Now each own-bank lastVote ADVANCE inside the episode stamps D2 and no take lands inside TAKEOVER_DELAY of the last one (no mint inside the floor, armed): (a) t123 = 63 + 60, (b) t135 / t130, (c) t155, the last advance t91 (fix round 1: t154 / t90 — this world's LOCAL reads take 1 s each, and fix round 2's added own-head samples (S2) move it by one second), lag-62 t135, (d) mint + take t171 = 71 + 100; the holder silent at every take (hvafter=0). Resuming after the would-be take — (e) 2.5 slots/s, (f) 3.7, (dres) armed: the 6.3.1 build took each (t75 / t108 / t117) with the holder voting at the mutation; now none is taken"
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
    ok "(7a-cost) NAMED COST of the agave-current rule (R1), MEASURED — a DEAD holder at MAX_DELINQUENT_SLOTS=15: unchanged at 2.5 and 3.7 slots/s (t80 / t75, the D6 rows) and at 1.35 slots/s at CHECK_INTERVAL 5 (t100 — the only cadence this case measures: the threshold depends on the cadence, and at CHECK_INTERVAL 1 or 3 1.35 slots/s moves, docs/SAFETY.md; the text's cadence-free "below ~1.35 slots/s" was retracted in fix round 2 and survived here until fix round 3 — the delta panel 2's CKB-8); at 1.2 and 1.0 slots/s the dead holder is still inside agave's 128 slots at the first take, the veto reads it VOTING once and the take moves by one TAKEOVER_DELAY: 1.2 slots/s t100 → t160, 1.0 slots/s t110 → t170 (the 6.3.1 build: t100 / t110). What it buys there, measured: the same 1.2 slots/s holder RESUMING at t101 — the rule neutered takes at t100 with the holder voting at the mutation, shipped holds; and the (e)-shaped world at 1.2 slots/s (the holder back at t150) — neutered takes at t149 into the resume, shipped holds"
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
# (7c) R3 + S2 — the veto's baseline on slow take cycles
r3_ok=1; r3_why=""
for spec in h5gv:145:15 h6:142:12 h8:146:16 hm15:99:14 hwiz:104:12; do
    w=${spec%%:*}; rest=${spec#*:}; m=${rest%%:*}; age=${rest#*:}
    [[ "$(wf "${w}_ship" mutation)" == "$m" && "$(wf "${w}_ship" ov_veto)" == "none" && "$(wf "${w}_ship" ov_age)" == "$age" ]] || { r3_ok=0; r3_why="$r3_why [${w}: $(wr "${w}_ship" | cut -c1-200)]"; }
    [[ "$(wf "${w}_nor3" ov_veto)" == *":blind" && $(wf "${w}_nor3" mutation) -ge $(( m + 60 )) ]] || { r3_ok=0; r3_why="$r3_why [${w} all-neutered not blind: $(wr "${w}_nor3" | cut -c1-200)]"; }
done
# an 11 s hold (27 slots — BEYOND the 22-slot budget) with TIER2 down: BLIND on both (the re-check waits out TIER2's
# 10 s timeout — the one sequential call, restored in fix round 3; round 1's pinned-first re-check took it at t140)
[[ "$(wf hd0_ship ov_veto)" == "150:blind" && "$(wf hd0_ship mutation)" == "252" && "$(wf hd0_ship ov_age)" == "10" && "$(wf hd0_nor3 ov_veto)" == "150:blind" ]] || { r3_ok=0; r3_why="$r3_why [hd0: $(wr hd0_ship | cut -c1-160) / $(wr hd0_nor3 | cut -c1-120)]"; }
[[ "$(wf d7_ship mutation)" == "none" && "$(wf d7_ship ov_veto)" == "171:blind" && "$(wf d7_ship starve)" == "380" && "$(wf m15d7_ship mutation)" == "none" && "$(wf m15d7_ship ov_veto)" == "126:blind" && "$(wf m15d7_ship starve)" == "335" \
   && "$(wf d7_nor3 mutation)" == "none" && "$(wf d7_nor3 ov_veto)" == "171:blind" && "$(wf m15d7_nor3 mutation)" == "none" \
   && "$(wf d7gv mutation)" == "none" && "$(wf d7gv ov_veto)" == "193:blind" && "$(wf d7gv starve)" == "372" && "$(wf d7wiz mutation)" == "none" && "$(wf d7wiz ov_veto)" == "149:blind" && "$(wf d7wiz starve)" == "328" ]] || { r3_ok=0; r3_why="$r3_why [starvation (the returning AV-6 residual): d7=$(wf d7_ship mutation)/$(wf d7_ship ov_veto)/$(wf d7_ship starve) m15d7=$(wf m15d7_ship mutation)/$(wf m15d7_ship ov_veto)/$(wf m15d7_ship starve) defaults=$(wf d7gv mutation)/$(wf d7gv ov_veto)/$(wf d7gv starve) wizard=$(wf d7wiz mutation)/$(wf d7wiz ov_veto)/$(wf d7wiz starve) :: neutered $(wf d7_nor3 mutation)/$(wf m15d7_nor3 mutation)]"; }
[[ "$(wf gv15_ship mutation)" == "142" && "$(wf gv15_ship ov_age)" == "2" && "$(wf gv15w_ship mutation)" == "98" && "$(wf gv15_nor3 mutation)" == "none" && "$(wf gv15_nor3 starve)" == "374" && "$(wf gv15w_nor3 mutation)" == "none" && "$(wf gv15w_nor3 starve)" == "330" ]] || { r3_ok=0; r3_why="$r3_why [advisory pair: gv15=$(wf gv15_ship mutation)/$(wf gv15_ship ov_age) wiz=$(wf gv15w_ship mutation) :: neutered $(wf gv15_nor3 mutation)/$(wf gv15_nor3 starve) wiz $(wf gv15w_nor3 mutation)/$(wf gv15w_nor3 starve)]"; }
[[ "$(wf c3g_ship ov_age)" == "16" && "$(wf c3g_ship mutation)" == "147" && "$(wf c3g_nor3 ov_age)" == "3" && "$(wf c3g_nor3 mutation)" == "147" ]] || { r3_ok=0; r3_why="$r3_why [TIER3 at 10 s: $(wr c3g_ship | cut -c1-120) / neutered $(wf c3g_nor3 ov_age)/$(wf c3g_nor3 mutation)]"; }
if [[ $r3_ok -eq 1 ]]; then
    ok "(7c) RED FIRST (R3 — the panel's AV-3; S2 — the delta panel's DAV-1/CK-2/DAV-2): a HEALTHY confirmed-head hold inside the 22-slot budget, aligned with the veto, on a slow take cycle — 6.3.1 as first built (every baseline layer neutered together: every R3/S2 sample and every two-tier split) → BLIND and +85..+93 s: GOSSIP_VERIFY on, TIER2 5 s, a 6 s hold t145 → t230; TIER2 6 s, a 7 s hold t142 → t229; TIER2 8 s, a 9 s hold (22 slots, the budget's edge) t146 → t239; MAX_DELINQUENT_SLOTS=15, TIER2 7 s, an 8 s hold t99 → t190; the wizard preset (TIER2 6 s, a 7 s hold) t104 → t195; the gossip advisory's pair unbracketed (TIER2's read at its 15 s bound, TIER3's 2 s) never taken — starvation page t374 (the wizard preset: t330); TIER3 answering in 10 s + TIER2 3 s, GOSSIP_VERIFY on: a 3 s baseline. Shipped: every hold world takes on time (t145 / t142 / t146 / t99 / t104, baselines 15 / 12 / 16 / 14 / 12 s), the advisory pair takes at t142 / t98 (baseline 2 s: the named residual, (7c-age)), TIER3 answering in 10 s + TIER2 3 s → 16 s, taken t147 (fix round 2: 13 s at t154 — its concurrent re-check waited out TIER3's timeout); an 11 s hold (27 slots, BEYOND the budget) with TIER2 down stays BLIND (t150 → t252, as 6.3.1 first built; fix round 1 took it at t140). NOT closed — the RETURNING residual (AV-6; docs/SAFETY.md residual 7): TIER2 down + TIER3 7 s late is never taken, every veto BLIND (t171; MAX_DELINQUENT_SLOTS=15 t126; at the shipped defaults — GOSSIP_VERIFY on — t193; the wizard preset t149), the starvation page at t380 / t335 / t372 / t328 (the 6.3 build takes them at t171 / t126 / t193 / t149 — an availability regression of 6.3.1) — as on the first 6.3.1 build: the pre-take sample's age at the veto (its LOCAL read, TIER2's 10 s timeout, then TIER3, then the veto's LOCAL read) outlasts OWN_HEAD_H and no sample may sit inside the span (fix round 1 read TIER3 alone and took t161; fix round 2's concurrent read took t164 — both removed, each took a voting holder elsewhere: DL-1, LB-1/LB-2)"
else
    bad "(7c) R3/S2:$r3_why"
fi
a_ok=1; a_got=""
for spec in age_t2_1:16 age_t2_2:16 age_t2_3:16 age_t2_4:16 age_t2_5:16 age_t2_5gv:15 age_t2_6:12 age_t2_7:14 age_t2_8:16 age_t2_9:9 age_t2_10:10 \
            t2d:10 age_d_1:12 age_d_2:14 age_d_3:16 age_d_4:14 age_d_5:15 age_d_6:16 \
            age_cg_0:16 age_cg_1:16 age_cg_2:16 c3g_ship:16 age_cg_4:8 age_cg_5:10 age_cg_6:12 age_cg_7:14 age_cg_8:16 age_cg_9:9 age_c_0:16 age_c_4:16 age_c_7:14 \
            gadv_1:2 gadv_2:4 gadv_3:6; do
    w=${spec%%:*}; want=${spec#*:}; got=$(wf "$w" ov_age); a_got="$a_got $w=$got"
    [[ "$got" == "$want" && "$(wf "$w" ov_veto)" == "none" ]] || a_ok=0
done
for spec in d7_ship:171 age_d_8:174 age_d_9:177; do   # TIER2 down, TIER3 7 / 8 / 9 s: no baseline at all — residual 7
    w=${spec%%:*}; want=${spec#*:}; a_got="$a_got $w=$(wf "$w" mutation)/$(wf "$w" ov_veto)"
    [[ "$(wf "$w" mutation)" == "none" && "$(wf "$w" ov_veto)" == "$want:blind" ]] || a_ok=0
done
if [[ $a_ok -eq 1 && "$(wf hd4_8 mutation)" == "162" && "$(wf hd4_8 ov_veto)" == "none" && "$(wf hd4_7 mutation)" == "162" && "$(wf gadv_2h4 ov_veto)" == "148:blind" && "$(wf gadv_2h4 mutation)" == "233" \
      && "$(wf cg4h8 ov_veto)" == "151:blind" && "$(wf cg4h8 mutation)" == "241" && "$(wf cg4h7 mutation)" == "151" && "$(wf cg4h7 ov_veto)" == "none" ]]; then
    ok "(7c-age) the baseline age at the veto, MEASURED here at MAX_DELINQUENT_SLOTS 0, CHECK_INTERVAL 5, 2.5 slots/s (the docs quote these; fix round 3's 512-cell sweep — MAX_DELINQUENT_SLOTS 0/15 × CHECK_INTERVAL 5/3 × 2.5/3.7 slots/s × GOSSIP_VERIFY off/on — found every age identical across the first three axes): TIER2 answering in 0–5 s → 16 s (15 at 5 s with GOSSIP_VERIFY on), 6 → 12, 7 → 14, 8 → 16, 9 → 9, at its 10 s bound → 10; TIER2 down and TIER3 in 0..6 s → 10 / 12 / 14 / 16 / 14 / 15 / 16, and at 7 / 8 / 9 s NO baseline (prompt LOCAL reads) — every veto BLIND (t171 / t174 / t177), never taken: residual 7, the first 6.3.1 build's starvation (the 6.3 build takes t171 / t174 / t177), back since fix round 3; TIER3 answering in 10 s (its -m 10 reads timing out, its -m 15 reads answering), TIER2 in x s → GOSSIP_VERIFY on 16 for x ≤ 3, 8 / 10 / 12 / 14 / 16 / 9 at x = 4..9 (off: 16 at 0 and 4, 14 at 7) — 8–16 s over the tier-answering matrix. The 8 s cell (TIER3 at 10 s, TIER2 4 s, GOSSIP_VERIFY on — fix round 2: 14 s) vetoes an aligned 8 s hold (20 slots, INSIDE the 22-slot budget): BLIND t151, taken t241 (+90 s); a 7 s hold is taken on time (t151). Fix round 1's residual cell (TIER2 down + TIER3 4 s: an 8 s baseline, an 8 s hold BLIND t152 → t254) is 14 s: taken t162 with that hold (fix round 2: t158). NAMED RESIDUAL (the gossip advisory): ONE advisory read of ~15 s (TIER3's) with TIER2 at 1 / 2 / 3 s → 2 / 4 / 6 s, and a 4 s hold (10 slots, inside the budget) aligned with the veto → BLIND t148, taken t233 (+85 s) — the reviewer's options in attempt_takeover's S2 note"
else
    bad "(7c-age)$a_got :: hd4 8s-hold=$(wf hd4_8 mutation)/$(wf hd4_8 ov_veto) 7s-hold=$(wf hd4_7 mutation) :: advisory 4s-hold=$(wf gadv_2h4 mutation)/$(wf gadv_2h4 ov_veto)"
fi
# (7c-r7) fix round 4 (the delta panel 3's TS3-E-UNPINNED; G1): the table R7_CELLS above, every field exact
r7_ok=1; r7_why=""
while IFS='|' read -r _n _w _k; do
    [[ -n "$_n" ]] || continue
    for _f in ${_w//,/ }; do [[ "$(wf "r7_$_n" "${_f%%=*}")" == "${_f#*=}" ]] || { r7_ok=0; r7_why="$r7_why [$_n: ${_f%%=*}=$(wf "r7_$_n" "${_f%%=*}") want ${_f#*=}]"; }; done
    [[ "$(wf "r7_$_n" hvafter)" == "1" ]] && { r7_ok=0; r7_why="$r7_why [$_n: taken with the holder voting]"; }
done <<EOF_R7
$R7_CELLS
EOF_R7
if [[ $r7_ok -eq 1 ]]; then
    ok "(7c-r7) residual 7 (docs/SAFETY.md — AV-6's starvation: the first 6.3.1 build's, an availability regression against the 6.3 build, which takes every one of these dead holders) pinned cell by cell (fix round 4 — the delta panel 3's TS3-E-UNPINNED): at the shipped defaults (GOSSIP_VERIFY on, CHECK_INTERVAL 5) TIER2 timing out with TIER3 6 s late is taken (t189), 8 / 9 s never (BLIND t197 / t201, the starvation page t385 / t368), 3.7 slots/s 7 s never (t173 / t352), the wizard preset 9 s never (t157 / t324), TIER2 answering at its bound (its -m 10 reads timing out) 7 s never (t188 / t380). The threshold is a SUM — TIER2's time to FAILURE + TIER3's latency + the pre-take sample's and the veto's own LOCAL reads > OWN_HEAD_H: with every LOCAL read at 1 s TIER3 4 s is taken with the baseline exactly 16 s old (t171; GOSSIP_VERIFY on t193) and 5 / 6 s are never taken (BLIND t175 / t179, pages t380 / t371; on: t199 / t204, t384 / t397); a TIER2 that fails LATE with an unusable answer (a non-canonical lastVote after 8 s, fix round 5 — the delta panel 4's CC4-1) with TIER3 9 s never (BLIND t190, page t366), 8 s taken with the baseline exactly 16 s old (t186), and with every LOCAL read at 1 s TIER3 7 s never (t196 / t378). The mitigations: TIER2_RPC blanked → at the defaults TIER3 7 / 9 s taken t153 / t161 (1 s LOCAL reads and TIER3 6 s: t159), GOSSIP_VERIFY off t146 / t152 (t170); a TIER2 that REFUSES at once does not starve (TIER3 7 / 9 s at the defaults: t153 / t161). No cell is taken with the holder voting (every holder here is dead)"
else
    bad "(7c-r7)$r7_why"
fi
# (7f) the re-check (fix round 3 — U1: fix round 2's concurrent read and fix round 1's pinned-first order REMOVED, the
# 6.3 build's one sequential call restored): DL-1's, LB-1's and LB-2's worlds never taken; the mirror residual named
s1_ok=1; s1_why=""
for spec in dl1a:168 dl1b:111 dl1c:169 dl1d:174 lb2a:168 lb2b:111 lb2c:169; do
    w=${spec%%:*}; m=${spec#*:}
    [[ "$(wf "${w}_ship" mutation)" == "none" && "$(wf "${w}_ship" end)" == "horizon" ]] || { s1_ok=0; s1_why="$s1_why [${w} shipped TOOK: $(wr "${w}_ship" | cut -c1-160)]"; }
    [[ "$(wf "${w}_pf" mutation)" == "$m" && "$(wf "${w}_pf" hvafter)" == "1" ]] || { s1_ok=0; s1_why="$s1_why [${w} pinned-first: $(wr "${w}_pf" | cut -c1-160)]"; }
done
for w in lb1a lb1b lb1c; do
    [[ "$(wf "$w" mutation)" == "none" && "$(wf "$w" end)" == "horizon" ]] || { s1_ok=0; s1_why="$s1_why [${w} shipped TOOK: $(wr "$w" | cut -c1-160)]"; }
done
[[ "$(wf lb1dead mutation)" == "190" && "$(wf lb1dead hvafter)" == "0" ]] || { s1_ok=0; s1_why="$s1_why [LB-1 dead control: $(wr lb1dead | cut -c1-160)]"; }
[[ "$(wf dl1a_ctl mutation)" == "168" && "$(wf dl1a_ctl hvafter)" == "1" && "$(wf lb2_38 mutation)" == "177" && "$(wf lb2_38 hvafter)" == "1" ]] || { s1_ok=0; s1_why="$s1_why [controls: never-recovering $(wr dl1a_ctl | cut -c1-120) / 38 s behind $(wr lb2_38 | cut -c1-120)]"; }
for spec in symsp:165 symlag:165 symsp15:105 mirdef:165 mirdef37:135 mirwiz:120 mirwiz37:105; do
    w=${spec%%:*}; m=${spec#*:}
    [[ "$(wf "$w" mutation)" == "$m" && "$(wf "$w" hvafter)" == "1" ]] || { s1_ok=0; s1_why="$s1_why [mirror ${w}: $(wr "$w" | cut -c1-160)]"; }
done
[[ "$(wf symdead mutation)" == "165" && "$(wf symdead hvafter)" == "0" && "$(wf mirwizdead mutation)" == "120" && "$(wf mirwizdead hvafter)" == "0" ]] || { s1_ok=0; s1_why="$s1_why [mirror dead controls: $(wf symdead mutation)/$(wf mirwizdead mutation)]"; }
if [[ $s1_ok -eq 1 ]]; then
    ok "(7f) RED FIRST (the delta panel's DL-1 and the delta panel 2's LB-1 / LB-2, BLOCKERS) — the re-check is the 6.3 build's ONE sequential call again (fix round 3): DL-1's worlds (the pair pinned on TIER3, TIER2 recovering before the re-check and showing the holder's vote ADVANCED): fix round 1's pinned-first order TOOK a voting holder — (a) t168, (b) MAX_DELINQUENT_SLOTS=15 at 3.7 slots/s t111, (c) GOSSIP_VERIFY on t169, (d) t174, 28 / 21 / 29 / 34 s into its voting; shipped never, as on the 6.3 build. LB-2's (DL-1 (a) / (b) / (c) with TIER2 back but 30 / 25 / 30 s behind): pinned-first t168 / t111 / t169 (fix round 2's concurrent read took the same, 21-29 s into the voting — the delta panel 2's measurement); shipped never (the flip abort re-pins onto TIER2, whose next verdict shows the vote). LB-1's (TIER2 hanging at every read, TIER3 honest and prompt, the spare 40 / 30 s behind, the holder resuming at t181 / t121 (MAX_DELINQUENT_SLOTS=15, 3.7) / t196 (GOSSIP_VERIFY on)): shipped never — TIER3 is read after TIER2's timeout and shows the vote (fix round 2's concurrent read took them at t190 / t130 / t205, 9 s into the voting — the delta panel 2's measurement, on the per-branch clock this round removes); the dead-holder control t190. Controls: TIER2 never recovering → t168; TIER2 back 38 s behind → t177 on the 6.3 build and shipped alike (no vantage shows the resumption before t178: residual 2's composition). The RETURNING residual, named (docs/SAFETY.md residual 6 — pre-existing on the 6.3 build and the first 6.3.1 build; fix round 2's concurrent read closed it and regressed LB-1 / LB-2): the pair pinned on TIER2 while it splices or lags, TIER3 honest and showing the advance — TIER3 is not read while TIER2 answers: taken t165 / t165, 25 s into the voting (the holder resuming at t140; a resumption anywhere inside the spare's lag before the take is taken too — the exposure is up to that lag), MAX_DELINQUENT_SLOTS=15 at 3.7 t105 (15 s); at the shipped defaults (GOSSIP_VERIFY on, CHECK_INTERVAL 5) t165 (25 s), 3.7 slots/s t135 (15 s), the wizard preset t120 (20 s), at 3.7 t105 (15 s) — each only while the spare's own replay lag also hides the resumption (40 / 30 s here); the dead-holder controls t165 / t120"
else
    bad "(7f):$s1_why"
fi
# (7f-r6) fix round 4 (the delta panel 3's RM-4 / CC3-4): the table R6_CELLS above, every field exact
r6_ok=1; r6_why=""
while IFS='|' read -r _n _w _k; do
    [[ -n "$_n" ]] || continue
    for _f in ${_w//,/ }; do [[ "$(wf "r6_$_n" "${_f%%=*}")" == "${_f#*=}" ]] || { r6_ok=0; r6_why="$r6_why [$_n: ${_f%%=*}=$(wf "r6_$_n" "${_f%%=*}") want ${_f#*=}]"; }; done
done <<EOF_R6
$R6_CELLS
EOF_R6
if [[ $r6_ok -eq 1 ]]; then
    ok "(7f-r6) residual 6 (docs/SAFETY.md — the mirror world, the 6.3 build's own) pinned over the lag, the resumption instant and the distance, at the shipped defaults (GOSSIP_VERIFY on, CHECK_INTERVAL 5; TIER2 splicing, TIER3 honest): the exposure is up to the spare's lag — 40 s behind, a resumption at t125 is taken at t165, 40 s into its voting, one at t124 reaches the lagging bank (VETO voting at t165); 50 s behind (125 slots) the t140 resumption is taken at t175, 51 s behind (127.5 slots, the most agave's default distance of 128 admits) a t129 resumption at t180, 51 s into it; 52 s behind reads behind and never takes. The node's own --health-check-slot-distance bounds the lag at the take cycle's Tier-1 check (Tier-1 is its health verdict since 6.3.1; a constant lag here): at 64 slots a 25 s lag takes the t140 / t125 resumptions at t150 (10 / 25 s in), a 26 s lag never takes; at 38 slots a 15 s lag takes both at t140 (0 / 15 s in), a 16 s lag never takes"
else
    bad "(7f-r6)$r6_why"
fi
# (7g) S2 — N-is-all over the take cycle's EXTERNAL reads (fix round 2 — the delta panel's DAV-1/CK-2 and T5-UNPINNED's
# class; on bash's own parse since fix round 5; its events from the parse's commands and structure since fix round 6 —
# the delta panel 5's TS5-VERBATIM-CODE / CLM5-1 / CLM5-2 / TS5-7G-SAMPLE-TOKEN). It reads bp_parse's records of each
# daemon — every simple command bash runs, wherever it runs it (a command substitution, a $((cmd) ), the $( ) / backticks
# of an unquoted here-document body; each with its level, subshell depth and the operators around it), and the structure
# (if / case / loops / { } groups, and whether a compound command is a pipeline element or a background job) — and checks:
# walking each take-cycle function's statements in order, every external read has an own-head sample since the previous
# external read.
#   READS, from every command of the walked function (a read runs whatever encloses it): a curl command — LOCAL when its
# URL word is exactly "$LOCAL_RPC" and its other words only -s, -m N, -X M, -H H, -d D (a gap an external read after it
# must see a sample past), else external; the liveness sampler; a call to a function whose first read its CALLER must
# have sampled for (C: the confirm, TIER2's / TIER3's delinquency reads, the fence, the re-check) — a read; a call to a
# function that samples before each of its own reads (S: the gossip advisory, peer_has_relinquished,
# take_staked_identity) — a read that brings its sample; a LOCAL-set function — a gap.
#   A SAMPLE counts only as a statement of the walked function run in its own shell: _own_head_sample its EFFECTIVE command
# word (not an argument, not a string; not behind a `command` or `builtin` prefix — command skips the function lookup,
# builtin refuses a non-builtin: bpcmd reports the prefix), at the function's own level — not inside a command
# substitution, a subshell, a pipeline, a background job or a compound command that is one (the ring write is lost there),
# not the right operand of && / || (it may not run).
#   The STRUCTURE is walked as bash runs it: if / else / fi branches apart and merged; each case arm from the state the
# case starts in, merged at esac with the no-match path unless an arm is `*)`; a loop body as run zero or more times (merged
# with the path that skips it); a compound command that is the operand of && / || merged with the path that skips it. A
# break or continue run in the function's own shell, whatever operator precedes it (a `cond && break`, a `cmd || continue`
# — the daemons' own tier-loop idiom — or none), merges its path into the exit of the loop it leaves — the Nth enclosing
# one for `break N` / `continue N` (an N deeper than the loops around it in the function's own shell, or one this census
# cannot read, is red) — and ENDS the path only when it is unconditional (not an && / || right operand); a continue is
# walked as leaving the loop (the body run again is the LIMIT's "a read a loop repeats"). A return / exit run in the
# function's own shell ends its path (a `cmd || return` is conditional: its path goes on).
#   A function's own first read is covered by its caller for the C functions (start clean) and needs a sample for the S
# functions and attempt_takeover (start dirty: armed, the watchdog-elapsed evaluation's reads precede it in the cycle;
# _elapsed_step itself follows the main loop's per-cycle sample — its first read is caller-covered). THE CALL GRAPH, over
# EVERY function bash's parse defines (a nested one too): a function READS when it holds a non-LOCAL curl command or the
# sampler, or calls one that reads; red when a walked function calls a reading function that is none of the sets above,
# and when a LOCAL-set function reads. A notification sender's (send_telegram, send_webhook, heartbeat_ping) curl is not
# a read only when EVERY URL word it sends to is that sender's own endpoint (api.telegram.org, "$WEBHOOK_URL",
# "$HEARTBEAT_URL"). A SHELL run as a command anywhere in the daemon is red: its -c string, its script or its stdin is code
# this census cannot walk (the daemons run none) — bp_parse's bpshell, fail-closed: a literal word naming a shell (sh /
# bash / rbash / dash / ash / hush / zsh / ksh / ksh93 / mksh and the other shells its header lists, by any path;
# busybox's sh / ash / hush / bash applet), whatever wrappers and options precede it, unless the only words after it are
# --version or --help (nothing after it reads stdin; any option, -c string or script runs code); an env -S string is read
# as its words, and sudo -s / -i runs a shell. (7g-local) pins where LOCAL_RPC is
# written — the LOCAL rule trusts that name. The PRIMARY's recovery pass is walked the same way.
#   The per-cycle and per-pass samples are not walked — worlds pin them (the delta panel 2 deleted each on fix round 2's
# build): the main loop's ((4b-residual)'s cut110 and (2)'s race turn BLIND), the recovery ladder's (test_act_then_alert
# (14a)'s rd20 is never recovered), the delay tail's (its (14d): the CLEAR age 15 → 12); the pass's FIRST sample by no
# world (deleted, every suite stayed green — its T9). What this census cannot say is which sample a world makes the
# baseline: MEASURED (7c)/(7c-age) — deleting the advisory's, the fence's, the fence split's, the pre-take and the
# per-cycle sample each changes a measured world; the confirm's reference samples, the fast path's, the probe's and the
# watchdog-elapsed split's changed none of 40 worlds (their reads are either rare at the take — the reference path runs
# only while TIER2 shows the holder within 128 slots — or followed by a chain longer than OWN_HEAD_H): this census pins
# them — each one deleted, guarded by && / ||, in one case arm, a loop body (one a conditional break or continue skips
# too), a subshell, a substitution, a pipeline or a background job is red here (rows g1–g5 below guard each one by &&;
# T2 moves the confirm's reference sample to the end of a payload retry loop left by `&& break`).
#   LIMIT, named — not seen: a read a loop repeats, or a while condition re-run (each walked once — the daemons' loops over
# the tiers sample before every read of the body, directly or inside the S function they call); network clients other
# than curl (wget, nc, socat, /dev/tcp — the daemons' only socat sends sd_notify datagrams to a UNIX socket); a read in
# the main loop's body (this census walks the take-cycle functions); a command word assembled at run time ($fn …, "$c");
# a string handed to eval / trap / mapfile -C (the (0d) census flags eval and pins every trap / mapfile); a shell whose
# word is assembled at run time ("$SHELL -c"), or a tool that runs its argument through a shell it names itself (flock -c);
# code an interpreter runs from a string (awk's system(), perl -e, python3 -c).
S2_PREP="$BP_AWK_LIB"'
function s2arg(wd,   l) {   # a curl option that takes the next word (NS_FUNCS argopt)
    if (wd ~ /^--/) return (wd ~ /^--(max-time|request|header|data|data-raw|data-binary|data-ascii|data-urlencode|json|output|write-out|connect-timeout|user-agent|referer|user|config|upload-file|form|proxy|url|cookie|cookie-jar|range|retry|retry-delay|retry-max-time|resolve|cacert|cert|key)$/)
    if (wd ~ /^-[A-Za-z]+$/) { l = substr(wd, length(wd), 1); return (l ~ /[mXHdowAeuKTFxbcrzE]/) }
    return 0
}
function curlw(n, W,   k, q) { for (k = 1; k <= n; k++) { q = bpq(W[k]); if (bplit(W[k]) && (q == "curl" || q ~ /\/curl$/)) return k } return 0 }
function locc(n, W, c,   j, q, r, nu) {   # the curl command at word c is a LOCAL read: one URL word, "$LOCAL_RPC", else only -s -m -X -H -d
  nu = 0
  for (j = c + 1; j <= n; j++) { q = bpq(W[j]); r = bpr(W[j])
    if (q == "-s") continue
    if (q ~ /^-[mXHd]$/) { j++; continue }
    if (r == "\"$LOCAL_RPC\"") { nu++; continue }
    return 0 }
  return (nu == 1)
}
function sender(n, W, c, f,   j, q, r, nu) {   # the curl command at word c of sender f sends ONLY to that sender endpoint: every URL word is it
  nu = 0
  for (j = c + 1; j <= n; j++) { q = bpq(W[j]); r = bpr(W[j])
    if (q == "--url" && j < n) { j++; r = bpr(W[j]) } else if (q ~ /^-/) { if (s2arg(q)) j++; continue }
    nu++
    if (f == "send_telegram" && r == "\"https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage\"") continue
    if (f == "send_webhook" && r == "\"$WEBHOOK_URL\"") continue
    if (f == "heartbeat_ping" && r == "\"$HEARTBEAT_URL\"") continue
    return 0 }
  return (nu > 0)
}'
S2_AWK="$S2_PREP"'
function rd(w) { if (st == 1) { printf "%s:%d: %s — an external read with no own-head sample since the previous one\n", fn, LNO, w; nb++ } if (st != -1) st = 1 }
function mv(a, b) { if (a == -1) return b; if (b == -1) return a; return (a > b) ? a : b }   # two paths join (-1: that path ended)
function fcl() { if (fc[fs]) st = mv(st, f0[fs]); if (fa[fs]) na--; fs-- }                   # a compound closes: an && / || operand joins the path that skipped it
BEGIN { st = start + 0; nb = 0; fs = 0; na = 0; n = split(cset, a, " "); for (i = 1; i <= n; i++) C[a[i]]; n = split(sset, a, " "); for (i = 1; i <= n; i++) S[a[i]]; n = split(lset, a, " "); for (i = 1; i <= n; i++) L[a[i]] }
NR == FNR { if ($1 == "A") ASY[$2] = 1; next }                                             # pass 1: the compounds that are a pipeline element or a background job
$2 != fn { next }
$1 == "K" && $5 == 1 && $6 == 0 { ev = $7                                                   # the structure at the function own level
  if (ev == "if" || ev == "loop" || ev == "case" || ev == "grp") { fs++; fk[fs] = ev; fc[fs] = ($9 == "&&" || $9 == "||"); fa[fs] = ($9 == "|" || $9 == "|&" || ($8 in ASY)); if (fa[fs]) na++
    f0[fs] = st; ca[fs] = 0; cd[fs] = 0; ct[fs] = ";;"; lm[fs] = -1; next }
  if (fs == 0) next
  if (ev == "then") { f1[fs] = st; mg[fs] = -1; he[fs] = 0 }
  else if (ev == "else") { mg[fs] = mv(mg[fs], st); st = f1[fs]; he[fs] = 1 }
  else if (ev == "fi") { mg[fs] = mv(mg[fs], st); if (!he[fs]) mg[fs] = mv(mg[fs], f1[fs]); st = mg[fs]; fcl() }
  else if (ev == "do") f1[fs] = st
  else if (ev == "done") { st = mv(mv(st, f1[fs]), lm[fs]); fcl() }
  else if (ev == "arm") { if (!ca[fs]) { f1[fs] = st; mg[fs] = -1 } else if (ct[fs] == ";&") st = mv(f1[fs], st); else { mg[fs] = mv(mg[fs], st); st = (ct[fs] == ";;&") ? mv(f1[fs], st) : f1[fs] }
    ca[fs] = 1; if ($9 == "*") cd[fs] = 1 }
  else if (ev == "arm-end") ct[fs] = $9
  else if (ev == "esac") { if (ca[fs]) mg[fs] = mv(mg[fs], st); else { f1[fs] = st; mg[fs] = -1 } if (!cd[fs]) mg[fs] = mv(mg[fs], f1[fs]); st = mg[fs]; fcl() }
  else if (ev == "grp-end") fcl()
  next }
$1 == "C" { LNO = $4; n = split($6, W, "\034"); split($7, X, ":")
  for (j = 1; j <= n; j++) { if (!bplit(W[j])) continue; w = bpq(W[j])
    if (w == "curl" || w ~ /\/curl$/) { if (locc(n, W, j)) { if (st != -1) st = 1 } else rd("curl"); break }
    if (w == "get_staked_liveness_sample" || (w in C)) rd(w)
    else if ((w in S) || (w in L)) { if (st != -1) st = 1 } }
  osh = (X[1] == 1 && X[2] == 0 && X[4] != "|" && X[4] != "|&" && X[4] != "&" && na == 0)   # run in the function own shell
  own = (osh && X[3] == "")                                                                  # … as a statement of its own (not an && / || right operand)
  k = bpcmd(n, W); q = k ? bpq(W[k]) : ""
  if (own && q == "_own_head_sample" && BPPRE == "") { if (st != -1) st = 0 }                # not behind command / builtin: neither runs a function
  else if (own && (q == "return" || q == "exit")) st = -1
  else if (osh && (q == "break" || q == "continue")) {                                       # the Nth enclosing loop exit takes this path; unconditional: it ends
    lv = 1
    if (k < n) { lv = bpq(W[k + 1]); if (!bplit(W[k + 1]) || lv !~ /^[1-9][0-9]*$/) { printf "%s:%d: %s %s — a loop count this census cannot read\n", fn, LNO, q, bpr(W[k + 1]); nb++; lv = 1 } else lv = lv + 0 }
    for (j = fs; j > 0; j--) if (fk[j] == "loop" && --lv <= 0) break
    if (j > 0) { lm[j] = mv(lm[j], st); if (X[3] == "") st = -1 }
    else { printf "%s:%d: %s — more loops than enclose it in the function own shell\n", fn, LNO, q; nb++ } }
  next }
END { exit (nb > 0) }'
S2_SHELL_AWK="$BP_AWK_LIB"'
$1 == "C" { n = split($6, W, "\034"); k = bpshell(n, W); if (k) printf "%s:%d: %s — a shell run as a command: its -c string or its stdin is code this census cannot walk\n", $2, $4, bpq(W[k]) }'
S2_GRAPH_AWK="$S2_PREP"'
BEGIN { n = split(wset, a, " "); for (i = 1; i <= n; i++) WS[a[i]]; n = split(kset, a, " "); for (i = 1; i <= n; i++) K[a[i]]; n = split(lset, a, " "); for (i = 1; i <= n; i++) L[a[i]]
        NS["send_telegram"]; NS["send_webhook"]; NS["heartbeat_ping"] }
$1 == "D" { if ($3 >= 1) isfn[$2] = 1; next }
$1 == "C" { f = $2; if (f == "" || f ~ /^\(/) next
  n = split($6, WW, "\034"); c = curlw(n, WW)
  if (c && !locc(n, WW, c) && !((f in NS) && sender(n, WW, c, f))) dr[f] = 1
  next }
$1 == "L" { f = $2; if (f == "" || f ~ /^\(/) next
  n = split($5, tk, /[^A-Za-z0-9_]+/)
  for (i = 1; i <= n; i++) { w = tk[i]; if (w == "" || w == f || w == "curl") continue; if (w == "get_staked_liveness_sample") dr[f] = 1; else calls[f] = calls[f] " " w }
  next }
END {
  for (f in isfn) R[f] = (f in dr)
  do { ch = 0; for (f in isfn) if (!R[f]) { n = split(calls[f], a, " "); for (i = 1; i <= n; i++) if ((a[i] in isfn) && R[a[i]]) { R[f] = 1; ch = 1; break } } } while (ch)
  for (w in WS) { if (!(w in isfn)) { printf "%s: NOT FOUND\n", w; continue }
    n = split(calls[w], a, " "); for (i = 1; i <= n; i++) if ((a[i] in isfn) && R[a[i]] && !(a[i] in K) && !(a[i] in L) && !((w, a[i]) in seen)) { seen[w, a[i]] = 1; printf "%s: calls %s — it reaches an external read (curl or the liveness sampler) and is none of the census sets\n", w, a[i] } }
  for (l in L) if (R[l]) printf "%s: a LOCAL-set function that reaches an external read\n", l
  for (f in NS) if (!(f in isfn)) printf "%s: notification sender NOT FOUND\n", f
  nr = 0; nf = 0; for (f in isfn) { nf++; if (R[f]) nr++ } printf "READERS %d\nFUNCTIONS %d\n", nr, nf
}'
# (7g-local) every place bash's parse WRITES the name LOCAL_RPC: an assignment word (NAME=, NAME+=, NAME[…]=) of any
# command; the name (or a nameref's =NAME) as an argument of local / declare / typeset / export / readonly / read / unset /
# printf (its -v, or -vNAME) / mapfile / readarray / for / select / getopts; and a ${LOCAL_RPC:=…} / ${LOCAL_RPC=…}
# expansion anywhere bash expands one — a command word, a redirection target or a here-string, a case pattern (bp_parse's
# R records), the body of an unquoted here-document (its H records; a quoted one is text). LIMIT: an arithmetic write
# (let, (( )), $(( ))), a name computed at run time (printf -v "$n", ${!n}), a string handed to eval (the (0d) census
# flags eval).
LOCALW_AWK="$BP_AWK_LIB"'
$1 == "C" { n = split($6, W, "\034"); k = bpcmd(n, W); e = (k ? k - 1 : n)
  for (j = 1; j <= e; j++) if (bpq(W[j]) ~ /^LOCAL_RPC(\[[^]]*\])?\+?=/) printf "%s:%s\n", $2, bpq(W[j])
  if (k && bpq(W[k]) ~ /^(local|declare|typeset|export|readonly|read|unset|printf|mapfile|readarray|for|select|getopts)$/)
    for (j = k + 1; j <= n; j++) { q = bpq(W[j]); if (q ~ /^LOCAL_RPC(\[|\+?=|$)/ || q ~ /^[A-Za-z_][A-Za-z0-9_]*=LOCAL_RPC$/ || (bpq(W[k]) == "printf" && q == "-vLOCAL_RPC")) printf "%s:%s %s\n", $2, bpq(W[k]), q }
  for (j = 1; j <= n; j++) if (bpr(W[j]) ~ /\$\{LOCAL_RPC:?=/) printf "%s:%s\n", $2, bpr(W[j]) }
$1 == "R" && $6 ~ /\$\{LOCAL_RPC:?=/ { printf "%s:%s %s\n", $2, $5, $6 }
$1 == "H" && $6 == "0" && $5 ~ /\$\{LOCAL_RPC:?=/ { printf "%s:here-document %s\n", $2, $5 }'
S2_STANDBY_FNS="attempt_takeover:1 confirm_delinquency_external:0 tier2_check_delinquency:0 tier3_confirm_delinquency:0 check_primary_dropped_identity:1 peer_has_relinquished:1 staked_is_actively_voting:0 take_staked_identity:1 _fresh_proof_recheck:0 _elapsed_step:0"
S2_STANDBY_C="tier2_check_delinquency tier3_confirm_delinquency confirm_delinquency_external staked_is_actively_voting _fresh_proof_recheck"
S2_STANDBY_S="check_primary_dropped_identity peer_has_relinquished take_staked_identity"
# the PRIMARY's recovery pass (the take path's other daemon — T5-UNPINNED's three primary lines among its samples)
S2_PRIMARY_FNS="attempt_safe_recovery:1 _check_rpc_delinquency:0 _check_single_rpc:1 check_standby_has_identity:1 staked_is_actively_voting:0 switch_to_staked:1 _fresh_proof_recheck:0"
S2_PRIMARY_C="_check_rpc_delinquency staked_is_actively_voting _fresh_proof_recheck"
S2_PRIMARY_S="check_standby_has_identity _check_single_rpc switch_to_staked"
S2_LOCAL="tier1_check_delinquency local_check_delinquency get_local_identity"
s2_census() {   # s2_census <daemon> <fn:start …> <C set> <S set> — every violation, one per line; rc 1 if any (bash's parse)
    local d="$1" fns="$2" cs="$3" ss="$4" f st rc=0 g w="" _p
    _p=$(ovp "$d"); [[ -f "$_p/FAIL" ]] && { echo "PARSE-FAIL $(basename "$d")"; return 1; }
    for f in $fns; do
        st=${f##*:}; f=${f%%:*}; w="$w $f"
        awk -F'\t' -v f="$f" '$1 == "D" && $2 == f && $3 == 1 { x = 1 } END { exit !x }' "$_p/lex" || { echo "$f: NOT FOUND"; rc=1; continue; }
        awk -F'\t' -v fn="$f" -v start="$st" -v cset="$cs" -v sset="$ss" -v lset="$S2_LOCAL" "$S2_AWK" "$_p/lex" "$_p/lex" || rc=1   # two passes: the async compounds first
    done
    g=$(awk -F'\t' "$S2_SHELL_AWK" "$_p/lex"); [[ -z "$g" ]] || { printf '%s\n' "$g"; rc=1; }
    g=$(awk -F'\t' -v wset="$w" -v kset="$cs $ss $w" -v lset="$S2_LOCAL" "$S2_GRAPH_AWK" "$_p/lex")
    s2_readers=$(printf '%s\n' "$g" | sed -n 's/^READERS //p'); s2_fns=$(printf '%s\n' "$g" | sed -n 's/^FUNCTIONS //p')
    g=$(printf '%s\n' "$g" | grep -v -e '^READERS ' -e '^FUNCTIONS ')
    [[ -z "$g" ]] || { printf '%s\n' "$g"; rc=1; }
    return $rc
}
s2_sb() { s2_census "$1" "$S2_STANDBY_FNS" "$S2_STANDBY_C" "$S2_STANDBY_S"; }
s2_pr() { s2_census "$1" "$S2_PRIMARY_FNS" "$S2_PRIMARY_C" "$S2_PRIMARY_S"; }
s2_sb "$STANDBY" > "$WORK/s2sb.out"; s2_rc=$?; s2_out=$(cat "$WORK/s2sb.out"); s2_sbr=$s2_readers; s2_sbf=$s2_fns   # (not $(s2_sb …): s2_readers must survive)
s2_pr "$PRIMARY" > "$WORK/s2pr.out"; s2p_rc=$?; s2p_out=$(cat "$WORK/s2pr.out"); s2_prr=$s2_readers; s2_prf=$s2_fns
s2_nsamp=$(awk -F'\t' "$BP_AWK_LIB"' $1 == "C" && $2 ~ /^(attempt_takeover|confirm_delinquency_external|tier2_check_delinquency|check_primary_dropped_identity|peer_has_relinquished|staked_is_actively_voting|take_staked_identity|_elapsed_step)$/ { n = split($6, W, "\034"); split($7, X, ":"); k = bpcmd(n, W); if (k && bpq(W[k]) == "_own_head_sample" && BPPRE == "" && X[1] == 1 && X[2] == 0 && X[3] == "" && X[4] !~ /^(\||\|&|&)$/) c++ } END { print c + 0 }' "$(ovp "$STANDBY")/lex")   # statement samples, in the own shell
mutate "$STANDBY" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 2, S2 — the delta panel.s DAV-1\/CK-2).*$/\1: deleted/' "$WORK/s-c7g-a.sh"
mutate "$STANDBY" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 2, S2): between the reference and the re-read.*$/\1: deleted/' "$WORK/s-c7g-b.sh"
mutate "$STANDBY" 's/^\(        _watchdog_pet   # §5 per-op pet (Block 5.2\/FF-B1 N-audit): bounded op completed (rc captured above) — post-op placement covers EVERY exit (holder-present return.*\)$/\1\
        _x=$(curl -s -m 5 "$TIER2_RPC" -d x)/' "$WORK/s-c7g-c.sh"
mutate "$STANDBY" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 2, S2): before the probe.s first read.*$/\1: deleted/' "$WORK/s-c7g-d.sh"
mutate "$PRIMARY" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 1, R3): before the pass.s TIER2 read.*$/\1: deleted/' "$WORK/p-c7g-e.sh"   # T5-UNPINNED's pre-TIER2 sample
# the delta panel 2's T8-S2SPELL evasions, each GREEN on fix round 2's census (fix round 3 — red first): after the
# fence's own sample (f, g: a quoted substitution), a helper holding the read (h: the sampler, i: a TIER2 curl), a
# TIER2 curl inside a LOCAL-set function (j), and a TIER2 read spelled with LOCAL_RPC right after the fence (k)
S2_FENCE_SAMPLE='^\(        _own_head_sample   # v0.7 (Block 6.3.1 fix round 1, R3): before the fence.s external read (see the R3 note above the confirm)\)$'
mutate "$STANDBY" "s/$S2_FENCE_SAMPLE/\\1\\
        _s2=\"\$(get_staked_liveness_sample)\"/" "$WORK/s-c7g-f.sh"
mutate "$STANDBY" "s/$S2_FENCE_SAMPLE/\\1\\
        _xr=\"\$(curl -s -m 10 \"\$TIER2_RPC\" -X POST -d x)\"/" "$WORK/s-c7g-g.sh"
mutate "$STANDBY" 's/^staked_is_actively_voting() {$/_x_probe() { get_staked_liveness_sample >\/dev\/null 2>\&1; }\
_x_tier2() {\
    curl -s -m 10 "$TIER2_RPC" -X POST -d x >\/dev\/null 2>\&1\
}\
&/' "$WORK/s-c7g-h0.sh"
mutate "$WORK/s-c7g-h0.sh" "s/$S2_FENCE_SAMPLE/\\1\\
        _x_probe/" "$WORK/s-c7g-h.sh"
mutate "$WORK/s-c7g-h0.sh" "s/$S2_FENCE_SAMPLE/\\1\\
        _x_tier2/" "$WORK/s-c7g-i.sh"
mutate "$STANDBY" 's/^\(    STAT_LOCAL_DELINQ=$((STAT_LOCAL_DELINQ + 1))\)$/\1\
    curl -s -m 10 "$TIER2_RPC" -X POST -d x >\/dev\/null 2>\&1/' "$WORK/s-c7g-j.sh"
mutate "$STANDBY" 's/^\(        staked_is_actively_voting; local liveness=$?\)$/\1\
        curl -s -m 10 "${TIER2_RPC:-$LOCAL_RPC}" -X POST -d x >\/dev\/null 2>\&1/' "$WORK/s-c7g-k.sh"
# the delta panel 3's TS3-7G-EVASIONS shapes, each GREEN on fix round 3's census (fix round 4 — red first): l (Y20)
# local_check_delinquency's LOCAL getVoteAccounts curl given a second URL "$TIER2_RPC" on its continuation line; m (Y21)
# a helper holding the sampler, spelled `_x_probe ( ) {…}`, called after the fence's sample; n (Y6b) a LOCAL curl given a
# second URL word in a variable, before the fence's sample
mutate "$STANDBY" 's/^\(    vote_result=$(curl -s -m 5 "$LOCAL_RPC"\) \(-X POST \\\)$/\1 \\\
        "$TIER2_RPC" \2/' "$WORK/s-c7g-l.sh"
mutate "$STANDBY" 's/^staked_is_actively_voting() {$/_x_probe ( ) { get_staked_liveness_sample >\/dev\/null 2>\&1; }\
&/' "$WORK/s-c7g-m0.sh"
mutate "$WORK/s-c7g-m0.sh" "s/$S2_FENCE_SAMPLE/\\1\\
        _x_probe/" "$WORK/s-c7g-m.sh"
mutate "$STANDBY" "s/$S2_FENCE_SAMPLE/        local _y6u=\"\$TIER2_RPC\"\\
        curl -s -m 10 \"\$LOCAL_RPC\" \"\$_y6u\" -X POST -d x >\\/dev\\/null 2>\\&1\\
\\1/" "$WORK/s-c7g-n.sh"
# the delta panels 3/4's shapes the source-line census could not see (fix round 5 — red first; each GREEN on fix round
# 4's census): o (T4-LEXER-QUOTES' s2_hashstr) a TIER2 curl behind `log_info "fence # probe";` right after the fence's
# sample; p (its s2_apos_helper) a column-0 helper holding the sampler behind an apostrophe, called there; q
# (T4-7G-ONELINE) the helper as `_x_probe() { local _z=${1:-}` ⏎ sampler ⏎ `}`; r / s / t (TS3-7G-EVASIONS' Y5 / Y3 /
# Y4) a TIER2 curl spelled "curl", cu''rl, c\url right after the fence's sample
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-o.sh" <<'EOB'
        log_info "fence # probe"; curl -s -m 10 "$TIER2_RPC" -X POST -d x >/dev/null 2>&1
EOB
ev_mut "$STANDBY" "staked_is_actively_voting() {" before "$WORK/s-c7g-p0.sh" <<'EOB'
: "the spare's probe"; _x_probe() { get_staked_liveness_sample >/dev/null 2>&1; }; : 'x'
EOB
ev_mut "$WORK/s-c7g-p0.sh" "R3): before the fence" after "$WORK/s-c7g-p.sh" <<'EOB'
        _x_probe
EOB
ev_mut "$STANDBY" "staked_is_actively_voting() {" before "$WORK/s-c7g-q0.sh" <<'EOB'
_x_probe() { local _z=${1:-}
    get_staked_liveness_sample >/dev/null 2>&1
}
EOB
ev_mut "$WORK/s-c7g-q0.sh" "R3): before the fence" after "$WORK/s-c7g-q.sh" <<'EOB'
        _x_probe
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-r.sh" <<'EOB'
        "curl" -s -m 10 "$TIER2_RPC" -X POST -d x >/dev/null 2>&1
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-s.sh" <<'EOB'
        cu''rl -s -m 10 "$TIER2_RPC" -X POST -d x >/dev/null 2>&1
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-t.sh" <<'EOB'
        c\url -s -m 10 "$TIER2_RPC" -X POST -d x >/dev/null 2>&1
EOB
# the delta panel 5's shapes (fix round 6 — red first; each GREEN on fix round 5's census): w1 / w2 a TIER2 curl in the
# $( ) of an UNQUOTED here-document body (inside a $( ), and at statement level — its m42 / m43), w3 a TIER2 curl as
# `$((curl …) )` (a command substitution holding a subshell, as bash reads it — its runarith), w4 `timeout 12 bash -c
# '…curl…'` (a shell run as a command — its runbashc / CLM5-1), each right after the fence's sample; s01–s06, s08, s14,
# s15 the fence's sample itself made conditional or lost (its TS5-7G-SAMPLE-TOKEN / CLM5-2 forms, by its numbers: an &&
# operand, one case arm, a subshell, a substitution, a background job, a pipeline, a loop body, an argument, a string);
# g1–g5 each sample the header says no
# world pins, guarded by && (the probe's, the fast path's, the confirm's two reference samples, the watchdog-elapsed
# split's); and s13, the sample that runs FIRST in an || list — it runs, so it stays GREEN
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-w1.sh" <<'EOB'
        _x=$(cat <<EOS
$(curl -s -m 10 "$TIER2_RPC" -X POST -d x 2>/dev/null)
EOS
)
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-w2.sh" <<'EOB'
        cat > /dev/null <<EOS
$(curl -s -m 10 "$TIER2_RPC" -X POST -d x 2>/dev/null)
EOS
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-w3.sh" <<'EOB'
        _x=$((curl -s -m 10 "$TIER2_RPC" -X POST -d x 2>/dev/null) )
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-w4.sh" <<'EOB'
        _x=$(timeout 12 bash -c 'curl -s -m 10 "$1" -X POST -d x' _ "$TIER2_RPC")
EOB
s2_rep() {   # s2_rep <name> <text> — the fence's sample line replaced by <text> (a copy of the standby)
    awk -v a="R3): before the fence" -v t="$2" '!d && index($0, a) && $0 !~ /^[[:space:]]*#/ { print t; d = 1; next } { print } END { exit(d ? 0 : 1) }' "$STANDBY" > "$WORK/s-c7g-$1.sh"
}
s2_rep s01 '        [[ -n "$TIER2_RPC" ]] && _own_head_sample'
s2_rep s02 '        case "$GOSSIP_VERIFY" in true) _own_head_sample ;; esac'
s2_rep s03 '        ( _own_head_sample )'
s2_rep s04 '        _x=$(_own_head_sample)'
s2_rep s05 '        _own_head_sample &'
s2_rep s06 '        _own_head_sample | cat'
s2_rep s08 '        while false; do _own_head_sample; done'
s2_rep s13 '        _own_head_sample 2>/dev/null || true'
s2_rep s14 '        : _own_head_sample'
s2_rep s15 '        log_info "_own_head_sample"'
mutate "$STANDBY" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 2, S2): before the probe.s first read/\1[[ -n "${_x_never:-}" ]] \&\& _own_head_sample   # (guarded) before the probe.s first read/' "$WORK/s-c7g-g1.sh"
mutate "$STANDBY" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 2, S2): before each external read (a fast-path cycle takes)/\1[[ -n "${_x_never:-}" ]] \&\& _own_head_sample   # (guarded)/' "$WORK/s-c7g-g2.sh"
mutate "$STANDBY" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 2, S2): between the payload and the reference/\1[[ -n "${_x_never:-}" ]] \&\& _own_head_sample   # (guarded)/' "$WORK/s-c7g-g3.sh"
mutate "$STANDBY" 's/^\( *\)_own_head_sample   # v0.7 (Block 6.3.1 fix round 2, S2): between the reference and the re-read/\1[[ -n "${_x_never:-}" ]] \&\& _own_head_sample   # (guarded)/' "$WORK/s-c7g-g4.sh"
mutate "$STANDBY" 's/^\(        _es_s=$(TIER3_RPC="" get_staked_liveness_sample) || { \)_own_head_sample;/\1[[ -n "${_x_never:-}" ]] \&\& _own_head_sample;/' "$WORK/s-c7g-g5.sh"
# the delta panel 6's CEN6-7G-CONDBREAK shapes (fix round 7 — red first; each GREEN on fix round 6's census, which ended a
# path only at an unconditional break / continue and dropped one behind && / ||, and merged a `break 2` into the inner loop):
# on the PRIMARY's recovery pass, _check_single_rpc's getVoteAccounts read in a retry loop with the sample before
# getClusterNodes moved to the loop's end — P1 `[[ $_csr_rc -eq 0 ]] && break`, P1or `[[ $_csr_rc -ne 0 ]] || break`, P3
# `&& continue` (a one-pass loop), P5 an inner loop left by `if …; then break 2; fi`, P5and by `… && break 2`, Pdeep a
# `break 2` with one loop around it, Pvar a `break "$_n"`; beside the if-forms P1if / P3if (red on fix round 6 too) and the
# control P5b1 (a plain `break` out of the inner loop, the sample after it: GREEN, correctly); on the STANDBY, T2 the
# confirm's payload read in an opt-in retry loop (`&& break`, `|| break`) with the reference's sample moved to its end —
# the sample the header says no world pins (test_elapsed_provider (13b)'s op order catches it elsewhere) — beside T2if;
# and g13 a liveness read in a two-try loop left by `&& break` right after the fence's sample, beside g13if. The delta
# panel 6's CEN6-7G-CMDPREFIX (red first; GREEN on fix round 6's census): b16 / b17 the fence's sample spelled
# `command _own_head_sample` / `builtin _own_head_sample` — neither runs the function (rc 127 / rc 1). Its
# CEN6-BPSHELL-LONGOPT (red first; GREEN on fix round 6's census, which enumerated wrappers): w01 `nice --adjustment 5
# bash -c '…curl…'`, w02 `… | xargs --max-args 1 bash -c '…curl…' _` and wsb `stdbuf -o0 bash -c '…curl…'`, each right
# after the fence's sample — a shell run as a command, found by its word
lw_mut() {   # lw_mut <in> <out> <fn> <open> <close> <head> <tail> [<sample-anchor>] — inside fn: <head> printed before the line
             # holding <open>, <tail> after the next line holding <close> (awk -v: \n separates lines), and the first
             # _own_head_sample statement after the line holding <sample-anchor> deleted; rc 1 when an anchor is missing
    awk -v fn="$3" -v oa="$4" -v ca="$5" -v hd="$6" -v tl="$7" -v sa="${8:-}" '
      $0 == fn "() {" { inf = 1 }
      inf && $0 == "}" { inf = 0 }
      inf && !o && index($0, oa) { print hd; print; o = 1; next }
      inf && o && !c && index($0, ca) { print; print tl; c = 1; next }
      inf && sa != "" && !sd && !sw && index($0, sa) { print; sw = 1; next }
      sw && $0 ~ /^[[:space:]]*_own_head_sample[[:space:]]/ { sw = 0; sd = 1; next }
      { print } END { exit((o && c && (sa == "" || sd)) ? 0 : 1) }' "$1" > "$2"
}
CB_O='vote_info=$(curl -s -m 15 "$rpc_url" -X POST'; CB_C='fires on the unreachable early-return too'; CB_S='local cluster_info staked_gossip_ep'
lw_mut "$PRIMARY" "$WORK/p-c7g-P1.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_try in 1 2; do' '[[ $_csr_rc -eq 0 ]] && break\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-P1if.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_try in 1 2; do' 'if [[ $_csr_rc -eq 0 ]]; then break; fi\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-P1or.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_try in 1 2; do' '[[ $_csr_rc -ne 0 ]] || break\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-P3.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_try in 1; do' '[[ $_csr_rc -eq 0 ]] && continue\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-P3if.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_try in 1; do' 'if [[ $_csr_rc -eq 0 ]]; then continue; fi\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-P5.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_o in 1; do\nfor _csr_try in 1; do' 'if [[ $_csr_rc -eq 0 ]]; then break 2; fi\ndone\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-P5and.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_o in 1; do\nfor _csr_try in 1; do' '[[ $_csr_rc -eq 0 ]] && break 2\ndone\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-P5b1.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_o in 1; do\nfor _csr_try in 1; do' 'if [[ $_csr_rc -eq 0 ]]; then break; fi\ndone\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-Pdeep.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_try in 1 2; do' '[[ $_csr_rc -eq 0 ]] && break 2\n_own_head_sample\ndone' "$CB_S"
lw_mut "$PRIMARY" "$WORK/p-c7g-Pvar.sh" _check_single_rpc "$CB_O" "$CB_C" 'for _csr_try in 1 2; do' '[[ $_csr_rc -eq 0 ]] && break "$_n"\n_own_head_sample\ndone' "$CB_S"
CB_TO='vote_result=$(curl -s -m "$curl_timeout" "$TIER2_RPC" -X POST'; CB_TC='a completed 15 s curl timeout is a completed op'; CB_TS='local current_slot last_vote'
lw_mut "$STANDBY" "$WORK/s-c7g-T2.sh" tier2_check_delinquency "$CB_TO" "$CB_TC" 'for _t2_try in 1 2; do' '[[ $_t2_rc -eq 0 && -n "$vote_result" ]] && break\n[[ $_t2_try -lt 2 && "${TIER2_RETRY:-false}" == "true" ]] || break\n_own_head_sample\ndone' "$CB_TS"
lw_mut "$STANDBY" "$WORK/s-c7g-T2if.sh" tier2_check_delinquency "$CB_TO" "$CB_TC" 'for _t2_try in 1 2; do' 'if [[ $_t2_rc -eq 0 && -n "$vote_result" ]]; then break; fi\n[[ $_t2_try -lt 2 && "${TIER2_RETRY:-false}" == "true" ]] || break\n_own_head_sample\ndone' "$CB_TS"
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-g13.sh" <<'EOB'
        for _try in 1 2; do
            _s=$(get_staked_liveness_sample) && break
            _own_head_sample
        done
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-g13if.sh" <<'EOB'
        for _try in 1 2; do
            if _s=$(get_staked_liveness_sample); then break; fi
            _own_head_sample
        done
EOB
s2_rep b16 '        command _own_head_sample'
s2_rep b17 '        builtin _own_head_sample'
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-w01.sh" <<'EOB'
        _x=$(nice --adjustment 5 bash -c 'curl -s -m 10 "$1" -X POST -d x' _ "$TIER2_RPC")
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-w02.sh" <<'EOB'
        _x=$(printf '%s\n' "$TIER2_RPC" | xargs --max-args 1 bash -c 'curl -s -m 10 "$1" -X POST -d x' _)
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-wsb.sh" <<'EOB'
        _x=$(stdbuf -o0 bash -c 'curl -s -m 10 "$1" -X POST -d x' _ "$TIER2_RPC")
EOB
# The delta panel 7's CHK7-BPSHELL-STDIN-REGRESSION (red first; GREEN on fix round 7's bpshell, which passed a shell
# followed only by options without c, and busybox's `sh -s` on every earlier round): ws — sixteen shells right after the
# fence's sample, one per line, each reading code from its stdin: `| bash -s`, `bash -e <<'EOS'` holding a confirmed
# getVoteAccounts curl, `| sh -eu`, `| bash -`, `| env bash -s`, `| busybox sh -s`, `bash -e < /dev/null`, `bash
# --noprofile --norc`, `| /bin/sh -s`, `| dash -e`, `| bash -i`, `| bash --posix`, `| bash --`, `| timeout 10 bash -x`,
# `| bash --norc`, `bash -l -s < /dev/null` — (7g) names sixteen shells and (1a) reads sixteen unparseable; wsv `bash
# --version` and `bash --help` (the only words bpshell lets follow a shell) green on both
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-ws.sh" <<'EOB'
        _x=$(printf ':' | bash -s)
        _x=$(bash -e <<'EOS'
curl -s -m 10 "$TIER2_RPC" -X POST -d '{"jsonrpc":"2.0","id":1,"method":"getVoteAccounts","params":[{"commitment":"confirmed"}]}'
EOS
)
        _x=$(printf ':' | sh -eu)
        _x=$(printf ':' | bash -)
        _x=$(printf ':' | env bash -s)
        _x=$(printf ':' | busybox sh -s)
        _x=$(bash -e < /dev/null)
        _x=$(bash --noprofile --norc < /dev/null)
        _x=$(printf ':' | /bin/sh -s)
        _x=$(printf ':' | dash -e)
        _x=$(printf ':' | bash -i)
        _x=$(printf ':' | bash --posix)
        _x=$(printf ':' | bash --)
        _x=$(printf ':' | timeout 10 bash -x)
        _x=$(printf ':' | bash --norc)
        _x=$(bash -l -s < /dev/null)
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-wsv.sh" <<'EOB'
        _v=$(bash --version | head -1)
        _v=$(bash --help | head -1)
EOB
# The delta panel 8's CHK8-BPSHELL-NAMES (red first; GREEN on fix round 8's bpshell, which knew the names bash sh dash zsh
# ksh only and read no env -S string): wn — ten shells right after the fence's sample, one per line, each reading code from
# its stdin or a -c string: `| ash -s`, `/bin/ash -c`, `| hush`, `| mksh -s`, `| rbash -s`, `| ksh93 -s`, `env -S 'bash
# -s'`, `env -S'bash -s'`, `env --split-string='bash -s'`, `sudo -s` — (7g) names ten shells and (1a) reads ten
# unparseable; wnv `env -S 'printf x'`, `sudo -u nobody printf x` and `env -u FOO printf x` (no shell) green on both
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-wn.sh" <<'EOB'
        _x=$(printf ':' | ash -s)
        _x=$(/bin/ash -c ':')
        _x=$(printf ':' | hush)
        _x=$(printf ':' | mksh -s)
        _x=$(printf ':' | rbash -s)
        _x=$(printf ':' | ksh93 -s)
        _x=$(printf ':' | env -S 'bash -s')
        _x=$(printf ':' | env -S'bash -s')
        _x=$(env --split-string='bash -s' < /dev/null)
        _x=$(sudo -s < /dev/null)
EOB
ev_mut "$STANDBY" "R3): before the fence" after "$WORK/s-c7g-wnv.sh" <<'EOB'
        _v=$(env -S 'printf x')
        _v=$(sudo -u nobody printf x)
        _v=$(env -u FOO printf x)
EOB
c7g_r7=1; c7g_r7r=""
for _g in "P1|p|_check_single_rpc:*: curl — an external read" "P1if|p|_check_single_rpc:*: curl — an external read" "P1or|p|_check_single_rpc:*: curl — an external read" \
          "P3|p|_check_single_rpc:*: curl — an external read" "P3if|p|_check_single_rpc:*: curl — an external read" "P5|p|_check_single_rpc:*: curl — an external read" \
          "P5and|p|_check_single_rpc:*: curl — an external read" "Pdeep|p|_check_single_rpc:*break — more loops than enclose it" "Pvar|p|_check_single_rpc:*a loop count this census cannot read" \
          "P5b1|p|GREEN" "T2|s|tier2_check_delinquency:*: curl — an external read" "T2if|s|tier2_check_delinquency:*: curl — an external read" \
          "g13|s|attempt_takeover:*staked_is_actively_voting — an external read" "g13if|s|attempt_takeover:*staked_is_actively_voting — an external read" \
          "b16|s|attempt_takeover:*staked_is_actively_voting — an external read" "b17|s|attempt_takeover:*staked_is_actively_voting — an external read" \
          "w01|s|attempt_takeover:*bash — a shell run as a command" "w02|s|attempt_takeover:*bash — a shell run as a command" "wsb|s|attempt_takeover:*bash — a shell run as a command"; do
    _n=${_g%%|*}; _k=${_g#*|}; _w=${_k#*|}; _k=${_k%%|*}; _f="$WORK/$_k-c7g-$_n.sh"
    [[ -s "$_f" ]] && ! cmp -s "$([[ $_k == p ]] && echo "$PRIMARY" || echo "$STANDBY")" "$_f" || { c7g_r7=0; c7g_r7r="$c7g_r7r [$_n: NOT-BUILT]"; continue; }
    if [[ $_k == p ]]; then _o=$(s2_pr "$_f"); _r=$?; else _o=$(s2_sb "$_f"); _r=$?; fi
    if [[ "$_w" == "GREEN" ]]; then [[ $_r -eq 0 && -z "$_o" ]] || { c7g_r7=0; c7g_r7r="$c7g_r7r [$_n: rc=$_r (want GREEN) $(printf '%s' "$_o" | tr '\n' ';' | cut -c1-160)]"; }; continue; fi
    [[ $_r -ne 0 && "$_o" == *$_w* ]] || { c7g_r7=0; c7g_r7r="$c7g_r7r [$_n: rc=$_r $(printf '%s' "$_o" | tr '\n' ';' | cut -c1-200)]"; }
done
# ws / wsv (CHK7-BPSHELL-STDIN-REGRESSION): sixteen shells named by (7g) and read unparseable by (1a); wsv green on both
if [[ -s "$WORK/s-c7g-ws.sh" && -s "$WORK/s-c7g-wsv.sh" ]]; then
    _o=$(s2_sb "$WORK/s-c7g-ws.sh"); _r=$?; _n=$(printf '%s\n' "$_o" | grep -c ' — a shell run as a command'); _d=$(d1_scan "$WORK/s-c7g-ws.sh" | head -1)
    [[ $_r -ne 0 && "$_n" == "16" && "$_d" == *" unparseable=16 "* ]] || { c7g_r7=0; c7g_r7r="$c7g_r7r [ws: rc=$_r shells named=$_n (want 16) (1a) $_d]"; }
    _o=$(s2_sb "$WORK/s-c7g-wsv.sh"); _r=$?; _d=$(d1_scan "$WORK/s-c7g-wsv.sh" | head -1)
    [[ $_r -eq 0 && -z "$_o" && "$_d" == *" unparseable=0 "* ]] || { c7g_r7=0; c7g_r7r="$c7g_r7r [wsv: rc=$_r (want GREEN) $(printf '%s' "$_o" | tr '\n' ';' | cut -c1-160) (1a) $_d]"; }
else
    c7g_r7=0; c7g_r7r="$c7g_r7r [ws/wsv: NOT-BUILT]"
fi
# wn / wnv (CHK8-BPSHELL-NAMES): ten shells named by (7g) and read unparseable by (1a); wnv green on both
if [[ -s "$WORK/s-c7g-wn.sh" && -s "$WORK/s-c7g-wnv.sh" ]]; then
    _o=$(s2_sb "$WORK/s-c7g-wn.sh"); _r=$?; _n=$(printf '%s\n' "$_o" | grep -c ' — a shell run as a command'); _d=$(d1_scan "$WORK/s-c7g-wn.sh" | head -1)
    [[ $_r -ne 0 && "$_n" == "10" && "$_d" == *" unparseable=10 "* ]] || { c7g_r7=0; c7g_r7r="$c7g_r7r [wn: rc=$_r shells named=$_n (want 10) (1a) $_d]"; }
    _o=$(s2_sb "$WORK/s-c7g-wnv.sh"); _r=$?; _d=$(d1_scan "$WORK/s-c7g-wnv.sh" | head -1)
    [[ $_r -eq 0 && -z "$_o" && "$_d" == *" unparseable=0 "* ]] || { c7g_r7=0; c7g_r7r="$c7g_r7r [wnv: rc=$_r (want GREEN) $(printf '%s' "$_o" | tr '\n' ';' | cut -c1-160) (1a) $_d]"; }
else
    c7g_r7=0; c7g_r7r="$c7g_r7r [wn/wnv: NOT-BUILT]"
fi
c7g_r6=1; c7g_r6r=""
for _g in "w1|attempt_takeover:*staked_is_actively_voting — an external read" "w2|attempt_takeover:*staked_is_actively_voting — an external read" "w3|attempt_takeover:*staked_is_actively_voting — an external read" "w4|attempt_takeover:*bash — a shell run as a command" \
          "s01|attempt_takeover:*staked_is_actively_voting — an external read" "s02|attempt_takeover:*staked_is_actively_voting — an external read" "s03|attempt_takeover:*staked_is_actively_voting — an external read" \
          "s04|attempt_takeover:*staked_is_actively_voting — an external read" "s05|attempt_takeover:*staked_is_actively_voting — an external read" "s06|attempt_takeover:*staked_is_actively_voting — an external read" \
          "s08|attempt_takeover:*staked_is_actively_voting — an external read" "s14|attempt_takeover:*staked_is_actively_voting — an external read" "s15|attempt_takeover:*staked_is_actively_voting — an external read" \
          "g1|attempt_takeover:*get_staked_liveness_sample — an external read" "g2|attempt_takeover:*: curl — an external read" "g3|tier2_check_delinquency:*: curl — an external read" "g4|tier2_check_delinquency:*: curl — an external read" \
          "g5|_elapsed_step:*get_staked_liveness_sample — an external read" "s13|GREEN"; do
    [[ -s "$WORK/s-c7g-${_g%%|*}.sh" ]] && ! cmp -s "$STANDBY" "$WORK/s-c7g-${_g%%|*}.sh" || { c7g_r6=0; c7g_r6r="$c7g_r6r [${_g%%|*}: NOT-BUILT]"; continue; }
    _o=$(s2_sb "$WORK/s-c7g-${_g%%|*}.sh"); _r=$?
    if [[ "${_g#*|}" == "GREEN" ]]; then [[ $_r -eq 0 && -z "$_o" ]] || { c7g_r6=0; c7g_r6r="$c7g_r6r [${_g%%|*}: rc=$_r (want GREEN) $(printf '%s' "$_o" | tr '\n' ';' | cut -c1-160)]"; }; continue; fi
    [[ $_r -ne 0 && "$_o" == *${_g#*|}* ]] || { c7g_r6=0; c7g_r6r="$c7g_r6r [${_g%%|*}: rc=$_r $(printf '%s' "$_o" | tr '\n' ';' | cut -c1-200)]"; }
done
c7g_e=$(s2_pr "$WORK/p-c7g-e.sh"); c7g_er=$?
c7g_a=$(s2_sb "$WORK/s-c7g-a.sh"); c7g_ar=$?; c7g_b=$(s2_sb "$WORK/s-c7g-b.sh"); c7g_br=$?
c7g_c=$(s2_sb "$WORK/s-c7g-c.sh"); c7g_cr=$?; c7g_d=$(s2_sb "$WORK/s-c7g-d.sh"); c7g_dr=$?
c7g_t8=1; c7g_t8r=""
for _g in "f|attempt_takeover:*staked_is_actively_voting — an external read" "g|attempt_takeover:*staked_is_actively_voting — an external read" "h|attempt_takeover: calls _x_probe" "i|attempt_takeover: calls _x_tier2" "j|local_check_delinquency: a LOCAL-set function that reaches an external read" "k|attempt_takeover:*: curl — an external read" \
          "l|local_check_delinquency: a LOCAL-set function that reaches an external read" "m|attempt_takeover: calls _x_probe" "n|attempt_takeover:*: curl — an external read" \
          "o|attempt_takeover:*staked_is_actively_voting — an external read" "p|attempt_takeover: calls _x_probe" "q|attempt_takeover: calls _x_probe" "r|attempt_takeover:*staked_is_actively_voting — an external read" \
          "s|attempt_takeover:*staked_is_actively_voting — an external read" "t|attempt_takeover:*staked_is_actively_voting — an external read"; do
    _o=$(s2_sb "$WORK/s-c7g-${_g%%|*}.sh"); _r=$?
    [[ $_r -ne 0 && "$_o" == *${_g#*|}* ]] || { c7g_t8=0; c7g_t8r="$c7g_t8r [${_g%%|*}: rc=$_r $(printf '%s' "$_o" | tr '\n' ';' | cut -c1-200)]"; }
done
if [[ $s2_rc -eq 0 && -z "$s2_out" && $s2p_rc -eq 0 && -z "$s2p_out" && $c7g_er -ne 0 && "$c7g_e" == *"attempt_safe_recovery:"*"_check_rpc_delinquency"* && "$s2_nsamp" == "13" && $c7g_ar -ne 0 && "$c7g_a" == *"check_primary_dropped_identity:"*"curl"* && $c7g_br -ne 0 && "$c7g_b" == *"tier2_check_delinquency:"* \
      && $c7g_cr -ne 0 && "$c7g_c" == *"check_primary_dropped_identity:"* && $c7g_dr -ne 0 && "$c7g_d" == *"attempt_takeover:"*"get_staked_liveness_sample"* && $c7g_t8 -eq 1 && $c7g_r6 -eq 1 && $c7g_r7 -eq 1 ]]; then
    ok "(7g) S2 census on bash's own parse of both daemons (bp_parse's commands and structure): walking each take-cycle function's statements in order (the standby's 10, $s2_nsamp statement sample sites; the PRIMARY's recovery pass) — if / case / loop / && || operands as the branches they are, a break / continue (behind && / || too, and break N / continue N) as the exit of the loop it leaves — every external read (a curl command that is not LOCAL — a LOCAL one: its one URL word \"\$LOCAL_RPC\" — the liveness sampler, a call to a caller-covered function; wherever bash runs it: a substitution, a \$((cmd) ), an unquoted here-document body) has an own-head sample since the previous read, a sample counting only as a statement run in the function's own shell (not an argument or a string, not behind command / builtin, not in a substitution, subshell, pipeline, background job or one arm, not an && / || right operand), a LOCAL read in between being a gap; over the call graph of every function the parse defines (standby $s2_sbf, $s2_sbr reading; primary $s2_prf, $s2_prr), no walked function calls a reading function outside the census's sets, no LOCAL-set function reads, a sender's curl sends only to its own endpoint; no shell is run as a command. Not seen (the header): a read a loop repeats, a read in the main loop's body, a network client other than curl, a command word assembled at run time, a string run by eval / trap / mapfile -C (the (0d) census's), a shell whose word is assembled at run time or that a tool runs itself (flock -c), code an interpreter runs from a string (awk's system(), perl -e, python3 -c); the per-cycle / per-pass samples are the worlds' (the header names which world pins each, and the one no world pins). Controls a–t, w1–w4, w01, w02, wsb (a shell behind nice --adjustment N, xargs --max-args N, stdbuf), ws (sixteen shells reading their stdin: -s, -e, -, --, -i, -l, --posix, --norc, env / timeout / busybox sh / /bin/sh / dash, a here-document and a redirection — each named, and in (1a) unparseable), wn (ten more by name or wrapper: ash, /bin/ash -c, hush, mksh, rbash, ksh93, env -S / -S'…' / --split-string='bash -s', sudo -s — each named, and in (1a) unparseable), s01–s06, s08, s14, s15, b16, b17, g1–g5 (each sample no world pins, guarded), g13 / g13if, P1 / P1if / P1or, P3 / P3if, P5 / P5and, Pdeep, Pvar and T2 / T2if (a loop left by a conditional break or continue, or by break N), each red; s13 (the sample first in an || list: it runs) and P5b1 (a plain break out of an inner loop, the sample after it) green, and wsv (bash --version, bash --help) and wnv (env -S 'printf x', sudo -u nobody printf x, env -u FOO printf x) green on (7g) and (1a)"
else
    bad "(7g) S2 census rc=$s2_rc samples=$s2_nsamp :: $s2_out :: primary rc=$s2p_rc $s2p_out e=$c7g_er[$c7g_e] :: controls a=$c7g_ar[$c7g_a] b=$c7g_br[$c7g_b] c=$c7g_cr[$c7g_c] d=$c7g_dr[$c7g_d] :: T8:$c7g_t8r :: fix round 6:$c7g_r6r :: fix round 7:$c7g_r7r"
fi
# (7g-local) where bash's parse WRITES LOCAL_RPC (the LOCAL rule above trusts the name): pinned — its default, at the file
# level (the operator's config may set it; it is sourced there). Red first on the delta panel 4's T4-7G-LOCALNAME shapes,
# each green on fix round 4's censuses: u `local LOCAL_RPC="$TIER2_RPC"` at the head of local_check_delinquency (a
# LOCAL-set function), v `LOCAL_RPC="$TIER2_RPC"` as startup_checks' last statement (every later LOCAL read — the veto's
# own — then reads TIER2). Red first on the delta panel 5's TS5-7GLOCAL-ANYWHERE shapes, each green on fix round 5's census
# and each a write bash makes in the current shell, at the head of local_check_delinquency: x1 a here-string, x2 a
# redirection target, x3 a case pattern, x4 an unquoted here-document body (each holding ${LOCAL_RPC:=$TIER2_RPC}), x5
# printf -vLOCAL_RPC. LIMIT: LOCALW_AWK's (an arithmetic write — let, (( )), $(( )); a name computed at run time —
# printf -v "$n", ${!n}; a string handed to eval, which the (0d) census flags).
LOCALW_PIN='(top):LOCAL_RPC=http://127.0.0.1:8899;'
lw_rows=""; lw_ok=1
for _d in "$STANDBY" "$PRIMARY"; do _lw=$(awk -F'\t' "$LOCALW_AWK" "$(ovp "$_d")/lex" | tr '\n' ';'); lw_rows="$lw_rows $(basename "$_d" .sh):[$_lw]"; [[ "$_lw" == "$LOCALW_PIN" ]] || lw_ok=0; done
ev_mut "$STANDBY" "local_check_delinquency() {" after "$WORK/s-c7g-u.sh" <<'EOB'
    local LOCAL_RPC="$TIER2_RPC"
EOB
rd_mut "$STANDBY" "$WORK/s-c7g-v.sh" tail:startup_checks <<'EOB'
    LOCAL_RPC="$TIER2_RPC"
EOB
printf '%s\n' '    read -r _x <<< "${LOCAL_RPC:=$TIER2_RPC}"' | ev_mut "$STANDBY" "local_check_delinquency() {" after "$WORK/s-c7g-x1.sh"
printf '%s\n' '    : > "/dev/null${LOCAL_RPC:=$TIER2_RPC}"' | ev_mut "$STANDBY" "local_check_delinquency() {" after "$WORK/s-c7g-x2.sh"
printf '%s\n' '    case x in ${LOCAL_RPC:=$TIER2_RPC}) : ;; esac' | ev_mut "$STANDBY" "local_check_delinquency() {" after "$WORK/s-c7g-x3.sh"
printf '%s\n' '    cat > /dev/null <<EOS' '${LOCAL_RPC:=$TIER2_RPC}' 'EOS' | ev_mut "$STANDBY" "local_check_delinquency() {" after "$WORK/s-c7g-x4.sh"
printf '%s\n' '    printf -vLOCAL_RPC %s "$TIER2_RPC"' | ev_mut "$STANDBY" "local_check_delinquency() {" after "$WORK/s-c7g-x5.sh"
for _x in u v x1 x2 x3 x4 x5; do
    [[ -s "$WORK/s-c7g-$_x.sh" ]] && ! cmp -s "$STANDBY" "$WORK/s-c7g-$_x.sh" || { lw_rows="$lw_rows $_x:NOT-BUILT"; lw_ok=0; continue; }
    _lw=$(awk -F'\t' "$LOCALW_AWK" "$(ovp "$WORK/s-c7g-$_x.sh")/lex" | tr '\n' ';')
    if [[ "$_lw" != "$LOCALW_PIN" ]]; then lw_rows="$lw_rows $_x:red[${_lw#"$LOCALW_PIN"}]"; else lw_rows="$lw_rows $_x:GREEN"; lw_ok=0; fi
done
if [[ $lw_ok -eq 1 ]]; then
    ok "(7g-local) LOCAL_RPC is written exactly once in each daemon, on bash's own parse — its default at the file level (an assignment word of any command; the name as an argument of local / declare / export / read / unset / printf, its -vNAME too / for …; a \${LOCAL_RPC:=…} wherever bash expands one: a command word, a redirection target or a here-string, a case pattern, an unquoted here-document body); not seen: an arithmetic write, a name computed at run time, eval (the (0d) census's):$lw_rows"
else
    bad "(7g-local) LOCAL_RPC write sites:$lw_rows (want each daemon [$LOCALW_PIN] and u / v / x1–x5 red)"
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
    ok "(7e) RED FIRST (the panel's L3): a node run with --health-check-slot-distance 64, the spare replaying 44 s (110 slots) behind: agave reports it 'behind by 110'; the 6.3.1 build's 128 cap admitted it and took at t170 with the holder voting for 40 s (RESUME t130; 30 s at t140); the 6.3 build (default 100) held. Now every 'behind' report fails Tier-1 (Tier-1 is ready only on getHealth's ok: LOCAL_HEALTH_MAX_BEHIND enters no decision — fix round 2, S5): Tier-1 BEHIND from t0, no take — never looser than the 6.3 build at any distance (test_config_drift (h4)/(h5))"
else
    bad "(7e) L3 dist64=$(wr dist64 | cut -c1-200) :: resume140=$(wf dist64r mutation)"
fi

rm -rf "$WORK"
results_banner
