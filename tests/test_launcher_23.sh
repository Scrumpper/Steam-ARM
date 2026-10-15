#!/bin/bash
# 2.3 launcher group. Automatic Windows build: block extracted from the installer copy in ~/.cache/sarm<NN>-work (paths.sh)
# (SARM_INST picks another), helper path pointed at a stand-in that logs its call and prints set/suggest lines;
# client_running, lnote stubbed. Also placement (after Bluetooth seed, before client start) and removal list.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-l23.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
B=$T/ab-block.sh
awk '/^# Automatic Windows build \(steam-arm-autobuild.py\)/{f=1} f && /^if \[ "\$CLIENT" = x86 \]; then cd "\$S" \|\| exit 1; else cd "\$D" \|\| exit 1; fi$/{exit} f' "$L" \
  | sed "s#/usr/local/lib/steam-arm-autobuild.py#$T/ab.py#" > "$B"
OUT=$(cat "$B")
check "AB1 launcher block present, helper call with apply and client folder" "grep -q 'python3 \"\$AB\" apply \"\$S\"' $B && grep -q '! client_running' $B"
check "AB1 launcher parses (sh -n)" "sh -n $L"
l_bt=$(grep -n '^# Client keeps host Bluetooth power' "$L" | cut -d: -f1); l_ab=$(grep -n '^# Automatic Windows build' "$L" | cut -d: -f1)
l_cd=$(grep -n '^if \[ "\$CLIENT" = x86 \]; then cd "\$S" || exit 1; else cd "\$D" || exit 1; fi$' "$L" | cut -d: -f1)
check "AB2 block after Bluetooth seed, before client start" "[ -n \"$l_ab\" ] && [ ${l_bt:-0} -lt ${l_ab:-0} ] && [ ${l_ab:-0} -lt ${l_cd:-0} ]"

# stand-in helper: argv to calls.log; output and exit from env
cat > "$T/ab.py" <<'EOF'
import os, sys
open(os.environ["T"] + "/calls.log", "a").write(" ".join(sys.argv[1:]) + "\n")
sys.stdout.write(os.environ.get("AB_OUT", "").replace("\\n", "\n"))
sys.stderr.write(os.environ.get("AB_ERR", ""))
sys.exit(int(os.environ.get("AB_RC", "0")))
EOF
abrun(){ rm -f "$T/calls.log" "$T/notes" "$T/l.log"
  ( export T; S=$T/Steam LOG=$T/l.log
    client_running(){ [ "${RUNNING:-0}" = 1 ]; }
    lnote(){ echo "$1" >> "$T/notes"; printf 'NOTE %s\n' "$1" >> "$LOG"; }
    . "$B"; echo REACHED ) 2>&1; }
