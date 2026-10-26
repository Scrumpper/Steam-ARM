#!/bin/bash
# 3.1 lepton component (off by default): host packages for Valve's Lepton recorded at install and purged on removal
# (only packages it added, never when the purge takes others), setpgid and steamvr stand-ins, launcher PATH and umask
# only with the part, guestos link, render node drop-in stub. Blocks extracted from the installer under test
# (SARM_INST picks another); dpkg-query and apt-get are stand-ins on a fake package state. Internal; not for release zips.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm31-lep.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }

# component lists, default off, descriptions, installed(), removal and owned paths
check "C1 lepton in COMPONENTS_ALL, DEFAULT_OFF (installer) and SA_COMPONENTS, SA_DEFAULT_OFF (menu)" \
  "grep -q '^COMPONENTS_ALL=\".* pi-governor lepton\"' '$INST' && grep -q '^DEFAULT_OFF=\".* pi-governor lepton\"' '$INST' && grep -q '^SA_COMPONENTS=\".* pi-governor lepton\"' '$CFG' && grep -q '^SA_DEFAULT_OFF=\".* pi-governor lepton\"' '$CFG'"
OUT=$(bash -c "cd '$T' && env -i HOME='$T' PATH=/usr/bin:/bin bash '$INST' --list" 2>&1)
check "C2 --list names lepton with its description" "grep -q \"^  lepton  *Host tools for Valve's Lepton (Android titles)\" <<<\"\$OUT\""
OUT=$(bash -c "cd '$T' && env -i HOME='$T' PATH=/usr/bin:/bin bash '$INST' --help" 2>&1)
check "C3 --help lists lepton without default mark" "grep -qE '^    lepton  ' <<<\"\$OUT\" && ! grep -qE '^  \\* lepton' <<<\"\$OUT\""
check "C4 installed() by setpgid stand-in; comp_short in menu; owned paths list stand-ins" \
  "grep -q '^  lepton)     \\[ -e \"\$LEP_BIN/setpgid\" \\];;' '$INST' && grep -q '^  lepton)     echo \"Lepton host tools' '$CFG' && grep -qF '    /usr/local/lib/steam-arm-lepton/bin/setpgid /usr/local/lib/steam-arm-lepton/bin/steamvr' '$CFG'"

# package record and purge on a fake package state
mkdir -p "$T/bin" "$T/etc"
cat > "$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
# stand-in: -W -f=FMT [PKG] over $T/state (one installed package per line)
shift 2
if [ $# -gt 0 ]; then grep -qx "$1" "$T/state" && { echo "ii "; exit 0; }; exit 1; fi
sed 's/^/ii  /' "$T/state"
EOF
cat > "$T/bin/apt-get" <<'EOF'
#!/bin/sh
# stand-in: install adds packages and their deps ($T/deps "pkg dep..."); -s purge lists rdeps ($T/rdeps); purge removes
echo "apt-get $*" >> "$T/apt.log"
sim=0; act=""; pk=""
while [ $# -gt 0 ]; do case "$1" in -s) sim=1;; -y) ;; -o) shift;; install|purge) act=$1;; *) pk="$pk $1";; esac; shift; done
case "$act" in
  install) for p in $pk; do echo "$p"; awk -v p="$p" '$1 == p { for (i = 2; i <= NF; i++) print $i }' "$T/deps"; done >> "$T/state"
           sort -u -o "$T/state" "$T/state";;
  purge) if [ $sim = 1 ]; then for p in $pk; do echo "Purg $p [1.0]"; awk -v p="$p" '$1 == p { for (i = 2; i <= NF; i++) print "Purg " $i " [1.0]" }' "$T/rdeps"; done
         else for p in $pk; do grep -vx "$p" "$T/state" > "$T/s2"; mv "$T/s2" "$T/state"; done; fi;;
