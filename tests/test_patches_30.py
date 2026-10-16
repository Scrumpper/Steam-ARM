#!/usr/bin/env python3
"""Steam ARM 3.0 own-patch probes (A4) and code cache narrowing (D2): steam-arm-entry.py probes, each with fixtures for
both states; handler's thunk-paths decision tied to the probe; guestos link no longer made (P13); launcher reads the
probes; handler diskcache at FEX tool 2610+. Helpers extracted from the installer under test (SARM_INST picks another
file); paths rewritten to temp copies in the extracts only. Internal; not for release zips."""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST  # noqa: E402
TMP = tempfile.mkdtemp(prefix="sarm30-patch-")
FAILS = []
PASSES = [0]
SRC = open(INST).read()


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if cond:
        PASSES[0] += 1
    else:
        FAILS.append(name)
        if detail:
            print("     ", str(detail)[:1500])


def heredoc(start, tag):
    i = SRC.find(start)
    if i < 0:
        return None
    i += len(start)
    return SRC[i:SRC.index("\n%s\n" % tag, i) + 1]


def put(path, data=b"", mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data if isinstance(data, bytes) else data.encode())
    os.chmod(path, mode)


ELF = b"\x7fELF\x02\x01\x01" + b"\0" * 57
E = heredoc("cat > /usr/local/lib/steam-arm-entry.py <<'ENTRYPY'\n", "ENTRYPY")
H = heredoc("cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n", "HANDLERPY")
check("P0 installer writes steam-arm-entry.py and handler", bool(E) and bool(H))
if not (E and H):
    print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
    sys.exit(1)

CONF = os.path.join(TMP, "steam-arm.conf")
GLXST = os.path.join(TMP, "glx-lax.state")
LINK = os.path.join(TMP, "guestos/fex-mesa")
RFSP = os.path.join(TMP, "rootfs")
ICD = os.path.join(TMP, "icd.d")
ENTRY = os.path.join(TMP, "entry.py")
put(ENTRY, E.replace('CONF = "/etc/steam-arm/steam-arm.conf"', "CONF = %r" % CONF)
    .replace('GLX_STATE = "/usr/local/lib/steam-arm-glx-lax.state"', "GLX_STATE = %r" % GLXST)
    .replace('GUESTOS = "/usr/share/guestos/fex-mesa"', "GUESTOS = %r" % LINK)
    .replace('RFS = "/opt/fex-rootfs/Ubuntu_24_04"', "RFS = %r" % RFSP)
    .replace('VK_ICD_DIR = "/usr/share/vulkan/icd.d"', "VK_ICD_DIR = %r" % ICD))
BIN = os.path.join(TMP, "bin")
os.makedirs(BIN)


def entry(*a, env=None):
    e = dict(os.environ, PATH=BIN + ":/usr/bin:/bin")
    e.update(env or {})
    r = subprocess.run([sys.executable, ENTRY] + list(a), capture_output=True, text=True, env=e)
    return r.returncode, r.stdout + r.stderr


def lines(out):
    return {m.group(1): (m.group(2), m.group(3)) for m in re.finditer(r"^patch ([\w-]+): (\w+) \((.*)\)$", out, re.M)}


S = os.path.join(TMP, "Steam")
F = os.path.join(S, "steamapps/common/FEX-Emu")
put(os.path.join(F, "toolmanifest.vdf"), '"manifest"\n{\n  "commandline" "/fex-compat-tool %verb% --"\n}\n')
put(os.path.join(F, "fex-compat-tool"), "#!/usr/bin/env python3\n", 0o755)
put(os.path.join(F, "VERSIONS.txt"), "FEX describe\tFEX-2607-76-g37265b1\n")
put(os.path.join(F, "emulator.json"), json.dumps({"emulator_v0": {"argv": "./usr/bin/FEX"}}))
put(CONF, "CLIENT=arm64\nCOMPONENTS_ON=glx-lax,vk-spoof\n")
put(GLXST, "patched\n")
# fake vulkaninfo: Mali device first (features from VK_T), then lavapipe with every feature
FEATS = ("fillModeNonSolid", "geometryShader", "multiViewport", "shaderClipDistance", "shaderCullDistance", "robustBufferAccess2")
put(os.path.join(BIN, "vulkaninfo"), "#!/bin/sh\necho call >> %s/vk-calls\ncat <<EOF\nDevices:\n\nGPU0:\n\tdeviceType = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU\n"
    "$VK_T\n\nGPU1:\n\tdeviceType = PHYSICAL_DEVICE_TYPE_CPU\n%s\nEOF\n" % (TMP, "\n".join("\t%s = true" % f for f in FEATS)), 0o755)
