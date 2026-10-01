# The test harness — contract and honest inventory (v0.7 Block 4)

`tests/lib/harness.sh` is the shared seam harness. This page is the contract a suite author needs
and the honest list of what deliberately stayed OUTSIDE the harness — recorded so nothing here is
a surprise later. (Design record: the Block-4 seam map in the project's private planning tree;
the contract lines below are self-contained.)

## The ❌ contract (run_all's printed-FAIL cross-check)

**❌ is reserved for failures in the output the SUITE writes.** `run_all.sh` cross-checks every
suite: printing any `❌` line while exiting 0 = FAILED (`printed-FAIL-but-exit-0`), and the
offending lines are printed for diagnosis. Two consequences:

1. A suite that reports a NON-failure must use a different marker — the precedent is
   `test_v058_regression.sh`, whose reproduced historical bugs are that suite's *success* and are
   marked `🐞 BUG CONFIRMED`.
2. **The daemons under test also print ❌ — on healthy paths — and must never reach a suite's
   stdout raw.** If the cross-check shows you a daemon line, stub that suite's log/alert sinks;
   never suppress the suite's own output (that would blind the suite — the opposite of the fix).
   The daemon-side ❌ census (source grep, both daemons, at Block 4.4):

   | site | line | healthy path? |
   |---|---|---|
   | primary:944 | `alert_info "🔍 3-tier: LOCAL ✅ ALCHEMY ✅ PUBLIC ❌ → switching…"` | yes — detector working |
   | primary:955 | `log_warn "❌ FALSE POSITIVE: Local delinquent but Alchemy says OK"` | yes — detector working |
   | primary:973 | `log_warn "❌ FALSE POSITIVE: Local delinquent, Alchemy down, PUBLIC says OK"` | yes — detector working |
   | primary:974 | `alert_info "🔍 False positive: … PUBLIC ❌ → reset"` | yes — detector working |
   | primary:1016 | `log_warn "❌ Latency false positive: …"` | yes — detector working |
   | primary:1772 | `alert … "SWITCH TO UNSTAKED FAILED ❌"` | failure path |
   | primary:1834 | `alert … "RECOVERY FAILED ❌"` | failure path |
   | primary:1893 | (comment only) | — |
   | standby:2130 | `alert … "TAKEOVER FAILED ❌"` | failure path |
   | standby:2201 | `alert … "GIVE BACK FAILED ❌"` | failure path |

   Line numbers drift with the daemons; re-derive with `grep -n "❌" solana-*-failover.sh` before
   relying on them. (This census exists because the cross-check went bare-❌ in 4.3; the T-b
   banner in `test_standby_take_timeout` was the first leak of this class, found by a live-output
   census — the daemon sites above are the *surface*, found only by a source census. Both
   censuses, always: live output answers "what leaks today", source answers "what can leak
   tomorrow".)

## The loud-refusal helpers (a control that cannot silently no-op)

- `mutate <in> <sed-expr> <out>` / `mutate_filter <in> <out> <cmd…>` — FAIL the suite if the
  mutation changed nothing (a moved anchor otherwise leaves the control green for the wrong
  reason). ALL daemon-mutation controls go through these — six at the time of writing; before
  adding or migrating "all N" of anything, re-derive N by grep (enumeration is always incomplete;
  this list was four, then five, then six — each extension found by grep, not memory).
- `extract_twin <start> <end>` — byte-parity extraction from BOTH daemons into `TWIN_P`/`TWIN_S`;
  loud on empty. `extract_region <file> <start> <end>` — single-file, loud on empty, region on
  stdout (❌ to stderr — stdout is usually `$()`-captured).
- `load_seam <script>` — the MAIN-LOOP cut (cached per basename+mtime+size) + source + automatic
  re-application of every registered shim (`harness_shim`); a re-sourced seam gets its fake clock
  back without the suite remembering to.
- `bp_parse <file> <dir>` / `bp_exec` / `bp_xcheck` / `bp_bodies` (v0.7 Block 6.3.1 fix round 5) — **bash's own
  parse** for the structural censuses (`test_own_view` (0a) (0b) (0d) (1a) (7g) (7g-local), `test_arm_ceremony`
  (16h)): the file wrapped as two functions at the MAIN LOOP marker, sourced in `env -i bash` (definitions only —
  nothing in it runs), printed back with `declare -f` (comments gone, one-liners expanded, the `function` keyword
  normalized — outside a `$( )`, which bash 3.2 prints verbatim), and lexed as bash reads that print — a `$((cmd) )` as the command substitution it is, an unquoted
  here-document body's `$( )` and backticks as code (fix round 6) — into definition / command / structure / line /
  here-document / redirection records whose command words carry their quotes and backslashes removed; `bp_xcheck`
  compares the parse with what sourcing the file's executable head leaves defined. LIMIT, named in its header: a
  command word assembled at run time; code inside a string a command runs — eval / trap / `mapfile -C` (the (0d)
  census flags or pins them) and a shell's `-c` string, script or stdin ((1a) and (7g) flag a shell run as a command by
  its word, whatever wraps it: a literal shell word — `sh`, `bash`, `rbash`, `dash`, `ash`, `hush`, `zsh`, `ksh`,
  `ksh93`, `mksh` and the others `bpshell`'s header lists — or busybox's shell applet, followed by anything but only
  `--version` / `--help` — nothing (stdin), any option, a script; an `env -S` / `--split-string` string read as its
  words; `sudo -s` / `-i` — not a shell whose word is assembled at run time, a tool running a shell it picks itself
  (`flock -c`, `su`, `script -c`), nor code an interpreter runs from a string, such as awk's `system()`); a
  here-document opened inside a here-document body's `$( )`; a backtick nested in backticks; aliases. bash 5.2 prints
  an if-condition's here-document after the then-branch's first statement, which the lexer would read as body text:
  `bp_parse` refuses such a print (every parse census red; the daemons use none).
- `dump_freshness` — **the sole reader of the freshness triple**
  (`_liveness_first_provider` / `_liveness_obs_since` / `_last_blind_end`) in suites; run_all
  stage (3) enforces this mechanically (a `$`-dereference in any suite = red). Priming WRITES in
  fixtures are fine. Read fields via `field "$(dump_freshness)" <vantage|observed_since|blind_until>`.

## The net guard (network clients reached through `PATH`)

Network clients reached through `PATH` are caught by run_all's stage (4) on every leg; at the syscall level,
`tests/strace-hermetic.sh` (CI's `strace-hermetic` job, ubuntu-24.04; its header holds the rules) fails on any inet
socket in the whole run — a line's family being its socket's own — and on any other socket family than AF_UNIX and
AF_NETLINK, on an exec of a listed client from outside the run's stand-in and stub directories, on a stub directory
listed outside the run's own temp root, and on a run that does not end (strace still tracing 30 s after run_all has
exited). This section is the `PATH` half.

`tests/lib/harness.sh` puts a directory of logging stand-ins FIRST in `PATH` for every suite that sources it — for
`curl` and for each client on its `HARNESS_NET_CLIENTS` list, the clients this guard stands in for:

- `curl` answers rc 7 (a refused connection — what an unanswered local read returns) and logs the call. It logs only
  to its own suite's RESULTS banner (a count), never to run_all's stage (4): it is the suites' RPC mock, by design.
  The suites shadow the daemons' reads as shell functions; only an unshadowed caller (or `command curl`) reaches the
  binary.
- every client in `HARNESS_NET_CLIENTS` (`ping`, `ping6`, `nc`, `ncat`, `netcat`, `wget`, `dig`, `host`, `nslookup`,
  `drill`, `getent`, `ssh`, `scp`, `sftp`, `telnet`, `traceroute`, `tftp`, `ftp`, `whois`, `nmap`, `openssl`,
  `rsync`, `git`) fails (rc 2) and logs the call, and the suite FAILS (its `results_banner`; every suite that sources
  the harness ends with it).

`run_all.sh` runs every suite — `test_v058_regression` included, which does not source the harness — with its own
directory of failing stand-ins (`curl` failing too) in `PATH`, made for that suite alone, and the suite's own log in
`HARNESS_NETGUARD_LOG` (the harness's client stand-ins write there too; in a suite that sources the harness, the
harness's directory comes first, so `curl` there is the mock above). Each stand-in has its log path written into it,
so a child that keeps a guard directory on its `PATH` still logs, even with its environment cleared
(`env -i PATH="$PATH" …`). A plain `env -i` child does not: it gets the libc or bash default `PATH` and runs the
host's client. Stage (4) reads each suite's log right after the suite and again after the last suite — a call a child
made after its suite's own check is then named with that suite (a child that left the suite's process group: what stays
in the group is stopped when the suite ends) — and removes the stand-ins only after that final read. A suite whose log
is not empty FAILS stage (4), named with its calls; a setup failure FAILS it with its own
reason, named with the suite: no client list readable, a stand-in or log not written, or — checked after each suite and
again at the final read — a suite's log, its stand-in directory or one of its stand-ins GONE (after that, a client the
suite ran went to the host's own). The GREEN line says "no network client reached through PATH". Every stand-in
directory — run_all's, the harness's, and each directory a suite names with `harness_stub_dir` because it holds the
suite's own stub of a listed client (`test_act_then_alert`, `test_proof_gate`, `test_own_view`,
`test_installer_guardrails`) — is written to `HARNESS_STUB_DIRS_LOG` when the strace job sets it: the job counts an exec
of a listed client from a directory on that list as a stand-in's or a stub's, from anywhere else as the REAL client. A
listed directory counts only under the run's own temp root — the job points `TMPDIR` at a fresh directory for the run,
so every `mktemp` lands under it — and one listed from anywhere else (`/etc/alternatives`, `/usr/bin`) is red. A suite
whose world runs a daemon path that reaches a client stubs the client in that world (the precedent:
`test_elapsed_provider`'s m5 world stubs `ping`; before fix round 6 that world — the primary's real `check_internet`
and heartbeat summary — ran the host's `ping` 126–135 times a run).

LIMIT: the guard is PATH-based. Stage (4) does not see the items below; the strace job sees each of them that opens a
socket (it fails on any AF_INET/AF_INET6 syscall from any process of the run, loopback included, and on any other
family than AF_UNIX and AF_NETLINK):

- bash's `/dev/tcp` and `/dev/udp` redirections (no binary runs; CI's facts job also permits them in one test fixture
  only — text a mutant inserts and never runs);
