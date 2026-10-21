#!/usr/bin/env python3
"""Steam ARM 2.3 handler tests: FEX code cache per title (diskcache=on|off), version gate, launch-option precedence,
own-JIT detection, stamp guard. Handler extracted from installer under test (SARM_INST picks another installer); conf path
and second-tree root rewritten to temp copies in the extract only. Runs as Valve's FEX tool does (runpy from __main__,
g_fex_path set). Internal; not for release zips."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
PROJ = os.path.dirname(HERE)
NEW = _INST
PREV = old("2.2")
START = "cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n"
CONF_P = '"/etc/steam-arm/steam-arm.conf"'
MALI_P = 'MALI_ROOT = "/opt/fex-rootfs/Ubuntu_24_04-mali"'

DRIVER = r'''
import json, os, runpy, sys
fd = os.environ.pop("T_FEXDIR", None)
if fd:
    g_fex_path = fd
def generate_app_config():
    return {"Config": {"TSOEnabled": True}, "ThunksDB": {}}
sys.argv = json.loads(os.environ.pop("T_ARGV"))
runpy.run_path(os.environ.pop("T_HANDLER"))
out = {"argv": sys.argv, "env": {k: v for k, v in os.environ.items() if k.startswith(("FEX_", "STEAM_COMPAT_GRAPHICS"))}}
p = os.environ.get("FEX_APP_CONFIG")
if p and os.path.exists(p):
    out["app_config"] = json.load(open(p))
print("RESULT " + json.dumps(out))
'''

TMP = tempfile.mkdtemp(prefix="sarm232-h23-")
CONF = os.path.join(TMP, "steam-arm.conf")
MALI = os.path.join(TMP, "mali-tree")
os.makedirs(MALI)
open(os.path.join(MALI, ".steam-arm-mali"), "w").write("26.1.8\n")
open(os.path.join(MALI, "graphics_provider.json"), "w").write("{}\n")


def handler(src, name):
    s = open(src).read()
    i = s.index(START) + len(START)
    h = s[i:s.index("\nHANDLERPY\n", i) + 1]
    assert h.count(CONF_P) >= 2 and h.count(MALI_P) == 1, "handler layout changed"
    p = os.path.join(TMP, name)
    open(p, "w").write(h.replace(CONF_P, repr(CONF)).replace(MALI_P, "MALI_ROOT = %r" % MALI))
    return p


HANDLER = handler(NEW, "handler.py")
HPREV = handler(PREV, "handler-prev.py") if PREV else None
DRV = os.path.join(TMP, "driver.py")
open(DRV, "w").write(DRIVER)
FAILS = []
G = os.path.join(TMP, "lib", "steamapps", "common")


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[:1500])


def put(path, data=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data if isinstance(data, bytes) else data.encode())


def elf(path, bits=64):
    put(path, b"\x7fELF" + bytes([1 if bits == 32 else 2, 1, 1]) + b"\0" * 57)


def tool(ver):
    """FEX tool folder with VERSIONS.txt naming ver (None: no file)."""
    d = tempfile.mkdtemp(dir=TMP, prefix="tool-")
    if ver:
        put(os.path.join(d, "VERSIONS.txt"), "%s\n" % ver)
    return d


T2609_1 = tool("FEX-2609.1")
LIB = os.path.join(TMP, "lib")
SHADER = os.path.join(LIB, "steamapps", "shadercache", "100")


def manifest(build):
    put(os.path.join(LIB, "steamapps", "appmanifest_100.acf"),
        '"AppState"\n{\n\t"appid"\t\t"100"\n\t"buildid"\t\t"%s"\n}\n' % build)


manifest("1234")


def title(name, files=(), bits=64):
    d = os.path.join(G, name)
    elf(os.path.join(d, "game.bin"), bits)
    for f in files:
        put(os.path.join(d, f))
    return d


def run(game, profile="", fexdir=T2609_1, env=None, family="other", h=None, shader=True, drv=DRV):
    open(CONF, "w").write("GPU_FAMILY=%s\nGFX_DEFAULT=auto\n" % family)
    home = tempfile.mkdtemp(dir=TMP)
    if profile:
        put(os.path.join(home, ".config/steam-arm/titles.conf"), "100 %s\n" % profile)
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": "100",
         "T_ARGV": json.dumps(["fex-compat-tool", "waitforexitandrun", os.path.join(game, "game.bin")]),
         "T_HANDLER": h or HANDLER, "STEAM_ARM_RENDERER_CHECK": "0",
         "STEAM_COMPAT_INSTALL_PATH": game}
    if shader:
        e["STEAM_COMPAT_SHADER_PATH"] = SHADER
    if fexdir:
        e["T_FEXDIR"] = fexdir
    e.update(env or {})
    r = subprocess.run([sys.executable, drv], env=e, cwd=game, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    res = json.loads([l for l in r.stdout.splitlines() if l.startswith("RESULT ")][-1][7:])
    res["log"] = r.stdout
    c = res.get("app_config", {}).get("Config", {})
    res["dc"] = c.get("DiskCache")
    res["anon"] = c.get("DiskCacheAnonCaching")
    res["cfg"] = c
    return res


plain = title("plain")
CD = os.path.join(SHADER, "fex-emu")
STAMP = os.path.join(CD, ".steam-arm-stamp")


def rd(path):
    try:
        return open(path).read().strip()
    except OSError:
        return ""


def reset_cache():
    if os.path.islink(CD):
        os.unlink(CD)
    elif os.path.isdir(CD):
        import shutil
        shutil.rmtree(CD)


# --- (1)(2) on/off with FEX-2609.1 ---
r = run(plain, "diskcache=on")
check("C1 diskcache=on, FEX-2609.1: Config.DiskCache 1", r["dc"] == "1", r)
check("C1 tool's own keys kept (TSOEnabled)", r["cfg"].get("TSOEnabled") is True, r["cfg"])
check("C1 log: code cache on (title profile)", "fex: code cache on (title profile)" in r["log"], r["log"][-800:])
check("C1 no JIT: DiskCacheAnonCaching not set", r["dc"] == "1" and r["anon"] is None, r["cfg"])
r = run(plain, "diskcache=off")
check("C2 diskcache=off: Config.DiskCache 0", r["dc"] == "0" and "fex: code cache off (title profile)" in r["log"], r)

# --- (3)(4) version gate ---
for v in ("FEX-2607-76-gabc1234", "FEX-2609", "FEX-2609-12-gabc1234"):
    r = run(plain, "diskcache=on", fexdir=tool(v))
    shown = v.split("-g")[0].rsplit("-", 1)[0] if v.count("-") > 1 else v
    check("C3 %s: no DiskCache key, needs-tool line" % v, r["dc"] is None
          and "fex: code cache not applied: needs FEX tool FEX-2609.1 or newer (tool: %s)" % shown in r["log"], r["log"][-600:])
r = run(plain, "diskcache=on", fexdir=tool("FEX-2609.2"))
check("C4 FEX-2609.2: DiskCache 1", r["dc"] == "1", r["log"][-600:])
# 3.0 (D2): FEX tool 2610+ turns the cache on itself; diskcache=on adds nothing
for v in ("FEX-2610", "FEX-2701-3-gdeadbee"):
    r = run(plain, "diskcache=on", fexdir=tool(v))
    check("C4 %s: no DiskCache key, Valve's default named" % v, r["dc"] is None and "diskcache=on adds nothing" in r["log"],
          r["log"][-600:])
r = run(plain, "diskcache=on", fexdir=tool(None))
check("C5 no VERSIONS.txt: version unknown line, no key", r["dc"] is None
      and "fex: code cache not applied: FEX tool version unknown (no VERSIONS.txt)" in r["log"], r["log"][-600:])
put(os.path.join(T2609_1, "fex-compat-tool"), DRIVER)
r = run(plain, "diskcache=on", fexdir=None, drv=os.path.join(T2609_1, "fex-compat-tool"))
check("C5b no g_fex_path: VERSIONS.txt beside tool script (__main__) read", r["dc"] == "1", r["log"][-600:])

# --- (6)(7) launch options win ---
r = run(plain, "diskcache=on", env={"FEX_DISKCACHE": "0"})
check("C6 FEX_DISKCACHE=0 launch option: no key, kept line", r["dc"] is None
      and "launch option kept: FEX_DISKCACHE=0 (title setting diskcache=on)" in r["log"], r["log"][-600:])
uf = os.path.join(TMP, "user-fex.json")
put(uf, '{"Config": {"DiskCache": "0"}}')
before = open(uf).read()
r = run(plain, "diskcache=on", env={"FEX_APP_CONFIG": uf})
check("C7 launch FEX_APP_CONFIG DiskCache: file untouched, kept line", open(uf).read() == before
      and r["env"].get("FEX_APP_CONFIG") == uf and "launch option kept: DiskCache=0 (title setting diskcache=on)" in r["log"], r)

# --- (8) Steam's FEX setting does not block diskcache; multiblock still yields ---
r = run(plain, "diskcache=on multiblock=on", env={"STEAM_COMPAT_FEX_CONFIG": "Multiblock:0"})
check("C8 STEAM_COMPAT_FEX_CONFIG set: DiskCache still written", r["dc"] == "1", r)
check("C8 multiblock=on same line: Steam setting kept", "Steam setting kept: STEAM_COMPAT_FEX_CONFIG=Multiblock:0" in r["log"], r["log"][-600:])

# --- (9) own JIT: anon caching off ---
jits = {
    "mono": title("unity-mono", ["G_Data/Managed/Assembly-CSharp.dll", "G_Data/MonoBleedingEdge/x86_64/libmonobdwgc-2.0.so"]),
    "dotnet": title("coreclr", ["runtime/libcoreclr.so"]),
    "luajit": title("luajit", ["bin/libluajit-5.1.so.2"]),
    "cef": title("cef", ["cef/libcef.so"]),
}
for name, d in jits.items():
    r = run(d, "diskcache=on")
    check("C9 %s layout: DiskCacheAnonCaching 0, JIT named" % name, r["dc"] == "1" and r["anon"] == "0"
          and "own JIT found (%s): only file-backed code cached" % name in r["log"], r["log"][-600:])
java = title("java", ["jre/bin/java", "jre/lib/server/libjvm.so"])
r = run(java, "diskcache=on")
check("C9 bundled Java runtime: anon off, java named", r["anon"] == "0" and "own JIT found (java)" in r["log"], r["log"][-600:])
il2 = title("il2cpp", ["GameAssembly.so", "G_Data/il2cpp_data/Metadata/global-metadata.dat"])
r = run(il2, "diskcache=on")
check("C9 IL2CPP layout: no anon key", r["dc"] == "1" and r["anon"] is None, r["cfg"])
r = run(jits["mono"], "diskcache=off")
check("C9 JIT title with diskcache=off: no anon key", r["dc"] == "0" and r["anon"] is None, r["cfg"])

# --- (10) one FEX_APP_CONFIG with gfx=b, multiblock, gl32 ---
r = run(plain, "gfx=b multiblock=on diskcache=on", family="mali-csf-v10")
check("C10 gfx=b + multiblock + diskcache merged", r["dc"] == "1" and r["cfg"].get("Multiblock") == "1"
      and r.get("app_config", {}).get("ThunksDB") == {"GL": 0, "Vulkan": 0}, r.get("app_config"))
p32 = title("p32", bits=32)
r = run(p32, "gl32=off diskcache=on")
check("C10 gl32=off + diskcache merged", r["dc"] == "1" and r.get("app_config", {}).get("ThunksDB", {}).get("GL") == 0, r.get("app_config"))

# --- (11) bad value ---
r = run(plain, "diskcache=yes")
check("C11 diskcache=yes: nothing written, no code cache line", r["dc"] is None and "code cache" not in r["log"], r["log"][-600:])

# --- (12) stamp guard ---
reset_cache()
r = run(plain, "diskcache=on")
check("C12 first start: stamp written", os.path.isfile(STAMP) and rd(STAMP) == "FEX-2609.1 build=1234", r["log"][-600:])
put(os.path.join(CD, "cache.foz"), b"x" * 4096)
r = run(plain, "diskcache=on")
check("C12 same tool and build: cache file kept", os.path.isfile(os.path.join(CD, "cache.foz")) and "cleared" not in r["log"]
      and rd(STAMP) == "FEX-2609.1 build=1234", r["log"][-600:])
r = run(plain, "diskcache=on", fexdir=tool("FEX-2609.2"))
check("C12 tool changed: cache deleted, cleared line names tool change and size",
      not os.path.exists(os.path.join(CD, "cache.foz"))
      and "fex: code cache of this title cleared (FEX tool FEX-2609.1 -> FEX-2609.2; 4.0K freed)" in r["log"], r["log"][-600:])
check("C12 tool changed: new stamp", rd(STAMP) == "FEX-2609.2 build=1234", rd(STAMP))
put(os.path.join(CD, "cache.foz"), b"x")
r = run(plain, "diskcache=on", fexdir=tool("FEX-2610"))
check("C12 tool 2610 (prunes old FEX versions itself): cache kept, stamp game build only",
      os.path.isfile(os.path.join(CD, "cache.foz")) and rd(STAMP) == "build=1234" and "cleared" not in r["log"], r["log"][-600:])
put(os.path.join(CD, "cache.foz"), b"x")
manifest("1240")
r = run(plain, "diskcache=on", fexdir=tool("FEX-2610"))
check("C12 game build changed: cache deleted, cleared line names build", not os.path.exists(os.path.join(CD, "cache.foz"))
      and "game build 1234 -> 1240" in r["log"] and rd(STAMP) == "build=1240", r["log"][-600:])
manifest("1234")
os.path.exists(STAMP) and os.unlink(STAMP)
put(os.path.join(CD, "cache.foz"), b"x")
r = run(plain, "diskcache=off")
check("C12 files without stamp, diskcache=off: untouched", os.path.isfile(os.path.join(CD, "cache.foz")), r["log"][-600:])
r = run(plain, "diskcache=on", env={"FEX_DISKCACHE": "1"})
check("C12 files without stamp, FEX_DISKCACHE launch option: untouched", os.path.isfile(os.path.join(CD, "cache.foz"))
      and not os.path.exists(STAMP) and "launch option kept: FEX_DISKCACHE=1" in r["log"], r["log"][-600:])
r = run(plain, "diskcache=on")
check("C12 files without stamp, diskcache=on: cleared (no stamp)", not os.path.exists(os.path.join(CD, "cache.foz"))
      and "cleared (no stamp;" in r["log"] and os.path.isfile(STAMP), r["log"][-600:])
reset_cache()
outside = os.path.join(TMP, "outside")
put(os.path.join(outside, "keep.foz"), b"x")
os.makedirs(SHADER, exist_ok=True)
os.symlink(outside, CD)
r = run(plain, "diskcache=on", fexdir=tool("FEX-2610"))
check("C12 symlinked fex-emu: left alone with log", os.path.islink(CD) and os.path.isfile(os.path.join(outside, "keep.foz"))
      and not os.path.exists(os.path.join(outside, ".steam-arm-stamp")) and "code cache folder is a link, left alone" in r["log"], r["log"][-600:])
reset_cache()
r = run(plain, "diskcache=on", shader=False)
check("C12 no STEAM_COMPAT_SHADER_PATH: no stamp, cache still on", not os.path.exists(CD) and r["dc"] == "1"
      and "stamp not written" not in r["log"], r["log"][-600:])
os.makedirs(SHADER, exist_ok=True)
os.chmod(SHADER, 0o555)
r = run(plain, "diskcache=on")
os.chmod(SHADER, 0o755)
check("C12 unwritable cache folder: logged, cache still on", r["dc"] == "1" and "code cache stamp not written" in r["log"], r["log"][-600:])
reset_cache()
r = run(plain, "diskcache=on")
check("C12 build id from appmanifest via STEAM_COMPAT_INSTALL_PATH", rd(STAMP) == "FEX-2609.1 build=1234", rd(STAMP))
reset_cache()
r = run(plain, "diskcache=on", env={"STEAM_COMPAT_INSTALL_PATH": "/nonexistent"})
check("C12 build id from shader path when install path lacks steamapps", rd(STAMP) == "FEX-2609.1 build=1234", rd(STAMP))
os.unlink(os.path.join(LIB, "steamapps", "appmanifest_100.acf"))
reset_cache()
r = run(plain, "diskcache=on")
check("C12 no appmanifest: build=unknown", rd(STAMP) == "FEX-2609.1 build=unknown", rd(STAMP))
manifest("1234")
reset_cache()

# --- x86 client (module flag CLIENT_X86): nothing written ---
HX = os.path.join(TMP, "handler-x86.py")
_h = open(HANDLER).read()
assert _h.count("\nimport atexit\n") == 1
open(HX, "w").write(_h.replace("\nimport atexit\n", "\nimport atexit\nCLIENT_X86 = True\n"))
r = run(plain, "diskcache=on", h=HX)
check("C14 x86 client: not-applied line, no key, no stamp", r["dc"] is None and not os.path.exists(CD)
      and "fex: code cache not applied: x86 client" in r["log"], r["log"][-600:])

# --- (13) titles without key: same FEX app config as 2.2 handler, no code cache line, no stamp ---
for name, d, prof, fam in (("plain", plain, "", "other"), ("mono", jits["mono"], "", "other"),
                           ("multiblock", plain, "multiblock=off", "other"), ("gfx=b", plain, "gfx=b", "mali-csf-v10"),
                           ("gl32", p32, "gl32=off", "other"), ("java", java, "", "mali-csf-v10")):
    a = run(d, prof, family=fam)
    if not HPREV:
        print("SKIP C13 %s: 2.2 release not available (SARM_OLD)" % name)
        continue
    b = run(d, prof, family=fam, h=HPREV)
    strip = lambda x: {k: v for k, v in x.get("app_config", {}).items()}
    check("C13 no diskcache key (%s): app config as 2.2, no code cache line, no stamp" % name,
          strip(a) == strip(b) and "code cache" not in a["log"] and not os.path.exists(CD), (a.get("app_config"), b.get("app_config")))

# --- CPU drawing notice (CPU_NOTICE): renderer check with stubbed process state, notice tools stubbed ---
NDRV = os.path.join(TMP, "driver-notice.py")
open(NDRV, "w").write(r"""
import json, os, runpy, sys
sys.argv = json.loads(os.environ.pop("T_ARGV"))
g = runpy.run_path(os.environ.pop("T_HANDLER"))["renderer_watch"].__globals__
st = json.loads(os.environ.pop("T_STATE"))
g["descendants"] = lambda root: [4242]
g["gfx_state"] = lambda pid: (st[0], True, st[1], st[2], set(st[3]))
g["renderer_watch"](1, limit=30, step=0)
print("DONE")
""")
NBIN = os.path.join(TMP, "nbin")
NBIN2 = os.path.join(TMP, "nbin2")
NOTE = os.path.join(TMP, "notice-args.log")
for d, tool in ((NBIN, "gdbus"), (NBIN2, "notify-send")):
    put(os.path.join(d, tool), "#!/bin/sh\nprintf '%%s|' \"$@\" >> %s\necho >> %s\nexit 0\n" % (NOTE, NOTE))
    os.chmod(os.path.join(d, tool), 0o755)
gold = title("goldsrc")
elf(os.path.join(gold, "hl_linux"), 32)
CPU = ["hl2_linux", [], True, []]
GPU = ["hl2_linux", [], True, ["panthor renderD128"]]


def notice(conf_line, state=CPU, game=plain, binp=NBIN, bus=True, h=None):
    open(CONF, "w").write("GPU_FAMILY=other\n" + (conf_line + "\n" if conf_line else ""))
    if os.path.exists(NOTE):
        os.unlink(NOTE)
    exe = os.path.join(game, "hl_linux" if game == gold else "game.bin")
    e = {"PATH": binp if binp == NBIN2 else binp + ":/usr/bin:/bin", "HOME": tempfile.mkdtemp(dir=TMP), "SteamAppId": "100",
         "T_ARGV": json.dumps(["fex-compat-tool", "waitforexitandrun", exe]), "T_HANDLER": h or HANDLER,
         "T_STATE": json.dumps(state), "STEAM_ARM_RENDERER_CHECK": "0", "LD_PRELOAD": "/x/gameoverlayrenderer.so",
         "XDG_RUNTIME_DIR": tempfile.mkdtemp(dir=TMP)}
    if bus:
        e["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/nonexistent"
    r = subprocess.run([sys.executable, NDRV], env=e, cwd=game, capture_output=True, text=True, timeout=60)
    return r.stdout + r.stderr, rd(NOTE)


out, note = notice("CPU_NOTICE=on")
check("N1 CPU_NOTICE=on, CPU verdict: renderer line, then notice through gdbus", "DONE" in out
      and "renderer: warning: GPU forwarding not active" in out and "notice: shown" in out
      and out.index("renderer: warning") < out.index("notice: shown"), out[-800:])
check("N1 notice: summary, cause line, urgency 2 (critical), stays (timeout 0)", "|Game draws on CPU|" in note
      and "renderer:" in note and "<byte 2>" in note and note.rstrip("\n").endswith("|0|"), note)
out, note = notice("")
check("N2 key absent: no notice (off by default)", "renderer: warning" in out and note == "" and "notice:" not in out, out[-400:])
out, note = notice("CPU_NOTICE=off")
check("N3 CPU_NOTICE=off: no notice", note == "" and "notice:" not in out, out[-400:])
out, note = notice("CPU_NOTICE=on", state=GPU)
check("N4 GPU verdict: no notice", "renderer: GPU (panthor renderD128)" in out and note == "", out[-400:])
out, note = notice("CPU_NOTICE=on", game=gold)
check("N5 GoldSrc title: no notice, log names reason", note == ""
      and "notice: not shown (GoldSrc title: Software renderer is a video option)" in out, out[-400:])
out, note = notice("CPU_NOTICE=on", bus=False)
check("N6 no session bus: not shown (logged), check ends normally", note == "" and "notice: not shown (no session bus)" in out
      and "DONE" in out, out[-400:])
out, note = notice("CPU_NOTICE=on", binp=NBIN2)
check("N7 notify-send fallback (no gdbus on PATH): critical, -t 0", "-u|critical|-t|0|Game draws on CPU|" in note, note)
out, note = notice('CPU_NOTICE="on"')
check("N8 quoted value read as on", "|Game draws on CPU|" in note, out[-400:])

# FEX loader process (entry-point shell hung before title start): no CPU verdict, no notice (box bug 8)
_nd = open(NDRV).read()
assert _nd.count("limit=30, step=0") == 1
NDRV = os.path.join(TMP, "driver-notice-short.py")
open(NDRV, "w").write(_nd.replace("limit=30, step=0", "limit=1, step=0"))
out, note = notice("CPU_NOTICE=on", state=["FEX", [], True, []])
check("N9 process named FEX (title not started): no CPU verdict, no notice, not-detected line",
      "renderer: warning" not in out and note == "" and "renderer: not detected within 1 s" in out, out[-400:])
out, note = notice("CPU_NOTICE=on", state=["FEX", [], True, ["panthor renderD128"]])
check("N10 process named FEX holding GPU: GPU verdict kept", "renderer: GPU (panthor renderD128)" in out and note == "", out[-400:])

# Wine helper processes (x86 Proton): never named as title, whatever device they hold (box re-test B7)
for helper in ("explorer.exe", "services.exe", "winedevice.exe", "wineserver", "wine64-preloader", "xalia.exe"):
    out, note = notice("CPU_NOTICE=on", state=[helper, [], True, ["panthor renderD128"]])
    check("N11 Wine helper %s holding GPU: no verdict naming it, not-detected line" % helper,
          "renderer: GPU" not in out and "renderer: warning" not in out and "renderer: not detected within 1 s" in out, out[-400:])
out, note = notice("CPU_NOTICE=on", state=["Game.exe", [], True, ["panthor renderD128"]])
check("N12 Windows title process holding GPU: GPU verdict names it", "renderer: GPU (panthor renderD128)" in out
      and "process Game.exe" in out, out[-400:])

# experiment lab-cef-gpu gl: launcher's OpenGL 4.5 report for the client window is not a launch option of the game
r = run(plain, env={"STEAM_ARM_LAB_CEF_GPU": "gl", "MESA_GL_VERSION_OVERRIDE": "4.5", "MESA_GLSL_VERSION_OVERRIDE": "450"})
check("L1 lab gl session: 4.5 report dropped before rules, logged", "lab gl: OpenGL 4.5 report of client window not passed to game" in r["log"]
      and "launch option kept: MESA_GL_VERSION_OVERRIDE" not in r["log"], r["log"][-600:])
r = run(plain, env={"MESA_GL_VERSION_OVERRIDE": "4.5", "MESA_GLSL_VERSION_OVERRIDE": "450"})
check("L2 same variables without the lab: kept (launch option)", "lab gl:" not in r["log"], r["log"][-600:])
r = run(plain, env={"STEAM_ARM_LAB_CEF_GPU": "vulkan"})
check("L3 lab vulkan: nothing to drop", "lab gl:" not in r["log"], r["log"][-600:])

print("handler 2.3: %d failed" % len(FAILS))
sys.exit(1 if FAILS else 0)
