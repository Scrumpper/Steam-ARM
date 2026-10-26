#!/usr/bin/env python3
"""Steam ARM 3.1 Valve Frame runtime: steam-arm-frameruntime.py (apply, list, applied, drop). Each Valve runtime value,
own mapping and GE-Proton kept, undone choice, unknown cache, FRAME_RUNTIME off, x86 client, helper failure.
Helper, compatmap and autobuild extracted from installer under test (SARM_INST picks another installer); conf,
compatmap, autobuild and appinfo reader paths rewritten to temp copies in the extracts only (reader: stand-in with
contract lines). Internal; not for release zips."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST  # noqa: E402
SRC = open(INST).read()
TMP = tempfile.mkdtemp(prefix="sarm31-fr-")
CONF = os.path.join(TMP, "steam-arm.conf")
RTS = os.path.join(TMP, "rts.json")
FAILS = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[-1500:])


def heredoc(start, end):
    i = SRC.find(start)
    if i < 0:
        return None
    i += len(start)
    return SRC[i:SRC.index("\n" + end + "\n", i) + 1]


FR_SRC = heredoc("cat > /usr/local/lib/steam-arm-frameruntime.py <<'FRPY'\n", "FRPY")
check("F0 helper heredoc steam-arm-frameruntime.py present in installer", FR_SRC is not None)
if FR_SRC is None:
    sys.exit(1)
AB_SRC = heredoc("cat > /usr/local/lib/steam-arm-autobuild.py <<'ABPY'\n", "ABPY")
CM_SRC = heredoc("cat > /usr/local/lib/steam-arm-compatmap.py <<'PYEOF'\n", "PYEOF")
CM = os.path.join(TMP, "compatmap.py")
assert CM_SRC.count("if steam_up():") == 1
open(CM, "w").write(CM_SRC.replace("if steam_up():", "if False:"))
CMFAIL = os.path.join(TMP, "compatmap-fail.py")
open(CMFAIL, "w").write("import sys\nsys.exit('steam-arm-compatmap: Steam ARM is running. Close it first')\n")
AB = os.path.join(TMP, "autobuild.py")
assert AB_SRC.count('CONF = "/etc/steam-arm/steam-arm.conf"') == 1
open(AB, "w").write(AB_SRC.replace('CONF = "/etc/steam-arm/steam-arm.conf"', "CONF = %r" % CONF))
# reader stand-in: 9-column contract line per requested appid, Frame runtime (column 5) from rts.json
AI = os.path.join(TMP, "appinfo.py")
open(AI, "w").write("import json, sys\nr = json.load(open(%r))\nfor a in sys.argv[2:]:\n"
                    "    print('\\t'.join([a, 'unknown', 'unknown', 'unknown', r.get(a, 'unknown'), '-', 'unknown', "
                    "'unknown', 'unknown']))\n" % RTS)


def helper(cm=CM, name="fr.py", exp_tool=None):
    s = FR_SRC
    for a, b in (('CONF = "/etc/steam-arm/steam-arm.conf"', CONF), ('COMPATMAP = "/usr/local/lib/steam-arm-compatmap.py"', cm),
                 ('APPINFO = "/usr/local/lib/steam-arm-appinfo.py"', AI), ('AUTOBUILD = "/usr/local/lib/steam-arm-autobuild.py"', AB)):
        assert s.count(a) == 1, a
        s = s.replace(a, a.split(" = ")[0] + " = %r" % b)
    if exp_tool is not None:
        assert s.count('"experimental": "proton-experimental-arm64", "linux"') == 1
        s = s.replace('"experimental": "proton-experimental-arm64", "linux"', '"experimental": %r, "linux"' % exp_tool)
    p = os.path.join(TMP, name)
    open(p, "w").write(s)
    return p


FR = helper()
FR_NOEXP = helper(name="fr-noexp.py", exp_tool="")
FR_CMFAIL = helper(CMFAIL, "fr-cmfail.py")


def put(path, data=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(data)


VDF = ('"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n'
       '\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n%s\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n')


def vdf_map(maps):
    return VDF % "".join('\t\t\t\t\t"%s"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n'
                         '\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n' % (a, t) for a, t in maps.items())


def library(rts, maps=None, cache=True):
    """Client home with one installed title per entry of rts (appid -> Valve Frame runtime); returns (home, steam)."""
    home = tempfile.mkdtemp(dir=TMP, prefix="home-")
    steam = os.path.join(home, ".local/share/Steam")
    put(os.path.join(steam, "config/config.vdf"), vdf_map(maps or {}))
    if cache:
        put(os.path.join(steam, "appcache/appinfo.vdf"), "stand-in\n")
    for a in rts:
        put(os.path.join(steam, "steamapps/appmanifest_%s.acf" % a),
            '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"Title"\n\t"installdir"\t\t"Title %s"\n}\n' % (a, a))
    json.dump({a: r for a, r in rts.items() if r}, open(RTS, "w"))
    return home, steam


def conf(**kv):
    kv.setdefault("FRAME_RUNTIME", "auto")
    open(CONF, "w").write("".join("%s=%s\n" % (k, v) for k, v in kv.items() if v is not None))


def run(*args, h=FR):
    r = subprocess.run([sys.executable, h] + list(args), capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout, r.stderr


def rd(p):
    try:
        return open(p).read()
    except OSError:
        return ""


def rec(home):
    return rd(os.path.join(home, ".config/steam-arm/frame-runtime.conf"))


def tool_of(steam, appid):
    s = rd(os.path.join(steam, "config/config.vdf"))
    i = s.find('"%s"\n' % appid)
    if i < 0:
        return None
    j = s.find('"name"', i)
    return s[j:].split('"')[3] if j >= 0 else None


def rec_has(home, appid, rt, tool):
    return any(l.split()[:3] == [appid, rt, tool] and len(l.split()) == 4 for l in rec(home).splitlines())


# ---------- each runtime value ----------
conf()
home, steam = library({"100": "proton-stable"})
rc, out, err = run("apply", steam)
check("F1 proton-stable, no tool: proton_11-arm64 set, log line names Valve Frame recommendation",
      rc == 0 and tool_of(steam, "100") == "proton_11-arm64" and
      "frame-runtime: app 100: Proton ARM64 stable (proton_11-arm64) set (Valve Frame recommendation proton-stable). "
      "Undo: steam-arm-config, Graphics > Route per game" in out, out + err)
check("F1 record: 100 proton-stable proton_11-arm64 <date>, file 644",
      rec_has(home, "100", "proton-stable", "proton_11-arm64")
      and oct(os.stat(os.path.join(home, ".config/steam-arm/frame-runtime.conf")).st_mode & 0o777) == "0o644", rec(home))
before = rd(os.path.join(steam, "config/config.vdf"))
rc, out, _ = run("apply", steam)
check("F1 second apply: no output, config.vdf byte-identical", out == "" and rd(os.path.join(steam, "config/config.vdf")) == before, out)

home, steam = library({"200": "proton-experimental"})
rc, out, _ = run("apply", steam)
check("F2 proton-experimental: proton-experimental-arm64 set", tool_of(steam, "200") == "proton-experimental-arm64"
      and "Proton ARM64 experimental (proton-experimental-arm64) set (Valve Frame recommendation proton-experimental)" in out
      and rec_has(home, "200", "proton-experimental", "proton-experimental-arm64"), out)
home, steam = library({"450390": "proton-experimental-arm64"})
rc, out, _ = run("apply", steam)
check("F3 proton-experimental-arm64: proton-experimental-arm64 set", tool_of(steam, "450390") == "proton-experimental-arm64"
      and rec_has(home, "450390", "proton-experimental-arm64", "proton-experimental-arm64"), out)
home, steam = library({"200": "proton-experimental", "201": "proton-experimental-arm64"})
rc, out, _ = run("apply", steam, h=FR_NOEXP)
check("F4 experimental tool name unknown: stable set for both experimental values, one log line each",
      tool_of(steam, "200") == "proton_11-arm64" and tool_of(steam, "201") == "proton_11-arm64"
      and out.count("Proton ARM64 experimental tool name unknown, stable used") == 2
      and rec_has(home, "200", "proton-experimental", "proton_11-arm64"), out)
home, steam = library({"300": "native"})
rc, out, _ = run("apply", steam)
check("F5 native: Linux build (steamlinuxruntime) set", tool_of(steam, "300") == "steamlinuxruntime"
      and "Linux build (steamlinuxruntime) set (Valve Frame recommendation native)" in out
      and rec_has(home, "300", "native", "steamlinuxruntime"), out)
home, steam = library({"400": "lepton-stable"})
before = rd(os.path.join(steam, "config/config.vdf"))
rc, out, _ = run("apply", steam)
check("F6 lepton-stable: unchanged, one log line, no record",
      out == "frame-runtime: app 400: Valve Frame runtime lepton-stable; Lepton not available here, tool unchanged\n"
      and rd(os.path.join(steam, "config/config.vdf")) == before and not rec(home), out)
home, steam = library({"500": "proton-future"})
before = rd(os.path.join(steam, "config/config.vdf"))
rc, out, _ = run("apply", steam)
check("F7 runtime value not known here: unchanged, silent", out == "" and rd(os.path.join(steam, "config/config.vdf")) == before and not rec(home), out)

# ---------- own mapping kept ----------
home, steam = library({"100": "proton-stable", "300": "native", "450390": "proton-experimental-arm64"},
                      {"100": "steamlinuxruntime", "300": "GE-Proton11-11-aarch64", "450390": "proton_11-arm64"})
before = rd(os.path.join(steam, "config/config.vdf"))
rc, out, _ = run("apply", steam)
check("F8 own mappings kept (Linux build over proton-stable, GE-Proton over native, stable over experimental): no write, silent",
      out == "" and rd(os.path.join(steam, "config/config.vdf")) == before and not rec(home), out)
rc, out, _ = run("list", steam)
check("F8 list: kept verdict with own tool", "app\t300\tkept\tnative\tGE-Proton11-11-aarch64" in out
      and "app\t100\tkept\tproton-stable\tsteamlinuxruntime" in out, out)

# ---------- unknown cache ----------
home, steam = library({"100": "proton-stable"}, cache=False)
rc, out, _ = run("apply", steam)
check("F9 appinfo cache missing: one line, nothing set", out == "frame-runtime: appinfo cache not read yet; nothing set\n"
      and tool_of(steam, "100") is None and not rec(home), out)
home, steam = library({"100": None, "101": None})
rc, out, _ = run("apply", steam)
check("F9 cache present, titles unknown to it: silent, nothing set", out == "" and tool_of(steam, "100") is None and not rec(home), out)

# ---------- setting off ----------
for v, why in ((None, "absent"), ("off", "off"), ("on", "unknown value")):
    conf(FRAME_RUNTIME=v)
    home, steam = library({"100": "proton-stable"})
    rc, out, _ = run("apply", steam)
    check("F10 FRAME_RUNTIME %s: nothing set, silent" % why, rc == 0 and out == "" and tool_of(steam, "100") is None and not rec(home), out)
rc, out, _ = run("list", steam)
check("F10 list names state off", out.startswith("frame-runtime\toff\n") and "app\t100\tpending\tproton-stable\tproton_11-arm64" in out, out)
conf(CLIENT="x86")
home, steam = library({"100": "proton-stable"})
rc, out, _ = run("apply", steam)
check("F11 x86 client: one line, nothing set", "x86 client" in out and tool_of(steam, "100") is None and not rec(home), out)

# ---------- applied, undone, drop ----------
conf()
home, steam = library({"100": "proton-stable"})
run("apply", steam)
rc, out, _ = run("applied", steam, "100")
check("F12 applied: runtime, tool, label", out == "proton-stable\tproton_11-arm64\tProton ARM64 stable (proton_11-arm64)\n", out)
rc, out, _ = run("list", steam)
check("F12 list: applied verdict", "app\t100\tapplied\tproton-stable\tproton_11-arm64" in out, out)
subprocess.run([sys.executable, CM, os.path.join(steam, "config/config.vdf"), "100", "GE-Proton11-11-aarch64"], capture_output=True)
rc, out, _ = run("applied", steam, "100")
check("F13 own tool after recommendation: applied prints nothing", out == "", out)
rc, out, _ = run("apply", steam)
check("F13 own tool after recommendation: kept on next apply", out == "" and tool_of(steam, "100") == "GE-Proton11-11-aarch64", out)
subprocess.run([sys.executable, CM, os.path.join(steam, "config/config.vdf"), "100", "--remove"], capture_output=True)
rc, out, _ = run("apply", steam)
check("F14 mapping removed, record kept (choice undone): not set again", out == "" and tool_of(steam, "100") is None, out)
rc, out, _ = run("drop", steam, "100")
check("F14 drop: record removed", "record of app 100 removed" in out and "100 " not in rec(home), out + rec(home))
rc, out, _ = run("apply", steam)
check("F14 after drop: recommendation applies again", tool_of(steam, "100") == "proton_11-arm64" and "app 100:" in out, out)
rc, out, _ = run("drop", steam, "999")
check("F14 drop of unknown title: message, no error", rc == 0 and "no record for app 999" in out, out)

# ---------- failures ----------
home, steam = library({"100": "proton-stable"})
rc, out, _ = run("apply", steam, h=FR_CMFAIL)
check("F15 compatmap fails: reason logged, no record", "frame-runtime: app 100: tool not set: steam-arm-compatmap: Steam ARM is running" in out
      and not rec(home), out)
rc, out, err = run("bogus")
check("F16 bad arguments: usage, status 1", rc == 1 and "usage: steam-arm-frameruntime.py" in err, err)
rc, out, err = run("applied", steam, "1x")
check("F16 bad appid: usage", rc == 1 and "usage:" in err, err)

shutil.rmtree(TMP, ignore_errors=True)
print("%d failed" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
