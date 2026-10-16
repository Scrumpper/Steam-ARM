#!/bin/bash
# 2.2 FEX package source on Debian / Raspberry Pi OS: os_ubuntu, debian_major, fex_series, fex_source_debian,
# setup block and --remove lines, extracted from the installer; /etc paths in a fake tree, stub curl/apt-get/getconf.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
OLD=${SARM_INST21:-$(sarm_old 2.1)}
[ -n "$OLD" ] || { echo "SKIP suite compares with 2.1 release: not available (run through run-all.sh)"; exit 0; }
KEYFIX=$(cd "$(dirname "$0")" && pwd)/fixtures/fex-ppa-key.asc
T=$(mktemp -d /tmp/sarm232-debsrc.XXXXXX); trap 'rm -rf "$T"' EXIT
F=$T/fake; S=$T/stub; mkdir -p "$S"
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -4; fail=$((fail + 1)); fi; }

# functions (constants .. fex_source_debian), setup block, remove lines; /etc pointed at fake tree
{ echo 'say(){ printf "==> %s\n" "$*"; }; warn(){ printf "[warn] %s\n" "$*"; }; die(){ printf "[fail] %s\n" "$*"; exit 1; }'
  echo 'CLEANUP=(); NETHINT="(nethint)"'
  awk '/^FEXPPA="ppa:fex-emu\/fex"$/{f=1} f{print} f&&/^fex_source_debian\(\)\{/{g=1} g&&/^}$/{exit}' "$INST"
  echo 'run_block(){'
  awk '/^if ! command -v FEX >\/dev\/null 2>&1 && ! os_ubuntu; then$/{f=1} f{print} f&&/^fi$/{exit}' "$INST"
  echo '}'
  echo 'remove_lines(){ local pkgs=$1'
  awk '/^  # Debian FEX source from setup:/{f=1} f{print} f&&/^  fi$/{exit}' "$INST" | sed 's/^  local fexsrc=0/  fexsrc=0/'
  awk '/^  if \[ -n "\$pkgs" \]; then$/{f=1} f{print} f&&/^  fi$/{exit}' "$INST"
  awk '/^  \[ "\$fexsrc" = 2 \] && echo/' "$INST"
  echo '}'
} | sed -e "s#/etc/#$F/etc/#g" > "$T/funcs.sh"
check "extract: functions, block, remove lines" "grep -q '^fex_source_debian()' $T/funcs.sh && grep -q 'fex_source_debian\$' $T/funcs.sh && grep -q 'fexsrc=2' $T/funcs.sh && grep -q 'Removed:   FEX package source' $T/funcs.sh"
check "installer: bash -n" "bash -n '$INST'"
# Ubuntu branch: same lines as 2.1
awk '/^if ! command -v FEX >\/dev\/null 2>&1; then$/{f=1;next} f&&/^fi$/{exit} f' "$OLD" > "$T/u21"
# 3.0 adds the record of add-apt-repository's cache folder (LPL lines); rest as in 2.1
awk '/^elif ! command -v FEX >\/dev\/null 2>&1; then$/{f=1;next} f&&/^fi$/{exit} f' "$INST" | grep -v -e LPL -e "add-apt-repository's cache folder" > "$T/u22"
check "Ubuntu branch identical to 2.1 (cache folder record aside)" "[ -s $T/u21 ] && cmp -s $T/u21 $T/u22"
check "pinned fingerprint = Launchpad signing_key_fingerprint" "grep -qx 'FEXPPA_FPR=EDB98BFE8A2310DC9C4A376E76DBFEBEA206F5AC' '$INST'"
check "functions defined outside embedded settings menu" "[ \$(grep -c '^fex_source_debian()' '$INST') = 1 ] && ! awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1} /^STEAMARMCONFIG\$/{f=0} f' '$INST' | grep -q fex_source_debian"

