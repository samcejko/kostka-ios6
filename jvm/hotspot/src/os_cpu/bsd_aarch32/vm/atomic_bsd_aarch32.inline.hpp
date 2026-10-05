/*
 * Copyright (c) 1999, 2011, Oracle and/or its affiliates. All rights reserved.
 * Copyright (c) 2014, Red Hat Inc. All rights reserved.
 * Copyright (c) 2015, Linaro Ltd. All rights reserved.
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

#ifndef OS_CPU_BSD_AARCH32_VM_ATOMIC_BSD_AARCH32_INLINE_HPP
#define OS_CPU_BSD_AARCH32_VM_ATOMIC_BSD_AARCH32_INLINE_HPP

#include "runtime/atomic.hpp"
#include "runtime/os.hpp"
#include "vm_version_aarch32.hpp"
#include <libkern/OSAtomic.h>

// Implementation of class atomic: the Linux AArch32 one, but for 64-bit values. Darwin's ARM ABI aligns a long long
// to 4 bytes only, so a jlong in a C++ object is often not 8-byte aligned - and LDREXD/STREXD fault on such an
// address (SIGBUS, BUS_ADRALN). An 8-byte aligned value is accessed with them as on Linux; any other one under one
// of a few spin locks, chosen by its address (every access of a given value takes the same path, its address does
// not change).

#define FULL_MEM_BARRIER  __asm__ __volatile__ ("dmb ish"   : : : "memory")
#define READ_MEM_BARRIER  __asm__ __volatile__ ("dmb ish"   : : : "memory")
#define WRITE_MEM_BARRIER __asm__ __volatile__ ("dmb ishst" : : : "memory")

// (defined in os_bsd_aarch32.cpp)
extern OSSpinLock kostka_atomic64_locks[32];

inline OSSpinLock* kostka_atomic64_lock(volatile void* p) {
  return &kostka_atomic64_locks[((uintptr_t)p >> 2) & 31];
}

inline bool kostka_aligned8(volatile void* p) {
  return ((uintptr_t)p & 7) == 0;
}

inline jlong kostka_read64(volatile jlong* p) {
  volatile juint* w = (volatile juint*)p;
  return (jlong)(((julong)w[1] << 32) | (julong)w[0]);
}

inline void kostka_write64(volatile jlong* p, jlong v) {
  volatile juint* w = (volatile juint*)p;
  w[0] = (juint)(julong)v;
  w[1] = (juint)((julong)v >> 32);
}

inline void Atomic::store    (jbyte    store_value, jbyte*    dest) { *dest = store_value; }
inline void Atomic::store    (jshort   store_value, jshort*   dest) { *dest = store_value; }
inline void Atomic::store    (jint     store_value, jint*     dest) { *dest = store_value; }
inline void Atomic::store_ptr(intptr_t store_value, intptr_t* dest) { *dest = store_value; }
inline void Atomic::store_ptr(void*    store_value, void*     dest) { *(void**)dest = store_value; }

inline void Atomic::store    (jbyte    store_value, volatile jbyte*    dest) { *dest = store_value; }
inline void Atomic::store    (jshort   store_value, volatile jshort*   dest) { *dest = store_value; }
inline void Atomic::store    (jint     store_value, volatile jint*     dest) { *dest = store_value; }
inline void Atomic::store_ptr(intptr_t store_value, volatile intptr_t* dest) { *dest = store_value; }
inline void Atomic::store_ptr(void*    store_value, volatile void*     dest) { *(void* volatile *)dest = store_value; }

inline jint Atomic::add(jint add_value, volatile jint* dest)
{
 return __sync_add_and_fetch(dest, add_value);
}

inline void Atomic::inc(volatile jint* dest)
{
 add(1, dest);
}

inline void Atomic::inc_ptr(volatile void* dest)
{
 add_ptr(1, dest);
}

inline void Atomic::dec (volatile jint* dest)
{
 add(-1, dest);
}

inline void Atomic::dec_ptr(volatile void* dest)
{
 add_ptr(-1, dest);
}

inline jint Atomic::xchg (jint exchange_value, volatile jint* dest)
{
  jint res = __sync_lock_test_and_set (dest, exchange_value);
  FULL_MEM_BARRIER;
  return res;
}

inline void* Atomic::xchg_ptr(void* exchange_value, volatile void* dest)
{
  return (void *) xchg_ptr((intptr_t) exchange_value,
                           (volatile intptr_t*) dest);
}

inline jint Atomic::cmpxchg (jint exchange_value, volatile jint* dest, jint compare_value)
{
 return __sync_val_compare_and_swap(dest, compare_value, exchange_value);
}

inline void Atomic::store (jlong store_value, jlong* dest) {
    store(store_value, (volatile jlong *)dest);
}

inline void Atomic::store (jlong store_value, volatile jlong* dest) {
  if (kostka_aligned8(dest)) {
    register long long t1;
    register int t3;
    __asm__ __volatile__ (
        "repeat_%=:\n\t"
        "ldrexd %Q[t1],%R[t1],[%[addr]]\n\t"
        "strexd %[t3],%Q[val],%R[val],[%[addr]]\n\t"
        "cmp %[t3],#0\n\t"
        "bne repeat_%="
        : [t1] "=&r" (t1),
          [t3] "=&r" (t3)
        : [val] "r" (store_value), [addr] "r" (dest)
        : "memory");
    return;
  }
  OSSpinLock* l = kostka_atomic64_lock(dest);
  OSSpinLockLock(l);
  kostka_write64(dest, store_value);
  OSSpinLockUnlock(l);
}

inline intptr_t Atomic::add_ptr(intptr_t add_value, volatile intptr_t* dest)
{
 return __sync_add_and_fetch(dest, add_value);
}

inline void* Atomic::add_ptr(intptr_t add_value, volatile void* dest)
{
  return (void *) add_ptr(add_value, (volatile intptr_t *) dest);
}

inline void Atomic::inc_ptr(volatile intptr_t* dest)
{
 add_ptr(1, dest);
}

inline void Atomic::dec_ptr(volatile intptr_t* dest)
{
 add_ptr(-1, dest);
}

inline intptr_t Atomic::xchg_ptr(intptr_t exchange_value, volatile intptr_t* dest)
{
  intptr_t res = __sync_lock_test_and_set (dest, exchange_value);
  FULL_MEM_BARRIER;
  return res;
}

inline jlong Atomic::cmpxchg (jlong exchange_value, volatile jlong* dest, jlong compare_value)
{
  if (kostka_aligned8(dest)) {
    register long long old_value;
    register int store_result;
    __asm__ __volatile__ (
        "mov %[res],#1\n\t"
        "repeat_%=:\n\t"
        "ldrexd %Q[old],%R[old],[%[addr]]\n\t"
        "cmp %Q[old], %Q[cmpr]\n\t"
        "ittt eq\n\t"
        "cmpeq %R[old], %R[cmpr]\n\t"
        "strexdeq %[res],%Q[exch],%R[exch],[%[addr]]\n\t"
        "cmpeq %[res],#1\n\t"
        "beq repeat_%="
        : [old] "=&r" (old_value),
          [res] "=&r" (store_result)
        : [exch] "r" (exchange_value),
          [cmpr] "r" (compare_value),
          [addr] "r" (dest)
        : "memory");
    return old_value;
  }
  OSSpinLock* l = kostka_atomic64_lock(dest);
  OSSpinLockLock(l);
  jlong old_value = kostka_read64(dest);
  if (old_value == compare_value) {
    kostka_write64(dest, exchange_value);
  }
  OSSpinLockUnlock(l);
  return old_value;
}

inline intptr_t Atomic::cmpxchg_ptr(intptr_t exchange_value, volatile intptr_t* dest, intptr_t compare_value)
{
 return __sync_val_compare_and_swap(dest, compare_value, exchange_value);
}

inline void* Atomic::cmpxchg_ptr(void* exchange_value, volatile void* dest, void* compare_value)
{
  return (void *) cmpxchg_ptr((intptr_t) exchange_value,
                              (volatile intptr_t*) dest,
                              (intptr_t) compare_value);
}

inline jlong Atomic::load(volatile jlong* src) {
  if (kostka_aligned8(src)) {
    register long long res;
    __asm__ __volatile__ (
        "ldrexd %Q[res], %R[res], [%[addr]]"
        : [res] "=r" (res)
        : [addr] "r" (src)
        : "memory");
    return res;
  }
  OSSpinLock* l = kostka_atomic64_lock(src);
  OSSpinLockLock(l);
  jlong v = kostka_read64(src);
  OSSpinLockUnlock(l);
  return v;
}

#endif // OS_CPU_BSD_AARCH32_VM_ATOMIC_BSD_AARCH32_INLINE_HPP
