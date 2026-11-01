#!/bin/bash
# v0.7 (AG-1.3): the vote-history file and the tower are CLASSIFIED and LOGGED, never touched.
# History: v0.6.0 — a static regression test of the --require-tower removal that also pinned "the PRIMARY DELETES the staked
# tower on switch-to-unstaked". Alpenglow (active on every public cluster, DESIGN-AG §1.2) replaces the tower with
# <ledger>/vote_history-<node pubkey>.bin, which a WARM swap copies from the old holder to the new one and which a cold take
# can never get back: FO deletes, moves, copies or rewrites neither file. The deletion is gone, and with it TOWER_PATH,
# detect_tower_base and get_tower_path; a CONFIRMED demote logs the history file's class and sha256.
#   (1) no '--require-tower' on a set-identity command (kept from v0.6.0)
#   (2) the staked set-identity takes the key as a PATH argument (kept)
#   (3) the tower knobs are gone: TOWER_PATH, _cached_tower_base, get_tower_path, detect_tower_base, tower-1_9 occur in no shipped file
#   (4) _vh_class / _sha256_of against independent tools: absent, present (mtime, size, sha256), present-and-older-than-episode,
#       unavailable (…), a read-only look — nothing about the file or its directory changes
#   (5) the REAL demotes (the primary's switch_to_unstaked, the standby's give_back_identity) over a scratch ledger: the tower file
#       and the history file keep their bytes, mtime and directory entry, and the log carries the class and the sha256
#       RED ON THE BASE (fd4ee8c): the tower is deleted by the primary's demote and no line carries the class
#   (6) the CENSUS by bash's own parse of the eight shipped scripts: no rm, mv, cp, truncate, tee, dd, ln, shred, install, unlink,
#       rsync, scp or touch, no in-place sed/perl/ed/ex, no find -delete/-exec, and no output redirection takes a path built from
#       vote_history, the tower or LEDGER_PATH — directly, or through a variable assigned from one
#   (7) CONTROLS (mutate()): the tower deletion put back, a history deletion / touch inside _vh_class, the log call dropped, and
#       five planted mutations the census must see (rm, an aliased mv, a redirection, truncate, the old tower_file shape)
#   (8) the scripts pass bash -n (kept)
# LIMITS, named: the census reads command WORDS and redirection targets — a path assembled in a variable through more than the
# two assignment passes below, a verb assembled at run time, or a destructive tool outside the list (python3 -c, an awk system())
# is not seen; the fence scripts do not log the class after their demote (a holder-slice item).
#
# harness: tests/lib/harness.sh — ok/bad+banners, paths, field, mutate, bp_parse/BP_AWK_LIB (the structural suites keep their
# local assert_absent/assert_present).
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

assert_absent() {   # desc, ERE pattern, file
    if grep -Eq "$2" "$3"; then echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1));
    else echo "  ✅ PASS: $1"; PASS=$((PASS+1)); fi
}
assert_present() {  # desc, fixed string, file
    if grep -Fq "$2" "$3"; then echo "  ✅ PASS: $1"; PASS=$((PASS+1));
    else echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); fi
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/th.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
SHIPPED="$HARNESS_DIR/install.sh $PRIMARY $STANDBY $HARNESS_DIR/deploy-failover.sh $HARNESS_DIR/deploy-failover-standby.sh $HARNESS_DIR/failover-arm.sh $HARNESS_DIR/systemd/failover-fence.sh $HARNESS_DIR/systemd/failover-fence-page-only.sh"

title_banner "Vote-history and tower handling (v0.6.0 static + v0.7 AG-1.3: never touched)"

echo ""
echo "─── 1. No '--require-tower' on the set-identity command ───"
# Match only the actual command line (has agave-validator); our explanatory comments
# mention --require-tower but never on a line that also runs agave-validator.
assert_absent "PRIMARY: set-identity has no --require-tower" 'agave-validator.*set-identity --require-tower' "$PRIMARY"
assert_absent "STANDBY: set-identity has no --require-tower" 'agave-validator.*set-identity --require-tower' "$STANDBY"

