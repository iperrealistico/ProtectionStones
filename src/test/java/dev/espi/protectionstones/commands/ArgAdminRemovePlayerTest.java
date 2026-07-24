/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package dev.espi.protectionstones.commands;

import dev.espi.protectionstones.utils.UUIDCache;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class ArgAdminRemovePlayerTest {

    @Test
    void resolvesCachedPlayerNameCaseInsensitively() {
        UUID uuid = UUID.randomUUID();
        UUIDCache.storeUUIDNamePair(uuid, "KnownPlayer");

        assertEquals(uuid, ArgAdminRemovePlayer.resolveTargetUuid("knownplayer"));
    }

    @Test
    void resolvesLiteralUuidWithoutCachedPlayerData() {
        UUID uuid = UUID.randomUUID();

        assertEquals(uuid, ArgAdminRemovePlayer.resolveTargetUuid(uuid.toString()));
    }

    @Test
    void rejectsUnknownPlayerName() {
        assertNull(ArgAdminRemovePlayer.resolveTargetUuid("player-who-is-not-cached"));
    }
}
