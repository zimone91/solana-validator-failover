#!/bin/bash
# v0.7 (AG-1.6 / AG-1.7): OPERATOR TEXTS — claim = check. Every figure and every promise an operator reads about the Alpenglow paths is either read from the
# code, computed here from the same bounds, or pinned by the phrase that carries it. A text that drifts from its number turns a case red; each case has a
# mutant control (mutate(), applied under assert) that does exactly that drift.
#   (1)  the slot-rate bounds (AG-1.6, G11): ONE constant in the [ag] block (the fastest row of the slot-params table, 200 ms = 5 slots/s), the VAT schedule
#        divides by it and by no literal; the seconds every text quotes for the 128-slot window are COMPUTED from the table's ends (128 / 5 = 26 s,
#        128 / 2.5 = 51 s) and the measured rate (128 / 4.667 = 27 s)
#   (2)  the fast-delinquency preset: ONE variable in the standby wizard (MAX_DELINQ_PRESET), 0 or >= 24 (G11: the old 15 sat close to the tail of the
#        measured Alpenglow vote lag), every echo / prompt / default reads it, no literal 15 is left in that block, and the env template's comment names the
#        same number
#   (3)  the texts that quote the 128-slot window: the wizard, README, DEPLOYMENT-MANUAL, the standby's Tier-1 comment and docs/SAFETY.md ("Slot time under
#        Alpenglow") say which bound they state (an UPPER bound at the slowest rate; the fast end; the measured rate) - and no text keeps "~150 slots (~60s)"
#   (4)  CONTROLS: the preset back to 15; a literal in an echo; the simple default off the variable; the wizard text back to "~150 slots (~60s)"; the README
#        and the MANUAL without their "upper bound"; the SAFETY paragraph without the table's ends
# RED ON THE BASE (the AG-1.5 / AG-1.4 tree): no constant, preset 15, the wizard says ~150 slots (~60s), no text names its bound.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, field, mutate.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Alpenglow operator texts: every claim is a check (v0.7 AG-1.6)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/agt.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
WIZ="$HARNESS_DIR/deploy-failover-standby.sh"
ENVS="$HARNESS_DIR/failover-standby.env.example"
README="$HARNESS_DIR/README.md"
MANUAL="$HARNESS_DIR/docs/DEPLOYMENT-MANUAL.md"
SAFETY="$HARNESS_DIR/docs/SAFETY.md"
for f in "$WIZ" "$ENVS" "$README" "$MANUAL" "$SAFETY"; do
    [[ -s "$f" ]] || { echo "  ❌ FAIL: harness: $f is missing or empty"; exit 1; }
done
role_of() { basename "$1" | sed 's/solana-\(.*\)-failover.sh/\1/'; }
fn_code() {   # fn_code <script> <function> - the function's CODE lines (no comment lines)
    sed -n "/^$2() {/,/^}/p" "$1" | grep -v '^[[:space:]]*#'
}
# the numbers every text is checked against - computed from the bounds, never typed twice
SLOW_X10=25                                   # 400 ms = 2.5 slots/s (the legacy row), in tenths of a slot per second
FAST=5                                        # 200 ms = 5 slots/s
MEAS_X1000=4667                               # measured under Alpenglow, mainnet 2026-11-01 (4.567 - 4.817)
WIN=128                                       # agave's delinquency window, in slots
S_SLOW=$(( (WIN * 10 + SLOW_X10 / 2) / SLOW_X10 ))          # 51 (51.2)
S_FAST=$(( (WIN * 2 + FAST) / (2 * FAST) ))                 # 26 (25.6)
S_MEAS=$(( (WIN * 1000 + MEAS_X1000 / 2) / MEAS_X1000 ))    # 27 (27.4)
[[ "$S_SLOW" == "51" && "$S_FAST" == "26" && "$S_MEAS" == "27" ]] \
    && ok "(0) the figures every text quotes, computed from the bounds: the $WIN-slot window is $S_FAST s at 5 slots/s (200 ms), $S_MEAS s at the measured 4.667, $S_SLOW s at 2.5 slots/s (400 ms)" \
    || bad "(0) arithmetic: slow=$S_SLOW fast=$S_FAST measured=$S_MEAS"

