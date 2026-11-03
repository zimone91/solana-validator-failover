#!/bin/bash
# v0.7 Block 7, trimmed for rc1 (TASK-BLOCK7-RC1.md): what the ARMED pair and the mainnet monitor-only phase still need. One suite, one section per item;
# each item is written red first on the AG-3 tip (c8989c1) and has its own mutants (mutate()).
#   (B7.1) _validator_pid is the validator, never an admin-client child of the daemon (set-identity / authorized-voter / contact-info / monitor / exit /
#          wait-for-restart-window): the unit's MainPID first, pgrep only as the fallback with the admin clients excluded - primary, standby, the fence
#          script and the arm ceremony (the last two are byte-identical copies of one function)
#   (B7.2) one instance per role: flock -n on "$STATE_DIR/.<role>.lock" at startup, before the first identity read; the second instance exits 3 with
#          one log line and one page SECOND INSTANCE REFUSED
#   (B7.3) the state file is written atomically (tmp + mv in the same directory, 0600); a torn file on load is one WARN, never an abort, and never a
#          lost lockout
#   (B7.4) fail-closed polarity at the two remaining AG stops: the primary's switch_to_staked and the standby's _prewarm_voter_add ask a positive
#          predicate (`if ! _ag_..._allowed`), so an undefined predicate withholds
#   (B7.5) DRY_RUN page storms: one dry page per ALERT_THROTTLE per reason (the primary's dry demote and the self-fence's dry pages), the standby's
#          cooldown / lockout WARN at most once per 60 s
# B7.6 (the version constant) is pinned in the `facts` job of .github/workflows/ci.yml, not here.
#
# harness: tests/lib/harness.sh - ok/bad+banners, paths, mutate(), extract_region, load_seam.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Block 7 trimmed for rc1: the validator pid, one instance per role, an atomic state file, fail-closed AG stops, quiet DRY_RUN (v0.7)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/b7.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cut_src() { local f="$WORK/seam.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$$.$RANDOM"; sed -n '1,/MAIN LOOP/p' "$1" > "$f"; printf '%s' "$f"; }
STK="StakedPubkey111111111111111111111111111111"
UNS="UnstakedPubkey1111111111111111111111111111"

# ── (0) the anchors every section below stands on ──────────────────────────────────────────────────────────────────────
echo ""; echo "─── (0) the daemons and the scripts the sections read are all there and parse ───"
b7_missing=""
for f in "$PRIMARY" "$STANDBY" "$HARNESS_DIR/systemd/failover-fence.sh" "$HARNESS_DIR/failover-arm.sh"; do
    [[ -f "$f" ]] || b7_missing="$b7_missing $(basename "$f")"
done
[[ -z "$b7_missing" ]] && ok "(0) both daemons, the fence script and the arm ceremony are present" || bad "(0) missing:$b7_missing"

