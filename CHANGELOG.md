# Changelog

All notable changes are documented here. Versions follow the project's internal `v0.6.x` line;
`v0.6.9` is the first public release.

## Unreleased (v0.7 line)

- **Block 6.3.1 — the spare's own view: detection on the slow reliable view (finalized), a veto on the fast one
  (confirmed).** The spare's own node (`LOCAL_RPC`, the one input no `TIER2`/`TIER3` intermediary can splice)
  now testifies at every take, and every piece is veto-only: it can turn a take into a hold, never the reverse.
  Every residual and every number lives in `docs/SAFETY.md`, linked here.
  - **Explicit commitments:** every `getVoteAccounts`/`getSlot` body in both daemons names its commitment
    (detection reads `finalized`, agave's default — behavior-neutral); a census parses every body with jq.
  - **The own bank restarts the countdown:** a `lastVote` advance of the staked account in the spare's own bank
    during an episode is holder voting — a fourth takeover-anchor input; watchdog-elapsed's silence restarts
    with it (`[elapsed-own]`); reset at every episode close; the witness fast path never skips it.
  - **One bounded local veto read before the switch**, on every take path (the standby's `take_staked_identity`,
    the primary's `switch_to_staked`): one `LOCAL_RPC` batch (`curl -m 2`) after the fresh re-check and before
    the `DRY_RUN` branch. A failed read vetoes, a voting holder re-anchors, and the spare's own confirmed head
    must have advanced past a sample no older than `OWN_HEAD_H` = 16 s. The act-then-alert rule now reads:
    **no network, no alerts; one bounded local veto read allowed.**
  - **The spare's own head:** sampled before every external read of the take cycle (a structural census);
    watchdog-elapsed's `[elapsed-rate]` layer abstains below an average of 2.5 slots/s; `N_HEAD` =
    (`MARGIN_ELAPSED` − 1) × 5/2 = 22 slots. This narrows the slow-cluster residual; it does not retire it.
  - **Small calls:** Tier 1 is the node's own health verdict (`LOCAL_HEALTH_MAX_BEHIND` enters no decision); a
    failed latency reference is no longer holder-voting evidence; the holder's opt-in latency demote reads its
    payload first (not part of the cross-node invariant); `failover arm` refuses a symlinked or non-canonical
    state directory, by its spelling or its nearest existing ancestor before creating anything.
  - **The fresh re-check is the 6.3 build's, unchanged;** two changes tried during review opened take-while-voting
    paths and were reverted. Two residuals come with it, named in SAFETY: the mirror world (residual 6), the 6.3
    build's own; and the re-check's starvation (residual 7) — a `TIER2` that times out while `TIER3` is slow
    leaves the veto no fresh baseline, so a dead holder is never taken over, loudly — this block's own
    availability regression against Block 6.3, never a double-sign.
  - The mechanism, its costs and its residuals (the `RECOVERY_MODE=rpc` one included): [the spare's own view](docs/SAFETY.md#the-spares-own-view-v07-block-631);
    the holder's fence against the spare's earliest take and mint, every crossing named: [the cross-node invariant](docs/SAFETY.md#the-cross-node-invariant).
  - Tests: `test_own_view` and `test_d6_holder` (new). Every suite now runs behind a failing, logging `curl` first
    in `PATH`, so no suite reaches a real endpoint (the earlier suites made read-only calls to `127.0.0.1:8899`).

- **Block 6.3 — the watchdog-elapsed proof provider (attested time), the spare's observation surface
  as a standing property, and the holder-side hardening of five review rounds.** Every residual and
  every number lives in `docs/SAFETY.md`, linked here.
  - **The provider** (the second behind the 6.1 proof gate; `[elapsed-provider]`, byte-identical in
    both daemons; armed + spare + registered only — zero reads and zero events anywhere else): it
    registers at startup only over a pairing token that classifies ok at the one derivation site, and
    answers PROVEN only when the silence observed on the spare's monotonic clock (restarting at every
    stamped blindness, counted from the adoption of the token in force) reaches `elapsed_floor` =
    W + B + `MARGIN_ELAPSED`, one fresh same-vantage read still shows the episode baseline, and the
    payload's cluster-max is within ±`N_HEAD` of this spare's own head read right after it. A verdict
    is withdrawn — never extended — past `PROOF_MAX_AGE`, when the seam moves under it, or when the
    stored token (keyed on its full line and file identity) no longer licenses it; a symlinked token or
    token directory never proves. Unwired (6.4). Its numbers:
    [slot time](docs/SAFETY.md#shared-vantages--the-spares-observation-surface-a-standing-property-v07)
    and the head cross-check, its own cost and age, in the same section.
  - **The spare's observation surface (D0)** — [Shared vantages](docs/SAFETY.md#shared-vantages--the-spares-observation-surface-a-standing-property-v07):
    on every configuration watchdog-elapsed's silence and the vote-FROZEN observation are one
    `TIER2`/`TIER3` input; the own bank's scope, the partitioned and lagging spare, forged G2 on shared
    vantages — measured on the real loop (`test_elapsed_provider` §11), most of them flipped by 6.3.1.
  - **The spare's take path:** span starts stamped after the read that establishes them; one
    canonical-integer validator (`_canon_uint`) for every external integer; an aborted main loop exits
    1; the Tier-1 and reference reads petted; the own-bank reference read first; `TIER2` re-reads the
    holder's `lastVote` after its reference.
  - **The holder's self-fence:** non-canonical input fails toward the fence; `load_state` decides per
    value; the restore floor (`SELFFENCE_RESTORE_CONFIRM_SECS`); the differential bar and the seven
    named residuals — [Holder self-fence](docs/SAFETY.md#holder-self-fence-the-differential-bar-and-its-named-residuals-v07-block-63).
  - **The heredoc guard (27)** in `test_installer_guardrails`; the standby deploy script's env heredoc
    ran `failover arm` as a command substitution (bare backticks in a comment) — escaped.

- **Install-verification claims aligned to the mechanism (docs, comments and one runtime output
  line; no logic change).** `install.sh`'s header, `SECURITY.md` ("Verifying what you install") and the README
  install paragraph promised more than exists: a signed release tag verified with `git tag -v`
  against a maintainer key at zim.one, and fail-closed `SHA256SUMS` verification with "no
  continue-without-verification path". The facts, checked against the tags themselves: `v0.6.9`
  and `v0.6.10` carry NO signature (annotated tags, zero signature blocks) and NO `SHA256SUMS`
  (neither tag contains a manifest), so for both — including the installer's default version —
  downloads are checked by SYNTAX ONLY, and the installer's own code already says so aloud
  (`PRECHECKSUM_VERSIONS` warning); the script verifies no signature at all. The texts now say
  exactly that: v0.6.x tags are unsigned and will stay so (published tags are never rewritten);
  checksum verification is fail-closed from the first manifest-bearing release on; tag signing
  starts with v0.7, after the maintainer key is published outside GitHub. The one line every
  install prints was wrong too: "Newer releases are checksum-verified; consider installing the
  latest version" — no release is checksum-verified today, and the latest IS v0.6.10, so the
  advice led nowhere. It now reads "Checksum verification starts with the first release that
  ships a SHA256SUMS manifest (v0.7)" — true now and after v0.7 (output text only, no logic).

- **Ratification follow-ups (Block 6.2).** The shared-vantage STANDING CONDITION now reads
  word-identically at every site an operator can meet it — `failover arm` precondition P6, the
  arm's end-of-summary, the armed spare daemon's startup WARN, and `docs/SAFETY.md` — so the
  sentence seen once at the ceremony is the sentence found by `grep` in a log a month later;
  each site keeps its own MEASURED clause and fix text around it, and a suite assert
  (`test_g2_provider` (9e)) fails on a reworded copy (guarded duplication, the `_pairing_crc`
  precedent). The `N_HEAD` coupling gains its condition AT the derivation site, recorded before
  anyone is under pressure: if Block 10 measures vantages failing the head cross-check and
  takeovers starving, the response is to raise `MARGIN_ELAPSED` — which raises the elapsed floor
  with it — never to relax `N_HEAD` alone; the coupling is the property the derivation exists
  for. And `tests/run_all.sh` gains SYMMETRIC failure diagnosis: the 4.4 "diagnosis, not just
  detection" fix had landed only on the printed-FAIL-but-exit-0 branch, so a plain non-zero exit
  recorded a bare suite name while the single reusable `$_suite_out` was overwritten by the next
  suite — a one-off failure left nothing to analyse. That branch now prints the exit code, the
  `❌` lines if any, and the output tail (a suite killed mid-run by `set -e`, a syntax error or a
  crash prints no `❌` at all — its last lines carry the reason), and EVERY diagnostic line in
  both branches is tagged with the suite that produced it (`exit rc=1 [test_x.sh]`,
  `tail [test_x.sh]: …`) — an untagged line in a log of 51 suites is unattached, and a grep by
  suite name missed it and read as "the diagnostics did not fire".
- **Block 6.2 — the G2 verified-demote proof provider (§2.4 + [rev3/№2]).** The first real
  provider behind the Block-6.1 proof gate, in a new `[g2-provider]` twin region (byte-identical
  in both daemons; armed+spare+configured-gated — zero reads, zero events on every un-armed or
  unconfigured host, census-asserted). G2 inverts the proof's polarity: instead of "the holder
  looks gone", it demands a POSITIVE observation that the demoted state is live NOW — the
  holder's unstaked ContactInfo at the staked identity's exact gossip endpoint (the F-A anchor:
  `set-identity` keeps ports) observed at T1 and STILL present ≥ `G2_DELTA=60 s` later on the
  SAME two pinned vantages from distinct failure domains (`G2_VANTAGE_A`/`G2_VANTAGE_B`, default
  `TIER2_RPC`/`TIER3_RPC`). A live publisher re-signs its unstaked ContactInfo every ~7.5 s and a
  stale entry cannot survive 30 s in a remote CRDS table, so survival across the hold proves a
  live publisher holds the unstaked key on that box — which, by the vote gates, means the box
  cannot sign staked votes. DELTA = 30 s provable CRDS bound + `G2_CLOCK_BUDGET=25 s` vantage
  clock budget + 5 s purge granularity/rounding, derived at ONE census-guarded site; G2's floor carries NOTHING of W+B
  ([6.0-COND-1] per-provider floors). Implemented as a per-cycle STATE MACHINE (baseline → T1 →
  hold → T2 → proven): the main loop is never blocked for DELTA — one bounded, petted read-batch
  per cycle (`curl -m 5` class), paced, zero sleeps, memory-only state (a restart mid-incident is
  cannot-determine, never a restored anchor). Every ambiguity fails toward cannot-determine or
  not-proven, NEVER proven; an environment must not be able to forge acceptance. Each snapshot is
  ONE JSON-RPC **batch** — a single POST carrying `getSlot(confirmed)` AND `getClusterNodes` with
  fresh per-request ids — so the freshness anchor is bound INTO the response that carries the
  proof (batching verified by execution against mainnet-beta/agave 4.2.1; members matched by id,
  never by array position). The layers: **batch shape** (not a 2-element array ⇒ cannot-determine
  — the anchor is unbound); **id echo** (any member, or the following `getBlockTime`, not echoing
  the id this cycle sent ⇒ cannot-determine: a stored/replayed answer carries stored ids);
  **slot-advance floor** (`G2_SLOT_ADVANCE_FLOOR = G2_DELTA = 60` slots — the vantage's own
  confirmed head, batched into the proof-bearing response, must advance across the hold; this
  layer trusts NO clock, and a stalled cluster lands cannot-determine: availability, never a
  take); **snapshot-freshness** (`getBlockTime` of that batched slot within ±25 s of the spare's
  wall clock — the block's ONE wall-clock read, pinned in CI); **[rev3/№2] node-table advance**
  (a byte-identical `getClusterNodes` RESULT 60 s apart is a TOTALLY frozen response, i.e. a
  naive cache ⇒ cannot-determine — the ratified control is red-first in the suite);
  **cross-vantage identity** (byte-identical node tables from both "distinct" vantages = one
  source wearing two names ⇒ cannot-determine + throttled page); **endpoint match** (a watched
  key at a DIFFERENT endpoint proves a publisher elsewhere, not this box ⇒ not-proven); **vantage
  distinctness tripwire** (identical/same-host vantage URLs at startup ⇒ CRITICAL page + G2
  permanently cannot-determine for the run); and, at the ARM only, `REFUSE[P6-batch]` (a vantage
  that cannot serve the batch) and `REFUSE[P6-vantage]` (both vantage names resolving to one
  address set). Two layers state their limits explicitly rather than over-claiming: node-table
  advance catches a totally frozen response but does NOT prove the unstaked entry was re-observed
  live (mainnet tables churn constantly — anti-replay duty belongs to the batched slot), and
  cross-vantage byte-distinctness is NECESSARY-NOT-SUFFICIENT for two failure domains (a source
  varying anything per vantage passes it; the enforceable half is the arm's resolved-address
  check, and two IPs of one provider remain an operator responsibility). Mid-hold absence on any
  vantage ⇒ NOT-PROVEN +
  full reset (the flip-then-flip-back kill: the ≤ 30 s CRDS expiry sits inside the 60 s hold); a
  proven verdict older than `PROOF_MAX_AGE` is WITHDRAWN and re-proven, never extended. The
  provider registers into the gate's registry at armed-spare startup and returns the structured
  verdict (observation_id carries gen + T1/T2 mono stamps; `observed_at` = the T2 read) — the
  gate's acceptance path gets its first real exerciser; the PAIRED posture line now prints the
  MEASURED registry (`proof providers registered: …`). The gate stays UNWIRED into any take path
  (wiring is Block 6.4); what G2 cannot see — flip-back-then-vote after T2 — belongs to the
  mutation-edge recheck's staked-vote pin, and the composition is stated at the verdict-minting
  site, and the SEVERITY of a false proof is stated there too: the gate is an ADDITIONAL
  requirement in front of the staked mutation, so a false PROVEN cannot by itself cause a take —
  it can only fail to BLOCK a take the pre-existing v0.6.x logic already authorized, and a
  double-sign needs BOTH a false G2 proof AND a false-frozen vote observation. New suite
  `tests/test_g2_provider.sh` (51 suites): reds-first per detector, the ratified №2 control, the
  multilayer rule over the enumerated layer set (each layer neutered alone → the attack falls
  through to a NAMED surviving layer; ALL neutered → the forged acceptance red restored),
  boundedness/pet censuses from live event order, inertness censuses, constants census extended
  to `G2_DELTA`/`G2_CLOCK_BUDGET`/`G2_SLOT_ADVANCE_FLOOR` with injection reds, twin byte-parity.
  **Panel fix round (blockers + notes, in this same entry — the claims above describe the SHIPPED
  mechanism, not the first cut).** Two blockers were found by executing attacks against the first
  cut and are closed here. (1) The freshness anchor was a SEPARATE HTTP request from the
  proof-bearing read, so a vantage serving honest live `getSlot`/`getBlockTime` while replaying
  only `getClusterNodes` minted PROVEN; the batch + id echo + slot-advance layers above replace
  it. The earlier claim that "even a partially replayed vantage answers with the old slot's old
  time" was FALSE as shipped and has been removed everywhere it appeared. (2) The advance and
  cross-vantage detectors fingerprinted the WHOLE body while the proof is one extracted fact, so
  a frozen proof entry riding on mainnet churn — and one cache behind two names with a
  per-vantage nonce — both passed; the duty moved to the batched slot, the two layers kept their
  place with narrowed claims, and vantage distinctness gained the arm-time resolved-address
  refusal. Named residual, executed and NOT defended: an ACTIVE, PROTOCOL-AWARE intermediary that
  splits the batch, forwards `getSlot` live and answers `getClusterNodes` from storage under our
  id. Binding raises the bar from passive cache/naive replay to that; it does not clear it, and
  no unsigned snapshot protocol can. Also in this round: presence now scans ALL gossip values for
  the watched key (the old `head -1` read an elsewhere-first topology as absent — a false
  negative that also killed attempts mid-hold); `_g2_url_host` handles bracketed IPv6 (two IPv6
  vantages used to collapse to host `[` and trip the same-host tripwire with a false reason); the
  spare closes its G2 episode when it observes ITSELF staked, so an attempt can never span the
  spare's own staked tenure; and the clock-budget attribution is corrected — the ±budget compare
  bounds a vantage's CHAIN-HEAD lag, not the local system clock CRDS purge depends on, which is
  now a named residual in `docs/SAFETY.md`. The batch merged two reads into one, so the region's
  per-op pet census moved 5 → 4 per daemon (totals 42/43 → 41/42) and its worst added per-cycle
  gap fell 36 s → 24 s; the CI wall-clock pins were re-derived and are UNCHANGED at 21/22.
  **Reviewer conditions (second fix round, in this same entry).** (C1) The severity statement
  above — "a double-sign needs BOTH a false G2 proof AND a false-frozen vote observation" — is
  formally true but MEANINGLESS on the default config, where `G2_VANTAGE_A`/`G2_VANTAGE_B` derive
  from `TIER2_RPC`/`TIER3_RPC` and every vote-liveness reader iterates exactly those: one
  protocol-aware intermediary in front of a shared vantage supplies BOTH halves, so the gate's
  additivity does not hold there and the named active-intermediary residual is not bounded by the
  composition. That is now MEASURED and said out loud rather than left implied. `failover arm`
  compares each vantage against each tier (normalized URL, host, and resolved address set where a
  resolver exists), prints which vantage matched which tier BY WHICH COMPARISON plus the
  consequence and the fix, and re-states it in the end-of-summary; the distinct case prints its own
  measured "vantages are SEPARATE" line, so a clean result is never a silent pass. It is a
  DEGRADATION, never a refusal — most operators run exactly two RPCs, and refusing would leave the
  spare un-armed. The armed daemon logs a URL-level version at startup (`log_warn`, not a page: the
  condition is config, constant for the run; no DNS in the daemon — the arm owns resolution, said
  so in the text). The recommendation — a THIRD endpoint in a SEPARATE FAILURE DOMAIN, meaning a
  different operator — is in `docs/SAFETY.md`, the manual's knob table, the standby env template
  and the installer's rendered env. (C2) The constants return to the project's own CRDS research
  record: `G2_DELTA` 50 → **60 s**, `G2_CLOCK_BUDGET` 20 → **25 s**, `G2_SLOT_ADVANCE_FLOOR` 50 →
  **60** slots (coupled as before). §2.4 deployed 50/20 for ONE reason — to fit the hold inside
  the 60 s un-armed timer — and that reason died when [6.0-COND-1] made proof floors PER-PROVIDER:
  `verified-demote`'s floor is its own hold, never `TAKEOVER_DELAY`. The record's residual
  ("both clocks >25 s wrong simultaneously") is stated against 25 s, so the smaller budget was
  widening the residual it was meant to bound. Cost, named: `verified-demote`'s branch answers
  ~10 s later; the timer path is unchanged because the gate is additive. The stale comment
  claiming `PROOF_MAX_AGE=50` equals G2's DELTA "by numeric COINCIDENCE" is corrected — the
  coincidence dissolved, and no code path assumes any ordering between the two (audited). Every
  suite fixture sized for the 50 s hold was re-derived above 60 s, and the coupling controls'
  mutant numbers with them (budget 25→35 ⇒ DELTA 70, the decoupled control static at 60).
- **Block 6.1 — spare-side proof-gate skeleton + pairing-token intake at the spare arm.** Block
  6's cost model inverts Block 5's: the worst outcome is DOUBLE-SIGN (the spare taking while
  the holder is alive), so everything below fails toward NOT-taking and toward REFUSING to arm.
  New `[proof-gate]` twin block (byte-identical in both daemons; structurally inert today:
  armed-gated AND role-gated, zero events on every un-armed host — census-asserted; NOT wired
  into any take path — wiring is Block 6.4): `require_relinquish_proof` consumes STRUCTURED
  verdicts (k=v records — proven/provider/observation_id + the Block-3 freshness triple +
  `observed_at`), refuses with zero registered providers, and returns a distinct `bypassed`
  outcome only under the exact-`true` `ALLOW_UNFENCED_TAKEOVER` lever (screams at every armed
  start AND per bypassed take). Floors are PER-PROVIDER, never global: `_derive_proof_floors`
  is the ONE derivation site — `elapsed_floor = W + B + MARGIN_ELAPSED` (=100 at the shipped
  30/60) with `N_HEAD = slots(MARGIN_ELAPSED)` (=25) COUPLED mechanically (staleness tolerance
  cannot be raised without visibly raising the floor); `PROOF_MAX_AGE=50` is derived from a
  full verdict→mutation read census (the recheck's sampler worst = 2×`curl -m 10` + 2 armed
  pets + glue = 36 s; healthy path 2–4 s — convergence proven with margin) and enforced at the
  MUTATION EDGE by `_proof_age_edge_check`, which refuses absent/0/garbage AND future-dated
  (negative-age) `observed_at`. The spare arm gains P5 pairing-token intake
  (`ARM_PAIRING_TOKEN`): crc/shape re-verified with the 5.3 emission's exact mechanics (one
  `_pairing_crc`, byte-identical in three copies), refusals with MEASURED-vs-REQUIRED texts —
  `P5-token-crc`, `P5-bound` (BOTH directions: `relinquish_bound <= TAKEOVER_DELAY` from
  above, and W/B bounded into `[1, PAIRING_BOUND_MAX=3600]` — the panel's L-1 blocker: a
  crc-valid token with W near 2^63 wrapped `elapsed_floor` NEGATIVE and logged a healthy
  PAIRED; the derivation site now also asserts floor convergence, `>0`/`>=W`/`>=B`, as an
  intake-independent backstop), `P5-floor` (the reviewer's floor MINIMUM: `W+B+MARGIN >=
  TAKEOVER_DELAY` — arming must never make the spare FASTER to take than not-arming;
  watchdog-elapsed stands on time, the weakest evidence kind, so its floor must dominate the
  un-armed timer path BY CONSTRUCTION; `MARGIN_ELAPSED` is READ from the installed daemon's
  single derivation site, never re-declared; the twin backstop re-asserts `floor >=
  TAKEOVER_DELAY` against on-disk-planted tokens and refuses an uncheckable delay),
  `P5-staked-unstaked` (per-entry zero-stake verification of `PRIMARY_UNSTAKED_PUBKEY` via
  bounded RPC — a staked "unstaked" key inherits the ~48 h CRDS extended_timeout and silently
  breaks G2's expiry math; degenerate/empty `getVoteAccounts` bodies are cannot-verify and
  REFUSE), and `P5-store` (tmp+mv+verify persistence). A `fence=page-only` token pairs but
  buys NOTHING on the time path; no token / invalid token / page-only = the §2.7 LOUD
  unpaired posture: CRITICAL page at every armed start, a standing line on the heartbeat
  status surface, and end-of-summary warnings in the arm and the standby wizard. SAFETY.md
  names the stale-bound re-arm residual (a holder re-armed with larger bounds + a forgotten
  re-pair is a double-sign direction the spare cannot detect by construction; the holder's arm
  refusing to complete without printing the token is the operational protection). New suite
  `tests/test_proof_gate.sh` (50 suites): reds-first, forged-token matrix, per-signal
  mutation controls (incl. the defense-in-depth pair: one neutered floor layer does NOT reopen
  the hole, both neutered restores the red), broadened constants census
  (`local`/`declare`/`export`/`readonly`/arithmetic spellings all bite).
- **Block 5.4 — fence-rot detection + `FENCE_ROT_GRACE` escalation (§2.1-rev2.1 №2).** The
  pairing token attests the holder's fence at pairing time only; the spare cannot see
  post-pairing rot — so the ARMED holder now re-verifies its own effective fence properties
  every `FENCE_ROT_CHECK_SECS` (default 60, floor 10) in a new `[fence-rot]` twin block
  (byte-identical in both daemons; structurally inert outside the armed unit — zero systemctl,
  zero pages on every host today, event-log-asserted). Every demote-vs-page classification is
  container-VERIFIED on systemd 249 (fleet floor) AND 255 (design record
  `verify-rot-properties.md`, private tree): fence unit gone/replaced/masked/`bad-setting` and
  monitor `Restart≠no` / `OnFailure` not naming the fence are demote-class (on 249 a
  `Restart=always` monitor NEVER dispatches the fence — watchdog kills included; the masked
  shape that matters is the /etc unit file replaced by a /dev/null symlink, invisible to
  `test -e`); `WatchdogSec` config drift (read via `systemctl cat` — the show-side
  `WatchdogUSec` is runtime-only and reload-immune), `StartLimitIntervalUSec≠0`, both-units
  XOR and a not-loadable monitor unit (whose other show keys are STUBS — never classified) are
  page-class: CRITICAL page, no demote clock; a failing systemctl is cannot-verify — NOT rot,
  paged only after a 4-sweep blind streak. Demote-class drift opens an EPISODIC escalation
  window: immediate CRITICAL page naming the exact broken element + exact fix command
  (re-paged per `ALERT_THROTTLE`), graceful self-demote through the daemon's EXISTING demote
  path only after `FENCE_ROT_GRACE` (default 1800, floor max(600, `ALERT_THROTTLE`) — both
  reasons in the validation error) of persistent verified rot while verifiably STAKED
  (unreadable identity at expiry = no demote, keep paging; heal = resolution + a FRESH window
  for any re-rot). During the grace the holder is voting and paging, so the spare's
  silence-based path cannot fire against it — the window adds no double-sign exposure (the
  reasoning lives as a comment at the grace check). New suite `tests/test_fence_rot.sh`
  (49 suites): reds-first against the pre-5.4 daemons (armed+masked-fence → zero pages, zero
  reads, no clock — logged), per-property red→green, measured episodic table
  (rot→heal→re-rot → demote at 240+grace, stale-anchor control at grace−history), never-instant
  and storm and first-immediate and gate controls (all `mutate()`-loud), both pet censuses
  (live event order + the one bounded `_rot_sysread` funnel), N-is-all systemctl census. The
  census surfaced a pre-existing UNBOUNDED `systemctl show … -p ExecStart` fallback in
  `get_validator_args` (both daemons) — bounded at the reviewer's GO condition with the
  `_rot_sysread` idiom (`timeout -k 2 5`): pre-Block-5 the bare read was harmless (daemon
  hangs, Restart=always), but under the armed Type=notify unit a wedged systemctl there
  blocked startup pre-READY — TimeoutStartSec → `failed` → OnFailure → a REAL fence on a
  healthy validator, the P1-capability trap from the other side. Case (19) pins the bound
  behaviorally (red observed: the bare call hung past the deadline on both daemons); the
  allowlist census asserts the bounded spelling. Docs: SAFETY.md holder-side self-enforcement contract, README knobs paragraph,
  systemd/README item 4 marked BUILT (zero-stake verification explicitly deferred to Block 6).
  **5.4 panel fix round** (3-lens adversarial panel; every fix reds-first, executed): the
  escalation anchor is now PER-SIGNAL — four plain first-seen stamps (file classification /
  fence LoadState / monitor Restart / monitor OnFailure) under one uniform rule: a firing
  signal opens its own window, a POSITIVELY-clean read closes it, a blind read leaves it —
  fixing the panel BLOCKER where a genuine fence heal under any blind sibling read kept the
  ancient anchor and a fresh rot demoted with 0 s of the 1800 s grace (executed on both
  daemons: demote at t=3000 where 4800 is correct; fixed = full grace + one resolution;
  continuous-rot-across-blindness semantics preserved and re-measured). Expiry demote ATTEMPTS
  are throttled at the rot call site (first immediate, then once per `ALERT_THROTTLE` with a
  suppression warn per skipped sweep — the un-completable-demote adapter storm was 60
  CRITICALs/hour; the per-attempt identity re-verify is unchanged), and the standby's
  keypair-blocked `give_back_identity` branch now PAGES (`GIVE BACK BLOCKED` — parity with the
  primary's `SWITCH BLOCKED`; it was silent). intent=none pages now state that a bare fence
  file drop-in will NOT clear the escalation (re-arm + monitor restart re-captures intent).
  Suite: the panel timelines as cases (both daemons), within-group split, never-positively-
  clean hold, stale-anchor + retry-storm controls; young-uptime first-page positives for the
  page-class and cannot-verify 0-sentinels (both were unkilled mutants); case 13 inverted to a
  fail-CLOSED allowlist census (command-position `if systemctl …` injections now bite); the
  live pet census extended through a rot+expiry sweep and the source stray-set widened
  (`$(timeout … systemctl` beside the funnel); (10a) now asserts the `[DRY RUN]` adapter title
  it always claimed; `_fence_rot_check`/`_rot_capture_intent` added to the HOLD baits; the
  pre-impl vacuity census corrected to the MEASURED sets (7 at land, 4 after this round —
  recorded in the suite header). 50→67 checks; monitor skeleton R8 comment split per the
  container record (249: never runs; 255: re-dispatches per iteration — either way outside the
  one-hop contract).
- **Block 5.3 — the `failover arm` ceremony** (`failover-arm.sh`, repo root: SHIPPABLE — in
  SHA256SUMS, shellcheck, and the parse gate — but EXECUTED only at the v0.7 rollout,
  upgrade-then-arm, per the release checklist; nothing in this repository runs it). Structure:
  preconditions → probe → install → verify → token, every precondition refusing with the exact
  fix printed. Preconditions: self-v0.7 patsub-guard check on the installed daemons (the
  rev3.2 release condition self-enforced — the ceremony IS the upgrade-then-arm checkpoint);
  socat hard-required (§2.6, the SOLE armed transport — no fallback); busybox-flock `-w` probe
  (reviewer 5.2-GO: detected AT ARM and said aloud — WARN, not refuse); **unit `--identity`
  verification** (the 5.1 proc-gone residual discharged: real-arm REFUSES unless the validator
  unit's ExecStart carries the unstaked keypair; page-only proceeds with WARN; frankendancer
  states the stop-only posture and skips); the §2.3 one-arm-state announcement. The
  §2.1-rev2.1 end-to-end PROBE: a transient Type=notify pair (new `arm-probe` skeletons)
  rendered into ARM_RUNTIME_DIR proves stopped-petting → watchdog → `failed` → OnFailure
  ON THIS HOST before any armed state exists — the one READY pet that starts it IS the §2.6
  socat self-test; no marker → refuse. Install renders the monitor (role fill) + exactly ONE
  fence unit (page-only XOR real per DRY_RUN, stale sibling removed — the arm is the alignment
  mechanism), places the fence bodies (the ceremony is the only placer), **retires the legacy
  monitor before enabling the new one** (fix round 2 blocker: the wizards' pre-fence units
  `solana-failover.service` / `solana-failover-standby.service` — the full set either wizard
  writes or enables — are detected, stopped, disabled, and the retirement VERIFIED via
  `is-active`/`is-enabled` re-reads; any failure → `REFUSE[INSTALL-legacy]` with the manual
  commands printed, the new monitor NOT enabled, no token; the unit file stays on disk for the
  operator to delete. Two Restart=always monitors on one host share the env + state file and
  race set-identity — one demotes, the other re-takes inside the lockout; the fix is this
  ceremony step, deliberately NOT a daemon-side flock, which would turn the losing notify
  monitor into a never-READY start timeout → OnFailure → REAL fence on a healthy validator),
  enables the monitor (the only `systemctl enable` of a Block-5 unit — supersession of the
  legacy deploy services is an ACTION the ceremony performs, not a plan), never touches
  the validator unit; post-install
  verify re-classifies and must agree (render→verify). The §2.1 pairing token
  (`v0.7|gen=N|watchdog=…|relinquish_bound=…|fence=…|host=…|crc`) bumps a persisted generation
  counter and the arm refuses to complete without printing it. New suite
  `tests/test_arm_ceremony.sh` (48 suites): reds-first, every actuator stubbed, every root in
  mktemp (the hard boundary — no test touches /etc, /run/systemd, or a real systemd),
  refuse-gate mutation controls on every gate, arm↔fence byte-parity on the reused
  unit-discovery helpers.
  The fence's "(the arm ceremony (5.3) must verify …)" comments/marker text now read "verified
  at arm since 5.3" — daemon↔fence byte-parity twins untouched.
  **5.3 panel fix round** (3-lens adversarial panel on the arm ceremony; every fix reds-first,
  every executed attack re-run and shown dead): P1 now requires WATCHDOG CAPABILITY in each
  installed daemon (`_watchdog_active()` + ≥1 `READY=1` + ≥10 `_watchdog_pet` sites, all
  comment-stripped) beside the patsub guard — the panel armed a v0.6.10 daemon whose READY-less
  monitor would have fenced a healthy validator; P4 verifies the KEY, not the path string
  (readlink-resolve, derive the pubkey via the host's `solana-keygen`/`agave-keygen`, compare
  to the env's `UNSTAKED_PUBKEY` — a symlink-to-staked at the configured path now refuses;
  unverifiable refuses too, with the manual command printed and the documented dangerous
  override `ARM_ACCEPT_UNVERIFIED_IDENTITY=1` that WARNs loudly; multiple `--identity` flags:
  the LAST wins, said aloud); the renderer is structural (bash replace, no sed — `&`/`\`/`|`
  paths render byte-exact, the delimiter refusal gone with the sed) with per-file post-render
  content verification and a directory-at-destination refusal; probe markers are file-typed
  with stale-marker announce+clean (the panel's M-A mutation survivor, now killed by a case +
  control) and an unremovable-marker refusal; an un-removable stale fence sibling under REAL
  intent refuses (was WARN — §2.3's one-unit invariant); the generation bump is
  flock-serialized (bounded; absent-flock residual named) and verified to persist as a regular
  file holding the bumped value; the "only enable" claim is scoped to the Block-5 unit set
  everywhere it is printed or written; all five `systemd/*.skel` render sources joined
  SHA256SUMS (integrity artifacts for root-installed units); `tests/run_all.sh` dispatches via
  `"${BASH:-bash}"` (interpreter-drift class closed). Suite 56 → 85 checks, mutation controls
  M1–M10. (5-lens adversarial verification panel; folded into the Block
  5.2 commit — every fix red-first, every panel mutant re-killed, every attack scenario re-run).
  **5.3 fix round 2** (reviewer blockers, both reds observed on a tool-bearing machine —
  docker bash:5.2 with socat/flock/util-linux installed): the arm suite's scenario PATH is now
  `"$STUB_DIR:$TOOLDIR"` with NO system path appended — TOOLDIR is a per-run dir of symlinks
  to the real host binaries for the arm's non-actuator commands (N-is-all by comment-stripped
  grep), so a DELETION stub means the tool resolves NOWHERE; the old appended `/usr/bin:/bin`
  made `STUB_NOSOCAT`/`STUB_NOFLOCK` vacuous exactly where the tools exist (every real
  validator host): with socat installed, (2a) ARMED with a printed pairing token where
  `REFUSE[P2-socat]` was expected (83/85, run_all 47/48 — reproduced, then fixed, then green
  on the same machine; standing non-vacuity tripwires (B6)/(B7) — asserting the exact PATH
  string the runner used (a snapshot at the deletion cases), never a locally rebuilt copy,
  so a runner-side PATH regression turns them red too; the flock-absent case (3c)
  is now exercised unconditionally on every leg). Plus the legacy-monitor retirement above
  (suite (15a–h) + mutation control M11: retire neutered → the dual-monitor arm completes,
  observed), and the `P1-capability` refusal now prints the failing daemon's MEASURED counts
  against the REQUIRED floors instead of static shipped-daemon figures (the old "carry 7 and
  35+" disagreed with the reviewer's count of the same daemons — illustrative numbers drift,
  measurements do not). Suite 85 → 97 checks, controls M1–M11.
  **FF-B1 (false-fence blocker):** the wedged-demote paths now pet their COMPLETED timed-out
  ops — a `timeout` rc 124/137 return IS a completed bounded op (the monitor is alive and
  remediating): the primary's `switch_to_unstaked` rc-124 branches pet BEFORE entering
  `_selffence_hard_stop`, the standby's `give_back_identity` branches pet before
  `_giveback_wedged_escalate`, and the escalate's own identity re-read is petted. Panel's
  measured pet-free stacks: PRIMARY 40 s → 20 s, STANDBY 48 s → 20 s (attack_petgap2 re-run),
  both < WatchdogSec 30 with margin. The N-is-all audit over the whole class (every
  early-return/branch after a ≥ 5 s-bound op) closed 11 more sites: primary
  `tier1_check_delinquency` / `tier1_get_vote_latency` ×2 / `_check_rpc_delinquency` /
  `_check_single_rpc` ×3, standby `tier1_check_local_health` / `local_check_delinquency` /
  `tier2_check_delinquency` / `tier3_confirm_delinquency` (capture-rc-then-pet idiom), and
  converted every loop-top pet (liveness sampler, alpenglow fetch, collision/gossip/relinquish
  loops, both daemons) to post-op placement so the loops' final reads are covered on every
  exit. **FF-B2:** the tiered checks' unreachable paths pet their completed 15 s curls —
  both-externals-hanging confirm: 30 s/0 pets → max gap 15 s (re-run). **FF-B3 + HOLD-B1:**
  all 11 main-loop/HOLD `sleep` sites route through `_watchdog_sleep` (chunked ≤ 10 s + a pet
  per chunk under the armed unit; byte-identical plain sleep un-armed — asserted): ANY legal
  `CHECK_INTERVAL`/`TURBO_INTERVAL` is now armed-safe — no interval ceiling needed; the A3
  comment no longer leans on the 3–5 s defaults, and it names the primary's opt-in
  MAX_VOTE_LATENCY>0 term (2 × 10 s, per-op petted). **FF nits:** the wait loop re-sends
  EXTEND immediately BEFORE and AFTER the one-time H3 alert (the composed flap+alert 72 s
  EXTEND→EXTEND trace closes to 52/33 s < 60, re-run); armed-only throttled re-page while the
  pre-READY wait extends ("validator still in startup after Ns; protection not yet active" —
  un-armed hosts unchanged); the monitor skel's WatchdogSec comment now carries the honest
  ≈ 22 s max-gap figure (the "~10–15 s cadence, tolerates one lost datagram" claim
  contradicted the daemons' own derivation) and pins `TimeoutStartSec=90s` (= the systemd
  default) so the part-D no-EXTEND-sent bound is stated where it binds; the honest pet
  call-site count is pinned structurally in the suite: 34 per-op/end-of-cycle call sites in
  the primary, 35 in the standby (`grep -cE '^[[:space:]]*_watchdog_pet\b'` minus the
  definition line — the earlier "36 per daemon" figure counted the definition + a comment).
  **HOLD fixes:** `_consume_fence_markers` now runs FIRST in `startup_checks` — before EVERY
  fatal gate (binary/keypair/one-arm/numeric/vote-liveness), so a fenced node parks in HOLD
  instead of looping a fatal exit-1 through OnFailure → fence-breaker → restart (suite-driven,
  both daemons; the HOLD loop sanitizes CHECK_INTERVAL locally since numeric validation now
  runs later); the fence script's HOLD comments and `systemd/README.md` now state the
  IMPLEMENTED HOLD (READY=1 + continuous pets + throttled re-page — explicitly superseding
  addendum §2.2's original "no watchdog re-arm, one CRITICAL page, quiet" wording, with both
  counterfactual directions traced in README), and the daemons' HOLD comment carries the same
  supersession line; the stale-marker branch re-checks existence before paging (a marker
  cleared mid-check → silent normal startup, no lying "stale marker present" page).
  **Comment-truth:** `systemd/README.md` transport section rewritten to the implemented truth
  (socat-CHILD datagrams + `MAINPID=$$` payload claim + `NotifyAccess=all`; the old
  "main-PID datagrams"/"NotifyAccess=main" wording would produce the functionally-dead unit
  class). **Test honesty (killing the panel's four surviving mutants):** `drive_hold` stubs
  17+ monitoring/takeover entrypoints as bait and case (7) asserts ZERO fire in HOLD (M6a/M6b
  now red); a primary drive-cycle case covers the primary's first-clean-cycle fenced-demoted
  clear (M7-primary now red); end-of-cycle pet CALL-line counts (5/4) and TOTAL pet call-site
  counts (35/36 incl. definitions) are pinned structurally — a call deleted or `:`-neutered
  under its kept comment trips the pin (the M1b class now red); a full non-delay cycle with
  the №8 lever ON asserts ZERO voter adds (M11x now red); the suite's inertness grep widened
  to socat|NOTIFY_SOCKET|WATCHDOG_USEC|READY=1|WATCHDOG=1|EXTEND_TIMEOUT_USEC in code outside
  the [watchdog] block; the red-log provenance note records that the archived red predates the
  final suite revision (identical per-case outcome set re-verified). The primary's dead-but-
  parity-kept `boolf` drift branch is annotated (twin discipline over dead-code purity).
  Suite grows 44 → 60 checks; the panel's M1–M11x battery re-run post-fix: 15/15 mutants red.
- **Block 5.2 — monitor-side fence integration** (installed by nothing; structurally inert on
  every host today — every mechanism activates only under the Block-5 systemd unit, i.e. when
  PID 1 exports `NOTIFY_SOCKET`+`WATCHDOG_USEC`, or when a fence outcome marker exists; both
  asserted by the new suite incl. a zero-inertness grep-proof). **Transport (§2.6):** sd_notify
  datagrams via the research record's `socat -t0` pattern with the `MAINPID=$$` claim; the
  monitor unit skeleton moves to `NotifyAccess=all` (honesty fix: socat is a forked child — its
  credentials are not the main PID's). **Per-op pets (§5):** `WATCHDOG=1` after every bounded
  network/admin op completes plus an end-of-cycle pet; every ≥ 15 s AND every main-loop/HOLD
  inter-cycle sleep is chunked through `_watchdog_sleep` (fix round); the WatchdogSec=30
  arithmetic is derived in-code (max inter-pet gap ≈ 22 s at zero datagram loss;
  the one-lost-datagram residual across a maximal 20 s op is named, not hidden); a pet NEVER
  fires between an op's start and completion — wedge detection is the pets' absence, and a
  timeout RETURN (rc 124/137) counts as completion (fix round).
  **Startup (§2.2 B):** `READY=1` only after the first successful identity read; pre-READY the
  wait loop sends `EXTEND_TIMEOUT_USEC=60000000` (2× the iteration's worst-case bound, derived)
  each iteration WHILE the validator is positively in startup/replay — process alive AND the
  fence's own startup-evidence probe, carried into the daemons as a byte-identical twin, so
  daemon and fence share ONE evidence definition. **Markers (§2.2 C):** same-boot
  `fenced-stopped` → HOLD (CRITICAL page + re-page per `ALERT_THROTTLE`, READY+pets — the one
  documented B1 exception — zero monitoring logic; the operator's clear → exit 0 for a clean
  restart under Restart=no); stale (pre-boot) → page once + monitor normally (same-boot
  semantics at both ends); `fenced-demoted` (any age) → normal demoted monitoring, marker
  cleared on the first clean cycle; the page-only twin's marker is ignored;
  `_marker_same_boot` is a daemon↔fence byte-parity twin (suite-visible divergence).
  **Part D:** the third-branch dispatch loop analyzed at the extension site — the shared
  evidence definition closes it (stable no-evidence terminates on the SECOND dispatch, driven
  as a two-dispatch test; the flap case is rate-bounded and loud, never stops the validator,
  and deliberately gets no counter). **№8 (STANDBY only, DEFAULT-OFF, live-test-gated):**
  `PREWARM_VOTER_ADD=false` — when true, ONE bounded `authorized-voter add` per episode inside
  the takeover delay window + `remove-all` hygiene on episode reset (never while holding
  staked); off/DRY_RUN = zero admin calls (asserted); drift-announced via the new `boolf`
  direction with the live-test-gate wording. New suite
  `tests/test_monitor_fence_integration.sh` (44 checks; 60 after the fix round — mutation
  controls, structural pins, twin parity); suite
  count 46 → 47; CI wall-clock pins 19→20/20→21 (the one new site per daemon is the
  `_marker_same_boot` twin — mtime/boot-epoch comparisons are inherently wall-clock, not a
  timer); `test_demote_killafter` census 8 → 9 (the bounded startup-evidence probe).
- **Block 5.1 panel fix round** (5-lens adversarial verification panel; blockers B1/B2/B3 +
  every nit — folded into the Block 5.1 commit). **B1 (double-sign blocker):** the crash-loop
  breaker now honors a `fenced-stopped` marker only if it is from the SAME BOOT (boot epoch =
  now − uptime via `${FENCE_PROC_ROOT:-/proc}/uptime`; pre-boot mtime with a 60 s slack toward
  stale, or unreadable/garbage uptime ⇒ STALE → WARN + page + fence normally) — a stale marker
  surviving an operator's staked recovery must never leave a genuine new incident unfenced,
  unmonitored, and paged journal-only; and a FRESH refusal now also restarts the monitor (dead
  in `failed` at OnFailure dispatch — the restart is what delivers the CRITICAL page and re-arms
  monitoring). The §2.5 proc-gone demote excuse now requires an ACCEPTED (rc 0) set-identity: a
  FAILED set-identity with the process gone goes to the stop-fallback (whose `systemctl stop`
  also cancels a Restart=always resurrection), and the two `fenced-demoted` reasons are truthful
  and DISTINCT — "ladder verified by N sustained unstaked reads" vs the proc-gone outcome naming
  the ACCEPTED set-identity and the unit `--identity` invariant this script cannot verify (arm
  ceremony (5.3) obligation). **B2 (availability blocker):** every monitor restart is
  `systemctl restart --no-block` — the monitor is `Type=notify` with READY gated on its first
  identity read (minutes away mid-replay), so a job-blocking 15 s restart deterministically
  produced a false CRITICAL "UNMONITORED; intervene" on a healthy node (a killed wait is not a
  canceled job); rc now means ENQUEUE outcome only. Also: single-instance `flock -n` guard
  (loser logs + exits 0; skipped where flock is absent — macOS harness only); marker precedence
  enforced in `_write_marker` (never `fenced-demoted` while `fenced-stopped` exists; a stopped
  write supersedes the demoted sibling); per-rung-sized watchdog pets (the repoll rung's real
  ~104 s bound, stop-path pets) made REAL by the fence unit skeleton's new `NotifyAccess=all` +
  derived `TimeoutStartSec=300` (term-by-term arithmetic in the skel; pets = belt, budget =
  suspenders, failure direction stated honestly — a cut fence is a silent half-fence, not
  "louder"); word-anchored startup token ("restarting" is NOT startup evidence); the
  third-branch fence↔monitor loop named honestly in a comment (loud, nothing stopped; breaker
  is 5.2 monitor-side); frankendancer stop-only posture documented (header +
  `systemd/README.md` — v0.7 limitation, reviewer-packet item). **B3 (test honesty):**
  `tests/test_fence_script.sh` grows 21 → 41 checks — B1 stale/fresh/unreadable-uptime cases,
  B2 enqueue semantics (with a slow-READY systemctl model), and a killer for every panel
  mutation that had survived: unreadable-re-poll-with-live-process abort, stop-UNCONFIRMED
  loudest-page path, delayed re-verify vs a Restart=always resurrection (per-call `proc.seq`
  pgrep model), wedged-BARRIER remove-all not excused by proc-gone, `UNSTAKED_KEYPAIR` guard,
  shipped-default re-poll (5, no env override) + floor clamp 0→1, twin/flock lock, marker
  precedence, and truthful marker reasons. The SIGTERM/SIGKILL kill invocations remain
  structurally unobservable (bash-builtin `kill`; ESRCH pid 2147483647 is the single
  containment — named in the suite header as the recorded coverage hole). `install.sh` joined
  the CI shellcheck list and `run_all.sh`'s parse gate (pre-existing gap the panel found: it
  was checksummed but never linted/parsed).

- **Block 5.1 — the fence script PROPER** (`systemd/failover-fence.sh` promoted from the
  skeleton; every `# BLOCK5-PROPER:` seam filled, structure and failure directions kept). The
  §2.2 identity verdict grows its three real branches: (a) staked/unknown → the §2.5 ladder —
  `authorized-voter remove-all` → `set-identity <unstaked>` → `remove-all` AGAIN (the
  late-voter-add barrier) → SUSTAINED identity re-poll (`FENCE_REPOLL_SECS`, provisional 5 —
  an EMPIRICAL floor Block 10 sets by measurement, [rev3/№5]) → `fenced-demoted`;
  (b) already unstaked → marker + INFO page, zero admin mutations; (c) unreadable + unit
  active + startup-phase evidence → restart monitor, NO stop (the reboot-brick fix);
  unreadable without evidence → stop. Every admin call bounded (`timeout -k 5`, the daemons'
  H4/B1 idiom; wedge rc 124/137 → stop-fallback). Stop-fallback ports the H2
  stop → mask --runtime → SIGTERM/SIGKILL → verify + delayed re-verify discipline; an
  unverifiable stop still writes `fenced-stopped` and exits 1 — **claim MORE fencing than
  proven, never less** (the monitor's HOLD path treats the marker as authoritative).
  `VALIDATOR_UNIT` comes from the validator's cgroup (v2 `0::` line, v1 `systemd:` fallback;
  configured env wins; no unit determinable → no guessed stop, marker + exit 1) — kills the
  hard-coded `solana.service`. Crash-loop breaker: a pre-existing `fenced-stopped` marker →
  page + exit 0, zero actuator calls (`fenced-demoted` allows the idempotent re-run). Markers
  live as files in `FENCE_MARKER_DIR` (default `/var/lib/solana-failover`), ISO timestamp +
  reason, atomic tmp+mv; the monitor consumes them in slice 5.2. NO network anywhere in the
  fence (pages are journal lines — a fence that waits on Telegram can hang mid-demote). Plus
  the §2.3 twin `systemd/failover-fence-page-only.sh` (structural DRY_RUN: marker + CRITICAL
  journal line, zero mutation tokens outside comments — grep-assertable). **Ship-surface
  promotion, deliberate:** both scripts enter `SHA256SUMS`, the CI shellcheck list, and
  `run_all.sh`'s parse gate; the `.service.skel` units stay skeletons — **still nothing
  installs anything anywhere**; execution begins only at the v0.7 rollout (`failover arm`,
  upgrade-then-arm). New suite `tests/test_fence_script.sh` (46 suites): drives the real
  script as a subprocess behind a fully mocked PATH (scriptable `agave-validator`/`systemctl`/
  `pgrep`/`timeout` stubs, ordered event log; no real systemctl can run), covering the exact
  ladder order (with a swap-mutation control), the stale-write re-poll abort, all three
  verdict branches, both breaker sides, unit detection (env/v2/v1/neither), and the page-only
  twin's inertness.

- **Block 5 skeleton — systemd unit skeletons + the ONE-arm-state refusal (№1)**. `systemd/` now
  carries the v0.7 fence topology as repo-only `.skel` files: the monitor under the native
  watchdog (`Type=notify`, `WatchdogSec=30`, `NotifyAccess=main` with socat main-PID pets as the
  sole armed transport §2.6, and the load-bearing R8 pair `Restart=no` +
  `StartLimitIntervalSec=0` so the FIRST missed pet reaches terminal `failed` and dispatches
  `OnFailure=`), the REAL fence unit (§2.5 stale-write barrier ladder mapped verbatim; §2.2
  third identity branch; the two outcome markers `fenced-stopped`/`fenced-demoted`), the
  PAGE-ONLY fence unit (§2.3 structural DRY_RUN — arm-state IS which of the two fence units is
  installed), and the fence script skeleton (ladder structure + failure directions real now,
  every branch labeled toward stop/page; mechanism behind `# BLOCK5-PROPER:` seams that page +
  fail — executing it can never stop, mask, kill, or demote anything). **NOTHING INSTALLS
  THESE**: no code path writes `/etc/systemd/system` or runs `systemctl` for them; they are
  outside `SHA256SUMS` and every CI ship glob (the `.sh.skel` is shellcheck-LINTED only).
  Installation is the future `failover arm` ceremony, gated on the Block-5 entry blocker (all
  four nodes confirmed on v0.6.10+). Both daemons gain the §2.3 [rev3/№1] startup check
  (byte-identical `_fence_unit_state` + `_enforce_one_arm_state`): `DRY_RUN=true` + REAL fence
  unit installed → **refuse to start** + CRITICAL page naming both alignment paths (re-run
  `failover arm` to install the page-only fence, or set `DRY_RUN=false` if arming was intended);
  `DRY_RUN=false` + page-only → WARN (v0.6.x behavior, the §2.3 third row — acceptable);
  classification is pure `test -e` on the two canonical unit paths (BOTH present = `real`, fail
  toward the refusal; no systemctl on the startup path), and `none` — no fence unit exists,
  every host today — keeps the check **structurally inert**. No new env knobs. New suite
  `tests/test_one_arm_state.sh` (45 suites).

- **Alpenglow feature-gate tripwire** (both daemons, pre-Block-4 №9): agave 4.2.1 ships the entire
  votor/BLS machinery dormant, runtime-gated on the on-chain `alpenglow` feature — on activation
  `set-identity` demands a vote-history file by default (a direct hit on the deliberate
  no-tower-transfer design) and the whole lastVote observation model needs re-derivation. The
  daemons now probe the feature-gate account (`getAccountInfo` on the agave v4.2.1 feature id,
  TIER2→TIER3, read-only) every `ALPENGLOW_GATE_CHECK_HOURS` (default 6, 0 = off,
  drift-announced; first check immediate) and **page the moment the gate shows pending/active** —
  `pending` at WARN (epoch-boundary slack), `active` on the CRITICAL channel (set-identity then
  fails by default without a vote-history file: the promote path may be inert — the
  UNKNOWN-IDENTITY class and channel) — with the instruction to re-run the 4.2 audit (Blocks 5–6
  constants freeze until it passes). The last known state persists in the state file; "unknown"
  (both externals unusable) never overwrites it, logs at WARN, retries on a **900 s floor**
  instead of waiting out the full cadence, and **pages after 4 consecutive failures** (repeating
  per `ALERT_THROTTLE`) — a tripwire whose failure mode is silence would be a dead gate that
  looks alive. The companion gate `alpenglow_fast_leader_handover` is deliberately NOT watched —
  source-verified (one usage, `replay_stage.rs:1611`, subordinate to the main migration status;
  gates neither set-identity nor observation). Page-only — the probe sits at the top of the main
  loop, never inside a takeover/recovery/verdict path.

- **Unstaked-key uniqueness enforced** (STANDBY, pre-Block-4 №3): the relinquish-proof fence (G2)
  and the Option-A fast path both read "a live publisher holds this unstaked key on box X" as
  "box X cannot sign staked votes" — sound only while each unstaked key belongs to ONE host.
  README always required a unique unstaked keypair per node; startup now refuses (same fatal class
  as the staked==unstaked refusal) when the node's own `UNSTAKED_PUBKEY` appears in
  `PRIMARY_UNSTAKED_PUBKEY` (membership over the space-separated list).

- **CI drift-counter pins** (pre-Block-4 №10): the `facts` job now pins the per-daemon counts of
  `date +%s` (wall-clock) and `${var//…}` (patsub) sites the same way it pins the suite count —
  growth = a new wall-clock/patsub site = review-stop (addendum §3b.4); a legitimate change
  updates the pin in the same diff.

- **Act-then-alert (A8) + fresh-proof re-check** (both daemons): the pre-take 🔍 alert is deleted —
  a network call between the verdict and the mutation (the tier summary is not lost: it travels
  verbatim inside the reason of the TOOK STAKED ✅ / WOULD TAKE / TAKEOVER FAILED alert) — and the
  alert now strictly follows the action. Accepted tradeoff, not a free win: the first page about a
  take now follows the mutation, so a process death in the fraction of a second between them leaves
  the take only in the local log (unsent); accepted because the alternative held ~10 s of blocking
  network before a safety-critical mutation on a ~20 s-stale proof, and a dead monitor is covered
  by the dead-man's switch. Immediately before `set-identity`, a **fresh-proof
  re-check** (one fresh sample compared against the episode's pinned baseline — sound because the
  frozen path never re-bases the pin, so the pair interval is pin→now) must re-confirm FROZEN:
  VOTING or cannot-determine **aborts** the take, and **zero network calls** sat between the
  re-check and `set-identity` (amended by Block 6.3.1 — the rule now reads: no network, no alerts;
  one bounded local veto read allowed — the own-view veto). An abort is a withdrawn verdict, not a failed take: **no cooldown is
  set**, no episode state is dropped — the re-check leaves exactly the state the normal fence paths
  would, and pacing comes from the normal re-anchor/re-pin (on the PRIMARY a VOTING abort is paced
  by the observed-span floor + recovery ladder — its recovery anchor never read the liveness
  re-anchor, same as the in-gate design). Abort pages throttle per `ALERT_THROTTLE` (first page
  immediate — a flipping vantage would otherwise page every ~20 s indefinitely); the per-event log
  lines are never throttled. DRY_RUN mirrors the live decision (an aborted take reports the abort,
  never "WOULD TAKE"). Extends the demote path's "safety action FIRST" rule (N2) to the take path.

- **Observed life restarts the observed span**: `_liveness_obs_since` now re-pins at every VOTING
  verdict, so the observation-span floor's claim is self-contained at any config (measured:
  `VOTE_LIVENESS_MIN_SPAN=100` with one observed vote, take moved t0+120 → t0+160; inert at the
  shipped defaults — the N3 re-anchor's 60s exceeds the 40s floor).

- **Docs honesty**: README / SAFETY / SPLIT-BRAIN-RESIDUAL now name the availability-side outcome
  explicitly — with blind or flapping externals the takeover holds **indefinitely** (a measured
  outcome, not a theoretical one) and the operator is paged (`TAKEOVER_STARVATION_ALERT_SECS`);
  "fails safe" there means "does not act, loudly".

- **Blindness counts as life**: any interval in which no external provider yields an observation
  restarts the takeover countdown in full — the 60 s window can no longer collapse to ~15 s across
  an external-RPC outage. A new `VOTE_LIVENESS_MIN_SPAN` floor (default 40 s, 0 = off) additionally
  requires the frozen verdict to rest on the **episode's** actually-observed span (since the
  episode's first successful observation, or the end of the last blind cycle) — a measure that
  converges under provider-flip storms; no-op on the normal path and after any blindness. (The
  first cut measured the span from the re-basable pair pin and was measured non-convergent for
  flip periods strictly between `VOTE_LIVENESS_MIN_INTERVAL` and the floor (10–40 s exclusive;
  flip 20 s / 35 s: no take in 3600 s, while 10 s and 60 s converged) — it never shipped.)

- **Takeover starvation page** (STANDBY): a delinquency episode held
  `TAKEOVER_STARVATION_ALERT_SECS` (default 300, 0 = off) with no takeover now pages, repeating per
  `ALERT_THROTTLE`, with per-episode hold diagnostics (blind cycles / provider flips / span-floor
  holds) and a resolution notice when the episode closes. Page-only — changes no verdict, triggers
  no action — and anchored to `FIRST_DELINQUENT_TIME` by design (the takeover anchor is exactly
  what starvation moves; an alarm anchored to it would starve with the takeover).

- **Upgrade note (PRIMARY only):** envs generated by installers ≤ v0.6.10 carry
  `VOTE_LIVENESS_EPSILON=2`, which overrides the new default of 0 on the primary's rpc-recovery
  fence until the wizard is re-run (in-place daemon upgrades don't touch the env). The STANDBY —
  the double-sign-critical side — never had the knob written and inherits 0 automatically.

- **Safety timers are monotonic** (`/proc/uptime`); the state file gains a `BOOT_ID` line and
  `*_MONO` twins for every persisted safety stamp. **Rollback is safe by construction:** the legacy
  keys keep wall-clock values (derived at each save), so a daemon ≤ v0.6.10 reading a v0.7-format
  file computes correct elapsed times — including the post-self-fence re-take lockout — with no
  operator steps. Upgrading forward needs nothing either: on an old-format file, lockouts and
  cooldowns re-hold in full (fail toward held).

## v0.6.10 — hotfix: alert delivery broken on bash 5.2 hosts (Ubuntu 24.04 / Debian 12)

**One-line fix per script, zero logic changes.** bash 5.2 enables `patsub_replacement` by default,
which makes `&` (and `\`) special in the replacement side of `${var//pat/repl}`. On bash 5.2 hosts
two alert surfaces were affected:

- **Telegram — broken.** `_html_escape` emitted `<lt;`/`>gt;` instead of `&lt;`/`&gt;`; Telegram
  rejects the malformed HTML, so CRITICAL pages (demote/takeover/self-fence/hard-stop) silently
  failed to send and the pending-alert retry could never succeed.
- **Custom `WEBHOOK_BODY` templates — mangled.** A `&` in a substituted value became the literal
  placeholder text and `\\` collapsed to `\`, corrupting the payload (possibly into invalid JSON).

**Not affected:** ntfy.sh push (HTTP headers + raw body via `_header_sanitize`) and the default
JSON webhook (built with `jq -nc --arg`). Failover logic, timers, fences, and the installers'
generated config (`printf '%q'`) are entirely untouched.

The fix — `shopt -u patsub_replacement` at the top of all four scripts — restores the bash-3.2
substitution semantics this codebase is written against, and is a no-op on bash ≤ 5.1 (which is why
the bug never surfaced on the live-test stack). Found by running the full suite under both
interpreters (macOS bash 3.2 **and** Ubuntu 24.04 bash 5.2); both now pass 36/36.

## v0.6.9 — first public release

Automatic staked-identity failover for Solana validators — the holder steps down before a spare
steps up, and ambiguity resolves toward nobody voting. Hardened across multiple internal audit
rounds and validated with live failover tests on a testnet stack (isolation, egress-only partition,
promoted-standby self-fence, holder restart).

**Safety**
- Cross-node timing invariant: holder self-fences (~30s) before the spare takes (60s), with an
  authoritative vote-liveness fence. Unsafe hand-edited timing refuses to start.
- Role-aware timing floors for STANDBY vs BACKUP (a BACKUP must also outwait the STANDBY's takeover
  becoming externally visible).
- Promoted-STANDBY self-fence with a re-take lockout; wedged-`set-identity` escalation to a verified
  hard stop; persisted self-fence baseline with evidence-gated restore across monitor restarts.
- Egress-only ("votes not landing") self-fence; frozen-slot and dead-RPC self-fence; sliding-window
  delinquency detection; identity-collision detector (page-only).

**Installer & UX**
- Interactive `deploy-failover.sh` / `deploy-failover-standby.sh` with Simple / Advanced modes,
  safe-by-default presets, and a DRY_RUN-first flow.

**Notifications**
- Telegram + ntfy.sh push + external dead-man's-switch watchdog.

**Testing**
- 36 test suites (parse-clean on bash 3.2+); each safety fix ships with a non-vacuous control.
