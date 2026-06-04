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
#define MAX_REAL 16
static struct { char name[48]; void* addr; } g_real[MAX_REAL];
static int g_real_count = 0;

void macgl_set_real_function(const char* gl_name, void* real_addr) {
    if (!gl_name) return;
    for (int i = 0; i < g_real_count; i++) {
        if (strncmp(g_real[i].name, gl_name, sizeof(g_real[i].name)) == 0) {
            g_real[i].addr = real_addr;
            return;
        }
    }
    if (g_real_count < MAX_REAL) {
        strncpy(g_real[g_real_count].name, gl_name, sizeof(g_real[g_real_count].name) - 1);
        g_real[g_real_count].addr = real_addr;
        g_real_count++;
    }
}

static void* real_of(const char* name) {
    for (int i = 0; i < g_real_count; i++) {
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
static int g_warned = 0;
static void warn_stub(const char* fn) {
    if (!g_warned) { fprintf(stderr, "[MacGLCompat] stub GL call (%s); Metal body lands in Phase 2.\n", fn); g_warned = 1; }
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
void* macgl_function_address(const char* gl_name) {
    if (!gl_name) return NULL;
    // overrides
    if (strcmp(gl_name, "glGetString") == 0)       return (void*)&mgl_glGetString;
    // gap fillers (registered; bodies are stubs until Phase 2)
    if (strcmp(gl_name, "glDispatchCompute") == 0) return (void*)&mgl_glDispatchCompute;
    if (strcmp(gl_name, "glMemoryBarrier") == 0)   return (void*)&mgl_glMemoryBarrier;
    if (strcmp(gl_name, "glBindImageTexture") == 0) return (void*)&mgl_glBindImageTexture;
    return NULL;
}
