#!/bin/bash
# Steam ARM 3.0 D1 extra Mesa trees: setup functions (tree build from a local archive, sha pin, saved file, rebuild and
# keep rules, deselect, removal) run on a fake RootFS with a fake archive (list entry rewritten to its sha in the
# extract only); option checks of the whole installer; menu: list consistency, profile key, Games and Components
# screens, info row; backup of a 3.0 settings file and titles.conf with mesa= restored by 2.3.2 and 3.0. Internal.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm30-mx.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -n 8; fail=$((fail + 1)); fi; }
command -v zstd >/dev/null 2>&1 || { echo "SKIP extra Mesa suite: zstd missing"; exit 0; }

# ---------- fake archive and RootFS ----------
A=$T/arch; mkdir -p "$A/usr/lib/x86_64-linux-gnu" "$A/usr/lib/i386-linux-gnu"
echo '{}' > "$A/graphics_provider.json"
echo new64 > "$A/usr/lib/x86_64-linux-gnu/libgallium-26.2.4.so"; echo new32 > "$A/usr/lib/i386-linux-gnu/libgallium-26.2.4.so"
(cd "$A" && tar --zstd -cf "$T/steam-arm-fex-mesa-26.2.4-x86_64-i386.tar.zst" .)
ARC=$T/steam-arm-fex-mesa-26.2.4-x86_64-i386.tar.zst; SHA=$(sha256sum "$ARC" | cut -c1-64)
R=$T/opt/fex-rootfs/Ubuntu_24_04; mkdir -p "$R/usr/lib/x86_64-linux-gnu" "$R/usr/lib/i386-linux-gnu" "$R/usr/bin" "$R/var/lib/dpkg/info"
echo libc > "$R/usr/lib/x86_64-linux-gnu/libc.so.6"; echo old64 > "$R/usr/lib/x86_64-linux-gnu/libgallium-26.1.6.so"
printf '/usr/lib/x86_64-linux-gnu/libgallium-26.1.6.so\n' > "$R/var/lib/dpkg/info/mesa-libgallium:amd64.list"
M=$T/opt/fex-rootfs/Ubuntu_24_04-mali; mkdir -p "$M"; echo 'archive x rootfs y' > "$M/.steam-arm-mali"; echo '{}' > "$M/graphics_provider.json"
CONF=$T/steam-arm.conf; : > "$CONF"
( cd "$R" && find . -type f -exec sha256sum {} + | sort ) > "$T/rfs.before"

# setup functions out of the installer; paths and list entry rewritten in the extract only
python3 - "$INST" "$T/fn.sh" "$R" "$M" "$CONF" "$SHA" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
names = ["conf_get", "conf_set", "conf_del", "rfs_id", "parent_in", "unlink_in", "paths_inside", "tree_part", "rfs_guard",
         "mx_entry", "mx_key", "mx_file_name", "mx_match", "mx_present", "mx_save", "mx_build", "mx_sync", "mx_drop_all"]
out = []
for n in names:
    m = re.search(r"^%s\(\)\{.*\}$" % re.escape(n), s, re.M)
    if not m or m.group(0).endswith("(){"):
        m = re.search(r"^%s\(\)\{\n.*?\n\}\n" % re.escape(n), s, re.S | re.M)
    assert m, n
    out.append(m.group(0).rstrip("\n") + "\n")
lst = re.search(r'^MESA_EXTRA_LIST="([^"]*)"', s, re.M).group(1).split()
assert lst[0] == "26.2.4"
head = ('RFS=%s\nMALI=%s\nCONF=%s\nMESA_EXTRA_LIST="26.2.4 %s - 1 1"\nSELF_DIR=""\nCLEANUP=()\nCURL_ENV=()\nCURL_SHOW=(-sS)\n'
        'NETHINT=net\nGUARD_MARK=steam-arm-guard\nPROVIDER_MESA_PKGS="mesa-libgallium"\n'
        'warn(){ echo "[warn] $*"; }\ndie(){ echo "[fail] $*"; exit 1; }\nsteam_up(){ return 1; }\nsay(){ echo "$*"; }\n'
        % (sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]))
