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
 * <p><b>Timing.</b> The function-provider swap must happen <i>before</i> Minecraft
 * calls {@code GL.createCapabilities()} in {@code com.mojang.blaze3d.platform.Window},
 * otherwise LWJGL has already decided which function sets exist. In Phase 0 we install
 * from the mod constructor, which on NeoForge runs during client bootstrap; whether
 * that reliably precedes capability creation has to be confirmed on a real Mac in
 * Phase 1, and if not, this call moves into a Mixin at the head of the capability-
 * creation method. The Java contract here does not change either way.
 */
public final class CompatInstaller {

    private static final Logger LOG = LoggerFactory.getLogger("MacGLCompat");
    private static boolean installed = false;

    private CompatInstaller() {}

    public static synchronized void install() {
        if (installed) return;
        installed = true;

        if (!PlatformDetection.shouldActivate()) {
            LOG.info("Not Apple Silicon macOS ({}); MacGLCompat inactive.", PlatformDetection.describe());
            return;
        }

        if (!NativeLibraryLoader.load()) {
            LOG.warn("Native backend unavailable; MacGLCompat inactive (game will run on plain OpenGL 4.1).");
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
                // GL not yet created — LWJGL will create the provider later; we install
                // our wrapper once it exists. In practice GL.create() has run by mod
                // construction time, but guard anyway.
                LOG.warn("LWJGL GL function provider not yet available at install time; "
                        + "Phase 1 will relocate the swap into a window-init mixin.");
                return;
            }

            GL.setFunctionProvider(new InterceptingFunctionProvider(real));
            MacGLCompatAPI.markActive(true);
            LOG.info("Interception installed. Reporting GL_VERSION as '{}'.",
                    NativeBridge.spoofedVersionString());
        } catch (Throwable t) {
            // A failure here must never take down the game.
            LOG.error("MacGLCompat install failed; continuing on plain OpenGL 4.1.", t);
        }
    }
}
