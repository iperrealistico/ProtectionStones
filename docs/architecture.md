# Architecture

## Repository

This is a standalone Maven repository nested in the plugin workspace. It is not
a module of the workspace Gradle build.

Remotes:

- `origin`: operator fork, `https://github.com/iperrealistico/ProtectionStones.git`
- `upstream`: canonical `https://github.com/espidev/ProtectionStones.git`
- `folia-reference`: audit-only
  `https://github.com/Galajus/ProtectionStones-folia.git`

The active compatibility branch is
`codex/protectionstones-folia-multiversion`.

## Main Subsystems

| Area | Primary classes | Responsibility |
| --- | --- | --- |
| Lifecycle/config | `ProtectionStones`, `PSConfig`, `PSL` | startup, reload, integrations, TOML/YAML |
| Region model | `PSRegion`, `PSStandardRegion`, `PSGroupRegion`, `PSMergedRegion` | stable public region API and WorldGuard metadata |
| Placement/events | `BlockHandler`, `ListenerClass`, `FlagHandler` | claim lifecycle and configured behavior |
| Commands | `PSCommand`, `commands/*`, `ArgAdminRemovePlayer` | command, permission, and global admin maintenance contract |
| Economy | `PSEconomy`, `PSPlayer` | Vault rent, tax, buy, and sell behavior |
| Scheduling | `scheduler/PlatformScheduler`, `TaskHandle` | Paper/Purpur/Folia execution boundary |
| WorldGuard geometry | `WGUtils`, `WGMerge`, `RegionTraverse` | lookup, overlap, merge, and traversal |
| Caches | `UUIDCache`, name index, command caches | cross-context lookup state |

## Compatibility Strategy

Paper exposes the global, region, entity, and asynchronous scheduler APIs on
both Paper-derived servers and Folia. The fork therefore uses one direct
`PlatformScheduler` implementation rather than runtime reflection or two
behaviorally divergent implementations. Purpur delegates these APIs to its
normal scheduler; Folia enforces ownership.

This is an intentional deviation from the initial two-implementation sketch.
It reduces version detection and class-loading risk while retaining one audited
boundary. Paper scheduler types are forbidden outside the scheduler package by
`BuildPolicyTest`.

The plugin continues to compile against WorldEdit 7.4.2 and WorldGuard 7.0.15
APIs, the lowest selected common API surface. Newer runtime implementations are
provided by the server lane and remain external to the plugin JAR.

Global member/owner removal enters through the global scheduler, iterates
WorldGuard managers for loaded worlds, mutates `PSRegion` domains, and saves
each changed manager once. Completion messages return through the command
sender's scheduler ownership. The operation never calls region deletion.

## Data Compatibility

The fork does not introduce a new database, region flag, or persisted region
schema. It retains:

- `config.toml`
- `blocks/*.toml`
- `messages.yml`
- existing WorldGuard region IDs and ProtectionStones flags
- owners, members, names, homes, rent, and tax metadata
- public classes and custom event names

The two new `/ps admin` subcommands add five message keys. Existing
`messages.yml` values are preserved and missing defaults are appended by the
normal message upgrade path.

Reload parses block configuration into a new map and publishes it only after
the complete snapshot is ready. Region-name indexes use concurrent maps and
copy-on-write ID lists without changing persisted data.
