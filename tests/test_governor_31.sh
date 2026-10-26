#!/bin/bash
# 3.1 pi-governor component (off by default): root helper steam-arm-governor (performance saves and sets every policy,
# restore puts the saved governors back) on a fake cpufreq tree; setup writes helper and sudo rule only with the part,
# removes both without it; component lists, relevance and removal list; launcher sets and restores through sudo
# (stand-in records calls); settings menu Maintenance row on a Raspberry Pi model. Blocks extracted from the installer
# under test (SARM_INST picks another). Internal; not for release zips.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm31-gov.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }

# helper script on a fake cpufreq tree (paths rewritten in the copy only)
H=$T/gov.sh
awk '/^cat > "\$GOV_HELPER" <<.GOVSH.$/{f=1;next} /^GOVSH$/{f=0} f' "$INST" | sed -e "s#^P=/sys/devices/system/cpu/cpufreq#P=$T/cpufreq#" -e "s#^S=/run/steam-arm-governor.prev#S=$T/prev#" > "$H"
check "G1 helper extracted (sh, parses), usage on other words" "[ -s $H ] && head -1 $H | grep -q '^#!/bin/sh' && sh -n $H && ! sh $H bogus 2>/dev/null && [ \$(sh $H bogus 2>&1 | grep -c usage) = 1 ]"
mkdir -p "$T/cpufreq/policy0" "$T/cpufreq/policy4"; echo ondemand > "$T/cpufreq/policy0/scaling_governor"; echo schedutil > "$T/cpufreq/policy4/scaling_governor"
sh "$H" performance; OUT=$(cat "$T/prev"; cat "$T/cpufreq/policy0/scaling_governor" "$T/cpufreq/policy4/scaling_governor")
check "G2 performance: saved governors per policy, both set to performance" "[ \"\$OUT\" = \$'policy0 ondemand\npolicy4 schedutil\nperformance\nperformance' ]"
sh "$H" performance; OUT=$(cat "$T/prev")
check "G3 performance twice: first saved state kept (no performance saved as previous)" "[ \"\$OUT\" = \$'policy0 ondemand\npolicy4 schedutil' ]"
sh "$H" restore; OUT=$(cat "$T/cpufreq/policy0/scaling_governor" "$T/cpufreq/policy4/scaling_governor"; [ -e "$T/prev" ] && echo prev-kept || echo prev-gone)
check "G4 restore: governors back, saved state removed" "[ \"\$OUT\" = \$'ondemand\nschedutil\nprev-gone' ]"
sh "$H" restore; check "G4b restore without saved state: nothing, status 0" "[ \$(sh $H restore; echo \$?) = 0 ]"

# component lists, default off, relevance, description, removal list
check "G5 pi-governor in COMPONENTS_ALL and DEFAULT_OFF (installer) and SA_COMPONENTS, SA_DEFAULT_OFF (menu)" \
  "grep -q '^COMPONENTS_ALL=\".* page-size pi-governor lepton\"' '$INST' && grep -q '^DEFAULT_OFF=\"pad-xbox shader-cache kde-input-prompt pi-governor lepton\"' '$INST' && grep -q '^SA_COMPONENTS=\".* page-size pi-governor lepton\"' '$CFG' && grep -q '^SA_DEFAULT_OFF=\"pad-xbox shader-cache kde-input-prompt pi-governor lepton\"' '$CFG'"
check "G6 relevance: Raspberry Pi model or sudo rule present (installer gov_relevant, menu gov_applies); listed only there" \
  "grep -qF 'gov_relevant(){ case' '$INST' && grep -qF 'in \"Raspberry Pi\"*) return 0;; esac; [ -e \"\$GOV_SUDO\" ]; }' '$INST' && grep -qF 'gov_relevant || COMPONENTS=\${COMPONENTS/ pi-governor/}' '$INST' && grep -qF 'gov_applies(){ case \"\$(hw_model)\" in \"Raspberry Pi\"*) return 0;; esac; [ -e /etc/sudoers.d/steam-arm-governor ]; }' '$CFG' && grep -qF 'gov_applies || l=' '$CFG' && grep -qF \"sed 's/ pi-governor / /'\" '$CFG'"
OUT=$(bash -c "cd '$T' && env -i HOME='$T' PATH=/usr/bin:/bin bash '$INST' --list" 2>&1)
if [ -r /proc/device-tree/model ] && grep -q "^Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
  check "G7 --list on a Raspberry Pi names pi-governor with heat note" "grep -q '^  pi-governor *Raspberry Pi: CPU governor performance while Steam runs (more heat and power); off by default' <<<\"\$OUT\""
