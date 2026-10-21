# Compatibility

## Requirements

Confirmed by inspection of installer:

- ARM64 system.
- Debian or Ubuntu family distribution, since installer uses `apt`. Setup halts before any
  change without `apt-get`, `apt-cache`, `dpkg` or package architecture `arm64`.
- Ubuntu 25.10 or newer, Debian 13 or newer, or distribution built on them: Ubuntu 24.04
  and Debian 12 lack SDL3 packages client needs. Setup checks host packages with
  `apt-cache policy` before any package or package source change.
- Mesa graphics stack.

FEX, emulation tool used for x86 game code, installs from FEX's Ubuntu PPA `ppa:fex-emu/fex`. Ubuntu family distribution is tested path for that step. On Debian 13 and Raspberry Pi OS built on it, setup adds same PPA as plain apt source with its Ubuntu 24.04 build (see Debian systems).

Installer has no hardcoded GPU render node and no hardcoded card index. GPU family detection reads every render node and sets component defaults per family (see GPU families). Page size check names fix for Raspberry Pi; on Apple Silicon it stops (16K page kernel not supported).

Vulkan driver is needed for Windows titles; GPUs without one run native OpenGL titles.

Native ARM64 client needs Armv8.1 or newer CPU with LSE atomics; on Armv8.0 cores
(Cortex-A53, A57, A72, A73) setup installs Valve's x86 client through emulation instead.
See `README.md`, Requirements and x86 client.

## Before you install

`bash steam-arm-install.sh --detect` prints GPU family, kernel driver, Vulkan driver, page
size, distribution and component defaults for this system; it installs nothing and needs
no root. Five checks below cover same ground by hand. Run them on desktop session;
`glxinfo` comes from `mesa-utils` and `vulkaninfo` from `vulkan-tools`.

```
bash steam-arm-install.sh --detect          # GPU family and defaults
lsmod | grep -w panthor                     # open Mali kernel driver loaded
glxinfo -B | grep -i "renderer string"      # OpenGL renderer
vulkaninfo --summary | grep -i "driverName\|deviceName"
grep -E "^ID=|VERSION_CODENAME" /etc/os-release
getconf PAGESIZE
```

Output on test device, RK3588 board with Mali-G610 GPU (family `mali-csf-v10`):

| Check           | Tested device                                | What other result means                                               |
|-----------------|----------------------------------------------|-----------------------------------------------------------------------|
| `panthor`       | loaded                                       | not loaded: image uses vendor blob or older kernel; untested here     |
| OpenGL renderer | `Mali-G610 MC4 (Panfrost)`, Mesa 26.1.4      | `llvmpipe`: no GPU acceleration; titles run on CPU or not at all      |
| Vulkan driver   | `panvk`, device `Mali-G610 MC4`, Mesa 26.1.4 | no Vulkan device: titles built for Linux only, no Windows titles      |
| Distribution    | `ubuntu`, `resolute`                         | `debian`, `trixie`: PPA added as apt source; older Debian, see below  |
| Page size       | `4096`                                       | `16384` or `65536`: setup halts and names fix, see Raspberry Pi below |

Mesa on tested device comes from `kisak-mesa` PPA. Older Mesa releases carry earlier
PanVK; when `vulkaninfo` lists no `panvk` device on Mali-G610, newer Mesa from that PPA
is route tested device uses.

Mesa 26.1 or newer is recommended: tested device runs 26.1, and 26.1 added PanVK
extensions that DXVK uses (`RESEARCH.md`, M4). Installer does not check Mesa version.
`gpu-in-emulation` component, on by default on Mali GPUs, brings its own x86 Mesa 26.1.8 for titles
launch handler puts on Mali drivers in emulation (Java, 32-bit Vulkan); other titles and
Windows titles use system Mesa.

Board whose five results match first column matches tested device in every property
installer depends on. That makes it expected to work, and still untested until someone
reports it.

## Armbian on RK3588 boards

Rock 5B, Orange Pi 5, NanoPi R6 and other RK3588 boards carry same Mali-G610 as tested
device. On Armbian, three choices at download time decide result:

- **Kernel branch.** `current` and `edge` branches are mainline kernels, and mainline has
  carried Panthor since Linux 6.10. `vendor` branch is Rockchip's 6.1 kernel; whether it
  has Panthor depends on build, so check with `lsmod` above.
- **Userland.** Ubuntu based images fit installer's tested path. Debian 13 (trixie) based
  images get FEX PPA as plain apt source (see Debian systems); Debian 12 based images lack
  SDL3 packages client needs, and setup halts there before any change.
- **Mesa.** Image's stock Mesa may predate PanVK support in use here; `vulkaninfo` check
  above shows it.

Reports from these boards are welcome.

## GPU families

Installer picks GPU family from kernel driver, Mali GPU id, device tree and PCI vendor;
`--detect` prints it, `GPU_FAMILY=id` sets it by hand (kept for later runs,
`GPU_FAMILY=auto` detects again). Family sets default state of three components; all
other components retain their own defaults. Detection method and family notes: `README.md`,
GPU detection.

