#!/usr/bin/env python3
"""Steam ARM 2.3 x86 client helpers: steam-arm-x86client.py (bootstrap, prepare, restore, probe) and steam-arm-run.py
(handler entry for the x86 client), both extracted from the installer (SARM_INST picks another file). Synthetic
client folders, zips and aarch64 ELF files in a temp folder; no network. Internal."""
import importlib.util
import json
import os
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zipfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
INST = _INST
TMP = tempfile.mkdtemp(prefix="sarm232-x86c-")
FAILS = []
PASSES = [0]


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name)
    if cond:
        PASSES[0] += 1
    else:
        FAILS.append(name)
        if detail:
            print("     ", str(detail)[:800])


def heredoc(start, tag):
    src = open(INST).read()
    i = src.find(start)
    if i < 0:
        return None
    i += len(start)
    return src[i:src.index("\n%s\n" % tag, i) + 1]


def load(name, text):
    p = os.path.join(TMP, name + ".py")
    open(p, "w").write(text or "raise SystemExit('missing')\n")
    spec = importlib.util.spec_from_file_location(name, p)
    m = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(m)
    except BaseException:
        return None, p
    return m, p


def put(path, data, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data if isinstance(data, bytes) else data.encode())
    os.chmod(path, mode)


def read(path):
    return open(path, "rb").read()


X = heredoc("cat > /usr/local/lib/steam-arm-x86client.py <<'X86PY'\n", "X86PY")
R = heredoc("cat > /usr/local/lib/steam-arm-run.py <<'RUNPY'\n", "RUNPY")
check("X0 installer writes steam-arm-x86client.py and steam-arm-run.py", bool(X) and bool(R))
x, XP = load("x86client", X)
r, RP = load("runwrap", R)
check("X0 both helpers import", x is not None and r is not None)
if x is None or r is None:
    print("%d FAIL" % (len(FAILS) + 40))
    sys.exit(1)

# ---------------- bootstrap ----------------
WEB = '''#!/bin/bash
set -eu
log "Starting steamwebhelper with steamrt steam runtime at ${entry_point}"
exec \\
    "${entry_point}" -- \\
    "${DIR}/steamwebhelper_sniper_wrap.sh" "$@"
'''
ELF_I386 = b"\x7fELF\x01\x01\x01" + b"\0" * 9 + struct.pack("<HH", 2, 3) + b"\0" * 32
ELF_X64 = b"\x7fELF\x02\x01\x01" + b"\0" * 9 + struct.pack("<HH", 2, 62) + b"\0" * 48


def zipfile_with(path, members, mode=0o666):
    with zipfile.ZipFile(path, "w") as z:
        for name, data in members:
            i = zipfile.ZipInfo(name)
            i.external_attr = (0o100000 | mode) << 16
            z.writestr(i, data)


BZ = os.path.join(TMP, "boot.zip")
zipfile_with(BZ, [("steam.sh", "#!/usr/bin/env bash\necho steam\n"), ("steam_msg.sh", "#!/bin/sh\n"),
                  ("steam_subscriber_agreement.txt", "text\n"), ("ubuntu12_32/steam", ELF_I386)])
S = os.path.join(TMP, "S")
os.makedirs(S)
rc = x.main(["bootstrap", BZ, S])
mode = lambda p: os.stat(os.path.join(S, p)).st_mode & 0o7777
check("B1 bootstrap: 4 files written, status 0", rc == 0 and all(os.path.isfile(os.path.join(S, n)) for n in
      ("steam.sh", "steam_msg.sh", "steam_subscriber_agreement.txt", "ubuntu12_32/steam")))
check("B2 bootstrap modes: programs and scripts 755, text 644 (zip modes 0666 ignored)",
      (mode("steam.sh"), mode("ubuntu12_32/steam"), mode("steam_msg.sh"), mode("steam_subscriber_agreement.txt"))
      == (0o755, 0o755, 0o755, 0o644))
BAD = os.path.join(TMP, "bad.zip")
zipfile_with(BAD, [("../evil.sh", "#!/bin/sh\n")])
try:
    x.main(["bootstrap", BAD, os.path.join(TMP, "S2")])
    refused = False
except SystemExit:
    refused = True
check("B3 bootstrap: member with .. refused, nothing written outside", refused and not os.path.exists(os.path.join(TMP, "evil.sh")))
zipfile_with(BAD, [("steam.sh", "#!/bin/sh\n")])
try:
    x.main(["bootstrap", BAD, os.path.join(TMP, "S3")])
    refused = False
except SystemExit as e:
    refused = "ubuntu12_32/steam" in str(e)
check("B4 bootstrap: package without ubuntu12_32/steam refused with reason", refused)
# runtime package (box re-check B14): steam.sh needs ubuntu12_32/steam-runtime.tar.xz + checksum
RZ = os.path.join(TMP, "rt.zip")
zipfile_with(RZ, [("ubuntu12_32/steam-runtime.tar.xz", b"\xfd7zXZ\0data"), ("ubuntu12_32/steam-runtime.tar.xz.checksum",
                  "abc  steam-runtime.tar.xz\n"), ("ubuntu12_32/steam-runtime-scout.version.txt", "0.20250707\n")])
rc = x.main(["runtime", RZ, S])
check("B5 runtime: tar, checksum and version file into ubuntu12_32, status 0, bootstrap files kept",
      rc == 0 and mode("ubuntu12_32/steam-runtime.tar.xz") == 0o644 and mode("ubuntu12_32/steam-runtime.tar.xz.checksum") == 0o644
      and os.path.isfile(os.path.join(S, "ubuntu12_32/steam-runtime-scout.version.txt")) and mode("ubuntu12_32/steam") == 0o755)