# ── (1) the slot-rate bounds in the daemons ───────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) one constant for the fast end; the VAT schedule divides by it ───"
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    blk=$(sed -n '/^# ── \[ag\] shared block/,/^# ── \[ag\] end shared block/p' "$scr")
    defs=$(printf '%s\n' "$blk" | grep -c '^_AG_SLOTS_PER_S_FAST=5$')
    anyd=$(grep -c '^_AG_SLOTS_PER_S_FAST=' "$scr")
    vr=$(fn_code "$scr" _vat_read)
    bare=$(printf '%s\n' "$vr" | grep -cE '/ *[0-9]+ *\)\)')
    uses=$(printf '%s\n' "$vr" | grep -c '_vat_left / _AG_SLOTS_PER_S_FAST')
    names=$(printf '%s\n' "$blk" | grep -c '400 ms = 2.5 slots/s is the SLOWEST rate any row allows, 200 ms = 5 slots/s the FASTEST')
    [[ $defs -eq 1 && $anyd -eq 1 && $bare -eq 0 && $uses -eq 3 && $names -eq 1 ]] \
        && ok "(1:$n) _AG_SLOTS_PER_S_FAST=5 is assigned once, inside the [ag] block, next to the comment that names both ends of the table (400 ms = 2.5, 200 ms = 5 slots/s); _vat_read divides $uses times by it and by no numeric literal" \
        || bad "(1:$n) constant: block-defs=$defs file-defs=$anyd literal-divisions=$bare uses=$uses comment=$names"
done

# ── (2) the fast-delinquency preset ────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (2) the preset: one variable, 0 or >= 24, read by every line of the block ───"
chk_preset() {   # chk_preset <wizard> <env template> -> the reasons it is wrong (empty = right)
    local w="$1" e="$2" why="" defs val env_n lits blk role_asg cfg_asg
    defs=$(grep -c '^MAX_DELINQ_PRESET=[0-9][0-9]*$' "$w")
    val=$(grep -m1 '^MAX_DELINQ_PRESET=[0-9][0-9]*$' "$w" | cut -d= -f2)
    [[ "$defs" == "1" ]] || why="$why preset-defined-$defs-times"
    if [[ -n "$val" ]]; then
        [[ "$val" == "0" || "$val" -ge 24 ]] || why="$why preset-$val-is-below-24"
        [[ "$val" == "24" ]] || why="$why preset-is-$val-not-24"
    fi
    role_asg=$(grep -c '^    ROLE_MAX_DELINQ_SLOTS=\$MAX_DELINQ_PRESET$' "$w")
    [[ "$role_asg" == "2" ]] || why="$why role-assignments-$role_asg-of-2-read-the-preset"
    [[ "$(grep -c 'ROLE_MAX_DELINQ_SLOTS=' "$w")" == "2" ]] || why="$why another-ROLE_MAX_DELINQ_SLOTS-assignment"
    cfg_asg=$(grep -c '^    CFG_MAX_DELINQ_SLOTS=\$MAX_DELINQ_PRESET ' "$w")
    [[ "$cfg_asg" == "1" ]] || why="$why simple-default-does-not-read-the-preset"
    blk=$(sed -n '/Fast delinquency detection/,/^CFG_MAX_DELINQ_SLOTS="\$REPLY"/p' "$w"; grep 'Preset: TAKEOVER_DELAY' "$w")
    lits=$(printf '%s\n' "$blk" | grep -cE '(^|[^0-9.])15([^0-9]|$)')
    [[ "$lits" == "0" ]] || why="$why a-literal-15-is-left-in-the-block($lits)"
    [[ "$(grep -c '\${MAX_DELINQ_PRESET}' "$w")" -ge 5 ]] || why="$why fewer-than-5-echo-or-prompt-reads"
    env_n=$(grep -m1 '^MAX_DELINQUENT_SLOTS=' "$e" | sed -n 's/.*; \([0-9][0-9]*\)=fast detect.*/\1/p')
    [[ -n "$val" && "$env_n" == "$val" ]] || why="$why env-template-comment-names-'$env_n'-not-'$val'"
    [[ "$(grep -c '^MAX_DELINQUENT_SLOTS=0 ' "$e")" == "1" ]] || why="$why env-template-default-is-not-0"
    printf '%s' "$why"
}
w=$(chk_preset "$WIZ" "$ENVS")
[[ -z "$w" ]] && ok "(2a) MAX_DELINQ_PRESET=24 is assigned once; it is 0 or >= 24; both role presets, the simple-mode default and the echoes / prompt read it; no literal 15 is left in that block; the env template's comment names the same 24" || bad "(2a) preset:$w"
for scr in "$STANDBY"; do
    [[ "$(grep -c '^MAX_DELINQUENT_SLOTS=0$' "$scr")" == "1" ]] && ok "(2b) the standby daemon's own default stays 0 (off): the preset is the WIZARD's, an installed node's, not a silent change of a running one" || bad "(2b) the standby's MAX_DELINQUENT_SLOTS default moved"