SET1='auto-build: app 220: Windows build (Proton ARM64) set; 32-bit Source engine Linux build stops at loading screen under emulation. Undo: steam-arm-config, Graphics > Route per game'
SET2=${SET1//220/240}
SUG='auto-build: app 300: Windows build suggested (FEX tool 2609 newer than tested)'
OUT=$(AB_OUT="$SET1\n$SET2\n$SUG\n" abrun)
check "AB3 two set lines + one suggestion: all three in log with date, helper called as apply <client>" \
  "[ \$(grep -c 'auto-build: app' $T/l.log) = 3 ] && grep -Eq '^[0-9-]{10} [0-9:]{8} auto-build: app 300: Windows build suggested' $T/l.log && [ \"\$(cat $T/calls.log)\" = \"apply $T/Steam\" ]"
check "AB3 one desktop notice naming count 2 and menu path" "[ \$(grep -c . $T/notes) = 1 ] && grep -q '^Windows build (Proton ARM64) set for 2 game(s) whose Linux build fails under emulation. Steam downloads it in background once client is up. Change: Steam ARM Settings > Graphics > Route per game.\$' $T/notes"
check "AB3b notice title names Windows build, not warning (box bug 22)" "grep -q 'lnote \"Windows build (Proton ARM64) set for .*\" \"Steam ARM: Windows build set\"\$' $B && grep -q 'notice 0 \"\${2:-Steam ARM: warning}\"' $L"
check "AB3 start continues" "printf '%s\n' \"\$OUT\" | grep -q REACHED"
OUT=$(AB_OUT="$SUG\n" abrun)
check "AB4 suggestion only: logged, no notice" "grep -q 'suggested' $T/l.log && [ ! -f $T/notes ]"
OUT=$(AB_RC=1 AB_ERR='Traceback: boom' abrun)
check "AB5 helper exit 1: start continues, error text to log, no notice" "printf '%s\n' \"\$OUT\" | grep -q REACHED && grep -q 'Traceback: boom' $T/l.log && [ ! -f $T/notes ]"
OUT=$(RUNNING=1 AB_OUT="$SET1\n" abrun)
check "AB6 client running: helper not called (client rewrites config.vdf on exit)" "[ ! -f $T/calls.log ] && [ ! -f $T/notes ] && printf '%s\n' \"\$OUT\" | grep -q REACHED"
mv "$T/ab.py" "$T/ab.off"
OUT=$(AB_OUT="$SET1\n" abrun)
check "AB7 helper file missing: nothing logged, start continues" "[ ! -s $T/l.log ] && printf '%s\n' \"\$OUT\" | grep -q REACHED"
mv "$T/ab.off" "$T/ab.py"
check "AB8 helper call bounded by timeout" "grep -q 'timeout 30 python3 \"\$AB\" apply' $B"

# removal list names both helpers
RM=$(awk '/^  rm -f \/usr\/local\/bin\/steam-arm \/usr\/local\/bin\/steam-arm-remoteplay/{f=1} f{print} f && !/\\$/{exit}' "$INST")
OUT=$RM
check "AB9 --remove deletes steam-arm-autobuild.py and steam-arm-appinfo.py" "grep -q '/usr/local/lib/steam-arm-autobuild.py' <<<\"\$RM\" && grep -q '/usr/local/lib/steam-arm-appinfo.py' <<<\"\$RM\""
check "AB10 setup summary names automatic build, no manual compatmap hint" "grep -q 'Graphics > Automatic Windows build)' $INST && ! grep -q 'needs: steam-arm-compatmap <appid> proton-stable-arm64' $INST"

# ---------- x86 client (CLIENT=x86 in settings file) ----------
blk(){ A=$1 B=$2 awk '!f && $0 ~ ENVIRON["A"] {f=1; print; next} f {print} f && $0 ~ ENVIRON["B"] {exit}' "$L"; }
mkdir -p "$T/xb"
NORM=$T/norm.sh; grep -A1 '^# Client type from setup (CLIENT in the settings file)' "$L" | tail -1 > "$NORM"
for v in x86 arm64 "" X86 "x86 "; do printf '%s=%s\n' "$v" "$(CLIENT=$v; . "$NORM"; echo "$CLIENT")"; done > "$T/norm.out"
OUT=$(cat "$T/norm.out")
check "XL1 CLIENT x86 -> x86; anything else (empty, X86, trailing space) -> arm64" "[ \"\$OUT\" = \$'x86=x86\narm64=arm64\n=arm64\nX86=arm64\nx86 =arm64' ]"
IC=$T/ic.sh; blk '^# Installed client check' '^fi$' > "$IC"
ic(){ ( S=$T/S$1 D=$T/S$1/steamrtarm64 CLIENT=$2 SETUP=setup; stop(){ echo "STOP $1"; exit 1; }; . "$IC"; echo GO ) 2>&1; }
mkdir -p "$T/Sx/ubuntu12_32" "$T/Sa/steamrtarm64"; : > "$T/Sx/steam.sh"; : > "$T/Sx/ubuntu12_32/steam-runtime.tar.xz.checksum"; printf '#!/bin/sh\n' > "$T/Sx/ubuntu12_32/steam"; chmod 755 "$T/Sx/ubuntu12_32/steam"
printf '#!/bin/sh\n' > "$T/Sa/steamrtarm64/steam"; chmod 755 "$T/Sa/steamrtarm64/steam"
OUT=$(ic x x86); check "XL2 x86 client installed (steam.sh + ubuntu12_32/steam) -> starts" "[ \"\$OUT\" = GO ]"
OUT=$(ic a x86); check "XL3 x86 conf without x86 client -> stop naming x86 client and Update / Repair" "grep -q '^STOP x86 Steam client not installed in .*Maintenance > Update / Repair' <<<\"\$OUT\""
OUT=$(ic a arm64); check "XL4 native conf: 2.2 check unchanged (steamrtarm64/steam)" "[ \"\$OUT\" = GO ]"
OUT=$(ic x arm64); check "XL5 native conf without native client -> 2.2 stop text" "grep -q '^STOP Steam client not installed in ' <<<\"\$OUT\""
EV=$T/ev.sh; blk '^# x86 client: runtime containers through host bubblewrap' '^fi$' > "$EV"
OUT=$( (export STEAM_COMPAT_GRAPHICS_PROVIDER=/opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json; unset PRESSURE_VESSEL_BWRAP; CLIENT=x86; . "$EV"; echo "gp=${STEAM_COMPAT_GRAPHICS_PROVIDER:-unset} pv=${PRESSURE_VESSEL_BWRAP:-unset}") 2>&1)
check "XL6 x86: PRESSURE_VESSEL_BWRAP = pv-bwrap, native graphics provider unset" "[ \"\$OUT\" = 'gp=unset pv=/usr/local/lib/steam-arm-pv-bwrap' ]"
OUT=$( (export STEAM_COMPAT_GRAPHICS_PROVIDER=g; unset PRESSURE_VESSEL_BWRAP; CLIENT=arm64; . "$EV"; echo "gp=${STEAM_COMPAT_GRAPHICS_PROVIDER:-unset} pv=${PRESSURE_VESSEL_BWRAP:-unset}") 2>&1)
check "XL7 native: environment as 2.2" "[ \"\$OUT\" = 'gp=g pv=unset' ]"
# stop path: client_x86 under FEX with package-tool stubs first in PATH; native path unchanged
SP=$T/sp.sh; awk '/^client_running\(\)/{f=1} f&&/^case "\$\{1:-\}" in/{exit} f' "$L" > "$SP"
printf '#!/bin/sh\necho "FEX $* PATH1=${PATH%%%%:*}" >> "$T/fex.log"\nrm -f "$T/running"\n' > "$T/xb/FEX"
printf '#!/bin/sh\n[ -f "$T/running" ]\n' > "$T/xb/pgrep"; printf '#!/bin/sh\necho "pkill $*" >> "$T/fex.log"\n' > "$T/xb/pkill"
chmod 755 "$T/xb/FEX" "$T/xb/pgrep" "$T/xb/pkill"
sp(){ rm -f "$T/fex.log"; : > "$T/running"; ( export T; S=$T/Sx D=$T/Sa/steamrtarm64 NOPKG=/usr/local/lib/steam-arm-nopkg CLIENT=$1 PATH=$T/xb:$PATH
      lwarn(){ :; }; . "$SP"; stop_client; echo "rc=$?" ) 2>&1; }
OUT=$(sp x86)
check "XL8 x86 stop: steam.sh -shutdown through FEX x86 bash, package stubs first in PATH, no SIGTERM needed" \
  "grep -q '^rc=0' <<<\"\$OUT\" && grep -qx \"FEX /usr/bin/bash $T/Sx/steam.sh -shutdown PATH1=/usr/local/lib/steam-arm-nopkg\" $T/fex.log && ! grep -q pkill $T/fex.log"
check "XL9 x86 client start command uses the same function, never SIGKILL" "grep -qF '  && PATH=\"\$NOPKG:\$PATH\" exec FEX /usr/bin/bash \"\$S/steam.sh\" \"\$@\" ); }' $L && grep -q '^client_x86(){ ( cd \"\$S\" && ' $L && [ \$(grep -c 'client_x86 ' $L) -ge 3 ] && ! grep -qE 'kill -9|kill -KILL|pkill -9' $L"
# x86 -shutdown through emulation takes over 20 s: client gone after 30 sleeps (box re-test B9)
sw(){ rm -f "$T/fex.log" "$T/sw.log" "$T/sl"; : > "$T/running"; printf '#!/bin/sh\necho "FEX $*" >> "$T/fex.log"\n' > "$T/xb/FEX"
      ( export T; S=$T/Sx D=$T/Sa/steamrtarm64 NOPKG=/n CLIENT=$1 PATH=$T/xb:$PATH
        lwarn(){ echo "LWARN $*" >> "$T/sw.log"; }; sleep(){ echo . >> "$T/sl"; [ "$(grep -c . "$T/sl")" -ge 30 ] && rm -f "$T/running"; }
        . "$SP"; stop_client; echo "rc=$?" ) 2>&1; }
OUT=$(sw x86)
check "XL38 x86 stop: client closing after 30 s of -shutdown not sent SIGTERM, no warning (box re-test B9)" "grep -q '^rc=0' <<<\"\$OUT\" && ! grep -q pkill $T/fex.log && [ ! -s $T/sw.log ]"
OUT=$(mkdir -p "$T/Sa/steamrtarm64"; printf '#!/bin/sh\n' > "$T/Sa/steamrtarm64/steam"; chmod 755 "$T/Sa/steamrtarm64/steam"; sw arm64; cat "$T/sw.log")
check "XL39 native stop: 20 s limit kept, SIGTERM after it" "grep -q 'pkill -TERM' $T/fex.log && grep -q 'did not act on -shutdown within 20 s' <<<\"\$OUT\""
# --shutdown from another account's folder (menu close_steam, STEAM_ARM_HOME): settings file CLIENT not used,
# no installed-client stop. Launcher front part up to the --shutdown case, settings file pointed at a fake.
SDF=$T/sd-front.sh
{ awk '/^REALHOME=/{f=1} f{print} f && /^  --shutdown\) stop_client; exit \$\?;;$/{exit}' "$L"; echo esac; echo 'echo "NOT REACHED"'; } \
  | sed "s#/etc/steam-arm/steam-arm.conf#$T/sd.conf#g" > "$SDF"
mkdir -p "$T/sdb"
printf '#!/bin/sh\n[ -f "$T/running" ]\n' > "$T/sdb/pgrep"; printf '#!/bin/sh\necho "pkill $*" >> "$T/sd.log"\n' > "$T/sdb/pkill"
printf '#!/bin/sh\necho "FEX $*" >> "$T/sd.log"\nrm -f "$T/running"\n' > "$T/sdb/FEX"; chmod 755 "$T/sdb/"*
# sd CONF_CLIENT FOLDER: folder h-arm64 (native files), h-x86 (x86 files); RECORD optional client-type record
sd(){ rm -f "$T/sd.log"; : > "$T/running"; [ "${NORUN:-0}" = 1 ] && rm -f "$T/running"; h=$T/sd-$2; rm -rf "$h"
  S=$h/.local/share/Steam
  case $2 in
    arm64*) mkdir -p "$S/steamrtarm64"; printf '#!/bin/sh\necho "NATIVE $*" >> "$T/sd.log"\nrm -f "$T/running"\n' > "$S/steamrtarm64/steam"; chmod 755 "$S/steamrtarm64/steam";;
    x86*) mkdir -p "$S/ubuntu12_32"; : > "$S/steam.sh"; printf '#!/bin/sh\n' > "$S/ubuntu12_32/steam"; chmod 755 "$S/ubuntu12_32/steam";;
  esac
  [ -n "${3:-}" ] && { mkdir -p "$h/.config/steam-arm"; echo "$3" > "$h/.config/steam-arm/client-type"; }
  printf 'GAMEUSER=%s\nCLIENT=%s\nCLIENT_SET=auto\n' "$(id -un)" "$1" > "$T/sd.conf"
  ( export T; env -u DISPLAY -u WAYLAND_DISPLAY STEAM_ARM_HOME="$h" PATH="$T/sdb:$PATH" sh "$SDF" --shutdown; echo "rc=$?" ) 2>&1; }
