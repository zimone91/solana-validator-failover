# Changelog

All notable changes are documented here. Versions follow the project's internal `v0.6.x` line;
`v0.6.9` is the first public release.

## v0.6.9 — first public release

Automatic double-sign-safe failover for Solana validators, hardened across multiple internal audit
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
- 37 test suites (parse-clean on bash 3.2+); each safety fix ships with a non-vacuous control.
