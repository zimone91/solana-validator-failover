# Notifications & Alerting — Solana Validator Failover (v0.6.9)

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
| `SWITCHED TO UNSTAKED ✅` | dropped the staked identity: internet lost / confirmed delinquency / **self-fence isolation** (reason is in the message) |
| `SWITCH TO UNSTAKED FAILED ❌` | `set-identity` to unstaked failed (throttled 10 min) |
| `SWITCH BLOCKED — keypair problem` | unstaked keypair missing/empty |
| `RECOVERED TO STAKED ✅` / `RECOVERY FAILED ❌` / `RECOVERY BLOCKED — keypair problem` | only in `RECOVERY_MODE=rpc` (auto re-take) |
| `[DRY RUN] WOULD SWITCH / RECOVER …` | dry-run equivalents |
| `PRIMARY SELF-FENCE — LOCAL RPC SILENT 🚨` | v0.6.5: LOCAL JSON-RPC silent ≥ `SELF_FENCE_NOANSWER_SECS` while staked → demote |
| `PRIMARY SELF-FENCE — VOTES NOT LANDING 🚨` | v0.6.7 (N6): own vote lagged cluster-max > threshold sustained (egress-only isolation) → demote |
| `PRIMARY SELF-FENCE — HARD STOP ✅` / `HARD STOP ✅ (unit masked)` | v0.6.8 (B1): demote `set-identity` wedged → validator hard-stopped, **confirmed DOWN** (v0.6.9 H2: re-verified after `HARD_STOP_REVERIFY_SECS`; if `systemctl stop` failed the unit was **masked `--runtime`** and the page names `systemctl unmask --runtime <unit>`) |
| `PRIMARY SELF-FENCE — HARD STOP FAILED 🚨` / `HARD STOP UNCONFIRMED 🚨` | v0.6.8 (B1): hard-stop couldn't kill / couldn't confirm — INTERVENE NOW |
| `PRIMARY SELF-FENCE WEDGED — NO HARD STOP 🚨` | v0.6.8 (B1): demote wedged and `SELF_FENCE_HARD_STOP=false` — INTERVENE NOW |
| `STAKED STARTUP IDENTITY 🚨` | F2: validator's startup `--identity` is the STAKED key (double-sign-on-restart risk) — fix the unit |
| `PRIMARY UNREACHABLE WHILE STAKED 🚨` | staked + local validator unreachable — daemon cannot self-demote; intervene |

### ⚠️ Warning (`alert_warn` → Telegram + ntfy)
- `⚠️ PRIMARY local validator unreachable! Failover monitoring paused.` *(throttled)*
- `⚠️ Recovery blocked: staked identity is ACTIVELY VOTING elsewhere (the STANDBY holds it). Manual switch-back needed.`
- `⚠️ STANDBY has staked identity. Manual switch-back needed.`
- `⚠️ TIER2_RPC == TIER3_RPC — single vantage point. …` *(v0.6.9 M8, at startup)*

