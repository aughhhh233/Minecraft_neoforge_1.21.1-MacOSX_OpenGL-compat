# D2 — LWJGL function-provider injection mechanism

Verified against the actual `org/lwjgl/opengl/GL.class` in LWJGL **3.3.3** (the version
Minecraft 1.21.1 bundles), by inspecting the class's method/field descriptors.

## What GL exposes (3.3.3)
- `create()` and `create(SharedLibrary)` — **no `create(FunctionProvider)` is public**;
  the `(FunctionProvider)V` overload exists but is private.
- `getFunctionProvider() : FunctionProvider` — getter only.
- **No `setFunctionProvider`.** (Confirmed earlier by a Phase 0 compile error too.)
- `createCapabilities()`, `createCapabilities(boolean)`, `createCapabilities(IntFunction<PointerBuffer>)`
  — all build a `GLCapabilities` from the private static field `functionProvider`.
- Private static field name: **`functionProvider`**.

## Mechanism we will use
Since there is no setter, reflectively replace the private static field:

```java
Field f = GL.class.getDeclaredField("functionProvider");
f.setAccessible(true);
FunctionProvider real = (FunctionProvider) f.get(null);
f.set(null, new InterceptingFunctionProvider(real));
```

Implemented as `CompatInstaller.swapProviderField(...)`. After the swap, the next
`GL.createCapabilities()` resolves every entry point through our wrapper, so:
- our `glGetString` override reports 4.6 → LWJGL attempts the 4.3/4.6 function sets,
- the 4.2+ entry points resolve to the Metal backend instead of returning 0.

## Timing — the part that needs a Mac
The swap must land **before** `GL.createCapabilities()`. Call-site, found by scanning
`client-1.21.1-official.jar`:

> **`com.mojang.blaze3d.platform.Window`** — its constructor calls `GL.createCapabilities()`.
> (The other hit, `com.mojang.blaze3d.audio.Library`, is OpenAL `ALC.createCapabilities` — unrelated.)

Whether NeoForge mod-constructor time reliably precedes Window construction is a runtime
ordering question only observable on hardware. Plan:
1. Phase 2 adds a **Mixin** at the head of `Window`'s constructor (before the
   `createCapabilities` call) that invokes `swapProviderField`.
2. On a real Mac, confirm the swap lands first and that LWJGL then reports the 4.6 set.

For now `CompatInstaller.install()` also calls the swap best-effort from the mod
constructor; if capabilities already exist by then, the swapped provider is simply
unused (no harm), and the mixin becomes the authoritative path.

## Module-access caveat
`GL.class.getDeclaredField(...).setAccessible(true)` on a field in the `org.lwjgl`
module may need `--add-opens`. NeoForge's module setup generally allows mod reflection
into LWJGL, but if `setAccessible` throws `InaccessibleObjectException` on a Mac, the
fix is a `--add-opens org.lwjgl/org.lwjgl.opengl=ALL-UNNAMED` JVM arg (documented for
users) or doing the swap from within the same module via the mixin. To verify on Mac.
