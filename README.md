# Steam ARM

Valve's native ARM64 Steam client on ARM64 Linux · x86 Linux titles through FEX · Windows
titles through ARM64 Proton · one installer script · settings menu `steam-arm-config`

This README is instruction booklet. Section 1 covers install and first game; use index to
jump to details.

Other routes to Steam on ARM64, and where each one runs: `COMPARISON.md`.

---

## Contents

1. Install, then play
2. Read this first
3. Requirements
4. Install
5. Setup menu (steam-arm-config)
6. GPU detection
7. First start
8. Component selection
9. Graphics route per title
    - Automatic Windows build
10. Page size
11. x86 client (Armv8.0 CPUs)
12. Playing games
    - Linux x86 titles
    - Windows titles
    - GE-Proton (optional)
    - Shader pre-caching
    - PhysX install step
    - Linux build installed as Windows build
    - Title profiles and launch options
13. Fixing games
14. Remote Play
15. Updating
16. Settings backup and restore
17. Uninstall
18. Advanced settings
19. Driver archive from local file
20. Custom driver archive
21. Driver archive build
    - On x86-64 PC
    - On GitHub (Actions)
22. Troubleshooting
23. What this does not do
24. Other documents
25. Credits
26. Disclaimers

---

## Install, then play

1. Check system: `bash steam-arm-install.sh --detect` prints GPU family, drivers, page
   size and default components; it installs nothing and needs no root. Page size must
   read `4096`; other results: see GPU detection and Page size.
2. Run installer in terminal:

   ```
   sudo bash steam-arm-install.sh
   ```

   Settings menu opens. Pick Install / Setup and confirm detected hardware, page size,
   Vulkan, parts and account; summary page starts install. `--defaults` in place of menu
   installs recommended components with no questions.
3. When installer ends with notice that account gained groups, log out and log back in
   (or restart) before first start.
4. Start "Steam ARM" from application menu, or run `steam-arm`. First start downloads
   client package and restarts client once; this takes several minutes. Desktop
   notification reports download, unpack and install phases meanwhile.
5. Sign in from Big Picture, or from "Steam ARM (Desktop mode)" menu entry.
6. Install game, press Play.

Re-running installer, changing components and uninstalling keep installed games, sign-in
and settings, unless you ask for their removal.

## Read this first

This installs Steam Frame's Steam client; Armv8.0 CPUs get Valve's x86 client through
emulation in its place (see x86 client). x86 code runs through emulation tool client
downloads. Windows titles run through Valve's ARM64 Proton build.

Nothing downloads before installer runs. Steam client, emulation tool and Proton build
download when installer runs and client is set up.

Installing, re-running installer and changing components leave game library
(`steamapps`), sign-in and settings untouched; only client's own program folder is
replaced, and only when it is missing or damaged.

## Requirements

- ARM64 system. GPU family detection sets defaults per GPU; Windows titles need Vulkan
  driver, native OpenGL titles run without one. See GPU detection.
