#!/bin/bash
# v0.7 (AG-1.6 / AG-1.7): OPERATOR TEXTS — claim = check. Every figure and every promise an operator reads about the Alpenglow paths is either read from the
# code, computed here from the same bounds, or pinned by the phrase that carries it. A text that drifts from its number turns a case red; each case has a
# mutant control (mutate(), applied under assert) that does exactly that drift.
#   (1)  the slot-rate bounds (AG-1.6, G11): ONE constant in the [ag] block (the fastest row of the slot-params table, 200 ms = 5 slots/s), the VAT schedule
#        divides by it and by no literal; the seconds every text quotes for the 128-slot window are COMPUTED from the table's ends (128 / 5 = 26 s,
#        128 / 2.5 = 51 s) and the measured rate (128 / 4.667 = 27 s)
#   (2)  the fast-delinquency preset: ONE variable in the standby wizard (MAX_DELINQ_PRESET), 0 or >= 24 (G11: the old 15 sat close to the tail of the
#        measured Alpenglow vote lag), every echo / prompt / default reads it, no literal 15 is left in that block, and the env template's comment names the
#        same number; the standby's startup drift note for a MAX_DELINQUENT_SLOTS below it compares against that same number
#   (3)  the texts that quote the 128-slot window: the wizard, README, DEPLOYMENT-MANUAL, the standby's Tier-1 comment and docs/SAFETY.md ("Slot time under
#        Alpenglow") say which bound they state (an UPPER bound at the slowest rate; the fast end; the measured rate) - and no text keeps "~150 slots (~60s)"
#   (4)  CONTROLS: the preset back to 15; a literal in an echo; the simple default off the variable; the wizard text back to "~150 slots (~60s)"; the README
#        and the MANUAL without their "upper bound"; the SAFETY paragraph without the table's ends; the drift note's number moved off the wizard's
#   (5)  G5 (AG-1.7): no text recommends an identity.json symlink re-pointed on each transition; the six places that speak of the validator's startup --identity
#        (both wizards' warn + fail, both daemons' startup alert) and the manual say it is this node's own unstaked keypair, never re-pointed, so every restart
#        comes up unstaked
#   (6)  G6 (AG-1.7): no shipped text tells an operator to scp a tower, to use --require-tower, or says the primary deletes the tower; the manual's procedures
#        are the warm swap (demote first, the sha256 equal on two reads, a copy with a sha check, voter first then identity), and 'a vote-history file is never
#        deleted'; every staked set-identity line of the manual is immediately preceded by its authorized-voter add
#   (7)  every text that promised an automatic takeover (AG-1.7): a table of (file, phrase that must be GONE, phrase that must be THERE) over the wizards, the
#        installer, both daemons' banners and alerts, README, the manual, NOTIFICATIONS, the templates, the arm ceremony, SPLIT-BRAIN-RESIDUAL, the systemd
#        README and SAFETY (the fix round added the three promises the first table missed - README's "the spare steps up", the standby template's "we TAKE
#        it", the systemd README's "the spare takes on its timer path" - and README's "A promoted STANDBY" bullet, now marked retained path; the 27 s
#        decision point and the unreadable/unavailable words)
#   (8)  the fence's ledger (D0 F3, F4): the manual says to set LEDGER_PATH before 'failover arm', why, and that -l is not detected
#   (9)  CONTROLS for (5)-(8): a wizard line back to the symlink advice, a hard-stop alert back to 'scp tower', the manual's voter/identity order broken, a
#        promise put back in each of the files of (7), a banner line deleted
# RED ON THE BASE (the AG-1.5 / AG-1.4 tree): no constant, preset 15, the wizard says ~150 slots (~60s), no text names its bound; AG-1.7: every old phrase is
# still there and no new one is.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, field, mutate.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Alpenglow operator texts: every claim is a check (v0.7 AG-1.6 / AG-1.7)"

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
chk_drift_preset() {   # chk_drift_preset <standby> <wizard> -> the reasons the standby's drift note is not tied to the wizard's preset (empty = tied)
    local sc="$1" wz="$2" why="" dp wp
    dp=$(sed -n '/^_delinq_drift_note() {/,/^}/p' "$sc" | grep -o 'local _preset=[0-9][0-9]*' | cut -d= -f2)
    wp=$(grep -m1 '^MAX_DELINQ_PRESET=[0-9][0-9]*$' "$wz" | cut -d= -f2)
    [[ "$(grep -c '^_delinq_drift_note() {' "$sc")" == "1" ]] || why="$why note-not-defined-exactly-once"
    [[ -n "$dp" ]] || why="$why note-carries-no-_preset"
    [[ -n "$wp" && "$dp" == "$wp" ]] || why="$why note-preset-'$dp'-is-not-the-wizards-'$wp'"
    printf '%s' "$why"
}
w=$(chk_drift_preset "$STANDBY" "$WIZ")
[[ -z "$w" ]] && ok "(2c) the standby's startup drift note (a MAX_DELINQUENT_SLOTS of 1..23, log only; tests/test_ag_take.sh (7d)) compares against the wizard's MAX_DELINQ_PRESET - the same number, read from the wizard here, not typed twice" || bad "(2c) drift-note preset:$w"

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
[[ "$(grep -cF '**Slot time under Alpenglow (v0.7, AG-1.6).**' "$SAFETY")" == "1" ]] && ok "(3g) the paragraph exists once" || bad "(3g) the SAFETY paragraph occurs $(grep -cF '**Slot time under Alpenglow (v0.7, AG-1.6).**' "$SAFETY") times"

