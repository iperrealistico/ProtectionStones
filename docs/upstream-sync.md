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
7. Reproduce the release artifact with two clean JDK 21 builds, then run the
   additional Java 25 automated verification without replacing that artifact.
8. Resolve the latest official Folia binary, build one candidate, and run
   Purpur 1.21.10, Purpur 26.2, and that Folia release.
9. Update the changelog, matrix, evidence, checksum, and workspace control
   records.

## Versioning

Use `<upstream-version>-pvc.<revision>`. Never reuse a released revision for
different bytes.

Publish maintenance branches to the operator-owned `origin` without rewriting
history. Record the pushed branch and commit in the release evidence.