- ARM64 CPU. Armv8.1 or newer with LSE atomics (`atomics` in `Features` line of
  `/proc/cpuinfo`) runs Valve's native ARM64 client: Raspberry Pi 5 (Cortex-A76), RK3588
  (Cortex-A76 and A55). Armv8.0 CPUs without LSE (Cortex-A53, A57, A72, A73: Raspberry Pi
  4, RK3399, S922X) run Valve's x86 client through emulation instead, since native builds
  newer than 15 April 2026 (client 1776387948) stop there with SIGILL
  (<https://github.com/ValveSoftware/steam-for-linux/issues/13288>). Setup picks client
  type by itself, before any package change, and names it; see x86 client.
- Ubuntu 25.10 or newer, Debian 13 or newer, or distribution built on them. Client needs
  SDL3 packages (`libsdl3-0`, `libsdl3-image0`, `libsdl3-ttf0`), which Ubuntu 24.04 and
  Debian 12 lack. Before any package or package source change, setup reads
  `apt-cache policy` for each distribution package it installs and stops with names of
  missing ones; FEX packages are checked once FEX package source is in place.
- Debian or Ubuntu family distribution, since installer uses `apt`. Before any change,
  setup checks for `apt-get`, `apt-cache`, `dpkg` and package architecture `arm64`, and
  stops with `No change made` otherwise; `--help`, `--detect` and `--list` run anywhere.
  FEX, emulation tool for x86 game code, installs from FEX's Ubuntu PPA `ppa:fex-emu/fex`:
  - Ubuntu family: added with `add-apt-repository`.
  - Debian 13 (trixie) and Raspberry Pi OS built on it: setup writes same PPA as apt
    source `/etc/apt/sources.list.d/steam-arm-fex.sources` with Ubuntu 24.04 (noble)
    build, which fits Debian 13's C library (glibc 2.41) and Qt 5 packages. Signing key
    comes from `keyserver.ubuntu.com`; setup compares its fingerprint with pinned
    `EDB98BFE8A2310DC9C4A376E76DBFEBEA206F5AC` (Launchpad's key for this PPA) before
    writing `/etc/apt/keyrings/steam-arm-fex.gpg`. Earlier FEX source naming Debian
    release (from `add-apt-repository` on Debian) is renamed to `.disabled`.
    Raspberry Pi OS desktop lacks `libibus-1.0-5`, which client window process
    (`steamwebhelper`) loads; setup installs it with other host packages.
  - Debian 12 (bookworm): host package check stops setup before any change, since
    Debian 12 has no SDL3 packages and no `libgtk2.0-0t64`. Upgrade to Debian 13.
  - Debian 11 and older: host package check stops setup before any change (no SDL3
    packages). Upgrade to Debian 13.
  - FEX from `fex-emu` package already installed: setup adds no package source.
  - FEX from another source (`FEX` command not owned by `fex-emu` package, for example
    build installed under `/usr/local`): setup adds no package source and installs no FEX
    packages. FEX's x86 binfmt entries (`FEX-x86`, `FEX-x86_64` in
    `/proc/sys/fs/binfmt_misc`) must be registered, else setup stops before any change.
    Thunk folders (`HostThunks`, `GuestThunks`, `ThunksDB.json`) come from FEX's own
    prefix, then `/usr`, then `/usr/local`; with no complete set, game user's FEX
    configuration gets GL and Vulkan thunks off and setup prints warning.
  `--remove` deletes setup's Debian source file and key once no FEX build is installed;
  while FEX stays, removal summary names command for both files.
- Mesa graphics stack for `glx-lax`. `vk-spoof` and `gpu-in-emulation` are written for
  Mali (Panfrost and PanVK) and are on by default on Mali GPUs only. Tested with Mesa
  26.1.
- 4K memory pages, or Raspberry Pi where installer switches kernel; see Page size.
- Network during install: host packages, x86 root filesystem, client package and driver
  archive download from their sources.

Checks to run before install, and results on test device: `COMPATIBILITY.md`.

## Install

One script, readable before running:

```
sudo bash steam-arm-install.sh             # settings menu (terminal)
sudo bash steam-arm-install.sh --defaults  # recommended components, no questions
```

With no options in terminal, installer opens settings menu `steam-arm-config` with itself
as installer; Install / Setup there runs guided install. With no options and no terminal
in graphical session, installer shows component checklist through zenity.

Installer installs into desktop user account, not root, and defaults to account of last
run, else first regular account on system (uid 1000).
`sudo env GAMEUSER=name bash steam-arm-install.sh` picks another account. Setup refuses
root as game account, and names with characters other than letters, digits, `.`, `_`, `@`
and `-`. When named account does not exist, setup creates it: password from
`--password-stdin` (first line of standard input, never printed or logged), else
14-character password setup makes and prints once; with no terminal, that password goes
to `/root/steam-arm-password-<name>.txt`, readable by root only. When account gains
`video`, `render`, `input` or `audio` group, installer says so; log out and log back in
before first start. Options: `--help`.

`.deb` package built from GitHub source installs command `steam-arm-setup` with same
options. `steam-arm-setup --detect`, `--list` and `--help` run without root.
`steam-arm-setup` without options in terminal opens setup menu, which asks for
administrator rights through `sudo` when needed. Package also adds application menu entry
"Steam ARM Setup", which opens that menu in terminal. Package install or upgrade replaces
setup script only: launcher, launch handler and settings menu on system stay at earlier
version until setup runs again. When client set up earlier (by package, zip or script) is
from other version, package says so, naming `sudo steam-arm-setup --keep`.

## Setup menu (steam-arm-config)

`steam-arm-config` is menu app for settings after install, installed as
`/usr/local/bin/steam-arm-config`. Application menu entry "Steam ARM Settings" (added with
launcher) and tray item Steam ARM Settings open it in terminal emulator. Front end: built-in full-screen screens (Python
`curses`) with textured background and light dialog box, when `python3` with `curses` is
present and terminal can place cursor; else `dialog` when installed, else `whiptail`, else
plain prompts. `STEAM_ARM_DIALOG=builtin|dialog|whiptail|read` picks one. `NO_COLOR` turns
colour off in built-in screens. Each menu opens with cursor on item chosen last. Changes
ask for administrator rights through `sudo`: screen clears, heading
`Administrator password for <user> (sudo):` comes first, sudo asks on next line, then menu
returns. On system without `sudo`, menu says to log in as root (`su -`), then run
`steam-arm-config`. Keys: arrows move, Enter selects, TAB
reaches buttons, SPACE toggles list items.

Main menu, built-in screens: `installer-menu.png`.

Sections:

1. Information: system (board, GPU, drivers, CPU), Steam ARM status, notes for this
   hardware. Status row `Client type` names native ARM64 or x86 client and why; with x86
   client, `FEX tool` row says system FEX serves it. Status names custom driver tree as
   `present (custom drivers, sha <first 12>…)`; row `Driver archive` names source:
   `download`, `local file <path>` or `custom <path>`. System row `Vulkan gaps` lists
   features `vk-spoof` reports that Vulkan driver lacks (`none` when driver has all;
   `unknown` without `vulkaninfo` or Vulkan driver).
2. Install / Setup: guided install. Hardware (detected choice first), page size, Vulkan,
   parts (recommended, minimal or custom), account, then summary. Account step lists
   existing accounts (normal accounts with login shell and home folder; current user and
   desktop user marked) with cursor on current or desktop user; last entry
   `Create a new account...` asks for name, then password twice (empty: setup makes one
   and shows it at end). With no normal account on system, step opens on new account. Summary names client download (several GB) only when client folder
   holds no client yet; otherwise it says setup keeps present client. Summary row `Client`
   names client type. On CPU without Armv8.1 atomics, x86 client screen (what changes,
   Continue or Back) comes first.
3. Components: Parts, checklist of installed parts; turning one off removes it, games
   stay. Driver archive: source of `gpu-in-emulation` drivers, Download (default), Local
   copy of published archive or Custom archive (see Driver archive from local file, Custom
   driver archive).
4. Graphics: default route for all games, and route per game: automatic, A (forwarding),
   B (Mali drivers in emulation), or forced Linux or Windows build. Automatic also
   clears forced build of that game (Steam closed). B is offered on Mali
   GPU, or with custom driver tree in place; elsewhere menu notes that route B needs Mali
   GPU or custom driver archive, and shows earlier B setting as
   `b (not used on this GPU)`, which can be changed. B on Mali GPU without
   `gpu-in-emulation` is kept, with note that games use forwarding until it is installed.
   Automatic Windows build: on or off (see Automatic Windows build); Route per game lists
   titles it set as `Windows (auto)`, with reason, and marks Windows build as suggested
   where rule matches title but does not apply on this system. CPU drawing notice: on or
   off (see Renderer check). Game lists of Graphics and Games mark titles whose newest game
   log says CPU drawing with `CPU!`.
5. Games: per installed game: Steam overlay, MangoHud, extra environment, extra arguments,
   FEX code cache (see Title profiles), "Rules used at last start", remove all settings of
   that game. Windows titles (Proton
   set in Steam's compatibility tool list, or Windows build installed) show rules and
   remove-all only, with note to use Steam launch options; profiles reach Linux titles
   only. Header names Steam Deck category of game (Verified, Playable, Unsupported or
   unknown) from client's `appcache/appinfo.vdf`, as hint only, since Steam Deck has other
   GPU; "Rules used at last start" adds Steam Deck runtime (`native` or Proton).
6. Controllers: connected pads and their rules; `pad-xbox` on or off.
7. Remote Play: settings state, how pairing works, apply settings now.
8. Maintenance: Update / Repair (setup again with same parts), view logs, hardware
   report, free `/dev/shm` now, back up settings, restore settings (see Settings backup
   and restore), check for new version (see Updating), caches. Hardware report holds
   system, status, notes, detection, profiles, renderer lines, last game start, last 20
   launcher log lines, start, update and error lines of client's bootstrap log, closing
   block of newest setup log, and groups of game account next to groups of its running
   processes (`Not active yet` names groups that need new login). Report leaves out home
   folders, account and full names, host name, Steam sign-in and persona names (from
   `config/loginusers.vdf`), Steam IDs, IPv4 and IPv6 addresses, MAC and e-mail addresses
   and token values; line still holding account, host or sign-in name after that reads
   `(line removed: personal data)`. Caches shows FEX code
   cache sizes (Linux games, Windows games in Proton prefixes, shared folder of
   client) and Steam's shader cache size, and deletes FEX code caches of all games or
   one game; Steam's shader cache is never deleted there. Refused while game runs.
   GE-Proton (ARM64), optional: install, update and removal of GE-Proton builds (see
   GE-Proton (optional)). Client type: Automatic (recommended), Native ARM64 client, x86
   client through emulation, Check native client now (see x86 client).
9. Uninstall: remove Steam ARM and keep games, or remove it with all games.
10. Help / About: `Fixing a game` page (see Fixing games) and About.

Screens that need Steam closed (Install / Setup, Components, Controllers, Update /
Repair, Uninstall, forced build in Graphics, Remote Play apply, Restore settings) offer
`Close Steam` while game account's client runs (Install / Setup: client of account picked
there): menu runs `steam-arm --shutdown` as that account (client's own exit, SIGTERM after
20 s, x86 client 45 s, never SIGKILL) and goes on once client has stopped. While game runs, menu asks to quit
game first; client of another account blocks Uninstall with message.

Command line, same settings from scripts:

| Command                                | Effect                                                  |
|----------------------------------------|---------------------------------------------------------|
| `info`                                 | System, Steam ARM status and hardware notes             |
| `report`                               | Hardware report to `~/steam-arm-report.txt`             |
| `gfx <appid> auto\|a\|b`               | Graphics route of one game                              |
| `gfx-default auto\|a\|b`               | Route for games without their own setting               |
| `profile <appid> key=value ...`        | Profile keys; `key=` removes one, `--clear` all         |
| `compat <appid> linux\|windows\|ge\|clear` | Force Linux, Windows or GE-Proton build, or clear it; Steam closed |
| `auto-build [on\|off]`                  | Automatic Windows build; no value: state, rules, titles |
| `cpu-notice [on\|off]`                  | CPU drawing notice; no value: state                     |
| `components a,b,...`                   | Install exactly these parts (runs setup)                |
| `driver-archive status\|download`      | Driver archive source; `download` clears saved file     |
| `driver-archive local FILE`            | Local copy of published archive (runs setup)            |
| `driver-archive custom FILE SHA256`    | Custom driver archive (runs setup)                      |
| `backup [DIR] [options]`               | Settings backup file in DIR (default: home)             |
| `restore FILE [options]`               | Restore parts of backup file                            |
| `cache`                                | FEX code cache sizes, per game; Steam shader cache size |
| `cache list`                           | One line per cache folder: app id, kind, KB, path       |
| `cache clear all\|<appid>`             | Delete FEX code caches; refused while game runs         |
| `ge-proton [status\|check]`            | GE-Proton builds installed; newest ARM64 release        |
| `ge-proton install\|remove ...`        | Install or remove GE-Proton build (see GE-Proton)       |
| `update-check`                         | Newest GitHub release compared with this version        |
| `help fixing`                          | Prints `Fixing a game` page                             |
| `--help`                               | Usage                                                   |

Profiles from menu and command line go to `/etc/steam-arm/titles.conf`. Logs of setup
runs started from menu: `~/.cache/steam-arm/`. `STEAM_ARM_INSTALLER=file` names setup
script menu runs (default: `steam-arm-setup`, else
`/usr/local/share/steam-arm/steam-arm-install.sh`, which setup writes, else
`steam-arm-install.sh` beside menu app).

## GPU detection

Installer reads kernel driver name of each render node, Mali GPU id from Panthor or
Panfrost, device tree compatible string and PCI vendor, and picks GPU family of
highest ranked node, so discrete card wins over integrated GPU. `/dev/mali0` with no
render node means Arm's closed `kbase` driver. When `vulkaninfo` is installed, it names
Vulkan driver and device. Family sets default state of `vk-spoof`, `gpu-in-emulation`
and `glx-lax`; every other component keeps its own default.

| Family            | GPU                             | On by default                 |
|-------------------|---------------------------------|-------------------------------|
| `mali-csf-v10`    | Mali-G610, G310 (Panthor)       | all three                     |
| `mali-csf-v11`    | Mali-G615, G715 (Panthor)       | `gpu-in-emulation`, `glx-lax` |
| `mali-csf-5thgen` | Mali-G720, G725 class (Panthor) | `gpu-in-emulation`, `glx-lax` |
| `mali-csf-g1`     | Mali-G1 (Panthor)               | `glx-lax`                     |
| `mali-csf`        | other Panthor Malis             | `glx-lax`                     |
| `mali-valhall-jm` | Mali-G57, G77, G78 (Panfrost)   | `gpu-in-emulation`, `glx-lax` |
| `mali-bifrost`    | Mali-G31, G52, G76 (Panfrost)   | `gpu-in-emulation`, `glx-lax` |
| `mali-midgard`    | Mali-T600 to T880 (Panfrost)    | `gpu-in-emulation`, `glx-lax` |
| `mali-panfrost`   | other Panfrost Mali models      | `gpu-in-emulation`, `glx-lax` |
| `mali-utgard`     | Mali-400, 450 (Lima)            | `glx-lax`                     |
| `mali-kbase`      | Mali on closed `kbase` driver   | none                          |
| `adreno-a8xx`     | Adreno 8xx (msm)                | `glx-lax`                     |
| `adreno-a7xx`     | Adreno 7xx (msm)                | `glx-lax`                     |
| `adreno-a6xx`     | Adreno 6xx (msm)                | `glx-lax`                     |
| `adreno`          | Adreno, model not read (msm)    | `glx-lax`                     |
| `adreno-a702`     | Adreno 702                      | `glx-lax`                     |
| `adreno-legacy`   | Adreno 5xx and older            | `glx-lax`                     |
| `apple-agx`       | Apple GPU (Asahi)               | `glx-lax`                     |
| `broadcom-v3d71`  | Raspberry Pi 5                  | `glx-lax`                     |
| `broadcom-v3d42`  | Raspberry Pi 4 (x86 client)     | `glx-lax`                     |
| `broadcom-vc4`    | Raspberry Pi 0 to 3             | `glx-lax`                     |
| `vivante`         | Vivante (etnaviv)               | `glx-lax`                     |
| `img-powervr`     | PowerVR                         | none                          |
| `amd-radv`        | AMD (amdgpu)                    | `glx-lax`                     |
| `amd-radeon`      | AMD, older cards (radeon)       | `glx-lax`                     |
| `nvidia-nouveau`  | NVIDIA (nouveau)                | `glx-lax`                     |
| `nvidia-prop`     | NVIDIA driver                   | none                          |
| `intel`           | Intel (i915, xe)                | `glx-lax`                     |
| `virtio-gpu`      | virtual machine                 | `glx-lax`                     |
| `none`            | no GPU driver                   | `glx-lax`                     |
| `unknown`         | driver not in this list         | `glx-lax`                     |

Notes installer prints per family:

- `mali-csf-v10`: test device's family (RK3588).
- `mali-csf-v11`, `mali-csf-5thgen`: untested. PanVK (Mesa's Vulkan driver) loads on
  these GPUs only with `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`
  <https://docs.mesa3d.org/drivers/panfrost.html>, so 32-bit Vulkan titles stay on
  forwarding there and `vk-spoof` is off by default.
- `mali-csf-g1`: needs Mesa 26.2 or newer <https://docs.mesa3d.org/relnotes/26.2.0.html>.
  Published driver archive (Mesa 26.1.8) does not cover it, so Mali drivers route there
  needs custom driver archive. Untested.
- `mali-csf`: Mali model not in this table; titles run through forwarding.
- Panfrost families: no default Vulkan driver; native OpenGL titles, Windows titles
  unlikely. Mali drivers in emulation serve Java titles there.
- `mali-utgard`: not suitable for Steam games. `mali-kbase`: warning; install needs
  Mesa's Panfrost or Panthor kernel driver.
- Adreno 6xx to 8xx: Windows titles through DXVK expected to work; x86 Adreno drivers for
  32-bit titles not included. `adreno-a702`, Raspberry Pi 4 and 5: Vulkan too limited for
  most Windows titles. `adreno-legacy`: no Vulkan driver, native OpenGL titles only.
  Raspberry Pi 4: x86 client through emulation (Armv8.0 CPU, see x86 client).
- `apple-agx`: not supported on 16K page kernel; setup stops and does not set up `muvm`
  (4K page virtual machine). `broadcom-vc4`: not supported.
  `vivante`: no Vulkan driver, most titles do not run.
- `img-powervr`: Vulkan driver in development, OpenGL through Zink. `nvidia-prop`:
  `glx-lax` not applicable.
- AMD, NVIDIA on nouveau and Intel: forwarding covers them; x86 root filesystem's Mesa
  has their drivers too. `amd-radeon`: OpenGL only, too old for most titles.
- `none`: warning, software rendering only. `unknown`: safe defaults.

`bash steam-arm-install.sh --detect` prints one `key: value` per line: GPU line, family
(with "set by user" when chosen by hand), detected family, GPU name, kernel driver,
Vulkan driver, features `vk-spoof` reports split into `vulkan features native:` and
`vulkan features missing:` (driver's own answer, layer off; full `vulkaninfo` run, in
`--detect` only), driver archive, CPU cores with Armv8 level (`cpu:`), client type
(`client:`), page size, distribution, state of each component, and family note or
warning. Installs nothing, needs no root. Installer and component checklist show same
GPU line.

`GPU_FAMILY=id` in environment uses that family in place of detection, and setup keeps
it for later runs (`GPU_FAMILY_SET=user` in settings file). `GPU_FAMILY=auto` detects
again. Id not in table above stops install with list of valid ids; with `--detect` it
prints warning and valid ids, shows detected family and exits with status 0. Launch
handler reads
same family: Mali drivers route applies to Mali families only (not `mali-csf-g1`), and
32-bit Vulkan titles switch to it on `mali-csf-v10` only.

```
sudo env GPU_FAMILY=mali-bifrost bash steam-arm-install.sh --defaults
```

## First start

Start "Steam ARM" from menu, or run `steam-arm`. First start downloads client package and
restarts itself; this takes several minutes. Sign in from Big Picture, or from
"Steam ARM (Desktop mode)". `steam-arm` refuses to run as root (except `--help`); start it
from desktop account that plays games.

Client shows no window while it downloads. Desktop notification (via `gdbus`, else
`notify-send`) appears at once and updates in place: download in 10 % steps with total
size, unpack, install, then "Client files installed. Steam opens now." Closed when client
exits early; never shown on later starts.

When client exits after applying its own update (exit status 42, or bootstrap log ending
in "Update complete, launching" with no client left running), launcher starts it again, at
most twice per start; during first start, once.

First start that ends before client files are complete (download stopped, client closed,
network gone) stops launcher with message, also as dialog (with `zenity`) when started from
menu: start Steam ARM again to finish download. Bootstrap log:
`.local/share/Steam/logs/bootstrap_log.txt` in client home.

Starting Steam ARM again while first start runs (menu, desktop icon, tray) starts nothing:
notification shows progress (`Steam ARM is still setting up: downloading client files (40% of
648 MB). Steam opens by itself when done.`), dialog with `zenity` when no notification
service runs, text on terminal. Same at normal start until client window process runs, so
interface switch never interrupts start. Tray Open items greyed meanwhile.

Installer downloads client from Valve's stable ARM64 channel and checks it against
checksum in Valve's manifest. On first start client's Steam Frame mode moves it to its
own ARM update channel, and client updates itself from there.

Client starts in Big Picture. Power menu's Switch to Desktop, and desktop mode entry,
restart it in desktop interface; Big Picture entry switches back.

Until first start, menu and desktop entries show plain disc: client's own icon file does
not exist yet. During first start, once client has downloaded that file, launcher redraws
icons with logo and sends KDE icon change signal (`org.kde.KIconLoader.iconChanged`). Icons are Steam's round icon on dark, grainy green disc with small squares of vivid
colour: chartreuse logo for Big Picture, bone logo for desktop mode.

## Component selection

Installer offers set of optional components. Choose them with one of:

- settings menu: Install / Setup (recommended, minimal or custom), or Components
- `--select` followed by list of component names
- `--skip` followed by list of component names to leave out of recommended set
- `--defaults` to accept recommended selection without prompting
- `--keep` to reuse components saved by last run without prompting
- desktop dialog with checklist, when installer starts with no options and no
  controlling terminal in graphical session and zenity is present

`--list` prints components; `--help` marks components on by default on this system.
Defaults: `pad-xbox`, `shader-cache` and `kde-input-prompt` off; `vk-spoof`,
`gpu-in-emulation` and `glx-lax` follow GPU family (see GPU detection); all others on.

When GPU family changes between runs, `vk-spoof`, `gpu-in-emulation` and `glx-lax` take
new family's defaults, except parts set by hand in checklist, menu, `--select` or `--skip`
(`COMPONENTS_USER_SET` in settings file). `--defaults` clears that record. First run after
upgrade from 1.2, which saved no family record, only turns such parts off.

- `glx-lax`: Installs private copy of Mesa GLX client library, for titles that bind one
  OpenGL context from several threads. Rebuilt after every package upgrade that changes
  system Mesa. (scope: Mesa specific)
- `vk-spoof`: Installs Vulkan layer that reports device features Direct3D translation
  layer requires and Mali driver does not expose, then removes them again from device
  creation. (scope: written for PanVK on Mali; on by default on Mali-G610 class only)
- `gpu-in-emulation`: Installs Mali drivers inside x86 emulation, in second copy of root
  filesystem; launch handler picks them for titles that fail on forwarding. See Graphics
  route per title. (scope: Mali; on by default on Mali GPUs with open drivers, except
  Mali-G1)
- `shader-cache`: Off by default on every GPU family. Turns on Steam's shader pre-caching,
  so Windows titles play in-game videos; downloads several GB and processes for long time
  on first start. See Shader pre-caching. (scope: Generic)
- `physx-skip`: On by default on every GPU family. Launcher marks PhysX install step of
  Windows titles done in their Proton prefix, else stops PhysX installer after 60 seconds.
  Turning it off stops only that launcher step and removes no files. See PhysX install
  step. (scope: Generic)
- `map-count`: Raises `vm.max_map_count` to value Proton expects. (scope: Generic)
- `xpad-dedup`: Drops duplicate joystick node that third-party Xbox 360 style pads expose.
  (scope: Generic)
- `pad-hidraw`: Installs Valve's controller rules (`steam-devices`), plus rules for 241
  pads from kernel `xpad` table that Valve's list lacks, matched on vendor and product, so
  client reads pads directly for rumble and battery level. Sony and Nintendo pads match
  by kernel pad driver (`hid-playstation`, `hid-sony`, `hid-nintendo`), so keyboards and
  mice of those makers stay out; on kernel without that driver module, all hidraw devices
  of that maker get access. (scope: Generic)
- `pad-xbox`: Off by default. Presents XInput pads from other makers as Xbox 360 pads.
  (scope: Generic)
- `desktop`: Adds application menu entry "Steam ARM", and KDE window rule that gives
  client's desktop interface windows title bar. Rule needs `kwriteconfig6` (Plasma 6) or
  `kwriteconfig5` (Plasma 5); without either on KDE Plasma, setup prints skip line. Rule file
  `kwinrulesrc` that setup created is deleted at removal once it holds no rules (record
  `/etc/steam-arm/kwinrules-made`, naming account). Setup for another account removes rule
  from previous account's rule file when setup created that file. (scope: Generic)
- `desktop-mode`: Adds menu entry "Steam ARM (Desktop mode)", which opens client in its
  desktop interface, for signing in and store pages. Found by searching "desktop" or "sign
  in". (scope: Generic)
- `icon-bigpicture`: Places "Steam ARM" icon on desktop. (scope: Generic)
- `icon-desktop`: Places "Steam ARM (Desktop mode)" icon on desktop. (scope: Generic)
- `tray`: Steam icon in panel tray with Open Steam, Open in Big Picture, Open in desktop
  mode, Steam pages (Store, Library, Friends, Downloads, Screenshots and Steam Settings; link to running client
  through `steam-arm --open`, greyed while client is not running and during first start),
  Stop Steam (`steam-arm --shutdown`; greyed while game runs), Steam ARM Settings
  (`steam-arm-config` in terminal emulator), View log (launcher log in `less`; greyed while empty) and Quit tray; client
  build shows none of its own.
  Starts at login through autostart entry for any desktop that reads autostart entries,
  and with each start of Steam ARM. Generic icon until client's first start, then client's
  own tray icon with dark outline, drawn into `$XDG_RUNTIME_DIR/steam-arm-tray/`, so it
  stays readable on light panels; without runtime folder, client's icon as is. (scope:
  Generic)
- `kde-input-prompt`: Off by default. On KDE Plasma (Wayland), pre-authorises input from
  X11 programs in KDE's permission store, so controller that drives desktop raises no
  "Remote control requested" prompt. Trade-off: every X11 program may then send input
  without asking. Setup saves value it replaces; turning part off, or uninstall, puts
  that value back. Applied inside desktop session, so with no session running it takes
  effect at next start of Steam ARM. Listed only where KDE Plasma's Wayland compositor is
  installed, or while its setting is in place. See Troubleshooting. (scope: KDE Plasma)
- `page-size`: On Raspberry Pi with 16K page kernel, adds `kernel=kernel8.img` to firmware
  `config.txt`, so firmware boots its 4K page kernel; reboot, then run installer again.
  Listed only on Raspberry Pi 5 class boards, on other Raspberry Pi with page size other
  than 4K, or while its `config.txt` block is in place; off and hidden elsewhere. (scope:
  Raspberry Pi)

## Graphics route per title

x86 Linux titles reach GPU on one of two routes, which launch handler picks per title at
start, with no launch options:

- **Forwarding (A):** OpenGL and Vulkan calls go to system's ARM64 Mesa (FEX thunks).
  Used for every title no rule below picks. FEX forwards Vulkan for 64-bit code only.
- **Mali drivers in emulation (B):** x86-64 and i386 builds of Mesa 26.1.8 with Panfrost
  and PanVK, in second copy of x86 root filesystem, same layout Valve uses on Steam
  Frame. Handler picks this route on Mali GPU families for:
  - Java titles: bundled Java runtime detected in game folder. LWJGL 2 titles also get
    `-DLWJGL_DISABLE_XRANDR=true`; Java 21 and newer get FEX Multiblock off, unless
    `FEX_APP_CONFIG` launch option sets Multiblock.
  - 32-bit titles started with `-vulkan` or `-force-vulkan`, on `mali-csf-v10`: option
    kept, title renders on GPU in place of CPU renderer. On other families handler
    removes option (profile key `vk32=keep` keeps it).

Game log line `steam-arm: graphics:` names route and reason. Override per title with
profile key `gfx=a` (forwarding) or `gfx=b` (Mali drivers in emulation), or with
`steam-arm-config gfx <appid> a|b`; `GFX_DEFAULT` sets route for titles without own
setting (see Advanced settings). On non-Mali GPU with published driver archive,
`steam-arm-config` refuses `b`, and `gfx=b` written by hand logs warning and title stays
on forwarding; with custom driver archive (see Custom
driver archive), `gfx=b` and `GFX_DEFAULT=b` apply on any GPU, while automatic rules stay
Mali-only. Windows titles run through ARM64 Proton on system Vulkan and use neither route.

`gpu-in-emulation` component provides second route; on by default on Mali GPUs (see GPU
detection). Installer downloads driver archive
`steam-arm-fex-mesa-26.1.8-x86_64-i386.tar.zst` (about 75 MB) from this project's
release (release address first, then same file name under `releases/latest/download`),
checks its SHA-256, and builds `/opt/fex-rootfs/Ubuntu_24_04-mali`: hard-link
copy of root filesystem with archive's Mesa, about 330 MB extra disk. Root filesystem
used for forwarding stays unchanged. Both trees belong to root and hold no set-user-ID
files: fetched image carries uid 1000, so every setup run sets owner (trees from earlier
versions included, logged once), and no desktop account can change x86 programs other
accounts run. PanVK in archive reports features DXVK and vkd3d ask
for, same set `vk-spoof` reports, for those two engines only. Deselecting component or
uninstalling deletes second tree. Without it, 32-bit titles lose `-vulkan` and Java
titles stay on forwarding. When both addresses answer HTTP 404, setup stops with message
that names missing release file and `STEAM_ARM_PROVIDER_TARBALL`, for pointing setup at
downloaded copy. Local copy in place of download: see Driver archive from local file.

Test results, 2026-10-01, test device (RK3588 board with Mali-G610 GPU), 90-second runs
per title:

- Every title type that ran on forwarding also ran on Mali drivers route.
- Java titles crash on forwarding and run on Mali drivers route; handler picked it for
  Java 25 (LWJGL 3) and Java 17 (LWJGL 2) titles with no profile, LWJGL 2 option added
  automatically.
- 32-bit title started with `-vulkan` switched to Mali drivers route and created its
  DXVK device on GPU; title still stops at loading screen, as with its OpenGL renderer.
- Titles with no rule stayed on forwarding in same client session; Windows titles
  unaffected.
- Frame rate on Mali drivers route, against forwarding: 64-bit Unity 5+ OpenGL title 409
  against 505 fps (vsync off); Unreal Engine 3 title 19.6 against 38.6 fps; Unreal Engine
  2 title 112.3 against 138.7 fps; Godot 3 title menu 5.6 against 15.8 fps; 32-bit Unity
  title 61.8 against 84.9 fps over 10 minutes, 82 against 69 fps over 90 seconds.
- GPU driver logs page-fault message at exit of one 32-bit Unity title on Mali drivers
  route; same message was logged on test device before that route existed; title
  unaffected.

Results per game type and frame rates on both routes: `GAMES.md`.

### Automatic Windows build

Launcher sets Windows build (Proton ARM64) for 32-bit Source engine titles before client
starts, since Linux build of this engine stops at loading screen under emulation. Applies
once per title, only with no build chosen in Steam or in settings menu, on GPU family
where Windows build was run (`mali-csf-v10`), with native ARM64 client (x86 client:
suggestion only), with Valve FEX tool versions where Linux build stopped (up to 2609) and
with `vk-spoof` chosen (DXVK finds no usable Mali device without it); elsewhere Route per
game marks Windows build as suggested. Tool name is `proton_11-arm64`, as Steam lists
Proton 11 (ARM64) in its Compatibility list. Steam downloads Windows build in background
once client is up. Shared content Steam keeps for another title (`LastOwner` 0 in its
manifest) counts as no title. Launcher log `steam-arm.log` names each title in
`auto-build:` line; desktop notice counts them. Title started before launcher set it
(installed during client session) skips that start once, with desktop notice; launch
option `STEAM_ARM_AUTO_BUILD=0 %command%` starts Linux build. Linux build stuck at loading
screen ignores Stop in Steam (stop request has no effect); desktop task manager (force
quit) or log out ends it. Undo: Graphics, Route per game, Force Linux build (kept for
good) or Automatic (rule may apply again). Turn off: Graphics, Automatic Windows build, or
`steam-arm-config auto-build off` (`AUTO_BUILD=off` in `/etc/steam-arm/steam-arm.conf`);
titles already set keep Windows build. Record of titles set:
`.config/steam-arm/auto-build.conf` in client folder.

## Page size

Setup checks page size before it installs anything. Emulation needs 4K pages; on 16K or
64K kernel it stops and names fix for that system, and on Raspberry Pi `page-size`
component applies that fix. Setup does not set up 4K page virtual machine such as `muvm`.
`STEAM_ARM_IGNORE_PAGESIZE=1` skips check on non-4K host kernel; use it only when x86 side
runs inside separate 4K page guest that check cannot see. On 16K host without such guest,
emulation fails.

Launcher checks page size at each start too: on 16K or 64K kernel (for example after
booting other kernel) it stops before client starts and names same fix.
`STEAM_ARM_IGNORE_PAGESIZE=1` in launcher environment or as line in
`/etc/steam-arm/steam-arm.conf` skips that check. Setup run with it on non-4K kernel writes
that line, so menu starts and later setup runs honour it; setup on 4K kernel removes it.

## x86 client (Armv8.0 CPUs)

Valve's native ARM64 client builds newer than 15 April 2026 stop at start with SIGILL on
CPUs without Armv8.1 atomics (LSE): Cortex-A53, A57, A72 and A73 cores
(<https://github.com/ValveSoftware/steam-for-linux/issues/13288>). On such CPU setup
installs Valve's x86 Linux client in place of native one and runs it through emulation,
with same launcher, launch handler, tray, settings menu and removal. Setup prints warning
block naming cores before any package change.

What runs:

- Client: Valve's x86 client (`steam.sh`, bootstrap package `steam_ubuntu12` and runtime
  package `runtime_scout_ubuntu12` from Valve's `steam_client_ubuntu12` manifest; client
  downloads rest at first start), started through system FEX (`FEX`
  package for this CPU) against x86-64 root filesystem setup fetches anyway. First start
  checks client files (native package leaves files of same names in client folder) and
  ends with one restart by launcher once client files are in; marker
  `.config/steam-arm/x86-verified` in client home records check, later starts skip it.
- First sign-in: with no account signed in, client opens desktop sign-in window (Deck
  interface without account runs SteamOS setup, whose update step needs SteamOS update
  tools). Deck interface from next start after sign-in.
- X errors: private copy of host libX11 in `.fex-emu/hostlib` of client home, with default
  X error handler returning instead of ending program (X error such as `GLXBadFBConfig`
  otherwise ends client). Launcher puts it first in library path of client; inside x86
  client's runtime containers `steam-arm-pv-bwrap` binds it over host libX11. Host libX11
  stays unchanged; rebuilt when host library changes.
- Runtime containers: host bubblewrap (native) through
  `/usr/local/lib/steam-arm-pv-bwrap`; x86 `bwrap` in root filesystem, if any, set aside
  (put back on switch to native client).
- Client window: drawn on CPU (`-cef-disable-gpu`; FEX app settings `steamwebhelper.json`
  and `exe.json` turn GL and Vulkan forwarding off for client browser only). Webhelper
  start script gets `--enable-features=NetworkServiceInProcess2`, so client's process
  check passes without transport dialog.
- Games: x86 Linux titles reach GPU through emulator's GL and Vulkan forwarding (route A
  only; Mali drivers inside emulation not wired for x86 client); Windows titles use x86
  Proton through emulation. 32-bit Windows titles draw on CPU (llvmpipe): emulator has no
  32-bit GL or Vulkan forwarding; 64-bit Windows titles reach GPU. Launch handler runs through Valve's launch wrapper (stand-in
  starts `/usr/local/lib/steam-arm-run.py`), so title rules, renderer check and logs work
  as with native client; log `/tmp/steam-arm-run-<pid>.log`, readable by game account
  only.
