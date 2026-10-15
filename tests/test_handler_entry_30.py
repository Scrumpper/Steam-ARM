#!/usr/bin/env python3
"""Steam ARM 3.0 handler entry (A2): launch wrapper stand-in of the native client (steam-arm-entry.py prepare, restore,
status), handler in arm64 entry (FEX settings through FEX_APP_CONFIG with Valve's per-title keys, thunk paths file per
title for FEX tools before 2609, LD_PRELOAD placed after the FEX tool's arguments), steam-arm-run.py --client arm64.
Fixtures for both FEX tool types: Valve's Python fex-compat-tool (fixtures/fex-tool) and a C/C++ host program (ELF).
Helpers extracted from the installer under test (SARM_INST picks another file); paths rewritten to temp copies in the
extracts only. Internal; not for release zips."""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST  # noqa: E402
TMP = tempfile.mkdtemp(prefix="sarm30-entry-")
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


def rd(path):
    with open(path, "rb") as f:
        return f.read()


ELF = b"\x7fELF\x02\x01\x01" + b"\0" * 57
RUN_FAKE = os.path.join(TMP, "run-fake.py")
E = heredoc("cat > /usr/local/lib/steam-arm-entry.py <<'ENTRYPY'\n", "ENTRYPY")
H = heredoc("cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n", "HANDLERPY")
R = heredoc("cat > /usr/local/lib/steam-arm-run.py <<'RUNPY'\n", "RUNPY")
check("E0 installer writes steam-arm-entry.py, handler and run helper", bool(E) and bool(H) and bool(R))
if not (E and H and R):
    print("%d FAIL" % len(FAILS))
    sys.exit(1)
check("E0 entry helper in removal list", "/usr/local/lib/steam-arm-entry.py \\" in SRC
      and 'steam-arm-entry.py restore "$armhome/.local/share/Steam"' in SRC)
check("E0 launcher: entry check before FEX tool edit, watcher runs it",
      "entry_check(){" in SRC and "do entry_check; fex_check;" in SRC and 'if [ "$ENTRY_OK" = 1 ]; then' in SRC)
check("E0 --detect: entry status lines", 'python3 /usr/local/lib/steam-arm-entry.py status "$c"' in SRC)
ENTRY = os.path.join(TMP, "entry.py")
put(ENTRY, E.replace('RUN = "/usr/local/lib/steam-arm-run.py"', "RUN = %r" % RUN_FAKE))


