// MacGLCompat native backend — shared declarations.
#ifndef MACGLCOMPAT_H
#define MACGLCOMPAT_H

#import <Metal/Metal.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Process-wide Metal context, created once by NativeBridge.initialize().
typedef struct {
    id<MTLDevice>       device;
    id<MTLCommandQueue> queue;
    bool                ready;
} MacGLContext;

MacGLContext* macgl_context(void);
bool          macgl_initialize(void);
void*         macgl_function_address(const char* gl_name);

// --- Phase 1a: IOSurface <-> MTLTexture bridge -----------------------------
//
// A "bridge" owns one IOSurface plus the MTLTexture that aliases it. Phase 1b
// will additionally bind the same IOSurface to an OpenGL texture (via
// CGLTexImageIOSurface2D) so a Metal compute pass and Apple's GL driver share
// one piece of GPU memory. That GL side needs a live GL context and is therefore
// deferred to on-Mac work.

typedef uint64_t MacGLBridgeHandle; // 0 == invalid

// Subset of GL internal formats we map. Extend as mods need more.
typedef enum {
    MACGL_FMT_RGBA8 = 0,   // GL_RGBA8   -> MTLPixelFormatRGBA8Unorm
    MACGL_FMT_RGBA16F = 1,  // GL_RGBA16F -> MTLPixelFormatRGBA16Float
    MACGL_FMT_R32F = 2      // GL_R32F    -> MTLPixelFormatR32Float
} MacGLFormat;

// Create an IOSurface + aliasing MTLTexture of the given size/format.
// Returns 0 on failure (no device, bad format, or surface/texture creation failed).
MacGLBridgeHandle macgl_bridge_create(uint32_t width, uint32_t height, MacGLFormat fmt);

// The aliasing MTLTexture (as id<MTLTexture>, returned as void* for the C ABI), or NULL.
void* macgl_bridge_mtltexture(MacGLBridgeHandle h);

// The backing IOSurface's global ID (IOSurfaceGetID), for the Phase 1b GL bind. 0 if invalid.
uint32_t macgl_bridge_iosurface_id(MacGLBridgeHandle h);

uint32_t macgl_bridge_width(MacGLBridgeHandle h);
uint32_t macgl_bridge_height(MacGLBridgeHandle h);

// Release the texture + surface and free the slot. No-op for an invalid handle.
void macgl_bridge_destroy(MacGLBridgeHandle h);

// Count of live bridges (for tests/diagnostics).
uint32_t macgl_bridge_live_count(void);

#ifdef __cplusplus
}
#endif

#endif // MACGLCOMPAT_H
