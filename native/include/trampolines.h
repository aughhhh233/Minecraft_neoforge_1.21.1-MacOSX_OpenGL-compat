// Pure-C trampoline interface (no Metal/Obj-C), so C-only test executables and the
// JNI layer can use it without pulling in Metal headers.
#ifndef MACGLCOMPAT_TRAMPOLINES_H
#define MACGLCOMPAT_TRAMPOLINES_H

#ifdef __cplusplus
extern "C" {
#endif

// Resolve a native trampoline (exact GL ABI) for an entry point we override or fill.
// Returns 0 if unprovided.
void* macgl_function_address(const char* gl_name);

// Store the REAL driver address of a GL function our trampolines delegate to
// (e.g. glGetString for non-version queries).
void  macgl_set_real_function(const char* gl_name, void* real_addr);

#ifdef __cplusplus
}
#endif

#endif // MACGLCOMPAT_TRAMPOLINES_H
