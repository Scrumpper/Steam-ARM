# Steam-ARM · ARM64 Steam Client Installer

**Feature list** :
  The Steam Frame's ARM64 (VR) client · runs on host GPU as ARM program · x86 titles through emulation with graphics forwarded to native drivers · Windows titles through ARM64 Proton · Remote Play with software decode · controller access rules 

This is an installable ARM64 client. 

Provides:

| Component    | Scope         | Note                                                                                               |
|--------------|---------------|----------------------------------------------------------------------------------------------------|
| `glx-lax`    | Mesa specific | Addresses Mesa client library limit with titles that bind one OpenGL context from several threads. |
| `vk-spoof`   | Mali specific | Written for PanVK Vulkan driver on Mali; not needed on other Vulkan drivers.                       |
| `map-count`  | Generic       | Raises `vm.max_map_count`; applies to any Linux system running Proton.                             |
| `xpad-dedup` | Generic       | Applies to any system where kernel exposes duplicate joystick node for pad.                        |
| `pad-hidraw` | Generic       | Applies to any system using kernel `xpad` driver's device list.                                    |
| `pad-xbox`   | Generic       | Applies to any XInput pad from maker other than Microsoft.                                         |
| `desktop`    | Generic       | Application menu entry and desktop icon; no hardware dependency.                                   |

---

## Client
- Native ARM64 build of Steam client; Produced by Valve for the Steam Frame ARM based VR headset.
- Client package downloads from Valve on first start, then client restarts itself; sign in from Big Picture or click the power button in big picture mode and go to Desktop Mode.
- Installs into desktop user account, not root: first regular account on system (uid 1000) by default, `GAMEUSER` to choose another; account is created only when none exists, with generated password printed once
- Own home directory under game user's account (`.local/share/steam-arm` by default, `ARMHOME_DIR` in `/etc/steam-arm/steam-arm.conf`) and own library, so it coexists with x86 client from other routes; run one at time
- `steam-arm` launches Deck interface; `steam-arm --desktop` launches desktop interface, `--bigpicture` forces Deck interface, `STEAM_ARM_UI=desktop` in `/etc/steam-arm/steam-arm.conf` makes desktop default
- `steam-arm-tray`: Steam icon in panel tray with Open, Open in desktop mode, Stop and Quit, started with session through autostart entry; this client build registers no tray item of its own
- Window rule for KDE: client draws its own frame and asks window manager for none, and this build does not move window when that frame is dragged; rule gives client's normal windows manager's frame so they move and resize like any other window; Big Picture is fullscreen and unaffected

## Games
- x86 Linux titles run through emulation tool client downloads, against x86-64 Ubuntu 24.04 root filesystem installer prepares at `/opt/fex-rootfs`
- Windows titles run through ARM64 Proton build client downloads; Direct3D through DXVK
- `steam-arm-compatmap <appid> <tool>`: pins title to compatibility tool in client's stored configuration, for title with Linux build on record but Windows files installed
- Titles protected by anti-cheat do not run: anti-cheat and DRM components require system call filter emulator does not implement

## Graphics
- OpenGL and Vulkan calls from emulated guest forwarded to host's native Mesa libraries through FEX thunks, not emulated; host thunks at `/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks`, guest thunks at `/usr/share/fex-emu/GuestThunks`, root filesystem linked as `/usr/share/guestos/fex-mesa`
- FEX `Multiblock` enabled in game user's FEX configuration
- `glx-lax` component: private copy of Mesa GLX client library, `libGLX_steamarmlax.so.0`, with one check relaxed, for titles that bind single OpenGL context from more than one thread; rebuilt against system Mesa when that library changes, own library name through `patchelf` so system copy is untouched
- `vk-spoof` component: implicit Vulkan layer `VK_LAYER_STEAM_ARM_feature_spoof`, built from source at install, reports device features DXVK lists as mandatory and Mali driver does not expose, then removes them again from device creation; self-check through `vulkaninfo` when present
- `map-count` component: `vm.max_map_count = 2147483642` in `/etc/sysctl.d/zz-steam-arm.conf`, value Proton expects; `zz-` name so it is read after `/etc/sysctl.conf`

## Remote Play
- Streaming runs package's x86-64 streaming client under system emulator, with software decoding
- `steam-arm-remoteplay` pins hardware decoding off and HEVC off in client's stored configuration, so host keeps to H.264 and software decoder; streaming client decodes through Vulkan Video, which Mali driver does not provide, and with hardware decoding advertised session can sit on launch screen and never finish negotiating
- Launcher applies setting before every start, including first; `--check` reports without changing anything
- Game window in background on host renders nothing new, so stream shows one frame and takes no input; keep game in foreground on host

