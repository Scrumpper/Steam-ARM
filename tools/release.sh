#!/bin/bash
# release.sh [--check] [--any-png] --menu-png PNG OUTDIR: rebuild release files of this checkout into OUTDIR:
# Steam.ARM.<V>.zip, Steam.ARM.<V>.zip.sha256, steam-arm-setup_<V>_arm64.deb, steam-arm-setup_<V>_arm64.deb.sha256.
# PNG is installer menu screenshot (installer-menu.png in zip), not held in repository; its sha256 must match pin below
# unless --any-png (test builds). --check: compare four digests with published pins below, exit 1 on any difference.
# Needs Info-ZIP zip 3.0 and dpkg-deb (host, else Debian rootfs from tools/gates/fetch-debian.sh). SARM_ROOTFS picks rootfs.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G=$ROOT/tools/gates
usage(){ echo "usage: $0 [--check] [--any-png] --menu-png PNG OUTDIR" >&2; exit 2; }
CHECK=0 ANY=0 PNG=${SARM_MENU_PNG:-} OUT=
while [ $# -gt 0 ]; do
  case $1 in
    --check) CHECK=1 ;;
    --any-png) ANY=1 ;;
    --menu-png) [ $# -ge 2 ] || usage; PNG=$2; shift ;;
    -h|--help) sed -n '2,6s/^# //p' "$0"; exit 0 ;;
    -*) usage ;;
    *) [ -z "$OUT" ] || usage; OUT=$1 ;;
  esac
  shift
done
[ -n "$OUT" ] && [ -n "$PNG" ] || usage

V=$(sed -n 's/^VERSION=//p' "$ROOT/build-deb.sh" | head -n 1)
IV=$(sed -n 's/^SA_VERSION=//p' "$ROOT/steam-arm-install.sh" | head -n 1)
[ -n "$V" ] && [ "$V" = "$IV" ] || { echo "release.sh: build-deb.sh VERSION ($V) and installer SA_VERSION ($IV) differ" >&2; exit 1; }

# published pins per version: menu screenshot, zip, zip sidecar, package, package sidecar
case $V in
  3.1) PIN_PNG=ad2ff7df067340631eea1b42315925d5b9058fc2eaffbd1183f4b16e882ff164
       PIN_ZIP=c2b36aa86bf21f013d8fa8864ef68ded3ea1c6f8cb50d78d293c934cd34d7ac6
       PIN_ZIPSHA=8ebc6d0567233ade7babc560df59697a19046fb6a66e576e82669798915c86bd
       PIN_DEB=1fe5be36e13600fb7a01e994e930b6f849d753e0ea40d5a15bca765571e90acb
       PIN_DEBSHA=e02493a23909debd6ca22b5a1c12ff3e1010ae703a97b4ee7ba4e491db91fc7a
       ZTIME='2026-10-24 17:00:00' ;;
  3.2) PIN_PNG=d8fe02615cc17f0e7cfac6b8d06e50c86e26c39b036b5fe34af278050b143065
       PIN_ZIP=bd9a2b9b80a1f4cb689d7909f46211d921a82585167adfd618ca525184e92825
       PIN_ZIPSHA=9af9547885b2355a5a2154f25dc500413ace4b79d402d3384a7a63d2249729d4
       PIN_DEB=9c792c76b2e4eb471c636e1516b03ff115495998bfae3529f61ff3d14bf70568
       PIN_DEBSHA=fa76667c1f85be123a068068e5e8f6ebb6085e5dae8a12437cb87e855286bf09
       ZTIME='2026-10-25 17:00:00' ;;
  *) PIN_PNG= PIN_ZIP= PIN_ZIPSHA= PIN_DEB= PIN_DEBSHA=
     ZTIME='2026-10-25 17:00:00' ;;
esac