else
  check "G7 --list on this host (no Raspberry Pi): pi-governor not listed" "! grep -q 'pi-governor' <<<\"\$OUT\" && grep -q 'glx-lax' <<<\"\$OUT\""
fi
check "G8 setup: helper and sudo rule only with the part (visudo checked), both removed without it; removal list and owned paths name them" \
  "grep -qF 'if opt pi-governor; then' '$INST' && grep -qF 'ALL=(root) NOPASSWD: %s performance, %s restore' '$INST' && grep -qF 'visudo -cqf \"\$T\" >/dev/null 2>&1 && chmod 440 \"\$T\" && mv -f \"\$T\" \"\$GOV_SUDO\"' '$INST' && grep -qF 'rm -f \"\$GOV_HELPER\" \"\$GOV_SUDO\"' '$INST' && grep -qF '        /usr/local/sbin/steam-arm-governor /etc/sudoers.d/steam-arm-governor' '$INST' && grep -qF '    /usr/local/sbin/steam-arm-governor /etc/sudoers.d/steam-arm-governor' '$CFG'"
check "G8b installed(): part counts as installed by its sudo rule" "grep -q '^  pi-governor) \\[ -e \"\$GOV_SUDO\" \\];;' '$INST'"

# launcher: performance at start, restore at exit, only with the part and the helper
L=$T/launcher.sh
awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
GB=$T/gb.sh; awk '/^# pi-governor \(component, off by default\): CPU governor performance while this client runs/{f=1} f{print} f && /^restore_gov\(\)/{exit}' "$L" > "$GB"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "sudo $*" >> "$T/sudo.log"\n[ "$3" = performance ] && [ -f "$T/sudo.fail" ] && exit 1\nexit 0\n' > "$T/bin/sudo"; chmod 755 "$T/bin/sudo"
mkdir -p "$T/root/usr/local/sbin"; printf '#!/bin/sh\n' > "$T/root/usr/local/sbin/steam-arm-governor"; chmod 755 "$T/root/usr/local/sbin/steam-arm-governor"
gb(){ rm -f "$T/sudo.log" "$T/g.log"; ( export T; COMPONENTS_ON=$1; LOG=$T/g.log; PATH=$T/bin:$PATH
    comp_on(){ [ -z "${COMPONENTS_ON+x}" ] && return 0; case ",$COMPONENTS_ON," in *",$1,"*) return 0;; esac; return 1; }
    llog(){ echo "$*" >> "$LOG"; }; lwarn(){ echo "WARN $*" >> "$LOG"; }
    . <(sed "s#/usr/local/sbin/steam-arm-governor#$T/root/usr/local/sbin/steam-arm-governor#g" "$GB"); echo "GOVSET=$GOVSET"; restore_gov ) 2>&1; cat "$T/sudo.log" "$T/g.log" 2>/dev/null; }
OUT=$(gb "tray,pi-governor")
check "L1 part on: sudo helper performance at start, restore at exit, logged" "grep -qx 'GOVSET=1' <<<\"\$OUT\" && grep -q \"^sudo -n $T/root/usr/local/sbin/steam-arm-governor performance\" <<<\"\$OUT\" && grep -q \"^sudo -n $T/root/usr/local/sbin/steam-arm-governor restore\" <<<\"\$OUT\" && grep -q '^CPU governor: performance while Steam runs (pi-governor); put back at exit' <<<\"\$OUT\""
OUT=$(gb "tray")
check "L2 part off: nothing called" "grep -qx 'GOVSET=0' <<<\"\$OUT\" && ! grep -q '^sudo' <<<\"\$OUT\""
: > "$T/sudo.fail"; OUT=$(gb "tray,pi-governor"); rm -f "$T/sudo.fail"
check "L3 sudo refuses: warning names setup, no restore call" "grep -qx 'GOVSET=0' <<<\"\$OUT\" && grep -q '^WARN CPU governor not changed: sudo rule for steam-arm-governor missing' <<<\"\$OUT\" && ! grep -q 'restore' <<<\"\$OUT\""
chmod 644 "$T/root/usr/local/sbin/steam-arm-governor"; OUT=$(gb "tray,pi-governor"); chmod 755 "$T/root/usr/local/sbin/steam-arm-governor"
check "L4 helper missing or not executable: nothing called" "grep -qx 'GOVSET=0' <<<\"\$OUT\" && ! grep -q '^sudo' <<<\"\$OUT\""
check "L5 on_exit calls restore_gov" "grep -q 'restore_pad; restore_gov; bt_restore; }' $L"

