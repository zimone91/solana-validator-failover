# Changelog

All notable changes are documented here. Versions follow the project's internal `v0.6.x` line;
`v0.6.9` is the first public release.

## Unreleased (v0.7 line)

- **Safety timers are monotonic** (`/proc/uptime`); the state file gains a `BOOT_ID` line and
  persisted safety stamps are now monotonic values. **Rollback note:** a daemon ≤ v0.6.10 reading a
  v0.7-format state file would misread the small monotonic stamps as long-expired wall times —
  including the post-self-fence re-take lockout. **If you roll back, delete
  `/opt/solana-failover/state*` first.** Upgrading forward needs nothing: old files are detected
  and lockouts re-hold in full (fail toward held).

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
