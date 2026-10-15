#!/bin/bash
# 2.3.1 platform gate: setup stops before any change on systems without apt tools or with another dpkg architecture.
# Installer copy (SARM_INST picks another) run with a PATH that hides or stubs apt-get, apt-cache and dpkg; with
# Debian rootfs SARM_ROOTFS (fetch-debian.sh) also a whole run in a rootless amd64 Debian chroot copy
# (no network) with tree compared before and after. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-plat.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
has(){ grep -qF -- "$1" <<<"$OUT"; }

check "installer parses (bash -n)" "bash -n '$INST'"
# host tools without apt-get, apt-cache, dpkg; stubs per case in $T/stub
mkdir -p "$T/sys" "$T/stub"
for f in /usr/bin/* /bin/*; do
  n=${f##*/}; case $n in apt-get|apt-cache|dpkg) continue;; esac
  [ -e "$T/sys/$n" ] || ln -s "$f" "$T/sys/$n" 2>/dev/null
done
stub(){ rm -f "$T/stub/"*; [ "$1" = none ] && return
  printf '#!/bin/sh\nexit 100\n' > "$T/stub/apt-get"; printf '#!/bin/sh\nexit 100\n' > "$T/stub/apt-cache"
  printf '#!/bin/sh\n[ "$1" = --print-architecture ] && { echo %s; exit 0; }\nexit 1\n' "$1" > "$T/stub/dpkg"
  chmod 755 "$T/stub/"*; }
# copy that ends right after the gate
python3 - "$INST" "$T/gate.sh" <<'EOF'
import sys
s = open(sys.argv[1]).read()
k = 'No change made."\nfi\n'
open(sys.argv[2], "w").write(s.replace(k, k + "echo PAST-GATE; exit 0\n", 1) if s.count(k) == 1 else s)
EOF
run(){ OUT=$(cd "$T" && env -i HOME="$T" PATH="$T/stub:$T/sys" GAMEUSER=nobody bash "$T/gate.sh" "$@" </dev/null 2>&1); RC=$?; }

stub none; run --defaults
check "G1 no apt tools: stop, names apt-get, no change made, status 1" "[ $RC = 1 ] && has 'needs a Debian or Ubuntu family distribution on 64-bit ARM' && has 'no apt-get. No change made.' && ! has PAST-GATE"
stub amd64; run --defaults
check "G2 apt tools, dpkg architecture amd64: stop names architecture" "[ $RC = 1 ] && has 'package architecture amd64. No change made.' && has \"\$(uname -m)\""
stub armhf; run --keep
check "G3 32-bit ARM userland (armhf): stop" "[ $RC = 1 ] && has 'package architecture armhf'"
stub arm64; run --defaults
check "G4 apt tools and arm64: passes gate" "has PAST-GATE && ! has 'No change made'"
stub none
for a in --remove --keep --select=tray --skip=tray --client-check "--remove --purge"; do
  run $a; check "G5 no apt tools, $a: stops at gate" "[ $RC = 1 ] && has 'No change made.' && ! has PAST-GATE"
done
OUT=$(cd "$T" && env -i HOME="$T" PATH="$T/stub:$T/sys" bash "$INST" --help </dev/null 2>&1); RC=$?
check "G6 --help runs anywhere" "[ $RC = 0 ] && has 'steam-arm-install.sh' && ! has 'No change made'"
OUT=$(cd "$T" && env -i HOME="$T" PATH="$T/stub:$T/sys" bash "$INST" --detect </dev/null 2>&1); RC=$?
check "G7 --detect runs anywhere (read-only report)" "! has 'No change made' && has 'page size:'"
OUT=$(cd "$T" && env -i HOME="$T" PATH="$T/stub:$T/sys" bash "$INST" --list </dev/null 2>&1); RC=$?
check "G8 --list runs anywhere" "[ $RC = 0 ] && has 'gpu-in-emulation'"
ln_of(){ grep -n -m1 -F -- "$1" "$INST" | cut -d: -f1; }
LG=$(ln_of 'PGAP=$(platform_gap)'); LM=$(ln_of 'STEAM_ARM_INSTALLER=$SELF bash "$MENU"'); LL=$(ln_of 'exec 8>/run/steam-arm-setup.lock')
LP=$(ln_of '[ "$MODE" = remove ] || gpu_pick'); LS=$(ln_of 'IFS= read -r GAMEPASS')
check "G9 gate before settings menu hand-off, GPU pick, setup lock and password read" "[ -n \"$LG\" ] && [ $LG -lt ${LM:-0} ] && [ $LG -lt ${LP:-0} ] && [ $LG -lt ${LL:-0} ] && [ $LG -lt ${LS:-0} ]"

# ---------- amd64 Debian (apt system, other architecture): whole run, tree unchanged ----------
R0=$SARM_ROOTFS
if [ ! -x "$R0/usr/bin/apt-get" ]; then
  echo "SKIP chroot case not run: no Debian rootfs (tools/fetch-debian.sh fetches it)"
else
  R=$T/root; cp -a "$R0" "$R"; mkdir -p "$R/proc" "$R/dev" "$R/tmp/x"; cp "$INST" "$R/tmp/x/install.sh"
  snap(){ (cd "$R" && find . -xdev \( -path ./proc -o -path ./dev -o -path ./tmp/x \) -prune -o -printf '%p %m %U %G %s %T@\n' | grep -v '^\./tmp ' | sort); }
  # /tmp itself left out: run's private temp folder is made there and removed at exit
  snap > "$T/before"
  OUT=$(unshare -r -n -m chroot "$R" /bin/bash -c 'cd /tmp/x; GAMEUSER=spike timeout 120 bash /tmp/x/install.sh --defaults </dev/null; echo "rc=$?"' 2>&1)
  snap > "$T/after"
  D=$(diff "$T/before" "$T/after" | head -5)
  check "G10 amd64 Debian chroot (root, no network): stop at gate, rc 1" "has 'package architecture amd64. No change made.' && has rc=1"
  OUT=$D; check "G11 amd64 Debian chroot: file tree unchanged (every file and folder; /tmp contents too)" "[ -z \"\$D\" ]"
fi
echo "platform 2.3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
