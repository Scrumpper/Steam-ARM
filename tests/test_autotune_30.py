#!/usr/bin/env python3
"""Steam ARM 3.0 automatic tuning, fix mode (C1): steam-arm-autotune.py verdicts, candidates, trial limits, undo,
stamp, tuned.conf layer, CLI helpers, restore merge; handler + steam-arm-run.py end to end with stand-in wrappers
(crash before graphics, hang without CPU use, good start). Never a signal to the game: the hang case ends on its
own. Module and handler extracted from the installer under test (SARM_INST picks another file); settings file and
module paths rewritten in the extracts only; hang window shortened in the extract. Internal; not for release zips."""
import json
import os
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST  # noqa: E402
TMP = tempfile.mkdtemp(prefix="sarm30-tune-")
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


A = heredoc("cat > /usr/local/lib/steam-arm-autotune.py <<'AUTOTUNEPY'\n", "AUTOTUNEPY")
H = heredoc("cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n", "HANDLERPY")
R = heredoc("cat > /usr/local/lib/steam-arm-run.py <<'RUNPY'\n", "RUNPY")
check("T0 installer writes autotune module, handler, run helper", bool(A) and bool(H) and bool(R))
if not (A and H and R):
    print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
    sys.exit(1)
check("T0 module in removal list", "        /usr/local/lib/steam-arm-autotune.py \\\n" in SRC)
hdr = SRC[SRC.index("# Local title profiles; override"):]
hdr = hdr[:hdr.index("\nTITLES\n")]
check("T0 /etc titles.conf header (refreshed by setup) lists autotune key, '#   ' lines only",
      "#   autotune=fix|off " in hdr and all(x.startswith("#   ") for x in hdr.splitlines()[1:]), hdr)
AP = os.path.join(TMP, "autotune.py")
put(AP, A)
M = runpy.run_path(AP, run_name="t")

# ---------------- verdicts ----------------
V = M["verdict"]
check("V1 verdicts: hang wins, CPU, no graphics, GPU ok / short, crash before graphics, unclear",
      V(10, "cpu", 200) == "hang" and V(None, "cpu", 70) == "cpu" and V(None, "none", 300) == "nographics"
      and V(None, "gpu", 60) == "ok" and V(None, "gpu", 59) == "short" and V(None, "unknown", 59) == "crash"
      and V(None, "unknown", 61) == "unclear")
check("V1b hang flag, then GPU memory in same start (own launcher window waited for input): no hang verdict",
      V(100, "gpu", 200) == "ok" and V(100, "gpu", 50) == "short" and V(100, "none", 300) == "hang")
check("V2 windows: crash 60 s, hang 90 s at 0.02 s/s, no graphics 300 s, 4 trials",
      (M["CRASH_S"], M["HANG_S"], M["HANG_CPU"], M["NOGFX_S"], M["MAX_TRIALS"]) == (60, 90, 0.02, 300, 4))
check("V3 knobs: gfx, multiblock, gl32 only; never TSO, X87, SMC or other correctness settings",
      sorted(M["KNOBS"]) == ["gfx", "gl32", "multiblock"]
      and not re.search(r"TSO|X87|SMC|VectorTSO|MemcpySetTSO", A.split("KNOBS =")[1].split("\n")[0]))

# ---------------- module flow ----------------
ST = "fex=FEX-2607 build=1 mesa=26.1.4 gpu=mali-csf-v10 client=arm64"
CTX = {"eff": {"gfx": "a", "multiblock": "on", "gl32": "on"}, "route_b": True, "bits": 64, "user_keys": []}


def home():
    return tempfile.mkdtemp(dir=TMP)


def tuned(h):
    p = os.path.join(h, ".config/steam-arm/tuned.conf")
    return open(p).read() if os.path.exists(p) else ""


def state(h, app="100"):
    return json.load(open(os.path.join(h, ".config/steam-arm/autotune/state.json")))["titles"].get(app)


def step(h, v, ctx=CTX, user=(), stamp=ST, secs=5):
    logs, note = M["begin"](h, "100", stamp, list(user))
    t = state(h)
    eff = dict(ctx["eff"])
    eff.update(t["best"])
    eff.update(t["trial"])
    return logs, note, M["finish"](h, "100", v, secs, dict(ctx, eff=eff, user_keys=list(user)))


h = home()
l, n, f = step(h, "ok")
check("F1 good start: nothing changed, no tuned.conf, no notice", tuned(h) == "" and n is None and "no change" in f[-1], (l, f))
l, n, f = step(h, "crash")
check("F2 bad start: next start tries graphics route flip (one knob)", re.search(r"^100 gfx=b +# autotune ", tuned(h), re.M)
      and f[-1] == "next start tries gfx=b", (tuned(h), f))
