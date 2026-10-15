#!/usr/bin/env python3
"""Privacy gate: check-private.py [ROOT]: every file under ROOT (default: repository root above tools/) free of private
words (privacy.py), 192.168.x.x addresses, e-mail addresses other than noreply and example domains, home folders and
agent job paths; internal work files (sarm_paths.internal) left out. Reports file, line and tag only. Exit 1 on any hit."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import privacy  # noqa: E402
from sarm_paths import internal  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
SKIP_DIRS = {".git", "__pycache__", "build"}
RULES = [
    ("lan address", re.compile(r"\b192\.168\.\d{1,3}\.\d{1,3}\b")),
    ("e-mail", re.compile(r"[A-Za-z0-9._%+-]+@(?!(?:[a-z0-9-]+\.)*(?:example\.(?:com|org|net|invalid)|users\.noreply\.github\.com)\b)"
                          r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.(?:com|net|org|de|io|me)\b")),
    ("home folder", re.compile(r"/home/(?!(?:tester|u|g|steam|runner|user|ga|gb|gx|alice|zed|games)\b)[a-z][a-z0-9_-]{2,}/(?:Desktop|\.claude|\.cache/sarm)")),
    ("agent path", re.compile(r"\.claude/(?:jobs|projects)/")),
]


def main():
    bad = 0
    files = 0
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, ROOT)
            if os.path.islink(p) or not os.path.isfile(p) or internal(rel):
                continue
            files += 1
            data = open(p, "rb").read()
            text = data.decode("utf-8", "replace")
            for n, line in enumerate(text.splitlines(), 1):
                tags = [t for _, t in privacy.hits(line, f)] + [name for name, rx in RULES if rx.search(line)]
                for t in sorted(set(tags)):
                    print("FAIL %s:%d %s" % (rel, n, t))
                    bad += 1
    print("privacy: %d files, %d hits" % (files, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