open(sys.argv[2], "w").write(head + "".join(out))
EOF
grep -q '^conf_set()' "$T/fn.sh" || { echo "FAIL function extract"; exit 1; }
run(){ OUT=$(bash -c ". $T/fn.sh; MESA_EXTRA_SEL='$1'; MESA_EXTRA_SET=$2; MESA_EXTRA_FILE='$3'; MX_FILE_VER=\$( [ -n '$3' ] && mx_match '$3'); $4" 2>&1); RC=$?; }
has(){ grep -qF -- "$1" <<<"$OUT"; }
E=$M-26.2.4

run "" 0 "$ARC" "mx_sync"
check "M1 local file of listed version: tree built, marker, setting and file path saved" \
  "[ $RC = 0 ] && [ -f $E/graphics_provider.json ] && grep -q '^archive $SHA rootfs ' $E/.steam-arm-mali && grep -qx 'MESA_EXTRA=26.2.4' $CONF && grep -qx 'MESA_EXTRA_FILE_26_2_4=$ARC' $CONF && has 'Mesa 26.2.4 drivers inside the emulation ready'"
check "M2 archive files new inodes, distro Mesa unlinked, RootFS unchanged" \
  "[ \"\$(cat $E/usr/lib/x86_64-linux-gnu/libgallium-26.2.4.so)\" = new64 ] && [ ! -e $E/usr/lib/x86_64-linux-gnu/libgallium-26.1.6.so ] && [ \"\$(stat -c %i $E/usr/lib/x86_64-linux-gnu/libc.so.6)\" = \"\$(stat -c %i $R/usr/lib/x86_64-linux-gnu/libc.so.6)\" ] && diff -q $T/rfs.before <(cd $R && find . -type f -exec sha256sum {} + | sort) >/dev/null"
i0=$(stat -c %i "$E/.steam-arm-mali")
run "" 0 "" "mx_sync"
check "M3 next run, same RootFS: already in place, not rebuilt" "[ $RC = 0 ] && has 'already in place' && [ \"\$(stat -c %i $E/.steam-arm-mali)\" = $i0 ]"
echo libc2 > "$R/usr/lib/x86_64-linux-gnu/libc.so.6.new"; mv "$R/usr/lib/x86_64-linux-gnu/libc.so.6.new" "$R/usr/lib/x86_64-linux-gnu/libc.so.6"
run "" 0 "" "mx_sync"
check "M4 RootFS changed, saved file present: rebuilt from saved file" "[ $RC = 0 ] && has 'rebuilding' && has 'local copy of Mesa 26.2.4 archive: $ARC' && [ \"\$(stat -c %i $E/.steam-arm-mali)\" != $i0 ]"
mv "$ARC" "$ARC.away"; echo x >> "$R/usr/lib/x86_64-linux-gnu/libc.so.6"; touch -d '2001-01-01' "$R/usr/lib/x86_64-linux-gnu/libc.so.6"
run "" 0 "" "mx_sync"
check "M5 RootFS changed, archive gone, version not published: tree kept with warning" "[ $RC = 0 ] && has 'kept as built before' && [ -f $E/graphics_provider.json ]"
run "26.2.4" 1 "" "mx_sync"
check "M6 asked for again in this run, same: tree kept (warning), no stop" "[ $RC = 0 ] && has 'kept as built before'"
run "" 1 "" "mx_sync"
check "M7 --mesa-extra= (none): tree deleted, setting and file key removed" \
  "[ $RC = 0 ] && [ ! -e $E ] && ! grep -q '^MESA_EXTRA' $CONF && has 'Mesa 26.2.4 tree deleted' && [ -f $M/graphics_provider.json ]"