l, n, f = step(h, "crash")
check("F3 trial start: counted, one notice text, logged", "trial 1 of 4: gfx=b" in l[-1] and n and "gfx=b" in n, (l, n))
check("F3 failed trial undone, next knob from best-known setting (multiblock flip, gfx back to rules)",
      re.search(r"^100 multiblock=off +#", tuned(h), re.M) and "gfx=b" not in tuned(h).split("#")[-2], tuned(h))
l, n, f = step(h, "ok", secs=70)
check("F4 good trial kept as best-known, line stays with evidence", re.search(r"^100 multiblock=off +#.*kept multiblock=off", tuned(h), re.M)
      and state(h)["status"] == "kept", (tuned(h), f))
l, n, f = step(h, "ok", secs=70)
check("F5 good start after keep: no new trial", state(h)["trial"] == {} and "no change" in f[-1], f)

h = home()
for v in ("hang", "cpu", "nographics"):
    step(h, v)
t = state(h)
check("F6 every bad verdict moves on; candidates exhausted after gfx and multiblock (64-bit)", t["status"] == "exhausted"
      and t["tried"] == ["gfx=b", "multiblock=off"] and tuned(h) == "", t)
l, n, f = step(h, "crash")
check("F7 exhausted: no more trials, best-known kept", "no setting left" in f[-1] and tuned(h) == "", f)
l, n, f = step(h, "crash", stamp=ST.replace("build=1", "build=2"))
check("F8 new stamp (game build): trial count and tried list start again", "new stamp" in l[0] and f[-1] == "next start tries gfx=b", (l, f))

h = home()
ctx32 = dict(CTX, bits=32, route_b=False)
step(h, "crash", ctx=ctx32)
step(h, "crash", ctx=ctx32)
check("F9 32-bit, no route B: multiblock first, then GL thunk off (gl32=off)", re.search(r"^100 gl32=off +#", tuned(h), re.M), tuned(h))

h = home()
for i in range(6):
    step(h, "short")
check("F10 no decision on short GPU runs: no trial", tuned(h) == "", tuned(h))
h = home()
step(h, "crash")
for i in range(5):
    l, n, f = step(h, "unclear", ctx=CTX)
t = state(h)
check("F11 trial without decision repeats, at most 4 trials per stamp", t["trials"] == 4 and t["status"] == "exhausted"
      and tuned(h) == "", (t, f))

h = home()
step(h, "crash", user=["gfx"])
check("F12 key set in /etc or personal titles.conf: not tried (multiblock instead), logged", "multiblock=off" in tuned(h), tuned(h))
l, n, f = step(h, "crash", user=["gfx", "multiblock"])
check("F13 trial key set by hand meanwhile: trial dropped, not counted", any("dropped" in x for x in l) and state(h)["trials"] == 0, l)

h = home()
step(h, "crash")
p = os.path.join(h, ".config/steam-arm/tuned.conf")
open(p, "w").write("# mine\n")
l, n, f = step(h, "crash")
check("F14 setting removed from tuned.conf by hand: undone, never tried again", "removed from tuned.conf by hand" in l[0]
      and "gfx" in state(h)["undone"] and "gfx=b" not in tuned(h), (l, tuned(h)))

h = home()
put(os.path.join(h, ".config/steam-arm/tuned.conf"), "100 gfx=b   # written by hand\n")
l, n, f = step(h, "crash")
check("F16 key written into tuned.conf by hand: kept as written, never tried (next knob multiblock)",
      any("written into tuned.conf by hand" in x for x in l) and re.search(r"^100 gfx=b multiblock=off +#", tuned(h), re.M), (l, tuned(h)))

h = home()
put(os.path.join(h, ".config/steam-arm/tuned.conf"), "100 gfx=b   # autotune 2026-10-15 fex=FEX-2607; kept gfx=b\n")
l, n, f = step(h, "crash")
t = state(h)
check("F17 own line without tuning record (restored backup): tuning result, not hand edit; next knob tried",
      any("taken as tuning result" in x for x in l) and not any("by hand" in x for x in l) and t["best"] == {"gfx": "b"}
      and "gfx" not in t["undone"] and re.search(r"^100 gfx=a +#.*kept gfx=b; trial gfx=a", tuned(h), re.M), (l, t, tuned(h)))
h = home()
put(os.path.join(h, ".config/steam-arm/tuned.conf"), "100 gfx=b multiblock=off   # autotune 2026-10-15 x; kept gfx=b; trial multiblock=off after crash\n")
l, n, f = step(h, "ok", secs=70)
t = state(h)
check("F18 restored line with pending trial: kept part is result, trial dropped at end of start",
      t["best"] == {"gfx": "b"} and re.search(r"^100 gfx=b +#", tuned(h), re.M) and "multiblock" not in tuned(h).split("#")[1],
      (l, t, tuned(h)))
