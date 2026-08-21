# `systemd/` — v0.7 Block-5 fence scripts (real) + unit skeletons (installed by NOTHING)

**Two kinds of file live here (Block 5.1 + 5.3):**

- **The fence scripts are REAL shippable artifacts** — `failover-fence.sh` (the §2.5
  ladder/§2.2 verdict body, tested by `tests/test_fence_script.sh`) and
  `failover-fence-page-only.sh` (the §2.3 structural-DRY_RUN twin). They are in `SHA256SUMS`,
  the CI shellcheck list, and `run_all.sh`'s parse gate. Shippable is NOT installed: their
  EXECUTION on a host happens only at the v0.7 rollout (`failover arm`, upgrade-then-arm, per
  the release checklist).
- **Every `.service.skel` stays a skeleton — repo-only.** Units are installed ONLY by the
  `failover arm` ceremony (`failover-arm.sh` at the repo root — shipped since Block 5.3,
  EXECUTED only at the rollout; tested by `tests/test_arm_ceremony.sh` with every root in
  mktemp and every actuator stubbed). The monitor + two fence skeletons render into the
  ceremony's `ARM_SYSTEMD_DIR` (default `/etc/systemd/system`); the two `arm-probe` skeletons
  render into `ARM_RUNTIME_DIR` (default `/run/systemd/system` — tmpfs, ephemeral by
  construction) for the §2.1-rev2.1 probe, and are cleaned by the ceremony in the same run.

Nothing in this repository writes to `/etc/systemd/system`, runs `systemctl enable`, or
`daemon-reload`s on behalf of these Block-5 units. (Scoped deliberately: the legacy deploy
scripts DO enable and install the pre-fence `solana-failover` service they ship today —
`deploy-failover.sh`, `deploy-failover-standby.sh` — and are superseded at the v0.7 rollout;
no script other than `failover-arm.sh` and the daemons' classifier constants references any
Block-5 unit name.) The **Block-5 entry blocker** gates the first
real installation: **all four nodes confirmed on v0.6.10+** (the patsub alert-death class —
pre-v0.6.10 daemons on bash 5.2 silently fail to deliver Telegram pages, and the fence's
semantics is "does not act, loudly"). The blocker lifts on host answers, not on code readiness.

## Topology

```
                pets (socat → $NOTIFY_SOCKET — socat-CHILD datagrams carrying a
                MAINPID=$$ payload claim; NotifyAccess=all accepts them; §2.6)
  ┌──────────────────────────────┐  WATCHDOG=1 / EXTEND_TIMEOUT_USEC / READY=1
  │ solana-failover-monitor      │ ───────────────────────────────────────────►  PID 1
  │ (Type=notify, WatchdogSec=30,│                                            (CLOCK_MONOTONIC)
  │  Restart=no +                │ ◄─────────────────────────────────────────────────┘
  │  StartLimitIntervalSec=0)    │   first missed pet → SIGABRT → terminal `failed`
  └──────────────┬───────────────┘
                 │ OnFailure= (fires ONLY on terminal `failed` — the R8 pair above
                 │             is what makes the FIRST miss terminal)
                 ▼
  ┌─────────────────────────────────────────────┐   arm-state IS which of the two
  │ solana-failover-fence.service      (REAL)   │   fence units is installed (§2.3);
  │   — OR —                                    │   the daemons' _fence_unit_state
  │ solana-failover-fence-page-only.service     │   classifies exactly these paths
  └──────────────┬──────────────────────────────┘
                 │ real: §2.5 ladder → marker          page-only: page + marker,
                 │       (or stop-fallback)            mutates NOTHING (§2.3)
                 ▼
        fence.outcome marker ──► restarted monitor:
          fenced-stopped  → HOLD: no monitoring logic, but READY=1 + continuous pets
                            + CRITICAL page re-paged per ALERT_THROTTLE until the
                            operator clears the marker (see "HOLD, as implemented")
          fenced-demoted  → normal demoted-holder monitoring (READY, watchdog re-armed)
          (no marker + §2.2 third branch: startup evidence → pre-READY extension, no stop)
```

## HOLD, as implemented (supersedes addendum §2.2's original wording)

