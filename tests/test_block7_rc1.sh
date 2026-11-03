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

# (B7.1) _validator_pid is the validator, never an admin-client child of the daemon (TASK-BLOCK7-RC1 item 1; the AG-1 D0 finding F7). The daemon's own bounded admin calls
# (agave-validator --ledger L set-identity | authorized-voter | contact-info | monitor | exit | wait-for-restart-window) carry the validator's process name and run while the
# hard stop runs: `pgrep | head -1` can answer one of them, and the hard stop would kill the client and call a still-STAKED hung holder "still running" (HARD STOP FAILED);
# in the fence script and the arm ceremony the pid is mapped to a systemd unit through /proc/<pid>/cgroup, so a client of the MONITOR unit would be taken for the validator's unit.
# The function: the unit's MainPID first (the daemons: P since AG-3.8, S is new), then pgrep per process name (agave-validator, fdctl on a Frankendancer box, solana-validator), every
# hit's argv read from ${PROC_ROOT:-/proc}/<pid>/cmdline (the fence and the arm: ${FENCE_PROC_ROOT:-/proc}): a hit with one of the six words as an ARGUMENT AFTER argv[0], as a
# whole word, is a client and is passed over; the first hit with --ledger and no such word wins, else the first hit that is not a client; a cmdline that cannot be read proves
# nothing (that hit counts as not-a-client, so with no readable cmdline at all the answer is the first pgrep hit, as before); only clients alive = no validator = empty.
#   (01) MainPID (canonical, > 1, alive) wins and pgrep is not asked (P; S is new)   (02) a MainPID that is empty / 0 / 1 / '007' / 'abc' / negative / too long / dead falls to pgrep WITH the exclusion
#   (03) a client of each of the six words, listed BEFORE the validator, is passed over (P S F A)   (04) only clients alive -> empty, rc 0, no byte printed
#   (05) --ledger and no client word wins over a hit that carries neither, in either order   (06) whole words only: --identity /keys/<word>.json, --ledger /mnt/<word> ... are not clients
#   (07) the word after --ledger is its VALUE (a relative ledger directory called `monitor`), argv[0] is not an argument   (08) unreadable cmdlines: the old first-hit answer is the floor
#   (09) the process names go through the same selection, in the old order and with the old number of pgrep calls   (10) the pid prints with no newline, rc 0
#   (11) the fence and the arm never ask the unit (no systemctl call)   (12) the REAL hard stop (P S) kills the validator, not the unkillable client listed first, and confirms DOWN
#   (13) the fence's and the arm's _detect_validator_unit names the VALIDATOR's unit when a client of the monitor unit is listed first
#   (14) twins: P and S carry one body, F and A are byte-identical, and the selection part is one text in all four   (15) structure by text   (16) CONTROLS (mutate()): every mutant turns its case red
# RED ON THE BASE (0730a78 + this section, the scripts unchanged): (01) on the standby only - the primary has had the MainPID path since AG-3.8 - and (02) (03) (04) (05) (08) (09) (11) (12) (13) (14a) (14c) (15),
# and every control of (16) (NOT-APPLIED: the lines they mutate do not exist yet). The hard stop of (12) on the base: rc=1, 'HARD STOP FAILED', events STOP,MASK,KILL 4001,KILL -9 4001 - the client, never the validator.
# NOT red on the base: (06) (07a) (07b) (10) (14b) - they pin what the code already does (a sole hit is answered whole; the fence and the arm are already byte-identical); their red is their mutants.
echo ""; echo "─── (B7.1) _validator_pid: the unit's MainPID first, pgrep after with the daemon's own admin clients passed over (P S F A) ───"
B71_FENCE="$HARNESS_DIR/systemd/failover-fence.sh"; B71_ARM="$HARNESS_DIR/failover-arm.sh"
B71_AV="/home/sol/.local/share/solana/install/active_release/bin/agave-validator"
B71_FD="/opt/firedancer/bin/fdctl"
B71_WORDS="set-identity authorized-voter contact-info monitor exit wait-for-restart-window"
B71_DIR="$WORK/b71"; mkdir -p "$B71_DIR"
b71_why=""

# ── fixtures: a fake /proc, the argv of a client and of the validator ───────────────────────────────────────────────────
b71_root() { mktemp -d "$B71_DIR/r.XXXXXX"; }
b71_proc() {   # b71_proc <root> <pid> [argv...] - <root>/<pid>/cmdline holds the argv NUL-terminated, as /proc/<pid>/cmdline does; no argv = a pid whose cmdline cannot be read
    local root="$1" pid="$2"; shift 2
    mkdir -p "$root/$pid" || return 1
    [[ $# -eq 0 ]] || printf '%s\0' "$@" > "$root/$pid/cmdline"
}
b71_adm() {    # b71_adm <root> <pid> <word> - the daemon's own bounded admin call: agave-validator --ledger L <word> ...
    local root="$1" pid="$2" word="$3" extra
    case "$word" in
        set-identity) extra="/keys/unstaked.json" ;;
        authorized-voter) extra="add /keys/staked.json" ;;
        exit) extra="--force" ;;
        wait-for-restart-window) extra="--min-idle-time 60" ;;
        *) extra="" ;;
    esac
    # shellcheck disable=SC2086
    b71_proc "$root" "$pid" "$B71_AV" --ledger /mnt/ledger "$word" $extra
}
b71_val() {    # b71_val <root> <pid> - the validator: --ledger among the usual options, no client word
    b71_proc "$1" "$2" "$B71_AV" --identity /keys/unstaked.json --vote-account /keys/vote.json --ledger /mnt/ledger --accounts /mnt/accounts --log /var/log/solana/validator.log --entrypoint entrypoint.mainnet-beta.solana.com:8001 --limit-ledger-size 50000000
}

# ── the runners ───────────────────────────────────────────────────────────────────────────────────────────────────────────
b71_fnsrc() {  # b71_fnsrc <fence|arm script> -> a file holding its _validator_pid and _detect_validator_unit, cached by path
    local s="$1" k
    k="$B71_DIR/fn.$(printf '%s' "$s" | cksum | cut -d' ' -f1)"
    if [[ ! -s "$k" ]]; then
        { extract_region "$s" '^_validator_pid() {' '^}$'; extract_region "$s" '^_detect_validator_unit() {' '^}$'; } > "$k"
    fi
    printf '%s' "$k"
}
b71_run() {    # b71_run <daemon|fence> <script> <MainPID text> <agave pids> <fdctl pids> <solana-validator pids> <proc root> [VALIDATOR_TYPE]
               # -> "<pid>|rc=<rc>|bytes=<n>|pgrep=<names asked, in order>|systemctl=<calls>": the REAL function over mocks at the I/O boundary only (timeout, systemctl, pgrep) and a fake /proc
    local kind="$1" script="$2" mp="$3" pa="$4" pf="$5" ps="$6" root="$7" vt="${8:-agave}" src log
    if [[ "$kind" == "daemon" ]]; then src=$(seam_cut "$script"); else src=$(b71_fnsrc "$script"); fi
    log=$(mktemp "$B71_DIR/run.XXXXXX")
    (
        set +e
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        timeout() { shift; "$@"; }
        systemctl() { echo "$*" >> "$log.sc"; printf '%s\n' "$mp"; }
        pgrep() { local l; echo "$2" >> "$log.pg"; case "$2" in agave-validator) l="$pa" ;; fdctl) l="$pf" ;; solana-validator) l="$ps" ;; *) l="" ;; esac; [[ -n "$l" ]] || return 1; printf '%s\n' $l; }
        VALIDATOR_TYPE="$vt"; PROC_ROOT="$root"; FENCE_PROC_ROOT="$root"; unset VALIDATOR_UNIT
        _validator_pid > "$log.out"; rc=$?
        printf '%s|rc=%s|bytes=%s|pgrep=%s|systemctl=%s' "$(cat "$log.out")" "$rc" "$(wc -c < "$log.out" | tr -d ' ')" "$(tr '\n' ',' < "$log.pg" 2>/dev/null)" "$(grep -c . "$log.sc" 2>/dev/null || echo 0)"
    )
}
b71_pid_of() { printf '%s' "${1%%|*}"; }
b71_hardstop() {   # b71_hardstop <script> -> rc=<rc>|status=<the last alert's status>|events=<STOP,MASK,KILL <argv>,...>
                   # the REAL _selffence_hard_stop, no unit (MainPID empty); the daemon's own set-identity client (4001: it survives every signal, a call wedged in the kernel) is listed BEFORE the validator (4002)
    local script="$1" src root ev
    src=$(seam_cut "$script"); root=$(b71_root); ev=$(mktemp "$B71_DIR/hs.XXXXXX")
    b71_adm "$root" 4001 set-identity; b71_val "$root" 4002
    printf '4001\n4002\n' > "$ev.live"
    (
        set +e
        # shellcheck disable=SC1090
        source "$src" 2>/dev/null
        STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VALIDATOR_TYPE="agave"; VALIDATOR_SERVICE="solana"
        SELF_FENCE_HARD_STOP=true; HARD_STOP_REVERIFY_SECS=7; TG_ENABLED=false; PROC_ROOT="$root"
        log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }; send_telegram(){ return 0; }; send_webhook(){ :; }
        _STATUS=""; alert(){ _STATUS="$3"; }
        timeout(){
            case "$*" in
                *systemctl\ stop*) echo STOP >> "$ev"; return 124 ;;
                *systemctl\ mask*) echo MASK >> "$ev"; return 0 ;;
            esac
            return 0
        }
        pgrep(){ [[ "$2" == "agave-validator" ]] && cat "$ev.live"; return 0; }
        kill(){ local a last=""; for a in "$@"; do last="$a"; done; echo "KILL $*" >> "$ev"; if [[ "$last" == "4002" ]]; then grep -v '^4002$' "$ev.live" > "$ev.live.n"; mv "$ev.live.n" "$ev.live"; fi; return 0; }
        sleep(){ :; }
        _selffence_hard_stop "test wedge"; rc=$?
        printf 'rc=%s|status=%s|events=%s' "$rc" "$_STATUS" "$(tr '\n' ',' < "$ev")"
    )
}

