// MacGLCompat native backend — shared declarations.
//
// Phase 0: device bring-up + JNI surface only. The compute/SSBO/IOSurface
// implementations are stubs that land in Phase 1+.
#ifndef MACGLCOMPAT_H
#define MACGLCOMPAT_H

#import <Metal/Metal.h>

#ifdef __cplusplus
extern "C" {
#endif

// Process-wide Metal context, created once by NativeBridge.initialize().
typedef struct {
    id<MTLDevice>       device;
    id<MTLCommandQueue> queue;
    bool                ready;
} MacGLContext;

// Accessor for the singleton context (NULL until initialize() succeeds).
MacGLContext* macgl_context(void);

// Brings up the Metal device + command queue. Idempotent. Returns true on success.
bool macgl_initialize(void);

// Resolves a native function pointer for a GL entry point this backend implements,
// or 0 if unimplemented. Phase 0 returns 0 for everything.
void* macgl_function_address(const char* gl_name);

#ifdef __cplusplus
}
#endif

#endif // MACGLCOMPAT_H
