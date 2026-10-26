#!/usr/bin/env python3
"""Steam ARM 2.3 Steam Deck hint: steam-arm-appinfo.py on generated appinfo.vdf files (v41 with string table, v40
with inline keys): category, runtime, damaged files give unknown with exit 0, large file speed. First four columns only;
3.1 adds Steam Frame columns behind them (tests/test_frame_31.py).
Reader extracted from installer under test (SARM_INST picks another installer). Internal; not for release zips."""
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
PROJ = os.path.dirname(HERE)
INST = _INST
SRC = open(INST).read()
TMP = tempfile.mkdtemp(prefix="sarm232-ai-")
FAILS = []
START = "cat > /usr/local/lib/steam-arm-appinfo.py <<'AIPY'\n"
MISSING = START not in SRC


def check(name, cond, detail=""):
    if MISSING:
        cond, detail = False, "reader absent from %s" % INST
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[-800:])


check("reader heredoc steam-arm-appinfo.py present in installer", True)
src = SRC if not MISSING else open(old("2.3.2") or INST).read()
i = src.index(START) + len(START)
AI = os.path.join(TMP, "appinfo.py")
open(AI, "w").write(src[i:src.index("\nAIPY\n", i) + 1])


class KV:
    """Binary KeyValues writer; keys inline (v40) or as string table indexes (v41)."""

    def __init__(self, table):
        self.table = table

    def key(self, k):
        if self.table is None:
            return k.encode() + b"\0"
        if k not in self.table:
            self.table.append(k)
        return struct.pack("<i", self.table.index(k))

    def enc(self, d):
        out = b""
        for k, v in d.items():
            if isinstance(v, dict):
                out += b"\x00" + self.key(k) + self.enc(v)
            elif isinstance(v, str):
                out += b"\x01" + self.key(k) + v.encode() + b"\0"
            elif isinstance(v, int):
                out += b"\x02" + self.key(k) + struct.pack("<i", v)
        return out + b"\x08"


def appinfo(path, apps, ver=41, filler=0):
    """apps: appid -> common dict. filler: extra small apps before them (scan speed)."""
    table = [] if ver == 41 else None
    w = KV(table)
    body = b""
    items = [(100000 + n, {"name": "x%d" % n}) for n in range(filler)] + list(apps.items())
    for appid, common in items:
        kv = w.enc({"appinfo": {"appid": appid, "common": common}})
        entry = struct.pack("<IIQ", 2, 0, 0) + b"\0" * 20 + struct.pack("<I", 1) + b"\0" * 20 + kv
        body += struct.pack("<II", appid, len(entry)) + entry
    body += struct.pack("<I", 0)
    if ver == 41:
        head_len = 16
        st = struct.pack("<I", len(table)) + b"".join(s.encode() + b"\0" for s in table)
        data = struct.pack("<IIq", 0x07564429, 1, head_len + len(body)) + body + st
    else:
        data = struct.pack("<II", 0x07564428, 1) + body
    open(path, "wb").write(data)
    return data


APPS = {
    220: {"name": "A", "steam_deck_compatibility": {"category": 3, "configuration": {"recommended_runtime": "native"}},
          "frame_compatibility": {"category": 2}},
    400: {"name": "B"},
    500: {"name": "C", "steam_deck_compatibility": {"category": 2, "configuration": {"recommended_runtime": "proton-stable"}}},
    600: {"name": "D", "steam_deck_compatibility": {"category": 1}},
    700: {"name": "E", "steam_deck_compatibility": {"category": 9}},
}


def run(path, *ids):
    """(exit status, output cut to its first four columns, seconds)."""
    t = time.monotonic()
    r = subprocess.run([sys.executable, AI, path] + [str(x) for x in ids], capture_output=True, text=True, timeout=30)
    out = "".join("\t".join(l.split("\t")[:4]) + "\n" for l in r.stdout.splitlines())
    return r.returncode, out, time.monotonic() - t


for ver in (41, 40):
    p = os.path.join(TMP, "v%d.vdf" % ver)
    appinfo(p, APPS, ver)
    rc, out, _ = run(p, 220, 400, 500, 600, 700, 999)
    lines = out.splitlines()
    check("v%d: Verified + runtime native; Frame unknown under 2.3 key name" % ver, rc == 0 and "220\tVerified\tunknown\tnative" in lines, out)
    check("v%d: title without Deck section: unknown" % ver, "400\tunknown\tunknown\tunknown" in lines, out)
    check("v%d: Playable + proton runtime" % ver, "500\tPlayable\tunknown\tproton-stable" in lines, out)
    check("v%d: Unsupported, runtime absent: unknown" % ver, "600\tUnsupported\tunknown\tunknown" in lines, out)
    check("v%d: category outside 1-3: unknown" % ver, "700\tunknown\tunknown\tunknown" in lines, out)
    check("v%d: appid absent from file: unknown, one line per requested id in order" % ver,
          "999\tunknown\tunknown\tunknown" in lines and [l.split("\t")[0] for l in lines] == ["220", "400", "500", "600", "700", "999"], out)

good = open(os.path.join(TMP, "v41.vdf"), "rb").read()
bad = {
    "truncated file": good[:len(good) // 2],
    "wrong magic (future format)": struct.pack("<I", 0x0756442A) + good[4:],
    "0-byte file": b"",
}
# string index out of range: string table count 1, keys refer to later indexes
off = struct.unpack_from("<q", good, 8)[0]
bad["string index out of range"] = good[:off] + struct.pack("<I", 1) + b"appinfo\0"
for name, data in bad.items():
    p = os.path.join(TMP, "bad.vdf")
    open(p, "wb").write(data)
    rc, out, _ = run(p, 220)
    check("damaged: %s -> unknown, exit 0" % name, rc == 0 and out == "220\tunknown\tunknown\tunknown\n", out)
rc, out, _ = run(os.path.join(TMP, "missing.vdf"), 220)
check("missing file -> unknown, exit 0", rc == 0 and out == "220\tunknown\tunknown\tunknown\n", out)
rc, out, _ = run(os.path.join(TMP, "v41.vdf"), "x1", 220)
check("non-numeric app id ignored", rc == 0 and out == "220\tVerified\tunknown\tnative\n", out)

big = os.path.join(TMP, "big.vdf")
appinfo(big, {220: APPS[220]}, 41, filler=20000)
rc, out, dt = run(big, 220)
check("20000 entries before title: found, under 1 s (%.2f s)" % dt, rc == 0 and out.startswith("220\tVerified") and dt < 1.0, out)

shutil.rmtree(TMP, ignore_errors=True)
print("%d failed" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
