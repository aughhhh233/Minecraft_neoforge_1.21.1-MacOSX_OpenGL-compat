package com.macglcompat.core;

import com.macglcompat.natives.NativeBridge;

/**
 * Java-facing handle to one shared IOSurface texture (Phase 1a).
 *
 * <p>Wraps a native bridge handle so callers get a typed, closeable object instead of a
 * raw {@code long}. The underlying surface is aliased by an {@code MTLTexture} (for our
 * Metal compute passes) and, once Phase 1b lands, by an OpenGL texture (for Apple's GL
 * driver) — the same GPU memory seen by both APIs.
 *
 * <p>Not thread-safe per instance; create/close on the render thread.
 */
public final class TextureBridge implements AutoCloseable {

    private long handle;
    private final int width;
    private final int height;

    private TextureBridge(long handle, int width, int height) {
        this.handle = handle;
        this.width = width;
        this.height = height;
    }

    /**
     * @param fmt one of {@link NativeBridge#FMT_RGBA8} / {@code FMT_RGBA16F} / {@code FMT_R32F}
     * @return a bridge, or {@code null} if creation failed (no device, bad size/format).
     */
    public static TextureBridge create(int width, int height, int fmt) {
        long h = NativeBridge.bridgeCreate(width, height, fmt);
        if (h == 0L) return null;
        return new TextureBridge(h, width, height);
    }

    /** Native id&lt;MTLTexture&gt; pointer, for handing to Phase 2 compute encoders. 0 if closed. */
    public long mtlTexturePointer() {
        return handle == 0L ? 0L : NativeBridge.bridgeMtlTextureHandle(handle);
    }

    /** IOSurface global ID, for the Phase 1b GL-side bind. 0 if closed. */
    public int ioSurfaceId() {
        return handle == 0L ? 0 : NativeBridge.bridgeIOSurfaceId(handle);
    }

    public int width()  { return width; }
    public int height() { return height; }
    public boolean isOpen() { return handle != 0L; }

    @Override
    public void close() {
        if (handle != 0L) {
            NativeBridge.bridgeDestroy(handle);
            handle = 0L;
        }
    }
}
