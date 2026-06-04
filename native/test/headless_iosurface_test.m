// Headless IOSurface <-> MTLTexture bridge self-test (Phase 1a).
//
// Verifies that we can create an IOSurface-backed MTLTexture, that it aliases a real
// surface (non-zero IOSurface ID), that writing through the MTLTexture and reading the
// IOSurface bytes back agrees (i.e. they share memory), and that teardown is clean.
//
// Like the compute test, this needs a Metal device. On a runner without one it exits 2
// (skip) rather than failing, so "no GPU in CI" stays distinguishable from a real bug.
//
// Exit codes: 0 = pass, 1 = bug, 2 = no Metal device.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#include "macglcompat.h"

int main(void) {
    @autoreleasepool {
        if (!macgl_initialize()) {
            fprintf(stderr, "SKIP: no Metal device on this host.\n");
            return 2;
        }

        const uint32_t W = 64, H = 64;
        MacGLBridgeHandle h = macgl_bridge_create(W, H, MACGL_FMT_RGBA8);
        if (h == 0) {
            fprintf(stderr, "FAIL: bridge_create returned 0.\n");
            return 1;
        }

        if (macgl_bridge_iosurface_id(h) == 0) {
            fprintf(stderr, "FAIL: IOSurface ID is 0.\n");
            return 1;
        }
        if (macgl_bridge_width(h) != W || macgl_bridge_height(h) != H) {
            fprintf(stderr, "FAIL: size mismatch.\n");
            return 1;
        }

        id<MTLTexture> tex = (__bridge id<MTLTexture>)macgl_bridge_mtltexture(h);
        if (tex == nil) {
            fprintf(stderr, "FAIL: MTLTexture is nil.\n");
            return 1;
        }

        // Write a known pixel through the MTLTexture...
        const uint8_t px[4] = { 0x11, 0x22, 0x33, 0x44 }; // RGBA8
        MTLRegion region = MTLRegionMake2D(1, 1, 1, 1);
        [tex replaceRegion:region mipmapLevel:0 withBytes:px bytesPerRow:W * 4];

        // ...and read it back from the IOSurface memory directly: same bytes => shared.
        // We re-fetch the surface via a second handle-free path: lock the surface that
        // backs this texture. The bridge exposes the ID; resolve it to a surface.
        IOSurfaceRef surf = IOSurfaceLookup(macgl_bridge_iosurface_id(h));
        if (surf == NULL) {
            fprintf(stderr, "FAIL: IOSurfaceLookup failed.\n");
            return 1;
        }
        IOSurfaceLock(surf, kIOSurfaceLockReadOnly, NULL);
        const uint8_t* base = (const uint8_t*)IOSurfaceGetBaseAddress(surf);
        size_t stride = IOSurfaceGetBytesPerRow(surf);
        const uint8_t* pixel = base + (1 * stride) + (1 * 4);
        bool match = pixel[0] == px[0] && pixel[1] == px[1]
                  && pixel[2] == px[2] && pixel[3] == px[3];
        IOSurfaceUnlock(surf, kIOSurfaceLockReadOnly, NULL);
        CFRelease(surf); // IOSurfaceLookup returns a +1 reference

        if (!match) {
            fprintf(stderr, "FAIL: MTLTexture write not visible in IOSurface — not shared memory.\n");
            return 1;
        }

        macgl_bridge_destroy(h);
        if (macgl_bridge_live_count() != 0) {
            fprintf(stderr, "FAIL: live count != 0 after destroy.\n");
            return 1;
        }

        fprintf(stdout, "PASS: IOSurface<->MTLTexture share memory; create/destroy clean.\n");
        return 0;
    }
}
