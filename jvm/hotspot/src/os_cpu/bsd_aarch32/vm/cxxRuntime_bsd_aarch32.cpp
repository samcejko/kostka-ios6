/*
 * Copyright (c) 2026, samcejko. The iOS (Darwin, armv7) port of the AArch32 port.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 */

// The few pieces of the C++ runtime HotSpot needs, inside libjvm. iOS 6 keeps operator new and delete in
// libc++.1.dylib, but the iOS 9.3 SDK binds them to libc++abi.dylib (where later iOS versions have them), and dyld
// on iOS 6 then refuses to load libjvm. HotSpot uses no exceptions: malloc and free do.

#include <stdlib.h>
#include <new>

void* operator new(size_t size) {
  void* p = malloc(size != 0 ? size : 1);
  if (p == NULL) abort();
  return p;
}

void* operator new[](size_t size) {
  void* p = malloc(size != 0 ? size : 1);
  if (p == NULL) abort();
  return p;
}

void* operator new(size_t size, const std::nothrow_t&) throw() {
  return malloc(size != 0 ? size : 1);
}

void* operator new[](size_t size, const std::nothrow_t&) throw() {
  return malloc(size != 0 ? size : 1);
}

void operator delete(void* p) throw() {
  free(p);
}

void operator delete[](void* p) throw() {
  free(p);
}

void operator delete(void* p, const std::nothrow_t&) throw() {
  free(p);
}

void operator delete[](void* p, const std::nothrow_t&) throw() {
  free(p);
}

extern "C" void __cxa_pure_virtual() {
  abort();
}
