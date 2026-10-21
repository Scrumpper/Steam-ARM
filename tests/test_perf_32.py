#!/usr/bin/env python3
"""Frame pacing readout and still-working notice: steam-arm-perf.py extracted from the installer under test (SARM_INST
picks another file). Game environment lines, percentile math on synthetic frame-time lists, overlay CSV and Gallium dump
parsing (header, NUL hole, truncation), watch lines and log cap, still-working state machine with stand-in processes
(reaper by argv[0], sleeping, busy, fake fossilize_replay, fake shader cache growth, readout file growth). No GPU use.
Internal; not for release zips."""
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST  # noqa: E402

SRC = open(INST).read()
TMP = tempfile.mkdtemp(prefix="sarm32-perf-")
FAILS, PASSES = [], [0]


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


P = heredoc("cat > /usr/local/lib/steam-arm-perf.py <<'PERFPY'\n", "PERFPY")
check("P0 helper heredoc present", bool(P))
if not P:
    print("0 PASS, 1 FAIL")
    sys.exit(1)
HELPER = os.path.join(TMP, "steam-arm-perf.py")
open(HELPER, "w").write(P)
M = {"__name__": "perf"}
exec(compile(P, HELPER, "exec"), M)


def run(*a, **kw):
    return subprocess.run([sys.executable, HELPER] + list(a), capture_output=True, text=True, timeout=kw.get("timeout", 60),
                          input=kw.get("input"), env=kw.get("env"))


# --- game environment lines ---
d = os.path.join(TMP, "perf")
os.makedirs(os.path.join(d, "gl"))
open(os.path.join(d, "vk-frames.csv"), "w").write("old\n")
open(os.path.join(d, "gl", "frametime_(ms)"), "w").write("1\n")
os.environ.pop("VK_LOADER_LAYERS_ENABLE", None)
out = M["env_lines"](d, layer=True, gl=True)
check("E1 both sources: layer enable, overlay config (hidden, per present, frame_timing), Gallium dump hidden per frame",
      out == ["VK_LOADER_LAYERS_ENABLE=VK_LAYER_MESA_overlay",
              "VK_LAYER_MESA_OVERLAY_CONFIG=no_display,output_file=%s/vk-frames.csv,fps_sampling_period=1,frame_timing" % d,
              "GALLIUM_HUD=frametime", "GALLIUM_HUD_PERIOD=0", "GALLIUM_HUD_VISIBLE=false", "GALLIUM_HUD_DUMP_DIR=%s/gl" % d], out)
check("E1 old files of earlier session removed, folders kept",
      not os.path.exists(os.path.join(d, "vk-frames.csv")) and os.listdir(os.path.join(d, "gl")) == [])
check("E1 every line NAME=VALUE without spaces (launcher splits on spaces)", all("=" in l and " " not in l for l in out))
os.environ["VK_LOADER_LAYERS_ENABLE"] = "VK_LAYER_x,VK_LAYER_MESA_overlay"
out = M["env_lines"](d, layer=True, gl=False)
check("E2 existing layer list kept, overlay once at end; no Gallium lines without Gallium driver",
      out[0] == "VK_LOADER_LAYERS_ENABLE=VK_LAYER_x,VK_LAYER_MESA_overlay" and len(out) == 2, out)
os.environ.pop("VK_LOADER_LAYERS_ENABLE")
check("E3 no source: no lines", M["env_lines"](d, layer=False, gl=False) == [])
r = run("env", os.path.join(TMP, "perf2"))
check("E4 CLI env: exit 0 with lines, or 1 with none (host dependent), folder made",
      (r.returncode == 0) == bool(r.stdout.strip()) and os.path.isdir(os.path.join(TMP, "perf2", "gl")), r)

# --- percentile math ---
summary = M["summary"]
s = summary([float(x) for x in range(1, 101)])
check("S1 1..100 ms: p50 50, p95 95, p99 99, max 100 (nearest rank)",
      (s["frames"], s["p50"], s["p95"], s["p99"], s["max"]) == (100, 50, 95, 99, 100), s)
check("S1 over 25 ms 75, over 50 ms 50 (strictly over)", (s["over25"], s["over50"]) == (75, 50), s)
s = summary([16.7] * 60)
check("S2 even pacing: every percentile equal, no slow interval",
      s["p50"] == s["p95"] == s["p99"] == s["max"] == 16.7 and s["over25"] == s["over50"] == 0, s)
s = summary([16.7] * 97 + [33.4, 33.4, 120.0])
check("S3 97 even + 2 x 33.4 + 120: p95 16.7, p99 33.4, max 120, over 25 = 3, over 50 = 1",
      (s["p95"], s["p99"], s["max"], s["over25"], s["over50"]) == (16.7, 33.4, 120.0, 3, 1), s)
