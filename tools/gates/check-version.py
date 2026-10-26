#!/usr/bin/env python3
"""Version-consistency gate: check-version.py [--work DIR] VERSION [--release].

Every SA_VERSION (installer 2, settings menu 1), embedded menu byte-identical, debian/control, build-deb.sh VERSION and
package name, CHANGELOG.md and doc/changelog top entries; built zips, repo copy and .deb (when present) carry the
same version; zip and package sidecars (when present) are one line naming Steam.ARM.<V>.zip or steam-arm-setup_<V>_arm64.deb
with its SHA-256. --release: changelog entries must not be unreleased. Exit 1 on any mismatch. Internal release tooling."""
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_paths import P  # noqa: E402
import debfile  # noqa: E402

START, END = "menu_app(){ cat <<'STEAMARMCONFIG'\n", "\nSTEAMARMCONFIG\n"
fails = []


def check(name, ok, info=""):
    print(("ok   " if ok else "FAIL ") + name + (" (%s)" % info if info and not ok else ""))
    if not ok:
        fails.append(name)


def embedded(inst_text):
    i = inst_text.index(START) + len(START)
    return inst_text[i:inst_text.index(END, i) + 1]


def main():
    args = sys.argv[1:]
    release = "--release" in args
    args = [a for a in args if a != "--release"]
    work = None
    if args[:1] == ["--work"] and len(args) == 3:
        work, args = args[1], args[2:]
    if len(args) != 1:
        sys.exit(__doc__)
    p = P(args[0])
    v = p.v
    if work:
        p.work, p.inst, p.cfg = work, os.path.join(work, "steam-arm-install.sh"), os.path.join(work, "steam-arm-config")
    inst, cfg = open(p.inst).read(), open(p.cfg).read()
    rd = lambda rel: open(os.path.join(p.work, rel)).read()
    sv = re.findall(r"(?m)^SA_VERSION=(.*)$", inst)
    check("installer SA_VERSION x2 = %s" % v, sv == [v, v], sv)
    sv = re.findall(r"(?m)^SA_VERSION=(.*)$", cfg)
    check("settings menu SA_VERSION = %s" % v, sv == [v], sv)
    check("embedded settings menu byte-identical", embedded(inst) == cfg)
    # menu fallback for installers without a "driver archive:" detect line (menu 2.3 and later)
    for ik, mk in (("PROVIDER_SHA256", "SA_PROVIDER_SHA"), ("PROVIDER_URL", "SA_PROVIDER_FILE")):
        if tuple(int(x) for x in v.split(".")[:2]) < (2, 3):
            break
        iv = re.findall(r"(?m)^%s=(.*)$" % ik, inst)
        mv = re.findall(r"(?m)^%s=(.*)$" % mk, cfg)
        if ik == "PROVIDER_URL":
            iv = [u.rsplit("/", 1)[-1] for u in iv]
        check("settings menu %s = installer %s" % (mk, ik), len(iv) == 1 and mv == iv, str((iv, mv)))
    ctl = re.findall(r"(?m)^Version: (.*)$", rd("debian/control"))
    check("debian/control Version: %s" % v, ctl == [v], ctl)
    bd = rd("build-deb.sh")
    check("build-deb.sh VERSION=%s" % v, re.findall(r"(?m)^VERSION=(.*)$", bd) == [v])
    check("build-deb.sh comment names %s" % p.deb_name, p.deb_name in bd)
    cl = re.findall(r"(?m)^## \[([^\]]+)\](.*)$", rd("CHANGELOG.md"))
    check("CHANGELOG.md top entry [%s]" % v, bool(cl) and cl[0][0] == v, cl[:1])
    if release:
        check("CHANGELOG.md top entry dated", bool(cl) and re.fullmatch(r" - [0-9]{4}-[0-9]{2}-[0-9]{2}", cl[0][1]), cl[:1])
    dc = rd("doc/changelog").split("\n", 1)[0]
    m = re.match(r"steam-arm-setup \(([^)]+)\) (\S+);", dc)
    check("doc/changelog top entry (%s)" % v, bool(m) and m.group(1) == v, dc)
    if release:
        check("doc/changelog top entry not UNRELEASED", bool(m) and m.group(2) != "UNRELEASED", dc)
        full = rd("doc/changelog")
        top = full.split("\nsteam-arm-setup (", 1)[0]
        check("doc/changelog top entry has no work-in-progress line", "Work in progress" not in top)
        dates = re.findall(r"(?m)^ -- .*>  (.+)$", full)
        check("doc/changelog top entry date differs from previous entry", len(dates) < 2 or dates[0] != dates[1], dates[:2])
    # built artifacts, when present
    if os.path.isfile(os.path.join(p.repo, "steam-arm-install.sh")):
        r = open(os.path.join(p.repo, "steam-arm-install.sh")).read()
        check("repo source installer SA_VERSION = %s" % v, re.findall(r"(?m)^SA_VERSION=(.*)$", r) == [v, v])
    for z, top in ((p.zip, "Steam ARM %s/" % v), (os.path.join(p.upload, "Steam ARM %s.zip" % v), "Steam ARM %s/" % v)):
        if not os.path.isfile(z):
            continue
        names = zipfile.ZipFile(z).namelist()
        check("%s: every member under %s" % (os.path.basename(z), top), all(n.startswith(top) for n in names))
        s = zipfile.ZipFile(z).read(top + "steam-arm-install.sh").decode()
        check("%s: installer SA_VERSION = %s" % (os.path.basename(z), v), re.findall(r"(?m)^SA_VERSION=(.*)$", s) == [v, v])
    # upgrade of 3.1 and later relies on release asset layout: Steam.ARM.<V>.zip, one top folder, sidecar line
    for z in (p.zip, os.path.join(p.upload, "Steam ARM %s.zip" % v), os.path.join(p.upload, p.gh_zip)):
        sc = z + ".sha256"
        if not (os.path.isfile(z) and os.path.isfile(sc)):
            continue
        import hashlib
        line = open(sc).read()
        want = "%s  %s\n" % (hashlib.sha256(open(z, "rb").read()).hexdigest(), p.gh_zip)
        check("%s: sidecar is one line '<sha256>  %s'" % (os.path.basename(sc), p.gh_zip), line == want, line[:120])
    # release asset steam-arm-setup_<V>_arm64.deb + .sha256 (package upgrade from menu relies on sidecar form)
    for k in (p.deb, os.path.join(p.upload, p.deb_name), os.path.join(p.work, p.deb_name)):
        sc = k + ".sha256"
        if not (os.path.isfile(k) and os.path.isfile(sc)):
            continue
        import hashlib
        line = open(sc).read()
        want = "%s  %s\n" % (hashlib.sha256(open(k, "rb").read()).hexdigest(), p.deb_name)
        check("%s: sidecar is one line '<sha256>  %s'" % (os.path.basename(sc), p.deb_name), line == want, line[:120])
    if os.path.isfile(p.deb):
        d = debfile.Deb(p.deb)
        check("%s: control Version %s" % (p.deb_name, v), d.field("Version") == v, d.field("Version"))
        s = d.member("./usr/share/steam-arm-setup/install.sh").decode()
        check("%s: install.sh SA_VERSION = %s" % (p.deb_name, v), re.findall(r"(?m)^SA_VERSION=(.*)$", s) == [v, v])
    print("version %s: %d failed" % (v, len(fails)))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