OUT=$(sd x86 arm64 arm64)
check "XL40 --shutdown, settings file x86, folder record arm64 (native client): native -shutdown, no stop" "grep -qx 'NATIVE -shutdown' $T/sd.log && grep -qx 'rc=0' <<<\"\$OUT\" && ! grep -q 'not installed' <<<\"\$OUT\""
OUT=$(sd arm64 x86)
check "XL41 --shutdown, settings file arm64, no record, x86 client files: x86 stop through FEX, no stop" "grep -q '^FEX /usr/bin/bash .*/steam.sh -shutdown' $T/sd.log && grep -qx 'rc=0' <<<\"\$OUT\" && ! grep -q 'not installed' <<<\"\$OUT\""
OUT=$(sd x86 x86 x86)
check "XL42 --shutdown, record and settings file agree (x86): x86 stop" "grep -q '^FEX /usr/bin/bash .*/steam.sh -shutdown' $T/sd.log && grep -qx 'rc=0' <<<\"\$OUT\""
OUT=$(NORUN=1 sd arm64 none)
check "XL43 --shutdown, folder without client files, no client running: status 0, nothing sent, no stop text" "grep -qx 'rc=0' <<<\"\$OUT\" && [ ! -f $T/sd.log ] && ! grep -q 'NOT REACHED\|not installed' <<<\"\$OUT\""
l_sd=$(grep -n '^  --shutdown) stop_client; exit \$?;;$' "$L" | cut -d: -f1); l_ic=$(grep -n '^# Installed client check' "$L" | cut -d: -f1)
check "XL44 installed-client check after --shutdown, before LSE check" "[ -n \"$l_ic\" ] && [ ${l_sd:-0} -lt ${l_ic:-0} ] && [ ${l_ic:-0} -lt \$(grep -n '^# Client needs Armv8.1 atomics' $L | cut -d: -f1) ]"
# CPU check: native client only, not a hand choice
CK=$T/ck.sh; blk '^# Client needs Armv8.1 atomics \(LSE\); STEAM_ARM_ALLOW_ARMV80=1 skips the check\.$' '^fi$' > "$CK"
printf 'processor\t: 0\nFeatures\t: fp asimd evtstrm crc32 cpuid\n' > "$T/cpu80"
ck(){ sed "s#/proc/cpuinfo#$T/cpu80#" "$CK" > "$T/ck-run.sh"; ( CLIENT=$1 CLIENT_SET=$2 CLIENT_PROBE=${3:-}; lwarn(){ :; }; stop(){ echo "STOP $1"; exit 1; }; unset STEAM_ARM_ALLOW_ARMV80; . "$T/ck-run.sh"; echo GO ) 2>&1; }
OUT=$(ck x86 auto); check "XL10 Armv8.0 + x86 client -> starts (no LSE stop)" "[ \"\$OUT\" = GO ]"
OUT=$(ck arm64 auto); check "XL11 Armv8.0 + native client from 2.2 setup -> stop says setup installs x86 client" "grep -q '^STOP This CPU has no Armv8.1 atomics (LSE). Native ARM64 client needs Armv8.1.*Run setup again (sudo steam-arm-config, Maintenance > Update / Repair): it installs x86 client' <<<\"\$OUT\""
OUT=$(ck arm64 auto 1788652215:ok); check "XL11b Armv8.0 + native client after setup's switch back (CLIENT_SET=auto, CLIENT_PROBE <v>:ok) -> starts" "[ \"\$OUT\" = GO ]"
OUT=$(ck arm64 auto 1788652215:lse); check "XL11c Armv8.0 + native client, last check lse -> stop" "grep -q '^STOP This CPU has no Armv8.1 atomics' <<<\"\$OUT\""
OUT=$(ck arm64 auto 1788652215:err); check "XL11d Armv8.0 + native client, last check err -> stop" "grep -q '^STOP This CPU has no Armv8.1 atomics' <<<\"\$OUT\""
OUT=$(ck arm64 user); check "XL12 Armv8.0 + native client chosen by hand (CLIENT_SET=user) -> starts" "[ \"\$OUT\" = GO ]"
# other x86 client warning: own client folder not counted
OX=$T/ox.sh; blk '^# Another x86 Steam client \(not from this client folder\) running\.$' '^fi$' > "$OX"
printf '#!/bin/sh\n[ -n "$PG_OUT" ] && printf "%%s\\n" "$PG_OUT"\n' > "$T/xb/pgrep"; printf '#!/bin/sh\necho ZENITY >> "$T/zen.log"\n' > "$T/xb/zenity"; chmod 755 "$T/xb/pgrep" "$T/xb/zenity"
ox(){ rm -f "$T/zen.log"; ( export T PG_OUT="$1"; S=$T/Sx PATH=$T/xb:$PATH; . "$OX" ); [ -f "$T/zen.log" ] && echo WARNED || echo QUIET; }
OUT=$(ox "123 /usr/bin/FEXInterpreter $T/Sx/ubuntu12_32/steam -steamos3"); check "XL13 own x86 client (inside client folder) -> no other-client warning" "[ \"\$OUT\" = QUIET ]"
OUT=$(ox "77 /home/u/.steam/debian-installation/ubuntu12_32/steam -silent"); check "XL14 x86 client from another Steam install -> warning" "[ \"\$OUT\" = WARNED ]"
OUT=$(ox ""); check "XL15 no x86 client -> no warning" "[ \"\$OUT\" = QUIET ]"
# stand-ins: native writes its two, x86 runs the helper's prepare and logs its lines
SI=$T/si.sh; { blk '^if \[ "\$CLIENT" = arm64 \]; then$' '^\[ "\$xrc" = 0 \] \|\| lnote'; echo fi; } > "$SI"
check "XL16 stand-in section extracted (native stand-ins, x86 prepare)" "grep -q 'streaming_client.new' $SI && grep -q 'steam-arm-x86client.py prepare' $SI && sh -n $SI"
printf '#!/bin/sh\necho "$*" >> "$T/py.log"\n[ "$2" = prepare ] && { printf "x86 client: line one\\nwarning: steamwebhelper.sh changed by Valve; transport dialog may appear at start\\n"; exit "${PREP_RC:-0}"; }\nexit 0\n' > "$T/xb/python3"; chmod 755 "$T/xb/python3"
si(){ rm -rf "$T/py.log" "$T/lnote" "$T/sl.log" "$T/D"; mkdir -p "$T/D"; ( export T PREP_RC="${2:-0}"; S=$T/Sx D=$T/D ARMHOME=$T/AH LOG=$T/sl.log CLIENT=$1 PATH=$T/xb:$PATH
     lnote(){ echo "$1" > "$T/lnote"; }; . "$SI" ) >/dev/null 2>&1; }
