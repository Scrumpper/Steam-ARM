# Sourced by suites: SARM_INST, SARM_CFG, SARM_TESTS, SARM_OLD, SARM_PREV from run-all.sh or caller. Suite run alone:
# this tests folder, source root (repo checkout) or <V>-work beside <V>-tests; settings menu extracted from installer
# when absent; no earlier releases (cases that need them SKIP). run-all.sh gives paths without spaces.
_sarm_d=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
if [ -f "$(dirname "$_sarm_d")/steam-arm-install.sh" ]; then _sarm_w=$(dirname "$_sarm_d")
else _sarm_w=$(dirname "$_sarm_d")/$(basename "$_sarm_d" | sed 's/-tests$/-work/'); fi
: "${SARM_TESTS:=$_sarm_d}"
: "${SARM_INST:=$_sarm_w/steam-arm-install.sh}"
: "${SARM_CFG:=$(dirname "$SARM_INST")/steam-arm-config}"
if [ ! -f "$SARM_CFG" ]; then
  SARM_CFG=$(mktemp "${TMPDIR:-/tmp}/sarm-menu.XXXXXX")
  awk "/^menu_app\\(\\)\\{ cat <<'STEAMARMCONFIG'\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f" "$SARM_INST" > "$SARM_CFG"
fi
: "${SARM_OLD:=}" "${SARM_PREV:=}"
: "${SARM_VERSION:=$(sed -n 's/^SA_VERSION=//p' "$SARM_INST" | head -n 1)}"
# gate tools: tools/gates in repo checkout, tools/ beside <V>-tests in project folder
if [ -d "$(dirname "$_sarm_d")/tools/gates" ]; then : "${SARM_GATES:=$(dirname "$_sarm_d")/tools/gates}"
else : "${SARM_GATES:=$(dirname "$_sarm_d")/tools}"; fi
# Debian rootfs for chroot cases (fetch-debian.sh puts it there)
: "${SARM_ROOTFS:=${SARM_TOOLS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sarm-tools}/trixie-slim-rootfs}"
export SARM_TESTS SARM_INST SARM_CFG SARM_OLD SARM_PREV SARM_VERSION SARM_GATES SARM_ROOTFS
# sarm_old VERSION [FILE]: file of an earlier release (installer by default); empty when not available
sarm_old(){ local f=${SARM_OLD:+$SARM_OLD/$1/${2:-steam-arm-install.sh}}; [ -n "$f" ] && [ -e "$f" ] && echo "$f"; }
unset _sarm_d _sarm_w
