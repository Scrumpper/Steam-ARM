#!/usr/bin/env python3
"""Steam ARM 3.0 run record (B3): handler start line and steam-arm-run.py exit line in
~/.local/state/steam-arm/runs.log; off by default, on with RUN_HISTORY=on or a title profile autotune key; values
only (no paths, names, profile values); owner-only file, no links followed; newest 200 lines kept. Handler and run
helper extracted from the installer under test (SARM_INST picks another file); settings file and Mali tree paths
rewritten in the extracts only. Internal; not for release zips."""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST  # noqa: E402
TMP = tempfile.mkdtemp(prefix="sarm30-runrec-")
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


H = heredoc("cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n", "HANDLERPY")
R = heredoc("cat > /usr/local/lib/steam-arm-run.py <<'RUNPY'\n", "RUNPY")
check("B0 installer writes handler and run helper", bool(H) and bool(R))
if not (H and R):
    print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
    sys.exit(1)

ELF = b"\x7fELF\x02\x01\x01" + b"\0" * 57
CONF = os.path.join(TMP, "steam-arm.conf")
MALI = os.path.join(TMP, "mali-tree")
HP = os.path.join(TMP, "handler.py")
put(HP, H.replace('"/etc/steam-arm/steam-arm.conf"', repr(CONF))
    .replace('MALI_ROOT = "/opt/fex-rootfs/Ubuntu_24_04-mali"', "MALI_ROOT = %r" % MALI))
RP = os.path.join(TMP, "run.py")
put(RP, R.replace('HANDLER = "/usr/local/lib/steam-arm-handler.py"', "HANDLER = %r" % HP))

S = os.path.join(TMP, "Steam")
F = os.path.join(S, "steamapps/common/FEX-Emu")
put(os.path.join(F, "toolmanifest.vdf"), '"manifest"\n{\n  "commandline" "/fex-compat-tool %verb% --"\n}\n')
put(os.path.join(F, "emulator.json"), '{"emulator_v0": {"argv": "./usr/bin/FEX", "main_argv": "./FEXCompatTool"}}\n')
put(os.path.join(F, "VERSIONS.txt"), "FEX describe\tFEX-2607-76-g37265b1\n")
put(os.path.join(F, "fex-compat-tool"), open(os.path.join(HERE, "fixtures/fex-tool/fex-compat-tool"), "rb").read(), 0o755)
put(os.path.join(F, "unshare.py"), "def unshare(flags):\n    pass\n")
put(os.path.join(F, "FEXCompatTool"), ELF, 0o755)
put(os.path.join(F, "usr/share/fex-emu/ThunksDB.json"), json.dumps({"DB": {}}))
GAME = os.path.join(S, "steamapps/common/Game")
put(os.path.join(GAME, "game.bin"), ELF, 0o755)
# stands in for Valve's launch wrapper: exit status from T_RC, or a signal from T_SIG
WR = os.path.join(TMP, "steam-launch-wrapper.real")
put(WR, '#!/bin/sh\n[ -n "$T_SIG" ] && kill -"$T_SIG" $$\nexit "${T_RC:-0}"\n', 0o755)


