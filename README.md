# Minecraft_neoforge_1.21.1-MacOSX_OpenGL-compat

*(internal mod id: `macglcompat`)*

A macOS **OpenGL 4.1 → Metal** compatibility shim for **NeoForge 1.21.1**.

Apple froze its OpenGL driver at 4.1 in 2018. Mods that need compute shaders, SSBOs,
or other OpenGL 4.2+ features therefore break on Apple Silicon — including Iris
shaderpacks, Voxy LOD rendering, and Create/Flywheel's `indirect` backend.

MacGLCompat intercepts the missing GL entry points at LWJGL's *function-provider*
layer and routes them to a Metal backend. It is a strict **no-op on every platform
except Apple Silicon macOS**.

> Status: **Phase 0** — scaffold. The interception architecture, public addon API, CI,
> and a headless Metal self-test are in place. No GL functions are translated yet.

## How it works

When LWJGL builds its `GLCapabilities`, it asks a `FunctionProvider` for each entry
point's address. We wrap that provider:

1. **Override set** — `glGetString`/version queries are rewritten so LWJGL believes the
   driver is 4.6 and actually *attempts* to bind the 4.3/4.6 function sets.
2. **Real driver** — Apple's OpenGL 4.1, for everything it genuinely provides.
3. **Metal backend** — the 4.2+ entry points the driver returned `0` for.
4. **Addon handlers** — last, so addons extend but never shadow the OS.

This resolves *before* the first GL call, because OpenGL errors are silent state, not
exceptions — a "run it and recover on crash" fallback cannot work.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the phase plan.

## Building

CI does everything (`.github/workflows/build.yml`):

- **java-build** (Linux) — compiles the NeoForge mod.
- **native-build** (macOS, Apple Silicon) — builds `libmacglcompat.dylib` and runs a
  headless Metal compute self-test (no Minecraft, no human).
- **package** — bundles the dylib into the final mod jar.

Locally, `gradle build` produces a Java-only jar that loads and cleanly no-ops without
the native library.

## For addon developers

Reference only `com.macglcompat.api`:

```java
if (MacGLCompatAPI.isActive()) {
    MacGLCompatAPI.registerFunctionHandler(name ->
        "glMyEntryPoint".equals(name) ? MyNativeBridge.addressOf(name) : 0L);
}
```

## License

MIT.