# ══ B7.1 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.1 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.2 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.2 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.3 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ── (B7.3) the state file is replaced atomically; a torn file is never read ─────────────────────────────────────────────
echo ""; echo "─── (B7.3) save_state writes beside the state file and renames over it (0600); a file cut short is one WARN, nothing restored, the stamps HELD ───"
# Why rc1: with the armed take, a torn state loses SELF_FENCE_DEMOTE_TIME (the 600-s re-take lockout after a self-fence) and LAST_TAKEOVER_TIME (the cooldown). The old "> $STATE_FILE" TRUNCATED first: a crash between the
# truncate and the last printf left half a file. Now the whole save goes to "$STATE_FILE.tmp" and `mv -f` renames it over. Each world below is a FRESH bash process over the real seam (a crash is a real kill -9 of that process).
b73_run() {   # b73_run <daemon script> <dir> <mv log> <body> -> the body's stdout; the seam sourced, log_* / boot_id / mono_now mocked (mono 5000, boot B1); $D = the state dir, $L = the mv log; STATE_FILE is the body's to set
    local script="$1" dir="$2" mvlog="$3" body="$4" src w; src=$(cut_src "$script"); w="$WORK/b73-world.$$.$RANDOM.sh"
    mkdir -p "$dir"
    {
        printf 'set +e\nsource %q 2>/dev/null\n' "$src"
        printf 'D=%q; L=%q; STATE_DIR="$D"; STATE_FILE="$D/state"; STATE_MAX_AGE_SECS=900; PRIMARY_SELF_FENCE=true; STANDBY_SELF_FENCE=true\n' "$dir" "$mvlog"
        printf 'STAKED_PUBKEY=%q; UNSTAKED_PUBKEY=%q; CURRENT_IDENTITY=%q\n' "$STK" "$UNS" "$UNS"
        printf 'WARNS=0; log_info() { :; }; log_error() { :; }; log_warn() { WARNS=$((WARNS+1)); }\n'
        printf 'boot_id() { echo B1; }; mono_now() { echo 5000; }\n'
        printf '%s\n' "$body"
    } > "$w"
    { bash "$w" 2>/dev/null; } 2>/dev/null
    rm -f "$w"
}
b73_stamps='_last_confirmed_slot=777; SELF_FENCE_DEMOTE_TIME=4000; LAST_TAKEOVER_TIME=4200; LAST_SWITCH_TIME=4100'
b73_a_body='
'"$b73_stamps"'
save_state; i1=$(ls -i "$D/state" | awk "{print \$1}")
mv() { printf "MV %s\n" "$*" >> "$L"; command mv "$@"; }
save_state; i2=$(ls -i "$D/state" | awk "{print \$1}")
echo "inode=$([ "$i1" != "$i2" ] && echo replaced || echo same)"
echo "mvcalls=$(grep -c "^MV " "$L")"
echo "mvline=$(grep "^MV " "$L" | head -1)"
echo "mode=$(ls -l "$D/state" | cut -c1-10)"
echo "left=$(ls -A "$D" | tr "\n" " ")"
echo "last=$(tail -n 1 "$D/state")"
'
p_b73_save() {   # the real save: ONE mv of "<state>.tmp" onto the state file in the SAME directory, a NEW inode, mode 0600, nothing but the state file left, a whole file (last line SAVE_TS=<digits>)
    local d="$WORK/b73a.$RANDOM" o; o=$(b73_run "$1" "$d" "$WORK/b73a-mv.$RANDOM.log" "$b73_a_body")
    [[ "$(printf '%s\n' "$o" | grep -c '^inode=replaced$')" == "1" && "$(printf '%s\n' "$o" | grep -c '^mvcalls=1$')" == "1" \
       && "$(printf '%s\n' "$o" | grep -c -x "mvline=MV -f $d/state.tmp $d/state")" == "1" && "$(printf '%s\n' "$o" | grep -c '^mode=-rw-------$')" == "1" \
       && "$(printf '%s\n' "$o" | grep -c -x 'left=state ')" == "1" && "$(printf '%s\n' "$o" | grep -c -E '^last=SAVE_TS=[0-9]+$')" == "1" ]]
}
b73_b_body='
'"$b73_stamps"'
save_state; cp "$D/state" "$D/A"
mv() { return 1; }
SELF_FENCE_DEMOTE_TIME=4900; save_state; rc1=$?; unset -f mv
cmp -s "$D/A" "$D/state" && same1=yes || same1=no; [ -e "$D/state.tmp" ] && tmp1=left || tmp1=none
mkdir "$D/state.tmp"
save_state; rc2=$?
cmp -s "$D/A" "$D/state" && same2=yes || same2=no
echo "rc1=$rc1 same1=$same1 tmp1=$tmp1 rc2=$rc2 same2=$same2 warns=$WARNS"
'
p_b73_fail() {   # a failed rename and a failed write: rc 0 (a state that cannot be saved is a warning, never an abort), the previous COMPLETE file untouched, no tmp left behind by the rename failure, one WARN each
    [[ "$(b73_run "$1" "$WORK/b73b.$RANDOM" "$WORK/b73b-mv.log" "$b73_b_body")" == "rc1=0 same1=yes tmp1=none rc2=0 same2=yes warns=2" ]]
}
b73_c_body='
'"$b73_stamps"'
save_state; cp "$D/state" "$D/A"
SELF_FENCE_DEMOTE_TIME=4900; LAST_TAKEOVER_TIME=4950; LAST_SWITCH_TIME=4960
boot_id() { kill -9 $$; }
save_state
echo NOT-KILLED
'
b73_c2_body='
SELF_FENCE_DEMOTE_TIME=0; LAST_TAKEOVER_TIME=0; LAST_SWITCH_TIME=0; _last_confirmed_slot=
load_state; lrc=$?
echo "rc=$lrc|take=$LAST_TAKEOVER_TIME|fence=$SELF_FENCE_DEMOTE_TIME|switch=$LAST_SWITCH_TIME|slot=$_last_confirmed_slot|warns=$WARNS"
save_state; [ -e "$D/state.tmp" ] && echo "tmp=left" || echo "tmp=none"
'
p_b73_crash() {   # a SIGKILL in the middle of the write (the clock helper that runs last kills the shell): the state file is byte-for-byte the previous complete save, loads with no WARN and the old stamps; the next save sweeps the stale tmp
    local d="$WORK/b73c.$RANDOM" o1 o2 prev=""
    o1=$(b73_run "$1" "$d" "$WORK/b73c-mv.log" "$b73_c_body")
    [[ "$o1" != *NOT-KILLED* && -f "$d/A" && -f "$d/state.tmp" ]] && cmp -s "$d/A" "$d/state" || return 1
    [[ "$(tail -n 1 "$d/state.tmp" | grep -c '^SAVE_TS=')" == "0" ]] || return 1      # it died MID-write: the tmp is not a whole save
    o2=$(b73_run "$1" "$d" "$WORK/b73c-mv.log" "$b73_c2_body")
    [[ "$o2" == *"|warns=0"* && "$o2" == *"|slot=777|"* ]] && [[ "$(printf '%s\n' "$o2" | grep -c -x 'tmp=none')" == "1" ]] || return 1
    case "$1" in
        *standby*) [[ "$o2" == "rc=0|take=4200|fence=4000|switch=0|slot=777|warns=0"* ]] ;;
        *)         [[ "$o2" == "rc=0|take=0|fence=0|switch=4100|slot=777|warns=0"* ]] ;;
    esac
}
b73_d_body='
'"$b73_stamps"'
save_state; cp "$D/state" "$D/full"; sz=$(wc -c < "$D/full" | tr -d " ")
head -c $(( $(head -n 5 "$D/full" | wc -c | tr -d " ") + 4 )) "$D/full" > "$D/c1-midline"
sed "\$d" "$D/full" | sed "\$d" > "$D/c2-boundary"
head -c $(( sz - 6 )) "$D/full" > "$D/c3-cut-number"
head -c $(( sz - 1 )) "$D/full" > "$D/c4-no-newline"
: > "$D/c5-empty"
printf "LAST_SWITCH_TIME=1000\nLAST_TAKEOVER_TIME=1000\n" > "$D/c6-legacy"
cp "$D/full" "$D/c7-complete"
for c in c1-midline c2-boundary c3-cut-number c4-no-newline c5-empty c6-legacy c7-complete; do
    (   STATE_FILE="$D/$c"; SELF_FENCE_DEMOTE_TIME=0; LAST_TAKEOVER_TIME=0; LAST_SWITCH_TIME=0; _last_confirmed_slot=; WARNS=0
        load_state; lrc=$?
        echo "$c|rc=$lrc|take=${LAST_TAKEOVER_TIME:-}|fence=${SELF_FENCE_DEMOTE_TIME:-}|switch=${LAST_SWITCH_TIME:-}|slot=${_last_confirmed_slot:-}|warns=$WARNS" )
