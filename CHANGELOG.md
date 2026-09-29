# Changelog

All notable changes to this project are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1] - 2026-09-28

### Added

- Launch handler, `/usr/local/lib/steam-arm-handler.py`. Valve's FEX compatibility tool runs it in place of its removal of `LD_PRELOAD`, before runtime container starts. It decides per title, with no launch options:
  - Steam overlay: x86 overlay core for Linux x86 titles by default. Title profile `overlay=vulkan` adds arm64 overlay core and arm64 overlay Vulkan layer, for Vulkan titles; `overlay=off` removes overlay.
  - MangoHud: `mangohud %command%` and `MANGOHUD=1 %command%` both work in Linux x86 titles, OpenGL and Vulkan.
  - Godot 4 titles: OpenGL renderer and GL 3.3 report, found from game's `.pck` header. Godot's Vulkan renderer freezes on splash on PanVK; Panfrost reports GL 3.1.
  - Unity titles, found from player next to game: 64-bit players that carry Vulkan renderer start with `-force-vulkan` and overlay for Vulkan titles; other Unity 5 and later players get GL 4.5 report, since their OpenGL core context asks for more than Panfrost's 3.1 and title stops with `GLXBadFBConfig`; 32-bit Unity players start with Steam overlay off, as title stops when overlay attaches. Profile key `unity=vulkan|gl`.
  - If handler fails, tool behaves as Valve wrote it.
- Title profiles, one Steam app id per line: `/usr/local/share/steam-arm/titles.conf` (shipped), `/etc/steam-arm/titles.conf` (local), and per-user file. Keys: `overlay`, `mangohud`, `godot`, `env`, `args`. Launch options `STEAM_ARM_OVERLAY=x86|vulkan|off` and `STEAM_ARM_PRELOAD_KEEP=a,b` override profiles.
- arm64 Steam overlay Vulkan layer, which client ships but does not register, registered behind `STEAM_ARM_VK_OVERLAY`; handler sets it only for titles profiled `overlay=vulkan`.
- Direct3D 8 titles under Proton run through DXVK's `d3d8`: launcher sets `PROTON_DXVK_D3D8=1`. Proton's default for Direct3D 8, wined3d on OpenGL, draws them wrong on Mali driver. Launch option `PROTON_DXVK_D3D8=0 %command%` restores default.
- Launcher removes shared-memory segments no process maps from `/dev/shm`, at start and every minute: Steam overlay leaves 26 MB segment behind per game session here, and FEX leaves stats file per process. Overlay segments stay mapped by `steamwebhelper` while client runs, so sweep skips them; they are reclaimed at next client start.
- Shipped profile for one custom OpenGL engine title that stops when Steam overlay attaches (`overlay=off`).
- Page size check before anything installs. Emulation needs 4K pages; on 16K or 64K kernel setup stops and names fix for that system (Raspberry Pi, Apple Silicon, other). `STEAM_ARM_IGNORE_PAGESIZE=1` skips check.
- `page-size` component: on Raspberry Pi with 16K page kernel, adds `kernel=kernel8.img` to firmware `config.txt` in marked block, keeps backup, asks for reboot and second run. Deselecting removes block. No effect on other systems.
- `desktop-mode` component: menu entry "Steam ARM (Desktop mode)", opens client in its desktop interface.
- `icon-bigpicture`, `icon-desktop` and `tray` components: each desktop icon and tray icon chosen on its own, or none.
- Power menu's Switch to Desktop: `steamos-session-select` restarts client in desktop interface.
- `steam-arm --desktop` and `--bigpicture` switch running client: it closes through its own shutdown and starts again in that interface.
- Right-click actions on main menu entry open either interface.
- `--help` prints usage: options, components with defaults marked, examples, environment variables.
- `GAMES.md`: compatibility by game type (build and graphics API). `COMPARISON.md`: this installer beside other routes to Steam on ARM64.
- Installer states that installed games, sign-in and settings are kept; docs say same, and removal section says which step deletes games.

### Changed

- Installer ships as plain script `steam-arm-install.sh`, readable before running; `.deb` still builds from GitHub source (`build-deb.sh`).