h = home()
step(h, "ok")
put(os.path.join(h, ".config/steam-arm/tuned.conf"), "100 gfx=b   # autotune 2026-10-15 x; kept gfx=b\n")
l, n, f = step(h, "ok", secs=70)
check("F19 title with a record: own-looking line added later still counts as hand edit", any("by hand" in x for x in l), l)
h = home()
put(os.path.join(h, ".config/steam-arm/tuned.conf"), "100 gfx=b   # autotune 2026-10-15 fex=FEX-2607 build=1\n")
l, n, f = step(h, "ok", secs=70)
t = state(h)
check("F20 restored own line with key kept from a hand edit (no kept or trial part): key stays as written, never tried",
      re.search(r"^100 gfx=b +#", tuned(h), re.M) and t["undone"] == ["gfx"] and t["best"] == {}, (l, t, tuned(h)))

h = home()
step(h, "crash")
s0 = open(os.path.join(h, ".config/steam-arm/autotune/state.json")).read()
check("F15 files: state.json owner only, tuned.conf lines valid for the backup check, titles.conf syntax",
      oct(os.stat(os.path.join(h, ".config/steam-arm/autotune/state.json")).st_mode & 0o777) == "0o600"
      and all(M["valid_line"](x) for x in tuned(h).splitlines()) and not M["valid_line"]("100 TSOEnabled=0"), s0)

# CLI helpers
r = subprocess.run([sys.executable, AP, "show", h, "100"], capture_output=True, text=True)
check("G1 show: state lines", "pending trial: gfx=b" in r.stdout and "trials this stamp: 0 of 4" in r.stdout, r.stdout)
r = subprocess.run([sys.executable, AP, "stop", h, "100"], capture_output=True, text=True)
check("G2 stop (autotune off): pending trial dropped from tuned.conf", tuned(h) == "" and "dropped" in r.stdout, r.stdout)
step(h, "crash")
r = subprocess.run([sys.executable, AP, "reset", h, "100"], capture_output=True, text=True)
check("G3 reset: line and state of the title gone", tuned(h) == "" and state(h) is None, r.stdout)
r = subprocess.run([sys.executable, AP, "show", h, "abc"], capture_output=True, text=True)
check("G4 bad app id refused", r.returncode == 2, r.stderr)

# merge (restore)
cur, bak = home(), home()
put(os.path.join(cur, "t.conf"), "100 gfx=b   # here\n")
put(os.path.join(cur, "s.json"), json.dumps({"version": 1, "titles": {"100": {"best": {"gfx": "b"}}}}))
put(os.path.join(bak, "t.conf"), "# head\n100 gfx=a   # backup\n200 multiblock=off   # backup\n")
put(os.path.join(bak, "s.json"), json.dumps({"version": 1, "titles": {"100": {"best": {"gfx": "a"}}, "200": {"best": {"multiblock": "off"}}}}))
o = home()
r = subprocess.run([sys.executable, AP, "merge", cur + "/t.conf", cur + "/s.json", bak + "/t.conf", bak + "/s.json",
                    o + "/t.conf", o + "/s.json"], capture_output=True, text=True)
mt = open(o + "/t.conf").read()
ms = json.load(open(o + "/s.json"))["titles"]
check("G5 merge: backup titles added, titles measured here keep their results", r.stdout.strip() == "added 1, kept 1"
      and "100 gfx=b" in mt and "200 multiblock=off" in mt and "100 gfx=a" not in mt and ms["100"]["best"] == {"gfx": "b"}
      and ms["200"]["best"] == {"multiblock": "off"}, (r.stdout, mt))
put(os.path.join(bak, "t.conf"), "100 TSOEnabled=0\n")
r = subprocess.run([sys.executable, AP, "merge", cur + "/t.conf", cur + "/s.json", bak + "/t.conf", bak + "/s.json",
                    o + "/t2", o + "/s2"], capture_output=True, text=True)
check("G6 merge refuses a tuned.conf with other keys", r.returncode == 1, r.stderr)

# ---------------- handler + run helper, end to end ----------------
CONF = os.path.join(TMP, "steam-arm.conf")
put(CONF, "GPU_FAMILY=other\nGFX_DEFAULT=auto\n")
APS = os.path.join(TMP, "autotune-short.py")
# hang window 6 s for the test; everything else as published
put(APS, A.replace("HANG_S = 90", "HANG_S = 6").replace("NOGFX_S = 300", "NOGFX_S = 40"))
HP = os.path.join(TMP, "handler.py")
put(HP, H.replace('"/etc/steam-arm/steam-arm.conf"', repr(CONF))
    .replace('AUTOTUNE_PY = "/usr/local/lib/steam-arm-autotune.py"', "AUTOTUNE_PY = %r" % APS)
    .replace('ENTRY_PY = "/usr/local/lib/steam-arm-entry.py"', "ENTRY_PY = %r" % os.path.join(TMP, "none.py")))
