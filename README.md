# Kostka - Minecraft: Java Edition on iOS 6

A launcher of **Minecraft: Java Edition** for jailbroken iOS 6.x (iPad 2 / iPhone 4S era, armv7): the game's own
files, downloaded from Mojang for the player's own account, run by a **Java VM ported to 32-bit iOS**. In English
and Czech.

Unofficial; not affiliated with, endorsed by or associated with Mojang AB or Microsoft. "Minecraft" is a trademark
of Mojang Synergies AB. Kostka ships nothing of Mojang's: the game is downloaded from Mojang's servers by the
player, who must own it.

## Status

Work in progress. The first milestone is the **device test** (`src/Probe`): what an iOS 6 device allows a Java
VM - code generated at run time (the JIT), handling faults in it, address space, memory, OpenGL ES 2.0, CPU speed.

| Milestone | |
| --- | --- |
| 1. Device test | in progress |
| 2. Java 8 on iOS 6 (OpenJDK 8, armv7, Darwin): "Hello world", then the JIT | |
| 3. LWJGL and OpenGL (desktop OpenGL translated to OpenGL ES 2.0 by gl4es), sound, touch controls | |
| 4. Minecraft Classic to Beta, then newer versions as far as the device's memory allows | |
| 5. The launcher: every version from Mojang's list, Microsoft sign-in, downloads | |

## What can run

Minecraft 1.17 and newer need OpenGL 3.2 and Java 17; iOS 6 devices have OpenGL ES 2.0 and 512 MB or 1 GB of
memory. Realistic: the old versions (Classic, Indev, Infdev, Alpha, Beta, the first releases), as far as memory
allows (an iPad 2 has 512 MB; an iPhone 5 or iPad 3/4 1 GB). The launcher will list every version and mark the ones
the device can run.

## Device test

```
uiopen 'kostka:probe?test=info'     # device, memory, storage
uiopen 'kostka:probe?test=jit'      # generated code in RWX memory, patched, a fault in it handled
uiopen 'kostka:probe?test=jitwx'    # the same, writing and running in turns (RW, then RX)
uiopen 'kostka:probe?test=vm'       # largest address space reservation, commit inside it
uiopen 'kostka:probe?test=mem'      # memory touched until the system stops the app (the log keeps the last step)
uiopen 'kostka:probe?test=gl'       # OpenGL ES 2.0: renderer, limits, extensions
uiopen 'kostka:probe?test=cpu'      # integer, floating point, memory copy
```

The results are on the screen and in the log (`[Kostka] probe ...`).

## Building

GitHub Actions builds the IPA and the DEB (Theos, iOS 9.3 SDK, deployment target iOS 6.0, armv7); see
`.github/workflows/build.yml`. Kostka is installed from the **DEB** (into `/Applications`, outside the container
sandbox), which a JIT needs.

## License

MIT (see LICENSE). Third-party parts: see THIRD-PARTY-NOTICES.md.
