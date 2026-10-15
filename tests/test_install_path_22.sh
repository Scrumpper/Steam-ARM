#!/bin/bash
# 2.2 install path: host package preflight, FEX from another source (packages skipped, thunk paths, stand-in),
# removal list, Mali family table (v11, 5th gen, G1, PanVK families). Blocks extracted from the installer copy in
# ~/.cache/sarm<NN>-work (paths.sh); /usr, /proc and /etc paths pointed at a fake tree; apt-cache, apt-get, dpkg, id stubbed.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
CFG=${SARM_CFG:-$(dirname "$INST")/steam-arm-config}
OLD=${SARM_INST21:-$(sarm_old 2.1)}
[ -n "$OLD" ] || { echo "SKIP suite compares with 2.1 release: not available (run through run-all.sh)"; exit 0; }
T=$(mktemp -d /tmp/sarm232-instpath.XXXXXX); trap 'rm -rf "$T"' EXIT
F=$T/fake; S=$T/stub; mkdir -p "$S" "$F"
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
# block <start regex> <end regex> [file]: lines from start through first end match after it
block(){ A=$1 B=$2 awk '!f && $0 ~ ENVIRON["A"] {f=1; print; next} f {print} f && $0 ~ ENVIRON["B"] {exit}' "${3:-$INST}"; }
upto(){ A=$1 B=$2 awk '$0 ~ ENVIRON["A"] {f=1} f && $0 ~ ENVIRON["B"] {exit} f {print}' "${3:-$INST}"; }

check "installer: bash -n" "bash -n '$INST'"
check "settings menu: bash -n" "bash -n '$CFG'"
check "embedded settings menu identical" "awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f' '$INST' | cmp -s - '$CFG'"

# ---------- extraction ----------
{ echo 'say(){ printf "==> %s\n" "$*"; }; warn(){ printf "[warn] %s\n" "$*"; }; die(){ printf "[fail] %s\n" "$*"; exit 1; }'
  echo 'opt(){ case " $OPTS " in *" $1 "*) return 0;; esac; return 1; }; wait_apt(){ :; }; NETHINT="(nethint)"'
  echo 'cpu_features(){ echo "$CPUF"; }'
  echo 'as_user(){ "$@"; }; user_write(){ cat > "$1"; }; own_mark(){ :; }'
  block '^# Packages among \$@ that apt offers' '^}$'
  block '^fex_packaged\(\)' '^fex_binfmt\(\)'
  block '^fex_thunk_paths\(\)' '^}$'
  block '^fex_arch\(\)\{' '^}$'
  block '^fex_pkg\(\)\{' '^}$'
  echo 'preflight(){'
  upto '^# --- host package preflight' '^if \[ "\$PAGESIZE" = 4096 \]; then$'
  echo '}'
  echo 'step1(){'
  block '^if \[ "\$FEX_OTHER" = 1 \]; then$' '^command -v FEX >/dev/null \|\| die'
  echo '}'
  echo 'fexcfg(){'
  block '^# Thunk folders of FEX in use \(package' '^JSON$'
  echo '}'
  echo 'remove_hint(){ local pkgs=$1'
  block '^  if \[ -n "\$pkgs" \]; then$' '^  fi$'
  echo '}'
} | sed -e "s#/proc/sys/fs/binfmt_misc#$F/binfmt#g" -e "s#for d in \$p /usr /usr/local; do#for d in \$p $F/usr $F/usr/local; do#" > "$T/funcs.sh"
check "extract: functions and blocks" "bash -n $T/funcs.sh && grep -q '^pkg_missing()' $T/funcs.sh && grep -q 'HOST_MISS=' $T/funcs.sh && grep -q 'FEXPKGS=' $T/funcs.sh && grep -q '\"ThunksDB\":{\"GL\":\$FEXTH' $T/funcs.sh && grep -q 'add-apt-repository --remove' $T/funcs.sh"

# stubs: apt-cache answers from $AVAIL (one name per line); apt-get logs, "update" swaps in $AVAIL2 (UPD_FAIL=1 fails);
# dpkg -S owns paths listed in $OWNED; id -u from $FAKEUID
cat > "$S/apt-cache" <<'EOF'
#!/bin/bash
[ "$1" = policy ] || exit 0; shift
L=Candidate; [ "${TRANSLATE:-0}" = 1 ] && [ "${LC_ALL:-}" != C ] && L=Installationskandidat
for p; do if grep -qx -- "$p" "$AVAIL"; then printf "%s${ARCHQ:+:arm64}:\n  Installed: (none)\n  $L: 1.0-1\n  Version table:\n     1.0-1 500\n" "$p"
  elif grep -qx -- "$p" "$KNOWN" 2>/dev/null; then printf '%s:\n  Installed: (none)\n  Candidate: (none)\n  Version table:\n' "$p"; fi; done
