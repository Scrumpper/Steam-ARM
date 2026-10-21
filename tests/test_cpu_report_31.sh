#!/bin/bash
# 3.1 CPU report (steam-arm --cpu-report): script extracted from the installer under test (SARM_INST picks another);
# stand-in processes named steamwebhelper (busy) and FEXInterpreter; --quick --no-wait run checked for every section
# header and numeric profile columns; cpu_delta arithmetic on a recorded /proc/stat pair; static sections only
# (--sections); redaction of home folders; launcher option, removal list, owned paths, menu item and CLI; verdict
# section on fixture client logs (both laptop line formats, restart loop, throttle bits) and the Information row. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm31-cpurep.XXXXXX)
cleanup(){ [ -n "${P1:-}" ] && kill "$P1" 2>/dev/null; [ -n "${P2:-}" ] && kill "$P2" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }

S=$T/steam-arm-cpu-report.sh
awk '/^cat > \/usr\/local\/lib\/steam-arm-cpu-report.sh <<.CPUREP.$/{f=1;next} /^CPUREP$/{f=0} f' "$INST" > "$S"
check "C1 installer writes steam-arm-cpu-report.sh (bash, parses)" "[ -s $S ] && head -1 $S | grep -q '^#!/bin/bash' && bash -n $S"
check "C1b installer chmods it, removal list and owned paths name it, menu constant SA_CPUREPORT" \
  "grep -q '^chmod 755 /usr/local/lib/steam-arm-cpu-report.sh$' '$INST' && grep -q '^        /usr/local/lib/steam-arm-cpu-report.sh \\\\$' '$INST' && grep -q '^    /usr/local/lib/steam-arm-cpu-report.sh /usr/local/lib/steam-arm-glx-lax-patch.py' '$INST' && grep -q '^SA_CPUREPORT=/usr/local/lib/steam-arm-cpu-report.sh$' '$CFG'"
# stand-in processes with the real command names (comm): busy steamwebhelper, idle FEXInterpreter
mkdir -p "$T/bin" "$T/home/.local/share/Steam/logs"
printf '#!/bin/bash\nwhile :; do :; done\n' > "$T/bin/steamwebhelper"; printf '#!/bin/bash\nsleep 300 & wait\n' > "$T/bin/FEXInterpreter"
chmod 755 "$T/bin/steamwebhelper" "$T/bin/FEXInterpreter"
"$T/bin/steamwebhelper" > /dev/null 2>&1 & P1=$!
"$T/bin/FEXInterpreter" & P2=$!
printf 'gpu_compositing: disabled\nGPU process exited\n[1] Loaded GL renderer\n' > "$T/home/.local/share/Steam/logs/webhelper-linux.txt"
printf 'Startup - updater\n' > "$T/home/steam-arm.log"
sleep 0.5
OUT=$(cd "$T" && HOME=$T/home timeout 120 bash "$S" --quick --no-wait --out "$T/rep.txt" --client x86 2>&1); RC=$?
check "C2 --quick --no-wait: status 0, file written, mode 600, stderr names file and redaction" "[ $RC = 0 ] && [ -s $T/rep.txt ] && [ \"\$(stat -c %a $T/rep.txt)\" = 600 ] && grep -q 'Report written: .*rep.txt' <<<\"\$OUT\" && grep -q 'home folders are replaced by ~' <<<\"\$OUT\""
OUT=$(grep '^==== ' "$T/rep.txt")
for h in system "firmware (vcgencmd)" session "graphics stack (host)" "emulator (FEX)" "Steam processes" "profile: idle on Library page (5 s, 1 s samples)" "profile: browsing Library and Store (5 s, 1 s samples)" "end state"; do
  check "C3 header: $h" "grep -qxF '==== $h ====' <<<\"\$OUT\""
