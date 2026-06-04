# Roadmap

Target hardware: **Apple Silicon (M1+) macOS**, still-supported releases.
Test shaderpack baseline: **Solas Shader** (compute-heavy) — config-tunable.

## Phase 0 — scaffold ✅ (this commit)
- NeoForge mod project + ModDevGradle build.
- LWJGL `FunctionProvider` interception layer (`com.macglcompat.core`).
- Public addon API (`com.macglcompat.api`).
- JNI bridge + native dylib skeleton with real Metal device bring-up.
- CI: Java build (Linux), dylib build + **headless Metal compute self-test** (Apple
  Silicon runner), packaging.
- **Verifiable now, no Mac:** Java compiles; dylib compiles; headless compute dispatch
  reads back correct results on the CI runner.

## Phase 1 — IOSurface resource bridge
**1a (done, CI-compiled):** Metal half — `IOSurface ↔ MTLTexture` mapping table
(`native/src/iosurface.m`, `core/TextureBridge.java`). Headless test verifies the
surface and texture share GPU memory (skips without a device). No GL context needed.

**1b (deferred, needs a real Mac):** GL half — bind the same IOSurface to an OpenGL
texture via `CGLTexImageIOSurface2D`. Requires a live GL context (in-game only), so it
is untestable in CI and risky to write blind; left until hardware is in the loop.
Also: relocate the provider swap into a window-init mixin if mod-constructor timing is
too late.

## Phase 2 — Iris compute shaders  *(primary goal)*
- **A1 done (CI):** glslang + SPIRV-Cross vendored via FetchContent; build/link/run on CI.
- **A2 done (CI):** `transpile_compute()` — GLSL compute → SPIR-V (glslang) → MSL
  (SPIRV-Cross), in `native/src/transpiler.cpp`. Pure CPU.
- **A3 done (CI):** `transpiler_test` asserts MSL output for a real SSBO compute shader
  and that bad GLSL fails cleanly. Runs on CI without a GPU.
- **B (next, no Mac):** function-pointer trampolines — `glDispatchCompute` →
  `MTLComputeCommandEncoder`, image load/store, DSA buffer/texture creation, the
  `glGetString` version spoof. Author + compile-check.
- **Mac-only remainder:** MSL → `MTLLibrary` compile, real dispatch, and getting
  **Solas Shader** to actually render. Plus the Window mixin timing (D2).
- Note (from D1): Iris needs image load/store + compute + DSA, **not** SSBO remapping.

## Phase 3 — Voxy LOD
- Persistent mapped buffers + Voxy's compute usage.

## Phase 4 — Flywheel `indirect`
- `glMultiDrawArraysIndirectCount` → Metal indirect command buffers (Create perf).

## Final — full-pack soak
- Run the complete Createpedia pack; chase per-mod interaction issues. Deferred until
  the feature phases above are stable.

## Known non-goals / out of scope
- `super_resolution`: its own C++ native has no macOS build — not an OpenGL-version
  problem, nothing this shim can do.
- `sable`: crashes from a JNI path-resolution bug (upstream PR #1016), unrelated to GL.
- `IMBlocker`: Windows-only IME code; breaks keyboard on macOS — unrelated to GL.
