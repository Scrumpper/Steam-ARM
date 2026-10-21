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
OUT=$(grep -n 'conf_set CPU_LSE\|conf_set CPU_CORES\|conf_set PLATFORM\|conf_set MESA_HOST\|conf_set GPU_FAMILY_SET' "$INST")
check "D7 setup writes CPU_LSE, CPU_CORES, PLATFORM (platform_pick of GPU_FAMILY), MESA_HOST after GPU_FAMILY_SET" \
  "[ \$(grep -c . <<<\"\$OUT\") = 5 ] && grep -q 'conf_set CPU_LSE \"\$(cpu_lse && echo 1 || echo 0)\"' <<<\"\$OUT\" && grep -q 'conf_set PLATFORM \"\$(platform_pick \"\$GPU_FAMILY\")\"' <<<\"\$OUT\" && grep -q 'conf_set MESA_HOST \"\$(mesa_host)\"' <<<\"\$OUT\" && [ \$(head -1 <<<\"\$OUT\" | cut -d: -f1) -lt \$(tail -1 <<<\"\$OUT\" | cut -d: -f1) ]"
GR=$(fn gpu_report "$INST")
check "D8 --detect prints cpu lse, cpu cores, platform and mesa host lines" "grep -q 'echo \"cpu lse: ' <<<\"\$GR\" && grep -q 'echo \"cpu cores: ' <<<\"\$GR\" && grep -q 'echo \"platform: \${v:-none}\"' <<<\"\$GR\" && grep -q 'echo \"mesa host: \${v:-unknown}\"' <<<\"\$GR\""
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
  "grep -q 'export STEAM_ARM_SLOW=\"\$SLOW\" STEAM_ARM_PLATFORM=\"\$PLATFORM\"' $SB && [ \$(grep -n '^# Slow emulation class' $L | cut -d: -f1) -gt \$(grep -n '^# Client needs Armv8.1 atomics' $L | cut -d: -f1) ] && [ \$(grep -n '^# Slow emulation class' $L | cut -d: -f1) -lt \$(grep -n '^# Emulation needs 4K pages' $L | cut -d: -f1) ]"
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
check "M7 X87_CLIENT in backup key list and value rule" "grep -q '^SA_BK_KEYS=.* X87_CLIENT\"' '$CFG' && grep -q 'UPDATE_CHECK_ON_OPEN|X87_CLIENT) case \"\$2\" in on|off|\"\") return 0;; esac; return 1;;' '$CFG'"

echo "pi4 detection 3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
