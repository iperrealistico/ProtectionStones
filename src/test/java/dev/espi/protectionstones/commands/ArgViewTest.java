/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package dev.espi.protectionstones.commands;

import org.bukkit.Color;
import org.bukkit.Particle;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ArgViewTest {

    @Test
    void purpleParticleSizeFitsTheCommonPaperApiRange() {
        assertTrue(ArgView.PURPLE_PARTICLE_SIZE >= 0.01F);
        assertTrue(ArgView.PURPLE_PARTICLE_SIZE <= 4.0F);
        assertDoesNotThrow(() -> new Particle.DustOptions(
                Color.fromRGB(255, 0, 255),
                ArgView.PURPLE_PARTICLE_SIZE
        ));
    }
}