- Package tools (`apt`, `apt-get`, `dpkg`, `pkexec`, `sudo`, `steamdeps`) refused for
  programs client starts: emulated writes reach host system.

Costs: first start downloads client files and takes several minutes; later starts slower
than native client; client window drawn on CPU. Needs 2 GB of memory or more (setup stops
on 1 GB boards; warns below 4 GB). Untested on Armv8.0 hardware until report arrives.

Way back: every setup run (Update / Repair included) on x86 client chosen by CPU rule
reads Valve's native client manifest; for build not checked yet it downloads native
package and scans its programs for Armv8.1 atomic instructions outside outline-atomics
helpers, then starts its client once on this CPU. Clean result moves client back to
native ARM64 in same run; games, sign-in and settings stay. `CLIENT_PROBE` in settings
file records last result. Switch back to native client (by CPU rule or by hand) drops
package records of both clients in client folder: next native start checks and downloads
native client files (about 460 MB on test device) once, since x86 client replaced shared
files with its own builds. Record `.config/steam-arm/client-type` in client home names
client type of that folder, so setup for another account checks only folders x86 client
used.

By hand: `--client=auto|arm64|x86` (kept for later runs), Maintenance > Client type in
settings menu, `--client-check` (check only, status 0 runs, 1 still needs Armv8.1, 2 check
failed; Armv8.1 CPU: runs, manifest read only; result recorded as `CLIENT_PROBE`, shown
in Client type screen as last check). `STEAM_ARM_ALLOW_ARMV80=1` keeps native client on
Armv8.0 CPU (same as `--client=arm64`). x86 client on Armv8.1 CPU works too (opt-in,
slower). Switching type
reuses client folder: Windows titles may rebuild their Proton prefix.

