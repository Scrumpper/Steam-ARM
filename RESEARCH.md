# Steam ARM · Researched, untested

Driver facts per GPU family, FEX settings per title, engine notes, known not-fixes and
refuted advice, each with what to change and where. Items marked "tested" ran on test
system (RK3588, Mali-G610); every other item is research only.

---

## Contents

1. Read this first
2. Where changes go
3. Tested on test system
4. Driver facts by GPU family
   - Mali: Panfrost and PanVK
   - Adreno: Turnip
   - Apple M-series: Asahi
   - Raspberry Pi 5: v3dv
   - Discrete GPUs on ARM hosts
5. FEX settings per title
6. Engine notes
7. Known not-fixes
8. Refuted advice
9. Popular-game survey
10. Reporting results
11. Disclaimer

---

## Read this first

Research behind this document was AI-assisted. AI agents ran web searches, fetched sources
and extracted claims; independent AI verifiers then cross-checked each claim against its
source, and claims that failed were dropped or moved to Refuted advice. Sources are cited
as plain links after each claim.

- Nothing here is tested unless marked "tested on test system" (section 3 and status
  lines).
- Test system: RK3588, Mali-G610, Panfrost and PanVK, Mesa 26.1, KDE Plasma on X11.
- Results vary by driver version, Mesa build, FEX build and Proton build. Claim valid for
  one Mesa release can be wrong for next one.
- Verify on your own system before relying on any item. Change one setting per test run
  and note what changed.
- Report what worked and what did not through project's compatibility report (see
  Reporting results). Reports move items from researched to tested.

Requirements, pre-install checks and device classes are in `COMPATIBILITY.md`; results by
game type are in `GAMES.md`. This document does not repeat them.

## Where changes go

Every item below ends with "What to change". Four places take those changes.

### Steam launch options

Title's Properties, General, Launch Options. Environment variables go before `%command%`,
game arguments after it:

```
PAN_MESA_DEBUG=noafbc %command%
FEX_X87REDUCEDPRECISION=0 %command%
%command% -vulkan
```

Launch options work for Linux x86 titles and for Windows titles under Proton. For Proton
titles they are only place: launch handler does not run for them.

### Title profiles (`titles.conf`)

One line per title, keyed by Steam app id. Launch handler reads them for Linux x86 titles
that run through FEX; Proton titles ignore them.

Read in this order, later files overriding earlier ones:

- `/usr/local/share/steam-arm/titles.conf`: included; installer replaces it every run, so
  local lines belong in one of files below.
- `/etc/steam-arm/titles.conf`: system wide.
- `~/.config/steam-arm/titles.conf`: per user, in account client runs under.

Line format and keys:

```
<appid> key=value key=value ...
  overlay=x86|vulkan|off     Steam overlay mode
  mangohud=on|off            MangoHud HUD
  godot=gl|vulkan            Godot renderer and GL report
  unity=vulkan|gl            Unity renderer
  env=NAME=VALUE             environment; several joined with ;  (env=A=1;B=2)
  args=ARG                   extra game arguments; several joined with ;  (args=-x;-y)
  gl32=off                   32-bit title without OpenGL forwarding (emulated x86 Mesa)
  vk32=keep                  32-bit title keeps -vulkan (removed by default)
```

Examples:

```
<appid> env=PAN_MESA_DEBUG=gl3
<appid> env=FEX_MULTIBLOCK=0;FEX_X87REDUCEDPRECISION=1
367520 unity=gl
```

Values from `env=` override engine settings handler applies on its own. Handler prints
every decision to `/tmp/fex-compat-tool-<pid>.log`; check it to confirm line took effect.

### Installer components

GPU family detection sets default state of components written for one driver
(`vk-spoof`, `gpu-in-emulation`, `glx-lax`); `--detect` prints family and defaults. On GPU
detection does not recognise, leave component out by hand:

```
sudo bash steam-arm-install.sh --skip vk-spoof
```

`--list` prints components; re-running with component deselected removes it.

### FEX AppConfig files

FEX also reads per-program JSON files. Environment variables (`FEX_<OPTION>`) beat every
JSON file, and it is not verified whether Valve's FEX build inside Steam's runtime
container reads these files at all. Prefer launch options or `env=`; use JSON only for
settings that have no environment variable (see F8). Details in F1.

---

## Tested on test system

Status of every item in this section: tested on test system (RK3588, Mali-G610).

### T1. 32-bit titles: OpenGL only, never `-vulkan`

FEX forwards 32-bit OpenGL to host driver but has no 32-bit Vulkan forwarding. With
`-vulkan`, 32-bit title renders on lavapipe, CPU renderer.

What to change: remove `-vulkan` from launch options and from `args=` of 32-bit titles.
Properties, Installed Files, Browse opens game folder; `file` on game binary shows
bitness:

```
file <game folder>/<binary>
```

### T2. `PAN_MESA_DEBUG=gl3`: per title, never global

Flag enables Panfrost's experimental GL 3.2/3.3 path; Mesa source describes it as "Enable
experimental GL 3.x implementation, up to 3.3"
<https://github.com/FireBurn/mesa/blob/main/src/gallium/drivers/panfrost/pan_screen.c>.
Mesa's public docs do not list it <https://docs.mesa3d.org/envvars.html>. Games that see
GL 3.3 pick heavier render paths, so global use changes titles that ran fine at 3.1.

What to change: for one title that needs GL 3.2 or 3.3, launch option
`PAN_MESA_DEBUG=gl3 %command%` or profile line `<appid> env=PAN_MESA_DEBUG=gl3`. Do not
put it in shell profile, `/etc/environment` or session environment.

