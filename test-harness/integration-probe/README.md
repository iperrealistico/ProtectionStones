# ProtectionStones Integration Probe

This local-only Java 21 plugin makes two integration tests deterministic without
changing the ProtectionStones production artifact:

- `/psintegrationprobe taxdue` asks the public ProtectionStones API to generate
  the current region's due tax and persists the WorldGuard state.
- `/psintegrationprobe orphan` replaces the invoking owner with a fixed UUID
  that has never joined the isolated server, allowing admin cleanup preview and
  removal to be verified.

The probe depends on the current fork candidate under `../../target/` and must
never be installed on a production server.