def entry(*a):
    r = subprocess.run([sys.executable, ENTRY] + list(a), capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


# ---------------- stand-in: prepare / restore ----------------
S = os.path.join(TMP, "Steam")
W = os.path.join(S, "linuxarm64/steam-launch-wrapper")
put(W, ELF + b"valve-1", 0o755)
rc, out = entry("prepare", S)
check("E1 prepare: rc 0, Valve's program kept as .real", rc == 0 and rd(W + ".real") == ELF + b"valve-1", out)
st = rd(W).decode()
check("E1 stand-in: marked shell script, executable", st.startswith("#!/bin/sh\n# steam-arm stand-in")
      and os.stat(W).st_mode & stat.S_IXUSR, st)
check("E1 stand-in: FEX tool starts go to steam-arm-run.py --client arm64, LD_PRELOAD passed as argument",
      "*/FEX-Emu/*) [ -f %s ] && exec env -u LD_PRELOAD /usr/bin/python3 %s --client arm64 --preload" % (RUN_FAKE, RUN_FAKE)
      in st, st)
rc2, out2 = entry("prepare", S)
check("E1 prepare again: no change, no output", rc2 == 0 and out2 == "" and rd(W).decode() == st, out2)

# stand-in behaviour with a recording real program and fake run helper
REC = os.path.join(TMP, "rec.txt")
put(W + ".real", "#!/bin/sh\nprintf 'real %%s\\n' \"$*\" >> %s\n" % REC, 0o755)
put(RUN_FAKE, "import os, sys\nopen(%r, 'a').write('run %%s preload=%%s ldp=%%s\\n' %% (' '.join(sys.argv[1:]), "
              "sys.argv[sys.argv.index('--preload') + 1], os.environ.get('LD_PRELOAD', '-')))\n" % REC)


def stand_in(*args, env=None):
    if os.path.exists(REC):
        os.unlink(REC)
    e = dict(os.environ)
    e.update(env or {})
    subprocess.run(["/bin/sh", W] + list(args), env=e, capture_output=True)
    return open(REC).read() if os.path.exists(REC) else ""


o = stand_in("--", "reaper", "SteamLaunch", "--", "/x/steamapps/common/Proton 11.0 (ARM64)/proton", "run", "g.exe")
check("E2 stand-in: start without FEX tool goes straight to Valve's program",
      o.splitlines() == ["real -- reaper SteamLaunch -- /x/steamapps/common/Proton 11.0 (ARM64)/proton run g.exe"], o)
o = stand_in("--", "reaper", "--", "/x/steamapps/common/FEX-Emu/fex-compat-tool", "waitforexitandrun", "--", "game",
             env={"LD_PRELOAD": "/a/x.so:/b/y.so"})
check("E2 stand-in: FEX tool start runs handler helper, LD_PRELOAD moved to --preload",
      len(o.splitlines()) == 1 and o.startswith("run --client arm64 --preload /a/x.so:/b/y.so -- ") and o.endswith(" ldp=-\n"), o)
os.rename(RUN_FAKE, RUN_FAKE + ".off")
o = stand_in("--", "reaper", "--", "/x/steamapps/common/FEX-Emu/fex-compat-tool", "waitforexitandrun", "--", "game")
check("E2 stand-in: helper missing (older version removed it): Valve's program runs", o.startswith("real -- reaper"), o)
os.rename(RUN_FAKE + ".off", RUN_FAKE)

# client update puts a new Valve program in place
put(W, ELF + b"valve-2", 0o755)
rc, out = entry("prepare", S)
check("E3 client update: new program becomes .real, stand-in back", rc == 0 and rd(W + ".real") == ELF + b"valve-2"
      and rd(W).startswith(b"#!/bin/sh\n# steam-arm stand-in"), out)
S4 = os.path.join(TMP, "Steam4")
put(os.path.join(S4, "linuxarm64/steam-launch-wrapper"), "#!/bin/sh\necho someone else\n", 0o755)
rc, out = entry("prepare", S4)
check("E4 unknown launch wrapper file: rc 1, left as it is", rc == 1 and b"someone else" in rd(
    os.path.join(S4, "linuxarm64/steam-launch-wrapper")) and "left as it is" in out, out)
rc, out = entry("prepare", os.path.join(TMP, "Steam-empty"))
check("E5 no launch wrapper yet: rc 1 (FEX tool edit fallback)", rc == 1 and "not there yet" in out, out)

# restore: wrapper back, own thunk paths files out of compatdata
own = os.path.join(S, "steamapps/compatdata/100/fex-emu/ThunksDB.json")
user = os.path.join(S, "steamapps/compatdata/200/fex-emu/ThunksDB.json")
put(own, json.dumps({"DB": {}, "steam-arm": "x"}))
put(user, json.dumps({"DB": {}}))
rc, out = entry("restore", S)
check("E6 restore: Valve's program back, no .real", rc == 0 and rd(W) == ELF + b"valve-2" and not os.path.exists(W + ".real"), out)
check("E6 restore: marked thunk paths file removed, own file of user kept", not os.path.exists(own) and os.path.exists(user), out)
rc, out = entry("restore", S)
check("E6 restore again: nothing to do", rc == 0 and rd(W) == ELF + b"valve-2", out)

# ---------------- FEX tool fixtures ----------------
MANIFEST = '"manifest"\n{\n  "commandline" "/fex-compat-tool %verb% --"\n  "filter_exclusive_priority" "2"\n  "version" "2"\n' \
           '  "use_tool_subprocess_reaper" "1"\n  "compatmanager_layer_name" "fex"\n}\n'
EMU = '{"emulator_v0": {"argv": "./usr/bin/FEX", "main_argv": "./FEXCompatTool", "server_argv": "./usr/bin/FEXServerManager"}}\n'
VALVE_DB = {"DB": {"GL": {"Library": "libGL-guest.so", "Overlay": ["@PREFIX_LIB@/libGL.so.1"]},
                   "Vulkan": {"Library": "libvulkan-guest.so", "Overlay": ["@PREFIX_LIB@/libvulkan.so.1"]}}}


def fex_tool(steam, kind, ver):
    f = os.path.join(steam, "steamapps/common/FEX-Emu")
    put(os.path.join(f, "toolmanifest.vdf"), MANIFEST)
    put(os.path.join(f, "emulator.json"), EMU)
    put(os.path.join(f, "VERSIONS.txt"), "FEX describe\t%s\n" % ver)
    put(os.path.join(f, "FEXCompatTool"), ELF, 0o755)
    put(os.path.join(f, "usr/share/fex-emu/ThunksDB.json"), json.dumps(VALVE_DB))
    if kind == "python":
        put(os.path.join(f, "fex-compat-tool"), rd(os.path.join(HERE, "fixtures/fex-tool/fex-compat-tool")), 0o755)
        put(os.path.join(f, "unshare.py"), "def unshare(flags):\n    pass\n")
    else:
        put(os.path.join(f, "fex-compat-tool"), ELF + b"cxx host entry", 0o755)
    return f


SP = os.path.join(TMP, "SteamPy")
FP = fex_tool(SP, "python", "FEX-2607-76-g37265b1")
SC = os.path.join(TMP, "SteamCxx")
FC = fex_tool(SC, "c++", "FEX-2610")
put(os.path.join(SP, "linuxarm64/steam-launch-wrapper"), ELF, 0o755)
entry("prepare", SP)
rc, out = entry("status", SP)
check("E7 status, Python tool: type and no edits", "fex tool: python, edits: 0" in out and "handler entry: launch wrapper" in out, out)
rc, out = entry("status", SC)
check("E7 status, C/C++ tool program: type c++", "fex tool: c++, edits: 0" in out and "handler entry: none" in out, out)
put(os.path.join(FC, "ConfigTemplate.json.steam-arm-sha"), "x\n")
put(os.path.join(FC, "usr/share/fex-emu/ThunksDB.json.steam-arm-sha"), "x\n")
rc, out = entry("status", SC)
check("E7 status: own edits counted (sha records), entry FEX tool edit", "fex tool: c++, edits: 2" in out
      and "handler entry: FEX tool edit" in out, out)
rc, out = entry("status", os.path.join(TMP, "SteamNone"))
check("E7 status: FEX tool not downloaded", "fex tool: not downloaded, edits: 0" in out, out)

# handler reach from Steam's gameprocess_log against handler logs in /tmp
now = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() + 5))
put(os.path.join(SP, "logs/gameprocess_log.txt"),
    '[%s] AppID 987650 adding PID 1 as a tracked process "/x/linuxarm64/steam-launch-wrapper -- reaper SteamLaunch '
    "AppId=987650 -- '/x/steamapps/common/FEX-Emu'/fex-compat-tool waitforexitandrun -- game\"\n" % now)
