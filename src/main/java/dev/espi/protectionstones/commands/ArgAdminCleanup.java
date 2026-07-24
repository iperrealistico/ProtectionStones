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
import com.sk89q.worldguard.protection.regions.ProtectedRegion;
import dev.espi.protectionstones.PSL;
import dev.espi.protectionstones.PSRegion;
import dev.espi.protectionstones.ProtectionStones;
import dev.espi.protectionstones.utils.WGUtils;
import org.bukkit.Bukkit;
import org.bukkit.ChatColor;
import org.bukkit.OfflinePlayer;
import org.bukkit.World;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

public class ArgAdminCleanup {

    private static final AtomicBoolean CLEANUP_RUNNING = new AtomicBoolean();
    private static final AtomicLong CLEANUP_GENERATION = new AtomicLong();

    // /ps admin cleanup [remove/preview]
    static boolean argumentAdminCleanup(CommandSender sender, String[] preParseArgs) {
        if (preParseArgs.length < 3
                || !Arrays.asList("remove", "preview").contains(preParseArgs[2].toLowerCase())) {
            PSL.msg(sender, ArgAdmin.getCleanupHelp());
            return true;
        }

        String operation = preParseArgs[2].toLowerCase();
        World world;
        String alias = null;
        List<String> args = new ArrayList<>();

        for (int i = 3; i < preParseArgs.length; i++) {
            if (preParseArgs[i].equals("-t") && i != preParseArgs.length - 1) {
                alias = preParseArgs[++i];
            } else {
                args.add(preParseArgs[i]);
            }
        }

        if (args.size() > 1 && Bukkit.getWorld(args.get(1)) != null) {
            world = Bukkit.getWorld(args.get(1));
        } else if (sender instanceof Player player) {
            world = player.getWorld();
        } else {
            PSL.msg(sender, args.size() > 1
                    ? PSL.INVALID_WORLD.msg()
                    : PSL.ADMIN_CONSOLE_WORLD.msg());
            return true;
        }

        int days;
        try {
            days = args.isEmpty() ? 30 : Integer.parseInt(args.get(0));
        } catch (NumberFormatException exception) {
            PSL.msg(sender, ArgAdmin.getCleanupHelp());
            return true;
        }

        if (!CLEANUP_RUNNING.compareAndSet(false, true)) {
            PSL.msg(sender, ChatColor.RED + "A cleanup operation is already running.");
            return true;
        }
        long cleanupId = CLEANUP_GENERATION.incrementAndGet();

        Path previewFile = null;
        if (operation.equals("preview")) {
            DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd H-m-s");
            previewFile = ProtectionStones.getInstance().getDataFolder().toPath()
                    .resolve(LocalDateTime.now().format(formatter) + " cleanup preview.txt");
        }

        RegionManager regionManager = WGUtils.getRegionManagerWithWorld(world);
        String selectedAlias = alias;
        Path selectedPreviewFile = previewFile;
        ProtectionStones.getInstance().getTaskScheduler().runGlobal(() ->
                scanRegions(
                        sender,
                        operation,
                        days,
                        world,
                        regionManager,
                        selectedAlias,
                        selectedPreviewFile,
                        cleanupId
                ));
        return true;
    }

    private static void scanRegions(
            CommandSender sender,
            String operation,
            int days,
            World world,
            RegionManager regionManager,
            String alias,
            Path previewFile,
            long cleanupId
    ) {
        if (!isActive(cleanupId)) {
            return;
        }
        try {
            send(sender, () -> PSL.msg(sender, PSL.ADMIN_CLEANUP_HEADER.msg()
                    .replace("%arg%", operation)
                    .replace("%days%", String.valueOf(days))));

            Set<UUID> activePlayers = new HashSet<>();
            for (OfflinePlayer offlinePlayer : Bukkit.getServer().getOfflinePlayers()) {
                long daysSinceLastPlayed =
                        (System.currentTimeMillis() - offlinePlayer.getLastPlayed()) / 86400000L;
                if (daysSinceLastPlayed < days) {
                    activePlayers.add(offlinePlayer.getUniqueId());
                }
            }

            List<PSRegion> toDelete = new ArrayList<>();
            for (ProtectedRegion protectedRegion : regionManager.getRegions().values()) {
                PSRegion region = PSRegion.fromWGRegion(world, protectedRegion);
                if (region == null) {
                    continue;
                }
                if (alias != null
                        && (region.getTypeOptions() == null
                        || !region.getTypeOptions().alias.equals(alias))) {
                    continue;
                }

                long activeOwners = region.getOwners().stream().filter(activePlayers::contains).count();
                long activeMembers = region.getMembers().stream().filter(activePlayers::contains).count();
                if (activeOwners == 0
                        && (ProtectionStones.getInstance().getConfigOptions()
                        .cleanupDeleteRegionsWithMembersButNoOwners || activeMembers == 0)) {
                    toDelete.add(region);
                }
            }

            if (operation.equals("preview")) {
                writePreview(sender, toDelete, previewFile, cleanupId);
            } else {
                removeNext(sender, toDelete.iterator(), cleanupId);
            }
        } catch (RuntimeException exception) {
            fail(sender, exception, cleanupId);
        }
    }

