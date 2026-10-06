/*
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend of LWJGL)
 * All rights reserved. BSD license, as LWJGL (see lwjgl/README.md).
 */

// OpenGL contexts on iOS (the JNI side of Kostka's MacOSXContextImplementation): an EAGL context for
// OpenGL ES 2.0 that draws into a framebuffer object whose color buffer is the window's layer. The game's
// desktop OpenGL goes through gl4es (ios_gl4es.c); here the real OpenGL ES functions are called (gl4es
// names all of its own gl4es_...), and gl4es is told which framebuffer is the window's.
// Built without ARC (a C structure holds the context).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>
#include <jni.h>
#include "common_tools.h"
#include "ios_common.h"

typedef struct {
    EAGLContext *context;   // retained
    KOWindow *window;       // the window the framebuffer is on (NULL: none yet)
    GLuint fbo, color, depth;
    int width, height;
} KOContext;

static KOContext *ko_context(JNIEnv *env, jobject handle)
{
    return handle ? (KOContext *)(*env)->GetDirectBufferAddress(env, handle) : NULL;
}

JNIEXPORT jobject JNICALL Java_org_lwjgl_opengl_MacOSXContextImplementation_nCreate(JNIEnv *env, jclass clazz, jobject peer_handle, jobject shared_handle)
{
    @autoreleasepool {
        KOContext *shared = ko_context(env, shared_handle);
        EAGLContext *context = shared
            ? [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2 sharegroup:shared->context.sharegroup]
            : [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!context) {
            throwException(env, "Could not create an OpenGL ES 2.0 context");
            return NULL;
        }
        KOContext *c = calloc(1, sizeof(KOContext));
        c->context = context;
        return (*env)->NewDirectByteBuffer(env, c, sizeof(KOContext));
    }
}

// The framebuffer on the window's layer: the color buffer is the layer's, depth and stencil one buffer
static BOOL ko_make_framebuffer(JNIEnv *env, KOContext *c, KOWindow *window)
{
    if (!c->fbo) glGenFramebuffers(1, &c->fbo);
    if (!c->color) glGenRenderbuffers(1, &c->color);
    if (!c->depth) glGenRenderbuffers(1, &c->depth);
    glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
    glBindRenderbuffer(GL_RENDERBUFFER, c->color);
    if (![c->context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)ko_window_layer(window)]) {
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
        throwException(env, "Could not attach the window to the context");
        return NO;
    }
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, c->color);
    GLint width = 0, height = 0;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);
    glBindRenderbuffer(GL_RENDERBUFFER, c->depth);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8_OES, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, c->depth);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, c->depth);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    // (gl4es's state: no renderbuffer bound; its framebuffer 0 is this one)
    glBindRenderbuffer(GL_RENDERBUFFER, 0);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        throwFormattedException(env, "The window's framebuffer is incomplete (0x%x, %dx%d)", status, width, height);
        return NO;
    }
    c->window = window;
    c->width = width;
    c->height = height;
    printfDebugJava(env, "Framebuffer %dx%d", width, height);
    return YES;
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_MacOSXContextImplementation_nMakeCurrent(JNIEnv *env, jclass clazz, jobject handle, jobject window_handle)
{
    @autoreleasepool {
        KOContext *c = ko_context(env, handle);
        KOWindow *window = window_handle ? (KOWindow *)(*env)->GetDirectBufferAddress(env, window_handle) : NULL;
        if (!c) return;
        if (![EAGLContext setCurrentContext:c->context]) {
            throwException(env, "Could not make the context current");
            return;
        }
        BOOL fresh = NO;
        if (window && c->window != window) {
            if (!ko_make_framebuffer(env, c, window)) return;
            fresh = YES;
        }
        ko_gl4es_init();
        if (c->fbo) {
            ko_gl4es_set_main_framebuffer(c->fbo, c->width, c->height);
            glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
        }
        if (fresh) {
            // (the whole framebuffer to begin with, through gl4es, which keeps track of it)
            void (*viewport)(GLint, GLint, GLsizei, GLsizei) = (void (*)(GLint, GLint, GLsizei, GLsizei))ko_gl4es_proc_address("glViewport");
            void (*scissor)(GLint, GLint, GLsizei, GLsizei) = (void (*)(GLint, GLint, GLsizei, GLsizei))ko_gl4es_proc_address("glScissor");
            if (viewport) viewport(0, 0, c->width, c->height);
            if (scissor) scissor(0, 0, c->width, c->height);
        }
    }
}

