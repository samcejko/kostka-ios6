# Java 8 for iOS 6 (armv7)

The Java runtime Kostka runs Minecraft with: **HotSpot**, the Java VM of OpenJDK 8, from the
[AArch32 port](https://openjdk.org/projects/aarch32-port/) (32-bit ARM: the template interpreter and the C1 JIT
compiler - the "client" VM), ported here to **iOS 6 (Darwin, armv7)**, with the JDK's native libraries; the Java
classes (`rt.jar` ...) are those of [Amazon Corretto 8](https://aws.amazon.com/corretto/) for macOS, the same
update (8u504).

`build.sh` cross-compiles it on Linux with Theos' iOS toolchain (the iOS 9.3 SDK, deployment target 6.0); CI runs it
in `.github/workflows/jre.yml`. The result has the macOS layout HotSpot expects on Darwin:
`jre/lib/client/libjvm.dylib`, `jre/lib/libjava.dylib` ..., `jre/lib/rt.jar`.

## The port

- `hotspot/src/os_cpu/bsd_aarch32/` - what differs from the Linux AArch32 files: the signal handler (32-bit Darwin
  reports most memory faults as SIGBUS; the registers of a signal's context; HotSpot built in ARM mode so it only
  ever continues at ARM code), the thread stacks (pthread_get_stackaddr_np), the byte swaps, the clock, 64-bit
  atomics on 4-byte aligned longs, and **lazy direct memory** (`lazyMemory_bsd_aarch32.cpp`): a large block of
  `Unsafe.allocateMemory` is zeroed without bringing its untouched pages into memory, as games ask for large direct
  buffers and fill them in part (old Minecraft's sound: 32 of 5 MB), and iOS 6 has no swap. The other files of
  `os_cpu/bsd_aarch32` are the Linux ones, renamed by `build.sh`.
- `ios_patch.py` - the changes to OpenJDK's own files, each checked to apply exactly once:
  - **Darwin's calling convention for native code** (APCS, soft-float): a `long` or `double` argument takes the next
    two words, unaligned, and may be split between `r3` and the stack (Linux puts it in an even register pair or
    at an 8-byte aligned slot) - in the compiled native wrappers and the interpreter's signature handlers;
  - the shared headers' lists of OS/CPU files get the `bsd_aarch32` entries;
  - what the iOS SDK lacks: `finite`, `__thread` (before iOS 8), `crt_externs.h`, `sys/proc_info.h`,
    `__clear_cache` (`sys_icache_invalidate` instead), `SCDynamicStore`, `AuthSession`;
  - `os.name` is "iPhone OS X", not "Mac OS X": programs that see a Mac load Mac libraries (Minecraft 1.12's
    narrator: JNA's, then AppKit's speech), while the JDK's own classes look for "OS X" in the name;
  - `Unsafe`'s memory calls tell the lazy direct memory of each block.
- Left out: the C2 compiler, the G1/CMS/Parallel collectors (serial GC only), JFR, CDS, the Serviceability Agent.

What the device test (`kostka:probe`) found on an iPad 2 makes this possible: a jailbroken iOS 6 lets an app outside
the container sandbox (`/Applications`) map memory read-write-execute and run code generated in it, and a signal
handler can take over a fault in such code.

## License

The files in `hotspot/` and the patched OpenJDK sources are under the **GNU General Public License, version 2, with
the Classpath exception** (OpenJDK's license); `build.sh` and `ios_patch.py` are MIT, like the rest of Kostka. The
built runtime carries OpenJDK's and Corretto's `LICENSE`, `ASSEMBLY_EXCEPTION` and `THIRD_PARTY_README`.
