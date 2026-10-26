#!/usr/bin/env python3
"""Steam ARM 3.0 game environment file (A1): steam-arm-entry.py gfx / restore / status on Valve's per-game environment
file (<home>/.config/steam/env/gfx.txt), launcher choice between that file and exports (stubbed helper), renderer
check without a driver library (title loading, waiting or stuck: no CPU verdict). Helpers extracted from the installer
under test (SARM_INST picks another file). Internal; not for release zips."""
import ast
import os
import re
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST  # noqa: E402
TMP = tempfile.mkdtemp(prefix="sarm30-gameenv-")
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
    with open(path) as f:
        return f.read()


E = heredoc("cat > /usr/local/lib/steam-arm-entry.py <<'ENTRYPY'\n", "ENTRYPY")
H = heredoc("cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n", "HANDLERPY")
L = heredoc("cat > /usr/local/bin/steam-arm <<'LAUNCHER'\n", "LAUNCHER")
check("G0 installer writes entry helper, handler, launcher", bool(E) and bool(H) and bool(L))
if not (E and H and L):
    print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
    sys.exit(1)
ENTRY = os.path.join(TMP, "entry.py")
put(ENTRY, E)


def entry(*a):
    r = subprocess.run([sys.executable, ENTRY] + list(a), capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


BEGIN = "# Steam ARM begin: lines up to end mark rewritten at each Steam ARM start; own lines go below"
END = "# Steam ARM end"
ELF = b"\x7fELF\x02\x01\x01" + b"\0" * 57


def home(wrapper=b"x %s/.config/steam/env/gfx.txt y", real=True, name="h"):
    """Client home with a launch wrapper (Valve's program as .real behind a stand-in, or in place)."""
    h = tempfile.mkdtemp(dir=TMP, prefix=name)
    s = os.path.join(h, ".local/share/Steam")
    w = os.path.join(s, "linuxarm64/steam-launch-wrapper")
    if wrapper is not None:
        if real:
            put(w, "#!/bin/sh\n# steam-arm stand-in\n", 0o755)
            put(w + ".real", ELF + wrapper, 0o755)
        else:
            put(w, ELF + wrapper, 0o755)
    return h, s, os.path.join(h, ".config/steam/env/gfx.txt")


# ---------------- write ----------------
h, s, g = home()
rc, out = entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
check("G1 new file: own block, rc 0, mode 644, logged", rc == 0 and rd(g) == "%s\nSTEAM_ARM_VK_SPOOF=1\n%s\n" % (BEGIN, END)
      and stat.S_IMODE(os.stat(g).st_mode) == 0o644 and "game environment file: STEAM_ARM_VK_SPOOF=1" in out, (rc, out))
check("G1 marks hold no '=' (Valve's wrapper reads NAME=VALUE lines, skips others)", "=" not in BEGIN and "=" not in END)
ino = os.stat(g).st_ino
rc, out = entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
check("G2 same lines again: file untouched, no output", rc == 0 and out == "" and os.stat(g).st_ino == ino, out)

h, s, g = home()
put(g, "# mine\nFOO=1\n%s\nSTEAM_ARM_VK_SPOOF=1\n%s\nBAR=a=b\n" % (BEGIN, END), 0o640)
rc, out = entry("gfx", s, "DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1", "STEAM_ARM_VK_SPOOF=1")
check("G3 person's lines kept in order after own block (later lines win), file mode kept",
      rc == 0 and rd(g) == "%s\nDISABLE_VK_LAYER_VALVE_steam_fossilize_1=1\nSTEAM_ARM_VK_SPOOF=1\n%s\n# mine\nFOO=1\nBAR=a=b\n"
      % (BEGIN, END) and stat.S_IMODE(os.stat(g).st_mode) == 0o640, rd(g))
rc, out = entry("gfx", s)
check("G4 no lines: block removed, person's lines kept", rc == 0 and rd(g) == "# mine\nFOO=1\nBAR=a=b\n"
      and "Steam ARM lines removed" in out, rd(g))
rc, out = entry("gfx", s)
check("G4 no block, no lines: nothing written, no output", rc == 0 and out == "" and rd(g) == "# mine\nFOO=1\nBAR=a=b\n", out)

h, s, g = home()
entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
rc, out = entry("gfx", s)
check("G5 block only: file and empty env folders removed", rc == 0 and not os.path.exists(g)
      and not os.path.exists(os.path.join(h, ".config/steam")) and os.path.isdir(os.path.join(h, ".config")), out)

h, s, g = home()
put(g, "%s\nSTEAM_ARM_VK_SPOOF=1\nDISABLE_VK_LAYER_VALVE_steam_fossilize_1=1\nMINE=1\n" % BEGIN)
rc, out = entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
check("G6 end mark gone: own-name lines after begin mark replaced, person's line kept",
      rc == 0 and rd(g) == "%s\nSTEAM_ARM_VK_SPOOF=1\n%s\nMINE=1\n" % (BEGIN, END), rd(g))

h, s, g = home(wrapper=b"old wrapper without the user file")
put(g, "%s\nSTEAM_ARM_VK_SPOOF=1\n%s\nMINE=1\n" % (BEGIN, END))
rc, out = entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
check("G7 launch wrapper does not read the file: rc 1 (launcher exports), stale block removed",
      rc == 1 and rd(g) == "MINE=1\n" and "not read by Valve's launch wrapper" in out, (rc, out, rd(g)))
h, s, g = home(wrapper=None)
rc, out = entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
check("G7 no launch wrapper yet (first start): rc 1, no file", rc == 1 and not os.path.exists(g), out)
h, s, g = home(real=False)
rc, out = entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
check("G7 Valve's program in place (no stand-in): its own text checked, rc 0", rc == 0 and "STEAM_ARM_VK_SPOOF=1" in rd(g), out)

h, s, g = home()
os.makedirs(os.path.dirname(g))
tgt = os.path.join(h, "elsewhere.txt")
put(tgt, "X=1\n")
os.symlink(tgt, g)
rc, out = entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
check("G8 file is a link: left as it is, rc 1", rc == 1 and os.path.islink(g) and rd(tgt) == "X=1\n", out)
h, s, g = home()
rc, out = entry("gfx", s, "NOT A LINE", "A=1")
check("G9 malformed line: rc 1, nothing written", rc == 1 and not os.path.exists(g) and "not NAME=VALUE" in out, out)

# ---------------- restore / status ----------------
h, s, g = home()
put(g, "MINE=1\n")
entry("gfx", s, "STEAM_ARM_VK_SPOOF=1")
rc, out = entry("status", s)
check("G10 status: own lines and count of other lines", "game environment file: Steam ARM lines: STEAM_ARM_VK_SPOOF=1, other lines: 1"
      in out, out)
rc, out = entry("restore", s)
check("G11 restore (removal): own block out, person's line kept, wrapper back", rc == 0 and rd(g) == "MINE=1\n"
      and "Steam ARM lines removed" in out, (out, rd(g)))
rc, out = entry("status", s)
check("G10 status without own lines", "game environment file: no Steam ARM lines, other lines: 1" in out, out)
h, s, g = home()
rc, out = entry("status", s)
check("G10 status without file", "game environment file: none" in out, out)

# ---------------- installer wiring ----------------
check("G12 launcher: game-only lines through entry helper, exports only when not written",
      'out=$(python3 /usr/local/lib/steam-arm-entry.py gfx "$S" $GAMEENV 2>&1) && GFXOK=1' in L
      and '[ "$GFXOK" = 1 ] || for v in $GAMEENV; do export "$v"; done' in L)
check("G12 launcher: no direct export of vk-spoof or fossilize switch",
      "export STEAM_ARM_VK_SPOOF" not in L and "export DISABLE_VK_LAYER_VALVE_steam_fossilize_1" not in L)
check("G12 launcher: settings launch options may override stay exports (D3D8, Raspberry Pi WineD3D)",
      'export PROTON_DXVK_D3D8="${PROTON_DXVK_D3D8:-1}"' in L and "export PROTON_USE_WINED3D=1 STEAM_ARM_D3D_DEFAULT=wined3d" in L)
check("G12 removal: entry restore (block out) as game account", 'as_user python3 /usr/local/lib/steam-arm-entry.py restore' in SRC)
check("G12 own names list matches launcher lines", re.search(r'GFX_NAMES = \("DISABLE_VK_LAYER_VALVE_steam_fossilize_1", "STEAM_ARM_VK_SPOOF"[,)]', E)
      and "GAMEENV=DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1" in L and "STEAM_ARM_VK_SPOOF=1\"" in L)

# launcher fragment with stubbed helper: native client written / not written, x86 client
a = L.index("NOSHADERS=-noshaders; GAMEENV=")
b = L.index('[ "$GFXOK" = 1 ] || for v in $GAMEENV; do export "$v"; done')
b = L.index("\n", b) + 1
frag = L[a:b]
BIN = os.path.join(TMP, "bin")
CALLS = os.path.join(TMP, "calls.txt")
put(os.path.join(BIN, "python3"), "#!/bin/sh\necho \"$*\" >> %s\nexit ${STUB_RC:-0}\n" % CALLS, 0o755)
put(os.path.join(TMP, "layer.json"), "{}")
frag = frag.replace("/usr/share/vulkan/implicit_layer.d/VkLayer_steam_arm_spoof.json", os.path.join(TMP, "layer.json"))
SH = os.path.join(TMP, "frag.sh")
put(SH, "comp_on(){ case \",$COMPONENTS_ON,\" in *\",$1,\"*) return 0;; esac; return 1; }\nretired(){ return 1; }\n"
        "llog(){ :; }\nS=/s\n" + frag + "env | grep -E '^(STEAM_ARM_VK_SPOOF|DISABLE_VK_LAYER)' | sort\necho NOSHADERS=$NOSHADERS\n")


def frag_run(client, comps, rc=0):
    if os.path.exists(CALLS):
        os.unlink(CALLS)
    e = {"PATH": BIN + ":/usr/bin:/bin", "CLIENT": client, "COMPONENTS_ON": comps, "STUB_RC": str(rc)}
    r = subprocess.run(["/bin/sh", SH], env=e, capture_output=True, text=True)
    return r.stdout, rd(CALLS) if os.path.exists(CALLS) else ""


o, c = frag_run("arm64", "vk-spoof,shader-cache")
check("G13 native client, file written: helper gets both lines, nothing exported, pre-caching on",
      c.strip() == "/usr/local/lib/steam-arm-entry.py gfx /s DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1 STEAM_ARM_VK_SPOOF=1"
      and "STEAM_ARM_VK_SPOOF" not in o and "NOSHADERS=\n" in o, (o, c))
o, c = frag_run("arm64", "vk-spoof", rc=1)
check("G13 native client, file not written: exports", "STEAM_ARM_VK_SPOOF=1" in o and "DISABLE_VK" not in o
      and "NOSHADERS=-noshaders" in o, (o, c))
o, c = frag_run("x86", "vk-spoof,shader-cache")
check("G13 x86 client (its launch wrapper reads no such file): exports, helper only removes a block",
      c.strip() == "/usr/local/lib/steam-arm-entry.py gfx /s" and "STEAM_ARM_VK_SPOOF=1" in o
      and "DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1" in o, (o, c))
o, c = frag_run("arm64", "")
check("G13 nothing chosen: helper called without lines (block removed)", c.strip() == "/usr/local/lib/steam-arm-entry.py gfx /s"
      and "STEAM_ARM" not in o, (o, c))

# ---------------- renderer check: idle title without GPU memory ----------------
tree = ast.parse(H)
keep = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.Import, ast.ImportFrom))
        or (isinstance(n, ast.Assign) and any(getattr(t, "id", "") in ("GFX_LIB", "GUEST_MESA", "IDLE_CPU", "HELPER_PREFIX",
                                                                        "HELPER_COMM", "NON_GPU_DRM", "FEX_COMM") for t in n.targets))]
