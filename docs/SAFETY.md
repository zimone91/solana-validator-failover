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
the code's derivations assume, e.g. `N_HEAD = MARGIN_ELAPSED × 5/2`). Mainnet **measured ≈ 3.7
slots/s** on 2026-09-26 (265–283 ms per slot: `getRecentPerformanceSamples` on the public
mainnet RPC, ten 60 s samples of 212–226 slots — re-run it to check), so the slot boundaries are the stable facts: the own
bank's delinquency rule is 128 slots (≈ 51 s at 2.5/s, ≈ 35 s at 3.7/s); *finalized* trails
*processed* by 32 slots (≈ 13 s / ≈ 9 s); `getHealth`'s distance is 128 slots; `N_HEAD` is 25 slots —
10 s at its assumed rate, ≈ 6.8 s on today's mainnet: **stricter** than its derivation (more blind
reads — availability, never a take). A *slower* cluster would loosen it (25 slots = 15 s at 600 ms).
Measured at 3.7 slots/s, the timing race below opens its episode at t45 instead of t65, takes at
t105 instead of t125, and its veto boundary is the same 32 slots — ≈ 9 s (t96 vetoed, t97 taken
after 8 s).

| Input | What reads it on the take path |
|---|---|
| **the spare's own node** (`LOCAL_RPC`) | Tier-1 health (`getHealth`); the own-bank delinquency check that opens the episode and fills the 7-of-10 window (`getVoteAccounts` at the RPC default commitment, *finalized* — and, when `MAX_DELINQUENT_SLOTS` > 0, a separate `getSlot` reference, also finalized, read FIRST (6.3 fix round 2): any gap between the two answers — a pet, a stall, a slow read — can only make the holder look MORE current, failing toward NOT opening an episode. Read after the payload, as before, the gap pushed a current holder toward "delinquent": a 3 s reference + a 7 s pet read a holder voting every slot as "Latency 25 > 15", and an armed spare took that live holder at t577, measured); watchdog-elapsed's head cross-check (`getSlot`, *processed* = the tower's vote bank); the local identity that selects the take branch (the admin socket's contact info; `getIdentity` on frankendancer) |
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
directory itself swapped away and back by RENAME, with no symlink anywhere — the token file keeps its
identity, and it proves at +100 s on every tree, this one included (a documented residual,
`test_elapsed_provider` (3l-R5a)).

**Where composition does add an independent input — and how much.**

1. **G2 on separately pinned vantages** (the way back above): a different operator's RPC is an
   input the `TIER2`/`TIER3` intermediary does not control.
