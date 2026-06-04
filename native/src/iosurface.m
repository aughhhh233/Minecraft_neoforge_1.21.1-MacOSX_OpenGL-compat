// Phase 1 target: the OpenGL-texture <-> Metal-texture bridge.
//
// When a compute shader (Metal backend) needs to read or write a texture that Iris
// created through Apple's OpenGL driver, both APIs must alias the same GPU memory.
// macOS provides IOSurface exactly for this: an OpenGL texture can be backed by an
// IOSurface, and MTLDevice.newTextureWithDescriptor:iosurface:plane: wraps the same
// surface as an MTLTexture. This file will own the GL-object <-> IOSurface <->
// MTLTexture mapping table and the cross-queue synchronization.
//
// Empty in Phase 0.

#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#include "macglcompat.h"

// (intentionally empty in Phase 0)
