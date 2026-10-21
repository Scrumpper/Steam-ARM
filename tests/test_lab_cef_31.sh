#!/bin/bash
# 3.1 experiment: client window through the GPU for one start. Launcher decision block (environment, one-shot file,
# earlier failed result, x86 client only), client flags, result watcher on synthetic client logs (three GPU process
# exits, compositing on, compositing off after 60 s, client gone), state file and notice; settings menu item 21 and
# CLI lab-cef-gpu; Help page Experiments. Blocks extracted from the installer under test (SARM_INST picks another).
# Internal; not for release zips.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm31-lab.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
check "L0 launcher parses" "sh -n $L"
DB=$T/decide.sh; awk '/^# --- Experiment: client window through the GPU for this start only/{f=1} f{print} f && /^# --- x86 client: webhelper flag/{exit}' "$L" | sed '$d' | sed "s#/proc/meminfo#$T/meminfo#" > "$DB"
printf 'MemTotal:        3884000 kB\nMemAvailable:    2500000 kB\n' > "$T/meminfo"
check "L0b decision block before the per-start prepare call" "grep -q '^export STEAM_ARM_LAB_CEF_GPU=\"\$LAB\"' $DB && [ \$(grep -n '^# --- Experiment: client window' $L | cut -d: -f1) -lt \$(grep -n 'x86client.py prepare \"\$S\" \"\$ARMHOME\" 2>&1); xrc=' $L | head -1 | cut -d: -f1) ]"
dec(){ # CLIENT env(-) onefile(-) state(-)
  rm -rf "$T/d"; mkdir -p "$T/d/.config/steam-arm"; rm -f "$T/d.log"
  [ "$3" = - ] || echo "$3" > "$T/d/.config/steam-arm/lab-cef-gpu"; [ "$4" = - ] || echo "cef-gpu=$4" > "$T/d/.config/steam-arm/state"
  ( CLIENT=$1 ARMHOME=$T/d LOG=$T/d.log; unset STEAM_ARM_LAB_CEF_GPU MESA_GL_VERSION_OVERRIDE MESA_GLSL_VERSION_OVERRIDE CLIENT_GPU; [ "$2" = - ] || export STEAM_ARM_LAB_CEF_GPU=$2; [ -z "${5:-}" ] || CLIENT_GPU=$5
    lwarn(){ echo "$*" >> "$LOG"; }; . "$DB"; echo "LAB=[$LAB] env=[$STEAM_ARM_LAB_CEF_GPU] gl=[${MESA_GL_VERSION_OVERRIDE:-}] file=$([ -f "$T/d/.config/steam-arm/lab-cef-gpu" ] && echo kept || echo gone)" ) 2>&1; cat "$T/d.log" 2>/dev/null; }
