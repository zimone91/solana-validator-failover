# Changelog

All notable changes are documented here. Versions follow the project's internal `v0.6.x` line;
`v0.6.9` is the first public release.

## Unreleased (v0.7 line)

- **Block 5.3 — the `failover arm` ceremony** (`failover-arm.sh`, repo root: SHIPPABLE — in
  SHA256SUMS, shellcheck, and the parse gate — but EXECUTED only at the v0.7 rollout,
  upgrade-then-arm, per the release checklist; nothing in this repository runs it). Structure:
  preconditions → probe → install → verify → token, every precondition refusing with the exact
  fix printed. Preconditions: self-v0.7 patsub-guard check on the installed daemons (the
  rev3.2 release condition self-enforced — the ceremony IS the upgrade-then-arm checkpoint);
  socat hard-required (§2.6, the SOLE armed transport — no fallback); busybox-flock `-w` probe
  (reviewer 5.2-GO: detected AT ARM and said aloud — WARN, not refuse); **unit `--identity`
  verification** (the 5.1 proc-gone residual discharged: real-arm REFUSES unless the validator
  unit's ExecStart carries the unstaked keypair; page-only proceeds with WARN; frankendancer
  states the stop-only posture and skips); the §2.3 one-arm-state announcement. The
  §2.1-rev2.1 end-to-end PROBE: a transient Type=notify pair (new `arm-probe` skeletons)
  rendered into ARM_RUNTIME_DIR proves stopped-petting → watchdog → `failed` → OnFailure
  ON THIS HOST before any armed state exists — the one READY pet that starts it IS the §2.6
  socat self-test; no marker → refuse. Install renders the monitor (role fill) + exactly ONE
  fence unit (page-only XOR real per DRY_RUN, stale sibling removed — the arm is the alignment
  mechanism), places the fence bodies (the ceremony is the only placer), **retires the legacy
  monitor before enabling the new one** (fix round 2 blocker: the wizards' pre-fence units
  `solana-failover.service` / `solana-failover-standby.service` — the full set either wizard
  writes or enables — are detected, stopped, disabled, and the retirement VERIFIED via
  `is-active`/`is-enabled` re-reads; any failure → `REFUSE[INSTALL-legacy]` with the manual
  commands printed, the new monitor NOT enabled, no token; the unit file stays on disk for the
  operator to delete. Two Restart=always monitors on one host share the env + state file and
  race set-identity — one demotes, the other re-takes inside the lockout; the fix is this
  ceremony step, deliberately NOT a daemon-side flock, which would turn the losing notify
  monitor into a never-READY start timeout → OnFailure → REAL fence on a healthy validator),
  enables the monitor (the only `systemctl enable` of a Block-5 unit — supersession of the
  legacy deploy services is an ACTION the ceremony performs, not a plan), never touches
  the validator unit; post-install
  verify re-classifies and must agree (render→verify). The §2.1 pairing token
  (`v0.7|gen=N|watchdog=…|relinquish_bound=…|fence=…|host=…|crc`) bumps a persisted generation
  counter and the arm refuses to complete without printing it. New suite
  `tests/test_arm_ceremony.sh` (48 suites): reds-first, every actuator stubbed, every root in
  mktemp (the hard boundary — no test touches /etc, /run/systemd, or a real systemd),
  refuse-gate mutation controls on every gate, arm↔fence byte-parity on the reused
  unit-discovery helpers.
  The fence's "(the arm ceremony (5.3) must verify …)" comments/marker text now read "verified
  at arm since 5.3" — daemon↔fence byte-parity twins untouched.
  **5.3 panel fix round** (3-lens adversarial panel on the arm ceremony; every fix reds-first,
  every executed attack re-run and shown dead): P1 now requires WATCHDOG CAPABILITY in each
  installed daemon (`_watchdog_active()` + ≥1 `READY=1` + ≥10 `_watchdog_pet` sites, all
  comment-stripped) beside the patsub guard — the panel armed a v0.6.10 daemon whose READY-less
  monitor would have fenced a healthy validator; P4 verifies the KEY, not the path string
  (readlink-resolve, derive the pubkey via the host's `solana-keygen`/`agave-keygen`, compare
  to the env's `UNSTAKED_PUBKEY` — a symlink-to-staked at the configured path now refuses;
  unverifiable refuses too, with the manual command printed and the documented dangerous
  override `ARM_ACCEPT_UNVERIFIED_IDENTITY=1` that WARNs loudly; multiple `--identity` flags:
  the LAST wins, said aloud); the renderer is structural (bash replace, no sed — `&`/`\`/`|`
  paths render byte-exact, the delimiter refusal gone with the sed) with per-file post-render
  content verification and a directory-at-destination refusal; probe markers are file-typed
  with stale-marker announce+clean (the panel's M-A mutation survivor, now killed by a case +
  control) and an unremovable-marker refusal; an un-removable stale fence sibling under REAL
  intent refuses (was WARN — §2.3's one-unit invariant); the generation bump is
  flock-serialized (bounded; absent-flock residual named) and verified to persist as a regular
  file holding the bumped value; the "only enable" claim is scoped to the Block-5 unit set
  everywhere it is printed or written; all five `systemd/*.skel` render sources joined
  SHA256SUMS (integrity artifacts for root-installed units); `tests/run_all.sh` dispatches via
  `"${BASH:-bash}"` (interpreter-drift class closed). Suite 56 → 85 checks, mutation controls
  M1–M10. (5-lens adversarial verification panel; folded into the Block
  5.2 commit — every fix red-first, every panel mutant re-killed, every attack scenario re-run).
  **5.3 fix round 2** (reviewer blockers, both reds observed on a tool-bearing machine —
  docker bash:5.2 with socat/flock/util-linux installed): the arm suite's scenario PATH is now
  `"$STUB_DIR:$TOOLDIR"` with NO system path appended — TOOLDIR is a per-run dir of symlinks
  to the real host binaries for the arm's non-actuator commands (N-is-all by comment-stripped
  grep), so a DELETION stub means the tool resolves NOWHERE; the old appended `/usr/bin:/bin`
  made `STUB_NOSOCAT`/`STUB_NOFLOCK` vacuous exactly where the tools exist (every real
  validator host): with socat installed, (2a) ARMED with a printed pairing token where
  `REFUSE[P2-socat]` was expected (83/85, run_all 47/48 — reproduced, then fixed, then green
  on the same machine; standing non-vacuity tripwires (B6)/(B7) — asserting the exact PATH
  string the runner used (a snapshot at the deletion cases), never a locally rebuilt copy,
  so a runner-side PATH regression turns them red too; the flock-absent case (3c)
  is now exercised unconditionally on every leg). Plus the legacy-monitor retirement above
  (suite (15a–h) + mutation control M11: retire neutered → the dual-monitor arm completes,
  observed), and the `P1-capability` refusal now prints the failing daemon's MEASURED counts
  against the REQUIRED floors instead of static shipped-daemon figures (the old "carry 7 and
  35+" disagreed with the reviewer's count of the same daemons — illustrative numbers drift,
  measurements do not). Suite 85 → 97 checks, controls M1–M11.
  **FF-B1 (false-fence blocker):** the wedged-demote paths now pet their COMPLETED timed-out
  ops — a `timeout` rc 124/137 return IS a completed bounded op (the monitor is alive and
  remediating): the primary's `switch_to_unstaked` rc-124 branches pet BEFORE entering
  `_selffence_hard_stop`, the standby's `give_back_identity` branches pet before
  `_giveback_wedged_escalate`, and the escalate's own identity re-read is petted. Panel's
  measured pet-free stacks: PRIMARY 40 s → 20 s, STANDBY 48 s → 20 s (attack_petgap2 re-run),
  both < WatchdogSec 30 with margin. The N-is-all audit over the whole class (every
  early-return/branch after a ≥ 5 s-bound op) closed 11 more sites: primary
  `tier1_check_delinquency` / `tier1_get_vote_latency` ×2 / `_check_rpc_delinquency` /
  `_check_single_rpc` ×3, standby `tier1_check_local_health` / `local_check_delinquency` /
  `tier2_check_delinquency` / `tier3_confirm_delinquency` (capture-rc-then-pet idiom), and
  converted every loop-top pet (liveness sampler, alpenglow fetch, collision/gossip/relinquish
  loops, both daemons) to post-op placement so the loops' final reads are covered on every
  exit. **FF-B2:** the tiered checks' unreachable paths pet their completed 15 s curls —
  both-externals-hanging confirm: 30 s/0 pets → max gap 15 s (re-run). **FF-B3 + HOLD-B1:**
  all 11 main-loop/HOLD `sleep` sites route through `_watchdog_sleep` (chunked ≤ 10 s + a pet
  per chunk under the armed unit; byte-identical plain sleep un-armed — asserted): ANY legal
  `CHECK_INTERVAL`/`TURBO_INTERVAL` is now armed-safe — no interval ceiling needed; the A3
  comment no longer leans on the 3–5 s defaults, and it names the primary's opt-in
  MAX_VOTE_LATENCY>0 term (2 × 10 s, per-op petted). **FF nits:** the wait loop re-sends
  EXTEND immediately BEFORE and AFTER the one-time H3 alert (the composed flap+alert 72 s
  EXTEND→EXTEND trace closes to 52/33 s < 60, re-run); armed-only throttled re-page while the
  pre-READY wait extends ("validator still in startup after Ns; protection not yet active" —
  un-armed hosts unchanged); the monitor skel's WatchdogSec comment now carries the honest
  ≈ 22 s max-gap figure (the "~10–15 s cadence, tolerates one lost datagram" claim
  contradicted the daemons' own derivation) and pins `TimeoutStartSec=90s` (= the systemd
  default) so the part-D no-EXTEND-sent bound is stated where it binds; the honest pet
  call-site count is pinned structurally in the suite: 34 per-op/end-of-cycle call sites in
  the primary, 35 in the standby (`grep -cE '^[[:space:]]*_watchdog_pet\b'` minus the
  definition line — the earlier "36 per daemon" figure counted the definition + a comment).
  **HOLD fixes:** `_consume_fence_markers` now runs FIRST in `startup_checks` — before EVERY
  fatal gate (binary/keypair/one-arm/numeric/vote-liveness), so a fenced node parks in HOLD
  instead of looping a fatal exit-1 through OnFailure → fence-breaker → restart (suite-driven,
  both daemons; the HOLD loop sanitizes CHECK_INTERVAL locally since numeric validation now
  runs later); the fence script's HOLD comments and `systemd/README.md` now state the
  IMPLEMENTED HOLD (READY=1 + continuous pets + throttled re-page — explicitly superseding
  addendum §2.2's original "no watchdog re-arm, one CRITICAL page, quiet" wording, with both
  counterfactual directions traced in README), and the daemons' HOLD comment carries the same
  supersession line; the stale-marker branch re-checks existence before paging (a marker
  cleared mid-check → silent normal startup, no lying "stale marker present" page).
  **Comment-truth:** `systemd/README.md` transport section rewritten to the implemented truth
  (socat-CHILD datagrams + `MAINPID=$$` payload claim + `NotifyAccess=all`; the old
  "main-PID datagrams"/"NotifyAccess=main" wording would produce the functionally-dead unit
  class). **Test honesty (killing the panel's four surviving mutants):** `drive_hold` stubs
  17+ monitoring/takeover entrypoints as bait and case (7) asserts ZERO fire in HOLD (M6a/M6b
  now red); a primary drive-cycle case covers the primary's first-clean-cycle fenced-demoted
  clear (M7-primary now red); end-of-cycle pet CALL-line counts (5/4) and TOTAL pet call-site
  counts (35/36 incl. definitions) are pinned structurally — a call deleted or `:`-neutered
  under its kept comment trips the pin (the M1b class now red); a full non-delay cycle with
  the №8 lever ON asserts ZERO voter adds (M11x now red); the suite's inertness grep widened
  to socat|NOTIFY_SOCKET|WATCHDOG_USEC|READY=1|WATCHDOG=1|EXTEND_TIMEOUT_USEC in code outside
  the [watchdog] block; the red-log provenance note records that the archived red predates the
  final suite revision (identical per-case outcome set re-verified). The primary's dead-but-
  parity-kept `boolf` drift branch is annotated (twin discipline over dead-code purity).
  Suite grows 44 → 60 checks; the panel's M1–M11x battery re-run post-fix: 15/15 mutants red.
- **Block 5.2 — monitor-side fence integration** (installed by nothing; structurally inert on
  every host today — every mechanism activates only under the Block-5 systemd unit, i.e. when
  PID 1 exports `NOTIFY_SOCKET`+`WATCHDOG_USEC`, or when a fence outcome marker exists; both
  asserted by the new suite incl. a zero-inertness grep-proof). **Transport (§2.6):** sd_notify
  datagrams via the research record's `socat -t0` pattern with the `MAINPID=$$` claim; the
  monitor unit skeleton moves to `NotifyAccess=all` (honesty fix: socat is a forked child — its
  credentials are not the main PID's). **Per-op pets (§5):** `WATCHDOG=1` after every bounded
  network/admin op completes plus an end-of-cycle pet; every ≥ 15 s AND every main-loop/HOLD
  inter-cycle sleep is chunked through `_watchdog_sleep` (fix round); the WatchdogSec=30
  arithmetic is derived in-code (max inter-pet gap ≈ 22 s at zero datagram loss;
  the one-lost-datagram residual across a maximal 20 s op is named, not hidden); a pet NEVER
  fires between an op's start and completion — wedge detection is the pets' absence, and a
  timeout RETURN (rc 124/137) counts as completion (fix round).
  **Startup (§2.2 B):** `READY=1` only after the first successful identity read; pre-READY the
  wait loop sends `EXTEND_TIMEOUT_USEC=60000000` (2× the iteration's worst-case bound, derived)
  each iteration WHILE the validator is positively in startup/replay — process alive AND the
  fence's own startup-evidence probe, carried into the daemons as a byte-identical twin, so
  daemon and fence share ONE evidence definition. **Markers (§2.2 C):** same-boot
  `fenced-stopped` → HOLD (CRITICAL page + re-page per `ALERT_THROTTLE`, READY+pets — the one
  documented B1 exception — zero monitoring logic; the operator's clear → exit 0 for a clean
  restart under Restart=no); stale (pre-boot) → page once + monitor normally (same-boot
  semantics at both ends); `fenced-demoted` (any age) → normal demoted monitoring, marker
  cleared on the first clean cycle; the page-only twin's marker is ignored;
  `_marker_same_boot` is a daemon↔fence byte-parity twin (suite-visible divergence).
  **Part D:** the third-branch dispatch loop analyzed at the extension site — the shared
  evidence definition closes it (stable no-evidence terminates on the SECOND dispatch, driven
  as a two-dispatch test; the flap case is rate-bounded and loud, never stops the validator,
  and deliberately gets no counter). **№8 (STANDBY only, DEFAULT-OFF, live-test-gated):**
  `PREWARM_VOTER_ADD=false` — when true, ONE bounded `authorized-voter add` per episode inside
  the takeover delay window + `remove-all` hygiene on episode reset (never while holding
  staked); off/DRY_RUN = zero admin calls (asserted); drift-announced via the new `boolf`
  direction with the live-test-gate wording. New suite
  `tests/test_monitor_fence_integration.sh` (44 checks; 60 after the fix round — mutation
  controls, structural pins, twin parity); suite
  count 46 → 47; CI wall-clock pins 19→20/20→21 (the one new site per daemon is the
  `_marker_same_boot` twin — mtime/boot-epoch comparisons are inherently wall-clock, not a
  timer); `test_demote_killafter` census 8 → 9 (the bounded startup-evidence probe).
- **Block 5.1 panel fix round** (5-lens adversarial verification panel; blockers B1/B2/B3 +
  every nit — folded into the Block 5.1 commit). **B1 (double-sign blocker):** the crash-loop
  breaker now honors a `fenced-stopped` marker only if it is from the SAME BOOT (boot epoch =
  now − uptime via `${FENCE_PROC_ROOT:-/proc}/uptime`; pre-boot mtime with a 60 s slack toward
  stale, or unreadable/garbage uptime ⇒ STALE → WARN + page + fence normally) — a stale marker
  surviving an operator's staked recovery must never leave a genuine new incident unfenced,
  unmonitored, and paged journal-only; and a FRESH refusal now also restarts the monitor (dead
  in `failed` at OnFailure dispatch — the restart is what delivers the CRITICAL page and re-arms
  monitoring). The §2.5 proc-gone demote excuse now requires an ACCEPTED (rc 0) set-identity: a
  FAILED set-identity with the process gone goes to the stop-fallback (whose `systemctl stop`
  also cancels a Restart=always resurrection), and the two `fenced-demoted` reasons are truthful
  and DISTINCT — "ladder verified by N sustained unstaked reads" vs the proc-gone outcome naming
  the ACCEPTED set-identity and the unit `--identity` invariant this script cannot verify (arm
  ceremony (5.3) obligation). **B2 (availability blocker):** every monitor restart is
  `systemctl restart --no-block` — the monitor is `Type=notify` with READY gated on its first
  identity read (minutes away mid-replay), so a job-blocking 15 s restart deterministically
  produced a false CRITICAL "UNMONITORED; intervene" on a healthy node (a killed wait is not a
  canceled job); rc now means ENQUEUE outcome only. Also: single-instance `flock -n` guard
  (loser logs + exits 0; skipped where flock is absent — macOS harness only); marker precedence
  enforced in `_write_marker` (never `fenced-demoted` while `fenced-stopped` exists; a stopped
  write supersedes the demoted sibling); per-rung-sized watchdog pets (the repoll rung's real
  ~104 s bound, stop-path pets) made REAL by the fence unit skeleton's new `NotifyAccess=all` +
  derived `TimeoutStartSec=300` (term-by-term arithmetic in the skel; pets = belt, budget =
  suspenders, failure direction stated honestly — a cut fence is a silent half-fence, not
  "louder"); word-anchored startup token ("restarting" is NOT startup evidence); the
  third-branch fence↔monitor loop named honestly in a comment (loud, nothing stopped; breaker
  is 5.2 monitor-side); frankendancer stop-only posture documented (header +
  `systemd/README.md` — v0.7 limitation, reviewer-packet item). **B3 (test honesty):**
  `tests/test_fence_script.sh` grows 21 → 41 checks — B1 stale/fresh/unreadable-uptime cases,
  B2 enqueue semantics (with a slow-READY systemctl model), and a killer for every panel
  mutation that had survived: unreadable-re-poll-with-live-process abort, stop-UNCONFIRMED
  loudest-page path, delayed re-verify vs a Restart=always resurrection (per-call `proc.seq`
  pgrep model), wedged-BARRIER remove-all not excused by proc-gone, `UNSTAKED_KEYPAIR` guard,
  shipped-default re-poll (5, no env override) + floor clamp 0→1, twin/flock lock, marker
  precedence, and truthful marker reasons. The SIGTERM/SIGKILL kill invocations remain
  structurally unobservable (bash-builtin `kill`; ESRCH pid 2147483647 is the single
  containment — named in the suite header as the recorded coverage hole). `install.sh` joined
  the CI shellcheck list and `run_all.sh`'s parse gate (pre-existing gap the panel found: it
  was checksummed but never linted/parsed).

- **Block 5.1 — the fence script PROPER** (`systemd/failover-fence.sh` promoted from the
  skeleton; every `# BLOCK5-PROPER:` seam filled, structure and failure directions kept). The
  §2.2 identity verdict grows its three real branches: (a) staked/unknown → the §2.5 ladder —
  `authorized-voter remove-all` → `set-identity <unstaked>` → `remove-all` AGAIN (the
  late-voter-add barrier) → SUSTAINED identity re-poll (`FENCE_REPOLL_SECS`, provisional 5 —
  an EMPIRICAL floor Block 10 sets by measurement, [rev3/№5]) → `fenced-demoted`;
  (b) already unstaked → marker + INFO page, zero admin mutations; (c) unreadable + unit
  active + startup-phase evidence → restart monitor, NO stop (the reboot-brick fix);
  unreadable without evidence → stop. Every admin call bounded (`timeout -k 5`, the daemons'
  H4/B1 idiom; wedge rc 124/137 → stop-fallback). Stop-fallback ports the H2
  stop → mask --runtime → SIGTERM/SIGKILL → verify + delayed re-verify discipline; an
  unverifiable stop still writes `fenced-stopped` and exits 1 — **claim MORE fencing than
  proven, never less** (the monitor's HOLD path treats the marker as authoritative).
  `VALIDATOR_UNIT` comes from the validator's cgroup (v2 `0::` line, v1 `systemd:` fallback;
  configured env wins; no unit determinable → no guessed stop, marker + exit 1) — kills the
  hard-coded `solana.service`. Crash-loop breaker: a pre-existing `fenced-stopped` marker →
  page + exit 0, zero actuator calls (`fenced-demoted` allows the idempotent re-run). Markers
  live as files in `FENCE_MARKER_DIR` (default `/var/lib/solana-failover`), ISO timestamp +
  reason, atomic tmp+mv; the monitor consumes them in slice 5.2. NO network anywhere in the
  fence (pages are journal lines — a fence that waits on Telegram can hang mid-demote). Plus
  the §2.3 twin `systemd/failover-fence-page-only.sh` (structural DRY_RUN: marker + CRITICAL
  journal line, zero mutation tokens outside comments — grep-assertable). **Ship-surface
  promotion, deliberate:** both scripts enter `SHA256SUMS`, the CI shellcheck list, and
  `run_all.sh`'s parse gate; the `.service.skel` units stay skeletons — **still nothing
  installs anything anywhere**; execution begins only at the v0.7 rollout (`failover arm`,
  upgrade-then-arm). New suite `tests/test_fence_script.sh` (46 suites): drives the real
  script as a subprocess behind a fully mocked PATH (scriptable `agave-validator`/`systemctl`/
  `pgrep`/`timeout` stubs, ordered event log; no real systemctl can run), covering the exact
  ladder order (with a swap-mutation control), the stale-write re-poll abort, all three
  verdict branches, both breaker sides, unit detection (env/v2/v1/neither), and the page-only
  twin's inertness.

- **Block 5 skeleton — systemd unit skeletons + the ONE-arm-state refusal (№1)**. `systemd/` now
  carries the v0.7 fence topology as repo-only `.skel` files: the monitor under the native
  watchdog (`Type=notify`, `WatchdogSec=30`, `NotifyAccess=main` with socat main-PID pets as the
  sole armed transport §2.6, and the load-bearing R8 pair `Restart=no` +
  `StartLimitIntervalSec=0` so the FIRST missed pet reaches terminal `failed` and dispatches
  `OnFailure=`), the REAL fence unit (§2.5 stale-write barrier ladder mapped verbatim; §2.2
  third identity branch; the two outcome markers `fenced-stopped`/`fenced-demoted`), the
  PAGE-ONLY fence unit (§2.3 structural DRY_RUN — arm-state IS which of the two fence units is
  installed), and the fence script skeleton (ladder structure + failure directions real now,
  every branch labeled toward stop/page; mechanism behind `# BLOCK5-PROPER:` seams that page +
  fail — executing it can never stop, mask, kill, or demote anything). **NOTHING INSTALLS
  THESE**: no code path writes `/etc/systemd/system` or runs `systemctl` for them; they are
  outside `SHA256SUMS` and every CI ship glob (the `.sh.skel` is shellcheck-LINTED only).
  Installation is the future `failover arm` ceremony, gated on the Block-5 entry blocker (all
  four nodes confirmed on v0.6.10+). Both daemons gain the §2.3 [rev3/№1] startup check
  (byte-identical `_fence_unit_state` + `_enforce_one_arm_state`): `DRY_RUN=true` + REAL fence
  unit installed → **refuse to start** + CRITICAL page naming both alignment paths (re-run
  `failover arm` to install the page-only fence, or set `DRY_RUN=false` if arming was intended);
  `DRY_RUN=false` + page-only → WARN (v0.6.x behavior, the §2.3 third row — acceptable);
  classification is pure `test -e` on the two canonical unit paths (BOTH present = `real`, fail
  toward the refusal; no systemctl on the startup path), and `none` — no fence unit exists,
  every host today — keeps the check **structurally inert**. No new env knobs. New suite
  `tests/test_one_arm_state.sh` (45 suites).

- **Alpenglow feature-gate tripwire** (both daemons, pre-Block-4 №9): agave 4.2.1 ships the entire
  votor/BLS machinery dormant, runtime-gated on the on-chain `alpenglow` feature — on activation
  `set-identity` demands a vote-history file by default (a direct hit on the deliberate
  no-tower-transfer design) and the whole lastVote observation model needs re-derivation. The
  daemons now probe the feature-gate account (`getAccountInfo` on the agave v4.2.1 feature id,
  TIER2→TIER3, read-only) every `ALPENGLOW_GATE_CHECK_HOURS` (default 6, 0 = off,
  drift-announced; first check immediate) and **page the moment the gate shows pending/active** —
  `pending` at WARN (epoch-boundary slack), `active` on the CRITICAL channel (set-identity then
  fails by default without a vote-history file: the promote path may be inert — the
  UNKNOWN-IDENTITY class and channel) — with the instruction to re-run the 4.2 audit (Blocks 5–6
  constants freeze until it passes). The last known state persists in the state file; "unknown"
  (both externals unusable) never overwrites it, logs at WARN, retries on a **900 s floor**
  instead of waiting out the full cadence, and **pages after 4 consecutive failures** (repeating
  per `ALERT_THROTTLE`) — a tripwire whose failure mode is silence would be a dead gate that
  looks alive. The companion gate `alpenglow_fast_leader_handover` is deliberately NOT watched —
  source-verified (one usage, `replay_stage.rs:1611`, subordinate to the main migration status;
  gates neither set-identity nor observation). Page-only — the probe sits at the top of the main
  loop, never inside a takeover/recovery/verdict path.

- **Unstaked-key uniqueness enforced** (STANDBY, pre-Block-4 №3): the relinquish-proof fence (G2)
  and the Option-A fast path both read "a live publisher holds this unstaked key on box X" as
  "box X cannot sign staked votes" — sound only while each unstaked key belongs to ONE host.
  README always required a unique unstaked keypair per node; startup now refuses (same fatal class
  as the staked==unstaked refusal) when the node's own `UNSTAKED_PUBKEY` appears in
  `PRIMARY_UNSTAKED_PUBKEY` (membership over the space-separated list).

- **CI drift-counter pins** (pre-Block-4 №10): the `facts` job now pins the per-daemon counts of
  `date +%s` (wall-clock) and `${var//…}` (patsub) sites the same way it pins the suite count —
  growth = a new wall-clock/patsub site = review-stop (addendum §3b.4); a legitimate change
  updates the pin in the same diff.

- **Act-then-alert (A8) + fresh-proof re-check** (both daemons): the pre-take 🔍 alert is deleted —
  a network call between the verdict and the mutation (the tier summary is not lost: it travels
  verbatim inside the reason of the TOOK STAKED ✅ / WOULD TAKE / TAKEOVER FAILED alert) — and the
  alert now strictly follows the action. Accepted tradeoff, not a free win: the first page about a
  take now follows the mutation, so a process death in the fraction of a second between them leaves
  the take only in the local log (unsent); accepted because the alternative held ~10 s of blocking
  network before a safety-critical mutation on a ~20 s-stale proof, and a dead monitor is covered
  by the dead-man's switch. Immediately before `set-identity`, a **fresh-proof
  re-check** (one fresh sample compared against the episode's pinned baseline — sound because the
  frozen path never re-bases the pin, so the pair interval is pin→now) must re-confirm FROZEN:
  VOTING or cannot-determine **aborts** the take, and **zero network calls** sit between the
  re-check and `set-identity`. An abort is a withdrawn verdict, not a failed take: **no cooldown is
  set**, no episode state is dropped — the re-check leaves exactly the state the normal fence paths
  would, and pacing comes from the normal re-anchor/re-pin (on the PRIMARY a VOTING abort is paced
  by the observed-span floor + recovery ladder — its recovery anchor never read the liveness
  re-anchor, same as the in-gate design). Abort pages throttle per `ALERT_THROTTLE` (first page
  immediate — a flipping vantage would otherwise page every ~20 s indefinitely); the per-event log
  lines are never throttled. DRY_RUN mirrors the live decision (an aborted take reports the abort,
  never "WOULD TAKE"). Extends the demote path's "safety action FIRST" rule (N2) to the take path.

- **Observed life restarts the observed span**: `_liveness_obs_since` now re-pins at every VOTING
  verdict, so the observation-span floor's claim is self-contained at any config (measured:
  `VOTE_LIVENESS_MIN_SPAN=100` with one observed vote, take moved t0+120 → t0+160; inert at the
  shipped defaults — the N3 re-anchor's 60s exceeds the 40s floor).

- **Docs honesty**: README / SAFETY / SPLIT-BRAIN-RESIDUAL now name the availability-side outcome
  explicitly — with blind or flapping externals the takeover holds **indefinitely** (a measured
  outcome, not a theoretical one) and the operator is paged (`TAKEOVER_STARVATION_ALERT_SECS`);
  "fails safe" there means "does not act, loudly".

- **Blindness counts as life**: any interval in which no external provider yields an observation
  restarts the takeover countdown in full — the 60 s window can no longer collapse to ~15 s across
  an external-RPC outage. A new `VOTE_LIVENESS_MIN_SPAN` floor (default 40 s, 0 = off) additionally
  requires the frozen verdict to rest on the **episode's** actually-observed span (since the
  episode's first successful observation, or the end of the last blind cycle) — a measure that
  converges under provider-flip storms; no-op on the normal path and after any blindness. (The
  first cut measured the span from the re-basable pair pin and was measured non-convergent for
  flip periods strictly between `VOTE_LIVENESS_MIN_INTERVAL` and the floor (10–40 s exclusive;
  flip 20 s / 35 s: no take in 3600 s, while 10 s and 60 s converged) — it never shipped.)

- **Takeover starvation page** (STANDBY): a delinquency episode held
  `TAKEOVER_STARVATION_ALERT_SECS` (default 300, 0 = off) with no takeover now pages, repeating per
  `ALERT_THROTTLE`, with per-episode hold diagnostics (blind cycles / provider flips / span-floor
  holds) and a resolution notice when the episode closes. Page-only — changes no verdict, triggers
  no action — and anchored to `FIRST_DELINQUENT_TIME` by design (the takeover anchor is exactly
  what starvation moves; an alarm anchored to it would starve with the takeover).

- **Upgrade note (PRIMARY only):** envs generated by installers ≤ v0.6.10 carry
  `VOTE_LIVENESS_EPSILON=2`, which overrides the new default of 0 on the primary's rpc-recovery
  fence until the wizard is re-run (in-place daemon upgrades don't touch the env). The STANDBY —
  the double-sign-critical side — never had the knob written and inherits 0 automatically.

- **Safety timers are monotonic** (`/proc/uptime`); the state file gains a `BOOT_ID` line and
  `*_MONO` twins for every persisted safety stamp. **Rollback is safe by construction:** the legacy
  keys keep wall-clock values (derived at each save), so a daemon ≤ v0.6.10 reading a v0.7-format
  file computes correct elapsed times — including the post-self-fence re-take lockout — with no
  operator steps. Upgrading forward needs nothing either: on an old-format file, lockouts and
  cooldowns re-hold in full (fail toward held).

## v0.6.10 — hotfix: alert delivery broken on bash 5.2 hosts (Ubuntu 24.04 / Debian 12)

**One-line fix per script, zero logic changes.** bash 5.2 enables `patsub_replacement` by default,
which makes `&` (and `\`) special in the replacement side of `${var//pat/repl}`. On bash 5.2 hosts
two alert surfaces were affected:

- **Telegram — broken.** `_html_escape` emitted `<lt;`/`>gt;` instead of `&lt;`/`&gt;`; Telegram
  rejects the malformed HTML, so CRITICAL pages (demote/takeover/self-fence/hard-stop) silently
  failed to send and the pending-alert retry could never succeed.
- **Custom `WEBHOOK_BODY` templates — mangled.** A `&` in a substituted value became the literal
  placeholder text and `\\` collapsed to `\`, corrupting the payload (possibly into invalid JSON).

**Not affected:** ntfy.sh push (HTTP headers + raw body via `_header_sanitize`) and the default
JSON webhook (built with `jq -nc --arg`). Failover logic, timers, fences, and the installers'
generated config (`printf '%q'`) are entirely untouched.

The fix — `shopt -u patsub_replacement` at the top of all four scripts — restores the bash-3.2
substitution semantics this codebase is written against, and is a no-op on bash ≤ 5.1 (which is why
the bug never surfaced on the live-test stack). Found by running the full suite under both
interpreters (macOS bash 3.2 **and** Ubuntu 24.04 bash 5.2); both now pass 36/36.

## v0.6.9 — first public release

Automatic staked-identity failover for Solana validators — the holder steps down before a spare
steps up, and ambiguity resolves toward nobody voting. Hardened across multiple internal audit
rounds and validated with live failover tests on a testnet stack (isolation, egress-only partition,
promoted-standby self-fence, holder restart).

**Safety**
- Cross-node timing invariant: holder self-fences (~30s) before the spare takes (60s), with an
  authoritative vote-liveness fence. Unsafe hand-edited timing refuses to start.
- Role-aware timing floors for STANDBY vs BACKUP (a BACKUP must also outwait the STANDBY's takeover
  becoming externally visible).
- Promoted-STANDBY self-fence with a re-take lockout; wedged-`set-identity` escalation to a verified
  hard stop; persisted self-fence baseline with evidence-gated restore across monitor restarts.
- Egress-only ("votes not landing") self-fence; frozen-slot and dead-RPC self-fence; sliding-window
  delinquency detection; identity-collision detector (page-only).

**Installer & UX**
- Interactive `deploy-failover.sh` / `deploy-failover-standby.sh` with Simple / Advanced modes,
  safe-by-default presets, and a DRY_RUN-first flow.

**Notifications**
- Telegram + ntfy.sh push + external dead-man's-switch watchdog.

**Testing**
- 36 test suites (parse-clean on bash 3.2+); each safety fix ships with a non-vacuous control.
