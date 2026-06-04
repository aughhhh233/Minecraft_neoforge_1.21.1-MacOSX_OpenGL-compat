package com.macglcompat.natives;

/**
 * JNI surface to the Metal backend (libmacglcompat.dylib).
 *
 * <p>Every method here has a matching {@code Java_com_macglcompat_natives_NativeBridge_*}
 * symbol in native/src/bridge.m. The dylib is loaded by {@link NativeLibraryLoader}
 * before any of these are called.
 *
 * <p>In Phase 0 the native side returns stubs (0 addresses); the real Metal
 * implementations land in Phase 1+.
 */
public final class NativeBridge {

    private NativeBridge() {}

    /**
     * One-time backend init: creates the shared MTLDevice and command queue,
     * and wires up the IOSurface bridge table.
     *
     * @return true on success.
     */
    public static native boolean initialize();

    /**
     * Resolve a native function pointer for an OpenGL entry point that this backend
     * implements (e.g. glDispatchCompute). Returns 0 if the backend does not provide it.
     *
     * <p>The returned pointer targets a C function in the dylib with the exact ABI of
     * the named GL entry point, suitable for handing back to LWJGL as a function address.
     */
    public static native long functionAddress(String glFunctionName);

    /**
     * The GL_VERSION string the shim should report to LWJGL so it attempts to load
     * the 4.6 function set. Backed by native so the spoofed value stays in one place.
     */
    public static native String spoofedVersionString();

    /** Human-readable backend description (Metal device name, feature set), for logs. */
    public static native String backendInfo();
}
