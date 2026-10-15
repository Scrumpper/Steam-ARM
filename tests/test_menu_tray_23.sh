#!/bin/bash
# 2.3 menu-tray group: KDE window rule file record (kwinrules-made: setup created kwinrulesrc, removal deletes it once
# empty), remove_all order, tray high-contrast icon in the runtime folder. Functions extracted from
# ~/.cache/sarm<NN>-work (SARM_INST picks another installer); kwriteconfig5 / kreadconfig5 are stand-ins editing a
# kwinrulesrc under a temp HOME, so the host's own file is never touched. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-mt23.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }

check "installer bash -n" "bash -n '$INST'"
# ---------- KDE rule file record ----------
K=$T/kde; mkdir -p "$K/bin" "$K/home"
cat > "$K/kcfg.py" <<'EOF'
import os, sys
mode, a = sys.argv[1], sys.argv[2:]
o = {}
i = 0
while i < len(a):
    if a[i] == "--delete":
        o["delete"] = True; i += 1
    elif a[i].startswith("--"):
        o[a[i][2:]] = a[i + 1]; i += 2
    else:
        o["value"] = a[i]; i += 1
p = os.path.join(os.environ["HOME"], ".config", o["file"])
groups, order = {}, []
if os.path.exists(p):
    g = None
    for l in open(p).read().splitlines():
        if l.startswith("["):
            g = l[1:-1]; groups.setdefault(g, {}); order.append(g)
        elif "=" in l and g is not None:
            k, v = l.split("=", 1); groups[g][k] = v
if mode == "r":
    print(groups.get(o["group"], {}).get(o["key"], ""))
    sys.exit(0)
g = groups.setdefault(o["group"], {})
if o["group"] not in order:
    order.append(o["group"])
if o.get("delete"):
    g.pop(o["key"], None)
else:
    g[o["key"]] = o.get("value", "")
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, "w") as f:
    for n in order:
        if groups[n]:
            f.write("[%s]\n" % n + "".join("%s=%s\n" % kv for kv in groups[n].items()) + "\n")
EOF
printf '#!/bin/sh\nexec python3 %s w "$@"\n' "$K/kcfg.py" > "$K/bin/kwriteconfig5"
printf '#!/bin/sh\nexec python3 %s r "$@"\n' "$K/kcfg.py" > "$K/bin/kreadconfig5"
chmod 755 "$K/bin/kwriteconfig5" "$K/bin/kreadconfig5"
KD=$T/kde.sh
{ echo "KWIN_MADE=$K/etc/kwinrules-made"; echo "OWNED=$K/etc/owned.sha"
  fn kcfg_ver "$INST"; fn kwin_rule_remove "$INST"; fn acct_records_drop "$INST"
  echo 'getent(){ case $2 in ga|gb) echo "$2:x:1001:1001::/home/$2:/bin/sh";; *) return 2;; esac; }'
  echo 'login_sh(){ sh -c "$1"; }; kwin_reload(){ :; }; say(){ echo "$*"; }'
  echo 'kwrite(){'; awk '/^  RID=steam-arm-frame$/{f=1} f{print} f && /^  fi$/{exit}' "$INST"; echo '}'; } > "$KD"
