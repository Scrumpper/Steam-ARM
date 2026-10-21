# Steam ARM: how it works

Client: Steam Frame's Steam client, Valve's native ARM64 build, set up on host.

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
+- other options without apt-get, apt-cache, dpkg or package architecture arm64
|    -> stop before any change ("No change made")
+- --remove [--purge]       -> uninstall (see Uninstall in README.md)
|    refuses while Steam client runs or another setup run holds lock
|    /etc/fstab: /dev/shm line out only when setup added it (FSTAB_ADDED=1);
|             line setup did not add: kept, and removal says so
|    client folder: deleted on typed DELETE, only with .steam-arm-client marker;
|             older client folder without marker kept
|    --purge: x86 root filesystem too, only when setup downloaded it
|             and other variant of this installer is not installed
|
+- older than installed version (3.1 and later) -> stop before any change,
|    unless --allow-older
+- --snapshot -> save installed version to /var/lib/steam-arm/snapshots, exit
+- install, update, repair
   |
   +- 0 checks: single setup run (lock), account and folder names (no root
   |            account), 4K page size, game account's Steam client closed,
   |            client folder holding steamapps or ubuntu12_32 refused;
   |            CPU: Armv8.1 (LSE atomics) -> native client, Armv8.0 -> x86 client
   |            (--client= or saved hand choice wins; x86: 2 GB memory or more)
   +- version change (installed VERSION differs): snapshot of installed version
   |    to /var/lib/steam-arm/snapshots (installer and menu copies, /etc/steam-arm,
   |    owned files with SHA-256, settings backup), upgrade.state written;
   |    snapshot failure stops setup before any change
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
   |    root filesystem and second tree owned by root, no set-user-ID files;
   |    unfinished extraction discarded, or extracted again from .sqsh;
   |    package guard: apt and dpkg inside emulation refuse to run
   +- 4 components: glx-lax, vk-spoof, gpu-in-emulation (second tree
   |    /opt/fex-rootfs/Ubuntu_24_04-mali: hard links plus Mali Mesa, route B;
   |    published archive (download, or local copy), or custom archive;
   |    extra Mesa trees /opt/fex-rootfs/Ubuntu_24_04-mali-<version> when picked,
   |    from SHA-256 pinned archives),
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
   |    settings in /etc/steam-arm/steam-arm.conf
   +- 7 version change finished: upgrade.state removed, history.log line,
        snapshots beyond installed version plus SNAPSHOT_KEEP earlier
        versions deleted (unfinished change and rollback target kept)

steam-arm-config upgrade (Maintenance, Upgrade to newest release)
+- refused: unfinished change, setup running, Steam running
+- GitHub releases/latest -> Steam.ARM.<version>.zip, .sha256, size, digest
+- same or older release -> nothing to do (--allow-older: older with warning)
+- package install (INSTALLED_FROM, else dpkg owns packaged setup):
|    release lists steam-arm-setup_<version>_arm64.deb (3.1 on) ->
|      digest required, download deb + .sha256 into staging folder,
|      size, sidecar form, SHA-256 (sidecar and GitHub digest), control
|      fields (steam-arm-setup, version, arm64), plan shown,
|      setup lock, snapshot, upgrade.state, apt-get install of checked file
|      (--allow-downgrades only with --allow-older), steam-arm-setup --keep;
|      apt or setup failure -> restore offered (upgrade --rollback)
|    release without package asset -> package steps, nothing downloads
+- free space, download (HTTPS only, 32 MB cap) into /var/cache/steam-arm/upgrade
+- size, sidecar form, SHA-256 (sidecar and GitHub digest), safe unpack
+- runs setup of new version with --keep (snapshot, install, new installed copy);
|    older setup before 3.1: snapshot saved here, run without --allow-older
+- failure after snapshot -> restore offered (upgrade --rollback)

steam-arm-config upgrade --rollback (Maintenance, Go back to previous version)
+- unfinished change without snapshot (--no-snapshot) -> no automatic pick,
|    snapshots listed, version named by hand
+- snapshot verified (manifest and member SHA-256, file list)
+- current version saved, files and /etc/steam-arm restored, installer and menu
|    copies put back, restored setup run with --keep
+- success -> history.log line, snapshots and staging folders pruned

