# Test Vault Economy

This local-only plugin is named `Vault`, embeds VaultAPI 1.7, and registers a
thread-safe in-memory economy service. It exists only to exercise
ProtectionStones buy, sell, rent, and tax integration deterministically on
Purpur and Folia.

It is not a production Vault replacement and is never bundled with or required
by the ProtectionStones release JAR. Balances are discarded on server stop.

Build on Java 21:

```powershell
..\..\mvnw.cmd -f .\pom.xml clean package
```

The test harness controls balances with:

```text
/testvault reset
/testvault set <player> <amount>
/testvault balance <player>
```