si x86 1
check "XL17 x86: prepare S ARMHOME called, no native stand-ins written" "[ \"\$(cat $T/py.log)\" = '/usr/local/lib/steam-arm-x86client.py prepare $T/Sx $T/AH' ] && [ -z \"\$(ls $T/D)\" ]"
check "XL18 x86: helper lines in launcher log with date; failure -> note of last line without 'warning:'" "[ \$(grep -Ec '^[0-9-]{10} [0-9:]{8} (x86 client: line one|warning: steamwebhelper)' $T/sl.log) = 2 ] && [ \"\$(cat $T/lnote)\" = 'steamwebhelper.sh changed by Valve; transport dialog may appear at start' ]"
si x86 0
check "XL19 x86: helper status 0 -> no note" "[ ! -f $T/lnote ]"
si arm64
check "XL20 native: launch wrapper and streaming stand-ins written as 2.2, helper not called" "[ -x $T/D/steam-launch-wrapper ] && [ -x $T/D/streaming_client ] && [ ! -f $T/py.log ]"
# x86 start passes: first start without -noverifyfiles, then normal start; no -deckard; client window on CPU
XS=$T/xs.sh; { blk '^boot_phase\(\)' '^}$'; blk '^# x86 client: own start passes' '^fi$'; } > "$XS"
check "XL21 x86 start block extracted, parses" "grep -q '^if \[ \"\$CLIENT\" = x86 \]; then\$' $XS && sh -n $XS"
printf '#!/bin/sh\necho "FEXServer $*" >> "$T/xs.log"\n' > "$T/xb/FEXServer"; chmod 755 "$T/xb/FEXServer"
# client_x86 stand-in: mk = bootstrap downloads, logs update complete and keeps client running until stop_client;
# quit = files in, user closed client
XOK=$T/AH/.config/steam-arm/x86-verified
# account signed in and runtime unpacked unless NOACCT=1 / NORT=1
xs(){ rm -f "$T/xs.log" "$T/shut" "$T/running" "$T/boot.log" "$T/py.log"; rm -rf "$T/R" "$T/AH"; mkdir -p "$T/R/ubuntu12_64" "$T/R/config" "$T/R/ubuntu12_32/steam-runtime"
  [ "${NOACCT:-}" = 1 ] || printf '"users"\n{\n\t"76561190000000000"\n\t{\n\t\t"AccountName"\t\t"acct"\n\t}\n}\n' > "$T/R/config/loginusers.vdf"
  [ "${NORT:-}" = 1 ] || { printf '#!/bin/sh\n' > "$T/R/ubuntu12_32/steam-runtime/setup.sh"; chmod 755 "$T/R/ubuntu12_32/steam-runtime/setup.sh"; }
  case "$1" in ready|native) : > "$T/R/ubuntu12_64/steamwebhelper";; esac
  [ "$1" = ready ] && { mkdir -p "${XOK%/*}"; : > "$XOK"; }
  ( export T MK="${2:-}"; S=$T/R ARMHOME=$T/AH CLIENT=x86 GPUI=${XGPUI--gamepadui} NOSHADERS=-noshaders BOOTLOG=$T/boot.log PATH=$T/xb:$PATH
    client_x86(){ echo "client_x86 $*" >> "$T/xs.log"
      case "$MK" in
        mk) : > "$T/running"; : > "$T/R/ubuntu12_64/steamwebhelper"; echo '[2026-10-07 10:00:00] Update complete, launching Steam...' >> "$T/boot.log"
            n=0; while [ ! -f "$T/shut" ] && [ $n -lt 25 ]; do sleep 0.2; n=$((n + 1)); done; rm -f "$T/running";;
        quit) : > "$T/R/ubuntu12_64/steamwebhelper";;
        quitv) : > "$T/R/ubuntu12_64/steamwebhelper"; echo '[2026-10-07 10:00:00] Verification complete' >> "$T/boot.log";;
        crash) return 139;;
      esac; return 0; }
    client_running(){ [ -f "$T/running" ]; }; stop_client(){ echo STOP_CLIENT >> "$T/xs.log"; : > "$T/shut"; }
    updated_exit(){ return 1; }; first_start_notice(){ echo NOTICE >> "$T/xs.log"; }
    lwarn(){ :; }; lnote(){ echo "LNOTE $1" >> "$T/xs.log"; }; stop(){ echo "STOP $1" >> "$T/xs.log"; exit 1; }; set --; . "$XS" ) >/dev/null 2>&1; sleep 0.2; }
