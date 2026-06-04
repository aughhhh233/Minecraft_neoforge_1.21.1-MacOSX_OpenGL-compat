// Non-JNI backend core: Metal device/queue bring-up and function resolution.
// Split out of bridge.m so test executables can link it without needing jni.h.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "macglcompat.h"

static MacGLContext g_ctx = { nil, nil, false };

MacGLContext* macgl_context(void) {
    return &g_ctx;
}

bool macgl_initialize(void) {
    if (g_ctx.ready) return true;

    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (dev == nil) {
        NSLog(@"[MacGLCompat] No Metal device available.");
        return false;
    }
    id<MTLCommandQueue> q = [dev newCommandQueue];
    if (q == nil) {
        NSLog(@"[MacGLCompat] Failed to create command queue.");
        return false;
    }
    g_ctx.device = dev;
    g_ctx.queue  = q;
    g_ctx.ready  = true;
    NSLog(@"[MacGLCompat] Metal device: %@", [dev name]);
    return true;
}

// macgl_function_address / macgl_set_real_function live in trampolines.c.
