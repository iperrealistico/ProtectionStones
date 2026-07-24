# ProtectionStones PVC Fork

This repository maintains a compatibility-focused fork of
[espidev/ProtectionStones](https://github.com/espidev/ProtectionStones).
It preserves the upstream command, configuration, data, API, event, and
integration contracts while centralizing Paper/Purpur and Folia scheduling.

The current fork line is `2.10.6-pvc.1`, based on upstream commit
`89be4aeab1f00422ad060e797660e56f32e1aaf0`.

## Runtime Contract

The release target is one Java 21 bytecode JAR for:

- Purpur 1.21.10 on Java 21
- Purpur 26.2 on Java 25
- the latest official Folia release on Java 25

At the 2026-07-24 release gate, latest official Folia means 26.1.2 build 8.
Future Folia releases require a fresh matrix pass before support is claimed.
WorldEdit and WorldGuard are required and are not bundled. Vault,
PlaceholderAPI, and LuckPerms remain optional. See the
[compatibility matrix](docs/compatibility-matrix.md) for exact builds and
checksums.

## Installation

1. Install the WorldEdit and WorldGuard builds specified for the server lane.
2. Put the verified `ProtectionStones-2.10.6-pvc.1.jar` in `plugins/`.
3. Start the server and configure `plugins/ProtectionStones/config.toml` and
   `plugins/ProtectionStones/blocks/*.toml`.

Existing upstream `2.10.6` configuration and WorldGuard region data are kept in
their original formats. A local migration test preserves config, block,
messages, owners, members, flags, priority, home, and sale state through two
candidate restarts. The fork adds five configurable admin-command messages to
`messages.yml` without changing existing entries. Always back up server data
before changing server or dependency versions.

## Global Admin Domain Removal

The following commands require `protectionstones.admin`:

```text
/ps admin removemember <playername|uuid>
/ps admin removeowner <playername|uuid>
```

They remove the target UUID from the corresponding WorldGuard domain in every
ProtectionStones region across all loaded worlds, save each changed region
manager, and never delete a region. Owner removal may intentionally leave a
region ownerless. Names must already be present in ProtectionStones' UUID cache,
which is populated from players known to the server; a literal UUID can always
be supplied.

## Build

Use JDK 21 for the canonical release artifact:

```powershell
.\mvnw.cmd clean verify
```

The main artifact is
`target/ProtectionStones-2.10.6-pvc.1.jar`. Automated tests also enforce the
scheduler boundary and Java 21 release setting. JDK 25 is an additional
compile/test gate, but its compiler output is not substituted for the
JDK-21-built release JAR.

## Maintenance

- [Architecture](docs/architecture.md)
- [Folia threading model](docs/folia-threading-model.md)
- [Feature inventory](docs/feature-inventory.md)
- [Admin domain removal](docs/admin-domain-removal.md)
- [Testing](docs/testing.md)
- [Upstream synchronization](docs/upstream-sync.md)
- [Release checklist](docs/release-checklist.md)

Workspace agents must begin with the workspace-level
`.ai-control/START-HERE.local.md`; fork documentation does not duplicate that
control plane.

Upstream user documentation remains available through the
[ProtectionStones wiki](https://github.com/espidev/ProtectionStones/wiki).
This GPLv3 fork preserves the upstream license and attribution.