| Family                                                | GPU                             | `vk-spoof` | `gpu-in-emulation` | `glx-lax` | Status   | Note                                                                                            |
|-------------------------------------------------------|---------------------------------|------------|--------------------|-----------|----------|-------------------------------------------------------------------------------------------------|
| `mali-csf-v10`                                        | Mali-G610, G310 (Panthor)       | on         | on                 | on        | tested   | test device (RK3588)                                                                            |
| `mali-csf-v11`                                        | Mali-G615, G715 (Panthor)       | off        | on                 | on        | untested | PanVK loads only with `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`                                     |
| `mali-csf-5thgen`                                     | Mali-G720, G725 class (Panthor) | off        | on                 | on        | untested | PanVK loads only with `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`                                     |
| `mali-csf-g1`                                         | Mali-G1 (Panthor)               | off        | off                | on        | untested | needs Mesa 26.2 or newer; published driver archive (Mesa 26.1.8) does not cover it              |
| `mali-csf`                                            | other Panthor Malis             | off        | off                | on        | untested | Mali model not in this table; titles run through forwarding                                     |
| `mali-valhall-jm`                                     | Mali-G57, G77, G78 (Panfrost)   | off        | on                 | on        | untested | no default Vulkan driver: native OpenGL titles; Windows titles unlikely                         |
| `mali-bifrost`                                        | Mali-G31, G52, G76 (Panfrost)   | off        | on                 | on        | untested | same as above                                                                                   |
| `mali-midgard`                                        | Mali-T600 to T880 (Panfrost)    | off        | on                 | on        | untested | same as above                                                                                   |
| `mali-panfrost`                                       | other Panfrost Mali models      | off        | on                 | on        | untested | same as above                                                                                   |
| `mali-utgard`                                         | Mali-400, 450 (Lima)            | off        | off                | on        | untested | not suitable for Steam games                                                                    |
| `mali-kbase`                                          | Mali on closed `kbase` driver   | off        | off                | off       | untested | warning: install needs Mesa's Panfrost or Panthor kernel driver                                 |
| `adreno-a8xx`, `adreno-a7xx`, `adreno-a6xx`, `adreno` | Adreno 6xx to 8xx (msm)         | off        | off                | on        | untested | Windows titles through DXVK expected to work; x86 Adreno drivers for 32-bit titles not included |
| `adreno-a702`                                         | Adreno 702                      | off        | off                | on        | untested | Vulkan too limited for most Windows titles                                                      |
| `adreno-legacy`                                       | Adreno 5xx and older            | off        | off                | on        | untested | no Vulkan driver; native OpenGL titles only                                                     |
| `apple-agx`                                           | Apple GPU (Asahi)               | off        | off                | on        | untested | not supported on 16K page kernel; setup does not set up `muvm`                                  |
| `broadcom-v3d71`, `broadcom-v3d42`                    | Raspberry Pi 5, 4               | off        | off                | on        | untested | OpenGL 3.1; Windows titles through WineD3D, not DXVK; Pi 4: x86 client through emulation, `PLATFORM=pi4` |
| `broadcom-vc4`                                        | Raspberry Pi 0 to 3             | off        | off                | on        | untested | not supported                                                                                   |
| `vivante`                                             | Vivante (etnaviv)               | off        | off                | on        | untested | no Vulkan driver; most titles do not run                                                        |
| `img-powervr`                                         | PowerVR                         | off        | off                | off       | untested | Vulkan driver in development; OpenGL through Zink                                               |
| `amd-radv`                                            | AMD (amdgpu)                    | off        | off                | on        | untested | forwarding covers it; x86 root filesystem's Mesa has its drivers too                            |
| `amd-radeon`                                          | AMD, older cards (radeon)       | off        | off                | on        | untested | OpenGL only, too old for most titles                                                            |
| `nvidia-nouveau`                                      | NVIDIA (nouveau)                | off        | off                | on        | untested | forwarding covers it                                                                            |
| `nvidia-prop`                                         | NVIDIA driver                   | off        | off                | off       | untested | `glx-lax` not applicable                                                                        |
| `intel`                                               | Intel (i915, xe)                | off        | off                | on        | untested | forwarding covers it                                                                            |
| `virtio-gpu`                                          | virtual machine                 | off        | off                | on        | untested |                                                                                                 |
| `none`                                                | no GPU driver                   | off        | off                | on        | untested | warning: software rendering only                                                                |
| `unknown`                                             | driver not in this list         | off        | off                | on        | untested | safe defaults                                                                                   |

Mali drivers route in launch handler applies to Mali families only, `mali-csf-g1`
excluded; 32-bit Vulkan titles switch to it on `mali-csf-v10` only, since PanVK loads by
default only there <https://docs.mesa3d.org/drivers/panfrost.html>. On other families
those titles lose `-vulkan` unless profile says `vk32=keep`.

## Component scope

