#!/usr/bin/env python3
"""Run a shell snippet on a pty, send keys with pauses, print screen titles seen and the raw text.
Usage: ptydrive.py SNIPPET KEY... ; KEY '@N' waits N seconds without reading; '!K' sends K at once; others are sent after 1.5 s of output."""
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


for k in sys.argv[2:]:
    if k.startswith("@"):
        time.sleep(float(k[1:]))
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
