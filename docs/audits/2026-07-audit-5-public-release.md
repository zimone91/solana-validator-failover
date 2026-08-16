# Audit 5 — the shipped v0.6.9 and its public claims, July 2026

**Scope.** The public release as a stranger meets it: the shipped code at tag `v0.6.9` *and* every
public claim made about it. Prior rounds audited diffs; this one audited the product.

**Method.** ~10 externally raised P0 claims were re-verified **by driving the real functions**
(sourcing each daemon to its main-loop boundary, mocking only I/O), then independently confirmed,
refuted, or sharpened. Several findings were *measured*, not argued.

## The headline outcome: a public retraction

The README had claimed the tool "guarantees two nodes never vote the same identity". The audit
established that the takeover gate reasons from **observation** (the vote account stopped
advancing, as seen from external RPC) — which is corroboration, not proof of the holder's
incapacity. The claim was withdrawn: the README gained an honest status note, `docs/SAFETY.md` an
explicit residual-risk section, and `docs/SPLIT-BRAIN-RESIDUAL.md` was published. Closing the gap
for real — making the holder's incapacity *true* rather than inferred — is the v0.7 fence work.

## Findings that fed the v0.7 fix list (execution-verified)

- **A1.** `VOTE_PUBKEY` was never bound to the staked identity: a real-but-wrong vote account could
  mislead the liveness fence, and the same unbound selector could silently disarm the holder's
  own-votes fence. (Runtime binding via `getVoteAccounts.nodePubkey` verified viable against agave
  source and scheduled for v0.7.)
- **A2.** The paired liveness samples discarded *which RPC provider answered* — a provider-lag
  mismatch between the two samples could fabricate a "frozen" verdict against a live holder.
- **A3/A4.** A too-generous liveness epsilon, and safety timers on wall clock (an NTP step during
  an incident could defeat both the takeover delay and the fence) — measured, not theorized.
- **A5.** Demote escalation keyed on two specific timeout exit codes; fast permanent failures left
  a node staked with only a page.
- **A6–A8.** An undocumented override that could disable the entire post-takeover protection
  stack; non-atomic state writes that could lose the re-take lockout; a blocking notification
  between the final verdict and the identity mutation (measured at 10 s of staleness).

Several originally reported claims were **refuted or narrowed** in the same round — the audit
records both directions deliberately.

## The propagation lesson

The retraction initially reached the README and SAFETY but **not** every surface an operator
actually meets (installer prompt text, changelog headline, the deployment manual's absolutes — and,
found later, the frozen GitHub release body). The claims-propagation checklist and the CI
claims-vs-reality gate exist because of this round.
