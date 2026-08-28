# Safety model

## Prime directive

**Never let two nodes hold and vote the same staked identity at the same time (double-sign).**

Every decision in this system is designed to fail toward *unstaked / stop / page the operator* rather
than toward two nodes voting. Availability loss (a brief voting gap) is always preferred over a
double-sign.

## The cross-node invariant

A spare must not take the staked identity until the previous holder has **provably relinquished** it.
Two independent mechanisms enforce this:

1. **Holder self-fence (~30s).** A PRIMARY that loses its local RPC, stops advancing its slot, or whose
   own votes stop landing (egress-only partition) demotes *itself* to its unstaked identity. A node on
   its unstaked identity structurally cannot vote the staked account.
2. **Spare takeover delay + vote-liveness fence.** The STANDBY waits `TAKEOVER_DELAY`
   (default **60s** = the holder's ~30s self-fence worst case + a 30s cross-node margin) **and** confirms
   via external RPC that the staked vote account has **stopped advancing** before it takes. Gossip
   presence alone is treated as advisory (a staked identity lingers in gossip for ~48h), so the
   authoritative signal is vote-liveness, not gossip.

```
t0        PRIMARY isolated
t0+~30s   PRIMARY self-fences → unstaked           (holder relinquishes)
t0+60s    STANDBY confirms vote frozen → takes     (spare takes)
          └─ 30s margin between the two: no overlap
```

A hand-edited `TAKEOVER_DELAY` below the safe floor **refuses to start** (opt-out only via
`ALLOW_UNSAFE_TIMING=true`, for labs). For a 3-node setup the BACKUP floor is stricter still — it must
also outwait the STANDBY's takeover becoming externally visible.

## Failure directions

| Situation | Resolves toward |
|---|---|
| Holder loses local RPC / frozen slot / egress-only | self-fence to unstaked |
| Ambiguous whether the holder relinquished | spare **does not** take (waits / pages) |
| Promoted STANDBY later isolates | self-fence + 600s re-take lockout |
| A demote (`set-identity`) wedges | escalate to stop the validator + page |
| Timing config unsafe | refuse to start |
| Both external RPCs unreachable | cannot confirm → **hold**, do not take |
| External RPCs stay down or flap | the hold is **indefinite** while blindness/flapping persists — a real, measured outcome (externals blinking one cycle per <60s starve the takeover for the whole outage) — and **paged** via `TAKEOVER_STARVATION_ALERT_SECS=300`, with a resolution notice at episode close |

## Detection

- **Local delinquency** via a sliding window (DDoS-flicker resistant), confirmed on an external tier.
- **Frozen slot / dead RPC** (isolation the node can see).
- **Egress-only partition** — the node still reaches the internet and its RPC answers, but its *own*
  votes stop landing on-chain; detected by comparing its own last vote against the cluster max.

## What has been tested

Beyond the 36 automated suites, the release was validated by **live failovers on a real two-node
testnet stack** (agave, systemd, real `set-identity`), with a 1 Hz on-chain observer recording the
vote account throughout. Each scenario below was run end to end and the observer confirmed **no
overlap** — at no point did two nodes hold the staked identity:

| Scenario | What was induced | Observed |
|---|---|---|
| Local RPC isolation | holder's local JSON-RPC blocked | holder self-fenced to unstaked at ~31s → spare took over on the timer |
| Egress-only partition | holder's outbound UDP dropped (it still received blocks) | holder detected its own votes weren't landing (lag 82-98 slots) and self-fenced at ~20-23s |
| Promoted spare isolated | same cut applied to the node that had just taken over | it self-fenced too, and refused to re-take for the 600s lockout |
| Holder daemon restart | `systemctl restart` while staked, with a stale persisted baseline | no false demote; the node kept voting |

**Beyond the staged scenarios, the system has one real, unplanned activation on record.** On
2026-08-10 at 08:45:52 the armed mainnet standby detected its primary gone (the host had been
powered off), walked every gate — local health, a 10/10 delinquency window, external confirmation,
advisory gossip, a frozen vote-liveness read — and took the staked identity exactly 60 s after the
anchor; the validator picked up voting on the new host. Every gate decision is in the log.

**Measured loop cadence** (four armed nodes, two of them mainnet, ~3.2 h windows each): 3.12–3.33 s
per cycle at `CHECK_INTERVAL=3` — mainnet load does not inflate the loop (per-cycle overhead
0.1–0.3 s over the sleep).

Automated suites additionally drive the real decision functions (self-fence, takeover gating,
cross-node timing) with mocked I/O, and every safety fix ships with a control that fails when the fix
is reverted. **Known limit:** these are function-level — they do not prove cross-process ordering
between two live systemd services. A chaos/E2E gate on real nodes is part of the v0.7 work.

## Residual risks (be honest with yourself)

### The big one: liveness is evidence, not a fence

The spare decides the old holder is gone by observing that its **vote account stopped advancing**.
That is *corroboration*, not proof of incapacity. A holder can stop being seen to vote and still be
able to vote:

- wedged on its admin RPC while the validator process keeps running;
- partitioned onto a minority fork whose votes you don't observe;
- votes not reaching the specific RPC providers you polled;
- paused and then recovering.

The mitigation stack (holder self-fence, cross-node margin, hard-stop escalation, re-take lockout)
covers the cases the **holder can detect about itself**. It cannot cover a holder that detects nothing
and later resumes. Closing that requires **external fencing (STONITH)** — a *confirmed* power-off or
network fence of the old host, verified to a terminal state — which this release does not perform.

**Consequence:** fully unattended mainnet failover is not yet a property of this tool. Run it in
`DRY_RUN`, on testnet, or with a human in the loop who fences the old node before the spare is
promoted (there is no built-in assisted mode). See [SPLIT-BRAIN-RESIDUAL.md](SPLIT-BRAIN-RESIDUAL.md) for the full analysis.

### Known hardening items (tracked)

- **Fencing** (v0.7): watchdog self-fence on the holder + a relinquish proof on the spare (verified
  demote / watchdog-elapsed); external fence providers (STONITH-style, cloud/IPMI) remain v0.8 options
  on the same interface.

### Fence rot (v0.7, armed hosts): holder-side self-enforcement

The `failover arm` pairing token attests the holder's fence **at pairing time only**. **After
pairing, `watchdog-elapsed` soundness rests on holder-side self-enforcement; the spare cannot see
fence rot** (a masked fence unit, a drop-in re-adding `Restart=`, a disarm) — there is no channel,
by design. The armed holder therefore re-verifies its own *effective* fence properties every
`FENCE_ROT_CHECK_SECS` (default 60 s) and treats **armed + staked + fence-broken** as fence-worthy,
under this escalation contract:

1. **Immediate CRITICAL page** on the first *verified* fence-killing drift, naming the exact broken
   element and the exact fix command, re-paged per `ALERT_THROTTLE`. Drift that verifiably does
   *not* kill the fence now (e.g. a `WatchdogSec` config change that affects only the next start)
   pages CRITICAL too but never starts a demote clock; a failing `systemctl` is *cannot-verify*,
   not rot — it pages after a persistent blind streak and never demotes.
2. **`FENCE_ROT_GRACE`** (default 1800 s, floor max(600, `ALERT_THROTTLE`)): the window between
   first detection and any action — one systemd typo must not take down a healthy production
   validator faster than a human can read a page. A healed fence closes the window; a later
   re-rot starts a fresh one.
3. **Graceful self-demote** only if the rot persists past the grace *and* the node still verifiably
   holds the staked identity: the standard set-identity-to-unstaked path, which the spare consumes
   as a verified-demote proof — an automatic failover to the healthy side. An unreadable identity
   at expiry demotes nothing (that would be a guess); paging continues.

The availability tradeoff is accepted and bounded: a broken-but-loud fence costs (at worst) one
graceful failover to the healthy spare after ≥30 minutes of CRITICAL paging — against the
alternative of a spare consuming `watchdog-elapsed` over a holder whose fence silently no longer
exists, which is the double-sign class this tool exists to prevent. During the grace the holder is
voting and paging, so the spare's silence-based path cannot fire against it: the window itself adds
no double-sign exposure.

### Verified-demote (G2) — what it proves, and what it cannot see (v0.7, armed spares)

The armed spare's strongest relinquish proof inverts the polarity of every check above: instead
of evidence that the holder *looks gone* (an absence, always forgeable by a broken view), G2
demands a **positive observation that the demoted state is live *now***. The holder's *unstaked*
gossip identity must be observed **at the staked identity's exact endpoint** (`set-identity`
keeps ports, so a self-fenced holder re-advertises its unstaked key at exactly the endpoint its
staked key last used) at T1 **and still be there ≥60 s later** on the **same two pinned RPC
vantages** from distinct failure domains. The CRDS mechanics make that hold load-bearing: a live
publisher re-signs its unstaked ContactInfo every ~7.5 s, while a stale entry (publisher gone,
or flipped back to staked) cannot survive 30 s in a remote table — so survival across the 60 s
hold proves a live process holds the unstaked key on that box, and the vote gates make a box
whose validator runs unstaked unable to sign staked votes. An entry at a *different* endpoint
proves only that some publisher exists elsewhere and is **not** the proof.