## Playing games

### Linux x86 titles

Linux titles built for x86 run through FEX. Launch handler decides per title, with no
launch options:

- Steam overlay: x86 overlay for Linux x86 titles by default.
- MangoHud: `mangohud %command%`, `MANGOHUD=1 %command%` or profile `mangohud=on`,
  OpenGL and Vulkan, 64-bit titles. Handler loads root filesystem's MangoHud from copy in
  client folder (`.local/lib/steam-arm`). 32-bit titles: no MangoHud (root filesystem
  carries 64-bit build only). Host without MangoHud: setup adds shim
  `/usr/local/bin/mangohud` that sets `MANGOHUD=1`, so `mangohud %command%` reaches handler;
  `mangohud` of MangoHud package is never replaced, and removal deletes only shim.
- Display mode: title that changes display mode (fullscreen at other resolution or refresh
  rate) and quits, crashes or is stopped without changing it back: launcher puts back mode
  from before title started, once no title runs, and when Steam closes (X11 sessions;
  `steam-arm.log` line `display mode put back after game`). `STEAM_ARM_MODE_RESTORE=0` in
  `/etc/steam-arm/steam-arm.conf` turns it off.
- Unity and Godot titles get renderer settings Mali driver can run, found from game
  files: Godot 4 OpenGL renderer and GL 3.3 report, Godot 3 GL 3.3 report. Godot version
  comes from PCK embedded in executable, else `.pck` beside executable (same order as
  Godot), also behind start script; Windows builds under x86 Proton keep Godot defaults.
- Graphics route: forwarding, or Mali drivers in emulation for Java titles and 32-bit
  Vulkan titles; see Graphics route per title.

Without Mali drivers in emulation, 32-bit titles reach GPU through OpenGL only; Vulkan in
32-bit titles falls back to CPU renderer, so handler removes `-vulkan` and `-force-vulkan`
from them (profile key `vk32=keep` keeps it). Titles started through start script (Source
engine style) are detected by binary script starts. Source 2 titles get warning in log,
no change.

Value rule would set that launch option or environment already sets stays; log then
names both: `launch option kept: NAME=value (rule wanted ...)`. Route set in title
profile wins over rules: `title setting kept: gfx=...`. On Mali drivers route, FEX
`Multiblock` set through `FEX_APP_CONFIG` launch option stays (`launch option kept`);
Steam's own per-title FEX setting (`STEAM_COMPAT_FEX_CONFIG`) counts as default, not as
user choice. GL or Vulkan thunk, graphics provider and GLX vendor set in launch options
are replaced, since that route needs its own (`overridden for Mali route`). Profile
`gl32=off` sets GLX vendor `mesa` same way. Unity and Godot log lines name values in
effect, launch options included: renderer and reported GL version, for example
`unity: OpenGL core, GL 4.5 report`, `godot 4: OpenGL renderer, GL 3.3 report` or
`godot 3: GL 3.3 report`.
Handler log of each start: `/tmp/fex-compat-tool-<pid>.log`, readable by game account only
(handler sets mode 600 before Valve's tool writes title's environment there); menu shows
lines of last start under Games, "Rules used at last start".