| Component                                                 | Scope         | Note                                                                                                       |
|-----------------------------------------------------------|---------------|------------------------------------------------------------------------------------------------------------|
| `glx-lax`                                                 | Mesa specific | Addresses Mesa client library limit with titles that bind one OpenGL context from several threads.         |
| `vk-spoof`                                                | Mali specific | Written for PanVK Vulkan driver on Mali; on by default on Mali-G610 class only.                            |
| `gpu-in-emulation`                                        | Mali specific | Published archive: Panfrost and PanVK only; on by default on Mali GPUs. Custom archive: route set by hand. |
| `shader-cache`                                            | Generic       | Off by default. Steam's shader pre-caching; in-game videos of Windows titles; several GB of download.      |
| `physx-skip`                                              | Generic       | On by default. Marks PhysX install step of Windows titles done; off removes no files.                      |
| `map-count`                                               | Generic       | Raises `vm.max_map_count`; applies to any Linux system running Proton.                                     |
| `xpad-dedup`                                              | Generic       | Applies to any system where kernel exposes duplicate joystick node for pad.                                |
| `pad-hidraw`                                              | Generic       | Valve's `steam-devices` rules and pads from kernel `xpad` list; any udev system.                           |
| `pad-xbox`                                                | Generic       | Applies to any XInput pad from maker other than Microsoft.                                                 |
| `desktop`                                                 | Generic       | Application menu entry and window rule (KDE Plasma 6 or 5); no hardware dependency.                        |
| `desktop-mode`, `icon-bigpicture`, `icon-desktop`, `tray` | Generic       | Menu entry, desktop icons and tray icon; no hardware dependency.                                           |
| `page-size`                                               | Raspberry Pi  | Selects 4K page kernel in firmware `config.txt`; listed only on Pi 5 class or Pi without 4K pages.         |
| `kde-input-prompt`                                        | KDE Plasma    | Off by default. Pre-authorises input from X11 programs on Plasma Wayland; any X11 program may send input.  |

## Known to work

Test device: RK3588 board with Mali-G610 GPU (GPU family `mali-csf-v10`).

## Not supported on Mali-G610

Title classes below do not run on tested device, and no setting in this installer changes
that. Each depends on PanVK features that have no release date; no timeline is given here.

- **Direct3D 12 titles (vkd3d-proton).** vkd3d-proton needs `VK_EXT_transform_feedback`,
  `robustBufferAccess2` and `robustImageAccess2` to create device; PanVK exposes none of
  them. With those forced, ceiling would still be feature level 11_0 and Shader Model 6.0
  (no `vertexPipelineStoresAndAtomics`, no `sparseResidencyAliased`,
  `denormBehaviorIndependence` none).
- **Unreal Engine 5 titles.** They render through Direct3D 12 or Shader Model 6; same
  limits.
- **Unreal Engine 4 Direct3D 11 titles.** Engine asks for feature level 11_0, which needs
  tessellation; PanVK has none. DXVK offers 10_1. Raising level in `dxvk.conf` crashes
  engine when it compiles geometry shader; reporting tessellation through Vulkan layer
  crashed X server.
- **Unity HDRP titles (Direct3D 11).** HDRP needs compute shaders, which Unity enables from
  feature level 11_0; at 10_1 title shows black screen.
- **Titles with kernel-level anti-cheat.** Anti-cheat and DRM components need system call
  filter emulator does not implement.

Direct3D 11 titles that accept feature level 10_1 run. Proton 11 ARM64 (DXVK 2.7.1) and
Proton Experimental ARM64 (DXVK 3.1.1) both reach 10_1 on PanVK; results in `GAMES.md`.

Vulkan features PanVK does not expose on Mali-G610 (Mesa 26.1): geometry shader,
tessellation, transform feedback, `fillModeNonSolid`, `multiViewport`, clip and cull
distance, `robustBufferAccess2`, `robustImageAccess2`. `vk-spoof` reports geometry shader,
`fillModeNonSolid`, `multiViewport`, clip and cull distance and `robustBufferAccess2` to
DXVK and removes them again at device creation; titles that use them in rendering still
fail.

## Untested

- GE-Proton ARM64 builds (optional, Maintenance, GE-Proton (ARM64)) on Mali and V3D GPUs.
- Other RK3588 boards with Mali-G610 GPU (for example Rock 5B, Orange Pi 5, NanoPi, and other Radxa boards): same GPU family as test device.
- Boards with different SoC or GPU; defaults per family in GPU families.
- Debian family distributions outside Ubuntu family: FEX source step tested in Debian 13
  containers only (Debian 12 stops at host package check).

## Debian systems

`add-apt-repository` maps PPA to Debian release name, which PPA does not publish, so on systems outside Ubuntu family setup writes PPA as apt source `/etc/apt/sources.list.d/steam-arm-fex.sources` (deb822, `Architectures: arm64`). Ubuntu series follows Debian release: FEX build must need C library no newer than host's and Qt 5 package names Debian release uses.

| Debian release              | glibc | PPA series (FEX build needs)     | Result                                                             |
|-----------------------------|-------|----------------------------------|--------------------------------------------------------------------|
| 13 trixie (Raspberry Pi OS) | 2.41  | noble, Ubuntu 24.04 (glibc 2.38) | FEX and every host package resolve for arm64 (container test)      |
| 12 bookworm                 | 2.36  | jammy, Ubuntu 22.04 (glibc 2.34) | setup halts before any change: no `libsdl3-0`, `libgtk2.0-0t64`    |
| testing, unstable           | 2.41+ | noble                            | untested                                                           |
| 11 bullseye and older       | 2.31  | none                             | setup halts before any change: no SDL3 packages; upgrade to 13     |

