# Folia Reference Audit

Reference repository:
`https://github.com/Galajus/ProtectionStones-folia.git`

Audited head:
`56ae832b62fa49919a0c3f77097dbfcd38985304`

Merge base with its historical upstream:
`ed2a2a16c6a85a683c40bcb9e72e9086d251c5e0`

## Findings

| Reference concept | Decision | Current implementation |
| --- | --- | --- |
| `folia-supported` metadata | Adopted | Preserved on current upstream baseline |
| Region scheduler for physical blocks | Adopted and rewritten | Central `runRegion*` methods |
| Entity scheduler for teleport timers | Adopted and rewritten | Tracked `TaskHandle` plus retirement cleanup |
| Async teleport | Adopted | `Player.teleportAsync` |
| Region scheduler for player particles | Rejected | Particles are player-facing and use entity ownership |
| Broad global scheduler substitutions | Rejected | Classified by global, region, entity, or pure async work |
| Async WorldGuard scans | Rejected | WorldGuard-wide work uses global scheduling |
| Permission-limit feature commits | Rejected | Unrelated behavior not present in upstream 2.10.6 contract |
| Direct scheduler calls throughout features | Rejected | Central boundary plus automated policy test |

The reference line is based on ProtectionStones 2.10.4 and cannot be merged
blindly into 2.10.6. No reference commit was cherry-picked.
