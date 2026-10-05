#!/bin/bash
# Kostka's Java runtime for iOS 6 (armv7): HotSpot from the AArch32 port of OpenJDK 8 (the client VM: template
# interpreter + C1), ported to Darwin, and the JDK's native libraries, cross-compiled on Linux with Theos' iOS
# toolchain. The Java classes (rt.jar ...) are those of Amazon Corretto 8 for macOS, the same update.
#
#   THEOS=/path/to/theos jvm/build.sh [fetch|prepare|jvmti|hotspot|all]
#
# Output: jvm/out/jre (lib/arm/client/libjvm.dylib, ...). Compiler errors: jvm/out/logs/*.log
set -uo pipefail

JDK_TAG="${JDK_TAG:-jdk8u504-ga-aarch32-20260819}"
HS_VERSION="${HS_VERSION:-25.504-b01}"
JRE_VERSION="${JRE_VERSION:-1.8.0_504}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-$HERE/out}"
SRC="$OUT/src"
GEN="$OUT/gen"
OBJ="$OUT/obj"
LOGS="$OUT/logs"
JRE="$OUT/jre"
SDK="$THEOS/sdks/iPhoneOS9.3.sdk"
TC="$THEOS/toolchain/linux/iphone/bin"
JOBS="${JOBS:-$(nproc)}"
HOST_JAVA_HOME="${HOST_JAVA_HOME:-${JAVA_HOME_8_X64:-${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}}}"
export PATH="$TC:$PATH"

CCACHE="$(command -v ccache || true)"
TARGET="-target armv7-apple-ios6.0 -isysroot $SDK -miphoneos-version-min=6.0"
CC="$CCACHE $TC/clang $TARGET"
CXX="$CCACHE $TC/clang++ $TARGET"
mkdir -p "$OUT" "$GEN" "$OBJ" "$LOGS" "$JRE"

step() { echo; echo "=== $*"; }

# 1. The sources: only the parts needed (HotSpot, the JDK's native code and its headers)
fetch() {
    if [ -f "$SRC/.kostka-fetched-$JDK_TAG" ]; then echo "sources $JDK_TAG: cached"; return 0; fi
    step "fetching $JDK_TAG"
    rm -rf "$SRC"
    git clone --quiet --depth 1 --branch "$JDK_TAG" --filter=blob:none --sparse \
        https://github.com/openjdk/aarch32-port-jdk8u "$SRC" || return 1
    (cd "$SRC" && git sparse-checkout set --no-cone /hotspot/src/ /hotspot/make/bsd/makefiles/mapfile-vers-product \
        /jdk/src/share/native/ /jdk/src/share/javavm/ /jdk/src/solaris/native/ /jdk/src/solaris/javavm/ \
        /jdk/src/macosx/native/ /jdk/src/macosx/javavm/ /jdk/make/mapfiles/) || return 1
    touch "$SRC/.kostka-fetched-$JDK_TAG"
}