OUT=$(dec x86 vulkan - -); check "D1 environment vulkan: LAB=vulkan exported, logged with state path" "grep -qx 'LAB=\[vulkan\] env=\[vulkan\] gl=\[\] file=gone' <<<\"\$OUT\" && grep -q '^lab: client window through GPU (ANGLE vulkan) for this start; result recorded in .*/state (cef-gpu=...)$' <<<\"\$OUT\""
OUT=$(dec x86 gl - -); check "D2 environment gl: GL 4.5 report for the session" "grep -qx 'LAB=\[gl\] env=\[gl\] gl=\[4.5\] file=gone' <<<\"\$OUT\""
OUT=$(dec x86 - gl -); check "D3 one-shot file gl: used once and removed" "grep -qx 'LAB=\[gl\] env=\[gl\] gl=\[4.5\] file=gone' <<<\"\$OUT\""
OUT=$(dec x86 - - -); check "D4 nothing armed: LAB empty, environment exported empty" "grep -qx 'LAB=\[\] env=\[\] gl=\[\] file=gone' <<<\"\$OUT\" && [ -z \"\$(grep '^lab' <<<\"\$OUT\")\" ]"
OUT=$(dec x86 vulkan - failed:gpu-process-exits); check "D5 earlier failed result: software, reason logged with retry hint" "grep -qx 'LAB=\[\] env=\[\] gl=\[\] file=gone' <<<\"\$OUT\" && grep -q '^lab: client window through GPU failed earlier (gpu-process-exits); drawing on CPU; steam-arm-config lab-cef-gpu retry allows another trial$' <<<\"\$OUT\""
OUT=$(dec x86 - - - on); check "D8 CLIENT_GPU=on: Vulkan variant armed without file or environment" "grep -qx 'LAB=\[vulkan\] env=\[vulkan\] gl=\[\] file=gone' <<<\"\$OUT\""
OUT=$(dec x86 - gl - on); check "D8b one-shot file wins over CLIENT_GPU=on" "grep -qx 'LAB=\[gl\] env=\[gl\] gl=\[4.5\] file=gone' <<<\"\$OUT\""
OUT=$(dec x86 - - failed:compositing-disabled on); check "D8c CLIENT_GPU=on with an earlier failed result: software, hint names client-gpu on" "grep -qx 'LAB=\[\] env=\[\] gl=\[\] file=gone' <<<\"\$OUT\" && grep -q 'drawing on CPU; steam-arm-config client-gpu on allows another trial$' <<<\"\$OUT\""
OUT=$(dec x86 - - - off); check "D8d CLIENT_GPU=off: nothing armed" "grep -qx 'LAB=\[\] env=\[\] gl=\[\] file=gone' <<<\"\$OUT\""
printf 'MemTotal:        3884000 kB\nMemAvailable:     900000 kB\n' > "$T/meminfo"
OUT=$(dec x86 vulkan - -); check "D9 MemAvailable below 1536 MB: trial skipped with the figure" "grep -qx 'LAB=\[\] env=\[\] gl=\[\] file=gone' <<<\"\$OUT\" && grep -q '^lab: client window through GPU skipped: 878 MB available, below 1536 MB$' <<<\"\$OUT\""
printf 'MemTotal:        3884000 kB\nMemAvailable:    2500000 kB\n' > "$T/meminfo"
OUT=$(dec x86 vulkan - ok:vulkan); check "D6 earlier ok result: trial allowed again" "grep -qx 'LAB=\[vulkan\] env=\[vulkan\] gl=\[\] file=gone' <<<\"\$OUT\""
OUT=$(dec x86 bogus - -); check "D7 unknown value: ignored" "grep -qx 'LAB=\[\] env=\[\] gl=\[\] file=gone' <<<\"\$OUT\""
# flags in the x86 block
XF=$T/xf.sh; awk '/^  XFLAGS="-steamos3 -cef-disable-gpu -cef-disable-gpu-compositing"$/{f=1} f{print} f && /^  \[ -n "\$LAB" \] && XFLAGS=/{exit}' "$L" > "$XF"
xf(){ ( LIGHT=$1 LAB=$2; unset STEAM_ARM_FRIENDS; LOG=/dev/null; llog(){ :; }; . "$XF"; echo "XFLAGS=[$XFLAGS]" ) 2>&1; }
OUT=$(xf 0 vulkan); check "F1 lab: -cef-force-gpu and GPU sandbox off in place of the disable flags" "grep -qx 'XFLAGS=\[-steamos3 -cef-force-gpu -cef-disable-gpu-sandbox\]' <<<\"\$OUT\""
OUT=$(xf 1 gl); check "F2 lab on the slow class: friends view flag kept" "grep -qx 'XFLAGS=\[-steamos3 -cef-force-gpu -cef-disable-gpu-sandbox -nofriendsui\]' <<<\"\$OUT\""
OUT=$(xf 0 ""); check "F3 no lab: flags as before" "grep -qx 'XFLAGS=\[-steamos3 -cef-disable-gpu -cef-disable-gpu-compositing\]' <<<\"\$OUT\""
# watcher on synthetic logs
WB=$T/watch.sh; awk '/^  LABOFF="\$ARMHOME\/.config\/steam-arm\/lab-offsets"$/{f=1} f{print} f && /^  }$/{c++; if (c == 3) exit}' "$L" > "$WB"
check "W0 watcher functions extracted (lab_new, lab_result, lab_watch), started beside the restart watcher" "grep -q '^  lab_watch(){' $WB && grep -q '^  lab_new(){' $WB && grep -q '^  lab_watch </dev/null >/dev/null 2>&1 &$' $L"
wrun(){ # LAB script-of-log-events
  rm -rf "$T/w"; mkdir -p "$T/w/S/logs" "$T/w/.config/steam-arm"; rm -f "$T/w.log" "$T/w.notes"
  printf 'old GPU process exited\nold GPU process exited\nold GPU process exited\n' > "$T/w/S/logs/webhelper-linux.txt"
  printf '%s\n' "$2" | tr '|' '\n' > "$T/w/events"
  ( LAB=$1 ARMHOME=$T/w S=$T/w/S LABST=$T/w/.config/steam-arm/state LOG=$T/w.log
    n_sleep=0; sleep(){ n_sleep=$((n_sleep + 1)); ev=$(sed -n "${n_sleep}p" "$T/w/events"); [ -n "$ev" ] || { echo end > "$T/w/gone"; return 0; }
      case $ev in gone) echo gone > "$T/w/gone";; -) ;; *) printf '%s\n' "$ev" >> "$T/w/S/logs/webhelper-linux.txt";; esac; }
    t_now=1000; date(){ echo $((t_now + n_sleep * 5)); }
    client_running(){ [ ! -f "$T/w/gone" ]; }
    llog(){ echo "$*" >> "$LOG"; }; lnote(){ echo "NOTE $1 | $2" >> "$T/w.notes"; }
    . "$WB"; lab_watch; echo "rc=$?" ) 2>&1; cat "$T/w/.config/steam-arm/state" "$T/w.log" "$T/w.notes" 2>/dev/null; }
