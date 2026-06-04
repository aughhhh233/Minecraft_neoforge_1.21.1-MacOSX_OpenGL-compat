// Phase 2 Metal compute engine: MSL source -> MTLComputePipelineState, and a dispatch
// helper used by tests. Blind-written; compiles in CI, runs on a Mac / GPU-capable CI.
//
// The real glDispatchCompute trampoline (Phase 2 integration) will track GL bind state
// and call into this; here we provide the self-contained, testable building blocks.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "macglcompat.h"
#include "compute.h"

@interface MGLPipeline : NSObject
@property (nonatomic, strong) id<MTLComputePipelineState> pso;
@end
@implementation MGLPipeline
@end

static NSMutableDictionary<NSNumber*, MGLPipeline*>* g_pipes = nil;
static uint64_t g_next_pipe = 1;
static NSLock* g_pipe_lock = nil;

static void ensure_pipe_tables(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_pipes = [NSMutableDictionary dictionary];
        g_pipe_lock = [[NSLock alloc] init];
    });
}

uint64_t macgl_compute_build_pipeline(const char* mslSource, const char* entryName,
                                      char* err, int errCap) {
    ensure_pipe_tables();
    MacGLContext* ctx = macgl_context();
    if (ctx == NULL || !ctx->ready || ctx->device == nil) {
        if (err && errCap > 0) snprintf(err, errCap, "no Metal device");
        return 0;
    }
    if (mslSource == NULL || entryName == NULL) {
        if (err && errCap > 0) snprintf(err, errCap, "null source/entry");
        return 0;
    }

    NSError* nserr = nil;
    NSString* src = [NSString stringWithUTF8String:mslSource];
    MTLCompileOptions* opts = [[MTLCompileOptions alloc] init];
    id<MTLLibrary> lib = [ctx->device newLibraryWithSource:src options:opts error:&nserr];
    if (lib == nil) {
        if (err && errCap > 0)
            snprintf(err, errCap, "MSL compile: %s",
                     nserr ? [[nserr localizedDescription] UTF8String] : "unknown");
        return 0;
    }

    id<MTLFunction> fn = [lib newFunctionWithName:[NSString stringWithUTF8String:entryName]];
    if (fn == nil) {
        if (err && errCap > 0) snprintf(err, errCap, "entry '%s' not found", entryName);
        return 0;
    }

    id<MTLComputePipelineState> pso =
        [ctx->device newComputePipelineStateWithFunction:fn error:&nserr];
    if (pso == nil) {
        if (err && errCap > 0)
            snprintf(err, errCap, "pipeline: %s",
                     nserr ? [[nserr localizedDescription] UTF8String] : "unknown");
        return 0;
    }

    MGLPipeline* p = [[MGLPipeline alloc] init];
    p.pso = pso;
    [g_pipe_lock lock];
    uint64_t h = g_next_pipe++;
    g_pipes[@(h)] = p;
    [g_pipe_lock unlock];
    return h;
}

static id<MTLComputePipelineState> pso_of(uint64_t handle) {
    if (handle == 0 || g_pipes == nil) return nil;
    [g_pipe_lock lock];
    MGLPipeline* p = g_pipes[@(handle)];
    [g_pipe_lock unlock];
    return p ? p.pso : nil;
}

int macgl_compute_run_single_buffer(uint64_t pipeline, void* data, int byteLen,
                                    unsigned threads) {
    MacGLContext* ctx = macgl_context();
    if (ctx == NULL || !ctx->ready) return 0;
    id<MTLComputePipelineState> pso = pso_of(pipeline);
    if (pso == nil || data == NULL || byteLen <= 0) return 0;

    id<MTLBuffer> buf = [ctx->device newBufferWithBytes:data
                                                 length:(NSUInteger)byteLen
                                                options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [ctx->queue commandBuffer];
    id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
    [enc setComputePipelineState:pso];
    [enc setBuffer:buf offset:0 atIndex:0];

    NSUInteger tpt = pso.maxTotalThreadsPerThreadgroup;
    if (tpt == 0) tpt = 64;
    if (tpt > threads && threads > 0) tpt = threads;
    [enc dispatchThreads:MTLSizeMake(threads, 1, 1)
        threadsPerThreadgroup:MTLSizeMake(tpt, 1, 1)];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if (cb.error != nil) return 0;

    memcpy(data, [buf contents], (size_t)byteLen);
    return 1;
}

void macgl_compute_destroy_pipeline(uint64_t pipeline) {
    if (pipeline == 0 || g_pipes == nil) return;
    [g_pipe_lock lock];
    [g_pipes removeObjectForKey:@(pipeline)];
    [g_pipe_lock unlock];
}

int macgl_compute_live_pipelines(void) {
    if (g_pipes == nil) return 0;
    [g_pipe_lock lock];
    int n = (int)g_pipes.count;
    [g_pipe_lock unlock];
    return n;
}