echo ""
echo "─── 2. Staked set-identity uses path-as-argument ───"
assert_present 'PRIMARY: set-identity "$STAKED_KEYPAIR"' 'set-identity "$STAKED_KEYPAIR"' "$PRIMARY"
assert_present 'STANDBY: set-identity "$STAKED_KEYPAIR"' 'set-identity "$STAKED_KEYPAIR"' "$STANDBY"

echo ""
echo "─── 3. The tower knobs are gone (v0.7 AG-1.3) ───"
TOWER_IDS='TOWER_PATH|_cached_tower_base|get_tower_path|detect_tower_base|tower-1_9'
tower_hits() {   # tower_hits <file…> → "<file>:<count>" for every file naming one of the retired identifiers
    local f n out=""
    for f in "$@"; do n=$(grep -Ec "$TOWER_IDS" "$f"); [[ "$n" != "0" ]] && out="$out $(basename "$f"):$n"; done
    printf '%s' "$out"
}
ENVS="$HARNESS_DIR/failover.env.example $HARNESS_DIR/failover-standby.env.example"
h=$(tower_hits $SHIPPED $ENVS)
[[ -z "$h" ]] \
    && ok "(3a) no shipped script or env template names TOWER_PATH, _cached_tower_base, get_tower_path, detect_tower_base or tower-1_9 (the v0.6 primary demote's deletion and its helpers are gone)" \
    || bad "(3a) a retired tower identifier is still named:$h"
assert_absent '(3b) PRIMARY: no `rm -f "$tower_file"` (the demote no longer deletes the staked tower)' 'rm -f "\$tower_file"' "$PRIMARY"
m="$WORK/m3.sh"
if mutate "$PRIMARY" 's/^LEDGER_PATH=""/TOWER_PATH=""; LEDGER_PATH=""/' "$m"; then
    h=$(tower_hits "$m")
    [[ -n "$h" ]] && ok "(3c) CONTROL: a mutant that brings the TOWER_PATH knob back is seen by the same check ($h )" || bad "(3c) the control did not bite"
fi