// (tests, KOSTKA_GLDEBUG in the environment: which step of the swap leaves an OpenGL error, the first ones)
static int ko_gl_debug(void)
{
    static int on = -1;
    if (on < 0) on = getenv("KOSTKA_GLDEBUG") != NULL;
    return on;
}

static void ko_check(const char *where)
{
    // (gl4es's glGetError: the errors gl4es keeps itself, then the driver's)
    static GLenum (*get_error)(void);
    static int told;
    if (!get_error) get_error = (GLenum (*)(void))ko_gl4es_proc_address("glGetError");
    GLenum e;
    while (get_error && (e = get_error()) != GL_NO_ERROR) {
        if (told < 12) {
            told++;
            fprintf(stderr, "[LWJGL] OpenGL error 0x%x %s\n", e, where);
        }
    }
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_MacOSXContextImplementation_nSwapBuffers(JNIEnv *env, jclass clazz, jobject handle)
{
    @autoreleasepool {
        KOContext *c = ko_context(env, handle);
        if (!c || !c->window) return;
        int debug = ko_gl_debug();
        if (debug) ko_check("left by the frame");
        ko_gl4es_pre_swap();
        if (debug) ko_check("from gl4es before the swap");
        glBindRenderbuffer(GL_RENDERBUFFER, c->color);
        if (debug) ko_check("binding the window's renderbuffer");
        [c->context presentRenderbuffer:GL_RENDERBUFFER];
        if (debug) ko_check("presenting");
        // (the game's thread has no run loop to commit Core Animation's transaction: without this the frame
        // reaches the screen only when the next present gives up waiting for it, once a second)
        [CATransaction flush];
        glBindRenderbuffer(GL_RENDERBUFFER, ko_gl4es_current_renderbuffer());
        if (debug) ko_check("binding gl4es's renderbuffer back");
        ko_gl4es_post_swap();
        if (debug) ko_check("from gl4es after the swap");
        ko_game_frames++;
        ko_wait_while_inactive();
    }
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_MacOSXContextImplementation_nReleaseCurrentContext(JNIEnv *env, jclass clazz)
{
    @autoreleasepool {
        if ([EAGLContext currentContext]) glFlush();
        [EAGLContext setCurrentContext:nil];
    }
}

JNIEXPORT jboolean JNICALL Java_org_lwjgl_opengl_MacOSXContextImplementation_nIsCurrent(JNIEnv *env, jclass clazz, jobject handle)
{
    @autoreleasepool {
        KOContext *c = ko_context(env, handle);
        return c && [EAGLContext currentContext] == c->context ? JNI_TRUE : JNI_FALSE;
    }
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_MacOSXContextImplementation_nDestroy(JNIEnv *env, jclass clazz, jobject handle)
{
    @autoreleasepool {
        KOContext *c = ko_context(env, handle);
        if (!c) return;
        EAGLContext *previous = [EAGLContext currentContext];
        if ([EAGLContext setCurrentContext:c->context]) {
            if (c->fbo) glDeleteFramebuffers(1, &c->fbo);
            if (c->color) glDeleteRenderbuffers(1, &c->color);
            if (c->depth) glDeleteRenderbuffers(1, &c->depth);
            ko_gl4es_set_main_framebuffer(0, 0, 0);
        }
        [EAGLContext setCurrentContext:previous == c->context ? nil : previous];
        [c->context release];
        free(c);
    }
}
