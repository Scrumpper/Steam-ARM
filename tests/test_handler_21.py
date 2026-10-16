#!/usr/bin/env python3
"""Steam ARM 2.1 handler tests: extract steam-arm-handler.py from the 2.1 and 2.0 installers, run both
on fake titles as Valve's FEX tool does (runpy from __main__), compare. Internal; not for release zips."""
import ast
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
PROJ = os.path.dirname(HERE)
NEW = _INST
OLD = old("2.0")
START = "cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n"

DRIVER = r'''
import json, os, runpy, sys
def generate_app_config():
    return {"Config": {"TSOEnabled": True}, "ThunksDB": {}}
sys.argv = json.loads(os.environ.pop("T_ARGV"))
runpy.run_path(os.environ.pop("T_HANDLER"))
out = {"argv": sys.argv, "env": {k: v for k, v in os.environ.items()
       if k.startswith(("MESA_", "LD_PRELOAD", "FEX_", "MANGOHUD", "STEAM_ARM_VK", "__GLX", "STEAM_COMPAT_GRAPHICS"))}}
p = os.environ.get("FEX_APP_CONFIG")
if p and os.path.exists(p):
    out["app_config"] = json.load(open(p))
print("RESULT " + json.dumps(out))
'''


def extract(path):
    s = open(path).read()
    i = s.index(START) + len(START)
    return s[i:s.index("\nHANDLERPY\n", i) + 1]


TMP = tempfile.mkdtemp(prefix="sarm232-test-")
HANDLERS = {}
for name, src in (("new", NEW), ("old", OLD or NEW)):
    HANDLERS[name] = os.path.join(TMP, "handler-%s.py" % name)
    open(HANDLERS[name], "w").write(extract(src))
DRV = os.path.join(TMP, "driver.py")
open(DRV, "w").write(DRIVER)
FAILS = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[:1500])


def elf(path, bits):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x7fELF" + bytes([1 if bits == 32 else 2, 1, 1]) + b"\0" * 57)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)


