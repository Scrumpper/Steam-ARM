#!/bin/bash
# 2.1 (2.2 merged) launcher: first-start notification (notice/notice_close/boot_phase/first_start_notice), sourced
# from the launcher embedded in the installer, against stub gdbus/notify-send/pgrep; Armv8.1 check of launcher and
# setup; fex_ver order. Installer from paths.sh (link path without spaces; SARM_INST picks another).
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232b-launcher.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
check "launcher parses (sh -n)" "sh -n $L"
# functions only: client_running, then BOOTLOG .. end of first_start_notice
F=$T/funcs.sh
{ awk '/^client_running\(\)/{print; exit}' "$L"
  awk '/^notice\(\)/{f=1} f{print} f&&/CloseNotification "\$1" >\/dev\/null 2>&1; }$/{exit}' "$L"
  awk '/^BOOTLOG=/{f=1} f{print} f&&/^first_start_notice\(\)/{g=1} g&&/^}/{exit}' "$L"
} > "$F"
check "function block extracted" "grep -q '^notice()' $F && grep -q '^notice_close()' $F && grep -q '^boot_phase()' $F && grep -q '^first_start_notice()' $F"
# tool dirs: base (real awk/tail/stat/sed/tr/id), gdbus stub, notify-send stub (-p ok), notify-send old (-p fails)
mkdir -p "$T/base" "$T/gd" "$T/ns" "$T/nsold" "$T/run" "$T/S/logs"
for c in awk tail stat sed tr head cat id sleep grep; do ln -s "$(command -v $c)" "$T/base/$c"; done
cat > "$T/base/pgrep" <<'EOF'
#!/bin/sh
[ -f "$STUB/client" ]
EOF
# gdbus stub: Notify prints "(uint32 ID,)", ID = replaces_id or 7 for a new one; every call logged
cat > "$T/gd/gdbus" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB/gdbus.log"
case "$*" in
  *Notifications.Notify*) for a; do shift; case $a in *Notifications.Notify) break;; esac; done
    id=$2; [ "$id" = 0 ] && id=7; echo "(uint32 $id,)";;
  *) echo "()";;
esac
EOF
cat > "$T/ns/notify-send" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB/ns.log"
case " $* " in *" -p "*) [ -f "$STUB/old-ns" ] && { echo "Unknown option -p" >&2; exit 1; }; echo 5;; esac
EOF
cp "$T/ns/notify-send" "$T/nsold/notify-send"
chmod +x "$T/base/pgrep" "$T/gd/gdbus" "$T/ns/notify-send" "$T/nsold/notify-send"
export STUB=$T/run
BL=$T/S/logs/bootstrap_log.txt
# run VARIANT CODE: sources the functions with stub tools; sleep feeds the next queued log line, no wait
run(){ ( export PATH="$T/$1:$T/base" DISPLAY=:0; S=$T/S; T=$T
  sleep(){ l=$(head -n 1 "$STUB/queue" 2>/dev/null); [ -n "$l" ] && { printf '%s\n' "$l" >> "$BOOTLOG"; sed -i 1d "$STUB/queue"; }; return 0; }
  . "$F"; eval "$2"); }
