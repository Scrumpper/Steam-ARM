# Steam ARM: how it works

Overview of what runs where: setup command, GPU detection, component defaults,
launcher, per-title launch handler and graphics routes. Details per step: `README.md`.

Flow from install command to game frame:

```
sudo bash steam-arm-install.sh [options]          (package: sudo steam-arm-setup)
|
+- no options, in terminal -> steam-arm-config (settings menu)
|    sections: Information, Install / Setup, Components, Graphics, Games,
|    Controllers, Remote Play, Maintenance, Uninstall, Help / About
|    front end: built-in screens, else dialog, whiptail or plain prompts
|    menu calls installer back with options (--select ..., GPU_FAMILY=...)
+- --detect, --list, --help -> print and exit, no root needed
+- --remove [--purge]       -> uninstall (see Uninstall in README.md)
|    refuses while Steam client runs or another setup run holds lock
|    /etc/fstab: /dev/shm line out only when setup added it (FSTAB_ADDED=1);
|             line setup did not add: kept, and removal says so
|    client folder: deleted on typed DELETE, only with .steam-arm-client marker;
|             older client folder without marker kept
|    --purge: x86 root filesystem too, only when setup downloaded it
|             and other variant of this installer is not installed
|
+- install, update, repair
   |
   +- 0 checks: single setup run (lock), account and folder names (no root
   |            account), 4K page size, game account's Steam client closed,
   |            client folder holding steamapps or ubuntu12_32 refused;
   |            CPU: Armv8.1 (LSE atomics) -> native client, Armv8.0 -> x86 client
   |            (--client= or saved hand choice wins; x86: 2 GB memory or more)
   +- 1 GPU detection
   |    render node -> kernel driver name (panthor, panfrost, msm, v3d, ...)
   |    Mali: GPU id; fallback: sysfs driver link and device tree
   |    optional: vulkaninfo for Vulkan driver and version
   |    several GPUs: best one wins; GPU_FAMILY=<id> replaces detection
   |    unknown id: --detect warns and lists valid ids, install stops
   |    result: GPU family, for example mali-csf-v10 (RK3588, Mali-G610)
   +- 2 component defaults from GPU family (saved choices win)
   |    Mali G610 / G310: vk-spoof, gpu-in-emulation, glx-lax on
   |    Mali G615 / G715 / 5th gen: gpu-in-emulation and glx-lax on; Mali-G1: glx-lax on
   |    older Mali: gpu-in-emulation and glx-lax on (OpenGL only)
   |    other GPUs: Mali components off, glx-lax on
   |    family changed since last run: GPU components take new defaults,
   |    except those set by hand (COMPONENTS_USER_SET)
   +- 3 host: FEX and binfmt, account and groups, /dev/shm (fstab line only
   |    when nothing else mounts it), vm.max_map_count,
   |    x86 root filesystem /opt/fex-rootfs/Ubuntu_24_04 (route A);
   |    unfinished extraction discarded, or extracted again from .sqsh;
   |    package guard: apt and dpkg inside emulation refuse to run
   +- 4 components: glx-lax, vk-spoof, gpu-in-emulation (second tree
   |    /opt/fex-rootfs/Ubuntu_24_04-mali: hard links plus Mali Mesa, route B;
   |    published archive (download, or local copy), or custom archive),
   |    controller rules, menu entries, icons, tray,
   |    kde-input-prompt (KDE Plasma; off by default),
   |    page-size (Pi 5 class, or Pi with page size other than 4K)
   +- 5 Steam client: Valve's ARM64 package, checksum checked, unpacked as user;
   |    x86 client: native package checked first (once per build: Armv8.1
   |    atomics scan, one start on this CPU), clean -> native client again;
   |    else Valve's x86 bootstrap (steam.sh, ubuntu12_32/steam) into client folder;
   |    marker .steam-arm-client written into client folder when folder was
   |    new, empty, already marked or earlier Steam ARM client folder
   +- 6 launcher steam-arm, settings menu, helpers;
        settings in /etc/steam-arm/steam-arm.conf

steam-arm (launcher, desktop account only, refuses root)
+- before client start, client closed: automatic Windows build rule
|    (steam-arm-autobuild.py) sets Proton ARM64 for matching titles through
|    steam-arm-compatmap.py, once per title
+- one client start at once (start lock): start during first start or before
|    client window runs shows progress notice and exits, client untouched
+- starts client (Big Picture or desktop mode)
+- client exits after applying its own update -> started again, at most twice
+- keeps Valve's FEX tool set up (forwarding on, per-title hook) when tool changes:
|    waits until tool files stay unchanged for 2 s, then edits them;
|    sha of each edited file in <file>.steam-arm-sha, removed again by uninstall
+- marks PhysX install step done in Proton prefixes; frees /dev/shm every minute
+- x86 client: steam.sh through system FEX (x86 bash of root filesystem), host
|    bubblewrap for runtime containers (steam-arm-pv-bwrap), client browser on
|    CPU, webhelper flag, launch wrapper stand-in and private libX11 copy (X
|    errors not fatal) set again at each start; first start checks files once;
|    launch wrapper stand-in -> steam-arm-run.py -> launch handler per title
|    (forwarding route only) -> Valve's launch wrapper
+- kde-input-prompt: sets or puts back KDE input permission in desktop session
|
+- Play: Windows title -> Proton ARM64 -> DXVK -> system Vulkan (PanVK)
|                                         vk-spoof reports features DXVK needs
|    GE-Proton build (optional), when picked per game, takes place of Valve's
|    ARM64 Proton; same runtime container, same host Vulkan driver
+- Play: x86 Linux title -> Valve's FEX tool -> launch handler, per title:
     reads title profile, GFX_DEFAULT, GPU family
     detects engine: Unity, Godot (embedded PCK, else .pck beside game), Java (bundled
       runtime, LWJGL), 32-bit, Source 2, GoldSrc (note only); Godot rules skip
       Windows builds under x86 Proton
     reads Steam's saved tool for title (config.vdf, never written): note when
       Proton build saved but Linux build started
     32-bit Source title not yet switched by automatic Windows build: start
       skipped once, desktop notice (STEAM_ARM_AUTO_BUILD=0 starts it)
     profile multiblock=on|off sets FEX Multiblock for title
     profile diskcache=on|off sets FEX code cache for title (FEX tool 2609.1+);
       cache deleted once when FEX tool or game build changed
     applies rules; launch options set by user win ("launch option kept" in log);
     log lines show values in effect (Unity GL, Godot renderer and GL)
     picks graphics route:
       profile gfx=a / gfx=b                 -> route set by user
                                                (gfx=b on non-Mali GPU with published
                                                archive: A, with warning)
       GFX_DEFAULT=a (or forward) / b        -> all titles A / all titles B
                                                (b: Mali GPU, or custom driver archive)
       Java title on Mali GPU                -> B (LWJGL 2 option;
                                                Java 21+: Multiblock off)
       32-bit -vulkan on Mali G610           -> B (keeps -vulkan)
       other titles                          -> A
     route A: FEX forwards OpenGL and Vulkan to system Mesa (glx-lax for threads)
     route B: x86 Mesa inside emulation drives GPU directly; Multiblock set by
              FEX_APP_CONFIG launch option kept (Steam's per-title FEX setting
              is not user choice); thunk, provider and GLX launch options
              replaced ("overridden for Mali route" in log)
     -> Steam runtime container -> FEX -> title -> GPU
     renderer check (background, up to 180 s): GPU device title holds, or
       "GPU forwarding not active: rendering on CPU (llvmpipe)" in log;
       CPU_NOTICE=on: desktop notice too (GoldSrc titles excluded)
```