def run(argv, profile="", appid="100", handler="new", cwd=None, env=None, home=None, renderer=False):
    home = home or tempfile.mkdtemp(dir=TMP)
    if profile:
        write(os.path.join(home, ".config/steam-arm/titles.conf"), "%s %s\n" % (appid, profile))
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": appid,
         "T_ARGV": json.dumps(argv), "T_HANDLER": HANDLERS[handler]}
    if not renderer:
        e["STEAM_ARM_RENDERER_CHECK"] = "0"
    e.update(env or {})
    r = subprocess.run([sys.executable, DRV], env=e, cwd=cwd or home, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    res = json.loads([l for l in r.stdout.splitlines() if l.startswith("RESULT ")][-1][7:])
    res["log"] = r.stdout
    res["env"].pop("STEAM_ARM_RENDERER_CHECK", None)
    return res


TOOL = ["fex-compat-tool", "waitforexitandrun"]
G = os.path.join(TMP, "games")
plain = os.path.join(G, "plain")
elf(os.path.join(plain, "game.bin"), 64)
p32 = os.path.join(G, "p32")
elf(os.path.join(p32, "game32"), 32)
u64 = os.path.join(G, "u64")
elf(os.path.join(u64, "game.x86_64"), 64)
os.makedirs(os.path.join(u64, "game_Data/Managed"))
open(os.path.join(u64, "UnityPlayer.so"), "wb").write(b"\0" * 64 + b"force-vulkan" + b"\0" * 64)
u32 = os.path.join(G, "u32")
elf(os.path.join(u32, "game.x86"), 32)
os.makedirs(os.path.join(u32, "game_Data/Managed"))
hl = os.path.join(G, "Half-Life")
elf(os.path.join(hl, "hl_linux"), 32)
write(os.path.join(hl, "valve/liblist.gam"), 'game "Half-Life"\n')
write(os.path.join(hl, "hl.sh"), '#!/bin/bash\nGAMEROOT=$(cd "${0%/*}" && echo $PWD)\n"${GAMEROOT}"/hl_linux "$@"\n')
mod = os.path.join(G, "modonly")
elf(os.path.join(mod, "launcher"), 32)
write(os.path.join(mod, "cstrike/liblist.gam"), 'game "Mod"\n')

# --- included titles.conf: custom OpenGL engine title 248570 overlay=off (1.1 profile restored) ---
import re
_inst = open(NEW).read()
_inc = re.search(r"cat > /usr/local/share/steam-arm/titles.conf <<'TITLES'\n(.*?)\nTITLES\n", _inst, re.S).group(1) + "\n"
INC = os.path.join(TMP, "included-titles.conf")
open(INC, "w").write(_inc)
HANDLERS["inc"] = os.path.join(TMP, "handler-inc.py")
_hs = open(HANDLERS["new"]).read()
assert _hs.count('"/usr/local/share/steam-arm/titles.conf"') == 1
open(HANDLERS["inc"], "w").write(_hs.replace('"/usr/local/share/steam-arm/titles.conf"', repr(INC)))
check("included titles.conf holds 248570 overlay=off", re.search(r"(?m)^248570 overlay=off\b", _inc) is not None, _inc)
r = run(TOOL + [os.path.join(plain, "game.bin")], appid="248570", handler="inc")
check("included profile: app 248570 starts with overlay off", "overlay: off" in r["log"], r["log"][-600:])
r = run(TOOL + [os.path.join(plain, "game.bin")], appid="248571", handler="inc")
check("included profile: other app keeps x86 overlay", "overlay: off" not in r["log"] and "overlay:" in r["log"], r["log"][-600:])
r = run(TOOL + [os.path.join(plain, "game.bin")], appid="248570", handler="inc", profile="overlay=x86")
check("included profile: personal profile overrides it", "overlay: off" not in r["log"], r["log"][-600:])

# --- Proton choice: read-only check ---
VDF = '''"InstallConfigStore"
{
\t"Software"
\t{
\t\t"Valve"
\t\t{
\t\t\t"Steam"
\t\t\t{
\t\t\t\t"CompatToolMapping"
\t\t\t\t{
\t\t\t\t\t"100"
\t\t\t\t\t{
\t\t\t\t\t\t"name"\t\t"proton-stable-arm64"
\t\t\t\t\t\t"config"\t\t""
\t\t\t\t\t\t"priority"\t\t"250"
\t\t\t\t\t}
\t\t\t\t\t"200"
\t\t\t\t\t{
\t\t\t\t\t\t"name"\t\t"steamlinuxruntime"
\t\t\t\t\t\t"config"\t\t""
\t\t\t\t\t\t"priority"\t\t"250"
\t\t\t\t\t}
\t\t\t\t\t"300"
\t\t\t\t\t{
\t\t\t\t\t\t"name"\t\t""
\t\t\t\t\t\t"config"\t\t""
\t\t\t\t\t\t"priority"\t\t"250"
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t}
\t}
}
'''


def home_with_vdf():
    h = tempfile.mkdtemp(dir=TMP)
    write(os.path.join(h, ".local/share/Steam/config/config.vdf"), VDF)
    return h


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


h = home_with_vdf()
vdf = os.path.join(h, ".local/share/Steam/config/config.vdf")
before = sha(vdf)
r = run(TOOL + [os.path.join(plain, "game.bin")], appid="100", home=h)
check("compat: ARM64 Proton saved, Linux build started -> warning", "compat: warning" in r["log"]
      and "proton-stable-arm64" in r["log"], r["log"])
r = run(TOOL + [os.path.join(plain, "game.bin")], appid="200", home=h)
check("compat: Linux runtime saved -> no compat line", "compat:" not in r["log"], r["log"])
r = run(TOOL + [os.path.join(plain, "game.bin")], appid="300", home=h)
check("compat: empty tool name -> no compat line", "compat:" not in r["log"], r["log"])
r = run(TOOL + [os.path.join(plain, "game.bin")], appid="999", home=h)
check("compat: no entry -> no compat line", "compat:" not in r["log"], r["log"])
r = run(TOOL + ["/x/SteamLinuxRuntime_sniper/_v2-entry-point", "--", "/x/Proton 11.0/proton", "waitforexitandrun",
                "/g/game.exe"], appid="100", home=h)
check("compat: x86 Proton through emulation noted", "compat: x86 Proton (proton-stable-arm64)" in r["log"], r["log"])
check("compat: config.vdf never written", sha(vdf) == before)
r = run(TOOL + [os.path.join(plain, "game.bin")], appid="100")
check("compat: no config.vdf -> no compat line", "compat:" not in r["log"], r["log"])

# --- GoldSrc note ---
r = run(TOOL + ["/w/reaper", "--", os.path.join(hl, "hl.sh"), "-game", "valve"], cwd=hl)
check("goldsrc: hl.sh -> hl_linux noted", "goldsrc: OpenGL 2.1 title" in r["log"], r["log"])
r = run(TOOL + [os.path.join(mod, "launcher")], cwd=mod)
check("goldsrc: liblist.gam mod folder noted", "goldsrc:" in r["log"], r["log"])
r = run(TOOL + [os.path.join(plain, "game.bin")])
check("goldsrc: plain title not noted", "goldsrc" not in r["log"], r["log"])
r = run(TOOL + ["/w/reaper", "--", os.path.join(hl, "hl.sh"), "-vulkan"], cwd=hl)
check("goldsrc: 32-bit, -vulkan still removed", "-vulkan" not in r["argv"], r["argv"])

# --- multiblock profile key ---
r = run(TOOL + [os.path.join(plain, "game.bin")], profile="multiblock=on")
ac = r.get("app_config", {})
check("multiblock=on -> Config.Multiblock 1", ac.get("Config", {}).get("Multiblock") == "1", r)
check("multiblock=on keeps tool's own app config", ac.get("Config", {}).get("TSOEnabled") is True, ac)
r = run(TOOL + [os.path.join(p32, "game32")], profile="multiblock=off")
check("multiblock=off -> 0", r.get("app_config", {}).get("Config", {}).get("Multiblock") == "0", r)
ucfg = os.path.join(TMP, "user.json")
json.dump({"Config": {"Multiblock": "0"}}, open(ucfg, "w"))
r = run(TOOL + [os.path.join(plain, "game.bin")], profile="multiblock=on", env={"FEX_APP_CONFIG": ucfg})
check("multiblock: launch-option FEX_APP_CONFIG wins", r["env"]["FEX_APP_CONFIG"] == ucfg
      and "launch option kept: Multiblock=0" in r["log"], r)
check("multiblock: user file untouched", json.load(open(ucfg)) == {"Config": {"Multiblock": "0"}})
r = run(TOOL + [os.path.join(plain, "game.bin")], profile="multiblock=on",
        env={"STEAM_COMPAT_FEX_CONFIG": "Multiblock:0,ThunksDB_GL:1"})
check("multiblock: Steam's FEX setting wins", "FEX_APP_CONFIG" not in r["env"] and "Steam setting kept" in r["log"], r)
r = run(TOOL + [os.path.join(plain, "game.bin")], profile="multiblock=maybe")
check("multiblock: bad value ignored", "FEX_APP_CONFIG" not in r["env"], r)
r = run(TOOL + [os.path.join(p32, "game32")], profile="gl32=off multiblock=on")
ac = r.get("app_config", {})
check("multiblock + gl32=off merge in one app config", ac.get("ThunksDB", {}).get("GL") == 0
      and ac.get("Config", {}).get("Multiblock") == "1", ac)

# --- unchanged titles: 2.1 gives same argv/env as 2.0 ---
pre = {"LD_PRELOAD": "/x/ubuntu12_64/gameoverlayrenderer.so:/y/steamrtarm64/gameoverlayrenderer.so"}
cases = [
    (TOOL + [os.path.join(plain, "game.bin"), "-foo"], "", None),
    (TOOL + [os.path.join(plain, "game.bin")], "overlay=vulkan mangohud=on env=A=1 args=-a", None),
    (TOOL + [os.path.join(u64, "game.x86_64")], "", None),
    (TOOL + [os.path.join(u64, "game.x86_64")], "unity=gl", None),
    (TOOL + [os.path.join(u32, "game.x86"), "-force-vulkan"], "", None),
    (TOOL + [os.path.join(p32, "game32"), "-vulkan"], "vk32=keep", None),
    (TOOL + [os.path.join(p32, "game32")], "gl32=off", None),
    (TOOL + ["/w/reaper", "--", os.path.join(hl, "hl.sh"), "-game", "valve"], "", hl),
]
for i, (argv, prof, cwd) in enumerate(cases if OLD else []):
    a = run(argv, profile=prof, cwd=cwd, env=pre)
    b = run(argv, profile=prof, cwd=cwd, env=pre, handler="old")
    a["env"].pop("FEX_APP_CONFIG", None); b["env"].pop("FEX_APP_CONFIG", None)
    # 2.1 fix: profile MangoHud preloads libMangoHud.so (RootFS MangoHud 0.6.x has no shim)
    if "LD_PRELOAD" in b["env"]:
        b["env"]["LD_PRELOAD"] = b["env"]["LD_PRELOAD"].replace("libMangoHud_shim.so", "libMangoHud.so")
    check("unchanged title %d: same argv/env as 2.0" % i, a["argv"] == b["argv"] and a["env"] == b["env"]
          and a.get("app_config") == b.get("app_config"), (a, b))
if not OLD:
    print("SKIP unchanged titles vs 2.0: 2.0 release not available (SARM_OLD)")
r = run(TOOL + [os.path.join(plain, "game.bin")], profile="mangohud=on", env=pre)
check("mangohud=on, no RootFS copy: falls back to /usr/$LIB/mangohud/libMangoHud.so (no shim)",
      r["env"].get("LD_PRELOAD", "").endswith("/usr/$LIB/mangohud/libMangoHud.so")
      and "shim" not in r["env"].get("LD_PRELOAD", "") and r["env"].get("MANGOHUD") == "1", r)
# RootFS MangoHud copied into client folder, preloaded from there (pressure-vessel drops /usr preloads of x86 libs)
FR = os.path.join(TMP, "fakerootfs/usr/lib/%s/mangohud")
for t in ("x86_64-linux-gnu",):
    write(os.path.join(FR % t, "libMangoHud.so"), "x" * 100)
    write(os.path.join(FR % t, "libMangoHud_dlsym.so"), "y" * 10)
HANDLERS["mh"] = os.path.join(TMP, "handler-mh.py")
src = open(HANDLERS["new"]).read()
check("handler names RootFS MangoHud source", 'MH_SRC = "/opt/fex-rootfs/Ubuntu_24_04/usr/lib/%s/mangohud"' in src)
open(HANDLERS["mh"], "w").write(src.replace('"/opt/fex-rootfs/Ubuntu_24_04/usr/lib/%s/mangohud"', repr(FR)))
h = tempfile.mkdtemp(dir=TMP)
r = run(TOOL + [os.path.join(plain, "game.bin")], profile="mangohud=on", env=pre, handler="mh", home=h)
lp = r["env"].get("LD_PRELOAD", "").split(":")
check("mangohud=on: preload from client folder copy", lp[-1] == os.path.join(h, ".local/lib/steam-arm/$LIB/libMangoHud.so")
      and open(os.path.join(h, ".local/lib/steam-arm/lib/x86_64-linux-gnu/libMangoHud.so")).read() == "x" * 100, r)
check("mangohud=on: no i386 copy when RootFS has none", not os.path.exists(os.path.join(h, ".local/lib/steam-arm/lib/i386-linux-gnu")))
write(os.path.join(FR % "x86_64-linux-gnu", "libMangoHud.so"), "z" * 100)
os.utime(os.path.join(FR % "x86_64-linux-gnu", "libMangoHud.so"), (1000000, 1000000))
r = run(TOOL + [os.path.join(plain, "game.bin")], profile="mangohud=on", env=pre, handler="mh", home=h)
check("mangohud: copy refreshed when RootFS library changes",
      open(os.path.join(h, ".local/lib/steam-arm/lib/x86_64-linux-gnu/libMangoHud.so")).read() == "z" * 100)
pm = {"LD_PRELOAD": pre["LD_PRELOAD"] + ":/usr/$LIB/mangohud/libMangoHud_dlsym.so:/usr/$LIB/mangohud/libMangoHud.so"}
r = run(TOOL + [os.path.join(plain, "game.bin")], env=pm, handler="mh", home=h)
lp = r["env"].get("LD_PRELOAD", "").split(":")
check("mangohud command (--dlsym): both libraries mapped to client folder copies",
      lp[-2:] == [os.path.join(h, ".local/lib/steam-arm/$LIB/libMangoHud_dlsym.so"), os.path.join(h, ".local/lib/steam-arm/$LIB/libMangoHud.so")], r)

# --- renderer check: thread on by default, off with STEAM_ARM_RENDERER_CHECK=0 ---
src = extract(NEW)
check("renderer thread started unless STEAM_ARM_RENDERER_CHECK=0",
      'os.environ.get("STEAM_ARM_RENDERER_CHECK", "1") != "0"' in src and "threading.Thread(target=renderer_thread" in src)
r = run(TOOL + [os.path.join(plain, "game.bin")], renderer=True)
check("renderer thread does not block the handler", "RESULT" in r["log"])

# renderer functions alone (definitions only, from the handler source)
tree = ast.parse(src)
keep = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.Import, ast.ImportFrom))
        or (isinstance(n, ast.Assign) and any(getattr(t, "id", "") in ("GFX_LIB", "GUEST_MESA", "HELPER_PREFIX", "HELPER_COMM", "NON_GPU_DRM", "FEX_COMM", "_GPU_FAMILY", "PI_FAMILIES", "MALI_FAMILIES", "GPU_OUTRANK")
                                               for t in n.targets))]
