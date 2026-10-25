#!/usr/bin/env python3
"""Steam ARM 3.1 Steam Frame rating: steam-arm-appinfo.py reads common/steam_frame_compatibility (v41 string table and
v40 inline keys): category as int (binary appinfo) and digit string (web PICS form), Frame runtime, test result tokens
without prefix in Valve's order, unknown tokens, oslist, test date, missing or malformed block gives unknown fields with
exit 0, four-column callers (awk $2 $4) unchanged, fixtures from three real PICS records (app ids only; no names).
Reader extracted from installer under test (SARM_INST picks another installer). Internal; not for release zips."""
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from sarm_env import INST  # noqa: E402

SRC = open(INST).read()
TMP = tempfile.mkdtemp(prefix="sarm31-frame-")
FAILS = []
START = "cat > /usr/local/lib/steam-arm-appinfo.py <<'AIPY'\n"
MISSING = START not in SRC
PREFIX = "#SteamFrame_TestResult_"
# every token Valve's Frame tests used by October 2026, in one made-up test order
TOKENS = ["ControllerGlyphsDoNotMatchDevice", "ControllerGlyphsMatchDevice", "DefaultConfigurationIsNotPerformant",
          "DefaultConfigurationIsPerformant", "DefaultControllerConfigFullyFunctional", "DefaultControllerConfigNotFullyFunctional",
          "DisplayOutputHasNonblockingIssues", "FirstTimeSetupRequiresActiveInternetConnection", "GameOrLauncherDoesntExitCleanly",
          "InterfaceTextIsLegible", "InterfaceTextIsNotLegible", "LauncherInteractionIssues", "NativeResolutionNotSupported",
          "SingleplayerGameplayRequiresActiveInternetConnection", "SteamOSDoesNotSupport", "TextInputDoesNotAutomaticallyInvokesKeyboard",
          "UnsupportedAntiCheatConfiguration", "UnsupportedGraphicsPerformance"]
UNKNOWN8 = "unknown\tunknown\tunknown\tunknown\t-\tunknown\tunknown"


def check(name, cond, detail=""):
    if MISSING:
        cond, detail = False, "reader absent from %s" % INST
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[-800:])


check("reader heredoc steam-arm-appinfo.py present in installer", True)
AI = os.path.join(TMP, "appinfo.py")
if not MISSING:
    i = SRC.index(START) + len(START)
    open(AI, "w").write(SRC[i:SRC.index("\nAIPY\n", i) + 1])
check('FRAME_KEY = "steam_frame_compatibility" set in reader', 'FRAME_KEY = "steam_frame_compatibility"' in SRC)


class KV:
    """Binary KeyValues writer; keys inline (v40) or as string table indexes (v41). None values skipped (absent key)."""

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
            elif isinstance(v, int) and -1 << 31 <= v < 1 << 31:
                out += b"\x02" + self.key(k) + struct.pack("<i", v)
            elif isinstance(v, int):
                out += b"\x0a" + self.key(k) + struct.pack("<q", v)
        return out + b"\x08"


def appinfo(path, apps, ver=41, filler=0):
    """apps: appid -> common dict."""
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
        st = struct.pack("<I", len(table)) + b"".join(s.encode() + b"\0" for s in table)
        data = struct.pack("<IIq", 0x07564429, 1, 16 + len(body)) + body + st
    else:
        data = struct.pack("<II", 0x07564428, 1) + body
    open(path, "wb").write(data)


def frame(cat, runtime, tokens, ts="1788270256", build="24070382", extra=None):
    """Frame block in PICS form (strings); tests indexed "0".. in given order."""
    cfg = {"recommended_runtime": runtime, "tso_enable": "0", "hdr_support": "0"}
    if runtime is None:
        del cfg["recommended_runtime"]
    cfg.update(extra or {})
    return {"category": cat, "configuration": cfg, "test_timestamp": ts, "tested_build_id": build,
            "tests": {str(n): {"display": "4", "token": t} for n, t in enumerate(tokens)}}


def deck(cat, runtime):
    return {"category": cat, "configuration": {"recommended_runtime": runtime}}


