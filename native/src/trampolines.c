// B: function-pointer trampolines.
//
// macgl_function_address(name) returns a C function pointer with the exact ABI of the
// named GL entry point. LWJGL calls these directly. Two kinds live here:
//
//   1. Overrides (e.g. glGetString) — replace a function the 4.1 driver HAS, so we can
//      spoof the reported GL version. Fully implemented + CPU-testable.
//   2. Gap fillers (glDispatchCompute, glMemoryBarrier, glBindImageTexture, ...) — the
//      4.2+ entry points the driver lacks. Phase 0..B provide registered stubs (so the
//      capability flags flip on and the wiring is exercised); the Metal bodies are wired
//      in Phase 2 on a real Mac.
//
// Pure C, no Metal here — so this whole layer's resolution + the version spoof are
// verifiable on a CPU-only CI runner.

#include "trampolines.h"
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdatomic.h>

// --- minimal GL typedefs (avoid pulling in deprecated OpenGL headers) ------
typedef unsigned int  GLenum;
typedef unsigned char GLubyte;
typedef unsigned int  GLuint;
typedef int           GLint;
typedef int           GLsizei;
typedef unsigned int  GLbitfield;
typedef unsigned char GLboolean;

#define GL_VENDOR                   0x1F00
#define GL_RENDERER                 0x1F01
#define GL_VERSION                  0x1F02
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C

static const char* SPOOF_VERSION = "4.6.0 Metal-MacGLCompat";
static const char* SPOOF_GLSL    = "4.60";

// --- table of REAL driver pointers our trampolines delegate to -------------
// Contract: entries are appended during single-threaded init (CompatInstaller), then
// read afterwards (possibly from a different thread than the installer). On ARM's weak
// memory model a plain write+read across threads does not guarantee the entry's bytes
// are visible. We publish via release/acquire on the count: the entry writes happen
// before the count is released, so any reader that acquires the new count sees a fully
// written entry. (Overwriting an existing entry's addr is not part of the contract — set
// each function once.)
#define MAX_REAL 16
static struct { char name[48]; void* addr; } g_real[MAX_REAL];
static atomic_int g_real_count = 0;

void macgl_set_real_function(const char* gl_name, void* real_addr) {
    if (!gl_name) return;
    int n = atomic_load_explicit(&g_real_count, memory_order_acquire);
    for (int i = 0; i < n; i++) {
        if (strncmp(g_real[i].name, gl_name, sizeof(g_real[i].name)) == 0) {
            g_real[i].addr = real_addr;
            return;
        }
    }
    if (n < MAX_REAL) {
        strncpy(g_real[n].name, gl_name, sizeof(g_real[n].name) - 1);
        g_real[n].addr = real_addr;
        // Release: the writes above are visible to any thread that acquire-loads count.
        atomic_store_explicit(&g_real_count, n + 1, memory_order_release);
    }
}

static void* real_of(const char* name) {
    int n = atomic_load_explicit(&g_real_count, memory_order_acquire);
    for (int i = 0; i < n; i++) {
        if (strncmp(g_real[i].name, name, sizeof(g_real[i].name)) == 0) {
            return g_real[i].addr;
        }
    }
    return NULL;
}

// --- (1) override: glGetString with version spoofing -----------------------
typedef const GLubyte* (*PFN_glGetString)(GLenum);

static const GLubyte* mgl_glGetString(GLenum name) {
    if (name == GL_VERSION)                  return (const GLubyte*)SPOOF_VERSION;
    if (name == GL_SHADING_LANGUAGE_VERSION) return (const GLubyte*)SPOOF_GLSL;
    // Everything else (VENDOR, RENDERER, EXTENSIONS) goes to the real driver.
    void* real = real_of("glGetString");
    if (real) return ((PFN_glGetString)real)(name);
    return NULL;
}

// --- (2) gap-filler stubs (Phase 2 replaces the bodies with Metal) ---------
static atomic_int g_warned = 0;
static void warn_stub(const char* fn) {
    // Exactly one thread prints, even if stubs are hit concurrently.
    if (atomic_exchange_explicit(&g_warned, 1, memory_order_relaxed) == 0) {
        fprintf(stderr, "[MacGLCompat] stub GL call (%s); Metal body lands in Phase 2.\n", fn);
    }
}

static void mgl_glDispatchCompute(GLuint x, GLuint y, GLuint z) {
    (void)x; (void)y; (void)z; warn_stub("glDispatchCompute");
}
static void mgl_glMemoryBarrier(GLbitfield barriers) {
    (void)barriers; warn_stub("glMemoryBarrier");
}
static void mgl_glBindImageTexture(GLuint unit, GLuint texture, GLint level,
                                   GLboolean layered, GLint layer, GLenum access, GLenum format) {
    (void)unit; (void)texture; (void)level; (void)layered; (void)layer; (void)access; (void)format;
    warn_stub("glBindImageTexture");
}

// --- resolution table ------------------------------------------------------
// Data-driven so adding the DSA / image / indirect functions is a one-line edit.
// MUST stay sorted by name (binary search). Mix of overrides (glGetString) and gap
// fillers; the stub bodies become real Metal in Phase 2.
typedef struct { const char* name; void* fn; } TrampEntry;

static const TrampEntry TRAMPOLINES[] = {
    { "glBindImageTexture", (void*)&mgl_glBindImageTexture },
    { "glDispatchCompute",  (void*)&mgl_glDispatchCompute  },
    { "glGetString",        (void*)&mgl_glGetString        },
    { "glMemoryBarrier",    (void*)&mgl_glMemoryBarrier    },
};

static int tramp_cmp(const void* key, const void* el) {
    return strcmp((const char*)key, ((const TrampEntry*)el)->name);
}

void* macgl_function_address(const char* gl_name) {
    if (!gl_name) return NULL;
    const TrampEntry* e = (const TrampEntry*)bsearch(
        gl_name, TRAMPOLINES,
        sizeof(TRAMPOLINES) / sizeof(TRAMPOLINES[0]), sizeof(TRAMPOLINES[0]),
        tramp_cmp);
    return e ? e->fn : NULL;
}
