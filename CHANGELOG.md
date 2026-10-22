# Changelog

All notable changes to this project are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [3.1] - 2026-10-21

### Added

- Upgrade to newest release: Maintenance, Upgrade to newest release (shown once Check for new version finds newer release; main screen names it), or `sudo steam-arm-config upgrade [--yes]`. Downloads `Steam.ARM.<version>.zip` and its `.sha256` file from GitHub over HTTPS only (at most 32 MB), checks size GitHub lists, sidecar form, SHA-256 against sidecar and GitHub's asset digest, unpacks with path, link, count and size rules, checks `SA_VERSION` and syntax of its setup, then runs that setup with `--keep`. Free space checked before download. `--file ZIP` takes zip downloaded by hand with `ZIP.sha256` beside it; `--check` compares only (same as `update-check`). Refused while Steam runs, during another setup run or unfinished change. Upgrade from zip never writes package files. Log per run in `~/.cache/steam-arm/upgrade-*.log`, also under View logs.
- Package upgrade in one step: each release lists `steam-arm-setup_<version>_arm64.deb` and its `.sha256` file, built byte-identical by `build-deb.sh`. Upgrade on package install (`steam-arm-setup`) downloads both over HTTPS into root-only staging folder, checks length, `.sha256` line and GitHub's digest (required) before anything runs, shows plan, then takes setup lock, keeps copy of installed version, runs `apt-get install` on checked file (noninteractive, local config files kept) and `steam-arm-setup --keep`. Failure of apt or setup offers restore of saved version. Older release only with `--allow-older` (`apt-get --allow-downgrades`). `--file` takes package with `.sha256` beside it. Release without package asset: versions compared, then package build steps; nothing downloads.
- Rollback protection: setup saves installed version before each version change to `/var/lib/steam-arm/snapshots/<version>-<date>/`: installed copies of setup and settings menu, `/etc/steam-arm`, every owned program, rule, menu entry and icon (mode and SHA-256 per path, missing ones recorded) and settings backup made by that version's menu, with SHA-256 manifest. Client folder, games, sign-in, x86-64 RootFS, Mali and extra Mesa trees and distribution packages are never included. Snapshot that cannot be written stops setup before any change; `--no-snapshot` skips it for full disks. Upgrades by hand from 2.3.1 and 3.0 get it from 3.1 setup.
- Go back to previous version: Maintenance item, or `sudo steam-arm-config upgrade --rollback [VERSION]`. Snapshots listed newest first with date, reason, size and check result; damaged snapshot cannot be chosen and can be deleted there. Unfinished change started with `--no-snapshot`: version named by hand. Current version saved first, chosen snapshot restored, its setup run with `--keep`. `upgrade --list` prints snapshots and version changes (`/var/lib/steam-arm/history.log`); `upgrade --snapshot` and setup option `--snapshot` save installed version by hand.
- Frame pacing readout, off by default: `steam-arm --perf-stats` or `STEAM_ARM_PERF_STATS=1`. Every 5 s one line per frame source: frame count, frame interval p50, p95, p99 and maximum, intervals over 25 ms and over 50 ms. Frame times from Mesa overlay layer (`VK_LAYER_MESA_overlay`, hidden, Vulkan) and Gallium HUD dump (hidden, OpenGL), set through game environment file only while readout is on. Lines on terminal and in client home `.local/state/steam-arm/perf.log` (newest 200); hardware report adds section `Frame pacing` with last 12. Steam already running: readout covers games started from then on until Ctrl+C, including starts through `steam://` links. Vulkan titles through Valve's FEX tool report nothing (no x86-64 overlay layer in Steam runtime container). Frames read after game end carry last app id with `(ended)`.
- Still-working notice: game with no frame 20 s after start gets one desktop notice (terminal line without notice service) naming likely state: compiling shaders (shader cache growth or `fossilize_replay`), loading, or idle (no CPU use, or disk wait without reads, for 10 s: own launcher or settings window waiting for input, or game not responding). Closed on first frame; frame signal from GPU engine time or cycles in kernel `fdinfo` or readout files (no readout growth in first 120 s: readout counts as off); kernel without per-process GPU lines in `fdinfo` and readout off: no notice, one log line. `STILL_NOTICE` absent (auto): on where display mode restore looks for games each second already, so no added work while idle; `on`, `off`: Graphics, Still-working notice, or `steam-arm-config still-notice on|off|auto`; part of setup choices in backups. `STEAM_ARM_STILL_WORKING=0|1` and `STEAM_ARM_STILL_AFTER=<seconds>` for one session.
- Unfinished change: `/var/lib/steam-arm/upgrade.state` written before first change of version change, removed after success. Present while no setup runs: next menu start and `upgrade --rollback` offer restore of saved version or new setup run, next setup run names it; nothing restores on its own. Setup stopped after its change began prints recovery installed settings menu offers: `upgrade --rollback` from 3.1 on, else same setup again with `--keep` (menus before 3.1 have no restore). Restore of unfinished change recorded as restore in `history.log`.
- Automatic deletion of snapshots after successful upgrade or rollback and when setting changes: installed version plus newest snapshot of last 2 earlier versions kept (Maintenance, Previous versions kept, `steam-arm-config snapshot-keep 1..5`, `SNAPSHOT_KEEP` in settings file and backups); older, damaged and half-written ones deleted, each named with date, size and freed space; upgrade staging folders of finished or restored changes deleted with them. Snapshot of unfinished change and newest snapshot of version before current one never deleted.
- Downgrade protection: setup over newer install stops before any change unless `--allow-older`; upgrade never installs older release by itself (`--allow-older` permits it with warning; setup before 3.1 runs without that option, after upgrade saves installed version). Going back through snapshot needs no option.
- Check for new release when menu opens, off by default (Maintenance item, `steam-arm-config update-check-on-open on|off`, `UPDATE_CHECK_ON_OPEN`): at most once daily, 8 s limit, result stored for main screen line only.
- Show what is new: release notes of newest release from last check.
- Host facts in `/etc/steam-arm/steam-arm.conf` on every setup run: `CPU_LSE`, `CPU_CORES`, `PLATFORM` (`pi4`, `pi5`, `pi-other` on Raspberry Pi, else empty), `MESA_HOST`; `--detect` prints them. Launcher derives slow emulation class (x86 client on CPU without Armv8.1 atomics), exports `STEAM_ARM_SLOW` and `STEAM_ARM_PLATFORM` to client helper and launch handler, logs session type once per start.
- `steam-arm --cpu-report [--quick] [--no-wait] [--out FILE]`, Maintenance, CPU profile of client window, and `steam-arm-config cpu-report`: CPU and GPU profile of client window and games (system, firmware throttle bits, session, host graphics stack, emulator, Steam processes with render nodes and graphics libraries per process, two 60 s profiles with CPU share per process group, v3d statistics, per-process GPU time, threads, temperature, clocks, throttle bits); home folders replaced by `~`, host name, account name and serial never read; hardware report appends its static sections.
- x86 client FEX app settings: own keys merged into `steamwebhelper.json` and `exe.json` (thunks off, FEX code cache off for client window processes; files of 3.0 rewritten, other keys kept); `steam.json` with reduced x87 precision for client program while Maintenance, Faster client start (`x87-client on`, `X87_CLIENT`) or `STEAM_ARM_X87=reduced` is set, off by default; on CPUs without LSE atomics third restart of oldest `steamwebhelper` after 5 minutes turns FEX Multiblock off for client window files once, with notice.
- Lighter client window on CPUs without Armv8.1 atomics: desktop interface by default and no friends view; `steam-arm --bigpicture`, `STEAM_ARM_UI=bigpicture`, `STEAM_ARM_FRIENDS=1` for one start, Maintenance, Client window: lighter (`client-light off`, `CLIENT_LIGHT`) restores Deck interface and friends view; setup summary names it.
- GPU forwarding state: on `PLATFORM` `pi4`, `pi5`, `pi-other`, thunks off in FEX config raise notice that stays at every start; Information, Steam ARM status row GPU forwarding; launch handler sets reason `thunks-missing` in run record and names x86 Mesa driver kind inside emulation.
- Per-title emulation keys `tso=off` (FEX relaxed memory model) and `x87=reduced` (reduced x87 precision): Games, game, Emulation; `steam-arm-config profile`; same precedence as `multiblock`; run record carries both; never automatic tuning knobs.
- Automatic tuning on Raspberry Pi GPU families: OpenGL version 3.3, then Zink, then Multiblock; no `gl32` there.
- Experiment, x86 client: client window through GPU for one start (`STEAM_ARM_LAB_CEF_GPU=vulkan|gl`, `steam-arm-config lab-cef-gpu`, Maintenance item); result `cef-gpu=ok|failed:<reason>` in client home `.config/steam-arm/state`; Help page Experiments.
- Component `pi-governor`, off by default, on Raspberry Pi boards: CPU governor `performance` while Steam ARM runs through root helper and sudo rule, saved governor back at exit; Maintenance, CPU governor while Steam runs.
- Container test matrix row `raspios-pi4` (Cortex-A72 without LSE, bcm2711 device tree, v3d render node, x86 client stand-ins): settings `CLIENT=x86`, `PLATFORM=pi4`, FEX package `fex-emu-armv8.0`, PPA package lists thunk files setup searches for.
- CPU report verdict (report format 2, also `--sections verdict`): client window state from client's own GPU log (GPU with renderer, software with Chromium's reason, unknown), client window starts in last 10 minutes with restart-loop flag (three within 120 s), GPU process exits, top process group of last profile phase, FEX settings of client window programs as FEX layers them, clock floor with throttle bits, Vulkan class cross-check, one next-step line. Information, Steam ARM status row Client window.
- Setting `CLIENT_GPU=on|off` (default off; `steam-arm-config client-gpu`, keep item on Experiment screen): ANGLE on Vulkan for client window at every start; failed start turns it off until `client-gpu on` again. Vulkan variant of experiment keeps GL thunk off (FEX default for Chromium's GLX pattern); experiment flags gain `-cef-disable-gpu-sandbox`; watcher reads Chromium's own `[ gpu_compositing ]: enabled` line form; trial skipped below 1536 MB available memory.
- Setting `CEF_HANG_KILLS=on|off` (default on, Chromium behaviour; `steam-arm-config cef-hang-kills`, Maintenance item 23): off appends `-cef-disable-hang-timeouts -cef-disable-renderer-restart`; opt-in because it hides restart loop report's verdict looks for.
- Setting `CLIENT_TSO=strict|relaxed` (default strict; `steam-arm-config client-tso [strict|relaxed|retry]`, Maintenance item 24 on CPUs without LSE atomics): relaxed writes FEX `TSOEnabled` 0 for client programs `steamwebhelper`, `steam` and `exe` (FEX keys by program name; `exe` also matches emulated programs that start themselves again through `/proc/self/exe`, Chromium and Electron based titles among them); guard records `client-tso=failed:<reason>` (three client window restarts within 120 s, or no start line within 300 s) and later starts run strict until `client-tso retry`. `STEAM_ARM_CLIENT_TSO=strict|relaxed` for one start.
- Host fact `VK_HOST=1.2|1.3` on Broadcom families (V3DV: 1.2 below Mesa 24.3, 1.3 from it): settings file, `--detect` line `vulkan host`, run record start line `vkhost`, report verdict cross-check against `vulkaninfo`.
- Setup block for x86 client on CPU without LSE names CPU-class expectation (client window on CPU, high CPU use while window is open), lighter window defaults, three levels (always on CPU, per title, experiments) with commands, `steam-arm --cpu-report`; Raspberry Pi line with host Mesa, Vulkan class and session type. One notice at first start in client home on that class (`STEAM_ARM_SLOW_HINT=0` skips it). Help page Raspberry Pi carries levels and Vulkan class per Raspberry Pi OS release.
- Per-title memory model: title with `tso=off` whose last two recorded runs (run history on for that title) ended crash or hang (or without verdict under 60 s) runs strict for one start (start record `tso=off:strict`, log and notice; run that ends well re-arms it). End hint on slow emulation class: title that kept all cores busy for 120 s or more while drawing on GPU, without `tso=off`, raises one notice naming per-title emulation settings; nothing applied.
- Run record reason `vk32-cpu` for 32-bit title that keeps `-vulkan` on forwarding (`vk32=keep`; Vulkan on lavapipe).

### Changed

- Update / Repair and other setup runs from settings menu pick setup script whose version equals installed version (package command, installed copy, file beside menu), else newest of them. Old package next to newer zip install no longer runs older setup.
- Check for new version names upgrade command (package installs of release without package asset: package build steps) in place of manual installer command, and stores result for main screen line.
- Information and run report name client channel: `stable`, `Valve ARM channel (set by Steam Frame mode)`, `beta (Steam Beta Participation)`, else raw name; run report adds raw name in brackets.
- Display mode restore after game also covers KDE Plasma Wayland sessions: launcher reads output modes and positions with `kscreen-doctor -j` and puts them back with `kscreen-doctor`; other Wayland sessions still skipped.
- `--remove` deletes `/var/lib/steam-arm` (snapshots, records) and `/var/cache/steam-arm` (upgrade downloads).
- Settings file keys `SNAPSHOT_KEEP`, `UPDATE_CHECK_ON_OPEN` (part of setup choices in backups; earlier versions skip them) and `INSTALLED_FROM` (package installs of 3.0 and earlier, which lack it, detected through dpkg).
- Settings file keys `X87_CLIENT` and `CLIENT_LIGHT` (setup choices in backups); machine state keys `CPU_LSE`, `CPU_CORES`, `PLATFORM`, `MESA_HOST`.
- Setup warning without FEX thunk libraries names that FEX packages include them and that games draw on CPU without them.
- x86 client FEX app settings gain `SilentLog` 1 in `steamwebhelper.json`, `exe.json` and `steam.json` (FEX-2603 names its logging as `steamwebhelper` crash cause; nothing reads those logs); `steam.json` exists with that key alone when reduced x87 precision is off.
- Lighter client window on CPUs without LSE atomics also passes `-cef-disable-site-isolation` (one renderer process for store and library); `client-light off` removes it with rest.
- Title setting `d3d=dxvk` on Raspberry Pi GPU families kept but not applied: DXVK needs `shaderInt64`, `robustBufferAccess2`, `textureCompressionBC`, `multiViewport` and `tessellationShader`, V3DV reports none; run proceeds through WineD3D with log line and notice. Direct3D screen says so.
- Settings file keys `CLIENT_GPU`, `CEF_HANG_KILLS`, `CLIENT_TSO` (setup choices in backups; earlier versions skip them).
- Going back to earlier version (`upgrade --rollback`) removes `TSOEnabled` and `X87ReducedPrecision` keys from client FEX files first (earlier setup knows no such keys).
- CPU report verdict: `gpu process exits` line printed once when count is 0; since-boot throttle bits get own line and no longer decide `next step` (current bits 0 to 3 do).
- `VK_HOST` empty on `broadcom-vc4` (no Vulkan driver); GPU forwarding notice names `fex-emu-armv8.2` on `pi5`.
- Client window watchers (experiment, restart counter, memory model guard) wait up to 90 s for client process before treating its absence as exit; earlier trial could end `failed:client-exited` before client started.
- Experiment `lab-cef-gpu gl`: OpenGL 4.5 report set for client window no longer reaches games started in that session (handler drops it).
- Machine state key `VK_HOST`. `mesa_host` takes first package instance on multiarch hosts.

## [3.0] - 2026-10-16

### Added

- Run report: Maintenance, Report how last game ran, or `steam-arm-config report run [APPID|last] [--history] [--save]`. One file per game start, `~/steam-arm-report-<appid>-<YYYYMMDD>-<HHMM>.md` (mode 600, at most 30 KB): summary (route, graphics route, renderer verdict, run time and exit status of launch chain), fields FEX, Proton and Steam client issue forms ask for, settings in effect, kernel GPU and memory lines of run window, core dump lines when `systemd-coredump` is installed, earlier starts, folded handler lines and hardware report. Allow-listed lines only; hardware report filter plus machine-id, board serial, MAC addresses and Wi-Fi name, then every removed value checked again and line holding one dropped. Shown before saving; nothing leaves machine. Windows games on ARM64 Proton and native games: route, Steam start and end, hardware.
- Run history, off by default: Maintenance, Run history, or `steam-arm-config run-history on|off` (`RUN_HISTORY` in `/etc/steam-arm/steam-arm.conf`, part of setup choices in backups). One line per start and end of x86 game through emulation in client folder `.local/state/steam-arm/runs.log`, values only, newest 200 lines; not backed up; off deletes it.
- Launch handler log of each start names start time and run time (`start:`, `run time:`).
- Automatic tuning, off by default, per game: Games, game, Automatic tuning, or `steam-arm-config tune <appid> on|fix|off|reset|show` (title key `autotune=fix`). x86 Linux games through emulation only. Each start gets verdict from time, CPU use and renderer check: crash (chain ended within 60 s before GPU memory), hang (under 0.02 s CPU per second for 90 s before GPU memory, cleared when game holds GPU memory later in same start), drawing on CPU, no graphics in 300 s, or good; exit status not used, since launch chain returns 0 after crash. After bad verdict next start tries one changed setting from best one found: graphics route, FEX Multiblock, GL forwarding off for 32-bit games; good start keeps it. At most 4 trials per FEX tool, game build, Mesa version, GPU family and client type; never TSO, x87 or self-modifying code settings. Results in `~/.config/steam-arm/tuned.conf` of client home, loaded below `/etc` and personal title profiles, so keys set by hand win; key removed there by hand never tried again. Never sends signal to game: hang raises one notice to use Steam's Stop. Settings backup part `personal-tuning`; versions before 3.0 restore every other part of such backup.
- `--detect` and launcher log: one `patch <name>: active|retired|off (reason)` line per own fix, read from its drop signal at each start (FEX tool version, launch wrapper stand-in, private GLX copy, Vulkan features of GPU, client type, guestos link). Retired fix is not applied: `glx-lax` once system Mesa GLX has no cross-thread check left to patch, `vk-spoof` once GPU's Vulkan driver offers every feature layer reports, per-title thunk paths once FEX tool lists them (2609 and newer).

- Extra Mesa versions for route B games, none by default: Components, Driver archive, Extra versions, or setup option `--mesa-extra=<version>[,<version>]` with `--mesa-extra-file=<archive>` for local copy. Archive and disk size shown before build. Each version gets own tree `/opt/fex-rootfs/Ubuntu_24_04-mali-<version>`: hard-link copy of root filesystem plus that version's driver archive, SHA-256 pinned in installer (fixed list, no online list). Games, game, Mesa version, or title key `mesa=<version>`, picks version per game. Route B only (Mali drivers inside emulation: Java games, 32-bit Vulkan games, `gfx=b`); forwarding route: key logs line, changes nothing. Version not installed: driver archive's Mesa, with log line. Run record names Mesa in use. `--mesa-extra=` removes extra trees; deselecting `gpu-in-emulation` or `--remove` deletes them. Version choice is machine state, left out of settings restore; `mesa=` lines restore with game profiles, also in 2.3.2.
- `--detect` and hardware report line `official client: none|found (...)`: signs of official ARM64 Linux client from Valve (arm64 package owning `/usr/bin/steam`, Steam folder with ARM64 client parts and no Steam ARM mark, running client started without `-deckard`). Detection only; nothing changes.

### Changed

- Launch handler of native client enters through stand-in of Valve's launch wrapper (`linuxarm64/steam-launch-wrapper`, Valve's program kept as `.real`), independent of FEX tool type (Valve's Python tool or C++ tool). Valve's FEX tool files stay unedited: FEX settings through `FEX_APP_CONFIG` with Valve's per-title keys kept, thunk paths of FEX tools before 2609 in title's `compatdata/<appid>/fex-emu/ThunksDB.json`, `LD_PRELOAD` placed after FEX tool arguments. Edits of earlier versions put back at next start; client update replacing stand-in noticed within one second. FEX tool edit stays as fallback when stand-in cannot be placed. `--detect` names FEX tool type, handler entry and whether newest start reached handler.
- Issue forms: one required Steam ARM report field replaces hand-typed board, distribution, kernel, GPU, page size and component list fields.
- FEX code cache with Valve FEX tool FEX-2610 or newer, which turns cache on for every title (1 GB cap, entries of older FEX versions pruned): `diskcache=on` adds nothing, title cache deleted only after game update, `diskcache=off` turns it off per title. Older tools unchanged.
- Setup no longer links root filesystem as `/usr/share/guestos/fex-mesa`: launcher names graphics provider at every start. Link of earlier versions removed by setup; link or folder of other software stays.
- Title profile layers: included profiles, automatic tuning results, `/etc/steam-arm/titles.conf`, personal profiles (later wins). Settings menu shows values in effect from all four.
- Game-only settings of native client (`STEAM_ARM_VK_SPOOF=1` of `vk-spoof`, `DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1` of `shader-cache`) go into Valve's game environment file `~/.config/steam/env/gfx.txt` of client home, as block at top of file between `# Steam ARM begin` and `# Steam ARM end`; Valve's launch wrapper sets them at every game start, Windows and x86 Linux titles alike, and client process no longer carries them. Lines written by hand stay below block and win over it; removal takes block out (file too when nothing else is in it). File lines win over Steam launch options, so `PROTON_DXVK_D3D8=1` and Raspberry Pi `PROTON_USE_WINED3D=1` stay in launcher environment. x86 client, whose launch wrapper reads no such file, and launch wrapper without file support: launcher environment as before. `--detect` line `game environment file:`.
- Automatic tuning: `tuned.conf` line with tuning evidence but no decision state (restore of backup without state file, state file deleted) counts as tuning result, not as hand edit; pending trial in such line is dropped at end of next start.
- Header comment of `/etc/steam-arm/titles.conf` (refreshed by setup) lists `autotune` key and code cache default of FEX-2610 and newer.

### Fixed

- GE-Proton install: intermediate folders of unpacked archive took caller's umask (group write under umask 002); every folder made by unpack is 0755 now.
- `--remove --purge` left setup's empty `~/.config/autostart`, empty `/root/.fex-emu` and `/root/.local/share/fex-emu` folders of root filesystem download, and `add-apt-repository` cache `/root/.launchpadlib`: removed now when setup made them (recorded at setup), else named as kept.
- Setup printed shell error for missing box64 and box32 binfmt entries.
- Controller rules: `/etc/udev/rules.d` created when missing; failed rule write gives warning in place of silent skip.
- Renderer check logged `rendering on CPU (llvmpipe)` for game that loaded graphics library and then waited or stopped before drawing (own launcher window, display that never answers, start-up stuck). CPU verdict now needs game busy (0.1 s CPU per s or more over last 30 s and last 10 s); idle game without GPU memory gets no verdict, and check that ends without one logs `renderer: not detected` naming idle process.

## [2.3.2] - 2026-10-14

### Fixed

- Proton titles on Raspberry Pi GPUs (`broadcom-v3d71`, `broadcom-v3d42`, `broadcom-vc4`) tried DXVK, which cannot run on V3D: V3DV lacks about twelve Vulkan features DXVK requires (BC texture compression, `shaderInt64`, `multiDrawIndirect`, more than one viewport, descriptor indexing and others), so title stopped at device creation. Launcher sets `PROTON_USE_WINED3D=1` there now: Direct3D 8 to 11 through WineD3D on OpenGL. Own launch option `PROTON_USE_WINED3D` wins; `PROTON_DXVK_D3D8=1` no longer set on these GPUs. Title setting `d3d=dxvk` switches one title back for tests. Other GPU families unchanged (DXVK, `vk-spoof` on Mali).

### Added

- OpenGL version report per title on Raspberry Pi GPUs: `glver=3.3` (also 3.2, 4.0 to 4.6) sets `MESA_GL_VERSION_OVERRIDE` with matching `MESA_GLSL_VERSION_OVERRIDE`; off by default. Titles that only check version start; titles using OpenGL 3.2 and newer features draw wrong. Title setting wins over engine rules (Unity GL 4.5, Godot 3.3 report). CPU drawing verdict and notice on these GPUs suggest it; nothing changes by itself.
- Experimental Zink per title on Raspberry Pi GPUs: `gl=zink` sets `MESA_LOADER_DRIVER_OVERRIDE=zink` and `GALLIUM_DRIVER=zink`; off by default; unproven on Raspberry Pi.
- Settings menu Graphics, Route per game: rows Direct3D, OpenGL version and OpenGL driver on Raspberry Pi GPUs; game list column shows these settings (`DXVK, GL 3.3, Zink`) and Graphics intro names them in place of Mali route B; `steam-arm-config profile` accepts `d3d`, `glver` and `gl`, `--clear` removes them.
- Raspberry Pi GPU title settings reach Windows titles on ARM64 Proton as Steam launch option: launcher writes `STEAM_ARM_LAUNCHOPTS=<names> NAME=value ... %command%` ahead of account's own launch options in each `localconfig.vdf` before client start, replaces or removes it when setting changes, and leaves variable to own launch options when they set it (GL and Zink variables as pairs); removal takes it out. Own launch options come back byte for byte: `%command%` added for options without it (marked `STEAM_ARM_LAUNCHOPTS=+<names>`) goes again with own part. x86 Linux titles and x86 Proton get same settings through launch handler (log lines `d3d:`, `pi gpu:`).

### Changed

- Setup refreshes header comment of existing `/etc/steam-arm/titles.conf` to current key list (Raspberry Pi keys included); title lines and other comments kept byte for byte, file without Steam ARM header left as is.

### Known issues

- Raspberry Pi behaviour of this release is untested on Raspberry Pi hardware (no Pi on hand); it follows from Mesa source and community reports.
- Items listed under 2.3 Known issues still apply.

## [2.3.1] - 2026-10-09

### Fixed

- Hardware report kept Steam IDs (SteamID64, SteamID3, SteamID2, `-steamid=`, `userdata/<id>`), Steam sign-in and persona names (`config/loginusers.vdf`, `SteamUser`, `SteamAppUser`), public IPv4, IPv6 and e-mail addresses and token values; removed now. Account named with common word (`steam`, `games`, `pi`) no longer rewrites `steam-arm-config` and Steam paths; dot in account name no longer matches any character; host name holding account name no longer stays in part. Line still holding account, host or sign-in name after filter reads `(line removed: personal data)`.
- Handler logs `/tmp/fex-compat-tool-<pid>.log` and `/tmp/steam-arm-run-<pid>.log` were readable by every account (Valve's tool writes title's environment there); readable by game account only now. Run log never written through link or into file of another account.
- Setup on system without `apt-get`, `apt-cache` or `dpkg`, or with package architecture other than `arm64`, stops before any change with `No change made`; it wrote apt keyring folder and setup lock file before failing, and ran on x86-64 hosts. `--help`, `--detect` and `--list` run anywhere.
- x86 root filesystem and second graphics tree belonged to uid 1000 (owner in fetched image), so that account could change x86 programs other accounts run. Setup sets owner root and removes set-user-ID and set-group-ID bits, on trees of earlier versions too (logged once).
- Removal summary named `graphics_provider.json` as kept when `--purge` deleted root filesystem in same run. Empty `~/.fex-emu` and runtime files of tray and launcher in `/run/user/<uid>` (`steam-arm-tray`, `steam-arm-tray.lock`, `steam-arm-start.lock`, `steam-arm-warned`) stayed after removal; removed now.
- Program started from tray menu stayed as defunct process after it ended, until next start from tray; tray reaps it now.

## [2.3] - 2026-10-07

### Highlights

- x86 client on Armv8.0 CPUs without LSE atomics: setup installs Valve's x86 client and runs it through system FEX in place of stopping; native client returns once Valve's build runs on CPU again.
- Driver archive source for `gpu-in-emulation` picked in settings menu: download, local copy of published archive, or custom archive.
- FEX code cache per title (`diskcache=on`), off by default; Maintenance, Caches lists and clears it.
- 32-bit Source engine titles start through Windows build (Proton ARM64) automatically on `mali-csf-v10` with Valve FEX tool up to 2609 and `vk-spoof` chosen.
- Optional GE-Proton (ARM64) install from settings menu Maintenance; nothing downloads until picked.

### Added

- x86 client on Armv8.0 CPUs without LSE atomics (Cortex-A53, A57, A72, A73): setup installs Valve's x86 client and runs it through system FEX, in place of stopping ([steam-for-linux #13288](https://github.com/ValveSoftware/steam-for-linux/issues/13288)). Warning names cores and costs (slower start, client window drawn on CPU, x86 Proton for Windows titles). Same launcher, launch handler (through Valve's launch wrapper, forwarding route only), tray, settings menu and removal. Memory check: stop below 2 GB, warning below 4 GB. Package tools (`apt`, `apt-get`, `dpkg`, `pkexec`, `sudo`, `steamdeps`) refused for programs client starts, since emulated writes reach host system. Untested on Armv8.0 hardware.
- Native client check on x86 client: each setup run scans newest native client package (once per build) for Armv8.1 atomic instructions and, on Armv8.0 CPU, starts its client once; clean result moves back to native client in same run. `--client-check` checks only.
- `--client=auto|arm64|x86` and settings menu Maintenance, Client type: client type by hand, kept for later runs (`CLIENT`, `CLIENT_SET`, `CLIENT_PROBE` in settings file; machine state, not restored from backups). Information rows `Client type` and `CPU`, tray entry and title, hardware report block, `--detect` lines `cpu:` and `client:` name client type.
- Settings menu: Components opens Parts (checklist) and Driver archive. Driver archive picks source of `gpu-in-emulation` drivers: Download (default), Local copy of published archive (SHA-256 checked against published archive, path saved as `PROVIDER_LOCAL_FILE`) or Custom archive (SHA-256 from `.sha256` file beside archive, else typed). Information status row `Driver archive` names source. Command line: `steam-arm-config driver-archive status|download|local FILE|custom FILE SHA256`.
- Setup uses published driver archive placed beside `steam-arm-install.sh` when its SHA-256 matches, in place of download, and saves its path; path from `STEAM_ARM_PROVIDER_TARBALL` is saved too. Saved file gone or changed: setup downloads published copy with note. `--detect` prints `driver archive:` line (file name, SHA-256).
- Profile key `diskcache=on|off`: FEX code cache per title, Valve FEX tool FEX-2609.1 or newer; off unless set. Titles with own JIT compiler cache file-backed code only. Cache of title deleted once after FEX tool or game build change. Settings menu Games: FEX code cache row.
- Maintenance, Caches, and `steam-arm-config cache [list|clear all|<appid>]`: FEX code cache sizes, clear all or one game; Steam shader cache size shown, never cleared there. Hardware report line counts titles with code cache on.
- Settings menu Graphics, Automatic Windows build, and `steam-arm-config auto-build [on|off]`: state, rules and titles set; `AUTO_BUILD` key, carried in settings backup. Route per game shows titles set automatically and suggestions.
- Steam Deck category of title (hint) in settings menu Games header, from client's appinfo cache; Rules page adds Steam Deck runtime.
- CPU drawing notice, off by default: settings menu Graphics, CPU drawing notice, and `steam-arm-config cpu-notice [on|off]`; `CPU_NOTICE` key, carried in settings backup. With it on, x86 title drawn on CPU (renderer check) raises desktop notice that stays until closed; GoldSrc titles excluded. Game lists of settings menu mark titles drawn on CPU at last start with `CPU!`.
- `--detect` prints which features `vk-spoof` reports Vulkan driver has itself (`vulkan features native:`, `vulkan features missing:`); Information row `Vulkan gaps`.
- Settings menu Maintenance, GE-Proton (ARM64), and `steam-arm-config ge-proton [status|check|install|remove]`: optional install of newest GE-Proton ARM64 build, or of downloaded file with its `.sha512sum` (sha512 check, archive members checked, unpacked as game account); per-game pick in Graphics, Route per game (`ge`) and `steam-arm-config compat <appid> ge`; removal per version and on uninstall; hand-installed copies left unchanged. Off until installed; nothing downloads otherwise.
- Tray Steam pages: Store, Library, Friends, Downloads, Screenshots and Steam Settings, as in Steam's own tray menu. Each passes its `steam://` link to running client (`steam-arm --open`); never starts, stops or restarts client. Greyed while client is not running, while stop runs and during first start. Tray item for settings menu named `Steam ARM Settings`.

