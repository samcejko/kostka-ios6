#!/bin/bash
# Kostka's LWJGL 2 for iOS 6 (armv7): LWJGL 2.9.4 (its last sources) with an iOS backend in place of the Mac OS X
# one - iOS reports os.name "Mac OS X", so LWJGL takes its Mac classes, and Kostka's replace them (java/) - and
# gl4es under it, for the desktop OpenGL of the games on the iPad's OpenGL ES 2.0. Cross-compiled on Linux with
# Theos' iOS toolchain, like the Java runtime (jvm/build.sh).
#
#   THEOS=/path/to/theos lwjgl/build.sh [fetch|java|natives|all]
#
# Output: lwjgl/out/lwjgl (lwjgl.jar, lwjgl_util.jar, liblwjgl.dylib, gltest.jar). Errors: lwjgl/out/logs/*.log
set -uo pipefail

LWJGL_COMMIT="${LWJGL_COMMIT:-2df01dd762e20ca0871edb75daf670ccacc89b60}"
GL4ES_COMMIT="${GL4ES_COMMIT:-ec16bedd8819c475326f4f1a3063772c6d986e06}"
JDK_TAG="${JDK_TAG:-jdk8u504-ga-aarch32-20260819}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-$HERE/out}"
LW="$OUT/src/lwjgl"
G4="$OUT/src/gl4es"
GEN="$OUT/gen"
OBJ="$OUT/obj"
LOGS="$OUT/logs"
DIST="$OUT/lwjgl"
SDK="$THEOS/sdks/iPhoneOS9.3.sdk"
TC="$THEOS/toolchain/linux/iphone/bin"
JOBS="${JOBS:-$(nproc)}"
HOST_JAVA_HOME="${HOST_JAVA_HOME:-${JAVA_HOME_8_X64:-${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}}}"

CCACHE="$(command -v ccache || true)"
TARGET="-target armv7-apple-ios6.0 -isysroot $SDK -miphoneos-version-min=6.0"
CC="$CCACHE $TC/clang $TARGET"
mkdir -p "$OUT/src" "$GEN" "$OBJ" "$LOGS" "$DIST"

step() { echo; echo "=== $*"; }

# 1. The sources: LWJGL 2 and gl4es at fixed commits, and the JNI headers of the Java runtime's OpenJDK
fetch() {
    if [ ! -f "$LW/.kostka-$LWJGL_COMMIT" ]; then
        step "fetching LWJGL $LWJGL_COMMIT"
        rm -rf "$LW" && mkdir -p "$LW"
        curl -sSfL "https://codeload.github.com/LWJGL/lwjgl/tar.gz/$LWJGL_COMMIT" | tar -xz -C "$LW" --strip-components=1 || return 1
        touch "$LW/.kostka-$LWJGL_COMMIT"
    fi
    if [ ! -f "$G4/.kostka-$GL4ES_COMMIT" ]; then
        step "fetching gl4es $GL4ES_COMMIT"
        rm -rf "$G4" && mkdir -p "$G4"
        # (only the library: its repository also holds traces of games for its tests)
        curl -sSfL "https://codeload.github.com/ptitSeb/gl4es/tar.gz/$GL4ES_COMMIT" |
            tar -xz -C "$G4" --strip-components=1 --wildcards '*/src/*' '*/include/*' '*/version.h' '*/LICENSE' || return 1
        touch "$G4/.kostka-$GL4ES_COMMIT"
    fi
    mkdir -p "$GEN/jni"
    local base="https://raw.githubusercontent.com/openjdk/aarch32-port-jdk8u/$JDK_TAG/jdk/src"
    [ -f "$GEN/jni/jni.h" ] || curl -sSfL "$base/share/javavm/export/jni.h" -o "$GEN/jni/jni.h" || return 1
    [ -f "$GEN/jni/jni_md.h" ] || curl -sSfL "$base/solaris/javavm/export/jni_md.h" -o "$GEN/jni/jni_md.h" || return 1
}

