#!/bin/bash
# 2.2 menu-tray group: Close Steam now (close_steam), tray (graceful Stop, icon refresh, Big Picture / Settings /
# log items, autostart without OnlyShowIn), Settings menu entry + .deb Setup entry, KDE window rule on Plasma 5,
# GE-Proton label, update-check, hardware report sections, View logs empty texts. Functions extracted from the
# copies in ~/.cache/sarm<NN>-work (paths.sh) into /tmp; curl, pgrep, id, runuser, kwriteconfig, gi stubbed.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
CFG=$SARM_CFG
WORK=$(dirname "$INST")
T=$(mktemp -d /tmp/sarm232-mt.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
# Function NAME of FILE: one line, or up to its closing "}" line.
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }
has(){ printf '%s\n' "$OUT" | grep -q -- "$1"; }

check "installer bash -n, settings menu bash -n" "bash -n '$INST' && bash -n '$CFG'"
check "embedded settings menu identical" "awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f' '$INST' | cmp -s - '$CFG'"
TRAY=$T/tray.py
awk '/^cat > \/usr\/local\/bin\/steam-arm-tray <<.TRAYPY.$/{f=1;next} /^TRAYPY$/{f=0} f' "$INST" > "$TRAY"
check "tray compiles" "python3 -m py_compile '$TRAY'"

