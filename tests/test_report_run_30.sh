#!/bin/bash
# Steam ARM 3.0 run report (B2), run history switch (B3 menu/CLI), issue templates (B4). Settings menu sourced through
# config-ui/harness.sh (fake tree); fake Steam folder, handler logs, Valve tool log with environment dump, runs.log,
# loginusers.vdf; collector's /tmp handler-log path rewritten into a temp folder in the test copy only. Screens stubbed
# (answers from a queue file). Internal; not for release zips.
. "$(dirname "$0")/paths.sh"
T0=$SARM_TESTS/config-ui
T=$(mktemp -d /tmp/sarm30-rr.XXXXXX); trap 'rm -rf "$T"' EXIT
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
R=$SARM_UI_FAKE
bash "$T0/mkfake.sh" >/dev/null
sed -e "s#^APP=.*#APP=\"$SARM_CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; sed 's/^/     /' <<<"$OUT" | tail -n 12; fail=$((fail + 1)); fi; }

ME=$(id -un)
GH=$R/home/tester
S=$GH/.local/share/steam-arm/.local/share/Steam
mkdir -p "$S/logs" "$S/config" "$S/steamapps/common/Game" "$S/package" "$T/tmp" "$GH/.local/share/steam-arm/.local/state/steam-arm"
lt(){ date -d "@$1" '+%Y-%m-%d %H:%M:%S'; }
ut(){ date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }
NOW=$(date +%s); T1=$((NOW - 600)); T2=$((NOW - 300)); T3=$((NOW - 120))
cat > "$S/steamapps/appmanifest_100.acf" <<'EOF'
"AppState"
{
	"appid"		"100"
	"name"		"Test Title One"
	"installdir"		"Game"
	"LastOwner"		"76561198012345678"
}
EOF
cat > "$S/config/loginusers.vdf" <<'EOF'
"users"
{
	"76561198012345678"
	{
		"AccountName"		"zlogname9"
		"PersonaName"		"Persona Qwerty"
		"MostRecent"		"1"
	}
}
EOF
printf '"ubuntu12"\n{\n\t"version"\t\t"1791328779"\n}\n' > "$S/package/steam_client_linux_arm64_beta_x_linuxarm64.manifest"
echo SECRETTOKEN > "$S/config/steam.token"; echo SECRETSSFN > "$S/ssfn12345"; mkdir -p "$S/userdata/52079950"
echo SECRETUSERDATA > "$S/userdata/52079950/localconfig.vdf"
CHAIN="/home/$ME/.local/share/steam-arm/.local/share/Steam/linuxarm64/steam-launch-wrapper --oom-score-adjust 900 -- reaper SteamLaunch"
{
  echo "[$(lt $T1)] Game process added : AppID 100 \"$CHAIN AppId=100 -- '/x/FEX-Emu'/fex-compat-tool waitforexitandrun -- game\", ProcID 11, IP 0.0.0.0:0"
  echo "[$(lt $((T1 + 47)))] Game process removed: AppID 100 \"$CHAIN AppId=100 -- '/x/FEX-Emu'/fex-compat-tool waitforexitandrun\", ProcID 11, IP 0.0.0.0:0"
  echo "[$(lt $T2)] Game process added : AppID 200 \"$CHAIN AppId=200 -- '/x/common/Proton 11.0 (ARM64)'/proton waitforexitandrun -- g.exe\", ProcID 12, IP 0.0.0.0:0"
  echo "[$(lt $((T2 + 30)))] Game process removed: AppID 200 \"$CHAIN AppId=200\", ProcID 12, IP 0.0.0.0:0"
} > "$S/logs/console_log.txt"
HL=$T/tmp/steam-arm-run-4242.log
cat > "$HL" <<EOF
SteamAppId=100
steam-arm: client: native ARM64
steam-arm: entry: launch wrapper
steam-arm: start: $(ut $((T1 + 1)))
steam-arm: profile for 100 {'multiblock': 'off'}
steam-arm: engine: unity, 64-bit
steam-arm: overlay: x86
steam-arm: graphics: forwarding
steam-arm: LD_PRELOAD for container: /home/$ME/.local/share/steam-arm/.local/share/Steam/ubuntu12_64/gameoverlayrenderer.so
steam-arm: fex: Multiblock off (title profile)
steam-arm: note for zlogname9 at 203.0.113.9 from boxhost-$ME
steam-arm: odd [U:1:52079950] line
steam-arm: persona Persona Qwerty line
steam-arm: glued zlogname9suffix word
steam-arm: glued x76561198099999999y id
steam-arm: command: /home/$ME/.local/share/steam-arm/.local/share/Steam/linuxarm64/steam-launch-wrapper.real -- reaper
steam-arm: renderer: GPU (panthor renderD130), forwarding to host driver, process exe
steam-arm: run record: on (RUN_HISTORY=on)
steam-arm: exit status 0
steam-arm: run time: 47 s
EOF
TL=$T/tmp/fex-compat-tool-4250.log
cat > "$TL" <<EOF
USER=$ME
SSH_CLIENT=203.0.113.9 47064 22
SteamAppUser=zlogname9
SteamAppId=100
HOME=/home/$ME/.local/share/steam-arm
STEAM_COMPAT_FEX_CONFIG=
ERRORLIKE_VAR=SIGSEGV in value
Graphics provider overwritten with: '/opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json'
fex compat fixups
[ERROR] Unhandled SIGILL at 0x1234
[ERROR] Unhandled SIGILL at 0x1234
EOF
touch -d "@$((T1 + 47))" "$HL"; touch -d "@$((T1 + 46))" "$TL"
RL=$GH/.local/share/steam-arm/.local/state/steam-arm/runs.log
cat > "$RL" <<EOF
t=$(ut $((T1 - 9000))) ev=start app=100 run=3001 entry=wrapper client=arm64 gfx=b overlay=x86 fex=FEX-2607 mesa=26.1.8 profile=-
t=$(ut $((T1 - 8900))) ev=exit app=100 run=3001 status=sig11 secs=100 renderer=gpu
t=$(ut $((T1 - 5000))) ev=start app=300 run=3002 entry=wrapper client=arm64 gfx=a fex=FEX-2607 profile=-
t=$(ut $((T1 + 1))) ev=start app=100 run=4242 entry=wrapper client=arm64 gfx=a fex=FEX-2607 profile=multiblock
t=$(ut $((T1 + 47))) ev=exit app=100 run=4242 status=0 secs=47 renderer=gpu
EOF
chmod 600 "$RL"