EOF
cat > "$S/apt-get" <<'EOF'
#!/bin/bash
echo "apt-get $*" >> "$LOGF"
case " $* " in *" update "*) [ "${UPD_FAIL:-0}" = 1 ] && exit 100; [ -n "${AVAIL2:-}" ] && cp "$AVAIL2" "$AVAIL";; esac; exit 0
EOF
printf '#!/bin/bash\n[ "$1" = -S ] && grep -qx -- "$2" "$OWNED" 2>/dev/null && { echo "fex-emu-armv8.2: $2"; exit 0; }\nexit 1\n' > "$S/dpkg"
printf '#!/bin/bash\n[ "$1" = -u ] && { echo "${FAKEUID:-0}"; exit 0; }\nexec /usr/bin/id "$@"\n' > "$S/id"
printf '#!/bin/sh\necho "add-apt-repository $*" >> "$LOGF"\n' > "$S/add-apt-repository"
chmod 755 "$S"/*
export LOGF=$T/log AVAIL=$T/avail KNOWN=$T/known OWNED=$T/owned
HOST="bubblewrap dbus-daemon xz-utils libsdl3-0 libsdl3-image0 libsdl3-ttf0 libgtk2.0-0t64 libopenal1 libibus-1.0-5 zenity xdotool x11-xserver-utils curl python3 file"
# 2.1 install line had no libibus-1.0-5 (step 1 package set comparison)
HOST21="bubblewrap dbus-daemon xz-utils libsdl3-0 libsdl3-image0 libsdl3-ttf0 libgtk2.0-0t64 libopenal1 zenity xdotool x11-xserver-utils curl python3 file"
BUILD="gcc libc6-dev libvulkan-dev patchelf zstd python3-pil gir1.2-ayatanaappindicator3-0.1"
FEXP="fex-emu-armv8.0 fex-emu-armv8.2 fex-emu-binfmt32 fex-emu-binfmt64"
CPU82="fp asimd atomics crc32 asimdrdm dcpop"
# reset [available words...]: fresh fake tree, empty log, nothing owned, no FEX on PATH, root
reset(){ rm -rf "$F"; mkdir -p "$F/binfmt" "$F/bin"; printf '%s\n' "$@" > "$AVAIL"; printf '%s\n' $HOST $BUILD $FEXP > "$KNOWN"
  : > "$LOGF"; : > "$OWNED"; unset AVAIL2 UPD_FAIL; export FAKEUID=0 OPTS="" CPUF="$CPU82"; }
run(){ OUT=$(PATH="$F/bin:$S:/usr/bin:/bin" bash -c ". $T/funcs.sh; $1" 2>&1); RC=$?; }
mkfex(){ mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\necho "FEX $*"\n' > "$1"; chmod 755 "$1"; ln -sf "$1" "$F/bin/FEX"; }

# ---------- pkg_missing ----------
reset $HOST
run "pkg_missing $HOST"; check "pkg_missing: all offered -> empty" "[ -z \"\$OUT\" ]"
reset bubblewrap zenity
run "pkg_missing bubblewrap libsdl3-0 zenity nosuchpkg"; check "pkg_missing: Candidate (none) and unknown package listed, offered ones not" "[ \"\$OUT\" = 'libsdl3-0 nosuchpkg ' ]"
reset libsdl3-0; export ARCHQ=1
run "pkg_missing libsdl3-0 zenity"; unset ARCHQ
check "pkg_missing: arch-qualified stanza (pkg:arm64:) counts as offered" "[ \"\$OUT\" = 'zenity ' ]"
reset $HOST; export TRANSLATE=1; unset LC_ALL
run "pkg_missing $HOST"; check "pkg_missing: translated apt-cache output (locale not C): all offered -> empty" "[ -z \"\$OUT\" ]"
reset $HOST $FEXP; export CPUF="$CPU82 fcma jscvt lrcpc paca pacg asimddp flagm ilrcpc uscat"
run "fex_pkg"; unset TRANSLATE
check "fex_pkg: translated locale, ARMv8.4 CPU, no 8.4 build offered: picks offered 8.2 build" "[ \"\$OUT\" = fex-emu-armv8.2 ]"

# ---------- preflight ----------
reset $HOST
run "preflight; echo FEX_OTHER=\$FEX_OTHER"
check "preflight: all host packages offered: passes, no apt-get call" "[ $RC = 0 ] && grep -q FEX_OTHER=0 <<<\"\$OUT\" && [ ! -s $LOGF ]"
reset bubblewrap dbus-daemon xz-utils libgtk2.0-0t64 libopenal1 libibus-1.0-5 zenity xdotool x11-xserver-utils curl python3 file
run preflight
check "preflight: Ubuntu 24.04 set (no SDL3): stops, names packages and minimum releases" "[ $RC = 1 ] && grep -q 'libsdl3-0 libsdl3-image0 libsdl3-ttf0\$' <<<\"\$OUT\" && grep -q 'Ubuntu 25.10 or newer, Debian 13 or newer' <<<\"\$OUT\" && grep -q 'README, Requirements' <<<\"\$OUT\" && grep -q 'No package or package source changed' <<<\"\$OUT\""
check "preflight: package lists read once, nothing installed, no source added" "[ \$(grep -c 'apt-get update' $LOGF) = 1 ] && ! grep -q 'install' $LOGF && ! grep -q add-apt-repository $LOGF"
reset bubblewrap dbus-daemon xz-utils libgtk2.0-0 libopenal1 libibus-1.0-5 zenity xdotool x11-xserver-utils curl python3 file
run preflight
check "preflight: Debian 12 set (no SDL3, no t64 gtk2): stops, names libgtk2.0-0t64" "[ $RC = 1 ] && grep -q 'libsdl3-ttf0 libgtk2.0-0t64\$' <<<\"\$OUT\""
reset bubblewrap; printf '%s\n' $HOST > "$T/avail2"; export AVAIL2=$T/avail2
run preflight
check "preflight: stale lists: refreshed once, then passes" "[ $RC = 0 ] && [ \$(grep -c 'apt-get update' $LOGF) = 1 ]"
reset bubblewrap; export FAKEUID=1000
run preflight
check "preflight: not root: no refresh, check skipped with warning" "[ $RC = 0 ] && [ ! -s $LOGF ] && grep -q 'host package check skipped' <<<\"\$OUT\""
reset bubblewrap; export UPD_FAIL=1
run preflight
check "preflight: refresh fails: check skipped with warning (later apt-get update reports)" "[ $RC = 0 ] && grep -q 'host package check skipped' <<<\"\$OUT\""
# libibus-1.0-5: steamwebhelper of native client links libibus-1.0.so.5 (absent on Raspberry Pi OS desktop)
check "host packages name libibus-1.0-5 (same name on Ubuntu 25.10+, Debian 13)" "grep -q '^HOSTPKGS=\".* libopenal1 libibus-1.0-5 ' '$INST'"
reset $(printf '%s\n' $HOST | grep -vx libibus-1.0-5)
run preflight
check "preflight: libibus-1.0-5 not offered: stops before any change, names it" "[ $RC = 1 ] && grep -q 'lack host packages setup needs: libibus-1.0-5\$' <<<\"\$OUT\" && ! grep -q install $LOGF"
check "after install: libibus-1.0.so.5 checked with SDL3, OpenAL, GTK 2" "grep -q '^for l in libSDL3.so.0 libopenal.so.1 libgtk-x11-2.0.so.0 libibus-1.0.so.5; do\$' '$INST'"
reset $HOST; export OPTS="vk-spoof tray"
run preflight
check "preflight: component build packages checked too (vk-spoof: gcc libc6-dev libvulkan-dev)" "[ $RC = 1 ] && grep -q 'gcc libc6-dev libvulkan-dev gir1.2-ayatanaappindicator3-0.1\$' <<<\"\$OUT\""
# FEX from another source
reset $HOST; mkfex "$F/usr/local/bin/FEX"; touch "$F/binfmt/FEX-x86_64" "$F/binfmt/FEX-x86"
run "preflight; echo FEX_OTHER=\$FEX_OTHER"
check "preflight: FEX from other source + binfmt entries: FEX_OTHER=1" "[ $RC = 0 ] && grep -q FEX_OTHER=1 <<<\"\$OUT\""
rm -f "$F/binfmt/FEX-x86"
run preflight
check "preflight: FEX from other source, 32-bit binfmt entry missing: stops before any change" "[ $RC = 1 ] && grep -q 'binfmt entries' <<<\"\$OUT\" && grep -q 'No package or package source changed' <<<\"\$OUT\" && [ ! -s $LOGF ]"
rm -f "$F/binfmt/FEX-x86_64"
run preflight; check "preflight: FEX from other source, no binfmt entries: stops" "[ $RC = 1 ]"
reset $HOST; mkfex "$F/usr/bin/FEX"; readlink -f "$F/usr/bin/FEX" > "$OWNED"
run "preflight; echo FEX_OTHER=\$FEX_OTHER"
check "preflight: FEX from fex-emu package (no binfmt needed here): FEX_OTHER=0" "[ $RC = 0 ] && grep -q FEX_OTHER=0 <<<\"\$OUT\""

# ---------- step 1 install line ----------
reset $HOST $FEXP; mkfex "$F/usr/local/bin/FEX"
run "FEX_OTHER=1; HOSTPKGS='$HOST'; step1"
check "step 1, other source: no FEX packages in apt-get install, host packages installed" "[ $RC = 0 ] && grep -q 'FEX from another source: .*/bin/FEX; FEX packages skipped' <<<\"\$OUT\" && grep -q '^apt-get install -y bubblewrap .* file\$' $LOGF && ! grep -q fex-emu $LOGF"
reset $HOST $FEXP; mkfex "$F/usr/bin/FEX"
run "FEX_OTHER=0; HOSTPKGS='$HOST21'; step1"
INSTW=$(sed -n 's/^apt-get install -y //p' "$LOGF" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ')
OLDW=$(grep -A1 '^wait_apt; apt-get install -y "\$FEXPKG"' "$OLD" | tr -d '\\' | sed 's/wait_apt; apt-get install -y//; s/"\$FEXPKG"/fex-emu-armv8.2/; s/\$BUILDPKGS//; s/||.*//' | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ')
check "step 1, package FEX: same apt-get install package set as 2.1" "[ $RC = 0 ] && [ -n \"\$INSTW\" ] && [ \"\$INSTW\" = \"\$OLDW\" ]"
reset $HOST; mkfex "$F/usr/bin/FEX"
run "FEX_OTHER=0; HOSTPKGS='$HOST'; step1"
check "step 1: FEX packages not offered: stops before apt-get install, points at other source" "[ $RC = 1 ] && grep -q 'FEX packages not offered by this system.s package sources: fex-emu-armv8.2 fex-emu-binfmt32 fex-emu-binfmt64\$' <<<\"\$OUT\" && grep -q InstallFEX.py <<<\"\$OUT\" && ! grep -q 'apt-get install' $LOGF"
check "install failure text names README Requirements" "grep -q \"README, Requirements names supported releases\" '$INST' && ! grep -q 'README lists supported systems' '$INST'"

# ---------- order: preflight before any package or source change ----------
ln_of(){ grep -n -m1 -- "$1" "$INST" | cut -d: -f1; }
LP=$(ln_of '^# --- host package preflight'); LR=$(ln_of '^if \[ "\$MODE" = remove \]; then remove_all; exit 0; fi')
LPS=$(grep -n -- '^if \[ "\$PAGESIZE" = 4096 \]; then$' "$INST" | tail -1 | cut -d: -f1); LRO=$(ln_of '^\[ "\$RETIRE_OTHER" = 1 \] && retire_other')
LS=$(ln_of '^  fex_source_debian$'); LA=$(ln_of '^wait_apt; apt-get update -y')
check "preflight after --remove exit, before page-size edit, retire_other, FEX source and apt-get update" "[ $LR -lt $LP ] && [ $LP -lt $LPS ] && [ $LPS -lt $LRO ] && [ $LRO -lt $LS ] && [ $LS -lt $LA ]"
OUTSIDE=$(awk '/^menu_app\(\)\{ cat <<.STEAMARMCONFIG.$/{f=1;next} /^STEAMARMCONFIG$/{f=0;next} !f' "$INST")
NEWCODE=$(upto '^# --- host package preflight' '^ *steam_banner '; block '^if \[ "\$FEX_OTHER" = 1 \]; then$' '^command -v FEX'; block '^# Thunk folders of FEX in use \(package' '^JSON$')
undef=""; for f in pkg_missing fex_packaged fex_binfmt fex_thunk_paths fex_pkg fex_arch cpu_features opt warn die say want_icons wait_apt as_user user_write; do
  grep -q "^$f()" <<<"$OUTSIDE" || undef="$undef $f"; done
grep -q 'fex_ver' <<<"$NEWCODE" && undef="$undef fex_ver(menu-only)"
OUT=$undef; check "helpers called by new blocks are defined outside embedded settings menu" "[ -z \"\$undef\" ]"
check "BUILDPKGS defined once" "[ \$(grep -c '^BUILDPKGS=\"\"; opt vk-spoof' '$INST') = 1 ] && [ \$(grep -c '^want_icons()' '$INST') = 1 ]"

# ---------- thunk paths in game user's FEX config ----------
cfg(){ run "RFS=/opt/fex-rootfs/Ubuntu_24_04; FEXEXTRA=\$'$1'; UHOME=$F/home; GAMEUSER=u; fexcfg; cat $F/home/.fex-emu/Config.json"; }
mkthunks(){ mkdir -p "$1" "$2/GuestThunks"; echo '{}' > "$2/ThunksDB.json"; }
EXTRA=',\n  "Multiblock":"1",\n  "HostEnv":"__GLX_VENDOR_LIBRARY_NAME=steamarmlax"'
reset; mkfex "$F/usr/bin/FEX"; mkthunks "$F/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks" "$F/usr/share/fex-emu"
cfg "$EXTRA"
# 2.1 block rendered with same values for comparison
{ echo 'as_user(){ "$@"; }; user_write(){ cat > "$1"; }'; echo 'old(){'; block '^as_user mkdir -p "\$UHOME/.fex-emu"' '^JSON$' "$OLD"; echo '}'; } > "$T/old.sh"
OLDJ=$(bash -c ". $T/old.sh; RFS=/opt/fex-rootfs/Ubuntu_24_04; FEXEXTRA=\$'$EXTRA'; UHOME=$T/oldhome; GAMEUSER=u; old; cat $T/oldhome/.fex-emu/Config.json" 2>&1)
check "package layout: Config.json byte-identical to 2.1 (paths under /usr)" "[ $RC = 0 ] && [ \"\$(sed \"s#$F##g\" <<<\"\$OUT\")\" = \"\$OLDJ\" ]"
check "package layout: JSON valid, thunks on" "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d[\"ThunksDB\"]=={\"GL\":1,\"Vulkan\":1}' $F/home/.fex-emu/Config.json"
has_lax(){ python3 -c 'import sys; sys.exit(0 if ",\n  \"HostEnv\":\"__GLX_VENDOR_LIBRARY_NAME=steamarmlax\"" in open(sys.argv[1]).read() else 1)' "$1"; }
check "launcher's glx-lax HostEnv strip string still matches" "has_lax $F/home/.fex-emu/Config.json"
reset; mkfex "$F/usr/local/bin/FEX"; mkthunks "$F/usr/local/lib/fex-emu/HostThunks" "$F/usr/local/share/fex-emu"
cfg ',\n  "Multiblock":"1"'
check "source build in /usr/local (lib/fex-emu): /usr/local thunk paths" "[ $RC = 0 ] && grep -q '\"ThunkHostLibs\":\"$F/usr/local/lib/fex-emu/HostThunks/\"' <<<\"\$OUT\" && grep -q '\"ThunkGuestLibs\":\"$F/usr/local/share/fex-emu/GuestThunks/\"' <<<\"\$OUT\" && grep -q '\"ThunkConfig\":\"$F/usr/local/share/fex-emu/ThunksDB.json\"' <<<\"\$OUT\" && grep -q '\"GL\":1' <<<\"\$OUT\""
reset; mkfex "$F/opt/fex/bin/FEX"; mkthunks "$F/opt/fex/lib/aarch64-linux-gnu/fex-emu/HostThunks" "$F/opt/fex/share/fex-emu"
mkthunks "$F/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks" "$F/usr/share/fex-emu"
cfg ',\n  "Multiblock":"1"'
check "FEX in other prefix: its own thunks win over /usr leftovers" "grep -q '\"ThunkHostLibs\":\"$F/opt/fex/lib/aarch64-linux-gnu/fex-emu/HostThunks/\"' <<<\"\$OUT\""
reset; mkfex "$F/usr/local/bin/FEX"; mkdir -p "$F/usr/local/share/fex-emu/GuestThunks"; echo '{}' > "$F/usr/local/share/fex-emu/ThunksDB.json"
cfg ',\n  "Multiblock":"1"'
check "no complete thunk set (HostThunks missing): thunks off with warning, no path keys, JSON valid" "[ $RC = 0 ] && grep -q 'thunk libraries not found' <<<\"\$OUT\" && ! grep -q ThunkHostLibs $F/home/.fex-emu/Config.json && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d[\"ThunksDB\"]=={\"GL\":0,\"Vulkan\":0} and d[\"Config\"][\"Multiblock\"]==\"1\"' $F/home/.fex-emu/Config.json"

# ---------- Remote Play stand-in: FEX outside /usr/bin ----------
mkdir -p "$T/sc/ubuntu12_64" "$T/sc/bin"; touch "$T/sc/ubuntu12_64/streaming_client"
block '^cat > "\$D/streaming_client.new" <<.SH.$' '^SH$' | sed '1d;$d' > "$T/sc/bin/streaming_client"; chmod 755 "$T/sc/bin/streaming_client"
reset; mkfex "$F/usr/local/bin/FEX"
OUT=$(PATH="$F/bin:/usr/bin:/bin" "$T/sc/bin/streaming_client" --openvr --x 2>&1)
check "stand-in: runs FEX found on PATH when /usr/bin/FEX is absent, --openvr dropped" "[ ! -e /usr/bin/FEX ] && [ \"\$OUT\" = \"FEX $T/sc/ubuntu12_64/streaming_client --x\" ]"
check "stand-in: FEX from PATH first (same FEX as thunk paths), /usr/bin/FEX fallback" "grep -qx 'F=\$(command -v FEX) || F=/usr/bin/FEX' $T/sc/bin/streaming_client"
# upgrade: 2.1 stand-in (hardcoded /usr/bin/FEX) replaced; current one left alone; ELF moved aside
SCW=$T/scw; mkdir -p "$SCW"
{ echo 'D=$1'; block '^if \[ -f "\$D/streaming_client" \] && \[ "\$\(head -c 4' '^else chmod 755 "\$D/streaming_client.new"'; } > "$T/sc/write.sh"
block '^cat > "\$D/streaming_client" <<.SH.$' '^SH$' "$OLD" | sed '1d;$d' > "$SCW/streaming_client"; chmod 755 "$SCW/streaming_client"
check "upgrade fixture: 2.1 stand-in has marker and exec /usr/bin/FEX" "grep -q 'x86-64 streaming client' $SCW/streaming_client && grep -q 'exec /usr/bin/FEX' $SCW/streaming_client"
# guard: run the extracted block only when it is the bounded stand-in writer
SCOK=0; [ "$(wc -l < "$T/sc/write.sh")" -lt 30 ] && grep -q '^else chmod 755 "$D/streaming_client.new"' "$T/sc/write.sh" && SCOK=1
check "extract: stand-in writer block bounded" "[ $SCOK = 1 ]"
[ $SCOK = 1 ] || : > "$T/sc/write.sh"
bash "$T/sc/write.sh" "$SCW"
check "upgrade: 2.1 stand-in replaced by current body, executable, no .new left" "cmp -s $SCW/streaming_client $T/sc/bin/streaming_client && [ -x $SCW/streaming_client ] && [ ! -e $SCW/streaming_client.new ]"
touch -d '2000-01-01' "$SCW/streaming_client"; bash "$T/sc/write.sh" "$SCW"
check "current stand-in: left untouched" "[ \"\$(stat -c %Y $SCW/streaming_client)\" = \"\$(date -d 2000-01-01 +%s)\" ] && [ ! -e $SCW/streaming_client.new ]"
printf '\177ELFbinary' > "$SCW/streaming_client"; rm -f "$SCW/streaming_client.real"; bash "$T/sc/write.sh" "$SCW"
check "client update (ELF): moved to .real, stand-in written" "grep -q ELFbinary $SCW/streaming_client.real && cmp -s $SCW/streaming_client $T/sc/bin/streaming_client"

# ---------- removal ----------
check "removal list names libgtk2.0-0 and libgtk2.0-0t64" "grep -q '^  pkgs=\"\$pkgs libgtk2.0-0t64 libgtk2.0-0 ' '$INST'"
check "removal list (kept, shown in apt remove hint) names libibus-1.0-5" "grep -q '^  pkgs=\"\$pkgs .* libopenal1 libibus-1.0-5 ' '$INST'"
reset
run "os_ubuntu(){ true; }; FEXSRC=/x; FEXKEY=/y; FEXPPA=ppa:fex-emu/fex; fexsrc=0; remove_hint 'fex-emu-armv8.2 zenity '"
check "remove on Ubuntu with FEX package: PPA removal hint" "grep -q 'sudo add-apt-repository --remove ppa:fex-emu/fex' <<<\"\$OUT\""
run "os_ubuntu(){ true; }; FEXSRC=/x; FEXKEY=/y; FEXPPA=ppa:fex-emu/fex; fexsrc=0; remove_hint 'zenity '"
check "remove on Ubuntu, FEX from other source: no PPA hint" "grep -q 'sudo apt remove zenity' <<<\"\$OUT\" && ! grep -q 'FEX package source' <<<\"\$OUT\""

# ---------- Mali family table ----------
{ echo 'GPU_DRV=""'; block '^gpu_family_of\(\)\{' '^}$'; block '^gpu_defaults\(\)\{' '^  esac$'; echo '}'; } > "$T/gpu.sh"
fam(){ bash -c ". $T/gpu.sh; gpu_family_of $*" 2>&1; }
check "panthor 10.7 (G610) -> mali-csf-v10" "[ \"\$(fam panthor - a0070000)\" = 'mali-csf-v10 60' ]"
check "panthor 10.4 (G310) -> mali-csf-v10" "[ \"\$(fam panthor - a0040000)\" = 'mali-csf-v10 60' ]"
check "panthor 11.x (G615/G715) -> mali-csf-v11" "[ \"\$(fam panthor - b0020000)\" = 'mali-csf-v11 59' ] && [ \"\$(fam panthor - b0030000)\" = 'mali-csf-v11 59' ]"
check "panthor 12.x, 13.x -> mali-csf-5thgen" "[ \"\$(fam panthor - c0010000)\" = 'mali-csf-5thgen 58' ] && [ \"\$(fam panthor - d0010000)\" = 'mali-csf-5thgen 58' ]"
check "panthor 14.x (G1) -> mali-csf-g1" "[ \"\$(fam panthor - e0010000)\" = 'mali-csf-g1 57' ]"
check "panthor arch 15 / no id, no known compatible -> mali-csf" "[ \"\$(fam panthor - f0010000)\" = 'mali-csf 55' ] && [ \"\$(fam panthor x -)\" = 'mali-csf 55' ]"
check "no id: rk3588 compatible -> v10, mt8196 -> 5thgen" "[ \"\$(fam panthor rockchip,rk3588-mali -)\" = 'mali-csf-v10 60' ] && [ \"\$(fam tyr mediatek,mt8196-mali -)\" = 'mali-csf-5thgen 58' ]"
def(){ bash -c ". $T/gpu.sh; gpu_defaults $1; echo \"\$GPU_DEF|\$GPU_NOTE\"" 2>&1; }
OUT=$(def mali-csf-v11); check "v11 defaults: vk-spoof off, gpu-in-emulation on, glx-lax on, untested + PanVK note" "[[ \"\$OUT\" == '0 1 1|'*untested*'PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1' ]]"
OUT=$(def mali-csf-g1); check "G1 defaults: vk-spoof and gpu-in-emulation off, Mesa 26.2 note" "[[ \"\$OUT\" == '0 0 1|'*'Mesa 26.2 or newer'* ]]"
OUT=$(def mali-csf-5thgen); check "5th gen: vk-spoof off by default (PanVK not loaded), PanVK note" "[[ \"\$OUT\" == '0 1 1|'*'PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1' ]]"
OUT=$(def mali-csf); check "mali-csf note no longer claims Mesa lacks model" "! grep -q 'does not support' <<<\"\$OUT\" && [[ \"\$OUT\" == '0 0 1|'* ]]"
check "GPU_FAMILIES accepts mali-csf-v11 and mali-csf-g1" "grep -q '^GPU_FAMILIES=\"mali-csf-v10 mali-csf-v11 mali-csf-5thgen mali-csf-g1 mali-csf ' '$INST'"
check "SA_MALI_FAMILIES (installer copy and settings menu): v11 in, g1 out" "for f in '$INST' '$CFG'; do grep -q '^SA_MALI_FAMILIES=\"mali-csf-v10 mali-csf-v11 mali-csf-5thgen mali-csf mali-valhall-jm' \"\$f\" || exit 1; done; ! grep -q '^SA_MALI_FAMILIES=.*mali-csf-g1' '$INST' '$CFG'"
check "install wizard (both copies) offers v11 and G1" "[ \$(grep -c 'mali-csf-v11 \"Mali-G615 / G715' '$INST') = 1 ] && [ \$(grep -c 'mali-csf-g1 \"Mali-G1' '$INST') = 1 ] && grep -q 'mali-csf-v11 \"Mali-G615 / G715' '$CFG' && grep -q 'mali-csf-g1 \"Mali-G1' '$CFG'"
# handler route decision (lines extracted, helpers stubbed)
{ grep -E '^(MALI_FAMILIES|PANVK_FAMILIES) = ' "$INST"
  upto '^vk = \[a for a in sys.argv if a in' '^if prof.get\("gfx"\) == "b" and fam not in MALI_FAMILIES'; } > "$T/route.py"
route(){ python3 - "$1" "$2" "$T/route.py" <<'EOF'
import sys
fam_, args, path = sys.argv[1], sys.argv[2].split(), sys.argv[3]
g = {"sys": type("S", (), {"argv": ["x"] + args})(), "bits": 32, "jre": None, "gpu_family": lambda: fam_,
     "gfx_default": lambda: "", "mali_ready": lambda: True, "mali_custom": lambda: False}
exec(open(path).read(), g)
print(g["gfx"], g["why"])
EOF
}
check "handler: PANVK_FAMILIES is mali-csf-v10 only; v11 in MALI_FAMILIES, g1 not" "grep -qx 'PANVK_FAMILIES = (\"mali-csf-v10\",)' $T/route.py && grep -q '\"mali-csf-v11\"' $T/route.py && ! grep -q 'mali-csf-g1' $T/route.py"
check "handler: 32-bit -vulkan on mali-csf-v10 -> route b" "[ \"\$(route mali-csf-v10 -vulkan)\" = 'b 32-bit Vulkan' ]"
check "handler: 32-bit -vulkan on mali-csf-5thgen -> forwarding (PanVK not loaded by default)" "[[ \"\$(route mali-csf-5thgen -vulkan)\" == 'a 32-bit Vulkan: no default Vulkan driver'* ]]"
check "handler: 32-bit -vulkan on mali-csf-g1 -> forwarding (second tree does not cover it)" "[[ \"\$(route mali-csf-g1 -vulkan)\" == 'a Mali drivers inside the emulation do not cover GPU family mali-csf-g1' ]]"
check "setup --help: -vulkan switch named for Mali-G610 class only" "grep -q '^  -force-vulkan (Mali-G610 class, mali-csf-v10, only)' '$INST' && ! grep -q 'Mali 5th gen only' '$INST'"
check "handler help text: panvk default only on mali-csf-v10" "grep -q '^                  mali-csf-v10 (panvk loads by default only there).' '$INST' && ! grep -q 'mali-csf-v10 or mali-csf-5thgen' '$INST'"

# ---------- 2.3 x86 client: removal ----------
RA=$(block '^remove_all\(\)' '^  return 0$')
l_rs=$(grep -n 'as_user python3 /usr/local/lib/steam-arm-x86client.py restore "\$armhome/.local/share/Steam" "\$armhome"' <<<"$RA" | cut -d: -f1)
l_rm=$(grep -n '^  rm -f /usr/local/bin/steam-arm /usr/local/bin/steam-arm-remoteplay' <<<"$RA" | cut -d: -f1)
check "x86 removal: client folder edits put back (restore) before helpers are deleted; result in Restored line" "[ -n '$l_rs' ] && [ -n '$l_rm' ] && [ $l_rs -lt $l_rm ] && grep -q 'restored=\"\${restored:+\$restored, }\$x\"' <<<\"\$RA\""
RL=$(awk '/^  rm -f \/usr\/local\/bin\/steam-arm \/usr\/local\/bin\/steam-arm-remoteplay/{f=1} f{print} f && !/\\$/{exit}' "$INST")
check "x86 removal: rm list names x86client.py, run.py, pv-bwrap and python link" "for f in steam-arm-x86client.py steam-arm-run.py steam-arm-pv-bwrap steam-arm-python3; do grep -q \"/usr/local/lib/\$f\" <<<\"\$RL\" || exit 1; done"
check "x86 removal: package-tool stub folder removed" "grep -q '^  rm -rf \"\$NOPKG\"\$' <<<\"\$RA\" && grep -q '^NOPKG=/usr/local/lib/steam-arm-nopkg\$' '$INST'"
check "x86 removal: RootFS bwrap put back by rfs_unguard (already called by removal)" "block '^rfs_unguard\\(\\)' '^}\$' | grep -q 'mv -f \"\$p.steam-arm-real\" \"\$p\" && r=0' && grep -q 'rfs_unguard \"\$RFS\"' <<<\"\$RA\""

echo "test_install_path_22: $pass passed, $fail failed"
[ "$fail" = 0 ]