ns = {}
exec(compile(ast.Module(body=keep, type_ignores=[]), "handler-defs", "exec"), ns)
V = ns["renderer_verdict"]
check("R1 graphics library, no GPU memory, process idle, 99 checks: no verdict (loading, waiting or stuck)",
      V(("game", True, [], True, set(), False), 99) is None)
v = V(("game", True, [], True, set(), True), 15)
check("R2 busy process without GPU memory, 15 checks: CPU warning", v and "rendering on CPU" in v, v)
check("R3 GPU memory while idle: GPU verdict", V(("game", True, [], True, {"panthor renderD130"}, False), 1)
      .startswith("renderer: GPU (panthor renderD130)"))
check("R4 CPU use unknown (None) or 5-field state: CPU warning after 15 checks (unchanged)",
      "rendering on CPU" in V(("g", True, [], True, set()), 15) and "rendering on CPU" in V(("g", True, [], True, set(), None), 15))
check("R5 idle threshold 0.1 s CPU per s (hung title measured 0.015 s/s, CPU drawing 1 s/s and more)", ns["IDLE_CPU"] == 0.1)
check("R5 CPU seconds without module constants (definitions-only extracts)", ns["proc_cpu"](os.getpid()) is not None)


def watch(cpu_of):
    LOG[:] = []
    ns["proc_cpu"] = cpu_of
    ns["RUN"] = {}
    ns["renderer_watch"](1, limit=0.6, step=0.02)
    return LOG


