#!/usr/bin/env python3
"""Steam ARM 2.2 handler rule fixtures (outline 2a item 21): expected argv/env/route per title kind and GPU family.
Java LWJGL 2/3 with Java 17/21, 32-bit -vulkan per family, Unity GL 4.5 / Vulkan / Unity 4. Handler extracted from
2.3-work installer; its conf path and second-tree root rewritten to temp copies in the extract only. Internal."""
import json
import os
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
NEW = _INST
START = "cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n"
CONF_P = '"/etc/steam-arm/steam-arm.conf"'
MALI_P = 'MALI_ROOT = "/opt/fex-rootfs/Ubuntu_24_04-mali"'

DRIVER = r'''
import json, os, runpy, sys
def generate_app_config():
    return {"Config": {"TSOEnabled": True}, "ThunksDB": {}}
sys.argv = json.loads(os.environ.pop("T_ARGV"))
runpy.run_path(os.environ.pop("T_HANDLER"), init_globals={"CLIENT_X86": True} if os.environ.pop("T_X86", "") else None)
out = {"argv": sys.argv, "env": {k: v for k, v in os.environ.items()
       if k.startswith(("MESA_", "JAVA_TOOL", "STEAM_COMPAT_GRAPHICS", "__GLX"))}}
p = os.environ.get("FEX_APP_CONFIG")
if p and os.path.exists(p):
    out["app_config"] = json.load(open(p))
print("RESULT " + json.dumps(out))
'''

TMP = tempfile.mkdtemp(prefix="sarm232-hfix-")
CONF = os.path.join(TMP, "steam-arm.conf")
MALI = os.path.join(TMP, "mali-tree")
os.makedirs(MALI)
open(os.path.join(MALI, ".steam-arm-mali"), "w").write("26.1.8\n")
open(os.path.join(MALI, "graphics_provider.json"), "w").write("{}\n")
src = open(NEW).read()
i = src.index(START) + len(START)
h = src[i:src.index("\nHANDLERPY\n", i) + 1]
assert h.count(CONF_P) >= 2 and h.count(MALI_P) == 1, "handler layout changed"
HANDLER = os.path.join(TMP, "handler.py")
open(HANDLER, "w").write(h.replace(CONF_P, repr(CONF)).replace(MALI_P, "MALI_ROOT = %r" % MALI))
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


def put(path, data=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data if isinstance(data, bytes) else data.encode())


def elf(path, bits):
    put(path, b"\x7fELF" + bytes([1 if bits == 32 else 2, 1, 1]) + b"\0" * 57)


def java_title(name, major, lwjgl):
    """Title folder with bundled jre/ (release file) and LWJGL 2 (Display.class jar) or 3 (liblwjgl.so)."""
    d = os.path.join(G, name)
    elf(os.path.join(d, "jre/bin/java"), 64)
    put(os.path.join(d, "jre/release"), 'JAVA_VERSION="%s"\n' % ("1.8.0_202" if major == 8 else "%d.0.2" % major))
    os.makedirs(os.path.join(d, "lib"), exist_ok=True)
    with zipfile.ZipFile(os.path.join(d, "lib", "lwjgl.jar"), "w") as z:
        z.writestr("org/lwjgl/opengl/Display.class" if lwjgl == 2 else "org/lwjgl/opengl/GL.class", b"\xca\xfe")
    put(os.path.join(d, "natives", "liblwjgl64.so" if lwjgl == 2 else "liblwjgl.so"))
    return d