# ---------- item 11: close_steam ----------
S=$T/st; mkdir -p "$S/bin"
cat > "$S/bin/pgrep" <<'EOF'
#!/bin/sh
case "$*" in *SteamLaunch*) [ -f "$ST/game" ];; *"-x steam"*) [ -f "$ST/running" ] || { [ -f "$ST/other" ] && [ "$1" = -x ]; };; *) exit 1;; esac
EOF
cat > "$S/launcher" <<'EOF'
#!/bin/sh
echo "$(id -un) HOME=$HOME $*" >> "$ST/launcher.log"
[ "$1" = --shutdown ] || exit 2
[ -f "$ST/stuck" ] && { echo "steam-arm: client still running 30 s after SIGTERM; close it from its menu" >&2; exit 1; }
rm -f "$ST/running"; exit 0
EOF
chmod +x "$S/bin/pgrep" "$S/launcher"
CS=$T/cs.sh
{ echo "SA_LAUNCHER=$S/launcher"
  for f in steam_running game_running steam_shutdown close_steam run_installer_tty; do fn "$f" "$CFG"; done
  cat <<'EOF'
game_user(){ echo "${GU:-$(id -un)}"; }
game_home(){ echo /home/gameacct; }
ui_msg(){ printf 'MSG[%s] %s\n' "$1" "$2" >> "$ST/ui.log"; }
ui_info(){ printf 'INFO[%s]\n' "$1" >> "$ST/ui.log"; }
ui_yesno(){ printf 'ASK[%s|%s|%s] %s\n' "$1" "$3" "$4" "$2" >> "$ST/ui.log"; [ "${ANSWER:-yes}" = yes ]; }
need_root(){ echo need_root >> "$ST/ui.log"; return "${ROOTRC:-0}"; }
as_root(){ "$@"; }
runuser(){ echo "runuser $*" >> "$ST/ui.log"; shift 3; "$@"; }
installer_cmd(){ echo /bin/true; }
clear(){ :; }; ui_pause(){ :; }; status_line(){ :; }
EOF
} > "$CS"
csrun(){ rm -f "$ST"/*.log; ( export ST=$S/state PATH="$S/bin:$PATH"; . "$CS"; eval "$1" ); }
mkdir -p "$S/state"; export ST=$S/state
rm -f "$ST"/*; OUT=$(csrun 'close_steam T "Why."; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "close_steam: client not running -> rc 0, no screen" "has 'rc=0' && ! has 'MSG\|ASK'"
rm -f "$ST"/*; touch "$ST/running" "$ST/game"; OUT=$(csrun 'close_steam T "Why."; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "close_steam: game running -> refused, rc 1, launcher not called" "has 'rc=1' && has 'A game is running in Steam ARM. Why.' && ! has 'ASK' && [ ! -f $ST/launcher.log ]"
rm -f "$ST"/*; touch "$ST/running"; OUT=$( (export ST PATH="$S/bin:$PATH"; . "$CS"; SA_LAUNCHER=/bin/true; close_steam T "Why."; echo rc=$?); cat "$ST"/*.log 2>/dev/null)
check "close_steam: launcher without --shutdown -> old text, rc 1" "has 'rc=1' && has 'Exit from its menu or tray' && ! has 'ASK'"
rm -f "$ST"/*; touch "$ST/running"; OUT=$(csrun 'ANSWER=no close_steam T "Why."; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "close_steam: Back -> rc 1, client left running" "has 'rc=1' && has 'ASK\[T|Close Steam|Back\]' && [ -f $ST/running ] && [ ! -f $ST/launcher.log ]"
rm -f "$ST"/*; touch "$ST/running"; OUT=$(csrun 'close_steam T "Why."; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "close_steam: game account itself -> steam-arm --shutdown direct, rc 0" "has 'rc=0' && has \"^$(id -un) HOME=.* --shutdown\$\" && ! has runuser && ! has need_root"
rm -f "$ST"/*; touch "$ST/running"; OUT=$(csrun 'GU=gameacct close_steam T "Why."; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "close_steam: other account -> need_root, runuser -u gameacct -- env HOME=<its home>" "has 'rc=0' && has need_root && has 'runuser -u gameacct -- env -u DISPLAY -u WAYLAND_DISPLAY HOME=/home/gameacct .*launcher --shutdown' && has 'HOME=/home/gameacct --shutdown'"
rm -f "$ST"/*; touch "$ST/running"; OUT=$(csrun 'GU=gameacct ROOTRC=1 close_steam T "Why."; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "close_steam: sudo refused -> rc 1, launcher not called" "has 'rc=1' && [ -f $ST/running ] && [ ! -f $ST/launcher.log ]"
rm -f "$ST"/*; touch "$ST/running" "$ST/stuck"; OUT=$(csrun 'close_steam T "Why."; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "close_steam: client does not stop -> launcher line shown, rc 1" "has 'rc=1' && has 'Steam did not close' && has 'still running 30 s after SIGTERM'"
rm -f "$ST"/*; touch "$ST/other"; OUT=$(csrun 'run_installer_tty --remove; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "uninstall: other account's client -> message, setup not run" "has 'rc=1' && has 'another account is running' && ! has need_root"
rm -f "$ST"/*; touch "$ST/running"; OUT=$(csrun 'ANSWER=no run_installer_tty --remove; echo rc=$?'; cat "$ST"/*.log 2>/dev/null)
check "uninstall: own client, Back -> setup not run" "has 'rc=1' && has 'ASK\[Uninstall' && ! has need_root"
rm -f "$ST"/*
# launcher run without display variables: its stop dialog would wait unseen behind the menu (MT-2)
printf '#!/bin/sh\n# --shutdown\necho "D=${DISPLAY:-none} W=${WAYLAND_DISPLAY:-none} H=${STEAM_ARM_HOME:-none} $*" >> "$ST/launcher.log"; rm -f "$ST/running"\n' > "$S/launcher-env"; chmod +x "$S/launcher-env"
touch "$ST/running"; OUT=$( (export ST PATH="$S/bin:$PATH" DISPLAY=:0 WAYLAND_DISPLAY=wayland-0; . "$CS"; SA_LAUNCHER=$S/launcher-env; close_steam T "Why."; echo rc=$?); cat "$ST"/*.log 2>/dev/null)
check "close_steam: launcher runs without DISPLAY / WAYLAND_DISPLAY (no hidden dialog), no STEAM_ARM_HOME" "has 'rc=0' && has '^D=none W=none H=none --shutdown'"
rm -f "$ST"/*
# account picked in Install / Setup: its client is checked and stopped (MT-5, MT-6)
A=$T/acct; mkdir -p "$A/bin" "$A/st"
cat > "$A/bin/pgrep" <<'EOF'
#!/bin/sh
echo "pgrep $*" >> "$AS/pgrep.log"
case "$*" in *SteamLaunch*) exit 1;; esac
u=; [ "$1" = -u ] && u=$2; [ -n "$u" ] && [ -f "$AS/running-$u" ]
EOF
cat > "$A/bin/getent" <<'EOF'
#!/bin/sh
case "$2" in oldacct|newacct) echo "$2:x:1001:1001::/home/$2:/bin/sh";; *) exit 2;; esac
EOF
cat > "$A/bin/id" <<'EOF'
#!/bin/sh
case "$1" in -un) echo admin;; -u) echo 1000;; oldacct|newacct) exit 0;; *) exec /usr/bin/id "$@";; esac
EOF
cat > "$A/launcher" <<'EOF'
#!/bin/sh
# --shutdown
echo "$(id -un) H=${STEAM_ARM_HOME:-none} D=${DISPLAY:-none} $*" >> "$AS/launcher.log"; for f in "$AS"/running-*; do rm -f "$f"; done
EOF
chmod +x "$A/bin/"* "$A/launcher"
AC=$T/ac.sh
{ echo "SA_LAUNCHER=$A/launcher"
  for f in game_user game_home armhome_rel arm_home steam_running game_running steam_shutdown close_steam run_installer; do fn "$f" "$CFG"; done
  cat <<'EOF'
conf_get(){ case "$1" in GAMEUSER) echo oldacct;; esac; }
ui_msg(){ printf 'MSG[%s] %s\n' "$1" "$2" >> "$AS/ui.log"; }
ui_info(){ :; }; ui_yesno(){ echo ASK >> "$AS/ui.log"; }
NR=0; need_root(){ NR=$((NR + 1)); echo "need_root $NR" >> "$AS/ui.log"; [ "$NR" -lt 2 ]; }
as_root(){ "$@"; }
runuser(){ echo "runuser $*" >> "$AS/ui.log"; shift 3; "$@"; }
installer_cmd(){ echo /bin/true; }
EOF
} > "$AC"
acrun(){ rm -f "$A/st"/*; touch "$A/st/running-$1"; OUT=$( (export AS=$A/st PATH="$A/bin:$PATH"; . "$AC"; INST_ENV=("GAMEUSER=$2" "GPU_FAMILY=auto"); run_installer "Install / Setup"; echo rc=$?) 2>&1; cat "$A/st"/*.log 2>/dev/null); }
acrun newacct newacct
check "Install / Setup, other account picked: its client checked and closed (in its own client folder)" "has 'pgrep -u newacct -x steam' && ! has 'pgrep -u oldacct' && has 'runuser -u newacct' && has 'H=/home/newacct/.local/share/steam-arm D=none --shutdown'"
acrun oldacct newacct
check "Install / Setup, other account picked: client of settings-file account not touched" "! has 'pgrep -u oldacct' && ! has 'launcher' && ! has ASK"
acrun oldacct oldacct
check "Install / Setup, same account: settings-file account checked, no STEAM_ARM_HOME" "has 'pgrep -u oldacct -x steam' && has 'H=none D=none --shutdown'"
acrun newacct ghost
check "Install / Setup, account not created yet: no client check, setup goes on" "! has 'pgrep -u' && has 'need_root 1'"
fnline(){ fn "$1" "$CFG" | grep -n "$2" | head -1 | cut -d: -f1; }
check "run_installer: close_steam before need_root" "[ -n \"\$(fnline run_installer close_steam)\" ] && [ \$(fnline run_installer close_steam) -lt \$(fnline run_installer need_root) ]"
check "graphics compat, Remote Play apply, Restore use close_steam" "fn graphics_compat '$CFG' | grep -q 'close_steam \"Graphics\"' && fn menu_remoteplay '$CFG' | grep -q 'close_steam \"Remote Play\"' && fn maint_restore '$CFG' | grep -q 'close_steam \"Restore settings\"'"
check "no 'Close Steam ARM first' dead end left in menu" "! grep -q 'Close Steam ARM first' '$CFG' && ! grep -q 'Retry Back' '$CFG'"
check "CLI compat/restore name steam-arm --shutdown" "[ \$(grep -c 'close it first (as \$(game_user): steam-arm --shutdown)' '$CFG') = 2 ]"
check "installer stop texts name steam-arm --shutdown" "[ \$(grep -c 'or steam-arm --shutdown' '$INST') -ge 4 ] && ! grep -q 'or Stop Steam in the tray), then' '$INST'"
check "no SIGKILL in settings menu or tray" "! grep -E 'SIGKILL|kill -9|-KILL' '$CFG' '$TRAY' | grep -qv 'never SIGKILL'"

# ---------- item 16: GE-Proton label ----------
GL=$T/gl.sh
{ fn compat_label "$CFG"; fn game_kind "$CFG"; echo 'compat_tool(){ echo "$TOOL"; }'; echo 'game_libraries(){ :; }'; } > "$GL"
lab(){ ( . "$GL"; compat_label "$1" ); }
kind(){ ( . "$GL"; TOOL=$1 game_kind 1 ); }
check "label: proton_experimental -> Windows build (Proton)" "[ \"\$(lab proton_experimental)\" = 'Windows build (Proton)' ]"
check "label: GE-Proton10-25 -> Windows build (GE-Proton10-25)" "[ \"\$(lab GE-Proton10-25)\" = 'Windows build (GE-Proton10-25)' ]"
check "label: steamlinuxruntime -> Linux build; empty -> empty" "[ \"\$(lab steamlinuxruntime)\" = 'Linux build' ] && [ -z \"\$(lab '')\" ]"
check "game_kind: GE-Proton -> windows, Proton -> windows, runtime -> linux" "[ \$(kind GE-Proton9-20) = windows ] && [ \$(kind proton-stable-arm64) = windows ] && [ \$(kind steamlinuxruntime) = linux ]"

# ---------- item 17: update-check ----------
# V installed (menu), NV next minor release, V10 minor 10 of same major (version sort, not text sort)
V=$(sed -n 's/^SA_VERSION=//p' "$CFG" | head -n 1); NV=${V%%.*}.$(( $(cut -d. -f2 <<<"$V") + 1 )); V10=${V%%.*}.10
U=$T/up; mkdir -p "$U/bin"
cat > "$U/bin/curl" <<'EOF'
#!/bin/sh
o=""; while [ $# -gt 0 ]; do case "$1" in -o) o=$2; shift;; esac; shift; done
echo "$*" > /dev/null
[ "$CODE" = 000 ] && { printf 000; exit 28; }
printf '%s' "$BODY" > "$o"; printf '%s' "$CODE"
EOF
chmod +x "$U/bin/curl"
uc(){ OUT=$(cd "$T" && env PATH="$U/bin:$PATH" CODE="$1" BODY="$2" bash "$CFG" update-check 2>&1); RC=$?; }
uc 200 "{\"tag_name\": \"steam-arm-v$NV\", \"html_url\": \"https://github.com/Scrumpper/Steam-ARM/releases/tag/steam-arm-v$NV\", \"draft\": false}"
check "update-check: newer release -> version, URL, installer hint, rc 0" "[ $RC = 0 ] && has 'Newer release: Steam ARM $NV (installed: $V)' && has 'releases/tag/steam-arm-v$NV' && has 'sudo bash steam-arm-install.sh --keep'"
uc 200 "{\"tag_name\": \"steam-arm-v$V\", \"html_url\": \"https://github.com/x\"}"
check "update-check: same version -> newest, rc 0" "[ $RC = 0 ] && has 'Steam ARM $V is the newest release.'"
uc 200 '{"tag_name": "steam-arm-v2.1", "html_url": "https://github.com/x"}'
check "update-check: older release -> this is newer" "[ $RC = 0 ] && has 'newer than the newest release (2.1)'"
uc 200 "{\"tag_name\": \"steam-arm-v$V10\", \"html_url\": \"https://github.com/x\"}"
check "update-check: $V10 > $V (version sort)" "has 'Newer release: Steam ARM $V10'"
uc 200 "{\"tag_name\": \"v$NV\", \"html_url\": \"https://evil.example/x\"}"
check "update-check: v-prefix read; non-GitHub URL replaced by releases page" "has 'Steam ARM $NV' && ! has evil && has 'Scrumpper/Steam-ARM/releases'"
uc 403 '{"message": "API rate limit exceeded"}'
check "update-check: 403 -> request limit text, rc 1" "[ $RC = 1 ] && has 'request limit'"
uc 000 ''
check "update-check: offline -> could not be reached, rc 1" "[ $RC = 1 ] && has 'could not be reached'"
uc 404 '{}'
check "update-check: 404 -> no published release" "[ $RC = 1 ] && has 'No published release'"
uc 200 'not json'
check "update-check: bad answer -> not understood" "[ $RC = 1 ] && has 'not understood'"
uc 200 '{"tag_name": "nightly; rm -rf /", "html_url": "https://github.com/x"}'
check "update-check: odd tag rejected" "[ $RC = 1 ] && has 'not understood'"
uc 200 "{\"tag_name\": \"v$V.0\", \"html_url\": \"https://github.com/x\"}"
check "update-check: v$V.0 with $V installed -> newest (trailing .0)" "[ $RC = 0 ] && has 'Steam ARM $V is the newest release.' && ! has 'Newer release'"
uc 200 "{\"tag_name\": \"steam-arm-v$NV\", \"html_url\": \" \"}"
check "update-check: blank html_url -> tag still read, releases page named" "[ $RC = 0 ] && has 'Newer release: Steam ARM $NV (installed: $V)' && has 'Scrumpper/Steam-ARM/releases'"
uc 200 "{\"tag_name\": \"steam-arm-v$NV-hotfix\", \"html_url\": \"https://github.com/x\"}"
check "update-check: suffixed tag ($NV-hotfix) -> newer release with full tag" "[ $RC = 0 ] && has 'Newer release: Steam ARM $NV-hotfix (installed: $V)'"
uc 200 '{"tag_name": "steam-arm-v2.1-hotfix", "html_url": "https://github.com/x"}'
check "update-check: older suffixed tag -> this is newer" "[ $RC = 0 ] && has 'newer than the newest release (2.1-hotfix)'"
check "update-check: endpoint releases/latest, timeout set, no download" "grep -q '^SA_RELEASE_API=https://api.github.com/repos/Scrumpper/Steam-ARM/releases/latest\$' '$CFG' && fn update_check '$CFG' | grep -q -- '--max-time' && ! fn update_check '$CFG' | grep -v 'echo' | grep -qE 'wget|curl .*-O |tar |bash '"
check "Check for new version: Maintenance item and CLI only (no automatic check)" "fn menu_maintenance '$CFG' | grep -q '7 \"Check for new version\"' && [ \$(grep -c '\\bupdate_check\\b' '$CFG') = 3 ] && [ \$(grep -c 'maint_update_check' '$CFG') = 2 ] && fn menu_maintenance '$CFG' | grep -q '7) maint_update_check;;'"

# ---------- item 18: hardware report ----------
R=$T/rep; mkdir -p "$R/ah/.local/share/Steam/logs" "$R/cache" "$R/bin"
printf '2026-10-05 10:00:00 private GLX copy missing\n' > "$R/ah/steam-arm.log"
printf '[2026-10-05 10:00:00] Startup - updater built Sep 1\n[2026-10-05 10:00:01] Verifying installation...\n[2026-10-05 10:00:02] Error: Download failed: http error 0\n[2026-10-05 10:01:00] Update complete, launching...\n' > "$R/ah/.local/share/Steam/logs/bootstrap_log.txt"
printf '==> 10/11  menu\nnoise\n==> 11/11  done\n  Client home: x\n' > "$R/cache/setup-20261005-1-a.log"
cat > "$R/bin/id" <<'EOF'
#!/bin/sh
[ "$1" = -nG ] && [ -n "$EXTRA" ] && { /usr/bin/id -nG "$2" | tr '\n' ' '; echo "$EXTRA"; exit; }
exec /usr/bin/id "$@"
EOF
chmod +x "$R/bin/id"
RP=$T/rep.sh
{ fn report_text "$CFG"; fn report_groups "$CFG"; fn log_summary "$CFG"; fn strip_ansi "$CFG"
  cat <<EOF
info_system(){ :; }; info_status(){ :; }; info_notes(){ :; }; detect_raw(){ :; }; renderer_lines(){ :; }; fexlogs(){ :; }
info_system(){ :; }
game_user(){ id -un; }
arm_home(){ echo "$R/ah"; }
steam_dir(){ echo "$R/ah/.local/share/Steam"; }
setuplogs(){ ls -t "$R/cache"/setup-*.log 2>/dev/null; }
SA_TITLES_ETC=/nonexistent; SA_VERSION=2.2
EOF
} > "$RP"
OUT=$( (PATH="$R/bin:$PATH"; . "$RP"; report_text) 2>&1)
check "report: launcher log section with its lines" "has '== Launcher log' && has 'private GLX copy missing'"
check "report: bootstrap lines filtered (Startup, Error, Update complete; not Verifying)" "has 'Startup - updater' && has 'Error: Download failed' && has 'Update complete, launching' && ! has Verifying"
check "report: newest setup log summary from its done line" "has '== Last setup run' && has '==> 11/11  done' && has 'Client home: x' && ! has noise"
check "report: groups of account and running processes" "has '^Account        ' && has '^Running       '"
OUT=$( (PATH="$R/bin:$PATH"; EXTRA=newgrp-sa; export EXTRA; . "$RP"; report_groups) 2>&1)
check "report: group not in running session -> Not active yet" "has 'Not active yet: newgrp-sa (log out and back in)'"
# groups: missing only when no process of the account holds them (old session processes keep old groups) (MT-5)
mkdir -p "$R/proc/100" "$R/proc/200" "$R/pg"
printf 'Gid:\t%s\t%s\nGroups:\t%s\n' "$(id -g)" "$(id -g)" "$(id -G)" > "$R/proc/100/status"
printf 'Gid:\t%s\t%s\nGroups:\t%s 4242\n' "$(id -g)" "$(id -g)" "$(id -G)" > "$R/proc/200/status"
printf '#!/bin/sh\ncase "$*" in *-o*) echo 100;; *) printf "100\\n200\\n";; esac\n' > "$R/pg/pgrep"
printf '#!/bin/sh\n[ "$1 $2" = "group 4242" ] && { echo newgrp-sa:x:4242:; exit 0; }\nexec /usr/bin/getent "$@"\n' > "$R/pg/getent"
chmod +x "$R/pg/pgrep" "$R/pg/getent"
{ fn report_groups "$CFG" | sed "s#\"/proc/#\"$R/proc/#"; echo 'game_user(){ id -un; }'; } > "$T/rg.sh"
OUT=$( (PATH="$R/pg:$R/bin:$PATH"; EXTRA=newgrp-sa; export EXTRA; . "$T/rg.sh"; report_groups) 2>&1)
check "report: group held by newer session process -> not reported missing" "has '^Running .*newgrp-sa' && ! has 'Not active yet'"
rm -f "$R/proc/200/status"; printf 'Gid:\t%s\t%s\nGroups:\t%s\n' "$(id -g)" "$(id -g)" "$(id -G)" > "$R/proc/200/status"
OUT=$( (PATH="$R/pg:$R/bin:$PATH"; EXTRA=newgrp-sa; export EXTRA; . "$T/rg.sh"; report_groups) 2>&1)
check "report: group in no process -> Not active yet" "has 'Not active yet: newgrp-sa (log out and back in)'"
# hw_model on a board without device tree (ACPI): no error text in menu header (MT-8)
OUT=$( (. <(fn hw_model "$CFG" | sed "s#/proc/device-tree/model#$T/no-such-dt/model#; s#/sys/class/dmi/id/#$T/no-dmi/#g"); trim(){ cat; }; hw_model) 2>&1)
check "hw_model: no device tree -> 'unknown', no error line" "[ \"\$OUT\" = unknown ]"
rm -rf "$R/ah" "$R/cache"/*
OUT=$( (PATH="$R/bin:$PATH"; . "$RP"; report_text) 2>&1)
check "report: missing logs -> placeholder lines" "has '(no setup log of this account)' && [ \$(printf '%s\n' \"\$OUT\" | grep -c 'not readable by this account') = 2 ]"
check "report goes through sanitize" "fn report_make '$CFG' | grep -c 'report_text 2>/dev/null | sanitize' | grep -qx 2"

# ---------- View logs: empty texts ----------
V=$T/vl; mkdir -p "$V/ah" "$V/cache"
: > "$V/ah/steam-arm.log"; : > "$V/fex.log"; : > "$V/cache/setup-1.log"
VL=$T/vl.sh
{ fn maint_logs "$CFG"; cat <<EOF
arm_home(){ echo "$V/ah"; }
fexlogs(){ echo "$V/fex.log"; }
setuplogs(){ echo "$V/cache/setup-1.log"; }
ui_menu(){ n=\$(cat "$V/n" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$V/n"; [ \$n -le 3 ] && echo \$n; [ \$n -le 3 ]; }
ui_msg(){ echo "MSG \$2"; }
ui_textstr(){ echo "TEXT \$1"; }
tilde(){ cat; }; strip_ansi(){ cat; }
EOF
} > "$VL"
OUT=$( (. "$VL"; maint_logs) )
check "View logs: empty launcher log -> warnings-only text" "has '^MSG steam-arm.log is empty (launcher writes warnings only).\$'"
check "View logs: empty game and setup logs -> plain 'is empty.'" "has '^MSG fex.log is empty.\$' && has '^MSG setup-1.log is empty.\$'"
rm -f "$V/n" "$V/ah/steam-arm.log"; echo line > "$V/fex.log"
OUT=$( (. "$VL"; maint_logs) )
check "View logs: missing -> No log found yet; non-empty -> shown" "has '^MSG No log found yet.\$' && has '^TEXT Log: fex.log\$'"
# setup logs live in the cache of the account that ran the menu; a desktop user is pointed at sudo (box walk)
sed 's#^setuplogs(){.*#setuplogs(){ :; }#' "$VL" > "$VL.2"
rm -f "$V/n"; OUT=$( (. "$VL.2"; id(){ [ "$1" = -u ] && echo 1000 || command id "$@"; }; maint_logs) )
check "View logs: no setup log, not root -> administrator's folder and sudo steam-arm-config named" "has \"^MSG No setup log of this account. Setup runs from sudo steam-arm-config are logged in the administrator's folder (.*/.cache/steam-arm). Run sudo steam-arm-config to view them.\$\""
rm -f "$V/n"; OUT=$( (. "$VL.2"; id(){ [ "$1" = -u ] && echo 0 || command id "$@"; }; maint_logs) )
check "View logs: no setup log as root -> No log found yet" "[ \$(printf '%s\n' \"\$OUT\" | grep -c '^MSG No log found yet.\$') = 2 ] && ! has 'administrator'"

