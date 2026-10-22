#!/bin/bash
# Launcher side of frame pacing readout and still-working notice, from the launcher embedded in the installer under test
# (SARM_INST picks another): --perf-stats parsing, env var, help, game environment lines, foreground readout with Steam
# running, exit cleanup, still_watch start rule, still_run notices and terminal lines (helper and notice stubbed),
# report section, removal lists. Internal; not for release zips.
# shellcheck disable=SC1090,SC2034  # blocks sourced from extracts; variables read by them
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm32-perfl.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
check "L0 launcher parses (sh -n)" "sh -n $L"

# --- option parsing: block from PERF= line through the arg loop ---
A=$T/args.sh
awk '/^PERF=0; case/{f=1} f{print} f&&/^for a in "\$@"; do shift; if \[ "\$a" = --perf-stats \]/{exit}' "$L" > "$A"
pa_run(){ OUT=$(env -u STEAM_ARM_PERF_STATS ${E:+"$E"} sh -c 'f=$1; shift; . "$f"; echo "PERF=$PERF"; for a in "$@"; do echo "ARG=$a"; done' sh "$A" "$@"); }
E=; pa_run --desktop -silent
check "A1 no option: off, client options unchanged" "[ \"\$OUT\" = \$'PERF=0\nARG=--desktop\nARG=-silent' ]"
E=; pa_run --bigpicture --perf-stats "-x y"
check "A2 --perf-stats anywhere: on, taken out, other options and spaces kept" "[ \"\$OUT\" = \$'PERF=1\nARG=--bigpicture\nARG=-x y' ]"
E=STEAM_ARM_PERF_STATS=1; pa_run
check "A3 STEAM_ARM_PERF_STATS=1: on" "[ \"\$OUT\" = PERF=1 ]"
E=STEAM_ARM_PERF_STATS=0; pa_run
check "A4 STEAM_ARM_PERF_STATS=0: off" "[ \"\$OUT\" = PERF=0 ]"
l_help=$(grep -n '^  -h|--help|help)$' "$L" | cut -d: -f1); l_perf=$(grep -n '^PERF=0; case' "$L" | cut -d: -f1)
l_case=$(grep -n '^case "\${1:-}" in$' "$L" | sed -n 2p | cut -d: -f1)
check "A5 parsed after help and root check, before --shutdown/--open dispatch" "[ ${l_help:-0} -lt ${l_perf:-0} ] && [ ${l_perf:-0} -lt ${l_case:-0} ] && grep -n 'not as root' $L | cut -d: -f1 | awk -v p=${l_perf:-0} '\$1 < p' | grep -q ."
OUT=$(sh "$L" --help)
check "A6 --help lists --perf-stats" "grep -q '^  steam-arm --perf-stats  also print frame pacing of running game every 5 s' <<<\"\$OUT\""

# --- game environment block ---
G=$T/gfx.sh
awk '/^# Frame-time sources for games/{f=1} f{print} f&&/^  stop "Frame pacing readout needs Steam started/{getline; print; exit}' "$L" > "$G"
check "G0 block extracted (sources, gfx write, foreground path)" "grep -q 'GAMEENV0=\$GAMEENV' $G && grep -q 'entry.py gfx' $G && grep -q 'watch \"\$PERFDIR\" \"\$PERFLOG\" 5' $G"
cat > "$T/perf.py" <<'EOF'
import os, sys
open(os.environ["T"] + "/perf-calls.log", "a").write(" ".join(sys.argv[1:]) + "\n")
if sys.argv[1] == "env":
    if os.environ.get("NOSRC"):
        sys.exit(1)
    print("VK_LOADER_LAYERS_ENABLE=VK_LAYER_MESA_overlay\nGALLIUM_HUD=frametime")