rc, out = entry("status", SP)
check("E8 FEX title start without handler log: handler not reached", "handler: not reached" in out, out)
runlog = "/tmp/steam-arm-run-%d.log" % (900000000 + os.getpid() % 1000000)
try:
    put(runlog, "SteamAppId=987650\nsteam-arm: client: native ARM64\n", 0o600)
    os.utime(runlog, (time.time() + 10, time.time() + 10))
    rc, out = entry("status", SP)
    check("E8 handler log of that title written since: handler reached", "handler: reached" in out, out)
finally:
    if os.path.exists(runlog):
        os.unlink(runlog)

# ---------------- handler, arm64 entry ----------------
CONF = os.path.join(TMP, "steam-arm.conf")
MALI = os.path.join(TMP, "mali-tree")
put(os.path.join(MALI, ".steam-arm-mali"), "26.1.8\n")
put(os.path.join(MALI, "graphics_provider.json"), "{}\n")
HP = os.path.join(TMP, "handler.py")
put(HP, H.replace('"/etc/steam-arm/steam-arm.conf"', repr(CONF))
    .replace('MALI_ROOT = "/opt/fex-rootfs/Ubuntu_24_04-mali"', "MALI_ROOT = %r" % MALI))
DRIVER = os.path.join(TMP, "driver.py")
put(DRIVER, r'''
import json, os, runpy, sys
sys.argv = json.loads(os.environ.pop("T_ARGV"))
g = {"ENTRY": os.environ.pop("T_ENTRY")}
try:
    runpy.run_path(os.environ.pop("T_HANDLER"), init_globals=g)
    err = None
except Exception as e:
    err = "%s: %s" % (type(e).__name__, e)
out = {"argv": sys.argv, "err": err, "env": {k: v for k, v in os.environ.items()
       if k.startswith(("FEX_", "STEAM_COMPAT_GRAPHICS", "LD_PRELOAD"))}}
p = os.environ.get("FEX_APP_CONFIG")
try:
    out["app_config"] = json.load(open(p)) if p else None
except (OSError, ValueError):
    pass
print("RESULT " + json.dumps(out))
''')
GAME = os.path.join(TMP, "lib/steamapps/common/Game")
put(os.path.join(GAME, "game.bin"), ELF, 0o755)
OV64 = "/x/Steam/ubuntu12_64/gameoverlayrenderer.so"
OVARM = "/x/Steam/steamrtarm64/gameoverlayrenderer.so"


