# LWJGL 2 for iOS 6

Minecraft: Java Edition up to 1.12 draws with LWJGL 2 and desktop OpenGL. On the iPad, LWJGL gets an iOS
backend, and [gl4es](https://github.com/ptitSeb/gl4es) turns the desktop OpenGL into OpenGL ES 2.0.

- `java/`: the iOS backend. iOS reports `os.name` "Mac OS X", so LWJGL loads its Mac OS X classes; these files
  replace them under the same names. The window is a UIKit view on an EAGL layer, the context an EAGL
  (OpenGL ES 2.0) context, touches are the mouse, and on-screen keys and the iOS keyboard are the keyboard.
  Nothing of AWT or Cocoa is used.
- `native/`: the backend's JNI side (`ios_display.m`, `ios_context.m`), gl4es on EAGL (`ios_gl4es.c`: the
  game's framebuffer 0 is the window's framebuffer object), LWJGL's OpenGL functions from gl4es
  (`ios_extgl.c`) and OpenAL from the system framework (`ios_al.c`).
- `test/GLTest.java`: the first test: a turning triangle, the mouse under the finger, the keys.
- `build.sh`: fetches LWJGL 2 (its last sources, 2.9.4) and gl4es at fixed commits, runs LWJGL's generator,
  builds the jars, and cross-compiles gl4es and LWJGL's natives into one `liblwjgl.dylib` for armv7.
  The GitHub workflow `lwjgl.yml` runs it; the app takes its result (`Resources/lwjgl`).

## Licenses

- LWJGL: BSD 3-clause, Copyright (c) 2002-2008 LWJGL Project. The files in `java/` and `native/` are under
  the same license (the replaced classes keep LWJGL's notice).
- gl4es: MIT, Copyright (c) 2016-2018 Sebastien Chevalier, (c) 2013-2016 Ryan Hileman.

The build puts both license texts next to the library (`licenses/`).
