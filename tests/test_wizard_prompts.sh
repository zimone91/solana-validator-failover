#!/bin/bash
# v0.7.0 (F23, F24): THE WIZARDS' YES/NO PROMPTS AND THEIR NEXT STEPS. F23: Measured on a live standby install (2026-11-05): a wrong-layout (Cyrillic) letter, a Backspace and an "n" left the two bytes d1 6e in the read; the old test
# `[[ "$yn" != "n" && "$yn" != "N" ]]` took every other answer as YES, the wizard printed "Loaded existing config", and the old env turned the DRY RUN default into false on a LIVE node. The same
# test sat in the primary wizard and in offer_start_service (any other byte started the service, any other byte enabled it at boot). Now ONE helper in each wizard, ask_yn "<prompt>" <y|n>:
# exactly y / Y / yes = yes, n / N / no = no, an empty line = the default (so is a Ctrl-D on the first ask), anything else is asked again ("answer y or n"), and the third unrecognised answer in a
# row - or a Ctrl-D after one - takes NO, which is the safe branch of every caller. The "Load existing values as defaults?" prompt now defaults to NO: an install over an old env opts IN to the old values.
#   (0)  structure: ask_yn is defined once in each wizard, the only `read -r yn` left is the helper's own, the four prompts go through it with their defaults (Load: n; Continue anyway: n; Start, Enable: y)
#   (a)  the REAL "existing config" fragment of each wizard, stdin driven: d1 6e -> not loaded and asked again; n -> not loaded; an empty line -> not loaded (the new default); y, Y, yes -> loaded;
#        no -> not loaded; three unrecognised answers -> not loaded and the wizard goes on; a Ctrl-D -> not loaded; YES is not an answer (asked again); a stray key then y -> loaded after ONE re-ask
#   (b)  the REAL interactive branch of offer_start_service (its tty guard cut out of a COPY, systemctl stubbed): defaults start and enable; n n starts nothing; d1 6e does NOT start;
#        three stray answers do NOT start; a stray start answer then a Ctrl-D does not start; three stray answers to the enable question do not enable
#   (c)  the REAL ask_path: "Continue anyway?" continues on y and on yes, asks again on a stray answer, re-asks the path on n
#   (d)  F24: the NEXT STEPS block of both wizards, RENDERED (the real echo lines, sleep stubbed): no `iptables` anywhere, the numbering 1-3 intact, the primary's item 2 says "Rehearse on a SPARE,
#        never on the holder" and points to docs/SAFETY.md "Rehearsing the self-fence", and that heading exists. The primary used to print `iptables -I OUTPUT 1 ! -o lo -j DROP; sleep 40; ...` as a
#        "simulated outage (DRY RUN)" after every install (seen on the mainnet holder 2026-11-06): the rule cuts the VALIDATOR's traffic, not the daemon's - on the node that holds the staked
#        identity that is a stretch without votes, and DRY_RUN gates only the daemon's action.
#   (e)  CONTROLS (mutate()): every mutant of the helper, of its callers and of the NEXT STEPS text turns its case red
# RED ON THE BASE (rc2, c92450e + this suite): ask_yn is not defined (0a), four bare `read -r yn` per wizard (0b), no prompt goes through it (0c); in (a) d1 6e, the empty line, no, three stray answers, a Ctrl-D (the wizard dies under
# set -e) and YES all LOAD; in (b) d1 6e and three stray answers START the service and a stray enable answer enables it; in (c) a stray answer and yes are not answers; in (d) the primary's NEXT
# STEPS prints the iptables line (one hit), prints no pointer, and docs/SAFETY.md has no such heading.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, mutate().
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Wizard yes/no prompts and next steps: only an explicit yes loads, starts, enables; no outage command (v0.7.0 F23, F24)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/wzp.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
DEPLOY_P="$HARNESS_DIR/deploy-failover.sh"; DEPLOY_S="$HARNESS_DIR/deploy-failover-standby.sh"
for f in "$DEPLOY_P" "$DEPLOY_S"; do [[ -f "$f" ]] || { echo "  ❌ missing $f"; exit 1; }; done
LOADQ='Load existing values as defaults?'