### Changed

- Armv8.0 CPUs no longer stop setup, Install / Setup screen or launcher: x86 client takes their place. `STEAM_ARM_ALLOW_ARMV80=1` now keeps native client (same as `--client=arm64`); launcher stops native client chosen automatically on Armv8.0 CPU (install from 2.2 or older) with hint to run Update / Repair.
- Tray icon drawn with dark outline (copy in runtime folder), readable on light panels.
- Settings menu game lists: name column 36 characters, setting column 24.
- GE-Proton tools show as `Windows build (GE-Proton<version>)` without `-aarch64` suffix (game lists: `Windows, GE-Proton<version>`). Restore lists GE-Proton builds not installed with install hint.
- `--provider-default` also clears saved local driver archive path. Driver download failure message names settings menu path (Components, Driver archive, Local copy) and file beside installer.

### Fixed

- 32-bit Source engine titles start through Windows build (Proton ARM64) without manual route choice on `mali-csf-v10` with Valve FEX tool up to 2609 and `vk-spoof` chosen: launcher sets it once per title when no build is chosen; title started before that skips one start with notice. Launch option `STEAM_ARM_AUTO_BUILD=0` starts Linux build once; Graphics > Route per game > Force Linux build keeps it.
- Windows build route uses tool name `proton_11-arm64`, as Steam lists it in Compatibility (`proton-stable-arm64` ran but showed blank there); earlier mappings stay valid.
- Automatic Windows build: title set by rule disappeared from lists once Steam swapped in Windows files, so Route per game, Automatic never dropped its record; record now decides. Shared-content manifests (`LastOwner` 0) no longer count as titles (notice counted one game twice) and no longer show in settings menu Games and Route per game.
- Renderer check gave CPU verdict and notice for start that hung before game ran (FEX loader process); no CPU verdict for such process. Wine helper processes (`explorer.exe`, `services.exe`, `wineserver` and others) no longer named as title in verdict.
- `--client-check` on Armv8.1 CPU reported "still needs Armv8.1"; Armv8.1 CPU runs any build (manifest read only). Result recorded as `CLIENT_PROBE`, so Client type screen shows last check.
- x86 client: `-shutdown` through emulation takes over 20 s; launcher waits 45 s before SIGTERM.
- Native client ended by signal (abort inside client) left no line in `steam-arm.log`; logged now, as for x86 client.
- x86 client: first start skipped file check when native package had left `ubuntu12_64/steamwebhelper`; marker `x86-verified` now decides. Private host libX11 copy makes X errors (`GLXBadFBConfig`) non-fatal for client. Client exit during first start logged with notice.
- Switch from x86 client back to native client left x86 builds of shared client files (Compatibility page failed); package records dropped, native client checks and downloads its files at next start. Client home records its client type (`.config/steam-arm/client-type`): setup moved from x86 test account back to native account no longer drops package records of native folder x86 client never used.
- Removal after switch back left `steam-launch-wrapper.real` copy; removed now.
- Setup summary and Notes line named missing Armv8.1 atomics for x86 client chosen by hand.
- Settings menu: CPU and Driver archive rows wrap with indent; dialog lists keep columns (`--no-collapse`); whiptail list height follows entry count, so summary lines above lists stay visible; Install wizard hardware screen keeps earlier choice after Back; download gauge shows download percent; dialog and whiptail text boxes use terminal height (System on 30-row terminal without scrolling).
- Hardware report and `cache` from other account: cache sizes unknown (no read access) in place of 0; `cache` asks for administrator rights with reason.
- GE-Proton remove: message names Steam's choice (Linux build where game has one) in place of default Proton alone.
- GE-Proton: interrupted release list or checksum download reported with curl status and retry hint (was `GitHub answer not understood.`); lock file `.steam-arm-ge.lock` removed after every action; failed screen puts log path on own line.
- Setup prints `local copy of driver archive` line for file named in environment (settings menu Local copy too), also when Mali tree is already built from that archive.
- Setup restarts running tray of game account, so new tray version runs without new login; restarted tray holds no file of setup run open (setup lock stays free for later runs; settings menu progress screen and piped setup output end with setup); summary names restart in place of next login.
- x86 client: fresh client folder never started (`Couldn't set up the Steam Runtime`): bootstrap package holds no runtime. Setup fetches runtime package `runtime_scout_ubuntu12` from x86 manifest (SHA-256 checked); launcher names missing runtime and Update / Repair in place of download hint.
- x86 client: first start in Deck interface on new account stopped at SteamOS update step (`steamos-update` missing, status 127). First sign-in now in desktop window; Deck interface from next start.
- x86 client: with `file` 5.4x (32-bit programs named `Intel i386`) every setup run unpacked bootstrap package again over updated client and left x86 `bwrap` of root filesystem in place; both checks accept `Intel i386` and `Intel 80386`.
- Automatic Windows build notice titled `Steam ARM: Windows build set`; says Steam downloads build in background; Graphics, Automatic Windows build screen says same.
- KDE rules file `kwinrulesrc` created by setup stayed after removal with no rules in it; removal now deletes it once empty (setup records that it created file).
- Setup for another account left records of previous account (`kwinrules-made`, FEX settings line in `owned.sha`), so later removal could take rule file of new account as setup-made. Record names account; setup for another account removes rule and created file of previous account and drops its lines.
- Driver archive recipe: library check in verify step read no library inside build roots (`/dev/fd` missing there) and reported pass. Build roots get `/dev/fd`; check that reads no library fails.
- Repeated starts during first start (menu entry, desktop icon, tray) stopped client still downloading its files and began first start again on each click, so first start never finished. Launcher runs one client start at once: lock held through first start and normal start until client window process runs; start meanwhile shows notice with progress (`Steam ARM is still setting up: downloading client files (40% of 648 MB)`; dialog with `zenity` without notification service, text on terminal) and exits without touching client. Tray Open items greyed meanwhile.
- Menu and desktop icons redrawn during first start stayed plain disc in running KDE session until next login. Launcher sends KDE icon change signal (`org.kde.KIconLoader.iconChanged`) after drawing, and draws once client's icon file keeps its size over one poll.
- Raspberry Pi OS: Steam window stayed empty; `steamwebhelper` needs `libibus-1.0-5`, which setup now installs (host package check and removal summary include it). `error while loading shared libraries` in `steamwebhelper.log` gives launcher warning naming library and its package; hardware report shows such lines.

