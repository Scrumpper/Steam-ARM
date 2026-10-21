#!/bin/bash
# 3.1 Raspberry Pi 4 detection: setup functions (cpu_lse, platform_pick, gpu_family_of, fex_arch, client_pick) on fake
# cpuinfo, device-tree and render-node facts (Pi 4, Pi 5, RK3588 stand-ins); settings keys CPU_LSE, CPU_CORES,
# PLATFORM, MESA_HOST written by setup and printed by --detect; menu hw_guess from device-tree compatible; launcher
# slow-emulation class and session line; handler platform() and slow_class(). Functions extracted from the installer
# under test (SARM_INST picks another), /proc paths pointed at the fake tree in the extracts only. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm31-pi4.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }

check "installer parses (bash -n)" "bash -n '$INST'"
# fake trees: one folder per board, cpuinfo + device-tree compatible and model
board(){ # name part features compat model
  local d=$T/$1; mkdir -p "$d/dt"
  printf 'processor\t: 0\nBogoMIPS\t: 108.00\nFeatures\t: %s\nCPU implementer\t: 0x41\nCPU architecture: 8\nCPU variant\t: 0x0\nCPU part\t: %s\nCPU revision\t: 3\n\n' "$3" "$2" > "$d/cpuinfo"
  for i in 1 2 3; do sed "s/^processor\t: 0/processor\t: $i/" "$d/cpuinfo" | head -n 9 >> "$d/cpuinfo"; done
  printf '%s' "$4" | tr ',' '\0' > "$d/dt/compatible"; printf '%s\0' "$5" > "$d/dt/model"
}
board pi4 0xd08 "fp asimd evtstrm crc32 cpuid" "raspberrypi;4-model-b,brcm;bcm2711" "Raspberry Pi 4 Model B Rev 1.4"
board pi5 0xd0b "fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp" "raspberrypi;5-model-b,brcm;bcm2712" "Raspberry Pi 5 Model B Rev 1.0"
board rk3588 0xd0b "fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp" "rockchip;rk3588" "Test Board RK3588"
for b in pi4 pi5 rk3588; do sed -i 's/;/,/g' "$T/$b/dt/compatible"; done
# setup functions with /proc paths of board $1
setup_fns(){
  { fn cpu_features "$INST"; fn cpu_lse "$INST"; fn cpu_label "$INST"; fn cpu_line "$INST"; fn platform_pick "$INST"
    fn mesa_host "$INST"; fn gpu_family_of "$INST"; fn fex_arch "$INST"; fn client_pick "$INST"; } \
    | sed -e "s#/proc/cpuinfo#$T/$1/cpuinfo#g" -e "s#/proc/device-tree/#$T/$1/dt/#g"
}
srun(){ # board command...
  local b=$1; shift
  ( conf_get(){ :; }; OPT_CLIENT=; STEAM_ARM_ALLOW_ARMV80=0; eval "$(setup_fns "$b")"; eval "$*" ) 2>&1
}
OUT=$(srun pi4 'gpu_family_of v3d "brcm,2711-v3d" - -; cpu_lse && echo lse=1 || echo lse=0; fex_arch; client_pick; echo "$CLIENT $CLIENT_SET"; platform_pick broadcom-v3d42; cpu_line')
check "D1 Pi 4 stand-in: family broadcom-v3d42 (rank 20), no LSE, FEX build 8.0, client x86 auto, platform pi4, Cortex-A72 named" \
  "[ \"\$(sed -n 1p <<<\"\$OUT\")\" = 'broadcom-v3d42 20' ] && grep -qx lse=0 <<<\"\$OUT\" && grep -qx 8.0 <<<\"\$OUT\" && grep -qx 'x86 auto' <<<\"\$OUT\" && grep -qx pi4 <<<\"\$OUT\" && grep -q 'Cortex-A72 x4, Armv8.0 (no LSE atomics)' <<<\"\$OUT\""
OUT=$(srun pi5 'gpu_family_of v3d "brcm,2712-v3d" - -; cpu_lse && echo lse=1 || echo lse=0; fex_arch; client_pick; echo "$CLIENT $CLIENT_SET"; platform_pick broadcom-v3d71')
check "D2 Pi 5 stand-in: family broadcom-v3d71, LSE, FEX build 8.2, client arm64 auto, platform pi5" \
  "[ \"\$(sed -n 1p <<<\"\$OUT\")\" = 'broadcom-v3d71 25' ] && grep -qx lse=1 <<<\"\$OUT\" && grep -qx 8.2 <<<\"\$OUT\" && grep -qx 'arm64 auto' <<<\"\$OUT\" && grep -qx pi5 <<<\"\$OUT\""
OUT=$(srun rk3588 'cpu_lse && echo lse=1 || echo lse=0; p=$(platform_pick mali-csf-v10); echo "platform=[$p]"; p=$(platform_pick broadcom-v3d42); echo "v3d42=[$p]"')
check "D3 RK3588 stand-in: LSE, platform empty, even with v3d42 family named by hand (no bcm2711 in device tree)" "grep -qx lse=1 <<<\"\$OUT\" && grep -qx 'platform=\[\]' <<<\"\$OUT\" && grep -qx 'v3d42=\[\]' <<<\"\$OUT\""
OUT=$(srun pi4 'platform_pick broadcom-vc4; platform_pick broadcom-v3d71; echo end')
check "D4 Pi 4 device tree: vc4 family -> pi-other; v3d71 family (wrong hand pick) -> nothing printed" "[ \"\$OUT\" = \$'pi-other\nend' ]"
# Pi 4 device tree without model file (compat only) still gives pi4
rm -f "$T/pi4/dt/model"; OUT=$(srun pi4 'platform_pick broadcom-v3d42'); printf 'Raspberry Pi 4 Model B Rev 1.4\0' > "$T/pi4/dt/model"
check "D5 compatible brcm,bcm2711 alone (no model file) -> pi4" "[ \"\$OUT\" = pi4 ]"
# model string alone (device tree without bcm compat, as a stand-in board gives) -> pi4
printf 'raspberrypi,4-model-b\0' > "$T/pi4/dt/compatible"; OUT=$(srun pi4 'platform_pick broadcom-v3d42'); printf 'raspberrypi,4-model-b\0brcm,bcm2711\0' > "$T/pi4/dt/compatible"
check "D6 model string alone -> pi4" "[ \"\$OUT\" = pi4 ]"

# setup writes the four keys beside GPU_FAMILY; --detect prints them
OUT=$(grep -n 'conf_set CPU_LSE\|conf_set CPU_CORES\|conf_set PLATFORM\|conf_set MESA_HOST\|conf_set VK_HOST\|conf_set GPU_FAMILY_SET' "$INST")
check "D7 setup writes CPU_LSE, CPU_CORES, PLATFORM (platform_pick of GPU_FAMILY), MESA_HOST, VK_HOST after GPU_FAMILY_SET" \
  "[ \$(grep -c . <<<\"\$OUT\") = 6 ] && grep -q 'conf_set CPU_LSE \"\$(cpu_lse && echo 1 || echo 0)\"' <<<\"\$OUT\" && grep -q 'conf_set PLATFORM \"\$(platform_pick \"\$GPU_FAMILY\")\"' <<<\"\$OUT\" && grep -q 'conf_set MESA_HOST \"\$(mesa_host)\"' <<<\"\$OUT\" && grep -q 'conf_set VK_HOST \"\$(vk_host \"\$GPU_FAMILY\")\"' <<<\"\$OUT\" && [ \$(head -1 <<<\"\$OUT\" | cut -d: -f1) -lt \$(tail -1 <<<\"\$OUT\" | cut -d: -f1) ]"