### T3. 32-bit Source engine title, native build, hangs at load

Native 32-bit build hangs at load under every OpenGL variant tried: plain,
`PAN_MESA_DEBUG=gl3`, `+mat_queue_mode 0`, overlay off, MangoHud off, GLX vendor forced to
Mesa. Windows build under Proton runs, slowly. FEX's lead developer lists 32-bit GL
forwarding as breaking several Source engine titles
<https://github.com/FEX-Emu/FEX/issues/4645>, but on test system hang stays with
forwarding off (below).

What to change: Properties, Compatibility, force ARM64 Proton build to run Windows
version. Also tested, same hang at load with all threads waiting: `<appid> gl32=off` (emulated
x86 Mesa, no GL forwarding), FEX Multiblock off, `-nosound`, FEX TSO forced on. GL
forwarding is not cause on test system. No setting fixed native build.

### T4. Unity rules (automatic)

Handler inspects Unity player and applies, with no launch options:

- 64-bit player with Vulkan renderer: `-force-vulkan`, overlay for Vulkan titles.
- Other Unity 5 and later players: GL 4.5 report (`MESA_GL_VERSION_OVERRIDE=4.5`,
  `MESA_GLSL_VERSION_OVERRIDE=450`). GL 3.3 report was not enough: title stopped with
  `GLXBadFBConfig`.
- 32-bit players: Steam overlay off; title stopped when overlay attached.

Unity's OpenGL core backend starts at GL 3.2
<https://docs.unity3d.com/2023.2/Documentation/Manual/OpenGLCoreDetails.html>; Panfrost
reports 3.1.

What to change: nothing by default. `<appid> unity=gl` keeps Vulkan-capable title on
OpenGL; `<appid> overlay=x86` turns overlay back on for 32-bit title. `args=-force-glcore`
works too since 1.2: handler counts profile `args=` before adding its own switch.

### T5. Godot 4 on OpenGL renderer (automatic)

Handler starts Godot 4 titles with `--rendering-driver opengl3` and GL 3.3 report. Godot's
Vulkan renderer froze on splash on PanVK with Mesa 26.1.

What to change: nothing by default. `<appid> godot=vulkan` tries Vulkan renderer, for
example after Mesa upgrade or on GPU other than Mali.

### T6. Steam overlay per title

Some custom OpenGL engines stop when Steam overlay attaches; Vulkan titles need arm64
overlay to show it.

What to change: profile `<appid> overlay=off`, `overlay=vulkan` or `overlay=x86`; or
launch option `STEAM_ARM_OVERLAY=off %command%`.

### T7. Direct3D 8 through DXVK

Launcher sets `PROTON_DXVK_D3D8=1`, so Direct3D 8 titles use DXVK's `d3d8`. Proton's
default for them, wined3d on OpenGL, drew them wrong on Mali.

What to change: nothing by default. `PROTON_DXVK_D3D8=0 %command%` restores Proton's
default for one title.

### T8. Unreal Engine 4 Direct3D 11 titles stop

UE4 asks for Direct3D feature level 11_0. DXVK on PanVK offers 10_1, since PanVK has no
tessellation. Reporting tessellation as present through Vulkan layer crashed X server.
Raising DXVK's level with `d3d11.maxFeatureLevel = 11_0` in `dxvk.conf` gets engine past
its check; engine then crashes compiling geometry shader, which PanVK does not implement
(`vk-spoof` only reports it).

What to change: none on Mali. Do not spoof tessellation or raise feature level.

### T9. DXVK 2.7.1 and 3.1.1 reach same level on PanVK

Proton 11 ARM64 carries DXVK 2.7.1, Proton Experimental ARM64 carries DXVK 3.1.1. With
`vk-spoof` on, both report feature level 10_1 on PanVK and both ran same Direct3D 11
titles: 64-bit GameMaker title reached title screen, UE4 title stopped at its 11_0 check.
DXVK 3 driver notes list transform feedback as required, and PanVK has none, so result
was expected to differ; on test system it did not
<https://github.com/doitsujin/dxvk/releases>.

What to change: nothing. When title fails on one Proton ARM64 build, try other one before
reporting.

### T10. Unity HDRP titles need feature level 11_0

Unity title using HD Render Pipeline showed black screen under Proton ARM64. Its log
states that feature level 10_1 lacks compute shaders and that HDRP is unsupported there.
DXVK on PanVK offers 10_1 (T9).

What to change: none on Mali. Unity titles on built-in or Universal pipeline do not hit
this check.

### T11. PhysX install step (automatic)

Legacy PhysX installer (PhysX 9.x, msiexec) waited over 5 minutes with no window on first
start of 32-bit UE3 title under Proton ARM64. Steam decides whether to run install step
from value in title's prefix: in `pfx/system.reg`, under
`[Software\\Wow6432Node\\Valve\\Steam\\Apps\\<appid>]`, named after install script
section. Value `1` skips step only when section sets no minimum; when section sets one
(`MinimumHasRunValue`), value has to reach it, else step runs again. Proton issue 51
documents value `1` for section without minimum
<https://github.com/ValveSoftware/Proton/issues/51>. On test system value at or above
minimum made install step finish in seconds, and Steam kept value. Stopping PhysX
installer with SIGTERM also let Steam continue to title.

Launcher applies both automatically (README, PhysX install step). Title in this test then
stopped 5 seconds in with engine assertion, same with `FEX_X87REDUCEDPRECISION=0`:
separate problem, not PhysX.