# ── the predicates: each takes <script> <kind>, returns 0 when the script behaves as specified, and leaves its reason in $b71_why ─────────────────────────
b71_p_mainpid() {   # (01) a live MainPID wins; pgrep is not asked; one bounded show
    local script="$1" kind="$2" r out
    [[ "$kind" == "daemon" ]] || return 0
    r=$(b71_root); b71_adm "$r" 4001 set-identity; b71_val "$r" 4002
    out=$(b71_run daemon "$script" "$$" "4001 4002" "" "" "$r"); b71_why="$out"
    [[ "$(b71_pid_of "$out")" == "$$" && "$(field "$out" pgrep)" == "" && "$(field "$out" systemctl)" == "1" ]]
}
b71_p_mainpid_unusable() {   # (02) an unusable MainPID falls to pgrep, and the pgrep answer passes the client over
    local script="$1" kind="$2" r out mp got=""
    [[ "$kind" == "daemon" ]] || return 0
    r=$(b71_root); b71_adm "$r" 4001 set-identity; b71_val "$r" 4002
    for mp in "" 0 1 007 abc -5 2147483000 99999999999999999999; do
        out=$(b71_run daemon "$script" "$mp" "4001 4002" "" "" "$r")
        [[ "$(b71_pid_of "$out")" == "4002" ]] || got="$got '$mp'->$(b71_pid_of "$out")"
    done
    b71_why="$got"; [[ -z "$got" ]]
}
b71_p_words() {   # (03) a client of each word (arg 3: one word only), listed BEFORE the validator, is passed over
    local script="$1" kind="$2" words="${3:-$B71_WORDS}" w r out got=""
    for w in $words; do
        r=$(b71_root); b71_adm "$r" 4001 "$w"; b71_val "$r" 4002
        out=$(b71_run "$kind" "$script" "" "4001 4002" "" "" "$r")
        [[ "$(b71_pid_of "$out")" == "4002" ]] || got="$got $w->$(b71_pid_of "$out")"
    done
    b71_why="$got"; [[ -z "$got" ]]
}
b71_p_only_admin() {   # (04) only clients alive: no validator - empty, rc 0, no byte; an agave box asks agave-validator, then solana-validator (the old shape)
    local script="$1" kind="$2" r out
    r=$(b71_root); b71_adm "$r" 4001 monitor; b71_adm "$r" 4002 set-identity
    out=$(b71_run "$kind" "$script" "" "4001 4002" "" "" "$r"); b71_why="$out"
    [[ "$(b71_pid_of "$out")" == "" && "$(field "$out" rc)" == "0" && "$(field "$out" bytes)" == "0" && "$(field "$out" pgrep)" == "agave-validator,solana-validator," ]]
}
b71_p_ledger() {   # (05) --ledger and no client word wins over a hit that carries neither, in either order
    local script="$1" kind="$2" r out1 out2
    r=$(b71_root); b71_proc "$r" 4001 "$B71_AV" --help; b71_val "$r" 4002
    out1=$(b71_run "$kind" "$script" "" "4001 4002" "" "" "$r"); out2=$(b71_run "$kind" "$script" "" "4002 4001" "" "" "$r")
    b71_why="client-first=$(b71_pid_of "$out1") validator-first=$(b71_pid_of "$out2")"
    [[ "$(b71_pid_of "$out1")" == "4002" && "$(b71_pid_of "$out2")" == "4002" ]]
}
b71_p_wholeword() {   # (06) a path or value that CONTAINS a client word is not a client: the sole hit is answered
    local script="$1" kind="$2" w r out got=""
    for w in $B71_WORDS; do
        r=$(b71_root)
        b71_proc "$r" 4002 "$B71_AV" --identity "/keys/$w.json" --log "$w.log" --ledger "/mnt/$w" --accounts "/data/$w/accounts" --snapshots "/data/x-$w"
        out=$(b71_run "$kind" "$script" "" "4002" "" "" "$r")
        [[ "$(b71_pid_of "$out")" == "4002" ]] || got="$got $w->'$(b71_pid_of "$out")'"
    done
    b71_why="$got"; [[ -z "$got" ]]
}
b71_p_ledgerval() {   # (07) the word after --ledger is its value: a relative ledger directory called like a client word is not a client
    local script="$1" kind="$2" w r out got=""
    for w in $B71_WORDS; do
        r=$(b71_root); b71_proc "$r" 4002 "$B71_AV" --identity /keys/unstaked.json --ledger "$w" --log -
        out=$(b71_run "$kind" "$script" "" "4002" "" "" "$r")
        [[ "$(b71_pid_of "$out")" == "4002" ]] || got="$got $w->'$(b71_pid_of "$out")'"
    done
    b71_why="$got"; [[ -z "$got" ]]
}
b71_p_argv0() {   # (07) argv[0] is not an argument: a bare client word in argv[0] does not make a client
    local script="$1" kind="$2" w r out got=""
    for w in $B71_WORDS; do
        r=$(b71_root); b71_proc "$r" 4002 "$w" --identity /keys/unstaked.json --ledger /mnt/ledger
        out=$(b71_run "$kind" "$script" "" "4002" "" "" "$r")
        [[ "$(b71_pid_of "$out")" == "4002" ]] || got="$got $w->'$(b71_pid_of "$out")'"
    done
    b71_why="$got"; [[ -z "$got" ]]
}
b71_p_unreadable() {   # (08) a cmdline that cannot be read proves nothing: the first pgrep hit is the floor; a readable client is still passed over, evidence still wins
    local script="$1" kind="$2" r out got=""
    r=$(b71_root)                                                                                              # no entry for either pid
    out=$(b71_run "$kind" "$script" "" "4001 4002" "" "" "$r"); [[ "$(b71_pid_of "$out")" == "4001" ]] || got="$got none->$(b71_pid_of "$out")"
    out=$(b71_run "$kind" "$script" "" "4001 4002" "" "" "$B71_DIR/no-such-proc"); [[ "$(b71_pid_of "$out")" == "4001" ]] || got="$got noroot->$(b71_pid_of "$out")"
    r=$(b71_root); b71_adm "$r" 4001 monitor; b71_proc "$r" 4002                                              # a readable client first, the validator unreadable
    out=$(b71_run "$kind" "$script" "" "4001 4002" "" "" "$r"); [[ "$(b71_pid_of "$out")" == "4002" ]] || got="$got client+unreadable->$(b71_pid_of "$out")"
    r=$(b71_root); b71_proc "$r" 4001; b71_val "$r" 4002                                                       # an unreadable hit first, the validator readable with --ledger
    out=$(b71_run "$kind" "$script" "" "4001 4002" "" "" "$r"); [[ "$(b71_pid_of "$out")" == "4002" ]] || got="$got unreadable+validator->$(b71_pid_of "$out")"
    r=$(b71_root); b71_proc "$r" 4001; b71_proc "$r" 4002 "$B71_AV" --help                                    # an unreadable hit first, a readable one with no evidence: the first non-client
    out=$(b71_run "$kind" "$script" "" "4001 4002" "" "" "$r"); [[ "$(b71_pid_of "$out")" == "4001" ]] || got="$got unreadable+noevidence->$(b71_pid_of "$out")"
    b71_why="$got"; [[ -z "$got" ]]
}
b71_p_names() {   # (09) fdctl (Frankendancer only) and solana-validator go through the same selection, in the old order, with the old number of pgrep calls
    local script="$1" kind="$2" r out got="" fdadm fdval
    r=$(b71_root)
    b71_proc "$r" 4001 "$B71_FD" set-identity --config /etc/firedancer/config.toml /keys/unstaked.json --force
    b71_proc "$r" 4002 "$B71_FD" run --config /etc/firedancer/config.toml
    b71_proc "$r" 4003 /usr/bin/solana-validator --ledger /mnt/ledger monitor
    b71_proc "$r" 4004 /usr/bin/solana-validator --ledger /mnt/ledger --identity /keys/unstaked.json
    b71_adm "$r" 4005 contact-info; b71_val "$r" 4006
    out=$(b71_run "$kind" "$script" "" "" "4001 4002" "" "$r" frankendancer)
    [[ "$(b71_pid_of "$out")" == "4002" && "$(field "$out" pgrep)" == "agave-validator,fdctl," ]] || got="$got fdctl->$out"
    out=$(b71_run "$kind" "$script" "" "" "4001 4002" "" "$r" agave)
    [[ "$(b71_pid_of "$out")" == "" && "$(field "$out" pgrep)" == "agave-validator,solana-validator," ]] || got="$got fdctl-on-agave->$out"
    out=$(b71_run "$kind" "$script" "" "" "" "4003 4004" "$r" agave)
    [[ "$(b71_pid_of "$out")" == "4004" && "$(field "$out" pgrep)" == "agave-validator,solana-validator," ]] || got="$got solana-validator->$out"
    out=$(b71_run "$kind" "$script" "" "" "" "4003 4004" "$r" frankendancer)
    [[ "$(b71_pid_of "$out")" == "4004" && "$(field "$out" pgrep)" == "agave-validator,fdctl,solana-validator," ]] || got="$got solana-validator-on-fd->$out"
    out=$(b71_run "$kind" "$script" "" "4005 4006" "" "4003 4004" "$r" agave)
    [[ "$(b71_pid_of "$out")" == "4006" && "$(field "$out" pgrep)" == "agave-validator," ]] || got="$got agave-first->$out"
    out=$(b71_run "$kind" "$script" "" "4005" "" "4003 4004" "$r" agave)
    [[ "$(b71_pid_of "$out")" == "4004" && "$(field "$out" pgrep)" == "agave-validator,solana-validator," ]] || got="$got agave-clients-only->$out"
    b71_why="$got"; [[ -z "$got" ]]
}
b71_p_shape() {   # (10) the pid prints with no newline, rc 0 - found and not found
    local script="$1" kind="$2" r out1 out2
    r=$(b71_root); b71_val "$r" 4002
    out1=$(b71_run "$kind" "$script" "" "4002" "" "" "$r"); out2=$(b71_run "$kind" "$script" "" "" "" "" "$r")
    b71_why="found=$out1 none=$out2"
    [[ "$(b71_pid_of "$out1")" == "4002" && "$(field "$out1" rc)" == "0" && "$(field "$out1" bytes)" == "4" && "$(b71_pid_of "$out2")" == "" && "$(field "$out2" rc)" == "0" && "$(field "$out2" bytes)" == "0" ]]
}
b71_p_nounit() {   # (11) the fence and the arm never ask the unit: no systemctl call, whatever the unit would have said
    local script="$1" kind="$2" r out
    [[ "$kind" == "fence" ]] || return 0
    r=$(b71_root); b71_adm "$r" 4001 set-identity; b71_val "$r" 4002
    out=$(b71_run fence "$script" "$$" "4001 4002" "" "" "$r"); b71_why="$out"
    [[ "$(b71_pid_of "$out")" == "4002" && "$(field "$out" systemctl)" == "0" ]]
}
b71_p_hardstop() {   # (12) the REAL hard stop kills the validator, never the client listed first, and confirms DOWN
    local script="$1" kind="$2" out
    [[ "$kind" == "daemon" ]] || return 0
    out=$(b71_hardstop "$script"); b71_why="$out"
    [[ "$(field "$out" rc)" == "0" && "$(field "$out" events)" == *"KILL 4002"* && "$(field "$out" events)" != *"4001"* && "$(field "$out" status)" == *"HARD STOP ✅"* ]]
}
b71_p_unit() {   # (13) _detect_validator_unit names the VALIDATOR's unit, not the monitor's, when the daemon's client (in the monitor unit's cgroup) is listed first
    local script="$1" kind="$2" r src out
    [[ "$kind" == "fence" ]] || return 0
    r=$(b71_root); b71_adm "$r" 4001 set-identity; b71_val "$r" 4002
    printf '0::/system.slice/solana-failover-monitor.service\n' > "$r/4001/cgroup"; printf '0::/system.slice/sol.service\n' > "$r/4002/cgroup"
    src=$(b71_fnsrc "$script")
    out=$( ( source "$src" 2>/dev/null; pgrep() { printf '4001\n4002\n'; }; FENCE_PROC_ROOT="$r"; VALIDATOR_TYPE=agave; unset VALIDATOR_UNIT; _detect_validator_unit ) )
    b71_why="unit='$out'"; [[ "$out" == "sol.service" ]]
}
b71_body() { sed -n '/^_validator_pid() {/,/^}$/p' "$1"; }
b71_sel() {   # the selection part of the function, as one text: the daemons' MainPID lines and the proc-root name normalised away
    b71_body "$1" | sed -e '/MainPID/d' -e '/kill -0/d' -e 's/FENCE_PROC_ROOT/PROC_ROOT/' -e 's/^    local p n c /    local n c /'
}
b71_p_same() {   # (14) two scripts carry the same _validator_pid, byte for byte (P/S, F/A)
    b71_why="$(b71_body "$1" | wc -c | tr -d ' ')B vs $(b71_body "$2" | wc -c | tr -d ' ')B"
    [[ -n "$(b71_body "$1")" && "$(b71_body "$1")" == "$(b71_body "$2")" ]]
}
b71_p_same_sel() {   # (14) the selection part is one text in two scripts
    b71_why="$(b71_sel "$1" | wc -c | tr -d ' ')B vs $(b71_sel "$2" | wc -c | tr -d ' ')B"
    [[ -n "$(b71_sel "$1")" && "$(b71_sel "$1")" == "$(b71_sel "$2")" ]]
}
b71_p_struct() {   # (15) by text: no `head -1` (the first-hit shape), ONE pgrep site; the fence and the arm name no unit; the daemons ask the unit once, bounded
    local script="$1" kind="$2" body why=""
    body=$(b71_body "$script" | grep -v '^[[:space:]]*#')
    [[ -n "$body" ]] || { b71_why="no function"; return 1; }
    [[ "$(printf '%s\n' "$body" | grep -c 'head -1')" == "0" ]] || why="$why head-1"
    [[ "$(printf '%s\n' "$body" | grep -c 'pgrep ')" == "1" ]] || why="$why pgrep-sites=$(printf '%s\n' "$body" | grep -c 'pgrep ')"
    if [[ "$kind" == "daemon" ]]; then
        [[ "$(printf '%s\n' "$body" | grep -c 'timeout 5 systemctl show -p MainPID --value "${VALIDATOR_SERVICE:-solana}"')" == "1" ]] || why="$why mainpid-show"
        [[ "$(printf '%s\n' "$body" | grep -c 'kill -0')" == "1" ]] || why="$why kill-0"
    else
        [[ "$(printf '%s\n' "$body" | grep -c -E 'systemctl|MainPID|VALIDATOR_SERVICE')" == "0" ]] || why="$why unit-named"
    fi
    b71_why="$why"; [[ -z "$why" ]]
}

# ── the checks ────────────────────────────────────────────────────────────────────────────────────────────────────────────
b71_fnsrc "$B71_FENCE" > /dev/null; b71_fnsrc "$B71_ARM" > /dev/null   # in THIS shell: an empty extraction is a FAIL of the suite, not a silent no-op
b71_chk() {   # b71_chk <text> <predicate> <targets: P S F A> - one ok when the predicate holds on every target, else one bad naming the targets that fail and why
    local text="$1" pred="$2" targets="$3" t script kind why=""
    for t in $targets; do
        case "$t" in P) script="$PRIMARY"; kind=daemon ;; S) script="$STANDBY"; kind=daemon ;; F) script="$B71_FENCE"; kind=fence ;; A) script="$B71_ARM"; kind=fence ;; esac
        b71_why=""
        "$pred" "$script" "$kind" || why="$why [$t: $b71_why]"
    done
    [[ -z "$why" ]] && ok "$text" || bad "$text -$why"
}
b71_chk "(B7.1-01) the unit's MainPID (canonical, > 1, alive) wins over pgrep, pgrep is not asked, one bounded show - the primary and the standby (S is new)" b71_p_mainpid "P S"
b71_chk "(B7.1-02) a MainPID that is empty, 0, 1, '007', 'abc', negative, 20 digits or dead falls to pgrep, and the pgrep answer passes the daemon's own set-identity client over - P S" b71_p_mainpid_unusable "P S"
b71_chk "(B7.1-03) a client of EACH of the six words (set-identity authorized-voter contact-info monitor exit wait-for-restart-window), listed before the validator, is passed over - P S F A" b71_p_words "P S F A"
b71_chk "(B7.1-04) only admin clients alive -> no validator: empty, rc 0, no byte printed, agave-validator then solana-validator asked - P S F A" b71_p_only_admin "P S F A"
b71_chk "(B7.1-05) --ledger and no client word wins over a hit that carries neither, whichever pgrep lists first - P S F A" b71_p_ledger "P S F A"
b71_chk "(B7.1-06) whole words only: --identity /keys/<word>.json, --log <word>.log, --ledger /mnt/<word> ... are not clients (the sole hit is answered) - P S F A" b71_p_wholeword "P S F A"
b71_chk "(B7.1-07a) the word after --ledger is its value: a relative ledger directory called like a client word is not a client - P S F A" b71_p_ledgerval "P S F A"
b71_chk "(B7.1-07b) argv[0] is not an argument: a bare client word in argv[0] does not make a client - P S F A" b71_p_argv0 "P S F A"
b71_chk "(B7.1-08) unreadable cmdlines prove nothing: no /proc entry at all -> the first pgrep hit (the old answer); a readable client is still passed over; --ledger evidence still wins - P S F A" b71_p_unreadable "P S F A"
b71_chk "(B7.1-09) fdctl (Frankendancer only) and solana-validator go through the same selection, in the old order, one pgrep per name asked - P S F A" b71_p_names "P S F A"
b71_chk "(B7.1-10) the pid prints with no newline and rc 0, found and not found - P S F A" b71_p_shape "P S F A"
b71_chk "(B7.1-11) the fence and the arm never ask the unit: no systemctl call even with a live MainPID-shaped answer on offer (the fence does not know VALIDATOR_SERVICE) - F A" b71_p_nounit "F A"
b71_chk "(B7.1-12) the REAL hard stop with no unit and the daemon's own set-identity client listed first kills the VALIDATOR (never the client), and confirms DOWN - P S" b71_p_hardstop "P S"
b71_chk "(B7.1-13) _detect_validator_unit answers the VALIDATOR's unit when a client in the monitor unit's cgroup is listed first - F A" b71_p_unit "F A"
if b71_p_same "$PRIMARY" "$STANDBY"; then ok "(B7.1-14a) the primary and the standby carry ONE _validator_pid body ($(b71_body "$PRIMARY" | wc -l | tr -d ' ') lines)"; else bad "(B7.1-14a) P and S _validator_pid bodies differ ($b71_why)"; fi
if b71_p_same "$B71_FENCE" "$B71_ARM"; then ok "(B7.1-14b) the fence script and the arm ceremony carry byte-identical _validator_pid bodies"; else bad "(B7.1-14b) F and A _validator_pid bodies differ ($b71_why)"; fi
if b71_p_same_sel "$PRIMARY" "$B71_FENCE" && b71_p_same_sel "$STANDBY" "$B71_ARM" && b71_p_same_sel "$PRIMARY" "$B71_ARM"; then ok "(B7.1-14c) the selection part (everything but the daemons' MainPID lines and the proc-root name) is ONE text in all four"; else bad "(B7.1-14c) the selection part differs between a daemon and the fence side ($b71_why)"; fi
b71_chk "(B7.1-15) by text: no 'head -1', ONE pgrep site; the daemons ask the unit once (timeout 5, kill -0), the fence and the arm name no unit - P S F A" b71_p_struct "P S F A"

