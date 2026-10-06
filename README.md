# Kostka - Minecraft: Java Edition on iOS 6

A launcher of **Minecraft: Java Edition** for jailbroken iOS 6.x (iPad 2 / iPhone 4S era, armv7): the game's own
files, downloaded from Mojang's servers, run unchanged by a **Java VM ported to 32-bit iOS**. In English and Czech.

Unofficial; not affiliated with, endorsed by or associated with Mojang AB or Microsoft. "Minecraft" is a trademark
of Mojang Synergies AB. Kostka ships nothing of Mojang's: the game is downloaded from Mojang's servers by the
player, who must own it.

## What plays (iPad 2, iOS 6.1.3, 512 MB)

| Version | |
| --- | --- |
Every version below was started on the iPad, made a new world and played in it (`Resources/Tested.json`, which the
launcher shows):

| Versions | | the app's memory | a new world |
| --- | --- | --- | --- |
| RubyDung, all 5 (May 2009) | play, 20-60 fps | 70-125 MB | at once |
| Classic, all 4 | play, 20-60 fps | 140-270 MB | at once |
| Infdev 2010-06-18 | plays | 150 MB | 30 s |
| Alpha, all 25 | play, 20-50 fps | 145-170 MB | 25-60 s |
| Beta, all 26 | play; walking into new land is slow (the world is made on the game's thread) | 140-185 MB | 20-140 s |
| 1.0 to 1.7.10, all 27 | play, 10-30 fps | 170-245 MB | 50-120 s |
| 1.12.2 | plays, 26 fps at render distance 2 | about 240 MB | about 3 min |
| 1.8 to 1.12.1 | not tried yet: the same pieces run them | | |
| 1.13 and newer | no: LWJGL 3, OpenGL 3.2 / Java 17 for the newest | | |

The iPad 2 warns from about 250 MB of the app's memory and ends it at about 320. Indev is not on Mojang's list of
versions (the launcher shows what Mojang offers).

Mojang's jars are not patched: the pieces under them are made to do what each era of the game expects.

## How

- **Java** (`jvm/`): HotSpot from the AArch32 port of OpenJDK 8 (client VM: template interpreter + C1 JIT, serial
  GC) ported to Darwin/armv7 - the Darwin calling convention, 4-byte aligned `long`s in structures, iOS 6's
  missing pieces, direct buffers that take memory only where they are written - with the JDK's native libraries
  (java, zip, net, nio, management, sunec for TLS's elliptic curves, a stub of awt); the class library is Amazon
  Corretto 8's. It calls itself
  "iPhone OS X": games that see a Mac load Mac libraries. Cross-compiled on Linux with Theos' toolchain.
- **LWJGL 2** (`lwjgl/`): an iOS backend in place of the Mac OS X one - a UIKit view on an EAGL layer, touches as
  the mouse, on-screen keys, the iOS keyboard - with **gl4es** turning the game's desktop OpenGL into OpenGL ES 2.0.
  Sound through iOS's OpenAL.
- **AWT** (`lwjgl/awt`): windows that exist without being drawn, for the versions that open a frame and an applet
  (Classic to 1.5.2 through Mojang's launchwrapper), and pictures drawn in Java.
- **The launcher** (`src/`): every version from Mojang's list, marked by what it does here; downloads the version,
  its libraries and assets (checked against their SHA-1) and starts it. One Java VM per process: when the game
  ends, Kostka closes.

## Touch controls

In menus a finger is the pointer. In the game a moving finger turns the view, a tap is the right button (use,
place), a finger held down the left one (attack, break); the arrows walk, Jump and Sneak, E (inventory), T (chat),
Esc, Aa (the keyboard); a tap on the hotbar picks its slot.

## Tests from a computer

```
uiopen 'kostka:play?version=1.6.4'          # download and start a version (any)
uiopen 'kostka:mouse?x=512&y=400&button=0'  # a click (LWJGL's coordinates, from the bottom left)
uiopen 'kostka:key?code=28&char=13'         # a key; kostka:text?s=... types
uiopen 'kostka:screenshot'                  # the screen into Library/Kostka/screen.png
uiopen 'kostka:probe?test=info|jit|vm|gl|cpu'   # the device test
```

## Building

GitHub Actions: `jre.yml` builds the Java runtime, `lwjgl.yml` LWJGL with gl4es and Kostka's AWT, `build.yml` the
app (IPA and DEB) with the latest of both. Kostka is installed from the **DEB** (into `/Applications`, outside the
container sandbox), which a JIT needs.

## License

MIT (see LICENSE); the Java runtime's files derived from OpenJDK are GPL v2 with the Classpath exception, LWJGL's
BSD, gl4es MIT. See THIRD-PARTY-NOTICES.md.