# ── (5) G5: the startup --identity ────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (5) G5: the startup --identity is this node's own unstaked keypair, never re-pointed ───"
DEPLOY_P="$HARNESS_DIR/deploy-failover.sh"; INSTALL="$HARNESS_DIR/install.sh"; ARM="$HARNESS_DIR/failover-arm.sh"
ENV_P="$HARNESS_DIR/failover.env.example"; NOTIF="$HARNESS_DIR/docs/NOTIFICATIONS.md"; SPLIT="$HARNESS_DIR/docs/SPLIT-BRAIN-RESIDUAL.md"
FENCE_A="$HARNESS_DIR/systemd/failover-fence.sh"; FENCE_B="$HARNESS_DIR/systemd/failover-fence-page-only.sh"; SYSD="$HARNESS_DIR/systemd/README.md"
SHIPPED_TXT="$STANDBY $PRIMARY $WIZ $DEPLOY_P $INSTALL $ARM $ENVS $ENV_P $FENCE_A $FENCE_B $README $MANUAL $SAFETY $NOTIF $SPLIT $SYSD"
for f in $SHIPPED_TXT; do   # a file that is missing would make every GONE row below vacuously true
    [[ -s "$f" ]] || { echo "  ❌ FAIL: harness: $f is missing or empty"; exit 1; }
done
cnt() {   # cnt <fixed phrase> <file…> -> the total number of lines carrying it
    local ph="$1" f c n=0; shift
    for f in "$@"; do c=$(grep -cF -e "$ph" "$f" 2>/dev/null); n=$(( n + ${c:-0} )); done
    printf '%s' "$n"
}
g5_gone=""
for ph in 'identity.json symlink' 'Anza `identity.json`' 'symlink recommended' 'symlink recomm' 'repoint it on each transition' 'Repoint the startup'; do
    n=$(cnt "$ph" $SHIPPED_TXT); [[ "$n" == "0" ]] || g5_gone="$g5_gone [$ph x$n]"
done
[[ -z "$g5_gone" ]] && ok "(5a) no shipped script, template or doc recommends an identity.json symlink, 'repointed on each transition', or an 'Anza identity.json' fix (6 phrases, 0 hits in $(printf '%s\n' $SHIPPED_TXT | wc -l | tr -d ' ') files)" || bad "(5a) the symlink advice is still there:$g5_gone"
g5_there=""
for spec in "$WIZ:2" "$DEPLOY_P:2" "$STANDBY:1" "$PRIMARY:1" "$MANUAL:1"; do
    f="${spec%:*}"; want="${spec##*:}"
    a=$(cnt 'never re-pointed' "$f"); b=$(cnt 'every restart comes up unstaked' "$f")
    [[ $a -ge $want && $b -ge $want ]] || g5_there="$g5_there [$(basename "$f"): never-re-pointed=$a unstaked-restart=$b want>=$want]"
done
[[ -z "$g5_there" ]] && ok "(5b) the six places that speak of the validator's startup --identity (both wizards' warn + fail, both daemons' startup alert) and the manual say 'never re-pointed' and 'every restart comes up unstaked'" || bad "(5b) the canonical sentence is missing:$g5_there"

# ── (6) G6: the warm swap ──────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) G6: no tower advice; the procedures are the warm swap ───"
g6_gone=""
for ph in 'scp tower' 'tower-1_9' '--require-tower is correct' 'deletes its staked tower' 'PRIMARY still deletes' 'hand the live tower' 'tower-aware procedure' 'the live tower is copied' 'confirm the spare took over'; do
    n=$(cnt "$ph" $SHIPPED_TXT); [[ "$n" == "0" ]] || g6_gone="$g6_gone [$ph x$n]"
done
[[ -z "$g6_gone" ]] && ok "(6a) no shipped text tells an operator to scp a tower, to assert --require-tower, or says the primary deletes the tower (9 phrases, 0 hits)" || bad "(6a) TowerBFT-era advice is still there:$g6_gone"
g6_there=""
for ph in 'Demote the old holder FIRST' 'sha256sum' 'authorized-voter remove-all' 'a vote-history file is never deleted' 'A vote-history file is never' 'the voter first, then the identity'; do
    n=$(cnt "$ph" "$MANUAL"); [[ $n -ge 1 ]] || g6_there="$g6_there [$ph]"
done
for ph in 'the old holder is demoted to its own unstaked identity first' 'is read twice on the old holder' 'authorized-voter add' 'in that order, with no extra flags' 'A vote-history file is never deleted'; do
    n=$(cnt "$ph" "$SAFETY"); [[ $n -ge 1 ]] || g6_there="$g6_there [SAFETY: $ph]"
