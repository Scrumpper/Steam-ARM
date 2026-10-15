#!/bin/bash
# 2.3.1 tray children: programs the tray starts (menu entries) leave no zombie once they end. spawn() and the tray's
# imports extracted from the installer copy (SARM_INST picks another), run with short-lived children. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-reap.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
awk '/^cat > \/usr\/local\/bin\/steam-arm-tray <<.TRAYPY.$/{f=1;next} /^TRAYPY$/{f=0} f' "$INST" > "$T/tray.py"
check "tray compiles" "python3 -m py_compile '$T/tray.py'"
cat > "$T/reap.py" <<'EOF'
import os, re, sys, time
src = open(sys.argv[1]).read()
head = "\n".join(l for l in src.split("\ntry:\n", 1)[0].splitlines() if l.startswith("import "))
m = re.search(r"\ndef spawn\(argv\):\n(?:    .*\n|\n)*?(?=\n\S)", src)
ns = {}
exec(head + "\n" + (m.group(0) if m else ""), ns)
def zombies():
    n = 0
    for p in os.listdir("/proc"):
        if p.isdigit():
            try:
                f = open("/proc/%s/stat" % p).read().rsplit(")", 1)[1].split()
            except OSError:
                continue
            if f[0] == "Z" and int(f[1]) == os.getpid():
                n += 1
    return n
ok = ns["spawn"](["sh", "-c", "exit 0"]) and ns["spawn"](["sh", "-c", "sleep 0.2"])
time.sleep(1.5)
print("started=%s zombies=%d bad=%s" % (ok, zombies(), ns["spawn"](["/nonexistent/program"])))
EOF
OUT=$(timeout 30 python3 "$T/reap.py" "$T/tray.py" 2>&1)
check "T1 two programs started from tray menu ended: no zombie left" "grep -qx 'started=True zombies=0 bad=False' <<<\"\$OUT\""
check "T2 tray imports threading at top" "grep -qx 'import threading' '$T/tray.py'"
echo "tray reap 2.3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