Signing key is fetched from `keyserver.ubuntu.com` by fingerprint `EDB98BFE8A2310DC9C4A376E76DBFEBEA206F5AC` (Launchpad's `signing_key_fingerprint` for `~fex-emu/+archive/ubuntu/fex`); setup checks that download holds this one key only, then writes `/etc/apt/keyrings/steam-arm-fex.gpg`. Existing FEX source is kept; one naming Debian release (left by `add-apt-repository` on Debian) is renamed to `.disabled`, since apt cannot update it. With `FEX` command already present, setup adds no source. To build FEX instead: FEX's `InstallFEX.py` or build guide, <https://github.com/FEX-Emu/FEX>. FEX from another source (`FEX` command not owned by `fex-emu` package) needs its x86 binfmt entries registered; setup then installs no FEX packages and reads thunk folders from FEX's own prefix, `/usr` or `/usr/local` (see `README.md`, Requirements). Tested with stubs only.

## Non-Mali GPUs

`vk-spoof` exists to report device features that Direct3D translation layer requires and that Mali PanVK driver does not expose. On system with Vulkan driver that already exposes those features, `vk-spoof` is unnecessary; GPU family detection leaves it and `gpu-in-emulation` off on non-Mali GPUs.

Published driver archive of `gpu-in-emulation` carries Mali drivers only; on non-Mali GPU, profile `gfx=b` logs warning and title stays on forwarding. Custom driver archive (`STEAM_ARM_PROVIDER_TARBALL` with `STEAM_ARM_PROVIDER_SHA256`, see Custom driver archive in `README.md`) can carry Mesa drivers for other GPUs; with it, `gfx=b` and `GFX_DEFAULT=b` apply on any GPU family, while automatic rules stay Mali-only. Untested on non-Mali GPUs; results depend on Mesa and kernel versions.

Automatic Windows build applies on `mali-csf-v10` only; other families show it as suggestion.

`glx-lax` addresses Mesa client library limit and applies to any Mesa based driver, not only Mali's, so it stays useful on non-Mali GPUs that use Mesa.

## Other ARM64 systems

Two properties decide whether this works on system, and neither is about board:

1. **Working Vulkan driver for GPU.** Windows titles reach it through Direct3D
   translation layer in ARM64 Proton build. Driver does not have to be Mesa one:
   public testing of native client was done on hardware using proprietary driver,
   and ARM workstations with discrete graphics cards use same drivers as desktop
   machines. What matters is that Vulkan works before any of this is installed. System
   whose GPU has no Vulkan driver at all can still run titles built for Linux against
   OpenGL, and cannot run Windows titles.
2. **4K page size for emulation half.** Code built for x86 assumes 4K pages. Most
   ARM64 Linux systems use 4K, but two common ones do not. Apple Silicon runs 16K pages and
   needs x86 side inside environment that provides 4K pages, which this package does not set
   up. Raspberry Pi 5 also defaults to 16K, and switches with one line of firmware
   configuration, described below.

What changes per graphics driver:

| Driver                    | `vk-spoof`                                       | `glx-lax` | Notes                                                                  |
|---------------------------|--------------------------------------------------|-----------|------------------------------------------------------------------------|
| PanVK on Mali             | needed                                           | applies   | tested configuration; `gpu-in-emulation` on by default on Mali GPUs    |
| Turnip on Adreno          | not needed                                       | applies   | driver exposes features layer reports; detection leaves `vk-spoof` off |
| Other Mesa Vulkan drivers | not needed unless title fails at device creation | applies   | detection leaves both Mali components off                              |

Distribution matters as much as hardware: installer uses apt throughout, and
emulation tool comes from Ubuntu PPA, so Ubuntu family system is path that has been
exercised. Debian 13 gets that PPA as plain apt source (see Debian systems). Distribution
outside Debian family needs package steps rewritten.

Everything in this section is reasoning from requirements, not result.

## Device classes

Checked against public sources in September 2026. Entries other than RK3588 are drawn from
driver documentation and public reports; grouping is judgement, not result.

### Test device, expected on same stack

**Rockchip RK3588 and RK3588S**, Mali-G610 through Panfrost and PanVK on Panthor kernel
driver. This is configuration package was built against and test device's family; other
RK3588 boards running same stack are expected to work.

### Works after one change

**Raspberry Pi 5.** Vulkan 1.3 through V3DV, but firmware loads 16K page kernel by
default and emulation layer needs 4K. Add `kernel=kernel8.img` to `config.txt`, described
below. Desktop OpenGL stops at 3.1 and DXVK cannot run, so Windows titles use WineD3D
(Raspberry Pi, Graphics).

### Titles built for Linux, but not Windows titles

**Rockchip RK3566 and RK3568, Amlogic parts such as Odroid N2 and N2+, and newer Allwinner
parts.** These carry Mali-G52 or G31. Panfrost gives them OpenGL, which is what title built
for Linux needs. Open Vulkan driver is not usable on this generation, so Direct3D
translation layer has nothing to reach and Windows titles are not reasonable expectation.
Odroid N2, N2+ and Allwinner parts with Cortex-A53 cores lack LSE atomics: x86 client
through emulation (see Plausible, not tested).

### Plausible, not tested

**NVIDIA Jetson Orin.** Vendor's own driver provides Vulkan, and base is Ubuntu, so
requirements are met. Base is older than current desktop distribution.

**Snapdragon laptops with 8cx Gen 3**, Adreno 690 through Turnip, which is established
part of that driver.

**ARM workstations with graphics card.** Card's own driver provides Vulkan exactly as it
does on desktop machine, which makes this least exotic case in list. Check page
size, because it has differed between releases of same distribution on this hardware.

**Armv8.0 CPUs without LSE atomics** (Cortex-A53, A57, A72, A73): Raspberry Pi 4, Odroid
N2 and N2+, Allwinner parts with Cortex-A53 cores. Native client builds stop at start;
setup installs Valve's x86 client through emulation there (`README.md`, x86 client).
Untested on such hardware. Boards with 1 GB of memory (Raspberry Pi 3) stop at memory
check.

### Wait

**Snapdragon laptops with X Elite or X2.** OpenGL support has landed; Vulkan driver
for these parts is still arriving.

**ARM Chromebooks.** GPU is forwarded into container, so quality follows host driver
through extra layer, and host itself is not distribution you control.

### Out of scope

**Boards with Mali-400 or 450**, served by Lima, which provides no Vulkan at all.

**Servers built for compute, such as Grace parts.** Recommended page size is 64K and there
is no display stack to speak of.

**Android through terminal emulator.** Whatever GPU can do, that environment has no
system service manager, which several components require.

**Apple Silicon under Asahi.** Honeykrisp is functional at Vulkan 1.3, but kernel runs 16K
pages and setup halts. Emulation half needs 4K page guest such as `muvm`, which this package
does not set up. `STEAM_ARM_IGNORE_PAGESIZE=1` skips check on non-4K host kernel; use it only
when x86 side runs inside separate 4K page guest that check cannot see. On 16K host without
such guest, emulation fails. Untested.

**Hardware with no 64-bit ARM support**, which is excluded by architecture itself.

## What decides it, in practice

**Which Mali driver OS image includes.** On Rockchip boards two stacks exist: open one,
Panfrost with PanVK on Panthor kernel driver, and vendor blob on its own kernel
driver. They bind different GPU nodes in device tree and cannot both be active, so
image carries one or other. This package expects open stack, which is what tested
image uses. On vendor image installer finds closed `kbase` driver (family `mali-kbase`),
warns and leaves Mali components off.
`glxinfo -B` and `vulkaninfo --summary` name driver in use.

**Which Mali generation chip is.** Open Vulkan driver is conformant on Mali-G610 and
other Valhall parts of that generation. On older Bifrost parts, G52 and G31 found
in cheaper boards, Vulkan is experimental to point that Mesa gates it behind
environment variable that calls itself broken. Those boards can run titles built for Linux
against OpenGL, which Panfrost supports well; Windows titles through Direct3D layer are
not reasonable expectation there.

**Page size, where it is not 4K.** Raspberry Pi 5 and Apple Silicon both default to 16K.
Pi is one line firmware change, which `page-size` component makes. Apple Silicon needs
emulation inside guest that provides 4K pages, which this package does not set up.
Setup checks page size first and stops with fix for that system rather than installing
something that cannot run. On ARM workstations default has moved between releases of same
distribution, so it is worth checking rather than assuming.

**Whether system has service manager and device manager at all.** Terminal emulator
environment on Android is not Linux system in sense this needs, whatever its GPU can do.

Hardware with no 64-bit ARM support at all, which includes earliest single board
computers, is excluded by architecture rather than by any of above.

## Raspberry Pi

Raspberry Pi 5 meets both requirements in principle: it is ARM64, and Mesa provides
Vulkan driver for its GPU. Three things need attention before emulation half runs.
Raspberry Pi 4 (Cortex-A72, Armv8.0 without LSE atomics) runs Valve's x86 client through
emulation, since native client builds stop at start there (`README.md`, x86 client);
untested.

**Page size.** Pi 5 firmware loads `kernel_2712.img` by default, which uses 16K pages.
Code built for x86 assumes 4K, and emulators refuse to start on 16K kernel. Adding

```
kernel=kernel8.img
```

to `config.txt` (on current Raspberry Pi OS that file is `/boot/firmware/config.txt`) selects
4K page kernel instead. `page-size` component, on by default, writes that line in marked
block, keeps `config.txt.steam-arm.bak`, and stops so system can reboot; second run of
`sudo bash steam-arm-install.sh` then installs. It stops instead when `config.txt` already sets
`kernel=` or when `kernel8.img` is missing. Deselecting `page-size` removes block again. 16K
kernel is there for performance, so change costs several percent on other workloads.

**Distribution.** Raspberry Pi OS is Debian based (`ID=debian` in `/etc/os-release`). On
Raspberry Pi OS built on Debian 13 (trixie), setup adds FEX PPA as apt source with its
Ubuntu 24.04 build (see Debian systems). Raspberry Pi OS built on Debian 12 (bookworm)
lacks SDL3 packages client needs; host package check halts setup there before any change. Ubuntu for Raspberry
Pi fits installer's tested path.

**Graphics.** Mesa drives Pi GPU with v3d (OpenGL) and V3DV (Vulkan). GPU family detection
names Pi 5 GPU `broadcom-v3d71`, Pi 4 GPU `broadcom-v3d42` and Pi 0 to 3 GPU `broadcom-vc4`,
and leaves Mali-only parts off. `glxinfo -B` shows OpenGL values on system;
`steam-arm-config` Information shows them as `OpenGL` line. Driver facts, from Mesa source
(`src/gallium/drivers/v3d/v3d_screen.c`, `src/broadcom/vulkan/v3dv_device.c`, checked
2026-10-14) and community reports:

- Desktop OpenGL 3.1, not conformant (GLSL 1.40 for compatibility contexts); OpenGL ES 3.1
  conformant. Shader compiler accepts GLSL 3.30, but desktop geometry shaders and seamless
  cube maps are missing, so driver stops at 3.1. Same on Pi 5 (V3D 7.1) and Pi 4 (V3D 4.2).
- V3DV is Vulkan 1.3 conformant on Pi 4 and Pi 5 since Mesa 24.3
  <https://9to5linux.com/mesa-24-3-open-source-graphics-stack-adds-vulkan-1-3-conformance-for-v3dv>,
  but lacks about twelve features DXVK requires: BC texture compression, `shaderInt64`,
  `multiDrawIndirect`, more than one viewport, `shaderCullDistance`, `shaderDrawParameters`,
  descriptor indexing, `robustBufferAccess2` and others. These are hardware and compiler gaps;
  feature layer `vk-spoof` cannot fill them, so it stays off. VKD3D-Proton (Direct3D 12)
  needs more than DXVK.
- GPU throughput about quarter of RK3588's Mali-G610 (third-party FP32 estimates; no
  like-for-like benchmark exists). GPU memory: 4 GiB address space, 1 GiB per allocation.

