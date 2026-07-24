package club.peacefulvanilla.protectionstonesprobe;

import dev.espi.protectionstones.PSRegion;
import dev.espi.protectionstones.event.PSBreakProtectBlockEvent;
import dev.espi.protectionstones.event.PSCreateEvent;
import dev.espi.protectionstones.event.PSRemoveEvent;
import dev.espi.protectionstones.utils.ParticlesUtil;
import org.bukkit.ExplosionResult;
import org.bukkit.Material;
import org.bukkit.block.Block;
import org.bukkit.block.BlockFace;
import org.bukkit.block.BlockState;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.entity.WindCharge;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBurnEvent;
import org.bukkit.event.block.BlockExplodeEvent;
import org.bukkit.event.block.BlockFadeEvent;
import org.bukkit.event.block.BlockFormEvent;
import org.bukkit.event.block.BlockFromToEvent;
import org.bukkit.event.block.BlockIgniteEvent;
import org.bukkit.event.block.BlockPistonExtendEvent;
import org.bukkit.event.block.SpongeAbsorbEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.player.PlayerBucketEmptyEvent;
import org.bukkit.inventory.EquipmentSlot;
import org.bukkit.inventory.ItemStack;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;

public final class ProtectionStonesRuntimeProbe extends JavaPlugin implements Listener {
    private final AtomicInteger createEvents = new AtomicInteger();
    private final AtomicInteger breakEvents = new AtomicInteger();
    private final AtomicInteger removeEvents = new AtomicInteger();