esac
EOF
chmod 755 "$T/bin/dpkg-query" "$T/bin/apt-get"
LIB=$T/lib.sh
{ echo 'warn(){ echo "WARN $*"; }; die(){ echo "DIE $*"; exit 1; }'
  awk '/^conf_get\(\)\{/{f=1} f{print} f && /^conf_del\(\)\{/{g=1} g && /^}$/{exit}' "$INST"
  awk '/^# lepton: host packages and SteamOS tool stand-ins/{f=1} f{print} f && /^lepton_dev_conf\(\)/{exit}' "$INST" \
    | sed -e "s#^LEP_DIR=.*#LEP_DIR=$T/lepdir#" -e "s#^LEP_GUEST=.*#LEP_GUEST=$T/guestos/android#" -e "s#/usr/share/guestos#$T/guestos#g" -e "s#^LEP_LAYER_JSON=.*#LEP_LAYER_JSON=$T/layer.json#"
} > "$LIB"
check "P0 extracted: conf helpers, package helpers, lepton_off, drop-in stub" "grep -q '^conf_del()' $LIB && grep -q '^lepton_pkgs_add()' $LIB && grep -q '^lepton_pkgs_purge()' $LIB && grep -q '^lepton_off()' $LIB && grep -q '^lepton_dev_conf()' $LIB && bash -n $LIB"
run(){ ( export T; PATH=$T/bin:$PATH; CONF=$T/etc/steam-arm.conf; . "$LIB"; eval "$1" ) 2>&1; }
printf 'attr\ngcc\njq\nlibc6\nlibc6-dev\n' > "$T/state"; printf 'podman conmon crun\nadb android-libbase\n' > "$T/deps"; : > "$T/rdeps"; : > "$T/etc/steam-arm.conf"
cp "$T/state" "$T/state.before"
OUT=$(run lepton_pkgs_add; cat "$T/apt.log"; echo "REC=$(sed -n 's/^LEPTON_PKGS_ADDED=//p' "$T/etc/steam-arm.conf")")
check "P1 install: apt-get gets only missing packages; record = every new package (deps too), not those already there" \
  "grep -qx 'apt-get install -y -o DPkg::Lock::Timeout=120 podman catatonit uidmap passt inotify-tools adb libvulkan-dev' <<<\"\$OUT\" && grep -qx 'REC=adb,android-libbase,catatonit,conmon,crun,inotify-tools,libvulkan-dev,passt,podman,uidmap' <<<\"\$OUT\""
rm -f "$T/apt.log"; OUT=$(run lepton_pkgs_add; cat "$T/apt.log" 2>/dev/null; echo "REC=$(sed -n 's/^LEPTON_PKGS_ADDED=//p' "$T/etc/steam-arm.conf")")
check "P2 second run, nothing missing: no apt-get call, record kept" "! grep -q '^apt-get' <<<\"\$OUT\" && grep -qx 'REC=adb,android-libbase,catatonit,conmon,crun,inotify-tools,libvulkan-dev,passt,podman,uidmap' <<<\"\$OUT\""
cp "$T/state" "$T/state.on"; cp "$T/etc/steam-arm.conf" "$T/conf.on"
echo "crun foo" > "$T/rdeps"; rm -f "$T/apt.log"
OUT=$(run lepton_pkgs_purge; echo "rc=$?"; cat "$T/apt.log"; echo "REC=$(sed -n 's/^LEPTON_PKGS_ADDED=//p' "$T/etc/steam-arm.conf")")
check "P3 purge would take another package: nothing purged, warning names it, record kept" \
  "grep -q '^WARN lepton: packages kept, purging them would also remove: foo' <<<\"\$OUT\" && grep -qx 'rc=1' <<<\"\$OUT\" && ! grep -q '^apt-get purge -y' <<<\"\$OUT\" && grep -q '^REC=adb,' <<<\"\$OUT\" && cmp -s '$T/state' '$T/state.on'"
