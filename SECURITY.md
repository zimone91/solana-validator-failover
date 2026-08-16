# Security

This tool runs as **root** next to a live Solana validator and can move a **staked identity**
between machines. Treat every claim here with the same skepticism we apply to ourselves — the
project's audit history (below) exists because claims kept failing review, not because they passed.

## Reporting a vulnerability

- **Contact:** `zimone91@gmail.com` (subject prefix `[failover-security]`), or GitHub's private
  vulnerability reporting on this repository if enabled for you.
- **In scope, highest priority first:** anything that can make **two nodes vote the same staked
  identity** (double-sign); anything that executes attacker-controlled code through the install
  path (`install.sh`, the Cloudflare route, the wizards); anything that silently disables
  protection or alerting (the monitor believing it is protecting when it is not — see the
  2026-08 incident class in the audit history); privilege issues in the generated systemd units.
- **Expectations:** acknowledgment within 72 hours; an honest assessment (including "you are
  right and it ships broken") rather than triage theater; credit if you want it. There is no
  bounty program — this is an MIT tool run by a validator operator, not a company.

## What runs as root, and why

The wizards write `/opt/solana-failover/` and a systemd unit, and the daemons call
`agave-validator set-identity` / `authorized-voter` on the validator's admin socket and (in
escalation paths) `systemctl` against the validator unit. That is the entire reason for root.
There is no telemetry, no phone-home, and no code fetched at runtime — the daemons make JSON-RPC
reads and send your configured notifications, nothing else.

## Verifying what you install

The bootstrap (`install.sh`) downloads the wizard + daemon for a **pinned tag** and verifies both
against the tag's `SHA256SUMS` manifest, **failing closed** on any mismatch or missing entry.

Be precise about what that buys you:

- **Checksums protect against** a corrupted or truncated download, a tampering mirror/CDN, and a
  partially applied tag.
- **Checksums do not protect against** a compromise of this repository or of `zim.one` — the
  manifest travels through the same channel as the files it describes.

The anchor outside the delivery channel is the **signed release tag**, verified against a
maintainer key published outside GitHub. Until a release ships with a signed tag and the published
key, do not treat the checksum layer as more than it is — and prefer the paranoid path regardless:

```sh
curl -fsSLO https://raw.githubusercontent.com/zimone91/solana-validator-failover/<TAG>/install.sh
# read it — it is ~120 lines — then:
sh install.sh
```

Everything shipped is plain bash: the entire tool can be read in an afternoon, and that remains
the strongest verification available. CI runs the full suite on every push (bash 3.2 and 5.2 —
the 5.2 job exists because a real interpreter-semantics bug shipped in v0.6.9 and was caught only
by running on both; see `.github/workflows/ci.yml`).

## Audit history

Four internal audit rounds plus an external-style verification round have run against this
codebase, every one of which found real problems after someone had declared it ready. The findings
and what changed are published in [`docs/audits/`](docs/audits/) — including the ones that made us
retract public claims. Production evidence (a real unplanned mainnet activation, measured loop
cadence) is in [`docs/evidence/`](docs/evidence/).
