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

    // Pipeline cache: rebuilding the same MSL+entry must reuse the same pipeline,
    // not recompile (the Metal shader compiler is expensive).
    uint64_t pipe2 = macgl_compute_build_pipeline(kMSL, "addOne", err, sizeof(err));
    if (pipe2 != pipe) { fprintf(stderr, "FAIL: cache miss — got new handle %llu vs %llu\n",
                                 (unsigned long long)pipe2, (unsigned long long)pipe); return 1; }
    if (macgl_compute_live_pipelines() != 1) {
        fprintf(stderr, "FAIL: expected 1 live pipeline after cached rebuild.\n"); return 1;
    }
    printf("ok: pipeline cache returns same handle on identical rebuild.\n");

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

    // Persistent binary archive: load (empty) -> build -> save -> file written.
    const char* arch = "/tmp/macglcompat_test.metalarchive";
    remove(arch);
    if (macgl_pipeline_cache_load(arch)) {
        char e2[256] = {0};
        uint64_t p3 = macgl_compute_build_pipeline(
            "#include <metal_stdlib>\nusing namespace metal;\n"
            "kernel void k(device int* d [[buffer(0)]], uint i [[thread_position_in_grid]]) { d[i] = d[i] * 3; }\n",
            "k", e2, sizeof(e2));
        if (p3 == 0) { fprintf(stderr, "FAIL: archive pipeline build: %s\n", e2); return 1; }
        if (!macgl_pipeline_cache_save(arch)) { fprintf(stderr, "FAIL: archive save.\n"); return 1; }
        FILE* f = fopen(arch, "rb");
        if (!f) { fprintf(stderr, "FAIL: archive file not written.\n"); return 1; }
        fseek(f, 0, SEEK_END); long sz = ftell(f); fclose(f);
        if (sz <= 0) { fprintf(stderr, "FAIL: archive file empty.\n"); return 1; }
        printf("ok: binary archive round-trips to disk (%ld bytes).\n", sz);
        macgl_compute_destroy_pipeline(p3);
    } else {
        printf("note: binary archive unavailable here; skipping archive check.\n");
    }

    macgl_compute_destroy_pipeline(pipe);
    if (macgl_compute_live_pipelines() != 0) { fprintf(stderr, "FAIL: leak.\n"); return 1; }

    printf("PASS: MSL -> pipeline -> dispatch -> readback correct.\n");
    return 0;
}
