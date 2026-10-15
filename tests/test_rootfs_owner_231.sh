#!/bin/bash
# 2.3.1 RootFS owner: rfs_root_own (extracted from the installer copy, SARM_INST picks another) on fake trees inside a
# rootless user namespace with subordinate ids (unshare --map-root-user --map-auto), so files of uid 1000 exist there;
# call site after the Mali tree step; programs that run as the game account never write into the trees. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
# files of mapped ids are removed inside a namespace too
T=$(mktemp -d /tmp/sarm232-rfs.XXXXXX); trap 'unshare --map-root-user --map-auto rm -rf "$T" 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }
has(){ grep -qF -- "$1" <<<"$OUT"; }

check "installer parses (bash -n)" "bash -n '$INST'"
fn rfs_root_own "$INST" > "$T/f.sh"
check "rfs_root_own extracted" "grep -q '^rfs_root_own()' $T/f.sh"
if ! unshare --map-root-user --map-auto true 2>/dev/null; then
  echo "SKIP namespace cases not run: unshare --map-auto unavailable (newuidmap, /etc/subuid)"
else
# whole case inside the namespace; prints facts as key=value lines
cat > "$T/case.sh" <<'EOF'
. "$1/f.sh"
R=$1/opt/Ubuntu_24_04 M=$1/opt/Ubuntu_24_04-mali O=$1/outside
mkdir -p "$R/usr/bin" "$R/usr/lib" "$O"
echo x > "$R/usr/bin/bash"; echo s > "$R/usr/bin/sudo"; echo g > "$R/usr/bin/wall"
echo keep > "$O/host-file"; ln -s "$O/host-file" "$R/usr/lib/link-out"
chown -R -h 1000:1000 "$R" "$O"
# set after chown (chown clears them)
chmod 4755 "$R/usr/bin/sudo"; chmod 2755 "$R/usr/bin/wall"
# Mali tree: hard links of RootFS (cp -al), own folder and archive file
cp -al "$R" "$M"; echo mesa > "$M/usr/lib/libvulkan_panfrost.so"; chown -h 0:0 "$M/usr/lib/libvulkan_panfrost.so"
echo "R1out=$(rfs_root_own "$R" | tr '\n' '|') rc1=$?"
echo "M1out=$(rfs_root_own "$M" | tr '\n' '|') rc2=$?"
echo "owners=$(find "$R" "$M" -xdev \( ! -uid 0 -o ! -gid 0 \) | wc -l)"
echo "outside=$(stat -c %u:%g "$O/host-file") linkowner=$(stat -c %u "$R/usr/lib/link-out")"
echo "sbits=$(find "$R" -type f -perm /6000 | wc -l) sudo=$(stat -c %a "$R/usr/bin/sudo") wall=$(stat -c %a "$R/usr/bin/wall")"
echo "bash=$(cat "$R/usr/bin/bash") mlink=$(stat -c %h "$M/usr/bin/bash")"
c1=$(stat -c %Z "$R/usr/bin/bash"); sleep 1
echo "again=[$(rfs_root_own "$R")] rc3=$? ctime_same=$([ "$(stat -c %Z "$R/usr/bin/bash")" = "$c1" ] && echo 1 || echo 0)"
echo "missing=[$(rfs_root_own "$1/none")] rc4=$?"
ln -s "$O" "$1/opt/linktree"; echo "linktree=[$(rfs_root_own "$1/opt/linktree")] rc5=$? lt=$(stat -c %u "$O")"
# root-owned tree with set-user-ID file only
mkdir -p "$1/opt/T2/usr/bin"; echo s > "$1/opt/T2/usr/bin/su"; chmod 4755 "$1/opt/T2/usr/bin/su"
echo "T2=[$(rfs_root_own "$1/opt/T2" | tr '\n' '|')] su=$(stat -c %a "$1/opt/T2/usr/bin/su")"
EOF
OUT=$(unshare --map-root-user --map-auto bash "$T/case.sh" "$T" 2>&1)
check "R1 RootFS of uid 1000: owned by root, logged, status 0" "has 'R1out=  $T/opt/Ubuntu_24_04 owned by root now (was owned by another account)|' && has 'rc1=0'"
check "R2 Mali tree (hard links + own folders): owned by root, every file and folder of both trees" "has 'M1out=  $T/opt/Ubuntu_24_04-mali owned by root now' && has 'owners=0'"
check "R3 link to file outside tree: link changed, target untouched" "has 'outside=1000:1000 linkowner=0'"
check "R4 set-user-ID and set-group-ID bits gone, content and hard links kept" "has 'sbits=0 sudo=755 wall=755' && has 'bash=x mlink=2'"
check "R5 second run: nothing to do, silent, no change" "has 'again=[] rc3=0 ctime_same=1'"
check "R6 missing tree and tree path that is a link: left alone" "has 'missing=[] rc4=0' && has 'linktree=[] rc5=0 lt=1000'"
check "R7 root-owned tree with set-user-ID file: bit removed, logged" "has 'set-user-ID and set-group-ID bits removed in $T/opt/T2|] su=755'"
fi
# call site: every setup run (upgrade fixes earlier trees), after Mali tree step, before FEX user config
ln_of(){ grep -n -m1 -F -- "$1" "$INST" | cut -d: -f1; }
LC=$(ln_of '  rfs_root_own "$t" || warn'); LF=$((${LC:-1} - 1)); LB=$(ln_of '  mali_tree_build'); LU=$(ln_of 'as_user mkdir -p "$UHOME/.fex-emu"')
check "R8 call for RootFS and Mali tree after Mali tree step, before FEX user config, not behind a component" "[ -n \"$LC\" ] && [ ${LB:-0} -lt $LF ] && [ $LC -lt ${LU:-0} ] && sed -n \"\${LF}p\" '$INST' | grep -qx 'for t in \"\$RFS\" \"\$MALI\"; do' && awk -v l=$LF 'NR==l-1' '$INST' | grep -q '^fi\$'"
# programs of the game account (launcher, handler, run helper, x86 client helper, tray) only read the trees
BAD=$(python3 - "$INST" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
bad = []
for tag in ("LAUNCHER", "HANDLERPY", "RUNPY", "X86PY", "TRAYPY"):
    m = re.search(r"<<'%s'\n(.*?)\n%s\n" % (tag, tag), s, re.S)
    if not m:
        bad.append(tag + ": not found")
        continue
    for l in m.group(1).splitlines():
        if ("fex-rootfs" in l or "MALI_ROOT" in l) and re.search(
                r">\s*\S*fex-rootfs|\b(mv|cp|rm|mkdir|chmod|chown|ln|touch|tee)\s|open\([^)]*['\"][wa]|os\.(rename|replace|remove|unlink|makedirs|mkdir|chmod)|shutil\.", l):
            bad.append(tag + ": " + l.strip())
print("\n".join(bad))
EOF
)
OUT=$BAD; check "R9 launcher, handler, run helper, x86 client helper, tray: no write into /opt/fex-rootfs" "[ -z \"\$BAD\" ]"
echo "rootfs owner 2.3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
