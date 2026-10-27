#!/usr/bin/env python3
"""Alliteration gate: check-alliteration.py [ROOT] [file ...]: published docs (check-docs.py list) hold no sentence with
three or more words sharing an initial letter inside any four-word window, and no repeated openers: the same first word
on neighbouring bullets or on neighbouring sentences of one paragraph, a determiner (one, nothing, every, each, single,
all, no, none, same, first, never, only, any) opening two comma or semicolon clauses of one sentence, and no slogan
phrases "one release/click/script/installer/command/step/file/line/run/image", "nothing bundled/installed/
else/more". Code spans, fenced and indented code, link targets, URLs, table rows, headings, numbered lists, bullets led
by a code span or a link, stopwords and words of one or two letters are not words here. Names in alliteration-allow.txt
keep their place in the window but never count; opener words in openers-allow.txt (optional "FILE:" scope, "# reason")
may repeat. Allow-lists: proper and product names and unavoidable requirement lists only, never ordinary words.
Exit 1 on any hit."""
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
# function words that may open neighbouring items without reading as a repeat
OPEN_STOP = set("a an the and or of to in on for with by at from as if then when while so not or yes".split())
# determiners that read as a slogan when they open two clauses of one sentence
CLAUSE = set("one nothing every each single all no none same first never only any".split())
PHRASES = re.compile(r"(?i)\b(one (?:release|click|script|installer|command|step|file|line|run|image)"
                     r"|nothing (?:bundled|installed|else|more))\b")
ALLOW_FILE = os.path.join(HERE, "alliteration-allow.txt")
OPEN_ALLOW_FILE = os.path.join(HERE, "openers-allow.txt")


def allow_words(path):
    """Set of (scope, word); scope "" means every file."""
    out = set()
    if os.path.isfile(path):
        for line in open(path, encoding="utf-8"):
            w = line.split("#", 1)[0].strip().lower()
            if w:
                scope, _, word = w.rpartition(":")
                out.add((scope, word))
    return out


ALLOW = {w for _, w in allow_words(ALLOW_FILE)}
OPEN_ALLOW = allow_words(OPEN_ALLOW_FILE)


def prose(s):
    s = re.sub(r"`[^`]*`", " ", s)
    s = re.sub(r"\]\([^)]*\)", "]", s)
    return re.sub(r"https?://\S+", " ", s)


def words(s):
    return [w for w in re.findall(r"[A-Za-z][A-Za-z'-]*", prose(s)) if len(w) > 2 and w.lower() not in STOP]


def initial(w):
    """First letter, lower case; empty for an allow-listed name so it never matches."""
    return "" if w.lower().strip("'-") in ALLOW else w[0].lower()


def opener(s):
    """First prose word of a bullet, sentence or clause, lower case; None when none or a function word."""
    s = re.sub(r"^[\s>*\-+]+", "", s)
    s = re.sub(r"^[*_\[\]\"'(]+|[^\x00-\x7f]+", "", s.strip()).strip()
    m = re.match(r"([A-Za-z][A-Za-z'-]*)", s)
    w = m.group(1).lower() if m else None
    return None if w is None or w in OPEN_STOP else w


def allowed(rel, w):
    rel = rel.lower()
    return ("", w) in OPEN_ALLOW or (os.path.basename(rel), w) in OPEN_ALLOW or (rel, w) in OPEN_ALLOW


BULLET = re.compile(r"^\s*[-*+]\s+")
SKIP_BULLET = re.compile(r"^\s*[-*+]\s+(`|\[)")
NUMBERED = re.compile(r"^\s*\d+[.)]\s")


