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

The bootstrap (`install.sh`) downloads the wizard + daemon for a **pinned tag**. What it can verify
depends on the tag:

- **v0.6.9 and v0.6.10 predate the `SHA256SUMS` manifest** — no manifest exists at those tags, so
  their downloads are checked **by syntax only** (`bash -n`), and the installer prints a warning
  saying so. No checksum can be added to them: a manifest would have to change the files those tags hold.
- **From the first manifest-bearing release on**, both files are verified against the tag's
  `SHA256SUMS`, **failing closed** on any mismatch, missing entry, or missing manifest.

Be precise about what that buys you:

- **Checksums catch** a corrupted or truncated download and a partially applied tag.
- **Checksums do not catch** an intermediary on the delivery path that rewrites the files and the
  manifest together — a compromised mirror or CDN, this repository, or `zim.one`: the manifest
  travels through the same channel as the files it describes.

**The release tags, and what anchors them.** The `v0.6.9` and `v0.6.10` release tags are **not
signed**, and they will not be: a signature cannot be added to a tag that was published without one.
From **v0.7.0** on, release tags are **signed** with the maintainer's SSH key, and from v0.7.0 on a
published tag is not moved or re-created. That signature is the anchor the checksum layer cannot be.

The key's public half is published outside GitHub, on the maintainer's own domain —
<https://zim.one/failover.pub>, with the `allowed_signers` file that git reads at
<https://zim.one/failover.allowed_signers> — and the same key is also a Signing Key on the
maintainer's GitHub profile, a second channel. Its fingerprint is
`SHA256:KiZjkE1/ETQXqSbAK9Oiwoy744XrS6r+nSOnTkmLixo`. Compare it on both channels, so that you trust
neither alone; on the GitHub side, one of the lines this prints is that fingerprint:

```sh
curl -sSf https://api.github.com/users/zimone91/ssh_signing_keys | jq -r '.[].key' | ssh-keygen -lf -
```

Verify a tag before you run anything, in a clone of this repository:

```sh
curl -sSfLO https://zim.one/failover.allowed_signers && git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=failover.allowed_signers tag -v v0.7.0
```

Success is exit status 0 and a line `Good "git" signature for <name> with ED25519 key SHA256:…`. Git
matches the signature to the **key** in that file and prints the name on the key's line only as a
label, so compare the **fingerprint** it prints with the one above, not the name. The same line
without `for <name>`, followed by `No principal matched.`, is a failure: the key that signed is not
the one in the file.

**`install.sh` itself verifies no signature**: it checks the files it fetches against the tag's
`SHA256SUMS` manifest, fail-closed, and nothing else - the signature is yours to check, with git,
before you run it. And prefer the paranoid path regardless:

```sh
curl -fsSLO https://raw.githubusercontent.com/zimone91/solana-validator-failover/<TAG>/install.sh
# read it — it is about 120 lines — then:
FAILOVER_VERSION=<TAG> sh install.sh   # pin it: at a tag the file's own default is the release before it
```

Everything shipped is plain text (bash scripts, the POSIX `sh` installer `install.sh`, two env
templates, five systemd unit skeletons): the entire tool can be read in an afternoon, and that
remains the strongest verification available. CI runs the full suite on pushes to `main` and on
pull requests (bash 3.2 and 5.2 — the 5.2 job exists because a real interpreter-semantics bug
shipped in v0.6.9 and was caught only by running on both; see `.github/workflows/ci.yml`).

## Audit history

Four internal audit rounds plus an external-style verification round have run against this
codebase, every one of which found real problems after someone had declared it ready. The findings
and what changed are published in [`docs/audits/`](docs/audits/) — including the ones that made us
retract public claims. Production evidence (a real unplanned mainnet activation, measured loop
cadence) is in [`docs/evidence/`](docs/evidence/).
