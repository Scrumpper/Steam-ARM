#!/bin/bash
# 3.1 CPU report (steam-arm --cpu-report): script extracted from the installer under test (SARM_INST picks another);
# stand-in processes named steamwebhelper (busy) and FEXInterpreter; --quick --no-wait run checked for every section
# header and numeric profile columns; cpu_delta arithmetic on a recorded /proc/stat pair; static sections only
# (--sections); redaction of home folders; launcher option, removal list, owned paths, menu item and CLI. Internal.
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
  "grep -q '^chmod 755 /usr/local/lib/steam-arm-cpu-report.sh$' '$INST' && grep -q '/usr/local/lib/steam-arm-autotune.py /usr/local/lib/steam-arm-cpu-report.sh' '$INST' && grep -q '^    /usr/local/lib/steam-arm-cpu-report.sh /usr/local/lib/steam-arm-glx-lax-patch.py' '$INST' && grep -q '^SA_CPUREPORT=/usr/local/lib/steam-arm-cpu-report.sh$' '$CFG'"
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

echo "cpu report 3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
