#!/usr/bin/env python3
"""Steam ARM 3.1 per-title emulation keys tso=off and x87=reduced: handler writes TSOEnabled 0 or X87ReducedPrecision 1
into FEX_APP_CONFIG (tool entry and x86 entry), launch-option FEX_APP_CONFIG and Steam's FEX setting win, unknown
values logged and dropped, run record start line carries tso and x87, CPU drawing notice on the slow class names the
memory model setting, autotune knobs stay free of both; strict for one start after two failed relaxed runs (run
record), end hint on the slow class (fabricated records and shares). Handler extracted from the installer under test (SARM_INST
picks another); settings file path rewritten in the extract only. Internal; not for release zips."""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST  # noqa: E402

SRC = open(INST).read()
START = "cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n"
CONF_P = '"/etc/steam-arm/steam-arm.conf"'
TMP = tempfile.mkdtemp(prefix="sarm31-emu-")
CONF = os.path.join(TMP, "steam-arm.conf")
FAILS = []
PASSES = [0]


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if cond:
        PASSES[0] += 1
    else:
        FAILS.append(name)
        if detail:
            print("     ", str(detail)[:1500])


def put(path, data=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(data)


i = SRC.index(START) + len(START)
H = SRC[i:SRC.index("\nHANDLERPY\n", i) + 1]
HANDLER = os.path.join(TMP, "handler.py")
open(HANDLER, "w").write(H.replace(CONF_P, repr(CONF)))
DRIVER = r'''
import json, os, runpy, sys
def generate_app_config():
    return {"Config": {"TSOEnabled": True}, "ThunksDB": {}}
sys.argv = json.loads(os.environ.pop("T_ARGV"))
init = {}
if os.environ.get("T_ENTRY"):
    init["ENTRY"] = os.environ.pop("T_ENTRY")
    init["CLIENT_X86"] = init["ENTRY"] == "x86"
g = runpy.run_path(os.environ.pop("T_HANDLER"), init_globals=init)
out = {"argv": sys.argv, "run": {k: v for k, v in g.get("RUN", {}).items() if isinstance(v, (str, int, bool))}}
p = os.environ.get("FEX_APP_CONFIG")
if p and os.path.exists(p):
    out["app_config"] = json.load(open(p))
print("RESULT " + json.dumps(out))
'''
DRV = os.path.join(TMP, "driver.py")
open(DRV, "w").write(DRIVER)
G = os.path.join(TMP, "games", "plain")
os.makedirs(G)
open(os.path.join(G, "game.bin"), "wb").write(b"\x7fELF\x02\x01\x01" + b"\0" * 57)


def run(profile="", env=None, entry=None, conf="GPU_FAMILY=other\nGFX_DEFAULT=auto\n", home=None):
    open(CONF, "w").write(conf)
    home = home or tempfile.mkdtemp(dir=TMP)
    if profile:
        put(os.path.join(home, ".config/steam-arm/titles.conf"), "100 %s\n" % profile)
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": "100",
         "T_ARGV": json.dumps(["fex-compat-tool", "waitforexitandrun", os.path.join(G, "game.bin")]),
         "T_HANDLER": HANDLER, "STEAM_ARM_RENDERER_CHECK": "0", "STEAM_COMPAT_INSTALL_PATH": G}
    if entry:
        e["T_ENTRY"] = entry
    e.update(env or {})
    r = subprocess.run([sys.executable, DRV], env=e, cwd=G, capture_output=True, text=True)
    if r.returncode:
        return {"cfg": {}, "log": r.stdout + r.stderr, "home": home}
    res = json.loads([l for l in r.stdout.splitlines() if l.startswith("RESULT ")][-1][7:])
    res["log"] = r.stdout
    res["cfg"] = res.get("app_config", {}).get("Config", {})
    res["home"] = home
    return res


r = run("tso=off")
check("E1 tso=off, tool entry: TSOEnabled 0 in FEX app config, tool's other keys kept, logged as correctness trade",
      r["cfg"].get("TSOEnabled") == "0" and "fex: memory model relaxed (TSO emulation off) (title setting tso=off; correctness trade, per title)" in r["log"], r)
r = run("x87=reduced")
check("E2 x87=reduced: X87ReducedPrecision 1, TSOEnabled untouched",
      r["cfg"].get("X87ReducedPrecision") == "1" and r["cfg"].get("TSOEnabled") is True
      and "fex: x87 precision reduced (title setting x87=reduced; correctness trade, per title)" in r["log"], r)
