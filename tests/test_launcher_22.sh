#!/bin/bash
# 2.2 launcher group: --help before root check, log cap, lnote (deduped desktop notice), page size stop,
# render node warning, first-start failure stop + one retry after bootstrap self-update, uid-scoped running
# checks (launcher, settings menu, tray), setup hints hidden from menu. Blocks extracted from the installer copy
# in ~/.cache/sarm<NN>-work (paths.sh) into /tmp; id, getconf, stat, pgrep, gdbus, ./steam stubbed.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
CFG=${SARM_CFG:-$(dirname "$INST")/steam-arm-config}
T=$(mktemp -d /tmp/sarm232-l22.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
block(){ A=$1 B=$2 awk '!f && $0 ~ ENVIRON["A"] {f=1; print; next} f {print} f && $0 ~ ENVIRON["B"] {exit}' "${3:-$L}"; }
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
check "launcher parses (sh -n)" "sh -n $L"
check "installer bash -n, settings menu bash -n" "bash -n '$INST' && bash -n '$CFG'"
check "embedded settings menu identical" "awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f' '$INST' | cmp -s - '$CFG'"
mkdir -p "$T/root" "$T/run"
export STUB=$T/run

# ---------- GAM-4: --help before root check ----------
printf '#!/bin/sh\n[ "$1" = -u ] && { echo 0; exit 0; }\nexec /usr/bin/id "$@"\n' > "$T/root/id"; chmod +x "$T/root/id"
OUT=$(PATH="$T/root:$PATH" sh "$L" --help 2>&1); rc=$?
check "--help as root: usage, rc 0" "[ $rc = 0 ] && printf '%s\n' \"\$OUT\" | grep -q '^Usage: steam-arm'"
check "--help lists --bigpicture, --desktop, --shutdown" "printf '%s\n' \"\$OUT\" | grep -q '^  steam-arm --bigpicture ' && printf '%s\n' \"\$OUT\" | grep -q '^  steam-arm --desktop ' && printf '%s\n' \"\$OUT\" | grep -q '^  steam-arm --shutdown '"
OUT=$(PATH="$T/root:$PATH" sh "$L" -h 2>&1); rc=$?
check "-h as root: usage" "[ $rc = 0 ] && printf '%s\n' \"\$OUT\" | grep -q '^Usage'"
OUT=$(PATH="$T/root:$PATH" sh "$L" 2>&1); rc=$?
check "no option as root: refused, rc 1" "[ $rc = 1 ] && printf '%s\n' \"\$OUT\" | grep -q 'not as root'"
OUT=$(PATH="$T/root:$PATH" sh "$L" --bigpicture 2>&1); rc=$?
check "--bigpicture as root: refused" "[ $rc = 1 ] && printf '%s\n' \"\$OUT\" | grep -q 'not as root'"
l_help=$(grep -n '^  -h|--help|help)$' "$L" | cut -d: -f1); l_root=$(grep -n '^if \[ "\$(id -u)" = 0 \]; then$' "$L" | cut -d: -f1)
check "launcher: one help case, before root check" "[ \$(grep -c -- '-h|--help|help)' $L) = 1 ] && [ $l_help -lt $l_root ]"

# ---------- log cap ----------
CAP=$T/cap.sh
{ echo 'LOG=$ARMHOME/steam-arm.log'; grep -A1 '^# Log cap: ' "$L" | tail -1; } > "$CAP"
check "log cap line extracted" "grep -q 'mv -f \"\$LOG\" \"\$LOG.1\"' $CAP"
mkdir -p "$T/ah"
head -c 1048577 /dev/zero > "$T/ah/steam-arm.log"; echo old > "$T/ah/steam-arm.log.1"
ARMHOME=$T/ah sh "$CAP"
check "log over 1 MB -> moved to .1 (old .1 replaced)" "[ ! -e $T/ah/steam-arm.log ] && [ \$(stat -c %s $T/ah/steam-arm.log.1) = 1048577 ]"
head -c 1048576 /dev/zero > "$T/ah/steam-arm.log"; rm -f "$T/ah/steam-arm.log.1"
ARMHOME=$T/ah sh "$CAP"
check "log at 1 MB -> kept" "[ -f $T/ah/steam-arm.log ] && [ ! -e $T/ah/steam-arm.log.1 ]"
rm -f "$T/ah/"*; ARMHOME=$T/ah sh "$CAP"
check "no log -> nothing created" "[ -z \"\$(ls $T/ah)\" ]"
l_cap=$(grep -n '^# Log cap: ' "$L" | cut -d: -f1); l_log=$(grep -n '^LOG="\$ARMHOME/steam-arm.log"$' "$L" | cut -d: -f1)
l_lw=$(grep -n '^lwarn()' "$L" | cut -d: -f1)
check "log cap after LOG, before first lwarn definition" "[ $l_log -lt $l_cap ] && [ $l_cap -lt $l_lw ]"

# ---------- lnote ----------
LN=$T/lnote.sh
{ echo 'LOG=$T/l.log'; grep '^lwarn()' "$L"; block '^lnote\(\)' '^}$'; echo 'notice(){ echo "$*" >> "$STUB/notice.log"; }'; } > "$LN"
lrun(){ ( export T XDG_RUNTIME_DIR=$T/run; . "$LN"; eval "$1" ) 2>/dev/null; wait; command sleep 0.2; }
rm -f "$STUB"/* "$T/l.log"
lrun 'DISPLAY=; WAYLAND_DISPLAY=; lnote "fix A"'
check "lnote without display: logged, no notice" "grep -q ' fix A$' $T/l.log && [ ! -f $STUB/notice.log ]"
rm -f "$STUB"/* "$T/l.log"
lrun 'DISPLAY=:0; lnote "fix A"; lnote "fix A"'
lrun 'DISPLAY=:0; lnote "fix A"'
check "lnote with display, no terminal: one notice for same text (per login session)" "[ \$(grep -c . $STUB/notice.log) = 1 ] && grep -q '^0 Steam ARM: warning fix A 20000$' $STUB/notice.log && [ \$(grep -c 'fix A' $T/l.log) = 3 ]"
lrun 'DISPLAY=:0; lnote "fix B"'
check "lnote: other text -> second notice" "[ \$(grep -c . $STUB/notice.log) = 2 ] && grep -q 'warning fix B' $STUB/notice.log"
rm -f "$STUB"/*
lrun 'WAYLAND_DISPLAY=wayland-0; DISPLAY=; lnote "fix C"'
check "lnote: Wayland display counts" "grep -q 'fix C' $STUB/notice.log"
rm -f "$STUB"/*
if command -v script >/dev/null 2>&1; then
  script -qc "bash -c 'export T=$T STUB=$STUB XDG_RUNTIME_DIR=$T/run DISPLAY=:0; . $LN; lnote \"fix T\"; sleep 0.3'" /dev/null >/dev/null 2>&1
  check "lnote from a terminal: no notice (stderr line suffices)" "[ ! -f $STUB/notice.log ] && grep -q 'fix T' $T/l.log"
fi
# actionable warnings use lnote; informational ones stay lwarn
check "Mali, GLX (2), display mode, Bluetooth power, render node -> lnote" "grep -q 'lnote \"Mali drivers inside' $L && [ \$(grep -c 'LAX_BAD=1; lnote' $L) = 2 ] && grep -q 'lnote \"display mode could not be put back' $L && grep -q 'lnote \"Bluetooth adapter left off by client and could not' $L && [ \$(grep -c 'lnote \"No GPU render node' $L) = 4 ]"
check "informational warnings stay log only" "grep -q 'lwarn \"display mode put back after game' $L && grep -q 'lwarn \"kde-input-prompt could not be applied' $L && grep -q 'lwarn \"client did not act on -shutdown' $L && grep -q 'lwarn \"\${msg:-steam-arm-fexpatch failed}\"' $L"
l_note=$(grep -n '^notice()' "$L" | cut -d: -f1); l_lnote=$(grep -n '^lnote()' "$L" | cut -d: -f1)
l_mali=$(grep -n 'lnote "Mali drivers inside' "$L" | cut -d: -f1)
check "notice and lnote defined once, before first use" "[ \$(grep -c '^notice()' $L) = 1 ] && [ \$(grep -c '^lnote()' $L) = 1 ] && [ $l_note -lt $l_lnote ] && [ $l_lnote -lt $l_mali ]"

# ---------- page size ----------
PS=$T/ps.sh
block '^# Emulation needs 4K pages' '^fi$' > "$PS"
check "page size block extracted" "grep -q 'getconf PAGESIZE' $PS && grep -q STEAM_ARM_IGNORE_PAGESIZE $PS"
psrun(){ printf '#!/bin/sh\necho %s\n' "$1" > "$T/gc/getconf"; chmod +x "$T/gc/getconf"
  ( PATH="$T/gc:$PATH"; lwarn(){ echo "LWARN $*"; }; stop(){ echo "STOP $1"; exit 1; }; unset STEAM_ARM_IGNORE_PAGESIZE; eval "$2"; . "$PS"; echo STARTED ); }
mkdir -p "$T/gc"
OUT=$(psrun 4096)
check "4K pages -> starts" "[ \"\$OUT\" = STARTED ]"
OUT=$(psrun 16384)
check "16K pages -> lwarn + stop with Pi and general fix, override named" "printf '%s\n' \"\$OUT\" | grep -q '^LWARN Kernel page size is 16384 bytes' && printf '%s\n' \"\$OUT\" | grep -q '^STOP .*needs 4096.*select page-size.*kernel=kernel8.img.*4K page kernel.*STEAM_ARM_IGNORE_PAGESIZE=1 (environment, or a line in /etc/steam-arm/steam-arm.conf) skips' && ! printf '%s\n' \"\$OUT\" | grep -q STARTED"
OUT=$(psrun 65536)
check "64K pages -> stop" "printf '%s\n' \"\$OUT\" | grep -q '^STOP Kernel page size is 65536'"
OUT=$(psrun 16384 'STEAM_ARM_IGNORE_PAGESIZE=1')
check "16K + STEAM_ARM_IGNORE_PAGESIZE=1 -> starts" "[ \"\$OUT\" = STARTED ]"
OUT=$(psrun 16384 'STEAM_ARM_IGNORE_PAGESIZE=0')
check "16K + STEAM_ARM_IGNORE_PAGESIZE=0 -> stop" "printf '%s\n' \"\$OUT\" | grep -q '^STOP'"
l_ps=$(grep -n '^# Emulation needs 4K pages' "$L" | cut -d: -f1); l_lse=$(grep -n '^# Client needs Armv8.1 atomics' "$L" | cut -d: -f1)
l_sd=$(grep -n '^  --shutdown) stop_client; exit \$?;;$' "$L" | cut -d: -f1); l_kde=$(grep -n '^KDEIN=' "$L" | cut -d: -f1)
l_first=$(grep -n '^if \[ ! -f "\$S/linuxarm64/steamclient.so" \] || \[ -f "\$NVER" \]; then$' "$L" | cut -d: -f1)
l_conf=$(grep -n '^\[ -r /etc/steam-arm/steam-arm.conf \] && \. /etc/steam-arm/steam-arm.conf$' "$L" | cut -d: -f1)
check "settings file (kept STEAM_ARM_IGNORE_PAGESIZE) sourced before page size check" "[ -n '$l_conf' ] && [ ${l_conf:-99999} -lt $l_ps ]"
check "page size check after --shutdown and LSE check, before KDE step and client start" "[ $l_sd -lt $l_ps ] && [ $l_lse -lt $l_ps ] && [ $l_ps -lt $l_kde ] && [ $l_ps -lt $l_first ]"

# ---------- render node ----------
RN=$T/rn.sh
block '^# GPU access: ' '^fi$' | sed "s#/dev/dri/renderD\\*\\([^)]\\)#$T/dri/renderD*\\1#g; s#for r in /dev/dri/renderD\\*#for r in $T/dri/renderD*#; s#-e /dev/mali0#-e $T/mali0#" > "$RN"
check "render node block extracted" "grep -q 'for r in $T/dri/renderD\\*' $RN"
rnrun(){ ( lnote(){ echo "LNOTE $1"; }; eval "${1:-}"; . "$RN"; echo STARTED ); }
mkdir -p "$T/dri"
OUT=$(rnrun)
check "no render node -> note: none found" "printf '%s\n' \"\$OUT\" | grep -q '^LNOTE No GPU render node (/dev/dri/renderD\*) found; games draw on CPU' && printf '%s\n' \"\$OUT\" | tail -1 | grep -q STARTED"
: > "$T/mali0"; OUT=$(rnrun); rm -f "$T/mali0"
check "no render node, closed Mali driver (/dev/mali0) -> panfrost/panthor kernel fix, no driver-loaded hint" "printf '%s\n' \"\$OUT\" | grep -q '^LNOTE No GPU render node .* closed Mali driver (mali_kbase) in use; games draw on CPU. Fix: kernel with Mesa.s panfrost or panthor' && ! printf '%s\n' \"\$OUT\" | grep -q 'Check that kernel GPU driver is loaded'"
: > "$T/dri/renderD128"; chmod 000 "$T/dri/renderD128"
OUT=$(rnrun)
g=$(stat -c %G "$T/dri/renderD128")
check "node without access -> note names group fix (usermod -aG <node group>)" "printf '%s\n' \"\$OUT\" | grep -q \"^LNOTE No GPU render node .* readable and writable by account \$(id -un); games draw on CPU. Fix: sudo usermod -aG $g \$(id -un), then log out\""
OUT=$(rnrun 'stat(){ echo root; }')
check "node owned by group root -> no usermod advice, permissions hint" "printf '%s\n' \"\$OUT\" | grep -q '^LNOTE .*Check permissions of .*renderD\\* (udev rules' && ! printf '%s\n' \"\$OUT\" | grep -q usermod"
chmod 600 "$T/dri/renderD128"
OUT=$(rnrun)
check "node readable and writable -> no note" "[ \"\$OUT\" = STARTED ]"
: > "$T/dri/renderD129"; chmod 000 "$T/dri/renderD128"; chmod 600 "$T/dri/renderD129"
OUT=$(rnrun)
check "second node accessible -> no note" "[ \"\$OUT\" = STARTED ]"
chmod 400 "$T/dri/renderD128"; rm -f "$T/dri/renderD129"
OUT=$(rnrun)
check "read-only node -> note" "printf '%s\n' \"\$OUT\" | grep -q '^LNOTE'"
chmod 600 "$T/dri/renderD128"
l_rn=$(grep -n '^# GPU access: ' "$L" | cut -d: -f1)
check "render check after page size, before client start" "[ $l_ps -lt $l_rn ] && [ $l_rn -lt $l_first ]"

# ---------- first start ----------
FS=$T/fs.sh
# start lock state (2.3 guard) not part of this block: stand-in
{ echo 'start_state(){ :; }'; block '^updated_exit\(\)' '^}$'; grep '^client_running()' "$L"
  block '^if \[ ! -f "\$S/linuxarm64/steamclient.so" \] \|\| \[ -f "\$NVER" \]; then$' '^fi$'; } > "$FS"
check "first start block extracted" "grep -q '^updated_exit()' $FS && grep -q 'Start Steam ARM again to finish download' $FS"
mkdir -p "$T/fsbin" "$T/D" "$T/S/logs"
# pgrep: client up while $STUB/up holds a count above 0 (each call uses one)
cat > "$T/fsbin/pgrep" <<'EOF'
#!/bin/sh
n=$(cat "$STUB/up" 2>/dev/null || echo 0); [ "$n" -gt 0 ] || exit 1; echo $((n - 1)) > "$STUB/up"
EOF
# ./steam: behaviour per call from $STUB/plan lines: ok (files appear), upd (bootstrap update + exit 0),
# r42 (exit 42), self (update, client restarts itself, files appear), selfnf (same, no files), fail (exit 1)
cat > "$T/D/steam" <<'EOF'
#!/bin/sh
echo "steam $*" >> "$STUB/steam.log"
a=$(head -n 1 "$STUB/plan"); sed -i 1d "$STUB/plan"
echo "[2026-10-05 10:00:00] Startup - updater built" >> "$BOOTLOG"
case "$a" in
  ok) mkdir -p "$S/linuxarm64"; : > "$S/linuxarm64/steamclient.so"; exit 0;;
  upd) echo "[2026-10-05 10:00:01] Update complete, launching..." >> "$BOOTLOG"; exit 0;;
  r42) exit 42;;
  self) echo "[2026-10-05 10:00:01] Update complete, launching..." >> "$BOOTLOG"; echo 3 > "$STUB/up"
        mkdir -p "$S/linuxarm64"; : > "$S/linuxarm64/steamclient.so"; exit 0;;
  selfnf) echo "[2026-10-05 10:00:01] Update complete, launching..." >> "$BOOTLOG"; echo 3 > "$STUB/up"; exit 0;;
  *) exit 1;;
esac
EOF
chmod +x "$T/fsbin/pgrep" "$T/D/steam"
fsrun(){ rm -rf "$STUB"/* "$T/S/linuxarm64" "$T/S/logs/"* "$T/ah/.steam"; mkdir -p "$T/ah/.steam"
  printf '%s\n' "$@" > "$STUB/plan"
  ( export PATH="$T/fsbin:$PATH" S=$T/S BOOTLOG=$T/S/logs/bootstrap_log.txt
    ARMHOME=$T/ah GPUI=-gamepadui; cd "$T/D"
    sleep(){ :; }; lwarn(){ echo "LWARN $*"; }; stop(){ echo "STOP $1"; exit 1; }
    first_start_notice(){ echo x >> "$STUB/fsn"; command sleep 0.05; }
    set --; . "$FS"; echo "CONTINUE rc=$?" ) 2>&1; }
OUT=$(fsrun ok)
check "first start completes -> continues to normal start, one client call, sdk link" "printf '%s\n' \"\$OUT\" | tail -1 | grep -q '^CONTINUE' && [ \$(grep -c . $STUB/steam.log) = 1 ] && [ -L $T/ah/.steam/sdkarm64 ] && ! printf '%s\n' \"\$OUT\" | grep -q LWARN"
check "first start call: no -noverifyfiles" "grep -q '^steam -deckard -steamos3 -gamepadui$' $STUB/steam.log"
OUT=$(fsrun fail)
check "files missing, no update -> lwarn + stop: start again to finish download, one call" "printf '%s\n' \"\$OUT\" | grep -q '^LWARN Steam client did not finish its first start' && printf '%s\n' \"\$OUT\" | grep -q '^STOP .*steamclient.so missing). Start Steam ARM again to finish download. Details: .*bootstrap_log.txt' && [ \$(grep -c . $STUB/steam.log) = 1 ] && ! printf '%s\n' \"\$OUT\" | grep -q CONTINUE"
OUT=$(fsrun upd ok)
check "bootstrap self-update exit -> started once more, then continues" "[ \$(grep -c . $STUB/steam.log) = 2 ] && printf '%s\n' \"\$OUT\" | grep -q '^LWARN client exited after applying its update during first start; starting it again' && printf '%s\n' \"\$OUT\" | tail -1 | grep -q CONTINUE"
OUT=$(fsrun upd upd ok)
check "second self-update exit without files -> stop (one retry only)" "[ \$(grep -c . $STUB/steam.log) = 2 ] && printf '%s\n' \"\$OUT\" | grep -q '^STOP .*finish download' && [ \$(grep -c 'starting it again' <<< \"\$OUT\") = 1 ]"
OUT=$(fsrun r42 ok)
check "status 42 -> started once more" "[ \$(grep -c . $STUB/steam.log) = 2 ] && printf '%s\n' \"\$OUT\" | tail -1 | grep -q CONTINUE"
OUT=$(fsrun self)
check "files there after first call even with update line -> no retry" "[ \$(grep -c . $STUB/steam.log) = 1 ] && printf '%s\n' \"\$OUT\" | tail -1 | grep -q CONTINUE"
OUT=$(fsrun selfnf ok)
check "client restarted itself, ends without files -> waited, no second start, stop" "[ \$(grep -c . $STUB/steam.log) = 1 ] && printf '%s\n' \"\$OUT\" | grep -q '^STOP .*finish download'"
# self-restarted client that writes the files while it runs: launcher exits 0 after it (client already ran)
cat > "$T/fsbin/pgrep" <<'EOF'
#!/bin/sh
n=$(cat "$STUB/up" 2>/dev/null || echo 0); [ "$n" -gt 0 ] || exit 1; echo $((n - 1)) > "$STUB/up"
[ "$n" = 1 ] && [ -f "$STUB/mkfile" ] && { mkdir -p "$S/linuxarm64"; : > "$S/linuxarm64/steamclient.so"; }
exit 0
EOF
OUT=$(fsrun selfnf ok; echo "rc=$?")
check "client restarted itself, without files at exit: no second start, stop" "[ \$(grep -c . $STUB/steam.log) = 1 ] && printf '%s\n' \"\$OUT\" | grep -q '^STOP'"
OUT=$( rm -rf "$STUB"/* "$T/S/linuxarm64" "$T/S/logs/"*; echo selfnf > "$STUB/plan"; touch "$STUB/mkfile"
  ( export PATH="$T/fsbin:$PATH" S=$T/S BOOTLOG=$T/S/logs/bootstrap_log.txt ARMHOME=$T/ah GPUI=; cd "$T/D"
    sleep(){ :; }; lwarn(){ echo "LWARN $*"; }; stop(){ echo "STOP $1"; exit 1; }; first_start_notice(){ :; }
    set --; . "$FS"; echo CONTINUE ) 2>&1; echo "rc=$?")
check "client restarted itself and wrote files -> launcher exits 0 after it, no second start" "[ \"\$OUT\" = rc=0 ] && [ \$(grep -c . $STUB/steam.log) = 1 ]"
# second pass: bootstrap updates and restarts itself again; that client is waited for, not stopped (L22-1)
OUT=$( rm -rf "$STUB"/* "$T/S/linuxarm64" "$T/S/logs/"*; printf 'upd\nselfnf\n' > "$STUB/plan"; touch "$STUB/mkfile"
  ( export PATH="$T/fsbin:$PATH" S=$T/S BOOTLOG=$T/S/logs/bootstrap_log.txt ARMHOME=$T/ah GPUI=; cd "$T/D"
    sleep(){ :; }; lwarn(){ echo "LWARN $*"; }; stop(){ echo "STOP $1"; exit 1; }; first_start_notice(){ :; }
    set --; . "$FS"; echo CONTINUE ) 2>&1; echo "rc=$?")
check "retry run restarts itself and writes files -> waited, exit 0, no stop" "printf '%s\n' \"\$OUT\" | tail -1 | grep -qx rc=0 && ! printf '%s\n' \"\$OUT\" | grep -q '^STOP' && [ \$(grep -c . $STUB/steam.log) = 2 ]"
check "first_start_notice: once at start; started again only when its watcher ended" "grep -q 'kill -0 \"\$NOTEWATCH\" 2>/dev/null || { first_start_notice' $FS"
check "old silent exit 1 gone" "! grep -q '\[ -f \"\$S/linuxarm64/steamclient.so\" \] || exit 1' $L"
check "stop() comment no longer claims 'before any write'" "! grep -q 'Stop before any write' $L"

# ---------- uid-scoped running checks ----------
check "launcher: Remote Play pre-start check uses own account's client" "grep -q 'steam-arm-remoteplay >/dev/null 2>&1 && ! client_running; then' $L && ! grep -q '! pgrep -x steam' $L"
SR=$T/sr.sh
{ grep '^conf_get()' "$CFG"; block '^game_user\(\)\{' '^}$' "$CFG"; block '^steam_running\(\)\{' '^}$' "$CFG"; } > "$SR"
check "settings menu steam_running extracted" "grep -q 'pgrep -u \"\$u\" -x steam' $SR"
printf '#!/bin/sh\necho "$*" >> "$STUB/pg.log"; exit 0\n' > "$T/fsbin/pgrep"; chmod +x "$T/fsbin/pgrep"
me=$(id -un)
srrun(){ rm -f "$STUB/pg.log"; printf 'GAMEUSER=%s\n' "$1" > "$T/conf"; ( PATH="$T/fsbin:$PATH" SA_CONF=$T/conf; . "$SR"; steam_running ); }
srrun "$me"
check "menu steam_running: game account only (pgrep -u GAMEUSER)" "[ \"\$(cat $STUB/pg.log)\" = '-u $me -x steam' ]"
srrun nosuchuser-sarm
check "menu steam_running: unknown GAMEUSER -> account game_user falls back to" "[ \"\$(cat $STUB/pg.log)\" = '-u $me -x steam' ]"
rm -f "$STUB/pg.log"; ( PATH="$T/fsbin:$PATH"; . "$SR"; game_user(){ :; }; steam_running )
check "menu steam_running: no account resolved -> any account (conservative)" "[ \"\$(cat $STUB/pg.log)\" = '-x steam' ]"
# tray: pids_by_comm counts only this account's processes
TP=$T/tray.py
awk '/^cat > \/usr\/local\/bin\/steam-arm-tray <<.TRAYPY.$/{f=1;next} /^TRAYPY$/{f=0} f' "$INST" \
  | awk '/^def proc_uid/{f=1} /^def signal_processes/{f=0} f' > "$TP"
cp "$(command -v sleep)" "$T/steam"; "$T/steam" 5 & SP=$!
command sleep 0.2
OUT=$(python3 - "$TP" "$SP" <<'PY'
import os, sys
ns = {"os": os}
exec(open(sys.argv[1]).read(), ns)
pid = int(sys.argv[2])
a = pid in ns["pids_by_comm"]("steam") and ns["steam_running"]()
os.getuid = lambda: 4242
b = pid in ns["pids_by_comm"]("steam")
print("own=%s other=%s" % (a, b))
PY
)
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
check "tray: own steam counted, same process under other uid not" "[ \"\$OUT\" = 'own=True other=False' ]"

# ---------- setup hints only outside menu ----------
HB=$T/hints.sh
block '^# Command line hints only outside the settings menu' '^EOM$' "$INST" > "$HB"
check "setup hints block extracted" "grep -q 'Uninstall:' $HB"
OUT=$(env -u STEAM_ARM_FROM_MENU bash "$HB")
check "command line run: hints shown" "printf '%s\n' \"\$OUT\" | grep -q 're-run with --select' && printf '%s\n' \"\$OUT\" | grep -q 'Settings: *steam-arm-config' && printf '%s\n' \"\$OUT\" | grep -q 'Uninstall:'"
OUT=$(STEAM_ARM_FROM_MENU=1 bash "$HB"; echo "rc=$?")
check "menu run: hints hidden, rc 0" "[ \"\$OUT\" = rc=0 ]"
check "menu passes STEAM_ARM_FROM_MENU=1 to setup (progress screen path)" "grep -q 'STEAM_ARM_ALLOW_ARMV80\"} STEAM_ARM_FROM_MENU=1 .*\"\${cmd\[@\]}\" \"\$@\"; rc=' '$CFG'"
check "summary keeps client home, launch, first start, optional lines" "awk '/^say \"11\\/11  done\"\$/{f=1} f&&/^# Command line hints/{exit} f' '$INST' | grep -q 'Launch:' && awk '/^say \"11\\/11  done\"\$/{f=1} f&&/^# Command line hints/{exit} f' '$INST' | grep -q 'Optional:'"

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