run "26.2.4" 1 "" "mx_sync"
check "M8 asked for, no file, not published: stops naming --mesa-extra-file" "[ $RC = 1 ] && has '--mesa-extra-file=' && [ ! -e $E ]"
echo MESA_EXTRA=26.2.4 >> "$CONF"
run "" 0 "" "mx_sync"
check "M9 saved choice, no file, no tree: warning only, setting kept" "[ $RC = 0 ] && has 'tree not built' && grep -qx 'MESA_EXTRA=26.2.4' $CONF"
mv "$ARC.away" "$ARC"; cp "$ARC" "$T/bad.tar.zst"; echo x >> "$T/bad.tar.zst"
run "" 0 "$T/bad.tar.zst" "mx_match $T/bad.tar.zst; echo rc=\$?"
check "M10 file of no listed version: no match" "has 'rc=1'"
mkdir -p "$M-1.2.3.part" "$M-other"; run "" 0 "$ARC" "mx_sync; mx_drop_all"
check "M11 remove all: extra trees and partial trees go, second tree and other folders stay" \
  "has '26.2.4' && [ ! -e $E ] && [ ! -e $M-1.2.3.part ] && [ -d $M-other ] && [ -f $M/graphics_provider.json ]"

# ---------- whole installer: option checks ----------
mkdir -p "$T/sys"; for f in /usr/bin/* /bin/*; do n=${f##*/}; [ -e "$T/sys/$n" ] || ln -s "$f" "$T/sys/$n" 2>/dev/null; done
printf '#!/bin/sh\n[ "$1" = --print-architecture ] && { echo arm64; exit 0; }\nexit 1\n' > "$T/dpkg"
printf '#!/bin/sh\nexit 0\n' > "$T/apt-get"; cp "$T/apt-get" "$T/apt-cache"; chmod 755 "$T/dpkg" "$T/apt-get" "$T/apt-cache"
mkdir -p "$T/stub"; mv "$T/dpkg" "$T/apt-get" "$T/apt-cache" "$T/stub/"
# copy that ends right after the option checks
python3 - "$INST" "$T/opt.sh" <<'EOF'
import sys
s = open(sys.argv[1]).read()
k = "# Custom archive path is saved in the settings file, which the launcher reads as shell.\n"
assert s.count(k) == 1
open(sys.argv[2], "w").write(s.replace(k, 'echo "PAST sel=$MESA_EXTRA_SEL file=$MX_FILE_VER"; exit 0\n' + k, 1))
EOF
iop(){ OUT=$(cd "$T" && env -i HOME="$T" PATH="$T/stub:$T/sys" GAMEUSER=nobody bash "$T/opt.sh" "$@" </dev/null 2>&1); RC=$?; }
iop --keep --mesa-extra=9.9.9
check "O1 --mesa-extra with unlisted version: stops, lists versions" "[ $RC = 1 ] && has 'not in this installer' && has 'listed: 26.2.4'"
iop --keep "--mesa-extra=26.2.4, 26.2.4"
check "O2 --mesa-extra list normalised (spaces, duplicates)" "has 'PAST sel=26.2.4 file='"
iop --keep --mesa-extra-file="$ARC"
check "O3 file not matching pinned sha256: stops, nothing changed" "[ $RC = 1 ] && has 'matches no listed Mesa archive' && has 'Nothing changed'"
iop --keep --mesa-extra-file="$T/none.tar.zst"
check "O4 missing file: stops" "[ $RC = 1 ] && has 'file not found'"
iop --remove --mesa-extra=9.9.9
check "O5 --remove skips extra checks" "! has 'not in this installer'"
OUT=$(cd "$T" && env -i HOME="$T" PATH="$T/stub:$T/sys" GAMEUSER=nobody bash "$INST" --detect </dev/null 2>&1)
check "O6 --detect: one mesa extra line per listed version, official client line" \
  "grep -qE '^mesa extra: 26\.2\.4 [0-9a-fA-Z]+ \S+ [0-9]+ [0-9]+$' <<<\"\$OUT\" && grep -qE '^official client: (none|found)' <<<\"\$OUT\""