done

# ── (3) the texts that quote the window ────────────────────────────────────────────────────────────────────
echo ""; echo "─── (3) each text says which bound it states ───"
# table: <label>|<file>|<line pattern (grep -E)>|<phrases that line's paragraph must carry, separated by ~~>
chk_text() {   # chk_text <file> <anchor regex> <lines after> <phrase>… -> the missing phrases
    local f="$1" anchor="$2" after="$3" para ph miss=""; shift 3
    para=$(grep -A "$after" -E -e "$anchor" "$f" | tr '\n' ' ')
    [[ -n "$para" ]] || { printf 'anchor-not-found'; return; }
    for ph in "$@"; do [[ "$para" == *"$ph"* ]] || miss="$miss [$ph]"; done
    printf '%s' "$miss"
}
m_wiz=$(chk_text "$WIZ" "marks a validator 'delinquent' after" 0 "128 slots" "$S_FAST to $S_SLOW s" "about $S_MEAS s at Alpenglow")
[[ -z "$m_wiz" ]] && ok "(3a) the wizard: the delinquency window is 128 slots = $S_FAST to $S_SLOW s (200-400 ms slots), about $S_MEAS s at Alpenglow's rate" || bad "(3a) wizard text missing:$m_wiz"
[[ "$(grep -c '~150 slots\|(~60s)' "$WIZ")" == "0" ]] && ok "(3b) the wizard no longer says '~150 slots (~60s)' (agave's window is 128 slots; 150 / 2.5 was 60 s only at the slowest rate)" || bad "(3b) the old '~150 slots (~60s)' text is still in the wizard"
m_rd=$(chk_text "$README" "Tier-1 check \\(128 slots by default" 1 "up to ≈ $S_SLOW s" "slowest rate of the slot-params table, 2.5 slots/s" "about $S_MEAS s at Alpenglow")
[[ -z "$m_rd" ]] && ok "(3c) README: the 128-slot figure is an UPPER bound (up to ≈ $S_SLOW s at the slowest rate, 2.5 slots/s) and names the measured rate (about $S_MEAS s)" || bad "(3c) README text missing:$m_rd"
m_mn=$(chk_text "$MANUAL" "The default is 128 \\(up to" 2 "up to ≈ $S_SLOW s" "UPPER bound" "about $S_MEAS s at Alpenglow")
[[ -z "$m_mn" ]] && ok "(3d) DEPLOYMENT-MANUAL: the health-check distance's seconds are an UPPER bound (up to ≈ $S_SLOW s) and name the measured rate (about $S_MEAS s)" || bad "(3d) MANUAL text missing:$m_mn"
m_cm=$(chk_text "$STANDBY" "holder sits in agave's .current. list for up to" 3 "up to ~$S_SLOW s" "the SLOWEST rate of the slot-params table" "~$S_MEAS s at the Alpenglow")
[[ -z "$m_cm" ]] && ok "(3e) the standby's Tier-1 comment: the 128-slot window is 'up to ~$S_SLOW s' - the slowest rate, an upper bound - and ~$S_MEAS s at the Alpenglow rate" || bad "(3e) Tier-1 comment missing:$m_cm"
m_sf=$(chk_text "$SAFETY" "Slot time under Alpenglow \\(v0.7, AG-1.6\\)" 14 "4.667 slots/s" "400 (legacy), 350, 300, 250 and 200 ms" "FASTEST rate, **5 slots/s**" "SLOWEST, **2.5 slots/s**" "at most ≈ $S_SLOW s" "≈ $S_FAST s at the fastest rate" "≈ $S_MEAS s at the measured one" "**24** slots (it was 15)" "the v0.7 wizard writes 24" "_AG_SLOTS_PER_S_FAST")
[[ -z "$m_sf" ]] && ok "(3f) docs/SAFETY.md 'Slot time under Alpenglow': the table's two ends (400 ... 200 ms), the measured 4.667, the 128-slot window at $S_FAST / $S_MEAS / $S_SLOW s, the preset 24 (was 15), what 'the wizard preset' means in the tables below, and the constant that carries the fast end" || bad "(3f) SAFETY paragraph missing:$m_sf"
[[ "$(grep -c 'Slot time under Alpenglow' "$SAFETY")" == "1" ]] && ok "(3g) the paragraph exists once" || bad "(3g) the SAFETY paragraph occurs $(grep -c 'Slot time under Alpenglow' "$SAFETY") times"

