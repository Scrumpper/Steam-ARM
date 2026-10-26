#!/bin/bash
# tools/release.sh: screenshot pin enforced, two builds byte-identical, zip layout (entry order, folder, modes, DOS time,
# no extra fields), sidecar form, --check flags digest difference. SKIP without Info-ZIP zip 3.0 or dpkg-deb/rootfs.
. "$(dirname "$0")/paths.sh"; WORK=$(dirname "$SARM_INST")
R=$WORK/tools/release.sh V=$SARM_VERSION
T=$(mktemp -d /tmp/sarm31-release.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -n 6; fail=$((fail + 1)); fi; }

check "release.sh parses (bash -n)" "bash -n '$R'"
if ! zip -v 2>/dev/null | grep -q '^This is Zip 3\.0 '; then echo "SKIP release builds: no Info-ZIP zip 3.0"; echo "release: $pass pass, $fail fail"; exit $((fail > 0)); fi
if ! command -v dpkg-deb >/dev/null && [ ! -x "$SARM_ROOTFS/usr/bin/dpkg-deb" ]; then
  echo "SKIP release builds: no dpkg-deb and no Debian rootfs"; echo "release: $pass pass, $fail fail"; exit $((fail > 0)); fi
printf '\x89PNG\r\n\x1a\nnot a screenshot\n' > "$T/menu.png"
OUT=$(bash "$R" --menu-png "$T/menu.png" "$T/o0" 2>&1); RC=$?
check "screenshot with other sha256 refused without --any-png" "[ $RC != 0 ] && grep -q 'menu screenshot' <<<\"\$OUT\" && [ ! -e '$T/o0/Steam.ARM.$V.zip' ]"
OUT=$(bash "$R" --menu-png "$T/missing.png" "$T/o0" 2>&1); RC=$?
check "missing screenshot refused" "[ $RC != 0 ] && grep -q 'not found' <<<\"\$OUT\""
ZN=Steam.ARM.$V.zip DN=steam-arm-setup_${V}_arm64.deb
OUT=$(bash "$R" --any-png --menu-png "$T/menu.png" "$T/o1" 2>&1 && bash "$R" --any-png --menu-png "$T/menu.png" "$T/o2" 2>&1); RC=$?
check "two builds succeed" "[ $RC = 0 ]"
same=1; for f in "$ZN" "$ZN.sha256" "$DN" "$DN.sha256"; do [ -s "$T/o1/$f" ] && cmp -s "$T/o1/$f" "$T/o2/$f" || same=0; done
check "two builds: four files present and byte-identical" "[ $same = 1 ]"
for f in "$ZN" "$DN"; do
  check "sidecar $f.sha256: one line '<sha256>  $f'" "[ \"\$(cat '$T/o1/$f.sha256')\" = \"\$(sha256sum < '$T/o1/$f' | cut -c1-64)  $f\" ] && [ \$(wc -l < '$T/o1/$f.sha256') = 1 ]"
done
OUT=$(python3 - "$T/o1/$ZN" "$V" "$SARM_INST" "$T/menu.png" "$R" <<'PY' 2>&1
import re, sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); top = "Steam ARM %s/" % sys.argv[2]
want = ["RESEARCH.md", "CHANGELOG.md", "README.md", "CREDITS.md", "COMPARISON.md", "COMPATIBILITY.md", "GAMES.md",
        "steam-arm-install.sh", "FEATURES.md", "installer-menu.png"]
inf = z.infolist()
# expected entry time: ZTIME of this version's case in release.sh, else default case
src = open(sys.argv[5]).read()
m = re.search(r"\n  %s\)(.*?);;" % re.escape(sys.argv[2]), src, re.S) or re.search(r"\n  \*\)(.*?);;", src, re.S)
zt = re.search(r"ZTIME='(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)'", m.group(1)).groups()
want_dt = tuple(int(x) for x in zt)
assert [i.filename for i in inf] == [top + n for n in want], [i.filename for i in inf]
for i in inf:
    mode = (i.external_attr >> 16) & 0o777
    assert mode == (0o775 if i.filename.endswith(".sh") else 0o664), (i.filename, oct(mode))
    assert i.date_time == want_dt, (i.filename, i.date_time, want_dt)
    assert i.extra == b"", i.filename
assert z.comment == b""
assert z.read(top + "steam-arm-install.sh") == open(sys.argv[3], "rb").read()
assert z.read(top + "installer-menu.png") == open(sys.argv[4], "rb").read()
print("layout ok")
PY
)
check "zip: entry order, folder, modes, DOS time, no extra fields, installer and screenshot byte copies" "grep -qx 'layout ok' <<<\"\$OUT\""
if grep -q "^  $V) PIN_PNG=" "$R"; then
  OUT=$(bash "$R" --check --any-png --menu-png "$T/menu.png" "$T/o3" 2>&1); RC=$?
  check "--check: other screenshot gives zip DIFFER and rc 1" "[ $RC = 1 ] && grep -q '^DIFFER .*  $ZN ' <<<\"\$OUT\" && grep -q 'digests differ' <<<\"\$OUT\""
else echo "SKIP --check: no published pins for $V"; fi
echo "release: $pass pass, $fail fail"
exit $((fail > 0))