What to change: nothing by default. `STEAM_ARM_PHYSX_SKIP=0` in launcher's environment
turns it off.

### T12. FEX 2609 lists container paths itself

FEX commit 71afe47 (2026-08-13, in FEX 2609) adds library paths of Steam's runtime
container to FEX's forwarding list, same paths 1.2 added to Valve's `ThunksDB.json`
<https://github.com/FEX-Emu/FEX/commit/71afe476751deac24adabd1adb575fd2337b6e0a>. With
FEX-2609 beta tool and stock `ThunksDB.json`, OpenGL and Vulkan forwarding loaded and
titles rendered on GPU. Valve's default FEX tool was still FEX-2607 at time of testing.

What to change: nothing. Launcher reads tool's `VERSIONS.txt` and edits `ThunksDB.json`
only below 2609.

### T13. `STEAM_COMPAT_FEX_CONFIG` cannot carry settings

FEX tool reads extra configuration from `STEAM_COMPAT_FEX_CONFIG`, but client always sets
it, empty when title has no per-app setting, so launch option or environment value never
reaches tool. Per-app option interface exists only on Steam Frame.

What to change: nothing. Launcher keeps its edit of tool's `ConfigTemplate.json` on
forwarding route.

### T14. Client channel with Steam Frame mode

Client started in Steam Frame mode (`-deckard`) moves itself to its own hidden ARM beta
channel on first start; client's `package/beta` file and bootstrap log name it.
`publicbeta` written into that file had no effect, so 2.0 no longer writes it and
downloads first package from stable `steam_client_linuxarm64` manifest.

What to change: nothing.

### T15. GPU drivers inside emulation (Valve's layout)

Valve's Steam Frame packages include x86 Mesa for use inside emulation: package
`deckard-mesa-linux-x86_64` in Valve's holo package repository installs it at
`/usr/share/guestos/fex-mesa`, beside x86 dependency tree, and Steam Frame's per-app
translation settings default OpenGL and Vulkan forwarding off
<https://holo-packages.steamos.cloud/archlinux-deckard-hotfixes/>. x86-64 and i386 Mesa
with Panfrost and PanVK ran under FEX on test system and drove Mali without forwarding,
including 32-bit Vulkan, which forwarding sends to CPU renderer. `gpu-in-emulation`
component uses this layout with Mesa 26.1.8. Linux titles that ran on forwarding also ran
here; 64-bit OpenGL title with vsync off started only here; 32-bit Source engine hang (T3)
stayed. 32-bit title that includes DXVK Native creates its device on Mali with 2.0 archive,
which reports DXVK and vkd3d features; that title then hangs at loading, as on OpenGL.
Proton ARM64 titles use system Vulkan, so component does not change them.

What to change: nothing for Java and 32-bit Vulkan titles; launch handler puts them on
Mali drivers in emulation. For other title that fails on forwarding, profile key `gfx=b`;
`gfx=a` returns title to forwarding.

---

## Driver facts by GPU family

### Mali: Panfrost and PanVK

#### M1. Panfrost OpenGL stops at GL 3.1

Status: researched; matches test system.

Panfrost reports GL 3.1 and GLES 3.1 on Valhall (Mali-G610 and siblings) and has no
geometry shaders <https://docs.mesa3d.org/drivers/panfrost.html>. Engines that ask for GL
3.3 or 4.x core context fail natively and need Vulkan renderer or version report (T4, T5);
Zink over PanVK reports no higher version on its own (M3).

What to change: engine rules handle Unity, Godot 4 and Godot 3. For other GL 3.2/3.3 titles see T2;
for GL 4.x titles see M3.

#### M2. PanVK Vulkan versions and conformance

Status: researched, untested beyond Mali-G610.

PanVK exposes Vulkan 1.4 on Valhall v10 and later (G310, G610, G615, G715, G720, G725, G1)
and Vulkan 1.3 on Bifrost (G72, G31, G51, G52, G76). It is conformant only on Mali-G610;
other Mali GPUs need `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` before it loads
<https://docs.mesa3d.org/drivers/panfrost.html>. Older distribution Mesa exposes lower
versions.

What to change: Mali-G610: nothing; do not set `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER`. Other
Mali: to try PanVK on one title, launch option
`PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 %command%`; expect faults. `vk-spoof` was written
against PanVK on Mali-G610 and is untested on other Mali parts.

#### M3. Zink over PanVK for OpenGL 4.x titles

Status: researched, untested here.

Zink runs OpenGL on top of PanVK, but does not reach GL 4.x there: Zink needs Vulkan
`geometryShader` for GL 3.2 and `tessellationShader` for GL 4.0
<https://docs.mesa3d.org/drivers/zink.html>, and PanVK exposes neither (M5, T8). Two posters on
Armbian community forum (topic 55217, December 2025) ran Tomb Raider (2013) through Zink on
Mali-G610, through box64 rather than FEX; their recipe reports GL 4.3 through
`MESA_GL_VERSION_OVERRIDE`, same version report trick as on Panfrost (T4, T5), so title
runs only while it avoids missing stages (inferred). Zink stacks two drivers; for titles that need GL
3.3 or less, native Panfrost is faster.

What to change: per title only, version report included. Linux x86 title, one profile line:

```
203160 env=MESA_LOADER_DRIVER_OVERRIDE=zink;GALLIUM_DRIVER=zink;LIBGL_KOPPER_DRI2=true;MESA_GL_VERSION_OVERRIDE=4.3
```