: > "$T/rdeps"; rm -f "$T/apt.log"
OUT=$(run lepton_pkgs_purge; cat "$T/apt.log"; echo "KEY=$(grep -c '^LEPTON_PKGS_ADDED=' "$T/etc/steam-arm.conf")")
check "P4 purge: exactly the recorded set, packages from before stay, state equals before, record removed" \
  "grep -qx 'apt-get purge -y -o DPkg::Lock::Timeout=120 adb android-libbase catatonit conmon crun inotify-tools libvulkan-dev passt podman uidmap' <<<\"\$OUT\" && cmp -s '$T/state' '$T/state.before' && grep -qx 'KEY=0' <<<\"\$OUT\""
cp "$T/state.on" "$T/state"; cp "$T/conf.on" "$T/etc/steam-arm.conf"; echo libc6 >> "$T/state"; rm -f "$T/apt.log"
OUT=$(run 'HOSTPKGS="curl crun"; lepton_pkgs_purge'; cat "$T/apt.log")
check "P5 setup's own packages (HOSTPKGS) never purged" "grep -q '^apt-get purge -y' <<<\"\$OUT\" && ! grep -q '^apt-get purge -y.* crun' <<<\"\$OUT\" && grep -qx crun '$T/state'"
grep -vx podman "$T/state.on" > "$T/state"; cp "$T/conf.on" "$T/etc/steam-arm.conf"; rm -f "$T/apt.log"
OUT=$(run lepton_pkgs_purge; cat "$T/apt.log")
check "P6 recorded package removed meanwhile by hand: left out of purge" "grep -q '^apt-get purge -y' <<<\"\$OUT\" && ! grep -q ' podman' <<<\"\$OUT\""
: > "$T/etc/steam-arm.conf"; rm -f "$T/apt.log"
OUT=$(run lepton_pkgs_purge; echo "rc=$?"; cat "$T/apt.log" 2>/dev/null)
check "P7 nothing recorded: no apt-get call" "grep -qx 'rc=0' <<<\"\$OUT\" && ! grep -q '^apt-get' <<<\"\$OUT\""

# lepton_off: stand-ins, own guestos link only, overlay content kept
mkdir -p "$T/lepdir/bin" "$T/guestos" "$T/lepdir/guestos-android/vendor/vulkan_layers"; touch "$T/lepdir/bin/setpgid" "$T/lepdir/bin/steamvr"
touch "$T/lepdir/guestos-android/vendor/vulkan_layers/libVkLayer_fossilize.so" "$T/lepdir/vk-fossilize-passthrough.c" "$T/layer.json"
ln -s "$T/lepdir/guestos-android" "$T/guestos/android"
OUT=$(run lepton_off; ls -A "$T/lepdir" "$T" 2>&1)
check "O1 off: stand-ins, layer, its source and manifest, own link gone, empty folders removed" "[ ! -e '$T/lepdir' ] && [ ! -e '$T/guestos' ] && [ ! -e '$T/layer.json' ]"
mkdir -p "$T/lepdir/bin" "$T/lepdir/guestos-android" "$T/guestos"; touch "$T/lepdir/bin/setpgid" "$T/lepdir/guestos-android/x.so"
ln -s /elsewhere "$T/guestos/android"
OUT=$(run lepton_off)
check "O2 off: foreign guestos link and overlay files kept, named" "[ -L '$T/guestos/android' ] && [ -f '$T/lepdir/guestos-android/x.so' ] && [ ! -e '$T/lepdir/bin' ] && grep -q \"kept: $T/lepdir\" <<<\"\$OUT\""
OUT=$(run 'lepton_dev_conf /dev/dri/renderD130')
check "D1 drop-in stub: render node passed as device, not applied by setup; node from gpu_detect (best rank), not fixed" \
  "[ \"\$OUT\" = \$'[containers]\ndevices = [\"/dev/dri/renderD130:/dev/dri/renderD130:rwm\"]' ] && [ \$(grep -c 'lepton_dev_conf' '$INST') = 1 ] && grep -qF 'best=\$rank; GPU_DETECTED=\$fam; GPU_NODE=/dev/dri/\$node' '$INST' && ! grep -q 'renderD1[0-9][0-9]' <(awk '/^# lepton: host packages/,/^lepton_dev_conf/' '$INST')"

