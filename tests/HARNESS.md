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
  census flags or pins them) and a shell's `-c` string or stdin ((1a) and (7g) flag a shell run as a command, directly
  or behind timeout / env / command / nohup / nice / setsid / xargs / exec — not behind another wrapper, nor code an
  interpreter runs from a string, such as awk's `system()`); a here-document opened inside a here-document body's
  `$( )`; a backtick nested in backticks; aliases.
- `dump_freshness` — **the sole reader of the freshness triple**
  (`_liveness_first_provider` / `_liveness_obs_since` / `_last_blind_end`) in suites; run_all
  stage (3) enforces this mechanically (a `$`-dereference in any suite = red). Priming WRITES in
  fixtures are fine. Read fields via `field "$(dump_freshness)" <vantage|observed_since|blind_until>`.

## The net guard (no suite reaches a network client through `PATH`)

`tests/lib/harness.sh` puts a directory of logging stand-ins FIRST in `PATH` for every suite that sources it:

- `curl` answers rc 7 (a refused connection — what an unanswered local read returns) and logs the call; the suite's
  RESULTS banner counts the calls. The suites shadow the daemons' reads as shell functions; only an unshadowed
  caller (or `command curl`) reaches the binary.
- every client in its `HARNESS_NET_CLIENTS` list (`ping`, `ping6`, `nc`, `ncat`, `netcat`, `wget`, `dig`, `host`,
  `nslookup`, `drill`, `getent`, `ssh`, `scp`, `sftp`, `telnet`, `traceroute`, `tftp`, `ftp`, `whois`, `nmap`,
  `openssl`, `rsync`, `git`) fails (rc 2) and logs the call, and the suite FAILS.

`run_all.sh` runs every suite — `test_v058_regression` included, which does not source the harness — with the same
failing clients, `curl` failing too, first in `PATH`, and the suite's own log in `HARNESS_NETGUARD_LOG` (the harness's
stand-ins write there too); stage (4) FAILS when any suite's log is not empty, naming the suite and its calls. A suite
whose world runs a daemon path that reaches a client stubs the client in that world (the precedent:
`test_elapsed_provider`'s m5 world stubs `ping`; before fix round 6 that world — the primary's real `check_internet`
and heartbeat summary — ran the host's `ping` 126–135 times a run).

LIMIT: the guard is PATH-based. It does not see an absolute path (`/usr/bin/curl`, `/sbin/ping`), a `PATH` a suite
builds without it (the arm suites' `env -i PATH="$STUB_DIR:$TOOLDIR"` scenarios), a client outside the list, or an
interpreter's own socket. `socat` and the interpreters are left out of the list on purpose (the notify socket is a
UNIX socket; `test_primary_self_fence` reads a clock through perl; `test_arm_ceremony` finds python3 and perl
through `PATH` and provisions them to its scenarios as removal tools).

## Deliberately NOT migrated (and why — decided, not deferred)

- `test_v058_regression.sh` — fully self-contained by design: INVERTED results semantics (its
  FAIL counter counts *reproduced v0.5.8 bugs*; it exits 0 when FAIL ≥ 2). The lib's
  `results_banner` would flip its meaning. Its success marker is `🐞`, invisible to the ❌
  cross-check on purpose.
- `test_unknown_identity_alert.sh` — sources main-loop regions repeatedly in the top-level shell
  (no function boundary); re-anchoring it means rewriting it, not migrating it. Only ok/bad+paths
  come from the lib.
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
