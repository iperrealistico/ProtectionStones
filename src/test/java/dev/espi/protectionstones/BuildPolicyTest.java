/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package dev.espi.protectionstones;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BuildPolicyTest {

    private static final Path MAIN_JAVA = Path.of("src", "main", "java");

    @Test
    void legacySchedulersAndImplementationInternalsAreForbidden() throws IOException {
        List<String> forbidden = List.of(
                "Bukkit.getScheduler()",
                "getServer().getScheduler()",
                "BukkitRunnable",
                "org.bukkit.craftbukkit",
                "net.minecraft"
        );

        for (Path source : javaSources()) {
            String contents = Files.readString(source);
            for (String token : forbidden) {
                assertFalse(
                        contents.contains(token),
                        () -> source + " must not contain forbidden token " + token
                );
            }
        }
    }

    @Test
    void paperSchedulerTypesStayInsideTheSchedulerBoundary() throws IOException {
        for (Path source : javaSources()) {
            String contents = Files.readString(source);
            if (contents.contains("io.papermc.paper.threadedregions.scheduler")) {
                assertTrue(
                        source.startsWith(MAIN_JAVA.resolve(
                                Path.of("dev", "espi", "protectionstones", "scheduler")
                        )),
                        () -> source + " imports Paper scheduler types outside the boundary"
                );
            }
        }
    }

    @Test
    void pluginMetadataDeclaresTheRequiredCommonRuntimeContract() throws IOException {
        String pluginYaml = Files.readString(Path.of("src", "main", "resources", "plugin.yml"));
        assertTrue(pluginYaml.contains("api-version: 1.21.10"));
        assertTrue(pluginYaml.contains("folia-supported: true"));
        assertTrue(pluginYaml.contains("depend: [WorldGuard, WorldEdit]"));

        String pom = Files.readString(Path.of("pom.xml"));
        assertTrue(pom.contains("<maven.compiler.release>${java.version}</maven.compiler.release>"));
        assertTrue(pom.contains("<java.version>21</java.version>"));
    }

    private static List<Path> javaSources() throws IOException {
        try (Stream<Path> paths = Files.walk(MAIN_JAVA)) {
            return paths.filter(path -> path.toString().endsWith(".java")).toList();
        }
    }
}