def run(argv, family=None, gfx_default="auto", cwd=None, profile="", env=None, x86=False):
    open(CONF, "w").write("GPU_FAMILY=%s\nGFX_DEFAULT=%s\n" % (family, gfx_default))
    home = tempfile.mkdtemp(dir=TMP)
    if profile:
        put(os.path.join(home, ".config/steam-arm/titles.conf"), "100 %s\n" % profile)
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": "100",
         "T_ARGV": json.dumps(argv), "T_HANDLER": HANDLER, "STEAM_ARM_RENDERER_CHECK": "0"}
    e.update(env or {})
    if x86:
        e["T_X86"] = "1"
    r = subprocess.run([sys.executable, DRV], env=e, cwd=cwd or home, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    res = json.loads([l for l in r.stdout.splitlines() if l.startswith("RESULT ")][-1][7:])
    res["log"] = r.stdout
    res["mb"] = res.get("app_config", {}).get("Config", {}).get("Multiblock")
    res["thunks"] = res.get("app_config", {}).get("ThunksDB", {})
    return res


def route_b(r):
    return r["env"].get("STEAM_COMPAT_GRAPHICS_PROVIDER") == MALI + "/graphics_provider.json" \
        and r["env"].get("__GLX_VENDOR_LIBRARY_NAME") == "mesa" and r["thunks"] == {"GL": 0, "Vulkan": 0}


def route_a(r):
    return "STEAM_COMPAT_GRAPHICS_PROVIDER" not in r["env"] and "graphics: forwarding" in r["log"]


XR = "-DLWJGL_DISABLE_XRANDR=true"

# --- Java: LWJGL 2 / 3, Java 8 / 17 / 21, Mali and other GPU ---
j2_17 = java_title("j2-17", 17, 2)
j3_17 = java_title("j3-17", 17, 3)
j2_21 = java_title("j2-21", 21, 2)
j3_21 = java_title("j3-21", 21, 3)
j2_8 = java_title("j2-8", 8, 2)
java = lambda d: TOOL + [os.path.join(d, "jre/bin/java"), "-jar", "game.jar"]

r = run(java(j2_17), cwd=j2_17, family="mali-csf-v10")
check("java 17 LWJGL 2 on mali-csf-v10: route b (Java title)", route_b(r) and "(Java title)" in r["log"], r)
check("java 17 LWJGL 2: XRandR off in JAVA_TOOL_OPTIONS", r["env"].get("JAVA_TOOL_OPTIONS") == XR, r["env"])
check("java 17: Multiblock left to tool (no key)", r["mb"] is None, r.get("app_config"))
check("java 17: version logged", "version 17" in r["log"], r["log"])
r = run(java(j3_17), cwd=j3_17, family="mali-csf-v10")
check("java 17 LWJGL 3: route b, no XRandR option", route_b(r) and "JAVA_TOOL_OPTIONS" not in r["env"], r)
r = run(java(j3_21), cwd=j3_21, family="mali-csf-v10")
check("java 21 LWJGL 3: route b, Multiblock 0", route_b(r) and r["mb"] == "0" and "java: 21 or newer, FEX Multiblock off" in r["log"], r)
check("java 21 LWJGL 3: no XRandR option", "JAVA_TOOL_OPTIONS" not in r["env"], r["env"])
r = run(java(j2_21), cwd=j2_21, family="mali-valhall-jm")
check("java 21 LWJGL 2 on mali-valhall-jm: route b, Multiblock 0, XRandR off",
      route_b(r) and r["mb"] == "0" and r["env"].get("JAVA_TOOL_OPTIONS") == XR, r)
r = run(java(j2_8), cwd=j2_8, family="mali-csf-v10")
check("java 8 (1.8.0 release string): version 8, Multiblock untouched", "version 8" in r["log"] and r["mb"] is None, r)
r = run(java(j3_21), cwd=j3_21, family="broadcom-v3d71")
check("java 21 on broadcom-v3d71: forwarding, reason names family", route_a(r) and "GPU family broadcom-v3d71" in r["log"], r["log"])
check("java 21 on broadcom-v3d71: no Multiblock change (route a)", r["mb"] is None, r.get("app_config"))
r = run(java(j2_17), cwd=j2_17, family="broadcom-v3d71")
check("java LWJGL 2 on broadcom-v3d71: XRandR off still applied", r["env"].get("JAVA_TOOL_OPTIONS") == XR, r["env"])
r = run(java(j2_17), cwd=j2_17, family="mali-csf-v10", env={"JAVA_TOOL_OPTIONS": "-DLWJGL_DISABLE_XRANDR=false"})
check("java: launch-option LWJGL_DISABLE_XRANDR kept", r["env"]["JAVA_TOOL_OPTIONS"] == "-DLWJGL_DISABLE_XRANDR=false"
      and "launch option kept: JAVA_TOOL_OPTIONS" in r["log"], r)
put(os.path.join(TMP, "user-fex.json"), '{"Config": {"Multiblock": "1"}}')
r = run(java(j3_21), cwd=j3_21, family="mali-csf-v10", env={"FEX_APP_CONFIG": os.path.join(TMP, "user-fex.json")})
check("java 21: launch-option Multiblock kept", r["mb"] == "1" and "launch option kept: Multiblock=1" in r["log"], r)
r = run(java(j3_21), cwd=j3_21, family="mali-csf-v10", gfx_default="a")
check("java 21 with GFX_DEFAULT=a: forwarding", route_a(r) and "GFX_DEFAULT=a" in r["log"], r["log"])
r = run(java(j3_21), cwd=j3_21, family="mali-csf-v10", profile="gfx=a")
check("java 21 with profile gfx=a: forwarding, rule logged", route_a(r) and "title setting kept: gfx=a" in r["log"], r["log"])

# --- 32-bit -vulkan per family ---
p32 = os.path.join(G, "p32")
elf(os.path.join(p32, "game32"), 32)
v32 = TOOL + [os.path.join(p32, "game32"), "-vulkan"]
r = run(v32, "mali-csf-v10")
check("32-bit -vulkan on mali-csf-v10: route b, -vulkan kept", route_b(r) and "-vulkan" in r["argv"] and "(32-bit Vulkan)" in r["log"], r)
for fam in ("mali-csf-5thgen", "mali-csf-v11", "mali-valhall-jm"):
    r = run(v32, fam)
    check("32-bit -vulkan on %s: forwarding, -vulkan removed" % fam,
          route_a(r) and "-vulkan" not in r["argv"] and "no default Vulkan driver on GPU family %s" % fam in r["log"], r["log"])
r = run(v32, "broadcom-v3d71")
check("32-bit -vulkan on broadcom-v3d71: forwarding, -vulkan removed, reason names family",
      route_a(r) and "-vulkan" not in r["argv"] and "GPU family broadcom-v3d71" in r["log"], r["log"])
r = run(v32, "broadcom-v3d71", profile="vk32=keep")
check("32-bit -vulkan with vk32=keep on broadcom-v3d71: kept", "-vulkan" in r["argv"], r["argv"])
r = run(TOOL + [os.path.join(p32, "game32"), "-force-vulkan"], "mali-csf-v10")
check("32-bit -force-vulkan on mali-csf-v10: route b", route_b(r) and "-force-vulkan" in r["argv"], r)
r = run(TOOL + [os.path.join(p32, "game32")], "mali-csf-v10")
check("32-bit without -vulkan on mali-csf-v10: forwarding, no reason", route_a(r) and "graphics: forwarding\n" in r["log"] + "\n", r["log"])
p64 = os.path.join(G, "p64")
elf(os.path.join(p64, "game64"), 64)
r = run(TOOL + [os.path.join(p64, "game64"), "-vulkan"], "mali-csf-v10")
check("64-bit -vulkan on mali-csf-v10: forwarding, -vulkan kept", route_a(r) and "-vulkan" in r["argv"], r)

# --- Unity ---
def unity(name, bits, vulkan=False, legacy=False):
    d = os.path.join(G, name)
    exe = os.path.join(d, "game." + ("x86_64" if bits == 64 else "x86"))
    elf(exe, bits)
    os.makedirs(os.path.join(d, "game_Data", "Managed"))
    if legacy:
        put(os.path.join(d, "game_Data", "mainData"))
    if bits == 64:
        put(os.path.join(d, "UnityPlayer.so"), b"\0" * 64 + (b"force-vulkan" if vulkan else b"force-glcore") + b"\0" * 64)
    return exe


ugl = unity("u-gl", 64)
uvk = unity("u-vk", 64, vulkan=True)
u4 = unity("u4", 64, legacy=True)
u32 = unity("u32", 32)
r = run(TOOL + [ugl], "mali-csf-v10")
check("unity 64 GL: GL 4.5 / GLSL 450 report", r["env"].get("MESA_GL_VERSION_OVERRIDE") == "4.5"
      and r["env"].get("MESA_GLSL_VERSION_OVERRIDE") == "450" and "unity: OpenGL core, GL 4.5 report" in r["log"], r)
check("unity 64 GL: no -force-vulkan added", "-force-vulkan" not in r["argv"], r["argv"])
r = run(TOOL + [ugl], "broadcom-v3d71")
check("unity 64 GL on broadcom-v3d71: GL 4.5 report too", r["env"].get("MESA_GL_VERSION_OVERRIDE") == "4.5", r["env"])
r = run(TOOL + [ugl], "mali-csf-v10", env={"MESA_GL_VERSION_OVERRIDE": "4.6"})
check("unity 64 GL: launch-option GL version kept", r["env"]["MESA_GL_VERSION_OVERRIDE"] == "4.6"
      and "unity: OpenGL core, GL 4.6 report" in r["log"], r)
r = run(TOOL + [uvk], "mali-csf-v10")
check("unity 64 Vulkan player: -force-vulkan, overlay vulkan, no GL report", r["argv"][-1] == "-force-vulkan"
      and "overlay: vulkan" in r["log"] and "MESA_GL_VERSION_OVERRIDE" not in r["env"], r)
r = run(TOOL + [uvk], "mali-csf-v10", profile="unity=gl")
check("unity 64 Vulkan player with unity=gl: GL 4.5 report, no -force-vulkan",
      "-force-vulkan" not in r["argv"] and r["env"].get("MESA_GL_VERSION_OVERRIDE") == "4.5", r)
r = run(TOOL + [uvk, "-force-glcore"], "mali-csf-v10")
check("unity 64 Vulkan player with -force-glcore: kept, logged", "-force-vulkan" not in r["argv"]
      and "launch option kept: -force-glcore" in r["log"], r["log"])
r = run(TOOL + [u4], "mali-csf-v10")
check("unity 4 (mainData): no GL report", "MESA_GL_VERSION_OVERRIDE" not in r["env"] and "unity:" not in r["log"], r)
r = run(TOOL + [u32], "mali-csf-v10")
check("unity 32: overlay off, GL 4.5 report", "overlay: off" in r["log"] and r["env"].get("MESA_GL_VERSION_OVERRIDE") == "4.5", r)

# --- x86 client (handler entered through steam-arm-run.py with CLIENT_X86) ---
r = run(java(j2_17), cwd=j2_17, family="mali-csf-v10", x86=True)
check("x86 client: Java title on mali-csf-v10 -> forwarding, reason logged", route_a(r)
      and "graphics: x86 client: Mali drivers inside the emulation not wired; forwarding (Java title)" in r["log"], r["log"])
check("x86 client: Java XRandR rule still applied", r["env"].get("JAVA_TOOL_OPTIONS") == XR, r["env"])
r = run(TOOL + [ugl], "mali-csf-v10", profile="gfx=b", x86=True)
check("x86 client: profile gfx=b -> forwarding", route_a(r) and "x86 client: Mali drivers inside the emulation not wired" in r["log"], r["log"])
r = run(TOOL + [ugl], "mali-csf-v10", gfx_default="b", x86=True)
check("x86 client: GFX_DEFAULT=b -> forwarding", route_a(r), r["log"])
PROTON = TOOL + ["/s/steamapps/common/Proton - Experimental/proton", "waitforexitandrun", "/g/game.exe"]
r = run(PROTON, "mali-csf-v10", x86=True)
check("x86 client: x86 Proton log names x86 client, no ARM64 Proton hint", "compat: x86 Proton through emulation (x86 client)" in r["log"]
      and "ARM64 Proton builds" not in r["log"], r["log"])
r = run(PROTON, "mali-csf-v10")
check("native client: x86 Proton log keeps ARM64 Proton hint", "ARM64 Proton builds run without x86 emulation" in r["log"], r["log"])
r = run(java(j2_17), cwd=j2_17, family="mali-csf-v10")
check("native client: Java title still on route b", route_b(r), r["log"])

import shutil
shutil.rmtree(TMP, ignore_errors=True)
print("%d FAIL" % len(FAILS) if FAILS else "all PASS")
sys.exit(1 if FAILS else 0)
