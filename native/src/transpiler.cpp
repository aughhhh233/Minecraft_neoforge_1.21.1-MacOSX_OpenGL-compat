// A2 implementation: GLSL compute -> SPIR-V -> MSL.

#include "transpiler.h"

#include <glslang/Public/ShaderLang.h>
#include <glslang/Public/ResourceLimits.h>
#include <SPIRV/GlslangToSpv.h>
#include <spirv_msl.hpp>

#include <mutex>

namespace macgl {

namespace {
// glslang's process init is global; guard it so concurrent translations are safe.
std::once_flag g_initFlag;
void ensure_glslang() {
    std::call_once(g_initFlag, [] { glslang::InitializeProcess(); });
}
} // namespace

TranspileResult transpile_compute(const std::string& glslSource,
                                  int glslVersion,
                                  int mslMajor,
                                  int mslMinor) {
    TranspileResult r;
    ensure_glslang();

    // --- 1. GLSL -> SPIR-V via glslang -------------------------------------
    glslang::TShader shader(EShLangCompute);
    const char* str = glslSource.c_str();
    shader.setStrings(&str, 1);

    // Vulkan semantics produce SPIR-V that SPIRV-Cross maps cleanly to MSL.
    shader.setEnvInput(glslang::EShSourceGlsl, EShLangCompute,
                       glslang::EShClientVulkan, glslVersion);
    shader.setEnvClient(glslang::EShClientVulkan, glslang::EShTargetVulkan_1_1);
    shader.setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_3);

    const TBuiltInResource* resources = GetDefaultResources();
    const int defaultVersion = glslVersion;
    const EShMessages messages =
        static_cast<EShMessages>(EShMsgSpvRules | EShMsgVulkanRules);

    if (!shader.parse(resources, defaultVersion, false, messages)) {
        r.ok = false;
        r.log = std::string("glslang parse failed:\n") + shader.getInfoLog();
        return r;
    }

    glslang::TProgram program;
    program.addShader(&shader);
    if (!program.link(messages)) {
        r.ok = false;
        r.log = std::string("glslang link failed:\n") + program.getInfoLog();
        return r;
    }

    glslang::TIntermediate* inter = program.getIntermediate(EShLangCompute);
    if (inter == nullptr) {
        r.ok = false;
        r.log = "glslang produced no intermediate for compute stage.";
        return r;
    }
    glslang::GlslangToSpv(*inter, r.spirv);
    if (r.spirv.empty()) {
        r.ok = false;
        r.log = "GlslangToSpv produced empty SPIR-V.";
        return r;
    }

    // --- 2. SPIR-V -> MSL via SPIRV-Cross ----------------------------------
    try {
        spirv_cross::CompilerMSL msl(r.spirv); // copy; keep r.spirv for inspection
        spirv_cross::CompilerMSL::Options opts;
        opts.platform = spirv_cross::CompilerMSL::Options::macOS;
        opts.set_msl_version(static_cast<uint32_t>(mslMajor),
                             static_cast<uint32_t>(mslMinor));
        msl.set_msl_options(opts);

        r.msl = msl.compile();
        r.ok = !r.msl.empty();
        if (!r.ok) r.log = "SPIRV-Cross produced empty MSL.";
    } catch (const std::exception& e) {
        r.ok = false;
        r.log = std::string("SPIRV-Cross failed: ") + e.what();
    }
    return r;
}

} // namespace macgl