LOG = []
ns["log"] = lambda *a: LOG.append(" ".join(str(x) for x in a))
ns["descendants"] = lambda root: [4242]
ns["gfx_state"] = lambda pid: ("game", True, [], True, set())
ns["pi_hint"] = lambda: None
ns["notify_cpu"] = lambda: None
lg = watch(lambda pid: 1.0)
check("R6 watch: idle for whole window: no CPU line, end line names loading, waiting or stuck",
      lg and "rendering on CPU" not in " ".join(lg) and "uses almost no CPU" in lg[-1] and ns["RUN"].get("renderer") == "none", lg)
t0 = [time.time()]
lg = watch(lambda pid: (time.time() - t0[0]) * 2.0)
check("R7 watch: busy (2 s CPU per s) without GPU memory: CPU line", lg and "rendering on CPU" in lg[-1]
      and ns["RUN"].get("renderer") == "cpu", lg)
n = [0]


def idle_then_busy(pid):
    n[0] += 1
    return 1.0 if n[0] < 20 else 1.0 + (n[0] - 20) * 1.0


lg = watch(idle_then_busy)
check("R8 watch: idle launcher first, then drawing on CPU: CPU line from the last 15 checks",
      lg and "rendering on CPU" in lg[-1] and n[0] > 20, lg)
m = [0]


def busy_then_idle(pid):
    m[0] += 1
    return min(m[0], 8) * 1.0


lg = watch(busy_then_idle)
check("R9 watch: runtime start-up CPU, then stuck before drawing (Java title on a dead display): no CPU line",
      lg and "rendering on CPU" not in " ".join(lg) and "uses almost no CPU" in lg[-1], lg)

print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
