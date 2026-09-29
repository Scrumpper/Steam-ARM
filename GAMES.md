# Steam ARM · Compatibility by game type

What works for each kind of game on this package, by build and graphics API. Updated as more
game types are run.

**Last updated:** 2026-09-29
**Run on:** RK3588 board (Mali-G610, PanVK and Panfrost, Mesa 26.1), Armbian, KDE Plasma on X11, `steam-arm-install.sh` 1.2, Valve FEX tool FEX-2607

Legend: ✅ works  ⚠️ works with conditions  ❌ does not work  ❓ not run yet

| Game type                                       | Starts | On GPU | MangoHud | Steam overlay | Notes                                                                                                                                                                                    |
|-------------------------------------------------|--------|--------|----------|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Linux, 32-bit x86, OpenGL (GameMaker)           | ✅      | ✅      | ✅        | ✅             | 32-bit GL forwarding. Overlay: Shift+Tab opens and closes; controller Steam button opens, cannot close                                                                                   |
| Linux, 64-bit x86, OpenGL (GameMaker)           | ✅      | ✅      | ✅        | ✅             | `glx-lax` covers titles that bind one GL context from several threads. Overlay as above                                                                                                  |
| Linux, 64-bit x86, Unity with Vulkan            | ✅      | ✅      | ✅        | ⚠️            | Handler starts player with `-force-vulkan`. Overlay: controller Steam button opens and closes, Shift+Tab does not. On quit client can show title running after window closes, until Stop |
| Linux, 64-bit x86, Unity 5+ on OpenGL           | ✅      | ✅      | ❓        | ❓             | Handler reports GL 4.5, otherwise title stops at start with `GLXBadFBConfig`                                                                                                             |
| Linux, 32-bit x86, Unity                        | ✅      | ✅      | ❓        | ❌             | Title stops when Steam overlay attaches; handler starts it with overlay off                                                                                                              |
| Linux, 64-bit x86, Godot 4                      | ✅      | ✅      | ✅        | ✅             | Handler switches Godot 4 to OpenGL renderer and GL 3.3 report (Vulkan renderer freezes on splash)                                                                                        |
| Linux, 64-bit x86, Source engine (OpenGL)       | ✅      | ✅      | ❓        | ❓             | Menu on GPU through GL forwarding                                                                                                                                                        |
| Linux, 32-bit x86, Source engine (OpenGL)       | ❌      | ✅      | ❓        | ❓             | Loading screen draws, then all threads wait; `gl32=off`, Multiblock off, `-nosound` do not help. Proton build runs                                                                       |
| Linux, 32-bit x86, Unreal Engine 2 (OpenGL)     | ✅      | ✅      | ❓        | ❓             | Switches display mode for fullscreen; mode restored on quit                                                                                                                              |
| Linux, 64-bit x86, C++ SDL, OpenGL              | ✅      | ✅      | ❓        | ❓             | On quit one thread can stay behind; client shows title running until Stop                                                                                                                |
| Linux, 64-bit x86, custom OpenGL engine         | ⚠️     | ✅      | ❓        | ⚠️            | Some stop when Steam overlay attaches; `overlay=off` profile (shipped for known one)                                                                                                     |
| Windows, Proton ARM64, Direct3D 11              | ✅      | ✅      | ❌        | ❌             | DXVK on PanVK at feature level 10_1 with `vk-spoof`; MangoHud and arm64 overlay layer each crash title at device creation                                                                |
| Windows, Proton ARM64, 32-bit Direct3D 9        | ✅      | ✅      | ❓        | ❓             | DXVK `d3d9`, including Adobe AIR and Ogre engine titles                                                                                                                                  |
| Windows, Proton ARM64, 32-bit Direct3D 8        | ✅      | ✅      | ❓        | ❓             | DXVK `d3d8` (`PROTON_DXVK_D3D8=1`, set by launcher); wined3d default draws these wrong                                                                                                   |
| Windows, Proton ARM64, GameMaker                | ✅      | ✅      | ❓        | ❓             |                                                                                                                                                                                          |
| Windows, Proton ARM64, .NET / XNA (32-bit)      | ✅      | ✅      | ❓        | ❓             | wine-mono                                                                                                                                                                                |
| Windows, Proton ARM64, Unreal Engine 3 (32-bit) | ❌      | none   | none     | none          | Legacy PhysX installer (msiexec) waits with no window on first start; engine stops at init without it                                                                                    |
| Windows, Proton ARM64, Unreal Engine 4 (D3D11)  | ❌      | none   | none     | none          | Engine asks for feature level 11_0; DXVK on PanVK offers 10_1 (no tessellation). Beyond this GPU                                                                                         |
| Remote Play stream from Windows PC              | ✅      | none   | none     | ⚠️            | Software decode, H.264, streaming client about one core. Use controller Steam button: Shift+Tab goes to host and stalls picture                                                          |

## What columns mean

- **Starts:** reaches its title screen or menu.
- **On GPU:** renders on Mali, not on CPU renderer (llvmpipe).
- **MangoHud:** HUD draws in game with launch option `mangohud %command%` or `MANGOHUD=1 %command%`; launch handler loads matching library for x86 titles.
- **Steam overlay:** Shift+Tab or controller Steam button opens overlay in game.

## Launch handler

Steam ARM's launch handler decides per title, before game starts, with no launch options needed:

- x86 Steam overlay on for Linux x86 titles
- MangoHud when title asks for it
- Godot 4 titles on OpenGL renderer
- Unity titles: Vulkan renderer where player carries it, else GL 4.5 report; 32-bit Unity players with overlay off
- 32-bit titles: `-vulkan` and `-force-vulkan` removed (Vulkan forwarding is 64-bit only)
- Start scripts (`hl2.sh` style) followed to binary they start

Title profiles in `/etc/steam-arm/titles.conf` change it per title, by Steam app id:

```
<appid> overlay=x86|vulkan|off  mangohud=on|off  godot=gl|vulkan  unity=vulkan|gl  env=A=1;B=2  args=-x;-y
<appid> gl32=off  vk32=keep
```

Per title launch options override profiles: `STEAM_ARM_OVERLAY=x86|vulkan|off %command%`.

Windows titles run through Valve's ARM64 Proton, where handler does not run. Launcher sets `PROTON_DXVK_D3D8=1` for them, so Direct3D 8 titles use DXVK.

## Updating this document

- Add row per game type: build (Linux or Windows, 32-bit or 64-bit), graphics API, engine where it decides behaviour.
- Mark ✅ only for what was seen: menu on screen, GPU in use, HUD or overlay drawn.
- Change **Last updated** date, and **Run on** when client, FEX tool or Mesa change.

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
