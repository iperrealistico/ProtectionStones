# Fork Changelog

## 2.10.6-pvc.1 - 2026-07-24

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
- Validate the same Java 21 artifact on Purpur 1.21.10, Purpur 26.2, and the
  latest official Folia available at release time (26.1.2 build 8).

### Administration

- Add admin-only `/ps admin removemember <playername|uuid>` to remove one UUID
  from every ProtectionStones member domain across loaded worlds.
- Add admin-only `/ps admin removeowner <playername|uuid>` with the equivalent
  owner-domain behavior.
- Preserve every affected region, including regions left with no owners, and
  persist each changed WorldGuard manager.
- Add configurable progress, completion, no-match, save-failure, and failure
  messages.

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
  configured-action, region-view, and global admin-domain sheets on all three
  required lanes.
- Pass Vault, PlaceholderAPI, LuckPerms, offline UUID, and cleanup integrations
  on representative Purpur 1.21.10 and latest-Folia lanes.
- Load a real upstream 2.10.6 configuration and WorldGuard region dataset
  through two candidate restarts without changing TOML files, existing message
  entries, or region metadata. Only the five new command-message keys are
  added.

### Compatibility Status

All required lanes in `docs/compatibility-matrix.md` passed with JAR SHA-256
`F9DF17E6545880A32B23B4A7CD19264603A3A7B0E1FFEF1C2087AE318C36FBFE`.
