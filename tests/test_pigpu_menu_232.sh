#!/bin/bash
# 2.3.2 menu cases, Raspberry Pi GPU: Graphics > Route per game rows Direct3D, OpenGL version, OpenGL driver (Pi
# families only), Graphics intro and list column on Pi families, choices written to titles.conf, CLI profile keys and --clear, Windows game hint, notes and help.
# Screens stubbed (answers from a queue file); GPU family from the fake settings file. Internal; not for release zips.
. "$(dirname "$0")/paths.sh"
T0=$SARM_TESTS/config-ui
CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm232-pimenu.XXXXXX); trap 'rm -rf "$T"' EXIT
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
R=$SARM_UI_FAKE
bash "$T0/mkfake.sh" >/dev/null
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; sed 's/^/     /' <<<"$OUT" | tail -n 8; fail=$((fail + 1)); fi; }
sed -e "s#^APP=.*#APP=\"$CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"
export Q=$T/q LOG=$T/ui.log
cat > "$T/stubs.sh" <<'EOF'
nxt(){ A=$(head -n 1 "$Q"); sed -i 1d "$Q"; }
ui_menu(){ printf 'MENU %s|%s|%s\n' "$1" "$2" "${*:3}" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; echo "$A"; }
ui_msg(){ printf 'MSG %s|%s\n' "$1" "$2" >> "$LOG"; }
ui_textstr(){ printf 'TEXT %s\n' "$1" >> "$LOG"; }
ui_info(){ :; }
ui_yesno(){ printf 'YESNO %s|%s\n' "$1" "$2" >> "$LOG"; nxt; [ "$A" = yes ]; }
ab_list(){ return 0; }
deck_hint(){ printf 'unknown\tunknown\n'; }
EOF
ui(){ local s=$1; shift; : > "$LOG"; printf '%s\n' "$@" > "$Q"
  bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; $s" >/dev/null 2>"$T/err"; RC=$?; OUT=$(cat "$LOG" "$T/err"); }
cli(){ OUT=$(bash -c ". $T/harness.sh --help >/dev/null; main $*" 2>&1); RC=$?; }
CONF=$R/etc/steam-arm/steam-arm.conf
TC=$R/etc/steam-arm/titles.conf
cp "$CONF" "$T/conf.orig"; cp "$TC" "$T/tc.orig"
fresh(){ cp "$T/conf.orig" "$CONF"; cp "$T/tc.orig" "$TC"; printf '%s\n' "$@" >> "$CONF"; }
row400(){ grep '^400 ' "$TC" | tail -1; }

# ---------- Route per game rows ----------
for f in broadcom-v3d71 broadcom-v3d42 broadcom-vc4; do
  fresh "GPU_FAMILY=$f"; ui graphics_game 400 BACK
  check "P1 $f: Route per game lists Direct3D (WineD3D), OpenGL version (off), OpenGL driver (v3d)" "grep -q '^MENU Graphics: Portal|' <<<\"\$OUT\" && grep -q ' d3d Direct3D, Windows build: WineD3D glver OpenGL version: off (driver: 3.1) gl OpenGL driver: v3d\$' <<<\"\$OUT\""
done
for f in mali-csf-v10 adreno-a7xx amd-radv; do
  fresh "GPU_FAMILY=$f"; ui graphics_game 400 BACK
  check "P2 $f: no Raspberry Pi rows" "grep -q '^MENU Graphics: Portal|' <<<\"\$OUT\" && ! grep -q 'Direct3D\\|OpenGL version\\|OpenGL driver' <<<\"\$OUT\""
done

# ---------- Direct3D ----------
fresh GPU_FAMILY=broadcom-v3d71; ui graphics_game 400 d3d dxvk
check "P3 Direct3D screen: WineD3D, DXVK stops at start, default; reason named" "grep -q '^MENU Direct3D: Portal|Windows games on Raspberry Pi GPU run Direct3D 8 to 11 through WineD3D' <<<\"\$OUT\" && grep -q 'wined3d WineD3D (OpenGL) dxvk DXVK (Vulkan), not applied: V3DV lacks shaderInt64, robustBufferAccess2, textureCompressionBC, multiViewport, tessellationShader default Default: WineD3D (remove this setting)\$' <<<\"\$OUT\""
check "P3 DXVK chosen: d3d=dxvk in titles.conf, message names apply times" "row400 | grep -q ' d3d=dxvk' && grep -q '^MSG Graphics|Portal: Direct3D through DXVK (not applied on this GPU).' <<<\"\$OUT\" && grep -q 'next start of Steam ARM (Steam launch option' <<<\"\$OUT\""
ui graphics_game 400 BACK
check "P3 row shows DXVK afterwards" "grep -q 'd3d Direct3D, Windows build: DXVK (not applied on this GPU)' <<<\"\$OUT\""
ui graphics_game 400 d3d default
check "P4 Direct3D default: d3d removed" "! grep -q 'd3d=' '$TC'"

# ---------- OpenGL version ----------
fresh GPU_FAMILY=broadcom-v3d42; ui graphics_game 400 glver 3.3
check "P5 OpenGL version screen: 3.2, 3.3, 4.5, off; driver 3.1 named" "grep -q '^MENU OpenGL version: Portal|Raspberry Pi GPU driver offers OpenGL 3.1' <<<\"\$OUT\" && grep -q '3.2 Report OpenGL 3.2 3.3 Report OpenGL 3.3 4.5 Report OpenGL 4.5 off Off (remove this setting)\$' <<<\"\$OUT\""
check "P5 3.3 chosen: glver=3.3 written" "row400 | grep -q ' glver=3.3' && grep -q '^MSG Graphics|Portal: OpenGL version 3.3 report.' <<<\"\$OUT\""
ui graphics_game 400 glver BACK
check "P5 current version marked" "grep -q '3.3 Report OpenGL 3.3 \\*' <<<\"\$OUT\""
ui graphics_game 400 glver off
check "P6 OpenGL version off: glver removed" "! grep -q 'glver=' '$TC'"

# ---------- Zink ----------
fresh GPU_FAMILY=broadcom-v3d71; ui graphics_game 400 gl zink
check "P7 OpenGL driver screen: Zink experimental, untested named" "grep -q '^MENU OpenGL driver: Portal|Zink runs OpenGL on Vulkan driver of this GPU. Experimental: untested on Raspberry Pi' <<<\"\$OUT\""
check "P7 Zink chosen: gl=zink written" "row400 | grep -q ' gl=zink' && grep -q 'OpenGL driver Zink (experimental)' <<<\"\$OUT\""
ui graphics_game 400 gl default
check "P7 v3d driver: gl removed" "! grep -q ' gl=' '$TC'"

# ---------- CLI ----------
fresh GPU_FAMILY=broadcom-v3d71
cli profile 400 glver=3.7
check "P8 CLI: glver outside list refused" "[ $RC = 2 ] && grep -q 'bad setting: glver=3.7' <<<\"\$OUT\""
cli profile 400 d3d=vulkan
check "P8 CLI: d3d value outside dxvk/wined3d refused" "[ $RC = 2 ]"
cli profile 400 gl=v3d
check "P8 CLI: gl value other than zink refused" "[ $RC = 2 ]"
cli profile 400 d3d=dxvk glver=4.5 gl=zink
check "P9 CLI: d3d, glver, gl accepted" "[ $RC = 0 ] && row400 | grep -q 'd3d=dxvk' && row400 | grep -q 'glver=4.5' && row400 | grep -q 'gl=zink'"
cli profile 400 --clear
check "P9 CLI --clear removes d3d, glver, gl" "[ $RC = 0 ] && ! grep -q '^400 .*\\(d3d\\|glver\\|gl\\)=' '$TC'"
cli --help
check "P10 CLI help names Raspberry Pi keys" "grep -q 'Raspberry Pi GPU keys d3d=dxvk|wined3d,' <<<\"\$OUT\""

# ---------- Games screen, notes, help ----------
fresh GPU_FAMILY=broadcom-v3d71; ui 'game_kind(){ echo windows; }; game_menu 400' BACK
check "P11 Windows game on Pi GPU: Games screen points to Graphics > Route per game" "grep -q 'Raspberry Pi GPU: Direct3D, OpenGL version and driver in Graphics > Route per game.' <<<\"\$OUT\""
fresh GPU_FAMILY=mali-csf-v10; ui 'game_kind(){ echo windows; }; game_menu 400' BACK
check "P11 Windows game on Mali: no Pi line" "grep -q '^MENU Game: Portal|' <<<\"\$OUT\" && ! grep -q 'Raspberry Pi' <<<\"\$OUT\""
fresh; ui 'gpu_family(){ echo broadcom-v3d71; }; info_notes_builtin >> $LOG'
check "P12 notes: OpenGL 3.1, WineD3D, per game settings" "grep -q 'Raspberry Pi GPU: OpenGL 3.1. Windows games use WineD3D (DXVK cannot run on V3D)' <<<\"\$OUT\""
fresh; ui 'fixing_text >> $LOG'
check "P13 Fixing a game: WineD3D default on Raspberry Pi GPU, Pi rows" "grep -q 'Vulkan (DXVK); default on Raspberry Pi GPU' <<<\"\$OUT\" && grep -q '^- Raspberry Pi GPU, Graphics > Route per game:' <<<\"\$OUT\" && grep -q '(experimental, untested on Raspberry Pi).' <<<\"\$OUT\""

# ---------- Graphics intro, Route per game list column ----------
fresh GPU_FAMILY=broadcom-v3d71; ui menu_graphics BACK
check "P14 Pi GPU: Graphics intro names Pi settings, no Mali route B" "grep -q '^MENU Graphics|How games reach the GPU. A: forwarding to host drivers. Raspberry Pi GPU: Direct3D, OpenGL version and driver per game in Route per game.|' <<<\"\$OUT\" && ! grep -q 'Mali' <<<\"\$OUT\""
fresh GPU_FAMILY=mali-csf-v10; ui menu_graphics BACK
check "P14 Mali: Graphics intro unchanged" "grep -q '^MENU Graphics|How x86 games reach the GPU. A: forwarding to host drivers. B: Mali drivers inside emulation.|' <<<\"\$OUT\""
fresh GPU_FAMILY=broadcom-v3d71; cli profile 400 d3d=dxvk glver=3.3 gl=zink; ui graphics_game BACK
check "P15 Pi GPU: list column shows Pi settings (DXVK, GL 3.3, Zink)" "grep -q '^MENU Graphics: per game|.* 400 Portal  *DXVK, GL 3.3, Zink' <<<\"\$OUT\""
cli profile 400 --clear; cli profile 400 glver=4.5; ui graphics_game BACK
check "P15 Pi GPU: one setting (GL 4.5) instead of route label" "grep -q ' 400 Portal  *GL 4.5 ' <<<\"\$OUT\""
cli profile 400 --clear; ui graphics_game BACK
check "P15 Pi GPU, no Pi settings: route label as before" "grep -q ' 400 Portal  *Forwarding' <<<\"\$OUT\""
ui 'compat_map(){ printf "400\tproton_experimental\n"; }; pi_family(){ return 0; }; tc_get(){ case $2 in d3d) echo dxvk;; glver) echo 3.3;; gl) echo zink;; esac; }; pick_game x gfx' BACK
check "P15 Pi GPU, Windows build: Win plus settings within 24 columns" "grep -q ' 400 Portal  *Win, DXVK, GL 3.3, Zink' <<<\"\$OUT\""
fresh GPU_FAMILY=mali-csf-v10; cli profile 400 d3d=dxvk glver=3.3 gl=zink; ui graphics_game BACK
check "P15 Mali with Pi settings: route label only" "grep -q ' 400 Portal  *Forwarding' <<<\"\$OUT\" && ! grep -q 'GL 3.3\|DXVK' <<<\"\$OUT\""

echo "pi gpu menu 2.3.2: $pass pass, $fail fail"
[ "$fail" = 0 ]