done
'
b73_torn_expect() {   # b73_torn_expect <script> <case> -> the line load_state must leave: held IN FULL from now (mono 5000), nothing else restored, ONE warning
    case "$1" in
        *standby*) printf '%s|rc=0|take=5000|fence=5000|switch=0|slot=|warns=1' "$2" ;;
        *)         printf '%s|rc=0|take=0|fence=0|switch=5000|slot=|warns=1' "$2" ;;
    esac
}
p_b73_torn() {   # four ways a file is cut short: inside a line, inside the SAVE_TS number, a whole last line without its newline, empty - each one WARN, rc 0, the stamps HELD, the slot NOT restored
    local o c; o=$(b73_run "$1" "$WORK/b73d.$RANDOM" "$WORK/b73d-mv.log" "$b73_d_body")
    for c in c1-midline c3-cut-number c4-no-newline c5-empty; do
        [[ "$(printf '%s\n' "$o" | grep -c -x -F "$(b73_torn_expect "$1" "$c")")" == "1" ]] || return 1
    done
    return 0
}
p_b73_whole() {   # the control the other way: what is NOT cut short loads exactly as before, with no torn WARN - a whole save (stamps verbatim, same boot; the slot restored), a cut at a line boundary (no BOOT_ID: the cross-boot rule holds the stamps), a pre-v0.6.9 file (legacy key: held)
    local o; o=$(b73_run "$1" "$WORK/b73e.$RANDOM" "$WORK/b73e-mv.log" "$b73_d_body")
    case "$1" in
        *standby*) [[ "$(printf '%s\n' "$o" | grep -c -x -F 'c7-complete|rc=0|take=4200|fence=4000|switch=0|slot=777|warns=0')" == "1" \
                      && "$(printf '%s\n' "$o" | grep -c -x -F 'c2-boundary|rc=0|take=5000|fence=5000|switch=0|slot=|warns=0')" == "1" \
                      && "$(printf '%s\n' "$o" | grep -c -x -F 'c6-legacy|rc=0|take=5000|fence=0|switch=0|slot=|warns=0')" == "1" ]] ;;
        *)         [[ "$(printf '%s\n' "$o" | grep -c -x -F 'c7-complete|rc=0|take=0|fence=0|switch=4100|slot=777|warns=0')" == "1" \
                      && "$(printf '%s\n' "$o" | grep -c -x -F 'c2-boundary|rc=0|take=0|fence=0|switch=5000|slot=|warns=0')" == "1" \
                      && "$(printf '%s\n' "$o" | grep -c -x -F 'c6-legacy|rc=0|take=0|fence=0|switch=5000|slot=|warns=0')" == "1" ]] ;;
    esac
}
b73_all_ok=1; b73_rows=""
for b73_s in "$PRIMARY" "$STANDBY"; do
    b73_n=$(basename "$b73_s" | cut -d- -f2)
    p_b73_save "$b73_s" && b73_rows="$b73_rows $b73_n:save" || { b73_all_ok=0; b73_rows="$b73_rows $b73_n:SAVE-FAILS"; }
    p_b73_fail "$b73_s" && b73_rows="$b73_rows fail" || { b73_all_ok=0; b73_rows="$b73_rows FAIL-PATHS"; }
    p_b73_crash "$b73_s" && b73_rows="$b73_rows crash" || { b73_all_ok=0; b73_rows="$b73_rows CRASH-TORN"; }