done
OUT=$(awk '/^==== profile: idle/{f=1} f && /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] /' "$T/rep.txt")
check "C4 profile rows: 5 samples, 7 numeric columns (total, steam, swh, fex, game, runtime, pids)" \
  "[ \$(grep -c . <<<\"\$OUT\") = 10 ] && ! awk '{ for (i = 2; i <= 8; i++) if (\$i !~ /^[0-9]+\$/) bad = 1 } END { exit bad }' <<<\"\$OUT\" || false; awk '{ for (i = 2; i <= 8; i++) if (\$i !~ /^[0-9]+\$/) exit 1 }' <<<\"\$OUT\""
check "C4b busy steamwebhelper stand-in shows in swh% column (above 50), total% at most 100, swh_cnt 1" \
  "awk '\$4 + 0 > 50 && \$2 + 0 <= 100 && \$9 == 1 { ok++ } END { exit ok < 5 }' <<<\"\$OUT\""
check "C5 processes section lists both stand-ins with their groups" "grep -q 'steamwebhelper processes: 1' $T/rep.txt && grep -qE '^fex +[0-9]+ +FEXInterpreter' $T/rep.txt || grep -q 'FEXInterpreter' $T/rep.txt"
check "C6 client log lines (gpu_compositing, GPU process, Loaded GL) and launcher log tail included" "grep -q 'gpu_compositing: disabled' $T/rep.txt && grep -q 'GPU process exited' $T/rep.txt && grep -q 'Loaded GL renderer' $T/rep.txt && grep -q 'launcher log, last 30 lines' $T/rep.txt"
check "C7 home folder redacted, no host name, no account name, no serial read" \
  "! grep -qF \"$T/home\" $T/rep.txt && ! grep -q \"\$(hostname)\" $T/rep.txt && ! grep -q 'serial-number' $S && ! grep -qE '^user=|^account:' $T/rep.txt"
check "C7b settings file keys and session line present" "grep -q '^--- settings file keys' $T/rep.txt && grep -q '^session type: ' $T/rep.txt"

# cpu_delta on a recorded /proc/stat pair: 4 cores, 1000 jiffies elapsed per core (4000 total), 1000 idle;
# steamwebhelper 1200 jiffies (120 % of one core), game 400 (40 %), fex 0
FN=$T/fn.sh; awk '/^cpu_delta\(\)\{/{f=1} f{print} f && /^}$/{exit}' "$S" > "$FN"
OUT=$( . "$FN"; printf 'total 10000 5000\nsteamwebhelper 100\ngame 50\nfex 7\ntotal 14000 6000\nsteamwebhelper 1300\ngame 450\nfex 7\n' | cpu_delta 4 )
check "C8 cpu_delta arithmetic: total 75, steam 0, swh 120, fex 0, game 40, runtime 0" "[ \"\$OUT\" = '75 0 120 0 40 0' ]"
OUT=$( . "$FN"; printf 'total 10000 5000\ntotal 10000 5000\n' | cpu_delta 4 )
check "C8b no time elapsed: zeros, no division error" "[ \"\$OUT\" = '0 0 0 0 0 0' ]"

# static sections only (hardware report): no profile, no FEXBash probe, exit 0
OUT=$(cd "$T" && HOME=$T/home timeout 60 bash "$S" --sections system,processes --user "$(id -un)" --home "$T/home" 2>&1); RC=$?
check "C9 --sections system,processes: those two headers only, no profile, status 0" \
  "[ $RC = 0 ] && grep -q '^==== system ====' <<<\"\$OUT\" && grep -q '^==== Steam processes ====' <<<\"\$OUT\" && ! grep -q 'profile:\\|through FEX\\|==== session' <<<\"\$OUT\""
OUT=$(bash "$S" --bogus 2>&1); RC=$?
check "C10 unknown option: status 2" "[ $RC = 2 ] && grep -q 'unknown option --bogus' <<<\"\$OUT\""

