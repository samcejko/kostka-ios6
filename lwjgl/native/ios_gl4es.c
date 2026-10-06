/*
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend of LWJGL)
 * All rights reserved. BSD license, as LWJGL (see lwjgl/README.md).
 */

// gl4es on EAGL. Built with gl4es's flags and headers (-I gl4es/src), because it sets gl4es's own state:
// iOS has no window framebuffer, so the game's framebuffer 0 has to be the framebuffer object on the
// window's layer (ios_context.m makes it), and gl4es binds that one wherever the game binds 0.
#include <dlfcn.h>
#include <stdlib.h>
#include "gl/gl4es.h"
#include "ios_common.h"

void set_getprocaddress(void *(*new_proc_address)(const char *));
void initialize_gl4es(void);
void gl4es_pre_swap(void);
void gl4es_post_swap(void);
void *gl4es_GetProcAddress(const char *name);

static void *g_gles;

// The real OpenGL ES 2.0 (gl4es's own functions are all named gl4es_..., so nothing here shadows it)
void *ko_gles_proc_address(const char *name)
{
    if (!g_gles) g_gles = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY | RTLD_GLOBAL);
    return g_gles ? dlsym(g_gles, name) : NULL;
}

void ko_gl4es_init(void)
{
    static int done;
    if (done) return;
    done = 1;
    // (glGetError answers no error: games only log what they get - Minecraft 1.6 three lines every frame for an
    // error gl4es keeps from its work - and the log costs them time. With KOSTKA_GLDEBUG the errors are told.)
    if (!getenv("KOSTKA_GLDEBUG")) setenv("LIBGL_NOERROR", "1", 0);
    set_getprocaddress(ko_gles_proc_address);
    initialize_gl4es();
}

void ko_gl4es_set_main_framebuffer(unsigned fbo, int width, int height)
{
    if (!glstate) return;
    glstate->fbo.mainfbo_fbo = fbo;
    glstate->fbo.mainfbo_width = width;
    glstate->fbo.mainfbo_height = height;
}

// The renderbuffer gl4es believes is bound (the swap binds the window's own for a moment)
unsigned ko_gl4es_current_renderbuffer(void)
{
    return glstate && glstate->fbo.current_rb ? glstate->fbo.current_rb->renderbuffer : 0;
}

void ko_gl4es_pre_swap(void)
{
    gl4es_pre_swap();
}

void ko_gl4es_post_swap(void)
{
    gl4es_post_swap();
}

void *ko_gl4es_proc_address(const char *name)
{
    return gl4es_GetProcAddress(name);
}