GR=$(fn gpu_report "$INST")
check "D8 --detect prints cpu lse, cpu cores, platform, mesa host and vulkan host lines" "grep -q 'echo \"cpu lse: ' <<<\"\$GR\" && grep -q 'echo \"cpu cores: ' <<<\"\$GR\" && grep -q 'echo \"platform: \${v:-none}\"' <<<\"\$GR\" && grep -q 'echo \"mesa host: \${v:-unknown}\"' <<<\"\$GR\" && grep -q 'echo \"vulkan host: \${v:-n/a}\"' <<<\"\$GR\""
# Vulkan class from the host Mesa version (Broadcom families only)
vkh(){ ( eval "$(fn vk_host "$INST")"; mesa_host(){ echo "$MH"; }; MH=$2; v=$(vk_host "$1"); echo "[$v]" ) 2>&1; }
OUT=$(vkh broadcom-v3d42 "24.2.8-1~bpo12+rpt5"); check "VK1 bookworm Mesa 24.2.8 on v3d42 -> 1.2" "[ \"\$OUT\" = '[1.2]' ]"
OUT=$(vkh broadcom-v3d42 "26.2.2-1~bpo13+0~rpt1"); check "VK2 trixie Mesa 26.2.2 -> 1.3" "[ \"\$OUT\" = '[1.3]' ]"
OUT=$(vkh broadcom-v3d71 "2:24.3.0-1"); check "VK3 epoch stripped, 24.3 -> 1.3" "[ \"\$OUT\" = '[1.3]' ]"
OUT=$(vkh mali-csf-v10 "26.2.2-1"); check "VK4 other family: empty" "[ \"\$OUT\" = '[]' ]"
OUT=$(vkh broadcom-v3d42 ""); check "VK5 no Mesa package: empty" "[ \"\$OUT\" = '[]' ]"
OUT=$(vkh broadcom-v3d42 "garbage"); check "VK6 unparsable version: empty" "[ \"\$OUT\" = '[]' ]"
check "VK7 handler start record carries vkhost from the settings file; report verdict cross-checks VK_HOST against vulkaninfo" "grep -q '(\"vkhost\", conf_value(\"VK_HOST\") or \"-\")' '$INST' && grep -q '^  echo \"vulkan host: \${vkh:-n/a} (settings file VK_HOST); vulkaninfo' '$INST'"
# setup block for the x86 client: levels, measure command, Pi line only on Pi platforms
XW=$(sed -n '/^x86_warn(){/,/^}/p' "$INST")
check "XW1 x86 client setup block names the CPU-class expectation, lighter window, three levels and --cpu-report" "grep -q 'high CPU use while window is open' <<<\"\$XW\" && grep -q 'site' <<<\"\$XW\" && grep -q 'Levels: always on CPU' <<<\"\$XW\" && grep -q 'steam-arm --cpu-report' <<<\"\$XW\" && grep -q 'pi_class_line' <<<\"\$XW\""
OUT=$( eval "$(fn pi_class_line "$INST")"; platform_pick(){ echo pi4; }; vk_host(){ echo 1.2; }; mesa_host(){ echo 24.2.8-1~bpo12+rpt5; }; XDG_SESSION_TYPE=wayland; GPU_FAMILY=broadcom-v3d42; pgrep(){ return 1; }; pi_class_line )
check "XW2 Pi line: host Mesa, Vulkan class, session" "[ \"\$OUT\" = '       Raspberry Pi: host Mesa 24.2.8-1~bpo12+rpt5, Vulkan 1.2 class (V3DV), session wayland.' ]"
OUT=$( eval "$(fn pi_class_line "$INST")"; platform_pick(){ :; }; pi_class_line; echo "[end]" )
check "XW3 not a Pi platform: no line" "[ \"\$OUT\" = '[end]' ]"
OUT=$(bash -c "cd '$T' && env -i HOME='$T' PATH=/usr/bin:/bin bash '$INST' --detect" 2>&1)
check "D9 --detect on this host: platform line present (none or pi value), cpu lse 0 or 1" "grep -qE '^platform: (none|pi4|pi5|pi-other)$' <<<\"\$OUT\" && grep -qE '^cpu lse: [01]$' <<<\"\$OUT\" && grep -qE '^cpu cores: [0-9]+$' <<<\"\$OUT\""

# menu hw_guess: compatible alone names the board
hwt(){ awk '/^hw_table\(\)\{ cat <<.HW.$/{f=1} f{print} f && /^}$/{exit}' "$CFG"; }
mfns(){ { hwt; fn hw_guess "$CFG"; fn hw_model "$CFG"; fn hw_label "$CFG"; } | sed -e "s#\"/proc/device-tree/#\"$T/$1/dt/#g" -e "s#\"/sys/class/dmi/id/#\"$T/$1/nodmi/#g"; }
mrun(){ local b=$1; shift; ( trim(){ sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }; gpu_family(){ echo "${FAM:-none}"; }; eval "$(mfns "$b")"; eval "$*" ) 2>&1; }
printf 'brcm,bcm2711\0' > "$T/pi4/dt/compatible"; rm -f "$T/pi4/dt/model"
OUT=$(mrun pi4 hw_guess); check "D10 menu hw_guess: compatible brcm,bcm2711 without model -> rpi4" "[ \"\$OUT\" = rpi4 ]"
printf 'raspberrypi,4-model-b\0brcm,bcm2711\0' > "$T/pi4/dt/compatible"; printf 'Raspberry Pi 4 Model B Rev 1.4\0' > "$T/pi4/dt/model"
printf 'brcm,bcm2712\0' > "$T/pi5/dt/compatible"; rm -f "$T/pi5/dt/model"
OUT=$(mrun pi5 hw_guess); check "D11 menu hw_guess: compatible brcm,bcm2712 without model -> rpi5" "[ \"\$OUT\" = rpi5 ]"
printf 'raspberrypi,5-model-b\0brcm,bcm2712\0' > "$T/pi5/dt/compatible"; printf 'Raspberry Pi 5 Model B Rev 1.0\0' > "$T/pi5/dt/model"
OUT=$(mrun rk3588 hw_guess); check "D12 menu hw_guess: RK3588 unchanged" "[ \"\$OUT\" = rk3588 ]"

# launcher: slow emulation class and session line
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
check "D13 launcher parses (sh -n)" "sh -n $L"
SB=$T/slow.sh; awk '/^# Slow emulation class: x86 client on a CPU without LSE atomics/{f=1} f{print} f && /^llog "session: /{exit}' "$L" > "$SB"
check "D13b slow class block present, after LSE check, before page size check" \
  "grep -q 'export STEAM_ARM_SLOW=\"\$SLOW\" STEAM_ARM_PLATFORM=\"\$PLATFORM\"' $SB && [ \$(grep -n '^# Slow emulation class: x86 client' $L | cut -d: -f1) -gt \$(grep -n '^# Client needs Armv8.1 atomics' $L | cut -d: -f1) ] && [ \$(grep -n '^# Slow emulation class: x86 client' $L | cut -d: -f1) -lt \$(grep -n '^# Emulation needs 4K pages' $L | cut -d: -f1) ]"
sl(){ # CLIENT CPU_LSE(or -) PLATFORM(or -) CPUF
  rm -f "$T/sl.log"
  ( CLIENT=$1; [ "$2" = - ] || CPU_LSE=$2; [ "$3" = - ] || PLATFORM=$3; CPUF=$4; LOG=$T/sl.log
    llog(){ printf '%s\n' "$*" >> "$LOG"; }
    unset XDG_SESSION_TYPE XDG_CURRENT_DESKTOP
    . "$SB"; echo "slow=$STEAM_ARM_SLOW platform=[$STEAM_ARM_PLATFORM]" ) 2>&1; cat "$T/sl.log"; }
