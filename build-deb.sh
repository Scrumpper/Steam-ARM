#!/bin/sh
# build-deb.sh: assemble the package tree from the files in this repository and build
# steam-arm-setup_2.3.1_arm64.deb with dpkg-deb. Same sources and dpkg-deb version give a byte-identical package.
set -e

VERSION=2.3.1
PKG=steam-arm-setup
DEB="${PKG}_${VERSION}_arm64.deb"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

command -v dpkg-deb >/dev/null 2>&1 || {
    echo "build-deb.sh: dpkg-deb not found. Install the dpkg package and try again." >&2
    exit 1
}

# file times from the top doc/changelog entry unless SOURCE_DATE_EPOCH is set (reproducible builds)
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    CDATE=$(sed -n '/^ -- /{p;q}' "$SCRIPT_DIR/doc/changelog" | sed -n 's/^ -- .*>  //p')
    [ -n "$CDATE" ] && SOURCE_DATE_EPOCH=$(date -d "$CDATE" +%s 2>/dev/null) || {
        echo "build-deb.sh: no date in the top doc/changelog entry" >&2
        exit 1
    }
fi
export SOURCE_DATE_EPOCH
umask 022

WORK=$(mktemp -d) || { echo "build-deb.sh: could not create a temporary directory" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT INT TERM

TREE="$WORK/$PKG"

mkdir -p "$TREE/DEBIAN"
mkdir -p "$TREE/usr/bin"
mkdir -p "$TREE/usr/share/$PKG"
mkdir -p "$TREE/usr/share/doc/$PKG"
mkdir -p "$TREE/usr/share/applications"

install -m 0755 "$SCRIPT_DIR/steam-arm-install.sh" "$TREE/usr/share/$PKG/install.sh"
install -m 0755 "$SCRIPT_DIR/bin/steam-arm-setup" "$TREE/usr/bin/steam-arm-setup"
install -m 0644 "$SCRIPT_DIR/debian/steam-arm-setup.desktop" "$TREE/usr/share/applications/steam-arm-setup.desktop"

install -m 0755 "$SCRIPT_DIR/debian/postinst" "$TREE/DEBIAN/postinst"
install -m 0755 "$SCRIPT_DIR/debian/prerm" "$TREE/DEBIAN/prerm"

install -m 0644 "$SCRIPT_DIR/doc/README.md" "$TREE/usr/share/doc/$PKG/README.md"
install -m 0644 "$SCRIPT_DIR/doc/copyright" "$TREE/usr/share/doc/$PKG/copyright"
gzip -9n -c "$SCRIPT_DIR/doc/changelog" > "$TREE/usr/share/doc/$PKG/changelog.Debian.gz"
chmod 0644 "$TREE/usr/share/doc/$PKG/changelog.Debian.gz"

# Installed-Size in KiB (each file rounded up to KiB, folders not counted) after Architecture
SIZE=$(find "$TREE/usr" -type f -printf '%s\n' | awk '{ s += int(($1 + 1023) / 1024) } END { print s + 0 }')
sed "s/^Architecture: .*/&\nInstalled-Size: $SIZE/" "$SCRIPT_DIR/debian/control" > "$TREE/DEBIAN/control"
chmod 0644 "$TREE/DEBIAN/control"
(cd "$TREE" && find usr -type f -print0 | LC_ALL=C sort -z | xargs -0 md5sum) > "$TREE/DEBIAN/md5sums"
chmod 0644 "$TREE/DEBIAN/md5sums"

find "$TREE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
dpkg-deb --build -Zgzip --root-owner-group "$TREE" "$SCRIPT_DIR/$DEB"

echo "build-deb.sh: built $SCRIPT_DIR/$DEB"
