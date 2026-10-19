#!/bin/bash
# Raspberry Pi 5 page-size flow of steam-arm-install.sh on this PC: a copy with board model, /boot and lock
# paths pointed at a fake tree, getconf/id stand-ins, and a stop after deferred page-size block removal. Internal.
. "$(dirname "$0")/paths.sh"; SRC=${1:-$SARM_INST}
W=$(mktemp -d); F=$W/fake; mkdir -p "$F/boot/firmware" "$W/bin"
sed -e "s#/proc/device-tree/model#$F/model#g" -e "s#/boot/firmware#$F/boot/firmware#g" -e "s#/boot/config.txt#$F/boot/config.txt#g" \
    -e "s#/run/steam-arm-setup.lock#$F/lock#g" -e "s#FWDIR=/boot\$#FWDIR=$F/boot#" -e "s#^CONF=/etc/steam-arm/steam-arm.conf\$#CONF=$F/steam-arm.conf#" \
    "$SRC" > "$W/inst.sh"
python3 - "$W/inst.sh" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
old = '[ "$(id -u)" = 0 ] || die "run as root"\nsteam_up && steam_up_die\n'
assert s.count(old) == 1, "root and Steam checks not found"
s = s.replace(old, '').replace('SA_STATE=/var/lib/steam-arm/upgrade.state\n', 'SA_STATE=/nonexistent/upgrade.state\n')
# stop after deferred page-size block removal (runs after snapshot step)
stop = '# Client folder marker (--remove deletes only a marked folder)'
assert s.count(stop) == 1, "stop point not found"
open(p, "w").write(s.replace(stop, 'echo PAST-PAGESIZE; exit 0\n' + stop))
EOF
printf '#!/bin/sh\n[ "$1" = PAGESIZE ] && { cat %s/pagesize; exit 0; }\nexec /usr/bin/getconf "$@"\n' "$F" > "$W/bin/getconf"
printf '#!/bin/sh\n[ "$#" = 1 ] && [ "$1" = -u ] && { echo 0; exit 0; }\nexec /usr/bin/id "$@"\n' > "$W/bin/id"
# platform gate (2.3.1): apt tools present, dpkg architecture arm64; other apt and dpkg calls fail as on a host without them
printf '#!/bin/sh\nexit 100\n' > "$W/bin/apt-get"; printf '#!/bin/sh\nexit 100\n' > "$W/bin/apt-cache"
printf '#!/bin/sh\n[ "$1" = --print-architecture ] && { echo arm64; exit 0; }\nexit 1\n' > "$W/bin/dpkg"
chmod 755 "$W/bin/"*
export PATH="$W/bin:$PATH" GPU_FAMILY=broadcom-v3d71
CFG=$F/boot/firmware/config.txt
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; echo "     $OUT" | tail -5; fail=$((fail + 1)); fi; }
reset(){ printf '%s' "$1" > "$F/model"; echo "$2" > "$F/pagesize"
  printf '# Pi OS default\ndtparam=audio=on\ncamera_auto_detect=1\n\n[cm5]\ndtoverlay=dwc2,dr_mode=host\n\n[all]\n' > "$CFG"
  rm -f "$CFG.steam-arm.bak"; : > "$F/boot/firmware/kernel8.img"; : > "$F/boot/firmware/kernel_2712.img"; }
run(){ OUT=$(bash "$W/inst.sh" "$@" </dev/null 2>&1); RC=$?; }

reset "Raspberry Pi 5 Model B Rev 1.0" 16384
run --detect
check "detect: page-size listed and on" "grep -q 'component page-size: on' <<<\"\$OUT\" && grep -q 'page size: 16384' <<<\"\$OUT\""
run --defaults
check "first run (16K): block added, backup kept, exit 0" "[ $RC = 0 ] && grep -qx 'kernel=kernel8.img' $CFG && [ -f $CFG.steam-arm.bak ] && grep -q 'reboot, then run sudo steam-arm-setup again' <<<\"\$OUT\""
check "block sits under its own [all] at end" "tail -3 $CFG | head -2 | tr '\n' ' ' | grep -q '\\[all\\] kernel=kernel8.img'"
check "earlier lines untouched" "head -7 $CFG | cmp -s - <(head -7 $CFG.steam-arm.bak)"
run --defaults
check "second run before reboot: no second block, says reboot" "[ $RC = 0 ] && [ \$(grep -c 'kernel=kernel8.img' $CFG) = 1 ] && grep -q 'already selected' <<<\"\$OUT\""
echo 4096 > "$F/pagesize"
run --defaults
check "after reboot (4K): install continues, block kept" "[ $RC = 0 ] && grep -q PAST-PAGESIZE <<<\"\$OUT\" && grep -qx 'kernel=kernel8.img' $CFG"
run --skip page-size
check "4K, page-size deselected: block removed, warning" "grep -q PAST-PAGESIZE <<<\"\$OUT\" && ! grep -q kernel8 $CFG && grep -q 'page-size deselected' <<<\"\$OUT\""

