# `systemd/` — v0.7 Block-5 fence scripts (real) + unit skeletons (installed by NOTHING)

**Two kinds of file live here (Block 5.1):**

- **The fence scripts are REAL shippable artifacts** — `failover-fence.sh` (the §2.5
  ladder/§2.2 verdict body, tested by `tests/test_fence_script.sh`) and
  `failover-fence-page-only.sh` (the §2.3 structural-DRY_RUN twin). They are in `SHA256SUMS`,
  the CI shellcheck list, and `run_all.sh`'s parse gate. Shippable is NOT installed: their
  EXECUTION on a host happens only at the v0.7 rollout (`failover arm`, upgrade-then-arm, per
  the release checklist).
- **Every `.service.skel` stays a skeleton — repo-only.** Units are installed ONLY by the
  `failover arm` ceremony (not yet shipped).

Nothing in this repository writes to `/etc/systemd/system`, runs `systemctl enable`, or
`daemon-reload`s on their behalf. The **Block-5 entry blocker** gates the first
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

## What `failover arm` will do LATER (none of it shipped here)

1. Verify the entry blocker's host answer, then install the monitor unit (filling the
   `<role>` daemon in `ExecStart=`) and exactly ONE fence unit — page-only first; the REAL unit
   only on explicit arming. Which unit it installs IS the arm state (§2.3).
2. **Probe before arming (§2.1-rev2.1, described NOT shipped):** launch a short-lived transient
   probe unit (`systemd-run`, `Type=notify`, `WatchdogSec=2s`, `OnFailure=` a probe-mode fence
   whose only action is writing a marker), let it go READY and deliberately never pet, and wait
   (bounded, ~15 s) for the marker: a physical demonstration that stopped-petting → watchdog →
   `failed` → `OnFailure` dispatch works on THIS host. Refuse to arm without it — this catches
   the "syntactically valid, functionally dead" unit-config class. There is deliberately NO
   probe `.skel` in this directory: the probe is transient (`systemd-run`), generated by the
   ceremony.
3. Run the socat round-trip self-test (a pet must land; §2.6), verify the holder's unstaked key
   is zero-stake (G2's arm condition), record fence properties into the pairing token (§2.1),
   and on any unit/arming change bump the token generation and re-print it (re-pair ceremony).
4. Periodic holder-side re-verification of effective fence properties + the `FENCE_ROT_GRACE`
   escalation window (§2.1-rev2.1 №2) — Block 5 proper, daemon-side.

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

While the entry blocker stands: unit files, the fence scripts, and harness tests MAY be written
— **NO unit is installed on ANY host (test hosts included)**, no `systemctl enable`, nothing
into `/etc/systemd/system`. For the units the `.skel` suffix is the guard (nothing execs these,
CI ships none of them, and the monitor skeleton's `<role>` placeholder makes it uninstallable
as-is); for the two real fence scripts the guard is that no code path references or copies them
to a host — they ship in the release artifact and are placed only by the `failover arm`
ceremony at the rollout (upgrade-then-arm). Their tests mock every actuator (`systemctl`, the
admin-socket CLI, `pgrep`, `/proc` reads); no real `systemctl` call runs from any test.

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
