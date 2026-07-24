/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package dev.espi.protectionstones;

import com.sk89q.worldguard.protection.managers.RegionManager;
import com.sk89q.worldguard.protection.managers.storage.StorageException;
import com.sk89q.worldguard.protection.regions.ProtectedRegion;
import dev.espi.protectionstones.scheduler.TaskHandle;
import dev.espi.protectionstones.utils.MiscUtil;
import dev.espi.protectionstones.utils.WGUtils;
import net.milkbowl.vault.economy.EconomyResponse;
import org.bukkit.Bukkit;
import org.bukkit.World;
import org.bukkit.entity.Player;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Handler for ProtectionStones economy related tasks.
 */

public class PSEconomy {
    private final CopyOnWriteArrayList<PSRegion> rentedList = new CopyOnWriteArrayList<>();
    private TaskHandle rentRunner;
    private TaskHandle taxRunner;

    public PSEconomy() {
        if (!ProtectionStones.getInstance().isVaultSupportEnabled()) {
            ProtectionStones.getInstance().getLogger().warning("Vault is not enabled! Economy functions (renting & buying) will not work!");
            return;
        }
        // find regions that are being rented out (called on startup or reload)
        loadRentList();

        // start rent
        rentRunner = ProtectionStones.getInstance().getTaskScheduler()
                .runGlobalAtFixedRate(this::updateRents, 1, 200);

        // start taxes
        if (ProtectionStones.getInstance().getConfigOptions().taxEnabled)
            taxRunner = ProtectionStones.getInstance().getTaskScheduler()
                    .runGlobalAtFixedRate(this::updateTaxes, 1, 200);
    }

    private synchronized void updateRents() {
        rentedList.removeIf(r -> r.getTypeOptions() == null
                || r.getRentStage() != PSRegion.RentStage.RENTING);
        for (PSRegion region : rentedList) {
            try {
                Duration rentPeriod = MiscUtil.parseRentPeriod(region.getRentPeriod());
                if (Instant.now().getEpochSecond()
                        > region.getRentLastPaid() + rentPeriod.getSeconds()) {
                    doRentPaymentNow(region);
                }
            } catch (Exception ignored) {
            }
        }
    }

    private void updateTaxes() {
        WGUtils.getAllRegionManagers()
                .forEach((w, rgm) -> {
                    for (ProtectedRegion r : rgm.getRegions().values()) {
                        if (ProtectionStones.isPSRegion(r)) {
                            PSRegion psr = PSRegion.fromWGRegion(w, r);
                            processTaxesNow(psr);
                        }
                    }
                });
    }

    /**
     * Stops the economy cycle. Used for reloads when creating a new PSEconomy.
     */
    public void stop() {
        if (rentRunner != null) {
            rentRunner.cancel();
            rentRunner = null;
        }
        if (taxRunner != null) {
            taxRunner.cancel();
            taxRunner = null;
        }
    }

    /**
     * Load list of regions that are rented into memory.
     */

    public void loadRentList() {
        rentedList.clear();

        HashMap<World, RegionManager> managers = WGUtils.getAllRegionManagers();

        for (World w : managers.keySet()) {
            RegionManager rgm = managers.get(w);
            for (ProtectedRegion pr : rgm.getRegions().values()) {
                if (ProtectionStones.isPSRegion(pr)) {
                    rentedList.add(PSRegion.fromWGRegion(w, pr));
                }
            }
        }
    }

    /**
     * Process taxes for a region.
     *
     * @param r the region to process taxes for
     */
    public static void processTaxes(PSRegion r) {
        ProtectionStones.getInstance().getTaskScheduler().runGlobal(() -> processTaxesNow(r));
    }

