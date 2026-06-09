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

// Pipeline cache: identical (MSL + entry) compiles to the same pipeline, so building it
// again should reuse the existing one instead of re-invoking the Metal shader compiler
// (which is expensive). key string -> handle, plus handle -> key for cleanup on destroy.
static NSMutableDictionary<NSString*, NSNumber*>* g_pipeCache = nil;
static NSMutableDictionary<NSNumber*, NSString*>* g_pipeKeyByHandle = nil;

// Cross-run persistent cache of compiled GPU binaries.
static id<MTLBinaryArchive> g_archive = nil;

static void ensure_pipe_tables(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_pipes = [NSMutableDictionary dictionary];
        g_pipe_lock = [[NSLock alloc] init];
        g_pipeCache = [NSMutableDictionary dictionary];
        g_pipeKeyByHandle = [NSMutableDictionary dictionary];
    });
}

static NSString* pipe_cache_key(const char* msl, const char* entry) {
    return [NSString stringWithFormat:@"%s\x01%s", msl, entry];
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

    // Cache hit: same MSL + entry already compiled and still live.
    NSString* ckey = pipe_cache_key(mslSource, entryName);
    [g_pipe_lock lock];
    NSNumber* cached = g_pipeCache[ckey];
    if (cached != nil && g_pipes[cached] != nil) {
        uint64_t h = (uint64_t)[cached unsignedLongLongValue];
        [g_pipe_lock unlock];
        return h;
    }
    [g_pipe_lock unlock];

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

    // Descriptor-based creation so we can attach the persistent binary archive: if the
    // pipeline's binary is already in the archive, Metal reuses it instead of recompiling.
    MTLComputePipelineDescriptor* pdesc = [[MTLComputePipelineDescriptor alloc] init];
    pdesc.computeFunction = fn;
    if (g_archive != nil) pdesc.binaryArchives = @[ g_archive ];

    id<MTLComputePipelineState> pso =
        [ctx->device newComputePipelineStateWithDescriptor:pdesc
                                                   options:MTLPipelineOptionNone
                                                reflection:NULL
                                                     error:&nserr];
    if (pso == nil) {
        if (err && errCap > 0)
            snprintf(err, errCap, "pipeline: %s",
                     nserr ? [[nserr localizedDescription] UTF8String] : "unknown");
        return 0;
    }
    // Record this pipeline into the archive so a later save persists it to disk.
    if (g_archive != nil) {
        NSError* aerr = nil;
        [g_archive addComputePipelineFunctionsWithDescriptor:pdesc error:&aerr];
    }

    MGLPipeline* p = [[MGLPipeline alloc] init];
    p.pso = pso;
    [g_pipe_lock lock];
    uint64_t h = g_next_pipe++;
    g_pipes[@(h)] = p;
    g_pipeCache[ckey] = @(h);
    g_pipeKeyByHandle[@(h)] = ckey;
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
    NSString* key = g_pipeKeyByHandle[@(pipeline)];
    if (key != nil) {
        [g_pipeCache removeObjectForKey:key];
        [g_pipeKeyByHandle removeObjectForKey:@(pipeline)];
    }
    [g_pipe_lock unlock];
}

int macgl_compute_live_pipelines(void) {
    if (g_pipes == nil) return 0;
    [g_pipe_lock lock];
    int n = (int)g_pipes.count;
    [g_pipe_lock unlock];
    return n;
}

int macgl_pipeline_cache_load(const char* path) {
    ensure_pipe_tables();
    MacGLContext* ctx = macgl_context();
    if (ctx == NULL || !ctx->ready || ctx->device == nil || path == NULL) return 0;

    MTLBinaryArchiveDescriptor* d = [[MTLBinaryArchiveDescriptor alloc] init];
    NSString* p = [NSString stringWithUTF8String:path];
    // If a previous archive exists, seed from it; otherwise start an empty one.
    if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
        d.url = [NSURL fileURLWithPath:p];
    }
    NSError* e = nil;
    id<MTLBinaryArchive> a = [ctx->device newBinaryArchiveWithDescriptor:d error:&e];
    if (a == nil) {
        NSLog(@"[MacGLCompat] binary archive load failed: %@", e ? [e localizedDescription] : @"?");
        return 0;
    }
    [g_pipe_lock lock];
    g_archive = a;
    [g_pipe_lock unlock];
    return 1;
}

int macgl_pipeline_cache_save(const char* path) {
    if (path == NULL) return 0;
    [g_pipe_lock lock];
    id<MTLBinaryArchive> a = g_archive;
    [g_pipe_lock unlock];
    if (a == nil) return 0;

    NSError* e = nil;
    BOOL ok = [a serializeToURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]]
                          error:&e];
    if (!ok) {
        NSLog(@"[MacGLCompat] binary archive save failed: %@", e ? [e localizedDescription] : @"?");
        return 0;
    }
    return 1;
}
