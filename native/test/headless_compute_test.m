// Headless Metal compute self-test.
//
// Verifies, with no Minecraft and no human, that:
//   1. a Metal device exists on this machine/runner,
//   2. an MSL compute shader compiles,
//   3. a dispatch runs and the result reads back correctly.
//
// This is the proof-of-life for the entire Metal path. If it passes on a GitHub
// macOS runner, the compute machinery Phase 2 depends on is exercisable in CI
// without a physical Mac. If the runner has no Metal device, it exits 2 so we can
// tell "no GPU in CI" apart from "compute is wrong".
//
// Exit codes: 0 = pass, 1 = compute incorrect / Metal error, 2 = no Metal device.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static const char* kShader =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "kernel void add_one(device int* data [[buffer(0)]],\n"
    "                    uint i [[thread_position_in_grid]]) {\n"
    "    data[i] = data[i] + 1;\n"
    "}\n";

int main(void) {
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        if (dev == nil) {
            fprintf(stderr, "SKIP: no Metal device on this host.\n");
            return 2;
        }
        fprintf(stdout, "Metal device: %s\n", [[dev name] UTF8String]);

        NSError* err = nil;
        id<MTLLibrary> lib =
            [dev newLibraryWithSource:[NSString stringWithUTF8String:kShader]
                              options:nil
                                error:&err];
        if (lib == nil) {
            fprintf(stderr, "FAIL: shader compile: %s\n", err ? [[err description] UTF8String] : "?");
            return 1;
        }
        id<MTLFunction> fn = [lib newFunctionWithName:@"add_one"];
        id<MTLComputePipelineState> pso = [dev newComputePipelineStateWithFunction:fn error:&err];
        if (pso == nil) {
            fprintf(stderr, "FAIL: pipeline: %s\n", err ? [[err description] UTF8String] : "?");
            return 1;
        }

        const int N = 1024;
        int host[N];
        for (int i = 0; i < N; i++) host[i] = i;

        id<MTLBuffer> buf = [dev newBufferWithBytes:host
                                             length:sizeof(host)
                                            options:MTLResourceStorageModeShared];

        id<MTLCommandQueue> q = [dev newCommandQueue];
        id<MTLCommandBuffer> cb = [q commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
        [enc setComputePipelineState:pso];
        [enc setBuffer:buf offset:0 atIndex:0];
        [enc dispatchThreads:MTLSizeMake(N, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
        [enc endEncoding];
        [cb commit];
        [cb waitUntilCompleted];

        if (cb.error != nil) {
            fprintf(stderr, "FAIL: command buffer: %s\n", [[cb.error description] UTF8String]);
            return 1;
        }

        int* out = (int*)[buf contents];
        for (int i = 0; i < N; i++) {
            if (out[i] != i + 1) {
                fprintf(stderr, "FAIL: out[%d] = %d, expected %d\n", i, out[i], i + 1);
                return 1;
            }
        }
        fprintf(stdout, "PASS: compute dispatch + readback correct for %d elements.\n", N);
        return 0;
    }
}