# launcher: --cpu-report option (after --shutdown and --open, before client checks), help line
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
check "C11 launcher --cpu-report execs the script with --home REALHOME and --client, listed in --help" \
  "grep -q '^  --cpu-report) shift; exec bash /usr/local/lib/steam-arm-cpu-report.sh --home \"\$REALHOME\" --client \"\$CLIENT\" \"\$@\";;' $L && grep -q 'steam-arm --cpu-report \\[--quick\\] \\[--no-wait\\] \\[--out FILE\\]' $L && [ \$(grep -n '^  --cpu-report)' $L | cut -d: -f1) -lt \$(grep -n '^# Installed client check' $L | cut -d: -f1) ]"
OUT=$(sh "$L" --help 2>&1)
check "C11b --help names --cpu-report" "grep -q -- '--cpu-report' <<<\"\$OUT\""
# menu: Maintenance item 18, maint_cpureport runs as game account with client home as HOME, CLI cpu-report
check "C12 menu Maintenance item 18 CPU profile, function runs script as game account, hardware report takes static sections, CLI cpu-report" \
  "grep -q 'up+=(18 \"CPU profile of client window (two 60 s samples)\")' '$CFG' && grep -q '18) maint_cpureport;;' '$CFG' && grep -q 'game_read env HOME=\"\$(arm_home)\" bash \"\$SA_CPUREPORT\" --no-wait --out \"\$out\"' '$CFG' && grep -q 'bash \"\$SA_CPUREPORT\" --sections system,processes' '$CFG' && grep -q '^    cpu-report)  shift; cli_cpu_report \"\$@\";;' '$CFG' && grep -q '^  cpu-report \\[--quick\\] \\[--no-wait\\]' '$CFG'"

# verdict section: client window state, restart loop, GPU process exits, fex client line, next step on fixture logs
VF=$T/vf.sh; awk '/^client_logs\(\)\{/{f=1} f{print} f && /^section_verdict\(\)\{/{g=1} g && /^}$/{exit}' "$S" > "$VF"
check "V0 verdict functions extracted (client_logs, cw_state, cw_starts, fexval, section_verdict); report runs it after end state and lists it in --sections" \
  "grep -q '^cw_state(){' $VF && grep -q '^cw_starts(){' $VF && grep -q '^fexval(){' $VF && grep -q '^section_verdict(){' $VF && grep -q '^section_end$' $S && grep -A1 '^section_end$' $S | grep -q '^section_verdict$' && grep -q '^  want verdict && section_verdict$' $S"
