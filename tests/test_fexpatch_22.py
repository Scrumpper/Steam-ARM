#!/usr/bin/env python3
"""steam-arm-fexpatch.py (outline 2a item 22): patch / unpatch of Valve's FEX tool files, pre-2609 and 2609+.
Extracted from installer under test; its other-flavour flag path (second /etc settings file) rewritten to a temp file in
the extract only. Synthetic fex-compat-tool stand-in in fixtures/fex-tool (stock two LD_PRELOAD lines). Internal."""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
NEW = _INST
START = "cat > /usr/local/lib/steam-arm-fexpatch.py <<'FEXPY'\n"
TMP = tempfile.mkdtemp(prefix="sarm232-fexpatch-")
FLAG = os.path.join(TMP, "other-flavour.conf")
src = open(NEW).read()
i = src.index(START) + len(START)
body = src[i:src.index("\nFEXPY\n", i) + 1]
# other-flavour flag path: only quoted /etc/<other>/steam-arm.conf in helper
FLAG_P = (re.findall(r'"/etc/(?!steam-arm/)[a-z0-9-]+/steam-arm\.conf"', body) or [""])[0]
assert body.count(FLAG_P) == 1, "flag path layout changed"
TOOL = os.path.join(TMP, "steam-arm-fexpatch.py")
open(TOOL, "w").write(body.replace(FLAG_P, repr(FLAG)))
STOCK_CT = open(os.path.join(HERE, "fixtures", "fex-tool", "fex-compat-tool")).read()
VALVE = "    if 'LD_PRELOAD' in os.environ:\n        del os.environ['LD_PRELOAD']\n"
STOCK_TPL = '{\n\t"Config": {\n\t\t"RootFS": "Ubuntu_24_04",\n\t\t"Multiblock": "1"\n\t}\n}\n'
STOCK_DB = json.dumps({"DB": {"GL": {"Library": "libGL-guest.so"}, "Vulkan": {"Library": "libvulkan-guest.so"},
                              "EGL": {"Library": "libEGL-guest.so", "Overlay": ["/usr/lib/x86_64-linux-gnu/libEGL.so.1"]},
                              "asound": {"Library": "libasound-guest.so"}}}, indent=4) + "\n"
FAILS = []
SOCK = "/run/user/%d/steam-arm-fexserver.sock" % os.getuid()


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[:1200])


def tool_dir(name, versions="FEX-2607-76-g1a2b3c\n", ct=STOCK_CT, tpl=STOCK_TPL, db=STOCK_DB, age=60):
    d = os.path.join(TMP, name)
    os.makedirs(os.path.join(d, "usr/share/fex-emu"))
    files = {"fex-compat-tool": ct, "ConfigTemplate.json": tpl, "usr/share/fex-emu/ThunksDB.json": db, "VERSIONS.txt": versions}
    for rel, text in files.items():
        if text is None:
            continue
        p = os.path.join(d, rel)
        open(p, "w").write(text)
        os.utime(p, (time.time() - age,) * 2)
    if ct is not None:
        os.chmod(os.path.join(d, "fex-compat-tool"), 0o755)
    return d


def P(d):
    return {"ct": os.path.join(d, "fex-compat-tool"), "tpl": os.path.join(d, "ConfigTemplate.json"),
            "db": os.path.join(d, "usr/share/fex-emu/ThunksDB.json")}


def rd(p):
    return open(p, "rb").read()


def snap(d):
    return {k: (rd(p), os.stat(p).st_ino, os.stat(p).st_mtime_ns) for k, p in P(d).items() if os.path.exists(p)}


def run(*args):
    r = subprocess.run([sys.executable, TOOL] + list(args), capture_output=True, text=True)
    return r.returncode, r.stderr


def leftovers(d):
    return sorted(f for dp, _, fs in os.walk(d) for f in fs if ".steam-arm-" in f)


def age(d, s=60):
    for p in P(d).values():
        if os.path.exists(p):
            os.utime(p, (time.time() - s,) * 2)


# --- pre-2609: all three files patched ---
d = tool_dir("pre")
orig = {k: rd(p) for k, p in P(d).items()}
rc, err = run("--no-wait", d)
check("pre-2609 patch: rc 0, quiet", rc == 0 and not err, (rc, err))
ct, tpl, db = rd(P(d)["ct"]).decode(), json.loads(rd(P(d)["tpl"])), json.loads(rd(P(d)["db"]))
check("pre-2609 patch: handler block in place of Valve's two lines",
      VALVE not in ct and "# steam-arm handler v2" in ct and "runpy.run_path('/usr/local/lib/steam-arm-handler.py')" in ct, ct[-800:])
