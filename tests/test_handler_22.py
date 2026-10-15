#!/usr/bin/env python3
"""Steam ARM 2.2 handler tests (outline 2a items 19, 20, 34): Godot 3 GL report, embedded PCK detection,
Godot rules off for Windows builds under x86 Proton. Extracts steam-arm-handler.py from installer under test
and runs it on fake titles as Valve's FEX tool does (runpy from __main__). Internal; not for release zips."""
import json
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
PROJ = os.path.dirname(HERE)
NEW = _INST
START = "cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n"

DRIVER = r'''
import json, os, runpy, sys
def generate_app_config():
    return {"Config": {"TSOEnabled": True}, "ThunksDB": {}}
sys.argv = json.loads(os.environ.pop("T_ARGV"))
runpy.run_path(os.environ.pop("T_HANDLER"))
out = {"argv": sys.argv, "env": {k: v for k, v in os.environ.items() if k.startswith("MESA_")}}
print("RESULT " + json.dumps(out))
'''

TMP = tempfile.mkdtemp(prefix="sarm232-handler-")
s = open(NEW).read()
i = s.index(START) + len(START)
HANDLER = os.path.join(TMP, "handler.py")
open(HANDLER, "w").write(s[i:s.index("\nHANDLERPY\n", i) + 1])
DRV = os.path.join(TMP, "driver.py")
open(DRV, "w").write(DRIVER)
FAILS = []
TOOL = ["fex-compat-tool", "waitforexitandrun"]
G = os.path.join(TMP, "games")


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[:1500])


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data)


def elf_bytes():
    return b"\x7fELF" + bytes([2, 1, 1]) + b"\0" * 57 + b"code" * 64


def pck(major, fmt=None):
    fmt = (2 if major >= 4 else 1) if fmt is None else fmt
    return b"GDPC" + struct.pack("<IIII", fmt, major, 2, 1) + b"\0" * 64 + b"res://data" * 8


def embedded(major, fmt=None, size_delta=0, pad=0):
    """Executable with PCK appended as Godot's "Embed PCK" export writes it: pck, uint64 size, GDPC."""
    p = pck(major, fmt) + b"\0" * pad
    return elf_bytes() + b"\0" * 5 + p + struct.pack("<Q", len(p) + size_delta) + b"GDPC"


