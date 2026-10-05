/*
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend of LWJGL)
 * All rights reserved. BSD license, as LWJGL (see lwjgl/README.md).
 */

// OpenAL on iOS: the system's OpenAL framework (LWJGL takes it when it finds no OpenAL library of its own)
#include <dlfcn.h>
#include <jni.h>
#include "extal.h"
#include "common_tools.h"

#define KO_OPENAL "/System/Library/Frameworks/OpenAL.framework/OpenAL"

static void *g_openal;

void *extal_NativeGetFunctionPointer(const char *function)
{
    return g_openal ? dlsym(g_openal, function) : NULL;
}

void extal_LoadLibrary(JNIEnv *env, jstring path)
{
    const char *p = (*env)->GetStringUTFChars(env, path, NULL);
    g_openal = dlopen(p, RTLD_LAZY);
    (*env)->ReleaseStringUTFChars(env, path, p);
    if (!g_openal) throwException(env, "Could not load the OpenAL library");
}

void extal_UnloadLibrary()
{
    // (a system framework stays loaded)
    g_openal = NULL;
}

JNIEXPORT void JNICALL Java_org_lwjgl_openal_AL_nCreateDefault(JNIEnv *env, jclass clazz)
{
    g_openal = dlopen(KO_OPENAL, RTLD_LAZY);
    if (!g_openal) throwException(env, "Could not load the OpenAL framework");
}
