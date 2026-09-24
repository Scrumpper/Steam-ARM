# Steam ARM setup

Full feature list: **[FEATURES.md](FEATURES.md)**.

One command installs Valve's native ARM64 Steam client on ARM64 Linux system, with
supporting pieces that client needs and does not carry: graphics forwarding, controller
access, and Remote Play settings system without Vulkan Video requires.

```bash
sudo dpkg -i steam-arm-setup_1.0_arm64.deb
sudo apt-get -f install          # if apt reports missing dependencies
sudo steam-arm-setup             # installs the client; nothing is downloaded before this
```


## Highlights

- **Valve's own ARM64 client.** Client build Valve made for its ARM based VR headset,
  Steam Frame. It is native ARM program: interface, overlay, input stack and
  download and shader systems run on CPU and GPU directly. Only title's x86 code
  goes through emulation tool client downloads.
- **Windows titles through ARM64 Proton.** Valve's ARM64 Proton build runs them, and its
  Direct3D layer reaches system Vulkan driver.
- **Vulkan compatibility layer for Mali.** Direct3D layer asks for device features
  Mali driver does not expose. `Vk-spoof` component reports them and removes them again
  before device creation, so Proton titles start on PanVK.
- **Remote Play that connects.** Streaming client decodes through Vulkan Video, which
  Mali driver does not provide, so client advertises decoder it does not have and
  session never finishes negotiating. `steam-arm-remoteplay` pins hardware decoding and HEVC
  off in client's stored configuration, and launcher applies it before every start,
  including first, so new installation streams without settings change.
- **Controllers client can read.** Steam client runs as desktop user and reads pad
  over `/dev/hidraw`, which kernel creates for root account only. Rules that hand
  those devices to logged-in user cover pads client has drivers for; this ships
  rules for every pad kernel `xpad` driver recognises, 243 of them, matched on vendor and
  product so keyboards and mice from same makers are not included, together with
  `/dev/uinput`.
- **One joystick per pad.** Third-party Xbox 360 style pads that expose headset interface
  were bound twice by `xpad` driver, so one pad appeared as two identical joysticks and
  two-player game handed player 2 copy of player 1. Udev rule unbinds that interface.
- **Nothing downloaded until asked.** Installing package writes files and prints
  command to run. Every download happens when that command runs.
- **Components are selectable.** `--defaults`, `--select a,b`, `--skip a,b`, `--list`, or
  keyboard checklist. Component deselected on later run is removed again.
- **It installs into desktop account, not root.** First regular account by default,
  another with `GAMEUSER`.

## How this differs from other ways to run Steam on ARM64

|                        | What it runs                           | Where it runs    | Graphics                                                         |
|------------------------|----------------------------------------|------------------|------------------------------------------------------------------|
| Arm64 Steam snap       | x86 client, wrapped in emulation layer | snap sandbox     | reported to fail on RK3588 with `failed to load driver: panthor` |
| Box86 and Box64 guides | x86 client under Box64                 | host             | works, with client itself emulated as well                       |
| This                   | native ARM64 client                    | host, no sandbox | host's Mesa drivers, used directly                               |

Two structural differences. Client is native, so only title's x86 code passes through
emulation, not interface, overlay, input stack or downloader. And it installs
onto host rather than into sandbox, which is what gives it host's own Vulkan and
OpenGL drivers.

Part that takes longest to work out on your own is not client, which package
manager installs; it is what has to be in place before titles start:

- Vulkan layer for device features Direct3D translation layer requires and some
  drivers do not expose, without which Proton titles fail at device creation
- Remote Play decode settings, without which session on GPU with no Vulkan Video
  never finishes negotiating
- private copy of Mesa GLX library for titles that bind one OpenGL context from several
  threads
- controller rules covering every pad kernel `xpad` driver recognises, duplicate
  joystick fix, and memory map limit Proton expects

Those ship here as selectable components, and deselecting one on later run removes it again.

## Components

| Component    | What it does                                                                                                              | Scope          |
|--------------|---------------------------------------------------------------------------------------------------------------------------|----------------|
| `glx-lax`    | Private copy of Mesa GLX client library, for titles that bind one OpenGL context from several threads                     | Mesa           |
| `vk-spoof`   | Reports Vulkan device features Direct3D layer requires and driver does not expose, then removes them from device creation | Mali and PanVK |
| `map-count`  | Raises `vm.max_map_count` to value Proton expects                                                                         | Generic        |
| `xpad-dedup` | Drops duplicate joystick node of third-party Xbox 360 style pads                                                          | Generic        |
| `pad-hidraw` | Hands pad's `/dev/hidraw` node and `/dev/uinput` to logged-in user                                                        | Generic        |
| `pad-xbox`   | Presents XInput pads from other makers as Xbox 360 pads                                                                   | Generic        |
| `desktop`    | Application menu entry and desktop icon for account client installs into                                                  | Generic        |

## Requirements

ARM64 system, Debian or Ubuntu family distribution, and working Vulkan driver.
Emulation tool is installed from Ubuntu PPA `ppa:fex-emu/fex`, so Ubuntu family
distribution is tested path; on Debian that tool has to come from elsewhere first.

Installer has no hardcoded GPU render node, no hardcoded card index and no board
detection.

## What it does not do

- Titles protected by anti-cheat do not run.
- There is no VR support. Client build comes from VR headset, VR runtime does not;
  launcher removes client's VR argument from streaming client.
- It has been tested on one device: RK3588 board with Mali-G610 GPU, on Armbian based
  image. Other RK3588 boards with same GPU are closest match and are untested. Boards
  with another SoC or another GPU are untested.
- No published account of native client rendering through Panthor and PanVK on Mali-G610
  was found while this was built. Corrections are welcome.

## Issues and questions

Report problems and ask questions in this repository's Issues. Include board,
distribution, output of `steam-arm-setup --list`, and what installer printed.

## Removing it

```bash
sudo apt-get purge steam-arm-setup
```

Package owns command and its documentation. Client, emulation tool and
components installer set up are removed by re-running installer with components
deselected, or by deleting client's directory in account it installed into.

## Building package

`build-deb.sh` assembles package tree from files in this repository and builds it with
`dpkg-deb`. It needs `dpkg` package, so it runs on Debian family system;
architecture of build machine does not matter.

```bash
./build-deb.sh          # writes steam-arm-setup_1.0_arm64.deb beside it
```

Layout: `steam-arm-install.sh` is installer and becomes
`/usr/share/steam-arm-setup/install.sh`, `bin/steam-arm-setup` is command that runs it,
`debian/` holds package control files, and `doc/` holds what lands in
`/usr/share/doc/steam-arm-setup`.

## Credits

This installer arranges other people's work: Valve's ARM64 client and Proton, FEX-Emu, Mesa
with Panfrost and PanVK, Panthor kernel driver, DXVK, bubblewrap and others. None of it is
bundled here. See **[CREDITS.md](CREDITS.md)**.

---

This is unofficial, community-built tool. It is not affiliated with, endorsed by or
supported by Armbian project or any board manufacturer.

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
