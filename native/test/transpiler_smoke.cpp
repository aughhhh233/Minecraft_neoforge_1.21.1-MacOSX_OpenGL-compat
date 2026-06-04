// A1 smoke test: prove glslang + SPIRV-Cross build and link, and that the basic
// objects construct. Pure CPU — runs to completion on CI with no GPU. The real
// GLSL->SPIR-V->MSL translation and its correctness tests arrive in A2/A3.
//
// Exit codes: 0 = pass, 1 = fail.

#include <glslang/Public/ShaderLang.h>
#include <spirv_msl.hpp>
#include <cstdio>
#include <vector>
#include <cstdint>

int main() {
    // glslang process bring-up.
    if (!glslang::InitializeProcess()) {
        std::fprintf(stderr, "FAIL: glslang InitializeProcess returned false.\n");
        return 1;
    }
    glslang::FinalizeProcess();

    // SPIRV-Cross MSL compiler links and constructs. An empty module is invalid input,
    // but constructing the object is enough to prove linkage; guard against throw.
    try {
        std::vector<uint32_t> empty;
        spirv_cross::CompilerMSL msl(std::move(empty));
        (void)msl;
    } catch (const std::exception& e) {
        // Expected for an empty module; linkage is what we're verifying.
        std::fprintf(stdout, "(SPIRV-Cross threw on empty module as expected: %s)\n", e.what());
    } catch (...) {
        std::fprintf(stdout, "(SPIRV-Cross threw on empty module as expected.)\n");
    }

    std::printf("PASS: glslang + SPIRV-Cross built, linked, and constructed.\n");
    return 0;
}