def run(argv, profile="", cwd=None, env=None):
    home = tempfile.mkdtemp(dir=TMP)
    if profile:
        put(os.path.join(home, ".config/steam-arm/titles.conf"), ("100 %s\n" % profile).encode())
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": "100",
         "T_ARGV": json.dumps(argv), "T_HANDLER": HANDLER, "STEAM_ARM_RENDERER_CHECK": "0"}
    e.update(env or {})
    r = subprocess.run([sys.executable, DRV], env=e, cwd=cwd or home, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    res = json.loads([l for l in r.stdout.splitlines() if l.startswith("RESULT ")][-1][7:])
    res["log"] = r.stdout
    return res


def gl33(r):
    return r["env"].get("MESA_GL_VERSION_OVERRIDE") == "3.3" and r["env"].get("MESA_GLSL_VERSION_OVERRIDE") == "330"


# --- separate .pck (existing detection) ---
g4 = os.path.join(G, "g4")
put(os.path.join(g4, "game.x86_64"), elf_bytes())
put(os.path.join(g4, "game.pck"), pck(4))
r = run(TOOL + [os.path.join(g4, "game.x86_64")], cwd=g4)
check("godot 4 .pck: opengl3 + GL 3.3", gl33(r) and r["argv"][-2:] == ["--rendering-driver", "opengl3"]
      and "godot 4: OpenGL renderer, GL 3.3 report" in r["log"], r)

# --- item 19: Godot 3 GL 3.3 report ---
g3 = os.path.join(G, "g3")
put(os.path.join(g3, "game.x86_64"), elf_bytes())
put(os.path.join(g3, "game.pck"), pck(3))
r = run(TOOL + [os.path.join(g3, "game.x86_64")], cwd=g3)
check("godot 3: GL 3.3 + GLSL 330 report, no profile", gl33(r) and "godot 3: GL 3.3 report" in r["log"], r)
check("godot 3: no renderer option added", "--rendering-driver" not in r["argv"], r["argv"])
r = run(TOOL + [os.path.join(g3, "game.x86_64")], cwd=g3, profile="godot=gl")
check("godot 3: profile godot=gl same", gl33(r) and "godot 3: GL 3.3 report" in r["log"], r)
r = run(TOOL + [os.path.join(g3, "game.x86_64")], cwd=g3, profile="godot=vulkan")
check("godot 3: profile godot=vulkan -> left as is", not r["env"] and "godot 3: left as is" in r["log"], r)
r = run(TOOL + [os.path.join(g3, "game.x86_64")], cwd=g3, env={"MESA_GL_VERSION_OVERRIDE": "4.0"})
check("godot 3: launch option GL 4.0 kept, logged in effect",
      r["env"].get("MESA_GL_VERSION_OVERRIDE") == "4.0" and r["env"].get("MESA_GLSL_VERSION_OVERRIDE") == "330"
      and "launch option kept: MESA_GL_VERSION_OVERRIDE=4.0 (rule wanted 3.3)" in r["log"]
      and "godot 3: GL 4.0 report" in r["log"], r)
r = run(TOOL + [os.path.join(g3, "game.x86_64")], cwd=g3,
        profile="env=MESA_GL_VERSION_OVERRIDE=3.3;MESA_GLSL_VERSION_OVERRIDE=330")
check("godot 3: 2.1 workaround profile still works", gl33(r), r)
g2 = os.path.join(G, "g2")
put(os.path.join(g2, "game.x86_64"), elf_bytes())
put(os.path.join(g2, "data.pck"), pck(2, fmt=0))
r = run(TOOL + [os.path.join(g2, "game.x86_64")], cwd=g2)
check("godot 2: left as is", not r["env"] and "godot 2: left as is" in r["log"], r)

# --- item 20: PCK embedded in executable ---
e4 = os.path.join(G, "e4")
put(os.path.join(e4, "game.x86_64"), embedded(4, fmt=3))
r = run(TOOL + [os.path.join(e4, "game.x86_64")], cwd=e4)
check("embedded godot 4 (format 3): opengl3 + GL 3.3", gl33(r) and r["argv"][-2:] == ["--rendering-driver", "opengl3"], r)
e4p = os.path.join(G, "e4p")
put(os.path.join(e4p, "game.x86_64"), embedded(4, pad=4))
r = run(TOOL + [os.path.join(e4p, "game.x86_64")], cwd=e4p)
check("embedded godot 4, padded to 8 bytes: detected", "godot 4: OpenGL renderer" in r["log"], r["log"])
e3 = os.path.join(G, "e3")
put(os.path.join(e3, "bin/game.x86_64"), embedded(3))
put(os.path.join(e3, "start.sh"), b'#!/bin/sh\ncd "$(dirname "$0")"\nexec ./bin/game.x86_64 "$@"\n')
r = run(TOOL + ["/w/reaper", "--", os.path.join(e3, "start.sh")], cwd=e3)
check("embedded godot 3 behind start script: GL 3.3", gl33(r) and "godot 3: GL 3.3 report" in r["log"], r)
bad = os.path.join(G, "bad")
put(os.path.join(bad, "big.x86_64"), embedded(4, size_delta=1 << 40))
put(os.path.join(bad, "shift.x86_64"), embedded(4, size_delta=3))
put(os.path.join(bad, "major.x86_64"), embedded(77))
put(os.path.join(bad, "tail.x86_64"), elf_bytes() + struct.pack("<Q", 16) + b"GDPC")
put(os.path.join(bad, "tiny.x86_64"), b"\x7fELF" + b"GDPC" * 3)
for n in ("big", "shift", "major", "tail", "tiny"):
    r = run(TOOL + [os.path.join(bad, n + ".x86_64")], cwd=bad)
    check("embedded footer invalid (%s): no Godot rule" % n, not r["env"] and "godot" not in r["log"], r)
ww = os.path.join(G, "wwise")
put(os.path.join(ww, "game.x86_64"), elf_bytes())
put(os.path.join(ww, "Init.pck"), b"AKPK" + b"\0" * 60)
r = run(TOOL + [os.path.join(ww, "game.x86_64")], cwd=ww)
check("non-Godot .pck (Wwise AKPK): no Godot rule", not r["env"] and "godot" not in r["log"], r)
mix = os.path.join(G, "mix")
put(os.path.join(mix, "game.x86_64"), embedded(3))
put(os.path.join(mix, "Init.pck"), b"AKPK" + b"\0" * 60)
r = run(TOOL + [os.path.join(mix, "game.x86_64")], cwd=mix)
check("non-Godot .pck beside embedded godot 3: embedded found", "godot 3: GL 3.3 report" in r["log"], r["log"])
# pack lookup as Godot does it (handler-1..3)
sb = os.path.join(G, "sbin")
put(os.path.join(sb, "bin/game.x86_64"), elf_bytes())
put(os.path.join(sb, "bin/game.pck"), pck(3))
put(os.path.join(sb, "start.sh"), b'#!/bin/sh\ncd "$(dirname "$0")"\nexec ./bin/game.x86_64 "$@"\n')
r = run(TOOL + ["/w/reaper", "--", os.path.join(sb, "start.sh")], cwd=sb)
check("start script at root, binary + .pck in bin/: godot 3 found", gl33(r) and "godot 3: GL 3.3 report" in r["log"], r)
br = os.path.join(G, "Game [Demo]?")
put(os.path.join(br, "game.x86_64"), elf_bytes())
put(os.path.join(br, "game.pck"), pck(4))
r = run(TOOL + [os.path.join(br, "game.x86_64")], cwd=br)
check("glob characters in install folder name: godot 4 found",
      r["argv"][-2:] == ["--rendering-driver", "opengl3"] and "godot 4: OpenGL renderer" in r["log"], r)
pr = os.path.join(G, "prec")
put(os.path.join(pr, "game.x86_64"), embedded(4))
put(os.path.join(pr, "old.pck"), pck(3))
r = run(TOOL + [os.path.join(pr, "game.x86_64")], cwd=pr)
check("embedded godot 4 wins over stray godot 3 .pck beside it", "godot 4: OpenGL renderer" in r["log"]
      and "godot 3" not in r["log"], r["log"])
nm = os.path.join(G, "named")
put(os.path.join(nm, "game.x86_64"), elf_bytes())
put(os.path.join(nm, "a-old.pck"), pck(3))
put(os.path.join(nm, "game.pck"), pck(4))
r = run(TOOL + [os.path.join(nm, "game.x86_64")], cwd=nm)
check("<name>.pck of executable wins over other .pck", "godot 4: OpenGL renderer" in r["log"]
      and "godot 3" not in r["log"], r["log"])
plain = os.path.join(G, "plain")
put(os.path.join(plain, "game.bin"), elf_bytes())
r = run(TOOL + [os.path.join(plain, "game.bin")], cwd=plain)
check("plain title: no Godot rule", not r["env"] and "godot" not in r["log"], r)

# --- item 34: Windows builds under x86 Proton ---
PROTON = ["/x/SteamLinuxRuntime_sniper/_v2-entry-point", "--verb=waitforexitandrun", "--",
          "/x/Proton 11.0/proton", "waitforexitandrun"]
w4 = os.path.join(G, "w4")
put(os.path.join(w4, "game.exe"), b"MZ" + b"\0" * 62)
put(os.path.join(w4, "game.pck"), pck(4))
r = run(TOOL + PROTON + [os.path.join(w4, "game.exe")], cwd=w4)
check("proton godot 4: no renderer option, no GL report", not r["env"] and "--rendering-driver" not in r["argv"], r)
check("proton godot 4: logged as left alone", "godot 4: Windows build under x86 Proton, left as is" in r["log"], r["log"])
r = run(TOOL + PROTON + [os.path.join(w4, "game.exe")], cwd=w4, profile="godot=gl")
check("proton godot 4: profile godot=gl does not apply rule", not r["env"] and "--rendering-driver" not in r["argv"], r)
w3 = os.path.join(G, "w3")
put(os.path.join(w3, "game.exe"), b"MZ" + b"\0" * 62)
put(os.path.join(w3, "game.pck"), pck(3))
r = run(TOOL + PROTON + [os.path.join(w3, "game.exe")], cwd=w3)
check("proton godot 3: no GL report", not r["env"] and "godot 3: Windows build under x86 Proton" in r["log"], r)
r = run(TOOL + PROTON + [os.path.join(w4, "game.exe")], cwd=w4,
        profile="env=MESA_GL_VERSION_OVERRIDE=3.3;MESA_GLSL_VERSION_OVERRIDE=330 args=--rendering-driver;opengl3")
check("proton godot 4: profile env/args still applied by hand", gl33(r) and r["argv"][-2:] == ["--rendering-driver", "opengl3"], r)

print("%d FAIL" % len(FAILS) if FAILS else "all PASS")
sys.exit(1 if FAILS else 0)
