# Changelog

## 0.0.1 (in progress)

- The device test: generated code (JIT), faults in it, address space, memory, OpenGL ES 2.0, CPU speed
- Java 8 on iOS 6: HotSpot (client VM with the C1 JIT) ported to Darwin/armv7, the JDK's native libraries
- LWJGL 2 on iOS (UIKit/EAGL) with gl4es, OpenAL, touch controls and on-screen keys
- Kostka's AWT: windows without drawing (for launchwrapper's frames and applets), pictures drawn in Java
- The launcher: Mojang's versions with what plays here, downloads checked against their SHA-1, settings
- Playing: RubyDung (rd-132211 ...), Classic 0.30, 1.6.4, 1.12.2; to the menu: Infdev, Alpha 1.2.6, Beta 1.7.3,
  1.2.5, 1.5.2, 1.7.10, 1.8.9
- Direct buffers take memory only where they are written (old versions' sound asked for 160 MB and ran out)
- Java calls the system "iPhone OS X" (1.12's narrator loaded a Mac library and stopped the game)
- The app's memory in the log while a game runs
- Java's HTTPS with elliptic curves (libsunec): TLS 1.3 to Mojang's servers from the game (profiles, skins)
