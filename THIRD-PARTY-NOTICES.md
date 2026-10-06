# Third-party notices

Kostka is an independent, unofficial launcher. It is not affiliated with, endorsed by or associated with Mojang AB
or Microsoft Corporation. "Minecraft" is a trademark of Mojang Synergies AB. Kostka contains none of Mojang's code
or assets: the game is downloaded from Mojang's servers by its owner.

- **OpenJDK 8** (the AArch32 port, `openjdk/aarch32-port-jdk8u`): HotSpot and the JDK's native libraries, built
  from source with Kostka's iOS port (`jvm/`) - GPL v2 with the Classpath exception. The class library and the
  runtime's other files come from **Amazon Corretto 8** (same license); their LICENSE, ASSEMBLY_EXCEPTION and
  THIRD_PARTY_README ship in the app's `jre` folder.
- **LWJGL 2** (Lightweight Java Game Library) - BSD 3-clause, Copyright (c) 2002-2008 LWJGL Project; Kostka's iOS
  backend (`lwjgl/java`, `lwjgl/native`) is under the same license. The license ships in the app's `lwjgl` folder.
- **gl4es** - MIT, Copyright (c) 2016-2018 Sebastien Chevalier, (c) 2013-2016 Ryan Hileman; ships in `lwjgl`.
- **Apple's open source** (XNU headers used at build time for the network code) - APSL; not shipped.
- **Theos** - the build system; not shipped in the app.
