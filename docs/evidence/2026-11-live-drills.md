# Live fault drills on real validators — June to November 2026

Every row below is a fault that was **caused on purpose on a running validator pair** (or, in the three rows marked
*not a drill*, happened by itself), with the failover daemons live. This file is the long form of the test claims in the
README and in `docs/FAILOVER-OVERVIEW.md`. It lists what went wrong as well as what worked.

**Scope and limits.** One pair of bare-metal hosts on Solana testnet, plus the author's mainnet pair where a row
says so. The raw driver logs, daemon logs and samplers are kept by the author and are not published, because they
carry host identifiers; the numbers below are read from them. Hosts are named by role: **A** — the node that
normally holds the staked identity (PRIMARY), **B** — the spare (STANDBY). Times are seconds after the induced
event unless a row says otherwise. The **Runs** column counts repeats: one run is one induced fault, one soak or
one planned swap, with its own records. This is evidence, not a guarantee: read `docs/SAFETY.md` for the residual risks.

## How the drills were run

- **Hosts.** A: AMD Ryzen 9 7950X (16 cores), 187 GiB RAM, 2 × 2 TB NVMe, Ubuntu 24.04, systemd 255. B: AMD Ryzen 9
  3900X (12 cores), 125 GiB RAM, 2 TB NVMe, Ubuntu 22.04, systemd 249. Both bare metal, 1 Gb/s.
- **Validator clients.** June: agave / Jito-Solana 4.1.0-rc.1 (A Jito, B agave). July: 4.2.0-rc.0. November: Jito-Solana
  4.4.0 on A and agave 4.4.0 on B, Alpenglow active on testnet; A on 4.5.0-beta.0 from 2026-11-10, both by 2026-11-11.
- **Faults.** `iptables` DROP/REJECT rules (full isolation except loopback and ssh; outbound-only cuts; a blocked
  local RPC port; a cut link between A and B; blocked external RPC providers), `tc netem` loss and delay,
  `SIGSTOP` / `SIGKILL` of the validator or of the failover daemon, host reboots. Every network rule had a timed
  automatic revert. The rules act at netfilter. In November A's validator ran with XDP egress, and packets sent
  through AF_XDP do not pass netfilter: an isolation of A was complete inbound and partial outbound.
- **Who caused them.** Process kills and reboots of a validator that held the staked identity, and every manual move
  of the identity, were done by the operator; the rest by a scripted driver from a third machine.
- **Observers.** A 1 Hz sampler of the vote account on each host, the public `lastVote` read from a third machine
  every two to three seconds, the validators' own vote logs, and the number of gossip entries for the staked identity.
- **Armed or not.** A row that says *take* was run with the spare armed (`AG_ARMED_TAKE=true` in November; the
  v0.6.x releases took by default). With the v0.7 default (unarmed) the spare sends `TAKEOVER WITHHELD` at the same
  point and the operator moves the identity.
- **Builds.** The v0.6.7 and v0.6.9 release candidates and releases; development builds of the v0.7 line (2–4 November),
  the release candidates (4–5 November) and the `v0.7.0` tag (9–11 November). The daemons at `v0.7.0` differ from rc2 in
  the version line only: `git diff v0.7.0-rc2 v0.7.0 -- solana-primary-failover.sh solana-standby-failover.sh`.
  From rc1 (commit `6f8cf00`) to the tag the spare's daemon changes in the version line and one comment. The holder's
  daemon gains the `STAKED IDENTITY SILENT` page and the six-round connectivity default; its hung-holder functions
  are byte-identical.
