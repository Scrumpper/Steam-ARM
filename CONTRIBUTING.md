# Contributing

## Building

Package is built with:

```
./build-deb.sh
```

This requires `dpkg-deb` and produces `steam-arm-setup_<version>_arm64.deb`.

## Testing change

1. Build package with `./build-deb.sh`.
2. Install built package: `sudo dpkg -i steam-arm-setup_*_arm64.deb`.
3. Run `steam-arm-setup --list` and confirm component list matches change.
4. Run `steam-arm-setup --help` and confirm usage text is correct.
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

`steam-arm-install.sh` is close to 1400 lines and is installer for every component listed in `README.md`. Keep changes minimal, scoped to one component or concern at time, and explain in pull request what change does and why it is needed.

---

This project is not affiliated with, endorsed by or sponsored by Valve Corporation. Steam,
Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