Renderer check: once title loads OpenGL or Vulkan library, handler logs which GPU device
its processes use: `renderer: GPU (v3d renderD128), forwarding to host driver, process
<name>`, or `drivers inside emulation` on Mali drivers route. Device counts as used once
title holds GPU memory on it (CPU renderer opens device only to probe it). Title that uses
no GPU device within 30 s draws on CPU, and log says `renderer: warning: GPU forwarding not
active: rendering on CPU (llvmpipe)`, with reason: x86 Mesa inside emulation loaded
(forwarding bypassed), or no GPU device in use. Hardware report lists
renderer lines of five newest starts. Launch option `STEAM_ARM_RENDERER_CHECK=0 %command%`
turns check off for one title.

CPU drawing notice (off by default): with `CPU_NOTICE=on` (Graphics, CPU drawing notice,
or `steam-arm-config cpu-notice on`), CPU verdict also raises desktop notice in game
account's session, which stays until closed. GoldSrc titles get none: Software renderer is choice in
their video options. Launch handler runs for x86 titles only, so Windows titles on Proton
ARM64 and native ARM64 titles get no notice.

Other log lines: `goldsrc:` for GoldSrc titles (Half-Life engine), whose video options
pick OpenGL or Software renderer (Software draws on CPU); `compat: warning:` when Steam's
saved compatibility tool for title names Proton build but Linux build started. Handler
only reads Steam's `config.vdf`; it never writes it.

### Windows titles

Windows titles run through ARM64 Proton, which client downloads. Direct3D 8 titles run
through DXVK's `d3d8`; `PROTON_DXVK_D3D8=0 %command%` restores Proton's default. Launch
handler does not run for Proton titles, so fixes for them go into Steam launch options.

Direct3D 11 titles run at feature level 10_1 on Mali. Titles that need 11_0 (Unreal
Engine 4, Unity HDRP) and Direct3D 12 titles do not run; see `COMPATIBILITY.md`.

### GE-Proton (optional)

Maintenance, GE-Proton (ARM64) installs newest GE-Proton release with ARM64 build into
client's `compatibilitytools.d`, as game account. GE-Proton is third-party Proton build by
GloriousEggroll, not supported by Valve. Off until installed; nothing downloads otherwise,
and setup, Update / Repair and launcher never fetch or update it. Download is checked
against release's published sha512 (and GitHub's sha256 record) before unpacking; archive
members outside tool folder, links leaving it, hard links and special files stop install;
unpacked files get no setuid bit and no group or other write. Restart Steam ARM to list
new build. Pick it per game in Graphics > Route per game (`ge`),
`steam-arm-config compat <appid> ge`, or game Properties > Compatibility in Steam.

Builds need Steam Linux Runtime 4.0 (Arm64), which Steam downloads at first start of game
set to them; GE-Proton screen shows whether it is installed. Install from downloaded file
takes `GE-Proton<version>-aarch64.tar.gz` with its `.sha512sum` beside it (for networks
that block GitHub API). Install needs free space of five times download size. Installing
newer build offers to move games from older build installed here and remove it (default:
keep both). Remove version moves its games to other installed build or back to Steam's
choice: Linux build where game has one, else default Proton. Copies installed by hand are listed and left unchanged. Not offered with
x86 client or page size other than 4K. Install log: `~/.cache/steam-arm/geproton-*.log`.

### Shader pre-caching

Windows titles that play in-game videos through Proton show colour bars in place of videos
while Steam's shader pre-caching is off, since client then downloads no transcoded videos.
Component `shader-cache` turns it on: launcher starts client without `-noshaders`, and
sets `DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1`, because Steam's ARM64 pipeline caching
layer stops Proton titles at Vulkan device creation.

Costs, from test run on RK3588 board:

- download: several GB into `steamapps/shadercache` (1.5 GB within 3 minutes of first
  start)
- processing: after first start, installs and updates, `fossilize_replay` runs on all
  cores (8 processes, about 45 minutes for large title); Steam offers to skip it
- heat: SoC reached 87.7 °C during processing

Off by default on every GPU family. To turn it on, tick `shader-cache` in settings menu,
Components, or in installer checklist, then start Steam ARM again. Turning it off later
keeps downloaded cache, and turning it on again reuses it. Settings menu shows size of
`steamapps/shadercache` in each library folder when part is turned off (main library:
`.local/share/Steam/steamapps/shadercache` in client home). Deleting that folder by hand
stops Steam from downloading those caches again: client's records in `config.vdf` still
list them as present, and videos then show colour bars with part on.

### PhysX install step

Some older Windows titles run legacy PhysX installer on first start, which waits with no
window under emulation. Launcher marks that install step done in title's Proton prefix,
with value title's own install script asks for, so Steam skips it from next start. When
prefix does not exist yet, PhysX installer running longer than 60 seconds gets stopped and
Steam continues to title. Each step is logged in `steam-arm.log` in client home.

Component `physx-skip` controls this step, on by default on every GPU family. Turning it
off in settings menu, Components, or in installer checklist stops step from next client
start and removes no files. `STEAM_ARM_PHYSX_SKIP=0` turns it off for one client session,
`STEAM_ARM_PHYSX_SKIP=1` turns it on for one client session.

### Linux build installed as Windows build

Client can install Windows build of title that also has Linux build. To switch it to Linux
build: exit client, run `steam-arm-compatmap <appid> steamlinuxruntime` as game account
(or `steam-arm-config compat <appid> linux`), start client again. Steam then swaps
title's files for Linux build. `proton_11-arm64` in place of `steamlinuxruntime`
(`compat <appid> windows`) forces Windows build. `steam-arm-compatmap <appid> --remove`
(`compat <appid> clear`, or Graphics > Route per game > automatic) clears forced build;
Steam then picks build again. When automatic Windows build set that entry, clear also drops
its record, so rule may set it again at next start.

`steam-arm-compatmap` refuses while Steam ARM runs, since client rewrites its
configuration on exit. It also refuses app id that is not number, tool name with
characters other than letters, digits, `_`, `.` and `-`, and `config.vdf` without
expected blocks, and any edit that would leave braces unbalanced; file then stays
unchanged. `--remove` on title without entry also leaves file unchanged. First original
`config.vdf` stays beside it as `config.vdf.bak-steam-arm`; later runs never overwrite
that copy.

### Title profiles and launch options

Title profiles, one Steam app id per line, later files override earlier ones:
`/usr/local/share/steam-arm/titles.conf` (included), `/etc/steam-arm/titles.conf`
(system; `steam-arm-config` writes here) and `~/.config/steam-arm/titles.conf` in client
home. Line: `<appid> key=value ...`.

| Key          | Values                 | Effect                                           |
|--------------|------------------------|--------------------------------------------------|
| `overlay`    | `x86`, `vulkan`, `off` | Steam overlay kind for title                     |
| `mangohud`   | `on`, `off`            | MangoHud for title                               |
| `godot`      | `gl`, `vulkan`         | Godot renderer and GL report (`vulkan`: as is)   |
| `unity`      | `vulkan`, `gl`         | Unity renderer                                   |
| `env`        | `NAME=VALUE;...`       | Extra environment                                |
| `args`       | `ARG;ARG`              | Extra arguments                                  |
| `gl32`       | `off`                  | x86 Mesa in emulation, no GL forwarding (32-bit) |
| `vk32`       | `keep`                 | 32-bit title keeps `-vulkan`                     |
| `gfx`        | `a`, `b`               | Graphics route: forwarding or Mali drivers       |
| `multiblock` | `on`, `off`            | FEX Multiblock for title                         |
| `diskcache`  | `on`, `off`            | FEX code cache for title (FEX 2609.1 or newer)   |

Without `multiblock`, title keeps Valve's per-title FEX default. Launch option
`FEX_APP_CONFIG` with `Multiblock`, and Steam's own FEX setting (`STEAM_COMPAT_FEX_CONFIG`),
win over profile; log then says `launch option kept` or `Steam setting kept`. Multiblock
translates larger blocks of x86 code at once: more work at first run of each block, less
afterwards. Test device, one 32-bit Unity title, three runs each way: 5 to 9 % higher frame
rate, 9 to 12 % less CPU load, first frame 2 to 4 s later. Java 21 and newer titles fail
with it on.

Without `diskcache`, title runs without FEX code cache (FEX default). `diskcache=on` keeps
translated code in per-title cache folder Steam sets, for next start. Needs Valve FEX tool
FEX-2609.1 or newer; with older tool, log says `code cache not applied` and nothing
changes. Titles with own JIT compiler (Java, Mono, .NET, LuaJIT, CEF) keep file-backed
code only. Launch option `FEX_DISKCACHE`, or `FEX_APP_CONFIG` with `DiskCache`, wins over
profile (`launch option kept`); Steam's own FEX setting does not block it. After game
update or FEX tool update, launch handler deletes that title's cache once before start.
FEX sets no size limit; Maintenance, Caches shows sizes and clears them. Effect on frame
times not measured yet. Setting covers every emulated process of title start, runtime
helper scripts included: on test device 2 of 11 starts with empty cache (FEX-2609.1) hung
in runtime helper before game started (Steam shows game running; Stop in Steam ends it).
Off by default for that reason; turn off for title that hangs this way.

Values hold no spaces and no `#`. Launch options `STEAM_ARM_OVERLAY=x86|vulkan|off` and
`STEAM_ARM_PRELOAD_KEEP=a,b` override profiles; `STEAM_ARM_VK_SPOOF_DISABLE=1 %command%`
turns `vk-spoof` layer off for one title.

Compatibility by game type, and tested titles: `GAMES.md`. Researched, untested settings
per GPU family, engine and title, with what to change: `RESEARCH.md`.

## Fixing games

Same text as Help page `Fixing a game` in `steam-arm-config` (`steam-arm-config help
fixing`).

What works:

- Steam launch options (game Properties, General, Launch options), for example:
  - `PROTON_USE_WINED3D=1 %command%`: Windows game on OpenGL (WineD3D) in place of
    Vulkan (DXVK).
  - `-vulkan`: game's own Vulkan switch, where it has one.
  - `MESA_GL_VERSION_OVERRIDE=4.5 %command%`: reports newer OpenGL version to game.
  Launch option wins over automatic rules; game log then says "launch option kept".
- Games section of menu: overlay, MangoHud, extra environment and arguments, FEX code
  cache, per Linux game.
- Crash at start after game or FEX tool update, with FEX code cache on: Maintenance,
  Caches, clear that game.
- Graphics, Route per game: A (forwarding to host drivers) or B (Mali drivers inside
  emulation), for x86 Linux games.

Game is slow (CPU-bound):

- Games, then game, rules of last start, or Maintenance, Hardware report: line
  `renderer:`. `GPU (...)` means GPU drawing. `GPU forwarding not active: rendering on CPU
  (llvmpipe)` means CPU drawing; reason follows in same line.
- GPU line, game still slow: lower its resolution. Frame rate goes up: GPU limit.
  Unchanged: CPU limit (x86 code runs through emulation).
- MangoHud shows per-core load: one core near 100% while frame rate stays low means CPU
  limit.

Proton version keeps changing back:

- Choice in Steam (Properties, Compatibility) wins; this menu writes it only through
  Graphics, Linux or Windows build. Steam saves it in `config.vdf` when it exits; close
  Steam from its own menu once after change.
