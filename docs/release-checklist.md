# Release Checklist

- [ ] Operator `origin` exists and branch is pushed.
- [x] Upstream base commit and fork version are recorded.
- [x] Java 21 `clean verify` passes.
- [x] Java 25 `clean verify` passes.
- [x] Two clean Java 21 builds produce identical main-JAR SHA-256 values.
- [x] Main classes have bytecode major version 65.
- [x] `plugin.yml` has the expected name, version, dependencies, API version,
      and Folia declaration.
- [x] JAR does not bundle WorldEdit, WorldGuard, Vault, PlaceholderAPI,
      LuckPerms, Paper, or server implementation classes.
- [x] Public API/event compatibility is compared with the upstream baseline.
- [ ] All four lane manifests contain exact server/dependency checksums.
- [ ] The same candidate checksum passes every core sheet.
- [x] Purpur and Folia integration sheets pass.
- [x] Copied upstream config and region data survive reload and restart.
- [ ] Logs contain no illegal-thread, scheduler, dependency, or task-leak error.
- [ ] Final JAR is copied to `downloads/`.
- [ ] Matching `.jar.sha256` contains exactly one checksum for that JAR.
- [ ] Compatibility matrix, changelog, testing evidence, and workspace
      `.ai-control` records are current.
- [x] No production server was modified.

Any unchecked compatibility lane blocks release.