- **Baselines.** Before the November series two measurements were taken with the failover daemons off (a restart of
  B's validator, a 90 s isolation of B). They are not counted below.

## 1. June–July 2026 — v0.6.7 and v0.6.9 (TowerBFT, testnet)

| Date | Fault | Result | Runs |
|---|---|---|---|
| 06-28 | Full outbound cut on A | A stepped down by the Internet-lost rule about 12 s after the cut; B took 67 s after the votes stopped; 65 s between the two; no overlap. The cut also severed the operator's ssh to A — a runbook lesson | 1 |
| 06-29 | Packet loss on A: a sustained 40 % loss, then flapping `tc netem` 95 % loss + 400 ms, 6 s on / 12 s off, about 8 cycles | 0 switches on either node; in the flapping run the vote account stayed within about 4 slots of the tip | 2 |
| 06-29 | A proxy fed B "delinquent but still voting" (B in `DRY_RUN`) | no take for 3.5 minutes while the holder's votes advanced; after real silence, `WOULD TAKE` 113 s later | 1 |
| 06-29 | **Outbound-only cut on A, release candidate 1** | 🔴 **B took 25 s before A stepped down** — both held the identity for about 25 s; A's votes could not land, so the chain saw no double vote. A blind spot of the self-fence (A still received blocks). Release blocked | 1 |
| 06-29 | The same cut, release candidate 3 (own-vote-lag rule added) | A fenced itself at +35 s (its votes lagging 93 slots for 22 s); B took at +83 s; 48 s between the two; no overlap. This run was the gate for v0.6.7 | 1 |
| 06-29 | Full outbound cut on A, repeated during that gate | A stepped down at +35 s by the Internet-lost rule; B took at +101 s; 66 s between the two | 1 |
| 06-29 | Healthy soak, armed, 1 h 33 min | 0 false actions; own-vote lag never above 6 slots | 1 |
| 06-30 | A's local RPC blocked while it kept voting | A fenced itself at +33 s, 86 s before B took; no overlap | 1 |
| 06-30 | `DRY_RUN` series: 18 induced faults (local RPC blocked, outbound-only cuts) | the self-fence decision fired at 33–35 s each time (detection only: `DRY_RUN` stops before the identity change); 0 false decisions; B's vote-liveness gate held a take back 8 times | 1 |
| 07-02/03 | Pre-release gate of v0.6.9: local RPC blocked on A; the same cut on B right after it took; outbound-only cut on A | A fenced itself and B took (84 s with no holder); B gave the identity back and did not re-take inside its 600 s lockout; A fenced itself on its own vote lag (87 slots / 21 s) and B took 48 s later. A first attempt at the third drill was invalid: a firewall rule shadowed the cut | 3 |
| 07-04 | The v0.6.9 final gate: local RPC blocked on A | A fenced itself at +33 s; B took at +117 s | 1 |
| 07-04 | The same cut on B right after it took | B gave the identity back after 31 s of silence and refused to re-take for the 600 s lockout | 1 |
| 07-04 | Outbound UDP cut on A, twice | A fenced itself at +33 s (lag 82 slots / 20 s) and at +39 s (98 slots / 23 s); B took at +131 s in the second run, after its lockout had ended | 2 |
| 07-04 | The failover daemon on A restarted (A unstaked at the time) | state restored, no action | 1 |

## 2. August 2026 — mainnet (v0.6.9, TowerBFT) — not drills

| Date | What happened | Result |
|---|---|---|
| 08-10 08:45 UTC | The primary's host was powered off | the armed spare took the staked identity 60 s after the anchor, every gate logged — [`2026-08-production.md`](2026-08-production.md) |
| 08-10 | During the manual return the validator was started on an unexpected identity | the spare went inert with only a warning in its log; changed to a critical page in the field round — [`../audits/2026-08-field-round.md`](../audits/2026-08-field-round.md) |

## 3. November 2026 — the v0.7 line under Alpenglow (testnet)

### 3.1 The holder fails

| Fault on A | A's own daemon | B | Build | Runs |
|---|---|---|---|---|
| Network isolated, 60–150 s | stepped down at +15…+22 s (three failed connectivity rounds) | unarmed: page at +72 s. Armed: took at +102 s (delay 90) and at +68…+71 s (delay 60) | dev builds, 2–4 Nov | 4 |
| Network isolated just before an epoch boundary | stepped down at +36 s (six rounds, the shipped default) | armed: took at +70 s; the boundary came 53 s later and voting continued across it | release candidate, 5 Nov | 1 |
| Validator killed (`SIGKILL`) | systemd restarted it on its unstaked identity within 3 s; healthy again at +193 s | unarmed: page at +65 s. Armed after the kill: took, the first take under Alpenglow (no timing: the spare was armed late). Armed in steady state: took at +103 s (delay 90) | dev builds, 2–3 Nov | 3 |
| Validator frozen (`SIGSTOP`) for 120 s and for 151 s, before the hung-holder rule existed | 🔴 one page and nothing else; it voted again when resumed | unarmed: page at +71 s in the first run | dev build, 2 Nov | 2 |
| Validator frozen, after the hung-holder rule was added | page at +9 s; hard stop at +47 s — but two **false** "hard stop failed" pages | armed: took at +66 s | rc1 candidate, 4 Nov | 1 |
| Validator frozen, after that fix | page at +8 s; hard stop at +47 s; confirmed down at +64 s | armed: took at +68 s | rc1, 4 Nov | 1 |
| Host rebooted (once after 105 days of uptime) | came back on its unstaked identity | armed: took about 70 s after A's last vote, and 79 s after A stopped answering | rc1 candidate and rc1, 4–5 Nov | 2 |
| Operator error: the identity moved back to A without `authorized-voter add` | A could not vote; its daemon demoted it at +45 s | armed: took at +66 s | rc1 candidate, 4 Nov | 3 |
| Network isolated for 20 s (a blip) | 🟠 with three rounds A stepped down at +17 s and B took at +69 s; with six rounds (now the default) no demote and no page | — | rc1, 5 Nov | 2 |
| 20 s freeze of the validator | one page at +10 s, no action | — | rc1, 5 Nov | 1 |

### 3.2 Something else fails — nothing should happen

| Fault | Result | Build | Runs |
|---|---|---|---|
| B isolated for 150 s | 0 takeover pages; one "not ready to judge" warning | dev build, 2 Nov | 1 |
| The link between A and B cut for 120 s | 0 pages, 0 actions — the daemons have no channel between them | dev build, 2 Nov | 1 |
| Both external RPC providers unreachable from A for 240 s | A kept the identity; 0 pages | rc1, 5 Nov | 1 |
| B's host rebooted | its daemon was back 35 s later; 0 pages on A | rc1, 5 Nov | 1 |
| B's host rebooted while its failover unit was not enabled (a hand-installed development build) | 🟠 no daemon on B after the boot: the pair had no spare for 22 minutes, until the unit was enabled and started. The release installers enable the unit | dev build, 3 Nov | 1 |
| The failover daemon killed on B, then on A while it held the identity | systemd restarted it in 12–13 s; roles unchanged; 0 pages | rc1, 5 Nov | 2 |
| Soaks: 30 minutes, about 12 hours, 2 hours on the `v0.7.0` tag | 0 false pages, 0 take attempts | 2–9 Nov | 3 |

### 3.3 The spare holds the identity and fails

| Fault on B (holding) | Result | Build | Runs |
|---|---|---|---|
| Network isolated | gave the identity back at +72 s — 42 s later than its 30 s threshold, because the cycle was waiting on external reads (a named limit) | rc1 candidate, 4 Nov | 1 |
| Validator killed | restarted unstaked; once healthy again B re-took its own identity at +255 s | rc1, 4 Nov | 1 |
| Validator frozen | one page at +8 s and no hard stop: the spare's daemon has no hung-holder rule yet (a named limit) | rc1 candidate, 4 Nov | 1 |
| B's daemon stopped and its validator killed, twice | 🔴 A, unstaked, stayed silent for 7 and 12 minutes | rc1, 4–5 Nov | 2 |
| The same, on the release | A paged `STAKED IDENTITY SILENT` at +106 s | **`v0.7.0`**, 9 Nov | 1 |

### 3.4 Blindness, planned moves, and what the client does

| Drill | Result | Build | Runs |
|---|---|---|---|
| Both external providers unreachable from the armed spare, then A isolated | no take while blind; the take came exactly 60 s after the providers were reachable again (+275 s) | rc1 candidate, 4 Nov | 1 |
| Planned warm swap A → B with a scripted gate | the staked identity was silent for 15.1 s (10.6 s of it the gate's own wait); then held for 603 s without a missed vote | 2 Nov | 1 |
| The swap back, aborted by the gate | the gate saw one more vote land and refused; B took the identity back; about 12 s of silence | 2 Nov | 1 |
| Deliberate duplicate: the operator set the staked identity on B while A held it | agave on A logged a duplicate instance at 6.0 s and exited at 7.9 s; in the 5.97 s of overlap the two nodes cast 29 **identical** votes — duplicates, not conflicting votes | dev build, 2 Nov | 1 |

### 3.5 Not a drill: the holder restarted for an upgrade (2026-11-10, `v0.7.0`)

The operator restarted A's validator to move it to 4.5.0-beta.0 while it held the identity. A's daemon paged
`PRIMARY UNREACHABLE WHILE STAKED` at once; at its 30 s mark the hung-holder rule declined to stop the validator
("the validator process changed … it restarted, it is not hung"). B, unarmed, saw the vote lag 6 s after A's page,
filled its 7-of-10 window in 8 s, and paged `TAKEOVER WITHHELD — Alpenglow mode` 69 s after A's first page. Nothing
took the identity; the operator moved it back.

## What the live runs found, and where each was fixed

| Found | By | Fixed in |
|---|---|---|
| The spare could take before an outbound-only-partitioned holder stepped down | the 06-29 drill | v0.6.7 (own-vote-lag self-fence), re-run the same day |
| An unexpected identity silently disabled the spare's protection | the 08-10 mainnet incident | the 2026-08 field round (critical page) |
| A frozen validator kept the identity; nothing acted | the 2 Nov freeze | v0.7 hung-holder rule (hard stop after 30 s of evidence) |
| False "hard stop failed" pages | the 4 Nov freeze | rc1: a requested stop, and a wait for the process to exit |
| Nobody paged when the spare's host died while it held the identity | the 4–5 Nov drill | rc2: `STAKED IDENTITY SILENT` |
| A 20 s blip demoted the holder | the 5 Nov drill | rc2: six connectivity rounds by default |

Five of the six were re-run live after the fix: sections 1 and 3 show each of those faults before and after. The
August finding was not re-run on a live pair; `tests/test_unknown_identity_alert.sh` covers it.

**Found and not fixed in v0.7.0:** no hung-holder rule on a spare that holds the identity;
the spare's give-back can be delayed by blocked external reads; a spare that reboots keeps its 600 s re-take lockout;
a page at 10 s for a freeze shorter than the 30 s rule; the validator-version floor pages but does not block an armed take.

## Counts

58 runs (18 in June–July, 40 in November) over 19 weeks: 52 with an induced fault, 4 soaks with none, and 2 planned
swaps. These are the sums of the **Runs** columns above. Three unplanned events came on top: two on mainnet in August,
one on the test pair in November. More than 30 distinct fault scenarios; more than 20 automatic takes by a spare, one of
them the unplanned mainnet event; no conflicting votes observed in any run.
