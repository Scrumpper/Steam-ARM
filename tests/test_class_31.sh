#!/bin/bash
# Steam ARM 3.1 run report row Class (Android-only, VR-only, Lepton route; none for 2D or unknown cache). Settings menu
# sourced through config-ui/harness.sh (fake tree); fake Steam folder with Steam starts of five titles; appinfo reader
# stand-in prints the Frame reader contract (9 columns; 4 for 3.0 reader); then reader extracted from the installer
# under test on a generated appinfo.vdf. Internal; not for release zips.
. "$(dirname "$0")/paths.sh"
T0=$SARM_TESTS/config-ui
T=$(mktemp -d /tmp/sarm31-class.XXXXXX); trap 'rm -rf "$T"' EXIT
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
R=$SARM_UI_FAKE
bash "$T0/mkfake.sh" >/dev/null
sed -e "s#^APP=.*#APP=\"$SARM_CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; sed 's/^/     /' <<<"$OUT" | tail -n 12; fail=$((fail + 1)); fi; }

ME=$(id -un)
GH=$R/home/tester
S=$GH/.local/share/steam-arm/.local/share/Steam
mkdir -p "$S/logs" "$S/config" "$S/package" "$S/appcache" "$T/tmp"
lt(){ date -d "@$1" '+%Y-%m-%d %H:%M:%S'; }
NOW=$(date +%s)
cat > "$S/config/loginusers.vdf" <<'VDF'
"users"
{
	"76561198012345678"
	{
		"AccountName"		"zlogname9"
		"PersonaName"		"Persona Qwerty"
		"MostRecent"		"1"
	}
}
VDF
printf '"ubuntu12"\n{\n\t"version"\t\t"1791328779"\n}\n' > "$S/package/steam_client_linux_arm64_beta_x_linuxarm64.manifest"
CHAIN="/home/$ME/.local/share/steam-arm/.local/share/Steam/linuxarm64/steam-launch-wrapper --oom-score-adjust 900 -- reaper SteamLaunch"
for a in 100 200 300 400 500; do
  echo "[$(lt $((NOW - 1000 + a)))] Game process added : AppID $a \"$CHAIN AppId=$a -- '/x/common/Proton 11.0 (ARM64)'/proton waitforexitandrun -- g.exe\", ProcID $a, IP 0.0.0.0:0"
  echo "[$(lt $((NOW - 990 + a)))] Game process removed: AppID $a \"$CHAIN AppId=$a\", ProcID $a, IP 0.0.0.0:0"
done > "$S/logs/console_log.txt"

# reader stand-in: contract line per appid (col5 Frame runtime, col7 oslist, col9 vr); COLS=4 = 3.0 reader
cat > "$T/appinfo-stub.py" <<'PY'
import os, sys
ROWS = {
    "100": ["Verified", "Verified", "unknown", "lepton-stable", "DefaultControllerConfigFullyFunctional", "android", "2026-10-22", "only"],
    "200": ["Verified", "Verified", "proton-stable", "proton-stable", "InterfaceTextIsLegible", "windows", "2026-09-01", "only"],
    "300": ["Verified", "Playable", "proton-stable", "proton-stable", "InterfaceTextIsLegible", "windows,macos,linux", "2026-08-01", "none"],
    "400": ["Verified", "Verified", "proton-stable", "lepton-stable", "InterfaceTextIsLegible", "windows,android", "2026-09-10", "supported"],
}
n = int(os.environ.get("COLS", "9"))
for a in sys.argv[2:]:
    print("\t".join(([a] + ROWS.get(a, ["unknown"] * 8))[:n]))
