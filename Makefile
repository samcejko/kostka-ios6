# Kostka - a launcher of Minecraft: Java Edition for jailbroken iOS: the game's own files, run by a Java VM ported to
# iOS. One source tree, two packages (Theos):
#   make package                               armv7 for iOS 6.x (the iOS 9.3 SDK, deployment target 6.0)
#   make package THEOS_PACKAGE_SCHEME=rootless arm64 for iOS 14-17 (the iOS 16.5 SDK, deployment target 14.0):
#                                              the .deb for rootless jailbreaks, the IPA for TrollStore.
#                                              NOTE: the Java VM and LWJGL shipped by CI are 32-bit (jre.yml,
#                                              lwjgl.yml build armv7 only): the arm64 launcher starts, but has no
#                                              runtime to run the game with until a 64-bit port of them exists.
# (`make clean` between the two; CI builds both, see .github/workflows/build.yml)

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET := iphone:clang:16.5:14.0
ARCHS := arm64
else
TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
endif
DEBUG ?= 0

# `make install` (Theos) wants THEOS_DEVICE_IP from the environment; tools/ipad.ps1 installs from tools/local.json
THEOS_DEVICE_USER ?= root

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Kostka

Kostka_FILES := $(wildcard src/*.m) $(wildcard src/*/*.m) $(wildcard src/*/*.c)

Kostka_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore OpenGLES

Kostka_CFLAGS := -Isrc -Isrc/Probe -Isrc/Java -Isrc/UI -Isrc/Util -Isrc/Launcher -Ivendor/fetched/jni \
                 -Os -fvisibility=hidden \
                 -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                 -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-unused-parameter -Wno-sign-compare \
                 -Wno-nullability-completeness -Wno-nullability-completeness-on-arrays -Wno-error

# Objective-C only: ARC; APIs newer than the deployment target are errors for our own sources (the pragma in
# src/KOCommon.h); src/UI/KOModern.m bridges the newer iOS on its own terms and opts out
Kostka_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

include $(THEOS)/makefiles/application.mk

KOSTKA_STAGED_APP := $(THEOS_STAGING_DIR)/Applications/Kostka.app
KOSTKA_STAGED_BIN := $(KOSTKA_STAGED_APP)/Kostka

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
# The arm64 bundle: iOS 14.0+, arm64 required, a launch screen the system draws instead of the iOS 6 launch
# images (tools/modern_bundle.py), signed again with the entitlements afterwards.
after-stage::
	python3 "$(THEOS_PROJECT_DIR)/tools/modern_bundle.py" "$(KOSTKA_STAGED_APP)"
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements-arm64.xml" "$(KOSTKA_STAGED_BIN)"
# The .deb is for rootless jailbreaks (iOS 15 and newer; Theos sets Architecture: iphoneos-arm64 and the /var/jb
# prefix itself) and tells the home screen about the app when installed or removed.
before-package::
	sed -i -e 's/^Depends: firmware (>= 6.0)/Depends: firmware (>= 15.0)/' "$(THEOS_STAGING_DIR)/DEBIAN/control"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = configure ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && { uicache -p /var/jb/Applications/Kostka.app >/dev/null 2>&1 || uicache -a >/dev/null 2>&1; }' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = remove ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && uicache -a >/dev/null 2>&1' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
	chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
else
# The iOS 9.3 SDK places the NSURL* loading classes in CFNetwork; on iOS 6 they live in Foundation and dyld aborts at
# launch when the binary asks CFNetwork for them: the load command is pointed at Foundation, then signed again.
after-stage::
	install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(KOSTKA_STAGED_BIN)" || true
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements.xml" "$(KOSTKA_STAGED_BIN)"
endif
