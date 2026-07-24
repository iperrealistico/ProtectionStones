# Compatibility Matrix

Status date: 2026-07-24

Candidate: `ProtectionStones-2.10.6-pvc.1.jar`

SHA-256:
`F9DF17E6545880A32B23B4A7CD19264603A3A7B0E1FFEF1C2087AE318C36FBFE`

All rows below used this byte-for-byte identical Java 21 artifact.

| Lane | Server | Java | WorldEdit | WorldGuard | Result |
| --- | --- | --- | --- | --- | --- |
| Purpur 1.21.10 | build 2535 | 21 | 7.4.2 | WorldGuard-Folia 7.0.15 snapshot, 2026-02-02 | PASS |
| Purpur 26.2 | build 2614 | 25 | 7.4.4 | 7.0.17 | PASS |
| Latest official Folia | 26.1.2 build 8 | 25 | 7.4.4 | 7.0.17 | PASS |

At validation time, 26.1.2 build 8 was the newest binary published on the
official [PaperMC Folia downloads page](https://papermc.io/downloads/folia).
“Latest Folia” is a moving target: re-resolve and rerun this matrix before each
future release rather than extending this result to a newer build.

## Runtime Coverage

Every lane passed:

- enable, `/ps reload`, clean stop, and fatal-log scan
- physical claim creation and break
- member, owner, flag, name, priority, home, hide, parent, and merge flows
- delayed and movement-cancelled teleport
- public API, custom events, configured actions, environmental protections,
  and `/ps view`
- `/ps admin removemember` and `/ps admin removeowner` across Overworld and
  Nether, including permission denial, UUID input, ownerless-region
  preservation, save, restart, and persistence

Purpur 1.21.10 and latest Folia also passed representative Vault,
PlaceholderAPI, LuckPerms, offline-player, tax, rent, and cleanup integrations.
An upstream 2.10.6 migration passed two candidate restarts.

## Pinned Checksums

| Artifact | SHA-256 |
| --- | --- |
| Purpur 1.21.10 build 2535 | `4159783677B08B6395782E6150CB28646C70ED988B7948C09E01AA5A5E90F548` |
| Purpur 26.2 build 2614 | `27189194D00B93BDF94045F08423D6E3D55D89DE3519E6548FB5A56CA99DCEA7` |
| Folia 26.1.2 build 8 | `607AFD1C3320008E1FFD2EAEE6780ACE4419D5F8C527B75E79F259BE79EBF57B` |
| WorldEdit 7.4.2 | `0EE152B1BE5DFB51500505E2BF5A8C9D66F09C7FA484BF9AEA384D7E7B459B06` |
| WorldGuard-Folia 7.0.15 snapshot | `0EE453113F45AD4129852FA9334789CC6A1F4700BE3FF9396F11FFC6787E02E1` |
| WorldEdit 7.4.4 | `44C97EE6C1DF9AFA127DF3C5A2C6A7108F826FB44AB7B255A7EC4250FEB89B9D` |
| WorldGuard 7.0.17 | `3F14562509BF01E7680571B6F56932239157FF938F257C3226DF3B4088AE54F2` |

The 26.x test roots use ViaVersion and ViaBackwards 5.11.0 only to transport
the pinned 1.21.10 Mineflayer client. They are not runtime dependencies of
ProtectionStones.

WorldEdit, WorldGuard, Vault, PlaceholderAPI, and LuckPerms are not bundled in
the release JAR. WorldEdit and WorldGuard are required; the others are
optional.
