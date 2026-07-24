# Runtime Probe

This local-only helper plugin verifies the ProtectionStones public API, custom
event delivery, environmental block listeners, and server-side `/ps view`
particle-task generation on a real server thread. It is never bundled with or
required by the release artifact.

Build it after the main candidate:

```powershell
..\..\mvnw.cmd -f .\pom.xml clean package
```

The resulting `target/ProtectionStonesRuntimeProbe.jar` has Java 21 bytecode
and declares both a hard dependency on ProtectionStones and Folia support.

The `/ps view` assertion observes ProtectionStones' tracked particle tasks on
the server. Mineflayer 4.34.0 cannot reliably decode the 1.21.10 particle
packet, so client packet parsing is not used as the pass condition.