done
if [[ $b73_all_ok -eq 1 ]]; then
    ok "(B7.3a) save_state (primary and standby) writes \"\$STATE_FILE.tmp\" and renames it over: ONE observed 'mv -f <state>.tmp <state>' in the state's own directory, a NEW inode each time, mode 0600, nothing left but the state file, last line SAVE_TS=<digits>; a failed rename or a failed write is a WARN with rc 0, the previous whole file intact and no tmp left; a kill -9 in the middle of the write leaves the previous save byte-for-byte, which loads with no WARN and its stamps, and the next save sweeps the stale tmp -$b73_rows"
else
    bad "(B7.3a) atomic save:$b73_rows"
fi
b73_all_ok=1; b73_rows=""
for b73_s in "$PRIMARY" "$STANDBY"; do
    b73_n=$(basename "$b73_s" | cut -d- -f2)
    p_b73_torn "$b73_s" && b73_rows="$b73_rows $b73_n:torn" || { b73_all_ok=0; b73_rows="$b73_rows $b73_n:TORN-READ"; }
    p_b73_whole "$b73_s" && b73_rows="$b73_rows whole" || { b73_all_ok=0; b73_rows="$b73_rows WHOLE-CHANGED"; }
done
if [[ $b73_all_ok -eq 1 ]]; then
    ok "(B7.3b) load_state: a file cut short (inside a line; inside the SAVE_TS number; a whole last line without its newline; empty) logs ONE WARN, returns 0, restores NOTHING (the self-fence slot stays unset) and HOLDS the cooldown/lockout IN FULL from now (standby: LAST_TAKEOVER_TIME and SELF_FENCE_DEMOTE_TIME = 5000; primary: LAST_SWITCH_TIME = 5000); what is not cut short loads as before with no torn WARN: a whole save (stamps verbatim, slot restored), a cut at a line boundary (the cross-boot rule holds the stamps), a pre-v0.6.9 file (the legacy key is held) -$b73_rows"