# 2. The Java side: LWJGL's generator (OpenGL and OpenAL bindings, Java and C), its classes with Kostka's iOS
#    ones in place of the Mac OS X ones, the JNI headers, the jars; and the test program
lwjgl_java() {
    step "LWJGL's classes, with the iOS backend"
    cp -r "$HERE/java/org" "$LW/src/java/" || return 1
    (cd "$LW" && JAVA_HOME="$HOST_JAVA_HOME" PATH="$HOST_JAVA_HOME/bin:$PATH" ant -noinput jars headers) > "$LOGS/ant.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "ant failed"
        grep -E 'error:|BUILD FAILED|cannot find|\[javac\].*\.java:[0-9]+' "$LOGS/ant.log" | head -n 120
        tail -n 40 "$LOGS/ant.log"
        return 1
    fi
    cp "$LW/libs/lwjgl.jar" "$LW/libs/lwjgl_util.jar" "$DIST/" || return 1

    rm -rf "$OUT/test" && mkdir -p "$OUT/test"
    "$HOST_JAVA_HOME/bin/javac" -source 1.6 -target 1.6 -nowarn -cp "$DIST/lwjgl.jar" -d "$OUT/test" "$HERE"/test/*.java || return 1
    (cd "$OUT/test" && "$HOST_JAVA_HOME/bin/jar" cf "$DIST/gltest.jar" .) || return 1

    # Kostka's AWT (windows that exist without being drawn, drawing on pictures in Java): it extends the JDK's own
    # AWT classes, so it is compiled against them (-XDignore.symbol.file: javac's list of public classes leaves sun.* out)
    rm -rf "$OUT/awt" && mkdir -p "$OUT/awt"
    "$HOST_JAVA_HOME/bin/javac" -source 1.6 -target 1.6 -nowarn -XDignore.symbol.file -d "$OUT/awt" \
        "$HERE"/awt/kostka/awt/*.java > "$LOGS/awt-javac.log" 2>&1 || { cat "$LOGS/awt-javac.log"; return 1; }
    (cd "$OUT/awt" && "$HOST_JAVA_HOME/bin/jar" cf "$DIST/kostka-awt.jar" .) || return 1
    ls -la "$DIST"
}

# objects <dir> <flags> <sources...>: compiles in parallel (make -k: all the errors in one go)
objects() {
    local dir="$1" flags="$2" mk s o lang
    shift 2
    mkdir -p "$dir"
    mk="$dir.mk"
    {
        echo "CC := $CC"
        printf 'OBJS :='
        for s in "$@"; do o="$(basename "${s%.*}")"; printf ' %s/%s.o' "$dir" "$o"; done
        echo
        echo 'all: $(OBJS)'
        for s in "$@"; do
            o="$(basename "${s%.*}")"
            lang="-x c"
            case "$s" in *.m) lang="-x objective-c -fno-objc-arc" ;; esac
            printf '%s/%s.o: %s\n\t@$(CC) %s %s -c $< -o $@ 2> $@.err || { cat $@.err; exit 1; }\n' "$dir" "$o" "$s" "$flags" "$lang"
        done
    } > "$mk"
    make -k -j"$JOBS" -f "$mk" all > "$mk.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "$(basename "$dir"): compile errors"
        grep -B2 -A6 -m 40 ' error: ' "$mk.log" | head -n 240
        return 1
    fi
}

# 3. The native side: gl4es (static, its symbols hidden) and LWJGL's natives with the iOS ones, one library
natives() {
    step "gl4es"
    # Two things gl4es does that Darwin cannot: thread-local storage (none on iOS 6: gl4es's once-per-thread
    # loading flags become plain statics) and symbol aliases (two become small functions)
    python3 - "$G4/src/gl" <<'EOF' || return 1
import os, sys
d = sys.argv[1]
def patch(name, old, new):
    p = os.path.join(d, name)
    s = open(p).read()
    if old in s:
        open(p, "w").write(s.replace(old, new, 1))
    elif new not in s:
        sys.exit("%s: not found: %s" % (name, old.splitlines()[0]))
patch("loader.h", "#if defined(_WIN32) || defined(_WIN64)\n  #define THREAD_LOCAL __declspec(thread)",
      "#if defined(__APPLE__) && defined(__arm__)\n  #define THREAD_LOCAL\n#elif defined(_WIN32) || defined(_WIN64)\n  #define THREAD_LOCAL __declspec(thread)")
for f in ("Enable", "Disable"):
    patch("directstate.c",
          "AliasDecl(void,gl4es_gl%sClientStatei,(GLenum array, GLuint index),gl4es_gl%sClientStateIndexed);" % (f, f),
          "void APIENTRY_GL4ES gl4es_gl%sClientStatei(GLenum array, GLuint index) { gl4es_gl%sClientStateIndexed(array, index); }" % (f, f))
EOF
    local g4flags="-std=gnu11 -O2 -fPIC -fvisibility=hidden -funwind-tables -fno-strict-aliasing -w
 -DNOX11 -DNOEGL -DNO_GBM -DNO_LOADER -DNO_INIT_CONSTRUCTOR -DSTATICLIB -DEGL_NO_X11 -DDEFAULT_ES=2
 -I$G4/include -I$G4/src -I$G4/src/util -I$G4/src/glx -I$HERE/native"
    # (the library is everything in src/gl, as gl4es's CMakeLists lists it, and hardext.c)
    local srcs
    srcs=$(find "$G4/src/gl" -name '*.c' | sort)
    [ -n "$srcs" ] || { echo "no gl4es sources found"; return 1; }
    objects "$OBJ/gl4es" "$(echo $g4flags)" $srcs "$G4/src/glx/hardext.c" "$HERE/native/ios_gl4es.c" || return 1

    step "LWJGL's natives"
    local n="$LW/src/native"
    srcs="$n/common/common_tools.c $n/common/extal.c $n/common/org_lwjgl_BufferUtils.c $n/common/org_lwjgl_openal_AL.c
 $n/common/org_lwjgl_openal_ALC10.c $n/common/org_lwjgl_openal_ALC11.c
 $n/common/opengl/extgl.c $n/common/opengl/org_lwjgl_opengl_GLContext.c $n/common/opengl/org_lwjgl_opengl_CallbackUtil.c
 $(ls "$n"/generated/opengl/*.c "$n"/generated/openal/*.c)
 $HERE/native/ios_display.m $HERE/native/ios_context.m $HERE/native/ios_extgl.c $HERE/native/ios_al.c"
    objects "$OBJ/lwjgl" "-std=gnu99 -O2 -fPIC -fno-strict-aliasing -w -I$GEN/jni -I$n/common -I$n/common/opengl -I$HERE/native" $srcs || return 1

    step "liblwjgl.dylib"
    $TC/clang $TARGET -dynamiclib -install_name "@loader_path/liblwjgl.dylib" -compatibility_version 1.0.0 -current_version 1.0.0 \
        -o "$DIST/liblwjgl.dylib" "$OBJ"/lwjgl/*.o "$OBJ"/gl4es/*.o \
        -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics -framework OpenGLES -lobjc \
        > "$LOGS/link.log" 2>&1
    if [ $? -ne 0 ]; then echo "link errors"; head -n 80 "$LOGS/link.log"; return 1; fi
    "$TC/nm" -u "$DIST/liblwjgl.dylib" > "$LOGS/liblwjgl-imports.txt" 2>/dev/null || true
    # (iOS loads no code without a signature: the pseudo-signature of ldid, as for the app)
    "$TC/ldid" -S "$DIST/liblwjgl.dylib" || return 1

    mkdir -p "$DIST/licenses"
    cp "$LW/doc/LICENSE" "$DIST/licenses/LWJGL-LICENSE.txt" 2>/dev/null || find "$LW" -maxdepth 2 -iname 'license*' -exec cp {} "$DIST/licenses/LWJGL-LICENSE.txt" \; -quit
    cp "$G4/LICENSE" "$DIST/licenses/gl4es-LICENSE.txt" 2>/dev/null || true
    cp "$HERE/README.md" "$DIST/README-Kostka.md" 2>/dev/null || true
    ls -la "$DIST"
}

# 4. lwjgl-debug.jar: the same classes with a check after every OpenGL call (LWJGL's generator, -Ageneratechecks):
#    a game that makes OpenGL report an error stops at the call that did it - for finding what gl4es does not take.
#    (After the natives: the generator rewrites the generated sources.)
lwjgl_debug() {
    step "lwjgl-debug.jar"
    (cd "$LW" && JAVA_HOME="$HOST_JAVA_HOME" PATH="$HOST_JAVA_HOME/bin:$PATH" ant -noinput generate-debug compile) > "$LOGS/ant-debug.log" 2>&1
    if [ $? -ne 0 ]; then echo "ant (debug) failed"; tail -n 40 "$LOGS/ant-debug.log"; return 1; fi
    printf 'Sealed: true\n' > "$OUT/debug-manifest.txt"
    (cd "$LW/bin" && "$HOST_JAVA_HOME/bin/jar" cfm "$DIST/lwjgl-debug.jar" "$OUT/debug-manifest.txt" org/lwjgl/*.class \
        org/lwjgl/opengl org/lwjgl/input org/lwjgl/openal org/lwjgl/opencl org/lwjgl/opengles/ContextAttribs*.class) || return 1
    ls -la "$DIST/lwjgl-debug.jar"
}

case "${1:-all}" in
    fetch) fetch ;;
    java) fetch && lwjgl_java ;;
    natives) fetch && natives ;;
    all) fetch && lwjgl_java && natives && lwjgl_debug ;;
    *) echo "unknown step $1"; exit 2 ;;
esac
