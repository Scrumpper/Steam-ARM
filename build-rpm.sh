#!/bin/sh
# build-rpm.sh: assemble the package tree from the files in this repository and build
# steam-arm-setup-3.1-1.aarch64.rpm with rpmbuild, plus its release sidecar
# steam-arm-setup-3.1-1.aarch64.rpm.sha256.
set -e

VERSION=3.1
PKG=steam-arm-setup
RPM="${PKG}-${VERSION}-1.aarch64.rpm"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

command -v rpmbuild >/dev/null 2>&1 || {
    echo "build-rpm.sh: rpmbuild not found. Install rpm (Debian) or rpm-build (Fedora) and try again." >&2
    exit 1
}

# file times from the top doc/changelog entry unless SOURCE_DATE_EPOCH is set (reproducible builds)
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    CDATE=$(sed -n '/^ -- /{p;q}' "$SCRIPT_DIR/doc/changelog" | sed -n 's/^ -- .*>  //p')
    [ -n "$CDATE" ] && SOURCE_DATE_EPOCH=$(date -d "$CDATE" +%s 2>/dev/null) || {
        echo "build-rpm.sh: no date in the top doc/changelog entry" >&2
        exit 1
    }
fi
export SOURCE_DATE_EPOCH
umask 022

WORK=$(mktemp -d) || { echo "build-rpm.sh: could not create a temporary directory" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT INT TERM

TREE="$WORK/payload"

mkdir -p "$TREE/usr/bin"
mkdir -p "$TREE/usr/share/$PKG"
mkdir -p "$TREE/usr/share/doc/$PKG"
mkdir -p "$TREE/usr/share/licenses/$PKG"
mkdir -p "$TREE/usr/share/applications"

install -m 0755 "$SCRIPT_DIR/steam-arm-install.sh" "$TREE/usr/share/$PKG/install.sh"
install -m 0755 "$SCRIPT_DIR/bin/steam-arm-setup" "$TREE/usr/bin/steam-arm-setup"
install -m 0644 "$SCRIPT_DIR/debian/steam-arm-setup.desktop" "$TREE/usr/share/applications/steam-arm-setup.desktop"

install -m 0644 "$SCRIPT_DIR/doc/README.md" "$TREE/usr/share/doc/$PKG/README.md"
install -m 0644 "$SCRIPT_DIR/doc/copyright" "$TREE/usr/share/licenses/$PKG/copyright"
gzip -9n -c "$SCRIPT_DIR/doc/changelog" > "$TREE/usr/share/doc/$PKG/changelog.gz"
chmod 0644 "$TREE/usr/share/doc/$PKG/changelog.gz"

find "$TREE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

rpmbuild -bb \
    --define "_topdir $WORK/rpmbuild" \
    --define "payload $TREE" \
    --define "_rpmfilename $RPM" \
    "$SCRIPT_DIR/rpm/$PKG.spec"

cp "$WORK/rpmbuild/RPMS/$RPM" "$SCRIPT_DIR/$RPM"
# release sidecar: one line "<sha256>  <file name>"
(cd "$SCRIPT_DIR" && sha256sum "$RPM" > "$RPM.sha256")

echo "build-rpm.sh: built $SCRIPT_DIR/$RPM and $RPM.sha256"
