#!/bin/bash
# 2.3 host library hint: launcher reads steamwebhelper.log of native client ("error while loading shared libraries")
# and warns naming library and apt package; hardware report shows those lines. Blocks extracted from the installer
# copy in ~/.cache/sarm<NN>-work (paths.sh) and settings menu; lnote, ldconfig, steam_dir stubbed.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm232-hostlibs.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
check "launcher parses (sh -n)" "sh -n $L"
B=$T/hint.sh
awk '/^# Client window process \(steamwebhelper\) missing host library/{f=1} f && /^wh_libhint$/{exit} f' "$L" > "$B"
check "hint block present: wh_libhint and wh_watch defined" "grep -q '^wh_libhint()' $B && grep -q '^wh_watch()' $B"
l_h=$(grep -n '^wh_libhint$' "$L" | cut -d: -f1); l_w=$(grep -n '^wh_watch </dev/null >/dev/null &$' "$L" | cut -d: -f1)
l_n=$(grep -n '^NVER="\$ARMHOME/.config/steam-arm/native-verify"$' "$L" | cut -d: -f1)
l_x=$(grep -n '^if \[ "\$CLIENT" = x86 \]; then cd "\$S" || exit 1; else cd "\$D" || exit 1; fi$' "$L" | cut -d: -f1)
check "hint: previous log checked, then watcher started, after x86 branch and before native first start" "[ -n \"$l_h\" ] && [ ${l_x:-0} -lt ${l_h:-0} ] && [ $((l_h + 1)) = ${l_w:-0} ] && [ ${l_w:-0} -lt ${l_n:-0} ]"
mkdir -p "$T/bin" "$T/S/logs"
# ldconfig stub: libraries listed in $T/have count as installed
printf '#!/bin/sh\n[ "$1" = -p ] || exit 0\nwhile read -r l; do printf "\\t%%s (libc6,AArch64) => /usr/lib/%%s\\n" "$l" "$l"; done < "%s/have"\n' "$T" > "$T/bin/ldconfig"
chmod 755 "$T/bin/ldconfig"
hint(){ : > "$T/have"; [ -n "${2:-}" ] && echo "$2" > "$T/have"; printf '%s\n' "$1" > "$T/S/logs/steamwebhelper.log"
  OUT=$(PATH="$T/bin:/usr/bin:/bin" sh -c "lnote(){ echo \"NOTE[\$2] \$1\"; }; S=$T/S; . $B; wh_libhint" 2>&1); }
hint "./steamwebhelper: error while loading shared libraries: libibus-1.0.so.5: cannot open shared object file: No such file or directory"
check "libibus missing: warning names library and apt package libibus-1.0-5" "[ \"\$OUT\" = 'NOTE[Steam ARM: library missing] Steam window stays empty: steamwebhelper cannot load libibus-1.0.so.5. Fix: sudo apt install libibus-1.0-5, then start Steam ARM again.' ]"
hint "/x/steamwebhelper: error while loading shared libraries: libfoo.so.3: cannot open shared object file: No such file or directory"
check "unknown library: warning names it, generic package text" "grep -q 'cannot load libfoo.so.3. Install distribution package that provides libfoo.so.3' <<<\"\$OUT\""
hint "./steamwebhelper: error while loading shared libraries: libnm.so.0: cannot open shared object file"
check "libnm.so.0 -> libnm0" "grep -q 'sudo apt install libnm0,' <<<\"\$OUT\""
hint "./steamwebhelper: error while loading shared libraries: libibus-1.0.so.5: cannot open shared object file" "libibus-1.0.so.5"
check "library installed since (old log): no warning" "[ -z \"\$OUT\" ]"
hint "[0101/000000.1:ERROR:ffmpeg_common.cc(959)] Unsupported pixel format: -1"
check "log without loader error: no warning" "[ -z \"\$OUT\" ]"
rm -f "$T/S/logs/steamwebhelper.log"; hint ""; rm -f "$T/S/logs/steamwebhelper.log"
OUT=$(PATH="$T/bin:/usr/bin:/bin" sh -c "lnote(){ echo NOTE; }; S=$T/S; . $B; wh_libhint" 2>&1)
check "no log: no warning, no error" "[ -z \"\$OUT\" ]"
check "watcher: bounded (90 s), only log written after this start" "grep -q 'while \[ \"\$n\" -lt 90 \]' $B && grep -q 'stat -c %Y \"\$WHLOG\"' $B && grep -q -- '-ge \"\$t0\"' $B"

# hardware report: native client shows loader error lines of steamwebhelper.log
R=$T/rep.sh
{ echo 'report_client(){'; awk '/^  echo "== Client"$/{f=1} f && /^  echo "== Notes"; info_notes$/{exit} f' "$CFG"; echo '}'; } > "$R"
check "report: client section extracted" "bash -n $R && grep -q 'steamwebhelper.log' $R"
printf 'a\n./steamwebhelper: error while loading shared libraries: libibus-1.0.so.5: cannot open shared object file\n' > "$T/S/logs/steamwebhelper.log"
OUT=$(bash -c "conf_get(){ :; }; client_type(){ echo arm64; }; steam_dir(){ echo $T/S; }; . $R; report_client" 2>&1)
check "report: native client lists steamwebhelper loader error" "grep -q '^steamwebhelper.log:\$' <<<\"\$OUT\" && grep -q 'libibus-1.0.so.5' <<<\"\$OUT\""
printf 'ok\n' > "$T/S/logs/steamwebhelper.log"
OUT=$(bash -c "conf_get(){ :; }; client_type(){ echo arm64; }; steam_dir(){ echo $T/S; }; . $R; report_client" 2>&1)
check "report: no loader error: no steamwebhelper.log section" "! grep -q steamwebhelper <<<\"\$OUT\""

echo "test_hostlibs_23: $pass passed, $fail failed"
[ "$fail" = 0 ]
