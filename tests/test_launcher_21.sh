#!/bin/bash
# 2.1 launcher: display mode restore (mode_get/mode_restore/mode_watch/on_exit) and stop path (stop_client),
# sourced from the launcher embedded in the installer, against stub xrandr/pgrep/pkill/steam.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-launcher.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
check "launcher parses (sh -n)" "sh -n $L"
# functions only: lwarn .. stop path, and display mode block .. on_exit
F=$T/funcs.sh
{ echo 'LOG=$T/steam-arm.log'
  awk '/^lwarn\(\)/{print} /^client_running\(\)/{f=1} f&&/^case "\$\{1:-\}" in/{f=0} f' "$L"
  awk '/^MODEF=/{f=1} f{print} f&&/^  mode_ok && ! game_up/{f=0}' "$L"
  awk '/^lnote\(\)/{f=1} f{print} f&&/^}/{exit}' "$L"
  echo 'notice(){ echo "$*" >> "$STUB/notice.log"; }'
  echo 'restore_pad(){ :; }'
} > "$F"
check "function block extracted" "grep -q '^mode_restore()' $F && grep -q '^stop_client()' $F && grep -q '^on_exit()' $F"
mkdir -p "$T/bin" "$T/run"
# stub xrandr: --verbose prints state; anything else is a set call, logged and applied
cat > "$T/bin/xrandr" <<'EOF'
#!/bin/sh
S=$STUB/state
if [ "$1" = --verbose ]; then
  while read -r o m g; do echo "$o connected primary $g ($m) normal (normal left inverted right x axis y axis) 1600mm x 900mm"
    echo "  1920x1080 (0x43) 148.500MHz +HSync +VSync *current +preferred"; done < "$S"
  echo "HDMI-2 disconnected (normal left inverted right x axis y axis)"; exit 0; fi
