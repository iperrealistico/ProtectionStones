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

package dev.espi.protectionstones.utils;

import dev.espi.protectionstones.ProtectionStones;
import dev.espi.protectionstones.scheduler.TaskHandle;
import org.bukkit.Location;
import org.bukkit.Particle;
import org.bukkit.entity.Player;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicReference;

public class ParticlesUtil {
    private static final Set<TaskHandle> ACTIVE_TASKS = ConcurrentHashMap.newKeySet();

    public static void persistRedstoneParticle(Player p, Location l, Particle.DustOptions d, int occ) {
        for (int i = 0; i < occ; i++) {
            AtomicReference<TaskHandle> taskReference = new AtomicReference<>();
            Runnable removeTask = () -> {
                TaskHandle task = taskReference.get();
                if (task != null) {
                    ACTIVE_TASKS.remove(task);
                }
            };
            TaskHandle task = ProtectionStones.getInstance().getTaskScheduler().runEntityDelayed(p, () -> {
                try {
                    if (!p.isOnline()) return;

                    // Stronger "glow marker" burst
                    p.spawnParticle(Particle.DUST, l,
                            2,
                            0.10, 0.15, 0.10,
                            0.0,
                            d
                    );

                    p.spawnParticle(Particle.GLOW, l,
                            2,
                            0.05, 0.08, 0.05,
                            0.0
                    );
                } finally {
                    removeTask.run();
                }

            }, removeTask, Math.max(1, i * 20L));
            taskReference.set(task);
            if (!task.isDone()) {
                ACTIVE_TASKS.add(task);
            }
        }
    }

    public static void cancelAll() {
        for (TaskHandle task : ACTIVE_TASKS.toArray(TaskHandle[]::new)) {
            task.cancel();
        }
        ACTIVE_TASKS.clear();
    }
}