# ── the worlds ──────────────────────────────────────────────────────────────────────────────────────────────
# frag_world <script> <input> -> "loaded=<yes|no|none> asks=<n> says=<n> died=<0|1>": the wizard's own `if [[ -n "$EXISTING_ENV" ]]` fragment run under set -e (as the wizard runs it) with stdin from <input>
# (printf %b escapes; \0321 is the byte d1). asks = how many times the prompt was printed, says = how many "answer y or n" lines, died = 1 when the fragment never finished (the wizard would have exited).
frag_world() {
    local script="$1" input="$2" in="$WORK/in.$RANDOM$$" envf="$WORK/old.env" frag askyn out
    printf '%b' "$input" > "$in"
    printf 'FX_LOADED=yes\n' > "$envf"
    frag=$(sed -n '/^if \[\[ -n "\$EXISTING_ENV" \]\]; then$/,/^fi$/p' "$script")
    askyn=$(sed -n '/^ask_yn() {$/,/^}$/p' "$script")
    [[ -n "$frag" ]] || { echo "NO-FRAGMENT"; return 0; }
    out=$(
        exec < "$in" 2>&1
        set -e
        BOLD=""; NC=""; DIM=""; YELLOW=""; GREEN=""; RED=""; CYAN=""
        warn() { echo "WARN: $*"; }
        ok() { echo "OK: $*"; }
        if [[ -n "$askyn" ]]; then eval "$askyn"; fi
        EXISTING_ENV="$envf"; unset FX_LOADED
        eval "$frag"
        echo "RESULT loaded=${FX_LOADED:-no}"
    )
    local res; res=$(printf '%s\n' "$out" | sed -n 's/^.*RESULT loaded=\([a-z]*\)$/\1/p' | tail -1)
    printf 'loaded=%s asks=%s says=%s died=%s' "${res:-none}" "$(printf '%s' "$out" | grep -o "$LOADQ" | wc -l | tr -d ' ')" \
        "$(printf '%s' "$out" | grep -o 'answer y or n' | wc -l | tr -d ' ')" "$([[ -z "$res" ]] && echo 1 || echo 0)"
}

# start_world <script> <input> -> "start=<n> enable=<n>": the wizard's offer_start_service with its tty guard cut out of a COPY (the interactive branch needs a terminal), systemctl stubbed (the unit is
# inactive-enabled-no: is-enabled fails, so the enable question is asked), stdin from <input>.
start_world() {
    local script="$1" input="$2" in="$WORK/in.$RANDOM$$" logf="$WORK/sysctl.log" fn askyn
    printf '%b' "$input" > "$in"; : > "$logf"
    fn=$(sed -n '/^offer_start_service() {$/,/^}$/p' "$script" | sed 's/\[\[ ! -t 0 \]\]/false/')
    askyn=$(sed -n '/^ask_yn() {$/,/^}$/p' "$script")
    [[ -n "$fn" ]] && printf '%s' "$fn" | grep -q 'if false; then' || { echo "NO-FUNCTION-OR-GUARD"; return 0; }
    (
        set -e
        BOLD=""; NC=""; DIM=""; YELLOW=""; GREEN=""; RED=""; CYAN=""
        warn() { echo "WARN: $*"; }
        ok() { echo "OK: $*"; }
        systemctl() { echo "$*" >> "$logf"; case "$1" in is-enabled) return 1 ;; esac; return 0; }
        if [[ -n "$askyn" ]]; then eval "$askyn"; fi
        eval "$fn"
        offer_start_service "solana-failover" ""
    ) < "$in" > /dev/null 2>&1
    printf 'start=%s enable=%s' "$(grep -c '^start ' "$logf")" "$(grep -c '^enable ' "$logf")"
}

# path_world <script> <input> -> "reply=<value>|died": the wizard's ask / ask_path with stdin from <input>; the first existing file the world may return is $WORK/exists.
path_world() {
    local script="$1" input="$2" in="$WORK/in.$RANDOM$$" fns askyn out
    printf '%b' "$input" > "$in"; : > "$WORK/exists"
    fns=$(sed -n '/^ask() {$/,/^}$/p;/^ask_path() {$/,/^}$/p' "$script")
    askyn=$(sed -n '/^ask_yn() {$/,/^}$/p' "$script")
    out=$(
        exec < "$in" 2>&1
        set -e
        BOLD=""; NC=""; DIM=""; YELLOW=""; GREEN=""; RED=""; CYAN=""
        warn() { echo "WARN: $*"; }
        if [[ -n "$askyn" ]]; then eval "$askyn"; fi
        eval "$fns"
        ask_path "Keypair" "" true
        echo "REPLY=$REPLY"
    )
    printf '%s' "$(printf '%s\n' "$out" | sed -n 's/^.*REPLY=\(.*\)$/\1/p' | tail -1 | sed "s|$WORK|W|")"
}

