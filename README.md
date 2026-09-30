# Solana Validator Failover

[![ci](https://github.com/zimone91/solana-validator-failover/actions/workflows/ci.yml/badge.svg)](https://github.com/zimone91/solana-validator-failover/actions/workflows/ci.yml)

Automatic staked-identity failover for Solana validators. If your staked node dies or goes silent, a
spare picks the identity up via `agave-validator set-identity` — no restart, no manual steps, ~60s.
The ~60s holds while the external RPCs are observable — when they are not, the takeover holds for as
long as the blindness lasts (by design: unobservable time counts as life) and the operator is paged
(`TAKEOVER_STARVATION_ALERT_SECS`, default 300s).

Built safety-first: the failing node **steps down before** the spare steps up, and every ambiguous
state resolves toward *nobody holds the stake* rather than two nodes holding it.

**Author:** [zim.one](https://zim.one) · **Tested on:** agave & Jito-Solana `4.2.x` — live failover gate on `4.2.0-rc.0`, running armed in production on `4.2.1`; earlier releases validated on `3.1.x` / `4.0.x` / `4.1.x` · **Networks:** testnet · mainnet

#### How safe is it — honestly

The failing node fences **itself** (dead RPC, frozen slot, or its own votes not landing) and drops to an
unstaked identity within ~30s. Only then, after a 60s floor plus an on-chain check that the vote account
really stopped, does the spare take over. Live-tested end to end on testnet: [test evidence](docs/SAFETY.md#what-has-been-tested).

The honest limit: a node that has gone **completely silent** cannot be proven incapable of voting — it
might be wedged, or partitioned and still signing where you can't see it. Detecting that from the
outside is impossible in principle; it has to be *made* true by fencing the old host. That fence lands
in **v0.7**. Until then, run a `DRY_RUN` soak on your own stack first, and read
[docs/SAFETY.md](docs/SAFETY.md) before pointing this at a mainnet identity you care about.

---

## What it does

- Watches the local validator. If the PRIMARY goes delinquent or isolated, it **self-fences** to its
  own unstaked identity within ~30s; a STANDBY then **takes** the staked identity after a cross-node
  safety delay.
- Detects the failure modes that matter: dead local RPC, frozen slot, **egress-only partition** (own
  votes not landing while the node still looks healthy), and on-chain delinquency.
- **Fails safe by design:** ambiguity resolves toward *unstaked / stop / page the operator*, not toward
  taking the identity. (Design intent — see the residual risks below and in `docs/SAFETY.md`.)

## Safety model

> **Prime directive: never let two nodes hold and vote the same staked identity (double-sign).**
> Everything below serves that goal; the honest limits of the current implementation follow it.

- The PRIMARY **relinquishes first** (self-fences to unstaked) before any spare can take.
- The STANDBY takes only after `TAKEOVER_DELAY` (default **60s** = the PRIMARY's ~30s self-fence + a 30s
  cross-node margin) **and** a vote-liveness check that the previous holder's vote account has stopped
  advancing. A hand-edited delay below the safe floor **refuses to start**. The last read before the
  take is the spare's **own** node (v0.7): one bounded read (`curl -m 2` + a watchdog pet) that
  withdraws the take if its own node shows the holder voting, cannot answer, or is not advancing; the
  spare also samples its own head through the episode and before each external read of the take cycle
  — five to twelve bounded local reads per take cycle at the defaults (one more on an armed unit, up to
  four more with the opt-in witness fast path), milliseconds on a healthy node (measured: +9 to
  +15 s when every local read takes 1 s with prompt tiers, up to +40 s in the measured cells with a slow
  tier as well; as a local read nears its 2 s bound the take slides later, and at 2 s or more the spare
  never takes — loudly: the veto page, then the starvation page). How that ordering holds up per failure
  class, measured, including where it does not:
  [docs/SAFETY.md — the cross-node invariant](docs/SAFETY.md#the-cross-node-invariant).
- Two named residuals of that own view ([docs/SAFETY.md — the spare's own view](docs/SAFETY.md#the-spares-own-view-v07-block-631),
  residuals 6 and 7). **The mirror world** (Block 6.3's too): with `TIER2` splicing or lagging (showing the
  holder frozen) while the spare's own node lags as well, a holder that resumed within that lag is taken
  while it votes — up to the lag the spare's own `--health-check-slot-distance` admits at the take cycle's
  Tier-1 check (128 slots by default, ≈ 51 s at 2.5 slots/s: the distance ÷ the cluster's slot rate; a lag
  that grows during a slow take cycle is not bounded by it), so a lower distance on the spare's validator
  narrows it. **The starvation** — introduced by Block 6.3.1's own-view veto, an availability regression (never a
  double-sign): Block 6.3 has no veto and takes these holders. A `TIER2` that fails slowly — times out, or answers
  an error or garbage late — while `TIER3` is slow (`TIER2`'s time to failure + `TIER3`'s answer + both local reads
  past 16 s: after a timeout, `TIER3` 7 s or more, 5 s when local reads take 1 s) leaves the veto no fresh own-head
  baseline, so a dead holder is never taken over, loudly — the veto page
  `⚠️ Take VETOED by this spare's own view (it could not testify): …`, then the starvation page
  `⚠️ TAKEOVER STARVATION: …` (on a real host one second less is vetoed too, at some phases) — repair that
  `TIER2`, or while it is broken leave `TIER2_RPC` empty (an armed spare with
  `PRIMARY_UNSTAKED_PUBKEY` set then pages "G2 VANTAGES NOT DISTINCT" at every start — verified-demote off for
  the run; a paired spare keeps watchdog-elapsed — unless `G2_VANTAGE_A` names another provider), or use a `TIER3`
  that answers the full `getVoteAccounts` well under ~5 s (about 3 s when local reads take 1 s); a `TIER2`
  that refuses at once does not starve the take.
- **This release has no relinquish-proof gate:** armed or not, the spare's take follows the v0.6.x semantics,
  which the 6.3 re-check and the own-view veto can only hold — no provider's verdict conditions any take. An armed
  spare that is not paired (or is paired with an invalid or page-only token) pages `ARMED SPARE NOT ATTESTED 🚨`
  at every start: arm the holder first and copy its token, because from the release that wires the gate (Block
  6.4) an unpaired or invalidly paired spare's silence-based take is disabled. That gate will decide *how* the old
  holder is known to be gone; its providers already run on an armed spare. The strongest proof is
  **verified-demote (G2)**: the holder's *unstaked* identity observed in gossip at the staked identity's exact
  endpoint, and still there ≥60s later on two pinned RPC
  vantages from distinct failure domains — a positive "the demoted state is live *now*", not an absence
  guess. Each snapshot is one JSON-RPC batch, so the freshness anchor (the vantage's own confirmed
  slot) rides *inside* the response that carries the proof: cached and replayed vantage data reads as
  *cannot-determine*, never as proof. `failover arm` refuses to arm a spare whose vantages cannot serve
  that batch, or whose two vantage names resolve to one address. By default those vantages *are*
  `TIER2_RPC`/`TIER3_RPC` — the same endpoints the vote-liveness check reads — and on such a host one
  compromised vantage can supply both halves of a double-sign; the arm measures that, says so, and
  recommends a third endpoint in a separate failure domain. What each layer does and does **not**
  catch — including an active protocol-aware intermediary, which it does not — is enumerated in
  [`docs/SAFETY.md`](docs/SAFETY.md). Un-armed hosts see none of this.
- A promoted STANDBY that later isolates self-fences too, with a 600s re-take lockout.

**Where the strength comes from.** The protection is strongest where the failing node can detect its
own trouble and step down — which covers dead RPC, a stalled slot, and an egress-only partition where
its votes stop landing. For a node that has gone *completely* silent, "stopped voting" is evidence
rather than proof; v0.7 adds a watchdog so a node that can no longer confirm it owns the identity
stops itself. Detail: [docs/SAFETY.md](docs/SAFETY.md) · [docs/SPLIT-BRAIN-RESIDUAL.md](docs/SPLIT-BRAIN-RESIDUAL.md).

```
PRIMARY ──self-fence ~30s──►  STANDBY ──takes at 60s──►  BACKUP
holds staked, steps down       takes staked              (120s, only if STANDBY is also down)
```

A spare's take also waits for its own-view reads (milliseconds on a healthy node; measured +9 to +15 s
when every local read takes 1 s with prompt tiers, up to +40 s in the measured cells with a slow tier as
well; a spare whose local reads take 2 s or more never takes, and pages — so does one whose `TIER2` fails
slowly (times out, or answers an error late) while `TIER3` is slow, the starvation above) after the delays
shown.
Details and the residual-risk analysis: [docs/SAFETY.md](docs/SAFETY.md).

## Requirements

- `agave-validator` (or Jito-Solana), `jq`, `curl`, `systemd`, run as root.
- Two nodes sharing the same **staked** keypair, each with its own **unique unstaked** keypair.

## Install (one command)

```bash
sh -c "$(curl -sSfL https://zim.one/failover/v0.6.10)"
```
Asks whether this node is PRIMARY or STANDBY, downloads that role's files for the pinned version, verifies them (against the version's `SHA256SUMS` manifest, fail-closed, from the first manifest-bearing release on — `v0.6.9`/`v0.6.10` predate the manifest and are syntax-checked only, which the installer says aloud; no v0.6.x tag is signed), and runs the installer (interactive; starts in DRY_RUN). This tool hot-swaps your staked identity — read `install.sh` before running it. The paranoid path (recommended for a root-level tool):

```bash
curl -fsSLO https://raw.githubusercontent.com/zimone91/solana-validator-failover/v0.6.10/install.sh
```
read it, then run `sh install.sh`. **What checksums honestly buy you:** detection of a corrupted or truncated download (or a partially applied tag) — not of anyone on the delivery path who rewrites the files and the manifest together: a compromised mirror/CDN, this repository, or zim.one (the manifest travels through the same channel). Details, scope, and disclosure: [SECURITY.md](SECURITY.md).

Or from source:
```bash
git clone --branch v0.6.10 https://github.com/zimone91/solana-validator-failover
cd solana-validator-failover
sudo bash deploy-failover.sh          # deploy-failover-standby.sh on the spare
```

## Quickstart

On the **PRIMARY**:
```bash
bash deploy-failover.sh
```
On the **STANDBY**:
```bash
bash deploy-failover-standby.sh
```

The interactive installer (**Simple** / **Advanced** modes) writes `/opt/solana-failover/*.env`, installs
a `systemd` unit, and starts in **DRY_RUN** — it logs what it *would* do and changes nothing. Verify the
logs, then arm (PRIMARY first, then STANDBY):
```bash
sed -i 's/DRY_RUN=true/DRY_RUN=false/' /opt/solana-failover/failover.env
systemctl restart solana-failover
```

## Configuration

The installer generates the env, or copy `failover.env.example` / `failover-standby.env.example`.
Key knobs: `STAKED_KEYPAIR`, `UNSTAKED_KEYPAIR`, `VOTE_PUBKEY`, `TAKEOVER_DELAY`, the three RPC tiers
(local → paid → public), and notifications. Full reference: [docs/DEPLOYMENT-MANUAL.md](docs/DEPLOYMENT-MANUAL.md).

On a host armed with the v0.7 fence, the daemon also re-verifies its own effective fence
properties every `FENCE_ROT_CHECK_SECS` (default 60 s): drift that verifiably kills the fence
(unit gone/masked/unloadable, a drop-in re-adding `Restart=`, `OnFailure` no longer naming the
fence) pages CRITICAL immediately with the exact fix command, and only if it persists for
`FENCE_ROT_GRACE` (default 1800 s, floor max(600, `ALERT_THROTTLE`)) while the node still
verifiably holds the staked identity does the holder gracefully demote itself to unstaked — the
spare then takes over via the verified-demote proof. Never instant, never on a guess: a failing
`systemctl` is treated as cannot-verify (page after a blind streak, no demote clock), and both
knobs are daemon defaults with validation — no env entry needed. Un-armed hosts (everything
before the v0.7 rollout) see zero behavior change.

## Notifications

Telegram + [ntfy.sh](https://ntfy.sh) push + an external "dead-man's switch" watchdog
(healthchecks.io / Uptime Kuma / cronitor) that pages you if the monitor process itself dies.
See [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md).

## Tests

```bash
cd tests && bash run_all.sh
```
54 suites, parse-clean on bash 3.2+ (CI runs them on both bash 3.2 and 5.2). They drive the real self-fence / takeover / timing functions with
mocked I/O, and each safety fix ships with a control that fails when the fix is reverted. Network clients reached
through `PATH` are caught by `run_all.sh`'s stage (4) on every leg; at the syscall level, the CI strace job
(ubuntu-24.04) sees no inet socket in the whole run. Note the limit: these are function-level tests — they do
**not** prove cross-process ordering between two live systemd services. A chaos/E2E gate on real nodes is part of the v0.7 work.

## ⚠️ Before you point this at a mainnet identity

- **Not for unattended mainnet yet** — see “How safe is it — honestly” above. Until the v0.7 fence
  lands, run `DRY_RUN`, testnet, or keep a human in the loop to fence the old node before promotion.
- **Test on testnet first** — DRY_RUN soak, then a live failover on a testnet stack.
- This tool **moves your staked identity between machines.** Never aim `STAKED_KEYPAIR` at an identity
  you can't afford to have hot-swapped.
- **Each node needs its own unique unstaked keypair** — a shared unstaked pubkey breaks the fence.
- **Point `VOTE_PUBKEY` at *your* vote account** — the one whose `nodePubkey` is your staked identity.
  The release does not yet verify that binding; a wrong vote account silently misleads the fence.
- Roll out **one node at a time**; leave the advanced gossip fast-path (Option A) **off** until you've
  watched the timer path in production for a while.

## Roadmap

- **v0.7** — the fence: a node that can no longer confirm it owns the identity is stopped by a
  watchdog, and the spare takes over only on positive proof the old holder was stopped or stepped
  down — never on inference alone. Ships alongside evidence fixes (vote account ↔ identity binding,
  atomic state, escalation on an unverified demote), a simpler installer, a status dashboard, and a
  chaos/E2E gate on real nodes.
- **v0.8** — optional external fence providers (cloud API / IPMI / PDU) on the same interface, for
  operators who want a second, out-of-band guarantee.

## Verify the claims, not the adjectives

- [SECURITY.md](SECURITY.md) — disclosure contact; what runs as root; what verification does and does not give you.
- [docs/audits/](docs/audits/) — every audit round, including the one that made us retract a public overclaim and the NO-GO verdict. Each finding shipped with a control test that fails if the fix is reverted.
- [docs/evidence/](docs/evidence/) — armed-production evidence: a real unplanned mainnet failover (2026-08-10, every gate logged) *and* the incident from the same fleet, because evidence cuts both ways.
- [CI](.github/workflows/ci.yml) runs the full suite on bash 3.2 **and** 5.2 on every push — the 5.2 job exists because a real interpreter bug shipped and was invisible to a single-interpreter suite.

## License

[MIT](LICENSE) © [zim.one](https://zim.one)
