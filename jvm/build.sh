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
}

# 4. HotSpot: the client VM (template interpreter and C1), serial GC only, no JFR/CDS
HS_DEFINES="-DDONT_USE_PRECOMPILED_HEADER -DPRODUCT -DCOMPILER1 -DVM_LITTLE_ENDIAN \
 -D_ALLBSD_SOURCE -D_GNU_SOURCE -D_XOPEN_SOURCE -D_DARWIN_C_SOURCE -D_REENTRANT -DALLOW_OPERATOR_NEW_USAGE \
 -DAARCH32 -DARM -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS \
 -DTARGET_OS_FAMILY_bsd -DTARGET_ARCH_aarch32 -DTARGET_ARCH_MODEL_aarch32 -DTARGET_OS_ARCH_bsd_aarch32 \
 -DTARGET_OS_ARCH_MODEL_bsd_aarch32 -DTARGET_COMPILER_gcc \
 -DINCLUDE_JFR=0 -DINCLUDE_ALL_GCS=0 -DINCLUDE_CDS=0 \
 -DHOTSPOT_RELEASE_VERSION='\"$HS_VERSION\"' -DHOTSPOT_BUILD_TARGET='\"product\"' -DHOTSPOT_BUILD_USER='\"kostka\"' \
 -DHOTSPOT_LIB_ARCH='\"arm\"' -DHOTSPOT_VM_DISTRO='\"OpenJDK\"' -DJRE_RELEASE_VERSION='\"$JRE_VERSION\"' \
 -DDEFAULT_LIBPATH='\"/usr/lib\"'"
HS_FLAGS="-marm -std=gnu++98 -fno-rtti -fno-exceptions -fno-strict-aliasing -fno-omit-frame-pointer -fwrapv \
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
           "*zero*", "*shark*", "ciTypeFlow.cpp", "chaitin*", "*x86*", "aarch32Test.cpp",
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
    step "linking libjvm.dylib"
    mkdir -p "$JRE/lib/arm/client"
    $TC/clang++ $TARGET -dynamiclib -install_name @rpath/libjvm.dylib -compatibility_version 1.0.0 -current_version 1.0.0 \
        -o "$JRE/lib/arm/client/libjvm.dylib" "$objdir"/*.o -lc++ -lm > "$LOGS/hotspot-link.log" 2>&1
    local ls=$?
    cat "$LOGS/hotspot-link.log" | head -n 80
    [ $ls -eq 0 ] || return 1
    ls -la "$JRE/lib/arm/client/libjvm.dylib"
}

case "${1:-all}" in
    fetch) fetch ;;
    prepare) fetch && prepare ;;
    jvmti) jvmti ;;
    hotspot) fetch && prepare && jvmti && hotspot ;;
    all) fetch && prepare && jvmti && hotspot ;;
    *) echo "unknown step $1"; exit 2 ;;
esac