    private static void processTaxesNow(PSRegion r) {
        // if taxes are enabled for this regions
        if (r.getTypeOptions() != null && r.getTypeOptions().taxPeriod != -1) {
            // update tax payments due
            r.updateTaxPayments();

            // check if a player is set to auto-pay
            if (!r.getTaxPaymentsDue().isEmpty() && r.getTaxAutopayer() != null) {
                PSPlayer psp = PSPlayer.fromUUID(r.getTaxAutopayer());
                EconomyResponse res = r.payTax(psp, psp.getBalance());

                Player player = psp.getPlayer();
                if (player != null && res.amount != 0) {
                    ProtectionStones.getInstance().getTaskScheduler().runEntity(player, () ->
                            PSL.msg(player, PSL.TAX_PAID.msg()
                                .replace("%amount%", String.format("%.2f", res.amount))
                                .replace("%region%", r.getName() == null
                                        ? r.getId()
                                        : r.getName() + " (" + r.getId() + ")")));
                }
            }

            // late tax payment punishment
            if (r.isTaxPaymentLate()) {
                ProtectionStones.getInstance().getTaskScheduler()
                        .runRegion(r.getProtectBlockLocation(), () -> r.deleteRegion(true));
            }
        }
    }

    /**
     * Process a rent payment for a region.
     * It does not do any checks, it is expected to check if the rent time has passed before this function is called.
     *
     * @param r the region to perform the rent payment
     */
    public static void doRentPayment(PSRegion r) {
        ProtectionStones.getInstance().getTaskScheduler().runGlobal(() -> doRentPaymentNow(r));
    }

    private static void doRentPaymentNow(PSRegion r) {
        PSPlayer tenant = PSPlayer.fromPlayer(Bukkit.getOfflinePlayer(r.getTenant()));
        PSPlayer landlord = PSPlayer.fromPlayer(Bukkit.getOfflinePlayer(r.getLandlord()));

        // not enough money for rent
        if (!tenant.hasAmount(r.getPrice())) {
            Player tenantPlayer = Bukkit.getPlayer(r.getTenant());
            if (tenantPlayer != null)
                ProtectionStones.getInstance().getTaskScheduler().runEntity(tenantPlayer, () ->
                        PSL.msg(tenantPlayer, PSL.RENT_EVICT_NO_MONEY_TENANT.msg()
                                .replace("%region%", r.getName() != null ? r.getName() : r.getId())
                                .replace("%price%", String.format("%.2f", r.getPrice()))));

            Player landlordPlayer = Bukkit.getPlayer(r.getLandlord());
            if (landlordPlayer != null)
                ProtectionStones.getInstance().getTaskScheduler().runEntity(landlordPlayer, () ->
                        PSL.msg(landlordPlayer, PSL.RENT_EVICT_NO_MONEY_LANDLORD.msg()
                                .replace("%region%", r.getName() != null ? r.getName() : r.getId())
                                .replace("%tenant%", tenant.getName())));

            r.removeRenting();
            return;
        }

        // send payment messages
        Player tenantPlayer = Bukkit.getPlayer(r.getTenant());
        if (tenantPlayer != null)
            ProtectionStones.getInstance().getTaskScheduler().runEntity(tenantPlayer, () ->
                    PSL.msg(tenantPlayer, PSL.RENT_PAID_TENANT.msg()
                            .replace("%price%", String.format("%.2f", r.getPrice()))
                            .replace("%landlord%", landlord.getName())
                            .replace("%region%", r.getName() != null ? r.getName() : r.getId())));

        Player landlordPlayer = Bukkit.getPlayer(r.getLandlord());
        if (landlordPlayer != null)
            ProtectionStones.getInstance().getTaskScheduler().runEntity(landlordPlayer, () ->
                    PSL.msg(landlordPlayer, PSL.RENT_PAID_LANDLORD.msg()
                            .replace("%price%", String.format("%.2f", r.getPrice()))
                            .replace("%tenant%", tenant.getName())
                            .replace("%region%", r.getName() != null ? r.getName() : r.getId())));

        tenant.pay(landlord, r.getPrice());
        r.setRentLastPaid(Instant.now().getEpochSecond());
        try { // must save region to persist last paid
            r.getWGRegionManager().saveChanges();
        } catch (StorageException e) {
            e.printStackTrace();
        }
    }

    /**
     * Get list of rented regions.
     *
     * @return the list of rented regions
     */
    public List<PSRegion> getRentedList() {
        return rentedList;
    }
}