# three real PICS records of October 2026 (app ids only), trimmed to keys reader uses
REAL = {
    450390: {"steam_deck_compatibility": {"category": "1", "configuration": {}},
             "steam_frame_compatibility": frame("1", "proton-experimental-arm64", [PREFIX + "UnsupportedGraphicsPerformance"],
                                                ts="1785954215", build="7242747")},
    1003590: {"oslist": "windows", "steam_deck_compatibility": deck("3", "proton-stable"),
              "steam_frame_compatibility": frame("2", "proton-stable", [PREFIX + t for t in (
                  "DefaultConfigurationIsNotPerformant", "DefaultControllerConfigFullyFunctional", "ControllerGlyphsMatchDevice",
                  "InterfaceTextIsLegible")], ts="1788270256", build="24070382")},
    4688290: {"oslist": "android",
              "steam_frame_compatibility": frame("3", "lepton-stable", [PREFIX + t for t in (
                  "DefaultControllerConfigFullyFunctional", "ControllerGlyphsMatchDevice", "InterfaceTextIsLegible",
                  "DefaultConfigurationIsPerformant")], ts="1787591620", build="23856283")},
}
REAL_OUT = {
    450390: "450390\tUnsupported\tUnsupported\tunknown\tproton-experimental-arm64\tUnsupportedGraphicsPerformance\tunknown\t2026-08-05",
    1003590: "1003590\tVerified\tPlayable\tproton-stable\tproton-stable\tDefaultConfigurationIsNotPerformant,"
             "DefaultControllerConfigFullyFunctional,ControllerGlyphsMatchDevice,InterfaceTextIsLegible\twindows\t2026-09-01",
    4688290: "4688290\tunknown\tVerified\tunknown\tlepton-stable\tDefaultControllerConfigFullyFunctional,ControllerGlyphsMatchDevice,"
             "InterfaceTextIsLegible,DefaultConfigurationIsPerformant\tandroid\t2026-08-24",
}
APPS = {
    # binary form: category ints, oslist three systems, Deck native + Frame proton-stable
    220: {"name": "A", "oslist": "windows,macos,linux", "steam_deck_compatibility": deck(3, "native"),
          "steam_frame_compatibility": frame(3, "proton-stable", [PREFIX + "DefaultConfigurationIsPerformant"])},
    # PICS form: digit strings, all 18 tokens in list order
    221: {"name": "A2", "oslist": "windows,linux", "steam_deck_compatibility": deck("2", "proton-stable"),
          "steam_frame_compatibility": frame("2", "proton-experimental", [PREFIX + t for t in TOKENS])},
    # Deck only: Frame fields unknown, tokens "-"
    400: {"name": "B", "oslist": "windows", "steam_deck_compatibility": deck(3, "native")},
    # nothing at all
    401: {"name": "B2"},
    # unknown token with prefix, token without prefix, token with odd characters; test keys out of order
    500: {"name": "C", "steam_frame_compatibility": {"category": 1, "configuration": {"recommended_runtime": "native"},
          "test_timestamp": 1760000000, "tests": {"2": {"token": PREFIX + "SomeFutureToken"}, "0": {"token": "NoPrefix"},
                                                  "1": {"token": PREFIX + "Odd token;$(x)"}, "10": {"token": PREFIX + "Ten"}}}},
    # malformed block: category nested, configuration string, tests string, timestamp text
    600: {"name": "D", "oslist": "Windows, Linux!", "steam_frame_compatibility": {"category": {"x": 1}, "configuration": "none",
          "test_timestamp": "soon", "tests": "none"}},
    # malformed tests entries, category outside 1-3, runtime with shell characters, timestamp too large
    601: {"name": "D2", "steam_frame_compatibility": {"category": 7, "configuration": {"recommended_runtime": "proton;rm -rf"},
          "test_timestamp": 1 << 50, "tests": {"0": "x", "1": {"token": 5}, "2": {"display": "4"}}}},
    # block is a string, oslist number, Deck category string
    602: {"name": "D3", "oslist": 3, "steam_frame_compatibility": "Verified", "steam_deck_compatibility": deck("3", "native")},
    # Frame block without configuration or tests, timestamp 0
    700: {"name": "E", "steam_frame_compatibility": {"category": 2, "test_timestamp": 0}},
}
APPS.update(REAL)


def run(path, *ids):
    t = time.monotonic()
    r = subprocess.run([sys.executable, AI, path] + [str(x) for x in ids], capture_output=True, text=True, timeout=30)
    return r.returncode, r.stdout, time.monotonic() - t


def line(out, appid):
    for l in out.splitlines():
        if l.split("\t")[0] == str(appid):
            return l
    return ""


