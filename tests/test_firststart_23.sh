#!/bin/bash
# 2.3 launcher: one client start at once (repeated clicks during first start), tray Open items while a start runs,
# menu icon redraw, --open and tray Steam pages. Blocks extracted from the installer (paths.sh); stand-in bootstrap, notice, pgrep, zenity, gdbus.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-fs.XXXXXX)
trap 'touch "$T/release" "$T/web"; sleep 0.3; rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
blk(){ A=$1 B=$2 awk '!f && $0 ~ ENVIRON["A"] {f=1; print; next} f {print} f && $0 ~ ENVIRON["B"] {exit}' "$L"; }
G=$T/guard.sh; blk '^# One client start at once' '^fi$' > "$G"
BP=$T/bp.sh; blk '^boot_phase\(\)' '^}$' > "$BP"
SL=$T/sl.sh; blk '^# Client start lock \(guard below\)' '^}$' > "$SL"
OUT=$(cat "$G")
check "FS1 guard block present (lock, busy notice, holder), parses" "grep -q 'flock -n 7 || { start_busy; exit 0; }' $G && grep -q '^start_hold()' $G && sh -n $G"
check "FS1b lock path (runtime folder, else client home) and lock reader defined before --shutdown and --open" "grep -q '^STARTLOCK=\"\$XDG_RUNTIME_DIR/steam-arm-start.lock\"' $SL && grep -q '^start_locked()' $SL && [ \$(grep -n '^# Client start lock (guard below)' $L | cut -d: -f1) -lt \$(grep -n '^  --shutdown) stop_client' $L | cut -d: -f1) ]"
ln(){ grep -n -- "$1" "$L" | head -1 | cut -d: -f1; }
l_g=$(ln '^# One client start at once'); l_bp=$(ln '^boot_phase()'); l_pad=$(ln '^# Pause steam-arm-pad-xbox')
l_sw=$(ln '^  stop_client || exit 1$'); l_tray=$(ln 'setsid steam-arm-tray'); l_fw=$(ln '^FEXWATCH=\$!$'); l_icon=$(ln '^UICON=')
check "FS2 guard after boot_phase, before pad service pause, watchers, icon waiter, tray and interface switch stop" \
  "[ -n '$l_g' ] && [ ${l_bp:-0} -lt ${l_g:-0} ] && [ ${l_g:-0} -lt ${l_pad:-0} ] && [ ${l_g:-0} -lt ${l_fw:-0} ] && [ ${l_g:-0} -lt ${l_icon:-0} ] && [ ${l_g:-0} -lt ${l_tray:-0} ] && [ ${l_g:-0} -lt ${l_sw:-0} ]"
n_first=$(grep -c '^ *start_state "first \$(stat -c %s "\$BOOTLOG" 2>/dev/null || echo 0)"$' "$L"); n_start=$(grep -c '^ *start_state start$' "$L")
l_nf=$(ln '^  start_state "first'); l_nsteam=$(ln '^    \./steam -deckard -steamos3 \${GPUI:+"\$GPUI"} "\$@"$')
l_ns=$(grep -n '^start_state start$' "$L" | cut -d: -f1); l_nloop=$(grep -n '^  \./steam -deckard -steamos3 \${GPUI:+"\$GPUI"} -noverifyfiles' "$L" | cut -d: -f1)
check "FS3 state: first start (native and x86) and normal start (native and x86) marked, before client runs" \
  "[ '$n_first' = 2 ] && [ '$n_start' = 2 ] && [ ${l_nf:-0} -lt ${l_nsteam:-0} ] && [ -n '$l_ns' ] && [ ${l_ns:-0} -lt ${l_nloop:-0} ]"