- Log line `compat: warning: ...`: saved choice and started build differ.
- Title switched to Windows build by itself: automatic Windows build (Graphics). Force
  Linux build keeps Linux build for good.

What to avoid:

- `MANGOHUD=1` or `mangohud %command%` on Windows games (Proton ARM64): game crashes.
- Options made for NVIDIA or AMD graphics cards.
- Installing packages inside emulation (`apt` or `dpkg` under FEX): FEX writes fall
  through to host system and can damage it. Setup replaces `apt`, `apt-get` and `dpkg` of
  x86 root filesystem with refusal that changes nothing and points to this page;
  read-only `dpkg` queries still answer. Original stays as `<tool>.steam-arm-real` for
  experts; uninstall puts originals back.

What cannot be fixed here:

- Direct3D 12 games.
- Unreal Engine 4 and 5 games.
- Games with kernel anti-cheat.

Reading "Rules used at last start" (Games, then game):

- "graphics: forwarding" or "graphics: Mali drivers in emulation": route of last start,
  reason in brackets.
- "launch option kept: NAME=value (rule wanted ...)": launch option won over rule.
- "title setting kept: gfx=...": route set for this game won over rules.
- "renderer: GPU (...)" or "renderer: warning: GPU forwarding not active ...": drawing on
  GPU or CPU.
- No lines: game has not started since setup. Windows games under x86 Proton show only
  compat and Godot note lines (Proton keeps its own logs).

## Remote Play