zipfile_with(BAD, [("ubuntu12_32/steam-runtime.tar.xz", b"x")])
try:
    x.main(["runtime", BAD, os.path.join(TMP, "S4")])
    refused = False
except SystemExit as e:
    refused = "checksum" in str(e)
check("B6 runtime: package without checksum file refused with reason", refused)
zipfile_with(BAD, [("../ubuntu12_32/steam-runtime.tar.xz", b"x")])
try:
    x.main(["runtime", BAD, os.path.join(TMP, "S5")])
    refused = False
except SystemExit:
    refused = True
check("B7 runtime: member with .. refused, nothing written outside",
      refused and not os.path.exists(os.path.join(TMP, "ubuntu12_32")))

# ---------------- prepare / restore ----------------
A = os.path.join(TMP, "armhome")
# host libX11 of this machine not used: cases below set X11_SRC themselves
x.X11_SRC = os.path.join(TMP, "no-host-libX11.so.6")


def client_folder(arm_beta=True):
    s = os.path.join(TMP, "C%d" % time.monotonic_ns())
    put(os.path.join(s, "ubuntu12_64/steamwebhelper.sh"), WEB, 0o755)
    put(os.path.join(s, "ubuntu12_32/steam-launch-wrapper"), ELF_X64, 0o755)
    if arm_beta:
        put(os.path.join(s, "package/beta"), "arm-channel\n")
        put(os.path.join(s, "steamrtarm64/steam"), b"\x7fELF", 0o755)
    a = os.path.join(s, "home")
    os.makedirs(a)
    return s, a


def quiet(f, *a):
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = f(*a)
    return rc, buf.getvalue()


s, a = client_folder()
web0 = read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh"))
rc, out = quiet(x.prepare, s, a)
web1 = read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh"))
check("P1 prepare: flag on wrapper exec line only, status 0",
      rc == 0 and web1.count(b"--enable-features=NetworkServiceInProcess2") == 1
      and b'"${DIR}/steamwebhelper_sniper_wrap.sh" "$@" --enable-features=NetworkServiceInProcess2\n' in web1, (rc, out, web1))
check("P2 prepare: sha record matches edited file", read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh.steam-arm-sha")).decode().strip()
      == __import__("hashlib").sha256(web1).hexdigest())
w = os.path.join(s, "ubuntu12_32/steam-launch-wrapper")
stand = read(w).decode()
check("P3 prepare: Valve's ELF moved to .real, stand-in runs handler through host python link",
      read(w + ".real") == ELF_X64 and stand.startswith("#!/bin/sh\n")
      and "exec env -u LD_PRELOAD /usr/local/lib/steam-arm-python3 /usr/local/lib/steam-arm-run.py --client x86" in stand
      and '--preload "${LD_PRELOAD-}" -- ' + w + '.real "$@"' in stand and os.stat(w).st_mode & 0o777 == 0o755, stand)
r1 = subprocess.run(["sh", "-n", w])
check("P4 stand-in parses (sh -n)", r1.returncode == 0)
cfgd = os.path.join(a, ".fex-emu/AppConfig")
WANT = {"ThunksDB": {"GL": 0, "Vulkan": 0}, "Config": {"DiskCache": "0", "SilentLog": "1"}}
check("P5 prepare: FEX app settings steamwebhelper.json and exe.json, thunks off, code cache off, logging off (3.1)",
      all(json.load(open(os.path.join(cfgd, n))) == WANT for n in ("steamwebhelper.json", "exe.json")) and "code cache off, logging off" in out, out)
check("P5b prepare: steam.json with logging off only without STEAM_ARM_X87=reduced, logged",
      json.load(open(os.path.join(cfgd, "steam.json"))) == {"Config": {"SilentLog": "1"}} and "steam.json: logging off" in out, out)
check("P6 prepare: native update channel set aside", not os.path.exists(os.path.join(s, "package/beta"))
      and read(os.path.join(s, "package/beta.steam-arm-arm64")) == b"arm-channel\n")
snap = {p: read(os.path.join(s, p)) for p in ("ubuntu12_64/steamwebhelper.sh", "ubuntu12_32/steam-launch-wrapper")}
put(os.path.join(s, "package/beta"), "x86-beta-chosen-later\n")
rc, out2 = quiet(x.prepare, s, a)
check("P7 prepare twice: no second edit, no output, later channel file of x86 client kept",
      rc == 0 and out2 == "" and all(read(os.path.join(s, p)) == v for p, v in snap.items())
      and read(os.path.join(s, "package/beta")) == b"x86-beta-chosen-later\n", out2)
os.remove(os.path.join(s, "package/beta"))
# client update put Valve's files back: re-applied
put(os.path.join(s, "ubuntu12_64/steamwebhelper.sh"), WEB, 0o755)
put(w, ELF_X64 + b"new", 0o755)
rc, out3 = quiet(x.prepare, s, a)
check("P8 after client update: webhelper flag and stand-in applied again, newer ELF is .real",
      read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh")).count(b"NetworkServiceInProcess2") == 1
      and read(w + ".real") == ELF_X64 + b"new" and b"steam-arm stand-in" in read(w), out3)
# stand-in from an older release (other body): rewritten
put(w, "#!/bin/sh\n# steam-arm stand-in: old body\nexec old\n", 0o755)
rc, out4 = quiet(x.prepare, s, a)
check("P9 stand-in with other body rewritten", read(w).decode() == stand and "stand-in runs launch handler" in out4, out4)
# restore
rc, out5 = quiet(x.restore, s, a)
check("R1 restore: webhelper script byte-identical to Valve's, record gone",
      read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh")) == WEB.encode()
      and not os.path.exists(os.path.join(s, "ubuntu12_64/steamwebhelper.sh.steam-arm-sha")), out5)
