# steam-arm-setup

Installs Valve's native ARM64 Steam client and supporting pieces
(RootFS, graphics provider, launcher, and optional components such as
Vulkan compatibility layer and controller access rules) on ARM64
Debian or Ubuntu family system with Mesa graphics stack.

Nothing is downloaded at package installation. All downloads happen
when setup command below is run.

## Usage

    sudo steam-arm-setup

Run `steam-arm-setup --help` for list of options, including
`--defaults`, `--select`, `--skip`, and `--list`. `steam-arm-setup`
without options in terminal opens setup menu, which asks for `sudo`
itself; application menu entry "Steam ARM Setup" opens same menu in
terminal.

Installed games are kept. Re-running setup, changing components and
upgrading package leave game library, sign-in and settings untouched.

## Update

Settings menu Maintenance, Upgrade to newest release (or
`sudo steam-arm-config upgrade`), downloads `steam-arm-setup_<version>_arm64.deb`
of newest release with its `.sha256` file, checks both against GitHub's digest,
saves installed version, installs package with apt and runs
`sudo steam-arm-setup --keep`. By hand: download both files, check with
`sha256sum -c steam-arm-setup_<version>_arm64.deb.sha256`, then
`sudo apt install ./steam-arm-setup_<version>_arm64.deb` and
`sudo steam-arm-setup --keep`. Releases before 3.1 list no package: build it from
source tag (`build-deb.sh`). Settings menu Maintenance, Go back to previous
version, returns to saved version.

## Uninstall

    sudo steam-arm-setup --remove

Removes what setup added and retains client folder with games unless deletion
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