OUT=$(wrun vulkan "GPU process exited|GPU process exited|GPU process exited")
check "W1 three new GPU process exits within 120 s: failed:gpu-process-exits, old lines not counted, one notice" \
  "grep -qx 'cef-gpu=failed:gpu-process-exits' <<<\"\$OUT\" && grep -q '^NOTE lab: client window through GPU (ANGLE vulkan) failed (gpu-process-exits); next start draws on CPU again' <<<\"\$OUT\" && [ \$(grep -c '^NOTE' <<<\"\$OUT\") = 1 ]"
OUT=$(wrun gl "-|GL_RENDERER: V3D 4.2|gpu_compositing: enabled")
check "W2 compositing enabled: ok:gl, renderer line logged, notice names --cpu-report and client-gpu on" "grep -qx 'cef-gpu=ok:gl' <<<\"\$OUT\" && grep -q '^lab: GL_RENDERER: V3D 4.2' <<<\"\$OUT\" && grep -q 'GPU compositing enabled; details in .* and steam-arm --cpu-report; steam-arm-config client-gpu on keeps it' <<<\"\$OUT\""
OUT=$(wrun vulkan "-|[2026-10-20 10:00:00]                 [ GL_RENDERER ]: ANGLE (Broadcom, V3D 4.2)|[2026-10-20 10:00:00]                     [ gpu_compositing ]: enabled")
check "W2b Chromium's own line form ([ gpu_compositing ]: enabled): ok:vulkan" "grep -qx 'cef-gpu=ok:vulkan' <<<\"\$OUT\""
OUT=$(CLIENT_GPU=on; export CLIENT_GPU; wrun vulkan "GPU process exited|GPU process exited|GPU process exited")
check "W2c failed with CLIENT_GPU=on: notice names client-gpu on for another trial, no keep hint" "grep -q 'failed (gpu-process-exits); next start draws on CPU again; steam-arm-config client-gpu on allows another trial' <<<\"\$OUT\""
ev=""; for i in $(seq 1 13); do ev="$ev-|"; done
OUT=$(wrun vulkan "gpu_compositing: disabled|${ev}-")
check "W3 compositing disabled, still so after 60 s: failed:compositing-disabled (not before 60 s)" "grep -qx 'cef-gpu=failed:compositing-disabled' <<<\"\$OUT\""
OUT=$(wrun vulkan "-|gone")
check "W4 client gone: failed:client-exited" "grep -qx 'cef-gpu=failed:client-exited' <<<\"\$OUT\""
ev=""; for i in $(seq 1 40); do ev="$ev-|"; done
OUT=$(wrun vulkan "${ev}-")
check "W5 nothing in 180 s: failed:no-result" "grep -qx 'cef-gpu=failed:no-result' <<<\"\$OUT\""
printf 'other=1\ncef-gpu=failed:old\n' > "$T/w.prev"
OUT=$( rm -rf "$T/w"; mkdir -p "$T/w/S/logs" "$T/w/.config/steam-arm"; cp "$T/w.prev" "$T/w/.config/steam-arm/state"; printf 'gpu_compositing: enabled\n' > "$T/w/events"
  ( LAB=vulkan ARMHOME=$T/w S=$T/w/S LABST=$T/w/.config/steam-arm/state LOG=/dev/null; n=0; sleep(){ n=$((n + 1)); [ $n = 1 ] && printf 'gpu_compositing: enabled\n' >> "$T/w/S/logs/webhelper-linux.txt"; [ $n -le 2 ]; }
    date(){ echo 1000; }; client_running(){ return 0; }; llog(){ :; }; lnote(){ :; }; . "$WB"; lab_watch ) 2>&1; cat "$T/w/.config/steam-arm/state" )
