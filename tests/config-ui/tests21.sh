#!/bin/bash
# 2.1 additions to steam-arm-config, against its own fake tree.
. "$(dirname "$0")/../paths.sh"
T=$SARM_TESTS/config-ui
APP=$SARM_CFG
INST=$SARM_INST
# private fake tree and menu copy: concurrent runs do not share them
UIP=$(mktemp -d /tmp/sarm-ui.XXXXXX); trap 'rm -rf "$UIP"' EXIT
export SARM_UI_FAKE=$UIP/fake SARM_UI_COPY=$UIP/app-copy.sh
H="bash $T/harness.sh"
R=$SARM_UI_FAKE
bash "$T/mkfake.sh" >/dev/null
pass=0; fail=0
ok(){ echo "PASS $1"; pass=$((pass + 1)); }
bad(){ echo "FAIL $1"; fail=$((fail + 1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

check "embedded menu equals steam-arm-config file" "awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f' $INST | cmp -s - $APP"
V=$(sed -n 's/^SA_VERSION=//p' "$INST" | head -n 1)
check "version $V in installer (twice) and menu" "[ -n '$V' ] && grep -qx 'SA_VERSION=$V' $APP && [ \$(grep -c '^SA_VERSION=$V\$' $INST) = 2 ]"

# multiblock profile key
E=$R/etc/steam-arm/titles.conf
$H profile 401 multiblock=on >/dev/null
check "profile multiblock=on written" "grep -qx '401 multiblock=on' $E"
check "profile multiblock=bad refused" "! $H profile 401 multiblock=fast 2>/dev/null"
$H profile 401 --clear >/dev/null
check "profile --clear drops multiblock" "! grep -q '^401' $E"
check "--help lists multiblock key" "bash $APP --help | grep -q multiblock"

# components: kde-input-prompt off by default, known to the menu
check "kde-input-prompt in fallback list and default-off" "grep -q 'SA_DEFAULT_OFF=\"pad-xbox shader-cache kde-input-prompt\"' $APP && grep -q 'tray kde-input-prompt page-size' $APP"
rec=$(bash -c ". $T/harness.sh --help >/dev/null; comp_recommended auto yes")
check "recommended set unchanged (kde-input-prompt off)" "[ \"\$rec\" = 'glx-lax vk-spoof gpu-in-emulation map-count xpad-dedup pad-hidraw desktop desktop-mode icon-bigpicture icon-desktop tray page-size' ]"
lab=$(bash -c ". $T/harness.sh --help >/dev/null; comp_short kde-input-prompt")
check "kde-input-prompt short label" "[ \"\$lab\" = 'KDE: no input prompt; X11 apps may send input' ] && [ \${#lab} -le 47 ]"

# report: renderer lines with app ids
printf 'SteamAppId=70\nsteam-arm: graphics: forwarding\nsteam-arm: renderer: warning: GPU forwarding not active: rendering on CPU (llvmpipe); no GPU device open, process hl_linux\n' > "$R/tmp/fex-compat-tool-2222.log"
printf 'SteamAppId=1036240\nsteam-arm: renderer: GPU (v3d renderD128), forwarding to host driver, process JellyBrawl\n' > "$R/tmp/fex-compat-tool-3333.log"
touch -d '1 minute ago' "$R/tmp/fex-compat-tool-2222.log"
$H report >/dev/null
rep=$R/tmp/steam-arm-report.txt
check "report: renderer section" "grep -q '== Renderer at recent game starts' $rep"
check "report: app 70 CPU warning line" "grep -q '^app 70: warning: GPU forwarding not active: rendering on CPU (llvmpipe)' $rep"
check "report: app 1036240 GPU line, newest first" "grep -n '^app ' $rep | head -1 | grep -q 'app 1036240: GPU (v3d renderD128)'"
check "report: OpenGL and governor lines" "grep -q '^OpenGL  ' $rep && grep -q '^CPU governor  ' $rep"
rm -f "$R/tmp/fex-compat-tool-2222.log" "$R/tmp/fex-compat-tool-3333.log"

# notes: host OpenGL on llvmpipe
out=$(bash -c ". $T/harness.sh --help >/dev/null; GL_SUMMARY='llvmpipe (LLVM 19, 128 bits) (GL 4.5, core 4.5)'; info_notes")
check "notes: host llvmpipe warning" "grep -q 'GPU forwarding not active: rendering on CPU (llvmpipe)' <<<\"\$out\""
out=$(bash -c ". $T/harness.sh --help >/dev/null; GL_SUMMARY='V3D 7.1.10.2 (GL 3.1, core 3.1)'; info_notes")
check "notes: no warning on GPU renderer" "! grep -q 'llvmpipe' <<<\"\$out\""

# help page
check "help: CPU-bound and Proton entries" "bash $APP help fixing | grep -q 'Game is slow (CPU-bound)' && bash $APP help fixing | grep -q 'Proton version keeps changing back'"

# restore: a tool chosen now for a game stays; games without a choice get the backup's
D=$(mktemp -d)
mkdir -p "$D/steam-arm-settings/personal"
printf '100 proton_experimental\n200 proton-stable-arm64\n300 steamlinuxruntime\n' > "$D/steam-arm-settings/personal/compattools.txt"
V=$D/config.vdf
printf '"x"\n{\n\t"Steam"\n\t{\n\t\t"CompatToolMapping"\n\t\t{\n\t\t\t"100"\n\t\t\t{\n\t\t\t\t"name"\t\t"proton-stable-arm64"\n\t\t\t}\n\t\t\t"300"\n\t\t\t{\n\t\t\t\t"name"\t\t"steamlinuxruntime"\n\t\t\t}\n\t\t}\n\t}\n}\n' > "$V"
out=$(bash -c ". $T/harness.sh --help >/dev/null; RS_D=$D; RS_NOTE=; bk_path(){ echo $V; }; acct_run(){ shift; \"\$@\"; }; have(){ command -v \"\$1\" >/dev/null; }; SA_COMPATMAP_PY=$INST
rs_plan compat-tools tester; printf '%s\n' \"\${RS_MAP[@]}\"; echo \"\$RS_SUM\"")
check "restore: current choice kept (app 100 stays proton-stable-arm64)" "grep -q '1 to set' <<<\"\$out\" && ! grep -qx '100 proton_experimental' <<<\"\$out\""
check "restore: game without choice gets backup tool (app 200)" "grep -qx '200 proton-stable-arm64' <<<\"\$out\""
check "restore: summary counts kept and unchanged" "grep -q '1 to set, 1 unchanged, 1 kept (other tool chosen here)' <<<\"\$out\""
rm -rf "$D"

# audit D: CPU governor per cpufreq policy
G=$(mktemp -d)
pol(){ mkdir -p "$G/$1/policy$2"; echo "$3" > "$G/$1/policy$2/related_cpus"; echo "$4" > "$G/$1/policy$2/scaling_governor"; echo "$5" > "$G/$1/policy$2/scaling_max_freq"; }
pol rk 0 "0 5 6 7" schedutil 1800000; pol rk 1 "1 2" schedutil 2208000; pol rk 3 "3 4" schedutil 2208000
pol mix 0 "0 5 6 7" schedutil 1800000; pol mix 1 "1 2" performance 2208000; pol mix 3 "3 4" schedutil 2208000
pol pi 0 "0 1 2 3" ondemand 2400000
mkdir -p "$G/none"
gov(){ bash -c ". $T/harness.sh --help >/dev/null; SA_CPUFREQ=$G/$1; cpu_governor"; }
check "governor: clusters grouped (RK3588 layout)" "[ \"\$(gov rk)\" = 'schedutil: cpu 0,5-7 max 1800 MHz, cpu 1-4 max 2208 MHz' ]"
check "governor: mixed governors named per cluster" "[ \"\$(gov mix)\" = 'mixed: cpu 0,5-7 schedutil max 1800 MHz, cpu 1-2 performance max 2208 MHz, cpu 3-4 schedutil max 2208 MHz' ]"
check "governor: one policy (Pi 5)" "[ \"\$(gov pi)\" = 'ondemand: cpu 0-3 max 2400 MHz' ]"
check "governor: no cpufreq gives unknown" "[ \"\$(gov none)\" = unknown ]"
rm -rf "$G"

# audit D: restore summary button leads on, so it is labelled Next
W=$(mktemp -d)
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > %s/args\n' "$W" > "$W/whiptail"; chmod +x "$W/whiptail"
bash -c ". $T/harness.sh --help >/dev/null; PATH=$W:\$PATH; DIALOG=whiptail; ui_size(){ UH=20; UW=70; }; ui_textstr 'Restore settings: summary' 'x' Next"
check "summary button: whiptail OK label Next" "grep -qx -- '--ok-button' $W/args && grep -A1 -x -- '--ok-button' $W/args | tail -1 | grep -qx Next"
bash -c ". $T/harness.sh --help >/dev/null; PATH=$W:\$PATH; DIALOG=whiptail; ui_size(){ UH=20; UW=70; }; ui_textstr 'Fixing a game' 'x'"
check "other text screens keep Back" "grep -A1 -x -- '--ok-button' $W/args | tail -1 | grep -qx Back"
rm -rf "$W"
out=$(python3 $T/ptydrive.py ". $T/harness.sh --help >/dev/null; DIALOG=builtin; ui_textstr 'Restore settings: summary' 'plan text' Next" '\r')
check "summary button: builtin screen shows Next" "grep -q 'Next' <<<\"\$out\" && ! grep -q '< *Back *>' <<<\"\$out\""
check "restore flow passes Next to summary" "grep -q 'ui_textstr \"Restore settings: summary\" \"\$RS_SUM\" Next' $APP"

# audit D: wizard Back from parts returns to Vulkan, also with keys typed while a screen loads
WIZ=". $T/harness.sh --help >/dev/null; DIALOG=builtin; comp_recommended(){ echo x; }; setup_account(){ return 1; }"
out=$(FAKE_NOT_INSTALLED=1 python3 $T/ptydrive.py "$WIZ; menu_setup" '\r' '\r' '\r' '\x1b' '\x1b' '\x1b' | head -1)
check "wizard: Back walks parts > Vulkan > page size > hardware" "[ \"\$out\" = 'SCREENS Install / Setup|Install: hardware|Install: page size|Install: Vulkan|Install: parts|Install: Vulkan|Install: page size|Install: hardware' ]"
out=$(FAKE_NOT_INSTALLED=1 python3 $T/ptydrive.py "$WIZ; vk_summary(){ sleep 3; echo 'Mali-G610, panvk, API 1.3'; }; menu_setup" '\r' '\r' @4 '\r' @4 '\x1b' @0.5 '\x1b' @5 | head -1)
check "wizard: Esc typed while Vulkan loads does not skip it" "[ \"\${out##*|}\" = 'Install: Vulkan' ]"
C=$(mktemp)
out=$(FAKE_NOT_INSTALLED=1 python3 $T/ptydrive.py "$WIZ; detect_raw(){ [ \"\$DETECT_DONE\" = 1 ] || echo run >> $C; DETECT_DONE=1; echo 'family: mali-csf-v10'; }; menu_setup" '\r' '\r' '\r' '\x1b' '\x1b' '\x1b' | head -1)
check "wizard: detection runs once for the whole walk" "[ \"\$(wc -l < $C)\" = 1 ]"
rm -f "$C"

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