# ── (4) _vh_class and _sha256_of against independent tools ────────────────────────────────────────
echo ""
echo "─── 4. _vh_class: absent / present / present-and-older-than-episode / unavailable — and nothing about the file changes ───"
sha_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
vhc() {   # vhc <script> <mode> [episode] → _vh_class's line (or a probe's record) in a scratch ledger; modes: absent file dir link emptyledger nopub nohash
    local script="$1" mode="$2" ep="${3:-}"
    (
        set +e
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        D=$(mktemp -d "${TMPDIR:-/tmp}/vh.XXXXXX"); trap 'rm -rf "$D"' EXIT
        LEDGER_PATH="$D/ledger"; mkdir -p "$LEDGER_PATH"; STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"
        VH="$LEDGER_PATH/vote_history-$STAKED_PUBKEY.bin"
        case "$mode" in
            file|nohash|keep) printf 'vote history bytes\n' > "$VH"; TZ=UTC touch -t 202001010000 "$VH" ;;
            dir)  mkdir "$VH" ;;
            link) ln -s "$D/nowhere" "$VH" ;;
            emptyledger) LEDGER_PATH="" ;;
            nopub) STAKED_PUBKEY="" ;;
        esac
        [[ "$mode" == "nohash" ]] && _sha256_of() { return 1; }
        _watchdog_pet() { :; }; log_info() { :; }; log_warn() { :; }; log_error() { :; }
        if [[ "$mode" == "keep" ]]; then
            b_ls=$(ls -A "$LEDGER_PATH" | tr '\n' ','); b_sha=$(sha_of "$VH"); b_mt=$(_vh_class | sed 's/.*mtime=\([0-9]*\).*/\1/')
            _vh_class > /dev/null; _vh_class 1900000000 > /dev/null; _vh_log_after_demote "a probe" 2>/dev/null
            a_ls=$(ls -A "$LEDGER_PATH" | tr '\n' ','); a_sha=$(sha_of "$VH")
            printf 'ls=%s|sha=%s|mt=%s|sz=%s' "$([[ "$a_ls" == "$b_ls" ]] && echo same || echo "CHANGED:$b_ls->$a_ls")" "$([[ "$a_sha" == "$b_sha" ]] && echo same || echo CHANGED)" "$b_mt" "$(wc -c < "$VH" | tr -d ' ')"
        else
            _vh_class $ep
        fi
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(basename "$scr" | sed 's/solana-\(.*\)-failover.sh/\1/')
    # the independent expectation: the same bytes through the system's own hasher; the mtime fixed by `touch -t` under TZ=UTC
    exp=$(mktemp "$WORK/exp.XXXXXX"); printf 'vote history bytes\n' > "$exp"; esha=$(sha_of "$exp"); rm -f "$exp"
    [[ "$(vhc "$scr" absent)" == "absent" ]] \
        && ok "(4a:$n) no file → 'absent'" || bad "(4a:$n) absent misread: '$(vhc "$scr" absent)'"
    r=$(vhc "$scr" file)
    [[ "$r" == "present (mtime=1577836800 size=19 sha256=$esha)" ]] \
        && ok "(4b:$n) a file → present (mtime=1577836800 size=19 sha256=<the system hasher's>)" || bad "(4b:$n) present misread: '$r' (want sha256=$esha)"
    r=$(vhc "$scr" file 1600000000)
    [[ "$r" == "present-and-older-than-episode (mtime=1577836800 size=19 sha256=$esha episode-start=1600000000)" ]] \
        && ok "(4c:$n) mtime before the episode's first sample → present-and-older-than-episode, the episode start named" || bad "(4c:$n) older-than-episode misread: '$r'"
    r=$(vhc "$scr" file 1500000000)
    [[ "$r" == "present (mtime=1577836800 size=19 sha256=$esha episode-start=1500000000)" ]] \
        && ok "(4d:$n) mtime after the episode's first sample → plain present (a file written during the episode is not old)" || bad "(4d:$n) newer-than-episode misread: '$r'"
    r=$(vhc "$scr" file 1577836800)
    [[ "$r" == "present (mtime=1577836800 size=19 sha256=$esha episode-start=1577836800)" ]] \
        && ok "(4e:$n) mtime == the episode start is NOT older (strict <)" || bad "(4e:$n) boundary misread: '$r'"
    [[ "$(vhc "$scr" emptyledger)" == "unavailable (LEDGER_PATH empty)" ]] \
        && ok "(4f:$n) empty LEDGER_PATH → 'unavailable (LEDGER_PATH empty)'" || bad "(4f:$n) empty ledger misread: '$(vhc "$scr" emptyledger)'"
    [[ "$(vhc "$scr" nopub)" == "unavailable (staked pubkey unknown)" ]] \
        && ok "(4g:$n) no staked pubkey → 'unavailable (staked pubkey unknown)'" || bad "(4g:$n) no-pubkey misread: '$(vhc "$scr" nopub)'"
    [[ "$(vhc "$scr" dir)" == "unavailable (not a regular file)" ]] \
        && ok "(4h:$n) a directory under the file's name → 'unavailable (not a regular file)' (never hashed, never entered)" || bad "(4h:$n) directory misread: '$(vhc "$scr" dir)'"
    [[ "$(vhc "$scr" link)" == "absent" ]] \
        && ok "(4i:$n) a dangling symlink → 'absent' (the file a validator would open is not there)" || bad "(4i:$n) dangling link misread: '$(vhc "$scr" link)'"
    r=$(vhc "$scr" nohash)
    [[ "$r" == "present (mtime=1577836800 size=19 sha256=unreadable)" ]] \
        && ok "(4j:$n) the hasher fails → the line still goes out with sha256=unreadable" || bad "(4j:$n) failed hash misread: '$r'"
    r=$(vhc "$scr" keep)
    [[ "$r" == "ls=same|sha=same|mt=1577836800|sz=19" ]] \
        && ok "(4k:$n) three _vh_class calls and a demote log line leave the directory entries, the bytes, the mtime and the size as they were" || bad "(4k:$n) the look changed something: $r"
    r=$(
        set +e
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$scr" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        f=$(mktemp "$WORK/abc.XXXXXX"); printf 'abc' > "$f"
        a=$(_sha256_of "$f"); ra=$?
        b=$(PATH=/nonexistent _sha256_of "$f"); rb=$?
        printf 'known=%s rc=%s|nobin=%s rc=%s' "$a" "$ra" "$b" "$rb"
    )
    [[ "$r" == "known=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad rc=0|nobin= rc=1" ]] \
        && ok "(4l:$n) _sha256_of: the FIPS 180-2 test vector 'abc' hashes right; with no hashing tool on PATH it prints nothing and returns 1" || bad "(4l:$n) _sha256_of misread: $r"