else
    bad "(B7.3b) torn read:$b73_rows :: $(b73_run "$PRIMARY" "$WORK/b73x.$RANDOM" "$WORK/b73x-mv.log" "$b73_d_body" | tr '\n' ';' | cut -c1-420)"
fi
b73_fn_text() { sed -n '/^_state_complete() {/,/^}/p' "$1" | grep -v '^[[:space:]]*#'; }
b73_shape_ok() {
    local ps pp sp
    ps=$(sed -n '/^save_state() {/,/^}/p' "$PRIMARY"); sp=$(sed -n '/^save_state() {/,/^}/p' "$STANDBY"); pp=$(b73_fn_text "$PRIMARY")
    [[ -n "$pp" && "$pp" == "$(b73_fn_text "$STANDBY")" \
       && "$(printf '%s\n' "$ps" | grep -c -F '} > "$_tmp" 2>/dev/null')" == "1" && "$(printf '%s\n' "$sp" | grep -c -F '} > "$_tmp" 2>/dev/null')" == "1" \
       && "$(printf '%s\n' "$ps" | grep -c -F 'mv -f "$_tmp" "$STATE_FILE"')" == "1" && "$(printf '%s\n' "$sp" | grep -c -F 'mv -f "$_tmp" "$STATE_FILE"')" == "1" \
       && "$(printf '%s\n' "$ps$sp" | grep -c -F '> "$STATE_FILE"')" == "0" && "$(printf '%s\n' "$ps" | grep -c -F '_tmp="${STATE_FILE}.tmp"')" == "1" && "$(printf '%s\n' "$sp" | grep -c -F '_tmp="${STATE_FILE}.tmp"')" == "1" ]]
}
if b73_shape_ok; then
    ok "(B7.3c) shapes: _state_complete is byte-identical in both daemons; each save_state writes '> \"\$_tmp\"' (the tmp is \"\${STATE_FILE}.tmp\", beside the state file) and renames with 'mv -f \"\$_tmp\" \"\$STATE_FILE\"', and no '> \"\$STATE_FILE\"' is left in either"
else
    bad "(B7.3c) shapes: helper-equal=$([[ "$(b73_fn_text "$PRIMARY")" == "$(b73_fn_text "$STANDBY")" ]] && echo yes || echo no)"