## Controllers
- `pad-hidraw` component: `/etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules` hands pad's `/dev/hidraw` node and `/dev/uinput` to logged-in user, so client reads pad directly for rumble and battery level; covers every pad kernel `xpad` driver recognises, 243 devices, matched on vendor and product so keyboards and mice from same makers stay excluded
- `xpad-dedup` component: `/etc/udev/rules.d/71-steam-arm-xpad-dedup.rules` unbinds driver from headset interface some third-party Xbox 360 style pads expose, so one pad is one joystick and two-player game does not hand player 2 copy of player 1; `steam-arm-xpad-dedup` does same for pads already connected
- `pad-xbox` component, off by default: `steam-arm-pad-xbox.service` presents XInput pads from other makers as Xbox 360 pads through `uinput`; off because client's own Steam Input re-identifies pads, and launcher pauses service while client runs in case another route enabled it

## Emulation
- FEX-Emu installed from project's PPA: `fex-emu-armv8.2`, 32-bit and 64-bit binfmt
- `steam-arm-fex-binfmt.service`: FEX owns x86 execution persistently; box64 and box32 binfmt registrations off while it runs
- x86-64 root filesystem: Ubuntu 24.04, prepared by installer at `/opt/fex-rootfs/Ubuntu_24_04`; about 2 GB
- Client's runtime container built through `bubblewrap`

## Installer
- Package: `steam-arm-setup_1.0_arm64.deb`, installs command `steam-arm-setup` and installer script; nothing downloads at package install
- `sudo steam-arm-setup` installs core (host packages, root filesystem and graphics provider, client package, launcher) and offers optional components: `glx-lax`, `vk-spoof`, `map-count`, `xpad-dedup`, `pad-hidraw`, `pad-xbox`, `desktop`
- Component choice through keyboard checklist, or `--select a,b`, `--skip a,b`, `--defaults`; `--list` prints components
- Idempotent: re-running refreshes every file, and component deselected on re-run is removed again
- `desktop` component: application menu entry and desktop icon for account client installs into
- Header names no board; same script runs on its own or from units, TTY gated, `NO_COLOR` honoured
- Removal: re-run with components deselected, or delete client's directory in account it installed into; `apt purge steam-arm-setup` removes package

## Requirements
- ARM64 system with working Vulkan driver; Debian or Ubuntu family distribution, since installer uses `apt`
- Mesa graphics stack for `glx-lax`; `vk-spoof` written for PanVK on Mali
- Ubuntu family system for FEX PPA; other systems need FEX from another source
- No hardcoded GPU render node, card index or board detection

## Compatibility
- Tested on one device: H96 Max V58, RK3588 board with Mali-G610 GPU
- `COMPATIBILITY.md` records what has and has not been tested, per device class and per driver

## How routes compare

Legend: ✅ yes  ⚠️ partly, or with conditions  ❌ no  ❓ not publicly verified

| Route | Client itself is native ARM | Installs onto your system | Mali and PanVK | Adreno | Apple GPU | Remote Play handled |
|---|---|---|---|---|---|---|
| **This package** | ✅ | ✅ host, no sandbox | ✅ tested on one RK3588 board | ⚠️ untested, skip `vk-spoof` | ⚠️ untested, needs 4K page environment | ✅ decode pinned before first start |
| Canonical arm64 Steam snap | ❌ x86 client under FEX | ⚠️ snap confinement | ❌ open issue #471 since 2026-01-10 | ⚠️ other driver loading bugs open | ❓ | ❓ |
| Box86 and Box64 | ❌ x86 client under Box64 | ✅ host | ✅ long standing SBC route | ✅ | ❓ | ❓ |
| steamclienttermux, Android | ✅ | ⚠️ Termux and PRoot | ❌ Adreno only | ✅ Turnip | ❌ | ❓ |
| ROCKNIX and pocknix-os | ✅ | ❌ replaces OS | ❌ Snapdragon only | ✅ | ❌ | ❓ |
| UbuntuAsahi `steam-arm64` | ✅ | ✅ host, in microVM | ❌ | ❌ | ✅ Honeykrisp | ❓ |
| Windows on ARM, Prism | ❌ x86 under Prism | ✅ host | ❌ | ✅ Snapdragon X | ❌ | ✅ native to Windows |
| macOS on Apple Silicon | ✅ since 2025-06 beta | ✅ host | ❌ | ❌ | ✅ | ✅ |

Reading table: routes that run **native** client are this package, Android and
handheld projects, UbuntuAsahi, and macOS. Of those, everything except this one targets
Adreno or Apple GPUs. Routes that cover Mali at all run **x86** client under
emulation, or fail on driver.

## Not included
- Anti-cheat titles
- VR runtime; Steam Frame's runtime is not part of this package
- Steam client, emulation tool, root filesystem, Proton: all downloaded at run time from their own sources, none bundled

---

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam, Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