Native ARM64 streaming client hardware path (V4L2) fails with green screen on Qualcomm
Iris (steam-for-linux #13428) and has no V4L2 decoder to use on Rockchip, so launcher runs
x86-64 streaming client under FEX in its place. x86 client under FEX reaches no host video
decoder, and with hardware decoding advertised session can sit on launch screen. Installer has `steam-arm-remoteplay`, which pins hardware decoding and HEVC
off in client's stored configuration, so host keeps to H.264 and software decoder. Launcher
applies this setting before every client start once account has signed in, so first
stream already runs with it. `steam-arm-remoteplay --check` reports without changing
anything; menu section Remote Play shows same state.

Game window in background on host renders nothing new, so stream shows one frame and takes
no input. Keep game in foreground on host during Remote Play session.

## Updating

Run newer `steam-arm-install.sh`, or Maintenance, Update / Repair in `steam-arm-config`.
Client, library, sign-in, component choices and GPU family set by hand are kept. To
remove one component, re-run with that component deselected.

Maintenance, Check for new version (or `steam-arm-config update-check`) asks GitHub API
(`releases/latest`, which lists no drafts and no pre-releases) for newest release and
compares its version with installed one. Newer release: menu shows its page and
installer command; nothing downloads, and nothing checks on its own. No network, request
limit (HTTP 403) and unreadable answers each give their own message. Update / Repair
runs installed copy of installer, so newer version needs newer `steam-arm-install.sh`.

Install, Update / Repair and component changes refuse to run while Steam ARM runs for
game account (message `Steam is running for '<user>'`); close client first (menu offers
`Close Steam`; from terminal: `steam-arm --shutdown` as game account). Second setup
run started while another one, install or removal, is in progress stops with notice.

Custom driver archive chosen with `STEAM_ARM_PROVIDER_SHA256` stays in use on every later
run, Update / Repair included; `--provider-default` switches back to published archive.
Custom settings are cleared only once published tree is built; when that fails, custom
settings and tree stay and setup says so.

Downloads show curl's progress bar on terminal and on settings menu's built-in progress
screen; setup logs keep final bar line, other menu screens get error lines only.

Other variant of this installer present: setup stops and names it. `--replace-other`
retires it first and writes two archives: its system files go into
`/var/backups/steam-arm-replaced-<date>.tar`, files from its account's home into
`/var/backups/steam-arm-replaced-<date>-<user>.tar`, owned by that account. Then setup
continues. Client folder of other variant stays in use, with its games and sign-in,
when neither `ARMHOME_DIR` nor settings file names another folder; its account stays
in use when `GAMEUSER` names none. Setup prints commands, in order, that bring other
variant back: `sudo tar -xpf <system archive> -C /` and
`sudo -u <user> tar -xpf <account archive> -C /`. `--detect-other` prints whether other
variant is present (status 0 when present), needs no root. Install in `steam-arm-config`
asks before it replaces other variant.

## Settings backup and restore

Maintenance, Back up settings writes one file into folder of your choice (input starts at
your home folder; missing folder is created on request). Name:
`steam-arm-settings-<date>-<time>.tar.gz`, with no host or account name. File is readable
by you only (mode 600) and owned by you, also when menu runs through `sudo`. It holds no
sign-in data, Steam files, accounts or passwords.

Checklist picks parts; all are ticked:

| Part                   | Contents                                                    |
|------------------------|-------------------------------------------------------------|
| Setup choices          | `/etc/steam-arm/steam-arm.conf`                             |
| System game profiles   | `/etc/steam-arm/titles.conf`                                |
| Personal game profiles | `.config/steam-arm/titles.conf` in client folder of account |
| Proton/tool per game   | App id and tool name of each `CompatToolMapping` entry      |
| FEX per-game settings  | `.fex-emu/AppConfig/*.json` in client folder, valid JSON    |
| MangoHud settings      | `.config/MangoHud/*.conf` in client folder                  |

Last four parts belong to one account. When one of them is ticked, account list follows:
existing normal accounts only, cursor on current account, else game account. Archive
stores these parts without account name, so restore can put them into any account.

Maintenance, Restore settings lists backups in last-used folder and home folder, or takes
typed path. Before anything changes, restore checks file: manifest present with known
format version, expected file names only, no links, no paths outside archive, size
limits. Checklist then shows parts file holds, all ticked; personal parts ask for account
again. Summary of every change comes before Restore / Back. Restore needs administrator
rights and refuses while Steam ARM runs.

- Setup choices: `COMPONENTS_ON`, `COMPONENTS_OFF`, `COMPONENTS_USER_SET`, `GFX_DEFAULT`,
  `AUTO_BUILD`, `CPU_NOTICE`, and `GPU_FAMILY` when set by hand (`GPU_FAMILY_SET=user`).
  State of this machine
  (`GAMEUSER`, `ARMHOME_DIR`, `VERSION`, `FSTAB_ADDED`, `RFS_CREATED`, `ACCOUNT_CREATED`,
  `LINGER_SET`, `COMPONENTS_FAMILY`, `PROVIDER_CUSTOM_*`, `PROVIDER_LOCAL_FILE`, `CLIENT`,
  `CLIENT_SET`, `CLIENT_PROBE`) stays;
  summary lists skipped
  keys. When part lists change, menu offers `setup --keep` so installed parts match.
- Game profiles, asked for system and personal file separately: Merge (default) adds
  lines of games missing here; Replace takes backup file as is. Merge conflict (game set
  here and in backup with other lines): Backup wins for all, Keep current for all, or one
  by one with both lines shown. Current file stays as `titles.conf.bak-restore`.
- Proton/tool per game: written through `steam-arm-compatmap` helper, same checks. Valve
  tools (`proton_*`, `proton-*-arm64`, `steamlinuxruntime*`) count as installed,
  since client fetches them; other tools need entry in `compatibilitytools.d`. Tools not
  installed are left out and listed. Game that has other tool chosen here keeps it:
  choice made now wins over backup (plan counts these as kept). Needs client settings of
  that account (sign in once). GE-Proton builds not installed: install from Maintenance,
  GE-Proton (ARM64) first, then restore again.
- FEX and MangoHud files: changed files replace current ones, which stay as
  `<file>.bak-restore`.

Backup and restore never create, change or delete accounts, passwords or groups.

Command line:

```
steam-arm-config backup [DIR] [--account NAME] [--parts a,b,...]
steam-arm-config restore FILE [--account NAME] [--parts a,b,...] [--merge|--replace]
                 [--system-profiles merge|replace] [--personal-profiles merge|replace]
                 [--take-system IDS|all] [--take-personal IDS|all] [--yes]
```

Part names: `setup`, `system-profiles`, `personal-profiles`, `compat-tools`, `fex`,
`mangohud` (default: all). `--account` takes existing normal account only. Restore
merges by default and keeps current lines on conflict, listed in summary;
`--take-system` and `--take-personal` let backup win for named app ids or `all`. Without
terminal, restore needs `--yes`.

Archive format 1: members under `steam-arm-settings/`: `manifest` (`FORMAT=1`,
`VERSION`, `DATE`, `GPU_FAMILY`, `PARTS`), `system/steam-arm.conf`, `system/titles.conf`,
`personal/titles.conf`, `personal/compattools.txt` (`appid tool` per line),
`personal/fex-appconfig/*.json`, `personal/mangohud/*.conf`. Every later version reads
every earlier format.

## Uninstall

```
sudo bash steam-arm-install.sh --remove
```

Also from `steam-arm-config`, Uninstall. Package install: `sudo steam-arm-setup --remove`
before removing package; package removal alone leaves client installed and prints
removal command. Close client first; removal refuses to run while it is up, and while
another setup run is in progress.

Removed: launcher, helpers, settings menu `steam-arm-config`, installer copy in
`/usr/local/share/steam-arm`, menu and desktop entries, icons, controller rules,
services, sudo rule, window rule, apt hook, settings in `/etc/steam-arm`, setup logs,
runtime files of tray and launcher in `/run/user/<uid>`,
second graphics tree `/opt/fex-rootfs/Ubuntu_24_04-mali`, GE-Proton builds installed from
settings menu (games set to them go back to Steam's choice: Linux build where game has
one, else default Proton; Proton prefixes stay), x86
client helpers (`steam-arm-x86client.py`, `steam-arm-run.py`, `steam-arm-pv-bwrap`,
package-tool stubs).

Restored: `vm.max_map_count` value from before setup; Raspberry Pi `config.txt` (block
removed, then its `config.txt.steam-arm.bak` backup deleted); Valve's FEX tool files,
with `<file>.steam-arm-orig` and `<file>.steam-arm-sha` records removed (Steam also
restores them at tool's next update); Valve's streaming client in kept client
folder; with x86 client, Valve's launch wrapper and webhelper start script in kept
client folder (while unchanged since edit), own FEX app settings removed, native update
channel file back; package tools and `bwrap` of x86 root filesystem; user services stop
at logout again, only when setup turned lingering on; `/etc/fstab` without `/dev/shm` line, only when setup
added it. `graphics_provider.json` and `~/.fex-emu/Config.json` go only while unchanged
since setup; `~/.fex-emu` goes with `Config.json` when nothing else is in it.

Setup adds `/dev/shm` line to `/etc/fstab` only when nothing else mounts `/dev/shm` at
boot (no `/dev/shm` line of its own, no `dev-shm.mount` unit), and records that as
`FSTAB_ADDED=1`; removal takes out that line only.

Saved: game profiles from `/etc/steam-arm/titles.conf` go to
`/var/backups/steam-arm-titles-<date>.conf` before `/etc/steam-arm` is removed.

Kept by default:

- Client folder with installed games, sign-in and settings. Removal asks; deleting it
  needs typed `DELETE`. Re-install picks kept folder up again.
- x86 root filesystem at `/opt/fex-rootfs` (about 2 GB).
- Account setup created; removal prints `sudo userdel -r <name>` to delete it with its
  home folder.
- Distribution packages and FEX package source; removal prints `apt remove` line for
  packages nothing else needs.
- Account groups.
- `/dev/shm` line in `/etc/fstab` that setup did not add (earlier version, or added by
  hand); removal lists it under "Kept".

Client folder is deleted, from prompt or with `--purge`, only when it holds marker file
`.steam-arm-client`. Setup writes that marker from 2.0 on, on install and Update / Repair,
and only into folder that was new or empty, already holds marker, or is client folder of
earlier Steam ARM install (its `steamrtarm64` folder, or `steam.sh` with
`ubuntu12_32/steam` of x86 client, present; same account and folder name in settings
file). Folder holding `steamapps` or `ubuntu12_32` at its top level
belongs to another Steam install: setup refuses it and asks for other `ARMHOME_DIR`.
Folder that held other files gets no marker; setup says so and records it in settings
file (`ARMHOME_FOREIGN=1`), so later runs never mark it, even once client lives there.
Folder without marker, or recorded that way, stays on removal: removal says so and prints
`rm -rf` line for deleting it by hand after checking its contents. Client folder of 1.2
install gets marker from Update / Repair run once before removal only under default name
`.local/share/steam-arm`; under other name it is kept.

`sudo bash steam-arm-install.sh --remove --purge` also deletes client folder with every
installed game, and x86 root filesystem, after typed `DELETE`. Root filesystem goes only
when setup downloaded it (`RFS_CREATED=1`, or download note in its `.steam-arm-rootfs`
file) and other variant of this installer is not installed; otherwise removal keeps it and
prints `sudo rm -rf` line. Without terminal to type into, nothing is deleted.

## Advanced settings

Environment for installer:

- `GAMEUSER=name`: account to install into (default: account of last run, else uid
  1000). Root, and names with characters other than letters, digits, `.`, `_`, `@` and
  `-`, are refused.
- `ARMHOME_DIR=path`: client folder relative to home of that account, first install only
  (default `.local/share/steam-arm`). Plain relative path: no `..`, spaces or special
  characters, and not shared folder such as `.local` or `Documents`.
- `GPU_FAMILY=id|auto`: GPU family by hand, kept for later runs; `auto` detects again.
- `STEAM_ARM_IGNORE_PAGESIZE=1`: skips 4K page size check of setup and launcher on non-4K
  host kernel; only when x86 side runs inside separate 4K page guest that check cannot see
  (Page size). Kept in `/etc/steam-arm/steam-arm.conf` for launcher and later runs.
- `STEAM_ARM_ALLOW_ARMV80=1`: native ARM64 client on Armv8.0 CPU in place of x86 client
  (same as `--client=arm64`); client stops at start until #13288 is fixed; kept for later
  runs.
- `--client=auto|arm64|x86`, `--client-check` (options): client type; see x86 client.
- `STEAM_ARM_PROVIDER_TARBALL=file`: `gpu-in-emulation` takes driver archive from local
  file in place of its download; checksum still checked; path saved for later runs (see
  Driver archive from local file). Other steps still need network.
- `STEAM_ARM_PROVIDER_SHA256=sha256`: with `STEAM_ARM_PROVIDER_TARBALL`, custom driver
  archive in place of published one; see Custom driver archive.
- `--provider-default` (option): back to download of published archive; clears saved
  local and custom archive settings.

```
sudo env STEAM_ARM_PROVIDER_TARBALL=$PWD/steam-arm-fex-mesa-26.1.8-x86_64-i386.tar.zst \
  bash steam-arm-install.sh --defaults
```

Settings file `/etc/steam-arm/steam-arm.conf`, one `KEY=value` per line, no spaces or
quotes (launcher reads it as shell):

| Key                      | Written by  | Meaning                                          |
|--------------------------|-------------|--------------------------------------------------|
| `ARMHOME_DIR`            | setup       | Client folder relative to home                   |
| `GAMEUSER`               | setup       | Game account                                     |
| `COMPONENTS_ON`          | setup       | Components selected at last run                  |
| `COMPONENTS_OFF`         | setup       | Components left out at last run                  |
| `COMPONENTS_USER_SET`    | setup       | GPU components set by hand                       |
| `COMPONENTS_FAMILY`      | setup       | GPU family GPU components last followed          |
| `GPU_FAMILY`             | setup       | GPU family in use                                |
| `GPU_FAMILY_SET`         | setup       | `user` when family was set by hand               |
| `GFX_DEFAULT`            | setup, menu | Default graphics route (below)                   |
| `AUTO_BUILD`             | menu        | `off`: no automatic Windows build (absent: on)   |
| `CPU_NOTICE`             | menu        | `on`: notice on CPU drawing (absent: off)        |
| `VERSION`                | setup       | Installer version of last run                    |
| `ACCOUNT_CREATED`        | setup       | `1` when setup created game account              |
| `LINGER_SET`             | setup       | `1` when setup turned lingering on               |
| `FSTAB_ADDED`            | setup       | `1` when setup added `/dev/shm` fstab line       |
| `RFS_CREATED`            | setup       | `1` when setup downloaded x86 root filesystem    |
| `ARMHOME_FOREIGN`        | setup       | `1` when client folder held other files at setup |
| `PROVIDER_CUSTOM_SHA256` | setup       | SHA-256 of custom driver archive in use          |
| `PROVIDER_CUSTOM_FILE`   | setup       | Path of that archive                             |
| `PROVIDER_LOCAL_FILE`    | setup       | Path of local copy of published driver archive   |
| `CLIENT`                 | setup       | `arm64` (native client) or `x86` (absent: arm64) |
| `CLIENT_SET`             | setup       | `user` when client type was set by hand          |
| `CLIENT_PROBE`           | setup       | Native client check: `<build>:ok\|lse\|err`      |
| `STEAM_ARM_UI`           | you         | `desktop`: `steam-arm` opens desktop interface   |
| `STEAM_ARM_HOME`         | you         | Client folder (absolute path) for launcher, tray |

`GFX_DEFAULT`, for x86 titles without `gfx=` of their own:

- `auto` (default; empty means same): forwarding, with automatic switch for Java and
  32-bit Vulkan titles.
- `a` (`forward` reads same): every title on forwarding, no automatic switch.
- `b`: every title on Mali drivers in emulation, on Mali GPU, or on any GPU with custom
  driver archive. Frame rates per route on test device: `GAMES.md`. `steam-arm-config`
  refuses `b` on other GPUs.
- Any other value: automatic rules, and game log names unknown value.

`steam-arm-config gfx-default auto|a|b` and menu Graphics, Default route write same
values.

Environment for launcher (`steam-arm`) and its helpers:

- `STEAM_ARM_HOME=path`: client folder in place of saved one (absolute path).
- `STEAM_ARM_PHYSX_SKIP=0` or `=1`: turns `physx-skip` off or on for that client
  session, over saved component setting: `STEAM_ARM_PHYSX_SKIP=0 steam-arm`.
- `STEAM_ARM_VK_SPOOF_DEBUG=1`: troubleshooting; `vk-spoof` layer prints its decisions
  to game's output.
- `steam-arm --desktop` and `steam-arm --bigpicture` start client in that interface, or
  restart running client in it. `steam-arm --open steam://...` passes link to running
  client and never starts one. `steam-arm --help` lists launcher options, also as root.

Per-title launch options (`STEAM_ARM_OVERLAY`, `STEAM_ARM_PRELOAD_KEEP`,
`STEAM_ARM_VK_SPOOF_DISABLE`, `PROTON_DXVK_D3D8`, `STEAM_ARM_AUTO_BUILD`): see Playing
games and Automatic Windows build.

## Driver archive from local file

`gpu-in-emulation` downloads its driver archive from project release on GitHub. Where
GitHub is blocked or network is slow, local copy of same file works in its place.

1. Get `steam-arm-fex-mesa-26.1.8-x86_64-i386.tar.zst` from release page on any computer.
2. Copy it to ARM64 system. Its path may hold only letters, digits and `. _ - + /`, since
   setup saves it.
3. Settings menu: Components, Driver archive, Local copy. Menu checks SHA-256 against
   published archive, then runs setup. With `gpu-in-emulation` off, menu asks to turn it
   on. Command line: `steam-arm-config driver-archive local <file>`.

File named as published archive and placed beside `steam-arm-install.sh` is used without
menu step when its SHA-256 matches; one that does not match is ignored with note and left
in place. Setup saves path (`PROVIDER_LOCAL_FILE`) for later runs. When saved file is gone
or changed, setup downloads published copy and says so. Components, Driver archive,
Download (or `steam-arm-config driver-archive download`) clears saved path; second tree in
place stays. Settings restore leaves this path out (state of this machine). Uninstall
leaves archive file in place. Other setup steps (client, root filesystem) still need
network.

## Custom driver archive

For advanced users. Results depend on Mesa version in archive and on kernel GPU driver
and kernel version of system; published archive is only one tested on test device.

`gpu-in-emulation` uses published driver archive by default. Custom archive, for example
own Mesa build, replaces it only when both file and its SHA-256 are given.

1. Build archive (see Driver archive build), or take one from other source, and note its
   SHA-256 (`sha256sum <file>`).
2. Copy `.tar.zst` file to ARM64 system. Its path may hold only letters, digits and
   `. _ - + /`, since setup saves it.
3. Run setup with file and checksum:

   ```
   sudo env STEAM_ARM_PROVIDER_TARBALL=/path/to/archive.tar.zst \
     STEAM_ARM_PROVIDER_SHA256=<sha256> bash steam-arm-install.sh --keep
   ```

   On GPU where `gpu-in-emulation` is off by default, select it in same run: `--select`
   with full component list, `gpu-in-emulation` included, in place of `--keep`.

   Settings menu: Components, Driver archive, Custom archive does same: path, SHA-256
   (read from `.sha256` file beside archive when present, else typed), warning, then
   setup; with `gpu-in-emulation` off, menu asks to turn it on.
4. Setup checks SHA-256, then layout: only `usr/`, `etc/` and `graphics_provider.json` at
   top level, and Mesa driver library (`libgallium-*.so`, `libvulkan_*.so` or
   `dri/*_dri.so`) in `usr/lib/x86_64-linux-gnu` or `usr/lib/i386-linux-gnu`. It prints
   warning that custom archive, not published one, is in use. Archive that fails either
   check changes nothing.
5. Start title; game log line reads `graphics: custom drivers inside the emulation`.

Behaviour with custom archive:

- Setup saves path and SHA-256 (`PROVIDER_CUSTOM_FILE`, `PROVIDER_CUSTOM_SHA256`), so
  repair, update and component changes keep custom archive. When file is gone or no
  longer matches, setup stops and prints both ways on: point setup at file again, or
  switch back with `--provider-default`.
- `--provider-default` clears these settings after published tree is built. When download
  or check of published archive fails, custom settings and tree stay, and setup says so.
- `gfx=b` and `GFX_DEFAULT=b` apply on any GPU family. Automatic rules (Java, 32-bit
  Vulkan) stay Mali-only.
- `STEAM_ARM_PROVIDER_SHA256` without `STEAM_ARM_PROVIDER_TARBALL` is refused; downloads
  are always published archive.

Back to published archive (settings menu: Components, Driver archive, Download):

```
sudo bash steam-arm-install.sh --keep --provider-default
```

## Driver archive build

Recipe `tools/build-driver-archive.sh` is part of GitHub source (not of release zip). It
builds x86-64 and i386 Mesa driver archive inside two Ubuntu 24.04 build roots. Defaults
reproduce published archive: Mesa 26.1.8, Panfrost and PanVK, CPU fallbacks, two Steam
ARM Mesa patches.

### On x86-64 PC

Needs:

- x86-64 Linux PC; recipe refuses other processors.
- About 25 GB free disk for build folder.
- Network: Ubuntu base image, Ubuntu package snapshot, Mesa source.
- Host tools `bash`, `curl`, `tar`, `xz`, `zstd`, `patch`, `sha256sum`, `unshare`
  (util-linux), and `git` for `--mesa-ref` only.
- No root: unprivileged run uses user namespaces, and needs them enabled and subordinate
  id range for account in `/etc/subuid`. Run as root works too.

| Option              | Effect                                                      |
|---------------------|-------------------------------------------------------------|
| `--mesa VERSION`    | Mesa release from archive.mesa3d.org (default 26.1.8)       |
| `--mesa-sha256 SHA` | SHA-256 of that release tarball (known for default release) |
| `--mesa-ref REF`    | Mesa git tag, branch or commit in place of release          |
| `--gallium LIST`    | Gallium drivers (default `panfrost,llvmpipe,softpipe,zink`) |
| `--vulkan LIST`     | Vulkan drivers (default `panfrost,swrast`)                  |
| `--no-patches`      | Build without two Steam ARM Mesa patches                    |
| `--snapshot STAMP`  | Ubuntu package snapshot (default `20260929T000000Z`)        |
| `--work DIR`        | Build folder (default `./driver-build`)                     |
| `--out DIR`         | Output folder (default `./driver-out`)                      |
| `--jobs N`          | Parallel compile jobs (default: all processors)             |
| `--clean`           | Delete build and output folders first                       |
| `--dry-run`         | Check options and host tools, print plan, build nothing     |

```
bash tools/build-driver-archive.sh --dry-run
bash tools/build-driver-archive.sh --mesa 26.1.8
```

Output in `--out` folder: `steam-arm-fex-mesa-<version>-x86_64-i386.tar.zst`, its
`.tar.zst.sha256`, and check logs `verify-x86_64.log` and `verify-i386.log`. Build stops
when checks fail (libraries resolve, LLVM linked in, and `llvmpipe` GL context when
`llvmpipe` is built). Mesa release other than 26.1.8 without `--mesa-sha256` is not
pinned; recipe prints its SHA-256. Patch that does not apply to chosen Mesa stops build;
`--no-patches` builds without them.

### On GitHub (Actions)

Workflow "Build driver archive" (`.github/workflows/build-driver-archive.yml`) runs same
recipe on GitHub's `ubuntu-24.04` runner, as root, with 6-hour limit and read-only access
to repository.

1. Fork repository on GitHub.
2. In fork, open Actions; enable workflows when GitHub asks.
3. Pick "Build driver archive", then "Run workflow".
4. Enter Mesa version (default 26.1.8); optional: SHA-256 of Mesa release tarball, and
   extra recipe options such as `--no-patches`. Start run.
5. When run ends, open its summary page: it shows archive's SHA-256. Download artifact
   `steam-arm-fex-mesa-<version>-x86_64-i386` and unzip it; it holds `.tar.zst`,
   `.tar.zst.sha256` and check logs.
6. Copy `.tar.zst` to ARM64 system and run setup with it, as in Custom driver archive:

   ```
   sudo env STEAM_ARM_PROVIDER_TARBALL=/path/to/archive.tar.zst \
     STEAM_ARM_PROVIDER_SHA256=<sha256> bash steam-arm-install.sh --keep
   ```

## Troubleshooting

- Client stays on "Starting launch", or shows black "Abort game" screen, after title exits
  on its own or after first-launch On-Screen Keyboard notice: exit client from power menu
  or tray, then start it again. Installed games and settings stay.
- `steam-arm` stops with "Steam ARM is set up for account NAME": client lives in home of
  account chosen at setup. Log in as that account, or run `sudo steam-arm-config`, Install / Setup,
  and pick current account.
- `steam-arm` stops with "Steam client did not finish its first start": client files
  incomplete (download stopped or client closed during first start). Start Steam ARM again;
  download continues.
- Desktop notification "Steam ARM: warning": launcher found problem it cannot fix itself
  (Mali drivers inside emulation missing, private GLX copy missing or broken, display mode
  not put back, Bluetooth adapter left off, no usable GPU render node); text names fix. Shown
  when Steam ARM starts from menu, once per text per login session; every warning is in
  `steam-arm.log` in client home (over 1 MiB at start: moved to `steam-arm.log.1`, one old
  copy kept).
- No GPU render node readable and writable by account (warning at start): games draw on CPU.
  Add account to group of `/dev/dri/renderD*` (warning names it, usually `render`), then log
  out and back in. No render node and `/dev/mali0` present: Arm's closed `kbase` driver;
  warning names fix (kernel with Mesa's `panfrost` or `panthor` driver).
- Steam window stays empty, desktop notification "Steam ARM: library missing": client
  window process (`steamwebhelper`) cannot load host library (`error while loading shared
  libraries` in `logs/steamwebhelper.log` of client folder). Notification names library and
  package, for example `sudo apt install libibus-1.0-5`; then start Steam ARM again.
  Hardware report lists such lines.
- `steam-arm` stops with "Steam client not installed": setup did not finish. Run it again with
  `sudo steam-arm-config`, Maintenance > Update / Repair. On Raspberry Pi 5, reboot first when
  setup switched to 4K page kernel.
- Client ignores `steam -shutdown` or `steam://` links (command line forwarded, nothing
  happens): client stops acting on forwarded command lines after second client started
  under other home folder on same account (for example client binary run by hand without
  launcher). Stop it with `steam-arm --shutdown` (SIGTERM after 20 s, x86 client 45 s) or
  tray, Stop, then start it again.
- Display stays at other resolution or refresh rate after game: launcher puts back mode
  from before game once game ends; log line `display mode put back after game` in
  `steam-arm.log`. Mode stays changed only with `STEAM_ARM_MODE_RESTORE=0`, in Wayland
  sessions, or when `xrandr` is missing (`sudo apt install x11-xserver-utils`).
- Bluetooth adapter off after Steam starts: client sets adapter power from its own saved
  setting (`System/Bluetooth/Enabled` in `config.vdf`; unset means off). Launcher writes
  host state there before each start, and at exit powers adapter on again when it was on
  before start and Steam's own Bluetooth switch is not off; log line `Bluetooth adapter
  left off by client; powered on again` in `steam-arm.log`.
- Title keeps running after SIGTERM or Alt+F4 (seen with 64-bit GameMaker title under
  emulation; KWin then offers Terminate): quit from title's own menu, or run
  `steam-arm --shutdown`, which stops client and title (6.5 s in test).
- Game does not start or draws wrong: see Fixing games.
- Game is slow or CPU-bound: check `renderer:` line in game log (Games, then game, or
  hardware report). `renderer: warning: GPU forwarding not active: rendering on CPU
  (llvmpipe)` names reason; `renderer: GPU (...)` with low frame rate: steps in Fixing
  games, "Game is slow". Raspberry Pi 5: `COMPATIBILITY.md`, Raspberry Pi 5 performance
  tips.
- Game starts slowly: first start of Windows title creates its Proton prefix and runs
  install steps of its redistributables (Visual C++, DirectX) under emulation; PhysX step
  is marked done or stopped after 60 s (`physx-skip`). Every start translates x86 code
  again (FEX). Later starts skip prefix and install steps. x86 Proton builds (`proton_11`,
  log line `compat: x86 Proton`) run Wine itself through emulation; ARM64 Proton builds do
  not.
- Proton choice falls back to default: Steam keeps choice in `config.vdf` and writes that
  file when client exits; client that crashes or is stopped another way can lose last
  change (likely cause, not reproduced). Pick tool again in Properties, Compatibility,
  then exit Steam from its menu once. Steam
  ARM writes that file only on request (Graphics, Linux or Windows build; settings
  restore, which keeps tool chosen now for each game).
- KDE Plasma (Wayland) asks "Remote control requested: input devices" when controller
  connects or drives desktop: X11 programs, Steam among them, send controller input as
  emulated keyboard and mouse, and KDE asks before allowing that. Optional component
  `kde-input-prompt` pre-authorises it (turn on under Components in `steam-arm-config`).
  Same as
  `flatpak permission-set kde-authorized remote-desktop "" yes`: empty app id covers every
  X11 program, so any of them may then send input without asking. Turning part off puts
  back value from before. Setup prints one-line hint when KDE Plasma Wayland session runs.
  Source: <https://discuss.kde.org/t/kde-linux-steam-controller-request-remote-access-dialog/30731>
- MangoHud draws no HUD in Unity titles on Vulkan renderer (`mangohud=on` profile, three
  titles); title itself runs. OpenGL titles draw it.
- Custom OpenGL engine title with included `overlay=off` profile (app 248570) stops about
  20 s in when MangoHud is loaded. Leave MangoHud off for it: no `mangohud=on` profile, no
  `mangohud %command%` or `MANGOHUD=1` launch option.
- `steam://rungameid/<appid>` link for title not in library opens install dialog that can
  stay over games started later. Restart Steam (Exit from power menu or tray, then start it
  again) to clear it.
- Launch option `powerprofilesctl launch -p performance -- %command%`: profile hold works
  only when Steam was started from desktop session (application menu or autostart). Steam
  started from other context (SSH, `runuser`, service) gets hold refused, and title does not
  start. Start Steam from desktop, or remove that launch option.
- Hardware report for compatibility report: `steam-arm-config report`.

## What this does not do

- Titles protected by kernel-level anti-cheat do not run.
- Direct3D 12 titles, Unreal Engine 5 titles and Direct3D 11 titles that need feature
  level 11_0 do not run on Mali; see `COMPATIBILITY.md`.
- No VR runtime is included; Steam Frame's runtime is not part of this installer.
- Test device: RK3588 board with Mali-G610 GPU. Status of other GPU families:
  `COMPATIBILITY.md`.

## Other documents

- `HOW-IT-WORKS.md` (GitHub repository): Flow from setup command to game, graphics routes
- `FEATURES.md`: Full feature list
- `COMPATIBILITY.md`: Requirements, pre-install checks, GPU families, unsupported titles
- `GAMES.md`: Compatibility by game type, tested titles
- `RESEARCH.md`: Researched, untested settings and what to change (AI-assisted research)
- `COMPARISON.md`: Other routes to Steam on ARM64
- `CHANGELOG.md`: Changes per version
- `CREDITS.md`: Projects this installer builds on

## Credits

This installer arranges other people's work: Valve's ARM64 Steam client and Proton,
FEX-Emu, Mesa with Panfrost and PanVK, Panthor kernel driver, DXVK and others. Each part
is installed from its own source. Only exception is `gpu-in-emulation` archive:
Mesa built for x86 by this project, published with its release. See `CREDITS.md`.

## Disclaimers

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.

This is unofficial, community-built tool. It is not affiliated with, endorsed by or
supported by Armbian project or any board manufacturer.