xs fresh mk
OUT=$(cat "$T/xs.log")
check "XL22 first start: bootstrap pass without -noverifyfiles, CEF GPU off, no -deckard, Big Picture" "grep -qx 'client_x86 -steamos3 -cef-disable-gpu -cef-disable-gpu-compositing -gamepadui' <<<\"\$OUT\" && ! grep -q deckard <<<\"\$OUT\""
check "XL23 bootstrap client still running after download: stopped through stop_client (graceful), then normal start with -noverifyfiles -norepairfiles -noshaders" "[ \"\$(grep -E '^(client_x86|STOP_CLIENT)' <<<\"\$OUT\" | sed 's/ -steamos3.*-gamepadui//' | paste -sd,)\" = 'client_x86,STOP_CLIENT,client_x86 -noverifyfiles -norepairfiles -noshaders' ]"
check "XL23b first start: helper prepare runs again after stop (webhelper flag before normal start)" "grep -qx '/usr/local/lib/steam-arm-x86client.py prepare $T/R $T/AH' $T/py.log"
xs fresh quit
OUT=$(cat "$T/xs.log")
check "XL23c user closes client during first start with files in: no new start, no stop" "[ \$(grep -c '^client_x86' <<<\"\$OUT\") = 1 ] && ! grep -q 'STOP' <<<\"\$OUT\""
check "XL24 one FEX server for the session, 60 s linger" "grep -qx 'FEXServer -p 60' <<<\"\$OUT\""
xs ready
OUT=$(cat "$T/xs.log")
check "XL25 later start (webhelper present, files checked before): one normal start only, no first-start notice" "[ \$(grep -c '^client_x86' <<<\"\$OUT\") = 1 ] && grep -q -- '-noverifyfiles' <<<\"\$OUT\" && ! grep -q NOTICE <<<\"\$OUT\""
xs fresh
OUT=$(cat "$T/xs.log")
check "XL26 first start without result -> stop names x86 client and missing webhelper" "grep -q '^STOP x86 Steam client did not finish its first start: client files incomplete (.*ubuntu12_64/steamwebhelper missing)' <<<\"\$OUT\""
xs native
OUT=$(cat "$T/xs.log")
check "XL31 webhelper from native package but x86 files never checked: first start without -noverifyfiles (box bug 9)" "grep -qx 'client_x86 -steamos3 -cef-disable-gpu -cef-disable-gpu-compositing -gamepadui' <<<\"\$OUT\" && grep -q NOTICE <<<\"\$OUT\""
xs fresh mk
check "XL32 first start done (update applied, client stopped): x86 check marker written" "[ -f $XOK ]"
xs native quit
check "XL33 user closes client before its log reports a file check: no marker, next start checks again" "[ ! -f $XOK ]"
xs native quitv
check "XL33b user closes client after 'Verification complete': marker written, no new start" "[ -f $XOK ] && [ \$(grep -c '^client_x86' $T/xs.log) = 1 ]"
xs fresh crash
OUT=$(cat "$T/xs.log")
check "XL34 client ends by signal during first start: note with status and log paths (box bug 9)" "grep -q '^LNOTE x86 Steam client stopped during first start (status 139). Start Steam ARM again; details: .*logs/stderr.txt' <<<\"\$OUT\""
# box re-check B15: Deck interface on fresh account runs SteamOS setup (steamos-update missing)
NOACCT=1 xs fresh mk
OUT=$(cat "$T/xs.log")
check "XL40 no account signed in: first and normal start in desktop window (no -gamepadui), note says why once" "[ \$(grep -c '^client_x86' <<<\"\$OUT\") = 2 ] && ! grep -q -- -gamepadui <<<\"\$OUT\" && [ \$(grep -c '^LNOTE No account signed in yet: x86 client opens desktop sign-in window. Deck interface from next start after sign-in.\$' <<<\"\$OUT\") = 1 ]"
xs ready
OUT=$(cat "$T/xs.log")
check "XL41 account signed in: Deck interface (-gamepadui), no note" "grep -q '^client_x86 .*-gamepadui' <<<\"\$OUT\" && ! grep -q 'No account signed in' <<<\"\$OUT\""
NOACCT=1 XGPUI= xs ready
OUT=$(cat "$T/xs.log")
check "XL42 desktop interface chosen, no account: no note" "grep -q '^client_x86' <<<\"\$OUT\" && ! grep -q LNOTE <<<\"\$OUT\""
# box re-check B14: first start failed, runtime never unpacked
NORT=1 xs fresh
OUT=$(cat "$T/xs.log")
check "XL44 first start without result and no unpacked runtime: stop names runtime and setup, not download" "grep -q '^STOP x86 Steam client did not finish its first start: runtime not unpacked (.*ubuntu12_32/steam-runtime). Run setup again' <<<\"\$OUT\" && ! grep -q 'finish download' <<<\"\$OUT\""
check "XL35 normal start: signal end of x86 client logged" "grep -q 'lwarn \"x86 client ended by signal \$((rc - 128)) (status \$rc)' $L"
# client_x86: private libX11 copy first in library path when present
mkdir -p "$T/xl/.fex-emu/hostlib"; printf '#!/bin/sh\necho "LDP=$LD_LIBRARY_PATH" >> "$T/fex.log"\n' > "$T/xb/FEX"; chmod 755 "$T/xb/FEX"
cx(){ rm -f "$T/fex.log"; ( export T LD_LIBRARY_PATH=/keep; S=$T/Sx ARMHOME=$T/xl NOPKG=/n PATH=$T/xb:$PATH; lwarn(){ :; }
      eval "$(grep '^XLIB=' "$L")"; eval "$(awk '/^client_x86\(\)/{f=1} f{print} f && /\); }$/{exit}' "$L")"; client_x86 -x ); cat "$T/fex.log"; }