def run(conf="", profile="", rc=0, sig="", home=None, appid="100"):
    open(CONF, "w").write("GPU_FAMILY=other\nGFX_DEFAULT=auto\n" + conf)
    home = home or tempfile.mkdtemp(dir=TMP)
    if profile:
        put(os.path.join(home, ".config/steam-arm/titles.conf"), "%s %s\n" % (appid, profile))
    argv = ["--client", "arm64", "--preload", "", "--", WR, "--oom-score-adjust", "900", "--",
            "/x/steamrtarm64/reaper", "SteamLaunch", "AppId=" + appid, "--", os.path.join(F, "fex-compat-tool"),
            "waitforexitandrun", "--", "/x/steamapps/common/SteamLinuxRuntime_soldier/_v2-entry-point",
            "--verb=waitforexitandrun", "--", os.path.join(GAME, "game.bin")]
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "SteamAppId": appid, "USER": "tester",
         "STEAM_ARM_RENDERER_CHECK": "0", "STEAM_COMPAT_INSTALL_PATH": GAME,
         "STEAM_COMPAT_DATA_PATH": os.path.join(S, "steamapps/compatdata", appid),
         "STEAM_COMPAT_GRAPHICS_PROVIDER": "/opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json",
         "T_RC": str(rc), "T_SIG": sig}
    p = subprocess.Popen([sys.executable, RP] + argv, env=e, cwd=GAME, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    p.communicate()
    lp = "/tmp/steam-arm-run-%d.log" % p.pid
    log = open(lp).read() if os.path.exists(lp) else ""
    if os.path.exists(lp):
        os.unlink(lp)
    rp = os.path.join(home, ".local/state/steam-arm/runs.log")
    return {"rc": p.returncode, "pid": p.pid, "log": log, "home": home, "runs": rp,
            "rows": open(rp).read().splitlines() if os.path.exists(rp) else None}


def kv(row):
    return dict(w.split("=", 1) for w in row.split())


r = run()
check("B1 default: no run record (RUN_HISTORY absent, no autotune key)", r["rows"] is None
      and not os.path.exists(os.path.join(r["home"], ".local/state")) and "run record" not in r["log"], r["log"][-600:])
check("B1 handler log: start time, exit status and run time lines", "steam-arm: start: 20" in r["log"]
      and "steam-arm: exit status 0" in r["log"] and "steam-arm: run time: " in r["log"], r["log"][-600:])
r = run(conf="RUN_HISTORY=off\n")
check("B1 RUN_HISTORY=off: no run record", r["rows"] is None, r["log"][-400:])

r = run(conf="RUN_HISTORY=on\n", rc=3)
rows = r["rows"] or []
check("B2 RUN_HISTORY=on: start and exit line, log names the reason", len(rows) == 2 and rows[0].startswith("t=")
      and "steam-arm: run record: on (RUN_HISTORY=on)" in r["log"], (rows, r["log"][-600:]))
s, x = (kv(rows[0]), kv(rows[1])) if len(rows) == 2 else ({}, {})
check("B2 start line: event, app, run id, entry, client, route values, FEX tool version and kind",
      s.get("ev") == "start" and s.get("app") == "100" and s.get("run") == str(r["pid"]) and s.get("entry") == "wrapper"
      and s.get("client") == "arm64" and s.get("gfx") == "a" and s.get("overlay") == "x86" and s.get("fex") == "FEX-2607"
      and s.get("tool") == "python" and s.get("proton") == "-" and "mesa" in s, s)
check("B2 exit line: same run id, status, seconds, renderer", x.get("ev") == "exit" and x.get("run") == str(r["pid"])
      and x.get("status") == "3" and x.get("secs", "").isdigit() and x.get("renderer") == "unknown" and r["rc"] == 3, x)
check("B2 runs.log owner only, folder owner only", stat.S_IMODE(os.stat(r["runs"]).st_mode) == 0o600
      and stat.S_IMODE(os.stat(os.path.dirname(r["runs"])).st_mode) == 0o700)
check("B2 record holds no path, home or account name", all("/" not in l and "tester" not in l and TMP not in l
                                                            for l in rows), rows)

r = run(conf="RUN_HISTORY=on\n", sig="SEGV")
x = kv(r["rows"][-1]) if r["rows"] else {}
check("B3 signal end: status sig11, run helper exit 139", x.get("status") == "sig11" and r["rc"] == 139, (x, r["rc"]))

r = run(profile="autotune=fix env=SECRET_NAME=hunter2;OTHER=1 multiblock=off")
rows = r["rows"] or []
s = kv(rows[0]) if rows else {}
check("B4 title autotune key, RUN_HISTORY off: record on for that title", len(rows) == 2
      and "steam-arm: run record: on (title autotune)" in r["log"], (rows, r["log"][-600:]))
check("B4 profile: key names only, values never recorded", s.get("profile") == "autotune,env,multiblock"
      and s.get("multiblock") == "off" and not any("hunter2" in l or "SECRET" in l for l in rows), rows)
r = run(profile="autotune=off")
check("B4 autotune=off: no record", r["rows"] is None, r["log"][-300:])

home = tempfile.mkdtemp(dir=TMP)
put(os.path.join(home, ".local/state/steam-arm/runs.log"),
    "".join("t=2026-01-01T00:00:00Z ev=start app=9 run=%d\n" % i for i in range(250)), 0o600)
r = run(conf="RUN_HISTORY=on\n", home=home)
rows = r["rows"] or []
check("B5 cap: newest 200 lines kept, new start and exit last", len(rows) == 200 and rows[0].endswith("run=52")
      and kv(rows[-2]).get("ev") == "start" and kv(rows[-1]).get("ev") == "exit", (len(rows), rows[:1], rows[-2:]))

home = tempfile.mkdtemp(dir=TMP)
tgt = os.path.join(TMP, "elsewhere.txt")
put(tgt, "keep\n")
os.makedirs(os.path.join(home, ".local/state/steam-arm"))
os.symlink(tgt, os.path.join(home, ".local/state/steam-arm/runs.log"))
r = run(conf="RUN_HISTORY=on\n", home=home)
check("B6 runs.log a link: not followed, target unchanged, log says not written, game still starts",
      open(tgt).read() == "keep\n" and "run record: not written" in r["log"] and "steam-arm: exit status 0" in r["log"]
      and "exit line not written" not in r["log"], r["log"][-600:])

# tool entry (FEX tool edit fallback): start line only, entry=tool
DRIVER = os.path.join(TMP, "driver.py")
put(DRIVER, "import os, runpy, sys\nsys.argv = ['fex-compat-tool', 'waitforexitandrun', '--', 'game']\n"
            "runpy.run_path(%r, init_globals={'ENTRY': 'tool'})\n" % HP)
open(CONF, "w").write("GPU_FAMILY=other\nRUN_HISTORY=on\n")
home = tempfile.mkdtemp(dir=TMP)
p = subprocess.run([sys.executable, DRIVER], env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home,
                   "SteamAppId": "100", "STEAM_ARM_RENDERER_CHECK": "0", "STEAM_COMPAT_INSTALL_PATH": GAME},
                   cwd=GAME, capture_output=True, text=True)