# next_steps <script> -> the rendered text of the wizard's NEXT STEPS block: the real lines from the heading to the offer_start_service call, sleep stubbed, no colours.
next_steps() {
    local script="$1" blk
    blk=$(awk '/NEXT STEPS/ { on = 1 } /^offer_start_service "/ { on = 0 } on' "$script")
    [[ -n "$blk" ]] || { echo "NO-BLOCK"; return 0; }
    ( BOLD=""; NC=""; DIM=""; CYAN=""; YELLOW=""; GREEN=""; RED=""; sleep() { :; }; eval "$blk" 2>&1 )
}
ns_iptables() { next_steps "$1" | grep -c 'iptables'; }
ns_numbers()  { next_steps "$1" | grep -c '^  [123]\. '; }
ns_pointer()  { next_steps "$1" | grep -c 'Rehearsing the self-fence'; }

expect() {   # expect <label> <got> <want>
    [[ "$2" == "$3" ]] && ok "$1 -> $2" || bad "$1: got [$2], want [$3]"
}

# ── (0) structure ──────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (0) structure ───"
for pair in "primary:$DEPLOY_P" "standby:$DEPLOY_S"; do
    name=${pair%%:*}; f=${pair#*:}
    n=$(grep -c '^ask_yn() {$' "$f")
    [[ "$n" == "1" ]] && ok "(0a-$name) ask_yn is defined once" || bad "(0a-$name) ask_yn definitions: $n (want 1)"
    n=$(grep -c 'read -r yn' "$f"); m=$(sed -n '/^ask_yn() {$/,/^}$/p' "$f" | grep -c 'read -r yn')
    [[ "$n" == "1" && "$m" == "1" ]] && ok "(0b-$name) the only 'read -r yn' is the helper's own" || bad "(0b-$name) 'read -r yn': $n in the file, $m of them inside ask_yn (want 1 and 1: every yes/no goes through ask_yn)"
    c=0
    grep -qF 'ask_yn "Continue anyway? (y/N)" n' "$f" && c=$((c + 1))
    grep -qF 'ask_yn "Start ${unit} now? (Y/n)" y' "$f" && c=$((c + 1))
    grep -qF 'ask_yn "Enable ${unit} at boot? (Y/n)" y' "$f" && c=$((c + 1))
    grep -qF "ask_yn \"$LOADQ (y/N)\" n" "$f" && c=$((c + 1))
    [[ "$c" == "4" ]] && ok "(0c-$name) the four prompts go through ask_yn with their defaults (Continue n, Start y, Enable y, Load n)" || bad "(0c-$name) $c/4 prompts are ask_yn calls with the expected default"
done

# ── (a) the "existing config" fragment ─────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (a) the existing-config prompt: only an explicit yes loads the old env ───"
for pair in "primary:$DEPLOY_P" "standby:$DEPLOY_S"; do
    name=${pair%%:*}; f=${pair#*:}
    expect "(a1-$name) d1 6e (a wrong-layout letter and a Backspace, then n) -> asked again, not loaded"  "$(frag_world "$f" '\0321n\n')" "loaded=no asks=2 says=1 died=0"
    expect "(a2-$name) n -> not loaded"                                                                    "$(frag_world "$f" 'n\n')"      "loaded=no asks=1 says=0 died=0"
    expect "(a3-$name) an empty line -> not loaded (the default is NO)"                                    "$(frag_world "$f" '\n')"       "loaded=no asks=1 says=0 died=0"
    expect "(a4-$name) y -> loaded"                                                                        "$(frag_world "$f" 'y\n')"      "loaded=yes asks=1 says=0 died=0"
    expect "(a5-$name) Y -> loaded"                                                                        "$(frag_world "$f" 'Y\n')"      "loaded=yes asks=1 says=0 died=0"
    expect "(a6-$name) yes -> loaded"                                                                      "$(frag_world "$f" 'yes\n')"    "loaded=yes asks=1 says=0 died=0"
    expect "(a7-$name) no -> not loaded"                                                                   "$(frag_world "$f" 'no\n')"     "loaded=no asks=1 says=0 died=0"
    expect "(a8-$name) three unrecognised answers -> not loaded, the wizard goes on"                       "$(frag_world "$f" 'x\nx\nx\n')" "loaded=no asks=3 says=2 died=0"
    expect "(a9-$name) a Ctrl-D (end of input) -> not loaded, the wizard does not die"                     "$(frag_world "$f" '')"         "loaded=no asks=1 says=0 died=0"
    expect "(a10-$name) YES is not an answer -> asked again, not loaded"                                   "$(frag_world "$f" 'YES\n')"    "loaded=no asks=2 says=1 died=0"
    expect "(a11-$name) a stray key, then y -> loaded after ONE re-ask"                                    "$(frag_world "$f" 'x\ny\n')"   "loaded=yes asks=2 says=1 died=0"
done

# ── (b) offer_start_service ────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (b) the start and enable questions: no stray byte starts or enables anything ───"
for pair in "primary:$DEPLOY_P" "standby:$DEPLOY_S"; do
    name=${pair%%:*}; f=${pair#*:}
    expect "(b1-$name) Enter, Enter -> started and enabled (the defaults are Y)"                       "$(start_world "$f" '\n\n')"               "start=1 enable=1"
    expect "(b2-$name) n, n -> nothing started, nothing enabled"                                       "$(start_world "$f" 'n\nn\n')"             "start=0 enable=0"
    expect "(b3-$name) y, y -> started and enabled"                                                    "$(start_world "$f" 'y\ny\n')"             "start=1 enable=1"
    expect "(b4-$name) d1 6e, n, n -> asked again, then no: NOT started"                                "$(start_world "$f" '\0321n\nn\nn\n')"     "start=0 enable=0"
    expect "(b5-$name) three stray answers, then y -> NOT started (the third takes NO), y enables"      "$(start_world "$f" 'x\nx\nx\ny\n')"       "start=0 enable=1"
    expect "(b6-$name) a stray answer, then a Ctrl-D -> NOT started (a Ctrl-D after one takes NO)"      "$(start_world "$f" '\0321n\n')"           "start=0 enable=1"
    expect "(b7-$name) y, then three stray answers -> started, NOT enabled"                            "$(start_world "$f" 'y\nx\nx\nx\n')"       "start=1 enable=0"
done

# ── (c) ask_path ───────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (c) ask_path: 'Continue anyway?' ───"
for pair in "primary:$DEPLOY_P" "standby:$DEPLOY_S"; do
    name=${pair%%:*}; f=${pair#*:}
    expect "(c1-$name) a missing file, y -> the path is kept"                                          "$(path_world "$f" '/nonexistent/k\ny\n')"                     "/nonexistent/k"
    expect "(c2-$name) a missing file, yes -> the path is kept"                                        "$(path_world "$f" '/nonexistent/k\nyes\n')"                   "/nonexistent/k"
    expect "(c3-$name) a missing file, n -> the path is asked again"                                   "$(path_world "$f" "/nonexistent/k\\nn\\n$WORK/exists\\n")"       "W/exists"
    expect "(c4-$name) a missing file, d1 6e, y -> asked again, then kept"                             "$(path_world "$f" '/nonexistent/k\n\0321n\ny\n')"             "/nonexistent/k"
done

# ── (d) the NEXT STEPS block (F24) ─────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (d) NEXT STEPS: no outage command, a pointer to the rehearsal that is safe ───"
for pair in "primary:$DEPLOY_P" "standby:$DEPLOY_S"; do
    name=${pair%%:*}; f=${pair#*:}
    n=$(next_steps "$f" | wc -l | tr -d ' ')
    [[ "$n" -ge 8 ]] && ok "(d1-$name) the block renders ($n lines)" || bad "(d1-$name) the NEXT STEPS block did not render ($n lines)"
    expect "(d2-$name) the numbering 1. 2. 3. is intact (lines that start a numbered item)" "$(ns_numbers "$f")" "3"
    expect "(d3-$name) lines of the rendered block that name iptables"                      "$(ns_iptables "$f")" "0"
done
expect "(d4) the primary's item 2 is 'Rehearse on a SPARE, never on the holder'" "$(next_steps "$DEPLOY_P" | grep -c '2\. Rehearse on a SPARE, never on the holder')" "1"
expect "(d5) ... and it points to docs/SAFETY.md, Rehearsing the self-fence"    "$(ns_pointer "$DEPLOY_P")" "1"
expect "(d6) that heading exists in docs/SAFETY.md (the pointer resolves)"      "$(grep -c '^### Rehearsing the self-fence$' "$HARNESS_DIR/docs/SAFETY.md")" "1"

# ── (e) controls ───────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (e) CONTROLS: a mutant of the helper, of a caller or of the NEXT STEPS text turns its case red ───"
ctl_ok=1; ctl_rows=""
ctl() {   # ctl <name> <script> <sed-expr> <world> <input> <what a CORRECT script prints>  (the mutant must print something else)
    local name="$1" script="$2" expr="$3" world="$4" input="$5" want="$6" m="$WORK/mut.$RANDOM.sh" got
    mutate "$script" "$expr" "$m" || { ctl_ok=0; ctl_rows="$ctl_rows $name:NOT-APPLIED"; return 0; }
    got=$($world "$m" "$input")
    if [[ "$got" != "$want" ]]; then ctl_rows="$ctl_rows $name:red"; else ctl_ok=0; ctl_rows="$ctl_rows $name:GREEN"; fi
}
for pair in "primary:$DEPLOY_P" "standby:$DEPLOY_S"; do
    name=${pair%%:*}; f=${pair#*:}
    ctl "$name-load-default-y"   "$f" 's/ask_yn "Load existing values as defaults? (y\/N)" n/ask_yn "Load existing values as defaults? (y\/N)" y/' frag_world '\n'      "loaded=no asks=1 says=0 died=0"
    ctl "$name-stray-is-yes"     "$f" 's/^        warn "answer y or n"$/        return 0/'                                                                       frag_world '\0321n\n' "loaded=no asks=2 says=1 died=0"
    ctl "$name-no-cap"           "$f" 's/\$tries -ge 3 \]\]/$tries -ge 99 ]]/'                                                                                          start_world 'x\nx\nx\ny\n' "start=0 enable=1"
    ctl "$name-eof-after-stray"  "$f" 's/\$eof -eq 1 && \$tries -gt 0/$eof -eq 9/'                                                                                    start_world '\0321n\n' "start=0 enable=1"
    ctl "$name-no-yes-word"      "$f" 's/y|Y|yes) return 0 ;;/y|Y) return 0 ;;/'                                                                                        frag_world 'yes\n' "loaded=yes asks=1 says=0 died=0"
    ctl "$name-result-ignored"   "$f" 's/if ask_yn "Load existing values as defaults? (y\/N)" n; then/if true; then/'                                                   frag_world 'n\n' "loaded=no asks=1 says=0 died=0"
    ctl "$name-start-bare-read"  "$f" 's/if ask_yn "Start ${unit} now? (Y\/n)" y; then/read -r yn || yn=""; if [[ "$yn" != "n" \&\& "$yn" != "N" ]]; then/'             start_world '\0321n\nn\nn\n' "start=0 enable=0"
done
ctl "primary-iptables-back"   "$DEPLOY_P" 's/Rehearse on a SPARE, never on the holder:/Test with iptables -I OUTPUT 1 ! -o lo -j DROP:/'      ns_iptables 'x' "0"
ctl "primary-numbering"       "$DEPLOY_P" 's/\${BOLD}2\.\${NC} Rehearse/${BOLD}4.${NC} Rehearse/'                                               ns_numbers  'x' "3"
ctl "primary-pointer-lost"    "$DEPLOY_P" 's/Rehearsing the self-fence/Rehearsing/'                                                                ns_pointer  'x' "1"
ctl "standby-iptables-added"  "$DEPLOY_S" 's/Verify monitoring is working:/Test with iptables -I OUTPUT 1 ! -o lo -j DROP:/'                      ns_iptables 'x' "0"
[[ $ctl_ok -eq 1 ]] && ok "(e) every mutant turns its case red:$ctl_rows" || bad "(e) a control did not turn its case red:$ctl_rows"

results_banner
