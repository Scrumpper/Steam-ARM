#!/usr/bin/env python3
"""Docs style gate: check-docs.py [ROOT] [file ...]: published docs (top-level *.md, doc/README.md, doc/changelog, pull
request template) hold no em or en dash, no "ship" forms, no first person plural, no filler words (really, actual,
actually, very, simply, just), no articles in prose (route letter A, gfx=a|b and "Keep a Changelog" allowed), balanced
code fences and no dangling in-page links. Code spans, fenced code, URLs and link targets are not prose. Exit 1 on any hit."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_paths import internal  # noqa: E402

RULES = [
    ("dash", re.compile("[\u2014\u2013]")),
    ("ship", re.compile(r"(?i)\bship(?:s|ped|ping)?\b")),
    ("first person plural", re.compile(r"(?i)\b(?:we|our|ours|us)\b")),
    ("filler word", re.compile(r"(?i)\b(?:really|actual|actually|very|simply|just)\b")),
    ("article", re.compile(r"\b(?:[Tt]he|[Aa]n)\b|(?<![|/])\ba\b(?![|/])|\bA (?=[a-z])")),
]
ALLOWED = ("Keep a Changelog",)


def doc_files(root):
    out = sorted(f for f in os.listdir(root) if f.endswith(".md") and os.path.isfile(os.path.join(root, f)) and not internal(f))
    out += [p for p in ("doc/README.md", "doc/changelog", ".github/PULL_REQUEST_TEMPLATE.md") if os.path.isfile(os.path.join(root, p))]
    return out


def anchor(h):
    h = re.sub(r"`", "", h.lstrip("#").strip()).lower()
    return re.sub(r"\s", "-", re.sub(r"[^\w\s-]", "", h))


def check(path):
    hits = []
    lines = open(path, encoding="utf-8").read().split("\n")
    fence, fences = False, 0
    heads = set()
    for n, line in enumerate(lines, 1):
        if line.lstrip().startswith("```"):
            fence = not fence
            fences += 1
            continue
        if fence:
            continue
        if line.startswith("#"):
            heads.add(anchor(line))
        prose = re.sub(r"`[^`]*`|\]\([^)]*\)|<?https?://\S+|<[^>]+>", "", line)
        for a in ALLOWED:
            prose = prose.replace(a, "")
        for name, rx in RULES:
            for m in rx.finditer(prose):
                hits.append((n, name, prose[max(0, m.start() - 30):m.end() + 30].strip()))
    if fences % 2:
        hits.append((len(lines), "unbalanced code fences", ""))
    if path.endswith(".md"):
        text = "\n".join(lines)
        for a in sorted(set(re.findall(r"\]\(#([^)]+)\)", text))):
            if a not in heads:
                hits.append((0, "dangling in-page link", "#" + a))
    return hits


def main():
    args = sys.argv[1:]
    root = args.pop(0) if args and os.path.isdir(args[0]) else os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    files = args or doc_files(root)
    bad = 0
    for f in files:
        hits = check(os.path.join(root, f))
        bad += len(hits)
        print(("ok   " if not hits else "FAIL ") + f + ("" if not hits else " (%d)" % len(hits)))
        for n, name, ctx in hits[:20]:
            print("       %s:%d %s: %s" % (f, n, name, ctx))
    print("docs: %d files, %d hits" % (len(files), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