# ---------- download progress on the built-in progress screen (box walk) ----------
D=$T/dl; mkdir -p "$D"
awk '/^CURL_SHOW=\(-sS\)/{f=1} f{print} f && (/^CURL_SHOW=.*progress-bar\)$/ || /fi$/){exit}' "$INST" > "$D/curl.sh"
OUT=$(STEAM_ARM_PROGRESS=1 bash -c ". '$D/curl.sh'; echo \"\${CURL_SHOW[*]}|\${CURL_ENV[*]}\"" 2>/dev/null </dev/null)
check "installer: STEAM_ARM_PROGRESS=1 without a terminal -> curl --progress-bar, 60 columns" "[ \"\$OUT\" = '--progress-bar|COLUMNS=60' ]"
OUT=$(bash -c ". '$D/curl.sh'; echo \"\${CURL_SHOW[*]}|\${CURL_ENV[*]}\"" 2>/dev/null </dev/null)
check "installer: no terminal, no STEAM_ARM_PROGRESS -> curl -sS" "[ \"\$OUT\" = '-sS|' ]"
OUT=$(grep -n 'CURL_SHOW\[@\]' "$INST")
check "installer: client package and driver downloads both take CURL_ENV" "[ \$(grep -c 'env \"\${CURL_ENV\[@\]}\" curl .*\"\${CURL_SHOW\[@\]}\"' '$INST') = 2 ] && [ \$(grep -c 'CURL_SHOW\[@\]' '$INST') = 2 ]"
OUT=$(fn run_installer "$CFG" | grep -o 'STEAM_ARM_PROGRESS=.*')
check "menu: setup run gets STEAM_ARM_PROGRESS=1 on the built-in screen only" "fn run_installer '$CFG' | grep -qF 'STEAM_ARM_PROGRESS=\"\$([ \"\$DIALOG\" = builtin ] && echo 1)\"'"
UR=$D/ur.sh
{ for f in ui_run cr_last tmpf ui_feed progress_feed ansi_lines; do fn "$f" "$CFG"; done
  cat <<EOF
UI_STDIN=""; SA_TMP=""; XDG_RUNTIME_DIR=""; TMPDIR=$D
ui_size(){ UW=60; UH=10; }
ui_msg(){ echo "MSG \$2"; }
tui(){ cat > "$D/screen"; }
whiptail(){ cat > "$D/gauge"; }
dl(){ printf '==> 4/11  Client\n'; printf '\r##      10.0%%\r####    50.0%%\r######## 100.0%%\n'; printf 'done line\r\n'; return 3; }
EOF
} > "$UR"
rm -f "$D/log" "$D/screen"; OUT=$( (. "$UR"; DIALOG=builtin ui_run T "$D/log" dl; echo "rc=$?") )
check "built-in screen: command status kept" "has '^rc=3\$'"
check "built-in screen: gets every progress update (carriage returns kept)" "grep -q \$'\\r####    50.0%' '$D/screen' && grep -q \$'\\r######## 100.0%' '$D/screen'"
check "built-in screen: log keeps only the final progress segment, 3 lines" "[ \$(wc -l < '$D/log') = 3 ] && grep -qx '######## 100.0%' '$D/log' && ! grep -q '50.0%' '$D/log' && grep -qx '==> 4/11  Client' '$D/log' && grep -q \$'^done line\\r\$' '$D/log'"
check "built-in screen: log fifo folder removed" "[ -z \"\$(ls -A '$D' | grep '^steam-arm-config')\" ]"
rm -f "$D/log" "$D/gauge"; OUT=$( (. "$UR"; DIALOG=whiptail ui_run T "$D/log" dl; echo "rc=$?") )
check "whiptail gauge: progress line ignored, step line fed" "has '^rc=3\$' && [ \$(grep -c '^XXX\$' '$D/gauge') = 2 ] && grep -qx 'Step 4 of 11: Client' '$D/gauge'"