F=$K/home/.config/kwinrulesrc; M=$K/etc/kwinrules-made
# PATH: stand-ins and plain tools only; the host's own kwriteconfig must never run (it writes the real kwinrulesrc)
mkdir -p "$K/sys"; for x in sh awk tr grep paste cat rm mkdir python3 head cut mktemp chmod cmp mv; do ln -s "$(command -v "$x")" "$K/sys/$x"; done
kd(){ OUT=$( (unset XDG_CONFIG_HOME; export HOME=$K/home PATH="$K/bin:$K/sys"; . "$KD"; eval "$1") 2>&1); }
check "K0 record path constant is /etc/steam-arm/kwinrules-made (inside folder removal deletes)" "grep -qx 'KWIN_MADE=/etc/steam-arm/kwinrules-made' '$INST'"
rm -rf "$K/home/.config" "$K/etc"; kd kwrite
check "K1 no kwinrulesrc before rule write: record made, rule written" "[ -f '$M' ] && grep -qx 'rules=steam-arm-frame' '$F' && grep -qx '\\[steam-arm-frame\\]' '$F'"
kd kwrite
check "K1 second setup run: record kept, rule listed once" "[ -f '$M' ] && grep -qx 'rules=steam-arm-frame' '$F'"
kd kwin_rule_remove
check "K2 removal with record, file emptied: file and record deleted" "[ ! -e '$F' ] && [ ! -e '$M' ]"
rm -rf "$K/home/.config" "$K/etc"; mkdir -p "$K/home/.config"; printf '[General]\ncount=1\nrules=mine\n\n[mine]\nwmclass=x\n\n' > "$F"
kd kwrite
check "K3 kwinrulesrc present before: no record, own rule kept" "[ ! -e '$M' ] && grep -qx 'rules=mine,steam-arm-frame' '$F'"
kd kwin_rule_remove
check "K3 removal without record: file kept with own rule" "[ -f '$F' ] && grep -qx 'rules=mine' '$F' && ! grep -q steam-arm-frame '$F'"
printf '[General]\ncount=0\nrules=\n\n' > "$F"; kd kwin_rule_remove
check "K4 removal without record, file empty: file kept (not made by setup)" "[ -f '$F' ]"
rm -rf "$K/home/.config" "$K/etc"; kd kwrite
kd "kwriteconfig5 --file kwinrulesrc --group General --key rules steam-arm-frame,other; kwriteconfig5 --file kwinrulesrc --group other --key wmclass y"
kd kwin_rule_remove
check "K5 record, but user added a rule since: file kept with that rule, record gone" "[ -f '$F' ] && grep -qx 'rules=other' '$F' && [ ! -e '$M' ]"
rm -rf "$K/home/.config" "$K/etc"; kd kwrite
LEG=$(grep -o -m1 'kwin_rule_remove [a-z0-9]*-steam-arm-frame' "$INST" | cut -d" " -f2)
kd "kwin_rule_remove ${LEG:-other-steam-arm-frame}"
check "K6 legacy rule group removal: record and file untouched" "[ -f '$M' ] && grep -qx 'rules=steam-arm-frame' '$F'"
rm -rf "$K/home/.config" "$K/etc"; kd "PATH=$K/sys; kwin_rule_remove"
check "K7 no KDE tools: nothing written, nothing deleted" "[ ! -e '$F' ] && [ -z \"\$OUT\" ]"
# box re-check B16: record names account; setup for another account drops records of previous one
rm -rf "$K/home/.config" "$K/etc"; kd "GAMEUSER=ga; kwrite"
check "K9 record names account it was made for" "[ \"\$(cat '$M' 2>/dev/null)\" = ga ]"
kd "GAMEUSER=gb; kwin_rule_remove"
check "K10 removal for other account: record of ga kept, file kept" "[ \"\$(cat '$M' 2>/dev/null)\" = ga ] && [ -f '$F' ]"
OW=$K/etc/owned.sha
own3(){ printf '%064d  /opt/rfs/graphics_provider.json\n%064d  /home/ga/.fex-emu/Config.json\n%064d  /home/gb/.fex-emu/Config.json\n' 1 2 3 > "$OW"; }
rm -rf "$K/home/.config" "$K/etc"; kd "GAMEUSER=ga; kwrite"; own3
kd "GAMEUSER=gb; acct_records_drop ga"
check "K11 setup for gb after ga: ga rule and file setup made gone, record gone, ga FEX settings line dropped, others kept, one line" \
  "[ ! -e '$F' ] && [ ! -e '$M' ] && [ \"\$(cut -c67- '$OW' | paste -sd,)\" = '/opt/rfs/graphics_provider.json,/home/gb/.fex-emu/Config.json' ] && [ \"\$OUT\" = '  setup records of previous account ga dropped (KDE rule file record, FEX settings file)' ]"
