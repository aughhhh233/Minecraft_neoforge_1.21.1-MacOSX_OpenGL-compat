package com.macglcompat.api;

/**
 * A provider of native function-pointer addresses for OpenGL entry points that
 * Apple's OpenGL 4.1 driver does not expose.
 *
 * <p>Addon mods (the "新雅互联-style" external interface) implement this to plug
 * their own Metal-backed implementations of additional GL functions into the
 * interception layer, without depending on MacGLCompat internals.
 *
 * <p>Contract: {@link #functionAddress(String)} must return a pointer (as a
 * {@code long}) to a C function whose ABI exactly matches the requested OpenGL
 * entry point, or {@code 0L} if this handler does not implement it. The returned
 * pointer must remain valid for the lifetime of the process.
 */
@FunctionalInterface
public interface GLFunctionHandler {

    /**
     * @param glFunctionName the LWJGL/GL entry-point name, e.g. {@code "glDispatchCompute"}.
     * @return a native function pointer, or {@code 0L} if unhandled.
     */
    long functionAddress(String glFunctionName);
}
