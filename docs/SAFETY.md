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
   authoritative signal is vote-liveness, not gossip. Since v0.7 (Block 6.3.1) the last read before
   the take is the spare's **own** node: one bounded read (`curl -m 2` + a watchdog pet) of its
   confirmed view that withdraws the take if the holder shows voting there, if the read fails, or if
   the spare's own head is not advancing — so every take lands up to that bound later
   ([the spare's own view](#the-spares-own-view-v07-block-631)).

```
t0        PRIMARY isolated
t0+~30s   PRIMARY self-fences → unstaked           (holder relinquishes)
t0+60s    STANDBY confirms vote frozen → takes     (spare takes)
          └─ 30s margin between the two: no overlap
```

A hand-edited `TAKEOVER_DELAY` below the safe floor **refuses to start** (opt-out only via
`ALLOW_UNSAFE_TIMING=true`, for labs). For a 3-node setup the BACKUP floor is stricter still — it must
also outwait the STANDBY's takeover becoming externally visible.

**The invariant, measured (v0.7, Block 6.3.1 — D6).** The two timers above are designed against each
other; this table measures them against each other, per failure class. **t = 0 is the holder's last
landed vote.** The holder column is the moment its own monitor demotes it (measured on the real
`check_self_fence_isolation` / `load_state` / startup path at `CHECK_INTERVAL` 1 / 3 / 5 — the
driver of the 6.3 holder panels); the spare columns are the **earliest** moment a spare can take (the
un-armed timer path) or the watchdog-elapsed provider can **mint** (armed — the proof gate is wired
only in 6.4, so this is the earliest proof, labelled as such), measured on the real standby main loop
(`tests/test_own_view.sh` (6)) with a dead holder behind tiers that show it frozen, at the assumed 2.5
slots/s and the measured mainnet 3.7:

| Spare (earliest, from the last vote) | `MAX_DELINQUENT_SLOTS=15` (the wizard's) | `MAX_DELINQUENT_SLOTS=0` (daemon/template default) |
|---|---|---|
| un-armed timer path — take | **80 s** at 2.5 slots/s, **75 s** at 3.7 | **125 s** at 2.5, **105 s** at 3.7 |
| armed watchdog-elapsed — earliest mint | never at 2.5 (the rate layer never certifies the assumed rate), **121 s** at 3.7 | never at 2.5, **151 s** at 3.7 |
| armed verified-demote (G2) | only after the holder's unstaked identity is live at its endpoint for 60 s — i.e. at least the holder's fence + 60 s, by construction; never for a holder that does not fence | same |

| Holder failure class | Holder fence (from the last vote) | Against the fastest spare (80 / 75 s) | Against `MAX_DELINQUENT_SLOTS=0` (125 / 105 s) | Against the armed mint (121 / 151 s at 3.7) |
|---|---|---|---|---|
| dead local RPC (validator not voting) | 30 s | margin 50 / 45 s | margin 95 / 75 s | margin ≥ 91 s |
| frozen slot | 29 / 27 / 25 s (`CHECK_INTERVAL` 1 / 3 / 5) | margin ≥ 46 s | margin ≥ 76 s | margin ≥ 92 s |
| egress-only (own votes not landing, N6) | 20 / 21 / 20 s | margin ≥ 54 s | margin ≥ 84 s | margin ≥ 100 s |
| garbage answers (non-canonical slot) | 29 / 27 / 25 s | margin ≥ 46 s | margin ≥ 76 s | margin ≥ 92 s |
| **(1)** still-frozen restore over a corrupted slot — the monitor restarted 30 / 45 / 63 s after the last vote | grace 30: 75 / 90 / 108 s; grace 0: 45 / 60 / 78 s (restart + 45 / + 15 at every interval) | **CROSSING**: grace 30 — 75 s ties the 75 s spare (5 s before the 80 s one), 90 and 108 s land 10–33 s after the spare can take; grace 0 — 78 s lands 3 s after the 75 s spare | grace 30: 108 s lands **3 s after** the 105 s spare (crossing); every other row holds (by 15 s or more) | margin ≥ 13 s |
| **(1)'s restart member** — a second restart 1–4 cycles into the first instance (`CHECK_INTERVAL` 3, stops of 0–20 s) | 60–89 s after the FIRST restart: **90–119 s** (first restart at +30) / **123–152 s** (at +63) | **CROSSING on every row**: 10–77 s after the spare can take | at 2.5: the +63 rows past 125 s cross (by up to 27 s); at 3.7: every row past 105 s crosses (by 1–47 s) | +63 rows cross the 121 s mint (by 2–31 s) and, at 152 s, the 151 s one (by 1 s); +30 rows hold |
| **N7** fresh-start silent gap (RPC silent from a fresh start; garbage before any canonical answer) | **never** by the self-fence (un-armed: never, every class — executed, below); ARMED: never while the admin socket answers (class A), restart + 90 s when it is silent too (class B, below) | **CROSSING** (never fenced; an armed class-B holder restarted at the last vote fences at 90 s — still 10–15 s after this spare) | **CROSSING** for the never-fenced forms; class B at 90 s holds (by 15 s or more) | class A crosses; class B at 90 s holds (90 < 121) |

**Every CROSSING above is a double-sign exposure of this build, named here, not a margin.** They share
one shape: a holder monitor that restarts while its validator is stuck and must re-establish evidence
from a corrupted or empty baseline, fencing later than a spare with a fast detector can take. The
floor rule behind (1) (`SELFFENCE_RESTORE_CONFIRM_SECS`) trades exactly this against never fencing a
paused healthy holder ([the holder's residuals](#holder-self-fence-the-differential-bar-and-its-named-residuals-v07-block-63),
(1)). **The reviewer's framing for (1)'s restart member, checked:** "holder fences 45 s – ~95 s after
the restart vs an un-armed fast-detect spare taking ~65 s after the holder stopped voting" — the
direction is confirmed (every restart-member row crosses the fast-detect spare), the numbers corrected:
the holder fences **60–89 s after the first restart** at `CHECK_INTERVAL` 3 (60 + 3 s per cycle of
the first instance + the stop), and the fast-detect spare takes at **80 s / 75 s** (2.5 / 3.7 slots/s)
after the last vote — its episode opens only when the finalized bank shows the holder 15 slots late
(32 + 15 slots: 20 s / 15 s), then the 60 s delay. From the same t = 0 the restart member fences at
90–152 s: 10–77 s after that spare can take. The `MAX_DELINQUENT_SLOTS=0` default and the armed
provider keep more of the ordering, not all of it (the table).

**The silent-restart residual, by execution (armed and un-armed).** An armed holder's monitor sends READY
only after its first identity read (the admin socket), and extends its start only on positive startup
evidence. Executed in throwaway real-systemd containers — systemd **249** (Ubuntu 22.04, the fleet
floor) and **255** (Ubuntu 24.04) — with this build's primary daemon under the shipped monitor unit
(`Type=notify`, `WatchdogSec=30`, `TimeoutStartSec=90s`, `Restart=no`,
`OnFailure=solana-failover-fence.service …`) and a marker fence unit, from a fresh start (no persisted
state) with the local JSON-RPC silent (nothing listening), identical timelines on both versions:

- **class A — RPC silent, admin socket ANSWERING** (the holder's identity readable): READY at t+1
  (`active/running`), **no fence dispatch in 150 s**, no identity mutation — **the residual survives
  arming**: the monitor runs, its self-fence never gets a canonical baseline (N7), and nothing fences;
- **class B — both silent, the validator process present and wedged** (the admin calls hang to their
  timeouts): no READY; the start times out at **t+90** → `failed` → `OnFailure` dispatches the fence at
  t+90;
- **class B′ — both silent, the validator process gone**: the same, the fence at **t+90**.

**Un-armed**, the same three classes under the unit the primary wizard installs (`Type=simple`,
`Restart=always`, no watchdog, no `OnFailure`), same containers and versions: **nothing fences any of
them** — class A runs its loop (every cycle's self-fence read logs "no answer — treating as
validator-unreachable, NOT isolation"), classes B and B′ wait in startup for the validator; no fence,
no restart, no identity mutation in 150 s.

So arming closes N7 only where the admin socket is silent too (fenced ≤ 90 s after the restart); an
RPC-silent holder whose admin socket answers is fenced by neither the self-fence nor systemd, and
un-armed no silent class is fenced at all.

## Failure directions

| Situation | Resolves toward |
|---|---|
| Holder loses local RPC / frozen slot / egress-only | self-fence to unstaked |
| Ambiguous whether the holder relinquished | spare **does not** take (waits / pages) |
| Promoted STANDBY later isolates | self-fence + 600s re-take lockout |
| A demote (`set-identity`) wedges | escalate to stop the validator + page |
| Timing config unsafe | refuse to start |
| Both external RPCs unreachable | cannot confirm → **hold**, do not take |
| The spare's own node shows the holder voting, cannot answer its bounded read, or its own head is not advancing — at the take (v0.7, 6.3.1) | the take is **withdrawn** (the own-view veto) and the countdown re-anchors; no cooldown |
| External RPCs stay down or flap | the hold is **indefinite** while blindness/flapping persists — a real, measured outcome (externals blinking one cycle per <60s starve the takeover for the whole outage) — and **paged** via `TAKEOVER_STARVATION_ALERT_SECS=300`, with a resolution notice at episode close |

## Detection

- **Local delinquency** via a sliding window (DDoS-flicker resistant), confirmed on an external tier —
  read at the *finalized* commitment (the slow, reliable view triggers); since v0.7 (Block 6.3.1) a
  not-delinquent own-bank answer inside an open episode restarts the countdown, and the take itself is
  vetoed on the spare's *confirmed* own view (the fast view vetoes) — [the spare's own view](#the-spares-own-view-v07-block-631).
- **Frozen slot / dead RPC** (isolation the node can see).
- **Egress-only partition** — the node still reaches the internet and its RPC answers, but its *own*
  votes stop landing on-chain; detected by comparing its own last vote against the cluster max.

## What has been tested

Beyond the automated suites (`tests/run_all.sh` — its manifest pins the count, and CI checks the
README's), the release was validated by **live failovers on a real two-node testnet stack** (agave,
systemd, real `set-identity`), with a 1 Hz on-chain observer recording the vote account throughout.
Each scenario below was run end to end and the observer confirmed **no overlap** — at no point did
two nodes hold the staked identity:

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
vote observation of a holder that is in fact alive and voting. **Read *Shared vantages* below
before relying on that sentence: on the default configuration it is true and empty.**

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

### Shared vantages — the spare's observation surface (a standing property, v0.7)

A claim that two checks are independent is a claim about their **inputs**. This section states it
for the spare's whole take path — a standing property of the spare, not a residual of one proof
provider; each provider's section points here. Read from the code, and confirmed by execution
against the real main loop (`tests/test_elapsed_provider.sh` §11–§12, a file-backed clock so reads
take time).

**The premise under test is what `TIER2`/`TIER3` serve, in three forms** — each a measured case, not
an assumption about who is lying:

1. an **active intermediary** in front of both tiers: the tip proxied live, the staked account's
   `lastVote` frozen;
2. an **honest tier lagging but advancing**: the true chain, some seconds late — no adversary at all;
3. the spare **partitioned together with its tiers after the episode's pin** (co-frozen): on a side
   holding less than 2/3 of the stake the tower fails its depth-8 2/3 threshold within ~8 votes, so
   the spare's *processed* bank — the tower's last votable bank — stops, and the co-partitioned
   tiers' view (its max `lastVote`) stops with it.

(An earlier text had "tiers partitioned together with the spare, honestly serving a live tip". That
is not a physical state: a side under 2/3 stops voting within ~8 votes, and a side at or above 2/3
is the canonical chain, where the spare's own bank sees exactly the holder votes the tiers see.)

**Slot time.** Every seconds figure below was measured at **2.5 slots/s** (400 ms slots — the rate
the code's derivations assume, e.g. `N_HEAD = (MARGIN_ELAPSED − 1) × 5/2`). Mainnet **measured ≈ 3.7
slots/s** on 2026-09-26 (265–283 ms per slot: `getRecentPerformanceSamples` on the public
mainnet RPC, ten 60 s samples of 212–226 slots — re-run it to check), so the slot boundaries are the stable facts: the own
bank's delinquency rule is 128 slots (≈ 51 s at 2.5/s, ≈ 35 s at 3.7/s); *finalized* trails
*processed* by 32 slots (≈ 13 s / ≈ 9 s); `getHealth`'s distance is 128 slots; `N_HEAD` is 22 slots
since 6.3.1 (25 before: the mono clock's < 1 s truncation is now budgeted out of `MARGIN_ELAPSED`) —
8.8 s at its assumed rate, ≈ 5.9 s on today's mainnet: **stricter** than its derivation (more blind
reads — availability, never a take). A count of slots is only as many seconds as the cluster's rate
makes it, so watchdog-elapsed no longer assumes the rate: since 6.3.1 it measures **one** head — the
spare's own confirmed head, sampled on the take path — at two **times** across its silence span and
abstains (blind) unless that rate is provably ≥ 2.5 slots/s (`[elapsed-rate]`: `2·Δslot ≥ 5·(Δt + 1)`
over at least 24 s — the truncating clock makes Δt uncertain by 1 s); at a mint `N_HEAD`'s slots are
never more than `MARGIN_ELAPSED − 1` seconds of chain. (The two heads of one evaluation — the
payload's cluster-max and the own processed head, ≤ 1 s apart — give a lag, not a rate.) The cost,
named: a cluster running at exactly the assumed 2.5 slots/s is never certified — the provider does not
mint there (measured: t171 before → never; 2.525 slots/s t171 → t181; 3.7 slots/s t151 → t151;
`test_own_view` (4e)).
Measured at 3.7 slots/s, the timing race below opens its episode at t45 instead of t65 and takes at
t105 instead of t125; since 6.3.1 its veto boundary is the confirmed view's (t104 vetoed, t105 — the
take's own second — taken), where the 6.3 build's was the finalized lag's 32 slots (t96 vetoed, t97
taken after 8 s).

| Input | What reads it on the take path |
|---|---|
| **the spare's own node** (`LOCAL_RPC`) | Tier-1 health (`getHealth`); the own-bank delinquency check that opens the episode and fills the 7-of-10 window (`getVoteAccounts` at *finalized* — agave's default commitment, spelled out in every request body since 6.3.1 — and, when `MAX_DELINQUENT_SLOTS` > 0, a separate `getSlot` reference, also finalized, read FIRST (6.3 fix round 2): any gap between the two answers — a pet, a stall, a slow read — can only make the holder look MORE current, failing toward NOT opening an episode. Read after the payload, as before, the gap pushed a current holder toward "delinquent": a 3 s reference + a 7 s pet read a holder voting every slot as "Latency 25 > 15", and an armed spare took that live holder at t577, measured); since 6.3.1 a not-delinquent answer of that check inside an open episode restarts the takeover countdown and watchdog-elapsed's silence; the **own-head samples** (`getSlot`, *confirmed* — one per take-path cycle of an open episode and one at the head of each take function); the **own-view veto** at every take (one `[getSlot, getVoteAccounts{votePubkey}]` batch at *confirmed*, `curl -m 2`, after the fresh re-check); watchdog-elapsed's head cross-check (`getSlot`, *processed* = the tower's vote bank) and its rate layer (the own-head samples); the local identity that selects the take branch (the admin socket's contact info; `getIdentity` on frankendancer) |
| **`TIER2_RPC` / `TIER3_RPC`** | external confirm (`TIER2`'s `MAX_DELINQUENT_SLOTS` latency verdict re-reads the holder's `lastVote` AFTER its reference before it can confirm — 6.3 fix round 2); the vote-FROZEN observation, its pinned first sample and the freshness seam they write; the mutation-edge re-check; the gossip advisory (logged, never a gate); the fast-path timer skip (`peer_has_relinquished`, `getClusterNodes` — only with `WITNESS_FASTPATH=true`, default off: it skips the remaining delay, never Gate 2 or 3); watchdog-elapsed's silence — on **every** configuration; G2's two vantages **on the default configuration** |
| **`G2_VANTAGE_A` / `G2_VANTAGE_B`** pinned elsewhere | G2 only |
| **the pairing token** | the proof-gate posture; the derived floors (`elapsed_floor`, `N_HEAD`); watchdog-elapsed's registration, and its re-classification at every evaluation and every serve of a standing verdict |
| **the spare's monotonic clock** | the re-take lockout, the cooldown, the takeover delay and its anchor, the observation-span floor, `VOTE_LIVENESS_MIN_INTERVAL`, `EXTERNAL_CONFIRM_THROTTLE`, the fast-path stagger floor, G2's hold, the silence floor, the proof age edge |
| **the state file** (`STATE_FILE`, stamped with `BOOT_ID`) | the re-take lockout and the cooldown across a monitor restart (a mono stamp is honored only within the boot that wrote it) |
| **the spare's wall clock** | G2's cluster-time freshness compare (±25 s) — no other gate on the take path (alert throttles aside) |

**Where composition adds nothing: any two checks in the `TIER2`/`TIER3` row.** An active,
protocol-aware intermediary in front of those two endpoints — one that proxies the tip live while
freezing the staked account's `lastVote` — supplies, in one capability, the external confirm, the
vote-FROZEN observation and a clean mutation-edge re-check. The tip guard does not stand in its way:
it compares the reference tip against the **pinned first sample's** tip and the frozen path never
re-bases it, so it catches a freeze only **at or before** that pinned sample — a naive, whole-body
freeze that begins after the pin passes it too (measured with tiers frozen together with the spare:
frozen before the pin → held on both paths; after it → taken). Two instances matter for the proof gate.

**The G2 instance — on the default configuration.**
The standing condition, in the words the ceremony and the daemon log print verbatim: *G2 and vote-liveness SHARE VANTAGES: one compromised vantage supplies BOTH halves of the double-sign condition — a false verified-demote proof AND a false-frozen vote observation — so the proof gate's additivity does NOT hold on this host.* Mechanically: G2 defaults
`G2_VANTAGE_A`/`G2_VANTAGE_B` to `TIER2_RPC`/`TIER3_RPC`, and every vote-liveness reader in the
daemons iterates exactly those two endpoints (`for rpc in "$TIER2_RPC" "$TIER3_RPC"`). On such a
host the two halves named above are **not independent**: the same active, protocol-aware
intermediary that splices `getSlot`/`getClusterNodes` into a false G2 proof can equally proxy the
tip live while freezing the staked account's `lastVote` into a false-frozen vote observation. One
capability supplies both halves, so the composition adds nothing and the G2 section's residual 2 is
**unbounded by it**. Measured, on a spare cut off after the episode opened (P1b below) with G2 on the
default vantages: the forged flip proves verified-demote and the gate accepts it — the take mutates
at t132 with the holder voting for 42 s; the promoted spare's own H1 self-fence (its local confirmed
slot frozen ≥ 30 s) gives the identity back at t168, 36 s after the take.

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
statement of the G2 section becomes load-bearing again — **for G2's path only** (every runtime
remedy text says so). It does not do that for watchdog-elapsed, next.

**The watchdog-elapsed instance — on every configuration.** watchdog-elapsed has no vantage of its
own: it measures the holder's silence through the same liveness sampler the take path reads, so its
silence and the take path's vote-FROZEN observation are **one observation, read twice** — coupled
more directly than G2's default case, and with no configuration that separates them. The
intermediary above supplies the elapsed floor's silence and the FROZEN verdict together; the
provider's head cross-check does not change that (the intermediary proxies the head live, and lag is
what that check measures — splicing is not). What watchdog-elapsed adds is attested **time** — the
pairing token's bound (W + B) on how long a holder whose fence works keeps signing once it is in a
failure that fence covers — never a second **witness** that the holder is silent. So on a host with
separately pinned G2 vantages the gate's additivity holds for G2's path and **not** for the elapsed
path: through watchdog-elapsed the false-frozen view, held for `elapsed_floor` (100 s at the shipped
token bounds — longer than the un-armed timer's 60 s, by the floor's own minimum), is the whole
forgery. Its silence clock starts at the episode's first observation and restarts at every
**stamped** blindness — a cycle in which the take path tried to observe the holder and could not.
Stretches nobody tried to observe are not stamped (both tiers down t80–t120, inside the delay: the
proof still mints at t171; outages overlapping take-path cycles restart it — mint at the outage's end
+ 100 s); `lastVote`'s on-chain monotonicity and the final same-vantage read cover them. A host
suspend or VM pause that the uptime clock counts (`/proc/uptime` includes suspended time) likewise
meets the floor with no observation in between and ends on one post-resume read. The standing
verdict is served only while the stored token still licenses it — re-classified at every serve; a
token removed, rotted, turned page-only or re-paired withdraws it at once, and a token adopted
mid-episode restarts the silence — and never after `PROOF_MAX_AGE`. "Adopted" means ANY change to the
stored token FILE (6.3 fix round 2): the adoption is keyed on its full classified line (gen, bounds,
fence, host, crc) and on the stored file's identity (inode, size, change time), so a new gen, a same-gen
re-pair with other bounds, another host's token with the same bounds, and a rewrite back to the same
bytes that no evaluation saw are all new adoptions (measured: a same-gen re-pair to a lower floor at
+121 s proves no earlier than +221 s; before, it proved at +121 s). A **symlinked** token never proves
(6.3 fix round 4): the provider answers *cannot* — "the pairing token is a symlink — store it as a
regular file, as `failover arm` does" — and the startup posture and the status line say so every
interval. No single file identity covers a link: keyed on the link itself, every rewrite of its target
is invisible (a flap proved at +100 s before fix round 3); keyed on its target (`stat -L`, fix round 3),
a link re-pointed away and back is invisible at any spacing (it proved at +100 s there). `failover arm`
always stores a regular file (tmp + `mv -f`, which replaces a link). The same holds one level up (6.3
fix round 5): a **symlinked state directory** re-pointed away and back leaves the token file under it
untouched — it proved at +100 s on every earlier tree — so a token whose directory does not canonicalize
to itself (`PROOF_STATE_DIR` reached through a symlink anywhere on its path, or spelled other than its
resolved path) never proves either: *cannot*, "the pairing token's directory is reached through a
symlink — point PROOF_STATE_DIR at the resolved path", on the same three surfaces (the provider's
reason, the startup posture, the status line). The availability cost, by design: **a symlinked state
directory disables watchdog-elapsed until `PROOF_STATE_DIR` is pointed at the resolved path** (and the
monitor restarted to read it; `failover arm` writes through the link into that same directory, so the
stored token does not move). Not visible, for the regular file: a rewrite back to identical bytes
within one ctime granule — a kernel tick on ns-timestamp filesystems, 1 s on ext4 with 128-byte inodes,
ext3 or HFS+ (the inode number does not help: ext4 recycles it across a tmp+mv); and the state
directory's contents swapped away and back between two steps — by a rename, a transient symlink or a
mount: the key sees only the token file's identity, and it proves at +100 s on every tree, this one
included (a documented residual, `test_elapsed_provider` (3l-R5a)).

**Where composition does add an independent input — and how much.**

1. **G2 on separately pinned vantages** (the way back above): a different operator's RPC is an
   input the `TIER2`/`TIER3` intermediary does not control.
2. **The spare's own bank.** `LOCAL_RPC` does not traverse `TIER2`/`TIER3`, so no intermediary
   there can splice it. Since 6.3.1 it is used twice, on two commitments — **the slow reliable view
   triggers, the fast one vetoes**:
   - the **finalized** bank is the per-cycle entry gate (the own-bank delinquency check that opens
     the episode), and inside an open episode its "current" verdict now **re-anchors the countdown**
     (a full `TAKEOVER_DELAY` after the last such cycle) and restarts watchdog-elapsed's silence;
   - the **confirmed** view is a **mutation-edge condition**: the last read before `set-identity` on
     every take path is the own-view veto (one bounded `LOCAL_RPC` read after the fresh re-check —
     [the spare's own view](#the-spares-own-view-v07-block-631)).

   **Finding 1 (6.3) — the own bank did not bound the exposure; since 6.3.1 it does.** In 6.3 the own
   bank was read once, at the take cycle's start, at finalized, and a "current" verdict vetoed that
   cycle only: a holder that resumed voting was taken over unless its votes reached the finalized bank
   before that read, and the exposure was the finalized lag (32 slots) PLUS every tier read (and, armed,
   every pet) between that read and `set-identity` — Σ. Measured then, the tiers as the intermediary
   (the D0 worlds, `test_elapsed_provider` §11): resumed at t113 → taken at t125 after **12 s**; the
   intermediary also controlling latency → taken at t147 after **34 s** (`GOSSIP_VERIFY=true`: t175 /
   62 s; `TIER2` blackholed: t182 / 69 s); armed with every pet 7 s → Σ = **50 s** (22 s of reads +
   28 s of pets), a holder resumed at t477 taken 62 s into its voting; an HONEST tier 40 s / 10 s
   behind reproduced the race (taken after 12 / 9 s); the armed provider could mature first (t159 →
   taken at t171 after 12 s); the intermittent holder (one vote at t40 its own bank saw, current
   t53–t59) was taken at t80 un-armed and at t126 armed — "100 s of silence" overstating the true
   silence by 14 s. **Measured now, the same worlds:**
   - zero latency: resumed at t113 → the veto reads it VOTING in the confirmed view at t125 — held;
     the boundary is the veto's own read: t124 vetoed, t125 (the take's own second) taken, **0 s**;
   - the intermediary controlling latency: the take still lands at t147, and the veto reads last —
     t146 vetoed, t147 taken, **0 s** (`GOSSIP_VERIFY=true`: vetoed at t175; `TIER2` blackholed: the
     re-check alone runs 19 s, the pre-take own-head sample is older than `OWN_HEAD_H` by the veto →
     BLIND, and a dead holder behind that latency is not taken either — an intermediary that controls
     latency can starve the take, as it could by withholding answers);
   - **armed, the exposure left is the veto's own pet** — the one op between the veto's snapshot and
     `set-identity`: with every pet 7 s and prompt tiers the veto reads at t574 and the take lands at
     t581; resumed at t573 → vetoed, at t574 → taken after **7 s**. The 6.3 Σ world itself (the
     splicer at `curl -m` − 1 s AND 7 s pets) never takes now, not even a dead holder: every veto is
     BLIND (the pre-take sample is 23 s old by the veto read) — availability at the house
     bound-counting, where a real pet is a datagram;
   - honest tiers 40 s / 10 s behind: t113 / t116 vetoed VOTING (were taken after 12 / 9 s);
   - armed (with `[elapsed-rate]` neutered — it abstains at the worlds' 2.5 slots/s): the proof
     matures at t171 and the veto reads the t159 resumption VOTING — held;
   - the intermittent holder: the take waits a full delay from the last own-bank "current" cycle —
     **t119 = t59 + 60** (was t80); armed (rate layer neutered) the mint waits a full floor —
     **t159 = t59 + 100** (was t126); the shipped provider does not mint there at all at 2.5 slots/s.

**Cadence residual (documented, 6.3 fix round 2).** The episode window opens, triggers and closes on
a COUNT of cycles (7-of-10; "mostly clear"), while the own bank's view of a holder vote is a matter of
TIME (a vote reaches the finalized bank 32 slots after it lands — ≈ 13 s at 2.5 slots/s). So any change
in how long a cycle takes — a pet that costs time, `CHECK_INTERVAL`, read latency — re-phases vetoes
and window closes, both ways, on every tree (the first 6.3 build included). The proof's re-mint cycle
(`PROOF_MAX_AGE` from `observed_at`) is phase too. Measured over a 1,115-world sweep against the
build before fix round 2: the own-bank reference read that round moved to before the payload (at
`MAX_DELINQUENT_SLOTS` > 0) re-phased 18 takes 1–8 s sooner and 49 later; moving `observed_at` back
10 s re-phased 43 takes sooner and 55 later — 22 of them takes where the previous build vetoed, as
that build takes the same family's holders at other resume instants.
That reference read is **moved on every check that reaches the latency compare, and ADDED only on the
checks the payload ends early** — the holder listed delinquent, the RPC unreachable, or no `.result`
— not "added to every check": measured, a healthy live holder's steady-state read multiset is
identical to the previous build's (80 = 80 `getSlot` over 40 cycles; only the getSlot/getVoteAccounts
order changes). The detection cost of a dead holder is **0 s at loopback latency** (the episode opens
on the same cycle as before) and **up to one cycle later when the LOCAL reads cost ~2 s each**
(one extra loopback read, plus a pet on armed units, per listed-delinquent or unreachable cycle). The
`TIER2` latency re-read adds an **external** `getVoteAccounts` only when TIER2's latency verdict fires
on a not-yet-listed holder (alive-but-lagging or intermittent); for a holder already delinquent since
the episode start `TIER2` lists it and never re-reads. Measured in one world (the
holder's one vote at t141, `TIER2` 10 s late during t73–t118, `MAX_DELINQUENT_SLOTS`=0, an armed
spare on the shipped timer path): pets that cost nothing take at t125, 1 s pets at t272, 2 s pets at t268
(6.3: t254 / t218 — 6.3.1's per-cycle own-head sample and its pet re-phase it again; the first 6.3
build: t152 / t284); with free pets, `CHECK_INTERVAL` 4 / 5 / 6 takes at t138 / t125 / t126 on every tree. On a real host a pet costs
milliseconds, far below RPC jitter: the class is the phase, not the pet. It flips when the
episode-close rule becomes time-based (the "mostly clear" window spanning at least the own bank's
visibility period for a vote) — a reviewed change, not in this build (`test_elapsed_provider` (13f)).

**A partitioned or lagging spare.** Agave's `getHealth` (v4.2.1, `rpc/src/rpc_health.rs`) compares
the node's own optimistically confirmed slot with the latest optimistic slot its **own blockstore**
has observed (through replay and gossip), at a 128-slot distance; it never consults `TIER2`/`TIER3`,
and neither does Tier-1 (its `getSlot` is logged, never compared). Measured:

- **Finding 2 (6.3) — partitioned AFTER the episode opened** (cut off, or on a minority fork): the
  frozen bank keeps its delinquent verdict and `getHealth` stays ok (the blockstore learns nothing
  new). In 6.3 **no spare-side gate held on the timer path** — taken at t125 with the holder voting
  since t90 (P1b); armed, watchdog-elapsed refused only against a LIVE view, and with **co-frozen
  tiers** (partitioned together, after the pin) it MINTED and the proof-gated take mutated at t171,
  81 s into the holder's voting; forged G2 on the default vantages was accepted and taken at t132.
  **Since 6.3.1 each is held**: the veto reads the spare's own confirmed head NOT advancing past its
  sample of at most `OWN_HEAD_H` (16 s) ago → BLIND (P1b at t125; the co-frozen spare at t125; the
  forged-G2 take at t132 after the gate accepted it); armed, `[elapsed-rate]` reads the frozen own head
  at 0 slots/s → no mint (SLOW OWN HEAD from t171), and with that layer neutered the veto still refuses
  the minted proof's take — two independent refusals. A **dead** holder behind such a partition is not
  taken either (availability, correctly: a partitioned spare cannot testify). What is left is the
  exposure below `OWN_HEAD_H` — a spare cut off within ~15 s of the veto read still passes ([the
  spare's own view](#the-spares-own-view-v07-block-631)). A spare cut off *before* any episode opened
  (P1a) never opens one, even for a dead holder: a silent availability loss, no page (unchanged);
- **on a minority fork that PRECEDES the episode**: held — the own bank's finalized read shows the
  holder current (a minority fork does not finalize), and so would a read at *processed* (the vote
  bank freezes within ~8 votes of the fork) or *confirmed* (optimistic confirmation needs 2/3). If
  the supermajority's gossip still reaches the spare, `getHealth` reports it behind and Tier-1 holds
  as well. A fork that begins after the episode opened is Finding 2;
- **replaying behind**: up to 128 slots behind reads ok, and every own-view read lags with the spare's
  replay — including the veto's. 40 s (100 slots) behind: a holder resumed at t95 is held by the
  finalized own bank; t115 (the 6.3 build: taken at t165 after 50 s of voting) and t124 are vetoed
  VOTING at t165; **t125 is taken at t165 after 40 s** — the veto testifies about the chain as of the
  spare's own replay lag, up to the 128 slots `getHealth` admits (≈ 51 s at 2.5 slots/s, ≈ 35 s at
  3.7) — a named residual of the veto. Armed, watchdog-elapsed refuses such a spare (stale reference):
  it cannot prove by time while its own bank lags a live view by more than `N_HEAD`.
  **`LOCAL_HEALTH_MAX_BEHIND` is clamped since 6.3.1: effective = min(configured, 128)** — agave's
  `getHealth` distance (it reports "behind" only beyond 128 slots, so a value at or below 128 behaves
  as 128: its within-tolerance branch is never reached, and every "behind" report fails Tier-1). The
  default is 128; a configured value above 128 is announced at startup as clamped. (Unclamped, 200
  widened Tier-1: a spare 150 slots behind took over at t185, 35 s into the holder's renewed voting —
  now Tier-1 BEHIND from t0, no take.)

**What the elapsed head cross-check does and does not see.** It is two-sided against the spare's own
bank (`getSlot`, *processed* — the tower's vote bank): a view more than `N_HEAD` slots behind that
bank reads blind (a lagged fleet), and that bank more than `N_HEAD` behind a live view reads blind (a
stale reference — the cut-off or lagging spare above). Both cost availability, never a take. It does
not see the bank and the view lagging or frozen **together** (Finding 2's co-frozen form — since 6.3.1
the frozen case is refused by `[elapsed-rate]`, which reads a frozen own head at 0 slots/s, and by the
veto; a bank and view lagging together but advancing still pass it), a bank at
the same height on another fork (the compare is on slot numbers), or an intermediary that proxies the
head live (it passes by construction). The head is read after the payload, and the bank moves while
the time between the two answers runs: that time deflates the bank-behind side, so a bank lagging a
live view by up to `N_HEAD` + (slot rate × that time) still passes — the hidden lag. Since 6.3 fix
round 2 the provider stamps the sampler's return and the head read's completion and answers BLIND
when the head landed more than `ELAPSED_HEAD_GAP_MAX` = 1 s (measured on the truncating monotonic
clock; < 2 s true) after the payload. Not stamped: the payload read's own pet and the sampler's parse
(~0.11 s measured on the test box, a 2,001-account payload). The time between the answers is
therefore under 2.2 s on a healthy host (a pet is one datagram — 4 ms measured) — a hidden lag under 6 slots at
2.5 slots/s and under 9 at 3.7 — and under 9.2 s with the payload's pet stalled at its full 7 s:
under 23 slots at 2.5/s, under 35 at 3.7. (The text before this round said "≤ 7 s, ~17 slots"; it
missed the head read's own `curl -m 5` + pet, which nothing bounded: with every read at its bound and
every pet 7 s, the pre-fix tree minted with the spare's bank 50–55 slots behind the view — twice
`N_HEAD` (25 then). That world now reads blind.) The stamps bound only the part **after the payload's
delivery**. The sampler's answer is computed at the server at request time and arrives up to its
own `curl -m 10` later, so the view it reports is a snapshot up to that much older than the arrival
the stamp records: a hidden lag of the slot rate × (the payload's snapshot → its delivery), up to
25 slots at 2.5/s and 37 at 3.7. This is only reachable when the view itself is stale-on-arrival —
a slow or early-snapshot external provider — which is exactly the **bank and view lagging together**
residual above; a live-and-current view carries a snapshot within its transfer time. It is a
**documented residual**, not bounded by `ELAPSED_HEAD_GAP_MAX` (that stamp is taken at the answer's
arrival, not its snapshot): a provider that snapshots getVoteAccounts at request and delivers 9 s
later, with instant free pets, mints with the bank 44 slots (≈ 18 s) behind the live chain — `N_HEAD`
(22 since 6.3.1; 47 = 25 + 22 before) plus 22 hidden at 2.5 slots/s (measured; pinned as a DOCUMENTED
RESIDUAL in `test_elapsed_provider` (5l), with the snapshot-at-delivery control minting only up to
`N_HEAD`). Bounding it would need the sampler to stamp before its own call and treat (head answer −
payload request) as the gap, which fails toward blind on every slow tier; deferred with the gate's
wiring (6.4).

**watchdog-elapsed's own cost, and its verdict's age.** The provider reads nothing below its floor and
nothing while a minted verdict stands (only the token's re-classification per step: a local file read +
cksum, ~20 ms measured), and runs at most one paced evaluation per cycle — its worst added gap is 48 s
at the house bound-counting (the sampler's two reads at their `curl -m 10` bound with a 7 s pet each,
the head read and its pet, parse glue), every read petted. Its verdict carries `observed_at` = the
evaluation's START, so its worst MINTING evaluation is 35 s old at the mint and 74 s at the mutation
edge by 6.1's acceptance→mutation arithmetic (84 s with 6.3.1's veto read in that span): it does not
converge under `PROOF_MAX_AGE` (50 s) — the edge refuses it (availability, never a take), and 6.4
decides (per-provider ages). The healthy path is ≈ 8 s at the edge.

### The spare's own view (v0.7, Block 6.3.1)

The reviewer's principle for this slice: **trigger on the slow reliable view (finalized), veto on the
fast one (confirmed).** The spare's own node (`LOCAL_RPC`) is the one input no `TIER2`/`TIER3`
intermediary can splice (*Shared vantages* above); 6.3.1 makes it testify at every take, and every
piece is **veto-only** — it can turn a take into a hold, never the reverse.

- **The detection reads say `finalized`, spelled out.** Every `getVoteAccounts`/`getSlot` request body
  in both daemons now carries an explicit commitment (a census test fails on any that does not). The
  detection reads — the standby's own-bank check and its reference, the `TIER2`/`TIER3` confirm — say
  `finalized`, which is agave's default when a request carries none (agave v4.2.1: the
  `CommitmentConfig` default is finalized; `rpc.rs` resolves a missing commitment to it), so the
  change is byte-for-byte behavior-neutral (measured: every detection read of both daemons decides
  identically with and without it, under a stub that serves each commitment a different view).
- **The own bank's "holder voting" restarts the countdown (D2).** Inside an open episode a LOCAL
  not-delinquent answer re-anchors the takeover countdown — a fourth anchor input of its own, kept
  apart from the `TIER2`/`TIER3` re-anchor so logs and tests can tell which stream moved it — and
  restarts watchdog-elapsed's silence; it resets with the episode at every close. No take for a full
  `TAKEOVER_DELAY`, and no mint for a full floor, after the last such cycle (measured: the intermittent
  holder t80 → t119; armed, with `[elapsed-rate]` out of the way, t126 → t159). **The cost, measured on
  both presets:** the 7-of-10 window
  existed to tolerate a *flickering* own bank; now every not-delinquent answer restarts the countdown,
  so a DEAD holder behind an own bank that shows it current once every P seconds is taken only after a
  flicker-free `TAKEOVER_DELAY`: P = 30 s → **never taken** — the hold is loud: the starvation page fires
  at the episode's start + 300 s (t365 at `MAX_DELINQUENT_SLOTS`=0, t320 at 15); P = 61 s → taken one
  delay after the last flicker (t182 / t121; the 6.3 build took at t125 / t80 whatever P).
- **One bounded local veto read before the switch (D3).** On every take path (the standby's
  `take_staked_identity`, the primary's `switch_to_staked` — the complete set-identity-to-staked
  census), right after the fresh re-check returns 0 and before the `DRY_RUN` branch: ONE request to
  `LOCAL_RPC`, a JSON-RPC batch `[getSlot{confirmed}, getVoteAccounts{confirmed, votePubkey}]` matched by
  id, `curl -m 2`, then its watchdog pet. It VETOES if the read fails, times out, or answers anything
  non-canonical or not echoing its ids (BLIND); if the holder is NOT delinquent in the confirmed view by
  the same predicate the own-bank check applies, or its confirmed `lastVote` is above the highest the
  own bank showed this episode (VOTING — the countdown and the silence restart); if the spare's own
  head is not advancing (below). State is written before the (throttled) alert; no cooldown is set —
  a withdrawn verdict, not a failed take. **The act-then-alert rule now reads: between the fresh
  re-check's return-0 and set-identity — no network, no alerts; one bounded local veto read allowed**;
  the census admits exactly this read. The 2 s bound is ~400× a healthy loopback read (4–5 ms
  measured), and every second of it lengthens the verdict→mutation span: **`PROOF_MAX_AGE` (50 s)
  still covers the acceptance→mutation span — now 49 s** (6.1's 39 s + the veto's worst 10 s: 2 s + a
  7 s pet + 1 s of parse), a margin of 1 s where it was 11 s; 6.4's gate must sit after the pre-take
  own-head sample (before it, the span is 58 s and does not converge). Reported, not changed:
  per-provider ages are 6.4's.
- **The spare's own head: advancing now, and at a rate (D4).** Own-head samples (`getSlot{confirmed}`
  + its pet) are taken once per take-path cycle of an open episode and once at the head of each take
  function. (b) At every take the veto's confirmed head must **exceed** the oldest sample no older
  than `OWN_HEAD_H` = **16 s** (derived: a healthy confirmed head holds for at most 22 slots — 5 fully
  skipped leader windows + 2 slots of confirmation jitter, 8.8 s at the assumed 2.5 slots/s; two
  snapshots whose stamps are A s apart are at least A − 5 s apart — two 2 s read bounds and 1 s of
  clock truncation — so A = 14 s guarantees a live head advanced, + 2 s of sample spacing). An
  opening-time baseline would not do: a spare cut off after the episode opened advanced from it up to
  the cut. (e) watchdog-elapsed's `[elapsed-rate]` layer (see *Slot time*).

**What it costs, measured** (the D0 worlds, `test_own_view`, `test_elapsed_provider` §11–§13):
a dead holder with prompt reads is taken as before (t125 / t80); every LOCAL read taking 1 s → t131 →
t139; every read at its `curl -m` bound → t215 → t233; pets at the house 7 s → t504 → t581. A spare
whose own node answers a loopback read in **2 s or more can never take**: the veto's read times out,
every veto is BLIND (t156 → never; the R7 world t197 → never). A re-check longer than
`OWN_HEAD_H` minus the sample's and the veto's own read times — 16 s with prompt LOCAL reads, 12 s with
both at their 2 s bound — leaves no own-head sample young enough by the veto: BLIND while it lasts
(`TIER2` down and `TIER3` 6 s late → taken at t168; 7 s late → never; the pre-take sample exists for
exactly this — without it a dead holder behind one dead tier was never taken). Every such hold is
loud: the takeover starvation page covers it.

**What it leaves, named (residuals of the own view):**

1. **The exposure below `OWN_HEAD_H`.** A spare cut off (or frozen) within the last ~15 s before the
   veto read advanced from the baseline up to the cut and passes (b): measured, a cut at t110 is taken
   at t125 and one at t109 is held (`MAX_DELINQUENT_SLOTS`=15: t65 taken, t64 held) — `test_own_view`
   (4b-residual). A shorter `OWN_HEAD_H` would veto a live bank in its longest healthy hold.
2. **The spare's own replay lag.** The veto testifies about the chain as of the spare's own replay:
   a spare 40 s behind takes a holder that resumed within those 40 s (up to the 128 slots `getHealth`
   admits — ≈ 51 s at 2.5 slots/s, ≈ 35 s at 3.7).
3. **The instant of the take.** A holder resuming inside the veto's confirmed lag (≈ 1 s) or, armed,
   inside the veto's own pet (up to 7 s at the house bound-counting; milliseconds on a real host) is
   taken: measured 0 s un-armed, 7 s armed.
4. **Only the confirmed view.** A vote the spare's node has not yet optimistically confirmed is
   invisible to the veto; the finalized trigger and the tiers' processed re-check cover the rest.
   The `votePubkey` filter narrows the delinquent-by-node leg to the holder's own vote account — fewer
   "delinquent" verdicts, i.e. only more vetoes.

### Holder self-fence: the differential bar and its named residuals (v0.7, Block 6.3)

Block 6.3's five review rounds hardened the holder's self-fence against non-canonical and corrupted
input; the rules and the residuals they leave are stated here (the rounds are named by number — the
first 6.3 build, then fix rounds 1–5). Rows (1) and (4) are measured against the spare in *The
cross-node invariant*: (1), its restart member and (4) (N7) are the table's crossings.

**The holder's self-fence (both daemons, identical decision logic; the demote action differs by
role).** (Not byte-identical twins: `check_self_fence_isolation` / `load_state` / `save_state` differ by
36 / 27 / 6 code-only lines between the daemons — the demote call, log and alert texts, `LAST_SWITCH`
vs `LAST_TAKEOVER`, the standby's `SELF_FENCE_DEMOTE` restore.) A present non-canonical LOCAL slot /
`numSlotsBehind` / own or cluster `lastVote` counts as frozen / behind / lagging — never healthy, never
the no-answer path's early return (`SELF_FENCE_NOANSWER_SECS=0` still fences through the frozen clock).
A non-canonical slot is also no CANONICAL answer: it keeps (or starts, or backdates from the persisted
start) the no-answer clock exactly as silence does, and only a canonical answer clears that clock and
its restored backdate. A garbage-slot cycle ADDS own-vote-lag (N6) evidence and never removes it: its
lagging (or garbage) vote reading counts and applies the restored backdate as ever, while its healthy
vote reading neither counts toward the B2 hysteresis reset nor consumes the restored backdate.
`load_state` reads every persisted number through `_canon_uint` and decides PER VALUE (never arithmetic
on a raw value; the rest of a fresh save restores): a non-canonical lockout/cooldown re-holds IN FULL
from now (a leading-zero value had been read as octal — "0777" silently expired the lockout); a
non-canonical `SAVE_TS` makes the whole save stale; a non-canonical stall / silence / lag STAMP — and a
same-boot one LATER than now, which can only be corruption where `/proc/uptime` and `boot_id` belong to
one kernel boot (the documented deployment; (5) names the container case) — restores as ANCIENT, applied
only if the first read after the restore still shows the condition (a healthy first read drops it); a
non-canonical SLOT restores as 0 (a baseline existed: the no-answer gate stays armed), the first
canonical answer after the restore is only a REFERENCE, and the stall backdate stays pending until a
later answer shows the slot not past that reference with the reference at least
`SELFFENCE_RESTORE_CONFIRM_SECS` = 15 s old (applied), or past it (dropped); a non-canonical answer
applies it; over a YOUNG stall stamp (under one window) the anchor is the restore instant, never
earlier, behind the same floor. The floor is a constant at ONE derivation site, byte-identical in both
daemons: above the longest hold a HEALTHY confirmed slot shows (assumed, not measured here: 5
consecutive fully-skipped leader windows + 2 slots of confirmation jitter = 22 slots = 8.8 s at 2.5
slots/s, 5.9 s at 3.7) plus the read-timing term (the reference's own `curl -m 5` + 1 s of `mono_now`
truncation), and below `SELF_FENCE_ISOLATION_SECS` (30); 15 s = 37 / 55 slots — a healthy hold longer
than 9 s right after such a restart can be fenced (availability; a corrupted slot and a restart needed).
The vote-lag baseline latch restores SET for any present value but 0 (`save_state` writes only 0 or 1);
a non-canonical hysteresis streak is not restored.

**The differential bar and the named residuals.** Every holder-fence change is proven by DIFFERENTIAL
runs of the review panels' grids — the real `load_state`, startup tail and `check_self_fence_isolation`,
both daemons: 8,656 restart / `load_state` rows per tree (a fresh bash per daemon instance), a 288-row
still-frozen grid at the turbo cadences, and the in-loop sweep (8,942 sequences per daemon and garbage
class) — against the first 6.3 build and fix rounds 1, 2 and 3. The bar: never later than fix round 2 or fix round 3
for any input; never later than the first 6.3 build / fix round 1 except where their fence came from misreading a
leading-zero value (a misread that fenced HEALTHY holders too) or from an aborted startup (no READY,
no grace) — each such row named here for the reviewer, with two further named exceptions: the floor's
own cost against fix round 3 (1), and the fresh-start rows where the first 6.3 build fenced only because it adopted
garbage as its baseline (4):

1. *The floor's cost (later than fix round 3, never later than fix round 2).* A still-frozen holder with a
corrupted slot over a stall a window old fences at the first read at or after reference + 15 s — up to
one LOOP CYCLE past it (the interval plus the cycle's reads and pets); in the free-read harness, grace
30 / 0: 45 / 15 s at `CHECK_INTERVAL` 1, 3 and 5, 51 / 21 s at 7 (a cadence that does not divide 15),
both daemons — where fix round 3 decided at the very next answer (35 / 5 s
at `CHECK_INTERVAL` 5, 33 / 3 s at 3, 31 / 1 s at 1, 37 / 7 s at 7): the decision that also fenced a
PAUSED HEALTHY holder (C F C, C D C, C S F C — 35 / 35 / 40 s at grace 30, 5 / 5 / 10 s at grace 0,
one cycle after the reference at the turbo cadences; never now). fix round 2: 60 / 30 s (65 / 35 s at 7);
the first 6.3 build / fix round 1: the same for a non-numeric slot (30 at grace 30 for the slots of (2)). Its restart
member: a monitor restart inside that ~15 s window (one check cycle on fix round 3, whose second read had
already fenced) defers the fence to the next instance, which fences at its first read if the reference
stamp is already `SELF_FENCE_ISOLATION_SECS` old at its restore, else at its first read at or after
restore + `SELF_FENCE_ISOLATION_SECS` — measured +25..+59 s later than fix round 3 for stops of 0–20 s,
equal to fix round 2 (7).
2. *The leading-zero misread (later than the first 6.3 build / fix round 1 only).* A persisted slot with a leading
zero and an 8 or 9 ("0999", "0400000009"): both references fence at 30 s (grace 30) in EVERY world,
the healthy holder included (their `[[ ]]` octal misread). Here, as on fix rounds 2 and 3, a healthy
holder is never fenced, and a frozen one at 45 s (a stall stamp a window old or young; fix round 3 33 / 35
or 60, fix round 2 60); a garbage decision read at 33 / 35 s (fix round 3 the same or 60, fix round 2 60); a
lagging one at 50 / 51 s, a silent one at 63 / 65 s, one across a boot at 60 s, one restarted between the
reference and the decision at 65 / 70 / 100 s — each equal to fix rounds 2 and 3. In the loop,
the first 6.3 build misread a LIVE "0400000129" (before any canonical answer) the same way and fenced at
30–60 s whatever followed, the healthy G C holder included: those 2,997 in-loop rows (both daemons)
are identical to fix round 3's here.
3. *The aborted startup (later than the first 6.3 build / fix round 1 only).* A `SAVE_TS` or `SF_ADVANCE_MONO` in
that leading-zero class: the references' `$(( ))` error discarded the rest of `startup_checks` (no
READY, no `STARTUP_GRACE`) and their loop fenced at 30 / 33 / 35 s; here the startup completes and
the holder fences after the grace, at 60 / 65 s — equal to fix rounds 2 and 3.
4. *The fresh-start gap (N7; not changed).* The no-answer gate needs a canonical baseline and silent
reads do not run the frozen clock, so a holder silent from a fresh start is fenced by neither: a
non-canonical `SAVE_TS` makes the whole save stale — a holder silent across that restart is never
fenced by the daemon's self-fence, on every tree (on an ARMED unit of the first 6.3 build or fix round 1 the leading-zero
`SAVE_TS` of (3) aborted the startup before READY, so the unit plausibly reached `failed` at its start
timeout and OnFailure fenced it; this build completes its startup, so that path is gone — and the
armed silent-restart classes were EXECUTED in 6.3.1 in real systemd: an answering admin socket sends
READY and nothing fences, a silent one reaches the start timeout and OnFailure fences at restart + 90 s —
[the cross-node invariant](#the-cross-node-invariant)); and garbage before any canonical answer, then silence (H4-N7-GARBAGE-FIRST) —
never on fix rounds 1, 2, 3 and here, where the first 6.3 build fenced such sequences at 33–60 s because it
adopted the digit garbage as its baseline ("0400000123" read as octal; 2^64+100, or a value just past
2^63−1, wrapped): 59 of the in-loop sweep's standby rows and 58 of its primary rows. Letting a present
answer arm the gate is an N7 change, not made (`docs/SPLIT-BRAIN-RESIDUAL.md`, no-answer sub-check).
5. *Corrupted-stamp blips (availability; a corrupted stamp or slot needed — or a container's
virtualized uptime, below).* A stamp restored as ANCIENT turns ONE first-read blip into an immediate
fence: a silent, non-canonical or lagging first read — or, at `STARTUP_GRACE=0`, a 3–5 s pause —
fences at that read (grace 30: 30 s; grace 0: 0 s) where the same holder with canonical stamps arms
nothing; the future-dated stamps now share it; the references had the same exposure for octal-valid
stamps. Over a corrupted slot (canonical stamps, a window old or young) a garbage DECISION read applies
the pending: C G C fences at 35 / 5 s (33 / 31 s at the faster cadences, grace 30), as on fix round 3 —
the first 6.3 build, fix round 1 and fix round 2 never fenced it (a non-numeric slot; the leading-zero slots are (2)) — and
now also over a young stall stamp (never → 35 s at grace 30). The future-stamp rule assumes
`/proc/uptime` and `boot_id` belong to one kernel boot, as on the documented deployment (the monitor
on the validator host; `docs/DEPLOYMENT-MANUAL.md`, Prerequisites): in a container that virtualizes
`/proc/uptime` but not `boot_id` (lxcfs-style) a container restart makes the self-fence stall /
silence / lag stamps "future" → ANCIENT (a future lockout / cooldown stamp restores verbatim and holds
until the uptime passes it), so there — once the container's uptime at that read is at least
`SELF_FENCE_ISOLATION_SECS` — a first-read blip fences with nothing corrupted — measured by the final
panel: a validator still catching up 10–25 s after such a restart, at grace 0, fenced at its first
read, where fix round 3 and the same restart on a normal host never fence (0 future stamps in 2,000
real-clock save → load round trips on a normal Linux host). Named, not changed.
6. *An absent vote-lag latch (every tree; not changed).* A fresh save without
`SF_VOTELAG_BASELINE` keeps N6's fresh-start rule (no healthy baseline → not armed): a holder lagging
continuously across such a restore is never fenced through N6.
7. *A restart between the reference and the decision.* The pending is not persisted: the next
instance restores the reference slot as its canonical baseline, with the reference's stamp as its stall
stamp, and fences as for a canonical slot — at its first read if that stamp is already
`SELF_FENCE_ISOLATION_SECS` old at its restore, else at its first read at or after restore +
`SELF_FENCE_ISOLATION_SECS`. For a restart right after the reference that is every tree's timing (65 /
70 / 100 s in the panel's rows; 45 s without the restart); a restart later inside the floor's ~15 s
window is (1)'s restart member: +25..+59 s later than fix round 3, equal to fix round 2.

The phase residuals, ratified phase-only by the three-lens panel: the revert of `observed_at` to the
evaluation start, the reference-first own-bank read and the head-gap bound re-phase takes (1,115-world
sweep against fix round 1, the build before fix round 2: 62 sooner, 119 later, 28 veto-only — of the 62
sooner, 22 were in worlds fix round 1 vetoed (18 on a holder voting again 0–45 s before the take), takes
the first 6.3 build also made; ratified phase-only because the acceptance predicate is the first 6.3 build's); REG-C — the
episode window closes on cycle COUNT while the own bank sees a vote in TIME, so any cadence change
re-phases vetoes both ways, on every tree (documented and pinned; flips when the close rule becomes
time-based). The PRIMARY's opt-in latency demote (`MAX_VOTE_LATENCY` > 0, off by default) read its reference first
in 6.3, so a stall or pet between its two reads made the holder look more current: whenever the
threshold crossing fell inside that ≤ 27 s snapshot gap (both reads at their `curl -m 10` bound + a 7 s
pet), the demote came up to ONE FULL STAKED LOOP CYCLE later (`DELINQUENCY_RETRIES` consecutive
over-limit reads are needed) — 37 s measured in a latency-only cycle at `CHECK_INTERVAL` 3 and 64 s in
one at `CHECK_INTERVAL` 30; a full default STAKED cycle with every per-cycle read and pet is ~103 s —
and a holder lagging within rate × that gap of the limit never demoted on that path. **Since 6.3.1 it
reads its payload FIRST**, then the reference: a stall between the two can only make the holder look
LESS current — the demote comes sooner, never later (the holder's side of the cost model); the price is
a live holder whose two reads straddle a long stall reading over-limit on that cycle (a demote still
needs `DELINQUENCY_RETRIES` such reads and `TIER2`'s own verdict). This path is **not** part of the
cross-node invariant: it may fire after a spare's take — the relinquish bound B bounds the self-fence
only.

### Local-host threat model — named, not defended (v0.7)

This tool defends against failures, and against the external RPC surface (the *Shared vantages*
premise). It does **not** defend against root on the spare or the holder: root can edit the env, stop
the monitor or set the identity by hand. Two local cases are named because the mechanisms above might
suggest otherwise:

- **The state directory's contents swapped away and back between two provider steps** — by a RENAME of
  the directory, a transient symlink or a mount. watchdog-elapsed's token key sees only the token
  FILE's identity, so such a swap is invisible: it proves at +100 s on every tree (a documented
  residual, `test_elapsed_provider` (3l-R5a)). What is closed: a symlinked token and a token directory
  reached through a symlink never prove (6.3 fix rounds 4–5), and since 6.3.1 `failover arm` refuses to
  store the token in such a directory (`REFUSE[STATE-dir-symlink]`, and `REFUSE[STATE-dir-missing]` for
  one it cannot create or enter) — the daemon's rule mirrored before anything is written. What remains
  is a live swap by a local root: not defended, named.
- **A container's virtualized uptime** (lxcfs-style: `/proc/uptime` virtualized, `boot_id` not): a
  container restart makes the holder's persisted self-fence stamps "future" → restored as ANCIENT → a
  first-read blip fences with nothing corrupted (availability, the holder side — *Holder self-fence*,
  (5)). The documented deployment runs the monitor on the validator host; not changed.

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
- **No lazy provider registration** (v0.7): watchdog-elapsed registers only at the monitor's startup,
  over a token that classifies ok; a spare paired while its monitor runs says so every heartbeat
  ("paired, but watchdog-elapsed is NOT registered — restart the monitor"). By design, not changed.
- Tests are function-level with mocked I/O: they exercise the real decision functions, but do **not**
  prove cross-process ordering between two live systemd services. A chaos/E2E gate on real nodes is
  required before unattended operation.
- On-chain slashing for double-signing is not (yet) enforced by the Solana network, but this system is
  built as if it were — do not weaken the fences.
- Always test on testnet, and roll to mainnet one node at a time.
