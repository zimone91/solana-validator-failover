# Solana Validator Failover

Automatic failover for Solana validators. When your staked node fails or is isolated, it hot-swaps the
staked identity to a healthy spare via `agave-validator set-identity` — no restart — with layered
fences whose every ambiguous case resolves toward *unstaked / stop / page the operator*.

**Author:** [zim.one](https://zim.one) · **Tested on:** agave & Jito-Solana `3.1.18` / `4.0.1` / `4.1.0` · **Networks:** testnet + mainnet

> ### ⚠️ Status: not yet for unattended mainnet
>
> Read this before pointing it at a staked mainnet identity.
>
> The spare decides the old holder is gone by observing that **its vote account stopped advancing**.
> That is strong *corroboration* — it is **not proof** that the old node is incapable of voting again.
> A wedged-but-alive validator, a node on a minority fork, or one whose votes simply aren't reaching
> the RPCs you polled can, in principle, resume. Closing that gap requires **external fencing
> (STONITH)** — a confirmed power-off / network fence of the old host — which this tool does **not**
> yet perform.
>
> **Therefore:** use it in `DRY_RUN`, on testnet, or in **assisted production** — where a human or an
> external automation fences the old node before the spare is promoted. Fully unattended mainnet
> failover is the goal of the fencing work tracked for v0.8, not a property of this release.
>
> Full analysis: [docs/SAFETY.md](docs/SAFETY.md) · [docs/SPLIT-BRAIN-RESIDUAL.md](docs/SPLIT-BRAIN-RESIDUAL.md)

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
  advancing. A hand-edited delay below the safe floor **refuses to start**.
- A promoted STANDBY that later isolates self-fences too, with a 600s re-take lockout.

**What this does not prove.** Vote-liveness is *evidence*, not a fence: a holder that is wedged,
partitioned onto a minority fork, or invisible to the RPCs you polled may still be able to sign. Until
external fencing lands (v0.8), the guarantee holds for the failure modes the holder can self-detect —
and for the rest you need a human or an external fence in the loop.

```
PRIMARY ──self-fence ~30s──►  STANDBY ──takes at 60s──►  BACKUP
holds staked, steps down       takes staked              (120s, only if STANDBY is also down)
```

Details and the residual-risk analysis: [docs/SAFETY.md](docs/SAFETY.md).

## Requirements

- `agave-validator` (or Jito-Solana), `jq`, `curl`, `systemd`, run as root.
- Two nodes sharing the same **staked** keypair, each with its own **unique unstaked** keypair.

## Install (one command)

```bash
sh -c "$(curl -sSfL https://zim.one/failover/v0.6.10)"
```
Asks whether this node is PRIMARY or STANDBY, downloads that role's files for the pinned version, and runs the installer (interactive; starts in DRY_RUN). This tool hot-swaps your staked identity — read `install.sh` before running it.

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

## Notifications

Telegram + [ntfy.sh](https://ntfy.sh) push + an external "dead-man's switch" watchdog
(healthchecks.io / Uptime Kuma / cronitor) that pages you if the monitor process itself dies.
See [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md).

## Tests

```bash
cd tests && bash run_all.sh
```
36 suites, parse-clean on bash 3.2+. They drive the real self-fence / takeover / timing functions with
mocked I/O, and each safety fix ships with a control that fails when the fix is reverted. Note the
limit: these are function-level tests — they do **not** prove cross-process ordering between two live
systemd services. A chaos/E2E gate on real nodes is part of the v0.8 work.

## ⚠️ Before you point this at a mainnet identity

- **Not for unattended mainnet yet** — see the status note at the top. Until external fencing lands,
  run `DRY_RUN`, testnet, or assisted production with a human/automation fencing the old node.
- **Test on testnet first** — DRY_RUN soak, then a live failover on a testnet stack.
- This tool **moves your staked identity between machines.** Never aim `STAKED_KEYPAIR` at an identity
  you can't afford to have hot-swapped.
- **Each node needs its own unique unstaked keypair** — a shared unstaked pubkey breaks the fence.
- **Point `VOTE_PUBKEY` at *your* vote account** — the one whose `nodePubkey` is your staked identity.
  The release does not yet verify that binding; a wrong vote account silently misleads the fence.
- Roll out **one node at a time**; leave the advanced gossip fast-path (Option A) **off** until you've
  watched the timer path in production for a while.

## Roadmap

- **v0.7** — evidence hardening: bind vote account ↔ identity, provider-pinned liveness samples,
  `EPSILON=0`, escalate on any unverified demote, atomic state, monotonic timers.
- **v0.8** — fencing: generation + verified relinquish (graceful) / external STONITH confirmed to a
  terminal state (ungraceful); no promotion without one of them. Plus a chaos/E2E gate on real nodes.

## License

[MIT](LICENSE) © [zim.one](https://zim.one)