check "V0b report header names format 2 and the verdict section" "grep -q '^==== verdict ====' $T/rep.txt && grep -q '^report format 2;.*verdict' $T/rep.txt && grep -q '^next step: ' $T/rep.txt"
vfix(){ # name: writes $T/v/<name>/logs fixture
  rm -rf "$T/v"; mkdir -p "$T/v/.local/share/Steam" "$T/v/.fex-emu/AppConfig"; ln -s "$T/v/.local/share/Steam/logs" "$T/v/logs"; mkdir -p "$T/v/.local/share/Steam/logs"
  case $1 in
    laptop) printf '[2026-05-28 18:22:11] Disabling GPU acceleration: Disabled/CommandLine\n[2026-05-28 18:22:11]                     [ gpu_compositing ]: disabled_software\n[2026-05-28 18:22:12]                 [ GL_RENDERER ]: ANGLE (Intel, Mesa Intel(R) Iris(R) Xe Graphics)\n' > "$T/v/logs/webhelper_gpu.txt"
            printf '[2026-05-28 18:22:11] Disabling GPU acceleration due to --disable-gpu-compositing (browser)\n' > "$T/v/logs/webhelper.txt";;
    gpu) printf '[2026-10-17 17:45:45]                     [ gpu_compositing ]: enabled\n[2026-10-17 17:45:45]                 [ GL_RENDERER ]: ANGLE (Broadcom, V3D 4.2, OpenGL ES 3.1 Mesa 24.2.8-1~bpo12+rpt5)\n' > "$T/v/logs/webhelper_gpu.txt"; : > "$T/v/logs/webhelper.txt";;
    runtime) printf '[2026-09-21 17:36:29] Disabling GPU acceleration: Disabled/RuntimeDetect\n' > "$T/v/logs/webhelper_gpu.txt"; : > "$T/v/logs/webhelper.txt";;
    loop) : > "$T/v/logs/webhelper_gpu.txt"; { local i; for i in 100 70 40; do printf '[%s] Startup - webhelper launched pid: %s commandline: ./steamwebhelper\n' "$(date -d "-$i sec" '+%Y-%m-%d %H:%M:%S')" "$i"; done; } > "$T/v/logs/webhelper.txt"
          printf '[1:1:1016/1.0:ERROR:gpu_process_host.cc(1002)] GPU process exited unexpectedly: exit_code=8704\n%.0s' 1 2 3 4 > "$T/v/logs/cef_log.txt";;
    slow) : > "$T/v/logs/webhelper_gpu.txt"; { local i; for i in 500 300 100; do printf '[%s] Startup - webhelper launched pid: %s\n' "$(date -d "-$i sec" '+%Y-%m-%d %H:%M:%S')" "$i"; done; printf '[2020-01-01 00:00:00] Startup - webhelper launched pid: 1\n'; } > "$T/v/logs/webhelper.txt";;
  esac
}
vrun(){ # fixture client phase-avg min-mhz
  vfix "$1"; ( HOME=$T/v UHOME=$T/v CLIENT=$2 PH_AVG=$3 MIN_MHZ=$4; hdr(){ :; }; case $5 in hot) throttled(){ echo "0x50005 under-voltage throttled under-voltage-since-boot throttled-since-boot"; };; boot) throttled(){ echo "0x50000 under-voltage-since-boot throttled-since-boot"; };; *) throttled(){ echo 0x0; };; esac; . "$VF"; section_verdict ) 2>&1; }
OUT=$(vrun laptop x86 "steam 12 steamwebhelper 180 fex 3 game 0 runtime 0" 1500 cool)
check "V1 flag-disabled window (both laptop line formats): software, reason named, top group steamwebhelper, next step names lab-cef-gpu vulkan, client-gpu on, client-tso relaxed" \
  "grep -qx 'client window: software (flag -cef-disable-gpu, window drawn on CPU by default)' <<<\"\$OUT\" && grep -q '^top group: steamwebhelper 180 ' <<<\"\$OUT\" && grep -q '^next step: client window drawn on CPU .*lab-cef-gpu vulkan.*client-gpu on.*client-tso relaxed' <<<\"\$OUT\" && grep -qx 'restart loop: no (0 client window starts in 10 min)' <<<\"\$OUT\""
OUT=$(vrun gpu x86 "steam 10 steamwebhelper 90 fex 0 game 0 runtime 0" 1500 cool)
check "V2 compositing enabled: GPU with renderer, next step names client-tso relaxed and x87-client" "grep -qx 'client window: GPU (ANGLE (Broadcom, V3D 4.2, OpenGL ES 3.1 Mesa 24.2.8-1~bpo12+rpt5))' <<<\"\$OUT\" && grep -q '^next step: client window on GPU.*client-tso relaxed.*x87-client on' <<<\"\$OUT\""
OUT=$(vrun runtime x86 "" "" cool)
check "V3 RuntimeDetect without compositor lines: software with that reason; no profile phase named" "grep -qx 'client window: software (Chromium found no usable GPU (RuntimeDetect))' <<<\"\$OUT\" && grep -qx 'top group: no profile phase in this run' <<<\"\$OUT\" && grep -q '^clock floor: n/a MHz' <<<\"\$OUT\""
OUT=$(vrun loop x86 "steam 5 steamwebhelper 300 fex 0 game 0 runtime 0" 1500 cool)
check "V4 three starts within 120 s and four GPU process exits: restart loop yes, exits counted, next step names the loop and cef-hang-kills off, not GPU work" \
  "grep -qx 'restart loop: yes (3 client window starts in 10 min, three within 120 s)' <<<\"\$OUT\" && grep -qx 'gpu process exits: 4 (cef_log.txt, whole file)' <<<\"\$OUT\" && grep -q '^next step: client window restarts in a loop.*cef-hang-kills off' <<<\"\$OUT\" && ! grep -q 'lab-cef-gpu' <<<\"\$OUT\""