### ℹ️ Info (`alert_info` → Telegram only)
- `🚀 PRIMARY v0.6.8 started [DRY_RUN|LIVE]`
- `🔍 3-tier …` decision traces (switching / false positive / reset) and `🔍 Latency …`
- `✅ PRIMARY back on STAKED (manual)` / `ℹ️ Manual identity change detected`
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
| `GAVE BACK — unstaked ✅` / `GIVE BACK FAILED ❌` | give-back (manual only by default) |
| `[DRY RUN] WOULD TAKE / GIVE BACK` | dry-run equivalents |
| `STANDBY SELF-FENCE — SWITCHED TO UNSTAKED 🚨` | v0.6.9 (H1): the **promoted holder** self-fenced (frozen slot / silent LOCAL RPC / N6 vote-lag / getHealth) and gave the identity back to its own unstaked key; re-take locked out for `SELF_FENCE_RETAKE_COOLDOWN` |
| `STANDBY SELF-FENCE — HARD STOP ✅` / `HARD STOP ✅ (unit masked)` / `HARD STOP FAILED 🚨` / `HARD STOP UNCONFIRMED 🚨` / `STANDBY SELF-FENCE WEDGED — NO HARD STOP 🚨` | v0.6.9 (H1+H2): the give-back wedged → the B1 hard-stop escalation (masked-`--runtime` + re-verified per H2; FAILED/UNCONFIRMED/WEDGED = INTERVENE NOW) |
| `GIVE BACK WEDGED — HOLDER MAY STILL BE VOTING 🚨` | v0.6.9 (H4): the give-back admin call timed out and the identity did **not** flip — escalating per `SELF_FENCE_HARD_STOP` |
| `STANDBY UNREACHABLE WHILE STAKED 🚨` | v0.6.9 (H1/H3): promoted holder + local validator unreachable (main loop, throttled; and once at monitor startup when the persisted role was STAKED) — cannot self-fence; a spare may take over; intervene |
| `STAKED IDENTITY SEEN ELSEWHERE (possible collision) 🚨` | v0.6.9 (M5): same detection-only collision page as the PRIMARY (while STAKED, 2 consecutive non-self gossip endpoints, throttled) |
| `UNSAFE CROSS-NODE TIMING — REFUSING TO START 🚨` | v0.6.9 (M9): `TAKEOVER_DELAY < EXPECTED + MARGIN` at startup → fatal (override: `ALLOW_UNSAFE_TIMING=true`, lab only) |

### ⚠️ Warning (`alert_warn` → Telegram + ntfy)
- `⚠️ STANDBY local validator unreachable! Cannot monitor or take over.` *(throttled)*
- `⚠️ STANDBY node too far behind or unhealthy! Cannot take over if needed.` *(throttled)*
- `⚠️ TIER2 (Alchemy) unreachable during takeover confirmation! Falling back to TIER3.` *(throttled)*
- `⚠️ Delinquent but fence not clear: <reason>. Waiting...` (gossip/vote-liveness fence holding)
- `⚠️ Takeover proceeding without external confirmation (T2+T3 down, emergency mode ON)`
- `⚠️ Take applied but the admin socket wedged … — verify node health.` / `⚠️ authorized-voter add timed out … voting may not start` *(v0.6.9 H4, after a wedged-but-applied take)*
- `⚠️ Give-back applied but the admin socket wedged … — verify node health.` *(v0.6.9 H4)*
- `⚠️ GIVE_BACK_MODE=auto is not implemented — treated as manual.` *(v0.6.9 M6, at startup)*
- `⚠️ TIER2_RPC == TIER3_RPC — single vantage point. …` *(v0.6.9 M8, at startup; also fail-closes the fast-path)*
- `⚠️ UNSAFE cross-node timing ACCEPTED via ALLOW_UNSAFE_TIMING=true …` *(v0.6.9 M9, lab override)*

### ℹ️ Info (`alert_info` → Telegram only)
- `🚀 STANDBY v0.6.8 started [DRY_RUN|LIVE]`
- `🔍 Takeover: <gate summary>` (the decision line just before taking over)
- `✅ STANDBY delinquency cleared`

### v0.6.8 fast-path (Option A) notes
- `⚠️ Fast-path disabled: <reason>` (`alert_warn` → Telegram + ntfy) — a required knob is missing;
  the daemon runs fail-closed on the pure timer. All other `[fast-path]` lines (armed banner,
  `POSITIVE relinquish`, stagger-floor raise) are **log-only** decision traces — the takeover
  itself still pages via `TOOK STAKED ✅`.

### Other
- `🛑 STANDBY failover stopped (signal)` → Telegram only
- 🩺 watchdog ping · ♥ heartbeat status line → log only

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

Repeating warning conditions are throttled by `ALERT_THROTTLE` (default 600s = 10 min) so they
alert once, then stay quiet until resolved: local-validator-unreachable (both roles),
switch-to-unstaked-failed (PRIMARY), Tier2-unreachable-during-confirmation (STANDBY),
node-too-far-behind (STANDBY).

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
unreachable / can't-take-over / fence-waiting / emergency-takeover / recovery-blocked) — plus the
external watchdog if the monitor itself dies. The ℹ️ decision traces stay in Telegram by design.