OUT=$(cd "$T" && env -i HOME="$T" PATH="$T/stub:$T/sys" bash "$INST" --help </dev/null 2>&1)
check "O7 --help names options and listed versions" "has '--mesa-extra=LIST' && has '--mesa-extra-file=FILE' && grep -q '^    26.2.4 ' <<<\"\$OUT\""
check "O8 removal deletes extra trees and says so; deselect deletes them" \
  "grep -q 'gone_mx=\$(mx_drop_all)' '$INST' && grep -q 'extra Mesa versions inside emulation: \$gone_mx' '$INST' && grep -q 'MX_GONE=\$(mx_drop_all)' '$INST'"
check "O9 bwrap and owner loops cover extra trees" "[ \"\$(grep -c 'mx_present | sed' '$INST')\" -ge 3 ]"

# ---------- menu ----------
L1=$(sed -n 's/^MESA_EXTRA_LIST="\(.*\)"$/\1/p' "$INST"); L2=$(sed -n 's/^SA_MESA_EXTRA="\(.*\)"$/\1/p' "$CFG")
check "U1 menu's built-in list equals installer's list" "[ -n \"$L1\" ] && [ \"$L1\" = \"$L2\" ]"
check "U2 embedded menu equals settings menu file" "awk \"/^menu_app\\\\(\\\\)\\\\{ cat <<'STEAMARMCONFIG'\\\$/{f=1;next} /^STEAMARMCONFIG\\\$/{f=0} f\" '$INST' | cmp -s - '$CFG'"
RF=$T/fake
sed "s#^R=.*#R=$RF#" "$HERE/config-ui/mkfake.sh" > "$T/mkfake.sh"; bash "$T/mkfake.sh" >/dev/null
mkh(){
  sed -e '$d' "$1" > "$T/app-$2.sh"
  cat > "$T/h-$2.sh" <<EOF
. "$T/app-$2.sh"
R=$RF
SA_CONF=\$R/etc/steam-arm/steam-arm.conf; SA_TITLES_SHARE=\$R/share/titles.conf; SA_TITLES_ETC=\$R/etc/steam-arm/titles.conf
SA_LAUNCHER=\$R/bin/steam-arm; SA_TMP=$T/tmp; SA_MALI=$M; SA_RFS=$R
game_home(){ echo \$R/home/tester; }; game_user(){ echo tester; }; detect_raw(){ printf 'family: x\nmesa extra: 26.2.4 $SHA - 75 330\n'; }
acct_home(){ echo \$R/home/\$1; }; acct_run(){ shift; "\$@"; }; owner_user(){ echo tester; }; owner_home(){ echo \$R/home/tester; }
as_owner(){ "\$@"; }; as_root(){ "\$@"; }; need_root(){ return 0; }; steam_running(){ return 1; }
EOF
}
mkdir -p "$T/tmp"; mkh "$CFG" 30
APP232=$(sarm_old 2.3.2 steam-arm-config); [ -n "$APP232" ] && mkh "$APP232" 232
mrun(){ bash -c ". $T/h-$1.sh; $2" 2>&1; }
OUT=$(mrun 30 "profile_ok mesa 26.2.4 && profile_ok mesa '' && ! profile_ok mesa abc && ! profile_ok mesa '26.2' && echo ok")
check "U3 profile key mesa=<x.y.z> accepted, other forms refused" "grep -qx ok <<<\"\$OUT\""
OUT=$(mrun 30 "cli_profile 100 mesa=26.2.4; tc_get 100 mesa")
check "U4 profile mesa=26.2.4 written; note when version not installed" "grep -qx 26.2.4 <<<\"\$OUT\" && grep -q 'Mesa 26.2.4 not installed' <<<\"\$OUT\""
OUT=$(mrun 30 "cli_profile 100 --clear; tc_get 100 mesa; echo end")
check "U5 --clear removes mesa" "[ \"\$(head -1 <<<\"\$OUT\")\" = 'app 100: profile removed' ] && ! grep -qx 26.2.4 <<<\"\$OUT\""
mkdir -p "$E"; echo a > "$E/.steam-arm-mali"; echo '{}' > "$E/graphics_provider.json"
OUT=$(mrun 30 "mx_state; mx_list; info_status | grep 'Extra Mesa'")
check "U6 installed versions found; list from --detect; info row" "grep -qx 26.2.4 <<<\"\$(head -1 <<<\"\$OUT\")\" && grep -q '^26.2.4 $SHA - 75 330' <<<\"\$OUT\" && grep -q 'Extra Mesa     26.2.4' <<<\"\$OUT\""
rm -rf "$E"
OUT=$(mrun 30 "mx_state")
check "U7 nothing installed: none" "[ \"\$OUT\" = none ]"
check "U8 Games > game row, Components > Driver archive row, screens and help" \
  "grep -q 'mesa \"Mesa, route B        \[' '$CFG' && grep -q '^game_mesa(){' '$CFG' && grep -q 'extra \"Extra versions, route B games' '$CFG' && grep -q '^da_extra(){' '$CFG' && grep -q '^da_extra_one(){' '$CFG' && grep -q 'mesa=<version>: route B game' '$CFG'"