    private static void writePreview(
            CommandSender sender,
            List<PSRegion> regions,
            Path previewFile,
            long cleanupId
    ) {
        ProtectionStones.getInstance().getTaskScheduler().runAsync(() -> {
            if (!isActive(cleanupId)) {
                return;
            }
            try {
                Files.createDirectories(previewFile.getParent());
                List<String> regionIds = regions.stream().map(PSRegion::getId).toList();
                Files.write(previewFile, regionIds, StandardCharsets.UTF_8);
                if (!finish(cleanupId)) {
                    return;
                }
                send(sender, () -> {
                    for (String regionId : regionIds) {
                        sender.sendMessage(ChatColor.YELLOW + "Found region " + regionId
                                + " that can be deleted.");
                    }
                    sendFooter(sender, "preview");
                    sender.sendMessage(ChatColor.YELLOW
                            + "Dumped the list regions that can be deleted in "
                            + previewFile.getFileName() + " (in the plugin folder).");
                });
            } catch (IOException exception) {
                fail(sender, exception, cleanupId);
            }
        });
    }

    // Delete one region per tick to avoid loading all protection-block chunks at once.
    private static void removeNext(
            CommandSender sender,
            Iterator<PSRegion> regions,
            long cleanupId
    ) {
        if (!isActive(cleanupId)) {
            return;
        }
        if (!regions.hasNext()) {
            if (finish(cleanupId)) {
                send(sender, () -> sendFooter(sender, "remove"));
            }
            return;
        }

        PSRegion region = regions.next();
        ProtectionStones.getInstance().getTaskScheduler().runRegionDelayed(
                region.getProtectBlockLocation(),
                () -> {
                    try {
                        if (region.deleteRegion(true)) {
                            send(sender, () -> sender.sendMessage(ChatColor.YELLOW
                                    + "Removed region " + region.getId()
                                    + " due to inactive owners."));
                        }
                    } catch (RuntimeException exception) {
                        ProtectionStones.getPluginLogger().severe(
                                "Failed to remove cleanup region " + region.getId()
                                        + ": " + exception.getMessage());
                    } finally {
                        removeNext(sender, regions, cleanupId);
                    }
                },
                1
        );
    }

    private static void sendFooter(CommandSender sender, String operation) {
        PSL.msg(sender, PSL.ADMIN_CLEANUP_FOOTER.msg().replace("%arg%", operation));
    }

    private static void send(CommandSender sender, Runnable action) {
        ProtectionStones.getInstance().getTaskScheduler().runCommandSender(sender, action);
    }

    private static void fail(CommandSender sender, Exception exception, long cleanupId) {
        if (!finish(cleanupId)) {
            return;
        }
        ProtectionStones.getPluginLogger().severe(
                "ProtectionStones cleanup failed: " + exception.getMessage());
        exception.printStackTrace();
        send(sender, () -> sender.sendMessage(
                ChatColor.RED + "Internal error, please check the console logs."));
    }

    private static boolean isActive(long cleanupId) {
        return CLEANUP_RUNNING.get() && CLEANUP_GENERATION.get() == cleanupId;
    }

    private static boolean finish(long cleanupId) {
        if (CLEANUP_GENERATION.get() != cleanupId) {
            return false;
        }
        return CLEANUP_RUNNING.compareAndSet(true, false);
    }

    public static void cancelActiveCleanup() {
        CLEANUP_GENERATION.incrementAndGet();
        CLEANUP_RUNNING.set(false);
    }
}