What Steam ARM does on `broadcom-v3d71`, `broadcom-v3d42` and `broadcom-vc4`:

- **Windows titles: WineD3D by default.** Launcher sets `PROTON_USE_WINED3D=1` for Proton,
  so Direct3D 8 to 11 run through WineD3D on OpenGL in place of DXVK, which stops at device
  creation on V3DV. `PROTON_DXVK_D3D8=1` (DXVK for Direct3D 8, set on other GPUs) stays
  unset here. Own launch option `PROTON_USE_WINED3D=0` wins. Title setting `d3d=dxvk`
  (`steam-arm-config`, Graphics, Route per game, Direct3D) switches one title back to DXVK,
  for tests only.
- **OpenGL version report per title, off by default.** `glver=3.3` sets
  `MESA_GL_VERSION_OVERRIDE=3.3` with matching `MESA_GLSL_VERSION_OVERRIDE=330` (Graphics,
  Route per game, OpenGL version; values 3.2, 3.3 and 4.0 to 4.6, GLSL version follows).
  Titles that only check version at start then start. Titles that use OpenGL 3.2 and newer
  features (geometry shaders, seamless cube maps, GLSL 3.30 paths) draw wrong or stop:
  remove setting again. Never global, since titles that run today would take paths v3d
  cannot draw. Game log line `renderer:` with CPU drawing, and CPU drawing notice, name this
  setting on these GPUs; nothing changes by itself.
