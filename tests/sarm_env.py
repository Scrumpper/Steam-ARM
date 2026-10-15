"""Paths for Python suites, same rules as paths.sh: SARM_INST, SARM_OLD from run-all.sh or caller; suite run alone
uses source root (repo checkout) or <V>-work beside <V>-tests, and no earlier releases."""
import os

HERE = os.path.dirname(os.path.realpath(__file__))
_UP = os.path.dirname(HERE)
if os.path.isfile(os.path.join(_UP, "steam-arm-install.sh")):
    WORK = _UP
else:
    WORK = os.path.join(_UP, os.path.basename(HERE)[:-len("-tests")] + "-work")
INST = os.environ.get("SARM_INST") or os.path.join(WORK, "steam-arm-install.sh")


def old(version, name="steam-arm-install.sh"):
    """File of an earlier release from SARM_OLD, or None when not available."""
    d = os.environ.get("SARM_OLD")
    p = os.path.join(d, version, name) if d else None
    return p if p and os.path.exists(p) else None