VK_NONE = "\n".join("\t%s = false" % f for f in FEATS)
VK_ALL = "\n".join("\t%s = true" % f for f in FEATS)
put(os.path.join(ICD, "panfrost_icd.json"), json.dumps({"ICD": {"library_path": "libvulkan_panfrost.so"}}))

rc, out = entry("patches", S, env={"VK_T": VK_NONE})
p = lines(out)
check("A1 patches: one line per own patch (8)", rc == 0 and sorted(p) == sorted(
    ["thunk-paths", "tool-edit", "server-socket", "code-cache", "glx-lax", "vk-spoof", "x86-client", "guestos-link"]), out)
check("A2 thunk-paths active on FEX-2607", p.get("thunk-paths", ("",))[0] == "active" and "FEX-2607" in p["thunk-paths"][1], out)
check("A3 tool-edit active without launch wrapper stand-in", p.get("tool-edit", ("",))[0] == "active", out)
check("A4 server-socket active, no per-game server", p.get("server-socket", ("", ""))[0] == "active"
      and "no FEX server" in p["server-socket"][1], out)
check("A5 code-cache active on FEX-2607", p.get("code-cache", ("",))[0] == "active", out)
check("A6 glx-lax active (copy patched)", p.get("glx-lax", ("",))[0] == "active", out)
check("A7 vk-spoof active, missing features named, CPU device skipped", p.get("vk-spoof", ("",))[0] == "active"
      and "geometryShader" in p["vk-spoof"][1], out)
check("A8 x86-client retired on native client", p.get("x86-client", ("",))[0] == "retired", out)
check("A9 guestos-link retired without link", p.get("guestos-link", ("",))[0] == "retired"
      and "every start" in p["guestos-link"][1], out)
check("A9 vk-spoof feature list = installer's VK_SPOOF_FEATURES",
      'VK_SPOOF_FEATURES="%s"' % " ".join(FEATS) in SRC and all('"%s"' % f in E for f in FEATS), FEATS)

# other state of every probe
put(os.path.join(F, "VERSIONS.txt"), "FEX describe\tFEX-2610\n")
put(os.path.join(F, "emulator.json"), json.dumps({"emulator_v0": {"server_argv": "./usr/bin/FEXServerManager"}}))
put(os.path.join(S, "linuxarm64/steam-launch-wrapper"), "#!/bin/sh\n# steam-arm stand-in: x\n", 0o755)
put(GLXST, "unpatched\n")
os.makedirs(os.path.dirname(LINK), exist_ok=True)
os.symlink(RFSP, LINK)
cache = os.path.join(TMP, "cache/vk-features")
rc, out = entry("patches", S, cache, env={"VK_T": VK_ALL})
p = lines(out)
check("B1 thunk-paths retired on FEX-2610", p.get("thunk-paths", ("",))[0] == "retired", out)
check("B2 tool-edit retired with stand-in", p.get("tool-edit", ("",))[0] == "retired", out)
check("B3 server-socket: per-game server named, still active (hardware check pending)",
      p.get("server-socket", ("", ""))[0] == "active" and "server_argv" in p["server-socket"][1], out)
check("B4 code-cache retired on FEX-2610 (1 GB cap)", p.get("code-cache", ("", ""))[0] == "retired" and "1 GB" in p["code-cache"][1], out)
check("B5 glx-lax retired (system GLX has no check)", p.get("glx-lax", ("",))[0] == "retired", out)
check("B6 vk-spoof retired (every feature native)", p.get("vk-spoof", ("",))[0] == "retired", out)
check("B7 guestos-link active: own link from earlier version", p.get("guestos-link", ("",))[0] == "active", out)
os.unlink(LINK)
os.symlink("/elsewhere", LINK)
os.unlink(os.path.join(TMP, "vk-calls"))
rc, out = entry("patches", S, cache, env={"VK_T": VK_NONE})
p = lines(out)
check("B8 guestos-link: other software's link left (retired)", p.get("guestos-link", ("", ""))[0] == "retired"
      and "other software" in p["guestos-link"][1], out)
