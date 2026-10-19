#!/usr/bin/env python3
"""Removal-list drift gate: check-removal.py [--work DIR] VERSION [-v].

Collects every path setup code writes (redirects, cat > X <<TAG, install, install -d, cp, ln, mv, gcc -o, user_write,
mkdir, touch, tee, curl -o, wget -O, dd of=), heredoc bodies and the embedded settings menu left out (their writes happen at run time of those programs),
resolves simple VAR=/path assignments, and checks each against --remove (remove_all, retire_other and the helpers
they call): literal path or variable (whole path, not a prefix of a longer one), glob, removed folder, or a listed
keep-by-design reason. Helpers in RUNTIME write in the client folder when run; setup writing one needs its cleanup
call in removal code. Folders the settings menu writes as root (MENU_DIRS) must be deleted by removal.
Exit 1 on any uncovered path. Internal release tooling."""
import fnmatch
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_paths import P  # noqa: E402

HD = re.compile(r"""<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1""")
# removal-side functions: their bodies count as removal text
REMOVERS = ("remove_all", "retire_other", "mali_tree_remove", "legacy_mesa_restore", "rfs_unguard", "mc_restore",
            "kwin_rule_remove", "ps_remove", "fstab_edit", "kde_input")
# parents other packages share; mkdir -p of these is no own write
SHARED_DIRS = (r"^/(etc|usr|usr/local|usr/share|usr/local/share|usr/local/lib|opt)(/(bin|sbin|lib|apt|apt/keyrings|"
               r"apt/sources\.list\.d|apt/preferences\.d|apt/apt\.conf\.d|applications|icons|icons/hicolor(/[^/]+(/apps)?)?|"
               r"udev|udev/rules\.d|xdg|xdg/autostart|sudoers\.d|sysctl\.d|modules-load\.d|security|security/limits\.d|"
               r"systemd|systemd/system|systemd/user|tmpfiles\.d|vulkan|vulkan/implicit_layer\.d|vulkan/icd\.d|"
               r"polkit-1|polkit-1/rules\.d|doc|man|share|lib/systemd/system|profile\.d|environment\.d))?/?$")
# kept on purpose (reason shown); regex on the resolved path
KEEP = [
    (r"^/var/backups/", "backup copies made for the person, named in setup and removal output"),
    (r"^/etc/fstab(\.steam-arm.*)?$", "/dev/shm line taken out by fstab_edit drop when setup added it"),
    (r"^\$FWCFG|^/boot/", "Pi firmware config: line taken out by ps_remove; backup stays"),
    (r"^/root/steam-arm-password-", "password of account setup created; removal names it, account stays"),
    (r"^\$(RFS|PART|part|STAGE|SRC|tmp|t|T|TMPD|W|STATE)\b|Ubuntu_24_04", "RootFS or temporary staging, handled by its own logic or trap"),
    (r"^/opt/fex-rootfs/", "x86-64 RootFS: deleted only with --purge when setup downloaded it"),
    (r"^\$(ARMHOME|armhome|S|D|d|NEW|ft|FT)\b|/\.local/share/steam-arm/|\$ARMHOME_DIR", "inside client folder: deleted with it on typed request"),
    (r"^\$(UHOME|REALHOME|uh|HOME)/\.local/share/Steam/", "client data"),
    (r"^/etc/apt/sources\.list\.d/[^/]*\.disabled$", "foreign Debian-codename FEX source renamed by setup, named in its warning"),
    (r"^\$LOG|/\.cache/steam-arm/", "setup logs: .cache/steam-arm removed per account"),
    (r"^\$PWFILE$", "password file of created account, named in removal output"),
    (r"^\$tb$|^\$tar$|^\$utar$", "backup written by removal itself"),
    (r"^\$(LOCK|PIDF)$|^/run/", "runtime lock, gone at reboot"),
    (r"^/etc/sudoers\.d/steam-arm\.tmp", "temporary, renamed into place"),
    (SHARED_DIRS, "shared system folder (mkdir -p of a parent other packages use)"),
]
# writes inside helpers whose target is an argument or a loop variable: reason per function
FUNC_KEEP = {
    "user_write": "writes its path argument; call sites checked",
    "rfs_guard": "package tool guards inside the RootFS; rfs_unguard puts the real tools back",
    "fex_source_debian": "foreign Debian-codename FEX source renamed .disabled, named in its warning",
    "mali_tree_build": "second RootFS tree staged by hard-link copy; mali_tree_remove deletes it",
}
# single lines whose target is a positional argument of sh -c
LINE_KEEP = [(r'mv "\$1/steamrtarm64" "\$2"', "client program folder ($D) inside client folder")]
# writers whose name comes from a loop: every listed removal glob must be in the removal text
COVERS = [(r"^/usr/share/icons/hicolor/.*/apps/\$n\.png$",
           ["/usr/share/icons/hicolor/*/apps/steam-arm.png", "/usr/share/icons/hicolor/*/apps/steam-arm-desktop.png"])]
