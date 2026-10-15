#!/bin/bash
# steam-arm-icon (placeholder disc before first start, logo from client's steam_tray.ico after), extracted from the
# installer copy in ~/.cache/sarm<NN>-work (paths.sh); restored from icontest.sh of 2026-10-04. Needs python3-pil. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-icon.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -4; fail=$((fail + 1)); fi; }
python3 -c 'import PIL' 2>/dev/null || { echo "FAIL python3-pil missing"; exit 1; }
awk "/^  cat > \/usr\/local\/bin\/steam-arm-icon <<'ICONPY'\$/{f=1;next} /^ICONPY\$/{f=0} f" "$INST" > "$T/steam-arm-icon"
check "icon helper extracted and compiles" "[ -s $T/steam-arm-icon ] && python3 -m py_compile $T/steam-arm-icon"
px(){ python3 -c "from PIL import Image; im = Image.open('$1').convert('RGBA'); print(*im.getpixel(($2, $3)))"; }
O=$T/out
if [ -e /opt/fex-rootfs/Ubuntu_24_04/usr/share/icons/hicolor/256x256/apps/steam.png ]; then
  echo "PASS placeholder cases skipped: RootFS steam.png present on this host (fallback logo source)"; pass=$((pass + 1))
else
  OUT=$(python3 "$T/steam-arm-icon" "$T/nosteam" "$O" 2>&1); rc=$?
  check "no client files: rc 0" "[ $rc = 0 ]"
  check "no client files: 6 sizes x 2 names" "[ \$(ls $O/*/apps/steam-arm.png $O/*/apps/steam-arm-desktop.png | wc -l) = 12 ]"
  check "no client files: placeholder marker written" "[ -f $O/.steam-arm-placeholder ]"
  OUT=$(px "$O/256x256/apps/steam-arm.png" 128 128)
  check "placeholder centre opaque dark disc, no logo" "(set -- \$OUT; [ \$4 = 255 ] && [ \$1 -lt 100 ] && [ \$2 -lt 100 ])"
  OUT=$(px "$O/256x256/apps/steam-arm.png" 0 0)
  check "placeholder corner transparent" "(set -- \$OUT; [ \$4 = 0 ])"
fi
# fake client icon: white ring on blue disc, as the client's tray icon is drawn
mkdir -p "$T/steam/public"
python3 - "$T/steam/public/steam_tray.ico" <<'EOF'
import sys
from PIL import Image
src = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
for y in range(256):
    for x in range(256):
        d = ((x - 128) ** 2 + (y - 128) ** 2) ** 0.5
        if d < 126:
            src.putpixel((x, y), (255, 255, 255, 255) if 40 < d < 60 else (20, 60, 140, 255))
src.save(sys.argv[1], sizes=[(256, 256)])
EOF
OUT=$(python3 "$T/steam-arm-icon" "$T/steam" "$O" 2>&1); rc=$?
check "client icon: rc 0" "[ $rc = 0 ]"
check "client icon: placeholder marker removed" "[ ! -e $O/.steam-arm-placeholder ]"
OUT=$(px "$O/256x256/apps/steam-arm.png" 128 178)
check "Big Picture icon: chartreuse logo on ring" "[ \"\$OUT\" = '156 200 101 255' ]"
OUT=$(px "$O/256x256/apps/steam-arm-desktop.png" 128 178)
check "desktop icon: bone logo on ring" "[ \"\$OUT\" = '196 186 160 255' ]"
OUT=$(px "$O/256x256/apps/steam-arm.png" 128 128)
check "client icon: centre is disc, not logo" "[ \"\$OUT\" != '156 200 101 255' ] && (set -- \$OUT; [ \$4 = 255 ])"
A=$(md5sum < "$O/256x256/apps/steam-arm.png"); python3 "$T/steam-arm-icon" "$T/steam" "$O"
check "same input draws same icon (fixed seeds)" "[ \"\$(md5sum < $O/256x256/apps/steam-arm.png)\" = '$A' ]"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
