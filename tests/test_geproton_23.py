#!/usr/bin/env python3
"""Steam ARM 2.3 optional GE-Proton ARM64 install: steam-arm-geproton.py (release pick, checksum file, safe unpack,
marker, placement, move, remove, remove-all, lock, list). Helper and compatmap extracted from installer under test
(SARM_INST picks another installer), imported in-process; network and Steam-running checks replaced by fakes.
Internal; not for release zips."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import stat
import sys
import tarfile
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_env import INST as _INST, old  # noqa: E402
PROJ = os.path.dirname(HERE)
INST = _INST
SRC = open(INST).read()
TMP = tempfile.mkdtemp(prefix="sarm232-ge-")
FAILS = []
NAMES = []


def check(name, cond, detail=""):
    NAMES.append(name)
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        print("     ", str(detail)[-1500:])


def heredoc(start, end):
    i = SRC.find(start)
    if i < 0:
        return None
    i += len(start)
    return SRC[i:SRC.index("\n" + end + "\n", i) + 1]


GE_SRC = heredoc("cat > /usr/local/lib/steam-arm-geproton.py <<'GEPY'\n", "GEPY")
if GE_SRC is None:
    # 2.2 installer: every case fails as such
    for n in ("G0 helper heredoc", "G1 pick", "G2 pick skips", "G3 pick rejects", "G4 read_sum", "G5 file install",
              "G6 sha512 mismatch", "G7 digest", "G8 unsafe archives", "G9 modes", "G10 unmarked", "G11 current",
              "G12 move", "G13 remove-all", "G14 lock", "G15 root", "G16 list slr4", "G17 refusals", "G18 remove",
              "G19 check", "G20 removal wiring"):
        check(n, False, "helper absent from %s" % INST)
    sys.exit(1)
check("G0 helper heredoc steam-arm-geproton.py present, mode 644 line after it",
      "GEPY\nchmod 644 /usr/local/lib/steam-arm-geproton.py\n" in SRC)

CM_SRC = heredoc("cat > /usr/local/lib/steam-arm-compatmap.py <<'PYEOF'\n", "PYEOF")
CM = os.path.join(TMP, "compatmap.py")
assert CM_SRC.count("if steam_up():") == 1
open(CM, "w").write(CM_SRC.replace("if steam_up():", "if False:"))
GEP = os.path.join(TMP, "geproton.py")
open(GEP, "w").write(GE_SRC)
spec = importlib.util.spec_from_file_location("geproton", GEP)
ge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ge)
ge.COMPATMAP = CM
ge.CONF = os.path.join(TMP, "steam-arm.conf")
ge.steam_up = lambda: False
ge.page_size = lambda: 4096
open(ge.CONF, "w").write("GAMEUSER=tester\n")


def run(*argv):
    o, e = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(o), contextlib.redirect_stderr(e):
        rc = ge.run(list(argv))
    return rc, o.getvalue() + e.getvalue()


def steam(name):
    s = os.path.join(TMP, name, "Steam")
    os.makedirs(os.path.join(s, "config"))
    os.makedirs(os.path.join(s, "steamapps"))
    return s


def vdf(maps):
    ent = "".join('\t\t\t\t\t"%s"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n'
                  '\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n' % (a, t) for a, t in maps)
    return ('"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n'
            '\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n' + ent + '\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n')


def balanced(p):
    s = open(p).read()
    return s.count("{") == s.count("}")


def member(t, name, data=b"", mode=0o644, kind=tarfile.REGTYPE, link=""):
    i = tarfile.TarInfo(name)
    i.type, i.mode, i.mtime = kind, mode, 1700000000
    if kind == tarfile.REGTYPE:
        i.size = len(data)
        t.addfile(i, io.BytesIO(data))
    else:
        i.linkname = link
        t.addfile(i)


def tool_tar(path, top, extra=None, vdf_name=None, skip_base=False):
    """Synthetic GE tarball: dir, compatibilitytool.vdf, toolmanifest.vdf, proton, files/lib/x, relative link."""
    with tarfile.open(path, "w:gz") as t:
        if not skip_base:
            member(t, top, kind=tarfile.DIRTYPE, mode=0o755)
            member(t, top + "/compatibilitytool.vdf", ('"compatibilitytools"\n{\n  "compat_tools"\n  {\n    "%s"\n    {\n'
                   '      "install_path" "."\n      "display_name" "%s"\n      "from_oslist"  "windows"\n'
                   '      "to_oslist"    "linux"\n    }\n  }\n}\n' % (vdf_name or top, top)).encode())
            member(t, top + "/toolmanifest.vdf", b'"manifest"\n{\n  "version" "2"\n  "commandline" "/proton %verb%"\n'
                   b'  "require_tool_appid" "4185400"\n  "use_sessions" "1"\n}\n')
            member(t, top + "/proton", b"#!/usr/bin/env python3\n", 0o755)
            member(t, top + "/files/lib/x.so", b"x" * 100, 0o644)
            member(t, top + "/files/lib/y.so", kind=tarfile.SYMTYPE, link="x.so")
        for e in extra or []:
            member(t, *e[:1], **e[1])
    h = hashlib.sha512(open(path, "rb").read()).hexdigest()
    open(path[:-len(".tar.gz")] + ".sha512sum", "w").write("%s  %s\n" % (h, os.path.basename(path)))
    return h


def dl(top, **kw):
    d = os.path.join(TMP, "dl-" + top + str(len(os.listdir(TMP))))
    os.makedirs(d)
    p = os.path.join(d, top + ".tar.gz")
    h = tool_tar(p, top, **kw)
    return p, h


def tree(d):
    out = []
    for root, dirs, files in os.walk(d):
        for f in sorted(dirs + files):
            p = os.path.join(root, f)
            st = os.lstat(p)
            out.append((p, st.st_mode, st.st_size, os.readlink(p) if os.path.islink(p) else
                        (open(p, "rb").read() if stat.S_ISREG(st.st_mode) else None)))
    return sorted(out)


def leftovers(cdir):
    return [n for n in os.listdir(cdir) if n.startswith(".steam-arm-ge-")] if os.path.isdir(cdir) else []


# ---------- G1-G3 pick ----------
def asset(tag, suf, url=None, size=645786140, digest=None):
    n = tag + suf
    a = {"name": n, "browser_download_url": url or ge.DL + tag + "/" + n, "size": size}
    if digest:
        a["digest"] = digest
    return a


def rel(tag, arm=True, draft=False, pre=False, assets=None):
    a = assets if assets is not None else ([asset(tag, "-aarch64.tar.gz", digest="sha256:" + "a" * 64),
                                            asset(tag, "-aarch64.sha512sum", size=150)] if arm else []) + \
        [asset(tag, ".tar.gz"), asset(tag, ".sha512sum")]
    return {"tag_name": tag, "draft": draft, "prerelease": pre, "assets": a, "published_at": "2026-09-16T10:00:00Z"}


R = [rel("GE-Proton11-9", draft=True), rel("GE-Proton11-8", pre=True), rel("GE-Proton11-7"), rel("GE-Proton11-2", arm=False)]
p = ge.pick(R)
check("G1 pick: newest non-draft non-prerelease with aarch64 assets (11-7), urls, size, sha256",
      p and p["tag"] == "GE-Proton11-7" and p["top"] == "GE-Proton11-7-aarch64" and p["size"] == 645786140
      and p["url"].endswith("/GE-Proton11-7/GE-Proton11-7-aarch64.tar.gz") and p["sha256"] == "a" * 64
      and p["date"] == "2026-09-16", p)
p = ge.pick([rel("GE-Proton11-2", arm=False), rel("GE-Proton11-1")])
check("G2 pick: newest release without aarch64 build skipped (11-2 -> 11-1)", p and p["tag"] == "GE-Proton11-1", p)
check("G2 pick: explicit older tag", (ge.pick(R, "GE-Proton11-7") or {}).get("tag") == "GE-Proton11-7"
      and ge.pick(R, "GE-Proton11-2") is None and ge.pick(R, "GE-Proton11-8") is None)
bad_host = rel("GE-Proton11-7", assets=[asset("GE-Proton11-7", "-aarch64.tar.gz", "https://evil.example/GE-Proton11-7-aarch64.tar.gz"),
                                        asset("GE-Proton11-7", "-aarch64.sha512sum")])
bad_path = rel("GE-Proton11-7", assets=[asset("GE-Proton11-7", "-aarch64.tar.gz",
                                              "https://github.com/someone/proton-ge-custom/releases/download/GE-Proton11-7/GE-Proton11-7-aarch64.tar.gz"),
                                        asset("GE-Proton11-7", "-aarch64.sha512sum")])
no_sum = rel("GE-Proton11-7", assets=[asset("GE-Proton11-7", "-aarch64.tar.gz")])
bad_tag = rel("GE-Proton11-7;rm", assets=[asset("GE-Proton11-7;rm", "-aarch64.tar.gz"), asset("GE-Proton11-7;rm", "-aarch64.sha512sum")])
check("G3 pick rejects other host, other repo path, missing .sha512sum, bad tag, bad explicit tag",
      all(ge.pick([r]) is None for r in (bad_host, bad_path, no_sum, bad_tag)) and ge.pick(R, "../x") is None
      and ge.pick({"message": "x"}) is None)

# ---------- G4 read_sum ----------
H = "0123456789abcdef" * 8
A = "GE-Proton11-7-aarch64.tar.gz"
check("G4 read_sum: plain line, binary marker, trailing newline",
      ge.read_sum("%s  %s\n" % (H, A), A) == H and ge.read_sum("%s  *%s" % (H, A), A) == H)
check("G4 read_sum refuses two lines, other name, 127 hex, upper case, one space",
      ge.read_sum("%s  %s\n%s  %s\n" % (H, A, H, A), A) is None and ge.read_sum("%s  other.tar.gz" % H, A) is None
      and ge.read_sum("%s  %s" % (H[:-1], A), A) is None and ge.read_sum("%s  %s" % (H.upper(), A), A) is None
      and ge.read_sum("%s %s" % (H, A), A) is None)

# ---------- G5 install from file ----------
S = steam("s5")
C = os.path.join(S, "compatibilitytools.d")
TOP = "GE-Proton11-7-aarch64"
f, h7 = dl(TOP, extra=[(TOP + "/files/ww", {"data": b"w", "mode": 0o666}), (TOP + "/files/wx", {"data": b"w", "mode": 0o777}),
                       (TOP + "/files/su", {"data": b"s", "mode": 0o4755})])
rc, out = run("install", "--file", f, S)
T7 = os.path.join(C, TOP)
mk = ge.marker(T7) or {}
check("G5 file install: status 0, folder in compatibilitytools.d, message names tag", rc == 0 and os.path.isfile(os.path.join(T7, "proton"))
      and "GE-Proton11-7 installed" in out, out)
check("G5 marker: TAG, SHA512, SOURCE=file, BYTES", mk.get("TAG") == "GE-Proton11-7" and mk.get("SHA512") == h7
      and mk.get("SOURCE") == "file" and mk.get("BYTES", "").isdigit(), mk)
md = lambda p: stat.S_IMODE(os.lstat(os.path.join(T7, p)).st_mode)
check("G5 modes: proton 755, lib 644, dirs 755, link kept relative, owner = caller",
      md("proton") == 0o755 and md("files/lib/x.so") == 0o644 and md("files") == 0o755 and md(".") == 0o755
      and os.readlink(os.path.join(T7, "files/lib/y.so")) == "x.so" and os.stat(T7).st_uid == os.getuid())
check("G9 world-writable members unpacked without group/other write; setuid bit dropped",
      md("files/ww") == 0o644 and md("files/wx") == 0o755 and md("files/su") == 0o755)
check("G5 no temp folder left; lock file only", leftovers(C) == [], os.listdir(C))
check("G21 install: lock file unlinked at end (box re-test B4)", not os.path.exists(os.path.join(C, ".steam-arm-ge.lock")), os.listdir(C))
check("G5 SLR line when appmanifest_4185400.acf absent", "Steam Linux Runtime 4.0 (Arm64): absent" in out, out)

# ---------- G6 sha512 mismatch ----------
S6 = steam("s6")
f6, _ = dl(TOP)
open(f6[:-7] + ".sha512sum", "w").write("%s  %s\n" % ("f" * 128, os.path.basename(f6)))
rc, out = run("install", "--file", f6, S6)
C6 = os.path.join(S6, "compatibilitytools.d")
check("G6 sha512 mismatch: status 2, nothing placed, temp gone", rc == 2 and "sha512 does not match" in out
      and not os.path.exists(os.path.join(C6, TOP)) and leftovers(C6) == [], out)
os.remove(f6[:-7] + ".sha512sum")
rc, out = run("install", "--file", f6, S6)
check("G6 checksum file missing beside archive: status 1, message names it", rc == 1
      and "Checksum file GE-Proton11-7-aarch64.sha512sum not found beside it" in out, out)
bad = os.path.join(TMP, "GE-Proton11-7.tar.gz")
open(bad, "w").write("x")
rc, out = run("install", "--file", bad, S6)
check("G6 file name not as published (no -aarch64): refused", rc == 1 and "File name must be" in out, out)


# ---------- G7 GitHub path with fakes ----------
def github(tarpath, sha512, digest):
    def api(_tmp):
        r = rel("GE-Proton11-7", assets=[asset("GE-Proton11-7", "-aarch64.tar.gz", size=os.path.getsize(tarpath), digest=digest),
                                         asset("GE-Proton11-7", "-aarch64.sha512sum")])
        return [r]
    ge.api_releases = api
    ge.fetch_sum = lambda r, t: sha512
    ge.download = lambda url, dest: shutil.copyfile(tarpath, dest)


S7 = steam("s7")
f7, h = dl(TOP)
github(f7, h, "sha256:" + "0" * 64)
rc, out = run("install", S7)
C7 = os.path.join(S7, "compatibilitytools.d")
check("G7 GitHub digest (sha256) mismatch with good sha512: status 2, nothing placed",
      rc == 2 and "sha256 does not match" in out and not os.path.exists(os.path.join(C7, TOP)) and leftovers(C7) == [], out)
github(f7, h, "sha256:" + hashlib.sha256(open(f7, "rb").read()).hexdigest())
rc, out = run("install", S7)
check("G7 GitHub path with matching digest: installed, SOURCE=github, URL from release",
      rc == 0 and (ge.marker(os.path.join(C7, TOP)) or {}).get("SOURCE") == "github"
      and (ge.marker(os.path.join(C7, TOP)) or {}).get("URL", "").startswith(ge.DL + "GE-Proton11-7/"), out)
ge.api_releases = lambda _t: [rel("GE-Proton11-2", arm=False)]
rc, out = run("install", S7)
check("G7 no ARM64 build in releases: status 2, message", rc == 2 and "No GE-Proton release with ARM64 build" in out, out)

# ---------- G8 unsafe archives ----------
cases = [
    ("dot-dot member", [(TOP + "/../x", {"data": b"x"})]),
    ("absolute member", [("/tmp/sarm-ge-abs", {"data": b"x"})]),
    ("link escaping top", [(TOP + "/esc", {"kind": tarfile.SYMTYPE, "link": "../../x"})]),
    ("absolute link", [(TOP + "/abs", {"kind": tarfile.SYMTYPE, "link": "/etc/passwd"})]),
    ("hard link", [(TOP + "/hl", {"kind": tarfile.LNKTYPE, "link": TOP + "/proton"})]),
    ("fifo", [(TOP + "/fifo", {"kind": tarfile.FIFOTYPE})]),
    ("char device", [(TOP + "/dev", {"kind": tarfile.CHRTYPE})]),
    ("second top folder", [("Other/x", {"data": b"x"})]),
    ("write through link", [(TOP + "/ln", {"kind": tarfile.SYMTYPE, "link": "files"}), (TOP + "/ln/z", {"data": b"z"})]),
    ("link chain leaving top", [(TOP + "/files/up", {"kind": tarfile.SYMTYPE, "link": ".."}),
                                (TOP + "/out", {"kind": tarfile.SYMTYPE, "link": "files/up/.."})]),
    ("repeated name", [(TOP + "/proton", {"data": b"again"})]),
]
res = []
for label, extra in cases:
    s = steam("s8-" + label.replace(" ", "-"))
    fx, _ = dl(TOP, extra=extra)
    rc, out = run("install", "--file", fx, s)
    c = os.path.join(s, "compatibilitytools.d")
    ok = rc == 2 and not os.path.exists(os.path.join(c, TOP)) and leftovers(c) == [] and not os.path.exists("/tmp/sarm-ge-abs")
    res.append((label, ok, rc, out.strip()[-160:]))
for label, ok, rc, out in res:
    check("G8 refused, nothing placed: " + label, ok, "rc %s: %s" % (rc, out))
s = steam("s8-vdf")
fx, _ = dl(TOP, vdf_name="GE-Proton11-6-aarch64")
rc, out = run("install", "--file", fx, s)
check("G8 refused: compatibilitytool.vdf names other tool than top folder", rc == 2 and "does not name" in out
      and not os.path.exists(os.path.join(s, "compatibilitytools.d", TOP)), out)

# ---------- G10 unmarked same-name folder ----------
S10 = steam("s10")
own = os.path.join(S10, "compatibilitytools.d", TOP)
os.makedirs(os.path.join(own, "files"))
open(os.path.join(own, "compatibilitytool.vdf"), "w").write('"compat_tools" { "%s" {} }' % TOP)
open(os.path.join(own, "files", "mine"), "w").write("own")
before = tree(own)
f10, _ = dl(TOP)
rc, out = run("install", "--file", f10, S10)
check("G10 hand-installed copy with same name: refused, folder byte-identical", rc == 1 and "not installed by Steam ARM" in out
      and tree(own) == before, out)
got = []
ge.api_releases = lambda _t: [rel("GE-Proton11-7")]
ge.fetch_sum = lambda r, t: "0" * 128
ge.download = lambda url, dest: got.append(url)
rc, out = run("install", S10)
check("G10 GitHub path: refused before download when hand copy holds the name", rc == 1 and got == [] and tree(own) == before, out)

# ---------- G11 reinstall same sha ----------
mt = os.stat(os.path.join(T7, ".steam-arm-ge")).st_mtime_ns
ino = os.stat(T7).st_ino
rc, out = run("install", "--file", f, S)
check("G11 same build again: 'installed and current', folder and marker untouched", rc == 0 and "is installed and current" in out
      and os.stat(os.path.join(T7, ".steam-arm-ge")).st_mtime_ns == mt and os.stat(T7).st_ino == ino, out)

# ---------- G12 update 11-6 -> 11-7 with --move ----------
S12 = steam("s12")
C12 = os.path.join(S12, "compatibilitytools.d")
f6b, _ = dl("GE-Proton11-6-aarch64")
rc0, _ = run("install", "--file", f6b, S12)
V12 = os.path.join(S12, "config", "config.vdf")
open(V12, "w").write(vdf([("100", "GE-Proton11-6-aarch64"), ("200", "GE-Proton11-6-aarch64"), ("300", "proton-stable-arm64")]))
rc, out = run("install", "--file", f, "--move", S12)
m = ge.mapped(S12)
check("G12 --move: games on 11-7, other mapping kept, 11-6 folder gone, vdf balanced",
      rc0 == 0 and rc == 0 and m == {"100": TOP, "200": TOP, "300": "proton-stable-arm64"}
      and not os.path.exists(os.path.join(C12, "GE-Proton11-6-aarch64")) and os.path.isdir(os.path.join(C12, TOP))
      and balanced(V12) and "2 games moved to GE-Proton11-7" in out, out + str(m))
open(V12, "w").write(vdf([("100", TOP)]))
rc, out = run("install", "--file", f6b, "--move", S12)
check("G12 older build installed with --move: newer one and its games kept (moves only from older builds)",
      rc == 0 and os.path.isdir(os.path.join(C12, TOP)) and os.path.isdir(os.path.join(C12, "GE-Proton11-6-aarch64"))
      and ge.mapped(S12) == {"100": TOP}, out)
S12b = steam("s12b")
run("install", "--file", f6b, S12b)
ge.steam_up = lambda: True
rc, out = run("install", "--file", f, "--move", S12b)
ge.steam_up = lambda: False
check("G12 --move while Steam runs: newer installed, older kept, note says close Steam",
      rc == 0 and os.path.isdir(os.path.join(S12b, "compatibilitytools.d", "GE-Proton11-6-aarch64"))
      and os.path.isdir(os.path.join(S12b, "compatibilitytools.d", TOP)) and "games not moved" in out, out)

# ---------- G18 remove ----------
open(V12, "w").write(vdf([("100", TOP), ("200", "GE-Proton11-6-aarch64")]))
rc, out = run("remove", "GE-Proton11-6", "--to", "GE-Proton11-7", S12)
check("G18 remove 11-6 --to 11-7: game moved, folder gone", rc == 0 and ge.mapped(S12) == {"100": TOP, "200": TOP}
      and not os.path.exists(os.path.join(C12, "GE-Proton11-6-aarch64")) and "1 game moved to GE-Proton11-7" in out, out)
ge.steam_up = lambda: True
rc, out = run("remove", "GE-Proton11-7", S12)
ge.steam_up = lambda: False
check("G18 remove while Steam runs: refused, folder kept", rc == 1 and "running" in out and os.path.isdir(os.path.join(C12, TOP)), out)
rc, out = run("remove", "GE-Proton11-7", "--to", "GE-Proton11-7", S12)
check("G18 remove --to itself: refused", rc == 1 and "not another installed" in out, out)
rc, out = run("remove", "GE-Proton11-7", S12)
check("G18 remove without --to: mappings dropped (Steam's default), folder gone", rc == 0 and ge.mapped(S12) == {}
      and not os.path.exists(os.path.join(C12, TOP)) and balanced(V12), out)
check("G21 remove: lock file unlinked at end (box re-test B4)", not os.path.exists(os.path.join(C12, ".steam-arm-ge.lock")),
      os.listdir(C12))
check("G18 remove without --to: message says Linux build where game has one, not default Proton alone",
      "back to Steam's choice (Linux build where game has one, else default Proton)." in out
      and "set to Steam's default Proton" not in out, out)
rc, out = run("remove", "GE-Proton10-34", S10)
check("G18 hand-installed copy never removed", rc == 1 and "left alone" in out and tree(own) == before, out)

# ---------- G13 remove-all ----------
S13 = steam("s13")
C13 = os.path.join(S13, "compatibilitytools.d")
run("install", "--file", f, S13)
run("install", "--file", f6b, S13)
hand = os.path.join(C13, "GE-Proton10-34")
os.makedirs(hand)
open(os.path.join(hand, "compatibilitytool.vdf"), "w").write('"compat_tools" { "GE-Proton10-34" {} }')
os.makedirs(os.path.join(C13, ".steam-arm-ge-stale"))
V13 = os.path.join(S13, "config", "config.vdf")
open(V13, "w").write(vdf([("1", TOP), ("2", "GE-Proton11-6-aarch64"), ("3", "GE-Proton10-34"), ("4", "proton_11")]))
rc, out = run("remove-all", S13)
check("G13 remove-all: marked builds gone, hand copy kept, tags printed", rc == 0 and not os.path.exists(os.path.join(C13, TOP))
      and not os.path.exists(os.path.join(C13, "GE-Proton11-6-aarch64")) and os.path.isdir(hand)
      and out.strip() == "GE-Proton11-7, GE-Proton11-6", out)
check("G13 remove-all: mappings to removed builds dropped, others kept, vdf balanced, lock and temp gone",
      ge.mapped(S13) == {"3": "GE-Proton10-34", "4": "proton_11"} and balanced(V13) and sorted(os.listdir(C13)) == ["GE-Proton10-34"],
      os.listdir(C13))
rc, out = run("remove-all", steam("s13b"))
check("G13 remove-all without compatibilitytools.d: status 0, nothing printed", rc == 0 and out.strip() == "", out)

# ---------- G14 lock ----------
import fcntl  # noqa: E402
S14 = steam("s14")
C14 = os.path.join(S14, "compatibilitytools.d")
os.makedirs(os.path.join(C14, ".steam-arm-ge-old"))
lk = open(os.path.join(C14, ".steam-arm-ge.lock"), "a")
fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)
rc, out = run("install", "--file", f, S14)
check("G14 lock held: second run status 1, nothing placed", rc == 1 and "Another GE-Proton action runs" in out
      and not os.path.exists(os.path.join(C14, TOP)) and os.path.isdir(os.path.join(C14, ".steam-arm-ge-old")), out)
lk.close()
rc, out = run("install", "--file", f, S14)
check("G14 stale temp folder deleted under lock", rc == 0 and leftovers(C14) == [], os.listdir(C14))

# ---------- G15 root ----------
real = os.getuid
os.getuid = lambda: 0
rc, out = run("list", S)
os.getuid = real
check("G15 root refused", rc == 1 and "run as game account" in out, out)

# ---------- G16 list ----------
S16 = steam("s16")
L2 = os.path.join(TMP, "lib2")
os.makedirs(os.path.join(L2, "steamapps"))
open(os.path.join(S16, "steamapps", "libraryfolders.vdf"), "w").write(
    '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' % (S16, L2))
run("install", "--file", f, S16)
h16 = os.path.join(S16, "compatibilitytools.d", "GE-Proton10-34")
os.makedirs(h16)
open(os.path.join(h16, "compatibilitytool.vdf"), "w").write("x" * 10)
open(os.path.join(S16, "config", "config.vdf"), "w").write(vdf([("7", TOP), ("8", TOP)]))
rc, out = run("list", S16)
ln = out.strip().splitlines()
check("G16 list: newest first, TSV tag/dir/marked/bytes/games, unmarked size ? without --sizes, slr4 absent",
      rc == 0 and ln[0].split("\t")[:3] == ["GE-Proton11-7", TOP, "1"] and ln[0].split("\t")[4] == "2"
      and ln[0].split("\t")[3].isdigit() and ln[1] == "GE-Proton10-34\tGE-Proton10-34\t0\t?\t0" and ln[2] == "slr4\tabsent", out)
open(os.path.join(L2, "steamapps", "appmanifest_4185400.acf"), "w").write("x")
rc, out = run("list", "--sizes", S16)
check("G16 list --sizes: unmarked size measured; slr4 installed from second library",
      rc == 0 and out.strip().splitlines()[1].split("\t")[3].isdigit() and out.strip().splitlines()[-1] == "slr4\tinstalled", out)
rc, out = run("install", "--file", f, S16)
check("G16 SLR present: no download line", "Steam Linux Runtime" not in out, out)

# ---------- G17 refusals ----------
S17 = steam("s17")
open(ge.CONF, "w").write("CLIENT=x86\n")
rc, out = run("install", "--file", f, S17)
check("G17 x86 client: refused with x86 Proton text", rc == 1 and "native ARM64 client only" in out, out)
open(ge.CONF, "w").write("CLIENT=arm64\n")
ge.page_size = lambda: 16384
rc, out = run("install", "--file", f, S17)
ge.page_size = lambda: 4096
check("G17 16K pages: refused", rc == 1 and "needs 4K memory pages (this system: 16K)" in out, out)
rc, out = run("install", "--file", f, os.path.join(TMP, "none", "Steam"))
check("G17 no client folder yet: sign in once", rc == 1 and "sign in once" in out, out)
ge.SPACE_FACTOR = 10 ** 9
rc, out = run("install", "--file", f, S17)
ge.SPACE_FACTOR = 5
check("G17 free space below need: refused before unpack", rc == 1 and "Needs about" in out
      and not os.path.exists(os.path.join(S17, "compatibilitytools.d", TOP)), out)
real_which = ge.shutil.which
rc, out = run("install", "bogus", S17)
check("G17 unknown argument: usage refusal", rc == 1 and "unknown argument" in out, out)

# ---------- G19 check ----------
S19 = steam("s19")
ge.api_releases = lambda t: R
rc, out = run("check", S19)
fl = out.strip().split("\t")
check("G19 check: release line tag, date, size, unpacked estimate, free bytes, new", rc == 0 and fl[:4] == ["release", "GE-Proton11-7", "2026-09-16", "645786140"]
      and int(fl[4]) > int(fl[3]) and fl[5].isdigit() and fl[6] == "new", out)
rc, out = run("check", S)
check("G19 check: installed tag -> current", rc == 0 and out.strip().endswith("\tcurrent"), out)


# fresh module: network functions back to real ones, curl call faked below
spec.loader.exec_module(ge)
ge.CONF, ge.COMPATMAP, ge.steam_up = os.path.join(TMP, "steam-arm.conf"), CM, (lambda: False)
real_run = ge.subprocess.run


def fake_curl(code, rc, body=""):
    def f(cmd, **kw):
        open(cmd[cmd.index("-o") + 1], "w").write(body)
        return ge.subprocess.CompletedProcess(cmd, rc, stdout=code, stderr=None)
    return f


msgs = {}
for code, crc in (("403", 22), ("404", 22), ("000", 7), ("500", 22)):
    ge.subprocess.run = fake_curl(code, crc)
    msgs[code] = run("check", S19)
ge.subprocess.run = fake_curl("200", 0, "not json")
msgs["bad"] = run("check", S19)
ge.subprocess.run = fake_curl("200", 18, '[{"tag_name": "GE-Pro')
msgs["cut"] = run("check", S19)
ge.subprocess.run = real_run
check("G22 HTTP 200 with curl status 18: download interrupted, curl status named, try again (box re-test B3)",
      msgs["cut"][0] == 2 and "download interrupted (curl status 18); try again" in msgs["cut"][1]
      and "not understood" not in msgs["cut"][1], msgs["cut"])
del msgs["cut"]
check("G19 check HTTP messages: limit, not found, offline, other status, unreadable; status 2",
      all(v[0] == 2 for v in msgs.values()) and "request limit" in msgs["403"][1] and "not found" in msgs["404"][1]
      and "could not be reached" in msgs["000"][1] and "HTTP 500" in msgs["500"][1] and "not understood" in msgs["bad"][1], msgs)
spec.loader.exec_module(ge)
ge.shutil.which = lambda n: None
rc, out = run("check", S19)
ge.shutil.which = real_which
check("G17 no curl: status 1, message names curl", rc == 1 and "curl is not installed" in out, out)

# ---------- G20 installer wiring ----------
ra = SRC[SRC.find("\nremove_all(){"):] if "\nremove_all(){" in SRC else ""
ra = ra[:ra.find("\n}\n")]
i_ge = ra.find("steam-arm-geproton.py remove-all")
i_rm = ra.find("/usr/local/lib/steam-arm-geproton.py", i_ge + 40)
check("G20 remove_all: remove-all as game account before helper rm -f; summary line",
      i_ge > 0 and "as_user python3 /usr/local/lib/steam-arm-geproton.py remove-all" in ra and i_rm > i_ge
      and "GE-Proton builds installed from settings menu" in ra, (i_ge, i_rm))

shutil.rmtree(TMP, ignore_errors=True)
print("passed %d, failed %d" % (len(NAMES) - len(FAILS), len(FAILS)))
sys.exit(1 if FAILS else 0)
