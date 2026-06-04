// Phase 1 target: glDispatchCompute and the SSBO binding family, backed by
// MTLComputeCommandEncoder + MTLBuffer. Empty in Phase 0 so the build graph and
// symbol layout are in place from the start.
//
// The hard part here is not the dispatch itself but feeding it GLSL: shaderpack
// compute shaders arrive as GLSL at runtime and must go GLSL -> SPIR-V (glslang)
// -> MSL (SPIRV-Cross) -> MTLLibrary. That toolchain integration is the bulk of
// Phase 2.

#import <Metal/Metal.h>
#include "macglcompat.h"

// (intentionally empty in Phase 0)