command -v zip >/dev/null || { echo "release.sh: zip (Info-ZIP) not found" >&2; exit 1; }
zip -v 2>/dev/null | grep -q '^This is Zip 3\.0 ' || { echo "release.sh: Info-ZIP zip 3.0 required" >&2; exit 1; }
[ -f "$PNG" ] || { echo "release.sh: menu screenshot not found: $PNG" >&2; exit 1; }
PSHA=$(sha256sum < "$PNG" | cut -c1-64)
if [ $ANY = 0 ]; then
  [ -n "$PIN_PNG" ] || { echo "release.sh: no menu screenshot pin for $V (use --any-png)" >&2; exit 1; }
  [ "$PSHA" = "$PIN_PNG" ] || { echo "release.sh: menu screenshot sha256 $PSHA, expected $PIN_PNG" >&2; exit 1; }
fi

mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
ZN=Steam.ARM.$V.zip DN=steam-arm-setup_${V}_arm64.deb TOP="Steam ARM $V"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# zip: entry order, modes and time are part of published bytes
FILES="RESEARCH.md CHANGELOG.md README.md CREDITS.md COMPARISON.md COMPATIBILITY.md GAMES.md steam-arm-install.sh FEATURES.md"
mkdir "$T/z" "$T/z/$TOP"
for f in $FILES; do cp "$ROOT/$f" "$T/z/$TOP/$f"; done
cp "$PNG" "$T/z/$TOP/installer-menu.png"
chmod 0664 "$T/z/$TOP"/*; chmod 0775 "$T/z/$TOP/steam-arm-install.sh"
# zip stores local DOS time under TZ UTC0; ZTIME per version (3.1: 2026-10-24 17:00)
export TZ=UTC0
touch -d "$ZTIME" "$T/z/$TOP"/*
set --; for f in $FILES installer-menu.png; do set -- "$@" "$TOP/$f"; done
rm -f "$OUT/$ZN"
(cd "$T/z" && zip -q -X -D "$OUT/$ZN" "$@")
(cd "$OUT" && echo "$(sha256sum < "$ZN" | cut -c1-64)  $ZN" > "$ZN.sha256")

# package: build-deb.sh on copy (it writes next to itself)
mkdir "$T/d"; cp -r "$ROOT/steam-arm-install.sh" "$ROOT/build-deb.sh" "$ROOT/bin" "$ROOT/debian" "$ROOT/doc" "$T/d/"
ROOTFS=${SARM_ROOTFS:-${SARM_TOOLS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sarm-tools}/trixie-slim-rootfs}
if command -v dpkg-deb >/dev/null; then
  (cd "$T/d" && env -u SOURCE_DATE_EPOCH sh ./build-deb.sh >"$T/deb.log" 2>&1) || { cat "$T/deb.log" >&2; exit 1; }
  mv "$T/d/$DN" "$OUT/$DN"
elif [ -x "$ROOTFS/usr/bin/dpkg-deb" ]; then
  env -u SOURCE_DATE_EPOCH bash "$G/deb-build-local.sh" "$V" "$OUT/$DN" "$T/d" >"$T/deb.log" 2>&1 || { cat "$T/deb.log" >&2; exit 1; }
else echo "release.sh: no dpkg-deb on host and no Debian rootfs at $ROOTFS" >&2; exit 1; fi
(cd "$OUT" && echo "$(sha256sum < "$DN" | cut -c1-64)  $DN" > "$DN.sha256")

bad=0
for n in "$ZN:$PIN_ZIP" "$ZN.sha256:$PIN_ZIPSHA" "$DN:$PIN_DEB" "$DN.sha256:$PIN_DEBSHA"; do
  f=${n%%:*} p=${n#*:} s=$(sha256sum < "$OUT/${n%%:*}" | cut -c1-64)
  if [ $CHECK = 0 ]; then echo "$s  $f"
  elif [ "$s" = "$p" ]; then echo "match  $s  $f"
  else echo "DIFFER $s  $f  (published ${p:-none})"; bad=1; fi
done
[ $CHECK = 0 ] || { [ $bad = 0 ] && echo "release.sh $V: all four files match published digests" || echo "release.sh $V: digests differ"; }
exit $bad