ns = {}
exec(compile(ast.Module(body=keep, type_ignores=[]), "handler-defs", "exec"), ns)
LOG = []
ns["log"] = lambda *a: LOG.append(" ".join(str(x) for x in a))
V = ns["renderer_verdict"]
check("verdict: GPU device held -> GPU", V(("hl_linux", True, [], True, {"v3d renderD128"}), 1)
      == "renderer: GPU (v3d renderD128), forwarding to host driver, process hl_linux")
check("verdict: x86 Mesa, no device, 14 checks -> undecided (Mali route opens device late)",
      V(("g", True, ["libgallium-25.0.so"], False, set()), 14) is None)
v = V(("g", True, ["libgallium-25.0.so"], False, set()), 15)
check("verdict: x86 Mesa, no device, 15 checks -> CPU warning",
      v and "GPU forwarding not active: rendering on CPU (llvmpipe)" in v and "x86 Mesa inside emulation" in v, v)
check("verdict: x86 Mesa with GPU device in use -> GPU, drivers inside emulation",
      V(("exe", True, ["libgallium-26.1.8.so"], False, {"panthor renderD130"}), 3)
      == "renderer: GPU (panthor renderD130), drivers inside emulation, process exe")
check("verdict: host driver, no device, 14 checks -> undecided", V(("g", True, [], True, set()), 14) is None)
v = V(("g", True, [], True, set()), 15)
check("verdict: host driver, no device, 15 checks -> CPU warning", v and "no GPU device in use" in v, v)
# fdinfo: probed device (memory stats all zero) does not count; no stats keys counts as used
FU = ns["drm_fd_used"]
fdi = tempfile.mkdtemp(dir=TMP)
real_open = open
def fake_open(path, *a, **k):
    if path.startswith("/proc/1/fdinfo/"):
        return real_open(os.path.join(fdi, path.rsplit("/", 1)[1]), *a, **k)
    return real_open(path, *a, **k)
