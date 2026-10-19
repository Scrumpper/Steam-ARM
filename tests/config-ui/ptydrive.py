#!/usr/bin/env python3
"""Run a shell snippet on a pty, send keys with pauses, print screen titles seen and the raw text.
Usage: ptydrive.py SNIPPET KEY... ; KEY '@N' waits N seconds without reading; '!K' sends K at once; '^FILE:N' reads output
until FILE has N lines (30 s limit; on timeout prints TIMEOUT FILE and exits 3); others are sent after 1.5 s of output."""
import os, pty, re, select, sys, time

pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM="xterm", LANG=os.environ.get("LANG", "C.UTF-8"), COLUMNS="100", LINES="40")
    os.execvp("bash", ["bash", "-c", sys.argv[1]])
os.set_blocking(fd, False)
out = b""


def drain(t):
    global out
    end = time.time() + t
    while time.time() < end:
        if select.select([fd], [], [], 0.1)[0]:
            try:
                out += os.read(fd, 65536)
            except OSError:
                return


def lines(p):
    try:
        with open(p, "rb") as f:
            return f.read().count(b"\n")
    except OSError:
        return 0


for k in sys.argv[2:]:
    if k.startswith("@"):
        time.sleep(float(k[1:]))
        continue
    if k.startswith("^"):
        p, n = k[1:].rsplit(":", 1)
        end = time.time() + 30
        while lines(p) < int(n):
            if time.time() > end:
                print("TIMEOUT " + p)
                try:
                    os.kill(pid, 9)
                except ProcessLookupError:
                    pass
                sys.exit(3)
            drain(0.05)
        continue
    if k.startswith("!"):
        k = k[1:]
    else:
        drain(1.5)
    os.write(fd, k.encode().decode("unicode_escape").encode())
drain(3)
try:
    os.kill(pid, 9)
except ProcessLookupError:
    pass
txt = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-Za-z]|\x1b[=>]", "", out.decode("utf-8", "replace"))
TITLES = ("Install: hardware", "Install: page size", "Install: Vulkan", "Install: parts", "Install / Setup")
hits = sorted((m.start(), n) for n in TITLES for m in re.finditer(re.escape(n), txt))
seen = []
for _, n in hits:
    if not seen or seen[-1] != n:
        seen.append(n)
print("SCREENS " + "|".join(seen))
print(txt)
