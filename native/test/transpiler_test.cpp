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

    // --- Test 2: image load/store compute (what Iris actually uses, per D1) -
    {
        std::printf("[test] image load/store compute (Iris-style)\n");
        const std::string glsl =
            "#version 450\n"
            "layout(local_size_x = 8, local_size_y = 8) in;\n"
            "layout(rgba8, binding = 0) uniform image2D img;\n"
            "void main() {\n"
            "    ivec2 p = ivec2(gl_GlobalInvocationID.xy);\n"
            "    vec4 c = imageLoad(img, p);\n"
            "    imageStore(img, p, c + vec4(0.1));\n"
            "}\n";
        macgl::TranspileResult r = macgl::transpile_compute(glsl, 450);
        if (!r.ok) {
            std::printf("  FAIL: transpile not ok. log:\n%s\n", r.log.c_str());
            ++g_failures;
        } else {
            check(contains(r.msl, "texture2d"), "MSL maps image2D to a texture2d");
            check(contains(r.msl, "kernel"), "MSL has a kernel function");
        }
    }

    // --- Test 3: shared memory + barrier compute --------------------------
    {
        std::printf("[test] shared memory + barrier compute\n");
        const std::string glsl =
            "#version 450\n"
            "layout(local_size_x = 64) in;\n"
            "shared int tmp[64];\n"
            "layout(std430, binding = 0) buffer B { int data[]; };\n"
            "void main() {\n"
            "    uint l = gl_LocalInvocationID.x;\n"
            "    uint g = gl_GlobalInvocationID.x;\n"
            "    tmp[l] = data[g];\n"
            "    barrier();\n"
            "    data[g] = tmp[l] + 1;\n"
            "}\n";
        macgl::TranspileResult r = macgl::transpile_compute(glsl, 450);
        if (!r.ok) {
            std::printf("  FAIL: transpile not ok. log:\n%s\n", r.log.c_str());
            ++g_failures;
        } else {
            check(contains(r.msl, "threadgroup"), "MSL emits threadgroup (shared) memory");
            check(contains(r.msl, "barrier"), "MSL emits a barrier");
            check(!r.entry.empty(), "entry name captured");
        }
    }

    // --- Test 4: invalid GLSL fails cleanly (no crash, ok=false, log set) --
    {
        std::printf("[test] invalid GLSL fails gracefully\n");
        const std::string bad =
            "#version 450\n"
            "void main() { this is not glsl @@@ }\n";
        macgl::TranspileResult r = macgl::transpile_compute(bad, 450);
        check(!r.ok, "transpile reports failure");
        check(!r.log.empty(), "failure log is populated");
    }

    // --- Test 5: the transpile cache hits on identical input --------------
    {
        std::printf("[test] transpile cache\n");
        macgl::transpile_clear_cache();
        const std::string s =
            "#version 450\n"
            "layout(local_size_x = 32) in;\n"
            "layout(std430, binding = 0) buffer B { int d[]; };\n"
            "void main() { d[gl_GlobalInvocationID.x] += 7; }\n";

        macgl::TranspileResult a = macgl::transpile_compute(s, 450);
        check(a.ok, "first transpile ok");
        check(macgl::transpile_cache_size() == 1, "cache holds 1 after first");
        check(macgl::transpile_cache_hits() == 0, "no hits yet");

        macgl::TranspileResult b = macgl::transpile_compute(s, 450);
        check(b.ok && b.msl == a.msl, "second transpile identical");
        check(macgl::transpile_cache_hits() == 1, "second transpile was a cache hit");
        check(macgl::transpile_cache_size() == 1, "cache still holds 1");

        // A different shader adds an entry; a failure is not cached.
        macgl::transpile_compute(
            "#version 450\nlayout(local_size_x=1) in;\nvoid main(){}\n", 450);
        check(macgl::transpile_cache_size() == 2, "distinct shader adds an entry");
        macgl::transpile_compute("#version 450\n@@@ not glsl\n", 450);
        check(macgl::transpile_cache_size() == 2, "failed transpile is not cached");
    }

    if (g_failures == 0) {
        std::printf("PASS: transpiler tests (%s)\n", "all");
        return 0;
    }
    std::printf("FAILED: %d transpiler checks failed.\n", g_failures);
    return 1;
}
