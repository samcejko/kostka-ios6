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
- Every version from RubyDung to 1.12.2 tried on an iPad 2: started, a new world made and played in (all 113 of
  Mojang's list); the launcher marks each version by what was tried (Resources/Tested.json)
- The snapshots tried too: 231 of 236 play. gl4es reserves large display list ranges (the 1.7 snapshots asked for
  14 million lists), shaders with initial values of uniforms compile (post-processing, 15w14a), the first 1.6
  snapshots get the options and assets they expect and start in English
- The Java heap grows only as needed and gives memory back; 1 MB thread stacks (Alpha's lighting recursion)
- Every version's first start gets the iPad's settings (Alpha and Beta started with the farthest view)
- A game that stops with an error says why ("The game has stopped"), then Kostka closes: Minecraft's own description
  of the crash, or the last exception with its cause (an old version's crash showed an earlier network error)
- 1.8's Super Secret Settings and the spectator's views: a shader loop bound by a uniform goes to at most 8 steps
  (3 when nested) - art and blobs2 took 2 seconds a frame - and LWJGL's clock goes on when frames keep taking over
  a second (Minecraft stood still for good: ntsc, 3 seconds a frame); a shader that takes a whole number for a
  float, as GLSL 1.20 lets it, compiles (wobble)
- Java has the iPad's time zone (it had GMT: the times in the log, the dates of worlds and screenshots were off)
- Every version fills the screen: Classic to 1.5.2 and the first 1.6 snapshots asked for 854x480 and had bars above
  and below (Kostka's AWT gives every window the whole screen, LWJGL maximizes a resizable window)
- The frame rate in the game's upper left corner (Settings, In the game: on by default)
- With snapshots shown and the versions that do not run yet tried, the snapshots too new for iOS 6 are listed too