s = summary([40.0, 10.0, 30.0, 20.0])
check("S4 unsorted input of 4: p50 20, p95 40", (s["p50"], s["p95"], s["frames"]) == (20.0, 40.0, 4), s)
check("S5 single frame: all percentiles that frame", summary([25.0])["p99"] == 25.0)
check("S6 no frames or only zero: None", summary([]) is None and summary([0.0, -1.0]) is None)
check("S7 line format", M["fmt"](summary([16.7] * 97 + [33.4, 33.4, 120.0])) ==
      "100 frames, interval p50 16.7 p95 16.7 p99 33.4 max 120.0 ms, over 25 ms 3, over 50 ms 1")
r = run("stats", input="16.7\n16.7\n50.5\nbad\n")
check("S8 CLI stats from stdin, bad line skipped", r.returncode == 0 and r.stdout.strip().startswith("3 frames,") and
      "max 50.5 ms" in r.stdout and "over 50 ms 1" in r.stdout, r)
r = run("stats", input="")
check("S8 CLI stats without frames: exit 1", r.returncode == 1 and r.stdout.strip() == "no frames", r)

# --- source parsing ---
col = [3]
v = M["vk_values"](["device, format, fps, frame_timing(us)", "0, 0, 60.00, 16667", "0, 0, 30.00, 33333", "junk"], col)
check("V1 overlay CSV: header picks column, us -> ms, junk skipped", [round(x, 3) for x in v] == [16.667, 33.333], v)
v = M["vk_values"](["frame_timing(us), fps", "20000, 50"], col)
check("V2 column follows header order", v == [20.0] and col[0] == 0, (v, col))
check("V3 Gallium dump: one value per line, time prefix form too",
      M["gl_values"](["2.477", "10.39", "12: 16.5", "x"]) == [2.477, 10.39, 16.5])
f = os.path.join(TMP, "tail.csv")
t = M["Tail"](f)
check("T1 missing file: no lines", t.lines() == [])
open(f, "w").write("a\nb\npart")
check("T2 complete lines only, partial kept", t.lines() == ["a", "b"])
open(f, "a").write("ial\nc\n")
check("T3 partial joined on next read", t.lines() == ["partial", "c"])
with open(f, "r+b") as fh:
    fh.truncate(0)
    fh.seek(10)
    fh.write(b"x\n")
check("T4 truncated by second writer: restart, NUL hole skipped", t.lines() == ["x"])
os.unlink(f)
open(f, "w").write("new\n")
check("T5 replaced file (new inode): read from start", t.lines() == ["new"])

# --- watch lines and log ---
wd = os.path.join(TMP, "w")
os.makedirs(os.path.join(wd, "gl"))
open(os.path.join(wd, "vk-frames.csv"), "w").write("device, format, fps, frame_timing(us)\n" +
                                                      "0, 0, 60, 16700\n" * 98 + "0, 0, 20, 50100\n0, 0, 10, 100000\n")
open(os.path.join(wd, "gl", "frametime_(ms)"), "w").write("16.7\n" * 10)
log = os.path.join(TMP, "state", "perf.log")
r = subprocess.run([sys.executable, "-c", "import sys; exec(open(sys.argv[1]).read().replace('if __name__ == \"__main__\":', "
                    "'if False:')); watch(sys.argv[2], sys.argv[3], rounds=1)", HELPER, wd, log],
                   capture_output=True, text=True, timeout=60)
lines = r.stdout.splitlines()
check("W1 one stdout line per source with frames", len(lines) == 2 and lines[0].startswith("steam-arm: perf app ") and
      " vulkan: 100 frames, interval p50 16.7 p95 16.7 p99 50.1 max 100.0 ms, over 25 ms 2, over 50 ms 2" in lines[0]
      and " opengl: 10 frames," in lines[1], r)
lg = open(log).read().splitlines() if os.path.exists(log) else []
check("W1 log lines carry date and time, same text", len(lg) == 2 and lg[0][:4].isdigit() and lg[0][20:] == lines[0][len("steam-arm: perf "):],
      lg)
r = subprocess.run([sys.executable, "-c", "import sys; exec(open(sys.argv[1]).read().replace('if __name__ == \"__main__\":', "
                    "'if False:')); watch(sys.argv[2], sys.argv[3], rounds=2)", HELPER, wd, log],
                   capture_output=True, text=True, timeout=60)
check("W2 second round without new frames: no line (fresh process reads files once)", len(r.stdout.splitlines()) == 2, r)
open(log, "w").write("".join("old %d\n" % i for i in range(400)))
M["log_line"](log, "newest")
lg = open(log).read().splitlines()
check("W3 log cap: at 400 lines trimmed to newest 200 with new line", len(lg) == 200 and lg[-1] == "newest" and lg[0] == "old 201",
      (len(lg), lg[:1]))

