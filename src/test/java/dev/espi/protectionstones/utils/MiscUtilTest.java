/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package dev.espi.protectionstones.utils;

import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MiscUtilTest {

    @Test
    void parsesCompoundRentPeriods() {
        assertEquals(
                Duration.ofDays(16).plusHours(4).plusMinutes(5).plusSeconds(6),
                MiscUtil.parseRentPeriod("2w 2d 4h 5m 6s")
        );
    }

    @Test
    void rejectsMalformedRentPeriods() {
        assertThrows(NumberFormatException.class, () -> MiscUtil.parseRentPeriod("2days"));
    }

    @Test
    void selectsHighestNumericPermission() {
        assertEquals(
                25,
                MiscUtil.getPermissionNumber(
                        List.of(
                                "protectionstones.limit.5",
                                "protectionstones.limit.25",
                                "protectionstones.limit.invalid"
                        ),
                        "protectionstones.limit.",
                        3
                )
        );
        assertEquals(
                3,
                MiscUtil.getPermissionNumber(
                        List.of("protectionstones.other.9"),
                        "protectionstones.limit.",
                        3
                )
        );
    }

    @Test
    void validatesIntegerBounds() {
        assertTrue(MiscUtil.isValidInteger("2147483647"));
        assertTrue(MiscUtil.isValidInteger("-42"));
        assertFalse(MiscUtil.isValidInteger("2147483648"));
        assertFalse(MiscUtil.isValidInteger("1.5"));
        assertFalse(MiscUtil.isValidInteger(null));
    }
}
