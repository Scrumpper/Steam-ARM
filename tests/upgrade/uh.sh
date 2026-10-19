#!/bin/bash
# Upgrade harness: sources a copy of steam-arm-config with every system path pointed at fake root $UHR, root and Steam
# checks stubbed, owned paths listed under $UHR/sys and $UHR/home; then runs main "$@". UH_SRC: menu file (default SARM_CFG).
R=${UHR:?UHR not set}
APP=${UH_SRC:-$SARM_CFG}
COPY=$R/.menu-copy.sh
[ "$(tail -1 "$APP")" = 'main "$@"' ] || { echo "uh: last line of $APP is not main \"\$@\"" >&2; exit 99; }
[ -f "$COPY" ] && [ "$COPY" -nt "$APP" ] || sed -e '$d' "$APP" > "$COPY"
# shellcheck source=/dev/null
. "$COPY"
SA_CONF=$R/etc/steam-arm/steam-arm.conf
SA_TITLES_ETC=$R/etc/steam-arm/titles.conf
SA_LAUNCHER=$R/bin/steam-arm
SA_LIB=$R/lib
SA_UPCACHE=$R/cache
SA_LOCK=$R/run/steam-arm-setup.lock
SA_CACHE=$R/ucache
SA_MENU_BIN=$R/bin/steam-arm-config
SA_SHARE_INSTALLER=$R/share/steam-arm-install.sh
SA_PKG_INST=$R/pkg/install.sh
SA_REPORT=$R/report.txt
SA_RELEASE_API=http://127.0.0.1:${UH_PORT:-9}/repos/Scrumpper/Steam-ARM/releases/latest
SA_DL_PREFIX=http://127.0.0.1:${UH_PORT:-9}/dl/
SA_CURL_PROTO=()
game_home(){ echo "$R/home/tester"; }
game_user(){ echo tester; }
need_root(){ return 0; }
as_root(){ "$@"; }
cli_root(){ return 0; }
steam_running(){ [ -f "$R/steam-running" ]; }
game_running(){ return 1; }
runuser(){ shift 3; "$@"; }
sa_owned_paths(){
  printf '%s\n' "$R/sys/bin/steam-arm" "$R/sys/lib/helper.py" "$R/sys/nopkg" "$R/sys/bin/steam-arm-config" \
    "$R/sys/rules/with space.rules" "$R/sys/absent.rules" "$R/sys/new31" "$R/sys/old30" \
    "$R/sys/icons/*/apps/steam-arm.png" "$R/home/tester/.fex-emu/Config.json" "$SA_MENU_BIN"
}
# one level only: setup stand-ins and menu re-runs started from here call this harness again without it
UH_E=${UH_EVAL:-}; unset UH_EVAL
[ -n "$UH_E" ] && { eval "$UH_E"; exit $?; }
main "$@"