- `command -p <client>`, which searches the default `PATH`;
- a plain `env -i` child (the libc or bash default `PATH`; only `env -i PATH=…` keeps the guard);
- an absolute path (`/usr/bin/curl`, `/sbin/ping`);
- a `PATH` a suite builds without the guard (the arm suites' `env -i PATH="$STUB_DIR:$TOOLDIR"` scenarios);
- a call made after stage (4)'s final read of the logs (a child of the last suite that left its process group);
- an interpreter's own socket;
- `socat` — left out of the list on purpose, with the interpreters (the notify socket is a UNIX socket;
  `test_primary_self_fence` reads a clock through perl; `test_arm_ceremony` finds python3 and perl through `PATH` and
  provisions them to its scenarios as removal tools);
- a client not on the list;
- a suite that truncates its own log or rewrites a stand-in (deliberate: the calls a stand-in logged were failed by it,
  nothing was sent, but this stage cannot name them; a log, a stand-in directory or a stand-in that is GONE is a setup
  failure, above).

The per-suite TIME CAP: `run_all.sh` runs each suite in its own process group under a watchdog; a suite still running
`RUN_ALL_SUITE_CAP` seconds after it started (a whole number, base 10; default 3600 — the slowest suite on the slowest
gate leg measured 1,858 s; CI sizes it per job, in `.github/workflows/ci.yml`) gets SIGTERM and FAILS the run gate,
named. When a suite's main process has ended — by itself or by that TERM — whatever is still in its process group gets
SIGTERM and, 5 s later, SIGKILL, and the run names the suite (`LEFT RUNNING`): no process left in the group outlives
its suite. A process that left the group (its own `set -m`, `setsid`) is not stopped; under the strace job, one that
holds strace past run_all's end is named and stopped by `tests/strace-hermetic.sh`. Each run prints every suite's wall
time and its three slowest against the cap.

## Deliberately NOT migrated (and why — decided, not deferred)

- `test_v058_regression.sh` — fully self-contained by design: INVERTED results semantics (its
  FAIL counter counts *reproduced v0.5.8 bugs*; it exits 0 when FAIL ≥ 2). The lib's
  `results_banner` would flip its meaning. Its success marker is `🐞`, invisible to the ❌
  cross-check on purpose.
- `test_unknown_identity_alert.sh` — sources main-loop regions repeatedly in the top-level shell
  (no function boundary); re-anchoring it means rewriting it, not migrating it. Only ok/bad, paths
  and the closing `results_banner` come from the lib.
- `test_required_fence.sh` — keeps its awk extraction: the region must EXCLUDE its end line (a
  sed range would source-execute `load_state`); it gained the loud-empty check instead.
- `test_alpenglow_tripwire.sh` case (8) parity — keeps its own `-n` guard (already loud).
- `test_demote_killafter.sh` / `test_tower_handling.sh` — structural-only suites; local
  assert_absent/assert_present kept.
- Clock/sink shims that are near-verbatim VARIANTS (not byte-identical) stay suite-local — the
  4.2 census found zero byte-identical sink blocks and one byte-identical clock pair; only
  byte-identical code migrates, variants are honest local state.
- The six fence-prime blocks — census-verified variants (different member sets, one omits the
  liveness priming entirely); not parameterizable by one offset; kept local.
- The `declare -f | sed '1s/…/_real_…/'` rename-to-wrap idiom — not a mutation control (it
  brackets a real body for event logging); out of mutate()'s class.

## Discipline for future migrations (the rules this harness was built under)

1. Mechanical diffs only: suite OUTPUT proven line-identical pre/post (volatile tokens identified
   by a pre1-vs-pre2 double run of the UNMODIFIED suite — mask only what disagrees with itself).
2. Every migrated control re-observed RED on its new mechanism (anchor-break: point the pattern
   at nothing → the loud helper must fail the suite).
3. N-is-all, both censuses: before touching "all N", re-derive N by grep over the tests AND the
   system under test; live output and source answer different questions.
4. bash-3.2-parseable everything (run_all's parse gate covers `tests/lib/` too); suites run on
   macOS bash 3.2 AND Linux bash 5.2 — both legs, every time; three bugs to date were visible on
   only one leg (a re-shim leak, a busybox `stat -f`, a GNU-only sed address).