The addendum's original §2.2 described HOLD as "no watchdog re-arm, one CRITICAL page, quiet".
**That wording is superseded** (ratified in the Block 5.2 spec, part C1) — the implemented HOLD
in both daemons' `_consume_fence_markers` is: **no monitoring logic runs**, and the monitor
sends `READY=1` (the ONE documented exception to the READY-after-first-identity-read gate),
**keeps petting**, and **re-pages CRITICAL per `ALERT_THROTTLE`** until the operator clears the
`fenced-stopped` marker (then exits 0 for a clean `Restart=no` restart). Why the original
wording could not ship, both directions traced:

- *No READY:* the unit's start would time out (`TimeoutStartSec`) → `failed` → `OnFailure` →
  the fence dispatches again against an already-fenced node — forever. Worse, the operator's
  marker-clear exit 0 would land pre-READY as a Type=notify "protocol" failure → `OnFailure` →
  the fence re-writes `fenced-stopped`, silently undoing the operator's clear.
- *No pets (once READY):* WatchdogSec fires against a parked, healthy monitor → the same
  re-dispatch loop.
- *Quiet:* a fenced node awaiting a human must not go silent — hence the throttled re-page.

## Where the design sections land

- **§2.2 (BLOCKER-2 — startup & post-fence states)** lands in the **monitor unit + daemons**:
  no `READY=1` until the first successful identity read (sole exception: HOLD, above); pre-READY
  the daemon sends `EXTEND_TIMEOUT_USEC` each cycle while it can positively confirm
  startup/replay (the reboot-brick fix — replaces the rev-1 static `TimeoutStartSec` guess; the
  skel's explicit `TimeoutStartSec=90s` = the systemd default bounds the no-EXTEND-yet window);
  and in the **fence script**: the third identity branch (unreadable + active + startup
  evidence ⇒ page + restart monitor, NO stop) and the two outcome markers.
- **§2.5 (stale-write barrier ladder)** lands in the **fence script**: remove-all →
  set-identity <unstaked> → remove-all AGAIN → SUSTAINED re-poll (EMPIRICAL floor, Block 10
  sets it — provisional, [rev3/№5]) → stop-fallback on any doubt.
- **§2.6 (transport)** lands in the **monitor unit + daemons**: `socat -t0` unit-datagrams to
  `$NOTIFY_SOCKET` are the SOLE armed transport in v0.7. socat is unavoidably a forked CHILD of
  the daemon, so the datagram's SCM_CREDENTIALS are socat's own, NOT the main PID's (the
  pre-257 fork-and-exit attribution race; the pidfd fix is systemd ≥ 257, the fleet ships
  249–255) — therefore the unit sets **`NotifyAccess=all`** (with `NotifyAccess=main` PID 1
  would drop every socat-child datagram: READY never lands, the start times out, a healthy
  monitor is fenced — the "syntactically valid, functionally dead" config class) and every
  payload carries the `MAINPID=$$` claim (see the daemons' `_sd_notify`). `systemd-notify` =
  monitoring-only mode below systemd 257 (the same attribution race).
- **§2.3 (arm-state) [rev3/№1]** lands in the **daemons NOW** (this slice): `_fence_unit_state`
  (none|page-only|real; pure file tests, both-present = real) + the startup refusal on
  `DRY_RUN=true` + real fence unit. Structurally inert wherever no fence unit exists — every
  host today.
- **§2.1 (attestation gate + rev2.1)** lands in **`failover arm` + the daemons** (Block 5
  proper): see below.

## What `failover arm` DOES (Block 5.3 — shipped as `failover-arm.sh`; EXECUTED only at the rollout)

1. **Preconditions, each refusing with the exact fix printed:** self-v0.7 check — TWO gates
   per installed daemon, both comment-stripped (5.3 panel fix round): the patsub guard
   (scoped to what it proves: pages survive bash 5.2) AND the **watchdog capability** markers
   (`_watchdog_active()` + ≥1 `READY=1` + ≥10 `_watchdog_pet` sites — a v0.6.10 daemon has
   the guard but would never take the armed monitor unit to READY, so the fence would fire on
   a healthy validator; the probe cannot catch that, so P1 must); socat present (§2.6 — the
   SOLE armed transport, refuse, never fall back); flock `-w` support probed (reviewer, 5.2
   GO: busybox flock is detected AT ARM and said aloud — WARN, not refuse: every dispatch
   would take the fence's loud lockless exit-1 path); **unit `--identity` verification** (the
   5.1 proc-gone residual, discharged here: the fenced-demoted outcome is sound only if the
   validator unit's `ExecStart` carries `--identity <unstaked>` — the fence cannot verify it,
   the arm must; since the 5.3 fix round it verifies the PATH **and the KEY**: the file at
   the readlink-resolved `--identity` path must derive — via the host's own
   `solana-keygen`/`agave-keygen` — the env's declared `UNSTAKED_PUBKEY`, so a symlinked or
   mis-copied staked key at the right path refuses too; with repeated `--identity` flags the
   LAST governs, agave semantics, said aloud. PROVEN mismatch refuses the REAL arm with no
   override; UNVERIFIABLE (no keygen / no `UNSTAKED_PUBKEY`) refuses with the manual keygen
   command printed and the one documented dangerous override
   `ARM_ACCEPT_UNVERIFIED_IDENTITY=1`, which arms with a LOUD WARN naming exactly what was
   not verified; page-only proceeds with a WARN and needs none of this; frankendancer states
   the stop-only posture and skips); and the §2.3 one-arm-state announcement (DRY_RUN decides
   WHICH unit).
2. **Probe before arming (§2.1-rev2.1 condition 1, shipped):** render the two `arm-probe`
   skeletons into `ARM_RUNTIME_DIR` (tmpfs — ephemeral by construction), daemon-reload, start
   the probe: `Type=notify` + `WatchdogSec=2s` + `OnFailure=` the probe fence whose ONLY action
   is writing a marker. The start's success IS the §2.6 socat self-test (one READY pet must
   land); the probe then deliberately never pets again, and the ceremony waits (bounded,
   ~15 s) for the OnFailure marker: a physical demonstration that stopped-petting → watchdog →
   `failed` → `OnFailure` dispatch works on THIS host. No marker → refuse to arm (the
   "syntactically valid, functionally dead" class). Transient units cleaned + reloaded.
