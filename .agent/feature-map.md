# Feature Map

## Codex multi-account quota refresh

- Product entry: open the CodexBar menu-bar item, select the Codex tab, then choose Refresh.
- Live OAuth probe: `codexbar usage --provider codex --all-accounts --source oauth --format json --pretty`.
- Persisted account snapshots: `~/Library/Application Support/CodexBar/codex-account-snapshots.json`.
- Weekly reset admission: `Sources/CodexBar/Providers/Codex/UsageStore+CodexWeeklyResetConfirmation.swift`.
- Reset evidence policy: `Sources/CodexBar/Providers/Codex/CodexWeeklyResetConfirmation.swift`.
- Source-transition regression: `Tests/CodexBarTests/CodexWeeklyResetSourceTransitionTests.swift`.