G2 treats its own environment as a suspect. Each snapshot is **one JSON-RPC batch** — a single
POST carrying `getSlot(confirmed)` *and* `getClusterNodes`, with fresh per-request ids — so the
freshness anchor rides **inside the very response that carries the proof**. Every one of these
reads *cannot-determine*, never proof:

| Layer | What it refuses | What it does **not** claim |
|---|---|---|
| batch shape | an answer that is not a 2-element JSON-RPC array (no batching, or a proxy that split our request) | — |
| id echo | any member (or the `getBlockTime` read) not echoing the id this process just sent — a stored/replayed answer carries stored ids | it cannot stop an intermediary that *rewrites* ids in flight |
| slot advance | a vantage whose own confirmed head, batched into the proof-bearing response, advanced fewer than 60 slots across the hold — a frozen or replayed head. **Trusts no clock** | a stalled *cluster* also lands here: cannot-determine, availability, never a take |
| cluster-time skew | a snapshot whose `getBlockTime`(that batched slot) sits more than ±25 s from the spare's clock | it assumes **the spare's own clock is correct** (see residuals); the slot-advance layer is the clock-free backstop |
| node-table advance | a `getClusterNodes` result byte-identical across the 60 s hold — a **totally frozen** response, i.e. a naive cache | it does **not** prove the unstaked-at-endpoint entry was re-observed live: real mainnet tables churn constantly, so a frozen proof entry riding on other nodes' churn passes this compare. Anti-replay duty belongs to the batched slot above |
| cross-vantage identity | byte-identical node tables from the two "distinct" vantages — one source wearing two names | byte-distinctness is **necessary, not sufficient**: a source that varies anything per vantage (a nonce, a re-serialization) passes. The enforceable half is at the arm |
| vantage distinctness (arm) | identical URLs / shared hostname (daemon startup, CRITICAL page, whole run) and identical **resolved address sets** (`REFUSE[P6-vantage]`) | two genuinely different IPs belonging to **one provider** are indistinguishable from here — an operator responsibility, stated plainly |
| batch capability (arm) | a vantage that cannot serve the batch at all (`REFUSE[P6-batch]`) | — |

