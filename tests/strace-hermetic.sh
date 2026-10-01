#!/bin/bash
# tests/strace-hermetic.sh — the WHOLE tests/run_all.sh under strace: at the syscall level, red on any inet socket (and any
# other socket family than AF_UNIX and AF_NETLINK) in the whole run (v0.7 Block 6.3.1). CI's `strace-hermetic` job runs
# it on ubuntu-24.04 (.github/workflows/ci.yml); any Linux host with strace can:
#     bash tests/strace-hermetic.sh [out-dir]          (out-dir default: a new mktemp -d; the trace rows land there)
# Not a suite (no test_ prefix: run_all never runs it) and Linux-only (strace).
#
# run_all's stage (4) sees a network client a suite reaches through PATH — the net guard's stand-ins log the call. It
# cannot see a socket opened any other way (its LIMIT, tests/HARNESS.md: bash's /dev/tcp and /dev/udp, `command -p`, a
# plain `env -i` child, an absolute path, a PATH a suite builds, a call after its final read of the logs, an
# interpreter's own socket, socat, a client not on the list, a log a suite truncates). This job traces run_all and every
# process it starts (strace -f --seccomp-bpf: socket socketpair connect bind listen sendto sendmsg sendmmsg, execve
# execveat, clone clone3 fork vfork; a process that outlives its suite is still traced and still attributed to it), and
# filters the trace through tests/lib/strace-net.awk (POSIX awk; CI pins mawk). RED on any of:
#   - an AF_INET or AF_INET6 syscall line, from ANY process of the run, loopback included;
#   - a syscall line naming any other socket family than AF_UNIX / AF_LOCAL and AF_NETLINK (AF_PACKET, AF_VSOCK …: a raw
#     frame leaves the host too — it needs CAP_NET_RAW, which a non-root runner does not have; root in docker does);
#   - an exec of a REAL network client: a client on the net guard's list (curl + HARNESS_NET_CLIENTS, read from
#     tests/lib/harness.sh as run_all reads it), by its basename, exec'd from a system directory (/bin /sbin /usr /snap
#     /opt) or from ANY directory that is not one of the run's stand-in and stub directories — so a symlink to a real
#     client, or a copy of it under the same name, is REAL wherever it sits. The run lists those directories itself: this
#     script sets HARNESS_STUB_DIRS_LOG, and run_all (each suite's stand-ins), the harness (its net guard) and every suite
#     with its own stub of a listed client (harness_stub_dir) write theirs there;
#   - run_all failing (its own exit status), or a vacuous trace (not every suite traced, no filter summary, or no stand-in
#     directory listed).
# LIMIT (named): a copy of a client RENAMED away from its listed basename, or a real client copied or linked INTO a listed
# stand-in or stub directory, is not REAL here — the INET and FAMILY rules see any socket it opens.
# NOT a failure by itself: a real exec of a tool a suite legitimately runs — socat (the daemons' sd_notify datagrams go
# to a UNIX socket), the interpreters (a suite's perl clock, the arm suite's python3 / perl removal tools) — counted and
# printed as OTHER; the INET and FAMILY rules see whatever they would do on the network. AF_NETLINK and AF_UNIX lines are
# counted, not failures (neither leaves the host). On red it prints the counts per suite and the first lines of each kind.
set -u
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT" || exit 2
OUT="$(cd "$OUT" && pwd)"
command -v strace > /dev/null 2>&1 || { echo "strace-hermetic: strace is not installed (Linux only)"; exit 2; }
clients=$(sed -n 's/^HARNESS_NET_CLIENTS="\(.*\)"$/\1/p' "$T/lib/harness.sh")
[[ -n "$clients" ]] || { echo "strace-hermetic: cannot read HARNESS_NET_CLIENTS from tests/lib/harness.sh"; exit 2; }
nsuites=$(ls "$T"/test_*.sh | wc -l | tr -d ' ')
echo "strace-hermetic: $(strace -V | head -1); bash $("${BASH:-bash}" --version | head -1 | sed 's/^GNU bash, version //'); awk $(readlink -f "$(command -v awk)" 2>/dev/null || command -v awk); out $OUT"
rm -f "$OUT/trace.fifo" "$OUT/net.tsv"; : > "$OUT/stub-dirs" || exit 2
HARNESS_STUB_DIRS_LOG="$OUT/stub-dirs"; export HARNESS_STUB_DIRS_LOG
mkfifo "$OUT/trace.fifo" || exit 2
awk -v clients="curl $clients" -v stubdirs="$OUT/stub-dirs" -f "$T/lib/strace-net.awk" < "$OUT/trace.fifo" > "$OUT/net.tsv" 2> "$OUT/filter.err" &
fpid=$!
t0=$(date +%s)
( cd "$T" && strace -f --seccomp-bpf -q -e trace=socket,socketpair,connect,bind,listen,sendto,sendmsg,sendmmsg,execve,execveat,clone,clone3,fork,vfork \
      -e signal=none -s 200 -o "$OUT/trace.fifo" "${BASH:-bash}" run_all.sh ) > "$OUT/runall.txt" 2>&1
