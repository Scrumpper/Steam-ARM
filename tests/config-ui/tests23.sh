#!/bin/bash
# 2.3 menu cases. Driver archive: Components split, Local copy, Custom archive, Download, CLI, status row, detect
# fallback. Caches: Maintenance item 8, clear all / one game, Games FEX code cache row. Automatic Windows build:
# Graphics item 3, Route per game labels, compat clear, CLI, report; Steam Deck line in Games. CPU drawing notice:
# Graphics item 4, CLI, backup keys, CPU! mark in game lists; Vulkan gaps row. x86 client: Information rows,
# Install x86 screen, Maintenance item 10 Client type, native check, Windows build tool, report block. Screens
# stubbed (answers from a queue file); setup is a stand-in that logs argv and driver archive env.
# Paths from paths.sh (SARM_CFG picks another menu copy); private fake tree of mkfake.sh.
. "$(dirname "$0")/../paths.sh"
T0=$SARM_TESTS/config-ui
CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm232-ui23.XXXXXX); trap 'rm -rf "$T"' EXIT
# private fake tree and menu copy: concurrent runs do not share them
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
R=$SARM_UI_FAKE
bash "$T0/mkfake.sh" >/dev/null
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; sed 's/^/     /' <<<"$OUT" | tail -n 8; fail=$((fail + 1)); fi; }

# harness copy pointed at $CFG
sed -e "s#^APP=.*#APP=\"$CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"

# fixtures: stand-in published archive, other file, custom archive with and without .sha256
PF=steam-arm-fex-mesa-test-x86_64-i386.tar.zst
D=$T/files; mkdir -p "$D"
echo published > "$T/$PF"; PSHA=$(sha256sum "$T/$PF" | cut -c1-64)
echo other > "$D/other.tar.zst"
echo custom > "$D/custom.tar.zst"; CSHA=$(sha256sum "$D/custom.tar.zst" | cut -c1-64)
cp "$D/custom.tar.zst" "$D/side.tar.zst"; echo "$CSHA  side.tar.zst" > "$D/side.tar.zst.sha256"
mkdir -p "$D/sp ace"; cp "$T/$PF" "$D/sp ace/$PF"

# setup stand-in: --detect with GPU_OFF / FAKE_DA, every other call logged with driver archive env
cat > "$T/inst.sh" <<'EOF'
#!/bin/bash
if [ "${1:-}" = --detect ]; then
  echo "family: mali-csf-v10"; echo "page size: 4096"
  [ -n "${FAKE_DA:-}" ] && echo "driver archive: $FAKE_DA"
  [ -n "${FAKE_CPU:-}" ] && echo "cpu: $FAKE_CPU"
  for c in glx-lax vk-spoof gpu-in-emulation tray; do v=on; [ "$c" = gpu-in-emulation ] && [ "${GPU_OFF:-0}" = 1 ] && v=off; echo "component $c: $v"; done
  exit 0
fi
[ "${1:-}" = --list ] && { for c in glx-lax vk-spoof gpu-in-emulation tray; do printf '  %-16s d\n' "$c"; done; exit 0; }
echo "SETUP $* TARBALL=${STEAM_ARM_PROVIDER_TARBALL:-} SHA=${STEAM_ARM_PROVIDER_SHA256:-}" >> "$INSTLOG"
EOF
chmod 755 "$T/inst.sh"
export INSTLOG=$T/inst.log Q=$T/q LOG=$T/ui.log

