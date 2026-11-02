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