EOF
cat > "$T/entry.py" <<'EOF'
import os, sys
open(os.environ["T"] + "/entry-calls.log", "a").write(" ".join(sys.argv[1:]) + "\n")
sys.exit(int(os.environ.get("GFX_RC", "0")))
EOF
sed -e "s#/usr/local/lib/steam-arm-perf.py#$T/perf.py#" -e "s#/usr/local/lib/steam-arm-entry.py#$T/entry.py#g" "$G" > "$G.2"
gr(){ rm -f "$T"/*-calls.log "$T/l.log"
  OUT=$( ( export T; ARMHOME=$T/arm S=$T/arm/Steam LOG=$T/l.log CLIENT=${CL:-arm64} GAMEENV=STEAM_ARM_VK_SPOOF=1 PERF=${PERF:-1}
    lwarn(){ echo "WARN $*"; }; llog(){ :; }; stop(){ echo "STOP $1"; exit 1; }
    client_running(){ [ "${RUNNING:-0}" = 1 ]; }
    pgrep(){ echo "pgrep $*" >> "$T/pgrep-calls.log"; [ "${WATCHING:-0}" = 1 ]; }
    . "$G.2"; echo "GAMEENV=$GAMEENV"; echo "GAMEENV0=$GAMEENV0"; echo "PERFDIR=$PERFDIR"; echo "GFXOK=$GFXOK"; echo REACHED ) 2>&1 ); }
gr
check "G1 on: helper env with client home cache folder; lines appended to game lines" "grep -qx \"env $T/arm/.cache/steam-arm/perf\" $T/perf-calls.log && grep -qx 'GAMEENV=STEAM_ARM_VK_SPOOF=1 VK_LOADER_LAYERS_ENABLE=VK_LAYER_MESA_overlay GALLIUM_HUD=frametime' <<<\"\$OUT\" && grep -qx 'GAMEENV0=STEAM_ARM_VK_SPOOF=1' <<<\"\$OUT\""
check "G1 native client: game environment file gets all lines" "grep -qx \"gfx $T/arm/Steam STEAM_ARM_VK_SPOOF=1 VK_LOADER_LAYERS_ENABLE=VK_LAYER_MESA_overlay GALLIUM_HUD=frametime\" $T/entry-calls.log && grep -q REACHED <<<\"\$OUT\""
PERF=0 gr
check "G2 off: helper not called, game lines unchanged" "[ ! -f $T/perf-calls.log ] && grep -qx 'GAMEENV=STEAM_ARM_VK_SPOOF=1' <<<\"\$OUT\" && grep -qx 'PERFDIR=' <<<\"\$OUT\""
NOSRC=1 gr
check "G3 no source: warning names Mesa layer, readout off, start continues" "grep -q '^WARN frame pacing readout off: no frame-time source' <<<\"\$OUT\" && grep -qx 'PERFDIR=' <<<\"\$OUT\" && grep -q REACHED <<<\"\$OUT\""
mkdir -p "$T/sp ace"; OUT=$( ( ARMHOME="$T/sp ace"; PERF=1; PERFDIR=; eval "$(sed -n '/^  PERFDIR="\$ARMHOME/,/^  case \$PERFDIR/p' "$G")"; echo "$PERFDIR" ) )
check "G4 client home with space: readout folder in /tmp per uid" "[ \"\$OUT\" = /tmp/steam-arm-perf-$(id -u) ]"
CL=x86 gr
check "G5 x86 client: lines exported (launcher environment)" "grep -q REACHED <<<\"\$OUT\" && grep -q 'export \"\$v\"' $G"
# foreground: watch helper stub returns at once; exit trap restores lines without readout
RUNNING=1 gr
check "G6 Steam running: foreground watch with folder and log, then exit (no client start)" "grep -qx \"watch $T/arm/.cache/steam-arm/perf $T/arm/.local/state/steam-arm/perf.log 5\" $T/perf-calls.log && ! grep -q REACHED <<<\"\$OUT\" && grep -q 'games started from now on, every 5 s; Ctrl+C stops it' <<<\"\$OUT\""
check "G6 exit puts game environment file back without readout lines" "[ \"\$(tail -1 $T/entry-calls.log)\" = \"gfx $T/arm/Steam STEAM_ARM_VK_SPOOF=1\" ]"
RUNNING=1 GFX_RC=1 gr
check "G7 Steam running, file not usable: stop names restart with option" "grep -q '^STOP Frame pacing readout needs Steam started with it' <<<\"\$OUT\" && ! grep -q '^watch' $T/perf-calls.log"

# start while Steam runs (steam:// link through xdg-open runs launcher): readout lines of another launcher stay
RUNNING=1 PERF=0 WATCHING=1 gr
check "G8 Steam running, readout watcher of this account: file left alone, no export, start continues" "[ ! -f $T/entry-calls.log ] && grep -qx 'GFXOK=1' <<<\"\$OUT\" && grep -q REACHED <<<\"\$OUT\" && grep -q -- \"-u \$(id -u) -f steam-arm-perf.py watch\" $T/pgrep-calls.log"
RUNNING=1 PERF=0 WATCHING=0 gr
check "G9 Steam running, no readout watcher: block rewritten without readout lines" "[ \"\$(cat $T/entry-calls.log)\" = \"gfx $T/arm/Steam STEAM_ARM_VK_SPOOF=1\" ]"
RUNNING=0 PERF=0 WATCHING=1 gr
check "G10 Steam not running (stale watcher): block rewritten" "[ \"\$(cat $T/entry-calls.log)\" = \"gfx $T/arm/Steam STEAM_ARM_VK_SPOOF=1\" ]"
CL=x86 RUNNING=1 PERF=0 WATCHING=1 gr
check "G11 x86 client: no file check, exports as before" "grep -qx 'GFXOK=0' <<<\"\$OUT\" && grep -q REACHED <<<\"\$OUT\""

# --- watcher start, exit cleanup ---
check "W1 1 s watcher: one game look per second shared by display mode restore and notice" "grep -q '^( n=0; while sleep 1; do entry_check; fex_check; GPID=; { mode_ok || \[ \"\$STILL\" = 1 \]; } && GPID=\$(game_pid)\$' $L && grep -q '^  mode_watch; still_watch;' $L"
check "W1 mode_watch uses that look (no second pgrep)" "awk '/^mode_watch\\(\\)\\{/{f=1} f&&/game_seen/{g=1} f&&/^}/{exit} END{exit !g}' $L"
check "W2 background readout started only when on, killed on exit" "grep -q '^  python3 \"\$PERFPY\" watch \"\$PERFDIR\" \"\$PERFLOG\" 5 </dev/null &\$' $L && grep -q 'kill \"\$PERFWATCH\"' $L"
check "W3 exit: on_exit calls perf_stop; readout lines out of file once client closed" "grep -q '^on_exit(){ perf_stop; ' $L && grep -q '\[ -n \"\$PERFDIR\" \] && \[ \"\$GFXOK\" = 1 \] && ! client_running && python3 \"\$ENTRYPY\" gfx \"\$S\" \$GAMEENV0' $L"

# --- still-working: settings, start rule, notices ---
SW=$T/still.sh
{ awk '/^game_up\(\)/{print} /^game_pid\(\)/{print} /^game_seen\(\)/{print}' "$L"
  awk '/^# Still-working notice: game start without frame/{f=1} f{print} f&&/^still_watch\(\)/{g=1} g&&/^}/{exit}' "$L"; } > "$SW"
check "N0 block extracted" "grep -q '^still_run()' $SW && grep -q '^still_watch()' $SW && grep -q '^STILL=auto' $SW"
st(){ OUT=$( ( unset STEAM_ARM_STILL_WORKING STEAM_ARM_STILL_AFTER; [ -n "$SN" ] && STILL_NOTICE=$SN; [ -n "$SE" ] && export STEAM_ARM_STILL_WORKING=$SE
  [ -n "$SA" ] && export STEAM_ARM_STILL_AFTER=$SA; . "$SW"; echo "$STILL $STILLAFTER" ) ); }
SN=; SE=; SA=; st; check "N1 absent key: auto, wait 20" "[ \"\$OUT\" = 'auto 20' ]"
SN=on; st; check "N1 STILL_NOTICE=on: 1" "[ \"\$OUT\" = '1 20' ]"
SN=off; st; check "N1 STILL_NOTICE=off: 0" "[ \"\$OUT\" = '0 20' ]"
SN=off SE=1 st; check "N1 STEAM_ARM_STILL_WORKING=1 wins over off" "[ \"\$OUT\" = '1 20' ]"
SN=on SE=0 st; check "N1 STEAM_ARM_STILL_WORKING=0 wins over on" "[ \"\$OUT\" = '0 20' ]"
SN=; SE=; SA=45 st; check "N1 STEAM_ARM_STILL_AFTER=45" "[ \"\$OUT\" = 'auto 45' ]"
SA=4x st; check "N1 bad wait value: 20" "[ \"\$OUT\" = 'auto 20' ]"
SA=
# still_watch with still_run stubbed: start once per game start, not while watcher alive, not when off or no game
sw(){ OUT=$( ( . "$SW"; STILL=$1; still_run(){ echo "RUN $1" >> "$T/sw.log"; sleep "${HOLD:-0}"; }
  rm -f "$T/sw.log"; for g in $2; do GPID=${g#-}; [ "$g" = - ] && GPID=; still_watch; sleep 0.2; done; wait; cat "$T/sw.log" 2>/dev/null ) ); }
sw auto "100 100 100"; check "N2 same game start seen each second: one watcher" "[ \"\$OUT\" = 'RUN 100' ]"
sw 1 "100 - 200"; check "N2 new game start: new watcher" "[ \"\$OUT\" = \$'RUN 100\nRUN 200' ]"
sw 0 "100 200"; check "N2 off: none" "[ -z \"\$OUT\" ]"
sw 1 "- -"; check "N2 no game: none" "[ -z \"\$OUT\" ]"
HOLD=2 sw 1 "100 200"; check "N2 watcher of earlier start still running: next waits" "[ \"\$OUT\" = 'RUN 100' ]"; HOLD=
# still_run: helper stub prints scripted lines; notice and notice_close logged
cat > "$T/still.py" <<'EOF'
import os, sys
open(os.environ["T"] + "/still-args.log", "w").write(" ".join(sys.argv[1:]) + "\n")
sys.stdout.write(os.environ.get("LINES", "").replace("\\n", "\n"))
EOF
sr(){ rm -f "$T/n.log" "$T/still-args.log"
  OUT=$( ( export T LINES; . "$SW"; PERFPY=$T/still.py; ARMHOME=$T/arm; PERFDIR=${PD:-}
    llog(){ echo "LOG $*" >> "$T/n.log"; }
    notice(){ echo "NOTICE $1|$2|$3|$4" >> "$T/n.log"; [ -n "$NOSVC" ] || echo 77; }
    notice_close(){ echo "CLOSE $1" >> "$T/n.log"; [ -z "$NOCLOSE" ]; }
    ${DISP:+export DISPLAY=:9}; [ -n "$DISP" ] || unset DISPLAY WAYLAND_DISPLAY
    still_run 4321 ) 2>&1 ); NL=$(cat "$T/n.log" 2>/dev/null); }
DISP=1 LINES='state loading 20\nstate shaders 24\nframe\n' sr
check "N3 helper args: reaper, wait, client home; no readout folder when off" "[ \"\$(cat $T/still-args.log)\" = \"still --reaper 4321 --after 20 --home $T/arm\" ]"
check "N3 first state: new notice (id 0), persistent, title names game start" "grep -qx 'NOTICE 0|Steam ARM: game still starting|No frame for 20 s: loading (game busy on CPU or disk).|0' <<<\"\$NL\""
check "N3 state change: same notice replaced (id 77), shaders text" "grep -q '^NOTICE 77|Steam ARM: game still starting|No frame for 24 s: compiling shaders' <<<\"\$NL\""
check "N3 first frame: notice closed, log lines, no terminal line with notice service" "grep -qx 'CLOSE 77' <<<\"\$NL\" && grep -q '^LOG still-working: loading after 20 s (game start 4321)' <<<\"\$NL\" && grep -q '^LOG still-working: frame (game start 4321)' <<<\"\$NL\" && [ -z \"\$OUT\" ]"
DISP=1 PD=$T/pf LINES='frame\n' sr
check "N4 frame before any state: nothing shown, nothing logged; readout folder passed" "[ -z \"\$NL\" ] && [ -z \"\$OUT\" ] && grep -q -- \"--perf $T/pf\" $T/still-args.log"
DISP='' LINES='state stuck 31\ngone\n' sr
check "N5 headless: terminal lines for state and end, no notice" "grep -q '^steam-arm: No frame for 31 s: game idle (no CPU use, or waiting on disk, for 10 s or more): own launcher or settings window waiting for input, or not responding' <<<\"\$OUT\" && grep -qx 'steam-arm: Game ended.' <<<\"\$OUT\" && ! grep -q NOTICE <<<\"\$NL\""
DISP=1 NOSVC=1 LINES='state loading 20\nnosignal\n' sr
check "N6 display without notice service: terminal lines" "grep -q '^steam-arm: No frame for 20 s: loading' <<<\"\$OUT\" && grep -qx 'steam-arm: No frame signal; notice closed.' <<<\"\$OUT\""
DISP=1 NOCLOSE=1 LINES='state loading 20\nframe\n' sr
check "N7 no close call (notify-send): short replacement notice 'Game is drawing.'" "grep -qx 'NOTICE 77|Steam ARM|Game is drawing.|3000' <<<\"\$NL\""
DISP=1 LINES='nosignal fdinfo\n' sr
check "N8 kernel without per-process GPU time: no notice, no terminal line, one log line" "[ \"\$NL\" = 'LOG still-working: off for game start 4321 (kernel reports no per-process GPU time)' ] && [ -z \"\$OUT\" ]"
DISP=1 LINES='nosignal\n' sr
check "N8 plain nosignal before any state: nothing logged" "[ -z \"\$NL\" ] && [ -z \"\$OUT\" ]"

# --- report and removal ---
check "R1 hardware report: Frame pacing section from client home perf.log, last 12" "grep -q 'echo \"== Frame pacing (steam-arm --perf-stats, last 12 lines)\"' $INST && grep -q 'f=\"\$(arm_home)/.local/state/steam-arm/perf.log\"' $INST && grep -q 'tail -12 \"\$f\"' $INST"
RM=$(awk '/^  rm -f \/usr\/local\/bin\/steam-arm \/usr\/local\/bin\/steam-arm-remoteplay/{f=1} f{print} f && !/\\$/{exit}' "$INST")
OUT=$RM
check "R2 --remove deletes steam-arm-perf.py; owned paths list it (snapshots)" "grep -q '/usr/local/lib/steam-arm-perf.py' <<<\"\$RM\" && awk '/^sa_owned_paths\\(\\)/{f=1} f&&/steam-arm-perf.py/{g=1} f&&/^}/{exit} END{exit !g}' $INST"
check "R3 game environment own names list readout variables" "grep -q '\"VK_LAYER_MESA_OVERLAY_CONFIG\", \"GALLIUM_HUD\", \"GALLIUM_HUD_PERIOD\", \"GALLIUM_HUD_VISIBLE\", \"GALLIUM_HUD_DUMP_DIR\")' $INST"

echo "$pass PASS, $fail FAIL"
[ "$fail" = 0 ]
