/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package dev.espi.protectionstones.scheduler;

import io.papermc.paper.threadedregions.scheduler.ScheduledTask;
import org.bukkit.Location;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Entity;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Function;

/**
 * Central scheduling boundary shared by Purpur and Folia.
 */
public final class PlatformScheduler {
    private static final TaskHandle COMPLETED_TASK = new TaskHandle() {
        @Override
        public void cancel() {
        }

        @Override
        public boolean isDone() {
            return true;
        }
    };

    private final JavaPlugin plugin;
    private final Set<TrackedTask> tasks = ConcurrentHashMap.newKeySet();
    private final AtomicBoolean shuttingDown = new AtomicBoolean();

    public PlatformScheduler(JavaPlugin plugin) {
        this.plugin = plugin;
    }

    public TaskHandle runGlobal(Runnable action) {
        return schedule(callback -> plugin.getServer().getGlobalRegionScheduler().run(plugin, callback), action, false);
    }

    public TaskHandle runGlobalDelayed(Runnable action, long delayTicks) {
        return schedule(callback -> plugin.getServer().getGlobalRegionScheduler()
                .runDelayed(plugin, callback, delayTicks), action, false);
    }

    public TaskHandle runGlobalAtFixedRate(Runnable action, long initialDelayTicks, long periodTicks) {
        return schedule(callback -> plugin.getServer().getGlobalRegionScheduler()
                .runAtFixedRate(plugin, callback, initialDelayTicks, periodTicks), action, true);
    }

    public TaskHandle runRegion(Location location, Runnable action) {
        Location target = location.clone();
        return schedule(callback -> plugin.getServer().getRegionScheduler().run(plugin, target, callback), action, false);
    }

    public TaskHandle runRegionDelayed(Location location, Runnable action, long delayTicks) {
        Location target = location.clone();
        return schedule(callback -> plugin.getServer().getRegionScheduler()
                .runDelayed(plugin, target, callback, delayTicks), action, false);
    }

    public TaskHandle runEntity(Entity entity, Runnable action) {
        return scheduleEntity(
                (callback, retired) -> entity.getScheduler().run(plugin, callback, retired),
                action,
                null,
                false
        );
    }

    public TaskHandle runEntityDelayed(Entity entity, Runnable action, Runnable retired, long delayTicks) {
        return scheduleEntity(
                (callback, trackedRetired) -> entity.getScheduler()
                        .runDelayed(plugin, callback, trackedRetired, delayTicks),
                action,
                retired,
                false
        );
    }

    public TaskHandle runEntityAtFixedRate(
            Entity entity,
            Runnable action,
            Runnable retired,
            long initialDelayTicks,
            long periodTicks
    ) {
        return scheduleEntity(
                (callback, trackedRetired) -> entity.getScheduler()
                        .runAtFixedRate(plugin, callback, trackedRetired, initialDelayTicks, periodTicks),
                action,
                retired,
                true
        );
    }

    public TaskHandle runCommandSender(CommandSender sender, Runnable action) {
        if (sender instanceof Player player) {
            return runEntity(player, action);
        }
        return runGlobal(action);
    }

    public TaskHandle runAsync(Runnable action) {
        return schedule(callback -> plugin.getServer().getAsyncScheduler().runNow(plugin, callback), action, false);
    }

    public TaskHandle runAsyncDelayed(Runnable action, long delay, TimeUnit unit) {
        return schedule(callback -> plugin.getServer().getAsyncScheduler()
                .runDelayed(plugin, callback, delay, unit), action, false);
    }

    public TaskHandle runAsyncAtFixedRate(
            Runnable action,
            long initialDelay,
            long period,
            TimeUnit unit
    ) {
        return schedule(callback -> plugin.getServer().getAsyncScheduler()
                .runAtFixedRate(plugin, callback, initialDelay, period, unit), action, true);
    }

    public void shutdown() {
        if (!shuttingDown.compareAndSet(false, true)) {
            return;
        }

        for (TrackedTask task : tasks.toArray(TrackedTask[]::new)) {
            task.cancel();
        }
        tasks.clear();
    }

    private TaskHandle schedule(
            Function<java.util.function.Consumer<ScheduledTask>, ScheduledTask> scheduler,
            Runnable action,
            boolean repeating
    ) {
        if (shuttingDown.get()) {
            return COMPLETED_TASK;
        }

        TrackedTask tracked = new TrackedTask(action, repeating);
        tasks.add(tracked);
        try {
            tracked.attach(scheduler.apply(tracked::execute));
            return tracked;
        } catch (RuntimeException exception) {
            tracked.cancel();
            throw exception;
        }
    }

    private TaskHandle scheduleEntity(
            EntitySchedule scheduler,
            Runnable action,
            Runnable retired,
            boolean repeating
    ) {
        if (shuttingDown.get()) {
            return COMPLETED_TASK;
        }

        TrackedTask tracked = new TrackedTask(action, repeating);
        tasks.add(tracked);
        Runnable trackedRetired = () -> {
            try {
                if (retired != null) {
                    retired.run();
                }
            } finally {
                tracked.complete();
            }
        };

        try {
            tracked.attach(scheduler.schedule(tracked::execute, trackedRetired));
            return tracked;
        } catch (RuntimeException exception) {
            tracked.cancel();
            throw exception;
        }
    }

    @FunctionalInterface
    private interface EntitySchedule {
        ScheduledTask schedule(
                java.util.function.Consumer<ScheduledTask> callback,
                Runnable retired
        );
    }

    private final class TrackedTask implements TaskHandle {
        private final Runnable action;
        private final boolean repeating;
        private final AtomicBoolean done = new AtomicBoolean();
        private final AtomicReference<ScheduledTask> scheduledTask = new AtomicReference<>();

        private TrackedTask(Runnable action, boolean repeating) {
            this.action = action;
            this.repeating = repeating;
        }

        private void attach(ScheduledTask task) {
            if (task == null) {
                complete();
                return;
            }
            scheduledTask.set(task);
            if (done.get()) {
                task.cancel();
            }
        }

        private void execute(ScheduledTask task) {
            if (done.get() || shuttingDown.get()) {
                cancel();
                return;
            }

            try {
                action.run();
                if (!repeating) {
                    complete();
                }
            } catch (Throwable throwable) {
                plugin.getLogger().severe("Scheduled ProtectionStones task failed: " + throwable.getMessage());
                throwable.printStackTrace();
                cancel();
            }
        }

        private void complete() {
            if (done.compareAndSet(false, true)) {
                tasks.remove(this);
            }
        }

        @Override
        public void cancel() {
            if (!done.compareAndSet(false, true)) {
                return;
            }

            ScheduledTask task = scheduledTask.get();
            if (task != null) {
                task.cancel();
            }
            tasks.remove(this);
        }

        @Override
        public boolean isDone() {
            return done.get();
        }
    }
}
