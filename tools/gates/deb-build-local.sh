#!/bin/bash
# deb-build-local.sh VERSION [OUT.deb] [SOURCE_DIR]: run SOURCE_DIR's build-deb.sh (default: VERSION-work) with Debian's
# dpkg-deb in a rootless chroot of debian:trixie-slim (fetched once by fetch-debian.sh); no box, no root. Internal.
set -e
T=$(cd "$(dirname "$0")" && pwd)
V=${1:?version}; PROJ=$(dirname "$T")
SRC=${3:-$PROJ/$V-work}; OUT=${2:-${SARM_TOOLS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sarm-tools}/steam-arm-setup_${V}_arm64.deb}
R=$(bash "$T/fetch-debian.sh" trixie-slim | tail -n 1)
B=$R/build; rm -rf "$B"; mkdir -p "$B"
for f in steam-arm-install.sh build-deb.sh bin debian doc; do cp -a "$SRC/$f" "$B/"; done
unshare -r chroot "$R" /bin/sh -c 'cd /build && PATH=/usr/sbin:/usr/bin:/sbin:/bin sh ./build-deb.sh' >/dev/null
mv -f "$B"/steam-arm-setup_*_arm64.deb "$OUT"
rm -rf "$B"
echo "$OUT"
