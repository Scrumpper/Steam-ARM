#!/usr/bin/env python3
"""Steam ARM 3.0 D1 handler: title setting mesa=<version> points route B titles at the extra tree
<second tree>-<version>; route A, bad value and missing tree keep the second tree with a log line; run record names the
Mesa in use; 2.3.2 handler ignores the key. Handler extracted from installer under test (SARM_INST); conf path and
second-tree root rewritten to temp copies in the extract only. Internal; not for release zips."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST, old  # noqa: E402

START = "cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n"
CONF_P = '"/etc/steam-arm/steam-arm.conf"'
MALI_P = 'MALI_ROOT = "/opt/fex-rootfs/Ubuntu_24_04-mali"'
DRIVER = r'''
import json, os, runpy, sys
fd = os.environ.pop("T_FEXDIR", None)
if fd:
    g_fex_path = fd
def generate_app_config():
    return {"Config": {}, "ThunksDB": {}}
sys.argv = json.loads(os.environ.pop("T_ARGV"))
runpy.run_path(os.environ.pop("T_HANDLER"))
print("RESULT " + json.dumps({k: v for k, v in os.environ.items() if k.startswith("STEAM_COMPAT_GRAPHICS")}))
'''
TMP = tempfile.mkdtemp(prefix="sarm30-mx-")
CONF = os.path.join(TMP, "steam-arm.conf")
MALI = os.path.join(TMP, "mali-tree")
FAILS = []


def put(path, data=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data if isinstance(data, bytes) else data.encode())


def tree(root, ver):
    put(os.path.join(root, ".steam-arm-mali"), "archive x rootfs y\n")
    put(os.path.join(root, "graphics_provider.json"), "{}\n")
    put(os.path.join(root, "usr/lib/x86_64-linux-gnu/libgallium-%s.so" % ver))


def handler(src, name):
    s = open(src).read()
    i = s.index(START) + len(START)
    h = s[i:s.index("\nHANDLERPY\n", i) + 1]
    assert h.count(MALI_P) == 1, "handler layout changed"
    p = os.path.join(TMP, name)
    open(p, "w").write(h.replace(CONF_P, repr(CONF)).replace(MALI_P, "MALI_ROOT = %r" % MALI))
    return p


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[-1500:])


tree(MALI, "26.1.8")
HANDLER = handler(INST, "handler.py")
P232 = old("2.3.2")
HPREV = handler(P232, "handler-232.py") if P232 else None
DRV = os.path.join(TMP, "driver.py")
open(DRV, "w").write(DRIVER)
TOOL = os.path.join(TMP, "tool")
put(os.path.join(TOOL, "VERSIONS.txt"), "FEX-2607\n")
G = os.path.join(TMP, "lib", "steamapps", "common")


def title(name, files=(), bits=64):
    d = os.path.join(G, name)
    put(os.path.join(d, "game.bin"), b"\x7fELF" + bytes([1 if bits == 32 else 2, 1, 1]) + b"\0" * 57)
    for f in files:
        put(os.path.join(d, f))
    return d


def run(game, profile="", family="mali-csf-v10", h=None, record=False):
    open(CONF, "w").write("GPU_FAMILY=%s\nGFX_DEFAULT=auto\n%s" % (family, "RUN_HISTORY=on\n" if record else ""))
    home = tempfile.mkdtemp(dir=TMP)
    if profile:
        put(os.path.join(home, ".config/steam-arm/titles.conf"), "100 %s\n" % profile)
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": "100", "T_FEXDIR": TOOL,
         "T_ARGV": json.dumps(["fex-compat-tool", "waitforexitandrun", os.path.join(game, "game.bin")]),
         "T_HANDLER": h or HANDLER, "STEAM_ARM_RENDERER_CHECK": "0", "STEAM_COMPAT_INSTALL_PATH": game}
    r = subprocess.run([sys.executable, DRV], env=e, cwd=game, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    res = json.loads([x for x in r.stdout.splitlines() if x.startswith("RESULT ")][-1][7:])
    res["log"] = r.stdout + r.stderr
    res["home"] = home
    return res


def gp(r):
    return r.get("STEAM_COMPAT_GRAPHICS_PROVIDER", "")


plain = title("plain")
java = title("java", ["jre/bin/java", "jre/lib/server/libjvm.so"])
EXTRA = MALI + "-26.2.4"

r = run(plain, "gfx=b mesa=26.2.4")
check("X1 mesa=26.2.4 without its tree: second tree, log names missing version and menu path",
      gp(r) == MALI + "/graphics_provider.json" and "Mesa 26.2.4 not installed" in r["log"]
      and "Extra versions" in r["log"], r["log"])
tree(EXTRA, "26.2.4")
r = run(plain, "gfx=b mesa=26.2.4")
check("X2 gfx=b mesa=26.2.4 with tree: provider of extra tree, graphics line names Mesa 26.2.4",
      gp(r) == EXTRA + "/graphics_provider.json" and "graphics: Mesa 26.2.4 drivers in emulation" in r["log"], r["log"])
r = run(java, "mesa=26.2.4")
check("X3 Java title (route B by rule) + mesa=26.2.4: extra tree", gp(r) == EXTRA + "/graphics_provider.json"
      and "Java title" in r["log"], r["log"])
r = run(plain, "mesa=26.2.4")
check("X4 route A title + mesa=: nothing changes, log line says not used",
      not gp(r).startswith(MALI) and "mesa=26.2.4 not used: route a" in r["log"], r["log"])
r = run(plain, "gfx=a mesa=26.2.4")
check("X5 gfx=a + mesa=: forwarding kept", not gp(r).startswith(MALI) and "not used: route a" in r["log"], r["log"])
r = run(plain, "gfx=b mesa=../x")
check("X6 bad value: second tree, log line", gp(r) == MALI + "/graphics_provider.json" and "unknown" in r["log"], r["log"])
r = run(plain, "gfx=b")
check("X7 no mesa key: second tree, no mesa line", gp(r) == MALI + "/graphics_provider.json" and "mesa:" not in r["log"], r["log"])
r = run(plain, "gfx=b mesa=26.2.4", family="other")
check("X8 other GPU family (no custom archive): route A, mesa not used",
      not gp(r).startswith(MALI) and "not used: route a" in r["log"], r["log"])
os.remove(os.path.join(EXTRA, ".steam-arm-mali"))
r = run(plain, "gfx=b mesa=26.2.4")
check("X9 extra tree without marker (incomplete): second tree", gp(r) == MALI + "/graphics_provider.json", r["log"])
tree(EXTRA, "26.2.4")
r = run(plain, "gfx=b mesa=26.2.4", record=True)
rl = os.path.join(r["home"], ".local/state/steam-arm/runs.log")
line = open(rl).read() if os.path.exists(rl) else ""
check("X10 run record: mesa=26.2.4 on extra tree", "mesa=26.2.4" in line, line or r["log"])
if HPREV:
    r = run(plain, "gfx=b mesa=26.2.4", h=HPREV)
    check("X11 2.3.2 handler ignores mesa= (second tree, no error)", gp(r) == MALI + "/graphics_provider.json", r["log"])
else:
    print("SKIP X11 2.3.2 release not available (run through run-all.sh)")
s = open(INST).read()
check("X12 handler, titles.conf header and docs name mesa=<version>",
      s.count("mesa=<version>") >= 3 and "def tree_ready(root):" in s)
print("%d failed" % len(FAILS))
sys.exit(1 if FAILS else 0)