# ── (4) controls ────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) CONTROLS (mutate()): each drift turns its case red ───"
ctl_ok=1; ctl_rows=""
ctl() {   # ctl <label> <file> <sed expr> <checker…> - the checker is red on the mutant
    local label="$1" src="$2" expr="$3" m out; shift 3
    m="$WORK/c-$label.$(basename "$src")"
    if mutate "$src" "$expr" "$m"; then
        out=$("$@" "$m")
        if [[ -n "$out" ]]; then ctl_rows="$ctl_rows $label"; else ctl_ok=0; bad "(4:$label) the control did not bite: the checker is still silent on the mutant"; fi
    else ctl_ok=0; fi
}
cp_pre() { chk_preset "$1" "$ENVS"; }
ctl preset-15 "$WIZ" 's/^MAX_DELINQ_PRESET=24$/MAX_DELINQ_PRESET=15/' cp_pre
ctl preset-literal-echo "$WIZ" 's/MAX_DELINQUENT_SLOTS=\${MAX_DELINQ_PRESET}\${NC}"$/MAX_DELINQUENT_SLOTS=24${NC}"/' cp_pre
ctl simple-default-literal "$WIZ" 's/CFG_MAX_DELINQ_SLOTS=\$MAX_DELINQ_PRESET /CFG_MAX_DELINQ_SLOTS=24 /' cp_pre
ctl role-literal "$WIZ" 's/^    ROLE_MAX_DELINQ_SLOTS=\$MAX_DELINQ_PRESET$/    ROLE_MAX_DELINQ_SLOTS=15/' cp_pre
ctl recommended-15 "$WIZ" 's/Recommended \${MAX_DELINQ_PRESET} /Recommended 15 /' cp_pre
cw_txt() { chk_text "$1" "marks a validator 'delinquent' after" 0 "128 slots" "$S_FAST to $S_SLOW s" "about $S_MEAS s at Alpenglow"; }
ctl wizard-text-150 "$WIZ" "s/after 128 slots without a vote: 26 to 51 s (200-400 ms slots), about 27 s at Alpenglow's rate/after ~150 slots (~60s)/" cw_txt
cr_txt() { chk_text "$1" "Tier-1 check \\(128 slots by default" 1 "up to ≈ $S_SLOW s" "slowest rate of the slot-params table, 2.5 slots/s" "about $S_MEAS s at Alpenglow"; }
ctl readme-no-bound "$README" 's/Tier-1 check (128 slots by default, up to ≈ 51 s:/Tier-1 check (128 slots by default, ≈ 51 s:/' cr_txt
cm_txt() { chk_text "$1" "The default is 128 \\(up to" 2 "up to ≈ $S_SLOW s" "UPPER bound" "about $S_MEAS s at Alpenglow"; }
ctl manual-no-bound "$MANUAL" 's/The default is 128 (up to ≈ 51 s:/The default is 128 (≈ 51 s:/' cm_txt
cs_txt() { chk_text "$1" "Slot time under Alpenglow \\(v0.7, AG-1.6\\)" 14 "400 (legacy), 350, 300, 250 and 200 ms" "FASTEST rate, **5 slots/s**" "SLOWEST, **2.5 slots/s**"; }
ctl safety-no-ends "$SAFETY" 's/at the FASTEST rate, \*\*5 slots\/s\*\*/at the fastest rate/' cs_txt
[[ $ctl_ok -eq 1 ]] && ok "(4) every drift turns its case red:$ctl_rows" || bad "(4) a control did not turn its case red"

results_banner