check("pre-2609 patch: compat tool still compiles", compile(ct, "ct", "exec") is not None)
check("pre-2609 patch: template socket, SilentLog, thunks on, own keys kept",
      tpl["Config"] == {"RootFS": "Ubuntu_24_04", "Multiblock": "1", "ServerSocketPath": SOCK, "SilentLog": "1"}
      and tpl["ThunksDB"] == {"GL": "1", "Vulkan": "1"}, tpl)
gl_ov = db["DB"]["GL"].get("Overlay", [])
check("pre-2609 patch: ThunksDB overlay paths for GL (pressure-vessel, aliases, /run/gfx, both arches)",
      len(gl_ov) == 24 and "/run/gfx/main/usr/lib/i386-linux-gnu/libGL.so.1" in gl_ov
      and "/usr/lib/pressure-vessel/overrides/lib/x86_64-linux-gnu/aliases/libGL.so" in gl_ov, gl_ov)
check("pre-2609 patch: EGL keeps own overlay entry first, entries without thunk names untouched",
      db["DB"]["EGL"]["Overlay"][0] == "/usr/lib/x86_64-linux-gnu/libEGL.so.1" and "Overlay" not in db["DB"]["asound"], db["DB"])
check("pre-2609 patch: originals saved byte for byte",
      all(rd(P(d)[k] + ".steam-arm-orig") == orig[k] for k in orig), leftovers(d))
check("pre-2609 patch: sha records match written bytes",
      all(open(P(d)[k] + ".steam-arm-sha").read().strip() == hashlib.sha256(rd(P(d)[k])).hexdigest() for k in orig))
check("pre-2609 patch: compat tool mode kept (755)", os.stat(P(d)["ct"]).st_mode & 0o777 == 0o755)
age(d)
s1 = snap(d)
rc, err = run("--no-wait", d)
check("repeat patch: rc 0, no file rewritten (bytes, inode, mtime)", rc == 0 and snap(d) == s1, (rc, err))
rc, err = run("--unpatch", d)
check("unpatch: rc 0", rc == 0, err)
check("unpatch: all three files byte-identical to Valve's", all(rd(P(d)[k]) == orig[k] for k in orig))
check("unpatch: no .steam-arm-orig / -sha / temp files left", leftovers(d) == [], leftovers(d))

# --- 2609+: ThunksDB never touched ---
for ver in ("FEX-2609\n", "FEX-2609.1\n", "FEX-2611-3-gdeadbee\n"):
    d = tool_dir("new-" + ver.strip(), versions=ver)
    orig = {k: rd(p) for k, p in P(d).items()}
    db_st = os.stat(P(d)["db"])
    rc, err = run("--no-wait", d)
    check("%s patch: ThunksDB untouched, no saved copy" % ver.strip(),
          rc == 0 and rd(P(d)["db"]) == orig["db"] and os.stat(P(d)["db"]).st_ino == db_st.st_ino
          and not os.path.exists(P(d)["db"] + ".steam-arm-orig"), (rc, err, leftovers(d)))
    check("%s patch: template and compat tool patched" % ver.strip(),
          rd(P(d)["tpl"]) != orig["tpl"] and b"# steam-arm handler v2" in rd(P(d)["ct"]))
    rc, err = run("--unpatch", d)
    check("%s unpatch: byte-identical, nothing left" % ver.strip(),
          rc == 0 and all(rd(P(d)[k]) == orig[k] for k in orig) and leftovers(d) == [], (rc, err, leftovers(d)))
d = tool_dir("noversions", versions=None)
run("--no-wait", d)
check("no VERSIONS.txt: treated as pre-2609 (ThunksDB patched)", os.path.exists(P(d)["db"] + ".steam-arm-orig"))

