# tests/lib/strace-net.awk — the filter of tests/strace-hermetic.sh (CI's strace job): reads `strace -f` output (each
# line led by its pid) of the whole tests/run_all.sh and writes TAB-separated rows. POSIX awk: it runs under mawk (the
# CI job's awk and Ubuntu's default), gawk and BWK awk; no {m,n} interval anywhere.
#   -v clients="curl ping …"  the net guard's list (curl + tests/lib/harness.sh's HARNESS_NET_CLIENTS, read there)
# Rows:
#   SUITE   <suite> <pid>                               a suite started (run_all's `bash test_*.sh`: argv[0] ends in bash)
#   INET    <suite> <pid> <exe> <syscall line>          EVERY AF_INET / AF_INET6 syscall line, from any process
#   REAL    <suite> <pid> <path> <execve line>          an exec of a client on the list from a SYSTEM directory
#   COUNT   <kind> <suite> <name> <n>                   kind INET (per suite), REAL / STUB / OTHER (per suite and
#                                                       basename), NETLINK / UNIX (per suite)
#   SUMMARY <name> <n>                                  execs, suites, inet_lines, real_client_execs, netlink_lines, unix_lines
# A process's suite is inherited at fork (clone / fork / vfork), set when it execs a suite, and dropped when it exits, so a
# child that outlives its suite stays that suite's (a late call is attributed, not lost). REAL = an exec, by a path under
# /bin /sbin /usr /snap or /opt, of a client on the list: the system's own binary. STUB = an exec of a listed or watched
# name by any other path: the net guard's stand-ins (run_all's and the harness's) and every suite's own stubs are files
# the suites create in their temp directories. OTHER = a real exec of a network-capable tool that is NOT on the list —
# socat (the notify socket is a UNIX socket), the interpreters, busybox, nc.openbsd …: counted, not failures by themselves;
# the INET rule sees whatever they would do on the network.
BEGIN {
  n = split(clients, W, " "); for (i = 1; i <= n; i++) if (W[i] != "") watch[W[i]] = 1
  n = split("socat python python3 python3.12 perl ruby node busybox nc.openbsd nc.traditional ssh-keyscan delv resolvectl ip ss", O, " ")
  for (i = 1; i <= n; i++) other[O[i]] = 1
  suite = "(run_all)"; nexec = 0; ninet = 0; nreal = 0; nnl = 0; nux = 0; nsuites = 0
}
function lead(l) {                                   # split the pid off the line: P = the pid, returns the rest
  if (match(l, /^\[pid +[0-9]+\] /)) { P = substr(l, 6, RLENGTH - 7); gsub(/ /, "", P); return substr(l, RLENGTH + 1) }
  if (match(l, /^[0-9]+ +/)) { P = substr(l, 1, RLENGTH); gsub(/ /, "", P); return substr(l, RLENGTH + 1) }
  P = "0"; return l
}
function su(p) { return (p in suite_of) ? suite_of[p] : suite }
function exec_ok(p, path, l,    b, kind, s) {
  prog[p] = path; nexec++
  if (l ~ /\["[^"]*", "run_all\.sh"\]/ || l ~ /\["[^"]*", "[^"]*\/run_all\.sh"\]/) suite_of[p] = "(run_all)"
  if (l ~ /\["[^"]*bash", "test_[A-Za-z0-9_]+\.sh"\]/) {     # run_all's `"${BASH:-bash}" test_x.sh` (not `dirname test_x.sh`)
    s = l; sub(/^[^[]*\["[^"]*", "/, "", s); sub(/".*/, "", s)
    suite = s; suite_of[p] = s; byexec[p] = 1
    if (!(s in seen)) { seen[s] = 1; nsuites++ }
    print "SUITE\t" s "\t" p
  }
  b = path; sub(/.*\//, "", b)
  if (!(b in watch) && !(b in other)) return
  kind = "STUB"
  if (path ~ /^\/(bin|sbin|usr|snap|opt)\//) kind = (b in watch) ? "REAL" : "OTHER"
  if (kind == "REAL") { nreal++; print "REAL\t" su(p) "\t" p "\t" path "\t" substr(l, 1, 400) }
  cnt[kind SUBSEP su(p) SUBSEP b]++
}
{
  rest = lead($0); p = P
  if (rest ~ /^\+\+\+ (exited|killed)/) { delete suite_of[p]; delete prog[p]; delete byexec[p]; next }
  if (rest ~ /^(clone|clone3|fork|vfork)\(/ || rest ~ /^<\.\.\. (clone|clone3|fork|vfork) resumed>/) {
    if (match(rest, /= [0-9]+$/)) {
      c = substr(rest, RSTART + 2)
      if (!(c in byexec)) { if (p in suite_of) suite_of[c] = suite_of[p]; else suite_of[c] = suite }   # a child that already exec'd its suite keeps it
      if (p in prog) prog[c] = prog[p]
    }
    next
  }
  if (rest ~ /^execve(at)?\(/) {
    path = rest; sub(/^execve(at)?\([^"]*"/, "", path); sub(/".*/, "", path)
    if (rest ~ /<unfinished \.\.\.>$/) { pend[p] = path; pendl[p] = rest; next }
    if (rest ~ /\) = 0$/) exec_ok(p, path, rest)
    next
  }
  if (rest ~ /^<\.\.\. execve(at)? resumed>/) {
    if ((p in pend) && rest ~ /= 0$/) exec_ok(p, pend[p], pendl[p])
    delete pend[p]; delete pendl[p]; next
  }
  if (rest ~ /AF_INET/) { ninet++; ci[su(p)]++; if (ninet <= 2000) print "INET\t" su(p) "\t" p "\t" prog[p] "\t" substr(rest, 1, 400); next }
  if (rest ~ /AF_NETLINK/) { nnl++; cn[su(p)]++; next }
  if (rest ~ /AF_UNIX|AF_LOCAL/) { nux++; cu[su(p)]++; next }
}
END {
  for (k in ci) print "COUNT\tINET\t" k "\t-\t" ci[k]
  for (k in cnt) { split(k, a, SUBSEP); print "COUNT\t" a[1] "\t" a[2] "\t" a[3] "\t" cnt[k] }
  for (k in cn) print "COUNT\tNETLINK\t" k "\t-\t" cn[k]
  for (k in cu) print "COUNT\tUNIX\t" k "\t-\t" cu[k]
  print "SUMMARY\texecs\t" nexec
  print "SUMMARY\tsuites\t" nsuites
  print "SUMMARY\tinet_lines\t" ninet
  print "SUMMARY\treal_client_execs\t" nreal
  print "SUMMARY\tnetlink_lines\t" nnl
  print "SUMMARY\tunix_lines\t" nux
}
