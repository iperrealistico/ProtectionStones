/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package dev.espi.protectionstones.utils;

import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class UUIDCacheTest {

    @Test
    void supportsConcurrentWritersAndCaseInsensitiveLookups() throws Exception {
        int entries = 500;
        List<UUID> uuids = new ArrayList<>(entries);
        List<Callable<Void>> writes = new ArrayList<>(entries);
        for (int i = 0; i < entries; i++) {
            UUID uuid = UUID.randomUUID();
            String name = "CacheUser" + i;
            uuids.add(uuid);
            writes.add(() -> {
                UUIDCache.storeUUIDNamePair(uuid, name);
                return null;
            });
        }

        try (var executor = Executors.newFixedThreadPool(12)) {
            executor.invokeAll(writes);
        }

        for (int i = 0; i < entries; i++) {
            String name = "CacheUser" + i;
            assertEquals(name, UUIDCache.getNameFromUUID(uuids.get(i)));
            assertEquals(uuids.get(i), UUIDCache.getUUIDFromName(name.toUpperCase()));
        }
    }

    @Test
    void removalUpdatesTheRequestedIndex() {
        UUID uuid = UUID.randomUUID();
        String name = "RemovalUser";
        UUIDCache.storeUUIDNamePair(uuid, name);

        UUIDCache.removeUUID(uuid);
        assertFalse(UUIDCache.containsUUID(uuid));
        assertTrue(UUIDCache.containsName(name));

        UUIDCache.removeName(name.toUpperCase());
        assertFalse(UUIDCache.containsName(name));
    }
}
