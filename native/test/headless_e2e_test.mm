// The crown-jewel end-to-end test: GLSL compute -> (transpiler, CPU) MSL ->
// (compute.m, Metal) pipeline -> dispatch -> readback. Proves the entire chain minus
// GL-state tracking. Obj-C++ (.mm) to bridge the C++ transpiler and Obj-C Metal code.
//
// Needs a Metal device; exits 2 (skip) without one. 0 = pass, 1 = fail.
//
// This is THE test a GPU-capable CI (D3) or a real Mac must run green to prove Phase 2.

#import <Foundation/Foundation.h>
#include "macglcompat.h"
#include "compute.h"
#include "transpiler.h"
#include <cstdio>
#include <string>

int main() {
    if (!macgl_initialize()) { std::fprintf(stderr, "SKIP: no Metal device.\n"); return 2; }

    // A GLSL compute shader that increments each SSBO element.
    const std::string glsl =
        "#version 450\n"
        "layout(local_size_x = 64) in;\n"
        "layout(std430, binding = 0) buffer Buf { int data[]; };\n"
        "void main() { uint i = gl_GlobalInvocationID.x; data[i] = data[i] + 1; }\n";

    macgl::TranspileResult tr = macgl::transpile_compute(glsl, 450);
    if (!tr.ok) { std::fprintf(stderr, "FAIL: transpile: %s\n", tr.log.c_str()); return 1; }
    std::printf("entry='%s'\n", tr.entry.c_str());

    const char* entry = tr.entry.empty() ? "main0" : tr.entry.c_str();
    char err[256] = {0};
    uint64_t pipe = macgl_compute_build_pipeline(tr.msl.c_str(), entry, err, sizeof(err));
    if (pipe == 0) {
        std::fprintf(stderr, "FAIL: build_pipeline (entry=%s): %s\nMSL:\n%s\n",
                     entry, err, tr.msl.c_str());
        return 1;
    }

    const int N = 256;
    int data[N];
    for (int i = 0; i < N; i++) data[i] = i;
    if (!macgl_compute_run_single_buffer(pipe, data, (int)sizeof(data), N)) {
        std::fprintf(stderr, "FAIL: dispatch.\n");
        return 1;
    }
    for (int i = 0; i < N; i++) {
        if (data[i] != i + 1) {
            std::fprintf(stderr, "FAIL: data[%d]=%d expected %d\n", i, data[i], i + 1);
            return 1;
        }
    }
    macgl_compute_destroy_pipeline(pipe);

    std::printf("PASS: GLSL -> MSL -> Metal pipeline -> dispatch -> readback correct.\n");
    return 0;
}
