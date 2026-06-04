// Phase 2 building-block test: compile MSL -> pipeline, dispatch, read back.
// Exercises macgl_compute_* directly with hand-written MSL (no transpiler).
//
// Needs a Metal device; exits 2 (skip) without one. 0 = pass, 1 = fail.

#import <Foundation/Foundation.h>
#include "macglcompat.h"
#include "compute.h"
#include <stdio.h>

static const char* kMSL =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "kernel void addOne(device int* data [[buffer(0)]],\n"
    "                   uint i [[thread_position_in_grid]]) {\n"
    "    data[i] = data[i] + 1;\n"
    "}\n";

int main(void) {
    if (!macgl_initialize()) { fprintf(stderr, "SKIP: no Metal device.\n"); return 2; }

    char err[256] = {0};
    uint64_t pipe = macgl_compute_build_pipeline(kMSL, "addOne", err, sizeof(err));
    if (pipe == 0) { fprintf(stderr, "FAIL: build_pipeline: %s\n", err); return 1; }

    const int N = 256;
    int data[N];
    for (int i = 0; i < N; i++) data[i] = i;

    if (!macgl_compute_run_single_buffer(pipe, data, (int)sizeof(data), N)) {
        fprintf(stderr, "FAIL: run_single_buffer.\n");
        return 1;
    }
    for (int i = 0; i < N; i++) {
        if (data[i] != i + 1) {
            fprintf(stderr, "FAIL: data[%d]=%d expected %d\n", i, data[i], i + 1);
            return 1;
        }
    }

    macgl_compute_destroy_pipeline(pipe);
    if (macgl_compute_live_pipelines() != 0) { fprintf(stderr, "FAIL: leak.\n"); return 1; }

    printf("PASS: MSL -> pipeline -> dispatch -> readback correct.\n");
    return 0;
}