# setup block and removal order
check "S1 setup: part on installs, writes stand-ins, links overlay only when free, clears group write as game user; off runs lepton_off" \
  "awk '/^if opt lepton; then\$/{f=1} f' '$INST' | head -260 > '$T/blk' && grep -q '^lepton_pkgs_add\$' '$T/blk' && grep -qF 'cat > \"\$LEP_BIN/setpgid\" <<'\"'\"'LEPSETPGID'\"'\"'' '$T/blk' && grep -qF '[ ! -e \"\$LEP_GUEST\" ] && [ ! -L \"\$LEP_GUEST\" ]' '$T/blk' && grep -qF 'as_user chmod -R g-w \"\$S/steamapps/common/Lepton\"' '$T/blk' && grep -A1 -x 'else' '$T/blk' | grep -qx 'lepton_off'"
a=$(grep -n '^remove_all(){' "$INST" | cut -d: -f1)
lo=$(awk -v a="$a" 'NR > a && /lepton_off; fi$/ { print NR; exit }' "$INST"); rm_=$(awk -v a="$a" 'NR > a && /rm -rf \/usr\/local\/share\/steam-arm \/etc\/steam-arm/ { print NR; exit }' "$INST")
check "R1 removal runs lepton_off before settings folder (holds the record) goes" "[ -n '$lo' ] && [ -n '$rm_' ] && [ '$lo' -lt '$rm_' ]"

# fossilize stand-in layer: built as at setup (cross compiler when the host is not arm64), Android ABI, no libc
C=$T/layer.c; awk "/^cat > \"\\\$LEP_LAYER_C\" <<'CEOF'\$/{f=1;next} f && /^CEOF\$/{exit} f" "$INST" > "$C"
FL=$(awk '/^if gcc -O2 -fPIC -shared -nostdlib/{f=1} f{print} f && /-o "\$LEP_LAYER" "\$LEP_LAYER_C"; then$/{exit}' "$INST" | tr -d '\\\n' | sed -e 's/^if gcc //' -e 's/ -o "\$LEP_LAYER" "\$LEP_LAYER_C"; then$//')
CC=gcc; [ "$(uname -m)" = aarch64 ] || CC=aarch64-linux-gnu-gcc
if command -v "$CC" >/dev/null && [ -f /usr/include/vulkan/vk_layer.h ]; then
  OUT=$(eval "$CC $FL -o '$T/layer.so' '$C'" 2>&1; LC_ALL=C readelf -W -hd --dyn-syms "$T/layer.so" 2>&1)
  check "Y1 layer builds with setup's flags: aarch64 shared object, no NEEDED libraries, soname, exports loader entry points" \
    "grep -q 'Machine: *AArch64' <<<\"\$OUT\" && grep -q 'DYN' <<<\"\$OUT\" && ! grep -q '(NEEDED)' <<<\"\$OUT\" && grep -q 'Library soname: \[libVkLayer_fossilize.so\]' <<<\"\$OUT\" && grep -q ' vkGetInstanceProcAddr\$' <<<\"\$OUT\" && grep -q ' vkGetDeviceProcAddr\$' <<<\"\$OUT\" && grep -q ' vkEnumerateInstanceLayerProperties\$' <<<\"\$OUT\""
