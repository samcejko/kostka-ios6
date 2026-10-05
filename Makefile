# Kostka - a launcher of Minecraft: Java Edition for jailbroken iOS 6.x (armv7): the game's own files, run by a
# Java VM ported to 32-bit iOS. Built with Theos. Deployment target iOS 6.0, compiled against the iOS 9.3 SDK.

TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
DEBUG ?= 0

# `make install` (Theos) wants THEOS_DEVICE_IP from the environment; tools/ipad.ps1 installs from tools/local.json
THEOS_DEVICE_USER ?= root

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Kostka

Kostka_FILES := $(wildcard src/*.m) $(wildcard src/*/*.m) $(wildcard src/*/*.c)

Kostka_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore OpenGLES

Kostka_CFLAGS := -Isrc -Isrc/Probe -Isrc/UI -Isrc/Util \
                 -Os -fvisibility=hidden \
                 -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                 -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-unused-parameter -Wno-sign-compare \
                 -Wno-nullability-completeness -Wno-nullability-completeness-on-arrays -Wno-error

# Objective-C only: ARC; APIs newer than iOS 6.0 are errors for our own sources (the pragma in src/KOCommon.h)
Kostka_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

include $(THEOS)/makefiles/application.mk

# The iOS 9.3 SDK places the NSURL* loading classes in CFNetwork; on iOS 6 they live in Foundation and dyld aborts at
# launch when the binary asks CFNetwork for them: the load command is pointed at Foundation, then signed again.
Kostka_STAGED_BIN := $(THEOS_STAGING_DIR)/Applications/Kostka.app/Kostka
after-stage::
	install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(Kostka_STAGED_BIN)" || true
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements.xml" "$(Kostka_STAGED_BIN)"