ns["open"] = fake_open
write(os.path.join(fdi, "3"), "pos:\t0\ndrm-driver:\tpanthor\ndrm-total-memory:\t0\ndrm-resident-memory:\t0\n")
write(os.path.join(fdi, "4"), "pos:\t0\ndrm-driver:\tpanthor\ndrm-total-memory:\t2048 KiB\ndrm-resident-memory:\t2048 KiB\n")
write(os.path.join(fdi, "5"), "pos:\t0\ndrm-driver:\tv3d\ndrm-engine-render:\t0 ns\n")
check("fdinfo: panthor fd with zero memory = probe only", FU(1, "3") is False)
check("fdinfo: panthor fd with memory = in use", FU(1, "4") is True)
check("fdinfo: driver without memory stats = in use", FU(1, "5") is True)
check("fdinfo: unreadable = in use", FU(1, "9") is True)
check("non-GPU render nodes skipped (display controller, NPU)", {"rockchip-drm", "RKNPU"} <= set(ns["NON_GPU_DRM"]))
check("verdict: no graphics library -> undecided", V(("g", False, [], False, set()), 99) is None)
m = ns["GUEST_MESA"]
check("x86 Mesa pattern: rootfs libgallium / swrast / lavapipe",
      m.search("/opt/fex-rootfs/Ubuntu_24_04/usr/lib/x86_64-linux-gnu/libgallium-25.2.8.so")
      and m.search("/usr/lib/i386-linux-gnu/dri/swrast_dri.so") and m.search("/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so")
      and not m.search("/usr/lib/aarch64-linux-gnu/libgallium-26.1.8.so"))
