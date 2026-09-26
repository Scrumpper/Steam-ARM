# Compatibility

## Requirements

Confirmed by inspection of installer:

- ARM64 system.
- Debian or Ubuntu family distribution, since installer uses `apt`.
- Mesa graphics stack.

FEX, emulation tool used for x86 game code, installs from Ubuntu PPA `ppa:fex-emu/fex`. Ubuntu family distribution is tested path for that step.

Installer has no hardcoded GPU render node, no hardcoded card index, and no board detection.

## Before you install

Five checks cover what installer depends on. Run them on desktop session; `glxinfo`
comes from `mesa-utils` and `vulkaninfo` from `vulkan-tools`.

```
lsmod | grep -w panthor                     # open Mali kernel driver loaded
glxinfo -B | grep -i "renderer string"      # OpenGL renderer
vulkaninfo --summary | grep -i "driverName\|deviceName"
grep -E "^ID=|VERSION_CODENAME" /etc/os-release
getconf PAGESIZE
```

Output on tested device, H96 Max V58:

| Check           | Tested device                                     | What other result means                                                  |
|-----------------|---------------------------------------------------|--------------------------------------------------------------------------|
| `panthor`       | loaded                                            | not loaded: image uses vendor blob or older kernel; untested here        |
| OpenGL renderer | `Mali-G610 MC4 (Panfrost)`, Mesa 26.1.4           | `llvmpipe`: no GPU acceleration; titles run on CPU or not at all         |
| Vulkan driver   | `panvk`, device `Mali-G610 MC4`, Mesa 26.1.4      | no Vulkan device: titles built for Linux only, no Windows titles         |
| Distribution    | `ubuntu`, `resolute`                              | `debian`: emulation tool needs another source first, see below           |
| Page size       | `4096`                                            | `16384` or `65536`: emulation half does not run, see Raspberry Pi below  |

Mesa on tested device comes from `kisak-mesa` PPA. Older Mesa releases carry earlier
PanVK; when `vulkaninfo` lists no `panvk` device on Mali-G610, newer Mesa from that PPA
is route tested device uses.

Board whose five results match first column matches tested device in every property
installer depends on. That makes it expected to work, and still untested until someone
reports it.

## Armbian on RK3588 boards

Rock 5B, Orange Pi 5, NanoPi R6 and other RK3588 boards carry same Mali-G610 as tested
device. On Armbian, three choices at download time decide result:

- **Kernel branch.** `current` and `edge` branches are mainline kernels, and mainline has
  carried Panthor since Linux 6.10. `vendor` branch is Rockchip's 6.1 kernel; whether it
  has Panthor depends on build, so check with `lsmod` above.
- **Userland.** Ubuntu based images fit installer's tested path. Debian based images need
  emulation tool from source other than Ubuntu PPA.
- **Mesa.** Image's stock Mesa may predate PanVK support in use here; `vulkaninfo` check
  above shows it.

Reports from these boards are what turn this section from expectation into result.

## Component scope

| Component    | Scope         | Note                                                                                               |
|--------------|---------------|----------------------------------------------------------------------------------------------------|
| `glx-lax`    | Mesa specific | Addresses Mesa client library limit with titles that bind one OpenGL context from several threads. |
| `vk-spoof`   | Mali specific | Written for PanVK Vulkan driver on Mali; not needed on other Vulkan drivers.                       |
| `map-count`  | Generic       | Raises `vm.max_map_count`; applies to any Linux system running Proton.                             |
| `xpad-dedup` | Generic       | Applies to any system where kernel exposes duplicate joystick node for pad.                        |
| `pad-hidraw` | Generic       | Applies to any system using kernel `xpad` driver's device list.                                    |
| `pad-xbox`   | Generic       | Applies to any XInput pad from maker other than Microsoft.                                         |
| `desktop`    | Generic       | Application menu entry and desktop icon; no hardware dependency.                                   |

## Known to work

Tested on one device: H96 Max V58, RK3588 board with Mali-G610 GPU, running
Armbian based image.

## Untested

- Other RK3588 boards with Mali-G610 GPU (for example Rock 5B, Orange Pi 5, NanoPi, and other Radxa boards). These are closest match to tested device but have not been tested.
- Boards with different SoC or GPU.
- Debian family distributions outside Ubuntu family.

## Non-Ubuntu Debian systems

Installer installs FEX from Ubuntu PPA `ppa:fex-emu/fex`. On Debian system without access to that PPA, FEX needs to come from another source before emulation component can be set up; installer does not provide alternative source.

## Non-Mali GPUs

`vk-spoof` exists to report device features that Direct3D translation layer requires and that Mali PanVK driver does not expose. On system with Vulkan driver that already exposes those features, `vk-spoof` is unnecessary.

`glx-lax` addresses Mesa client library limit and applies to any Mesa based driver, not only Mali's, so it remains relevant on non-Mali GPUs that use Mesa.

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
   needs x86 side inside environment that provides 4K pages. Raspberry Pi 5 also
   defaults to 16K, and switches with one line of firmware configuration, described below.

What changes per graphics driver:

| Driver                    | `vk-spoof`                                       | `glx-lax` | Notes                                 |
|---------------------------|--------------------------------------------------|-----------|---------------------------------------|
| PanVK on Mali             | needed                                           | applies   | tested configuration                  |
| Turnip on Adreno          | not needed                                       | applies   | driver exposes features layer reports |
| Other Mesa Vulkan drivers | not needed unless title fails at device creation | applies   | skip it with `--skip vk-spoof`        |

