#!/bin/bash
# tests/strace-hermetic.sh — the WHOLE tests/run_all.sh under strace: at the syscall level, red on any inet socket (and any
# other socket family than AF_UNIX and AF_NETLINK) in the whole run (v0.7 Block 6.3.1). CI's `strace-hermetic` job runs
# it on ubuntu-24.04 (.github/workflows/ci.yml); any Linux host with strace can:
#     bash tests/strace-hermetic.sh [out-dir]          (out-dir default: a new mktemp -d; the trace rows land there)
# Not a suite (no test_ prefix: run_all never runs it) and Linux-only (strace, /proc).
#
# run_all's stage (4) sees a network client a suite reaches through PATH — the net guard's stand-ins log the call. It
# cannot see a socket opened any other way (its LIMIT, tests/HARNESS.md: bash's /dev/tcp and /dev/udp, `command -p`, a
# plain `env -i` child, an absolute path, a PATH a suite builds, a call after its final read of the logs, an
# interpreter's own socket, socat, a client not on the list, a log a suite truncates). This job traces run_all and every
# process it starts (strace -f --seccomp-bpf: socket socketpair connect bind listen sendto sendmsg sendmmsg, execve
# execveat, clone clone3 fork vfork; a process that outlives its suite is still traced and still attributed to it), and
# filters the trace through tests/lib/strace-net.awk (POSIX awk; CI pins mawk). A syscall line's family is its socket's
# own — socket()'s first argument, else the line's sockaddr (sa_family=); a decoded netlink payload's family word is not
# the socket's. RED on any of:
#   - an AF_INET or AF_INET6 socket's syscall line, from ANY process of the run, loopback included;
#   - a socket of any other family than AF_UNIX / AF_LOCAL and AF_NETLINK (AF_PACKET, AF_VSOCK, an unknown family, a
#     sockaddr of AF_UNSPEC …: a raw frame leaves the host too — it needs CAP_NET_RAW, which a non-root runner does not
#     have; root in docker does);
#   - an exec of a REAL network client: a client on the net guard's list (curl + HARNESS_NET_CLIENTS, read from
#     tests/lib/harness.sh as run_all reads it), by its basename, exec'd from a system directory (/bin /sbin /usr /snap
#     /opt) or from ANY directory that is not one of the run's trusted stand-in and stub directories — so a symlink to a
#     real client, or a copy of it under the same name, is REAL wherever it sits. The run lists those directories
#     itself: this script sets HARNESS_STUB_DIRS_LOG, and run_all (each suite's stand-ins), the harness (its net guard)
#     and every suite with its own stub of a listed client (harness_stub_dir) write theirs there;
#   - a BAD registration: a listed directory outside the run's own temp root. This script points TMPDIR at a fresh
#     directory under the out-dir for the whole run, so every mktemp of run_all, the harness and the suites lands under
#     it; a directory listed from anywhere else (/etc/alternatives, whose nc / netcat / telnet / traceroute link to the
#     real binaries on Ubuntu; /usr/bin; a Homebrew bin) would turn real execs into stubs — it is red, and not trusted;
#   - run_all failing (its own exit status), or a vacuous trace (not every suite traced, no filter summary, or no stand-in
#     directory listed);
#   - a run that does not END: strace still tracing 30 s after run_all itself has exited (a process that left its
#     suite's process group outlived run_all — run_all stops whatever a suite leaves in its own group), or, when
#     STRACE_HERMETIC_BOUND is set (seconds; CI sets it from the job's own budget, below its timeout-minutes), the run
#     still going at that bound. Either way every process still traced is named and KILLed, so the step ends red with
#     its names instead of at the job's timeout. run_all's output streams into the step log as it is written, so a suite
#     KILLED at run_all's per-suite cap is named there live.
# LIMIT (named): a copy of a client RENAMED away from its listed basename, a real client copied or linked INTO a trusted
# stand-in or stub directory (or a symlink under the temp root leading out of it), and an exec through a file descriptor
# (execveat AT_EMPTY_PATH, /proc/self/fd/N — counted and printed as fd execs: there is no name to read) are not REAL here;
# the INET and FAMILY rules see any socket such a binary opens through a socket syscall (not one io_uring's socket op
# makes).
# NOT a failure by itself: a real exec of a tool a suite legitimately runs — socat (the daemons' sd_notify datagrams go
# to a UNIX socket), the interpreters (a suite's perl clock, the arm suite's python3 / perl removal tools) — counted and
# printed as OTHER; the INET and FAMILY rules see whatever they would do on the network. AF_NETLINK and AF_UNIX lines are
# counted, not failures (neither leaves the host). On red it prints the counts per suite and the first lines of each kind.
set -u
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT" || exit 2
OUT="$(cd "$OUT" && pwd -P)"
command -v strace > /dev/null 2>&1 || { echo "strace-hermetic: strace is not installed (Linux only)"; exit 2; }
clients=$(sed -n 's/^HARNESS_NET_CLIENTS="\(.*\)"$/\1/p' "$T/lib/harness.sh")
[[ -n "$clients" ]] || { echo "strace-hermetic: cannot read HARNESS_NET_CLIENTS from tests/lib/harness.sh"; exit 2; }
bound="${STRACE_HERMETIC_BOUND:-0}"
case "$bound" in ''|*[!0-9]*|0?*) echo "strace-hermetic: STRACE_HERMETIC_BOUND must be a whole number of seconds, base 10, without a leading zero (0: no bound) — got '$bound'"; exit 2 ;; esac
GRACE=30   # seconds strace may still trace after run_all itself has exited (its last processes ending)
nsuites=$(ls "$T"/test_*.sh | wc -l | tr -d ' ')
echo "strace-hermetic: $(strace -V | head -1); bash $("${BASH:-bash}" --version | head -1 | sed 's/^GNU bash, version //'); awk $(readlink -f "$(command -v awk)" 2>/dev/null || command -v awk); out $OUT; bound ${bound} s (0: none)"
rm -rf "$OUT/tmp"; rm -f "$OUT/trace.fifo" "$OUT/net.tsv" "$OUT/runall.rc"; : > "$OUT/stub-dirs" || exit 2
mkdir -p "$OUT/tmp" || exit 2
HARNESS_STUB_DIRS_LOG="$OUT/stub-dirs"; export HARNESS_STUB_DIRS_LOG
TMPDIR="$OUT/tmp"; export TMPDIR     # the run's own temp root: the filter trusts a listed directory only under it
mkfifo "$OUT/trace.fifo" || exit 2
awk -v clients="curl $clients" -v stubdirs="$OUT/stub-dirs" -v tmproot="$TMPDIR" -f "$T/lib/strace-net.awk" < "$OUT/trace.fifo" > "$OUT/net.tsv" 2> "$OUT/filter.err" &
fpid=$!
: > "$OUT/runall.txt" || exit 2
t0=$(date +%s)
# run_all under strace; a wrapper shell writes run_all's own exit status once run_all has ended (strace itself ends only
# when every traced process has)
( cd "$T" && exec strace -f --seccomp-bpf -q -e trace=socket,socketpair,connect,bind,listen,sendto,sendmsg,sendmmsg,execve,execveat,clone,clone3,fork,vfork \
      -e signal=none -s 200 -o "$OUT/trace.fifo" "${BASH:-bash}" -c '"$1" run_all.sh; r=$?; printf "%s\n" "$r" > "$2"; exit "$r"' strace-hermetic "${BASH:-bash}" "$OUT/runall.rc" ) > "$OUT/runall.txt" 2>&1 &
