# Reference — the long form of the README

Moved off the README front page on 2026-11-10 (v0.7.0 docs). The text is as it stood in the v0.7.0 README; the front page keeps the summary and links here.

## Quickstart

On the **PRIMARY**:
```bash
bash deploy-failover.sh
```
On the **STANDBY**:
```bash
bash deploy-failover-standby.sh
```

The interactive installer (on the STANDBY it asks for **Simple** or **Advanced** mode; on the PRIMARY it has no mode prompt) writes `/opt/solana-failover/*.env`, installs
a `systemd` unit, and starts in **DRY_RUN** — it logs what it *would* do and changes nothing. Verify the
logs, then arm (PRIMARY first, then STANDBY). On the **PRIMARY**:
```bash
sed -i 's/DRY_RUN=true/DRY_RUN=false/' /opt/solana-failover/failover.env
systemctl restart solana-failover
```
On the **STANDBY**:
```bash
sed -i 's/DRY_RUN=true/DRY_RUN=false/' /opt/solana-failover/failover-standby.env
systemctl restart solana-failover-standby
```
On a host that has been armed with `failover arm`, `DRY_RUN` is part of the arm state: change it by editing the env file and re-running `failover arm`, not by a `sed` and a restart alone
(see the deployment manual, *Update existing*).

## Configuration

The installer generates the env, or copy `failover.env.example` / `failover-standby.env.example`.
Key knobs: `STAKED_KEYPAIR`, `UNSTAKED_KEYPAIR`, `VOTE_PUBKEY`, `TAKEOVER_DELAY`, the three RPC tiers
(local → paid → public), and notifications. Full reference: [docs/DEPLOYMENT-MANUAL.md](DEPLOYMENT-MANUAL.md).
`failover arm` (the fence ceremony) refuses a real arm until `LEDGER_PATH` in the env file names the validator's ledger directory - the fence has no detection of its own - and the monitor unit it installs carries an
`ExecStop=` that re-sends a lost TERM. The standby's take switch is separate: `AG_ARMED_TAKE=false` (the default) only pages; `true` arms the cold take, with `AG_TAKE_MARGIN_SLOTS` (default 200) as its readiness margin and the
pairing rule `TAKEOVER_DELAY` ≥ the holder's `HOLDER_GAP_DEMOTE_SECS` + 30 (shipped 60 ≥ 30 + 30) - [docs/SAFETY.md — Armed cold take](SAFETY.md#armed-cold-take-opt-in-rc1).

On a host armed with the v0.7 fence, the daemon also re-verifies its own effective fence
properties every `FENCE_ROT_CHECK_SECS` (default 60 s): drift that verifiably kills the fence
(unit gone/masked/unloadable, a drop-in re-adding `Restart=`, `OnFailure` no longer naming the
fence) pages CRITICAL immediately with the exact fix command, and only if it persists for
`FENCE_ROT_GRACE` (default 1800 s, floor max(600, `ALERT_THROTTLE`)) while the node still
verifiably holds the staked identity does the holder gracefully demote itself to unstaked — the
spare then sees a silent holder and pages (v0.7: an unarmed spare never takes, an armed one takes cold; the retained path took over on its timer path, the v0.6.x semantics, with or without G2; once Block 6.4 wires
the relinquish-proof gate, via the verified-demote proof). Never instant, never on a guess: a failing
`systemctl` is treated as cannot-verify (page after a blind streak, no demote clock), and both
knobs are daemon defaults with validation — no env entry needed. Un-armed hosts (everything
before the v0.7 rollout) see zero behavior change.

## Tests

```bash
cd tests && bash run_all.sh
```
65 suites, parse-clean on bash 3.2+ (CI runs them on both bash 3.2 and 5.2). They drive the real self-fence / takeover / timing functions with
mocked I/O, and each safety fix ships with a control that fails when the fix is reverted. Seven older controls compare
against an earlier release's file, which this repository does not ship; they print `⏭ SKIP` instead of passing (Block 6.4
moves them onto the harness's `mutate()`). Network clients reached
through `PATH` are caught by `run_all.sh`'s stage (4) on every leg; at the syscall level, `tests/strace-hermetic.sh`
(CI's strace job, ubuntu-24.04) fails on any inet socket in the whole run. A suite still running at `run_all.sh`'s
per-suite cap (`RUN_ALL_SUITE_CAP`: an hour by default; CI sizes it per job) is killed, with whatever it left in its
process group, and fails the run, named. Note the limit: these are function-level tests — they do
**not** prove cross-process ordering between two live systemd services. A chaos/E2E gate on real nodes is required before unattended operation, and this release does not ship one; the live fault runs that were made are listed in [evidence/2026-11-live-drills.md](evidence/2026-11-live-drills.md).

## Roadmap

**Status after the release.** `v0.7.0` shipped the fence (a systemd watchdog installed by `failover arm`, opt-in), the paging spare and atomic state writes. It did not ship the rest of the v0.7 entry below: the relinquish-proof gate that would condition a take on the fence, the check that the vote account belongs to the staked identity, escalation to a hard stop on every unverified demote in the daemons' own demote path (the armed fence, in live mode, already stops the validator on any failed or doubtful demote), a simpler installer, a status dashboard, or a chaos/E2E gate on real nodes. These remain open. The entries below are the text as at `v0.7.0`.

- **v0.7** — the fence: a node that can no longer confirm it owns the identity is stopped by a
  watchdog, and the spare pages (an unarmed spare never takes, in Alpenglow mode) on the same gates; the retained take path needs positive proof the old holder was stopped or stepped
  down — never inference alone. Ships alongside evidence fixes (vote account ↔ identity binding,
  atomic state, escalation on an unverified demote), a simpler installer, a status dashboard, and a
  chaos/E2E gate on real nodes.
- **v0.8** — optional external fence providers (cloud API / IPMI / PDU) on the same interface, for
  operators who want a second, out-of-band guarantee.
