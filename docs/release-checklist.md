# Release Checklist

- [x] Operator branch is pushed to `origin`.
- [x] Upstream base commit and fork version are recorded.
- [x] Java 21 and Java 25 `clean verify` pass.
- [x] Two clean canonical Java 21 builds reproduce one main-JAR SHA-256.
- [x] The release JAR is the Java 21 build, not the compiler-distinct Java 25
      verification output.
- [x] Main classes have bytecode major version 65.
- [x] `plugin.yml` metadata and `folia-supported: true` are verified.
- [x] Required/optional server APIs are not bundled in the JAR.
- [x] Public/protected API compatibility is compared with upstream.
- [x] All three manifests contain exact server/dependency checksums.
- [x] One candidate checksum passes every required runtime sheet.
- [x] Global admin member/owner removal passes on every lane without deleting
      regions.
- [x] Purpur and Folia representative integration sheets pass.
- [x] Upstream config and region data survive two candidate restarts.
- [x] Logs contain no plugin linkage, illegal-thread, or task-leak error.
- [x] Final JAR and matching checksum are present in `downloads/`.
- [x] Compatibility matrix, changelog, and test documentation are current.
- [x] No production server was modified.

Before a future release, resolve “latest Folia” again and rerun all unchecked
and runtime-dependent gates. Never infer compatibility with a newer Folia
binary from this release.
