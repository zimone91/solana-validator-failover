# tests/lib/strace-net.awk — the filter of tests/strace-hermetic.sh (CI's strace job): reads `strace -f` output (each
# line led by its pid) of the whole tests/run_all.sh and writes TAB-separated rows. POSIX awk: it runs under mawk (the
# CI job's awk and Ubuntu's default), gawk and BWK awk; no {m,n} interval anywhere.
#   -v clients="curl ping …"  the net guard's list (curl + tests/lib/harness.sh's HARNESS_NET_CLIENTS, read there)
#   -v stubdirs=<file>        the run's stand-in and stub directories, one per line (HARNESS_STUB_DIRS_LOG: run_all, the
#                             harness and the suites write each directory that holds a stand-in or a stub of a listed
#                             client); read at the END, once the run has written all of them
#   -v tmproot=<dir>          the run's own temp root (tests/strace-hermetic.sh points TMPDIR there for the whole run, so
#                             every mktemp of run_all, the harness and the suites lands under it): a listed directory is
#                             TRUSTED as a stand-in or stub directory only when it lies under this root — anything else on
#                             the list (/etc/alternatives, /usr/bin, a Homebrew bin, /tmp/x) is a BAD registration: red,
#                             and not trusted (an exec of a listed client from it is REAL)
# Rows:
#   SUITE   <suite> <pid>                               a suite started (run_all's `bash test_*.sh`: argv[0] ends in bash)
#   INET    <suite> <pid> <exe> <syscall line>          EVERY syscall line whose socket is AF_INET / AF_INET6, from any process
#   FAMILY  <suite> <pid> <family> <syscall line>       every syscall line whose socket is of another family than AF_INET,
#                                                       AF_INET6, AF_UNIX / AF_LOCAL or AF_NETLINK (AF_PACKET, AF_VSOCK,
#                                                       AF_BLUETOOTH, an unknown 0x.. family, a sockaddr of AF_UNSPEC …)
#   REAL    <suite> <pid> <path> <execve line>          an exec of a client on the list that is not a stand-in or a stub
#   BADREG  <dir>                                       a listed stand-in or stub directory outside the run's temp root
#   FDEXEC  <suite> <pid> <execve line>                 an exec through a file descriptor (execveat AT_EMPTY_PATH, a
#                                                       /proc/…/fd/N or /dev/fd/N path): no basename to read (the LIMIT)
#   COUNT   <kind> <suite> <name> <n>                   kind INET / FAMILY (per suite; FAMILY per family), REAL / STUB /
#                                                       OTHER (per suite and basename), NETLINK / UNIX (per suite)
#   SUMMARY <name> <n>                                  execs, suites, inet_lines, other_family_lines, real_client_execs,
#                                                       netlink_lines, unix_lines, stub_dirs, bad_stub_dirs, fd_execs
# A line's FAMILY is its socket's own: socket()'s and socketpair()'s first argument, else the first sockaddr on the line
# (`{sa_family=…`: connect's and bind's address, sendto's destination, sendmsg's msg_name). A decoded payload's family
# word (a netlink request's ifa_family=AF_INET, rtm_family=…) is not the socket's, and a line with no family of its own
# (a send on a connected socket, listen) is counted where its socket was created: an inet socket's socket() line is INET.
# A process's suite is inherited at fork (clone / fork / vfork), set when it execs a suite, and dropped when it exits, so a
# child that outlives its suite stays that suite's (a late call is attributed, not lost). REAL = an exec of a LISTED
# client's basename from a system directory (/bin /sbin /usr /snap /opt), or from ANY other directory that is not a
# trusted stand-in or stub directory (the stubdirs list, under tmproot) — so a symlink to the real client or a copy of it
# under the same name counts as REAL wherever it sits outside those directories. STUB = an exec of a listed basename from
# a trusted directory (the net guard's stand-ins, run_all's and the harness's, and the suites' own stubs), or of an OTHER
# name from outside the system directories. OTHER = a real exec of a network-capable tool that is NOT on the list —
# socat (the notify socket is a UNIX socket), the interpreters, busybox, nc.openbsd …: counted, not failures by
# themselves. LIMIT (named): a copy of a client RENAMED (not its listed basename), a real client copied or linked INTO a
# trusted directory (or a symlink under the temp root that leads out of it), and an exec through a file descriptor
# (FDEXEC: no name to read) are not REAL here; the INET and FAMILY rules see any socket such a binary opens — but not a
# socket made without a socket syscall line (io_uring's socket op).
BEGIN {
  n = split(clients, W, " "); for (i = 1; i <= n; i++) if (W[i] != "") watch[W[i]] = 1
  n = split("socat python python3 python3.12 perl ruby node busybox nc.openbsd nc.traditional ssh-keyscan delv resolvectl ip ss", O, " ")
  for (i = 1; i <= n; i++) other[O[i]] = 1
  suite = "(run_all)"; nexec = 0; ninet = 0; nfam = 0; nreal = 0; nnl = 0; nux = 0; nsuites = 0; npend = 0; nfd = 0
}
function lead(l) {                                   # split the pid off the line: P = the pid, returns the rest
  if (match(l, /^\[pid +[0-9]+\] /)) { P = substr(l, 6, RLENGTH - 7); gsub(/ /, "", P); return substr(l, RLENGTH + 1) }
  if (match(l, /^[0-9]+ +/)) { P = substr(l, 1, RLENGTH); gsub(/ /, "", P); return substr(l, RLENGTH + 1) }
  P = "0"; return l
}
function su(p) { return (p in suite_of) ? suite_of[p] : suite }
function trusted(d) {                                # a listed directory under the run's temp root, spelled plainly
  if (tmproot == "" || substr(d, 1, length(tmproot) + 1) != tmproot "/") return 0
  return (d !~ /\/\.\.?(\/|$)/ && d !~ /\/\//)
}
function exec_ok(p, path, l,    b, s, d, k) {
  prog[p] = path; nexec++
  if (l ~ /\["[^"]*", "run_all\.sh"\]/ || l ~ /\["[^"]*", "[^"]*\/run_all\.sh"\]/) suite_of[p] = "(run_all)"
  if (l ~ /\["[^"]*bash", "test_[A-Za-z0-9_]+\.sh"\]/) {     # run_all's `"${BASH:-bash}" test_x.sh` (not `dirname test_x.sh`)
    s = l; sub(/^[^[]*\["[^"]*", "/, "", s); sub(/".*/, "", s)
    suite = s; suite_of[p] = s; byexec[p] = 1
    if (!(s in seen)) { seen[s] = 1; nsuites++ }
    print "SUITE\t" s "\t" p
  }
  if ((l ~ /^execveat\(/ && l ~ /AT_EMPTY_PATH/) || path ~ /^\/(proc\/(self|[0-9]+)|dev)\/fd\//) {   # through a descriptor
    nfd++; if (nfd <= 200) print "FDEXEC\t" su(p) "\t" p "\t" substr(l, 1, 400)
    return
  }
  b = path; sub(/.*\//, "", b)
  if (!(b in watch) && !(b in other)) return
  if (path ~ /^\/(bin|sbin|usr|snap|opt)\//) {
    if (b in watch) { nreal++; print "REAL\t" su(p) "\t" p "\t" path "\t" substr(l, 1, 400); cnt["REAL" SUBSEP su(p) SUBSEP b]++ }
    else cnt["OTHER" SUBSEP su(p) SUBSEP b]++
    return
  }
  if (!(b in watch)) { cnt["STUB" SUBSEP su(p) SUBSEP b]++; return }
  d = path; if (d !~ /\//) d = "."; else sub(/\/[^\/]*$/, "", d)   # a listed basename outside the system directories:
  k = su(p) SUBSEP b SUBSEP d                                         # decided at the END, against the stub directories
  if (!(k in pend)) { npend++; pk[npend] = k; pp[npend] = p; ppath[npend] = path; pl[npend] = substr(l, 1, 400) }
  pend[k]++
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
    if (rest ~ /<unfinished \.\.\.>$/) { xpend[p] = path; xpendl[p] = rest; next }
    if (rest ~ /\) = 0$/) exec_ok(p, path, rest)
    next
  }
  if (rest ~ /^<\.\.\. execve(at)? resumed>/) {
    if ((p in xpend) && rest ~ /= 0$/) exec_ok(p, xpend[p], xpendl[p])
    delete xpend[p]; delete xpendl[p]; next
  }
  # the socket's own family: socket()'s / socketpair()'s first argument, else the line's first sockaddr ({sa_family=…)
  if (rest ~ /^socket(pair)?\(/) { fam = rest; sub(/^socket(pair)?\(/, "", fam); sub(/[,)].*/, "", fam); sub(/[ \t].*/, "", fam) }
  else if (match(rest, /\{sa_family=[^,}]*/)) fam = substr(rest, RSTART + 11, RLENGTH - 11)
  else next                                          # no family of its own: counted where its socket was created
  if (fam == "AF_INET" || fam == "AF_INET6") { ninet++; ci[su(p)]++; if (ninet <= 2000) print "INET\t" su(p) "\t" p "\t" prog[p] "\t" substr(rest, 1, 400); next }
  if (fam == "AF_NETLINK") { nnl++; cn[su(p)]++; next }
  if (fam == "AF_UNIX" || fam == "AF_LOCAL") { nux++; cu[su(p)]++; next }
  nfam++; cf[su(p) SUBSEP fam]++; if (nfam <= 2000) print "FAMILY\t" su(p) "\t" p "\t" fam "\t" substr(rest, 1, 400)
}
END {
  ns = 0; nbad = 0
  if (stubdirs != "") while ((getline sd < stubdirs) > 0) {
    if (sd == "" || (sd in listed)) continue
    listed[sd] = 1
    if (trusted(sd)) { stubdir[sd] = 1; ns++ } else { nbad++; print "BADREG\t" sd }
  }
  for (i = 1; i <= npend; i++) {
    split(pk[i], a, SUBSEP)
    if (a[3] in stubdir) { cnt["STUB" SUBSEP a[1] SUBSEP a[2]] += pend[pk[i]]; continue }
    nreal += pend[pk[i]]; cnt["REAL" SUBSEP a[1] SUBSEP a[2]] += pend[pk[i]]
    print "REAL\t" a[1] "\t" pp[i] "\t" ppath[i] "\t" pl[i]
  }
  for (k in ci) print "COUNT\tINET\t" k "\t-\t" ci[k]
  for (k in cf) { split(k, a, SUBSEP); print "COUNT\tFAMILY\t" a[1] "\t" a[2] "\t" cf[k] }
  for (k in cnt) { split(k, a, SUBSEP); print "COUNT\t" a[1] "\t" a[2] "\t" a[3] "\t" cnt[k] }
  for (k in cn) print "COUNT\tNETLINK\t" k "\t-\t" cn[k]
  for (k in cu) print "COUNT\tUNIX\t" k "\t-\t" cu[k]
  print "SUMMARY\texecs\t" nexec
  print "SUMMARY\tsuites\t" nsuites
  print "SUMMARY\tinet_lines\t" ninet
  print "SUMMARY\tother_family_lines\t" nfam
  print "SUMMARY\treal_client_execs\t" nreal
  print "SUMMARY\tnetlink_lines\t" nnl
  print "SUMMARY\tunix_lines\t" nux
  print "SUMMARY\tstub_dirs\t" ns
  print "SUMMARY\tbad_stub_dirs\t" nbad
  print "SUMMARY\tfd_execs\t" nfd
}
