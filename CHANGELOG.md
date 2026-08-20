# Changelog

All notable changes are documented here. Versions follow the project's internal `v0.6.x` line;
`v0.6.9` is the first public release.

## Unreleased (v0.7 line)

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