# 2. The Darwin port: os_cpu/bsd_aarch32 (renamed from the Linux files, the ones that differ are ours), patches
prepare() {
    step "preparing the iOS port"
    (cd "$SRC" && git checkout --quiet -- . && git clean -fdq hotspot/src/os_cpu) || return 1
    local hs="$SRC/hotspot/src" dst="$SRC/hotspot/src/os_cpu/bsd_aarch32/vm"
    mkdir -p "$dst"
    local f b nb
    for f in "$hs"/os_cpu/linux_aarch32/vm/*; do
        b="$(basename "$f")"
        nb="${b//linux_aarch32/bsd_aarch32}"
        [ -e "$HERE/hotspot/src/os_cpu/bsd_aarch32/vm/$nb" ] && continue
        case "$nb" in *.s|*.ad) continue ;; esac
        sed -e 's/linux_aarch32/bsd_aarch32/g; s/LINUX_AARCH32/BSD_AARCH32/g; s/os::Linux::/os::Bsd::/g' "$f" > "$dst/$nb"
    done
    cp "$HERE"/hotspot/src/os_cpu/bsd_aarch32/vm/* "$dst/"
    ls "$dst"
    python3 "$HERE/ios_patch.py" "$SRC" || return 1
}

# 3. JVMTI's generated sources (XSLT run by HotSpot's own tool, on the build machine's Java)
jvmti() {
    step "generating the JVMTI sources (host Java: $HOST_JAVA_HOME)"
    local prims="$SRC/hotspot/src/share/vm/prims" out="$GEN/jvmtifiles"
    mkdir -p "$out"
    "$HOST_JAVA_HOME/bin/javac" -d "$out" "$prims/jvmtiGen.java" "$prims/jvmtiEnvFill.java" || return 1
    local gen="$HOST_JAVA_HOME/bin/java -classpath $out jvmtiGen -IN $prims/jvmti.xml"
    $gen -XSL "$prims/jvmtiEnter.xsl" -OUT "$out/jvmtiEnter.cpp" -PARAM interface jvmti || return 1
    $gen -XSL "$prims/jvmtiEnter.xsl" -OUT "$out/jvmtiEnterTrace.cpp" -PARAM interface jvmti -PARAM trace Trace || return 1
    $gen -XSL "$prims/jvmtiHpp.xsl" -OUT "$out/jvmtiEnv.hpp" || return 1
    $gen -XSL "$prims/jvmtiH.xsl" -OUT "$out/jvmti.h" || return 1
    ls -la "$out"
    # JFR's event classes: needed even with JFR left out (they are then empty)
    local jfr="$SRC/hotspot/src/share/vm/jfr" jout="$GEN/jfrfiles" jtools="$GEN/tools/jfr"
    mkdir -p "$jout" "$jtools"
    "$HOST_JAVA_HOME/bin/javac" -d "$jtools" "$jfr/GenerateJfrFiles.java" || return 1
    "$HOST_JAVA_HOME/bin/java" -cp "$jtools" build.tools.jfr.GenerateJfrFiles "$jfr/metadata/metadata.xml" \
        "$jfr/metadata/metadata.xsd" "$jout" || return 1
    ls -la "$jout"
}

# 4. HotSpot: the client VM (template interpreter and C1), serial GC only, no JFR/CDS
HS_DEFINES="-DDONT_USE_PRECOMPILED_HEADER -DPRODUCT -DCOMPILER1 -DVM_LITTLE_ENDIAN \
 -D_ALLBSD_SOURCE -D_GNU_SOURCE -D_XOPEN_SOURCE -D_DARWIN_C_SOURCE -D_REENTRANT -DALLOW_OPERATOR_NEW_USAGE \
 -DAARCH32 -DARM -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS \
 -DTARGET_OS_FAMILY_bsd -DTARGET_ARCH_aarch32 -DTARGET_ARCH_MODEL_aarch32 -DTARGET_OS_ARCH_bsd_aarch32 \
 -DTARGET_OS_ARCH_MODEL_bsd_aarch32 -DTARGET_COMPILER_gcc \
 -DINCLUDE_JFR=0 -DINCLUDE_ALL_GCS=0 -DINCLUDE_CDS=0 -DINCLUDE_VM_STRUCTS=0 \
 -DHOTSPOT_RELEASE_VERSION='\"$HS_VERSION\"' -DHOTSPOT_BUILD_TARGET='\"product\"' -DHOTSPOT_BUILD_USER='\"kostka\"' \
 -DHOTSPOT_LIB_ARCH='\"arm\"' -DHOTSPOT_VM_DISTRO='\"OpenJDK\"' -DJRE_RELEASE_VERSION='\"$JRE_VERSION\"' \
 -DDEFAULT_LIBPATH='\"/usr/lib\"'"
# (-fno-threadsafe-statics: no __cxa_guard_* imported from a C++ runtime, see cxxRuntime_bsd_aarch32.cpp)
HS_FLAGS="-marm -std=gnu++98 -fno-rtti -fno-exceptions -fno-threadsafe-statics -fno-strict-aliasing -fno-omit-frame-pointer -fwrapv \
 -fno-delete-null-pointer-checks -fPIC -fvisibility=hidden -pthread -O2 -g0 -w"

hotspot_sources() {
    local hs="$SRC/hotspot/src"
    {
        # share/vm minus the compiler-2/Shark/adlc/JFR directories (as hotspot/make/bsd/makefiles/vm.make)
        find "$hs/share/vm" \( -name jfr -o -name adlc -o -name opto -o -name shark -o -name libadt \) -prune -o -name '*.cpp' -print
        find "$hs/os/bsd/vm" "$hs/os/posix/vm" "$hs/cpu/aarch32/vm" "$hs/os_cpu/bsd_aarch32/vm" -maxdepth 1 -name '*.cpp'
        echo "$GEN/jvmtifiles/jvmtiEnter.cpp"
        echo "$GEN/jvmtifiles/jvmtiEnterTrace.cpp"
    } | python3 -c '
import os, sys, fnmatch
# hotspot/make/bsd/makefiles/vm.make and make/excludeSrc.make: client VM, INCLUDE_ALL_GCS=0, INCLUDE_CDS=0, INCLUDE_JFR=0
exclude = ["jsig.c", "jvmtiEnvRecommended.cpp", "jvmtiEnvStub.cpp", "bcEscapeAnalyzer.cpp", "c2_*", "runtime_*",
           "*zero*", "*shark*", "ciTypeFlow.cpp", "chaitin*", "*x86*", "os_perf_*.cpp", "vmStructs.cpp",
           "filemap.cpp", "metaspaceShared*.cpp", "sharedPathsMiscInfo.cpp", "systemDictionaryShared.cpp",
           "classLoaderExt.cpp", "sharedClassUtil.cpp", "g1MemoryPool.cpp", "psMemoryPool.cpp"]
gc_keep = ["adaptiveSizePolicy.cpp", "ageTable.cpp", "ageTableTracer.cpp", "collectorCounters.cpp", "cSpaceCounters.cpp",
           "gcId.cpp", "gcPolicyCounters.cpp", "gcStats.cpp", "gcTimer.cpp", "gcTrace.cpp", "gcTraceSend.cpp",
           "gcTraceTime.cpp", "gcUtil.cpp", "generationCounters.cpp", "markSweep.cpp", "objectCountEventSender.cpp",
           "spaceDecorator.cpp", "vmGCOperations.cpp"]
seen = set()
for line in sys.stdin:
    p = line.strip()
    b = os.path.basename(p)
    parts = p.split("/")
    if any(fnmatch.fnmatch(b, e) for e in exclude):
        continue
    if "gc_implementation" in parts:
        sub = parts[parts.index("gc_implementation") + 1]
        if sub in ("concurrentMarkSweep", "g1", "parallelScavenge", "parNew"):
            continue
        if sub == "shared" and b not in gc_keep:
            continue
    if b in seen:
        sys.exit("duplicate source name " + b)
    seen.add(b)
    print(p)
'
}

hotspot() {
    step "compiling HotSpot ($JOBS jobs, ccache: ${CCACHE:-none})"
    local hs="$SRC/hotspot/src" list="$OUT/hotspot.list" mk="$OUT/hotspot.mk" objdir="$OBJ/hotspot"
    mkdir -p "$objdir"
    hotspot_sources > "$list" || return 1
    echo "$(wc -l < "$list") sources"
    local inc="-I$hs/share/vm -I$hs/share/vm/precompiled -I$hs/share/vm/prims -I$hs/cpu/aarch32/vm \
 -I$hs/os_cpu/bsd_aarch32/vm -I$hs/os/bsd/vm -I$hs/os/posix/vm -I$GEN -I$GEN/jvmtifiles"
    {
        echo "CXX := $CXX"
        echo "CXXFLAGS := $HS_FLAGS $HS_DEFINES $inc"
        # (fdlibm's copies must not be optimized: hotspot/make/linux/makefiles/aarch32.make)
        echo "FLAGS_sharedRuntimeTrig.o := -O0"
        echo "FLAGS_sharedRuntimeTrans.o := -O0"
        printf 'OBJS :='
        while read -r s; do b="$(basename "$s")"; printf ' %s/%s.o' "$objdir" "${b%.*}"; done < "$list"
        echo
        echo 'all: $(OBJS)'
        while read -r s; do
            b="$(basename "$s")"
            printf '%s/%s.o: %s\n\t@$(CXX) $(CXXFLAGS) $(FLAGS_$(notdir $@)) -c $< -o $@ 2> $@.err || { cat $@.err; exit 1; }\n' "$objdir" "${b%.*}" "$s"
        done < "$list"
    } > "$mk"
    make -k -j"$JOBS" -f "$mk" all > "$LOGS/hotspot-compile.log" 2>&1
    local status=$?
    local failed
    failed=$(grep -c ' error: ' "$LOGS/hotspot-compile.log" || true)
    echo "compile status $status, $failed errors"
    if [ $status -ne 0 ]; then
        grep -E ' error: ' "$LOGS/hotspot-compile.log" | sort | uniq -c | sort -rn | head -n 60
        echo "--- first errors in context:"
        grep -B2 -A6 -m 25 ' error: ' "$LOGS/hotspot-compile.log" | head -n 250
        return 1
    fi
    # (the macOS layout, which os_bsd.cpp expects on Darwin: <java.home>/lib/client/libjvm.dylib, the JDK's
    # libraries in <java.home>/lib)
    step "linking libjvm.dylib"
    mkdir -p "$JRE/lib/client"
    $TC/clang++ $TARGET -dynamiclib -install_name @rpath/libjvm.dylib -compatibility_version 1.0.0 -current_version 1.0.0 \
        -o "$JRE/lib/client/libjvm.dylib" "$objdir"/*.o -lc++ -lc++abi -lm > "$LOGS/hotspot-link.log" 2>&1
    local ls=$?
    # (the SDK's .tbd files make ld warn about the simulator on every line: only the rest is worth showing)
    grep -v 'built for iOS Simulator' "$LOGS/hotspot-link.log" | head -n 80
    [ $ls -eq 0 ] || return 1
    ls -la "$JRE/lib/client/libjvm.dylib"
    # What libjvm takes from the system: iOS 6 must have every one of these (dyld refuses the library otherwise)
    local nm; nm="$(command -v "$TC/nm" || command -v "$TC/llvm-nm" || command -v nm || true)"
    if [ -n "$nm" ]; then
        "$nm" -u "$JRE/lib/client/libjvm.dylib" > "$LOGS/libjvm-imports.txt" 2>&1
        echo "$(wc -l < "$LOGS/libjvm-imports.txt") imported symbols; C++ runtime ones:"
        grep -E '__Z|___cxa|__Unwind|___gxx' "$LOGS/libjvm-imports.txt" | head -n 40
    fi
}

# 5. The Java classes: Amazon Corretto 8 for macOS, the same update (its natives are x86_64: not used)
CORRETTO="${CORRETTO:-8.504.04.1}"
corretto() {
    local dir="$OUT/corretto"
    if [ -f "$dir/.done-$CORRETTO" ]; then echo "Corretto $CORRETTO: cached"; return 0; fi
    step "fetching Corretto $CORRETTO (macOS)"
    rm -rf "$dir"; mkdir -p "$dir"
    curl -sSfL "https://corretto.aws/downloads/resources/$CORRETTO/amazon-corretto-$CORRETTO-macosx-x64.tar.gz" | tar -xz -C "$dir" || return 1
    touch "$dir/.done-$CORRETTO"
}
corretto_home() { find "$OUT/corretto" -maxdepth 4 -type d -name Home | head -n1; }

# The JNI headers the given sources include ("java_lang_Float.h"), made by javah from Corretto's classes
jni_headers() {
    local home cp classes c
    home="$(corretto_home)"
    cp="$home/jre/lib/rt.jar:$(ls "$home"/jre/lib/ext/*.jar | tr '\n' ':')"
    mkdir -p "$GEN/jni"
    classes=$(python3 - "$GEN/jni" "$@" <<'PY'
import os, re, sys
out, names = sys.argv[1], set()
for f in sys.argv[2:]:
    for m in re.finditer(r'#\s*include\s*"([A-Za-z0-9_]+)\.h"', open(f, encoding="latin-1").read()):
        n = m.group(1)
        if n.split("_")[0] in ("java", "javax", "sun", "jdk", "com", "apple") and "_" in n:
            names.add(n)
for n in sorted(names):
    if not os.path.exists(os.path.join(out, n + ".h")):
        print(n.replace("_00024", "$").replace("_1", "\x01").replace("_", ".").replace("\x01", "_"))
PY
)
    for c in $classes; do
        "$HOST_JAVA_HOME/bin/javah" -bootclasspath "$cp" -d "$GEN/jni" "$c" 2>/dev/null || echo "javah: no class $c"
    done
}

J_SRC() { echo "$SRC/jdk/src"; }
JDK_CFLAGS() {
    local j; j="$(J_SRC)"
    echo "-O2 -fPIC -fno-strict-aliasing -w -D_ALLBSD_SOURCE -DMACOSX -D_DARWIN_UNLIMITED_SELECT -D_LITTLE_ENDIAN \
 -DARCH='\"arm\"' -DRELEASE='\"$JRE_VERSION\"' -DARCHPROPNAME='\"arm\"' \
 -DJDK_MAJOR_VERSION='\"1\"' -DJDK_MINOR_VERSION='\"8\"' -DJDK_MICRO_VERSION='\"0\"' -DJDK_UPDATE_VERSION='\"504\"' \
 -DJDK_BUILD_NUMBER='\"b01\"' \
 -I$GEN/jni -I$j/share/javavm/export -I$j/macosx/javavm/export -I$j/solaris/javavm/export -idirafter $GEN/ios-include \
 -I$j/share/native/common -I$j/solaris/native/common"
}

# native_lib <name> "<sources>" "<cflags>" "<ldflags>": lib<name>.dylib in <java.home>/lib
native_lib() {
    local name="$1" srcs="$2" cflags="$3" ldflags="$4"
    local objdir="$OBJ/lib$name" mk="$OUT/lib$name.mk" s o
    step "lib$name ($(echo $srcs | wc -w) sources)"
    mkdir -p "$objdir" "$JRE/lib"
    jni_headers $srcs
    {
        echo "CC := $CC"
        echo "CFLAGS := $(JDK_CFLAGS) $cflags"
        printf 'OBJS :='
        for s in $srcs; do o="${s#$SRC/}"; printf ' %s/%s.o' "$objdir" "${o//\//_}"; done
        echo
        echo 'all: $(OBJS)'
        for s in $srcs; do
            o="${s#$SRC/}"
            local lang=""
            case "$s" in *.m|*/java_props_md.c|*/java_props_macosx.c) lang="-x objective-c" ;; esac
            printf '%s/%s.o: %s\n\t@$(CC) $(CFLAGS) %s -c $< -o $@ 2> $@.err || { cat $@.err; exit 1; }\n' "$objdir" "${o//\//_}" "$s" "$lang"
        done
    } > "$mk"
    make -k -j"$JOBS" -f "$mk" all > "$LOGS/lib$name-compile.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "lib$name: compile errors"
        grep -B2 -A6 -m 30 ' error: ' "$LOGS/lib$name-compile.log" | head -n 200
        return 1
    fi
    $TC/clang $TARGET -dynamiclib -install_name "@rpath/lib$name.dylib" -compatibility_version 1.0.0 -current_version 1.0.0 \
        -o "$JRE/lib/lib$name.dylib" "$objdir"/*.o -L"$JRE/lib" -L"$JRE/lib/client" \
        -Wl,-rpath,@loader_path -Wl,-rpath,@loader_path/client $ldflags > "$LOGS/lib$name-link.log" 2>&1
    if [ $? -ne 0 ]; then echo "lib$name: link errors"; head -n 80 "$LOGS/lib$name-link.log"; return 1; fi
    ls -la "$JRE/lib/lib$name.dylib"
}

jdklibs() {
    local j; j="$(J_SRC)"
    # fdlibm (StrictMath), not optimized (as the JDK builds it), linked into libjava
    local fd="$OBJ/fdlibm" s
    mkdir -p "$fd"
    for s in "$j"/share/native/java/lang/fdlibm/src/*.c; do
        # (eval: the flags hold quoted string defines, as a Makefile's shell would read them)
        eval "$CC $(JDK_CFLAGS) -O0 -I'$j/share/native/java/lang/fdlibm/include' -c '$s' -o '$fd/$(basename "${s%.c}").o'" || return 1
    done

    native_lib verify "$j/share/native/common/check_code.c $j/share/native/common/check_format.c" "" "-ljvm" || return 1

    local dirs="solaris/native/java/lang share/native/java/lang share/native/java/lang/reflect share/native/java/io
 solaris/native/java/io share/native/java/nio share/native/java/security share/native/common share/native/sun/misc
 share/native/sun/reflect share/native/java/util share/native/java/util/concurrent/atomic solaris/native/common
 solaris/native/java/util macosx/native/sun/util/locale/provider"
    local d inc="" srcs
    for d in $dirs; do inc="$inc -I$j/$d"; done
    srcs=$(for d in $dirs; do find "$j/$d" \( -path '*/fdlibm/src' -o -name zip \) -prune -o \( -name '*.c' -o -name '*.m' \) -print; done | sort -u |
        grep -vE '/(check_code|check_format|jspawnhelper|ProcessImpl_md|WinNTFileSystem_md|dirent_md|WindowsPreferences|WinCAPISeedGenerator|Win32ErrorMode)\.c$')
    native_lib java "$srcs" "$inc -I$j/share/native/java/lang/fdlibm/include" \
        "$fd/*.o -ljvm -lverify -framework CoreFoundation -framework Foundation -framework Security -framework SystemConfiguration" || return 1

    srcs=$(find "$j/share/native/java/util/zip" -name zlib -prune -o -name '*.c' -print)
    native_lib zip "$srcs" "-DUSE_MMAP -I$j/share/native/java/util/zip -I$j/share/native/java/io -I$j/solaris/native/java/io" \
        "-ljava -ljvm -lz" || return 1

    # (network headers the iOS SDK leaves out and the macOS one has: from Apple's open source XNU of the iOS 6 era)
    local xnu="https://raw.githubusercontent.com/apple-oss-distributions/xnu/xnu-2050.48.11" hdr
    for hdr in netinet/ip_icmp.h netinet/icmp6.h net/if_arp.h; do
        mkdir -p "$GEN/ios-include/$(dirname "$hdr")"
        [ -f "$GEN/ios-include/$hdr" ] || curl -sSfL "$xnu/bsd/$hdr" -o "$GEN/ios-include/$hdr" || return 1
    done

    # libnet (jdk/make/lib/NetworkingLibraries.gmk, macosx)
    dirs="share/native/java/net solaris/native/java/net solaris/native/sun/net"
    inc=""
    for d in $dirs solaris/native/sun/net/dns solaris/native/sun/net/spi solaris/native/sun/net/sdp; do inc="$inc -I$j/$d"; done
    srcs=$(for d in $dirs; do find "$j/$d" -name '*.c'; done | sort -u |
        grep -vE '/(linux_close|TwoStacksPlainSocketImpl|DualStackPlainSocketImpl|TwoStacksPlainDatagramSocketImpl|DualStackPlainDatagramSocketImpl|NTLMAuthSequence|NetworkInterface_winXP|NetworkInterface)\.c$')
    # (NetworkInterface.c - listing the network interfaces - wants kernel headers iOS has not; nothing needs it yet)
    native_lib net "$srcs" "$inc -I$j/share/native/java/io -I$j/solaris/native/java/io" "-ljvm -ljava" || return 1

    # libnio (jdk/make/lib/NioLibraries.gmk, macosx: only the files listed there)
    local f files="DatagramChannelImpl DatagramDispatcher FileChannelImpl FileDispatcherImpl FileKey IOUtil MappedByteBuffer Net
 ServerSocketChannelImpl SocketChannelImpl SocketDispatcher InheritedChannel NativeThread PollArrayWrapper
 UnixAsynchronousServerSocketChannelImpl UnixAsynchronousSocketChannelImpl BsdNativeDispatcher MacOSXNativeDispatcher
 UnixCopyFile UnixNativeDispatcher KQueue KQueuePort KQueueArrayWrapper"
    srcs=""
    for f in $files; do
        srcs="$srcs $(find "$j/solaris/native/java/nio" "$j/solaris/native/sun/nio/ch" "$j/solaris/native/sun/nio/fs" \
            "$j/macosx/native/sun/nio/ch" -name "$f.c" | head -n1)"
    done
    native_lib nio "$srcs" "-I$j/share/native/sun/nio/ch -I$j/share/native/java/io -I$j/share/native/java/net \
 -I$j/solaris/native/java/net -I$j/solaris/native/sun/nio/ch -I$j/solaris/native/sun/nio/fs -I$j/solaris/native/java/io" \
        "-ljava -lnet -ljvm -framework CoreFoundation" || return 1
}