# --- sha mismatch: file changed by someone else after the patch ---
d = tool_dir("foreign")
orig = {k: rd(p) for k, p in P(d).items()}
run("--no-wait", d)
t = json.loads(rd(P(d)["tpl"]))
t["Config"]["TSOEnabled"] = "0"
open(P(d)["tpl"], "w").write(json.dumps(t, indent=2))
rc, err = run("--unpatch", d)
t2 = json.loads(rd(P(d)["tpl"]))
check("sha mismatch unpatch: saved copy not restored, own keys taken out, foreign key kept",
      rc == 0 and t2["Config"] == {"RootFS": "Ubuntu_24_04", "Multiblock": "1", "TSOEnabled": "0"} and "ThunksDB" not in t2, t2)
check("sha mismatch unpatch: other files still restored byte for byte",
      rd(P(d)["ct"]) == orig["ct"] and rd(P(d)["db"]) == orig["db"] and leftovers(d) == [], leftovers(d))
# Steam updated the tool after the patch: new stock file, old record
d = tool_dir("update")
run("--no-wait", d)
newtpl = STOCK_TPL.replace('"1"', '"0"')
open(P(d)["tpl"], "w").write(newtpl)
age(d)
rc, err = run("--no-wait", d)
check("tool updated by Steam: new stock template saved as original, patched again",
      rc == 0 and rd(P(d)["tpl"] + ".steam-arm-orig").decode() == newtpl and SOCK in rd(P(d)["tpl"]).decode(), (rc, err))
rc, err = run("--unpatch", d)
check("tool updated by Steam: unpatch gives new stock template back", rd(P(d)["tpl"]).decode() == newtpl)

# --- no record (setup from before the sha record): same_base fallback ---
d = tool_dir("norecord")
orig = {k: rd(p) for k, p in P(d).items()}
run("--no-wait", d)
for p in P(d).values():
    os.remove(p + ".steam-arm-sha")
age(d)
s1 = snap(d)
rc, err = run("--no-wait", d)
check("no record, repeat patch: nothing rewritten", rc == 0 and snap(d) == s1, (rc, err))
rc, err = run("--unpatch", d)
check("no record unpatch: same_base -> saved originals back byte for byte",
      rc == 0 and all(rd(P(d)[k]) == orig[k] for k in orig) and leftovers(d) == [], (rc, err, leftovers(d)))
# older setup without record and without /run/gfx paths: completed, Valve's saved original kept
d = tool_dir("older")
orig = {k: rd(p) for k, p in P(d).items()}
run("--no-wait", d)
os.remove(P(d)["db"] + ".steam-arm-sha")
db = json.loads(rd(P(d)["db"]))
for e in db["DB"].values():
    if "Overlay" in e:
        e["Overlay"] = [x for x in e["Overlay"] if not x.startswith("/run/gfx/")]
open(P(d)["db"], "w").write(json.dumps(db, indent=2))
age(d)
rc, err = run("--no-wait", d)
check("older setup, no record: missing /run/gfx paths added, saved original stays Valve's",
      rc == 0 and "/run/gfx/main/usr/lib/x86_64-linux-gnu/libGL.so" in rd(P(d)["db"]).decode()
      and rd(P(d)["db"] + ".steam-arm-orig") == orig["db"], (rc, err))
rc, err = run("--unpatch", d)
check("older setup: unpatch gives Valve's ThunksDB back", rc == 0 and rd(P(d)["db"]) == orig["db"])
d = tool_dir("norecord-edit")
run("--no-wait", d)
os.remove(P(d)["tpl"] + ".steam-arm-sha")
t = json.loads(rd(P(d)["tpl"]))
t["Config"]["RootFS"] = "Other"
open(P(d)["tpl"], "w").write(json.dumps(t, indent=4))
rc, err = run("--unpatch", d)
t2 = json.loads(rd(P(d)["tpl"]))
check("no record + foreign edit: own keys out, edit kept (no restore)", t2 == {"Config": {"RootFS": "Other", "Multiblock": "1"}}, t2)

# --- earlier filter (v1) and other flavour's handler ---
V1_BLOCK = ("    # steam-arm preload filter v1\n    try:\n        import runpy\n        runpy.run_path('/usr/local/lib/steam-arm-preload.py')\n"
            "    except Exception as _e:\n        print('steam-arm: filter failed:', _e)\n        os.environ.pop('LD_PRELOAD', None)\n")
