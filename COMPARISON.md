# Steam ARM · How routes compare

Routes for running Steam on ARM64 hardware, side by side. Updated as routes change and as
reports come in.

**Last updated:** 2026-09-26

Legend: ✅ yes  ⚠️ partly, or with conditions  ❌ no  ❓ not publicly verified

| Route                      | Client itself is native ARM | Installs onto your system | Mali and PanVK                      | Adreno                                                          | Apple GPU                              | Remote Play handled                 |
|----------------------------|-----------------------------|---------------------------|-------------------------------------|-----------------------------------------------------------------|----------------------------------------|-------------------------------------|
| **This package**           | ✅                          | ✅ host, no sandbox       | ✅ tested on one RK3588 board       | ⚠️ community report: Radxa Dragon Q6A (QCS6490), `vk-spoof` off | ⚠️ untested, needs 4K page environment | ✅ decode pinned before first start |
| Canonical arm64 Steam snap | ❌ x86 client under FEX     | ⚠️ snap confinement       | ❌ open issue #471 since 2026-01-10 | ⚠️ other driver loading bugs open                               | ❓                                     | ❓                                  |
| Box86 and Box64            | ❌ x86 client under Box64   | ✅ host                   | ✅ long standing SBC route          | ✅                                                              | ❓                                     | ❓                                  |
| steamclienttermux, Android | ✅                          | ⚠️ Termux and PRoot       | ❌ Adreno only                      | ✅ Turnip                                                       | ❌                                     | ❓                                  |
| ROCKNIX and pocknix-os     | ✅                          | ❌ replaces OS            | ❌ Snapdragon only                  | ✅                                                              | ❌                                     | ❓                                  |
| UbuntuAsahi `steam-arm64`  | ✅                          | ✅ host, in microVM       | ❌                                  | ❌                                                              | ✅ Honeykrisp                          | ❓                                  |
| Windows on ARM, Prism      | ❌ x86 under Prism          | ✅ host                   | ❌                                  | ✅ Snapdragon X                                                 | ❌                                     | ✅ native to Windows                |
| macOS on Apple Silicon     | ✅ since 2025-06 beta       | ✅ host                   | ❌                                  | ❌                                                              | ✅                                     | ✅                                  |

Reading table: routes that run **native** client are this package, Android and
handheld projects, UbuntuAsahi, and macOS. Of those, everything except this one targets
Adreno or Apple GPUs. Routes that cover Mali at all run **x86** client under
emulation, or fail on driver.

## Reports for this package

| Date       | Hardware                             | GPU and driver   | Result                                                                                          | Source                    |
|------------|--------------------------------------|------------------|-------------------------------------------------------------------------------------------------|---------------------------|
| 2026-09-23 | H96 Max V58, RK3588                  | Mali-G610, PanVK | Tested configuration                                                                            | project                   |
| 2026-09-26 | Radxa Dragon Q6A, Snapdragon QCS6490 | Adreno, Turnip   | Client and games run; PS4 pad works; `glx-lax` and `vk-spoof` skipped; overlay and MangoHud off | Armbian forum user report |

## Updating this document

- Change cell only on report that names hardware, driver and what was run.
- Add each report to table above, with date and source.
- Other routes' cells cite their project's own issue tracker or release notes.
- Change **Last updated** date.

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
