// Phase 1a: the Metal half of the OpenGL-texture <-> Metal-texture bridge.
//
// We create an IOSurface and an MTLTexture that aliases the same GPU memory via
// -[MTLDevice newTextureWithDescriptor:iosurface:plane:]. Phase 1b will bind that
// same IOSurface to an OpenGL texture with CGLTexImageIOSurface2D so Apple's GL
// driver and our Metal compute passes read/write one shared buffer. The GL side
// needs a live GL context (in-game, on a Mac) and is not in this file yet.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
// OpenGL is deprecated on macOS but still present; needed for the CGL IOSurface bind.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#import <OpenGL/OpenGL.h>
#import <OpenGL/CGLIOSurface.h>
#import <OpenGL/gl.h>
#include "macglcompat.h"

// One live bridge: an IOSurface and the MTLTexture aliasing it.
@interface MGLBridgeEntry : NSObject
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic, assign) IOSurfaceRef surface; // CF, released in dealloc
@property (nonatomic, assign) uint32_t width;
@property (nonatomic, assign) uint32_t height;
@end

@implementation MGLBridgeEntry
- (void)dealloc {
    if (_surface) {
        CFRelease(_surface);
        _surface = NULL;
    }
}
@end

// handle -> entry. Guarded by a lock; texture creation can race the render thread.
static NSMutableDictionary<NSNumber*, MGLBridgeEntry*>* g_bridges = nil;
static MacGLBridgeHandle g_next_handle = 1;
static NSLock* g_lock = nil;

static void ensure_tables(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_bridges = [NSMutableDictionary dictionary];
        g_lock = [[NSLock alloc] init];
    });
}

// Map our format enum to (MTLPixelFormat, IOSurface pixel format, bytes/element).
static bool resolve_format(MacGLFormat fmt,
                           MTLPixelFormat* outMtl,
                           uint32_t* outFourCC,
                           uint32_t* outBytesPerElement) {
    switch (fmt) {
        case MACGL_FMT_RGBA8:
            *outMtl = MTLPixelFormatRGBA8Unorm;
            *outFourCC = 'RGBA';
            *outBytesPerElement = 4;
            return true;
        case MACGL_FMT_RGBA16F:
            *outMtl = MTLPixelFormatRGBA16Float;
            *outFourCC = 'RGhA'; // 64-bit half-float RGBA
            *outBytesPerElement = 8;
            return true;
        case MACGL_FMT_R32F:
            *outMtl = MTLPixelFormatR32Float;
            *outFourCC = 'L032';
            *outBytesPerElement = 4;
            return true;
        default:
            return false;
    }
}

MacGLBridgeHandle macgl_bridge_create(uint32_t width, uint32_t height, MacGLFormat fmt) {
    ensure_tables();
    MacGLContext* ctx = macgl_context();
    if (ctx == NULL || !ctx->ready || ctx->device == nil) {
        NSLog(@"[MacGLCompat] bridge_create: no Metal device.");
        return 0;
    }
    if (width == 0 || height == 0) return 0;

    MTLPixelFormat mtlFmt;
    uint32_t fourCC, bpe;
    if (!resolve_format(fmt, &mtlFmt, &fourCC, &bpe)) {
        NSLog(@"[MacGLCompat] bridge_create: unsupported format %d.", (int)fmt);
        return 0;
    }

    size_t bytesPerRow = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, (size_t)width * bpe);

    NSDictionary* props = @{
        (id)kIOSurfaceWidth:           @(width),
        (id)kIOSurfaceHeight:          @(height),
        (id)kIOSurfaceBytesPerElement: @(bpe),
        (id)kIOSurfaceBytesPerRow:     @(bytesPerRow),
        (id)kIOSurfacePixelFormat:     @(fourCC),
    };
    IOSurfaceRef surf = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (surf == NULL) {
        NSLog(@"[MacGLCompat] bridge_create: IOSurfaceCreate failed (%ux%u).", width, height);
        return 0;
    }

    MTLTextureDescriptor* desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:mtlFmt
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    desc.storageMode = MTLStorageModeShared; // required for IOSurface-backed textures

    id<MTLTexture> tex = [ctx->device newTextureWithDescriptor:desc iosurface:surf plane:0];
    if (tex == nil) {
        NSLog(@"[MacGLCompat] bridge_create: newTextureWithDescriptor:iosurface: failed.");
        CFRelease(surf);
        return 0;
    }

    MGLBridgeEntry* e = [[MGLBridgeEntry alloc] init];
    e.texture = tex;
    e.surface = surf; // ownership transferred; released in -dealloc
    e.width = width;
    e.height = height;

    [g_lock lock];
    MacGLBridgeHandle h = g_next_handle++;
    g_bridges[@(h)] = e;
    [g_lock unlock];
    return h;
}

static MGLBridgeEntry* lookup(MacGLBridgeHandle h) {
    if (h == 0 || g_bridges == nil) return nil;
    [g_lock lock];
    MGLBridgeEntry* e = g_bridges[@(h)];
    [g_lock unlock];
    return e;
}

void* macgl_bridge_mtltexture(MacGLBridgeHandle h) {
    MGLBridgeEntry* e = lookup(h);
    return e ? (__bridge void*)e.texture : NULL;
}

uint32_t macgl_bridge_iosurface_id(MacGLBridgeHandle h) {
    MGLBridgeEntry* e = lookup(h);
    return e ? IOSurfaceGetID(e.surface) : 0;
}

uint32_t macgl_bridge_width(MacGLBridgeHandle h)  { MGLBridgeEntry* e = lookup(h); return e ? e.width  : 0; }
uint32_t macgl_bridge_height(MacGLBridgeHandle h) { MGLBridgeEntry* e = lookup(h); return e ? e.height : 0; }

void macgl_bridge_destroy(MacGLBridgeHandle h) {
    if (h == 0 || g_bridges == nil) return;
    [g_lock lock];
    [g_bridges removeObjectForKey:@(h)]; // ARC + -dealloc release texture/surface
    [g_lock unlock];
}

uint32_t macgl_bridge_live_count(void) {
    if (g_bridges == nil) return 0;
    [g_lock lock];
    uint32_t n = (uint32_t)g_bridges.count;
    [g_lock unlock];
    return n;
}

bool macgl_bridge_bind_gl_texture(MacGLBridgeHandle h, uint32_t glTarget,
                                  uint32_t glInternalFormat, uint32_t glFormat,
                                  uint32_t glType) {
    MGLBridgeEntry* e = lookup(h);
    if (!e || e.surface == NULL) return false;
    CGLContextObj cgl = CGLGetCurrentContext();
    if (cgl == NULL) {
        NSLog(@"[MacGLCompat] bind_gl_texture: no current CGL context.");
        return false;
    }
    // Binds the IOSurface as storage for the currently-bound texture of glTarget.
    // Historically glTarget must be GL_TEXTURE_RECTANGLE for IOSurface textures; whether
    // GL_TEXTURE_2D works for Minecraft's textures is the open question to settle on Mac.
    CGLError err = CGLTexImageIOSurface2D(cgl, (GLenum)glTarget, (GLenum)glInternalFormat,
                                          (GLsizei)e.width, (GLsizei)e.height,
                                          (GLenum)glFormat, (GLenum)glType, e.surface, 0);
    if (err != kCGLNoError) {
        NSLog(@"[MacGLCompat] CGLTexImageIOSurface2D failed: %d", (int)err);
        return false;
    }
    return true;
}

#pragma clang diagnostic pop
