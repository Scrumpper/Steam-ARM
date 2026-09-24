# Changelog

All notable changes to this project are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
