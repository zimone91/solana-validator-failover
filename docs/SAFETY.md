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
