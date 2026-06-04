// B test: function resolution + glGetString version spoof. Pure CPU, runs on CI.
//
// Exit codes: 0 = pass, 1 = fail.

#include "trampolines.h"
#include <stdio.h>
#include <string.h>

typedef unsigned int        GLenum;
typedef unsigned char       GLubyte;
typedef const GLubyte* (*PFN_glGetString)(GLenum);

#define GL_VERSION                  0x1F02
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#define GL_VENDOR                   0x1F00

static int failures = 0;
static void check(int cond, const char* what) {
    if (cond) { printf("  ok: %s\n", what); }
    else { printf("  FAIL: %s\n", what); failures++; }
}

// A fake "real" glGetString so we can test delegation without a GL context.
static const GLubyte* fake_real_getstring(GLenum name) {
    if (name == GL_VENDOR) return (const GLubyte*)"FAKE_VENDOR";
    return (const GLubyte*)"FAKE_OTHER";
}

int main(void) {
    // Resolution: overrides + gap fillers are wired, unknowns are not.
    check(macgl_function_address("glGetString") != NULL,       "glGetString resolves");
    check(macgl_function_address("glDispatchCompute") != NULL, "glDispatchCompute resolves");
    check(macgl_function_address("glMemoryBarrier") != NULL,   "glMemoryBarrier resolves");
    check(macgl_function_address("glBindImageTexture") != NULL,"glBindImageTexture resolves");
    check(macgl_function_address("glNotARealFunction") == NULL,"unknown name returns NULL");

    // Version spoof: GL_VERSION/GLSL are faked; other queries delegate to the real fn.
    macgl_set_real_function("glGetString", (void*)&fake_real_getstring);
    PFN_glGetString gs = (PFN_glGetString)macgl_function_address("glGetString");

    const char* ver = (const char*)gs(GL_VERSION);
    check(ver != NULL && strstr(ver, "4.6") != NULL, "GL_VERSION reports 4.6");

    const char* glsl = (const char*)gs(GL_SHADING_LANGUAGE_VERSION);
    check(glsl != NULL && strstr(glsl, "4.6") != NULL, "GLSL version reports 4.60");

    const char* vendor = (const char*)gs(GL_VENDOR);
    check(vendor != NULL && strcmp(vendor, "FAKE_VENDOR") == 0,
          "non-version query delegates to real driver");

    if (failures == 0) { printf("PASS: trampoline tests\n"); return 0; }
    printf("FAILED: %d checks\n", failures);
    return 1;
}