Mid-hold absence on any vantage is **not-proven** plus a full restart of the attempt — the
flip-then-flip-back kill. A spare that observes *itself* staked closes the episode outright, so an
attempt can never span the spare's own staked tenure.

**Why byte-distinctness is worth keeping even though it is not sufficient:** a single source that
*keeps* a stale unstaked entry across the whole 60 s hold must do one of two things. Either it
freezes its CRDS table — a local clock slow enough to reject fresh gossip stops its body churning,
and the node-table advance and cross-vantage layers fire — or it genuinely re-signs the entry,
which means a live publisher, i.e. the true proof. That churn-versus-purge tension is the real
guarantee; anyone relaxing the advance layer is removing that, not a redundant checksum.

**What G2 cannot see, named honestly.**

1. **After T2.** The verdict rests on the T2 read. A holder that flips back to staked and votes
   *after* T2 is invisible to any snapshot-based proof — that direction is owned by the
   mutation-edge re-check (`_fresh_proof_recheck`'s staked-vote pin, which aborts on any vote
   advance) plus the edge age bound (`PROOF_MAX_AGE`); the provider withdraws and re-proves a
   verdict older than that bound rather than serving it.
2. **An active, protocol-aware intermediary.** Binding the anchor into the batch raises the bar
   from *passive cache / naive replay* to *active tampering*: an intermediary that splits our
   batch, forwards `getSlot` to a live node and answers `getClusterNodes` from storage under our
   id still mints. That was executed against this build and is **not** defended — it is the
   named residual, and no unsigned snapshot protocol clears it. The same applies to an
   environment that fabricates fresh cluster times for old slots.
   **On a shared-vantage host this residual is not bounded by the composition** — see
   *Shared vantages* below. That is the one place the severity statement further down stops
   applying, and it is the default configuration, so it is stated here rather than in a footnote.
