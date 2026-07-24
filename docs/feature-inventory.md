# Feature and Risk Inventory

This inventory maps the upstream user contract to source ownership and runtime
verification IDs. `C-*` checks run on every server lane; `I-*` integration
checks run on at least one Purpur and one Folia lane.

| Feature | Source | Mutable/runtime risk | Verification |
| --- | --- | --- | --- |
| Startup, reload, disable | `ProtectionStones`, `PSConfig`, `PSL` | global config and task lifecycle | C-01, C-12, C-14 |
| Block acquisition/give | `ArgGet`, `ArgGive`, `PSProtectBlock` | inventory and optional Vault | C-02, I-01 |
| Claim placement | `BlockHandler`, `ListenerClass` | region block and WG manager | C-02, C-03 |
| Break/unclaim | `ListenerClass`, `ArgUnclaim`, `PSStandardRegion` | region block, event, name cache | C-07 |
| Owners/members | `ArgAddRemove`, `ArgAdminRemovePlayer`, `PSRegion` | player context, global scans, WG domains, and persistence | C-03, C-09 |
| Flags/defaults | `ArgFlag`, `FlagHandler` | WG flags and permissions | C-05 |
| Hide/unhide | `ArgHideUnhide`, `ArgAdminHide`, `PSRegion` | region block ownership | C-06 |
| Homes/teleport | `ArgHome`, `ArgSethome`, `ArgTp` | entity timer, movement, cross-world teleport | C-08 |
| Region particles | `ArgView`, `ParticlesUtil`, `RegionTraverse` | CPU traversal and entity task batch | C-09 |
| Priority/parent | `ArgPriority`, `ArgSetparent` | WG inheritance | C-10 |
| Merge/group regions | `ArgMerge`, `WGMerge`, region subclasses | multi-region WG mutation | C-10 |
| Piston/explosion/liquid/fire/wind | `ListenerClass` | region event ownership | C-11 |
| Create/remove actions | `ListenerClass.execEvent` | sender/entity/global command routing | I-06 |
| Rent | `ArgRent`, `PSEconomy`, `PSStandardRegion` | Vault and repeating global task | I-01 |
| Buy/sell | `ArgBuySell`, `PSStandardRegion` | Vault and ownership transfer | I-01 |
| Tax/autopay | `ArgTax`, `PSEconomy` | Vault, global scan, region deletion | I-01 |
| PlaceholderAPI | `PSPlaceholderExpansion` | optional plugin boundary | I-02 |
| LuckPerms limits | `LimitUtil`, `MiscUtil` | async permission data/API | I-03 |
| UUID/offline players | `UUIDCache`, `PSPlayer` | cross-region cache and profile lookup | I-04 |
| Admin cleanup/repair/stats | `ArgAdmin*` | global scan, report I/O, sequential regions | I-05 |
| Global admin domain removal | `ArgAdminRemovePlayer` | loaded-world scan, ownerless regions, WG save | C-09 |
| Public API/events | `PSRegion`, `PSPlayer`, `event/*` | binary/source and event behavior | I-07 |
| Persistence/restart | WorldGuard flags and TOML/YAML | no destructive migration | C-13, I-08 |

## Command Contract

Default arguments remain: `add`, `remove`, `addowner`, `removeowner`, `admin`,
`buy`, `sell`, `count`, `flag`, `get`, `give`, `hide`, `unhide`, `home`,
`info`, `list`, `merge`, `name`, `priority`, `region`, `reload`, `rent`,
`sethome`, `setparent`, `tax`, `toggle`, `on`, `off`, `tp`, `unclaim`, `view`,
and `help`.

Permissions remain under `protectionstones.*` as declared in `plugin.yml`.
The fork adds `admin removemember <playername|uuid>` and
`admin removeowner <playername|uuid>` under the existing
`protectionstones.admin` permission.