fi
b73_ok=1; b73_rows=""
b73_shipped() {   # b73_shipped <predicate> <script> -> y|n, evaluated once per (predicate, script)
    local key="b73_rv_${1}_$(printf '%s' "$2" | cksum | cut -d' ' -f1)" v
    eval "v=\${$key:-}"
    if [[ -z "$v" ]]; then "$1" "$2" && v=y || v=n; eval "$key=$v"; fi
    printf '%s' "$v"
}
b73_ctl() {   # b73_ctl <label> <script> <sed expr> <predicate>: the predicate holds on the shipped script and FAILS on the mutant
    local label="$1" script="$2" expr="$3" pred="$4" m="$WORK/b73-$1.sh" rv mv_
    if ! mutate "$script" "$expr" "$m"; then b73_ok=0; b73_rows="$b73_rows $label:NOT-APPLIED"; return; fi
    rv=$(b73_shipped "$pred" "$script"); "$pred" "$m" && mv_=y || mv_=n
    if [[ "$rv" == "y" && "$mv_" == "n" ]]; then b73_rows="$b73_rows $label:red"; else b73_ok=0; b73_rows="$b73_rows $label:[shipped=$rv,mutant=$mv_]"; fi
}
b73_both() {   # the same sed expression on both daemons (the line is the same text in both)
    b73_ctl "pr-$1" "$PRIMARY" "$2" "$3"; b73_ctl "sb-$1" "$STANDBY" "$2" "$3"
}
b73_both nonatomic       's|^    } > "\$_tmp" 2>/dev/null \\$|    } > "$STATE_FILE" 2>/dev/null \\|;s|^    mv -f "\$_tmp" "\$STATE_FILE" 2>/dev/null \\$|    true \\|' p_b73_save
b73_both no-rename       's|^    mv -f "\$_tmp" "\$STATE_FILE" 2>/dev/null \\$|    true \\|' p_b73_save
b73_both nonatomic-crash 's|^    } > "\$_tmp" 2>/dev/null \\$|    } > "$STATE_FILE" 2>/dev/null \\|;s|^    mv -f "\$_tmp" "\$STATE_FILE" 2>/dev/null \\$|    true \\|' p_b73_crash
b73_both no-chmod        '/^    chmod 600 "\$_tmp" 2>\/dev\/null || true$/d' p_b73_save
b73_both tmp-elsewhere   's|_tmp="\${STATE_FILE}.tmp"|_tmp="/tmp/fo-state.$$.tmp"|' p_b73_save
b73_both tmp-left        's|state not persisted"; rm -f "\$_tmp" 2>/dev/null; return 0; }$|state not persisted"; return 0; }|' p_b73_fail
b73_both complete-never  '/^_state_complete() {/,/^}/ s|^    \[\[ .*\]\]$|    true|' p_b73_torn
b73_both complete-inverted '/^_state_complete() {/,/^}/ s|== "1" \]\]$|!= "1" ]]|' p_b73_whole
b73_both counts-bytes    '/^_state_complete() {/,/^}/ s|wc -l|wc -c|' p_b73_torn
b73_both torn-continues  '/^    if ! _state_complete; then$/,/^    fi$/ s|^        return 0$|        :|' p_b73_torn
b73_both torn-aborts     '/^    if ! _state_complete; then$/,/^    fi$/ s|^        return 0$|        exit 1|' p_b73_torn
b73_both warn-twice      '/^    if ! _state_complete; then$/,/^    fi$/ s|^        return 0$|        log_warn "again"; return 0|' p_b73_torn
b73_ctl sb-held-defaults "$STANDBY" '/^    if ! _state_complete; then$/,/^    fi$/ s|^        LAST_TAKEOVER_TIME=\$(mono_now); SELF_FENCE_DEMOTE_TIME=\$LAST_TAKEOVER_TIME$|        :|' p_b73_torn
b73_ctl pr-held-defaults "$PRIMARY" '/^    if ! _state_complete; then$/,/^    fi$/ s|^        LAST_SWITCH_TIME=\$(mono_now)$|        :|' p_b73_torn
b73_ctl sb-held-half     "$STANDBY" '/^    if ! _state_complete; then$/,/^    fi$/ s|; SELF_FENCE_DEMOTE_TIME=\$LAST_TAKEOVER_TIME$||' p_b73_torn
[[ $b73_ok -eq 1 ]] && ok "(B7.3d) CONTROLS: a save that truncates in place, one that never renames (the state file never appears), one that is not atomic when killed, one without chmod, a tmp in another directory, a failed rename that leaves its tmp, a test for a cut-short file that is always satisfied / inverted / counts bytes instead of newlines, a torn branch that does not return / aborts / warns twice, a hold that is left at defaults (either daemon) or only half held (standby) - each turns its case red:$b73_rows" || bad "(B7.3d) a control is not red:$b73_rows"