# folders the settings menu writes as root (snapshots, version records, upgrade downloads): removal deletes them
MENU_DIRS = ("/var/lib/steam-arm", "/var/cache/steam-arm")
# helper path, removal call that undoes its run-time writes
RUNTIME = [("/usr/local/lib/steam-arm-geproton.py", r"steam-arm-geproton\.py remove-all"),
           ("/usr/local/lib/steam-arm-x86client.py", r"steam-arm-x86client\.py restore")]
# same account home under other names in setup and removal code
ALIASES = [(r"\$\{?(UHOME|REALHOME)\}?", "$uh"), (r"\$\{?ARMHOME\}?(?![_A-Za-z])", "$armhome")]


def strip_heredocs(lines):
    out, i = [], 0
    while i < len(lines):
        l = lines[i]
        out.append((i + 1, l))
        m = HD.search(l)
        if m and not l.lstrip().startswith("#"):
            tag, dash = m.group(2), "<<-" in l
            j = i + 1
            while j < len(lines) and (lines[j].lstrip("\t") if dash else lines[j]) != tag:
                j += 1
            i = j
        i += 1
    return out


def func_body(text, name):
    m = re.search(r"(?m)^%s\(\)\s*\{" % re.escape(name), text)
    if not m:
        return ""
    e = re.search(r"(?m)^\}", text[m.end():])
    return text[m.start():m.end() + (e.end() if e else 0)]


TGT = r"""("[^"]+"|'[^']+'|[^\s;&|<>()]+)"""
ARGS = r"""((?:\s+(?:"[^"]+"|'[^']+'|[^\s;&|<>()]+))+)"""
WRITE = [
    re.compile(r"(?<![0-9&>])>{1,2}\s*" + TGT),
    re.compile(r"\binstall\b(?:\s+-[A-Za-z]+(?:\s+[0-9a-z]+)?)*\s+" + TGT + r"\s+" + TGT),
    re.compile(r"\b(?:cp|mv)\b(?:\s+-[A-Za-z-]+)*\s+(?:--\s+)?" + TGT + r"\s+" + TGT + r"\s*(?:$|[;&|)])"),
    re.compile(r"\bln\s+-[sfnT]+\s+" + TGT + r"\s+" + TGT),
    re.compile(r"\bgcc\b.*?\s-o\s+" + TGT),
    re.compile(r"\buser_write\s+" + TGT),
    re.compile(r"\bdesk_icon\s+\S+\s+" + TGT),
    re.compile(r"\btee\b(?:\s+-[a-z]+)*\s+" + TGT),
    re.compile(r"\bcurl\b[^;&|]*?\s(?:-o|--output)\s+" + TGT),
    re.compile(r"\bwget\b[^;&|]*?\s-O\s*" + TGT),
    re.compile(r"\bdd\b[^;&|]*?\sof=" + TGT),
]
# writers with several path arguments (options and modes skipped)
MULTI = [
    re.compile(r"\bmkdir\b" + ARGS),
    re.compile(r"\btouch\b" + ARGS),
    re.compile(r"\binstall\s+(?:-[A-Za-z]*d[A-Za-z]*\b)(?:\s+-[A-Za-z]+(?:\s+[0-9a-z]+)?)*" + ARGS),
]


def targets(code):
    found = []
    for ln, l in code:
        s = l.split(" #", 1)[0] if not l.lstrip().startswith("#") else ""
        if not s.strip():
            continue
        ts = [m.group(m.lastindex) for rx in WRITE for m in rx.finditer(s)]
        for rx in MULTI:
            for m in rx.finditer(s):
                ts += [a for a in re.findall(TGT, m.group(1)) if not a.startswith("-") and not a.isdigit()]
        for t in ts:
            t = t.strip("\"'")
            if t.startswith(("/dev/", "/proc/", "/sys/", "$(dirname")) or t in ("&2", "&1", "/dev/null") or t.startswith("&"):
                continue
            if (t.startswith("/") or t.startswith("$")) and not re.search(r"\bapt(-get)?\s+install\b", s):
                found.append((ln, t, l.strip()))
    return found


def listed(tok, rm_text):
    """tok in removal text as a whole path: not followed by more path characters."""
    return re.search(re.escape(tok) + r"(?![\w.-])", rm_text) is not None