rm -rf "$K/home/.config" "$K/etc"; mkdir -p "$K/home/.config"; printf '[General]\ncount=1\nrules=mine\n\n[mine]\nwmclass=x\n\n' > "$F"
kd "GAMEUSER=ga; kwrite"; mkdir -p "$K/etc"; printf '%064d  /opt/rfs/graphics_provider.json\n%064d  /home/gb/.fex-emu/Config.json\n' 1 3 > "$OW"; cp "$OW" "$K/ow0"
kd "GAMEUSER=gb; acct_records_drop ga"
check "K12 previous account's file predates setup (no record): its rule left, records unchanged, no line" "[ ! -e '$M' ] && grep -qx 'rules=mine,steam-arm-frame' '$F' && cmp -s '$OW' '$K/ow0' && [ -z \"\$OUT\" ]"
rm -rf "$K/home/.config" "$K/etc"; kd "GAMEUSER=gx; kwrite"; own3; printf '%064d  /home/gx/.fex-emu/Config.json\n' 4 >> "$OW"
kd "GAMEUSER=ga; acct_records_drop gx"
check "K13 previous account deleted: record dropped, its file untouched, FEX settings lines of other homes dropped" "[ ! -e '$M' ] && [ -f '$F' ] && [ \"\$(cut -c67- '$OW' | paste -sd,)\" = '/opt/rfs/graphics_provider.json,/home/ga/.fex-emu/Config.json' ] && [ \"\$OUT\" = '  setup records of previous account gx dropped (KDE rule file record, FEX settings file)' ]"
own3; kd "GAMEUSER=gb; acct_records_drop ga"
check "K13b no rule record, FEX settings line dropped: line names that only" "[ \"\$OUT\" = '  setup records of previous account ga dropped (FEX settings file)' ]"
rm -rf "$K/home/.config" "$K/etc"; mkdir -p "$K/etc"; : > "$M"
kd "GAMEUSER=gb; acct_records_drop ga"
check "K14 record of earlier release (empty) belongs to previous account: dropped" "[ ! -e '$M' ]"
l_ro=$(grep -n '^\[ "\$RETIRE_OTHER" = 1 \] && retire_other$' "$INST" | cut -d: -f1)
l_pu=$(grep -n '^\[ -n "\$PREV_USER" \] && \[ "\$PREV_USER" != "\$GAMEUSER" \] && acct_records_drop "\$PREV_USER"$' "$INST" | cut -d: -f1)
l_cs=$(grep -n '^conf_set GAMEUSER "\$GAMEUSER"$' "$INST" | cut -d: -f1); l_rm=$(grep -n '^if \[ "\$MODE" = remove \]; then remove_all; exit 0; fi$' "$INST" | cut -d: -f1)
check "K15 setup: previous account from settings file, records dropped after removal branch, before GAMEUSER saved" "grep -qx 'PREV_USER=\$(conf_get GAMEUSER)' '$INST' && [ -n '$l_pu' ] && [ ${l_rm:-0} -lt ${l_pu:-0} ] && [ ${l_ro:-0} -lt ${l_pu:-0} ] && [ ${l_pu:-0} -lt ${l_cs:-0} ]"
RA=$(fn remove_all "$INST")
l_kw=$(printf '%s\n' "$RA" | grep -n '^  \[ -n "\$uh" \] && kwin_rule_remove$' | cut -d: -f1)
l_rm=$(printf '%s\n' "$RA" | grep -n '^  rm -rf /usr/local/share/steam-arm /etc/steam-arm$' | cut -d: -f1)
OUT="kw=$l_kw rm=$l_rm"
check "K8 remove_all: rule removal (reads record) before /etc/steam-arm goes, once" "[ -n '$l_kw' ] && [ -n '$l_rm' ] && [ '$l_kw' -lt '$l_rm' ] && [ \$(printf '%s\n' \"\$RA\" | grep -c 'kwin_rule_remove\$') = 1 ]"

# ---------- running tray restarted by setup (box bug 19) ----------
TR=$T/tr.sh; awk '/^tray_restart\(\)/{f=1} f{print} f && /^}$/{exit}' "$INST" | sed "s#/proc/#$T/proc/#g" > "$TR"
check "TR0 tray_restart extracted, parses; setup calls it after tray install" "grep -q '^tray_restart()' $TR && bash -n $TR && grep -A1 -x 'if tray_restart; then' '$INST' | grep -q 'tray helper installed'"
TS=$(grep -A4 -x 'if tray_restart; then' "$INST")
check "TR6 summary: restarted tray -> restart line only; else next-login line (box re-test B12)" "grep -qx '  say \"     tray helper installed; running tray restarted (new version)\"' <<<\"\$TS\" && [ \"\$(sed -n 3p <<<\"\$TS\")\" = else ] && sed -n 4p <<<\"\$TS\" | grep -q 'at next login' && ! sed -n 1,2p <<<\"\$TS\" | grep -q 'next login'"
mkdir -p "$T/proc/4711" "$T/trb"
printf 'DISPLAY=:0\0HOME=/home/g\0SECRET=x\0DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus\0' > "$T/proc/4711/environ"
printf '#!/bin/sh\n[ -n "$TR_PID" ] && echo "$TR_PID"\n[ -n "$TR_PID" ]\n' > "$T/trb/pgrep"; chmod 755 "$T/trb/pgrep"
trr(){ ( export T TR_PID=$1; PATH=$T/trb:$PATH GAMEUSER=g; kill(){ echo "kill $*" >> "$T/tr.log"; [ "$1" = -TERM ]; }; sleep(){ :; }
         as_acct(){ shift; echo "start $*" >> "$T/tr.log"; }; . "$TR"; tray_restart; echo "rc=$?" > "$T/tr.rc"; wait ) >/dev/null 2>&1; }