- **Zink per title, experimental.** `gl=zink` sets `MESA_LOADER_DRIVER_OVERRIDE=zink` and
  `GALLIUM_DRIVER=zink`: OpenGL on V3DV (Graphics, Route per game, OpenGL driver). Unproven
  on Raspberry Pi: published Pi 4 tests show about half frame rate of v3d and blank or
  single-colour windows in some programs; no Pi 5 measurements exist. Zink can offer
  geometry shaders v3d lacks, so title whose only need beyond 3.1 is geometry shaders may
  draw under Zink; pair with `glver=3.3`.
- **How settings reach title.** x86 Linux titles and x86 Proton: launch handler (game log
  lines `d3d:` and `pi gpu:`). Windows titles on ARM64 Proton start without launch
  handler: launcher writes settings as Steam launch option before client start
  (`STEAM_ARM_LAUNCHOPTS=<names> NAME=value ... %command%` ahead of own launch options),
  replaces or removes that part when setting changes, and removal takes it out. Variable
  own launch options set already stays theirs (GL pair and Zink pair as whole).

Expectations: older and lighter titles. 2D and indie titles fit; Source-era 3D runs at 720p
on low settings; Direct3D 9 era 3D through WineD3D mostly runs slow. Direct3D 11 titles
that need feature level 11_0 or newer, Direct3D 12 titles, Vulkan-only Windows titles and
OpenGL 4.5-class titles (newer Unity OpenGL builds included) do not run. Frame rates from
RK3588 test device in `GAMES.md` divide by about 3 to 4 for Pi 5, then need checking on
hardware.

