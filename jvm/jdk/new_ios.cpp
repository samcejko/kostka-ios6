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

// new and delete for the JDK's C++ libraries (libsunec), inside each of them: iOS 6 keeps these operators in
// libc++.1.dylib, but the iOS 9.3 SDK binds them to libc++abi.dylib, which iOS 6 does not have, and dyld would then
// refuse the library (as for libjvm: hotspot/src/os_cpu/bsd_aarch32/vm/cxxRuntime_bsd_aarch32.cpp).

#include <stdlib.h>

#define HIDDEN __attribute__((visibility("hidden")))

HIDDEN void* operator new(size_t size) {
  void* p = malloc(size != 0 ? size : 1);
  if (p == NULL) abort();
  return p;
}

HIDDEN void* operator new[](size_t size) {
  void* p = malloc(size != 0 ? size : 1);
  if (p == NULL) abort();
  return p;
}

HIDDEN void operator delete(void* p) throw() {
  free(p);
}

HIDDEN void operator delete[](void* p) throw() {
  free(p);
}
