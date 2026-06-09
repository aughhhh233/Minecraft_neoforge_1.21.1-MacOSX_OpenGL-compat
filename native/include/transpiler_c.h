// Pure-C wrapper around the C++ transpiler, so the Obj-C JNI layer (bridge.m, compiled
// as Objective-C, not Objective-C++) can call it.
#ifndef MACGLCOMPAT_TRANSPILER_C_H
#define MACGLCOMPAT_TRANSPILER_C_H

#ifdef __cplusplus
extern "C" {
#endif

// Translate a GLSL compute shader to MSL. Returns a malloc'd NUL-terminated string the
// caller must free(), or NULL on failure. Pure CPU — no Metal/GPU needed.
char* macgl_transpile_compute_to_msl(const char* glsl, int glslVersion);

#ifdef __cplusplus
}
#endif

#endif // MACGLCOMPAT_TRANSPILER_C_H