def chain(f):
    return ["steam-arm-run", "/x/linuxarm64/steam-launch-wrapper.real", "--oom-score-adjust", "900", "--",
            "/x/steamrtarm64/reaper", "SteamLaunch", "AppId=100", "--",
            os.path.join(f, "fex-compat-tool"), "waitforexitandrun", "--",
            "/x/steamapps/common/SteamLinuxRuntime_soldier/_v2-entry-point", "--verb=waitforexitandrun", "--",
            os.path.join(GAME, "game.bin")]


def run(f, env=None, profile="", family="other", entry_kind="arm64", argv=None):
    open(CONF, "w").write("GPU_FAMILY=%s\nGFX_DEFAULT=auto\n" % family)
    home = tempfile.mkdtemp(dir=TMP)
    if profile:
        put(os.path.join(home, ".config/steam-arm/titles.conf"), "100 %s\n" % profile)
    cd = os.path.join(os.path.dirname(os.path.dirname(f)), "compatdata", "100")
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": "100",
         "T_ARGV": json.dumps(argv or chain(f)), "T_HANDLER": HP, "T_ENTRY": entry_kind, "STEAM_ARM_RENDERER_CHECK": "0",
         "STEAM_COMPAT_INSTALL_PATH": GAME, "STEAM_COMPAT_DATA_PATH": cd,
         "STEAM_COMPAT_GRAPHICS_PROVIDER": "/opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json",
         "LD_PRELOAD": OV64 + ":" + OVARM}
    e.update(env or {})
    r = subprocess.run([sys.executable, DRIVER], env=e, cwd=GAME, capture_output=True, text=True)
    lines = [l for l in r.stdout.splitlines() if l.startswith("RESULT ")]
    if r.returncode or not lines:
        return {"log": r.stdout + r.stderr, "argv": [], "env": {}, "err": "driver failed", "cd": cd}
    res = json.loads(lines[-1][7:])
    res["log"] = r.stdout
    res["cd"] = cd
    res["cfg"] = (res.get("app_config") or {}).get("Config", {})
    res["th"] = (res.get("app_config") or {}).get("ThunksDB", {})
    return res


SOCK = "/run/user/%d/steam-arm-fexserver.sock" % os.getuid()
r = run(FP, env={"STEAM_FEX_MULTIBLOCK": "0"})
check("H1 Python tool: Valve's per-title key from the tool's own function (Multiblock false)",
      r["cfg"].get("Multiblock") is False, r.get("app_config"))