# settings menu: Maintenance row 22 on a Raspberry Pi model, setup run with the part added or removed
T0=$SARM_TESTS/config-ui
export SARM_UI_FAKE=$T/fake SARM_UI_COPY=$T/app-copy.sh
bash "$T0/mkfake.sh" >/dev/null
sed -e "s#^APP=.*#APP=\"$CFG\"#" -e "s#^COPY=.*#COPY=$T/app-copy.sh#" "$T0/harness.sh" > "$T/harness.sh"
export Q=$T/q LOG=$T/ui.log FAKE_INST_LOG=$T/inst.log
cat > "$T/stubs.sh" <<'EOF'
nxt(){ A=$(head -n 1 "$Q"); sed -i 1d "$Q"; }
ui_menu(){ printf 'MENU %s|%s|%s\n' "$1" "$2" "${*:3}" >> "$LOG"; nxt; [ -n "$A" ] && [ "$A" != BACK ] || return 1; echo "$A"; }
ui_msg(){ printf 'MSG %s|%s\n' "$1" "$2" >> "$LOG"; }
ui_textstr(){ printf 'TEXT %s\n' "$1" >> "$LOG"; }
ui_info(){ :; }
ui_yesno(){ printf 'YESNO %s|%s\n' "$1" "$2" >> "$LOG"; nxt; [ "$A" = yes ]; }
up_notice(){ :; }; up_check_open(){ :; }; state_pending(){ return 1; }; status_line(){ :; }
run_installer(){ printf 'RUN_INSTALLER %s|%s\n' "$1" "$2" >> "$LOG"; }
EOF
ui(){ local s=$1; shift; : > "$LOG"; printf '%s\n' "$@" > "$Q"; bash -c ". $T/harness.sh --help >/dev/null; . $T/stubs.sh; $s" >/dev/null 2>"$T/err"; RC=$?; OUT=$(cat "$LOG" "$T/err"); }
ui menu_maintenance BACK
check "M1 other board (RK3588 model): no row 22" "! grep -q ' 22 CPU governor' <<<\"\$OUT\""
printf 'Raspberry Pi 4 Model B Rev 1.4\0' > "$SARM_UI_FAKE/proc/device-tree/model"
ui menu_maintenance 22 on
check "M2 Raspberry Pi model: row 22 (now: off); screen names heat, --cpu-report, /etc/default/cpu_governor; On runs setup with pi-governor added" \
  "grep -q ' 22 CPU governor while Steam runs (now: off)' <<<\"\$OUT\" && grep -q '^MENU CPU governor while Steam runs|Now: off. Governor in use: ' <<<\"\$OUT\" && grep -q 'more heat and power' <<<\"\$OUT\" && grep -q '/etc/default/cpu_governor' <<<\"\$OUT\" && grep -q '^RUN_INSTALLER CPU governor|--select=.*pi-governor' <<<\"\$OUT\""
ui menu_maintenance 22 off
check "M3 Off while off: message, no setup run" "grep -q '^MSG CPU governor|CPU governor while Steam runs: already off.' <<<\"\$OUT\" && ! grep -q RUN_INSTALLER <<<\"\$OUT\""
sed -i 's/^COMPONENTS_ON=\(.*\)$/COMPONENTS_ON=\1,pi-governor/' "$SARM_UI_FAKE/etc/steam-arm/steam-arm.conf"
ui menu_maintenance 22 off
check "M4 part on: row says on; Off runs setup without pi-governor" "grep -q ' 22 CPU governor while Steam runs (now: on)' <<<\"\$OUT\" && grep -q '^RUN_INSTALLER CPU governor|--select=' <<<\"\$OUT\" && ! grep -q '^RUN_INSTALLER.*pi-governor' <<<\"\$OUT\""
OUT=$(bash -c ". $T/harness.sh --help >/dev/null; gov_applies && echo applies; comp_short pi-governor" 2>&1)
check "M5 gov_applies on a Raspberry Pi model; comp_short names the part; SA_COMPONENTS lists it (installer --list decides elsewhere)" "grep -qx applies <<<\"\$OUT\" && grep -qx 'Raspberry Pi: governor performance while Steam runs' <<<\"\$OUT\" && grep -q '^SA_COMPONENTS=\".* pi-governor\"' '$CFG'"

echo "governor 3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
