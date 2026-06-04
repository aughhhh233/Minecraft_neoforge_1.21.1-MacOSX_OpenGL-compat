package com.macglcompat.natives;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/**
 * Extracts and loads libmacglcompat.dylib from the mod jar.
 *
 * <p>Layout inside the jar (populated by CI):
 * {@code natives/macos/aarch64/libmacglcompat.dylib}
 *
 * <p>If the dylib is absent (e.g. a Java-only local build, or a non-mac platform),
 * loading is skipped and the caller treats the backend as unavailable — the mod
 * degrades to a no-op rather than crashing.
 */
public final class NativeLibraryLoader {

    private static final Logger LOG = LoggerFactory.getLogger("MacGLCompat/Native");
    private static final String RESOURCE = "/natives/macos/aarch64/libmacglcompat.dylib";

    private static boolean loaded = false;

    private NativeLibraryLoader() {}

    public static synchronized boolean load() {
        if (loaded) return true;
        try (InputStream in = NativeLibraryLoader.class.getResourceAsStream(RESOURCE)) {
            if (in == null) {
                LOG.warn("Native dylib not present in jar ({}). Backend unavailable; MacGLCompat will no-op.", RESOURCE);
                return false;
            }
            Path tmp = Files.createTempFile("libmacglcompat", ".dylib");
            tmp.toFile().deleteOnExit();
            Files.copy(in, tmp, StandardCopyOption.REPLACE_EXISTING);
            System.load(tmp.toAbsolutePath().toString());
            loaded = true;
            LOG.info("Loaded native backend from {}", tmp);
            return true;
        } catch (Throwable t) {
            // Never let a native load failure crash the game — that would defeat the purpose.
            LOG.error("Failed to load native backend; MacGLCompat will no-op.", t);
            return false;
        }
    }

    public static boolean isLoaded() {
        return loaded;
    }
}
