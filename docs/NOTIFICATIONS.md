# Notifications & Alerting — Solana Validator Failover (v0.7 line, Block 6.3.1)

Operator reference for every notification the failover scripts emit, the channel each one
uses, and how to set them up. Applies to all roles (PRIMARY, STANDBY, BACKUP). All messages are
prefixed with `[NODE_NAME]`, so give every node a distinct `NODE_NAME`.

---

## Delivery tiers

There are four delivery mechanisms. The first three are message alerts; the fourth is an
external liveness ping.

| Tier | Function | Channels | ntfy priority | Telegram retry if down? |
|------|----------|----------|---------------|--------------------------|
| 🚨 **Critical** | `alert()` | log + Telegram + ntfy/webhook | `urgent` | **Yes** (`_pending_alert`, re-sent on next good cycle) |
| ⚠️ **Warning** | `alert_warn()` | log + Telegram + ntfy/webhook | `high` | No (best-effort) |
| ℹ️ **Info** | `alert_info()` | log + Telegram **only** | — | No (best-effort) |
| 🩺 **Watchdog** | `heartbeat_ping()` | external URL only (liveness ping, no body) | — | n/a |

Also: `🛑` shutdown → Telegram only; `♥` heartbeat status → **log file only** (not a notification).

### Channel matrix — what arrives where
- **ntfy / phone push** (pierces Do-Not-Disturb): 🚨 Critical + ⚠️ Warning. **ℹ️ Info does NOT push.**
- **Telegram**: 🚨 + ⚠️ + ℹ️ + 🛑 (everything).
- **External watchdog**: only "the monitor process is alive."
- **Log file**: everything, including ♥ heartbeat and the 🔍 decision traces.

> Design note: only action-needed events (🚨/⚠️) reach the phone. Informational traces
> (🔍 tiered-RPC decisions, startup, manual-change, "recovered/cleared") are Telegram-only on
> purpose — they're useful context, not pages. Use Telegram if you want the full trace.
> Only 🚨 Critical alerts are re-queued when Telegram is temporarily down; ⚠️/ℹ️ are best-effort,
> which is another reason ⚠️ also goes to ntfy.

---

## PRIMARY — events

### 🚨 Critical (`alert` → Telegram + ntfy)
| Status | Trigger |
|--------|---------|
| `SWITCHED TO UNSTAKED ✅` | dropped the staked identity: internet lost / confirmed delinquency / **self-fence isolation** / a **fence-rot graceful demote** (the reason is in the message). The fence-rot reason says "the spare takes over via the verified-demote proof": in this release the spare takes on its timer path (v0.6.x semantics), with or without G2 — the verified-demote proof conditions a take only from the release that wires the gate (Block 6.4) |
| `SWITCH TO UNSTAKED FAILED ❌` | `set-identity` to unstaked failed (throttled 10 min) |
| `SWITCH BLOCKED — keypair problem` | unstaked keypair missing/empty |
| `RECOVERED TO STAKED ✅` / `RECOVERY FAILED ❌` / `RECOVERY BLOCKED — keypair problem` | only in `RECOVERY_MODE=rpc` (auto re-take) |
| `[DRY RUN] WOULD SWITCH TO UNSTAKED` / `[DRY RUN] WOULD RECOVER TO STAKED` | `DRY_RUN=true`: the switch to unstaked, or the `RECOVERY_MODE=rpc` re-take, that a live daemon would have made — nothing changed |
| `PRIMARY SELF-FENCE — LOCAL RPC SILENT 🚨` | v0.6.5: LOCAL JSON-RPC silent ≥ `SELF_FENCE_NOANSWER_SECS` while staked → demote |
| `PRIMARY SELF-FENCE — VOTES NOT LANDING 🚨` | v0.6.7 (N6): own vote lagged cluster-max > threshold sustained (egress-only isolation) → demote |
| `PRIMARY SELF-FENCE — HARD STOP ✅` / `PRIMARY SELF-FENCE — HARD STOP ✅ (unit masked)` | v0.6.8 (B1): demote `set-identity` wedged → validator hard-stopped, **confirmed DOWN** (v0.6.9 H2: re-verified after `HARD_STOP_REVERIFY_SECS`; if `systemctl stop` failed the unit was **masked `--runtime`** and the page names `systemctl unmask --runtime <unit>`) |
| `PRIMARY SELF-FENCE — HARD STOP FAILED 🚨` / `PRIMARY SELF-FENCE — HARD STOP UNCONFIRMED 🚨` | v0.6.8 (B1): hard-stop couldn't kill / couldn't confirm — INTERVENE NOW |
| `PRIMARY SELF-FENCE WEDGED — NO HARD STOP 🚨` | v0.6.8 (B1): demote wedged and `SELF_FENCE_HARD_STOP=false` — INTERVENE NOW |
| `PRIMARY UNREACHABLE WHILE STAKED 🚨` | staked + local validator unreachable — daemon cannot self-demote; intervene |
| `STAKED IDENTITY SEEN ELSEWHERE (possible collision) 🚨` | v0.6.9 (M5): while STAKED, gossip shows the staked pubkey at a non-self endpoint on 2 consecutive checks — detection only, no automatic action (throttled) |

