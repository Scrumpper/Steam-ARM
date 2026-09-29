# Credits

This installer writes little software of its own. It arranges other people's work into
combination that runs native ARM64 Steam client on ARM64 system, and projects below
are what it stands on. Nothing listed here is bundled in package: each is either already on
system, installed from its own repository, or downloaded by client at first start.

## Client and Runtime

- **Valve Corporation**: ARM64 build of Steam client, published for Linux on ARM64 as
  public beta. Also **Proton**, ARM64 build of which runs Windows titles; **Steam Linux
  Runtime** and its **pressure-vessel** container tool, whose library overrides are what let
  guest reach host drivers; **Steam Input**, which re-identifies game controllers; and
  **Remote Play**. Client package and Proton are downloaded from Valve at run time.
- **Wine**: Windows compatibility layer Proton is built from.
  <https://www.winehq.org>
- **DXVK** by Philip Rebohle and contributors: Direct3D to Vulkan layer inside Proton.
  `Vk-spoof` component exists because DXVK requires set of Vulkan device features that
  Mali driver does not expose.
  <https://github.com/doitsujin/dxvk>

## Emulation

- **FEX-Emu**: x86 and x86-64 emulator that runs games ARM64 client installs, and
  x86-64 Remote Play streaming client. Its **thunk** mechanism, which forwards OpenGL and
  Vulkan calls from emulated guest to host's native libraries rather than emulating
  them, is reason games reach GPU at usable speed. Installed from project's PPA.
  <https://github.com/FEX-Emu/FEX>
- **Canonical** and **Ubuntu** project: Ubuntu 24.04 x86-64 root filesystem FEX runs
  its guest against, and ARM64 distribution most target systems run.
  <https://ubuntu.com>
- **Debian**: packaging format this tool ships in, and base Ubuntu derives from.
  <https://www.debian.org>
- **box86** and **box64** by ptitSeb: translation layers behind older guides for running
  x86 Steam client on ARM. This project takes different route, running client natively
  rather than emulating it, but that earlier work is what established approach.
  <https://github.com/ptitSeb/box64>

## Graphics

- **Mesa**: **Panfrost** for OpenGL and GLES and **PanVK** for Vulkan on Mali hardware.
  Client, emulated games and Proton all render through these. `Glx-lax` component builds
  private copy of Mesa's GLX client library with one check relaxed, for titles that bind
  single OpenGL context from more than one thread.
  <https://www.mesa3d.org>
- **Panthor** kernel DRM driver authors at **Collabora** and **ARM**: open kernel driver for
  Mali "Valhall" hardware that PanVK is built on, in place of closed vendor blob.
- **Khronos Group**: Vulkan specification, loader and layer interface that
  `vk-spoof` layer is written against.
  <https://www.vulkan.org>

## System

- **bubblewrap**: unprivileged sandbox client's runtime uses to build its container.
  <https://github.com/containers/bubblewrap>
- **Linux kernel** `xpad` driver maintainers: controller table `pad-hidraw` rules are
  generated from, and `uinput` subsystem `pad-xbox` component presents pads through.
- **patchelf**: used to give private GLX copy its own library name so it does not collide
  with system one.
  <https://github.com/NixOS/patchelf>

## Community

- **Armbian** and its community forums: distribution many target boards run, and
  RK3588 bring-up discussions that made this work possible.
  <https://www.armbian.com>
- **Collabora**: for sustained Mali and Panthor work that put open Vulkan driver on this
  class of hardware at all.

## Development

Developed and tested on one device, H96 Max V58, RK3588 board with Mali-G610 GPU.
`COMPATIBILITY.md` records what has been tested and what has not.

Development was done conversationally with **Claude Code**. 
Treat everything in this repository as community work offered in good faith, with no warranty.

## Trademarks and affiliation

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation. No Valve artwork is
distributed with this package.

This is unofficial, community-built tool. It is not affiliated with, endorsed by or supported
by Armbian project, Canonical, Collabora, ARM, FEX-Emu project or any board
manufacturer. Each project named above is credited for its work, not for any involvement in
this one.

Every project named here is distributed under its own licence. This installer is MIT licensed;
see `LICENSE`.