# ── (16) CONTROLS: every mutant turns its case red (mutate() cannot silently no-op) ─────────────────────────────────────────────────────────
b71_ok=1; b71_rows=""
b71_ctl() {   # b71_ctl <label> <target: P S F A> <sed expr> <predicate> [more args] - the predicate holds on the shipped script and FAILS on the mutant
    local label="$1" t="$2" expr="$3" pred="$4" script kind m rv mv rvk; shift 4
    case "$t" in P) script="$PRIMARY"; kind=daemon ;; S) script="$STANDBY"; kind=daemon ;; F) script="$B71_FENCE"; kind=fence ;; A) script="$B71_ARM"; kind=fence ;; esac
    m="$B71_DIR/mut-$label-$t.sh"
    if ! mutate "$script" "$expr" "$m"; then b71_ok=0; b71_rows="$b71_rows $label/$t:NOT-APPLIED"; return; fi
    b71_body "$m" | "${BASH:-bash}" -n 2>/dev/null || { b71_ok=0; b71_rows="$b71_rows $label/$t:MUTANT-DOES-NOT-PARSE"; return; }   # red for the wrong reason is not red
    rvk="$B71_DIR/rv.$(printf '%s|%s|%s' "$pred" "$t" "$*" | cksum | cut -d' ' -f1)"   # the shipped script's answer is computed once per (predicate, target, args)
    if [[ -f "$rvk" ]]; then rv=$(cat "$rvk"); else "$pred" "$script" "$kind" "$@" && rv=y || rv=n; echo "$rv" > "$rvk"; fi
    "$pred" "$m" "$kind" "$@" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then b71_rows="$b71_rows $label/$t:red"; else b71_ok=0; b71_rows="$b71_rows $label/$t:[shipped=$rv,mutant=$mv]"; fi
}
b71_ctl_pair() {   # b71_ctl_pair <label> <fixed target> <mutated target> <sed expr> <predicate> - the predicate over (fixed script, mutant) holds on the shipped pair and FAILS on the mutant
    local label="$1" ta="$2" tb="$3" expr="$4" pred="$5" sa sb m rv mv
    case "$ta" in P) sa="$PRIMARY" ;; S) sa="$STANDBY" ;; F) sa="$B71_FENCE" ;; A) sa="$B71_ARM" ;; esac
    case "$tb" in P) sb="$PRIMARY" ;; S) sb="$STANDBY" ;; F) sb="$B71_FENCE" ;; A) sb="$B71_ARM" ;; esac
    m="$B71_DIR/mut-$label-$tb.sh"
    if ! mutate "$sb" "$expr" "$m"; then b71_ok=0; b71_rows="$b71_rows $label:NOT-APPLIED"; return; fi
    b71_body "$m" | "${BASH:-bash}" -n 2>/dev/null || { b71_ok=0; b71_rows="$b71_rows $label:MUTANT-DOES-NOT-PARSE"; return; }
    "$pred" "$sa" "$sb" && rv=y || rv=n; "$pred" "$sa" "$m" && mv=y || mv=n
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then b71_rows="$b71_rows $label:red"; else b71_ok=0; b71_rows="$b71_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
B71R='/^_validator_pid() {/,/^}/ '     # every expression below is scoped to the function: nothing else in the script moves
for b71_t in P S F A; do
    b71_ctl exclusion-removed "$b71_t" "$B71R"'s/^            \[\[ -z "\$sub" \]\] || continue$/            :/' b71_p_words
    for b71_w in $B71_WORDS; do
        b71_ctl "word-$b71_w-missing" "$b71_t" "$B71R"'s/\([ |]\)'"$b71_w"'\([|)]\)/\1zz-'"$b71_w"'\2/' b71_p_words "$b71_w"
    done
    b71_ctl substring-not-whole-word "$b71_t" "$B71R"'s/^\( *\)set-identity|authorized-voter|contact-info|monitor|exit|wait-for-restart-window)/\1*set-identity*|*authorized-voter*|*contact-info*|*monitor*|*exit*|*wait-for-restart-window*)/' b71_p_wholeword
    b71_ctl ledger-preference-removed "$b71_t" "$B71R"'s/^            \[\[ -z "\$led" \]\] || { pick=\$c; break; }$/            :/' b71_p_ledger
    b71_ctl unreadable-hit-skipped "$b71_t" "$B71R"'s/^            if \[\[ -r "\$f" \]\]; then$/            [[ -r "$f" ]] || continue; if [[ -r "$f" ]]; then/' b71_p_unreadable
    b71_ctl ledger-value-not-skipped "$b71_t" "$B71R"'s/^                    \[\[ -z "\$sk" \]\] || { sk=""; continue; }$/                    :/' b71_p_ledgerval
    b71_ctl argv0-compared "$b71_t" "$B71R"'s/^                    \[\[ \$i -gt 1 \]\] || continue$/                    :/' b71_p_argv0
    b71_ctl fdctl-ungated "$b71_t" "$B71R"'s/^        \[\[ "\$n" == "fdctl" && "\$VALIDATOR_TYPE" != "frankendancer" \]\] && continue$/        :/' b71_p_names
    b71_ctl head1-shape-back "$b71_t" "$B71R"'s/for c in \$(pgrep -x "\$n" 2>\/dev\/null); do/for c in $(pgrep -x "$n" 2>\/dev\/null | head -1); do/' b71_p_struct
    b71_ctl newline-printed "$b71_t" "$B71R"'s/printf .%s. "\$pick"/echo "$pick"/' b71_p_shape
    b71_ctl rc-nonzero-when-none "$b71_t" "$B71R"'s/^    return 0$/    return 1/' b71_p_shape
done
for b71_t in P S; do
    b71_ctl mainpid-not-preferred "$b71_t" "$B71R"'{ /kill -0/d; }' b71_p_mainpid
    b71_ctl mainpid-alive-check-removed "$b71_t" "$B71R"'s/ \&\& kill -0 "\$p" 2>\/dev\/null//' b71_p_mainpid_unusable
    b71_ctl mainpid-unbounded "$b71_t" "$B71R"'s/p=\$(timeout 5 systemctl show/p=$(systemctl show/' b71_p_struct
done
b71_ctl_pair identity-ps-broken P S "$B71R"'s/^        first=""; pick=""$/        first=""; pick=""  /' b71_p_same
b71_ctl_pair identity-fa-broken F A "$B71R"'s/^        first=""; pick=""$/        first=""; pick=""  /' b71_p_same
b71_ctl_pair selection-fence-word-dropped P F "$B71R"'s/|monitor|exit|/|zz-monitor|exit|/' b71_p_same_sel
[[ $b71_ok -eq 1 ]] && ok "(B7.1-16) every mutant turns its case red:$b71_rows" || bad "(B7.1-16) a control is not red (NOT-APPLIED = its sed matched nothing):$b71_rows"
# ══ B7.1 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.2 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ── (B7.2) one instance per role ────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (B7.2) a second copy of the same role is refused at startup: flock -n on \$STATE_DIR/.<role>.lock, exit 3 within 2 s, one log line, one page SECOND INSTANCE REFUSED ───"
# S-7: nothing stopped an operator's manual start beside the unit; two copies of one role run the same decisions and each can call set-identity. The lock is the first thing startup_checks does - before the fence markers are
# consumed (a second copy would park in HOLD beside the first) and before any identity read. The checks drive the REAL _single_instance_lock in separate bash processes: the holder keeps its descriptor open until it is
# killed, the second copy must exit 3. flock(1) is util-linux (the Linux legs); the macOS box has none, so there the same syscall is made by a python3 shim on the INHERITED descriptor (the lock belongs to the open file
# description the daemon holds, exactly as flock(1) does it).
b72_bin="$WORK/b72-bin"; mkdir -p "$b72_bin"; b72_bash=$(command -v bash)
b72_how=""
if command -v flock >/dev/null 2>&1; then
    b72_how="flock(1)"
elif command -v python3 >/dev/null 2>&1; then
    cat > "$b72_bin/flock" <<'PYEOF'
#!/usr/bin/env python3
import fcntl, sys
a = sys.argv[1:]
nb = False; code = 1; fd = None; i = 0
while i < len(a):
    if a[i] == "-n":
        nb = True
    elif a[i] == "-E":
        i += 1; code = int(a[i])
    else:
        fd = int(a[i])
    i += 1
try:
    fcntl.flock(fd, fcntl.LOCK_EX | (fcntl.LOCK_NB if nb else 0))
except BlockingIOError:
    sys.exit(code)
sys.exit(0)
PYEOF
    chmod +x "$b72_bin/flock"; b72_how="a python3 fcntl shim"
fi
if [[ -z "$b72_how" ]]; then
    echo "⏭ SKIP: (B7.2) neither flock(1) nor python3 on this box: the single-instance guard is tested on the Linux legs"