def blocks(lines):
    """(kind, first line number, [(line number, text)]) per bullet item or paragraph; kind in bullet, skip, para.
    Headings, numbered items, tables, blank lines and fences end a block and separate bullet runs (kind break)."""
    out = []
    fence = False
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if s.startswith("```"):
            fence = not fence
            out.append(("break", n, []))
            continue
        if fence or not s or s.startswith("#") or s.startswith("|") or NUMBERED.match(line):
            out.append(("break", n, []))
            continue
        if BULLET.match(line):
            out.append(("skip" if SKIP_BULLET.match(line) else "bullet", n, [(n, prose(BULLET.sub("", line, 1)))]))
        elif out and out[-1][0] in ("bullet", "skip", "para") and (line.startswith(" ") or out[-1][0] == "para"):
            out[-1][2].append((n, prose(s)))
        elif line.startswith("    "):
            out.append(("break", n, []))
        else:
            out.append(("para", n, [(n, prose(s))]))
    return out


def sentences(pieces):
    """(line number, sentence) over joined pieces of one block."""
    text, starts = "", []
    for n, t in pieces:
        starts.append((len(text), n))
        text += (" " if text else "") + t
    pos = 0
    for s in re.split(r"(?<=[.!?])\s+", text):
        if not s.strip():
            continue
        at = text.find(s, pos)
        pos = at + len(s)
        yield max(n for o, n in starts if o <= at), s


def check(path, rel=""):
    """Alliteration windows: (line, window, sentence). Openers: (line, kind, word, text)."""
    hits, ohits = [], []
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    fence = False
    for n, line in enumerate(lines, 1):
        if line.strip().startswith("```"):
            fence = not fence
            continue
        if fence or line.startswith("|") or line.startswith("    "):
            continue
        for m in PHRASES.finditer(prose(line)):
            if not line.lstrip().startswith("#"):
                ohits.append((n, "phrase", m.group(1), line.strip()[:110]))
        for sent in re.split(r"(?<=[.;:!?])\s+", line):
            ws = words(sent)
            for i in range(len(ws) - 2):
                win = ws[i:i + 4]
                if initial(win[0]) and sum(1 for w in win if initial(w) == initial(win[0])) >= 3:
                    hits.append((n, " ".join(win), sent.strip()[:110]))
                    break
    prev = None
    for kind, n, pieces in blocks(lines):
        if kind == "break":
            prev = None
            continue
        w = opener(pieces[0][1]) if kind == "bullet" else None
        if kind == "bullet" and w and w == prev and not allowed(rel, w):
            ohits.append((n, "bullet opener", w, pieces[0][1].strip()[:110]))
        prev = w if kind in ("bullet", "skip") else None
        last = None
        for ln, s in sentences(pieces):
            sw = opener(s)
            if sw and sw == last and not allowed(rel, sw):
                ohits.append((ln, "sentence opener", sw, s.strip()[:110]))
            last = sw
            cl = [opener(c) for c in re.split(r"[;,]\s+", s)]
            cl = [c for c in cl if c in CLAUSE]
            for c in cl:
                if cl.count(c) >= 2 and not allowed(rel, c):
                    ohits.append((ln, "clause opener", c, s.strip()[:110]))
                    break
    return hits, ohits


def main():
    args = sys.argv[1:]
    root = args.pop(0) if args and os.path.isdir(args[0]) else os.path.dirname(os.path.dirname(HERE))
    # doc/changelog: package changelog, past entries frozen (published package bytes)
    files = args or [f for f in doc_files(root) if f != "doc/changelog"]
    bad = windows = openers = 0
    for f in files:
        hits, ohits = check(os.path.join(root, f), f)
        n = len(hits) + len(ohits)
        bad += n
        windows += len(hits)
        openers += len(ohits)
        print(("ok   " if not n else "FAIL ") + f + ("" if not n else " (%d)" % n))
        for ln, win, sent in hits[:20]:
            print("       %s:%d %s | %s" % (f, ln, win, sent))
        for ln, kind, w, text in ohits[:40]:
            print("       %s:%d %s '%s' | %s" % (f, ln, kind, w, text))
    print("alliteration: %d files, %d hits (%d windows, %d openers)" % (len(files), bad, windows, openers))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
