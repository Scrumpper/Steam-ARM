# Steam ARM · Compatibility by game type

What works for each kind of game on this package, by build and graphics API. Updated as more
game types are run.

**Last updated:** 2026-10-06
**Run on:** RK3588 board (Mali-G610, PanVK and Panfrost, Mesa 26.1), KDE Plasma on X11, `steam-arm-install.sh` 2.0, 2.1 and 2.2, Valve FEX tool FEX-2607 and FEX-2609 beta, Proton 11 ARM64 and Proton Experimental ARM64

Legend: ✅ works  ⚠️ works with conditions  ❌ does not work  ❓ not run yet

| Game type                                              | Starts | On GPU | MangoHud | Steam overlay | Mali drivers in emulation         | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
|--------------------------------------------------------|--------|--------|----------|---------------|-----------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Linux, 32-bit x86, OpenGL (GameMaker)                  | ✅     | ✅     | ❌       | ✅            | same                              | 32-bit GL forwarding. Overlay: Shift+Tab opens and closes; controller Steam button opens, cannot close. MangoHud: root filesystem has no 32-bit build |
| Linux, 64-bit x86, OpenGL (GameMaker)                  | ✅     | ✅     | ✅       | ✅            | ✅                                | `glx-lax` covers titles that bind one GL context from several threads; 60 fps on forwarding. Mali drivers in emulation carry same check relaxed. Overlay as above. 2.1: MangoHud through `mangohud=on` profile draws, 60 fps menu |
| Linux, 64-bit x86, Unity with Vulkan                   | ✅     | ✅     | ⚠️      | ⚠️            | same                              | Two titles. Handler starts player with `-force-vulkan`. Overlay: controller Steam button opens and closes, Shift+Tab does not. On quit client can show title running after window closes, until Stop. Title hangs at start when overlay Vulkan layer is registered twice; 2.0 launcher removes second registration. 2.1: with `mangohud=on` profile no HUD in three titles (forwarding, `-force-vulkan`) |
| Linux, 64-bit x86, Unity 5+ on OpenGL                  | ✅     | ✅     | ❓       | ❓            | ✅ lower frame rate               | Handler reports GL 4.5, otherwise title stops at start with `GLXBadFBConfig`                                                                                                                                                                                                                                                                                                                                                                                   |
| Linux, 32-bit x86, Unity                               | ✅     | ✅     | ❌       | ❌            | same                              | Unity 4 and Unity 5 titles. Title stops when Steam overlay attaches; handler starts it with overlay off. 10-minute run on each route: no crash. On Mali drivers route GPU driver logs page-fault message at title exit; same message was logged on test system before that route existed; title unaffected                                                                                                                                                     |
| Linux, 64-bit x86, Godot 4                             | ✅     | ✅     | ✅       | ✅            | same                              | Handler switches Godot 4 to OpenGL renderer and GL 3.3 report (Vulkan renderer freezes on splash). Second title reaches menu at 4.5 fps on both routes                                                                                                                                                                                                                                                                                                         |
| Linux, 64-bit x86, Godot 3                             | ⚠️     | ✅     | ✅       | ❓            | ⚠️ with same profile              | Stops at start: `GLXBadFBConfig` on forwarding, "Unable to initialize video driver" on Mali drivers route. Menu runs with profile `env=MESA_GL_VERSION_OVERRIDE=3.3;MESA_GLSL_VERSION_OVERRIDE=330`. 2.1: menu on GPU with that profile, 13 fps. 2.2: handler sets both values without profile, not run yet |
| Linux, 64-bit x86, Source engine (OpenGL)              | ✅     | ✅     | ❓       | ❓            | same                              | Menu on GPU through GL forwarding                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Linux, 32-bit x86, Source engine (OpenGL)              | ❌     | ✅     | ❌       | ❓            | ❌ same                           | Loading screen draws, then all threads wait; `gl32=off`, Multiblock off, `-nosound`, `gfx=b` do not help. Windows build through Proton 11.0 ARM64 (DXVK d3d9, on GPU) reaches main menu, loads first map and plays through three level changes with input; set it from Graphics > Route per game > windows. 2.2: same on Proton 11.0-2 ARM64, 3 of 3 starts, 50 to 65 fps in map (on-screen counter); first start plays intro video slowly, Escape skips it |
| Linux, 32-bit x86, Unreal Engine 2 (OpenGL)            | ✅     | ✅     | ❌       | ❓            | ✅ lower frame rate               | Switches display mode for fullscreen; mode restored on quit                                                                                                                                                                                                                                                                                                                                                                                                    |
| Linux, 64-bit x86, Unreal Engine 3                     | ✅     | ✅     | ❓       | ❓            | ✅ lower frame rate               |                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Linux, 64-bit x86, Unreal Engine 4                     | ❌     | none   | none     | none          | ❌ same                           | Engine fatal error at start on both routes                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Linux, 64-bit x86, Ren'Py                              | ✅     | ✅     | ❓       | ❓            | same                              | Python 3 build                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Linux, 64-bit x86, Java (LWJGL 2)                      | ❌     | none   | none     | none          | ⚠️ automatic                      | Bundled Java 17. Forwarding: Java runtime crashes within about 20 s; other garbage collector, Multiblock off and `ParanoidTSO` do not help; interpreter-only mode runs at 1.6 fps. Handler detects bundled Java runtime and picks Mali drivers route, and adds `-DLWJGL_DISABLE_XRANDR=true` to `JAVA_TOOL_OPTIONS` (without it LWJGL 2 fails at display-mode query on both routes). `-XX:-UseShenandoahGC` in `_JAVA_OPTIONS` raised frame rate on test title. 2.1: on Mali drivers route 3 of 6 starts ended with Java runtime crash (SIGSEGV) 20 to 25 s in; others reached menu on GPU. 2.2, Valve FEX tool FEX-2607: about half of first-start map loads fail (Java runtime crash in compiled code, server thread stall or deadlock); Multiblock off, TSO options, full SMC checks, other garbage collector, one CPU and `DynamicL1Cache` 0 do not lower rate. FEX-2609.1 beta: 2 of 10 failed |
| Linux, 64-bit x86, Java (LWJGL 3)                      | ❌     | none   | none     | none          | ✅ automatic                      | Bundled Java 25. Forwarding: updater crashes in Java compiler; with `FEX_MULTIBLOCK=0` updater passes, then game runtime exits. Handler picks Mali drivers route and turns FEX Multiblock off (Java 21 and newer); title screen runs                                                                                                                                                                                                                           |
| Linux, 64-bit x86, FNA                                 | ✅     | ✅     | ✅       | ❓            | same                              | Second title stops on both routes: native library missing from game package. MangoHud draws in first title |
| Linux, 64-bit x86, C++ SDL, OpenGL                     | ✅     | ✅     | ✅       | ❓            | not tested                        | On quit one thread can stay behind; client shows title running until Stop                                                                                                                                                                                                                                                                                                                                                                                      |
| Linux, 64-bit x86, C++ SDL, OpenGL (second title)      | ⚠️     | ✅     | ❓       | ❌            | ✅                                | Stopped about 1 s after Steam overlay attached (heap error) in validation runs; runs with `overlay=off` profile. On Mali drivers route ran with vsync on and off                                                                                                                                                                                                                                                                                               |
| Linux, 64-bit x86, custom OpenGL engine                | ⚠️     | ✅     | ❓       | ⚠️            | ✅ with same profile              | Some stop when Steam overlay attaches; `overlay=off` profile for that title; one title also needs `env=MESA_GL_VERSION_OVERRIDE=4.5` (`GLXBadFBConfig` otherwise). SDL title that exits 20 to 30 s in on both routes runs with `overlay=off`. Another SDL title stops with segmentation fault on both routes (game's own crash log). 2.1: that title (`overlay=off`) reaches login screen on GPU; with MangoHud loaded it stops about 20 s in |
| Linux, 64-bit x86, custom Vulkan engine                | ❌     | ❓     | none     | none          | ❌ same                           | Exits 20 to 30 s in on both routes; no clear error in logs                                                                                                                                                                                                                                                                                                                                                                                                     |
| Linux, 32-bit x86, DXVK Native (Vulkan)                | ❌     | ❌     | none     | none          | ⚠️ automatic, on GPU, title hangs | 32-bit Source engine title started with `-vulkan`. Handler picks Mali drivers route for 32-bit titles started with `-vulkan` or `-force-vulkan` and keeps option; DXVK creates device on Mali, with features 2.0 archive reports. Title still stops at loading screen, as with its OpenGL renderer. Without Mali drivers in emulation option is removed, since Vulkan would run on CPU renderer                                                                |
| Windows, Proton ARM64, Direct3D 11                     | ✅     | ✅     | ❌       | ❌            | no change                         | DXVK on PanVK at feature level 10_1 with `vk-spoof`; MangoHud and arm64 overlay layer each crash title at device creation                                                                                                                                                                                                                                                                                                                                      |
| Windows, Proton ARM64, Direct3D 11 (GameMaker, 64-bit) | ✅     | ✅     | ❓       | ❓            | no change                         | Title screen on Proton 11 ARM64 (DXVK 2.7.1) and Proton Experimental ARM64 (DXVK 3.1.1)                                                                                                                                                                                                                                                                                                                                                                        |
| Windows, Proton ARM64, Direct3D 11 (Unity HDRP)        | ❌     | none   | none     | none          | no change                         | Black screen; Unity reports feature level 10_1 lacks compute shaders it needs. HDRP titles need feature level 11_0                                                                                                                                                                                                                                                                                                                                             |
| Windows, Proton ARM64, 32-bit Direct3D 9               | ✅     | ✅     | ❓       | ❓            | no change                         | DXVK `d3d9`, including Adobe AIR and Ogre engine titles                                                                                                                                                                                                                                                                                                                                                                                                        |
| Windows, Proton ARM64, 32-bit Direct3D 8               | ✅     | ✅     | ❓       | ❓            | no change                         | DXVK `d3d8` (`PROTON_DXVK_D3D8=1`, set by launcher); wined3d default draws these wrong                                                                                                                                                                                                                                                                                                                                                                         |
| Windows, Proton ARM64, GameMaker                       | ✅     | ✅     | ❓       | ❓            | no change                         | In-game videos show colour bars unless `shader-cache` component is on                                                                                                                                                                                                                                                                                                                                                                                          |
| Windows, Proton ARM64, Ren'Py                          | ✅     | ✅     | ❓       | ❓            | no change                         |                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Windows, Proton ARM64, Java (bundled runtime)          | ⚠️    | ✅      | none     | none          | no change                         | Earlier test: exits about 25 s in. 2.1 test: title reached intro scene on GPU and ran 70 s |
| Windows, Proton ARM64, .NET / XNA (32-bit)             | ✅     | ✅     | ❓       | ❓            | no change                         | wine-mono. Second XNA title showed no window within 90 s. 2.1: that title again showed no window within 120 s |
| Windows, Proton ARM64, Unreal Engine 3 (32-bit, PhysX) | ❌     | none   | none     | none          | no change                         | PhysX install step: ✅ skipped by launcher, finishes in seconds. Title then stops about 5 seconds in with engine assertion; `FEX_X87REDUCEDPRECISION=0` does not help                                                                                                                                                                                                                                                                                          |
| Windows, Proton ARM64, Unreal Engine 4 (D3D11)         | ❌     | none   | none     | none          | no change                         | Engine asks for feature level 11_0; DXVK on PanVK offers 10_1 (no tessellation), on both Proton builds. Raising level in `dxvk.conf` crashes engine compiling geometry shader                                                                                                                                                                                                                                                                                  |
| Remote Play stream from Windows PC                     | ✅     | none   | none     | ⚠️            | no change                         | Software decode, H.264, streaming client about one core. Use controller Steam button: Shift+Tab goes to host and stalls picture                                                                                                                                                                                                                                                                                                                                |

## What columns mean

- **Starts:** reaches its title screen or menu on forwarding route.
- **On GPU:** renders on Mali, not on CPU renderer (llvmpipe).
- **MangoHud:** HUD draws in game with launch option `mangohud %command%`, `MANGOHUD=1 %command%` or profile `mangohud=on`; launch handler loads root filesystem's 64-bit MangoHud library from client folder. 32-bit titles: no MangoHud.
- **Steam overlay:** Shift+Tab or controller Steam button opens overlay in game.
- **Mali drivers in emulation:** result on Mali drivers route (`gpu-in-emulation` component), tests 2026-09-30 and 2026-10-01. "automatic": handler picks this route for title with no profile; "same": same result on both routes; "not tested": row not run on this route; "no change": Windows titles use system Vulkan through ARM64 Proton, so route does not apply.

## Route choice

x86 Linux titles run on one of two graphics routes, picked per title at start:

- **Forwarding:** OpenGL and Vulkan calls go to system's ARM64 Mesa (FEX thunks). Used
  for every title no rule below picks.
- **Mali drivers in emulation:** x86 builds of Mesa with Panfrost and PanVK, in second
  copy of root filesystem (`gpu-in-emulation` component; defaults per Mali family in README GPU
  detection). Handler picks it for Java titles (bundled Java runtime detected in game folder)
  and, on `mali-csf-v10`, for 32-bit titles started with `-vulkan` or `-force-vulkan`, which
  have no Vulkan forwarding.

Profile key `gfx=a` (forwarding) or `gfx=b` (Mali drivers in emulation) overrides choice
per title; `GFX_DEFAULT=b` in `/etc/steam-arm/steam-arm.conf` puts every x86 title on Mali
drivers. Game log line `steam-arm: graphics:` names route and reason. Windows titles run
through ARM64 Proton on system Vulkan, on neither route.

## Route comparison

Frame rates on both routes, tests 2026-10-01. Conditions: one test system (RK3588,
Mali-G610), one title per row, 90-second runs unless noted, frame rate from Mesa Gallium
HUD. Mali drivers route: 2.0 driver archive, forced with `gfx=b` where handler picks
forwarding.

| Game type                                                                  | Forwarding                           | Mali drivers in emulation                      |
|----------------------------------------------------------------------------|--------------------------------------|------------------------------------------------|
| Linux, 32-bit x86, OpenGL (GameMaker)                                      | 60 fps                               | 60 fps                                         |
| Linux, 64-bit x86, OpenGL (GameMaker), one GL context from several threads | 60 fps (`glx-lax`)                   | menu, 60 fps                                   |
| Linux, 64-bit x86, Unity 5+ on OpenGL, vsync off                           | 505 fps, GPU load 93%                | 409 fps, GPU load 20% (CPU limited)            |
| Linux, 32-bit x86, Unity 5, 90 s                                           | 69 fps                               | 82 fps                                         |
| Linux, 32-bit x86, Unity 5, 10-minute average                              | 84.9 fps                             | 61.8 fps                                       |
| Linux, 32-bit x86, Unity 4                                                 | 30 fps                               | 29 fps                                         |
| Linux, 64-bit x86, Godot 4, first title                                    | 60 fps                               | 60 fps                                         |
| Linux, 64-bit x86, Godot 4, second title                                   | menu, 4.5 fps                        | menu, 4.5 fps                                  |
| Linux, 64-bit x86, Godot 3, GL 3.3 profile                                 | menu, 15.8 fps                       | menu, 5.6 fps                                  |
| Linux, 64-bit x86, Source engine (OpenGL)                                  | 59.7 fps                             | 58.9 fps                                       |
| Linux, 64-bit x86, FNA                                                     | 52.7 fps                             | 57.4 fps                                       |
| Linux, 64-bit x86, SDL OpenGL, `overlay=off` profile                       | 62 fps                               | 62 fps                                         |
| Linux, 32-bit x86, Unreal Engine 2                                         | 138.7 fps                            | 112.3 fps                                      |
| Linux, 64-bit x86, Unreal Engine 3                                         | 38.6 fps                             | 19.6 fps (CPU limited)                         |
| Linux, 64-bit x86, Ren'Py, menu                                            | 10.7 fps                             | 10.1 fps                                       |
| Linux, 64-bit x86, Java (LWJGL 2)                                          | Java runtime crash within about 20 s | menu, 162 fps (automatic)                      |
| Linux, 64-bit x86, Java (LWJGL 3)                                          | Java runtime crash                   | title screen, 58.8 fps (60 fps cap), automatic |

Mali drivers route ran every title type that ran on forwarding. Java titles that crash on
forwarding ran on it, so handler picks it for them; other titles stay on forwarding, which
ran same or higher frame rate for most types above. Frame rates are from one system and
one title each; other titles and boards can differ.

## Launch handler

Steam ARM's launch handler decides per title, before game starts, with no launch options needed:

- x86 Steam overlay on for Linux x86 titles
- MangoHud when title asks for it
- Godot 4 titles on OpenGL renderer with GL 3.3 report; Godot 3 titles with GL 3.3 report; engine version from PCK embedded in executable, else `.pck` beside it; Windows builds under x86 Proton left as is
- Unity titles: Vulkan renderer where player carries it, else GL 4.5 report; 32-bit Unity players with overlay off
- Graphics route: forwarding, or Mali drivers in emulation for Java titles and, on `mali-csf-v10`, for 32-bit titles started with `-vulkan` or `-force-vulkan` (option kept); see Route choice
- Java titles with LWJGL 2: `-DLWJGL_DISABLE_XRANDR=true` added; Java 21 and newer on Mali drivers route: FEX Multiblock off
- 32-bit titles without Mali drivers in emulation: `-vulkan` and `-force-vulkan` removed (Vulkan forwarding is 64-bit only)
- Start scripts (Source engine style) followed to binary they start

Title profiles in `/etc/steam-arm/titles.conf` change it per title, by Steam app id:

```
<appid> overlay=x86|vulkan|off  mangohud=on|off  godot=gl|vulkan  unity=vulkan|gl  env=A=1;B=2  args=-x;-y
<appid> gl32=off  vk32=keep  gfx=a|b
```

Per title launch options override profiles: `STEAM_ARM_OVERLAY=x86|vulkan|off %command%`.

Windows titles run through Valve's ARM64 Proton, where handler does not run. Launcher sets `PROTON_DXVK_D3D8=1` for them, so Direct3D 8 titles use DXVK, and skips PhysX install step for titles whose install script runs it.

## Raspberry Pi 5

Raspberry Pi 4: current client builds do not start (Cortex-A72, Armv8.0 without LSE
atomics; `README.md`, Requirements).

Not run on test system. Expectations come from driver source, title requirements and
community reports (Raspberry Pi 5, marked as such). V3D offers OpenGL 3.1 at most; DXVK
needs Vulkan features V3DV does not report. Details: `COMPATIBILITY.md`, Raspberry Pi.

| Game type                                      | Expectation                     | Reason                                                                                                                                                                                                                                                                                                                         |
|------------------------------------------------|---------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Linux, x86, OpenGL 3.1 or older                | starts on GPU                   | Within V3D's OpenGL 3.1. Community report: SteamWorld Dig on GPU, about 47 fps                                                                                                                                                                                                                                                 |
| Linux, 32-bit x86, GoldSrc (Half-Life)         | starts on GPU, CPU limit likely | Linux build asks for OpenGL 2.1 (Steam store page), within V3D. 32-bit code runs through emulation and each old-style OpenGL call crosses forwarding on its own, so processor is likely limit (suspected, unmeasured). Video options must name OpenGL renderer; Software renderer draws on CPU. Community report: about 30 fps |
| Linux, 64-bit x86, OpenGL 4.x (Feral ports)    | does not start                  | Tomb Raider (2013): Feral lists GL 4-class drivers (Mesa 11.2 on Radeon R7 260X, NVIDIA 364). Zink (OpenGL on Vulkan) reaches OpenGL 4.0 only with `tessellationShader` (Mesa Zink documentation), which V3DV lacks. Community report: Tomb Raider GOTY did not start                                                          |
| Linux, 64-bit x86, Unity 5+ on OpenGL, Godot   | unknown                         | Handler reports GL 4.5 (Unity) or 3.3 (Godot), above V3D's 3.1                                                                                                                                                                                                                                                                 |
| Linux, 64-bit x86, Vulkan                      | unknown                         | V3DV is Vulkan 1.3 conformant; features beyond that vary                                                                                                                                                                                                                                                                       |
| Linux, 32-bit x86, Vulkan                      | CPU renderer                    | No 32-bit Vulkan forwarding; handler removes `-vulkan` and `-force-vulkan`                                                                                                                                                                                                                                                     |
| Windows, Proton ARM64, DXVK (Direct3D 8 to 11) | does not start                  | DXVK 3.1.1 baseline for Direct3D 9 asks `textureCompressionBC`, `shaderCullDistance`, `nullDescriptor` and `robustBufferAccess2`; Direct3D 11 also asks `multiViewport` and transform feedback. Mesa 26.1 V3DV reports none of these (`v3dv_device.c`; DXVK `VP_DXVK_requirements.json`)                                       |
| Windows, Proton ARM64, `PROTON_USE_WINED3D=1`  | unknown                         | WineD3D draws Direct3D through OpenGL, limited by V3D's 3.1                                                                                                                                                                                                                                                                    |

## Known issues

- MangoHud: no HUD in Unity titles on Vulkan renderer (`mangohud=on` profile, three titles);
  title runs. 32-bit titles: no MangoHud (root filesystem has no 32-bit build).
- Custom OpenGL engine title with included `overlay=off` profile (app 248570): stops about
  20 s in with MangoHud loaded; leave MangoHud off for it.
- `steam://rungameid/<appid>` for title not in library: install dialog can stay over games
  started later; restart Steam to clear it.
- `powerprofilesctl launch -p performance -- %command%`: hold works only when Steam was
  started from desktop session (menu or autostart); started from other context, hold is
  refused and title does not start.

## Updating this document

- Add row per game type: build (Linux or Windows, 32-bit or 64-bit), graphics API, engine where it decides behaviour.
- Mark ✅ only for what was seen: menu on screen, GPU in use, HUD or overlay drawn.
- Change **Last updated** date, and **Run on** when client, FEX tool, Proton or Mesa change.

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
