# Fork Changelog

## 2.10.6-pvc.1 - Unreleased

Base: upstream ProtectionStones `2.10.6` at
`89be4aeab1f00422ad060e797660e56f32e1aaf0`.

### Compatibility

- Compile the common artifact to Java 21 bytecode against Paper API 1.21.10.
- Add `folia-supported: true`.
- Centralize global, region, entity, and asynchronous tasks in
  `PlatformScheduler`.
- Use asynchronous teleport and entity-owned delayed teleport countdowns.
- Move block changes to region ownership and WorldGuard-wide work to the global
  scheduler.
- Track and cancel economy, teleport, particle, cleanup, and scheduler tasks on
  reload or disable as applicable.
- Cap the purple `/ps view` dust marker at the shared Paper API maximum so the
  same visual command executes on both 1.21.10 and 26.2.

### Concurrency

- Replace cross-region UUID, cooldown, teleport, and name caches with
  concurrent collections.
- Publish block configuration and help/recipe data as complete snapshots.
- Serialize reload and reject concurrent cleanup runs.
- Keep the rented-region collection safe across region and global contexts.

### Build

- Add Maven Wrapper 3.9.11, Java 21 release enforcement, JUnit 5, deterministic
  output settings, non-minimized shading, and bStats relocation.
- Add Java 21 and Java 25 CI verification.
- Add source policy, cache concurrency, and cross-version particle-range tests.

### Verification

- Pass the complete physical core, restart, teleport, environment, API/event,
  configured-action, and region-view sheets on all three runnable lanes.
- Pass Vault, PlaceholderAPI, LuckPerms, offline UUID, and cleanup integrations
  on representative Purpur 1.21.10 and Folia 26.2 lanes.
- Load a real upstream 2.10.6 configuration and WorldGuard region dataset
  through two candidate restarts without changing upstream TOML/YAML files or
  losing region metadata.

### Compatibility Status

No release is final until every lane in
`docs/compatibility-matrix.md` is marked `PASS` with the same JAR checksum.
Exact Folia 1.21.10 remains unavailable and therefore blocks release.