3. **Install → verify → token:** place the fence bodies into `ARM_INSTALL_DIR` (the ceremony
   is the only placer), render the monitor unit (filling the `<role>` daemon + role env) and
   exactly ONE fence unit — page-only XOR real per DRY_RUN, removing the stale sibling (the
   arm is the alignment mechanism); daemon-reload; **retire the legacy monitor** (fix round 2
   blocker: "exactly ONE" applies to the monitor too — the wizards' pre-fence units
   `solana-failover.service` / `solana-failover-standby.service`, the full name set both
   wizards write or enable, are detected via unit file / `is-active` / `is-enabled`, then
   `stop` → `disable` → VERIFIED retired BEFORE the new monitor is enabled; any failure or
   verify disagreement → `REFUSE[INSTALL-legacy]` with the manual commands printed, no enable,
   no token; the unit FILE stays on disk — deleting it is the operator's cleanup. Supersession
   is an ACTION the ceremony performs, not a rollout plan — and deliberately NOT a daemon-side
   single-instance flock: a Type=notify monitor losing that race never goes READY → start
   timeout → `failed` → OnFailure → a REAL fence on a healthy validator); then `enable` the
   monitor (the only enable of a Block-5 unit); NEVER start/restart the validator unit. Then a
   `_fence_unit_state`-equivalent
   re-read must agree with the intent (render→verify, not render→hope), the persisted
   config-generation counter bumps, and the ceremony REFUSES to complete without printing the
   pairing token (§2.1-rev2.1 conditions 2–3; spare-side consumption is Block 6). Since the
   5.3 fix round: rendering is structural (bash replace, no sed — metacharacter paths render
   byte-exact) with per-file content verification after every render; an un-removable stale
   sibling under REAL intent refuses outright (§2.3's one-unit invariant, never
   WARN-and-arm); and the generation bump is flock-serialized (bounded, residual named where
   flock is absent) and verified to have landed as a regular file holding the bumped value.
