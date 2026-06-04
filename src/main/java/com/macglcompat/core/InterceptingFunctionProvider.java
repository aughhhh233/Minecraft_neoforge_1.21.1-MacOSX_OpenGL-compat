package com.macglcompat.core;

import com.macglcompat.api.MacGLCompatAPI;
import com.macglcompat.natives.NativeBridge;
import org.lwjgl.system.FunctionProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Set;

/**
 * The core trick. Wraps LWJGL's real OpenGL {@link FunctionProvider} and decides,
 * per function, where its address comes from.
 *
 * <h2>Why a function provider and not a try/catch fallback</h2>
 * OpenGL errors are silent state, not exceptions, and the GPU pipeline is async, so
 * "let it run and recover on crash" is not viable — by the time anything throws, the
 * GL state machine is already corrupt. Instead we resolve every entry point up front:
 * functions Apple's 4.1 driver lacks are bound to our Metal backend before the first
 * call ever happens.
 *
 * <h2>Resolution order</h2>
 * <ol>
 *   <li><b>Override set</b> — functions we always replace even though 4.1 has them.
 *       Currently just version queries, so LWJGL believes it is talking to a 4.6 driver
 *       and therefore attempts to load the 4.3/4.6 function sets at all.</li>
 *   <li><b>Real driver</b> — Apple's OpenGL 4.1, for everything it genuinely provides.</li>
 *   <li><b>Our Metal backend</b> — for 4.2+ entry points the driver returned 0 for.</li>
 *   <li><b>Addon handlers</b> — last, so addons extend but never shadow the OS.</li>
 * </ol>
 */
public final class InterceptingFunctionProvider implements FunctionProvider {

    private static final Logger LOG = LoggerFactory.getLogger("MacGLCompat/Provider");

    /**
     * Functions we override unconditionally. {@code glGetString} is here so we can
     * rewrite GL_VERSION; without that, LWJGL parses Apple's "4.1" and never even
     * tries to bind the 4.3+ function pointers, no matter what we offer.
     */
    private static final Set<String> OVERRIDE = Set.of(
            "glGetString",
            "glGetStringi",
            "glGetIntegerv"
    );

    private final FunctionProvider delegate;

    public InterceptingFunctionProvider(FunctionProvider delegate) {
        this.delegate = delegate;
    }

    @Override
    public long getFunctionAddress(CharSequence functionName) {
        String name = functionName.toString();

        // (1) Unconditional overrides — version spoofing lives here.
        if (OVERRIDE.contains(name)) {
            long a = NativeBridge.functionAddress(name);
            if (a != 0L) return a;
            // If the backend doesn't override it after all, fall through to the driver.
        }

        // (2) The real Apple OpenGL 4.1 driver.
        long real = delegate.getFunctionAddress(functionName);
        if (real != 0L) return real;

        // (3) Our Metal backend fills the 4.2+ gaps.
        long metal = NativeBridge.functionAddress(name);
        if (metal != 0L) {
            if (LOG.isDebugEnabled()) LOG.debug("Bound {} -> Metal backend", name);
            return metal;
        }

        // (4) Addon-supplied handlers.
        long addon = MacGLCompatAPI.queryAddons(name);
        if (addon != 0L) {
            if (LOG.isDebugEnabled()) LOG.debug("Bound {} -> addon handler", name);
            return addon;
        }

        // Genuinely unavailable. Returning 0 leaves the capability flag false, same as
        // stock behaviour — callers that feature-detect will simply skip it.
        return 0L;
    }
}
