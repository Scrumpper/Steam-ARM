#!/bin/bash
# Steam ARM 3.0 automatic tuning in the settings menu app (C1): tune CLI, autotune profile key, tuned.conf layer in the
# effective profile, backup part personal-tuning (manifest keys), restore by 3.0 (merge) and by 2.3.2 (other parts
# restore, tuning part skipped), 2.2 archive into 3.0 unchanged. Menu apps sourced as test_backup_22.sh does. Internal.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$(dirname "$0")/paths.sh"
CFG=$SARM_CFG
INST=$SARM_INST
APP232=$(sarm_old 2.3.2 steam-arm-config); APP22=$(sarm_old 2.2 steam-arm-config)
[ -n "$APP232" ] && [ -n "$APP22" ] || { echo "SKIP tuning config suite: 2.2, 2.3.2 releases not available (run through run-all.sh)"; exit 0; }
T=$(mktemp -d /tmp/sarm30-tunecfg.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -n 8; fail=$((fail + 1)); fi; }

R=$T/fake
sed "s#^R=.*#R=$R#" "$HERE/config-ui/mkfake.sh" > "$T/mkfake.sh"; bash "$T/mkfake.sh" >/dev/null
A=$R/home/tester/.local/share/steam-arm
awk "/^cat > \/usr\/local\/lib\/steam-arm-autotune.py <<'AUTOTUNEPY'\$/{f=1;next} /^AUTOTUNEPY\$/{f=0} f" "$INST" > "$T/autotune.py"
awk "/^cat > \/usr\/local\/lib\/steam-arm-compatmap.py <<'PYEOF'\$/{f=1;next} /^PYEOF\$/{f=0} f" "$INST" > "$T/compatmap.py"
mkh(){
  sed -e "s#\"/proc/#\"$R/proc/#g" -e "s#/sys/class#$R/sys/class#g" -e '$d' "$1" > "$T/app-$2.sh"
  cat > "$T/h-$2.sh" <<EOF
. "$T/app-$2.sh"
R=$R
SA_CONF=\$R/etc/steam-arm/steam-arm.conf; SA_TITLES_SHARE=\$R/share/titles.conf; SA_TITLES_ETC=\$R/etc/steam-arm/titles.conf
SA_LAUNCHER=\$R/bin/steam-arm; SA_COMPATMAP=\$R/bin/steam-arm-compatmap; SA_COMPATMAP_PY=$T/compatmap.py; SA_TMP=$T/tmp
SA_AUTOTUNE_PY=$T/autotune.py
game_home(){ echo \$R/home/tester; }; game_user(){ echo tester; }
acct_home(){ echo \$R/home/\$1; }; acct_run(){ shift; "\$@"; }; owner_user(){ echo tester; }; owner_home(){ echo \$R/home/tester; }
as_owner(){ "\$@"; }; as_root(){ "\$@"; }; need_root(){ return 0; }; steam_running(){ return 1; }
EOF
}
mkdir -p "$T/tmp"; mkh "$CFG" 30; mkh "$APP232" 232; mkh "$APP22" 22
run(){ bash -c ". $T/h-$1.sh; $2" 2>&1; }

# ---------------- tune CLI and profile key ----------------
OUT=$(run 30 "cli_tune 100 on; tc_get 100 autotune")
check "U1 tune on: autotune=fix in /etc titles.conf" "grep -qx 'fix' <<<\"\$OUT\" && grep -q '^100 .*autotune=fix' $R/etc/steam-arm/titles.conf"
OUT=$(run 30 "cli_tune 100 show")
check "U2 tune show: mode and no record yet" "grep -q 'automatic tuning on (fix problems)' <<<\"\$OUT\" && grep -q 'no tuning record' <<<\"\$OUT\""
mkdir -p "$A/.config/steam-arm/autotune"
printf '# x\n100 gfx=b   # autotune test\n' > "$A/.config/steam-arm/tuned.conf"
printf '{"version": 1, "titles": {"100": {"best": {}, "trial": {"gfx": "b"}, "applied": {"gfx": "b"}, "status": "trying", "trials": 1}}}\n' \
  > "$A/.config/steam-arm/autotune/state.json"
