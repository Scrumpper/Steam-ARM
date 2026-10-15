#!/usr/bin/env python3
"""Steam ARM 2.3.1 private handler logs: steam-arm-run.py log (/tmp/steam-arm-run-<pid>.log) and Valve tool log
(/tmp/fex-compat-tool-<pid>.log, made owner-only by the launch handler). Run helper and handler's private_log
extracted from the installer (SARM_INST picks another file); stand-in handler and tool process. Internal."""
import importlib.util
import os
import re
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
INST = _INST
TMP = tempfile.mkdtemp(prefix="sarm232-plog-")
FAILS = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        if detail:
            print("     ", str(detail)[:600])


def heredoc(start, tag):
    src = open(INST).read()
    i = src.find(start)
    if i < 0:
        return ""
    i += len(start)
    return src[i:src.index("\n%s\n" % tag, i) + 1]


def mode(p):
    return stat.S_IMODE(os.lstat(p).st_mode)


R = heredoc("cat > /usr/local/lib/steam-arm-run.py <<'RUNPY'\n", "RUNPY")
H = heredoc("cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'\n", "HANDLERPY")
check("P0 installer writes steam-arm-run.py and handler", bool(R) and bool(H))
RP = os.path.join(TMP, "run.py")
open(RP, "w").write(R or "raise SystemExit('missing')\n")

# ---------- steam-arm-run.py log ----------
FH = os.path.join(TMP, "fake-handler.py")
open(FH, "w").write('print("steam-arm: rule line")\n')
DRV = os.path.join(TMP, "rdrv.py")
open(DRV, "w").write('''import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("r", %r)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.HANDLER = %r
os.umask(0o022)
sys.exit(m.main(sys.argv[1:]))
''' % (RP, FH))
p = subprocess.Popen([sys.executable, DRV, "--client", "x86", "--", sys.executable, "-c", "pass"],
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=dict(os.environ, SteamAppId="4242"))
p.communicate(timeout=60)
lp = "/tmp/steam-arm-run-%d.log" % p.pid
ok = os.path.isfile(lp)
check("P1 run log written at /tmp/steam-arm-run-<pid>.log (path kept)", ok and "steam-arm: rule line" in open(lp).read(),
      ok and open(lp).read())
check("P2 run log mode 0600 (umask 022)", ok and mode(lp) == 0o600, ok and oct(mode(lp)))
if ok:
    os.remove(lp)

spec = importlib.util.spec_from_file_location("r", RP)
r = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(r)
except BaseException:
    r = None
ol = getattr(r, "open_log", None)
check("P3 run helper has open_log", callable(ol))
if callable(ol):
    old = os.path.join(TMP, "old.log")
    open(old, "w").write("earlier start of same pid\n")
    os.chmod(old, 0o644)
    f = ol(old)
    f.write("new\n")
    f.close()
    check("P4 earlier own file: truncated, mode 0600", open(old).read() == "new\n" and mode(old) == 0o600,
          (open(old).read(), oct(mode(old))))
    tgt = os.path.join(TMP, "target")
    open(tgt, "w").write("keep\n")
    ln = os.path.join(TMP, "link.log")
    os.symlink(tgt, ln)
    f = ol(ln)
    f.write("x\n")
    f.close()
    check("P5 link at log path: not followed, target unchanged, output to /dev/null",
          open(tgt).read() == "keep\n" and f.name == os.devnull, f.name)
    f = ol(os.path.join(TMP, "no-such-dir", "x.log"))
    check("P6 log cannot be created: /dev/null, no error", f.name == os.devnull)
    f.close()
else:
    for n in ("P4", "P5", "P6"):
        check(n + " open_log cases", False, "open_log missing")

# ---------- Valve tool log: handler makes it owner-only ----------
m = re.search(r"\ndef private_log\(\):\n(?:    .*\n|\n)*?(?=\n\S)", H)
check("P7 handler defines private_log and calls it at load", bool(m) and "\nprivate_log()\n" in H)
TOOL = os.path.join(TMP, "tool.py")
open(TOOL, "w").write('''import os, re, sys
os.umask(0o022)
path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fex-compat-tool-%%d.log" %% os.getpid()
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND)
os.dup2(fd, 1); os.dup2(fd, 2)
print("before", flush=True)
exec(%r)
private_log()
print("after", flush=True)
''' % ((m.group(0) if m else "def private_log():\n    pass\n")))


def tool(arg=None):
    q = subprocess.Popen([sys.executable, TOOL] + ([arg] if arg else []), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = q.communicate(timeout=60)
    return q.pid, err


pid, err = tool()
tp = "/tmp/fex-compat-tool-%d.log" % pid
ok = os.path.isfile(tp)
check("P8 tool log created by tool as Valve does (0755 at umask 022), handler sets 0600, writes go on",
      ok and mode(tp) == 0o600 and open(tp).read() == "before\nafter\n", (ok and oct(mode(tp)), err))
if ok:
    os.remove(tp)
other = os.path.join(TMP, "steam-console.log")
pid, err = tool(other)
check("P9 stdout to another file (not /tmp/fex-compat-tool-<pid>.log): mode left as it is", mode(other) == 0o755,
      oct(mode(other)))
check("P10 handler docstring names owner-only tool log", "/tmp/fex-compat-tool-<pid>.log, readable by game account only" in H)

import shutil  # noqa: E402
shutil.rmtree(TMP, ignore_errors=True)
print("privlog 2.3.1: %d failed" % len(FAILS))
sys.exit(1 if FAILS else 0)