else echo "SKIP Y1 layer build: $CC or Vulkan headers missing"; fi
OUT=$(awk '/^  cat > "\$LEP_LAYER_JSON" <<JSON$/{f=1;next} /^JSON$/{f=0} f' "$INST" | LEP_LAYER=/x/libVkLayer_fossilize.so envsubst 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin)["layer"]; print(d["name"], d["library_path"])')
check "Y2 manifest names VK_LAYER_fossilize with library path ending libVkLayer_fossilize.so (Lepton's id lookup)" "[ \"\$OUT\" = 'VK_LAYER_fossilize /x/libVkLayer_fossilize.so' ]"
check "Y3 setup builds layer into overlay, manifest only on success; compiler and headers in LEP_BUILD (recorded, purged with the part), not BUILDPKGS" \
  "grep -qF 'LEP_LAYER=\$LEP_OVERLAY/vendor/vulkan_layers/libVkLayer_fossilize.so' '$INST' && grep -qF 'rm -f \"\$LEP_LAYER\" \"\$LEP_LAYER_JSON\"; warn \"lepton: fossilize stand-in layer did not build' '$INST' && grep -qx 'LEP_BUILD=\"gcc libc6-dev libvulkan-dev\"' '$INST' && grep -qF 'for p in \$LEP_PKGS \$LEP_BUILD; do' '$INST' && ! grep -q 'opt lepton && BUILDPKGS' '$INST'"

# setpgid stand-in
P=$T/setpgid; awk "/^cat > \"\\\$LEP_BIN\\/setpgid\" <<'LEPSETPGID'\$/{f=1;next} /^LEPSETPGID\$/{f=0} f" "$INST" > "$P"; chmod 755 "$P"
check "G1 setpgid extracted (python3 -I, compiles)" "head -1 '$P' | grep -qx '#!/usr/bin/python3 -I' && python3 -m py_compile '$P' 2>/dev/null; python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' '$P'"
OUT=$(sh -c 'echo "parent $(ps -o pgid= -p $$)"; python3 -I '"$P"' sh -c '"'"'echo "child $$ $(ps -o pgid= -p $$)"'"'"'')
check "G2 own process group: child pgid = its pid, differs from parent group" "awk '/^parent/{p=\$2} /^child/{c=\$2; g=\$3} END { exit !(c == g && g != p) }' <<<\"\$OUT\""
OUT=$(setsid -w python3 -I "$P" --foreground sh -c 'echo "fg $$ $(ps -o pgid= -p $$)"' </dev/null 2>&1)
check "G3 --foreground without terminal: runs, own group" "awk '/^fg/{ exit !(\$2 == \$3) } END {}' <<<\"\$OUT\" && grep -q '^fg ' <<<\"\$OUT\""
OUT=$(python3 -I "$P" -- printf '[%s]' 'a b' '' c)
check "G4 arguments pass unchanged (spaces, empty, after --)" "[ \"\$OUT\" = '[a b][][c]' ]"
OUT=$(python3 -I "$P" 2>&1; echo "rc=$?"); OUT2=$(python3 -I "$P" /nonexistent/cmd 2>&1; echo "rc=$?")
check "G5 no command: usage, status 1; missing command: message, status 127" "grep -q '^usage: setpgid' <<<\"\$OUT\" && grep -qx 'rc=1' <<<\"\$OUT\" && grep -q '^setpgid: /nonexistent/cmd:' <<<\"\$OUT2\" && grep -qx 'rc=127' <<<\"\$OUT2\""
OUT=$(env -u GAMESCOPE_WAYLAND_DISPLAY WAYLAND_DISPLAY=wayland-0 python3 -I "$P" sh -c 'echo "g=${GAMESCOPE_WAYLAND_DISPLAY-unset}"'
      env GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 WAYLAND_DISPLAY=wayland-0 python3 -I "$P" sh -c 'echo "g=${GAMESCOPE_WAYLAND_DISPLAY-unset}"'
      env -u GAMESCOPE_WAYLAND_DISPLAY -u WAYLAND_DISPLAY python3 -I "$P" sh -c 'echo "g=${GAMESCOPE_WAYLAND_DISPLAY-unset}"')
check "G6 GAMESCOPE_WAYLAND_DISPLAY: unset takes WAYLAND_DISPLAY, set kept, no session socket stays unset" "[ \"\$OUT\" = \$'g=wayland-0\ng=gamescope-0\ng=unset' ]"
OUT=$(python3 -I "$P" sh -c 'grep "^SigIgn" /proc/$$/status')
check "G7 exec'd command starts with no signal ignored by Python (SIGPIPE, SIGXFSZ default)" "[ \$(( 0x\$(awk '{print \$2}' <<<\"\$OUT\") & 0x1000 | 0x\$(awk '{print \$2}' <<<\"\$OUT\") & 0x2000000 )) = 0 ]"

