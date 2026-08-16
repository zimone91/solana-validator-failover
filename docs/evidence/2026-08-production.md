# Production evidence — v0.6.9 in armed operation (August 2026)

Collected from **four armed nodes** (`DRY_RUN=false`): a mainnet primary/standby pair and a
testnet primary/standby pair. Hostnames and provider details redacted; timestamps and numbers are
as logged. This complements the staged testnet scenarios in
[SAFETY.md](../SAFETY.md#what-has-been-tested) — it is unstaged, real operation.

## 1. A real, unplanned mainnet failover

```
[2026-08-10 08:45:52] ALERT: TOOK STAKED ✅ — Delinquent 60s
  (T1:health✅ LOCAL:delinq✅(10/10) EXTERN:confirm✅ gossip:advisory liveness:frozen✅ ⚡turbo)
```

The mainnet primary's host was powered off (unplanned). The armed standby detected the loss, walked
every gate — local health, a full 10/10 delinquency window, external confirmation, advisory gossip,
a frozen vote-liveness read — and took the staked identity **exactly 60 seconds after the
countdown anchor**, as designed. The validator picked up voting on the new host. Every gate
decision is in the log line above.

## 2. Measured loop cadence (the number the v0.7 watchdog is sized against)

Derived from heartbeat counters over ~3.2 h windows per node:

| node | s / cycle |
|---|---|
| mainnet primary (real validator load) | 3.33 |
| mainnet standby | 3.23 |
| testnet primary | 3.12 |
| testnet standby | 3.22 |

At `CHECK_INTERVAL=3`, per-cycle overhead is **0.1–0.3 s — and mainnet load does not inflate the
loop**. Heartbeat gaps (nominal 60 s) stayed within ~63 s in these windows. Caveat, stated so
nobody over-reads this: heartbeats resolve to ~60 s, so rare multi-second stalls are invisible
here; a full-history log analysis (months, all four nodes) for the p99/p999 tail is in progress
and gates the v0.7 watchdog deadline.

## 3. An incident that shipped a fix

On 2026-08-10 at 23:20, during a manual failback, a validator was briefly brought up on a
*different* unstaked key than its monitor's config named. The monitor entered its
"unknown identity" state — in which the entire protection stack is inert — and reported it as a
routine warning. The armed mainnet standby was unprotected for that window, silently.

The config was correct; the operation deviated. It shipped as a fix within days (critical paging
on the unknown state, and a stricter primary dispatch — see the
[2026-08 field round](../audits/2026-08-field-round.md)), and it is recorded here because it is
the honest counterweight to §1: the same fleet that produced the clean save also produced the
incident. Evidence cuts both ways, or it is not evidence.
