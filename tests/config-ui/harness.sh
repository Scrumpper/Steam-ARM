#!/bin/bash
# Test harness: sources a sed-edited copy of steam-arm-config (/sys and /proc pointed at the fake tree, final main call dropped).
[ -n "${SARM_TESTS:-}" ] || . "$(dirname "${BASH_SOURCE[0]}")/../paths.sh"
R=${SARM_UI_FAKE:-$SARM_TESTS/config-ui/fake}
APP="$SARM_CFG"
COPY=${SARM_UI_COPY:-$SARM_TESTS/config-ui/app-copy.sh}
[ "$(tail -1 "$APP")" = 'main "$@"' ] || { echo "harness: last line of $APP is not main \"\$@\"" >&2; exit 99; }
sed -e "s#\"/proc/#\"$R/proc/#g" -e "s#/sys/class#$R/sys/class#g" -e '$d' "$APP" > "$COPY"
# shellcheck source=/dev/null
. "$COPY"
SA_CONF=$R/etc/steam-arm/steam-arm.conf
SA_TITLES_SHARE=$R/share/titles.conf
SA_TITLES_ETC=$R/etc/steam-arm/titles.conf
SA_LAUNCHER=$R/bin/steam-arm
SA_COMPATMAP=$R/bin/steam-arm-compatmap
SA_REMOTEPLAY=$R/bin/steam-arm-remoteplay
SA_RFS=$R/opt/Ubuntu_24_04
SA_MALI=$R/opt/Ubuntu_24_04-mali
SA_REPORT=$R/tmp/steam-arm-report.txt
SA_CACHE=$R/tmp/cache
SA_RULE_HIDRAW=$R/rules/60-steam-arm-gamepad-hidraw.rules
SA_RULE_DEDUP=$R/rules/71-steam-arm-xpad-dedup.rules
SA_PADXBOX_UNIT=$R/rules/steam-arm-pad-xbox.service
SA_FEXLOG_GLOB="$R/tmp/fex-compat-tool-*.log"
export STEAM_ARM_INSTALLER=$R/bin/fake-installer.sh
[ "${HARNESS_REAL_INSTALLER:-0}" = 1 ] && STEAM_ARM_INSTALLER="$SARM_INST"
[ "${FAKE_NOT_INSTALLED:-0}" = 1 ] && SA_LAUNCHER=$R/bin/missing
game_home(){ echo "$R/home/tester"; }
game_user(){ echo tester; }
need_root(){ return 0; }
as_root(){ "$@"; }
self_root(){ main "$@" >/dev/null; }
cli_root(){ return 0; }
steam_running(){ return 1; }
runuser(){ shift 3; "$@"; }
main "$@"
