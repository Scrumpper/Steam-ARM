#!/bin/bash
# 3.1 report "== Valve tools" block: vt_build reads appmanifest_<appid>.acf in every library (present, absent, malformed),
# valve_tools rows for ARM64 and x86 clients, block in report_text. Settings menu sourced on the config-ui fake tree
# (SARM_CFG picks another menu). Internal; not for release zips.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm31-status.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
has(){ grep -qF -- "$1" <<<"$OUT"; }

check "V1 installer and menu parse; embedded menu equals menu file" \
  "bash -n '$INST' && bash -n '$CFG' && awk \"/^menu_app\\\\(\\\\)\\\\{ cat <<'STEAMARMCONFIG'\\\$/{f=1;next} /^STEAMARMCONFIG\\\$/{f=0} f\" '$INST' | cmp -s - '$CFG'"
lno(){ grep -n -- "$1" "$CFG" | cut -d: -f1 | paste -sd' ' -; }
A=$(lno '^  echo "== Versions"$'); B=$(lno '^  echo "== Valve tools"; valve_tools$'); C=$(lno '^  echo "== Notes"; info_notes$')
check "V2 report_text prints the block once, between Versions and Notes" "[ -n '$A' ] && [ -n '$B' ] && [ -n '$C' ] && [ '$A' -lt '$B' ] && [ '$B' -lt '$C' ]"
check "V3 vt_build reads appmanifest files only" "[ \"\$(sed -n '/^vt_build(){/,/^}$/p' '$CFG' | grep -c 'appmanifest_\$1.acf')\" = 1 ] && ! sed -n '/^vt_build(){/,/^}$/p' '$CFG' | grep -q 'userdata\|config/'"

R=$T/fake
sed "s#^R=.*#R=$R#" "$SARM_TESTS/config-ui/mkfake.sh" > "$T/mkfake.sh"; bash "$T/mkfake.sh" >/dev/null
S=$R/home/tester/.local/share/steam-arm/.local/share/Steam; L2="$R/media/Game Drive/SteamLibrary"
sed -e '$d' "$CFG" > "$T/app.sh"
cat > "$T/h.sh" <<EOH
. "$T/app.sh"
R=$R
SA_CONF=\$R/etc/steam-arm/steam-arm.conf; SA_TITLES_SHARE=\$R/share/titles.conf; SA_TITLES_ETC=\$R/etc/steam-arm/titles.conf
game_home(){ echo \$R/home/tester; }; game_user(){ echo tester; }
EOH
mrun(){ bash -c ". $T/h.sh; $1" 2>&1; }
acf(){ printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"buildid"\t\t"%s"\n}\n' "$2" "$3" "$4" > "$1/steamapps/appmanifest_$2.acf"; }

OUT=$(mrun "valve_tools")
check "V4 nothing downloaded: four rows, each not downloaded yet, FEX version from VERSIONS.txt kept" \
  "[ \"\$(grep -c 'not downloaded yet' <<<\"\$OUT\")\" = 4 ] && [ \"\$(wc -l <<<\"\$OUT\")\" = 4 ] && has 'FEX tool                FEX-2609.1, app 3127680 not downloaded yet' && has 'Proton 11.0             app 4628740 not downloaded yet' && has 'Proton Experimental     app 4427310 not downloaded yet' && has 'Steam Linux Runtime 4.0 app 4185400 not downloaded yet'"
rm "$S/steamapps/common/FEX-Emu/VERSIONS.txt"; OUT=$(mrun "valve_tools")
check "V5 no VERSIONS.txt: FEX tool row without version, one note" "has 'FEX tool                app 3127680 not downloaded yet' && ! has 'not downloaded yet,'"
echo "FEX-2609.1 (2026-08-13)" > "$S/steamapps/common/FEX-Emu/VERSIONS.txt"
acf "$S" 3127680 "FEX-Emu" 20123456; acf "$L2" 4628740 "Proton 11.0 (ARM64)" 20111222
OUT=$(mrun "valve_tools")
check "V6 manifests present: build id from client library and from second library (libraryfolders.vdf path with space)" \
  "has 'FEX tool                FEX-2609.1, app 3127680 build 20123456' && has 'Proton 11.0             app 4628740 build 20111222' && has 'app 4427310 not downloaded yet'"
printf '"AppState"\n{\n\t"appid"\t\t"4427310"\n\t"name"\t\t"Proton Experimental (ARM64)"\n}\n' > "$S/steamapps/appmanifest_4427310.acf"
printf '"AppState"\n{\n\t"appid"\t\t"4185400"\n\t"buildid"\t\t"12ab"\n\t"buildid"\t\t"77"\n' > "$S/steamapps/appmanifest_4185400.acf"
OUT=$(mrun "valve_tools")
check "V7 malformed manifests: no buildid line noted; non-numeric buildid skipped, later numeric one used, truncated file read" \
  "has 'Proton Experimental     app 4427310 unknown build (no buildid line in manifest)' && has 'Steam Linux Runtime 4.0 app 4185400 build 77'"
: > "$S/steamapps/appmanifest_4185400.acf"; OUT=$(mrun "vt_build 4185400")
check "V8 empty manifest: unknown build" "[ \"\$OUT\" = 'unknown build (no buildid line in manifest)' ]"
chmod 000 "$S/steamapps/appmanifest_4185400.acf"; OUT=$(mrun "vt_build 4185400"); chmod 644 "$S/steamapps/appmanifest_4185400.acf"
if [ "$(id -u)" = 0 ]; then echo "SKIP V9 unreadable manifest (root reads every file)"
else check "V9 unreadable manifest: not downloaded yet, no error text" "[ \"\$OUT\" = 'not downloaded yet' ]"; fi
printf '"buildid" "5"\n' > "$S/steamapps/appmanifest_4185400.acf"; OUT=$(mrun "vt_build 4185400")
check "V10 buildid line without leading tabs read" "[ \"\$OUT\" = 'build 5' ]"
OUT=$(mrun "client_type(){ echo x86; }; valve_tools")
check "V11 x86 client: one row, not used" "[ \"\$OUT\" = 'not used (x86 client runs on system FEX and x86 tools)' ]"
rm "$S/steamapps/libraryfolders.vdf"; OUT=$(mrun "valve_tools")
check "V12 no libraryfolders.vdf: client library still read, second library not" "has 'app 3127680 build 20123456' && has 'app 4628740 not downloaded yet'"

echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
