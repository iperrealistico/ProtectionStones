/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

package dev.espi.protectionstones.commands;

import com.sk89q.worldguard.protection.managers.RegionManager;
import com.sk89q.worldguard.protection.managers.storage.StorageException;
import com.sk89q.worldguard.protection.regions.ProtectedRegion;
import dev.espi.protectionstones.PSL;
import dev.espi.protectionstones.PSRegion;
import dev.espi.protectionstones.ProtectionStones;
import dev.espi.protectionstones.utils.UUIDCache;
import dev.espi.protectionstones.utils.WGUtils;
import org.bukkit.World;
import org.bukkit.command.CommandSender;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.logging.Level;

final class ArgAdminRemovePlayer {

    enum DomainRole {
        MEMBER("member"),
        OWNER("owner");

        private final String displayName;

        DomainRole(String displayName) {
            this.displayName = displayName;
        }

        String displayName() {
            return displayName;
        }

        boolean contains(PSRegion region, UUID playerUuid) {
            return this == MEMBER
                    ? region.isMember(playerUuid)
                    : region.isOwner(playerUuid);
        }

        void remove(PSRegion region, UUID playerUuid) {
            if (this == MEMBER) {
                region.removeMember(playerUuid);
            } else {
                region.removeOwner(playerUuid);
            }
        }
    }

    private ArgAdminRemovePlayer() {
    }

    static boolean argumentAdminRemovePlayer(
            CommandSender sender,
            String[] args,
            DomainRole role
    ) {
        if (args.length != 3) {
            return PSL.msg(sender, role == DomainRole.MEMBER
                    ? ArgAdmin.getRemoveMemberHelp()
                    : ArgAdmin.getRemoveOwnerHelp());
        }

        UUID playerUuid = resolveTargetUuid(args[2]);
        if (playerUuid == null) {
            return PSL.msg(sender, PSL.PLAYER_NOT_FOUND.msg());
        }

        String cachedName = UUIDCache.getNameFromUUID(playerUuid);
        String displayName = cachedName == null ? args[2] : cachedName;
        PSL.msg(sender, PSL.ADMIN_REMOVE_PLAYER_STARTED.msg()
                .replace("%player%", displayName)
                .replace("%role%", role.displayName()));

        ProtectionStones.getInstance().getTaskScheduler().runGlobal(() ->
                removeFromAllRegionsSafely(sender, playerUuid, displayName, role));
        return true;
    }

    static UUID resolveTargetUuid(String target) {
        UUID cachedUuid = UUIDCache.getUUIDFromName(target);
        if (cachedUuid != null) {
            return cachedUuid;
        }

        try {
            return UUID.fromString(target);
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private static void removeFromAllRegionsSafely(
            CommandSender sender,
            UUID playerUuid,
            String displayName,
            DomainRole role
    ) {
        try {
            removeFromAllRegions(sender, playerUuid, displayName, role);
        } catch (RuntimeException exception) {
            ProtectionStones.getInstance().getLogger().log(
                    Level.SEVERE,
                    "Could not complete global admin " + role.displayName()
                            + " removal for " + displayName,
                    exception
            );
            ProtectionStones.getInstance().getTaskScheduler().runCommandSender(sender, () ->
                    PSL.msg(sender, PSL.ADMIN_REMOVE_PLAYER_FAILED.msg()
                            .replace("%player%", displayName)
                            .replace("%role%", role.displayName())));
        }
    }

    private static void removeFromAllRegions(
            CommandSender sender,
            UUID playerUuid,
            String displayName,
            DomainRole role
    ) {
        int affectedRegions = 0;
        List<String> failedWorlds = new ArrayList<>();

        for (Map.Entry<World, RegionManager> entry : WGUtils.getAllRegionManagers().entrySet()) {
            World world = entry.getKey();
            RegionManager regionManager = entry.getValue();
            boolean worldChanged = false;

            for (ProtectedRegion protectedRegion
                    : new ArrayList<>(regionManager.getRegions().values())) {
                if (!ProtectionStones.isPSRegionFormat(protectedRegion)) {
                    continue;
                }

                PSRegion region = PSRegion.fromWGRegion(world, protectedRegion);
                if (region == null || !role.contains(region, playerUuid)) {
                    continue;
                }

                role.remove(region, playerUuid);
                affectedRegions++;
                worldChanged = true;
            }

            if (worldChanged) {
                try {
                    regionManager.saveChanges();
                } catch (StorageException exception) {
                    failedWorlds.add(world.getName());
                    ProtectionStones.getInstance().getLogger().log(
                            Level.SEVERE,
                            "Could not persist admin " + role.displayName()
                                    + " removal for world " + world.getName(),
                            exception
                    );
                }
            }
        }

        int finalAffectedRegions = affectedRegions;
        List<String> finalFailedWorlds = List.copyOf(failedWorlds);
        ProtectionStones.getInstance().getTaskScheduler().runCommandSender(sender, () -> {
            if (!finalFailedWorlds.isEmpty()) {
                PSL.msg(sender, PSL.ADMIN_REMOVE_PLAYER_SAVE_FAILED.msg()
                        .replace("%player%", displayName)
                        .replace("%role%", role.displayName())
                        .replace("%count%", String.valueOf(finalAffectedRegions))
                        .replace("%worlds%", String.join(", ", finalFailedWorlds)));
            } else if (finalAffectedRegions == 0) {
                PSL.msg(sender, PSL.ADMIN_REMOVE_PLAYER_NONE.msg()
                        .replace("%player%", displayName)
                        .replace("%role%", role.displayName()));
            } else {
                PSL.msg(sender, PSL.ADMIN_REMOVE_PLAYER_COMPLETE.msg()
                        .replace("%player%", displayName)
                        .replace("%role%", role.displayName())
                        .replace("%count%", String.valueOf(finalAffectedRegions)));
            }
        });
    }
}
