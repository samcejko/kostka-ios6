/*
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend of LWJGL)
 * All rights reserved. BSD license, as LWJGL (see lwjgl/README.md).
 */

// What the parts of Kostka's iOS backend of LWJGL share: the window (ios_display.m), the contexts
// (ios_context.m) and gl4es (ios_gl4es.c).
#ifndef KOSTKA_IOS_COMMON_H
#define KOSTKA_IOS_COMMON_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The events MacOSXDisplay.update() takes (the same numbers as there): int type, a, b, c; long nanos
enum {
    KO_EVENT_MOUSE_MOVE = 1,    // a, b: position, bottom-left origin
    KO_EVENT_MOUSE_DELTA = 2,   // a, b: movement (grabbed mouse), up positive
    KO_EVENT_MOUSE_BUTTON = 3,  // a: button, b: 1 down / 0 up
    KO_EVENT_MOUSE_WHEEL = 4,   // a: amount
    KO_EVENT_KEY = 5,           // a: LWJGL key code, b: 1 down / 0 up, c: character
    KO_EVENT_CLOSE = 6,
    KO_EVENT_FOCUS = 7          // a: 1 in front / 0 in the background
};

typedef struct {
    int32_t type, a, b, c;
    int64_t nanos;
} KOEvent;

void ko_post_event(int type, int a, int b, int c);

// The window: a view on an EAGL layer, shown scaled to the screen (ios_display.m)
typedef struct KOWindow KOWindow;
void *ko_window_layer(KOWindow *window);   // CAEAGLLayer *
int ko_window_width(KOWindow *window);
int ko_window_height(KOWindow *window);

// In the background iOS kills an app that draws: the swap waits there until the app is back (ios_display.m)
void ko_wait_while_inactive(void);

// For tests, read by the app (dlsym): the frames the game has drawn, the size of its window (ios_display.m)
extern int ko_game_frames, ko_game_width, ko_game_height;

// gl4es (ios_gl4es.c): set up on the first current context; framebuffer 0 of the game is the window's
void ko_gl4es_init(void);
void ko_gl4es_set_main_framebuffer(unsigned fbo, int width, int height);
unsigned ko_gl4es_current_renderbuffer(void);
void ko_gl4es_pre_swap(void);
void ko_gl4es_post_swap(void);
void *ko_gl4es_proc_address(const char *name);
void *ko_gles_proc_address(const char *name);

#ifdef __cplusplus
}
#endif

#endif
