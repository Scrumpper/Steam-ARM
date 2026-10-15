#!/bin/bash
# 2.3 driver archive source: precedence (env, saved custom, saved local, beside installer, download), soft fallback to
# download, saved PROVIDER_LOCAL_FILE, --provider-default clear, --detect line, arg checks, recipe /dev/fd fix.
# Blocks extracted from the installer copy in ~/.cache/sarm<NN>-work (paths.sh); settings file, trees and curl point at a temp tree.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
CFG=${SARM_CFG:-$(dirname "$INST")/steam-arm-config}
RECIPE=${SARM_RECIPE:-$(dirname "$INST")/tools/build-driver-archive.sh}
T=$(mktemp -d /tmp/sarm232-da.XXXXXX); trap 'rm -rf "$T"' EXIT
S=$T/stub; mkdir -p "$S"
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; sed 's/^/     /' <<<"$OUT" | tail -8; fail=$((fail + 1)); fi; }
block(){ A=$1 B=$2 awk '!f && $0 ~ ENVIRON["A"] {f=1; print; next} f {print} f && $0 ~ ENVIRON["B"] {exit}' "${3:-$INST}"; }
upto(){ A=$1 B=$2 awk '$0 ~ ENVIRON["A"] {f=1} f && $0 ~ ENVIRON["B"] {exit} f {print}' "${3:-$INST}"; }

check "installer: bash -n" "bash -n '$INST'"
check "settings menu: bash -n" "bash -n '$CFG'"
check "embedded settings menu identical" "awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f' '$INST' | cmp -s - '$CFG'"

