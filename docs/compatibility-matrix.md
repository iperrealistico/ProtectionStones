# Compatibility Matrix

Status date: 2026-07-24

Candidate: `ProtectionStones-2.10.6-pvc.1.jar`

Current candidate SHA-256:
`4E002C5A8A42C955803C7532C2EF4D4F524655D3806523997E9083A065E06E50`

No lane is a release pass until it records the same candidate SHA-256 and a
completed core test sheet.

| Lane | Server source/build | Java | WorldEdit | WorldGuard | Status |
| --- | --- | --- | --- | --- | --- |
| Purpur 1.21.10 | Purpur build 2535 | 21 | 7.4.2 | WorldGuard-Folia 7.0.15 snapshot, 2026-02-02 | AVAILABLE CORE PASS; REPRESENTATIVE INTEGRATIONS PASS |
| Purpur 26.2 | Purpur build 2614 | 25 | 7.4.4 | 7.0.17 | AVAILABLE CORE PASS |
| Folia 1.21.10 | No official PaperMC Folia build or source line exists | 21 | 7.4.2 | WorldGuard-Folia 7.0.15 snapshot, 2026-02-02 | BLOCKED |
| Folia 26.2 | Source commit `602048cb815db2ded68cca8cd43f480b983185a1` | 25 | 7.4.4 | 7.0.17 | AVAILABLE CORE PASS; REPRESENTATIVE INTEGRATIONS PASS |

## Dependency Sources

- WorldEdit 7.4.2:
  `https://cdn.modrinth.com/data/1u6JkXh5/versions/p8T2aZ8U/worldedit-bukkit-7.4.2.jar`
- WorldEdit 7.4.4:
  `https://cdn.modrinth.com/data/1u6JkXh5/versions/qNuPcliz/worldedit-bukkit-7.4.4.jar`
- WorldGuard-Folia 7.0.15 snapshot:
  `https://github.com/Inquisitors-transfers/WorldGuard-Folia/releases/download/2026-02-02/worldguard-bukkit-7.0.15-SNAPSHOT-dist.jar`
- WorldGuard 7.0.17:
  `https://cdn.modrinth.com/data/DKY9btbd/versions/pI4UHLJL/worldguard-bukkit-7.0.17.jar`

Representative integration dependencies:

- LuckPerms Bukkit 5.5.65, SHA-256
  `8B842D9D95C3F3C056E471214D156C0D3D704A46CBDD1A04A9BC47281D54B8A3`.
- PlaceholderAPI 2.12.2 on Purpur 1.21.10, SHA-256
  `FF76AF20C7ACF327FF2A28FB2DBD6694E3F946503E72635A5F7B6CB2E64FC014`.
- Unmodified PlaceholderAPI commit
  `7d21d2f1d73f045b86812c70e6c6975b102c6d89` on the locally source-built
  Folia 26.2 lane, version `2.12.4-DEV-7d21d2f`, SHA-256
  `B1B706DD708A745A4C9F4A3BCF591684D6055FF8AAAC1145B19F2113C2E237B2`.

PlaceholderAPI 2.12.2 cannot parse the non-release server version string
`26.2.local-SNAPSHOT`. The pinned official source commit uses its newer server
version resolver and loads without modification. This is a test-environment
metadata issue, not a ProtectionStones runtime patch.

The missing Folia 1.21.10 runtime is a release blocker. Folia history updates
directly from 1.21.8 to 1.21.11, so substituting either version would not prove
the requested lane.

### Folia 1.21.10 blocker evidence

The blocker was re-audited against the official PaperMC sources on
2026-07-24:

- The PaperMC Fill GraphQL catalog for Folia family `1.21` contains
  `1.21.4`, `1.21.5`, `1.21.6`, `1.21.8`, and `1.21.11`; it does not contain
  `1.21.10`. A direct version query for `1.21.10` returns `null`.
- `PaperMC/Folia` has no `ver/1.21.10` branch and no tag for that version.
- Official commit
  `e1120c1436f9a4a0f849a22ec8c62c7a1e02b74c` still declares
  `mcVersion=1.21.8`. Its direct child
  `8bfaa08bec8dfc0b55ab78b82b56dde20d3f55ba` changes the declaration to
  `mcVersion=1.21.11`.

PaperMC catalog: `https://fill.papermc.io/graphql`

Folia source: `https://github.com/PaperMC/Folia`

Creating an unreviewed private server fork by attempting to transplant Folia
patches onto Paper 1.21.10 would introduce a different, unaudited runtime. A
pass on that runtime would not prove compatibility with a released Folia
1.21.10 implementation and would expand this plugin-maintenance task into
maintaining server software. The release gate therefore requires an exact,
provenanced Folia 1.21.10 implementation rather than a locally invented
substitute.

`AVAILABLE CORE PASS` covers two-player physical placement and break, exact
WorldGuard region assertions, member/owner/flag/home/hide/parent/merge
behavior, immediate/delayed/cancelled teleport, real `/ps view` dispatch and
particle-task generation, environmental protections, reload, clean stop, real
restart, persistence, and removal.

The representative integration passes cover real Vault sale, purchase, rent,
and tax transfers; three PlaceholderAPI values; a LuckPerms global claim
limit; offline owner UUID resolution; and admin cleanup preview/removal.
Configured actions, public API calls, and custom events also pass on both
representative platforms.

An upstream-data migration test created a region using the unmodified
ProtectionStones 2.10.6 JAR
`D5CEF66231F3534EA2554822947CC882C8D14002208C3639446F0617589CF17C`.
The candidate preserved its name, owner, member, flags, priority, home, sale
state, price, and all three upstream TOML/YAML files through two candidate
restarts.

The unavailable fourth lane remains a release blocker, so none of these
statuses constitutes a four-lane release pass.
