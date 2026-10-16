#!/bin/bash
# Steam ARM 3.0 A5: --detect line "official client: none|found (...)" from synthetic signs: arm64 package owning
# /usr/bin/steam, Steam folder with ARM64 client parts and no Steam ARM mark, running client without -deckard outside
# a Steam ARM folder. Functions from installer under test; /proc rewritten in the extract only; dpkg-query, getent,
# pgrep stubbed through PATH. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm30-oc.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -n 6; fail=$((fail + 1)); fi; }
python3 - "$INST" "$T/fn.sh" "$T" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
out = []
for n in ("sa_folder", "official_client"):
    m = re.search(r"^%s\(\)\{.*\}$" % n, s, re.M)
    if not m or m.group(0).endswith("(){"):
        m = re.search(r"^%s\(\)\{\n.*?\n\}\n" % n, s, re.S | re.M)
    assert m, n
    out.append(m.group(0).rstrip("\n") + "\n")
open(sys.argv[2], "w").write("".join(out).replace('"/proc/', '"%s/proc/' % sys.argv[3]))
EOF
grep -q '^official_client()' "$T/fn.sh" || { echo "FAIL extract"; exit 1; }
mkdir -p "$T/bin" "$T/proc" "$T/home"
# stubs read their answers from files in $T
cat > "$T/bin/dpkg-query" <<EOF
#!/bin/sh
case "\$1" in -S) [ -s $T/owner ] && { cat $T/owner; exit 0; }; exit 1;; -W) cat $T/arch 2>/dev/null; exit 0;; esac
EOF
printf '#!/bin/sh\ncat %s/passwd\n' "$T" > "$T/bin/getent"
printf '#!/bin/sh\ncat %s/pids 2>/dev/null\n' "$T" > "$T/bin/pgrep"
chmod 755 "$T"/bin/*
reset(){ : > "$T/owner"; : > "$T/arch"; : > "$T/pids"; rm -rf "$T/home" "$T/proc"; mkdir -p "$T/home/u" "$T/proc"
  printf 'root:x:0:0::%s/home/root:/bin/sh\nu:x:1000:1000::%s/home/u:/bin/sh\nsvc:x:500:500::%s/home/svc:/bin/sh\n' "$T" "$T" "$T" > "$T/passwd"; }
oc(){ OUT=$(PATH="$T/bin:/usr/bin:/bin" bash -c ". $T/fn.sh; official_client"); }
proc(){ mkdir -p "$T/proc/$1"; printf '%s\0' "${@:3}" > "$T/proc/$1/cmdline"; ln -s "$2" "$T/proc/$1/exe"; echo "$1" >> "$T/pids"; }

reset; oc
check "C1 no sign: none" "[ \"\$OUT\" = none ]"
reset; echo 'steam-launcher: /usr/bin/steam' > "$T/owner"; echo all > "$T/arch"; oc
check "C2 package for all architectures (today's x86 launcher): none" "[ \"\$OUT\" = none ]"
echo arm64 > "$T/arch"; oc
check "C3 arm64 package owns /usr/bin/steam: found" "[ \"\$OUT\" = 'found (arm64 package)' ]"
reset; echo 'steam:arm64: /usr/bin/steam' > "$T/owner"; : > "$T/arch"; oc
check "C4 multiarch name steam:arm64, no query answer: found" "[ \"\$OUT\" = 'found (arm64 package)' ]"
reset; mkdir -p "$T/home/u/.local/share/Steam/ubuntu12_32"; oc
check "C5 x86 Steam folder only: none" "[ \"\$OUT\" = none ]"
mkdir -p "$T/home/u/.local/share/Steam/linuxarm64"; oc
check "C6 Steam folder with linuxarm64, no mark: found" "[ \"\$OUT\" = 'found (Steam folder without Steam ARM mark)' ]"
touch "$T/home/u/.steam-arm-client"; oc
check "C7 same folder with Steam ARM mark (client home = account home): none" "[ \"\$OUT\" = none ]"
reset; mkdir -p "$T/home/u/.local/share/steam-arm/.local/share/Steam/linuxarm64"; touch "$T/home/u/.local/share/steam-arm/.steam-arm-client"; oc
check "C8 Steam ARM client home below account home: none" "[ \"\$OUT\" = none ]"
reset; mkdir -p "$T/home/svc/.local/share/Steam/steamrtarm64"; oc
check "C9 system account (uid 500) skipped" "[ \"\$OUT\" = none ]"
reset; S=$T/home/u/.local/share/steam-arm/.local/share/Steam; mkdir -p "$S/linuxarm64"; touch "$T/home/u/.local/share/steam-arm/.steam-arm-client"
proc 10 "$S/linuxarm64/steam" ./steam -deckard -steamos3; oc
check "C10 Steam ARM client running with -deckard: none" "[ \"\$OUT\" = none ]"
reset; mkdir -p "$S/linuxarm64"; touch "$T/home/u/.local/share/steam-arm/.steam-arm-client"
proc 11 "$S/linuxarm64/steam" ./steam -gamepadui; oc
check "C11 client without -deckard inside a Steam ARM folder: none" "[ \"\$OUT\" = none ]"
reset; mkdir -p "$T/opt/steam/linuxarm64"; proc 12 "$T/opt/steam/linuxarm64/steam" /opt/steam/linuxarm64/steam; oc
check "C12 client without -deckard elsewhere: found" "[ \"\$OUT\" = 'found (running client without -deckard)' ]"
reset; proc 13 /usr/bin/FEXInterpreter "$S/ubuntu12_32/steam"; oc
check "C13 x86 client under emulation: none" "[ \"\$OUT\" = none ]"
reset; echo 'steam-launcher: /usr/bin/steam' > "$T/owner"; echo arm64 > "$T/arch"; mkdir -p "$T/home/u/.local/share/Steam/linuxarm64"
mkdir -p "$T/opt/steam/linuxarm64"; proc 14 "$T/opt/steam/linuxarm64/steam" x; oc
check "C14 all three signs: listed together, no paths or names" \
  "[ \"\$OUT\" = 'found (arm64 package, Steam folder without Steam ARM mark, running client without -deckard)' ] && ! grep -q '/' <<<\"\$OUT\""
check "C15 --detect prints the line; no mode switch in setup" "grep -q 'echo \"official client: \$(official_client)\"' '$INST' && ! grep -qi 'helper mode' '$INST'"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