r = run("tso=off x87=reduced", entry="x86")
check("E3 x86 entry (x86 client): both keys from an empty config", r["cfg"] == {"TSOEnabled": "0", "X87ReducedPrecision": "1"}, r)
r = run()
check("E4 no setting: no FEX app config written by these rules", r["cfg"] == {}, r)
# launch option FEX_APP_CONFIG with the key wins
lo = os.path.join(TMP, "launch.json")
put(lo, json.dumps({"Config": {"TSOEnabled": "1"}}))
r = run("tso=off", env={"FEX_APP_CONFIG": lo})
check("E5 launch option FEX_APP_CONFIG with TSOEnabled: kept, logged", r["cfg"].get("TSOEnabled") == "1"
      and "launch option kept: TSOEnabled=1 (title setting tso=off)" in r["log"], r)
r = run("x87=reduced", env={"FEX_APP_CONFIG": lo})
check("E5b launch option without X87 key: title setting applied beside it", r["cfg"].get("X87ReducedPrecision") == "1" and r["cfg"].get("TSOEnabled") == "1", r)
r = run("tso=off", env={"STEAM_COMPAT_FEX_CONFIG": "/x/steam.json"})
check("E6 Steam's FEX setting present: kept, logged, nothing written", r["cfg"] == {}
      and "Steam setting kept: STEAM_COMPAT_FEX_CONFIG=/x/steam.json (title setting tso=off)" in r["log"], r)
r = run("tso=relaxed x87=fast")
check("E7 unknown values: logged with the accepted value, nothing written", r["cfg"] == {}
      and "fex: title setting tso=relaxed unknown (value: off); not applied" in r["log"] and "fex: title setting x87=fast unknown (value: reduced); not applied" in r["log"], r)
# run record start line carries tso and x87
r = run("tso=off x87=reduced", conf="GPU_FAMILY=other\nGFX_DEFAULT=auto\nRUN_HISTORY=on\n")
runs = os.path.join(r["home"], ".local/state/steam-arm/runs.log")
line = open(runs).read().splitlines()[-1] if os.path.exists(runs) else ""
check("E8 run record start line: tso=off x87=reduced, vkhost, then profile", " tso=off x87=reduced vkhost=- profile=" in line, line or r["log"][-600:])
r = run(conf="GPU_FAMILY=other\nGFX_DEFAULT=auto\nRUN_HISTORY=on\n")
runs = os.path.join(r["home"], ".local/state/steam-arm/runs.log")
line = open(runs).read().splitlines()[-1] if os.path.exists(runs) else ""
check("E8b without settings: tso=- x87=-", " tso=- x87=- " in line, line)
# memory model back to strict after two failed relaxed runs (run record), re-armed by a run that ends well
def recs(home, *runs):
    """runs: (tso-of-start, exit fields) pairs written as start+exit lines for app 100."""
    lines = []
    for i, (tso, ex) in enumerate(runs):
        lines.append("t=2026-10-20T00:00:%02dZ ev=start app=100 run=%d entry=tool client=arm64 gfx=a tso=%s x87=- profile=tso" % (i, 1000 + i, tso))
        lines.append("t=2026-10-20T00:01:%02dZ ev=exit app=100 run=%d %s" % (i, 1000 + i, ex))
    put(os.path.join(home, ".local/state/steam-arm/runs.log"), "\n".join(lines) + "\n")
    os.chmod(os.path.join(home, ".local/state/steam-arm/runs.log"), 0o600)


RH = "GPU_FAMILY=other\nGFX_DEFAULT=auto\nRUN_HISTORY=on\n"
h = tempfile.mkdtemp(dir=TMP)
recs(h, ("off", "status=0 secs=12 renderer=unknown verdict=crash"), ("off", "status=0 secs=300 renderer=gpu verdict=hang"))
r = run("tso=off", conf=RH, home=h)
line = open(os.path.join(h, ".local/state/steam-arm/runs.log")).read().splitlines()[-1]
check("T1 two failed relaxed runs (crash, hang verdicts): this start strict, nothing written, log line, start record tso=off:strict",
      "TSOEnabled" not in r["cfg"] and "memory model: back to strict after 2 failed runs (title setting kept; a run that ends well re-arms it)" in r["log"]
      and " tso=off:strict " in line and r["run"].get("tso_strict") is True, (r["cfg"], r["log"][-500:], line))
