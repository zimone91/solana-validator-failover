# Split-brain residual — the partition double-sign and how to close it (v0.6.9)

This note documents the **one** double-sign scenario the RPC-based failover fences cannot fully
close on their own, what the current release does about it (the mitigation stack has grown
substantially since this note was first written for v0.6.3), the honestly-known remaining gaps,
and the options for closing it completely.

## The residual scenario

Double-sign = two nodes voting the **same staked identity** at the same time. The fences prevent
this by deciding, before a takeover, whether the staked identity is *still being voted*:

- **STANDBY/BACKUP takeover** is gated by the vote-liveness fence (external RPC view of the
  vote account's `lastVote`, with a cluster-max freshness reference) + external delinquency
  confirmation + the N3-anchored `TAKEOVER_DELAY`.
- **PRIMARY rpc-recovery** is gated by the same vote-liveness signal.

These all reason from an **external** vantage point. The residual is the case where the external
vantage point is **wrong or blind about a still-voting holder**:

> The live PRIMARY is **partitioned from the supermajority** (or under severe targeted DDoS) such
> that the cluster — and the failover's external RPCs — see it as **delinquent / not voting**,
> while it is in fact **still producing votes** into its side of the partition. STANDBY confirms
> "delinquent", sees `lastVote` frozen (it can't see the partitioned votes), clears the fence, and
> **takes over**. When the partition **heals**, the previously-partitioned PRIMARY's in-flight /
> just-landed votes collide with STANDBY's → **double-sign**.

The external fences cannot see "votes that exist but are invisible to us". `TAKEOVER_DELAY` +
multiple independent confirmations shrink the window but do not eliminate it.

## What the current release does (closure option #1 — layered, shipped v0.6.3 → v0.6.8)

**PRIMARY self-fence ("vote lease").** The closure must come from the **PRIMARY side**, because
only the PRIMARY can observe its *own* loss of supermajority contact. While STAKED, the PRIMARY
watches **LOCAL signals only** (an external-RPC outage never triggers a demote) and drops itself
to unstaked **during** the partition — before a heal can double-sign. Fail-safe: it can only ever
switch *to unstaked*. The signal set has grown release by release; all fire times were measured
live on the 2-node testnet:

1. **Frozen confirmed slot** (v0.6.3): LOCAL `getSlot(confirmed)` stops advancing for
   `SELF_FENCE_ISOLATION_SECS` (30) — a confirmed slot only advances when the supermajority
   confirms this node's view.
2. **LOCAL JSON-RPC silent** (v0.6.5 F1): the local RPC answers nothing for
   `SELF_FENCE_NOANSWER_SECS` (30), only armed once a baseline exists. Measured live: fires ~+33s.
3. **Own votes not landing / N6** (v0.6.7): own `lastVote` lags the same-payload cluster-max by
   > 32 slots sustained 20s — closes the **egress-only** blindness ("can hear, can't be heard")
   that the first two signals miss (found live as a −25s inversion in rc.1; re-tested after the
   fix: **+48s margin, zero overlap**). v0.6.8 **B2** adds reset hysteresis
   (`SELF_FENCE_VOTE_LAG_RESET_CYCLES=3` consecutive healthy cycles to clear the sustain timer),
   so flapping egress cannot indefinitely re-arm the window.
4. **getHealth behind** (optional): local node reports > `SELF_FENCE_MAX_BEHIND` slots behind.

**Bounded demote + hard-stop (v0.6.8 B1; hardened v0.6.9 H2/H4).** A self-fence is only as good as
its demote actually *completing*. Every demote/admin-socket call is bounded
(`timeout -k 5 $SETIDENTITY_TIMEOUT`) — since v0.6.9 (H4) on the **standby's take/give-back too**;
a wedged `set-identity` escalates to `_selffence_hard_stop` (`systemctl stop` →
`systemctl mask --runtime` when the stop failed → SIGTERM → SIGKILL) which **verifies the validator
is actually down before reporting success**, and since v0.6.9 (H2) **re-verifies after
`HARD_STOP_REVERIFY_SECS`** so a `Restart=always` resurrect reads as HARD STOP FAILED instead of a
false ✅. The promote/take path is bounded but never kills (fail-safe direction).

**Promoted-holder self-fence (v0.6.9 H1).** After a takeover the STANDBY is the holder, and it now
runs the **same self-fence** (same signals, knobs, 30s worst case) in its STAKED branch — demote =
give-back to its own unstaked identity + the B1/H2 hard-stop escalation — so the
holder-relinquishes-first invariant covers the **STANDBY→BACKUP hop** (30 + 30 ≤ the BACKUP's
120s). A self-fenced standby is **locked out of re-taking** for `SELF_FENCE_RETAKE_COOLDOWN`
(600s): its own fenced vote account reads delinquent+frozen *because it stopped voting it*, so
without the lockout the normal takeover gates would pass and it would take the identity right
back. The baseline that arms these fences is **persisted and restored** across a monitor restart
(v0.6.9 H3, freshness- and continuity-gated), and a **detection-only collision detector**
(v0.6.9 M5) pages when gossip shows the staked pubkey at a non-self endpoint while we hold it —
the one two-holder state no other gate can see.

**Cross-node timing invariant.** Spare `TAKEOVER_DELAY` (60 STANDBY / 120 BACKUP) ≥ PRIMARY
worst-case self-fence (30) + margin (30), so the holder relinquishes before any spare takes. The
spare's countdown is **anchored to last-seen-voting** (v0.6.7 N3), not first-delinquency.

**Option A fast-path (v0.6.8) does not weaken any of this.** A is OFF by default and skips *only
the remaining timer* when it has a **positive proof of relinquish** — the holder's known unstaked
pubkey appearing in gossip (15s CRDS TTL ⇒ fresh) at the **same ip:port endpoint** as the staked
identity's lingering entry, corroborated on two vantages. An unstaked identity structurally cannot
vote the staked account. External-confirm and vote-liveness gates still run; any missing knob ⇒
fail-closed to pure timer behavior. Philosophically, A is a first step from "two timers" toward a
*positive hand-off* (option #2) — but observational via gossip, not a private channel.

**Agave duplicate-instance backstop (defense-in-depth only).** Agave's own duplicate-instance
check (verified on 4.1.0-rc.1) makes the earlier-started twin exit — but it is **reactive** (a
brief both-running overlap can precede the kill) and **does not fire across a partition**, i.e.
exactly not in the residual scenario. It is never load-bearing in this design.

**Why this is still not a hard guarantee.** It remains two independent, well-tuned timers rather
than a coordinated lease hand-off: a sufficiently adversarial partition timing, a mis-tuned or
disabled self-fence, or a dishonest LOCAL RPC could still leave a narrow overlap. Hence the
closure options below.

## Known gaps in the current stack (honest list, as of v0.6.9)

- ~~**Promoted spare is not self-fenced.**~~ **Closed in v0.6.9 (H1):** the PRIMARY self-fence is
  ported into the standby's STAKED branch (same signals/knobs/defaults, `STANDBY_SELF_FENCE=true`),
  with the give-back demote bounded (H4), the B1/H2 hard-stop escalation, and a 600s post-fence
  **re-take lockout**. The holder-relinquishes-first invariant now covers the STANDBY→BACKUP hop
  (worst-case 30s + margin ≤ 120s); 3-node mode is no longer degraded after a failover.
  *Pending live validation on the 2-node stack before the tag (see the release gate).*
- ~~**Monitor restart during a validator stall disarms the no-answer fence.**~~ **Closed in v0.6.9
  (H3):** the self-fence baseline (frozen-slot / no-answer / vote-lag clocks + role) is persisted
  every cycle and restored on startup — freshness-gated (`STATE_MAX_AGE_SECS`) and
  continuity-gated (the stall clock is inherited only when the first post-restart read shows the
  stall/silence/lag is genuinely continuous). A restarted daemon over a still-stalled validator
  can fence immediately; a recovered validator clears instantly; a stale save restores nothing.
- **A fully-wedged validator** (admin socket dead too) cannot be demoted by software — the daemon
  pages URGENT (incl., since v0.6.9, at monitor startup and from the promoted standby) and the
  hard-stop path covers the wedged-but-killable case; a truly unkillable process needs option #3
  (witness/STONITH, v0.7).
- The frozen-slot sub-check has been proven by unit tests and its no-answer sibling live, but has
  not itself been isolated in a live test (low residual).
- **Adversarial timing remains the structural residual:** the stack is still two independent,
  well-tuned timers rather than a coordinated lease hand-off (see "Why this is still not a hard
  guarantee") — a sufficiently adversarial partition timing, a mis-tuned or disabled self-fence,
  or a dishonest LOCAL RPC could still leave a narrow overlap. The v0.6.9 collision detector (M5)
  makes the resulting two-holder state *visible* (🚨 page) but deliberately does not auto-resolve
  it; the real closure is option #2/#3 (v0.7).

## The three closure options

1. **PRIMARY self-fence (shipped, layered).** See above. Pros: no extra infrastructure, purely
   local, fail-safe. Cons: two uncoordinated timers (no positive hand-off), relies on the LOCAL
   RPC being honest, tuning trade-off between fast demote and false demotes.

2. **Private-heartbeat cooperative fencing (lease hand-off).** PRIMARY and STANDBY exchange a
   direct, out-of-band heartbeat (private link / second network path). STANDBY takes the staked
   identity **only after** PRIMARY positively acknowledges it has released it (or the lease has
   provably expired on a shared clock). Turns "two timers" into a **coordinated lease**. Pros: a
   real hand-off, much smaller window. Cons: needs a private channel that does **not** share the
   failure domain of the partition, and careful lease/clock design (a partitioned heartbeat must
   fail *closed*). Option A's gossip flip-watch is a zero-infrastructure approximation of the
   "positive acknowledgement" half of this.

3. **External witness with active STONITH.** A third, independent witness (separate network/region)
   arbitrates who may hold the identity and **forcibly fences** the loser — e.g. powers it off,
   revokes its network, or kills the validator process ("Shoot The Other Node In The Head") before
   the peer is allowed to take over. Pros: the strongest guarantee (the loser is *made* unable to
   vote). Cons: most infrastructure, a witness that must itself be partition-tolerant, and a
   genuinely destructive action that has to be perfectly safe.

These are complementary: #1 is the layered local fail-safe shipped now; #2 adds a positive
hand-off; #3 adds an external enforcer. A production "no double-sign under partition" guarantee
typically wants **#1 + (#2 or #3)**. Target: **v0.7**.

## When this MUST be fully closed

As of mid-2026: **SIMD-0204** (Slashable Event Verification — the enshrined Slashing Program that
records duplicate-block proofs **on-chain, permanently**) is active in the Agave v2.3 feature-gate
cycle — *detection and logging only, no stake is burned*. Economic penalties (**SIMD-0212**) are
expected only **after Alpenglow** (test cluster live since May 2026; mainnet targeted Q3–late
2026). So today a brief double-sign costs consensus disruption, reputation, and a permanent
on-chain record — not automatic stake loss. That changes with post-Alpenglow vote-equivocation
slashing. The residual above is exactly a vote-equivocation event.

> **Trigger:** the split-brain residual must be closed **fully** (option #1 plus a positive
> hand-off, #2 or #3) **before post-Alpenglow vote-equivocation slashing goes live**. Until then,
> the layered self-fence + N3-anchored `TAKEOVER_DELAY` + multi-confirmation is the operating
> mitigation, and the TESTNET-RUNBOOK isolation/flap/egress-only scenarios are the validation gate.

> **Alpenglow note (research pending):** Alpenglow replaces TowerBFT (and the tower file) with
> Votor/BLS certificates. This design deliberately never transfers tower files, which ages well —
> but the vote-liveness fence and delinquency semantics (`lastVote`, lockouts) will need to be
> re-derived against Votor before this tool is certified on an Alpenglow cluster.