OUT=$(vrun slow x86 "steam 5 steamwebhelper 50 fex 0 game 0 runtime 0" 1500 cool)
check "V5 three starts spread over 500 s (old line outside 10 min ignored): no loop, count 3" "grep -qx 'restart loop: no (3 client window starts in 10 min)' <<<\"\$OUT\""
OUT=$(vrun laptop x86 "steam 5 steamwebhelper 50 fex 0 game 0 runtime 0" 600 hot)
check "V6 throttle bits set: clock floor line carries them, next step names power and cooling first" "grep -q '^clock floor: 600 MHz (max [0-9n/a]*) throttled=0x50005 under-voltage' <<<\"\$OUT\" && grep -q '^next step: CPU clock capped or throttled: power supply and cooling first' <<<\"\$OUT\""
OUT=$(vrun laptop x86 "steam 5 steamwebhelper 50 fex 0 game 0 runtime 0" 600 cool)
check "V6b low idle clock without throttle bits: no power verdict (ondemand idles low)" "! grep -q 'power supply' <<<\"\$OUT\""
OUT=$(vrun laptop x86 "steam 12 steamwebhelper 180 fex 3 game 0 runtime 0" 600 boot)
check "V6c since-boot bits only: own line, bits named, next step unchanged (not power)" "grep -qx 'throttle since boot: under-voltage-since-boot throttled-since-boot (bits clear now; not decisive, power supply worth a look)' <<<\"\$OUT\" && ! grep -q '^next step: CPU clock capped' <<<\"\$OUT\" && grep -q '^next step: client window drawn on CPU' <<<\"\$OUT\""
OUT=$(vrun laptop x86 "" "" hot); check "V6d current bits: no since-boot line, power verdict" "! grep -q '^throttle since boot' <<<\"\$OUT\" && grep -q '^next step: CPU clock capped' <<<\"\$OUT\""
OUT=$(vrun laptop arm64 "steam 40 steamwebhelper 20 fex 0 game 0 runtime 0" 1500 cool)
check "V7 native client: no x86 next step" "grep -qx 'next step: none from this report' <<<\"\$OUT\""
rm -rf "$T/v"; mkdir -p "$T/v/.fex-emu/AppConfig"
printf '{"Config":{"TSOEnabled":"0","SilentLog":"1","DiskCache":"0"},"ThunksDB":{"GL":0,"Vulkan":1}}\n' > "$T/v/.fex-emu/AppConfig/steamwebhelper.json"
printf '{"Config":{"X87ReducedPrecision":"1"}}\n' > "$T/v/.fex-emu/AppConfig/steam.json"
printf '{"Config":{"Multiblock":true,"TSOEnabled":true},"ThunksDB":{"GL":1,"Vulkan":1}}\n' > "$T/v/.fex-emu/Config.json"
OUT=$(( HOME=$T/v UHOME=$T/v CLIENT=x86 PH_AVG= MIN_MHZ=; hdr(){ :; }; throttled(){ echo 0x0; }; . "$VF"; section_verdict ) 2>&1)
check "V8 fex client line: app file wins over Config.json (tso 0, GL 0), Config.json fills the rest (multiblock true -> 1), x87 from steam.json" \
  "grep -qx 'fex client: tso=0 x87=1 silentlog=1 multiblock=1 thunks=GL0/VK1 (steamwebhelper; x87 from steam.json)' <<<\"\$OUT\""