d = tool_dir("v1", ct=STOCK_CT.replace(VALVE, V1_BLOCK))
rc, err = run("--no-wait", d)
ct = rd(P(d)["ct"]).decode()
check("v1 filter: replaced by v2 handler block", rc == 0 and "preload filter v1" not in ct and ct.count("# steam-arm handler v2") == 1, ct[-700:])
rc, err = run("--unpatch", d)
ct = rd(P(d)["ct"]).decode()
check("v1 filter: unpatch puts Valve's two lines back (no stock copy saved)", rc == 0 and ct == STOCK_CT, ct[-600:])
OTHER = ("    # steam-arm handler v2\n    try:\n        import runpy\n        runpy.run_path('/usr/local/lib/other-steam-handler.py')\n"
         "    except Exception as _e:\n        print('steam-arm: handler failed, Valve default applies:', _e)\n        os.environ.pop('LD_PRELOAD', None)\n")
d = tool_dir("other", ct=STOCK_CT.replace(VALVE, OTHER))
rc, err = run("--no-wait", d)
ct = rd(P(d)["ct"]).decode()
check("other flavour's handler: re-pointed to this handler", rc == 0 and "other-steam-handler" not in ct
      and "/usr/local/lib/steam-arm-handler.py" in ct, ct[-600:])
d = tool_dir("other-keep", ct=STOCK_CT.replace(VALVE, OTHER))
open(FLAG, "w").write("x\n")
rc, err = run("--unpatch", d)
check("other flavour installed: its handler block stays on unpatch", rc == 0 and rd(P(d)["ct"]).decode() == STOCK_CT.replace(VALVE, OTHER))
os.remove(FLAG)
rc, err = run("--unpatch", d)
check("other flavour not installed: its block replaced by Valve's lines", rc == 0 and rd(P(d)["ct"]).decode() == STOCK_CT)

# --- non-stock tool, broken files, missing pieces ---
d = tool_dir("nonstock", ct=STOCK_CT.replace(VALVE, "    os.environ.pop('LD_PRELOAD', None)\n"))
before = rd(P(d)["ct"])
rc, err = run("--no-wait", d)
check("Valve changed text: exit 3, message, compat tool untouched",
      rc == 3 and "Valve changed the text of fex-compat-tool" in err and rd(P(d)["ct"]) == before
      and not os.path.exists(P(d)["ct"] + ".steam-arm-orig"), (rc, err))
check("Valve changed text: template and ThunksDB still patched", SOCK in rd(P(d)["tpl"]).decode())
d = tool_dir("badjson", tpl="{ not json")
rc, err = run("--no-wait", d)
check("unreadable template: exit 3, 'could not read', file untouched",
      rc == 3 and "could not read the emulation tool's settings" in err and rd(P(d)["tpl"]) == b"{ not json", (rc, err))
d = tool_dir("badlayout", tpl='{"Config": []}')
rc, err = run("--no-wait", d)
check("unknown template layout: exit 3", rc == 3 and "unknown layout" in err, (rc, err))
d = tool_dir("noct", ct=None)
rc, err = run("--no-wait", d)
check("no compat tool: rc 0, other files patched", rc == 0 and SOCK in rd(P(d)["tpl"]).decode(), (rc, err))
rc, err = run("--unpatch", os.path.join(TMP, "missing"))
check("unpatch of missing folder: rc 0", rc == 0, err)
d = tool_dir("stockonly")
orig = {k: rd(p) for k, p in P(d).items()}
rc, err = run("--unpatch", d)
check("unpatch of stock tool: rc 0, untouched", rc == 0 and all(rd(P(d)[k]) == orig[k] for k in orig) and leftovers(d) == [])

# --- settle: Steam still writing ---
d = tool_dir("fresh", age=0)
rc, err = run("--no-wait", d)
check("--no-wait with files written now: exit 75, nothing changed", rc == 75 and "still being updated" in err
      and leftovers(d) == [], (rc, err))
d = tool_dir("future", age=-3600)
rc, err = run("--no-wait", d)
check("--no-wait with future mtime (clock stepped back): exit 75", rc == 75, (rc, err))
d = tool_dir("wait", age=0)
t0 = time.monotonic()
rc, err = run(d)
check("default mode: waits 2 s for files to settle, then patches", rc == 0 and time.monotonic() - t0 >= 2.0
      and b"# steam-arm handler v2" in rd(P(d)["ct"]), (rc, err))

shutil.rmtree(TMP, ignore_errors=True)
print("%d FAIL" % len(FAILS) if FAILS else "all PASS")
sys.exit(1 if FAILS else 0)
