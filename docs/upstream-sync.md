# Upstream Synchronization

## Remotes

```powershell
git remote -v
git fetch upstream --tags --prune
git fetch folia-reference --prune
```

Never merge the Folia reference remote. It is evidence for scheduler review
only.

## Update Procedure

1. Create `codex/protectionstones-upstream-<version>` from the last released
   fork commit.
2. Record old/new upstream hashes and inspect `git diff --stat`.
3. Merge `upstream/master` without rewriting the published fork history.
4. Resolve upstream changes while preserving the scheduler boundary.
5. Re-audit commands, region mutation, WorldGuard/WorldEdit APIs, teleports,
   reload, static caches, and plugin metadata.
6. Update compile dependencies only when the lowest common runtime lane still
   works.
7. Run Java 21 and Java 25 automated verification.
8. Build one candidate and run all four local runtime lanes.
9. Update the changelog, matrix, evidence, checksum, and workspace control
   records.

## Versioning

Use `<upstream-version>-pvc.<revision>`. Never reuse a released revision for
different bytes.

`origin` publication requires the operator-owned GitHub repository. If the
remote does not exist or authentication is unavailable, local work may
continue, but release publication remains open and must not be reported as
complete.
