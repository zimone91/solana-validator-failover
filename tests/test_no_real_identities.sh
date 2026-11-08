#!/bin/bash
# v0.7.0 (F25): NO REAL IDENTITY IN THE PUBLIC TREE. The repository's rule is that no real identifier of a node or of a person - the validator, vote-account or fee-payer address - sits in a public file.
# Until v0.7.0 one suite (tests/test_unknown_identity_alert.sh) carried the real identity of a mainnet node as its fixture, in two lines: on-chain it is public, but the fixture tied the author's
# infrastructure to that address and nothing would have stopped the next one. Now: the suites take a SYNTHETIC identity from tests/lib/fixtures.sh (FX_IDENTITY_A), and THIS suite fails on any
# base58 literal of 43 or 44 characters - the length of a Solana address - under tests/, docs/ or in README.md, SECURITY.md, CHANGELOG.md and the two *.example templates that is not a row of
# tests/fixtures-allowlist.txt (program ids, feature ids, genesis hashes, synthetic fixtures - each row with a one-word reason). A literal is a MAXIMAL run of base58 characters (no 0, O, I, l): a
# 45-character run, or a literal glued to more letters, is not an address. The shipped scripts are outside the rule: the two wizards print the author's published validator in their banner, by design.
# The suite never prints a literal it flags: file, line, the first four characters and the length - the job logs of a public repository are public.
#   (0)  the allowlist: every row is "<literal> <reason>", a 43/44-character base58 literal, one of four reasons, no duplicates
#   (1)  the REAL tree: every literal the rule finds is a row (and the scan is not vacuous: it reads the files of both directories and the top-level pages)
#   (2)  the fixture: FX_IDENTITY_A is a 43/44-character base58 string, is a "synthetic" row, and the suite that used to carry the real identity uses it
#   (3)  CONTROLS (planted trees): a literal in a test file, in a doc, in README.md, SECURITY.md, CHANGELOG.md and a template is found, with its line; 43 and 44 are found, 42 and 45 are not; a literal
#        glued to more base58 characters is not an address, one next to _ or 0 is; a row passes it; the allowlist file is not scanned against itself; bad rows are named; the output never holds the
#        literal; the real suite with its fixture swapped back for a literal is found twice
# RED ON THE BASE (rc2 c92450e + this suite + its allowlist): (1) finds 2 unlisted literals, both in tests/test_unknown_identity_alert.sh, and (2) finds no fixtures library.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, mutate().
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "No real identity in the public tree: every 43/44-character base58 literal is on the allowlist (v0.7.0 F25)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/nri.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
ALLOW="$HARNESS_DIR/tests/fixtures-allowlist.txt"
REASONS="synthetic program-id feature-id genesis-hash"
B58='[1-9A-HJ-NP-Za-km-z]'