4. Daemon-side rot re-verification is BUILT (Block 5.4, the `[fence-rot]` twin block in both
   daemons; `tests/test_fence_rot.sh`): while ARMED, the holder re-verifies its own effective
   fence properties every `FENCE_ROT_CHECK_SECS` — fence unit files re-classified, fence
   LoadState, monitor `Restart`/`OnFailure`/`StartLimitIntervalUSec`, and the `WatchdogSec`
   config for the next start (`systemctl cat` — the show-side `WatchdogUSec` is runtime-only;
   every demote-vs-page classification container-verified on systemd 249 AND 255, design
   record `verify-rot-properties.md`, private tree). Verified fence-killing drift pages
   CRITICAL immediately (exact element + exact fix) and, only after `FENCE_ROT_GRACE` of
   persistence while verifiably STAKED, gracefully self-demotes via the daemon's existing
   demote path (§2.1-rev2.1 №2). Structurally inert on every un-armed host. What remains for
   Block 6 (deliberately NOT daemon work here): the zero-stake verification of the unstaked
   key — it is G2's arm condition and its consumer/wiring is spare-side.

## Frankendancer: STOP-ONLY fencing in v0.7 (named limitation — reviewer-packet item)

On a `VALIDATOR_TYPE=frankendancer` box **every real-fence dispatch takes the stop path**:
`_read_identity` and `_startup_phase_evidence` are agave-CLI-only, the fence's no-network rule
bans the daemons' fd identity read (a localhost curl `getIdentity`) like any other network call,
and no `fdctl` demote rung exists in the fence. A monitor failure on fd therefore means full
validator stop + `fenced-stopped` + HOLD (operator-owned recovery) — and a stopped node never
re-advertises the unstaked flip, so the spare's G2 verified-demote proof cannot form (slower or
no takeover). The daemons DO demote fd (bounded `fdctl set-identity`); the fence deliberately
does not in v0.7. An fd-native demote rung is future work; until then, arming a frankendancer
box means accepting stop-only fencing.

## The boundary, restated

While the entry blocker stands: unit files, the fence scripts, and the arm ceremony MAY be
written — **NO Block-5 unit is installed on ANY host (test hosts included)**, no `systemctl
enable` of one, nothing of theirs into `/etc/systemd/system`. All five `.skel` files are in
`SHA256SUMS` (5.3 panel fix round): they are RENDER SOURCES for root-installed units —
integrity artifacts exactly like the scripts, even though nothing in the repo installs them
(`install.sh` verifies only the files it downloads; the extra manifest rows are inert there,
while CI's `sha256sum -c` checks every row). For the units the `.skel` suffix is the guard (nothing
execs these, CI ships none of them, and the monitor skeleton's `<role>` placeholder makes it
uninstallable as-is); for the two fence scripts and `failover-arm.sh` the guard is that no
code path in this repository RUNS them — they ship in the release artifact, the ceremony is
the only thing that places the fence bodies on a host, and the ceremony itself runs only by
the operator's hand at the rollout (upgrade-then-arm, release checklist). Their tests mock
every actuator (`systemctl`, the admin-socket CLI, `pgrep`, `/proc` reads, `socat`, `flock`)
and point every arm root (`ARM_SYSTEMD_DIR`, `ARM_RUNTIME_DIR`, `ARM_INSTALL_DIR`,
`FENCE_MARKER_DIR`, `ARM_STATE_DIR`) at mktemp; no real `systemctl` call runs from any test.

## Assumptions — verified by execution

1. **OnFailure= tolerates a missing listed unit** — ✅ VERIFIED 2026-08-20 in real-systemd
   containers on the fleet's boundary versions (systemd 249 = Ubuntu 22.04 floor, systemd 255 =
   Ubuntu 24.04): missing target is ignored+logged ("Failed to enqueue OnFailure= job,
   ignoring"), the failing unit reaches terminal `failed` normally, and the existing unit in a
   two-unit list dispatches despite the missing sibling. Load-bearing in ANY design (every
   un-armed host names a nonexistent unit) — executed, not reasoned (the gate-B class). Full
   record: the project design records (`verify-onfailure-missing-unit.md`). The §2.1-rev2.1
   arm-time probe remains: the record proves systemd's semantics, the probe proves THIS host's
   wiring.
