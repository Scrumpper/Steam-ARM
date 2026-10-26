#!/bin/bash
# 3.1 Valve Frame runtime, menu and launcher side: Graphics item 6 and screen, CLI frame-runtime, --help, backup key and
# restore check, Route per game note, compat clear drops record, run report row, launcher block (stand-in helper),
# removal lists, 3.0 setup and menu with FRAME_RUNTIME (rollback). Settings menu sourced through config-ui/harness.sh
# (fake tree); screens stubbed (answers from a queue file). Internal; not for release zips.
. "$(dirname "$0")/paths.sh"
T0=$SARM_TESTS/config-ui
CFG=$SARM_CFG INST=$SARM_INST
T=$(mktemp -d /tmp/sarm31-frm.XXXXXX); trap 'rm -rf "$T"' EXIT
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
R=$SARM_UI_FAKE
bash "$T0/mkfake.sh" >/dev/null
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; sed 's/^/     /' <<<"$OUT" | tail -n 8; fail=$((fail + 1)); fi; }
sed -e "s#^APP=.*#APP=\"$CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"
export Q=$T/q LOG=$T/ui.log
cat > "$T/stubs.sh" <<'S'
nxt(){ A=$(head -n 1 "$Q"); sed -i 1d "$Q"; }
ui_menu(){ printf 'MENU %s|%s|%s\n' "$1" "$2" "${*:3}" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; echo "$A"; }
ui_msg(){ printf 'MSG %s|%s\n' "$1" "$2" >> "$LOG"; }
ui_info(){ :; }
ui_yesno(){ printf 'YESNO %s|%s|%s\n' "$1" "$2" "${3:-}" >> "$LOG"; nxt; [ "$A" = yes ]; }
S
# helper stand-in: applied/list/drop per appid from $T/fr-applied; calls logged
cat > "$T/fr.py" <<P
import sys
open("$T/fr-calls.log", "a").write(" ".join(sys.argv[1:]) + "\n")
rows = [l.rstrip("\n").split("\t") for l in open("$T/fr-applied")] if __import__("os").path.exists("$T/fr-applied") else []
if sys.argv[1] == "applied":
    for r in rows:
        if r[0] == sys.argv[3]:
            print("\t".join(r[1:]))
elif sys.argv[1] == "list":
    print("frame-runtime\toff")
    for r in rows:
        print("app\t%s\tapplied\t%s\t%s" % (r[0], r[1], r[2]))
elif sys.argv[1] == "drop":
    print("frame-runtime: record of app %s removed" % sys.argv[3])