else
    b72_mk() {   # b72_mk <daemon script> <dir> <hold|try|noflock> -> prints the path of a world script: the seam sourced, the senders and the log mocked (every call appended to <dir>/log, <dir>/tg, <dir>/wh), STATE_DIR = ${B72_STATE_DIR:-<dir>/state}
        local script="$1" dir="$2" mode="$3" src w; src=$(cut_src "$script"); w="$WORK/b72-world.$$.$RANDOM.sh"
        mkdir -p "$dir"
        {
            printf 'set +e\numask 022\nsource %q 2>/dev/null\n' "$src"
            printf 'D=%q; STATE_DIR="${B72_STATE_DIR:-$D/state}"\n' "$dir"
            printf 'log_info() { :; }; log_warn() { echo "WARN $*" >> "$D/log"; }; log_error() { echo "ERROR $*" >> "$D/log"; }\n'
            printf 'send_telegram() { echo "TG $*" >> "$D/tg"; }; send_webhook() { echo "WH $*" >> "$D/wh"; }\n'
            [[ "$mode" != "noflock" ]] || printf 'command() { if [[ "$1" == "-v" && "$2" == "flock" ]]; then return 1; fi; builtin command "$@"; }\n'
            case "$mode" in
                hold)  printf '_single_instance_lock; echo "LOCKED rc=$?" > "$D/hold.out"; : > "$D/ready"; read -r _ < "$D/hold.fifo"\n' ;;
                *)     printf '_single_instance_lock; echo "LOCKED rc=$?" > "$D/try.out"; echo "STDERR-STILL-OPEN" >&2\n' ;;
            esac
        } > "$w"
        printf '%s' "$w"
    }
    b72_run() {   # b72_run <script> <dir> <mode> [path prefix] -> the world's exit status; its stderr in <dir>/err
        local w; w=$(b72_mk "$1" "$2" "$3")
        PATH="${4:-$b72_bin}:$PATH" "$b72_bash" "$w" 2> "$2/err"; local rc=$?
        rm -f "$w"; return $rc
    }
    p_b72_two() {   # the holder alive -> the second copy exits 3 inside 2 s with ONE log line and ONE page (telegram + webhook), the first copy is unaffected; the holder killed -> its stale lock file is acquired, quietly
        local script="$1" role d t0 rc hpid hw n
        role=$(basename "$script" | cut -d- -f2)
        d="$WORK/b72a.$RANDOM"; mkdir -p "$d"; mkfifo "$d/hold.fifo"
        hw=$(b72_mk "$script" "$d" hold)
        PATH="$b72_bin:$PATH" "$b72_bash" "$hw" 2>/dev/null & hpid=$!
        n=0; while [[ ! -e "$d/ready" && $n -lt 100 ]]; do sleep 0.1; n=$((n + 1)); done
        [[ -e "$d/ready" && "$(cat "$d/hold.out" 2>/dev/null)" == "LOCKED rc=0" ]] || { kill -9 "$hpid" 2>/dev/null; return 1; }
        t0=$SECONDS; b72_run "$script" "$d" try; rc=$?
        [[ $rc -eq 3 && $(( SECONDS - t0 )) -le 2 && ! -e "$d/try.out" ]] || { kill -9 "$hpid" 2>/dev/null; return 1; }
        [[ "$(wc -l < "$d/log" | tr -d ' ')" == "1" && "$(grep -c '^WARN .*SECOND INSTANCE REFUSED' "$d/log")" == "1" \
           && "$(wc -l < "$d/tg" | tr -d ' ')" == "1" && "$(grep -c 'SECOND INSTANCE REFUSED' "$d/tg")" == "1" \
           && "$(wc -l < "$d/wh" | tr -d ' ')" == "1" && "$(grep -c 'SECOND INSTANCE REFUSED' "$d/wh")" == "1" \
           && -f "$d/state/.$role.lock" ]] || { kill -9 "$hpid" 2>/dev/null; return 1; }
        kill -0 "$hpid" 2>/dev/null || return 1          # the first copy is unaffected
        kill -9 "$hpid" 2>/dev/null; { wait "$hpid"; } 2>/dev/null
        rm -f "$d/log" "$d/tg" "$d/wh"
        b72_run "$script" "$d" try; rc=$?
        [[ $rc -eq 0 && "$(cat "$d/try.out" 2>/dev/null)" == "LOCKED rc=0" && ! -e "$d/log" && ! -e "$d/tg" && ! -e "$d/wh" && "$(cat "$d/err")" == "STDERR-STILL-OPEN" ]]
    }
    p_b72_dir() {   # a missing state dir (and its missing parents) is created 0700; an existing one keeps its mode
        local script="$1" d="$WORK/b72b.$RANDOM" m1 m2
        mkdir -p "$d"
        B72_STATE_DIR="$d/new/sub/dir" b72_run "$script" "$d" try
        m1=$(ls -ld "$d/new/sub/dir" 2>/dev/null | cut -c1-10)
        mkdir -p "$d/old"; chmod 755 "$d/old"
        B72_STATE_DIR="$d/old" b72_run "$script" "$d" try
        m2=$(ls -ld "$d/old" 2>/dev/null | cut -c1-10)
        [[ "$m1" == "drwx------" && "$m2" == "drwxr-xr-x" && -f "$d/old/.$(basename "$script" | cut -d- -f2).lock" ]]
    }
    p_b72_guard() {   # no flock on the box, a flock that fails for another reason than a held lock, a lock file that cannot be opened: ONE WARN, the daemon starts, no page - it is a guard, not a gate
        local script="$1" d="$WORK/b72c.$RANDOM" rc1 rc2 rc3 role; role=$(basename "$script" | cut -d- -f2)
        mkdir -p "$d"
        b72_run "$script" "$d" noflock; rc1=$?
        [[ $rc1 -eq 0 && "$(wc -l < "$d/log" | tr -d ' ')" == "1" && "$(grep -c '^WARN .*single-instance guard is OFF' "$d/log")" == "1" && ! -e "$d/tg" && "$(cat "$d/try.out")" == "LOCKED rc=0" ]] || return 1
        rm -rf "$d"; mkdir -p "$d/rc2bin"; printf '#!/bin/sh\nexit 2\n' > "$d/rc2bin/flock"; chmod +x "$d/rc2bin/flock"
        b72_run "$script" "$d" try "$d/rc2bin"; rc2=$?
        [[ $rc2 -eq 0 && "$(wc -l < "$d/log" | tr -d ' ')" == "1" && "$(grep -c '^WARN .*flock failed (rc 2)' "$d/log")" == "1" && ! -e "$d/tg" && "$(cat "$d/try.out")" == "LOCKED rc=0" ]] || return 1
        rm -rf "$d"; mkdir -p "$d/state/.$role.lock"      # the lock "file" is a directory: it cannot be opened for writing
        b72_run "$script" "$d" try; rc3=$?
        [[ $rc3 -eq 0 && "$(wc -l < "$d/log" | tr -d ' ')" == "1" && "$(grep -c '^WARN .*cannot open' "$d/log")" == "1" && ! -e "$d/tg" && "$(cat "$d/try.out")" == "LOCKED rc=0" ]]
    }
    b72_fn() { sed -n '/^_single_instance_lock() {/,/^}/p' "$1" | grep -v '^[[:space:]]*#'; }
    b72_first_two() {   # the first two statements of startup_checks after the banner
        sed -n '/^startup_checks() {/,/^}/p' "$1" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*echo "' | grep -v '^[[:space:]]*$' | sed -n '2,3p' | sed 's/^[[:space:]]*//; s/[[:space:]]*#.*$//' | tr '\n' ';'
    }
    p_b72_shape() {   # the lock is the FIRST statement of startup_checks, before _consume_fence_markers; one flock call, one exit 3, one lock file name per role, descriptor 8 opened in a group so the shell's own stderr is not redirected
        local script="$1" role f; role=$(basename "$script" | cut -d- -f2); f=$(b72_fn "$script")
        [[ "$(grep -c '^_single_instance_lock() {' "$script")" == "1" && "$(printf '%s\n' "$f" | grep -c -F 'flock -n -E 77 8')" == "1" && "$(printf '%s\n' "$f" | grep -c -F 'exit 3 ;;')" == "1" \
           && "$(printf '%s\n' "$f" | grep -c -F "local _lf=\"\$STATE_DIR/.$role.lock\"")" == "1" && "$(printf '%s\n' "$f" | grep -c -F '{ exec 8>>"$_lf"; } 2>/dev/null')" == "1" \
           && "$(printf '%s\n' "$f" | grep -c -F 'alert_warn "🛑 SECOND INSTANCE REFUSED')" == "1" \
           && "$(b72_first_two "$script")" == "_single_instance_lock;_consume_fence_markers;" ]]
    }
    b72_all=1; b72_rows=""
    for b72_s in "$PRIMARY" "$STANDBY"; do
        b72_n=$(basename "$b72_s" | cut -d- -f2)
        p_b72_two "$b72_s" && b72_rows="$b72_rows $b72_n:two" || { b72_all=0; b72_rows="$b72_rows $b72_n:TWO-COPIES"; }
        p_b72_dir "$b72_s" && b72_rows="$b72_rows dir" || { b72_all=0; b72_rows="$b72_rows DIR-MODE"; }
        p_b72_guard "$b72_s" && b72_rows="$b72_rows guard" || { b72_all=0; b72_rows="$b72_rows GUARD-GATES"; }
        p_b72_shape "$b72_s" && b72_rows="$b72_rows shape" || { b72_all=0; b72_rows="$b72_rows SHAPE"; }
    done
    [[ $b72_all -eq 1 ]] && ok "(B7.2a) _single_instance_lock (primary and standby; flock via $b72_how): while a copy holds the lock a second copy exits 3 inside 2 s with ONE log line and ONE page on each channel ('SECOND INSTANCE REFUSED') and the first copy lives on; once the holder is killed its stale lock file is acquired, quietly, and the shell's stderr is still open; a missing state dir is created 0700 and an existing one keeps its mode; no flock, a flock failing with another status than 77, or a lock file that cannot be opened is one WARN and the daemon starts; the call is the first statement of startup_checks, before _consume_fence_markers -$b72_rows" || bad "(B7.2a) single instance:$b72_rows"
    b72_ok=1; b72_crows=""
    b72_ctl() {   # b72_ctl <label> <script> <sed expr> <predicate>: the predicate holds on the shipped script and FAILS on the mutant
        local label="$1" script="$2" expr="$3" pred="$4" m="$WORK/b72-$1.sh" rv mv_
        if ! mutate "$script" "$expr" "$m"; then b72_ok=0; b72_crows="$b72_crows $label:NOT-APPLIED"; return; fi
        "$pred" "$script" && rv=y || rv=n; "$pred" "$m" && mv_=y || mv_=n
        if [[ "$rv" == "y" && "$mv_" == "n" ]]; then b72_crows="$b72_crows $label:red"; else b72_ok=0; b72_crows="$b72_crows $label:[shipped=$rv,mutant=$mv_]"; fi
    }
    b72_both() { b72_ctl "pr-$1" "$PRIMARY" "$2" "$3"; b72_ctl "sb-$1" "$STANDBY" "$2" "$3"; }
    b72_both no-lock        's|^    flock -n -E 77 8; _rc=\$?$|    true; _rc=0|' p_b72_two
    b72_both exit-1         's|^            exit 3 ;;$|            exit 1 ;;|' p_b72_two
    b72_both no-page        's|^        77) alert_warn "|        77) true "|' p_b72_two
    b72_both page-twice     's|^\(        77) \)\(alert_warn .*\)$|\1\2; \2|' p_b72_two
    b72_both fd-closed      's|^        0)  return 0 ;;$|        0)  exec 8>\&-; return 0 ;;|' p_b72_two
    b72_both stderr-leak    's|^    { exec 8>>"\$_lf"; } 2>/dev/null; _rc=\$?$|    exec 8>>"$_lf" 2>/dev/null; _rc=$?|' p_b72_two
    b72_both dir-mode       's|^    ( umask 077; mkdir -p "\$STATE_DIR" ) 2>/dev/null$|    ( mkdir -p "$STATE_DIR" ) 2>/dev/null|' p_b72_dir
    b72_both chmod-existing 's|^    ( umask 077; mkdir -p "\$STATE_DIR" ) 2>/dev/null$|    ( umask 077; mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" ) 2>/dev/null|' p_b72_dir
    b72_both other-rc-refuses '/^        \*)  log_warn "\[single-instance\] flock failed/ s|^        \*)  |        *)  exit 3; |' p_b72_guard
    b72_both no-flock-refuses '/command -v flock/,/^    fi$/ s|^        return 0$|        exit 3|' p_b72_guard
    b72_both cannot-open-refuses '/cannot open/,/^    fi$/ s|^        return 0$|        exit 3|' p_b72_guard
    b72_ctl pr-lock-name-shared "$PRIMARY" 's|\.primary\.lock|.standby.lock|' p_b72_shape
    b72_ctl sb-lock-name-shared "$STANDBY" 's|\.standby\.lock|.primary.lock|' p_b72_shape
    b72_both call-removed   '/^    _single_instance_lock     # /d' p_b72_shape
    [[ $b72_ok -eq 1 ]] && ok "(B7.2b) CONTROLS: no flock call, exit 1 instead of 3, no page, a page twice, the descriptor closed after the lock (the lock dies with it), a stderr redirection that sticks to the shell, a state dir created without the 0700 umask, a chmod of an existing dir, a refusal on another flock status / on no flock / on an unopenable lock file, one lock name for both roles, the call removed - each turns its case red:$b72_crows" || bad "(B7.2b) a control is not red:$b72_crows"
fi

# (B7.2c) the unit the deploy scripts write does not restart a copy the lock refused. With Restart=always, RestartSec=10 and a manual copy holding the lock, systemd would start the unit's copy every 10 s,
# refuse it every time and page SECOND INSTANCE REFUSED six times a minute. Exit status 3 is the refusal's alone; RestartPreventExitStatus=3 stops the loop at the first one (the unit shows `failed`, the manual copy is
# untouched). Text pin, no flock needed. (The armed monitor unit is Restart=no already.)
p_b72_unit() {   # the deploy script's unit heredoc: Restart=always once, RestartPreventExitStatus=3 once
    local script="$1" blk; blk=$(sed -n "/<< 'SERVICEEOF'/,/^SERVICEEOF\$/p" "$script")
    [[ "$(printf '%s\n' "$blk" | grep -c -x 'Restart=always')" == "1" && "$(printf '%s\n' "$blk" | grep -c -x 'RestartPreventExitStatus=3')" == "1" ]]
}
b72u_ok=1; b72u_rows=""
for b72u_s in deploy-failover.sh deploy-failover-standby.sh; do
    b72u_f="$HARNESS_DIR/$b72u_s"
    if p_b72_unit "$b72u_f"; then b72u_rows="$b72u_rows $b72u_s:pinned"; else b72u_ok=0; b72u_rows="$b72u_rows $b72u_s:NOT-PINNED"; fi
    b72u_m="$WORK/b72u-$b72u_s"
    if mutate "$b72u_f" '/^RestartPreventExitStatus=3$/d' "$b72u_m"; then
        if p_b72_unit "$b72u_m"; then b72u_ok=0; b72u_rows="$b72u_rows $b72u_s:MUTANT-GREEN"; else b72u_rows="$b72u_rows mutant:red"; fi
    else b72u_ok=0; b72u_rows="$b72u_rows $b72u_s:NOT-APPLIED"; fi
done
[[ $b72u_ok -eq 1 ]] && ok "(B7.2c) the unit each deploy script writes carries Restart=always once and RestartPreventExitStatus=3 once: a refused copy (exit 3) is not restarted every RestartSec into a page every 10 s; the mutant without the line is red -$b72u_rows" || bad "(B7.2c) deploy unit:$b72u_rows"
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
       && "$(printf '%s\n' "$ps" | grep -c -F '} > "$_state_new" 2>/dev/null')" == "1" && "$(printf '%s\n' "$sp" | grep -c -F '} > "$_state_new" 2>/dev/null')" == "1" \
       && "$(printf '%s\n' "$ps" | grep -c -F 'mv -f "$_state_new" "$STATE_FILE"')" == "1" && "$(printf '%s\n' "$sp" | grep -c -F 'mv -f "$_state_new" "$STATE_FILE"')" == "1" \
       && "$(printf '%s\n' "$ps$sp" | grep -c -F '> "$STATE_FILE"')" == "0" && "$(printf '%s\n' "$ps" | grep -c -F '_state_new="${STATE_FILE}.tmp"')" == "1" && "$(printf '%s\n' "$sp" | grep -c -F '_state_new="${STATE_FILE}.tmp"')" == "1" ]]
}
if b73_shape_ok; then
    ok "(B7.3c) shapes: _state_complete is byte-identical in both daemons; each save_state writes '> \"\$_state_new\"' (the tmp is \"\${STATE_FILE}.tmp\", beside the state file) and renames with 'mv -f \"\$_state_new\" \"\$STATE_FILE\"', and no '> \"\$STATE_FILE\"' is left in either"
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
b73_both nonatomic       's|^    } > "\$_state_new" 2>/dev/null \\$|    } > "$STATE_FILE" 2>/dev/null \\|;s|^    mv -f "\$_state_new" "\$STATE_FILE" 2>/dev/null \\$|    true \\|' p_b73_save
b73_both no-rename       's|^    mv -f "\$_state_new" "\$STATE_FILE" 2>/dev/null \\$|    true \\|' p_b73_save
b73_both nonatomic-crash 's|^    } > "\$_state_new" 2>/dev/null \\$|    } > "$STATE_FILE" 2>/dev/null \\|;s|^    mv -f "\$_state_new" "\$STATE_FILE" 2>/dev/null \\$|    true \\|' p_b73_crash
b73_both no-chmod        '/^    chmod 600 "\$_state_new" 2>\/dev\/null || true$/d' p_b73_save
b73_both tmp-elsewhere   's|_state_new="\${STATE_FILE}.tmp"|_state_new="/tmp/fo-state.$$.tmp"|' p_b73_save
b73_both tmp-left        's|state not persisted"; rm -f "\$_state_new" 2>/dev/null; return 0; }$|state not persisted"; return 0; }|' p_b73_fail
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
        switch_to_staked "recovery test" 2>/dev/null; rc=$?   # the "unset" world calls an UNDEFINED predicate on purpose: bash says "command not found" - not the suite's output
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
        _prewarm_voter_add 2>/dev/null; printf 'admin=%s' "$(grep -c '^A$' "$EVF")"   # (the "unset" world: an undefined predicate on purpose)
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
echo ""; echo "─── (B7.5) DRY_RUN page storms: one dry page per ALERT_THROTTLE per reason; the standby's cooldown / lockout WARN at most once per 60 s ───"
# The mainnet monitor-only phase (DRY_RUN=true) runs the SAME decisions as a live node and only swaps the mutation for a log line and a page. A decision that holds
# for many cycles - the offline node (every ~5 s cycle), the self-fence's getHealth path (every 3 s), its frozen-slot path (every 30 s) - used to page every time
# it was reached. The primary's switch_to_unstaked is the ONE function every demote goes through (the internet-lost path, the four self-fence signals, the gap
# rule, the vote-latency and delinquency escalations, the fence-rot demote): its DRY_RUN branch now logs EVERY call and pages once per ALERT_THROTTLE per reason
# (the reason with its digits stripped; a table of keys). The standby's two per-cycle WARN lines (the takeover cooldown, the re-take lockout) are WARN once per
# 60 s and INFO in between. Names below are all b75_* (one file, five sections). Worlds:
#   b75_calls  - the REAL switch_to_unstaked over a simulated clock, one call per spec line (the exact throttle semantics)
#   b75_loop   - the REAL main-loop region of the primary (the gap-demote suite's technique) with the REAL check_self_fence_isolation and switch_to_unstaked over
#                a plan of cycles and a mocked LOCAL RPC: the wiring, end to end (offline, getHealth behind, frozen slot, silent RPC, own-vote lag)
#   b75_sb     - the REAL attempt_takeover of the standby, one call per simulated second (turbo), the log levels of the two sites
b75_n()  { printf '%s\n' "$1" | grep -c -E "$2"; }                                                                          # b75_n <events> <regex> - how many event lines match
b75_at() { printf '%s\n' "$1" | grep -E "$2" | awk '{ printf "%s%s", (n++ ? "," : ""), $2 } END { print "" }'; }          # b75_at <events> <regex> - the 2nd field (the time) of the matching lines, comma-joined
b75_spec() { printf '%s\t%s\n' "$@"; }                                                                                     # b75_spec <t> <reason> [<t> <reason> ...] -> the spec lines of b75_calls
b75_plan() { local i s=""; for ((i = 0; i < $1; i++)); do s="$s $2"; done; printf '%s' "${s# }"; }                          # b75_plan <n> <token> -> n copies of the token
b75_ri() { printf 'Internet lost (%sx) — no tier verification needed' "$1"; }                                               # the main loop's reason: the failure count changes every cycle
b75_rb() { printf 'self-fence: local getHealth behind %s slots (> 150) — isolated from supermajority' "$1"; }               # the self-fence (2) reason: the slot count changes
b75_rf() { printf 'self-fence: local confirmed slot frozen %ss — isolated from supermajority' "$1"; }                       # the self-fence (1b) reason: the seconds change
b75_spec_same() { local a=() i; for ((i = 0; i < 20; i++)); do a[${#a[@]}]=$(( i * 5 )); a[${#a[@]}]="$(b75_ri $(( i + 1 )))"; done; b75_spec "${a[@]}"; }   # 20 calls, 5 s apart, one reason with a new number each time
b75_why=""

# ── world 1: the real switch_to_unstaked over a simulated clock ───────────────────────────────────────────────────────
b75_calls() {   # b75_calls <script> <spec> [VAR=val ...] -> P <t> <status>|<reason> (a page) / L <t> (a dry log line) / R <t> <rc> (a call's return) / ADMIN <argv> / N <keys in the throttle table>
    local script="$1" spec="$2" cs b75_t b75_r b75_rc kv; shift 2
    cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        EV=$(mktemp); KP=$(mktemp); echo '[1]' > "$KP"
        trap 'rm -rf "$EV" "$EV.bin" "$KP"' EXIT
        mkdir -p "$EV.bin"; printf '#!/bin/bash\necho "ADMIN $*" >> "%s"\nexit 0\n' "$EV" > "$EV.bin/agave-validator"; chmod +x "$EV.bin/agave-validator"
        SOLANA_PATH="$EV.bin"; LEDGER_PATH="$EV.ledger"; VALIDATOR_TYPE=agave; SETIDENTITY_TIMEOUT=15
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; UNSTAKED_KEYPAIR="$KP"; CURRENT_IDENTITY="$STK"
        DRY_RUN=true; ALERT_THROTTLE=600; TG_ENABLED=false; UNDEF=0
        for kv in "$@"; do eval "$kv"; done
        [[ "$UNDEF" == "1" ]] && unset -f _dry_page_throttled
        B=100000; _SIM_NOW=$B
        mono_now() { echo "$_SIM_NOW"; }
        log_info() { :; }; log_error() { :; }; _watchdog_pet() { :; }; sleep() { :; }; save_state() { :; }
        timeout() { [[ "$1" == "-k" ]] && shift 2; shift; "$@"; }
        get_local_identity() { echo "$STK"; }
        log_warn() { case "$1" in "[DRY RUN] Would switch to UNSTAKED"*) printf 'L %s\n' $(( _SIM_NOW - B )) >> "$EV" ;; esac; }
        alert() { printf 'P %s %s|%s\n' $(( _SIM_NOW - B )) "$3" "$1" >> "$EV"; }
        while IFS=$'\t' read -r b75_t b75_r; do
            [[ -n "$b75_t" ]] || continue
            _SIM_NOW=$(( B + b75_t ))
            switch_to_unstaked "$b75_r" 2>/dev/null; b75_rc=$?   # (UNDEF=1 calls an undefined predicate on purpose: bash says "command not found")
            printf 'R %s %s\n' "$b75_t" "$b75_rc" >> "$EV"
        done <<< "$spec"
        printf 'N %s\n' "${#_dry_page_keys[@]}" >> "$EV"
        cat "$EV"
    )
}

# ── world 2: the real main-loop region of the primary over a plan (token = S <flags>; i = the internet check fails that cycle) ──────────────────────────────
b75_loop() {   # b75_loop <script> <plan> [VAR=val ...] -> CYCLE k / PAGE <t> <status> / TXT <t> <text> / DRYLOG <dry log line> / ADMIN <argv>;  SF = the mocked LOCAL RPC: ok behind frozen flap vlag mixed
    local script="$1" plan="$2" cs region kv; shift 2
    cs=$(cut_src "$script")
    region=$(extract_region "$script" '^while \$_running; do' '^done$') || { echo "NO-REGION"; return 0; }
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        eval "run_loop() {
$region
}"
        EV=$(mktemp); KP=$(mktemp); echo '[1]' > "$KP"
        trap 'rm -rf "$EV" "$EV.bin" "$KP"' EXIT
        mkdir -p "$EV.bin"; printf '#!/bin/bash\necho "ADMIN $*" >> "%s"\nexit 0\n' "$EV" > "$EV.bin/agave-validator"; chmod +x "$EV.bin/agave-validator"
        SOLANA_PATH="$EV.bin"
        ev() { printf '%s\n' "$*" >> "$EV"; }
        read -r -a PLAN <<< "$plan"
        IDX=0; CYC=0
        STAKED_PUBKEY="$STK"; UNSTAKED_PUBKEY="$UNS"; UNSTAKED_KEYPAIR="$KP"; LEDGER_PATH="$EV.ledger"; VALIDATOR_TYPE=agave; LOCAL_RPC="http://mock-local"
        TG_ENABLED=false; DRY_RUN=true; ALERT_THROTTLE=600; PRIMARY_SELF_FENCE=true; CHECK_INTERVAL=3; TURBO_INTERVAL=1; _current_interval=3
        CONNECTIVITY_RETRIES=1; MAX_VOTE_LATENCY=0; DELINQUENCY_RETRIES=1; STARTUP_GRACE=30; RECOVERY_MODE=manual; SETIDENTITY_TIMEOUT=15
        SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=150; SELF_FENCE_NOANSWER_SECS=30
        SELF_FENCE_VOTE_LAG_SLOTS=32; SELF_FENCE_VOTE_LAG_SECS=20; SELF_FENCE_VOTE_LAG_RESET_CYCLES=3; VOTE_PUBKEY=""
        T_BASE=1700000000; _SIM_NOW=$T_BASE; ICOST=2; SF=ok
        for kv in "$@"; do eval "$kv"; done
        mono_now() { echo "$_SIM_NOW"; }
        tok_has() { local t="${PLAN[$IDX]}"; [[ "${t:1}" == *"$1"* ]]; }
        _last_heartbeat=$(date +%s); HEARTBEAT_INTERVAL=2000000000; _last_known_identity="$STK"
        rotate_log() { CYC=$(( CYC + 1 )); [[ $CYC -gt $(( ${#PLAN[@]} + 5 )) ]] && _running=false; }   # a safety valve: the loop can never outlive its plan
        heartbeat_ping() { :; }; _alpenglow_gate_check() { :; }; _version_startup_check() { :; }; _vat_cycle() { :; }; _fence_rot_check() { :; }; _g2_step() { :; }; _elapsed_step() { :; }
        flush_pending_alerts() { :; }; display_status() { :; }; save_state() { :; }; _watchdog_pet() { :; }; send_telegram() { return 0; }; send_webhook() { :; }
        log_info() { :; }; log_error() { :; }
        log_warn() { case "$1" in "[DRY RUN]"*) ev "DRYLOG ${1:0:90}" ;; esac; }
        alert() { ev "PAGE $(( _SIM_NOW - T_BASE )) $3"; ev "TXT $(( _SIM_NOW - T_BASE )) ${1:0:140}"; return 0; }
        alert_info() { :; }; alert_warn() { :; }
        get_local_identity() { echo "$STAKED_PUBKEY"; }
        check_internet() { tok_has i && return 1; return 0; }
        check_identity_collision() { return 0; }
        tier1_check_delinquency() { return 1; }
        tier1_get_vote_latency() { echo 1; }
        verify_latency_tiered() { return 0; }
        _vat_hold() { return 1; }
        window_push() { :; }; window_count() { echo 0; }; window_triggered() { return 1; }; window_mostly_clear() { return 1; }; window_reset() { :; }
        timeout() { [[ "$1" == "-k" ]] && shift 2; shift; "$@"; }
        sleep() { :; }
        curl() {   # the LOCAL requests of the self-fence (the only reads the cycle makes), answered by SF from the cycle index
            local d="" c=$IDX cm own
            while [[ $# -gt 0 ]]; do if [[ "$1" == "-d" ]]; then d="$2"; shift 2; continue; fi; shift; done
            case "$d" in
                *getSlot*)
                    if [[ "$SF" == "flap" && $(( c % 15 )) -ge 3 ]]; then return 7; fi
                    if [[ "$SF" == "frozen" || "$SF" == "mixed" ]]; then printf '{"jsonrpc":"2.0","result":1000000,"id":1}'; else printf '{"jsonrpc":"2.0","result":%s,"id":1}' $(( 1000000 + 8 * c )); fi ;;
                *getHealth*)
                    if [[ "$SF" == "behind" ]] || { [[ "$SF" == "mixed" ]] && [[ $(( c % 12 )) -eq 11 ]]; }; then
                        printf '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind","data":{"numSlotsBehind":%s}},"id":1}' $(( 20000 + 7 * c ))
                    else printf '{"jsonrpc":"2.0","result":"ok","id":1}'; fi ;;
                *getVoteAccounts*)
                    cm=$(( 2000000 + 8 * c )); own=$(( cm - 5 ))
                    if [[ "$SF" == "vlag" && $(( c % 20 )) -ge 4 ]]; then own=$(( cm - 500 )); fi
                    printf '{"jsonrpc":"2.0","result":{"current":[{"votePubkey":"Cluster111","lastVote":%s},{"votePubkey":"%s","lastVote":%s}],"delinquent":[]},"id":1}' "$cm" "$VOTE_PUBKEY" "$own" ;;
                *) return 7 ;;
            esac
        }
        _watchdog_sleep() {   # every cycle ends here (_cycle_sleep): the clock moves, the next cycle starts or the loop ends
            _SIM_NOW=$(( _SIM_NOW + $1 ))
            tok_has i && _SIM_NOW=$(( _SIM_NOW + ICOST ))   # an offline cycle also paid for its failed connectivity probe
            IDX=$(( IDX + 1 ))
            if [[ $IDX -ge ${#PLAN[@]} ]]; then _running=false; else ev "CYCLE $IDX"; fi
        }
        _selffence_reset
        ev "CYCLE 0"
        _running=true; run_loop
        cat "$EV"
    )
}

# ── world 3: the standby's real attempt_takeover, one call per simulated second (the turbo cadence) ───────────────────────────────────────────────────────
b75_sb() {   # b75_sb <script> <seconds> [LOCK=<s> CD=<s> T0=<clock> ...] -> W <t> <text> / I <t> <text> (the two sites' texts at WARN / INFO) / R <t> <rc>;  LOCK = the re-take lockout armed with that many s, CD = the takeover cooldown
    local script="$1" secs="$2" cs t kv; shift 2
    cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        EV=$(mktemp); trap 'rm -f "$EV"' EXIT
        TG_ENABLED=false; DRY_RUN=true; ALERT_THROTTLE=600; T0=1700000000; LOCK=0; CD=0
        for kv in "$@"; do eval "$kv"; done
        _SIM_NOW=$T0
        mono_now() { echo "$_SIM_NOW"; }
        log_error() { :; }; alert() { :; }; alert_warn() { :; }; alert_info() { :; }; send_telegram() { return 0; }; send_webhook() { :; }; _watchdog_pet() { :; }; save_state() { :; }
        log_warn() { case "$1" in "Re-take locked out"*|"Takeover cooldown"*) printf 'W %s %s\n' $(( _SIM_NOW - T0 )) "$1" >> "$EV" ;; esac; }
        log_info() { case "$1" in "Re-take locked out"*|"Takeover cooldown"*) printf 'I %s %s\n' $(( _SIM_NOW - T0 )) "$1" >> "$EV" ;; esac; }
        SELF_FENCE_DEMOTE_TIME=0; SELF_FENCE_RETAKE_COOLDOWN=600; LAST_TAKEOVER_TIME=0; TAKEOVER_COOLDOWN=120; _last_lockout_log=0
        if [[ $LOCK -gt 0 ]]; then SELF_FENCE_DEMOTE_TIME=$T0; SELF_FENCE_RETAKE_COOLDOWN=$LOCK; fi
        if [[ $CD -gt 0 ]]; then LAST_TAKEOVER_TIME=$T0; TAKEOVER_COOLDOWN=$CD; fi
        FIRST_DELINQUENT_TIME=$T0; LAST_LIVENESS_ACTIVE_TIME=0; _last_blind_end=0; _own_bank_active_time=0; _delinq_window="1111111111"; VOTE_LIVENESS_VERIFY=false
        for ((t = 0; t <= secs; t++)); do
            _SIM_NOW=$(( T0 + t ))
            attempt_takeover >/dev/null 2>&1; printf 'R %s %s\n' "$t" "$?" >> "$EV"
        done
        cat "$EV"
    )
}

# ── the cases, as predicates over a script (the same predicate runs on the shipped daemon and, in (B7.5-23), on every mutant) ──────────────────────────────
b75_p_same() {   # (1) 20 calls of one reason whose number changes every time: 20 log lines, ONE page (the first), every call returns 0, no admin call
    local ev; ev=$(b75_calls "$1" "$(b75_spec_same)")
    b75_why="pages=$(b75_n "$ev" '^P ') at [$(b75_at "$ev" '^P ')] logs=$(b75_n "$ev" '^L ') rc0=$(b75_n "$ev" '^R [0-9]+ 0$') admin=$(b75_n "$ev" '^ADMIN')"
    [[ "$(b75_n "$ev" '^P ')" == "1" ]] || return 1
    [[ "$(b75_at "$ev" '^P ')" == "0" ]] || return 1
    [[ "$ev" == *"P 0 [DRY RUN] WOULD SWITCH TO UNSTAKED|Internet lost (1x) — no tier verification needed"* ]] || return 1
    [[ "$(b75_n "$ev" '^L ')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^R [0-9]+ 0$')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^ADMIN')" == "0" ]] || return 1
    return 0
}
b75_p_window() {   # (2) the window: a repeat exactly ALERT_THROTTLE after the last page pages (>=), one second earlier does not; the stamp is the LAST page's; the knob is honoured (30; 0 = every call)
    local e1 e2 e3
    e1=$(b75_calls "$1" "$(b75_spec 0 "$(b75_ri 1)" 599 "$(b75_ri 2)" 600 "$(b75_ri 3)" 1199 "$(b75_ri 4)" 1200 "$(b75_ri 5)")")
    e2=$(b75_calls "$1" "$(b75_spec 0 "$(b75_ri 1)" 29 "$(b75_ri 2)" 30 "$(b75_ri 3)" 59 "$(b75_ri 4)" 60 "$(b75_ri 5)")" ALERT_THROTTLE=30)
    e3=$(b75_calls "$1" "$(b75_spec 0 "$(b75_ri 1)" 0 "$(b75_ri 2)" 1 "$(b75_ri 3)")" ALERT_THROTTLE=0)
    b75_why="600: pages at [$(b75_at "$e1" '^P ')] logs $(b75_n "$e1" '^L ') / 30: pages at [$(b75_at "$e2" '^P ')] / 0: pages $(b75_n "$e3" '^P ')"
    [[ "$(b75_at "$e1" '^P ')" == "0,600,1200" ]] || return 1
    [[ "$(b75_n "$e1" '^L ')" == "5" ]] || return 1
    [[ "$(b75_at "$e2" '^P ')" == "0,30,60" ]] || return 1
    [[ "$(b75_n "$e3" '^P ')" == "3" ]] || return 1
    return 0
}
b75_p_keys() {   # (3) a different reason pages at once; a table of keys (not one stamp): two reasons that alternate are one page each per window, and again after it
    local e1 e2 a=() i
    e1=$(b75_calls "$1" "$(b75_spec 0 "$(b75_rb 100)" 1 "$(b75_rf 31)" 2 "$(b75_rb 200)" 3 "$(b75_rf 61)" 600 "$(b75_rb 300)" 601 "$(b75_rf 91)" 602 "$(b75_rb 400)")")
    for ((i = 0; i < 20; i++)); do
        a[${#a[@]}]=$i
        if (( i % 2 )); then a[${#a[@]}]="$(b75_rf $(( 30 + i )))"; else a[${#a[@]}]="$(b75_rb $(( 100 + i )))"; fi
    done
    e2=$(b75_calls "$1" "$(b75_spec "${a[@]}")")
    b75_why="A@0 B@1 A@2 B@3 A@600 B@601 A@602: pages at [$(b75_at "$e1" '^P ')] logs $(b75_n "$e1" '^L ') / 20 alternating calls: pages $(b75_n "$e2" '^P ') logs $(b75_n "$e2" '^L ')"
    [[ "$(b75_at "$e1" '^P ')" == "0,1,600,601" ]] || return 1
    [[ "$(b75_n "$e1" '^L ')" == "7" ]] || return 1
    [[ "$(b75_n "$e2" '^P ')" == "2" ]] || return 1
    [[ "$(b75_n "$e2" '^L ')" == "20" ]] || return 1
    return 0
}
b75_p_digits() {   # (4) the key is the reason without its digits: the same text with other numbers is the same reason; other words are another one; the page carries the reason as written
    local ev; ev=$(b75_calls "$1" "$(b75_spec 0 "$(b75_rb 12345)" 3 "$(b75_rb 99)" 6 "$(b75_rb 7)" 9 "$(b75_rf 31)" 12 "$(b75_rf 61)")")
    b75_why="pages at [$(b75_at "$ev" '^P ')] logs $(b75_n "$ev" '^L ')"
    [[ "$(b75_at "$ev" '^P ')" == "0,9" ]] || return 1
    [[ "$ev" == *"P 0 [DRY RUN] WOULD SWITCH TO UNSTAKED|self-fence: local getHealth behind 12345 slots (> 150) — isolated from supermajority"* ]] || return 1
    [[ "$ev" == *"P 9 [DRY RUN] WOULD SWITCH TO UNSTAKED|self-fence: local confirmed slot frozen 31s — isolated from supermajority"* ]] || return 1
    [[ "$(b75_n "$ev" '^L ')" == "5" ]] || return 1
    return 0
}
b75_p_empty() {   # (5) a reason with nothing left once its digits go has no key to throttle by: it pages every time (a page too many, never one too few)
    local ev; ev=$(b75_calls "$1" "$(b75_spec 0 "123" 1 "456" 2 "7")")
    b75_why="pages=$(b75_n "$ev" '^P ') logs=$(b75_n "$ev" '^L ')"
    [[ "$(b75_n "$ev" '^P ')" == "3" ]] || return 1
    [[ "$(b75_n "$ev" '^L ')" == "3" ]] || return 1
    return 0
}
b75_p_bound() {   # (6) the table is bounded: 40 different reasons page once each, nothing is held back, and the table never grows past 16 keys
    local a=() i s="" ev n
    for ((i = 1; i <= 40; i++)); do s="${s}x"; a[${#a[@]}]=$i; a[${#a[@]}]="reason $s"; done
    ev=$(b75_calls "$1" "$(b75_spec "${a[@]}")")
    n=$(printf '%s\n' "$ev" | sed -n 's/^N //p')
    b75_why="pages=$(b75_n "$ev" '^P ') rc0=$(b75_n "$ev" '^R [0-9]+ 0$') table=${n:-?}"
    [[ "$(b75_n "$ev" '^P ')" == "40" ]] || return 1
    [[ "$(b75_n "$ev" '^R [0-9]+ 0$')" == "40" ]] || return 1
    [[ "${n:-0}" -ge 1 && "${n:-0}" -le 16 ]] || return 1
    return 0
}
b75_p_live() {   # (7) DRY_RUN=false: the real demote acts on EVERY call (remove-all + set-identity each time); nothing of the dry branch runs
    local ev; ev=$(b75_calls "$1" "$(b75_spec 0 "$(b75_ri 3)" 1 "$(b75_ri 4)" 2 "$(b75_ri 5)" 3 "$(b75_ri 6)" 4 "$(b75_ri 7)")" DRY_RUN=false)
    b75_why="remove-all=$(b75_n "$ev" '^ADMIN .*remove-all') set-identity=$(b75_n "$ev" '^ADMIN .*set-identity') dry-logs=$(b75_n "$ev" '^L ') dry-pages=$(b75_n "$ev" '^P [0-9]+ \[DRY RUN\]')"
    [[ "$(b75_n "$ev" '^ADMIN .*authorized-voter remove-all')" == "5" ]] || return 1
    [[ "$(b75_n "$ev" '^ADMIN .*set-identity')" == "5" ]] || return 1
    [[ "$(b75_n "$ev" '^L ')" == "0" ]] || return 1
    [[ "$(b75_n "$ev" '^P [0-9]+ \[DRY RUN\]')" == "0" ]] || return 1
    return 0
}
b75_p_undef() {   # (8) fail toward paging: the predicate gone (unset -f), the dry demote pages on every call and still logs and returns 0
    local ev; ev=$(b75_calls "$1" "$(b75_spec_same)" UNDEF=1)
    b75_why="pages=$(b75_n "$ev" '^P ') logs=$(b75_n "$ev" '^L ') rc0=$(b75_n "$ev" '^R [0-9]+ 0$')"
    [[ "$(b75_n "$ev" '^P ')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^L ')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^R [0-9]+ 0$')" == "20" ]] || return 1
    return 0
}
b75_p_off20() {   # (9) the offline node through the real loop: 20 cycles, check_internet fails each one -> 20 log lines, ONE page (the first reason), no admin call, the plan ran to its end
    local ev; ev=$(b75_loop "$1" "$(b75_plan 20 Si)")
    b75_why="cycles=$(b75_n "$ev" '^CYCLE ') dry-logs=$(b75_n "$ev" '^DRYLOG ') pages=$(b75_n "$ev" '^PAGE ') admin=$(b75_n "$ev" '^ADMIN')"
    [[ "$(b75_n "$ev" '^CYCLE ')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^DRYLOG ')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE ')" == "1" ]] || return 1
    [[ "$ev" == *"PAGE 0 [DRY RUN] WOULD SWITCH TO UNSTAKED"* ]] || return 1
    [[ "$ev" == *"TXT 0 Internet lost (1x) — no tier verification needed"* ]] || return 1
    [[ "$(b75_n "$ev" '^ADMIN')" == "0" ]] || return 1
    return 0
}
b75_p_offwin() {   # (10) the same offline node over 150 s with ALERT_THROTTLE=60 (a cycle = 3 s sleep + 2 s probe): the page repeats once per window - at 0, 60, 120 s - and every cycle is logged
    local ev; ev=$(b75_loop "$1" "$(b75_plan 30 Si)" ALERT_THROTTLE=60)
    b75_why="dry-logs=$(b75_n "$ev" '^DRYLOG ') pages at [$(b75_at "$ev" '^PAGE ')]"
    [[ "$(b75_n "$ev" '^DRYLOG ')" == "30" ]] || return 1
    [[ "$(b75_at "$ev" '^PAGE ')" == "0,60,120" ]] || return 1
    return 0
}
b75_p_behind() {   # (11) self-fence (2), getHealth behind: fires on EVERY cycle (the tracker is re-armed by the dry success), the number in the reason changes every cycle -> 20 log lines, ONE page
    local ev; ev=$(b75_loop "$1" "$(b75_plan 20 S)" SF=behind)
    b75_why="cycles=$(b75_n "$ev" '^CYCLE ') dry-logs=$(b75_n "$ev" '^DRYLOG ') pages=$(b75_n "$ev" '^PAGE ') admin=$(b75_n "$ev" '^ADMIN')"
    [[ "$(b75_n "$ev" '^CYCLE ')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^DRYLOG ')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE ')" == "1" ]] || return 1
    [[ "$ev" == *"PAGE 0 [DRY RUN] WOULD SWITCH TO UNSTAKED"* ]] || return 1
    [[ "$ev" == *"TXT 0 self-fence: local getHealth behind 20000 slots (> 150)"* ]] || return 1
    [[ "$(b75_n "$ev" '^ADMIN')" == "0" ]] || return 1
    return 0
}
b75_p_frozen() {   # (12) self-fence (1b), frozen slot: fires every ~33 s (30 s of freeze, then the tracker starts over) -> 4 fires in 45 cycles, ONE page
    local ev f; ev=$(b75_loop "$1" "$(b75_plan 45 S)" SF=frozen); f=$(b75_n "$ev" '^DRYLOG ')
    b75_why="fires=$f pages=$(b75_n "$ev" '^PAGE ') admin=$(b75_n "$ev" '^ADMIN')"
    [[ "$f" -ge 3 ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE ')" == "1" ]] || return 1
    [[ "$ev" == *"TXT "*" self-fence: local confirmed slot frozen 30s"* ]] || return 1
    [[ "$(b75_n "$ev" '^ADMIN')" == "0" ]] || return 1
    return 0
}
b75_p_silent() {   # (13) self-fence (1a), the LOCAL RPC goes silent after answering (three times in 45 cycles): ONE dry page; the self-fence's own page 'PRIMARY SELF-FENCE - LOCAL RPC SILENT' is sent every time, as ever
    local ev f; ev=$(b75_loop "$1" "$(b75_plan 45 S)" SF=flap); f=$(b75_n "$ev" '^DRYLOG ')
    b75_why="fires=$f dry-pages=$(b75_n "$ev" '^PAGE [0-9]+ \[DRY RUN\]') own-pages=$(b75_n "$ev" '^PAGE [0-9]+ PRIMARY SELF-FENCE — LOCAL RPC SILENT') admin=$(b75_n "$ev" '^ADMIN')"
    [[ "$f" -ge 3 ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE [0-9]+ \[DRY RUN\]')" == "1" ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE [0-9]+ PRIMARY SELF-FENCE — LOCAL RPC SILENT')" == "$f" ]] || return 1
    [[ "$(b75_n "$ev" '^ADMIN')" == "0" ]] || return 1
    return 0
}
b75_p_vlag() {   # (14) self-fence (3), the own vote lags (healthy 4 cycles, then 16 lagging, twice in 45 cycles): ONE dry page; the own page 'VOTES NOT LANDING' is sent every time
    local ev f; ev=$(b75_loop "$1" "$(b75_plan 45 S)" SF=vlag VOTE_PUBKEY=VotePubkey111); f=$(b75_n "$ev" '^DRYLOG ')
    b75_why="fires=$f dry-pages=$(b75_n "$ev" '^PAGE [0-9]+ \[DRY RUN\]') own-pages=$(b75_n "$ev" '^PAGE [0-9]+ PRIMARY SELF-FENCE — VOTES NOT LANDING') admin=$(b75_n "$ev" '^ADMIN')"
    [[ "$f" -ge 2 ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE [0-9]+ \[DRY RUN\]')" == "1" ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE [0-9]+ PRIMARY SELF-FENCE — VOTES NOT LANDING')" == "$f" ]] || return 1
    [[ "$(b75_n "$ev" '^ADMIN')" == "0" ]] || return 1
    return 0
}
b75_p_mixed() {   # (15) a partition that is frozen AND behind: the two signals fire in turn (frozen, behind, frozen, behind ...) -> 6 fires in 45 cycles, ONE page for each reason (two), not one per change of reason
    local ev f; ev=$(b75_loop "$1" "$(b75_plan 45 S)" SF=mixed); f=$(b75_n "$ev" '^DRYLOG ')
    b75_why="fires=$f pages=$(b75_n "$ev" '^PAGE ') frozen-pages=$(b75_n "$ev" '^TXT [0-9]+ self-fence: local confirmed slot frozen') behind-pages=$(b75_n "$ev" '^TXT [0-9]+ self-fence: local getHealth behind')"
    [[ "$f" -ge 4 ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE ')" == "2" ]] || return 1
    [[ "$(b75_n "$ev" '^TXT [0-9]+ self-fence: local confirmed slot frozen')" == "1" ]] || return 1
    [[ "$(b75_n "$ev" '^TXT [0-9]+ self-fence: local getHealth behind')" == "1" ]] || return 1
    return 0
}
b75_p_liveloop() {   # (16) the live node through the real loop (DRY_RUN=false, offline, 20 cycles): the real demote acts on every cycle - its admin calls are never throttled - and no dry line or page exists
    local ev; ev=$(b75_loop "$1" "$(b75_plan 20 Si)" DRY_RUN=false)
    b75_why="remove-all=$(b75_n "$ev" '^ADMIN .*authorized-voter remove-all') set-identity=$(b75_n "$ev" '^ADMIN .*set-identity') dry-logs=$(b75_n "$ev" '^DRYLOG ') dry-pages=$(b75_n "$ev" '^PAGE [0-9]+ \[DRY RUN\]')"
    [[ "$(b75_n "$ev" '^ADMIN .*authorized-voter remove-all')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^ADMIN .*set-identity')" == "20" ]] || return 1
    [[ "$(b75_n "$ev" '^DRYLOG ')" == "0" ]] || return 1
    [[ "$(b75_n "$ev" '^PAGE [0-9]+ \[DRY RUN\]')" == "0" ]] || return 1
    return 0
}
b75_p_sb_lock() {   # (17) the standby's re-take lockout over 131 turbo cycles (t = 0..130): WARN at 0, 60, 120; the other 128 cycles INFO with the same text (the remaining seconds count down); the take stays refused (rc 1)
    local ev; ev=$(b75_sb "$1" 130 LOCK=600)
    b75_why="warn at [$(b75_at "$ev" '^W ')] info=$(b75_n "$ev" '^I ') refused=$(b75_n "$ev" '^R [0-9]+ 1$')"
    [[ "$(b75_at "$ev" '^W ')" == "0,60,120" ]] || return 1
    [[ "$(b75_n "$ev" '^I ')" == "128" ]] || return 1
    [[ "$(b75_n "$ev" '^R [0-9]+ 1$')" == "131" ]] || return 1
    [[ "$ev" == *"W 60 Re-take locked out after self-fence: 540s remaining — we fenced OURSELVES"* ]] || return 1
    [[ "$ev" == *"I 5 Re-take locked out after self-fence: 595s remaining — we fenced OURSELVES"* ]] || return 1
    return 0
}
b75_p_sb_cd() {   # (18) the standby's takeover cooldown over 131 turbo cycles: WARN at 0, 60, 120; the other 128 cycles INFO with the same text; the take stays refused (rc 1)
    local ev; ev=$(b75_sb "$1" 130 CD=300)
    b75_why="warn at [$(b75_at "$ev" '^W ')] info=$(b75_n "$ev" '^I ') refused=$(b75_n "$ev" '^R [0-9]+ 1$')"
    [[ "$(b75_at "$ev" '^W ')" == "0,60,120" ]] || return 1
    [[ "$(b75_n "$ev" '^I ')" == "128" ]] || return 1
    [[ "$(b75_n "$ev" '^R [0-9]+ 1$')" == "131" ]] || return 1
    [[ "$ev" == *"W 60 Takeover cooldown: 240s remaining since last attempt"* ]] || return 1
    [[ "$ev" == *"I 5 Takeover cooldown: 295s remaining since last attempt"* ]] || return 1
    return 0
}
b75_p_sb_20() {   # (19) 20 turbo cycles: ONE WARN (the first) and 19 INFO for each of the two sites
    local e1 e2
    e1=$(b75_sb "$1" 19 LOCK=600); e2=$(b75_sb "$1" 19 CD=300)
    b75_why="lockout: warn [$(b75_at "$e1" '^W ')] info $(b75_n "$e1" '^I ') / cooldown: warn [$(b75_at "$e2" '^W ')] info $(b75_n "$e2" '^I ')"
    [[ "$(b75_at "$e1" '^W ')" == "0" && "$(b75_n "$e1" '^I ')" == "19" ]] || return 1
    [[ "$(b75_at "$e2" '^W ')" == "0" && "$(b75_n "$e2" '^I ')" == "19" ]] || return 1
    return 0
}
b75_p_sb_young() {   # (20) the FIRST call of a site is a WARN at once, even on a host whose clock reads 5 s (a stamp of 0 means 'never', not 'a minute ago')
    local e1 e2
    e1=$(b75_sb "$1" 2 LOCK=600 T0=5); e2=$(b75_sb "$1" 2 CD=300 T0=5)
    b75_why="lockout: warn [$(b75_at "$e1" '^W ')] info $(b75_n "$e1" '^I ') / cooldown: warn [$(b75_at "$e2" '^W ')] info $(b75_n "$e2" '^I ')"
    [[ "$(b75_at "$e1" '^W ')" == "0" && "$(b75_n "$e1" '^I ')" == "2" ]] || return 1
    [[ "$(b75_at "$e2" '^W ')" == "0" && "$(b75_n "$e2" '^I ')" == "2" ]] || return 1
    return 0
}
b75_p_sb_sep() {   # (21) one stamp per site: the lockout (t = 0..99) WARNs at 0 and 60, the cooldown that follows (t = 100..169) WARNs at its own first call (100) and 60 s later (160)
    local ev lk cd
    ev=$(b75_sb "$1" 170 LOCK=100 CD=300)
    lk=$(printf '%s\n' "$ev" | grep 'Re-take locked out'); cd=$(printf '%s\n' "$ev" | grep 'Takeover cooldown')
    b75_why="lockout warn at [$(b75_at "$lk" '^W ')] cooldown warn at [$(b75_at "$cd" '^W ')]"
    [[ "$(b75_at "$lk" '^W ')" == "0,60" ]] || return 1
    [[ "$(b75_at "$cd" '^W ')" == "100,160" ]] || return 1
    return 0
}
b75_p_struct() {   # (22) structure: the throttle helper reads the monotonic clock only (no wall clock, no patsub), derives the key with tr; switch_to_unstaked logs, asks it in its dry branch only, then pages; ONE site pages the dry demote
    local f="$1" fn sw sf n_site l_log l_ask l_alert l_live
    fn=$(sed -n '/^_dry_page_throttled() {/,/^}/p' "$f" | grep -v '^[[:space:]]*#')
    sw=$(sed -n '/^switch_to_unstaked() {/,/^}/p' "$f" | grep -v '^[[:space:]]*#')
    sf=$(sed -n '/^check_self_fence_isolation() {/,/^}/p' "$f" | grep -v '^[[:space:]]*#')
    n_site=$(grep -v '^[[:space:]]*#' "$f" | grep -c '"\[DRY RUN\] WOULD SWITCH TO UNSTAKED"')
    l_log=$(printf '%s\n' "$sw" | grep -n 'log_warn "\[DRY RUN\] Would switch to UNSTAKED' | head -1 | cut -d: -f1)
    l_ask=$(printf '%s\n' "$sw" | grep -n 'if ! _dry_page_throttled "\$reason"; then' | head -1 | cut -d: -f1)
    l_alert=$(printf '%s\n' "$sw" | grep -n 'alert "\$reason" "\$UNSTAKED_PUBKEY" "\[DRY RUN\] WOULD SWITCH TO UNSTAKED"' | head -1 | cut -d: -f1)
    l_live=$(printf '%s\n' "$sw" | grep -n 'SWITCHING TO UNSTAKED' | head -1 | cut -d: -f1)
    b75_why="helper-lines=$(printf '%s\n' "$fn" | grep -c .) mono=$(printf '%s\n' "$fn" | grep -c 'mono_now') wall=$(printf '%s\n' "$fn" | grep -c 'date +%s') patsub=$(printf '%s\n' "$fn" | grep -c -E '\$\{[A-Za-z_0-9]+//') tr=$(printf '%s\n' "$fn" | grep -c -F "tr -d '0-9'") asks=$(printf '%s\n' "$sw" | grep -c '_dry_page_throttled') page-sites=$n_site self-fence-dry=$(printf '%s\n' "$sf" | grep -c '\[DRY RUN\]') order=[log:${l_log:-?} ask:${l_ask:-?} page:${l_alert:-?} live:${l_live:-?}]"
    [[ -n "$fn" && -n "$sw" ]] || return 1
    [[ "$(printf '%s\n' "$fn" | grep -c 'mono_now')" == "1" ]] || return 1
    [[ "$(printf '%s\n' "$fn" | grep -c 'date +%s')" == "0" ]] || return 1
    [[ "$(printf '%s\n' "$fn" | grep -c -E '\$\{[A-Za-z_0-9]+//')" == "0" ]] || return 1
    [[ "$(printf '%s\n' "$fn" | grep -c -F "tr -d '0-9'")" == "1" ]] || return 1
    [[ "$(printf '%s\n' "$sw" | grep -c '_dry_page_throttled')" == "1" ]] || return 1
    [[ -n "$l_log" && -n "$l_ask" && -n "$l_alert" && -n "$l_live" ]] || return 1
    [[ $l_log -lt $l_ask && $l_ask -lt $l_alert && $l_alert -lt $l_live ]] || return 1
    [[ "$n_site" == "1" ]] || return 1
    [[ "$(printf '%s\n' "$sf" | grep -c '\[DRY RUN\]')" == "0" ]] || return 1
    return 0
}

# ── (B7.5-1..8) the throttle itself: the real switch_to_unstaked over a simulated clock ──────────────────────────────────────────────────────────────────
echo ""; echo "─── (B7.5-1..8) the dry demote: every call is logged, one page per ALERT_THROTTLE per reason (digit-stripped key, a table of keys), the live path untouched ───"
if b75_p_same "$PRIMARY"; then ok "(B7.5-1) 20 DRY_RUN demotes of one reason whose number changes every call ('Internet lost (1x)' ... '(20x)'): 20 '[DRY RUN] Would switch' log lines, ONE '[DRY RUN] WOULD SWITCH TO UNSTAKED' page (the first, with the first reason), every call returns 0 (DRY_RUN's logged success), no admin call"; else bad "(B7.5-1) same reason, changing number: $b75_why"; fi
if b75_p_window "$PRIMARY"; then ok "(B7.5-2) the window is >=: calls at 0, 599, 600, 1199, 1200 s page at 0, 600, 1200 (the stamp is the LAST page's, not the first); ALERT_THROTTLE=30 pages at 0, 30, 60; ALERT_THROTTLE=0 pages every call"; else bad "(B7.5-2) window: $b75_why"; fi
if b75_p_keys "$PRIMARY"; then ok "(B7.5-3) a different reason pages at once and each reason has its own window: A@0 B@1 A@2 B@3 A@600 B@601 A@602 pages at 0, 1, 600, 601; twenty calls alternating between two reasons are two pages (a single stamp would page on every change)"; else bad "(B7.5-3) per-reason windows: $b75_why"; fi
if b75_p_digits "$PRIMARY"; then ok "(B7.5-4) the key is the reason with its digits stripped: 'behind 12345 slots', '99', '7' are one reason (one page, at 0, carrying '12345'); 'frozen 31s' and '61s' another (one page, at 9); 5 log lines"; else bad "(B7.5-4) key: $b75_why"; fi
if b75_p_empty "$PRIMARY"; then ok "(B7.5-5) a reason that is nothing but digits has no key: it pages on every call (3 calls, 3 pages) - a page too many, never one too few"; else bad "(B7.5-5) empty key: $b75_why"; fi
if b75_p_bound "$PRIMARY"; then ok "(B7.5-6) the table is bounded: 40 different reasons page once each (40 pages, every call 0) and the table holds at most 16 keys"; else bad "(B7.5-6) bound: $b75_why"; fi
if b75_p_live "$PRIMARY"; then ok "(B7.5-7) DRY_RUN=false: five calls of one reason within a second make ten admin calls (authorized-voter remove-all + set-identity each time) - the throttle is the dry branch's alone; no dry log line, no dry page"; else bad "(B7.5-7) live path: $b75_why"; fi
if b75_p_undef "$PRIMARY"; then ok "(B7.5-8) fail toward paging: with the predicate unset (unset -f _dry_page_throttled) the dry demote pages on every call, still logs and still returns 0"; else bad "(B7.5-8) undefined predicate: $b75_why"; fi

# ── (B7.5-9..16) through the real main loop, the real self-fence and the real switch_to_unstaked ───────────────────────────────────────────────────────────
echo ""; echo "─── (B7.5-9..16) the real loop: offline, getHealth behind, frozen slot, silent RPC, own-vote lag, a partition, and the live node ───"
if b75_p_off20 "$PRIMARY"; then ok "(B7.5-9) 20 offline cycles in DRY_RUN (check_internet fails each one): 20 '[DRY RUN] Would switch to UNSTAKED' log lines, ONE page ('Internet lost (1x)'), zero admin calls"; else bad "(B7.5-9) offline x20: $b75_why"; fi
if b75_p_offwin "$PRIMARY"; then ok "(B7.5-10) the offline node over 150 s with ALERT_THROTTLE=60: 30 log lines, pages at 0, 60 and 120 s - once per window"; else bad "(B7.5-10) offline over windows: $b75_why"; fi
if b75_p_behind "$PRIMARY"; then ok "(B7.5-11) the self-fence's getHealth path (2) fires on every cycle (the number of slots behind changes each time): 20 log lines, ONE page, no admin call"; else bad "(B7.5-11) self-fence behind: $b75_why"; fi
if b75_p_frozen "$PRIMARY"; then ok "(B7.5-12) the frozen-slot path (1b) fires every ~33 s: 3+ fires in 45 cycles, ONE page, no admin call"; else bad "(B7.5-12) self-fence frozen: $b75_why"; fi
if b75_p_silent "$PRIMARY"; then ok "(B7.5-13) the silent-RPC path (1a): ONE dry page over 3+ fires; the self-fence's own 'PRIMARY SELF-FENCE — LOCAL RPC SILENT' page is still sent at every fire (not a dry page, not touched)"; else bad "(B7.5-13) self-fence silent: $b75_why"; fi
if b75_p_vlag "$PRIMARY"; then ok "(B7.5-14) the own-vote-lag path (3): ONE dry page over 2+ fires; the self-fence's own 'PRIMARY SELF-FENCE — VOTES NOT LANDING' page is still sent at every fire"; else bad "(B7.5-14) self-fence vote lag: $b75_why"; fi
if b75_p_mixed "$PRIMARY"; then ok "(B7.5-15) a partition that is both frozen and behind (the two paths fire in turn): 4+ fires, TWO pages in all - one 'frozen', one 'behind' - not one per alternation"; else bad "(B7.5-15) frozen+behind: $b75_why"; fi
if b75_p_liveloop "$PRIMARY"; then ok "(B7.5-16) the live node (DRY_RUN=false) offline for 20 cycles: 20 authorized-voter remove-all and 20 set-identity calls - the real demote is never throttled - and no dry line or page"; else bad "(B7.5-16) live loop: $b75_why"; fi

# ── (B7.5-17..21) the standby: the two per-cycle WARN lines ──────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (B7.5-17..21) the standby's takeover cooldown and re-take lockout: WARN at most once per 60 s per site, INFO in between ───"
if b75_p_sb_lock "$STANDBY"; then ok "(B7.5-17) the re-take lockout over 131 turbo cycles: WARN at t = 0, 60, 120; 128 INFO lines with the same text (595s remaining, 594s, ...); attempt_takeover keeps returning 1"; else bad "(B7.5-17) lockout: $b75_why"; fi
if b75_p_sb_cd "$STANDBY"; then ok "(B7.5-18) the takeover cooldown over 131 turbo cycles: WARN at t = 0, 60, 120; 128 INFO lines with the same text (295s remaining since last attempt, ...); attempt_takeover keeps returning 1"; else bad "(B7.5-18) cooldown: $b75_why"; fi
if b75_p_sb_20 "$STANDBY"; then ok "(B7.5-19) 20 turbo cycles: ONE WARN and 19 INFO for each of the two sites"; else bad "(B7.5-19) 20 cycles: $b75_why"; fi
if b75_p_sb_young "$STANDBY"; then ok "(B7.5-20) the first call of each site is a WARN at once on a host whose clock reads 5 s (a stamp of 0 means 'never logged')"; else bad "(B7.5-20) young clock: $b75_why"; fi
if b75_p_sb_sep "$STANDBY"; then ok "(B7.5-21) one stamp per site: the lockout (t = 0..99) WARNs at 0 and 60, the cooldown that follows WARNs at its own first call (100) and 60 s later (160) - the lockout's last WARN does not use up the cooldown's"; else bad "(B7.5-21) separate stamps: $b75_why"; fi

# ── (B7.5-22) structure and docs ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (B7.5-22) structure: monotonic clock only, one dry-demote page site, the docs entry ───"
if b75_p_struct "$PRIMARY"; then ok "(B7.5-22a) _dry_page_throttled reads mono_now once, no wall-clock read, no patsub, the key from tr -d '0-9'; switch_to_unstaked logs, THEN asks it (once, in the dry branch), THEN pages, and the live path is below; the dry demote page has one site in the file and the self-fence function sends no dry page of its own"; else bad "(B7.5-22a) structure: $b75_why"; fi
b75_p_docs() { local row; row=$(grep -F '`[DRY RUN] WOULD SWITCH TO UNSTAKED`' "$HARNESS_DIR/docs/NOTIFICATIONS.md" | head -1); [[ "$row" == *'`ALERT_THROTTLE`'* && "$row" == *"per reason"* ]]; }
if b75_p_docs; then ok "(B7.5-22b) docs/NOTIFICATIONS.md: the '[DRY RUN] WOULD SWITCH TO UNSTAKED' entry says the page is sent once per ALERT_THROTTLE per reason"; else bad "(B7.5-22b) docs/NOTIFICATIONS.md does not say the dry page is throttled per reason"; fi

# ── (B7.5-23) controls: every mutant of the rule turns a case red ────────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (B7.5-23) CONTROLS (mutate()): each mutant must turn its case red ───"
b75_ctl_ok=1; b75_ctl_rows=""; b75_cache=""
b75_ctl() {   # b75_ctl <label> <script> <sed expr> <predicate> - the predicate holds on the shipped script and FAILS on the mutant (a mutant must still parse)
    local label="$1" script="$2" expr="$3" pred="$4" m="$WORK/b75-mut-$1.sh" key rv mv
    key="$pred@${script##*/}"
    if ! mutate "$script" "$expr" "$m"; then b75_ctl_ok=0; b75_ctl_rows="$b75_ctl_rows $label:NOT-APPLIED"; return; fi
    if ! "${BASH:-bash}" -n "$m" 2>/dev/null; then b75_ctl_ok=0; b75_ctl_rows="$b75_ctl_rows $label:DOES-NOT-PARSE"; return; fi
    case " $b75_cache " in
        *" $key=y "*) rv=y ;;
        *" $key=n "*) rv=n ;;
        *) if "$pred" "$script"; then rv=y; else rv=n; fi; b75_cache="$b75_cache $key=$rv" ;;
    esac
    if "$pred" "$m"; then mv=y; else mv=n; fi
    if [[ "$rv" == "y" && "$mv" == "n" ]]; then b75_ctl_rows="$b75_ctl_rows $label:red"; else b75_ctl_ok=0; b75_ctl_rows="$b75_ctl_rows $label:[shipped=$rv,mutant=$mv]"; fi
}
# the dry demote - each mutant of the rule, against the exact-semantics world (and, for the first two, against the real loop as well)
b75_ctl throttle-removed          "$PRIMARY" 's/^        if ! _dry_page_throttled "\$reason"; then$/        if true; then/' b75_p_same
b75_ctl throttle-removed-loop     "$PRIMARY" 's/^        if ! _dry_page_throttled "\$reason"; then$/        if true; then/' b75_p_off20
b75_ctl throttle-removed-behind   "$PRIMARY" 's/^        if ! _dry_page_throttled "\$reason"; then$/        if true; then/' b75_p_behind
b75_ctl polarity-flipped          "$PRIMARY" 's/^        if ! _dry_page_throttled "\$reason"; then$/        if _dry_page_throttled "$reason"; then/' b75_p_same
b75_ctl polarity-flipped-undef    "$PRIMARY" 's/^        if ! _dry_page_throttled "\$reason"; then$/        if _dry_page_throttled "$reason"; then/' b75_p_undef
b75_ctl key-not-stripped          "$PRIMARY" "s/tr -d '0-9'/cat/" b75_p_same
b75_ctl key-not-stripped-loop     "$PRIMARY" "s/tr -d '0-9'/cat/" b75_p_off20
b75_ctl key-ignored               "$PRIMARY" 's/^        if \[\[ "\${_dry_page_keys\[\$_i\]}" == "\$_key" \]\]; then$/        if [[ -n "${_dry_page_keys[$_i]}" ]]; then/' b75_p_keys
b75_ctl key-ignored-mixed         "$PRIMARY" 's/^        if \[\[ "\${_dry_page_keys\[\$_i\]}" == "\$_key" \]\]; then$/        if [[ -n "${_dry_page_keys[$_i]}" ]]; then/' b75_p_mixed
b75_ctl window-gt-not-ge          "$PRIMARY" 's/\(_dry_page_stamps\[\$_i\]} )) \)-ge /\1-gt /' b75_p_window
b75_ctl stamp-not-refreshed       "$PRIMARY" '/^            _dry_page_stamps\[\$_i\]=\$_now$/d' b75_p_window
b75_ctl empty-key-guard-removed   "$PRIMARY" '/^    \[\[ -n "\$_key" \]\] || return 1$/d' b75_p_empty
b75_ctl table-unbounded           "$PRIMARY" '/^    \[\[ \${#_dry_page_keys\[@\]} -lt 16 \]\] || { _dry_page_keys=(); _dry_page_stamps=(); }$/d' b75_p_bound
b75_ctl throttled-call-returns-1  "$PRIMARY" 's/^        if ! _dry_page_throttled "\$reason"; then$/        _dry_page_throttled "$reason" \&\& return 1; if true; then/' b75_p_same
b75_ctl throttle-on-live-path     "$PRIMARY" 's/^    \[\[ ! -s "\$UNSTAKED_KEYPAIR" \]\] && {$/    _dry_page_throttled "$reason" \&\& return 0; [[ ! -s "$UNSTAKED_KEYPAIR" ]] \&\& {/' b75_p_live
b75_ctl throttle-on-live-path-loop "$PRIMARY" 's/^    \[\[ ! -s "\$UNSTAKED_KEYPAIR" \]\] && {$/    _dry_page_throttled "$reason" \&\& return 0; [[ ! -s "$UNSTAKED_KEYPAIR" ]] \&\& {/' b75_p_liveloop
b75_ctl log-line-throttled-too    "$PRIMARY" 's/^        log_warn "\[DRY RUN\] Would switch to UNSTAKED.*$/        :/; s/^            alert "\$reason" "\$UNSTAKED_PUBKEY" "\[DRY RUN\] WOULD SWITCH TO UNSTAKED"$/            log_warn "[DRY RUN] Would switch to UNSTAKED — $reason"; alert "$reason" "$UNSTAKED_PUBKEY" "[DRY RUN] WOULD SWITCH TO UNSTAKED"/' b75_p_same
b75_ctl log-line-throttled-loop   "$PRIMARY" 's/^        log_warn "\[DRY RUN\] Would switch to UNSTAKED.*$/        :/; s/^            alert "\$reason" "\$UNSTAKED_PUBKEY" "\[DRY RUN\] WOULD SWITCH TO UNSTAKED"$/            log_warn "[DRY RUN] Would switch to UNSTAKED — $reason"; alert "$reason" "$UNSTAKED_PUBKEY" "[DRY RUN] WOULD SWITCH TO UNSTAKED"/' b75_p_off20
# the structure (22a): a wall-clock read in the helper, a second site that pages the dry demote on its own
b75_ctl helper-reads-wall-clock   "$PRIMARY" '/^_dry_page_throttled() {/,/^}/ s/^    _now=\$(mono_now)$/    _now=$(date +%s)/' b75_p_struct
b75_ctl second-dry-page-site      "$PRIMARY" 's/^_gap_demote() {$/_gap_demote() { alert "x" "y" "[DRY RUN] WOULD SWITCH TO UNSTAKED";/' b75_p_struct
# the standby's two sites
b75_ctl sb-cooldown-60-to-0       "$STANDBY" 's/\$(( now - _last_cooldown_log )) -ge 60/$(( now - _last_cooldown_log )) -ge 0/' b75_p_sb_cd
b75_ctl sb-lockout-60-to-0        "$STANDBY" 's/\$(( now - _last_lockout_log )) -ge 60/$(( now - _last_lockout_log )) -ge 0/' b75_p_sb_lock
b75_ctl sb-cooldown-info-dropped  "$STANDBY" '/_gate_msg="Takeover cooldown/,/^        fi$/ s/^            log_info "\$_gate_msg"$/            :/' b75_p_sb_cd
b75_ctl sb-lockout-info-dropped   "$STANDBY" '/_gate_msg="Re-take locked out/,/^        fi$/ s/^            log_info "\$_gate_msg"$/            :/' b75_p_sb_lock
b75_ctl sb-cooldown-stays-warn    "$STANDBY" '/_gate_msg="Takeover cooldown/,/^        fi$/ s/^            log_info "\$_gate_msg"$/            log_warn "$_gate_msg"/' b75_p_sb_cd
b75_ctl sb-lockout-stays-warn     "$STANDBY" '/_gate_msg="Re-take locked out/,/^        fi$/ s/^            log_info "\$_gate_msg"$/            log_warn "$_gate_msg"/' b75_p_sb_lock
b75_ctl sb-cooldown-stamp-unset   "$STANDBY" '/^            _last_cooldown_log=\$now$/d' b75_p_sb_cd
b75_ctl sb-cooldown-shares-stamp  "$STANDBY" 's/_last_cooldown_log/_last_lockout_log/g' b75_p_sb_sep
b75_ctl sb-cooldown-no-sentinel   "$STANDBY" 's/\[\[ \${_last_cooldown_log:-0} -eq 0 || /[[ /' b75_p_sb_young
b75_ctl sb-lockout-no-sentinel    "$STANDBY" 's/\[\[ \${_last_lockout_log:-0} -eq 0 || /[[ /' b75_p_sb_young
[[ $b75_ctl_ok -eq 1 ]] && ok "(B7.5-23) every mutant of the rule turns its case red:$b75_ctl_rows" || bad "(B7.5-23) a control is not red (NOT-APPLIED = its sed matched nothing; DOES-NOT-PARSE = the mutant is not bash):$b75_ctl_rows"
# ══ B7.5 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

# ══ B7.6 BEGIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# ── (B7.6) one version string, the one the operator reads ───────────────────────────────────────────────────────────────
echo ""; echo "─── (B7.6) FO_VERSION: the start banner, the start page and --version say the constant; sourcing the script never answers --version ───"
# The labels said v0.6.9 / v0.6.10 on a v0.7 daemon: an operator reading the start page could not tell which build ran. One constant per daemon (and per deploy script); the facts job pins the four equal, equal to the CHANGELOG head,
# and the templates' line 2, the manual's title and the notification entries carrying it. This section pins the daemons' own use of the constant.
b76_ver() { sed -n 's/^FO_VERSION="\([^"]*\)".*$/\1/p' "$1" | head -1; }
b76_run() {   # b76_run <script> <args...> -> "<stdout>|rc=<n>|err=<bytes>|files=<n>": the script EXECUTED (not sourced) in an empty directory with an empty environment
    local script="$1" d o rc e; shift; d=$(mktemp -d "$WORK/b76.XXXXXX")
    o=$( cd "$d" && env -i PATH="$PATH" HOME="$d" "$BASH" "$script" "$@" 2> "$d/.err" ); rc=$?
    e=$(wc -c < "$d/.err" | tr -d ' ')
    printf '%s|rc=%s|err=%s|files=%s' "$o" "$rc" "$e" "$(find "$d" -mindepth 1 ! -name .err | wc -l | tr -d ' ')"
}
p_b76_version() {   # --version prints "<script name without .sh> <FO_VERSION>" and nothing else, rc 0, no stderr, creates no file; the constant looks like a version
    local script="$1" v name; v=$(b76_ver "$script"); name=$(basename "$script" .sh)
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ && "$(b76_run "$script" --version)" == "$name $v|rc=0|err=0|files=0" ]]
}
p_b76_sourced() {   # SOURCED with --version as the caller's first argument (a test, an operator's `source`), the script does not answer and does not exit
    local script="$1" src o; src=$(cut_src "$script")
    o=$( "$BASH" -c 'source "$1" --version 2>/dev/null; echo SURVIVED' bash "$src" 2>/dev/null )
    [[ "$o" == "SURVIVED" ]]
}
p_b76_text() {   # the banner and the two start pages carry ${FO_VERSION}, exactly once each; the daemon names no literal version in them
    local script="$1" R; R=$(basename "$script" | cut -d- -f2 | tr 'a-z' 'A-Z')
    [[ "$(grep -c -F "echo \" Solana $R Failover v\${FO_VERSION} (3-TIER RPC)\"" "$script")" == "1" \
       && "$(grep -c -F "alert_info \"🚀 $R v\${FO_VERSION} started [DRY_RUN]" "$script")" == "1" && "$(grep -c -F "alert_info \"🚀 $R v\${FO_VERSION} started [LIVE]" "$script")" == "1" \
       && "$(grep -v '^[[:space:]]*#' "$script" | grep -c -E "(echo|alert_info).*(Failover|$R) v0\.[0-9]+\.[0-9]+")" == "0" \
       && "$(grep -c -E '^FO_VERSION="[^"]+"' "$script")" == "1" ]]
}
b76_all=1; b76_rows=""
for b76_s in "$PRIMARY" "$STANDBY"; do
    b76_n=$(basename "$b76_s" | cut -d- -f2)
    p_b76_version "$b76_s" && b76_rows="$b76_rows $b76_n:version" || { b76_all=0; b76_rows="$b76_rows $b76_n:VERSION"; }
    p_b76_sourced "$b76_s" && b76_rows="$b76_rows sourced" || { b76_all=0; b76_rows="$b76_rows SOURCED-EXITS"; }
    p_b76_text "$b76_s" && b76_rows="$b76_rows text" || { b76_all=0; b76_rows="$b76_rows TEXT"; }
done
[[ $b76_all -eq 1 ]] && ok "(B7.6a) both daemons: 'script --version' (executed, empty environment, empty directory) prints '<name> <FO_VERSION>' and nothing else - rc 0, no stderr, no file; sourced with --version as the caller's argument the script neither answers nor exits; the startup banner and the [DRY_RUN] / [LIVE] start pages say v\${FO_VERSION} once each and no printed line carries a literal version -$b76_rows" || bad "(B7.6a) version string:$b76_rows"
b76_ok=1; b76_crows=""
b76_ctl() {   # b76_ctl <label> <script> <sed expr> <predicate>: the predicate holds on the shipped script and FAILS on the mutant
    local label="$1" script="$2" expr="$3" pred="$4" m="$WORK/b76-$1.sh" rv mv_
    if ! mutate "$script" "$expr" "$m"; then b76_ok=0; b76_crows="$b76_crows $label:NOT-APPLIED"; return; fi
    "$pred" "$script" && rv=y || rv=n; "$pred" "$m" && mv_=y || mv_=n
    if [[ "$rv" == "y" && "$mv_" == "n" ]]; then b76_crows="$b76_crows $label:red"; else b76_ok=0; b76_crows="$b76_crows $label:[shipped=$rv,mutant=$mv_]"; fi
}
b76_both() { b76_ctl "pr-$1" "$PRIMARY" "$2" "$3"; b76_ctl "sb-$1" "$STANDBY" "$2" "$3"; }
b76_both no-handler     '/^if \[\[ "\${BASH_SOURCE\[0\]}" == "\$0" && "\${1:-}" == "--version" \]\]; then$/,/^fi$/ d' p_b76_version
b76_both handler-sourced 's|^if \[\[ "\${BASH_SOURCE\[0\]}" == "\$0" && |if [[ |' p_b76_sourced
b76_both handler-noexit '/^if \[\[ "\${BASH_SOURCE\[0\]}" == "\$0" && "\${1:-}" == "--version" \]\]; then$/,/^fi$/ s|; exit 0$||' p_b76_version
b76_both handler-extra  's|printf '"'"'%s %s\\n'"'"' "\$_fo_name" "\$FO_VERSION"|printf '"'"'%s %s extra\\n'"'"' "$_fo_name" "$FO_VERSION"|' p_b76_version
b76_both banner-literal 's|Failover v\${FO_VERSION} (3-TIER RPC)|Failover v0.6.10 (3-TIER RPC)|' p_b76_text
b76_both page-dry-literal 's|v\${FO_VERSION} started \[DRY_RUN\]|v0.6.9 started [DRY_RUN]|' p_b76_text
b76_both page-live-literal 's|v\${FO_VERSION} started \[LIVE\]|v0.6.9 started [LIVE]|' p_b76_text
b76_both constant-twice '/^FO_VERSION="/p' p_b76_text
[[ $b76_ok -eq 1 ]] && ok "(B7.6b) CONTROLS: no --version handler, a handler that fires when the script is sourced, one that does not exit, one that prints more than the name and the constant, a literal version in the banner / the [DRY_RUN] page / the [LIVE] page, the constant assigned twice - each turns its case red:$b76_crows" || bad "(B7.6b) a control is not red:$b76_crows"
# ══ B7.6 END ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

results_banner
