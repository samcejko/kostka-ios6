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

// DirectByteBuffer zeroes the memory it gets from Unsafe.allocateMemory, and on iOS 6 (no swap; an iPad 2 has
// 512 MB, a game gets some 300 of them) every page so written stays in memory as long as the buffer lives, used or
// not. Games ask for large buffers that they fill in part: old Minecraft (paulscode's sound system inside its jar,
// up to 1.2.5) 32 buffers of 5 MB for its sound channels, of which it writes a few kilobytes; later versions
// texture and vertex buffers of 8 and 16 MB.
//
// Large blocks from malloc are pages straight from the kernel, which read as zero until something writes them. So
// within a large block from Unsafe.allocateMemory, zeroing writes only the pages that are in memory: mincore() says
// which. A page of such memory that is neither in memory nor paged out (iOS 6 does not page it out; later versions
// compress it, and mincore says so) has never been touched since the kernel gave it, or since malloc gave it back
// with MADV_FREE and the kernel took it: either way it reads as zero. Only blocks known to come from
// Unsafe.allocateMemory (malloc's anonymous memory) are treated so, never any other address.

#include "precompiled.hpp"
#include "lazyMemory_bsd_aarch32.hpp"
#include "runtime/os.hpp"
#include "runtime/threadCritical.hpp"
#include "utilities/copy.hpp"
#include "utilities/globalDefinitions.hpp"

#include <sys/mman.h>

#ifndef MINCORE_PAGED_OUT
#define MINCORE_PAGED_OUT 0x20
#endif

// (smaller blocks are not worth it; the latest 64 large ones are remembered, which is plenty: DirectByteBuffer
// zeroes its block right after allocating it, and a block that is not remembered is zeroed the plain way)
static const size_t lazy_min_size = 256 * K;
static const int lazy_slots = 64;
static struct {
  char* base;
  size_t size;
} lazy_blocks[lazy_slots];
static int lazy_next = 0;

void LazyMemory::allocated(void* p, size_t size) {
  if (p == NULL || size < lazy_min_size) {
    return;
  }
  ThreadCritical tc;
  lazy_blocks[lazy_next].base = (char*) p;
  lazy_blocks[lazy_next].size = size;
  lazy_next = (lazy_next + 1) % lazy_slots;
}

void LazyMemory::freed(void* p) {
  if (p == NULL) {
    return;
  }
  ThreadCritical tc;
  for (int i = 0; i < lazy_slots; i++) {
    if (lazy_blocks[i].base == (char*) p) {
      lazy_blocks[i].base = NULL;
    }
  }
}

bool LazyMemory::zero(void* p, size_t size) {
  char* from = (char*) p;
  char* to = from + size;
  if (from == NULL || size < lazy_min_size || to < from) {
    return false;
  }
  bool known = false;
  {
    ThreadCritical tc;
    for (int i = 0; i < lazy_slots && !known; i++) {
      char* base = lazy_blocks[i].base;
      known = base != NULL && base <= from && to <= base + lazy_blocks[i].size;
    }
  }
  if (!known) {
    return false;
  }
  const size_t page = os::vm_page_size();
  char* first = (char*) align_size_up((intptr_t) from, (intptr_t) page);
  char* last = (char*) align_size_down((intptr_t) to, (intptr_t) page);
  // (the parts of pages at either end: written as usual)
  Copy::fill_to_memory_atomic(from, first - from);
  Copy::fill_to_memory_atomic(last, to - last);
  char in_memory[256];
  for (char* q = first; q < last; ) {
    size_t pages = MIN2((size_t) (last - q) / page, sizeof(in_memory));
    if (mincore(q, pages * page, in_memory) != 0) {
      Copy::fill_to_memory_atomic(q, last - q);
      break;
    }
    for (size_t i = 0; i < pages; i++) {
      if ((in_memory[i] & (MINCORE_INCORE | MINCORE_PAGED_OUT)) != 0) {
        Copy::fill_to_memory_atomic(q + i * page, page);
      }
    }
    q += pages * page;
  }
  return true;
}