# screen stubs: ui_menu/ui_input/ui_yesno take answers from $Q (BACK or end of queue = Back); everything logged to $LOG
cat > "$T/stubs.sh" <<EOF
STEAM_ARM_INSTALLER=$T/inst.sh
SA_PROVIDER_FILE=$PF; SA_PROVIDER_SHA=$PSHA
EOF
cat >> "$T/stubs.sh" <<'EOF'
nxt(){ A=$(head -n 1 "$Q"); sed -i 1d "$Q"; }
ui_menu(){ printf 'MENU %s|%s|%s\n' "$1" "$2" "${*:3}" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; echo "$A"; }
ui_check(){ echo "CHECK $1" >> "$LOG"; return 1; }
ui_msg(){ printf 'MSG %s|%s\n' "$1" "$2" >> "$LOG"; }
ui_textstr(){ printf 'TEXT %s\n' "$1" >> "$LOG"; }
ui_info(){ :; }
ui_yesno(){ printf 'YESNO %s|%s\n' "$1" "$2" >> "$LOG"; nxt; [ "$A" = yes ]; }
ui_input(){ printf 'INPUT %s|%s|%s\n' "$1" "$2" "${3:-}" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; [ "$A" = PREFILL ] && A=${3:-}; echo "$A"; }
run_installer(){ printf 'RUN %s|%s|%s\n' "$1" "${INST_ENV[*]}" "${*:2}" >> "$LOG"; }
owner_home(){ echo "$R/home/tester"; }
EOF
# ui SNIPPET ANSWER...: fresh log, queue of answers, snippet run inside the harness
ui(){ local s=$1; shift; : > "$LOG"; : > "$INSTLOG"; printf '%s\n' "$@" > "$Q"
  bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; $s" >/dev/null 2>"$T/err"; RC=$?; OUT=$(cat "$LOG" "$T/err"); }
CONF=$R/etc/steam-arm/steam-arm.conf
cp "$CONF" "$T/conf.orig"
fresh(){ cp "$T/conf.orig" "$CONF"; printf '%s\n' "$@" >> "$CONF"; }
key(){ sed -n "s/^$1=//p" "$CONF"; }

# ---------- M1 Components split ----------
fresh; ui menu_components 1 BACK
check "M1 Components: two entries, Parts and Driver archive (now: Download)" "grep -q '^MENU Components|.* 1 Parts (checklist) 2 Driver archive for gpu-in-emulation (now: Download)\$' <<<\"\$OUT\""
check "M1 entry 1 opens parts checklist, then Components again, Back leaves" "[ \"\$(cut -c1-16 <<<\"\$OUT\" | paste -sd,)\" = 'MENU Components|,CHECK Components,MENU Components|' ]"
FAKE_NOT_INSTALLED=1 ui menu_components
check "M1 not installed: install offer first" "grep -q '^YESNO Steam ARM|Steam ARM is not installed' <<<\"\$OUT\" && ! grep -q '^MENU' <<<\"\$OUT\""
fresh "PROVIDER_LOCAL_FILE=$T/$PF"; ui menu_components
check "M1 entry label: Local file" "grep -q '(now: Local file)\$' <<<\"\$OUT\""
fresh "PROVIDER_LOCAL_FILE=$D/gone.tar.zst"; ui menu_components
check "M1 entry label: Local file, not found" "grep -q '(now: Local file, not found)\$' <<<\"\$OUT\""
fresh "PROVIDER_CUSTOM_SHA256=$CSHA" "PROVIDER_CUSTOM_FILE=$D/custom.tar.zst"; ui menu_components
check "M1 entry label: Custom (sha 8 chars...)" "grep -q '(now: Custom (sha ${CSHA:0:8}...))\$' <<<\"\$OUT\""
fresh; ui menu_driver_archive BACK
check "screen: Now and published archive lines, three choices" "grep -q 'Now: download' <<<\"\$OUT\" && grep -q \"Published archive: $PF, sha256 ${PSHA:0:12}...\" <<<\"\$OUT\" && grep -q 'dl Download from project release (recommended) local Local copy of published archive... custom Custom archive (own Mesa build)...' <<<\"\$OUT\""

# ---------- M2 Local copy ----------
fresh; ui menu_driver_archive local PREFILL yes BACK
check "M2 Local: path prefilled with file beside setup script" "grep -qx \"INPUT Driver archive: local copy|Path of $PF:|$T/$PF\" <<<\"\$OUT\""
check "M2 Local: matching file -> setup with TARBALL and --keep" "grep -qx \"RUN Driver archive|STEAM_ARM_PROVIDER_TARBALL=$T/$PF|--keep\" <<<\"\$OUT\""
fresh "PROVIDER_CUSTOM_SHA256=$CSHA" "PROVIDER_CUSTOM_FILE=$D/custom.tar.zst"; ui "da_local $PF $PSHA" "$T/$PF" yes
check "M2 Local over saved custom archive: setup with TARBALL, --keep --provider-default" "grep -qx \"RUN Driver archive|STEAM_ARM_PROVIDER_TARBALL=$T/$PF|--keep --provider-default\" <<<\"\$OUT\""
fresh "PROVIDER_CUSTOM_SHA256=$CSHA" "PROVIDER_CUSTOM_FILE=$D/custom.tar.zst"; ui "da_custom" "$D/side.tar.zst" yes yes
check "M2 Custom over saved custom: no --provider-default" "grep -q '^RUN Driver archive|.*STEAM_ARM_PROVIDER_SHA256=$CSHA|--keep\$' <<<\"\$OUT\""
fresh "PROVIDER_LOCAL_FILE=$D/sp" ; mkdir -p "$R/home/tester/Downloads"; cp "$T/$PF" "$R/home/tester/Downloads/$PF"; mv "$T/$PF" "$T/pf.keep"
ui "da_local $PF $PSHA" BACK
check "M2 Local: prefill falls back to Downloads folder" "grep -qx \"INPUT Driver archive: local copy|Path of $PF:|$R/home/tester/Downloads/$PF\" <<<\"\$OUT\""
mv "$T/pf.keep" "$T/$PF"
fresh; ui "da_local $PF $PSHA" "$T/$PF" no
check "M2 Local: Back on confirm -> setup not run" "grep -q '^YESNO Driver archive: local copy|Use this file' <<<\"\$OUT\" && ! grep -q '^RUN' <<<\"\$OUT\""
# real run_installer, ui_run stubbed: env reaches setup command line
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; unset -f run_installer; . <(sed -n '/^run_installer(){/,/^}/p' $T/app-copy.sh); ui_run(){ shift 2; printf 'CMD %s\n' \"\$*\"; }; status_line(){ :; }; close_steam(){ return 0; }; printf '%s\n' '$T/$PF' yes > \$Q; da_local $PF $PSHA" 2>&1)
check "M2 Local: setup command gets STEAM_ARM_PROVIDER_TARBALL and --keep" "grep -q \"^CMD as_root env STEAM_ARM_PROVIDER_TARBALL=$T/$PF .*$T/inst.sh --keep\$\" <<<\"\$OUT\""

# ---------- M3 Local refusals ----------
fresh; ui "da_local $PF $PSHA" "$D/other.tar.zst" relative.tar.zst "$D/sp ace/$PF" "$D/none.tar.zst" BACK
check "M3 mismatch: sha message, back to prompt" "grep -q \"^MSG Driver archive: local copy|File does not match published archive (sha256 .*, expected ${PSHA:0:12}...)\" <<<\"\$OUT\""
check "M3 relative path refused" "grep -q '^MSG Driver archive: local copy|Path must be absolute' <<<\"\$OUT\""
check "M3 spaced path refused with move hint" "grep -q '^MSG Driver archive: local copy|Path may hold only letters, digits and . _ - + / (setup saves it)' <<<\"\$OUT\""
check "M3 missing file refused" "grep -q '^MSG Driver archive: local copy|$D/none.tar.zst is not a file.' <<<\"\$OUT\""
check "M3 setup never run, prompt shown again each time" "! grep -q '^RUN' <<<\"\$OUT\" && [ \$(grep -c '^INPUT' <<<\"\$OUT\") = 5 ]"
cp "$T/$PF" "$D/locked.tar.zst"; chmod 000 "$D/locked.tar.zst"
if [ -r "$D/locked.tar.zst" ]; then echo "PASS M3 unreadable file case skipped (runs as root)"; pass=$((pass + 1))
else
  fresh; ui "da_local $PF $PSHA" "$D/locked.tar.zst" no BACK
  check "M3 unreadable file: asks before reading as administrator" "grep -q \"^YESNO Driver archive|$D/locked.tar.zst is not readable by account\" <<<\"\$OUT\" && ! grep -q '^RUN' <<<\"\$OUT\""
fi

# ---------- M4 Custom archive ----------
fresh; ui da_custom "$D/side.tar.zst" yes yes
check "M4 Custom with .sha256 file: sha shown, setup gets path and sha" "grep -q \"^YESNO Driver archive: custom|Expected SHA-256, from $D/side.tar.zst.sha256:\" <<<\"\$OUT\" && grep -qx \"RUN Driver archive|STEAM_ARM_PROVIDER_TARBALL=$D/side.tar.zst STEAM_ARM_PROVIDER_SHA256=$CSHA|--keep\" <<<\"\$OUT\""
check "M4 Custom: warning names Download as way back" "grep -q 'until Download is picked here' <<<\"\$OUT\""
fresh; ui da_custom "$D/custom.tar.zst" "$PSHA" "$D/custom.tar.zst" short "$D/custom.tar.zst" "$(tr a-f A-F <<<"$CSHA")" yes
check "M4 Custom typed sha: wrong -> differs message; short -> format message" "grep -q '^MSG Driver archive: custom|Checksum differs: file has $CSHA, expected $PSHA. Nothing changed.' <<<\"\$OUT\" && grep -q '^MSG Driver archive: custom|SHA-256 must be 64 characters' <<<\"\$OUT\""
check "M4 Custom typed sha (upper case accepted): setup gets lower-case sha" "grep -qx \"RUN Driver archive|STEAM_ARM_PROVIDER_TARBALL=$D/custom.tar.zst STEAM_ARM_PROVIDER_SHA256=$CSHA|--keep\" <<<\"\$OUT\" && [ \$(grep -c '^RUN' <<<\"\$OUT\") = 1 ]"

# ---------- M5 gpu-in-emulation off ----------
fresh; sed -i 's/gpu-in-emulation,//' "$CONF"; sed -i 's/^COMPONENTS_OFF=/&gpu-in-emulation,/' "$CONF"
OUT0=$(GPU_OFF=1; export GPU_OFF; ui "da_local $PF $PSHA" "$T/$PF" yes yes; echo "$OUT")
OUT=$OUT0
check "M5 gpu-in-emulation off: asks to turn it on" "grep -q '^YESNO Driver archive|gpu-in-emulation is off. Turn it on with this file?' <<<\"\$OUT\""
check "M5 setup gets --select with gpu-in-emulation added" "grep -q '^RUN Driver archive|STEAM_ARM_PROVIDER_TARBALL=$T/$PF|--select=.*gpu-in-emulation' <<<\"\$OUT\""
OUT=$(GPU_OFF=1; export GPU_OFF; ui "da_local $PF $PSHA" "$T/$PF" yes no; echo "$OUT")
check "M5 Back on turn-on question: setup not run" "! grep -q '^RUN' <<<\"\$OUT\""

# ---------- M6 Download ----------
fresh "PROVIDER_LOCAL_FILE=$T/$PF"; ui da_download
check "M6 Download with saved local file: key removed, no setup run" "[ -z \"\$(key PROVIDER_LOCAL_FILE)\" ] && ! grep -q '^RUN' <<<\"\$OUT\" && grep -q '^MSG Driver archive|Driver archive: download from project release on next build' <<<\"\$OUT\""
fresh "PROVIDER_CUSTOM_SHA256=$CSHA" "PROVIDER_CUSTOM_FILE=$D/custom.tar.zst"; ui da_download yes
check "M6 Download with custom archive: setup --keep --provider-default" "grep -qx 'RUN Driver archive||--keep --provider-default' <<<\"\$OUT\""
fresh; ui da_download
check "M6 Download, nothing saved: message only" "grep -qx 'MSG Driver archive|Already set to download.' <<<\"\$OUT\" && ! grep -q '^RUN' <<<\"\$OUT\""

# ---------- M7 CLI ----------
cli(){ : > "$INSTLOG"; OUT=$(bash -c ". $T/harness.sh --help >/dev/null; STEAM_ARM_INSTALLER=$T/inst.sh; SA_PROVIDER_FILE=$PF; SA_PROVIDER_SHA=$PSHA; main $*" 2>&1); RC=$?; OUT="$OUT
$(cat "$INSTLOG")"; }
fresh; cli driver-archive
check "M7 CLI: no argument -> usage, exit 2" "[ $RC = 2 ] && grep -q 'usage: steam-arm-config driver-archive' <<<\"\$OUT\""
cli driver-archive local
check "M7 CLI: local without file -> exit 2" "[ $RC = 2 ]"
cli driver-archive custom "$D/custom.tar.zst" nothex
check "M7 CLI: custom with bad sha -> exit 2" "[ $RC = 2 ]"
cli driver-archive status
check "M7 CLI: status download" "[ $RC = 0 ] && grep -qx 'driver archive: download' <<<\"\$OUT\""
cli driver-archive local "$D/other.tar.zst"
check "M7 CLI: local mismatch -> exit 1, setup not run" "[ $RC = 1 ] && grep -q 'does not match published archive' <<<\"\$OUT\" && ! grep -q '^SETUP' <<<\"\$OUT\""
cli driver-archive local "$T/$PF"
check "M7 CLI: local match -> setup --keep with TARBALL" "[ $RC = 0 ] && grep -qx \"SETUP --keep TARBALL=$T/$PF SHA=\" <<<\"\$OUT\""
cli driver-archive custom "$D/custom.tar.zst" "$CSHA"
check "M7 CLI: custom -> setup --keep with TARBALL and SHA" "[ $RC = 0 ] && grep -qx \"SETUP --keep TARBALL=$D/custom.tar.zst SHA=$CSHA\" <<<\"\$OUT\""
fresh "PROVIDER_LOCAL_FILE=$T/$PF"; cli driver-archive download
check "M7 CLI: download with saved local -> key removed, no setup" "[ $RC = 0 ] && [ -z \"\$(key PROVIDER_LOCAL_FILE)\" ] && ! grep -q '^SETUP' <<<\"\$OUT\""
fresh "PROVIDER_CUSTOM_SHA256=$CSHA"; cli driver-archive download
check "M7 CLI: download with custom -> setup --keep --provider-default" "grep -qx 'SETUP --keep --provider-default TARBALL= SHA=' <<<\"\$OUT\""
fresh "PROVIDER_CUSTOM_SHA256=$CSHA" "PROVIDER_CUSTOM_FILE=$D/custom.tar.zst"; cli driver-archive local "$T/$PF"
check "M7 CLI: local with saved custom -> setup --keep --provider-default with TARBALL" "[ $RC = 0 ] && grep -qx \"SETUP --keep --provider-default TARBALL=$T/$PF SHA=\" <<<\"\$OUT\""
fresh; sed -i 's/gpu-in-emulation,//' "$CONF"; sed -i 's/^COMPONENTS_OFF=/&gpu-in-emulation,/' "$CONF"; GPU_OFF=1 cli driver-archive local "$T/$PF"
check "M7 CLI: gpu-in-emulation off -> refused, names components command" "[ $RC = 1 ] && grep -q 'gpu-in-emulation is off; add it with steam-arm-config components' <<<\"\$OUT\" && ! grep -q '^SETUP' <<<\"\$OUT\""
OUT=$(bash "$CFG" --help)
check "M7 --help lists driver-archive command" "grep -q 'driver-archive status|download|local FILE|custom FILE SHA256' <<<\"\$OUT\""

# ---------- M8 status row ----------
# row text with wrapped continuation lines (15-space indent) joined back
srow(){ OUT=$(bash -c ". $T/harness.sh --help >/dev/null; info_status" 2>&1 \
  | awk '/^Driver archive/ { f = 1; printf "%s", $0; next } f && /^               / { printf "%s", substr($0, 16); next } f { exit }'); }
fresh; srow
check "M8 status row: download" "[ \"\$OUT\" = 'Driver archive download' ]"
fresh "PROVIDER_LOCAL_FILE=$T/$PF"; srow
check "M8 status row: local file path" "[ \"\$OUT\" = 'Driver archive local file $T/$PF' ]"
fresh "PROVIDER_LOCAL_FILE=$D/gone.tar.zst"; srow
check "M8 status row: local file, not found" "[ \"\$OUT\" = 'Driver archive local file $D/gone.tar.zst, not found' ]"
fresh "PROVIDER_CUSTOM_SHA256=$CSHA" "PROVIDER_CUSTOM_FILE=$D/custom.tar.zst" "PROVIDER_LOCAL_FILE=$T/$PF"; srow
check "M8 status row: custom wins over local" "[ \"\$OUT\" = 'Driver archive custom $D/custom.tar.zst' ]"
fresh; OUT=$(bash -c ". $T/harness.sh --help >/dev/null; info_status" 2>&1 | grep -n '' | grep -E ':(Mali tree|Driver archive|Components on) ' | cut -d: -f2 | cut -c1-14 | paste -sd,)
check "M8 status row between Mali tree and Components on" "[ \"\$OUT\" = 'Mali tree     ,Driver archive,Components on ' ]"

# ---------- M9 published archive from --detect, else constants ----------
pub(){ OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; da_pub" 2>&1); }
OUT=$(FAKE_DA="steam-arm-fex-mesa-27.0.1-x86_64-i386.tar.zst $CSHA"; export FAKE_DA; pub; echo "$OUT")
check "M9 da_pub: installer's driver archive line (detect_get driverarchive)" "[ \"\$OUT\" = 'steam-arm-fex-mesa-27.0.1-x86_64-i386.tar.zst $CSHA' ]"
pub
check "M9 da_pub: installer without the line -> built-in constants" "[ \"\$OUT\" = '$PF $PSHA' ]"
OUT=$(FAKE_DA="bad name; rm $CSHA"; export FAKE_DA; pub; echo "$OUT")
check "M9 da_pub: malformed line -> built-in constants" "[ \"\$OUT\" = '$PF $PSHA' ]"
OUT=$(sed -n 's/^SA_PROVIDER_SHA=//p' "$CFG")
check "M9 menu constant equals installer PROVIDER_SHA256" "[ -n \"\$OUT\" ] && grep -qx \"PROVIDER_SHA256=\$OUT\" \"$(dirname "$CFG")/steam-arm-install.sh\""

# ---------- C caches: Maintenance > Caches, Games > FEX code cache ----------
bash "$T0/mkfake.sh" >/dev/null
H=$R/home/tester; S=$H/.local/share/steam-arm/.local/share/Steam; L2="$R/media/Game Drive/SteamLibrary"
mkdir -p "$T/cbin"; printf '#!/bin/sh\ncase "$*" in *SteamLaunch*) [ "${FAKE_GAME:-0}" = 1 ];; *) exit 1;; esac\n' > "$T/cbin/pgrep"; chmod 755 "$T/cbin/pgrep"
mkc(){ mkdir -p "$S/steamapps/shadercache/312520/fex-emu" "$L2/steamapps/shadercache/1036240/fex-emu"
  head -c 65536 /dev/urandom > "$S/steamapps/shadercache/312520/fex-emu/a.foz"
  head -c 262144 /dev/urandom > "$L2/steamapps/shadercache/1036240/fex-emu/a.foz"; }
# game account = this account, so cache commands run in this process
cu(){ local s=$1; shift; PATH="$T/cbin:$PATH" ui "game_user(){ id -un; }; $s" "$@"; }
mkc; cu menu_maintenance 8 BACK BACK
check "C1 Maintenance: item 8 Caches after item 7" "grep -q '^MENU Maintenance|.*7 Check for new version 8 Caches (sizes, clear FEX code caches)' <<<\"\$OUT\""
check "C1 item 8 opens Caches screen with summary rows" "grep -q '^MENU Caches|FEX code cache, Linux games' <<<\"\$OUT\" && grep -q '^Steam shader cache' <<<\"\$OUT\" && grep -q 'list Sizes per game all Clear FEX code caches of all games game Clear FEX code cache of one game...\$' <<<\"\$OUT\""
check "C1 Back from Caches: Maintenance again, cursor on 8" "grep -q '^MENU Caches|' <<<\"\$OUT\" && [ \$(grep -c '^MENU Maintenance' <<<\"\$OUT\") = 2 ] && grep '^MENU Maintenance' <<<\"\$OUT\" | tail -n 1 | grep -q -- '--default 8 '"
cu menu_caches all no BACK
check "C2 Clear all, Back on confirm: nothing deleted" "grep -q '^YESNO Caches|Delete FEX code caches of all games (' <<<\"\$OUT\" && [ -f '$S/steamapps/shadercache/312520/fex-emu/a.foz' ] && [ -f '$L2/steamapps/shadercache/1036240/fex-emu/a.foz' ]"
check "C2 confirm text keeps Steam shader caches" "grep -q 'Steam shader caches stay.' <<<\"\$OUT\""
cu menu_caches list BACK
check "C3 Sizes per game: text screen, then Caches again" "grep -q '^TEXT Caches' <<<\"\$OUT\" && [ \$(grep -c '^MENU Caches|' <<<\"\$OUT\") = 2 ]"
cu menu_caches game 312520 yes BACK
check "C4 one game: list largest first with names" "grep -q '^MENU Caches: one game|FEX code cache of which game?|1036240 .*Jelly Brawl 312520 .*Rain World\$' <<<\"\$OUT\""
check "C4 one game: only that game's cache deleted, freed message" "[ ! -e '$S/steamapps/shadercache/312520/fex-emu' ] && [ -f '$L2/steamapps/shadercache/1036240/fex-emu/a.foz' ] && grep -q '^MSG Caches|Freed ' <<<\"\$OUT\""
cu menu_caches game BACK BACK
check "C4 one game list, Back: nothing deleted" "grep -q '^MENU Caches: one game|' <<<\"\$OUT\" && [ -f '$L2/steamapps/shadercache/1036240/fex-emu/a.foz' ] && ! grep -q '^YESNO' <<<\"\$OUT\""
mkc; OUT=$(FAKE_GAME=1; export FAKE_GAME; cu menu_caches all yes BACK; echo "$OUT")
check "C5 game running: message, nothing deleted" "grep -q '^MSG Caches|A game is running in Steam ARM' <<<\"\$OUT\" && [ -f '$S/steamapps/shadercache/312520/fex-emu/a.foz' ]"
cu menu_caches all yes BACK
check "C6 Clear all: every FEX cache deleted, Steam shader cache folders stay" "[ ! -e '$S/steamapps/shadercache/312520/fex-emu' ] && [ ! -e '$L2/steamapps/shadercache/1036240/fex-emu' ] && [ -d '$S/steamapps/shadercache/312520' ] && grep -q '^MSG Caches|Freed .*Folders deleted: 2' <<<\"\$OUT\""
cu menu_caches all game BACK
check "C7 nothing found: messages, no confirm" "grep -q '^MSG Caches|No FEX code caches found.' <<<\"\$OUT\" && grep -q '^MSG Caches|No FEX code caches of games found.' <<<\"\$OUT\" && ! grep -q '^YESNO' <<<\"\$OUT\""
FAKE_NOT_INSTALLED=1 cu menu_caches
check "C8 not installed: install offer" "grep -q '^YESNO Steam ARM|Steam ARM is not installed' <<<\"\$OUT\" && ! grep -q '^MENU' <<<\"\$OUT\""
TC=$R/etc/steam-arm/titles.conf; VT=$S/steamapps/common/FEX-Emu/VERSIONS.txt
cu "game_menu 312520" diskcache on BACK
check "C9 Linux game: FEX code cache and automatic tuning rows between args and rules, [off]" "grep -m1 -A1 '^MENU Game: Rain World' <<<\"\$OUT\" | paste -sd ' ' | grep -q 'args Extra arguments      \\[none\\] diskcache FEX code cache       \\[off\\] mesa Mesa, route B        \\[default\\] autotune Automatic tuning     \\[off\\] rules Rules'"
check "C9 choice screen: text, FEX-2609.1 has no needs-tool note" "grep -q '^MENU FEX code cache|Stores translated code of this game for its next start.' <<<\"\$OUT\" && grep -q '^Now: off. FEX tool: FEX-2609.1.|' <<<\"\$OUT\" && ! grep -q 'Needs FEX-2609.1' <<<\"\$OUT\""
check "C9 On written to profile, row then shows [on]" "grep -qE '^312520 .*diskcache=on' '$TC' && grep -A1 '^MENU Game: Rain World' <<<\"\$OUT\" | tail -n 2 | paste -sd ' ' | grep -q 'FEX code cache       \\[on\\]'"
echo "FEX-2607-76-gabc1234" > "$VT"
HAD=$(grep -c '^312520 .*diskcache=on' "$TC")
cu "game_diskcache 312520" default
check "C10 FEX-2607 tool: note says setting kept until tool update" "grep -q 'Now: on. FEX tool: FEX-2607. Needs FEX-2609.1 or newer; setting is kept and applies once Steam updates tool.' <<<\"\$OUT\""
check "C10 Default removes setting" "[ $HAD = 1 ] && ! grep -q 'diskcache' '$TC'"
cu "game_diskcache 312520" BACK
check "C10 Back: nothing written" "grep -q '^MENU FEX code cache|' <<<\"\$OUT\" && ! grep -q 'diskcache' '$TC'"
mkdir -p "$S/steamapps/compatdata/219150/pfx"
cu "game_menu 219150" BACK
check "C11 Windows game: no FEX code cache row" "grep -q '^MENU Game: Hotline Miami 2' <<<\"\$OUT\" && ! grep -q 'diskcache' <<<\"\$OUT\""
# built-in screens on a pty: Maintenance, 8, Caches screen, Back, Back
mkc
OUT=$(python3 "$T0/ptydrive.py" ". $T/harness.sh --help >/dev/null; game_user(){ id -un; }; DIALOG=builtin; menu_maintenance; echo MENU-DONE" '8' '\r' @2 '\x1b' @1 '\x1b' 2>&1)
check "C13 built-in screens: Caches opens from Maintenance 8, summary rows and items shown, Back twice leaves" "grep -q 'Caches (sizes, clear FEX code caches)' <<<\"\$OUT\" && grep -q \"Steam shader cache .*Steam's own, not cleared here\" <<<\"\$OUT\" && grep -q 'Clear FEX code cache of one game' <<<\"\$OUT\" && grep -q MENU-DONE <<<\"\$OUT\""
W66=$(PATH="$T/cbin:$PATH" bash -c ". $T/harness.sh --help >/dev/null; game_user(){ id -un; }; cache_summary \"\$(cache_scan)\"" 2>/dev/null | awk '{ if (length > m) m = length } END { print m + 0 }')
check "C13 summary rows fit 66 columns (widest $W66)" "[ $W66 -gt 40 ] && [ $W66 -le 66 ]"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; fixing_text")
check "C12 Help, Fixing a game: clear cache entry" "grep -q 'FEX code cache on: Maintenance > Caches, clear that' <<<\"\$OUT\""

# ---------- R automatic Windows build (Graphics item 3, Route per game, CLI, report) and Steam Deck hint ----------
bash "$T0/mkfake.sh" >/dev/null
cp "$CONF" "$T/conf.orig"
RS=$R/home/tester/.local/share/steam-arm/.local/share/Steam
printf '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n\t\t\t\t\t"400"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"proton-stable-arm64"\n\t\t\t\t\t}\n\t\t\t\t\t"312520"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"steamlinuxruntime"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n' > "$RS/config/config.vdf"
# helper stand-ins: autobuild list from $T/ab-list, calls logged; appinfo prints one line per id from $T/ai-out
cat > "$T/ab.py" <<EOF
import sys
open("$T/ab-calls.log", "a").write(" ".join(sys.argv[1:]) + "\n")
if sys.argv[1] == "list":
    sys.stdout.write(open("$T/ab-list").read())
elif sys.argv[1] == "drop":
    print("auto-build: record of app %s removed; rule may apply again at next start of Steam ARM" % sys.argv[3])
EOF
cat > "$T/ai.py" <<EOF
import sys
for a in sys.argv[2:]:
    print(a + "\t" + open("$T/ai-out").read().strip() if a == "400" else a + "\tunknown\tunknown\tunknown")
EOF
ablist(){ printf '%s\n' 'auto-build	on' 'rule	source32	proton-stable-arm64	mali-csf-v10	2607	32-bit Source engine' "gate	source32	${1:--}" \
  'app	400	auto	source32	32-bit Source engine Linux build stops at loading screen under emulation' \
  'app	1036240	suggest	source32	GPU family broadcom-v3d not tested' 'app	312520	kept	source32	build chosen in Steam or settings menu (steamlinuxruntime)' \
  'record	400	source32	proton-stable-arm64	2026-10-06' > "$T/ab-list"; }
ablist; printf 'Verified\tunknown\tnative\n' > "$T/ai-out"
echo "SA_AUTOBUILD_PY=$T/ab.py; SA_APPINFO_PY=$T/ai.py" > "$T/rstubs.sh"
ru(){ local s=$1; shift; rm -f "$T/ab-calls.log"; ui ". $T/rstubs.sh; $s" "$@"; }
rcli(){ rm -f "$T/ab-calls.log"; OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/rstubs.sh; main $*" 2>&1); RC=$?; }

fresh; ru menu_graphics BACK
check "R1 Graphics: item 3 Automatic Windows build (now: on), absent key = on" "grep -q '^MENU Graphics|.* 2 Route per game 3 Automatic Windows build (now: on) 4 CPU drawing notice (now: off)\$' <<<\"\$OUT\""
fresh AUTO_BUILD=off; ru menu_graphics BACK
check "R1 Graphics: AUTO_BUILD=off -> (now: off)" "grep -q '3 Automatic Windows build (now: off) 4 ' <<<\"\$OUT\""
fresh; ru menu_graphics 3 BACK BACK
check "R2 item 3 opens screen: state, rule line, count, Turn off / Back" "grep -q '^YESNO Automatic Windows build|Automatic Windows build: on' <<<\"\$OUT\" && grep -q '^  32-bit Source engine (GPU family mali-csf-v10, FEX tool up to 2607)\$' <<<\"\$OUT\" && grep -q '^Set for: 1 game. Route per game shows and undoes each.\$' <<<\"\$OUT\" && grep -q 'Turning off keeps titles already set' <<<\"\$OUT\""
check "R2b Graphics 3 text: download in background once client is up, as notice (box re-test B6)" "grep -q '^Steam downloads Windows build in background once client is up.\$' <<<\"\$OUT\" && ! grep -q 'at next start of game' <<<\"\$OUT\""
check "R2 Back on screen: key not written, Graphics again" "[ -z \"\$(key AUTO_BUILD)\" ] && [ \$(grep -c '^MENU Graphics' <<<\"\$OUT\") = 2 ]"
fresh; ru graphics_auto_build yes
check "R2 Turn off: AUTO_BUILD=off written, message keeps titles set" "[ \"\$(key AUTO_BUILD)\" = off ] && grep -q '^MSG Graphics|Automatic Windows build: off. Titles already set keep Windows build' <<<\"\$OUT\""
fresh AUTO_BUILD=off; ru graphics_auto_build yes
check "R2 Turn on from off: AUTO_BUILD=on written (explicit, restore-safe)" "[ \"\$(key AUTO_BUILD)\" = on ] && grep -q 'Automatic Windows build: on. Applies at next start of Steam ARM.' <<<\"\$OUT\""
ablist 'GPU family broadcom-v3d not tested'; fresh; ru graphics_auto_build BACK
check "R2 gate closed on this system: suggestion-only line" "grep -q '^On this system: suggestion only (GPU family broadcom-v3d not tested).\$' <<<\"\$OUT\""
ablist
# shared content: manifest with LastOwner 0 (base files kept for another title) is not a game (box re-test B5)
printf '"AppState"\n{\n\t"appid"\t\t"220"\n\t"name"\t\t"Shared Base"\n\t"installdir"\t\t"SharedBase"\n\t"LastOwner"\t\t"0"\n}\n' > "$RS/steamapps/appmanifest_220.acf"
printf '"AppState"\n{\n\t"appid"\t\t"221"\n\t"name"\t\t"Owned Title"\n\t"installdir"\t\t"Owned"\n\t"LastOwner"\t\t"76561190000000000"\n}\n' > "$RS/steamapps/appmanifest_221.acf"
fresh; ui 'games_list >> $LOG'
check "R3a games_list: LastOwner 0 manifest left out, owned title with LastOwner listed (box re-test B5)" "! grep -q '^220	' <<<\"\$OUT\" && grep -q '^221	Owned Title	Owned\$' <<<\"\$OUT\" && grep -q '^400	Portal	Portal\$' <<<\"\$OUT\""
fresh; ru "pick_game T gfx" BACK
check "R3b Route per game list: no shared-content entry" "! grep -q ' 220 Shared Base' <<<\"\$OUT\" && grep -q ' 221 Owned Title' <<<\"\$OUT\""
rm -f "$RS/steamapps/appmanifest_220.acf" "$RS/steamapps/appmanifest_221.acf"
fresh; ru "pick_game T gfx" BACK
check "R3 Route per game list: Windows (auto) for title set by rule, others unchanged" "grep -qE '^MENU T\\|.* 400 Portal +Windows \\(auto\\) ' <<<\"\$OUT\" && grep -qE ' 312520 Rain World +Linux build$' <<<\"\$OUT\""
check "R3 list read once per screen (one helper call)" "[ \$(grep -c '^list ' $T/ab-calls.log) = 1 ]"
fresh; ru graphics_game 400 BACK
check "R4 title set by rule: now line says set automatically, reason and undo lines" "grep -q '^MENU Graphics: Portal|App 400. Route now: Windows build (Proton), set automatically.' <<<\"\$OUT\" && grep -q '^Reason: 32-bit Source engine Linux build stops at loading screen under emulation.\$' <<<\"\$OUT\" && grep -q '^Automatic lets rule set it again; Force Linux build keeps Linux build.|' <<<\"\$OUT\""
fresh; ru graphics_game 1036240 BACK
check "R5 suggested title: suggestion line, windows item marked (suggested)" "grep -q '^Windows build suggested: 32-bit Source engine Linux build fails under emulation (GPU family broadcom-v3d not tested).|' <<<\"\$OUT\" && grep -q 'windows Force Windows build, Proton (needs Steam closed) (suggested)' <<<\"\$OUT\""
fresh; ru graphics_game 312520 BACK
check "R5 title kept (forced build): no suggestion, no automatic text" "! grep -q 'suggested\\|set automatically' <<<\"\$OUT\""
fresh; ru "graphics_compat(){ echo \"GC \$*\" >> $LOG; }; graphics_game" 400 auto
check "R6 Route per game > Automatic on rule's title: forced build cleared through compat clear" "grep -q '^GC 400 clear Portal' <<<\"\$OUT\""
rcli compat 400 clear
check "R6 compat clear, mapping = rule's record: mapping removed, record dropped" "[ $RC = 0 ] && grep -q 'compatmap 400 --remove' <<<\"\$OUT\" && grep -q 'record of app 400 removed' <<<\"\$OUT\" && grep -q '^drop .*/Steam 400\$' $T/ab-calls.log"
rcli compat 312520 clear
check "R6 compat clear, hand-set tool: record left alone (R7)" "[ $RC = 0 ] && grep -q 'compatmap 312520 --remove' <<<\"\$OUT\" && ! grep -q '^drop' $T/ab-calls.log"
rcli compat 400 linux
check "R6 compat linux keeps record (rule never re-applies)" "grep -q 'compatmap 400 steamlinuxruntime' <<<\"\$OUT\" && ! grep -qs '^drop' $T/ab-calls.log"
fresh; rcli auto-build off
check "R7 CLI auto-build off: key off, message" "[ $RC = 0 ] && [ \"\$(key AUTO_BUILD)\" = off ] && grep -qx 'automatic Windows build: off' <<<\"\$OUT\""
rcli auto-build on
check "R7 CLI auto-build on: key on" "[ $RC = 0 ] && [ \"\$(key AUTO_BUILD)\" = on ]"
rcli auto-build maybe
check "R7 CLI bad value: usage, exit 2, key unchanged" "[ $RC = 2 ] && grep -q 'usage: steam-arm-config auto-build \\[on|off\\]' <<<\"\$OUT\" && [ \"\$(key AUTO_BUILD)\" = on ]"
rcli auto-build
check "R7 CLI no value: state, rule, titles, records" "[ $RC = 0 ] && grep -qx 'automatic Windows build: on' <<<\"\$OUT\" && grep -qx 'rule source32: 32-bit Source engine, tool proton-stable-arm64, GPU family mali-csf-v10, FEX tool up to 2607' <<<\"\$OUT\" && grep -qx 'app 400 auto source32: 32-bit Source engine Linux build stops at loading screen under emulation' <<<\"\$OUT\" && grep -qx 'record app 400 source32 proton-stable-arm64 2026-10-06' <<<\"\$OUT\""
OUT=$(bash "$CFG" --help)
check "R8 --help lists auto-build and AUTO_BUILD key" "grep -q '^  auto-build \\[on|off\\]  ' <<<\"\$OUT\" && grep -q 'AUTO_BUILD=on|off' <<<\"\$OUT\""
fresh; OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/rstubs.sh; report_text" 2>&1 | grep '^Automatic build')
check "R9 hardware report: one line, counts only" "[ \"\$OUT\" = 'Automatic build on, 1 set, 1 suggested' ]"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; echo \"\$SA_BK_KEYS\"; for v in on off '' maybe; do rs_valid AUTO_BUILD \"\$v\" && echo \"ok:\$v\" || echo \"bad:\$v\"; done" 2>&1)
check "R10 backup keys carry AUTO_BUILD; restore accepts on, off, empty only" "grep -q 'GFX_DEFAULT AUTO_BUILD' <<<\"\$OUT\" && [ \"\$(grep -c '^ok:' <<<\"\$OUT\")\" = 3 ] && grep -qx 'bad:maybe' <<<\"\$OUT\""
fresh; ru "game_menu 400" BACK
check "R11 Windows game header: Steam Deck line, hint only" "grep -q '^MENU Game: Portal|App 400. Windows game (Proton): ' <<<\"\$OUT\" && grep -q '^Steam Deck: Verified (hint only: Steam Deck has other GPU).|' <<<\"\$OUT\""
check "R11 Frame value not shown (key unconfirmed)" "! grep -qi 'frame' <<<\"\$OUT\""
ru "game_menu 312520" BACK
check "R11 Linux game header: Steam Deck line (unknown)" "grep -q '^MENU Game: Rain World|App 312520. Settings apply from the next start of the game.\$' <<<\"\$OUT\" && grep -q '^Steam Deck: unknown (hint only: Steam Deck has other GPU).|' <<<\"\$OUT\""
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; SA_APPINFO_PY=$T/none.py; deck_hint 400" 2>&1)
check "R11 reader missing: unknown" "[ \"\$OUT\" = \$'unknown\\tunknown' ]"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/rstubs.sh; game_rules 400" 2>&1)
check "R12 Rules page: Steam Deck runtime line" "grep -qx 'Steam Deck runtime: native' <<<\"\$OUT\""
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; fixing_text")
check "R13 Fixing a game: switched-by-itself bullet" "grep -q '^- Title switched to Windows build by itself: automatic\$' <<<\"\$OUT\""
OUT=$(python3 "$T0/ptydrive.py" ". $T/harness.sh --help >/dev/null; . $T/rstubs.sh; DIALOG=builtin; menu_graphics; echo MENU-DONE" '3' '\r' @2 '\x1b' @1 '\x1b' @1 '\x1b' 2>&1)
check "R14 built-in screens: Graphics 3 opens Automatic Windows build screen, Back leaves" "grep -q 'Automatic Windows build (now: on)' <<<\"\$OUT\" && grep -q 'Set for: 1 game' <<<\"\$OUT\" && grep -q 'Turn off' <<<\"\$OUT\" && grep -q MENU-DONE <<<\"\$OUT\""

# ---------- P CPU drawing notice (Graphics item 4, CLI, backup keys), CPU mark in game lists, Vulkan gaps row ----------
bash "$T0/mkfake.sh" >/dev/null
cp "$CONF" "$T/conf.orig"
fresh; ru menu_graphics BACK
check "P1 Graphics: item 4 CPU drawing notice (now: off), absent key = off" "grep -q '^MENU Graphics|.* 3 Automatic Windows build (now: on) 4 CPU drawing notice (now: off)\$' <<<\"\$OUT\""
fresh CPU_NOTICE=on; ru menu_graphics BACK
check "P1 Graphics: CPU_NOTICE=on -> (now: on)" "grep -q ' 4 CPU drawing notice (now: on)\$' <<<\"\$OUT\""
fresh; ru menu_graphics 4 BACK BACK
check "P2 item 4 opens screen: state off, llvmpipe, scope and GoldSrc lines" "grep -q '^YESNO CPU drawing notice|CPU drawing notice: off' <<<\"\$OUT\" && grep -q 'draws on CPU (llvmpipe)' <<<\"\$OUT\" && grep -q '^Not for Windows games on ARM64 Proton or native ARM64 games.\$' <<<\"\$OUT\" && grep -q '^GoldSrc games get no notice' <<<\"\$OUT\""
check "P2 Back on screen: key not written, Graphics again" "grep -q '^YESNO CPU drawing notice' <<<\"\$OUT\" && [ -z \"\$(key CPU_NOTICE)\" ] && [ \$(grep -c '^MENU Graphics' <<<\"\$OUT\") = 2 ]"
check "P2 screen text fits 66 columns" "grep -q '^YESNO CPU drawing notice' <<<\"\$OUT\" && ! sed -n '/^YESNO CPU drawing notice/,/^MENU/p' <<<\"\$OUT\" | grep -v '^YESNO\\|^MENU' | awk 'length > 66' | grep -q ."
fresh; ru graphics_cpu_notice yes
check "P3 Turn on: CPU_NOTICE=on written, message" "[ \"\$(key CPU_NOTICE)\" = on ] && grep -q '^MSG Graphics|CPU drawing notice: on. Applies from the next game start.' <<<\"\$OUT\""
fresh CPU_NOTICE=on; ru graphics_cpu_notice yes
check "P3 Turn off: CPU_NOTICE=off written (explicit, restore-safe)" "[ \"\$(key CPU_NOTICE)\" = off ] && grep -q 'CPU drawing notice: off.' <<<\"\$OUT\""
fresh; rcli cpu-notice on
check "P4 CLI cpu-notice on: key on, message" "[ $RC = 0 ] && [ \"\$(key CPU_NOTICE)\" = on ] && grep -qx 'CPU drawing notice: on' <<<\"\$OUT\""
rcli cpu-notice off
check "P4 CLI cpu-notice off: key off" "[ $RC = 0 ] && [ \"\$(key CPU_NOTICE)\" = off ]"
rcli cpu-notice
check "P4 CLI no value: state" "[ $RC = 0 ] && grep -qx 'CPU drawing notice: off' <<<\"\$OUT\""
rcli cpu-notice maybe
check "P4 CLI bad value: usage, exit 2, key unchanged" "[ $RC = 2 ] && grep -q 'usage: steam-arm-config cpu-notice \\[on|off\\]' <<<\"\$OUT\" && [ \"\$(key CPU_NOTICE)\" = off ]"
OUT=$(bash "$CFG" --help)
check "P4 --help lists cpu-notice and CPU_NOTICE key" "grep -q '^  cpu-notice \\[on|off\\]  ' <<<\"\$OUT\" && grep -q 'CPU_NOTICE=on|off' <<<\"\$OUT\""
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; echo \"\$SA_BK_KEYS\"; for v in on off '' maybe; do rs_valid CPU_NOTICE \"\$v\" && echo \"ok:\$v\" || echo \"bad:\$v\"; done" 2>&1)
check "P5 backup keys carry CPU_NOTICE after AUTO_BUILD (then RUN_HISTORY of 3.0, SNAPSHOT_KEEP and UPDATE_CHECK_ON_OPEN of 3.1); restore accepts on, off, empty only" "grep -q 'GFX_DEFAULT AUTO_BUILD CPU_NOTICE RUN_HISTORY SNAPSHOT_KEEP UPDATE_CHECK_ON_OPEN\$' <<<\"\$OUT\" && [ \"\$(grep -c '^ok:' <<<\"\$OUT\")\" = 3 ] && grep -qx 'bad:maybe' <<<\"\$OUT\""
# game logs: 400 newest log CPU, 312520 newest GPU (older CPU log ignored), 219150 CPU log without id line ignored
L=$R/tmp
printf 'SteamAppId=312520\nsteam-arm: renderer: warning: GPU forwarding not active: rendering on CPU (llvmpipe); no GPU device in use, process a\n' > "$L/fex-compat-tool-3001.log"
printf 'SteamAppId=400\nsteam-arm: renderer: warning: GPU forwarding not active: rendering on CPU (llvmpipe); no GPU device in use, process hl2\n' > "$L/fex-compat-tool-3002.log"
printf 'SteamAppId=312520\nsteam-arm: renderer: GPU (panthor renderD128), forwarding to host driver, process RainWorld\n' > "$L/fex-compat-tool-3003.log"
printf 'steam-arm: renderer: warning: GPU forwarding not active: rendering on CPU (llvmpipe); x, process y\n' > "$L/fex-compat-tool-3004.log"
touch -d '2026-10-01 10:00' "$L/fex-compat-tool-3001.log"; touch -d '2026-10-02 10:00' "$L/fex-compat-tool-3002.log"
touch -d '2026-10-03 10:00' "$L/fex-compat-tool-3003.log"; touch -d '2026-10-04 10:00' "$L/fex-compat-tool-3004.log"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; cpu_apps" 2>&1)
check "P6 cpu_apps: newest log per title decides (400 only)" "[ \"\$OUT\" = 400 ]"
fresh; ru "pick_game T gfx" BACK
check "P6 Route per game: CPU! mark on 400, none on 312520" "grep -qE '^MENU T\\|.* 400 Portal +Windows \\(auto\\) +CPU! ' <<<\"\$OUT\" && grep -qE ' 312520 Rain World +Automatic$' <<<\"\$OUT\""
check "P6 list columns: name 36 wide, setting from column 38" "grep -oE ' 400 Portal +[^ ]' <<<\"\$OUT\" | awk '{ exit !(length(\$0) == 4 + 1 + 36 + 1 + 1) }'"
fresh; ru "pick_game T profile" BACK
check "P6 Games list: CPU! mark too" "grep -qE ' 400 Portal +.* CPU! ' <<<\"\$OUT\""
rm -f "$L"/fex-compat-tool-300[1-4].log
vg(){ OUT=$(bash -c "D=\$1; . $T/harness.sh --help >/dev/null; detect_raw(){ printf '%b' \"\$D\"; }; vk_gaps" _ "$1" 2>&1); }
vg 'family: mali-csf-v10\nvulkan features native: multiViewport shaderClipDistance\nvulkan features missing: fillModeNonSolid geometryShader shaderCullDistance robustBufferAccess2\n'
check "P7 Vulkan gaps: missing list, comma separated, wrapped under 15-column label" "[ \"\$(head -1 <<<\"\$OUT\" | sed 's/ *\$//')\" = 'fillModeNonSolid, geometryShader, shaderCullDistance,' ] && [ \"\$(sed -n 2p <<<\"\$OUT\")\" = '               robustBufferAccess2' ]"
vg 'family: x\nvulkan features native: a b\nvulkan features missing: none\n'
check "P7 Vulkan gaps: none -> driver has every feature" "[ \"\$OUT\" = 'none (driver has every feature vk-spoof covers)' ]"
vg 'family: x\nvulkan features: unknown (vulkaninfo not installed)\n'
check "P7 Vulkan gaps: unknown line passed through" "[ \"\$OUT\" = 'unknown (vulkaninfo not installed)' ]"
vg 'family: x\n'
check "P7 Vulkan gaps: setup without the lines -> unknown" "[ \"\$OUT\" = unknown ]"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; info_system" 2>&1)
check "P7 Information > System: Vulkan gaps row right after Vulkan" "grep -A1 '^Vulkan  ' <<<\"\$OUT\" | tail -1 | grep -q '^Vulkan gaps    '"
OUT=$(python3 "$T0/ptydrive.py" ". $T/harness.sh --help >/dev/null; . $T/rstubs.sh; DIALOG=builtin; menu_graphics; echo MENU-DONE" '4' '\r' @2 '\x1b' @1 '\x1b' @1 '\x1b' 2>&1)
check "P8 built-in screens: Graphics 4 opens CPU drawing notice screen, Back leaves" "grep -q 'CPU drawing notice (now: off)' <<<\"\$OUT\" && grep -q 'Turn on' <<<\"\$OUT\" && grep -q 'GoldSrc' <<<\"\$OUT\" && grep -q MENU-DONE <<<\"\$OUT\""

# ---------- G GE-Proton (Maintenance item 9, screen, file install, remove, Route per game, labels, CLI) ----------
bash "$T0/mkfake.sh" >/dev/null
cp "$CONF" "$T/conf.orig"
GS=$R/home/tester/.local/share/steam-arm/.local/share/Steam; GC=$GS/compatibilitytools.d
# helper from installer beside $CFG: settings file of fake tree, compatmap copy, Steam-running checks off
python3 - "$(dirname "$CFG")/steam-arm-install.sh" "$T" "$CONF" <<'EOF'
import sys
src, t, conf = sys.argv[1:4]
s = open(src).read()
def hd(start, end):
    i = s.find(start)
    return None if i < 0 else s[i + len(start):s.index("\n" + end + "\n", i) + 1]
cm = hd("cat > /usr/local/lib/steam-arm-compatmap.py <<'PYEOF'\n", "PYEOF")
open(t + "/cm.py", "w").write(cm.replace("if steam_up():", "if False:"))
ge = hd("cat > /usr/local/lib/steam-arm-geproton.py <<'GEPY'\n", "GEPY") or "import sys\nsys.exit('helper absent')\n"
ge = ge.replace('CONF = "/etc/steam-arm/steam-arm.conf"', "CONF = %r" % conf)
ge = ge.replace('COMPATMAP = "/usr/local/lib/steam-arm-compatmap.py"', "COMPATMAP = %r" % (t + "/cm.py"))
ge = ge.replace("def steam_up():\n", "def steam_up():\n    return False\n")
open(t + "/ge.py", "w").write(ge)
# check stand-in: release line from $T/ge-check, every other action to helper copy
open(t + "/gechk.py", "w").write("import runpy, sys\nif sys.argv[1] == 'check':\n    print(open(%r).read().strip())\n"
                                 "    sys.exit(0)\nrunpy.run_path(%r, run_name='__main__')\n" % (t + "/ge-check", t + "/ge.py"))
EOF
# synthetic builds 11-6 and 11-7 with .sha512sum beside each
python3 - "$T/gedl" <<'EOF'
import hashlib, io, os, sys, tarfile
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
for tag in ("GE-Proton11-6", "GE-Proton11-7"):
    top = tag + "-aarch64"; p = os.path.join(d, top + ".tar.gz")
    with tarfile.open(p, "w:gz") as t:
        def add(n, data=b"", mode=0o644, dir=False):
            i = tarfile.TarInfo(n); i.mode = mode
            if dir: i.type = tarfile.DIRTYPE; t.addfile(i); return
            i.size = len(data); t.addfile(i, io.BytesIO(data))
        add(top, dir=True, mode=0o755)
        add(top + "/compatibilitytool.vdf", ('"compatibilitytools"\n{\n  "compat_tools"\n  {\n    "%s"\n    {\n      "install_path" "."\n    }\n  }\n}\n' % top).encode())
        add(top + "/toolmanifest.vdf", b'"manifest"\n{\n  "commandline" "/proton %verb%"\n  "require_tool_appid" "4185400"\n}\n')
        add(top + "/proton", b"#!/bin/sh\n", 0o755)
    open(p[:-7] + ".sha512sum", "w").write("%s  %s\n" % (hashlib.sha512(open(p, "rb").read()).hexdigest(), top + ".tar.gz"))
EOF
printf 'release\tGE-Proton11-7\t2026-09-16\t645786140\t2163383569\t99999999999\tnew\n' > "$T/ge-check"
echo "SA_GE_PY=$T/gechk.py" > "$T/gstubs.sh"
gu(){ local s=$1; shift; ui ". $T/gstubs.sh; $s" "$@"; }
gcli(){ OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/gstubs.sh; main $*" 2>&1); RC=$?; }
vdfmap(){ printf '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n' > "$GS/config/config.vdf"
  for m in "$@"; do printf '\t\t\t\t\t"%s"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n' "${m%%:*}" "${m#*:}" >> "$GS/config/config.vdf"; done
  printf '\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n' >> "$GS/config/config.vdf"; }
vdfmap

fresh; gu menu_maintenance BACK
check "G1 Maintenance: item 9 GE-Proton (ARM64), optional (now: none) after item 8" "grep -q '^MENU Maintenance|.*8 Caches (sizes, clear FEX code caches) 9 GE-Proton (ARM64), optional (now: none) 10 Client type (now: native ARM64) 11 Report how last game ran 12 Run history (now: off) 14 Show what is new' <<<\"\$OUT\""
fresh; ui "SA_GE_PY=$T/none.py; menu_maintenance" 9 BACK
check "G1 helper missing (2.2 setup): label (now: helper missing), screen says Update / Repair" "grep -q '9 GE-Proton (ARM64), optional (now: helper missing)' <<<\"\$OUT\" && grep -q '^MSG GE-Proton (ARM64)|Helper is missing. Run Maintenance > Update / Repair.' <<<\"\$OUT\""
fresh; gu menu_maintenance 9 BACK BACK
check "G2 item 9 opens screen: third-party line, state rows, four actions" "grep -q '^MENU GE-Proton (ARM64)|Optional Proton build by GloriousEggroll, not by Valve.' <<<\"\$OUT\" && grep -q '^Installed here: none\$' <<<\"\$OUT\" && grep -q '^Other copies:   none\$' <<<\"\$OUT\" && grep -q '^Steam Linux Runtime 4.0 (Arm64): absent|' <<<\"\$OUT\" && grep -q 'check Check for newest release (nothing downloads) install Install newest release... file Install from downloaded file... remove Remove version...\$' <<<\"\$OUT\""
check "G2 Back from screen: Maintenance again, cursor on 9" "[ \$(grep -c '^MENU Maintenance' <<<\"\$OUT\") = 2 ] && grep '^MENU Maintenance' <<<\"\$OUT\" | tail -n 1 | grep -q -- '--default 9 '"
check "G2 screen text fits 66 columns" "! sed -n '/^MENU GE-Proton (ARM64)|/,/|/p' <<<\"\$OUT\" | sed 's/|.*//' | awk 'length > 66' | grep -q ."
fresh; gu ge_check
check "G3 check: newest build, sizes, installed none, nothing installed" "grep -q '^MSG GE-Proton (ARM64)|Newest ARM64 build: GE-Proton11-7 (2026-09-16), download 646 MB, about 2.2 GB on disk. Installed here: none.\$' <<<\"\$OUT\" && [ ! -e '$GC/GE-Proton11-7-aarch64' ]"
# install failed screen: log path on its own line, not hard-broken inside its name (box re-test B12)
fresh; gu "SA_CACHE=$T/c; DIALOG=whiptail; ui_size(){ UW=75; }; need_root(){ :; }; ui_run(){ echo 'steam-arm-geproton: GitHub answer not understood.' > \"\$2\"; return 2; }; ui_textstr(){ printf 'TEXT %s|%s\n' \"\$1\" \"\$2\" >> \$LOG; }; ge_do --newest"
GL=$(ls "$T"/c/geproton-*.log 2>/dev/null | head -n 1)
check "G4b failed screen: Full output label, then whole log path on one line" "[ -n '$GL' ] && grep -q '^TEXT GE-Proton (ARM64): failed|Install stopped (status 2)' <<<\"\$OUT\" && grep -qx 'Full output:' <<<\"\$OUT\" && grep -qxF '$GL' <<<\"\$OUT\" && grep -qx 'GitHub answer not understood.' <<<\"\$OUT\""
rm -rf "$T/c"
# text box on 30-row terminal: 20-line System text fits without scrolling (box re-test F12 note)
W=$T/wt; mkdir -p "$W"; printf '#!/bin/sh\nprintf "%%s\\n" "$@" > %s/args\n' "$W" > "$W/whiptail"; cp "$W/whiptail" "$W/dialog"; chmod 755 "$W/whiptail" "$W/dialog"
TX=$(seq -f 'row %g' 1 20)
bash -c ". $T/harness.sh --help >/dev/null; PATH=$W:\$PATH; DIALOG=whiptail; stty(){ echo '30 100'; }; ui_text System <(printf '%s\n' \"$TX\")" >/dev/null 2>&1
OUT=$(cat "$W/args")
check "TB1 whiptail, 30 rows: 20-line text box 27 rows high, no scroll" "! grep -qx -- '--scrolltext' <<<\"\$OUT\" && [ \"\$(tail -n 2 <<<\"\$OUT\" | head -n 1)\" = 27 ]"
bash -c ". $T/harness.sh --help >/dev/null; PATH=$W:\$PATH; DIALOG=dialog; stty(){ echo '30 100'; }; ui_text System <(printf '%s\n' \"$TX\")" >/dev/null 2>&1
OUT=$(cat "$W/args")
check "TB2 dialog, 30 rows: 20-line text box 27 rows high" "[ \"\$(tail -n 2 <<<\"\$OUT\" | head -n 1)\" = 27 ]"
bash -c ". $T/harness.sh --help >/dev/null; PATH=$W:\$PATH; DIALOG=dialog; stty(){ echo '24 80'; }; ui_text System <(printf '%s\n' \"$TX\")" >/dev/null 2>&1
OUT=$(cat "$W/args")
check "TB3 dialog, 24 rows: height 22 as before" "[ \"\$(tail -n 2 <<<\"\$OUT\" | head -n 1)\" = 22 ]"
fresh; gu ge_install no
check "G4 install: confirm names size, third-party note and sha512, default Back; Back installs nothing" "grep -q '^YESNO GE-Proton (ARM64)|Install GE-Proton11-7 (download 646 MB, about 2.2 GB on disk) into ~/.local/share/steam-arm/.local/share/Steam/compatibilitytools.d?' <<<\"\$OUT\" && grep -q '^Build by GloriousEggroll, not supported by Valve. File checked against its published sha512.\$' <<<\"\$OUT\" && [ ! -e '$GC/GE-Proton11-7-aarch64' ]"
printf 'release\tGE-Proton11-7\t2026-09-16\t645786140\t2163383569\t1000\tnew\n' > "$T/ge-check"
fresh; gu ge_install yes
check "G4 free space below 5 x download: refused before confirm" "grep -q '^MSG GE-Proton (ARM64)|Needs about 3.2 GB free in ~/.local/share/steam-arm; 0 MB free.' <<<\"\$OUT\" && ! grep -q '^YESNO' <<<\"\$OUT\""
printf 'release\tGE-Proton11-7\t2026-09-16\t645786140\t2163383569\t99999999999\tcurrent\n' > "$T/ge-check"
fresh; gu ge_install yes
check "G4 newest already installed here: current message, no confirm" "grep -q '^MSG GE-Proton (ARM64)|GE-Proton11-7 is installed and current.' <<<\"\$OUT\" && ! grep -q '^YESNO' <<<\"\$OUT\""
printf 'release\tGE-Proton11-7\t2026-09-16\t645786140\t2163383569\t99999999999\tnew\n' > "$T/ge-check"
fresh CLIENT=x86; gu ge_install yes
check "G5 x86 client: refusal text, nothing asked" "grep -q '^MSG GE-Proton (ARM64)|GE-Proton ARM64 runs with native ARM64 client only. This system runs x86 client through emulation; Windows games use x86 Proton there.' <<<\"\$OUT\" && ! grep -q '^YESNO' <<<\"\$OUT\""
fresh CLIENT=x86; gu ge_install_file
check "G5 x86 client: file install refused too" "grep -q 'native ARM64 client only' <<<\"\$OUT\" && ! grep -q '^INPUT' <<<\"\$OUT\""
fresh; gu "page_size(){ echo 16384; }; ge_install"
check "G5 16K pages: refusal text" "grep -q '^MSG GE-Proton (ARM64)|GE-Proton ARM64 needs 4K memory pages (this system: 16K).' <<<\"\$OUT\""
fresh; gu ge_install_file relative.tar.gz "$T/gedl/other.tar.gz" "$T/gedl/GE-Proton11-5-aarch64.tar.gz" BACK
check "G6 file: relative path, wrong name, missing file refused, prompt again" "grep -q 'Path must be absolute' <<<\"\$OUT\" && grep -q 'File name must be GE-Proton<version>-aarch64.tar.gz, as published.' <<<\"\$OUT\" && grep -q 'GE-Proton11-5-aarch64.tar.gz is not a file.' <<<\"\$OUT\" && [ \$(grep -c '^INPUT' <<<\"\$OUT\") = 4 ]"
cp "$T/gedl/GE-Proton11-7-aarch64.tar.gz" "$T/gedl/GE-Proton11-8-aarch64.tar.gz"
fresh; gu ge_install_file "$T/gedl/GE-Proton11-8-aarch64.tar.gz" BACK
check "G6 file without .sha512sum beside it: message names checksum file" "grep -q 'Checksum file GE-Proton11-8-aarch64.sha512sum not found beside it. Download both files from GE-Proton' <<<\"\$OUT\""
rm -f "$T/gedl/GE-Proton11-8-aarch64.tar.gz"
fresh; gu ge_install_file "$T/gedl/GE-Proton11-6-aarch64.tar.gz" yes
check "G7 file install 11-6: folder and marker in compatibilitytools.d, restart + per-game message, SLR line" "[ -f '$GC/GE-Proton11-6-aarch64/.steam-arm-ge' ] && grep -q '^MSG GE-Proton (ARM64)|GE-Proton11-6 installed. Restart Steam ARM to list it. Pick it per game: Graphics > Route per game > ge, or game Properties > Compatibility in Steam.' <<<\"\$OUT\" && grep -q '^First start of game set to it downloads Steam Linux Runtime 4.0 (Arm64).' <<<\"\$OUT\""
check "G7 install log in menu cache folder" "ls '$R'/tmp/cache/geproton-*.log >/dev/null 2>&1"
fresh; gu menu_maintenance BACK
check "G8 label after install: (now: GE-Proton11-6)" "grep -q '9 GE-Proton (ARM64), optional (now: GE-Proton11-6) 10 Client type (now: native ARM64) 11 Report how last game ran 12 Run history (now: off) 14 Show what is new' <<<\"\$OUT\""
vdfmap 400:GE-Proton11-6-aarch64 312520:steamlinuxruntime
fresh; gu ge_install_file "$T/gedl/GE-Proton11-7-aarch64.tar.gz" yes yes
check "G9 newer file install: move offer names 1 game, default Keep both" "grep -q '^YESNO GE-Proton (ARM64)|Move 1 game from GE-Proton11-6 to GE-Proton11-7 and remove GE-Proton11-6?' <<<\"\$OUT\""
check "G9 Move and remove: game on 11-7, 11-6 gone, other mapping kept" "grep -A1 '\"400\"' '$GS/config/config.vdf' | tail -1 | grep -q . && grep -A3 '\"400\"' '$GS/config/config.vdf' | grep -q GE-Proton11-7-aarch64 && grep -A3 '\"312520\"' '$GS/config/config.vdf' | grep -q steamlinuxruntime && [ ! -e '$GC/GE-Proton11-6-aarch64' ] && grep -q '^MSG GE-Proton (ARM64)|GE-Proton11-6 removed; 1 game moved to GE-Proton11-7.' <<<\"\$OUT\""
mkdir -p "$GC/GE-Proton10-34"; echo '"compat_tools" { "GE-Proton10-34" {} }' > "$GC/GE-Proton10-34/compatibilitytool.vdf"
fresh; gu menu_maintenance BACK
check "G8 label with hand copy: newest first, 1 more" "grep -q '9 GE-Proton (ARM64), optional (now: GE-Proton11-7, 1 more) 10 Client type (now: native ARM64) 11 Report how last game ran 12 Run history (now: off) 14 Show what is new' <<<\"\$OUT\""
fresh; gu menu_geproton BACK
check "G2 screen: installed here with size and games, other copy left alone" "grep -q '^Installed here: GE-Proton11-7 ([0-9]* MB, 1 game)\$' <<<\"\$OUT\" && grep -q '^Other copies:   GE-Proton10-34 (not installed here, left alone)\$' <<<\"\$OUT\""
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; . $T/gstubs.sh; info_status" 2>&1)
check "G10 Information > Steam ARM status: GE-Proton row last" "[ \"\$(tail -n 1 <<<\"\$OUT\")\" = 'GE-Proton      GE-Proton11-7, 1 more' ]"
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; for t in GE-Proton11-7-aarch64 GE-Proton10-34 proton_11 proton-stable-arm64 steamlinuxruntime; do compat_label \$t; done" 2>&1)
check "G11 compat_label: GE builds without -aarch64, Valve tools unchanged" "[ \"\$(paste -sd'|' <<<\"\$OUT\")\" = 'Windows build (GE-Proton11-7)|Windows build (GE-Proton10-34)|Windows build (Proton)|Windows build (Proton)|Linux build' ]"
fresh; gu "pick_game T gfx" BACK
check "G11 Route per game list: short GE label in 24-column setting field" "grep -qE ' 400 Portal +Windows, GE-Proton11-7 ' <<<\"\$OUT\" && grep -oE ' 400 Portal +[^ ]' <<<\"\$OUT\" | awk '{ exit !(length(\$0) == 4 + 1 + 36 + 1 + 1) }'"
fresh; gu graphics_game 400 BACK
check "G12 Route per game: ge entry with newest build installed here, starred when mapped to GE" "grep -q '^MENU Graphics: Portal|App 400. Route now: Windows build (GE-Proton11-7).' <<<\"\$OUT\" && grep -q 'ge Force Windows build, GE-Proton11-7 (needs Steam closed) \\*\$' <<<\"\$OUT\""
fresh; gu 'as_root(){ echo "ROOT $*"; }; graphics_game' 312520 ge
check "G12 ge chosen: compat ge runs, message names build" "grep -q '^MSG Graphics|Rain World: Windows build with GE-Proton11-7.' <<<\"\$OUT\" && grep -q '^ROOT bash .* compat 312520 ge$' <<<\"\$OUT\""
gcli compat 400 ge
check "G13 CLI compat ge: compatmap gets newest build installed here" "[ $RC = 0 ] && grep -qx 'compatmap 400 GE-Proton11-7-aarch64' <<<\"\$OUT\""
gcli ge-proton
check "G14 CLI ge-proton: status rows, sizes measured" "[ $RC = 0 ] && grep -q '^Installed here: GE-Proton11-7 (' <<<\"\$OUT\" && grep -q '^Other copies:   GE-Proton10-34' <<<\"\$OUT\" && grep -q '^Steam Linux Runtime 4.0 (Arm64): absent' <<<\"\$OUT\""
gcli ge-proton check
check "G14 CLI ge-proton check: text line" "[ $RC = 0 ] && grep -q '^Newest ARM64 build: GE-Proton11-7 (2026-09-16)' <<<\"\$OUT\""
gcli ge-proton bogus
check "G14 CLI unknown action: usage, exit 2" "[ $RC = 2 ] && grep -q '^usage: steam-arm-config ge-proton' <<<\"\$OUT\""
fresh CLIENT=x86; gcli ge-proton install --file "$T/gedl/GE-Proton11-7-aarch64.tar.gz"
check "G14 CLI install on x86 client: helper refuses, exit 1" "[ $RC = 1 ] && grep -q 'native ARM64 client only' <<<\"\$OUT\""
fresh; OUT=$(bash -c ". $T/harness.sh --help >/dev/null; SA_GE_PY=$T/none.py; main ge-proton" 2>&1); RC=$?
check "G14 CLI helper missing: message, exit 1" "[ $RC = 1 ] && grep -q 'helper $T/none.py missing' <<<\"\$OUT\""
OUT=$(bash "$CFG" --help)
check "G14 --help lists ge-proton commands and compat ge" "grep -q '^  ge-proton \\[status\\]' <<<\"\$OUT\" && grep -q '^  ge-proton install \\[TAG\\] \\[--file FILE.tar.gz\\] \\[--move\\]' <<<\"\$OUT\" && grep -q '^  ge-proton remove TAG' <<<\"\$OUT\" && grep -q '^  compat <appid> linux|windows|ge|clear' <<<\"\$OUT\""
fresh; gu ge_remove GE-Proton11-7 default
check "G15 remove: only builds installed here listed, games question, Steam's default drops mapping, folder gone" "grep -q '^MENU GE-Proton: remove|Remove which version? Its folder is deleted.|GE-Proton11-7 ' <<<\"\$OUT\" && ! grep -q 'GE-Proton10-34 ' <<<\"\$(grep '^MENU GE-Proton: remove|Remove which' <<<\"\$OUT\")\" && grep -q '^MENU GE-Proton: remove|1 game use GE-Proton11-7:|other Move them to GE-Proton10-34 default' <<<\"\$OUT\" && [ ! -e '$GC/GE-Proton11-7-aarch64' ] && ! grep -q '\"400\"' '$GS/config/config.vdf' && [ -d '$GC/GE-Proton10-34' ]"
fresh; gu ge_remove
check "G15 nothing installed here: message, hand copy left" "grep -q '^MSG GE-Proton (ARM64)|No GE-Proton build installed by this menu. Copies installed by hand are left alone.' <<<\"\$OUT\""
fresh; gu graphics_game 312520 BACK
check "G12 Route per game, hand copy only: ge entry offers it (newest other copy)" "grep -q 'ge Force Windows build, GE-Proton10-34 (needs Steam closed)\$' <<<\"\$OUT\""
rm -rf "$GC"
fresh; gu graphics_game 312520 BACK
check "G12 no GE build: no ge entry" "grep -q '^MENU Graphics: Rain World' <<<\"\$OUT\" && ! grep -q ' ge Force' <<<\"\$OUT\""
gcli compat 400 ge
check "G13 CLI compat ge without build: exit 1, install hint" "[ $RC = 1 ] && grep -q 'no GE-Proton build installed (steam-arm-config ge-proton install)' <<<\"\$OUT\""
OUT=$(python3 "$T0/ptydrive.py" ". $T/harness.sh --help >/dev/null; . $T/gstubs.sh; DIALOG=builtin; menu_maintenance; echo MENU-DONE" '9' '\r' @2 '\x1b' @1 '\x1b' 2>&1)
check "G16 built-in screens: GE-Proton opens from Maintenance 9, state rows and actions shown, Back twice leaves" "grep -q 'GE-Proton (ARM64), optional (now: none)' <<<\"\$OUT\" && grep -q 'Steam Linux Runtime 4.0 (Arm64): absent' <<<\"\$OUT\" && grep -q 'Install from downloaded file' <<<\"\$OUT\" && grep -q MENU-DONE <<<\"\$OUT\""

# ---------- x86 client (CLIENT in settings file; fake /proc/cpuinfo) ----------
CPUF=$R/proc/cpuinfo; mkdir -p "$R/proc"
v80(){ printf 'processor\t: 0\nFeatures\t: fp asimd evtstrm crc32 cpuid\nCPU part\t: 0xd08\n' > "$CPUF"; }
v82(){ printf 'processor\t: 0\nFeatures\t: fp asimd evtstrm crc32 atomics cpuid\nCPU part\t: 0xd0b\n' > "$CPUF"; }
XS="need_root(){ :; }; close_steam(){ :; }"
v80; fresh CLIENT=x86 CLIENT_SET=auto CLIENT_PROBE=1788652215:lse; ui "info_status | sed -n '1,6p' >> \$LOG"
check "XM1 status: Client type row after Installed (x86 by CPU rule); FEX tool row says system FEX" "sed -n 2p <<<\"\$OUT\" | grep -qx 'Client type    x86 through emulation (CPU without Armv8.1 atomics)' && grep -qx 'FEX tool       not used (x86 client runs on system FEX)' <<<\"\$OUT\""
fresh CLIENT=x86 CLIENT_SET=user; ui "info_status >> \$LOG"
check "XM2 status: x86 chosen by hand" "grep -qx 'Client type    x86 through emulation (chosen by hand)' <<<\"\$OUT\""
fresh CLIENT=arm64 CLIENT_SET=user; ui "info_status >> \$LOG"
check "XM3 status: native client chosen by hand on Armv8.0 CPU" "grep -qx 'Client type    native ARM64 (chosen by hand on Armv8.0 CPU)' <<<\"\$OUT\""
fresh CLIENT=arm64 CLIENT_SET=auto CLIENT_PROBE=1788652215:ok; ui "info_status >> \$LOG"
check "XM3b status: native client after setup's switch back on Armv8.0 CPU" "grep -qx 'Client type    native ARM64 (runs on this Armv8.0 CPU)' <<<\"\$OUT\""
fresh CLIENT=arm64 CLIENT_SET=auto CLIENT_PROBE=1788652215:ok; ui "IN_HW=auto IN_FAM=auto IN_DRV= IN_VK=yes IN_COMPS=tray IN_USER=tester IN_PASS_MADE=0; setup_summary" no
check "XM3c Install summary on Armv8.0 after native check passed: Client row native ARM64" "grep -q '^Client         native ARM64\$' <<<\"\$OUT\""
fresh CLIENT=arm64 CLIENT_SET=auto CLIENT_PROBE=1788652215:ok; ui "planned_client >> \$LOG"
check "XM3d planned client after native check passed on Armv8.0: arm64 (no x86 screen)" "grep -qx arm64 <<<\"\$OUT\""
v82; fresh; ui "info_status >> \$LOG"
check "XM4 status from 2.2 settings file (no CLIENT): native ARM64, FEX tool version row as before" "grep -qx 'Client type    native ARM64' <<<\"\$OUT\" && ! grep -q 'system FEX' <<<\"\$OUT\""
v80; fresh; ui "FAKE_CPU='Cortex-A72 x4, Armv8.0 (no LSE atomics)'; export FAKE_CPU; info_system >> \$LOG"
check "XM5 System: CPU row from setup --detect, before CPU governor" "grep -A1 '^CPU            Cortex-A72 x4, Armv8.0 (no LSE atomics)\$' <<<\"\$OUT\" | grep -q '^CPU governor'"
fresh; ui "info_system >> \$LOG"
check "XM6 System: CPU row without detect line, from cpuinfo" "grep -Eq '^CPU            [0-9]+ cores, Armv8.0 \(no LSE atomics\)\$' <<<\"\$OUT\""
fresh CLIENT=x86; ui "info_notes >> \$LOG"
check "XM7 Notes: x86 client line names #13288 and Maintenance > Client type" "grep -qx -- '- x86 client: slower start, client window on CPU; native client returns once Valve fixes #13288 (Maintenance > Client type).' <<<\"\$OUT\""
fresh CLIENT=arm64; ui "info_notes >> \$LOG"
check "XM7b Notes: no x86 line on native client" "! grep -q 'x86 client:' <<<\"\$OUT\""
fresh CLIENT=x86 CLIENT_SET=auto CLIENT_PROBE=1788652215:lse; ui "$XS; menu_maintenance" 10 BACK BACK
check "XM8 Maintenance: item 10 Client type (now: x86) opens type screen with state and four entries" "grep -q '^MENU Maintenance|.* 10 Client type (now: x86) 11 Report how last game ran 12 Run history (now: off) 14 Show what is new' <<<\"\$OUT\" && grep -q '^MENU Client type|Now: x86 through emulation (CPU without Armv8.1 atomics)' <<<\"\$OUT\" && grep -q '^Native client last checked: client 1788652215, lse\$' <<<\"\$OUT\" && grep -q 'auto Automatic (recommended) arm64 Native ARM64 client x86 x86 client through emulation check Check native client now\$' <<<\"\$OUT\""
check "XM8b Back from type screen: Maintenance again, cursor on 10" "[ \$(grep -c '^MENU Maintenance' <<<\"\$OUT\") = 2 ] && grep '^MENU Maintenance' <<<\"\$OUT\" | tail -n 1 | grep -q -- '--default 10 '"
fresh CLIENT=x86; ui "$XS; maint_client" auto BACK
check "XM9 Automatic: setup --keep --client=auto, no question" "grep -qx 'RUN Client type||--keep --client=auto' <<<\"\$OUT\" && ! grep -q '^YESNO' <<<\"\$OUT\""
fresh CLIENT=x86; ui "$XS; maint_client" arm64 no BACK
check "XM10 native on Armv8.0: asks first; Back -> no setup run" "grep -q '^YESNO Client type|This CPU has no Armv8.1 atomics (LSE).' <<<\"\$OUT\" && ! grep -q '^RUN' <<<\"\$OUT\""
fresh CLIENT=x86; ui "$XS; maint_client" arm64 yes BACK
check "XM11 native on Armv8.0 confirmed: setup --keep --client=arm64" "grep -qx 'RUN Client type||--keep --client=arm64' <<<\"\$OUT\""
check "XM12 both warnings default to Back (defaultno)" "[ \$(grep -c '\" Back defaultno || return 1\$' $CFG) -ge 2 ] && grep -q '\"Use native\" Back defaultno' $CFG && grep -q '\"Use x86\" Back defaultno' $CFG"
v82; fresh; ui "$XS; maint_client" x86 yes BACK
check "XM13 x86 on Armv8.1: asks (prefix rebuild named), then setup --keep --client=x86" "grep -q '^YESNO Client type|This CPU runs Valve.s native ARM64 client.' <<<\"\$OUT\" && grep -q 'may be rebuilt' <<<\"\$OUT\" && grep -qx 'RUN Client type||--keep --client=x86' <<<\"\$OUT\""
v80; fresh; ui "$XS; maint_client" x86 BACK
check "XM14 x86 on Armv8.0: no question, setup runs" "grep -qx 'RUN Client type||--keep --client=x86' <<<\"\$OUT\" && ! grep -q '^YESNO' <<<\"\$OUT\""
CC="$XS; ui_run(){ echo \"UIRUN \${*:3}\" >> \$LOG; printf '%s\n' \"\$CCOUT\" > \"\$2\"; return \$CCRC; }"
fresh CLIENT=x86; ui "$CC; CCOUT='native client: runs on this CPU (client 9)'; CCRC=0; maint_client" check yes BACK
check "XM15 Check now: setup --client-check in progress screen; runs -> offer switch -> setup --client=auto" "grep -q '^UIRUN .*inst.sh --client-check\$' <<<\"\$OUT\" && grep -q '^YESNO Client type|native client: runs on this CPU (client 9)' <<<\"\$OUT\" && grep -qx 'RUN Client type||--keep --client=auto' <<<\"\$OUT\""
fresh CLIENT=x86; ui "$CC; CCOUT='native client: still needs Armv8.1 (client 9, steam-for-linux #13288)'; CCRC=1; maint_client" check BACK
check "XM16 Check now: still affected -> message with result line, no setup run" "grep -q '^MSG Client type|native client: still needs Armv8.1 (client 9, steam-for-linux #13288)' <<<\"\$OUT\" && ! grep -q '^RUN' <<<\"\$OUT\""
fresh CLIENT=x86; ui "$XS; is_installed(){ return 1; }; offer_install(){ echo OFFER >> \$LOG; }; maint_client"
check "XM17 not installed: install offer in place of type screen" "grep -qx OFFER <<<\"\$OUT\" && ! grep -q '^MENU Client type' <<<\"\$OUT\""
v80; fresh; ui "IN_HW=auto IN_FAM=auto IN_DRV= IN_VK=yes IN_COMPS=tray IN_USER=tester IN_PASS_MADE=0; setup_summary" no
check "XM18 Install summary on Armv8.0: Client row names x86 client" "grep -q '^Client         x86 client through emulation\$' <<<\"\$OUT\""
v82; fresh; ui "IN_HW=auto IN_FAM=auto IN_DRV= IN_VK=yes IN_COMPS=tray IN_USER=tester IN_PASS_MADE=0; setup_summary" no
check "XM19 Install summary on Armv8.1: Client row native ARM64" "grep -q '^Client         native ARM64\$' <<<\"\$OUT\""
printf '#!/bin/sh\necho "MAP $*" >> "$LOG"\n' > "$T/cmap"; chmod 755 "$T/cmap"
fresh CLIENT=x86; ui "SA_COMPATMAP=$T/cmap; steam_running(){ return 1; }; cli_compat 220 windows"
check "XM20 compat windows on x86 client: Valve's x86 Proton (proton_experimental)" "grep -qx 'MAP 220 proton_experimental' <<<\"\$OUT\""
fresh CLIENT=arm64; ui "SA_COMPATMAP=$T/cmap; steam_running(){ return 1; }; cli_compat 220 windows"
check "XM21 compat windows on native client: proton_11-arm64, name Steam lists in Compatibility (box finding 6)" "grep -qx 'MAP 220 proton_11-arm64' <<<\"\$OUT\""
GA=$T/gauge.py
awk '/^PCT = re.compile/{f=1} f{print} f && /^    return "Starting...", 0$/{exit}' "$CFG" > "$GA"
OUT=$(python3 -c "import re
exec(open('$GA').read())
print(gauge(None, '######                    29.8%'))
print(gauge(None, 'some text'))
print(gauge((3, 11, 'x'), '###  50.0%'))
print(gauge(None, '#################### 100.0%'))" 2>&1)
printf "%s\n" "('Downloading...', 29)" "('Starting...', 0)" "('Step 3 of 11: x', 27)" "('Downloading...', 100)" > "$T/gauge.want"
check "BF22 progress gauge: download bar percent shown with Downloading... (GE download no longer 'Starting... 0%'); step lines win" "[ \"\$OUT\" = \"\$(cat $T/gauge.want)\" ]"
check "XM21b tool check accepts both ARM64 Proton names and earlier proton-stable-arm64 mappings" "grep -q '^  case \"\$2\" in proton_\*|proton-\*-arm64|steamlinuxruntime\*) return 0;; esac\$' '$CFG'"
fresh CLIENT=x86; ui "SA_COMPATMAP=$T/cmap; $XS; as_root(){ echo done; }; graphics_compat 220 windows Game"
check "XM22 Route per game Windows on x86 client: message names x86 Proton and untested tool name" "grep -q '^MSG Graphics|Game: Windows build with x86 Proton (proton_experimental, untested tool name).' <<<\"\$OUT\""
v80; fresh CLIENT=x86 CLIENT_SET=auto CLIENT_PROBE=1788652215:lse; ui "report_text | sed -n '/^== Client\$/,/^== Notes\$/p' >> \$LOG"
check "XM23 Hardware report: == Client block with CLIENT, CLIENT_SET, CLIENT_PROBE" "grep -qx 'CLIENT=x86 CLIENT_SET=auto CLIENT_PROBE=1788652215:lse' <<<\"\$OUT\""
OUT=$(bash "$CFG" --help 2>&1)
check "XM24 --help: STEAM_ARM_ALLOW_ARMV80 keeps native client; CLIENT key in Files" "grep -q 'STEAM_ARM_ALLOW_ARMV80=1  native ARM64 client on Armv8.0 CPU in place of' <<<\"\$OUT\" && grep -q 'CLIENT=arm64|x86 set by' <<<\"\$OUT\""
# Install / Setup follows setup's client choice: saved hand choice first, then CPU
SUM="IN_HW=auto IN_FAM=auto IN_DRV= IN_VK=yes IN_COMPS=tray IN_USER=tester IN_PASS_MADE=0; setup_summary"
MS="is_installed(){ return 1; }; detect_raw(){ :; }; setup_hardware(){ echo HW >> \$LOG; return 1; }; menu_setup"
v80; fresh CLIENT=arm64 CLIENT_SET=user; ui "$SUM" no
check "XM25 Install summary, Armv8.0 with native chosen by hand: Client row native ARM64" "grep -q '^Client         native ARM64\$' <<<\"\$OUT\""
v82; fresh CLIENT=x86 CLIENT_SET=user; ui "$SUM" no
check "XM26 Install summary, Armv8.1 with x86 chosen by hand: Client row x86 client" "grep -q '^Client         x86 client through emulation\$' <<<\"\$OUT\""
v80; fresh CLIENT=arm64 CLIENT_SET=user; ui "$MS"
check "XM27 Install / Setup, Armv8.0 with native chosen by hand: no x86 client screen" "! grep -q '^YESNO Install: x86 client' <<<\"\$OUT\" && grep -qx HW <<<\"\$OUT\""
v80; fresh CLIENT=x86 CLIENT_SET=auto; ui "$MS" no
check "XM28 Install / Setup, Armv8.0 by CPU rule: x86 client screen first, Back leaves" "grep -q '^YESNO Install: x86 client|This CPU has no Armv8.1' <<<\"\$OUT\" && ! grep -qx HW <<<\"\$OUT\""
v82; fresh CLIENT=x86 CLIENT_SET=user; ui "$MS"
check "XM29 Install / Setup, Armv8.1 with x86 chosen by hand: no CPU screen" "! grep -q '^YESNO Install: x86 client' <<<\"\$OUT\" && grep -qx HW <<<\"\$OUT\""
v80; fresh; ui "STEAM_ARM_ALLOW_ARMV80=1; $SUM" no
check "XM30 Install summary, Armv8.0 with STEAM_ARM_ALLOW_ARMV80=1: native ARM64" "grep -q '^Client         native ARM64\$' <<<\"\$OUT\""

# ---------- box fix pass (bugs 13-16, 18, 20) ----------
v82; fresh CLIENT=x86 CLIENT_SET=user; ui "info_notes >> \$LOG"
check "BF13 Notes, x86 chosen by hand on Armv8.1: hand line, no #13288" "grep -qx -- '- x86 client chosen by hand: slower start, client window on CPU; native client runs on this CPU (Maintenance > Client type).' <<<\"\$OUT\" && ! grep -q 13288 <<<\"\$OUT\""
v80; fresh CLIENT=x86 CLIENT_SET=user; ui "info_notes >> \$LOG"
check "BF13 Notes, x86 chosen by hand on Armv8.0: #13288 line kept" "grep -q '#13288' <<<\"\$OUT\" && ! grep -q 'chosen by hand' <<<\"\$OUT\""
fresh; ui "FAKE_CPU='8 cores (Cortex-A76 x4, Cortex-A55 x4), Armv8.1 or newer (LSE atomics), part table extra words'; export FAKE_CPU; info_system >> \$LOG"
check "BF14 System: long CPU row wraps under value column (15 spaces), not column 0" "grep -A1 '^CPU            8 cores' <<<\"\$OUT\" | sed -n 2p | grep -q '^               [^ ]' && grep -A2 '^CPU            8 cores' <<<\"\$OUT\" | sed -n 3p | grep -q '^CPU governor'"
LP=$R/home/tester/Downloads/a-rather-long-folder-name/another-long-folder/steam-arm-fex-mesa-test-x86_64-i386.tar.zst
fresh "PROVIDER_LOCAL_FILE=$LP"; ui "info_status >> \$LOG"
check "BF14 status: long Driver archive row wraps under value column" "grep -A1 '^Driver archive local file' <<<\"\$OUT\" | sed -n 2p | grep -q '^               [^ ]' && awk '/^Driver archive/ { f = 1; next } f && !/^               / { print; exit }' <<<\"\$OUT\" | grep -q '^Components on' && ! awk 'length > 70' <<<\"\$(grep -A4 '^Driver archive' <<<\"\$OUT\")\" | grep -q ."
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "DLG $(basename "$0") $*" >> "$LOG"\nexit 1\n' > "$T/bin/dialog"; cp "$T/bin/dialog" "$T/bin/whiptail"; chmod 755 "$T/bin/dialog" "$T/bin/whiptail"
REAL="unset -f ui_menu ui_check; . <(sed -n '/^ui_menu(){/,/^}/p;/^ui_check(){/,/^}/p' $T/app-copy.sh); PATH=$T/bin:\$PATH"
fresh; ui "$REAL; DIALOG=dialog; ui_menu Caches 'a  b' 1 'x    y' 2 'z    w'; ui_check Parts t a 'p    q' ON"
check "BF15 dialog menu and checklist keep column spacing (--no-collapse)" "[ \$(grep -c '^DLG dialog .*--no-collapse' <<<\"\$OUT\") = 2 ]"
fresh; ui "$REAL; DIALOG=whiptail; ui_menu Caches text 1 a 2 b 3 c; ui_check Parts t a p ON b q OFF"
check "BF16 whiptail list height = number of entries (3 menu, 2 checklist), rest left to text" "grep -q -- '--menu text 22 [0-9]* 3 1 a 2 b 3 c\$' <<<\"\$OUT\" && grep -q -- '--checklist t 22 [0-9]* 2 a p ON b q OFF\$' <<<\"\$OUT\""
fresh; ui "$REAL; DIALOG=whiptail; set --; for i in \$(seq 1 20); do set -- \"\$@\" \$i x; done; ui_menu Long text \"\$@\""
check "BF16 whiptail long list: height capped at UH-9 (13)" "grep -q -- '--menu text 22 [0-9]* 13 1 x' <<<\"\$OUT\""
fresh; ui "IN_HW=rk3588; setup_hardware" BACK
check "BF18 Install hardware screen opens on earlier choice (Back keeps it)" "grep -q '^MENU Install: hardware|.*--default rk3588 auto ' <<<\"\$OUT\""
fresh; ui "unset IN_HW; setup_hardware" BACK
check "BF18 Install hardware screen, first visit: cursor on auto" "grep -q '^MENU Install: hardware|.*--default auto auto ' <<<\"\$OUT\""
fresh; ui "steam_dir(){ echo $T/no-access; }; report_text | grep '^FEX code cache' >> \$LOG"
check "BF20 report from account without read access: sizes unknown, no false 0" "grep -Eqx \"FEX code cache on for [0-9]+ games?, cache sizes unknown \\(no read access to game account's folder\\)\" <<<\"\$OUT\" && ! grep -q 'in caches' <<<\"\$OUT\""
printf '#!/bin/sh\necho "SUDO $*" >&2\n' > "$T/bin/sudo"; chmod 755 "$T/bin/sudo"
CR="unset -f cli_root; . <(sed -n '/^cli_root(){/,/^}/p' $T/app-copy.sh); have(){ return 0; }; PATH=$T/bin:\$PATH"
fresh; ui "$CR; cli_cache list"
check "BF20 cache list from other account: sudo reason names reading, not a change" "grep -q \"steam-arm-config: game account's caches are readable only with administrator rights; running it with sudo\" <<<\"\$OUT\" && grep -q '^SUDO .* cache list\$' <<<\"\$OUT\""
fresh; ui "$CR; cli_cache clear all"
check "BF20 cache clear from other account: change message kept" "grep -q 'steam-arm-config: this change needs administrator rights; running it with sudo' <<<\"\$OUT\""
rm -f "$CPUF"

bash "$T0/mkfake.sh" >/dev/null
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