spid=$!
tail -n +1 -f "$OUT/runall.txt" 2> /dev/null &   # run_all's lines into the step log as they are written
tpid=$!
held=""; tend=""
while kill -0 "$spid" 2> /dev/null; do
    now=$(date +%s)
    [[ -z "$tend" && -s "$OUT/runall.rc" ]] && tend=$now
    if [[ -n "$tend" ]] && (( now - tend >= GRACE )); then held="outlived"; break; fi
    if (( bound > 0 && now - t0 >= bound )); then held="bound"; break; fi
    sleep 1
done
if [[ -n "$held" ]]; then
    hp=$(grep -l "^TracerPid:[[:space:]]*$spid\$" /proc/[0-9]*/status 2> /dev/null | sed 's#^/proc/##; s#/status$##' | tr '\n' ' ')
    if [[ "$held" == "bound" ]]; then
        echo "  BOUND REACHED: STRACE_HERMETIC_BOUND=$bound s after the run began, run_all $([[ -n "$tend" ]] && echo "had ended" || echo "was still running") — every traced process is named and stopped (KILL):"
    else
        echo "  HELD: strace still tracing ${GRACE} s after run_all itself ended — the processes that outlived run_all, named and stopped (KILL):"
    fi
    for p in $hp; do printf '    pid %s: %s\n' "$p" "$(tr '\0' ' ' < "/proc/$p/cmdline" 2> /dev/null | cut -c1-200)"; done
    for p in $hp; do kill -KILL "$p" 2> /dev/null; done
    sleep 2; kill -KILL "$spid" 2> /dev/null
