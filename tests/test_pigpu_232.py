#!/usr/bin/env python3
"""Steam ARM 2.3.2 Raspberry Pi GPU tests. GPU family stubbed through GPU_FAMILY of a temp settings file
(broadcom-v3d71, broadcom-v3d42, broadcom-vc4, mali-csf-v10). Handler: x86 Proton WineD3D default, d3d=dxvk opt-out,
launch-option and launcher-default precedence, glver and gl=zink env, rule precedence, other families unchanged, CPU
drawing hint. Launcher: WineD3D default and PROTON_DXVK_D3D8 by family, launch options sync before client start.
steam-arm-launchopts.py: titles.conf parsing, launch options composed into fixture localconfig.vdf files, idempotent
sync, own launch options kept, restore, other family, client running, odd layout. Removal restores launch options.
Helpers extracted from installer under test (SARM_INST picks another installer). Internal; not for release zips."""
import json
import os
import re
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
TMP = tempfile.mkdtemp(prefix="sarm232-pi-")
CONF = os.path.join(TMP, "steam-arm.conf")
FAILS = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[:1500])


def heredoc(start, end):
    i = SRC.find(start)
    if i < 0:
        return None
    i += len(start)
    return SRC[i:SRC.index("\n%s\n" % end, i) + 1]


def put(path, data=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(data)


# ---------------- handler ----------------
H = heredoc("cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n", "HANDLERPY")
HANDLER = os.path.join(TMP, "handler.py")
open(HANDLER, "w").write(H.replace('"/etc/steam-arm/steam-arm.conf"', repr(CONF)))
DRIVER = r'''
import json, os, runpy, sys
sys.argv = json.loads(os.environ.pop("T_ARGV"))
g = runpy.run_path(os.environ.pop("T_HANDLER"))
hint = g["pi_hint"]() if "pi_hint" in g else None
keys = ("PROTON_", "MESA_", "GALLIUM_DRIVER")
print("RESULT " + json.dumps({"env": {k: v for k, v in os.environ.items() if k.startswith(keys)}, "hint": hint}))
'''
DRV = os.path.join(TMP, "driver.py")
open(DRV, "w").write(DRIVER)
G = os.path.join(TMP, "games")


def elf(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(b"\x7fELF\x02\x01\x01" + b"\0" * 57)


elf(os.path.join(G, "plain", "game.bin"))
elf(os.path.join(G, "unity", "game.bin"))
os.makedirs(os.path.join(G, "unity", "game_Data", "Managed"))
put(os.path.join(G, "unity", "UnityPlayer.so"), "x")
PROTON = os.path.join(TMP, "proton", "proton")
put(PROTON, "#!/usr/bin/env python3\n")
put(os.path.join(G, "win", "game.exe"), "MZ")


def run(family, profile="", env=None, proton=False, game="plain"):
    open(CONF, "w").write("GPU_FAMILY=%s\nGFX_DEFAULT=auto\n" % family)
    home = tempfile.mkdtemp(dir=TMP)
    if profile:
        put(os.path.join(home, ".config/steam-arm/titles.conf"), "100 %s\n" % profile)
    d = os.path.join(G, "win" if proton else game)
    argv = (["fex-compat-tool", "waitforexitandrun", PROTON, "waitforexitandrun", os.path.join(d, "game.exe")] if proton
            else ["fex-compat-tool", "waitforexitandrun", os.path.join(d, "game.bin")])
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": "100",
         "T_ARGV": json.dumps(argv), "T_HANDLER": HANDLER, "STEAM_ARM_RENDERER_CHECK": "0",
         "STEAM_COMPAT_INSTALL_PATH": d}
    e.update(env or {})
    r = subprocess.run([sys.executable, DRV], env=e, cwd=d, capture_output=True, text=True)
    if r.returncode:
        return {"env": {}, "log": r.stdout + r.stderr, "hint": None}
    res = json.loads([l for l in r.stdout.splitlines() if l.startswith("RESULT ")][-1][7:])
    res["log"] = r.stdout
    return res


PI = ("broadcom-v3d71", "broadcom-v3d42", "broadcom-vc4")
LDEF = {"PROTON_USE_WINED3D": "1", "STEAM_ARM_D3D_DEFAULT": "wined3d"}
for fam in PI:
    r = run(fam, proton=True)
    check("H1 %s, x86 Proton, no setting: PROTON_USE_WINED3D=1, logged" % fam,
          r["env"].get("PROTON_USE_WINED3D") == "1" and "d3d: WineD3D (OpenGL): Raspberry Pi GPU" in r["log"], r)
    r = run(fam, "d3d=dxvk", proton=True, env=LDEF)
    check("H2 %s, d3d=dxvk: refused, WineD3D kept, five missing features named (3.1)" % fam,
          r["env"].get("PROTON_USE_WINED3D") == "1"
          and "d3d: WineD3D kept (title setting d3d=dxvk not applied): DXVK needs shaderInt64, robustBufferAccess2, textureCompressionBC, multiViewport, tessellationShader; V3DV reports none" in r["log"], r)
r = run("broadcom-v3d42", "d3d=dxvk", proton=True, env={"PROTON_USE_WINED3D": "0"})
check("H2b d3d=dxvk with own launch option PROTON_USE_WINED3D=0: refusal logged, launch option kept",
      r["env"].get("PROTON_USE_WINED3D") == "0" and "launch option kept: PROTON_USE_WINED3D=0 (title setting d3d=dxvk)" in r["log"] and "not applied" in r["log"], r)
r = run("mali-csf-v10", "d3d=dxvk", proton=True)
check("H2c Mali: d3d key not applied there, no DXVK refusal text", "DXVK needs" not in r["log"] and "PROTON_USE_WINED3D" not in r["env"], r)
for fam in ("mali-csf-v10", "other"):
    r = run(fam, proton=True, env={"PROTON_DXVK_D3D8": "1"})
    check("H3 %s, x86 Proton: no WineD3D, PROTON_DXVK_D3D8 kept, no d3d line" % fam,
          "PROTON_USE_WINED3D" not in r["env"] and r["env"].get("PROTON_DXVK_D3D8") == "1" and "d3d:" not in r["log"], r)
r = run("mali-csf-v10", "d3d=wined3d glver=3.3 gl=zink", proton=True)
check("H3 Mali with Pi settings: nothing set, logged as Raspberry Pi GPU only",
      not r["env"] and "not applied: Raspberry Pi GPU only (GPU family mali-csf-v10)" in r["log"], r)
r = run("broadcom-v3d71", proton=True, env={"PROTON_USE_WINED3D": "0"})
check("H4 own launch option PROTON_USE_WINED3D=0 kept over Pi default, logged",
      r["env"].get("PROTON_USE_WINED3D") == "0" and "launch option kept: PROTON_USE_WINED3D=0 (title setting d3d=wined3d)" in r["log"], r)
r = run("broadcom-v3d71", "d3d=wined3d", proton=True,
        env={"PROTON_USE_WINED3D": "0", "STEAM_ARM_LAUNCHOPTS": "PROTON_USE_WINED3D"})
check("H5 launch option from earlier title setting (STEAM_ARM_LAUNCHOPTS): current setting wins",
      r["env"].get("PROTON_USE_WINED3D") == "1" and "launch option kept" not in r["log"], r)
r = run("broadcom-v3d71", "d3d=wined3d", proton=True,
        env={"PROTON_USE_WINED3D": "0", "STEAM_ARM_LAUNCHOPTS": "+PROTON_USE_WINED3D"})
check("H5 marker with %command% flag (+names): names still read as title settings",
      r["env"].get("PROTON_USE_WINED3D") == "1" and "launch option kept" not in r["log"], r)
r = run("broadcom-v3d71", "d3d=vulkan", proton=True)
check("H6 unknown d3d value: logged, WineD3D default", r["env"].get("PROTON_USE_WINED3D") == "1"
      and "title setting d3d=vulkan unknown" in r["log"], r)
r = run("broadcom-v3d71")
check("H7 Linux title, no setting: no Proton or Mesa variables", not r["env"], r)
for v, glsl in (("3.2", "150"), ("3.3", "330"), ("4.5", "450")):
    r = run("broadcom-v3d42", "glver=" + v)
    check("H8 glver=%s: GL/GLSL pair %s/%s, logged" % (v, v, glsl),
          r["env"].get("MESA_GL_VERSION_OVERRIDE") == v and r["env"].get("MESA_GLSL_VERSION_OVERRIDE") == glsl
          and "pi gpu: GL %s report, GLSL %s (title setting glver)" % (v, glsl) in r["log"], r)
r = run("broadcom-v3d71", "glver=3.1x")
check("H9 unknown glver: logged, nothing set", not r["env"] and "title setting glver=3.1x unknown" in r["log"], r)
r = run("broadcom-v3d71", "gl=zink")
check("H10 gl=zink: MESA_LOADER_DRIVER_OVERRIDE and GALLIUM_DRIVER zink, logged experimental",
      r["env"].get("MESA_LOADER_DRIVER_OVERRIDE") == "zink" and r["env"].get("GALLIUM_DRIVER") == "zink"
      and "OpenGL through Zink (title setting gl=zink), experimental" in r["log"], r)
r = run("broadcom-v3d71", "glver=3.3", proton=True)
check("H11 x86 Proton with glver: WineD3D and GL pair both set",
      r["env"].get("PROTON_USE_WINED3D") == "1" and r["env"].get("MESA_GL_VERSION_OVERRIDE") == "3.3", r)
r = run("broadcom-v3d71", "glver=3.3", env={"MESA_GL_VERSION_OVERRIDE": "3.2", "MESA_GLSL_VERSION_OVERRIDE": "150"})
check("H12 own launch option GL pair kept over glver, logged",
      r["env"].get("MESA_GL_VERSION_OVERRIDE") == "3.2" and r["env"].get("MESA_GLSL_VERSION_OVERRIDE") == "150"
      and "launch option kept: MESA_GL_VERSION_OVERRIDE=3.2 MESA_GLSL_VERSION_OVERRIDE=150 (title setting glver=3.3)" in r["log"], r)
r = run("broadcom-v3d71", "glver=3.3", env={"MESA_GL_VERSION_OVERRIDE": "3.2"})
check("H12 own launch option sets GL version only: GLSL not added from glver (pair stays the account's)",
      r["env"].get("MESA_GL_VERSION_OVERRIDE") == "3.2" and "MESA_GLSL_VERSION_OVERRIDE" not in r["env"], r)
r = run("broadcom-v3d71", "glver=3.3", game="unity")
check("H13 Unity rule (GL 4.5 report) under glver=3.3: title setting wins, logged",
      r["env"].get("MESA_GL_VERSION_OVERRIDE") == "3.3" and r["env"].get("MESA_GLSL_VERSION_OVERRIDE") == "330"
      and "title setting kept: glver=3.3 (rule wanted MESA_GL_VERSION_OVERRIDE=4.5)" in r["log"], r)
r = run("mali-csf-v10", game="unity")
check("H13 Mali Unity rule unchanged: GL 4.5 report", r["env"].get("MESA_GL_VERSION_OVERRIDE") == "4.5", r)
r = run("broadcom-v3d71")
check("H14 CPU drawing hint on Pi GPU without glver names OpenGL version 3.3 and menu path",
      r["hint"] and "Try OpenGL version 3.3 for this game" in r["hint"] and "Graphics, Route per game" in r["hint"], r)
r = run("broadcom-v3d71", "glver=3.3")
check("H14 no hint once glver is set", r["hint"] is None, r)
r = run("mali-csf-v10")
check("H14 no hint on Mali", r["hint"] is None, r)
check("H15 renderer CPU verdict logs the hint and notice carries it",
      'log("renderer: " + pi)' in H and '+ (" " + pi if pi else "")' in H)

# ---------------- launcher ----------------
L = heredoc("cat > /usr/local/bin/steam-arm <<'LAUNCHER'\n", "LAUNCHER") or ""
m = re.search(r'case "\$\{GPU_FAMILY:-\}" in\n  # Raspberry Pi GPU.*?\nesac\n', L, re.S)
check("E0 launcher: family case for Proton defaults present", m, "")


def launch_env(family, extra=None):
    if not m:
        return {}
    sh = 'LOG=%s/l.log; GPU_FAMILY=%s\n%s\nenv\n' % (TMP, family, m.group(0))
    e = {"PATH": "/usr/bin:/bin"}
    e.update(extra or {})
    out = subprocess.run(["sh", "-c", sh], env=e, capture_output=True, text=True).stdout
    return dict(l.split("=", 1) for l in out.splitlines() if "=" in l)


for fam in PI:
    e = launch_env(fam)
    check("E1 %s: launcher exports PROTON_USE_WINED3D=1 with its marker, no PROTON_DXVK_D3D8" % fam,
          e.get("PROTON_USE_WINED3D") == "1" and e.get("STEAM_ARM_D3D_DEFAULT") == "wined3d" and "PROTON_DXVK_D3D8" not in e, e)
e = launch_env("broadcom-v3d71", {"PROTON_USE_WINED3D": "0"})
check("E2 own PROTON_USE_WINED3D=0 kept, no marker", e.get("PROTON_USE_WINED3D") == "0" and "STEAM_ARM_D3D_DEFAULT" not in e, e)
for fam in ("mali-csf-v10", "adreno-a7xx", ""):
    e = launch_env(fam)
    check("E3 %s: PROTON_DXVK_D3D8=1 as before, no WineD3D" % (fam or "no family"),
          e.get("PROTON_DXVK_D3D8") == "1" and "PROTON_USE_WINED3D" not in e, e)
i_sync, i_rp = L.find("steam-arm-launchopts.py sync \"$S\" \"${GPU_FAMILY:-}\""), L.find("steam-arm-remoteplay >/dev/null 2>&1\nfi")
i_start = L.find("# --- interface: Deck (gamepadui)")
check("E4 launcher syncs launch options with client closed, before client start",
      0 < i_rp < i_sync < i_start and "if [ -f /usr/local/lib/steam-arm-launchopts.py ] && ! client_running; then" in L)

# ---------------- launch options helper ----------------
LO = heredoc("cat > /usr/local/lib/steam-arm-launchopts.py <<'LOPY'\n", "LOPY")
check("L0 steam-arm-launchopts.py written by setup", LO is not None)
SHARE, ETC = os.path.join(TMP, "share-titles.conf"), os.path.join(TMP, "etc-titles.conf")
LOP = os.path.join(TMP, "launchopts.py")
if LO:
    assert LO.count('"/usr/local/share/steam-arm/titles.conf"') == 1 and LO.count('"/etc/steam-arm/titles.conf"') == 1
    open(LOP, "w").write(LO.replace('"/usr/local/share/steam-arm/titles.conf"', repr(SHARE))
                         .replace('"/etc/steam-arm/titles.conf"', repr(ETC)))
LHOME = os.path.join(TMP, "lhome")
STEAM = os.path.join(TMP, "Steam")
VDF = '''"UserLocalConfigStore"
{
\t"Software"
\t{
\t\t"Valve"
\t\t{
\t\t\t"Steam"
\t\t\t{
\t\t\t\t"apps"
\t\t\t\t{
\t\t\t\t\t"400"
\t\t\t\t\t{
\t\t\t\t\t\t"LastPlayed"\t\t"1700000000"
\t\t\t\t\t\t"LaunchOptions"\t\t"-windowed"
\t\t\t\t\t}
\t\t\t\t\t"700"
\t\t\t\t\t{
\t\t\t\t\t\t"LaunchOptions"\t\t"MESA_GL_VERSION_OVERRIDE=3.2 %command% -name \\"a b\\""
\t\t\t\t\t}
\t\t\t\t\t"800"
\t\t\t\t\t{
\t\t\t\t\t\t"LastPlayed"\t\t"1"
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t}
\t}
\t"streaming_v2"
\t{
\t\t"EnableStreaming"\t\t"1"
\t}
}
'''
A1 = os.path.join(STEAM, "userdata", "111", "config", "localconfig.vdf")
A2 = os.path.join(STEAM, "userdata", "222", "config", "localconfig.vdf")


def lo(*args, env=None):
    e = {"PATH": "/usr/bin:/bin", "HOME": LHOME}
    e.update(env or {})
    r = subprocess.run([sys.executable, "-I", LOP] + list(args), env=e, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def opts(path):
    s = open(path).read()
    out = {}
    for m2 in re.finditer(r'\n\t{5}"([0-9]+)"\n\t{5}\{\n(.*?)\n\t{5}\}', s, re.S):
        k = re.search(r'"LaunchOptions"\t\t"((?:[^"\\]|\\.)*)"', m2.group(2))
        out[m2.group(1)] = k.group(1).replace('\\"', '"') if k else None
    return out


def fresh(profile_etc="", profile_home="", vdf2=VDF):
    shutil.rmtree(STEAM, ignore_errors=True)
    put(A1, VDF)
    put(A2, vdf2)
    put(ETC, profile_etc)
    put(SHARE, "248570 overlay=off\n")
    put(os.path.join(LHOME, ".config/steam-arm/titles.conf"), profile_home)


if LO:
    ns = {}
    exec(compile(LO, "launchopts", "exec"), ns)
    ns["PROFILE_FILES"] = (SHARE, ETC)
    put(SHARE, "400 overlay=off d3d=wined3d\n# 500 d3d=dxvk\n")
    put(ETC, "400 d3d=dxvk glver=3.3 # comment\n500 gl=zink\nx d3d=dxvk\n")
    p = ns["profiles"]((SHARE, ETC))
    check("L1 titles.conf parsing: later file wins, comments and bad app ids skipped",
          p == {"400": {"overlay": "off", "d3d": "dxvk", "glver": "3.3"}, "500": {"gl": "zink"}}, p)
    W = ns["wanted"]
    check("L2 wanted: v3d71 d3d=dxvk glver=3.3 gl=zink -> WineD3D off, GL pair, Zink pair",
          W({"d3d": "dxvk", "glver": "3.3", "gl": "zink"}, "broadcom-v3d71")
          == [("PROTON_USE_WINED3D", "0"), ("MESA_GL_VERSION_OVERRIDE", "3.3"), ("MESA_GLSL_VERSION_OVERRIDE", "330"),
              ("MESA_LOADER_DRIVER_OVERRIDE", "zink"), ("GALLIUM_DRIVER", "zink")])
    check("L2 wanted: v3d42 d3d=wined3d (default) -> nothing", W({"d3d": "wined3d"}, "broadcom-v3d42") == [])
    check("L2 wanted: mali / unknown glver -> nothing",
          W({"d3d": "dxvk", "glver": "3.3"}, "mali-csf-v10") == [] and W({"glver": "9.9"}, "broadcom-v3d71") == [])

    fresh("400 d3d=dxvk\n500 glver=3.3\n700 glver=3.3\n", "800 gl=zink\n")
    rc, out = lo("sync", STEAM, "broadcom-v3d71")
    o = opts(A1)
    check("L3 sync: own part leads, account options kept after %command%",
          rc == 0 and o["400"] == "STEAM_ARM_LAUNCHOPTS=+PROTON_USE_WINED3D PROTON_USE_WINED3D=0 %command% -windowed", (rc, out, o))
    check("L3 sync: app without entry gets block with launch options",
          o.get("500") == "STEAM_ARM_LAUNCHOPTS=MESA_GL_VERSION_OVERRIDE,MESA_GLSL_VERSION_OVERRIDE MESA_GL_VERSION_OVERRIDE=3.3 "
          "MESA_GLSL_VERSION_OVERRIDE=330 %command%", o)
    check("L3 sync: client home titles.conf read (800 gl=zink), LastPlayed kept",
          o.get("800") == "STEAM_ARM_LAUNCHOPTS=MESA_LOADER_DRIVER_OVERRIDE,GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE=zink "
          "GALLIUM_DRIVER=zink %command%" and '"LastPlayed"\t\t"1"' in open(A1).read(), o)
    check("L4 own launch option names a variable: account's value left, logged",
          o["700"] == 'MESA_GL_VERSION_OVERRIDE=3.2 %command% -name "a b"'
          and "app 700: MESA_GL_VERSION_OVERRIDE left to own launch options" in out, (o, out))
    check("L5 both accounts written, log lines name app and setting",
          opts(A2) == o and "account 111: app 400: launch options STEAM_ARM_LAUNCHOPTS" in out and "(d3d=dxvk)" in out, out)
    check("L5 other blocks byte-identical (streaming_v2, structure)",
          open(A1).read().count("\n") == VDF.count("\n") + 4 + 1 and '\t"streaming_v2"\n\t{\n\t\t"EnableStreaming"\t\t"1"\n\t}\n}\n' in open(A1).read())
    before = open(A1).read()
    st = os.stat(A1).st_mtime_ns
    rc, out = lo("sync", STEAM, "broadcom-v3d71")
    check("L6 second sync: no change, file not rewritten", rc == 0 and open(A1).read() == before and os.stat(A1).st_mtime_ns == st
          and "launch options STEAM" not in out, out)
    put(ETC, "500 glver=4.5\n700 glver=3.3\n")
    rc, out = lo("sync", STEAM, "broadcom-v3d71")
    o = opts(A1)
    check("L7 setting removed: own part gone, account options back byte for byte (added %command% dropped)",
          o["400"] == "-windowed", o)
    check("L7 setting changed: own part replaced", o["500"].startswith("STEAM_ARM_LAUNCHOPTS=MESA_GL_VERSION_OVERRIDE,"
                                                                       "MESA_GLSL_VERSION_OVERRIDE MESA_GL_VERSION_OVERRIDE=4.5 "), o)
    rc, out = lo("sync", STEAM, "mali-csf-v10")
    o = opts(A1)
    check("L8 other GPU family: every own part removed", rc == 0 and "STEAM_ARM" not in open(A1).read()
          and o["500"] == "" and o["800"] == "" and o["700"] == 'MESA_GL_VERSION_OVERRIDE=3.2 %command% -name "a b"', o)
    fresh("400 d3d=dxvk\n")
    st = os.stat(A1).st_mtime_ns
    rc, out = lo("sync", STEAM, "mali-csf-v10")
    check("L9 other GPU family, nothing of own in file: file untouched, silent", rc == 0 and out == ""
          and os.stat(A1).st_mtime_ns == st and open(A1).read() == VDF, out)
    lo("sync", STEAM, "broadcom-v3d42")
    rc, out = lo("restore", STEAM)
    check("L10 restore: own parts removed, account options kept", rc == 0 and "STEAM_ARM" not in open(A1).read()
          and opts(A1)["400"] == "-windowed" and opts(A2)["400"] == "-windowed", (rc, out))
    fresh("400 d3d=dxvk\n", vdf2='"UserLocalConfigStore"\n{\n\t"x"\t\t"1"\n}\n')
    rc, out = lo("sync", STEAM, "broadcom-v3d71")
    check("L11 account without apps block: file unchanged, note logged",
          open(A2).read() == '"UserLocalConfigStore"\n{\n\t"x"\t\t"1"\n}\n' and "account 222: launch options not set (no Software block" in out, out)
    fresh("400 d3d=dxvk\n", vdf2='"UserLocalConfigStore"\n{\n\t"Software"\n\t{\n')
    rc, out = lo("sync", STEAM, "broadcom-v3d71")
    check("L12 broken file: left unchanged, reason logged; other account written",
          open(A2).read() == '"UserLocalConfigStore"\n{\n\t"Software"\n\t{\n' and "account 222: localconfig.vdf left unchanged" in out
          and "STEAM_ARM_LAUNCHOPTS" in open(A1).read(), out)
    fresh("400 d3d=dxvk\n")
    fake = os.path.join(TMP, "steam")
    shutil.copy("/bin/sleep", fake)
    p = subprocess.Popen([fake, "20"])
    try:
        rc, out = lo("sync", STEAM, "broadcom-v3d71")
    finally:
        p.kill()
        p.wait()
    check("L13 client running: refused, file unchanged", rc == 1 and "client is running" in out and open(A1).read() == VDF, (rc, out))
    rc, out = lo("sync", STEAM)
    check("L14 usage error: rc 2", rc == 2 and "usage:" in out, out)
    c = ns["compose"]
    check("L15 compose: wrapper before %command% kept, args-only options get %command%",
          c("gamemoderun %command% -x", [("A", "1")]) == ("STEAM_ARM_LAUNCHOPTS=A A=1 gamemoderun %command% -x", [])
          and c("-x", [("A", "1")])[0] == "STEAM_ARM_LAUNCHOPTS=+A A=1 %command% -x")
    check("L15 strip: own part with values containing '=' removed exactly",
          ns["strip_own"]("STEAM_ARM_LAUNCHOPTS=A,B A=x=y B=2 %command% -z") == "%command% -z")
    rt = {}
    for own in ("-own -windowed", "  -x  ", "-x", "", "SA232_OWN=1 %command% -own", "gamemoderun %command%",
                "%command%", "A=0 %command% -k"):
        new, _ = c(own, [("A", "1"), ("B", "2")])
        again, _ = c(new, [("A", "1"), ("B", "2")])
        rt[own] = (new, ns["strip_own"](new), again == new)
    check("L16 round trip byte-exact: own options with and without %command% back unchanged after strip, re-sync stable",
          all(back == own and stable for own, (new, back, stable) in rt.items() if own != "%command%")
          and rt["%command%"][1] == "" and rt["A=0 %command% -k"][0] == "STEAM_ARM_LAUNCHOPTS=B B=2 A=0 %command% -k", rt)
    check("L16 %command% flag only when added: '+' for options without %command%, none with it or empty",
          rt["-own -windowed"][0] == "STEAM_ARM_LAUNCHOPTS=+A,B A=1 B=2 %command% -own -windowed"
          and rt["SA232_OWN=1 %command% -own"][0] == "STEAM_ARM_LAUNCHOPTS=A,B A=1 B=2 SA232_OWN=1 %command% -own"
          and rt[""][0] == "STEAM_ARM_LAUNCHOPTS=A,B A=1 B=2 %command%", rt)
    check("L16 legacy marker without flag: %command% kept as before",
          ns["strip_own"]("STEAM_ARM_LAUNCHOPTS=A A=1 %command% -own -windowed") == "%command% -own -windowed"
          and ns["strip_own"]("STEAM_ARM_LAUNCHOPTS=A A=1 %command%") == ""
          and c("STEAM_ARM_LAUNCHOPTS=A A=1 %command% -own", [])[0] == "%command% -own")
    fresh("400 d3d=dxvk glver=3.3 gl=zink\n")
    rc1, out1 = lo("sync", STEAM, "broadcom-v3d71")
    mid = opts(A1)["400"]
    rc2, out2 = lo("restore", STEAM)
    check("L16 sync then restore on localconfig.vdf: own '-windowed' back byte-exact",
          rc1 == rc2 == 0 and mid.startswith("STEAM_ARM_LAUNCHOPTS=+") and mid.endswith(" %command% -windowed")
          and '"LaunchOptions"\t\t"-windowed"' in open(A1).read() and opts(A1)["400"] == "-windowed", (mid, out1, out2))

# ---------------- titles.conf header on upgrade ----------------
i0 = SRC.find("# Header comment of system titles.conf: this version's text; every other line kept byte for byte.\ntmp=$(mktemp)\n")
i1 = SRC.find('rm -f "$tmp"\n', i0)
TCB = SRC[i0:i1 + len('rm -f "$tmp"\n')] if 0 < i0 < i1 else ""
check("T0 setup refreshes header of existing /etc/steam-arm/titles.conf", bool(TCB) and "[ -f /etc/steam-arm/titles.conf ] ||" not in SRC)
NEWHEAD = TCB[TCB.find("<<'TITLES'\n") + 11:TCB.find("\nTITLES\n")] + "\n" if TCB else ""
TD = os.path.join(TMP, "etcsa")


def tc_run(content):
    shutil.rmtree(TD, ignore_errors=True)
    os.makedirs(TD)
    f = os.path.join(TD, "titles.conf")
    if content is not None:
        open(f, "wb").write(content)
        os.chmod(f, 0o640)
    sh = "set -e\nwarn(){ echo \"WARN $*\"; }\n" + TCB.replace("/etc/steam-arm", TD)
    r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr, (open(f, "rb").read() if os.path.exists(f) else None), f


OLDHEAD = (b"# Local title profiles; override /usr/local/share/steam-arm/titles.conf. One line per title: <appid> key=value ...\n"
           b"#   overlay=x86|vulkan|off  mangohud=on|off  godot=gl|vulkan  env=A=1;B=2  args=-x;-y   (example: <appid> overlay=off)\n"
           b"#   gfx=b (Mali drivers inside emulation)  gfx=a (forwarding); unset = automatic\n")
BODY = b"# own note\n1087810 d3d=dxvk glver=3.3   gl=zink # keep\r\n\n  400 overlay=off\n#   indented own comment after body\n500 gfx=b"
if TCB:
    rc, out, got, f = tc_run(OLDHEAD + BODY)
    check("T1 old header replaced by this version's header, every other line byte-identical (no final newline kept)",
          rc == 0 and got == NEWHEAD.encode() + BODY and b"d3d=dxvk|wined3d" in got and "WARN" not in out, (rc, out, got))
    check("T1 file mode kept", oct(os.stat(f).st_mode & 0o777) == "0o640", oct(os.stat(f).st_mode))
    st = os.stat(f).st_mtime_ns
    rc, out, got2, f = tc_run(got)
    check("T2 current header: content unchanged", rc == 0 and got2 == got, (rc, out))
    rc, out, got, f = tc_run(None)
    check("T3 no file: written with header, mode 644", rc == 0 and got == NEWHEAD.encode() and oct(os.stat(f).st_mode & 0o777) == "0o644", (rc, out, got))
    own = b"# my own header\n#   my lines\n400 overlay=off\n"
    rc, out, got, f = tc_run(own)
    check("T4 file without Steam ARM header: left byte-identical", rc == 0 and got == own, (rc, out, got))
    rc, out, got, f = tc_run(b"")
    check("T4 empty file: left empty", rc == 0 and got == b"", (rc, out, got))
    check("T5 no temp files left", sorted(os.listdir(TD)) == ["titles.conf"], os.listdir(TD))

# ---------------- removal ----------------
RM = SRC[SRC.index("remove_all(){"):]
RM = RM[:RM.index("\n}\n")]
check("R1 removal restores launch options before helper goes, helper removed",
      RM.find("steam-arm-launchopts.py restore") > 0 and RM.find("steam-arm-launchopts.py restore") < RM.find("/usr/local/lib/steam-arm-launchopts.py \\")
      if "/usr/local/lib/steam-arm-launchopts.py \\" in RM else False)

shutil.rmtree(TMP, ignore_errors=True)
print("pi gpu 2.3.2: %d failed" % len(FAILS))
sys.exit(1 if FAILS else 0)