# --- still-working state machine ---
cls = M["classify"]
base = [(0.0, 5.0, 100, 1000, "R", False), (5.0, 7.0, 200, 1000, "R", False), (10.0, 9.0, 300, 1000, "R", False)]
check("C1 window not full yet: no verdict", cls(base[:2]) is None)
check("C2 CPU busy, no cache growth: loading", cls(base) == "loading")
check("C3 cache grew over window: shaders", cls(base[:2] + [(10.0, 9.0, 300, 5000, "R", False)]) == "shaders")
check("C4 fossilize_replay running: shaders at once", cls([(0.0, 1.0, 0, 0, "S", True)]) == "shaders")
check("C5 under 0.1 s CPU in 10 s: stuck", cls([(0.0, 5.0, 0, 0, "S", False), (10.0, 5.05, 0, 0, "S", False)]) == "stuck")
dd = [(0.0, 5.0, 100, 0, "D", False), (5.0, 6.0, 100, 0, "D", False), (10.0, 7.0, 100, 0, "D", False)]
check("C6 busiest process in D for 10 s, no reads: stuck", cls(dd) == "stuck")
check("C7 D with reads going on: loading", cls(dd[:2] + [(10.0, 7.0, 900, 0, "D", False)]) == "loading")

BIN = os.path.join(TMP, "bin")
os.makedirs(BIN)
open(os.path.join(BIN, "fossilize_replay"), "w").write("#!/bin/sh\nsleep \"$1\"\n")
os.chmod(os.path.join(BIN, "fossilize_replay"), 0o755)
HOME = os.path.join(TMP, "home")
os.makedirs(os.path.join(HOME, ".cache", "mesa_shader_cache"))


def still(script, after, extra=(), timeout=60):
    """Reaper stand-in (argv[0] 'reaper SteamLaunch AppId=4242') running script; still output lines and seconds."""
    rp = subprocess.Popen(["bash", "-c", "exec -a 'reaper SteamLaunch AppId=4242' bash -c \"$0\"", script],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    code = ("import sys; exec(open(sys.argv[1]).read().replace('if __name__ == \"__main__\":', 'if False:')); "
            "still(int(sys.argv[2]), after=float(sys.argv[3]), home=sys.argv[4], perf=sys.argv[5] or None, poll=0.5, "
            "nogpu=float(sys.argv[6]))")
    t0 = time.time()
    args = [sys.executable, "-c", code, HELPER, str(rp.pid), str(after), HOME] + list(extra)
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        out = r.stdout.split("\n")
    except subprocess.TimeoutExpired:
        out = ["timeout"]
    rp.terminate()
    try:
        rp.wait(5)
    except subprocess.TimeoutExpired:
        rp.kill()
    subprocess.run(["pkill", "-TERM", "-f", TMP + "/bin/fossilize_replay"], capture_output=True)
    return [l for l in out if l], time.time() - t0


cmdline = M["cmdline"]
rp = subprocess.Popen(["bash", "-c", "exec -a 'reaper SteamLaunch AppId=4242' sleep 5"])
time.sleep(0.3)
check("R0 reaper stand-in visible by argv[0]", "reaper SteamLaunch AppId=4242" in cmdline(rp.pid))
rp.terminate()
rp.wait()

out, dt = still("sleep 1", 10, ("", "60"), timeout=20)
check("R1 game ends before wait (reaper left as zombie of its parent): gone, no state", out == ["gone"] and dt < 10, (out, dt))
pd = os.path.join(TMP, "pf")
os.makedirs(os.path.join(pd, "gl"))
out, dt = still("sleep 2; for i in $(seq 40); do echo 16.7 >> %s/gl/frametime_x; done; sleep 30" % pd, 10, (pd, "60"))
check("R2 readout file grows: frame, before wait ends", out == ["frame"] and dt < 10, (out, dt))
out, dt = still("%s/bin/fossilize_replay 30 & sleep 30" % TMP, 1, ("", "6"), timeout=40)
check("R3 fossilize_replay of this account: state shaders", out[:1] and out[0].startswith("state shaders "), out)
check("R3 nosignal after no GPU client for nogpu seconds", out[-1:] == ["nosignal"], out)
cache = os.path.join(HOME, ".cache", "mesa_shader_cache")
out, dt = still("for i in $(seq 40); do head -c 4096 /dev/zero > %s/f$i; sleep 0.5; done" % cache, 1, ("", "13"))
check("R4 shader cache grows: state shaders once window is full", any(l.startswith("state shaders ") for l in out), out)
out, dt = still("sleep 30", 1, ("", "13"))
check("R5 no CPU use for 10 s: state stuck, then nosignal (no GPU client)", out[:1] and out[0].startswith("state stuck ")
      and out[-1] == "nosignal", out)
out, dt = still("timeout 30 sh -c 'while :; do :; done'", 1, ("", "13"))
check("R6 busy on CPU: state loading", out[:1] and out[0].startswith("state loading "), out)
r = run("still", "--reaper", "x")
check("R7 CLI: bad reaper pid refused with usage", r.returncode != 0 and "Usage" in r.stderr, r)
check("R8 never signals game: no kill call in helper", "os.kill(" not in P and "signal." not in P)

shutil.rmtree(TMP, ignore_errors=True)
print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
