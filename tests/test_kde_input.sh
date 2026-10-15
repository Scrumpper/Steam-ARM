#!/bin/bash
# steam-arm-kde-input against a stand-in busctl (permission store state in a file). Internal; not for release zips.
. "$(dirname "$0")/paths.sh"
W=$(mktemp -d); export HOME=$W/home STATE=$W/state; mkdir -p "$HOME" "$W/bin"
python3 - "$W/kdein.sh" "$SARM_INST" <<'PY' || { echo "extract failed"; exit 1; }
import sys
s = open(sys.argv[2]).read()
st = "cat > /usr/local/lib/steam-arm-kde-input <<'KDEIN'\n"
i = s.index(st) + len(st)
open(sys.argv[1], "w").write(s[i:s.index("\nKDEIN\n", i) + 1])
PY
cat > "$W/bin/busctl" <<'EOF'
#!/bin/sh
# stand-in: introspect ok unless DOWN; Lookup/SetPermission/DeletePermission on app "" of kde-authorized/remote-desktop
[ -n "$DOWN" ] && exit 1
for a in "$@"; do last=$a; done
case " $* " in
  *" introspect "*) exit 0;;
  *" Lookup "*) [ -f "$STATE" ] || { echo "Call failed: No entry for remote-desktop" >&2; exit 1; }
     printf '{"type":"a{sas}v","data":[{"":["%s"],"org.other.App":["no"]},{"type":"s","data":""}]}\n' "$(cat "$STATE")";;
  *" SetPermission "*) echo "$last" > "$STATE";;
  *" DeletePermission "*) rm -f "$STATE";;
  *) exit 1;;
esac
EOF
chmod 755 "$W/bin/busctl"; export PATH="$W/bin:$PATH"
K=$W/kdein.sh; M=$HOME/.config/steam-arm/kde-input-prompt
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }

sh $K on >/dev/null
check "on, no prior entry: permission yes, prior 'none' saved" "[ \"\$(cat $STATE)\" = yes ] && [ \"\$(cat $M)\" = none ]"
sh $K on >/dev/null
check "on again: no change" "[ \"\$(cat $M)\" = none ]"
check "status names value" "sh $K status | grep -q 'permission for X11 programs: yes'"
sh $K off >/dev/null
check "off: entry removed again, marker gone" "[ ! -f $STATE ] && [ ! -f $M ]"
echo no > "$STATE"; sh $K on >/dev/null
check "on over user's 'no': yes, prior 'no' saved" "[ \"\$(cat $STATE)\" = yes ] && [ \"\$(cat $M)\" = no ]"
sh $K off >/dev/null
check "off: user's 'no' back" "[ \"\$(cat $STATE)\" = no ] && [ ! -f $M ]"
echo yes > "$STATE"; sh $K on >/dev/null; sh $K off >/dev/null
check "user's own 'yes' stays after off" "[ \"\$(cat $STATE)\" = yes ] && [ ! -f $M ]"
rm -f "$STATE"; sh $K off >/dev/null
check "off without marker: nothing touched" "[ ! -f $STATE ]"
echo no > "$STATE"; sh $K off >/dev/null
check "off without marker leaves user's value" "[ \"\$(cat $STATE)\" = no ]"
rm -f "$STATE"
DOWN=1 sh $K on 2>/dev/null; rc=$?
check "no session bus: exit 75, no marker" "[ $rc = 75 ] && [ ! -f $M ]"
sh $K on >/dev/null; DOWN=1 sh $K off 2>/dev/null; rc=$?
check "off without bus: exit 75, marker kept for next try" "[ $rc = 75 ] && [ -f $M ]"
sh $K off >/dev/null
check "next off with bus: restored" "[ ! -f $STATE ] && [ ! -f $M ]"
sh $K bogus 2>/dev/null; rc=$?
check "bad argument: exit 2" "[ $rc = 2 ]"
rm -rf "$W"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