check("R2 restore: Valve's launch wrapper back, .real gone", read(w) == ELF_X64 + b"new" and not os.path.exists(w + ".real"))
check("R3 restore: own FEX app settings removed, native update channel back",
      not os.listdir(cfgd) and read(os.path.join(s, "package/beta")) == b"arm-channel\n"
      and not os.path.exists(os.path.join(s, "package/beta.steam-arm-arm64")))
check("R4 restore prints one summary line", out5.count("\n") == 1 and "launch wrapper" in out5 and "webhelper" in out5, out5)
rc, out6 = quiet(x.restore, s, a)
check("R5 restore twice: nothing left to do, no output", rc == 0 and out6 == "", out6)
# Valve changed the script after prepare: left alone by restore
s, a = client_folder(arm_beta=False)
quiet(x.prepare, s, a)
put(os.path.join(s, "ubuntu12_64/steamwebhelper.sh"), WEB.replace("set -eu", "set -eux") + "# --enable-features=NetworkServiceInProcess2\n", 0o755)
changed = read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh"))
quiet(x.restore, s, a)
check("R6 webhelper changed since prepare: restore leaves it as it is", read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh")) == changed)
# Valve renamed the exec line: warning, status 1, file untouched
s, a = client_folder(arm_beta=False)
put(os.path.join(s, "ubuntu12_64/steamwebhelper.sh"), WEB.replace("steamwebhelper_sniper_wrap.sh", "other_wrap.sh"), 0o755)
before = read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh"))
rc, out7 = quiet(x.prepare, s, a)
check("P10 exec line gone: file untouched, status 1, last line names transport dialog",
      rc == 1 and read(os.path.join(s, "ubuntu12_64/steamwebhelper.sh")) == before
      and out7.strip().splitlines()[-1] == "warning: steamwebhelper.sh changed by Valve; transport dialog may appear at start", out7)
# FEX app settings: own keys merged, other keys kept (3.1)
s, a = client_folder(arm_beta=False)
put(os.path.join(a, ".fex-emu/AppConfig/exe.json"), '{"Config": {"Multiblock": "0"}}\n')
put(os.path.join(a, ".fex-emu/AppConfig/steamwebhelper.json"), '{"ThunksDB":{"GL":0,"Vulkan":0}}\n')
rc, out8 = quiet(x.prepare, s, a)
check("P11 FEX app setting with other keys: own keys merged, Multiblock kept, no warning, status 0",
      json.load(open(os.path.join(a, ".fex-emu/AppConfig/exe.json"))) == {"ThunksDB": {"GL": 0, "Vulkan": 0}, "Config": {"DiskCache": "0", "SilentLog": "1", "Multiblock": "0"}}
      and rc == 0 and "exe.json: thunks off, code cache off, logging off (other keys kept)" in out8, out8)
check("P11b 3.0 content (thunk keys only) rewritten with code cache off",
      json.load(open(os.path.join(a, ".fex-emu/AppConfig/steamwebhelper.json"))) == WANT and "steamwebhelper.json: thunks off, code cache off, logging off (other keys kept)" in out8, out8)
rc, out8b = quiet(x.prepare, s, a)
check("P11c prepare again: no change, no output", rc == 0 and out8b == "", out8b)
put(os.path.join(a, ".fex-emu/AppConfig/steamwebhelper.json"), '{"ThunksDB":{"GL":0,"Vulkan":0}\n')
rc, out8c = quiet(x.prepare, s, a)
check("P11d unparsable file: left as it is, warning, status 1",
      read(os.path.join(a, ".fex-emu/AppConfig/steamwebhelper.json")) == b'{"ThunksDB":{"GL":0,"Vulkan":0}\n' and rc == 1
      and out8c.strip().splitlines()[-1] == "warning: FEX app setting steamwebhelper.json is not valid JSON; left as it is (client window may fail)", out8c)
put(os.path.join(a, ".fex-emu/AppConfig/steamwebhelper.json"), json.dumps(WANT))
# steam.json: reduced x87 precision from STEAM_ARM_X87 (launcher sets it from X87_CLIENT or the environment)
os.environ["STEAM_ARM_X87"] = "reduced"
rc, out9 = quiet(x.prepare, s, a)
sj = os.path.join(a, ".fex-emu/AppConfig/steam.json")
check("P12 STEAM_ARM_X87=reduced: steam.json with X87ReducedPrecision 1 beside SilentLog, line names faster start and rendering errors",
      json.load(open(sj)) == {"Config": {"X87ReducedPrecision": "1", "SilentLog": "1"}} and "steam.json: reduced x87 precision (faster client start; rendering errors possible)" in out9, out9)
os.environ["STEAM_ARM_X87"] = "exact"
rc, out9b = quiet(x.prepare, s, a)
check("P12b STEAM_ARM_X87=exact: x87 key removed, logging key stays, logged", json.load(open(sj)) == {"Config": {"SilentLog": "1"}} and "steam.json: reduced x87 precision removed" in out9b, out9b)
put(sj, '{"Config": {"X87ReducedPrecision": "1", "Multiblock": "1"}}\n')
quiet(x.prepare, s, a)
check("P12c exact with other key in steam.json: own key removed, other kept, logging key added", json.load(open(sj)) == {"Config": {"Multiblock": "1", "SilentLog": "1"}})
os.unlink(sj)
del os.environ["STEAM_ARM_X87"]
rc, out9c = quiet(x.prepare, s, a)
check("P12d STEAM_ARM_X87 unset: steam.json with logging off only, that line alone", json.load(open(sj)) == {"Config": {"SilentLog": "1"}} and rc == 0 and out9c.strip() == "x86 client: FEX app setting steam.json: logging off", out9c)
rc, out9d = quiet(x.prepare, s, a)
check("P12e prepare again: idempotent", rc == 0 and out9d == "", out9d)
quiet(x.restore, s, a)
check("P12f restore removes steam.json (logging key was the only one)", not os.path.exists(sj))
# client window memory model relaxed (STEAM_ARM_CLIENT_TSO=relaxed): TSOEnabled 0 for the three client programs only
s3, a3 = client_folder(arm_beta=False)
cfg3 = os.path.join(a3, ".fex-emu/AppConfig")
os.environ["STEAM_ARM_CLIENT_TSO"] = "relaxed"
rc, outt = quiet(x.prepare, s3, a3)
check("T1 relaxed: TSOEnabled 0 in steamwebhelper.json, exe.json and steam.json beside the base keys; lines name it",
      all(json.load(open(os.path.join(cfg3, n))) == {"ThunksDB": {"GL": 0, "Vulkan": 0}, "Config": {"DiskCache": "0", "SilentLog": "1", "TSOEnabled": "0"}} for n in ("steamwebhelper.json", "exe.json"))
      and json.load(open(os.path.join(cfg3, "steam.json"))) == {"Config": {"SilentLog": "1", "TSOEnabled": "0"}}
      and outt.count("memory model relaxed (TSOEnabled 0)") == 3 and rc == 0, outt)
check("T1b only the three client files exist (no game file touched)", sorted(os.listdir(cfg3)) == ["exe.json", "steam.json", "steamwebhelper.json"])
rc, outt2 = quiet(x.prepare, s3, a3)
check("T1c prepare again: idempotent", rc == 0 and outt2 == "", outt2)
os.environ["STEAM_ARM_X87"] = "reduced"
quiet(x.prepare, s3, a3)
check("T2 relaxed with x87 reduced: steam.json carries both", json.load(open(os.path.join(cfg3, "steam.json"))) == {"Config": {"SilentLog": "1", "TSOEnabled": "0", "X87ReducedPrecision": "1"}})
os.environ["STEAM_ARM_CLIENT_TSO"] = "strict"
rc, outt3 = quiet(x.prepare, s3, a3)
check("T3 strict again: TSOEnabled removed from all three, x87 and base keys kept, logged",
      all("TSOEnabled" not in json.load(open(os.path.join(cfg3, n)))["Config"] for n in ("steamwebhelper.json", "exe.json", "steam.json"))
      and json.load(open(os.path.join(cfg3, "steam.json"))) == {"Config": {"SilentLog": "1", "X87ReducedPrecision": "1"}}
      and "steam.json: memory model strict again" in outt3 and outt3.count("code cache off, logging off (other keys kept)") == 2, outt3)
del os.environ["STEAM_ARM_X87"]
del os.environ["STEAM_ARM_CLIENT_TSO"]
rc, outt4 = quiet(x.prepare, s3, a3)
check("T3b unset: strict, x87 key removed", json.load(open(os.path.join(cfg3, "steam.json"))) == {"Config": {"SilentLog": "1"}} and rc == 0, outt4)
put(os.path.join(cfg3, "steam.json"), '{"Config": {"SilentLog": "1", "TSOEnabled": "1"}}\n')
quiet(x.prepare, s3, a3)
check("T3c a TSOEnabled value that is not ours (1) stays", json.load(open(os.path.join(cfg3, "steam.json")))["Config"].get("TSOEnabled") == "1")
os.environ["STEAM_ARM_CLIENT_TSO"] = "relaxed"
quiet(x.prepare, s3, a3)
quiet(x.restore, s3, a3)
del os.environ["STEAM_ARM_CLIENT_TSO"]
check("T4 restore after a relaxed start: all three files gone (own keys only)", not os.path.exists(cfg3) or not os.listdir(cfg3))
# lab: client window through GPU for one start (STEAM_ARM_LAB_CEF_GPU), base put back without it
s2, a2 = client_folder(arm_beta=False)
os.environ["STEAM_ARM_LAB_CEF_GPU"] = "vulkan"
rc, outl = quiet(x.prepare, s2, a2)
web = read(os.path.join(s2, "ubuntu12_64/steamwebhelper.sh"))
check("P15 lab vulkan: wrap line gets transport flag plus ANGLE Vulkan flags, sha record follows, line names lab",
      b'"${DIR}/steamwebhelper_sniper_wrap.sh" "$@" --enable-features=NetworkServiceInProcess2 --use-gl=angle --use-angle=vulkan --ignore-gpu-blocklist --enable-gpu-rasterization\n' in web
      and read(os.path.join(s2, "ubuntu12_64/steamwebhelper.sh.steam-arm-sha")).decode().strip() == __import__("hashlib").sha256(web).hexdigest()
      and "client window through GPU (ANGLE vulkan), this start" in outl, outl)
check("P15b lab vulkan: client FEX app settings Vulkan thunk on, GL thunk off, code cache off",
      all(json.load(open(os.path.join(a2, ".fex-emu/AppConfig", n))) == {"ThunksDB": {"GL": 0, "Vulkan": 1}, "Config": {"DiskCache": "0", "SilentLog": "1"}} for n in ("steamwebhelper.json", "exe.json"))
      and "thunks Vulkan on, GL off (lab, this start)" in outl, outl)
rc, outl2 = quiet(x.prepare, s2, a2)
check("P15c lab prepare again: idempotent", rc == 0 and outl2 == "", outl2)
os.environ["STEAM_ARM_LAB_CEF_GPU"] = "gl"
quiet(x.prepare, s2, a2)
check("P15d lab gl replaces the vulkan flags, both thunks on", b' --use-angle=gl --ignore-gpu-blocklist' in read(os.path.join(s2, "ubuntu12_64/steamwebhelper.sh")) and b"use-angle=vulkan" not in read(os.path.join(s2, "ubuntu12_64/steamwebhelper.sh"))
      and all(json.load(open(os.path.join(a2, ".fex-emu/AppConfig", n)))["ThunksDB"] == {"GL": 1, "Vulkan": 1} for n in ("steamwebhelper.json", "exe.json")))
del os.environ["STEAM_ARM_LAB_CEF_GPU"]
rc, outl3 = quiet(x.prepare, s2, a2)
check("P16 next start without lab: base line back (transport flag only), thunks off, logged",
      b'"${DIR}/steamwebhelper_sniper_wrap.sh" "$@" --enable-features=NetworkServiceInProcess2\n' in read(os.path.join(s2, "ubuntu12_64/steamwebhelper.sh"))
      and all(json.load(open(os.path.join(a2, ".fex-emu/AppConfig", n)))["ThunksDB"] == {"GL": 0, "Vulkan": 0} for n in ("steamwebhelper.json", "exe.json"))
      and "lab flags removed" in outl3 and "thunks off" in outl3, outl3)
os.environ["STEAM_ARM_LAB_CEF_GPU"] = "bogus"
rc, outl4 = quiet(x.prepare, s2, a2)
check("P16b unknown lab value: base, nothing changed", rc == 0 and outl4 == "", outl4)
del os.environ["STEAM_ARM_LAB_CEF_GPU"]
os.environ["STEAM_ARM_LAB_CEF_GPU"] = "vulkan"
quiet(x.prepare, s2, a2)
del os.environ["STEAM_ARM_LAB_CEF_GPU"]
quiet(x.restore, s2, a2)
check("P16c restore after a lab start: Valve's wrap line without any own flag", b'"${DIR}/steamwebhelper_sniper_wrap.sh" "$@"\n' in read(os.path.join(s2, "ubuntu12_64/steamwebhelper.sh"))
      and b"--enable-features" not in read(os.path.join(s2, "ubuntu12_64/steamwebhelper.sh")))
# multiblock-off (launcher restart counter): Multiblock 0 into both client files, own keys kept; second call silent
put(os.path.join(a, ".fex-emu/AppConfig/exe.json"), json.dumps(WANT))
put(os.path.join(a, ".fex-emu/AppConfig/steamwebhelper.json"), json.dumps(WANT))
rc, out10 = quiet(x.multiblock_off, s, a)
check("P13 multiblock-off: Multiblock 0 in steamwebhelper.json and exe.json beside own keys",
      rc == 0 and all(json.load(open(os.path.join(a, ".fex-emu/AppConfig", n))) == {"ThunksDB": {"GL": 0, "Vulkan": 0}, "Config": {"DiskCache": "0", "SilentLog": "1", "Multiblock": "0"}}
                      for n in ("steamwebhelper.json", "exe.json")) and out10.count("Multiblock off") == 2, out10)
rc, out10b = quiet(x.multiblock_off, s, a)
check("P13b multiblock-off again: no change, no output", rc == 0 and out10b == "", out10b)
# restore: own keys out, Multiblock kept without the launcher's state file, file with nothing left removed
put(os.path.join(a, ".fex-emu/AppConfig/steamwebhelper.json"), json.dumps(WANT))
quiet(x.restore, s, a)
check("R7 restore keeps FEX app setting key it did not write (Multiblock), removes own keys and empty file",
      json.load(open(os.path.join(a, ".fex-emu/AppConfig/exe.json"))) == {"Config": {"Multiblock": "0"}}
      and not os.path.exists(os.path.join(a, ".fex-emu/AppConfig/steamwebhelper.json")))
put(os.path.join(a, ".config/steam-arm/multiblock-client"), "1\n")
quiet(x.restore, s, a)
check("R7b restore with the launcher's state file: its Multiblock removed too, state file gone",
      not os.path.exists(os.path.join(a, ".fex-emu/AppConfig/exe.json")) and not os.path.exists(os.path.join(a, ".config/steam-arm/multiblock-client")))
# no client files yet (first start): nothing done, status 0
s0 = os.path.join(TMP, "empty")
os.makedirs(s0)
rc, out9 = quiet(x.prepare, s0, os.path.join(s0, "h"))
check("P12 first start (no client files): only FEX app settings, status 0", rc == 0 and "steamwebhelper.sh" not in out9 and "launch-wrapper" not in out9, out9)
check("P13 no channel file moved without native client in folder", not os.path.exists(os.path.join(s0, "package")))

# ---------------- private libX11 copy (X errors not fatal), box bug 9 ----------------
FX = os.path.join(HERE, "fixtures", "x86client", "libX11-aarch64.so")
lib0 = read(FX)
check("XE0 fixture: aarch64 libX11 stand-in with _XDefaultError (bti, paciasp prologue)", hasattr(x, "elf_func")
      and x.elf_func(lib0, "_XDefaultError") is not None, FX)
if hasattr(x, "elf_func") and x.elf_func(lib0, "_XDefaultError"):
    off, size = x.elf_func(lib0, "_XDefaultError")
    check("XE1 symbol found in dynamic table: file offset of function, size from symbol", size == 0x38 and lib0[off:off + 4] == bytes.fromhex("5f2403d5"), (off, size))
    src = os.path.join(TMP, "hostlib-src", "libX11.so.6.4.0")
    put(src, lib0, 0o644)
    os.symlink("libX11.so.6.4.0", os.path.join(TMP, "hostlib-src", "libX11.so.6"))
    x.X11_SRC = os.path.join(TMP, "hostlib-src", "libX11.so.6")
    s, a = client_folder(arm_beta=False)
    rc, outx = quiet(x.prepare, s, a)
    cp = os.path.join(a, ".fex-emu/hostlib/libX11.so.6")
    new = read(cp) if os.path.exists(cp) else b""
    check("XE2 prepare: private copy in client home, _XDefaultError = bti c; mov w0,#0; ret, rest byte-identical",
          rc == 0 and len(new) == len(lib0) and new[off:off + 12] == bytes.fromhex("5f2403d5" "00008052" "c0035fd6")
          and new[:off] == lib0[:off] and new[off + 12:] == lib0[off + 12:] and "private libX11 copy" in outx, outx)
    check("XE3 source sha recorded beside copy, host file untouched", read(cp + ".steam-arm-src").decode().strip()
          == __import__("hashlib").sha256(lib0).hexdigest() and read(src) == lib0)
    rc, outy = quiet(x.prepare, s, a)
    check("XE4 prepare again, host libX11 unchanged: no rewrite, no output", rc == 0 and outy == "", outy)
    put(src, lib0 + b"\0" * 16, 0o644)
    rc, outz = quiet(x.prepare, s, a)
    check("XE5 host libX11 updated: copy rebuilt", "private libX11 copy" in outz and len(read(cp)) == len(lib0) + 16, outz)
    put(src, b"\x7fELF" + b"\0" * 100, 0o644)
    rc, outw = quiet(x.prepare, s, a)
    check("XE6 host libX11 without the symbol: copy removed, warning, status 1", rc == 1 and not os.path.exists(cp)
          and "no _XDefaultError" in outw, outw)
    put(src, lib0, 0o644)
    quiet(x.prepare, s, a)
    rc, outr = quiet(x.restore, s, a)
    check("XE7 restore removes private copy and its folder", not os.path.exists(os.path.join(a, ".fex-emu/hostlib"))
          and "private libX11 copy removed" in outr, outr)
    x.X11_SRC = os.path.join(TMP, "no-host-libX11.so.6")

# restore after client put its own launch wrapper back: stale .real removed (box bug 12)
s, a = client_folder(arm_beta=False)
quiet(x.prepare, s, a)
w = os.path.join(s, "ubuntu12_32/steam-launch-wrapper")
put(w, ELF_X64, 0o755)
rc, outq = quiet(x.restore, s, a)
check("RX1 Valve's wrapper back over stand-in: restore removes stale .real copy", read(w) == ELF_X64 and not os.path.exists(w + ".real")
      and "old copy of launch wrapper removed" in outq, outq)

# reset on client type switch (box bugs 9, 10)
s, a = client_folder()
pk = os.path.join(s, "package")
for n in ("steam_client_steamdeck_stable_ubuntu12.installed", "steam_client_steamdeck_stable_ubuntu12.manifest",
          "steam_client_linux_arm64_beta_861407927dc8_linuxarm64.installed", "steam_client_linux_arm64_beta_861407927dc8_linuxarm64.manifest",
          "steamui_websrc_all.zip.vz.abc_1"):
    put(os.path.join(pk, n), "x\n")
put(os.path.join(a, ".config/steam-arm/x86-verified"), "")
rc, outr = quiet(x.reset, s, a, "arm64") if hasattr(x, "reset") else (None, "")
left = sorted(os.listdir(pk))
check("RS1 reset arm64: x86 package records and native client record removed, other files kept",
      left == ["beta", "steam_client_linux_arm64_beta_861407927dc8_linuxarm64.manifest", "steamui_websrc_all.zip.vz.abc_1"], left)
check("RS2 reset arm64: native file check marker written, x86 marker gone, one line names records",
      os.path.isfile(os.path.join(a, ".config/steam-arm/native-verify")) and not os.path.exists(os.path.join(a, ".config/steam-arm/x86-verified"))
      and outr.count("\n") == 1 and "steam_client_steamdeck_stable_ubuntu12.installed" in outr, outr)
rc, outr = quiet(x.reset, s, a, "x86") if hasattr(x, "reset") else (None, "x")
check("RS3 reset x86: both markers gone, package folder untouched, no output",
      not os.path.exists(os.path.join(a, ".config/steam-arm/native-verify")) and outr == "" and sorted(os.listdir(pk)) == left, outr)
r3 = subprocess.run([sys.executable, XP, "reset", s, a, "other"], capture_output=True, text=True)
check("RS4 reset with other client type: usage, status 2", r3.returncode == 2 and "reset S ARMHOME arm64|x86" in r3.stderr, r3.stderr)

# ---------------- probe ----------------
SHSTR = b"\0.text\0.shstrtab\0.symtab\0.strtab\0"


def aelf(words, obj=None, mapd=None):
    """Minimal aarch64 ELF: .text with words; optional symtab with object symbol (index range) or $d mapping symbol."""
    text = b"".join(struct.pack("<I", w) for w in words)
    strtab = b"\0obj\0$d\0$x\0"
    syms = b"\0" * 24
    if obj:
        syms += struct.pack("<IBBHQQ", 1, 1, 0, 1, 0x1000 + 4 * obj[0], 4 * (obj[1] - obj[0]))
    if mapd is not None:
        syms += struct.pack("<IBBHQQ", 5, 0, 0, 1, 0x1000 + 4 * mapd[0], 0)
        if mapd[1] is not None:
            syms += struct.pack("<IBBHQQ", 8, 0, 0, 1, 0x1000 + 4 * mapd[1], 0)
    off_text = 64
    off_shstr = off_text + len(text)
    off_sym = off_shstr + len(SHSTR)
    off_str = off_sym + len(syms)
    off_sh = (off_str + len(strtab) + 7) & ~7
    body = bytearray(off_sh)
    body[off_text:off_text + len(text)] = text
    body[off_shstr:off_shstr + len(SHSTR)] = SHSTR
    body[off_sym:off_sym + len(syms)] = syms
    body[off_str:off_str + len(strtab)] = strtab
    sh = b"\0" * 64
    sh += struct.pack("<IIQQQQIIQQ", 1, 1, 6, 0x1000, off_text, len(text), 0, 0, 4, 0)
    sh += struct.pack("<IIQQQQIIQQ", 7, 3, 0, 0, off_shstr, len(SHSTR), 0, 0, 1, 0)
    sh += struct.pack("<IIQQQQIIQQ", 17, 2, 0, 0, off_sym, len(syms), 4, 1, 8, 24)
    sh += struct.pack("<IIQQQQIIQQ", 25, 3, 0, 0, off_str, len(strtab), 0, 0, 1, 0)
    hdr = b"\x7fELF\x02\x01\x01" + b"\0" * 9 + struct.pack("<HHIQQQIHHHHHH", 3, 183, 1, 0x1000, 0, off_sh, 0, 64, 56, 0, 64, 5, 2)
    return hdr + bytes(body[64:]) + sh


NOP, RET = 0xD503201F, 0xD65F03C0
LDADDAL = 0xB8E20062        # ldaddal w2, w2, [x3]
CASAL = 0x88E0FC41          # casal w0, w1, [x2]
SWPA = 0xB8A08020           # swpa w0, w0, [x1]
ADRP, LDRB, CBZ = 0x90000010, 0x39400210, 0x34000050   # adrp x16; ldrb w16, [x16]; cbz w16, +8
plain = [NOP] * 8 + [RET]
check("E1 clean code: no hits", x.lse_hits(aelf(plain)) == 0)
check("E2 bare ldaddal: one hit", x.lse_hits(aelf([NOP, LDADDAL, RET])) == 1)
check("E3 casal and swpa count", x.lse_hits(aelf([CASAL, SWPA, RET])) == 2)
check("E4 outline-atomics helper (adrp, ldrb w16, cbz w16, ldaddal): guarded, no hit", x.lse_hits(aelf([ADRP, LDRB, CBZ, LDADDAL, RET])) == 0)
check("E5 cbz on a 64-bit register before ldaddal: not a guard", x.lse_hits(aelf([ADRP, LDRB, 0xB4000050, LDADDAL, RET])) == 1)
check("E6 LSE bytes inside object symbol in .text (data table): skipped", x.lse_hits(aelf([NOP, LDADDAL, NOP, RET], obj=(1, 3))) == 0)
check("E7 LSE bytes after $d mapping symbol, code after $x: skipped", x.lse_hits(aelf([NOP, LDADDAL, NOP, LDADDAL], mapd=(1, 3))) == 1)
check("E8 non-aarch64 ELF: no hits", x.lse_hits(ELF_X64 + struct.pack("<I", LDADDAL) * 4) == 0)


def armzip(path, steam_words):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("steamrtarm64\\steam", aelf(steam_words))
        z.writestr("steamrtarm64\\libclean.so", aelf(plain))
        z.writestr("steamrtarm64\\readme.txt", "x" * 100)


zl, zo = os.path.join(TMP, "lse.zip"), os.path.join(TMP, "ok.zip")
armzip(zl, [NOP, LDADDAL, RET])
armzip(zo, [ADRP, LDRB, CBZ, LDADDAL, RET])
check("Z1 probe: package with bare ldaddal (backslash names, as Valve's) -> lse", x.probe(zl, False) == "lse")
check("Z2 probe: package with guarded helpers only -> ok", x.probe(zo, False) == "ok")
put(os.path.join(TMP, "broken.zip"), b"not a zip")
check("Z3 probe: unreadable package -> err with reason", x.probe(os.path.join(TMP, "broken.zip"), False).startswith("err "))
out = subprocess.run([sys.executable, XP, "probe", zl], capture_output=True, text=True)
check("Z4 command line: probe ZIP prints lse, status 0", out.returncode == 0 and out.stdout.strip() == "lse", out)
out = subprocess.run([sys.executable, XP, "bogus"], capture_output=True, text=True)
check("Z5 command line: unknown action -> usage, status 2", out.returncode == 2 and "usage:" in out.stderr)


# stage 2 (--run): only clean exit counts; extraction folder removed after every result
def runzip(path, body):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("steamrtarm64\\steam", "#!/bin/sh\n" + body + "\n")
        z.writestr("steamrtarm64\\libclean.so", aelf(plain))


ptmp = os.path.join(TMP, "ptmp")
os.makedirs(ptmp)
old_tmp, tempfile.tempdir = tempfile.tempdir, ptmp
for tag, body, want in (("exit 0", "exit 0", "ok"), ("SIGSEGV", "kill -SEGV $$", "err client stopped by signal 11"),
                        ("exit 1", "echo no display; exit 1", "err client exit status 1"), ("SIGILL", "kill -ILL $$", "lse"),
                        ("exit 127", "exit 127", "err client could not load its libraries")):
    zp = os.path.join(TMP, "run-%s.zip" % tag.replace(" ", ""))
    runzip(zp, body)
    got = x.probe(zp, True)
    check("Z6 probe --run, client %s -> %s" % (tag, want), got == want, got)
check("Z7 probe --run leaves no steam-arm-probe.* folder", not [n for n in os.listdir(ptmp) if n.startswith("steam-arm-probe.")],
      os.listdir(ptmp))
tempfile.tempdir = old_tmp

# ---------------- steam-arm-run.py ----------------
check("W1 run: argument parse (client, preload, command)", r.parse(["--client", "x86", "--preload", "a.so", "--", "w", "-x"]) == ("x86", "a.so", ["w", "-x"])
      and r.parse(["--client", "x86", "--", "w"]) == ("x86", None, ["w"]) and r.parse(["--client", "x86", "w"]) is None
      and r.parse(["--client", "ppc", "--", "w"]) is None)
FH = os.path.join(TMP, "fake-handler.py")
put(FH, '''import os, sys
open(os.environ["T_OUT"] + ".h", "w").write(repr((globals().get("CLIENT_X86"), sys.argv[:], os.environ.get("LD_PRELOAD"))))
if os.environ.get("T_SKIP"):
    raise SystemExit(0)
if os.environ.get("T_BOOM"):
    raise RuntimeError("boom")
sys.argv.append("-added")
os.environ["T_FROM_HANDLER"] = "1"
print("steam-arm: rule line")
''')
CHILD = os.path.join(TMP, "child.py")
put(CHILD, '''import json, os, sys, time, signal
json.dump({"argv": sys.argv[1:], "env": os.environ.get("T_FROM_HANDLER"), "pre": os.environ.get("LD_PRELOAD")}, open(os.environ["T_OUT"], "w"))
if os.environ.get("T_SLEEP"):
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(143 - 128 + 100))
    time.sleep(30)
sys.exit(int(os.environ.get("T_RC", "0")))
''')
DRV = os.path.join(TMP, "rdrv.py")
put(DRV, '''import importlib.util, sys
spec = importlib.util.spec_from_file_location("r", %r)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.HANDLER = %r
sys.exit(m.main(sys.argv[1:]))
''' % (RP, FH))


def wrun(extra_env=None, args=None, wait=True):
    o = os.path.join(TMP, "o%d" % time.monotonic_ns())
    e = dict(os.environ, T_OUT=o, SteamAppId="4242")
    e.pop("LD_PRELOAD", None)
    e.update(extra_env or {})
    a = args or ["--client", "x86", "--preload", "/x/gameoverlayrenderer.so", "--", sys.executable, CHILD, "-game", "arg one"]
    if not wait:
        return subprocess.Popen([sys.executable, DRV] + a, env=e), o
    p = subprocess.run([sys.executable, DRV] + a, env=e, capture_output=True, text=True)
    return p, o


p, o = wrun({"T_RC": "7"})
res = json.load(open(o)) if os.path.exists(o) else {}
hres = eval(open(o + ".h").read()) if os.path.exists(o + ".h") else None
check("W2 handler runs with CLIENT_X86 True, argv of command (runpy puts handler path first), game LD_PRELOAD from --preload",
      hres == (True, [FH, sys.executable, CHILD, "-game", "arg one"], "/x/gameoverlayrenderer.so"), hres)
check("W3 child gets handler's argv and environment changes and LD_PRELOAD", res.get("argv") == ["-game", "arg one", "-added"]
      and res.get("env") == "1" and res.get("pre") == "/x/gameoverlayrenderer.so", res)
check("W4 exit status of child passed on (7)", p.returncode == 7, p)
check("W5 handler output only in log, not in game output", "rule line" not in p.stdout + p.stderr, p.stdout)
logs = sorted((os.path.getmtime(os.path.join("/tmp", f)), f) for f in os.listdir("/tmp") if f.startswith("steam-arm-run-"))
lt = open(os.path.join("/tmp", logs[-1][1])).read() if logs else ""
check("W6 log /tmp/steam-arm-run-<pid>.log: SteamAppId first, client line, handler lines, exit status",
      lt.startswith("SteamAppId=4242\n") and "steam-arm: client: x86 through emulation" in lt and "steam-arm: rule line" in lt
      and "steam-arm: exit status 7" in lt, lt)
for _m, f in logs:
    try:
        os.remove(os.path.join("/tmp", f))
    except OSError:
        pass
p, o = wrun({"T_SKIP": "1"})
check("W7 handler skips start (SystemExit 0): command not run, status 0", p.returncode == 0 and not os.path.exists(o), p)
p, o = wrun({"T_BOOM": "1"})
res = json.load(open(o)) if os.path.exists(o) else {}
check("W8 handler error: command still runs unchanged", p.returncode == 0 and res.get("argv") == ["-game", "arg one"], (p, res))
p, o = wrun(args=["--client", "x86", "--preload", "", "--", sys.executable, CHILD])
hres = eval(open(o + ".h").read()) if os.path.exists(o + ".h") else None
check("W9 empty --preload: no LD_PRELOAD for handler or child", hres is not None and hres[2] is None and json.load(open(o)).get("pre") is None, hres)
p, o = wrun(args=["--client", "x86"])
check("W10 malformed arguments: usage, status 2", p.returncode == 2 and "usage:" in p.stderr)
p, o = wrun(args=["--client", "x86", "--", "/nonexistent/wrapper"])
check("W11 command missing: status 127", p.returncode == 127, p)
proc, o = wrun({"T_SLEEP": "1"}, wait=False)
for _ in range(100):
    if os.path.exists(o):
        break
    time.sleep(0.05)
proc.send_signal(signal.SIGTERM)
try:
    rc = proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()
    rc = None
check("W12 SIGTERM to wrapper reaches the game (graceful), its status returned", rc == 115, rc)

import shutil
shutil.rmtree(TMP, ignore_errors=True)
print("%d FAIL" % len(FAILS) if FAILS else "all PASS")
sys.exit(1 if FAILS else 0)