3. **A slow spare clock.** The ±25 s freshness compare measures cluster time against *this
   spare's* wall clock, so a spare whose clock drifts by R seconds would collapse the skew of an
   R-second-old replay toward zero. The clock-free slot-advance layer is the backstop.
4. **A slow vantage *local* clock.** The ±25 s budget bounds a vantage's **chain-head lag**, not
   its local system clock — and CRDS purge fires on that local clock. A vantage that is caught up
   on-chain but whose system clock is slow retains a stale unstaked entry longer than the 15 s /
   30 s expiry math assumes. One honest vantage forces not-proven, since it purges on time; the
   both-vantages-slow case is caught, where it is caught at all, by the churn-versus-purge
   argument above (a clock slow enough to retain the entry is slow enough to reject fresh gossip,
   which freezes the body), **not** by the freshness detector. See the deployed-constants note
   below.
5. **One provider on two addresses.** See the table.

Layered refusal is still the posture — every layer above has its own red *and* a neuter control
proving the attack falls through to a named surviving layer, plus an all-layers-neutered control
that restores the forged acceptance (`tests/test_g2_provider.sh` §4/§5). And in v0.7 the gate is
not yet wired into any take path at all (wiring is a later, separately reviewed step).

**Severity of a false G2 proof, stated exactly.** The proof gate is an *additional* requirement in
front of the staked mutation, never a trigger for one: the pre-existing, live-tested v0.6.x path
(delinquency detection, the vote-frozen observation, `_fresh_proof_recheck`) must still pass on its
own. A false PROVEN therefore cannot by itself cause a take — it can only fail to *block* a take
that logic already authorized. A double-sign needs **both** a false G2 proof **and** a false-frozen
vote observation of a holder that is in fact alive and voting. **Read the next section before
relying on that sentence: on the default configuration it is true and empty.**

**Shared vantages — where the additivity argument stops holding (the default config).** G2 defaults
`G2_VANTAGE_A`/`G2_VANTAGE_B` to `TIER2_RPC`/`TIER3_RPC`, and every vote-liveness reader in the
daemons iterates exactly those two endpoints (`for rpc in "$TIER2_RPC" "$TIER3_RPC"`). On such a
host the two halves named above are **not independent**: the same active, protocol-aware
intermediary that splices `getSlot`/`getClusterNodes` into a false G2 proof can equally proxy the
tip live while freezing the staked account's `lastVote` into a false-frozen vote observation. One
capability supplies both halves, so the composition adds nothing and residual 2 above is
**unbounded by it**. (A *naive* freeze is still caught by the tip-guard; an active one is the same
"passive closed, active open" boundary G2 draws everywhere else.)

This is **not** refused, deliberately: most operators run exactly two RPCs, and refusing to arm
would trade a named residual for no spare at all. It is **measured and stated**: `failover arm`
compares each vantage against each tier — by normalized URL, by host, and by resolved address set
where a resolver exists — and prints which vantage matched which tier by which comparison, the
consequence, and the fix, both at precondition P6 and again in the end-of-summary; the armed
daemon repeats a URL-level version of the same statement as a startup `WARN` (it does no DNS — the
arm owns resolution, so a shared vantage hiding behind two hostnames is visible at the arm and
invisible to the daemon).

**The way back is a third endpoint in a separate failure domain:** point `G2_VANTAGE_A` and/or
`G2_VANTAGE_B` in `failover-standby.env` at an RPC run by a *different operator* — not another
hostname or another API key for one you already use — and re-run `failover arm`. The arm then
prints the measured "vantages are SEPARATE from the vote-liveness tiers" line, and the additivity
statement above becomes load-bearing again.

