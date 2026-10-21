#!/usr/bin/env python3
"""Scan Steam ARM deliverables for test tooling: test files, shims, bench tools, test hooks in the installer and menu app.

Every environment variable read by the installer (shell, embedded python, C layer) and the menu app must be in an
allow-list (documented knobs, launch-option knobs, standard system variables); alternate-root patterns (R=, ROOT=,
PREFIX=, DESTDIR=, SYSROOT=, "$R/...") are flagged; private words (privacy.py) too. Usage: scan-testtools.py
[--work DIR] VERSION [file ...] (default: work files, plus the version's upload folder and zips when present).
Internal release tooling."""
import os, re, subprocess, sys, zipfile
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from sarm_paths import P  # noqa: E402
import privacy  # noqa: E402
if sys.argv[1:2] == ["--work"] and len(sys.argv) > 3:
    _WORK = sys.argv[2]
    del sys.argv[1:3]
else:
    _WORK = None
if len(sys.argv) < 2:
    sys.exit(__doc__)
_P = P(sys.argv.pop(1))
if _WORK:
    _P.work = _WORK
OUT = _P.upload + "/"
U = _P.releases + "/"
WORK = _P.work + "/"
RECIPE = WORK + "tools/build-driver-archive.sh"
PAT = re.compile(r"drm[-_]shim|shim|test|bench|glmark|vkmark|vktest|gltest|xmesa|sarm13|/root/|/tmp/sarm|job|TEST_ROOT|debug|\.orig\b|fixture|mock|stub", re.I)

# Documented user knobs (installer --help, menu --help, README) and per-title launch-option knobs.
DOCUMENTED = {
    "GAMEUSER", "ARMHOME_DIR", "STEAM_ARM_IGNORE_PAGESIZE", "GPU_FAMILY", "STEAM_ARM_PROVIDER_TARBALL", "STEAM_ARM_PROVIDER_SHA256",
    "STEAM_ARM_HOME", "STEAM_ARM_PHYSX_SKIP", "STEAM_ARM_VK_SPOOF_DEBUG", "STEAM_ARM_DIALOG", "STEAM_ARM_INSTALLER",
    "STEAM_ARM_OVERLAY", "STEAM_ARM_PRELOAD_KEEP", "STEAM_ARM_UI", "PROTON_DXVK_D3D8", "NO_COLOR",
    "STEAM_ARM_RENDERER_CHECK", "STEAM_ARM_MODE_RESTORE", "STEAM_ARM_AUTO_BUILD", "STEAM_ARM_X87", "STEAM_ARM_FRIENDS", "STEAM_ARM_LAB_CEF_GPU",
    "STEAM_ARM_CLIENT_TSO", "STEAM_ARM_NOTICE",
}
# Set by this project's own programs for each other (layer manifest switches, handler -> launcher), not user knobs.
INTERNAL = {"STEAM_ARM_VK_SPOOF", "STEAM_ARM_VK_SPOOF_DISABLE", "STEAM_ARM_VK_OVERLAY", "STEAM_ARM_PRELOAD_MANGOHUD",
            "STEAM_ARM_SLOW", "STEAM_ARM_PLATFORM",
            "STEAM_ARM_LAUNCHOPTS", "STEAM_ARM_D3D_DEFAULT"}
# Standard variables of the system, desktop session, sudo, Steam, FEX, Mesa, Java.
SYSTEM = {
    "HOME", "USER", "LOGNAME", "PATH", "LANG", "TERM", "TMPDIR", "SHELL", "SUDO_USER", "DISPLAY", "WAYLAND_DISPLAY",
    "XAUTHORITY", "XDG_RUNTIME_DIR", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CURRENT_DESKTOP",
    "XDG_SESSION_TYPE", "DBUS_SESSION_BUS_ADDRESS", "LD_PRELOAD", "LD_LIBRARY_PATH", "JAVA_TOOL_OPTIONS",
    "FEX_APP_CONFIG", "SteamAppId", "SteamGameId", "STEAM_COMPAT_DATA_PATH", "STEAM_COMPAT_GRAPHICS_PROVIDER",
    "STEAM_COMPAT_CLIENT_INSTALL_PATH", "STEAM_COMPAT_FEX_CONFIG", "MANGOHUD", "MESA_GL_VERSION_OVERRIDE", "MESA_GLSL_VERSION_OVERRIDE",
    "__GLX_VENDOR_LIBRARY_NAME", "DEBIAN_FRONTEND", "BASH_REMATCH", "PIPESTATUS", "UID", "EUID",
    "FEX_DISKCACHE", "STEAM_COMPAT_SHADER_PATH", "STEAM_COMPAT_INSTALL_PATH",
}
# Keys of /etc/steam-arm/steam-arm.conf, which the launcher sources as shell.
CONF = {"ARMHOME_DIR", "GAMEUSER", "COMPONENTS_ON", "COMPONENTS_OFF", "GPU_FAMILY", "GPU_FAMILY_SET", "GFX_DEFAULT",
        "VERSION", "LINGER_SET", "ACCOUNT_CREATED", "COMPONENTS_USER_SET", "COMPONENTS_FAMILY", "FSTAB_ADDED", "RFS_CREATED",
        "PROVIDER_CUSTOM_SHA256", "PROVIDER_CUSTOM_FILE", "CPU_LSE", "CPU_CORES", "PLATFORM", "MESA_HOST", "X87_CLIENT", "CLIENT_LIGHT"}