OUT=$(cx)
check "XL36 no private libX11 copy: library path unchanged" "[ \"\$OUT\" = 'LDP=/keep' ]"
: > "$T/xl/.fex-emu/hostlib/libX11.so.6"
OUT=$(cx)
check "XL37 private libX11 copy: its folder first in library path (box bug 9)" "[ \"\$OUT\" = 'LDP=$T/xl/.fex-emu/hostlib:/keep' ]"
check "XL27 x86 first-start notice text (no size figure)" "grep -q 'FIRST_MSG=\"Downloading x86 client files, this takes several minutes. Steam opens when done.\"' $L && ! grep -q 'x86 client files (about' $L"
check "XL28 Valve's FEX tool check, arm64 overlay layer and client LD_LIBRARY_PATH: native client only" \
  "grep -q '^  \[ \"\$CLIENT\" = arm64 \] && \[ -d \"\$F\" \] || return 0\$' $L && grep -q '^if \[ \"\$CLIENT\" = arm64 \] && \[ -f \"\$D/steamoverlayvulkanlayer.so\" \]; then\$' $L && grep -q '^\[ \"\$CLIENT\" = x86 \] || export LD_LIBRARY_PATH=\"\$D' $L"
check "XL29 launcher log names client type at every start" "grep -q \"printf '%s client: %s\\\\\\\\n' .*'x86 through emulation' || echo 'native ARM64'\" $L"
check "XL30 native start lines unchanged (-deckard, ./steam in steamrtarm64)" "grep -q '^    ./steam -deckard -steamos3 \${GPUI:+\"\$GPUI\"} \"\$@\"\$' $L && grep -q '^  ./steam -deckard -steamos3 \${GPUI:+\"\$GPUI\"} -noverifyfiles -norepairfiles' $L"