reset "Raspberry Pi 5 Model B Rev 1.0" 16384
run --skip page-size
check "16K with page-size skipped: stops with fix" "[ $RC != 0 ] && grep -q 'Select page-size' <<<\"\$OUT\" && ! grep -q kernel8 $CFG"
reset "Raspberry Pi 5 Model B Rev 1.0" 16384; echo "kernel=kernel_2712.img" >> "$CFG"
run --defaults
check "16K with own kernel= line: stops, file unchanged" "[ $RC != 0 ] && grep -q 'already sets kernel itself' <<<\"\$OUT\" && [ \$(grep -c '^kernel=' $CFG) = 1 ]"
reset "Raspberry Pi 5 Model B Rev 1.0" 16384; rm -f "$F/boot/firmware/kernel8.img"
run --defaults
check "16K without kernel8.img: stops with package hint" "[ $RC != 0 ] && grep -q 'no kernel8.img' <<<\"\$OUT\""
reset "Raspberry Pi 500 Rev 1.0" 16384
run --defaults
check "Raspberry Pi 500: same flow" "[ $RC = 0 ] && grep -qx 'kernel=kernel8.img' $CFG"
reset "Raspberry Pi Compute Module 5 Rev 1.0" 16384
run --defaults
check "Compute Module 5: same flow" "[ $RC = 0 ] && grep -qx 'kernel=kernel8.img' $CFG"
reset "Raspberry Pi 4 Model B Rev 1.5" 4096
run --detect
check "Pi 4 on 4K: page-size not listed" "! grep -q 'component page-size' <<<\"\$OUT\""
reset "Raspberry Pi 5 Model B Rev 1.0" 4096
run --defaults
check "Pi 5 already on 4K (Ubuntu or kernel8 by hand): no edit" "grep -q PAST-PAGESIZE <<<\"\$OUT\" && ! grep -q kernel8 $CFG"
check "settings file path rewritten in copy" "grep -q '^CONF=$F/steam-arm.conf\$' $W/inst.sh"
# override kept in the settings file by an earlier run (L22-2)
reset "Generic ARM64 board" 16384; rm -f "$F/steam-arm.conf"
run --defaults
check "16K, no override: stops" "[ $RC != 0 ] && ! grep -q PAST-PAGESIZE <<<\"\$OUT\""
echo STEAM_ARM_IGNORE_PAGESIZE=1 > "$F/steam-arm.conf"
run --defaults
check "16K, override kept in settings file: continues with warning" "grep -q PAST-PAGESIZE <<<\"\$OUT\" && grep -q 'continuing because STEAM_ARM_IGNORE_PAGESIZE=1' <<<\"\$OUT\""
OUT=$(STEAM_ARM_IGNORE_PAGESIZE=0 bash "$W/inst.sh" --defaults </dev/null 2>&1); RC=$?
check "16K, kept override, environment 0: stops" "[ $RC != 0 ] && ! grep -q PAST-PAGESIZE <<<\"\$OUT\""
# save step at end of setup: kept on non-4K with override, cleared otherwise
SV=$W/save.sh
{ echo 'die(){ echo "DIE $*"; exit 1; }'; awk 'NR > 300 {exit} /^conf_get\(\)\{/{print} /^conf_set\(\)\{/,/^}$/{print} /^conf_del\(\)\{/,/^}$/{print}' "$W/inst.sh"
  grep -A1 '^# Page size override used on a non-4K kernel' "$W/inst.sh" | tail -1; } > "$SV"
svrun(){ printf 'GAMEUSER=u\n' > "$F/steam-arm.conf"; [ -z "$3" ] || echo "$3" >> "$F/steam-arm.conf"
  ( CONF=$F/steam-arm.conf PAGESIZE=$1 PS_IGNORE=$2; . "$SV" ); }
svrun 16384 1
check "save: 16K + override -> key written, rest kept" "grep -qx STEAM_ARM_IGNORE_PAGESIZE=1 $F/steam-arm.conf && grep -qx GAMEUSER=u $F/steam-arm.conf"
svrun 4096 1 STEAM_ARM_IGNORE_PAGESIZE=1
check "save: 4K -> key removed" "! grep -q IGNORE_PAGESIZE $F/steam-arm.conf && grep -qx GAMEUSER=u $F/steam-arm.conf"
svrun 16384 '' STEAM_ARM_IGNORE_PAGESIZE=1
check "save: no override in effect -> key removed" "! grep -q IGNORE_PAGESIZE $F/steam-arm.conf"
rm -rf "$W"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