for ver in (41, 40):
    p = os.path.join(TMP, "v%d.vdf" % ver)
    appinfo(p, APPS, ver)
    ids = sorted(APPS) + [999]
    rc, out, _ = run(p, *ids)
    lines = out.splitlines()
    check("v%d: exit 0, one line per requested id in order, 8 columns each" % ver,
          rc == 0 and [l.split("\t")[0] for l in lines] == [str(x) for x in ids] and all(len(l.split("\t")) == 8 for l in lines), out)
    check("v%d: binary ints: Deck Verified native, Frame Verified proton-stable, one token, oslist, date" % ver,
          line(out, 220) == "220\tVerified\tVerified\tnative\tproton-stable\tDefaultConfigurationIsPerformant\twindows,macos,linux\t2026-09-01", out)
    check("v%d: digit strings (PICS form): Deck Playable, Frame Playable proton-experimental" % ver,
          line(out, 221).startswith("221\tPlayable\tPlayable\tproton-stable\tproton-experimental\t"), out)
    check("v%d: all 18 tokens, prefix removed, Valve's index order kept" % ver,
          line(out, 221).split("\t")[5] == ",".join(TOKENS), out)
    check("v%d: Deck only: Frame unknown, Frame runtime unknown, tokens -, oslist windows, date unknown" % ver,
          line(out, 400) == "400\tVerified\tunknown\tnative\tunknown\t-\twindows\tunknown", out)
    check("v%d: no blocks: every field unknown, tokens -" % ver, line(out, 401) == "401\t" + UNKNOWN8, out)
    check("v%d: appid absent from file: unknown fields" % ver, line(out, 999) == "999\t" + UNKNOWN8, out)
    check("v%d: unknown token passes through stripped; no prefix kept as is; odd characters dropped; numeric key order 0,1,2,10" % ver,
          line(out, 500).split("\t")[5] == "NoPrefix,Oddtokenx,SomeFutureToken,Ten", out)
    check("v%d: timestamp int 1760000000 -> 2025-10-09 UTC" % ver, line(out, 500).split("\t")[7] == "2025-10-09", out)
    check("v%d: malformed block (nested category, string configuration and tests, text timestamp): unknown, exit 0; oslist sanitised" % ver,
          line(out, 600) == "600\tunknown\tunknown\tunknown\tunknown\t-\twindows,linux\tunknown", out)
    check("v%d: malformed test entries skipped, category 7 unknown, runtime with shell characters unknown, timestamp too large unknown" % ver,
          line(out, 601) == "601\tunknown\tunknown\tunknown\tunknown\t-\tunknown\tunknown", out)
    check("v%d: Frame block as string, oslist as number: unknown; Deck fields kept" % ver,
          line(out, 602) == "602\tVerified\tunknown\tnative\tunknown\t-\tunknown\tunknown", out)
    check("v%d: Frame category without configuration or tests; timestamp 0 unknown" % ver,
          line(out, 700) == "700\tunknown\tPlayable\tunknown\tunknown\t-\tunknown\tunknown", out)
    for appid, want in REAL_OUT.items():
        check("v%d: real record %d: %s" % (ver, appid, want.split("\t")[2]), line(out, appid) == want, out)
    check("v%d: proton-experimental-arm64 passes through as Frame runtime" % ver, line(out, 450390).split("\t")[4] == "proton-experimental-arm64", out)
    check("v%d: oslist android (Lepton title)" % ver, line(out, 4688290).split("\t")[6] == "android", out)
    # four-column callers of 2.3 (deck_hint awk: $2 and $4) see same values as before
    old = subprocess.run(["awk", "-F\t", "-v", "id=220", '$1 == id { print $2 "\\t" $4; exit }'], input=out, capture_output=True, text=True).stdout
    check("v%d: 2.3 caller (awk $2, $4): deck category and Deck runtime unchanged" % ver, old == "Verified\tnative\n", old)
    old = subprocess.run(["awk", "-F\t", "-v", "id=4688290", '$1 == id { print $2 "\\t" $4; exit }'], input=out, capture_output=True, text=True).stdout
    check("v%d: 2.3 caller on Frame-only title: unknown, unknown" % ver, old == "unknown\tunknown\n", old)

good = open(os.path.join(TMP, "v41.vdf"), "rb").read()
for name, data in {"truncated file": good[:len(good) // 2], "0-byte file": b""}.items():
    p = os.path.join(TMP, "bad.vdf")
    open(p, "wb").write(data)
    rc, out, _ = run(p, 220)
    check("damaged: %s -> 8 unknown columns, exit 0" % name, rc == 0 and out == "220\t" + UNKNOWN8 + "\n", out)
rc, out, _ = run(os.path.join(TMP, "missing.vdf"), 220)
check("missing file -> 8 unknown columns, exit 0", rc == 0 and out == "220\t" + UNKNOWN8 + "\n", out)

big = os.path.join(TMP, "big.vdf")
appinfo(big, {1003590: APPS[1003590]}, 41, filler=20000)
rc, out, dt = run(big, 1003590)
check("20000 entries before title: found with Frame fields, under 1 s (%.2f s)" % dt, rc == 0 and out.strip() == REAL_OUT[1003590] and dt < 1.0, out)

shutil.rmtree(TMP, ignore_errors=True)
print("%d failed" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
