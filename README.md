# Solana Validator Failover

Automatic, **double-sign-safe** failover for Solana validators. When your staked node fails or is
isolated, it hot-swaps the staked identity to a healthy spare via `agave-validator set-identity` — no
restart, no manual intervention — while guaranteeing that **two nodes never vote the same identity**.

**Author:** [zim.one](https://zim.one) · **Tested on:** agave & Jito-Solana `3.1.18` / `4.0.1` / `4.1.0` · **Networks:** testnet + mainnet

---

## What it does

- Watches the local validator. If the PRIMARY goes delinquent or isolated, it **self-fences** to its
  own unstaked identity within ~30s; a STANDBY then **takes** the staked identity after a cross-node
  safety delay.
- Detects the failure modes that matter: dead local RPC, frozen slot, **egress-only partition** (own
  votes not landing while the node still looks healthy), and on-chain delinquency.
- **Fails safe by construction:** every ambiguous state resolves toward *unstaked / page the operator* —
  never toward two nodes holding the stake.

## Safety model

> **Prime directive: never let two nodes hold and vote the same staked identity (double-sign).**

- The PRIMARY **relinquishes first** (self-fences to unstaked) before any spare can take.
- The STANDBY takes only after `TAKEOVER_DELAY` (default **60s** = the PRIMARY's ~30s self-fence + a 30s
  cross-node margin) **and** an authoritative vote-liveness check that the previous holder has stopped
  voting. A hand-edited delay below the safe floor **refuses to start**.
- A promoted STANDBY that later isolates self-fences too, with a 600s re-take lockout.

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
sh -c "$(curl -sSfL https://zim.one/failover/v0.6.9)"
```
Asks whether this node is PRIMARY or STANDBY, downloads that role's files for the pinned version, and runs the installer (interactive; starts in DRY_RUN). This tool hot-swaps your staked identity — read `install.sh` before running it.

Or from source:
```bash
git clone --branch v0.6.9 https://github.com/zimone91/solana-validator-failover
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
37 suites, parse-clean on bash 3.2+. They drive the real self-fence / takeover / timing functions with
mocked I/O, and each safety fix ships with a control that fails when the fix is reverted.

## ⚠️ Before you point this at a mainnet identity

- **Test on testnet first** — DRY_RUN soak, then a live failover on a testnet stack.
- This tool **moves your staked identity between machines.** Never aim `STAKED_KEYPAIR` at an identity
  you can't afford to have hot-swapped.
- **Each node needs its own unique unstaked keypair** — a shared unstaked pubkey breaks the fence.
- Roll out **one node at a time**; leave the advanced gossip fast-path (Option A) **off** until you've
  watched the timer path in production for a while.

## License

[MIT](LICENSE) © [zim.one](https://zim.one)