Forum recipe also sets `PAN_MESA_DEBUG=gl3`; under Zink Panfrost's GL driver is not
loaded, so that flag likely has no effect (inferred).

#### M4. Mesa version

Status: researched; test system runs 26.1.4.

- 25.2 (2025-08-06): Vulkan 1.2 and 1.3 on PanVK v10 and later; practical floor
  <https://linuxiac.com/mesa-25-2-lands-with-vulkan-1-4-on-panvk-drops-x11-dri2-support/>.
- 26.1: PanVK extension sprint aimed at DXVK and vkd3d-proton required extensions
  (conditional rendering, mutable descriptor type, memory budget, attachment feedback
  loop, shader stencil export); recommended floor for Proton titles
  <https://christian-gmeiner.info/2026-04-20-panvk-extensions/>.
- 26.2.x: further extensions; 26.2.3 (2026-09-16) is newest bugfix release at time of
  writing <https://docs.mesa3d.org/relnotes/26.2.3.html>.

What to change: check version with `glxinfo -B`. Newer Mesa for Ubuntu family comes from
kisak-mesa PPA (test system's source) or ernstp/mesarc PPA
<https://launchpad.net/~ernstp/+archive/ubuntu/mesarc>:

```
sudo add-apt-repository ppa:kisak/kisak-mesa
sudo apt update && sudo apt full-upgrade
```

Re-test `glx-lax` and `vk-spoof` titles after any Mesa change.

#### M5. No geometry shaders in PanVK

Status: researched, untested here.

DXVK maps Direct3D geometry shader stages to Vulkan geometry shaders, which PanVK lacks.
Dragon Quest XI S failed for this reason in Armbian community forum topic 55217; forum
thread tracks it as open Mesa merge request 38401. With `vk-spoof`, feature is reported
present and removed at device creation, so such title gets device and then misrenders,
crashes or hangs instead of refusing to start.

What to change: none. No setting adds geometry shaders.

#### M6. Panfrost workaround and debug flags

Status: researched, untested here.

`PAN_MESA_DEBUG` takes comma-separated flags
<https://github.com/FireBurn/mesa/blob/main/src/gallium/drivers/panfrost/pan_screen.c>:

- `nofp16`, `noafbc`, `nocrc`, `linear`: workarounds for corruption in one title; each
  costs bandwidth or speed.
- `sync`, `trace`, `dirty`, `dump`, `nocache`: diagnosis only, heavy speed cost.
- `deqp`: conformance test hacks, not for games.

`PANVK_DEBUG` flags (`sync`, `trace`, `force_blackhole` and others) are diagnostic only
<https://github.com/FireBurn/mesa/blob/main/src/panfrost/vulkan/panvk_instance.c>.

What to change: launch option `PAN_MESA_DEBUG=noafbc %command%` (or other workaround flag)
for title with corruption; remove after test if it changes nothing.

#### M7. Frame counters without MangoHud

Status: researched, untested here.

`GALLIUM_HUD=simple,fps` draws frame rate in OpenGL titles on any Gallium driver.
`VK_LOADER_LAYERS_ENABLE=*mesa_overlay*` loads Mesa's Vulkan overlay layer;
`VK_INSTANCE_LAYERS` form is deprecated <https://docs.mesa3d.org/envvars.html>.

What to change: launch option `GALLIUM_HUD=simple,fps %command%` for OpenGL titles. Vulkan
layer under Proton is untested; on test system MangoHud and arm64 overlay layer each
crashed Proton titles at device creation, so try Mesa layer on Linux Vulkan titles first.


#### M8. Direct3D 12 and vkd3d-proton on PanVK

Status: device features checked with `vulkaninfo` on test system and in vkd3d-proton
source; no Direct3D 12 title run.

vkd3d-proton refuses to create device without `VK_EXT_transform_feedback`,
`robustBufferAccess2` and `robustImageAccess2`
<https://github.com/HansKristian-Work/vkd3d-proton/blob/master/libs/vkd3d/device.c>. PanVK
on Mali-G610 exposes none of them. Even with them present, missing
`vertexPipelineStoresAndAtomics` and `sparseResidencyAliased` cap feature level at 11_0,
and `denormBehaviorIndependence` none caps Shader Model at 6.0. Unreal Engine 5 titles
fall under same limits (E2).

Open Mesa merge requests cover geometry shaders (38401, 44118), transform feedback (43359)
and clip and cull distance (40343, 43156); none covers tessellation, and none has merge
date <https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43359>.

What to change: none. Direct3D 12 titles do not run on Mali.

### Adreno: Turnip

#### A1. Turnip Vulkan level

Status: researched, untested.

Turnip is Vulkan 1.3 on Adreno 6xx, which meets DXVK 2.x API baseline, and supports Adreno
7xx; A750 is main development target, with 600+ game frames from Direct3D 8 to 12, Vulkan
and OpenGL replayed nightly <https://docs.mesa3d.org/drivers/freedreno.html>
<https://blogs.igalia.com/dpiliaiev/turnip-my-5y-retrospective/>. Low-end Adreno 6xx parts
may lack some feature level pieces.

What to change: none at install; GPU family detection leaves `vk-spoof` off on Adreno, and Turnip exposes features that layer reports.
`glx-lax` applies (Mesa).

#### A2. Unreal Engine 5 Direct3D 12 titles need vkd3d-proton fix

Status: researched, untested.

UE5 Direct3D 12 titles did not work correctly under vkd3d-proton on Adreno because of
Adreno's wave128 subgroup size. vkd3d-proton pull request 3265, "Avoid wave128 on Turnip",
merged 2026-09-03, works around it
<https://blogs.igalia.com/dpiliaiev/turnip-my-5y-retrospective/>. Fix is in vkd3d-proton,
not Mesa.

What to change: in Properties, Compatibility, pick newest ARM64 Proton build; builds made
before 2026-09-03 lack fix.

#### A3. Per-title Turnip fixes need Mesa 23.0 or newer

Status: researched, untested.

Psychonauts 2 (main menu artifacts, merge request 20533), Injustice 2 (main menu NaN
corruption, 20396) and Monster Hunter: World (main menu misrender, 20099 and 20100) were
fixed in Mesa around 23.0; no environment variable works around them
<https://blogs.igalia.com/dpiliaiev/turnips-in-the-wild-part-3/>.

What to change: Mesa 23.0 or newer.

### Apple M-series: Asahi

#### AS1. Conformant Vulkan and OpenGL

Status: researched, untested.

Honeykrisp is conformant Vulkan 1.3 with no portability waivers; AGX OpenGL driver is
conformant GL 4.6 and GLES 3.2 <https://asahilinux.org/2024/06/vk13-on-the-m1-in-1-month/>
<https://asahilinux.org/2024/02/conformant-gl46-on-the-m1/>. Conformance says nothing
about speed or optional extensions.

What to change: none at install; GPU family detection leaves `vk-spoof` off on `apple-agx`. Handler's Unity and Godot rules target
Panfrost's GL 3.1; on Asahi `<appid> godot=vulkan` restores Godot 4's own Vulkan renderer and
leaves Godot 3 at its own GL request (inferred, untested).

#### AS2. Geometry shaders and tessellation emulated

Status: researched, untested.

Apple GPUs have no hardware geometry shaders, tessellation or transform feedback; Asahi
emulates all three with compute shaders, at speed cost. Titles shown running: Witcher 3,
Ghostrunner, Control, Cyberpunk 2077, Fallout 4, Hollow Knight, Portal 2. Newer AAA titles
did not reach 60 fps <https://asahilinux.org/2024/10/aaa-gaming-on-asahi-linux/>.

What to change: none.

#### AS3. Direct3D 12 and 32-bit DXVK

Status: researched, untested.

Sparse binding completed requirements for Direct3D feature level 12_0 through vkd3d-proton
(March 2025) <https://asahilinux.org/2025/03/progress-report-6-14/>. Mesa 25.2 added
`VK_EXT_map_memory_placed`, which Wine needs to forward 32-bit DXVK; GPU acceleration of
32-bit Windows titles depends on it
<https://asahilinux.org/2025/08/progress-report-6-16/>.

What to change: Mesa 25.2 or newer and current FEX root filesystem.

#### AS4. 16K pages: Steam inside muvm

Status: researched, untested.

FEX needs 4K pages. Asahi runs FEX and Steam inside muvm, microVM with 4K page guest
kernel; GPU reaches guest through DRM native context, slightly slower than native, most
for workloads that poll for GPU completion
<https://asahilinux.org/2024/12/muvm-x11-bridging/>. This installer does not set up muvm;
on 16K kernel setup stops.

What to change: install inside 4K page environment set up by distribution, such as muvm.
`STEAM_ARM_IGNORE_PAGESIZE=1` skips page size check on non-4K host kernel; use it only when
x86 side runs inside separate 4K page guest that check cannot see. On 16K host without such
guest, emulation fails.

#### AS5. Community launch options from Asahi scripts

Status: researched, weak (one enthusiast's scripts, not verified).

Community runner scripts set `FEX_X87REDUCEDPRECISION=1` for speed
<https://github.com/Rouzihiro/Gaming_on_Linux/blob/main/Asahi-Fedora/Turtle.WoW/runner.sh>
and `PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1` for compatibility:

```
<https://github.com/Rouzihiro/Gaming_on_Linux/blob/main/Asahi-Fedora/WoW.Epoch/epoch_proton>
```

What to change: per title only, as launch options; see F3 for X87 trade.

### Raspberry Pi 5: v3dv

#### P1. No verified data

Status: no claim survived verification.

Research found no verified v3dv Vulkan version, geometry or tessellation support, DXVK
feature level, or Steam title result with 4K `kernel8.img`. Page size handling is in
`COMPATIBILITY.md`.

What to change: keep `page-size` component selected; report results.

### Discrete GPUs on ARM hosts

#### D1. No verified data

Status: no claim survived verification.

Research found no verified result for ARM servers or workstations with AMD or NVIDIA
cards: no DXVK or vkd3d-proton feature level, no PCIe or firmware quirk list.

What to change: none at install; GPU family detection leaves `vk-spoof` off on AMD, NVIDIA
and Intel, and `glx-lax` off on NVIDIA's own driver. Check `getconf PAGESIZE`; some server kernels use
64K pages.

---

## FEX settings per title

### F1. How to set FEX options per title

Status: researched, untested.

Every FEX option has environment variable `FEX_<OPTION>`, option name in capitals
(`X87ReducedPrecision` becomes `FEX_X87REDUCEDPRECISION`). Environment beats every JSON
file. User AppConfig files, matched on program name, sit in
`~/.fex-emu/AppConfig/<program>.json` or
`~/.fex-emu/AppConfig/Steam_<appid>_<program>.json`
<https://wiki.fex-emu.com/index.php/Config>. Upstream FEX includes no per-game fixes: its
AppConfig folder holds only `client.json` and `steamwebhelper.json`
<https://github.com/FEX-Emu/FEX/tree/main/Data/AppConfig>.

What to change:

- Linux x86 title: profile line `<appid> env=FEX_<OPTION>=<value>`.
- Windows title under Proton: launch option `FEX_<OPTION>=<value> %command%`.
- JSON, only where no variable exists (graphics forwarding, F8):

```
{"Config": {"X87ReducedPrecision": "0"}}
```

Whether Valve's FEX reads AppConfig inside Steam's runtime container is not verified.

### F2. PlayStation PC SDK titles: `FEX_X87REDUCEDPRECISION=0`

Status: researched; confirmed by FEX maintainers, untested here.

Stellar Blade (3489700) under ARM64 Proton crashed about 43 s after launch with access
violation in `VCRUNTIME140.dll` while X87ReducedPrecision was on. Setting it off reached
gameplay; reporter tested on two ARM64 Proton builds with Adreno 830, Mesa 26.2.2
<https://github.com/FEX-Emu/FEX/issues/5988>. Schema default is off, so ARM64 Proton's FEX
setup turns it on (inferred). FEX maintainers closed issue as class issue: recent titles
built on PlayStation PC SDK need full x87 precision. Until Dawn, Horizon Zero Dawn
Remastered and Marvel's Spider-Man 2 continue with full precision; God of War Ragnarök
still crashes with full precision (FEX #4556 open)
<https://github.com/FEX-Emu/FEX/issues/4556>,
<https://wiki.fex-emu.com/index.php/Stellar_Blade%E2%84%A2>.

What to change: launch option, for Stellar Blade, Until Dawn, Horizon Zero Dawn Remastered
and Spider-Man 2:

```
FEX_X87REDUCEDPRECISION=0 %command%
```

### F3. X87ReducedPrecision on: speed for accuracy

Status: researched, untested.

Option computes x87 floating point at 64 instead of 80 bits; schema describes on as "may
result in rendering bugs"; default off <https://wiki.fex-emu.com/index.php/Config>. F2
shows opposite need in another title.

What to change: per title trial only: `<appid> env=FEX_X87REDUCEDPRECISION=1`, or launch
option. Revert on crash or misrender.

### F4. TSOEnabled: leave on

Status: researched, untested.

TSO emulation is on by default; schema says turning it off is "highly likely to break any
multithreaded application". Not safe as global setting.

What to change: nothing. Per title experiment only: `FEX_TSOENABLED=0 %command%`.

Source for F3 and F4 descriptions:

```
<https://raw.githubusercontent.com/FEX-Emu/FEX/main/FEXCore/Source/Interface/Config/Config.json.in>
```

### F5. Metal Gear Rising: Revengeance: Multiblock and X87 combination

Status: researched, fixed upstream, untested here.

32-bit title (235460) crashed at title screen only with Multiblock on and
X87ReducedPrecision off together; other three combinations worked
<https://github.com/FEX-Emu/FEX/issues/4486>. Cause was ARM64 branch range in large JIT
blocks: FEX #4538 hid it, FEX #5024 (recovering from branch encoding failures, November
2025) fixed it, and issue closed.

What to change: current FEX, nothing else. On FEX older than November 2025: launch option
`FEX_MULTIBLOCK=0 %command%` or `FEX_X87REDUCEDPRECISION=1 %command%`, not both.

### F6. SMCChecks for self-modifying code

Status: researched, untested.

`SMCChecks` takes `none`, `mtrack` (default) or `full` (checks code before every run,
slow). Suspected use: titles with their own JIT, such as Mono (see N1).

What to change: per title trial: `<appid> env=FEX_SMCCHECKS=full`.

### F7. Java titles: G1 collector, not ZGC

Status: researched; confirmed 2-1, single reproducer, no game tested.

x86-64 HotSpot with ZGC under FEX corrupts object fields or segfaults. `-XX:+UseG1GC` or
`-Xint` (interpreter only) run correctly; G1 is HotSpot default and only workaround fast
enough for games <https://github.com/FEX-Emu/FEX/issues/5813>. Titles that do not force
`-XX:+UseZGC` are not affected.

What to change: remove `-XX:+UseZGC` from title's JVM options, in its launch script or
config file. Steam file verification can restore original file.

### F8. 32-bit OpenGL forwarding breaks many titles

Status: researched, confirmed 2-1; forwarding off tested on T3 title (did not help there).

FEX's lead developer tested 32-bit X11 GL forwarding: about 12 titles worked, about 28
crashed or hung, several Source engine titles among them; issue argues against
turning it on by default <https://github.com/FEX-Emu/FEX/issues/4645>. Title-by-title
lists from that issue failed verification.

What to change: profile line `<appid> gl32=off` (1.2) runs 32-bit title on emulated x86
Mesa, without forwarding; slower. Per-program file below is unverified: Valve's FEX tool
keeps its configuration under title's compatibility data folder, and whether it reads
this path is not confirmed:

```
~/.fex-emu/AppConfig/Steam_<appid>_<program>.json
{"ThunksDB": {"GL": 0}}
```

---

## Engine notes

### E1. Unity

Status: rules tested (T4); options below researched.

Unity player switches: `-force-vulkan`, `-force-glcore`, `-force-glcoreXY` with XY from 32
to 45, `-force-clamped` (skips extra extension checks); no switch below GL 3.2
<https://docs.unity3d.com/6000.0/Documentation/Manual/PlayerCommandLineArguments.html>.
Compute shaders need GL 4.2 in Unity's OpenGL backend
<https://docs.unity3d.com/2023.2/Documentation/Manual/OpenGLCoreDetails.html>. Hollow
Knight switched its Linux default to Vulkan in its Unity 2020.2 update:

<https://www.gamingonlinux.com/2021/02/team-cherry-upgrade-the-excellent-hollow-knight-with-vulkan-for-linux/>

What to change: renderer through `unity=vulkan` or `unity=gl` profile key, or
`args=-force-glcore` (T4). Example for Vulkan title that misrenders: `367520 unity=gl`.

Windows Unity titles on HD Render Pipeline need feature level 11_0 and do not run on Mali
(T10).

### E2. Unreal Engine 4 and 5

Status: UE4 Direct3D 11 limit tested (T8); rest researched.

- UE4 Direct3D 11 renderer needs feature level 11_0 and Shader Model 5. On Mali it stops
  (T8).
- UE5 Nanite and Lumen need Shader Model 6; Nanite needs Direct3D 12 with 6.6 atomics or
  Vulkan `VK_KHR_shader_atomic_int64`, whichever renderer runs. UE5 Direct3D 12 titles
  fail on Mali before that, at vkd3d-proton device creation (M8).
- UE5 Direct3D 12 on Adreno: A2. Asahi reaches feature level 12_0: AS3.
- Native Linux UE4 and UE5 builds already render through Vulkan; their Shader Model 5 path
  needs tessellation too (inferred from T8).

Sources:

```
<https://dev.epicgames.com/documentation/unreal-engine/hardware-and-software-specifications-for-unreal-engine?lang=en-US>
<https://forums.unrealengine.com/t/a-d3d11-compatible-gpu-feature-level-11-0-shader-model-5-0-is-required-to-run-the-engine/2272322>
```

What to change: none on Mali. On Adreno, Asahi or discrete GPUs: newest ARM64 Proton
(detection leaves `vk-spoof` off there).

### E3. Source (Source 1)

Status: T1 and T3 tested; rest researched.

Native Linux Source builds render OpenGL through Valve's ToGL layer. Newer builds add
opt-in `-vulkan` through DXVK Native. Reported problems with it on desktop GPUs: monitor
set to 24 Hz, worked around with `-freq 120` or `-freq 144`
<https://github.com/ValveSoftware/Source-1-Games/issues/7778>; crash on start with Mesa
25.3.1 <https://github.com/ValveSoftware/Source-1-Games/issues/7783>; props that vanish in
Left 4 Dead 2. FEX wiki reports Portal's native build crashing on level load unless run
with Vulkan <https://wiki.fex-emu.com/index.php/Portal>.

What to change:

- 64-bit Source build: `<appid> args=-vulkan`, adding `;-freq;120` if screen drops to 24
  Hz (`args=-vulkan;-freq;120`).
- 32-bit Source build: no `-vulkan` (T1). OpenGL title that needs GL 3.2 or 3.3:
  `<appid> env=PAN_MESA_DEBUG=gl3` (T2). If it hangs as in T3, Windows build under Proton.

### E4. Source 2

Status: researched, untested.

Source 2 is Vulkan only, with no OpenGL fallback. Counter-Strike 2 lists AMD GCN or NVIDIA
Kepler as floor <https://www.phoronix.com/news/Counter-Strike-2-Linux> and reports Vulkan
1.2 errors on weaker drivers
<https://github.com/ValveSoftware/csgo-osx-linux/issues/3772>. No report was found of
Source 2 running on Mali or other mobile Vulkan driver.

What to change: none. Counter-Strike 2 (730) is free to install; report result.

### E5. Godot

Status: Godot 4 rule tested (T5); Godot 3 GL 3.3 report tested as profile in 2.1, automatic
rule not run on device; rest researched.

Godot 4 has three renderers: Forward+ and Mobile on Vulkan, Compatibility on OpenGL
<https://docs.godotengine.org/en/4.4/tutorials/rendering/renderers.html>. Project setting
`renderer/rendering_method="gl_compatibility"` selects Compatibility
<https://godotengine.org/article/status-of-opengl-renderer/>. Godot's GPU detection can
fall back to llvmpipe on Panfrost class hardware while other programs use GPU
<https://github.com/godotengine/godot/issues/50469>. Godot 3 titles stop at start on
Panfrost's GL 3.1 (`GLXBadFBConfig`); handler sets GL 3.3 and GLSL 330 report for them
(GAMES.md, Godot 3 row). Engine version comes from PCK embedded in executable, else `.pck`
beside it, in Godot's own pack order. Windows builds under x86 Proton keep Godot defaults;
A/B run with Windows Godot 4 title not done.

What to change: `<appid> godot=vulkan` or `godot=gl`. Check handler log and frame rate for
silent software rendering.

### E6. Java

Status: researched, untested.

Linux Java titles under FEX run x86 JVM with x86 native libraries, so missing ARM64 LWJGL
natives do not matter here. Garbage collector matters: F7.

What to change: see F7.

---

## Known not-fixes

Titles below have no known fix; settings listed were tried and did not help. Status:
researched unless marked.

### N1. `Slay the Spire 2`

Native Linux Godot 4 Mono build crashes with access violation during menu asset preload on
Adreno 740. `FEX_TSOENABLED=1`, with or without `FEX_PARANOIDTSO=1`, did not help;
`taskset` core pinning only moved crash point. Reporter suspects clash between FEX
self-modifying code tracking and Mono's JIT <https://github.com/FEX-Emu/FEX/issues/5991>.

What to change: none known; `FEX_SMCCHECKS=full` (F6) is untested guess.

### N2. 32-bit Source engine title, native build (tested)

See T3: GL variants, overlay off, MangoHud off and GLX vendor did not help.

### N3. Geometry shader titles on PanVK

See M5. No setting helps.

### N4. Unreal Engine 4 Direct3D 11 titles on PanVK (tested)

See T8. Tessellation spoof crashed X server; raised feature level crashed engine.

### N5. Valheim dedicated server

Unity headless server segfaults every few hours under FEX on Neoverse-N1 server, inside
FEX syscall passthrough; issue open, low confidence
<https://github.com/FEX-Emu/FEX/issues/5985>.

What to change: none known.

### N6. 32-bit Unreal Engine 3 title under Proton ARM64 (tested)

See T11. PhysX install step skipped; title stops 5 seconds in with engine assertion.
`FEX_X87REDUCEDPRECISION=0` did not help.

---

## Refuted advice

Do not try these. Each failed verification or conflicts with test results.

- **UE4 `-vulkan` as feature level 11_0 bypass on Mali.** UE4's Vulkan Shader Model 5 path
  also needs tessellation, which PanVK lacks (T8).
- **`d3d11.maxFeatureLevel = 11_0` in `dxvk.conf` for UE4 on Mali.** Tested: engine passes
  its check, then crashes compiling geometry shader (T8).
- **`publicbeta` in client's `package/beta` with Steam Frame mode.** Tested: client moves
  to its own ARM channel regardless (T14).
- **`STEAM_COMPAT_FEX_CONFIG` as launch option.** Tested: client overwrites it (T13).
- **`R600_DEBUG=mono`.** Variable of AMD r600 driver; no effect on Panfrost, PanVK, Turnip
  or Asahi.
- **`DXVK_ASYNC=1` or unsetting `DXVK_ASYNC`.** Sources disagree; upstream DXVK ignores
  it, only async forks read it.
- **`FEX_PARANOIDTSO`, `SMCLazyInval`.** Not FEX options; FEX schema has neither
  <https://wiki.fex-emu.com/index.php/Config>. Nearest options are `TSOEnabled` and
  `SMCChecks`.
- **Multiblock off as documented stutter fix.** Refuted 0-3; FEX schema does not say that.
  Multiblock off costs speed (F5 was title-specific crash, not stutter, fixed upstream).
- **Portal 2 native build crash under FEX and Proton as its workaround.** Both refuted 0-3
  <https://github.com/FEX-Emu/FEX/issues/3807>.
- **`PAN_MESA_DEBUG=gofaster`.** Belongs to old panfork fork; mainline Mesa flag table has
  no such flag.
- **`PAN_MESA_DEBUG=gles3`.** No such flag in Mesa source.
- **Frame rates from box64 issue 3593 as Mali data.** Poster measured with AMD RX 470 over
  PCIe, not Mali <https://github.com/ptitSeb/box64/issues/3593>. Unity FEX versus box64
  frame rates attributed to that issue were refuted 0-3.
- **Title lists of working and broken 32-bit GL forwarding.** Refuted 1-2; only overall
  counts in F8 held.
- **Stellar Blade: "no other FEX setting helps".** Refuted 0-3; F2 fix itself holds.
- **`Slay the Spire 2`: "renderer switch did not help, so not GPU related".** Refuted 0-3.
- **Freedreno reaching desktop GL 4.5 on Adreno.** Refuted 0-3
  <https://docs.mesa3d.org/drivers/freedreno.html>; OpenGL engines on Adreno unverified.
- **UE5 wave128 problem blamed on old Mesa.** Refuted 0-3; fix is in vkd3d-proton (A2).
- **Turnip needing driver-side handling for Execute Indirect Tier 1.1 misuse.** Refuted
  0-3.
- **DXVK and vkd3d-proton not yet running on Honeykrisp in June 2024.** Refuted 1-2.
- **Counter-Strike 2 dedicated server segfault under FEX on Neoverse-N1.** Refuted 1-2
  <https://github.com/FEX-Emu/FEX/issues/4568>.
- **Unity `A Short Hike` freezing under box64 on Mali-G52 class hardware.** Refuted 1-2
  <https://github.com/ptitSeb/box64/issues/1252>.

---

## Popular-game survey

Status: survey of public compatibility data, September 2026; no title in it was run for
this survey.

568 popular Steam titles were sorted by Steam Deck compatibility data, engine and graphics
API. Steam Frame ratings gave little: 543 of 568 were unknown.

- Direct3D 12 is largest gap: 119 titles use it only and 45 more offer it beside other
  API, most of them Unreal Engine 5. None of Direct3D 12 path runs on Mali (M8).
- Unreal Engine 4: 43 titles, blocked by tessellation (T8).
- Kernel-level anti-cheat: 19 titles left out.
- Unity: 110 titles, largest engine, mostly Direct3D 11, which runs at 10_1 unless title
  uses HDRP (T10).

What to change: use Steam Deck rating over Steam Frame rating for now, and check engine
and graphics API of title before relying on it for Mali.

---

## Reporting results

Use compatibility report form in project's GitHub issue tracker. Useful fields for items
in this document:

- Item number from this document (for example F2 or M3) and exact setting used.
- Result: starts, renders on GPU, playable, or failure mode.
- Output of:

```
glxinfo -B | grep -i "renderer string\|version string"
vulkaninfo --summary | grep -i "driverName\|driverInfo\|deviceName"
getconf PAGESIZE
```

- Launch handler log for Linux x86 titles: `/tmp/fex-compat-tool-<pid>.log`.

---

## Disclaimer

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
