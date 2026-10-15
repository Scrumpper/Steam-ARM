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


def internal(rel):
    b = os.path.basename(rel)
    return (rel in INTERNAL_NAMES or b in INTERNAL_NAMES or b.startswith(("REPLY-", "CHANGES.md")) or ".pre-" in b
            or b.endswith((".deb", "~", ".swp", ".bak", ".pre", ".pyc")) or "__pycache__" in rel
            or any(p.lower().startswith("research") or p == "design" for p in rel.split(os.sep)[:-1]))


def check_version(v):
    if not re.fullmatch(r"[0-9]+\.[0-9]+(\.[0-9]+)?", v or ""):
        raise SystemExit("version must look like 2.2, got %r" % v)
    return v


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
