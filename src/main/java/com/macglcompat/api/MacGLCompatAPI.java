package com.macglcompat.api;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Public, stable entry point for addon mods.
 *
 * <p>This is the only class addon developers should reference. Everything under
 * {@code com.macglcompat.core} and {@code com.macglcompat.natives} is internal and
 * may change between versions.
 *
 * <h2>Usage from an addon mod</h2>
 * <pre>{@code
 * if (MacGLCompatAPI.isActive()) {
 *     MacGLCompatAPI.registerFunctionHandler(name -> switch (name) {
 *         case "glMyCustomEntryPoint" -> MyNativeBridge.addressOf(name);
 *         default -> 0L;
 *     });
 * }
 * }</pre>
 *
 * <p>Resolution order when LWJGL asks for a function pointer:
 * <ol>
 *   <li>MacGLCompat's own override table (version spoofing + the core compute/SSBO set)</li>
 *   <li>Apple's real OpenGL 4.1 driver (the delegate)</li>
 *   <li>Registered addon handlers, in registration order, until one returns non-zero</li>
 * </ol>
 */
public final class MacGLCompatAPI {

    private MacGLCompatAPI() {}

    private static volatile boolean active = false;
    private static final List<GLFunctionHandler> ADDON_HANDLERS = new CopyOnWriteArrayList<>();

    /** Current API version, so addons can feature-detect. */
    public static final int API_VERSION = 1;

    /**
     * @return true if the interception layer is installed and running
     *         (i.e. we are on Apple Silicon macOS and the native dylib loaded).
     */
    public static boolean isActive() {
        return active;
    }

    /**
     * Register an addon-supplied source of native function addresses. Handlers are
     * consulted only after the core override table and the real driver, so an addon
     * cannot accidentally shadow a function the OS already provides correctly.
     */
    public static void registerFunctionHandler(GLFunctionHandler handler) {
        if (handler == null) throw new IllegalArgumentException("handler must not be null");
        ADDON_HANDLERS.add(handler);
    }

    // ---- internal plumbing, called by core ----

    /** @hidden internal use only */
    public static void markActive(boolean value) {
        active = value;
    }

    /** @hidden internal use only — queried by InterceptingFunctionProvider */
    public static long queryAddons(String glFunctionName) {
        for (GLFunctionHandler h : ADDON_HANDLERS) {
            long addr = h.functionAddress(glFunctionName);
            if (addr != 0L) return addr;
        }
        return 0L;
    }
}