done
[[ -z "$g6_there" ]] && ok "(6b) the manual's procedure and SAFETY's four steps are the warm swap: demote first, the sha256 read twice, the copy with a sha check, the voter then the identity, no flags - and a vote-history file is never deleted" || bad "(6b) warm-swap text missing:$g6_there"
order_of() {   # order_of <manual> -> "<staked set-identity lines NOT directly preceded by their authorized-voter add>/<staked set-identity lines>"
    awk '/agave-validator .*set-identity .*mainnet-validator-keypair\.json/ { if (prev !~ /authorized-voter add .*mainnet-validator-keypair\.json/) bad++; n++ } { if ($0 !~ /^[[:space:]]*$/) prev=$0 } END { printf "%d/%d", bad+0, n+0 }' "$1"
}
[[ "$(order_of "$MANUAL")" == "0/3" ]] && ok "(6c) the manual's three staked set-identity lines (Phase 3, the emergency step 2, the switch-back) are each immediately preceded by the staked authorized-voter add: voter first, then identity" || bad "(6c) voter/identity order in the manual: $(order_of "$MANUAL") (want 0/3)"
# AG-3.3: the flag has ONE place in the shipped code (the standby's armed cold take) and is explained in docs/SAFETY.md only, in the "Armed cold take" subsection; the manual, the README and the primary never name it
[[ "$(cnt 'do-not-require' "$MANUAL" "$README" "$PRIMARY")" == "0" && "$(cnt 'do-not-require' "$STANDBY")" == "1" ]] && ok "(6d) the flag that switches the vote-history requirement off is named in the standby once (the armed cold take's one definition) and in neither the manual, the README nor the primary (the whole-tree census is test_ag_take (8e) and the facts job's step)" || bad "(6d) the do-not-require flag census: manual+README+primary=$(cnt 'do-not-require' "$MANUAL" "$README" "$PRIMARY") standby=$(cnt 'do-not-require' "$STANDBY")"