Status: Raspberry Pi behaviour above is untested on Raspberry Pi hardware (no Pi on hand);
it follows from Mesa source and community reports. Reports welcome; table in `GAMES.md`,
Raspberry Pi 5.

### Raspberry Pi 4

Cortex-A72 (Armv8.0, no LSE atomics), VideoCore VI (`broadcom-v3d42`), Mesa v3d (OpenGL
3.1) and V3DV (Vulkan 1.2 on Raspberry Pi OS bookworm Mesa 24.2, Vulkan 1.3 on trixie
Mesa 25 and 26). Setup writes `PLATFORM=pi4`, `CPU_LSE=0` and `MESA_HOST`, picks FEX
package `fex-emu-armv8.0` and Valve's x86 client (native client stops with SIGILL on this
CPU; setup checks each new native build and moves back by itself).

What runs where:

- Client window: x86 client through emulation, drawn on CPU. Expected, not fault; native
  client is blocked by Valve issue 13288. 3.1 lowers its work: desktop interface by
  default (Deck interface is one animated page), no friends view, site isolation off, FEX
  code cache and logging off for client processes, optional reduced x87 precision for
  client program, Multiblock off after repeated client window restarts. Magnitude is
  unmeasured; `steam-arm --cpu-report` names processes and threads and ends with verdict.
  Window size follows desktop resolution: 1920x1080 output halves layout work against
  3840x2160.
- Three levels: always on CPU (client window, emulator's translated code); per title
  (`tso=off`, `x87=reduced`, `glver`, Zink; correctness trades named on each screen);
  experiments (`lab-cef-gpu vulkan`, kept with `client-gpu on`; `client-tso relaxed`;
  `x87-client on`), each off by default and each with guard or watcher. Vulkan class:
  V3DV 1.2 on Raspberry Pi OS bookworm (Mesa 24.2), 1.3 on trixie (Mesa 25 and 26);
  setup stores it as `VK_HOST`.
- Client window through GPU: only ANGLE on Vulkan thunk can reach host GPU (GL thunk
  breaks on Chromium's GLX pattern, EGL thunk lacks entry Chromium's loader uses);
  unverified on V3DV, black window possible, so opt-in.
- Games: x86 Linux titles reach v3d and V3DV through FEX GL and Vulkan forwarding when
  FEX's thunk libraries are present (package `fex-emu-armv8.0` includes
  `HostThunks/libGL-host.so`, `libvulkan-host.so`, `GuestThunks/libGL-guest.so`,
  `libvulkan-guest.so`, `ThunksDB.json`; checked by project's container test). Without
  them every game draws on CPU and launcher raises notice at every start. 32-bit titles
  are worst case: no 32-bit Vulkan thunk, GL thunk only.
- Windows titles: x86 Proton through emulation, WineD3D on OpenGL 3.1 (Direct3D 9 class,
  feature level 9_3); Direct3D 10 and 11 titles need `glver=3.3` and may misrender.
  `d3d=dxvk` is kept but not applied: DXVK needs `shaderInt64`, `robustBufferAccess2`,
  `textureCompressionBC`, `multiViewport` and `tessellationShader`, V3DV reports none.
- 32-bit titles with Vulkan: no 32-bit Vulkan forwarding, so `-vulkan` is removed (GL
  path); `vk32=keep` keeps it on lavapipe (CPU) and records reason `vk32-cpu`.
- Per-title levers (opt-in): `tso=off`, `x87=reduced` (Emulation keys), `glver`, Zink,
  automatic tuning order on Pi families (OpenGL version 3.3, Zink, Multiblock; no
  `gl32`), `pi-governor` component.
- Session: Raspberry Pi OS desktop runs labwc (Wayland), client and titles draw through
  XWayland; launcher logs session type once per start, setup names it in Raspberry Pi
  line of x86 client block.
- Power and heat: under-voltage and 80 C capping lower clocks; `steam-arm --cpu-report`
  decodes `vcgencmd get_throttled` bits per sample.

Not movable to GPU by any setting: emulator's translated code (client, Proton, game
logic), memory model barriers, translation time, per-call marshalling of forwarded GL,
software video decode.

Untested on Raspberry Pi 4 hardware; report with two `steam-arm --cpu-report` files
(before and after change) at project's issues:

| Item                                              | State                                    |
|---------------------------------------------------|------------------------------------------|
| Thunk libraries load on v3d and V3DV under FEX     | untested, report with `steam-arm --cpu-report` |
| Idle CPU split (client, client window, emulator)   | untested, report with `steam-arm --cpu-report` |
| Desktop interface and no friends view: CPU change  | untested, report with `steam-arm --cpu-report` |
| Code cache off: client window restart loop absent  | untested, report with `steam-arm --cpu-report` |
| Reduced x87 precision: start time                  | untested, report with `steam-arm --cpu-report` |
| Multiblock restart counter ever fires              | untested, report with `steam-arm --cpu-report` |
| `tso=off`, `x87=reduced`: frame rate and stability | untested, per title                      |
| `glver=3.3` starts title that stopped on GL 3.1    | untested, per title                      |
| Client window through GPU experiment               | untested, low odds                       |
| `client-gpu on` after `cef-gpu=ok`: CPU change     | untested, report with `steam-arm --cpu-report` |
| Site isolation off: process count and CPU change   | untested, report with `steam-arm --cpu-report` |
| `client-tso relaxed`: 30 min browse without guard  | untested, report with `steam-arm --cpu-report` |
| Verdict `restart loop` ever fires                  | untested, report with `steam-arm --cpu-report` |
| `VK_HOST` matches `vulkaninfo` per release          | untested, verdict line `vulkan host`     |
| `pi-governor`: frame rate and throttle bits        | untested, report with `steam-arm --cpu-report` |
| Thermal capping under load                         | untested, report with `steam-arm --cpu-report` |

