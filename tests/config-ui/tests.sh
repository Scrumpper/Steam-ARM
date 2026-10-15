#!/bin/bash
# Non-interactive tests of steam-arm-config against the fake tree.
. "$(dirname "$0")/../paths.sh"
T=$SARM_TESTS/config-ui
APP=$SARM_CFG
# private fake tree and menu copy: concurrent runs do not share them
UIP=$(mktemp -d /tmp/sarm-ui.XXXXXX); trap 'rm -rf "$UIP"' EXIT
export SARM_UI_FAKE=$UIP/fake SARM_UI_COPY=$UIP/app-copy.sh
H="bash $T/harness.sh"
R=$SARM_UI_FAKE
pass=0; fail=0
ok(){ echo "PASS $1"; pass=$((pass + 1)); }
bad(){ echo "FAIL $1"; fail=$((fail + 1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

bash "$T/mkfake.sh" >/dev/null
check "bash -n" "bash -n $APP"
SC=$(command -v shellcheck || { [ -x "$T/venv/bin/shellcheck" ] && echo "$T/venv/bin/shellcheck"; })
if [ -n "$SC" ]; then check "shellcheck clean" "$SC $APP"; else echo "SKIP shellcheck clean: shellcheck not installed"; fi
check "--help" "bash $APP --help | grep -q 'gfx-default auto|a|b'"
check "unknown command exits 2" "bash $APP bogus 2>/dev/null; [ \$? = 2 ]"
check "menu without tty refuses" "bash $APP </dev/null 2>&1 | grep -q 'needs a terminal'"

out=$($H info)
check "info: installed + detect (installer format)" "grep -q 'GPU            Mali-G610' <<<\"\$out\" && grep -q 'Mali (mali-csf-v10)' <<<\"\$out\" && grep -q 'panvk 26.1.4' <<<\"\$out\" && grep -q 'version 1.3' <<<\"\$out\" && grep -q 'FEX-2609.1' <<<\"\$out\""
check "info: detect note" "grep -q '^- Mali-G610 on Panthor' <<<\"\$out\""
out=$(FAKE_DETECT_FMT=old $H info)
check "info: alternate detect format (KEY: value + Notes block)" "grep -q 'Direct3D 12' <<<\"\$out\" && grep -q 'Kernel driver  panthor' <<<\"\$out\""
printf '#!/bin/sh\necho "unknown option: $1" >&2; exit 1\n' > $R/bin/old-installer.sh
out=$(STEAM_ARM_INSTALLER_OLD=1 bash -c ". $T/harness.sh --help >/dev/null; STEAM_ARM_INSTALLER=$R/bin/old-installer.sh; DETECT_DONE=0; main info")
check "info: fallback detection (installer without --detect, RK3588 panthor = mali-csf-v10)" "grep -q 'Kernel driver  panthor' <<<\"\$out\" && grep -q 'Mali (mali-csf-v10)' <<<\"\$out\" && grep -q 'open drivers' <<<\"\$out\""
out=$(HARNESS_REAL_INSTALLER=1 $H info)
check "info: real installer --detect parsed (GPU family line)" "grep -q 'GPU family     ' <<<\"\$out\""
if ls /dev/dri/renderD* >/dev/null 2>&1; then check "info: real installer --detect finds GPU of this host" "! grep -q 'GPU family     no GPU' <<<\"\$out\""
else echo "SKIP info: real installer GPU detection: no /dev/dri render node on this host"; fi
# family ids offered by the app are all known to the installer
ids=$(grep -oE '(mali|adreno|broadcom|apple|amd|nvidia|intel|virtio|vivante|img)[a-z0-9-]*' $APP | sort -u)
known=$(sed -n '/^GPU_FAMILIES="/,/"$/p' "$SARM_INST" | tr -d '"' | sed 's/GPU_FAMILIES=//' | tr ' ' '\n' | grep -v '^$')
miss=""; for i in $(bash -c ". $T/harness.sh --help >/dev/null; hw_table | cut -d'|' -f3; for d in panthor panfrost lima mali_kbase msm v3d vc4 etnaviv powervr asahi amdgpu radeon nouveau nvidia i915 virtio_gpu; do family_of_driver \$d; done" | grep -v '^?$'; echo mali-valhall-jm mali-bifrost mali-csf-5thgen mali-panfrost adreno-a7xx adreno-a6xx adreno-a8xx adreno amd-radv nvidia-nouveau nvidia-prop intel); do grep -qx "$i" <<<"$known" || miss="$miss $i"; done
check "all GPU_FAMILY ids known to installer (missing:$miss)" "[ -z \"$miss\" ]"
rec=$(bash -c ". $T/harness.sh --help >/dev/null; comp_recommended auto yes")
check "recommended from installer component lines" "[ \"\$rec\" = 'glx-lax vk-spoof gpu-in-emulation map-count xpad-dedup pad-hidraw desktop desktop-mode icon-bigpicture icon-desktop tray page-size' ]"
rec=$(bash -c ". $T/harness.sh --help >/dev/null; comp_recommended adreno-a7xx yes")
check "recommended for forced family passes GPU_FAMILY to --detect" "! grep -q vk-spoof <<<\"\$rec\" && ! grep -q gpu-in-emulation <<<\"\$rec\" && grep -q glx-lax <<<\"\$rec\""
rec=$(bash -c ". $T/harness.sh --help >/dev/null; comp_recommended auto no")
check "Vulkan no drops vk-spoof" "! grep -q vk-spoof <<<\"\$rec\" && grep -q gpu-in-emulation <<<\"\$rec\""
out=$(FAKE_NOT_INSTALLED=1 $H info)
check "info: not installed" "grep -q 'not installed. Use Install' <<<\"\$out\""

# report sanitising
printf 'steam-arm: path /home/tester/.local/x host %s ip 10.20.30.190 mac aa:bb:cc:dd:ee:ff user tester api 1.3.275\n' "$(hostname)" >> "$R/tmp/fex-compat-tool-1234.log"
touch "$R/tmp/fex-compat-tool-1234.log"
$H report >/dev/null
rep=$R/tmp/steam-arm-report.txt
check "report saved" "[ -s $rep ]"
check "report: no home paths" "! grep -q '/home/' $rep"
check "report: no user name" "! grep -qw tester $rep && { [ \"$(id -un)\" = root ] || ! grep -qw \"$(id -un)\" $rep; }"
check "report: no host name" "! grep -qw \"$(hostname)\" $rep"
check "report: no IP/MAC" "! grep -q '10.20.30.190' $rep && ! grep -q 'aa:bb:cc' $rep && grep -q '<ip>' $rep && grep -q '<mac>' $rep"
check "report: version kept" "grep -q 'api 1.3.275' $rep && grep -q 'panvk 26.1.4' $rep"

# games list
g=$(bash -c ". $T/harness.sh _none 2>/dev/null; games_list" 2>/dev/null)
cat > "$UIP/gl.sh" <<EOF
. $T/harness.sh --help >/dev/null
games_list
EOF
g=$(bash "$UIP/gl.sh")
echo "$g" | sed 's/^/   games: /'
check "games: 4 titles, tools skipped, 2nd library (space in path)" "[ \$(echo \"\$g\" | wc -l) = 4 ] && grep -q 'Jelly Brawl' <<<\"\$g\" && ! grep -qE 'Proton|Runtime|Steamworks|FEX' <<<\"\$g\""

# titles.conf round trips
E=$R/etc/steam-arm/titles.conf
cp "$E" "$UIP/titles.orig"
$H gfx 312520 b >/dev/null
check "gfx set appends to last line of app" "grep -qx '312520 env=A=1;B=2 gfx=b' $E && grep -qx '312520 overlay=vulkan' $E"
$H gfx 312520 auto >/dev/null
check "gfx auto round-trips to original bytes" "cmp -s $E $UIP/titles.orig"
$H gfx 219150 a >/dev/null
check "gfx change keeps other keys + comment" "grep -qx '219150 mangohud=on gfx=a # Hotline Miami 2 test' $E"
$H gfx 219150 auto >/dev/null
$H profile 219150 mangohud= >/dev/null
check "line with only a comment left is kept" "grep -qx '219150 # Hotline Miami 2 test' $E"
$H gfx 555 b >/dev/null
check "new app appended" "tail -1 $E | grep -qx '555 gfx=b'"
$H gfx 555 auto >/dev/null
check "new app removed cleanly" "! grep -q '^555' $E"
check "header comments untouched" "head -2 $E | cmp -s - <(head -2 $UIP/titles.orig)"
$H profile 312520 --clear >/dev/null
check "profile --clear drops both lines of app" "! grep -q '^312520' $E"
check "bad value refused" "! $H profile 400 'env=A 1' 2>/dev/null && ! $H profile 400 overlay=bogus 2>/dev/null && ! $H gfx abc b 2>/dev/null"
$H profile 400 overlay=off mangohud=on 'args=-windowed;-nosound' >/dev/null
check "profile multi keys" "grep -qx '400 overlay=off mangohud=on args=-windowed;-nosound' $E"
eff=$(bash -c ". $T/harness.sh --help >/dev/null; tc_effective 400 | tr '\n' ' '")
check "effective profile merges files (user gfx=a wins)" "grep -q 'gfx=a' <<<\"\$eff\" && grep -q 'overlay=off' <<<\"\$eff\""
src=$(bash -c ". $T/harness.sh --help >/dev/null; tc_source 400 gfx")
check "tc_source finds client home file" "[ \"\$src\" = $R/home/tester/.local/share/steam-arm/.config/steam-arm/titles.conf ]"
check "atomic write left no temp files" "[ \$(ls $R/etc/steam-arm | wc -l) = 2 ]"

# gfx-default
C=$R/etc/steam-arm/steam-arm.conf
$H gfx-default b >/dev/null
check "gfx-default b" "grep -qx 'GFX_DEFAULT=b' $C && [ \$(grep -c GFX_DEFAULT $C) = 1 ] && grep -qx 'VERSION=1.3' $C"
$H gfx-default a >/dev/null
check "gfx-default a writes a" "grep -qx 'GFX_DEFAULT=a' $C"
lab=$(bash -c ". $T/harness.sh --help >/dev/null; gfx_default_label \$(gfx_default)")
check "a reads as Forwarding for all" "[ \"\$lab\" = 'Forwarding for all' ]"
sed -i 's/^GFX_DEFAULT=.*/GFX_DEFAULT=forward/' $C
lab=$(bash -c ". $T/harness.sh --help >/dev/null; gfx_default_label \$(gfx_default)")
check "GFX_DEFAULT=forward reads as Forwarding for all" "[ \"\$lab\" = 'Forwarding for all' ]"
$H gfx-default auto >/dev/null
check "gfx-default auto" "grep -qx 'GFX_DEFAULT=auto' $C"
check "gfx-default bad value" "! $H gfx-default x 2>/dev/null"

# compat
out=$($H compat 400 windows)
check "compat windows -> proton_11-arm64 (name Steam lists)" "[ \"\$out\" = 'compatmap 400 proton_11-arm64' ]"
out=$($H compat 400 linux)
check "compat linux -> steamlinuxruntime" "[ \"\$out\" = 'compatmap 400 steamlinuxruntime' ]"

# components pass-through
export FAKE_INST_LOG=$UIP/inst.log; : > "$FAKE_INST_LOG"
$H components glx-lax,tray >/dev/null
check "components runs installer --select" "grep -q 'ARGS: --select=glx-lax,tray' $FAKE_INST_LOG"

# integration pass additions
check "help fixing page" "bash $APP help fixing | grep -q 'What cannot be fixed here' && bash $APP help fixing | grep -q 'launch option kept'"
check "no test hooks (SA_SYS/SA_PROC/source guard) in app" "! grep -qE 'SA_SYS|SA_PROC|BASH_SOURCE\\[0\\]\" = \"\\\$0' $APP && [ \"\$(tail -1 $APP)\" = 'main \"\$@\"' ]"
out=$(bash -c ". $T/harness.sh --help >/dev/null; DIALOG=read; UI_STDIN=s3cret; L=\$(mktemp); ui_run t \"\$L\" sh -c 'read -r p; [ \"\$p\" = s3cret ] && echo got-it'; echo rc=\$?; cat \"\$L\"; rm -f \"\$L\"" 2>&1)
check "ui_run feeds UI_STDIN to the command, not to the log" "grep -q 'rc=0' <<<\"\$out\" && grep -q got-it <<<\"\$out\" && ! grep -q s3cret <<<\"\$out\""
check "--help documents STEAM_ARM_INSTALLER" "bash $APP --help | grep -q 'STEAM_ARM_INSTALLER=file'"

echo "passed $pass, failed $fail"
