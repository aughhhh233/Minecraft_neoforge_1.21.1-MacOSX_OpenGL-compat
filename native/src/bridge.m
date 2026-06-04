// JNI bridge: connects com.macglcompat.natives.NativeBridge to the Metal backend.
//
// Phase 0 scope: real Metal device bring-up (so we can confirm the CI runner has a
// usable Metal device) plus stubbed function resolution. The version string is the
// one piece of real behaviour the Java side depends on immediately.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <jni.h>
#include <string.h>
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

void* macgl_function_address(const char* gl_name) {
    // Phase 0: nothing implemented yet. Phase 1 wires glDispatchCompute, SSBO
    // binding, and the glGetString version override through here.
    (void)gl_name;
    return NULL;
}

// ---- JNI exports (must match com.macglcompat.natives.NativeBridge) ----

JNIEXPORT jboolean JNICALL
Java_com_macglcompat_natives_NativeBridge_initialize(JNIEnv* env, jclass clazz) {
    (void)env; (void)clazz;
    return macgl_initialize() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL
Java_com_macglcompat_natives_NativeBridge_functionAddress(JNIEnv* env, jclass clazz, jstring name) {
    (void)clazz;
    if (name == NULL) return 0;
    const char* c = (*env)->GetStringUTFChars(env, name, NULL);
    void* addr = macgl_function_address(c);
    (*env)->ReleaseStringUTFChars(env, name, c);
    return (jlong)(uintptr_t)addr;
}

JNIEXPORT jstring JNICALL
Java_com_macglcompat_natives_NativeBridge_spoofedVersionString(JNIEnv* env, jclass clazz) {
    (void)clazz;
    // Report 4.6 so LWJGL attempts to bind the 4.3/4.6 function sets at all.
    return (*env)->NewStringUTF(env, "4.6.0 Metal-MacGLCompat");
}

JNIEXPORT jstring JNICALL
Java_com_macglcompat_natives_NativeBridge_backendInfo(JNIEnv* env, jclass clazz) {
    (void)clazz;
    if (!g_ctx.ready || g_ctx.device == nil) {
        return (*env)->NewStringUTF(env, "uninitialized");
    }
    const char* dn = [[g_ctx.device name] UTF8String];
    char buf[256];
    snprintf(buf, sizeof(buf), "Metal device='%s'", dn ? dn : "unknown");
    return (*env)->NewStringUTF(env, buf);
}