**Deployed constants, and why the number moved twice.** This build deploys `G2_DELTA = 60 s` and
`G2_CLOCK_BUDGET = 25 s` (and `G2_SLOT_ADVANCE_FLOOR = G2_DELTA` slots), derived at one site as
30 s (the provable CRDS bound: 15 s unstaked-origin expiry + ≤ 15 s late re-insert) + 25 s clock
budget + 5 s purge granularity and rounding. The history, recorded rather than tidied away:

1. The project's own CRDS-timeout research record recommends **DELTA = 60 s with a ≥ 25 s vantage
   clock-error budget**, and states its slow-vantage-clock residual against *that* number ("both
   clocks being >25 s wrong simultaneously").
2. The v0.7 design addendum §2.4 deployed **50 s / 20 s** instead, for one stated reason: to fit
   the whole hold inside the 60 s un-armed takeover timer.
3. That reason died when the proof gate made floors **per-provider**: `verified-demote`'s floor is
   its own hold, never `TAKEOVER_DELAY`. Nothing had depended on the fit since, and nobody noticed
   until the constants were re-read against the record.
4. So the constants are back to the record's 60 s / 25 s.

The cost, named: `verified-demote`'s own branch answers about 10 s later than it did. The timer
path is **unchanged** — the gate is additive, so a later G2 answer can only delay a take the
proof would have permitted, never enable one. What is bought is residual 4 above: a 25 s budget
is the one the research record's residual is actually stated against, so the earlier 20 s left
*less* headroom for a slow vantage local clock than the analysis assumed.

**The stale-bound re-arm residual (v0.7, named):** the pairing token carries the holder's
`relinquish_bound` as of pairing generation N, and the spare derives its silence (elapsed) floor
from those stored bounds. A holder later re-armed with a **larger** bound whose operator forgets to
re-pair leaves the spare's elapsed floor resting on the old, smaller bounds — the spare could then
take on silence before the holder's real worst-case relinquish completes: a double-sign direction.
The spare **cannot detect this by construction**: the token is configuration, not state — there is
no holder→spare channel (the same by-design gap as fence rot above). The protection is operational
and mechanical on the holder side: the holder's `failover arm` refuses to complete without printing
the new token ("re-pair every spare" is ceremony, not advice — Block 5.3), and the spare's own arm
re-validates its stored token at every arm. The residual stays and is stated plainly: between a
holder re-arm and the next spare re-pair, the spare's elapsed floor rests on stale bounds.
- **Evidence quality** (v0.7): bind `VOTE_PUBKEY` to `STAKED_PUBKEY` via `getVoteAccounts`
  (`nodePubkey`) before acting. Landed in v0.7: the paired liveness sample is provider-pinned, and
  *any* forward movement of `lastVote` now counts as "alive" (`VOTE_LIVENESS_EPSILON=0`, which
  presumes that pinned pair).
- **Failure handling** (v0.7): escalate on *any* unverified demote postcondition, not only on
  command timeouts; atomic state writes; monotonic (boot-time) safety timers.

### Availability-side starvation (blind or flapping externals)

While the external RPCs are unobservable — hard-down or blinking — the takeover holds
**indefinitely**: unobservable time counts as life, and every blind cycle restarts the countdown in
full. This is a real, measured outcome (externals blinking one cycle per <60s starved the takeover
for the whole outage), not a theoretical corner. "Fails safe" here means **does not act, loudly**:
the daemon pages rather than guesses (`TAKEOVER_STARVATION_ALERT_SECS`, default 300s, repeating per
`ALERT_THROTTLE`, with per-episode hold diagnostics and a resolution notice at episode close).

### Other standing notes

- The system trades availability for safety: a genuine failover has a voting gap of roughly one
  takeover delay. That is intentional.
- The gossip **fast-path** (Option A, off by default) is a conservative, fail-closed optimization that
  in practice rarely fires; the proven path is the timer + vote-liveness fence.
- Tests are function-level with mocked I/O: they exercise the real decision functions, but do **not**
  prove cross-process ordering between two live systemd services. A chaos/E2E gate on real nodes is
  required before unattended operation.
- On-chain slashing for double-signing is not (yet) enforced by the Solana network, but this system is
  built as if it were — do not weaken the fences.
- Always test on testnet, and roll to mainnet one node at a time.