# ── the rule ────────────────────────────────────────────────────────────────────────────────────────────────
# scan_files <root> -> the files the rule covers, one per line: everything under tests/ and docs/ (the allowlist itself excluded), the top-level pages and the *.example templates.
scan_files() {
    local root="$1" f
    {
        find "$root/tests" "$root/docs" -type f 2>/dev/null
        for f in "$root/README.md" "$root/SECURITY.md" "$root/CHANGELOG.md" "$root"/*.example; do [[ -f "$f" ]] && echo "$f"; done
    } | grep -v '/tests/fixtures-allowlist\.txt$' | LC_ALL=C sort
}
# literals <file> -> "<file>:<line>:<literal>" for every MAXIMAL run of base58 characters that is exactly 43 or 44 long (LC_ALL=C: a range like A-H must not take lower-case letters in a locale's collation).
literals() {
    LC_ALL=C awk '{ line = $0
                    while (match(line, /[1-9A-HJ-NP-Za-km-z]+/)) {
                        w = substr(line, RSTART, RLENGTH)
                        if (length(w) == 43 || length(w) == 44) printf "%s:%d:%s\n", FILENAME, FNR, w
                        line = substr(line, RSTART + RLENGTH)
                    } }' "$1"
}
# unlisted <root> <allowlist> -> one line per literal that is not a row: "<file>:<line>: <first 4 characters>... (<n> chars)" - the literal itself is never printed.
unlisted() {
    local root="$1" allow="$2" f
    scan_files "$root" | while IFS= read -r f; do literals "$f"; done | LC_ALL=C awk -F: -v allow="$allow" '
        BEGIN { while ((getline row < allow) > 0) { if (row ~ /^#/ || row ~ /^[ \t]*$/) continue; split(row, a, " "); ok[a[1]] = 1 } }
        !($3 in ok) { printf "%s:%s: %s... (%d chars)\n", $1, $2, substr($3, 1, 4), length($3) }'
}
# bad_rows <allowlist> -> the malformed or duplicate rows: "<line>: <what is wrong>".
bad_rows() {
    LC_ALL=C awk -v reasons="$REASONS" '
        BEGIN { n = split(reasons, r, " "); for (i = 1; i <= n; i++) okr[r[i]] = 1 }
        /^#/ || /^[ \t]*$/ { next }
        { if (NF != 2) { printf "%d: not \"<literal> <reason>\"\n", NR; next }
          if ($1 !~ /^[1-9A-HJ-NP-Za-km-z]+$/ || (length($1) != 43 && length($1) != 44)) { printf "%d: the first field is not a 43/44-character base58 literal\n", NR; next }
          if (!($2 in okr)) { printf "%d: the reason is not one of: %s\n", NR, reasons; next }
          if ($1 in seen) { printf "%d: duplicate literal\n", NR; next }
          seen[$1] = 1 }' "$1"
}
expect() {   # expect <label> <got> <want>
    [[ "$2" == "$3" ]] && ok "$1 -> $2" || bad "$1: got [$2], want [$3]"
}
rep() { local n="$1" c="$2" out="" i; for ((i = 0; i < n; i++)); do out="$out$c"; done; printf '%s' "$out"; }   # rep <n> <char>

# ── (0) the allowlist ───────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (0) the allowlist ───"
if [[ -f "$ALLOW" ]]; then
    ok "(0a) tests/fixtures-allowlist.txt exists ($(grep -vc '^#\|^[[:space:]]*$' "$ALLOW") rows)"
else
    bad "(0a) tests/fixtures-allowlist.txt is missing"
fi
expect "(0b) malformed or duplicate rows" "$(bad_rows "$ALLOW" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" ""

# ── (1) the real tree ───────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) the real tree ───"
nfiles=$(scan_files "$HARNESS_DIR" | wc -l | tr -d ' ')
nt=$(scan_files "$HARNESS_DIR" | grep -c '/tests/'); nd=$(scan_files "$HARNESS_DIR" | grep -c '/docs/')
nlit=$(scan_files "$HARNESS_DIR" | while IFS= read -r f; do literals "$f"; done | cut -d: -f3 | LC_ALL=C sort -u | wc -l | tr -d ' ')
if [[ "$nt" -ge 40 && "$nd" -ge 5 ]] && scan_files "$HARNESS_DIR" | grep -q '/README.md$' && scan_files "$HARNESS_DIR" | grep -q '/SECURITY.md$' \
   && scan_files "$HARNESS_DIR" | grep -q '/CHANGELOG.md$' && [[ "$(scan_files "$HARNESS_DIR" | grep -c '\.example$')" == "2" ]]; then
    ok "(1a) the scan is not vacuous: $nfiles files ($nt under tests/, $nd under docs/, README.md, SECURITY.md, CHANGELOG.md, 2 templates), $nlit distinct 43/44-character literals"
else
    bad "(1a) the scan reads too little: $nfiles files ($nt under tests/, $nd under docs/)"
fi
un=$(unlisted "$HARNESS_DIR" "$ALLOW")
expect "(1b) literals that are not rows of the allowlist" "$(printf '%s' "$un" | grep -c .)" "0"
[[ -z "$un" ]] || printf '%s\n' "$un" | sed 's/^/        unlisted: /'

# ── (2) the fixture ─────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (2) the fixture ───"
FIXLIB="$HARNESS_DIR/tests/lib/fixtures.sh"
if [[ -f "$FIXLIB" ]]; then
    # shellcheck disable=SC1090
    source "$FIXLIB"
    if printf '%s' "$FX_IDENTITY_A" | LC_ALL=C grep -qE "^${B58}{43,44}$"; then
        ok "(2a) FX_IDENTITY_A is a 43/44-character base58 string (${#FX_IDENTITY_A} characters)"
    else
        bad "(2a) FX_IDENTITY_A is not a 43/44-character base58 string"
    fi
    expect "(2b) FX_IDENTITY_A is a 'synthetic' row of the allowlist" "$(grep -c "^$FX_IDENTITY_A synthetic\$" "$ALLOW" 2>/dev/null)" "1"
else
    bad "(2a) tests/lib/fixtures.sh is missing"; bad "(2b) no fixture to look up"
fi
expect "(2c) the suite that carried the real identity takes the fixture (uses of FX_IDENTITY_A beyond the import)" "$(grep -c 'FX_IDENTITY_A' "$HARNESS_DIR/tests/test_unknown_identity_alert.sh")" "3"

# ── (3) controls ────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (3) CONTROLS: planted trees ───"
L44=$(rep 44 K); L43=$(rep 43 K); L45=$(rep 45 K); L42=$(rep 42 K)
mkworld() { local w="$WORK/$1"; mkdir -p "$w/tests" "$w/docs"; printf '%s' "$w"; }
w=$(mkworld c1); printf '#!/bin/bash\nX=1\nCURRENT_IDENTITY="%s"\n' "$L44" > "$w/tests/x.sh"
o=$(unlisted "$w" /dev/null)
expect "(3a) a 44-character literal in a test file is found, with file and line, as first 4 characters + length" "$(printf '%s' "$o" | sed "s|$w/||")" "tests/x.sh:3: KKKK... (44 chars)"
expect "(3b) ... and the output never holds the literal itself" "$(printf '%s' "$o" | grep -c "$L44")" "0"
w=$(mkworld c2); printf '# t\n\nThe node %s is the one.\n' "$L44" > "$w/docs/y.md"
expect "(3c) a literal in a doc is found, on its line" "$(unlisted "$w" /dev/null | sed "s|$w/||")" "docs/y.md:3: KKKK... (44 chars)"
w=$(mkworld c3); n=0
for f in README.md SECURITY.md CHANGELOG.md failover.env.example; do printf 'line\n%s\n' "$L44" > "$w/$f"; done
expect "(3d) a literal in README.md, SECURITY.md, CHANGELOG.md and a *.example template is found (4 files)" "$(unlisted "$w" /dev/null | cut -d: -f1 | sed "s|$w/||" | tr '\n' ' ')" "CHANGELOG.md README.md SECURITY.md failover.env.example "
w=$(mkworld c4); printf '%s\n%s\n%s\n%s\n' "$L43" "$L44" "$L42" "$L45" > "$w/tests/len.txt"
expect "(3e) 43 and 44 characters are found, 42 and 45 are not" "$(unlisted "$w" /dev/null | sed "s|$w/||" | tr '\n' ' ')" "tests/len.txt:1: KKKK... (43 chars) tests/len.txt:2: KKKK... (44 chars) "
w=$(mkworld c5); printf 'a_%s_b\n%sabc\n0%s0\n' "$L44" "$L44" "$L44" > "$w/tests/glue.txt"
expect "(3f) next to _ or 0 a literal is found (line 1 and 3); glued to more base58 characters it is a 47-character run, not an address (line 2)" "$(unlisted "$w" /dev/null | sed "s|$w/||" | cut -d: -f2 | tr '\n' ' ')" "1 3 "
w=$(mkworld c6); printf '%s\n' "$L44" > "$w/tests/x.sh"; printf '# allowed\n%s synthetic\n' "$L44" > "$w/allow.txt"
expect "(3g) a row of the allowlist passes the literal" "$(unlisted "$w" "$w/allow.txt" | grep -c .)" "0"
w=$(mkworld c7); printf '%s synthetic\n' "$L44" > "$w/tests/fixtures-allowlist.txt"
expect "(3h) the allowlist file itself is not scanned" "$(unlisted "$w" "$w/tests/fixtures-allowlist.txt" | grep -c .)" "0"
printf '%s real\n%s synthetic\n%s synthetic\n%s synthetic extra\n%s synthetic\n' "$L44" "$L44" "$L44" "$L44" "$L42" > "$WORK/badrows.txt"
expect "(3i) bad rows are named: an unknown reason, a duplicate, a third field, a 42-character literal" "$(bad_rows "$WORK/badrows.txt" | cut -d: -f1 | tr '\n' ' ')" "1 3 4 5 "
# the real suite that carried the real identity, its fixture swapped back for a literal: found twice
w=$(mkworld c8); cp "$HARNESS_DIR/tests/test_unknown_identity_alert.sh" "$w/tests/test_unknown_identity_alert.sh"
mutate "$w/tests/test_unknown_identity_alert.sh" "s/CURRENT_IDENTITY=\"\\\$FX_IDENTITY_A\"/CURRENT_IDENTITY=\"$L44\"/" "$w/tests/mut.sh" && cp "$w/tests/mut.sh" "$w/tests/test_unknown_identity_alert.sh" && rm "$w/tests/mut.sh"
expect "(3j) the suite with its fixture swapped back for a literal: 2 literals found" "$(unlisted "$w" "$ALLOW" | grep -c 'test_unknown_identity_alert.sh')" "2"

results_banner