rm -f "$T/tr.log"; trr 4711
OUT=$(cat "$T/tr.log" "$T/tr.rc")
check "TR1b running tray restarted: status 0" "grep -qx rc=0 $T/tr.rc"
check "TR1 running tray: SIGTERM, then started as game account with its session variables only" "grep -qx 'kill -TERM 4711' <<<\"\$OUT\" && grep -qx 'start env DISPLAY=:0 HOME=/home/g DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus setsid /usr/local/bin/steam-arm-tray' <<<\"\$OUT\""
rm -f "$T/tr.log"; trr ""
check "TR2 no tray running: nothing stopped or started, status 1" "[ ! -f $T/tr.log ] && grep -qx rc=1 $T/tr.rc"
rm -f "$T/tr.log"; mkdir -p "$T/proc/99"; : > "$T/proc/99/environ"; trr 99
check "TR3 tray without session variables: left running, status 1" "[ ! -f $T/tr.log ] && grep -qx rc=1 $T/tr.rc"
# box re-test B1: restarted tray must not hold setup lock fd 8 (or any other descriptor above 2)
LK=$(grep -m1 'exec 8>/run/steam-arm-setup.lock' "$INST" | sed "s#/run/steam-arm-setup.lock#$T/lock#; s/^ *//; s/ *\\\\\$//")
sed "s#/usr/local/bin/steam-arm-tray#$T/trb/tray#" "$TR" > "$T/tr4.sh"
printf '#!/bin/sh\necho $$ > "%s/tray.pid"; exec sleep 20\n' "$T" > "$T/trb/tray"; chmod 755 "$T/trb/tray"
rm -f "$T/tray.pid" "$T/tray.fds"
( export T TR_PID=4711; PATH=$T/trb:$PATH GAMEUSER=g; kill(){ [ "$1" = -TERM ]; }; sleep(){ :; }
  as_acct(){ shift; "$@"; }; . "$T/tr4.sh"; eval "$LK" || exit 3; exec 7>"$T/extra.log"; tray_restart >/dev/null ) 2>/dev/null
n=0; while [ "$(cat "/proc/$(cat "$T/tray.pid" 2>/dev/null)/comm" 2>/dev/null)" != sleep ] && [ $n -lt 50 ]; do command sleep 0.1; n=$((n + 1)); done
ls "/proc/$(cat "$T/tray.pid" 2>/dev/null)/fd" > "$T/tray.fds" 2>/dev/null
SECOND=$(bash -c "$LK && echo locked" 2>&1)
OUT="lockline=[$LK] second=[$SECOND] trayfds=[$(tr '\n' ' ' < "$T/tray.fds" 2>/dev/null)]"
check "TR4 setup run after tray_restart takes lock (tray holds no fd 8)" "[ -n \"\$LK\" ] && [ \"\$SECOND\" = locked ]"
check "TR5 restarted tray has only descriptors 0-2 of setup run" "[ -s $T/tray.fds ] && ! grep -qvxE '[0-2]' $T/tray.fds"
[ -s "$T/tray.pid" ] && kill "$(cat "$T/tray.pid")" 2>/dev/null
# box re-check B13: setup output read through pipe (menu tee) ends while restarted tray still runs
rm -f "$T/tray.pid"; t0=$(date +%s)
( export T TR_PID=4711; PATH=$T/trb:$PATH GAMEUSER=g; kill(){ [ "$1" = -TERM ]; }; sleep(){ :; }
  as_acct(){ shift; "$@"; }; . "$T/tr4.sh"; tray_restart; echo done ) 2>&1 | cat > "$T/pipe.out"
EOF_S=$(( $(date +%s) - t0 ))
n=0; while [ ! -s "$T/tray.pid" ] && [ $n -lt 50 ]; do command sleep 0.1; n=$((n + 1)); done
TRAY_UP=no; kill -0 "$(cat "$T/tray.pid" 2>/dev/null)" 2>/dev/null && TRAY_UP=yes
OUT="reader EOF after ${EOF_S} s, tray running=$TRAY_UP, out=[$(cat "$T/pipe.out")]"
check "TR7 reader of setup output gets EOF after tray_restart, tray keeps running (box re-check B13)" "[ \"\$EOF_S\" -le 5 ] && [ \$TRAY_UP = yes ] && grep -qx done $T/pipe.out"
[ -s "$T/tray.pid" ] && kill "$(cat "$T/tray.pid")" 2>/dev/null