OUT=$(sl x86 0 pi4 "Features	: fp asimd evtstrm crc32 cpuid")
check "D14 x86 client, CPU_LSE=0, PLATFORM=pi4: STEAM_ARM_SLOW=1, STEAM_ARM_PLATFORM=pi4, session line logged" \
  "grep -qx 'slow=1 platform=\[pi4\]' <<<\"\$OUT\" && grep -q '^session: unknown, desktop unknown.*, platform pi4, slow emulation class 1$' <<<\"\$OUT\""
OUT=$(sl x86 - - "Features	: fp asimd evtstrm crc32 cpuid")
check "D15 settings file without CPU_LSE (3.0 setup): class from this CPU's Features line, platform empty" "grep -qx 'slow=1 platform=\[\]' <<<\"\$OUT\" && grep -q 'platform none, slow emulation class 1' <<<\"\$OUT\""
OUT=$(sl x86 - - "Features	: fp asimd atomics cpuid")
check "D16 x86 client by hand on an LSE CPU: not slow class" "grep -qx 'slow=0 platform=\[\]' <<<\"\$OUT\""
OUT=$(sl arm64 0 pi5 "Features	: fp asimd evtstrm crc32 cpuid")
check "D17 native client: never slow class, platform passed on" "grep -qx 'slow=0 platform=\[pi5\]' <<<\"\$OUT\""
OUT=$(sl x86 1 - "")
check "D18 CPU_LSE=1 from setup wins over an empty Features line" "grep -qx 'slow=0 platform=\[\]' <<<\"\$OUT\""
# launcher: one notice at the first start on the slow class
NB=$T/notice.sh; awk '/^# Slow class, first start in this client home: one notice/{f=1} f{print} f && /^fi$/{exit}' "$L" > "$NB"
nrun(){ # SLOW env(-) keep-home(0|1)
  [ "$3" = 1 ] || { rm -rf "$T/nh"; mkdir -p "$T/nh"; }
  ( SLOW=$1 ARMHOME=$T/nh LOG=$T/nh.log DISPLAY=:0; unset STEAM_ARM_SLOW_HINT; [ "$2" = - ] || export STEAM_ARM_SLOW_HINT=$2; rm -f "$T/nh.log"
    notice(){ echo "NOTICE $2|$3" >> "$T/nh.log"; }; llog(){ echo "$*" >> "$T/nh.log"; }; . "$NB"; wait ) 2>&1; cat "$T/nh.log" 2>/dev/null; cat "$T/nh/.config/steam-arm/state" 2>/dev/null; }
OUT=$(nrun 1 - 0); check "N1 slow class, first start: notice names CPU class, renderer line and --cpu-report; marker written" "grep -q '^NOTICE Steam ARM: this CPU class|Client window is drawn by CPU through emulation' <<<\"\$OUT\" && grep -q 'renderer:' <<<\"\$OUT\" && grep -q 'steam-arm --cpu-report' <<<\"\$OUT\" && grep -qx 'slow-notice=shown' <<<\"\$OUT\""
OUT=$(nrun 1 - 1); check "N2 second start, same home: no notice, marker once" "! grep -q NOTICE <<<\"\$OUT\" && [ \$(grep -c 'slow-notice=shown' <<<\"\$OUT\") = 1 ]"
OUT=$(nrun 1 0 0); check "N3 STEAM_ARM_SLOW_HINT=0: no notice, no marker" "! grep -q 'NOTICE\|slow-notice' <<<\"\$OUT\""
OUT=$(nrun 0 - 0); check "N4 not slow class: nothing" "[ -z \"\$OUT\" ]"
rm -rf "$T/nh"; mkdir -p "$T/nh/.config/steam-arm"; printf 'cef-gpu=ok:vulkan\n' > "$T/nh/.config/steam-arm/state"
OUT=$(nrun 1 - 1); check "N5 state file with other lines: marker appended, other line kept" "[ \"\$(tail -n 2 <<<\"\$OUT\" | paste -sd,)\" = 'cef-gpu=ok:vulkan,slow-notice=shown' ]"

# handler: platform() and slow_class() from environment, else settings file
H=$T/handler.py
awk '/^cat > \/usr\/local\/lib\/steam-arm-handler.py <<.HANDLERPY.$/{f=1;next} /^HANDLERPY$/{f=0} f' "$INST" > "$H"
python3 - "$H" "$T" > "$T/hp.out" 2>&1 <<'EOF'
import os, re, sys
src = open(sys.argv[1]).read()
conf = os.path.join(sys.argv[2], "conf")
def fnsrc(name):
    m = re.search(r"^def %s\([^)]*\):\n(?:    .*\n|\n)*" % name, src, re.M)
    return m.group(0)
code = fnsrc("conf_value").replace('"/etc/steam-arm/steam-arm.conf"', repr(conf)) + fnsrc("platform") + fnsrc("slow_class")
g = {"os": os, "CLIENT_X86": True}
exec(code, g)
open(conf, "w").write("CPU_LSE=0\nPLATFORM=pi4\n")
os.environ.pop("STEAM_ARM_PLATFORM", None); os.environ.pop("STEAM_ARM_SLOW", None)
print("conf", g["platform"](), g["slow_class"]())
os.environ["STEAM_ARM_PLATFORM"] = ""; os.environ["STEAM_ARM_SLOW"] = "0"
print("env", repr(g["platform"]()), g["slow_class"]())
os.environ["STEAM_ARM_PLATFORM"] = "pi5"; os.environ["STEAM_ARM_SLOW"] = "1"
print("env2", g["platform"](), g["slow_class"]())
g["CLIENT_X86"] = False; os.environ.pop("STEAM_ARM_SLOW")
print("native", g["slow_class"]())
EOF
OUT=$(cat "$T/hp.out")
check "D19 handler platform()/slow_class(): settings file, empty environment wins over file, native client never slow" \
  "grep -qx 'conf pi4 True' <<<\"\$OUT\" && grep -qx \"env '' False\" <<<\"\$OUT\" && grep -qx 'env2 pi5 True' <<<\"\$OUT\" && grep -qx 'native False' <<<\"\$OUT\""

# launcher: reduced x87 precision environment for the client helper
XB=$T/x87.sh; awk '/^# Reduced x87 precision for the 32-bit client binary/{f=1} f{print} f && /^export STEAM_ARM_X87$/{exit}' "$L" > "$XB"
x87(){ ( unset STEAM_ARM_X87 X87_CLIENT; [ "$1" = - ] || X87_CLIENT=$1; [ "$2" = - ] || export STEAM_ARM_X87=$2; . "$XB"; echo "$STEAM_ARM_X87" ) 2>&1; }
OUT=$(x87 on -); check "X1 X87_CLIENT=on -> STEAM_ARM_X87=reduced" "[ \"\$OUT\" = reduced ]"
OUT=$(x87 - -); check "X2 no setting -> exact (off by default)" "[ \"\$OUT\" = exact ]"
OUT=$(x87 on exact); check "X3 environment STEAM_ARM_X87=exact wins over setting on" "[ \"\$OUT\" = exact ]"
OUT=$(x87 off reduced); check "X4 environment reduced wins over setting off" "[ \"\$OUT\" = reduced ]"
OUT=$(x87 on bogus); check "X5 unknown environment value falls back to setting" "[ \"\$OUT\" = reduced ]"

# launcher: client window restart counter (slow emulation class only)
RW=$T/rw.sh; awk '/^  wh_restart_watch\(\)\{/{f=1} f{print} f && /^  }$/{exit}' "$L" > "$RW"
check "R0 restart watcher extracted, started in background before the normal x86 start loop" \
  "[ -s $RW ] && grep -q '^  wh_restart_watch </dev/null >/dev/null 2>&1 &$' $L && [ \$(grep -n '^  wh_restart_watch </dev/null' $L | cut -d: -f1) -lt \$(grep -n 'client_x86 \$XFLAGS \${GPUI:+\"\$GPUI\"} -noverifyfiles' $L | cut -d: -f1) ]"