# Keys of /etc/os-release, which setup sources in a subshell.
OS_RELEASE = {"ID", "ID_LIKE", "VERSION_ID", "VERSION_CODENAME"}
ALLOW = DOCUMENTED | INTERNAL | SYSTEM | CONF | OS_RELEASE

SH_READ = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(:?[-+=?])")
PY_READ = re.compile(r"""os\.environ\.get\(\s*["']([A-Za-z_][A-Za-z0-9_]*)["']|os\.environ\[\s*["']([A-Za-z_][A-Za-z0-9_]*)["']\s*\](?!\s*=[^=])"""
                     r"""|["']([A-Za-z_][A-Za-z0-9_]*)["']\s+(?:not\s+)?in\s+os\.environ|getenv\(\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*\)""")
ALT_ROOT = re.compile(r"""(?:^|[\s;(&|])(?:local\s+)?(R|ROOT|PREFIX|DESTDIR|SYSROOT)=|"\$\{?R\}?/|\$\{R:-|\$\{ROOT|\$\{PREFIX|\$\{DESTDIR""")
HOOK_CS = re.compile(r"[A-Z0-9_]+_POLL\b")
HOOK_TEXT = re.compile(r"STEAM_ARM_[A-Z_]*TEST|TEST_ROOT|/tmp/sarm|\.claude|jobs/|xmesa|drm-shim|fixture|"
                       r"for tests|test only|testing only|SA_SYS|SA_PROC|BASH_SOURCE\[0\]\}?\"?\s*=\s*\"?\$0", re.I)


def assigned_names(text):
    """Variables the file assigns itself (not the NAME=${NAME:-...} self-default form), loop/read/local names."""
    names = set()
    for m in re.finditer(r"(?:^|[\s;(&|{])(?:local\s+|export\s+|declare\s+[-a-z]*\s*)?([A-Za-z_][A-Za-z0-9_]*)=(.?)", text, re.M):
        n, nxt = m.group(1), m.group(2)
        if nxt in ('"', "$") and re.match(r'"?\$\{%s:?[-=]' % re.escape(n), text[m.end(2) - 1:m.end(2) + len(n) + 4]):
            continue
        names.add(n)
    for m in re.finditer(r"\blocal\s+([^\n;=]*)", text):
        names.update(w for w in m.group(1).split() if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", w))
    for m in re.finditer(r"\b(?:for|read(?:\s+-[a-z]+)*)\s+([A-Za-z_][A-Za-z0-9_ ]*)", text):
        names.update(w for w in m.group(1).split() if w not in ("in", "do"))
    for m in re.finditer(r"\bmapfile\s+-t\s+([A-Za-z_][A-Za-z0-9_]*)", text):
        names.add(m.group(1))
    return names


def scan_env(path, alt=True):
    text = open(path, encoding="utf-8", errors="replace").read()
    own = assigned_names(text)
    flags = []
    for i, line in enumerate(text.splitlines(), 1):
        for m in SH_READ.finditer(line):
            n = m.group(1)
            # lower-case names are script locals by convention; env knobs are upper case
            if n in ALLOW or n != n.upper():
                continue
            if n in own and not re.search(r'(?m)^\s*(?:export\s+)?%s="?\$\{%s:?[-=]' % (n, n), text):
                continue
            flags.append((i, "env read ${%s%s" % (n, m.group(2)), line))
        for m in PY_READ.finditer(line):
            n = next(g for g in m.groups() if g)
            if n not in ALLOW:
                flags.append((i, "env read %s" % n, line))
        if alt and ALT_ROOT.search(line):
            flags.append((i, "alternate root", line))
        if HOOK_TEXT.search(line) or HOOK_CS.search(line):
            flags.append((i, "test hook text", line))
        for w, tag in privacy.hits(line, os.path.basename(path)):
            flags.append((i, "private word (%s)" % tag, line))
    return flags


def main():
    # build recipe in the repo source: a published tool, scanned for env knobs and leaked paths like the work files
    files = sys.argv[1:] or [WORK + "steam-arm-install.sh", WORK + "steam-arm-config", RECIPE]
    total = 0
    for f in files:
        # build roots and DESTDIR installs are what the recipe is for: no alternate-root rule there
        fl = scan_env(f, alt=f != RECIPE)
        total += len(fl)
        print("== env reads / alternate roots / hook text:", f, "->", len(fl), "unexpected")
        for i, why, line in fl:
            print("  %5d  %-28s %s" % (i, why, line.strip()[:110]))
    if sys.argv[1:]:
        return total
    if os.path.isdir(OUT):
        print("== upload folder files")
        for dp, dn, fn in os.walk(OUT):
            for f in fn:
                rel = os.path.relpath(os.path.join(dp, f), OUT)
                print(("  FLAG " if PAT.search(rel) else "       ") + rel)
    for zp in (_P.zip, _P.repo_zip, os.path.join(OUT, "Steam ARM %s.zip" % _P.v)):
        if os.path.isfile(zp):
            print("== zip", os.path.basename(zp))
            for n in zipfile.ZipFile(zp).namelist():
                if PAT.search(n):
                    print("  FLAG", n)
    tb = OUT + "steam-arm-fex-mesa-26.1.8-x86_64-i386.tar.zst"
    if os.path.isfile(tb):
        print("== provider tarball entries matching test patterns")
        tl = subprocess.run(["tar", "--zstd", "-tf", tb], capture_output=True, text=True).stdout.splitlines()
        print("  entries:", len(tl))
        for n in tl:
            if PAT.search(n):
                print("  FLAG", n)
    print("unexpected env reads / alternate roots / hook text in work files:", total)
    return total


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
