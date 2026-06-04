// A3: unit tests for the GLSL->SPIR-V->MSL transpiler. Pure CPU — runs on CI.
//
// Exit codes: 0 = all pass, 1 = a failure.

#include "transpiler.h"
#include <cstdio>
#include <string>

static int g_failures = 0;

static void check(bool cond, const char* what) {
    if (cond) {
        std::printf("  ok: %s\n", what);
    } else {
        std::printf("  FAIL: %s\n", what);
        ++g_failures;
    }
}

static bool contains(const std::string& hay, const char* needle) {
    return hay.find(needle) != std::string::npos;
}

int main() {
    // --- Test 1: a valid SSBO compute shader translates to MSL -------------
    {
        std::printf("[test] SSBO add-one compute\n");
        const std::string glsl =
            "#version 450\n"
            "layout(local_size_x = 64) in;\n"
            "layout(std430, binding = 0) buffer Buf { int data[]; };\n"
            "void main() { data[gl_GlobalInvocationID.x] = data[gl_GlobalInvocationID.x] + 1; }\n";

        macgl::TranspileResult r = macgl::transpile_compute(glsl, 450);
        if (!r.ok) {
            std::printf("  FAIL: transpile not ok. log:\n%s\n", r.log.c_str());
            ++g_failures;
        } else {
            check(!r.spirv.empty(), "SPIR-V is non-empty");
            check(!r.spirv.empty() && r.spirv[0] == 0x07230203u, "SPIR-V magic word present");
            check(contains(r.msl, "metal_stdlib"), "MSL includes metal_stdlib");
            check(contains(r.msl, "kernel"), "MSL has a kernel function");
            check(contains(r.msl, "gl_GlobalInvocationID") ||
                  contains(r.msl, "thread_position_in_grid"),
                  "MSL references the global invocation id");
        }
    }

    // --- Test 2: invalid GLSL fails cleanly (no crash, ok=false, log set) --
    {
        std::printf("[test] invalid GLSL fails gracefully\n");
        const std::string bad =
            "#version 450\n"
            "void main() { this is not glsl @@@ }\n";
        macgl::TranspileResult r = macgl::transpile_compute(bad, 450);
        check(!r.ok, "transpile reports failure");
        check(!r.log.empty(), "failure log is populated");
    }

    if (g_failures == 0) {
        std::printf("PASS: transpiler tests (%s)\n", "all");
        return 0;
    }
    std::printf("FAILED: %d transpiler checks failed.\n", g_failures);
    return 1;
}
