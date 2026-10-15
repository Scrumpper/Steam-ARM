#!/bin/bash
# 2.3 caches group, command line: steam-arm-config cache / cache list / cache clear, profile key diskcache, usage,
# hardware report line. Menu copy from ~/.cache/sarm<NN>-work (SARM_CFG / SARM_INST pick others) run through the
# config-ui harness on its fake tree; pgrep stubbed (game running or not). Internal.
. "$(dirname "$0")/paths.sh"
T0=$SARM_TESTS/config-ui
INST=$SARM_INST
CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm232-cache.XXXXXX); trap 'rm -rf "$T"' EXIT
# private fake tree and menu copy: concurrent runs do not share them
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
R=$SARM_UI_FAKE
bash "$T0/mkfake.sh" >/dev/null
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -n 8; fail=$((fail + 1)); fi; }
sed -e "s#^APP=.*#APP=\"$CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"
mkdir -p "$T/bin"
printf '#!/bin/sh\ncase "$*" in *SteamLaunch*) [ "${FAKE_GAME:-0}" = 1 ];; *) exit 1;; esac\n' > "$T/bin/pgrep"
chmod 755 "$T/bin/pgrep"
cli(){ OUT=$(PATH="$T/bin:$PATH" bash "$T/harness.sh" "$@" 2>&1); RC=$?; }

H=$R/home/tester; A=$H/.local/share/steam-arm; S=$A/.local/share/Steam; L2="$R/media/Game Drive/SteamLibrary"
blob(){ mkdir -p "$1"; head -c "$2" /dev/urandom > "$1/${3:-cache.foz}"; }
caches(){
  blob "$S/steamapps/shadercache/312520/fex-emu" 1048576
  blob "$S/steamapps/shadercache/312520/fozpipelinesv6" 65536 steamapp.foz
  blob "$S/steamapps/shadercache/312520/mesa_shader_cache_sf" 65536 index
  blob "$L2/steamapps/shadercache/1036240/fex-emu" 2097152
  blob "$S/steamapps/compatdata/219150/pfx/drive_c/users/steamuser/AppData/Local/fex-emu" 524288
  blob "$L2/steamapps/compatdata/400/pfx/drive_c/users/steamuser/AppData/Roaming/fex-emu" 262144
  blob "$A/.cache/fex-emu" 131072
  blob "$T/outside/fex-emu" 65536 keep.foz
  mkdir -p "$S/steamapps/shadercache"; ln -sfn "$T/outside" "$S/steamapps/shadercache/9001"
  blob "$T/outside2" 65536 keep.foz
  mkdir -p "$S/steamapps/shadercache/9002"; ln -sfn "$T/outside2" "$S/steamapps/shadercache/9002/fex-emu"
}
caches

# ---------- sizes ----------
cli cache list
LIST=$OUT
row(){ awk -F'\t' -v id="$1" -v k="$2" '$1 == id && $2 == k { print $3 }' <<<"$LIST"; }
check "cache list: exit 0" "[ $RC = 0 ]"
check "cache list: Linux games in library 1 and library 2" "[ -n \"\$(row 312520 linux)\" ] && [ -n \"\$(row 1036240 linux)\" ]"
check "cache list: Proton prefixes, AppData/Local and AppData/Roaming" "[ -n \"\$(row 219150 windows)\" ] && [ -n \"\$(row 400 windows)\" ]"
check "cache list: shared folder of client" "[ -n \"\$(row - shared)\" ] && grep -q \"$A/.cache/fex-emu\$\" <<<\"\$LIST\""
check "cache list: linked folders (9001 link, 9002/fex-emu link) not listed" "! grep -qE '^900[12]\\b' <<<\"\$LIST\" && [ \$(grep -c . <<<\"\$LIST\") = 5 ]"
check "cache list: size of one folder equals du -sk" "[ \"\$(row 312520 linux)\" = \"\$(du -sk \"$S/steamapps/shadercache/312520/fex-emu\" | cut -f1)\" ]"
check "cache list: fozpipelinesv6 and mesa cache not listed" "[ -n \"\$(row 312520 linux)\" ] && ! grep -qE 'fozpipelines|mesa_shader' <<<\"\$LIST\""
cli cache
check "cache: summary rows, counts per kind" "[ $RC = 0 ] && grep -qE '^FEX code cache, Linux games +[0-9.]+M +2 games\$' <<<\"\$OUT\" && grep -qE '^FEX code cache, Windows games +[0-9.]+K +2 games \\(Proton prefixes\\)\$' <<<\"\$OUT\" && grep -qE '^FEX code cache, shared folder +128K\$' <<<\"\$OUT\""
check "cache: Steam shader cache row read only, FEX caches not counted twice" "grep -qE '^Steam shader cache +[0-9.]+K +Steam.s own, not cleared here\$' <<<\"\$OUT\""
check "cache: per game list with game name, largest first" "grep -A1 '^Per game, largest first:' <<<\"\$OUT\" | grep -qE 'linux +1036240 +Jelly Brawl'"
check "cache: diskcache=on count and FEX tool line" "grep -qx 'Code cache on (diskcache=on): 0 games. FEX tool: FEX-2609.1.' <<<\"\$OUT\""