done

# ── (5) the REAL demotes over a scratch ledger ─────────────────────────────────────────────────────
echo ""
echo "─── 5. The real demotes: the tower file and the history file are left as they were; the log carries the class and the sha256 ───"
# dw <script> <demote function> → one record. The scratch ledger holds a tower file AND a vote-history file for the staked
# identity (fixed mtime). `_cached_tower_base` points at the ledger: on the base (v0.6) that variable is what made
# get_tower_path name the tower file, so the base DELETES it; the new code has no such variable and ignores it.
dw() {
    local script="$1" fn="$2"
    (
        set +e
        SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$script" > "$SRC"
        # shellcheck disable=SC1090
        source "$SRC" 2>/dev/null; rm -f "$SRC"
        D=$(mktemp -d "${TMPDIR:-/tmp}/dw.XXXXXX"); trap 'rm -rf "$D"' EXIT
        LEDGER_PATH="$D/ledger"; mkdir -p "$LEDGER_PATH"
        STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"; UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
        TW="$LEDGER_PATH/tower-1_9-$STAKED_PUBKEY.bin"; VH="$LEDGER_PATH/vote_history-$STAKED_PUBKEY.bin"
        printf 'tower bytes\n' > "$TW"; printf 'vote history bytes\n' > "$VH"; TZ=UTC touch -t 202001010000 "$TW" "$VH"
        _cached_tower_base="$LEDGER_PATH"
        UNSTAKED_KEYPAIR="$D/unstaked.json"; echo '[4,5,6]' > "$UNSTAKED_KEYPAIR"; STAKED_KEYPAIR="$D/staked.json"; echo '[1,2,3]' > "$STAKED_KEYPAIR"
        SOLANA_PATH="/mock"; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15; DRY_RUN=false; ALERT_THROTTLE=0; LAST_SWITCH_TIME=0; STAT_SWITCHES=0
        CURRENT_IDENTITY="$STAKED_PUBKEY"; TG_ENABLED=false; SELF_FENCE_HARD_STOP=true
        LOGF="$D/log"; ALF="$D/alerts"; : > "$LOGF"; : > "$ALF"
        log_info() { printf 'INFO %s\n' "$*" >> "$LOGF"; }; log_warn() { printf 'WARN %s\n' "$*" >> "$LOGF"; }; log_error() { printf 'ERROR %s\n' "$*" >> "$LOGF"; }
        send_telegram() { return 0; }; send_webhook() { :; }; save_state() { :; }; sleep() { :; }; mono_now() { echo 1000; }; _watchdog_pet() { :; }
        alert() { printf '%s\n' "${3:-}" >> "$ALF"; }
        # the admin-socket calls are mocked away (rc 0, no output); the hashing the daemon bounds with `timeout` passes through
        timeout() { case "$*" in *agave-validator*|*fdctl*|*systemctl*) return 0 ;; esac; shift 3; command "$@"; }
        get_local_identity() { echo "$UNSTAKED_PUBKEY"; }
        b_ls=$(ls -A "$LEDGER_PATH" | tr '\n' ','); b_tw=$(sha_of "$TW"); b_vh=$(sha_of "$VH")
        "$fn" "test: the world" > /dev/null 2>&1; rc=$?
        a_ls=$(ls -A "$LEDGER_PATH" | tr '\n' ',')
        tw="gone"; [[ -f "$TW" ]] && { tw="kept"; [[ "$(sha_of "$TW")" == "$b_tw" ]] || tw="CHANGED"; }
        vh="gone"; [[ -f "$VH" ]] && { vh="kept"; [[ "$(sha_of "$VH")" == "$b_vh" ]] || vh="CHANGED"; }
        mt=$(stat -c %Y "$VH" 2>/dev/null); case "$mt" in ''|*[!0-9]*) mt=$(stat -f %m "$VH" 2>/dev/null) ;; esac
        line=$(grep -F '[vote-history]' "$LOGF" | head -1 | sed 's/^INFO //')
        printf 'rc=%s|tower=%s|hist=%s|histmtime=%s|ls=%s|alert=%s|vh=%s\n' "$rc" "$tw" "$vh" "$mt" \
            "$([[ "$a_ls" == "$b_ls" ]] && echo same || echo "CHANGED:$b_ls->$a_ls")" "$(head -1 "$ALF")" "$line"
    )
}
ESHA_FILE=$(mktemp "$WORK/e.XXXXXX"); printf 'vote history bytes\n' > "$ESHA_FILE"; ESHA=$(sha_of "$ESHA_FILE")
check_world() {   # check_world <label> <record> <alert fragment> — the invariants of one demote
    local lab="$1" out="$2" alf="$3" vh
    vh=$(field "$out" vh)
    [[ "$(field "$out" rc)" == "0" && "$(field "$out" alert)" == *"$alf"* ]] \
        && ok "($lab-a) the demote itself still works: rc 0, the '$alf' page" || bad "($lab-a) the demote broke ($out)"
    [[ "$(field "$out" hist)" == "kept" && "$(field "$out" histmtime)" == "1577836800" && "$(field "$out" ls)" == "same" ]] \
        && ok "($lab-b) the vote-history file keeps its bytes and its mtime, and the ledger directory its entries" || bad "($lab-b) the demote touched the ledger ($out)"
    [[ "$vh" == *"vote_history-StakedPubkey111111111111111111111111111111.bin is present (mtime=1577836800 size=19 sha256=$ESHA)"* ]] \
        && ok "($lab-c) the log carries the history file's class and sha256 (the system hasher's value)" || bad "($lab-c) no class/sha line for the file a warm swap copies ($vh)"
}
for pair in "$PRIMARY:switch_to_unstaked:p5:SWITCHED TO UNSTAKED" "$STANDBY:give_back_identity:s5:GAVE BACK"; do
    IFS=: read -r scr fn lab alf <<< "$pair"
    out=$(dw "$scr" "$fn")
    check_world "$lab" "$out" "$alf"
    [[ "$(field "$out" tower)" == "kept" ]] \
        && ok "($lab-d) the tower file is still there, byte for byte (the v0.6 primary demote deleted it)" || bad "($lab-d) the tower file is '$(field "$out" tower)' after the demote"