PY
cat > "$T/stubs.sh" <<EOS
game_user(){ echo "$ME"; }
game_home(){ echo "$GH"; }
SA_APPINFO_PY=$T/appinfo-stub.py
eval "\$(declare -f rr_py | sed 's#"/tmp/#"$T/tmp/#g')"
EOS
sh_(){ bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; $1" 2>&1; }
rep(){ OUT=$(sh_ "${2:-:}; rr_make $1 0 $T/rep.md; echo RC=\$? APP=\$RR_APP"); REP=$(cat "$T/rep.md" 2>/dev/null); }
cls(){ sed -n '/^## Upstream fields/,/^## Knobs/p' <<<"$REP" | grep '^Class '; }

rep 100
check "A1 Android-only (oslist android): Class row after Upstream fields, Lepton runtime named" "grep -q 'RC=0 APP=100' <<<\"\$OUT\" && [ \"\$(cls)\" = 'Class           Android-only title: needs Lepton runtime, not available outside Steam Frame; no Linux or Windows build to run' ]"
check "A1 Class row follows Proton row, before Knobs" "[ \"\$(sed -n '/^## Upstream fields/,/^## Knobs/p' <<<\"\$REP\" | grep -E '^(Proton|Class) ' | cut -d' ' -f1 | paste -sd,)\" = Proton,Class ]"
rep 200
check "A2 VR-only (VR flag only, Windows build on Proton route): Class row names VR runtime" "[ \"\$(cls)\" = 'Class           VR-only title: needs VR runtime (Steam Frame or SteamVR component), not present on this stack' ]"
rep 300
check "A3 2D title (windows,macos,linux, proton-stable, no VR): no Class row" "grep -q 'RC=0 APP=300' <<<\"\$OUT\" && [ -z \"\$(cls)\" ]"
rep 400
check "A4 Lepton route, VR supported, Windows build present: Lepton route row" "[ \"\$(cls)\" = 'Class           Lepton route title: Steam Frame runs its Android build through Lepton, not present here; Windows or Linux build starts instead' ]"
rep 500
check "A5 title absent from cache (all unknown): no Class row, report made" "grep -q 'RC=0 APP=500' <<<\"\$OUT\" && [ -z \"\$(cls)\" ]"
rep 100 "SA_APPINFO_PY=$T/missing.py"
check "A6 reader missing: no Class row, report made" "grep -q 'RC=0 APP=100' <<<\"\$OUT\" && [ -z \"\$(cls)\" ]"
rep 100 "export COLS=4"
check "A8 reader of 3.0 (4 columns): no Class row" "grep -q 'RC=0 APP=100' <<<\"\$OUT\" && [ -z \"\$(cls)\" ]"
check "A9 rr_class reads reader line through appinfo_line once, no own parse; rr_make adds none" "[ \$(sed -n '/^rr_class(){/,/^}/p' \"\$SARM_CFG\" | grep -c 'appinfo_line') = 1 ] && ! sed -n '/^rr_class(){/,/^}/p;/^rr_make(){/,/^}/p' \"\$SARM_CFG\" | grep -q 'SA_APPINFO_PY\|deck_hint'"

# reader extracted from the installer under test on a generated appinfo.vdf (v41): Android-only title with Frame block
awk "/^cat > \/usr\/local\/lib\/steam-arm-appinfo.py <<'AIPY'\$/{f=1;next} /^AIPY\$/{f=0} f" "$SARM_INST" > "$T/appinfo.py"
python3 - "$S/appcache/appinfo.vdf" <<'PY'
import struct, sys
table = []
def key(k):
    if k not in table: table.append(k)
    return struct.pack("<i", table.index(k))
def enc(d):
    out = b""
    for k, v in d.items():
        if isinstance(v, dict): out += b"\x00" + key(k) + enc(v)
        elif isinstance(v, str): out += b"\x01" + key(k) + v.encode() + b"\0"
        elif isinstance(v, int): out += b"\x02" + key(k) + struct.pack("<i", v)
    return out + b"\x08"
frame = lambda rt: {"category": 3, "configuration": {"recommended_runtime": rt}, "test_timestamp": "1792695299",
                    "tests": {"0": {"display": "4", "token": "#SteamFrame_TestResult_DefaultControllerConfigFullyFunctional"}}}
apps = {
    100: {"name": "Android title", "oslist": "android", "onlyvrsupport": "1", "category": {"category_2": "1", "category_54": "1"},
          "steam_deck_compatibility": {"category": 1}, "steam_frame_compatibility": frame("lepton-stable")},
    200: {"name": "VR title", "oslist": "windows", "onlyvrsupport": "1", "category": {"category_2": "1", "category_54": "1"},
          "steam_frame_compatibility": frame("proton-stable")},
    300: {"name": "Flat title", "oslist": "windows,macos,linux", "category": {"category_2": "1"},
          "steam_deck_compatibility": {"category": 3, "configuration": {"recommended_runtime": "proton-stable"}},
          "steam_frame_compatibility": frame("proton-stable")},
}
body = b""
for appid, common in apps.items():
    kv = enc({"appinfo": {"appid": appid, "common": common}})
    entry = struct.pack("<IIQ", 2, 0, 0) + b"\0" * 20 + struct.pack("<I", 1) + b"\0" * 20 + kv
    body += struct.pack("<II", appid, len(entry)) + entry
body += struct.pack("<I", 0)
st = struct.pack("<I", len(table)) + b"".join(s.encode() + b"\0" for s in table)
open(sys.argv[1], "wb").write(struct.pack("<IIq", 0x07564429, 1, 16 + len(body)) + body + st)
PY
OUT=$(python3 "$T/appinfo.py" "$S/appcache/appinfo.vdf" 100 200 300 2>&1)
if [ "$(awk -F'\t' '$1 == 100 { print NF }' <<<"$OUT")" -ge 9 ] 2>/dev/null; then
  check "B0 installer reader: Frame columns for Android title (runtime lepton-stable, oslist android)" "awk -F'\t' '\$1 == 100 && \$5 == \"lepton-stable\" && \$7 == \"android\" { f = 1 } END { exit !f }' <<<\"\$OUT\""
  check "B0 installer reader: vr column only for VR title, none for flat title" "awk -F'\t' '(\$1 == 200 && \$9 == \"only\") || (\$1 == 300 && \$9 == \"none\") { n++ } END { exit n != 2 }' <<<\"\$OUT\""
  rep 100 "SA_APPINFO_PY=$T/appinfo.py"
  check "B1 installer reader: Android-only Class row from generated appinfo.vdf" "grep -q '^Class           Android-only title: needs Lepton runtime' <<<\"\$(cls)\""
  rep 200 "SA_APPINFO_PY=$T/appinfo.py"
  check "B3 installer reader: VR-only Class row for Windows VR title on Proton route" "grep -q '^Class           VR-only title' <<<\"\$(cls)\""
  rep 300 "SA_APPINFO_PY=$T/appinfo.py"
  check "B2 installer reader: flat title gets no Class row" "grep -q 'RC=0 APP=300' <<<\"\$OUT\" && [ -z \"\$(cls)\" ]"
else
  echo "SKIP B installer reader prints $(awk -F'\t' '$1 == 100 { print NF }' <<<"$OUT") columns (Steam Frame block not read yet)"
fi

echo "$pass PASS, $fail FAIL"
[ "$fail" = 0 ]