# ── (7) the promises ───────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (7) every text that promised an automatic takeover says what Alpenglow mode does, or is marked retained path ───"
# <file key>|<A = must be GONE | P = must be THERE>|<min hits for P>|<fixed phrase>
CLAIMS='wizard|A|0|Automatic staked-identity hot-swap
wizard|A|0|Hot spare. Takes over at
wizard|A|0|Cold spare. Takes over at 120s
wizard|A|0|safe-fast takeover
wizard|A|0|delayed takeover, gossip OFF
wizard|A|0|BACKUP takes over
wizard|A|0|A BACKUP takes over only AFTER
wizard|P|1|Staked-identity failover monitor for Solana validators — Alpenglow mode
wizard|P|1|Monitoring spare. Pages you at
wizard|P|1|NEVER takes the staked identity itself
wizard|P|1|Cold spare. Pages you at 120s
wizard|P|1|it never takes the identity either
wizard|P|1|in Alpenglow mode it pages and never takes
wizard|P|1|retained path: Alpenglow mode withholds every take in v0.7
wizard|P|1|retained path — v0.7 never takes
wizard|P|1|BACKUP pages only after BOTH PRIMARY and STANDBY
deploy_p|A|0|Automatic staked-identity hot-swap
deploy_p|P|1|Staked-identity failover monitor for Solana validators — Alpenglow mode
install|A|0|hot spare (or BACKUP)
install|P|1|monitoring spare (or BACKUP): pages, never takes the identity (Alpenglow mode)
standby|A|0|STANDBY (hot spare)
standby|A|0|Cannot monitor or take over
standby|A|0|Cannot take over if needed
standby|A|0|a spare may take over
standby|A|0|confirm the spare took over
standby|A|0|the spare takes over via the verified-demote proof
standby|A|0|not ready to take over
standby|A|0|gate FO has says
standby|P|1|every gate FO has said the take would happen now
standby|P|1|Mode:              ALPENGLOW — this node NEVER takes the staked identity itself
standby|P|2|no spare takes the identity by itself
standby|P|1|no spare takes it by itself unless it is armed (AG_ARMED_TAKE=true), otherwise an operator moves it
standby|P|4|retained path: v0.7 withholds every take
standby|P|1|in Alpenglow mode (v0.7) no take is made at all, so nothing is bypassed today
standby|P|2|Tier-1 not ready (no take decision is made while this holds)
primary|A|0|STANDBY may take over
primary|A|0|confirm the spare took over
primary|A|0|the spare takes over via the verified-demote proof
primary|A|0|gate FO has says
primary|P|1|every gate FO has said the take would happen now
primary|P|1|Mode:              ALPENGLOW — this node NEVER re-takes the staked identity itself
primary|P|2|no spare takes the identity by itself
primary|P|1|no spare takes it by itself unless it is armed (AG_ARMED_TAKE=true), otherwise an operator moves it
primary|P|1|the retained automatic re-take path
primary|P|1|in Alpenglow mode (v0.7) no take is made at all, so nothing is bypassed today
readme|A|0|Automatic staked-identity failover for Solana validators.
readme|A|0|no restart, no manual steps, ~60s
readme|A|0|does the spare take over.
readme|P|1|Alpenglow mode (always on in v0.7): FO never takes the
readme|P|1|**pages you**
readme|P|3|retained path
readme|P|1|a take every gate approves is **withheld and paged**
readme|A|0|the spare steps up
readme|P|1|then the spare only **pages you**
readme|P|1|**v0.7 needs agave / Jito-Solana `4.4.0` or newer**
readme|P|1|v0.7 itself is being exercised on the testnet pair (the Block 10 end-to-end run)
readme|P|1|up to about 27 s at the decision point
readme|A|0|- A promoted STANDBY that later isolates self-fences too
readme|A|0|(the retained path: v0.7 never promotes one by itself)
readme|P|1|A promoted STANDBY (an unarmed spare never promotes itself; an armed one does, by the cold take) that later isolates self-fences too
manual|A|0|Recommended fix — the Anza
manual|A|0|(hot spare)
manual|P|1|ALPENGLOW MODE (always on)
manual|P|1|(monitoring spare)
manual|P|1|retained path
notifications|A|0|Cannot monitor or take over
notifications|A|0|Cannot take over if needed
notifications|A|0|a spare may take over
notifications|P|1|Retained path — not sent in v0.7
notifications|P|1|The second is the retained path: not sent in v0.7
notifications|P|1|The take is the retained path: not sent in v0.7
notifications|P|1|no spare takes the identity by itself
arm|P|1|Alpenglow mode (v0.7): the pairing (P5), the vantage checks (P6) and this summary condition only the retained take path
templates|P|1|v0.7 ALPENGLOW MODE (always on): by default FO never takes the staked identity automatically
templates|P|1|v0.7 ALPENGLOW MODE (always on): this node never takes the staked identity automatically
templates|P|1|(Retained path: v0.7 withholds every take.)
templates|A|0|(we TAKE it when PRIMARY drops it)
templates|P|1|v0.7: an unarmed spare - the default - never takes it: you move it to this node by the warm swap after the page
templates|P|1|a value of 1..23 is logged once at start
sysd|A|0|the spare takes on its timer path
sysd|P|1|in Alpenglow mode the spare takes nothing
splitbrain|A|0|(research pending)
splitbrain|P|1|v0.7 never takes the staked
safety|P|1|## Alpenglow mode (v0.7)
safety|P|1|**The retained take path, unreachable in v0.7.**
safety|P|1|**What FO does not do.** By default it does not take, re-take or pre-warm
safety|P|1|`TAKEOVER WITHHELD — Alpenglow mode 🚨`
safety|P|1|in v0.7 (Alpenglow mode) the spare pages instead of taking
safety|P|1|The top-2000 cut is not checked
safety|A|0|can take up to 15 s
safety|P|1|can take up to about 27 s
safety|P|1|the standby says so once at start - a log line, no page - when the value is 1 to 23
safety|P|1|the vote-history file under `timeout -k 2 10` (12 s more
safety|A|0|A field that cannot be read prints
safety|P|1|`unreadable (<why>)` for `getHealth`
safety|P|1|the validator stays unstaked until an operator acts
standby|P|1|this spare is NOT ARMED (AG_ARMED_TAKE=false): nothing was done
standby|P|1|this spare is ARMED, but the readiness margin held the take
standby|P|1|TAKEOVER BLOCKED — authorized-voter add failed
standby|P|1|[DRY RUN] WOULD TAKE STAKED (Alpenglow cold take)
standby|P|1|ALPENGLOW, ARMED — this spare WILL take the staked identity by itself
standby|P|1|LIVE MODE — STANDBY will perform a real takeover
standby|P|1|it never takes (not armed)
standby|P|1|cold take: empty history, floor = own root
readme|P|1|(`AG_ARMED_TAKE=true`, off by default
readme|P|1|What an **armed** spare runs instead is the *cold take*
readme|P|1|(default **60s** = the PRIMARY
readme|P|1|`AG_ARMED_TAKE=false` (the default) only pages
readme|P|1|(`AG_ARMED_TAKE=true`), the standby takes it cold, voter first
templates|P|1|ONLY the literal `true` arms it
templates|P|1|HOLDER_GAP_DEMOTE_SECS + 30 (shipped 60 >= 30 + 30;
templates|P|1|an armed spare below 60 REFUSES to start
templates|P|1|the on-chain lastVote understates the real one by up to ~8 slots: 170 + 8 = 178, rounded up to 200
notifications|P|1|`TAKEOVER BLOCKED — authorized-voter add failed`
notifications|P|1|`[DRY RUN] WOULD TAKE STAKED (Alpenglow cold take)`
notifications|P|1|this spare is ARMED, but the readiness margin held the take
safety|P|1|### Armed cold take (opt-in, rc1)
safety|P|1|`own - holder >= AG_TAKE_MARGIN_SLOTS` (default 200)
safety|P|1|so 170 + 8 = 178, rounded up to **200**
safety|P|1|`authorized-voter add` of the staked keypair first
safety|P|1|`TAKEOVER BLOCKED — authorized-voter add failed`
safety|P|1|`validator/src/commands/set_identity/mod.rs`
safety|P|1|`HOLDER_GAP_DEMOTE_SECS` + 30 (shipped: 60 >= 30 + 30)
safety|P|1|an armed spare REFUSES to start when its `TAKEOVER_DELAY` is below 60 s
safety|P|1|`HOLDER_UNREACHABLE_STOP_SECS` (default 30 s, floor 20)
safety|P|1|`HOLDER HUNG — HARD STOP 🚨` names the three facts and the branch taken
safety|P|1|since AG-3.8 the unreachable path has its own rung
safety|P|1|a knob of 22 would mean the third
safety|P|1|clock reads 0, 12, 23, 34 s
safety|P|1|the validator is dead 48 to 51 s after the hang
safety|P|1|70 to 73 s when it is wedged for its whole bound
safety|P|1|**A restarted validator is not a hung one (AG-3.8d).**
safety|P|1|validator restarted (new process,
safety|P|1|cannot tell a hung validator from a restarted one
safety|A|0|A limit of the process test
notifications|P|1|cannot tell a hung validator from a restarted one
notifications|P|1|restarted since the last readable identity read
templates|P|1|a validator that restarted (since the last readable read, or during the episode)
safety|A|0|0, 11, 22, 33
safety|A|0|49 to 55 s
safety|A|0|70 to 75 s
safety|P|1|the fast branch kills at least about 10 s before it
readme|P|1|hard-stopped by its own daemon after
templates|P|1|HOLDER_UNREACHABLE_STOP_SECS=30) hard-stops a mute validator
templates|P|1|22 would be the third
templates|P|1|clock reads 0, 12, 23, 34 s
templates|P|1|not voting 48 to 51 s after the hang on its fast branch
templates|A|0|0 / 11 / 22 / 33
templates|A|0|49 to 55 s
templates|A|0|70 to 75 s
primary|P|1|clock reads 0, 12, 23, 34 s
primary|P|1|A validator that RESTARTED since the last readable identity read is not hung either (AG-3.8d)
primary|P|1|log_info "[hung] validator restarted (new process
primary|A|0|LIMIT: the pid is taken at the FIRST unreadable cycle
primary|A|0|(0, 11, 22, 33 s)
primary|A|0|49 to 55 s
primary|A|0|a restarted one never either
safety|P|1|two bounded local reads, the veto, then the margin
safety|P|1|3 + 36 + 10 + 11 = 60 s, which does not converge either
safety|P|1|duplicates, not equivocation;
safety|P|1|exit is not a guarantee when the forks diverge
safety|P|1|systemd does not expand `$HOME` in an `EnvironmentFile=`
safety|P|1|That line is in the monitor skeleton (AG-3.5)
safety|A|0|That is unit work, not part of this release.
sysd|P|1|unless it is armed (`AG_ARMED_TAKE=true`'
claims_for() {   # claims_for <key> <file…> -> the claims that do not hold, empty = all hold
    local key="$1" k kind min ph n c f why=""; shift
    while IFS='|' read -r k kind min ph; do
        [[ "$k" == "$key" ]] || continue
        n=0; for f in "$@"; do c=$(grep -cF -e "$ph" "$f" 2>/dev/null); n=$(( n + ${c:-0} )); done
        case "$kind" in
            A) [[ $n -eq 0 ]] || why="$why [still there x$n: $ph]" ;;
            P) [[ $n -ge $min ]] || why="$why [missing (found $n, want >= $min): $ph]" ;;
        esac
    done <<< "$CLAIMS"
    printf '%s' "$why"
}
claim_files() {   # claim_files <key> -> the file(s) the key names
    case "$1" in
        wizard) echo "$WIZ" ;; deploy_p) echo "$DEPLOY_P" ;; install) echo "$INSTALL" ;; standby) echo "$STANDBY" ;; primary) echo "$PRIMARY" ;;
        readme) echo "$README" ;; manual) echo "$MANUAL" ;; notifications) echo "$NOTIF" ;; arm) echo "$ARM" ;; templates) echo "$ENVS $ENV_P" ;;
        splitbrain) echo "$SPLIT" ;; sysd) echo "$SYSD" ;; safety) echo "$SAFETY" ;;
    esac
}
cl_ok=1; cl_rows=""; cl_n=$(printf '%s\n' "$CLAIMS" | grep -c .)
for key in wizard deploy_p install standby primary readme manual notifications arm templates splitbrain sysd safety; do
    # shellcheck disable=SC2046
    w=$(claims_for "$key" $(claim_files "$key"))
    if [[ -z "$w" ]]; then cl_rows="$cl_rows $key"; else cl_ok=0; bad "(7:$key) a claim does not hold:$w"; fi