check("B9 vk-spoof: cache used while driver files unchanged (no vulkaninfo run)",
      p.get("vk-spoof", ("",))[0] == "retired" and not os.path.exists(os.path.join(TMP, "vk-calls")), out)
open(os.path.join(ICD, "panfrost_icd.json"), "a").write(" ")
os.utime(os.path.join(ICD, "panfrost_icd.json"), (1, 1))
rc, out = entry("patches", S, cache, env={"VK_T": VK_NONE})
check("B9 vk-spoof: driver file changed, probe runs again", lines(out).get("vk-spoof", ("",))[0] == "active", out)
os.rename(os.path.join(BIN, "vulkaninfo"), os.path.join(BIN, "vulkaninfo.off"))
rc, out = entry("patches", S, env={"VK_T": VK_NONE, "PATH": BIN})
check("B10 vk-spoof without vulkaninfo: active, unknown", lines(out).get("vk-spoof", ("", ""))[0] == "active"
      and "unknown" in lines(out)["vk-spoof"][1], out)
os.unlink(GLXST)
rc, out = entry("patches", S)
check("B11 glx-lax without state file: active (not built yet)", lines(out).get("glx-lax", ("", ""))[0] == "active", out)
put(CONF, "CLIENT=x86\nCOMPONENTS_ON=desktop\n")
rc, out = entry("patches", S)
p = lines(out)
check("B12 x86 client: FEX tool patches off, x86-client active, components off",
      all(p.get(k, ("",))[0] == "off" for k in ("thunk-paths", "tool-edit", "server-socket", "code-cache", "glx-lax", "vk-spoof"))
      and p.get("x86-client", ("",))[0] == "active", out)
rc, out = entry("status", S)
check("B13 status (--detect) prints the patch lines", "patch thunk-paths:" in out and "handler entry:" in out, out)

# ---------------- installer wiring ----------------
check("C1 setup no longer creates the guestos link; removes its own link on upgrade",
      'ln -s "$RFS" /usr/share/guestos/fex-mesa' not in SRC
      and 'rm -f /usr/share/guestos/fex-mesa && rmdir /usr/share/guestos' in SRC)
check("C2 launcher reads probes once per start and logs them",
      'PATCHES=$(python3 /usr/local/lib/steam-arm-entry.py patches "$S"' in SRC and "retired(){" in SRC)
check("C3 launcher: retired glx-lax and vk-spoof not applied",
      "comp_on glx-lax && retired glx-lax; then\n  LAX_BAD=1" in SRC and "comp_on vk-spoof && ! retired vk-spoof" in SRC)
check("C4 glx-lax build writes its drop signal; removal lists the state file",
      'echo "$RES" > "$STATE"' in SRC and SRC.count("/usr/local/lib/steam-arm-glx-lax.state") >= 3)
check("C5 --detect: patch lines for both client types", 'steam-arm-entry.py patches "$c"' in SRC
      and 'steam-arm-entry.py status "$c"' in SRC)

# ---------------- handler: thunk-paths tied to the probe ----------------
HP = os.path.join(TMP, "handler.py")
FAKE_ENTRY = os.path.join(TMP, "fake-entry.py")
put(FAKE_ENTRY, "def probe_thunk_paths(f, client):\n    return ('retired', 'fake probe')\n")
CONF2 = os.path.join(TMP, "conf2")
put(CONF2, "GPU_FAMILY=other\n")
put(HP, H.replace('"/etc/steam-arm/steam-arm.conf"', repr(CONF2)).replace(
    'ENTRY_PY = "/usr/local/lib/steam-arm-entry.py"', "ENTRY_PY = %r" % FAKE_ENTRY))
put(os.path.join(F, "VERSIONS.txt"), "FEX describe\tFEX-2607-76-g37265b1\n")
put(os.path.join(F, "usr/share/fex-emu/ThunksDB.json"), json.dumps({"DB": {}}))
DRIVER = os.path.join(TMP, "driver.py")
put(DRIVER, r'''
import json, os, runpy, sys
sys.argv = json.loads(os.environ.pop("T_ARGV"))
try:
    runpy.run_path(os.environ.pop("T_HANDLER"), init_globals={"ENTRY": "arm64"})
except Exception as e:
    print("ERR", e)
''')
GAME = os.path.join(S, "steamapps/common/Game")
put(os.path.join(GAME, "game.bin"), ELF, 0o755)
CD = os.path.join(S, "steamapps/compatdata/100")