reset(){ rm -f "$STUB"/* "$BL"; : > "$BL"; }
D1='[2026-10-04 21:22:46] Downloading update (113,634 of 662,547 KB)...'
D2='[2026-10-04 21:22:50] Downloading update (131,000 of 662,547 KB)...'
D3='[2026-10-04 21:23:36] Downloading update (662,547 of 662,547 KB)...'
EX='[2026-10-04 21:23:37] Extracting package...'
IN='[2026-10-04 21:24:02] Installing update...'
UP='[2026-10-04 21:24:09] Update complete, launching...'

# boot_phase
reset; printf '%s\n' "$D1" > "$BL"
check "boot_phase: download line -> 10 % step and total MB" "[ \"\$(run gd 'boot_phase 0')\" = 'Downloading client files: 10% of 647 MB' ]"
printf '%s\n' "$D2" >> "$BL"
check "boot_phase: 19 % reads as 10 %" "[ \"\$(run gd 'boot_phase 0')\" = 'Downloading client files: 10% of 647 MB' ]"
printf '%s\n' "$D3" "$EX" >> "$BL"
check "boot_phase: extracting -> unpacking" "[ \"\$(run gd 'boot_phase 0')\" = 'Unpacking client files' ]"
printf '%s\n' "$IN" >> "$BL"
check "boot_phase: installing" "[ \"\$(run gd 'boot_phase 0')\" = 'Installing client files' ]"
printf '%s\n' "$UP" >> "$BL"
check "boot_phase: update complete -> done" "[ \"\$(run gd 'boot_phase 0')\" = done ]"
off=$(stat -c %s "$BL"); printf '%s\n' '[2026-10-04 21:24:10] Startup - updater' >> "$BL"
check "boot_phase: lines before the start offset ignored" "[ -z \"\$(run gd \"boot_phase $off\")\" ]"
check "boot_phase: missing log -> empty" "[ -z \"\$(run gd 'BOOTLOG=$T/none; boot_phase 0')\" ]"

# first_start_notice, gdbus path
reset
run gd 'DISPLAY=; WAYLAND_DISPLAY=; first_start_notice'
check "no display: no notification" "[ ! -f $STUB/gdbus.log ]"
reset; touch "$STUB/client"; printf '%s\n' "$D1" "$D2" "$D3" "$EX" "$IN" "$UP" > "$STUB/queue"
run gd 'first_start_notice'
check "gdbus: first notice at once, new id, persistent, app and icon set" "grep -q -- '--timeout 5 .*Notifications.Notify Steam ARM 0 steam-arm Steam ARM: first start Downloading client files, this takes a few minutes. Steam opens when done. \[\] {} 0$' $STUB/gdbus.log"
check "gdbus: phases (10 %, 100 %, unpack, install, done) replace the same notification in place" "[ \$(grep -c 'Notify Steam ARM 7 ' $STUB/gdbus.log) = 5 ] && [ \$(grep -c 'Notify Steam ARM 0 ' $STUB/gdbus.log) = 1 ]"
check "gdbus: unchanged download step sends nothing" "[ \$(grep -c 'Downloading client files: 10% of 647 MB' $STUB/gdbus.log) = 1 ]"
check "gdbus: unpack and install phases sent" "grep -q 'Notify Steam ARM 7 steam-arm Steam ARM: first start Unpacking client files' $STUB/gdbus.log && grep -q 'Installing client files' $STUB/gdbus.log"
check "gdbus: update complete -> final notice with timeout, no close" "grep -q 'Notify Steam ARM 7 steam-arm Steam ARM Client files installed. Steam opens now. \[\] {} 10000$' $STUB/gdbus.log && ! grep -q CloseNotification $STUB/gdbus.log"
# client gone before the update completes: notification closed
reset; printf '%s\n' "$D1" > "$STUB/queue"
run gd 'first_start_notice'
check "gdbus: client gone -> notification closed" "grep -q 'CloseNotification 7$' $STUB/gdbus.log && [ \$(grep -c Notify $STUB/gdbus.log) = 2 ]"
# client stays, log silent: ends after the 30 min cap with a close
reset; touch "$STUB/client"
run gd 'first_start_notice'
check "gdbus: 30 min cap -> one notice, then closed" "[ \$(grep -c 'Notifications.Notify' $STUB/gdbus.log) = 1 ] && grep -q 'CloseNotification 7$' $STUB/gdbus.log"
# no id from the server: nothing more
reset; touch "$STUB/client"; printf '%s\n' "$D1" > "$STUB/queue"
run gd 'notice(){ echo "$*" >> $STUB/n.log; }; first_start_notice'
check "no id from server: no updates, no close" "[ \$(wc -l < $STUB/n.log) = 1 ] && [ ! -f $STUB/gdbus.log ]"
# SIGTERM while waiting (launcher exit), started in the background like the launcher does: notification closed
reset; touch "$STUB/client"
run gd 'sleep(){ command sleep 0.2; }; first_start_notice & w=$!; command sleep 0.6; kill -TERM $w; wait $w'
check "gdbus: SIGTERM closes the notification" "grep -q 'CloseNotification 7$' $STUB/gdbus.log && [ \$(grep -c Notifications.Notify $STUB/gdbus.log) = 1 ]"

# notify-send path (no gdbus)
reset; touch "$STUB/client"; printf '%s\n' "$D1" "$UP" > "$STUB/queue"
run ns 'first_start_notice'
check "notify-send: first call -p -r 0, updates -r 5, final with timeout" "grep -q -- '^-p -r 0 -a Steam ARM -i steam-arm -t 0 Steam ARM: first start Downloading client files, this takes' $STUB/ns.log && grep -q -- '^-p -r 5 -a Steam ARM -i steam-arm -t 0 Steam ARM: first start Downloading client files: 10% of 647 MB' $STUB/ns.log && grep -q -- '^-p -r 5 -a Steam ARM -i steam-arm -t 10000 Steam ARM Client files installed' $STUB/ns.log"
reset; touch "$STUB/client" "$STUB/old-ns"; printf '%s\n' "$D1" "$UP" > "$STUB/queue"
run nsold 'first_start_notice'
check "notify-send without -p: one plain notice, no updates" "[ \$(wc -l < $STUB/ns.log) = 2 ] && grep -q -- '^-a Steam ARM -i steam-arm -t 15000 Steam ARM: first start' $STUB/ns.log"

# launcher structure: notice starts inside the first-start block, before the client, watched by on_exit
ln_if=$(grep -n '^if \[ ! -f "\$S/linuxarm64/steamclient.so" \] || \[ -f "\$NVER" \]; then$' "$L" | head -1 | cut -d: -f1)
ln_call=$(grep -n '^  first_start_notice </dev/null >/dev/null 2>&1 &$' "$L" | cut -d: -f1)
ln_pid=$(grep -n '^  NOTEWATCH=\$!$' "$L" | cut -d: -f1)
ln_steam=$(grep -n '^    \./steam -deckard -steamos3 \${GPUI:+"\$GPUI"} "\$@"$' "$L" | head -1 | cut -d: -f1)
ln_fi=$(awk -v s="$ln_if" 'NR > s && /^fi$/ { print NR; exit }' "$L")
ln_log=$(grep -n '^BOOTLOG=' "$L" | cut -d: -f1)
check "launcher: notice started inside the first-start block, before the client" "[ -n '$ln_if' ] && [ -n '$ln_call' ] && [ -n '$ln_pid' ] && [ -n '$ln_steam' ] && [ $ln_if -lt $ln_call ] && [ $ln_call -lt $ln_pid ] && [ $ln_pid -lt $ln_steam ] && [ $ln_steam -lt $ln_fi ]"
check "launcher: first_start_notice defined once, called at first start and on bootstrap restart (native and x86 client)" "[ \$(grep -c 'first_start_notice' $L) = 5 ]"
check "launcher: on_exit stops the notice watcher" "grep -q '\[ -n \"\$NOTEWATCH\" \] && kill \"\$NOTEWATCH\"' $L"
check "launcher: BOOTLOG set once, before the first-start block" "[ \$(printf '%s\n' '$ln_log' | wc -l) = 1 ] && [ $ln_log -lt $ln_if ]"
check "launcher: no env override for the notice" "! grep -q 'STEAM_ARM_NOTI\|STEAM_ARM_FIRST' $L"

# Armv8.1 (LSE) check. Fake cpuinfo: with atomics, without (later CPU has it), no Features line.
printf 'processor\t: 0\nBogoMIPS\t: 48.00\nFeatures\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp\n\nprocessor\t: 1\nFeatures\t: fp asimd\n' > "$T/cpu-lse"
printf 'processor\t: 0\nBogoMIPS\t: 108.00\nFeatures\t: fp asimd evtstrm crc32 cpuid\n\nprocessor\t: 1\nFeatures\t: fp asimd evtstrm crc32 cpuid atomics\n' > "$T/cpu-v80"
printf 'processor\t: 0\nBogoMIPS\t: 48.00\n' > "$T/cpu-none"
# launcher block: comment line to closing fi, /proc/cpuinfo pointed at fake file, lwarn/stop stubbed
LB=$T/lse-launcher.sh
awk '/^# Client needs Armv8.1 atomics \(LSE\); STEAM_ARM_ALLOW_ARMV80=1 skips the check\.$/{f=1} f{print} f&&/^fi$/{exit}' "$L" > "$LB"
check "launcher: LSE block extracted" "grep -q atomics $LB && [ \$(wc -l < $LB) -ge 5 ]"
lrun(){ sed "s#/proc/cpuinfo#$T/$1#" "$LB" > "$T/lb-$1.sh"
  printf 'lwarn(){ echo "LWARN $*"; }\nstop(){ echo "STOP $1"; exit 1; }\n. %s\necho STARTED\n' "$T/lb-$1.sh" > "$T/lb-run.sh"
  env -u STEAM_ARM_ALLOW_ARMV80 $2 sh "$T/lb-run.sh"; }
out=$(lrun cpu-lse)
check "launcher: Features with atomics -> starts" "[ \"\$out\" = STARTED ]"
out=$(lrun cpu-v80)
check "launcher: Features without atomics -> lwarn + stop, issue and override named" "printf '%s\n' \"\$out\" | grep -q '^LWARN This CPU has no Armv8.1 atomics' && printf '%s\n' \"\$out\" | grep -q '^STOP .*needs Armv8.1 or newer.*steam-for-linux/issues/13288.*STEAM_ARM_ALLOW_ARMV80=1' && ! printf '%s\n' \"\$out\" | grep -q STARTED"
out=$(lrun cpu-v80 STEAM_ARM_ALLOW_ARMV80=1)
check "launcher: STEAM_ARM_ALLOW_ARMV80=1 -> starts" "[ \"\$out\" = STARTED ]"
out=$(lrun cpu-v80 STEAM_ARM_ALLOW_ARMV80=0)
check "launcher: STEAM_ARM_ALLOW_ARMV80=0 -> stops" "printf '%s\n' \"\$out\" | grep -q '^STOP'"
out=$(lrun cpu-none)
check "launcher: no Features line -> starts" "[ \"\$out\" = STARTED ]"
ln_lse=$(grep -n '^# Client needs Armv8.1 atomics (LSE); STEAM_ARM_ALLOW_ARMV80' "$L" | cut -d: -f1)
ln_sd=$(grep -n '^  --shutdown) stop_client; exit \$?;;$' "$L" | cut -d: -f1)
ln_kde=$(grep -n '^KDEIN=' "$L" | cut -d: -f1)
check "launcher: check after --help/--shutdown, before KDE step and client start" "[ -n '$ln_lse' ] && [ $ln_sd -lt $ln_lse ] && [ $ln_lse -lt $ln_kde ] && [ $ln_lse -lt $ln_if ]"

# setup preflight (2.3): client type in place of the 2.2 stop; CPU helpers + client_pick + mem_gate + block, fake cpuinfo
IB=$T/lse-inst.sh
{ awk '/^cpu_features\(\)/{f=1} /^# curl progress bar/{exit} f' "$INST"
  awk '/^# Client type \(CPU, option or saved choice\): before any package change\.$/{f=1} f{print} f&&/^fi$/{exit}' "$INST"
} > "$IB"
check "setup: preflight extracted" "grep -q '^cpu_features()' $IB && grep -q '^client_pick()' $IB && grep -q '^mem_gate()' $IB && grep -q 'warn \"\$(x86_warn)\"' $IB"
irun(){ sed "s#/proc/cpuinfo#$T/$1#" "$IB" > "$T/ib-$1.sh"
  printf 'die(){ echo "DIE $*"; exit 1; }\nwarn(){ echo "WARN $*"; }\nconf_get(){ :; }\nMODE=${MODE:-defaults}\n. %s\necho "CONTINUE ${CLIENT:-}"\n' "$T/ib-$1.sh" > "$T/ib-run.sh"
  env -u STEAM_ARM_ALLOW_ARMV80 $2 bash "$T/ib-run.sh"; }
out=$(irun cpu-lse)
check "setup: Features with atomics -> native client, no warning" "[ \"\$out\" = 'CONTINUE arm64' ]"
out=$(irun cpu-v80)
check "setup: Features without atomics -> x86 client with warning; issue 13288 and way back named" "printf '%s\n' \"\$out\" | head -1 | grep -q '^WARN CPU without Armv8.1 atomics (LSE)' && printf '%s\n' \"\$out\" | grep -q 'steam-for-linux #13288' && printf '%s\n' \"\$out\" | grep -q 'STEAM_ARM_ALLOW_ARMV80=1) keeps native client' && [ \"\$(printf '%s\n' \"\$out\" | tail -1)\" = 'CONTINUE x86' ]"
out=$(irun cpu-v80 STEAM_ARM_ALLOW_ARMV80=1)
check "setup: override -> native client, warning, continues" "printf '%s\n' \"\$out\" | head -1 | grep -q '^WARN CPU without Armv8.1 atomics (LSE), native ARM64 client chosen by hand' && [ \"\$(printf '%s\n' \"\$out\" | tail -1)\" = 'CONTINUE arm64' ]"
out=$(irun cpu-v80 MODE=remove)
check "setup: --remove not blocked" "[ \"\$out\" = 'CONTINUE ' ]"
out=$(irun cpu-none)
check "setup: no Features line -> continues" "[ \"\$out\" = 'CONTINUE arm64' ]"
check "setup: fex_arch reads same helper" "awk '/^fex_arch\\(\\)/{f=1} f&&/cpu_features/{print; exit}' $INST | grep -q 'cpu_features'"
# order: after --help/--detect exits, before lock, checklist, page size, PPA and apt
lnI(){ grep -n -- "$1" "$INST" | head -1 | cut -d: -f1; }
l_chk=$(lnI '^# Client type (CPU, option or saved choice): before any package change.$')
l_help=$(lnI '^\[ "\$HELP" = 1 \] && { usage; exit 0; }$')
l_det=$(lnI '^\[ "\$MODE" = detect \] && { gpu_report; exit 0; }$')
l_lock=$(lnI 'exec 8>/run/steam-arm-setup.lock')
l_case=$(lnI '^case "\$MODE" in$')
l_ps=$(lnI '^PAGESIZE=\$(getconf PAGESIZE')
l_ppa=$(lnI 'add-apt-repository -y "\$FEXPPA"')
l_upd=$(lnI 'apt-get update -y ||')
check "setup: check after --help/--detect, before lock, checklist, page size, PPA and apt" "[ -n '$l_chk' ] && [ $l_help -lt $l_chk ] && [ $l_det -lt $l_chk ] && [ $l_chk -lt $l_lock ] && [ $l_chk -lt $l_case ] && [ $l_chk -lt $l_ps ] && [ $l_chk -lt $l_ppa ] && [ $l_chk -lt $l_upd ]"
check "setup --help names STEAM_ARM_ALLOW_ARMV80" "awk '/^usage\\(\\)/{f=1} f' $INST | grep -q '^  STEAM_ARM_ALLOW_ARMV80=1 '"

# fex_ver (embedded settings menu): FEXGetConfig, FEX, FEXInterpreter (--version each), then package.
# Stubs as on box 2026-10-04 (FEX 2609.1): FEXGetConfig prints "2609.1", FEX runs "--version" as a program.
CF=$T/cfg.sh
awk '/^menu_app\(\)\{ cat <<.STEAMARMCONFIG.$/{f=1;next} /^STEAMARMCONFIG$/{f=0} f' "$INST" > "$CF"
FV=$T/fexver.sh
{ echo 'have(){ command -v "$1" >/dev/null 2>&1; }'; awk '/^fex_ver\(\)/{f=1} f{print} f&&/^}/{exit}' "$CF"; } > "$FV"
mkdir -p "$T/fx"
mk(){ printf '#!/bin/sh\n%s\n' "$2" > "$T/fx/$1"; chmod +x "$T/fx/$1"; }
fv(){ ( PATH="$T/fx:$T/base"; . "$FV"; fex_ver ); }
FEX2609='echo "$1: command not found" >&2; exit 1'
rm -f "$T/fx/"*; mk FEXGetConfig 'echo 2609.1'; mk FEX "$FEX2609"; mk dpkg-query 'echo "fex-emu-armv8.2 2609.1-1"'
check "fex_ver: FEX 2609.1 layout -> FEXGetConfig version" "[ \"\$(fv)\" = FEX-2609.1 ]"
rm -f "$T/fx/FEXGetConfig"; mk FEX 'echo "FEX-Emu (FEX-2610)"'
check "fex_ver: no FEXGetConfig, FEX with --version -> FEX" "[ \"\$(fv)\" = 'FEX-Emu (FEX-2610)' ]"
mk FEX "$FEX2609"; mk FEXInterpreter 'echo "FEX-Emu (FEX-2607)"'
check "fex_ver: FEX without --version -> FEXInterpreter" "[ \"\$(fv)\" = 'FEX-Emu (FEX-2607)' ]"
mk FEXGetConfig 'echo "Usage: FEXGetConfig [options]"'
check "fex_ver: FEXGetConfig output without digits skipped" "[ \"\$(fv)\" = 'FEX-Emu (FEX-2607)' ]"
rm -f "$T/fx/FEXInterpreter" "$T/fx/FEXGetConfig"
check "fex_ver: no version from tools -> package" "[ \"\$(fv)\" = 'fex-emu-armv8.2 2609.1-1' ]"
rm -f "$T/fx/"*
check "fex_ver: nothing -> not installed" "[ \"\$(fv)\" = 'not installed' ]"

# mangohud shim: mh_real/mh_shim from setup; shim path, PATH and fixed dirs pointed into $T.
MS=$T/mhshim.sh
{ grep -m1 '^MH_MARK=' "$INST"; awk '/^mh_real\(\)/{f=1} f{print} f&&/^MHSHIM$/{g=1} g&&/^}$/{exit}' "$INST"; } \
  | sed "s#for d in \$PATH /usr/bin /bin#for d in \$PATH $T/mh/usrbin#" > "$MS"
check "mangohud: shim functions extracted" "grep -q '^mh_real()' $MS && grep -q '^mh_shim()' $MS && grep -q 'MANGOHUD=1 exec' $MS"
mkdir -p "$T/mh/usrbin" "$T/mh/other" "$T/mh/loc" "$T/mhb"
for c in dirname mkdir chmod rm sh cmp env cat grep; do ln -s "$(command -v $c)" "$T/mhb/$c"; done
mrun(){ ( export PATH="$T/mh/loc:$1:$T/mhb" MH_SHIM=$T/mh/loc/mangohud; . "$MS"; eval "$2" ); }
real='#!/bin/sh
echo real-mangohud "$@"'
mrun "$T/mh/other" mh_shim
check "mangohud: no mangohud on PATH -> shim written, executable, marker" "[ -x $T/mh/loc/mangohud ] && grep -qF '# steam-arm-setup mangohud shim' $T/mh/loc/mangohud"
out=$(env -u MANGOHUD PATH="$T/mhb" sh "$T/mh/loc/mangohud" sh -c 'echo "MH=$MANGOHUD args=$*"' x a b)
check "mangohud: shim sets MANGOHUD=1 and runs the command with its arguments" "[ \"\$out\" = 'MH=1 args=a b' ]"
sed -i 's/MANGOHUD=1 exec/MANGOHUD=1 exec  /' "$T/mh/loc/mangohud"; mrun "$T/mh/other" mh_shim
check "mangohud: own shim refreshed on later run" "grep -q 'MANGOHUD=1 exec \"' $T/mh/loc/mangohud"
printf '%s\n' "$real" > "$T/mh/other/mangohud"; chmod +x "$T/mh/other/mangohud"
mrun "$T/mh/other" mh_shim
check "mangohud: real mangohud elsewhere on PATH -> own shim removed" "[ ! -e $T/mh/loc/mangohud ] && [ -x $T/mh/other/mangohud ]"
mrun "$T/mh/other" mh_shim
check "mangohud: real mangohud on PATH -> no shim written" "[ ! -e $T/mh/loc/mangohud ]"
rm -f "$T/mh/other/mangohud"; printf '%s\n' "$real" > "$T/mh/usrbin/mangohud"; chmod +x "$T/mh/usrbin/mangohud"
mrun "$T/mh/other" mh_shim
check "mangohud: real mangohud in fixed dir (off PATH) -> no shim written" "[ ! -e $T/mh/loc/mangohud ]"
rm -f "$T/mh/usrbin/mangohud"; printf '%s\n' "$real" > "$T/mh/loc/mangohud"; chmod +x "$T/mh/loc/mangohud"; cp "$T/mh/loc/mangohud" "$T/mh/real.ref"
mrun "$T/mh/other" mh_shim
check "mangohud: real mangohud at shim path -> not overwritten" "cmp -s $T/mh/loc/mangohud $T/mh/real.ref"
printf '#!/bin/sh\necho user script\n' > "$T/mh/loc/mangohud"; chmod -x "$T/mh/loc/mangohud"; cp "$T/mh/loc/mangohud" "$T/mh/real.ref"
mrun "$T/mh/other" mh_shim
check "mangohud: non-executable foreign file at shim path -> not overwritten" "cmp -s $T/mh/loc/mangohud $T/mh/real.ref"
# removal line from remove_all, run against marked and foreign file
RL=$(awk '/^remove_all\(\)/{f=1} f&&/grep -qsF "\$MH_MARK" "\$MH_SHIM" && rm -f "\$MH_SHIM"/{print; exit}' "$INST")
check "mangohud: remove_all deletes shim by marker only" "[ -n '$RL' ]"
mrun "$T/mh/other" "$RL"
check "mangohud: removal keeps file without marker" "cmp -s $T/mh/loc/mangohud $T/mh/real.ref"
rm -f "$T/mh/loc/mangohud"; mrun "$T/mh/other" mh_shim; had=0; [ -x "$T/mh/loc/mangohud" ] && had=1; mrun "$T/mh/other" "$RL"
check "mangohud: removal deletes own shim" "[ $had = 1 ] && [ ! -e $T/mh/loc/mangohud ]"
ln_h=$(grep -n '^chmod 644 /usr/local/lib/steam-arm-handler.py$' "$INST" | cut -d: -f1)
ln_m=$(grep -n '^mh_shim || warn ' "$INST" | cut -d: -f1)
check "mangohud: setup writes shim once, after handler" "[ -n '$ln_m' ] && [ \$(printf '%s\n' '$ln_m' | wc -l) = 1 ] && [ $ln_h -lt $ln_m ]"
check "mangohud: handler adds no mangohud word handling (shim only sets MANGOHUD=1)" "! awk '/^cat > \\/usr\\/local\\/lib\\/steam-arm-handler.py/{f=1} f&&/^HANDLERPY\$/{exit} f' $INST | grep -q 'argv.*mangohud\\|mangohud.*argv'"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