# stubs: curl serves key fixture (CURL_FAIL=1 fails, CURL_KEY=file other key); apt-get, add-apt-repository log; getconf glibc
cat > "$S/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$LOGF"; [ "${CURL_FAIL:-0}" = 1 ] && exit 22
o=; while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done; cp "${CURL_KEY:-$KEYFIX}" "$o"
EOF
printf '#!/bin/sh\necho "apt-get $*" >> "$LOGF"\n' > "$S/apt-get"
printf '#!/bin/sh\necho "add-apt-repository $*" >> "$LOGF"\n' > "$S/add-apt-repository"
printf '#!/bin/sh\n[ "$1" = GNU_LIBC_VERSION ] && { echo "glibc $GLIBC"; exit 0; }\nexec /usr/bin/getconf "$@"\n' > "$S/getconf"
chmod 755 "$S"/*
export PATH="$S:$PATH" LOGF=$T/log KEYFIX
SRCF=$F/etc/apt/sources.list.d/steam-arm-fex.sources; KEYF=$F/etc/apt/keyrings/steam-arm-fex.gpg
# reset <os-release text> [debian_version] [glibc]
reset(){ rm -rf "$F"; mkdir -p "$F/etc/apt/sources.list.d"; printf '%s\n' "$1" > "$F/etc/os-release"
  [ -n "${2:-}" ] && echo "$2" > "$F/etc/debian_version"; export GLIBC=${3:-2.41}; : > "$LOGF"; unset CURL_FAIL CURL_KEY; }
run(){ OUT=$(bash -c ". $T/funcs.sh; $1" 2>&1); RC=$?; }
fpr(){ gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}'; }
OS_U='PRETTY_NAME="Ubuntu 26.04 LTS"
ID=ubuntu
ID_LIKE=debian
VERSION_ID="26.04"
VERSION_CODENAME=resolute'
OS_MINT='PRETTY_NAME="Linux Mint 22"
ID=linuxmint
ID_LIKE="ubuntu debian"
VERSION_CODENAME=wilma'
OS_D12='PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
VERSION_CODENAME=bookworm
ID=debian'
OS_D13='PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
NAME="Debian GNU/Linux"
VERSION_ID="13"
VERSION_CODENAME=trixie
ID=debian'
OS_D11='PRETTY_NAME="Debian GNU/Linux 11 (bullseye)"
VERSION_ID="11"
VERSION_CODENAME=bullseye
ID=debian'
# Raspberry Pi OS (64-bit) os-release: ID=debian, no ID_LIKE
OS_PIOS=$OS_D13
OS_RASPBIAN='PRETTY_NAME="Raspbian GNU/Linux 12 (bookworm)"
VERSION_ID="12"
VERSION_CODENAME=bookworm
ID=raspbian
ID_LIKE=debian'
OS_SID='PRETTY_NAME="Debian GNU/Linux forky/sid"
VERSION_CODENAME=forky
ID=debian'
OS_UNK='PRETTY_NAME="Some OS"
ID=someos'

# --- detection
reset "$OS_U"; run 'os_ubuntu && echo U'; check "Ubuntu: os_ubuntu" "[ \"\$OUT\" = U ]"
reset "$OS_MINT"; run 'os_ubuntu && echo U'; check "Ubuntu derivative (ID_LIKE ubuntu): os_ubuntu" "[ \"\$OUT\" = U ]"
reset "$OS_D12" 12.11 2.36; run 'os_ubuntu || echo "$(debian_major) $(fex_series)"'; check "Debian 12: jammy" "[ \"\$OUT\" = '12 jammy' ]"
reset "$OS_D13" 13.1 2.41; run 'os_ubuntu || echo "$(debian_major) $(fex_series)"'; check "Debian 13: noble" "[ \"\$OUT\" = '13 noble' ]"
reset "$OS_PIOS" 13.1 2.41; run 'os_ubuntu || echo "$(debian_major) $(fex_series)"'; check "Raspberry Pi OS (ID=debian, no ID_LIKE): noble" "[ \"\$OUT\" = '13 noble' ]"
reset "$OS_RASPBIAN" 12.4 2.36; run 'os_ubuntu || echo "$(debian_major) $(fex_series)"'; check "Raspbian (ID_LIKE=debian): 12 from debian_version, jammy" "[ \"\$OUT\" = '12 jammy' ]"
reset "$OS_SID" forky/sid 2.42; run 'echo "[$(debian_major)] $(fex_series)"'; check "Debian testing/sid: noble" "[ \"\$OUT\" = '[] noble' ]"
reset "$OS_D11" 11.9 2.31; run 'fex_series || echo none'; check "Debian 11: no series" "[ \"\$OUT\" = none ]"
reset "$OS_UNK" "" 2.31; run 'os_ubuntu || fex_series || echo none'; check "unknown system, glibc 2.31: no series" "[ \"\$OUT\" = none ]"
reset "$OS_D13" 13.1 2.33; run 'fex_series || echo none'; check "Debian 13 claimed, glibc 2.33: no series" "[ \"\$OUT\" = none ]"

# --- source written
reset "$OS_D13" 13.1 2.41; run run_block
check "Debian 13: block rc 0, source + keyring" "[ $RC = 0 ] && [ -f $SRCF ] && [ -f $KEYF ]"
check "Debian 13: deb822 fields" "grep -qx 'URIs: https://ppa.launchpadcontent.net/fex-emu/fex/ubuntu' $SRCF && grep -qx 'Suites: noble' $SRCF && grep -qx 'Components: main' $SRCF && grep -qx 'Architectures: arm64' $SRCF && grep -qx \"Signed-By: $KEYF\" $SRCF"
check "Debian 13: keyring binary, pinned fingerprint" "! grep -q 'BEGIN PGP' $KEYF && [ \"\$(fpr $KEYF)\" = EDB98BFE8A2310DC9C4A376E76DBFEBEA206F5AC ]"
check "Debian 13: key from keyserver.ubuntu.com by fingerprint, https only" "grep -q 'keyserver.ubuntu.com/pks/lookup?op=get&search=0xEDB98BFE8A2310DC9C4A376E76DBFEBEA206F5AC' $LOGF && grep -q 'proto =https' $LOGF"
check "Debian 13: no add-apt-repository, no software-properties-common" "! grep -q -e add-apt-repository -e software-properties $LOGF"
check "Debian 13: modes 0644" "[ \$(stat -c %a $SRCF) = 644 ] && [ \$(stat -c %a $KEYF) = 644 ]"
reset "$OS_D12" 12.11 2.36; run run_block; check "Debian 12: Suites jammy" "[ $RC = 0 ] && grep -qx 'Suites: jammy' $SRCF"
reset "$OS_PIOS" 13.1 2.41; run run_block; check "Raspberry Pi OS: Suites noble" "[ $RC = 0 ] && grep -qx 'Suites: noble' $SRCF"
reset "$OS_D13" 13.1 2.41; run 'run_block; run_block'
check "second run: one source, one curl" "[ $RC = 0 ] && [ \$(grep -rl fex-emu/fex $F/etc/apt/sources.list.d | wc -l) = 1 ] && [ \$(grep -c '^curl' $LOGF) = 1 ]"

# --- Ubuntu path unchanged
reset "$OS_U"; run run_block
check "Ubuntu: add-apt-repository -y ppa:fex-emu/fex, no deb822 file" "[ $RC = 0 ] && grep -qx 'add-apt-repository -y ppa:fex-emu/fex' $LOGF && [ ! -e $SRCF ] && ! grep -q '^curl' $LOGF"
reset "$OS_U"; echo 'deb https://ppa.launchpadcontent.net/fex-emu/fex/ubuntu/ resolute main' > "$F/etc/apt/sources.list.d/fex-emu-ubuntu-fex-resolute.list"
# Ubuntu grep (path rewritten to fake tree): source present, no call
run run_block; check "Ubuntu: existing PPA source, no add-apt-repository" "[ $RC = 0 ] && ! grep -q add-apt-repository $LOGF"

# --- existing sources on Debian
reset "$OS_D13" 13.1 2.41; printf 'Types: deb\nURIs: https://ppa.launchpadcontent.net/fex-emu/fex/ubuntu\nSuites: noble\nComponents: main\n' > "$F/etc/apt/sources.list.d/fex.sources"
run run_block; check "existing hand-made fex source: kept, nothing added" "[ $RC = 0 ] && [ ! -e $SRCF ] && [ -f $F/etc/apt/sources.list.d/fex.sources ] && ! grep -q '^curl' $LOGF"
reset "$OS_D13" 13.1 2.41; echo 'deb https://ppa.launchpadcontent.net/fex-emu/fex/ubuntu noble main' > "$F/etc/apt/sources.list"
run run_block; check "fex line in sources.list: nothing added" "[ $RC = 0 ] && [ ! -e $SRCF ]"
reset "$OS_D13" 13.1 2.41; echo 'deb http://ppa.launchpad.net/fex-emu/fex/ubuntu trixie main' > "$F/etc/apt/sources.list.d/fex-emu-ubuntu-fex-trixie.list"
run run_block; check "fex source naming trixie: renamed .disabled, new source written" "[ $RC = 0 ] && [ -f $F/etc/apt/sources.list.d/fex-emu-ubuntu-fex-trixie.list.disabled ] && [ ! -e $F/etc/apt/sources.list.d/fex-emu-ubuntu-fex-trixie.list ] && grep -qx 'Suites: noble' $SRCF && grep -q 'renamed to' <<<\"\$OUT\""
reset "$OS_D13" 13.1 2.41; echo 'deb https://example.org/other trixie main' > "$F/etc/apt/sources.list.d/other.list"
run run_block; check "unrelated source naming trixie: untouched" "[ $RC = 0 ] && [ -f $F/etc/apt/sources.list.d/other.list ] && [ -f $SRCF ]"

# --- failures write nothing
reset "$OS_D11" 11.9 2.31; run run_block
check "Debian 11: stops, names Debian 13, nothing written" "[ $RC = 1 ] && grep -q 'Debian 13 or newer' <<<\"\$OUT\" && ! grep -q InstallFEX.py <<<\"\$OUT\" && [ ! -e $SRCF ] && [ ! -e $KEYF ] && ! grep -q '^curl' $LOGF"
reset "$OS_UNK" "" 2.31; run run_block; check "unknown system: stops, names system" "[ $RC = 1 ] && grep -q 'Some OS, glibc 2.31' <<<\"\$OUT\" && [ ! -e $SRCF ]"
reset "$OS_D13" 13.1 2.41; export CURL_FAIL=1; run run_block
check "key download fails: stops, nothing written" "[ $RC = 1 ] && grep -q 'signing key download failed' <<<\"\$OUT\" && [ ! -e $SRCF ] && [ ! -e $KEYF ]"
G=$T/gpgh; mkdir -m 700 "$G"
GNUPGHOME=$G gpg --batch --passphrase '' --quick-gen-key 'wrong <w@example.org>' ed25519 sign never >/dev/null 2>&1
GNUPGHOME=$G gpg --batch --armor --export > "$T/wrong.asc"
reset "$OS_D13" 13.1 2.41; export CURL_KEY=$T/wrong.asc; run run_block
check "wrong key fingerprint: stops, nothing written" "[ -s $T/wrong.asc ] && [ $RC = 1 ] && grep -q 'wrong fingerprint' <<<\"\$OUT\" && [ ! -e $SRCF ] && [ ! -e $KEYF ]"
cat "$KEYFIX" "$T/wrong.asc" > "$T/two.asc"
reset "$OS_D13" 13.1 2.41; export CURL_KEY=$T/two.asc; run run_block
check "extra key in download: stops, nothing written" "[ $RC = 1 ] && [ ! -e $SRCF ] && [ ! -e $KEYF ]"
reset "$OS_D13" 13.1 2.41; printf '#!/bin/sh\necho fake\n' > "$S/FEX"; chmod 755 "$S/FEX"; run run_block; rm -f "$S/FEX"
check "FEX already installed: no source step" "[ $RC = 0 ] && [ ! -e $SRCF ] && [ ! -s $LOGF ]"

# --- removal
reset "$OS_D13" 13.1 2.41; run run_block
run 'remove_lines "fex-emu-armv8.2 zenity "'
check "remove, FEX installed: source kept, hint names file + keyring" "[ -f $SRCF ] && [ -f $KEYF ] && grep -q \"FEX package source:  sudo rm $SRCF $KEYF\" <<<\"\$OUT\" && ! grep -q add-apt-repository <<<\"\$OUT\""
run 'remove_lines "zenity "'
check "remove, no FEX build installed: source + keyring deleted, reported" "[ ! -e $SRCF ] && [ ! -e $KEYF ] && grep -q 'Removed:   FEX package source' <<<\"\$OUT\""
reset "$OS_U"; run 'remove_lines "fex-emu-armv8.2 "'
check "remove on Ubuntu: add-apt-repository --remove hint as in 2.1" "grep -q 'FEX package source:  sudo add-apt-repository --remove ppa:fex-emu/fex' <<<\"\$OUT\""
reset "$OS_D13" 13.1 2.41; run 'remove_lines "fex-emu-armv8.2 "'
check "remove on Debian without setup's source: no PPA hint" "! grep -q 'FEX package source' <<<\"\$OUT\""

echo "test_debian_source: $pass passed, $fail failed"
[ "$fail" = 0 ]