def hrun(home=None, extra_env=None):
    home = home or tempfile.mkdtemp(dir=TMP)
    argv = ["steam-arm-run", "/x/wrapper.real", "--", os.path.join(F, "fex-compat-tool"), "waitforexitandrun", "--",
            os.path.join(GAME, "game.bin")]
    e = {"PATH": "/usr/bin:/bin", "HOME": home, "SteamAppId": "100", "T_ARGV": json.dumps(argv), "T_HANDLER": HP,
         "STEAM_ARM_RENDERER_CHECK": "0", "STEAM_COMPAT_INSTALL_PATH": GAME, "STEAM_COMPAT_DATA_PATH": CD,
         "STEAM_COMPAT_SHADER_PATH": os.path.join(S, "steamapps/shadercache/100")}
    e.update(extra_env or {})
    r = subprocess.run([sys.executable, DRIVER], env=e, cwd=GAME, capture_output=True, text=True)
    return r.stdout + r.stderr, home


out, _ = hrun()
check("H1 handler: probe says retired, no thunk paths file even on FEX-2607 (decision follows the probe)",
      not os.path.exists(os.path.join(CD, "fex-emu/ThunksDB.json")), out[-600:])
put(FAKE_ENTRY, "def probe_thunk_paths(f, client):\n    return ('active', 'fake probe')\n")
out, _ = hrun()
check("H2 handler: probe says active, thunk paths file written",
      os.path.exists(os.path.join(CD, "fex-emu/ThunksDB.json")), out[-600:])
os.unlink(FAKE_ENTRY)
put(os.path.join(F, "VERSIONS.txt"), "FEX describe\tFEX-2609.1\n")
out, _ = hrun()
check("H3 handler: probe file unreadable, version rule (2609: retired) used and logged",
      not os.path.exists(os.path.join(CD, "fex-emu/ThunksDB.json")) and "patch probe thunk-paths not read" in out, out[-600:])

# ---------------- D2: code cache at FEX tool 2610+ ----------------
put(os.path.join(F, "VERSIONS.txt"), "FEX describe\tFEX-2610\n")
FEXC = os.path.join(S, "steamapps/shadercache/100/fex-emu")
put(os.path.join(FEXC, ".steam-arm-stamp"), "FEX-2609.1 build=unknown\n")
put(os.path.join(FEXC, "cache.bin"), b"x" * 100)


def profile_home(line):
    h = tempfile.mkdtemp(dir=TMP)
    put(os.path.join(h, ".config/steam-arm/titles.conf"), "100 %s\n" % line)
    return h


out, _ = hrun(profile_home("diskcache=on"))
check("D1 2610, diskcache=on: nothing added, logged as Valve's default",
      "diskcache=on adds nothing" in out and "DiskCache" not in out.split("fex: app config")[-1].split("\n")[0], out[-800:])
check("D2 2610: stamp compares game build only; FEX tool change keeps the cache",
      os.path.exists(os.path.join(FEXC, "cache.bin")) and open(os.path.join(FEXC, ".steam-arm-stamp")).read().strip() == "build=unknown",
      os.listdir(FEXC))
put(os.path.join(FEXC, ".steam-arm-stamp"), "build=999\n")
out, _ = hrun(profile_home("diskcache=on"))
check("D3 2610: game build changed, cache cleared with reason", not os.path.exists(os.path.join(FEXC, "cache.bin"))
      and "game build 999 -> unknown" in out, out[-600:])
out, _ = hrun(profile_home("diskcache=off"))
m = re.search(r"fex: app config \S+: (\{.*\})", out)
cfg = json.loads(m.group(1)) if m else {}
check("D4 2610, diskcache=off: per-title off switch DiskCache 0", cfg.get("Config", {}).get("DiskCache") == "0", out[-800:])
put(os.path.join(F, "VERSIONS.txt"), "FEX describe\tFEX-2609.1\n")
out, _ = hrun(profile_home("diskcache=on"))
m = re.search(r"fex: app config \S+: (\{.*\})", out)
cfg = json.loads(m.group(1)) if m else {}
check("D5 2609.1, diskcache=on: DiskCache 1 written as in 2.3", cfg.get("Config", {}).get("DiskCache") == "1", out[-800:])
check("D6 settings menu: 2610 wording (on for every game, 1 GB cap)", "fex_cache_all(){" in SRC
      and "turns code cache on for every game (1 GB cap)" in SRC)

shutil.rmtree(TMP, ignore_errors=True)
print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