### ⚠️ Warning (`alert_warn` → Telegram + ntfy)
- `⚠️ PRIMARY local validator unreachable! Failover monitoring paused.` *(throttled)*
- `⚠️ Recovery blocked: staked identity is ACTIVELY VOTING elsewhere (the STANDBY holds it). Manual switch-back needed.` *(`RECOVERY_MODE=rpc` only; since v0.7 Block 6.3.1 not sent while this node's own bank sees the STANDBY voting — the recovery pass ends there, before the fence — so after an ordinary failover an rpc-mode PRIMARY sends no page and the STANDBY's `TOOK STAKED ✅` is the signal; sent when this node's own view misses the advance)*
- `⚠️ STANDBY has staked identity. Manual switch-back needed.`
- `⚠️ TIER2_RPC == TIER3_RPC — single vantage point. The tiered confirmations are no longer independent; configure two distinct RPC providers.` *(v0.6.9 M8, at startup)*
- `⚠️ Take VETOED by this spare's own view: …` / `⚠️ Take VETOED by this spare's own view (it could not testify): …` *(v0.7 Block 6.3.1 — the `RECOVERY_MODE=rpc` re-take withdrawn by the own-view veto; throttled)*
- The final re-check's `⚠️ Take ABORTED at the final re-check: …` pages *(the `RECOVERY_MODE=rpc` re-take — see "Both daemons" below)*

### ℹ️ Info (`alert_info` → Telegram only)
- `🚀 PRIMARY v0.6.9 started [DRY_RUN]` / `🚀 PRIMARY v0.6.9 started [LIVE]` (the daemons' own version label)
- `🔍 3-tier: …` decision traces (switching / reset), `🔍 False positive …` and `🔍 Latency: LOCAL …`
- `✅ PRIMARY back on STAKED (manual): …` / `ℹ️ Manual identity change detected: …`
- `✅ PRIMARY internet recovered after N fail(s)`

### Other
- `🛑 Failover monitor stopped (signal received)` → Telegram only
- 🩺 watchdog ping (see below) · ♥ heartbeat status line → log only

---

## STANDBY / BACKUP — events

### 🚨 Critical (`alert` → Telegram + ntfy)
| Status | Trigger |
|--------|---------|
| `TOOK STAKED ✅` | takeover succeeded (role-agnostic label; `[NODE_NAME]` identifies the node, incl. BACKUP) |
| `TAKEOVER FAILED ❌` / `TAKEOVER BLOCKED` | `set-identity` to staked failed / keypair missing |
| `GAVE BACK — unstaked ✅` / `GIVE BACK FAILED ❌` | sent when this node gives the identity back ITSELF: a promoted holder's self-fence, or its fence-rot graceful demote (whose reason says "the spare takes over via the verified-demote proof" — in this release a spare takes on its timer path, with or without G2). Never a manual give-back: `GIVE_BACK_MODE` is manual-only, and the daemon holds after a takeover |
| `GIVE BACK BLOCKED — keypair problem` | give-back refused: the unstaked keypair is missing or empty |
| `[DRY RUN] WOULD TAKE STAKED` / `[DRY RUN] WOULD GIVE BACK` | `DRY_RUN=true`: the take, or the give-back (a self-fence or a fence-rot demote), that a live daemon would have made — nothing changed |
| `STANDBY SELF-FENCE — SWITCHED TO UNSTAKED 🚨` | v0.6.9 (H1): the **promoted holder** self-fenced (frozen slot / silent LOCAL RPC / N6 vote-lag / getHealth) and gave the identity back to its own unstaked key; re-take locked out for `SELF_FENCE_RETAKE_COOLDOWN` |
| `STANDBY SELF-FENCE — HARD STOP ✅` / `STANDBY SELF-FENCE — HARD STOP ✅ (unit masked)` / `STANDBY SELF-FENCE — HARD STOP FAILED 🚨` / `STANDBY SELF-FENCE — HARD STOP UNCONFIRMED 🚨` / `STANDBY SELF-FENCE WEDGED — NO HARD STOP 🚨` | v0.6.9 (H1+H2): the give-back wedged → the B1 hard-stop escalation (masked-`--runtime` + re-verified per H2; FAILED/UNCONFIRMED/WEDGED = INTERVENE NOW) |
| `GIVE BACK WEDGED — HOLDER MAY STILL BE VOTING 🚨` | v0.6.9 (H4): the give-back admin call timed out and the identity did **not** flip — escalating per `SELF_FENCE_HARD_STOP` |
| `STANDBY UNREACHABLE WHILE STAKED 🚨` | v0.6.9 (H1/H3): promoted holder + local validator unreachable (main loop, throttled; and once at monitor startup when the persisted role was STAKED) — cannot self-fence; a spare may take over; intervene |
| `STAKED IDENTITY SEEN ELSEWHERE (possible collision) 🚨` | v0.6.9 (M5): same detection-only collision page as the PRIMARY (while STAKED, 2 consecutive non-self gossip endpoints, throttled) |
| `UNSAFE CROSS-NODE TIMING — REFUSING TO START 🚨` | v0.6.9 (M9): at startup, `TAKEOVER_DELAY` below this spare's floor → fatal (override: `ALLOW_UNSAFE_TIMING=true`, lab only). A STANDBY's floor is `EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS`; a BACKUP's is max(`EXPECTED_PRIMARY_SELF_FENCE_SECS + SELF_FENCE_MARGIN_SECS`, 120 s, `STANDBY_TAKEOVER_DELAY + VOTE_LIVENESS_MIN_INTERVAL + SELF_FENCE_MARGIN_SECS`), and a BACKUP without a positive `STANDBY_TAKEOVER_DELAY` refuses too |
| `G2 VANTAGES NOT DISTINCT 🚨` | v0.7 (Block 6.2): an **armed** spare with `PRIMARY_UNSTAKED_PUBKEY` set whose two G2 vantages are not distinct — fewer than two configured (vantage A defaults to `TIER2_RPC`, so an empty `TIER2_RPC` leaves one), the same URL twice, or one host — pages at every daemon start; verified-demote answers cannot-determine for the whole run. The page's "(fail toward NOT-TAKING)" is the gate's behavior once it is wired: in this release no G2 answer conditions any take, so this page means that verified-demote cannot prove here from the release that wires the gate (a paired spare keeps watchdog-elapsed for that release). Fix: point `G2_VANTAGE_A`/`G2_VANTAGE_B` (or `TIER2_RPC`/`TIER3_RPC`) at two bank-bearing RPC providers in distinct failure domains |
| `ARMED SPARE NOT ATTESTED 🚨` | v0.7 (Block 6.1, §2.7): an **armed** spare at every daemon start (unthrottled) whose holder is not attested — no pairing token stored, a `fence=page-only` token, or an invalid one (the page names which). **This release has no relinquish-proof gate:** no provider's verdict conditions any take, armed or not; the spare takes on v0.6.x semantics, which the 6.3 re-check and the own-view veto can only hold. Fix: arm the holder first and pair this spare with the token it prints — from the release that wires the gate, an unpaired or invalidly paired spare's silence-based take is disabled, and an unpaired spare with no other provider configured (no `PRIMARY_UNSTAKED_PUBKEY`, or G2 disabled by `G2 VANTAGES NOT DISTINCT 🚨`) takes nothing at all. A `fence=page-only` token: the holder was armed with `DRY_RUN` not `false` — arm its REAL fence (`DRY_RUN=false` on the holder, then `failover arm` there) and pair with the new token. An INVALID pairing whose floor is shorter than `TAKEOVER_DELAY` (the delay raised after pairing): re-pairing is refused at intake (the arm's `P5-floor`) until the holder is re-armed with bounds whose floor covers `TAKEOVER_DELAY`, or the spare's `TAKEOVER_DELAY` is lowered into the range the arm prints |
| `PROOF GATE BYPASS ARMED 🚨` | v0.7 (Block 6.1): an **armed** spare with `ALLOW_UNFENCED_TAKEOVER=true` — at every daemon start (unthrottled). The page says every take will bypass the relinquish-proof gate; in this release there is no gate to bypass, and the lever does what it did in v0.6.x: with `VOTE_LIVENESS_VERIFY=false` it lets the daemon start and the take run without the vote-liveness fence (with vote-liveness on, it changes no take). From the release that wires the gate, every take bypasses it |
| `PROOF GATE BYPASSED 🚨` | the per-take half of the same lever, sent from `require_relinquish_proof` — which this release calls nowhere, so **it is not sent in this release**; listed for the release that wires the gate |

The PRIMARY daemon carries the same proof-gate and G2 code (a byte-identical shared block) but never sends these
pages: its role adapter is not a spare.

### ⚠️ Warning (`alert_warn` → Telegram + ntfy)
- `⚠️ STANDBY local validator unreachable! Cannot monitor or take over.` *(throttled)*
- `⚠️ STANDBY node too far behind or unhealthy! Cannot take over if needed.` *(throttled)*
- `⚠️ TIER2 (Alchemy) unreachable during takeover confirmation! Falling back to TIER3.` *(throttled)*
- `⚠️ Delinquent but fence not clear: …. Waiting...` (the vote-liveness fence holding; the gossip check is advisory and never sets the reason). With both TIER2 and TIER3 unreachable the confirmation holds and logs `[CONFIRM] ⚠️ BOTH T2 and T3 unreachable — cannot confirm, holding` — a log line, not a page.
- `⚠️ Take applied but the admin socket wedged (timeout rc 124/137) during set-identity — verify node health.` / `⚠️ authorized-voter add timed out after the take — voting may not start; run 'agave-validator --ledger … authorized-voter add <staked keypair>' manually.` *(v0.6.9 H4, after a wedged-but-applied take)*
- `⚠️ Give-back applied but the admin socket wedged (…) — verify node health.` *(v0.6.9 H4)*
- `⚠️ GIVE_BACK_MODE=auto is not implemented — treated as manual.` *(v0.6.9 M6, at startup)*
- `⚠️ TIER2_RPC == TIER3_RPC — single vantage point. Configure two distinct RPC providers.` *(v0.6.9 M8, at startup; also fail-closes the fast-path)*
- `⚠️ UNSAFE failover timing […]: TAKEOVER_DELAY=…s < …s (…). Double-sign risk on heal — raise TAKEOVER_DELAY.` *(v0.6.9 M9, at startup, just before `UNSAFE CROSS-NODE TIMING — REFUSING TO START 🚨`; the brackets hold the role, STANDBY or BACKUP, and the parentheses the floor's terms)*
- `⚠️ UNSAFE failover timing [BACKUP]: …` *(the same, for a BACKUP without a positive `STANDBY_TAKEOVER_DELAY`: "BACKUP requires STANDBY_TAKEOVER_DELAY …")*
- `⚠️ UNSAFE cross-node timing ACCEPTED via ALLOW_UNSAFE_TIMING=true […]: TAKEOVER_DELAY=…s < …s. Lab/testing only.` *(v0.6.9 M9, lab override — the daemon starts instead of refusing; the brackets hold the role)*
- `⚠️ Take VETOED by this spare's own view: …` / `⚠️ Take VETOED by this spare's own view (it could not testify): …` *(v0.7 Block 6.3.1 — the take withdrawn at its last step: the spare's own node showed the holder voting, could not answer its bounded read, or is not advancing; no action taken, the countdown restarts; throttled per `ALERT_THROTTLE`. "no own-head sample within the last 16 s" on every take while a `TIER2` fails slowly — times out, or answers an error late — and `TIER3` is slow is the own view's residual 7, not the spare's node: see `docs/SAFETY.md`)*
- `⚠️ TAKEOVER STARVATION: holder delinquent …s and the takeover is still held. …` *(v0.7 Block 3 — the holder has been delinquent for `TAKEOVER_STARVATION_ALERT_SECS` (300 s) and the takeover is still held; the page counts the episode's blind cycles (a BLIND own-view veto is one), provider flips and span-floor holds; page-only; throttled per `ALERT_THROTTLE`)*
- The final re-check's `⚠️ Take ABORTED at the final re-check: …` pages *(see "Both daemons" below)*
- The G2 (verified-demote) environment-suspicion pages — an **armed** spare with a registered G2 provider, while a delinquency episode runs; each makes verified-demote hold cannot-determine; one shared throttle (first page immediate, repeats per `ALERT_THROTTLE`):
  - `⚠️ G2 vantage A answers with cluster time …s off this spare's clock (budget ±…s) — …` / `⚠️ G2 vantage B answers with cluster time …` — the vantage's cluster time is outside `G2_CLOCK_BUDGET`
  - `⚠️ G2 vantage A advanced only … slots in …s (floor …) — …` / `⚠️ G2 vantage B advanced only …` — the confirmed head advanced less than `G2_SLOT_ADVANCE_FLOOR` between T1 and T2
  - `⚠️ G2 vantage A served a byte-identical getClusterNodes payload …s apart — …` / `⚠️ G2 vantage B served a byte-identical getClusterNodes payload …` — a cache in front of the RPC
  - `⚠️ G2 vantages A and B served BYTE-IDENTICAL getClusterNodes payloads — they are likely one provider/cache behind two names (no independent corroboration); verified-demote holds cannot-determine. Use two genuinely distinct providers.`

### ℹ️ Info (`alert_info` → Telegram only)
- `🚀 STANDBY v0.6.9 started [DRY_RUN]` / `🚀 STANDBY v0.6.9 started [LIVE]` (the daemons' own version label)
- `✅ STANDBY delinquency cleared (window mostly clear)`
- `✅ Takeover starvation over — episode closed (…)`

### v0.6.8 fast-path (Option A) notes
- `⚠️ Fast-path disabled: …. Set STANDBY_TAKEOVER_DELAY = the STANDBY's TAKEOVER_DELAY on every spare.` (`alert_warn` → Telegram + ntfy) — a required knob is missing;
  the daemon runs fail-closed on the pure timer. All other `[fast-path]` lines (armed banner,
  `POSITIVE relinquish`, stagger-floor raise) are **log-only** decision traces — the takeover
  itself still pages via `TOOK STAKED ✅`.

### Other
- `🛑 STANDBY failover stopped (signal)` → Telegram only
- 🩺 watchdog ping · ♥ heartbeat status line → log only

---

## Both daemons — events

Sent by the PRIMARY and by the STANDBY/BACKUP daemon alike. The fence pages need the **armed** unit
(`failover arm`); a host that was never armed does not send them.

### 🚨 Critical (`alert` → Telegram + ntfy)
| Status | Trigger |
|--------|---------|
| `🚨 PROTECTION OFFLINE` | UNKNOWN IDENTITY: the validator's identity is neither this node's unstaked key nor the staked key — the daemon's protection is inert (the STANDBY: no takeover, no self-fence; the PRIMARY: no self-fence, no recovery); paged on entry, re-paged per `ALERT_THROTTLE` while it lasts (ℹ️ `✅ Identity classified again after …` when it clears) |
| `🚨 ALPENGLOW ACTIVE — RE-AUDIT REQUIRED` | the Alpenglow feature-gate probe (every `ALPENGLOW_GATE_CHECK_HOURS`, 6 h; 0 = off) saw the gate turn ACTIVE — `set-identity` then needs a vote-history file by default, so the promote path can start failing; re-run the 4.2 audit (once per transition) |
| `ONE ARM-STATE VIOLATION — REFUSING TO START 🚨` | v0.7 (Block 5): `DRY_RUN=true` with the REAL fence unit installed — the fence could stop a live validator the operator believes inert; the daemon refuses to start until the arm-states align (re-run `failover arm` for the page-only fence, or `DRY_RUN=false`) |
| `FENCED (stopped) — MONITOR IN HOLD 🚨` | v0.7 (Block 5.2): the fence stopped this validator this boot (`fenced-stopped` marker in `FENCE_MARKER_DIR`) — the monitor runs no monitoring logic, pages on entry and re-pages per `ALERT_THROTTLE` until the operator clears the marker (ℹ️ `✅ fenced-stopped marker cleared — …`; restart the monitor) |
| `FENCE ROT — ARMED HOLDER 🚨` | v0.7 (Block 5.4): on a host armed with the real fence (or armed with no fence unit left at all), the armed fence sweep (every `FENCE_ROT_CHECK_SECS`, 60 s) verified rot that kills the fence — the fence unit's file gone, masked or mis-set, the monitor's `Restart` not `no`, or its `OnFailure` not naming the fence; paged immediately, re-paged per `ALERT_THROTTLE`; a staked node self-demotes gracefully once the rot has lasted `FENCE_ROT_GRACE` (1800 s) — `SWITCHED TO UNSTAKED ✅` on a PRIMARY, `GAVE BACK — unstaked ✅` on a promoted STANDBY — and in this release a spare then takes on its timer path (ℹ️ `✅ fence rot resolved after …` when fixed) |
| `STAKED STARTUP IDENTITY 🚨` | F2: the validator's startup `--identity` is the STAKED key (double-sign-on-restart risk) — fix the unit; checked by both daemons at startup |
| `FENCE CONFIG DRIFT (armed) 🚨` | v0.7 (Block 5.4): the sweep verified drift that does not kill the fence now — e.g. the monitor's `WatchdogSec` config changed or absent, its `StartLimitIntervalUSec` ≠ 0, both fence unit files present, the monitor unit not loadable, or on a page-only arm a change to the page-only fence; the page names each finding and its fix — no demote clock; throttled (ℹ️ `✅ fence config drift cleared — …`) |

### ⚠️ Warning (`alert_warn` → Telegram + ntfy)
- The final re-check just before the take (with `VOTE_LIVENESS_VERIFY` on) — the STANDBY/BACKUP take, and the PRIMARY's `RECOVERY_MODE=rpc` re-take — withdraws it; no action taken; one shared throttle (first page immediate, repeats per `ALERT_THROTTLE`):
  - `⚠️ Take ABORTED at the final re-check: externals gave no usable sample (cannot determine). No action taken; the countdown re-anchored.`
  - `⚠️ Take ABORTED at the final re-check: the holder VOTED (+… slots) between the verdict and the action. …` — the take must re-qualify from this observation
  - `⚠️ Take ABORTED at the final re-check: inconsistent external view (lastVote went backwards). No action taken.`
  - `⚠️ Take ABORTED at the final re-check: the answering RPC vantage flipped (…→…); the frozen reading is not same-vantage comparable. No action taken.`
  - `⚠️ Take ABORTED at the final re-check: the external view is stale (cluster reference frozen since the pin). No action taken.`
- `🚨 ALPENGLOW FEATURE GATE is now pending (was …). …` — the probe saw the gate turn pending (there is epoch-boundary slack before activation); re-run the 4.2 audit
- `⚠️ ALPENGLOW TRIPWIRE BLIND: … consecutive feature-gate probe failures — …` — 4 failed probes in a row (retried every 900 s), then per `ALERT_THROTTLE`
- `⚠️ FENCE-ROT SWEEP BLIND: … consecutive sweeps could not verify the fence properties (systemctl failing/timing out). …` — armed; 4 blind sweeps in a row, then per `ALERT_THROTTLE`; not rot, no demote clock
- `⚠️ stale fenced-stopped marker from a previous boot under … — clearing it is safe; monitoring normally` — at startup, once
- `⚠️ validator still in startup after …s — monitor pre-READY: failover protection NOT yet active …` — armed; the monitor has waited `ALERT_THROTTLE` for the validator at startup, then per `ALERT_THROTTLE`

### ℹ️ Info (`alert_info` → Telegram only)
- `✅ Identity classified again after …` (the end of `🚨 PROTECTION OFFLINE`)
- `✅ fenced-stopped marker cleared — …` / `ℹ️ fence outcome: fenced-demoted — …`
- `✅ fence rot resolved after …` / `ℹ️ fence-rot grace expired but this node is already unstaked — …` / `✅ fence config drift cleared — …`

The fence scripts' own `PAGE[…]` journal lines (`failover-fence.sh`, `failover-fence-page-only.sh`) are not
daemon notifications and are not listed here.

---

## 🩺 External watchdog (dead-man's switch)

The one signal nothing else can give you: **is the failover monitor itself alive?** If the
monitor process crashes (and can't restart), the host dies, or the network drops, the message
alerts above can't fire — you'd get silence. The watchdog closes that gap.

- `heartbeat_ping()` runs at the **top of the main loop**, before identity is read and before any
  `continue` — so it keeps pinging even while the loop is paused on "local validator unreachable."
  It signals *"the monitor is looping,"* not *"everything is healthy"* (the message alerts cover health).
- Fire-and-forget and safe: `curl -fsS -m 10 "$HEARTBEAT_URL" &` (backgrounded, time-bounded,
  never blocks or aborts the loop). It fires in DRY_RUN too, and is a **no-op when `HEARTBEAT_URL`
  is empty**.
- Cadence: `HEARTBEAT_PING_INTERVAL` seconds (empty or non-numeric → falls back to
  `HEARTBEAT_INTERVAL`, default 600s).

**Operator setup (required for this to do anything):** point `HEARTBEAT_URL` at an external
**alert-on-absence** monitor and configure that service to page if no ping arrives within
~2× the ping interval (e.g. expect every 10 min, alert after 20–30 min). Suitable services:
healthchecks.io, Uptime-Kuma (push monitor), cronitor, or an ntfy topic with an expected cadence.
**Give each node its own `HEARTBEAT_URL`** so you know which node's monitor went dark. Tighten
both intervals if you want faster dead-monitor detection.

---

## ♥ Heartbeat log line (not a notification)

Every `HEARTBEAT_INTERVAL` (default 600s) the script writes a status line to the log only
(role/identity, internet ping summary, counters: checks/switches/T2/false-positives, window state).
Use it with `tail -f` or log shipping; it is intentionally **not** sent to Telegram/ntfy.

---

## Throttling

Repeating conditions are throttled by `ALERT_THROTTLE` (default 600s = 10 min): the first page
is immediate, repeats wait the throttle. The rows above say where it applies — among them
local-validator-unreachable (both roles), switch-to-unstaked-failed (PRIMARY),
Tier2-unreachable-during-confirmation and node-too-far-behind (STANDBY), the re-check aborts, the
own-view vetoes, the starvation page, the G2 environment pages, and the fence and Alpenglow re-pages.
The every-start pages (`ARMED SPARE NOT ATTESTED 🚨`, `PROOF GATE BYPASS ARMED 🚨`,
`G2 VANTAGES NOT DISTINCT 🚨`) are deliberately not throttled across restarts.

---

## Configuration reference

```bash
# --- Telegram ---
TG_ENABLED=true
TG_BOT_TOKEN="BOTID:BOTKEY"     # from @BotFather
TG_CHAT_ID="123456789"          # from @userinfobot

# --- ntfy / webhook (phone push; pierces DND) ---
WEBHOOK_URL="https://ntfy.sh/your-private-topic"   # ntfy auto-detected by URL
WEBHOOK_BODY=""                 # leave empty for ntfy; custom JSON template for Slack/Discord
                                # placeholders: {reason} {identity} {status}

# --- External watchdog (dead-man's switch) — off by default ---
HEARTBEAT_URL=""                # per-node alert-on-absence ping URL (healthchecks.io / Uptime-Kuma / ntfy / cronitor)
HEARTBEAT_PING_INTERVAL=""      # ping cadence in seconds; empty → HEARTBEAT_INTERVAL (600)

# --- Cadence / throttle ---
HEARTBEAT_INTERVAL=600          # log heartbeat + default watchdog cadence
ALERT_THROTTLE=600              # min seconds between repeats of the same warning
```

ntfy priority is set automatically: `urgent` for 🚨 Critical, `high` for ⚠️ Warning. For
Slack/Discord, set `WEBHOOK_BODY` to your JSON template (the `{reason}/{identity}/{status}`
placeholders are substituted).

---

## Recommended setup

Run all three channels for defense in depth:
1. **Telegram** — full stream incl. ℹ️ traces (good for a team channel / history).
2. **ntfy** (same topic on all nodes) — phone push for everything actionable (🚨 + ⚠️), pierces DND.
3. **External watchdog** — a **distinct** `HEARTBEAT_URL` per node on an alert-on-absence service,
   so a dead monitor / dead host is never silent.

**What reaches your phone (ntfy):** every action-needed event (🚨 switches/takeovers, ⚠️
unreachable / can't-take-over / fence-waiting / take aborted or vetoed / recovery-blocked) — plus the
external watchdog if the monitor itself dies. The ℹ️ decision traces stay in Telegram by design.
