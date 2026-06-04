package com.macglcompat;

import com.macglcompat.core.CompatInstaller;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.loading.FMLEnvironment;
import net.neoforged.api.distmarker.Dist;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * MacGLCompat — a macOS OpenGL 4.1 -> Metal compatibility shim.
 *
 * <p>Apple capped its OpenGL driver at 4.1 in 2018. Mods that need compute shaders,
 * SSBOs, or other 4.2+ features (Iris shaderpacks, Voxy LOD, Flywheel's indirect
 * backend) therefore fail on Apple Silicon. This mod intercepts the missing GL entry
 * points at LWJGL's function-provider layer and routes them to a Metal backend.
 *
 * <p>It is a strict no-op on every platform except Apple Silicon macOS.
 */
@Mod(MacGLCompat.MOD_ID)
public final class MacGLCompat {

    public static final String MOD_ID = "macglcompat";
    private static final Logger LOG = LoggerFactory.getLogger("MacGLCompat");

    public MacGLCompat() {
        // Only the client renders; there is nothing to do on a dedicated server.
        if (FMLEnvironment.dist == Dist.CLIENT) {
            LOG.info("MacGLCompat v0 loading.");
            CompatInstaller.install();
        }
    }
}