# test copy: collector reads handler logs from $T/tmp; screens stubbed; game account = this account
export Q=$T/q LOG=$T/ui.log
cat > "$T/stubs.sh" <<EOF
game_user(){ echo "$ME"; }
game_home(){ echo "$GH"; }
hostname(){ echo "boxhost-$ME"; }
eval "\$(declare -f rr_py | sed 's#"/tmp/#"$T/tmp/#g')"
EOF
cat >> "$T/stubs.sh" <<'EOF'
nxt(){ A=$(head -n 1 "$Q"); sed -i 1d "$Q"; }
ui_menu(){ printf 'MENU %s|%s|%s\n' "$1" "$2" "${*:3}" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; echo "$A"; }
ui_msg(){ printf 'MSG %s|%s\n' "$1" "$2" >> "$LOG"; }
ui_text(){ printf 'TEXT %s|%s\n' "$1" "$3" >> "$LOG"; cp "$2" "$LOG.text"; }
ui_textstr(){ printf 'TEXTSTR %s\n' "$1" >> "$LOG"; }
ui_info(){ :; }
ui_yesno(){ printf 'YESNO %s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$LOG"; nxt; [ "$A" = yes ]; }
pick_game(){ echo "PICK $1" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; echo "$A"; }
EOF
sh_(){ bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; $1" 2>&1; }
ui(){ local c=$1; shift; printf '%s\n' "$@" > "$Q"; : > "$LOG"; rm -f "$LOG.text"; sh_ "$c" >/dev/null; OUT=$(cat "$LOG"); }
rep(){ OUT=$(sh_ "rr_make $1 ${2:-0} $T/rep.md; echo RC=\$? APP=\$RR_APP"); REP=$(cat "$T/rep.md" 2>/dev/null); }

# ---------------- B2 report content ----------------
rep 100
check "R1 report made for 100: status 0" "grep -q 'RC=0 APP=100' <<<\"\$OUT\""
OUT=$REP
check "R1 Summary: AppID, title from app manifest, route, graphics, renderer" "grep -q '^AppID  *100\$' <<<\"\$REP\" && grep -q '^Title  *Test Title One\$' <<<\"\$REP\" && grep -q '^Route  *x86 Linux build through FEX, native ARM64 client, entry: launch wrapper\$' <<<\"\$REP\" && grep -q '^Graphics  *forwarding\$' <<<\"\$REP\" && grep -q '^Renderer  *GPU (panthor renderD130), forwarding to host driver, process exe\$' <<<\"\$REP\""
check "R1 Result from handler: run time and launch chain exit status" "grep -q '^Result  *ended after 47 s, launch chain exit status 0\$' <<<\"\$REP\""
check "R1 sections in order: Summary, Upstream fields, Knobs, Outcome, Earlier runs, Logs, Hardware report" "[ \"\$(grep -E '^## |<summary>' <<<\"\$REP\" | tr '\n' '|')\" = '## Summary|## Upstream fields|## Knobs|## Outcome|## Earlier runs|<details><summary>Logs</summary>|<details><summary>Hardware report</summary>|' ]"
check "R2 Upstream fields: FEX tool, executable from engine line, Proton none, Steam client build from package manifest" "grep -q '^Executable  *unity, 64-bit\$' <<<\"\$REP\" && grep -q '^FEX tool ' <<<\"\$REP\" && grep -q '^Proton  *none (Linux build)\$' <<<\"\$REP\" && grep -q '^Steam client  *1791328779 (' <<<\"\$REP\""
K=$(sed -n '/^## Knobs/,/^## Outcome/p' <<<"$REP")
check "R3 Knobs: profile, overlay, graphics, FEX lines; no client, entry, command, renderer, exit lines" "grep -q '^overlay: x86' <<<\"\$K\" && grep -q '^fex: Multiblock off (title profile)' <<<\"\$K\" && grep -q '^profile for 100' <<<\"\$K\" && ! grep -qE '^(client|entry|command|renderer|exit status|run time|start):' <<<\"\$K\""
check "R3 Outcome: Steam start/end, exit status note, resources" "grep -q '^Steam start ' <<<\"\$REP\" && grep -q '^Exit status  *0 (launch chain; a game crash inside the runtime container can also end with 0)' <<<\"\$REP\" && grep -q '^max_map_count ' <<<\"\$REP\" && grep -q '^/dev/shm ' <<<\"\$REP\""
check "R4 FEX tool log: error lines only, counted; environment lines left out" "grep -q '^\[ERROR\] Unhandled SIGILL at 0x1234 (2 times)\$' <<<\"\$REP\" && ! grep -qE 'SSH_CLIENT|SteamAppUser|ERRORLIKE_VAR|^USER=|fex compat fixups' <<<\"\$REP\""
check "R5 earlier runs: this title only by default, current run left out" "grep -q 'gfx=b .* status=sig11 secs=100 renderer=gpu' <<<\"\$REP\" && ! grep -q 'app=300' <<<\"\$REP\" && grep -q '^(this title only)' <<<\"\$REP\" && [ \$(sed -n '/^## Earlier runs/,/^<details>/p' <<<\"\$REP\" | grep -c '^20') = 1 ]"
check "R6 personal data: account, sign-in and persona names, Steam IDs, host, LAN address, home paths gone" "! grep -qiE \"zlogname9|Persona Qwerty|76561198012345678|52079950|boxhost|203\\.0\\.113\\.9|/home/\$ME|\$ME\" <<<\"\$REP\""
check "R6 inline values replaced by tags, line kept" "grep -q '^note for <login> at <ip> from <host>\$' <<<\"\$REP\" && grep -q '^odd \[U:1:<steamid>\] line\$' <<<\"\$REP\" && grep -q '^LD_PRELOAD for container: ~/' <<<\"\$REP\""
check "R6 self-check: a value or Steam ID that survives scrubbing drops its whole line" "[ \$(sed -n '/^## Knobs/,/^## Outcome/p' <<<\"\$REP\" | grep -c '^(line removed: personal data)\$') = 2 ] && ! grep -q 'glued' <<<\"\$REP\""
check "R7 never reads steam.token, ssfn*, userdata/: content absent, collector has no such path" "! grep -q 'SECRET' <<<\"\$REP\" && ! sed -n '/^rr_py(){/,/^}/p;/^rr_make(){/,/^}/p' \"\$SARM_CFG\" | grep -qE 'steam\\.token|ssfn|userdata'"
check "R8 footer lists removed categories; size under 30 KB" "grep -q '^Removed before saving: home folders, account names' <<<\"\$REP\" && [ \$(wc -c <<<\"\$REP\") -le 30720 ]"

rep 100 1
check "R5 earlier runs ticked: other titles' App IDs added" "grep -q 'app=300 gfx=a' <<<\"\$REP\" && ! grep -q '^(this title only)' <<<\"\$REP\""

rep 200
check "R9 Windows title on ARM64 Proton: route named, run record not available for this route" "grep -q '^Route  *Windows build on ARM64 Proton\$' <<<\"\$REP\" && grep -q '^Run history  *run record: not available for this route\$' <<<\"\$REP\" && grep -q '^Result  *ended (Steam.s end line); exit status not recorded\$' <<<\"\$REP\" && ! grep -q '^Handler  ' <<<\"\$REP\""
check "R9 Proton tool of start line named, never Linux build on Proton route" "grep -q '^Proton  *Proton 11.0 (ARM64) (from Steam.s start line)\$' <<<\"\$REP\" && ! sed -n '/^## Upstream/,/^## Knobs/p' <<<\"\$REP\" | grep -q 'Linux build'"
cp "$S/logs/console_log.txt" "$T/console.bak2"
echo "[$(lt $((NOW - 60)))] Game process added : AppID 400 \"$CHAIN AppId=400 -- '$S/compatibilitytools.d/GE-Proton10-x-aarch64'/proton waitforexitandrun -- g.exe\", ProcID 14, IP 0.0.0.0:0" >> "$S/logs/console_log.txt"
rep 400
check "R9 GE-Proton from compatibilitytools.d named" "grep -q '^Proton  *GE-Proton10-x-aarch64 (from Steam.s start line)\$' <<<\"\$REP\" && grep -q '^Route  *Windows build on ARM64 Proton\$' <<<\"\$REP\""
cp "$T/console.bak2" "$S/logs/console_log.txt"
rep last
check "R10 last: newest Steam start (200)" "grep -q '^AppID  *200\$' <<<\"\$REP\""
rep 999
check "R11 title never started: status 1, message" "grep -q 'RC=1 APP=\$' <<<\"\$OUT\" && grep -q '^No game start found' <<<\"\$REP\""

# handler not reached: Steam start of 100 through FEX tool newer than its handler log
cp "$S/logs/console_log.txt" "$T/console.bak"
echo "[$(lt $T3)] Game process added : AppID 100 \"$CHAIN AppId=100 -- '/x/FEX-Emu'/fex-compat-tool waitforexitandrun -- game\", ProcID 13, IP 0.0.0.0:0" >> "$S/logs/console_log.txt"
rep 100
check "R12 FEX start without handler log: Handler not reached, earlier handler lines not shown as this start" "grep -q '^Handler  *not reached at newest start (handler log only of an earlier start)\$' <<<\"\$REP\" && ! grep -q '^overlay: x86' <<<\"\$REP\" && grep -q '^(no handler lines for this start)' <<<\"\$REP\""
cp "$T/console.bak" "$S/logs/console_log.txt"

# kernel and core dump lines through stand-ins
OUT=$(sh_ "journalctl(){ echo '2026-10-15T08:36:00 h kernel: panthor fb000000.gpu: job timeout'; echo 'unrelated line'; }; coredumpctl(){ case \$1 in list) echo 'Thu 2026-10-15 08:36:01 PDT 777 1000 1000 SIGSEGV present /home/$ME/.local/share/steam-arm/.local/share/Steam/steamapps/common/Game/game.bin 1M'; echo 'Thu 2026-10-15 08:36:02 PDT 778 1000 1000 SIGSEGV present /usr/bin/bash 1M';; info) if [ \$2 = 777 ]; then printf '      Signal: 11 (SEGV)\n  Executable: /home/$ME/g/game.bin\n       #0  0x1 crashfn (game.bin)\n'; else echo '  Executable: /usr/bin/bash'; fi;; esac; }; rr_make 100 0 $T/rep.md"); REP=$(cat "$T/rep.md")
check "R13 kernel GPU lines and game core dump lines of the run window; other programs' dumps left out" "grep -q 'panthor fb000000.gpu: job timeout' <<<\"\$REP\" && ! grep -q 'unrelated line' <<<\"\$REP\" && grep -q 'Signal: 11 (SEGV)' <<<\"\$REP\" && grep -q 'crashfn' <<<\"\$REP\" && ! grep -q '/usr/bin/bash' <<<\"\$REP\" && ! grep -q \"/home/\$ME\" <<<\"\$REP\""
OUT=$(sh_ "journalctl(){ echo 'No journal files were opened due to insufficient permissions.'; }; rr_make 100 0 $T/rep.md"); REP=$(cat "$T/rep.md")
check "R13 kernel log not readable: said so" "grep -q '^Kernel  *log not readable by this account' <<<\"\$REP\""

# 30 KB cap: long handler log
cp "$HL" "$T/hl.bak"
for i in $(seq 1 1500); do echo "steam-arm: fex: filler line $i with some padding text to grow the report $(printf '%0200d' 0)"; done >> "$HL"
rep 100
check "R14 cap: report at most 30 KB, oldest lines of largest block left out with note" "[ \$(wc -c < $T/rep.md) -le 30720 ] && grep -q 'older lines left out: 30 KB report limit' <<<\"\$REP\" && grep -q '^## Summary' <<<\"\$REP\" && grep -q 'filler line 1500' <<<\"\$REP\""
cp "$T/hl.bak" "$HL"; touch -d "@$((T1 + 47))" "$HL"

# sign-in names unreadable: no report (fail closed)
OUT=$(sh_ "rr_read(){ case \"\$1\" in cat) case \"\$2\" in *loginusers.vdf) return 1;; esac;; esac; \"\$@\" 2>/dev/null; }; rr_make 100 0 $T/rep.md; echo RC=\$?"); REP=$(cat "$T/rep.md")
check "R15 sign-in file present but unreadable: report not made" "grep -q 'RC=1' <<<\"\$OUT\" && grep -q 'could not be read to remove them; report not made' <<<\"\$REP\""

# ---------------- menu screens ----------------
ui "menu_maintenance" BACK
check "M1 Maintenance: items 11 Report how last game ran, 12 Run history (now: off), version items after them" "grep -q '^MENU Maintenance|.* 11 Report how last game ran 12 Run history (now: off) 14 Show what is new' <<<\"\$OUT\""
ui "menu_maintenance" 11 BACK BACK
check "M2 Back from report screen: Maintenance again, cursor on 11" "grep -q '^MENU Report how last game ran|Report of one game start' <<<\"\$OUT\" && [ \$(grep -c '^MENU Maintenance' <<<\"\$OUT\") = 2 ] && grep '^MENU Maintenance' <<<\"\$OUT\" | tail -n 1 | grep -q -- '--default 11 '"
rm -f "$R"/tmp/steam-arm-report-*.md
ui "maint_runreport" 1 yes
F=$(ls "$R"/tmp/steam-arm-report-200-*.md 2>/dev/null | head -1)
check "M3 Last game: review screen (button Next), save question, saved file name and mode 600" "grep -q '^TEXT Run report: read before saving|Next' <<<\"\$OUT\" && grep -q '^YESNO Run report|Save report to' <<<\"\$OUT\" && [ -n \"\$F\" ] && [[ \"\$F\" =~ steam-arm-report-200-[0-9]{8}-[0-9]{4}\\.md\$ ]] && [ \$(stat -c %a \"\$F\") = 600 ] && grep -q '^MSG Run report|Saved to' <<<\"\$OUT\""
check "M3 run history off: no earlier-runs question" "! grep -q '^YESNO Earlier runs' <<<\"\$OUT\""
rm -f "$R"/tmp/steam-arm-report-*.md
ui "maint_runreport" 2 100 no
check "M4 Pick a game, Discard: list shown, nothing saved" "grep -q '^PICK Report how a game ran' <<<\"\$OUT\" && ! ls \"$R\"/tmp/steam-arm-report-*.md >/dev/null 2>&1 && grep -q '^AppID  *100' \"$LOG.text\""
ui "maint_runreport" 2 BACK
check "M5 Pick a game, Back: no report" "! grep -q '^TEXT' <<<\"\$OUT\""
echo RUN_HISTORY=on >> "$R/etc/steam-arm/steam-arm.conf"
ui "maint_runreport" 2 100 yes no
check "M6 run history on: earlier-runs question (default: this game only), Add adds other titles" "grep -q '^YESNO Earlier runs|.*App IDs.*|Add|This game only' <<<\"\$OUT\" && grep -q 'app=300' \"$LOG.text\""
sed -i '/^RUN_HISTORY=/d' "$R/etc/steam-arm/steam-arm.conf"
ui "maint_runhistory" yes
check "M7 Run history: turn on (text names file, 200 lines, no backups); setting on" "grep -q '^YESNO Run history|Run history: off' <<<\"\$OUT\" && grep -q 'runs.log' <<<\"\$OUT\" && grep -q 'not part of backups' <<<\"\$OUT\" && grep -q '^RUN_HISTORY=on' \"$R/etc/steam-arm/steam-arm.conf\" && grep -q '^MSG Maintenance|Run history: on' <<<\"\$OUT\""
ui "menu_maintenance" BACK
check "M7 label follows: Run history (now: on)" "grep -q '12 Run history (now: on) 14 Show what is new' <<<\"\$OUT\""
ui "maint_runhistory" no
check "M8 Back from Run history: unchanged" "grep -q '^RUN_HISTORY=on' \"$R/etc/steam-arm/steam-arm.conf\" && ! grep -q '^MSG' <<<\"\$OUT\""
cp "$RL" "$T/runs.bak"
ui "maint_runhistory" yes
check "M9 turn off: setting off, recorded lines deleted" "grep -q '^RUN_HISTORY=off' \"$R/etc/steam-arm/steam-arm.conf\" && [ ! -e \"$RL\" ] && grep -q 'Recorded lines deleted' <<<\"\$OUT\""
cp "$T/runs.bak" "$RL"

# ---------------- CLI ----------------
rm -f "$R"/tmp/steam-arm-report-*.md
OUT=$(sh_ "main report run 100 </dev/null | cat")
check "C1 report run APPID, no terminal: printed, not saved" "grep -q '^# Steam ARM run report' <<<\"\$OUT\" && ! ls \"$R\"/tmp/steam-arm-report-*.md >/dev/null 2>&1"
OUT=$(sh_ "main report run 100 --save </dev/null | cat")
check "C2 --save: saved without asking" "grep -q '^Saved to .*steam-arm-report-100-' <<<\"\$OUT\" && ls \"$R\"/tmp/steam-arm-report-100-*.md >/dev/null 2>&1"
OUT=$(sh_ "main report run abc; echo RC=\$?")
check "C3 bad argument: usage, status 2" "grep -q 'usage: steam-arm-config report run' <<<\"\$OUT\" && grep -q 'RC=2' <<<\"\$OUT\""
OUT=$(sh_ "main report run 999 </dev/null | cat; echo RC=\${PIPESTATUS[0]}")
check "C4 never-started title: message, status 1" "grep -q '^No game start found' <<<\"\$OUT\" && grep -q 'RC=1' <<<\"\$OUT\""
OUT=$(sh_ "main run-history; main run-history on; main run-history; main run-history maybe; echo RC=\$?")
check "C5 run-history: state, on, usage on bad value" "grep -q '^Run history: off' <<<\"\$OUT\" && grep -q '^Run history: on (from the next game start)' <<<\"\$OUT\" && grep -q '^Run history: on\$' <<<\"\$OUT\" && grep -q 'RC=2' <<<\"\$OUT\""
OUT=$(sh_ "usage")
check "C6 --help: report run and run-history documented, RUN_HISTORY in settings file" "grep -q 'report run \[APPID|last\] \[--history\] \[--save\]' <<<\"\$OUT\" && grep -q 'run-history \[on|off\]' <<<\"\$OUT\" && grep -q 'RUN_HISTORY=on|off' <<<\"\$OUT\""
OUT=$(sh_ "rs_valid RUN_HISTORY on && echo V1; rs_valid RUN_HISTORY yes || echo V2; echo \"\$SA_BK_KEYS\"")
check "C7 backup: RUN_HISTORY a setup key with on/off check" "grep -q V1 <<<\"\$OUT\" && grep -q V2 <<<\"\$OUT\" && grep -q 'CPU_NOTICE RUN_HISTORY' <<<\"\$OUT\""
OUT=$(sh_ "main report </dev/null | head -3")
check "C8 plain report unchanged: hardware report" "grep -q '^Steam ARM hardware report' <<<\"\$OUT\""

# ---------------- F Steam Frame rows (3.1): reader stub, rows only when known ----------------
cat > "$T/ai.py" <<EOF
import sys
for a in sys.argv[2:]:
    print(a + "\t" + open("$T/ai-out").read().strip() if a == "100" else a + "\tunknown\tunknown\tunknown\tunknown\t-\tunknown\tunknown")
EOF
printf 'Verified\tPlayable\tnative\tproton-stable\tDefaultConfigurationIsNotPerformant,InterfaceTextIsLegible\twindows,linux\t2026-09-01\tonly\n' > "$T/ai-out"
OUT=$(sh_ "SA_APPINFO_PY=$T/ai.py; rr_make 100 0 $T/rep.md"); REP=$(cat "$T/rep.md")
check "F1 Upstream fields: Steam Frame category row with hint note, after Proton row" "grep -q '^Steam Frame  *Playable (Valve.s rating for Steam Frame; hint only on this device)\$' <<<\"\$REP\" && [ \"\$(grep -nE '^(Proton|Steam Frame) ' <<<\"\$REP\" | cut -d: -f1 | tr '\n' ' ')\" = \"\$(grep -nE '^(Proton|Steam Frame) ' <<<\"\$REP\" | cut -d: -f1 | sort -n | tr '\n' ' ')\" ]"
check "F1 Frame runtime, Frame tests (comma and space), Frame tested rows; ninth column (vr) not in Frame tested" "grep -q '^Frame runtime  *proton-stable\$' <<<\"\$REP\" && grep -q '^Frame tests  *DefaultConfigurationIsNotPerformant, InterfaceTextIsLegible\$' <<<\"\$REP\" && grep -q '^Frame tested  *2026-09-01\$' <<<\"\$REP\""
check "F1 Frame rows sit in Upstream fields section" "sed -n '/^## Upstream fields/,/^## Knobs/p' <<<\"\$REP\" | grep -q '^Steam Frame '"
printf 'Verified\tunknown\tnative\tunknown\t-\tunknown\tunknown\n' > "$T/ai-out"
OUT=$(sh_ "SA_APPINFO_PY=$T/ai.py; rr_make 100 0 $T/rep.md"); REP=$(cat "$T/rep.md")
check "F2 Frame fields unknown: no Frame rows, Proton row kept" "! grep -qE '^(Steam Frame|Frame runtime|Frame tests|Frame tested) ' <<<\"\$REP\" && grep -q '^Proton ' <<<\"\$REP\""
OUT=$(sh_ "SA_APPINFO_PY=$T/none.py; rr_make 100 0 $T/rep.md"); REP=$(cat "$T/rep.md")
check "F3 reader missing: no Frame rows, report still made" "! grep -q '^Steam Frame ' <<<\"\$REP\" && grep -q '^## Knobs' <<<\"\$REP\""

# ---------------- B4 issue templates ----------------
TD=$(dirname "$SARM_INST")/.github/ISSUE_TEMPLATE
for f in bug_report.yml compatibility_report.yml; do
  OUT=$(cat "$TD/$f")
  check "T1 $f: one required report textarea without render, no setup --list ask" "python3 -c '
import re, sys
t = open(sys.argv[1]).read()
b = [x for x in re.split(r\"\n  - type: \", t)[1:]]
r = [x for x in b if \"id: steam-arm-report\" in x]
sys.exit(not (len(r) == 1 and r[0].startswith(\"textarea\") and \"required: true\" in r[0] and \"render:\" not in r[0]
              and \"steam-arm-config report run\" in r[0] and \"--list\" not in t))' \"$TD/$f\""
  check "T2 $f: no hand-typed board, distro, uname, GPU, page size fields; leak note" "! grep -qE 'id: (board|distro|uname|gpu|pagesize|soc-gpu|driver|components|component-list)\$' <<<\"\$OUT\" && grep -q 'no account names, host names, addresses or Steam IDs' <<<\"\$OUT\""
done
OUT=$(cat "$TD/compatibility_report.yml")
check "T3 compatibility form keeps Device field and four dropdowns" "grep -q 'id: device\$' <<<\"\$OUT\" && [ \$(grep -c 'type: dropdown' <<<\"\$OUT\") = 4 ]"

echo "$pass PASS, $fail FAIL"
[ "$fail" = 0 ]
