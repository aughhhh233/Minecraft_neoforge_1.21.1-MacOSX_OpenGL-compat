// A2: GLSL compute shader -> SPIR-V (glslang) -> MSL source (SPIRV-Cross).
//
// Pure CPU. No Metal, no GPU — fully unit-testable in CI. Turning the resulting MSL
// into an MTLLibrary and running it is a separate, Mac-only step (Phase 2 runtime).
#ifndef MACGLCOMPAT_TRANSPILER_H
#define MACGLCOMPAT_TRANSPILER_H

#include <string>
#include <vector>
#include <cstdint>

namespace macgl {

struct TranspileResult {
    bool ok = false;
    std::string msl;   // Metal Shading Language source (when ok)
    std::string entry; // MSL kernel entry name (SPIRV-Cross renames main->main0)
    std::string log;   // compiler/linker diagnostics (esp. when !ok)
    std::vector<uint32_t> spirv; // intermediate, for inspection/validation in tests
};

// Translate a GLSL compute shader source string to MSL.
// `glslVersion` is the #version value (e.g. 450); `mslMajor.mslMinor` selects the MSL
// target (default 2.1, broadly available on Apple Silicon).
TranspileResult transpile_compute(const std::string& glslSource,
                                  int glslVersion = 450,
                                  int mslMajor = 2,
                                  int mslMinor = 1);

// Translate many compute shaders in parallel across a thread pool. A shaderpack load
// hands us dozens-to-hundreds of shaders at once; doing them sequentially stalls
// startup, so this fans them out over hardware threads. Each result lines up with its
// input by index. glslang is initialized once up front (thread-safe), and every worker
// uses its own TShader/CompilerMSL, so there is no shared mutable state.
std::vector<TranspileResult> transpile_compute_batch(
        const std::vector<std::string>& glslSources,
        int glslVersion = 450,
        int mslMajor = 2,
        int mslMinor = 1);

} // namespace macgl

#endif // MACGLCOMPAT_TRANSPILER_H