check "U9 extra version screen shows sizes before build and needs gpu-in-emulation" \
  "grep -q 'Archive: about \$a MB. Disk: about \$d MB extra' '$CFG' && grep -q 'turn on gpu-in-emulation first' '$CFG'"

# ---------- backup ----------
printf 'GFX_DEFAULT=auto\nMESA_EXTRA=26.2.4\nMESA_EXTRA_FILE_26_2_4=/x/a.tar.zst\n' >> "$RF/etc/steam-arm/steam-arm.conf"
printf '100 gfx=b mesa=26.2.4\n' > "$RF/etc/steam-arm/titles.conf"
mkdir -p "$T/out"
OUT=$(mrun 30 "bk_make $T/out setup,system-profiles tester; echo rc=\$?")
B=$(ls "$T"/out/*.tar.gz 2>/dev/null | head -1)
check "K1 3.0 backup with mesa= line written; member names unchanged" "grep -q rc=0 <<<\"\$OUT\" && [ \"\$(tar -tzf \"$B\" | sort | paste -sd' ')\" = 'steam-arm-settings/manifest steam-arm-settings/system/steam-arm.conf steam-arm-settings/system/titles.conf' ]"
printf '' > "$RF/etc/steam-arm/titles.conf"; sed -i '/^MESA_EXTRA/d' "$RF/etc/steam-arm/steam-arm.conf"
OUT=$(mrun 30 "rs_open $B || echo ERR; rs_plan \"\$RS_PARTS\" tester replace replace all all; echo \"\$RS_SUM\"; rs_apply; echo apply=\$?")
check "K2 3.0 restore: mesa= line back, extra version choice not restored (state of this machine)" \
  "grep -q apply=0 <<<\"\$OUT\" && grep -q '^100 gfx=b mesa=26.2.4' $RF/etc/steam-arm/titles.conf && ! grep -q '^MESA_EXTRA' $RF/etc/steam-arm/steam-arm.conf"
if [ -n "$APP232" ]; then
  printf '' > "$RF/etc/steam-arm/titles.conf"
  OUT=$(mrun 232 "rs_open $B || echo ERR \$RS_ERR; rs_plan \"\$RS_PARTS\" tester replace replace all all; rs_apply; echo apply=\$?")
  check "K3 2.3.2 restores the 3.0 archive (mesa= line kept as text)" "! grep -q '^ERR' <<<\"\$OUT\" && grep -q apply=0 <<<\"\$OUT\" && grep -q '^100 gfx=b mesa=26.2.4' $RF/etc/steam-arm/titles.conf"
else
  echo "SKIP K3 2.3.2 release not available (run through run-all.sh)"
fi
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
