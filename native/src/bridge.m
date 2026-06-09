// JNI bridge: connects com.macglcompat.natives.NativeBridge to the Metal backend.
//
// Phase 0 scope: real Metal device bring-up (so we can confirm the CI runner has a
// usable Metal device) plus stubbed function resolution. The version string is the
// one piece of real behaviour the Java side depends on immediately.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <jni.h>
#include <stdint.h>
#include <string.h>
#include "macglcompat.h"
#include "trampolines.h"
#include "transpiler_c.h"
#include <stdlib.h>

// Device/queue bring-up + function resolution live in core.m so test executables
// can link them without jni.h. This file is the JNI surface only.

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
    MacGLContext* ctx = macgl_context();
    if (ctx == NULL || !ctx->ready || ctx->device == nil) {
        return (*env)->NewStringUTF(env, "uninitialized");
    }
    const char* dn = [[ctx->device name] UTF8String];
    char buf[256];
    snprintf(buf, sizeof(buf), "Metal device='%s'", dn ? dn : "unknown");
    return (*env)->NewStringUTF(env, buf);
}

// ---- Phase 1a: IOSurface <-> MTLTexture bridge (JNI) ----

JNIEXPORT jlong JNICALL
Java_com_macglcompat_natives_NativeBridge_bridgeCreate(JNIEnv* env, jclass clazz,
                                                       jint width, jint height, jint fmt) {
    (void)env; (void)clazz;
    return (jlong)macgl_bridge_create((uint32_t)width, (uint32_t)height, (MacGLFormat)fmt);
}

JNIEXPORT jlong JNICALL
Java_com_macglcompat_natives_NativeBridge_bridgeMtlTextureHandle(JNIEnv* env, jclass clazz, jlong h) {
    (void)env; (void)clazz;
    return (jlong)(uintptr_t)macgl_bridge_mtltexture((MacGLBridgeHandle)h);
}

JNIEXPORT jint JNICALL
Java_com_macglcompat_natives_NativeBridge_bridgeIOSurfaceId(JNIEnv* env, jclass clazz, jlong h) {
    (void)env; (void)clazz;
    return (jint)macgl_bridge_iosurface_id((MacGLBridgeHandle)h);
}

JNIEXPORT jint JNICALL
Java_com_macglcompat_natives_NativeBridge_bridgeWidth(JNIEnv* env, jclass clazz, jlong h) {
    (void)env; (void)clazz;
    return (jint)macgl_bridge_width((MacGLBridgeHandle)h);
}

JNIEXPORT jint JNICALL
Java_com_macglcompat_natives_NativeBridge_bridgeHeight(JNIEnv* env, jclass clazz, jlong h) {
    (void)env; (void)clazz;
    return (jint)macgl_bridge_height((MacGLBridgeHandle)h);
}

JNIEXPORT void JNICALL
Java_com_macglcompat_natives_NativeBridge_bridgeDestroy(JNIEnv* env, jclass clazz, jlong h) {
    (void)env; (void)clazz;
    macgl_bridge_destroy((MacGLBridgeHandle)h);
}

JNIEXPORT jint JNICALL
Java_com_macglcompat_natives_NativeBridge_bridgeLiveCount(JNIEnv* env, jclass clazz) {
    (void)env; (void)clazz;
    return (jint)macgl_bridge_live_count();
}

JNIEXPORT void JNICALL
Java_com_macglcompat_natives_NativeBridge_setRealFunction(JNIEnv* env, jclass clazz,
                                                          jstring name, jlong addr) {
    (void)clazz;
    if (name == NULL) return;
    const char* c = (*env)->GetStringUTFChars(env, name, NULL);
    macgl_set_real_function(c, (void*)(uintptr_t)addr);
    (*env)->ReleaseStringUTFChars(env, name, c);
}

JNIEXPORT jstring JNICALL
Java_com_macglcompat_natives_NativeBridge_transpileComputeToMsl(JNIEnv* env, jclass clazz,
                                                                jstring glsl, jint glslVersion) {
    (void)clazz;
    if (glsl == NULL) return NULL;
    const char* g = (*env)->GetStringUTFChars(env, glsl, NULL);
    char* msl = macgl_transpile_compute_to_msl(g, (int)glslVersion);
    (*env)->ReleaseStringUTFChars(env, glsl, g);
    if (msl == NULL) return NULL;
    jstring out = (*env)->NewStringUTF(env, msl);
    free(msl);
    return out;
}