### Known issues

- x86 client: on RK3588 test device (x86 client chosen by hand) client reaches sign-in and library with private libX11 copy (X errors not fatal); no client exit on X error in 6 starts. 32-bit Windows titles through x86 Proton draw on CPU (llvmpipe): emulator has no 32-bit GL or Vulkan forwarding; 64-bit Windows titles reach GPU. Untested on Armv8.0 hardware: first start, sign-in and GPU use of titles not confirmed there.
- FEX code cache (`diskcache=on`): setting covers runtime helper scripts of title start too; 2 of 11 starts with empty cache on FEX-2609.1 hung before game start. Off by default.
- Steam Frame rating of titles not shown: appinfo key (`steam_frame_compatibility`, categories as Steam Deck) known since this release, display not built yet.
- Linux build of 32-bit Source engine titles stuck at loading screen ignores Stop in Steam; desktop task manager (force quit) ends it.
- Java (LWJGL 2) titles on Valve FEX tool FEX-2607: about half of first-start map loads still fail; cause lies in FEX.
- 32-bit Source engine titles, native Linux build: Windows build set automatically only on `mali-csf-v10` with native ARM64 client, Valve FEX tool up to 2609 and `vk-spoof` chosen; other systems get suggestion in Graphics > Route per game.
- x86 client at sign-in window takes `-shutdown` but does not exit (client behaviour; native client exits); Steam ARM stops it with SIGTERM after 45 s.
- Items listed under 2.2 Known issues and not fixed above still apply.

