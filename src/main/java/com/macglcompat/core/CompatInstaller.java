package com.macglcompat.core;

import com.macglcompat.api.MacGLCompatAPI;
import com.macglcompat.natives.NativeBridge;
import com.macglcompat.natives.NativeLibraryLoader;
import org.lwjgl.opengl.GL;
import org.lwjgl.system.FunctionProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Wires the interception layer into LWJGL.
 *
 * <p><b>Phase 0 status.</b> This builds the wrapping {@link InterceptingFunctionProvider}
 * around LWJGL's real provider and proves the backend is alive, but does NOT yet swap it
 * into LWJGL. LWJGL's {@code GL} class exposes {@link GL#getFunctionProvider()} but no
 * public setter, so the actual swap has to go through {@code GL.create(...)} /
 * {@code GLCapabilities} reconstruction, whose correct sequencing must be validated on a
 * real Apple-Silicon Mac (Phase 1). Baking in a guessed mechanism here would be wrong.
 *
 * <p><b>Timing.</b> The swap must land before Minecraft calls {@code GL.createCapabilities()}
 * in {@code com.mojang.blaze3d.platform.Window}. Phase 1 decides between a window-init
 * mixin and a provider rebuild, once observable on hardware.
 */
public final class CompatInstaller {

    private static final Logger LOG = LoggerFactory.getLogger("MacGLCompat");
    private static boolean installed = false;

    /** The wrapper, retained for Phase 1 to install into LWJGL. */
    private static volatile InterceptingFunctionProvider provider;

    private CompatInstaller() {}

    public static InterceptingFunctionProvider provider() {
        return provider;
    }

    public static synchronized void install() {
        if (installed) return;
        installed = true;

        if (!PlatformDetection.shouldActivate()) {
            LOG.info("Not Apple Silicon macOS ({}); MacGLCompat inactive.", PlatformDetection.describe());
            return;
        }

        if (!NativeLibraryLoader.load()) {
            LOG.warn("Native backend unavailable; MacGLCompat inactive (game runs on plain OpenGL 4.1).");
            return;
        }

        try {
            if (!NativeBridge.initialize()) {
                LOG.error("Metal backend failed to initialize; staying on plain OpenGL 4.1.");
                return;
            }
            LOG.info("Metal backend: {}", NativeBridge.backendInfo());

            FunctionProvider real = GL.getFunctionProvider();
            if (real == null) {
                LOG.warn("LWJGL GL provider not available yet at install time; "
                        + "Phase 1 will hook window-init to capture it.");
                return;
            }

            provider = new InterceptingFunctionProvider(real);
            MacGLCompatAPI.markActive(true);
            LOG.info("Interception provider built (will report GL_VERSION '{}'). "
                    + "Phase 1: swap into LWJGL before createCapabilities.",
                    NativeBridge.spoofedVersionString());
        } catch (Throwable t) {
            // A failure here must never take down the game.
            LOG.error("MacGLCompat install failed; continuing on plain OpenGL 4.1.", t);
        }
    }
}