h = tempfile.mkdtemp(dir=TMP)
recs(h, ("off", "status=0 secs=12 renderer=unknown verdict=crash"), ("off", "status=0 secs=900 renderer=gpu verdict=ok"), ("off", "status=0 secs=20 renderer=unknown verdict=crash"))
r = run("tso=off", conf=RH, home=h)
check("T2 crash, ok, crash: relaxed kept (last two not both failed)", r["cfg"].get("TSOEnabled") == "0" and "back to strict" not in r["log"], r["cfg"])
h = tempfile.mkdtemp(dir=TMP)
recs(h, ("off", "status=0 secs=12 renderer=unknown"), ("off", "status=sig11 secs=40 renderer=unknown"))
r = run("tso=off", conf=RH, home=h)
check("T3 no verdicts (no autotune): two exits under 60 s count as failed", "TSOEnabled" not in r["cfg"] and "back to strict" in r["log"], r["cfg"])
h = tempfile.mkdtemp(dir=TMP)
recs(h, ("-", "status=0 secs=12 renderer=unknown verdict=crash"), ("-", "status=0 secs=12 renderer=unknown verdict=crash"))
r = run("tso=off", conf=RH, home=h)
check("T4 failed runs that were strict (tso=-) do not count", r["cfg"].get("TSOEnabled") == "0", r["cfg"])
h = tempfile.mkdtemp(dir=TMP)
recs(h, ("off", "status=0 secs=12 renderer=unknown verdict=crash"), ("off:strict", "status=0 secs=12 renderer=unknown verdict=crash"))
r = run("tso=off", conf=RH, home=h)
check("T5 strict retry that failed too keeps strict (both last runs carry tso off)", "TSOEnabled" not in r["cfg"], r["cfg"])
h = tempfile.mkdtemp(dir=TMP)
recs(h, ("off", "status=0 secs=12 renderer=unknown verdict=crash"), ("off", "status=0 secs=12 renderer=unknown verdict=crash"))
r = run("tso=off", conf="GPU_FAMILY=other\nGFX_DEFAULT=auto\n", home=h)
check("T6 run history off: records still read (file present), strict", "TSOEnabled" not in r["cfg"], r["cfg"])
r = run("tso=off", conf=RH)
check("T7 no run record file: relaxed applied", r["cfg"].get("TSOEnabled") == "0", r["cfg"])
# end hint: slow class, GPU renderer, 90 % of all cores over 120 s and more, no tso=off yet
m = re.search(r"^def end_hint\(secs\):.*?^    return share\n", H, re.M | re.S)
check("T8 end_hint defined, called from run_exit, load_watch thread on the slow class only", bool(m) and "        end_hint(secs)\n" in H
      and 'if slow_class() and os.environ.get("STEAM_ARM_RENDERER_CHECK", "1") != "0":\n    threading.Thread(target=load_watch' in H)
EH = {}
notes = []
exec("import os\n" + m.group(0), EH)
EH.update(RUN={"renderer": "gpu", "cpu_s": 0.0}, prof={}, bits=32, log=lambda *a: notes.append(("log",) + a),
          desktop_notice=lambda s, b, **k: notes.append(("notice", s, b)), slow_class=lambda: True)
EH["os"] = type("o", (), {"cpu_count": staticmethod(lambda: 4)})
EH["RUN"]["cpu_s"] = 0.95 * 4 * 300
v = EH["end_hint"](300)
check("T9 95 % of four cores over 300 s, GPU, 32-bit: notice names tso=off and x87=reduced with the menu path",
      v and v > 0.9 and any(n[0] == "notice" and "Memory model relaxed (tso=off)" in n[2] and "x87 precision reduced (x87=reduced)" in n[2] and "Games, this game, Emulation" in n[2] for n in notes), notes)
notes.clear(); EH["bits"] = 64; EH["end_hint"](300)
check("T9b 64-bit: x87 not named", any(n[0] == "notice" and "x87" not in n[2] for n in notes), notes)
notes.clear(); EH["RUN"]["cpu_s"] = 0.5 * 4 * 300
check("T10 50 % share: nothing", EH["end_hint"](300) is None and not notes, notes)
notes.clear(); EH["RUN"]["cpu_s"] = 0.95 * 4 * 300; EH["RUN"]["renderer"] = "cpu"
check("T10b renderer CPU: nothing (CPU drawing notice covers it)", EH["end_hint"](300) is None and not notes)
EH["RUN"]["renderer"] = "gpu"; EH["prof"] = {"tso": "off"}
check("T10c tso=off already set: nothing", EH["end_hint"](300) is None and not notes)
EH["prof"] = {}; EH["RUN"]["cpu_s"] = 0.95 * 4 * 60
check("T10d run under 120 s: nothing", EH["end_hint"](60) is None and not notes)
EH["slow_class"] = lambda: False; EH["RUN"]["cpu_s"] = 0.95 * 4 * 300
check("T10e not slow class: nothing", EH["end_hint"](300) is None and not notes)