Distribution matters as much as hardware: installer uses apt throughout, and
emulation tool comes from Ubuntu PPA, so Ubuntu family system is path that has been
exercised. Debian system needs that tool from another source first. Distribution outside
Debian family needs package steps rewritten.

Everything in this section is reasoning from requirements, not result. One device has
been tested.

## Device classes

Checked against public sources in September 2026. One device has been tested here; everything
in this table is drawn from driver documentation and public reports, and last column is
judgement, not result.

### Tested on one device, expected on same stack

**Rockchip RK3588 and RK3588S**, Mali-G610 through Panfrost and PanVK on Panthor kernel
driver. This is configuration package was built against. Tested on H96 Max V58; other
RK3588 boards running same stack are expected to work and have not been tested.

### Works after one change

**Raspberry Pi 5.** Vulkan 1.3 through V3DV, but firmware loads 16K page kernel by
default and emulation layer needs 4K. Add `kernel=kernel8.img` to `config.txt`, described
below.

**Apple Silicon under Asahi.** Honeykrisp is functional at Vulkan 1.3, and system runs 16K
pages, so emulation half has to run inside guest that provides 4K pages.

### Titles built for Linux, but not Windows titles

**Rockchip RK3566 and RK3568, Amlogic parts such as Odroid N2 and N2+, and newer Allwinner
parts.** These carry Mali-G52 or G31. Panfrost gives them OpenGL, which is what title built
for Linux needs. Open Vulkan driver is not usable on this generation, so Direct3D
translation layer has nothing to reach and Windows titles are not reasonable expectation.

### Plausible, not tested

**NVIDIA Jetson Orin.** Vendor's own driver provides Vulkan, and base is Ubuntu, so
requirements are met. Base is older than current desktop distribution.

**Snapdragon laptops with 8cx Gen 3**, Adreno 690 through Turnip, which is established
part of that driver.

**ARM workstations with graphics card.** Card's own driver provides Vulkan exactly as it
does on desktop machine, which makes this least exotic case in list. Check page
size, because it has differed between releases of same distribution on this hardware.

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

**Hardware with no 64-bit ARM support**, which is excluded by architecture itself.

## What decides it, in practice

**Which Mali driver image ships.** On Rockchip boards two stacks exist: open one,
Panfrost with PanVK on Panthor kernel driver, and vendor blob on its own kernel
driver. They bind different GPU nodes in device tree and cannot both be active, so
image carries one or other. This package expects open stack, which is what tested
image uses. Vendor image is different configuration and has not been tested here.
`glxinfo -B` and `vulkaninfo --summary` name driver in use.

**Which Mali generation chip is.** Open Vulkan driver is conformant on Mali-G610 and
other Valhall parts of that generation. On older Bifrost parts, G52 and G31 found
in cheaper boards, Vulkan is experimental to point that Mesa gates it behind
environment variable that calls itself broken. Those boards can run titles built for Linux
against OpenGL, which Panfrost supports well; Windows titles through Direct3D layer are
not reasonable expectation there.

**Page size, where it is not 4K.** Raspberry Pi 5 and Apple Silicon both default to 16K.
Pi is one line firmware change. Apple Silicon needs emulation inside guest that
provides 4K pages. On ARM workstations default has moved between releases of same
distribution, so it is worth checking rather than assuming.

**Whether system has service manager and device manager at all.** Terminal emulator
environment on Android is not Linux system in sense this needs, whatever its GPU can do.

Hardware with no 64-bit ARM support at all, which includes earliest single board
computers, is excluded by architecture rather than by any of above.

## Raspberry Pi

Raspberry Pi 5 or 64-bit Raspberry Pi 4 meets both requirements in principle: it is ARM64,
and Mesa provides Vulkan driver for its GPU. Three things need attention before
emulation half runs.

**Page size.** Pi 5 firmware loads `kernel_2712.img` by default, which uses 16K pages.
Code built for x86 assumes 4K, and emulators refuse to start on 16K kernel. Adding

```
kernel=kernel8.img
```

to `config.txt` (on current Raspberry Pi OS that file is `/boot/firmware/config.txt`) selects
4K page kernel instead. 16K kernel is there for performance, so change costs a
few percent on other workloads.

**Distribution.** Raspberry Pi OS is Debian based, and emulation tool used here comes from
Ubuntu PPA, so that step does not apply as written. Ubuntu for Raspberry Pi fits path
this installer uses; on Raspberry Pi OS emulation tool has to come from another source
first.

**Graphics.** Pi's Mesa Vulkan driver is conformant, and it is smaller GPU than
parts this has been tested against. Titles built for Linux are reasonable expectation;
Windows titles through Direct3D translation layer are heavier ask. Whether
`vk-spoof` component helps there is unknown, since it was written against different driver.

None of this has been tested.

## Not limited to single board computers

Nothing in installer detects board, GPU render node or card index. Requirement
is ARM64 system, Debian or Ubuntu family distribution and Mesa graphics stack, which
also describes ARM64 workstations, servers and laptops, not only single board computers.

Two of seven components are help for specific driver rather than requirements:
`vk-spoof` exists because Mali driver does not expose features Direct3D translation
layer asks for, and is unnecessary on driver that exposes them; `glx-lax` applies to Mesa.
Other five are generic.

Testing has been done on one device, so anything beyond it is reasoning rather than result.

## Disclaimer

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam, Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
