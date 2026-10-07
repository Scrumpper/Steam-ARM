#!/bin/sh
# build-deb.sh: assemble the package tree from the files in this repository and build
# steam-arm-setup_2.1_arm64.deb with dpkg-deb.
set -e

VERSION=2.1
PKG=steam-arm-setup
DEB="${PKG}_${VERSION}_arm64.deb"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

command -v dpkg-deb >/dev/null 2>&1 || {
    echo "build-deb.sh: dpkg-deb not found. Install the dpkg package and try again." >&2
    exit 1
}

WORK=$(mktemp -d) || { echo "build-deb.sh: could not create a temporary directory" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT INT TERM

TREE="$WORK/$PKG"

mkdir -p "$TREE/DEBIAN"
mkdir -p "$TREE/usr/bin"
mkdir -p "$TREE/usr/share/$PKG"
mkdir -p "$TREE/usr/share/doc/$PKG"

install -m 0755 "$SCRIPT_DIR/steam-arm-install.sh" "$TREE/usr/share/$PKG/install.sh"
install -m 0755 "$SCRIPT_DIR/bin/steam-arm-setup" "$TREE/usr/bin/steam-arm-setup"

install -m 0644 "$SCRIPT_DIR/debian/control" "$TREE/DEBIAN/control"
install -m 0755 "$SCRIPT_DIR/debian/postinst" "$TREE/DEBIAN/postinst"
install -m 0755 "$SCRIPT_DIR/debian/prerm" "$TREE/DEBIAN/prerm"

install -m 0644 "$SCRIPT_DIR/doc/README.md" "$TREE/usr/share/doc/$PKG/README.md"
install -m 0644 "$SCRIPT_DIR/doc/copyright" "$TREE/usr/share/doc/$PKG/copyright"
gzip -9n -c "$SCRIPT_DIR/doc/changelog" > "$TREE/usr/share/doc/$PKG/changelog.Debian.gz"
chmod 0644 "$TREE/usr/share/doc/$PKG/changelog.Debian.gz"

dpkg-deb --build -Zgzip --root-owner-group "$TREE" "$SCRIPT_DIR/$DEB"

echo "build-deb.sh: built $SCRIPT_DIR/$DEB"
