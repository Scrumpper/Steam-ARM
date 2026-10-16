#!/bin/bash
# .deb packaging (outline 2a item 28): postinst upgrade notice (paths pointed at temp files in a copy), build-deb.sh
# md5sums, Homepage, Installed-Size, reproducible build; with Debian rootfs SARM_ROOTFS (fetch-debian.sh) also two real
# builds compared and dpkg -i upgrade from previous release package (built from SARM_OLD tree) in a rootless chroot.
. "$(dirname "$0")/paths.sh"; WORK=$(dirname "$SARM_INST")
TOOLS=$SARM_GATES
# NEWV under test, OLDV previous release; SARM_OLDDEB names a package of OLDV (else built from SARM_OLD tree)
NEWV=$SARM_VERSION OLDV=${SARM_PREV:-0.1}
OLDDEB=${SARM_OLDDEB:-}
T=$(mktemp -d /tmp/sarm232-deb.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -n 6; fail=$((fail + 1)); fi; }

check "postinst, prerm, build-deb.sh parse (sh -n)" "sh -n $WORK/debian/postinst && sh -n $WORK/debian/prerm && sh -n $WORK/build-deb.sh"
sed -e "s#/usr/share/steam-arm-setup/install.sh#$T/install.sh#" -e "s#/etc/steam-arm/steam-arm.conf#$T/steam-arm.conf#" \
  "$WORK/debian/postinst" > "$T/postinst"
# prerm: client stays for package and script installs alike (box walk: text said "it installed")
sed -e "s#/etc/steam-arm/steam-arm.conf#$T/prerm.conf#" "$WORK/debian/prerm" > "$T/prerm"; : > "$T/prerm.conf"
OUT=$(sh "$T/prerm" remove 2>&1); RC=$?
check "prerm remove: Steam ARM client stays, no 'it installed', removal command named" "[ $RC = 0 ] && grep -qx 'steam-arm-setup: Steam ARM client and its files stay on this system.' <<<\"\$OUT\" && ! grep -q 'it installed' <<<\"\$OUT\" && grep -q -- '--remove' <<<\"\$OUT\""
rm -f "$T/prerm.conf"; OUT=$(sh "$T/prerm" remove 2>&1)
check "prerm remove without Steam ARM settings: silent" "[ -z \"\$OUT\" ]"
check "postinst copy points at temp files""! grep -q '/etc/steam-arm\|/usr/share/steam-arm-setup' $T/postinst"
printf 'SA_VERSION=%s\nx\nSA_VERSION=%s\n' "$NEWV" "$NEWV" > "$T/install.sh"
pi(){ OUT=$(sh "$T/postinst" "$@" 2>&1); RC=$?; }
pi configure
check "fresh install: install hint, rc 0" "[ $RC = 0 ] && grep -q 'To install the native ARM64 Steam client' <<<\"\$OUT\" && ! grep -q -- --keep <<<\"\$OUT\""
printf 'GAMEUSER=a\nVERSION=%s\n' "$OLDV" > "$T/steam-arm.conf"
pi configure $OLDV
check "upgrade over $OLDV setup: notice names both versions and --keep" "[ $RC = 0 ] && grep -q 'steam-arm-setup $NEWV installed; Steam ARM programs on this system are from $OLDV' <<<\"\$OUT\" && grep -qx '  sudo steam-arm-setup --keep' <<<\"\$OUT\""
check "upgrade notice never runs setup (install.sh only read by sed, steam-arm-setup only echoed)" "[ \$(grep -c 'install\\.sh' $WORK/debian/postinst) = 1 ] && grep -q \"sed -n .*install\\.sh\" $WORK/debian/postinst && ! grep -v '^ *echo ' $WORK/debian/postinst | grep -q 'steam-arm-setup '"
pi configure $NEWV
printf 'VERSION=%s\n' "$NEWV" > "$T/steam-arm.conf"; pi configure $NEWV
check "reinstall, setup already $NEWV: set-up line with --keep, no upgrade notice, no install hint" "[ $RC = 0 ] && grep -q 'Steam ARM $NEWV is set up on this system' <<<\"\$OUT\" && grep -q -- --keep <<<\"\$OUT\" && ! grep -q 'programs on this system are from' <<<\"\$OUT\" && ! grep -q 'To install the native' <<<\"\$OUT\""
printf 'VERSION=%s\n' "$OLDV" > "$T/steam-arm.conf"; pi configure
check "first package install over client set up from zip (conf $OLDV, no old package): upgrade notice" "grep -q 'programs on this system are from $OLDV' <<<\"\$OUT\" && grep -qx '  sudo steam-arm-setup --keep' <<<\"\$OUT\""
# build-deb.sh: top changelog trailer without a parsable date stops the build (dpkg-deb stubbed, nothing built)
mkdir -p "$T/q4/bin" "$T/stub"; cp -r "$WORK/steam-arm-install.sh" "$WORK/build-deb.sh" "$WORK/bin" "$WORK/debian" "$WORK/doc" "$T/q4/"
printf '#!/bin/sh\necho STUB-DPKG-DEB\n' > "$T/stub/dpkg-deb"; chmod +x "$T/stub/dpkg-deb"
sed -i '0,/^ -- \(.*>\)  /s// -- \1 /' "$T/q4/doc/changelog"
OUT=$(env -u SOURCE_DATE_EPOCH PATH="$T/stub:$PATH" sh "$T/q4/build-deb.sh" 2>&1); RC=$?
check "build-deb.sh: one-space changelog trailer -> no date, stops before dpkg-deb" "[ $RC != 0 ] && grep -q 'no date in the top doc/changelog entry' <<<\"\$OUT\" && ! grep -q STUB-DPKG-DEB <<<\"\$OUT\""
cp "$WORK/doc/changelog" "$T/q4/doc/changelog"
OUT=$(env -u SOURCE_DATE_EPOCH PATH="$T/stub:$PATH" sh "$T/q4/build-deb.sh" 2>&1); RC=$?
check "build-deb.sh: dated trailer -> reaches dpkg-deb" "[ $RC = 0 ] && grep -q STUB-DPKG-DEB <<<\"\$OUT\""
rm -f "$T/steam-arm.conf"; pi configure $OLDV
check "upgrade, client never set up: install hint" "[ $RC = 0 ] && grep -q 'To install the native' <<<\"\$OUT\""
rm -f "$T/install.sh"; printf 'VERSION=%s\n' "$OLDV" > "$T/steam-arm.conf"; pi configure $OLDV
check "set -e safe when install.sh missing" "[ $RC = 0 ]"
pi abort-upgrade $NEWV
check "abort-upgrade: silent, rc 0" "[ $RC = 0 ] && [ -z \"\$OUT\" ]"
check "control: Homepage" "grep -qx 'Homepage: https://github.com/Scrumpper/Steam-ARM' $WORK/debian/control"
check "build-deb.sh: md5sums, Installed-Size, SOURCE_DATE_EPOCH, touch, umask" "grep -q 'DEBIAN/md5sums' $WORK/build-deb.sh && grep -q 'Installed-Size' $WORK/build-deb.sh && grep -q 'SOURCE_DATE_EPOCH' $WORK/build-deb.sh && grep -q 'touch -h -d' $WORK/build-deb.sh && grep -qx 'umask 022' $WORK/build-deb.sh"
check "control in repo has no Installed-Size (computed)" "! grep -q '^Installed-Size' $WORK/debian/control"

