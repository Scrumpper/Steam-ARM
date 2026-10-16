#!/bin/bash
# 2.3.1 removal leftovers: summary names no file of a RootFS deleted in same run; empty ~/.fex-emu and runtime files of
# tray and launcher (/run/user/<uid>) go. Blocks of remove_all extracted from the installer copy (SARM_INST picks
# another) and run on a fake home and runtime folder; as_user and id stubbed. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-rm.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }
has(){ grep -qF -- "$1" <<<"$OUT"; }
RA=$T/ra.sh; fn remove_all "$INST" > "$RA"
check "remove_all extracted" "grep -q '^remove_all()' $RA"
# ---------- Kept lines ----------
awk '/^  for p in \$kept; do/{f=1} f{print} f && /^  done$/{exit} f && /done$/ && !/^  for/{exit}' "$RA" > "$T/kept.sh"
kept(){ OUT=$(RFS=/opt/fex-rootfs/Ubuntu_24_04 gone_rfs=$1 kept=" /opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json /home/u/.fex-emu/Config.json" bash "$T/kept.sh" 2>&1); }
kept 1
check "K1 RootFS deleted in same run: no Kept line for its graphics_provider.json, other kept file still named" "! has graphics_provider.json && has 'Kept:      /home/u/.fex-emu/Config.json'"
kept 0
check "K2 RootFS stays: graphics_provider.json still named as kept" "has 'Kept:      /opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json (changed since setup'"
# ---------- ~/.fex-emu ----------
awk '/^    if \[ "\$fc_rm" = 1 \]; then/{f=1} f{print} f && /^    elif /{exit}' "$RA" > "$T/fex.sh"
check "fex block extracted, parses" "grep -q rmdir '$T/fex.sh' && bash -n '$T/fex.sh'"
fexrun(){ OUT=$(as_user(){ "$@"; }; uh=$T/h fc_rm=$1 kept=; . "$T/fex.sh"; echo "kept=[$kept]"; ls -A "$T/h" 2>&1); }
mkdir -p "$T/h/.fex-emu"; echo '{}' > "$T/h/.fex-emu/Config.json"; fexrun 1
check "F1 setup's Config.json removed: empty ~/.fex-emu removed too" "[ ! -e '$T/h/.fex-emu' ]"
mkdir -p "$T/h/.fex-emu/RootFS"; echo '{}' > "$T/h/.fex-emu/Config.json"; fexrun 1
check "F2 other files in ~/.fex-emu: folder and its files stay" "[ -d '$T/h/.fex-emu/RootFS' ] && [ ! -e '$T/h/.fex-emu/Config.json' ]"
rm -rf "$T/h/.fex-emu"; mkdir -p "$T/h/.fex-emu"; echo '{"x":1}' > "$T/h/.fex-emu/Config.json"; fexrun 0
check "F3 Config.json changed since setup: kept and named, folder stays" "has 'kept=[ $T/h/.fex-emu/Config.json]' && [ -f '$T/h/.fex-emu/Config.json' ]"
# ---------- runtime files ----------
awk '/# runtime files of tray and launcher/{f=1; next} f{print} f && !/\\$/ && !/^    d=/{exit}' "$RA" | sed "s#/run/user/#$T/run/user/#" > "$T/run.sh"
U=$T/run/user/4321; mkdir -p "$U/steam-arm-tray" "$U/other"
touch "$U/steam-arm-tray/steam_tray_hc.png" "$U/steam-arm-tray.lock" "$U/steam-arm-start.lock" "$U/steam-arm-warned" \
  "$U/steam-arm-display-mode" "$U/steam-arm-icon-wait-4321.lock" "$U/bus" "$U/steam-arm-fexserver.sock"
OUT=$(as_user(){ "$@"; }; id(){ echo 4321; }; GAMEUSER=u; . "$T/run.sh"; ls -A "$U" 2>&1)
check "R1 tray folder, tray and start locks, warned flag, display mode, icon lock removed" "[ \"\$(printf '%s ' \$OUT)\" = 'bus other steam-arm-fexserver.sock ' ]"
OUT=$(as_user(){ echo "CALLED $*"; }; id(){ echo 9999; }; GAMEUSER=u; . "$T/run.sh" 2>&1)
check "R2 no runtime folder (no session): nothing done, no message" "[ -z \"\$OUT\" ]"
l_t=$(grep -n 'pkill -TERM -f /usr/local/bin/steam-arm-tray' "$RA" | head -1 | cut -d: -f1); l_r=$(grep -n '# runtime files of tray and launcher' "$RA" | cut -d: -f1)
check "R3 runtime files go after tray is stopped" "[ -n '$l_t' ] && [ -n '$l_r' ] && [ $l_t -lt $l_r ]"
echo "remove 2.3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