def resolve(t, assigns):
    m = re.match(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(.*)$", t)
    if m and m.group(1) in assigns:
        return assigns[m.group(1)] + m.group(2)
    return t


def main():
    args = [a for a in sys.argv[1:] if a != "-v"]
    verbose = "-v" in sys.argv
    work = None
    if args[:1] == ["--work"] and len(args) == 3:
        work, args = args[1], args[2:]
    if len(args) != 1:
        sys.exit(__doc__)
    p = P(args[0])
    inst = os.path.join(work, "steam-arm-install.sh") if work else p.inst
    text = open(inst).read()
    lines = text.split("\n")
    code = strip_heredocs(lines)
    # setup code only: settings menu embed and functions that run the removal are not writers
    rm_text = "\n".join(func_body(text, f) for f in REMOVERS)
    # for p in a b; do ... $p ... done: each value written out, so loop-built paths count as listed
    for m in re.finditer(r"\bfor (\w+) in ([^;\n]+); do(.*?)\bdone\b", rm_text, re.S):
        rm_text += "\n" + "\n".join(re.sub(r"\$\{?%s\}?" % m.group(1), w, m.group(3)) for w in m.group(2).split())
    rm_spans = [(text[:text.find(func_body(text, f))].count("\n") + 1,
                 text[:text.find(func_body(text, f))].count("\n") + func_body(text, f).count("\n") + 1)
                for f in REMOVERS if func_body(text, f)]
    code = [(ln, l) for ln, l in code if not any(a <= ln <= b for a, b in rm_spans)]
    assigns = {}
    for ln, l in code:
        for m in re.finditer(r"(?:^|;\s*)(?:local\s+|readonly\s+|export\s+)?([A-Z][A-Z0-9_]*)=(?:\"([/$][^\"`]*)\"|(/[^\s\"$;]*))", l.strip()):
            val = m.group(2) or m.group(3)
            if m.group(1) not in assigns and "$(" not in val:
                assigns[m.group(1)] = val
    # file globs only (case patterns such as "$oh"/* or /etc/sysctl.d/* stand for whole folders)
    rm_globs = set(g for g in re.findall(r"(?<![\w$])(/[A-Za-z0-9_./*{}-]+)", rm_text)
                   if not g.endswith("/*") and g.count("/") >= 3)
    rm_vars = set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", rm_text))
    rm_dirs = set()
    for m in re.finditer(r"\brm -rf\s+([^;\n|&]+)", rm_text):
        for w in m.group(1).split():
            w = w.strip('"')
            rm_dirs.add(resolve(w, assigns))
    funcs = []
    for i, l in enumerate(lines, 1):
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{", l)
        if m:
            funcs.append((i, m.group(1)))

    def enclosing(ln):
        name = None
        for i, n in funcs:
            if i > ln:
                break
            body = func_body(text, n)
            if i + body.count("\n") >= ln:
                name = n
        return name

    fails, rows = 0, []
    seen = set()
    for ln, raw, line in targets(code):
        path = resolve(raw, assigns)
        key = path
        if key in seen:
            continue
        seen.add(key)
        how = None
        v = re.match(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$", raw)
        alias, palias = raw, path
        for rx, to in ALIASES:
            alias, palias = re.sub(rx, to, alias), re.sub(rx, to, palias)
        fn = enclosing(ln)
        bare_local = v and v.group(1) != v.group(1).upper()
        if bare_local:
            how = None
        elif v and v.group(1) in rm_vars:
            how = "listed as $" + v.group(1)
        elif (not v and (listed(raw, rm_text) or listed(alias, rm_text))) or listed(palias, rm_text) \
                or (path.startswith("/") and listed(path, rm_text)):
            how = "listed"
        elif path.startswith("/") and any(fnmatch.fnmatch(path, g) for g in rm_globs if "*" in g):
            how = "glob"
        elif any(path == d or path.startswith(d.rstrip("/") + "/") for d in rm_dirs if d):
            how = "folder removed"
        if how is None:
            for rx, globs in COVERS:
                if re.search(rx, path):
                    lost = [g for g in globs if g not in rm_text]
                    how = None if lost else "globs " + ", ".join(globs)
        if how is None and fn in FUNC_KEEP:
            how = "kept: %s (%s)" % (FUNC_KEEP[fn], fn)
        if how is None:
            how = next(("kept: " + w for rx, w in LINE_KEEP if re.search(rx, line)), None)
        if how is None:
            how = next(("kept: " + w for rx, w in KEEP if re.search(rx, path) or re.search(rx, raw)), None)
        if how is None:
            fails += 1
            rows.append("FAIL %5d %s  (%s)" % (ln, path, line[:120]))
        elif verbose:
            rows.append("ok   %5d %-70s %s" % (ln, path, how))
    for helper, call in RUNTIME:
        if re.search(r"(?m)^cat > %s <<" % re.escape(helper), text) and not re.search(call, rm_text):
            fails += 1
            rows.append("FAIL runtime writes of %s not removed (no %s call in removal code)" % (helper, call.replace("\\", "")))
    for d in MENU_DIRS:
        if d not in rm_dirs:
            fails += 1
            rows.append("FAIL %s (written by settings menu) not deleted by removal (rm -rf)" % d)
    print("\n".join(rows))
    print("removal drift: %d written paths, %d not covered by --remove" % (len(seen), fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