rc=$?
exec 3<> "$OUT/trace.fifo"; exec 3>&-   # a filter still waiting for a writer (strace never opened the fifo) now reads EOF
wait "$fpid"
t1=$(date +%s)
sv() { awk -F'\t' -v k="$1" '$1 == "SUMMARY" && $2 == k { print $3 }' "$OUT/net.tsv"; }
inet=$(sv inet_lines); fam=$(sv other_family_lines); real=$(sv real_client_execs); seen=$(sv suites); execs=$(sv execs); nl=$(sv netlink_lines); ux=$(sv unix_lines); nsd=$(sv stub_dirs)
grep -E '^  suites:|^  slowest:|^  per-suite wall seconds:|^  FAILED|NET-GUARD|KILLED|^═══ (GREEN|NOT GREEN)' "$OUT/runall.txt"
echo "  run_all rc=$rc under strace; wall $((t1 - t0)) s"
echo "  traced: ${execs:-?} execs, ${seen:-?} of $nsuites suites; AF_INET/AF_INET6 syscall lines: ${inet:-?}; other-family lines: ${fam:-?}; real network-client execs: ${real:-?}; AF_NETLINK lines: ${nl:-?}; AF_UNIX lines: ${ux:-?}; stand-in and stub directories listed: ${nsd:-?}"
awk -F'\t' '$1 == "COUNT" && $2 == "OTHER" { printf "  OTHER (real, not on the list — not a failure by itself): %s %s x%s\n", $3, $4, $5 }' "$OUT/net.tsv" | sort
fail=""
[[ -n "$inet" && -n "$fam" && -n "$real" && -n "$seen" && -n "$nsd" ]] || fail="$fail no-filter-summary(see $OUT/filter.err)"
[[ "$rc" == "0" ]] || fail="$fail run_all-rc=$rc"
[[ "${inet:-x}" == "0" ]] || fail="$fail inet-lines=${inet:-?}"
[[ "${fam:-x}" == "0" ]] || fail="$fail other-family-lines=${fam:-?}"
[[ "${real:-x}" == "0" ]] || fail="$fail real-client-execs=${real:-?}"
[[ "${seen:-x}" == "$nsuites" ]] || fail="$fail suites-traced=${seen:-?}/$nsuites"
[[ "${nsd:-0}" -ge "$nsuites" ]] 2>/dev/null || fail="$fail stub-dirs-listed=${nsd:-?}(fewer than one per suite: the list is not being written)"
if [[ -z "$fail" ]]; then
    echo "═══ strace: HERMETIC — the whole run_all, every process: zero AF_INET/AF_INET6 syscalls, zero other-family sockets, zero real network-client execs, $seen/$nsuites suites traced ═══"
    exit 0
fi
echo "  per suite — AF_INET/AF_INET6 lines:"
awk -F'\t' '$1 == "COUNT" && $2 == "INET" { printf "    %6d  %s\n", $5, $3 }' "$OUT/net.tsv" | sort -rn
echo "  per suite — other-family socket lines:"
awk -F'\t' '$1 == "COUNT" && $2 == "FAMILY" { printf "    %6d  %s  %s\n", $5, $3, $4 }' "$OUT/net.tsv" | sort -rn
echo "  per suite — real network-client execs:"
awk -F'\t' '$1 == "COUNT" && $2 == "REAL" { printf "    %6d  %s  %s\n", $5, $3, $4 }' "$OUT/net.tsv" | sort -rn
echo "  first AF_INET lines (suite, pid, program, syscall):"
awk -F'\t' '$1 == "INET" && n[$2]++ < 3 { printf "    %s  %s  %s  %s\n", $2, $3, $4, substr($5, 1, 200) }' "$OUT/net.tsv"
echo "  first other-family lines (suite, pid, family, syscall):"
awk -F'\t' '$1 == "FAMILY" && n[$2]++ < 3 { printf "    %s  %s  %s  %s\n", $2, $3, $4, substr($5, 1, 200) }' "$OUT/net.tsv"
echo "  first real client execs:"
awk -F'\t' '$1 == "REAL" && n[$2]++ < 3 { printf "    %s  %s  %s\n", $2, $3, substr($5, 1, 200) }' "$OUT/net.tsv"
[[ "$rc" == "0" ]] || { echo "  run_all's last lines:"; tail -15 "$OUT/runall.txt" | sed 's/^/    /'; }
echo "═══ strace: NOT HERMETIC —$fail (rows: $OUT/net.tsv) ═══"
exit 1
