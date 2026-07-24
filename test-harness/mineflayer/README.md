# Mineflayer Core Harness

This harness drives two offline-mode players through the repeatable
ProtectionStones core flow. It is local-only test tooling and never targets a
production server.

## Requirements

- Node.js 22 or newer
- pnpm compatible with `pnpm-lock.yaml`
- A provisioned isolated lane under the workspace `local-servers/` directory
- A lane manifest containing `ProtectionStones-2.10.6-pvc.1.jar`

Install exactly the locked dependencies:

```powershell
pnpm install --frozen-lockfile
```

Run one lane from this directory:

```powershell
.\run-core-flow.ps1 `
  -Lane purpur-1.21.10-protectionstones-smoke `
  -JavaExe C:\path\to\java.exe `
  -Port 25581 `
  -BaseX 1000 `
  -ExpectedCandidateSha256 4E002C5A8A42C955803C7532C2EF4D4F524655D3806523997E9083A065E06E50
```

The runner performs a create phase, stops the server, starts a verify phase,
checks persisted data, tests remote unclaim and physical break, stops cleanly,
and scans both server logs for fatal compatibility patterns.

Delayed and movement-cancelled teleports use a separate runner:

```powershell
.\run-teleport-flow.ps1 `
  -Lane purpur-1.21.10-protectionstones-smoke `
  -JavaExe C:\path\to\java.exe `
  -Port 25581 `
  -BaseX 1500 `
  -ExpectedCandidateSha256 4E002C5A8A42C955803C7532C2EF4D4F524655D3806523997E9083A065E06E50
```

This runner requires LuckPerms in the isolated lane. It temporarily sets the
block teleport wait to two seconds, denies the owner's bypass permission,
tests a completed countdown and cancellation after movement, then restores the
original block configuration even when the test fails.

The runtime probe runner checks public API access, custom events, configured
create/remove actions, environmental listeners, and server-side `/ps view`
particle-task generation:

```powershell
.\run-probe-flow.ps1 `
  -Lane purpur-1.21.10-protectionstones-smoke `
  -JavaExe C:\path\to\java.exe `
  -Port 25581 `
  -BaseX 1600 `
  -ExpectedCandidateSha256 4E002C5A8A42C955803C7532C2EF4D4F524655D3806523997E9083A065E06E50
```

Build `../runtime-probe` first. The runner installs that test-only JAR into the
isolated lane, temporarily enables deterministic region action messages, and
restores the original TOML bytes after the server stops.

Mineflayer's known particle decoder limitation is tolerated only after the
view assertion is requested. The server log must still report a successful
real command dispatch and a non-zero tracked particle-task count.

The integration runner verifies real sale, purchase, rent, tax,
PlaceholderAPI, LuckPerms limit, offline UUID, and admin cleanup behavior:

```powershell
.\run-integration-flow.ps1 `
  -Lane purpur-1.21.10-protectionstones-smoke `
  -JavaExe C:\path\to\java.exe `
  -Port 25581 `
  -BaseX 5000 `
  -ExpectedCandidateSha256 4E002C5A8A42C955803C7532C2EF4D4F524655D3806523997E9083A065E06E50
```

Build `../test-vault` and `../integration-probe` first. The runner restores
the temporarily edited tax configuration byte-for-byte after every run.

The migration runner creates a fresh dataset with the unmodified upstream
`2.10.6` JAR, swaps in the fork candidate, and verifies that dataset through
two candidate restarts. Build the exact upstream commit documented by the
runner into
`.ai-control/workspace-local/protectionstones-upstream-api-89be4ae/target/protectionstones-2.10.6.jar`
before running it:

```powershell
.\run-migration-flow.ps1 `
  -JavaExe C:\path\to\java.exe `
  -ExpectedCandidateSha256 4E002C5A8A42C955803C7532C2EF4D4F524655D3806523997E9083A065E06E50
```

For `26.2`, the isolated lane may include pinned ViaVersion and ViaBackwards so
the fixed `1.21.10` Mineflayer protocol can reach the server. Those plugins are
test transport only and are not ProtectionStones dependencies.