rw(){ # SLOW XOK(1/0) STATE(1/0) pid-sequence...
  local slow=$1 xok=$2 st=$3; shift 3; rm -rf "$T/rw"; mkdir -p "$T/rw/.config/steam-arm" "$T/rw/bin"
  [ "$xok" = 1 ] && : > "$T/rw/.config/steam-arm/x86-verified"; [ "$st" = 1 ] && echo 1 > "$T/rw/.config/steam-arm/multiblock-client"
  printf '%s\n' "$@" > "$T/rw/q"
  printf '#!/bin/sh\necho "py $*" >> "%s/rw/calls"\n' "$T" > "$T/rw/bin/python3"; chmod 755 "$T/rw/bin/python3"
  ( SLOW=$slow ARMHOME=$T/rw S=$T/rw/S XOK=$T/rw/.config/steam-arm/x86-verified MBSTATE=$T/rw/.config/steam-arm/multiblock-client PATH=$T/rw/bin:$PATH
    sleep(){ :; }; date(){ if [ -e "$T/rw/t0" ]; then echo 2000; else : > "$T/rw/t0"; echo 1000; fi; }
    # client gone once the pid queue is empty, or after 20 looks (watcher loops that never read the queue)
    client_running(){ echo . >> "$T/rw/cr"; [ "$(grep -c . "$T/rw/cr")" -le 20 ] && [ -s "$T/rw/q" ]; }
    pgrep(){ head -n 1 "$T/rw/q"; sed -i 1d "$T/rw/q"; }
    lnote(){ echo "NOTE $1 | $2" >> "$T/rw/calls"; }
    . "$RW"; wh_restart_watch; echo "rc=$?" ) 2>&1; cat "$T/rw/calls" 2>/dev/null; }
OUT=$(rw 1 1 0 100 100 200 200 300 400 400)
check "R1 slow class, three changes of the oldest steamwebhelper pid: multiblock-off once, state file, one notice" \
  "[ \$(grep -c 'multiblock-off ' <<<\"\$OUT\") = 1 ] && grep -q \"^py /usr/local/lib/steam-arm-x86client.py multiblock-off $T/rw/S $T/rw\$\" <<<\"\$OUT\" && grep -q '^NOTE steamwebhelper restarted 3 times: FEX Multiblock off for client window from next start; delete .fex-emu/AppConfig/steamwebhelper.json and exe.json in client home to retry | Steam ARM: client window' <<<\"\$OUT\" && [ -s $T/rw/.config/steam-arm/multiblock-client ] && grep -q '^rc=0' <<<\"\$OUT\""
OUT=$(rw 1 1 0 100 100 200 200 300)
check "R2 two changes only, client gone: nothing written, no notice" "! grep -q 'py\\|NOTE' <<<\"\$OUT\" && [ ! -e $T/rw/.config/steam-arm/multiblock-client ]"
OUT=$(rw 0 1 0 100 200 300 400 500)
check "R3 not slow class: watcher returns at once" "! grep -q 'py\\|NOTE' <<<\"\$OUT\" && [ -s $T/rw/q ]"
OUT=$(rw 1 1 1 100 200 300 400 500)
check "R4 state file present (fired before): nothing done" "! grep -q 'py\\|NOTE' <<<\"\$OUT\" && [ -s $T/rw/q ]"
OUT=$(rw 1 0 0 100 200 300 400 500)
check "R5 file check marker missing (first start): never counts" "! grep -q 'py\\|NOTE' <<<\"\$OUT\""
rw1(){ rm -rf "$T/rw"; mkdir -p "$T/rw/.config/steam-arm"; : > "$T/rw/.config/steam-arm/x86-verified"; printf '%s\n' 100 200 300 400 500 > "$T/rw/q"
  ( SLOW=1 ARMHOME=$T/rw S=$T/rw/S XOK=$T/rw/.config/steam-arm/x86-verified MBSTATE=$T/rw/.config/steam-arm/multiblock-client; sleep(){ :; }; date(){ echo 1000; }
    client_running(){ echo . >> "$T/rw/cr"; [ "$(grep -c . "$T/rw/cr")" -le 20 ] && [ -s "$T/rw/q" ]; }; pgrep(){ head -n 1 "$T/rw/q"; sed -i 1d "$T/rw/q"; }; lnote(){ echo "NOTE" >> "$T/rw/calls"; }
    python3(){ echo py >> "$T/rw/calls"; }; . "$RW"; wh_restart_watch ) 2>&1; cat "$T/rw/calls" 2>/dev/null; }
OUT=$(rw1); check "R6 within 5 minute grace: pid changes not counted" "! grep -q 'py\\|NOTE' <<<\"\$OUT\""