# ---------- tray high-contrast icon ----------
TRAY=$T/tray.py
awk '/^cat > \/usr\/local\/bin\/steam-arm-tray <<.TRAYPY.$/{f=1;next} /^TRAYPY$/{f=0} f' "$INST" > "$TRAY"
check "tray compiles" "python3 -m py_compile '$TRAY'"
if python3 -c 'import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf' 2>/dev/null; then
cat > "$T/hc.py" <<'EOF'
import os, sys, types, tempfile
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib
src = sys.argv[1]
# stand-ins for the indicator modules; GdkPixbuf and GLib stay real
rep = types.ModuleType("gi.repository")
rep.GdkPixbuf, rep.GLib = GdkPixbuf, GLib
class _Ind:
    def __init__(self): self.icon = self.theme = None
    def set_icon_theme_path(self, p): self.theme = p
    def set_icon_full(self, n, d): self.icon = n
    def __getattr__(self, n): return lambda *a: None
class _W:
    def __init__(self, *a, **k): pass
    def __getattr__(self, n): return lambda *a, **k: None
rep.Gtk = types.SimpleNamespace(Menu=_W, MenuItem=_W, SeparatorMenuItem=_W, main_quit=lambda: None)
rep.AyatanaAppIndicator3 = types.SimpleNamespace(IndicatorCategory=types.SimpleNamespace(APPLICATION_STATUS=0),
    IndicatorStatus=types.SimpleNamespace(ACTIVE=1), Indicator=types.SimpleNamespace(new=lambda *a: _Ind()))
rep.Gio = types.SimpleNamespace()
gi.require_version = lambda *a: None
sys.modules["gi.repository"] = rep
import importlib.util
spec = importlib.util.spec_from_file_location("tray", src); tray = importlib.util.module_from_spec(spec); spec.loader.exec_module(tray)
def ok(n, c): print(("PASS " if c else "FAIL ") + n)
# white 12x12 icon: 4x4 white square centred, rest transparent
pb = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 12, 12); pb.fill(0x00000000)
sq = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 4, 4); sq.fill(0xffffffff); sq.copy_area(0, 0, 4, 4, pb, 4, 4)
d = tempfile.mkdtemp(); mono = os.path.join(d, "steam_tray_mono.png"); pb.savev(mono, "png", [], [])
rt = tempfile.mkdtemp()
p = tray.contrast_icon(mono, rt)
ok("H1 contrast icon written under runtime folder steam-arm-tray/", p == os.path.join(rt, "steam-arm-tray", "steam_tray_hc.png") and os.path.isfile(p))
ok("H1 folder private (0700)", p and (os.stat(os.path.dirname(p)).st_mode & 0o777) == 0o700)
out = GdkPixbuf.Pixbuf.new_from_file(p); px = out.get_pixels(); rs = out.get_rowstride()
at = lambda x, y: tuple(px[y * rs + x * 4:y * rs + x * 4 + 4])
ok("H2 glyph kept white, one-pixel dark outline, rest transparent",
   at(5, 5) == (255, 255, 255, 255) and at(3, 5) == (32, 32, 32, 255) and at(3, 3) == (32, 32, 32, 255) and at(1, 1)[3] == 0 and at(2, 5)[3] == 0)
ok("H3 no runtime folder: None, nothing written", tray.contrast_icon(mono, None) is None and tray.contrast_icon(mono, os.path.join(d, "missing")) is None
   and not os.path.exists(os.path.join(d, "missing")))
