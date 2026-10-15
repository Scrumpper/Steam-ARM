"""Private words: account, host and machine names, other flavour names. Kept as sha256 of lower-case word or word pair
(private-words.sha256 beside this file: hash and tag per line); SARM_PRIVATE_WORDS names an extra plain list (one
word per line) for local runs. hits(text, file) gives (word, tag) pairs, minus tags allowed for that file name."""
import hashlib
import os
import re

HERE = os.path.dirname(os.path.realpath(__file__))
WORD = re.compile(r"[a-z0-9]+")
# installer retires an install of other flavour: its paths and unit names stay readable there
ALLOW = {("steam-arm-install.sh", "flavour")}


def sha(w):
    return hashlib.sha256(w.encode()).hexdigest()


def _load():
    hs = {}
    with open(os.path.join(HERE, "private-words.sha256")) as f:
        for line in f:
            line = line.split("#", 1)[0].split()
            if len(line) == 2:
                hs[line[0]] = line[1]
    extra = os.environ.get("SARM_PRIVATE_WORDS")
    if extra and os.path.isfile(extra):
        for w in open(extra).read().splitlines():
            if w.strip():
                hs[sha(" ".join(WORD.findall(w.lower())))] = "local"
    return hs


HASHES = _load()


def hits(text, file=""):
    ws = WORD.findall(text.lower())
    out = set()
    for w in ws + [a + " " + b for a, b in zip(ws, ws[1:])]:
        tag = HASHES.get(sha(w))
        if tag and (file, tag) not in ALLOW:
            out.add((w, tag))
    return sorted(out)