# menu: Maintenance item 19 for x86 client type, CLI x87-client, backup key
T0=$SARM_TESTS/config-ui
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
bash "$T0/mkfake.sh" >/dev/null
sed -e "s#^APP=.*#APP=\"$CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"
export Q=$T/q LOG=$T/ui.log
cat > "$T/stubs.sh" <<'EOF'
nxt(){ A=$(head -n 1 "$Q"); sed -i 1d "$Q"; }
ui_menu(){ printf 'MENU %s|%s|%s\n' "$1" "$2" "${*:3}" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; echo "$A"; }
ui_msg(){ printf 'MSG %s|%s\n' "$1" "$2" >> "$LOG"; }
ui_textstr(){ printf 'TEXT %s\n' "$1" >> "$LOG"; }
ui_info(){ :; }
ui_yesno(){ printf 'YESNO %s|%s\n' "$1" "$2" >> "$LOG"; nxt; [ "$A" = yes ]; }
up_notice(){ :; }; up_check_open(){ :; }; state_pending(){ return 1; }; status_line(){ :; }
EOF
ui(){ local s=$1; shift; : > "$LOG"; printf '%s\n' "$@" > "$Q"; bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; $s" >/dev/null 2>"$T/err"; RC=$?; OUT=$(cat "$LOG" "$T/err"); }
cli(){ OUT=$(bash -c ". $T/harness.sh --help >/dev/null; main $*" 2>&1); RC=$?; }
CONF=$SARM_UI_FAKE/etc/steam-arm/steam-arm.conf
echo CLIENT=x86 >> "$CONF"
ui menu_maintenance 19 BACK
check "M1 x86 client: Maintenance item 19 Faster client start (now: off); screen names FEX X87ReducedPrecision and rendering errors" \
  "grep -q ' 19 Faster client start, reduced x87 precision (now: off)' <<<\"\$OUT\" && grep -q '^YESNO Reduced x87 precision|Reduced x87 precision for client: off' <<<\"\$OUT\" && grep -q 'X87ReducedPrecision' <<<\"\$OUT\" && grep -q 'rendering errors' <<<\"\$OUT\""
ui menu_maintenance 19 yes BACK
check "M2 Turn on: X87_CLIENT=on written, message names next start" "grep -qx 'X87_CLIENT=on' '$CONF' && grep -q '^MSG Maintenance|Reduced x87 precision for client: on. Applies from next start of Steam ARM.' <<<\"\$OUT\""
ui menu_maintenance 19 yes BACK
check "M3 Turn off: X87_CLIENT=off" "grep -qx 'X87_CLIENT=off' '$CONF'"
sed -i 's/^CLIENT=x86$/CLIENT=arm64/' "$CONF"
ui menu_maintenance BACK
check "M4 native client: no item 19" "! grep -q ' 19 Faster client start' <<<\"\$OUT\""
cli x87-client; check "M5 CLI state line" "[ $RC = 0 ] && grep -q '^reduced x87 precision for client: off$' <<<\"\$OUT\""
cli x87-client on; check "M5b CLI on writes key" "[ $RC = 0 ] && grep -qx 'X87_CLIENT=on' '$CONF'"
cli x87-client maybe; check "M5c CLI bad value: usage, status 2" "[ $RC = 2 ]"
cli --help; check "M6 --help lists x87-client and X87_CLIENT" "grep -q '^  x87-client \\[on|off\\]' <<<\"\$OUT\" && grep -q 'X87_CLIENT=on|off' <<<\"\$OUT\""
check "M7 X87_CLIENT and CLIENT_LIGHT in backup key list and value rule" "grep -q '^SA_BK_KEYS=.* X87_CLIENT CLIENT_LIGHT' '$CFG' && grep -q 'UPDATE_CHECK_ON_OPEN|X87_CLIENT|CLIENT_LIGHT' '$CFG' && grep -q 'CLIENT_LIGHT|CLIENT_GPU[|)].*case \"\$2\" in on|off|\"\") return 0;; esac; return 1;;' '$CFG'"

# launcher: GPU forwarding notice on Pi platforms when the copied FEX config has thunks off
TN=$T/tn.sh; awk '/^# GPU forwarding libraries: ThunksDB GL or Vulkan 0 in the copied FEX config/{f=1} f{print} f && /^esac$/{exit}' "$L" > "$TN"
check "T0 notice block present after the FEX config copy" "grep -q 'GPU forwarding libraries not found: every game draws on CPU' $TN && [ \$(grep -n '^# GPU forwarding libraries: ThunksDB' $L | cut -d: -f1) -gt \$(grep -n '^FEXCFG=' $L | cut -d: -f1) ]"
tn(){ # PLATFORM config-json
  rm -f "$T/tn.log" "$T/tn.notes"; printf '%s\n' "$2" > "$T/tn.json"
  ( PLATFORM=$1 FEXCFG=$T/tn.json DISPLAY=:9; lwarn(){ echo "$*" >> "$T/tn.log"; }; notice(){ echo "NOTICE $2 | $3 | $4" >> "$T/tn.notes"; }; . "$TN"; wait ) 2>&1; cat "$T/tn.log" "$T/tn.notes" 2>/dev/null; }
OUT=$(tn pi4 '{ "Config": { "RootFS":"/opt/x" }, "ThunksDB":{"GL":0,"Vulkan":0} }')
check "T1 pi4, thunks off: warning logged with config path, notice that stays (timeout 0) names package and Update / Repair" \
  "grep -q 'GPU forwarding libraries not found.*(ThunksDB in $T/tn.json)' <<<\"\$OUT\" && grep -q '^NOTICE Steam ARM: GPU forwarding off | GPU forwarding libraries not found: every game draws on CPU. Fix: install FEX again (package fex-emu-armv8.0 from FEX.s package source), then sudo steam-arm-config, Maintenance, Update / Repair. | 0$' <<<\"\$OUT\""
OUT=$(tn pi4 '{ "Config": { "RootFS":"/opt/x", "ThunkHostLibs":"/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks/" }, "ThunksDB":{"GL":1,"Vulkan":1} }')
check "T2 pi4, thunks on: nothing" "[ -z \"\$OUT\" ]"
OUT=$(tn "" '{ "ThunksDB":{"GL":0,"Vulkan":0} }'); check "T3 other board, thunks off: nothing (forwarding may be off on purpose)" "[ -z \"\$OUT\" ]"
OUT=$(tn mali '{ "ThunksDB":{"GL":0,"Vulkan":0} }'); check "T3b non-pi platform value: nothing" "[ -z \"\$OUT\" ]"
OUT=$(tn pi5 '{ "ThunksDB":{"GL":1,"Vulkan":0} }'); check "T4 pi5, Vulkan thunk off alone: notice" "grep -q '^NOTICE Steam ARM: GPU forwarding off' <<<\"\$OUT\""
rm -f "$T/tn.json"; OUT=$(tn pi4 ''); rm -f "$T/tn.json"; OUT=$( rm -f "$T/tn.log" "$T/tn.notes"; ( PLATFORM=pi4 FEXCFG=$T/none.json DISPLAY=:9; lwarn(){ echo "$*" >> "$T/tn.log"; }; notice(){ echo N >> "$T/tn.notes"; }; . "$TN"; wait ); cat "$T/tn.log" "$T/tn.notes" 2>/dev/null )
check "T5 config file missing: nothing" "[ -z \"\$OUT\" ]"

# menu: Information > Steam ARM status row GPU forwarding
FC=$SARM_UI_FAKE/home/tester/.fex-emu/Config.json; mkdir -p "${FC%/*}"
printf '{ "Config": { "RootFS":"/opt/x" },\n  "ThunksDB":{"GL":1,"Vulkan":1} }\n' > "$FC"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; info_status" 2>&1)
check "I1 Information status: GPU forwarding on (GL, Vulkan) before FEX tool row" "grep -q '^GPU forwarding on (GL, Vulkan)$' <<<\"\$OUT\" && [ \$(grep -n '^GPU forwarding' <<<\"\$OUT\" | cut -d: -f1) -lt \$(grep -n '^FEX tool' <<<\"\$OUT\" | cut -d: -f1) ]"
printf '{ "Config": { "RootFS":"/opt/x" },\n  "ThunksDB":{"GL":0,"Vulkan":0} }\n' > "$FC"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; info_status" 2>&1)
check "I2 thunks off: row says off, libraries not found, games draw on CPU (folded)" "grep -q '^GPU forwarding off (FEX thunk libraries not found at setup; games draw$' <<<\"\$OUT\" && grep -q '^ *on CPU)$' <<<\"\$OUT\""
rm -f "$FC"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; info_status" 2>&1)
check "I3 no FEX config: unknown" "grep -q '^GPU forwarding unknown (no FEX config for game account)' <<<\"\$OUT\""

# distro matrix: Pi 4 row and its stand-ins
DM=$SARM_GATES/distro-matrix.sh
if [ -f "$DM" ]; then
  check "DM1 row raspios-pi4 (install, trixie-slim) listed" "bash '$DM' --list | grep -q '^raspios-pi4 *install *Raspberry Pi OS trixie, Pi 4 model'"
  check "DM2 Pi 4 stand-ins: Cortex-A72 part without atomics, bcm2711 compatible, 2711-v3d render node, SIGILL client stand-in" \
    "grep -q 'feat=\"fp asimd evtstrm crc32 cpuid\"; part=0xd08; : > \"\$R/sim/nolse\"' '$DM' && grep -q \"printf 'raspberrypi,4-model-b\\\\\\\\0brcm,bcm2711\\\\\\\\0'\" '$DM' && grep -q \"printf 'brcm,2711-v3d\\\\\\\\0'\" '$DM' && grep -q 'kill -ILL' '$DM'"
  check "DM3 x86 client stand-ins: manifest-x86, bootstrap and runtime zips served by the curl stand-in" \
    "grep -q 'steam_client_ubuntu12) cp /sim/www/manifest-x86' '$DM' && grep -q 'steam_ubuntu12.zip.\\*) cp /sim/www/x86boot.zip' '$DM' && grep -q 'runtime_scout_ubuntu12.zip.\\*) cp /sim/www/x86rt.zip' '$DM'"
  check "DM4 Pi 4 row checks: settings keys, FEX build 8.0 with MESA_HOST, x86 files, PPA package thunk files" \
    "grep -q 'CLIENT=x86 CLIENT_SET=auto CPU_LSE=0 GPU_FAMILY=broadcom-v3d42 PLATFORM=pi4' '$DM' && grep -q 'apt-get download fex-emu-armv8.0' '$DM' && grep -q 'FEX build for this CPU (ARMv8.0 features): fex-emu-armv8.0' '$DM'"
else echo "SKIP distro matrix checks: $DM not found"; fi

# launcher: lighter client window on the slow class (interface and friends view)
UB=$T/ui.sh; awk '/^# --- interface: Deck \(gamepadui\) by default/{f=1} f{print} f && /^esac$/{exit}' "$L" > "$UB"
uib(){ # SLOW CLIENT_LIGHT(-) STEAM_ARM_UI(-) args...
  local slow=$1 cl=$2 ui=$3; shift 3; rm -f "$T/ui.log"
  ( SLOW=$slow; [ "$cl" = - ] || CLIENT_LIGHT=$cl; unset STEAM_ARM_UI; [ "$ui" = - ] || STEAM_ARM_UI=$ui; LOG=$T/ui.log
    llog(){ echo "$*" >> "$LOG"; }; set -- "$@"; . "$UB"; echo "GPUI=[$GPUI] SWITCH=[$SWITCH] rest=[$*]" ) 2>&1; cat "$T/ui.log" 2>/dev/null; }
OUT=$(uib 1 - -); check "U1 slow class: desktop interface, logged with --bigpicture and client-light hints" "grep -qx 'GPUI=\[\] SWITCH=\[\] rest=\[\]' <<<\"\$OUT\" && grep -q '^client window: desktop interface (slow emulation class; steam-arm --bigpicture for Deck interface, steam-arm-config client-light off for the 3.0 behaviour)$' <<<\"\$OUT\""
OUT=$(uib 0 - -); check "U2 not slow: Deck interface as before, nothing logged" "grep -qx 'GPUI=\[-gamepadui\] SWITCH=\[\] rest=\[\]' <<<\"\$OUT\" && ! grep -q 'client window' <<<\"\$OUT\""
OUT=$(uib 1 off -); check "U3 slow, CLIENT_LIGHT=off: Deck interface" "grep -qx 'GPUI=\[-gamepadui\] SWITCH=\[\] rest=\[\]' <<<\"\$OUT\""
OUT=$(uib 1 - bigpicture); check "U4 slow, STEAM_ARM_UI=bigpicture: Deck interface" "grep -qx 'GPUI=\[-gamepadui\] SWITCH=\[\] rest=\[\]' <<<\"\$OUT\""
OUT=$(uib 1 - - --bigpicture -x); check "U5 slow, --bigpicture: Deck interface, switch, option consumed" "grep -qx 'GPUI=\[-gamepadui\] SWITCH=\[1\] rest=\[-x\]' <<<\"\$OUT\" && ! grep -q 'client window' <<<\"\$OUT\""
OUT=$(uib 1 - - --desktop); check "U6 slow, --desktop: desktop, switch" "grep -qx 'GPUI=\[\] SWITCH=\[1\] rest=\[\]' <<<\"\$OUT\""
OUT=$(uib 0 - desktop); check "U7 STEAM_ARM_UI=desktop on other boards as before" "grep -qx 'GPUI=\[\] SWITCH=\[\] rest=\[\]' <<<\"\$OUT\""
check "U8 constant SA_UI_SLOW=desktop in one place" "[ \$(grep -c '^SA_UI_SLOW=desktop$' $L) = 1 ]"
XF=$T/xf.sh; awk '/^  XFLAGS="-steamos3 -cef-disable-gpu -cef-disable-gpu-compositing"$/{f=1} f{print} f && /^  fi$/{exit}' "$L" > "$XF"
xf(){ rm -f "$T/xf.log"; ( LIGHT=$1; unset STEAM_ARM_FRIENDS; [ "$2" = - ] || STEAM_ARM_FRIENDS=$2; LOG=$T/xf.log; llog(){ echo "$*" >> "$LOG"; }; . "$XF"; echo "XFLAGS=[$XFLAGS]" ) 2>&1; cat "$T/xf.log" 2>/dev/null; }
OUT=$(xf 1 -); check "U9 lighter: -nofriendsui appended, logged" "grep -qx 'XFLAGS=\[-steamos3 -cef-disable-gpu -cef-disable-gpu-compositing -nofriendsui\]' <<<\"\$OUT\" && grep -q '^client window: friends view off (slow emulation class; STEAM_ARM_FRIENDS=1 keeps it)$' <<<\"\$OUT\""
OUT=$(xf 1 1); check "U10 STEAM_ARM_FRIENDS=1: friends view kept" "grep -qx 'XFLAGS=\[-steamos3 -cef-disable-gpu -cef-disable-gpu-compositing\]' <<<\"\$OUT\""
OUT=$(xf 0 -); check "U11 not lighter: flags as 3.0" "grep -qx 'XFLAGS=\[-steamos3 -cef-disable-gpu -cef-disable-gpu-compositing\]' <<<\"\$OUT\""
check "U12 setup summary names desktop window, --bigpicture, Maintenance items and --cpu-report for CPUs without LSE" \
  "grep -q 'cpu_lse || SUM_FIRST=\"downloads the client files and restarts itself; sign-in in desktop window.' '$INST' && grep -q 'steam-arm --bigpicture for Deck interface; settings menu: Maintenance >' '$INST' && grep -q 'steam-arm --cpu-report measures it' '$INST'"
# menu: Maintenance item 20 on x86 client without LSE, CLI client-light
sed -i 's/^CLIENT=.*/CLIENT=x86/' "$CONF"
cp "$T/pi4/cpuinfo" "$SARM_UI_FAKE/proc/cpuinfo"
ui menu_maintenance 20 BACK
check "L1 x86 client, Armv8.0 CPU: item 20 Client window: lighter (now: on); screen names desktop window, friends view, --bigpicture" \
  "grep -q ' 20 Client window: lighter (now: on)' <<<\"\$OUT\" && grep -q '^YESNO Client window: lighter|Client window: lighter: on' <<<\"\$OUT\" && grep -q 'friends view' <<<\"\$OUT\" && grep -q 'steam-arm --bigpicture' <<<\"\$OUT\""
ui menu_maintenance 20 yes BACK
check "L2 Turn off: CLIENT_LIGHT=off, message" "grep -qx 'CLIENT_LIGHT=off' '$CONF' && grep -q '^MSG Maintenance|Client window: lighter: off. Applies from next start of Steam ARM.' <<<\"\$OUT\""
cp "$T/pi5/cpuinfo" "$SARM_UI_FAKE/proc/cpuinfo"
ui menu_maintenance BACK
check "L3 x86 client on an LSE CPU: no item 20" "! grep -q ' 20 Client window' <<<\"\$OUT\""
cli client-light; check "L4 CLI state" "[ $RC = 0 ] && grep -q '^client window lighter: off$' <<<\"\$OUT\""
cli client-light on; check "L4b CLI on" "[ $RC = 0 ] && grep -qx 'CLIENT_LIGHT=on' '$CONF'"
cli --help; check "L5 --help lists client-light and CLIENT_LIGHT" "grep -q '^  client-light \[on|off\]' <<<\"\$OUT\" && grep -q 'CLIENT_LIGHT=on|off' <<<\"\$OUT\""
# menu: item 24 client window memory model (x86 client without LSE), CLI client-tso, key
cp "$T/pi4/cpuinfo" "$SARM_UI_FAKE/proc/cpuinfo"; AHT=$SARM_UI_FAKE/home/tester/.local/share/steam-arm; mkdir -p "$AHT/.config/steam-arm"
ui menu_maintenance 24 relaxed
check "TS1 Armv8.0 CPU: item 24 Client window: memory model (now: strict); screen names the three programs, FEX's warning, the guard; relaxed written" \
  "grep -q ' 24 Client window: memory model (now: strict)' <<<\"\$OUT\" && grep -q '^MENU Client window: memory model|' <<<\"\$OUT\" && grep -q 'steamwebhelper, steam and exe only' <<<\"\$OUT\" && grep -q 'multithreaded' <<<\"\$OUT\" && grep -q 'three client window restarts within 120 s' <<<\"\$OUT\" && grep -qx 'CLIENT_TSO=relaxed' '$CONF' && grep -q '^MSG Maintenance|Client window: memory model: relaxed. Applies from next start of Steam ARM.' <<<\"\$OUT\""
printf 'client-tso=failed:restart-loop\n' > "$AHT/.config/steam-arm/state"
ui menu_maintenance 24 retry
check "TS2 screen shows the last guard result; retry removes it" "grep -q 'last guard result: failed:restart-loop' <<<\"\$OUT\" && ! grep -q client-tso $AHT/.config/steam-arm/state"
ui menu_maintenance 24 strict; check "TS3 strict written" "grep -qx 'CLIENT_TSO=strict' '$CONF'"
cp "$T/pi5/cpuinfo" "$SARM_UI_FAKE/proc/cpuinfo"; ui menu_maintenance BACK
check "TS4 LSE CPU: no item 24" "! grep -q ' 24 Client window' <<<\"\$OUT\""
cli client-tso; check "TS5 CLI state and last guard result" "[ $RC = 0 ] && grep -q '^client window memory model: strict; last guard result: none$' <<<\"\$OUT\""
cli client-tso relaxed; check "TS5b CLI relaxed writes key" "[ $RC = 0 ] && grep -qx 'CLIENT_TSO=relaxed' '$CONF'"
printf 'client-tso=failed:no-startup\n' > "$AHT/.config/steam-arm/state"
cli client-tso retry; check "TS5c CLI retry removes the guard result" "[ $RC = 0 ] && ! grep -q client-tso $AHT/.config/steam-arm/state && grep -q 'earlier guard result removed' <<<\"\$OUT\""
cli client-tso maybe; check "TS5d bad value: usage" "[ $RC = 2 ]"
cli --help; check "TS6 --help lists client-tso and CLIENT_TSO" "grep -q '^  client-tso \[strict|relaxed|retry\]' <<<\"\$OUT\" && grep -q 'CLIENT_TSO=strict|relaxed' <<<\"\$OUT\""
check "TS7 CLIENT_TSO in backup key list with its own value rule (strict, relaxed, empty)" "grep -q '^SA_BK_KEYS=.* CEF_HANG_KILLS CLIENT_TSO\"' '$CFG' && grep -q '^  CLIENT_TSO) case \"\$2\" in strict|relaxed|\"\") return 0;; esac; return 1;;' '$CFG'"
# launcher: client window memory model environment and failed guard result
TB=$T/tso.sh; awk '/^# Client window memory model \(client helper writes TSOEnabled 0/{f=1} f{print} f && /^\[ "\$STEAM_ARM_CLIENT_TSO" = relaxed \] && llog/{exit}' "$L" > "$TB"
tso(){ # CLIENT_TSO(-) env(-) state(-)
  rm -rf "$T/ts"; mkdir -p "$T/ts/.config/steam-arm"; [ "$3" = - ] || echo "client-tso=$3" > "$T/ts/.config/steam-arm/state"
  ( ARMHOME=$T/ts LOG=$T/ts.log; unset STEAM_ARM_CLIENT_TSO CLIENT_TSO; [ "$1" = - ] || CLIENT_TSO=$1; [ "$2" = - ] || export STEAM_ARM_CLIENT_TSO=$2
    lwarn(){ echo "W $*"; }; llog(){ echo "L $*"; }; . "$TB"; echo "env=[$STEAM_ARM_CLIENT_TSO]" ) 2>&1; }
OUT=$(tso - - -); check "TE1 no setting: strict" "grep -qx 'env=\[strict\]' <<<\"\$OUT\" && ! grep -q '^L' <<<\"\$OUT\""
OUT=$(tso relaxed - -); check "TE2 CLIENT_TSO=relaxed: relaxed, logged as correctness trade" "grep -qx 'env=\[relaxed\]' <<<\"\$OUT\" && grep -q '^L client window memory model: relaxed (TSO emulation off for client window programs; correctness trade)' <<<\"\$OUT\""
OUT=$(tso relaxed strict -); check "TE3 environment strict wins over setting relaxed" "grep -qx 'env=\[strict\]' <<<\"\$OUT\""
OUT=$(tso strict relaxed -); check "TE4 environment relaxed wins over setting strict" "grep -qx 'env=\[relaxed\]' <<<\"\$OUT\""
OUT=$(tso relaxed - failed:restart-loop); check "TE5 earlier guard result: strict with warning naming reason and retry" "grep -qx 'env=\[strict\]' <<<\"\$OUT\" && grep -q '^W client window memory model: strict (relaxed failed earlier: restart-loop; steam-arm-config client-tso retry allows another trial)' <<<\"\$OUT\""
OUT=$(tso relaxed - ok); check "TE6 other state line: relaxed stays" "grep -qx 'env=\[relaxed\]' <<<\"\$OUT\""
# launcher: guard watcher on synthetic pids and client log
TW=$T/tw.sh; awk '/^  tso_watch\(\)\{/{f=1} f{print} f && /^  }$/{exit}' "$L" > "$TW"
check "TW0 guard extracted, started beside the lab watcher" "[ -s $TW ] && grep -q '^  tso_watch </dev/null >/dev/null 2>&1 &$' $L"
tw(){ # mode(relaxed|strict) startup-after-n-ticks(-|N) pid-sequence...
  local mode=$1 su=$2; shift 2; rm -rf "$T/tw"; mkdir -p "$T/tw/.config/steam-arm" "$T/tw/S/logs"; printf 'old Startup - webhelper launched\n' > "$T/tw/S/logs/webhelper.txt"
  printf '%s\n' "$@" > "$T/tw/q"; : > "$T/tw/n"
  ( STEAM_ARM_CLIENT_TSO=$mode ARMHOME=$T/tw S=$T/tw/S TSOST=$T/tw/.config/steam-arm/state
    sleep(){ echo . >> "$T/tw/n"; [ "$su" != - ] && [ "$(grep -c . "$T/tw/n")" = "$su" ] && echo 'Startup - webhelper launched pid 1' >> "$T/tw/S/logs/webhelper.txt"; :; }
    date(){ echo $((1000 + $(grep -c . "$T/tw/n") * 10)); }
    client_running(){ [ -s "$T/tw/q" ] || [ "$(grep -c . "$T/tw/n")" -le 40 ]; }
    pgrep(){ head -n 1 "$T/tw/q"; sed -i 1d "$T/tw/q"; }
    lnote(){ echo "NOTE $1 | $2" >> "$T/tw/calls"; }
    . "$TW"; tso_watch; echo "rc=$?" ) 2>&1; cat "$T/tw/calls" "$T/tw/.config/steam-arm/state" 2>/dev/null; }
OUT=$(tw relaxed 1 100 100 200 300 400 400 400)
check "TG1 three pid changes within 120 s (10 s ticks): failed:restart-loop, one notice naming retry" "grep -qx 'client-tso=failed:restart-loop' <<<\"\$OUT\" && [ \$(grep -c '^NOTE' <<<\"\$OUT\") = 1 ] && grep -q 'relaxed failed (restart-loop); next start runs strict; steam-arm-config client-tso retry' <<<\"\$OUT\""
OUT=$(tw relaxed 1 100 100 100 100 100 100 100 100 100 100 100 100 100 100 200 200 200 200 200 200 200 200 200 200 200 200 200 300 300 300 300 300 300 300 300 300 300 300 300 300 400 400)
check "TG2 changes spread over more than 120 s, start line present: nothing recorded" "! grep -q 'client-tso\|NOTE' <<<\"\$OUT\""
OUT=$(tw relaxed - 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100)
check "TG3 no new Startup line within 300 s (old line not counted): failed:no-startup" "grep -qx 'client-tso=failed:no-startup' <<<\"\$OUT\""
OUT=$(tw relaxed 2 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100)
check "TG4 Startup line within 300 s, stable pid: nothing" "! grep -q 'client-tso\|NOTE' <<<\"\$OUT\""
OUT=$(tw strict 1 100 200 300 400); check "TG5 strict: watcher returns at once" "grep -qx rc=0 <<<\"\$OUT\" && [ -s $T/tw/q ]"
printf 'cef-gpu=ok:vulkan\n' > "$T/tw/.config/steam-arm/state"
OUT=$( ( STEAM_ARM_CLIENT_TSO=relaxed ARMHOME=$T/tw S=$T/tw/S TSOST=$T/tw/.config/steam-arm/state; n=0; sleep(){ n=$((n + 1)); [ $n -le 5 ]; }; date(){ echo $((1000 + n * 10)); }; client_running(){ :; }
  pgrep(){ echo $((100 * (n + 1))); }; lnote(){ :; }; . "$TW"; tso_watch ) 2>&1; cat "$T/tw/.config/steam-arm/state" )
check "TG6 state file: other lines kept, guard line added" "[ \"\$OUT\" = \$'cef-gpu=ok:vulkan\nclient-tso=failed:restart-loop' ]"

# menu: Games > game > Emulation rows on a non-Pi settings file; CLI profile keys
sed -i 's/^GPU_FAMILY=.*/GPU_FAMILY=mali-csf-v10/' "$CONF"; grep -q '^GPU_FAMILY=' "$CONF" || echo GPU_FAMILY=mali-csf-v10 >> "$CONF"
TC=$SARM_UI_FAKE/etc/steam-arm/titles.conf
ui "game_menu 400" emu BACK
check "E1 game screen row Emulation [strict, x87 full]; submenu rows Memory model: strict, x87 precision: full" \
  "grep -q 'emu Emulation            \[strict, x87 full\]' <<<\"\$OUT\" && grep -q '^MENU Emulation: Portal|FEX settings for this game only. Both trade correctness for speed' <<<\"\$OUT\" && grep -q 'tso Memory model: strict x87 x87 precision: full' <<<\"\$OUT\""
ui "game_menu 400" emu tso off BACK BACK
check "E2 Memory model relaxed: tso=off written, screen names crash, hang, corrupt saves and LSE" \
  "grep -q '^400 .*tso=off' '$TC' && grep -q '^MENU Memory model: Portal|strict (default): x86 memory ordering kept (TSO emulation). relaxed: faster on CPUs without LSE atomics; games with several threads can crash, hang or corrupt saves.' <<<\"\$OUT\" && grep -q '^MSG Emulation|Portal: memory model relaxed. Applies from the next start of the game.' <<<\"\$OUT\""
ui "game_menu 400" emu x87 reduced BACK BACK
check "E3 x87 reduced: x87=reduced written, screen names geometry or physics errors" "grep -q '^400 .*x87=reduced' '$TC' && grep -q 'geometry or physics errors possible' <<<\"\$OUT\" && grep -q '^MSG Emulation|Portal: x87 precision reduced.' <<<\"\$OUT\""
ui "game_menu 400" emu BACK
check "E4 row shows relaxed, x87 reduced" "grep -q 'emu Emulation            \[relaxed, x87 reduced\]' <<<\"\$OUT\" && grep -q 'tso Memory model: relaxed x87 x87 precision: reduced' <<<\"\$OUT\""
ui "game_menu 400" emu tso default BACK BACK; ui "game_menu 400" emu x87 default BACK BACK
check "E5 defaults remove both keys" "! grep -q 'tso=\|x87=' '$TC'"
cli profile 400 tso=off x87=reduced; check "E6 CLI profile accepts tso=off x87=reduced" "[ $RC = 0 ] && grep -q '^400 .*tso=off' '$TC' && grep -q '^400 .*x87=reduced' '$TC'"
cli profile 400 tso=relaxed; check "E7 CLI refuses tso=relaxed" "[ $RC = 2 ] && grep -q 'bad setting: tso=relaxed' <<<\"\$OUT\""
cli profile 400 x87=fast; check "E7b CLI refuses x87=fast" "[ $RC = 2 ]"
cli profile 400 --clear; check "E8 --clear removes them" "[ $RC = 0 ] && ! grep -q '^400 ' '$TC'"
cli --help; check "E9 --help names tso=off, x87=reduced" "grep -q 'multiblock, diskcache, tso=off, x87=reduced,' <<<\"\$OUT\""

# driver archive recipe: --family broadcom preset (dry run; setup never selects it)
RECIPE=$(dirname "$INST")/tools/build-driver-archive.sh
if [ -f "$RECIPE" ]; then
  OUT=$(bash "$RECIPE" --family broadcom --dry-run 2>&1); RC=$?
  if grep -q "missing host tools\|user namespaces are off" <<<"$OUT"; then echo "SKIP A1 recipe dry run: $OUT"
  else
    check "A1 --family broadcom --dry-run: v3d,vc4,zink,llvmpipe,softpipe and broadcom,swrast, archive name with -broadcom, no panfrost note" \
      "[ $RC = 0 ] && grep -q '^  family     broadcom$' <<<\"\$OUT\" && grep -q '^  gallium    v3d,vc4,zink,llvmpipe,softpipe$' <<<\"\$OUT\" && grep -q '^  vulkan     broadcom,swrast$' <<<\"\$OUT\" && grep -q 'steam-arm-fex-mesa-26.1.8-broadcom-x86_64-i386.tar.zst' <<<\"\$OUT\" && ! grep -q 'no panfrost driver selected' <<<\"\$OUT\""
    OUT=$(bash "$RECIPE" --family broadcom --gallium v3d,zink --dry-run 2>&1)
    check "A2 --gallium given by hand wins over preset" "grep -q '^  gallium    v3d,zink$' <<<\"\$OUT\" && grep -q '^  vulkan     broadcom,swrast$' <<<\"\$OUT\""
    OUT=$(bash "$RECIPE" --dry-run 2>&1)
    check "A3 default family mali: lists unchanged, archive name unchanged" "grep -q '^  family     mali$' <<<\"\$OUT\" && grep -q '^  gallium    panfrost,llvmpipe,softpipe,zink$' <<<\"\$OUT\" && grep -q 'steam-arm-fex-mesa-26.1.8-x86_64-i386.tar.zst' <<<\"\$OUT\""
  fi
  OUT=$(bash "$RECIPE" --family nvidia --dry-run 2>&1); RC=$?
  check "A4 unknown family refused" "[ $RC = 1 ] && grep -q -- '--family: mali or broadcom' <<<\"\$OUT\""
  check "A5 verify step checks dri/v3d_dri.so, dri/vc4_dri.so and libvulkan_broadcom.so for the broadcom family, FAMILY passed into the build root" \
    "grep -q 'broadcom) for f in dri/v3d_dri.so dri/vc4_dri.so libvulkan_broadcom.so; do check' '$RECIPE' && grep -q \"FAMILY='\\\"\\\$FAMILY\\\"'\" '$RECIPE'"
else echo "SKIP recipe checks: $RECIPE not found"; fi

echo "pi4 detection 3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
