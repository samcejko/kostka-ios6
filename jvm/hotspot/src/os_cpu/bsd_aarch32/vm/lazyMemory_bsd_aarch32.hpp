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

#ifndef OS_CPU_BSD_AARCH32_VM_LAZYMEMORY_BSD_AARCH32_HPP
#define OS_CPU_BSD_AARCH32_VM_LAZYMEMORY_BSD_AARCH32_HPP

#include "memory/allocation.hpp"

// Large blocks of Unsafe.allocateMemory zeroed without bringing their untouched pages into memory
// (lazyMemory_bsd_aarch32.cpp). Unsafe tells it of each block it allocates and frees.
class LazyMemory : AllStatic {
 public:
  static void allocated(void* p, size_t size);
  static void freed(void* p);
  // Zeroes [p, p + size) if it lies in a large block from Unsafe.allocateMemory, leaving out the pages that have
  // never been touched; false if it does not (the caller zeroes it)
  static bool zero(void* p, size_t size);
};

#endif // OS_CPU_BSD_AARCH32_VM_LAZYMEMORY_BSD_AARCH32_HPP