# ---------- fixtures: tiny published archive, other archive, fake RootFS ----------
mkdir -p "$T/fx/usr/lib/x86_64-linux-gnu" "$T/fy/usr/lib/x86_64-linux-gnu" "$T/rfs/usr/lib/x86_64-linux-gnu" "$T/rfs/var/lib/dpkg/info"
echo '{"file_format_version":"1.0.0"}' > "$T/fx/graphics_provider.json"; echo pub > "$T/fx/usr/lib/x86_64-linux-gnu/libgallium-26.so"
cp "$T/fx/graphics_provider.json" "$T/fy/"; echo other > "$T/fy/usr/lib/x86_64-linux-gnu/libgallium-26.so"
echo base > "$T/rfs/usr/lib/x86_64-linux-gnu/libbase.so.1"
PF=steam-arm-fex-mesa-test-x86_64-i386.tar.zst
tar --zstd -cf "$T/pub.tar.zst" -C "$T/fx" . && tar --zstd -cf "$T/other.tar.zst" -C "$T/fy" .
PUBSHA=$(sha256sum "$T/pub.tar.zst" | cut -c1-64)
# curl stub: CURL_OK=1 writes published fixture to -o file; every call logged
cat > "$S/curl" <<'EOF'
#!/bin/bash
o=""; u=""; while [ $# -gt 0 ]; do case $1 in -o) o=$2; shift;; https://*) u=$1;; esac; shift; done
echo "curl $u" >> "$LOGF"
if [ "${CURL_OK:-0}" = 1 ]; then cp "$PUBARC" "$o"; printf 200; exit 0; fi
printf "${CURL_CODE:-000}"; exit 7
EOF
chmod 755 "$S/curl"
export LOGF=$T/log PUBARC=$T/pub.tar.zst

# ---------- extraction ----------
{ echo 'warn(){ printf "[warn] %s\n" "$*"; }; die(){ printf "[fail] %s\n" "$*"; exit 1; }'
  echo "CONF=$T/conf; RFS=$T/rfs; MALI=$T/opt/mali; MALI_MARK=\$MALI/.steam-arm-mali; PROVIDER_MESA_PKGS=none"
  echo "PROVIDER_URL=https://example.invalid/r/$PF; PROVIDER_SHA256=$PUBSHA"
  echo 'PROVIDER_FILE=${PROVIDER_URL##*/}; PROVIDER_FALLBACK=https://example.invalid/latest/$PROVIDER_FILE'
  echo 'PROVIDER_DEFAULT=${PD:-0}; SELF_DIR=${BESIDE:-}; CLEANUP=(); CURL_ENV=(); CURL_SHOW=(); NETHINT="(nethint)"'
  echo 'rfs_id(){ echo rid; }; rfs_guard(){ return 0; }; steam_up(){ return 1; }'
  upto '^conf_get\(\)' '^# GAMEUSER: env'
  block '^unlink_in\(\)' '^}$'
  block '^paths_inside\(\)' '^}$'
  block '^parent_in\(\)' '^}$'
  upto '^# Driver archive in use' '^# Delete the second graphics tree'
  echo 'pd_clear(){'
  block '^if \[ "\$PROVIDER_DEFAULT" = 1 \] && grep -qs .\^PROVIDER_' '^fi$'
  echo '}'
  echo 'argchk(){ MODE=keep; HELP=0'
  upto '^# Custom driver archive: only a local file' '^if \[ "\$PASS_STDIN" = 1 \]; then$'
  echo '}'
} > "$T/funcs.sh"
check "extract: provider functions and blocks" "bash -n $T/funcs.sh && grep -q '^provider_source()' $T/funcs.sh && grep -q '^mali_tree_build()' $T/funcs.sh && grep -q '^conf_del()' $T/funcs.sh && grep -q 'conf_del PROVIDER_CUSTOM_SHA256' $T/funcs.sh"

reset(){ rm -rf "$T/opt" "$T/bes"; mkdir -p "$T/opt" "$T/bes"; : > "$T/conf"; : > "$LOGF"; unset PD BESIDE CURL_OK STEAM_ARM_PROVIDER_TARBALL STEAM_ARM_PROVIDER_SHA256; }
run(){ OUT=$(PATH="$S:/usr/bin:/bin" bash -c ". $T/funcs.sh; $1" 2>&1); RC=$?; }
src(){ run "provider_source; echo \"K=\$PSRC_KIND F=\$PSRC_FILE FROM=\${PSRC_FROM-unset} SOFT=\${PSRC_SOFT-unset} SAVED=\$PSRC_SAVED\""; }
key(){ sed -n "s/^$1=//p" "$T/conf"; }
CSHA=$(printf 'c%.0s' $(seq 64))

# ---------- T1 precedence ----------
reset; export STEAM_ARM_PROVIDER_TARBALL=$T/other.tar.zst STEAM_ARM_PROVIDER_SHA256=$CSHA; echo "PROVIDER_LOCAL_FILE=$T/pub.tar.zst" > "$T/conf"; src
check "T1 env SHA + TARBALL: custom, not local" "grep -q \"^K=custom F=$T/other.tar.zst FROM= \" <<<\"\$OUT\""
reset; printf 'PROVIDER_CUSTOM_SHA256=%s\nPROVIDER_CUSTOM_FILE=%s\nPROVIDER_LOCAL_FILE=%s\n' "$CSHA" "$T/other.tar.zst" "$T/pub.tar.zst" > "$T/conf"; src
check "T1 saved custom wins over saved local" "grep -q \"^K=custom F=$T/other.tar.zst .*SAVED=1\" <<<\"\$OUT\""
reset; export STEAM_ARM_PROVIDER_TARBALL=$T/pub.tar.zst; echo "PROVIDER_LOCAL_FILE=$T/x.tar.zst" > "$T/conf"; src
check "T1 env TARBALL: published, from env, not soft" "grep -qx \"K=published F=$T/pub.tar.zst FROM=env SOFT=0 SAVED=0\" <<<\"\$OUT\""
reset; echo "PROVIDER_LOCAL_FILE=$T/pub.tar.zst" > "$T/conf"; cp "$T/pub.tar.zst" "$T/bes/$PF"; export BESIDE=$T/bes; src
check "T1 saved local: from saved, soft, wins over beside" "grep -qx \"K=published F=$T/pub.tar.zst FROM=saved SOFT=1 SAVED=0\" <<<\"\$OUT\""
reset; echo "PROVIDER_LOCAL_FILE=$T/pub.tar.zst" > "$T/conf"; export PD=1; src
check "T1 --provider-default: saved local ignored, download" "grep -qx 'K=published F= FROM= SOFT=0 SAVED=0' <<<\"\$OUT\""
reset; cp "$T/pub.tar.zst" "$T/bes/$PF"; export BESIDE=$T/bes; src
check "T1 file beside installer: from beside, soft" "grep -qx \"K=published F=$T/bes/$PF FROM=beside SOFT=1 SAVED=0\" <<<\"\$OUT\""
reset; export BESIDE=$T/bes; src
check "T1 nothing set: download" "grep -qx 'K=published F= FROM= SOFT=0 SAVED=0' <<<\"\$OUT\""

# ---------- T2-T5 tree build ----------
reset; echo "PROVIDER_LOCAL_FILE=$T/gone.tar.zst" > "$T/conf"; export CURL_OK=1; run mali_tree_build
check "T2 saved local missing: note, download, tree built" "[ $RC = 0 ] && grep -q 'saved driver archive $T/gone.tar.zst not found; downloading published copy' <<<\"\$OUT\" && grep -q '^curl ' $LOGF && grep -qx 'archive $PUBSHA rootfs rid' $T/opt/mali/.steam-arm-mali"
check "T2 saved local missing: key kept" "[ \"\$(key PROVIDER_LOCAL_FILE)\" = $T/gone.tar.zst ]"
reset; echo "PROVIDER_LOCAL_FILE=$T/other.tar.zst" > "$T/conf"; export CURL_OK=1; run mali_tree_build
check "T3 saved local mismatch: note, download, file kept" "[ $RC = 0 ] && grep -q '$T/other.tar.zst does not match published archive; downloading published copy' <<<\"\$OUT\" && grep -q '^curl ' $LOGF && [ -f $T/other.tar.zst ]"
reset; cp "$T/other.tar.zst" "$T/bes/$PF"; export BESIDE=$T/bes CURL_OK=1; run mali_tree_build
check "T3 beside mismatch: note, download, not saved, file kept" "[ $RC = 0 ] && grep -q 'does not match published archive; downloading' <<<\"\$OUT\" && grep -q '^curl ' $LOGF && [ -z \"\$(key PROVIDER_LOCAL_FILE)\" ] && [ -f $T/bes/$PF ]"
reset; export STEAM_ARM_PROVIDER_TARBALL=$T/other.tar.zst CURL_OK=1; run mali_tree_build
check "T3 env TARBALL mismatch: stops, no download" "[ $RC != 0 ] && grep -q 'does not match the checksum this installer expects' <<<\"\$OUT\" && [ ! -s $LOGF ]"
reset; cp "$T/pub.tar.zst" "$T/bes/$PF"; export BESIDE=$T/bes; run mali_tree_build
check "T4 beside match: no download, local copy line, tree built" "[ $RC = 0 ] && [ ! -s $LOGF ] && grep -q 'local copy of driver archive: $T/bes/$PF (checksum matches; no download)' <<<\"\$OUT\" && [ -f $T/opt/mali/graphics_provider.json ]"
check "T4 beside match: path saved" "[ \"\$(key PROVIDER_LOCAL_FILE)\" = $T/bes/$PF ]"
reset; ln -s "$T/pub.tar.zst" "$T/bes/link.tar.zst"; export STEAM_ARM_PROVIDER_TARBALL=$T/bes/link.tar.zst; run mali_tree_build
check "T5 env TARBALL success: resolved path saved" "[ $RC = 0 ] && [ ! -s $LOGF ] && [ \"\$(key PROVIDER_LOCAL_FILE)\" = $T/pub.tar.zst ]"
check "T5b env TARBALL (menu Local copy): log line names local copy, no download (box bug 17)" "grep -q 'local copy of driver archive: .*tar.zst (no download)' <<<\"\$OUT\""
: > "$T/conf"; run mali_tree_build
check "T5 env TARBALL, tree already in place: path saved" "[ $RC = 0 ] && grep -q 'already in place' <<<\"\$OUT\" && [ \"\$(key PROVIDER_LOCAL_FILE)\" = $T/pub.tar.zst ]"
check "T5c env TARBALL, tree already in place: local copy line names file (box re-test B2)" "grep -q 'local copy of driver archive: .*\\.tar\\.zst saved for later runs (Mali tree already built from this archive; no download)' <<<\"\$OUT\""
reset; mkdir -p "$T/sp ace"; cp "$T/pub.tar.zst" "$T/sp ace/a.tar.zst"; export STEAM_ARM_PROVIDER_TARBALL="$T/sp ace/a.tar.zst"; run mali_tree_build
check "T5 spaced path: used for run, not saved, note" "[ $RC = 0 ] && [ -f $T/opt/mali/graphics_provider.json ] && grep -q 'driver archive path not saved' <<<\"\$OUT\" && [ -z \"\$(key PROVIDER_LOCAL_FILE)\" ]"
reset; echo "PROVIDER_LOCAL_FILE=$T/pub.tar.zst" > "$T/conf"; run mali_tree_build
check "T5 saved local match: no download, tree built" "[ $RC = 0 ] && [ ! -s $LOGF ] && grep -q 'local copy of driver archive' <<<\"\$OUT\""
reset; run mali_tree_build
check "download failure names menu path and beside option" "[ $RC != 0 ] && grep -q 'Components, Driver archive, Local copy; or place $PF beside steam-arm-install.sh' <<<\"\$OUT\""

# ---------- T6 --provider-default clear ----------
reset; printf 'GFX_DEFAULT=auto\nPROVIDER_LOCAL_FILE=%s\n' "$T/pub.tar.zst" > "$T/conf"; export PD=1; run pd_clear
check "T6 --provider-default clears saved local path" "[ -z \"\$(key PROVIDER_LOCAL_FILE)\" ] && grep -qx GFX_DEFAULT=auto $T/conf && grep -q 'driver archive settings cleared' <<<\"\$OUT\""
reset; printf 'PROVIDER_CUSTOM_SHA256=%s\nPROVIDER_CUSTOM_FILE=/x\nPROVIDER_LOCAL_FILE=/y\n' "$CSHA" > "$T/conf"; export PD=1; run pd_clear
check "T6 --provider-default clears custom and local keys" "! grep -q '^PROVIDER_' $T/conf"
reset; export PD=1 CURL_CODE=404; echo "PROVIDER_LOCAL_FILE=/y" > "$T/conf"; run "provider_download $T/dl"; unset CURL_CODE
check "T6 404 hint keeps --provider-default with saved local key, names menu path" "grep -q 'bash steam-arm-install.sh --keep --provider-default' <<<\"\$OUT\" && grep -q 'Driver archive, Local copy' <<<\"\$OUT\""

# ---------- T9 local copy of published archive picked over saved custom (menu passes --provider-default) ----------
reset; printf 'PROVIDER_CUSTOM_SHA256=%s\nPROVIDER_CUSTOM_FILE=%s\n' "$CSHA" "$T/other.tar.zst" > "$T/conf"; export STEAM_ARM_PROVIDER_TARBALL=$T/pub.tar.zst PD=1; src
check "T9 saved custom + TARBALL + --provider-default: published, from env" "grep -qx \"K=published F=$T/pub.tar.zst FROM=env SOFT=0 SAVED=0\" <<<\"\$OUT\""
mkdir -p "$T/opt/mali"; echo '{}' > "$T/opt/mali/graphics_provider.json"; echo "custom $CSHA rootfs rid" > "$T/opt/mali/.steam-arm-mali"
run "opt(){ return 0; }; mali_tree_build && pd_clear"
check "T9 custom tree rebuilt from local file (no download); custom keys gone, local path saved" "[ $RC = 0 ] && [ ! -s $LOGF ] && grep -qx 'archive $PUBSHA rootfs rid' $T/opt/mali/.steam-arm-mali && [ -z \"\$(key PROVIDER_CUSTOM_SHA256)\" ] && [ \"\$(key PROVIDER_LOCAL_FILE)\" = $T/pub.tar.zst ] && grep -q 'local copy of published archive from now on' <<<\"\$OUT\""
run "opt(){ return 0; }; mali_tree_build && pd_clear"
check "T9 second run, tree in place: local path still saved" "[ $RC = 0 ] && grep -q 'already in place' <<<\"\$OUT\" && [ \"\$(key PROVIDER_LOCAL_FILE)\" = $T/pub.tar.zst ]"

# ---------- T7 --detect line ----------
{ echo 'COMPONENTS=""; var_of(){ echo X; }; kde_wayland(){ return 1; }; GPU_LINE=g; GPU_SRC=auto; GPU_FAMILY=f; GPU_DETECTED=f; GPU_NAME=n; GPU_DRV=d; GPU_VK=v; GPU_NOTE=""; GPU_WARN=""'
  grep -m1 '^PROVIDER_URL=' "$INST"; grep -m1 '^PROVIDER_SHA256=' "$INST"; echo 'PROVIDER_FILE=${PROVIDER_URL##*/}'
  block '^gpu_report\(\)' '^}$'; } > "$T/rep.sh"
OUT=$(bash -c ". $T/rep.sh; gpu_report" 2>&1)
REAL_FILE=$(sed -n 's#^PROVIDER_URL=.*/##p' "$INST" | head -1); REAL_SHA=$(sed -n 's/^PROVIDER_SHA256=//p' "$INST" | head -1)
check "T7 --detect prints driver archive: <file> <sha>" "grep -qx \"driver archive: $REAL_FILE $REAL_SHA\" <<<\"\$OUT\""
check "T7 driver archive line after vulkan, before components" "[ \"\$(grep -n '' <<<\"\$OUT\" | grep -E '^[0-9]+:(vulkan:|driver archive:|page size:)' | cut -d: -f2 | paste -sd,)\" = 'vulkan,driver archive,page size' ]"

# ---------- T8 arg checks ----------
reset; mkdir -p "$T/sp ace"; export STEAM_ARM_PROVIDER_TARBALL="$T/sp ace/a.tar.zst"; run 'argchk; echo passed'
check "T8 spaced env path without custom: accepted (2.2 behaviour)" "grep -qx passed <<<\"\$OUT\""
export STEAM_ARM_PROVIDER_SHA256=$CSHA; run 'argchk; echo passed'
check "T8 spaced env path with custom sha: stops" "! grep -qx passed <<<\"\$OUT\" && grep -q 'path may hold only letters' <<<\"\$OUT\""
unset STEAM_ARM_PROVIDER_SHA256 STEAM_ARM_PROVIDER_TARBALL

# ---------- SELF_DIR: regular file only ----------
upto '^# Folder of this script when it is a regular file' '^# --provider-default' > "$T/bes/selfdir.sh"; echo 'echo "SELF_DIR=$SELF_DIR"' >> "$T/bes/selfdir.sh"
OUT=$(bash "$T/bes/selfdir.sh" 2>&1)
check "SELF_DIR: script run from file -> its folder" "grep -qx 'SELF_DIR=$T/bes' <<<\"\$OUT\""
OUT=$(bash <(cat "$T/bes/selfdir.sh") 2>&1)
check "SELF_DIR: bash <(...) -> empty" "grep -qx 'SELF_DIR=' <<<\"\$OUT\""
OUT=$(cat "$T/bes/selfdir.sh" | bash 2>&1)
check "SELF_DIR: piped script -> empty" "grep -qx 'SELF_DIR=' <<<\"\$OUT\""

# ---------- help text ----------
OUT=$(sed -n '/^usage(){$/,/^}$/p' "$INST")
check "--help: TARBALL saved, beside file, menu path; --provider-default clears local" "grep -q 'saved for later' <<<\"\$OUT\" && grep -q 'beside this script' <<<\"\$OUT\" && grep -q 'Components, Driver' <<<\"\$OUT\" && grep -q 'clears saved local and custom' <<<\"\$OUT\""

# ---------- recipe: /dev/fd in build roots, verify loop not vacuous ----------
OUT=$(block "^inroot\\(\\)" '^}$' "$RECIPE")
check "recipe: inroot links /dev/fd after proc mount" "grep -A2 'mount -t proc proc' <<<\"\$OUT\" | grep -q 'ln -s /proc/self/fd \$R/dev/fd'"
awk "/^cat > \"\\\$R\\/inner\\/verify.sh\" <<'EOF'\$/{f=1;next} f && /^EOF\$/{exit} f" "$RECIPE" > "$T/verify.sh"
mkdir -p "$T/vs/stage/usr/lib/x86_64-linux-gnu"
if printf 'int m(void){return 0;}\n' > "$T/m.c" && printf 'int m(void); int g(void){return m();}\n' > "$T/g.c" \
   && gcc -shared -fPIC -o "$T/libsarmmissing.so" "$T/m.c" 2>/dev/null \
   && gcc -shared -fPIC -o "$T/vs/stage/usr/lib/x86_64-linux-gnu/libgood.so.1" "$T/g.c" -L"$T" -lsarmmissing 2>/dev/null; then
  rm -f "$T/libsarmmissing.so"
  sed -i "s#^S=/work/stage#S=$T/vs/stage#" "$T/verify.sh"
  OUT=$(GALLIUM=none bash "$T/verify.sh" x86_64 2>&1)
  check "recipe verify: unresolved NEEDED -> FAIL" "grep -q '^FAIL x86_64: all NEEDED libraries resolve' <<<\"\$OUT\""
  sed 's#^done < <(find.*#done < /nonexistent/fd/63#' "$T/verify.sh" > "$T/verify2.sh"
  OUT=$(GALLIUM=none bash "$T/verify2.sh" x86_64 2>&1)
  check "recipe verify: unreadable file list -> FAIL, not vacuous PASS" "grep -q '^FAIL x86_64: libraries found to check (0)' <<<\"\$OUT\""
else
  echo "FAIL recipe verify: gcc fixture build"; fail=$((fail + 1))
fi

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