check("H1 own settings that 2.3 wrote into ConfigTemplate: socket, SilentLog, thunks on",
      r["cfg"].get("ServerSocketPath") == SOCK and r["cfg"].get("SilentLog") == "1"
      and r["th"] == {"GL": "1", "Vulkan": "1"}, r.get("app_config"))
check("H1 FEX_APP_CONFIG set to own file (marker for the tool hook)",
      os.path.basename(r["env"].get("FEX_APP_CONFIG", "")).startswith("steam-arm-fex-app-config-"), r["env"])
check("H1 Valve's tool files untouched, no bytecode written into tool folder",
      not os.path.exists(os.path.join(FP, "__pycache__")) and not any(n.endswith(".steam-arm-sha") for n in os.listdir(FP)),
      os.listdir(FP))
i = r["argv"].index(os.path.join(FP, "fex-compat-tool"))
check("H1 LD_PRELOAD placed after the tool's own arguments through env, x86 overlay only",
      r["argv"][i + 1:i + 5] == ["waitforexitandrun", "--", "/usr/bin/env", "LD_PRELOAD=" + OV64]
      and "LD_PRELOAD" not in r["env"], r["argv"])
check("H1 rest of the command unchanged", r["argv"][i + 5:] == chain(FP)[i + 3:], r["argv"])
db = json.load(open(os.path.join(r["cd"], "fex-emu/ThunksDB.json")))
check("H1 FEX tool 2607: thunk paths file in title's compatdata with container paths, Valve's entries kept",
      "steam-arm" in db and "/run/gfx/main/usr/lib/x86_64-linux-gnu/libGL.so.1" in db["DB"]["GL"]["Overlay"]
      and "@PREFIX_LIB@/libGL.so.1" in db["DB"]["GL"]["Overlay"]
      and "/usr/lib/pressure-vessel/overrides/lib/i386-linux-gnu/libvulkan.so.1" in db["DB"]["Vulkan"]["Overlay"], db)

r = run(FP, env={"STEAM_COMPAT_FEX_CONFIG": "TSOEnabled:1"})
check("H2 Python tool, Steam's FEX setting: Valve's 2607 rule (missing keys 0) kept over own thunk default",
      r["cfg"].get("TSOEnabled") == "1" and r["cfg"].get("Multiblock") == "0" and r["th"] == {"GL": "0", "Vulkan": "0"},
      r.get("app_config"))

r = run(FC, env={"STEAM_FEX_MULTIBLOCK": "0"})
check("H3 C++ tool: Valve's key by FEXCompatTool rule (Multiblock 0)", r["cfg"].get("Multiblock") == "0"
      and r["th"] == {"GL": "1", "Vulkan": "1"}, r.get("app_config"))
check("H3 C++ tool: LD_PRELOAD after tool arguments too", "/usr/bin/env" in r["argv"]
      and r["argv"][r["argv"].index("/usr/bin/env") - 1] == "--"
      and r["argv"][r["argv"].index("/usr/bin/env") - 3] == os.path.join(FC, "fex-compat-tool"), r["argv"])
check("H3 FEX tool 2610: no thunk paths file", not os.path.exists(os.path.join(r["cd"], "fex-emu/ThunksDB.json")), r["log"][-400:])
r = run(FC, env={"STEAM_FEX_MULTIBLOCK": "0", "STEAM_COMPAT_FEX_CONFIG": ""})
check("H3 C++ tool, Steam's empty FEX setting: override replaces appinfo keys (FEXCompatTool rule)",
      "Multiblock" not in r["cfg"] and r["th"] == {"GL": "1", "Vulkan": "1"}, r.get("app_config"))
r = run(FC, env={"STEAM_COMPAT_FEX_CONFIG": "ThunksDB_GL:0,TSOEnabled:1"})
check("H3 C++ tool, Steam's FEX setting: GL 0 kept, Vulkan own default", r["th"] == {"GL": "0", "Vulkan": "1"}
      and r["cfg"].get("TSOEnabled") == "1", r.get("app_config"))