done
[[ $cl_ok -eq 1 ]] && ok "(7) all $cl_n claims hold - each file of the table has none of its old promises left and carries its Alpenglow wording:$cl_rows" || true

# ── (8) the fence's ledger ─────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) the fence's ledger: LEDGER_PATH is set explicitly before 'failover arm' (D0 F3, F4) ───"
m_led=$(chk_text "$MANUAL" "Arming the fence \\(v0.7\\): set .LEDGER_PATH. explicitly" 5 "before" "failover arm" "has no such detection" "every admin-socket call it makes fails to connect" "falls to its stop path" "short form \`-l\`" "exit 1 at startup" "ask for \`LEDGER_PATH\`")
[[ -z "$m_led" ]] && ok "(8) the manual's 'Arming the fence' paragraph: set LEDGER_PATH before 'failover arm'; the fence has no detection, so every admin-socket call it makes fails to connect and it falls to its stop path; the daemons do not detect -l and exit 1 at startup asking for LEDGER_PATH" || bad "(8) the fence's ledger paragraph is missing:$m_led"

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
cp_drift() { chk_drift_preset "$1" "$WIZ"; }
ctl note-preset-moved "$STANDBY" 's/local _preset=24 /local _preset=15 /' cp_drift
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

# ── (9) controls for (5)-(8) ──────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) CONTROLS (mutate()) for (5)-(8): each put-back turns its case red ───"
c9_ok=1; c9_rows=""
ctl9() {   # ctl9 <label> <file> <sed expr> <checker…> - the checker prints something on the mutant
    local label="$1" src="$2" expr="$3" m out; shift 3
    m="$WORK/c9-$label.$(basename "$src")"
    if mutate "$src" "$expr" "$m"; then
        out=$("$@" "$m")
        if [[ -n "$out" ]]; then c9_rows="$c9_rows $label"; else c9_ok=0; bad "(9:$label) the control did not bite: the checker is silent on the mutant"; fi
    else c9_ok=0; fi
}
g5_probe() { cnt 'Anza' "$1" | grep -v '^0$'; }
ctl9 g5-wizard-fail "$WIZ" 's/Fix it: the validator.s startup --identity is this node.s own UNSTAKED keypair, never re-pointed: every restart comes up unstaked\./Set the startup --identity to the UNSTAKED keypair (Anza identity.json symlink recommended)./' g5_probe
g6_probe() { cnt 'scp tower' "$1" | grep -v '^0$'; }
ctl9 g6-hardstop-scp-tower "$PRIMARY" 's/Node is down; recover manually (restart on the unstaked identity;/Node is down; recover manually (scp tower, restart on the unstaked identity;/' g6_probe
order_probe() { local o; o=$(order_of "$1"); [[ "$o" == "0/3" ]] || printf '%s' "$o"; }
ctl9 g6-order "$MANUAL" 's/^   agave-validator --ledger \/root\/solana\/ledger authorized-voter add \/root\/solana\/mainnet-validator-keypair.json$/   agave-validator --ledger \/root\/solana\/ledger authorized-voter add \/root\/solana\/other-keypair.json/' order_probe
cw() { claims_for wizard "$1"; }
ctl9 p-wizard-hot-spare "$WIZ" 's/Monitoring spare\. Pages you at/Hot spare. Takes over at/' cw
cs() { claims_for standby "$1"; }
ctl9 p-standby-mode-line "$STANDBY" '/Mode:              ALPENGLOW — this node NEVER takes the staked identity itself/d' cs
ctl9 p-standby-alert "$STANDBY" 's/in Alpenglow mode no spare takes the identity by itself unless it is armed (AG_ARMED_TAKE=true), so by default it stays on this node until an operator moves it\. Intervene (stop the validator; move the identity only by the warm swap, docs\/SAFETY.md)\." "\$STAKED_PUBKEY" "STANDBY UNREACHABLE WHILE STAKED 🚨"/a spare may take over. Intervene (stop the validator or confirm the spare took over)." "$STAKED_PUBKEY" "STANDBY UNREACHABLE WHILE STAKED 🚨"/' cs
cp_() { claims_for primary "$1"; }
ctl9 p-primary-banner "$PRIMARY" '/Mode:              ALPENGLOW — this node NEVER re-takes the staked identity itself/d' cp_
cr() { claims_for readme "$1"; }
ctl9 p-readme-headline "$README" 's/^Staked-identity failover \*\*monitor\*\* for Solana validators\. \*\*Alpenglow mode (always on in v0.7): FO never takes the$/Automatic staked-identity failover for Solana validators. FO takes the/' cr
cm() { claims_for manual "$1"; }
ctl9 p-manual-banner "$MANUAL" 's/ALPENGLOW MODE (always on)/MODE/' cm
cn() { claims_for notifications "$1"; }
ctl9 p-notif-mark "$NOTIF" 's/| `RECOVERED TO STAKED ✅` \/ `RECOVERY FAILED ❌` \/ `RECOVERY BLOCKED — keypair problem` | \*\*Retained path — not sent in v0.7\*\* (Alpenglow mode withholds the take: see the `WITHHELD` page)\. /| `RECOVERED TO STAKED ✅` \/ `RECOVERY FAILED ❌` \/ `RECOVERY BLOCKED — keypair problem` | /' cn
ca() { claims_for arm "$1"; }
ctl9 p-arm-summary "$ARM" '/Alpenglow mode (v0.7): the pairing (P5), the vantage checks (P6) and this summary condition only the retained take path/d' ca
ct() { claims_for templates "$1" "$ENV_P"; }
cpt() { claims_for templates "$ENVS" "$1"; }   # the mutated PRIMARY template + the untouched standby one
ctl9 p-template-header "$ENVS" 's/^# v0\.7 ALPENGLOW MODE (always on): by default FO never takes the staked identity automatically:/# MODE:/' ct
cx() { claims_for splitbrain "$1"; }
ctl9 p-splitbrain-note "$SPLIT" 's/Alpenglow note (v0\.7)/Alpenglow note (research pending)/' cx
cq() { claims_for safety "$1"; }
ctl9 p-safety-section "$SAFETY" 's/^## Alpenglow mode (v0\.7)$/## Mode/' cq
ctl9 p-safety-15s "$SAFETY" 's/can take up to about 27 s/can take up to 15 s/' cq
ctl9 p-safety-unreadable "$SAFETY" 's/`unreadable (<why>)` for `getHealth`/`unavailable (<why>)` for everything/' cq
ctl9 p-readme-steps-up "$README" 's/then the spare only \*\*pages you\*\*/the spare steps up/' cr
ctl9 p-standby-notarmed "$STANDBY" 's/this spare is NOT ARMED (AG_ARMED_TAKE=false): nothing was done/in Alpenglow mode FO never takes the staked identity automatically: nothing was done/' cs
ctl9 p-standby-armed-held "$STANDBY" 's/this spare is ARMED, but the readiness margin held the take/the readiness margin held the take/g' cs
ctl9 p-standby-blocked-status "$STANDBY" 's/"TAKEOVER BLOCKED — authorized-voter add failed"/"TAKEOVER BLOCKED"/' cs
ctl9 p-standby-armed-banner "$STANDBY" 's/ALPENGLOW, ARMED — this spare WILL take the staked identity by itself/ALPENGLOW/' cs
ctl9 p-standby-live-mode "$STANDBY" 's/LIVE MODE — STANDBY will perform a real takeover/LIVE MODE/' cs
ctl9 p-readme-armed-default "$README" 's/`AG_ARMED_TAKE=false` (the default) only pages/AG_ARMED_TAKE only pages/' cr
ctl9 p-readme-delay-60 "$README" 's/(default \*\*60s\*\* = the PRIMARY/(default **90s** = the PRIMARY/' cr
ctl9 p-readme-coldtake "$README" 's/What an \*\*armed\*\* spare runs instead is the \*cold take\*/What an armed spare runs instead is a take/' cr
ctl9 p-template-literal-true "$ENVS" 's/ONLY the literal `true` arms it/any value arms it/' ct
ctl9 p-template-pairing "$ENVS" 's/HOLDER_GAP_DEMOTE_SECS + 30 (shipped 60 >= 30 + 30;/HOLDER_GAP_DEMOTE_SECS (shipped;/' ct
ctl9 p-notif-blocked "$NOTIF" 's/| `TAKEOVER BLOCKED — authorized-voter add failed` |/| `TAKEOVER BLOCKED` |/' cn
ctl9 p-notif-dry-cold "$NOTIF" 's/| `\[DRY RUN\] WOULD TAKE STAKED (Alpenglow cold take)` |/| `[DRY RUN] WOULD TAKE STAKED` |/' cn
ctl9 p-safety-armed-section "$SAFETY" 's/^### Armed cold take (opt-in, rc1)$/### Cold take/' cq
ctl9 p-safety-margin-200 "$SAFETY" 's/so 170 + 8 = 178, rounded up to \*\*200\*\*/so 170 + 8 = 178, rounded up to **180**/' cq
ctl9 p-safety-duplicates "$SAFETY" 's/exit is not a guarantee when the forks diverge/exit is a guarantee/' cq
ctl9 p-safety-unit-work "$SAFETY" 's/That line is in the monitor skeleton (AG-3.5)/That is unit work, not part of this release./' cq
ctl9 p-safety-pairing "$SAFETY" 's/`HOLDER_GAP_DEMOTE_SECS` + 30 (shipped: 60 >= 30 + 30)/`HOLDER_GAP_DEMOTE_SECS` + 30 (shipped: 90 >= 30 + 30)/' cq
ctl9 p-safety-refuse "$SAFETY" 's/an armed spare REFUSES to start when its `TAKEOVER_DELAY` is below 60 s/an armed spare warns at start when its `TAKEOVER_DELAY` is below 60 s/' cq
ctl9 p-template-refuse "$ENVS" 's/an armed spare below 60 REFUSES to start/an armed spare below 60 warns at start/' ct
ctl9 p-safety-rung "$SAFETY" 's/`HOLDER_UNREACHABLE_STOP_SECS` (default 30 s, floor 20)/`HOLDER_UNREACHABLE_STOP_SECS` (default 45 s, floor 30)/' cq
ctl9 p-safety-rung-page "$SAFETY" 's/`HOLDER HUNG — HARD STOP 🚨` names the three facts and the branch taken/the hard stop is silent/' cq
ctl9 p-safety-rung-row "$SAFETY" 's/since AG-3.8 the unreachable path has its own rung/the unreachable path pages and never stops anything/' cq
ctl9 p-safety-rung-quant "$SAFETY" 's/a knob of 22 would mean the third/a knob of 22 would work like 30/' cq
ctl9 p-safety-rung-clock "$SAFETY" 's/clock reads 0, 12, 23, 34 s/clock reads 0, 11, 22, 33 s/' cq
ctl9 p-safety-rung-dead "$SAFETY" 's/the validator is dead 48 to 51 s after the hang/the validator is dead 49 to 55 s after the hang/' cq
ctl9 p-safety-rung-wedged "$SAFETY" 's/70 to 73 s when it is wedged for its whole bound/70 to 75 s when it is wedged for its whole bound/' cq
ctl9 p-safety-rung-restart "$SAFETY" 's/\*\*A restarted validator is not a hung one (AG-3.8d).\*\*/**A note (AG-3.8d).**/' cq
ctl9 p-safety-rung-cannot-tell "$SAFETY" 's/cannot tell a hung validator from a restarted one/cannot tell/' cq
ctl9 p-notif-rung-restart "$NOTIF" 's/restarted since the last readable identity read/restarted/' cn
ctl9 p-template-rung-restart "$ENV_P" 's/a validator that restarted (since the last readable read, or during the episode)/a restarted process/' cpt
ctl9 p-primary-rung-clock "$PRIMARY" 's/clock reads 0, 12, 23, 34 s/clock reads 0, 11, 22, 33 s/' cp_
ctl9 p-primary-rung-restart "$PRIMARY" 's/A validator that RESTARTED since the last readable identity read is not hung either (AG-3.8d)/A validator that restarted/' cp_
ctl9 p-primary-rung-info "$PRIMARY" 's/log_info "\[hung\] validator restarted (new process/log_info "[hung] restarted (new process/' cp_
ctl9 p-safety-rung-margin "$SAFETY" 's/the fast branch kills at least about 10 s before it/the fast branch kills well after it/' cq
ctl9 p-readme-rung "$README" 's/hard-stopped by its own daemon after/paged after/' cr
ctl9 p-template-rung "$ENVS" 's/HOLDER_UNREACHABLE_STOP_SECS=30) hard-stops a mute validator/HOLDER_UNREACHABLE_STOP_SECS=30) pages a mute validator/' ct
ctl9 p-template-rung-quant "$ENV_P" 's/22 would be the third/22 would be the same/' cpt
ctl9 p-template-rung-clock "$ENV_P" 's/clock reads 0, 12, 23, 34 s/clock reads 0, 11, 22, 33 s/' cpt
ctl9 p-standby-template-dead "$ENVS" 's/not voting 48 to 51 s after the hang on its fast branch/not voting 49 to 55 s after the hang on its fast branch/' ct
ctl9 p-safety-envfile "$SAFETY" 's/systemd does not expand `\$HOME` in an `EnvironmentFile=`/systemd expands `$HOME` in an `EnvironmentFile=`/' cq
ctl9 p-readme-version "$README" 's/\*\*v0\.7 needs agave \/ Jito-Solana `4\.4\.0` or newer\*\*/v0.7 runs on any agave/' cr
ctl9 p-readme-27s "$README" 's/up to about 27 s at the decision point/up to about 15 s at the decision point/' cr
ctl9 p-readme-promoted "$README" 's/A promoted STANDBY (an unarmed spare never promotes itself; an armed one does, by the cold take) that later/A promoted STANDBY that later/' cr
ctl9 p-template-take "$ENVS" 's/(v0\.7: an unarmed spare - the default - never takes it: you move it to this node by the warm swap after the page;/(we TAKE it when PRIMARY drops it;/' ct
csd() { claims_for sysd "$1"; }
ctl9 p-sysd-armed "$SYSD" 's/unless it is armed (`AG_ARMED_TAKE=true`: a cold take/unless it is configured (a cold take/' csd
ctl9 p-sysd-timer "$SYSD" 's/in Alpenglow mode the spare takes nothing/the spare takes on its timer path/' csd
led_probe() { chk_text "$1" "Arming the fence \\(v0.7\\): set .LEDGER_PATH. explicitly" 5 "has no such detection" "falls to its stop path" "short form \`-l\`"; }
ctl9 led-no-detection "$MANUAL" 's/but the fence (`failover-fence.sh`, run by the unit.s `OnFailure=`) has no such detection/but the fence (`failover-fence.sh`, run by the unit'"'"'s `OnFailure=`) reads it like the daemons/' led_probe
[[ $c9_ok -eq 1 ]] && ok "(9) every put-back turns its case red:$c9_rows" || bad "(9) a control did not turn its case red"

results_banner
