// Phase 2 Metal compute engine — pure-C interface (no Metal types) so C/C++ tests and
// the transpiler can drive it. Implemented in compute.m.
//
// Written blind (no Mac to verify yet); compiles in CI. A GPU-capable runner or a real
// Mac executes the bodies. This is the half that turns transpiled MSL into a running
// compute dispatch.
#ifndef MACGLCOMPAT_COMPUTE_H
#define MACGLCOMPAT_COMPUTE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Compile MSL source into a compute pipeline. Returns a non-zero handle on success, or
// 0 on failure (no device, compile error, missing entry). On failure, a message is
// written to err (truncated to errCap).
uint64_t macgl_compute_build_pipeline(const char* mslSource,
                                      const char* entryName,
                                      char* err, int errCap);

// Test/utility: run a pipeline over a single shared buffer. Uploads byteLen bytes from
// data into an MTLBuffer bound at buffer index 0, dispatches `threads` threads, then
// copies the result back into data. Returns 1 on success, 0 on failure.
int macgl_compute_run_single_buffer(uint64_t pipeline,
                                    void* data, int byteLen,
                                    unsigned threads);

void macgl_compute_destroy_pipeline(uint64_t pipeline);

// Number of live pipelines (diagnostics/tests).
int macgl_compute_live_pipelines(void);

// --- Persistent pipeline cache (MTLBinaryArchive) -------------------------
// The in-memory pipeline cache avoids recompiling within one run; this avoids it ACROSS
// runs. Compiled GPU binaries are serialized to disk, so a later launch reuses them
// instead of re-running the Metal shader compiler (a big cold-start cost). Load the
// archive before building pipelines; save it after. Both no-op without a device.
// Return 1 on success, 0 otherwise.
int macgl_pipeline_cache_load(const char* path);
int macgl_pipeline_cache_save(const char* path);

#ifdef __cplusplus
}
#endif

#endif // MACGLCOMPAT_COMPUTE_H
