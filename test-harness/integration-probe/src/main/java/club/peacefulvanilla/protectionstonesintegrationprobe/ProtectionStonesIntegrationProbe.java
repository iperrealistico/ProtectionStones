package club.peacefulvanilla.protectionstonesintegrationprobe;

import com.sk89q.worldguard.protection.managers.storage.StorageException;
import dev.espi.protectionstones.PSRegion;
import dev.espi.protectionstones.ProtectionStones;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.Locale;
import java.util.UUID;

public final class ProtectionStonesIntegrationProbe extends JavaPlugin {
    private static final UUID NEVER_PLAYED_OWNER =
            UUID.fromString("11111111-2222-3333-8444-555555555555");

    @Override
    public boolean onCommand(
            CommandSender sender,
            Command command,
            String label,
            String[] args
    ) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("PSINTEGRATION FAIL player-required");
            return true;
        }
        if (args.length != 1) {
            sender.sendMessage("PSINTEGRATION FAIL usage");
            return true;
        }

        PSRegion region = PSRegion.fromLocationGroup(player.getLocation());
        if (region == null) {
            player.sendMessage("PSINTEGRATION FAIL region-null");
            return true;
        }

        return switch (args[0].toLowerCase(Locale.ROOT)) {
            case "taxdue" -> prepareTaxDue(player, region);
            case "orphan" -> prepareOrphan(player, region);
            default -> {
                player.sendMessage("PSINTEGRATION FAIL unknown-subcommand");
                yield true;
            }
        };
    }

    private boolean prepareTaxDue(Player player, PSRegion region) {
        ProtectionStones.getInstance().getTaskScheduler().runGlobal(() -> {
            region.updateTaxPayments();
            double owed = region.getTaxPaymentsDue().stream()
                    .mapToDouble(PSRegion.TaxPayment::getAmount)
                    .sum();
            save(region);
            reply(
                    player,
                    "PSINTEGRATION TAX region=" + region.getId()
                            + " due=" + String.format(Locale.ROOT, "%.2f", owed)
            );
        });
        return true;
    }

    private boolean prepareOrphan(Player player, PSRegion region) {
        ProtectionStones.getInstance().getTaskScheduler().runGlobal(() -> {
            region.addOwner(NEVER_PLAYED_OWNER);
            region.removeOwner(player.getUniqueId());
            save(region);
            reply(
                    player,
                    "PSINTEGRATION ORPHAN region=" + region.getId()
                            + " activeOwner=" + region.isOwner(player.getUniqueId())
                            + " staleOwner=" + region.isOwner(NEVER_PLAYED_OWNER)
                            + " owners=" + region.getOwners().size()
            );
        });
        return true;
    }

    private void save(PSRegion region) {
        try {
            region.getWGRegionManager().saveChanges();
        } catch (StorageException exception) {
            throw new IllegalStateException(
                    "Could not persist integration probe region " + region.getId(),
                    exception
            );
        }
    }

    private void reply(Player player, String message) {
        ProtectionStones.getInstance().getTaskScheduler()
                .runEntity(player, () -> player.sendMessage(message));
    }
}
