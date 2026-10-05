/*
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend of LWJGL)
 * All rights reserved. BSD license, as LWJGL (see lwjgl/README.md).
 */

// LWJGL's OpenGL functions on iOS are gl4es's. A function gl4es does not have gets a stand-in that does
// nothing (and says so once): LWJGL refuses a whole OpenGL version for one missing function, while the
// games call few of the old ones it checks for.
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include "extgl.h"
#include "ios_common.h"

static int ko_gl_missing(void)
{
    return 0;
}

void *extgl_GetProcAddress(const char *name)
{
    void *p = ko_gl4es_proc_address(name);
    if (p == NULL && strncmp(name, "gl", 2) == 0 && strncmp(name, "glX", 3) != 0) {
        fprintf(stderr, "[LWJGL] gl4es has no %s: it does nothing\n", name);
        p = (void *)ko_gl_missing;
    }
    return p;
}

bool extgl_Open(JNIEnv *env)
{
    return true;
}

void extgl_Close(void)
{
}