check "W6 state file: other lines kept, earlier cef-gpu line replaced" "[ \"\$OUT\" = \$'other=1\ncef-gpu=ok:vulkan' ]"
OUT=$( ( LAB=; . "$WB"; lab_watch; echo "rc=$?" ) 2>&1 ); check "W7 no lab: watcher returns at once" "[ \"\$OUT\" = rc=0 ]"

# settings menu: item 21, screen, CLI
T0=$SARM_TESTS/config-ui
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
bash "$T0/mkfake.sh" >/dev/null
sed -e "s#^APP=.*#APP=\"$CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"
export Q=$T/q LOG=$T/ui.log
cat > "$T/stubs.sh" <<'EOF'
nxt(){ A=$(head -n 1 "$Q"); sed -i 1d "$Q"; }
ui_menu(){ printf 'MENU %s|%s|%s\n' "$1" "$2" "${*:3}" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; echo "$A"; }
ui_msg(){ printf 'MSG %s|%s\n' "$1" "$2" >> "$LOG"; }
ui_textstr(){ printf 'TEXT %s|%s\n' "$1" "$2" >> "$LOG"; }
ui_info(){ :; }
ui_yesno(){ printf 'YESNO %s|%s\n' "$1" "$2" >> "$LOG"; nxt; [ "$A" = yes ]; }
up_notice(){ :; }; up_check_open(){ :; }; state_pending(){ return 1; }; status_line(){ :; }
EOF
ui(){ local s=$1; shift; : > "$LOG"; printf '%s\n' "$@" > "$Q"; bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; $s" >/dev/null 2>"$T/err"; RC=$?; OUT=$(cat "$LOG" "$T/err"); }
cli(){ OUT=$(bash -c ". $T/harness.sh --help >/dev/null; main $*" 2>&1); RC=$?; }
CONF=$SARM_UI_FAKE/etc/steam-arm/steam-arm.conf; echo CLIENT=x86 >> "$CONF"
AH=$SARM_UI_FAKE/home/tester/.local/share/steam-arm
ui menu_maintenance 21 vulkan
check "M1 Maintenance item 21 (x86 client); screen names one start, ANGLE, state file, low odds; vulkan arms the next start" \
  "grep -q ' 21 Experiment: client window through GPU at next start' <<<\"\$OUT\" && grep -q '^MENU Experiment: client window through GPU|x86 client. Next start of Steam ARM runs the client window with GPU forwarding on and ANGLE' <<<\"\$OUT\" && grep -q 'Low odds' <<<\"\$OUT\" && [ \"\$(cat $AH/.config/steam-arm/lab-cef-gpu)\" = vulkan ] && grep -q '^MSG Experiment|Client window through GPU: next start: vulkan; last result: none' <<<\"\$OUT\""
cli lab-cef-gpu; check "M2 CLI status" "[ $RC = 0 ] && grep -q '^client window through GPU: next start: vulkan; last result: none$' <<<\"\$OUT\""
cli lab-cef-gpu off; check "M3 CLI off removes the file" "[ $RC = 0 ] && [ ! -e $AH/.config/steam-arm/lab-cef-gpu ]"
mkdir -p "$AH/.config/steam-arm"; printf 'cef-gpu=failed:gpu-process-exits\n' > "$AH/.config/steam-arm/state"
cli lab-cef-gpu status; check "M4 status shows last result" "grep -q 'last result: failed:gpu-process-exits' <<<\"\$OUT\""
cli lab-cef-gpu retry; check "M5 retry removes the result line" "[ $RC = 0 ] && ! grep -q cef-gpu $AH/.config/steam-arm/state"
cli lab-cef-gpu maybe; check "M6 bad value: usage" "[ $RC = 2 ]"
# client-gpu: setting key, failed result cleared by on, lab screen keep item
printf 'cef-gpu=failed:no-result\n' > "$AH/.config/steam-arm/state"
cli client-gpu; check "K1 CLI state: off, last result shown" "[ $RC = 0 ] && grep -q '^client window through GPU at every start: off; last result: failed:no-result$' <<<\"\$OUT\""
cli client-gpu on; check "K2 CLI on: CLIENT_GPU=on written, failed result cleared, line names Vulkan and the turn-off rule" "[ $RC = 0 ] && grep -qx 'CLIENT_GPU=on' '$CONF' && ! grep -q cef-gpu $AH/.config/steam-arm/state && grep -q 'on (ANGLE on Vulkan; a failed start turns it off)' <<<\"\$OUT\""
cli client-gpu off; check "K3 CLI off" "[ $RC = 0 ] && grep -qx 'CLIENT_GPU=off' '$CONF'"
cli client-gpu maybe; check "K4 bad value: usage" "[ $RC = 2 ]"
ui menu_maintenance 21 keep yes
check "K5 lab screen: keep item, confirmation names the turn-off rule, CLIENT_GPU=on" "grep -q 'keep Keep ANGLE on Vulkan at every start (now: off)' <<<\"\$OUT\" && grep -q '^YESNO Keep client window through GPU|' <<<\"\$OUT\" && grep -q 'turns this off again' <<<\"\$OUT\" && grep -qx 'CLIENT_GPU=on' '$CONF' && grep -q '^MSG Experiment|Client window through GPU at every start: on.' <<<\"\$OUT\""
ui menu_maintenance 21 keep
check "K6 lab screen keep with on: turned off without question" "grep -qx 'CLIENT_GPU=off' '$CONF' && grep -q '^MSG Experiment|Client window through GPU at every start: off.' <<<\"\$OUT\""
check "K7 CLIENT_GPU in backup key list and value rule, --help lists client-gpu and CLIENT_GPU" "grep -q '^SA_BK_KEYS=.* CLIENT_LIGHT CLIENT_GPU' '$CFG' && grep -q 'X87_CLIENT|CLIENT_LIGHT|CLIENT_GPU) case \"\$2\" in on|off|\"\") return 0;; esac; return 1;;' '$CFG'"
cli --help; check "K8 --help lists client-gpu and CLIENT_GPU" "grep -q '^  client-gpu \[on|off\]' <<<\"\$OUT\" && grep -q 'CLIENT_GPU=on|off' <<<\"\$OUT\""
sed -i 's/^CLIENT=x86$/CLIENT=arm64/' "$CONF"; ui menu_maintenance BACK
check "M7 native client: no item 21" "! grep -q ' 21 Experiment' <<<\"\$OUT\""
ui menu_help 2 BACK
check "M8 Help page Experiments present, names lab-cef-gpu, state file and --cpu-report" "grep -q '^TEXT Experiments|Experiments' <<<\"\$OUT\" && grep -q 'lab-cef-gpu' <<<\"\$OUT\" && grep -q 'cef-gpu=failed:<reason>' <<<\"\$OUT\" && grep -q 'steam-arm --cpu-report' <<<\"\$OUT\""
cli --help; check "M9 --help lists lab-cef-gpu" "grep -q '^  lab-cef-gpu \[vulkan|gl|off|retry|status\]' <<<\"\$OUT\""

echo "lab cef gpu 3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
