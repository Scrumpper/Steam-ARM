# Contributing

## Building

Package is built with:

```
./build-deb.sh
```

This requires `dpkg-deb` and produces `steam-arm-setup_<version>_arm64.deb` plus
`steam-arm-setup_<version>_arm64.deb.sha256` (single line, `<sha256>  <file name>`). Same
sources and `dpkg-deb` version give matching bytes; `tools/release-gates.sh` builds twice
and compares.

## Release assets

Each release lists `Steam.ARM.<version>.zip`, `Steam.ARM.<version>.zip.sha256`,
`steam-arm-setup_<version>_arm64.deb`, `steam-arm-setup_<version>_arm64.deb.sha256` and docs.
Settings menu upgrade depends on these names and on sidecar form; package installs upgrade
from `.deb` asset.

## Rebuilding release files

`tools/release.sh` rebuilds four release files from checkout: `Steam.ARM.<version>.zip`,
`Steam.ARM.<version>.zip.sha256`, `steam-arm-setup_<version>_arm64.deb` and
`steam-arm-setup_<version>_arm64.deb.sha256`. It needs Info-ZIP `zip` 3.0 and `dpkg-deb` (host, or
Debian rootfs from `tools/gates/fetch-debian.sh`).

Menu screenshot (`installer-menu.png` in zip) is not held in repository. Take it from published zip;
script refuses any file with other sha256:

```
curl -fLO https://github.com/Scrumpper/Steam-ARM/releases/download/steam-arm-v3.1/Steam.ARM.3.1.zip
unzip -p Steam.ARM.3.1.zip "Steam ARM 3.1/installer-menu.png" > installer-menu.png
tools/release.sh --check --menu-png installer-menu.png out
```

Run from release source; later change to installer, docs or package files changes digests.
`--check` compares digests with published values and exits 1 on any difference. Expected for 3.1:

```
installer-menu.png                    ad2ff7df067340631eea1b42315925d5b9058fc2eaffbd1183f4b16e882ff164
Steam.ARM.3.1.zip                     66ffbe9ee8d088e8a868e8cc1815eca9d78af7dee779a3acb41997ca5ba022a9
Steam.ARM.3.1.zip.sha256              555cc4f7d4a23312e285dcab6538d865b0dd6ad080998bfb76305ffb62807ed9
steam-arm-setup_3.1_arm64.deb         1fe5be36e13600fb7a01e994e930b6f849d753e0ea40d5a15bca765571e90acb
steam-arm-setup_3.1_arm64.deb.sha256  e02493a23909debd6ca22b5a1c12ff3e1010ae703a97b4ee7ba4e491db91fc7a
```

Zip holds nine repository files and one screenshot, inside folder `Steam ARM 3.1`, in set order, modes 664
(installer 775), entry time 2026-10-25 00:00 UTC, no extra fields (`zip -X -D`). Package comes from
`build-deb.sh`; file times follow top `doc/changelog` entry. `tests/test_release_31.sh` covers
determinism and zip layout.

## Testing change

1. Build package with `./build-deb.sh`.
2. Install built package: `sudo dpkg -i steam-arm-setup_*_arm64.deb`.
3. Run `steam-arm-setup --list` and verify component list matches change.
4. Check `steam-arm-setup --help` output and confirm usage text is correct.
5. Remove package: `sudo apt-get purge steam-arm-setup`.

## Required checks

`steam-arm-install.sh` must pass:

```
bash -n steam-arm-install.sh
```

before pull request is opened. This is also enforced in CI.

## Compatibility reports

Reports of device working, or not working, belong in compatibility issue template, not in pull request. Compatibility data collected there feeds `COMPATIBILITY.md`.

## Scope of changes

`steam-arm-install.sh` is close to 1400 lines and is installer for every component listed in `README.md`. Keep changes minimal, scoped to single component or concern, and explain in pull request what change does and why it is needed.

---

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
