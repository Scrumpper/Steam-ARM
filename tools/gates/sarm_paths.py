"""Paths of one Steam ARM version: work folder, tests, release folders, zips, deb. Internal release tooling."""
import os
import re

PROJ = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
DESK = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(PROJ))), "Steam ARM")
DOCS = ["README.md", "HOW-IT-WORKS.md", "CHANGELOG.md", "FEATURES.md", "COMPATIBILITY.md", "GAMES.md", "RESEARCH.md",
        "COMPARISON.md", "CREDITS.md"]
ASSET_DOCS = ["README.md", "CHANGELOG.md", "COMPATIBILITY.md", "GAMES.md"]
# work-folder files and folders that never leave the project (internal notes, design notes, menu working copy, tooling)
INTERNAL_NAMES = ("CHANGES.md", "steam-arm-config")
# repo copy (GitHub CI) carries test suites and gate tools beside work files; sources outside the work folder
GATE_FILES = ["sarm_paths.py", "debfile.py", "check-version.py", "check-heredocs.py", "check-removal.py", "scan-testtools.py",
              "privacy.py", "check-private.py", "check-docs.py", "deb-check.sh", "fetch-debian.sh", "deb-build-local.sh",
              "distro-matrix.sh", "distro-matrix-tree.py", "distro-matrix.lock", "fetch-image.py", "private-words.sha256"]
TESTS_SKIP = ("test_tools_22.sh",)


def internal(rel):
    b = os.path.basename(rel)
    return (rel in INTERNAL_NAMES or b in INTERNAL_NAMES or b.startswith(("REPLY-", "CHANGES.md")) or ".pre-" in b
            or b.endswith((".deb", "~", ".swp", ".bak", ".pre", ".pyc")) or "__pycache__" in rel
            or any(p.lower().startswith("research") or p == "design" for p in rel.split(os.sep)[:-1]))


def check_version(v):
    if not re.fullmatch(r"[0-9]+\.[0-9]+(\.[0-9]+)?", v or ""):
        raise SystemExit("version must look like 2.2, got %r" % v)
    return v


def repo_extra(p):
    """{repo path: source path} for tests/ (VERSION-tests minus internal suites) and tools/gates/ (this folder)."""
    extra = {}
    for dp, dn, fn in os.walk(p.tests):
        dn[:] = sorted(d for d in dn if d not in ("__pycache__", "venv"))
        for n in sorted(fn):
            q = os.path.join(dp, n)
            # regular files only: no local virtualenv link, no editor leftovers
            if n in TESTS_SKIP or n == "venv" or n.endswith((".pyc", "~", ".swp", ".bak")) or not os.path.isfile(q) or os.path.islink(q):
                continue
            extra[os.path.join("tests", os.path.relpath(q, p.tests))] = q
    for n in GATE_FILES:
        extra[os.path.join("tools", "gates", n)] = os.path.join(os.path.dirname(os.path.realpath(__file__)), n)
    return extra


class P:
    def __init__(self, v):
        v = check_version(v)
        self.v = v
        self.work = os.path.join(PROJ, v + "-work")
        self.tests = os.path.join(PROJ, v + "-tests")
        self.inst = os.path.join(self.work, "steam-arm-install.sh")
        self.cfg = os.path.join(self.work, "steam-arm-config")
        self.releases = os.path.join(DESK, "Releases")
        self.rel = os.path.join(self.releases, "Steam ARM " + v)
        self.repo = os.path.join(self.releases, "Steam ARM %s - GitHub Repo Source" % v)
        self.zip = os.path.join(self.releases, "Steam ARM %s.zip" % v)
        self.repo_zip = os.path.join(self.releases, "Steam ARM %s - GitHub Repo Source.zip" % v)
        self.deb_name = "steam-arm-setup_%s_arm64.deb" % v
        self.deb = os.path.join(self.releases, self.deb_name)
        self.upload = os.path.join(DESK, "Upload " + v)
        self.gh_zip = "Steam.ARM.%s.zip" % v
        self.tag = "sarm" + v.replace(".", "")
