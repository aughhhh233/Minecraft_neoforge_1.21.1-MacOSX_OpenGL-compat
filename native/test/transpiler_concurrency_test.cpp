// Concurrency test for transpile_compute_batch. Pure CPU — runs on CI.
//
// Thread-safety is proven by determinism: the parallel batch must produce byte-for-byte
// the same MSL as sequential translation for every shader. A data race in glslang or
// SPIRV-Cross would surface as a mismatch, an empty result, or a crash.
//
// Exit codes: 0 = pass, 1 = fail.

#include "transpiler.h"
#include <cstdio>
#include <string>
#include <vector>

static const char* kSSBO =
    "#version 450\n"
    "layout(local_size_x = 64) in;\n"
    "layout(std430, binding = 0) buffer B { int data[]; };\n"
    "void main() { uint i = gl_GlobalInvocationID.x; data[i] = data[i] + 1; }\n";

static const char* kImage =
    "#version 450\n"
    "layout(local_size_x = 8, local_size_y = 8) in;\n"
    "layout(rgba8, binding = 0) uniform image2D img;\n"
    "void main() {\n"
    "  ivec2 p = ivec2(gl_GlobalInvocationID.xy);\n"
    "  imageStore(img, p, imageLoad(img, p) + vec4(0.1));\n"
    "}\n";

static const char* kShared =
    "#version 450\n"
    "layout(local_size_x = 64) in;\n"
    "shared int tmp[64];\n"
    "layout(std430, binding = 0) buffer B { int data[]; };\n"
    "void main() {\n"
    "  uint l = gl_LocalInvocationID.x; uint g = gl_GlobalInvocationID.x;\n"
    "  tmp[l] = data[g]; barrier(); data[g] = tmp[l] + 1;\n"
    "}\n";

int main() {
    // A realistic-ish load: many shaders, mixed kinds (like a shaderpack).
    const int N = 96;
    std::vector<std::string> sources;
    sources.reserve(N);
    for (int i = 0; i < N; ++i) {
        switch (i % 3) {
            case 0: sources.emplace_back(kSSBO);  break;
            case 1: sources.emplace_back(kImage); break;
            default: sources.emplace_back(kShared); break;
        }
    }

    // Sequential baseline.
    std::vector<macgl::TranspileResult> seq;
    seq.reserve(N);
    for (int i = 0; i < N; ++i) seq.push_back(macgl::transpile_compute(sources[i], 450));

    // Parallel batch.
    std::vector<macgl::TranspileResult> par = macgl::transpile_compute_batch(sources, 450);

    if ((int)par.size() != N) {
        std::fprintf(stderr, "FAIL: batch size %zu != %d\n", par.size(), N);
        return 1;
    }

    int fails = 0;
    for (int i = 0; i < N; ++i) {
        if (!par[i].ok) {
            std::fprintf(stderr, "FAIL: par[%d] not ok: %s\n", i, par[i].log.c_str());
            ++fails; continue;
        }
        if (!seq[i].ok) {
            std::fprintf(stderr, "FAIL: seq[%d] not ok (baseline broken): %s\n", i, seq[i].log.c_str());
            ++fails; continue;
        }
        if (par[i].msl != seq[i].msl) {
            std::fprintf(stderr, "FAIL: par[%d] MSL differs from sequential (data race?)\n", i);
            ++fails;
        }
    }

    if (fails == 0) {
        std::printf("PASS: %d shaders transpiled in parallel, all byte-identical to sequential.\n", N);
        return 0;
    }
    std::fprintf(stderr, "FAILED: %d mismatches.\n", fails);
    return 1;
}
