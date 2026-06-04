package com.macglcompat.core;

import java.util.Locale;

/**
 * Decides whether MacGLCompat should activate at all.
 *
 * <p>The whole mod is a no-op on anything that is not macOS-on-ARM. On Windows,
 * Linux, and Intel Macs the OpenGL driver is either modern enough or irrelevant,
 * so we never touch the LWJGL function provider there.
 */
public final class PlatformDetection {

    private PlatformDetection() {}

    private static final String OS = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
    private static final String ARCH = System.getProperty("os.arch", "").toLowerCase(Locale.ROOT);

    public static boolean isMac() {
        return OS.contains("mac") || OS.contains("darwin");
    }

    public static boolean isArm64() {
        return ARCH.equals("aarch64") || ARCH.equals("arm64");
    }

    /**
     * @return true only on Apple Silicon macOS, the one environment this shim targets.
     */
    public static boolean shouldActivate() {
        // A debug flag lets us force-disable on a real Mac while bisecting issues.
        if (Boolean.getBoolean("macglcompat.disable")) {
            return false;
        }
        return isMac() && isArm64();
    }

    public static String describe() {
        return "os=" + OS + " arch=" + ARCH;
    }
}
