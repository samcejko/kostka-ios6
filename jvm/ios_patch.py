#!/usr/bin/env python3
"""Adapts the OpenJDK 8 AArch32 sources to iOS (Darwin, armv7): run on the checked-out tree by jvm/build.sh.

1. Shared HotSpot headers include the files of each OS/CPU pair from lists
   (#ifdef TARGET_OS_ARCH_bsd_x86 / # include "atomic_bsd_x86.inline.hpp" / #endif): the bsd_aarch32 pair is added
   next to bsd_x86 wherever such a list exists.
2. Targeted edits (PATCHES below): each one must match exactly once, or the build stops - an upstream change is then
   seen at once instead of silently skipped.

Usage: python3 jvm/ios_patch.py <source tree>
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "jvm/out/src"
HS = os.path.join(ROOT, "hotspot", "src")

# Darwin's ARM ABI for calls into C (APCS, soft-float) passes a long or a double in the next two words, in registers
# or on the stack, with no alignment; its low word may even be the last register (r3) and its high word on the
# stack. Linux (AAPCS) puts it in an even register pair or at an 8-byte aligned stack slot. These patches give the
# AArch32 port Darwin's rule where it calls native code: the C calling convention of compiled native wrappers, their
# argument moves, the interpreter's signature handlers.
SR = "hotspot/src/cpu/aarch32/vm/sharedRuntime_aarch32.cpp"
IRT = "hotspot/src/cpu/aarch32/vm/interpreterRT_aarch32.cpp"
PROPS = "jdk/src/solaris/native/java/lang/java_props_macosx.c"

# (file relative to the tree, exact text, replacement, how many times it is there)
REPLACE_ALL = [
    # (pthread_t is a pointer on Darwin; these are debugging helpers that print a thread's number)
    ("hotspot/src/cpu/aarch32/vm/macroAssembler_aarch32.cpp", "int id = pthread_self();",
     "int id = (int)(intptr_t)pthread_self();", 3),
    # (size_t against the overloads of cmp: ambiguous for clang)
    ("hotspot/src/cpu/aarch32/vm/stubGenerator_aarch32.cpp", "    __ cmp(count, tmp_set_size);",
     "    __ cmp(count, (int)tmp_set_size);", 2),
]

# (file relative to the tree, exact text, replacement)
PATCHES = [
    # iOS 6 has no thread-local storage for __thread (iOS 8 brought it); these hold the state of a debugging helper
    ("hotspot/src/cpu/aarch32/vm/frame_aarch32.cpp",
     '''static __thread unsigned long nextfp;
static __thread unsigned long nextpc;
static __thread unsigned long nextsp;
static __thread RegisterMap *reg_map;''',
     '''static unsigned long nextfp;
static unsigned long nextpc;
static unsigned long nextsp;
static RegisterMap *reg_map;'''),
    # The instruction cache: Darwin's call for it (there is no __clear_cache to rely on in iOS 6's libraries)
    ("hotspot/src/cpu/aarch32/vm/icache_aarch32.hpp",
     '''  static void invalidate_word(address addr) {
    __clear_cache((char *)addr, (char *)(addr + 3));
  }
  static void invalidate_range(address start, int nbytes) {
    __clear_cache((char *)start, (char *)(start + nbytes));
  }''',
     '''  static void invalidate_word(address addr) {
    sys_icache_invalidate((void *)addr, 4);
  }
  static void invalidate_range(address start, int nbytes) {
    sys_icache_invalidate((void *)start, nbytes);
  }'''),
    ("hotspot/src/cpu/aarch32/vm/icache_aarch32.hpp",
     '''#define CPU_AARCH32_VM_ICACHE_AARCH32_HPP
''',
     '''#define CPU_AARCH32_VM_ICACHE_AARCH32_HPP

#include <libkern/OSCacheControl.h>
'''),
    # (not on iOS, and not needed there: it works around x86 stack alignment in lazily bound callbacks)
    ("hotspot/src/os/bsd/vm/os_bsd.cpp",
     '''  _dyld_bind_fully_image_containing_address((const void *) &os::init);''',
     '''#ifndef __arm__
  _dyld_bind_fully_image_containing_address((const void *) &os::init);
#endif'''),
    # (the iOS SDK has no crt_externs.h; the function is in iOS's libc)
    ("hotspot/src/os/bsd/vm/os_bsd.cpp",
     '''#include <crt_externs.h>
#define environ (*_NSGetEnviron())''',
     '''extern "C" char ***_NSGetEnviron(void);
#define environ (*_NSGetEnviron())'''),
    # iOS's libc has isfinite, not finite (marked unavailable)
    ("hotspot/src/share/vm/utilities/globalDefinitions_gcc.hpp",
     '''#if defined(LINUX)
// Linux libc without BSD extensions have no finite, but has isfinite''',
     '''#if defined(LINUX) || defined(__APPLE__)
// Linux libc without BSD extensions have no finite, but has isfinite (so has iOS)'''),
    # (macOS headers the iOS SDK does not have; nothing of them is used: the Objective-C collector is looked up with
    # dlsym, and is not there on iOS)
    ("hotspot/src/os/bsd/vm/os_bsd.cpp",
     '''# include <sys/proc_info.h>
# include <objc/objc-auto.h>
''',
     ''''''),
    # The system properties on iOS: no window server session to ask about (AWT is headless), no SCDynamicStore for
    # the system's proxy settings (SystemConfiguration has none of that on iOS)
    (PROPS, '''#include <Security/AuthSession.h>
''', '''#include <TargetConditionals.h>
#if !TARGET_OS_IPHONE
#include <Security/AuthSession.h>
#endif
'''),
    (PROPS, '''#include <SystemConfiguration/SystemConfiguration.h>
''', '''#if !TARGET_OS_IPHONE
#include <SystemConfiguration/SystemConfiguration.h>
#endif
'''),
    (PROPS, '''    // Is the WindowServer available?
    SecuritySessionId session_id;''', '''#if TARGET_OS_IPHONE
    return 0;
#else
    // Is the WindowServer available?
    SecuritySessionId session_id;'''),
    (PROPS, '''        if (session_info & sessionHasGraphicAccess) {
            return 1;
        }
    }
    return 0;
}''', '''        if (session_info & sessionHasGraphicAccess) {
            return 1;
        }
    }
    return 0;
#endif
}'''),
    (PROPS, '''    CFDictionaryRef dict = SCDynamicStoreCopyProxies(NULL);
    if (dict == NULL) return;''', '''#if TARGET_OS_IPHONE
    return;
#else
    CFDictionaryRef dict = SCDynamicStoreCopyProxies(NULL);
    if (dict == NULL) return;'''),
    (PROPS, '''#undef CHECK_PROXY

    CFRelease(dict);
}''', '''#undef CHECK_PROXY

    CFRelease(dict);
#endif
}'''),
    (SR,
     '''      case T_LONG:
        assert(sig_bt[i + 1] == T_VOID, "expecting half");
        if (int_args + 1 < Argument::n_int_register_parameters_c) {
            // c2 requires aligned reg pair''',
     '''      case T_LONG:
        assert(sig_bt[i + 1] == T_VOID, "expecting half");
#ifdef __APPLE__
        // Darwin (APCS): the next two words, not aligned; the low word may be r3 and the high word on the stack
        if (int_args + 1 < Argument::n_int_register_parameters_c) {
          regs[i].set_pair(INT_ArgReg[int_args + 1]->as_VMReg(), INT_ArgReg[int_args]->as_VMReg());
          int_args += 2;
        } else if (int_args < Argument::n_int_register_parameters_c) {
          regs[i].set_pair(VMRegImpl::stack2reg(stk_args), INT_ArgReg[int_args]->as_VMReg());
          int_args++;
          stk_args++;
        } else {
          regs[i].set_pair(VMRegImpl::stack2reg(stk_args + 1), VMRegImpl::stack2reg(stk_args));
          stk_args += 2;
        }
        break;
#endif
        if (int_args + 1 < Argument::n_int_register_parameters_c) {
            // c2 requires aligned reg pair'''),
    (SR,
     '''static void long_move(MacroAssembler* masm, VMRegPair src, VMRegPair dst) {
  if (src.first()->is_stack()) {''',
     '''static void long_move(MacroAssembler* masm, VMRegPair src, VMRegPair dst) {
#ifdef __APPLE__
  // (Darwin: a destination split in two, the low word in r3 and the high word on the stack)
  if (dst.first()->is_Register() && dst.second()->is_stack()) {
    if (src.first()->is_stack()) {
      __ ldr(rscratch1, Address(rfp, reg2offset_in(src.first()) + wordSize));
      __ str(rscratch1, Address(sp, reg2offset_out(dst.second())));
      __ ldr(dst.first()->as_Register(), Address(rfp, reg2offset_in(src.first())));
    } else {
      __ str(src.second()->as_Register(), Address(sp, reg2offset_out(dst.second())));
      if (dst.first() != src.first()) {
        __ mov(dst.first()->as_Register(), src.first()->as_Register());
      }
    }
    return;
  }
#endif
  if (src.first()->is_stack()) {'''),
    (SR,
     '''static void double_move(MacroAssembler* masm, VMRegPair src, VMRegPair dst) {
  if(hasFPU()) {''',
     '''static void double_move(MacroAssembler* masm, VMRegPair src, VMRegPair dst) {
#ifdef __APPLE__
  // (soft-float on Darwin: a double goes to C in two core registers, in r3 and on the stack, or on the stack)
  if (src.first()->is_FloatRegister()) {
    if (dst.first()->is_stack()) {
      __ vstr_f64(src.first()->as_FloatRegister(), Address(sp, reg2offset_out(dst.first())));
    } else if (dst.second()->is_stack()) {
      __ vmov_f64(dst.first()->as_Register(), rscratch1, src.first()->as_FloatRegister());
      __ str(rscratch1, Address(sp, reg2offset_out(dst.second())));
    } else {
      __ vmov_f64(dst.first()->as_Register(), dst.second()->as_Register(), src.first()->as_FloatRegister());
    }
  } else {
    long_move(masm, src, dst);
  }
  return;
#endif
  if(hasFPU()) {'''),
    (IRT,
     '''  // Needs to be aligned to even registers. Means also won't be split across
  // registers and stack.

  switch (_num_int_args) {''',
     '''  // Needs to be aligned to even registers. Means also won't be split across
  // registers and stack.
#ifdef __APPLE__
  // (not on Darwin, APCS: the next two words, not aligned; the low word may be r3 and the high word on the stack)
  const Address src_hi(from(), Interpreter::local_offset_in_bytes(offset() + 1) + wordSize);
  switch (_num_int_args) {
  case 0:
    __ ldr(c_rarg1, src);
    __ ldr(c_rarg2, src_hi);
    _num_int_args = 2;
    break;
  case 1:
    __ ldr(c_rarg2, src);
    __ ldr(c_rarg3, src_hi);
    _num_int_args = 3;
    break;
  case 2:
    __ ldr(c_rarg3, src);
    __ ldr(r0, src_hi);
    __ str(r0, Address(to(), _stack_offset));
    _stack_offset += wordSize;
    _num_int_args = 3;
    break;
  default:
    __ ldr(r0, src);
    __ str(r0, Address(to(), _stack_offset));
    __ ldr(r0, src_hi);
    __ str(r0, Address(to(), _stack_offset + wordSize));
    _stack_offset += 2 * wordSize;
    _num_int_args += 2;
    break;
  }
  return;
#endif

  switch (_num_int_args) {'''),
    (IRT,
     '''    _from -= 2*Interpreter::stackElementSize;

    if (_num_int_reg_args < Argument::n_int_register_parameters_c-2) {''',
     '''    _from -= 2*Interpreter::stackElementSize;

#ifdef __APPLE__
    // (Darwin, APCS: the next two words, in registers or on the stack, not aligned)
    if (_num_int_reg_args < Argument::n_int_register_parameters_c-1) {
      *_int_args++ = low_obj;
      _num_int_reg_args++;
    } else {
      *_to++ = low_obj;
    }
    if (_num_int_reg_args < Argument::n_int_register_parameters_c-1) {
      *_int_args++ = high_obj;
      _num_int_reg_args++;
    } else {
      *_to++ = high_obj;
    }
    return;
#endif

    if (_num_int_reg_args < Argument::n_int_register_parameters_c-2) {'''),
]


def add_os_arch_includes():
    # (the AArch32 port's own headers list only linux_aarch32; the shared ones list bsd_x86 as well: the
    # linux_aarch32 entries are copied first, the bsd_x86 ones where a file has no aarch32 entry)
    lists = [("linux_aarch32", re.compile(r'(#ifdef TARGET_OS_ARCH_linux_aarch32\n((?:# *include "[^"]*"\n)+)#endif\n)')),
             ("bsd_x86", re.compile(r'(#ifdef TARGET_OS_ARCH_bsd_x86\n((?:# *include "[^"]*"\n)+)#endif\n)'))]
    changed = 0
    for dirpath, _, files in os.walk(HS):
        for name in files:
            if not name.endswith((".hpp", ".cpp", ".h")):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="latin-1") as f:
                text = f.read()
            new = text
            for pair, block in lists:
                if "TARGET_OS_ARCH_" + pair not in new or "TARGET_OS_ARCH_bsd_aarch32" in new:
                    continue

                def repl(m, pair=pair):
                    includes = m.group(2).replace(pair, "bsd_aarch32")
                    return m.group(1) + "#ifdef TARGET_OS_ARCH_bsd_aarch32\n" + includes + "#endif\n"

                new = block.sub(repl, new)
            if new != text:
                with open(path, "w", encoding="latin-1") as f:
                    f.write(new)
                changed += 1
    print("bsd_aarch32 includes added to %d files" % changed)


def apply_patches():
    for rel, old, new, expected in REPLACE_ALL:
        path = os.path.join(ROOT, rel)
        with open(path, encoding="latin-1") as f:
            text = f.read()
        count = text.count(old)
        if count != expected:
            sys.exit("ios_patch: %s: expected the text %d times, found it %d times:\n%s" % (rel, expected, count, old))
        with open(path, "w", encoding="latin-1") as f:
            f.write(text.replace(old, new))
    for rel, old, new in PATCHES:
        path = os.path.join(ROOT, rel)
        with open(path, encoding="latin-1") as f:
            text = f.read()
        count = text.count(old)
        if count != 1:
            sys.exit("ios_patch: %s: expected the text once, found it %d times:\n%s" % (rel, count, old))
        with open(path, "w", encoding="latin-1") as f:
            f.write(text.replace(old, new))
    print("%d targeted patches applied" % len(PATCHES))


add_os_arch_includes()
apply_patches()