rp = os.path.join(home, ".local/state/steam-arm/runs.log")
rows = open(rp).read().splitlines() if os.path.exists(rp) else []
check("B7 FEX tool edit entry: start line with entry=tool, no exit line", len(rows) == 1
      and kv(rows[0]).get("entry") == "tool" and kv(rows[0]).get("ev") == "start", (rows, p.stdout[-400:], p.stderr[-400:]))

# consumers: menu reads the same file name and keys
CFG = SRC[SRC.index("menu_app(){ cat <<'STEAMARMCONFIG'\n"):]
check("B8 menu reads runs.log at the handler's path", "SA_RUNS_REL=.local/state/steam-arm/runs.log" in CFG
      and 'os.path.join(os.path.expanduser("~"), ".local/state/steam-arm/runs.log")' in H)
check("B8 backup: runs.log not a backup part; RUN_HISTORY switch is a setup key", ".local/state" not in
      CFG[CFG.index("bk_path(){"):CFG.index("bk_expand(){")] and "CPU_NOTICE RUN_HISTORY SNAPSHOT_KEEP UPDATE_CHECK_ON_OPEN X87_CLIENT CLIENT_LIGHT CLIENT_GPU CEF_HANG_KILLS CLIENT_TSO" in CFG)

shutil.rmtree(TMP, ignore_errors=True)
print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
