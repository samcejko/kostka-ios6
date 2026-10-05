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

# (file relative to the tree, exact text, replacement)
PATCHES = [
]


def add_os_arch_includes():
    block = re.compile(r'(#ifdef TARGET_OS_ARCH_bsd_x86\n((?:# *include "[^"]*"\n)+)#endif\n)')
    changed = 0
    for dirpath, _, files in os.walk(HS):
        for name in files:
            if not name.endswith((".hpp", ".cpp", ".h", ".inline.hpp")):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="latin-1") as f:
                text = f.read()
            if "TARGET_OS_ARCH_bsd_x86" not in text or "TARGET_OS_ARCH_bsd_aarch32" in text:
                continue

            def repl(m):
                includes = m.group(2).replace("bsd_x86", "bsd_aarch32")
                return m.group(1) + "#ifdef TARGET_OS_ARCH_bsd_aarch32\n" + includes + "#endif\n"

            new, n = block.subn(repl, text)
            if n:
                with open(path, "w", encoding="latin-1") as f:
                    f.write(new)
                changed += 1
    print("bsd_aarch32 includes added to %d files" % changed)


def apply_patches():
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
