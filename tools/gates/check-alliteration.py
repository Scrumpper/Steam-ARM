#!/usr/bin/env python3
"""Alliteration gate: check-alliteration.py [ROOT] [file ...]: published docs (check-docs.py list) hold no sentence with
three or more words sharing an initial letter inside any four-word window. Code spans, fenced and indented code, link
targets, URLs, table rows, stopwords and words of one or two letters are not words here; names in
alliteration-allow.txt keep their place in the window but never count. Allow-list: one word per line, optional
"# reason" after it, case does not matter; proper and product names only (Panfrost, PanVK, Panthor...), never ordinary
words. Exit 1 on any hit."""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
# doc_files() lives in check-docs.py; hyphen in the name needs importlib
_spec = importlib.util.spec_from_file_location("check_docs", os.path.join(HERE, "check-docs.py"))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
doc_files = _mod.doc_files

STOP = set("a an the and or of to in on for with by at from as is are was be it its this that these those not no if then"
           " than when while into onto over under up out off per via each every all any some one two".split())
ALLOW_FILE = os.path.join(HERE, "alliteration-allow.txt")


def allow_words():
    out = set()
    if os.path.isfile(ALLOW_FILE):
        for line in open(ALLOW_FILE, encoding="utf-8"):
            w = line.split("#", 1)[0].strip().lower()
            if w:
                out.add(w)
    return out


ALLOW = allow_words()


def words(s):
    s = re.sub(r"`[^`]*`", " ", s)
    s = re.sub(r"\]\([^)]*\)", "]", s)
    s = re.sub(r"https?://\S+", " ", s)
    return [w for w in re.findall(r"[A-Za-z][A-Za-z'-]*", s) if len(w) > 2 and w.lower() not in STOP]


def initial(w):
    """First letter, lower case; empty for an allow-listed name so it never matches."""
    return "" if w.lower().strip("'-") in ALLOW else w[0].lower()


def check(path):
    hits = []
    fence = False
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace").read().split("\n"), 1):
        if line.strip().startswith("```"):
            fence = not fence
            continue
        if fence or line.startswith("|") or line.startswith("    "):
            continue
        for sent in re.split(r"(?<=[.;:!?])\s+", line):
            ws = words(sent)
            for i in range(len(ws) - 2):
                win = ws[i:i + 4]
                if initial(win[0]) and sum(1 for w in win if initial(w) == initial(win[0])) >= 3:
                    hits.append((n, " ".join(win), sent.strip()[:110]))
                    break
    return hits


def main():
    args = sys.argv[1:]
    root = args.pop(0) if args and os.path.isdir(args[0]) else os.path.dirname(os.path.dirname(HERE))
    files = args or doc_files(root)
    bad = 0
    for f in files:
        hits = check(os.path.join(root, f))
        bad += len(hits)
        print(("ok   " if not hits else "FAIL ") + f + ("" if not hits else " (%d)" % len(hits)))
        for n, win, sent in hits[:20]:
            print("       %s:%d %s | %s" % (f, n, win, sent))
    print("alliteration: %d files, %d hits" % (len(files), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
