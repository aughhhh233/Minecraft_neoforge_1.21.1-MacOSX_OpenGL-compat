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

    // ---- Phase 1a: IOSurface <-> MTLTexture bridge ----

    /** Format codes — must match MacGLFormat in native/include/macglcompat.h. */
    public static final int FMT_RGBA8 = 0;
    public static final int FMT_RGBA16F = 1;
    public static final int FMT_R32F = 2;

    /** Create an IOSurface-backed MTLTexture. Returns a handle, or 0 on failure. */
    public static native long bridgeCreate(int width, int height, int fmt);

    /** Raw id&lt;MTLTexture&gt; pointer for the handle (for Phase 2 compute), or 0. */
    public static native long bridgeMtlTextureHandle(long handle);

    /** IOSurfaceGetID of the backing surface — used by the Phase 1b GL bind. 0 if invalid. */
    public static native int bridgeIOSurfaceId(long handle);

    public static native int bridgeWidth(long handle);
    public static native int bridgeHeight(long handle);

    /** Release the texture + surface for this handle. No-op if invalid. */
    public static native void bridgeDestroy(long handle);

    /** Number of live bridges (diagnostics/tests). */
    public static native int bridgeLiveCount();

    /**
     * Hand the backend the REAL driver address of a GL function our trampolines must
     * delegate to (e.g. {@code glGetString} for non-version queries). Captured from
     * LWJGL's original provider before the swap.
     */
    public static native void setRealFunction(String glFunctionName, long realAddress);

    /**
     * Translate a GLSL compute shader to MSL via the bundled glslang + SPIRV-Cross
     * toolchain (pure CPU). Returns the MSL source, or {@code null} on failure.
     */
    public static native String transpileComputeToMsl(String glslSource, int glslVersion);
}
