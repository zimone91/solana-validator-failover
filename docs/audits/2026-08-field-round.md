# 2026-08 field round — production incidents and the interpreter matrix

**Scope.** Not a scheduled audit: a cluster of findings from armed production operation and from
the first run of the suite under a second bash interpreter. Everything here shipped as
`v0.6.10` and the three commits after it.

## The bash 5.2 alert-death bug (→ hotfix v0.6.10)

The first-ever run of the (always-green) suite under Ubuntu 24.04's bash 5.2 failed: bash 5.2
enables `patsub_replacement` by default, making `&` special in `${var//pat/repl}` replacements.
That silently corrupted the Telegram HTML escaper — **on bash 5.2 hosts, critical pages (demote /
takeover / self-fence / hard-stop) were rejected by Telegram and never delivered**, and custom
webhook templates could be mangled. Two of four production nodes — including the mainnet primary —
were affected; alerts from them had been dead since install. ntfy and the default JSON webhook
were unaffected (different construction), which is the only reason the fleet's alerting worked at
all. Fix: one `shopt` guard per script restoring the semantics the codebase is written against.
Consequence: the CI matrix runs both interpreters permanently — one interpreter *cannot* see this
class.

## The Unknown-identity incident (→ critical paging + primary dispatch fix)

During a manual failback, an operator briefly brought a validator up on a *different* unstaked key.
The standby's monitor classified its identity as "unknown" — a state in which **the entire
protection stack is inert** (no takeover logic, no self-fence, no collision detector) — and
reported it as a routine throttled warning. The armed mainnet standby sat dark during the exact
operation where it mattered most.

Fixes: the unknown state now **pages critically** on entry, re-pages while it persists, and
announces recovery. Auditing the same class on the primary found something sharper: its dispatch
was binary, so an unclassified identity fell into the *recovery* branch — meaning a node whose
config had drifted could hold the real staked key with its self-fence never armed, and (in rpc
recovery mode) an unclassified node could attempt to take the staked identity. The recovery branch
now requires an exact match on the configured unstaked key; an unclassified node can neither take
nor demote — only page.

## The re-run trap class (installer sticky defaults)

Re-running the wizard (the documented upgrade path) sources the existing config — but several
prompt *defaults* ignored it, so pressing Enter could silently downgrade a safety setting: convert
a BACKUP into a second STANDBY (two spares taking at once), lower the BACKUP's take-visibility
floor, reset lock-step-tuned timing to shipped values, or replace a working webhook with a fresh
unsubscribed channel. All prompts are now sticky, values below the shipped safe numbers warn in
red, and every fix carries a control test that fails on revert.

## The frozen-claims class (third occurrence)

A published claim drifted from reality three separate times: a stale suite count, a "tested on"
version whose upstream tag does not exist, and release-page bodies still carrying retracted
wording weeks after the docs were fixed. Public numbers are now checked **mechanically**: CI's
claims-vs-reality job compares the README's suite count and the test-gate manifest against the
actual files on every push, and "GitHub Release bodies" is a standing line on the propagation
checklist.