uf = os.path.join(TMP, "user-app.json")
put(uf, json.dumps({"Config": {"Multiblock": "1"}, "ThunksDB": {"Vulkan": "0"}}))
r = run(FP, env={"FEX_APP_CONFIG": uf, "STEAM_FEX_MULTIBLOCK": "0"})
check("H4 launch option FEX_APP_CONFIG: its keys win, Valve's keys not added, file untouched",
      r["cfg"].get("Multiblock") == "1" and r["th"].get("Vulkan") == "0" and r["th"].get("GL") == "1"
      and json.load(open(uf)) == {"Config": {"Multiblock": "1"}, "ThunksDB": {"Vulkan": "0"}}, r.get("app_config"))

r = run(FP, profile="gfx=b", family="mali-csf-v10")
check("H5 route B: thunks off survive own default, Mali provider", r["th"].get("GL") in (0, "0")
      and r["th"].get("Vulkan") in (0, "0") and r["env"].get("STEAM_COMPAT_GRAPHICS_PROVIDER") == MALI + "/graphics_provider.json",
      r.get("app_config"))

r = run(FC, env={"LD_PRELOAD": ""})
check("H6 nothing to preload: no env placed, command unchanged", "/usr/bin/env" not in r["argv"] and r["argv"][1:] == chain(FC)[1:],
      r["argv"])
cd2 = os.path.join(SP, "steamapps/compatdata/100/fex-emu/ThunksDB.json")
put(cd2, json.dumps({"DB": {}}))
r = run(FP)
check("H7 user's own ThunksDB.json in compatdata left as it is", json.load(open(cd2)) == {"DB": {}}
      and "own ThunksDB.json of this title left as it is" in r["log"], r["log"][-400:])
os.unlink(cd2)
run(FP)
put(os.path.join(FP, "VERSIONS.txt"), "FEX describe\tFEX-2610\n")
r = run(FP)
check("H7 tool updated to 2610: own thunk paths file removed", not os.path.exists(cd2), r["log"][-400:])

own = tempfile.mkstemp(prefix="steam-arm-fex-app-config-", suffix=".json", dir="/tmp")[1]
r = run(FP, entry_kind="tool", env={"FEX_APP_CONFIG": own})
os.unlink(own)
check("H8 tool hook after stand-in: handler steps out with an exception the tool block catches",
      (r.get("err") or "").startswith("RuntimeError"), r)

# ---------------- steam-arm-run.py --client arm64 ----------------
RP = os.path.join(TMP, "run.py")
HREC = os.path.join(TMP, "handler-rec.py")
put(HREC, "import os, sys\nprint('steam-arm: entry=%s x86=%s preload=%s' % (ENTRY, CLIENT_X86, os.environ.get('LD_PRELOAD')))\n")
put(RP, R.replace('HANDLER = "/usr/local/lib/steam-arm-handler.py"', "HANDLER = %r" % HREC))
r = subprocess.run([sys.executable, RP, "--client", "arm64", "--preload", "/a.so", "--", "/bin/sh", "-c", "exit 3"],
                   capture_output=True, text=True)
logs = sorted((os.path.getmtime(p), p) for p in
              ("/tmp/" + n for n in os.listdir("/tmp") if n.startswith("steam-arm-run-") and n.endswith(".log")))
text = open(logs[-1][1]).read() if logs else ""
check("R1 run helper, arm64: handler gets ENTRY arm64 and the game's LD_PRELOAD", "entry=arm64 x86=False preload=/a.so" in text
      and "steam-arm: entry: launch wrapper" in text, text)
check("R1 exit status of Valve's wrapper passed on; log owner only", r.returncode == 3 and logs
      and stat.S_IMODE(os.stat(logs[-1][1]).st_mode) == 0o600, (r.returncode, r.stderr))
if logs:
    os.unlink(logs[-1][1])

shutil.rmtree(TMP, ignore_errors=True)
print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