steam-arm (launcher, desktop account only, refuses root)
+- before client start, client closed: automatic Windows build rule
|    (steam-arm-autobuild.py) sets Proton ARM64 for matching titles through
|    steam-arm-compatmap.py, once per title
+- own fixes: drop signal of each read at start (steam-arm-entry.py patches,
|    logged; --detect prints same lines): FEX tool version (thunk paths, code
|    cache), launch wrapper stand-in (FEX tool edit), private GLX copy built
|    patched or not (glx-lax), Vulkan features of GPU (vk-spoof), client type,
|    guestos link; retired fix is not applied
+- game-only settings (vk-spoof layer on, shader-cache layer off): native client
|    -> block in Valve's game environment file ~/.config/steam/env/gfx.txt of
|    client home, set by Valve's launch wrapper at each game start; x86 client
|    -> launcher environment. Settings launch options override per title
|    (PROTON_DXVK_D3D8, Pi PROTON_USE_WINED3D) stay launcher environment
+- one client start at once (start lock): start during first start or before
|    client window runs shows progress notice and exits, client untouched
+- starts client (Big Picture or desktop mode)
+- client exits after applying its own update -> started again, at most twice
+- native client: launch wrapper stand-in (linuxarm64/steam-launch-wrapper,
|    Valve's program kept as <name>.real) set at start and again after client
|    update; starts through Valve's FEX tool -> steam-arm-run.py -> launch
|    handler -> Valve's launch wrapper; other starts go straight to Valve's
|    program. Valve's FEX tool files stay unedited; edits of earlier versions
|    put back. Fallback without stand-in: FEX tool edit (forwarding on,
|    per-title hook), sha of each edited file in <file>.steam-arm-sha
+- marks PhysX install step done in Proton prefixes; frees /dev/shm every minute
+- x86 client: steam.sh through system FEX (x86 bash of root filesystem), host
|    bubblewrap for runtime containers (steam-arm-pv-bwrap), client browser on
|    CPU, webhelper flag, launch wrapper stand-in and private libX11 copy (X
|    errors not fatal) set again at each start; first start checks files once;
|    launch wrapper stand-in -> steam-arm-run.py -> launch handler per title
|    (forwarding route only) -> Valve's launch wrapper
+- kde-input-prompt: sets or puts back KDE input permission in desktop session
+- --perf-stats (off by default): Mesa overlay layer (Vulkan) and Gallium HUD dump
|    (OpenGL) set hidden in game environment; steam-arm-perf.py watch prints frame
|    interval p50/p95/p99/max and counts over 25 and 50 ms every 5 s, perf.log;
|    Steam already running: foreground for games started from then on
+- still-working notice (1 s watcher, auto: where display mode restore runs):
|    game start without frame 20 s -> one notice: compiling shaders (cache
|    growth, fossilize_replay), loading, not responding (no CPU or disk wait
|    10 s); frame = GPU engine time in fdinfo rising, or readout files growing;
|    closed on first frame
|
+- Play: Windows title -> Proton ARM64 -> DXVK -> system Vulkan (PanVK)
|                                         vk-spoof reports features DXVK needs
|    GE-Proton build (optional), when picked per game, takes place of Valve's
|    ARM64 Proton; same runtime container, same host Vulkan driver
+- Play: x86 Linux title -> launch handler (stand-in) -> Valve's FEX tool, per title:
     FEX settings through FEX_APP_CONFIG: Valve's per-title keys (appinfo,
       Steam's FEX setting) as Valve's tool writes them, plus thunks on, own
       FEXServer socket, FEX log off; FEX_APP_CONFIG launch option wins
     FEX tool before 2609 (probe thunk-paths active): thunk paths of runtime
       container in title's compatdata/<appid>/fex-emu/ThunksDB.json (FEX reads
       it after Valve's); removed once probe retires fix
     LD_PRELOAD (overlay, MangoHud) placed after FEX tool arguments (env)
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
       cache deleted once when FEX tool or game build changed; FEX tool 2610+
       turns cache on for every title (1 GB cap): diskcache=on adds nothing,
       cache deleted after game build change only, diskcache=off turns it off
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
     route B tree: profile mesa=<version> with that tree installed -> extra tree;
       else second tree (log line); route A: mesa= logged, nothing else
     route A: FEX forwards OpenGL and Vulkan to system Mesa (glx-lax for threads)
     route B: x86 Mesa inside emulation drives GPU directly; Multiblock set by
              FEX_APP_CONFIG launch option kept (Steam's per-title FEX setting
              is not user choice); thunk, provider and GLX launch options
              replaced ("overridden for Mali route" in log)
     -> Steam runtime container -> FEX -> title -> GPU
     renderer check (background, up to 180 s): GPU device title holds, or
       "GPU forwarding not active: rendering on CPU (llvmpipe)" in log (busy
       title, no GPU memory); idle title without GPU memory: no verdict;
       CPU_NOTICE=on: desktop notice too (GoldSrc titles excluded)
     run history (RUN_HISTORY=on): start line from launch handler, end line
       (exit status, run time, renderer verdict) from steam-arm-run.py, in
       client folder .local/state/steam-arm/runs.log, newest 200 lines;
       steam-arm-config report run reads it with handler logs of /tmp
     automatic tuning (autotune=fix, off by default; steam-arm-autotune.py):
       profile layers: included < tuned.conf (results) < /etc < personal
       start: stamp (FEX tool, game build, Mesa, GPU family, client type),
         keys set by hand skipped, trial counted, one notice
       during run: renderer check up to 300 s; hang check reads /proc: under
         0.02 s CPU per s for 90 s before GPU memory -> hang, one notice;
         GPU memory later in same start clears it
         (stop with Steam's Stop); never signals game
       end (steam-arm-run.py): verdict crash / hang / CPU / no graphics / good;
         bad -> next start tries one knob from best found (gfx, multiblock,
         gl32), good -> kept; at most 4 trials per stamp
```