# ---------- native: one start with file check after switch back from x86 client ----------
NS=$T/ns.sh; { blk '^updated_exit\(\)' '^}$'; awk '/^# Switch back from x86 client \(marker from setup\)/{f=1} /^if \[ ! -f "\$S\/linuxarm64\/steamclient.so" \]; then$/{f=1} f{print} f && /^tries=0$/{exit}' "$L"; } > "$NS"
check "NV0 native start block extracted, parses" "grep -q 'linuxarm64/steamclient.so' $NS && bash -n $NS"
ns(){ rm -rf "$T/N" "$T/NA" "$T/ns.log"; mkdir -p "$T/N/linuxarm64" "$T/N/steamrtarm64" "$T/NA/.config/steam-arm"; : > "$T/N/linuxarm64/steamclient.so"
  [ "$1" = verify ] && : > "$T/NA/.config/steam-arm/native-verify"
  ( export T NRC="${2:-0}"; S=$T/N ARMHOME=$T/NA BOOTLOG=$T/nboot.log GPUI=-gamepadui; : > "$BOOTLOG"; cd "$T/N/steamrtarm64"
    printf '#!/bin/sh\necho "steam $*" >> "$T/ns.log"\nexit $NRC\n' > ./steam; chmod 755 ./steam
    client_running(){ return 1; }; first_start_notice(){ echo NOTICE >> "$T/ns.log"; }; lwarn(){ :; }; stop(){ echo "STOP $1" >> "$T/ns.log"; exit 1; }
    set --; . "$NS"; echo "REACHED normal start" >> "$T/ns.log" ) >/dev/null 2>&1; }
