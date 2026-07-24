# Global Admin Domain Removal

## Commands

```text
/ps admin removemember <playername|uuid>
/ps admin removeowner <playername|uuid>
```

Both commands are subcommands of the existing `/ps admin` tree and require
`protectionstones.admin`. They are available to authorized players and the
console.

## Behavior

The command resolves a cached player name or a literal UUID, then runs one
global WorldGuard scan across every loaded Bukkit world. It mutates only
ProtectionStones-formatted regions, removes the UUID from the selected member
or owner domain, and calls `RegionManager.saveChanges()` once for each changed
world.

No region, protection block, flag, name, parent, or merged-region definition is
deleted. Removing the last owner is allowed and leaves the region ownerless.
Existing `PSRegion.removeOwner` semantics still apply, including clearing tax,
sale, or rent ownership metadata when the removed UUID is responsible for it.

The completion message reports the number of affected WorldGuard regions. A
save failure is logged with the world name and reported to the command sender.
Worlds not loaded by the server cannot be scanned and must be loaded before the
command is run.

## Verification

`test-harness/mineflayer/run-admin-domain-flow.ps1` verifies:

- denial for a non-admin player
- name-based member removal in Overworld and Nether
- name- and UUID-based owner removal
- zero-owner regions remaining present
- no-match reporting
- persistence through a real stop and restart
- absence of linkage and Folia thread-ownership failures