    @Override
    public void onEnable() {
        getServer().getPluginManager().registerEvents(this, this);
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onCreate(PSCreateEvent event) {
        createEvents.incrementAndGet();
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onBreak(PSBreakProtectBlockEvent event) {
        breakEvents.incrementAndGet();
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onRemove(PSRemoveEvent event) {
        removeEvents.incrementAndGet();
    }

    @Override
    public boolean onCommand(
            CommandSender sender,
            Command command,
            String label,
            String[] args
    ) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("PSPROBE FAIL player-required");
            return true;
        }
        if (args.length == 0) {
            sender.sendMessage("PSPROBE FAIL usage");
            return true;
        }

        return switch (args[0].toLowerCase(Locale.ROOT)) {
            case "reset" -> reset(sender);
            case "events" -> events(sender);
            case "api" -> api(player);
            case "environment" -> environment(player);
            case "view" -> view(player);
            default -> {
                sender.sendMessage("PSPROBE FAIL unknown-subcommand");
                yield true;
            }
        };
    }

    private boolean reset(CommandSender sender) {
        createEvents.set(0);
        breakEvents.set(0);
        removeEvents.set(0);
        sender.sendMessage("PSPROBE RESET");
        return true;
    }

    private boolean events(CommandSender sender) {
        sender.sendMessage(
                "PSPROBE EVENTS create=" + createEvents.get()
                        + " break=" + breakEvents.get()
                        + " remove=" + removeEvents.get()
        );
        return true;
    }

    private boolean api(Player player) {
        PSRegion region = PSRegion.fromLocation(player.getLocation());
        if (region == null) {
            player.sendMessage("PSPROBE FAIL api-region-null");
            return true;
        }

        boolean owner = region.isOwner(player.getUniqueId());
        boolean blockMatches = region.getProtectBlock().getType() == Material.EMERALD_ORE;
        boolean homeWorldMatches = region.getHome().getWorld() == player.getWorld();
        player.sendMessage(
                "PSPROBE API id=" + region.getId()
                        + " type=" + region.getType()
                        + " owner=" + owner
                        + " block=" + blockMatches
                        + " homeWorld=" + homeWorldMatches
        );
        return true;
    }

    private boolean environment(Player player) {
        PSRegion region = PSRegion.fromLocation(player.getLocation());
        if (region == null) {
            player.sendMessage("PSPROBE FAIL environment-region-null");
            return true;
        }

        Block protectBlock = region.getProtectBlock();
        Block neighbor = protectBlock.getRelative(BlockFace.EAST);
        Block below = protectBlock.getRelative(BlockFace.DOWN);

        BlockPistonExtendEvent piston = new BlockPistonExtendEvent(
                neighbor,
                List.of(protectBlock),
                BlockFace.WEST
        );
        getServer().getPluginManager().callEvent(piston);

        List<Block> explosionBlocks = new ArrayList<>(List.of(protectBlock));
        BlockState explodedState = neighbor.getState();
        BlockExplodeEvent explosion = new BlockExplodeEvent(
                neighbor,
                explodedState,
                explosionBlocks,
                1.0F,
                ExplosionResult.DESTROY
        );
        getServer().getPluginManager().callEvent(explosion);
        boolean explosionProtected = !explosionBlocks.contains(protectBlock)
                && protectBlock.getType() == Material.EMERALD_ORE;

        WindCharge windCharge = player.getWorld().spawn(
                protectBlock.getLocation().add(0.5, 1.0, 0.5),
                WindCharge.class
        );
        List<Block> windBlocks = new ArrayList<>(List.of(protectBlock));
        EntityExplodeEvent wind = new EntityExplodeEvent(
                windCharge,
                windCharge.getLocation(),
                windBlocks,
                1.0F,
                ExplosionResult.DESTROY
        );
        getServer().getPluginManager().callEvent(wind);
        windCharge.remove();
        boolean windProtected = !windBlocks.contains(protectBlock)
                && protectBlock.getType() == Material.EMERALD_ORE;

        BlockFromToEvent liquid = new BlockFromToEvent(neighbor, protectBlock);
        getServer().getPluginManager().callEvent(liquid);

        PlayerBucketEmptyEvent bucket = new PlayerBucketEmptyEvent(
                player,
                protectBlock,
                below,
                BlockFace.UP,
                Material.WATER_BUCKET,
                new ItemStack(Material.WATER_BUCKET),
                EquipmentSlot.HAND
        );
        getServer().getPluginManager().callEvent(bucket);

        BlockIgniteEvent ignite = new BlockIgniteEvent(
                protectBlock,
                BlockIgniteEvent.IgniteCause.FLINT_AND_STEEL,
                player
        );
        getServer().getPluginManager().callEvent(ignite);

        BlockBurnEvent burn = new BlockBurnEvent(protectBlock, neighbor);
        getServer().getPluginManager().callEvent(burn);

        BlockState airState = protectBlock.getState();
        airState.setType(Material.AIR);
        BlockFadeEvent fade = new BlockFadeEvent(protectBlock, airState);
        getServer().getPluginManager().callEvent(fade);
        BlockFormEvent form = new BlockFormEvent(protectBlock, airState);
        getServer().getPluginManager().callEvent(form);

        SpongeAbsorbEvent sponge = new SpongeAbsorbEvent(
                protectBlock,
                List.of(protectBlock.getState())
        );
        getServer().getPluginManager().callEvent(sponge);

        player.sendMessage(
                "PSPROBE ENV piston=" + piston.isCancelled()
                        + " explosion=" + explosionProtected
                        + " wind=" + windProtected
                        + " liquid=" + liquid.isCancelled()
                        + " bucket=" + bucket.isCancelled()
                        + " ignite=" + ignite.isCancelled()
                        + " burn=" + burn.isCancelled()
                        + " fade=" + fade.isCancelled()
                        + " form=" + form.isCancelled()
                        + " sponge=" + sponge.isCancelled()
        );
        return true;
    }

    private boolean view(Player player) {
        PSRegion region = PSRegion.fromLocation(player.getLocation());
        if (region == null) {
            player.sendMessage("PSPROBE FAIL view-region-null");
            return true;
        }

        int tasksBefore = activeParticleTasks();
        boolean commandDispatched = player.performCommand("ps view");
        AtomicInteger attempts = new AtomicInteger();
        player.getScheduler().runAtFixedRate(
                this,
                task -> {
                    int activeTasks = activeParticleTasks();
                    if (activeTasks > tasksBefore) {
                        String result = "PSPROBE VIEW command=" + commandDispatched
                                + " activeTasks=" + activeTasks;
                        getLogger().info(result);
                        player.sendMessage(result);
                        task.cancel();
                        region.deleteRegion(true, player);
                    } else if (attempts.incrementAndGet() >= 40) {
                        String result = "PSPROBE VIEW command=" + commandDispatched
                                + " activeTasks=0";
                        getLogger().warning(result);
                        player.sendMessage(result);
                        task.cancel();
                    }
                },
                () -> getLogger().warning("PSPROBE VIEW retired-before-result"),
                1L,
                1L
        );
        return true;
    }

    private int activeParticleTasks() {
        try {
            var field = ParticlesUtil.class.getDeclaredField("ACTIVE_TASKS");
            field.setAccessible(true);
            return ((Set<?>) field.get(null)).size();
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("Cannot inspect ProtectionStones particle tasks", exception);
        }
    }
}
