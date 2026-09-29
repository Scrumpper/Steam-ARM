# Steam ARM · native ARM64 Steam client installer

**Feature list** · Steam Frame's ARM64 client · runs on host GPU as ARM program · x86 titles through emulation with graphics forwarded to native drivers · Windows titles through ARM64 Proton · Remote Play with software decode · controller access rules · one package, nothing bundled

---

## Client
- Native ARM64 build of Steam client, build Valve produced for its ARM based VR headset, Steam Frame; client interface, input stack, downloader and shader system run on CPU and GPU without emulation; in Linux x86 titles, Steam overlay's in-game part is x86 code loaded into emulated title
- Client package downloads from Valve on first start, then client restarts itself; sign in from Big Picture
- Installs into desktop user account, not root: first regular account on system (uid 1000) by default, `GAMEUSER` to choose another; account is created only when none exists, with generated password printed once
- Own home directory under game user's account (`.local/share/steam-arm` by default, `ARMHOME_DIR` in `/etc/steam-arm/steam-arm.conf`) and own library, so it coexists with x86 client from other routes; run one at time
- `steamos-session-select`, which power menu's Switch to Desktop runs, restarts client in desktop interface
- `--desktop` or `--bigpicture` with client already running closes it through its own shutdown and restarts it in that interface
- `steam-arm` launches Deck interface; `steam-arm --desktop` launches desktop interface, `--bigpicture` forces Deck interface, `STEAM_ARM_UI=desktop` in `/etc/steam-arm/steam-arm.conf` makes desktop default
- `steam-arm-tray`: Steam icon in panel tray with Open, Open in desktop mode, Stop and Quit, started with session through autostart entry and by launcher; this client build registers no tray item of its own
- Window rule for KDE: client draws its own frame and asks window manager for none, and this build does not move window when that frame is dragged; rule gives client's normal windows manager's frame so they move and resize like any other window; Big Picture is fullscreen and unaffected

## Games
- x86 Linux titles run through emulation tool client downloads, against x86-64 Ubuntu 24.04 root filesystem installer prepares at `/opt/fex-rootfs`
- Windows titles run through ARM64 Proton build client downloads; Direct3D through DXVK
- `steam-arm-compatmap <appid> <tool>`: pins title to compatibility tool in client's stored configuration, for title with Linux build on record but Windows files installed
- Titles protected by anti-cheat do not run: anti-cheat and DRM components require system call filter emulator does not implement

## Graphics
- OpenGL and Vulkan calls from emulated guest forwarded to host's native Mesa libraries through FEX thunks, not emulated; host thunks at `/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks`, guest thunks at `/usr/share/fex-emu/GuestThunks`, root filesystem linked as `/usr/share/guestos/fex-mesa`
- FEX `Multiblock` enabled in game user's FEX configuration
- 32-bit titles: OpenGL forwarded, Vulkan not (FEX forwards Vulkan for 64-bit code only); launch handler removes `-vulkan` and `-force-vulkan` from them, profile key `vk32=keep` keeps it
- Profile key `gl32=off`: title not detected as 64-bit, without OpenGL forwarding, on x86 Mesa inside emulation (slower), through FEX app configuration (`ThunksDB` GL off) merged with Steam's FEX settings
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
- One script: `steam-arm-install.sh`; GitHub source also builds `.deb` package that installs command `steam-arm-setup` and installer script; nothing downloads at package install
- `sudo bash steam-arm-install.sh` installs core (host packages, root filesystem and graphics provider, client package, launcher) and offers optional components: `glx-lax`, `vk-spoof`, `map-count`, `xpad-dedup`, `pad-hidraw`, `pad-xbox`, `desktop`, `desktop-mode`, `icon-bigpicture`, `icon-desktop`, `tray`, `page-size`
- Component choice through keyboard checklist, desktop dialog (zenity) when started with no controlling terminal in graphical session, or `--select a,b`, `--skip a,b`, `--defaults`; `--list` prints components
- Idempotent: re-running refreshes every file, and component deselected on re-run is removed again
- Installed games kept: install, re-run, component changes and package upgrade leave game library (`steamapps`), sign-in and settings untouched; only client's program folder is replaced, and only when missing or not ARM64
- `desktop` component: application menu entry "Steam ARM", right-click actions open either interface; window rule gives desktop interface windows title bar, and KWin reloads its rules so it applies at once
- `desktop-mode` component: second menu entry, "Steam ARM (Desktop mode)", found by searching "desktop" or "sign in"
- `icon-bigpicture` and `icon-desktop` components: desktop icon for either entry, each chosen on its own; neither selected places none
- `tray` component: tray helper below; deselecting it removes helper and its autostart entry and stops it
- Menu icons made at install from client's own `steam_tray.ico`: dark, grainy green disc with small squares of vivid colour, chartreuse logo for Big Picture and bone logo for desktop mode; fixed seeds, so every install draws same icons; nothing bundled
- Page size check before anything installs: emulation needs 4K pages; 16K or 64K kernel stops setup with fix for that system, `STEAM_ARM_IGNORE_PAGESIZE=1` to skip
- `page-size` component: on Raspberry Pi with 16K page kernel, adds `kernel=kernel8.img` to firmware `config.txt` in marked block, keeps backup, and asks for reboot and second run; deselecting removes block again; no effect on other systems
- Header names no board; same script runs on its own or from units, TTY gated, `NO_COLOR` honoured
- Removal: re-run with components deselected removes those components; script has no uninstall option for host packages, root filesystem, client package or launcher; deleting client's directory in account it installed into removes client and every game in it

## Requirements
- ARM64 system with working Vulkan driver; Debian or Ubuntu family distribution, since installer uses `apt`
- Mesa graphics stack for `glx-lax`; `vk-spoof` written for PanVK on Mali
- Ubuntu family system for FEX PPA; other systems need FEX from another source
- No hardcoded GPU render node or card index; only board detection is Raspberry Pi check in `page-size`

## Compatibility
- Tested on one device: RK3588 board with Mali-G610 GPU, Armbian based image
- `COMPATIBILITY.md` records what has and has not been tested, per device class and per driver

## Charts
- **[GAMES.md](GAMES.md):** game types tested on this package, by build, graphics API and engine, and what works for each
- **[COMPARISON.md](COMPARISON.md):** this package beside other routes to Steam on ARM64

## Not included
- Anti-cheat titles
- VR runtime; Steam Frame's runtime is not part of this package
- Steam client, emulation tool, root filesystem, Proton: all downloaded at run time from their own sources, none bundled

---

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam, Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
