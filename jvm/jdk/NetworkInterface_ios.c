/*
 * Copyright (c) 2026, samcejko. Part of Kostka's Java runtime for iOS 6.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 */

// java.net.NetworkInterface on iOS: OpenJDK's NetworkInterface.c wants kernel headers the iOS SDK has not
// (netinet/in_var.h, netinet6/in6_var.h); until it is needed, the device simply lists no interfaces. Sockets,
// addresses and DNS do not depend on it; multicast on a chosen interface does.

#include <jni.h>
#include <stddef.h>

// (used by PlainDatagramSocketImpl.c)
jfieldID ni_addrsID;

JNIEXPORT void JNICALL
Java_java_net_NetworkInterface_init(JNIEnv *env, jclass cls)
{
    ni_addrsID = (*env)->GetFieldID(env, cls, "addrs", "[Ljava/net/InetAddress;");
}

JNIEXPORT jobjectArray JNICALL
Java_java_net_NetworkInterface_getAll(JNIEnv *env, jclass cls)
{
    return (*env)->NewObjectArray(env, 0, cls, NULL);
}

JNIEXPORT jobject JNICALL
Java_java_net_NetworkInterface_getByName0(JNIEnv *env, jclass cls, jstring name)
{
    return NULL;
}

JNIEXPORT jobject JNICALL
Java_java_net_NetworkInterface_getByIndex0(JNIEnv *env, jclass cls, jint index)
{
    return NULL;
}

JNIEXPORT jobject JNICALL
Java_java_net_NetworkInterface_getByInetAddress0(JNIEnv *env, jclass cls, jobject iaObj)
{
    return NULL;
}

JNIEXPORT jboolean JNICALL
Java_java_net_NetworkInterface_isUp0(JNIEnv *env, jclass cls, jstring name, jint index)
{
    return JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_java_net_NetworkInterface_isLoopback0(JNIEnv *env, jclass cls, jstring name, jint index)
{
    return JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_java_net_NetworkInterface_supportsMulticast0(JNIEnv *env, jclass cls, jstring name, jint index)
{
    return JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_java_net_NetworkInterface_isP2P0(JNIEnv *env, jclass cls, jstring name, jint index)
{
    return JNI_FALSE;
}

JNIEXPORT jbyteArray JNICALL
Java_java_net_NetworkInterface_getMacAddr0(JNIEnv *env, jclass cls, jbyteArray addrArray, jstring name, jint index)
{
    return NULL;
}

JNIEXPORT jint JNICALL
Java_java_net_NetworkInterface_getMTU0(JNIEnv *env, jclass cls, jstring name, jint index)
{
    return -1;
}