### Fixed

- Titles drew on CPU renderer (llvmpipe) after fresh install. Client downloads Valve's FEX tool at first title start, after launcher applied its settings, so GL and Vulkan forwarding stayed off until next client start. Launcher now applies them within one second of tool appearing or being replaced, and covers `/run/gfx/main`, where current runtimes mount graphics libraries.
- Steam overlay UI (`gameoverlayui`) crashed on every start: client's helper programs load libraries from client's own directory, which launcher now puts on library path.
- Client's desktop windows had no title bar until next login: setup now tells KWin to reload its window rules after writing frame rule.
- Menu icon missing on fresh install: 1.0 inverted icon from x86 Steam package in rootfs, which fresh rootfs does not carry. Icons now come from client's own `steam_tray.ico`, drawn during first start once client has downloaded that file; KDE menu cache refreshes after.
- Installer created account from saved setting naming account absent on system. Such setting now gets ignored with warning, and installer picks desktop user; new account gets created only when `GAMEUSER` is given on command line.
- `vk-spoof` resolves `vkDestroyDevice` when device is destroyed, not straight after device creation.
- Every title failed to start, with `Bus error`, after many game sessions: `/dev/shm` filled with segments Steam overlay left behind, and launch helper died writing to one. Launcher now clears unmapped segments; segments `steamwebhelper` still maps are reclaimed at client restart, so restart client after long run of sessions.
- Launch handler did not run when FEX tool had been patched by other steam-arm installer (same marker, other handler path). Setup and launcher now check for their own handler path and re-point tool.
- Re-run keeps client home set by earlier run: installer reads `ARMHOME_DIR` from `/etc/steam-arm/steam-arm.conf` before its default, so re-run with no `ARMHOME_DIR` in environment never moves client away from its games.

### Changed

- Menu icons: dark, grainy green disc with small squares of vivid colour; chartreuse logo for Big Picture, bone logo for desktop mode.
- `desktop` component covers menu entry and window frame rule only; desktop icons and tray are components of their own.
- Launcher starts tray helper, so tray icon appears in session setup ran in, not only after next login.
- Menu entry no longer labelled Big Picture only.
- Component checklist shows all twelve components without scrolling.

### Known issues

- Proton ARM64 titles: MangoHud and arm64 Steam overlay layer each crash title at device creation, together with `vk-spoof`. Handler does not run for these titles; leave `MANGOHUD` unset for them.
- Steam overlay in OpenGL titles: controller Steam button opens it but cannot close it; Shift+Tab or on-screen close button does. In Vulkan titles Shift+Tab does not open it; controller Steam button opens and closes it.
- Remote Play: Shift+Tab goes to host PC and can stall picture; use controller Steam button.
- Some native OpenGL titles stop when Steam overlay attaches. Profile `overlay=off` for that title, or launch option `STEAM_ARM_OVERLAY=off %command%`.
- Some native titles leave one thread behind on quit; client shows title as running until Stop.
- Windows titles whose first start runs legacy PhysX installer (msiexec) stop there: installer waits with no window, and title does not start without it.

## [1.0] - 2026-09-23

### Added

- Initial public release of `steam-arm-setup`, installer for Valve's native ARM64 Steam client and supporting components on ARM64 Debian or Ubuntu family system.
- Selectable components (`--select`, `--skip`, `--defaults`, `--list`):
  - `glx-lax`: private Mesa GLX copy, for titles that bind one OpenGL context from several threads.
  - `vk-spoof`: Vulkan layer that reports device features Direct3D translation layer requires, written for PanVK on Mali.
  - `map-count`: raises `vm.max_map_count`.
  - `xpad-dedup`: drops duplicate joystick node.
  - `pad-hidraw`: hands pad hidraw nodes and `/dev/uinput` to logged-in user, covering 243 pads.
  - `pad-xbox`: presents other XInput pads as Xbox 360 pads.
  - `desktop`: adds menu entry and desktop icon.
- Debian packaging (`build-deb.sh`) producing `steam-arm-setup_1.0_arm64.deb`.
- Nothing is downloaded until `sudo steam-arm-setup` runs.

---

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