OUT=$(run 30 "tc_effective 100; echo src=\$(tc_source 100 gfx)")
check "U3 effective profile includes tuned.conf layer (below /etc and personal)" \
  "grep -qx 'gfx=b' <<<\"\$OUT\" && grep -q 'src=.*tuned.conf' <<<\"\$OUT\""
printf '100 gfx=a\n' >> "$R/etc/steam-arm/titles.conf"
OUT=$(run 30 "tc_get 100 gfx")
check "U4 /etc key wins over tuned.conf" "[ \"\$OUT\" = a ]"
sed -i 's/^100 gfx=a$//' "$R/etc/steam-arm/titles.conf"
OUT=$(run 30 "cli_tune 100 off; tc_get 100 autotune; cat $A/.config/steam-arm/tuned.conf")
check "U5 tune off: key removed, pending trial dropped from tuned.conf" \
  "grep -q 'automatic tuning off' <<<\"\$OUT\" && ! grep -q '^100 gfx=b' $A/.config/steam-arm/tuned.conf 2>/dev/null"
OUT=$(run 30 "cli_tune 100 bogus"; echo "rc=$?")
check "U6 tune: bad value refused" "grep -q usage <<<\"\$OUT\""
OUT=$(run 30 "profile_ok autotune fix && profile_ok autotune off && ! profile_ok autotune yes && echo ok")
check "U7 profile key autotune=fix|off accepted, others refused" "grep -qx ok <<<\"\$OUT\""
check "U8 menu: Games > title item and screen, CLI in help and dispatch" \
  "grep -q 'autotune \"Automatic tuning     \[' '$CFG' && grep -q '^game_autotune(){' '$CFG' && grep -q '  tune <appid> \[on|fix|off|reset|show\]' '$CFG' && grep -q '    tune)        case' '$CFG'"