# mini launcher: guard, then stand-in client start (bootstrap writes log, waits for release; window process on "web")
mkdir -p "$T/bin" "$T/run" "$T/AH" "$T/S/logs"
cat > "$T/bin/pgrep" <<'EOF'
#!/bin/sh
case "$*" in *steamwebhelper*) [ -f "$T/web" ];; *) exit 1;; esac
EOF
cat > "$T/bin/zenity" <<'EOF'
#!/bin/sh
echo "ZENITY $*" >> "$T/zen"; sleep 1
EOF
chmod 755 "$T/bin/pgrep" "$T/bin/zenity"
M=$T/mini.sh
{ echo 'LOG=$T/l.log; ARMHOME=$T/AH; XDG_RUNTIME_DIR=$T/run; S=$T/S; BOOTLOG=$T/S/logs/bootstrap_log.txt'
  echo 'notice(){ echo "NOTICE $*" >> "$T/notes"; [ -f "$T/nonotice" ] || echo 41; }'
  cat "$SL" "$BP" "$G"
  cat <<'EOF'
echo "CLIENT_START $$" >> "$T/events"
start_state "first $(stat -c %s "$BOOTLOG" 2>/dev/null || echo 0)"
ls -l /proc/self/fd/ > "$T/clientfd.$$"
echo '[2026-10-08 18:47:36] Startup - updater built Sep  3 2026' >> "$BOOTLOG"
echo '[2026-10-08 18:47:43] [ 10%] Downloading update (70,000 of 663,571 KB)...' >> "$BOOTLOG"
n=0; while [ ! -f "$T/release" ] && [ $n -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
start_state start
n=0; while [ ! -f "$T/quit" ] && [ $n -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
echo "CLIENT_END $$" >> "$T/events"
EOF
} > "$M"
export T PATH="$T/bin:$PATH"
click(){ DISPLAY=${CDISP-:9} WAYLAND_DISPLAY= timeout 20 sh "$M" 2>>"$T/err" </dev/null; }
DISPLAY=:9 WAYLAND_DISPLAY= sh "$M" 2>/dev/null </dev/null &
MAIN=$!
n=0; until grep -q 'Downloading update' "$T/S/logs/bootstrap_log.txt" 2>/dev/null || [ $n -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
rcs=; for i in 1 2 3 4 5; do click; rcs="$rcs$?"; done
OUT=$(cat "$T/events" "$T/notes" 2>/dev/null)
check "FS4 5 launches during first start download: one client start, each exits 0" "[ \$(grep -c CLIENT_START $T/events) = 1 ] && [ '$rcs' = 00000 ]"
check "FS5 popup text with download percentage" "[ \$(grep -c 'Steam ARM is still setting up: downloading client files (10% of 648 MB). Steam opens by itself when done. 10000\$' $T/notes) = 5 ]"
check "FS6 one notice replaced in place (first id 0, then id from notice service)" "[ \"\$(cut -d' ' -f2 $T/notes | paste -sd,)\" = '0,41,41,41,41' ]"
check "FS7 launcher log notes each refused start" "[ \$(grep -c 'start while client starts: not started again (Steam ARM is still setting up' $T/l.log) = 5 ]"
OUT=$(cat "$T"/clientfd.* 2>/dev/null)
check "FS8 client start holds no lock fd (client and helpers never keep it)" "[ -n \"\$OUT\" ] && ! grep -q steam-arm-start.lock <<<\"\$OUT\""
echo '[2026-10-08 18:49:04] Extracting package...' >> "$T/S/logs/bootstrap_log.txt"
: > "$T/notes"; click
OUT=$(cat "$T/notes")
check "FS9 unpack phase shown" "grep -q 'Steam ARM is still setting up: unpacking client files. Steam opens' $T/notes"
: > "$T/err"; : > "$T/notes"; CDISP= click
OUT=$(cat "$T/err")
check "FS10 no display: text on stderr, no notice" "grep -q '^steam-arm: Steam ARM is still setting up: unpacking client files' $T/err && [ ! -s $T/notes ]"
: > "$T/notes"; : > "$T/nonotice"; click & c1=$!; click & c2=$!; wait "$c1" "$c2"
OUT=$(cat "$T/zen" 2>/dev/null)
check "FS11 no notice service: one dialog at a time for concurrent launches" "[ \$(grep -c '^ZENITY --info' $T/zen) = 1 ] && grep -q 'unpacking client files' $T/zen"
rm -f "$T/nonotice"
# normal start: lock kept until window process runs, then a launch goes through (interface switch possible again)
touch "$T/release"; sleep 0.5; : > "$T/notes"; click
OUT=$(cat "$T/notes")
check "FS12 normal start before window process: launch shows starting text, no start" "grep -q 'Steam ARM is starting. Steam opens by itself when ready.' $T/notes && [ \$(grep -c CLIENT_START $T/events) = 1 ]"
touch "$T/web"; sleep 4.5; : > "$T/quit"
click; OUT=$(cat "$T/events")
check "FS13 window process up: lock released, next launch starts (switch path reachable)" "[ \$(grep -c CLIENT_START $T/events) = 2 ]"
wait "$MAIN" 2>/dev/null
rm -f "$T/web" "$T/quit" "$T/release"; sleep 1.5
DISPLAY=:9 WAYLAND_DISPLAY= sh "$M" 2>/dev/null </dev/null & M2=$!; sleep 0.5; kill -TERM "$M2"; wait "$M2" 2>/dev/null; sleep 1.5; touch "$T/release" "$T/quit"
click; OUT=$(cat "$T/events")
check "FS14 launcher ended during first start: lock freed, next launch starts" "[ \$(grep -c CLIENT_START $T/events) = 4 ]"

# tray: Open items greyed while lock held (read from /proc/locks, lock never taken)
TP=$T/tray.py
awk "/^cat > \/usr\/local\/bin\/steam-arm-tray <<'TRAYPY'\$/{f=1;next} /^TRAYPY\$/{f=0} f" "$INST" > "$T/tray-full.py"
python3 - "$T/tray-full.py" "$TP" "$T/run2" <<'EOF'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"^def start_locked\(armhome\):\n(?:(?:    .*)?\n)+", src, re.M)
out = "import os\n" + (m.group(0).replace('"/run/user/%d" % os.getuid()', repr(sys.argv[3])) if m else "")
open(sys.argv[2], "w").write(out)
EOF
mkdir -p "$T/run2"; OUT=$(python3 - "$TP" "$T/run2" <<'EOF'
import fcntl, os, sys
ns = {}
exec(open(sys.argv[1]).read(), ns)
p = os.path.join(sys.argv[2], "steam-arm-start.lock")
r = [ns["start_locked"]("/nonexistent")]
f = open(p, "a"); fcntl.flock(f, fcntl.LOCK_EX); r.append(ns["start_locked"]("/nonexistent"))
fcntl.flock(f, fcntl.LOCK_UN); r.append(ns["start_locked"]("/nonexistent"))
g = open(p, "a"); fcntl.flock(g, fcntl.LOCK_EX | fcntl.LOCK_NB); r.append("free-after")
print(" ".join(map(str, r)))
EOF
)
check "FS15 tray reads launcher lock: free / held / released, test leaves it takeable" "[ \"\$OUT\" = 'False True False free-after' ]"
check "FS16 tray Open, Big Picture and desktop items insensitive while start lock held; title says starting" \
  "grep -q 'self.open_item.set_sensitive(not running and not starting)' $T/tray-full.py && [ \$(grep -c 'not game and not starting)' $T/tray-full.py) = 2 ] && grep -q '\"Steam (starting)\" if starting' $T/tray-full.py"

# icon waiter: draws once icon file keeps its size, then KIconLoader signal for groups 0-5 (KDE reloads icons live)
IW=$T/iw.sh; blk '^UICON=' '^fi$' | sed 's/STEP=5/STEP=1/' > "$IW"
cat > "$T/bin/steam-arm-icon" <<'EOF'
#!/bin/sh
echo "ICON $(stat -c %s "$1/public/steam_tray.ico")" >> "$T/icon.log"
EOF
cat > "$T/bin/gdbus" <<'EOF'
#!/bin/sh
echo "GDBUS $*" >> "$T/icon.log"
EOF
printf '#!/bin/sh\necho KBUILD >> "$T/icon.log"\n' > "$T/bin/kbuildsycoca6"
chmod 755 "$T/bin/steam-arm-icon" "$T/bin/gdbus" "$T/bin/kbuildsycoca6"
mkdir -p "$T/IS/public" "$T/RH"
iw(){ ( REALHOME=$T/RH S=$T/IS XDG_RUNTIME_DIR=$T/run; . "$IW" ) ; }
printf 'x' > "$T/IS/public/steam_tray.ico"
iw
for i in 1 2 3 4; do sleep 0.6; printf 'xx' >> "$T/IS/public/steam_tray.ico"; done
OUT=$(cat "$T/icon.log" 2>/dev/null)
check "FS17 icon file still growing: not drawn yet" "! grep -q '^ICON' $T/icon.log 2>/dev/null"
n=0; until grep -q '^ICON' "$T/icon.log" 2>/dev/null || [ $n -ge 60 ]; do sleep 0.1; n=$((n + 1)); done; sleep 0.5
OUT=$(cat "$T/icon.log" 2>/dev/null)
check "FS18 drawn from complete file once size holds" "grep -qx 'ICON 9' $T/icon.log"
check "FS19 KDE told after drawing: kbuildsycoca, then KIconLoader iconChanged for groups 0-5" \
  "[ \"\$(grep -c '^GDBUS emit --session --object-path /KIconLoader --signal org.kde.KIconLoader.iconChanged [0-5]\$' $T/icon.log)\" = 6 ] && [ \"\$(head -n 2 $T/icon.log | tail -1)\" = KBUILD ]"
# --open: steam:// link forwarded to running client only (tray Steam pages); front part of launcher, fake settings file
OF=$T/open-front.sh
{ awk '/^REALHOME=/{f=1} f{print} f && /^  --open\) open_link "\$\{2:-\}"; exit \$\?;;$/{exit}' "$L"; echo esac; echo 'echo "NOT REACHED"'; } \
  | sed -e "s#/etc/steam-arm/steam-arm.conf#$T/op.conf#g" -e 's#^export XDG_RUNTIME_DIR="/run/user/\$(id -u)"$#export XDG_RUNTIME_DIR="$T/oprun"#' > "$OF"
mkdir -p "$T/oprun"
mkdir -p "$T/opb"
printf '#!/bin/sh\n[ -f "$T/running" ]\n' > "$T/opb/pgrep"
printf '#!/bin/sh\necho "FEX $*" >> "$T/op.log"\n' > "$T/opb/FEX"; chmod 755 "$T/opb/"*
# op FOLDER(arm64|x86) URL [locked]
op(){ rm -f "$T/op.log"; h=$T/op-$1; rm -rf "$h"; S=$h/.local/share/Steam
  case $1 in
    arm64) mkdir -p "$S/steamrtarm64"; printf '#!/bin/sh\necho "NATIVE $(pwd) $*" >> "$T/op.log"\n' > "$S/steamrtarm64/steam"; chmod 755 "$S/steamrtarm64/steam";;
    x86) mkdir -p "$S/ubuntu12_32" "$h/.config/steam-arm"; : > "$S/steam.sh"; printf '#!/bin/sh\n' > "$S/ubuntu12_32/steam"; chmod 755 "$S/ubuntu12_32/steam"; echo x86 > "$h/.config/steam-arm/client-type";;
  esac
  printf 'GAMEUSER=%s\nCLIENT=arm64\n' "$(id -un)" > "$T/op.conf"
  ( export T; [ "${3:-}" = locked ] && { exec 6>>"$T/oprun/steam-arm-start.lock"; flock 6; }
    env -u DISPLAY -u WAYLAND_DISPLAY STEAM_ARM_HOME="$h" PATH="$T/opb:$PATH" sh "$OF" --open "$2"; echo "rc=$?" ) 2>&1; }