P
printf '400\tproton-stable\tproton_11-arm64\tProton ARM64 stable (proton_11-arm64)\n' > "$T/fr-applied"
echo "SA_FRAMERT_PY=$T/fr.py" > "$T/rstubs.sh"
ui(){ local s=$1; shift; : > "$LOG"; rm -f "$T/fr-calls.log"; printf '%s\n' "$@" > "$Q"
  bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; . $T/rstubs.sh; $s" >/dev/null 2>"$T/err"; RC=$?; OUT=$(cat "$LOG" "$T/err"); }
rcli(){ rm -f "$T/fr-calls.log"; OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/rstubs.sh; main $*" 2>&1); RC=$?; }
CONF=$R/etc/steam-arm/steam-arm.conf
cp "$CONF" "$T/conf.orig"
fresh(){ cp "$T/conf.orig" "$CONF"; printf '%s\n' "$@" >> "$CONF"; }
key(){ sed -n "s/^$1=//p" "$CONF"; }
RS=$R/home/tester/.local/share/steam-arm/.local/share/Steam

# ---------- menu ----------
fresh; ui menu_graphics BACK
check "M1 Graphics: item 6 Valve Frame runtime (now: off), absent key = off" "grep -q '^MENU Graphics|.* 5 Still-working notice (now: auto) 6 Valve Frame runtime (now: off)\$' <<<\"\$OUT\""
fresh FRAME_RUNTIME=auto; ui menu_graphics BACK
check "M1 FRAME_RUNTIME=auto -> (now: auto); unknown value -> off" "grep -q ' 6 Valve Frame runtime (now: auto)\$' <<<\"\$OUT\" && [ \"\$(bash -c \". $T/harness.sh --help >/dev/null; conf_get(){ echo on; }; frame_runtime\")\" = off ]"
fresh; ui menu_graphics 6 BACK BACK
check "M2 item 6 opens screen: state, four runtime lines, own choices kept, Turn on" "grep -q '^YESNO Valve Frame runtime|Valve Frame runtime: off' <<<\"\$OUT\" && grep -qx '  proton-stable: Proton ARM64 stable' <<<\"\$OUT\" && grep -qx '  proton-experimental: Proton ARM64 experimental' <<<\"\$OUT\" && grep -qx '  native: Linux build' <<<\"\$OUT\" && grep -qx '  lepton-stable: unchanged (no Lepton here)' <<<\"\$OUT\" && grep -q 'GE-Proton and own choices kept' <<<\"\$OUT\" && grep -q 'Route per game shows and undoes each.|Turn on\$' <<<\"\$OUT\""
check "M2 Back: key not written, Graphics again" "[ -z \"\$(key FRAME_RUNTIME)\" ] && [ \$(grep -c '^MENU Graphics' <<<\"\$OUT\") = 2 ]"
check "M2 screen text fits 66 columns" "! sed -n '/^YESNO Valve Frame runtime/,/^MENU Graphics/p' <<<\"\$OUT\" | grep -v '^MENU' | sed 's/^YESNO [^|]*|//; s/|Turn on\$//' | awk 'length > 66' | grep -q ."
fresh; ui graphics_frame_runtime yes
check "M3 Turn on: FRAME_RUNTIME=auto written, message" "[ \"\$(key FRAME_RUNTIME)\" = auto ] && grep -q '^MSG Graphics|Valve Frame runtime: auto. Applies at next start of Steam ARM.' <<<\"\$OUT\""
fresh FRAME_RUNTIME=auto; ui graphics_frame_runtime yes
check "M3 Turn off from auto: FRAME_RUNTIME=off, titles set kept" "[ \"\$(key FRAME_RUNTIME)\" = off ] && grep -q '^YESNO Valve Frame runtime|Valve Frame runtime: auto' <<<\"\$OUT\" && grep -q 'Turning off keeps titles already set.|Turn off\$' <<<\"\$OUT\" && grep -q 'Titles already set keep their tool' <<<\"\$OUT\""
fresh; ui graphics_game 400 BACK
check "M4 Route per game, title set from recommendation: note names runtime and undo" "grep -q '^Set from Valve Frame recommendation (proton-stable). Automatic lets it apply again.' <<<\"\$OUT\" && grep -q '^applied .* 400\$' $T/fr-calls.log"

# ---------- CLI ----------
fresh; rcli frame-runtime auto
check "C1 frame-runtime auto: key auto" "[ $RC = 0 ] && [ \"\$(key FRAME_RUNTIME)\" = auto ] && grep -qx 'Valve Frame runtime: auto (from next start of Steam ARM)' <<<\"\$OUT\""
rcli frame-runtime off
check "C1 frame-runtime off: key off" "[ $RC = 0 ] && [ \"\$(key FRAME_RUNTIME)\" = off ]"
rcli frame-runtime
check "C2 no value: state and titles from helper list" "[ $RC = 0 ] && grep -qx 'Valve Frame runtime: off' <<<\"\$OUT\" && grep -qx 'app 400 applied: Valve runtime proton-stable, tool proton_11-arm64' <<<\"\$OUT\""
rcli frame-runtime on
check "C3 bad value: usage, exit 2, key unchanged" "[ $RC = 2 ] && grep -q 'usage: steam-arm-config frame-runtime \\[auto|off\\]' <<<\"\$OUT\" && [ \"\$(key FRAME_RUNTIME)\" = off ]"
printf '#!/bin/sh\necho "compatmap $*"\n' > "$R/bin/steam-arm-compatmap"; chmod 755 "$R/bin/steam-arm-compatmap"
rcli compat 400 clear
check "C4 compat clear on title set from recommendation: mapping removed, record dropped" "[ $RC = 0 ] && grep -q 'compatmap 400 --remove' <<<\"\$OUT\" && grep -q '^drop .* 400\$' $T/fr-calls.log"
rcli compat 312520 clear
check "C4 compat clear on other title: record left alone" "[ $RC = 0 ] && grep -q 'compatmap 312520 --remove' <<<\"\$OUT\" && ! grep -q '^drop' $T/fr-calls.log"
OUT=$(bash "$CFG" --help)
check "C5 --help lists frame-runtime and FRAME_RUNTIME key" "grep -q '^  frame-runtime \\[auto|off\\]' <<<\"\$OUT\" && grep -q 'FRAME_RUNTIME=auto|off (absent: off)' <<<\"\$OUT\""
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; echo \"\$SA_BK_KEYS\"; for v in auto off '' on; do rs_valid FRAME_RUNTIME \"\$v\" && echo \"ok:\$v\" || echo \"bad:\$v\"; done" 2>&1)
check "C6 backup keys carry FRAME_RUNTIME; restore accepts auto, off, empty only" "grep -qE ' FRAME_RUNTIME( |\$)' <<<\"\$OUT\" && [ \"\$(grep -c '^ok:' <<<\"\$OUT\")\" = 3 ] && grep -qx 'bad:on' <<<\"\$OUT\""

# ---------- run report ----------
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/rstubs.sh; SA_APPINFO_PY=$T/none.py; rr_upstream 400 unity" 2>&1)
check "R1 Upstream fields: Runtime applied row when set from recommendation" "grep -qx 'Runtime applied Proton ARM64 stable (proton_11-arm64) (Valve Frame recommendation)' <<<\"\$OUT\""
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/rstubs.sh; SA_APPINFO_PY=$T/none.py; rr_upstream 312520 unity" 2>&1)
check "R2 title not set from recommendation: no Runtime applied row" "! grep -q '^Runtime applied' <<<\"\$OUT\" && grep -q '^Proton ' <<<\"\$OUT\""
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; SA_FRAMERT_PY=$T/none.py; SA_APPINFO_PY=$T/none.py; rr_upstream 400 unity" 2>&1)
check "R3 helper missing: no Runtime applied row, report fields kept" "! grep -q '^Runtime applied' <<<\"\$OUT\" && grep -q '^Proton ' <<<\"\$OUT\""

# ---------- launcher block ----------
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
B=$T/fr-block.sh
awk '/^# Valve Frame runtime \(steam-arm-frameruntime.py\)/{f=1} f && /^if \[ "\$CLIENT" = x86 \]; then cd "\$S" \|\| exit 1; else cd "\$D" \|\| exit 1; fi$/{exit} f' "$L" \
  | sed "s#/usr/local/lib/steam-arm-frameruntime.py#$T/frl.py#" > "$B"
OUT=$(cat "$B")
l_ab=$(grep -n '^# Automatic Windows build (steam-arm-autobuild.py)' "$L" | cut -d: -f1); l_fr=$(grep -n '^# Valve Frame runtime' "$L" | cut -d: -f1)
l_cd=$(grep -n '^if \[ "\$CLIENT" = x86 \]; then cd "\$S" || exit 1; else cd "\$D" || exit 1; fi$' "$L" | cut -d: -f1)
check "L1 block after automatic Windows build, before client start; helper call bounded, apply <client>" "[ -n \"$l_fr\" ] && [ ${l_ab:-0} -lt ${l_fr:-0} ] && [ ${l_fr:-0} -lt ${l_cd:-0} ] && grep -q 'timeout 30 python3 \"\$FR\" apply \"\$S\"' $B"
cat > "$T/frl.py" <<'P'
import os, sys
open(os.environ["T"] + "/calls.log", "a").write(" ".join(sys.argv[1:]) + "\n")
sys.stdout.write(os.environ.get("FR_OUT", "").replace("\\n", "\n"))
P
frun(){ rm -f "$T/calls.log" "$T/notes" "$T/l.log"
  ( export T; S=$T/Steam LOG=$T/l.log
    client_running(){ [ "${RUNNING:-0}" = 1 ]; }
    lnote(){ echo "$1|$2" >> "$T/notes"; }
    . "$B"; echo REACHED ) 2>&1; }
SET1='frame-runtime: app 100: Proton ARM64 stable (proton_11-arm64) set (Valve Frame recommendation proton-stable). Undo: steam-arm-config, Graphics > Route per game'
SET2='frame-runtime: app 300: Linux build (steamlinuxruntime) set (Valve Frame recommendation native). Undo: steam-arm-config, Graphics > Route per game'
LEP='frame-runtime: app 400: Valve Frame runtime lepton-stable; Lepton not available here, tool unchanged'
OUT=$(FR_OUT="$SET1\n$SET2\n$LEP\n" frun)
check "L2 FRAME_RUNTIME absent: helper not called, start continues" "[ ! -f $T/calls.log ] && grep -q REACHED <<<\"\$OUT\""
OUT=$(FRAME_RUNTIME=off FR_OUT="$SET1\n" frun)
check "L2 FRAME_RUNTIME=off: helper not called" "[ ! -f $T/calls.log ]"
OUT=$(FRAME_RUNTIME=auto FR_OUT="$SET1\n$SET2\n$LEP\n" frun)
check "L3 auto: helper called as apply <client>, three lines dated in log" "[ \"\$(cat $T/calls.log)\" = \"apply $T/Steam\" ] && [ \$(grep -cE '^[0-9-]{10} [0-9:]{8} frame-runtime: app ' $T/l.log) = 3 ]"
check "L3 one desktop notice counting 2 set titles" "[ \$(grep -c . $T/notes) = 1 ] && grep -qx 'Compatibility tool set for 2 game(s) from Valve Frame recommendation. Change: Steam ARM Settings > Graphics > Route per game.|Steam ARM: Frame runtime set' $T/notes && grep -q REACHED <<<\"\$OUT\""
OUT=$(FRAME_RUNTIME=auto FR_OUT="$LEP\n" frun)
check "L4 Lepton line only: logged, no notice" "grep -q 'lepton-stable' $T/l.log && [ ! -f $T/notes ]"
OUT=$(RUNNING=1 FRAME_RUNTIME=auto FR_OUT="$SET1\n" frun)
check "L5 client running: helper not called" "[ ! -f $T/calls.log ] && grep -q REACHED <<<\"\$OUT\""
mv "$T/frl.py" "$T/frl.off"
OUT=$(FRAME_RUNTIME=auto FR_OUT="$SET1\n" frun)
check "L6 helper file missing: nothing logged, start continues" "[ ! -s $T/l.log ] && grep -q REACHED <<<\"\$OUT\""
check "L7 launcher parses (sh -n)" "sh -n $L"

# ---------- removal, owned paths ----------
RM=$(awk '/^  rm -f \/usr\/local\/bin\/steam-arm \/usr\/local\/bin\/steam-arm-remoteplay/{f=1} f{print} f && !/\\$/{exit}' "$INST")
OWN=$(awk '/^sa_owned_paths\(\)\{/{f=1} f{print} f && /^}/{exit}' "$INST")
check "X1 --remove and owned paths name steam-arm-frameruntime.py; setup writes it 644" "grep -q '/usr/local/lib/steam-arm-frameruntime.py' <<<\"\$RM\" && grep -q '/usr/local/lib/steam-arm-frameruntime.py' <<<\"\$OWN\" && grep -qx 'chmod 644 /usr/local/lib/steam-arm-frameruntime.py' $INST"

# ---------- rollback: 3.0 keeps key, 3.0 menu skips it on restore ----------
OLD30=$(sarm_old 3.0)
if [ -n "$OLD30" ]; then
  fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }
  printf 'VERSION=3.1\nFRAME_RUNTIME=auto\n' > "$T/c.conf"
  OUT=$( { fn conf_set "$OLD30"; echo 'die(){ exit 1; }'; echo "CONF=$T/c.conf; conf_set VERSION 3.0; conf_set GFX_DEFAULT a"; } | bash 2>&1; cat "$T/c.conf")
  check "B1 3.0 setup keeps FRAME_RUNTIME in settings file (conf_set)" "grep -qx FRAME_RUNTIME=auto <<<\"\$OUT\" && grep -qx VERSION=3.0 <<<\"\$OUT\""
  F=$T/fk; export SARM_UI_FAKE=$F SARM_UI_COPY=$T/fk-copy.sh
  bash "$T0/mkfake.sh" >/dev/null
  echo FRAME_RUNTIME=auto >> "$F/etc/steam-arm/steam-arm.conf"
  mkdir -p "$T/bk"; OUT=$(bash "$T/harness.sh" backup "$T/bk" --parts setup 2>&1); BF=$(sed -n 's/^Saved to //p' <<<"$OUT")
  check "B2 3.1 backup holds FRAME_RUNTIME" "[ -f \"\$BF\" ] && tar -xzOf \"\$BF\" steam-arm-settings/system/steam-arm.conf | grep -qx FRAME_RUNTIME=auto"
  sed -i '/^FRAME_RUNTIME=/d' "$F/etc/steam-arm/steam-arm.conf"
  mkdir -p "$T/m30"; awk "/^menu_app\\(\\)\\{ cat <<'STEAMARMCONFIG'\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f" "$OLD30" > "$T/m30/steam-arm-config"
  OUT=$(SARM_CFG=$T/m30/steam-arm-config SARM_UI_COPY=$T/fk-copy30.sh bash "$T0/harness.sh" restore "$BF" --yes 2>&1); RC=$?
  check "B3 3.0 menu restores 3.1 backup, FRAME_RUNTIME skipped" "[ $RC = 0 ] && grep -q 'Settings restored.' <<<\"\$OUT\" && ! grep -q '^FRAME_RUNTIME=' $F/etc/steam-arm/steam-arm.conf"
  OUT=$(bash "$T/harness.sh" restore "$BF" --yes 2>&1); RC=$?
  check "B4 3.1 menu restores FRAME_RUNTIME" "[ $RC = 0 ] && grep -qx FRAME_RUNTIME=auto $F/etc/steam-arm/steam-arm.conf"
else
  echo "SKIP B1-B4 rollback cases: release 3.0 not available"
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