fi
wait "$spid"
exec 3<> "$OUT/trace.fifo"; exec 3>&-   # a filter still waiting for a writer (strace never opened the fifo) now reads EOF
wait "$fpid"
t1=$(date +%s)
sleep 2; kill "$tpid" 2> /dev/null; wait "$tpid" 2> /dev/null
rc=$(cat "$OUT/runall.rc" 2> /dev/null); [[ -n "$rc" ]] || rc="none"
sv() { awk -F'\t' -v k="$1" '$1 == "SUMMARY" && $2 == k { print $3 }' "$OUT/net.tsv"; }
inet=$(sv inet_lines); fam=$(sv other_family_lines); real=$(sv real_client_execs); seen=$(sv suites); execs=$(sv execs); nl=$(sv netlink_lines); ux=$(sv unix_lines); nsd=$(sv stub_dirs); nbad=$(sv bad_stub_dirs); nfd=$(sv fd_execs)
echo "  ── strace-hermetic summary ──"
grep -E '^  suites:|^  slowest:|^  per-suite wall seconds:|^  FAILED|NET-GUARD|KILLED|LEFT RUNNING|^═══ (GREEN|NOT GREEN)' "$OUT/runall.txt"
echo "  run_all rc=$rc under strace; wall $((t1 - t0)) s"
echo "  traced: ${execs:-?} execs, ${seen:-?} of $nsuites suites; AF_INET/AF_INET6 syscall lines: ${inet:-?}; other-family lines: ${fam:-?}; real network-client execs: ${real:-?}; AF_NETLINK lines: ${nl:-?}; AF_UNIX lines: ${ux:-?}; stand-in and stub directories listed: ${nsd:-?} trusted, ${nbad:-?} outside the run's temp root; fd execs (no name to read): ${nfd:-?}"
awk -F'\t' '$1 == "COUNT" && $2 == "OTHER" { printf "  OTHER (real, not on the list — not a failure by itself): %s %s x%s\n", $3, $4, $5 }' "$OUT/net.tsv" | sort
fail=""
[[ -n "$inet" && -n "$fam" && -n "$real" && -n "$seen" && -n "$nsd" && -n "$nbad" ]] || fail="$fail no-filter-summary(see $OUT/filter.err)"
[[ -z "$held" ]] || fail="$fail run-did-not-end(${held})"
[[ "$rc" == "0" ]] || fail="$fail run_all-rc=$rc"
[[ "${inet:-x}" == "0" ]] || fail="$fail inet-lines=${inet:-?}"
[[ "${fam:-x}" == "0" ]] || fail="$fail other-family-lines=${fam:-?}"
[[ "${real:-x}" == "0" ]] || fail="$fail real-client-execs=${real:-?}"
[[ "${nbad:-x}" == "0" ]] || fail="$fail stub-dirs-outside-the-temp-root=${nbad:-?}"
[[ "${seen:-x}" == "$nsuites" ]] || fail="$fail suites-traced=${seen:-?}/$nsuites"
[[ "${nsd:-0}" -ge "$nsuites" ]] 2>/dev/null || fail="$fail stub-dirs-listed=${nsd:-?}(fewer than one per suite: the list is not being written)"
if [[ -z "$fail" ]]; then
    echo "═══ strace: HERMETIC — the whole run_all, every process: zero AF_INET/AF_INET6 syscalls, zero other-family sockets, zero real network-client execs, every listed stub directory under the run's temp root, $seen/$nsuites suites traced ═══"
    exit 0
fi
echo "  per suite — AF_INET/AF_INET6 lines:"
awk -F'\t' '$1 == "COUNT" && $2 == "INET" { printf "    %6d  %s\n", $5, $3 }' "$OUT/net.tsv" | sort -rn
echo "  per suite — other-family socket lines:"
awk -F'\t' '$1 == "COUNT" && $2 == "FAMILY" { printf "    %6d  %s  %s\n", $5, $3, $4 }' "$OUT/net.tsv" | sort -rn
echo "  per suite — real network-client execs:"
awk -F'\t' '$1 == "COUNT" && $2 == "REAL" { printf "    %6d  %s  %s\n", $5, $3, $4 }' "$OUT/net.tsv" | sort -rn
echo "  stand-in or stub directories listed outside the run's temp root ($TMPDIR):"
awk -F'\t' '$1 == "BADREG" { printf "    %s\n", $2 }' "$OUT/net.tsv"
echo "  first AF_INET lines (suite, pid, program, syscall):"
awk -F'\t' '$1 == "INET" && n[$2]++ < 3 { printf "    %s  %s  %s  %s\n", $2, $3, $4, substr($5, 1, 200) }' "$OUT/net.tsv"
echo "  first other-family lines (suite, pid, family, syscall):"
awk -F'\t' '$1 == "FAMILY" && n[$2]++ < 3 { printf "    %s  %s  %s  %s\n", $2, $3, $4, substr($5, 1, 200) }' "$OUT/net.tsv"
echo "  first real client execs:"
awk -F'\t' '$1 == "REAL" && n[$2]++ < 3 { printf "    %s  %s  %s\n", $2, $3, substr($5, 1, 200) }' "$OUT/net.tsv"
[[ "$rc" == "0" ]] || { echo "  run_all's last lines:"; tail -15 "$OUT/runall.txt" | sed 's/^/    /'; }
echo "═══ strace: NOT HERMETIC —$fail (rows: $OUT/net.tsv) ═══"
exit 1