: > "$T/running"
OUT=$(op arm64 steam://open/friends)
check "FS20 --open, native client running: link passed to client in its folder, nothing else" "grep -qx \"NATIVE $T/op-arm64/.local/share/Steam/steamrtarm64 steam://open/friends\" $T/op.log && [ \$(wc -l < $T/op.log) = 1 ] && grep -qx rc=0 <<<\"\$OUT\" && ! grep -q 'NOT REACHED' <<<\"\$OUT\""
OUT=$(op x86 steam://open/games)
check "FS21 --open, x86 client folder: link through FEX (client's steam.sh)" "grep -q '^FEX /usr/bin/bash .*/steam.sh steam://open/games\$' $T/op.log && grep -qx rc=0 <<<\"\$OUT\""
rm -f "$T/running"; OUT=$(op arm64 steam://store)
check "FS22 --open, client not running: status 1, message, client not started" "[ ! -f $T/op.log ] && grep -qx rc=1 <<<\"\$OUT\" && grep -q 'Steam is not running' <<<\"\$OUT\""
: > "$T/running"; OUT=$(op arm64 steam://store locked)
check "FS23 --open while start lock held (first start): status 1, nothing forwarded" "[ ! -f $T/op.log ] && grep -qx rc=1 <<<\"\$OUT\" && grep -q 'Steam ARM is starting' <<<\"\$OUT\""
OUT=$(op arm64 https://example.org)
check "FS24 --open refuses link other than steam://" "[ ! -f $T/op.log ] && grep -qx rc=2 <<<\"\$OUT\""
check "FS25b test runtime folder used (no lock in real runtime folder)" "grep -q 'export XDG_RUNTIME_DIR=\"\$T/oprun\"' $OF"
check "FS25 --help names --open" "grep -q 'steam-arm --open URL    pass steam:// link to running client (never starts one)' $L"

# tray Steam pages: order, links, greyed unless client runs and no start in progress
G2=$T/gi/gi; mkdir -p "$G2/repository"; echo 'def require_version(*a): pass' > "$G2/__init__.py"
cat > "$G2/repository/__init__.py" <<'EOF'
class _Item:
    def __init__(self, label=""): self.label = label; self.sensitive = True; self.cb = None
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
    def __getattr__(self, n): return lambda *a: None
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
class Gio: pass
EOF
cat > "$T/pages.py" <<'EOF'
import importlib.util, os, sys, tempfile
sys.path.insert(0, sys.argv[2])
spec = importlib.util.spec_from_file_location("tray", sys.argv[1]); tray = importlib.util.module_from_spec(spec); spec.loader.exec_module(tray)
calls = []
tray.spawn = lambda argv: calls.append(argv) or True
os.environ["STEAM_ARM_HOME"] = tempfile.mkdtemp()
st = {"run": False, "lock": False}
tray.steam_running = lambda: st["run"]
tray.game_running = lambda: False
tray.start_locked = lambda armhome: st["lock"]
t = tray.SteamTray()
labels = [i.label for i in t.menu.items]
pages = ["Store", "Library", "Friends", "Downloads", "Screenshots", "Steam Settings"]
i = labels.index("Store") if "Store" in labels else -1
print("order", i > 0 and labels[i:i + 6] == pages and labels[i - 1] == "" and labels[i + 6] == "" and labels[i - 2] == "Open in desktop mode")
item = {x.label: x for x in t.menu.items}
want = ["steam://store", "steam://open/games", "steam://open/friends", "steam://open/downloads", "steam://open/screenshots", "steam://open/settings"]
for p in pages:
    if p in item:
        item[p].activate()
print("links", calls == [["/usr/local/bin/steam-arm", "--open", u] for u in want])
t.update_state(); print("notrun", all(p in item and not item[p].sensitive for p in pages))
st["run"] = True; t.update_state(); print("run", all(p in item and item[p].sensitive for p in pages))
st["lock"] = True; t.update_state()
print("lock", all(p in item and not item[p].sensitive for p in pages), item["Open in desktop mode"].sensitive is False, item["Open Steam"].sensitive is False)
st["lock"] = False; t.stopping = 1e18; t.update_state(); print("stopping", all(p in item and not item[p].sensitive for p in pages))
print("own settings", "Steam ARM Settings" in labels)
EOF
OUT=$(python3 "$T/pages.py" "$T/tray-full.py" "$T/gi" 2>&1)
check "FS26 tray Steam pages in Valve's order under own separators, after Open items" "grep -qx 'order True' <<<\"\$OUT\""
check "FS27 each page item runs steam-arm --open with its steam:// link" "grep -qx 'links True' <<<\"\$OUT\""
check "FS28 page items greyed while client not running, offered while it runs" "grep -qx 'notrun True' <<<\"\$OUT\" && grep -qx 'run True' <<<\"\$OUT\""
check "FS29 page and Open items greyed during first start (start lock), page items while stopping" "grep -qx 'lock True True True' <<<\"\$OUT\" && grep -qx 'stopping True' <<<\"\$OUT\""
check "FS30 Steam ARM settings item named apart from Steam's settings" "grep -qx 'own settings True' <<<\"\$OUT\""
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
