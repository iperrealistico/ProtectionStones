# Testing

## Automated

Run on Java 21 and Java 25:

```powershell
.\mvnw.cmd clean verify
```

Tests cover rent-period parsing, numeric permission resolution, UUID cache
concurrency, the shared particle-size range, metadata requirements, Java
release policy, and forbidden scheduler/implementation imports.

Compare a rebuilt upstream baseline against the candidate:

```powershell
.\scripts\compare-public-api.ps1 `
  -BaselineJar C:\path\to\upstream-protectionstones.jar `
  -CandidateJar .\target\ProtectionStones-2.10.6-pvc.1.jar
```

The API check compares public/protected classes and JVM member descriptors, so
it detects binary API removals without treating non-binary implementation
modifiers such as `volatile` as breaks.

## Runtime Roots

The isolated roots are:

```text
local-servers/purpur-1.21.10-protectionstones-smoke
local-servers/purpur-26.2-protectionstones-smoke
local-servers/folia-1.21.10-protectionstones-smoke
local-servers/folia-26.2-protectionstones-smoke
local-servers/purpur-1.21.10-protectionstones-upstream-migration
```

Each root must contain `server.jar`, `plugins/`, `eula.txt`, a lane manifest,
startup/shutdown logs, and no production data.

## Core Sheet

Run and record on all four lanes:

- C-01 clean startup and plugin enable
- C-02 obtain and place a protection block
- C-03 verify bounds, owner, type, home, and default flags
- C-04 add/remove member and owner
- C-05 edit and restore flags
- C-06 hide and unhide
- C-07 break and remote/local unclaim
- C-08 set home, immediate/delayed/cancelled teleport
- C-09 view particles
- C-10 priority, parent, and merge
- C-11 piston, explosion, liquid, fire, and wind-charge behavior
- C-12 `/ps reload`
- C-13 restart and persistence
- C-14 clean stop with no task warning
- C-15 log scan for thread, scheduler, dependency, and exception failures

## Integration Sheet

Run on at least one Purpur and one Folia lane:

- I-01 Vault economy buy/sell/rent/tax
- I-02 PlaceholderAPI values
- I-03 LuckPerms-derived limits
- I-04 offline-player and UUID resolution
- I-05 cleanup preview/remove and maintenance commands
- I-06 configured create/remove actions
- I-07 public API and custom-event listener
- I-08 copied upstream configuration and region-data restart

All lanes must use a byte-for-byte identical final JAR. Record `Get-FileHash
-Algorithm SHA256` before each startup.

I-01 through I-07 pass on Purpur 1.21.10 and Folia 26.2. I-08 passes in the
dedicated Purpur 1.21.10 migration root after an upstream-create phase and two
candidate verification restarts.

## Automated Player Harness

The current local harness uses Mineflayer `4.34.0` with two offline-mode
players. It verifies physical acquisition/placement, exact region metadata,
members, owners, flags, name, priority, home, hide/unhide, parent, merge,
reload, real restart, persistence, remote unclaim, and physical break. Separate
runners verify delayed/movement-cancelled teleport, the runtime probe sheet,
optional integrations, and upstream-data migration.

For `26.2` only, the isolated test roots use ViaVersion and ViaBackwards
`5.11.0` to translate the pinned `1.21.10` test client. These are test transport
dependencies and are neither bundled with nor required by ProtectionStones.

Mineflayer cannot reliably parse the `1.21.10` particle packet emitted by
`/ps view`. The Java 21 runtime probe therefore invokes the real command as the
player and requires a non-zero ProtectionStones tracked particle-task count in
the server log. All three runnable lanes report 9,390 tasks, closing C-09
without treating client decoder failure as server success.

The integration runner uses a local-only Vault economy and a Java 21 probe. It
tests exact balance transitions for sale, rent, and tax, active placeholders,
LuckPerms claim denial, offline owner add/remove, and asynchronous cleanup. It
restores `config.toml` and `block1.toml` byte-for-byte in `finally`.

The migration runner creates data with upstream commit
`89be4aeab1f00422ad060e797660e56f32e1aaf0`, swaps in the candidate, and
verifies the same data twice. It requires unchanged hashes for all upstream
ProtectionStones TOML/YAML files and semantic persistence of WorldGuard region
metadata.