### Raspberry Pi 5 performance tips

Gains below are unmeasured on Raspberry Pi 5. Settings that cost heat or power are opt-in
and stay off unless set by hand.

1. **Renderer first.** Game log line `renderer:` (`steam-arm-config`, Games, then game; or
   hardware report). `GPU forwarding not active: rendering on CPU (llvmpipe)`: fix that
   first, since nothing below helps CPU drawing.
2. **CPU or GPU limit.** MangoHud on x86 Linux title, launch option
   `MANGOHUD_CONFIG=fps,frametime,frame_timing,cpu_stats,core_load mangohud %command%`.
   One core near 100% while frame rate stays low: CPU limit. Lower in-game resolution:
   frame rate goes up with GPU limit, stays with CPU limit. `vcgencmd get_throttled` prints
   `throttled=0x0` when board has not throttled; other values mean power or heat limit.
3. **Vsync steps.** At 60 Hz with vsync and double buffering, frame times fall on 16.7 ms
   or 33.3 ms. Frame time graph alternating between these two bands means title misses
   some 60 Hz frames, and average such as 47 fps sits between 60 and 30. Graph spread
   around one value means throughput limit.
4. **Output resolution.** 1920x1080 output in place of 3840x2160: titles that render at
   desktop resolution draw quarter as many pixels. Set it in Screen Configuration
   (Raspberry Pi OS) or display settings of desktop.
5. **Session.** Raspberry Pi OS desktop runs labwc (Wayland); client and x86 titles draw
   through XWayland. X11 session (`raspi-config`, Advanced Options, Wayland, X11) is other
   option; compare both on one title
   <https://www.raspberrypi.com/news/a-new-release-of-raspberry-pi-os/>.
6. **CPU governor (opt-in).** Raspberry Pi kernel default is `ondemand`
   (`CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y` in `bcm2712_defconfig`,
   <https://github.com/raspberrypi/linux>). `performance` holds cores at top clock, with
   more heat and power. Component `pi-governor` (off by default; Maintenance, CPU governor
   while Steam runs) sets it while Steam ARM runs and puts saved governor back at exit.
   By hand until next reboot:
   `echo performance | sudo tee /sys/devices/system/cpu/cpufreq/policy0/scaling_governor`;
   back with `ondemand` in same command. `steam-arm-config` Information shows governor in
   use (`CPU governor` line); `steam-arm --cpu-report` shows governor and throttle bits
   per sample.
7. **FEX Multiblock per title (opt-in).** `steam-arm-config profile <appid> multiblock=on`;
   `multiblock=` removes it. Valve sets this per title in its own data; profile replaces
   that default for one title. Unmeasured on Pi 5; on RK3588 test device one 32-bit Unity
   title ran 5 to 9 % faster with 9 to 12 % less CPU load, first frame 2 to 4 s later.
   Java 21 and newer titles fail with it on.
8. **FEX code cache per title (opt-in).** `steam-arm-config profile <appid> diskcache=on`;
   needs Valve FEX tool FEX-2609.1 or newer. Unmeasured on Pi 5 and RK3588 test device;
   on RK3588 test device 2 of 11 starts with empty cache hung before game start.
   Proton Experimental (ARM64) turns code cache on for Windows titles by itself.
9. **Clocks (opt-in, warranty and heat).** Raspberry Pi documents `arm_freq`, `gpu_freq`,
   `v3d_freq` (on Pi 5 V3D clock is independent of core clock) and `over_voltage_delta`
   for `config.txt`; Steam ARM sets none of them and suggests no values. Active cooling
   needed. Raspberry Pi documents that some combinations set permanent bit in SoC
   <https://www.raspberrypi.com/documentation/computers/config_txt.html>.

## Not limited to single board computers

Installer hardcodes no GPU render node or card index; GPU family detection reads every render node, and page size check looks at board. Requirement
is ARM64 system, Debian or Ubuntu family distribution and Mesa graphics stack, which
also describes ARM64 workstations, servers and laptops, not only single board computers.

Three of sixteen components are help for specific driver rather than requirements:
`vk-spoof` exists because Mali driver does not expose features Direct3D translation
layer asks for, and is unnecessary on driver that exposes them; `gpu-in-emulation` carries
Mali drivers only; `glx-lax` applies to Mesa. `page-size` applies to Raspberry Pi only,
`kde-input-prompt` to KDE Plasma only. Other eleven are generic. Detection turns `vk-spoof` and `gpu-in-emulation` off on GPUs they do not serve.

## Disclaimer

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam, Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