# ---------- clear ----------
FAKE_GAME=1 cli cache clear all; OUT1=$OUT; RC1=$RC
check "clear while game runs: exit 1, refused" "[ $RC1 = 1 ] && grep -q 'a game is running in Steam ARM' <<<\"\$OUT1\" && [ -d \"$S/steamapps/shadercache/312520/fex-emu\" ]"
cli cache clear abc
check "clear abc: usage, exit 2" "[ $RC = 2 ] && grep -q 'usage: steam-arm-config cache' <<<\"\$OUT\""
cli cache clear
check "clear without target: exit 2" "[ $RC = 2 ] && grep -q 'usage: steam-arm-config cache' <<<\"\$OUT\""
cli cache bogus
check "cache bogus: exit 2" "[ $RC = 2 ] && grep -q 'usage: steam-arm-config cache' <<<\"\$OUT\""
cli cache clear 312520
check "clear one game: only that game's fex-emu removed" "[ $RC = 0 ] && [ ! -e \"$S/steamapps/shadercache/312520/fex-emu\" ] && [ -d \"$L2/steamapps/shadercache/1036240/fex-emu\" ]"
check "clear one game: fozpipelinesv6 and mesa cache stay" "[ ! -e \"$S/steamapps/shadercache/312520/fex-emu\" ] && [ -f \"$S/steamapps/shadercache/312520/fozpipelinesv6/steamapp.foz\" ] && [ -f \"$S/steamapps/shadercache/312520/mesa_shader_cache_sf/index\" ]"
check "clear one game: freed message" "grep -qE '^Freed [0-9.]+M\\. Folders deleted: 1\\. Steam shader caches stay\\.\$' <<<\"\$OUT\""
cli cache clear 312520
check "clear same game again: nothing found, exit 0" "[ $RC = 0 ] && grep -qx 'No FEX code caches found.' <<<\"\$OUT\""
cli cache clear all
check "clear all: every real fex-emu removed (both libraries, Local, Roaming, shared)" "[ $RC = 0 ] && [ ! -e \"$L2/steamapps/shadercache/1036240/fex-emu\" ] && [ ! -e \"$S/steamapps/compatdata/219150/pfx/drive_c/users/steamuser/AppData/Local/fex-emu\" ] && [ ! -e \"$L2/steamapps/compatdata/400/pfx/drive_c/users/steamuser/AppData/Roaming/fex-emu\" ] && [ ! -e \"$A/.cache/fex-emu\" ]"
check "clear all: link targets untouched, links kept" "[ ! -e \"$L2/steamapps/shadercache/1036240/fex-emu\" ] && [ -f \"$T/outside/fex-emu/keep.foz\" ] && [ -f \"$T/outside2/keep.foz\" ] && [ -L \"$S/steamapps/shadercache/9001\" ] && [ -L \"$S/steamapps/shadercache/9002/fex-emu\" ]"
check "clear all: Proton prefix itself stays" "[ ! -e \"$S/steamapps/compatdata/219150/pfx/drive_c/users/steamuser/AppData/Local/fex-emu\" ] && [ -d \"$S/steamapps/compatdata/219150/pfx/drive_c/users/steamuser/AppData/Local\" ]"
cli cache
check "empty tree: no caches line, exit 0" "[ $RC = 0 ] && grep -qx 'No FEX code caches found.' <<<\"\$OUT\""
mkdir -p "$S/steamapps/common/x/fex-emu"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; for p in '$S/steamapps/shadercache/312520' '$T/outside/fex-emu' '$S/steamapps/shadercache/9002/fex-emu' '$S/steamapps/common/x/fex-emu'; do cache_path_ok \"\$p\" && echo ok \"\$p\"; done" 2>&1)
check "cache_path_ok refuses non-fex-emu, outside, link and common/ paths" "[ -z \"\$OUT\" ]"

# ---------- profile key ----------
TC=$R/etc/steam-arm/titles.conf
cli profile 100 diskcache=on
check "profile 100 diskcache=on accepted" "[ $RC = 0 ] && grep -qE '^100 .*diskcache=on' '$TC'"
cli cache
check "diskcache=on counted in summary" "grep -q 'Code cache on (diskcache=on): 1 game\\.' <<<\"\$OUT\""
cli profile 100 diskcache=maybe
check "profile diskcache=maybe refused, exit 2" "[ $RC = 2 ] && grep -q 'bad setting: diskcache=maybe' <<<\"\$OUT\""
cli profile 100 diskcache=off
check "profile diskcache=off accepted" "[ $RC = 0 ] && grep -qE '^100 .*diskcache=off' '$TC'"
cli profile 100 diskcache=
check "profile diskcache= removes key" "[ $RC = 0 ] && ! grep -q 'diskcache' '$TC'"
cli profile 100 diskcache=on mangohud=on
HAD=$(grep -c '^100 .*diskcache=on' "$TC")
cli profile 100 --clear
check "profile --clear drops diskcache" "[ $HAD = 1 ] && [ $RC = 0 ] && ! grep -qE '^100 ' '$TC'"

# ---------- usage, report, files ----------
OUT=$(bash "$CFG" --help)
check "--help lists cache commands" "grep -q '^  cache  ' <<<\"\$OUT\" && grep -q '^  cache clear all|<appid>' <<<\"\$OUT\" && grep -q '^  cache list' <<<\"\$OUT\""
check "--help lists diskcache profile key" "grep -q 'multiblock, diskcache);' <<<\"\$OUT\""
caches; cli profile 100 diskcache=on
OUT=$(PATH="$T/bin:$PATH" bash -c ". $T/harness.sh --help >/dev/null; detect_raw(){ :; }; report_text" 2>&1 | grep '^FEX code cache')
check "hardware report: one line, count and total, no names or paths" "grep -qE '^FEX code cache on for 1 game, [0-9.]+M in caches\$' <<<\"\$OUT\""
check "installer bash -n, settings menu bash -n" "bash -n '$INST' && bash -n '$CFG'"
check "embedded settings menu identical" "awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f' '$INST' | cmp -s - '$CFG'"
check "titles.conf template names diskcache" "grep -q '^#   diskcache=on|off (FEX code cache for the title' '$INST'"

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