# 6. The runtime's other files: Corretto's lib folder without its (x86_64) native code and what an iPad has no use for
runtime() {
    step "assembling the runtime"
    local home; home="$(corretto_home)"
    rsync -a --exclude '*.dylib' --exclude 'jli' --exclude 'server' --exclude '*.jsa' --exclude 'jspawnhelper' \
        --exclude 'nashorn.jar' --exclude 'cldrdata.jar' --exclude 'jfr*' --exclude 'deploy*' --exclude 'javafx*' \
        --exclude 'ant-javafx.jar' --exclude 'jexec' --exclude '*.framework' --exclude 'applet' \
        "$home/jre/lib/" "$JRE/lib/" || return 1
    # (the runtime's licenses: GPL v2 with the Classpath exception, and the third parties' notices)
    local f
    for f in LICENSE ASSEMBLY_EXCEPTION THIRD_PARTY_README; do
        [ -f "$home/$f" ] && cp "$home/$f" "$JRE/$f"
    done
    cp "$HERE/README.md" "$JRE/README-Kostka.md" 2>/dev/null || true
    # (iOS loads no code without a signature: the pseudo-signature of ldid, as for the app itself)
    local lib
    for lib in $(find "$JRE" -name '*.dylib'); do
        "$TC/ldid" -S "$lib" || return 1
    done
    du -sh "$JRE"
    find "$JRE" -maxdepth 2 | sort | head -n 80
}

case "${1:-all}" in
    fetch) fetch ;;
    prepare) fetch && prepare ;;
    jvmti) jvmti ;;
    hotspot) fetch && prepare && jvmti && hotspot ;;
    jdk) corretto && jdklibs && runtime ;;
    all) fetch && prepare && jvmti && hotspot && corretto && jdklibs && runtime ;;
    *) echo "unknown step $1"; exit 2 ;;
esac
