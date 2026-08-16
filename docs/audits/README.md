# Audit history

Every release of this tool has been audited before shipping, and **every audit round found real
problems after someone had already declared the release ready** — including the maintainers. We
publish the rounds because "here is what was found and fixed" is verifiable; "trust us" is not.

Method used throughout: findings are only accepted when **verified by execution** (driving the real
functions with mocked I/O, or reproducing on a live testnet stack), never by reading alone. Every
safety fix ships with a **control test that fails when the fix is reverted** — the suite contains
no vacuous assertions of the form "the code we wrote is present".

| Round | Scope | Outcome |
|---|---|---|
| [Audits 1–2 (v0.6.8)](2026-06-audits-1-2-v0.6.8.md) | takeover speed-up design + implementation | 6 implementation fixes before tag |
| [Audit 3 (v0.6.9)](2026-06-audit-3-v0.6.9.md) | post-failover symmetry implementation | **NO-GO verdict**; 3 blockers fixed before tag |
| [Audit 5 (public release)](2026-07-audit-5-public-release.md) | the shipped v0.6.9 + its public claims | led to a public retraction of an overclaim, and a P0 fix list feeding v0.7 |
| [2026-08 field round](2026-08-field-round.md) | production incidents + interpreter matrix | the v0.6.10 hotfix, the re-run-safety fixes, the Unknown-identity paging |

Naming note: findings below carry the internal IDs used at the time (`S-1`, `A2`, `H1`, …). The
code still references some of them; a vocabulary rewrite to self-contained comments is part of the
v0.7 work.

A standing lesson from these rounds, recorded so readers can hold us to it: **every serious miss
lived in a seam** — installer↔daemon, restart↔persisted state, promotion↔fence-arming,
outage↔decision-window — not inside a function. Function-level tests are structurally blind there;
the v0.7 validation work exists specifically to close that class.
