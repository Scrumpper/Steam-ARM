#!/usr/bin/env python3
"""Syntax gate for every quoted heredoc in the installer and settings menu, plus the outer package scripts. Unquoted
heredocs that hold a program or data (shebang, .py/.json target, apt hook) are checked with expansions replaced by
placeholders; unquoted text heredocs are skipped. The settings menu file is checked once when its embedded copy in the
installer is byte-identical.

check-heredocs.py [--work DIR] VERSION [-v]: shell by shebang (dash -n for /bin/sh: host dash or one in ~/.cache/sarm-tools/*-rootfs,
else bash --posix -n),
python (compile), C (cc -fsyntax-only, Vulkan headers from /usr/include or ~/.cache/sarm-tools/Vulkan-Headers-*),
JSON (json.loads), desktop entries (desktop-file-validate), systemd units, udev rules and apt.conf hooks (shape only), text.
Exit 1 on any failure; a check that cannot run (tool missing) is a failure too. Internal release tooling."""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_paths import P  # noqa: E402

START = re.compile(r"""<<(-?)\s*(['"])([A-Za-z_][A-Za-z0-9_]*)\2""")
UNQ = re.compile(r"""<<(-?)\s*()([A-Z][A-Z0-9_]*)\b""")
EMB_START, EMB_END = "menu_app(){ cat <<'STEAMARMCONFIG'\n", "\nSTEAMARMCONFIG\n"
TEXT_TAGS = {"HW", "USAGE", "TITLES", "EOF", "VALVERULES", "RULE"}


def heredocs(path):
    """(line, tag, head, line text, body, quoted) for every heredoc, nested ones included."""
    lines = open(path, encoding="utf-8").read().split("\n")
    out = []
    for i, l in enumerate(lines):
        m = START.search(l)
        quoted = m is not None
        m = m or UNQ.search(l)
        if not m or l.lstrip().startswith("#"):
            continue
        dash, tag = m.group(1) == "-", m.group(3)
        body = []
        for j in range(i + 1, len(lines)):
            t = lines[j].lstrip("\t") if dash else lines[j]
            if t == tag:
                break
            body.append(lines[j])
        else:
            out.append((i + 1, tag, "unterminated", l, "", quoted))
            continue
        out.append((i + 1, tag, l[:m.start()], l, "\n".join(body) + "\n", quoted))
    return out


def expand(body, k):
    """Unquoted heredoc body with shell expansions replaced: JSON value position 0, JSON fragment empty, else x."""
    b = body.replace("\\\\", "\x01").replace("\\$", "\x02").replace("\\`", "\x03")
    out, i = [], 0
    while i < len(b):
        c = b[i]
        if c == "`":
            j = b.find("`", i + 1)
            i, rep_ = (len(b) if j < 0 else j + 1), "x"
        elif c == "$" and b[i + 1:i + 2] in ("(", "{"):
            close, depth, j = ")" if b[i + 1] == "(" else "}", 0, i + 1
            while j < len(b):
                depth += b[j] == b[i + 1]
                depth -= b[j] == close
                j += 1
                if depth == 0:
                    break
            i, rep_ = j, "x"
        elif c == "$" and re.match(r"[A-Za-z_0-9@#?*!-]", b[i + 1:i + 2]):
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*|.", b[i + 1:])
            i, rep_ = i + 1 + m.end(), "x"
        else:
            out.append(c)
            i += 1
            continue
        if k == "json":
            prev = "".join(out).rstrip()[-1:]
            in_str = "".join(out).count('"') % 2 == 1
            rep_ = "x" if in_str else ("0" if prev in (":", "[", ",") else "")
        out.append(rep_)
    return "".join(out).replace("\x01", "\\").replace("\x02", "$").replace("\x03", "`")


def kind(tag, head, line, body):
    first = body.split("\n", 1)[0]
    target = re.search(r">\s*\"?([^\s\"]+)\"?\s*$", head)
    target = target.group(1) if target else ""
    if tag == "unterminated":
        return "unterminated"
    if first.startswith("#!"):
        if "python" in first:
            return "python"
        return "sh" if re.search(r"/(ba)?sh\b", first) and "bash" not in first else "bash"
    if target.endswith(".py") or "python3 -" in head or tag.endswith("PY") or tag in ("SATUI", "PY", "PYEOF"):
        return "python"
    if target.endswith(".c") or tag == "CEOF":
        return "c"
    if target.endswith(".json") or tag == "JSON":
        return "json"
    if target.endswith(".desktop") or tag.endswith("DESK"):
        return "desktop"
    if target.endswith((".service", ".timer")) or tag == "UNIT":
        return "unit"
    if target.endswith(".rules") or tag in ("RULE", "VALVERULES"):
        return "rules"
    if tag == "STEAMARMCONFIG":
        return "bash"
    if tag == "APTHOOK":
        return "aptconf"
    if tag in TEXT_TAGS:
        return "text"
    return "unknown"


def vk_include():
    if os.path.isfile("/usr/include/vulkan/vk_layer.h"):
        return []
    c = sorted(glob.glob(os.path.expanduser("~/.cache/sarm-tools/Vulkan-Headers-*/include")))
    return ["-I", c[-1]] if c else None