R=$SARM_ROOTFS
if [ ! -x "$R/usr/bin/dpkg-deb" ]; then
  echo "SKIP chroot cases not run: no Debian rootfs (tools/fetch-debian.sh fetches it)"
else
  A=$(bash "$TOOLS/deb-build-local.sh" "$NEWV" "$T/a.deb" "$WORK" | tail -n 1)
  mkdir -p "$T/src"; cp -r "$WORK/steam-arm-install.sh" "$WORK/build-deb.sh" "$WORK/bin" "$WORK/debian" "$WORK/doc" "$T/src/"
  chmod -R go-w "$T/src"; touch "$T/src/doc/README.md"
  B=$(bash "$TOOLS/deb-build-local.sh" "$NEWV" "$T/b.deb" "$T/src" | tail -n 1)
  check "two builds (other source mtimes) byte-identical" "[ -s $T/a.deb ] && cmp -s $T/a.deb $T/b.deb"
  OD=$(sarm_old "$OLDV" build-deb.sh)
  [ -z "$OLDDEB" ] && [ -n "$OD" ] && OLDDEB=$(bash "$TOOLS/deb-build-local.sh" "$OLDV" "$T/old.deb" "$(dirname "$OD")" | tail -n 1)
  cp "$T/a.deb" "$R/tmp/new.deb"; [ -f "$OLDDEB" ] && cp "$OLDDEB" "$R/tmp/old.deb"
  OUT=$(unshare -r chroot "$R" /bin/sh -c 'cd /tmp; dpkg-deb -f new.deb Homepage Installed-Size; rm -rf x; dpkg-deb -R new.deb x && cd x && md5sum -c --quiet DEBIAN/md5sums && echo MD5OK; cd /tmp; rm -rf x' 2>&1)
  check "built deb: Homepage, Installed-Size, md5sums verify" "grep -q 'Homepage: https://github.com/Scrumpper/Steam-ARM' <<<\"\$OUT\" && grep -qE 'Installed-Size: [0-9]+' <<<\"\$OUT\" && grep -qx MD5OK <<<\"\$OUT\""
  if [ -f "$R/tmp/old.deb" ]; then
    OUT=$(unshare -r chroot "$R" /bin/sh -c 'export PATH=/usr/sbin:/usr/bin:/sbin:/bin; F="--force-architecture --force-depends"
      mkdir -p /etc/steam-arm; dpkg $F -i /tmp/old.deb >/dev/null 2>&1; echo VERSION=$1 > /etc/steam-arm/steam-arm.conf
      dpkg $F -i /tmp/new.deb 2>&1; echo "rc=$?"; dpkg-query -W -f="\${Version}\n" steam-arm-setup
      dpkg $F -P steam-arm-setup >/dev/null 2>&1; rm -rf /etc/steam-arm /tmp/old.deb /tmp/new.deb' sh "$OLDV" 2>&1)
    check "dpkg -i $NEWV over $OLDV with $OLDV setup: notice shown, rc 0, version $NEWV" "grep -q 'Steam ARM programs on this system are from $OLDV' <<<\"\$OUT\" && grep -qx rc=0 <<<\"\$OUT\" && grep -qx $NEWV <<<\"\$OUT\""
  else
    echo "SKIP upgrade case not run: no $OLDV package (SARM_OLDDEB or SARM_OLD tree)"; rm -f "$R/tmp/new.deb"
  fi
fi
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