# steamvr stand-in
V=$T/steamvr; awk "/^cat > \"\\\$LEP_BIN\\/steamvr\" <<'LEPSTEAMVR'\$/{f=1;next} /^LEPSTEAMVR\$/{f=0} f" "$INST" > "$V"; chmod 755 "$V"
OUT=$(HOME=$T/h sh "$V" path; HOME=$T/h sh "$V" logpath; HOME=$T/h sh "$V" configpath)
B=$T/h/.local/share/steam-arm-lepton/steamvr
check "V1 path, logpath, configpath: folders under client home, created, runtime empty" "[ \"\$OUT\" = \"$B/runtime
$B/logs
$B/config\" ] && [ -d '$B/runtime' ] && [ -d '$B/logs' ] && [ -d '$B/config' ] && [ -z \"\$(ls -A '$B/runtime')\" ]"
OUT=$(HOME=$T/h sh "$V" bogus 2>&1; echo "rc=$?")
check "V2 other words: usage, status 2" "grep -q '^usage: steamvr path|logpath|configpath' <<<\"\$OUT\" && grep -qx 'rc=2' <<<\"\$OUT\""

# launcher: PATH and umask only with the part and its stand-in
L=$T/launcher.sh; awk '/^cat > \/usr\/local\/bin\/steam-arm <<.LAUNCHER.$/{f=1;next} /^LAUNCHER$/{f=0} f' "$INST" > "$L"
LB=$T/lb.sh; awk '/^# lepton \(component, off by default\): SteamOS tool stand-ins first in PATH/{f=1} f{print} f && /^fi$/{exit}' "$L" | sed "s#^LEPBIN=.*#LEPBIN=$T/lb#" > "$LB"
mkdir -p "$T/lb"; printf '#!/bin/sh\n' > "$T/lb/setpgid"; chmod 755 "$T/lb/setpgid"
lb(){ ( umask 0002; comp_on(){ [ -z "${COMPONENTS_ON+x}" ] && return 0; case ",$COMPONENTS_ON," in *",$1,"*) return 0;; esac; return 1; }
       llog(){ echo "LOG $*"; }; if [ "$1" = unset ]; then unset COMPONENTS_ON; else COMPONENTS_ON=$1; fi
       . "$LB"; echo "umask=$(umask) path1=${PATH%%:*}" ) 2>&1; }
OUT=$(lb "tray,lepton")
check "U1 part on: umask 022, stand-ins first in PATH, logged" "grep -qx 'umask=0022 path1=$T/lb' <<<\"\$OUT\" && grep -q '^LOG lepton: SteamOS tool stand-ins in PATH, umask 022' <<<\"\$OUT\""
OUT=$(lb "tray")
check "U2 part off: session umask and PATH unchanged" "grep -qx 'umask=0002 path1=${PATH%%:*}' <<<\"\$OUT\""
OUT=$(lb unset)
check "U3 no component list in settings: unchanged (part never counts as chosen)" "grep -qx 'umask=0002 path1=${PATH%%:*}' <<<\"\$OUT\""
chmod 644 "$T/lb/setpgid"; OUT=$(lb "tray,lepton"); chmod 755 "$T/lb/setpgid"
check "U4 stand-in missing or not executable: unchanged" "grep -qx 'umask=0002 path1=${PATH%%:*}' <<<\"\$OUT\""
check "U5 launcher sets GAMESCOPE_WAYLAND_DISPLAY nowhere (client env untouched; setpgid sets it for Lepton only)" "! grep -q 'GAMESCOPE_WAYLAND_DISPLAY' '$L'"

echo "test_lepton_31: $pass pass, $fail fail"
[ "$fail" = 0 ]