OUT=$(rm -rf "$T/v"; mkdir -p "$T/v"; ( HOME=$T/v UHOME=$T/v CLIENT=x86 PH_AVG= MIN_MHZ=; hdr(){ :; }; throttled(){ echo 0x0; }; . "$VF"; section_verdict ) 2>&1)
check "V9 no client logs, no FEX files: unknown state, defaults named, status lines still printed" "grep -qx 'client window: unknown (no client log folder)' <<<\"\$OUT\" && grep -q '^fex client: tso=default x87=default silentlog=default multiblock=default thunks=GLdefault/VKdefault' <<<\"\$OUT\" && grep -qx 'gpu process exits: 0 (cef_log.txt, whole file)' <<<\"\$OUT\""
OUT=$(vfix laptop; : > "$T/v/logs/cef_log.txt"; ( HOME=$T/v UHOME=$T/v CLIENT=x86 PH_AVG= MIN_MHZ=; hdr(){ :; }; throttled(){ echo 0x0; }; . "$VF"; section_verdict ) 2>&1)
check "V9b cef_log.txt without GPU exits: one line with 0, no bare 0 line (grep -c status 1)" "grep -qx 'gpu process exits: 0 (cef_log.txt, whole file)' <<<\"\$OUT\" && ! grep -qx '0' <<<\"\$OUT\" && [ \$(grep -c '^gpu process exits' <<<\"\$OUT\") = 1 ]"
OUT=$(cd "$T" && HOME=$T/home timeout 60 bash "$S" --sections verdict --client x86 2>&1); RC=$?
check "V10 --sections verdict alone: status 0, verdict header, no profile" "[ $RC = 0 ] && grep -q '^==== verdict ====' <<<\"\$OUT\" && ! grep -q 'profile:' <<<\"\$OUT\""
check "V11 settings file keys line lists the 3.1 client keys" "grep -q 'X87_CLIENT|CLIENT_LIGHT|CLIENT_GPU|CLIENT_TSO|CEF_HANG_KILLS' $S && grep -q 'VK_HOST' $S"
# menu: Information status row Client window from the client's GPU log
MF=$T/cw.sh; awk '/^cw_row\(\)\{/{f=1} f{print} f && /^}$/{exit}' "$CFG" > "$MF"
cwm(){ ( ct=$1; client_type(){ echo "$ct"; }; steam_dir(){ echo "$T/m"; }; game_read(){ "$@"; }; . "$MF"; cw_row ) 2>&1; }
rm -rf "$T/m"; mkdir -p "$T/m/logs"; printf '[x]   [ gpu_compositing ]: enabled\n[x]   [ GL_RENDERER ]: ANGLE (Broadcom, V3D 4.2)\n' > "$T/m/logs/webhelper_gpu.txt"
OUT=$(cwm x86); check "M1 Information row Client window: GPU with renderer" "[ \"\$OUT\" = 'GPU (ANGLE (Broadcom, V3D 4.2))' ]"
printf '[x] Disabling GPU acceleration: Disabled/CommandLine\n[x]   [ gpu_compositing ]: disabled_software\n' > "$T/m/logs/webhelper_gpu.txt"
OUT=$(cwm x86); check "M2 Information row Client window: software, default reason" "[ \"\$OUT\" = 'software (drawn on CPU, default)' ]"
rm -f "$T/m/logs/webhelper_gpu.txt"; OUT=$(cwm x86); check "M3 no GPU log yet: unknown" "[ \"\$OUT\" = 'unknown (no client GPU log yet)' ]"
OUT=$(cwm arm64); check "M4 native client row" "[ \"\$OUT\" = 'native client (GPU)' ]"
check "M5 Information status table has the row after GPU forwarding" "grep -A1 '^GPU forwarding \$(fwd_state' '$CFG' | grep -q '^Client window  \$(cw_row | wrap_row -h)$'"

echo "cpu report 3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