echo "$*" >> "$STUB/xrandr.log"
[ -f "$STUB/fail" ] && exit 1
: > "$S.new"; set -- "$@"; o=; m=; p=
while [ $# -gt 0 ]; do case $1 in --output) o=$2; shift;; --mode) m=$2; shift;; --pos) p=$2; shift;; esac; shift; done
w=1920; h=1080; [ "$m" = 0x99 ] && { w=800; h=600; }
echo "$o $m ${w}x${h}+${p%x*}+${p#*x}" > "$S"
EOF
# stub pgrep/pkill: game and client presence from flag files
cat > "$T/bin/pgrep" <<'EOF'
#!/bin/sh
case "$*" in *reaper*) [ -f "$STUB/game" ];; *"-x steam"*) [ -f "$STUB/client" ];; *) exit 1;; esac
EOF
cat > "$T/bin/pkill" <<'EOF'
#!/bin/sh
echo "pkill $*" >> "$STUB/kill.log"; [ -f "$STUB/term-ignored" ] || rm -f "$STUB/client"
EOF
mkdir -p "$T/d"
cat > "$T/d/steam" <<'EOF'
#!/bin/sh
echo "steam $*" >> "$STUB/steam.log"; [ -f "$STUB/shutdown-ignored" ] || rm -f "$STUB/client"
EOF
chmod +x "$T/bin/"* "$T/d/steam"
export STUB=$T/run PATH="$T/bin:$PATH"
run(){ (export DISPLAY=:0; unset WAYLAND_DISPLAY; XDG_RUNTIME_DIR=$T/run; D=$T/d; T=$T; sleep(){ :; }; . "$F"; eval "$1"); }
reset(){ rm -f "$STUB"/*; echo "HDMI-1 0x43 1920x1080+0+0" > "$STUB/state"; }

reset
check "mode_get: name, mode id, geometry; skips disconnected" "[ \"\$(run mode_get)\" = 'HDMI-1 0x43 1920x1080+0+0' ]"
# title starts: mode saved; title switches to 800x600; title ends: mode put back
touch "$STUB/game"; run mode_watch
check "watch: mode saved when title starts" "[ \"\$(cat $STUB/steam-arm-display-mode)\" = 'HDMI-1 0x43 1920x1080+0+0' ]"
echo "HDMI-1 0x99 800x600+0+0" > "$STUB/state"; run mode_watch
check "watch: saved mode kept while title runs" "grep -q 0x43 $STUB/steam-arm-display-mode && [ ! -f $STUB/xrandr.log ]"
rm -f "$STUB/game"; run mode_watch
check "watch: mode put back after title ends" "grep -qx -- '--fb 1920x1080 --output HDMI-1 --mode 0x43 --pos 0x0' $STUB/xrandr.log && grep -q 0x43 $STUB/state"
check "watch: saved mode file removed" "[ ! -f $STUB/steam-arm-display-mode ]"
check "watch: restore logged" "grep -q 'display mode put back after game: HDMI-1 0x43' $T/steam-arm.log"
# unchanged mode: no xrandr call
reset; touch "$STUB/game"; run mode_watch; rm -f "$STUB/game"; run mode_watch
check "watch: no xrandr call when mode unchanged" "[ ! -f $STUB/xrandr.log ] && [ ! -f $STUB/steam-arm-display-mode ]"
# next title starts within the 2 s grace: no restore yet
reset; touch "$STUB/game"; run mode_watch; echo "HDMI-1 0x99 800x600+0+0" > "$STUB/state"
run 'sleep(){ touch $STUB/game; }; rm -f $STUB/game; mode_watch'
check "watch: no restore when next title starts in grace period" "[ ! -f $STUB/xrandr.log ] && [ -f $STUB/steam-arm-display-mode ]"
# Steam closes (or launcher gets SIGTERM) with a title gone: on_exit restores
reset; touch "$STUB/game"; run mode_watch; echo "HDMI-1 0x99 800x600+0+0" > "$STUB/state"; rm -f "$STUB/game"
run 'FEXWATCH=; PHYSXWATCH=; on_exit'
check "on_exit: restores when no title runs" "grep -q -- '--mode 0x43' $STUB/xrandr.log"
# on_exit of a second launcher while a title runs: no restore
reset; touch "$STUB/game"; run mode_watch; echo "HDMI-1 0x99 800x600+0+0" > "$STUB/state"
run 'FEXWATCH=; PHYSXWATCH=; on_exit'
check "on_exit: no restore while a title runs" "[ ! -f $STUB/xrandr.log ] && [ -f $STUB/steam-arm-display-mode ]"
# xrandr failure: warning logged, no loop
reset; touch "$STUB/game"; run mode_watch; echo "HDMI-1 0x99 800x600+0+0" > "$STUB/state"; rm -f "$STUB/game"; touch "$STUB/fail"
run mode_watch
check "restore failure logged" "grep -q 'display mode could not be put back' $T/steam-arm.log"
# Wayland session, missing xrandr, opt-out: nothing saved
reset; touch "$STUB/game"
run 'WAYLAND_DISPLAY=wayland-0; mode_watch'
check "wayland session: nothing saved" "[ ! -f $STUB/steam-arm-display-mode ]"
run 'STEAM_ARM_MODE_RESTORE=0; mode_watch'
check "STEAM_ARM_MODE_RESTORE=0: nothing saved" "[ ! -f $STUB/steam-arm-display-mode ]"
# two outputs, second at offset
rm -f "$STUB"/*; printf 'HDMI-1 0x43 1920x1080+0+0\nDP-1 0x50 2560x1440+1920+0\n' > "$STUB/state"
check "mode_get: two outputs" "[ \"\$(run mode_get | wc -l)\" = 2 ]"
run 'mode_get > $XDG_RUNTIME_DIR/steam-arm-display-mode'; echo "HDMI-1 0x99 800x600+0+0" > "$STUB/state"
run mode_restore
check "two outputs: fb covers both, each output set" "grep -qx -- '--fb 4480x1440 --output HDMI-1 --mode 0x43 --pos 0x0 --output DP-1 --mode 0x50 --pos 1920x0' $STUB/xrandr.log"
rm -f "$T/steam-arm.log"

# stop path
reset; touch "$STUB/client"
run 'stop_client'; rc=$?
check "stop: -shutdown works, no SIGTERM" "[ $rc = 0 ] && grep -qx 'steam -shutdown' $STUB/steam.log && [ ! -f $STUB/kill.log ]"
reset; touch "$STUB/client" "$STUB/shutdown-ignored"
run 'stop_client'; rc=$?
check "stop: ignored -shutdown -> SIGTERM to client" "[ $rc = 0 ] && grep -q 'pkill -TERM -u [0-9]* -x steam' $STUB/kill.log && grep -q 'did not act on -shutdown' $T/steam-arm.log"
reset; touch "$STUB/client" "$STUB/shutdown-ignored" "$STUB/term-ignored"
run 'stop_client'; rc=$?
check "stop: never SIGKILL, status 1 when client stays" "[ $rc = 1 ] && ! grep -q -- '-KILL\|-9' $STUB/kill.log && grep -q 'still running 30 s after SIGTERM' $T/steam-arm.log"
reset
run 'stop_client'; rc=$?
check "stop: no client -> nothing sent" "[ $rc = 0 ] && [ ! -f $STUB/steam.log ]"
check "launcher: --shutdown handled before watchers start" "awk '/--shutdown\) stop_client/{a=NR} /^FEXWATCH=\\\$!/{b=NR} END{exit !(a && b && a < b)}' $L"
check "launcher: interface switch uses stop_client" "grep -q 'stop_client || exit 1' $L && ! grep -q 'did not exit within 60 s' $L"
check "launcher: watcher loop calls mode_watch" "grep -q 'fex_check; mode_watch;' $L"
check "installer: x11-xserver-utils in host packages" "grep -q 'xdotool x11-xserver-utils' $INST"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