# CPU drawing notice text: slow class sentence from the handler source
m = re.search(r'slow = \("CPU without Armv8.1 atomics: title setting Memory model: relaxed \(steam-arm-config, Games, Emulation\) "\n\s+"speeds up emulation at a stability cost." if slow_class\(\) else ""\)', H)
check("E9 CPU drawing notice adds the memory model sentence on the slow class only", bool(m))
# autotune never trials them
A = SRC[SRC.index("cat > /usr/local/lib/steam-arm-autotune.py <<'AUTOTUNEPY'\n") + len("cat > /usr/local/lib/steam-arm-autotune.py <<'AUTOTUNEPY'\n"):]
A = A[:A.index("\nAUTOTUNEPY\n")]
kn = re.search(r"^KNOBS = (.*)$", A, re.M).group(1)
check("E10 autotune KNOBS hold neither tso nor x87", "tso" not in kn and "x87" not in kn and "TSO" not in kn, kn)
# menu: profile CLI accepts the keys, --clear removes them (static)
M = SRC[SRC.index("menu_app(){ cat <<'STEAMARMCONFIG'\n"):]
check("E11 settings menu: profile_ok accepts tso=off and x87=reduced only; --clear lists them; Games row Emulation",
      "mesa=|tso=|tso=off|x87=|x87=reduced) return 0;;" in M and "multiblock diskcache autotune tso x87 d3d glver gl; do tc_set" in M
      and 'emu "Emulation            [$(emu_summary "$id")]"' in M and "game_emulation()" in M)

# thunks-missing reason: GL or Vulkan thunk off in the account's FEX config
import ast
tree = ast.parse(H)
keep = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.Import, ast.ImportFrom))
        or (isinstance(n, ast.Assign) and any(getattr(t, "id", "") in ("GFX_LIB", "GUEST_MESA", "FEX_COMM", "NON_GPU_DRM") for t in n.targets))]
ns = {}
exec(compile(ast.Module(body=keep, type_ignores=[]), "handler-defs", "exec"), ns)
V = ns["renderer_verdict"]
v = V(("g", True, ["libgallium-25.0.so", "swrast_dri.so"], False, set()), 15)
check("R1 verdict text names x86 Mesa llvmpipe", v and "x86 Mesa inside emulation loaded (llvmpipe; libgallium-25.0.so, swrast_dri.so)" in v, v)
v = V(("g", True, ["v3d_dri.so", "libgallium-26.2.so"], False, set()), 15)
check("R2 verdict text names Broadcom x86 driver", v and "(v3d, Broadcom x86 driver; " in v, v)
v = V(("g", True, ["libvulkan_lvp.so"], False, set()), 15)
check("R2b lavapipe counts as llvmpipe", v and "(llvmpipe; libvulkan_lvp.so)" in v, v)
v = V(("g", True, ["radeonsi_dri.so"], False, set()), 15)
check("R2c other driver: unknown", v and "(driver unknown; radeonsi_dri.so)" in v, v)
home = tempfile.mkdtemp(dir=TMP)
put(os.path.join(home, ".fex-emu/Config.json"), '{ "Config": { "RootFS":"/opt/x" },\n  "ThunksDB":{"GL":0,"Vulkan":0} }\n')
r = run(home=home)
check("R3 thunks off in FEX config: RUN reason thunks-missing, log line", r.get("run", {}).get("reason") == "thunks-missing"
      and "fex: GL or Vulkan thunk off in ~/.fex-emu/Config.json (setup found no thunk libraries): forwarding route draws on CPU" in r["log"], r)
home = tempfile.mkdtemp(dir=TMP)
put(os.path.join(home, ".fex-emu/Config.json"), '{ "Config": { "RootFS":"/opt/x" },\n  "ThunksDB":{"GL":1,"Vulkan":1} }\n')
r = run(home=home)
check("R4 thunks on: no reason", "reason" not in r.get("run", {}) and "thunk off" not in r["log"], r)
r = run()
check("R5 no FEX config: no reason", "reason" not in r.get("run", {}), r)
check("R6 run record exit line carries reason when set; renderer watch logs the cause",
      '+ ([("reason", RUN["reason"])] if RUN.get("reason") else []))' in H and 'log("renderer: cause: GL or Vulkan thunk off in FEX config (setup found no thunk libraries)")' in H)

print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
