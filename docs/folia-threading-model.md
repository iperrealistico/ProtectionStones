# Folia Threading Model

## Scheduler Rules

All scheduling enters through `PlatformScheduler`.

| Work | Scheduler |
| --- | --- |
| WorldGuard-wide scans, lifecycle, recipe/config publication | Global |
| Block reads/writes and claim block mutation | Region at block location |
| Player messages, GUI, particles, countdowns | Entity |
| Profile cache writes and file-only report output | Async |

The location used for region scheduling is calculated from the ProtectionStones
region ID through `PSRegion.getProtectBlockLocation()`. Code must not read a
world block merely to discover the scheduler location.

## State Policy

- `protectionStonesOptions` is an immutable, volatile snapshot.
- `regionNameToID` is a concurrent map with copy-on-write ID lists.
- UUID, teleport, cooldown, and tab-completion caches use concurrent
  collections.
- Rent state uses `CopyOnWriteArrayList`.
- Help and recipe lists are published as immutable snapshots.
- Reload is serialized; cleanup uses a generation token to prevent an old run
  from interacting with a newer run.

## Lifecycle

`onDisable()` stops economy cycles, delayed teleports, cleanup progression, and
particle tasks before shutting down the scheduler. `/ps reload` cancels tasks
that depend on old configuration before loading and publishing replacement
state.

Entity scheduler retirement callbacks remove associated task handles. The
central scheduler also tracks every task and cancels the remaining set during
plugin disable.

## Review Gate

The following are forbidden outside the scheduler package:

- Bukkit legacy scheduler calls
- direct Paper scheduler type imports
- CraftBukkit or NMS imports
- synchronous player teleport

Any upstream change involving world access, commands, WorldGuard mutation,
teleport, caches, or callbacks requires a new ownership review and all four
runtime lanes.
