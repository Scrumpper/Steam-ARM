#!/bin/bash
# deb-check.sh [SOURCE_DIR]: build-deb.sh run twice on copies with other file times and modes gives byte-identical
# packages; package holds only installer, launcher, desktop entry and docs (no test tooling); packaged installer
# byte-identical to source. Host dpkg-deb, else Debian rootfs chroot (deb-build-local.sh). Exit 1 on any failure.
G=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "${1:-$G/../..}" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok(){ echo "ok   $1"; }; bad(){ echo "FAIL $1"; fail=1; }
ROOTFS=${SARM_ROOTFS:-${SARM_TOOLS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sarm-tools}/trixie-slim-rootfs}
build(){ # build SRC_COPY OUT
  if command -v dpkg-deb >/dev/null; then
    (cd "$1" && env -u SOURCE_DATE_EPOCH sh ./build-deb.sh >"$1.log" 2>&1) && mv "$1"/*.deb "$2"
  elif [ -x "$ROOTFS/usr/bin/dpkg-deb" ]; then
    env -u SOURCE_DATE_EPOCH bash "$G/deb-build-local.sh" 0.0 "$2" "$1" >"$1.log" 2>&1
  else echo "no dpkg-deb on host and no Debian rootfs at $ROOTFS" > "$1.log"; return 1; fi
}
for x in a b; do
  mkdir "$T/$x"; cp -r "$SRC/steam-arm-install.sh" "$SRC/build-deb.sh" "$SRC/bin" "$SRC/debian" "$SRC/doc" "$T/$x/"
done
touch -d '2001-02-03 04:05:06' "$T/b/doc/README.md" "$T/b/bin/steam-arm-setup"; chmod -R go-w "$T/b"; chmod -R g+w "$T/a"
for x in a b; do build "$T/$x" "$T/$x.deb" || { sed 's/^/       /' "$T/$x.log"; bad "package build ($x) failed"; }; done
[ -s "$T/a.deb" ] && [ -s "$T/b.deb" ] || { echo "deb-check: FAILED"; exit 1; }
if cmp -s "$T/a.deb" "$T/b.deb"; then ok "two builds byte-identical ($(sha256sum < "$T/a.deb" | cut -c1-16))"; else bad "two builds differ"; fi
G=$G python3 - "$T/a.deb" "$SRC/steam-arm-install.sh" <<'EOF' || fail=1
import os, re, sys
sys.path.insert(0, os.environ["G"])
import debfile
d = debfile.Deb(sys.argv[1])
bad = 0
def check(name, cond, info=""):
    global bad
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else "  " + str(info)))
    bad += not cond
files = sorted(e[0] for e in d.entries() if e[5] != b"5" and e[5] != "5")
want = ["./usr/bin/steam-arm-setup", "./usr/share/applications/steam-arm-setup.desktop",
        "./usr/share/doc/steam-arm-setup/README.md", "./usr/share/doc/steam-arm-setup/changelog.Debian.gz",
        "./usr/share/doc/steam-arm-setup/copyright", "./usr/share/steam-arm-setup/install.sh"]
check("package files: installer, launcher, desktop entry, docs only", files == want, files)
ctl = sorted(m.name.lstrip("./") for m in d.control.getmembers() if m.isfile())
check("control members: control md5sums postinst prerm", ctl == ["control", "md5sums", "postinst", "prerm"], ctl)
tt = [n for n, *_ in d.entries() if re.search(r"(?i)test|fixture|shim|stub|mock|bench|\.orig|config-ui", n)]
check("no test tooling names in package", not tt, tt)
check("packaged install.sh = steam-arm-install.sh", d.member("./usr/share/steam-arm-setup/install.sh") == open(sys.argv[2], "rb").read())
sys.exit(1 if bad else 0)
EOF
[ $fail = 0 ] && echo "deb-check: all passed" || echo "deb-check: FAILED"
exit $fail
