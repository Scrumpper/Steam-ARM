#!/bin/bash
# 2.1 with 2.2 merged: wizard Back walk and typeahead (from tests22.sh), Armv8.1 check of Install / Setup,
# override passed on to setup. Paths from paths.sh (~/.cache links of this version, or SARM_INST / SARM_CFG).
. "$(dirname "$0")/../paths.sh"
T=$SARM_TESTS/config-ui
APP=$SARM_CFG
INST=$SARM_INST
# private fake tree and menu copy: concurrent runs do not share them
UIP=$(mktemp -d /tmp/sarm-ui.XXXXXX); trap 'rm -rf "$UIP"' EXIT
export SARM_UI_FAKE=$UIP/fake SARM_UI_COPY=$UIP/app-copy.sh
R=$SARM_UI_FAKE
bash "$T/mkfake.sh" >/dev/null
pass=0; fail=0; skip=0
ok(){ echo "PASS $1"; pass=$((pass + 1)); }
bad(){ echo "FAIL $1"; fail=$((fail + 1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

check "bash -n menu" "bash -n $APP"
check "bash -n installer" "bash -n $INST"
check "embedded menu equals steam-arm-config file" "awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f' $INST | cmp -s - $APP"
V=$(sed -n 's/^SA_VERSION=//p' "$INST" | head -n 1)
check "version $V in installer (twice) and menu" "[ -n '$V' ] && grep -qx 'SA_VERSION=$V' $APP && [ \$(grep -c '^SA_VERSION=$V\$' $INST) = 2 ]"

# Wizard Back from parts: parts > Vulkan > page size > hardware, no screen skipped
WALK='SCREENS Install / Setup|Install: hardware|Install: page size|Install: Vulkan|Install: parts|Install: Vulkan|Install: page size|Install: hardware'
wiz(){ echo ". $T/harness.sh --help >/dev/null; DIALOG=$1; comp_recommended(){ echo x; }; setup_account(){ return 1; }${2:+; $2}; menu_setup"; }
drive(){ FAKE_NOT_INSTALLED=1 python3 "$T/ptydrive.py" "$@" | head -1; }
out=$(drive "$(wiz builtin)" '\r' '\r' '\r' '\x1b' '\x1b' '\x1b')
check "builtin: Esc walks parts > Vulkan > page size > hardware" "[ \"\$out\" = \"\$WALK\" ]"
out=$(drive "$(wiz builtin)" '\r' '\r' '\r' '\t\t\r' '\t\t\r' '\t\r')
check "builtin: Back button walks parts > Vulkan > page size > hardware" "[ \"\$out\" = \"\$WALK\" ]"
# second Esc 0.1 s / 1 s after the first, while Vulkan screen loads (3 s): dropped, Vulkan screen stays
SLOWVK="vk_summary(){ sleep 3; echo 'Mali-G610, panvk, API 1.3'; }"
for d in 0.1 1; do
  out=$(drive "$(wiz builtin "$SLOWVK")" '\r' '\r' @4 '\r' @4 '\x1b' "@$d" '!\x1b' @6)
  check "builtin: Esc typed ${d} s into Vulkan load does not skip it" "[ \"\${out#*Install: parts|}\" = 'Install: Vulkan' ]"
done
if command -v whiptail >/dev/null; then
  out=$(drive "$(wiz whiptail)" '\r' '\r' '\r' '\t\t\r' '\t\t\r' '\t\r')
  check "whiptail: Back button walks parts > Vulkan > page size > hardware" "[ \"\$out\" = \"\$WALK\" ]"
  out=$(drive "$(wiz whiptail "$SLOWVK")" '\r' '\r' @4 '\r' @4 '\t\t\r' @0.5 '!\t\t\r' @6)
  check "whiptail: Back typed into Vulkan load does not skip it" "[ \"\${out#*Install: parts|}\" = 'Install: Vulkan' ]"
else
  echo "SKIP whiptail not installed"; skip=$((skip + 2))
fi

# Armv8.1 check of Install / Setup (harness points "/proc/ at the fake tree)
CPU=$R/proc/cpuinfo
LSEON='processor	: 0
Features	: fp asimd evtstrm crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp'
LSEOFF='processor	: 0
Features	: fp asimd evtstrm crc32 cpuid

processor	: 1
Features	: fp asimd evtstrm crc32 cpuid atomics'
# screens shown by menu_setup: ui_msg / setup_hardware stubbed to print their titles
ms(){ bash -c ". $T/harness.sh --help >/dev/null; ui_msg(){ echo \"MSG \$1|\$2\"; }; setup_hardware(){ echo HW; return 1; }; ui_info(){ :; }; ui_yesno(){ echo \"YESNO \$1|\$2\"; [ \"\${NO:-0}\" = 0 ]; }; menu_setup" 2>&1; }
printf '%s\n' "$LSEOFF" > "$CPU"
out=$(unset STEAM_ARM_ALLOW_ARMV80; ms)
check "Install / Setup: no atomics -> x86 client screen, then hardware screen" "printf '%s\n' \"\$out\" | grep -q '^YESNO Install: x86 client|This CPU has no Armv8.1 atomics (LSE)' && printf '%s\n' \"\$out\" | grep -qx HW && ! printf '%s\n' \"\$out\" | grep -q '^MSG'"
check "Install / Setup x86 screen: issue 13288, x86 client, way back to native" "printf '%s\n' \"\$out\" | grep -q 'steam-for-linux #13288' && printf '%s\n' \"\$out\" | grep -q \"installs\" && printf '%s\n' \"\$out\" | grep -q 'Maintenance > Client type'"
out=$(unset STEAM_ARM_ALLOW_ARMV80; NO=1 ms)
check "Install / Setup x86 screen: Back -> no hardware screen" "printf '%s\n' \"\$out\" | grep -q '^YESNO Install: x86 client' && ! printf '%s\n' \"\$out\" | grep -qx HW"
out=$(export STEAM_ARM_ALLOW_ARMV80=1; ms)
check "Install / Setup: no atomics + STEAM_ARM_ALLOW_ARMV80=1 -> hardware screen" "printf '%s\n' \"\$out\" | grep -qx HW && ! printf '%s\n' \"\$out\" | grep -q '^MSG'"
printf '%s\n' "$LSEON" > "$CPU"
out=$(unset STEAM_ARM_ALLOW_ARMV80; ms)
check "Install / Setup: atomics -> hardware screen" "printf '%s\n' \"\$out\" | grep -qx HW && ! printf '%s\n' \"\$out\" | grep -q '^MSG'"
rm -f "$CPU"
out=$(unset STEAM_ARM_ALLOW_ARMV80; ms)
check "Install / Setup: no cpuinfo Features -> hardware screen" "printf '%s\n' \"\$out\" | grep -qx HW"
# override reaches the installer: run_installer through stub ui_run
ri(){ bash -c ". $T/harness.sh --help >/dev/null; ui_run(){ shift 2; printf '%s\n' \"\$*\"; }; ui_textstr(){ :; }; status_line(){ :; }; INST_ENV=(GAMEUSER=tester); run_installer T --keep" 2>/dev/null | head -1; }
out=$(export STEAM_ARM_ALLOW_ARMV80=1; ri)
check "run_installer passes STEAM_ARM_ALLOW_ARMV80=1 to setup" "printf '%s\n' \"\$out\" | grep -q 'env GAMEUSER=tester STEAM_ARM_ALLOW_ARMV80=1 .* --keep'"
out=$(unset STEAM_ARM_ALLOW_ARMV80; ri)
check "run_installer without override adds nothing" "printf '%s\n' \"\$out\" | grep -q 'env GAMEUSER=tester ' && ! printf '%s\n' \"\$out\" | grep -q ARMV80"
check "--help names STEAM_ARM_ALLOW_ARMV80" "bash $APP --help | grep -q 'STEAM_ARM_ALLOW_ARMV80=1'"

# View logs > Launcher log: empty log -> message, non-empty -> text, missing -> "No log found yet."
vl(){ bash -c ". $T/harness.sh --help >/dev/null; M=\$(mktemp); ui_menu(){ [ -s \$M ] && return 1; echo x > \$M; echo 1; }; ui_textstr(){ echo \"TEXT \$1|\$2\"; }; ui_msg(){ echo \"MSG \$1|\$2\"; }; LG=\$(arm_home)/steam-arm.log; $1; maint_logs; rm -f \$M" 2>&1; }
out=$(vl 'mkdir -p "${LG%/*}"; : > "$LG"')
check "View logs: empty launcher log -> empty message, no text screen" "[ \"\$out\" = 'MSG View logs|steam-arm.log is empty (launcher writes warnings only).' ]"
out=$(vl 'mkdir -p "${LG%/*}"; echo "warn: sample line" > "$LG"')
check "View logs: non-empty launcher log -> text screen with log" "[ \"\$out\" = 'TEXT Log: steam-arm.log|warn: sample line' ]"
out=$(vl 'rm -f "$LG"')
check "View logs: no launcher log -> No log found yet." "[ \"\$out\" = 'MSG View logs|No log found yet.' ]"

echo "passed $pass, failed $fail, skipped $skip"
[ "$fail" = 0 ]