2. **The spare's own bank.** `LOCAL_RPC` does not traverse `TIER2`/`TIER3`, so no intermediary
   there can splice it. What it buys was measured, and it is less than it looks:
   - it is a **per-cycle entry gate, not a mutation-edge condition**: the take cycle reads the own
     bank, then `attempt_takeover` reads only `TIER2`/`TIER3` (external confirm, the vote-FROZEN
     sample, the mutation-edge re-check; the gossip advisory too) and mutates — zero `LOCAL_RPC`
     reads in between;
   - it reads the **finalized** bank, so a resumed holder's vote shows there 32 slots after it lands;
   - a "current" verdict vetoes the take **on that cycle only**: it never re-anchors the countdown
     (the re-anchor rides the vote-FROZEN gate, i.e. `TIER2`/`TIER3`); from a full window, the
     7-of-10 trigger drops after 4 consecutive current cycles and the episode closes only after 9.

   **Finding 1 — the own bank does not bound the exposure.** (A design finding, named here as
   measured; the remedy is a separate, reviewed design change.) A holder that resumes voting is
   taken over unless its votes reach the spare's finalized bank before the take cycle's own-bank
   read. The exposure is **the own bank's commitment lag (32 slots at finalized) PLUS every tier
   read between that read and `set-identity`** — bounded by those reads' `curl -m` on the timer
   path, and on the armed path by the proof's age (up to `PROOF_MAX_AGE`) as well; **on an armed
   unit Σ also counts one per-op pet per read** (a pet is `timeout -k 2 5` — 7 s at the house
   counting). Measured on an armed spare, every take-cycle tier read answered at its `curl -m` − 1 s
   and every pet 7 s: the own-bank read at t489, the attempt at t496, three `TIER2` reads answering
   +4, +9 and +9 s, each followed by a 7 s pet, the mutation at t539 — Σ = 50 s, 22 s of reads + 28 s
   of pets (the reads' bounds alone imply about 35 s); a holder that resumed at t477 was taken 62 s
   into its voting (t476: vetoed) — pinned in `test_elapsed_provider` (11j-Σ). Measured, the tiers
   as the intermediary, the take scheduled at t125 on the timer path:
   - zero latency: resumed at t112 → vetoed; at t113 → taken at t125 after **12 s** of renewed
     voting. Armed (proof minted at t171): t158 → vetoed; t159 → the gate accepts watchdog-elapsed
     and the take mutates at t171 — the proof matures before the own bank sees the resumption;
   - **the intermediary also controls latency** (each tier read of the take cycle answered at its
     `curl -m` − 1 s, legal within every bound): the veto boundary is unchanged (t112 vetoed — the
     own bank is read once, at the cycle's start), but the mutation trails that read by Σ: t113 →
     taken at t147, **34 s** into the holder's voting; with `GOSSIP_VERIFY=true` t175 / 62 s; with
     `TIER2` blackholed t182 / 69 s. Armed: the proof mints at t181, t166 is vetoed, t169 is taken
     at t203 after 34 s;
   - **no adversary needed**: an HONEST tier 40 s behind reproduces the zero-latency race exactly
     (t112 vetoed; t113 taken at t125 after 12 s); 10 s behind, t115 is caught by the tiers and t116
     is taken at t125 after 9 s. This applies to **un-armed** installs as they ship. Armed,
     watchdog-elapsed refuses such a view — it reads LAGGED VIEW (blind) whenever the view trails
     the own bank by more than `N_HEAD` (25 slots): no mint, no take;
   - an **intermittent holder**: at `MAX_DELINQUENT_SLOTS=15` one vote at t40 reached the spare's
     bank (current from t53) and the take still fired at t80 on the original anchor. Armed,
     watchdog-elapsed minted PROVEN at t126 — its clock runs from the episode's first sample (t26)
     and never sees the vote the tiers withhold — and the proof-gated take mutated at t126, **86 s**
     after a vote the spare's own bank saw: the verdict's "100 s of silence" overstated the true
     silence by 14 s, more than `MARGIN_ELAPSED` (10 s).

**Cadence residual (documented, 6.3 fix round 2).** The episode window opens, triggers and closes on
a COUNT of cycles (7-of-10; "mostly clear"), while the own bank's view of a holder vote is a matter of
TIME (a vote reaches the finalized bank 32 slots after it lands — ≈ 13 s at 2.5 slots/s). So any change
in how long a cycle takes — a pet that costs time, `CHECK_INTERVAL`, read latency — re-phases vetoes
and window closes, both ways, on every tree (de21927 included). The proof's re-mint cycle
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
spare on the shipped timer path): pets that cost nothing take at t125, 1 s pets at t254, 2 s pets at t218
(de21927: t125 / t152 / t284 — its 2 s-pet take is 66 s later than this build's); with free pets,
`CHECK_INTERVAL` 4 / 5 / 6 takes at t138 / t125 / t126 on every tree. On a real host a pet costs
milliseconds, far below RPC jitter: the class is the phase, not the pet. It flips when the
episode-close rule becomes time-based (the "mostly clear" window spanning at least the own bank's
visibility period for a vote) — a reviewed change, not in this build (`test_elapsed_provider` (13f)).

**A partitioned or lagging spare.** Agave's `getHealth` (v4.2.1, `rpc/src/rpc_health.rs`) compares
the node's own optimistically confirmed slot with the latest optimistic slot its **own blockstore**
has observed (through replay and gossip), at a 128-slot distance; it never consults `TIER2`/`TIER3`,
and neither does Tier-1 (its `getSlot` is logged, never compared). Measured:

- **Finding 2 — partitioned AFTER the episode opened** (cut off, or on a minority fork): the frozen
  bank keeps its delinquent verdict and `getHealth` stays ok (the blockstore learns nothing new) —
  **no spare-side gate holds on the timer path**: taken at t125 with the holder voting since t90
  (P1b). On the armed path watchdog-elapsed refuses **only against a LIVE view**: its two-sided head
  cross-check reads the frozen own head as a stale reference (blind, every cycle). With **co-frozen
  tiers** (the third premise: partitioned together, after the pin) the frozen vote bank and the
  frozen view agree within `N_HEAD` and watchdog-elapsed **MINTS PROVEN**: the proof-gated take
  mutated at t171, 81 s into the holder's renewed voting — indistinguishable from a dead holder.
  A spare cut off *before* any episode opened (P1a) never opens one, even for a dead holder: a
  silent availability loss, no page;
- **on a minority fork that PRECEDES the episode**: held — the own bank's finalized read shows the
  holder current (a minority fork does not finalize), and so would a read at *processed* (the vote
  bank freezes within ~8 votes of the fork) or *confirmed* (optimistic confirmation needs 2/3). If
  the supermajority's gossip still reaches the spare, `getHealth` reports it behind and Tier-1 holds
  as well. A fork that begins after the episode opened is Finding 2;
- **replaying behind**: up to 128 slots behind reads ok, and the own-bank veto's reaction grows by
  the lag — 40 s (100 slots) behind, a holder that resumed at t95 was vetoed and one that resumed at
  t115 was taken over at t165, after 50 s of voting. Armed, watchdog-elapsed refuses such a spare
  (stale reference): it cannot prove by time while its own bank lags a live view by more than
  `N_HEAD`. **`LOCAL_HEALTH_MAX_BEHIND`** is inert at or below 128 at agave's default distance
  (agave reports "behind" only beyond 128 slots, so the knob's within-tolerance branch is never
  reached and every "behind" report fails Tier-1) — the shipped 100 promises no 100-slot protection;
  **above 128 it WIDENS Tier-1** to admit a spare up to that many slots behind: at 200, a spare 150
  slots behind passed Tier-1 and took over at t185, 35 s into the holder's renewed voting. The daemon
  announces a value above 128 at startup; it does not clamp it.

**What the elapsed head cross-check does and does not see.** It is two-sided against the spare's own
bank (`getSlot`, *processed* — the tower's vote bank): a view more than `N_HEAD` slots behind that
bank reads blind (a lagged fleet), and that bank more than `N_HEAD` behind a live view reads blind (a
stale reference — the cut-off or lagging spare above). Both cost availability, never a take. It does
not see the bank and the view lagging or frozen **together** (Finding 2's co-frozen form), a bank at
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
`N_HEAD`. That world now reads blind.) The stamps bound only the part **after the payload's
delivery**. The sampler's answer is computed at the server at request time and arrives up to its
own `curl -m 10` later, so the view it reports is a snapshot up to that much older than the arrival
the stamp records: a hidden lag of the slot rate × (the payload's snapshot → its delivery), up to
25 slots at 2.5/s and 37 at 3.7. This is only reachable when the view itself is stale-on-arrival —
a slow or early-snapshot external provider — which is exactly the **bank and view lagging together**
residual above; a live-and-current view carries a snapshot within its transfer time. It is a
**documented residual**, not bounded by `ELAPSED_HEAD_GAP_MAX` (that stamp is taken at the answer's
arrival, not its snapshot): a provider that snapshots getVoteAccounts at request and delivers 9 s
later, with instant free pets, mints with the bank 47 slots (≈19 s) behind the live chain — `N_HEAD`
(25) plus 22 hidden at 2.5 slots/s (measured, both trees — no regression; pinned as a DOCUMENTED
RESIDUAL in `test_elapsed_provider` (5l), with the snapshot-at-delivery control minting only up to
`N_HEAD`). Bounding it would need the sampler to stamp before its own call and treat (head answer −
payload request) as the gap, which fails toward blind on every slow tier; deferred with the gate's
wiring (6.4).

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
