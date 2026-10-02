# steam-arm-setup

Installs Valve's native ARM64 Steam client and supporting pieces
(RootFS, graphics provider, launcher, and optional components such as
Vulkan compatibility layer and controller access rules) on ARM64
Debian or Ubuntu family system with Mesa graphics stack.

Nothing is downloaded during package installation. All downloads happen
when setup command below is run.

## Usage

    sudo steam-arm-setup

Run `steam-arm-setup --help` for list of options, including
`--defaults`, `--select`, `--skip`, and `--list`.

Installed games are kept. Re-running setup, changing components and
upgrading package leave game library, sign-in and settings untouched.

## Uninstall

    sudo steam-arm-setup --remove

Removes what setup added and keeps client folder with games unless deletion
is confirmed. `--remove --purge` also deletes client folder and x86 root
filesystem setup downloaded, after typed confirmation. Then
`sudo apt remove steam-arm-setup`.

## Requirements

- ARM64 (aarch64) system
- Debian or Ubuntu family distribution
- Mesa graphics stack
- 4K page kernel (`getconf PAGESIZE` prints 4096); setup checks this first,
  and on Raspberry Pi `page-size` component selects firmware's 4K kernel

## Issues

Report problems in project's repository:
https://github.com/Scrumpper/Steam-ARM

## Disclaimer

This project is not affiliated with, endorsed by or sponsored by Valve
Corporation. Steam, Proton, Steam Deck and Steam Frame are trademarks of
Valve Corporation.