check("graphics library pattern: thunks and loaders",
      all(ns["GFX_LIB"].search(p) for p in ("/usr/lib/x86_64-linux-gnu/libGL.so.1", "/usr/share/fex-emu/GuestThunks/libGL-guest.so",
                                            "/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks/libvulkan-host.so",
                                            "/usr/lib/aarch64-linux-gnu/libGLX_mesa.so.0"))
      and not ns["GFX_LIB"].search("/usr/lib/libGLU.so.1x") and not ns["GFX_LIB"].search("/usr/lib/libc.so.6"))

# live: a GL process on this machine's GPU, then the same on llvmpipe
PROBE = r'''
import ctypes, sys, time
X = ctypes.CDLL("libX11.so.6"); GL = ctypes.CDLL("libGL.so.1")
X.XOpenDisplay.restype = ctypes.c_void_p; X.XOpenDisplay.argtypes = [ctypes.c_char_p]
d = X.XOpenDisplay(None)
GL.glXChooseVisual.restype = ctypes.c_void_p
GL.glXChooseVisual.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
vi = GL.glXChooseVisual(d, 0, (ctypes.c_int * 3)(4, 5, 0))
GL.glXCreateContext.restype = ctypes.c_void_p
GL.glXCreateContext.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
ctx = GL.glXCreateContext(d, vi, None, 1)
X.XDefaultRootWindow.restype = ctypes.c_ulong; X.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
X.XCreateSimpleWindow.restype = ctypes.c_ulong
X.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint,
                                  ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong]
w = X.XCreateSimpleWindow(d, X.XDefaultRootWindow(d), 0, 0, 16, 16, 0, 0, 0)
GL.glXMakeCurrent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p]
GL.glXMakeCurrent(d, w, ctx)
GL.glGetString.restype = ctypes.c_char_p
print(GL.glGetString(0x1F01).decode(), flush=True)
time.sleep(float(sys.argv[1]))
'''
if os.environ.get("DISPLAY"):
    pf = os.path.join(TMP, "probe.py")
    open(pf, "w").write(PROBE)
    game = os.path.join(TMP, "fakegame")          # own name, so the helper filter does not skip it
    shutil.copy(os.path.realpath(sys.executable), game)
    for label, extra, want in (("GPU", {}, "renderer: GPU ("), ("llvmpipe", {"LIBGL_ALWAYS_SOFTWARE": "1"},
                                                                 "GPU forwarding not active: rendering on CPU (llvmpipe)")):
        LOG.clear()
        p = subprocess.Popen([game, pf, "8"], env=dict(os.environ, **extra), stdout=subprocess.PIPE, text=True)
        rend = p.stdout.readline().strip()
        t = time.time()
        ns["renderer_watch"](os.getpid(), limit=6, step=0.3)
        p.wait()
        check("live %s (%s): %s" % (label, rend, LOG[-1] if LOG else "-"), LOG and want in LOG[-1]
              and "process fakegame" in LOG[-1], LOG)
    # integration as Valve's tool runs it: stdout to log file, runpy handler, then subprocess.call the game
    TOOLSIM = r'''
import os, runpy, subprocess, sys
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND)
os.dup2(fd, 1); os.dup2(fd, 2)
sys.argv = ["fex-compat-tool", "waitforexitandrun", "--", sys.argv[2]]
runpy.run_path(os.environ["T_HANDLER"])
print("fex compat fixups", flush=True)
subprocess.call([os.environ["T_GAME"], os.environ["T_PROBE"], "9"], stdout=subprocess.DEVNULL)
'''
    ts = os.path.join(TMP, "toolsim.py")
    open(ts, "w").write(TOOLSIM)
    logf = os.path.join(TMP, "fex-compat-tool-sim.log")
    e = dict(os.environ, T_HANDLER=HANDLERS["new"], T_GAME=game, T_PROBE=pf, SteamAppId="70", HOME=tempfile.mkdtemp(dir=TMP))
    e.pop("STEAM_ARM_RENDERER_CHECK", None)
    subprocess.run([sys.executable, ts, logf, os.path.join(plain, "game.bin")], env=e, timeout=60)
    txt = open(logf).read()
    check("integration (runpy + subprocess.call): renderer line in tool log",
          "steam-arm: renderer: GPU (" in txt and "process fakegame" in txt, txt[-800:])
else:
    print("SKIP live renderer checks (no DISPLAY)")

shutil.rmtree(TMP, ignore_errors=True)
print("\n%d failed" % len(FAILS) if FAILS else "\nall passed")
sys.exit(1 if FAILS else 0)
