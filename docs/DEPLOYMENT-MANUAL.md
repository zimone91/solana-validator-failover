# Solana Validator Failover System v0.6.9 — Deployment Manual

> **Status:** read the honest-limits note in the [README](../README.md) and the safety model in
> [SAFETY.md](SAFETY.md) before arming anything. `DRY_RUN=true` is the shipped default everywhere.

> **v0.6.9 changes (vs v0.6.8) — `DRY_RUN=true` default unchanged.**
> **"Post-failover symmetry" hardening** — the protection the PRIMARY demote path already had is
> evened out across the states the system lives in *after* a failover. **H1 (the big one):** the
> PRIMARY self-fence is **ported into the promoted STANDBY's STAKED branch** (same signals, same
> knobs, same 30s worst case; master switch `STANDBY_SELF_FENCE=true`) — the "holder relinquishes
> before any spare takes" invariant now also covers the **STANDBY→BACKUP hop**, and a self-fenced
> standby is **locked out of re-taking** for `SELF_FENCE_RETAKE_COOLDOWN=600s` (its own fenced vote
> account looks delinquent — that's why it fenced). **H2:** a hard-stop now survives
> `Restart=always` — the unit is masked (`--runtime`) when `systemctl stop` fails, and the
> down-state is **re-verified after `HARD_STOP_REVERIFY_SECS=15`** so a resurrected validator pages
> `HARD STOP FAILED` instead of a false ✅. **H3:** the self-fence baseline (frozen-slot /
> no-answer / vote-lag clocks) is **persisted every cycle and restored** across a monitor restart
> (freshness-gated by `STATE_MAX_AGE_SECS=900`, continuity-gated on first-read evidence), so a
> daemon restart mid-stall no longer disarms the fence; the startup wait loop keeps the watchdog
> pinging and pages 🚨 if the persisted role was STAKED and the validator stays unreachable.
> **H4:** the standby take/give-back admin calls are **bounded** (`SETIDENTITY_TIMEOUT=15`,
> B1 parity) — a wedged take fails toward NOT taking; a wedged give-back escalates to the hard
> stop. **M5:** a **detection-only collision detector** (both daemons, while STAKED) pages
> `STAKED IDENTITY SEEN ELSEWHERE` on 2 consecutive gossip endpoint mismatches — never demotes.
> **M6:** `GIVE_BACK_MODE=auto` (never implemented) removed from the wizard and coerced to manual.
> **M7:** the installers now **offer to start (and enable) the service they stopped**. **M8:**
> `TIER2_RPC == TIER3_RPC` is detected (warn; fast-path fail-closed; wizard re-prompts). **M9:**
> a cross-node timing violation is now **fatal at startup** (opt-out: `ALLOW_UNSAFE_TIMING=true`,
> lab only). **M10:** role-specific state files (`state-primary` / `state-standby`, one-time
> migration). All new knobs are safe-by-default; see **"v0.6.9 — post-failover symmetry knobs"**.

> **v0.6.8 changes (vs v0.6.7) — `DRY_RUN=true` default unchanged.** Takeover
> **speedup + hardening**, all safe-by-default. **B1 (primary):** the demote `set-identity` /
> `authorized-voter` calls are bounded by `SETIDENTITY_TIMEOUT` (default 15s, `timeout -k 5` so a
> SIGTERM-ignoring CLI is SIGKILL'd rather than wedging the single-threaded loop); on a wedged admin socket
> the self-fence escalates to a **verified** hard stop (`SELF_FENCE_HARD_STOP=true`) so the staked identity
> provably stops voting (a stopped validator can't double-sign). The promote path is bounded but **fail-safe**
> (never kills). **B2 (primary + standby):** N6 own-vote-lag reset **hysteresis**
> (`SELF_FENCE_VOTE_LAG_RESET_CYCLES=3`) so a flapping/intermittent egress can't keep dodging the self-fence;
> plus a fatal startup assert `VOTE_LIVENESS_EPSILON ≤ EXPECTED_PRIMARY_VOTE_LAG_SLOTS/4`. **Option A
> (standby, OFF by default):** a *gossip identity-flip fast-path* — when the holder gracefully self-fences
> (re-advertises its **UNSTAKED** identity in gossip), the spare skips the remaining `TAKEOVER_DELAY` and
> proceeds to the **same** authoritative gates (external-confirm + `vote-liveness==frozen`); it skips **only
> the timer**, never a gate. Helps planned / no-answer / graceful failovers (~85 → ~30–40s); does **not**
> help crash / egress-only (no flip reaches the spare → the timer governs). **Phase 3 (lowering
> `TAKEOVER_DELAY` 60 → ~50) is intentionally NOT in this release** — the timer stays 60/30/30 pending an
> armed soak. Every untouched v0.6.7 fence/liveness/window/switch/takeover body is **byte-identical**. See
> **"v0.6.8 — takeover-speedup knobs & Option A"** below before enabling anything.

> **v0.6.7 changes (vs v0.6.6):** a High **safety** fix (N3) + installer guardrails. **N3:** the STANDBY
> takeover delay was anchored to *first-delinquent*, so a long **delinquent-but-still-voting** episode
> pre-consumed the delay and STANDBY could take the staked identity only ~10s after the holder finally
> went silent — while the PRIMARY self-fence still needs ~30s → ~20s double-staked overlap → double-sign
> on heal. The fix anchors the delay to the holder's **last observed vote**
> (`max(FIRST_DELINQUENT_TIME, LAST_LIVENESS_ACTIVE_TIME)`), so the full `TAKEOVER_DELAY` re-elapses from
> *actual* silence; `TAKEOVER_DELAY` and the cross-node numbers are **unchanged** (the fix changes the
> *anchor*, not the *length*). **Normal failover is unchanged (~70s)** — the anchor is inert when the
> holder is already silent before STANDBY checks. **Installer guardrails:** the deploy prompts now show a
> calm one-line "why" note for the safety-timing values and a RED nudge if `TAKEOVER_DELAY` is set below
> the cross-node-safe floor (`EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS`, derived in one
> place); the four hardcoded self-fence values stay hardcoded with a "don't tune in isolation" comment.
> No fence/liveness/window/switch/takeover body changed (byte-identical vs v0.6.6, incl.
> `staked_is_actively_voting`); `DRY_RUN=true` default unchanged; **deploy-prompt UX only** (no daemon
> behavior change). Built on the unmerged v0.6.6; the off-prod the internal testnet runbook still gates
> `DRY_RUN=false` and must now include the **N3 composed scenario** (delinquent-but-voting → silent) in
> the recorded **zero-overlap** result.

> **v0.6.6 changes (vs v0.6.5):** a cross-node **fail-over timing** fix from a second independent
> re-audit (N1 High, N2 Med). **N1:** the PRIMARY must RELINQUISH the staked identity (self-fence)
> *before* any spare can take it, or both hold staked across a partition heal → double-sign. The fix
> lowers the PRIMARY self-fence no-answer timer (`SELF_FENCE_NOANSWER_SECS` 60 → 30, matching
> `SELF_FENCE_ISOLATION_SECS`), raises the STANDBY `TAKEOVER_DELAY` preset 20 → **60** (= PRIMARY
> self-fence worst case 30 + a 30s cross-node margin), adds the STANDBY/BACKUP knobs
> `EXPECTED_PRIMARY_SELF_FENCE_SECS`/`SELF_FENCE_MARGIN_SECS` with a **loud startup warning** when
> `TAKEOVER_DELAY < EXPECTED + margin`, and enables fast-detect (`MAX_DELINQUENT_SLOTS=15`) so the
> end-to-end takeover stays ~70s. **N2:** the no-answer self-fence now demotes BEFORE its alert (the
> safety action never waits on notification I/O). The anti-double-sign margin is **unchanged** — only
> availability is traded (faster PRIMARY relinquish). No fence/liveness/window/switch/takeover body
> changed (byte-identical vs v0.6.5); `DRY_RUN=true` default unchanged. Built on the unmerged v0.6.5;
> the off-prod **`the internal testnet runbook` (now with scenario C3 measuring the real cross-node overlap)**
> still gates `DRY_RUN=false`, which requires a recorded **zero-overlap** result.
>
> **30s no-answer caveat:** lowering `SELF_FENCE_NOANSWER_SECS` to 30s is more false-fire-prone than
> 60s (a healthy node's JSON-RPC can stall ~30s under load/compaction). The demote is fail-safe
> (→ UNSTAKED, stops voting) so a false fire costs availability, not a double-sign — but **measure
> local JSON-RPC stall frequency on testnet** (runbook C3) and nudge it (with `TAKEOVER_DELAY`) back up
> if too twitchy. **Next (v0.6.8):** a *lite-witness fast-path* for sub-30s safe takeover — take over
> immediately once the PRIMARY's *unstaked* identity is positively seen fresh in gossip at its endpoint
> (+ staked liveness frozen), falling back to the full delay only for the ambiguous wedge case.

> **v0.6.4 changes (vs v0.6.3):** observability only — adds an external heartbeat watchdog
> ("dead-man's switch") and routes warning-level events to ntfy/webhook (not just Telegram). It does
> **not** change any failover decision logic, timing, thresholds, fences, or the existing critical
> alert behavior. See the **Notifications** section. (Built on the unmerged `v0.6.3`; the v0.6.3
> fence-gate below still applies before going live.)

> **v0.6.3 changes (vs v0.6.2):** acts on the agave-v4 behavior research. Same files, same flow,
> `DRY_RUN=true` default. ⚠️ Like v0.6.2, v0.6.3 changes the safety fence and **must pass the
> internal testnet runbook (extended with isolation/flap scenarios) on a non-mainnet cluster
> before going live.** Highlights:
> - **Vote-liveness is now the single AUTHORITATIVE fence; gossip is advisory.** A *staked*
>   pubkey's gossip entry persists ~48 h in CRDS, so a stale "dropped-but-present" entry can't be
>   told from a live holder — it must not block a takeover that liveness has cleared. Gossip now
>   only logs/corroborates; vote-liveness drives the decision (see **Split-brain fence**).
> - **Vote-liveness is REQUIRED.** With `VOTE_LIVENESS_VERIFY=false` the daemon refuses to start
>   (and never takes over) unless `ALLOW_UNFENCED_TAKEOVER=true` — closing the old "both fences
>   off → silent unfenced takeover" hole.
> - **RPC-freshness guard + `processed` sampling.** Liveness samples at `commitment=processed` and
>   requires the external RPC's cluster tip to advance between samples; a stalled/cached RPC →
>   "cannot determine → BLOCK" (closes a false-freeze → false-ALLOW hole).
> - **PRIMARY rpc-recovery gets vote-liveness parity** (re-take only if nobody is voting it).
> - **PRIMARY self-fence ("vote lease").** A STAKED node isolated from the supermajority (LOCAL
>   confirmed slot frozen) drops itself to unstaked *during* the partition — LOCAL signals only,
>   safe-direction only. Closes the residual partition double-sign (see **SPLIT-BRAIN-RESIDUAL.md**).
>
> Carries forward all v0.6.2 (vote-liveness/gossip fence, F3 ip:port) and v0.6.1/v0.6.0 fixes.
> **Known limit (now mitigated from the PRIMARY side):** under a full network partition of the live
> holder, no *external* RPC fence can see its votes — but the v0.6.3 self-fence uses LOCAL
> confirmed-slot stall to drop the isolated node before a heal. The remaining residual and its
> closure options are tracked in **SPLIT-BRAIN-RESIDUAL.md**.

## Architecture

```
┌──────────────────────────────────┐     ┌──────────────────────────────────┐
│       PRIMARY (v0.6.2)           │     │      STANDBY (v0.6.2)            │
│                                  │     │                                  │
│  LOCAL: delinquency (every 1-3s) │     │  LOCAL: delinquency (every 1-3s) │
│  LOCAL: internet ping (parallel) │     │  LOCAL: own health (getHealth)   │
│  T2/T3: confirm only on trigger  │     │  T2/T3: confirm only on trigger  │
│                                  │     │  Fence: liveness (gossip advis.) │
│  Identity: STAKED                │────→│  Identity: UNSTAKED              │
│  (normal operation)              │     │  (hot spare)                     │
└──────────────────────────────────┘     └──────────────────────────────────┘
                                                          │
                                         ┌────────────────▼────────────────┐
                                         │      BACKUP (v0.6.2)            │
                                         │  TAKEOVER_DELAY=120s            │
                                         │  GOSSIP_VERIFY=false            │
                                         │  Fence: vote-liveness (real!)   │
                                         └─────────────────────────────────┘
```

### RPC cost model

Normal operation: **0 external RPC calls**. Everything via LOCAL RPC.

| Function | RPC | When called |
|    ---    |    ---    |    ---    |
| tier1_check_local_health | LOCAL | every cycle |
| local_check_delinquency | LOCAL | every cycle |
| confirm_delinquency_external | T2 → T3 | only when window 7/10 triggered |
| check_primary_dropped_identity | T2 / T3 | once before takeover |

### Failure scenario (3-server)

1. PRIMARY: Internet lost → parallel pings fail 3x → switch to unstaked (~9s). OR isolated from the
   supermajority (LOCAL confirmed slot frozen / LOCAL JSON-RPC silent) → **self-fence** to unstaked at
   ~30s (`SELF_FENCE_ISOLATION_SECS`/`SELF_FENCE_NOANSWER_SECS`) — it relinquishes BEFORE any spare takes.
2. STANDBY: LOCAL RPC sees delinquent → sliding window 7/10 → external confirm → **fence (vote-liveness authoritative; gossip advisory)** → takes staked (~70s: `TAKEOVER_DELAY=60` after the PRIMARY has relinquished at ~30s, with a 30s cross-node margin)
3. BACKUP: Same with 120s delay + the **vote-liveness** fence (no longer blind). Only activates if STANDBY also stopped voting (~130s)
4. PRIMARY (rpc mode): checks T2/T3 → sees STANDBY holds/votes the identity → stays unstaked

### Split-brain fence (v0.6.3 — vote-liveness authoritative, gossip advisory)

Taking the staked identity is the one dangerous action (two nodes voting it = double-sign — today a
consensus/reputation hit and, once on-chain slashing detection activates, a permanent record). **Vote-liveness is the single authoritative gate**; gossip is advisory.

- **Vote-liveness (AUTHORITATIVE, REQUIRED, all roles incl. BACKUP).** Is the staked **vote
  account** producing votes right now? The daemon samples `lastVote` twice across `TAKEOVER_DELAY`
  at `commitment=processed` (fresher/less bursty than finalized). If it **advanced**
  (> `VOTE_LIVENESS_EPSILON` slots), a holder is voting → **BLOCK** + alert. If it is **frozen**,
  the holder is not voting → clear. If `lastVote` is **unavailable** (externals down) → **BLOCK**
  (same "cannot confirm → don't take" rule as the delinquency check). Topology-independent: it
  does not matter which IP/port holds the identity, how many servers exist, or that a brand-new
  node appeared — only whether *someone* is voting.
  - **RPC-freshness guard (v0.6.3):** the daemon also reads a cluster-wide freshness reference — the
    **max `lastVote`** across all vote accounts — from the **same `getVoteAccounts` payload**. A
    "frozen" staked `lastVote` only clears the fence if that reference **advanced** between samples;
    a stale/cached/lagging RPC view (frozen reference) → **cannot determine → BLOCK**. Because the
    staked `lastVote` and the reference come from one atomic snapshot, a stale view cannot show a
    fresh reference alongside a stale `lastVote` — closing the false-freeze → false-ALLOW hole
    (including the cross-RPC / asymmetric-cache case a decoupled `getSlot` would miss).
- **Gossip (ADVISORY only, v0.6.3).** It logs where the staked pubkey is seen (and whether it is a
  self/non-self endpoint, full `ip:port`), and may corroborate the verdict — but it **no longer
  blocks** a takeover that vote-liveness has cleared. Reason: a **staked** pubkey's gossip
  ContactInfo persists in CRDS for **~48 h** (epoch-length timeout), so a "dropped-but-stale" entry
  is indistinguishable from a live holder and would otherwise stall a legitimate takeover for hours.
  The reliable fast signals are an **overwrite** (the new holder re-publishing) and **positive
  vote-liveness**, not entry-disappearance.

`VOTE_LIVENESS_VERIFY=true` is **required**. With it off the daemon **refuses to start** and never
takes over, unless you explicitly set `ALLOW_UNFENCED_TAKEOVER=true` — which removes all
split-brain protection (double-sign risk). Leave both at their defaults.

### Manual switch protection (PRIMARY)

If operator manually runs `set-identity staked`, the script detects the change,
resets the delinquency window, and applies a 30s grace period before resuming
monitoring. Prevents the script from switching back to unstaked immediately.

---

## Design invariants

These hold on every node; the deploy scripts and the failover daemon enforce or check them.

- **Startup `--identity` must be the UNSTAKED keypair (hard requirement).** Failover manages the
  voting identity at *runtime*. The validator's `solana.service` is `Restart=always`, so if it
  ever restarts it must come back **not voting** — i.e. booting on the unstaked identity.
  Booting on the staked identity means a restart instantly starts voting on this node,
  which can double-sign against whichever node currently holds the stake. Enforcement (v0.6.5 F2):
  - **Deploy scripts HARD FAIL** if the running validator's `--identity` resolves to the staked
    key. Override only with an explicit ack — `--allow-staked-startup-identity` (or
    `ALLOW_STAKED_STARTUP_IDENTITY=true`) — which downgrades it to a warning.
  - **The daemon emits an URGENT alert at startup** if the validator was started on the staked
    identity. It does **not** refuse to run — refusing would leave the node unmonitored; a loud,
    persistent page is the safer choice.
  - **Recommended fix — the Anza `identity.json` symlink.** Point `solana.service`'s startup
    `--identity` at a soft link (e.g. `identity.json`) that targets the **unstaked** keypair, and
    repoint it on each transition. A restart then always fails safe to unstaked. If your
    validator's unit is managed by your own deployment tooling, make that startup-flag change
    through that tooling so it survives redeploys.
- **`staked ≠ unstaked`.** Each node has a unique unstaked keypair; the staked keypair is
  shared. The scripts refuse to start (and deploy refuses to finish) if the two are equal,
  or if either pubkey cannot be derived.
- **Safe direction is "drop to unstaked".** PRIMARY going unstaked on internet loss,
  delinquency, or **isolation from the supermajority** (the v0.6.3 self-fence, below) is always
  safe (a non-voting node can't double-sign) and is **never blocked**. Taking the staked identity
  is the dangerous direction and is gated by external delinquency confirmation **plus** the
  vote-liveness fence.
- **A node actively voting the staked identity blocks everyone else.** The vote-liveness
  fence (see **Split-brain fence**) is the authoritative anti-double-sign check and is used by
  all roles, including BACKUP. "Advancing → BLOCK"; "frozen → clear"; "can't tell → BLOCK".
- **STANDBY takeover needs POSITIVE external confirmation + a clear vote-liveness fence**
  (gossip is advisory). "Could not confirm" (external RPCs unreachable) does **not** cause
  takeover; it holds and retries. *(v0.6.5 F3: `ALLOW_TAKEOVER_WHEN_EXTERNAL_RPC_DOWN` is removed —
  it could never force a takeover because the authoritative vote-liveness fence also needs the
  external RPCs to sample `lastVote`, so a both-externals-down takeover blocked regardless. The one
  explicit emergency local-only path is `ALLOW_UNFENCED_TAKEOVER=true` with `VOTE_LIVENESS_VERIFY=false`,
  which disables the split-brain fence entirely.)*
- **Automatic `set-identity` runs WITHOUT `--require-tower`;** PRIMARY still deletes the
  staked tower when it goes unstaked. `--require-tower` is correct only in the operator-
  driven switch-back, where the live tower is copied with the identity (see Manual
  switch-back).
  - **Why no-tower `set-identity` is safe here (the on-chain floor).** Without a local tower,
    agave does **not** vote from an empty tower — it seeds the lockout floor from the **on-chain
    vote account** (`initialize_lockouts_from_bank`), i.e. the vote account's *last landed* vote.
    That floor is a real safety net, but it lags **in-flight votes** (submitted but not yet landed),
    so a no-tower takeover is double-sign-safe **only while the previous holder is genuinely not
    voting** — which is exactly what the delinquency-confirm + vote-liveness fences are built to ensure
    (they are strong evidence, not proof — see SPLIT-BRAIN-RESIDUAL.md). This
    is why vote-liveness is mandatory and `TAKEOVER_DELAY` covers the in-flight-vote window. A
    *corrupt/wrong* tower does not silently fall back — agave exits; only a truly-missing/too-old
    tower rebuilds from the bank.
- **Delinquency threshold = 128 slots** (`DELINQUENT_VALIDATOR_SLOT_DISTANCE`; `getHealth` uses the
  same 128). A vote account is `current` iff `lastVote > tip − 128`, else `delinquent`. Reason in
  **slots, not seconds** — mainnet slot time varies and `lastVote` (read at finalized by default)
  lags and advances in bursts; the daemon samples liveness at `processed` and uses a slot-delta
  rule, never a wall-clock conversion.

### Compatibility & tuning notes

- **Validator engine:** **agave only** is supported for now. The `frankendancer` (`fdctl`)
  path exists in the scripts but is **experimental** — the deploy menu labels it as such.
  Full Frankendancer support is planned.
- **agave v4.1 operator note (deploy tooling, not this repo):** on agave **v4.1**, migrate the
  validator's XDP flags `--experimental-retransmit-xdp-*` → `--xdp-*` in your `validator.sh`
  (and run **beta.3+** — earlier v4.1 betas had a `set-identity`→repair-ping regression). v4.0.x
  is unaffected. This is your validator's startup tooling, not the failover scripts.
- **Vote-latency trigger (`MAX_VOTE_LATENCY` / `MAX_DELINQUENT_SLOTS`):** off by default
  (`0`). Enabling it makes detection faster by treating "N slots behind on `lastVote`" as
  delinquent before the cluster marks the node delinquent. It only moves PRIMARY toward
  *unstaked* (the safe direction) and STANDBY still requires external confirmation + the authoritative vote-liveness fence (gossip advisory),
  so it is safe to opt into; left opt-in to avoid false positives on a busy node.
- **Recovery mode (`RECOVERY_MODE`):** `manual` is the **default and recommended** path —
  operator-driven switch-back (see Manual switch-back). `rpc` is an **opt-in** automatic path:
  in v0.6.3 it gets **vote-liveness parity** — PRIMARY re-takes the staked identity only when the
  vote account is **not being voted** (frozen over the interval, external tip advancing); if it is
  advancing (the STANDBY holds it), recovery is refused. The v0.6.2 full-`ip:port` gossip check
  stays as advisory corroboration (it can still abort recovery — the safe direction). `manual`
  remains recommended because automatic re-take is inherently riskier than a human deciding. The
  daemon logs a startup notice when `rpc` is selected. `auto` is reserved/disabled.

- **PRIMARY self-fence / "vote lease" (`PRIMARY_SELF_FENCE`, v0.6.3):** mitigates the residual
  partition case — a PRIMARY that is alive but **isolated from the supermajority** (partition /
  severe DDoS) looks dead to the cluster yet keeps voting, then heals into a double-sign. While
  STAKED, the daemon watches its **LOCAL** `getSlot(commitment=confirmed)`; if that confirmed slot
  does not advance for `SELF_FENCE_ISOLATION_SECS` (default 30) it concludes it is isolated and
  drops itself to **unstaked** — *during* the partition, before a heal. Optionally, a LOCAL
  `getHealth` "behind by > `SELF_FENCE_MAX_BEHIND`" (default 150; 0 = off) demotes faster.
  - **LOCAL signals only.** No external (T2/T3) RPC can ever trigger a self-fence (an external-RPC
    outage must not cause a failover).
  - **Continuously-silent LOCAL RPC (`SELF_FENCE_NOANSWER_SECS`, v0.6.5 F1).** A LOCAL
    `getSlot(confirmed)` that does not answer is normally the "validator unreachable" pause path, and a
    *brief* gap is not isolation. But if the LOCAL JSON-RPC stays silent for `SELF_FENCE_NOANSWER_SECS`
    (default 30; `0` = off) **while the node still holds staked and a confirmed-slot baseline already
    exists**, that silent-but-staked state is itself isolation: the node may be partitioned/wedged yet
    still voting, while STANDBY confirms delinquency + frozen liveness and takes over → heal
    double-sign. The daemon then **demotes to unstaked first, then urgent-alerts** (v0.6.6 N2: the safety action never waits on notification I/O). It never arms on a
    fresh start (no baseline) and any successful read resets the timer.
  - It can **only ever** lead to `switch_to_unstaked` (the safe direction), respects `DRY_RUN`
    (logs "would self-fence", no swap) and the startup / manual-change grace, and is disabled with
    `PRIMARY_SELF_FENCE=false`.
  - **Fully-wedged residual.** The demote uses `set-identity` via the admin RPC; in the target case
    (admin RPC up, JSON-RPC silent) it succeeds. If the validator is *fully* wedged (admin RPC down
    too) the demote cannot run — the main loop's "validator unreachable" path then fires an **urgent**
    alert when the last-known identity was STAKED. Closing this residual for real needs an external
    witness/STONITH (tracked for v0.7; see **SPLIT-BRAIN-RESIDUAL.md**).

---

## Files

```
PRIMARY (/opt/solana-failover/):
├── solana-primary-failover.sh    # Main script
└── failover.env                      # Configuration

STANDBY/BACKUP (/opt/solana-failover/):
├── solana-standby-failover.sh    # Standby/backup script
└── failover-standby.env              # Configuration

/etc/systemd/system/
├── solana-failover.service           # PRIMARY systemd unit
└── solana-failover-standby.service   # STANDBY/BACKUP systemd unit
```

---

## Core features (added in v0.5.9, carried forward)

- **LOCAL-first architecture**: normal cycle uses only LOCAL RPC (0 external calls, 0 CU)
- **Turbo mode**: adaptive interval — 1s checks when delinquency detected, normal 3-5s otherwise
- **Parallel pings**: PRIMARY internet detection runs all 3 pings simultaneously (~1.5s vs ~3s)
- **Gossip pre-fetch**: STANDBY starts gossip query during takeover delay, ready when delay expires
- **Sliding window**: "7 out of 10" instead of "5 consecutive" — survives DDoS flickering
- **Manual switch protection**: PRIMARY detects external set-identity, resets window + 30s grace
- **STANDBY/BACKUP role selector**: deploy auto-sets defaults (delay, gossip, interval)
- **RPC health alerts**: TIER2 unreachable during confirmation → throttled alert (10 min)
- **Heartbeat**: periodic status log with ping results and stats (configurable interval)
- **ntfy.sh push**: auto-detected by URL, Priority: urgent (pierces Do Not Disturb)
- **Faster verification**: sleep 2→1s after set-identity
- **False positive protection**: LOCAL detects → external T2/T3 confirms → vote-liveness fence (gossip advisory)

---

## Quick Deploy

### PRIMARY

```bash
mkdir -p /root/failover-deploy && cd /root/failover-deploy
# Upload: solana-primary-failover.sh, deploy-failover.sh
bash deploy-failover.sh
```

### STANDBY / BACKUP

```bash
mkdir -p /root/failover-deploy && cd /root/failover-deploy
# Upload: solana-standby-failover.sh, deploy-failover-standby.sh
bash deploy-failover-standby.sh
# Deploy asks: STANDBY or BACKUP role — sets defaults automatically
```

### Update existing (no re-deploy)

```bash
# Just replace scripts, keep config:
cp solana-primary-failover.sh /opt/solana-failover/
cp solana-standby-failover.sh /opt/solana-failover/
systemctl restart solana-failover
systemctl restart solana-failover-standby
```

---

## v0.6.9 — post-failover symmetry knobs

All safe-by-default; the installers write them automatically (no new prompts beyond M7's start
offer and M8's re-prompt-on-equal). Hand-edits: `systemctl restart solana-failover[-standby]`.

### H1 — promoted-STANDBY self-fence (`failover-standby.env`)
| Knob | Default | Meaning |
|---|---|---|
| `STANDBY_SELF_FENCE` | `true` | Master switch for the promoted-holder self-fence (the PRIMARY's port). `false` = pre-v0.6.9 "hold unfenced" (NOT recommended in 3-node mode). |
| `SELF_FENCE_ISOLATION_SECS` / `SELF_FENCE_NOANSWER_SECS` / `SELF_FENCE_MAX_BEHIND` / `SELF_FENCE_VOTE_LAG_SLOTS` / `SELF_FENCE_VOTE_LAG_SECS` / `SELF_FENCE_VOTE_LAG_RESET_CYCLES` | `30/30/150/32/20/3` | Same signals, names and defaults as the PRIMARY's block — see the PRIMARY self-fence section. LOCAL signals only; demote = give-back to this node's own unstaked key. Do **not** raise the `*_SECS` without raising the BACKUP's `EXPECTED_PRIMARY_SELF_FENCE_SECS` + `TAKEOVER_DELAY` in lock-step. |
| `SETIDENTITY_TIMEOUT` | `15` | H4: bounds every take/give-back admin-socket call (≥ 8). Take timeout → fail toward NOT taking; give-back timeout → escalate. |
| `SELF_FENCE_HARD_STOP` | `true` | A wedged give-back (identity did not flip) hard-stops the validator (stop → mask → SIGTERM → SIGKILL, verified + re-verified). Never fires on the take path or in DRY_RUN. |
| `SELF_FENCE_RETAKE_COOLDOWN` | `600` | **Safety-critical.** After a self-fence demote, `attempt_takeover` refuses for this long (persisted across monitor restarts) — the fenced vote account looks delinquent *because we stopped voting it*; without the lockout the standby would take the identity right back. After expiry every normal gate must pass fresh. `0` disables (NOT recommended). |

### H2/H3/M5 — both daemons (`failover.env` + `failover-standby.env`)
| Knob | Default | Meaning |
|---|---|---|
| `HARD_STOP_REVERIFY_SECS` | `15` | H2: re-verify the hard-stop after this delay (≥ the validator unit's `RestartSec`). A resurrected process = `HARD STOP FAILED` page. When `systemctl stop` failed, the unit is masked `--runtime` first — recovery: `systemctl unmask --runtime solana`. |
| `STATE_MAX_AGE_SECS` | `900` | H3: restore the persisted self-fence baseline only from a save fresher than this (stale = discarded; fresh timers). |
| `STARTUP_STAKED_UNREACHABLE_ALERT_SECS` | `60` | H3: persisted-STAKED + validator unreachable this long at monitor startup → 🚨 `… UNREACHABLE WHILE STAKED` (once per startup). |
| `COLLISION_CHECK_INTERVAL` | `60` | M5: while STAKED, compare the external gossip endpoint of the staked pubkey vs our own; 2 consecutive mismatches → 🚨 `STAKED IDENTITY SEEN ELSEWHERE (possible collision)` (throttled). **Detection-only — never demotes** (loser-selection under a real collision is the operator's call; see *Emergency: Split-Brain*). |

### M9 — standby/BACKUP startup gate (`failover-standby.env`)
| Knob | Default | Meaning |
|---|---|---|
| `ALLOW_UNSAFE_TIMING` | `false` | A violation of `TAKEOVER_DELAY ≥ EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS` is now **fatal at startup** (was warn-only). `true` restores warn-and-continue — **lab/testing only** (double-sign risk on heal). |

### M10 — state files
`STATE_FILE` defaults are now role-specific: `/var/lib/solana-failover/state-primary` and
`…/state-standby` (colocated lab roles no longer clobber each other; H3 makes the file
load-bearing). A legacy `…/state` file is migrated once at startup; operator overrides are left
alone.

---

## v0.6.8 — takeover-speedup knobs & Option A

All new knobs are **safe-by-default**: a fresh deploy is behaviourally identical to v0.6.7 (Option A OFF,
timer unchanged). The interactive installers write them; you can also hand-edit the env (then
`systemctl restart solana-failover`).

### B1/B2 — primary hardening knobs (`failover.env`)
| Knob | Default | Meaning |
|---|---|---|
| `SETIDENTITY_TIMEOUT` | `15` | Bounds the demote/promote `set-identity`/`authorized-voter` admin-socket calls (≥ the read path's 8s). Uses `timeout -k 5` → SIGKILL if the CLI ignores SIGTERM. |
| `SELF_FENCE_HARD_STOP` | `true` | On a **demote** timeout, hard-stop the validator (`systemctl stop` → SIGTERM → SIGKILL) and **verify** it stopped, so the staked identity provably stops voting. `false` = alert only (NOT recommended — re-opens the wedge gap). Never fires in `DRY_RUN` or on the promote path. |
| `SELF_FENCE_VOTE_LAG_RESET_CYCLES` | `3` | N6 hysteresis: the own-vote-lag sustain timer clears only after this many **consecutive** healthy cycles, so a flapping egress (one vote burst per `< SELF_FENCE_VOTE_LAG_SECS`) can't keep dodging the self-fence. Must be ≥ 2. |

### B2 — standby coupling assert (`failover-standby.env`)
| Knob | Default | Meaning |
|---|---|---|
| `EXPECTED_PRIMARY_VOTE_LAG_SLOTS` | `32` | **Must match the PRIMARY's `SELF_FENCE_VOTE_LAG_SLOTS`.** Startup asserts `VOTE_LIVENESS_EPSILON ≤ this/4` so a holder still landing votes inside its own self-fence band is always seen here as "voting" → BLOCK. `0` = skip the assert. |

### Option A — gossip identity-flip fast-path (`failover-standby.env`, OFF by default)
| Knob | Default | Meaning |
|---|---|---|
| `WITNESS_FASTPATH` | `false` | Master switch. `false` = pure v0.6.7 timer behaviour. |
| `PRIMARY_UNSTAKED_PUBKEY` | `""` | Space-separated **unstaked** pubkey(s) of the *other* staked-capable node(s) to watch in gossip. **Must NOT be the staked pubkey** (the daemon refuses to start if it is). Empty ⇒ disabled. |
| `STANDBY_TAKEOVER_DELAY` | `""` | The **STANDBY's** `TAKEOVER_DELAY`, set the **same on every spare**. The node enforces an effective stagger `= max(FASTPATH_STAGGER_SECS, TAKEOVER_DELAY − STANDBY_TAKEOVER_DELAY)`, so a BACKUP can never fast-take ahead of the STANDBY. Empty / non-numeric / `> TAKEOVER_DELAY` ⇒ disabled (fail-closed). |
| `WITNESS_FASTPATH_FIRST_SPARE` | `false` | **Set `true` ONLY on the STANDBY.** A zero stagger floor (i.e. `STANDBY_TAKEOVER_DELAY ≥ TAKEOVER_DELAY`) = fast-take with no delay — allowed only for the one declared first spare. A zero floor without this `true` ⇒ fast-path **disabled (fail-closed)**, so a BACKUP that mistakenly sets `STANDBY_TAKEOVER_DELAY` to its *own* delay cannot silently race the STANDBY into a two-spare take. (The deploy wizard sets this automatically per role.) |
| `FASTPATH_PEER_RECOVERY_MANUAL` | `false` | Operator affirmation that **all** staked-capable peers run `RECOVERY_MODE=manual` (no auto re-stake). The fast-path never fires unless `true`. |
| `FASTPATH_CONFIRM_SAMPLES` | `2` | Consecutive corroborated cycles before firing. |
| `FASTPATH_STAGGER_SECS` | `0` | Extra per-node stagger floor; usually 0 (the node computes the required floor from `STANDBY_TAKEOVER_DELAY`). |

**What the fast-path does NOT change.** It only skips the *timer wait*. A take still requires the
external-confirm to say delinquent **and** `staked_is_actively_voting()==frozen` (a fresh ≥`MIN_INTERVAL`
sample); `voting` and `cannot-determine` both BLOCK exactly as on the timer path. The holder must already
be on its unstaked identity (which structurally cannot vote the staked account) for the flip to be visible.

**The flip is anchored to the holder (v0.6.8 F-A).** The fast-path fires only when a watched unstaked
pubkey appears **at the same gossip endpoint (`ip:port`) as the staked identity** — read from the staked
identity's own lingering (~48h) CRDS entry in the *same* `getClusterNodes` payload. `set-identity` keeps
ports, so a self-fenced holder re-advertises its unstaked identity at exactly the endpoint its staked
identity last used. This makes the **multi-peer watch-list safe**: you may list every staked-capable peer's
unstaked pubkey, but only the *current holder's* unstaked-at-the-staked-endpoint triggers a fast-take — a
non-holder peer going unstaked at its *own* endpoint is ignored. If the staked identity is absent from
gossip (cannot anchor), the fast-path does not fire and the timer governs.

**Enabling Option A (3-server recipe).** On **both** the STANDBY and the BACKUP:
1. Set `WITNESS_FASTPATH=true`.
2. `PRIMARY_UNSTAKED_PUBKEY` = the unstaked pubkey(s) of every *other* staked-capable node (on STANDBY:
   the PRIMARY's, and the BACKUP's if it can hold staked; on BACKUP: the PRIMARY's and the STANDBY's).
3. `STANDBY_TAKEOVER_DELAY` = the **STANDBY's** `TAKEOVER_DELAY` (e.g. 60) — the SAME value on both nodes.
   (On the STANDBY this yields stagger floor 0; on the BACKUP, `120 − 60 = 60s`, so it can't take first.)
3a. `WITNESS_FASTPATH_FIRST_SPARE=true` on the **STANDBY only**; leave it `false` on the BACKUP. (Belt-and-
   suspenders for step 3: if a BACKUP is mistakenly given a zero stagger floor it fails closed instead of
   racing the STANDBY.) The deploy wizard sets this for you based on the role you pick.
4. Confirm every staked-capable node runs `RECOVERY_MODE=manual`, then set `FASTPATH_PEER_RECOVERY_MANUAL=true`.
5. Ensure both `TIER2_RPC` and `TIER3_RPC` are set (the flip must be corroborated on two vantage points).
Any missing/invalid item ⇒ the fast-path stays disabled (fail-closed) and the proven timer governs; the
startup banner prints the live fast-path state (`ARMED` / `DISABLED (fail-closed): <reason>`).

> **The STANDBY is the fast-path's main beneficiary.** A BACKUP only begins recording the holder's
> absent→present flip *after* it crosses its own stagger floor, so when the holder self-fences early
> (the common graceful case) the BACKUP typically never observes a fresh absent edge and simply falls
> back to the timer — by design, the STANDBY (floor 0) is the one that fast-takes. Don't expect the
> BACKUP to fast-take in normal operation; its value is the stagger-protected last line of defense.

> **Phase 3 (NOT in this release).** Lowering `TAKEOVER_DELAY` (60→~50) / `EXPECTED`/`MARGIN` is gated on an
> armed soak. The timer stays 60/30/30 — do not lower it. (Historical note: the cross-node timing
> guardrail was warn-only when this was written; **since v0.6.9 it is FATAL at startup** unless
> `ALLOW_UNSAFE_TIMING=true`.)

---

## Recommended settings (3-server)

| Parameter | PRIMARY | STANDBY | BACKUP |
|---|---|---|---|
| CHECK_INTERVAL | 3 | 3 | 5 |
| TURBO_INTERVAL | 1 | 1 | 1 |
| TAKEOVER_DELAY | — | **60** | 120 |
| MAX_DELINQUENT_SLOTS | — | 15 | 15 |
| SELF_FENCE_ISOLATION_SECS | 30 | — | — |
| SELF_FENCE_NOANSWER_SECS | **30** | — | — |
| EXPECTED_PRIMARY_SELF_FENCE_SECS | — | **30** | **30** |
| SELF_FENCE_MARGIN_SECS | — | **30** | **30** |
| GOSSIP_VERIFY | — | true | **false** |
| VOTE_LIVENESS_VERIFY | — | true | **true** |
| DRY_RUN | false | false | false |
| RECOVERY_MODE | manual | — | — |
| WINDOW (threshold/size) | 7/10 | 7/10 | 7/10 |

GOSSIP_VERIFY=false for BACKUP: if STANDBY took identity and crashed, gossip
still shows staked on STANDBY's endpoint for 5-10 min, which would block BACKUP.
So gossip is off, but **VOTE_LIVENESS_VERIFY=true** gives BACKUP a real fence:
it takes over only once the staked vote account stops advancing (the crashed
STANDBY is no longer voting) — plus the 120s delay + window + external confirm.

**Numeric config is validated at startup (v0.6.5 F4).** Every timing/threshold knob must be a
non-negative integer — a non-numeric value (`abc`, `10s`) reads as `0` in bash arithmetic and would
silently collapse a delay/interval. The daemon rejects a bad value and refuses to start, normalizes
leading-zero entries (`10#`, octal-safe), and asserts `TAKEOVER_DELAY >= VOTE_LIVENESS_MIN_INTERVAL`
so the second `lastVote` sample is reachable within the takeover delay (the deploy prompts mirror
these checks).

**Installer guardrails (v0.6.7, deploy-prompt UX only).** The interactive deploy now shows a calm
one-line "why" note alongside the safety-timing prompts and a **red nudge** when `TAKEOVER_DELAY` is
entered **below** the cross-node-safe floor — `EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS`
(`= 60` by default), derived in one place so the note, the nudge, and the daemon's startup warning all
agree. It is a *nudge, not a block*: the existing clamp still raises a too-low value to the floor.
`MAX_DELINQUENT_SLOTS` gets a why-note only (it is detection speed, not a double-sign value). The four
hardcoded self-fence values (`SELF_FENCE_ISOLATION_SECS`/`SELF_FENCE_NOANSWER_SECS` on the PRIMARY;
`EXPECTED_PRIMARY_SELF_FENCE_SECS`/`SELF_FENCE_MARGIN_SECS` on the spares) stay hardcoded, each with a
"don't raise without raising every spare's `EXPECTED` + `TAKEOVER_DELAY` in lock-step" comment. No daemon
behavior changed.

**Cross-node delay ordering (operator-enforced; FATAL at startup since v0.6.9 M9).** Two hard rules
keep the nodes from ever holding the staked identity at the same time. Each daemon validates its own
knobs — no daemon can read another node's config — and since **v0.6.9 (M9)** a spare whose
`TAKEOVER_DELAY` violates Rule 1 **refuses to start** (🚨 page + exit 1) instead of warning; the
opt-out `ALLOW_UNSAFE_TIMING=true` (lab/testing only) restores the old warn-and-continue.

> **Rule 1 (v0.6.6 N1 — PRIMARY relinquishes first):**
> `STANDBY TAKEOVER_DELAY  ≥  PRIMARY self-fence worst case + cross-node margin`
> i.e. `TAKEOVER_DELAY ≥ EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS`  (default `60 = 30 + 30`).
>
> **Rule 2 (BACKUP after STANDBY):**
> `BACKUP TAKEOVER_DELAY  >  STANDBY TAKEOVER_DELAY + VOTE_LIVENESS_MIN_INTERVAL + propagation margin`

> **v0.6.9 (H1) — Rule 1 now also covers the STANDBY→BACKUP hop.** After a failover the *promoted
> STANDBY* is the holder, and it now runs the **same self-fence** as the PRIMARY
> (`STANDBY_SELF_FENCE=true`; worst case `max(SELF_FENCE_ISOLATION_SECS, SELF_FENCE_NOANSWER_SECS)`
> = 30s + margin). Against the BACKUP's 120s delay the invariant holds trivially
> (30 + 30 ≤ 120): an isolated promoted STANDBY relinquishes (gives back to its own unstaked
> identity, or is hard-stopped) **before** the BACKUP can take. The pre-v0.6.9 caveat that "the
> promoted standby holds unfenced" no longer applies — 3-node mode is no longer degraded after a
> failover. A self-fenced standby is additionally **locked out of re-taking** for
> `SELF_FENCE_RETAKE_COOLDOWN` (600s): its own fenced vote account looks delinquent+frozen precisely
> because it stopped voting it, so without the lockout every normal gate would pass and it would
> take the identity straight back.

Rule 1: a PRIMARY that is alive but ISOLATED keeps the staked identity until its self-fence demotes it
(worst case `max(SELF_FENCE_ISOLATION_SECS, SELF_FENCE_NOANSWER_SECS)`, default 30s, post-N2 with the
demote done before any alert). A spare must NOT take the identity until after that, or both hold staked
and a partition heal double-signs. The delinquency head-start D (the spare detecting PRIMARY delinquent)
is **bonus margin only** — never rely on it (an isolated-but-voting PRIMARY may look healthy to the
spare's delinquency check until the self-fence acts).

> ⚠️ **Tuning rule (cross-node, easy to get silently wrong).** If you raise the PRIMARY's
> `SELF_FENCE_NOANSWER_SECS` (or `SELF_FENCE_ISOLATION_SECS`) — e.g. testnet shows the local JSON-RPC
> stalls ≥30s — you **MUST** raise, on **every** spare (STANDBY *and* BACKUP), **both**
> `EXPECTED_PRIMARY_SELF_FENCE_SECS` **and** `TAKEOVER_DELAY` by the **same amount**.
> The startup warning compares only the spare's **own** knobs (`TAKEOVER_DELAY` vs
> `EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS`) — it **cannot read the PRIMARY's
> config**. So if you bump the PRIMARY's self-fence timer but leave the spare's
> `EXPECTED_PRIMARY_SELF_FENCE_SECS` stale, the warning stays **SILENT** (the spare's local arithmetic
> still "passes") while the real cross-node overlap **returns** — the PRIMARY now relinquishes later
> than the spare takes. Bump `EXPECTED` first so the warning *does* fire until `TAKEOVER_DELAY` is
> raised too. (The deploy script only auto-raises `TAKEOVER_DELAY` to its *own* `EXPECTED + margin`; it
> likewise cannot know you changed the PRIMARY.)

Rule 2: the STANDBY needs `TAKEOVER_DELAY` to confirm delinquency **plus** `VOTE_LIVENESS_MIN_INTERVAL`
for its second liveness sample; the BACKUP must not begin until the STANDBY has had that full window
plus a propagation margin. The default presets (STANDBY 60s, BACKUP 120s, MIN_INTERVAL 10s) satisfy both
rules with margin — preserve the ordering if you tune them.

**Takeover-delay anchor (v0.6.7 N3 — measured from the holder's *last observed vote*).** The spare's
`TAKEOVER_DELAY` is measured from the **later** of when delinquency was first seen and the **last time
the staked holder was observed voting** — `max(FIRST_DELINQUENT_TIME, LAST_LIVENESS_ACTIVE_TIME)`. This
matters for a PRIMARY that is **delinquent but still voting** (flagged by the RPC delinquent list or
fast slot-lag while its `lastVote` keeps advancing, so the vote-liveness fence correctly BLOCKS): such an
episode no longer **pre-consumes** the delay. When the holder finally goes silent, the **full**
`TAKEOVER_DELAY` re-elapses from that moment, so the PRIMARY's self-fence (~30s) always completes before
the spare takes — Rule 1's margin holds even in this composed case. The delay **length** is unchanged;
only its **anchor** moved. Normal failover is unaffected: when the holder is already silent before the
spare starts checking, liveness never reports "active", the anchor stays at first-delinquent, and the
timeline is identical to v0.6.6 (~70s).

---

## Expected timelines

> **Read the cross-node invariant first (v0.6.6 N1).** The spare's `TAKEOVER_DELAY` must be **≥
> `EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS` (= 60 by default)** so the PRIMARY
> *always relinquishes first*. The binding case is **not** the fast internet-loss path (PRIMARY
> unstaked ~9s) — it is an **isolated-but-still-voting** PRIMARY, which holds the staked identity until
> its self-fence demotes it at ~30s. A spare must take only **after** that, with margin.
> **Pre-N1 fast presets (`TAKEOVER_DELAY=10`/`20`) are UNSAFE and must not be used** — they would let
> the spare take before the PRIMARY self-fences (double-sign on heal). The examples below use the
> shipped-safe presets.

### STANDBY — shipped v0.6.6 (MAX_DELINQUENT_SLOTS=15, TAKEOVER_DELAY=60)

```
# PRIMARY relinquishes FIRST (whichever trigger applies):
PRIMARY t=~9s:    internet-loss path → SWITCHED TO UNSTAKED
   …or (the BINDING cross-node case)…
PRIMARY t=~30s:   isolated-but-voting → SELF-FENCE → SWITCHED TO UNSTAKED (demote before alert, N2)
# STANDBY (fast-detect 15, delay 60):
STANDBY t=~12s:   lastVote 15+ slots behind → TURBO MODE (1s checks)   [FIRST_DELINQUENT_TIME]
STANDBY t=~20s:   Window 7/10 → external confirm + vote-liveness 1st sample
STANDBY t=~72s:   TAKEOVER_DELAY (60s from first-delinquent) elapsed + liveness frozen → TOOK STAKED
# ⇒ STANDBY takes ~72s, after the PRIMARY's worst-case self-fence (~30s) plus margin — no overlap
#   observed in any live test (this is the designed ordering, not an unconditional guarantee).
```

### BACKUP — shipped v0.6.6 (TAKEOVER_DELAY=120), only if STANDBY also failed

```
BACKUP t=~12s:    sees staked delinquent → TURBO MODE
BACKUP t=~132s:   TAKEOVER_DELAY (120s) elapsed + liveness frozen (crashed STANDBY not voting) → TOOK STAKED
# ⇒ BACKUP > STANDBY (Rule 2) and > PRIMARY self-fence + margin (Rule 1).
```

### Without fast-detect (MAX_DELINQUENT_SLOTS=0, TAKEOVER_DELAY=60)

```
PRIMARY t=~9-30s: SWITCHED TO UNSTAKED (internet-loss or self-fence, as above)
STANDBY t=~60s:   RPC delinquent list (~128 slots) → first-delinquent → window starts
STANDBY t=~120s:  TAKEOVER_DELAY (60s) elapsed + Window 7/10 → TOOK STAKED
# ⇒ slower detection (no fast-detect) only LENGTHENS the spare's takeover — the cross-node margin is preserved.
```

---

## Testing

### Phase 1 — DRY RUN (safe)

Config: `DRY_RUN=true`

```bash
systemctl start solana-failover
tail -f /var/log/solana-failover.log
```

Verify: startup alert received, heartbeat every 10 min, no errors.

### Phase 2 — Simulated failure (DRY RUN)

```bash
iptables -I OUTPUT 1 ! -o lo -j DROP; sleep 40; iptables -D OUTPUT ! -o lo -j DROP
```

Expected: `[DRY RUN] Would switch to UNSTAKED`, then `Internet recovered`.

### Phase 3 — Real switch (PRIMARY only)

```bash
sed -i 's/DRY_RUN=true/DRY_RUN=false/' /opt/solana-failover/failover.env
systemctl restart solana-failover
# Test, then restore manually (path-as-argument, NOT stdin redirection):
agave-validator --ledger /root/solana/ledger set-identity /root/solana/mainnet-validator-keypair.json
agave-validator --ledger /root/solana/ledger authorized-voter add /root/solana/mainnet-validator-keypair.json
```

### Phase 4 — Full integration (PRIMARY + STANDBY)

Both `DRY_RUN=false`. On PRIMARY:

```bash
iptables -I OUTPUT 1 ! -o lo -j DROP; sleep 120; iptables -D OUTPUT ! -o lo -j DROP
```

After test, restore (see [Manual switch-back](#manual-switch-back-standby--primary-after-an-incident) for the tower-aware procedure):

```bash
# On STANDBY — give back (hand the live tower to PRIMARY for vote continuity):
scp /root/solana/ledger/tower-1_9-<STAKED_PUBKEY>.bin root@PRIMARY:/root/solana/ledger/
agave-validator --ledger /root/solana/ledger authorized-voter remove-all
agave-validator --ledger /root/solana/ledger set-identity /path/to/unstaked.json

# On PRIMARY — take back (tower now present → assert it with --require-tower):
agave-validator --ledger /root/solana/ledger set-identity --require-tower /root/solana/mainnet-validator-keypair.json
agave-validator --ledger /root/solana/ledger authorized-voter add /root/solana/mainnet-validator-keypair.json
```

---

## Emergency: Split-Brain

If both nodes claim staked identity (not expected with the vote-liveness fence, but possible in the
residual partition case — see SPLIT-BRAIN-RESIDUAL.md):

```bash
# Step 1: STANDBY → force unstaked
agave-validator --ledger /root/solana/ledger authorized-voter remove-all
agave-validator --ledger /root/solana/ledger set-identity /path/to/unstaked.json

# Step 2: PRIMARY → force staked
agave-validator --ledger /root/solana/ledger set-identity /root/solana/mainnet-validator-keypair.json
agave-validator --ledger /root/solana/ledger authorized-voter add /root/solana/mainnet-validator-keypair.json
```

---

## Manual switch-back (STANDBY → PRIMARY, after an incident)

Recovery is **operator-driven** — the scripts never auto-return the staked identity to
PRIMARY (production runs `RECOVERY_MODE=manual`). Once the incident is resolved:

> **v0.6.9 (H2) — after a masked hard-stop, unmask FIRST.** If the incident involved a wedged
> demote and the self-fence hard-stopped the validator with `systemctl stop` failing, the unit was
> **masked** (`systemctl mask --runtime`) so `Restart=always` could not resurrect it voting staked
> (the ✅ page says `HARD STOP ✅ (unit masked)` and names the command). Before restarting that
> validator:
>
> ```bash
> systemctl unmask --runtime solana     # the mask is --runtime, so a reboot also clears it
> systemctl start solana                # boots on the UNSTAKED startup identity (F2 invariant)
> ```

1. **On the node currently holding the staked identity (usually STANDBY)** — copy the
   *live* tower to PRIMARY so vote lockouts move with the identity, then drop to unstaked:

   ```bash
   scp /root/solana/ledger/tower-1_9-<STAKED_PUBKEY>.bin root@PRIMARY:/root/solana/ledger/
   agave-validator --ledger /root/solana/ledger authorized-voter remove-all
   agave-validator --ledger /root/solana/ledger set-identity /root/solana/unstaked-standby.json
   ```

2. **On PRIMARY** — bring the staked identity back. Because you just copied the tower, use
   `--require-tower` so agave refuses to vote if it is missing. This is the **one place
   `--require-tower` is correct** — you deliberately moved the tower; the automatic
   codepaths omit it because they have none:

   ```bash
   agave-validator --ledger /root/solana/ledger set-identity --require-tower /root/solana/mainnet-validator-keypair.json
   agave-validator --ledger /root/solana/ledger authorized-voter add /root/solana/mainnet-validator-keypair.json
   ```

> Why not let PRIMARY auto-recover with its OLD tower? After a long outage PRIMARY's own
> tower is stale; reusing it risks voting on slots STANDBY already voted (double-sign).
> PRIMARY therefore **deletes its staked tower** when it goes unstaked, and switch-back
> uses the *current* tower copied from the node that held the identity.

---

## Daily Operations

```bash
# Check status:
tail -20 /var/log/solana-failover.log
tail -20 /var/log/solana-failover-standby.log

# Restart after config change:
systemctl restart solana-failover
systemctl restart solana-failover-standby

# Graceful stop (sends Telegram + ntfy alert):
systemctl stop solana-failover
```

---

## Notifications

Both Telegram and ntfy.sh work simultaneously. Configure one or both.

### ntfy.sh (recommended — no signup, instant push)

ntfy.sh is a free push notification service. The deploy script auto-generates
a private channel and sends a test notification.

**How it works:**
- Script sends HTTP POST to `https://ntfy.sh/your-channel-name`
- ntfy app on your phone receives push with Priority: urgent (pierces DND)
- Same channel for PRIMARY + STANDBY + BACKUP = unified alerts

**Setup (automatic via deploy):**
1. Install ntfy app: [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy) / [iOS](https://apps.apple.com/app/ntfy/id1625396347)
2. Run deploy — it generates a channel and sends test push
3. Subscribe to the channel shown in deploy output
4. Done — alerts arrive instantly

**Manual setup (if not using deploy):**
```bash
# Add to env file:
WEBHOOK_URL="https://ntfy.sh/solana-failover-YOUR_SECRET_HERE"

# Test:
curl -X POST "https://ntfy.sh/solana-failover-YOUR_SECRET_HERE" \
    -H "Title: Test" -H "Priority: urgent" -d "Hello from validator"
```

**Use same channel on all servers** for unified alerts from PRIMARY + STANDBY + BACKUP.

### Telegram

```bash
# Add to env file:
TG_ENABLED=true
TG_BOT_TOKEN="BOTID:BOTKEY"    # from @BotFather
TG_CHAT_ID="123456789"          # from @userinfobot
```

### Delivery matrix (v0.6.4)

The monitor emits notifications through four tiers. Channels are chosen in the env
(`TG_*` for Telegram, `WEBHOOK_URL` for ntfy/webhook); each tier maps to fixed channels:

| Tier | Telegram | ntfy / webhook | ntfy priority | Used for |
|---|---|---|---|---|
| `alert()`      | 🚨 yes | yes | **urgent** | Critical switch / takeover events: SWITCHED TO UNSTAKED, TOOK STAKED, RECOVERED, GAVE BACK, and their failures. Retried via `_pending_alert` if Telegram blips. |
| `alert_warn()` | ⚠️ yes | yes | high | Action-needed warnings (list below). **New in v0.6.4: these now reach ntfy too** (were Telegram-only). |
| `alert_info()` | ℹ️ yes | no | — | Informational: startup banner, 3-tier `🔍` decision traces, manual identity change, and back-to-normal `✅` (internet recovered / delinquency cleared). |
| Heartbeat (`♥`) | no | no | — | Periodic status **log line only** (see *Heartbeat log*). |
| External watchdog | no | own URL | — | Fire-and-forget liveness ping to an alert-on-absence monitor (see *External heartbeat watchdog*). |

**Routed through `alert_warn` (Telegram **and** ntfy) as of v0.6.4** — previously Telegram-only:
local validator unreachable (PRIMARY + STANDBY), STANDBY node too far behind, TIER2 unreachable
during takeover confirmation, "delinquent but fence not clear / waiting", emergency-mode takeover
(external RPCs down), and recovery-blocked / STANDBY-holds-staked-identity.

> `alert_warn` uses ntfy **high** priority (not `urgent`), so warnings stay distinguishable from the
> critical switch/takeover alerts on your phone. `alert()` and the `_pending_alert` retry are unchanged.

---

## Heartbeat log

Every 10 minutes (configurable via `HEARTBEAT_INTERVAL`):

**PRIMARY:**
```
♥ Heartbeat: STAKED | Internet: 8.8.8.8✓ 1.1.1.1✓ 9.9.9.9✓ | Checks: 1200 | Switches: 0 | T2 calls: 0 | FP: 0 | Window: [0000000000]
```

**STANDBY:**
```
♥ Heartbeat: STANDBY | Checks: 600 | LOCAL delinq: 600 | Delinq seen: 0 | Takeovers: 0 | T2: 0 | T3: 0 | Window: [empty]
```

T2/T3 should stay at 0 in normal operation (LOCAL-first = no external calls).

---

## External heartbeat watchdog (v0.6.4 — "dead-man's switch")

The in-loop heartbeat above is a **log line only** — it cannot tell you when the monitor *itself*
is dead. If the failover process crashes (and cannot restart), the host dies, or the network drops,
**no event alert can fire**, because nothing is running to send one. "Healthy and quiet" and "the
watcher is dead" look identical. The external watchdog closes that gap: the monitor sends a
fire-and-forget HTTP ping at the **top of every loop**, and an **alert-on-absence** service pages you
when the pings stop.

**Setup:**
1. Create a check on an alert-on-absence service — e.g. [healthchecks.io](https://healthchecks.io),
   Uptime-Kuma (push monitor), [cronitor](https://cronitor.io), or an ntfy topic with an expected
   cadence. Configure it to **alert if no ping arrives within ~2× `HEARTBEAT_PING_INTERVAL`**
   (default interval 600s → alert after ~20 min of silence).
2. Put that check's ping URL in the node's env, then restart the monitor:
   ```bash
   HEARTBEAT_URL="https://hc-ping.com/<your-uuid>"   # this node only; empty = OFF
   HEARTBEAT_PING_INTERVAL=""                          # empty → defaults to HEARTBEAT_INTERVAL (600s)
   ```

**One distinct URL per node.** Give PRIMARY, STANDBY, and BACKUP each their **own** check/URL so the
absence alert tells you *which* node's monitor went silent. Do **not** reuse a single URL across nodes
(unlike the ntfy event channel, which is intentionally shared).

**Properties:**
- Off by default (empty `HEARTBEAT_URL`).
- Fires in `DRY_RUN` too, so a dry-run soak is externally monitored.
- Time-bounded (`curl -m 10`) and backgrounded — can never block or abort the failover loop.
- Keeps firing even while the local validator is unreachable, so a validator-down event is not
  mistaken for a dead monitor.
- Scope is deliberately narrow: it signals **"this monitor process is alive and looping"**, *not*
  "everything is healthy." Validator state is still reported by the Telegram/ntfy event alerts above.

---

## Prerequisites

- All nodes running agave-validator
- Each node has its own UNIQUE unstaked keypair
- Staked keypair present on ALL nodes (same file)
- Vote account keypair at `/root/solana/vote-account-keypair.json` (for auto-detect)
- `jq` installed
- Paid RPC key (Alchemy/Helius/Triton) in env files (optional, T3 works alone)
- ntfy app installed on phone (recommended)
- Telegram bot configured (optional)
