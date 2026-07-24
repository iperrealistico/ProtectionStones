# Testing

## Automated

Run `clean verify` on Java 21 and Java 25:

```powershell
.\mvnw.cmd clean verify
```

Produce and reproduce the release candidate with JDK 21. JDK 25 is a separate
compile/test gate: different `javac` releases may emit byte-different Java 21
class files, so its output must not replace the JDK-21-built candidate used by
the runtime matrix.

Tests cover rent parsing, numeric permission resolution, cache concurrency,
particle ranges, command registration, non-destructive global domain removal,
metadata, Java release policy, and forbidden scheduler/implementation imports.

Compare a rebuilt upstream baseline against the candidate:

```powershell
.\scripts\compare-public-api.ps1 `
  -BaselineJar C:\path\to\upstream-protectionstones.jar `
  -CandidateJar .\target\ProtectionStones-2.10.6-pvc.1.jar
```

The API check compares public/protected classes and JVM member descriptors.

## Runtime Roots

The required isolated roots are:

```text
local-servers/purpur-1.21.10-protectionstones-smoke
local-servers/purpur-26.2-protectionstones-smoke
local-servers/folia-26.1.2-protectionstones-smoke
local-servers/purpur-1.21.10-protectionstones-upstream-migration
```

Provision the three release lanes with exact dependency and server hashes:

```powershell
.\scripts\provision-test-matrix.ps1 -AcceptEula
```

Folia 26.1.2 build 8 was the latest official Folia binary on 2026-07-24.
Resolve “latest” again before a later release.

## Runtime Sheets

Run on all three release lanes:

- C-01 startup, enable, reload, and clean stop
- C-02 physical placement, metadata, and physical break
- C-03 members, owners, flags, name, priority, parent, and merge
- C-04 home plus immediate, delayed, and cancelled teleport
- C-05 `/ps view` and tracked particle generation
- C-06 piston, explosion, liquid, fire, wind-charge, and related protections
- C-07 public API, configured actions, and custom events
- C-08 restart, persistence, remote unclaim, and fatal-log scan
- C-09 global member/owner removal, admin permission, UUID input, unchanged
  region existence, ownerless persistence, and multi-world save

Run on at least one Purpur and one Folia lane:

- I-01 Vault buy, sell, rent, and tax
- I-02 PlaceholderAPI values
- I-03 LuckPerms-derived limits
- I-04 offline-player and UUID resolution
- I-05 cleanup preview/remove and maintenance commands
- I-06 copied upstream configuration and region-data migration

All runtime invocations must assert the same candidate SHA-256 recorded in the
lane manifest.

## Mineflayer Harness

Install the locked Node dependencies in `test-harness/mineflayer`, then use:

```powershell
.\run-core-flow.ps1 ...
.\run-teleport-flow.ps1 ...
.\run-probe-flow.ps1 ...
.\run-admin-domain-flow.ps1 ...
.\run-integration-flow.ps1 ...
.\run-migration-flow.ps1 ...
```

The admin-domain runner creates regions in Overworld and Nether, denies a
non-admin, removes a cached name and literal UUID globally, leaves both regions
present with no owners, restarts the server, and verifies persisted domains.

The runtime probe invokes the real `/ps view` command and requires a non-zero
tracked particle-task count. Mineflayer's particle decoder limitation is not
treated as a server pass by itself.

The integration runner restores temporary tax and block configuration
byte-for-byte in `finally`. The migration runner creates data with unmodified
upstream 2.10.6, preserves TOML and every existing message entry, permits only
the five additive admin command messages, and checks semantic region data
through two candidate restarts.

ViaVersion and ViaBackwards in the 26.x roots are test-client transport only.
No harness targets production.