ns verify
OUT=$(cat "$T/ns.log")
check "NV1 marker from setup (switch from x86): start without -noverifyfiles, marker gone, client closed by user: no new start (box bug 10)" \
  "[ \"\$(grep '^steam' <<<\"\$OUT\")\" = 'steam -deckard -steamos3 -gamepadui' ] && [ ! -f $T/NA/.config/steam-arm/native-verify ] && ! grep -q REACHED <<<\"\$OUT\""
ns verify 42
OUT=$(cat "$T/ns.log")
check "NV2 marker, client restarts after own update (42): normal start follows" "grep -q REACHED <<<\"\$OUT\" && [ ! -f $T/NA/.config/steam-arm/native-verify ]"
ns plain
OUT=$(cat "$T/ns.log")
check "NV3 no marker, client files present: no file-check start (2.2 behaviour)" "! grep -q '^steam' <<<\"\$OUT\" && grep -q REACHED <<<\"\$OUT\""

# ---------- native normal loop: client end by signal logged (box re-test B11) ----------
NL=$T/nl.sh; awk '/^tries=0$/{f=1} f{print} f && /^done$/{exit}' "$L" > "$NL"
nl(){ rm -f "$T/nl.log"; mkdir -p "$T/NL"; ( export T NRC="$1"; cd "$T/NL"
    printf '#!/bin/sh\nexit $NRC\n' > ./steam; chmod 755 ./steam
    lwarn(){ echo "LWARN $*" >> "$T/nl.log"; }; updated_exit(){ return 1; }; client_running(){ return 1; }; set --; . "$NL" ) >/dev/null 2>&1; cat "$T/nl.log" 2>/dev/null; }
check "NL0 native normal loop extracted, parses" "grep -q -- '-noverifyfiles' $NL && bash -n $NL"
OUT=$(nl 134)
check "NL1 native client ends by signal 6: logged with status (box re-test B11)" "grep -qx 'LWARN client ended by signal 6 (status 134); start Steam ARM again' <<<\"\$OUT\""
OUT=$(nl 0)
check "NL2 native client normal exit: nothing logged" "[ -z \"\$OUT\" ]"

echo "launcher 2.3: $pass pass, $fail fail"
[ "$fail" = 0 ]