def run(cmd, data=None):
    r = subprocess.run(cmd, input=data, capture_output=True, text=True)
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def check(k, body, tmp, name):
    p = os.path.join(tmp, name)
    open(p, "w").write(body)
    if k == "bash":
        return run(["bash", "-n", p])
    if k == "sh":
        d = shutil.which("dash") or next(iter(glob.glob(os.path.expanduser("~/.cache/sarm-tools/*-rootfs/usr/bin/dash"))), None)
        if d:
            return run([d, "-n", p])
        ok, msg = run(["bash", "--posix", "-n", p])
        return ok, msg or "dash not found; bash --posix -n used"
    if k == "python":
        try:
            compile(body, name, "exec")
            return True, ""
        except SyntaxError as e:
            return False, str(e)
    if k == "c":
        inc = vk_include()
        if inc is None:
            return False, "Vulkan headers missing (fetch Vulkan-Headers into ~/.cache/sarm-tools)"
        cc = shutil.which("cc") or shutil.which("gcc")
        return run([cc, "-fsyntax-only", "-Wall", "-Werror=implicit-function-declaration", "-x", "c"] + inc + [p])
    if k == "json":
        try:
            json.loads(body)
            return True, ""
        except ValueError as e:
            return False, str(e)
    if k == "desktop":
        if not shutil.which("desktop-file-validate"):
            return False, "desktop-file-validate not found"
        q = p + ".desktop"
        os.rename(p, q)
        return run(["desktop-file-validate", q])
    if k == "unit":
        ok = re.search(r"(?m)^\[Unit\]$", body) and re.search(r"(?m)^\[(Service|Timer)\]$", body) \
            and all(re.fullmatch(r"\[[A-Za-z]+\]|[A-Za-z]+=.*|#.*|", l) for l in body.splitlines())
        return bool(ok), "" if ok else "unit file shape"
    if k == "rules":
        bad = [l for l in body.splitlines() if l.strip() and not l.lstrip().startswith("#")
               and not re.search(r'[A-Z_{}]+(==|!=|=|\+=)"', l)]
        return not bad, "; ".join(bad[:3])
    if k == "aptconf":
        t = re.sub(r'"(\\.|[^"\\])*"', '""', "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("//")))
        ok = '"' not in t.replace('""', "") and t.count("{") == t.count("}") and t.strip().endswith(";") \
            and all(x.strip().endswith((";", "{")) or not x.strip() for x in t.splitlines())
        return ok, "" if ok else "apt.conf shape (quotes, braces, ending ;)"
    if k == "text":
        return True, ""
    return False, "unknown heredoc kind"


def main():
    args = [a for a in sys.argv[1:] if a != "-v"]
    verbose = "-v" in sys.argv
    work = None
    if args[:1] == ["--work"] and len(args) == 3:
        work, args = args[1], args[2:]
    if len(args) != 1:
        sys.exit(__doc__)
    p = P(args[0])
    if work:
        p.work, p.inst, p.cfg = work, os.path.join(work, "steam-arm-install.sh"), os.path.join(work, "steam-arm-config")
    tmp = tempfile.mkdtemp(prefix="sarm-heredocs-")
    fails = counts = skipped = 0
    kinds = {}
    try:
        inst_text = open(p.inst).read()
        i = inst_text.find(EMB_START)
        same = i >= 0 and inst_text[i + len(EMB_START):inst_text.find(EMB_END, i) + 1] == open(p.cfg).read()
        targets = [p.inst] if same else [p.inst, p.cfg]
        print("settings menu: %s" % ("embedded copy identical, its heredocs checked once (in installer)" if same
                                     else "embedded copy differs, both checked"))
        for f in targets:
            for ln, tag, head, line, body, quoted in heredocs(f):
                k = kind(tag, head, line, body) if head != "unterminated" else "unterminated"
                if not quoted and k in ("text", "unknown"):
                    skipped += 1
                    continue
                if not quoted and k != "unterminated":
                    body = expand(body, k)
                    k_label = k + ", unquoted"
                else:
                    k_label = k
                ok, msg = (False, "no end line") if k == "unterminated" else check(k, body, tmp, "%s-%d" % (tag, ln))
                counts += 1
                kinds[k] = kinds.get(k, 0) + 1
                if not ok or verbose:
                    print("%s %s:%d %s (%s) %s" % ("ok  " if ok else "FAIL", os.path.basename(f), ln, tag, k_label, msg[:300]))
                fails += not ok
        # outer files: package scripts and the work copies themselves
        for rel, k in (("steam-arm-install.sh", "bash"), ("steam-arm-config", "bash"), ("bin/steam-arm-setup", "sh"),
                       ("build-deb.sh", "sh"), ("debian/postinst", "sh"), ("debian/prerm", "sh"),
                       ("tools/build-driver-archive.sh", "bash"), ("debian/steam-arm-setup.desktop", "desktop")):
            f = os.path.join(p.work, rel)
            if not os.path.exists(f):
                continue
            ok, msg = check(k, open(f).read(), tmp, os.path.basename(rel))
            counts += 1
            if not ok or verbose:
                print("%s %s (%s) %s" % ("ok  " if ok else "FAIL", rel, k, msg[:300]))
            fails += not ok
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("heredocs: %d checked (%s), %d failed; %d unquoted text heredocs not checked"
          % (counts, ", ".join("%s %d" % kv for kv in sorted(kinds.items())), fails, skipped))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
