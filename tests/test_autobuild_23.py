#!/usr/bin/env python3
"""Steam ARM 2.3 automatic Windows build: steam-arm-autobuild.py (apply, list, drop, rule gates, marker) and the
launch handler check (skip with notice, launch option, forced build, undone choice, other engines, missing file).
Helper, compatmap and handler extracted from installer under test (SARM_INST picks another installer); conf path,
helper path and compatmap path rewritten to temp copies in the extracts only. Internal; not for release zips."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
PROJ = os.path.dirname(HERE)
INST = _INST
SRC = open(INST).read()
TMP = tempfile.mkdtemp(prefix="sarm232-ab-")
CONF = os.path.join(TMP, "steam-arm.conf")
FAILS = []


def check(name, cond, detail=""):
    # installer without helper: helper cases fail as such; handler cases run its handler with the 2.3.2 release helper
    if HELPER_MISSING and name[:1] in "AL":
        cond, detail = False, "helper absent from %s" % INST
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[-1500:])


def heredoc(start, end, src=None):
    src = SRC if src is None else src
    i = src.find(start)
    if i < 0:
        return None
    i += len(start)
    return src[i:src.index("\n" + end + "\n", i) + 1]


AB_START = "cat > /usr/local/lib/steam-arm-autobuild.py <<'ABPY'\n"
AB_SRC = heredoc(AB_START, "ABPY")
HELPER_MISSING = AB_SRC is None
check("A0 helper heredoc steam-arm-autobuild.py present in installer", not HELPER_MISSING)
if HELPER_MISSING:
    AB_SRC = heredoc(AB_START, "ABPY", open(old("2.3.2") or INST).read())

CM_SRC = heredoc("cat > /usr/local/lib/steam-arm-compatmap.py <<'PYEOF'\n", "PYEOF")
# compatmap copy: client-running check off (test host may run its own Steam)
CM = os.path.join(TMP, "compatmap.py")
assert CM_SRC.count("if steam_up():") == 1
open(CM, "w").write(CM_SRC.replace("if steam_up():", "if False:"))
CMFAIL = os.path.join(TMP, "compatmap-fail.py")
open(CMFAIL, "w").write("import sys\nsys.exit('steam-arm-compatmap: Steam ARM is running. Close it first')\n")
CMLOG = os.path.join(TMP, "cm.log")
CMSPY = os.path.join(TMP, "compatmap-spy.py")
open(CMSPY, "w").write("import sys\nopen(%r, 'a').write(' '.join(sys.argv[1:]) + '\\n')\nexec(open(%r).read())\n" % (CMLOG, CM))


def helper(cm=CM, name="autobuild.py", skip=None):
    s = AB_SRC
    assert s.count('CONF = "/etc/steam-arm/steam-arm.conf"') == 1 and s.count('COMPATMAP = "/usr/local/lib/steam-arm-compatmap.py"') == 1
    s = s.replace('CONF = "/etc/steam-arm/steam-arm.conf"', "CONF = %r" % CONF)
    s = s.replace('COMPATMAP = "/usr/local/lib/steam-arm-compatmap.py"', "COMPATMAP = %r" % cm)
    if skip is not None:
        assert s.count('"skip_launch": True') == 1
        s = s.replace('"skip_launch": True', '"skip_launch": %r' % skip)
    p = os.path.join(TMP, name)
    open(p, "w").write(s)
    return p


AB = helper()
AB_CMFAIL = helper(CMFAIL, "autobuild-cmfail.py")
AB_SPY = helper(CMSPY, "autobuild-spy.py")


def put(path, data=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data if isinstance(data, bytes) else data.encode())


def elf(path, bits=32, machine=3):
    h = b"\x7fELF" + bytes([1 if bits == 32 else 2, 1, 1]) + b"\0" * 9 + b"\x02\x00" + machine.to_bytes(2, "little")
    put(path, h + b"\0" * 44)


VDF = ('"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n'
       '\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n%s\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n')


def vdf_map(maps):
    return VDF % "".join('\t\t\t\t\t"%s"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n'
                         '\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n' % (a, t) for a, t in maps.items())


def library(kind="source32", maps=None, fex="FEX-2607-76-g1234\n", win=False, appid="220", extra_lib=False):
    """Client home with one title of kind in a library; returns (home, steam dir)."""
    home = tempfile.mkdtemp(dir=TMP, prefix="home-")
    steam = os.path.join(home, ".local/share/Steam")
    lib = steam
    if extra_lib:
        lib = os.path.join(TMP, tempfile.mkdtemp(dir=TMP, prefix="lib-"))
        put(os.path.join(steam, "steamapps/libraryfolders.vdf"),
            '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' % (steam, lib))
    if fex:
        put(os.path.join(steam, "steamapps/common/FEX-Emu/VERSIONS.txt"), fex)
    put(os.path.join(steam, "config/config.vdf"), vdf_map(maps or {}))
    d = os.path.join(lib, "steamapps/common/Title %s" % appid)
    acf = '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"Title"\n\t"installdir"\t\t"Title %s"\n' % (appid, appid)
    if win:
        acf += '\t"UserConfig"\n\t{\n\t\t"platform_override_source"\t\t"windows"\n\t}\n'
    put(os.path.join(lib, "steamapps/appmanifest_%s.acf" % appid), acf + "}\n")
    if kind in ("source32", "source64"):
        elf(os.path.join(d, "hl2_linux"), 32)
        put(os.path.join(d, "mod/gameinfo.txt"), "GameInfo {}\n")
        names = "hl2_linux64 hl2_linux" if kind == "source64" else "hl2_linux"
        if kind == "source64":
            elf(os.path.join(d, "hl2_linux64"), 64, 62)
        put(os.path.join(d, "hl2.sh"), '#!/bin/bash\nGAMEROOT=$(cd "${0%%/*}" && pwd)\nfor e in %s; do :; done\n'
            'exec "${GAMEROOT}/hl2_linux" "$@"\n' % names)
    elif kind == "goldsrc":
        elf(os.path.join(d, "hl_linux"), 32)
        put(os.path.join(d, "valve/liblist.gam"), "game \"x\"\n")
    elif kind == "nomod":
        elf(os.path.join(d, "hl2_linux"), 32)
    return home, steam


def conf(**kv):
    kv.setdefault("GPU_FAMILY", "mali-csf-v10")
    kv.setdefault("COMPONENTS_ON", "glx-lax,vk-spoof,gpu-in-emulation")
    open(CONF, "w").write("".join("%s=%s\n" % (k, v) for k, v in kv.items() if v is not None))


def run(*args, helper_p=AB):
    r = subprocess.run([sys.executable, helper_p] + list(args), capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout, r.stderr


def rec_file(home):
    return os.path.join(home, ".config/steam-arm/auto-build.conf")


def rd(p):
    try:
        return open(p).read()
    except OSError:
        return ""


def mapping_of(steam):
    s = rd(os.path.join(steam, "config/config.vdf"))
    i = s.find('"220"')
    return s[i:i + 200] if i >= 0 else ""


# ---------- apply ----------
conf()
home, steam = library()
rc, out, err = run("apply", steam)
check("A1 32-bit Source title, mali-csf-v10, FEX-2607: Windows build set", rc == 0 and
      "auto-build: app 220: Windows build (Proton ARM64) set; 32-bit Source engine Linux build stops at loading screen "
      "under emulation. Undo: steam-arm-config, Graphics > Route per game" in out, out + err)
check("A1 config.vdf: proton_11-arm64 (name Steam lists) for app 220, original kept as .bak-steam-arm",
      '"name"\t\t"proton_11-arm64"' in mapping_of(steam) and os.path.exists(os.path.join(steam, "config/config.vdf.bak-steam-arm")))
recs = rd(rec_file(home))
check("A1 record line: 220 source32 proton_11-arm64 <date>, file 644",
      any(l.split()[:3] == ["220", "source32", "proton_11-arm64"] and len(l.split()) == 4 for l in recs.splitlines())
      and oct(os.stat(rec_file(home)).st_mode & 0o777) == "0o644", recs)
before = rd(os.path.join(steam, "config/config.vdf"))
rc, out, err = run("apply", steam)
check("A10 second apply: no output, config.vdf byte-identical", out == "" and rd(os.path.join(steam, "config/config.vdf")) == before, out)

home, steam = library("source64")
rc, out, _ = run("apply", steam)
check("A2 start script names 64-bit binary: skip, no write", out == "" and "proton" not in mapping_of(steam) and not rd(rec_file(home)), out)
home, steam = library("goldsrc")
rc, out, _ = run("apply", steam)
check("A3 GoldSrc layout (hl_linux, liblist.gam): skip", out == "" and not rd(rec_file(home)), out)
home, steam = library("nomod")
rc, out, _ = run("apply", steam)
check("A3b hl2_linux without mod folder (gameinfo.txt): skip", out == "" and not rd(rec_file(home)), out)

home, steam = library(fex="FEX-2609.1\n")
rc, out, _ = run("apply", steam)
check("A4a FEX-2609.1 (Linux build hangs there too, box A0): Windows build set", "app 220: Windows build (Proton ARM64) set;" in out, out)
home, steam = library(fex="FEX-2610\n")
rc, out, _ = run("apply", steam)
check("A4 FEX-2610: suggestion only, reason FEX newer, no write",
      "auto-build: app 220: Windows build suggested (FEX tool 2610 newer than tested)" in out
      and "proton" not in mapping_of(steam) and not rd(rec_file(home)), out)
home, steam = library(fex=None)
rc, out, _ = run("apply", steam)
check("A4 VERSIONS.txt missing: suggestion (FEX tool version unknown)",
      "Windows build suggested (FEX tool version unknown)" in out and not rd(rec_file(home)), out)

for fam in ("mali-valhall-jm", "broadcom-v3d"):
    conf(GPU_FAMILY=fam)
    home, steam = library()
    rc, out, _ = run("apply", steam)
    check("A5 GPU family %s: suggestion (not tested), no write" % fam,
          "Windows build suggested (GPU family %s not tested)" % fam in out and not rd(rec_file(home)), out)
conf(GPU_FAMILY=None)
home, steam = library()
rc, out, _ = run("apply", steam)
check("A5 no GPU_FAMILY in settings file: suggestion only", "GPU family unknown not tested" in out and not rd(rec_file(home)), out)
conf(CLIENT="x86")
home, steam = library()
rc, out, _ = run("apply", steam)
check("A5 CLIENT=x86 in settings file (R2): suggestion only (x86 client)", "suggested (x86 client)" in out and not rd(rec_file(home)), out)
conf(CLIENT="arm64")
home, steam = library()
rc, out, _ = run("apply", steam)
check("A5 CLIENT=arm64: applies", "set;" in out, out)

conf()
home, steam = library(maps={"220": "steamlinuxruntime"})
rc, out, _ = run("apply", steam)
check("A6 mapping present (forced Linux build): skip, mapping unchanged",
      out == "" and "steamlinuxruntime" in mapping_of(steam) and not rd(rec_file(home)), out)
home, steam = library(maps={"220": "proton_experimental"})
rc, out, _ = run("apply", steam)
check("A6 mapping present (other Proton): skip", out == "" and "proton_experimental" in mapping_of(steam), out)
home, steam = library(win=True)
rc, out, _ = run("apply", steam)
check("A6 Windows build installed (platform_override_source): skip", out == "" and not rd(rec_file(home)), out)

home, steam = library()
put(rec_file(home), "220 source32 proton-stable-arm64 2026-10-01\n")
rc, out, _ = run("apply", steam)
check("A7 record present, mapping absent (undone in Steam): no re-apply", out == "" and "proton" not in mapping_of(steam), out)

conf(AUTO_BUILD="off")
home, steam = library()
rc, out, _ = run("apply", steam)
check("A8 AUTO_BUILD=off: no write, suggestion line", "suggested (AUTO_BUILD=off)" in out and "proton" not in mapping_of(steam), out)
rc, out, _ = run("list", steam)
check("A8 list with AUTO_BUILD=off: state off, title as suggestion",
      "auto-build\toff\n" in out and "app\t220\tsuggest\tsource32\tAUTO_BUILD=off\n" in out, out)
conf(AUTO_BUILD="on")
home, steam = library()
rc, out, _ = run("apply", steam)
check("A8 AUTO_BUILD=on: applies", "set;" in out, out)

conf()
home, steam = library()
rc, out, _ = run("apply", steam, helper_p=AB_CMFAIL)
check("A9 compatmap failure: no record, line names failure",
      "auto-build: app 220: Windows build not set: steam-arm-compatmap: Steam ARM is running" in out and not rd(rec_file(home)), out)

home, steam = library(extra_lib=True, appid="240")
rc, out, _ = run("apply", steam)
check("A11 title in second library (libraryfolders.vdf): applies", "auto-build: app 240: Windows build (Proton ARM64) set" in out, out)

home, steam = library()
open(CMLOG, "w").close()
rc, out, _ = run("apply", steam, helper_p=AB_SPY)
check("A12 one writer: compatmap called with config.vdf, appid, proton_11-arm64",
      rd(CMLOG).strip() == "%s 220 proton_11-arm64" % os.path.join(steam, "config/config.vdf"), rd(CMLOG))

# vk-spoof off: Windows build stops at DXVK device creation on Mali (box A9)
conf(COMPONENTS_ON="glx-lax,gpu-in-emulation")
home, steam = library()
rc, out, _ = run("apply", steam)
check("A13 vk-spoof not chosen: suggestion only (component vk-spoof off), no write (box bug 3)",
      "Windows build suggested (component vk-spoof off)" in out and "proton" not in mapping_of(steam) and not rd(rec_file(home)), out)
open(CONF, "w").write("GPU_FAMILY=mali-csf-v10\n")
home, steam = library()
rc, out, _ = run("apply", steam)
check("A13b settings file without COMPONENTS_ON (all chosen, launcher rule): applies", "set;" in out, out)
conf()

# shared content manifest (LastOwner 0, same folder as owned title): no title of its own (box bug 2)
home, steam = library(appid="280")
lib = steam
put(os.path.join(lib, "steamapps/appmanifest_220.acf"),
    '"AppState"\n{\n\t"appid"\t\t"220"\n\t"name"\t\t"Base"\n\t"installdir"\t\t"Title 280"\n\t"LastOwner"\t\t"0"\n}\n')
rc, out, _ = run("apply", steam)
check("A14 LastOwner 0 manifest skipped: one title set, not two",
      out.count("Windows build (Proton ARM64) set;") == 1 and "app 280:" in out and "app 220:" not in out
      and "220 " not in rd(rec_file(home)), out)

# rule set title, Steam then swapped in Windows files (Linux files gone): record decides (box bug 1)
home, steam = library()
run("apply", steam)
d = os.path.join(steam, "steamapps/common/Title 220")
os.remove(os.path.join(d, "hl2_linux"))
put(os.path.join(d, "hl2.exe"), b"MZ")
rc, out, _ = run("list", steam)
check("A15 Windows files in place of Linux build: still listed as auto (Windows (auto), counts)",
      "app\t220\tauto\tsource32\t" in out, out)
rc, out, _ = run("drop", steam, "220")
check("A15 drop after swap: record removed (Route per game > Automatic)", "record of app 220 removed" in out and "220 " not in rd(rec_file(home)), out)
home, steam = library()
run("apply", steam)
d = os.path.join(steam, "steamapps/common/Title 220")
os.remove(os.path.join(d, "hl2_linux"))
s0 = rd(os.path.join(steam, "config/config.vdf"))
open(os.path.join(steam, "config/config.vdf"), "w").write(vdf_map({"220": "proton_experimental"}))
rc, out, _ = run("list", steam)
check("A16 after swap, mapping changed by hand: kept, names hand choice", "app\t220\tkept\tsource32\tbuild chosen in Steam or settings menu (proton_experimental)" in out, out)

# ---------- list / drop ----------
conf()
home, steam = library()
run("apply", steam)
rc, out, _ = run("list", steam)
check("L1 list: state on, rule line, gate open, app auto, record",
      out.startswith("auto-build\ton\n") and "rule\tsource32\tproton_11-arm64\tmali-csf-v10\t2609\t32-bit Source engine\n" in out
      and "gate\tsource32\t-\n" in out and "app\t220\tauto\tsource32\t" in out and "\nrecord\t220\tsource32\tproton_11-arm64\t" in out, out)
rc, out, _ = run("drop", steam, "220")
check("L2 drop: record removed, message", "record of app 220 removed" in out and "220 " not in rd(rec_file(home)), out)
rc, out, _ = run("drop", steam, "220")
check("L2 drop again: no record", "no record for app 220" in out and rc == 0, out)
rc, out, err = run("drop", steam, "22x")
check("L3 drop with bad app id: usage, exit 1", rc == 1 and "usage" in err, err)
home, steam = library()
rc, out, _ = run("list", steam)
check("L4 list before apply: pending verdict", "app\t220\tpending\tsource32\t" in out, out)
home, steam = library(maps={"220": "steamlinuxruntime"})
rc, out, _ = run("list", steam)
check("L5 list with forced build: kept", "app\t220\tkept\tsource32\tbuild chosen in Steam or settings menu (steamlinuxruntime)" in out, out)

# ---------- handler ----------
HSTART = "cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n"
H_SRC = heredoc(HSTART, "HANDLERPY")
CONF_P = '"/etc/steam-arm/steam-arm.conf"'
AB_P = 'AUTOBUILD = "/usr/local/lib/steam-arm-autobuild.py"'


def handler_copy(ab_path, name):
    h = H_SRC.replace(CONF_P, repr(CONF))
    if AB_P in h:
        h = h.replace(AB_P, "AUTOBUILD = %r" % ab_path)
    p = os.path.join(TMP, name)
    open(p, "w").write(h)
    return p


HANDLER = handler_copy(AB, "handler.py")
HANDLER_NOAB = handler_copy(os.path.join(TMP, "absent.py"), "handler-noab.py")
HANDLER_NOSKIP = handler_copy(helper(name="autobuild-noskip.py", skip=False), "handler-noskip.py")
DRIVER = os.path.join(TMP, "driver.py")
open(DRIVER, "w").write(r'''
import json, os, runpy, sys
g_fex_path = os.environ.pop("T_FEXDIR")
sys.argv = json.loads(os.environ.pop("T_ARGV"))
try:
    runpy.run_path(os.environ.pop("T_HANDLER"))
except SystemExit as e:
    print("EXIT %r" % (e.code,))
    sys.exit(0)
print("RESULT " + json.dumps({"argv": sys.argv}))
''')
BIN = os.path.join(TMP, "bin")
NLOG = os.path.join(TMP, "notice.log")
put(os.path.join(BIN, "gdbus"), "#!/bin/sh\nprintf '%%s|' \"$@\" >> %s\necho >> %s\nenv | grep -c '^LD_PRELOAD=' >> %s\nexit 0\n" % (NLOG, NLOG, NLOG))
os.chmod(os.path.join(BIN, "gdbus"), 0o755)


def hrun(kind="source32", maps=None, fex="FEX-2607-76-g1234\n", env=None, h=HANDLER, argv_extra=("-game", "mod"), rec=False):
    home, steam = library(kind, maps=maps, fex=fex)
    if rec:
        put(rec_file(home), "220 source32 proton-stable-arm64 2026-10-01\n")
    d = os.path.join(steam, "steamapps/common/Title 220")
    script = "hl2.sh" if kind.startswith("source") else ("hl_linux" if kind == "goldsrc" else "game.bin")
    if kind == "unity32":
        elf(os.path.join(d, "game.bin"), 32)
        os.makedirs(os.path.join(d, "game_Data/Managed"), exist_ok=True)
    if os.path.exists(NLOG):
        os.unlink(NLOG)
    e = {"PATH": BIN + ":" + os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": "220",
         "STEAM_ARM_RENDERER_CHECK": "0", "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent",
         "LD_PRELOAD": "/x/gameoverlayrenderer.so", "T_FEXDIR": os.path.join(steam, "steamapps/common/FEX-Emu"),
         "T_ARGV": json.dumps(["fex-compat-tool", "waitforexitandrun", os.path.join(d, script)] + list(argv_extra)),
         "T_HANDLER": h}
    e.update(env or {})
    r = subprocess.run([sys.executable, DRIVER], env=e, cwd=d, capture_output=True, text=True, timeout=60)
    return r.stdout + r.stderr, rd(NLOG), home, steam


conf()
out, note, home, steam = hrun()
check("H11 32-bit Source start, gates pass: SystemExit(0) before container, log names skip",
      "EXIT 0" in out and "RESULT" not in out and "steam-arm: source32: 32-bit Source engine Linux build stops at loading "
      "screen under emulation; Windows build set at next start of Steam ARM; launch skipped (launch option "
      "STEAM_ARM_AUTO_BUILD=0 starts Linux build)" in out, out)
check("H11 desktop notice through gdbus: summary, body, urgency 1, 5 s, LD_PRELOAD not passed",
      "org.freedesktop.Notifications.Notify|Steam ARM|0|steam-arm|Steam ARM|Exit Steam ARM and start it again: this game then "
      "downloads and runs its Windows build.|[]|{'urgency': <byte 1>}|5000|" in note and note.strip().endswith("0")
      and "steam-arm: notice: shown" in out, note + out)
check("H11 nothing written: no record, no mapping (launcher sets it)", not rd(rec_file(home)) and "proton" not in mapping_of(steam))
out, note, home, steam = hrun(h=HANDLER_NOSKIP)
check("H11b skip_launch False: notice + log, title starts",
      "RESULT" in out and "EXIT" not in out and "starts Linux build)" in out and "Notify" in note, out)
out, note, _, _ = hrun(env={"STEAM_ARM_AUTO_BUILD": "0"})
check("H12 STEAM_ARM_AUTO_BUILD=0: starts, launch option kept", "RESULT" in out and
      "steam-arm: launch option kept: STEAM_ARM_AUTO_BUILD=0 (source32: Linux build)" in out and not note, out)
out, note, _, _ = hrun(maps={"220": "steamlinuxruntime"})
check("H13 mapping steamlinuxruntime: starts, Linux build kept (forced build)",
      "RESULT" in out and "steam-arm: source32: Linux build kept (forced build)" in out and not note, out)
out, note, _, _ = hrun(rec=True)
check("H13b record present, mapping absent: starts, automatic choice undone",
      "RESULT" in out and "source32: Linux build kept (automatic choice undone)" in out, out)
out, note, _, _ = hrun(h=HANDLER_NOAB)
check("H14 helper file missing: starts, no source32 or auto-build line (2.2 behaviour)",
      "RESULT" in out and "source32" not in out and "auto-build" not in out, out)
out, note, _, _ = hrun(fex="FEX-2610\n")
check("H15 FEX-2610: starts with suggestion line", "RESULT" in out and
      "source32: 32-bit Source engine Linux build stops at loading screen under emulation; Windows build suggested "
      "(FEX tool 2610 newer than tested): steam-arm-config, Graphics > Route per game > windows" in out and not note, out)
out, note, _, _ = hrun("source64")
check("H16 64-bit Source (start script names 64-bit binary): no source32 line", "RESULT" in out and "source32" not in out, out)
out, note, _, _ = hrun("unity32", argv_extra=())
check("H16 32-bit Unity: no source32 line", "RESULT" in out and "source32" not in out, out)
out, note, _, _ = hrun(argv_extra=())
check("H16 hl2_linux without -game: no source32 line", "RESULT" in out and "source32" not in out, out)
conf(COMPONENTS_ON="glx-lax")
out, note, _, _ = hrun()
check("H19 vk-spoof not chosen: starts with suggestion, no skip (box bug 3)", "RESULT" in out and "EXIT" not in out
      and "Windows build suggested (component vk-spoof off)" in out and not note, out)
conf(GPU_FAMILY="broadcom-v3d")
out, note, _, _ = hrun()
check("H17 other GPU family: starts, suggestion", "RESULT" in out and "Windows build suggested (GPU family broadcom-v3d not tested)" in out, out)
conf()
out, note, _, _ = hrun(env={"DBUS_SESSION_BUS_ADDRESS": "", "XDG_RUNTIME_DIR": os.path.join(TMP, "norun")})
check("H18 no session bus: notice not shown (logged), start still skipped",
      "steam-arm: notice: not shown (no session bus)" in out and "EXIT 0" in out and not note, out)

shutil.rmtree(TMP, ignore_errors=True)
print("%d failed" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
