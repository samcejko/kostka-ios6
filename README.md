# Kostka - Minecraft: Java Edition on iOS 6

A launcher of **Minecraft: Java Edition** for jailbroken iOS 6.x (iPad 2 / iPhone 4S era, armv7): the game's own
files, downloaded from Mojang's servers, run unchanged by a **Java VM ported to 32-bit iOS**. In English and Czech.

Unofficial; not affiliated with, endorsed by or associated with Mojang AB or Microsoft. "Minecraft" is a trademark
of Mojang Synergies AB. Kostka ships nothing of Mojang's: the game is downloaded from Mojang's servers by the
player, who must own it.

## What plays (iPad 2, iOS 6.1.3, 512 MB)

Every version below was started on the iPad, made a new world and played in it (`Resources/Tested.json`, which the
launcher shows):

| Versions | | the app's memory | a new world |
| --- | --- | --- | --- |
| RubyDung, all 5 (May 2009) | play, 20-60 fps | 70-125 MB | at once |
| Classic, all 4 | play, 20-60 fps | 140-270 MB | at once |
| Infdev 2010-06-18 | plays | 150 MB | 30 s |
| Alpha, all 25 | play, 20-50 fps | 145-170 MB | 25-60 s |
| Beta, all 26 | play; walking into new land is slow (the world is made on the game's thread) | 140-185 MB | 20-140 s |
| 1.0 to 1.7.10, all 28 | play, 10-30 fps | 170-245 MB | 50-120 s |
| 1.8 to 1.12.2, all 24 | play, 25-55 fps at render distance 2 | 200-260 MB | 2-4 min |
| snapshots, 231 of 236 | play (the 1.3 to 1.5 pre-releases, every snapshot from 13w16a to 1.12.2-pre2) | 200-260 MB | 1-4 min |
| 13w47a to 13w47d | not yet: they will not start without Twitch's streaming library, which has no iOS build | | |
| 15w41a | not yet: its integrated server stops on a bug of its own when the player joins | | |
| 1.13 and newer | no: LWJGL 3, OpenGL 3.2 / Java 17 for the newest | | |

All 113 versions of the LWJGL 2 era on Mojang's list play, and 231 of its 236 snapshots (shown when snapshots are
switched on in the settings). The first 1.6 snapshots (13w16a to 13w23b) and 13w42b start in English: the first have
no other language, 13w42b's font stops on a Czech letter. The iPad 2 warns from about 250 MB of the app's memory and
ends it at about 320. Indev is not on Mojang's list of versions (the launcher shows what Mojang offers). A new world
can put the player at the bottom of an ocean, as on a computer (the game looks for the ground through water): swim
up.

Every version fills the screen. The oldest (Classic to 1.5.2, the first 1.6 snapshots) asked for an 854x480 window;
at the screen's 1024x768 Alpha draws about a fifth fewer frames. The frame rate shows in the upper left corner (it
can be switched off in the settings).

1.8's Super Secret Settings: most of its effects run at 11-27 fps; art, blobs2 and blur at 2-4 fps with a smaller
radius than on a computer (their loops are cut down), ntsc at 0.3 fps - more than the iPad 2's graphics can do, but
the game goes on and the next click moves past it.

Mojang's jars are not patched: the pieces under them are made to do what each era of the game expects.

## OptiFine

For 1.7.2 to 1.12.2 the list has an OptiFine section. Add OptiFine shows what optifine.net offers (its newest edition
for each version), opens OptiFine's own download page in Kostka - with its advertisement; you tap Download there -
and runs OptiFine's installer in Kostka's Java. Kostka does not hand OptiFine out: it comes from optifine.net only.
An OptiFine version plays in its version's folder (the same worlds and options), and its first start sets OptiFine's
own settings to their fastest, Render Regions off.

On an iPad 2, frames a second standing (30 s) / turning round (30 looks), and the app's memory at its highest: one
Creative world per version, render distance 2, the player in the same place for every column. 60 is the screen's
most.

| | vanilla | OptiFine, its defaults | OptiFine at its fastest (Kostka's) |
| --- | --- | --- | --- |
| 1.7.10 | 33 / 29, 234 MB | 29 / 28, 232 MB | **49 / 41**, 242 MB |
| 1.8.9 | 40 / 35, 232 MB | 34 / 33, 256 MB | **59 / 52**, 257 MB |
| 1.9.4 | 58 / 35, 203 MB | 40 / 38, 238 MB | **59 / 50**, 237 MB |
| 1.10.2 | 30 / 26, 207 MB | 39 / 25, 246 MB | **59 / 46**, 245 MB |
| 1.11.2 | 43 / 40, 213 MB | 51 / 32, 249 MB | **58 / 51**, 255 MB |
| 1.12.2 | 40 / 35, 221 MB | 34 / 31, 255 MB | **58 / 48**, 257 MB |

At its fastest OptiFine draws 1.3 to 1.8 times vanilla's frames turning round, and standing comes to the screen's 60;
with its defaults it draws about as many as vanilla, or fewer. It takes 8 to 42 MB more memory (the iPad 2 warns
from about 250 MB and ends an app at about 320). Render Regions on: 1.8.9 59 / 54, 263 MB, 1.12.2 60 / 51, 267 MB - 4
to 6 % more frames turning round for 6 to 10 MB more memory, which is what the iPad 2 runs out of first. Shader packs
need OpenGL 3: not on the iPad 2.

## What is new

A version's page shows what is new in it: the Minecraft Wiki's page about the version (minecraft.wiki, its text
under CC BY-NC-SA 3.0), fetched when the page is opened and kept for later, as plain text - its lead, Additions,
Changes, Fixes.

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
place), a finger held down the left one (attack, break); the arrows walk - or a joystick, chosen in the settings
(forwards at its edge sprints) - Jump and Sneak, E (inventory), T (chat), Esc, Aa (the keyboard); a tap on the hotbar
picks its slot.

## Tests from a computer

```
uiopen 'kostka:play?version=1.6.4'          # download and start a version (any)
uiopen 'kostka:play?version=1.12.2&gamedir=test-1'  # its game in games/test-1, away from the player's worlds
uiopen 'kostka:open?version=1.12.2'         # a version's page (optifine=1: the OptiFine list)
uiopen 'kostka:mouse?x=512&y=400&button=0'  # a click (LWJGL's coordinates, from the bottom left)
uiopen 'kostka:key?code=28&char=13'         # a key; kostka:text?s=... types
uiopen 'kostka:stick?x=0&y=1'               # the joystick's knob (-1 to 1, up positive; 0,0 lets go)
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