# ---------------- backup part ----------------
run 30 "cli_tune 100 on" >/dev/null
printf '100 gfx=b   # autotune kept gfx=b\n' > "$A/.config/steam-arm/tuned.conf"
printf '{"version": 1, "titles": {"100": {"best": {"gfx": "b"}, "status": "kept"}}}\n' > "$A/.config/steam-arm/autotune/state.json"
printf '200 overlay=off\n' > "$A/.config/steam-arm/titles.conf"
mkdir -p "$T/out"
ALL=setup,system-profiles,personal-profiles,compat-tools,fex,mangohud,personal-tuning
OUT=$(run 30 "bk_make $T/out $ALL tester; echo rc=\$? err=\$BK_ERR")
B=$(ls "$T"/out/*.tar.gz 2>/dev/null | head -1)
check "K1 3.0 backup with personal-tuning written" "grep -q rc=0 <<<\"\$OUT\" && [ -f \"\$B\" ]"
OUT=$(tar -tzf "$B" | sort | paste -sd' ')
check "K2 no new member names (2.3.2 refuses unknown members): tuning rides in the manifest" \
  "! grep -q tun <<<\"\$OUT\""
OUT=$(tar -xOzf "$B" steam-arm-settings/manifest)
check "K3 manifest: PARTS lists personal-tuning, TUNED_CONF and TUNED_STATE base64" \
  "grep -q '^PARTS=.*personal-tuning' <<<\"\$OUT\" && [ \"\$(sed -n 's/^TUNED_CONF=//p' <<<\"\$OUT\" | base64 -d)\" = \"\$(cat $A/.config/steam-arm/tuned.conf)\" ] && grep -q '^TUNED_STATE=' <<<\"\$OUT\""
mkdir -p "$T/only"
OUT=$(run 30 "bk_make $T/only personal-tuning tester; echo rc=\$?")
BO=$(ls "$T"/only/*.tar.gz 2>/dev/null | head -1)
check "K4 backup of only personal-tuning (manifest only) written" "grep -q rc=0 <<<\"\$OUT\" && [ -f \"\$BO\" ]"

# restore by 3.0: this machine has its own result for 100; backup brings 100 (kept here) and 300 (added)
printf '100 multiblock=off   # here\n' > "$A/.config/steam-arm/tuned.conf"
printf '{"version": 1, "titles": {"100": {"best": {"multiblock": "off"}}}}\n' > "$A/.config/steam-arm/autotune/state.json"
mkdir -p "$T/x"; tar -xzf "$B" -C "$T/x"
printf '100 gfx=b   # backup\n300 gfx=b   # backup\n' > "$T/x/t.conf"
sed -i "s/^TUNED_CONF=.*/TUNED_CONF=$(base64 -w0 < "$T/x/t.conf")/" "$T/x/steam-arm-settings/manifest"
(cd "$T/x" && tar --owner=0 --group=0 --numeric-owner -czf "$T/b2.tar.gz" steam-arm-settings)
OUT=$(run 30 "rs_open $T/b2.tar.gz || echo ERR \$RS_ERR; echo PARTS=\$RS_PARTS; rs_plan \"\$RS_PARTS\" tester merge merge '' ''; echo \"\$RS_SUM\"; rs_apply; echo apply=\$?")
check "R1 3.0 restore: part listed, plan names it, merge adds 300 and keeps 100 here" \
  "grep -q 'PARTS=.*personal-tuning' <<<\"\$OUT\" && grep -q 'added 1, kept 1' <<<\"\$OUT\" && grep -q 'apply=0' <<<\"\$OUT\" && grep -q '^300 gfx=b' $A/.config/steam-arm/tuned.conf && grep -q '^100 multiblock=off' $A/.config/steam-arm/tuned.conf && ! grep -q '^100 gfx=b' $A/.config/steam-arm/tuned.conf"
check "R2 restored state.json owner only" "[ \"\$(stat -c %a $A/.config/steam-arm/autotune/state.json)\" = 600 ]"
sed -i "s/^TUNED_CONF=.*/TUNED_CONF=$(printf '100 TSOEnabled=0\n' | base64 -w0)/" "$T/x/steam-arm-settings/manifest"
(cd "$T/x" && tar --owner=0 --group=0 --numeric-owner -czf "$T/b3.tar.gz" steam-arm-settings)
OUT=$(run 30 "rs_open $T/b3.tar.gz; echo PARTS=\$RS_PARTS NOTE=\$RS_NOTE")
check "R3 tuned.conf with other keys left out (never TSO from a backup)" "grep -q 'NOTE=.*tuned.conf' <<<\"\$OUT\""

# restore of the 3.0 archive by 2.3.2: every other part restores, tuning part skipped
printf '999 overlay=off\n' > "$R/etc/steam-arm/titles.conf"; rm -f "$A/.config/steam-arm/titles.conf"
OUT=$(run 232 "rs_open $B || echo ERR \$RS_ERR; echo PARTS=\$RS_PARTS; rs_plan \"\$RS_PARTS\" tester replace replace all all; rs_apply; echo apply=\$?")
check "O1 2.3.2 opens the 3.0 archive, restores other parts, skips personal-tuning" \
  "! grep -q '^ERR' <<<\"\$OUT\" && grep -q 'PARTS=setup,system-profiles,personal-profiles' <<<\"\$OUT\" && ! grep -q 'PARTS=.*tuning' <<<\"\$OUT\" && grep -q 'apply=0' <<<\"\$OUT\" && grep -q '^200 overlay=off' $A/.config/steam-arm/titles.conf"
OUT=$(run 232 "rs_open $BO; echo rc=\$? ERR=\$RS_ERR")
check "O2 2.3.2 and a tuning-only archive: refused as holding no usable part (nothing else to restore)" \
  "grep -q 'no usable part' <<<\"\$OUT\""

# 2.2 archive into 3.0: unchanged behaviour, no tuning part
mkdir -p "$T/o22"
OUT=$(run 22 "bk_make $T/o22 setup,system-profiles,personal-profiles tester; echo rc=\$?")
B22=$(ls "$T"/o22/*.tar.gz 2>/dev/null | head -1)
OUT=$(run 30 "rs_open $B22 || echo ERR \$RS_ERR; echo PARTS=\$RS_PARTS; rs_plan \"\$RS_PARTS\" tester merge merge '' ''; rs_apply; echo apply=\$?")
check "O3 2.2 archive restores in 3.0 with its own parts only" \
  "grep -q 'PARTS=setup,system-profiles,personal-profiles$' <<<\"\$OUT\" && grep -q 'apply=0' <<<\"\$OUT\""

echo "$pass PASS, $fail FAIL"
[ "$fail" = 0 ]