## [2.2] - 2026-10-06

### Fixed

- Ubuntu 24.04 and Debian 12: setup added FEX package source, then failed at host packages (no SDL3 packages there). Setup now checks host packages with `apt-cache policy` before any package or package source change and stops naming missing packages and minimum releases (Ubuntu 25.10, Debian 13); README Requirements names them.
- FEX from another source: setup skipped FEX package source but still installed FEX packages, so systems with FEX built from source stopped at host packages. With `FEX` command not owned by `fex-emu` package and its x86 binfmt entries registered, setup installs no FEX packages; missing binfmt entries stop setup before any change.
- FEX thunk folders in game user's FEX configuration were fixed to `/usr`; setup now reads them from FEX's own prefix, `/usr` or `/usr/local`, and turns GL and Vulkan thunks off with warning when none is complete. x86 Remote Play stand-in runs `FEX` found on `PATH`, same FEX whose thunk folders setup reads, and launcher replaces stand-in left by earlier release whenever its content differs.
- `--remove` summary: package list names `libgtk2.0-0` as well as `libgtk2.0-0t64`; PPA removal hint on Ubuntu only when FEX package is installed.
- Mali family table: Mali-G615/G715 (arch v11) get own family `mali-csf-v11` (`gpu-in-emulation` and `glx-lax` on, untested); Mali-G1 (arch v14) gets `mali-csf-g1` (Mali components off, needs Mesa 26.2); both were `mali-csf` with note that Mesa does not support model. 32-bit Vulkan titles on Mali 5th gen stay on forwarding and `vk-spoof` is off there by default, since PanVK loads there only with `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`; `steam-arm-setup --help` names Mali-G610 class only. Install wizard (MediaTek) lists both new families.
- Debian 13 and Raspberry Pi OS: setup stopped at FEX package source (`software-properties-common` missing on Debian 13; `add-apt-repository` fails for PPAs on Debian 12). Outside Ubuntu family, setup now writes FEX's PPA as apt source `/etc/apt/sources.list.d/steam-arm-fex.sources` with Ubuntu series matching Debian release (Debian 13: noble, Debian 12: jammy) and signing key `/etc/apt/keyrings/steam-arm-fex.gpg`, checked against pinned fingerprint. Debian 11 and older stop at host package check (no SDL3 packages); message from FEX package source step names Debian 13. Earlier FEX source naming Debian release is renamed to `.disabled`. `--remove` deletes both files once no FEX build is installed. Ubuntu path unchanged.
- Apple GPU notes (setup, setup wizard page size screen, Information, README, COMPATIBILITY, COMPARISON) said client runs inside `muvm` or on 4K page kernel; no code sets up `muvm`, and setup stops there. Notes now say 16K page kernel is not supported; Apple Silicon page size message no longer offers `STEAM_ARM_IGNORE_PAGESIZE=1`. That variable skips check on non-4K host kernel; docs name it only for x86 side inside separate 4K page guest that check cannot see.
- Remote Play cause in README and FEATURES: native ARM64 streaming client hardware path (V4L2) fails with green screen on Qualcomm Iris (steam-for-linux #13428) and has no V4L2 decoder on Rockchip, so launcher runs x86-64 client under FEX, which reaches no host video decoder.
- RESEARCH: F5 (Metal Gear Rising: Revengeance) marked fixed upstream (FEX #5024); Thief 2014 dropped from known not-fixes (Android-only, FEX #5791), later items renumbered; F2 widened to PlayStation PC SDK titles that continue with full x87 precision, God of War Ragnarök listed as still crashing (FEX #4556); M3 no longer says Zink over PanVK reaches GL 4.x (needs `geometryShader` and `tessellationShader`).
- Host package check and FEX package choice read `apt-cache policy` in C locale; under translated locale every package counted as missing and setup stopped on supported releases.
- First start: client that exited before its files were complete made launcher exit with no message. Launcher now stops with message (dialog with `zenity` when started from menu) to start Steam ARM again to finish download, and starts client once more when bootstrap exited after updating itself.
- Launcher warnings that need action (Mali drivers inside emulation missing, private GLX copy missing or broken, display mode not put back, Bluetooth adapter left off) went to terminal and `steam-arm.log` only, so menu starts never showed them. Menu starts now also show desktop notification, once per text per login session.
- Settings menu and tray counted Steam client of any account as running; they now count only game account's client (tray: own account's).
- `steam-arm --help` did not list `--bigpicture` and `--desktop` and refused to run as root; it lists both and works as root.
- Setup run from settings menu: closing summary no longer shows command line hints (re-run options, settings menu command, uninstall command).
- Tray Stop sent SIGTERM to `steam` and `steamwebhelper` itself; it now runs `steam-arm --shutdown` (client's own exit, SIGTERM after 20 s) and is greyed while game runs, as settings menu Close Steam refuses then.
- Tray kept generic icon after client's first start until next login; it now switches to client's own icon once client has unpacked it.
- Tray autostart entry named KDE, GNOME and XFCE only, so labwc (Raspberry Pi OS) and other desktops never started tray at login; entry no longer limits desktops. Setup line said tray appears when client starts; it now says next login and each start.
- KDE window rule needed `kwriteconfig6`, so Plasma 5 got no rule and no message; setup now writes and removes rule with `kwriteconfig5` there, and prints skip line when KDE Plasma is installed and neither tool exists.
- Settings menu Games and Graphics showed hand-installed `GE-Proton*` tools as `Linux build`; tool names containing `proton` now count as Windows build; names not starting with `proton` show as `Windows build (<first 20 characters of tool name>)`.
- View logs said `launcher writes warnings only` for empty game and setup logs too; those now say `is empty`, and log not readable by account running menu says so. Last setup run said `No log found yet.` in menu run by desktop account, since setup logs of `sudo steam-arm-config` runs are kept in administrator's folder; menu now names that folder and `sudo steam-arm-config`.
- Godot 3 titles stopped at start (`GLXBadFBConfig` on forwarding, "Unable to initialize video driver" on Mali drivers route) unless profile set GL 3.3 report. Launch handler now sets `MESA_GL_VERSION_OVERRIDE=3.3` and `MESA_GLSL_VERSION_OVERRIDE=330` for them (log `godot 3: GL 3.3 report`); profile `godot=vulkan` leaves them as is. Not run on device yet without profile.
- Settings menu header on ARM systems without device tree (ACPI boards) printed `/proc/device-tree/model: No such file or directory` above menu; that error text is gone.
- Godot titles exported with PCK embedded in executable got no Godot rule; launch handler now also reads engine version from PCK appended to title's binary (or binary its start script names).
- Setup run from settings menu showed no download progress: client package (about 110 MB) and Mali driver archive (about 75 MB) printed one line while gauge stood still. Built-in progress screen now shows curl progress bar; setup log keeps final bar line only.
- Dialog texts (replace other variant, `pad-xbox`, hardware report, Free /dev/shm, Restore settings, Update / Repair, Uninstall) had line breaks inside sentences, leaving one-word lines on built-in screens; those sentences now wrap to screen width.
- `.deb` package removal said Steam client "it installed" stays, also when client came from script install; message now says Steam ARM client and its files stay.
- Godot version lookup missed `.pck` beside binary that start script names in subfolder (`bin/game.x86_64` + `bin/game.pck`) and `.pck` in install folder whose name holds `[`, `]`, `?` or `*`. Handler now reads packs in Godot's own order: PCK embedded in executable, `<name>.pck` beside it, then other `.pck` files in executable's folder, working folder or folder of last file argument.

### Changed

- README links `COMPARISON.md` near top.
- Godot rules (Godot 4 `--rendering-driver opengl3` and GL 3.3 report, Godot 3 GL 3.3 report) apply to Linux builds only; Windows Godot titles under x86 Proton, which got Godot 4 rule when `.pck` lay beside `.exe`, keep Godot defaults (log `godot 4: Windows build under x86 Proton, left as is`). Not measured on device with and without rule.
- Launcher checks page size at each start: 16K or 64K page kernel stops start with fix (Raspberry Pi 5 `page-size` component, 4K page kernel); `STEAM_ARM_IGNORE_PAGESIZE=1` skips check. Setup run with that variable on non-4K kernel keeps it in `/etc/steam-arm/steam-arm.conf`, so menu starts and later setup runs honour it.
- Launcher warns when no GPU render node is readable and writable by account (games draw on CPU), naming group to join; with Arm's closed `kbase` driver (`/dev/mali0`, no render node) it names kernel with Mesa's `panfrost` or `panthor` driver.
- `steam-arm.log` capped: over 1 MiB at start, it moves to `steam-arm.log.1` (one old copy kept).
- Settings menu: screens that need Steam closed (Install / Setup, Components, Controllers, Update / Repair, Uninstall, forced build in Graphics, Remote Play apply, Restore settings) offer `Close Steam` (runs `steam-arm --shutdown` as game account, in Install / Setup as account picked there; refused while game runs; question wraps to screen width) in place of "close it first" messages; setup and `steam-arm-config` command line stop messages name `steam-arm --shutdown`.
- Tray menu adds Open in Big Picture, Settings (settings menu in terminal emulator) and View log (`steam-arm.log` at its end in `less` in terminal emulator, else desktop's default program; greyed while log is empty or missing). Open in Big Picture and Open in desktop mode restart client, so they are greyed while game runs, as Stop is.
- Application menu entry "Steam ARM Settings" opens settings menu in terminal; written with launcher, removed by uninstaller.
- `.deb` package adds application menu entry "Steam ARM Setup"; `steam-arm-setup` without options in terminal opens setup menu, which asks for `sudo` itself.
- `.deb` package install over client set up earlier (by package, zip or script): package names Steam ARM version on system and command that applies new one (`sudo steam-arm-setup --keep`); package install never runs setup.
- `.deb` package carries `md5sums`, `Homepage` and `Installed-Size`; `build-deb.sh` gives byte-identical package from same sources with same `dpkg-deb` version (file times from top `doc/changelog` entry, or `SOURCE_DATE_EPOCH`; stops when that entry has no date).
- Maintenance, Check for new version, and `steam-arm-config update-check`: newest GitHub release compared with installed version, by hand only; nothing downloads.
- Hardware report adds last launcher log lines, start, update and error lines of client's bootstrap log, closing block of newest setup log, and game account groups next to groups of its running processes.

### Known issues

- Java (LWJGL 2) titles on Valve FEX tool FEX-2607: about half of first-start map loads fail (Java runtime crash in compiled code, server thread stall or deadlock). Cause lies in FEX; Multiblock off, TSO options, full SMC checks and other garbage collector do not lower rate. FEX-2609.1 beta: 2 of 10 failed.
- 32-bit Source engine titles, native Linux build: loading screen draws, then title hangs. Windows build through Proton reaches menu and plays; set it from Graphics > Route per game > windows.
- Client builds newer than 15 April 2026 stop at start on Armv8.0 CPUs without LSE atomics (Cortex-A53, A57, A72: Raspberry Pi 4, Pi 3) ([steam-for-linux #13288](https://github.com/ValveSoftware/steam-for-linux/issues/13288)); setup and launcher stop on such CPUs, as in 2.1.
- Items listed under 2.1 and 2.0 Known issues and not fixed above still apply.

## [2.1] - 2026-10-02

### Highlights

- Renderer check: launch handler logs whether title draws on GPU or on CPU (`renderer: GPU (<driver> <node>), forwarding to host driver`, or `renderer: warning: GPU forwarding not active: rendering on CPU (llvmpipe)` with reason). Hardware report lists renderer lines of five newest starts.
- Page size up front: settings menu title bar starts with page size state (`pages 4K ok`, `pages 16K: needs 4K` and others); setup and removal banners name page size and what `page-size` component does about it.
- FEX build matches CPU: setup picks `fex-emu-armv8.0`, `fex-emu-armv8.2` or `fex-emu-armv8.4` from CPU features, so setup completes on ARMv8.0 CPUs (Cortex-A72 and others); current client builds need Armv8.1 (Known issues).
- Display mode restore: launcher saves mode of each output when title starts and puts it back once no title runs, and when Steam closes.
- `steam-arm --shutdown`: stops running client, with SIGTERM fallback when client ignores its shutdown command.
- MangoHud in x86 Linux titles: `mangohud %command%`, `MANGOHUD=1` and profile `mangohud=on` draw HUD in 64-bit titles.
- `kde-input-prompt` component, off by default: no "Remote control requested" prompt on KDE Plasma (Wayland) when controller drives desktop.
- Profile key `multiblock=on|off`: FEX Multiblock per title.
- Armv8.1 check: setup, Install / Setup screen and launcher stop on CPUs without LSE atomics, naming client issue, before any package change.
- First start: desktop notification reports client download, unpack and install; menu icons show plain disc until client's own icon file arrives.

### Added

- Renderer check, on by default, log only: background thread watches title's processes for up to 180 s. GPU device counts once title allocates GPU memory on it; display controller and NPU device nodes are skipped; CPU verdict comes after 30 s with no GPU device in use, or with x86 Mesa inside emulation loaded. Mali drivers route reads `drivers inside emulation`. Game start not delayed. `STEAM_ARM_RENDERER_CHECK=0` turns it off per title.
- Compatibility tool check, read only: `compat: warning` line when Steam's `config.vdf` names Proton build for title but Linux build starts; `compat: x86 Proton` line when x86 Proton runs through emulation. Handler never writes `config.vdf`.
- GoldSrc titles (Half-Life engine): log line notes that video options pick OpenGL or Software renderer, and Software draws on CPU.
- Profile key `multiblock=on|off`: FEX Multiblock per title through `FEX_APP_CONFIG`. Launch option `FEX_APP_CONFIG` with `Multiblock` and Steam's FEX setting win over profile (`launch option kept`, `Steam setting kept`); profile wins over Java 21 rule (`title setting kept`). `steam-arm-config profile <appid> multiblock=on`; `--clear` removes it.
- `kde-input-prompt` component: pre-authorises input from X11 programs in KDE's permission store (`kde-authorized`, `remote-desktop`, empty app id) through `busctl`; value it replaces is saved and put back when component is turned off or on `--remove`. Listed only where KDE Plasma's Wayland compositor is installed or its setting is in place. Trade-off: every X11 program may then send input without asking. Setup, `--detect` and Information print one-line hint in KDE Plasma Wayland session.
- Display mode restore (X11 session): saved per output (mode id and position), restored 2 s after last title ends; log line `display mode put back after game`. `STEAM_ARM_MODE_RESTORE=0` turns it off; skipped in Wayland sessions and without `xrandr`. Host packages now include `x11-xserver-utils`.
- `steam-arm --shutdown`: `steam -shutdown`, SIGTERM after 20 s, never SIGKILL; exit status 1 when client still runs 30 s after SIGTERM.
- `steam-arm --help` (also `-h`, `help`): prints launcher usage and exits; client not started.
- Information: `OpenGL` line (host renderer, GL and core profile versions from `glxinfo -B`) and `CPU governor` line with governor and max clock per CPU cluster, `mixed` when clusters differ; note when host renderer is software (`llvmpipe`).
- `Fixing a game` help page: "Game is slow (CPU-bound)" and "Proton version keeps changing back"; renderer line in "Reading rules".
- `COMPATIBILITY.md`: Raspberry Pi graphics facts (V3D, V3DV) and Raspberry Pi 5 performance tips. `GAMES.md`: Raspberry Pi 5 table with expectations and community reports.
- `steam://` links open in Steam ARM: menu entry `steam-arm.desktop` declares `x-scheme-handler/steam` (`Exec=/usr/local/bin/steam-arm %U`); setup runs `update-desktop-database` after writing menu entries and on `--remove`. No `xdg-mime default` is set, so user's own `mimeapps.list` stays as it was.
- Armv8.1 check: first CPU's `Features` line without `atomics` stops setup before any package source or package change, stops Install / Setup screen at start, and stops launcher (log line plus dialog when started from menu); message names [steam-for-linux #13288](https://github.com/ValveSoftware/steam-for-linux/issues/13288). `STEAM_ARM_ALLOW_ARMV80=1` skips check (setup prints warning); settings menu passes it on to setup. `--remove`, `--detect` and `--help` run without check.
- First-start notification: client's first start downloads its files with no window; launcher sends desktop notification at once (`gdbus`, else `notify-send`) and updates it in place from client's bootstrap log: download in 10 % steps with total size, unpack, install, then "Client files installed. Steam opens now." Closed when client exits early, after 30 min, or when launcher ends; never on later starts. No new dependency.
- Placeholder icons: before client's first start, `steam-arm-icon` draws disc without logo and marks it (`.steam-arm-placeholder` in icon folder, `/usr/local/share/steam-arm/icon-placeholder` for system icons); setup line `menu icons: plain disc until first start, then redrawn from client's own icon`. Launcher redraws icons with logo once client has `steam_tray.ico`. Earlier, menu and desktop entries had no icon until first start.
- `README.md` Troubleshooting: Bluetooth adapter off after Steam starts, and title that keeps running after SIGTERM or Alt+F4 (quit from title's own menu, or run `steam-arm --shutdown`).

### Changed

- `--desktop` and `--bigpicture` switch running client through `--shutdown` path (was: give up after 60 s).
- Settings restore, Proton/tool per game: game with other tool chosen now keeps it; summary counts `kept (other tool chosen here)`.
- Install / Setup reads hardware details once per run; built-in screens drop keys typed while screen was loading.
- `FEATURES.md` corrected: FEX Multiblock is on in game user's own FEX configuration only; titles run through Valve's FEX tool use Valve's per-title value unless profile sets `multiblock`.
- Maintenance > Update / Repair asks before running setup (`Run` / `Back`, Back by default).

### Fixed

- Setup stopped on ARMv8.0 CPUs (Cortex-A72 and others): `fex-emu-armv8.2` has no install candidate there. Setup now picks build from CPU features, same rule as FEX's own installer, falls back to newest older build apt offers, never newer than CPU supports, and names chosen build in setup log. Removal lists all three builds.
- MangoHud never loaded in x86 titles: preload named MangoHud shim that root filesystem's MangoHud lacks, and game container maps `/usr` libraries to host system. Handler now copies root filesystem's MangoHud library into client folder (`.local/lib/steam-arm`) and preloads it from there. 32-bit titles get no MangoHud (root filesystem has no 32-bit build).
- Launch option `mangohud %command%` failed: host has no `mangohud` command. Setup adds small host shim `/usr/local/bin/mangohud` that sets `MANGOHUD=1`, written only where no `mangohud` of MangoHud package exists; removal deletes only that shim.
- Title that changed refresh rate (for example 1080p at 24 Hz) left it changed after exit.
- Client that ignored forwarded command lines, after second client ran under other home folder on same account, kept running on `--desktop` and `--bigpicture`.
- Settings restore summary: its only button read Back but led on to confirm screen; it now reads Next.
- Install / Setup: Back from parts could skip Vulkan screen, as key pressed while Vulkan screen loaded acted on it.
- Information showed governor and max clock of first CPU only (little core on boards with two clusters).
- `steam-arm --help` passed `--help` to client, which started second client session.
- Included profile `248570 overlay=off` (custom OpenGL engine title that stops when Steam overlay attaches), absent since 1.2, restored.
- Client in SteamOS mode switched host Bluetooth adapter off at every start: it sets adapter power from its own saved setting `System/Bluetooth/Enabled` in `config.vdf`, and unset means off. Launcher now writes host adapter state there before start (only while no client runs), and at exit powers adapter on again when it was on before start, client left it off and Steam's own Bluetooth switch is not off; log line `Bluetooth adapter left off by client; powered on again`.
- Components checklist cut off `kde-input-prompt` label; label now reads `KDE: no input prompt; X11 apps may send input` and fits.
- Information and hardware report showed FEX package string (or "not installed" when FEX came from another source) with FEX-2608 and newer: version came from `FEXInterpreter --version`, which those releases no longer include, and FEX-2609.1's `FEX` has no `--version`. Version now read from `FEXGetConfig --version` (for example `FEX-2609.1`), then `FEX --version`, then `FEXInterpreter --version`, then package.
- Setup started from folder game user cannot enter (for example `/root`) stopped with "client program missing after unpacking": steps that run as game user now start in that user's home folder.
- Maintenance > View logs: empty launcher log showed blank page; menu now says log is empty (launcher writes warnings only).

### Known issues

- Client builds newer than 15 April 2026 stop at start with SIGILL on Armv8.0 CPUs without LSE atomics (Cortex-A53, A57, A72: Raspberry Pi 4, Pi 3); client needs Armv8.1 or newer ([steam-for-linux #13288](https://github.com/ValveSoftware/steam-for-linux/issues/13288)). `README.md` Requirements, `COMPATIBILITY.md` and `GAMES.md` updated; setup and launcher stop on such CPUs (Added).
- One Java 17 title on Mali drivers route stopped with JVM crash after 21 s in one of three runs.
- MangoHud draws no HUD in Unity titles on Vulkan renderer.
- Custom OpenGL engine title with included `overlay=off` profile (app 248570) stops about 20 s in when MangoHud is loaded; leave MangoHud off for it.
- `steam://rungameid/<appid>` for title not in library can leave install dialog over games started later; restart Steam to clear it.
- `powerprofilesctl launch -p performance -- %command%` holds profile only when Steam was started from desktop session (menu or autostart); started from other context, hold is refused and title does not start.
- Items listed under 2.0 Known issues still apply.

## [2.0] - 2026-10-01

### Highlights

- Graphics route per title, automatic: launch handler puts Java titles and 32-bit Vulkan titles on Mali drivers inside emulation; other x86 titles stay on forwarding. Profile key `gfx=a` or `gfx=b` overrides per title.
- GPU family detection: installer reads kernel driver and GPU id of each render node and sets default state of `vk-spoof`, `gpu-in-emulation` and `glx-lax` per family. Mali components are on by default on Mali GPUs only; unknown GPU gets safe defaults. `--detect` prints result; `GPU_FAMILY=id` sets family by hand.
- `steam-arm-config`: settings menu with ten sections (Information, Install / Setup, Components, Graphics, Games, Controllers, Remote Play, Maintenance, Uninstall, Help / About) and command-line subcommands. Installer opens it when started in terminal with no options.
- PhysX install step skip: launcher marks legacy PhysX install step done in title's Proton prefix, so older Windows titles no longer wait on it at first start.
- Uninstaller: `--remove` takes out everything installer added; `--remove --purge` also deletes client folder and root filesystem setup downloaded, after typed confirmation.
- Controller access: Valve's `steam-devices` rules, plus pads from kernel `xpad` table that Valve's list lacks.
- Custom driver archive, opt-in for advanced users: own Mesa build for `gpu-in-emulation`, given by file and SHA-256; build recipe `tools/build-driver-archive.sh` and GitHub Actions workflow "Build driver archive" in GitHub source.

### Added

- GPU family detection: kernel driver name of each render node (DRM version query), Mali GPU id (Panthor and Panfrost queries), device tree compatible and PCI vendor; highest ranked node wins. 27 GPU families from Mali, Adreno, Apple, Raspberry Pi, Vivante, PowerVR, AMD, NVIDIA, Intel and virtual GPUs, plus `none` and `unknown`, each with default component states and note or warning; table in `README.md`, GPU detection. Installer, checklist and `--detect` print GPU line with kernel driver and Vulkan driver (from `vulkaninfo` when installed). `--help` marks components on by default on this system.
- `--detect`: prints GPU family, detected family, GPU, kernel driver, Vulkan driver, page size, distribution, default state of each component and family note, one `key: value` per line; installs nothing, needs no root.
- `GPU_FAMILY=id` in environment: family in place of detection, kept for later runs (`GPU_FAMILY_SET=user`); `GPU_FAMILY=auto` detects again; unknown id stops install with list of valid ids; with `--detect` it prints warning and valid ids, shows detected family and exits with status 0. Launch handler reads same family: Mali drivers route only on Mali families, 32-bit Vulkan titles on it only on `mali-csf-v10` and `mali-csf-5thgen`.
- `steam-arm-config` settings menu (`/usr/local/bin/steam-arm-config`), front end: built-in full-screen screens (Python `curses`, textured background, light dialog box), else `dialog`, `whiptail` or plain prompts; `STEAM_ARM_DIALOG=builtin|dialog|whiptail|read` picks one. Each menu opens with cursor on item chosen last. Sections: Information; Install / Setup (hardware, page size, Vulkan, parts, account, summary, which names client download only when no client is present); Components; Graphics (default route, route per game, forced Linux or Windows build); Games (overlay, MangoHud, extra environment and arguments, "Rules used at last start"); Controllers (`pad-xbox`); Remote Play; Maintenance (Update / Repair, logs, hardware report, free `/dev/shm`, back up settings, restore settings); Uninstall; Help / About with `Fixing a game` page. Subcommands `info`, `report`, `gfx`, `gfx-default`, `profile`, `compat`, `components`, `backup`, `restore`, `help fixing`.
- Account step of Install / Setup: pick existing account from list, or create new one. List holds normal accounts (uid 1000 to 59999, login shell, home folder present), marks current user and desktop user, and opens on current or desktop user, else account with uid 1000. Last entry `Create a new account...` asks for name (letters, digits, `.`, `_`, `@` and `-`, not starting with `-`, not root, not existing), then password twice; empty password: setup makes one and shows it at end. System with no normal account opens on new-account entry, with note saying why.
- Settings backup and restore (Maintenance, and `steam-arm-config backup` / `restore`): one file `steam-arm-settings-<date>-<time>.tar.gz` in folder of your choice, mode 600, owned by person who asked, with no host or account name. Parts by checklist: setup choices, system game profiles, personal game profiles, Proton/tool per game, FEX per-game settings, MangoHud settings. Personal parts come from, and go to, account picked in list of existing accounts; archive stores them without account name. Restore checks archive first (manifest and format version, expected names, no links, no paths outside, size limits), restores user choices only and lists skipped machine keys, merges or replaces game profiles per file with conflicts decided for all or one by one, leaves out tools not installed, keeps current files as `.bak-restore`, shows summary before applying, offers `setup --keep` when part lists change, and refuses while Steam ARM runs. Backup and restore never create, change or delete accounts, passwords or groups. Archive format 1; later versions read every earlier format. Setup writes copy of installer to `/usr/local/share/steam-arm/steam-arm-install.sh` for menu's Update / Repair, Components and Uninstall.
- `--password-stdin`: first line of standard input is password of game account, used only when setup creates that account; never printed or logged. Without it, setup makes password and prints it once, or with no terminal saves it to `/root/steam-arm-password-<name>.txt`, readable by root only.
- `GFX_DEFAULT` in `/etc/steam-arm/steam-arm.conf`: `auto` (default; empty same) rules decide, `a` every x86 title on forwarding (`forward` reads same), `b` every x86 title on Mali drivers in emulation (Mali GPU, or any GPU with custom driver archive); any other value: rules, with log line naming it. `steam-arm-config gfx-default auto|a|b` and menu write same values.
- Launch handler logs value it leaves alone: `launch option kept: NAME=value (rule wanted ...)` when launch option or environment already set what rule would set, and `title setting kept: gfx=...` when title profile route wins over rules. Unity and Godot lines name values in effect, launch options included: renderer and reported GL version.
- Package-install guard: `apt`, `apt-get` and `dpkg` of x86 root filesystem replaced by refusal that changes nothing and points to `Fixing a game` help page, since package installs under FEX write to host system; read-only `dpkg` queries still answer. Original stays as `<tool>.steam-arm-real` for experts; `--remove` puts originals back.
- `shader-cache` component, off by default on every GPU family: Steam's shader pre-caching, so Windows titles play in-game videos that show colour bars without it. Launcher starts client without `-noshaders` and sets `DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1`, since Steam's ARM64 pipeline caching layer stops Proton titles at Vulkan device creation. Costs several GB of download into `steamapps/shadercache` and processing on all cores after first start, installs and updates. Turning it off keeps cache, and turning it on again reuses it; Components confirmation shows cache size per library. Deleting `steamapps/shadercache` by hand stops Steam from downloading those caches again.
- `gpu-in-emulation` component, on by default on Mali GPUs: Mali drivers inside emulation. x86-64 and i386 Mesa 26.1.8 with Panfrost and PanVK go into second graphics tree `/opt/fex-rootfs/Ubuntu_24_04-mali`, hard-link copy of x86 root filesystem (about 330 MB extra disk), laid out as Valve does it on Steam Frame. Root filesystem used for forwarding stays unchanged. Driver archive (about 75 MB) downloads from this project's release with SHA-256 check, from release address first, then same file name under `releases/latest/download`; HTTP 404 at both stops setup with message naming missing file and `STEAM_ARM_PROVIDER_TARBALL`; `STEAM_ARM_PROVIDER_TARBALL` takes local file instead of that download. Deselecting component or `--remove` deletes second tree. Windows titles unchanged, since ARM64 Proton uses system Vulkan.
- Graphics route per title, automatic: launch handler puts Java titles (bundled Java runtime detected in game folder, including `lib/runtime` layout) and 32-bit titles started with `-vulkan` or `-force-vulkan` on Mali drivers in emulation; every other x86 title stays on forwarding. Java titles crash on forwarding; 32-bit Vulkan has no forwarding and ran on CPU renderer. LWJGL 2 titles get `-DLWJGL_DISABLE_XRANDR=true` in `JAVA_TOOL_OPTIONS`, Java 21 and newer get FEX Multiblock off, unless `FEX_APP_CONFIG` launch option sets Multiblock; Steam's per-title FEX setting counts as default, not as user choice. Profile key `gfx=a` (forwarding) or `gfx=b` (Mali drivers) overrides per title; on non-Mali GPU with published archive, `gfx=b` logs warning and title stays on forwarding. Game log line `steam-arm: graphics:` names route and reason.
- PhysX install step skip, automatic: legacy PhysX installer that some Windows titles run on first start waits with no window under emulation. Launcher reads title's install script and writes install step's has-run value into title's Proton prefix (`system.reg`), at least 1 and never below minimum script asks for, so Steam skips step from next start. Written only while no Wine process uses prefix. When prefix does not exist yet, PhysX installer running over 60 seconds gets SIGTERM and Steam continues to title. Log in `steam-arm.log`. Component `physx-skip`, on by default on every GPU family; turning it off stops launcher step and removes no files. `STEAM_ARM_PHYSX_SKIP=0` or `=1` turns it off or on for one client session.
- Uninstaller: `--remove` takes out launcher, helpers, settings menu, installer copy, menu and desktop entries, icons, controller rules, services, sudo rule, window rule, apt hook, setup logs and `/etc/steam-arm`, deletes second graphics tree, and restores `vm.max_map_count`, Raspberry Pi `config.txt` (then deletes its `config.txt.steam-arm.bak`), Valve's FEX tool files, Valve's streaming client in kept client folder and package tools of x86 root filesystem. Lingering goes off only when setup turned it on. Game profiles in `/etc/steam-arm/titles.conf` are saved to `/var/backups/steam-arm-titles-<date>.conf` first. `graphics_provider.json` and `~/.fex-emu/Config.json` go only while unchanged since setup. `/dev/shm` line in `/etc/fstab` goes only when setup added it; line setup did not add is listed as kept. Client folder with games is kept unless you confirm its deletion by typing `DELETE`, and is deleted only when it holds marker `.steam-arm-client`; folder of older install without marker is kept, with `rm -rf` line printed. Root filesystem, distribution packages and account groups are kept; account setup created is kept, with `sudo userdel -r <name>` printed to delete it. Removal prints `apt remove` line for packages nothing else needs. `--remove --purge` also deletes client folder and root filesystem, after typed confirmation; root filesystem only when setup downloaded it and other variant of this installer is not installed. Without terminal nothing is deleted. Refuses while client runs.
- `.deb` package: removal of package prints how to remove installed client (`--remove`, or Uninstall in `steam-arm-config`); `steam-arm-setup --detect`, `--list` and `--help` run without root.
- `--replace-other` retires other variant of this installer: its system files go into `/var/backups/steam-arm-replaced-<date>.tar` and files from its account's home into `/var/backups/steam-arm-replaced-<date>-<user>.tar`, owned by that account (restore with `sudo -u <user> tar -xpf <archive> -C /`); its tray, menu entries, window rule, services and rules stop, then setup continues. In 1.2 option only replaced launcher commands, and other variant's tray, menu entries and rules stayed active. Client folder and account of other variant stay in use, with games and sign-in, unless `ARMHOME_DIR`, `GAMEUSER` or settings file name others. `--detect-other` prints whether other variant is present. Install in `steam-arm-config` asks before it replaces other variant (Replace or Back).
- Controller rules: `pad-hidraw` installs Valve's controller rules from `steam-devices` (`60-steam-input.rules`, MIT licence) unless system package already provides them, plus rules for 241 pads from kernel `xpad` table that Valve's list lacks. Sony and Nintendo hidraw devices match by kernel pad driver (`hid-playstation`, `hid-sony`, `hid-nintendo`); on kernel without that driver module, by vendor.
- `glx-lax`: apt hook (`/etc/apt/apt.conf.d/80steam-arm-glx-lax`) rebuilds private GLX copy after every package run that changed system Mesa GLX. In 1.2 copy was rebuilt only at install, so Mesa upgrade could break OpenGL titles until next install.
- Launcher falls back to system Mesa GLX, with message in `steam-arm.log`, when private GLX copy is missing or cannot load; and to forwarding when title is set for Mali drivers in emulation but second tree is missing.
- Setup lock: second setup run started while install or removal is in progress stops with notice.
- Install, Update / Repair and component changes refuse while Steam ARM runs for game account, with message `Steam is running for '<user>'`.
- Client folder marker `.steam-arm-client`: install and Update / Repair write it only into folder that was new, empty, already marked or client folder of earlier Steam ARM install; folder that held other files gets none, now or on later runs (`ARMHOME_FOREIGN=1` in settings file), and removal keeps it with message saying so; 1.2 client folder is treated as earlier install under default name `.local/share/steam-arm` only. Folder with `steamapps` or `ubuntu12_32` at its top level is refused as other Steam install. Removal deletes only folder that holds marker; older client folder without it is kept.
- `/dev/shm` line in `/etc/fstab` added only when nothing else mounts `/dev/shm` at boot, recorded as `FSTAB_ADDED=1`.
- GPU components (`vk-spoof`, `gpu-in-emulation`, `glx-lax`) follow GPU family change between runs, except those set by hand; settings keys `COMPONENTS_USER_SET` and `COMPONENTS_FAMILY` record them. `--defaults` clears hand settings.
- Launch handler log on Mali drivers route: FEX `Multiblock` from `FEX_APP_CONFIG` launch option kept (`launch option kept`); GL or Vulkan thunk, graphics provider and GLX vendor from launch options replaced (`overridden for Mali route`). Profile `gl32=off` sets GLX vendor `mesa`.
- Valve's FEX tool: each edited file gets `<file>.steam-arm-sha` record, removed by uninstall; edits start once tool files stay unchanged for about 2 s after Steam updates tool.
- Launcher starts client again when it exits after applying its own update (exit status 42, or bootstrap log ending in "Update complete, launching" with no client left running), at most twice per start.
- x86 root filesystem: unfinished extraction left by stopped earlier run is discarded, or extracted again from downloaded `.sqsh`.
- Custom driver archive, opt-in: `STEAM_ARM_PROVIDER_TARBALL=/path` with `STEAM_ARM_PROVIDER_SHA256=<sha256>` replaces published archive. Setup checks SHA-256 and layout (only `usr/`, `etc/` and `graphics_provider.json` at top level, Mesa driver library present) and prints warning; archive kept across repair and update (`PROVIDER_CUSTOM_SHA256`, `PROVIDER_CUSTOM_FILE`); `--provider-default` switches back, clearing custom settings only once published tree is built; when that fails, custom settings and tree stay and setup says so. With it, `gfx=b` and `GFX_DEFAULT=b` apply on any GPU; automatic rules stay Mali-only. For advanced users; results depend on Mesa and kernel versions.
- GitHub source: driver archive recipe `tools/build-driver-archive.sh` (x86-64 Linux PC, about 25 GB disk, network, no root through user namespaces; writes `.tar.zst` and `.sha256`), and GitHub Actions workflow "Build driver archive" (`.github/workflows/build-driver-archive.yml`) that runs it with Mesa version as input and uploads both files as artifact.
- Launcher environment `STEAM_ARM_HOME` (client folder, absolute path) and `STEAM_ARM_VK_SPOOF_DEBUG=1` (layer prints its decisions) listed in `--help`; launch option `STEAM_ARM_VK_SPOOF_DISABLE=1` turns `vk-spoof` layer off per title.

### Changed

- Running installer in terminal with no options opens `steam-arm-config`; `--defaults`, `--select`, `--skip` and `--keep` install without menu. With no terminal in graphical session, zenity checklist as before.
- Default state of `vk-spoof`, `gpu-in-emulation` and `glx-lax` follows GPU family in place of fixed defaults.
- Requirements: Vulkan driver needed for Windows titles only; GPUs without Vulkan driver run native OpenGL titles.
- FEX tool 2609 and later lists runtime container library paths for forwarding itself (FEX commit 71afe47). Launcher reads tool version and edits Valve's `ThunksDB.json` only for older tools.
- Client channel: first download comes from Valve's stable ARM64 channel; installer no longer writes `publicbeta`. Client's Steam Frame mode moves it to its own ARM update channel on first start.
- FEX logging off (`SilentLog`) in Valve's FEX tool configuration.
- `pad-hidraw`: Valve's rules plus extra pads replace 1.2's generated list of 243 pads.
- 32-bit titles started with `-vulkan` or `-force-vulkan` keep option and run on Mali drivers in emulation on `mali-csf-v10` and `mali-csf-5thgen`; 1.2 removed it. Removed when second tree is missing, on other GPU families, with profile `gfx=a`, or with `GFX_DEFAULT=a`, unless profile says `vk32=keep`.
- Settings file: setup writes `VERSION`, `GPU_FAMILY`, `GPU_FAMILY_SET`, `GFX_DEFAULT=auto`, `COMPONENTS_USER_SET`, `COMPONENTS_FAMILY`, and when they apply `FSTAB_ADDED`, `RFS_CREATED`, `PROVIDER_CUSTOM_SHA256`, `PROVIDER_CUSTOM_FILE` and `ARMHOME_FOREIGN`, beside `ARMHOME_DIR`, `GAMEUSER`, `COMPONENTS_ON` and `COMPONENTS_OFF`.
- `STEAM_ARM_PROVIDER_TARBALL`: replaces driver archive download only; other install steps still need network.
- `page-size` component listed only on Raspberry Pi 5 class boards, on other Raspberry Pi with page size other than 4K, or while its `config.txt` block is in place; off and hidden elsewhere.
- `steam-arm-compatmap` refuses while Steam ARM runs, and refuses non-numeric app id, tool name with characters other than letters, digits, `_`, `.` and `-`, and malformed `config.vdf`, leaving file unchanged. First original stays as `config.vdf.bak-steam-arm`; later runs never overwrite it. `--remove` deletes title's entry under same checks; Graphics > Route per game > automatic and `steam-arm-config compat <appid> clear` use it.
- `steam-arm` refuses to run as root. Setup refuses `GAMEUSER` set to root, or name with characters other than letters, digits, `.`, `_`, `@` and `-`.
- Settings menu on system without `sudo`: says to log in as root (`su -`), then run `steam-arm-config`.
- Settings menu sudo prompt: screen clears, heading `Administrator password for <user> (sudo):` comes first, sudo asks on next line, then menu returns.
- Settings menu Graphics: route B offered on Mali GPU or with custom driver tree only; elsewhere menu notes that route B needs Mali GPU or custom driver archive, shows earlier B setting as `b (not used on this GPU)`, and `steam-arm-config gfx`, `gfx-default` and `profile gfx=b` refuse it. B on Mali GPU without `gpu-in-emulation` comes with note that games use forwarding until it is installed.
- Settings menu Games: Windows titles (Proton in Steam's compatibility tool list, Windows build installed, or Proton prefix in `compatdata`, which Steam's default Proton leaves with no tool entry) show rules and remove-all only, with note to use Steam launch options, since profiles reach Linux titles only.
- Settings menu status names custom driver tree: `present (custom drivers, sha <first 12>…)`.
- Downloads show curl progress bar on terminal only; setup logs and menu screens get error lines only.

### Fixed

- Launcher enabled private GLX copy and Vulkan layer even when `glx-lax` or `vk-spoof` was deselected. It now enables only components selected at install.
- Sudo rule (`/etc/sudoers.d/steam-arm`) was written on every install. It now exists only with `pad-xbox`, which launcher pauses through it, and is removed otherwise.
- Setup log line for kept client carried carriage return from client's `builddate.txt`.
- New account creation failed on systems without `render` group. Account now joins only groups that exist.
- Account that gained groups at install got no notice. Installer now says to log out and log back in before first start.
- Vulkan titles with Steam overlay hung at start when arm64 overlay Vulkan layer was registered twice, on systems where another variant of this installer had also run. Launcher now removes every second registration of that layer before client starts.
- Remote Play text in README: settings apply once account has signed in, not before first start.
- `steam-arm` started from account other than one chosen at setup, or after setup stopped before client step (Raspberry Pi 5 page-size switch), printed "Directory nonexistent" errors. Launcher now stops before writing anything and names account to use, or says to run setup again. Setup summary names account to play as when desktop session runs under another account.
- Security hardening: files in game account's home are written as that account, so link placed there never redirects root write; `ARMHOME_DIR` must be plain relative path below home (no `..`, spaces, special characters or shared folders such as `.local` or `Documents`); account named in settings file must already exist; sudo rule checked with `visudo` before it goes live; Valve's FEX tool files, settings file, profiles and `config.txt` edited through new file renamed over old one; temporary files made with `mktemp` and removed on exit; client package checked against checksum in Valve's manifest, driver archive against pinned SHA-256.

### Known issues

- 32-bit Linux title that includes DXVK Native: handler puts it on Mali drivers in emulation and DXVK creates its device on GPU; title then stops at loading screen, as with its OpenGL renderer.
- Mali drivers in emulation: GPU driver logs page-fault message at exit of one 32-bit Unity title; same message was logged on test device before that route existed; title unaffected.
- Godot 3 titles stop at start on both routes; profile `env=MESA_GL_VERSION_OVERRIDE=3.3;MESA_GLSL_VERSION_OVERRIDE=330` brings menu up.
- Client can stay on "Starting launch" or black "Abort game" screen after title exits on its own or after first-launch On-Screen Keyboard notice; exiting client from power menu or tray, then starting it again, clears it.
- Windows titles that need Direct3D feature level 11_0 (Unreal Engine 4, Unity HDRP) or Direct3D 12 do not run on Mali; see `COMPATIBILITY.md`.
- 32-bit Unreal Engine 3 title under Proton: PhysX install step now skipped, title then stops at start with engine assertion.
- Proton ARM64 titles: MangoHud and Steam overlay each crash title at start.
- Remote Play: Shift+Tab goes to host PC; use controller Steam button.
- GPU families other than `mali-csf-v10` are untested; their defaults follow driver documentation.

## [1.2] - 2026-09-29

### Added

- Title profile key `gl32=off`: title not detected as 64-bit runs without FEX's OpenGL forwarding, on x86 Mesa inside emulation (slower). For titles forwarding breaks. Handler writes FEX app configuration with `ThunksDB` GL off, merged with Steam's own FEX settings for that title.
- Title profile key `vk32=keep`: 32-bit title keeps `-vulkan` launch option (see Changed).
- Component checklist as desktop dialog (zenity) when installer starts with no controlling terminal in graphical session. Terminal checklist and runs with neither terminal nor display behave as before.
- `RESEARCH.md`: researched, untested notes per GPU family, emulation settings per title and engine, with what to change for each. Research AI-assisted; see disclaimer in file.

### Changed

- 32-bit titles: handler removes `-vulkan` and `-force-vulkan`. FEX forwards Vulkan for 64-bit code only, so 32-bit Vulkan ran on CPU renderer (lavapipe).
- Source 2 titles: handler logs warning, launch unchanged.
- Included title profile list is empty. Handler's engine rules cover Unity titles on Vulkan; title that stops when Steam overlay attaches takes local profile `<appid> overlay=off` in `/etc/steam-arm/titles.conf`.

### Fixed

- Memory held after game sessions: Steam overlay leaves two 25 MB frame buffers per session in `/dev/shm`, kept mapped by client's web helper until client restarts, so memory shrank with each game started. Launcher's minute sweep now frees their pages when no game runs (hole punched, file size and mappings kept). Test: 205 MB back to 55 MB one minute after third session.
- Profile `args` counted by Unity and Godot renderer rules: profile's own `-force-glcore` or `--rendering-driver` now wins, no second renderer option added.
- Titles started through start script (Source engine style) are detected by binary script starts: 32-bit rules, Unity and Godot rules apply to them.
- Installer stopped at RootFS step when earlier RootFS download was left behind: FEX's fetcher asked to overwrite it and aborted. Leftover download is removed before fetch.

## [1.1] - 2026-09-28

### Added

- Launch handler, `/usr/local/lib/steam-arm-handler.py`. Valve's FEX compatibility tool runs it in place of its removal of `LD_PRELOAD`, before runtime container starts. It decides per title, with no launch options:
  - Steam overlay: x86 overlay core for Linux x86 titles by default. Title profile `overlay=vulkan` adds arm64 overlay core and arm64 overlay Vulkan layer, for Vulkan titles; `overlay=off` removes overlay.
  - MangoHud: `mangohud %command%` and `MANGOHUD=1 %command%` both work in Linux x86 titles, OpenGL and Vulkan.
  - Godot 4 titles: OpenGL renderer and GL 3.3 report, found from game's `.pck` header. Godot's Vulkan renderer freezes on splash on PanVK; Panfrost reports GL 3.1.
  - Unity titles, found from player next to game: 64-bit players that carry Vulkan renderer start with `-force-vulkan` and overlay for Vulkan titles; other Unity 5 and later players get GL 4.5 report, since their OpenGL core context asks for more than Panfrost's 3.1 and title stops with `GLXBadFBConfig`; 32-bit Unity players start with Steam overlay off, as title stops when overlay attaches. Profile key `unity=vulkan|gl`.
  - If handler fails, tool behaves as Valve wrote it.
- Title profiles, one Steam app id per line: `/usr/local/share/steam-arm/titles.conf` (included), `/etc/steam-arm/titles.conf` (local), and per-user file. Keys: `overlay`, `mangohud`, `godot`, `env`, `args`. Launch options `STEAM_ARM_OVERLAY=x86|vulkan|off` and `STEAM_ARM_PRELOAD_KEEP=a,b` override profiles.
- arm64 Steam overlay Vulkan layer, which client includes but does not register, registered behind `STEAM_ARM_VK_OVERLAY`; handler sets it only for titles profiled `overlay=vulkan`.
- Direct3D 8 titles under Proton run through DXVK's `d3d8`: launcher sets `PROTON_DXVK_D3D8=1`. Proton's default for Direct3D 8, wined3d on OpenGL, draws them wrong on Mali driver. Launch option `PROTON_DXVK_D3D8=0 %command%` restores default.
- Launcher removes shared-memory segments no process maps from `/dev/shm`, at start and every minute: Steam overlay leaves 26 MB segment behind per game session here, and FEX leaves stats file per process. Overlay segments stay mapped by `steamwebhelper` while client runs, so sweep skips them; they are reclaimed at next client start.
- Included profile for one custom OpenGL engine title that stops when Steam overlay attaches (`overlay=off`).
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

- Installer published as plain script `steam-arm-install.sh`, readable before running; `.deb` still builds from GitHub source (`build-deb.sh`).

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