# ══ B7.3 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.4 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ── (B7.4) fail-closed polarity at the two remaining Alpenglow stops ──────────────────────────────────────────────────
echo ""; echo "─── (B7.4) the primary's re-take stop and the standby's pre-warm stop ask a positive predicate: an undefined predicate withholds ───"
# AG-3.1 gave the standby's TAKE this shape (`if ! _ag_take_allowed`); AG-1's form, `if _ag_mode; then <withhold>; fi`, lets an UNDEFINED predicate (rc 127) fall through to the mutation. Two such stops were left:
# the primary's switch_to_staked and the standby's _prewarm_voter_add. Both predicates are "never" in rc1; `_ag_mode` itself stays as the facts job pins it (unconditional `return 0`).
b74_pr_world() {   # b74_pr_world <script> <shadow|unset|ship> -> "rc=<switch_to_staked's rc>|withheld=<n>|admin=<n>|keypair=<n>": the primary's re-take, every gate before the stop mocked open
    local script="$1" mode="$2" src; src=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        EVF=$(mktemp); trap 'rm -f "$EVF"' EXIT
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; STAKED_KEYPAIR="$EVF.missing"; DRY_RUN=false; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15; TG_ENABLED=false
        _own_head_sample() { :; }; _fresh_proof_recheck() { return 0; }; _own_view_veto() { return 0; }
        mono_now() { echo 1000; }; save_state() { :; }; log_info() { :; }; log_warn() { :; }; log_error() { :; }; _watchdog_pet() { :; }
        _ag_take_withheld() { echo W >> "$EVF"; }
        alert() { case "$3" in *"keypair problem"*) echo K >> "$EVF" ;; esac; return 0; }
        timeout() { echo A >> "$EVF"; return 0; }
        case "$mode" in
            unset)  unset -f _ag_primary_retake_allowed ;;
            shadow) _ag_primary_retake_allowed() { return 0; } ;;
        esac
        switch_to_staked "recovery test"; rc=$?
        printf 'rc=%s|withheld=%s|admin=%s|keypair=%s' "$rc" "$(grep -c '^W$' "$EVF")" "$(grep -c '^A$' "$EVF")" "$(grep -c '^K$' "$EVF")"
    )
}
b74_sb_world() {   # b74_sb_world <script> <shadow|unset|ship> -> "admin=<n>": the standby's pre-warm with PREWARM_VOTER_ADD=true and DRY_RUN=false
    local script="$1" mode="$2" src; src=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        EVF=$(mktemp); trap 'rm -f "$EVF"' EXIT
        STAKED_PUBKEY="$STK"; STAKED_KEYPAIR="$EVF.kp"; DRY_RUN=false; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15; SOLANA_PATH="$EVF.bin"; LEDGER_PATH="$EVF.ledger"
        PREWARM_VOTER_ADD=true; _prewarm_done=0; _ag_pv_logged=0
        log_info() { :; }; log_warn() { :; }; log_error() { :; }; _watchdog_pet() { :; }
        timeout() { echo A >> "$EVF"; return 0; }
        case "$mode" in
            unset)  unset -f _ag_prewarm_allowed ;;
            shadow) _ag_prewarm_allowed() { return 0; } ;;
        esac
        _prewarm_voter_add; printf 'admin=%s' "$(grep -c '^A$' "$EVF")"
    )
}
p_b74_pr_closed() { [[ "$(b74_pr_world "$1" ship)" == "rc=1|withheld=1|admin=0|keypair=0" && "$(b74_pr_world "$1" unset)" == "rc=1|withheld=1|admin=0|keypair=0" ]]; }
p_b74_pr_open_when_allowed() { [[ "$(b74_pr_world "$1" shadow)" == "rc=1|withheld=0|admin=0|keypair=1" ]]; }
p_b74_sb_closed() { [[ "$(b74_sb_world "$1" ship)" == "admin=0" && "$(b74_sb_world "$1" unset)" == "admin=0" ]]; }
p_b74_sb_open_when_allowed() { [[ "$(b74_sb_world "$1" shadow)" == "admin=1" ]]; }
if p_b74_pr_closed "$PRIMARY" && p_b74_pr_open_when_allowed "$PRIMARY"; then
    ok "(B7.4a) primary switch_to_staked: as shipped, and with the predicate UNDEFINED (unset -f _ag_primary_retake_allowed), the re-take is withheld - rc 1, ONE _ag_take_withheld, no keypair test, no admin call; with the predicate shadowed to 'allowed' the stop is not what stops it (the next gate, the keypair test, answers)"
else
    bad "(B7.4a) primary stop: shipped=[$(b74_pr_world "$PRIMARY" ship)] undefined=[$(b74_pr_world "$PRIMARY" unset)] allowed=[$(b74_pr_world "$PRIMARY" shadow)]"
fi
if p_b74_sb_closed "$STANDBY" && p_b74_sb_open_when_allowed "$STANDBY"; then
    ok "(B7.4b) standby _prewarm_voter_add (PREWARM_VOTER_ADD=true, live): as shipped, and with _ag_prewarm_allowed UNDEFINED, ZERO admin calls; with the predicate shadowed to 'allowed' the add is issued once - the predicate is the gate"
else
    bad "(B7.4b) standby pre-warm: shipped=[$(b74_sb_world "$STANDBY" ship)] undefined=[$(b74_sb_world "$STANDBY" unset)] allowed=[$(b74_sb_world "$STANDBY" shadow)]"
