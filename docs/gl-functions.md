# D1 — GL 4.2+ functions each target actually calls

Method: scanned the mod jars' class bytecode (constant-pool references to
`org/lwjgl/opengl/GLNN` classes + `gl*` method names) from the Createpedia pack.
This is evidence from the shipped bytecode, not guesswork.

macOS provides OpenGL **4.1**. Everything below is what the shim must supply.

## Iris 1.8.12 — 10 functions
Referenced GL classes: GL42, GL43, GL45, GL46 (+ ARBDirectStateAccess,
ARBShaderImageLoadStore, ARBClearTexture, KHRDebug).

| Feature | GL ver | Functions |
|---|---|---|
| Compute | 4.3 | `glDispatchCompute`, `glDispatchComputeIndirect` |
| Image load/store | 4.2 | `glBindImageTexture`, `glMemoryBarrier` |
| Immutable buffer | 4.4 | `glBufferStorage` |
| DSA | 4.5 | `glCreateBuffers`, `glNamedBufferData`, `glCreateTextures`, `glCreateFramebuffers`, `glNamedFramebufferTexture` |

**Note:** No SSBO binding calls (`glShaderStorageBlockBinding` absent). Iris uses
image load/store + compute, not SSBO remapping. Narrows Phase 2 scope.

## Flywheel 1.0.6 (`indirect` backend) — 23 functions
Referenced GL classes: GL42, GL43, GL44, GL45, GL46 (+ ARBInstancedArrays for the
`instancing` fallback, which already works on 4.1).

| Feature | GL ver | Functions |
|---|---|---|
| Compute | 4.3 | `glDispatchCompute`, `glMemoryBarrier`, `glBindImageTexture` |
| Multidraw indirect | 4.3 | `glMultiDrawElementsIndirect` |
| Vertex attrib binding | 4.3 | `glVertexAttribFormat`, `glVertexAttribIFormat`, `glVertexAttribBinding`, `glBindVertexBuffer` |
| Multi-bind | 4.4 | `glBindBuffersRange` |
| DSA | 4.5 | `glCreateBuffers`, `glCreateTextures`, `glCreateVertexArrays`, `glNamedBufferData`, `glNamedBufferStorage`, `glNamedBufferSubData`, `glMapNamedBuffer`, `glMapNamedBufferRange`, `glTextureStorage2D`, `glCreateFramebuffers`, `glNamedFramebufferTexture`, `glVertexArrayVertexBuffer`, `glVertexArrayAttribFormat`, `glVertexArrayAttribBinding` |

**Note:** indirect backend uses `glMultiDrawElementsIndirect` (4.3), **not** the 4.6
`...IndirectCount` variant. Lower bar than assumed.

## Voxy
`voxy_server_lod-1.1.4` has **no GL calls** (server-side data feeder). The GL-4.6
client renderer is not present in the Createpedia pack; analyzing it needs its own
client jar separately. Deferred.

## The shared core (implement once, unlock Iris + Flywheel)
Both depend on the same foundation:
- **Compute (4.3):** `glDispatchCompute` (+ `glMemoryBarrier`, `glBindImageTexture`)
- **DSA object creation (4.5):** `glCreateBuffers` / `glNamedBuffer*` / `glCreateTextures` / `glCreateFramebuffers`
- **Image load/store (4.2)** + memory barriers

Implementing this shared set is the highest-leverage work. SSBO-specific entry points
are not required by either; SSBO usage, if any, surfaces inside the compute GLSL and is
handled by the Phase 2 transpiler, not by extra GL entry points.

Divergent extras: Flywheel additionally needs vertex-attrib-binding (4.3),
`glMultiDrawElementsIndirect` (4.3), and the named vertex-array DSA calls.