# ---------- prose without hard line breaks (built-in screen wraps it; box walk orphan line) ----------
rm -f "$ST"/*; touch "$ST/running"; OUT=$(csrun 'ANSWER=no close_steam T "Why."'; cat "$ST"/*.log 2>/dev/null)
check "close_steam: question is one paragraph (no orphan 'does;' line)" "has 'as Exit in its menu does; this can take up to a minute.' && ! has '^does;'"
rm -f "$ST"/*
OUT=""
for p in "its files are archived in /var/backups." "XInput pad is not recognised in games." "e-mail addresses are removed. Attach" \
         "when Steam ARM starts and every minute" "now so the installed parts match?" "rules for those parts. Games, saves" \
         "settings it added, and puts back system settings it changed. Your games and sign-in stay in the client folder;" \
         "saves kept in the client folder, and"; do grep -qF -- "$p" "$CFG" || OUT="$OUT missing: $p"; done
check "dialog prose: hard-wrapped sentences joined" "[ -z \"\$OUT\" ]"

# ---------- item 15: KDE window rule, Plasma 5 fallback ----------
# PATH holds only these stubs and plain tools: the host's own kwriteconfig must never run (it writes the real kwinrulesrc).
K=$T/kde; mkdir -p "$K/b5" "$K/b6" "$K/none" "$K/sys" "$K/plasma"
printf '#!/bin/sh\nexit 0\n' > "$K/plasma/plasmashell"; chmod +x "$K/plasma/plasmashell"
mkdir -p "$K/home"; for x in sh awk tr grep paste cat rm mkdir; do ln -s "$(command -v "$x")" "$K/sys/$x"; done
for v in 5 6; do
  printf '#!/bin/sh\necho "w%s $*" >> "$KL"\n' "$v" > "$K/b$v/kwriteconfig$v"
  printf '#!/bin/sh\necho "r%s $*" >> "$KL"\necho "$CUR"\n' "$v" > "$K/b$v/kreadconfig$v"
  chmod +x "$K/b$v/kwriteconfig$v" "$K/b$v/kreadconfig$v"
done
KD=$T/kde.sh
{ echo "KWIN_MADE=$K/made"; fn kcfg_ver "$INST"; fn kwin_rule_remove "$INST"
  echo 'login_sh(){ sh -c "$1"; }; kwin_reload(){ echo reload >> "$KL"; }; say(){ echo "$*"; }'
  echo 'kwrite(){'; awk '/^  RID=steam-arm-frame$/{f=1} f{print} f && /^  fi$/{exit}' "$INST"; echo '}'; } > "$KD"
kd(){ rm -f "$K/log"; OUT=$( (unset XDG_CONFIG_HOME; export HOME=$K/home KL=$K/log CUR="$2" PATH="$1:$K/sys"; . "$KD"; eval "$3") 2>&1; cat "$K/log" 2>/dev/null); }
kd "$K/b5" "" kwrite
check "rule write: Plasma 5 only -> kwriteconfig5, rules list, reload" "has 'w5 --file kwinrulesrc --group steam-arm-frame --key wmclass steam' && has 'w5 --file kwinrulesrc --group General --key rules steam-arm-frame' && has reload && ! has w6"
kd "$K/b5:$K/b6" "a,b" kwrite
check "rule write: Plasma 6 present -> kwriteconfig6, existing rules kept" "has 'w6 .*--key rules a,b,steam-arm-frame' && has 'w6 .*--key count 3' && ! has w5"
kd "$K/none:$K/plasma" "" kwrite
check "rule write: KDE installed, neither tool -> skip line, nothing written" "has 'KDE window rule skipped: kwriteconfig6 / kwriteconfig5 not found' && ! has 'w[56]' && ! has reload"
kd "$K/none" "" kwrite
check "rule write: no KDE (GNOME, labwc, XFCE) -> no skip line, nothing written" "! has 'KDE window rule skipped' && ! has 'w[56]' && ! has reload"
check "kwin_rule_remove has its comment directly above (kcfg_ver keeps its own)" "grep -B1 '^kwin_rule_remove(){' '$INST' | head -1 | grep -q '^# Take a window rule group' && grep -B1 '^kcfg_ver(){' '$INST' | head -1 | grep -q '^# KDE config tools of Plasma 6'"
kd "$K/b5" "a,steam-arm-frame" kwin_rule_remove
check "rule removal: Plasma 5 -> kwriteconfig5 drops list entry and keys" "has 'w5 --file kwinrulesrc --group General --key rules a' && has 'w5 --file kwinrulesrc --group steam-arm-frame --key noborderrule --delete'"
kd "$K/none" "" kwin_rule_remove
check "rule removal: neither tool -> nothing" "[ -z \"\$OUT\" ]"
check "no kwriteconfig6-only call left in installer" "! grep -q 'kwriteconfig6 --file\|kreadconfig6 --file' '$INST'"

# ---------- item 14: Settings entry, .deb Setup entry ----------
awk '/<<.CFGDESK. /{f=1;next} /^CFGDESK$/{f=0} f' "$INST" > "$T/steam-arm-config.desktop"
check "Settings entry: Terminal=true, Exec + TryExec steam-arm-config" "grep -qx 'Terminal=true' $T/steam-arm-config.desktop && grep -qx 'Exec=/usr/local/bin/steam-arm-config' $T/steam-arm-config.desktop && grep -qx 'TryExec=/usr/local/bin/steam-arm-config' $T/steam-arm-config.desktop && grep -qx 'Name=Steam ARM Settings' $T/steam-arm-config.desktop"
command -v desktop-file-validate >/dev/null && check "Settings entry and .deb Setup entry validate" "desktop-file-validate $T/steam-arm-config.desktop && desktop-file-validate '$WORK/debian/steam-arm-setup.desktop'"
check "Settings entry written outside component switches (always with launcher)" "l=\$(grep -n '<<.CFGDESK.' '$INST' | cut -d: -f1); m=\$(grep -n '^  warn \"settings menu /usr/local/bin/steam-arm-config could not be written\"' '$INST' | cut -d: -f1); [ \$l -gt \$m ] && sed -n \"\$((l - 3)),\$((l - 1))p\" '$INST' | grep -qv '^if opt'"
ic(){ cp "$T/steam-arm-config.desktop" "$T/icon.desktop"
  ( r=$1; want_icons(){ return "$r"; }; eval "$(grep '^want_icons || sed -i .*steam-arm-config.desktop' "$INST" | sed "s#/usr/share/applications/steam-arm-config.desktop#$T/icon.desktop#")" ); grep '^Icon=' "$T/icon.desktop"; }
check "Settings entry icon: steam-arm with icons, generic theme icon when setup removed them" "[ \"\$(ic 0)\" = Icon=steam-arm ] && [ \"\$(ic 1)\" = Icon=preferences-system ]"
check "removal deletes Settings entry" "fn remove_all '$INST' | grep -q '/usr/share/applications/steam-arm-config.desktop'"
check ".deb: build-deb installs Setup entry" "grep -q 'debian/steam-arm-setup.desktop\" \"\$TREE/usr/share/applications/steam-arm-setup.desktop\"' '$WORK/build-deb.sh' && grep -qx 'Terminal=true' '$WORK/debian/steam-arm-setup.desktop'"
W=$T/wrap; mkdir -p "$W"
sed "s#/usr/share/steam-arm-setup/install.sh#$W/install.sh#g" "$WORK/bin/steam-arm-setup" > "$W/steam-arm-setup"
printf '#!/bin/sh\necho "install.sh args:[$*]"\n' > "$W/install.sh"; chmod +x "$W/steam-arm-setup" "$W/install.sh"
OUT=$(script -qec "sh $W/steam-arm-setup" /dev/null 2>&1 | tr -d '\r')
check "wrapper: no options in a terminal -> menu (install.sh, no args) without root" "has 'install.sh args:\[\]'"
OUT=$(sh "$W/steam-arm-setup" </dev/null 2>&1); RC=$?
check "wrapper: no terminal, not root -> run as root text" "[ $RC = 1 ] && has 'run as root'"
OUT=$(script -qec "sh $W/steam-arm-setup --defaults" /dev/null 2>&1 | tr -d '\r')
check "wrapper: options in a terminal, not root -> run as root text" "has 'run as root' && ! has 'install.sh args'"

# ---------- item 13: tray ----------
awk '/<<.TRAYDESK./{f=1;next} /^TRAYDESK$/{f=0} f' "$INST" > "$T/tray-autostart.desktop"
check "autostart entry: no OnlyShowIn (labwc and others)" "grep -qx 'Exec=/usr/local/bin/steam-arm-tray' $T/tray-autostart.desktop && ! grep -q OnlyShowIn $T/tray-autostart.desktop"
check "setup line: tray at login and at each start" "grep -q 'it appears in the panel at next login and whenever Steam ARM starts' '$INST'"
G=$T/gi/gi; mkdir -p "$G/repository"
cat > "$G/__init__.py" <<'EOF'
def require_version(*a):
    pass
EOF
cat > "$G/repository/__init__.py" <<'EOF'
import os, sys
LOG = []
class _Item:
    def __init__(self, label=""):
        self.label = label; self.sensitive = True; self.cb = None
    def connect(self, sig, cb): self.cb = cb
    def set_sensitive(self, v): self.sensitive = v
    def set_label(self, v): self.label = v
    def activate(self): self.cb(self)
class _Menu:
    def __init__(self): self.items = []
    def append(self, i): self.items.append(i)
    def show_all(self): pass
class Gtk:
    Menu = _Menu
    MenuItem = _Item
    class SeparatorMenuItem(_Item): pass
    @staticmethod
    def main_quit(): pass
class _Ind:
    def __init__(self): self.icon = None; self.theme = None; self.title = None
    def set_icon_theme_path(self, p): self.theme = p
    def set_icon_full(self, n, d): self.icon = n
    def set_title(self, t): self.title = t
    def set_status(self, s): pass
    def set_menu(self, m): self.menu = m
class AyatanaAppIndicator3:
    class IndicatorCategory: APPLICATION_STATUS = 0
    class IndicatorStatus: ACTIVE = 1
    class Indicator:
        @staticmethod
        def new(*a): return _Ind()
class GLib:
    class Error(Exception): pass
    @staticmethod
    def timeout_add_seconds(*a): pass
class _Info:
    def launch(self, files, ctx):
        LOG.append("gio-launch")
        if os.environ.get("GIO_FAIL"): raise GLib.Error("Unable to find terminal required for application")
        return True
class Gio:
    class DesktopAppInfo:
        @staticmethod
        def new(name):
            LOG.append("gio-new " + name)
            return _Info()
EOF
cat > "$T/traytest.py" <<'EOF'
import os, sys, signal, subprocess, shutil, importlib.util, tempfile
sys.path.insert(0, sys.argv[2])
spec = importlib.util.spec_from_file_location("tray", sys.argv[1]); tray = importlib.util.module_from_spec(spec); spec.loader.exec_module(tray)
from gi.repository import LOG
calls, kills = [], []
class P:
    def __init__(self, argv, **kw): calls.append(argv)
    # spawn() reaps its child in a thread (2.3.1)
    def wait(self): return 0
RP = subprocess.Popen
tray.subprocess.Popen = P
os.kill = lambda pid, sig: kills.append((pid, sig))
home = tempfile.mkdtemp(); os.environ["STEAM_ARM_HOME"] = home
running = [True]
tray.steam_running = lambda: running[0]
# game state from a flag: another title of this account (concurrent run, real game) must not change results
real_game_running, game = tray.game_running, [False]
tray.game_running = lambda: game[0]
t = tray.SteamTray()
labels = [i.label for i in t.menu.items if i.label]
def ok(name, cond): print(("PASS " if cond else "FAIL ") + name)
ok("tray: menu items", labels == ["Client: native ARM64", "Open Steam", "Open in Big Picture", "Open in desktop mode", "Store", "Library", "Friends", "Downloads", "Screenshots", "Steam Settings", "Stop Steam", "Steam ARM Settings", "View log", "Quit tray"])
item = {i.label: i for i in t.menu.items}
ok("tray: generic icon before client files", t.indicator.icon is None)
pub = os.path.join(home, ".local/share/Steam/public"); os.makedirs(pub); open(os.path.join(pub, "steam_tray_mono.png"), "w").close()
t.on_poll()
ok("tray: client icon after first start (poll)", t.indicator.icon == "steam_tray_mono" and t.indicator.theme == pub)
ok("tray: View log greyed while no log", item["View log"].sensitive is False)
LOGP = os.path.join(home, "steam-arm.log")
open(LOGP, "w").close(); t.on_poll()
# empty log opens as inode/x-empty (blank browser page on the box walk)
ok("tray: View log greyed while log is empty", item["View log"].sensitive is False)
n = len(calls); item["View log"].activate()
ok("tray: View log on empty log opens nothing", len(calls) == n)
with open(LOGP, "w") as h: h.write("steam-arm: sample line\n")
t.on_poll()
ok("tray: View log offered once log has a line", item["View log"].sensitive is True)
item["Stop Steam"].activate()
ok("tray: Stop -> steam-arm --shutdown, no signals", calls[-1] == ["/usr/local/bin/steam-arm", "--shutdown"] and kills == [])
ok("tray: Stop greyed while stopping", item["Stop Steam"].sensitive is False)
t.on_poll()
ok("tray: still stopping on next poll", item["Stop Steam"].sensitive is False)
t.stopping -= 61; t.on_poll()
ok("tray: Stop offered again 60 s after a stop that did not finish", item["Stop Steam"].sensitive is True)
running[0] = False; t.on_poll()
ok("tray: not running -> Open on, Stop off", item["Open Steam"].sensitive and not item["Stop Steam"].sensitive)
item["Open in Big Picture"].activate()
ok("tray: Big Picture -> steam-arm --bigpicture", calls[-1] == ["/usr/local/bin/steam-arm", "--bigpicture"])
real_which = tray.shutil.which
tray.shutil.which = lambda p: "/usr/bin/" + p if p in ("konsole", "less") else None
item["View log"].activate()
ok("tray: View log -> less at its end in first terminal", calls[-1] == ["/usr/bin/konsole", "-e", "/usr/bin/less", "+G", LOGP])
tray.shutil.which = lambda p: None
item["View log"].activate()
ok("tray: View log without terminal or less -> xdg-open", calls[-1] == ["xdg-open", LOGP])
tray.shutil.which = real_which
n = len(calls); item["Steam ARM Settings"].activate()
ok("tray: Settings -> desktop entry through GIO", "gio-new steam-arm-config.desktop" in LOG and len(calls) == n)
os.environ["GIO_FAIL"] = "1"
tray.shutil.which = lambda p: "/usr/bin/" + p if p in ("konsole", "xterm") else None
item["Steam ARM Settings"].activate()
ok("tray: Settings without GIO terminal -> first terminal found", calls[-1] == ["/usr/bin/konsole", "-e", "/usr/local/bin/steam-arm-config"])
tray.shutil.which = lambda p: "/usr/bin/foot" if p == "foot" else None
item["Steam ARM Settings"].activate()
ok("tray: terminal without option (foot)", calls[-1] == ["/usr/bin/foot", "/usr/local/bin/steam-arm-config"])
ok("tray: no signal_processes left", not hasattr(tray, "signal_processes"))
ok("tray: docstring names panel tray (any desktop), not Plasma only", (tray.__doc__ or "").startswith("Panel tray icon (StatusNotifier)"))
# uid from status: kernel shows a non-dumpable process's /proc folder as root-owned (folder owner simulated) (L22-3)
ch = RP([sys.executable, "-c", "import ctypes, time; ctypes.CDLL(None).prctl(15, b'sarmtrayt', 0, 0, 0); print('r', flush=True); time.sleep(30)"], stdout=subprocess.PIPE)
ch.stdout.readline()
real_stat = os.stat
class RootOwned: st_uid = 0
os.stat = lambda p, *a, **k: RootOwned() if p == "/proc/%d" % ch.pid else real_stat(p, *a, **k)
ok("tray: own process with root-owned /proc folder counted (uid from status)", tray.comm_matches(str(ch.pid), "sarmtrayt"))
os.stat = real_stat
ch.terminate(); ch.wait()
# Stop greyed while a title runs (MT-1)
g = RP(["/bin/sh", "-c", "sleep 30; :", "/x/ubuntu12_32/reaper", "SteamLaunch", "AppId=1"])
# real /proc scan, limited to this test's processes
real_listdir = os.listdir
os.listdir = lambda p=".": [str(os.getpid()), str(g.pid)] if p == "/proc" else real_listdir(p)
tray.game_running = real_game_running
running[0] = True; t.stopping = False; t.on_poll()
ok("tray: Stop greyed while a game runs", tray.game_running() and item["Stop Steam"].sensitive is False)
ok("tray: Big Picture and desktop mode greyed while a game runs",
   item["Open in Big Picture"].sensitive is False and item["Open in desktop mode"].sensitive is False)
g.terminate(); g.wait(); t.on_poll()
ok("tray: Stop offered again once the game ended", not tray.game_running() and item["Stop Steam"].sensitive is True)
ok("tray: Big Picture and desktop mode offered again once the game ended",
   item["Open in Big Picture"].sensitive is True and item["Open in desktop mode"].sensitive is True)
os.listdir = real_listdir
EOF
tp=0
while IFS= read -r l; do
  case "$l" in PASS*) echo "$l"; pass=$((pass + 1)); tp=$((tp + 1));; FAIL*) echo "$l"; fail=$((fail + 1)); tp=$((tp + 1));; *) echo "     $l";; esac
done < <(python3 "$T/traytest.py" "$TRAY" "$T/gi" 2>&1)
OUT="$tp of $(grep -c '^ok(' "$T/traytest.py") tray checks ran"
check "tray: all checks ran (no crash)" "[ $tp = \$(grep -c '^ok(' '$T/traytest.py') ]"

echo; echo "test_menu_tray_22: $pass passed, $fail failed"
[ "$fail" = 0 ]