fi
b74_fn_code() { sed -n "/^$2() {/,/^}/p" "$1" | grep -v '^[[:space:]]*#'; }
b74_shape_ok() {   # the stop's line, the predicate's one-line body, the facts pin of _ag_mode
    local pr_stop sb_first pp sp am_p am_s
    pr_stop=$(b74_fn_code "$PRIMARY" switch_to_staked | grep -c -x '    if ! _ag_primary_retake_allowed; then')
    sb_first=$(b74_fn_code "$STANDBY" _prewarm_voter_add | sed -n '2p')
    pp=$(grep -c -x '_ag_primary_retake_allowed() { return 1; }' "$PRIMARY"); sp=$(grep -c -x '_ag_prewarm_allowed() { return 1; }' "$STANDBY")
    am_p=$(grep -c -x '_ag_mode() { return 0; }' "$PRIMARY"); am_s=$(grep -c -x '_ag_mode() { return 0; }' "$STANDBY")
    [[ "$pr_stop" == "1" && "$sb_first" == "    if ! _ag_prewarm_allowed; then" && "$pp" == "1" && "$sp" == "1" && "$am_p" == "1" && "$am_s" == "1" ]]
}
if b74_shape_ok; then
    ok "(B7.4c) shapes: the primary's stop is 'if ! _ag_primary_retake_allowed; then' (once, in switch_to_staked), the standby's first statement is 'if ! _ag_prewarm_allowed; then'; both predicates are one line, 'return 1' (rc1: never); _ag_mode stays 'return 0' exactly once per daemon (the facts pin)"
else
    bad "(B7.4c) shapes: primary stop=$(b74_fn_code "$PRIMARY" switch_to_staked | grep -c -x '    if ! _ag_primary_retake_allowed; then') standby first=[$(b74_fn_code "$STANDBY" _prewarm_voter_add | sed -n '2p')] predicates=$(grep -c -x '_ag_primary_retake_allowed() { return 1; }' "$PRIMARY")/$(grep -c -x '_ag_prewarm_allowed() { return 1; }' "$STANDBY")"
fi
b74_ok=1; b74_rows=""
b74_ctl() {   # b74_ctl <label> <script> <sed expr> <predicate over a script>: holds on the shipped script, FAILS on the mutant
    local label="$1" script="$2" expr="$3" pred="$4" m="$WORK/b74-$1.sh" rv mv
    if ! mutate "$script" "$expr" "$m"; then b74_ok=0; b74_rows="$b74_rows $label:NOT-APPLIED"; return; fi
    "$pred" "$script" && rv=y || rv=n; "$pred" "$m" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then b74_rows="$b74_rows $label:red"; else b74_ok=0; b74_rows="$b74_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
b74_ctl pr-polarity-open "$PRIMARY" '/^switch_to_staked() {/,/^}/ s/^    if ! _ag_primary_retake_allowed; then$/    if _ag_primary_retake_allowed; then/' p_b74_pr_closed
b74_ctl pr-stop-removed "$PRIMARY" '/^switch_to_staked() {/,/^}/ s/^    if ! _ag_primary_retake_allowed; then$/    if false; then/' p_b74_pr_closed
b74_ctl pr-predicate-allows "$PRIMARY" 's/^_ag_primary_retake_allowed() { return 1; }$/_ag_primary_retake_allowed() { return 0; }/' p_b74_pr_closed
b74_ctl pr-gate-ignored "$PRIMARY" '/^switch_to_staked() {/,/^}/ s/^    if ! _ag_primary_retake_allowed; then$/    if true; then/' p_b74_pr_open_when_allowed
b74_ctl sb-polarity-open "$STANDBY" '/^_prewarm_voter_add() {/,/^}/ s/^    if ! _ag_prewarm_allowed; then$/    if _ag_prewarm_allowed; then/' p_b74_sb_closed
b74_ctl sb-stop-removed "$STANDBY" '/^_prewarm_voter_add() {/,/^}/ s/^    if ! _ag_prewarm_allowed; then$/    if false; then/' p_b74_sb_closed
b74_ctl sb-predicate-allows "$STANDBY" 's/^_ag_prewarm_allowed() { return 1; }$/_ag_prewarm_allowed() { return 0; }/' p_b74_sb_closed
b74_ctl sb-gate-ignored "$STANDBY" '/^_prewarm_voter_add() {/,/^}/ s/^    if ! _ag_prewarm_allowed; then$/    if true; then/' p_b74_sb_open_when_allowed
[[ $b74_ok -eq 1 ]] && ok "(B7.4d) CONTROLS: the polarity opened, the stop removed, a predicate that allows, a gate that ignores its predicate (always withholds) - each turns its case red:$b74_rows" || bad "(B7.4d) a control is not red:$b74_rows"
# ══ B7.4 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.5 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ══ B7.5 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

results_banner