RP = os.path.join(TMP, "run.py")
put(RP, R.replace('HANDLER = "/usr/local/lib/steam-arm-handler.py"', "HANDLER = %r" % HP))
ELF = b"\x7fELF\x02\x01\x01" + b"\0" * 57
S = os.path.join(TMP, "Steam")
F = os.path.join(S, "steamapps/common/FEX-Emu")
put(os.path.join(F, "toolmanifest.vdf"), '"manifest"\n{\n  "commandline" "/fex-compat-tool %verb% --"\n}\n')
put(os.path.join(F, "VERSIONS.txt"), "FEX describe\tFEX-2610\n")
put(os.path.join(F, "fex-compat-tool"), ELF, 0o755)
put(os.path.join(F, "emulator.json"), '{"emulator_v0": {}}')
GAME = os.path.join(S, "steamapps/common/Game")
put(os.path.join(GAME, "game.bin"), ELF, 0o755)
WR = os.path.join(TMP, "wrapper.real")
# stands in for Valve's chain: T_SLEEP seconds in a child that uses no CPU; never signalled by the test
put(WR, '#!/bin/sh\nsleep "${T_SLEEP:-0}"\nexit 0\n', 0o755)


def e2e(profile, sleep, appid="100"):
    hm = home()
    if profile:
        put(os.path.join(hm, ".config/steam-arm/titles.conf"), "%s %s\n" % (appid, profile))
    e = {"PATH": "/usr/bin:/bin", "HOME": hm, "SteamAppId": appid, "T_SLEEP": str(sleep),
         "STEAM_COMPAT_INSTALL_PATH": GAME, "STEAM_COMPAT_DATA_PATH": os.path.join(S, "steamapps/compatdata", appid)}
    t0 = time.time()
    r = subprocess.run([sys.executable, RP, "--client", "arm64", "--", WR, "--", os.path.join(F, "fex-compat-tool"),
                        "waitforexitandrun", "--", os.path.join(GAME, "game.bin")], env=e, capture_output=True, text=True,
                       timeout=120)
    took = time.time() - t0
    logs = sorted((os.path.getmtime(p), p) for p in ("/tmp/" + n for n in os.listdir("/tmp") if n.startswith("steam-arm-run-")))
    text = ""
    # newest handler log of this run (written by run.py under its pid)
    for mt, p in reversed(logs):
        if mt >= t0 - 1:
            text = open(p, errors="replace").read()
            os.unlink(p)
            break
    return r, text, hm, took


r, text, hm, took = e2e("autotune=fix", 1)
check("E1 crash before graphics (chain ends at 1 s, exit status 0): verdict crash, next start tries a knob",
      "autotune: app 100: verdict: ended at 1 s before graphics" in text and "next start tries multiblock=off" in text
      and re.search(r"^100 multiblock=off", tuned(hm), re.M), text[-1500:])
r, text, hm, took = e2e("autotune=fix", 10)
check("E2 hang: no CPU use for the (shortened) window, hang line, one notice try; chain left to end by itself",
      "autotune: app 100: hang:" in text and "verdict: no CPU or GPU activity" in text and took >= 9.5, (took, text[-1500:]))
check("E2 hang: autotune sends no signal (stand-in exit status 0, ran its full time)", "exit status 0" in text, text[-400:])
r, text, hm, took = e2e("autotune=off", 1)
check("E3 autotune off: no autotune lines, no tuned.conf", "autotune:" not in text and tuned(hm) == "", text[-800:])
r, text, hm, took = e2e("autotune=yes", 1)
check("E4 unknown mode: logged, off", "autotune=yes unknown" in text and tuned(hm) == "", text[-800:])
r, text, hm, took = e2e("autotune=fix gfx=a", 1)
check("E5 gfx in personal titles.conf: not tested (user key wins)", "gfx set by title profile, not tested" in text, text[-800:])

# tuned.conf layer: below /etc and personal files
check("L1 handler profile order: share, tuned.conf, /etc, personal", re.search(
    r'PROFILE_FILES = \("/usr/local/share/steam-arm/titles.conf", TUNED_CONF, "/etc/steam-arm/titles.conf",', H) is not None)
check("L2 hang check reads /proc only; no kill or signal call in handler autotune code or module",
      not re.search(r"os\.kill|signal\.|send_signal|killpg", A)
      and not re.search(r"os\.kill|killpg", H.split("def hang_watch")[1].split("def at_notice")[0]))

shutil.rmtree(TMP, ignore_errors=True)
print("%d PASS, %d FAIL" % (PASSES[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