bad = os.path.join(d, "bad.png"); open(bad, "w").close()
ok("H4 unreadable icon: None (mono kept)", tray.contrast_icon(bad, tempfile.mkdtemp()) is None)
home = tempfile.mkdtemp(); os.environ["STEAM_ARM_HOME"] = home
pub = os.path.join(home, ".local/share/Steam/public"); os.makedirs(pub)
import shutil; shutil.copy(mono, os.path.join(pub, "steam_tray_mono.png"))
tray.steam_running = lambda: False
os.environ["XDG_RUNTIME_DIR"] = rt
t = tray.SteamTray()
ok("H5 tray uses contrast icon from runtime folder", t.indicator.icon == "steam_tray_hc" and t.indicator.theme == os.path.join(rt, "steam-arm-tray"))
del os.environ["XDG_RUNTIME_DIR"]
t = tray.SteamTray()
ok("H6 no XDG_RUNTIME_DIR: mono icon from client folder", t.indicator.icon == "steam_tray_mono" and t.indicator.theme == pub)
EOF
OUT=$(python3 "$T/hc.py" "$TRAY" 2>&1)
echo "$OUT" | grep -E '^(PASS|FAIL) '
pass=$((pass + $(grep -c '^PASS' <<<"$OUT"))); fail=$((fail + $(grep -c '^FAIL' <<<"$OUT")))
grep -q '^PASS H6' <<<"$OUT" || { echo "FAIL tray test did not finish"; echo "$OUT" | tail -5; fail=$((fail + 1)); }
else
  echo "SKIP tray contrast icon: python3 GdkPixbuf not available here"
fi
check "H7 contrast icon only under XDG_RUNTIME_DIR (no ~/.cache path)" "grep -q 'hc = contrast_icon(src, os.environ.get(\"XDG_RUNTIME_DIR\"))' '$TRAY' && ! grep -q 'steam_tray_hc' <<<\"\$(grep -n cache '$TRAY')\""

# ---------- tray names client type (CLIENT in settings file); stand-in indicator modules ----------
G=$T/gx/gi; mkdir -p "$G/repository"
printf 'def require_version(*a):\n    pass\n' > "$G/__init__.py"
cat > "$G/repository/__init__.py" <<'EOF'
class _Item:
    def __init__(self, label=""): self.label = label; self.sensitive = True
    def connect(self, *a): pass
    def set_label(self, v): self.label = v
    def set_sensitive(self, v): self.sensitive = v
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
    def __init__(self): self.title = None
    def set_title(self, t): self.title = t
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
cat > "$T/tx.py" <<'EOF'
import os, sys, tempfile, importlib.util
sys.path.insert(0, sys.argv[2])
spec = importlib.util.spec_from_file_location("tray", sys.argv[1]); tray = importlib.util.module_from_spec(spec); spec.loader.exec_module(tray)
conf = os.path.join(tempfile.mkdtemp(), "steam-arm.conf"); tray.CONF_PATH = conf
os.environ["STEAM_ARM_HOME"] = tempfile.mkdtemp()
def ok(n, c, d=""): print(("PASS " if c else "FAIL ") + n + ("" if c else "  " + repr(d)))
def make(text, running):
    open(conf, "w").write(text)
    tray.steam_running = lambda: running
    tray.game_running = lambda: False
    return tray.SteamTray()
t = make("GAMEUSER=u\nCLIENT=x86\nCLIENT_SET=auto\n", False)
first = t.menu.items[0]
ok("TX1 x86 client: first menu entry 'Client: x86 through emulation', not clickable", first.label == "Client: x86 through emulation" and first.sensitive is False, first.label)
ok("TX2 x86 client: title 'Steam (x86 client)'", t.indicator.title == "Steam (x86 client)", t.indicator.title)
t = make("CLIENT=x86\n", True)
ok("TX3 x86 client running: title 'Steam (x86 client, running)'", t.indicator.title == "Steam (x86 client, running)", t.indicator.title)
t = make("GAMEUSER=u\n", True)
ok("TX4 settings file without CLIENT (2.2): 'Client: native ARM64', title 'Steam (running)'",
   t.menu.items[0].label == "Client: native ARM64" and t.indicator.title == "Steam (running)", (t.menu.items[0].label, t.indicator.title))
t = make("CLIENT=arm64\n", False)
ok("TX5 native client stopped: title 'Steam'", t.indicator.title == "Steam", t.indicator.title)
t = make("CLIENT=x86\n", False)
open(conf, "w").write("CLIENT=arm64\n")
t.update_state()
ok("TX6 client type switched while tray runs: entry and title follow on next poll",
   t.menu.items[0].label == "Client: native ARM64" and t.indicator.title == "Steam", (t.menu.items[0].label, t.indicator.title))
EOF
OUT=$(python3 "$T/tx.py" "$TRAY" "$T/gx" 2>&1)
echo "$OUT" | grep -E '^(PASS|FAIL) '
pass=$((pass + $(grep -c '^PASS' <<<"$OUT"))); fail=$((fail + $(grep -c '^FAIL' <<<"$OUT")))
grep -q '^PASS TX5\|^FAIL TX5' <<<"$OUT" || { echo "FAIL tray client test did not finish"; echo "$OUT" | tail -5; fail=$((fail + 1)); }

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