done

# ── (6) the census, by bash's own parse ────────────────────────────────────────────────────────────
echo ""
echo "─── 6. Census (bash's parse of the eight shipped scripts): nothing deletes, moves, copies, truncates or redirects into a vote_history / tower / LEDGER_PATH path ───"
VH_AWK="$BP_AWK_LIB"'
function hit(s) { return (s ~ /vote_history|vote-history|tower|TOWER_PATH|LEDGER_PATH/) }
function tainted(s,   v) { for (v in TNT) if (index(s, "$" v) > 0 || index(s, "${" v) > 0) return 1; return 0 }
function bad(s) { return hit(s) || tainted(s) }
function strip(v) { gsub(/\$\([^)]*\)/, "", v); gsub(/`[^`]*`/, "", v); return v }   # a command substitution holds OUTPUT, not a path
FNR == 1 { pass++ }   # (the violations accumulate in VIOL: BP_AWK_LIB owns the global array V)
$1 == "C" {
    n = split($6, W, "\034")
    for (k = 1; k <= n; k++) {                                       # NAME=value / local NAME=value: a name holding a ledger path is TAINTED
        q = bpq(W[k])
        if (q ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/) { nm = q; sub(/\+?=.*$/, "", nm); val = bpr(W[k]); sub(/^[^=]*=/, "", val); if (bad(strip(val))) TNT[nm] = 1 }
    }
    if (pass < 2) next
    k = bpcmd(n, W); if (!k) next
    v = bpq(W[k]); sub(/^.*\//, "", v); mut = 0
    if (v ~ /^(rm|mv|cp|truncate|tee|dd|ln|shred|install|unlink|rsync|scp|touch)$/) mut = 1
    else if (v ~ /^(sed|perl|ed|ex)$/) { for (j = k + 1; j <= n; j++) { q = bpq(W[j]); if (q ~ /^-[A-Za-z]*i/ || q == "--in-place") mut = 1 } }
    else if (v == "find") { for (j = k + 1; j <= n; j++) { q = bpq(W[j]); if (q == "-delete" || q == "-exec" || q == "-execdir" || q == "-ok") mut = 1 } }
    if (!mut) next
    nmut++
    for (j = k + 1; j <= n; j++) if (bad(bpr(W[j]))) { VIOL = VIOL sprintf("%s:%d: %s %s\n", $2, $4, v, bpr(W[j])); break }
}
pass == 2 && $1 == "R" && $5 == "redir" && bad($6) { VIOL = VIOL sprintf("%s:%d: redirection to %s\n", $2, $4, $6) }
END { if (mode == "count") print nmut + 0; else printf "%s", VIOL }'
vh_scan() {   # vh_scan <file> [count] → the census lines of one script (empty = clean), or with `count` the number of mutating commands it examined; PARSE-FAIL when bash's print of it cannot be lexed
    local d="$WORK/p.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$RANDOM"
    mkdir -p "$d"
    bp_parse "$1" "$d" && [[ -s "$d/lex" ]] || { echo "PARSE-FAIL:$(basename "$1")"; return 0; }
    awk -F'\t' -v mode="${2:-scan}" "$VH_AWK" "$d/lex" "$d/lex"
}
all=""; for f in $SHIPPED; do s=$(vh_scan "$f"); [[ -n "$s" ]] && all="$all$(basename "$f")[$(printf '%s' "$s" | tr '\n' ';')]"; done
nmut=0; for f in $SHIPPED; do c=$(vh_scan "$f" count); case "$c" in ''|*[!0-9]*) nmut=-1000 ;; *) nmut=$((nmut + c)) ;; esac; done
[[ "$nmut" -ge 20 ]] \
    && ok "(6-nonvacuous) the census examined $nmut mutating commands (rm, mv, cp, tee, …) in the eight scripts — it reads them, it does not skip them" \
    || bad "(6-nonvacuous) the census examined only $nmut mutating commands — the reader is broken, not the scripts clean"
[[ -z "$all" ]] \
    && ok "(6a) the eight shipped scripts: no destructive verb, in-place edit or output redirection takes a vote_history / tower / LEDGER_PATH path (nor a variable assigned from one)" \
    || bad "(6a) a shipped script touches a ledger path: $all"

# ── (7) CONTROLS ───────────────────────────────────────────────────────────────────────────────────
echo ""
echo "─── 7. CONTROLS: each mutant must turn its case red ───"
# the demote worlds: the tower deletion put back (primary), the history file deleted / touched inside _vh_class (both), the log call dropped (both)
m="$WORK/c-tower.sh"
if mutate "$PRIMARY" 's/^\(    log_warn ">>> SWITCHING TO UNSTAKED.*\)$/\1; rm -f "${LEDGER_PATH}\/tower-1_9-${STAKED_PUBKEY}.bin"/' "$m"; then
    out=$(dw "$m" switch_to_unstaked)
    [[ "$(field "$out" tower)" == "gone" ]] && ok "(7a) CONTROL: with the old deletion put back the primary's world reports the tower GONE (case 5-d bites)" || bad "(7a) the tower control did not bite ($out)"
    s=$(vh_scan "$m")
    [[ "$s" == *"switch_to_unstaked:"*"rm"* ]] && ok "(7b) CONTROL: the census names the put-back deletion ($(printf '%s' "$s" | head -1))" || bad "(7b) the census missed the put-back tower deletion ($s)"
fi
for scr in "$PRIMARY" "$STANDBY"; do
    n=$(basename "$scr" | sed 's/solana-\(.*\)-failover.sh/\1/'); fn=switch_to_unstaked; [[ "$n" == "standby" ]] && fn=give_back_identity
    m="$WORK/c-vhrm-$n.sh"
    if mutate "$scr" 's/^\(    _h=\$(_sha256_of "\$_vp") || _h="unreadable"\)$/\1; rm -f "$_vp"/' "$m"; then
        out=$(dw "$m" "$fn")
        [[ "$(field "$out" hist)" == "gone" ]] && ok "(7c:$n) CONTROL: a _vh_class that deletes the file after hashing it: the world reports the history file GONE (5-b bites)" || bad "(7c:$n) the deletion control did not bite ($out)"
        s=$(vh_scan "$m"); [[ "$s" == *"_vh_class:"*"rm"* ]] && ok "(7d:$n) CONTROL: the census names it ($(printf '%s' "$s" | head -1))" || bad "(7d:$n) the census missed a deletion inside _vh_class ($s)"
    fi
    m="$WORK/c-vhtouch-$n.sh"
    if mutate "$scr" 's/^\(    _h=\$(_sha256_of "\$_vp") || _h="unreadable"\)$/\1; TZ=UTC touch -t 202101010000 "$_vp"/' "$m"; then
        out=$(dw "$m" "$fn")
        [[ "$(field "$out" histmtime)" != "1577836800" ]] && ok "(7e:$n) CONTROL: a _vh_class that touches the file: the world reports a moved mtime (5-b bites)" || bad "(7e:$n) the touch control did not bite ($out)"
    fi
    m="$WORK/c-nolog-$n.sh"
    if mutate "$scr" 's/^\(        \)_vh_log_after_demote "[^"]*"\(.*\)$/\1:\2/' "$m"; then
        out=$(dw "$m" "$fn")
        [[ -z "$(field "$out" vh)" ]] && ok "(7f:$n) CONTROL: with the log call dropped the world carries no class line (5-c bites)" || bad "(7f:$n) the log control did not bite ($out)"
    fi
done
# the census: five planted mutations in a copy of the primary, each of a different shape
plant() {   # plant <label> <replacement for the SWITCHING line's tail> <expected census fragment>
    local lab="$1" tail="$2" want="$3" mm="$WORK/c-plant-$1.sh" s
    if mutate "$PRIMARY" "s/^\\(    log_warn \">>> SWITCHING TO UNSTAKED.*\\)\$/\\1; $tail/" "$mm"; then
        s=$(vh_scan "$mm")
        [[ "$s" == *"$want"* ]] && ok "(7g:$lab) CONTROL: the census names the planted mutation ($(printf '%s' "$s" | head -1))" || bad "(7g:$lab) the census did not see the planted mutation (got '$s', want '$want')"
    fi
}
plant rm       'rm -f "$LEDGER_PATH\/vote_history-${STAKED_PUBKEY}.bin"' 'switch_to_unstaked:'
plant alias    '_vh_f="$LEDGER_PATH\/x.bin"; mv "$_vh_f" "$_vh_f.old"' 'mv'
plant redirect ': > "$LEDGER_PATH\/vote_history-${STAKED_PUBKEY}.bin"' 'redirection to'
plant truncate 'truncate -s 0 "$LEDGER_PATH\/vote_history-${STAKED_PUBKEY}.bin"' 'truncate'
plant oldshape 'tower_file="${LEDGER_PATH}\/tower-1_9-${STAKED_PUBKEY}.bin"; [[ -f "$tower_file" ]] \&\& rm -f "$tower_file"' 'rm'

echo ""
echo "─── 8. Scripts pass bash -n ───"
if bash -n "$PRIMARY" 2>/dev/null; then echo "  ✅ PASS: PRIMARY syntax"; PASS=$((PASS+1)); else echo "  ❌ FAIL: PRIMARY syntax"; FAIL=$((FAIL+1)); fi
if bash -n "$STANDBY" 2>/dev/null; then echo "  ✅ PASS: STANDBY syntax"; PASS=$((PASS+1)); else echo "  ❌ FAIL: STANDBY syntax"; FAIL=$((FAIL+1)); fi

results_banner
