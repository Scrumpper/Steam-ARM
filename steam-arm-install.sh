#!/bin/bash
# steam-arm-setup: installs Valve's native ARM64 Steam client (x86 client through FEX on CPUs without Armv8.1 atomics), with host packages, RootFS, launcher, optional components; run as root, then launch via steam-arm. See --help.
set -u
SA_VERSION=2.3.1
# Banner: self-contained (no board helper needed); TTY-gated, honours NO_COLOR.
steam_banner() {
    [ -t 1 ] || return 0
    local C=$'\033[96m' D=$'\033[2m' B=$'\033[1m' X=$'\033[0m'
    [ -n "${NO_COLOR:-}" ] && { C=; D=; B=; X=; }
    local line; line=$(printf '\u2500%.0s' $(seq 1 62))
    printf '\n%s  %s%s\n' "$D" "$line" "$X"
    printf '%s   %s%s\n' "${C}${B}" "$1" "$X"
    printf '%s   %s%s\n' "$D" "$2" "$X"
    [ -n "${3:-}" ] && printf '%s   %s%s\n' "$B" "$3" "$X"
    printf '%s  %s%s\n\n' "$D" "$line" "$X"
}

say(){ printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[fail]\033[0m %s\n' "$*"; [ -n "${DIE_NOTE:-}" ] && printf '       %s\n' "$DIE_NOTE"; exit 1; }
# First CPU's Features line (FEX build pick, client type).
cpu_features(){ grep -m1 '^Features' /proc/cpuinfo 2>/dev/null | cut -d: -f2; }
# Armv8.1 LSE atomics; empty Features line (container, odd kernel) counts as present.
cpu_lse(){ case " $(cpu_features) " in "  "|*" atomics "*) return 0;; esac; return 1; }
# Core types from "CPU part" lines, counted: "Cortex-A76 x4, Cortex-A55 x4"; empty when the kernel lists none.
cpu_label(){
  awk -F: '/^CPU part/ { p = $2; gsub(/[ \t]/, "", p); p = tolower(p); if (!(p in n)) o[++k] = p; n[p]++ }
    END { m = split("0xd03 Cortex-A53 0xd04 Cortex-A35 0xd05 Cortex-A55 0xd07 Cortex-A57 0xd08 Cortex-A72 0xd09 Cortex-A73 0xd0a Cortex-A75 0xd0b Cortex-A76 0xd0c Neoverse-N1 0xd0d Cortex-A77 0xd41 Cortex-A78 0xd44 Cortex-X1 0xd46 Cortex-A510 0xd47 Cortex-A710 0xd48 Cortex-X2 0xd49 Neoverse-N2 0xd4b Cortex-A78C 0xd4d Cortex-A715 0xd4e Cortex-X3 0xd80 Cortex-A520 0xd81 Cortex-A720 0xd82 Cortex-X4", t, " ")
      for (i = 1; i < m; i += 2) nm[t[i]] = t[i + 1]
      for (i = 1; i <= k; i++) s = s (i > 1 ? ", " : "") (o[i] in nm ? nm[o[i]] : "part " o[i]) " x" n[o[i]]
      print s }' /proc/cpuinfo 2>/dev/null
}
cpu_line(){
  local l; l=$(cpu_label)
  if cpu_lse; then echo "${l:-cores not listed}, Armv8.1 or newer (LSE atomics)"; else echo "${l:-cores not listed}, Armv8.0 (no LSE atomics)"; fi
}
x86_warn(){ cat <<EOF
CPU without Armv8.1 atomics (LSE): $(cpu_label | sed 's/^$/cores not listed/').
       Valve's native ARM64 client stops at start on this CPU (steam-for-linux #13288);
       setup installs Valve's x86 client, run through emulation:
       - first start downloads client files and takes several minutes; later starts are
         slower than native client
       - client window drawn on CPU; games reach GPU through emulator's GL and Vulkan forwarding
       - Windows titles use x86 Proton through emulation
       Setup moves to native client by itself once Valve's build runs on this CPU again.
       --client=arm64 (or STEAM_ARM_ALLOW_ARMV80=1) keeps native client instead.
EOF
}
ARMV80_NATIVE_WARN="CPU without Armv8.1 atomics (LSE), native ARM64 client chosen by hand (--client=arm64 or
       STEAM_ARM_ALLOW_ARMV80=1): client builds newer than 15 April 2026 stop at start with SIGILL here
       until steam-for-linux #13288 is fixed (https://github.com/ValveSoftware/steam-for-linux/issues/13288).
       --client=auto returns to automatic choice (x86 client on this CPU)."
# Client type: arm64 (native) or x86 (Valve's x86 client through FEX). Option, then STEAM_ARM_ALLOW_ARMV80,
# then saved hand choice (CLIENT_SET=user), then CPU: x86 only without LSE atomics. Sets CLIENT, CLIENT_SET.
OPT_CLIENT=
client_pick(){
  local saved; saved=$(conf_get CLIENT)
  if [ -n "$OPT_CLIENT" ] && [ "$OPT_CLIENT" != auto ]; then CLIENT=$OPT_CLIENT; CLIENT_SET=user
  elif [ -z "$OPT_CLIENT" ] && ! cpu_lse && [ "${STEAM_ARM_ALLOW_ARMV80:-0}" = 1 ]; then CLIENT=arm64; CLIENT_SET=user
  elif [ -z "$OPT_CLIENT" ] && [ "$(conf_get CLIENT_SET)" = user ] && { [ "$saved" = arm64 ] || [ "$saved" = x86 ]; }; then
    CLIENT=$saved; CLIENT_SET=user
  elif cpu_lse; then CLIENT=arm64; CLIENT_SET=auto
  else CLIENT=x86; CLIENT_SET=auto; fi
}
# Why x86 client: hand choice or CPU rule (banner, final summary).
x86_why(){ if [ "$CLIENT_SET" = user ]; then echo "chosen by hand"; else echo "CPU without Armv8.1 atomics"; fi; }
# x86 client and a game share memory: stop below 1.5 GiB (1 GB boards), warn below 3.5 GiB.
mem_gate(){
  local kb; kb=$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null)
  [ -n "$kb" ] || return 0
  if [ "$kb" -lt 1572864 ]; then
    die "x86 client needs 2 GB of memory or more; this system has $((kb / 1024)) MiB. Client window and game do not fit together."
  elif [ "$kb" -lt 3670016 ]; then
    warn "x86 client and game share $((kb / 1024)) MiB of memory; close other programs while playing."
  fi
}
# curl progress bar on a terminal or the menu's progress screen (STEAM_ARM_PROGRESS=1, 60 columns); errors only elsewhere.
CURL_SHOW=(-sS); CURL_ENV=()
if [ -t 2 ]; then CURL_SHOW=(--progress-bar)
elif [ "${STEAM_ARM_PROGRESS:-0}" = 1 ]; then CURL_SHOW=(--progress-bar); CURL_ENV=(COLUMNS=60); fi
# Temporary files and folders of this run, removed on any exit; UCLEANUP ones (in the game user's home) by that user.
CLEANUP=(); UCLEANUP=()
trap 'rm -rf "${CLEANUP[@]}"; [ ${#UCLEANUP[@]} -gt 0 ] && as_user rm -rf "${UCLEANUP[@]}"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM
# As root: private temp folder and root's own home (sudo -E and su keep the caller's folders, which that account can change).
if [ "$(id -u)" = 0 ]; then
  SA_TMP=$(mktemp -d /tmp/steam-arm.XXXXXX) || die "could not create a folder in /tmp; free some space and run this again"
  CLEANUP+=("$SA_TMP")
  HOME=$(getent passwd 0 | cut -d: -f6)
  export TMPDIR="$SA_TMP" HOME="${HOME:-/root}"
  unset XDG_RUNTIME_DIR XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME
fi
# Files in the game user's home are written by that user, so a link placed there never redirects a root write.
# Account switch without a PAM session: pam_systemd writes OSC 3008 escapes straight to the terminal.
# Runs from the account's home: a caller's folder (for example /root) may be closed to it.
as_acct(){
  local u=$1 h s; shift
  h=$(getent passwd "$u" | cut -d: -f6); s=$(getent passwd "$u" | cut -d: -f7)
  ( cd "${h:-/}" 2>/dev/null || cd /
    command -v setpriv >/dev/null 2>&1 || exec runuser -u "$u" -- "$@"
    exec setpriv --reuid="$u" --regid="$(id -g "$u")" --init-groups env HOME="$h" SHELL="${s:-/bin/sh}" USER="$u" LOGNAME="$u" "$@" )
}
as_user(){ as_acct "$GAMEUSER" env -u TMPDIR "$@"; }
# Running tray of game account: restarted in its own session, so new tray code runs without a new login.
# Status 0 when restarted, 1 when no tray (or no session variables) found.
tray_restart(){
  local p n e=()
  p=$(pgrep -o -u "$GAMEUSER" -f /usr/local/bin/steam-arm-tray 2>/dev/null) || return 1
  mapfile -t e < <(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null \
    | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|XDG_CURRENT_DESKTOP|HOME)=')
  [ ${#e[@]} -gt 0 ] || return 1
  kill -TERM "$p" 2>/dev/null
  n=0; while kill -0 "$p" 2>/dev/null && [ "$n" -lt 10 ]; do sleep 0.5; n=$((n + 1)); done
  # Waiting subshell and tray keep no descriptor of this run: setup lock (fd 8) refuses later runs, output pipe never ends.
  ( exec </dev/null >/dev/null 2>&1
    for f in /dev/fd/*; do f=${f##*/}; [ "$f" -gt 2 ] 2>/dev/null && [ "$f" != 255 ] && eval "exec $f>&-"; done
    as_acct "$GAMEUSER" env "${e[@]}" setsid /usr/local/bin/steam-arm-tray ) &
  return 0
}
# Command line as the game user, login-style environment, from its home folder (as su - did).
login_sh(){
  local h; h=$(getent passwd "$GAMEUSER" | cut -d: -f6)
  ( cd "${h:-/}" 2>/dev/null || cd /; as_acct "$GAMEUSER" env -i HOME="$h" USER="$GAMEUSER" LOGNAME="$GAMEUSER" \
      SHELL=/bin/sh PATH=/usr/local/bin:/usr/bin:/bin LANG="${LANG:-C.UTF-8}" sh -c "$1" )
}
# stdin into file $1 (mode $2, default 644) as the game user; new file renamed over the old one.
user_write(){
  # shellcheck disable=SC2016
  as_user sh -c 't=$(mktemp "$1.XXXXXX") && cat > "$t" && chmod "$2" "$t" && mv -f "$t" "$1" || { rm -f "$t"; exit 1; }' sh "$1" "${2:-644}"
}
GAMEPASS=""
# Opt-in components (all others default on). pad-xbox: client's own Steam Input re-identifies pads.
# shader-cache: several GB download and long first-run processing. kde-input-prompt: security trade-off.
DEFAULT_OFF="pad-xbox shader-cache kde-input-prompt"
# Client home: env, then saved setting, then default; re-run never moves the client away from its games.
ARMHOME_ENV=${ARMHOME_DIR:-}; GAMEUSER_ENV=${GAMEUSER:-}
ARMHOME_DIR="${ARMHOME_DIR:-$(sed -n 's/^ARMHOME_DIR=//p' /etc/steam-arm/steam-arm.conf 2>/dev/null | tail -1)}"
ARMHOME_DIR="${ARMHOME_DIR:-.local/share/steam-arm}"
ARMHOME_DIR="${ARMHOME_DIR%/}"
# Client folder: plain relative path below the home, never the home itself or a shared folder in it.
armhome_ok(){
  case "$1" in ''|/*|.|./*|..|../*|*/..|*/../*|*/.|*/./*|*//*|*[!A-Za-z0-9._/-]*) return 1;; esac
  case "$1" in .local|.local/share|.local/state|.local/bin|.config|.cache|.var|.var/app|.steam|.ssh|.gnupg|.mozilla|snap|bin|\
    Desktop|Documents|Downloads|Music|Pictures|Public|Templates|Videos) return 1;; esac
  return 0
}
ARMHOME_BAD="ARMHOME_DIR=$ARMHOME_DIR is not usable. It must be a folder path relative to the home folder, such as .local/share/steam-arm, without '..', spaces or special characters, and not a shared folder such as .local or Documents. Correct ARMHOME_DIR in /etc/steam-arm/steam-arm.conf or in the environment, then run this again."
# Settings file is also read by the launcher/tray; conf_set updates its own key in place, keeping the rest.
CONF=/etc/steam-arm/steam-arm.conf
conf_get(){ sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -1; }
conf_set(){
  local t; [ -f "$CONF" ] || : > "$CONF" || die "could not write $CONF"
  t=$(mktemp "$CONF.XXXXXX") || die "could not write $CONF"
  awk -v k="$1=" -v v="$1=$2" 'index($0, k) == 1 { if (!d) print v; d = 1; next } { print } END { if (!d) print v }' "$CONF" > "$t" \
    && chmod 644 "$t" && mv -f "$t" "$CONF" || { rm -f "$t"; die "could not write $CONF"; }
}
conf_del(){
  local t; grep -qs "^$1=" "$CONF" || return 0
  t=$(mktemp "$CONF.XXXXXX") || die "could not write $CONF"
  if ! { awk -v k="$1=" 'index($0, k) != 1' "$CONF" > "$t" && chmod 644 "$t" && mv -f "$t" "$CONF"; }; then
    rm -f "$t"; die "could not write $CONF"
  fi
}
# GAMEUSER: env, then saved account, then account whose home already holds the client, then uid 1000; created if none exists.
# Only an env GAMEUSER or the final steamarm fallback may create an account; a conf/detected
# name must already exist here, else a conf naming a foreign user creates it.
GAMEUSER_MAY_CREATE=0
if [ -n "${GAMEUSER:-}" ]; then
  GAMEUSER_MAY_CREATE=1
else
  GAMEUSER="$(conf_get GAMEUSER)"
  if [ -n "$GAMEUSER" ] && ! getent passwd "$GAMEUSER" >/dev/null 2>&1; then
    warn "conf GAMEUSER='$GAMEUSER' has no account on this system; ignored"
    GAMEUSER=
  fi
fi
if [ -z "$GAMEUSER" ] && [ -f "$CONF" ]; then
  GAMEUSER=$(getent passwd | while IFS=: read -r u _ id _ _ h _; do
    [ "$id" -ge 1000 ] 2>/dev/null && [ -d "$h/$ARMHOME_DIR/.local/share/Steam" ] && echo "$u"; done)
  [ "$(printf '%s\n' "$GAMEUSER" | wc -l)" = 1 ] || GAMEUSER=
fi
GAMEUSER="${GAMEUSER:-$(getent passwd 1000 2>/dev/null | cut -d: -f1)}"
if [ -z "$GAMEUSER" ]; then GAMEUSER=steamarm; GAMEUSER_MAY_CREATE=1; fi
RFS=/opt/fex-rootfs/Ubuntu_24_04
FEXPPA="ppa:fex-emu/fex"
# Debian: same PPA as plain apt source; key pinned to Launchpad's signing_key_fingerprint for the PPA.
FEXPPA_URI=https://ppa.launchpadcontent.net/fex-emu/fex/ubuntu
FEXPPA_FPR=EDB98BFE8A2310DC9C4A376E76DBFEBEA206F5AC
FEXSRC=/etc/apt/sources.list.d/steam-arm-fex.sources
FEXKEY=/etc/apt/keyrings/steam-arm-fex.gpg
# Ubuntu family: add-apt-repository maps the PPA to its own series; elsewhere it maps to the Debian codename, which the PPA lacks.
os_ubuntu(){ ( . /etc/os-release 2>/dev/null; case " ${ID:-} ${ID_LIKE:-} " in *" ubuntu "*) exit 0;; esac; exit 1 ); }
# Debian major release: VERSION_ID on Debian (and Raspberry Pi OS), else /etc/debian_version; empty on testing/sid.
debian_major(){
  ( . /etc/os-release 2>/dev/null; v=; [ "${ID:-}" = debian ] && v=${VERSION_ID:-}
    [ -n "$v" ] || v=$(cut -d. -f1 /etc/debian_version 2>/dev/null)
    case "$v" in [0-9]*) echo "${v%%.*}";; esac )
}
glibc_ver(){ getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}'; }
# PPA series for this Debian release; its FEX build needs libc6 at or below host glibc and Debian's Qt 5 package names
# (jammy: libc6 2.34, libqt5core5a = Debian 12; noble: libc6 2.38, libqt5core5t64 = Debian 13 and newer).
fex_series(){
  local m g need s; m=$(debian_major); g=$(glibc_ver)
  case "$m" in
    12) s=jammy need=2.34;;
    1[3-9]|[2-9][0-9]) s=noble need=2.38;;
    "") s=noble need=2.38;;   # testing/sid: newer than 13
    *) return 1;;
  esac
  [ -n "$g" ] && [ "$(printf '%s\n%s\n' "$need" "$g" | sort -V | head -1)" = "$need" ] || return 1
  echo "$s"
}
# Debian: PPA written as deb822 source with its signing key, fingerprint checked before apt sees it.
fex_source_debian(){
  local s f t k have=0 cn
  cn=$( . /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}")
  # fex source named after Debian codename (add-apt-repository on Debian, or by hand) fails apt-get update: disabled
  for f in /etc/apt/sources.list.d/*; do
    [ -f "$f" ] && [ "$f" != "$FEXSRC" ] && grep -qs "fex-emu/fex" "$f" || continue
    case "$f" in *.list|*.sources) ;; *) continue;; esac
    if [ -n "$cn" ] && grep -qsw -- "$cn" "$f"; then
      mv -f "$f" "$f.disabled" && warn "FEX package source $f names $cn, which FEX's PPA does not publish; renamed to $f.disabled"
    else have=1; fi
  done
  grep -qs "fex-emu/fex" /etc/apt/sources.list && have=1
  [ -f "$FEXSRC" ] && have=1
  [ "$have" = 1 ] && return 0
  s=$(fex_series) || die "FEX's package source has no build for this system ($(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"'), glibc $(glibc_ver)); Steam ARM needs Debian 13 or newer
       (README, Requirements)."
  { command -v curl >/dev/null && command -v gpg >/dev/null; } || apt-get install -y curl gpg ca-certificates \
    || die "curl and gpg did not install (needed to add FEX package source). $NETHINT"
  t=$(mktemp -d) || die "could not create a temporary folder"; CLEANUP+=("$t")
  curl -fsSL --proto =https "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$FEXPPA_FPR" -o "$t/key.asc" \
    || die "FEX package signing key download failed (keyserver.ubuntu.com). $NETHINT"
  # exactly one primary key, with pinned fingerprint
  k=$(GNUPGHOME=$t gpg --batch --show-keys --with-colons "$t/key.asc" 2>/dev/null | awk -F: '$1=="pub"{p=1;next} $1=="fpr"&&p{print $10;p=0}')
  [ "$k" = "$FEXPPA_FPR" ] || die "FEX package signing key has wrong fingerprint (${k:-none}, expected $FEXPPA_FPR); nothing written."
  GNUPGHOME=$t gpg --batch --yes --dearmor -o "$t/key.gpg" "$t/key.asc" || die "could not convert FEX package signing key"
  mkdir -p -m 0755 /etc/apt/keyrings && install -m 0644 "$t/key.gpg" "$FEXKEY" || die "could not write $FEXKEY"
  printf '# steam-arm-setup: FEX PPA, Ubuntu %s build, for this Debian system\nTypes: deb\nURIs: %s\nSuites: %s\nComponents: main\nArchitectures: arm64\nSigned-By: %s\n' \
    "$s" "$FEXPPA_URI" "$s" "$FEXKEY" > "$FEXSRC" && chmod 0644 "$FEXSRC" || die "could not write $FEXSRC"
  say "     FEX package source: $FEXPPA_URI $s (Ubuntu build matching this Debian release)"
}
# Packages among $@ that apt offers no version of (read-only; C locale for apt's labels).
pkg_missing(){
  LC_ALL=C apt-cache policy "$@" 2>/dev/null | awk -v want="$*" '
    /^[^ ].*:$/ { p = $0; sub(/:$/, "", p); sub(/:.*/, "", p) }
    /^  Candidate: [0-9]/ { ok[p] = 1 }
    END { n = split(want, w, " "); for (i = 1; i <= n; i++) if (!(w[i] in ok)) printf "%s ", w[i] }'
}
# FEX command installed by a fex-emu package.
fex_packaged(){ local p; p=$(readlink -f "$(command -v FEX 2>/dev/null)" 2>/dev/null) && [ -n "$p" ] && dpkg -S "$p" 2>/dev/null | grep -q '^fex-emu'; }
fex_binfmt(){ [ -e /proc/sys/fs/binfmt_misc/FEX-x86_64 ] && [ -e /proc/sys/fs/binfmt_misc/FEX-x86 ]; }
# Thunk folders of FEX in use: its own prefix first, then /usr, /usr/local; prints "host guest db", status 1 when none is complete.
fex_thunk_paths(){
  local p d h
  p=$(readlink -f "$(command -v FEX 2>/dev/null)" 2>/dev/null); p=${p%/bin/FEX}
  for d in $p /usr /usr/local; do
    [ -f "$d/share/fex-emu/ThunksDB.json" ] && [ -d "$d/share/fex-emu/GuestThunks" ] || continue
    for h in "$d/lib/aarch64-linux-gnu/fex-emu/HostThunks" "$d/lib/fex-emu/HostThunks" "$d/lib64/fex-emu/HostThunks"; do
      [ -d "$h" ] && { echo "$h/ $d/share/fex-emu/GuestThunks/ $d/share/fex-emu/ThunksDB.json"; return 0; }
    done
  done
  return 1
}
# Stable arm64 manifest for the first download; -deckard moves the client to its own ARM channel on first start.
MANIFEST=https://client-update.steamstatic.com/steam_client_linuxarm64
CDN=https://client-update.steamstatic.com
# x86 client (CPU without Armv8.1 atomics): bootstrap package; the client downloads the rest at first start.
MANIFEST_X86=https://client-update.steamstatic.com/steam_client_ubuntu12
X86PY=/usr/local/lib/steam-arm-x86client.py
# Package tools refused first in PATH of the x86 client (emulated writes reach the host system).
NOPKG=/usr/local/lib/steam-arm-nopkg
# gpu-in-emulation: x86-64 + i386 Mesa (Mali drivers) in a second RootFS tree; sha256 pinned; local file via menu,
# STEAM_ARM_PROVIDER_TARBALL, saved PROVIDER_LOCAL_FILE or file beside installer.
PROVIDER_URL=https://github.com/Scrumpper/Steam-ARM/releases/download/steam-arm-v2.0/steam-arm-fex-mesa-26.1.8-x86_64-i386.tar.zst
PROVIDER_SHA256=3ba2c461bc069dc702af7f8ee81e7c5343604148977bdddde41b1d3826cb7495
PROVIDER_FILE=${PROVIDER_URL##*/}
# Second address: same file name in the newest release.
PROVIDER_FALLBACK=https://github.com/Scrumpper/Steam-ARM/releases/latest/download/$PROVIDER_FILE
# Folder of this script when it is a regular file (not bash <(curl ...)); archive placed there is used without download.
SELF_DIR=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null) || SELF_DIR=""
case "$SELF_DIR" in /dev/*|/proc/*|"") SELF_DIR="";; *) if [ -f "$SELF_DIR" ]; then SELF_DIR=${SELF_DIR%/*}; else SELF_DIR=""; fi;; esac
# --provider-default: saved local and custom driver archive settings cleared, published archive downloaded again.
PROVIDER_DEFAULT=0
# Second tree: hard-link copy of $RFS with the archive's Mesa; handler picks it per title (steam-arm-handler.py MALI_ROOT).
MALI=/opt/fex-rootfs/Ubuntu_24_04-mali
MALI_MARK="$MALI/.steam-arm-mali"
# Pre-release builds laid the drivers over $RFS itself; state dir of that layout.
PSTATE="$RFS/.steam-arm-fex-mesa"
PROVIDER_MESA_PKGS="libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgbm1 mesa-vulkan-drivers mesa-libgallium mesa-va-drivers mesa-vdpau-drivers"
# Marks the copy of Valve's controller rules this installer wrote (removed only when it matches).
VALVE_MARK='MIT licence; installed by steam-arm-setup'
GLX_HOOK=/etc/apt/apt.conf.d/80steam-arm-glx-lax
# Host `mangohud` command for launch option `mangohud %command%` when host has none; marker line identifies it.
MH_SHIM=/usr/local/bin/mangohud
MH_MARK='# steam-arm-setup mangohud shim'
# zz- sorts after 99-sysctl.conf (else its vm.max_map_count would win at boot); drop-in saves the prior value as a comment.
MC=/etc/sysctl.d/zz-steam-arm.conf
MC_PRIOR='# steam-arm-setup map-count; value before setup: '
# Drop the map-count drop-in and put back the value from before setup; $1 prefixes the message.
mc_restore(){
  local prior
  rm -f /etc/sysctl.d/99-steam-arm.conf
  [ -f "$MC" ] || return 0
  prior=$(sed -n "s/^$MC_PRIOR//p" "$MC" | head -1)
  rm -f "$MC"
  case "$prior" in
    ''|*[!0-9]*|2147483642) echo "  $1vm.max_map_count returns to system setting at next boot";;
    *) sysctl -q -w vm.max_map_count="$prior" 2>/dev/null || true
       echo "  $1vm.max_map_count back to $prior";;
  esac
}
# /dev/shm line setup adds to /etc/fstab (recorded as FSTAB_ADDED=1, so --remove takes only that line out).
FSTAB_LINE='tmpfs /dev/shm tmpfs rw,nosuid,nodev,mode=1777 0 0'
# /etc/fstab through a new file renamed over it: $1 add appends the line, drop removes it.
fstab_edit(){
  local t
  [ -L /etc/fstab ] && return 1
  t=$(mktemp /etc/.fstab.XXXXXX) || return 1
  if { if [ "$1" = add ]; then cat /etc/fstab && { [ -z "$(tail -c1 /etc/fstab)" ] || echo; } && echo "$FSTAB_LINE"
       else grep -vxF "$FSTAB_LINE" /etc/fstab || [ $? = 1 ]; fi; } > "$t" \
     && chmod --reference=/etc/fstab "$t" && chown --reference=/etc/fstab "$t" && sync "$t" && mv -f "$t" /etc/fstab; then
    return 0
  fi
  rm -f "$t"; return 1
}
# KWin only re-reads kwinrulesrc when told; without a reconfigure signal, rules wait until next login.
kwin_reload(){
  local u; u=$(id -u "$GAMEUSER" 2>/dev/null) || return 0
  login_sh "XDG_RUNTIME_DIR=/run/user/$u DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$u/bus dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure" >/dev/null 2>&1 || true
}
# KDE config tools of Plasma 6, else Plasma 5: prints 6 or 5, status 1 when neither pair is installed.
kcfg_ver(){
  local v
  for v in 6 5; do
    command -v "kwriteconfig$v" >/dev/null 2>&1 && command -v "kreadconfig$v" >/dev/null 2>&1 && { echo "$v"; return 0; }
  done
  return 1
}
# Take a window rule group (default steam-arm-frame) out of the game user's KWin rules: list entry and every key setup writes.
kwin_rule_remove(){
  local rid=${1:-steam-arm-frame} cur new n k kv cmd=""
  kv=$(kcfg_ver) || return 0
  cur=$(login_sh "kreadconfig$kv --file kwinrulesrc --group General --key rules" 2>/dev/null)
  case ",$cur," in *",$rid,"*)
    new=$(printf '%s' "$cur" | tr ',' '\n' | grep -vx "$rid" | paste -sd, -)
    n=$(printf '%s' "$new" | awk -F, '{print NF}'); n=${n:-0}
    cmd="kwriteconfig$kv --file kwinrulesrc --group General --key rules '$new'; kwriteconfig$kv --file kwinrulesrc --group General --key count $n; ";;
  esac
  for k in Description wmclass wmclassmatch wmclasscomplete types noborder noborderrule; do
    cmd="${cmd}kwriteconfig$kv --file kwinrulesrc --group $rid --key $k --delete; "
  done
  login_sh "$cmd" 2>/dev/null
  kwin_reload
  [ "$rid" = steam-arm-frame ] && [ -f "$KWIN_MADE" ] || return 0
  # record names account whose file setup created (empty: record of earlier release)
  case "$(head -n 1 "$KWIN_MADE")" in ''|"$GAMEUSER") ;; *) return 0;; esac
  # file setup created: deleted once only empty General keys remain
  login_sh 'f=$HOME/.config/kwinrulesrc; [ -f "$f" ] && ! grep -qvxF -e "[General]" -e count=0 -e rules= -e "" "$f" && rm -f "$f"' 2>/dev/null
  rm -f "$KWIN_MADE"
}
# Record: kwinrulesrc of account named in it did not exist before setup wrote its rule.
KWIN_MADE=/etc/steam-arm/kwinrules-made
# Files shared with other tools: sha256 of what setup wrote, so --remove deletes them only while unchanged.
OWNED=/etc/steam-arm/owned.sha
own_mark(){
  local t
  mkdir -p "${OWNED%/*}" && t=$(mktemp "$OWNED.XXXXXX") || return 0
  { awk -v p="$1" 'substr($0, 67) != p' "$OWNED" 2>/dev/null; sha256sum "$1"; } > "$t" && chmod 644 "$t" && mv -f "$t" "$OWNED" || rm -f "$t"
}
own_ok(){ [ -f "$1" ] && grep -qxF "$(sha256sum "$1" 2>/dev/null)" "$OWNED" 2>/dev/null; }
# Setup for another account: rule file record of previous account $1 (its rule and file go) and FEX settings
# lines of other homes leave the records, so --remove never takes them as setup's.
acct_records_drop(){
  local ou=$1 nh t n=""
  if [ -f "$KWIN_MADE" ] && case "$(head -n 1 "$KWIN_MADE")" in ''|"$ou") true;; *) false;; esac; then
    getent passwd "$ou" >/dev/null 2>&1 && GAMEUSER=$ou kwin_rule_remove
    rm -f "$KWIN_MADE"; n="KDE rule file record"
  fi
  nh=$(getent passwd "$GAMEUSER" 2>/dev/null | cut -d: -f6)
  if [ -f "$OWNED" ] && t=$(mktemp "$OWNED.XXXXXX"); then
    awk -v k="${nh%/}/.fex-emu/Config.json" '{p = substr($0, 67)} p ~ /\/\.fex-emu\/Config\.json$/ && p != k {next} {print}' "$OWNED" > "$t" \
      && chmod 644 "$t" || { rm -f "$t"; return 0; }
    if cmp -s "$t" "$OWNED"; then rm -f "$t"; else mv -f "$t" "$OWNED"; n="${n:+$n, }FEX settings file"; fi
  fi
  [ -z "$n" ] || echo "  setup records of previous account $ou dropped ($n)"
}
# Client type record in client home (arm64 or x86), written by step 9.
CLIENT_REC=.config/steam-arm/client-type
# Client type this client home held: its record, else settings file when it names this home, else x86 edits found.
folder_client(){
  local r
  r=$(head -n 1 "$ARMHOME/$CLIENT_REC" 2>/dev/null)
  case $r in arm64|x86) echo "$r"; return 0;; esac
  if [ "$(conf_get GAMEUSER)" = "$GAMEUSER" ] && [ "$(conf_get ARMHOME_DIR)" = "$ARMHOME_DIR" ]; then
    echo "${CLIENT_PREV:-arm64}"
  elif [ -e "$S/ubuntu12_32/steam-launch-wrapper.real" ] || [ -e "$S/ubuntu12_64/steamwebhelper.sh.steam-arm-sha" ] \
       || [ -e "$ARMHOME/.config/steam-arm/x86-verified" ]; then
    echo x86
  else
    echo arm64
  fi
}
# graphics_provider.json of $RFS, architecture list form.
gp_list_json(){ printf '{\n  "graphics_provider_v0": {\n    "architectures": ["x86_64-linux-gnu", "i386-linux-gnu"]\n  }\n}\n'; }
# Write it through a new file, so no other hard link to the old one changes.
gp_list_write(){
  local t; t=$(mktemp "$RFS/.graphics_provider.json.XXXXXX") || return 1
  if ! { gp_list_json > "$t" && chmod 644 "$t" && mv -f "$t" "$RFS/graphics_provider.json"; }; then rm -f "$t"; return 1; fi
}
# Pre-release layout: its driver files out of $RFS, distro Mesa back from the saved tar, list-form json back.
legacy_mesa_restore(){
  [ -d "$PSTATE" ] || return 0
  [ -f "$PSTATE/installed.list" ] && unlink_in "$RFS" < "$PSTATE/installed.list"
  if [ -f "$PSTATE/distro-mesa.tar" ] && ! { tar -tf "$PSTATE/distro-mesa.tar" | paths_inside "$RFS" \
       && tar -xpf "$PSTATE/distro-mesa.tar" -C "$RFS"; }; then
    warn "distro Mesa files could not be put back into $RFS; saved copy kept in $PSTATE, run this again"
    return 1
  fi
  gp_list_write || return 1
  rm -rf "$PSTATE"
  echo "  distro Mesa restored in the x86-64 root filesystem"
}
# $RFS identity: directory inode + x86-64 libc; changes when the RootFS is fetched again.
rfs_id(){ printf '%s %s' "$(stat -c %i "$RFS" 2>/dev/null)" "$(stat -Lc %i:%Y "$RFS/usr/lib/x86_64-linux-gnu/libc.so.6" 2>/dev/null)"; }
# Parent folder of path $3 (relative to $2), resolved; status 1 when it lies outside $2 (resolved: $1).
parent_in(){
  local d
  d=$(readlink -m "$2/$(dirname "$3")") || return 1
  case "$d/" in "$1"/*) echo "$d";; *) return 1;; esac
}
# Unlink paths read from stdin (relative to $1) that resolve inside $1; unlink never writes a shared inode.
unlink_in(){
  local rr x d f
  rr=$(readlink -f "$1") || return 1
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    d=$(parent_in "$rr" "$1" "$x") || continue
    f="$d/${x##*/}"
    [ -L "$f" ] && [ -d "$f" ] && continue
    if [ -L "$f" ] || [ -f "$f" ]; then rm -f "$f"; fi
  done
}
# Status 1 when an archive member read from stdin (relative to $1) would land outside $1 through a link in its parent path.
paths_inside(){
  local rr x bad=0
  rr=$(readlink -f "$1") || return 1
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    case "/$x/" in */../*) bad=1; echo "  archive member outside $1: $x" >&2; continue;; esac
    parent_in "$rr" "$1" "$x" >/dev/null || { bad=1; echo "  archive member outside $1: $x" >&2; }
  done
  return $bad
}
# Steam client processes (account $1, else any): one match for native and x86 client.
client_pids(){ pgrep ${1:+-u "$1"} -x steam 2>/dev/null; }
# Status 0 while a Steam client of the game user runs.
steam_up(){ id "$GAMEUSER" >/dev/null 2>&1 && client_pids "$GAMEUSER" >/dev/null; }
steam_up_die(){ die "Steam is running for '$GAMEUSER'. Close it first (exit from its menu, Stop Steam in the tray, or steam-arm --shutdown as $GAMEUSER), then run this again."; }
# Driver archive in use: PSRC_KIND published (download or local copy) or custom (file and sha256 given, saved for later runs).
# Local copy of published archive: PSRC_FROM env|saved|beside; PSRC_SOFT=1 falls back to download when unusable.
provider_source(){
  local f
  PSRC_KIND=published; PSRC_SHA=$PROVIDER_SHA256; PSRC_FILE=${STEAM_ARM_PROVIDER_TARBALL:-}; PSRC_SAVED=0; PSRC_FROM=""; PSRC_SOFT=0
  if [ -n "${STEAM_ARM_PROVIDER_SHA256:-}" ]; then
    PSRC_KIND=custom; PSRC_SHA=$STEAM_ARM_PROVIDER_SHA256
  elif [ "$PROVIDER_DEFAULT" != 1 ] && [ -n "$(conf_get PROVIDER_CUSTOM_SHA256)" ]; then
    PSRC_KIND=custom; PSRC_SHA=$(conf_get PROVIDER_CUSTOM_SHA256); PSRC_SAVED=1
    [ -n "$PSRC_FILE" ] || PSRC_FILE=$(conf_get PROVIDER_CUSTOM_FILE)
  elif [ -n "$PSRC_FILE" ]; then
    PSRC_FROM=env
  elif [ "$PROVIDER_DEFAULT" != 1 ] && f=$(conf_get PROVIDER_LOCAL_FILE) && [ -n "$f" ]; then
    PSRC_FILE=$f; PSRC_FROM=saved; PSRC_SOFT=1
  elif [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/$PROVIDER_FILE" ]; then
    PSRC_FILE=$SELF_DIR/$PROVIDER_FILE; PSRC_FROM=beside; PSRC_SOFT=1
  fi
}
# File $1 is the published archive (sha256 pinned above).
provider_local_ok(){ [ -f "$1" ] && [ -r "$1" ] && [ "$(sha256sum -- "$1" 2>/dev/null | cut -c1-64)" = "$PROVIDER_SHA256" ]; }
# Local copy of published archive recorded for later runs; launcher sources the settings file, so path charset is limited.
provider_local_save(){
  local p
  # --provider-default saves only a file given for this run (local copy picked over a saved custom archive)
  [ "$PROVIDER_DEFAULT" = 1 ] && [ "$PSRC_FROM" != env ] && return 0
  p=$(readlink -f -- "$PSRC_FILE" 2>/dev/null) || p=$PSRC_FILE
  if [[ "$p" =~ ^/[A-Za-z0-9._/+-]+$ ]]; then
    [ "$(conf_get PROVIDER_LOCAL_FILE)" = "$p" ] || conf_set PROVIDER_LOCAL_FILE "$p"
  else
    echo "  driver archive path not saved (letters, digits and . _ - + / only); used for this run"
  fi
  return 0
}
# Saved custom archive unusable: the two ways on.
provider_custom_stop(){
  die "Mali drivers inside the emulation come from a custom driver archive (sha256 $PSRC_SHA), and $1.
       Point setup at that file again:
         sudo env STEAM_ARM_PROVIDER_TARBALL=/path/to/file STEAM_ARM_PROVIDER_SHA256=$PSRC_SHA bash steam-arm-install.sh --keep
       or go back to the published drivers:
         sudo bash steam-arm-install.sh --keep --provider-default"
}
# Published archive: release address, then the newest release's file of the same name; 404 at both = file not published.
provider_download(){
  local u code n404=0 pd=""
  # --provider-default with saved local or custom keys: the rerun needs the flag too, or the saved source comes back
  [ "$PROVIDER_DEFAULT" = 1 ] && grep -qs '^PROVIDER_\(CUSTOM\|LOCAL\)_' "$CONF" && pd=" --provider-default"
  for u in "$PROVIDER_URL" "$PROVIDER_FALLBACK"; do
    code=$(env "${CURL_ENV[@]}" curl -fL --proto =https --proto-redir =https "${CURL_SHOW[@]}" -w '%{http_code}' -o "$1" "$u") && return 0
    [ "$code" = 404 ] && n404=$((n404 + 1))
    echo "  no download from $u (HTTP ${code:-000})"
  done
  rm -f "$1"
  [ "$n404" = 2 ] && die "release file $PROVIDER_FILE is not published on GitHub (HTTP 404 at both addresses).
       Download it when it is available, then point setup at it:
         sudo env STEAM_ARM_PROVIDER_TARBALL=/path/to/$PROVIDER_FILE bash steam-arm-install.sh --keep$pd
       or settings menu: Components, Driver archive, Local copy; or place $PROVIDER_FILE beside steam-arm-install.sh;
       or deselect gpu-in-emulation."
  die "driver download failed. $NETHINT Or settings menu: Components, Driver archive, Local copy; or place $PROVIDER_FILE beside steam-arm-install.sh. Or deselect gpu-in-emulation."
}
# Custom archive layout: only usr/, etc/ and graphics_provider.json at the top, and an x86-64 or i386 Mesa driver library.
provider_layout_ok(){
  local l bad
  l=$(tar --zstd -tf "$1" | sed 's#^\./##') || return 1
  bad=$(printf '%s\n' "$l" | awk -F/ '$1 != "" && $1 != "usr" && $1 != "etc" && $0 != "graphics_provider.json" { print $1 }' | sort -u | head -5 | tr '\n' ' ')
  [ -z "$bad" ] || { echo "  unexpected top-level entries: $bad" >&2; return 1; }
  printf '%s\n' "$l" | grep -qE '^usr/lib/(x86_64|i386)-linux-gnu/(libgallium-[^/]*\.so|libvulkan_[^/]*\.so|dri/[^/]*_dri\.so)$' \
    || { echo "  no Mesa driver library in usr/lib/x86_64-linux-gnu or usr/lib/i386-linux-gnu" >&2; return 1; }
}
# Second graphics tree $MALI: hard-link copy of $RFS, distro Mesa unlinked, archive Mesa unpacked as new files.
mali_tree_build(){
  local want pkg tmp="" p a f n t miss="" part="$MALI.part" av extra
  provider_source
  want="archive $PSRC_SHA rootfs $(rfs_id)"
  [ "$PSRC_KIND" = custom ] && want="custom $PSRC_SHA rootfs $(rfs_id)"
  if [ -f "$MALI/graphics_provider.json" ] && [ "$(cat "$MALI_MARK" 2>/dev/null)" = "$want" ]; then
    echo "  Mali drivers inside the emulation already in place ($MALI)"
    [ "$PSRC_KIND" = custom ] && echo "  custom driver archive, not the published one (sha256 $PSRC_SHA)"
    rfs_guard "$MALI" || warn "could not guard package tools in $MALI; run this again"
    [ "$PSRC_KIND" = custom ] && [ "$PSRC_SAVED" = 0 ] && provider_custom_save
    if [ "$PSRC_KIND" = published ] && [ "$PSRC_FROM" = env ]; then
      [ -f "$PSRC_FILE" ] && echo "  local copy of driver archive: $PSRC_FILE saved for later runs (Mali tree already built from this archive; no download)"
      provider_local_save
    fi
    return 0
  fi
  [ -e "$MALI" ] && echo "  driver archive or x86-64 root filesystem changed: rebuilding $MALI"
  if [ "$PSRC_KIND" = custom ] && [ ! -f "$PSRC_FILE" ]; then
    [ "$PSRC_SAVED" = 1 ] && provider_custom_stop "its file ${PSRC_FILE:-(not recorded)} is not there"
    die "STEAM_ARM_PROVIDER_TARBALL=$PSRC_FILE: file not found. Point it at the .tar.zst file."
  fi
  av=$(df -Pm "${MALI%/*}" 2>/dev/null | awk 'NR==2 {print $4}')
  [ "${av:-0}" -ge 400 ] 2>/dev/null || die "Mali drivers inside the emulation need about 400 MB free in ${MALI%/*} (${av:-?} MB free). Free some space and run this again, or deselect gpu-in-emulation."
  tmp=$(mktemp /var/tmp/steam-arm-fex-mesa.XXXXXX) || die "could not create a file in /var/tmp; free some space and run this again"
  CLEANUP+=("$tmp")
  # saved or beside copy: missing or changed file falls back to download
  if [ "$PSRC_SOFT" = 1 ]; then
    if [ ! -f "$PSRC_FILE" ]; then
      warn "saved driver archive $PSRC_FILE not found; downloading published copy"; PSRC_FILE=""; PSRC_FROM=""
    elif ! provider_local_ok "$PSRC_FILE"; then
      echo "  $PSRC_FILE does not match published archive; downloading published copy"; PSRC_FILE=""; PSRC_FROM=""
    else
      echo "  local copy of driver archive: $PSRC_FILE (checksum matches; no download)"
    fi
  # file named in environment (also menu Local copy): same line; checksum checked below
  elif [ "$PSRC_KIND" = published ] && [ "$PSRC_FROM" = env ] && [ -f "$PSRC_FILE" ]; then
    echo "  local copy of driver archive: $PSRC_FILE (no download)"
  fi
  # local archive: root's own copy is checked and unpacked, so the file cannot change in between
  if [ -n "$PSRC_FILE" ]; then
    [ -f "$PSRC_FILE" ] || die "STEAM_ARM_PROVIDER_TARBALL=$PSRC_FILE: file not found. Point it at the .tar.zst file, or unset it to download."
    cp -- "$PSRC_FILE" "$tmp" \
      || { rm -f "$tmp"; die "could not copy $PSRC_FILE to /var/tmp. Free some space and run this again."; }
  else
    echo "  downloading Mali drivers for the emulation (about 75 MB)"
    provider_download "$tmp"
  fi
  pkg=$tmp
  if [ "$(sha256sum "$pkg" | cut -c1-64)" != "$PSRC_SHA" ]; then
    rm -f "$tmp"
    [ "$PSRC_SAVED" = 1 ] && provider_custom_stop "$PSRC_FILE no longer matches it"
    [ "$PSRC_KIND" = custom ] && die "$PSRC_FILE does not match STEAM_ARM_PROVIDER_SHA256=$PSRC_SHA. Nothing changed."
    die "${PSRC_FILE:-downloaded driver archive} does not match the checksum this installer expects. Download it again, or deselect gpu-in-emulation."
  fi
  if [ "$PSRC_KIND" = custom ]; then
    warn "custom driver archive, not the published one: $PSRC_FILE (sha256 $PSRC_SHA)"
    provider_layout_ok "$pkg" || { rm -f "$tmp"; die "$PSRC_FILE does not have the layout of a driver archive (above). Nothing changed."; }
  fi
  echo "  building second graphics tree $MALI (about 330 MB extra disk; unchanged files shared with $RFS)"
  rm -rf "$part"; CLEANUP+=("$part")
  if ! cp -al "$RFS" "$part"; then
    rm -rf "$part"; rm -f "$tmp"
    die "could not copy $RFS to $part. Free some space and run this again, or deselect gpu-in-emulation."
  fi
  rm -rf "$part/.steam-arm-fex-mesa" "$part/.steam-arm-mali"
  # Distro Mesa files of both arches, listed from the RootFS package database.
  for p in $PROVIDER_MESA_PKGS; do
    for a in amd64 i386; do
      f=$part/var/lib/dpkg/info/$p:$a.list
      [ -f "$f" ] || f=$part/var/lib/dpkg/info/$p.list
      [ -f "$f" ] && grep -v -e '^/usr/share/doc/' -e '^/usr/share/lintian/' "$f" | sed 's#^/##'
    done
  done | sort -u | unlink_in "$part"
  # Archive targets unlinked first: tar then creates new files, never writes into $RFS through a shared inode.
  tar --zstd -tf "$pkg" | sed -n 's#^\./##; /[^/]$/p' | unlink_in "$part"
  # a link in a member's parent path would make tar write outside the tree
  if ! tar --zstd -tf "$pkg" | sed 's#^\./##' | paths_inside "$part"; then
    rm -rf "$part"; rm -f "$tmp"
    die "driver archive would write outside $part (a folder link in $RFS points elsewhere). Check $RFS, or deselect gpu-in-emulation."
  fi
  if ! tar --zstd -xpf "$pkg" -C "$part" --no-same-owner || [ ! -f "$part/graphics_provider.json" ]; then
    rm -rf "$part"; rm -f "$tmp"
    die "could not unpack the driver archive. Run this again, or deselect gpu-in-emulation."
  fi
  rm -f "$tmp"
  chmod 644 "$part/graphics_provider.json"
  # Libraries the drivers load from the RootFS, both arches.
  for t in x86_64 i386; do
    for n in libX11-xcb.so.1 libX11.so.6 libXext.so.6 libXxf86vm.so.1 libdrm.so.2 libexpat.so.1 libgcc_s.so.1 \
             libstdc++.so.6 libtinfo.so.6 libxcb-dri3.so.0 libxcb-glx.so.0 libxcb-present.so.0 libxcb-randr.so.0 \
             libxcb-shm.so.0 libxcb-sync.so.1 libxcb-xfixes.so.0 libxcb.so.1 libxshmfence.so.1 libz.so.1 libzstd.so.1 \
             libGLX.so.0 libEGL.so.1 libGLdispatch.so.0 libvulkan.so.1; do
      [ -e "$part/usr/lib/$t-linux-gnu/$n" ] || [ -e "$part/lib/$t-linux-gnu/$n" ] || miss="$miss $t/$n"
    done
  done
  [ -z "$miss" ] || warn "x86-64 root filesystem lacks:$miss. Titles of that architecture may not start on the Mali drivers inside the emulation; gfx=a in their titles.conf line keeps them on forwarding."
  rfs_guard "$part" || die "could not guard package tools in $part. Free some space and run this again."
  printf '%s\n' "$want" > "$part/.steam-arm-mali"
  steam_up && steam_up_die
  [ -n "${DIE_NOTE:-}" ] && DIE_NOTE="Custom driver archive settings kept. Run this again with --provider-default."
  { rm -rf "$MALI" && mv "$part" "$MALI"; } || die "could not move $part to $MALI; run this again"
  [ "$PSRC_KIND" = custom ] && provider_custom_save
  [ "$PSRC_KIND" = published ] && [ -n "$PSRC_FROM" ] && provider_local_save
  extra=$(du -sm "$RFS" "$MALI" 2>/dev/null | awk 'NR==2 {print $1}')
  echo "  Mali drivers inside the emulation ready: $MALI (${extra:-?} MB extra disk)"
}
# Custom archive recorded, so later runs keep it or stop instead of switching back to the published one.
provider_custom_save(){
  conf_set PROVIDER_CUSTOM_SHA256 "$PSRC_SHA"
  conf_set PROVIDER_CUSTOM_FILE "$(readlink -f -- "$PSRC_FILE" 2>/dev/null || printf '%s' "$PSRC_FILE")"
}
# Delete the second graphics tree; status 1 when there was none.
mali_tree_remove(){
  { [ -e "$MALI" ] || [ -e "$MALI.part" ]; } || return 1
  rm -rf "$MALI" "$MALI.part"
}
# Package tools of an x86 tree ($1) replaced by a refusal: under emulation they write to the host system.
# Original kept as <tool>.steam-arm-real (expert escape hatch); wrappers are new files, never written through a shared inode.
GUARD_MARK='steam-arm-guard'
rfs_guard(){
  local b p t
  for b in apt apt-get dpkg; do
    p="$1/usr/bin/$b"
    # tool missing but original kept: an earlier run stopped between the two renames
    { [ -e "$p" ] || [ -L "$p" ] || [ -e "$p.steam-arm-real" ] || [ -L "$p.steam-arm-real" ]; } || continue
    t=$(mktemp "$p.XXXXXX") || return 1
    { printf '#!/bin/sh\n# %s: %s of this x86 root filesystem is off; %s.steam-arm-real is the original.\n' "$GUARD_MARK" "$b" "$b"
      # read-only dpkg queries still answer (architecture, versions), also after --admindir= style options
      # shellcheck disable=SC2016
      [ "$b" = dpkg ] && printf '%s\n' 'a=; for x in "$@"; do case "$x" in --admindir=*|--root=*|--instdir=*) ;; *) a=$x; break;; esac; done' \
        'case "$a" in --print-architecture|--print-foreign-architectures|--version|-l|--list|-s|--status|-L|--listfiles|-S|--search|-W|--show|--compare-versions|--get-selections|-p|--print-avail|--assert-*) exec "$0.steam-arm-real" "$@";; esac'
      printf '%s\nexit 1\n' "echo \"Package installs inside the x86 emulation write to the real system and can damage it. Nothing was changed. See 'Fixing a game' in steam-arm-config (Help) for what to do instead.\" >&2"
    } > "$t" && chmod 755 "$t"
    [ -x "$t" ] || { rm -f "$t"; return 1; }
    if grep -qs "$GUARD_MARK" "$p"; then
      # own file of this tree with current text: nothing to do
      [ "$(stat -c %h "$p")" = 1 ] && cmp -s "$t" "$p" && { rm -f "$t"; continue; }
    elif [ -e "$p" ] || [ -L "$p" ]; then
      mv -f "$p" "$p.steam-arm-real" || { rm -f "$t"; return 1; }
    fi
    mv -f "$t" "$p" || { rm -f "$t"; return 1; }
  done
}
# Originals back in place of the wrappers (and bwrap set aside for x86 client); status 1 when nothing was guarded.
rfs_unguard(){
  local b p r=1
  for b in apt apt-get dpkg; do
    p="$1/usr/bin/$b"
    { [ -e "$p.steam-arm-real" ] || [ -L "$p.steam-arm-real" ]; } || continue
    if grep -qs "$GUARD_MARK" "$p" || [ ! -e "$p" ]; then mv -f "$p.steam-arm-real" "$p" && r=0; fi
  done
  rfs_bwrap_on "$1" && r=0
  return $r
}
# bwrap set aside for x86 client back in place (native client, removal); status 1 when nothing moved.
rfs_bwrap_on(){
  local p="$1/usr/bin/bwrap"
  [ -e "$p.steam-arm-real" ] && [ ! -e "$p" ] && [ ! -L "$p" ] || return 1
  mv -f "$p.steam-arm-real" "$p"
}
# x86 client: an x86 bwrap in the RootFS hangs runtime containers under emulation; set aside so host bwrap answers.
rfs_bwrap_off(){
  local p="$1/usr/bin/bwrap"
  [ -f "$p" ] && [ ! -L "$p" ] || return 0
  file -b "$p" 2>/dev/null | grep -qE 'x86-64|Intel (80386|i386)' || return 0
  mv -f "$p" "$p.steam-arm-real" && echo "  x86 bwrap in $RFS set aside (host bubblewrap serves the x86 client)"
}
# Tree owned by root, no set-user-ID or set-group-ID files: fetched image carries uid 1000, so that account could change x86 programs others run.
rfs_root_own(){
  [ -d "$1" ] && [ ! -L "$1" ] || return 0
  if [ -n "$(find "$1" -xdev \( ! -uid 0 -o ! -gid 0 \) -print -quit 2>/dev/null)" ]; then
    chown -R -h root:root "$1" || return 1
    echo "  $1 owned by root now (was owned by another account)"
  fi
  [ -z "$(find "$1" -xdev -type f -perm /6000 -print -quit 2>/dev/null)" ] && return 0
  find "$1" -xdev -type f -perm /6000 -exec chmod ug-s {} + && echo "  set-user-ID and set-group-ID bits removed in $1"
}
# ---------------------------------------------------------------------------
COMPONENTS_ALL="glx-lax vk-spoof gpu-in-emulation shader-cache physx-skip map-count xpad-dedup pad-hidraw pad-xbox desktop desktop-mode icon-bigpicture icon-desktop tray kde-input-prompt page-size"
# page-size applies to Raspberry Pi 5 class boards (16K page kernel), or where its boot line is still in place.
ps_relevant(){
  case "$( { tr -d '\0' < /proc/device-tree/model; } 2>/dev/null)" in
    "Raspberry Pi 5"*|"Raspberry Pi Compute Module 5"*) return 0;;
    "Raspberry Pi"*) [ "$(getconf PAGESIZE 2>/dev/null)" != 4096 ] && return 0;;
  esac
  grep -qs '^# steam-arm-setup page-size:' /boot/firmware/config.txt /boot/config.txt
}
# kde-input-prompt applies where KDE Plasma's Wayland compositor is installed, or where it was set before.
KDE_MARK=.config/steam-arm/kde-input-prompt
kde_relevant(){
  command -v kwin_wayland >/dev/null 2>&1 && return 0
  [ -f "$(getent passwd "$GAMEUSER" 2>/dev/null | cut -d: -f6)/$KDE_MARK" ]
}
# KDE Plasma Wayland session running now (its prompt shows when a controller drives desktop input).
kde_wayland(){ pgrep -x kwin_wayland >/dev/null 2>&1; }
# Components listed and saved on this system; page-size and kde-input-prompt only where they apply.
COMPONENTS=$COMPONENTS_ALL
ps_relevant || COMPONENTS=${COMPONENTS% page-size}
kde_relevant || COMPONENTS=${COMPONENTS/ kde-input-prompt/}
desc_of(){ case "$1" in
  glx-lax)    echo "Private Mesa GLX copy, for GL contexts bound from several threads";;
  vk-spoof)   echo "Vulkan feature layer: DXVK device on the Mali driver (Proton titles)";;
  gpu-in-emulation) echo "Mali drivers in emulation, auto for titles that need them (Java, 32-bit Vulkan)";;
  shader-cache) echo "Shader pre-caching: in-game videos in Windows games; downloads GBs, long first-run processing";;
  physx-skip) echo "PhysX install step: mark done / stop after 60 s (Windows titles)";;
  map-count)  echo "vm.max_map_count raised to the SteamOS value (Proton warns below it)";;
  xpad-dedup) echo "Drop the duplicate joystick node of third-party Xbox 360 style pads";;
  pad-hidraw) echo "Let the client read pads directly, for rumble and battery level";;
  pad-xbox)   echo "Present other makers' XInput pads as Xbox 360 pads (client does this itself)";;
  desktop)    echo "Menu entry \"Steam ARM\", and title bar for desktop interface windows";;
  desktop-mode) echo "Menu entry \"Steam ARM (Desktop mode)\": desktop interface, for signing in";;
  icon-bigpicture) echo "Desktop icon \"Steam ARM\"";;
  icon-desktop) echo "Desktop icon \"Steam ARM (Desktop mode)\"";;
  tray)       echo "Steam icon in the panel tray: open, Big Picture, desktop mode, Steam pages, Stop, Steam ARM Settings, log";;
  kde-input-prompt) echo "KDE Plasma (Wayland): no \"Remote control requested\" prompt; any X11 program may then send input";;
  page-size)  echo "Raspberry Pi 5: boot firmware's 4K page kernel (no effect elsewhere)";;
esac; }
var_of(){ echo "OPT_$(echo "$1" | tr 'a-z-' 'A-Z_')"; }
for c in $COMPONENTS_ALL; do eval "$(var_of "$c")=1"; done
# DEFAULT_OFF components stay opt-in (pad-xbox grabs the physical pad, starving direct reads).
for c in ${DEFAULT_OFF:-}; do eval "$(var_of "$c")=0"; done
ps_relevant || eval "$(var_of page-size)=0"
kde_relevant || eval "$(var_of kde-input-prompt)=0"
# GPU family: sets default states of vk-spoof, gpu-in-emulation and glx-lax. GPU_FAMILY=<id> (env) picks one by hand, GPU_FAMILY=auto detects.
GPU_FAMILIES="mali-csf-v10 mali-csf-v11 mali-csf-5thgen mali-csf-g1 mali-csf mali-valhall-jm mali-bifrost mali-midgard mali-panfrost mali-utgard mali-kbase
  adreno-a8xx adreno-a7xx adreno-a6xx adreno-a702 adreno-legacy adreno apple-agx broadcom-v3d71 broadcom-v3d42 broadcom-vc4
  vivante img-powervr amd-radv amd-radeon nvidia-nouveau nvidia-prop intel virtio-gpu none unknown"
# Kernel driver name and Mali GPU id per render node (DRM_IOCTL_VERSION, panthor DEV_QUERY, panfrost GET_PARAM); lines "node driver id".
gpu_ioctl_probe(){
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - 2>/dev/null <<'GPUPY'
import ctypes, fcntl, glob, os, struct


def iowr(nr, size):
    return 0xC0000000 | (size << 16) | (0x64 << 8) | nr


class Ver(ctypes.Structure):
    _fields_ = [("major", ctypes.c_int), ("minor", ctypes.c_int), ("patch", ctypes.c_int),
                ("name_len", ctypes.c_size_t), ("name", ctypes.c_void_p),
                ("date_len", ctypes.c_size_t), ("date", ctypes.c_void_p),
                ("desc_len", ctypes.c_size_t), ("desc", ctypes.c_void_p)]


for n in sorted(glob.glob("/dev/dri/renderD*")):
    try:
        fd = os.open(n, os.O_RDWR | os.O_CLOEXEC)
    except OSError:
        continue
    try:
        nb, db, eb = (ctypes.create_string_buffer(80) for _ in range(3))
        v = Ver(0, 0, 0, 79, ctypes.addressof(nb), 79, ctypes.addressof(db), 79, ctypes.addressof(eb))
        fcntl.ioctl(fd, iowr(0x00, ctypes.sizeof(Ver)), v)
        drv, gid = nb.value.decode("ascii", "replace").strip() or "-", "-"
        try:
            if drv == "panthor":
                # DEV_QUERY GPU_INFO into a buffer larger than the struct (kernel zero-fills the rest); gpu_id is first field
                buf = ctypes.create_string_buffer(256)
                fcntl.ioctl(fd, iowr(0x40, 16), struct.pack("IIQ", 0, 256, ctypes.addressof(buf)))
                gid = "%08x" % struct.unpack_from("I", buf.raw)[0]
            elif drv == "panfrost":
                # GET_PARAM GPU_PROD_ID
                gid = "%x" % struct.unpack("IIQ", fcntl.ioctl(fd, iowr(0x44, 16), struct.pack("IIQ", 0, 0, 0)))[2]
        except OSError:
            pass
        print(os.path.basename(n), drv.replace(" ", "_"), gid, flush=True)
    except OSError:
        pass
    finally:
        os.close(fd)
GPUPY
}
# Family and rank (higher wins) of one render node: $1 kernel driver, $2 DT compatible, $3 Mali GPU id (hex), $4 PCI vendor.
gpu_family_of(){
  local a=0 p=0 n f
  case "$1" in
    panthor|tyr)
      # arch major and product major from gpu_id: G610 (10.7), G310 (10.4); v11 G615/G715; 5th gen v12/v13; G1 v14
      case "$3" in ''|-) ;; *) a=$(( 16#$3 >> 28 )); p=$(( 16#$3 >> 16 & 0xf ));; esac
      case "$a.$p/$2" in
        10.[47]/*|0*/*rk3588-mali*) echo mali-csf-v10 60;;
        11.*/*) echo mali-csf-v11 59;;
        1[23].*/*|0*/*mt8196-mali*) echo mali-csf-5thgen 58;;
        14.*/*) echo mali-csf-g1 57;;
        *) echo mali-csf 55;;
      esac;;
    panfrost)
      case "$3" in
        ''|-) ;;
        600|620|720) a=4;;
        750|820|830|860|880) a=5;;
        *) a=$(( 16#$3 >> 12 ));;
      esac
      case "$a/$2" in
        9/*|0/*mali-valhall-jm*) echo mali-valhall-jm 40;;
        [67]/*|0/*mali-bifrost*) echo mali-bifrost 40;;
        [45]/*|0/*arm,mali-t[0-9]*) echo mali-midgard 30;;
        *) echo mali-panfrost 38;;
      esac;;
    lima) echo mali-utgard 10;;
    msm|msm_dpu|msm_mdp|mdp4|adreno)
      # Adreno generation from GPU node compatible: qcom,adreno-XYZ.W or chip id qcom,adreno-CCMMmmpp
      n=$(cat /sys/bus/platform/drivers/adreno/*/of_node/compatible \
            /sys/firmware/devicetree/base/soc*/gpu@*/compatible \
            /sys/firmware/devicetree/base/gpu@*/compatible 2>/dev/null | tr '\0' '\n' \
          | grep -m1 -oE '^qcom,adreno-[0-9][0-9a-f.]*$'); n=${n#qcom,adreno-}
      case "$n" in
        44??????|8??.*) f="adreno-a8xx 82";;
        0700????|702.*) f="adreno-a702 45";;
        43??????|07??????|7??.*) f="adreno-a7xx 80";;
        06??????|6??.*) f="adreno-a6xx 75";;
        '') f="adreno 70";;
        *) f="adreno-legacy 35";;
      esac
      echo "$f";;
    asahi) echo apple-agx 85;;
    v3d) case "$2" in *2712-v3d*) echo broadcom-v3d71 25;; *) echo broadcom-v3d42 20;; esac;;
    vc4|vc4-drm) echo broadcom-vc4 5;;
    etnaviv|etnaviv-gpu) echo vivante 8;;
    powervr) echo img-powervr 15;;
    amdgpu) echo amd-radv 100;;
    radeon) echo amd-radeon 88;;
    nouveau) echo nvidia-nouveau 90;;
    nvidia|nvidia-drm) echo nvidia-prop 95;;
    i915|xe) echo intel 90;;
    virtio_gpu) echo virtio-gpu 50;;
    vgem|vkms|simpledrm|-) echo none 0;;
    *) case "$4" in
         0x1002) echo amd-radv 100;;
         0x10de) echo nvidia-nouveau 90;;
         0x8086) echo intel 90;;
         0x1af4) echo virtio-gpu 50;;
         *) echo unknown 1;;
       esac;;
  esac
}
# Detected family into GPU_DETECTED, with GPU_DRV and GPU_NAME.
gpu_detect(){
  local r node sdrv idrv gid compat vendor fam rank f2 r2 best=-1 io p a
  GPU_DETECTED=none; GPU_DRV=""; GPU_NAME=""
  io=$(gpu_ioctl_probe)
  for r in /sys/class/drm/renderD*; do
    [ -e "$r" ] || continue
    node=${r##*/}
    sdrv=$(basename "$(readlink -f "$r/device/driver" 2>/dev/null)" 2>/dev/null)
    [ -e "$r/device/driver" ] || sdrv=-
    idrv=$(printf '%s\n' "$io" | awk -v n="$node" '$1 == n {print $2}')
    gid=$(printf '%s\n' "$io" | awk -v n="$node" '$1 == n {print $3}')
    compat=$(tr '\0' ' ' 2>/dev/null < "$r/device/of_node/compatible")
    vendor=$(cat "$r/device/vendor" 2>/dev/null)
    # Kernel's own name wins; tyr registers as panthor, so its sysfs name is kept for display
    read -r fam rank <<< "$(gpu_family_of "${idrv:-$sdrv}" "$compat" "$gid" "$vendor")"
    [ "$fam" = unknown ] && [ "$sdrv" != - ] && [ -n "$idrv" ] && [ "$idrv" != "$sdrv" ] \
      && read -r f2 r2 <<< "$(gpu_family_of "$sdrv" "$compat" "$gid" "$vendor")" && [ "$f2" != unknown ] && { fam=$f2; rank=$r2; }
    [ "$rank" -gt "$best" ] || continue
    best=$rank; GPU_DETECTED=$fam
    GPU_DRV=${idrv:-$sdrv}; [ "$sdrv" = tyr ] && GPU_DRV=tyr
    [ "$GPU_DRV" = - ] && GPU_DRV=""
    GPU_NAME=""
    case "$fam/$gid" in
      mali-csf*/[0-9a-f]*)
        p=$(( 16#$gid >> 16 & 0xf )); a=$(( 16#$gid >> 28 ))
        case "$a.$p" in
          10.2) GPU_NAME=Mali-G710;; 10.3) GPU_NAME=Mali-G510;; 10.4) GPU_NAME=Mali-G310;; 10.7) GPU_NAME=Mali-G610;;
          11.*) GPU_NAME=Mali-G715/G615;; 12.*) GPU_NAME=Mali-G720/G620;; 13.*) GPU_NAME=Mali-G725/G625/G925;; 14.*) GPU_NAME=Mali-G1;;
          *) GPU_NAME="Mali (arch v$a)";;
        esac;;
      mali-*/[0-9a-f]*) GPU_NAME="Mali (product 0x$gid)";;
    esac
    [ -n "$GPU_NAME" ] || case "$fam" in
      mali-csf-v10) GPU_NAME="Mali-G610 class";;
      mali-*) GPU_NAME=Mali;;
      adreno-legacy) GPU_NAME="Adreno 5xx or older";;
      adreno*) GPU_NAME="Adreno${fam#adreno}"; GPU_NAME=${GPU_NAME/-a/ };;
      apple-agx) GPU_NAME="Apple AGX";;
      broadcom-v3d71) GPU_NAME="VideoCore VII";;
      broadcom-v3d42) GPU_NAME="VideoCore VI";;
      broadcom-vc4) GPU_NAME="VideoCore IV";;
      vivante) GPU_NAME=Vivante;;
      img-powervr) GPU_NAME="Imagination PowerVR";;
      amd-*) GPU_NAME=AMD;;
      nvidia-*) GPU_NAME=NVIDIA;;
      intel) GPU_NAME=Intel;;
      virtio-gpu) GPU_NAME="virtio GPU";;
      *) GPU_NAME="unknown GPU";;
    esac
  done
  # Arm's closed kbase driver: /dev/mali0, no render node
  if [ "$best" -le 0 ] && { [ -e /dev/mali0 ] || [ -e /sys/class/misc/mali0 ]; }; then
    GPU_DETECTED=mali-kbase; GPU_DRV=mali_kbase; GPU_NAME=Mali
  fi
  [ "$GPU_DETECTED" = none ] && { GPU_DRV=""; GPU_NAME="no GPU"; }
  return 0
}
# PCI vendor id of detected GPU family as vulkaninfo prints it; status 1 for other families.
gpu_vendor_id(){
  case "$GPU_DETECTED" in
    mali-*) echo 0x13b5;; adreno*) echo 0x5143;; broadcom-*) echo 0x14e4;; apple-agx) echo 0x106b;;
    img-powervr) echo 0x1010;; amd-*) echo 0x1002;; nvidia-*) echo 0x10de;; intel) echo 0x8086;; virtio-gpu) echo 0x1af4;;
    *) return 1;;
  esac
}
# Vulkan driver of detected GPU from vulkaninfo, when installed: GPU_VK "<driver> <version>", Vulkan device name into GPU_NAME.
gpu_vulkan(){
  local want out
  GPU_VK=""
  command -v vulkaninfo >/dev/null 2>&1 || return 0
  want=$(gpu_vendor_id) || return 0
  out=$(timeout 20 vulkaninfo --summary 2>/dev/null | awk -v w="$want" '
    /^GPU[0-9]+:/ { if (v == w && !done) { print n "\t" d " " ver; done = 1 } v = n = d = ver = "" }
    $1 == "vendorID" { v = tolower($3) }  $1 == "deviceName" { sub(/^[^=]*= /, ""); n = $0 }
    $1 == "driverName" && d == "" { d = tolower($3) }  $1 == "driverVersion" { ver = $3 }
    $1 == "driverID" { d = $3; sub(/^DRIVER_ID_(MESA_)?/, "", d)
      d = d == "INTEL_OPEN_SOURCE_MESA" ? "anv" : d == "IMAGINATION_OPEN_SOURCE_MESA" ? "pvr" : d == "NVIDIA_PROPRIETARY" ? "nvidia" : tolower(d) }
    END { if (v == w && !done) print n "\t" d " " ver }')
  [ -n "$out" ] || return 0
  GPU_VK=${out#*$'\t'}
  out=${out%%$'\t'*}; out=${out% (*)}
  [ -n "$out" ] && GPU_NAME=$out
  return 0
}
VK_SPOOF_FEATURES="fillModeNonSolid geometryShader multiViewport shaderClipDistance shaderCullDistance robustBufferAccess2"
# --detect only: features vk-spoof reports, split into native / missing for detected GPU (full vulkaninfo, layer off).
gpu_vk_features(){
  local want out
  command -v vulkaninfo >/dev/null 2>&1 || { echo "vulkan features: unknown (vulkaninfo not installed)"; return 0; }
  if [ -z "${GPU_VK:-}" ] || ! want=$(gpu_vendor_id); then echo "vulkan features: unknown (no Vulkan driver for this GPU)"; return 0; fi
  out=$(env -u STEAM_ARM_VK_SPOOF STEAM_ARM_VK_SPOOF_DISABLE=1 timeout 20 vulkaninfo 2>/dev/null | awk -v w="$want" -v names="$VK_SPOOF_FEATURES" '
    function flush(   i, nat, mis) {
      if (!g || v != w || done) return
      for (i = 1; i <= n; i++) if (f[nm[i]] == "true") nat = nat " " nm[i]; else mis = mis " " nm[i]
      printf "vulkan features native: %s\nvulkan features missing: %s\n", nat == "" ? "none" : substr(nat, 2), mis == "" ? "none" : substr(mis, 2)
      done = 1
    }
    BEGIN { n = split(names, nm, " "); for (i = 1; i <= n; i++) want[nm[i]] = 1 }
    /^GPU[0-9]+:[ \t]*$/ { flush(); g = 1; v = ""; for (k in f) delete f[k]; next }
    g && $1 == "vendorID" { v = tolower($3) }
    g && ($1 in want) && $2 == "=" { f[$1] = $3 }
    END { flush() }')
  echo "${out:-vulkan features: unknown (vulkaninfo listed no features for this GPU)}"
}
# Default states (1 on, 0 off) of vk-spoof, gpu-in-emulation, glx-lax for family $1, with GPU_NOTE and GPU_WARN.
gpu_defaults(){
  GPU_NOTE=""; GPU_WARN=""
  case "$1" in
    mali-csf-v10) GPU_DEF="1 1 1";;
    mali-csf-v11) GPU_DEF="0 1 1"; GPU_NOTE="Mali-G615/G715 (arch v11): untested; PanVK (Mesa Vulkan) loads here only with PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1";;
    mali-csf-5thgen) GPU_DEF="0 1 1"; GPU_NOTE="Mali 5th gen: untested; PanVK (Mesa Vulkan) loads here only with PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1";;
    mali-csf-g1) GPU_DEF="0 0 1"; GPU_NOTE="Mali-G1 (arch v14): needs Mesa 26.2 or newer; vk-spoof and gpu-in-emulation off by default, untested";;
    mali-csf) GPU_DEF="0 0 1"; GPU_NOTE="Mali model not in this setup's table; titles run through forwarding";;
    mali-valhall-jm|mali-bifrost|mali-midgard|mali-panfrost)
      GPU_DEF="0 1 1"; GPU_NOTE="no default Vulkan driver for this Mali: native OpenGL titles; Windows titles unlikely";;
    mali-utgard) GPU_DEF="0 0 1"; GPU_NOTE="Mali-400/450: not suitable for Steam games";;
    mali-kbase) GPU_DEF="0 0 0"; GPU_WARN="closed Mali driver found: install needs Mesa's panfrost/panthor kernel driver";;
    adreno-a8xx|adreno-a7xx|adreno-a6xx|adreno)
      GPU_DEF="0 0 1"; GPU_NOTE="Adreno: Windows titles through DXVK expected to work; x86 Adreno drivers for 32-bit titles not included yet";;
    adreno-a702) GPU_DEF="0 0 1"; GPU_NOTE="Adreno 702: entry-level GPU, Vulkan too limited for most Windows titles";;
    adreno-legacy) GPU_DEF="0 0 1"; GPU_NOTE="Adreno 5xx or older: no Vulkan driver; native OpenGL titles only";;
    apple-agx) GPU_DEF="0 0 1"; GPU_NOTE="Apple GPU: 16K-page kernel not supported; setup does not set up 4K VM (muvm)";;
    broadcom-v3d71|broadcom-v3d42) GPU_DEF="0 0 1"; GPU_NOTE="Raspberry Pi GPU: Vulkan too limited for most Windows titles";;
    broadcom-vc4) GPU_DEF="0 0 1"; GPU_NOTE="VideoCore IV (Raspberry Pi 0-3): not supported";;
    vivante) GPU_DEF="0 0 1"; GPU_NOTE="Vivante GPU: no Vulkan driver, OpenGL ES class; most titles do not run";;
    img-powervr) GPU_DEF="0 0 0"; GPU_NOTE="PowerVR: Vulkan driver in development; OpenGL through Zink; glx-lax not applicable";;
    amd-radv) GPU_DEF="0 0 1"; GPU_NOTE="AMD GPU: forwarding covers it; x86 root filesystem's Mesa has its drivers too";;
    nvidia-nouveau) GPU_DEF="0 0 1"; GPU_NOTE="NVIDIA GPU on nouveau: forwarding covers it; x86 root filesystem's Mesa has its drivers too";;
    intel) GPU_DEF="0 0 1"; GPU_NOTE="Intel GPU: forwarding covers it; x86 root filesystem's Mesa has its drivers too";;
    amd-radeon) GPU_DEF="0 0 1"; GPU_NOTE="legacy radeon driver: OpenGL only, too old for most titles";;
    nvidia-prop) GPU_DEF="0 0 0"; GPU_NOTE="NVIDIA driver: glx-lax not applicable";;
    virtio-gpu) GPU_DEF="0 0 1"; GPU_NOTE="virtual machine";;
    none) GPU_DEF="0 0 1"; GPU_WARN="no GPU driver found: software rendering only";;
    *) GPU_DEF="0 0 1"; GPU_NOTE="unknown GPU (driver ${GPU_DRV:-none}): safe defaults";;
  esac
}
gpu_known(){ local f; for f in $GPU_FAMILIES; do [ "$f" = "$1" ] && return 0; done; return 1; }
# Family in use: env GPU_FAMILY, else family saved by hand on an earlier run, else detected; then component defaults.
gpu_pick(){
  local d1 d2 d3 env=${GPU_FAMILY:-}
  gpu_detect
  GPU_SRC=detected; GPU_FAMILY=$GPU_DETECTED
  local valid; valid=$(printf '%s auto' "$GPU_FAMILIES" | tr -s ' \n' ' ' | fold -s -w 78 | sed 's/ *$//; s/^/       /')
  if [ -n "$env" ] && [ "$env" != auto ] && ! gpu_known "$env" && [ "${MODE:-}" = detect ]; then
    # --detect only reports: detected family, with the valid values
    warn "GPU_FAMILY=$env is not a known GPU family; detected family shown. Valid values:
$valid" >&2
  elif [ -n "$env" ] && [ "$env" != auto ]; then
    gpu_known "$env" || die "GPU_FAMILY=$env is not a known GPU family. Valid values:
$valid"
    GPU_FAMILY=$env; GPU_SRC=user
  elif [ -z "$env" ] && [ "$(conf_get GPU_FAMILY_SET)" = user ] && gpu_known "$(conf_get GPU_FAMILY)"; then
    GPU_FAMILY=$(conf_get GPU_FAMILY); GPU_SRC=user
  fi
  gpu_defaults "$GPU_FAMILY"
  read -r d1 d2 d3 <<< "$GPU_DEF"
  [ "$d1" = 1 ] || eval "$(var_of vk-spoof)=0"
  [ "$d2" = 1 ] || eval "$(var_of gpu-in-emulation)=0"
  [ "$d3" = 1 ] || eval "$(var_of glx-lax)=0"
}
# Plain installer line: GPU: <name> (<kernel driver>[, Vulkan: <driver> <version>])
gpu_line(){
  local d=${GPU_DRV:-no driver}
  [ -n "${GPU_VK:-}" ] && d="$d, Vulkan: $GPU_VK"
  GPU_LINE="GPU: $GPU_NAME ($d)"
  GPU_MSG=${GPU_WARN:-$GPU_NOTE}
}
# --detect: one "key: value" per line.
gpu_report(){
  local c v
  echo "$GPU_LINE"
  if [ "$GPU_SRC" = user ]; then echo "family: $GPU_FAMILY (set by user)"; else echo "family: $GPU_FAMILY"; fi
  echo "detected family: $GPU_DETECTED"
  echo "gpu: $GPU_NAME"
  echo "kernel driver: ${GPU_DRV:-none}"
  if [ -n "$GPU_VK" ]; then v=$GPU_VK
  elif command -v vulkaninfo >/dev/null 2>&1; then v="none found"
  else v="unknown (vulkaninfo not installed)"; fi
  echo "vulkan: $v"
  gpu_vk_features
  echo "driver archive: $PROVIDER_FILE $PROVIDER_SHA256"
  echo "cpu: $(cpu_line)"
  client_pick
  case "$CLIENT:$CLIENT_SET" in
    x86:auto) echo "client: x86 (CPU without Armv8.1 atomics)";;
    x86:*) echo "client: x86 (chosen by hand)";;
    arm64:user) cpu_lse && echo "client: arm64" || echo "client: arm64 (chosen by hand on Armv8.0 CPU)";;
    *) echo "client: arm64";;
  esac
  echo "page size: $(getconf PAGESIZE 2>/dev/null || echo unknown)"
  v=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"')
  echo "distro: ${v:-unknown}"
  for c in $COMPONENTS; do
    if eval "[ \"\$$(var_of "$c")\" = 1 ]"; then v=on; else v=off; fi
    echo "component $c: $v"
  done
  [ -n "$GPU_NOTE" ] && echo "note: $GPU_NOTE"
  [ -n "$GPU_WARN" ] && echo "warning: $GPU_WARN"
  kde_wayland && echo "note: $KDE_HINT"
  return 0
}
KDE_HINT="KDE Plasma on Wayland: controllers can raise \"Remote control requested\" prompt; optional component kde-input-prompt stops it (README, FAQ)"
# Settings menu, installed as /usr/local/bin/steam-arm-config.
menu_app(){ cat <<'STEAMARMCONFIG'
#!/bin/bash
# steam-arm-config: menu-driven settings for Steam ARM (built-in screens, dialog, whiptail or plain prompts). See --help.
set -u

SA_VERSION=2.3.1
SA_DOCS=https://github.com/Scrumpper/Steam-ARM
SA_CONF=/etc/steam-arm/steam-arm.conf
SA_TITLES_SHARE=/usr/local/share/steam-arm/titles.conf
SA_TITLES_ETC=/etc/steam-arm/titles.conf
SA_LAUNCHER=/usr/local/bin/steam-arm
SA_COMPATMAP=/usr/local/bin/steam-arm-compatmap
SA_COMPATMAP_PY=/usr/local/lib/steam-arm-compatmap.py
SA_AUTOBUILD_PY=/usr/local/lib/steam-arm-autobuild.py
SA_APPINFO_PY=/usr/local/lib/steam-arm-appinfo.py
SA_GE_PY=/usr/local/lib/steam-arm-geproton.py
SA_REMOTEPLAY=/usr/local/bin/steam-arm-remoteplay
SA_SHARE_INSTALLER=/usr/local/share/steam-arm/steam-arm-install.sh
SA_RFS=/opt/fex-rootfs/Ubuntu_24_04
SA_MALI=/opt/fex-rootfs/Ubuntu_24_04-mali
# Published driver archive, for installers whose --detect prints no "driver archive:" line.
SA_PROVIDER_FILE=steam-arm-fex-mesa-26.1.8-x86_64-i386.tar.zst
SA_PROVIDER_SHA=3ba2c461bc069dc702af7f8ee81e7c5343604148977bdddde41b1d3826cb7495
# As root: root's own home and a private temp folder (sudo -E and su keep the caller's folders, which that account can change).
SA_TMP=""
if [ "$(id -u)" = 0 ]; then
  SA_ROOTHOME=$(getent passwd 0 | cut -d: -f6); SA_ROOTHOME=${SA_ROOTHOME:-/root}
  SA_TMP=$(mktemp -d /tmp/steam-arm.XXXXXX) || { echo "steam-arm-config: could not create a folder in /tmp; free some space and run this again" >&2; exit 1; }
  trap 'rm -rf "$SA_TMP"' EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM
fi
# Report goes to the home of the account that runs this menu (the sudo caller when run through sudo).
if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  SA_REPORT="$(getent passwd "$SUDO_USER" | cut -d: -f6)/steam-arm-report.txt"
elif [ "$(id -u)" = 0 ]; then
  SA_REPORT="$SA_ROOTHOME/steam-arm-report.txt"
else
  SA_REPORT="${HOME:-/root}/steam-arm-report.txt"
fi
# Setup logs and temporary files: private folders, never fixed names in /tmp.
if [ "$(id -u)" = 0 ]; then SA_CACHE="$SA_ROOTHOME/.cache/steam-arm"
else SA_CACHE="${XDG_CACHE_HOME:-${HOME:-/root}/.cache}/steam-arm"; fi
SA_SETUP_LOG=""
SA_RULE_HIDRAW=/etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules
SA_RULE_DEDUP=/etc/udev/rules.d/71-steam-arm-xpad-dedup.rules
SA_PADXBOX_UNIT=/etc/systemd/system/steam-arm-pad-xbox.service
SA_FEXLOG_GLOB='/tmp/fex-compat-tool-*.log /tmp/steam-arm-run-*.log'
# Valve's x86 Proton for Windows titles on the x86 client (name not yet confirmed on hardware).
X86_PROTON=proton_experimental
# Proton ARM64 under the name Steam lists in its Compatibility list (proton-stable-arm64 runs but shows blank there).
ARM64_PROTON=proton_11-arm64
SA_CPUFREQ=/sys/devices/system/cpu/cpufreq
# Fallback component list when the installer cannot be asked.
SA_COMPONENTS="glx-lax vk-spoof gpu-in-emulation shader-cache physx-skip map-count xpad-dedup pad-hidraw pad-xbox desktop desktop-mode icon-bigpicture icon-desktop tray kde-input-prompt page-size"
SA_DEFAULT_OFF="pad-xbox shader-cache kde-input-prompt"
SA_MALI_ONLY="vk-spoof gpu-in-emulation"
SA_TOOL_RE='^(FEX|Proton|Steam Linux Runtime|Steamworks Common|Steamworks Shared)'

DIALOG=""
BT=""
DETECT_CACHE=""
DETECT_DONE=0
SUDO_OK=0

# ===========================================================================
# Common helpers
# ===========================================================================
have(){ command -v "$1" >/dev/null 2>&1; }
self_path(){ readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}"; }
strip_ansi(){ sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
dot(){ case "$(locale charmap 2>/dev/null)" in UTF-8|utf8) printf ' \xc2\xb7 ';; *) printf ' | ';; esac; }
trim(){ sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
# Temp file (tmpf -d: folder): root's private folder, else XDG_RUNTIME_DIR or TMPDIR when this account owns and can write it, else /tmp.
tmpf(){
  local d
  if [ -n "$SA_TMP" ]; then mktemp "$@" "$SA_TMP/steam-arm-config.XXXXXX"; return; fi
  for d in "${XDG_RUNTIME_DIR:-}" "${TMPDIR:-}" /tmp; do
    if [ -z "$d" ] || [ ! -d "$d" ] || [ ! -w "$d" ]; then continue; fi
    if [ "$d" != /tmp ] && [ ! -O "$d" ]; then continue; fi
    mktemp "$@" "$d/steam-arm-config.XXXXXX" 2>/dev/null && return 0
  done
  return 1
}
TMP_FAIL="No temporary file could be created (XDG_RUNTIME_DIR, TMPDIR and /tmp tried). Free some space in /tmp, then try again."
# Comma list wrapped to 55 columns, continuation lines indented under a 15-column label.
wrap_list(){ sed 's/,/, /g' | fold -s -w 55 | sed '2,$s/^/               /'; }
# Free text value of a 15-column row: wrapped at 55 (-h: hard breaks, for paths), continuation lines indented.
wrap_row(){ if [ "${1:-}" = -h ]; then fold -w 55; else fold -s -w 55 | sed 's/ *$//'; fi | sed '2,$s/^/               /'; }

conf_get(){ sed -n "s/^$1=//p" "$SA_CONF" 2>/dev/null | tail -1 | sed "s/^[\"']//; s/[\"']\$//"; }
# Set one key in the settings file, keeping every other line; atomic.
conf_set(){
  local t
  mkdir -p "$(dirname "$SA_CONF")" || return 1
  [ -f "$SA_CONF" ] || : > "$SA_CONF" || return 1
  t=$(mktemp "$SA_CONF.XXXXXX") || return 1
  if awk -v k="$1=" -v v="$1=$2" 'index($0, k) == 1 { if (!d) print v; d = 1; next } { print } END { if (!d) print v }' \
       "$SA_CONF" > "$t" && chmod 644 "$t" && mv -f "$t" "$SA_CONF"; then return 0; fi
  rm -f "$t"; return 1
}
conf_del(){
  local t; grep -qs "^$1=" "$SA_CONF" || return 0
  t=$(mktemp "$SA_CONF.XXXXXX") || return 1
  if awk -v k="$1=" 'index($0, k) != 1' "$SA_CONF" > "$t" && chmod 644 "$t" && mv -f "$t" "$SA_CONF"; then return 0; fi
  rm -f "$t"; return 1
}

is_installed(){ [ -x "$SA_LAUNCHER" ] && [ -f "$SA_CONF" ]; }

game_user(){
  # GU_OVERRIDE: account picked in Install / Setup, while its client is checked
  [ -n "${GU_OVERRIDE:-}" ] && { echo "$GU_OVERRIDE"; return; }
  local u; u=$(conf_get GAMEUSER)
  [ -n "$u" ] && getent passwd "$u" >/dev/null 2>&1 && { echo "$u"; return; }
  [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != root ] && { echo "$SUDO_USER"; return; }
  [ "$(id -u)" != 0 ] && { id -un; return; }
  getent passwd 1000 2>/dev/null | cut -d: -f1
}
game_home(){ getent passwd "$(game_user)" 2>/dev/null | cut -d: -f6; }
# Client folder: ARMHOME_DIR relative to the game home (setup refuses other forms, so they read as the default).
armhome_rel(){
  local d; d=$(conf_get ARMHOME_DIR)
  case "$d" in ''|/*|..|../*|*/..|*/../*) d=.local/share/steam-arm;; esac
  echo "${d%/}"
}
arm_home(){ echo "$(game_home)/$(armhome_rel)"; }
steam_dir(){ echo "$(arm_home)/.local/share/Steam"; }
titles_user(){ echo "$(arm_home)/.config/steam-arm/titles.conf"; }
titles_files(){ printf '%s\n' "$SA_TITLES_SHARE" "$SA_TITLES_ETC" "$(titles_user)"; }
# Shorten home paths for display.
tilde(){ local h; h=$(game_home); if [ -n "$h" ]; then sed "s#${h}#~#g"; else cat; fi; }

# Game account's client only (another account's Steam reads and writes its own files).
steam_running(){
  local u; u=$(game_user)
  if [ -n "$u" ] && id "$u" >/dev/null 2>&1; then pgrep -u "$u" -x steam >/dev/null 2>&1; else pgrep -x steam >/dev/null 2>&1; fi
}
# Game of the game account running (Steam starts every title under its reaper).
game_running(){
  local u; u=$(game_user)
  [ -n "$u" ] && pgrep -u "$u" -f 'reaper SteamLaunch' >/dev/null 2>&1
}

# Installer: explicit env, packaged command, embedded copy, file beside this app.
find_installer(){
  local d
  if [ -n "${STEAM_ARM_INSTALLER:-}" ] && [ -f "$STEAM_ARM_INSTALLER" ]; then echo "$STEAM_ARM_INSTALLER"; return 0; fi
  if have steam-arm-setup; then command -v steam-arm-setup; return 0; fi
  [ -f "$SA_SHARE_INSTALLER" ] && { echo "$SA_SHARE_INSTALLER"; return 0; }
  d=$(dirname "$(self_path)")
  [ -f "$d/steam-arm-install.sh" ] && { echo "$d/steam-arm-install.sh"; return 0; }
  return 1
}
# Run installer with args (caller adds sudo/env).
installer_cmd(){
  local i; i=$(find_installer) || return 1
  case "$i" in *.sh) echo "bash"; echo "$i";; *) echo "$i";; esac
}

# ===========================================================================
# Detection
# ===========================================================================
# Raw --detect output of installer, for family $1 (GPU_FAMILY override) or detected (cached); empty when unsupported.
detect_raw(){
  local -a cmd; local out=""
  if [ -z "${1:-}" ] && [ "$DETECT_DONE" = 1 ]; then printf '%s\n' "$DETECT_CACHE"; return; fi
  mapfile -t cmd < <(installer_cmd)
  if [ "${#cmd[@]}" -gt 0 ]; then
    if [ -n "${1:-}" ]; then out=$(timeout 60 env GPU_FAMILY="$1" "${cmd[@]}" --detect 2>/dev/null </dev/null | strip_ansi)
    else out=$(timeout 60 "${cmd[@]}" --detect 2>/dev/null </dev/null | strip_ansi); fi
  fi
  printf '%s' "$out" | grep -qiE '^(detected )?family[:=]|^page size[:=]' || out=""
  [ -z "${1:-}" ] && { DETECT_DONE=1; DETECT_CACHE=$out; }
  printf '%s\n' "$out"
}
# Last value of key(s) in "key: value" / "KEY=value" lines on stdin; case, spaces, _ and - ignored.
detect_parse(){
  awk -v want="$*" '
    BEGIN { n = split(tolower(want), w, " "); for (i = 1; i <= n; i++) ok[w[i]] = 1 }
    { p = match($0, /[:=]/); if (!p) next
      k = tolower(substr($0, 1, p - 1)); gsub(/[ \t_-]/, "", k)
      if (k in ok) { v = substr($0, p + 1); sub(/^[ \t"]+/, "", v); sub(/[ \t"]+$/, "", v); r = v; f = 1 } }
    END { if (f) print r }'
}
detect_get(){ detect_raw | detect_parse "$@"; }
# Note and warning lines ("note: x", "warning: x", or indented lines under "notes:").
detect_notes(){
  detect_raw | awk '
    { l = $0; p = match(l, /[:=]/); k = p ? tolower(substr(l, 1, p - 1)) : ""; gsub(/[ \t_-]/, "", k) }
    k ~ /^(notes?|warnings?)$/ { v = substr(l, p + 1); sub(/^[ \t]+/, "", v)
      if (v != "") print (k ~ /^warn/ ? "Warning: " : "") v; inn = 1; next }
    inn && /^[ \t]+[^ \t]/ { sub(/^[ \t]+(- )?/, ""); print; next }
    { inn = 0 }'
}
# Components on by default for family $1 ("" = detected): "component NAME: on" lines, or a "defaults: a,b" line.
detect_components(){
  detect_raw "${1:-}" | awk '
    tolower($1) == "component" { n = $2; sub(/:$/, "", n); if (tolower($3) == "on") { printf "%s%s", s, n; s = " " } ; c = 1; next }
    { p = match($0, /[:=]/); k = p ? tolower(substr($0, 1, p - 1)) : ""; gsub(/[ \t_-]/, "", k)
      if (k == "defaults" || k == "defaultcomponents") { d = substr($0, p + 1); gsub(/[ \t]/, "", d); gsub(/,/, " ", d) } }
    END { if (!c && d != "") printf "%s", d; print "" }'
}

hw_model(){
  local m
  m=$( { tr -d '\0' < "/proc/device-tree/model"; } 2>/dev/null)
  [ -z "$m" ] && m=$(cat "/sys/class/dmi/id/sys_vendor" "/sys/class/dmi/id/product_name" 2>/dev/null | tr '\n' ' ' | trim)
  echo "${m:-unknown}"
}
hw_soc(){
  local c
  c=$(tr '\0' '\n' < "/proc/device-tree/compatible" 2>/dev/null | tail -1)
  if [ -n "$c" ]; then echo "${c#*,}" | tr '[:lower:]' '[:upper:]'; return; fi
  grep -m1 -E '^(model name|Hardware)' "/proc/cpuinfo" 2>/dev/null | cut -d: -f2- | trim
}
# Kernel drivers bound to DRM devices (display-only drivers included).
gpu_drivers(){
  local d
  for d in /sys/class/drm/card*/device/driver /sys/class/drm/renderD*/device/driver; do
    [ -L "$d" ] && basename "$(readlink "$d")"
  done | sort -u
  [ -e "/sys/class/misc/mali0" ] && echo mali_kbase
}
# Installer GPU family id of a kernel driver (fallback when installer gives none).
family_of_driver(){ case "$1" in
  panthor|tyr)  case "$(tr '\0' ' ' < "/proc/device-tree/compatible" 2>/dev/null)" in
                  *rk3588*) echo mali-csf-v10;; *mt8196*) echo mali-csf-5thgen;; *) echo mali-csf;; esac;;
  panfrost)     echo mali-panfrost;;
  lima)         echo mali-utgard;;
  mali_kbase)   echo mali-kbase;;
  msm|msm_dpu|adreno) echo adreno;;
  v3d)          case "$(tr '\0' ' ' < "/proc/device-tree/compatible" 2>/dev/null)" in *2712*) echo broadcom-v3d71;; *) echo broadcom-v3d42;; esac;;
  vc4|vc4-drm)  echo broadcom-vc4;;
  etnaviv)      echo vivante;;
  powervr)      echo img-powervr;;
  asahi)        echo apple-agx;;
  amdgpu)       echo amd-radv;;
  radeon)       echo amd-radeon;;
  nouveau)      echo nvidia-nouveau;;
  nvidia|nvidia-drm) echo nvidia-prop;;
  i915|xe)      echo intel;;
  virtio_gpu|virtio-pci) echo virtio-gpu;;
  *) return 1;;
esac; }
# GPU kernel driver: installer's answer, else first GPU driver bound in sysfs.
gpu_driver(){
  local v d
  v=$(detect_get kerneldriver); [ -n "$v" ] && { echo "$v"; return; }
  for d in $(gpu_drivers); do family_of_driver "$d" >/dev/null && { echo "$d"; return; }; done
  echo none
}
gpu_family(){
  local v
  v=$(detect_get family); [ -n "$v" ] && { echo "$v" | awk '{print $1}'; return; }
  family_of_driver "$(gpu_driver)" || echo none
}
gpu_name(){
  local v; v=$(detect_get gpu | sed 's/ (.*//')
  [ -n "$v" ] && { echo "$v"; return; }
  vk_summary | cut -d, -f1
}
is_mali(){ case "$1" in mali-kbase|mali-utgard) return 1;; mali-*) return 0;; esac; return 1; }
family_label(){
  local v
  case "$1" in
    mali-kbase) v="Mali, closed driver";; mali-*) v="Mali";; adreno*) v="Adreno";; apple-agx) v="Apple GPU";;
    broadcom-*) v="Raspberry Pi VideoCore";; vivante) v="Vivante";; img-powervr) v="PowerVR";;
    amd-*) v="AMD";; nvidia-*) v="NVIDIA";; intel) v="Intel";; virtio-gpu) v="Virtual GPU";;
    none|'') echo "no GPU driver found"; return;; *) v="unknown GPU";;
  esac
  echo "$v ($1)"
}
page_size(){ getconf PAGESIZE 2>/dev/null || echo 4096; }
# page-size part applies on Raspberry Pi 5 class boards (16K kernel), or while its boot line is in place.
page_size_applies(){
  case "$(hw_model)" in
    "Raspberry Pi 5"*|"Raspberry Pi Compute Module 5"*) return 0;;
    "Raspberry Pi"*) [ "$(page_size)" != 4096 ] && return 0;;
  esac
  grep -qs '^# steam-arm-setup page-size:' /boot/firmware/config.txt /boot/config.txt
}
page_label(){ case "$1" in 4096) echo "4K";; 16384) echo "16K";; 65536) echo "64K";; *) echo "$1 bytes";; esac; }
# Page-size verdict for title bar: size in use, 4K kernel switch made by setup, pending reboot.
page_status(){
  local ps sw; ps=$(page_size)
  grep -qs '^# steam-arm-setup page-size:' /boot/firmware/config.txt /boot/config.txt && sw=1 || sw=0
  if [ "$ps" = 4096 ]; then
    [ "$sw" = 1 ] && echo "pages 4K (setup kernel switch)" || echo "pages 4K ok"
  elif [ "$sw" = 1 ]; then echo "pages $(page_label "$ps"): reboot for 4K"
  else echo "pages $(page_label "$ps"): needs 4K"
  fi
}
# Vulkan driver: installer's answer, else first non-CPU device from vulkaninfo.
vk_summary(){
  local v
  v=$(detect_get vulkan); [ -n "$v" ] && { echo "$v"; return; }
  have vulkaninfo || { echo "unknown (vulkaninfo not installed)"; return; }
  timeout 15 vulkaninfo --summary 2>/dev/null | awk -F'= *' '
    /^GPU[0-9]+:/ { if (name != "" && type !~ /CPU/) exit; name = drv = info = api = type = "" }
    /apiVersion/ { api = $2 } /deviceType/ { type = $2 } /deviceName/ { name = $2 }
    /driverName/ { drv = $2 } /driverInfo/ { info = $2 }
    END { if (name == "" || type ~ /CPU/) print "none found"; else printf "%s, %s %s, API %s\n", name, drv, info, api }'
}
# vk_ok [summary]: summary given, or read now
vk_ok(){ case "${1-$(vk_summary)}" in none*|unknown*|*llvmpipe*|*lavapipe*) return 1;; esac; return 0; }
distro(){ sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"'; }
pkg_ver(){ dpkg-query -W -f='${Version}\n' "$@" 2>/dev/null | grep -v '^$' | head -1; }
mesa_ver(){
  local v
  have glxinfo && v=$(timeout 10 glxinfo -B 2>/dev/null | grep -o 'Mesa [0-9][0-9.]*' | head -1 | cut -d' ' -f2)
  [ -z "${v:-}" ] && v=$(pkg_ver libgl1-mesa-dri mesa-libgallium libglx-mesa0)
  echo "${v:-unknown}"
}
# FEX-2608 dropped FEXInterpreter and FEX 2609.1 has no --version: FEXGetConfig, FEX, FEXInterpreter, then package.
fex_ver(){
  local v='' c
  for c in FEXGetConfig FEX FEXInterpreter; do
    have "$c" && v=$("$c" --version 2>/dev/null | grep -m1 '[0-9]') && [ -n "$v" ] && break
    v=
  done
  case "$v" in [0-9]*) v="FEX-$v";; esac
  [ -z "${v:-}" ] && v=$(dpkg-query -W -f='${Package} ${Version}\n' 'fex-emu*' 2>/dev/null | grep -v ' $' | head -1)
  echo "${v:-not installed}"
}
# Armv8.1 atomics (LSE) on first CPU; empty Features line counts as present.
cpu_has_lse(){
  local f; f=$(grep -m1 '^Features' "/proc/cpuinfo" 2>/dev/null)
  [ -z "$f" ] && return 0
  case " ${f#*:} " in *" atomics "*) return 0;; esac; return 1
}
# Native client passed setup's check on this CPU (CLIENT_PROBE VER:ok).
probe_ok(){ case "$(conf_get CLIENT_PROBE)" in *:ok) return 0;; esac; return 1; }
# Client type setup picks without --client (as its client_pick, then step 9 switch back): arm64 or x86.
planned_client(){
  local c; c=$(conf_get CLIENT)
  if ! cpu_has_lse && [ "${STEAM_ARM_ALLOW_ARMV80:-0}" = 1 ]; then echo arm64
  elif [ "$(conf_get CLIENT_SET)" = user ] && { [ "$c" = arm64 ] || [ "$c" = x86 ]; }; then echo "$c"
  elif cpu_has_lse || probe_ok; then echo arm64
  else echo x86; fi
}
X86_MSG="This CPU has no Armv8.1 atomics (LSE). Valve's native ARM64 client
stops at start on it (steam-for-linux #13288), so setup installs
Valve's x86 client, run through emulation:
- first start downloads client files and takes several minutes;
  later starts are slower than native client
- client window drawn on CPU; games reach GPU through emulator's
  GL and Vulkan forwarding
- Windows titles use x86 Proton through emulation
Setup moves to native client by itself once Valve's build runs on
this CPU again (Maintenance > Client type)."
# CPU cores and Armv8 level, from setup --detect, else from /proc/cpuinfo.
cpu_info(){
  local c; c=$(detect_get cpu)
  [ -n "$c" ] && { echo "$c"; return; }
  if cpu_has_lse; then echo "$(nproc 2>/dev/null) cores, Armv8.1 or newer (LSE atomics)"
  else echo "$(nproc 2>/dev/null) cores, Armv8.0 (no LSE atomics)"; fi
}
# Valve's FEX tool version; x86 client uses system FEX instead.
fex_tool_row(){ if [ "$(client_type)" = x86 ]; then echo "not used (x86 client runs on system FEX)"; else fex_tool_ver; fi; }
# Client type with reason, as Information shows it.
client_label(){
  if [ "$(client_type)" = x86 ]; then
    if [ "$(conf_get CLIENT_SET)" = user ]; then echo "x86 through emulation (chosen by hand)"
    else echo "x86 through emulation (CPU without Armv8.1 atomics)"; fi
  elif ! cpu_has_lse && [ "$(conf_get CLIENT_SET)" = user ]; then echo "native ARM64 (chosen by hand on Armv8.0 CPU)"
  elif ! cpu_has_lse && probe_ok; then echo "native ARM64 (runs on this Armv8.0 CPU)"
  else echo "native ARM64"; fi
}
disk_free(){ df -h --output=avail,target "$1" 2>/dev/null | tail -1 | awk '{print $1 " free on " $2}'; }

# Hardware entries of the install flow: id|label|GPU family ("?" = asks which GPU).
hw_table(){ cat <<'HW'
rk3588|Rockchip RK3588 / RK3588S|mali-csf-v10
rk356x|Rockchip RK3566 / RK3568 / RK3576|mali-bifrost
mediatek|MediaTek (Mali)|?
snapdragon|Qualcomm Snapdragon (Adreno)|?
rpi5|Raspberry Pi 5|broadcom-v3d71
rpi4|Raspberry Pi 4|broadcom-v3d42
asahi|Apple Silicon (Asahi)|apple-agx
pc|PC graphics card (AMD/NVIDIA)|?
vm|Virtual machine|virtio-gpu
other|Other...|?
HW
}
# Board entry matching this system, empty when unknown.
hw_guess(){
  local c m
  c=$(tr '\0' ' ' < "/proc/device-tree/compatible" 2>/dev/null); m=$(hw_model)
  case "$c $m" in
    *rk3588*) echo rk3588;; *rk3566*|*rk3568*|*rk3576*) echo rk356x;;
    *"Raspberry Pi 5"*) echo rpi5;; *"Raspberry Pi 4"*) echo rpi4;;
    *mediatek*) echo mediatek;; *qcom*) echo snapdragon;; *apple,*) echo asahi;;
    *) case "$(gpu_family)" in virtio-gpu) echo vm;; amd-*|nvidia-*|intel) echo pc;; esac;;
  esac
}
hw_label(){ hw_table | awk -F'|' -v id="$1" '$1 == id { print $2 }'; }
hw_short(){ local m; m=$(hw_model); [ "$m" = unknown ] && m=$(hw_label "$(hw_guess)"); echo "${m:0:28}"; }

# ===========================================================================
# Settings readers
# ===========================================================================
# GFX_DEFAULT in settings: auto (or empty) = rules decide, a (or forward) = route A for all, b = route B for all.
gfx_default(){ case "$(conf_get GFX_DEFAULT)" in a|forward) echo a;; b) echo b;; *) echo auto;; esac; }
gfx_label(){ case "$1" in a) echo "Forwarding";; b) echo "Mali drivers";; *) echo "Automatic";; esac; }
gfx_default_label(){ case "$1" in a) echo "Forwarding for all";; b) echo "Mali drivers for all";; *) echo "Automatic";; esac; }
comps_on(){ conf_get COMPONENTS_ON | tr ',' ' '; }
# Parts on as setup would see them: saved choice; parts in neither saved list, and GPU parts not set by hand
# once the GPU family changed, at the recommended state (family not saved: GPU parts only turn off).
comps_effective(){
  local on off rec user prev fam c out="" g
  on=" $(comps_on) "; off=" $(conf_get COMPONENTS_OFF | tr ',' ' ') "
  user=",$(conf_get COMPONENTS_USER_SET),"; prev=$(conf_get COMPONENTS_FAMILY); fam=$(gpu_family)
  rec=" $(comp_recommended "$fam" yes) "
  for c in $(comp_all); do
    case "$c" in vk-spoof|gpu-in-emulation|glx-lax) g=1;; *) g=0;; esac
    if [ "$g" = 1 ] && [ "$prev" != "$fam" ] && [[ "$user" != *",$c,"* ]]; then
      if [ -z "$prev" ]; then [[ "$on" == *" $c "* && "$rec" == *" $c "* ]] && out="$out $c"
      else [[ "$rec" == *" $c "* ]] && out="$out $c"; fi
    elif [[ "$on" == *" $c "* ]]; then out="$out $c"
    elif [[ "$off" != *" $c "* && "$rec" == *" $c "* ]]; then out="$out $c"
    fi
  done
  echo "$out" | trim
}
comp_is_on(){ case " $(comps_on) " in *" $1 "*) return 0;; esac; return 1; }
installed_version(){
  local v; v=$(conf_get VERSION)
  [ -z "$v" ] && v=$(pkg_ver steam-arm-setup steam-arm)
  echo "${v:-unknown}"
}
client_channel(){
  local b; b=$(head -1 "$(steam_dir)/package/beta" 2>/dev/null | trim)
  echo "${b:-stable}"
}
fex_tool_ver(){
  local v; v=$(grep -o 'FEX-[0-9][0-9.]*' "$(steam_dir)/steamapps/common/FEX-Emu/VERSIONS.txt" 2>/dev/null | head -1)
  echo "${v:-not downloaded yet}"
}
# FEX tool has the code cache option (FEX-2609.1 or newer; FEX-2609 and FEX-2609-N-g... are 2609.0).
fex_cache_ok(){
  local v; v=$(fex_tool_ver); v=${v#FEX-}
  [[ "$v" =~ ^[0-9]{4}(\.[0-9]+)?$ ]] && [ "$(printf '%s\n' 2609.1 "$v" | sort -V | head -n 1)" = 2609.1 ]
}
mali_tree(){
  local m e="..."
  if [ -f "$SA_MALI/.steam-arm-mali" ]; then
    m=$(head -1 "$SA_MALI/.steam-arm-mali" 2>/dev/null)
    case "$(locale charmap 2>/dev/null)" in UTF-8|utf8) e="…";; esac
    case "$m" in custom\ *) m=${m#custom }; printf 'present (custom drivers, sha %s%s), ' "${m:0:12}" "$e";; *) printf 'present, ';; esac
    echo "$(du -shc "$SA_RFS" "$SA_MALI" 2>/dev/null | sed -n 2p | awk '{print $1}') extra (shared files counted once)"
  elif [ -d "$SA_MALI" ]; then echo "incomplete (run Update / Repair)"
  else echo "not installed"; fi
}
mali_ready(){ [ -f "$SA_MALI/.steam-arm-mali" ] && [ -f "$SA_MALI/graphics_provider.json" ]; }
# Published driver archive as "file sha256": installer's --detect line, else built-in constants.
da_pub(){
  local f h
  read -r f h _ <<<"$(detect_get driverarchive)"
  if [[ "$f" =~ ^[A-Za-z0-9._+-]+\.tar\.zst$ && "$h" =~ ^[0-9a-f]{64}$ ]]; then echo "$f $h"
  else echo "$SA_PROVIDER_FILE $SA_PROVIDER_SHA"; fi
}
# Driver archive source: short label (menu entry) and status row.
da_state(){
  local c l; c=$(conf_get PROVIDER_CUSTOM_SHA256); l=$(conf_get PROVIDER_LOCAL_FILE)
  if [ -n "$c" ]; then echo "Custom (sha ${c:0:8}...)"
  elif [ -n "$l" ] && [ -f "$l" ]; then echo "Local file"
  elif [ -n "$l" ]; then echo "Local file, not found"
  else echo "Download"; fi
}
da_status(){
  local l; l=$(conf_get PROVIDER_LOCAL_FILE)
  if [ -n "$(conf_get PROVIDER_CUSTOM_SHA256)" ]; then echo "custom $(conf_get PROVIDER_CUSTOM_FILE)"
  elif [ -n "$l" ]; then echo "local file $l$([ -f "$l" ] || echo ", not found")"
  else echo "download"; fi
}
# Why path $1 cannot be used (empty when it can); setup saves the path, and the launcher sources the settings file.
da_path_err(){
  local r
  case "$1" in /*) ;; *) echo "Path must be absolute (start with /)."; return;; esac
  [ -f "$1" ] || { echo "$1 is not a file."; return; }
  r=$(readlink -f -- "$1" 2>/dev/null) || r=$1
  [[ "$1" =~ ^[A-Za-z0-9._/+-]+$ && "$r" =~ ^[A-Za-z0-9._/+-]+$ ]] \
    || echo "Path may hold only letters, digits and . _ - + / (setup saves it). Move or rename the file, then try again."
}
# sha256 of file $1 into DA_SHA: read as this account, as administrator only after asking.
da_hash(){
  DA_SHA=""
  if [ -r "$1" ]; then
    ui_info "Driver archive" "Checking file..."
    DA_SHA=$(sha256sum -- "$1" 2>/dev/null | cut -c1-64)
  else
    ui_yesno "Driver archive" "$1 is not readable by account $(id -un). Read it with administrator rights?" Read Back || return 1
    need_root || return 1
    ui_info "Driver archive" "Checking file..."
    DA_SHA=$(as_root sha256sum -- "$1" 2>/dev/null | cut -c1-64)
  fi
  [[ "$DA_SHA" =~ ^[0-9a-f]{64}$ ]] || { ui_msg "Driver archive" "Could not read $1."; return 1; }
}
mali_custom(){ case "$(head -1 "$SA_MALI/.steam-arm-mali" 2>/dev/null)" in custom\ *) return 0;; esac; return 1; }
# GPU families the Mali tree covers (MALI_FAMILIES of the launch handler); family as the handler reads it.
SA_MALI_FAMILIES="mali-csf-v10 mali-csf-v11 mali-csf-5thgen mali-csf mali-valhall-jm mali-bifrost mali-midgard mali-panfrost"
route_family(){ local f; f=$(conf_get GPU_FAMILY); echo "${f:-$(gpu_family)}"; }
mali_family(){ case " $SA_MALI_FAMILIES " in *" $(route_family) "*) return 0;; esac; return 1; }
# Route B offered on a Mali GPU, or with a custom driver tree in place (handler applies it there too).
route_b_ok(){ mali_family || { mali_ready && mali_custom; }; }
client_type(){ case "$(conf_get CLIENT)" in x86) echo x86;; *) echo arm64;; esac; }
auto_build(){ case "$(conf_get AUTO_BUILD)" in off) echo off;; *) echo on;; esac; }
cpu_notice(){ case "$(conf_get CPU_NOTICE)" in on) echo on;; *) echo off;; esac; }
# Appids whose newest game log says CPU drawing (renderer warning line).
cpu_apps(){
  local f id l seen=" "
  while IFS= read -r f; do
    [ -r "$f" ] || continue
    id=$(grep -a -m1 -oE '^Steam(App|Game)Id=[0-9]+' "$f" | cut -d= -f2)
    [ -n "$id" ] && [[ "$seen" != *" $id "* ]] || continue
    l=$(grep -a 'steam-arm: renderer:' "$f" | tail -1)
    [ -n "$l" ] || continue
    seen="$seen$id "
    case "$l" in *"rendering on CPU"*) echo "$id";; esac
  done < <(fexlogs | head -50)
}
# Read-only helper as game account when root or that account, else as this account (no sudo prompt for a view).
game_read(){ if [ "$(id -u)" = 0 ] || [ "$(id -un)" = "$(game_user)" ]; then acct_run "$(game_user)" "$@"; else "$@"; fi; }
# Automatic Windows build state (list of steam-arm-autobuild.py); cached until ab_reset.
AB_CACHE=""; AB_DONE=0
ab_list(){
  if [ "$AB_DONE" = 0 ]; then
    AB_CACHE=$([ -f "$SA_AUTOBUILD_PY" ] && game_read timeout 30 python3 "$SA_AUTOBUILD_PY" list "$(steam_dir)" 2>/dev/null </dev/null)
    AB_DONE=1
  fi
  [ -n "$AB_CACHE" ] && printf '%s\n' "$AB_CACHE"
  return 0
}
ab_reset(){ AB_DONE=0; AB_CACHE=""; }
# Field $3 (verdict) or $5 (reason) of app line of one title.
ab_app(){ ab_list | awk -F'\t' -v id="$1" -v f="${2:-3}" '$1 == "app" && $2 == id { print $f; exit }'; }
# Title class of a rule id, for example "32-bit Source engine".
ab_what(){ ab_list | awk -F'\t' -v r="$1" '$1 == "rule" && $2 == r { print $6; exit }'; }
ab_drop(){ [ -f "$SA_AUTOBUILD_PY" ] && acct_run "$(game_user)" python3 "$SA_AUTOBUILD_PY" drop "$(steam_dir)" "$1" </dev/null; }
SA_NO_ROUTE_B="Route B (Mali drivers in emulation) needs a Mali GPU or a custom driver archive."
SA_NO_MALI="Mali drivers in emulation are not installed (Components); games use forwarding until it is."
# Warning after choosing route B on a Mali GPU without the tree.
route_b_note(){ [ "$1" = b ] && ! mali_ready && printf '%s' "$SA_NO_MALI"; return 0; }
status_line(){
  local d s; d=$(dot)
  s="not installed"; is_installed && s="installed"
  BT="Steam ARM $SA_VERSION${d}$(page_status)${d}$(hw_short)${d}$s${d}graphics: $(gfx_default_label "$(gfx_default)")"
}

# ===========================================================================
# titles.conf editing
# ===========================================================================
# Effective profile of appid over all profile files: key=value lines, later files win.
tc_effective(){
  local f
  while IFS= read -r f; do [ -r "$f" ] && cat "$f"; done < <(titles_files) | awk -v id="$1" '
    { d = $0; sub(/#.*/, "", d); n = split(d, w, /[ \t]+/); s = (w[1] == "" ? 2 : 1)
      if (w[s] != id) next
      for (i = s + 1; i <= n; i++) { p = index(w[i], "="); if (p) { k = substr(w[i], 1, p - 1); v[k] = substr(w[i], p + 1); if (!(k in o)) o[k] = ++c } } }
    END { for (k in o) ord[o[k]] = k; for (i = 1; i <= c; i++) print ord[i] "=" v[ord[i]] }'
}
tc_get(){ tc_effective "$1" | sed -n "s/^$2=//p" | tail -1; }
# File that sets key for appid last (later wins), empty if none.
tc_source(){
  local f src=""
  while IFS= read -r f; do
    [ -r "$f" ] && awk -v id="$1" -v k="$2=" '{ d = $0; sub(/#.*/, "", d); n = split(d, w, /[ \t]+/); s = (w[1] == "" ? 2 : 1)
      if (w[s] != id) next; for (i = s + 1; i <= n; i++) if (index(w[i], k) == 1) f = 1 } END { exit !f }' "$f" && src=$f
  done < <(titles_files)
  echo "$src"
}
# Set (or with empty value remove) key for appid in file; other lines and keys kept, atomic write.
tc_set(){
  local file=$1 id=$2 key=$3 val=${4:-} t
  mkdir -p "$(dirname "$file")" || return 1
  [ -f "$file" ] || : > "$file" || return 1
  t=$(mktemp "$file.XXXXXX") || return 1
  if TC_ID=$id TC_KEY=$key TC_VAL=$val awk '
      BEGIN { id = ENVIRON["TC_ID"]; key = ENVIRON["TC_KEY"]; val = ENVIRON["TC_VAL"] }
      { line[NR] = $0; d = $0; c = ""; p = index(d, "#"); if (p) { c = substr(d, p); d = substr(d, 1, p - 1) }
        n = split(d, w, /[ \t]+/); s = (w[1] == "" ? 2 : 1)
        if (w[s] == id) { hit[NR] = 1; last = NR; out = id
          for (i = s + 1; i <= n; i++) if (w[i] != "" && index(w[i], key "=") != 1) out = out " " w[i]
          body[NR] = out; com[NR] = c } }
      END { if (val != "" && last) body[last] = body[last] " " key "=" val
        for (i = 1; i <= NR; i++) {
          if (!hit[i]) { print line[i]; continue }
          if (body[i] == id && com[i] == "") continue
          print body[i] (com[i] != "" ? " " com[i] : "") }
        if (val != "" && !last) print id " " key "=" val }' "$file" > "$t" \
     && chmod 644 "$t" && mv -f "$t" "$file"; then return 0; fi
  rm -f "$t"; return 1
}
valid_appid(){ [[ "$1" =~ ^[0-9]{1,10}$ ]]; }
# Profile values: no spaces or '#' (file format splits on them).
valid_value(){ [[ "$1" != *[[:space:]#]* ]]; }

# ===========================================================================
# Games
# ===========================================================================
# Library folders: client library plus every "path" in libraryfolders.vdf.
game_libraries(){
  local s; s=$(steam_dir)
  { echo "$s"; sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$s/steamapps/libraryfolders.vdf" 2>/dev/null; } | awk '!seen[$0]++'
}
# Installed games: appid<TAB>name<TAB>installdir; tools, runtimes and shared content (LastOwner 0) left out; sorted by name.
games_list(){
  local lib f
  while IFS= read -r lib; do
    for f in "$lib"/steamapps/appmanifest_*.acf; do
      [ -r "$f" ] || continue
      awk '/^[ \t]*"(appid|name|installdir|LastOwner)"/ { k = $1; gsub(/"/, "", k); v = $0; sub(/^[ \t]*"[A-Za-z]+"[ \t]*"/, "", v); sub(/"[ \t]*$/, "", v); if (!(k in a)) a[k] = v }
           END { if (a["appid"] != "" && a["LastOwner"] != "0") printf "%s\t%s\t%s\n", a["appid"], a["name"], a["installdir"] }' "$f"
    done
  done < <(game_libraries) | awk -F'\t' -v re="$SA_TOOL_RE" '!seen[$1]++ && $2 !~ re && $1 != 228980' | sort -t"$(printf '\t')" -k2,2f
}
game_name(){ games_list | awk -F'\t' -v id="$1" '$1 == id { print $2 }'; }
game_dir(){ games_list | awk -F'\t' -v id="$1" '$1 == id { print $3 }'; }
# FEX tool logs, newest first.
# shellcheck disable=SC2012,SC2086
fexlogs(){ ls -t $SA_FEXLOG_GLOB 2>/dev/null; }
# shellcheck disable=SC2012
setuplogs(){ ls -t "$SA_CACHE"/setup-*.log 2>/dev/null; }
# Newest FEX tool log naming this title (AppId, profile line or its install folder).
game_fexlog(){
  local dir f; dir=$(game_dir "$1")
  while IFS= read -r f; do
    [ -r "$f" ] || continue
    if grep -qE "AppId=$1([^0-9]|\$)|profile for $1 |SteamAppId=$1([^0-9]|\$)" "$f" 2>/dev/null \
       || { [ -n "$dir" ] && grep -qF "/common/$dir/" "$f" 2>/dev/null; }; then echo "$f"; return 0; fi
  done < <(fexlogs)
  return 1
}

# ===========================================================================
# Dialog layer (built-in screens, else dialog, else whiptail, else plain prompts)
# ===========================================================================
ui_pick(){
  if [ -n "${STEAM_ARM_DIALOG:-}" ]; then DIALOG=$STEAM_ARM_DIALOG
  elif [ -t 0 ] && [ -t 1 ] && tui_ok; then DIALOG=builtin
  elif have dialog; then DIALOG=dialog
  elif have whiptail; then DIALOG=whiptail
  else DIALOG="read"; fi
  [ "$DIALOG" = dialog ] && dialog_rc
}
# Built-in screens need python3 with curses and a terminal that can place the cursor.
tui_ok(){ have python3 && python3 -c 'import curses, sys; curses.setupterm(); sys.exit(not curses.tigetstr("cup"))' >/dev/null 2>&1; }
# Light backtitle for dialog (its default can be dark on blue).
dialog_rc(){
  local f; f=$(tmpf) || return 0
  printf 'screen_color = (WHITE,BLUE,ON)\n' > "$f" && export DIALOGRC="$f" && SA_DIALOGRC=$f
}
SA_DIALOGRC=""
tui(){ python3 -c "$(tui_py)" "$1" "$BT" "${@:2}"; }
# Full-screen dialogs in Python curses: sparse purple texture, lily-white box.
tui_py(){ cat <<'SATUI'
import codecs, curses, locale, os, re, select, signal, sys, textwrap, time, unicodedata

locale.setlocale(locale.LC_ALL, "")
ENC = locale.nl_langinfo(locale.CODESET)
UTF = ENC.upper().replace("-", "") == "UTF8"
KIND, BT, ARGS = sys.argv[1], sys.argv[2], sys.argv[3:]
NOCOLOR = bool(os.environ.get("NO_COLOR"))
# Linux console fonts often lack the dashed rule glyph.
CONSOLE = os.environ.get("TERM", "").startswith("linux")
K, R, G, Y, B, M, C, W = range(8)
BOLD, REV, UL = curses.A_BOLD, curses.A_REVERSE, curses.A_UNDERLINE
# Role: (fg, bg, attr). 256 values: closest xterm-256 entry that keeps the hue.
THEMES = {
    "256": {
        "base": (252, 233, 0), "edge": (54, 233, 0), "mid": (53, 233, 0), "dim": (236, 233, 0),
        "hi": (98, 233, 0), "back": (252, 233, 0), "shadow": (16, 16, 0),
        "box": (235, 255, 0), "title": (55, 255, BOLD), "rule": (103, 255, 0), "hint": (244, 255, 0),
        "sel": (255, 98, BOLD), "soft": (235, 253, 0), "on": (255, 98, BOLD), "off": (235, 252, 0),
        "field": (16, 253, 0), "gon": (255, 98, BOLD), "goff": (235, 252, 0), "log": (241, 255, 0),
    },
    "8": {
        "base": (W, K, 0), "edge": (M, K, 0), "mid": (M, K, 0), "dim": (M, K, 0),
        "hi": (M, K, BOLD), "back": (W, K, BOLD), "shadow": (K, K, 0),
        "box": (K, W, 0), "title": (M, W, 0), "rule": (K, W, 0), "hint": (K, W, 0),
        "sel": (W, M, BOLD), "soft": (K, C, 0), "on": (W, M, BOLD), "off": (K, W, 0),
        "field": (K, C, 0), "gon": (W, M, BOLD), "goff": (W, K, 0), "log": (K, W, 0),
    },
    "mono": {
        "base": (0, 0, 0), "edge": (0, 0, 0), "mid": (0, 0, 0), "dim": (0, 0, 0), "hi": (0, 0, 0),
        "back": (0, 0, BOLD), "shadow": (0, 0, 0), "box": (0, 0, 0), "title": (0, 0, BOLD),
        "rule": (0, 0, 0), "hint": (0, 0, 0), "sel": (0, 0, REV), "soft": (0, 0, UL), "on": (0, 0, REV),
        "off": (0, 0, 0), "field": (0, 0, UL), "gon": (0, 0, REV), "goff": (0, 0, 0), "log": (0, 0, 0),
    },
}
MODE = "mono"
ATTR = {}
TEX = {"hi": "█", "edge": "▓", "mid": "▒", "dim": "░", "dash": "╌"} if UTF else \
      {"hi": "#", "edge": "#", "mid": ":", "dim": ".", "dash": "-"}
TEX8 = {"hi": "#", "edge": ":", "mid": ":", "dim": ".", "dash": "."}
LINE = "┌┐└┘─│" if UTF else "++++-|"
ARROW = "↑↓" if UTF else "^v"


def pick_mode(colours):
    if NOCOLOR or colours < 8:
        return "mono"
    return "256" if colours >= 256 else "8"


def noise(x, seed):
    h = (x * 2654435761 + seed * 40503) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 2246822519) & 0xFFFFFFFF
    return ((h >> 8) & 0xFF) / 255.0


# Sparse speckle, denser toward the side edges; fixed per cell so it never shifts.
def speckle(x, y, w):
    d = 1.0 - min(x, w - 1 - x) / max(1.0, (w - 1) / 2.0)
    if noise(x, y + 978) < 0.006 + d * 0.01:
        return "hi"
    r, e = noise(x, y + 1), d * 0.083
    for lim, tier in ((e, "edge"), (e + 0.027, "mid"), (e + 0.06, "dim"), (e + 0.093, "dash")):
        if r < lim:
            return tier
    return None


def cw(ch):
    return 2 if unicodedata.east_asian_width(ch) in "WF" else 1


def dw(s):
    return sum(cw(c) for c in s)


def clean(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch in "\t\n":
            out.append(ch)
        elif 0xd800 <= o < 0xe000 or (not UTF and o > 126):
            out.append("?")
        elif o < 32 or 0x7f <= o < 0xa0 or unicodedata.combining(ch):
            continue
        else:
            out.append(ch)
    return "".join(out)


def cut(s, n):
    out, used = [], 0
    for ch in s:
        if used + cw(ch) > n:
            break
        out.append(ch)
        used += cw(ch)
    return "".join(out)


# Backtitle in n columns: whole " · " (or " | ") segments dropped from the right; ellipsis only when
# the first segment alone is too wide.
def fit_bt(s, n):
    if dw(s) <= n:
        return s
    sep = " · " if " · " in s else " | "
    parts = s.split(sep)
    while len(parts) > 1:
        parts.pop()
        t = sep.join(parts)
        if dw(t) <= n:
            return t
    ell = "…" if UTF else "..."
    return cut(cut(parts[0], max(0, n - dw(ell))) + ell, n)


def wrap(text, width):
    width = max(8, width)
    lines = clean(text).rstrip("\n").split("\n")
    out = []
    for line in lines:
        line = line.expandtabs(8).rstrip()
        if dw(line) <= width:
            out.append(line)
            continue
        body = line.lstrip()
        sub = line[:len(line) - len(body)] + ("  " if body.startswith(("- ", "* ")) else "")
        if len(sub) > width // 2:
            sub = ""
        out.extend(textwrap.wrap(line, width, subsequent_indent=sub, break_on_hyphens=False) or [""])
    return out


class Grid:
    def __init__(s, h, w):
        s.h, s.w = h, w
        s.c = [[" "] * w for _ in range(h)]
        s.r = [["base"] * w for _ in range(h)]

    def put(s, y, x, text, role, lim=None):
        lim = s.w if lim is None else min(s.w, lim)
        if not 0 <= y < s.h:
            return x
        for ch in text:
            n = cw(ch)
            if x + n > lim:
                break
            if x >= 0:
                s.c[y][x], s.r[y][x] = ch, role
                if n == 2:
                    s.c[y][x + 1], s.r[y][x + 1] = "", role
            x += n
        return x

    def fill(s, y, x, h, w, role, ch=" "):
        for yy in range(max(0, y), min(s.h, y + h)):
            for xx in range(max(0, x), min(s.w, x + w)):
                s.c[yy][xx], s.r[yy][xx] = ch, role

    def runs(s, y, last=None):
        row, roles, x, end = s.c[y], s.r[y], 0, s.w if last is None else last
        while x < end:
            role, x0, buf = roles[x], x, []
            while x < end and roles[x] == role:
                ch = row[x]
                if ch == "" and not (x > 0 and row[x - 1] and cw(row[x - 1]) == 2):
                    ch = " "
                buf.append(ch)
                x += 1
            yield x0, "".join(buf), role


def background(g):
    if MODE == "8":
        # 8/16 colours: a third of the cells, plain magenta, ASCII dots
        for y in range(g.h):
            for x in range(g.w):
                t = speckle(x, y, g.w)
                if t and noise(x, y + 5113) < 0.34:
                    if t == "hi" and noise(x, y + 7919) < 0.5:
                        t = "mid"
                    g.c[y][x], g.r[y][x] = TEX8[t], "dim"
    elif MODE != "mono":
        dash = "-" if CONSOLE else TEX["dash"]
        for y in range(g.h):
            for x in range(g.w):
                t = speckle(x, y, g.w)
                if t:
                    g.c[y][x], g.r[y][x] = (dash if t == "dash" else TEX[t]), ("dim" if t == "dash" else t)
    bt = fit_bt(clean(BT).replace("\t", " ").replace("\n", " "), g.w - 2)
    if bt:
        g.fill(0, 0, 1, dw(bt) + 3, "base")
        g.put(0, 1, bt, "back")


# Box with border, title and drop shadow; returns its top-left corner.
def box(g, h, w, title, foot=""):
    y0 = max(1, (g.h - h) // 2)
    x0 = max(0, (g.w - w) // 2)
    if MODE == "256":
        g.fill(y0 + 1, x0 + w, h, 2, "shadow")
        g.fill(y0 + h, x0 + 2, 1, w, "shadow")
    g.fill(y0, x0, h, w, "box")
    tl, tr, bl, br, hz, vt = LINE
    g.put(y0, x0, tl + hz * (w - 2) + tr, "rule")
    g.put(y0 + h - 1, x0, bl + hz * (w - 2) + br, "rule")
    for y in range(y0 + 1, y0 + h - 1):
        g.put(y, x0, vt, "rule")
        g.put(y, x0 + w - 1, vt, "rule")
    t = cut(clean(title).replace("\n", " "), w - 6)
    if t:
        g.put(y0, x0 + (w - dw(t) - 2) // 2, " " + t + " ", "title")
    if foot:
        g.put(y0 + h - 1, x0 + w - dw(foot) - 4, " " + foot + " ", "hint")
    return y0, x0


def chip(label):
    return " %s " % label.center(max(6, dw(label))) if MODE == "256" else "<%s>" % label.center(max(6, dw(label)))


def btn_width(labels):
    return sum(dw(chip(l)) for l in labels) + 3 * (len(labels) - 1)


def buttons(g, y, x0, w, labels, active):
    x = x0 + (w - btn_width(labels)) // 2
    for i, l in enumerate(labels):
        x = g.put(y, x, chip(l), "on" if i == active else "off") + 3


def small(g):
    return g.h < 10 or g.w < 36


def tiny(scr, g):
    g.fill(0, 0, g.h, g.w, "base", " ")
    g.put(0, 0, "Enlarge the terminal (Esc: Back)", "back")
    show(scr, g)


def show(scr, g, cursor=None):
    for y in range(g.h):
        for x, s, role in g.runs(y):
            try:
                scr.addstr(y, x, s, ATTR[role])
            except curses.error:
                pass
    try:
        if cursor:
            curses.curs_set(1)
            scr.move(*cursor)
        else:
            curses.curs_set(0)
    except curses.error:
        pass
    scr.refresh()


KEYS = {curses.KEY_ENTER: "enter", curses.KEY_UP: "up", curses.KEY_DOWN: "down", curses.KEY_LEFT: "left",
        curses.KEY_RIGHT: "right", curses.KEY_PPAGE: "pgup", curses.KEY_NPAGE: "pgdn", curses.KEY_HOME: "home",
        curses.KEY_END: "end", curses.KEY_BTAB: "btab", curses.KEY_BACKSPACE: "bs", curses.KEY_DC: "del",
        curses.KEY_RESIZE: "resize", "\n": "enter", "\r": "enter", "\x1b": "esc", "\t": "tab", "\x7f": "bs",
        "\b": "bs", " ": "space"}
for _n, _k in (("KEY_A1", "home"), ("KEY_C1", "end"), ("KEY_A3", "pgup"), ("KEY_C3", "pgdn")):
    if hasattr(curses, _n):
        KEYS[getattr(curses, _n)] = _k


def key(scr):
    while True:
        try:
            k = scr.get_wch()
        except curses.error:
            continue
        if k in KEYS:
            return KEYS[k]
        if isinstance(k, str) and k.isprintable():
            return k
        if isinstance(k, int) and k >= 0:
            return None


def frame(scr):
    h, w = scr.getmaxyx()
    g = Grid(h, w)
    background(g)
    return g


def move(cur, n, k, page):
    step = {"up": -1, "down": 1, "pgup": -page, "pgdn": page, "home": -n, "end": n}.get(k)
    return cur if step is None else max(0, min(n - 1, cur + step))


# menu and checklist: (status, output)
def listbox(scr, title, text, items, check, labels, default=""):
    top, focus, typed, tlast = 0, -1, "", 0.0
    cur = next((i for i, it in enumerate(items) if default and it[0] == default), 0)
    tagw = max([dw(clean(t)) for t, _, _ in items] + [0])

    def row(i):
        t, l, on = items[i]
        t = clean(t)
        s = t + " " * (tagw - dw(t) + 2) + clean(l).replace("\n", " ")
        return ("[%s] " % ("x" if on else " ") + s) if check else s

    def find(buf):
        b = buf.lower()
        for i, (t, _, _) in enumerate(items):
            if t.lower() == b:
                return i
        order = list(range(cur + 1, len(items))) + list(range(0, cur + 1)) if len(b) == 1 else range(len(items))
        for i in order:
            if items[i][0].lower().startswith(b):
                return i
        for i in order:
            if items[i][1].lower().startswith(b):
                return i
        return None

    while True:
        g = frame(scr)
        if small(g):
            tiny(scr, g)
        else:
            wmax = min(g.w - 4, 76)
            lines = wrap(text, wmax - 6) if text else []
            rows = [row(i) for i in range(len(items))]
            bw = max([dw(l) + 6 for l in lines] + [dw(r) + 7 for r in rows] + [dw(clean(title)) + 8, btn_width(labels) + 6, 50])
            bw = min(bw, wmax)
            nt, nl = len(lines), max(1, len(items))
            extra = 6 if nt else 5
            avail = g.h - 2
            if nt + nl + extra > avail:
                nl = max(min(len(items), 3), avail - nt - extra)
            if nt + nl + extra > avail:
                nt = max(0, avail - nl - extra)
                lines = lines[:nt]
            bh = nt + nl + (6 if nt else 5)
            if cur < top:
                top = cur
            if cur >= top + nl:
                top = cur - nl + 1
            top = max(0, min(top, max(0, len(items) - nl)))
            y0, x0 = box(g, bh, bw, title)
            y = y0 + 2
            for l in lines:
                g.put(y, x0 + 3, l, "box", x0 + bw - 2)
                y += 1
            if nt:
                y += 1
            lx, lw = x0 + 2, bw - 4
            for i in range(top, min(len(items), top + nl)):
                role = "box"
                if i == cur:
                    role = "sel" if focus == -1 else "soft"
                    g.fill(y + i - top, lx, 1, lw, role)
                g.put(y + i - top, lx + 1, rows[i], role, lx + lw - 2)
            if top > 0:
                g.put(y, lx + lw - 1, ARROW[0], "sel" if cur == top and focus == -1 else "hint")
            if top + nl < len(items):
                yy = y + nl - 1
                g.put(yy, lx + lw - 1, ARROW[1], "sel" if cur == top + nl - 1 and focus == -1 else "hint")
            buttons(g, y0 + bh - 2, x0, bw, labels, 0 if focus == -1 else focus)
            show(scr, g)
            page = nl
        k = key(scr)
        if k == "esc":
            return 1, ""
        if k in ("up", "down", "pgup", "pgdn", "home", "end") and items:
            cur = move(cur, len(items), k, max(1, page - 1) if not small(g) else 1)
        elif k == "tab":
            focus = {-1: 0, 0: 1}.get(focus, -1)
        elif k == "btab":
            focus = {-1: 1, 1: 0}.get(focus, -1)
        elif k in ("left", "right"):
            focus = 1 if (focus in (-1, 0)) == (k == "right") else 0
        elif k == "space" and check and focus == -1 and items:
            items[cur][2] = not items[cur][2]
        elif k == "enter" or (k == "space" and focus >= 0):
            if focus == 1:
                return 1, ""
            if check:
                return 0, "".join(t + "\n" for t, _, on in items if on)
            return (0, items[cur][0]) if items else (1, "")
        elif k and len(k) == 1 and items:
            now = time.monotonic()
            buf = typed + k if now - tlast < 1.0 else k
            tlast = now
            i = find(buf)
            if i is None and len(buf) > 1:
                buf, i = k, find(k)
            typed = buf
            if i is not None:
                cur, focus = i, -1


# msgbox, yesno, textbox, infobox: (status, output)
def pager(scr, title, text, labels, focus, draw_only=False, g=None):
    top = 0
    while True:
        if g is None:
            g = frame(scr)
        if small(g):
            if draw_only:
                return g
            tiny(scr, g)
            vis = 1
        else:
            wmax = min(g.w - 4, 76)
            lines = wrap(text, wmax - 6)
            bw = min(wmax, max([dw(l) + 6 for l in lines] + [dw(clean(title)) + 8, 50] + ([btn_width(labels) + 6] if labels else [])))
            extra = 5 if labels else 4
            vis = max(1, min(len(lines), g.h - 2 - extra))
            top = max(0, min(top, len(lines) - vis))
            foot = ""
            if len(lines) > vis:
                foot = "%s%s %d-%d/%d" % (ARROW[0] if top else " ", ARROW[1] if top + vis < len(lines) else " ",
                                           top + 1, top + vis, len(lines))
            bh = vis + extra
            y0, x0 = box(g, bh, bw, title, foot)
            for i, l in enumerate(lines[top:top + vis]):
                g.put(y0 + 2 + i, x0 + 3, l, "box", x0 + bw - 2)
            if draw_only:
                return g
            buttons(g, y0 + bh - 2, x0, bw, labels, focus)
            show(scr, g)
        g = None
        k = key(scr)
        if k == "esc":
            return 1, ""
        if k in ("up", "down", "pgup", "pgdn", "home", "end"):
            n = len(wrap(text, min(scr.getmaxyx()[1] - 4, 76) - 6))
            top = move(top, max(1, n - vis + 1), k, max(1, vis - 1))
        elif k in ("tab", "right", "btab", "left") and len(labels) > 1:
            focus = (focus + (1 if k in ("tab", "right") else -1)) % len(labels)
        elif k in ("enter", "space"):
            return (0 if focus == 0 else 1), ""


# inputbox and passwordbox: (status, output)
def entry(scr, title, text, value, mask):
    val, pos, focus, off = list(value), len(value), -1, 0
    labels = ["OK", "Back"]
    while True:
        g = frame(scr)
        cursor = None
        if small(g):
            tiny(scr, g)
        else:
            wmax = min(g.w - 4, 76)
            lines = wrap(text, wmax - 6)
            bw = min(wmax, max([dw(l) + 6 for l in lines] + [dw(clean(title)) + 8, 50]))
            nt = max(1, min(len(lines), g.h - 2 - 7))
            bh = nt + 7
            y0, x0 = box(g, bh, bw, title)
            for i, l in enumerate(lines[:nt]):
                g.put(y0 + 2 + i, x0 + 3, l, "box", x0 + bw - 2)
            fy, fx, fw = y0 + 3 + nt, x0 + 3, bw - 6
            s = "*" * len(val) if mask else clean("".join(val))
            if pos - off >= fw:
                off = pos - fw + 1
            if pos < off:
                off = pos
            g.fill(fy, fx, 1, fw, "field")
            g.put(fy, fx, s[off:off + fw], "field", fx + fw)
            buttons(g, y0 + bh - 2, x0, bw, labels, 0 if focus == -1 else focus)
            if focus == -1:
                cursor = (fy, fx + dw(s[off:pos]))
            show(scr, g, cursor)
        k = key(scr)
        if k == "esc":
            return 1, ""
        if k == "enter" or (k == "space" and focus >= 0):
            return (1, "") if focus == 1 else (0, "".join(val))
        if k == "tab":
            focus = {-1: 0, 0: 1}.get(focus, -1)
        elif k == "btab":
            focus = {-1: 1, 1: 0}.get(focus, -1)
        elif focus >= 0:
            if k in ("left", "right"):
                focus = 1 - focus
        elif k == "left":
            pos = max(0, pos - 1)
        elif k == "right":
            pos = min(len(val), pos + 1)
        elif k == "home":
            pos = 0
        elif k == "end":
            pos = len(val)
        elif k == "bs" and pos > 0:
            pos -= 1
            del val[pos]
        elif k == "del" and pos < len(val):
            del val[pos]
        elif k == "space" or (k and len(k) == 1):
            val.insert(pos, " " if k == "space" else k)
            pos += 1


STEP = re.compile(r"^(==>)?\s*([0-9]+)/([0-9]+)\s+(.*)$")
# download bar (curl --progress-bar) ends in a percentage
PCT = re.compile(r"\s([0-9]{1,3})(\.[0-9])?%\s*$")


# Gauge label and percent: setup step lines first, else a download bar in the open line.
def gauge(step, line):
    if step:
        n, tot, txt = step
        return "Step %d of %d: %s" % (n, tot, txt), max(0, min(100, n * 100 // tot))
    m = PCT.search(" " + line)
    if m:
        return "Downloading...", min(100, int(m.group(1)))
    return "Starting...", 0
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[()][0-9A-Za-z]|\x1b[=>]")


def plain(line):
    parts = [p for p in ANSI.sub("", line).split("\r") if p.strip()]
    return clean(parts[-1] if parts else "").expandtabs(8).rstrip()


# Live log tail and step gauge from "N/total text" lines; returns at end of input.
def progress(scr, title, feed):
    os.set_blocking(feed, False)
    dec = codecs.getincrementaldecoder("utf-8")("replace")
    log, part, step, eof = [], "", None, False
    scr.nodelay(True)
    while True:
        g = frame(scr)
        if small(g):
            tiny(scr, g)
        else:
            bw = min(g.w - 4, 76)
            bh = min(g.h - 2, 18)
            y0, x0 = box(g, bh, bw, title)
            tail = bh - 6
            rows = []
            for l in log[-tail:] + ([plain(part)] if plain(part) else []):
                rows.extend(wrap(l, bw - 6))
            shown = rows[-tail:] if tail > 0 else []
            for i, l in enumerate(shown):
                g.put(y0 + 1 + i, x0 + 3, l, "log", x0 + bw - 3)
            label, pct = gauge(step, plain(part))
            g.put(y0 + bh - 4, x0 + 3, label, "box", x0 + bw - 3)
            gw = bw - 6
            fill = gw * pct // 100
            bar = ("%d%%" % pct).center(gw)
            for i in range(gw):
                ch = bar[i]
                if MODE == "mono" and i >= fill and ch == " ":
                    ch = "." if not UTF else "·"
                g.put(y0 + bh - 3, x0 + 3 + i, ch, "gon" if i < fill else "goff")
            show(scr, g)
        if eof:
            return 0, ""
        r = select.select([feed, 0], [], [], 0.25)[0]
        if feed in r:
            try:
                b = os.read(feed, 65536)
            except BlockingIOError:
                b = None
            if b == b"":
                eof, chunk = True, dec.decode(b"", True)
            else:
                chunk = dec.decode(b) if b else ""
            part += chunk
            *done, part = part.split("\n")
            # progress bar redraws: keep the open line from its last full segment on
            if len(part) > 4096 and "\r" in part[:-1]:
                part = part[part.rindex("\r", 0, len(part) - 1):]
            if eof and part:
                done.append(part)
                part = ""
            for line in done:
                p = plain(line)
                m = STEP.match(p)
                if m and int(m.group(3)) > 0:
                    step = (int(m.group(2)), int(m.group(3)), m.group(4)[:60])
                if p:
                    log.append(p)
            del log[:-300]
        while scr.getch() != -1:
            pass


def colours():
    global MODE, ATTR
    n = 0
    if not NOCOLOR and curses.has_colors():
        curses.start_color()
        n = curses.COLORS
    MODE = pick_mode(n)
    if MODE == "mono" and curses.has_colors():
        try:
            curses.start_color()
            curses.use_default_colors()
        except curses.error:
            pass
    pairs = {}
    for role, (fg, bg, a) in THEMES[MODE].items():
        if MODE == "mono":
            ATTR[role] = a
            continue
        if (fg, bg) not in pairs:
            pairs[(fg, bg)] = len(pairs) + 1
            curses.init_pair(pairs[(fg, bg)], fg, bg)
        ATTR[role] = curses.color_pair(pairs[(fg, bg)]) | a


def run(scr, feed):
    colours()
    scr.keypad(True)
    curses.flushinp()
    a = ARGS + [""] * 6
    if KIND in ("menu", "check"):
        title, text = a[0], a[1]
        if KIND == "menu":
            labels, rest = ["Select", a[2] or "Back"], ARGS[4:]
            items = [[rest[i], rest[i + 1], False] for i in range(0, len(rest) - 1, 2)]
        else:
            labels, rest = ["OK", "Back"], ARGS[2:]
            items = [[rest[i], rest[i + 1], rest[i + 2].upper() == "ON"] for i in range(0, len(rest) - 2, 3)]
        return listbox(scr, title, text, items, KIND == "check", labels, a[3] if KIND == "menu" else "")
    if KIND == "msg":
        return pager(scr, a[0], a[1], ["OK"], 0)
    if KIND == "yesno":
        return pager(scr, a[0], a[1], [a[2] or "Yes", a[3] or "No"], 1 if a[4] == "defaultno" else 0)
    if KIND == "textstr":
        return pager(scr, a[0], a[1], [a[2] or "Back"], 0)
    if KIND == "text":
        try:
            with open(a[1], encoding="utf-8", errors="replace") as f:
                body = f.read()
        except OSError as e:
            body = "Could not read %s: %s" % (a[1], e.strerror)
        return pager(scr, a[0], body, [a[2] or "Back"], 0)
    if KIND in ("input", "password"):
        return entry(scr, a[0], a[1], "" if KIND == "password" else a[2], KIND == "password")
    if KIND == "progress":
        return progress(scr, a[0], feed)
    return 1, ""


# Paint a grid on the normal screen with terminfo strings (no curses session).
def paint(g):
    def cap(name, *p):
        s = curses.tigetstr(name)
        return (curses.tparm(s, *p) if p else s) if s else b""
    seq = {}
    for role, (fg, bg, a) in THEMES[MODE].items():
        s = b""
        if MODE != "mono":
            s += cap("setaf", fg) + cap("setab", bg)
        s += (cap("bold") if a & BOLD else b"") + (cap("rev") if a & REV else b"") + (cap("smul") if a & UL else b"")
        seq[role] = s
    out = [cap("sgr0"), cap("clear")]
    for y in range(g.h - 1):
        out.append(cap("cup", y, 0))
        for x, s, role in g.runs(y):
            out.append(cap("sgr0") + seq[role] + s.encode(ENC, "replace"))
    out += [cap("sgr0"), cap("cup", g.h - 1, 0)]
    os.write(1, b"".join(out))


def term_grid():
    try:
        curses.setupterm(None, 1)
    except curses.error:
        return None
    global MODE
    MODE = pick_mode(curses.tigetnum("colors"))
    w, h = os.get_terminal_size(1)
    if not curses.tigetstr("cup") or h < 2 or w < 2:
        return None
    g = Grid(h, w)
    background(g)
    return g


def main():
    feed = os.dup(0) if KIND == "progress" else None
    res = os.dup(1)
    try:
        tty = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
    except OSError:
        tty = 2 if os.isatty(2) else None
    if tty is None:
        return 1
    os.dup2(tty, 0)
    os.dup2(tty, 1)
    if KIND == "info":
        g = term_grid()
        if g is None:
            os.write(1, ("\n%s\n%s\n" % (ARGS[0] if ARGS else "", ARGS[1] if len(ARGS) > 1 else "")).encode(ENC, "replace"))
        elif small(g):
            paint(g)
        else:
            paint(pager(None, ARGS[0], ARGS[1] if len(ARGS) > 1 else "", [], 0, True, g))
        return 0
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda *_: sys.exit(1))
    os.environ["ESCDELAY"] = "25"
    try:
        st, out = curses.wrapper(run, feed)
    except KeyboardInterrupt:
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        os.kill(os.getpid(), signal.SIGINT)
        return 130
    except Exception as e:
        if feed is not None:
            os.set_blocking(feed, True)
            while os.read(feed, 65536):
                pass
        sys.stderr.write("steam-arm-config: screen error: %s\n" % e)
        return 1
    if MODE != "mono":
        g = Grid(*os.get_terminal_size(1)[::-1])
        background(g)
        paint(g)
    if out:
        os.write(res, os.fsencode(out))
    return st


sys.exit(main())
SATUI
}
ui_size(){
  local r c; read -r r c < <(stty size 2>/dev/null || echo "24 80")
  UH=$(( r - 2 )); [ "$UH" -gt 22 ] && UH=22; [ "$UH" -lt 20 ] && UH=20
  UW=$(( c - 4 )); [ "$UW" -gt 76 ] && UW=76; [ "$UW" -lt 70 ] && UW=70
  UL=$(( UH - 9 ))
  # text boxes may use every terminal row
  UT=$(( r - 2 )); [ "$UT" -lt "$UH" ] && UT=$UH
}
# List height for $1 entries: no more rows than entries, so text above the list keeps the rest.
ui_lh(){ [ "$1" -lt "$UL" ] && echo "$(( $1 < 1 ? 1 : $1 ))" || echo "$UL"; }
ui_pause(){ printf '\nPress Enter to continue... ' >&2; read -r _ </dev/tty; }
# ui_menu title text [--cancel label] [--default tag] tag item ...; prints chosen tag, status 1 on Back.
ui_menu(){
  local title=$1 text=$2 cancel=Back def="" n i sel; shift 2
  while :; do
    case "${1:-}" in --cancel) cancel=$2; shift 2;; --default) def=$2; shift 2;; *) break;; esac
  done
  local -a di=(); [ -n "$def" ] && di=(--default-item "$def")
  ui_size
  case "$DIALOG" in
    builtin)  tui menu "$title" "$text" "$cancel" "$def" "$@";;
    whiptail) whiptail --backtitle "$BT" --title "$title" "${di[@]}" --ok-button Select --cancel-button "$cancel" \
                --menu "$text" "$UH" "$UW" "$(ui_lh $(( $# / 2 )))" "$@" 3>&1 1>&2 2>&3;;
    dialog)   dialog --backtitle "$BT" --title "$title" --no-collapse "${di[@]}" --ok-label Select --cancel-label "$cancel" \
                --menu "$text" "$UH" "$UW" "$(ui_lh $(( $# / 2 )))" "$@" 3>&1 1>&2 2>&3;;
    *) { printf '\n== %s ==\n%s\n\n%s\n\n' "$title" "$BT" "$text"
         n=0; while [ $# -ge 2 ]; do n=$((n + 1)); eval "_t$n=\$1"; printf '  %2d) %s\n' "$n" "$2"; shift 2; done
         printf '   0) %s\n\nChoice: ' "$cancel"; } >&2
       read -r sel </dev/tty || return 1
       [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$n" ] || return 1
       i="_t$sel"; echo "${!i}";;
  esac
}
# ui_check title text tag item ON|OFF ...; prints chosen tags one per line.
ui_check(){
  local title=$1 text=$2 n=0 i sel; shift 2
  ui_size
  case "$DIALOG" in
    builtin)  tui check "$title" "$text" "$@";;
    whiptail) whiptail --backtitle "$BT" --title "$title" --separate-output --ok-button OK --cancel-button Back \
                --checklist "$text" "$UH" "$UW" "$(ui_lh $(( $# / 3 )))" "$@" 3>&1 1>&2 2>&3;;
    dialog)   dialog --backtitle "$BT" --title "$title" --no-collapse --separate-output --ok-label OK --cancel-label Back \
                --checklist "$text" "$UH" "$UW" "$(ui_lh $(( $# / 3 )))" "$@" 3>&1 1>&2 2>&3;;
    *) while [ $# -ge 3 ]; do n=$((n + 1)); eval "_t$n=\$1 _d$n=\$2 _s$n=\$3"; shift 3; done
       while :; do
         { printf '\n== %s ==\n%s\n\n' "$title" "$text"
           for i in $(seq 1 "$n"); do eval "printf '  %2d) [%s] %-16s %s\n' $i \"\$( [ \"\$_s$i\" = ON ] && echo x || echo ' ')\" \"\$_t$i\" \"\$_d$i\""; done
           printf '\nNumber to toggle, Enter to accept, 0 for Back: '; } >&2
         read -r sel </dev/tty || return 1
         [ -z "$sel" ] && break; [ "$sel" = 0 ] && return 1
         [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -le "$n" ] && eval "[ \"\$_s$sel\" = ON ] && _s$sel=OFF || _s$sel=ON"
       done
       for i in $(seq 1 "$n"); do eval "[ \"\$_s$i\" = ON ] && echo \"\$_t$i\""; done; return 0;;
  esac
}
ui_msg(){
  ui_size
  case "$DIALOG" in
    builtin)  tui msg "$1" "$2";;
    whiptail) whiptail --backtitle "$BT" --title "$1" --ok-button OK --msgbox "$2" "$UH" "$UW";;
    dialog)   dialog --backtitle "$BT" --title "$1" --msgbox "$2" "$UH" "$UW";;
    *) printf '\n== %s ==\n%s\n' "$1" "$2" >&2; ui_pause;;
  esac
}
# ui_yesno title text [yes-label no-label [defaultno]]
ui_yesno(){
  local y=${3:-Yes} n=${4:-No} def=(); [ "${5:-}" = defaultno ] && def=(--defaultno)
  ui_size
  case "$DIALOG" in
    builtin)  tui yesno "$1" "$2" "$y" "$n" "${5:-}";;
    whiptail) whiptail --backtitle "$BT" --title "$1" "${def[@]}" --yes-button "$y" --no-button "$n" --yesno "$2" "$UH" "$UW";;
    dialog)   dialog --backtitle "$BT" --title "$1" "${def[@]}" --yes-label "$y" --no-label "$n" --yesno "$2" "$UH" "$UW";;
    *) local a; printf '\n== %s ==\n%s\n\n[%s/%s]: ' "$1" "$2" "$y" "$n" >&2; read -r a </dev/tty
       case "$(echo "$a" | tr '[:upper:]' '[:lower:]')" in y|yes|"$(echo "$y" | tr '[:upper:]' '[:lower:]')") return 0;; esac; return 1;;
  esac
}
# Hidden entry; prints what was typed, status 1 on Back.
ui_password(){
  ui_size
  case "$DIALOG" in
    builtin)  tui password "$1" "$2";;
    whiptail) whiptail --backtitle "$BT" --title "$1" --ok-button OK --cancel-button Back --passwordbox "$2" 12 "$UW" 3>&1 1>&2 2>&3;;
    dialog)   dialog --backtitle "$BT" --title "$1" --cancel-label Back --insecure --passwordbox "$2" 12 "$UW" 3>&1 1>&2 2>&3;;
    *) local a; printf '\n== %s ==\n%s\n(0 = Back): ' "$1" "$2" >&2; read -rs a </dev/tty || return 1; echo >&2
       [ "$a" = 0 ] && return 1; echo "$a";;
  esac
}
ui_input(){
  ui_size
  case "$DIALOG" in
    builtin)  tui input "$1" "$2" "${3:-}";;
    whiptail) whiptail --backtitle "$BT" --title "$1" --ok-button OK --cancel-button Back --inputbox "$2" 12 "$UW" "${3:-}" 3>&1 1>&2 2>&3;;
    dialog)   dialog --backtitle "$BT" --title "$1" --cancel-label Back --inputbox "$2" 12 "$UW" "${3:-}" 3>&1 1>&2 2>&3;;
    *) local a; printf '\n== %s ==\n%s\n[%s] (0 = Back): ' "$1" "$2" "${3:-}" >&2; read -r a </dev/tty || return 1
       [ "$a" = 0 ] && return 1; echo "${a:-${3:-}}";;
  esac
}
# ui_text title file [button]: box sized to text, scrolling only when longer than the screen (whiptail's scroll view ignores Enter).
ui_text(){
  local h th f b=${3:-Back}
  [ "$DIALOG" = builtin ] && { tui text "$1" "$2" "$b"; return; }
  ui_size
  # no temp file: the unfolded file itself
  if f=$(tmpf); then fold -s -w $(( UW - 5 )) "$2" > "$f"; else f=$2; fi
  h=$(( $(wc -l < "$f") + 7 )); th=${UT:-$UH}
  case "$DIALOG" in
    whiptail) if [ "$h" -le "$th" ]; then
                whiptail --backtitle "$BT" --title "$1" --ok-button "$b" --textbox "$f" "$h" "$UW"
              else
                whiptail --backtitle "$BT" --title "$1 (arrows scroll; Tab, Enter: $b)" --scrolltext --ok-button "$b" --textbox "$f" "$th" "$UW"
              fi;;
    dialog)   [ "$h" -lt "$UH" ] && h=$UH; [ "$h" -gt "$th" ] && h=$th
              dialog --backtitle "$BT" --title "$1" --exit-label "$b" --textbox "$f" "$h" "$UW";;
    *) printf '\n== %s ==\n' "$1" >&2; cat "$2" >&2; ui_pause;;
  esac
  [ "$f" = "$2" ] || rm -f "$f"
}
# ui_textstr title text [button]: builtin screens take it directly; others through a temp file, else a message box.
ui_textstr(){
  local f
  if [ "$DIALOG" = builtin ] && [ "${#2}" -lt 100000 ]; then tui textstr "$1" "$2" "${3:-Back}"; return; fi
  if f=$(tmpf); then printf '%s\n' "$2" > "$f"; ui_text "$1" "$f" "${3:-Back}"; rm -f "$f"; return; fi
  case "$DIALOG" in
    builtin|whiptail|dialog) ui_msg "$1" "$2";;
    *) printf '\n== %s ==\n%s\n' "$1" "$2" >&2; ui_pause;;
  esac
}
ui_info(){
  case "$DIALOG" in
    builtin)  tui info "$1" "$2";;
    whiptail) TERM=${TERM:-vt100} whiptail --backtitle "$BT" --title "$1" --infobox "$2" 8 60;;
    dialog)   dialog --backtitle "$BT" --title "$1" --infobox "$2" 8 60;;
    *) printf '%s\n' "$2" >&2;;
  esac
}
# Standard input of the command run by ui_run: UI_STDIN (one line, e.g. a password), else nothing.
UI_STDIN=""
ui_feed(){ [ -n "$UI_STDIN" ] && printf '%s\n' "$UI_STDIN"; return 0; }
# Progress of a long command: log tail and step gauge (built-in), gauge fed by "N/11" step lines (whiptail),
# programbox (dialog), terminal (plain).
# ui_run title log cmd...; status of cmd.
ui_run(){
  local title=$1 log=$2 rcf; shift 2
  rcf=$(tmpf) || { ui_msg "$title" "$TMP_FAIL"; return 1; }
  ui_size
  case "$DIALOG" in
    builtin)  local fd lp
              if ! { fd=$(tmpf -d) && mkfifo -m 600 "$fd/log"; }; then rm -rf "$fd" "$rcf"; ui_msg "$title" "$TMP_FAIL"; return 1; fi
              cr_last < "$fd/log" >> "$log" & lp=$!
              { ui_feed | "$@" 2>&1; echo "${PIPESTATUS[1]}" > "$rcf"; } | tee "$fd/log" | tui progress "$title"
              wait "$lp"; rm -rf "$fd";;
    whiptail) { ui_feed | "$@" 2>&1; echo "${PIPESTATUS[1]}" > "$rcf"; } | tee -a "$log" | progress_feed \
                | whiptail --backtitle "$BT" --title "$title" --gauge "Starting..." 8 "$UW" 0;;
    dialog)   { ui_feed | "$@" 2>&1; echo "${PIPESTATUS[1]}" > "$rcf"; } | tee -a "$log" | ansi_lines \
                | dialog --backtitle "$BT" --title "$title" --programbox "$UH" "$UW";;
    *) { ui_feed | "$@" 2>&1; echo "${PIPESTATUS[1]}" > "$rcf"; } | tee -a "$log";;
  esac
  local rc; rc=$(cat "$rcf" 2>/dev/null); rm -f "$rcf"
  return "${rc:-1}"
}
# Log copy: last carriage-return segment of each line, so a progress bar logs as one line.
cr_last(){ sed -u 's/.*\r\(.\)/\1/'; }
# Colour codes removed line by line (no pipe buffering, so progress shows live).
ansi_lines(){
  local l
  while IFS= read -r l; do
    while [[ "$l" =~ $'\e'\[[0-9\;]*[A-Za-z] ]]; do l=${l//"${BASH_REMATCH[0]}"/}; done
    printf '%s\n' "$l"
  done
}
# Gauge protocol from installer step lines "==> N/11  text".
progress_feed(){
  local line n tot txt re='^(==>)?[[:space:]]*([0-9]+)/([0-9]+)[[:space:]]+(.*)$'
  while IFS= read -r line; do
    while [[ "$line" =~ $'\e'\[[0-9\;]*[A-Za-z] ]]; do line=${line//"${BASH_REMATCH[0]}"/}; done
    if [[ "$line" =~ $re ]]; then
      n=${BASH_REMATCH[2]}; tot=${BASH_REMATCH[3]}; txt=${BASH_REMATCH[4]}
      [ "$tot" -gt 0 ] 2>/dev/null || continue
      printf 'XXX\n%d\nStep %s of %s: %s\nXXX\n' $(( n * 100 / tot )) "$n" "$tot" "${txt:0:60}"
    fi
  done
}

# ===========================================================================
# Root access
# ===========================================================================
# Make sure root commands can run: explain once, then let sudo ask in the terminal.
need_root(){
  [ "$(id -u)" = 0 ] && return 0
  [ "$SUDO_OK" = 1 ] && sudo -n true 2>/dev/null && return 0
  have sudo || { ui_msg "Administrator rights" "This change writes system files. Log in as root (for example: su -), then run steam-arm-config."; return 1; }
  if ! sudo -n true 2>/dev/null; then
    ui_msg "Administrator rights" "This change writes system files, so it needs administrator rights.

After OK, sudo asks for your password in the terminal. The menu comes back afterwards." || return 1
    term_reset
    printf 'Administrator password for %s (sudo):\n' "$(id -un)"
    sudo -p "Password: " -v || { ui_msg "Administrator rights" "sudo did not accept the password. Nothing was changed."; return 1; }
  fi
  SUDO_OK=1
}
# Plain attributes, empty screen, cursor home and visible (a full-screen menu may leave any of them changed).
term_reset(){
  { tput sgr0 && tput clear && tput cup 0 0 && tput cnorm; } 2>/dev/null || printf '\033[0m\033[H\033[2J\033[?25h'
}
as_root(){ if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
# Run this app's own subcommand as root.
self_root(){
  local out
  need_root || return 1
  out=$(as_root bash "$(self_path)" "$@" 2>&1) && return 0
  ui_msg "Steam ARM" "The change did not go through:

$out"
  return 1
}
# Non-interactive subcommands re-run themselves with sudo.
cli_root(){
  [ "$(id -u)" = 0 ] && return 0
  have sudo || { echo "steam-arm-config: needs root" >&2; exit 1; }
  echo "steam-arm-config: ${CLI_ROOT_WHY:-this change needs administrator rights}; running it with sudo" >&2
  exec sudo env STEAM_ARM_INSTALLER="${STEAM_ARM_INSTALLER:-}" bash "$(self_path)" "$@"
}
# Launcher's graceful stop as game account (client -shutdown, SIGTERM after 20 s, x86 client 45 s, never SIGKILL). Without display
# variables: a launcher stop dialog would wait unseen behind this menu. Account other than the settings file's: its own folder.
steam_shutdown(){
  local -a e=(env -u DISPLAY -u WAYLAND_DISPLAY ${GU_OVERRIDE:+"STEAM_ARM_HOME=$(arm_home)"})
  if [ "$(id -un)" = "$(game_user)" ]; then "${e[@]}" "$SA_LAUNCHER" --shutdown </dev/null 2>&1; return; fi
  as_root runuser -u "$(game_user)" -- "${e[@]}" HOME="$(game_home)" "$SA_LAUNCHER" --shutdown </dev/null 2>&1
}
# Steam closed before $1 (screen title), $2 says why: offers "Close Steam"; status 0 once game account's client is gone.
close_steam(){
  local title=$1 why=$2 out
  steam_running || return 0
  if game_running; then
    ui_msg "$title" "A game is running in Steam ARM. $why

Quit the game, then try again."; return 1
  fi
  if ! grep -q -- '--shutdown' "$SA_LAUNCHER" 2>/dev/null; then
    ui_msg "$title" "Steam ARM is running. $why

Close Steam ARM completely (Exit from its menu or tray), then try again."; return 1
  fi
  ui_yesno "$title" "Steam ARM is running. $why

Close Steam now? Steam ARM asks the client to exit, as Exit in its menu does; this can take up to a minute." "Close Steam" Back || return 1
  [ "$(id -un)" = "$(game_user)" ] || need_root || return 1
  ui_info "$title" "Closing Steam..."
  out=$(steam_shutdown | tail -3)
  steam_running || return 0
  ui_msg "$title" "Steam did not close.${out:+

$out}

Close Steam ARM completely (Exit from its menu or tray), then try again."
  return 1
}
# Run installer with args as root, with progress (download bars on the built-in screen); env GPU_FAMILY/GAMEUSER from INST_ENV.
run_installer(){
  local title=$1 rc; shift
  local -a cmd; mapfile -t cmd < <(installer_cmd) || true
  [ "${#cmd[@]}" -gt 0 ] || { ui_msg "$title" "Setup script not found. Get it from $SA_DOCS and run it once."; return 1; }
  local e gu=""
  for e in "${INST_ENV[@]}"; do case $e in GAMEUSER=?*) gu=${e#GAMEUSER=};; esac; done
  # setup checks the client of the account it installs for; an account not created yet runs none
  if [ -n "$gu" ] && [ "$gu" != "$(conf_get GAMEUSER)" ]; then
    if getent passwd "$gu" >/dev/null 2>&1; then GU_OVERRIDE=$gu close_steam "$title" "Setup stops while it runs." || return 1; fi
  else
    close_steam "$title" "Setup stops while it runs." || return 1
  fi
  need_root || return 1
  if [ -L "$SA_CACHE" ]; then
    ui_msg "$title" "$SA_CACHE is a link. Delete the link (rm \"$SA_CACHE\"), then try again."; return 1
  fi
  if ! { mkdir -p "$SA_CACHE" && [ ! -L "$SA_CACHE" ] && chmod 700 "$SA_CACHE" \
         && SA_SETUP_LOG=$(mktemp --suffix=.log "$SA_CACHE/setup-$(date +%Y%m%d-%H%M%S)-XXXXXX"); }; then
    ui_msg "$title" "Could not create a log file in $SA_CACHE. Free some space, then try again."; return 1
  fi
  ui_run "$title" "$SA_SETUP_LOG" as_root env "${INST_ENV[@]}" ${STEAM_ARM_ALLOW_ARMV80:+"STEAM_ARM_ALLOW_ARMV80=$STEAM_ARM_ALLOW_ARMV80"} STEAM_ARM_FROM_MENU=1 STEAM_ARM_PROGRESS="$([ "$DIALOG" = builtin ] && echo 1)" "${cmd[@]}" "$@"; rc=$?
  status_line
  if [ "$rc" = 0 ]; then
    ui_textstr "$title: done" "$({ echo "Finished."; echo; log_summary "$SA_SETUP_LOG"; echo
      echo "Full output: $SA_SETUP_LOG"; } | tilde | pre_fold)"
  else
    ui_textstr "$title: failed" "$({ echo "Setup stopped (status $rc). Last lines:"; echo
      strip_ansi < "$SA_SETUP_LOG" | grep -v '^[[:space:]]*$' | tail -10; echo
      echo "Full output: $SA_SETUP_LOG (Maintenance > View logs)."; } | tilde | pre_fold)"
  fi
  return "$rc"
}
# Closing block of a setup log: from its last "done" step line, else its last 8 lines.
log_summary(){
  strip_ansi < "$1" | grep -v '^[[:space:]]*$' \
    | awk '/^==> (11\/11  done|done:)/ { n = 0; keep = 1 } { l[++n] = $0 }
           END { s = (keep ? 1 : (n > 8 ? n - 7 : 1)); for (i = s; i <= n; i++) print l[i] }'
}
# Text for a box: lines wider than it folded at a space, continued under their own value column (else their first non-space column).
pre_fold(){
  local c w; read -r _ c < <({ stty size </dev/tty; } 2>/dev/null || echo "24 80")
  if [ "$DIALOG" = builtin ]; then w=$(( c - 4 )); [ "$w" -gt 76 ] && w=76; w=$(( w - 6 ))
  else ui_size; w=$(( UW - 5 )); fi
  [ "$w" -ge 20 ] || w=20
  # Join hard-wrapped "Key: value" rows first (value-column lines; deeper keyless lines after no end punctuation).
  awk -v w="$w" '
  function fold(l,    ind, pad, k) {
    if (length(l) <= w) { print l; return }
    ind = 0
    if (match(l, /^\[[a-z]+\] /) || match(l, /^==> [^ ]+ +/) || match(l, /^ *[A-Za-z][A-Za-z0-9 ().\/-]*: +/)) ind = RLENGTH
    if (ind == 0 || ind > w / 2) { match(l, /^ */); ind = RLENGTH; if (ind > w / 2) ind = int(w / 2) }
    pad = sprintf("%" ind "s", "")
    while (length(l) > w) {
      k = w + 1
      while (k > ind + 1 && substr(l, k, 1) != " ") k--
      if (k <= ind + 1) k = w + 1
      print substr(l, 1, k - 1)
      l = substr(l, k); sub(/^ +/, "", l); l = pad l
    }
    print l
  }
  {
    l = $0; gsub(/\t/, "        ", l)
    match(l, /^ */); lead = RLENGTH
    key = match(l, /^ *[A-Za-z][A-Za-z0-9 ().\/-]*: +/) ? RLENGTH : 0
    if (have && vcol && l ~ /[^ ]/ && (lead == vcol || (!key && lead > kind && prev !~ /[.!?:;] *$/))) {
      row = row " " substr(l, lead + 1); prev = l; next
    }
    if (have) flush()
    row = l; prev = l; have = 1; vcol = key; kind = lead
  }
  # key rows: one space between words of the value text, key column kept
  function flush(    v) {
    if (vcol) { v = substr(row, vcol + 1); gsub(/  +/, " ", v); row = substr(row, 1, vcol) v }
    fold(row)
  }
  END { if (have) flush() }'
}
INST_ENV=()
GU_OVERRIDE=   # never taken from the environment
# Run installer in the plain terminal (it asks its own questions there).
run_installer_tty(){
  local -a cmd; mapfile -t cmd < <(installer_cmd) || true
  [ "${#cmd[@]}" -gt 0 ] || { ui_msg "Steam ARM" "Setup script not found."; return 1; }
  close_steam "Uninstall" "Removal stops while it runs." || return 1
  if pgrep -x steam >/dev/null 2>&1; then
    ui_msg "Uninstall" "A Steam client of another account is running. Close it first (exit from its menu), then try again."; return 1
  fi
  need_root || return 1
  clear
  as_root env ${STEAM_ARM_ALLOW_ARMV80:+"STEAM_ARM_ALLOW_ARMV80=$STEAM_ARM_ALLOW_ARMV80"} "${cmd[@]}" "$@"; local rc=$?
  ui_pause; status_line; return "$rc"
}

# ===========================================================================
# Components
# ===========================================================================
comp_short(){ case "$1" in
  glx-lax)    echo "GL fix for games that draw from several threads";;
  vk-spoof)   echo "Vulkan layer for Windows games (Mali only)";;
  gpu-in-emulation) echo "Mali drivers inside emulation, used when needed";;
  shader-cache) echo "Shader pre-caching: videos in Windows games";;
  physx-skip) echo "PhysX install step: mark done / stop after 60 s";;
  map-count)  echo "Raise memory map limit (Windows games want it)";;
  xpad-dedup) echo "One joystick per third-party Xbox 360 pad";;
  pad-hidraw) echo "Direct pad access: rumble, battery level";;
  pad-xbox)   echo "Show other XInput pads as Xbox 360 pads";;
  desktop)    echo "Menu entry \"Steam ARM\"";;
  desktop-mode) echo "Menu entry \"Steam ARM (Desktop mode)\"";;
  icon-bigpicture) echo "Desktop icon \"Steam ARM\"";;
  icon-desktop) echo "Desktop icon \"Steam ARM (Desktop mode)\"";;
  tray)       echo "Steam icon in the panel tray";;
  kde-input-prompt) echo "KDE: no input prompt; X11 apps may send input";;
  page-size)  echo "Raspberry Pi 5: switch to 4K page kernel";;
  *)          echo "$1";;
esac; }
# Component names from installer --list, else built-in list.
comp_all(){
  local -a cmd; local l=""
  mapfile -t cmd < <(installer_cmd)
  [ "${#cmd[@]}" -gt 0 ] && l=$("${cmd[@]}" --list 2>/dev/null </dev/null | strip_ansi | awk '/^[ \t]+[a-z][a-z0-9-]+[ \t]/ { print $1 }' | tr '\n' ' ')
  l=${l:-$SA_COMPONENTS}
  page_size_applies || l=$(echo " $l " | sed 's/ page-size / /')
  kde_applies || l=$(echo " $l " | sed 's/ kde-input-prompt / /')
  echo "$l" | trim
}
# kde-input-prompt part applies where KDE Plasma's Wayland compositor is installed, or while its setting is in place.
kde_applies(){ have kwin_wayland || [ -f "$(game_home)/.config/steam-arm/kde-input-prompt" ]; }
# Recommended set for family $1 (auto = detect) and Vulkan yes/no: installer's defaults, else built-in rules.
comp_recommended(){
  local fam=$1 vk=$2 c out
  out=$(detect_components "$fam")
  if [ -z "$out" ]; then
    [ "$fam" = auto ] && fam=$(gpu_family)
    for c in $(comp_all); do
      case " $SA_DEFAULT_OFF " in *" $c "*) continue;; esac
      case " $SA_MALI_ONLY " in *" $c "*) is_mali "$fam" || continue;; esac
      out="$out $c"
    done
  fi
  [ "$vk" = no ] && out=$(echo " $out " | sed 's/ vk-spoof / /')
  echo "$out" | trim
}
comp_checklist(){
  local title=$1 text=$2 pre=" $3 " c items=()
  for c in $(comp_all); do
    case "$pre" in *" $c "*) items+=("$c" "$(comp_short "$c")" ON);; *) items+=("$c" "$(comp_short "$c")" OFF);; esac
  done
  ui_check "$title" "$text" "${items[@]}"
}

# ===========================================================================
# 1. Information
# ===========================================================================
info_system(){
  local ps; ps=$(page_size)
  cat <<EOF
Board          $(hw_model)
SoC            $(hw_soc)
GPU            $(gpu_name)
GPU family     $(family_label "$(gpu_family)")
Kernel driver  $(gpu_driver)
Vulkan         $(vk_summary)
Vulkan gaps    $(vk_gaps)
Page size      $ps ($(page_label "$ps")$([ "$ps" = 4096 ] && echo ", OK" || echo ", x86 games need 4K"))
Distribution   $(distro)
Kernel         $(uname -r)
Mesa           $(mesa_ver)
OpenGL         $(gl_summary)
CPU            $(cpu_info | wrap_row)
CPU governor   $(cpu_governor)
FEX            $(fex_ver)
Disk free      $(disk_free "$(game_home)")
EOF
}
# Features vk-spoof reports that the Vulkan driver lacks (setup --detect, layer off).
vk_gaps(){
  local m; m=$(detect_get vulkanfeaturesmissing)
  case "$m" in
    '') m=$(detect_get vulkanfeatures); echo "${m:-unknown}";;
    none) echo "none (driver has every feature vk-spoof covers)";;
    *) printf '%s\n' "$m" | tr ' ' ',' | wrap_list;;
  esac
}
# Host OpenGL renderer and versions (compatibility, core) from glxinfo; what forwarding hands x86 titles.
GL_SUMMARY=""
gl_summary(){
  local out r v c
  if [ -z "$GL_SUMMARY" ]; then
    if ! have glxinfo; then GL_SUMMARY="unknown (glxinfo not installed)"
    elif [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then GL_SUMMARY="unknown (no desktop session in this terminal)"
    elif ! out=$(timeout 10 glxinfo -B 2>/dev/null); then GL_SUMMARY="unknown (glxinfo failed)"
    else
      r=$(sed -n 's/^ *OpenGL renderer string: //p' <<<"$out" | head -1)
      v=$(sed -n 's/^ *OpenGL version string: \([0-9.]*\).*/\1/p' <<<"$out" | head -1)
      c=$(sed -n 's/^ *OpenGL core profile version string: \([0-9.]*\).*/\1/p' <<<"$out" | head -1)
      GL_SUMMARY="${r:-unknown} (GL ${v:-?}, core ${c:-?})"
    fi
  fi
  echo "$GL_SUMMARY"
}
# Governor and max clock per cpufreq policy (cluster); "mixed" when governors differ.
cpu_governor(){
  local p c g f out
  out=$(for p in "$SA_CPUFREQ"/policy*; do
          g=$(cat "$p/scaling_governor" 2>/dev/null) || continue
          c=$(cat "$p/related_cpus" 2>/dev/null || cat "$p/affected_cpus" 2>/dev/null)
          f=$(cat "$p/scaling_max_freq" 2>/dev/null)
          printf '%s|%s|%s\n' "$g" "${f:+$((f / 1000))}" "$c"
        done | awk -F'|' '
    function span(s,   n, a, i, j, k, x, r) {
      n = split(s, a, " ")
      for (i = 2; i <= n; i++) { x = a[i] + 0; for (j = i - 1; j >= 1 && a[j] + 0 > x; j--) a[j + 1] = a[j]; a[j + 1] = x }
      for (i = 1; i <= n; i = k + 1) {
        for (k = i; k < n && a[k + 1] == a[k] + 1; k++) ;
        r = r (r == "" ? "" : ",") (k > i ? a[i] "-" a[k] : a[i])
      }
      return r
    }
    $1 != "" { key = $1 "|" $2; if (!(key in cpus)) { order[++n] = key; gov[key] = $1; mhz[key] = $2 }
               cpus[key] = cpus[key] " " $3; if (!($1 in seen)) { seen[$1] = 1; ng++ } }
    END {
      if (!n) exit
      for (i = 1; i <= n; i++) { k = order[i]
        s = s (i > 1 ? ", " : "") "cpu " span(cpus[k]) (ng > 1 ? " " gov[k] : "") (mhz[k] != "" ? " max " mhz[k] " MHz" : "") }
      print (ng > 1 ? "mixed" : gov[order[1]]) ": " s
    }')
  echo "${out:-unknown}"
}
info_status(){
  if ! is_installed; then echo "Steam ARM is not installed. Use Install / Setup."; return; fi
  local on off
  on=$(conf_get COMPONENTS_ON | wrap_list); off=$(conf_get COMPONENTS_OFF | wrap_list)
  cat <<EOF
Installed      yes, version $(installed_version)
Client type    $(client_label)
Game account   $(game_user)
Client home    $(arm_home | tilde)
Client channel $(client_channel)
FEX tool       $(fex_tool_row)
Graphics       $(gfx_default_label "$(gfx_default)")
Mali tree      $(mali_tree)
Driver archive $(da_status | wrap_row -h)
Components on  ${on:-none}
Components off ${off:-none}
GE-Proton      $(ge_state)
EOF
}
# Own notes when installer gives none.
info_notes_builtin(){
  local ps fam; ps=$(page_size); fam=$(gpu_family)
  case "$fam" in
    mali-kbase) echo "- Mali GPU on the closed driver: Mesa cannot use it. Use a kernel with Panthor or Panfrost.";;
    mali-utgard) echo "- Mali-400/450: too old for Steam games.";;
    mali-*)     echo "- Mali GPU on open drivers: Mali-only parts can be used.";;
    adreno*)    echo "- Adreno GPU: Windows games through DXVK expected to work. Mali-only parts stay off.";;
    broadcom-*) echo "- Raspberry Pi GPU: OpenGL games fit best; Vulkan is too limited for most Windows games.";;
    apple-agx)  echo "- Apple GPU: 16K-page kernel not supported; setup does not set up a 4K-page VM (muvm).";;
    amd-*|nvidia-*|intel) echo "- PC graphics card: forwarding covers it. Mali-only parts stay off.";;
    virtio-gpu) echo "- Virtual machine: expect software drawing unless the VM passes the GPU through.";;
    *)          echo "- No GPU driver found: games would draw on the CPU.";;
  esac
  [ "$ps" = 4096 ] || echo "- Page size is $(page_label "$ps"). x86 games need 4K pages; see Install / Setup."
  vk_ok || echo "- No Vulkan driver found: Windows games (Proton) will not start."
}
info_notes(){
  local n; n=$(detect_notes)
  if [ -n "$n" ]; then printf '%s\n' "$n" | sed 's/^\([^-]\)/- \1/'; else info_notes_builtin; fi
  if [ "$(client_type)" = x86 ] && [ "$(conf_get CLIENT_SET)" = user ] && cpu_has_lse; then
    echo "- x86 client chosen by hand: slower start, client window on CPU; native client runs on this CPU (Maintenance > Client type)."
  elif [ "$(client_type)" = x86 ]; then
    echo "- x86 client: slower start, client window on CPU; native client returns once Valve fixes #13288 (Maintenance > Client type)."
  fi
  case "$(gl_summary)" in *llvmpipe*|*softpipe*|*"Software Rasterizer"*)
    echo "- GPU forwarding not active: rendering on CPU (llvmpipe). Host OpenGL itself draws on CPU: GPU driver missing, or this session has no GPU access.";;
  esac
}
menu_info(){
  local c=""
  while c=$(ui_menu "Information" "What do you want to see?" --default "$c" \
      1 "System (board, GPU, drivers)" 2 "Steam ARM status" 3 "Notes for this hardware"); do
    case "$c" in
      1) ui_info "Information" "Reading system details..."; ui_textstr "System" "$(info_system)";;
      2) ui_info "Information" "Reading Steam ARM status..."; ui_textstr "Steam ARM status" "$(info_status)";;
      3) ui_textstr "Notes for this hardware" "$(info_notes)";;
    esac
  done
}

# ===========================================================================
# 2. Install / Setup
# ===========================================================================
# Sets IN_HW, IN_FAM (installer GPU_FAMILY id, auto = detect) and IN_DRV. Status 1 on Back.
setup_hardware(){
  local g lab c items=() id l f
  g=$(hw_guess)
  if [ -n "$g" ]; then lab="Detected: $(hw_label "$g")"
  elif [ "$(gpu_family)" != none ]; then lab="Detected: $(family_label "$(gpu_family)")"
  else lab="Nothing detected: safe defaults"; fi
  items=(auto "${lab:0:44} (recommended)")
  while IFS='|' read -r id l f; do items+=("$id" "$l"); done < <(hw_table)
  while :; do
    c=$(ui_menu "Install: hardware" "Pick your hardware. The detected choice fits most systems." --default "${IN_HW:-auto}" "${items[@]}") || return 1
    IN_HW=$c; IN_DRV=""
    f=$(hw_table | awk -F'|' -v id="$c" '$1 == id { print $3 }')
    case "$c" in
      auto)  IN_FAM=auto; IN_DRV=$(gpu_driver); return 0;;
      mediatek|snapdragon|pc) setup_gpu_model "$c" && return 0;;
      other) setup_driver && return 0;;
      *)     IN_FAM=$f
             case "$c" in rk3588) IN_DRV=panthor;; rk356x) IN_DRV=panfrost;; rpi5|rpi4) IN_DRV=v3d;;
               asahi) IN_DRV=asahi;; vm) IN_DRV=virtio_gpu;; esac
             return 0;;
    esac
  done
}
# GPU of boards that come with several; sets IN_FAM and IN_DRV. Status 1 on Back.
setup_gpu_model(){
  local c
  case "$1" in
    mediatek)
      c=$(ui_menu "Install: MediaTek GPU" "Which Mali GPU?" \
          mali-valhall-jm "Mali-G57 / G77 (MT8192, MT8195, Kompanio 1200/1380)" \
          mali-bifrost "Mali-G52 / G72 (MT8183, MT8186, Helio)" \
          mali-csf-v11 "Mali-G615 / G715 (Dimensity 8300, 9200)" \
          mali-csf-5thgen "Mali-G720 / G925 (MT8196, Dimensity 9300+)" \
          mali-csf-g1 "Mali-G1 (Dimensity 9500)" \
          mali-panfrost "Other Mali / not sure") || return 1
      case "$c" in mali-csf*) IN_DRV=panthor;; *) IN_DRV=panfrost;; esac;;
    snapdragon)
      c=$(ui_menu "Install: Adreno GPU" "Which Adreno GPU?" \
          adreno-a7xx "Adreno 7xx (X Elite, X Plus, 8 Gen 1/2/3)" \
          adreno-a6xx "Adreno 6xx (8cx, 7c, 865, 888)" \
          adreno-a8xx "Adreno 8xx (8 Elite)" \
          adreno "Other Adreno / not sure") || return 1
      IN_DRV=msm;;
    pc)
      c=$(ui_menu "Install: graphics card" "Which graphics card?" \
          amd-radv "AMD (amdgpu)" nvidia-nouveau "NVIDIA, open driver (nouveau)" \
          nvidia-prop "NVIDIA, NVIDIA driver" intel "Intel") || return 1
      case "$c" in amd-radv) IN_DRV=amdgpu;; nvidia-nouveau) IN_DRV=nouveau;; nvidia-prop) IN_DRV=nvidia;; intel) IN_DRV=i915;; esac;;
  esac
  IN_FAM=$c
}
setup_driver(){
  local c
  c=$(ui_menu "Install: GPU driver" "Which kernel GPU driver does this system use?
Information > System shows the detected one." \
      panthor "Mali, newer chips (panthor)" panfrost "Mali, older chips (panfrost)" \
      lima "Mali-400/450 (lima)" mali_kbase "Mali, closed driver (mali_kbase)" \
      msm "Adreno (msm)" v3d "Raspberry Pi 4/5 (v3d)" vc4 "Raspberry Pi 0-3 (vc4)" \
      etnaviv "Vivante (etnaviv)" powervr "PowerVR (powervr)" asahi "Apple GPU (asahi)" \
      amdgpu "AMD (amdgpu)" radeon "AMD, old cards (radeon)" nouveau "NVIDIA (nouveau)" \
      nvidia "NVIDIA driver (nvidia)" i915 "Intel (i915 / xe)" virtio_gpu "Virtual GPU (virtio)" \
      none "No GPU driver / not sure") || return 1
  IN_DRV=$c; IN_FAM=$(family_of_driver "$c" || echo none)
}
setup_pagesize(){
  local ps txt; ps=$(page_size)
  if [ "$ps" = 4096 ]; then
    txt="Page size: 4K. Good, nothing to do."
  else
    txt="Page size: $(page_label "$ps"). x86 games and the emulator need 4K pages.

Raspberry Pi 5: keep the \"page-size\" part on. Setup switches the
boot firmware to the 4K kernel; reboot, then run setup again.

Apple Silicon: a 16K page kernel is not supported, and setup does
not set up a 4K page virtual machine (muvm).

Other boards: boot a kernel built with 4K pages.

Setup stops with this advice until the page size is 4K."
  fi
  ui_yesno "Install: page size" "$txt" Next Back
}
setup_vulkan(){
  local d def c; d=$(vk_summary); def=yes; vk_ok "$d" || def=no
  c=$(ui_menu "Install: Vulkan" "Detected Vulkan: ${d:0:60}
Windows games (Proton) need Vulkan." \
      "$def" "$([ "$def" = yes ] && echo "Vulkan works (detected, recommended)" || echo "No Vulkan (detected, recommended)")" \
      "$([ "$def" = yes ] && echo no || echo yes)" "$([ "$def" = yes ] && echo "No Vulkan" || echo "Vulkan works")") || return 1
  IN_VK=$c
}
setup_components(){
  local c rec
  ui_info "Install: parts" "Working out the recommended parts..."
  rec=$(comp_recommended "$IN_FAM" "$IN_VK")
  # Back from the checklist returns to this parts menu
  while :; do
    c=$(ui_menu "Install: parts" "Which parts to install? Client and launcher are always installed." \
        rec "Recommended" min "Minimal (client and launcher only)" custom "Custom (pick from a list)") || return 1
    case "$c" in
      rec) IN_COMPS=$rec; return 0;;
      min) IN_COMPS=""; return 0;;
      custom) c=$(comp_checklist "Install: custom parts" "SPACE turns a part on or off. TAB moves to the buttons." "$rec") || continue
              IN_COMPS=$(echo "$c" | tr '\n' ' ' | trim); return 0;;
    esac
  done
}
# Normal accounts (uid 1000-59999, login shell, home present): name TAB home.
normal_accounts(){
  getent passwd 2>/dev/null | while IFS=: read -r u _ id _ _ h sh; do
    [[ "$id" =~ ^[0-9]+$ ]] && [ "$id" -ge 1000 ] && [ "$id" -lt 60000 ] || continue
    case "$sh" in */nologin|*/false) continue;; esac
    [ -n "$h" ] && [ -d "$h" ] && printf '%s\t%s\n' "$u" "$h"
  done | awk -F'\t' '!seen[$1]++'
}
# Account of the graphical session (active one first), if any.
desktop_user(){
  local s k v n t c a first=""
  have loginctl || return 0
  while read -r s _; do
    n="" t="" c="" a=""
    while IFS='=' read -r k v; do
      case "$k" in Name) n=$v;; Type) t=$v;; Class) c=$v;; Active) a=$v;; esac
    done < <(loginctl show-session "$s" -p Name -p Type -p Class -p Active 2>/dev/null </dev/null)
    case "$t" in x11|wayland|mir) ;; *) continue;; esac
    [ "$c" = user ] && [ -n "$n" ] || continue
    [ "$a" = yes ] && { echo "$n"; return 0; }
    [ -n "$first" ] || first=$n
  done < <(loginctl list-sessions --no-legend 2>/dev/null </dev/null)
  [ -n "$first" ] && echo "$first"
  return 0
}
# Account that runs this menu: the sudo caller, else a non-root user.
caller_user(){
  local u=${SUDO_USER:-}; [ "$u" = root ] && u=""
  [ -z "$u" ] && [ "$(id -u)" != 0 ] && u=$(id -un)
  echo "$u"
}
# Account list items (tag, label) in ACCT_ITEMS; names in ACCT_NAMES; ACCT_CUR, ACCT_DESK.
acct_list(){
  local u h d
  ACCT_ITEMS=(); ACCT_NAMES=" "; ACCT_CUR=$(caller_user); ACCT_DESK=$(desktop_user)
  while IFS=$'\t' read -r u h; do
    d=""; [ "$u" = "$ACCT_CUR" ] && d="current user, "; [ "$u" = "$ACCT_DESK" ] && d="${d}desktop user, "
    ACCT_ITEMS+=("$u" "$d$h"); ACCT_NAMES="$ACCT_NAMES$u "
  done < <(normal_accounts)
}
# First argument that is a listed account.
acct_default(){
  local u
  for u in "$@"; do [ -n "$u" ] && [[ "$ACCT_NAMES" == *" $u "* ]] && { echo "$u"; return 0; }; done
  return 0
}
# Pick an existing normal account, or create one. Status 1 on Back.
setup_account(){
  local c def
  acct_list
  if [ ${#ACCT_ITEMS[@]} -eq 0 ]; then
    setup_new_account "No normal account found on this system, so setup creates one."
    return
  fi
  # default: configured account on a re-run, then caller, desktop user, uid 1000
  def=$(acct_default "$(is_installed && conf_get GAMEUSER)" "$ACCT_CUR" "$ACCT_DESK" "$(getent passwd 1000 2>/dev/null | cut -d: -f1)")
  while :; do
    c=$(ui_menu "Install: account" "Account that plays games (its home holds the client and games):" \
        --default "$def" "${ACCT_ITEMS[@]}" + "Create a new account...") || return 1
    if [ "$c" = "+" ]; then
      setup_new_account && return 0
      def="+"; continue
    fi
    IN_USER=$c; IN_PASS=""; IN_PASS_MADE=0; return 0
  done
}
# Name of an account setup creates, then its password. Status 1 on Back.
setup_new_account(){
  local u="" note=${1:+$1

}
  while :; do
    u=$(ui_input "Install: new account" "${note}Name of the new account that plays games:" "$u") || return 1
    if [[ ! "$u" =~ ^[A-Za-z0-9._@][A-Za-z0-9._@-]{0,31}$ ]]; then
      ui_msg "Install: new account" "Use letters, digits, '.', '_', '@' and '-' only (up to 32), not starting with '-'."
    elif [ "$u" = root ]; then
      ui_msg "Install: new account" "root is the administrator account. Pick another name."
    elif getent passwd "$u" >/dev/null 2>&1; then
      ui_msg "Install: new account" "Account $u already exists. Pick another name, or go Back to pick it from the list when it is there."
    else
      IN_USER=$u; IN_PASS=""; IN_PASS_MADE=0
      setup_password && return 0
    fi
  done
}
# Password of an account setup creates: typed twice, or made here and shown once after install. Never logged.
setup_password(){
  local a b
  while :; do
    a=$(ui_password "Install: password" "Account $IN_USER does not exist yet; setup creates it.

Password for it (leave empty to have one made and shown at the end):") || return 1
    if [ -z "$a" ]; then
      IN_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 14); IN_PASS_MADE=1; return 0
    fi
    b=$(ui_password "Install: password" "Type the password for $IN_USER again:") || return 1
    [ "$a" = "$b" ] && { IN_PASS=$a; IN_PASS_MADE=0; return 0; }
    ui_msg "Install: password" "The two entries differ. Type them again."
  done
}
setup_summary(){
  local fam note=""
  fam=$IN_FAM; [ "$fam" = auto ] && fam=$(gpu_family)
  getent passwd "$IN_USER" >/dev/null 2>&1 || note="
               (new account; password $([ "$IN_PASS_MADE" = 1 ] && echo "made by setup, shown at the end" || echo "as typed"))"
  local hw="detected"; [ "$IN_HW" = auto ] || hw=$(hw_label "$IN_HW")
  local h d dl="Setup downloads the client and its files (several GB) and can
take a while."
  h=$(getent passwd "$IN_USER" 2>/dev/null | cut -d: -f6); d=$(conf_get ARMHOME_DIR)
  case "$d" in ''|/*|..|../*|*/..|*/../*) d=.local/share/steam-arm;; esac
  local ct="native ARM64"; [ "$(planned_client)" = x86 ] && ct="x86 client through emulation"
  if [ "$ct" = "native ARM64" ]; then
    [ -n "$h" ] && [ -x "$h/${d%/}/.local/share/Steam/steamrtarm64/steam" ] && dl="Client already present: setup keeps it (it updates itself)."
  else
    [ -n "$h" ] && [ -x "$h/${d%/}/.local/share/Steam/ubuntu12_32/steam" ] && dl="Client already present: setup keeps it (it updates itself)."
  fi
  ui_yesno "Install: summary" "Hardware       $hw
Client         $ct
GPU            $(family_label "$fam")${IN_DRV:+, driver $IN_DRV}
Page size      $(page_label "$(page_size)")
Vulkan         $IN_VK
Account        $IN_USER$note
Parts          $(echo "${IN_COMPS:-none}" | fold -s -w 55 | sed '2,$s/^/               /')

$dl" Install Back
}
# Other variant of the installer present (setup --detect-other; a setup without that option counts as none).
other_present(){
  local -a cmd; mapfile -t cmd < <(installer_cmd) || true
  [ "${#cmd[@]}" -gt 0 ] && timeout 60 "${cmd[@]}" --detect-other >/dev/null 2>&1 </dev/null
}
# Replace other variant before install: IN_REPLACE=1 on yes. Status 1 on Back.
setup_other(){
  IN_REPLACE=0
  other_present || return 0
  ui_yesno "Install: other variant" "Another Steam ARM install (other variant) is present. Replace it?

Games, sign-in and client folder are kept; its files are archived in /var/backups." Replace Back || return 1
  IN_REPLACE=1
}
setup_run(){
  local rc; local -a xo=()
  [ "${IN_REPLACE:-0}" = 1 ] && xo=(--replace-other)
  INST_ENV=("GAMEUSER=$IN_USER" "GPU_FAMILY=${IN_FAM:-auto}")
  if [ -n "$IN_PASS" ]; then
    UI_STDIN=$IN_PASS
    run_installer "Install" --password-stdin "${xo[@]}" "--select=$(echo "$IN_COMPS" | tr ' ' ',')"; rc=$?
    UI_STDIN=""
    if [ "$rc" = 0 ] && [ "$IN_PASS_MADE" = 1 ]; then
      ui_msg "Install: new account" "Account $IN_USER was created. Its password:

    $IN_PASS

Write it down now; it is not saved anywhere. Change it later with:
passwd $IN_USER"
    elif [ "$rc" = 0 ]; then
      ui_msg "Install: new account" "Account $IN_USER was created with the password you typed."
    fi
    IN_PASS=""
    return "$rc"
  fi
  run_installer "Install" "${xo[@]}" "--select=$(echo "$IN_COMPS" | tr ' ' ',')"
}
menu_setup(){
  local step=1
  # CPU text: shown when setup picks x86 client on an Armv8.0 CPU
  { cpu_has_lse || [ "$(planned_client)" != x86 ]; } || ui_yesno "Install: x86 client" "$X86_MSG" Continue Back || return
  if is_installed; then
    ui_yesno "Install / Setup" "Steam ARM is already installed. Run setup again with new choices?

Games, sign-in and settings are kept." Continue Back || return
  fi
  IN_HW=auto IN_FAM=auto IN_DRV="" IN_VK=yes IN_COMPS="" IN_USER="" IN_PASS="" IN_PASS_MADE=0 IN_REPLACE=0
  # detection cached in this shell: screens reopen at once on Back
  ui_info "Install / Setup" "Reading hardware details..."; detect_raw >/dev/null
  while :; do
    case "$step" in
      0) return;;
      1) if setup_hardware; then step=2; else step=0; fi;;
      2) if setup_pagesize; then step=3; else step=1; fi;;
      3) if setup_vulkan; then step=4; else step=2; fi;;
      4) if setup_components; then step=5; else step=3; fi;;
      5) if setup_account; then step=6; else step=4; fi;;
      6) if setup_summary; then setup_other && { setup_run; return; }; else step=5; fi;;
    esac
  done
}

# ===========================================================================
# 3. Components
# ===========================================================================
# Size of steamapps/shadercache per library (best effort; nothing when none found).
shader_cache_sizes(){
  local lib out=""
  while IFS= read -r lib; do
    [ -d "$lib/steamapps/shadercache" ] || continue
    out+=$(du -sh "$lib/steamapps/shadercache" 2>/dev/null | awk -F'\t' -v l="$lib" '{ printf "\n  %-6s %s", $1, l }')
  done < <(game_libraries)
  [ -z "$out" ] || printf '\n\nsteamapps/shadercache size now, per library:%s' "$(tilde <<<"$out")"
}
menu_components(){
  local c=""
  if ! is_installed; then offer_install; return; fi
  while c=$(ui_menu "Components" "Parts of Steam ARM, and source of driver archive for gpu-in-emulation." --default "$c" \
      1 "Parts (checklist)" 2 "Driver archive for gpu-in-emulation (now: $(da_state))"); do
    case "$c" in 1) components_parts;; 2) menu_driver_archive;; esac
  done
}
components_parts(){
  local c was note=""; was=$(comps_effective)
  c=$(comp_checklist "Components" "Parts to keep. Turning one off removes it; games are kept." "$was") || return
  c=$(echo "$c" | tr '\n' ' ' | trim)
  [[ " $was " == *" shader-cache "* && " $c " != *" shader-cache "* ]] && note="

shader-cache off keeps the downloaded cache; turning it on
again reuses it. Deleting steamapps/shadercache by hand stops
Steam from downloading those caches again.$(shader_cache_sizes)"
  [[ " $was " == *" physx-skip "* && " $c " != *" physx-skip "* ]] && note="$note

physx-skip off stops only the PhysX watcher at launch;
nothing is removed."
  ui_yesno "Components" "Apply this selection?

${c:-(none)}$note

Setup runs again; this takes a few minutes." Apply Back || return
  INST_ENV=(); run_installer "Components" "--select=$(echo "$c" | tr ' ' ',')"
}
menu_driver_archive(){
  local c="" f h
  detect_raw >/dev/null
  read -r f h <<<"$(da_pub)"
  while c=$(ui_menu "Components: driver archive" "Archive with Mali drivers for emulated games (gpu-in-emulation).
Now: $(da_status)
Published archive: $f, sha256 ${h:0:12}..." --default "$c" \
      dl "Download from project release (recommended)" \
      local "Local copy of published archive..." \
      custom "Custom archive (own Mesa build)..."); do
    case "$c" in dl) da_download;; local) da_local "$f" "$h";; custom) da_custom;; esac
  done
}
# Setup run with driver archive env $2...; turns gpu-in-emulation on after asking when it is off. $1: published|custom.
da_apply(){
  local kind=$1 sel="--keep" note=""; shift
  if [[ " $(comps_effective) " != *" gpu-in-emulation "* ]]; then
    [ "$kind" = published ] && ! mali_family && note="

Published archive carries Mali drivers only; games on this GPU stay on forwarding."
    ui_yesno "Driver archive" "gpu-in-emulation is off. Turn it on with this file?$note" "Turn on" Back || return 1
    sel="--select=$(echo "$(comps_effective) gpu-in-emulation" | trim | tr ' ' ',')"
  fi
  # published file over a saved custom archive: setup drops the custom settings only with --provider-default
  local -a pd=(); [ "$kind" = published ] && [ -n "$(conf_get PROVIDER_CUSTOM_SHA256)" ] && pd=(--provider-default)
  INST_ENV=("$@"); run_installer "Driver archive" "$sel" "${pd[@]}"
}
da_local(){
  local f=$1 h=$2 p="" d i e
  i=$(find_installer 2>/dev/null) && i=${i%/*}
  for d in "$(conf_get PROVIDER_LOCAL_FILE)" ${i:+"$i/$f"} "$(owner_home)/Downloads/$f"; do
    case "$d" in /*) [ -f "$d" ] && { p=$d; break; };; esac
  done
  while :; do
    p=$(ui_input "Driver archive: local copy" "Path of $f:" "$p") || return 1
    e=$(da_path_err "$p")
    [ -z "$e" ] || { ui_msg "Driver archive: local copy" "$e"; continue; }
    da_hash "$p" || continue
    [ "$DA_SHA" = "$h" ] && break
    ui_msg "Driver archive: local copy" "File does not match published archive (sha256 ${DA_SHA:0:12}..., expected ${h:0:12}...). Download it again, or pick Custom archive for own Mesa build."
  done
  ui_yesno "Driver archive: local copy" "Use this file in place of a download?

$p

Setup runs again and saves the path for later runs. Mali tree is rebuilt only when it holds another archive." Run Back || return 1
  da_apply published "STEAM_ARM_PROVIDER_TARBALL=$p"
}
da_custom(){
  local p x e
  p=$(conf_get PROVIDER_CUSTOM_FILE)
  while :; do
    p=$(ui_input "Driver archive: custom" "Path of custom driver archive (.tar.zst):" "$p") || return 1
    e=$(da_path_err "$p")
    [ -z "$e" ] || { ui_msg "Driver archive: custom" "$e"; continue; }
    x=""
    [ -r "$p.sha256" ] && x=$(head -c 64 "$p.sha256" | tr 'A-F' 'a-f')
    if [[ "$x" =~ ^[0-9a-f]{64}$ ]]; then
      ui_yesno "Driver archive: custom" "Expected SHA-256, from $p.sha256:

$x" OK Back || continue
    else
      x=$(ui_input "Driver archive: custom" "SHA-256 of this archive (64 characters, sha256sum prints it):" "") || continue
      x=$(printf '%s' "$x" | tr -d ' \t' | tr 'A-F' 'a-f')
      [[ "$x" =~ ^[0-9a-f]{64}$ ]] || { ui_msg "Driver archive: custom" "SHA-256 must be 64 characters, 0-9 and a-f."; continue; }
    fi
    da_hash "$p" || continue
    [ "$DA_SHA" = "$x" ] && break
    ui_msg "Driver archive: custom" "Checksum differs: file has $DA_SHA, expected $x. Nothing changed."
  done
  ui_yesno "Driver archive: custom" "Custom archive, not published one. Results depend on Mesa version and kernel GPU driver. Setup keeps it on every later run until Download is picked here." Use Back || return 1
  da_apply custom "STEAM_ARM_PROVIDER_TARBALL=$p" "STEAM_ARM_PROVIDER_SHA256=$x"
}
da_download(){
  if [ -n "$(conf_get PROVIDER_CUSTOM_SHA256)" ]; then
    ui_yesno "Driver archive" "Go back to published archive? Setup downloads it (about 75 MB) and rebuilds Mali tree; custom archive stays when download fails." Run Back || return 1
    INST_ENV=(); run_installer "Driver archive" --keep --provider-default
  elif [ -n "$(conf_get PROVIDER_LOCAL_FILE)" ]; then
    self_root driver-archive download || return 1
    ui_msg "Driver archive" "Driver archive: download from project release on next build of Mali tree. Mali tree in place unchanged."
  else
    ui_msg "Driver archive" "Already set to download."
  fi
}

# ===========================================================================
# 4. Graphics
# ===========================================================================
graphics_default(){
  local cur c now n; cur=$(gfx_default)
  local -a items=(auto "Automatic: forwarding, Mali drivers where needed$([ "$cur" = auto ] && echo " *")"
                  a "Forwarding for all: game GL/Vulkan run on host drivers$([ "$cur" = a ] && echo " *")")
  now=$(gfx_default_label "$cur"); n=""
  if route_b_ok; then items+=(b "Mali drivers in emulation for all (slower CPU)$([ "$cur" = b ] && echo " *")")
  else
    n=$'\n'"$SA_NO_ROUTE_B"; [ "$cur" = b ] && now="b (not used on this GPU)"
  fi
  c=$(ui_menu "Graphics: default route" "Route for games without their own setting. Now: $now.$n" "${items[@]}") || return
  [ "$c" = "$cur" ] && return
  self_root gfx-default "$c" && status_line && ui_msg "Graphics" "Default route: $(gfx_default_label "$c"). Applies from the next game start.$(
    n=$(route_b_note "$c"); [ -n "$n" ] && printf '\n\n%s' "$n")"
}
# Pick an installed game; prints appid. $1 = title, $2 = key to show (gfx or profile), $3 = appid to start on.
pick_game(){
  local title=$1 show=$2 def=${3:-} id name dir items=() r maps="" autos="" cpus
  if ! is_installed; then offer_install; return 1; fi
  [ "$show" = gfx ] && { maps=$(compat_map); autos=$(ab_list | awk -F'\t' '$1 == "app" && $3 == "auto" { print $2 }'); }
  cpus=" $(cpu_apps | tr '\n' ' ')"
  while IFS=$'\t' read -r id name dir; do
    [ -n "$id" ] || continue
    case "$show" in
      gfx) r=$(compat_label "$(awk -v id="$id" '$1 == id { print $2; exit }' <<<"$maps")")
           # GE label shortened to fit 24 columns
           case "$r" in "Windows build (GE-"*) r="Windows, ${r#Windows build (}"; r=${r%)};; esac
           grep -qx "$id" <<<"$autos" && r="Windows (auto)"
           [ -n "$r" ] || r=$(gfx_label "$(tc_get "$id" gfx)");;
      *)   r=$(tc_effective "$id" | grep -v '^gfx=' | tr '\n' ' ' | trim); r=${r:-default};;
    esac
    [[ "$cpus" == *" $id "* ]] && r="${r:0:19} CPU!"
    items+=("$id" "$(printf '%-36.36s %s' "$name" "${r:0:24}")")
  done < <(games_list)
  if [ "${#items[@]}" = 0 ]; then
    ui_msg "$title" "No installed games found in $(steam_dir | tilde).

Install games from the Steam ARM client first."; return 1
  fi
  ui_menu "$title" "Installed games (App ID, name, current setting):" --default "$def" "${items[@]}"
}
graphics_game(){
  local id name cur c src note="" map abv sug=""
  ab_reset; ab_list >/dev/null
  id=$(pick_game "Graphics: per game" gfx) || return
  name=$(game_name "$id"); cur=$(tc_get "$id" gfx); src=$(tc_source "$id" gfx); map=$(compat_tool "$id")
  [ -n "$src" ] && [ "$src" = "$(titles_user)" ] && note="
Note: the client home file sets this game; it wins over this menu."
  local now; now=$(gfx_label "$cur")
  case "$(compat_label "$map")" in Linux*) now="Linux build${cur:+, $now}";; Windows*) now=$(compat_label "$map");; esac
  abv=$(ab_app "$id")
  case "$abv" in
    auto) now="$now, set automatically"; note="$note"$'\n'"Reason: $(ab_app "$id" 5)."$'\n'"Automatic lets rule set it again; Force Linux build keeps Linux build.";;
    suggest) sug=" (suggested)"; note="$note"$'\n'"Windows build suggested: $(ab_what "$(ab_app "$id" 4)") Linux build fails under emulation ($(ab_app "$id" 5)).";;
    pending) sug=" (suggested)"; note="$note"$'\n'"Windows build set at next start of Steam ARM: $(ab_app "$id" 5).";;
  esac
  local -a items=(auto "Automatic (rules decide)$([ -z "$cur$map" ] && echo " *")" a "A: forwarding to host drivers$([ "$cur" = a ] && echo " *")")
  if route_b_ok; then items+=(b "B: Mali drivers in emulation$([ "$cur" = b ] && echo " *")")
  else
    note="$note"$'\n'"$SA_NO_ROUTE_B"; [ "$cur" = b ] && now="b (not used on this GPU)"
  fi
  local ge; ge=$(ge_newest)
  local -a gi=(); [ -n "$ge" ] && gi=(ge "Force Windows build, ${ge%-aarch64} (needs Steam closed)$(case "$map" in GE-Proton*) echo " *";; esac)")
  c=$(ui_menu "Graphics: ${name:0:40}" "App $id. Route now: $now.$note" "${items[@]}" \
      linux "Force Linux build (needs Steam closed)$([ "$(compat_label "$map")" = "Linux build" ] && echo " *")" \
      windows "Force Windows build, Proton (needs Steam closed)$sug$([ "$(compat_label "$map")" = "Windows build (Proton)" ] && echo " *")" \
      "${gi[@]}") || return
  case "$c" in
    auto|a|b) self_root gfx "$id" "$c" || return
              # auto also drops a forced build
              if [ "$c" = auto ] && [ -n "$map" ]; then graphics_compat "$id" clear "$name"; return; fi
              ui_msg "Graphics" "${name}: $(gfx_label "$c"). Applies from the next start of the game.$(
                n=$(route_b_note "$c"); [ -n "$n" ] && printf '\n\n%s' "$n")";;
    linux|windows|ge) graphics_compat "$id" "$c" "$name";;
  esac
}
graphics_compat(){
  local id=$1 how=$2 name=$3 out
  [ -x "$SA_COMPATMAP" ] || { ui_msg "Graphics" "Helper steam-arm-compatmap is missing. Run Maintenance > Update / Repair."; return; }
  close_steam "Graphics" "It rewrites this setting when it exits." || return
  need_root || return
  out=$(as_root bash "$(self_path)" compat "$id" "$how" 2>&1)
  ui_msg "Graphics" "${name}: $(case "$how" in linux) echo "Linux build";;
    windows) if [ "$(client_type)" = x86 ]; then echo "Windows build with x86 Proton ($X86_PROTON, untested tool name)"; else echo "Windows build with Proton"; fi;;
    ge) t=$(ge_newest); echo "Windows build with ${t%-aarch64}";; *) echo "Automatic, forced build removed";; esac).

$out

In Steam, the game may download its other build on next start."
}
graphics_auto_build(){
  local st rules gates n t
  ab_reset; ab_list >/dev/null; st=$(auto_build)
  rules=$(ab_list | awk -F'\t' '$1 == "rule" { printf "  %s (GPU family %s, FEX tool up to %s)\n", $6, $4, $5 }')
  gates=$(ab_list | awk -F'\t' '$1 == "gate" && $3 != "-" && $3 != "AUTO_BUILD=off" { print $3; exit }')
  n=$(ab_list | awk -F'\t' '$1 == "app" && $3 == "auto"' | grep -c .)
  t="Automatic Windows build: $st

Titles whose Linux build is known to fail under emulation get
Windows build (Proton ARM64) when Steam ARM starts, once per title,
only when no build is chosen for them:
${rules:-  (rule file missing: Maintenance > Update / Repair)}
Steam downloads Windows build in background once client is up.
Set for: $(n_games "$n"). Route per game shows and undoes each."
  [ -n "$gates" ] && t="$t
On this system: suggestion only ($gates)."
  if [ "$st" = on ]; then
    ui_yesno "Automatic Windows build" "$t

Turning off keeps titles already set (Steam's setting now)." "Turn off" Back defaultno || return
    self_root auto-build off && ui_msg "Graphics" "Automatic Windows build: off. Titles already set keep Windows build; Route per game changes them."
  else
    ui_yesno "Automatic Windows build" "$t" "Turn on" Back || return
    self_root auto-build on && ui_msg "Graphics" "Automatic Windows build: on. Applies at next start of Steam ARM."
  fi
}
graphics_cpu_notice(){
  local st t; st=$(cpu_notice)
  t="CPU drawing notice: $st

When an x86 game draws on CPU (llvmpipe) because GPU forwarding
is not active, a desktop notice says so once per start and stays
until closed. Game log line \"renderer:\" names the cause either
way; game lists of this menu mark such games CPU!.
Not for Windows games on ARM64 Proton or native ARM64 games.
GoldSrc games get no notice: their Software renderer is a choice
in their video options."
  if [ "$st" = on ]; then
    ui_yesno "CPU drawing notice" "$t" "Turn off" Back defaultno || return
    self_root cpu-notice off && ui_msg "Graphics" "CPU drawing notice: off. Applies from the next game start."
  else
    ui_yesno "CPU drawing notice" "$t" "Turn on" Back || return
    self_root cpu-notice on && ui_msg "Graphics" "CPU drawing notice: on. Applies from the next game start."
  fi
}
menu_graphics(){
  local c=""
  is_installed || { offer_install; return; }
  while c=$(ui_menu "Graphics" "How x86 games reach the GPU. A: forwarding to host drivers. B: Mali drivers inside emulation." --default "$c" \
      1 "Default route (now: $(gfx_default_label "$(gfx_default)"))" 2 "Route per game" \
      3 "Automatic Windows build (now: $(auto_build))" 4 "CPU drawing notice (now: $(cpu_notice))"); do
    case "$c" in 1) graphics_default;; 2) graphics_game;; 3) graphics_auto_build;; 4) graphics_cpu_notice;; esac
  done
}

# ===========================================================================
# 5. Games
# ===========================================================================
# Steam Deck category and runtime of one title ("deck<TAB>runtime") from client's appinfo cache; read as game account.
deck_hint(){
  local f o=""; f="$(steam_dir)/appcache/appinfo.vdf"
  [ -f "$SA_APPINFO_PY" ] && o=$(game_read timeout 3 python3 "$SA_APPINFO_PY" "$f" "$1" 2>/dev/null </dev/null)
  o=$(awk -F'\t' -v id="$1" '$1 == id { print $2 "\t" $4; exit }' <<<"$o")
  printf '%s\n' "${o:-unknown	unknown}"
}
deck_line(){ echo "Steam Deck: $(cut -f1 <<<"$1") (hint only: Steam Deck has other GPU)."; }
game_rules(){
  local id=$1 f
  if f=$(game_fexlog "$id"); then
    echo "Last start of this game ($(date -r "$f" '+%F %H:%M' 2>/dev/null)):"
    echo
    grep -a 'steam-arm:' "$f" | tail -20 | sed 's/^.*steam-arm: */  /' | tilde
  else
    echo "No log of this game yet. Start it once; logs of the last start live in /tmp"
    echo "(Windows games through Proton write no such log)."
  fi
  echo
  echo "Profile: $(tc_effective "$id" | tr '\n' ' ' | trim)"
  echo "Steam Deck runtime: $(deck_hint "$id" | cut -f2)"
}
game_set(){ self_root profile "$1" "$2=$3"; }
# How a game runs: windows (Proton mapped, Windows build installed, or Proton prefix in compatdata), linux (other tool mapped), unknown.
game_kind(){
  local id=$1 t lib
  t=$(compat_tool "$id")
  case "$t" in *[Pp]roton*) echo windows; return;; ?*) echo linux; return;; esac
  while IFS= read -r lib; do
    grep -qsiE '^[[:space:]]*"platform_override_source"[[:space:]]+"windows"' "$lib/steamapps/appmanifest_$id.acf" \
      && { echo windows; return; }
  done < <(game_libraries)
  # Steam's default Proton writes no mapping; FEX-run Linux games leave only "fex-emu" in compatdata
  while IFS= read -r lib; do
    t="$lib/steamapps/compatdata/$id"
    { [ -d "$t/pfx" ] || grep -qsi proton "$t/version"; } && { echo windows; return; }
  done < <(game_libraries)
  echo unknown
}
# Profile value for display, $3 when unset.
tc_show(){ local v; v=$(tc_get "$1" "$2"); v=${v:-$3}; echo "${v:0:24}"; }
game_choose(){
  local id=$1 key=$2 title=$3; shift 3
  local cur c; cur=$(tc_get "$id" "$key")
  c=$(ui_menu "$title" "Now: ${cur:-default}" "$@" default "Default (remove this setting)") || return
  [ "$c" = default ] && c=""
  game_set "$id" "$key" "$c"
}
game_text(){
  local id=$1 key=$2 title=$3 help=$4 cur v
  cur=$(tc_get "$id" "$key")
  while :; do
    v=$(ui_input "$title" "$help
Separate items with ; (no spaces). Empty removes it." "$cur") || return
    valid_value "$v" && break
    ui_msg "$title" "Spaces and # are not allowed here."
  done
  game_set "$id" "$key" "$v"
}
game_diskcache(){
  local id=$1 cur v note c
  cur=$(tc_get "$id" diskcache); v=$(fex_tool_ver)
  if fex_cache_ok; then note="FEX tool: $v."
  else note="FEX tool: $v. Needs FEX-2609.1 or newer; setting is kept and applies once Steam updates tool."; fi
  c=$(ui_menu "FEX code cache" "Stores translated code of this game for its next start. Uses disk space (Maintenance > Caches shows it).
Now: ${cur:-off}. $note" --default "${cur:-default}" on "On" off "Off" default "Default (remove this setting)") || return
  [ "$c" = default ] && c=""
  game_set "$id" diskcache "$c"
}
game_menu(){
  local id=$1 name c="" win=0 deck; name=$(game_name "$id")
  [ "$(game_kind "$id")" = windows ] && win=1
  deck=$(deck_line "$(deck_hint "$id")")
  while :; do
    # profiles reach Linux games only (emulation handler); Proton reads Steam launch options
    if [ "$win" = 1 ]; then
      c=$(ui_menu "Game: ${name:0:50}" "App $id. Windows game (Proton): these settings apply to Linux games only. Use Steam launch options."$'\n'"$deck" \
          --default "$c" rules "Rules used at last start" clear "Remove all settings for this game") || break
    else
      c=$(ui_menu "Game: ${name:0:50}" "App $id. Settings apply from the next start of the game."$'\n'"$deck" --default "$c" \
          overlay "Steam overlay        [$(tc_show "$id" overlay default)]" \
          mangohud "MangoHud             [$(tc_show "$id" mangohud default)]" \
          env "Extra environment    [$(tc_show "$id" env none)]" \
          args "Extra arguments      [$(tc_show "$id" args none)]" \
          diskcache "FEX code cache       [$(tc_show "$id" diskcache off)]" \
          rules "Rules used at last start" \
          clear "Remove all settings for this game") || break
    fi
    case "$c" in
      overlay)  game_choose "$id" overlay "Steam overlay" x86 "On (default for most games)" vulkan "On, for Vulkan games" off "Off";;
      mangohud) game_choose "$id" mangohud "MangoHud" on "On" off "Off";;
      env)      game_text "$id" env "Extra environment" "Variables, for example: DXVK_HUD=fps;MESA_NO_ERROR=1";;
      args)     game_text "$id" args "Extra arguments" "Arguments, for example: -windowed;-nosound";;
      diskcache) game_diskcache "$id";;
      rules)    ui_textstr "Rules: ${name:0:40}" "$(game_rules "$id")";;
      clear)    ui_yesno "Game: ${name:0:50}" "Remove every setting for this game from $SA_TITLES_ETC (route included)?" Remove Back defaultno \
                  && self_root profile "$id" --clear;;
    esac
  done
}
menu_games(){
  local id=""
  while id=$(pick_game "Games" profile "$id"); do game_menu "$id"; done
}

# ===========================================================================
# 6. Controllers
# ===========================================================================
pads_input(){
  awk '/^N: Name=/ { n = $0; sub(/^N: Name="/, "", n); sub(/"$/, "", n) }
       /^H: Handlers=/ && / js[0-9]/ { h = $0; sub(/^H: Handlers=/, "", h); printf "  %-40.40s %s\n", n, h }' \
    "/proc/bus/input/devices" 2>/dev/null
}
pads_hidraw(){
  local u n i
  for u in /sys/class/hidraw/hidraw*/device/uevent; do
    [ -r "$u" ] || continue
    n=$(sed -n 's/^HID_NAME=//p' "$u"); i=$(sed -n 's/^HID_ID=//p' "$u" | awk -F: '{printf "%s:%s", substr($2, 5), substr($3, 5)}')
    printf '  %-10s %-40.40s %s\n' "$(basename "$(dirname "$(dirname "$u")")")" "$n" "$i"
  done
}
rule_state(){ [ -e "$1" ] && echo "installed" || echo "not installed"; }
padxbox_state(){
  [ -e "$SA_PADXBOX_UNIT" ] || { echo "not installed"; return; }
  systemctl is-active steam-arm-pad-xbox >/dev/null 2>&1 && echo "installed, running" || echo "installed, not running"
}
controllers_text(){
  local p h
  p=$(pads_input); h=$(pads_hidraw)
  cat <<EOF
Joysticks (kernel input):
${p:-  none found}

Raw HID devices (hidraw):
${h:-  none found}

Rules:
  pad-hidraw   direct pad access        $(rule_state "$SA_RULE_HIDRAW")
  xpad-dedup   one joystick per pad     $(rule_state "$SA_RULE_DEDUP")
  pad-xbox     Xbox 360 look-alike      $(padxbox_state)
EOF
}
controllers_padxbox(){
  local on new c
  is_installed || { offer_install; return; }
  if comp_is_on pad-xbox; then
    ui_yesno "pad-xbox" "pad-xbox is on. It shows other makers' XInput pads as Xbox 360 pads.

Turn it off? Setup runs again (a few minutes)." "Turn off" Back || return
    new=$(comps_effective | tr ' ' '\n' | grep -vx pad-xbox | tr '\n' ' ')
  else
    ui_yesno "pad-xbox" "pad-xbox is off. Turn it on when a non-Microsoft XInput pad is not recognised in games. The Steam client usually handles pads by itself.

Turn it on? Setup runs again (a few minutes)." "Turn on" Back || return
    new="$(comps_effective) pad-xbox"
  fi
  c=$(echo "$new" | tr -s ' ' ',' | sed 's/^,//; s/,$//')
  INST_ENV=(); run_installer "Controllers" "--select=$c"
}
menu_controllers(){
  local c=""
  while c=$(ui_menu "Controllers" "Game pads and their rules." --default "$c" \
      1 "Show pads and rules" 2 "pad-xbox (now: $(comp_is_on pad-xbox && echo on || echo off))"); do
    case "$c" in 1) ui_textstr "Controllers" "$(controllers_text)";; 2) controllers_padxbox;; esac
  done
}

# ===========================================================================
# 7. Remote Play
# ===========================================================================
# Run steam-arm-remoteplay as the game account.
rp_run(){
  [ -x "$SA_REMOTEPLAY" ] || { echo "Helper steam-arm-remoteplay is missing (not installed)."; return 1; }
  if [ "$(id -un)" = "$(game_user)" ]; then "$SA_REMOTEPLAY" "$@" 2>&1; return; fi
  as_root runuser -u "$(game_user)" -- "$SA_REMOTEPLAY" "$@" 2>&1
}
# Other accounts read the game account's files through root (ask before any $(...) capture).
rp_ready(){ [ "$(id -un)" = "$(game_user)" ] || need_root; }
# Helper output with "Account: <id> (pinned)" lines in place of localconfig.vdf paths.
rp_show(){
  local out; out=$(rp_run "$@" | sed -E \
    -e 's#^.*/userdata/([0-9]+)/config/localconfig\.vdf: (already pinned|pinned .*|ClientConfig entry created, pinned.*)$#Account: \1 (pinned)#' \
    -e 's#^.*/userdata/([0-9]+)/config/localconfig\.vdf: not pinned \((.*)\)$#Account: \1 (not pinned: \2)#' \
    -e 's#^.*/userdata/([0-9]+)/config/localconfig\.vdf: #Account: \1: #' | tilde)
  echo "Settings (hardware decoding off, HEVC off):"
  printf '%s\n' "${out:-no answer}" | awk '{ print "  " $0 }'
}
rp_status(){ rp_show --check; }
rp_help(){ cat <<'EOF'
Remote Play streams a game from another computer (the host) to
this one.

- Sign in to the same Steam account on both.
- Keep the game in front on the host. A stream that shows one
  frame and stops means the game is in the background there.
- First time: this device shows a 4-digit code. Type it on the
  HOST within 60 seconds.
- Decoding runs on the CPU here, so keep the stream at 1080p or
  lower.
- Steam ARM pins the settings it needs before each start. "Apply
  settings now" does the same by hand (Steam must be closed).
EOF
}
menu_remoteplay(){
  local c=""
  is_installed || { offer_install; return; }
  while c=$(ui_menu "Remote Play" "Stream games from another computer." --default "$c" \
      1 "Show settings state" 2 "How pairing works" 3 "Apply settings now"); do
    case "$c" in
      1) rp_ready && ui_textstr "Remote Play" "$(rp_status)";;
      2) ui_textstr "Remote Play: pairing" "$(rp_help)";;
      3) close_steam "Remote Play" "It rewrites these settings when it exits." && rp_ready \
           && ui_textstr "Remote Play" "$(rp_show)";;
    esac
  done
}

# ===========================================================================
# 8. Maintenance
# ===========================================================================
# Scrubber of sanitize: stdin to stdout. Arguments h=home u=account n=full name s=host v=loginusers.vdf.
san_py(){ cat <<'PY'
import ipaddress, re, sys
STOP = {"steam", "games", "game", "user", "users", "admin", "administrator", "pi", "root", "guest", "test", "ubuntu",
        "debian", "linux", "arm", "default", "video", "render", "input", "audio", "player", "home", "desktop", "localhost"}
lit, homes, check = [], [], []
def add(v, tag, ci=False, chk=True):
    v = v.strip()
    if v and len(v) <= 128:
        lit.append((v, tag, ci))
        # self-check list: identifying names still present after scrubbing drop their line
        if chk and len(v) >= 4 and v.lower() not in STOP:
            check.append(v.lower())
for a in sys.argv[1:]:
    k, _, v = a.partition("=")
    if k == "h" and v.startswith("/") and len(v) > 1:
        homes.append(v.rstrip("/"))
    elif k in ("u", "n"):
        add(v, "<user>")
    elif k == "s":
        add(v, "<host>", True)
        add(v.split(".")[0], "<host>", True)
    elif k == "v":
        try:
            t = open(v, encoding="utf-8", errors="replace").read()
        except OSError:
            t = ""
        for m in re.finditer(r'"(7656119[0-9]{10})"\s*\{([^{}]*)\}', t):
            aid = int(m.group(1)) - 76561197960265728
            if aid >= 10000:
                add(str(aid), "<steamid>", chk=False)
            for key, val in re.findall(r'"(AccountName|PersonaName)"\s+"((?:[^"\\]|\\.)*)"', m.group(2)):
                val = val.replace('\\"', '"').replace("\\\\", "\\")
                add(val, "<login>", key == "AccountName", key == "AccountName")
B, A = r"(?<![A-Za-z0-9_.<-])", r"(?![A-Za-z0-9_>-]|\.[A-Za-z0-9])"
rules = []
for h in sorted(set(homes), key=len, reverse=True):
    rules.append((re.compile(re.escape(h) + r"(?![A-Za-z0-9_.-])"), "~"))
rules += [(re.compile(r"/home/[^/\s\"']*"), "~"), (re.compile(r"/root\b"), "~"),
          (re.compile(r"(\\{1,2})home\1[^\\\s\"']+"), r"\1~"),
          (re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"), "<email>"),
          (re.compile(r"(?i)\b(token|ticket|password|passwd|secret|auth|session|sessionid|access_token|steamLoginSecure)=[^&\s\"']+"),
           r"\1=<removed>")]
seen = set()
for v, tag, ci in sorted(lit, key=lambda x: -len(x[0])):
    if (v.lower(), tag) in seen:
        continue
    seen.add((v.lower(), tag))
    e, f = re.escape(v), re.I if ci else 0
    if tag != "<steamid>" and (v.lower() in STOP or len(v) < 3):
        # common words and short names: path and assignment context only
        rules.append((re.compile(r"(/media/|/run/media/|=)" + e + r"(?![A-Za-z0-9_.-])", f), r"\1" + tag))
    else:
        # host names: domain suffix may follow
        rules.append((re.compile(B + e + (r"(?![A-Za-z0-9_>-])" if tag == "<host>" else A), f), tag))
rules += [
    (re.compile(r'"(AccountName|PersonaName)"(\s+)"(?:[^"\\]|\\.)*"'), r'"\1"\2"<login>"'),
    (re.compile(r"\b(SteamUser|SteamAppUser|STEAM_USER|SteamUserName)=[^\s&\"']+"), r"\1=<login>"),
    (re.compile(r"\b7656119[0-9]{10}\b"), "<steamid>"),
    (re.compile(r"\[U:[0-9]:[0-9]+\]"), "<steamid>"),
    (re.compile(r"\bSTEAM_[0-5]:[01]:[0-9]+\b"), "<steamid>"),
    (re.compile(r"(?i)\b(steamid[=:\"\s]+)[0-9]+"), r"\1<steamid>"),
    (re.compile(r"userdata/[0-9]+"), "userdata/<steamid>"),
    (re.compile(r"\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b"), "<mac>"),
    # interface names built from MAC (enx..., wlx...)
    (re.compile(r"\b(enx|wlx)[0-9a-fA-F]{12}\b"), r"\1<mac>"),
]
O = r"(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
V4 = re.compile(r"(?<![0-9A-Za-z.-])" + O + r"(?:\." + O + r"){3}(?![0-9A-Za-z]|\.[0-9])")
V6 = re.compile(r"(?<![0-9A-Za-z:.])[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?:%[0-9A-Za-z_.-]+)?(?![0-9A-Za-z:])")
def v4(m):
    # version numbers (v1.2.3.4, version 1.2.3.4) and loopback stay
    if m.group(0) in ("127.0.0.1", "0.0.0.0") or re.search(r"(?i)version[ :=]*$", m.string[max(0, m.start() - 16):m.start()]):
        return m.group(0)
    return "<ip>"
def v6(m):
    a = m.group(0).split("%")[0]
    if ("::" not in a and a.count(":") != 7) or a in ("::", "::1") or len(re.sub("[^0-9A-Fa-f]", "", a)) < 4:
        return m.group(0)
    try:
        ipaddress.IPv6Address(a)
    except ValueError:
        return m.group(0)
    return "<ip6>"
out = sys.stdout.buffer
for line in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").splitlines(True):
    for rx, rep in rules:
        line = rx.sub(rep, line)
    line = V6.sub(v6, V4.sub(v4, line))
    if any(c in line.lower() for c in check):
        line = "(line removed: personal data)\n"
    out.write(line.encode("utf-8", "surrogateescape"))
PY
}
# Report text with personal details removed: home paths, account, Steam sign-in and persona names, Steam IDs, host name,
# addresses, MACs, e-mail, tokens. Without python3 nothing passes.
sanitize(){
  local u g args=()
  if ! have python3; then cat >/dev/null; echo "(report text left out: python3 is missing; it removes personal details)"; return 1; fi
  args+=("h=$(game_home)")
  for u in "$(game_user)" "${SUDO_USER:-}" "$(id -un)"; do
    [ -n "$u" ] && [ "$u" != root ] || continue
    g=$(getent passwd "$u" 2>/dev/null | cut -d: -f5 | cut -d, -f1)
    args+=("u=$u" "n=$g")
  done
  args+=("s=$(hostname 2>/dev/null)" "v=$(steam_dir)/config/loginusers.vdf")
  python3 -c "$(san_py)" "${args[@]}"
}
report_text(){
  local d f
  echo "Steam ARM hardware report ($(date -u +%F))"
  echo "steam-arm-config $SA_VERSION"
  echo
  echo "== System"; info_system
  echo "Architecture   $(uname -m)"
  echo "Memory         $(awk '/^MemTotal/ { printf "%.1f GB\n", $2 / 1048576 }' "/proc/meminfo" 2>/dev/null)"
  echo "GPU drivers    $(gpu_drivers | tr '\n' ' ')"
  echo
  echo "== Steam ARM"; info_status
  if is_installed && cache_readable; then echo "FEX code cache on for $(n_games "$(dc_on_count)"), $(kb_h "$(cache_scan | awk -F'\t' '{ s += $3 } END { print s + 0 }')") in caches"
  elif is_installed; then echo "FEX code cache on for $(n_games "$(dc_on_count)"), cache sizes unknown (no read access to game account's folder)"; fi
  is_installed && ab_list >/dev/null
  is_installed && echo "Automatic build $(auto_build), $(ab_list | awk -F'\t' '$1 == "app" && $3 == "auto"' | grep -c .) set, $(ab_list | awk -F'\t' '$1 == "app" && ($3 == "suggest" || $3 == "pending")' | grep -c .) suggested"
  echo
  echo "== Client"
  echo "CLIENT=$(conf_get CLIENT) CLIENT_SET=$(conf_get CLIENT_SET) CLIENT_PROBE=$(conf_get CLIENT_PROBE)"
  if [ "$(client_type)" = x86 ]; then
    for f in "$(steam_dir)/logs/webhelper-linux.txt" "$(steam_dir)/logs/bootstrap_log.txt"; do
      [ -r "$f" ] || continue
      echo "$(basename "$f"):"; grep -aiE 'error|fail|check-requirements' "$f" | tail -10
    done
  else
    f="$(steam_dir)/logs/steamwebhelper.log"
    [ -r "$f" ] && grep -aq 'error while loading shared libraries' "$f" \
      && { echo "steamwebhelper.log:"; grep -a 'error while loading shared libraries' "$f" | tail -3; }
  fi
  echo
  echo "== Notes"; info_notes
  d=$(detect_raw)
  if [ -n "$d" ]; then echo; echo "== Setup --detect"; echo "$d"; fi
  echo
  echo "== Game profiles (/etc/steam-arm/titles.conf)"
  grep -v '^[[:space:]]*#' "$SA_TITLES_ETC" 2>/dev/null | grep -v '^[[:space:]]*$' || echo "(none)"
  echo
  echo "== Renderer at recent game starts (newest first)"
  renderer_lines | grep . || echo "(no renderer line yet: start game once)"
  f=$(fexlogs | head -1)
  if [ -n "$f" ] && [ -r "$f" ]; then echo; echo "== Last game start"; grep -a 'steam-arm:' "$f" | tail -15; fi
  echo
  echo "== Launcher log (last 20 lines)"
  f="$(arm_home)/steam-arm.log"
  if [ -r "$f" ]; then tail -20 "$f" | grep . || echo "(empty: launcher writes warnings only)"; else echo "(none, or not readable by this account)"; fi
  echo
  echo "== Client bootstrap log (start, update and error lines)"
  f="$(steam_dir)/logs/bootstrap_log.txt"
  if [ -r "$f" ]; then grep -aE 'Startup - |Update complete|[Ee]rror|[Ff]ail' "$f" | tail -15 | grep . || echo "(no such lines)"
  else echo "(none, or not readable by this account)"; fi
  echo
  echo "== Last setup run"
  f=$(setuplogs | head -1)
  if [ -n "$f" ] && [ -r "$f" ]; then echo "$(basename "$f"):"; log_summary "$f"; else echo "(no setup log of this account)"; fi
  echo
  echo "== Groups of game account"; report_groups
}
# Groups of game account, those its running processes hold (set at login), and the ones no process has yet (new login adds them).
report_groups(){
  local u pid pids g n ids="" live="" miss=""
  u=$(game_user)
  if [ -z "$u" ] || ! id "$u" >/dev/null 2>&1; then echo "(no game account)"; return; fi
  echo "Account        $(id -nG "$u" 2>/dev/null)"
  pids=$(pgrep -u "$u" 2>/dev/null)
  [ -n "$pids" ] || { echo "Running        (no process of this account)"; return; }
  for pid in $pids; do ids="$ids $(awk '/^Gid:/ { print $2 } /^Groups:/ { $1 = ""; print }' "/proc/$pid/status" 2>/dev/null)"; done
  for g in $ids; do
    n=$(getent group "$g" | cut -d: -f1); n=${n:-$g}
    case " $live " in *" $n "*) ;; *) live="$live $n";; esac
  done
  echo "Running       $live"
  for g in $(id -nG "$u" 2>/dev/null); do case " $live " in *" $g "*) ;; *) miss="$miss $g";; esac; done
  [ -z "$miss" ] || echo "Not active yet:$miss (log out and back in)"
}
# "app <id>: <renderer line>" of the five newest game logs.
renderer_lines(){
  local f id l
  while IFS= read -r f; do
    [ -r "$f" ] || continue
    l=$(grep -a 'steam-arm: renderer:' "$f" | tail -1 | sed 's/^.*steam-arm: renderer: *//')
    [ -n "$l" ] || continue
    id=$(grep -a -m1 -oE '^Steam(App|Game)Id=[0-9]+' "$f" | cut -d= -f2)
    echo "app ${id:-unknown}: $l"
  done < <(fexlogs | head -5)
}
# Written by the account whose home gets it (no root write into a user folder).
report_make(){
  if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    # shellcheck disable=SC2016
    report_text 2>/dev/null | sanitize | runuser -u "$SUDO_USER" -- sh -c 'cat > "$1"' sh "$SA_REPORT"
  else
    report_text 2>/dev/null | sanitize > "$SA_REPORT"
  fi
}
maint_report(){
  ui_info "Hardware report" "Collecting details..."
  report_make
  ui_text "Hardware report" "$SA_REPORT"
  ui_msg "Hardware report" "Saved to $SA_REPORT (your home folder).

Home folders, account names, Steam sign-in names, Steam IDs, host name, network addresses and e-mail addresses are removed. Attach the file to a compatibility report at:
$SA_DOCS/issues"
}
maint_logs(){
  local c="" f
  while c=$(ui_menu "View logs" "Newest lines are at the end." --default "$c" \
      1 "Launcher log" 2 "Last game start (emulation tool)" 3 "Last setup run"); do
    case "$c" in
      1) f="$(arm_home)/steam-arm.log";;
      2) f=$(fexlogs | head -1);;
      3) f=$(setuplogs | head -1);;
    esac
    if { [ -z "$f" ] || [ ! -e "$f" ]; } && [ "$c" = 3 ] && [ "$(id -u)" != 0 ]; then
      ui_msg "View logs" "No setup log of this account. Setup runs from sudo steam-arm-config are logged in the administrator's folder ($(r=$(getent passwd 0 | cut -d: -f6); echo "${r:-/root}")/.cache/steam-arm). Run sudo steam-arm-config to view them."
    elif [ -z "$f" ] || [ ! -e "$f" ]; then ui_msg "View logs" "No log found yet."
    elif [ ! -r "$f" ]; then ui_msg "View logs" "$(basename "$f") is not readable by this account. Run sudo steam-arm-config to read it."
    elif [ -s "$f" ]; then ui_textstr "Log: $(basename "$f")" "$(tail -300 "$f" | strip_ansi | tilde)"
    elif [ "$c" = 1 ]; then ui_msg "View logs" "$(basename "$f") is empty (launcher writes warnings only)."
    else ui_msg "View logs" "$(basename "$f") is empty."; fi
  done
}
SA_RELEASE_API=https://api.github.com/repos/Scrumpper/Steam-ARM/releases/latest
# Newest published release vs this version (asked by hand only; nothing downloads); status 0 newer, 1 not newer, 2 failed.
update_check(){
  local f code tag url v cur
  cur=$(installed_version); case "$cur" in [0-9]*) ;; *) cur=$SA_VERSION;; esac
  have curl || { echo "curl is not installed. Releases: $SA_DOCS/releases"; return 2; }
  have python3 || { echo "python3 is not installed. Releases: $SA_DOCS/releases"; return 2; }
  f=$(tmpf) || { echo "$TMP_FAIL"; return 2; }
  code=$(curl -sS --max-time 20 -o "$f" -w '%{http_code}' -H 'Accept: application/vnd.github+json' "$SA_RELEASE_API" 2>/dev/null)
  case "$code" in
    200) ;;
    403|429) rm -f "$f"; echo "GitHub refused the request (request limit for this address). Try again in an hour, or see $SA_DOCS/releases"; return 2;;
    404) rm -f "$f"; echo "No published release found at $SA_DOCS/releases"; return 2;;
    000|'') rm -f "$f"; echo "GitHub could not be reached (offline, or address blocked). Releases: $SA_DOCS/releases"; return 2;;
    *) rm -f "$f"; echo "GitHub answered with HTTP $code. Releases: $SA_DOCS/releases"; return 2;;
  esac
  read -r tag url < <(python3 -c 'import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
t = str(d.get("tag_name") or "-").split() or ["-"]
print(t[0], (str(d.get("html_url") or "").split() or ["-"])[0])' "$f" 2>/dev/null)
  rm -f "$f"
  v=${tag#steam-arm-}; v=${v#v}
  # 2.3-hotfix style tags: number part compared, full tag shown
  [[ "${v%%-*}" =~ ^[0-9]+(\.[0-9]+)*$ ]] && [[ "$v" =~ ^[0-9.]+(-[A-Za-z0-9.]+)?$ ]] \
    || { echo "Release answer not understood (tag ${tag:-none}). Releases: $SA_DOCS/releases"; return 2; }
  case "$url" in https://github.com/*) ;; *) url="$SA_DOCS/releases";; esac
  # 2.2.0 and 2.2 are the same version
  local a=${v%%-*} b=$cur
  while [[ "$a" == *.0 ]]; do a=${a%.0}; done
  while [[ "$b" == *.0 ]]; do b=${b%.0}; done
  if [ "$a" = "$b" ] && [ "$v" = "${v%%-*}" ]; then
    echo "Steam ARM $cur is the newest release."; return 1
  fi
  if [ "$a" != "$b" ] && [ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | tail -1)" = "$b" ]; then
    echo "Steam ARM $cur is newer than the newest release ($v)."; return 1
  fi
  echo "Newer release: Steam ARM $v (installed: $cur)."
  echo "$url"
  echo
  echo "Download that release, unpack it and run its installer:"
  echo "  sudo bash steam-arm-install.sh --keep"
  echo "(Update / Repair here runs the installed copy, version $cur.)"
  return 0
}
maint_update_check(){
  ui_info "Check for new version" "Asking GitHub for the newest release..."
  ui_msg "Check for new version" "$(update_check)"
}
maint_shm(){
  local before
  before=$(df -h --output=used,size /dev/shm 2>/dev/null | tail -1 | awk '{print $1 " of " $2}')
  if [ -x "$SA_LAUNCHER" ] && grep -q -- '--sweep-shm' "$SA_LAUNCHER" 2>/dev/null; then
    "$SA_LAUNCHER" --sweep-shm >/dev/null 2>&1
    ui_msg "Free /dev/shm" "Before: $before in use.
After:  $(df -h --output=used /dev/shm 2>/dev/null | tail -1 | trim) in use."
  else
    ui_msg "Free /dev/shm" "In use now: $before.

This version frees unused shared memory by itself: when Steam ARM starts and every minute while it runs. Nothing to do here."
  fi
}
# --- GE-Proton (optional third-party Proton build) ------------------------------
# Helper runs as game account; client Steam folder is its last argument.
ge_run(){ acct_run "$(game_user)" python3 "$SA_GE_PY" "$@" "$(steam_dir)"; }
# tag, folder, marked (1 = installed here), bytes (? = not measured), games; last line "slr4 installed|absent".
ge_tools(){ [ -f "$SA_GE_PY" ] && game_read python3 "$SA_GE_PY" list "$@" "$(steam_dir)" 2>/dev/null </dev/null; }
ge_gb(){ awk -v b="$1" 'BEGIN { if (b !~ /^[0-9]+$/) print "?"; else if (b >= 1e9) printf "%.1f GB\n", b / 1e9; else printf "%d MB\n", b / 1e6 + 0.5 }'; }
# Maintenance label: markers and folder names only (no tree walk).
ge_state(){
  local l n
  [ -f "$SA_GE_PY" ] || { echo "helper missing"; return; }
  l=$(ge_tools | awk -F'\t' '$1 != "slr4" && NF >= 5 { print $1 }')
  n=$(grep -c . <<<"$l")
  if [ "$n" = 0 ]; then echo none; else echo "$(head -n 1 <<<"$l")$([ "$n" -gt 1 ] && echo ", $((n - 1)) more")"; fi
}
# Folder name of newest build installed here, else newest other copy.
ge_newest(){ ge_tools | awk -F'\t' '$1 != "slr4" && NF >= 5 { if ($3 == 1 && m == "") m = $2; if (a == "") a = $2 } END { print (m != "" ? m : a) }'; }
ge_text(){
  local tag dir m b n mine="" other="" slr=unknown
  while IFS=$'\t' read -r tag dir m b n; do
    case "$tag" in '') continue;; slr4) slr=$dir; continue;; esac
    if [ "$m" = 1 ]; then mine="${mine:+$mine; }$tag ($(ge_gb "$b"), $(n_games "$n"))"; else other="${other:+$other, }$tag"; fi
  done < <(ge_tools "$@")
  echo "Installed here: ${mine:-none}"
  echo "Other copies:   ${other:-none}${other:+ (not installed here, left alone)}"
  echo "Steam Linux Runtime 4.0 (Arm64): $slr"
}
ge_check_raw(){ game_read python3 "$SA_GE_PY" check "$(steam_dir)" </dev/null; }
# Text of a check line: release TAG DATE SIZE UNPACKED FREE STATE.
ge_check_text(){
  local _r tag date size unp _f _s inst
  IFS=$'\t' read -r _r tag date size unp _f _s <<<"$1"
  inst=$(ge_tools | awk -F'\t' '$1 != "slr4" && $3 == 1 { printf "%s%s", s, $1; s = ", " }')
  echo "Newest ARM64 build: $tag ($date), download $(ge_gb "$size"), about $(ge_gb "$unp") on disk. Installed here: ${inst:-none}."
}
ge_ready(){
  local ps
  [ -f "$SA_GE_PY" ] || { ui_msg "GE-Proton (ARM64)" "Helper is missing. Run Maintenance > Update / Repair."; return 1; }
  if [ "$(client_type)" = x86 ]; then
    ui_msg "GE-Proton (ARM64)" "GE-Proton ARM64 runs with native ARM64 client only. This system runs x86 client through emulation; Windows games use x86 Proton there."; return 1
  fi
  ps=$(page_size)
  [ "$ps" = 4096 ] || { ui_msg "GE-Proton (ARM64)" "GE-Proton ARM64 needs 4K memory pages (this system: $((ps / 1024))K)."; return 1; }
  [ -d "$(steam_dir)" ] || { ui_msg "GE-Proton (ARM64)" "Start Steam ARM and sign in once, then try again."; return 1; }
}
ge_check(){
  local out
  ui_info "GE-Proton (ARM64)" "Asking GitHub for releases..."
  if out=$(ge_check_raw 2>&1); then ui_msg "GE-Proton (ARM64)" "$(ge_check_text "$out")"
  else ui_msg "GE-Proton (ARM64)" "${out//steam-arm-geproton: /}"; fi
}
# Install through progress screen; log in $SA_CACHE; result message, then move offer for older builds installed here.
ge_do(){
  local log rc tag top old n msg
  [ "$(id -u)" = 0 ] || [ "$(id -un)" = "$(game_user)" ] || need_root || return 1
  if [ -L "$SA_CACHE" ] || ! { mkdir -p "$SA_CACHE" && chmod 700 "$SA_CACHE" \
       && log=$(mktemp --suffix=.log "$SA_CACHE/geproton-$(date +%Y%m%d-%H%M%S)-XXXXXX"); }; then
    ui_msg "GE-Proton (ARM64)" "Could not create a log file in $SA_CACHE. Free some space, then try again."; return 1
  fi
  ui_run "GE-Proton (ARM64)" "$log" ge_run install "$@"; rc=$?
  if [ "$rc" != 0 ]; then
    ui_textstr "GE-Proton (ARM64): failed" "$({ echo "Install stopped (status $rc). Last lines:"; echo
      strip_ansi < "$log" | cr_last | grep -v '^[[:space:]]*$' | tail -6 | sed 's/^steam-arm-geproton: //'; echo
      echo "Full output:"; echo "$log"; } | tilde | pre_fold)"
    return 1
  fi
  if grep -q 'is installed and current' "$log"; then
    ui_msg "GE-Proton (ARM64)" "$(sed -n 's/^\(GE-Proton.* is installed and current\.\)$/\1/p' "$log" | tail -n 1)"; return 0
  fi
  read -r tag top < <(sed -n 's#^\(GE-Proton[0-9]*-[0-9]*\) installed in .*/\([^/]*\)\.$#\1 \2#p' "$log" | tail -n 1)
  msg="$tag installed. Restart Steam ARM to list it. Pick it per game: Graphics > Route per game > ge, or game Properties > Compatibility in Steam."
  grep -q 'Steam Linux Runtime 4.0 (Arm64): absent' "$log" \
    && msg+=$'\n\n'"First start of game set to it downloads Steam Linux Runtime 4.0 (Arm64)."
  old=$(ge_tools | awk -F'\t' -v t="$top" '$1 == "slr4" || NF < 5 { next } $2 == t { s = 1; next } s && $3 == 1 { print $1 "\t" $5 }')
  if [ -n "$old" ] && steam_running; then
    msg+=$'\n\n'"Close Steam ARM, then use Remove version to move games."; old=""
  fi
  ui_msg "GE-Proton (ARM64)" "$msg"
  while IFS=$'\t' read -r o n; do
    [ -n "$o" ] || continue
    ui_yesno "GE-Proton (ARM64)" "Move $(n_games "$n") from $o to $tag and remove $o?" "Move and remove" "Keep both" defaultno || continue
    ui_msg "GE-Proton (ARM64)" "$(ge_run remove "$o" --to "$tag" 2>&1 </dev/null | sed 's/^steam-arm-geproton: //')"
  done <<<"$old"
}
ge_install(){
  local out tag date size unp free state need
  ge_ready || return 1
  ui_info "GE-Proton (ARM64)" "Asking GitHub for releases..."
  out=$(ge_check_raw 2>&1) || { ui_msg "GE-Proton (ARM64)" "${out//steam-arm-geproton: /}"; return 1; }
  IFS=$'\t' read -r _ tag date size unp free state <<<"$out"
  [ "$state" = current ] && { ui_msg "GE-Proton (ARM64)" "$tag is installed and current."; return 0; }
  need=$((size * 5))
  [ "$free" -ge "$need" ] || { ui_msg "GE-Proton (ARM64)" "Needs about $(ge_gb "$need") free in $(arm_home | tilde); $(ge_gb "$free") free."; return 1; }
  ui_yesno "GE-Proton (ARM64)" "Install $tag (download $(ge_gb "$size"), about $(ge_gb "$unp") on disk) into $(steam_dir | tilde)/compatibilitytools.d?

Build by GloriousEggroll, not supported by Valve. File checked against its published sha512." Install Back defaultno || return 1
  ge_do "$tag"
}
ge_install_file(){
  local f="" b
  ge_ready || return 1
  while f=$(ui_input "GE-Proton: from file" "Path of GE-Proton<version>-aarch64.tar.gz (its .sha512sum beside it):" "${f:-$(owner_home)/Downloads/}"); do
    b=${f##*/}
    if [[ "$f" != /* ]]; then ui_msg "GE-Proton: from file" "Path must be absolute (start with /)."; continue; fi
    if [[ ! "$b" =~ ^GE-Proton[0-9]{1,3}-[0-9]{1,4}-aarch64\.tar\.gz$ ]]; then
      ui_msg "GE-Proton: from file" "File name must be GE-Proton<version>-aarch64.tar.gz, as published."; continue
    fi
    [ -f "$f" ] || { ui_msg "GE-Proton: from file" "$f is not a file."; continue; }
    if [ ! -f "${f%.tar.gz}.sha512sum" ]; then
      ui_msg "GE-Proton: from file" "Checksum file ${b%.tar.gz}.sha512sum not found beside it. Download both files from GE-Proton's release page."; continue
    fi
    ui_yesno "GE-Proton: from file" "Install ${b%-aarch64.tar.gz} from $f into $(steam_dir | tilde)/compatibilitytools.d?

Build by GloriousEggroll, not supported by Valve. File checked against .sha512sum beside it." Install Back defaultno || return 1
    ge_do --file "$f"; return
  done
}
ge_remove(){
  local l c tag dir b n other how to=default out
  l=$(ge_tools | awk -F'\t' '$1 != "slr4" && NF >= 5 && $3 == 1')
  [ -n "$l" ] || { ui_msg "GE-Proton (ARM64)" "No GE-Proton build installed by this menu. Copies installed by hand are left alone."; return 1; }
  local -a items=()
  while IFS=$'\t' read -r tag dir _ b n; do items+=("$tag" "$(printf '%-8s %s' "$(ge_gb "$b")" "$(n_games "$n")")"); done <<<"$l"
  c=$(ui_menu "GE-Proton: remove" "Remove which version? Its folder is deleted." "${items[@]}") || return 1
  close_steam "GE-Proton (ARM64)" "It holds the tool list while it runs." || return 1
  n=$(awk -F'\t' -v t="$c" '$1 == t { print $5; exit }' <<<"$l")
  if [ "${n:-0}" -gt 0 ]; then
    other=$(ge_tools | awk -F'\t' -v t="$c" '$1 != "slr4" && NF >= 5 && $1 != t { print $1; exit }')
    local -a it=(); [ -n "$other" ] && it=(other "Move them to $other")
    how=$(ui_menu "GE-Proton: remove" "$(n_games "$n") use $c:" "${it[@]}" default "Setting removed: Linux build, else Steam's default Proton") || return 1
    [ "$how" = other ] && to=$other
  fi
  [ "$(id -u)" = 0 ] || [ "$(id -un)" = "$(game_user)" ] || need_root || return 1
  out=$(ge_run remove "$c" --to "$to" 2>&1 </dev/null)
  ui_msg "GE-Proton (ARM64)" "${out//steam-arm-geproton: /}"
}
menu_geproton(){
  local c=""
  if ! is_installed; then offer_install; return; fi
  [ -f "$SA_GE_PY" ] || { ui_msg "GE-Proton (ARM64)" "Helper is missing. Run Maintenance > Update / Repair."; return; }
  while c=$(ui_menu "GE-Proton (ARM64)" "Optional Proton build by GloriousEggroll, not by Valve.
Windows games use it only when picked per game. Off until
installed here.

$(ge_text --sizes)" --default "$c" \
      check "Check for newest release (nothing downloads)" install "Install newest release..." \
      file "Install from downloaded file..." remove "Remove version..."); do
    case "$c" in
      check) ge_check;;
      install) ge_install;;
      file) ge_install_file;;
      remove) ge_remove;;
    esac
  done
}
# --- FEX code caches -----------------------------------------------------------
# Cache folders, appid<TAB>kind<TAB>path (kind linux, windows or shared; appid - for shared); $1 limits to one game.
# find -P never follows links, so a clear stays inside the library.
fex_cache_dirs(){
  local lib p id
  {
    while IFS= read -r lib; do
      [ -d "$lib/steamapps" ] || continue
      while IFS= read -r p; do
        id=${p#"$lib/steamapps/shadercache/"}; id=${id%%/*}
        valid_appid "$id" && printf '%s\tlinux\t%s\n' "$id" "$p"
      done < <(find -P "$lib/steamapps/shadercache" -mindepth 2 -maxdepth 2 -type d -name fex-emu 2>/dev/null)
      while IFS= read -r p; do
        id=${p#"$lib/steamapps/compatdata/"}; id=${id%%/*}
        valid_appid "$id" && printf '%s\twindows\t%s\n' "$id" "$p"
      done < <(find -P "$lib/steamapps/compatdata" -mindepth 8 -maxdepth 8 -type d -name fex-emu \
                 -path '*/pfx/drive_c/users/steamuser/AppData/*' 2>/dev/null)
    done < <(game_libraries)
    find -P "$(arm_home)/.cache" -mindepth 1 -maxdepth 1 -type d -name fex-emu 2>/dev/null | sed 's/^/-\tshared\t/'
  } | awk -F'\t' -v id="${1:-}" 'id == "" || $1 == id'
}
# Folder fex_cache_dirs may list: named fex-emu, no link, inside a library's shadercache or compatdata, or the shared one.
cache_path_ok(){
  local p=$1 lib
  case "$p" in */fex-emu) ;; *) return 1;; esac
  [ -d "$p" ] && [ ! -L "$p" ] || return 1
  [ "$p" = "$(arm_home)/.cache/fex-emu" ] && return 0
  while IFS= read -r lib; do
    case "$p" in "$lib"/steamapps/shadercache/*/fex-emu|"$lib"/steamapps/compatdata/*/fex-emu) return 0;; esac
  done < <(game_libraries)
  return 1
}
# Game account's library readable here (other accounts often have no access: sizes would read 0).
cache_readable(){ [ "$(id -u)" = 0 ] || [ "$(id -un)" = "$(game_user)" ] || { [ -r "$(steam_dir)/steamapps" ] && [ -x "$(steam_dir)/steamapps" ]; }; }
# appid<TAB>kind<TAB>KB<TAB>path per cache folder.
cache_scan(){
  local id kind p k
  while IFS=$'\t' read -r id kind p; do
    k=$(du -sk -- "$p" 2>/dev/null | cut -f1)
    printf '%s\t%s\t%s\t%s\n' "$id" "$kind" "${k:-0}" "$p"
  done < <(fex_cache_dirs "$@")
}
# "1 game", "2 games"
n_games(){ if [ "$1" = 1 ]; then echo "1 game"; else echo "$1 games"; fi; }
kb_h(){ awk -v k="${1:-0}" 'BEGIN { if (k == 0) print "0"; else if (k < 1024) printf "%dK\n", k; else if (k < 1048576) printf "%.1fM\n", k / 1024; else printf "%.1fG\n", k / 1048576 }'; }
# Games whose effective profile has diskcache=on.
dc_on_count(){
  local f
  while IFS= read -r f; do cat "$f" 2>/dev/null; echo; done < <(titles_files) \
    | awk '{ sub(/#.*/, ""); for (i = 2; i <= NF; i++) if ($i ~ /^diskcache=/) v[$1] = substr($i, 11) }
           END { n = 0; for (k in v) if (v[k] == "on") n++; print n }'
}
# Size of steamapps/shadercache of every library, in KB.
shader_kb(){
  local lib t=0 k
  while IFS= read -r lib; do
    [ -d "$lib/steamapps/shadercache" ] || continue
    k=$(du -sk "$lib/steamapps/shadercache" 2>/dev/null | cut -f1); t=$((t + ${k:-0}))
  done < <(game_libraries)
  echo "$t"
}
# Summary lines from cache_scan output $1.
cache_summary(){
  local lk ln wk wn sk n
  read -r lk ln wk wn sk <<<"$(awk -F'\t' '$2 == "linux" { l += $3; ln++ } $2 == "windows" { w += $3; wn++ } $2 == "shared" { s += $3 }
                               END { print l + 0, ln + 0, w + 0, wn + 0, s + 0 }' <<<"$1")"
  n=$(( $(shader_kb) - lk )); [ "$n" -ge 0 ] || n=0
  printf '%-29s %-6s %s\n' "FEX code cache, Linux games" "$(kb_h "$lk")" "$(n_games "$ln")"
  printf '%-29s %-6s %s (Proton prefixes)\n' "FEX code cache, Windows games" "$(kb_h "$wk")" "$(n_games "$wn")"
  printf '%-29s %s\n' "FEX code cache, shared folder" "$(kb_h "$sk")"
  printf '%-29s %-6s %s\n' "Steam shader cache" "$(kb_h "$n")" "Steam's own, not cleared here"
  echo "Code cache on (diskcache=on): $(n_games "$(dc_on_count)"). FEX tool: $(fex_tool_ver)."
}
# Per-folder list, largest first, with game names.
cache_list(){
  [ -n "$1" ] || { echo "No FEX code caches found."; return 0; }
  echo "Per game, largest first:"
  sort -t$'\t' -k3,3nr <<<"$1" | while IFS=$'\t' read -r id kind k p; do
    if [ "$kind" = shared ]; then printf '  %-7s %-8s %s\n' "$(kb_h "$k")" shared "$p"
    else printf '  %-7s %-8s %-8s %s\n' "$(kb_h "$k")" "$kind" "$id" "$(game_name "$id" | cut -c1-40)"; fi
  done | tilde
}
cache_text(){
  local scan; scan=$(cache_scan)
  cache_summary "$scan"; echo; cache_list "$scan"
}
# Delete FEX code cache folders of all games or one ($1); refused while a game runs. Steam's own caches stay.
cache_clear(){
  local id kind k p kb=0 n=0 bad=0 scan
  if game_running; then
    echo "steam-arm-config: a game is running in Steam ARM; FEX writes its cache while games run. Quit the game, then try again." >&2
    return 1
  fi
  scan=$(cache_scan "$([ "$1" = all ] || echo "$1")")
  [ -n "$scan" ] || { echo "No FEX code caches found."; return 0; }
  while IFS=$'\t' read -r id kind k p; do
    cache_path_ok "$p" || { echo "steam-arm-config: skipped (not a cache folder): $p" >&2; bad=1; continue; }
    if acct_run "$(game_user)" rm -rf -- "$p"; then kb=$((kb + k)); n=$((n + 1)); else bad=1; fi
  done <<<"$scan"
  echo "Freed $(kb_h "$kb"). Folders deleted: $n. Steam shader caches stay."
  [ "$bad" = 0 ]
}
# Cache commands run in this process for root and the game account; others through sudo (client folder may be private).
cache_run(){
  if [ "$(id -u)" = 0 ] || [ "$(id -un)" = "$(game_user)" ]; then cli_cache "$@"
  else need_root || return 1; as_root bash "$(self_path)" cache "$@"; fi
}
cache_ask(){
  local what=$1 label=$2 size=$3 out
  ui_yesno "Caches" "Delete FEX code caches of $label ($size)? Games translate code again at their next start. Steam shader caches stay." Delete Back defaultno || return 1
  if game_running; then
    ui_msg "Caches" "A game is running in Steam ARM. FEX writes its cache while games run.

Quit the game, then try again."
    return 1
  fi
  out=$(cache_run clear "$what" 2>&1)
  ui_msg "Caches" "$out"
}
cache_pick(){
  local c id k
  local -a items=()
  while IFS=$'\t' read -r id k; do
    items+=("$id" "$(printf '%-7s %s' "$(kb_h "$k")" "$(game_name "$id" | cut -c1-40)")")
  done < <(awk -F'\t' 'NF >= 4 && $1 != "-" { s[$1] += $3 } END { for (i in s) printf "%s\t%s\n", i, s[i] }' <<<"$1" | sort -t$'\t' -k2,2nr)
  [ "${#items[@]}" -gt 0 ] || { ui_msg "Caches" "No FEX code caches of games found."; return 1; }
  c=$(ui_menu "Caches: one game" "FEX code cache of which game?" "${items[@]}") || return 1
  k=$(awk -F'\t' -v id="$c" '$1 == id { s += $3 } END { print s + 0 }' <<<"$1")
  cache_ask "$c" "$(game_name "$c" | cut -c1-40)" "$(kb_h "$k")"
}
menu_caches(){
  local c="" scan
  if ! is_installed; then offer_install; return; fi
  while :; do
    ui_info "Caches" "Measuring cache folders..."
    scan=$(cache_run list) || return
    c=$(ui_menu "Caches" "$(cache_summary "$scan")" --default "$c" \
        list "Sizes per game" all "Clear FEX code caches of all games" game "Clear FEX code cache of one game...") || return
    case "$c" in
      list) ui_textstr "Caches" "$(cache_list "$scan")";;
      all)  if [ -z "$scan" ]; then ui_msg "Caches" "No FEX code caches found."
            else cache_ask all "all games" "$(kb_h "$(awk -F'\t' '{ s += $3 } END { print s + 0 }' <<<"$scan")")"; fi;;
      game) cache_pick "$scan";;
    esac
  done
}
# --- Settings backup and restore ---------------------------------------------
# Archive steam-arm-settings-<date>-<time>.tar.gz, members under steam-arm-settings/: manifest (FORMAT, VERSION,
# DATE, GPU_FAMILY, PARTS), system/steam-arm.conf, system/titles.conf, personal/titles.conf,
# personal/compattools.txt ("appid tool"), personal/fex-appconfig/*.json, personal/mangohud/*.conf.
# Personal parts carry no account name; restore puts them into any chosen account. Accounts are never changed.
SA_BK_FMT=1
SA_BK_TOP=steam-arm-settings
SA_BK_MAX=1048576
SA_BK_TOTAL=8388608
SA_BK_FILES=400
SA_BK_PARTS="setup system-profiles personal-profiles compat-tools fex mangohud"
SA_BK_PERSONAL="personal-profiles compat-tools fex mangohud"
# steam-arm.conf keys restored; every other key is machine state (GPU_FAMILY only when GPU_FAMILY_SET=user).
SA_BK_KEYS="COMPONENTS_ON COMPONENTS_OFF COMPONENTS_USER_SET GFX_DEFAULT AUTO_BUILD CPU_NOTICE"
SA_BK_NAME='[A-Za-z0-9_+-][A-Za-z0-9._+-]*'
part_label(){ case "$1" in
  setup) echo "Setup choices";; system-profiles) echo "System game profiles";;
  personal-profiles) echo "Personal game profiles";; compat-tools) echo "Proton/tool per game";;
  fex) echo "FEX per-game settings";; mangohud) echo "MangoHud settings";; *) echo "$1";;
esac; }
in_list(){ case ",$1," in *",$2,"*) return 0;; esac; return 1; }
any_personal(){ local p; for p in $SA_BK_PERSONAL; do in_list "$1" "$p" && return 0; done; return 1; }
drop_personal(){ local p o=""; for p in ${1//,/ }; do case " $SA_BK_PERSONAL " in *" $p "*) ;; *) o="$o${o:+,}$p";; esac; done; echo "$o"; }
parts_ok(){
  local p
  [ -n "$1" ] || return 1
  for p in ${1//,/ }; do case " $SA_BK_PARTS " in *" $p "*) ;; *) echo "steam-arm-config: unknown part: $p (parts: ${SA_BK_PARTS// /,})" >&2; return 1;; esac; done
}
# Person who asked: the sudo caller when run through sudo.
owner_user(){
  if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then echo "$SUDO_USER"; else id -un; fi
}
owner_home(){ getent passwd "$(owner_user)" 2>/dev/null | cut -d: -f6; }
as_owner(){ if [ "$(id -u)" = 0 ] && [ "$(owner_user)" != root ]; then runuser -u "$(owner_user)" -- "$@"; else "$@"; fi; }
acct_home(){ getent passwd "$1" 2>/dev/null | cut -d: -f6; }
# Run as account $1: directly when it is this one, root through runuser, others through sudo.
acct_run(){
  local u=$1; shift
  if [ "$(id -un)" = "$u" ]; then "$@"
  elif [ "$(id -u)" = 0 ]; then runuser -u "$u" -- "$@"
  else as_root runuser -u "$u" -- "$@"; fi
}
# acct_put ACCOUNT FILE < data: atomic write as that account; a current file is kept as FILE.bak-restore.
acct_put(){
  # shellcheck disable=SC2016
  acct_run "$1" sh -c 'umask 022; mkdir -p "${1%/*}" || exit 1
    [ ! -f "$1" ] || cp -p "$1" "$1.bak-restore" || exit 1
    t=$(mktemp "$1.XXXXXX") || exit 1
    if cat > "$t" && chmod 644 "$t" && mv -f "$t" "$1"; then exit 0; fi
    rm -f "$t"; exit 1' sh "$2"
}
acct_same(){ acct_run "$1" cmp -s - "$2" 2>/dev/null; }
# Personal part location in the client folder of account $1 (where games read it).
bk_path(){
  local c; c="$(acct_home "$1")/$(armhome_rel)"
  case "$2" in
    personal-profiles) echo "$c/.config/steam-arm/titles.conf";;
    compat-tools) echo "$c/.local/share/Steam/config/config.vdf";;
    fex) echo "$c/.fex-emu/AppConfig";;
    mangohud) echo "$c/.config/MangoHud";;
  esac
}
# CompatToolMapping of a config.vdf on stdin: "appid tool" lines.
compat_py(){ cat <<'PY'
import re, sys
s = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
m = re.search(r'\n(\t+)"CompatToolMapping"\n\1\{\n', s)
if m:
    e = s.find("\n" + m.group(1) + "}", m.end() - 1)
    for a in re.finditer(r'^\t+"([0-9]{1,10})"\n\t+\{\n((?:.*\n)*?)\t+\}\n', s[m.end():e + 1], re.M):
        n = re.search(r'^\t+"name"\t+"([^"]*)"', a.group(2), re.M)
        if n and re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", n.group(1)):
            print(a.group(1), n.group(1))
PY
}
# CompatToolMapping of the client as "appid tool" lines; forced build of one game; its label.
compat_map(){ { python3 -c "$(compat_py)" < "$(steam_dir)/config/config.vdf"; } 2>/dev/null; }
compat_tool(){ compat_map | awk -v id="$1" '$1 == id { print $2; exit }'; }
compat_label(){ case "$1" in [Pp]roton*) echo "Windows build (Proton)";; GE-Proton*) echo "Windows build (${1%-aarch64})";; *[Pp]roton*) echo "Windows build (${1:0:20})";; ?*) echo "Linux build";; esac; }
json_ok(){ python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$1" >/dev/null 2>&1; }
text_ok(){ [ "$(tr -d '\000' < "$1" | wc -c)" = "$(wc -c < "$1")" ]; }
# Valve tools (the client fetches them); other tools need a compatibilitytools.d entry.
tool_ok(){
  local d
  case "$2" in proton_*|proton-*-arm64|steamlinuxruntime*) return 0;; esac
  for d in "$(acct_home "$1")/$(armhome_rel)/.local/share/Steam/compatibilitytools.d" \
           /usr/share/steam/compatibilitytools.d /usr/local/share/steam/compatibilitytools.d; do
    acct_run "$1" grep -rqsF --include=compatibilitytool.vdf "\"$2\"" "$d" && return 0
  done
  return 1
}
bk_expand(){
  local d=$1
  case "$d" in \~) d=$(owner_home);; \~/*) d="$(owner_home)/${d:2}";; esac
  [ "$d" = / ] || d=${d%/}
  echo "$d"
}
bk_last_file(){ echo "$(owner_home)/.cache/steam-arm/last-backup-dir"; }
bk_last_dir(){ local d; d=$(head -1 "$(bk_last_file)" 2>/dev/null); [ -n "$d" ] && [ -d "$d" ] && echo "$d"; return 0; }
bk_last_set(){
  # shellcheck disable=SC2016
  as_owner sh -c 'mkdir -p "${1%/*}" && printf "%s\n" "$2" > "$1"' sh "$(bk_last_file)" "$1" 2>/dev/null || true
}
# Status 2: folder missing; 1: not writable for the owner.
bk_dir_ok(){
  as_owner test -d "$1" || return 2
  as_owner test -w "$1" && as_owner test -x "$1" || return 1
}
bk_note(){ BK_NOTE="$BK_NOTE$(part_label "$1"): $2"$'\n'; }
# Valid *.json (fex) or *.conf (mangohud) of account $1 into $3; member names added to BK_MEM.
bk_files(){
  local acct=$1 part=$2 out=$3 src ext sub n sz bad="" k=0
  src=$(bk_path "$acct" "$part")
  case "$part" in fex) ext=json; sub=fex-appconfig;; *) ext=conf; sub=mangohud;; esac
  while IFS=$'\t' read -r n sz; do
    [ -n "$n" ] || continue
    if [[ ! "$n" =~ ^${SA_BK_NAME}\.${ext}$ ]] || [ "$sz" -gt "$SA_BK_MAX" ]; then bad="$bad $n"; continue; fi
    acct_run "$acct" cat "$src/$n" > "$out/$sub/$n" 2>/dev/null || { rm -f "$out/$sub/$n"; bad="$bad $n"; continue; }
    if { [ "$ext" = json ] && ! json_ok "$out/$sub/$n"; } || ! text_ok "$out/$sub/$n"; then
      rm -f "$out/$sub/$n"; bad="$bad $n"; continue
    fi
    BK_MEM+=("personal/$sub/$n"); k=$((k + 1))
  done < <(acct_run "$acct" find "$src" -mindepth 1 -maxdepth 1 -type f -name "*.$ext" -printf '%f\t%s\n' 2>/dev/null | sort)
  BK_BAD=$bad; [ -n "$bad" ] && bk_note "$part" "left out (name, size or content not valid):$bad"
  [ "$k" -gt 0 ]
}
# bk_make DIR PARTS ACCOUNT: archive written as the person who asked (mode 600). Sets BK_PATH, BK_NOTE, BK_ERR.
bk_make(){
  local dir parts=$2 acct=$3 s m rc fam got="" name p
  local -a list=()
  BK_PATH="" BK_NOTE="" BK_ERR="" BK_MEM=()
  dir=$(bk_expand "$1"); case "$dir" in /*) ;; *) dir="$PWD/$dir";; esac
  bk_dir_ok "$dir"; rc=$?
  [ "$rc" = 2 ] && { BK_ERR="Folder $dir does not exist."; return 1; }
  [ "$rc" = 1 ] && { BK_ERR="$(owner_user) cannot write to $dir."; return 1; }
  s=$(tmpf -d) || { BK_ERR=$TMP_FAIL; return 1; }
  m="$s/$SA_BK_TOP"; mkdir -p "$m/system" "$m/personal/fex-appconfig" "$m/personal/mangohud"
  if in_list "$parts" setup; then
    if [ -r "$SA_CONF" ] && cp "$SA_CONF" "$m/system/steam-arm.conf"; then BK_MEM+=(system/steam-arm.conf); got+=,setup
    else bk_note setup "no settings file, left out"; fi
  fi
  if in_list "$parts" system-profiles; then
    if [ -f "$SA_TITLES_ETC" ] && cp "$SA_TITLES_ETC" "$m/system/titles.conf"; then BK_MEM+=(system/titles.conf); got+=,system-profiles
    else bk_note system-profiles "none yet, left out"; fi
  fi
  if any_personal "$parts" && [ -z "$acct" ]; then
    for p in $SA_BK_PERSONAL; do in_list "$parts" "$p" && bk_note "$p" "no account, left out"; done
  elif any_personal "$parts"; then
    if in_list "$parts" personal-profiles; then
      if acct_run "$acct" cat "$(bk_path "$acct" personal-profiles)" > "$m/personal/titles.conf" 2>/dev/null; then
        BK_MEM+=(personal/titles.conf); got+=,personal-profiles
      else rm -f "$m/personal/titles.conf"; bk_note personal-profiles "none yet, left out"; fi
    fi
    if in_list "$parts" compat-tools; then
      if ! have python3; then bk_note compat-tools "python3 not found, left out"
      elif acct_run "$acct" cat "$(bk_path "$acct" compat-tools)" 2>/dev/null | python3 -c "$(compat_py)" > "$m/personal/compattools.txt" 2>/dev/null \
           && [ -s "$m/personal/compattools.txt" ]; then BK_MEM+=(personal/compattools.txt); got+=,compat-tools
      else rm -f "$m/personal/compattools.txt"; bk_note compat-tools "none set, left out"; fi
    fi
    for p in fex mangohud; do
      in_list "$parts" "$p" || continue
      if [ "$p" = fex ] && ! have python3; then bk_note fex "python3 not found, left out"; continue; fi
      if bk_files "$acct" "$p" "$m/personal"; then got+=",$p"; elif [ -z "$BK_BAD" ]; then bk_note "$p" "none found, left out"; fi
    done
  fi
  if [ ${#BK_MEM[@]} -eq 0 ]; then rm -rf "$s"; BK_ERR="Nothing to back up in the chosen parts."; return 1; fi
  fam=$(conf_get GPU_FAMILY); [ -n "$fam" ] || fam=$(gpu_family)
  printf 'FORMAT=%s\nVERSION=%s\nDATE=%s\nGPU_FAMILY=%s\nPARTS=%s\n' "$SA_BK_FMT" "$(installed_version)" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$fam" "${got#,}" > "$m/manifest"
  list=("$SA_BK_TOP/manifest"); for p in "${BK_MEM[@]}"; do list+=("$SA_BK_TOP/$p"); done
  name="steam-arm-settings-$(date +%Y%m%d-%H%M%S).tar.gz"
  if [ -e "$dir/$name" ]; then rm -rf "$s"; BK_ERR="$dir/$name already exists; try again."; return 1; fi
  # no account or host names inside: numeric owner 0
  if ! tar --owner=0 --group=0 --numeric-owner --mode=u=rw,go=r -C "$s" -czf "$s/out.tar.gz" "${list[@]}" 2>/dev/null; then
    rm -rf "$s"; BK_ERR="Could not pack the backup."; return 1
  fi
  # shellcheck disable=SC2016
  as_owner sh -c 'umask 077; t=$(mktemp "$2/.steam-arm-settings.XXXXXX") || exit 1
    if cat > "$t" && { ln "$t" "$1" 2>/dev/null || { [ ! -e "$1" ] && mv "$t" "$1"; }; }; then rm -f "$t"; exit 0; fi
    rm -f "$t"; exit 1' sh "$dir/$name" "$dir" < "$s/out.tar.gz"; rc=$?
  rm -rf "$s"
  [ "$rc" = 0 ] || { BK_ERR="Could not write $dir/$name."; return 1; }
  BK_PATH="$dir/$name"
}
rs_val(){ sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1 | sed "s/^[\"']//; s/[\"']\$//"; }
rs_norm(){ tr ',' '\n' | grep -v '^$' | sort -u | paste -sd, -; }
rs_valid(){ case "$1" in
  GFX_DEFAULT) case "$2" in auto|a|b|forward) return 0;; esac; return 1;;
  AUTO_BUILD|CPU_NOTICE) case "$2" in on|off|"") return 0;; esac; return 1;;
  GPU_FAMILY) [[ "$2" =~ ^[a-z0-9-]+$ ]];;
  *) [[ "$2" =~ ^[a-z0-9,-]*$ ]];;
esac; }
rs_close(){ [ -n "${RS_D:-}" ] && rm -rf "$RS_D"; RS_D=""; }
# rs_open FILE: archive checked, unpacked to RS_D; parts held in RS_PARTS, left-out files in RS_NOTE. Error in RS_ERR.
rs_open(){
  local f=$1 names list typ n name fmt p re total=0 count=0 g
  local -a files=()
  RS_D="" RS_ERR="" RS_NOTE="" RS_PARTS=""
  [ -f "$f" ] && [ -r "$f" ] || { RS_ERR="Cannot read $f."; return 1; }
  [ "$(stat -c %s -- "$f" 2>/dev/null || echo 0)" -le "$SA_BK_MAX" ] || { RS_ERR="$f is too large for a settings backup."; return 1; }
  if ! names=$(LC_ALL=C tar --quoting-style=escape -tzf "$f" 2>/dev/null) \
     || ! list=$(LC_ALL=C tar --quoting-style=escape --numeric-owner -tvzf "$f" 2>/dev/null); then
    RS_ERR="$f is not a readable .tar.gz archive."; return 1
  fi
  [ -z "$(sort <<<"$names" | uniq -d)" ] || { RS_ERR="Refused: a member appears twice."; return 1; }
  # names every format may hold; the manifest's format narrows them below
  re="^$SA_BK_TOP/(manifest|system/steam-arm\\.conf|system/titles\\.conf|personal/titles\\.conf|personal/compattools\\.txt|personal/fex-appconfig/${SA_BK_NAME}\\.json|personal/mangohud/${SA_BK_NAME}\\.conf)\$"
  while read -r typ _ n _ _ name; do
    [ -n "$typ" ] || continue
    case "$name" in "$SA_BK_TOP/"|"$SA_BK_TOP/system/"|"$SA_BK_TOP/personal/"|"$SA_BK_TOP/personal/fex-appconfig/"|"$SA_BK_TOP/personal/mangohud/")
      [ "${typ:0:1}" = d ] && continue;; esac
    [ "${typ:0:1}" = - ] || { RS_ERR="Refused: link or special file in the archive ($name)."; return 1; }
    [[ "$name" =~ $re ]] || { RS_ERR="Refused: unexpected member $name."; return 1; }
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -le "$SA_BK_MAX" ] || { RS_ERR="Refused: $name is too large."; return 1; }
    total=$((total + n)); count=$((count + 1)); files+=("$name")
  done <<<"$list"
  [ "$total" -le "$SA_BK_TOTAL" ] && [ "$count" -le "$SA_BK_FILES" ] || { RS_ERR="Refused: archive holds too much."; return 1; }
  grep -qx "$SA_BK_TOP/manifest" <<<"$names" || { RS_ERR="Refused: no manifest, so not a Steam ARM settings backup."; return 1; }
  RS_D=$(tmpf -d) || { RS_ERR=$TMP_FAIL; return 1; }
  tar -xzf "$f" -C "$RS_D" --no-same-owner --no-same-permissions -- "$SA_BK_TOP/manifest" 2>/dev/null \
    || { RS_ERR="Could not unpack $f."; rs_close; return 1; }
  fmt=$(rs_val "$RS_D/$SA_BK_TOP/manifest" FORMAT)
  # one entry per format ever written; older formats stay readable
  case "$fmt" in
    1) ;;
    '') RS_ERR="Refused: manifest has no format version."; rs_close; return 1;;
    *) RS_ERR="Refused: backup format $fmt is newer than this version reads (up to $SA_BK_FMT). Update Steam ARM, then try again."
       rs_close; return 1;;
  esac
  tar -xzf "$f" -C "$RS_D" --no-same-owner --no-same-permissions -- "${files[@]}" 2>/dev/null \
    || { RS_ERR="Could not unpack $f."; rs_close; return 1; }
  if [ -n "$(find "$RS_D" -mindepth 1 ! -type f ! -type d -print -quit)" ]; then
    RS_ERR="Refused: unexpected file type after unpacking."; rs_close; return 1
  fi
  g="$RS_D/$SA_BK_TOP"
  for n in "$g"/personal/fex-appconfig/*.json "$g"/personal/mangohud/*.conf; do
    [ -f "$n" ] || continue
    if { [[ "$n" == *.json ]] && ! json_ok "$n"; } || ! text_ok "$n"; then
      RS_NOTE="$RS_NOTE ${n##*/}"; rm -f "$n"
    fi
  done
  for p in $SA_BK_PARTS; do
    in_list "$(rs_val "$g/manifest" PARTS)" "$p" || continue
    case "$p" in
      setup) [ -f "$g/system/steam-arm.conf" ];;
      system-profiles) [ -f "$g/system/titles.conf" ];;
      personal-profiles) [ -f "$g/personal/titles.conf" ];;
      compat-tools) [ -f "$g/personal/compattools.txt" ];;
      fex) compgen -G "$g/personal/fex-appconfig/*.json" >/dev/null;;
      mangohud) compgen -G "$g/personal/mangohud/*.conf" >/dev/null;;
    esac && RS_PARTS="$RS_PARTS${RS_PARTS:+,}$p"
  done
  [ -n "$RS_PARTS" ] || { RS_ERR="Refused: the backup holds no usable part."; rs_close; return 1; }
}
# Titles files: "1 line" rows of the current file, then "2 line" rows of the backup.
tc_rows(){ { sed 's/^/1 /' "$1" 2>/dev/null; sed 's/^/2 /' "$2"; }; }
# shellcheck disable=SC2016
TC_AWK='{ f = substr($0, 1, 1); l = substr($0, 3); d = l; sub(/#.*/, "", d); split(d, w, /[ \t]+/); id = w[w[1] == "" ? 2 : 1]; game = (id ~ /^[0-9]+$/) }'
# Games in the backup with other lines than here (MODE=conf) or not here at all (MODE=new); comma list.
tc_ids(){
  tc_rows "$2" "$3" | awk -v MODE="$1" "$TC_AWK"'
    !game { next }
    { L[f, id] = L[f, id] l "\n"; if (f == 1) A[id] = 1; else if (!(id in B)) { B[id] = 1; o[++k] = id } }
    END { for (i = 1; i <= k; i++) { id = o[i]
      if (MODE == "conf" && (id in A) && L[1, id] != L[2, id]) print id
      if (MODE == "new" && !(id in A)) print id } }' | paste -sd, -
}
# Current file plus backup lines of new games; games in TAKE get the backup's lines.
tc_merge(){
  tc_rows "$1" "$2" | awk -v take=",$3," "$TC_AWK"'
    f == 1 { if (game) { A[id] = 1; if (index(take, "," id ",")) next }; print l; next }
    game && (!(id in A) || index(take, "," id ",")) { print l }'
}
tc_lines(){ awk -v id="$2" '{ d = $0; sub(/#.*/, "", d); split(d, w, /[ \t]+/); if (w[w[1] == "" ? 2 : 1] == id) print }' "$1" 2>/dev/null; }
# rs_titles CUR BAK MODE TAKE OUT: OUT gets the new content; TP_TXT says what changes. Status 1: no change.
rs_titles(){
  local cur=$1 bak=$2 take=$4 out=$5 new conf won="" kept="" id
  if [ ! -f "$cur" ]; then cp "$bak" "$out"; TP_TXT="no file yet: taken from the backup"; return 0; fi
  if cmp -s "$cur" "$bak"; then TP_TXT="unchanged"; return 1; fi
  if [ "$3" = replace ]; then cp "$bak" "$out"; TP_TXT="replaced by the backup (current one kept as titles.conf.bak-restore)"; return 0; fi
  new=$(tc_ids new "$cur" "$bak"); conf=$(tc_ids conf "$cur" "$bak")
  for id in ${conf//,/ }; do
    if [ "$take" = all ] || in_list "$take" "$id"; then won="$won${won:+,}$id"; else kept="$kept${kept:+,}$id"; fi
  done
  tc_merge "$cur" "$bak" "$won" > "$out"
  TP_TXT="merge: adds ${new:-no games}; backup wins for ${won:-none}; current kept for ${kept:-none}"
  if cmp -s "$cur" "$out"; then TP_TXT="merge: nothing to add; current kept for ${kept:-none}"; return 1; fi
  TP_TXT="$TP_TXT (current file kept as titles.conf.bak-restore)"
}
# Copy of the account's current personal titles.conf in RS_D (absent when it has none).
rs_cur_personal(){
  local o="$RS_D/out/cur-personal.conf"
  mkdir -p "$RS_D/out"; rm -f "$o"
  acct_run "$1" cat "$(bk_path "$1" personal-profiles)" > "$o" 2>/dev/null || rm -f "$o"
  echo "$o"
}
rs_line(){ printf '  %-20s %s\n' "$1" "$2"; }
# rs_plan PARTS ACCOUNT SYS-MODE PERSONAL-MODE SYS-TAKE PERSONAL-TAKE: what restore changes, text in RS_SUM.
rs_plan(){
  local parts=$1 acct=$2 c="$RS_D/$SA_BK_TOP" s k v cur keys skip="" fam_user=0 a r p sub dest add rep same n src
  local vdf curmap bad="" miss="" shown=0 kept=0
  RS_SET=(); RS_MAP=(); RS_COPY=(); RS_COMP=0; RS_SYS_OUT=""; RS_PERS_OUT=""; RS_ACCT=$acct
  mkdir -p "$RS_D/out"
  s="Backup of $(rs_val "$c/manifest" DATE), Steam ARM $(rs_val "$c/manifest" VERSION), GPU $(rs_val "$c/manifest" GPU_FAMILY)."$'\n'
  any_personal "$parts" && s+="Personal parts go to account $acct; accounts themselves are not changed."$'\n'
  if in_list "$parts" setup; then
    s+=$'\n'"Setup choices"$'\n'
    keys=$SA_BK_KEYS
    [ "$(rs_val "$c/system/steam-arm.conf" GPU_FAMILY_SET)" = user ] && grep -q '^GPU_FAMILY=' "$c/system/steam-arm.conf" \
      && { keys="$keys GPU_FAMILY"; fam_user=1; }
    for k in $keys; do
      grep -q "^$k=" "$c/system/steam-arm.conf" || continue
      v=$(rs_val "$c/system/steam-arm.conf" "$k"); cur=$(conf_get "$k")
      if ! rs_valid "$k" "$v"; then s+=$(rs_line "$k" "value not valid, kept as is")$'\n'; [ "$k" = GPU_FAMILY ] && fam_user=0; continue; fi
      case "$k" in
        COMPONENTS_*)
          if [ "$(rs_norm <<<"$cur")" = "$(rs_norm <<<"$v")" ]; then s+=$(rs_line "$k" unchanged)$'\n'; continue; fi
          a=$(comm -13 <(tr ',' '\n' <<<"$cur" | grep -v '^$' | sort -u) <(tr ',' '\n' <<<"$v" | grep -v '^$' | sort -u) | paste -sd, - | sed 's/,/, /g')
          r=$(comm -23 <(tr ',' '\n' <<<"$cur" | grep -v '^$' | sort -u) <(tr ',' '\n' <<<"$v" | grep -v '^$' | sort -u) | paste -sd, - | sed 's/,/, /g')
          s+=$(rs_line "$k" "${a:+adds $a}${a:+${r:+; }}${r:+drops $r}")$'\n'
          case "$k" in COMPONENTS_ON|COMPONENTS_OFF) RS_COMP=1;; esac;;
        *)
          if [ "$cur" = "$v" ]; then s+=$(rs_line "$k" unchanged)$'\n'; continue; fi
          s+=$(rs_line "$k" "${cur:-(empty)} -> ${v:-(empty)}")$'\n';;
      esac
      RS_SET+=("$k=$v")
    done
    if [ "$fam_user" = 1 ] && [ "$(conf_get GPU_FAMILY_SET)" != user ]; then
      RS_SET+=("GPU_FAMILY_SET=user"); s+=$(rs_line GPU_FAMILY_SET "$(conf_get GPU_FAMILY_SET) -> user")$'\n'
    fi
    while read -r k; do
      case " $keys " in *" $k "*) continue;; esac
      [ "$k" = GPU_FAMILY_SET ] && [ "$fam_user" = 1 ] && continue
      skip="$skip${skip:+, }$k"
    done < <(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$c/system/steam-arm.conf" | sort -u)
    [ -n "$skip" ] && s+="  Not restored (state of this machine):"$'\n'"$(echo "$skip" | fold -s -w 62 | sed 's/^/    /')"$'\n'
    [ "$RS_COMP" = 1 ] && s+="  Part lists change: setup --keep makes the installed parts match."$'\n'
  fi
  if in_list "$parts" system-profiles; then
    rs_titles "$SA_TITLES_ETC" "$c/system/titles.conf" "$3" "$5" "$RS_D/out/system-titles.conf" && RS_SYS_OUT="$RS_D/out/system-titles.conf"
    s+=$'\n'"System game profiles ($SA_TITLES_ETC)"$'\n'"$(echo "$TP_TXT" | fold -s -w 66 | sed 's/^/  /')"$'\n'
  fi
  if in_list "$parts" personal-profiles; then
    rs_titles "$(rs_cur_personal "$acct")" "$c/personal/titles.conf" "$4" "$6" "$RS_D/out/personal-titles.conf" \
      && RS_PERS_OUT="$RS_D/out/personal-titles.conf"
    s+=$'\n'"Personal game profiles (account $acct)"$'\n'"$(echo "$TP_TXT" | fold -s -w 66 | sed 's/^/  /')"$'\n'
  fi
  if in_list "$parts" compat-tools; then
    s+=$'\n'"Proton/tool per game (account $acct)"$'\n'
    vdf=$(bk_path "$acct" compat-tools); same=0
    if ! have python3 || [ ! -f "$SA_COMPATMAP_PY" ]; then s+="  compat helper not found (run Update / Repair): left out"$'\n'
    elif ! acct_run "$acct" test -f "$vdf"; then s+="  no client settings for $acct yet (start Steam ARM and sign in once): left out"$'\n'
    else
      curmap=$(acct_run "$acct" cat "$vdf" 2>/dev/null | python3 -c "$(compat_py)" 2>/dev/null)
      while read -r a v _; do
        [ -n "$a" ] || continue
        if ! valid_appid "$a" || [[ ! "$v" =~ ^[A-Za-z0-9_.-]{1,64}$ ]]; then bad="$bad $a"; continue; fi
        if grep -qxF "$a $v" <<<"$curmap"; then same=$((same + 1)); continue; fi
        # tool chosen now for this game stays: explicit choice wins over the backup
        if grep -q "^$a " <<<"$curmap"; then kept=$((kept + 1)); continue; fi
        if ! tool_ok "$acct" "$v"; then miss="$miss $a:$v"; continue; fi
        RS_MAP+=("$a $v")
        [ "$shown" -lt 8 ] && s+=$(rs_line "app $a" "-> $v")$'\n'; shown=$((shown + 1))
      done < "$c/personal/compattools.txt"
      [ "$shown" -gt 8 ] && s+="  ... $((shown - 8)) more"$'\n'
      s+="  ${#RS_MAP[@]} to set, $same unchanged, $kept kept (other tool chosen here)"$'\n'
      [ -n "$miss" ] && s+="  Tool not installed, left out:"$'\n'"$(echo "${miss# }" | fold -s -w 62 | sed 's/^/    /')"$'\n'
      grep -qE ':GE-Proton[0-9]+-[0-9]+-aarch64( |$)' <<<"$miss" \
        && s+="  GE-Proton builds: install from Maintenance > GE-Proton (ARM64), then restore again."$'\n'
      [ -n "$bad" ] && s+="  Not valid, left out:$bad"$'\n'
    fi
  fi
  for p in fex mangohud; do
    in_list "$parts" "$p" || continue
    case "$p" in fex) sub=fex-appconfig;; *) sub=mangohud;; esac
    dest=$(bk_path "$acct" "$p"); add=0 rep=0 same=0
    for src in "$c/personal/$sub"/*; do
      [ -f "$src" ] || continue
      n=${src##*/}
      if acct_same "$acct" "$dest/$n" < "$src"; then same=$((same + 1)); continue; fi
      if acct_run "$acct" test -f "$dest/$n"; then rep=$((rep + 1)); else add=$((add + 1)); fi
      RS_COPY+=("$src"$'\t'"$dest/$n")
    done
    s+=$'\n'"$(part_label "$p") (account $acct)"$'\n'"  $add new, $rep replaced (current ones kept as .bak-restore), $same unchanged"$'\n'
  done
  [ -n "$RS_NOTE" ] && s+=$'\n'"Left out (not valid):$RS_NOTE"$'\n'
  RS_SUM=$s
}
# Writes the plan. Accounts, passwords and groups are never touched.
rs_apply(){
  local kv e a t fail=0 vdf
  for kv in "${RS_SET[@]}"; do
    conf_set "${kv%%=*}" "${kv#*=}" || { echo "steam-arm-config: could not write $SA_CONF" >&2; fail=1; }
  done
  if [ -n "$RS_SYS_OUT" ]; then
    if ! { mkdir -p "$(dirname "$SA_TITLES_ETC")" && { [ ! -f "$SA_TITLES_ETC" ] || cp -p "$SA_TITLES_ETC" "$SA_TITLES_ETC.bak-restore"; } \
           && t=$(mktemp "$SA_TITLES_ETC.XXXXXX") && cat "$RS_SYS_OUT" > "$t" && chmod 644 "$t" && mv -f "$t" "$SA_TITLES_ETC"; }; then
      [ -n "${t:-}" ] && rm -f "$t"; echo "steam-arm-config: could not write $SA_TITLES_ETC" >&2; fail=1
    fi
  fi
  if [ -n "$RS_PERS_OUT" ]; then
    acct_put "$RS_ACCT" "$(bk_path "$RS_ACCT" personal-profiles)" < "$RS_PERS_OUT" \
      || { echo "steam-arm-config: could not write personal game profiles of $RS_ACCT" >&2; fail=1; }
  fi
  vdf=$(bk_path "$RS_ACCT" compat-tools)
  for e in "${RS_MAP[@]}"; do
    read -r a t <<<"$e"
    acct_run "$RS_ACCT" python3 "$SA_COMPATMAP_PY" "$vdf" "$a" "$t" >/dev/null || fail=1
  done
  for e in "${RS_COPY[@]}"; do
    acct_put "$RS_ACCT" "${e#*$'\t'}" < "${e%%$'\t'*}" || { echo "steam-arm-config: could not write ${e#*$'\t'}" >&2; fail=1; }
  done
  return "$fail"
}
# Existing normal account for personal parts (no create item). Status 1 on Back, 2 when none exists.
acct_pick(){
  local def
  acct_list
  [ ${#ACCT_ITEMS[@]} -gt 0 ] || return 2
  def=$(acct_default "$ACCT_CUR" "$(game_user)" "$ACCT_DESK")
  ui_menu "$1" "$2" --default "$def" "${ACCT_ITEMS[@]}"
}
# Sudo first when another account's files are read from a non-root menu.
acct_ready(){ [ "$(id -u)" = 0 ] || [ "$1" = "$(id -un)" ] || need_root; }
bk_parts_items(){ local p; for p in ${1//,/ }; do printf '%s\n%s\nON\n' "$p" "$(part_label "$p")"; done; }
maint_backup(){
  local d rc parts acct="" p
  local -a items=()
  mapfile -t items < <(bk_parts_items "${SA_BK_PARTS// /,}")
  d=$(owner_home)
  while :; do
    d=$(ui_input "Back up settings" "Folder for the backup file. It holds settings and game profiles only:
no sign-in data, Steam files, accounts or passwords." "$d") || return
    d=$(bk_expand "$d")
    case "$d" in /*) ;; *) ui_msg "Back up settings" "Type a full path, starting with / or ~."; continue;; esac
    bk_dir_ok "$d"; rc=$?
    if [ "$rc" = 2 ]; then
      ui_yesno "Back up settings" "Folder $d does not exist. Create it?" Create Back || continue
      as_owner mkdir -p -- "$d" 2>/dev/null || { ui_msg "Back up settings" "Could not create $d."; continue; }
      bk_dir_ok "$d"; rc=$?
    fi
    [ "$rc" = 0 ] || { ui_msg "Back up settings" "$(owner_user) cannot write to $d. Pick another folder."; continue; }
    while :; do
      parts=$(ui_check "Back up settings: parts" "Parts to save. SPACE turns a part on or off." "${items[@]}") || continue 2
      parts=$(echo "$parts" | paste -sd, -)
      [ -n "$parts" ] || { ui_msg "Back up settings" "Pick at least one part."; continue; }
      acct=""
      if any_personal "$parts"; then
        acct=$(acct_pick "Back up settings: account" "Account whose personal parts are saved:"); rc=$?
        [ "$rc" = 1 ] && continue
        if [ "$rc" = 2 ]; then
          ui_msg "Back up settings" "No normal account found: personal parts are left out."
          parts=$(drop_personal "$parts"); [ -n "$parts" ] || continue
        fi
        [ -n "$acct" ] && { acct_ready "$acct" || continue; }
      fi
      break 2
    done
  done
  ui_info "Back up settings" "Saving..."
  if bk_make "$d" "$parts" "$acct"; then
    bk_last_set "$d"
    p="Saved to:
$BK_PATH"
    [ -n "$BK_NOTE" ] && p="$p

$BK_NOTE"
    ui_msg "Back up settings" "$p

Restore it with Maintenance > Restore settings, or:
steam-arm-config restore FILE"
  else
    ui_msg "Back up settings" "No backup was written: $BK_ERR"
  fi
}
rs_ask_mode(){
  ui_menu "$1" "Current file differs from the one in the backup." --default merge \
    merge "Merge: add games missing here" replace "Replace: take the backup file as is"
}
# Merge conflicts of one titles file: RS_TAKE gets the games where the backup wins. Status 1 on Back.
rs_ask_conflicts(){
  local ids c id nm
  RS_TAKE=""
  ids=$(tc_ids conf "$2" "$3"); [ -n "$ids" ] || return 0
  c=$(ui_menu "$1" "$(tr ',' '\n' <<<"$ids" | wc -l) games have other lines in the backup than here." \
      backup "Backup wins for all" current "Keep current for all" each "Decide one by one") || return 1
  case "$c" in backup) RS_TAKE=all; return 0;; current) return 0;; esac
  for id in ${ids//,/ }; do
    nm=$(game_name "$id"); nm=${nm:-game $id}
    if ui_yesno "$1: $nm" "App $id

Current:
$(tc_lines "$2" "$id")

Backup:
$(tc_lines "$3" "$id")" Backup Current; then RS_TAKE="$RS_TAKE${RS_TAKE:+,}$id"; fi
  done
}
# Status 1: back to the file choice.
rs_menu(){
  local f=$1 sel acct="" sm=merge pm=merge ts="" tp="" rc comp g cur
  local -a items=() args=()
  rs_open "$f" || { ui_msg "Restore settings" "$RS_ERR"; return 1; }
  g="$RS_D/$SA_BK_TOP"
  mapfile -t items < <(bk_parts_items "$RS_PARTS")
  while :; do
    sel=$(ui_check "Restore settings: parts" "Parts in this backup. SPACE turns a part on or off." "${items[@]}") || { rs_close; return 1; }
    sel=$(echo "$sel" | paste -sd, -)
    [ -n "$sel" ] || { ui_msg "Restore settings" "Pick at least one part."; continue; }
    acct=""
    if any_personal "$sel"; then
      acct=$(acct_pick "Restore settings: account" "Account that gets the personal parts:"); rc=$?
      [ "$rc" = 1 ] && continue
      if [ "$rc" = 2 ]; then
        ui_msg "Restore settings" "No normal account found: personal parts are left out."
        sel=$(drop_personal "$sel"); [ -n "$sel" ] || continue
      fi
      [ -n "$acct" ] && { acct_ready "$acct" || continue; }
    fi
    break
  done
  if in_list "$sel" system-profiles && [ -f "$SA_TITLES_ETC" ] && ! cmp -s "$SA_TITLES_ETC" "$g/system/titles.conf"; then
    sm=$(rs_ask_mode "Restore: system game profiles") || { rs_close; return 1; }
    if [ "$sm" = merge ]; then rs_ask_conflicts "System game profiles" "$SA_TITLES_ETC" "$g/system/titles.conf" || { rs_close; return 1; }; ts=$RS_TAKE; fi
  fi
  if in_list "$sel" personal-profiles; then
    cur=$(rs_cur_personal "$acct")
    if [ -f "$cur" ] && ! cmp -s "$cur" "$g/personal/titles.conf"; then
      pm=$(rs_ask_mode "Restore: personal game profiles") || { rs_close; return 1; }
      if [ "$pm" = merge ]; then rs_ask_conflicts "Personal game profiles" "$cur" "$g/personal/titles.conf" || { rs_close; return 1; }; tp=$RS_TAKE; fi
    fi
  fi
  rs_plan "$sel" "$acct" "$sm" "$pm" "$ts" "$tp"
  ui_textstr "Restore settings: summary" "$RS_SUM" Next
  if ! ui_yesno "Restore settings" "Apply these changes from
$(basename "$f")?" Restore Back defaultno; then rs_close; return 1; fi
  comp=$RS_COMP; rs_close
  args=(restore "$f" --yes --parts "$sel" --system-profiles "$sm" --personal-profiles "$pm" --take-system "$ts" --take-personal "$tp")
  [ -n "$acct" ] && args+=(--account "$acct")
  bk_last_set "$(dirname "$f")"
  self_root "${args[@]}" || return 0
  if [ "$comp" = 1 ]; then
    ui_yesno "Restore settings" "Settings restored. Part lists changed: run setup --keep now so the installed parts match? It takes a few minutes." "Run setup" Later || return 0
    INST_ENV=(); run_installer "Restore settings" --keep
  else
    ui_msg "Restore settings" "Settings restored."
  fi
  return 0
}
maint_restore(){
  local d f c h seen=" " n=0
  local -a files=() items=()
  is_installed || { offer_install; return; }
  close_steam "Restore settings" "It reads these settings while it runs." || return
  h=$(owner_home)
  for d in "$(bk_last_dir)" "$h"; do
    [ -n "$d" ] || continue
    case "$seen" in *" $d "*) continue;; esac; seen="$seen$d "
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      n=$((n + 1)); files+=("$f"); items+=("$n" "$(basename "$f")  (${d/#"$h"/\~})")
    done < <(ls -t "$d"/steam-arm-settings-*.tar.gz 2>/dev/null)
  done
  items+=(p "Type a path...")
  while :; do
    if [ "$n" -gt 0 ]; then
      c=$(ui_menu "Restore settings" "Backup to restore (newest first):" "${items[@]}") || return
    else c=p; fi
    if [ "$c" = p ]; then
      f=$(ui_input "Restore settings" "Path of the backup file (steam-arm-settings-....tar.gz):" "$h/") || { [ "$n" -gt 0 ] && continue; return; }
      f=$(bk_expand "$f")
    else
      f=${files[$((c - 1))]}
    fi
    rs_menu "$f" && return
  done
}
menu_maintenance(){
  local c=""
  while c=$(ui_menu "Maintenance" "Keep Steam ARM working." --default "$c" \
      1 "Update / Repair (run setup again, same parts)" 2 "View logs" \
      3 "Hardware report (for a compatibility report)" 4 "Free /dev/shm now" \
      5 "Back up settings" 6 "Restore settings" 7 "Check for new version" \
      8 "Caches (sizes, clear FEX code caches)" 9 "GE-Proton (ARM64), optional (now: $(ge_state))" \
      10 "Client type (now: $([ "$(client_type)" = x86 ] && echo x86 || echo native ARM64))"); do
    case "$c" in
      1) if is_installed; then
           ui_yesno "Update / Repair" "Run setup again with the parts chosen at last setup?

Setup reinstalls packages, launcher, helpers and rules for those parts. Games, saves and sign-in stay in the client folder." Run Back defaultno || continue
           INST_ENV=(); run_installer "Update / Repair" --keep
         else offer_install; fi;;
      2) maint_logs;;
      3) maint_report;;
      4) maint_shm;;
      5) maint_backup;;
      6) maint_restore;;
      7) maint_update_check;;
      8) menu_caches;;
      9) menu_geproton;;
      10) maint_client;;
    esac
  done
}
# Client type: setup run with --keep --client=<type>; arm64 on Armv8.0 and x86 on Armv8.1 ask first (default Back).
client_switch(){
  local t=$1
  if [ "$t" = arm64 ] && ! cpu_has_lse; then
    ui_yesno "Client type" "This CPU has no Armv8.1 atomics (LSE). Valve's native client builds
newer than 15 April 2026 stop at start on it (steam-for-linux #13288).

Use native ARM64 client anyway?" "Use native" Back defaultno || return 1
  elif [ "$t" = x86 ] && cpu_has_lse; then
    ui_yesno "Client type" "This CPU runs Valve's native ARM64 client. x86 client runs through
emulation: slower start, client window drawn on CPU, Windows titles
on x86 Proton (prefixes made by ARM64 Proton may be rebuilt).

Use x86 client anyway?" "Use x86" Back defaultno || return 1
  fi
  INST_ENV=(); run_installer "Client type" --keep "--client=$t"
}
# Native client check (setup --client-check, no change); offers automatic choice when it runs here.
client_check_ui(){
  local -a cmd; local rc r
  mapfile -t cmd < <(installer_cmd) || true
  [ "${#cmd[@]}" -gt 0 ] || { ui_msg "Client type" "Setup script not found. Get it from $SA_DOCS and run it once."; return 1; }
  need_root || return 1
  if ! { mkdir -p "$SA_CACHE" && [ ! -L "$SA_CACHE" ] && chmod 700 "$SA_CACHE" \
         && SA_SETUP_LOG=$(mktemp --suffix=.log "$SA_CACHE/client-check-$(date +%Y%m%d-%H%M%S)-XXXXXX"); }; then
    ui_msg "Client type" "Could not create a log file in $SA_CACHE. Free some space, then try again."; return 1
  fi
  ui_run "Client type: check" "$SA_SETUP_LOG" as_root env STEAM_ARM_PROGRESS="$([ "$DIALOG" = builtin ] && echo 1)" "${cmd[@]}" --client-check; rc=$?
  r=$(strip_ansi < "$SA_SETUP_LOG" | grep '^native client: ' | tail -1)
  if [ "$rc" = 0 ] && [ "$(client_type)" = x86 ]; then
    ui_yesno "Client type" "${r:-native client: runs on this CPU}

Move back to native ARM64 client now? Setup runs and keeps games." "Switch" Back || return 0
    client_switch auto
  else
    ui_msg "Client type" "${r:-native client: check failed (no result; see $SA_SETUP_LOG)}"
  fi
}
maint_client(){
  local c="" t p
  is_installed || { offer_install; return; }
  while :; do
    p=$(conf_get CLIENT_PROBE); p=${p:+client ${p%%:*}, ${p#*:}}
    t="Now: $(client_label)
Native client last checked: ${p:-never}

Automatic picks x86 client only on CPUs without Armv8.1 atomics and
moves back once native client runs there. Switching closes Steam;
games and sign-in stay."
    c=$(ui_menu "Client type" "$t" --default "$c" auto "Automatic (recommended)" arm64 "Native ARM64 client" \
          x86 "x86 client through emulation" check "Check native client now") || return
    case "$c" in
      auto|arm64|x86) client_switch "$c";;
      check) client_check_ui;;
    esac
  done
}

# ===========================================================================
# 9. Uninstall
# ===========================================================================
uninstall_keep(){
  ui_yesno "Uninstall" "Remove Steam ARM?

Removes the launcher, menu entries, rules and settings it added, and puts back system settings it changed. Your games and sign-in stay in the client folder; setup asks before touching it.

Setup runs in the terminal and may ask questions there." Remove Back defaultno || return
  run_installer_tty --remove
}
uninstall_purge(){
  ui_yesno "Uninstall everything" "Remove Steam ARM AND delete all installed games, saves kept in the client folder, and the x86-64 system files setup downloaded?

This cannot be undone." Continue Back defaultno || return
  ui_yesno "Uninstall everything" "Last check: delete Steam ARM with every installed game?

Setup asks for one more typed confirmation in the terminal." "Delete all" Back defaultno || return
  run_installer_tty --remove --purge
}
menu_uninstall(){
  local c=""
  is_installed || { ui_msg "Uninstall" "Steam ARM is not installed."; return; }
  while c=$(ui_menu "Uninstall" "Games are kept unless you pick the second entry." --default "$c" \
      1 "Remove Steam ARM (keep games)" 2 "Remove Steam ARM and all games"); do
    case "$c" in 1) uninstall_keep;; 2) uninstall_purge;; esac
    is_installed || return
  done
}

# ===========================================================================
# 10. Help / About
# ===========================================================================
about_text(){ cat <<EOF
steam-arm-config $SA_VERSION: settings for Steam ARM.

Steam ARM runs Valve's ARM64 Steam client on ARM Linux boards. x86
games run through emulation (FEX); Windows games through Proton.

Keys: arrows move, Enter selects, TAB reaches the buttons, SPACE
toggles list items. Back: TAB to the Back button, then Enter.
Same settings from scripts: steam-arm-config --help

Documentation and compatibility reports: $SA_DOCS

This project is not affiliated with, endorsed by or sponsored by
Valve Corporation. Steam, Proton, Steam Deck and Steam Frame are
trademarks of Valve Corporation.
EOF
}

fixing_text(){ cat <<'EOF'
Fixing a game

What works
- Steam launch options (game Properties > General >
  Launch options), for example:
    PROTON_USE_WINED3D=1 %command%
        Windows game: OpenGL (WineD3D) in place of
        Vulkan (DXVK)
    -vulkan
        game's own Vulkan switch, where it has one
    MESA_GL_VERSION_OVERRIDE=4.5 %command%
        report a newer OpenGL version to the game
  A launch option wins over the automatic rules; the
  game log then says "launch option kept".
- Games screen of this menu: overlay, MangoHud, extra
  environment and arguments, FEX code cache, one game
  at a time.
- Crash at start after game or FEX tool update, with
  FEX code cache on: Maintenance > Caches, clear that
  game.
- Graphics > Route per game: A (forwarding to host
  drivers) or B (Mali drivers inside the emulation),
  for x86 Linux games.
- Videos in Windows games show colour bars: turn on
  the shader-cache part (Components). It downloads
  several GB and processes caches on all cores after
  installs and updates. Turning it off keeps the
  cache, and turning it on again reuses it.
  Deleting steamapps/shadercache by hand stops
  Steam from downloading those caches again.

Game is slow (CPU-bound)
- Games > game > rules of last start, or Maintenance
  > Hardware report: line "renderer:". "GPU (...)"
  means GPU drawing. "GPU forwarding not active:
  rendering on CPU (llvmpipe)" means CPU drawing;
  reason follows in same line.
- GPU line, game still slow: lower its resolution.
  Frame rate goes up: GPU limit. Unchanged: CPU limit
  (x86 code runs through emulation).
- MangoHud shows per-core load: one core near 100%
  while frame rate stays low means CPU limit.

Proton version keeps changing back
- Choice in Steam (Properties > Compatibility) wins;
  this menu writes it only through Graphics > Linux
  or Windows build. Steam saves it in config.vdf;
  close Steam from its own menu once after change.
- Log line "compat: warning: ...": saved choice and
  started build differ.
- Title switched to Windows build by itself: automatic
  Windows build (Graphics). Force Linux build keeps
  Linux build for good.

What to avoid
- MANGOHUD=1 or "mangohud %command%" on Windows games
  (Proton ARM64): the game crashes.
- Options made for NVIDIA or AMD graphics cards.
- Installing packages inside the emulation (apt or
  dpkg under FEX): they write to the real system and
  can damage it.

What cannot be fixed here
- Direct3D 12 games.
- Unreal Engine 4 and 5 games.
- Games with kernel anti-cheat.

Reading "Rules used at last start" (Games > a game)
- "graphics: forwarding" or "graphics: Mali drivers
  in emulation": route of the last start, reason in
  brackets.
- "launch option kept: NAME=value (rule wanted ...)":
  your launch option won over a rule.
- "title setting kept: gfx=...": the route set for
  this game won over the rules.
- "renderer: GPU (...)" or "renderer: warning: GPU
  forwarding not active ...": drawing on GPU or CPU.
- No lines: the game has not started since setup. Windows
  games under x86 Proton show only compat and Godot note
  lines (Proton keeps its own logs).
EOF
}
menu_help(){
  local c=""
  while c=$(ui_menu "Help / About" "Choose a page." --default "$c" 1 "Fixing a game" 2 "About steam-arm-config"); do
    case "$c" in 1) ui_textstr "Fixing a game" "$(fixing_text)";; 2) ui_textstr "About" "$(about_text)";; esac
  done
}

# ===========================================================================
# Main menu
# ===========================================================================
offer_install(){
  ui_yesno "Steam ARM" "Steam ARM is not installed yet. Install it now?" Install Back && menu_setup
}
menu_main(){
  local c=""
  status_line
  while c=$(ui_menu "steam-arm-config" "Choose a section." --cancel Exit --default "$c" \
      1 "Information" 2 "Install / Setup" 3 "Components" 4 "Graphics" 5 "Games" \
      6 "Controllers" 7 "Remote Play" 8 "Maintenance" 9 "Uninstall" 10 "Help / About"); do
    case "$c" in
      1) menu_info;; 2) menu_setup;; 3) menu_components;; 4) menu_graphics;; 5) menu_games;;
      6) menu_controllers;; 7) menu_remoteplay;; 8) menu_maintenance;; 9) menu_uninstall;;
      10) menu_help;;
    esac
    status_line
  done
  [ -n "$SA_DIALOGRC" ] && rm -f "$SA_DIALOGRC"
  clear 2>/dev/null
}

# ===========================================================================
# Command line
# ===========================================================================
usage(){ cat <<EOF
Usage: steam-arm-config [command]

Settings for Steam ARM. Without a command: menu (built-in screens,
dialog, whiptail or plain prompts). Changes ask for administrator rights
through sudo.

Commands
  info                      system, Steam ARM status and hardware notes
  report                    hardware report without personal details,
                            saved to $SA_REPORT
  gfx <appid> auto|a|b      graphics route of one game: automatic,
                            A forwarding, B Mali drivers in emulation
  gfx-default auto|a|b      route for games without their own setting:
                            automatic rules, A forwarding for all,
                            B Mali drivers in emulation for all
  profile <appid> key=value ...
                            game profile keys (overlay, mangohud, env,
                            args, gl32, vk32, godot, unity, gfx,
                            multiblock, diskcache);
                            key= removes one, --clear removes all
  compat <appid> linux|windows|ge|clear
                            force Linux build or Windows build (Proton;
                            ge: newest installed GE-Proton build),
                            clear removes it (and record of automatic
                            Windows build it matches); Steam must be closed
  auto-build [on|off]       automatic Windows build for titles whose
                            Linux build fails under emulation; no value:
                            state, rules and titles set
  cpu-notice [on|off]       desktop notice when an x86 game draws on CPU
                            (off by default); no value: state
  components a,b,...        install exactly these parts (runs setup)
  driver-archive status|download|local FILE|custom FILE SHA256
                            driver archive of gpu-in-emulation: download
                            (default), local copy of published archive,
                            or custom archive (own Mesa build); local and
                            custom run setup
  backup [DIR] [--account NAME] [--parts a,b,...]
                            settings backup file in DIR (default: your
                            home), readable by you only; parts: setup,
                            system-profiles, personal-profiles,
                            compat-tools, fex, mangohud (default: all);
                            personal parts come from NAME (default: you,
                            else the game account)
  restore FILE [--account NAME] [--parts a,b,...] [--merge|--replace]
               [--system-profiles merge|replace]
               [--personal-profiles merge|replace]
               [--take-system IDS|all] [--take-personal IDS|all] [--yes]
                            restore parts of a backup (default: all it
                            holds); profiles merge by default and keep
                            current lines of games set both here and in
                            the backup, unless --take-* names them;
                            accounts, passwords and groups are never
                            changed; asks before applying unless --yes
  cache                     sizes of FEX code caches and Steam
                            shader cache, per game
  cache list                one line per cache folder: app id, kind,
                            size in KB, path
  cache clear all|<appid>   delete FEX code caches (all games, or
                            one game); Steam shader caches stay;
                            refused while a game runs
  ge-proton [status]        GE-Proton builds in client's
                            compatibilitytools.d and Steam Linux Runtime
                            4.0 (Arm64) state; no network
  ge-proton check           newest GE-Proton release with ARM64 build
                            on GitHub (nothing downloads)
  ge-proton install [TAG] [--file FILE.tar.gz] [--move]
                            optional third-party Proton build: download
                            newest (TAG: that release) or take FILE with
                            its .sha512sum beside it, check sha512,
                            unpack as game account; --move moves games
                            from older builds installed here, removes them
  ge-proton remove TAG [--to TAG|--to default]
                            remove build installed here; games set to it
                            move to TAG, or setting removed (Linux build,
                            else Steam's default Proton); Steam closed
  update-check              ask GitHub for the newest release and compare
                            it with this version (nothing downloads)
  help fixing              what helps a game that does not start or
                            draws wrong, and what cannot be fixed
  --help                    this text

Environment
  STEAM_ARM_DIALOG=builtin|dialog|whiptail|read
                            menu front end (default: builtin screens when
                            python3 with curses is present, else dialog,
                            else whiptail, else plain prompts)
  STEAM_ARM_INSTALLER=file  setup script to run (default: steam-arm-setup,
                            else $SA_SHARE_INSTALLER,
                            else steam-arm-install.sh beside this app);
                            the installer sets it when it opens this menu
  STEAM_ARM_ALLOW_ARMV80=1  native ARM64 client on Armv8.0 CPU in place of
                            x86 client (Install / Setup); passed on to setup

Files
  $SA_CONF      settings (GFX_DEFAULT=auto|a|b;
                            forward is read as a; AUTO_BUILD=on|off;
                            CPU_NOTICE=on|off; CLIENT=arm64|x86 set by
                            setup, Maintenance > Client type)
  $SA_TITLES_ETC        game profiles written here
  ~/steam-arm-report.txt    hardware report (report command)
  ~/.cache/steam-arm/       logs of setup runs started here

Documentation: $SA_DOCS
Not affiliated with Valve Corporation. Steam, Proton, Steam Deck and
Steam Frame are trademarks of Valve Corporation.
EOF
}
cli_gfx(){
  valid_appid "${1:-}" || { echo "usage: steam-arm-config gfx <appid> auto|a|b" >&2; return 2; }
  [ "${2:-}" != b ] || route_b_ok || { echo "steam-arm-config: $SA_NO_ROUTE_B" >&2; return 1; }
  case "${2:-}" in auto) tc_set "$SA_TITLES_ETC" "$1" gfx "";; a|b) tc_set "$SA_TITLES_ETC" "$1" gfx "$2";;
    *) echo "usage: steam-arm-config gfx <appid> auto|a|b" >&2; return 2;; esac \
    && echo "app $1: graphics $(gfx_label "$([ "$2" = auto ] || echo "$2")")" \
    && { [ "$2" != b ] || mali_ready || echo "note: $SA_NO_MALI"; }
}
cli_gfx_default(){
  local v
  case "${1:-}" in auto) v=auto;; a|forward) v=a;; b) v=b;;
    *) echo "usage: steam-arm-config gfx-default auto|a|b" >&2; return 2;; esac
  [ "$v" != b ] || route_b_ok || { echo "steam-arm-config: $SA_NO_ROUTE_B" >&2; return 1; }
  case "$v" in auto|a|b) conf_set GFX_DEFAULT "$v" && echo "default graphics route: $(gfx_default_label "$(gfx_default)")" \
                   && { [ "$v" != b ] || mali_ready || echo "note: $SA_NO_MALI"; };;
    *) echo "usage: steam-arm-config gfx-default auto|a|b" >&2; return 2;; esac
}
profile_ok(){ case "$1=$2" in
  overlay=|overlay=x86|overlay=vulkan|overlay=off|mangohud=|mangohud=on|mangohud=off|gfx=|gfx=a|gfx=b) return 0;;
  gl32=|gl32=off|vk32=|vk32=keep|godot=|godot=gl|godot=vulkan|unity=|unity=vulkan|unity=gl) return 0;;
  multiblock=|multiblock=on|multiblock=off|diskcache=|diskcache=on|diskcache=off) return 0;;
  env=*|args=*) valid_value "$2";;
  *) return 1;;
esac; }
cli_profile(){
  local id=${1:-} kv k v
  valid_appid "$id" || { echo "usage: steam-arm-config profile <appid> key=value ..." >&2; return 2; }
  shift
  if [ "${1:-}" = --clear ]; then
    for k in overlay mangohud env args gl32 vk32 godot unity gfx multiblock diskcache; do tc_set "$SA_TITLES_ETC" "$id" "$k" "" || return 1; done
    echo "app $id: profile removed"; return 0
  fi
  for kv in "$@"; do
    k=${kv%%=*}; v=${kv#*=}
    if [ "$k" = "$kv" ] || ! profile_ok "$k" "$v"; then echo "steam-arm-config: bad setting: $kv" >&2; return 2; fi
    [ "$kv" != gfx=b ] || route_b_ok || { echo "steam-arm-config: $SA_NO_ROUTE_B" >&2; return 1; }
  done
  for kv in "$@"; do tc_set "$SA_TITLES_ETC" "$id" "${kv%%=*}" "${kv#*=}" || return 1; done
  echo "app $id: $(tc_effective "$id" | tr '\n' ' ')"
}
cli_compat(){
  valid_appid "${1:-}" || { echo "usage: steam-arm-config compat <appid> linux|windows|ge|clear" >&2; return 2; }
  steam_running && { echo "steam-arm-config: Steam ARM is running; close it first (as $(game_user): steam-arm --shutdown)" >&2; return 1; }
  case "${2:-}" in
    linux)   "$SA_COMPATMAP" "$1" steamlinuxruntime;;
    windows) if [ "$(client_type)" = x86 ]; then "$SA_COMPATMAP" "$1" "$X86_PROTON"; else "$SA_COMPATMAP" "$1" "$ARM64_PROTON"; fi;;
    ge)      local t; t=$(ge_newest)
             [ -n "$t" ] || { echo "steam-arm-config: no GE-Proton build installed (steam-arm-config ge-proton install)" >&2; return 1; }
             "$SA_COMPATMAP" "$1" "$t";;
    clear)   # record dropped only when mapping was the rule's own (hand-set tool never comes back)
             local v; v=$(ab_app "$1")
             "$SA_COMPATMAP" "$1" --remove || return
             if [ "$v" = auto ]; then ab_drop "$1"; fi;;
    *) echo "usage: steam-arm-config compat <appid> linux|windows|ge|clear" >&2; return 2;;
  esac
}
cli_auto_build(){
  case "${1:-}" in
    on|off) conf_set AUTO_BUILD "$1" && echo "automatic Windows build: $1";;
    '')
      echo "automatic Windows build: $(auto_build)"
      [ -f "$SA_AUTOBUILD_PY" ] || { echo "rule file missing: $SA_AUTOBUILD_PY (run setup again)"; return 0; }
      ab_list | awk -F'\t' '
        $1 == "rule" { printf "rule %s: %s, tool %s, GPU family %s, FEX tool up to %s\n", $2, $6, $3, $4, $5 }
        $1 == "gate" && $3 != "-" { printf "  on this system: suggestion only (%s)\n", $3 }
        $1 == "app" { printf "app %s %s %s: %s\n", $2, $3, $4, $5 }
        $1 == "record" { printf "record app %s %s %s %s\n", $2, $3, $4, $5 }
        $1 == "partial" { printf "library scan stopped after %s s\n", $2 }';;
    *) echo "usage: steam-arm-config auto-build [on|off]" >&2; return 2;;
  esac
}
cli_cpu_notice(){
  case "${1:-}" in
    on|off) conf_set CPU_NOTICE "$1" && echo "CPU drawing notice: $1";;
    '') echo "CPU drawing notice: $(cpu_notice)";;
    *) echo "usage: steam-arm-config cpu-notice [on|off]" >&2; return 2;;
  esac
}
cli_components(){
  local -a cmd; mapfile -t cmd < <(installer_cmd) || true
  [ "${#cmd[@]}" -gt 0 ] || { echo "steam-arm-config: setup script not found" >&2; return 1; }
  "${cmd[@]}" "--select=${1:-}"
}
cli_driver_archive(){
  local -a cmd; local u="usage: steam-arm-config driver-archive status|download|local FILE|custom FILE SHA256" e h
  case "${1:-}/$#" in status/1|download/1|local/2|custom/3) ;; *) echo "$u" >&2; return 2;; esac
  case "$1" in
    status) echo "driver archive: $(da_status)"; return 0;;
    download)
      if [ -z "$(conf_get PROVIDER_CUSTOM_SHA256)" ]; then
        if [ -n "$(conf_get PROVIDER_LOCAL_FILE)" ]; then
          conf_del PROVIDER_LOCAL_FILE || { echo "steam-arm-config: could not write $SA_CONF" >&2; return 1; }
          echo "driver archive: download from project release on next build of Mali tree"
        else echo "driver archive: already set to download"; fi
        return 0
      fi;;
    custom) h=$(printf '%s' "$3" | tr 'A-F' 'a-f')
      [[ "$h" =~ ^[0-9a-f]{64}$ ]] || { echo "steam-arm-config: SHA256 must be 64 characters, 0-9 and a-f" >&2; return 2; };;
  esac
  mapfile -t cmd < <(installer_cmd) || true
  [ "${#cmd[@]}" -gt 0 ] || { echo "steam-arm-config: setup script not found" >&2; return 1; }
  [ "$1" = download ] && { "${cmd[@]}" --keep --provider-default; return; }
  e=$(da_path_err "$2"); [ -z "$e" ] || { echo "steam-arm-config: $e" >&2; return 1; }
  [[ " $(comps_effective) " == *" gpu-in-emulation "* ]] \
    || { echo "steam-arm-config: gpu-in-emulation is off; add it with steam-arm-config components ...,gpu-in-emulation first" >&2; return 1; }
  if [ "$1" = local ]; then
    read -r _ h <<<"$(da_pub)"
    [ "$(sha256sum -- "$2" 2>/dev/null | cut -c1-64)" = "$h" ] \
      || { echo "steam-arm-config: $2 does not match published archive (sha256 ${h:0:12}...); pick custom for own Mesa build" >&2; return 1; }
    if [ -n "$(conf_get PROVIDER_CUSTOM_SHA256)" ]; then env STEAM_ARM_PROVIDER_TARBALL="$2" "${cmd[@]}" --keep --provider-default
    else env STEAM_ARM_PROVIDER_TARBALL="$2" "${cmd[@]}" --keep; fi
  else
    env STEAM_ARM_PROVIDER_TARBALL="$2" STEAM_ARM_PROVIDER_SHA256="$h" "${cmd[@]}" --keep
  fi
}
cli_cache(){
  local u="usage: steam-arm-config cache [list|clear all|clear <appid>]"
  case "${1:-}/$#" in
    /0|list/1) ;;
    clear/2) [ "$2" = all ] || valid_appid "$2" || { echo "$u" >&2; return 2; };;
    *) echo "$u" >&2; return 2;;
  esac
  [ "${1:-}" = clear ] || CLI_ROOT_WHY="game account's caches are readable only with administrator rights"
  [ "$(id -u)" = 0 ] || [ "$(id -un)" = "$(game_user)" ] || cli_root cache "$@"
  case "${1:-}" in
    "") cache_text;;
    list) cache_scan;;
    clear) cache_clear "$2";;
  esac
}
cli_ge(){
  local u="usage: steam-arm-config ge-proton [status|check|install [TAG] [--file FILE] [--move]|remove TAG [--to TAG|default]]" out
  case "${1:-status}/$#" in status/[01]|check/1|install/*|remove/2|remove/4) ;; *) echo "$u" >&2; return 2;; esac
  [ -f "$SA_GE_PY" ] || { echo "steam-arm-config: helper $SA_GE_PY missing; run setup again (Maintenance > Update / Repair)" >&2; return 1; }
  case "${1:-status}" in
    status) ge_text --sizes;;
    check)  out=$(ge_check_raw) || return; ge_check_text "$out";;
    *)      [ "$(id -u)" = 0 ] || [ "$(id -un)" = "$(game_user)" ] || cli_root ge-proton "$@"
            ge_run "$@" </dev/null;;
  esac
}
cli_need(){ [ "$1" -ge 2 ] || { echo "steam-arm-config: $2 needs a value (see --help)" >&2; return 1; }; }
# Account for personal parts: --account (existing normal account only), else caller, game account, desktop user.
cli_acct(){
  acct_list
  if [ -n "$1" ]; then
    [[ "$ACCT_NAMES" == *" $1 "* ]] || { echo "steam-arm-config: $1 is not an existing normal account" >&2; return 1; }
    echo "$1"
  else acct_default "$ACCT_CUR" "$(game_user)" "$ACCT_DESK"; fi
}
cli_backup(){
  local dir="" parts=${SA_BK_PARTS// /,} acct="" aset=""
  local -a orig=("$@")
  while [ $# -gt 0 ]; do
    case "$1" in
      --account) cli_need $# "$1" || return 2; aset=$2; shift 2;;
      --parts)   cli_need $# "$1" || return 2; parts=$2; shift 2;;
      -*) echo "steam-arm-config: unknown option: $1 (see --help)" >&2; return 2;;
      *) [ -z "$dir" ] || { echo "usage: steam-arm-config backup [DIR] [--account NAME] [--parts a,b,...]" >&2; return 2; }
         dir=$1; shift;;
    esac
  done
  parts_ok "$parts" || return 2
  if any_personal "$parts"; then
    acct=$(cli_acct "$aset") || return 2
    [ -n "$acct" ] && [ "$(id -u)" != 0 ] && [ "$acct" != "$(id -un)" ] && cli_root backup "${orig[@]}"
  fi
  bk_make "${dir:-$(owner_home)}" "$parts" "$acct" || { echo "steam-arm-config: $BK_ERR" >&2; return 1; }
  printf '%s' "$BK_NOTE"
  echo "Saved to $BK_PATH"
}
cli_restore(){
  local f="" parts="" acct="" aset="" sm=merge pm=merge ts="" tp="" yes=0 a
  while [ $# -gt 0 ]; do
    case "$1" in
      --account) cli_need $# "$1" || return 2; aset=$2; shift 2;;
      --parts)   cli_need $# "$1" || return 2; parts=$2; shift 2;;
      --merge)   sm=merge; pm=merge; shift;;
      --replace) sm=replace; pm=replace; shift;;
      --system-profiles)   cli_need $# "$1" || return 2; sm=$2; shift 2;;
      --personal-profiles) cli_need $# "$1" || return 2; pm=$2; shift 2;;
      --take-system)   cli_need $# "$1" || return 2; ts=$2; shift 2;;
      --take-personal) cli_need $# "$1" || return 2; tp=$2; shift 2;;
      --yes) yes=1; shift;;
      -*) echo "steam-arm-config: unknown option: $1 (see --help)" >&2; return 2;;
      *) [ -z "$f" ] || { echo "usage: steam-arm-config restore FILE [options] (see --help)" >&2; return 2; }
         f=$1; shift;;
    esac
  done
  [ -n "$f" ] || { echo "usage: steam-arm-config restore FILE [options] (see --help)" >&2; return 2; }
  case "$sm,$pm" in merge,merge|merge,replace|replace,merge|replace,replace) ;;
    *) echo "steam-arm-config: profiles mode is merge or replace" >&2; return 2;; esac
  [[ "$ts" =~ ^(all|[0-9,]*)$ ]] && [[ "$tp" =~ ^(all|[0-9,]*)$ ]] || { echo "steam-arm-config: --take-* takes app ids (a,b,...) or all" >&2; return 2; }
  is_installed || { echo "steam-arm-config: Steam ARM is not installed; install it, then restore" >&2; return 1; }
  steam_running && { echo "steam-arm-config: Steam ARM is running; close it first (as $(game_user): steam-arm --shutdown)" >&2; return 1; }
  rs_open "$f" || { echo "steam-arm-config: $RS_ERR" >&2; return 1; }
  if [ -n "$parts" ]; then
    parts_ok "$parts" || { rs_close; return 2; }
    for a in ${parts//,/ }; do in_list "$RS_PARTS" "$a" || { echo "steam-arm-config: part $a is not in this backup (it holds $RS_PARTS)" >&2; rs_close; return 2; }; done
  else parts=$RS_PARTS; fi
  if any_personal "$parts"; then
    acct=$(cli_acct "$aset") || { rs_close; return 2; }
    if [ -z "$acct" ]; then echo "No normal account found: personal parts are left out."; parts=$(drop_personal "$parts"); fi
    [ -n "$parts" ] || { rs_close; return 1; }
  fi
  rs_plan "$parts" "$acct" "$sm" "$pm" "$ts" "$tp"
  printf '%s\n' "$RS_SUM"
  if [ "$yes" != 1 ]; then
    if [ -t 0 ]; then
      printf 'Apply these changes? [y/N] '; read -r a
      case "$a" in y|Y|yes|YES) ;; *) echo "Nothing changed."; rs_close; return 1;; esac
    else echo "steam-arm-config: add --yes to apply without a terminal" >&2; rs_close; return 1; fi
  fi
  if rs_apply; then
    echo "Settings restored."
    [ "$RS_COMP" = 1 ] && echo "Part lists changed: run Maintenance > Update / Repair (setup --keep) so the installed parts match."
    rs_close; return 0
  fi
  rs_close; return 1
}
main(){
  case "${1:-}" in
    -h|--help) usage;;
    help)        if [ "${2:-}" = fixing ]; then fixing_text; else usage; fi;;
    info)        echo "== System"; info_system; echo; echo "== Steam ARM"; info_status; echo; echo "== Notes"; info_notes;;
    report)      report_make && cat "$SA_REPORT" && echo && echo "Saved to $SA_REPORT (home folder of the account that ran this)";;
    gfx)         cli_root "$@"; shift; cli_gfx "$@";;
    gfx-default) cli_root "$@"; shift; cli_gfx_default "$@";;
    profile)     cli_root "$@"; shift; cli_profile "$@";;
    compat)      cli_root "$@"; shift; cli_compat "$@";;
    auto-build)  case "${2:-}" in on|off) cli_root "$@";; esac; shift; cli_auto_build "$@";;
    cpu-notice)  case "${2:-}" in on|off) cli_root "$@";; esac; shift; cli_cpu_notice "$@";;
    components)  cli_root "$@"; shift; cli_components "$@";;
    driver-archive) case "${2:-}" in download|local|custom) cli_root "$@";; esac; shift; cli_driver_archive "$@";;
    backup)      shift; cli_backup "$@";;
    restore)     cli_root "$@"; shift; cli_restore "$@";;
    cache)       shift; cli_cache "$@";;
    ge-proton)   shift; cli_ge "$@";;
    update-check) update_check; [ $? = 2 ] && exit 1; exit 0;;
    ''|menu)
      if [ ! -t 0 ] || [ ! -t 1 ]; then echo "steam-arm-config: the menu needs a terminal; see --help" >&2; exit 1; fi
      ui_pick; menu_main;;
    *) echo "steam-arm-config: unknown command: $1 (see --help)" >&2; exit 2;;
  esac
}

main "$@"
STEAMARMCONFIG
}
usage(){
  local c mark
  echo "Steam ARM $SA_VERSION installer"
  cat <<'USAGE'
Usage: sudo bash steam-arm-install.sh [--defaults | --select a,b,... | --skip a,b,...]
       sudo bash steam-arm-install.sh --remove [--purge]
       bash steam-arm-install.sh --detect | --list | --help

Installs Valve's native ARM64 Steam client for the desktop user, with the pieces it
needs on this system. Nothing downloads until this command runs.

Same installer as `.deb` package built from GitHub source (`build-deb.sh`); that
package's command is `steam-arm-setup`, options below are identical either way.

Options
  (none)            in a terminal: settings menu (steam-arm-config) with install,
                    components, graphics and uninstall; without terminal on desktop:
                    checklist dialog (zenity) of components
  --defaults        recommended components, no questions (GPU-related defaults
                    follow detected GPU family, see --detect)
  --keep            components saved by last run, no questions (recommended set if none)
  --select a,b      exactly these components
  --skip a,b        recommended components, without these
  --list            print components and exit
  --detect          print detected GPU family, drivers, page size, distribution and
                    default components, then exit; installs nothing, needs no root
  --help            print this text and exit
  --replace-other   retire other variant of this installer when present: its files
                    go into one backup archive in /var/backups, then removed; its
                    client folder and account stay in use unless set here
  --detect-other    print whether other variant of this installer is present
                    (status 0 when present), then exit; needs no root
  --provider-default
                    gpu-in-emulation: back to download of published driver
                    archive (clears saved local and custom archive settings;
                    rebuilds after custom archive)
  --remove          uninstall: removes everything this installer added and restores
                    changed system settings; asks before deleting client folder
                    (games live there), keeps it by default; distribution packages stay
  --remove --purge  also deletes client folder with all games and, when setup
                    downloaded it, the x86-64 root filesystem, after typed confirmation
  --password-stdin  first line of standard input is password of game account, used
                    only when setup creates that account (not printed, not logged)
  --client=auto|arm64|x86
                    client type, kept for later runs: arm64 = Valve's native ARM64
                    client, x86 = Valve's x86 client through emulation, auto = by CPU
                    (x86 only on CPUs without Armv8.1 atomics; default)
  --client-check    download newest native client package and check whether it runs
                    on this CPU (prints result, changes nothing; status 0 runs,
                    1 still needs Armv8.1, 2 check failed); needs installed setup

Always installed: host packages, x86-64 root filesystem, client package, launcher,
settings menu steam-arm-config.

Components (* = on by default on this system)
USAGE
  for c in $COMPONENTS; do
    mark=" "; eval "[ \"\$$(var_of "$c")\" = 1 ]" && mark="*"
    printf '  %s %-16s %s\n' "$mark" "$c" "$(desc_of "$c")"
  done
  cat <<'USAGE'

  shader-cache (off by default) lets the client download shader caches and
  transcoded videos for Windows titles, so their in-game videos play in place
  of colour bars. Costs several GB of disk and long processing on all cores
  after an install or update. Turning it off keeps the cache; turning it on
  again reuses it. Deleting the cache folder by hand
  (<client folder>/.local/share/Steam/steamapps/shadercache) stops the client
  from downloading those caches again.

  physx-skip (on by default) marks PhysX install step of Windows titles as
  done in their prefix, else stops it after 60 s (PhysX installer hangs
  under emulation).
  Turning it off stops only that watcher; its helper file stays.

  kde-input-prompt (off by default, KDE Plasma only) pre-authorises input
  from X11 programs in KDE's permission store, so controller driving desktop
  raises no "Remote control requested" prompt. Trade-off: every X11 program
  may then send input without asking. Turning it off, or --remove, puts back
  value from before.

Examples
  sudo bash steam-arm-install.sh --defaults
  sudo bash steam-arm-install.sh --skip tray                           no tray icon
  sudo bash steam-arm-install.sh --skip icon-bigpicture,icon-desktop   no desktop icons
  sudo bash steam-arm-install.sh --select desktop,desktop-mode         menu entries only
  sudo env GAMEUSER=alice bash steam-arm-install.sh --defaults         install for account alice

Re-running
  --keep, and any run without terminal or dialog, reuse account and components saved
  by last run; checklist and dialog start from them.
  A component left out on a later run is removed again. Installed games, sign-in
  and settings are kept: install, re-run, component changes and package upgrades
  never touch the game library.

After install
  Start "Steam ARM" from the menu, or run: steam-arm
  Sign in from Big Picture, or from "Steam ARM (Desktop mode)". The first start
  downloads the client and restarts it once.
  Settings later: "Steam ARM Settings" menu entry, steam-arm-config (menu), or
  steam-arm-config --help

Environment
  GAMEUSER=name                account to install into (default: account of last run,
                               else uid 1000)
  ARMHOME_DIR=path             client folder relative to home of that account, first
                               install only (default .local/share/steam-arm)
  STEAM_ARM_IGNORE_PAGESIZE=1  skip the 4K page size check; on a non-4K kernel kept in
                               the settings file, so launcher and later runs honour it
  STEAM_ARM_ALLOW_ARMV80=1     native ARM64 client on Armv8.0 CPU in place of x86 client
                               (same as --client=arm64, kept for later runs); client builds
                               newer than 15 April 2026 stop at start there (steam-for-linux
                               issue 13288); launcher honours it too
  GPU_FAMILY=id                GPU family in place of detection, kept for later runs
                               (GPU_FAMILY=auto detects again); wrong id lists valid ones
  STEAM_ARM_PROVIDER_TARBALL=file
                               gpu-in-emulation: local driver archive in place of its
                               download (checksum still checked); saved for later
                               runs; file named as published one beside this script
                               is used without it; settings menu: Components, Driver
                               archive; other steps still need network
  STEAM_ARM_PROVIDER_SHA256=sha256
                               with STEAM_ARM_PROVIDER_TARBALL: custom driver archive
                               (own Mesa build), accepted when its sha256 matches;
                               saved for later runs, --provider-default undoes it
Environment of the launcher (steam-arm) and its helpers
  STEAM_ARM_HOME=path          client folder in place of the saved one (absolute path)
  STEAM_ARM_PHYSX_SKIP=0       physx-skip off for this session; =1 on for this session
  STEAM_ARM_VK_SPOOF_DEBUG=1   troubleshooting: Vulkan feature layer (vk-spoof) prints
                               its decisions to the game's output
  STEAM_ARM_RENDERER_CHECK=0   launch option of x86 Linux title: no renderer check
                               (log line "renderer:") for that title
  STEAM_ARM_AUTO_BUILD=0       launch option of x86 Linux title: Linux build starts although
                               automatic Windows build applies to it; Linux build stuck at
                               loading screen ignores Stop in Steam (desktop task manager
                               ends it)
  STEAM_ARM_MODE_RESTORE=0     no display mode restore: by default (X11 session) launcher
                               saves display mode when game starts and puts it back
                               when game ends, crashes or is stopped, and when Steam closes
Stopping client
  steam-arm --shutdown         asks running client to exit; after 20 s without effect
                               (x86 client: 45 s), stops it with SIGTERM (never SIGKILL)

Graphics per title (x86 Linux titles)
  Forwarding (default): emulated title's GL and Vulkan calls run on host GPU drivers.
  With gpu-in-emulation on Mali GPU, titles that fail on forwarding switch automatically
  to Mali drivers inside emulation: Java titles, and 32-bit titles started with -vulkan or
  -force-vulkan (Mali-G610 class, mali-csf-v10, only). Game log line
  "steam-arm: graphics:" names choice.
  Per title, in /etc/steam-arm/titles.conf:  <appid> gfx=b  (Mali drivers inside
  emulation)  or  <appid> gfx=a  (forwarding).
  GFX_DEFAULT in /etc/steam-arm/steam-arm.conf, for titles without gfx= of their own:
    auto     forwarding, automatic switch above (default; empty means the same)
    a        every title on forwarding, no automatic switch (forward: same)
    b        every title on Mali drivers inside emulation (slower in titles with heavy
             processor load)
  Custom driver archive (STEAM_ARM_PROVIDER_SHA256): gfx=b and GFX_DEFAULT=b also
  work on other GPU families; automatic switch stays Mali-only.
  steam-arm-config sets it too (Graphics > Default route).

x86 client (CPU without Armv8.1 atomics)
  Valve's native ARM64 client stops at start on Armv8.0 CPUs (Cortex-A53, A57, A72, A73),
  so setup installs Valve's x86 client there and runs it through emulation (system FEX,
  host bubblewrap for its runtime containers). First start downloads client files and
  takes several minutes; client window draws on CPU; games reach GPU through emulator's
  GL and Vulkan forwarding; Windows titles use x86 Proton. Every setup run checks newest
  native client and moves back to it once it runs on this CPU (--client-check: check only).
  Needs 2 GB of memory or more.

Automatic Windows build
  32-bit Source engine titles get Proton ARM64 at start of Steam ARM (mali-csf-v10, native
  client, FEX tool up to 2609, vk-spoof chosen), once per title, when no build is chosen for
  them. AUTO_BUILD=off in
  /etc/steam-arm/steam-arm.conf turns it off (settings menu: Graphics > Automatic Windows
  build).

Documentation: README.md beside this script, or https://github.com/Scrumpper/Steam-ARM

This project is not affiliated with, endorsed by or sponsored by Valve Corporation.
Steam, Proton, Steam Deck and Steam Frame are trademarks of Valve Corporation.
USAGE
}
# Valve client package $2 from manifest $1 into a new root-owned stage $STAGE (client.zip); PKG_VER = manifest version.
# Status 1 with DL_ERR set on failure (callers stop or note it).
client_dl(){ client_manifest "$1" "$2" && client_pkg; }
# Manifest $1 into a new stage: PKG_VER, ENTRY and DL_SHA2 of package $2.
client_manifest(){
  DL_ERR=; PKG_VER=; DL_SHA2=
  STAGE=$(mktemp -d /var/tmp/steam-arm-client.XXXXXX) || { DL_ERR="could not create a folder in /var/tmp; free some space and run this again"; return 1; }
  CLEANUP+=("$STAGE")
  curl -fsSL --proto =https --proto-redir =https -o "$STAGE/manifest" "$1" || { DL_ERR="client manifest download failed ($1). $NETHINT"; return 1; }
  PKG_VER=$(awk '$1 == "\"version\"" { gsub(/"/, "", $2); print $2; exit }' "$STAGE/manifest")
  ENTRY=$(grep -aoE "\"$2\\.zip\\.[0-9a-f]+" "$STAGE/manifest" | head -1 | tr -d '"')
  [ -n "$ENTRY" ] || { DL_ERR="Valve's client manifest has no $2 package entry (Valve may have renamed it). Run this again later; if it persists, report it."; return 1; }
  # Manifest entry: "sha2" = sha256 of the zip; the name ends in its sha1.
  DL_SHA2=$(awk -v k="\"$2\"" '$1 == k {b = 1} b && $1 == "\"sha2\"" {gsub(/"/, "", $2); print $2; exit} b && /^[[:space:]]*}/ {exit}' "$STAGE/manifest")
}
# Package $ENTRY of the last client_manifest into $STAGE/client.zip, checksum checked.
client_pkg(){
  local csum want
  echo "  package $ENTRY"
  env "${CURL_ENV[@]}" curl -fL --proto =https --proto-redir =https "${CURL_SHOW[@]}" -o "$STAGE/client.zip" "$CDN/$ENTRY" \
    || { DL_ERR="client package download failed ($CDN/$ENTRY). $NETHINT"; return 1; }
  if [ "${#DL_SHA2}" = 64 ]; then csum=$(sha256sum "$STAGE/client.zip" | cut -c1-64); want=$DL_SHA2
  else csum=$(sha1sum "$STAGE/client.zip" | cut -c1-40); want=${ENTRY##*.}; fi
  [ "$csum" = "$want" ] || { DL_ERR="client package does not match the checksum in Valve's manifest (download damaged or cut short). Run this again."; return 1; }
  chmod 711 "$STAGE"; chmod 644 "$STAGE/client.zip"
}
# Native client on this CPU: newest linuxarm64 package scanned for Armv8.1 atomics; on Armv8.0 a clean scan
# also starts its client once (as game account). Sets PROBE (ok, lse or err) and PKG_VER.
# $1 = earlier result VER:ok|lse: same manifest version reuses it (PROBE_OLD=1), no package download.
native_probe(){
  local r run=()
  PROBE=err; PROBE_OLD=0
  [ -f "$X86PY" ] || { DL_ERR="$X86PY missing (run setup first)"; return 1; }
  client_manifest "$MANIFEST" bins_linuxarm64_linuxarm64 || return 1
  case "${1:-}" in "$PKG_VER:ok"|"$PKG_VER:lse") PROBE=${1##*:}; PROBE_OLD=1; return 0;; esac
  client_pkg || return 1
  cpu_lse || run=(--run)
  if [ "$(id -u)" = 0 ] && id "$GAMEUSER" >/dev/null 2>&1; then
    r=$(as_user python3 "$X86PY" probe "$STAGE/client.zip" "${run[@]}" 2>&1 | tail -1)
  else
    r=$(python3 "$X86PY" probe "$STAGE/client.zip" "${run[@]}" 2>&1 | tail -1)
  fi
  case "$r" in ok|lse) PROBE=$r;; *) DL_ERR=${r:-no result}; return 1;; esac
}
# --client-check: result only; recorded as CLIENT_PROBE when settings file is writable (menu: last checked).
probe_save(){ [ -n "${CONF:-}" ] && [ -w "$CONF" ] && [ -w "${CONF%/*}" ] && conf_set CLIENT_PROBE "$1"; return 0; }
client_check(){
  NETHINT="Check the network connection, then run this again."
  # Armv8.1 CPU runs any build: manifest version only, no package download
  if cpu_lse; then
    if ! client_manifest "$MANIFEST" bins_linuxarm64_linuxarm64; then echo "native client: check failed ($DL_ERR)"; return 2; fi
    probe_save "$PKG_VER:ok"
    echo "native client: runs on this CPU (client $PKG_VER)"; return 0
  fi
  if ! native_probe; then echo "native client: check failed ($DL_ERR)"; return 2; fi
  probe_save "$PKG_VER:$PROBE"
  if [ "$PROBE" = ok ]; then echo "native client: runs on this CPU (client $PKG_VER)"; return 0; fi
  echo "native client: still needs Armv8.1 (client $PKG_VER, steam-for-linux #13288)"; return 1
}
# Other variant of this installer: its launcher reads its own settings path.
OTHER_CONF=/etc/h96/steam-arm.conf
other_variant(){ grep -qs "$OTHER_CONF" /usr/local/bin/steam-arm; }
MODE=ask; REPLACE_OTHER=0; PURGE=0; HELP=0; PASS_STDIN=0; ARGC=$#; CLIENT_CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --detect-other) if other_variant; then echo "other variant: present"; exit 0; fi; echo "other variant: none"; exit 1;;
    --remove)   MODE=remove;;
    --purge)    PURGE=1;;
    --password-stdin) PASS_STDIN=1;;
    --defaults) MODE=defaults;;
    --keep)     MODE=keep;;
    --replace-other) REPLACE_OTHER=1;;
    --provider-default) PROVIDER_DEFAULT=1;;
    --select)   MODE=select; SEL="${2:-}"; shift;;
    --select=*) MODE=select; SEL="${1#*=}";;
    --skip)     MODE=skip; SEL="${2:-}"; shift;;
    --skip=*)   MODE=skip; SEL="${1#*=}";;
    --detect)   MODE=detect;;
    --client)   OPT_CLIENT="${2:-}"; shift;;
    --client=*) OPT_CLIENT="${1#*=}";;
    --client-check) CLIENT_CHECK=1;;
    --list)     for c in $COMPONENTS; do printf '  %-16s %s\n' "$c" "$(desc_of "$c")"; done; exit 0;;
    -h|--help)  HELP=1; break;;
    *) die "unknown option: $1 (see --help)";;
  esac; shift
done
if [ "$PURGE" = 1 ] && [ "$MODE" != remove ]; then die "--purge works only together with --remove (see --help)"; fi
case "$OPT_CLIENT" in ""|auto|arm64|x86) ;; *) die "--client takes auto, arm64 or x86 (see --help)";; esac
# Debian or Ubuntu family on 64-bit ARM (apt tools, dpkg architecture arm64): checked before any change; --help and --detect run anywhere.
platform_gap(){
  local c a
  for c in apt-get apt-cache dpkg; do command -v "$c" >/dev/null 2>&1 || { echo "no $c"; return; }; done
  a=$(dpkg --print-architecture 2>/dev/null)
  [ "$a" = arm64 ] || echo "package architecture ${a:-unknown}"
}
if [ "$HELP" = 0 ] && [ "$MODE" != detect ]; then
  PGAP=$(platform_gap)
  [ -z "$PGAP" ] || die "Steam ARM needs a Debian or Ubuntu family distribution on 64-bit ARM (apt, dpkg, arm64).
       This system: $(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"' | grep . || echo unknown), $(uname -m), $PGAP. No change made."
fi
# Custom driver archive: only a local file with its sha256; downloads are always the published archive.
if [ -n "${STEAM_ARM_PROVIDER_SHA256:-}" ] && [ "$MODE" != remove ] && [ "$HELP" = 0 ]; then
  [ -n "${STEAM_ARM_PROVIDER_TARBALL:-}" ] || die "STEAM_ARM_PROVIDER_SHA256 works only together with STEAM_ARM_PROVIDER_TARBALL=/path/to/file (a custom driver archive on this computer). Downloads are always the published archive."
  [ "$PROVIDER_DEFAULT" = 0 ] || die "--provider-default and STEAM_ARM_PROVIDER_SHA256 contradict each other. Pass one of them."
  [[ "$STEAM_ARM_PROVIDER_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "STEAM_ARM_PROVIDER_SHA256 must be the 64-character sha256 of the archive (sha256sum prints it)."
  STEAM_ARM_PROVIDER_SHA256=$(printf '%s' "$STEAM_ARM_PROVIDER_SHA256" | tr 'A-F' 'a-f')
fi
# Custom archive path is saved in the settings file, which the launcher reads as shell.
if [ -n "${STEAM_ARM_PROVIDER_TARBALL:-}" ] && [ "$MODE" != remove ] && [ "$HELP" = 0 ] && [ "$PROVIDER_DEFAULT" = 0 ] \
   && [ -n "${STEAM_ARM_PROVIDER_SHA256:-}$(conf_get PROVIDER_CUSTOM_SHA256)" ]; then
  case "$(readlink -f -- "$STEAM_ARM_PROVIDER_TARBALL" 2>/dev/null)" in
    *[!A-Za-z0-9._/+-]*) die "STEAM_ARM_PROVIDER_TARBALL path may hold only letters, digits and . _ - + / (setup saves it). Move or rename the file, then run this again.";;
  esac
fi
if [ "$PASS_STDIN" = 1 ]; then
  IFS= read -r GAMEPASS || true
  [ -n "$GAMEPASS" ] || die "--password-stdin: no password on standard input. Pass it as first line, or leave the option out (setup then makes one)."
fi
# Replacing other variant: its client folder, and its account unless one is given, stay in use when neither is set here.
if [ "$REPLACE_OTHER" = 1 ] && [ "$MODE" != remove ] && [ -z "$ARMHOME_ENV" ] && [ -z "$(conf_get ARMHOME_DIR)" ] && other_variant; then
  o_u=$(sed -n 's/^GAMEUSER=//p' "$OTHER_CONF" 2>/dev/null | tail -1)
  o_d=$(sed -n 's/^ARMHOME_DIR=//p' "$OTHER_CONF" 2>/dev/null | tail -1); o_d=${o_d%/}
  if [ -z "$GAMEUSER_ENV" ] && [ -z "$(conf_get GAMEUSER)" ] && [ -n "$o_u" ] && getent passwd "$o_u" >/dev/null 2>&1 \
     && [ "$(id -u "$o_u" 2>/dev/null)" != 0 ]; then GAMEUSER=$o_u; fi
  o_h=$(getent passwd "$GAMEUSER" 2>/dev/null | cut -d: -f6)
  if armhome_ok "${o_d:=.local/share/h96-steam-arm}" && [ -n "$o_h" ] && [ -d "$o_h/$o_d/.local/share/Steam" ]; then
    ARMHOME_DIR=$o_d
    echo "  client folder of other variant stays in use: $o_h/$o_d"
  fi
fi
# No options in a terminal: settings menu, with this script as its installer; embedded copy when the installed one differs.
if [ "$ARGC" = 0 ] && [ -t 0 ] && [ -t 1 ]; then
  SELF=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)
  if [ -f "$SELF" ]; then
    MENU=/usr/local/bin/steam-arm-config
    if [ ! -f "$MENU" ] || ! menu_app | cmp -s - "$MENU"; then
      MENU=$(mktemp "${SA_TMP:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}}/steam-arm-config.XXXXXX") || die "could not create a temporary file; free some space and run this again"
      CLEANUP+=("$MENU"); menu_app > "$MENU"
    fi
    STEAM_ARM_INSTALLER=$SELF bash "$MENU"
    exit $?
  fi
fi
[ "$MODE" = remove ] || gpu_pick
[ "$HELP" = 1 ] && { usage; exit 0; }
GPU_VK=""
[ "$MODE" = remove ] || { gpu_vulkan; gpu_line; }
[ "$MODE" = detect ] && { gpu_report; exit 0; }
[ "$CLIENT_CHECK" = 1 ] && { client_check; exit $?; }
# Client type (CPU, option or saved choice): before any package change.
if [ "$MODE" != remove ]; then
  client_pick
  if [ "$CLIENT" = x86 ]; then
    if cpu_lse; then warn "x86 client chosen by hand (--client=x86): runs through emulation, slower than native client."
    else warn "$(x86_warn)"; fi
    mem_gate
  elif ! cpu_lse; then
    warn "$ARMV80_NATIVE_WARN"
  fi
fi
if [ "$MODE" != remove ]; then
  echo "  $GPU_LINE"
  [ "$GPU_SRC" = user ] && echo "  GPU family: $GPU_FAMILY (set by user)"
  [ -n "$GPU_NOTE" ] && echo "  $GPU_NOTE"
  [ -n "$GPU_WARN" ] && warn "$GPU_WARN"
  kde_wayland && echo "  $KDE_HINT"
  armhome_ok "$ARMHOME_DIR" || die "$ARMHOME_BAD"
fi
# Account name: plain characters only (it reaches runuser and su), never the administrator account.
case "$GAMEUSER" in -*|*[!A-Za-z0-9._@-]*) die "GAMEUSER='$GAMEUSER' is not a usable account name (letters, digits, '.', '_', '@', '-'). Set GAMEUSER=name, then run this again.";; esac
[ "$(id -u "$GAMEUSER" 2>/dev/null)" = 0 ] && die "GAMEUSER=$GAMEUSER is the administrator account. Steam ARM runs in a normal desktop account; set GAMEUSER=name, then run this again."
# One setup run at a time, install or removal.
if [ "$(id -u)" = 0 ]; then
  { exec 8>/run/steam-arm-setup.lock && flock -n 8; } 2>/dev/null \
    || die "another steam-arm-setup run is in progress. Wait for it to finish, then run this again."
fi
known(){ for c in $COMPONENTS_ALL; do [ "$c" = "$1" ] && return 0; done; return 1; }
# Component whose files are in place (install from before selection was saved in $CONF).
installed(){ case "$1" in
  glx-lax)    [ -e /usr/local/sbin/steam-arm-glx-lax ];;
  vk-spoof)   [ -e /usr/share/vulkan/implicit_layer.d/VkLayer_steam_arm_spoof.json ];;
  gpu-in-emulation) [ -f "$MALI_MARK" ] || [ -f "$PSTATE/provider.sha256" ];;
  physx-skip) return 0;;  # fix: on unless turned off
  map-count)  [ -e /etc/sysctl.d/zz-steam-arm.conf ];;
  xpad-dedup) [ -e /etc/udev/rules.d/71-steam-arm-xpad-dedup.rules ];;
  pad-hidraw) [ -e /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules ];;
  pad-xbox)   [ -e /etc/systemd/system/steam-arm-pad-xbox.service ];;
  desktop)    [ -e /usr/share/applications/steam-arm.desktop ];;
  desktop-mode) [ -e /usr/share/applications/steam-arm-desktop.desktop ];;
  icon-bigpicture) [ -e "$2/Desktop/Steam ARM.desktop" ];;
  icon-desktop) [ -e "$2/Desktop/Steam ARM (Desktop mode).desktop" ];;
  tray)       [ -e /usr/local/bin/steam-arm-tray ];;
  kde-input-prompt) [ -f "$2/$KDE_MARK" ];;
  page-size)  grep -qs '^# steam-arm-setup page-size:' /boot/firmware/config.txt /boot/config.txt;;
  *)          return 1;;
esac; }
# Selection of last run: COMPONENTS_ON and COMPONENTS_OFF in $CONF, else read from files of
# earlier install. Component in neither list (new in this version) keeps its default.
# Status 1 when there is no earlier run.
prior_selection(){
  local c on= off= uh
  if grep -q '^COMPONENTS_ON=' "$CONF" 2>/dev/null; then
    on=$(conf_get COMPONENTS_ON); off=$(conf_get COMPONENTS_OFF)
  elif [ -f "$CONF" ] && [ -x /usr/local/bin/steam-arm ]; then
    uh=$(getent passwd "$GAMEUSER" | cut -d: -f6)
    for c in $COMPONENTS; do if installed "$c" "$uh"; then on="$on,$c"; else off="$off,$c"; fi; done
  else
    return 1
  fi
  for c in $(echo "$on" | tr ',' ' '); do known "$c" && eval "$(var_of "$c")=1"; done
  for c in $(echo "$off" | tr ',' ' '); do known "$c" && eval "$(var_of "$c")=0"; done
  return 0
}
opt(){ eval "[ \"\$$(var_of "$1")\" = 1 ]"; }
# GPU components follow the GPU family unless set by hand: COMPONENTS_USER_SET lists those, COMPONENTS_FAMILY the family last applied.
GPU_COMPS="vk-spoof gpu-in-emulation glx-lax"
USER_SET=",$(conf_get COMPONENTS_USER_SET),"
# Family changed since last run: family defaults again for GPU components not set by hand; family not saved (older setup): only turns them off.
family_reapply(){
  local prev c v d1 d2 d3
  prev=$(conf_get COMPONENTS_FAMILY)
  [ "$prev" = "$GPU_FAMILY" ] && return 0
  read -r d1 d2 d3 <<< "$GPU_DEF"
  for c in $GPU_COMPS; do
    case "$USER_SET" in *",$c,"*) continue;; esac
    case "$c" in vk-spoof) v=$d1;; gpu-in-emulation) v=$d2;; *) v=$d3;; esac
    [ -z "$prev" ] && [ "$v" = 1 ] && continue
    eval "$(var_of "$c")=$v"
  done
}
gpu_state(){ local c; for c in $GPU_COMPS; do if opt "$c"; then printf '%s=1 ' "$c"; else printf '%s=0 ' "$c"; fi; done; }
# GPU components whose state differs from $1 (states before the user's choice) count as set by hand.
user_mark(){
  local c v
  for c in $GPU_COMPS; do
    if opt "$c"; then v=1; else v=0; fi
    case " $1 " in *" $c=$v "*) ;; *) case "$USER_SET" in *",$c,"*) ;; *) USER_SET="$USER_SET$c,";; esac;; esac
  done
}
case "$MODE" in
  select) prior_selection; family_reapply; PRE=$(gpu_state)
          for c in $COMPONENTS; do eval "$(var_of "$c")=0"; done
          for c in $(echo "$SEL" | tr ',' ' '); do known "$c" || die "unknown component: $c"; eval "$(var_of "$c")=1"; done
          user_mark "$PRE";;
  skip)   USER_SET=","
          for c in $(echo "$SEL" | tr ',' ' '); do known "$c" || die "unknown component: $c"; eval "$(var_of "$c")=0"
            case " $GPU_COMPS " in *" $c "*) USER_SET="$USER_SET$c,";; esac; done;;
  defaults) USER_SET=",";;
  keep)   prior_selection; family_reapply;;
  ask)    if prior_selection; then PRIOR=1; else PRIOR=0; fi
          family_reapply; PRE=$(gpu_state)
          if [ -t 0 ] && [ -t 1 ]; then
            # Explain the keyboard-driven picker and its flag alternatives before showing it.
            printf '\n  Components: --defaults takes the recommended set, --select a,b takes exactly\n'
            printf '  those, --skip a,b takes the defaults without them, --list prints them all.\n'
            [ "$PRIOR" = 1 ] && printf '  Checklist starts from selection of last run; --keep reuses it without asking.\n'
            echo
            if command -v whiptail >/dev/null 2>&1; then
              args=(); for c in $COMPONENTS; do
                args+=("$c" "$(desc_of "$c")" "$(eval "[ \"\$$(var_of "$c")\" = 1 ]" && echo ON || echo OFF)")
              done
              chosen=$(whiptail --title "Native ARM64 Steam" --checklist "Optional components.\n$GPU_LINE${GPU_MSG:+\n$GPU_MSG}\n\nSPACE toggles the item under the cursor.  TAB moves to the buttons.  ENTER confirms.\nThis list is keyboard driven; a mouse click does nothing." 30 100 13 "${args[@]}" 3>&1 1>&2 2>&3) || die "cancelled"
              for c in $COMPONENTS; do eval "$(var_of "$c")=0"; done
              for c in $chosen; do c=${c//\"/}; eval "$(var_of "$c")=1"; done
            else
              for c in $COMPONENTS; do
                if eval "[ \"\$$(var_of "$c")\" = 1 ]"; then
                  printf '  %-16s %s [Y/n] ' "$c" "$(desc_of "$c")"; read -r a
                  case "$a" in n|N) eval "$(var_of "$c")=0";; esac
                else
                  printf '  %-16s %s [y/N] ' "$c" "$(desc_of "$c")"; read -r a
                  case "$a" in y|Y) eval "$(var_of "$c")=1";; esac
                fi
              done
            fi
          elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1 \
               && ! { : </dev/tty; } 2>/dev/null; then
            # No controlling terminal but graphical session: same checklist as dialog; no reachable display keeps preset.
            args=(); for c in $COMPONENTS; do
              args+=("$(eval "[ \"\$$(var_of "$c")\" = 1 ]" && echo TRUE || echo FALSE)" "$c" "$(desc_of "$c")")
            done
            zerr=$(mktemp); rc=0
            chosen=$(zenity --list --checklist --title="Native ARM64 Steam" --text="Optional components\n$GPU_LINE${GPU_MSG:+\n$GPU_MSG}"\
              --column="Install" --column="Component" --column="Description" --print-column=2 --separator=' ' \
              --width=900 --height=560 "${args[@]}" 2>"$zerr") || rc=$?
            if [ "$rc" = 0 ]; then
              for c in $COMPONENTS; do eval "$(var_of "$c")=0"; done
              for c in $chosen; do known "$c" && eval "$(var_of "$c")=1"; done
            elif [ "$rc" = 1 ] && ! grep -qiE '(cannot|failed to|unable to) open display' "$zerr"; then
              rm -f "$zerr"; die "cancelled"
            else
              warn "component dialog failed (status $rc); using preset selection"
            fi
            rm -f "$zerr"
          fi
          user_mark "$PRE";;
esac
# page-size has no effect here (no Raspberry Pi 5): always off. Same for kde-input-prompt without KDE Plasma.
ps_relevant || eval "$(var_of page-size)=0"
kde_relevant || eval "$(var_of kde-input-prompt)=0"

# Detect other installer variant (by its launcher's settings path); refuse unless --replace-other, which retires it.
RETIRE_OTHER=0
if other_variant; then
  [ "$REPLACE_OTHER" = 1 ] || die "/usr/local/bin/steam-arm belongs to other variant of this installer.
       Both variants write steam-arm and steamos-session-select.
       Pass --replace-other to retire it first: its files go into one backup archive in
       /var/backups, then this variant installs (with --remove: this variant is removed too)."
  RETIRE_OTHER=1
fi

# --- page size ---
# Emulation needs 4K pages; Pi's page-size component selects its 4K kernel, elsewhere this stops with the fix.
PAGESIZE=$(getconf PAGESIZE 2>/dev/null || echo 4096)
# Override from the environment, else the one an earlier run kept in the settings file.
PS_IGNORE=${STEAM_ARM_IGNORE_PAGESIZE:-$(conf_get STEAM_ARM_IGNORE_PAGESIZE)}
MODEL=$( { tr -d '\0' < /proc/device-tree/model; } 2>/dev/null)
FWDIR=/boot/firmware
[ -f "$FWDIR/config.txt" ] || { [ -f /boot/config.txt ] && FWDIR=/boot; }
FWCFG="$FWDIR/config.txt"
PS_BEGIN="# steam-arm-setup page-size: 4K page kernel for x86 emulation. Remove this block to undo."
PS_END="# end steam-arm-setup page-size"
# Banner line: page size in use, board default where setup switches it, what happens next.
case "$PAGESIZE" in 4096) PS_NOW=4K;; 16384) PS_NOW=16K;; 65536) PS_NOW=64K;; *) PS_NOW="$PAGESIZE bytes";; esac
if [ "$PAGESIZE" = 4096 ]; then
  if grep -qs "^$PS_BEGIN" "$FWCFG"; then PS_LINE="Page size: 4K from setup's kernel switch (board default 16K; uninstall restores it)"
  else PS_LINE="Page size: 4K, as x86 emulation needs"; fi
elif grep -qs "^$PS_BEGIN" "$FWCFG"; then PS_LINE="Page size: $PS_NOW now; 4K kernel set in $FWCFG, starts after reboot"
else
  case "$MODEL" in
    "Raspberry Pi"*) PS_LINE="Page size: $PS_NOW (board default); x86 emulation needs 4K, page-size component switches it";;
    *) PS_LINE="Page size: $PS_NOW; x86 emulation needs 4K";;
  esac
fi
is_pi(){ case "$MODEL" in "Raspberry Pi"*) [ -f "$FWCFG" ];; *) return 1;; esac; }
ps_block(){ [ -f "$FWCFG" ] && grep -qxF "$PS_BEGIN" "$FWCFG"; }
# Block out of $FWCFG through a new file renamed over it (power loss never leaves it half written); backup goes after.
ps_remove(){
  local t; t=$(mktemp "$FWDIR/.config.txt.XXXXXX") || return 1
  if awk -v b="$PS_BEGIN" -v e="$PS_END" '$0==b{s=1} !s{print} $0==e{s=0}' "$FWCFG" > "$t" \
     && { chmod --reference="$FWCFG" "$t" 2>/dev/null; sync "$t" 2>/dev/null; true; } && mv -f "$t" "$FWCFG"; then
    rm -f "$FWCFG.steam-arm.bak"; return 0
  fi
  rm -f "$t"; return 1
}

# Retire other variant of this installer: its files into one tar in /var/backups (paths kept), then deleted.
retire_other(){
  local ou oh oad tar utar f u kwin_copy list=() keep=() rel=() urel=() en=()
  client_pids >/dev/null && die "a Steam client is running. Close it first (exit from its menu, Stop Steam in the tray, or steam-arm --shutdown as its account), then run this again."
  ou=$(sed -n 's/^GAMEUSER=//p' "/etc/h96/steam-arm.conf" 2>/dev/null | tail -1)
  getent passwd "$ou" >/dev/null 2>&1 || ou=$GAMEUSER
  oh=$(getent passwd "$ou" 2>/dev/null | cut -d: -f6)
  oad=$(sed -n 's/^ARMHOME_DIR=//p' "/etc/h96/steam-arm.conf" 2>/dev/null | tail -1)
  case "${oad:=.local/share/h96-steam-arm}" in /*|*..*) oad=.local/share/h96-steam-arm;; esac
  say "retiring other variant of this installer"
  pkill -TERM -f /usr/local/bin/h96-steam-tray 2>/dev/null
  for u in h96-pad-xbox h96-fex-binfmt; do
    [ -f "/etc/systemd/system/$u.service" ] || continue
    systemctl is-enabled --quiet "$u" 2>/dev/null && en+=("$u")
    systemctl disable --now "$u" >/dev/null 2>&1
  done
  for f in /usr/local/bin/steam-arm /usr/local/bin/steamos-session-select \
           /usr/local/bin/h96-steam-remoteplay /usr/local/bin/h96-steam-arm-compatmap /usr/local/bin/h96-steam-arm-icon \
           /usr/local/bin/h96-steam-tray \
           /usr/local/lib/h96-steam-handler.py /usr/local/lib/h96-steam-fexpatch.py /usr/local/lib/h96-steam-compatmap.py \
           /usr/local/lib/h96-glx-lax-patch.py /usr/local/lib/h96-glx-lax.src /usr/local/lib/h96-vk-spoof.c \
           /usr/local/sbin/h96-glx-lax /usr/local/sbin/h96-xpad-dedup /usr/local/sbin/h96-pad-xbox \
           /usr/lib/aarch64-linux-gnu/libGLX_h96lax.so.0 /usr/lib/aarch64-linux-gnu/libVkLayer_h96_spoof.so \
           /usr/share/vulkan/implicit_layer.d/VkLayer_h96_spoof.json \
           /etc/udev/rules.d/71-h96-xpad-dedup.rules /etc/udev/rules.d/60-h96-gamepad-hidraw.rules \
           /etc/sysctl.d/zz-h96-steam.conf /etc/sysctl.d/99-h96-steam.conf \
           /etc/systemd/system/h96-fex-binfmt.service /etc/systemd/system/h96-pad-xbox.service \
           /etc/sudoers.d/h96-steam-arm \
           /usr/share/applications/h96-steam-arm.desktop /usr/share/applications/h96-steam-arm-desktop.desktop \
           /usr/local/share/h96/titles.conf /etc/h96/titles.conf /etc/h96/steam-arm.conf \
           /usr/share/icons/hicolor/*/apps/h96-steam-arm.png /usr/share/icons/hicolor/*/apps/steam-arm-desktop.png; do
    { [ -e "$f" ] || [ -L "$f" ]; } && list+=("$f")
  done
  if [ -n "$oh" ]; then
    for f in "$oh/.config/autostart/h96-steam-tray.desktop" \
             "$oh"/.local/share/icons/hicolor/*/apps/h96-steam-arm.png \
             "$oh"/.local/share/icons/hicolor/*/apps/steam-arm-desktop.png \
             "$oh/$oad/.local/share/vulkan/implicit_layer.d/steamoverlay_arm64_h96.json"; do
      { [ -e "$f" ] || [ -L "$f" ]; } && list+=("$f")
    done
    # same overlay registration in this installer's client home, when that is another folder
    f="$oh/$ARMHOME_DIR/.local/share/vulkan/implicit_layer.d/steamoverlay_arm64_h96.json"
    [ "$ARMHOME_DIR" != "$oad" ] && [ -f "$f" ] && list+=("$f")
    # files this setup overwrites later: copied into backup, left in place
    for f in "$oh/.fex-emu/Config.json" "$oh/$oad/.fex-emu/Config.json" "$oh"/Desktop/*[Ss]team*ARM*.desktop; do
      [ -f "$f" ] && keep+=("$f")
    done
  fi
  [ -f "$RFS/graphics_provider.json" ] && keep+=("$RFS/graphics_provider.json")
  # copy of window rules before the other variant's rule group leaves them
  [ -n "$oh" ] && [ -f "$oh/.config/kwinrulesrc" ] && grep -qx '\[h96-steam-arm-frame\]' "$oh/.config/kwinrulesrc" \
    && kwin_copy="$oh/.config/kwinrulesrc" || kwin_copy=
  # files in the old account's home go into its own archive, read and restored by that account
  for f in "${list[@]}" "${keep[@]}" ${kwin_copy:+"$kwin_copy"}; do
    case "$f" in "${oh:-//}"/*) urel+=("${f#/}");; *) rel+=("${f#/}");; esac
  done
  tar="/var/backups/steam-arm-replaced-$(date +%Y%m%d-%H%M%S).tar"
  [ -e "$tar" ] && tar="${tar%.tar}-$$.tar"   # never overwrite an earlier backup
  utar="${tar%.tar}-$ou.tar"
  if [ ${#rel[@]} -gt 0 ] || [ ${#urel[@]} -gt 0 ]; then
    mkdir -p /var/backups || die "could not create /var/backups; nothing removed. Free some space and run this again."
    if [ ${#rel[@]} -gt 0 ]; then
      tar -cpf "$tar" -C / "${rel[@]}" || die "could not write backup $tar; nothing removed. Free some space and run this again."
      chmod 600 "$tar"
    fi
    if [ ${#urel[@]} -gt 0 ]; then
      { as_acct "$ou" env -u TMPDIR tar -cpf - -C / "${urel[@]}" > "$utar" && chown "$ou" "$utar" && chmod 600 "$utar"; } \
        || { rm -f "$utar"; die "could not write backup $utar; nothing removed. Free some space and run this again."; }
    fi
    for f in "${list[@]}"; do case "$f" in "${oh:-//}"/*) as_acct "$ou" env -u TMPDIR rm -f "$f";; *) rm -f "$f";; esac; done
  fi
  rmdir "/etc/h96" "/usr/local/share/h96" 2>/dev/null
  [ -n "$kwin_copy" ] && GAMEUSER="$ou" kwin_rule_remove h96-steam-arm-frame
  systemctl daemon-reload 2>/dev/null
  udevadm control --reload 2>/dev/null
  sysctl -q --system >/dev/null 2>&1
  ldconfig 2>/dev/null
  if [ ${#rel[@]} -gt 0 ] || [ ${#urel[@]} -gt 0 ]; then
    echo "  other variant of this installer retired; backup:${rel[0]:+ $tar}${urel[0]:+ $utar}"
    echo "  to go back, run in this order:"
    echo "    sudo bash steam-arm-install.sh --remove"
    [ ${#rel[@]} -gt 0 ] && echo "    sudo tar -xpf $tar -C /"
    [ ${#urel[@]} -gt 0 ] && echo "    sudo -u $ou tar -xpf $utar -C /"
    echo "    sudo systemctl daemon-reload; sudo udevadm control --reload"
    for u in "${en[@]}"; do echo "    sudo systemctl enable --now $u"; done
    for f in "${list[@]}"; do case "$f" in /etc/sysctl.d/*) echo "    sudo sysctl -p $f";; esac; done
  else echo "  other variant of this installer retired; no files left to back up"; fi
  return 0
}

# kde-input-prompt helper as the game account in its desktop session; 75 when no session bus is up.
KDE_PS_CALL="org.freedesktop.impl.portal.PermissionStore /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore"
kde_input(){
  local u; u=$(id -u "$GAMEUSER" 2>/dev/null) || return 1
  [ -x /usr/local/lib/steam-arm-kde-input ] || return 1
  [ -S "/run/user/$u/bus" ] || return 75
  as_user env XDG_RUNTIME_DIR="/run/user/$u" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$u/bus" \
    /usr/local/lib/steam-arm-kde-input "$1"
}
# Real mangohud (no shim marker) in PATH or /usr/bin, /bin.
mh_real(){
  local d; local IFS=:
  for d in $PATH /usr/bin /bin; do
    [ -x "$d/mangohud" ] && ! grep -qsF "$MH_MARK" "$d/mangohud" && return 0
  done
  return 1
}
# Shim written only where no real mangohud exists; own shim refreshed, or removed once a real one is installed.
mh_shim(){
  if mh_real; then
    grep -qsF "$MH_MARK" "$MH_SHIM" && rm -f "$MH_SHIM"
    return 0
  fi
  { [ -e "$MH_SHIM" ] || [ -L "$MH_SHIM" ]; } && ! grep -qsF "$MH_MARK" "$MH_SHIM" && return 0
  mkdir -p "$(dirname "$MH_SHIM")" && cat > "$MH_SHIM" <<MHSHIM && chmod 755 "$MH_SHIM"
#!/bin/sh
$MH_MARK: MANGOHUD=1 for the launch handler, which loads MangoHud of the x86 RootFS.
[ -x /usr/bin/mangohud ] && exec /usr/bin/mangohud "\$@"
MANGOHUD=1 exec "\$@"
MHSHIM
}
# --- uninstall (--remove): everything this installer added; client folder only on typed request ---
remove_all(){
  local uh="" armhome="" del=0 a gone_client=0 gone_rfs=0 gone_mali=0 restored="" pkgs p binfmt=0 other=0 gp_rm=0 fc_rm=0 kept="" ft
  local linger made_acct tb="" d fstab_added rfs_made rfs_del=0 nomark=0 fstab_kept=0 foreign ge="" x
  [ "$(id -u)" = 0 ] || die "run as root: sudo bash steam-arm-install.sh --remove"
  getent passwd "$GAMEUSER" >/dev/null 2>&1 && uh=$(getent passwd "$GAMEUSER" | cut -d: -f6)
  client_pids >/dev/null && die "a Steam client is running. Close it first (exit from its menu, Stop Steam in the tray, or steam-arm --shutdown as its account), then run this again."
  if armhome_ok "$ARMHOME_DIR"; then [ -n "$uh" ] && armhome="$uh/$ARMHOME_DIR"
  else warn "$ARMHOME_BAD"; warn "client folder is not touched by this removal"; fi
  linger=$(conf_get LINGER_SET); made_acct=$(conf_get ACCOUNT_CREATED)
  fstab_added=$(conf_get FSTAB_ADDED); rfs_made=$(conf_get RFS_CREATED); foreign=$(conf_get ARMHOME_FOREIGN)
  grep -qs '^downloaded by steam-arm-setup' "$RFS/.steam-arm-rootfs" && rfs_made=1
  steam_banner "Steam ARM $SA_VERSION: native ARM64 Steam client removal" "Removes what setup added; installed games stay unless asked" "$PS_LINE"
  [ "$RETIRE_OTHER" = 1 ] && retire_other
  # Shared files go only while unchanged since setup wrote them, and never while other variant is installed.
  [ -f /etc/h96/steam-arm.conf ] && other=1
  if [ "$other" = 0 ] && [ -f "$OWNED" ]; then
    own_ok "$RFS/graphics_provider.json" && gp_rm=1
    [ -n "$uh" ] && own_ok "$uh/.fex-emu/Config.json" && fc_rm=1
  elif [ "$other" = 0 ]; then
    # setup from before ownership records: list form and RootFS line identify its files
    [ "$(cat "$RFS/graphics_provider.json" 2>/dev/null)" = "$(gp_list_json)" ] && gp_rm=1
    [ -n "$uh" ] && grep -qs "\"RootFS\":\"$RFS\"" "$uh/.fex-emu/Config.json" && fc_rm=1
  fi
  say "services"
  [ -f /etc/systemd/system/steam-arm-fex-binfmt.service ] && binfmt=1
  for p in steam-arm-pad-xbox steam-arm-fex-binfmt; do
    systemctl disable --now "$p" >/dev/null 2>&1; rm -f "/etc/systemd/system/$p.service"
  done
  systemctl daemon-reload 2>/dev/null
  pkill -TERM -f /usr/local/bin/steam-arm-tray 2>/dev/null
  if [ "$linger" = 1 ] && [ -n "$uh" ]; then
    loginctl disable-linger "$GAMEUSER" >/dev/null 2>&1 && restored="${restored:+$restored, }user services of $GAMEUSER stop at logout again"
  fi
  say "kernel limit"
  if [ -f "$MC" ]; then mc_restore ""; restored="${restored:+$restored, }vm.max_map_count"; else echo "  vm.max_map_count was not changed"; fi
  # Valve's emulation tool back to its original lines; needs the patch helper, so before it goes.
  ft="$armhome/.local/share/Steam/steamapps/common/FEX-Emu"
  if [ -n "$armhome" ] && [ -d "$ft" ] && [ -f /usr/local/lib/steam-arm-fexpatch.py ]; then
    say "emulation tool"
    if as_user python3 /usr/local/lib/steam-arm-fexpatch.py --unpatch "$ft"; then
      echo "  Valve's emulation tool files put back (exact files again at Steam's next update of the tool)"
    else
      warn "Valve's emulation tool files could not be put back; Steam restores them at its next update"
    fi
  fi
  # GE-Proton builds from settings menu (marked folders only); needs helper and compatmap, so before they go
  if [ -n "$armhome" ] && [ -f /usr/local/lib/steam-arm-geproton.py ] && [ -d "$armhome/.local/share/Steam/compatibilitytools.d" ]; then
    say "GE-Proton"
    ge=$(as_user python3 /usr/local/lib/steam-arm-geproton.py remove-all "$armhome/.local/share/Steam") \
      || warn "GE-Proton builds could not all be removed; see lines above"
  fi
  # x86 client edits in a client folder that stays (launch wrapper, webhelper script, FEX app settings); helper goes below
  if [ -n "$armhome" ] && [ -f /usr/local/lib/steam-arm-x86client.py ] && [ -d "$armhome/.local/share/Steam" ]; then
    x=$(as_user python3 /usr/local/lib/steam-arm-x86client.py restore "$armhome/.local/share/Steam" "$armhome") \
      && [ -n "$x" ] && restored="${restored:+$restored, }$x"
  fi
  if [ -n "$uh" ] && [ -f "$uh/$KDE_MARK" ]; then
    say "KDE input prompt"
    if kde_input off; then restored="${restored:+$restored, }KDE input prompt for X11 programs"
    else
      warn "KDE input permission stays until reversed: log in to desktop, then run as $GAMEUSER:"
      warn "  busctl --user call $KDE_PS_CALL DeletePermission sss kde-authorized remote-desktop \"\""
    fi
  fi
  say "programs, rules, menu entries, settings"
  # Profiles written by hand or by steam-arm-config: saved before /etc/steam-arm goes.
  if grep -qsv -e '^[[:space:]]*#' -e '^[[:space:]]*$' /etc/steam-arm/titles.conf; then
    tb="/var/backups/steam-arm-titles-$(date +%Y%m%d-%H%M%S).conf"
    { mkdir -p /var/backups && cp -p /etc/steam-arm/titles.conf "$tb"; } || tb=""
  fi
  rm -f /usr/local/bin/steam-arm /usr/local/bin/steam-arm-remoteplay /usr/local/bin/steam-arm-compatmap \
        /usr/local/bin/steam-arm-icon /usr/local/bin/steam-arm-tray /usr/local/bin/steam-arm-config \
        /usr/local/lib/steam-arm-handler.py /usr/local/lib/steam-arm-fexpatch.py /usr/local/lib/steam-arm-compatmap.py \
        /usr/local/lib/steam-arm-physx.py /usr/local/lib/steam-arm-kde-input \
        /usr/local/lib/steam-arm-autobuild.py /usr/local/lib/steam-arm-appinfo.py /usr/local/lib/steam-arm-geproton.py \
        /usr/local/lib/steam-arm-x86client.py /usr/local/lib/steam-arm-run.py /usr/local/lib/steam-arm-pv-bwrap \
        /usr/local/lib/steam-arm-python3 \
        /usr/local/lib/steam-arm-glx-lax-patch.py /usr/local/lib/steam-arm-glx-lax.src /usr/local/lib/steam-arm-glx-lax.stat \
        /usr/local/lib/steam-arm-vk-spoof.c \
        /usr/local/sbin/steam-arm-glx-lax /usr/local/sbin/steam-arm-xpad-dedup /usr/local/sbin/steam-arm-pad-xbox \
        /usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0 /usr/lib/aarch64-linux-gnu/libVkLayer_steam_arm_spoof.so \
        /usr/share/vulkan/implicit_layer.d/VkLayer_steam_arm_spoof.json \
        /etc/udev/rules.d/71-steam-arm-xpad-dedup.rules /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules \
        /etc/sudoers.d/steam-arm "$GLX_HOOK" \
        /usr/share/applications/steam-arm.desktop /usr/share/applications/steam-arm-desktop.desktop \
        /usr/share/applications/steam-arm-config.desktop \
        /usr/share/icons/hicolor/*/apps/steam-arm.png /usr/share/icons/hicolor/*/apps/steam-arm-desktop.png
  grep -qs "$VALVE_MARK" /etc/udev/rules.d/60-steam-input.rules && rm -f /etc/udev/rules.d/60-steam-input.rules
  grep -qs steam-arm /usr/local/bin/steamos-session-select && rm -f /usr/local/bin/steamos-session-select
  grep -qsF "$MH_MARK" "$MH_SHIM" && rm -f "$MH_SHIM"
  # reads the kwinrulesrc record in /etc/steam-arm
  [ -n "$uh" ] && kwin_rule_remove
  rm -rf /usr/local/share/steam-arm /etc/steam-arm
  rm -rf "$NOPKG"
  if [ -d "$PSTATE" ]; then
    legacy_mesa_restore && { restored="${restored:+$restored, }distro Mesa in $RFS"; [ "$other" = 0 ] && gp_rm=1; }
  fi
  mali_tree_remove && gone_mali=1
  if [ "$gp_rm" = 1 ]; then rm -f "$RFS/graphics_provider.json"
  elif [ -f "$RFS/graphics_provider.json" ]; then kept="$kept $RFS/graphics_provider.json"; fi
  [ "$other" = 0 ] && [ "$(readlink /usr/share/guestos/fex-mesa 2>/dev/null)" = "$RFS" ] && rm -f /usr/share/guestos/fex-mesa
  rmdir /usr/share/guestos 2>/dev/null
  [ "$other" = 0 ] && [ -d "$RFS" ] && rfs_unguard "$RFS" && restored="${restored:+$restored, }package tools in $RFS"
  ldconfig; udevadm control --reload 2>/dev/null
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications 2>/dev/null
  if [ -n "$uh" ]; then
    as_user rm -f "$uh/Desktop/Steam ARM.desktop" "$uh/Desktop/Steam ARM (Desktop mode).desktop" \
          "$uh/.config/autostart/steam-arm-tray.desktop" \
          "$uh"/.local/share/icons/hicolor/*/apps/steam-arm.png "$uh"/.local/share/icons/hicolor/*/apps/steam-arm-desktop.png
    # folder goes with setup's Config.json when nothing else is in it
    if [ "$fc_rm" = 1 ]; then as_user rm -f "$uh/.fex-emu/Config.json"; as_user rmdir "$uh/.fex-emu" 2>/dev/null
    elif [ -f "$uh/.fex-emu/Config.json" ]; then kept="$kept $uh/.fex-emu/Config.json"; fi
    [ -n "$armhome" ] && as_user rm -f "$armhome/.local/share/vulkan/implicit_layer.d/steamoverlay_arm64_steamarm.json"
    # runtime files of tray and launcher (tray stopped above, client not running)
    d=/run/user/$(id -u "$GAMEUSER" 2>/dev/null)
    [ -d "$d" ] && as_user rm -rf "$d/steam-arm-tray" "$d/steam-arm-tray.lock" "$d/steam-arm-start.lock" "$d/steam-arm-warned" \
      "$d/steam-arm-display-mode" "$d/steam-arm-icon-wait-$(id -u "$GAMEUSER").lock" 2>/dev/null
  fi
  # Setup logs and temporary files of the settings menu, for the game account and the account that ran it.
  for p in "$GAMEUSER" "${SUDO_USER:-}"; do
    [ -n "$p" ] && [ "$p" != root ] && d=$(getent passwd "$p" | cut -d: -f6) && [ -n "$d" ] \
      && as_acct "$p" env -u TMPDIR rm -rf "$d/.cache/steam-arm" 2>/dev/null
  done
  rm -rf /root/.cache/steam-arm
  if [ "$fstab_added" = 1 ] && grep -qxF "$FSTAB_LINE" /etc/fstab; then
    if fstab_edit drop; then restored="${restored:+$restored, }/etc/fstab without the /dev/shm line"
    else warn "could not take the /dev/shm line out of /etc/fstab; remove the line '$FSTAB_LINE' by hand"; fi
  elif grep -qxF "$FSTAB_LINE" /etc/fstab 2>/dev/null; then
    # same line from an earlier version (not recorded) or added by hand: stays
    fstab_kept=1
  fi
  if is_pi && ps_block; then
    ps_remove && { restored="${restored:+$restored, }boot kernel line in $FWCFG"
      warn "4K page kernel line removed from $FWCFG; firmware loads its default kernel after next reboot"; }
  fi
  # Valve's streaming client back in place of the launcher's stand-in, for a client folder that stays.
  d="$armhome/.local/share/Steam/steamrtarm64"
  if [ -n "$armhome" ] && [ -f "$d/streaming_client.real" ] && grep -qs 'x86-64 streaming client' "$d/streaming_client"; then
    as_user mv -f "$d/streaming_client.real" "$d/streaming_client" && restored="${restored:+$restored, }Valve's streaming client"
  fi
  # Client folder holds the games: deleted only with setup's marker in it and typed confirmation.
  if [ -n "$armhome" ] && [ -d "$armhome" ]; then
    if [ "$foreign" = 1 ] || [ ! -f "$armhome/.steam-arm-client" ]; then nomark=1
    elif [ "$PURGE" = 1 ]; then del=1
    elif [ -t 0 ]; then
      printf '\n  Client folder %s holds installed games, sign-in and settings.\n  Delete it too? [y/N] ' "$armhome"
      read -r a; case "$a" in y|Y|yes) del=1;; esac
    fi
  fi
  # x86-64 root filesystem: --purge deletes it only when setup downloaded it and the other variant does not use it.
  [ "$PURGE" = 1 ] && [ "$rfs_made" = 1 ] && [ "$other" = 0 ] && [ -d "$RFS" ] && rfs_del=1
  if [ "$del" = 1 ] || [ "$rfs_del" = 1 ]; then
    if [ -t 0 ]; then
      [ "$del" = 1 ] && printf '  This deletes every installed game in %s.\n' "$armhome"
      [ "$rfs_del" = 1 ] && printf '  This deletes the x86-64 root filesystem %s.\n' "$RFS"
      printf '  Type DELETE to confirm: '
      read -r a
    else
      a=; warn "no terminal to confirm; nothing deleted"
    fi
    if [ "$a" = DELETE ]; then
      if [ "$del" = 1 ]; then
        as_user rm -rf "$armhome" && gone_client=1
        [ "$gone_client" = 1 ] || warn "client folder $armhome could not be deleted completely; delete the rest with: sudo rm -rf \"$armhome\""
      fi
      if [ "$rfs_del" = 1 ]; then rm -rf "$RFS" && gone_rfs=1; rmdir /opt/fex-rootfs 2>/dev/null; fi
    else
      echo "  not confirmed; nothing deleted"
    fi
  fi
  pkgs="fex-emu-armv8.0 fex-emu-armv8.2 fex-emu-armv8.4 fex-emu-binfmt32 fex-emu-binfmt64 bubblewrap libsdl3-0 libsdl3-image0 libsdl3-ttf0"
  pkgs="$pkgs libgtk2.0-0t64 libgtk2.0-0 libopenal1 libibus-1.0-5 zenity xdotool patchelf libvulkan-dev python3-pil python3-evdev gir1.2-ayatanaappindicator3-0.1"
  pkgs=$(for p in $pkgs; do dpkg-query -W -f='${Status}\n' "$p" 2>/dev/null | grep -q '^install ok installed' && printf '%s ' "$p"; done)
  # Debian FEX source from setup: goes once no FEX build is installed, else stays for its updates
  local fexsrc=0
  if [ -f "$FEXSRC" ]; then
    case " $pkgs" in *" fex-emu-armv8"*) fexsrc=1;; *) rm -f "$FEXSRC" "$FEXKEY" && fexsrc=2;; esac
  fi
  say "done: Steam ARM removed"
  echo "  Removed:   launcher, helpers, settings menu, menu and desktop entries, icons, controller rules,"
  echo "             services, sudo rule, window rule, apt hook, settings in /etc/steam-arm"
  [ "$gone_mali" = 1 ] && echo "  Removed:   Mali drivers inside emulation ($MALI)"
  [ -n "$ge" ] && echo "  Removed:   GE-Proton builds installed from settings menu: $ge (games set to them go back to Steam's choice: Linux build where game has one, else default Proton)"
  [ "$fexsrc" = 2 ] && echo "  Removed:   FEX package source $FEXSRC and its key $FEXKEY"
  [ -n "$restored" ] && echo "  Restored:  $restored"
  [ -n "$tb" ] && echo "  Saved:     game profiles from /etc/steam-arm/titles.conf in $tb"
  for p in $kept; do
    # file went with the deleted RootFS
    [ "$gone_rfs" = 1 ] && [ "$p" = "$RFS/graphics_provider.json" ] && continue
    echo "  Kept:      $p (changed since setup, or used by other variant of this installer)"
  done
  if [ "$gone_client" = 1 ]; then echo "  Deleted:   client folder $armhome (games included)"
  elif [ "$nomark" = 1 ] && [ "$foreign" = 1 ]; then
    echo "  Kept:      folder $armhome: it held other files before setup, so setup does not delete it."
    echo "             To delete it yourself, check its contents first: rm -rf \"$armhome\""
  elif [ "$nomark" = 1 ]; then
    echo "  Kept:      folder $armhome: it has no Steam ARM client marker, so setup does not delete it."
    echo "             To delete it yourself, check its contents first: rm -rf \"$armhome\""
  elif [ -n "$armhome" ] && [ -d "$armhome" ]; then
    echo "  Kept:      client folder $armhome (installed games, sign-in, settings)."
    echo "             Reinstall picks it up again; to delete it yourself: rm -rf \"$armhome\""
    echo "             FEX code caches stay with games (per-game cache folders that Steam sets)."
  fi
  if [ "$gone_rfs" = 1 ]; then echo "  Deleted:   x86-64 root filesystem $RFS"
  elif [ -d "$RFS" ]; then
    echo "  Kept:      x86-64 root filesystem $RFS; to delete it: sudo rm -rf $RFS"
    [ "$PURGE" = 1 ] && [ "$rfs_del" = 0 ] && echo "             (not downloaded by this setup, or in use by the other variant of this installer)"
  fi
  if [ "$made_acct" = 1 ] && [ -n "$uh" ]; then
    echo "  Kept:      account $GAMEUSER, created by setup. To delete it with its home folder:"
    echo "             sudo userdel -r $GAMEUSER"
    [ -f "/root/steam-arm-password-$GAMEUSER.txt" ] && echo "             its saved password: sudo rm /root/steam-arm-password-$GAMEUSER.txt"
  fi
  echo "  Kept:      account groups (video, render, input, audio)"
  [ "$fstab_kept" = 1 ] && echo "  Kept:      /dev/shm line in /etc/fstab"
  if [ -n "$pkgs" ]; then
    echo "  Packages:  distribution packages stay installed. Remove the ones nothing else on this system"
    echo "             needs with:  sudo apt remove $pkgs"
    if [ "$fexsrc" = 1 ]; then echo "             FEX package source:  sudo rm $FEXSRC $FEXKEY"
    elif os_ubuntu && case " $pkgs" in *" fex-emu-armv8"*) true;; *) false;; esac; then
      echo "             FEX package source:  sudo add-apt-repository --remove $FEXPPA"; fi
  fi
  [ "$binfmt" = 1 ] && echo "  box64 and box32, if installed, handle x86 programs again after next reboot."
  return 0
}
if [ "$MODE" = remove ]; then remove_all; exit 0; fi
# --- host package preflight (read-only), before any package or package source change ---
BUILDPKGS=""; opt vk-spoof && BUILDPKGS="gcc libc6-dev libvulkan-dev"
opt glx-lax && BUILDPKGS="$BUILDPKGS patchelf"
opt gpu-in-emulation && BUILDPKGS="$BUILDPKGS zstd"                                  # driver archive
want_icons(){ opt desktop || opt desktop-mode || opt icon-bigpicture || opt icon-desktop; }
want_icons && BUILDPKGS="$BUILDPKGS python3-pil"                                     # menu and desktop icons
opt tray && BUILDPKGS="$BUILDPKGS gir1.2-ayatanaappindicator3-0.1"                   # tray helper binding
HOSTPKGS="bubblewrap dbus-daemon xz-utils libsdl3-0 libsdl3-image0 libsdl3-ttf0 libgtk2.0-0t64 libopenal1 libibus-1.0-5 zenity xdotool x11-xserver-utils curl python3 file $BUILDPKGS"
HOST_MISS=$(pkg_missing $HOSTPKGS)
# stale or empty package lists: read once more (sources unchanged)
if [ -n "$HOST_MISS" ]; then
  if [ "$(id -u)" = 0 ] && apt-get update -qq >/dev/null 2>&1; then HOST_MISS=$(pkg_missing $HOSTPKGS)
  else HOST_MISS=; warn "package lists could not be refreshed; host package check skipped"; fi
fi
[ -z "$HOST_MISS" ] || die "this system's package sources lack host packages setup needs: ${HOST_MISS% }
       Steam ARM needs Ubuntu 25.10 or newer, Debian 13 or newer, or a distribution built on
       them (README, Requirements); Ubuntu 24.04 and Debian 12 have no SDL3 packages.
       No package or package source changed."
# FEX from another source (FEX command not from a fex-emu package): its x86 binfmt entries needed; FEX packages skipped.
FEX_OTHER=0
if command -v FEX >/dev/null 2>&1 && ! fex_packaged; then
  fex_binfmt || die "FEX at $(command -v FEX) comes from another source, and its x86 binfmt entries
       (FEX-x86, FEX-x86_64 in /proc/sys/fs/binfmt_misc) are not registered. Register them
       (FEX's build guide, binfmt_misc step: https://github.com/FEX-Emu/FEX), then run this again.
       No package or package source changed."
  FEX_OTHER=1
fi
if [ "$PAGESIZE" = 4096 ]; then
  if is_pi && ps_block && ! opt page-size; then
    [ "$(id -u)" = 0 ] || die "run as root"
    ps_remove || die "could not edit $FWCFG"
    warn "page-size deselected: 4K kernel line removed from $FWCFG. After next reboot, firmware"
    warn "loads its default kernel, and x86 titles stop running until page-size is selected again."
  fi
elif [ "$PS_IGNORE" = 1 ]; then
  warn "page size is $PAGESIZE, not 4096; continuing because STEAM_ARM_IGNORE_PAGESIZE=1."
  warn "x86 titles run only if this system provides its own 4K environment for them."
elif is_pi; then
  opt page-size || die "page size is $PAGESIZE and emulation needs 4096. Select page-size
       component, or add kernel=kernel8.img to $FWCFG yourself and reboot."
  [ "$(id -u)" = 0 ] || die "run as root"
  if ps_block; then
    say "4K page kernel already selected in $FWCFG; reboot, then run sudo steam-arm-setup again."
    exit 0
  fi
  [ -f "$FWDIR/kernel8.img" ] || die "page size is $PAGESIZE and $FWDIR has no kernel8.img (4K page
       kernel). Install your distribution's 4K kernel package, then run this again."
  if grep -qE '^[[:space:]]*kernel[[:space:]]*=' "$FWCFG"; then
    die "$FWCFG already sets kernel itself: $(grep -E '^[[:space:]]*kernel[[:space:]]*=' "$FWCFG" | head -1)
       Point it at kernel8.img (4K pages) and reboot, then run this again."
  fi
  [ -f "$FWCFG.steam-arm.bak" ] || cp -p "$FWCFG" "$FWCFG.steam-arm.bak" || die "could not back up $FWCFG"
  [ -n "$(tail -c1 "$FWCFG")" ] && echo >> "$FWCFG"   # file ending without a newline
  printf '%s\n[all]\nkernel=kernel8.img\n%s\n' "$PS_BEGIN" "$PS_END" >> "$FWCFG" || die "could not edit $FWCFG"
  say "page size is $PAGESIZE: $FWCFG now selects 4K page kernel (kernel8.img)."
  say "     previous file kept as $FWCFG.steam-arm.bak"
  say "     reboot, then run sudo steam-arm-setup again to install."
  exit 0
else
  case "$MODEL" in
    Apple*) die "page size is $PAGESIZE (Apple Silicon) and emulation needs 4096. Kernel on this
       hardware stays at 16K; x86 side has to run inside 4K virtual machine, such as muvm,
       which this installer does not set up.";;
  esac
  die "page size is $PAGESIZE and emulation needs 4096. Boot 4K page kernel (on most
       distributions, separate kernel package), then run this again.
       STEAM_ARM_IGNORE_PAGESIZE=1 skips this check."
fi
[ "$(id -u)" = 0 ] || die "run as root"
steam_up && steam_up_die
# Client folder marker (--remove deletes only a marked folder): folder new or empty, or the client folder of an earlier install.
# ARMHOME_FOREIGN=1 in the conf: folder held other files at first setup; it never gets the marker.
ARMHOME_MARK=1; ARMHOME_FOREIGN=0
ARMHOME_PRE="$(getent passwd "$GAMEUSER" 2>/dev/null | cut -d: -f6)"
ARMHOME_SAME=0
[ "$(conf_get ARMHOME_DIR)" = "$ARMHOME_DIR" ] && [ "$(conf_get GAMEUSER)" = "$GAMEUSER" ] && ARMHOME_SAME=1
if [ -n "$ARMHOME_PRE" ] && { [ -e "$ARMHOME_PRE/$ARMHOME_DIR" ] || [ -L "$ARMHOME_PRE/$ARMHOME_DIR" ]; }; then
  ARMHOME_PRE="$ARMHOME_PRE/$ARMHOME_DIR"
  if [ -e "$ARMHOME_PRE/steamapps" ] || [ -e "$ARMHOME_PRE/ubuntu12_32" ]; then
    die "$ARMHOME_PRE holds another Steam installation (steamapps or ubuntu12_32 in it). Steam ARM needs a folder of its own. Set ARMHOME_DIR to another folder (for example .local/share/steam-arm), then run this again."
  fi
  if [ "$ARMHOME_SAME" = 1 ] && [ "$(conf_get ARMHOME_FOREIGN)" = 1 ]; then ARMHOME_MARK=0; ARMHOME_FOREIGN=1
  elif [ -f "$ARMHOME_PRE/.steam-arm-client" ] || [ -z "$(ls -A "$ARMHOME_PRE" 2>/dev/null)" ]; then :
  # earlier client folder: recorded as not foreign, or (setup from before the record) default folder name only
  elif [ "$ARMHOME_SAME" = 1 ] && { [ -d "$ARMHOME_PRE/.local/share/Steam/steamrtarm64" ] \
       || { [ -f "$ARMHOME_PRE/.local/share/Steam/steam.sh" ] && [ -f "$ARMHOME_PRE/.local/share/Steam/ubuntu12_32/steam" ]; }; } \
       && { [ "$(conf_get ARMHOME_FOREIGN)" = 0 ] || [ "$ARMHOME_DIR" = .local/share/steam-arm ]; }; then :
  else ARMHOME_MARK=0; ARMHOME_FOREIGN=1
  fi
fi
[ "$RETIRE_OTHER" = 1 ] && retire_other
PREV_USER=$(conf_get GAMEUSER)
[ -n "$PREV_USER" ] && [ "$PREV_USER" != "$GAMEUSER" ] && acct_records_drop "$PREV_USER"

# wait for any boot-time apt/dpkg (unattended-upgrades, armbian online-extras) to release the lock
wait_apt(){
  local n=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
    [ $n = 0 ] && warn "another apt/dpkg is running; waiting for the lock..."
    sleep 5; n=$((n+5)); [ $n -ge 600 ] && die "another package manager still holds the dpkg lock after 10 minutes. Let it finish (or restart this system), then run this again."
  done
}
NETHINT="Check the network connection (and that this system's date is right), then run this again."

# ---------------------------------------------------------------------------
if [ "$CLIENT" = x86 ]; then
  steam_banner "Steam ARM $SA_VERSION: Steam client setup (x86 client through emulation)" \
               "Valve's x86 Linux client and its titles through FEX ($(x86_why))" "$PS_LINE"
else
  steam_banner "Steam ARM $SA_VERSION: native ARM64 Steam client setup" \
               "Valve's ARM Linux client, x86 titles through the emulation tool it downloads" "$PS_LINE"
fi
printf 'Optional components:'; for c in $COMPONENTS; do opt "$c" && printf ' %s' "$c" || printf ' [no %s]' "$c"; done; echo
say "1/11  host packages"
export DEBIAN_FRONTEND=noninteractive
wait_apt
# FEX serves Remote Play and the thunk libraries; the client's own emulator tool comes separately.
if ! command -v FEX >/dev/null 2>&1 && ! os_ubuntu; then
  fex_source_debian
elif ! command -v FEX >/dev/null 2>&1; then
  command -v add-apt-repository >/dev/null || apt-get install -y software-properties-common \
    || die "software-properties-common did not install (needed to add the FEX package source). $NETHINT"
  grep -rq "fex-emu/fex" /etc/apt/sources.list.d/ 2>/dev/null || add-apt-repository -y "$FEXPPA" \
    || die "could not add the FEX package source $FEXPPA. $NETHINT FEX packages exist for Ubuntu-based systems; on other distributions install FEX yourself first."
fi
wait_apt; apt-get update -y || die "package lists could not be updated (apt-get update failed). $NETHINT"
# FEX build for this CPU, same rule as FEX's InstallFEX.py (first CPU's Features line).
fex_arch(){
  local f; f=" $(cpu_features) "
  fex_has(){ local x; for x; do case "$f" in *" $x "*) ;; *) return 1;; esac; done; }
  if fex_has atomics asimdrdm crc32 dcpop fcma jscvt lrcpc paca pacg asimddp flagm ilrcpc uscat; then echo 8.4
  elif fex_has atomics asimdrdm crc32 dcpop; then echo 8.2
  else echo 8.0; fi
}
# Newest build this CPU runs that apt offers; older builds run on newer CPUs, never the reverse.
fex_pkg(){
  local a c; a=$(fex_arch)
  for c in 8.4 8.2 8.0; do
    case "$a:$c" in 8.2:8.4|8.0:8.4|8.0:8.2) continue;; esac
    LC_ALL=C apt-cache policy "fex-emu-armv$c" 2>/dev/null | grep -q 'Candidate: [0-9]' && { echo "fex-emu-armv$c"; return; }
  done
  echo "fex-emu-armv$a"
}
if [ "$FEX_OTHER" = 1 ]; then
  FEXPKGS=""
  say "FEX from another source: $(command -v FEX); FEX packages skipped"
else
  FEXPKG=$(fex_pkg)
  say "FEX build for this CPU (ARMv$(fex_arch) features): $FEXPKG"
  FEXPKGS="$FEXPKG fex-emu-binfmt32 fex-emu-binfmt64"
  FEX_MISS=$(pkg_missing $FEXPKGS)
  [ -z "$FEX_MISS" ] || die "FEX packages not offered by this system's package sources: ${FEX_MISS% }
       Install FEX from another source with its x86 binfmt entries (FEX's InstallFEX.py or
       build guide: https://github.com/FEX-Emu/FEX), then run this again."
fi
wait_apt; apt-get install -y $FEXPKGS $HOSTPKGS \
  || die "host packages did not install (apt-get install failed; its message is above). $NETHINT If it reports packages it cannot find, this distribution release lacks them; README, Requirements names supported releases."
command -v FEX >/dev/null || die "FEX is not on this system after package install. Install $FEXPKG by hand (sudo apt install $FEXPKG), then run this again."
# x86 client: runtime containers start through host bubblewrap (an emulated one hangs).
if [ "$CLIENT" = x86 ] && ! file -b "$(command -v bwrap 2>/dev/null || echo /nonexistent)" 2>/dev/null | grep -q aarch64; then
  die "native bubblewrap needed for x86 client: $(command -v bwrap || echo 'bwrap not found'). Install distribution package bubblewrap (ARM64 build), then run this again."
fi
for l in libSDL3.so.0 libopenal.so.1 libgtk-x11-2.0.so.0 libibus-1.0.so.5; do
  ldconfig -p | grep -q "$l" || die "$l missing after package install. Run this again; if it stays missing, report it with the output above."
done
# FEX owns x86 execution (box64/box32 binfmt off), persistent
echo 0 > /proc/sys/fs/binfmt_misc/box64 2>/dev/null || true
echo 0 > /proc/sys/fs/binfmt_misc/box32 2>/dev/null || true
cat > /etc/systemd/system/steam-arm-fex-binfmt.service <<'UNIT'
[Unit]
Description=Disable box64/box32 binfmt so FEX owns x86-64 execution
After=systemd-binfmt.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 0 > /proc/sys/fs/binfmt_misc/box64 2>/dev/null; echo 0 > /proc/sys/fs/binfmt_misc/box32 2>/dev/null; true'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now steam-arm-fex-binfmt.service >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
say "2/11  game user '$GAMEUSER', /dev/shm, kernel limits"
mkdir -p /etc/steam-arm
if ! id "$GAMEUSER" >/dev/null 2>&1; then
  [ "$GAMEUSER_MAY_CREATE" = 1 ] || die "account '$GAMEUSER' not found and this source may not create one"
  # only groups that exist (some systems have no render group)
  GRPS=$(for g in video render input audio; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done)
  useradd -m -s /bin/bash ${GRPS:+-G "${GRPS%,}"} "$GAMEUSER" \
    || die "account '$GAMEUSER' could not be created (useradd failed). Pick another name with GAMEUSER=name, then run this again."
  conf_set ACCOUNT_CREATED 1
  # Password: from --password-stdin (never printed), else made here and shown once; no terminal: root-only file.
  if [ -z "$GAMEPASS" ]; then
    GAMEPASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 14)
    if [ -t 1 ]; then
      say "     created account '$GAMEUSER' with password: $GAMEPASS"
      say "     write it down now; change it with: passwd $GAMEUSER"
    else
      PWFILE="/root/steam-arm-password-$GAMEUSER.txt"
      ( umask 077; printf '%s\n' "$GAMEPASS" > "$PWFILE" ) && chmod 600 "$PWFILE"
      say "     created account '$GAMEUSER'; its password is in $PWFILE (readable by root only)."
      say "     read it with: sudo cat $PWFILE   then delete the file; change the password with: passwd $GAMEUSER"
    fi
  else
    say "     created account '$GAMEUSER' with the password given"
  fi
  printf '%s:%s\n' "$GAMEUSER" "$GAMEPASS" | chpasswd || warn "password of '$GAMEUSER' could not be set; set one with: sudo passwd $GAMEUSER"
fi
# Groups apply at next login; say so when an existing account gained any.
NEWGROUPS=
for g in video render input audio; do
  getent group "$g" >/dev/null 2>&1 || continue
  id -nG "$GAMEUSER" | tr ' ' '\n' | grep -qx "$g" && continue
  usermod -aG "$g" "$GAMEUSER" 2>/dev/null && NEWGROUPS="$NEWGROUPS $g"
done
if [ -n "$NEWGROUPS" ]; then
  warn "account '$GAMEUSER' added to groups:$NEWGROUPS"
  warn "log out and log back in (or restart) before first start of Steam ARM, so they take effect"
fi
# Linger keeps the user's runtime folder for the client; recorded only when setup turned it on, so --remove undoes only that.
if [ ! -e "/var/lib/systemd/linger/$GAMEUSER" ] && loginctl enable-linger "$GAMEUSER" >/dev/null 2>&1; then
  conf_set LINGER_SET 1
fi
UHOME=$(getent passwd "$GAMEUSER" | cut -d: -f6)
[ -d "$UHOME" ] || die "home folder of '$GAMEUSER' ($UHOME) does not exist. Create it (sudo mkhomedir_helper $GAMEUSER), then run this again."
ARMHOME="$UHOME/$ARMHOME_DIR"
# /dev/shm: tmpfs with mode 1777; a mounted one is fixed in place, never mounted over (programs may hold it).
if ! mountpoint -q /dev/shm; then
  mount -t tmpfs -o rw,nosuid,nodev,mode=1777 tmpfs /dev/shm || warn "could not mount tmpfs on /dev/shm; Proton titles may not start"
elif [ "$(stat -f -c %T /dev/shm)" != tmpfs ]; then
  warn "/dev/shm is mounted but is not tmpfs; left as it is. Proton titles may not start"
elif [ "$(stat -c %a /dev/shm)" != 1777 ]; then
  chmod 1777 /dev/shm
fi
# fstab line only when nothing else mounts /dev/shm at boot (a line of its own, or a dev-shm.mount unit)
if ! grep -q '^[^#]*[[:space:]]/dev/shm[[:space:]]' /etc/fstab 2>/dev/null && ! systemctl cat dev-shm.mount >/dev/null 2>&1; then
  if fstab_edit add; then conf_set FSTAB_ADDED 1; else warn "could not add the /dev/shm line to /etc/fstab"; fi
fi
if opt map-count; then
  rm -f /etc/sysctl.d/99-steam-arm.conf
  if [ -f "$MC" ]; then prior=$(sed -n "s/^$MC_PRIOR//p" "$MC" | head -1)
  else prior=$(sysctl -n vm.max_map_count 2>/dev/null); fi
  # the value setup writes is no earlier value (another setup's drop-in, or a run that stopped)
  [ "$prior" = 2147483642 ] && prior=
  { [ -n "$prior" ] && printf '%s%s\n' "$MC_PRIOR" "$prior"; printf 'vm.max_map_count = 2147483642\n'; } > "$MC"
  sysctl -q -p "$MC" 2>/dev/null || true
else
  mc_restore "map-count deselected: "
fi

# ---------------------------------------------------------------------------
say "3/11  x86-64 RootFS (graphics provider) + emulator configuration"
# Fetch the x86-64 Ubuntu 24.04 RootFS (graphics provider) via FEXRootFSFetcher.
# Files every usable RootFS has; prints the missing ones.
rfs_missing(){ local f; for f in usr/lib/x86_64-linux-gnu/libc.so.6 usr/lib/i386-linux-gnu/libc.so.6 usr/bin/bash; do [ -e "$1/$f" ] || printf ' %s' "$f"; done; }
# Moved in through $RFS.part, completeness checked, marker written last; a stopped earlier run leaves only $RFS.part, removed here.
rm -rf "$RFS.part"
# Fetcher's folders; a fetched RootFS counts only once setup marked it complete there.
RFS_DIRS=(/root/.fex-emu/RootFS /root/.local/share/fex-emu/RootFS)
RFS_DONE=.steam-arm-fetch-complete
if [ ! -d "$RFS" ]; then
  SRC=
  for d in "${RFS_DIRS[@]}"; do
    [ -d "$d/Ubuntu_24_04" ] || continue
    if [ -z "$SRC" ] && [ -f "$d/Ubuntu_24_04/$RFS_DONE" ]; then SRC=$d/Ubuntu_24_04; continue; fi
    rm -rf "$d/Ubuntu_24_04"; echo "  unfinished or duplicate extraction removed: $d/Ubuntu_24_04"
  done
  # earlier download whose extraction stopped: extract again
  for d in "${RFS_DIRS[@]}"; do
    if [ -n "$SRC" ] || [ ! -f "$d/Ubuntu_24_04.sqsh" ] || ! command -v unsquashfs >/dev/null 2>&1; then continue; fi
    echo "  extracting earlier download $d/Ubuntu_24_04.sqsh"
    if unsquashfs -q -n -d "$d/Ubuntu_24_04" "$d/Ubuntu_24_04.sqsh" >/dev/null 2>&1 && [ -z "$(rfs_missing "$d/Ubuntu_24_04")" ]; then
      : > "$d/Ubuntu_24_04/$RFS_DONE" && SRC=$d/Ubuntu_24_04
    else
      rm -rf "$d/Ubuntu_24_04"; echo "  earlier download unusable; downloading again"
    fi
  done
  if [ -z "$SRC" ]; then
    # leftover download from earlier run: fetcher's overwrite prompt aborts under -y
    for d in "${RFS_DIRS[@]}"; do rm -f "$d/Ubuntu_24_04.sqsh"; done
    if ( cd /opt 2>/dev/null; env -u DISPLAY FEXRootFSFetcher -y -x --force-ui=tty --distro-name=ubuntu --distro-version=24.04 ); then
      SRC=$(find "${RFS_DIRS[@]}" -maxdepth 1 -name Ubuntu_24_04 -type d 2>/dev/null | head -1)
      [ -n "$SRC" ] && : > "$SRC/$RFS_DONE"
    fi
  fi
  [ -n "$SRC" ] || die "x86-64 root filesystem download failed (FEXRootFSFetcher, about 525 MB; it needs about 2.5 GB free in /root and /opt). $NETHINT"
  { mkdir -p /opt/fex-rootfs && mv "$SRC" "$RFS.part"; } \
    || { rm -rf "$RFS.part"; die "could not move the x86-64 root filesystem from $SRC to $RFS (about 2 GB). Free some space on the disk that holds /opt, then run this again."; }
  MISS=$(rfs_missing "$RFS.part")
  if [ -n "$MISS" ]; then
    rm -rf "$RFS.part"
    die "x86-64 root filesystem download was incomplete (missing:$MISS) and is deleted. Free some space in /root and /opt, then run this again."
  fi
  # marker records that setup downloaded it (kept across --remove, so a later --purge still knows)
  rm -f "$RFS.part/$RFS_DONE"
  echo "downloaded by steam-arm-setup $(date '+%F %T')" > "$RFS.part/.steam-arm-rootfs"
  conf_set RFS_CREATED 1
  mv "$RFS.part" "$RFS" || die "could not move $RFS.part to $RFS; run this again"
  # download no longer needed once extracted (525 MB)
  for d in "${RFS_DIRS[@]}"; do rm -f "$d/Ubuntu_24_04.sqsh"; done
elif [ ! -f "$RFS/.steam-arm-rootfs" ] && MISS=$(rfs_missing "$RFS") && [ -n "$MISS" ]; then
  die "x86-64 root filesystem $RFS is incomplete (missing:$MISS). Move it away or delete it (sudo rm -rf $RFS), then run this again to download it."
elif grep -qs '^downloaded by steam-arm-setup' "$RFS/.steam-arm-rootfs"; then
  conf_set RFS_CREATED 1
fi
chmod o+rx /opt /opt/fex-rootfs "$RFS"
[ -f "$RFS/usr/lib/x86_64-linux-gnu/libGL.so.1" ] || warn "RootFS carries no x86-64 libGL; games will not reach the GPU"
# Pre-release layout laid the drivers over this RootFS: distro Mesa back first (second tree is built from it).
if [ -d "$PSTATE" ]; then
  echo "  earlier driver layout found: putting distro Mesa back into $RFS"
  legacy_mesa_restore || die "run this again to finish putting distro Mesa back"
fi
rfs_guard "$RFS" || warn "package tools in $RFS could not be guarded; never run apt or dpkg inside the emulation"
[ "$CLIENT" = x86 ] && { rfs_bwrap_off "$RFS" || warn "x86 bwrap in $RFS could not be set aside; runtime containers of x86 client may hang"; }
if [ "$CLIENT" = arm64 ]; then
  for t in "$RFS" "$MALI"; do rfs_bwrap_on "$t" && echo "  x86 bwrap in $t put back (native client)"; done
fi
# graphics_provider.json makes the runtime use this RootFS as the emulation path (forwarding, default for every title).
# A different file placed by something else stays untouched and that owner's (not recorded, so --remove keeps it).
if [ -f "$RFS/graphics_provider.json" ] && ! awk -v p="$RFS/graphics_provider.json" 'substr($0, 67) == p {f=1} END {exit !f}' "$OWNED" 2>/dev/null \
   && [ "$(cat "$RFS/graphics_provider.json")" != "$(gp_list_json)" ]; then
  echo "  $RFS/graphics_provider.json was placed by other software; left as it is"
else
  gp_list_write || die "could not write $RFS/graphics_provider.json. Free some space on the disk that holds /opt, then run this again."
  own_mark "$RFS/graphics_provider.json"
fi
# Same RootFS under the path Valve's runtime looks at; a folder or link placed there by other software stays.
if [ -L /usr/share/guestos/fex-mesa ] && [ "$(readlink /usr/share/guestos/fex-mesa)" = "$RFS" ]; then :
elif [ -e /usr/share/guestos/fex-mesa ] || [ -L /usr/share/guestos/fex-mesa ]; then
  echo "  /usr/share/guestos/fex-mesa was placed by other software; left as it is"
else
  mkdir -p /usr/share/guestos && ln -s "$RFS" /usr/share/guestos/fex-mesa
fi
# Second graphics tree for titles that need Mali drivers inside the emulation (handler picks per title).
# --provider-default: custom settings cleared only once the published tree is in place; on failure both stay.
[ "$PROVIDER_DEFAULT" = 1 ] && grep -qs '^PROVIDER_CUSTOM_' "$CONF" \
  && DIE_NOTE="Custom driver archive settings and $MALI kept: games keep the custom drivers. Fix the above, then run this again with --provider-default."
if opt gpu-in-emulation; then
  command -v zstd >/dev/null 2>&1 || die "zstd missing; install it (sudo apt install zstd), then run this again"
  mali_tree_build
else
  mali_tree_remove && echo "  gpu-in-emulation deselected: $MALI deleted"
fi
DIE_NOTE=
if [ "$PROVIDER_DEFAULT" = 1 ] && grep -qs '^PROVIDER_\(CUSTOM\|LOCAL\)_' "$CONF"; then
  conf_del PROVIDER_CUSTOM_SHA256; conf_del PROVIDER_CUSTOM_FILE
  if [ "${PSRC_FROM:-}" = env ] && opt gpu-in-emulation && [ -n "$(conf_get PROVIDER_LOCAL_FILE)" ]; then
    echo "  custom driver archive settings cleared: local copy of published archive from now on"
  else
    conf_del PROVIDER_LOCAL_FILE
    echo "  driver archive settings cleared: download from project release from now on"
  fi
fi
for t in "$RFS" "$MALI"; do
  rfs_root_own "$t" || warn "owner of $t could not be set to root; account owning it can change x86 programs of the emulation"
done
# FEX config for the game user; HostEnv entries select the GLX copy (step 4) and Vulkan layer path (step 5).
FEXEXTRA=",
  \"Multiblock\":\"1\""
opt glx-lax && FEXEXTRA="$FEXEXTRA,
  \"HostEnv\":\"__GLX_VENDOR_LIBRARY_NAME=steamarmlax\""
opt vk-spoof  && FEXEXTRA="$FEXEXTRA,
  \"HostEnv\":\"VK_IMPLICIT_LAYER_PATH=/usr/share/vulkan/implicit_layer.d\""
# Thunk folders of FEX in use (package: /usr, other source: its prefix); none found: thunks off.
FEXTHUNK=""; FEXTH=0
if read -r TH_HOST TH_GUEST TH_DB < <(fex_thunk_paths); then
  FEXTHUNK=",
  \"ThunkHostLibs\":\"$TH_HOST\",
  \"ThunkGuestLibs\":\"$TH_GUEST\",
  \"ThunkConfig\":\"$TH_DB\""; FEXTH=1
else
  warn "FEX thunk libraries not found (HostThunks, GuestThunks, ThunksDB.json beside $(command -v FEX));"
  warn "GL and Vulkan thunks off in $UHOME/.fex-emu/Config.json (x86 Remote Play client runs without them)."
fi
as_user mkdir -p "$UHOME/.fex-emu" || die "could not create $UHOME/.fex-emu as '$GAMEUSER'. Check that this account owns its home folder, then run this again."
user_write "$UHOME/.fex-emu/Config.json" <<JSON || die "could not write $UHOME/.fex-emu/Config.json as '$GAMEUSER'. Free some space, then run this again."
{ "Config": { "RootFS":"$RFS"$FEXTHUNK$FEXEXTRA },
  "ThunksDB":{"GL":$FEXTH,"Vulkan":$FEXTH} }
JSON
own_mark "$UHOME/.fex-emu/Config.json"
as_user rm -f "$ARMHOME/.fex-emu/Config.json" 2>/dev/null   # the launcher copies the fresh one

# ---------------------------------------------------------------------------
if opt glx-lax; then
say "4/11  GL context binding across threads (private Mesa GLX copy)"
# Patch libGLX_mesa to allow one GL context bound from multiple threads (some titles need this); installed as vendor "steamarmlax", host-side only.
cat > /usr/local/lib/steam-arm-glx-lax-patch.py <<'PYEOF'
#!/usr/bin/env python3
# Patch libGLX_mesa: nop MakeContextCurrent's cross-thread current-context check (exit 1 if no match). Usage: <in> <out>
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
b = bytearray(open(src, "rb").read())
hits = []
for off in range(0, len(b) - 12, 4):
    i0, i1, i2 = struct.unpack_from("<III", b, off)
    if (i0 & 0xFFFFFC00) != 0xF9408000: continue      # ldr x?, [x?, #256]
    if (i1 & 0xFF000000) != 0xB5000000: continue      # cbnz x?, imm
    if (i2 & 0xFFFFFC00) != 0xF9401400: continue      # ldr x?, [x?, #40]
    rt, rn = i0 & 31, (i0 >> 5) & 31
    if (i1 & 31) != rt or ((i2 >> 5) & 31) != rn: continue
    hits.append(off + 4)
if len(hits) != 1:
    print("steam-arm-glx-lax-patch: expected one match, found %d %s" % (len(hits), [hex(h) for h in hits]), file=sys.stderr)
    sys.exit(1)
struct.pack_into("<I", b, hits[0], 0xD503201F)  # nop
open(dst, "wb").write(b)
print("steam-arm-glx-lax-patch: cbnz at 0x%x replaced" % hits[0])
PYEOF
cat > /usr/local/sbin/steam-arm-glx-lax <<'GLX'
#!/bin/sh
# Keep libGLX_steamarmlax.so.0 in sync with system Mesa GLX; rebuilds only on checksum change.
SRC=$(realpath /usr/lib/aarch64-linux-gnu/libGLX_mesa.so.0 2>/dev/null) || exit 0
[ -f "$SRC" ] || exit 0
OUT=/usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0
STAMP=/usr/local/lib/steam-arm-glx-lax.src
# Fast path for the apt hook: source path, size and mtime unchanged since last build.
STAT=/usr/local/lib/steam-arm-glx-lax.stat
ST="$SRC $(stat -c '%s %Y' "$SRC")"
[ -f "$OUT" ] && [ "$(cat "$STAT" 2>/dev/null)" = "$ST" ] && exit 0
SUM=$(sha256sum "$SRC" | cut -c1-64)
[ -f "$OUT" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$SUM" ] && [ "$(patchelf --print-soname "$OUT" 2>/dev/null)" = libGLX_steamarmlax.so.0 ] && { echo "$ST" > "$STAT"; exit 0; }
T=$(mktemp "$OUT.XXXXXX") || exit 1
trap 'rm -f "$T"' EXIT
if python3 /usr/local/lib/steam-arm-glx-lax-patch.py "$SRC" "$T" >/dev/null 2>&1; then
  echo "steam-arm-glx-lax: patched copy built from $(basename "$SRC")"
else
  cp -f "$SRC" "$T"
  echo "steam-arm-glx-lax: pattern not found in $(basename "$SRC"); vendor library is an unpatched copy" >&2
fi
# Own SONAME so Steam Linux Runtime containers copy this vendor lib in too.
command -v patchelf >/dev/null && patchelf --set-soname libGLX_steamarmlax.so.0 "$T"
chmod 644 "$T" && mv -f "$T" "$OUT" && echo "$SUM" > "$STAMP" && echo "$ST" > "$STAT" && ldconfig
GLX
chmod 755 /usr/local/sbin/steam-arm-glx-lax
# Rebuild after every dpkg run that changed system Mesa GLX; never fails the apt run.
cat > "$GLX_HOOK" <<'APTHOOK'
// steam-arm-setup glx-lax: keep the private GLX copy in step with system Mesa.
DPkg::Post-Invoke { "if [ -x /usr/local/sbin/steam-arm-glx-lax ]; then /usr/local/sbin/steam-arm-glx-lax || true; fi"; };
APTHOOK
chmod 644 "$GLX_HOOK"
/usr/local/sbin/steam-arm-glx-lax
[ -f /usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0 ] && echo "  libGLX_steamarmlax.so.0 ready" || echo "  [warn] no native libGLX_mesa found; lax GLX copy skipped"
else
say "4/11  private Mesa GLX copy: not selected"
rm -f /usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0 /usr/local/sbin/steam-arm-glx-lax /usr/local/lib/steam-arm-glx-lax-patch.py \
      /usr/local/lib/steam-arm-glx-lax.src /usr/local/lib/steam-arm-glx-lax.stat "$GLX_HOOK"
fi

# ---------------------------------------------------------------------------
if opt vk-spoof; then
say "5/11  Vulkan feature layer for Proton titles (DXVK on the Mali driver)"
# DXVK requires Vulkan features panvk lacks; this layer spoofs them present, then strips missing ones before vkCreateDevice. Enabled via STEAM_ARM_VK_SPOOF=1, opt-out STEAM_ARM_VK_SPOOF_DISABLE=1.
cat > /usr/local/lib/steam-arm-vk-spoof.c <<'CEOF'
/* VK_LAYER_STEAM_ARM_feature_spoof: report a fixed set of VkPhysicalDeviceFeatures as supported and strip
 * them again from vkCreateDevice where the driver lacks them, so it never sees a missing one enabled. */
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_INST 16
#define MAX_DEV 64
typedef struct { void *key; PFN_vkGetInstanceProcAddr gipa; PFN_vkCreateDevice create_device;
  PFN_vkGetPhysicalDeviceFeatures gpdf; PFN_vkGetPhysicalDeviceFeatures2 gpdf2; PFN_vkDestroyInstance destroy; } inst_t;
typedef struct { void *key; PFN_vkGetDeviceProcAddr gdpa; } dev_t_;
static inst_t insts[MAX_INST]; static dev_t_ devs[MAX_DEV]; static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int dbg;

static void *key_of(const void *h) { return *(void **)h; }
static inst_t *inst_find(const void *h) { void *k = key_of(h); for (int i = 0; i < MAX_INST; i++) if (insts[i].key == k) return &insts[i]; return NULL; }
static dev_t_ *dev_find(const void *h) { void *k = key_of(h); for (int i = 0; i < MAX_DEV; i++) if (devs[i].key == k) return &devs[i]; return NULL; }

static void spoof_features(VkPhysicalDeviceFeatures *f) {
  f->fillModeNonSolid = VK_TRUE; f->geometryShader = VK_TRUE; f->multiViewport = VK_TRUE;
  f->shaderClipDistance = VK_TRUE; f->shaderCullDistance = VK_TRUE;
}
/* keep a requested feature only where the driver has it; never enable one the app left off */
static void unspoof_features(VkPhysicalDeviceFeatures *f, const VkPhysicalDeviceFeatures *real) {
  f->fillModeNonSolid &= real->fillModeNonSolid; f->geometryShader &= real->geometryShader; f->multiViewport &= real->multiViewport;
  f->shaderClipDistance &= real->shaderClipDistance; f->shaderCullDistance &= real->shaderCullDistance;
}

static VKAPI_ATTR void VKAPI_CALL layer_GetPhysicalDeviceFeatures(VkPhysicalDevice pd, VkPhysicalDeviceFeatures *f) {
  inst_t *in = inst_find(pd); in->gpdf(pd, f); spoof_features(f);
}
static VKAPI_ATTR void VKAPI_CALL layer_GetPhysicalDeviceFeatures2(VkPhysicalDevice pd, VkPhysicalDeviceFeatures2 *f) {
  inst_t *in = inst_find(pd); in->gpdf2(pd, f); spoof_features(&f->features);
  for (VkBaseOutStructure *p = (VkBaseOutStructure *)f->pNext; p; p = p->pNext)
    if (p->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT)
      ((VkPhysicalDeviceRobustness2FeaturesEXT *)p)->robustBufferAccess2 = VK_TRUE;
}

static VKAPI_ATTR VkResult VKAPI_CALL layer_CreateInstance(const VkInstanceCreateInfo *ci, const VkAllocationCallbacks *ac, VkInstance *inst) {
  VkLayerInstanceCreateInfo *li = (VkLayerInstanceCreateInfo *)ci->pNext;
  while (li && !(li->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO && li->function == VK_LAYER_LINK_INFO)) li = (VkLayerInstanceCreateInfo *)li->pNext;
  if (!li) return VK_ERROR_INITIALIZATION_FAILED;
  PFN_vkGetInstanceProcAddr gipa = li->u.pLayerInfo->pfnNextGetInstanceProcAddr;
  li->u.pLayerInfo = li->u.pLayerInfo->pNext;
  PFN_vkCreateInstance next = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
  VkResult r = next(ci, ac, inst);
  if (r != VK_SUCCESS) return r;
  pthread_mutex_lock(&lock);
  for (int i = 0; i < MAX_INST; i++) if (!insts[i].key) {
    insts[i].key = key_of(*inst); insts[i].gipa = gipa;
    insts[i].create_device = (PFN_vkCreateDevice)gipa(*inst, "vkCreateDevice");
    insts[i].gpdf = (PFN_vkGetPhysicalDeviceFeatures)gipa(*inst, "vkGetPhysicalDeviceFeatures");
    insts[i].gpdf2 = (PFN_vkGetPhysicalDeviceFeatures2)gipa(*inst, "vkGetPhysicalDeviceFeatures2");
    if (!insts[i].gpdf2) insts[i].gpdf2 = (PFN_vkGetPhysicalDeviceFeatures2)gipa(*inst, "vkGetPhysicalDeviceFeatures2KHR");
    insts[i].destroy = (PFN_vkDestroyInstance)gipa(*inst, "vkDestroyInstance");
    break; }
  pthread_mutex_unlock(&lock);
  if (dbg) fprintf(stderr, "[steam-arm-vk-spoof] instance created\n");
  return VK_SUCCESS;
}
static VKAPI_ATTR void VKAPI_CALL layer_DestroyInstance(VkInstance inst, const VkAllocationCallbacks *ac) {
  inst_t *in = inst_find(inst); PFN_vkDestroyInstance d = in->destroy;
  pthread_mutex_lock(&lock); memset(in, 0, sizeof *in); pthread_mutex_unlock(&lock);
  d(inst, ac);
}

static VKAPI_ATTR VkResult VKAPI_CALL layer_CreateDevice(VkPhysicalDevice pd, const VkDeviceCreateInfo *ci, const VkAllocationCallbacks *ac, VkDevice *dev) {
  inst_t *in = inst_find(pd);
  VkLayerDeviceCreateInfo *li = (VkLayerDeviceCreateInfo *)ci->pNext;
  while (li && !(li->sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO && li->function == VK_LAYER_LINK_INFO)) li = (VkLayerDeviceCreateInfo *)li->pNext;
  if (!li) return VK_ERROR_INITIALIZATION_FAILED;
  PFN_vkGetDeviceProcAddr gdpa = li->u.pLayerInfo->pfnNextGetDeviceProcAddr;
  li->u.pLayerInfo = li->u.pLayerInfo->pNext;

  VkPhysicalDeviceFeatures real; in->gpdf(pd, &real);
  VkDeviceCreateInfo ci2 = *ci;
  VkPhysicalDeviceFeatures ef;
  if (ci->pEnabledFeatures) { ef = *ci->pEnabledFeatures; unspoof_features(&ef, &real); ci2.pEnabledFeatures = &ef; }
  /* clone the chain nodes that need editing; the rest is shared */
  VkPhysicalDeviceFeatures2 f2; VkPhysicalDeviceRobustness2FeaturesEXT r2; int have_f2 = 0, have_r2 = 0;
  VkBaseOutStructure head = { VK_STRUCTURE_TYPE_APPLICATION_INFO, (VkBaseOutStructure *)ci->pNext }; VkBaseOutStructure *prev = &head;
  for (VkBaseOutStructure *p = (VkBaseOutStructure *)ci->pNext; p; p = p->pNext) {
    if (p->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 && !have_f2) {
      f2 = *(VkPhysicalDeviceFeatures2 *)p; unspoof_features(&f2.features, &real); prev->pNext = (VkBaseOutStructure *)&f2; prev = (VkBaseOutStructure *)&f2; have_f2 = 1;
    } else if (p->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT && !have_r2) {
      /* strip robustBufferAccess2 only where the driver lacks it; without gpdf2 it counts as missing */
      VkPhysicalDeviceRobustness2FeaturesEXT rr = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT };
      VkPhysicalDeviceFeatures2 rf = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &rr };
      if (in->gpdf2) in->gpdf2(pd, &rf);
      r2 = *(VkPhysicalDeviceRobustness2FeaturesEXT *)p; r2.robustBufferAccess2 &= rr.robustBufferAccess2; prev->pNext = (VkBaseOutStructure *)&r2; prev = (VkBaseOutStructure *)&r2; have_r2 = 1;
    } else prev = p;
  }
  ci2.pNext = head.pNext;
  VkResult r = in->create_device(pd, &ci2, ac, dev);
  if (dbg) fprintf(stderr, "[steam-arm-vk-spoof] vkCreateDevice -> %d (features2 %d, robustness2 %d)\n", r, have_f2, have_r2);
  if (r != VK_SUCCESS) return r;
  pthread_mutex_lock(&lock);
  /* record the device only; vkDestroyDevice is resolved when it is called */
  for (int i = 0; i < MAX_DEV; i++) if (!devs[i].key) { devs[i].key = key_of(*dev); devs[i].gdpa = gdpa; break; }
  pthread_mutex_unlock(&lock);
  return VK_SUCCESS;
}
static VKAPI_ATTR void VKAPI_CALL layer_DestroyDevice(VkDevice dev, const VkAllocationCallbacks *ac) {
  dev_t_ *d = dev_find(dev); PFN_vkDestroyDevice f = (PFN_vkDestroyDevice)d->gdpa(dev, "vkDestroyDevice");
  pthread_mutex_lock(&lock); memset(d, 0, sizeof *d); pthread_mutex_unlock(&lock);
  f(dev, ac);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL steam_arm_GetDeviceProcAddr(VkDevice dev, const char *name);
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL steam_arm_GetInstanceProcAddr(VkInstance inst, const char *name) {
  if (!strcmp(name, "vkGetInstanceProcAddr")) return (PFN_vkVoidFunction)steam_arm_GetInstanceProcAddr;
  if (!strcmp(name, "vkCreateInstance")) return (PFN_vkVoidFunction)layer_CreateInstance;
  if (!strcmp(name, "vkDestroyInstance")) return (PFN_vkVoidFunction)layer_DestroyInstance;
  if (!strcmp(name, "vkCreateDevice")) return (PFN_vkVoidFunction)layer_CreateDevice;
  if (!strcmp(name, "vkGetDeviceProcAddr")) return (PFN_vkVoidFunction)steam_arm_GetDeviceProcAddr;
  if (!strcmp(name, "vkGetPhysicalDeviceFeatures")) return (PFN_vkVoidFunction)layer_GetPhysicalDeviceFeatures;
  if (!strcmp(name, "vkGetPhysicalDeviceFeatures2") || !strcmp(name, "vkGetPhysicalDeviceFeatures2KHR")) return (PFN_vkVoidFunction)layer_GetPhysicalDeviceFeatures2;
  if (!inst) return NULL;
  inst_t *in = inst_find(inst); return in ? in->gipa(inst, name) : NULL;
}
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL steam_arm_GetDeviceProcAddr(VkDevice dev, const char *name) {
  if (!strcmp(name, "vkGetDeviceProcAddr")) return (PFN_vkVoidFunction)steam_arm_GetDeviceProcAddr;
  if (!strcmp(name, "vkDestroyDevice")) return (PFN_vkVoidFunction)layer_DestroyDevice;
  dev_t_ *d = dev_find(dev); return d ? d->gdpa(dev, name) : NULL;
}
VKAPI_ATTR VkResult VKAPI_CALL vkNegotiateLoaderLayerInterfaceVersion(VkNegotiateLayerInterface *p) {
  dbg = getenv("STEAM_ARM_VK_SPOOF_DEBUG") != NULL;
  if (p->loaderLayerInterfaceVersion < 2) return VK_ERROR_INITIALIZATION_FAILED;
  p->loaderLayerInterfaceVersion = 2;
  p->pfnGetInstanceProcAddr = steam_arm_GetInstanceProcAddr;
  p->pfnGetDeviceProcAddr = steam_arm_GetDeviceProcAddr;
  p->pfnGetPhysicalDeviceProcAddr = NULL;
  return VK_SUCCESS;
}
CEOF
if gcc -shared -fPIC -O2 -o /usr/lib/aarch64-linux-gnu/libVkLayer_steam_arm_spoof.so /usr/local/lib/steam-arm-vk-spoof.c -lpthread; then
  chmod 644 /usr/lib/aarch64-linux-gnu/libVkLayer_steam_arm_spoof.so
  mkdir -p /usr/share/vulkan/implicit_layer.d
  cat > /usr/share/vulkan/implicit_layer.d/VkLayer_steam_arm_spoof.json <<'JSON'
{
  "file_format_version": "1.0.0",
  "layer": {
    "name": "VK_LAYER_STEAM_ARM_feature_spoof",
    "type": "GLOBAL",
    "library_path": "/usr/lib/aarch64-linux-gnu/libVkLayer_steam_arm_spoof.so",
    "api_version": "1.4.0",
    "implementation_version": "1",
    "description": "Reports fillModeNonSolid, geometryShader, multiViewport, shaderClipDistance, shaderCullDistance and robustBufferAccess2 as supported and strips missing ones from device creation",
    "functions": {
      "vkNegotiateLoaderLayerInterfaceVersion": "vkNegotiateLoaderLayerInterfaceVersion"
    },
    "enable_environment": { "STEAM_ARM_VK_SPOOF": "1" },
    "disable_environment": { "STEAM_ARM_VK_SPOOF_DISABLE": "1" }
  }
}
JSON
  chmod 644 /usr/share/vulkan/implicit_layer.d/VkLayer_steam_arm_spoof.json
  if command -v vulkaninfo >/dev/null 2>&1 && STEAM_ARM_VK_SPOOF=1 vulkaninfo 2>/dev/null | grep -q 'fillModeNonSolid *= *true'; then
    echo "  layer built and active under STEAM_ARM_VK_SPOOF=1"
  else
    echo "  layer built (vulkaninfo not available for a self-check)"
  fi
else
  echo "  [warn] layer build failed; Proton titles that need DXVK will not start"
fi
else
say "5/11  Vulkan feature layer: not selected"
rm -f /usr/lib/aarch64-linux-gnu/libVkLayer_steam_arm_spoof.so /usr/share/vulkan/implicit_layer.d/VkLayer_steam_arm_spoof.json /usr/local/lib/steam-arm-vk-spoof.c
fi

# ---------------------------------------------------------------------------
if opt xpad-dedup; then
say "6/11  one joystick per pad (duplicate xpad node removed)"
# Some third-party pads expose a headset interface that xpad also binds, duplicating the joystick; unbind it.
cat > /usr/local/sbin/steam-arm-xpad-dedup <<'DEDUP'
#!/bin/sh
# Unbind xpad from third-party pads' duplicate headset interface (ff/5d/3); idempotent.
case "${1:-}" in
  -h|--help)
    echo "usage: steam-arm-xpad-dedup   (root)"
    echo "  Unbinds xpad from duplicate headset interface (class ff/5d, protocol 3) of"
    echo "  third-party Xbox 360 style pads, so one pad no longer shows as two joysticks."
    echo "  Run by udev on plug-in and at boot."
    exit 0;;
esac
for i in /sys/bus/usb/drivers/xpad/*:*; do
  [ -e "$i" ] || continue
  [ "$(cat "$i/bInterfaceClass" 2>/dev/null)" = ff ] || continue
  [ "$(cat "$i/bInterfaceSubClass" 2>/dev/null)" = 5d ] || continue
  [ "$(cat "$i/bInterfaceProtocol" 2>/dev/null)" = 03 ] || continue
  n=$(basename "$i"); echo "$n" > /sys/bus/usb/drivers/xpad/unbind && echo "steam-arm-xpad-dedup: unbound duplicate pad interface $n"
done
exit 0
DEDUP
chmod 755 /usr/local/sbin/steam-arm-xpad-dedup
cat > /etc/udev/rules.d/71-steam-arm-xpad-dedup.rules <<'RULE'
# Drop duplicate xpad binding on third-party pads' headset interface.
ACTION=="add|bind", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", DRIVER=="xpad", ATTR{bInterfaceProtocol}=="03", RUN+="/usr/bin/systemd-run --no-block --quiet /usr/local/sbin/steam-arm-xpad-dedup"
RULE
udevadm control --reload-rules 2>/dev/null; /usr/local/sbin/steam-arm-xpad-dedup
else
say "6/11  duplicate joystick node: not selected"
rm -f /usr/local/sbin/steam-arm-xpad-dedup /etc/udev/rules.d/71-steam-arm-xpad-dedup.rules; udevadm control --reload-rules 2>/dev/null
fi

# ---------------------------------------------------------------------------
if opt pad-hidraw; then
say "7/11  controller access for the client"
# Valve's own rules first; a system package copy (steam-devices) wins over this copy.
if [ -f /usr/lib/udev/rules.d/60-steam-input.rules ] || [ -f /lib/udev/rules.d/60-steam-input.rules ]; then
  grep -qs "$VALVE_MARK" /etc/udev/rules.d/60-steam-input.rules && rm -f /etc/udev/rules.d/60-steam-input.rules
  echo "  Valve's controller rules come from a system package; kept"
elif [ -f /etc/udev/rules.d/60-steam-input.rules ] && ! grep -qs "$VALVE_MARK" /etc/udev/rules.d/60-steam-input.rules; then
  echo "  /etc/udev/rules.d/60-steam-input.rules was placed by someone else; kept"
else
cat > /etc/udev/rules.d/60-steam-input.rules <<'VALVERULES'
# Valve steam-devices 60-steam-input.rules (https://github.com/ValveSoftware/steam-devices), MIT licence; installed by steam-arm-setup
# Copyright (c) 2018 Valve Software
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software
# and associated documentation files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
# BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Valve USB devices
SUBSYSTEMS=="usb", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"

# Steam Controller udev write access
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"

# Valve HID devices over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"

# Valve HID devices hidraw
SUBSYSTEM=="hidraw", KERNELS=="000[356]:28DE:*", MODE="0660", TAG+="uaccess"

# Valve HID devices over bluetooth evdev
SUBSYSTEM=="input", ATTRS{id/vendor}=="28de", MODE="0660", TAG+="uaccess"

# Allow wakeup from Valve devices (Steam Controller 2015 receiver, Steam Controller 2026 receiver, Steam Machine Bluetooth) 
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", ATTR{power/wakeup}=="*", ATTR{power/wakeup}="enabled"

# DualShock 3 over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0268", MODE="0660", TAG+="uaccess"

# DualShock 3 over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*054C:0268*", MODE="0660", TAG+="uaccess"

# DualShock 4 over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", TAG+="uaccess"

# DualShock 4 wireless adapter over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ba0", MODE="0660", TAG+="uaccess"

# DualShock 4 Slim over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", TAG+="uaccess"

# DualShock 4 over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*054C:05C4*", MODE="0660", TAG+="uaccess"

# DualShock 4 Slim over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*054C:09CC*", MODE="0660", TAG+="uaccess"

# PS5 DualSense controller over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"

# PS5 DualSense controller over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"

# Sony DualSense Edge Wireless-Controller over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*054C:0DF2*", MODE="0660", TAG+="uaccess"

# Sony DualSense Edge Wireless-Controller over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", TAG+="uaccess"

# Nintendo Switch Pro Controller over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2009", MODE="0660", TAG+="uaccess"

# Nintendo Switch Pro Controller over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*057E:2009*", MODE="0660", TAG+="uaccess"

# Nintendo Switch Joy-Con (L/R)
KERNEL=="hidraw*", KERNELS=="*057E:200[67]*", MODE="0660", TAG+="uaccess"

# PDP Faceoff Wired Pro Controller for Nintendo Switch
KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0180", MODE="0660", TAG+="uaccess"

# PDP Faceoff Deluxe+ Audio Wired Pro Controller for Nintendo Switch
KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0184", MODE="0660", TAG+="uaccess"

# PDP Wired Fight Pad Pro for Nintendo Switch
KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0185", MODE="0660", TAG+="uaccess"

# Logic3 Rock Candy Wired Controller for Nintendo Switch
KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0187", MODE="0660", TAG+="uaccess"

# PowerA Wired Controller for Nintendo Switch
KERNEL=="hidraw*", ATTRS{idVendor}=="20d6", ATTRS{idProduct}=="a711", MODE="0660", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="20d6", ATTRS{idProduct}=="a712", MODE="0660", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="20d6", ATTRS{idProduct}=="a713", MODE="0660", TAG+="uaccess"

# PowerA Wireless Controller for Nintendo Switch we have to use
# ATTRS{name} since VID/PID are reported as zeros. We use /bin/sh
# instead of udevadm directly becuase we need to use '*' glob at the
# end of "hidraw" name since we don't know the index it'd have.
#
KERNEL=="input*", ATTRS{name}=="Lic Pro Controller", RUN{program}+="/bin/sh -c 'udevadm test-builtin uaccess /sys/%p/../../hidraw/hidraw*'"

# Afterglow Deluxe+ Wired Controller for Nintendo Switch
KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0188", MODE="0660", TAG+="uaccess"

# Nacon PS4 Revolution Pro Controller
KERNEL=="hidraw*", ATTRS{idVendor}=="146b", ATTRS{idProduct}=="0d01", MODE="0660", TAG+="uaccess"

# Razer Raiju PS4 Controller
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="1000", MODE="0660", TAG+="uaccess"

# Razer Raiju 2 Tournament Edition
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="1007", MODE="0660", TAG+="uaccess"

# Razer Panthera EVO Arcade Stick
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="1008", MODE="0660", TAG+="uaccess"

# Razer Raiju PS4 Controller Tournament Edition over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*1532:100A*", MODE="0660", TAG+="uaccess"

# Razer Raiju Ultimate over USB
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="1004", MODE="0660", TAG+="uaccess"

# Razer Raiju Ultimate over PC Bluetooth
KERNEL=="hidraw*", KERNELS=="*1532:1009*", MODE="0660", TAG+="uaccess"

# Razer Panthera Arcade Stick
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="0401", MODE="0660", TAG+="uaccess"

# Razer Wolverine V2 Pro in wired PS5 mode
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="100b", MODE="0660", TAG+="uaccess"

# Mad Catz - Street Fighter V Arcade FightPad PRO
KERNEL=="hidraw*", ATTRS{idVendor}=="0738", ATTRS{idProduct}=="8250", MODE="0660", TAG+="uaccess"

# Mad Catz - Street Fighter V Arcade FightStick TE S+
KERNEL=="hidraw*", ATTRS{idVendor}=="0738", ATTRS{idProduct}=="8384", MODE="0660", TAG+="uaccess"

# Brooks Universal Fighting Board
KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="0c30", MODE="0660", TAG+="uaccess"

# EMiO Elite Controller for PS4
KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="1cf6", MODE="0660", TAG+="uaccess"

# ZeroPlus P4 (hitbox)
KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="0ef6", MODE="0660", TAG+="uaccess"

# HORI RAP4
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="008a", MODE="0660", TAG+="uaccess"

# HORI Alpha for PS5 (PS5 Mode)
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="0184", MODE="0660", TAG+="uaccess"

# HORI Alpha for PS5 (PS4 Mode)
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="011c", MODE="0660", TAG+="uaccess"

# HORI Alpha for PS5 (PC Mode)
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="011e", MODE="0660", TAG+="uaccess"

# HORIPAD 4 FPS
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="0055", MODE="0660", TAG+="uaccess"

# HORIPAD 4 FPS Plus
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="0066", MODE="0660", TAG+="uaccess"

# HORIPAD for Nintendo Switch
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="00c1", MODE="0660", TAG+="uaccess"

# HORIPAD mini 4
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="00ee", MODE="0660", TAG+="uaccess"

# HORIPAD STEAM
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="01ab", MODE="0660", TAG+="uaccess"

# Armor Armor 3 Pad PS4
KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="0e10", MODE="0660", TAG+="uaccess"

# STRIKEPAD PS4 Grip Add-on
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c5", MODE="0660", TAG+="uaccess"

# NVIDIA Shield Portable (2013 - NVIDIA_Controller_v01.01 - In-Home Streaming only)
KERNEL=="hidraw*", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7203", MODE="0660", TAG+="uaccess", ENV{ID_INPUT_JOYSTICK}="1", ENV{ID_INPUT_MOUSE}=""

# NVIDIA Shield Controller (2015 - NVIDIA_Controller_v01.03 over USB hidraw)
KERNEL=="hidraw*", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7210", MODE="0660", TAG+="uaccess", ENV{ID_INPUT_JOYSTICK}="1", ENV{ID_INPUT_MOUSE}=""

# NVIDIA Shield Controller (2017 - NVIDIA_Controller_v01.04 over bluetooth hidraw)
KERNEL=="hidraw*", KERNELS=="*0955:7214*", MODE="0660", TAG+="uaccess"

# Astro C40
KERNEL=="hidraw*", ATTRS{idVendor}=="9886", ATTRS{idProduct}=="0025", MODE="0660", TAG+="uaccess"

# Thrustmaster eSwap Pro
KERNEL=="hidraw*", ATTRS{idVendor}=="044f", ATTRS{idProduct}=="d00e", MODE="0660", TAG+="uaccess"

# EdgeTX and OpenTX radio controllers in gamepad mode over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="4f54", MODE="0660", TAG+="uaccess"

# Thrustmaster TFRP Rudder
KERNEL=="hidraw*", ATTRS{idVendor}=="044f", ATTRS{idProduct}=="b679", MODE="0660", TAG+="uaccess"

# Thrustmaster TWCS Throttle
KERNEL=="hidraw*", ATTRS{idVendor}=="044f", ATTRS{idProduct}=="b687", MODE="0660", TAG+="uaccess"

# Thrustmaster T.16000M Joystick
KERNEL=="hidraw*", ATTRS{idVendor}=="044f", ATTRS{idProduct}=="b10a", MODE="0660", TAG+="uaccess"

# Performance Designed Products Victrix Pro FS-12 for PS4 & PS5
KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="020c", MODE="0660", TAG+="uaccess"

# Hori Co., Ltd HORI Wireless Pad ONYX PLUS Wired
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="012d", MODE="0660", TAG+="uaccess"

# Hori Co., Ltd HORI Wireless Pad ONYX PLUS Wireless
KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="012b", MODE="0660", TAG+="uaccess"

# Xbox One Elite 2 Controller
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="*045E:0B22*", MODE="0660", TAG+="uaccess"

# Generic SInput Device over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="10c6", MODE="0660", TAG+="uaccess"

# Generic SInput Device over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*2E8A:10C6*", MODE="0660", TAG+="uaccess"

# ProGCC in SInput Mode over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="10df", MODE="0660", TAG+="uaccess"

# ProGCC in SInput Mode over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*2E8A:10DF*", MODE="0660", TAG+="uaccess"

# GC Ultimate in SInput Mode over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="10dd", MODE="0660", TAG+="uaccess"

# GC Ultimate in SInput Mode over bluetooth hidraw
KERNEL=="hidraw*", KERNELS=="*2E8A:10DD*", MODE="0660", TAG+="uaccess"

# Firebird in SInput Mode over USB hidraw
KERNEL=="hidraw*", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="10e0", MODE="0660", TAG+="uaccess"

# 8bitdo 2.4 GHz / Wired
KERNEL=="hidraw*", ATTRS{idVendor}=="2dc8", MODE="0660", TAG+="uaccess"

# 8bitdo Bluetooth
KERNEL=="hidraw*", KERNELS=="*2DC8:*", MODE="0660", TAG+="uaccess"

# Flydigi 2.4 GHz / Wired
KERNEL=="hidraw*", ATTRS{idVendor}=="04b4", MODE="0660", TAG+="uaccess"

# Flydigi HIDAPI Enhanced Mode
KERNEL=="hidraw*", ATTRS{idVendor}=="37d7", MODE="0660", TAG+="uaccess"

# Nintendo Wii U/Switch Wired GameCube Controller Adapter
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="0337", MODE="0660", TAG+="uaccess"

# Nintendo Switch 2 Joy-Con (R) over USB
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2066", MODE="0660", TAG+="uaccess"

# Nintendo Switch 2 Joy-Con (L) over USB
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2067", MODE="0660", TAG+="uaccess"

# Nintendo Switch 2 Pro Controller over USB
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2069", MODE="0660", TAG+="uaccess"

# Nintendo Switch 2 GameCube Controller over USB
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2073", MODE="0660", TAG+="uaccess"
VALVERULES
chmod 644 /etc/udev/rules.d/60-steam-input.rules
fi
# Pads on the kernel's xpad table that Valve's rules lack; regenerate with gen-gamepad-hidraw-rules.py.
PAD_IDS="
0079:18d4 03eb:ff01 03eb:ff02 03f0:0495 044f:0f00 044f:0f03 044f:0f07
044f:0f10 044f:b326 045e:0202 045e:0285 045e:0287 045e:0288 045e:0289
045e:028e 045e:028f 045e:0291 045e:02d1 045e:02dd 045e:02e3 045e:02ea
045e:0719 045e:0b00 045e:0b0a 045e:0b12 046d:c21d 046d:c21e 046d:c21f
046d:c242 046d:ca84 046d:ca88 046d:ca8a 046d:caa3 056e:2004 05fd:1007
05fd:107a 05fe:3030 05fe:3031 062a:0020 062a:0033 06a3:0200 06a3:0201
06a3:f51a 0738:4506 0738:4516 0738:4520 0738:4522 0738:4526 0738:4530
0738:4536 0738:4540 0738:4556 0738:4586 0738:4588 0738:45ff 0738:4716
0738:4718 0738:4726 0738:4728 0738:4736 0738:4738 0738:4740 0738:4743
0738:4758 0738:4a01 0738:6040 0738:9871 0738:b726 0738:b738 0738:beef
0738:cb02 0738:cb03 0738:cb29 0738:f738 07ff:ffff 0c12:0005 0c12:8801
0c12:8802 0c12:8809 0c12:880a 0c12:8810 0c12:9902 0d2f:0002 0e4c:1097
0e4c:1103 0e4c:2390 0e4c:3510 0e6f:0003 0e6f:0005 0e6f:0006 0e6f:0008
0e6f:0105 0e6f:0113 0e6f:011f 0e6f:0131 0e6f:0133 0e6f:0139 0e6f:013a
0e6f:0146 0e6f:0147 0e6f:015c 0e6f:0161 0e6f:0162 0e6f:0163 0e6f:0164
0e6f:0165 0e6f:0201 0e6f:0213 0e6f:021f 0e6f:0246 0e6f:02a0 0e6f:02a1
0e6f:02a2 0e6f:02a4 0e6f:02a6 0e6f:02a7 0e6f:02a8 0e6f:02ab 0e6f:02ad
0e6f:02b3 0e6f:02b8 0e6f:0301 0e6f:0346 0e6f:0401 0e6f:0413 0e6f:0501
0e6f:f900 0e8f:0201 0e8f:3008 0f0d:000a 0f0d:000c 0f0d:000d 0f0d:0016
0f0d:001b 0f0d:0063 0f0d:0067 0f0d:0078 0f0d:00c5 0f30:010b 0f30:0202
0f30:8888 102c:ff0c 1038:1430 1038:1431 11c9:55f0 11ff:0511 1209:2882
12ab:0004 12ab:0301 12ab:0303 12ab:8809 1430:4748 1430:8888 1430:f801
146b:0601 146b:0604 1532:0a00 1532:0a03 1532:0a29 15e4:3f00 15e4:3f0a
15e4:3f10 162e:beef 1689:fd00 1689:fd01 1689:fe00 17ef:6182 1949:041a
1bad:0002 1bad:0003 1bad:0130 1bad:f016 1bad:f018 1bad:f019 1bad:f021
1bad:f023 1bad:f025 1bad:f027 1bad:f028 1bad:f02e 1bad:f030 1bad:f036
1bad:f038 1bad:f039 1bad:f03a 1bad:f03d 1bad:f03e 1bad:f03f 1bad:f042
1bad:f080 1bad:f501 1bad:f502 1bad:f503 1bad:f504 1bad:f505 1bad:f506
1bad:f900 1bad:f901 1bad:f903 1bad:f904 1bad:f906 1bad:fa01 1bad:fd00
1bad:fd01 20d6:2001 20d6:2009 20d6:281f 24c6:5000 24c6:5300 24c6:5303
24c6:530a 24c6:531a 24c6:5397 24c6:541a 24c6:542a 24c6:543a 24c6:5500
24c6:5501 24c6:5502 24c6:5503 24c6:5506 24c6:550d 24c6:550e 24c6:5510
24c6:551a 24c6:561a 24c6:5b00 24c6:5b02 24c6:5b03 24c6:5d04 24c6:fafe
2563:058d 2e24:0652 31e3:1100 31e3:1200 31e3:1210 31e3:1220 31e3:1300
31e3:1310 3285:0607 3767:0101
"
{
  echo "# Hand the logged-in user the hidraw node of a game controller Valve's rules do not list."
  echo "# Written by the Steam installer. uaccess grants the access to whoever holds the"
  echo "# active local seat, the same way it is granted for a keyboard or a sound card."
  # Sony and Nintendo pads Valve lists only by model (e.g. Switch Online pads): matched by their kernel pad driver,
  # so keyboards, mice and other devices of these makers stay out.
  echo 'KERNEL=="hidraw*", DRIVERS=="playstation|sony|nintendo", MODE="0660", TAG+="uaccess"'
  # kernel without the pad driver: no DRIVERS match, so the whole vendor gets the node
  for vd in 057e:hid-nintendo 054c:hid-playstation,hid-sony; do
    v=${vd%%:*}; m=0
    for mod in $(echo "${vd#*:}" | tr ',' ' '); do modinfo "$mod" >/dev/null 2>&1 && m=1; done
    [ $m = 1 ] && continue
    u=$(echo "$v" | tr 'a-f' 'A-F')
    echo "KERNEL==\"hidraw*\", ATTRS{idVendor}==\"$v\", MODE=\"0660\", TAG+=\"uaccess\""
    echo "KERNEL==\"hidraw*\", KERNELS==\"*$u:*\", MODE=\"0660\", TAG+=\"uaccess\""
  done
  for id in $PAD_IDS; do
    v=${id%:*}; p=${id#*:}
    u=$(printf '%s:%s' "$v" "$p" | tr 'a-f' 'A-F')
    echo "KERNEL==\"hidraw*\", ATTRS{idVendor}==\"$v\", ATTRS{idProduct}==\"$p\", MODE=\"0660\", TAG+=\"uaccess\""
    echo "KERNEL==\"hidraw*\", KERNELS==\"*$u*\", MODE=\"0660\", TAG+=\"uaccess\""
  done
} > /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules
chmod 644 /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules
udevadm control --reload 2>/dev/null
udevadm trigger --subsystem-match=hidraw --subsystem-match=misc 2>/dev/null
udevadm settle 2>/dev/null
n=$(grep -c 'ATTRS{idProduct}' /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules)
say "     Valve's controller list, plus $n more pads"
else
say "7/11  controller access: not selected"
rm -f /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules
grep -qs "$VALVE_MARK" /etc/udev/rules.d/60-steam-input.rules && rm -f /etc/udev/rules.d/60-steam-input.rules
udevadm control --reload 2>/dev/null
fi

# ---------------------------------------------------------------------------
if opt pad-xbox; then
say "8/11  pads from other makers presented as Xbox 360 pads"
# Re-emit non-Microsoft xpad pads as Xbox 360 (045e:028e) via uinput, for engines matching by USB IDs; grabs the physical node.
wait_apt; apt-get install -y python3-evdev >/dev/null 2>&1 || warn "python3-evdev did not install; the pad service will not start"
cat > /usr/local/sbin/steam-arm-pad-xbox <<'PADEOF'
#!/usr/bin/env python3
"""steam-arm-pad-xbox: present XInput-class pads from other makers as a Microsoft Xbox 360 pad.

Games identify controllers by USB vendor and product ID. A pad in XInput mode from 8BitDo,
PowerA and others is driven by the kernel's xpad driver and works like an Xbox pad, but carries
its maker's IDs, so engines without a profile for that exact model (Rewired, InControl, older
SDL, Wine's XInput) ignore it or show it as unknown. This service grabs every xpad device whose
vendor is not Microsoft and re-emits it through uinput as "Microsoft X-Box 360 pad" 045e:028e,
which every engine maps. The physical node stays grabbed so nothing sees the pad twice. Rumble
is not forwarded.
"""
import glob, os, threading, time
import evdev
from evdev import UInput, ecodes

XBOX360 = dict(vendor=0x045E, product=0x028E, version=0x0114, name="Microsoft X-Box 360 pad")
active = {}   # physical path -> thread

def is_target(dev):
    try:
        drv = os.path.basename(os.readlink("/sys/class/input/%s/device/device/driver" % os.path.basename(dev.path)))
    except OSError:
        return False
    return drv == "xpad" and dev.info.vendor != XBOX360["vendor"]

def caps_of(dev):
    caps = {}
    for etype, codes in dev.capabilities(absinfo=True).items():
        if etype in (ecodes.EV_SYN, ecodes.EV_FF):
            continue
        caps[etype] = codes
    return caps

def forward(path):
    try:
        dev = evdev.InputDevice(path)
        if not is_target(dev):
            return
        ui = UInput(caps_of(dev), name=XBOX360["name"], vendor=XBOX360["vendor"],
                    product=XBOX360["product"], version=XBOX360["version"], bustype=ecodes.BUS_USB)
        dev.grab()
        print("steam-arm-pad-xbox: %s (%04x:%04x '%s') -> %s" % (path, dev.info.vendor, dev.info.product, dev.name, ui.device.path), flush=True)
        for ev in dev.read_loop():
            ui.write_event(ev)
    except OSError:
        pass
    finally:
        try: ui.close()
        except Exception: pass
        print("steam-arm-pad-xbox: %s gone" % path, flush=True)
        active.pop(path, None)

def main():
    while True:
        for path in glob.glob("/dev/input/event*"):
            if path in active:
                continue
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            if is_target(dev):
                dev.close()
                t = threading.Thread(target=forward, args=(path,), daemon=True)
                active[path] = t
                t.start()
            else:
                dev.close()
        time.sleep(2)

if __name__ == "__main__":
    main()
PADEOF
chmod 755 /usr/local/sbin/steam-arm-pad-xbox
cat > /etc/systemd/system/steam-arm-pad-xbox.service <<'UNIT'
[Unit]
Description=Present XInput pads from other makers as Xbox 360 pads
After=systemd-udevd.service
[Service]
ExecStart=/usr/local/sbin/steam-arm-pad-xbox
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now steam-arm-pad-xbox >/dev/null 2>&1 && echo "  steam-arm-pad-xbox running" || warn "steam-arm-pad-xbox did not start (python3-evdev missing?)"
else
say "8/11  pads presented as Xbox 360 pads: not selected"
systemctl disable --now steam-arm-pad-xbox >/dev/null 2>&1
rm -f /usr/local/sbin/steam-arm-pad-xbox /etc/systemd/system/steam-arm-pad-xbox.service; systemctl daemon-reload
fi

# ---------------------------------------------------------------------------
S="$ARMHOME/.local/share/Steam"; D="$S/steamrtarm64"
# x86 client helper first: native client check below and the launcher use it.
cat > /usr/local/lib/steam-arm-x86client.py <<'X86PY'
#!/usr/bin/env python3
"""steam-arm x86 client helper: Valve's x86 client through FEX on CPUs without Armv8.1 atomics.

  bootstrap ZIP S       x86 bootstrap package (steam_ubuntu12) into client folder S: steam.sh,
                        ubuntu12_32/steam and the files beside them; programs and scripts 755, rest 644.
  runtime ZIP S         x86 runtime package (runtime_scout_ubuntu12) into S: ubuntu12_32/steam-runtime.tar.xz
                        and its checksum, unpacked by steam.sh at start.
  prepare S ARMHOME     edits for the x86 client, at every start (no change when already in place):
                        webhelper start script gets --enable-features=NetworkServiceInProcess2 (network
                        service in the browser process, so the client's process check passes);
                        launch wrapper moved to <name>.real, stand-in runs steam-arm launch handler first;
                        FEX app settings steamwebhelper.json and exe.json: thunks off (client window on CPU);
                        update channel file of native client moved aside (package/beta.steam-arm-arm64);
                        private copy of host libX11 (ARMHOME/.fex-emu/hostlib) whose default X error
                        handler returns, so an X error (GLXBadFBConfig, BadDrawable) no longer ends client.
  restore S ARMHOME     undoes prepare where files are unchanged since; prints what it put back.
  reset S ARMHOME arm64|x86
                        client type switch: next start of that client checks its files once; arm64 also
                        drops package records of both clients, so native client downloads its files again.
  probe ZIP [--run]     native client package (bins_linuxarm64_linuxarm64): "lse" when its programs hold
                        Armv8.1 atomic instructions outside outline-atomics helpers, else "ok"; --run (CPU
                        without atomics) also starts its client once: SIGILL gives "lse". "err <why>" when
                        the check cannot run.
Record <file>.steam-arm-sha beside the edited webhelper script holds sha256 of the edited text."""
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import zipfile

FLAG = " --enable-features=NetworkServiceInProcess2"
WEBHELPER = "ubuntu12_64/steamwebhelper.sh"
WRAP_LINE = re.compile(r'^(\s*"\$\{DIR\}/steamwebhelper_sniper_wrap\.sh" "\$@")[ \t]*$', re.M)
WRAPPERS = ("ubuntu12_32/steam-launch-wrapper", "steamrt64/steam-launch-wrapper")
MARK = "# steam-arm stand-in"
PY = "/usr/local/lib/steam-arm-python3"
RUN = "/usr/local/lib/steam-arm-run.py"
APPCFG = ("steamwebhelper.json", "exe.json")
APPCFG_TEXT = '{"ThunksDB":{"GL":0,"Vulkan":0}}\n'
BETA_SAVE = "package/beta.steam-arm-arm64"
X11_SRC = "/usr/lib/aarch64-linux-gnu/libX11.so.6"
HOSTLIB = ".fex-emu/hostlib"
# bti c; mov w0, #0; ret: X error handler returns to caller instead of exit
X11_STUB = bytes.fromhex("5f2403d5" "00008052" "c0035fd6")
# launcher markers in client home: x86 client files checked once; native client to check its files at next start
X86_OK = ".config/steam-arm/x86-verified"
NATIVE_VERIFY = ".config/steam-arm/native-verify"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def put(path, data, mode):
    """Atomic write through a temp file in the same folder."""
    fd, t = tempfile.mkstemp(prefix=".steam-arm-", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(t, mode)
        os.replace(t, path)
    except BaseException:
        if os.path.exists(t):
            os.unlink(t)
        raise


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def stand_in(real):
    return ("#!/bin/sh\n%s: Valve's launch wrapper (%s) started through steam-arm launch handler.\n"
            'exec env -u LD_PRELOAD %s %s --client x86 --preload "${LD_PRELOAD-}" -- %s "$@"\n'
            % (MARK, os.path.basename(real), PY, RUN, shlex.quote(real)))


def elf_func(data, name):
    """(file offset, size) of function symbol name in a 64-bit little-endian aarch64 ELF, else None."""
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1 or struct.unpack_from("<H", data, 18)[0] != 183:
        return None
    phoff, = struct.unpack_from("<Q", data, 32)
    phentsize, phnum = struct.unpack_from("<HH", data, 54)
    loads = []
    for k in range(phnum):
        ptype, _fl, off, va, _pa, filesz = struct.unpack_from("<IIQQQQ", data, phoff + k * phentsize)
        if ptype == 1:
            loads.append((va, off, filesz))
    shoff, = struct.unpack_from("<Q", data, 40)
    shentsize, shnum = struct.unpack_from("<HH", data, 58)
    secs = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + k * shentsize) for k in range(shnum)] if shoff else []
    want = name.encode()
    for typ in (11, 2):
        for _n, t, _f, _a, off, size, link, _i, _al, ent in secs:
            if t != typ or not ent or link >= len(secs):
                continue
            stroff = secs[link][4]
            for k in range(size // ent):
                st_name, st_info, _o, _sh, value, ssize = struct.unpack_from("<IBBHQQ", data, off + k * ent)
                if st_info & 0xF != 2 or not value:
                    continue
                e = data.find(b"\0", stroff + st_name)
                if data[stroff + st_name:e] != want:
                    continue
                for va, fo, fs in loads:
                    if va <= value < va + fs:
                        return value - va + fo, ssize
    return None


def x11_copy(armhome):
    """Private libX11 with non-fatal default X error handler; None when done or nothing to do, else warning text."""
    try:
        data = open(os.path.realpath(X11_SRC), "rb").read()
    except OSError:
        return None
    d = os.path.join(armhome, HOSTLIB)
    dst = os.path.join(d, "libX11.so.6")
    rec = dst + ".steam-arm-src"
    h = sha(data)
    try:
        if open(rec).read().strip() == h and os.path.isfile(dst):
            return None
    except OSError:
        pass
    f = elf_func(data, "_XDefaultError")
    if not f or (f[1] and f[1] < len(X11_STUB)):
        for p in (dst, rec):
            if os.path.isfile(p):
                os.unlink(p)
        return "host libX11 has no _XDefaultError to change; an X error may end x86 client"
    os.makedirs(d, exist_ok=True)
    put(dst, data[:f[0]] + X11_STUB + data[f[0] + len(X11_STUB):], 0o644)
    put(rec, (h + "\n").encode(), 0o644)
    print("x86 client: private libX11 copy (%s): X errors no longer end client" % HOSTLIB)
    return None


def reset(s, armhome, kind):
    done = []
    for rel in (X86_OK, NATIVE_VERIFY):
        p = os.path.join(armhome, rel)
        if os.path.isfile(p):
            os.unlink(p)
    if kind == "arm64":
        # package records of both clients: native bootstrap installs its files again (shared folders were x86 builds)
        pk = os.path.join(s, "package")
        try:
            names = sorted(os.listdir(pk))
        except OSError:
            names = []
        for n in names:
            if n.startswith("steam_client_") and (n.endswith("ubuntu12.installed") or n.endswith("ubuntu12.manifest")
                                                  or n.endswith("linuxarm64.installed")):
                os.unlink(os.path.join(pk, n))
                done.append(n)
        p = os.path.join(armhome, NATIVE_VERIFY)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        put(p, b"native client checks its files at next start (switch from x86 client)\n", 0o644)
        print("native client checks and downloads its files at next start%s"
              % (" (package records removed: %s)" % ", ".join(done) if done else ""))
    return 0


def unpack(zpath, s, what):
    z = zipfile.ZipFile(zpath)
    n = 0
    for i in z.infolist():
        name = i.filename.replace("\\", "/")
        if name.endswith("/"):
            continue
        if name.startswith("/") or ".." in name.split("/") or i.external_attr >> 16 & 0o170000 == 0o120000:
            raise SystemExit("%s package member refused: %s" % (what, name))
        dst = os.path.join(s, name)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        data = z.read(i)
        exe = data[:4] == b"\x7fELF" or data[:2] == b"#!"
        put(dst, data, 0o755 if exe else 0o644)
        n += 1
    return n


def bootstrap(zpath, s):
    n = unpack(zpath, s, "bootstrap")
    if not os.path.isfile(os.path.join(s, "steam.sh")) or not is_elf(os.path.join(s, "ubuntu12_32/steam")):
        raise SystemExit("bootstrap package lacks steam.sh or ubuntu12_32/steam (Valve may have changed its layout)")
    print("  x86 client bootstrap: %d files" % n)


def runtime(zpath, s):
    n = unpack(zpath, s, "runtime")
    rt = os.path.join(s, "ubuntu12_32/steam-runtime.tar.xz")
    if not os.path.isfile(rt) or not os.path.isfile(rt + ".checksum"):
        raise SystemExit("runtime package lacks ubuntu12_32/steam-runtime.tar.xz or its checksum"
                         " (Valve may have changed its layout)")
    print("  x86 client runtime: %d files" % n)


def prepare(s, armhome):
    warn = []
    # 1. webhelper start script
    p = os.path.join(s, WEBHELPER)
    if os.path.isfile(p):
        t = open(p, "rb").read().decode("utf-8", "surrogateescape")
        if FLAG not in t:
            m = list(WRAP_LINE.finditer(t))
            if len(m) == 1:
                t = t[:m[0].end(1)] + FLAG + t[m[0].end(1):]
                b = t.encode("utf-8", "surrogateescape")
                put(p, b, os.stat(p).st_mode & 0o7777)
                put(p + ".steam-arm-sha", (sha(b) + "\n").encode(), 0o644)
                print("x86 client: %s: network service in browser process" % WEBHELPER)
            else:
                warn.append("steamwebhelper.sh changed by Valve; transport dialog may appear at start")
        elif not os.path.exists(p + ".steam-arm-sha"):
            put(p + ".steam-arm-sha", (sha(t.encode("utf-8", "surrogateescape")) + "\n").encode(), 0o644)
    # 2. launch wrapper stand-ins
    for rel in WRAPPERS:
        w = os.path.join(s, rel)
        if not os.path.lexists(w):
            continue
        real = w + ".real"
        if is_elf(w) and not os.path.islink(w):
            os.replace(w, real)
        elif not os.path.isfile(real):
            continue
        want = stand_in(real).encode()
        try:
            cur = open(w, "rb").read()
        except OSError:
            cur = b""
        if cur and MARK.encode() not in cur:
            warn.append("%s is not Valve's program nor stand-in; left as it is" % rel)
            continue
        if cur != want:
            put(w, want, 0o755)
            print("x86 client: %s: stand-in runs launch handler" % rel)
    # 3. FEX app settings (own content only)
    d = os.path.join(armhome, ".fex-emu/AppConfig")
    for n in APPCFG:
        f = os.path.join(d, n)
        try:
            cur = open(f).read()
        except OSError:
            cur = None
        if cur is None:
            os.makedirs(d, exist_ok=True)
            put(f, APPCFG_TEXT.encode(), 0o644)
            print("x86 client: FEX app setting %s: thunks off" % n)
        elif cur != APPCFG_TEXT:
            try:
                ok = json.loads(cur).get("ThunksDB") == {"GL": 0, "Vulkan": 0}
            except (ValueError, AttributeError):
                ok = False
            if not ok:
                warn.append("FEX app setting %s holds other settings; left as it is (client window may fail)" % n)
    # 4. update channel file of native client, once
    b = os.path.join(s, "package/beta")
    if os.path.isfile(b) and os.path.isfile(os.path.join(s, "steamrtarm64/steam")) \
            and not os.path.lexists(os.path.join(s, BETA_SAVE)):
        os.replace(b, os.path.join(s, BETA_SAVE))
        print("x86 client: update channel of native client set aside (%s)" % BETA_SAVE)
    # 5. private libX11 copy (launcher puts it first in library path)
    x = x11_copy(armhome)
    if x:
        warn.append(x)
    for x in warn:
        print("warning: " + x)
    return 1 if warn else 0


def restore(s, armhome):
    done = []
    p = os.path.join(s, WEBHELPER)
    rec = p + ".steam-arm-sha"
    if os.path.isfile(rec):
        try:
            b = open(p, "rb").read()
            if open(rec).read().strip() == sha(b) and FLAG.encode() in b:
                put(p, b.replace(FLAG.encode(), b"", 1), os.stat(p).st_mode & 0o7777)
                done.append("Valve's webhelper start script")
        except OSError:
            pass
        os.unlink(rec)
    for rel in WRAPPERS:
        w = os.path.join(s, rel)
        real = w + ".real"
        try:
            ours = MARK.encode() in open(w, "rb").read()
        except OSError:
            ours = not os.path.lexists(w)
        if ours and os.path.isfile(real):
            os.replace(real, w)
            done.append("Valve's launch wrapper (%s)" % rel.split("/")[0])
        elif is_elf(w) and not os.path.islink(real) and os.path.isfile(real):
            # client put its own program back: saved copy is stale
            os.unlink(real)
            done.append("old copy of launch wrapper removed (%s)" % rel.split("/")[0])
    for n in APPCFG:
        f = os.path.join(armhome, ".fex-emu/AppConfig", n)
        try:
            if open(f).read() == APPCFG_TEXT:
                os.unlink(f)
                done.append("FEX app setting %s removed" % n)
        except OSError:
            pass
    sv = os.path.join(s, BETA_SAVE)
    if os.path.isfile(sv):
        os.replace(sv, os.path.join(s, "package/beta"))
        done.append("update channel of native client")
    lib = os.path.join(armhome, HOSTLIB, "libX11.so.6")
    if os.path.isfile(lib + ".steam-arm-src"):
        for p in (lib, lib + ".steam-arm-src"):
            if os.path.isfile(p):
                os.unlink(p)
        try:
            os.rmdir(os.path.dirname(lib))
        except OSError:
            pass
        done.append("private libX11 copy removed")
    if done:
        print(", ".join(done))
    return 0


# A64 encodings of Armv8.1 atomics (LSE): LDADD/LDCLR/LDEOR/LDSET/LDSMAX../SWP class, CAS, CASP.
LSE = ((0x3F200C00, 0x38200000), (0x3FA07C00, 0x08A07C00), (0xBFA07C00, 0x08207C00))


def byte_class(mask, value, shift):
    m, v = (mask >> shift) & 0xFF, (value >> shift) & 0xFF
    return b"[" + b"".join(re.escape(bytes([c])) for c in range(256) if c & m == v) + b"]"


LSE_RE = [re.compile(b"(?=" + b"".join(byte_class(m, v, 8 * k) for k in range(4)) + b")", re.S) for m, v in LSE]


def guarded(words, i):
    """Outline-atomics helper shape: ldrb wN then cbz/cbnz wN (N = 16 or 17) just before the instruction."""
    for j in range(max(0, i - 4), i):
        w = words[j]
        if w & 0xFE000000 == 0x34000000 and w & 0x1F in (16, 17):
            r = w & 0x1F
            for k in range(max(0, j - 3), j):
                if words[k] & 0xFFC00000 == 0x39400000 and words[k] & 0x1F == r:
                    return True
    return False


def data_spans(data, secs):
    """File offset spans of data inside code sections: $d mapping symbols and object symbols (symtab, else dynsym)."""
    spans = []
    for want in (2, 11):
        tabs = [s for s in secs if s[1] == want]
        if not tabs:
            continue
        for _n, _t, _f, _a, off, size, link, ent in tabs:
            strs = secs[link]
            marks = {}
            for k in range(size // (ent or 24)):
                name, info, _o, shndx, value, ssize = struct.unpack_from("<IBBHQQ", data, off + k * (ent or 24))
                if shndx >= len(secs) or not secs[shndx][2] & 4:
                    continue
                base = secs[shndx][4] - secs[shndx][3]
                if info & 0xF == 1 and ssize:
                    spans.append((value + base, value + base + ssize))
                s0 = strs[4] + name
                if data[s0:s0 + 2] in (b"$d", b"$x") and data[s0 + 2:s0 + 3] in (b"\0", b"."):
                    marks.setdefault(shndx, []).append((value, data[s0 + 1:s0 + 2]))
            for shndx, m in marks.items():
                m.sort()
                end = secs[shndx][3] + secs[shndx][5]
                for i, (v, kind) in enumerate(m):
                    if kind == b"d":
                        base = secs[shndx][4] - secs[shndx][3]
                        spans.append((v + base, (m[i + 1][0] if i + 1 < len(m) else end) + base))
        break
    return spans


def code_ranges(data):
    """(offset, size) of executable sections; executable segments when the file has no section table."""
    shoff, = struct.unpack_from("<Q", data, 40)
    shentsize, shnum = struct.unpack_from("<HH", data, 58)
    r = []
    if shoff and shnum:
        secs = []
        for k in range(shnum):
            n, t, f, a, o, sz, ln, _i, _al, ent = struct.unpack_from("<IIQQQQIIQQ", data, shoff + k * shentsize)
            secs.append((n, t, f, a, o, sz, ln, ent))
        for _n, stype, flags, _a, off, size, _l, _e in secs:
            if stype == 1 and flags & 4:
                r.append((off, size))
        return r, data_spans(data, secs)
    phoff, = struct.unpack_from("<Q", data, 32)
    phentsize, phnum = struct.unpack_from("<HH", data, 54)
    for k in range(phnum):
        ptype, flags, off, _va, _pa, filesz = struct.unpack_from("<IIQQQQ", data, phoff + k * phentsize)
        if ptype == 1 and flags & 1:
            r.append((off, filesz))
    return r, []


def lse_hits(data):
    """Unguarded LSE instructions in code of a 64-bit little-endian aarch64 ELF (data tables skipped)."""
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1 or struct.unpack_from("<H", data, 18)[0] != 183:
        return 0
    n = 0
    ranges, spans = code_ranges(data)
    for off, size in ranges:
        seg = data[off:off + size]
        base = off & 3
        cand = sorted({m.start() for r in LSE_RE for m in r.finditer(seg) if (m.start() + base) % 4 == 0})
        if not cand:
            continue
        a = (4 - base) % 4
        words = struct.unpack_from("<%dI" % ((len(seg) - a) // 4), seg, a)
        for c in cand:
            if not guarded(words, (c - a) // 4) and not any(lo <= off + c < hi for lo, hi in spans):
                n += 1
    return n


def run_client(z):
    # unpacked client and its temp HOME removed on every result
    d = tempfile.mkdtemp(prefix="steam-arm-probe.")
    try:
        return run_client_in(z, d)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def run_client_in(z, d):
    names = [i for i in z.infolist() if i.filename.replace("\\", "/").startswith("steamrtarm64/")]
    for i in names:
        name = i.filename.replace("\\", "/")
        if name.endswith("/") or ".." in name.split("/"):
            continue
        dst = os.path.join(d, name)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(z.read(i))
        os.chmod(dst, 0o755)
    exe = os.path.join(d, "steamrtarm64/steam")
    if not os.path.isfile(exe):
        return "err client program missing in package"
    home = os.path.join(d, "home")
    os.mkdir(home)
    env = {"HOME": home, "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LD_LIBRARY_PATH": os.path.dirname(exe)}
    p = subprocess.Popen([exe, "-shutdown"], cwd=os.path.dirname(exe), env=env, stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        # still running after 20 s without SIGILL: started; stopped gracefully
        os.killpg(p.pid, signal.SIGTERM)
        try:
            p.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            return "err client did not stop after SIGTERM (pid %d)" % p.pid
        return "ok"
    text = out.decode("utf-8", "replace")
    if p.returncode in (-signal.SIGILL, 128 + signal.SIGILL) or "Illegal instruction" in text:
        return "lse"
    if p.returncode == 127 or "error while loading shared libraries" in text:
        return "err client could not load its libraries"
    # only a clean exit counts as started; other signals and statuses keep the x86 client
    if p.returncode < 0:
        return "err client stopped by signal %d" % -p.returncode
    if p.returncode:
        return "err client exit status %d" % p.returncode
    return "ok"


def probe(zpath, run):
    try:
        z = zipfile.ZipFile(zpath)
        hits = 0
        for i in z.infolist():
            name = i.filename.replace("\\", "/")
            if name.startswith("steamrtarm64/") and not name.endswith("/") and i.file_size > 64:
                hits += lse_hits(z.read(i))
    except (OSError, zipfile.BadZipFile, struct.error) as e:
        return "err %s" % e
    if hits:
        return "lse"
    return run_client(z) if run else "ok"


def main(a):
    if len(a) == 3 and a[0] == "bootstrap":
        bootstrap(a[1], a[2])
        return 0
    if len(a) == 3 and a[0] == "runtime":
        runtime(a[1], a[2])
        return 0
    if len(a) == 3 and a[0] == "prepare":
        return prepare(a[1], a[2])
    if len(a) == 3 and a[0] == "restore":
        return restore(a[1], a[2])
    if len(a) == 4 and a[0] == "reset" and a[3] in ("arm64", "x86"):
        return reset(a[1], a[2], a[3])
    if len(a) in (2, 3) and a[0] == "probe" and (len(a) == 2 or a[2] == "--run"):
        print(probe(a[1], len(a) == 3))
        return 0
    sys.stderr.write("usage: steam-arm-x86client.py bootstrap ZIP S | runtime ZIP S | prepare S ARMHOME | restore S ARMHOME"
                     " | reset S ARMHOME arm64|x86 | probe ZIP [--run]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
X86PY
chmod 644 "$X86PY"
CLIENT_PREV=$(conf_get CLIENT)
# client type this client home held (settings file CLIENT may belong to another account)
FOLDER_PREV=$(folder_client)
CLIENT_PROBE=$(conf_get CLIENT_PROBE)
# x86 client by CPU rule: native client checked whenever Valve's manifest names a build not checked yet.
if [ "$CLIENT" = x86 ] && [ "$CLIENT_SET" = auto ]; then
  say "9/11  native client check (CPU without Armv8.1 atomics)"
  if native_probe "$CLIENT_PROBE"; then
    CLIENT_PROBE="$PKG_VER:$PROBE"
    po=; [ "$PROBE_OLD" = 1 ] && po=" (checked before)"
    if [ "$PROBE" = ok ]; then
      echo "  native client $PKG_VER runs on this CPU again$po; switching back to native ARM64 client"
      CLIENT=arm64
      for t in "$RFS" "$MALI"; do rfs_bwrap_on "$t" && echo "  x86 bwrap in $t put back (native client)"; done
    else
      echo "  native client $PKG_VER still needs Armv8.1$po (steam-for-linux #13288); x86 client stays"
    fi
  else
    CLIENT_PROBE="${PKG_VER:-0}:err"
    warn "native client check failed ($DL_ERR); x86 client stays"
  fi
fi
if [ "$CLIENT" = x86 ]; then
say "9/11  client package (x86, ubuntu12) into $ARMHOME"
echo "  installed games, sign-in and settings are kept; only client program files are ever replaced"
as_user mkdir -p "$S" || die "could not create $S as '$GAMEUSER'. Check that this account owns its home folder, then run this again."
# Switch from native client: first x86 start checks files (native package left files of the same names).
if [ "$FOLDER_PREV" != x86 ]; then as_user python3 "$X86PY" reset "$S" "$ARMHOME" x86 >/dev/null; fi
# file 5.4x prints "Intel i386", older releases "Intel 80386"
if [ -x "$S/ubuntu12_32/steam" ] && [ -f "$S/steam.sh" ] && file -b "$S/ubuntu12_32/steam" | grep -qE 'Intel (80386|i386)'; then
  echo "  x86 client present; keeping it (the client updates itself)"
else
  # Bootstrap package into a root-owned stage; the game account writes its files into the client folder.
  client_dl "$MANIFEST_X86" steam_ubuntu12 || die "$DL_ERR"
  steam_up && steam_up_die
  as_user python3 "$X86PY" bootstrap "$STAGE/client.zip" "$S" \
    || die "x86 client bootstrap could not be unpacked into $S (disk full?). Free some space, then run this again."
fi
# steam.sh unpacks ubuntu12_32/steam-runtime.tar.xz at start; bootstrap package lacks it.
if [ -f "$S/ubuntu12_32/steam-runtime.tar.xz" ] && [ -f "$S/ubuntu12_32/steam-runtime.tar.xz.checksum" ]; then
  echo "  x86 client runtime present"
else
  client_dl "$MANIFEST_X86" runtime_scout_ubuntu12 || die "$DL_ERR"
  steam_up && steam_up_die
  as_user python3 "$X86PY" runtime "$STAGE/client.zip" "$S" \
    || die "x86 client runtime could not be unpacked into $S (disk full?). Free some space, then run this again."
fi
else
say "9/11  client package (linuxarm64) into $ARMHOME"
echo "  installed games, sign-in and settings are kept; only the client program folder is ever replaced"
echo "  first start moves the client to its own ARM update channel"
as_user mkdir -p "$S" || die "could not create $S as '$GAMEUSER'. Check that this account owns its home folder, then run this again."
# Switch back from x86 client: Valve's files it edited put back (no-op when unchanged by it).
if [ "$FOLDER_PREV" = x86 ]; then
  x=$(as_user python3 "$X86PY" restore "$S" "$ARMHOME") && [ -n "$x" ] && echo "  x86 client edits put back: $x"
  # x86 client replaced shared client files: native client checks and downloads its own at next start
  x=$(as_user python3 "$X86PY" reset "$S" "$ARMHOME" arm64) && [ -n "$x" ] && echo "  $x"
fi
if [ -x "$D/steam" ] && file -b "$D/steam" | grep -q aarch64; then
  echo "  client present ($(head -1 "$D/builddate.txt" 2>/dev/null | tr -d '\r')); keeping it (the client updates itself)"
else
  # Download into a root-owned folder, then the game user unpacks it into a new folder and swaps it in.
  client_dl "$MANIFEST" bins_linuxarm64_linuxarm64 || die "$DL_ERR"
  NEW=$(as_user mktemp -d "$S/.steamrtarm64-new.XXXXXX") || die "could not create a folder in $S; free some space and run this again"
  UCLEANUP+=("$NEW")
  # Archive has steamrtarm64/ prefix with backslash separators; unzip would create literal backslash names.
  as_user python3 - "$STAGE/client.zip" "$NEW" <<'PY' || die "client package could not be unpacked into $S (disk full?). Free some space, then run this again."
import os, sys, zipfile
zpath, root = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(zpath); n = 0
for i in z.infolist():
    name = i.filename.replace("\\", "/")
    if name.endswith("/") or name.startswith("/") or ".." in name.split("/"): continue
    dst = os.path.join(root, name); os.makedirs(os.path.dirname(dst), exist_ok=True)
    with z.open(i) as src, open(dst, "wb") as out: out.write(src.read())
    mode = i.external_attr >> 16
    if mode: os.chmod(dst, mode & 0o755)   # archive modes are group/world writable
    n += 1
print("  extracted %d files" % n)
PY
  # archive modes are unreliable; mark programs and scripts executable (as the game user, inside its own folder)
  # shellcheck disable=SC2016
  as_user find "$NEW" -type f -exec sh -c 'for f; do file -b "$f" | grep -qE "executable|shell script" && chmod 755 "$f"; done; true' sh {} +
  [ -x "$NEW/steamrtarm64/steam" ] || die "client program missing after unpacking (Valve may have changed the package layout). Run this again later; if it persists, report it."
  steam_up && steam_up_die
  # shellcheck disable=SC2016
  as_user sh -c 'rm -rf "$2" && mv "$1/steamrtarm64" "$2" && rmdir "$1"' sh "$NEW" "$D" \
    || die "could not put the new client folder in place at $D. Free some space, then run this again."
fi
fi
as_user mkdir -p "$ARMHOME/${CLIENT_REC%/*}" && printf '%s\n' "$CLIENT" | user_write "$ARMHOME/$CLIENT_REC" \
  || warn "could not write $ARMHOME/$CLIENT_REC"
# Marker: --remove deletes this folder only when it carries this file; a folder that held other files gets none.
if [ -f "$ARMHOME/.steam-arm-client" ]; then :
elif [ "$ARMHOME_MARK" = 1 ]; then
  printf 'Steam ARM client folder (games, sign-in, settings); steam-arm-setup --remove asks before deleting it.\n' \
    | user_write "$ARMHOME/.steam-arm-client" || warn "could not write $ARMHOME/.steam-arm-client"
else
  echo "  $ARMHOME held other files before setup: --remove keeps this folder"
fi
# the -deckard client reads a VR runtime registry; an empty one keeps it quiet
as_user mkdir -p "$ARMHOME/.config/openvr"
if [ ! -e "$ARMHOME/.config/openvr/openvrpaths.vrpath" ] && [ ! -L "$ARMHOME/.config/openvr/openvrpaths.vrpath" ]; then
  user_write "$ARMHOME/.config/openvr/openvrpaths.vrpath" <<'JSON'
{
  "config": [],
  "external_drivers": null,
  "jsonid": "vrpathreg",
  "log": [],
  "runtime": [],
  "version": 1
}
JSON
fi

# ---------------------------------------------------------------------------
say "10/11  launcher, configuration, menu entry"
mkdir -p /etc/steam-arm
conf_set ARMHOME_DIR "$ARMHOME_DIR"
conf_set GAMEUSER "$GAMEUSER"
conf_set ARMHOME_FOREIGN "$ARMHOME_FOREIGN"
CONF_ON=; CONF_OFF=
for c in $COMPONENTS; do if opt "$c"; then CONF_ON="$CONF_ON${CONF_ON:+,}$c"; else CONF_OFF="$CONF_OFF${CONF_OFF:+,}$c"; fi; done
conf_set COMPONENTS_ON "$CONF_ON"
conf_set COMPONENTS_OFF "$CONF_OFF"
conf_set COMPONENTS_USER_SET "$(printf '%s' "$USER_SET" | tr -s ',' | sed 's/^,//; s/,$//')"
conf_set COMPONENTS_FAMILY "$GPU_FAMILY"
# GPU family for the launch handler's graphics rules; GPU_FAMILY_SET=user keeps a hand-picked family for later runs.
conf_set GPU_FAMILY "$GPU_FAMILY"
conf_set GPU_FAMILY_SET "$GPU_SRC"
# Graphics for x86 titles: auto = forwarding plus the handler's rules; a (or forward) = forwarding only; b = every title on Mali drivers.
[ -n "$(conf_get GFX_DEFAULT)" ] || conf_set GFX_DEFAULT auto
conf_set VERSION "$SA_VERSION"
# Client type (machine state, not in settings backups): arm64 or x86, auto or user, last native check.
conf_set CLIENT "$CLIENT"
conf_set CLIENT_SET "$CLIENT_SET"
if [ -n "$CLIENT_PROBE" ]; then conf_set CLIENT_PROBE "$CLIENT_PROBE"; fi
# Page size override used on a non-4K kernel: kept so the launcher and later runs honour it.
if [ "$PAGESIZE" != 4096 ] && [ "$PS_IGNORE" = 1 ]; then conf_set STEAM_ARM_IGNORE_PAGESIZE 1; else conf_del STEAM_ARM_IGNORE_PAGESIZE; fi
# Launch handler: replaces the FEX tool's LD_PRELOAD deletion; picks overlay/MangoHud/engine fixes per title.
cat > /usr/local/lib/steam-arm-handler.py <<'HANDLERPY'
#!/usr/bin/env python3
"""steam-arm launch handler.

Valve's FEX compatibility tool (fex-compat-tool, patched by steam-arm-setup) runs this file in
place of its own `del os.environ['LD_PRELOAD']`, before the runtime container starts. It works
on the tool's os.environ and sys.argv and decides per title:

  Steam overlay   x86 overlay core by default; `vulkan` adds the arm64 core and the arm64
                  overlay Vulkan layer (for Vulkan titles, whose frames x86 core never sees);
                  `off` removes both. The arm64 core stops OpenGL titles from starting, so it
                  is never loaded unless asked for.
  MangoHud        loaded when title asks for it: `mangohud %command%`, `MANGOHUD=1`, or profile.
  Engine fixes    Godot 4 titles: OpenGL renderer and GL 3.3 report (Vulkan renderer freezes on
                  splash; Panfrost reports GL 3.1, Godot's OpenGL renderer needs 3.3).
                  Godot 3 titles: GL 3.3 report (GLES3 renderer needs 3.3). Godot version from
                  .pck beside game or PCK embedded in its executable; Windows builds under x86
                  Proton left alone.
                  32-bit Unity players: Steam overlay off (the title stops when it attaches).
                  64-bit Unity players with a Vulkan renderer: -force-vulkan (Unity's OpenGL core
                  context needs a newer GL than Panfrost offers); overlay mode for Vulkan titles.
                  Other Unity 5+ players: GL 4.5 report, so the core context is created.
                  Java titles with LWJGL 2: -DLWJGL_DISABLE_XRANDR=true added to JAVA_TOOL_OPTIONS.
                  Source 2 titles: warning only.
                  32-bit Source titles: start skipped once, with notice, when automatic Windows
                  build applies and launcher has not set it yet (steam-arm-autobuild.py).
  Graphics        Forwarding (GL/Vulkan thunks to host GPU drivers) by default. Mali drivers
                  inside the emulation (gpu-in-emulation, second RootFS tree) when installed,
                  GPU_FAMILY in /etc/steam-arm/steam-arm.conf is a Mali family (panfrost/panthor), and:
                  Java title (Java runtime in game folder; Java 21+ also gets FEX Multiblock off),
                  or 32-bit title started with -vulkan/-force-vulkan (no 32-bit Vulkan thunk) on
                  mali-csf-v10 (panvk loads by default only there).
                  Otherwise 32-bit -vulkan/-force-vulkan is removed (CPU renderer).
                  Profile gfx=a|b overrides (gfx=b on other GPU: warning, forwarding). GFX_DEFAULT in
                  /etc/steam-arm/steam-arm.conf: auto (or empty) = these rules; a (or forward) = every
                  title on forwarding; b = every title on the second tree (Mali GPU only).
                  Second tree from a custom driver archive (marker "custom"): gfx=b and GFX_DEFAULT=b
                  on any GPU family; automatic rules stay Mali-only.
  Kept settings   A value a rule would set that launch options or the environment already set
                  stays, with a "launch option kept" log line naming both values (FEX Multiblock
                  too, from a launch-option FEX_APP_CONFIG; Steam's own FEX setting is no choice). Mali drivers inside the emulation need thunks off and their own graphics
                  provider and GLX vendor; launch options for these are replaced, with an
                  "overridden for" log line. gl32=off sets GLX vendor mesa the same way.
                  FEX code cache: FEX_DISKCACHE, or DiskCache in a launch-option FEX_APP_CONFIG, wins.
  Code cache      diskcache=on: FEX code cache (FEX tool 2609.1 or newer only); titles with own JIT
                  (Java, Mono, .NET, LuaJIT, CEF) cache file-backed code only. Title's cache folder
                  ($STEAM_COMPAT_SHADER_PATH/fex-emu) deleted before start when FEX tool or game build
                  changed (stamp file .steam-arm-stamp inside it).
  Script launchers  Source engine style start scripts are followed to binary they name, for detection.
  x86 client      On CPUs without Armv8.1 atomics Valve's x86 client runs through system FEX; its launch
                  wrapper stand-in enters this handler through steam-arm-run.py (CLIENT_X86 set): same
                  rules, forwarding only (gfx=b falls back with a log line), no FEX code cache.
  GoldSrc titles  note only: renderer picked in the title's video options (Software draws on CPU).
  Compat check    note when Steam's saved tool for the title (config.vdf CompatToolMapping) names a
                  Proton build but this Linux build started; never writes that file.
  Renderer check  background thread: once the title loads a GL or Vulkan library, logs the GPU
                  device its processes hold ("renderer: GPU ..."), or "GPU forwarding not active:
                  rendering on CPU (llvmpipe)" when none is held. STEAM_ARM_RENDERER_CHECK=0 turns it off.
                  CPU_NOTICE=on in steam-arm.conf: CPU verdict also raises a desktop notice that stays
                  until closed (GoldSrc titles excluded).

Profiles, one title per line, later files override earlier ones:
  /usr/local/share/steam-arm/titles.conf      included with steam-arm-setup
  /etc/steam-arm/titles.conf                  system
  ~/.config/steam-arm/titles.conf              client home (HOME inside the launcher)
Line: <appid> key=value ...   keys: overlay=x86|vulkan|off  mangohud=on|off
      godot=gl|vulkan  unity=vulkan|gl  env=NAME=VALUE;NAME=VALUE  args=ARG;ARG
      gl32=off (32-bit title on emulated x86 Mesa, no GL thunk)  vk32=keep (keep -vulkan)
      gfx=a (forwarding)  gfx=b (Mali drivers inside the emulation)
      multiblock=on|off (FEX Multiblock; launch-option FEX_APP_CONFIG and Steam's FEX setting win)
      diskcache=on|off (FEX code cache, FEX tool 2609.1+; launch-option FEX_DISKCACHE / FEX_APP_CONFIG win)
Per-title launch options override profiles: STEAM_ARM_OVERLAY=x86|vulkan|off, and
STEAM_ARM_PRELOAD_KEEP=a,b (keep exactly LD_PRELOAD entries containing these substrings).
Every decision is printed to the tool's log, /tmp/fex-compat-tool-<pid>.log, readable by game account only."""
import atexit
import glob
import json
import os
import re
import runpy
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zipfile


def log(*a):
    # flushed: the renderer thread writes while the game runs
    print("steam-arm:", *a, flush=True)


def private_log():
    """Tool log in /tmp (Valve's tool creates it readable by all; environment follows): owner only."""
    try:
        fd = sys.stdout.fileno()
        st = os.fstat(fd)
        if (re.fullmatch(r"/tmp/fex-compat-tool-[0-9]+\.log", os.readlink("/proc/self/fd/%d" % fd))
                and st.st_uid == os.getuid() and st.st_mode & 0o077):
            os.fchmod(fd, 0o600)
    except (OSError, ValueError, AttributeError):
        pass


private_log()


def keep_env(k, want):
    """setdefault that logs when launch options or the environment already chose another value."""
    cur = os.environ.get(k)
    if cur is None:
        os.environ[k] = want
    elif cur != want:
        log("launch option kept: %s=%s (rule wanted %s)" % (k, cur, want))


APPID = os.environ.get("SteamAppId") or os.environ.get("SteamGameId") or ""
# x86 client: handler entered through steam-arm-run.py (launch wrapper stand-in), which sets this flag.
CLIENT_X86 = globals().get("CLIENT_X86", False)
PROFILE_FILES = ("/usr/local/share/steam-arm/titles.conf", "/etc/steam-arm/titles.conf",
                 os.path.join(os.path.expanduser("~"), ".config/steam-arm/titles.conf"))


def load_profile():
    prof = {}
    for path in PROFILE_FILES:
        try:
            lines = open(path).read().splitlines()
        except OSError:
            continue
        for line in lines:
            words = line.split("#", 1)[0].split()
            if len(words) > 1 and words[0] == APPID:
                for kv in words[1:]:
                    if "=" in kv:
                        k, v = kv.split("=", 1)
                        prof[k] = v
    return prof


def pck_header(f, off):
    """Engine major from PCK header at off (GDPC, format, major...), else None."""
    f.seek(off)
    h = f.read(12)
    if len(h) == 12 and h[:4] == b"GDPC":
        fmt, major = struct.unpack("<II", h[4:12])
        if fmt < 10 and 0 < major < 10:
            return major
    return None


def embedded_pck_major(path):
    """Engine major from PCK appended to executable ("Embed PCK" export): footer is uint64 size + GDPC."""
    try:
        with open(path, "rb") as f:
            end = f.seek(0, 2)
            if end < 24:
                return None
            f.seek(end - 12)
            t = f.read(12)
            if t[8:] != b"GDPC":
                return None
            size = struct.unpack("<Q", t[:8])[0]
            return pck_header(f, end - 12 - size) if size <= end - 24 else None
    except OSError:
        return None


def godot_major():
    """Engine major in Godot's own pack order: PCK embedded in the executable, <name>.pck beside it,
    then any .pck in its folder, the working folder or the folder of the last file argument."""
    exe = game_binary()
    major = embedded_pck_major(exe) if exe else None
    if major is not None:
        return major
    cands = [os.path.splitext(exe)[0] + ".pck"] if exe else []
    dirs = [os.path.dirname(exe)] if exe else []
    dirs.append(os.getcwd())
    for a in reversed(sys.argv):
        if os.path.isfile(a):
            dirs.append(os.path.dirname(os.path.abspath(a)))
            break
    for d in dirs:
        cands += sorted(glob.glob(os.path.join(glob.escape(d), "*.pck")))
    for p in cands:
        try:
            with open(p, "rb") as f:
                major = pck_header(f, 0)
        except OSError:
            continue
        if major is not None:
            return major
    return None


def is_elf(p):
    try:
        with open(p, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def script_target(path):
    """ELF in the script's own directory that a start script (hl2.sh style) names, else None."""
    try:
        with open(path, "rb") as f:
            if f.read(2) != b"#!":
                return None
            text = f.read(1 << 16).decode("utf-8", "replace")
    except OSError:
        return None
    d = os.path.dirname(os.path.abspath(path))
    found = []
    for m in re.finditer(r"[\w./+-]+", text):
        tok = m.group(0)
        # "$DIR"/game and "${DIR}/game": path relative to script
        if tok.startswith("/") and m.start() and text[m.start() - 1] in "\"}":
            tok = tok[1:]
        tok = tok[2:] if tok.startswith("./") else tok
        if not tok or tok.startswith("/") or ".." in tok.split("/") or re.search(r"\.so(\.|$)", tok) \
                or re.search(r"crash|report|breakpad|minidump", tok, re.I):
            continue
        p = os.path.join(d, tok)
        if p != os.path.abspath(path) and p not in found and os.path.isfile(p) and is_elf(p):
            found.append(p)
    # arch-switch scripts name both builds; FEX reports x86_64, so 64-bit one runs
    for p in found:
        try:
            with open(p, "rb") as f:
                if f.read(5)[4:5] == b"\x02":
                    return p
        except OSError:
            pass
    return found[-1] if found else None


def game_binary():
    """The title's own executable: last existing file on the command line that is an ELF,
    or the binary a start script there names."""
    for a in reversed(sys.argv):
        if os.path.isfile(a):
            if is_elf(a):
                return os.path.abspath(a)
            t = script_target(a)
            if t:
                return t
    return None


def source2():
    """True when the title's files carry Source 2's engine library (bin/linuxsteamrt64/libengine2.so)."""
    dirs = [os.getcwd()]
    exe = game_binary()
    if exe:
        dirs.append(os.path.dirname(exe))
    for a in reversed(sys.argv):
        if os.path.isfile(a):
            dirs.append(os.path.dirname(os.path.abspath(a)))
            break
    for d in dirs:
        for sub in ("", "bin/linuxsteamrt64", "game/bin/linuxsteamrt64"):
            if os.path.isfile(os.path.join(d, sub, "libengine2.so")):
                return True
    return False


# Own file with a random name (created exclusively); in /tmp because the runtime container shares only that with FEX.
APP_CFG = None


def fex_app_config(thunks=None, config=None):
    global APP_CFG
    """Merge ThunksDB/Config keys into FEX_APP_CONFIG (FEX's highest layer); keeps user's or tool's own keys."""
    cfg = {}
    user = os.environ.get("FEX_APP_CONFIG")
    if user:
        try:
            cfg = json.load(open(user))
        except (OSError, ValueError):
            cfg = {}
    else:
        # tool's own translation of Steam's FEX settings, which it skips once FEX_APP_CONFIG is set
        gen = getattr(sys.modules.get("__main__"), "generate_app_config", None)
        if callable(gen):
            cfg = gen()
    if not isinstance(cfg, dict):
        cfg = {}
    for key, add in (("ThunksDB", thunks), ("Config", config)):
        if add:
            if not isinstance(cfg.get(key), dict):
                cfg[key] = {}
            cfg[key].update(add)
    if APP_CFG is None:
        fd, path = tempfile.mkstemp(prefix="steam-arm-fex-app-config-", suffix=".json", dir="/tmp")
        os.close(fd)
        APP_CFG = path
        atexit.register(lambda: os.path.exists(path) and os.unlink(path))
    with open(APP_CFG, "w") as f:
        json.dump(cfg, f, indent=2)
    os.environ["FEX_APP_CONFIG"] = APP_CFG


def engine_info():
    """(engine, bits) for the title's executable. engine is 'unity' when the Unity player's
    <name>_Data folder (Managed or il2cpp data) sits beside it, else None."""
    exe = game_binary()
    if not exe:
        return None, None
    try:
        with open(exe, "rb") as f:
            bits = {1: 32, 2: 64}.get(f.read(5)[4])
    except OSError:
        bits = None
    d = os.path.dirname(exe)
    stem = os.path.splitext(os.path.basename(exe))[0]
    data = [os.path.join(d, stem + "_Data")] + glob.glob(os.path.join(d, "*_Data"))
    unity = any(os.path.isdir(os.path.join(p, "Managed")) or os.path.isdir(os.path.join(p, "il2cpp_data"))
                for p in data) or os.path.isfile(os.path.join(d, "UnityPlayer.so"))
    return ("unity" if unity else None), bits


def unity_legacy_gl():
    """True for Unity 4 players (<name>_Data/mainData): legacy OpenGL path, no core context."""
    exe = game_binary()
    if not exe:
        return False
    d = os.path.dirname(exe)
    return any(os.path.isfile(os.path.join(p, "mainData")) for p in glob.glob(os.path.join(d, "*_Data")))


def unity_has_vulkan():
    """True when the title's Unity player (UnityPlayer.so) carries the Vulkan renderer switch."""
    exe = game_binary()
    if not exe:
        return False
    p = os.path.join(os.path.dirname(exe), "UnityPlayer.so")
    try:
        with open(p, "rb") as f:
            while True:
                b = f.read(1 << 22)
                if b"force-vulkan" in b:
                    return True
                if len(b) < 1 << 22:
                    return False
                # full chunk: step back so string split across chunk boundary is found
                f.seek(-16, 1)
    except OSError:
        return False


# Second RootFS tree with Mali drivers inside the emulation (gpu-in-emulation; setup's MALI).
MALI_ROOT = "/opt/fex-rootfs/Ubuntu_24_04-mali"


def mali_ready():
    """True when the second tree is complete (setup writes its marker last)."""
    return os.path.isfile(MALI_ROOT + "/.steam-arm-mali") and os.path.isfile(MALI_ROOT + "/graphics_provider.json")


# GPU families the second tree's drivers cover (panfrost GL, panvk; G1 needs Mesa 26.2); panvk loads by default only on PANVK_FAMILIES.
MALI_FAMILIES = ("mali-csf-v10", "mali-csf-v11", "mali-csf-5thgen", "mali-csf", "mali-valhall-jm", "mali-bifrost", "mali-midgard", "mali-panfrost")
PANVK_FAMILIES = ("mali-csf-v10",)
# Drivers that outrank a Mali GPU in setup's detection (discrete, Adreno, Apple).
GPU_OUTRANK = ("amdgpu", "radeon", "nouveau", "nvidia", "i915", "xe", "msm", "msm_dpu", "msm_mdp", "mdp4", "asahi")
_GPU_FAMILY = None


def sysfs_gpu_family():
    """Mali family from render node driver and DT compatible; 'other' for other GPUs, 'none' without one."""
    fams = []
    for r in sorted(glob.glob("/sys/class/drm/renderD*")):
        try:
            drv = os.path.basename(os.readlink(r + "/device/driver"))
        except OSError:
            continue
        try:
            compat = open(r + "/device/of_node/compatible", "rb").read().decode("ascii", "replace")
        except OSError:
            compat = ""
        if drv in GPU_OUTRANK:
            return "other"
        if drv in ("panthor", "tyr"):
            fams.append("mali-csf-v10" if "rk3588-mali" in compat else "mali-csf-5thgen" if "mt8196-mali" in compat else "mali-csf")
        elif drv == "panfrost":
            fams.append("mali-valhall-jm" if "mali-valhall-jm" in compat else "mali-bifrost" if "mali-bifrost" in compat
                        else "mali-midgard" if "arm,mali-t" in compat else "mali-panfrost")
        elif drv not in ("vgem", "vkms"):
            fams.append("other")
    mali = [f for f in fams if f in MALI_FAMILIES]
    return mali[0] if mali else fams[0] if fams else "none"


def gpu_family():
    """GPU_FAMILY from /etc/steam-arm/steam-arm.conf (setup writes it), else sysfs check; cached."""
    global _GPU_FAMILY
    if _GPU_FAMILY is None:
        try:
            v = [l[11:].strip().strip("'\"") for l in open("/etc/steam-arm/steam-arm.conf").read().splitlines()
                 if l.startswith("GPU_FAMILY=")]
        except OSError:
            v = []
        _GPU_FAMILY = v[-1] if v and v[-1] else sysfs_gpu_family()
    return _GPU_FAMILY


def user_fex():
    """FEX settings chosen in launch options (a FEX_APP_CONFIG file); Steam's STEAM_COMPAT_FEX_CONFIG is its default, no choice."""
    p = os.environ.get("FEX_APP_CONFIG")
    if not p:
        return {}
    try:
        c = json.load(open(p))
    except (OSError, ValueError):
        c = {}
    return c if isinstance(c, dict) else {}


def fex_tool_ver():
    """(YYMM, point) of Valve's FEX tool from VERSIONS.txt beside the tool, None when unknown; FEX-2607-76-g... is (2607, 0)."""
    m = sys.modules.get("__main__")
    # runpy puts the handler path in sys.argv[0]; the tool script itself is __main__
    d = getattr(m, "g_fex_path", None) or os.path.dirname(os.path.abspath(getattr(m, "__file__", None) or "."))
    try:
        m = re.search(r"FEX-([0-9]{4})(?:\.([0-9]+))?", open(os.path.join(d, "VERSIONS.txt")).read())
    except OSError:
        return None
    return (int(m.group(1)), int(m.group(2) or 0)) if m else None


def fex_ver_str(v):
    return "FEX-%d" % v[0] + (".%d" % v[1] if v[1] else "")


# Libraries of runtimes that compile code at run time (their code is anonymous memory).
JIT_LIBS = (("mono", "libmono*-2.0.so*"), ("dotnet", "libcoreclr.so"), ("luajit", "libluajit-5.1.so*"), ("cef", "libcef.so"))


def own_jit():
    """Name of a JIT runtime in the title's folders (three levels deep), else None."""
    for d in game_dirs():
        for name, pat in JIT_LIBS:
            for depth in ("", "*", "*/*", "*/*/*"):
                if glob.glob(os.path.join(glob.escape(d), depth, pat)):
                    return name
    return None


def game_build():
    """Steam build id of the title from its appmanifest, 'unknown' when not found."""
    for v in ("STEAM_COMPAT_INSTALL_PATH", "STEAM_COMPAT_SHADER_PATH"):
        p = os.environ.get(v, "")
        if "/steamapps/" not in p:
            continue
        acf = os.path.join(p.split("/steamapps/")[0], "steamapps", "appmanifest_%s.acf" % APPID)
        try:
            m = re.search(r'"buildid"\s+"([0-9]+)"', open(acf, errors="replace").read())
        except OSError:
            continue
        if m:
            return m.group(1)
    return "unknown"


def tree_size(d):
    n = 0
    for root, _dirs, files in os.walk(d):
        for f in files:
            try:
                n += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return n


def human(n):
    for u in ("B", "K", "M", "G"):
        if n < 1024 or u == "G":
            return ("%d%s" if u == "B" else "%.1f%s") % (n, u)
        n /= 1024.0


STAMP = ".steam-arm-stamp"


def cache_stamp_check(want):
    """Delete this title's FEX cache folder when tool version or game build changed since last start."""
    base = os.environ.get("STEAM_COMPAT_SHADER_PATH")
    if not base:
        return
    d = os.path.join(base, "fex-emu")
    if os.path.islink(d):
        log("fex: code cache folder is a link, left alone: %s" % d)
        return
    try:
        have = open(os.path.join(d, STAMP)).read().strip()
    except OSError:
        have = None
    if have == want:
        return
    try:
        if os.path.isdir(d) and [f for f in os.listdir(d) if f != STAMP]:
            size = tree_size(d)
            shutil.rmtree(d)
            if have is None:
                why = "no stamp"
            else:
                o, n = have.split(" build=", 1) + ["?"], want.split(" build=", 1)
                why = ", ".join("%s %s -> %s" % (k, o[i], n[i]) for i, k in enumerate(("FEX tool", "game build")) if o[i] != n[i])
            log("fex: code cache of this title cleared (%s; %s freed)" % (why, human(size)))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, STAMP), "w") as f:
            f.write(want + "\n")
    except OSError as e:
        log("fex: code cache stamp not written:", e)


def set_env(k, want, why, default=()):
    """Set k; logs when launch options had chosen another value (values in default are the launcher's own)."""
    cur = os.environ.get(k)
    if cur is not None and cur != want and cur not in default:
        log("overridden for %s: %s=%s (now %s)" % (why, k, cur, want))
    os.environ[k] = want


def gfx_default():
    """GFX_DEFAULT from /etc/steam-arm/steam-arm.conf: 'auto' (auto or empty: rules decide), 'a' (a or forward:
    every title on forwarding) or 'b' (every title on the second tree); other values: rules, logged."""
    try:
        v = [l[12:] for l in open("/etc/steam-arm/steam-arm.conf").read().splitlines() if l.startswith("GFX_DEFAULT=")]
    except OSError:
        return "auto"
    v = v[-1].strip().strip("'\"") if v else ""
    if v in ("", "auto"):
        return "auto"
    if v in ("a", "forward"):
        return "a"
    if v == "b":
        return "b"
    log("graphics: GFX_DEFAULT=%s unknown, automatic rules apply (values: auto, a, b)" % v)
    return "auto"


def mali_custom():
    """True when the second tree comes from a custom driver archive (setup's marker starts with 'custom')."""
    try:
        return open(MALI_ROOT + "/.steam-arm-mali").read().startswith("custom ")
    except OSError:
        return False


def game_dirs():
    """Title folders: working directory, executable's folder, and for a bundled java its runtime root."""
    dirs = [os.getcwd()]
    exe = game_binary()
    if exe:
        d = os.path.dirname(exe)
        dirs.append(d)
        if os.path.basename(exe) == "java" and os.path.basename(d) == "bin":
            dirs.append(os.path.dirname(d))
    return dedupe(os.path.realpath(d) for d in dirs)


def java_home(d):
    """d itself when it is a Java runtime (bin/java or libjvm.so), else None."""
    for sub in ("bin/java", "lib/server/libjvm.so", "lib/amd64/server/libjvm.so", "lib/i386/server/libjvm.so"):
        if os.path.isfile(os.path.join(d, sub)):
            return d
    return None


def java_runtime():
    """Bundled Java runtime root: a title folder itself, one folder below it (jre/, runtime/, jdk-*/ ...), or lib/runtime (jpackage)."""
    for d in game_dirs():
        if java_home(d):
            return d
        for c in (os.path.join(d, "lib", "runtime"), os.path.join(os.path.dirname(d), "lib", "runtime")):
            if java_home(c):
                return c
        try:
            subs = sorted(os.listdir(d))
        except OSError:
            continue
        for n in subs:
            p = os.path.join(d, n)
            if os.path.isdir(p) and java_home(p):
                return p
    return None


def java_major(home):
    """Major version from the runtime's `release` file (JAVA_VERSION="17.0.2", "1.8.0_202"); None if unknown."""
    try:
        m = re.search(r'^JAVA_VERSION="?([0-9]+)(?:\.([0-9]+))?', open(os.path.join(home, "release")).read(), re.M)
    except OSError:
        return None
    if not m:
        return None
    major = int(m.group(1))
    return int(m.group(2) or 0) if major == 1 else major


def lwjgl2():
    """True when the title includes LWJGL 2: its window class org/lwjgl/opengl/Display.class in a jar
    (LWJGL 3 has none), or its 64-bit native liblwjgl64.so (LWJGL 3 names it liblwjgl.so)."""
    jars = 0
    for top in game_dirs():
        for root, subs, files in os.walk(top):
            if root[len(top):].count(os.sep) >= 3:
                subs[:] = []
            if "liblwjgl64.so" in files:
                return True
            for n in files:
                if not n.endswith(".jar") or jars >= 64:
                    continue
                jars += 1
                try:
                    with zipfile.ZipFile(os.path.join(root, n)) as z:
                        if "org/lwjgl/opengl/Display.class" in z.namelist():
                            return True
                except (OSError, zipfile.BadZipFile, ValueError):
                    pass
    return False


def dedupe(seq):
    out = []
    for s in seq:
        if s not in out:
            out.append(s)
    return out


def goldsrc():
    """True for GoldSrc titles: hl_linux binary, or a mod folder with liblist.gam beside the binary."""
    exe = game_binary()
    if exe and os.path.basename(exe) == "hl_linux":
        return True
    dirs = dedupe([os.getcwd()] + ([os.path.dirname(exe)] if exe else []))
    return any(glob.glob(os.path.join(d, "*", "liblist.gam")) for d in dirs)


def compat_mapping(appid):
    """Tool name in Steam's config.vdf CompatToolMapping for appid; None when absent or empty."""
    p = os.path.join(os.path.expanduser("~"), ".local/share/Steam/config/config.vdf")
    try:
        s = open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    m = re.search(r'\n(\t+)"CompatToolMapping"\n\1\{\n(.*?)\n\1\}', s, re.S)
    if not m or not appid:
        return None
    cur = None
    for line in m.group(2).split("\n"):
        t = line.strip()
        k = re.fullmatch(r'"([^"]*)"', t)
        if k:
            cur = k.group(1)
            continue
        n = re.fullmatch(r'"name"\s+"([^"]*)"', t)
        if n and cur == appid:
            return n.group(1) or None
        if t == "}":
            cur = None
    return None


def desktop_notice(summary, body, urgency=1, timeout=5):
    """Desktop notification in the game account's session (gdbus, else notify-send); timeout in s, 0 stays."""
    env = {k: v for k, v in os.environ.items() if k not in ("LD_PRELOAD", "LD_LIBRARY_PATH", "PYTHONPATH", "PYTHONHOME")}
    if not env.get("DBUS_SESSION_BUS_ADDRESS"):
        bus = os.path.join(env.get("XDG_RUNTIME_DIR") or "/nonexistent", "bus")
        if not os.path.exists(bus):
            log("notice: not shown (no session bus)")
            return False
        env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=" + bus
    ms = str(int(timeout * 1000))
    gd, ns = shutil.which("gdbus", path=env.get("PATH")), shutil.which("notify-send", path=env.get("PATH"))
    if gd:
        cmd = [gd, "call", "--session", "--timeout", "3", "--dest", "org.freedesktop.Notifications",
               "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
               "Steam ARM", "0", "steam-arm", summary, body, "[]", "{'urgency': <byte %d>}" % urgency, ms]
    elif ns:
        cmd = [ns, "-a", "Steam ARM", "-i", "steam-arm", "-u", ("low", "normal", "critical")[min(max(urgency, 0), 2)],
               "-t", ms, summary, body]
    else:
        log("notice: not shown (no gdbus or notify-send)")
        return False
    try:
        r = subprocess.run(cmd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=5)
    except (OSError, subprocess.SubprocessError) as e:
        log("notice: not shown (%s)" % e)
        return False
    if r.returncode:
        log("notice: not shown (%s exit %d)" % (os.path.basename(cmd[0]), r.returncode))
        return False
    log("notice: shown")
    return True


def cpu_notice_on():
    """CPU_NOTICE from /etc/steam-arm/steam-arm.conf: True only for on (absent = off)."""
    try:
        v = [l[11:] for l in open("/etc/steam-arm/steam-arm.conf").read().splitlines() if l.startswith("CPU_NOTICE=")]
    except OSError:
        return False
    return bool(v) and v[-1].strip().strip("'\"") == "on"


def notify_cpu():
    """Notice that stays until closed, for a title drawn on CPU; GoldSrc skipped (Software renderer is its own option)."""
    if not cpu_notice_on():
        return False
    if goldsrc():
        log("notice: not shown (GoldSrc title: Software renderer is a video option)")
        return False
    return desktop_notice("Game draws on CPU",
                          "GPU forwarding is not active for this game (llvmpipe); frame rate stays low. "
                          "Cause: game log line \"renderer:\". Help: steam-arm-config, Help > Fixing a game.",
                          urgency=2, timeout=0)


AUTOBUILD = "/usr/local/lib/steam-arm-autobuild.py"


def auto_build(tool, bits):
    """(action, text) from the automatic Windows build rules for this start; None without a matching rule."""
    if not os.path.isfile(AUTOBUILD):
        return None
    try:
        v = fex_tool_ver()
        return runpy.run_path(AUTOBUILD)["launch_verdict"](
            APPID, game_binary(), bits, sys.argv, tool, gpu_family(), v[0] if v else 0,
            os.path.join(os.path.expanduser("~"), ".local/share/Steam"))
    except Exception as e:
        log("auto-build: check failed:", e)
        return None


# Renderer check: GL/Vulkan library of the title's processes, and the GPU device they hold.
GFX_LIB = re.compile(r"/(libGLX?(_\w+)?\.so|libEGL(_\w+)?\.so|libOpenGL\.so|libvulkan\.so|lib(GL|EGL|vulkan)-(guest|host)\.so"
                     r"|libgallium[^/]*\.so|\w+_dri\.so|libvulkan_\w+\.so)")
# x86 Mesa inside the emulation: on forwarding, a sign that the thunk was bypassed
GUEST_MESA = re.compile(r"(x86_64|i386)-linux-gnu/(?:\S*/)?(libgallium[^/]*\.so|\w+_dri\.so|libvulkan_\w+\.so)")
# runtime, launcher and Wine helpers that may load GL or open the GPU; not the title
HELPER_PREFIX = ("steam-runtime", "srt-", "pressure-vessel", "pv-", "steam-launch-w", "python", "wine")
HELPER_COMM = {"bwrap", "reaper", "FEXServer", "sh", "bash", "dash", "printenv", "steam",
               "explorer.exe", "services.exe", "winedevice.exe", "plugplay.exe", "svchost.exe", "rpcss.exe",
               "tabtip.exe", "steam.exe", "conhost.exe", "rundll32.exe", "start.exe", "xalia.exe"}
FEX_COMM = {"FEX", "FEXInterpreter", "FEXLoader"}


def drm_driver(node):
    try:
        return os.path.basename(os.readlink("/sys/class/drm/%s/device/driver" % node))
    except OSError:
        return "unknown"


def descendants(root):
    """Process ids below root, from /proc/<pid>/stat parent links."""
    kids = {}
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            st = open("/proc/%s/stat" % p).read()
            ppid = int(st[st.rindex(")") + 2:].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        kids.setdefault(ppid, []).append(int(p))
    out, todo = [], [root]
    while todo:
        for c in kids.get(todo.pop(), ()):
            out.append(c)
            todo.append(c)
    return out


# render nodes without 3D engine: virtual, display controller, NPU
NON_GPU_DRM = ("vgem", "vkms", "rockchip-drm", "RKNPU", "rknpu")


def drm_fd_used(pid, fd):
    """False when the fd's memory stats are all zero (device only probed, e.g. by llvmpipe); True otherwise."""
    try:
        lines = open("/proc/%d/fdinfo/%s" % (pid, fd)).read().splitlines()
    except OSError:
        return True
    mem = [l.split(":", 1)[1].split() for l in lines if re.match(r"drm-(total|resident|memory)-", l)]
    return not mem or any(v and v[0] != "0" for v in mem)


def gfx_state(pid):
    """(comm, graphics library loaded, x86 Mesa libraries, forwarding libraries loaded, GPU devices held) or None."""
    try:
        comm = open("/proc/%d/comm" % pid).read().strip()
        paths = {l.split(None, 5)[5] for l in open("/proc/%d/maps" % pid).read().splitlines() if len(l.split(None, 5)) == 6}
    except OSError:
        return None
    gfx = any(GFX_LIB.search(p) for p in paths)
    guest = sorted({m.group(2) for m in (GUEST_MESA.search(p) for p in paths) if m})
    fwd = any(re.search(r"/lib(GL|EGL|vulkan)-(guest|host)\.so", p) for p in paths)
    devs = set()
    try:
        fds = os.listdir("/proc/%d/fd" % pid)
    except OSError:
        fds = []
    for fd in fds:
        try:
            t = os.readlink("/proc/%d/fd/%s" % (pid, fd))
        except OSError:
            continue
        if t.startswith("/dev/dri/renderD"):
            d = drm_driver(os.path.basename(t))
            if d not in NON_GPU_DRM and drm_fd_used(pid, fd):
                devs.add("%s %s" % (d, os.path.basename(t)))
        elif t.startswith("/dev/nvidia"):
            devs.add("nvidia")
    return comm, gfx, guest, fwd, devs


def renderer_verdict(state, polls):
    """Log text for one process state seen with a graphics library for `polls` checks; None while undecided.
    A GPU render node in use (memory allocated) means GPU; none after 15 checks: CPU."""
    comm, gfx, guest, fwd, devs = state
    if not gfx:
        return None
    how = "forwarding to host driver" if fwd else "drivers inside emulation" if guest else "host driver"
    if devs:
        return "renderer: GPU (%s), %s, process %s" % (", ".join(sorted(devs)), how, comm)
    # FEX loader name: program not started yet (title processes carry their own name), so no CPU verdict
    if polls >= 15 and comm not in FEX_COMM:
        why = ("x86 Mesa inside emulation loaded (%s)" % ", ".join(guest)) if guest else "no GPU device in use"
        return "renderer: warning: GPU forwarding not active: rendering on CPU (llvmpipe); %s, process %s" % (why, comm)
    return None


def renderer_watch(root, limit=180, step=2):
    """Every `step` s for `limit` s: first verdict for a title process below root goes to the log."""
    seen = {}
    t0 = time.time()
    while time.time() - t0 < limit:
        time.sleep(step)
        for pid in descendants(root):
            s = gfx_state(pid)
            if not s or not s[1] or s[0] in HELPER_COMM or s[0].startswith(HELPER_PREFIX):
                continue
            seen[pid] = seen.get(pid, 0) + 1
            v = renderer_verdict(s, seen[pid])
            if v:
                log(v)
                if v.startswith("renderer: warning:"):
                    notify_cpu()
                return
    log("renderer: not detected within %d s (no GL or Vulkan library loaded, or title still loading)" % limit)


def renderer_thread(root):
    try:
        renderer_watch(root)
    except Exception as e:
        log("renderer: check stopped:", e)


prof = load_profile()
if prof:
    log("profile for", APPID, prof)
# FEX settings from launch options, read before any rule writes its own FEX_APP_CONFIG
LAUNCH_FEX = user_fex()
extra = [x for x in prof.get("args", "").split(";") if x]
engine, bits = engine_info()
if engine:
    log("engine: %s, %s-bit" % (engine, bits))
if source2():
    log("source 2: needs desktop-class Vulkan features; no known fix, launched unchanged")
if goldsrc():
    log("goldsrc: OpenGL 2.1 title; its video options pick OpenGL or Software renderer (Software draws on CPU)")
# Steam's saved tool choice is only read here, never written.
tool = compat_mapping(APPID)
x86_proton = any(os.path.basename(a) == "proton" for a in sys.argv)
if x86_proton and CLIENT_X86:
    log("compat: x86 Proton%s through emulation (x86 client)" % (" (%s)" % tool if tool else ""))
elif x86_proton:
    log("compat: x86 Proton%s through emulation; ARM64 Proton builds run without x86 emulation" % (" (%s)" % tool if tool else ""))
elif tool and "proton" in tool.lower():
    log("compat: warning: Steam's saved setting names %s for this title, but its Linux build started; "
        "Steam's current choice differs from its saved one (Properties > Compatibility)" % tool)
# Automatic Windows build: a start the launcher has not switched yet is skipped (SystemExit passes the tool's handler try).
AB = None if x86_proton else auto_build(tool, bits)
if AB:
    log(AB[1])
    if AB[0] in ("skip", "notice"):
        desktop_notice("Steam ARM", "Exit Steam ARM and start it again: this game then downloads and runs its Windows build.")
    if AB[0] == "skip":
        raise SystemExit(0)
# 32-bit Unity stops when x86 overlay attaches; default overlay off unless profile/launch option asks.
engine_overlay = "off" if (engine == "unity" and bits == 32) else None
# 64-bit Unity+Vulkan: Panfrost's GL is too old for Unity's core path (GLXBadFBConfig), so force Vulkan unless profile/launch overrides.
unity_vk = False
if engine == "unity" and bits == 64 and prof.get("unity", "vulkan") == "vulkan":
    forced = [a for a in sys.argv + extra if a.startswith("-force-")]
    if not forced and unity_has_vulkan():
        unity_vk = True
        engine_overlay = "vulkan"
    elif forced and "-force-vulkan" not in forced and unity_has_vulkan():
        log("launch option kept: %s (rule wanted -force-vulkan)" % " ".join(forced))
entries = [e for e in os.environ.get("LD_PRELOAD", "").replace(" ", ":").split(":") if e]
x86_overlay = [e for e in entries if "gameoverlayrenderer" in e and "steamrtarm64" not in e]
arm_overlay = [e for e in entries if "gameoverlayrenderer" in e and "steamrtarm64" in e]
mh_entries = [e for e in entries if "mangohud" in e.lower()]

# Steam overlay
explicit = os.environ.get("STEAM_ARM_PRELOAD_KEEP")
if explicit is not None:
    keep = [k for k in explicit.split(",") if k]
    items = [e for e in entries if any(k in e for k in keep)]
    log("overlay: STEAM_ARM_PRELOAD_KEEP", keep)
else:
    rule_mode = prof.get("overlay") or engine_overlay or "x86"
    mode = os.environ.get("STEAM_ARM_OVERLAY") or rule_mode
    if mode != rule_mode:
        log("launch option kept: STEAM_ARM_OVERLAY=%s (rule wanted %s)" % (mode, rule_mode))
    items = []
    if mode in ("x86", "vulkan"):
        items += x86_overlay
    if mode == "vulkan":
        items += arm_overlay
        os.environ["STEAM_ARM_VK_OVERLAY"] = "1"
    log("overlay:", mode)

# MangoHud
MH_SRC = "/opt/fex-rootfs/Ubuntu_24_04/usr/lib/%s/mangohud"
MH_DIR = os.path.join(os.path.expanduser("~"), ".local/lib/steam-arm")


def mh_local(name):
    """RootFS MangoHud library copied per arch into the client folder (refreshed on change); its $LIB path or None."""
    ok = False
    for triplet in ("x86_64-linux-gnu", "i386-linux-gnu"):
        src = os.path.join(MH_SRC % triplet, name)
        dst = os.path.join(MH_DIR, "lib", triplet, name)
        try:
            st = os.stat(src)
        except OSError:
            continue
        try:
            d = os.stat(dst)
            if (d.st_size, int(d.st_mtime)) == (st.st_size, int(st.st_mtime)):
                ok = True
                continue
        except OSError:
            pass
        try:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst + ".tmp")
            os.replace(dst + ".tmp", dst)
            ok = True
        except OSError as e:
            log("mangohud: copy to client folder failed:", e)
    return os.path.join(MH_DIR, "$LIB", name) if ok else None


mh = prof.get("mangohud", "auto")
wants_mh = bool(mh_entries) or os.environ.get("MANGOHUD") == "1" \
    or os.environ.get("STEAM_ARM_PRELOAD_MANGOHUD") == "1" or mh == "on"
if mh == "off":
    os.environ.pop("MANGOHUD", None)
    log("mangohud: off (profile)")
elif wants_mh:
    # RootFS copy preloaded from client folder (pressure-vessel maps /usr preloads to ARM host); 0.6.x has no shim
    names = [os.path.basename(e) for e in mh_entries if "/mangohud/" in e] or ["libMangoHud.so"]
    local = [x for x in (mh_local(n) for n in names) if x]
    items += [e for e in mh_entries if "/mangohud/" not in e] \
        + (local or [e for e in mh_entries if "/mangohud/" in e] or ["/usr/$LIB/mangohud/libMangoHud.so"])
    os.environ["MANGOHUD"] = "1"
    log("mangohud: on")

# Godot 4 OpenGL and Godot 3 GLES3 need GL 3.3 (Panfrost reports 3.1); Windows builds under Proton left alone
major = godot_major()
if major is not None and x86_proton:
    log("godot %d: Windows build under x86 Proton, left as is" % major)
elif major == 4 and prof.get("godot", "gl") == "gl":
    keep_env("MESA_GL_VERSION_OVERRIDE", "3.3")
    keep_env("MESA_GLSL_VERSION_OVERRIDE", "330")
    args = sys.argv + extra
    drv = "opengl3"
    if "--rendering-driver" not in args:
        sys.argv += ["--rendering-driver", "opengl3"]
    elif args[args.index("--rendering-driver") + 1:][:1] != ["opengl3"]:
        drv = "".join(args[args.index("--rendering-driver") + 1:][:1])
        log("launch option kept: --rendering-driver %s (rule wanted opengl3)" % drv)
    # values in effect, launch options included
    log("godot 4: %s renderer, GL %s report" % ("OpenGL" if drv == "opengl3" else drv or "default",
                                               os.environ["MESA_GL_VERSION_OVERRIDE"]))
elif major == 3 and prof.get("godot", "gl") == "gl":
    keep_env("MESA_GL_VERSION_OVERRIDE", "3.3")
    keep_env("MESA_GLSL_VERSION_OVERRIDE", "330")
    log("godot 3: GL %s report" % os.environ["MESA_GL_VERSION_OVERRIDE"])
elif major is not None:
    log("godot %d: left as is" % major)

# Unity 5+ needs GL core above Panfrost's 3.1 (GLXBadFBConfig); report GL 4.5 unless on Vulkan. Unity 4 (legacy GL) untouched.
if unity_vk:
    sys.argv += ["-force-vulkan"]
    log("unity: Vulkan renderer (-force-vulkan)")
elif engine == "unity" and not unity_legacy_gl():
    keep_env("MESA_GL_VERSION_OVERRIDE", "4.5")
    keep_env("MESA_GLSL_VERSION_OVERRIDE", "450")
    # values in effect, launch options included
    if bits == 64 and "-force-vulkan" in sys.argv + extra:
        log("unity: Vulkan renderer (launch option -force-vulkan)")
    else:
        log("unity: OpenGL core, GL %s report" % os.environ["MESA_GL_VERSION_OVERRIDE"])

# profile extras
for kv in [x for x in prof.get("env", "").split(";") if "=" in x]:
    k, v = kv.split("=", 1)
    os.environ[k] = v
    log("env:", k)
if extra:
    sys.argv += extra
    log("args:", extra)

# Java: LWJGL 2 fails on both graphics routes unless its XRandR mode switching is off.
jre = java_runtime()
if jre:
    log("java: runtime %s, version %s" % (jre, java_major(jre) or "unknown"))
    jto = os.environ.get("JAVA_TOOL_OPTIONS", "")
    if lwjgl2() and "LWJGL_DISABLE_XRANDR" not in jto:
        os.environ["JAVA_TOOL_OPTIONS"] = (jto + " -DLWJGL_DISABLE_XRANDR=true").strip()
        log("java: LWJGL 2, -DLWJGL_DISABLE_XRANDR=true")
    elif "LWJGL_DISABLE_XRANDR" in jto and "-DLWJGL_DISABLE_XRANDR=true" not in jto and lwjgl2():
        log("launch option kept: JAVA_TOOL_OPTIONS=%s (rule wanted -DLWJGL_DISABLE_XRANDR=true)" % jto)

# Graphics route: forwarding (a) unless a rule or setting picks Mali drivers inside the emulation (b); title profile wins.
vk = [a for a in sys.argv if a in ("-vulkan", "-force-vulkan")] if bits == 32 else []
fam = gpu_family()
gd = gfx_default()
custom = mali_ready() and mali_custom()
# custom driver archive: chosen by hand (GFX_DEFAULT=b, gfx=b) on any GPU family; automatic rules stay Mali-only
if gd == "b" and (fam in MALI_FAMILIES or custom):
    gfx, why = "b", "GFX_DEFAULT=b"
elif gd == "a":
    gfx, why = "a", "GFX_DEFAULT=a"
elif fam not in MALI_FAMILIES:
    gfx, why = "a", ("Mali drivers inside the emulation do not cover GPU family %s" % fam if gd == "b" or jre or vk else None)
elif jre:
    gfx, why = "b", "Java title"
elif vk and fam in PANVK_FAMILIES:
    gfx, why = "b", "32-bit Vulkan"
elif vk:
    gfx, why = "a", "32-bit Vulkan: no default Vulkan driver on GPU family %s" % fam
else:
    gfx, why = "a", None
if prof.get("gfx") == "b" and fam not in MALI_FAMILIES and not custom:
    log("graphics: warning: Mali drivers inside the emulation do not cover GPU family %s; title profile gfx=b "
        "not applied (a custom driver archive allows it)" % fam)
    gfx, why = "a", "gfx=b needs a Mali GPU or a custom driver archive"
elif prof.get("gfx") in ("a", "b"):
    if prof["gfx"] != gfx:
        log("title setting kept: gfx=%s (rule wanted gfx=%s)" % (prof["gfx"], gfx))
    gfx, why = prof["gfx"], "title profile"
if gfx == "b" and CLIENT_X86:
    log("graphics: x86 client: Mali drivers inside the emulation not wired; forwarding (%s)" % why)
    gfx, why = "a", "x86 client: Mali drivers inside the emulation not wired"
if gfx == "b" and not mali_ready():
    gfx, why = "a", "Mali drivers inside the emulation not installed"
if gfx == "b":
    try:
        uf = user_fex()
        umb = uf.get("Config", {}).get("Multiblock") if isinstance(uf.get("Config"), dict) else None
        cfg = None
        if jre and (java_major(jre) or 0) >= 21:
            if umb is None:
                cfg = {"Multiblock": "0"}
            else:
                log("launch option kept: Multiblock=%s (rule wanted 0 for Java 21 or newer)" % umb)
        utd = uf.get("ThunksDB") if isinstance(uf.get("ThunksDB"), dict) else {}
        for k in ("GL", "Vulkan"):
            if str(utd.get(k)).lower() in ("1", "true"):
                log("overridden for Mali route: thunk %s=%s (now 0, drivers run inside the emulation)" % (k, utd[k]))
        fex_app_config(thunks={"GL": 0, "Vulkan": 0}, config=cfg)
        set_env("STEAM_COMPAT_GRAPHICS_PROVIDER", MALI_ROOT + "/graphics_provider.json", "Mali route",
                ("/opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json",))
        set_env("__GLX_VENDOR_LIBRARY_NAME", "mesa", "Mali route", ("steamarmlax",))
        log(("graphics: custom drivers inside the emulation (%s)" if custom else "graphics: Mali drivers in emulation (%s)") % why)
        if cfg:
            log("java: 21 or newer, FEX Multiblock off")
    except OSError as e:
        gfx = "a"
        log("graphics: forwarding (could not write FEX app config: %s)" % e)
else:
    log("graphics: forwarding" + (" (%s)" % why if why else ""))

# 32-bit on forwarding: no 32-bit Vulkan thunk, so a Vulkan renderer lands on lavapipe (CPU).
if gfx == "a" and vk and prof.get("vk32") != "keep":
    sys.argv = [a for a in sys.argv if a not in vk]
    log("32-bit: removed", vk, "(Vulkan would run on CPU; vk32=keep keeps it)")
# gl32=off: emulated x86 Mesa instead of the host GL thunk, for titles the thunk breaks.
if gfx == "a" and prof.get("gl32") == "off" and bits != 64:
    try:
        fex_app_config(thunks={"GL": 0})
        # x86 Mesa inside the emulation has no steamarmlax vendor library
        set_env("__GLX_VENDOR_LIBRARY_NAME", "mesa", "gl32=off", ("steamarmlax",))
        log("gl32: GL thunk off (FEX_APP_CONFIG=%s)" % os.environ["FEX_APP_CONFIG"])
    except OSError as e:
        log("gl32: could not write FEX app config:", e)

# multiblock=on|off: FEX Multiblock for this title in place of Valve's per-title default; launch options and Steam's FEX setting win.
mbp = prof.get("multiblock")
if mbp in ("on", "off"):
    want = "1" if mbp == "on" else "0"
    lc = LAUNCH_FEX.get("Config") if isinstance(LAUNCH_FEX.get("Config"), dict) else {}
    if "Multiblock" in lc:
        log("launch option kept: Multiblock=%s (title setting multiblock=%s)" % (lc["Multiblock"], mbp))
    elif os.environ.get("STEAM_COMPAT_FEX_CONFIG"):
        log("Steam setting kept: STEAM_COMPAT_FEX_CONFIG=%s (title setting multiblock=%s)"
            % (os.environ["STEAM_COMPAT_FEX_CONFIG"], mbp))
    else:
        try:
            prev = None
            if APP_CFG:
                c = json.load(open(APP_CFG)).get("Config")
                prev = c.get("Multiblock") if isinstance(c, dict) else None
            if prev is not None and str(prev) != want:
                log("title setting kept: multiblock=%s (rule wanted Multiblock=%s)" % (mbp, prev))
            fex_app_config(config={"Multiblock": want})
            log("fex: Multiblock %s (title profile)" % mbp)
        except (OSError, ValueError) as e:
            log("fex: could not write FEX app config:", e)

# diskcache=on|off: FEX code cache (FEX 2609.1+); launch options win; own-JIT titles cache file-backed code only.
# Steam's FEX setting (STEAM_COMPAT_FEX_CONFIG) holds no cache key, so it does not block this one.
dcp = prof.get("diskcache")
if dcp in ("on", "off"):
    lc = LAUNCH_FEX.get("Config") if isinstance(LAUNCH_FEX.get("Config"), dict) else {}
    ver = fex_tool_ver()
    if CLIENT_X86:
        log("fex: code cache not applied: x86 client")
    elif "FEX_DISKCACHE" in os.environ:
        log("launch option kept: FEX_DISKCACHE=%s (title setting diskcache=%s)" % (os.environ["FEX_DISKCACHE"], dcp))
    elif "DiskCache" in lc:
        log("launch option kept: DiskCache=%s (title setting diskcache=%s)" % (lc["DiskCache"], dcp))
    elif ver is None:
        log("fex: code cache not applied: FEX tool version unknown (no VERSIONS.txt)")
    elif ver < (2609, 1):
        log("fex: code cache not applied: needs FEX tool FEX-2609.1 or newer (tool: %s)" % fex_ver_str(ver))
    else:
        cfg = {"DiskCache": "1" if dcp == "on" else "0"}
        jit = (own_jit() or ("java" if jre else None)) if dcp == "on" else None
        if jit:
            cfg["DiskCacheAnonCaching"] = "0"
        try:
            if dcp == "on":
                cache_stamp_check("%s build=%s" % (fex_ver_str(ver), game_build()))
            fex_app_config(config=cfg)
            log("fex: code cache %s (title profile)%s" % (dcp, "; own JIT found (%s): only file-backed code cached" % jit if jit else ""))
        except (OSError, ValueError) as e:
            log("fex: could not write FEX app config:", e)

if os.environ.get("STEAM_ARM_RENDERER_CHECK", "1") != "0":
    threading.Thread(target=renderer_thread, args=(os.getpid(),), daemon=True).start()

items = dedupe(items)
if items:
    os.environ["LD_PRELOAD"] = ":".join(items)
    log("LD_PRELOAD for container:", os.environ["LD_PRELOAD"])
else:
    os.environ.pop("LD_PRELOAD", None)
    log("LD_PRELOAD: none")
HANDLERPY
chmod 644 /usr/local/lib/steam-arm-handler.py
# x86 client: launch wrapper stand-in runs the handler through this file (native python, outside the emulation).
cat > /usr/local/lib/steam-arm-run.py <<'RUNPY'
#!/usr/bin/env python3
"""steam-arm-run: steam-arm launch handler for Valve's x86 client (CPUs without Armv8.1 atomics).

Stand-in of Valve's launch wrapper runs:
  steam-arm-run.py --client x86 [--preload LIST] -- WRAPPER ARGS...
Launch handler (/usr/local/lib/steam-arm-handler.py) decides per title on this process's environment and
arguments, as inside Valve's FEX tool for native client; LIST is the game's LD_PRELOAD (kept out of this
native process). WRAPPER then runs as child with result; SIGTERM, SIGINT and SIGHUP pass on to it; exit
status is its own. Handler log: /tmp/steam-arm-run-<pid>.log, readable by game account only."""
import os
import runpy
import signal
import subprocess
import sys

HANDLER = "/usr/local/lib/steam-arm-handler.py"


def parse(a):
    """(client, preload or None, command) from arguments, None when malformed."""
    if len(a) < 3 or a[0] != "--client" or a[1] not in ("x86", "arm64"):
        return None
    client, rest, preload = a[1], a[2:], None
    if rest[:1] == ["--preload"] and len(rest) >= 2:
        preload, rest = rest[1], rest[2:]
    if rest[:1] != ["--"] or len(rest) < 2:
        return None
    return client, preload, rest[1:]


def open_log(path):
    """Handler log readable by owner only; never through a link or another account's file; else /dev/null."""
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    except OSError:
        return open(os.devnull, "w")
    try:
        if os.fstat(fd).st_uid != os.getuid():
            raise OSError("not own file")
        os.fchmod(fd, 0o600)
        os.ftruncate(fd, 0)
    except OSError:
        os.close(fd)
        return open(os.devnull, "w")
    return os.fdopen(fd, "w", buffering=1)


def main(a):
    p = parse(a)
    if not p:
        sys.stderr.write("usage: steam-arm-run.py --client x86 [--preload LIST] -- COMMAND [ARG...]\n")
        return 2
    client, preload, cmd = p
    if preload is not None:
        if preload:
            os.environ["LD_PRELOAD"] = preload
        else:
            os.environ.pop("LD_PRELOAD", None)
    sys.argv = ["steam-arm-run"] + cmd
    log = open_log("/tmp/steam-arm-run-%d.log" % os.getpid())
    out = sys.stdout
    sys.stdout = log
    print("SteamAppId=%s" % (os.environ.get("SteamAppId") or os.environ.get("SteamGameId") or ""))
    print("steam-arm: client: %s through emulation" % client if client == "x86" else "steam-arm: client: native ARM64")
    try:
        runpy.run_path(HANDLER, init_globals={"CLIENT_X86": client == "x86"})
    except SystemExit as e:
        # handler skipped this start (automatic Windows build pending)
        print("steam-arm: launch skipped by handler")
        sys.stdout = out
        return e.code if isinstance(e.code, int) else 0
    except Exception as e:
        print("steam-arm: handler failed, launched unchanged:", e)
    cmd = sys.argv[1:]
    print("steam-arm: command:", " ".join(cmd))
    try:
        child = subprocess.Popen(cmd)
    except OSError as e:
        print("steam-arm: could not start %s: %s" % (cmd[0], e))
        sys.stdout = out
        return 127

    def forward(sig, _frame):
        try:
            child.send_signal(sig)
        except OSError:
            pass

    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(s, forward)
    while True:
        try:
            rc = child.wait()
            break
        except InterruptedError:
            continue
    print("steam-arm: exit status", rc)
    sys.stdout = out
    return 128 - rc if rc < 0 else rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
RUNPY
chmod 644 /usr/local/lib/steam-arm-run.py
# Host python under a path the x86 RootFS lacks: an emulated exec of it stays native.
ln -sfn /usr/bin/python3 /usr/local/lib/steam-arm-python3
# Runtime containers of the x86 client: host bubblewrap with host libraries, FEX thunks and FEXServer socket inside.
PVB_BINDS=""
if read -r TH_HOST TH_GUEST TH_DB < <(fex_thunk_paths); then
  for d in "${TH_HOST%/}" "${TH_GUEST%/}" "$(dirname "$TH_DB")"; do PVB_BINDS="$PVB_BINDS --ro-bind-try $d $d"; done
fi
# shellcheck disable=SC2016
{ printf '#!/bin/sh\n# steam-arm: bubblewrap for runtime containers of the x86 client (pressure-vessel passes --args FD; no fd closed).\n'
  printf 'u=$(id -u)\n'
  printf '# private libX11 copy (X errors not fatal) over host one inside container, when present\n'
  printf 'x="$HOME/.fex-emu/hostlib/libX11.so.6"; t=$(readlink -f /usr/lib/aarch64-linux-gnu/libX11.so.6)\n'
  printf 'if [ -f "$x" ] && [ -n "$t" ]; then set -- --ro-bind "$x" "$t" "$@"; fi\n'
  printf 'exec /usr/bin/bwrap --ro-bind /usr/lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu%s \\\n' "$PVB_BINDS"
  printf '  --ro-bind-try "/run/user/$u/0.FEXServer.Socket" "/run/user/$u/0.FEXServer.Socket" --setenv FEX_ROOTFS / "$@"\n'
} > /usr/local/lib/steam-arm-pv-bwrap
chmod 755 /usr/local/lib/steam-arm-pv-bwrap
# Package tools for programs of the x86 client: refused (emulated writes reach the host system).
mkdir -p "$NOPKG"
for t in apt apt-get dpkg pkexec sudo steamdeps; do
  printf '#!/bin/sh\necho "%s: package changes from the x86 client are off (emulated writes reach the host system); nothing changed." >&2\nexit 1\n' "$t" > "$NOPKG/$t"
  chmod 755 "$NOPKG/$t"
done
mh_shim || warn "$MH_SHIM could not be written; use MANGOHUD=1 %command% instead of mangohud %command%"
mkdir -p /usr/local/share/steam-arm
cat > /usr/local/share/steam-arm/titles.conf <<'TITLES'
# Included title profiles; local overrides belong in /etc/steam-arm/titles.conf or ~/.config/steam-arm/titles.conf.
248570 overlay=off      # custom OpenGL engine: stops when Steam overlay attaches
TITLES
[ -f /etc/steam-arm/titles.conf ] || cat > /etc/steam-arm/titles.conf <<'TITLES'
# Local title profiles; override /usr/local/share/steam-arm/titles.conf. One line per title: <appid> key=value ...
#   overlay=x86|vulkan|off  mangohud=on|off  godot=gl|vulkan  env=A=1;B=2  args=-x;-y   (example: <appid> overlay=off)
#   gl32=off (32-bit title on emulated x86 Mesa, no GL thunk)  vk32=keep (32-bit title keeps -vulkan)
#   gfx=b (Mali drivers inside emulation)  gfx=a (forwarding); unset = automatic
#   multiblock=on|off (FEX Multiblock for the title; unset = Valve's per-title default)
#   diskcache=on|off (FEX code cache for the title, FEX tool 2609.1 or newer; unset = off)
TITLES

# FEX tool edit, shared by the launcher's start and its watcher (see the launcher).
cat > /usr/local/lib/steam-arm-fexpatch.py <<'FEXPY'
#!/usr/bin/env python3
"""steam-arm-fexpatch FEXTOOLDIR: thunk overlay paths, server socket, GL and Vulkan thunks, logging off.

GL and Vulkan thunks are on ("1"); titles on Mali drivers inside the emulation get them off per title
through FEX_APP_CONFIG (steam-arm launch handler).

FEX substitutes a thunk only when the guest opens a library path listed in ThunksDB's Overlay.
Inside the runtime container the guest opens libGL, libEGL and libvulkan from pressure-vessel's
overrides directory, or from /run/gfx/main where current runtimes mount the graphics provider,
for 32-bit and 64-bit titles alike. FEX 2609 and later list these paths itself (VERSIONS.txt
names the release), so the overlay edit is skipped there. Writes only when something is missing.

Also replaces the tool's deletion of LD_PRELOAD with a call to the steam-arm launch handler,
/usr/local/lib/steam-arm-handler.py, which decides overlay, MangoHud and engine fixes per title
(if it fails, the tool behaves as Valve wrote it). Patched only where Valve's two lines match
exactly; an earlier steam-arm filter (v1) is replaced.

Before an edit Valve's file is saved as <file>.steam-arm-orig, unless the file is what this tool
wrote last (sha256 in <file>.steam-arm-sha). Steam may be updating the tool: edits start only once the three
files are unchanged for 2 s, and a file that changes before its edit lands is left alone (exit 75,
the launcher tries again). --no-wait FEXTOOLDIR: no waiting; exit 75 unless the files are 2 s old.

steam-arm-fexpatch --unpatch FEXTOOLDIR: puts back Valve's files. A file still as this tool wrote
it gets the saved copy back byte for byte; otherwise the two lines, keys and overlay
paths added here are taken out. Missing or stock tool is left as is."""
import hashlib, json, os, re, sys, tempfile, time
UNPATCH = sys.argv[1:2] == ["--unpatch"]
NOWAIT = sys.argv[1:2] == ["--no-wait"]
F = sys.argv[2] if UNPATCH or NOWAIT else sys.argv[1]
db_p, tpl_p, ct_p = F + "/usr/share/fex-emu/ThunksDB.json", F + "/ConfigTemplate.json", F + "/fex-compat-tool"
ORIG = ".steam-arm-orig"
# sha256 of the bytes this tool last wrote to the file beside it
SHA = ".steam-arm-sha"
OLD_LINES = "    if 'LD_PRELOAD' in os.environ:\n        del os.environ['LD_PRELOAD']\n"
POP_END = "        os.environ.pop('LD_PRELOAD', None)\n"
MARK = "# steam-arm handler v2"
V1 = "# steam-arm preload filter v1"
HANDLER = "/usr/local/lib/steam-arm-handler.py"
BLOCK = ("    " + MARK + "\n"
         "    try:\n"
         "        import runpy\n"
         "        runpy.run_path('" + HANDLER + "')\n"
         "    except Exception as _e:\n"
         "        print('steam-arm: handler failed, Valve default applies:', _e)\n" + POP_END)
SOCK_RE = r"/run/user/[0-9]+/(steam-arm|h96)-fexserver\.sock"
NAMES = {"GL": ["libGL.so", "libGL.so.1", "libGL.so.1.7.0", "libGL.so.1.2.0"],
         "Vulkan": ["libvulkan.so", "libvulkan.so.1"], "EGL": ["libEGL.so", "libEGL.so.1"]}


class Changed(Exception):
    """A file changed on disk between its read and its replacement."""


def overlay_paths(ns):
    for arch in ("i386-linux-gnu", "x86_64-linux-gnu"):
        for base in ("/usr/lib/pressure-vessel/overrides/lib/" + arch,
                     "/usr/lib/pressure-vessel/overrides/lib/%s/aliases" % arch,
                     "/run/gfx/main/usr/lib/" + arch):
            for n in ns:
                yield base + "/" + n


def fstat(p):
    try:
        st = os.stat(p)
    except OSError:
        return None
    return (st.st_ino, st.st_size, st.st_mtime_ns)


SEEN = {}


def read(p):
    SEEN[p] = fstat(p)
    with open(p, "rb") as f:
        return f.read()


def write_atomic(p, data, check=True):
    # New file in the same folder renamed over p (Steam may read it at any time); mode kept.
    try:
        mode = os.stat(p).st_mode & 0o7777
    except OSError:
        mode = 0o644
    fd, t = tempfile.mkstemp(prefix=".steam-arm-", dir=os.path.dirname(p) or ".")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode())
        os.chmod(t, mode)
        if check and fstat(p) != SEEN.get(p):
            raise Changed(p)
        os.replace(t, p)
    except BaseException:
        try:
            os.unlink(t)
        except OSError:
            pass
        raise
    SEEN[p] = fstat(p)


def fex_yymm():
    # First "FEX-YYMM" in VERSIONS.txt (FEX-2609.1, FEX-2607-76-g...); 0 when unknown. Launcher's fex_new() matches this.
    try:
        m = re.search(r"FEX-([0-9]{4})", open(F + "/VERSIONS.txt").read())
    except OSError:
        return 0
    return int(m.group(1)) if m else 0


def block_span(ct, mark):
    # (start, end) of a handler block starting at mark, None when absent or without its end line
    i = ct.find("    " + mark)
    if i < 0:
        return None
    j = ct.find(POP_END, i)
    return None if j < 0 else (i, j + len(POP_END))


# --- fex-compat-tool ---
def ct_parse(raw):
    return raw.decode("utf-8")


def ct_strip(ct, keep_other=False):
    # Valve's two lines in place of each handler block; keep_other: the other flavour's handler stays
    for mark in (MARK, V1):
        sp = block_span(ct, mark)
        if not sp:
            continue
        blk = ct[sp[0]:sp[1]]
        if keep_other and HANDLER not in blk and "handler.py" in blk:
            continue
        ct = ct[:sp[0]] + OLD_LINES + ct[sp[1]:]
    return ct


def ct_patch(ct):
    if MARK in ct and "run_path('%s')" % HANDLER in ct:
        return ct
    for mark in (MARK, V1):
        sp = block_span(ct, mark)
        if sp:
            # patched for another handler (other steam-arm flavour) or an earlier filter: re-point the block
            return ct[:sp[0]] + BLOCK + ct[sp[1]:]
    if MARK not in ct and ct.count(OLD_LINES) == 1:
        return ct.replace(OLD_LINES, BLOCK)
    return None


def ct_stock(ct):
    return MARK not in ct and V1 not in ct and ct.count(OLD_LINES) == 1


def ct_dump(ct):
    compile(ct, ct_p, "exec")
    return ct.encode("utf-8")


# --- ConfigTemplate.json ---
def tpl_parse(raw):
    t = json.loads(raw.decode("utf-8"))
    if not isinstance(t, dict) or not isinstance(t.get("Config", {}), dict):
        raise ValueError("unknown layout")
    return t


def tpl_strip(t):
    t = json.loads(json.dumps(t))
    c = t.get("Config", {})
    if re.fullmatch(SOCK_RE, str(c.get("ServerSocketPath", ""))):
        del c["ServerSocketPath"]
    if c.get("SilentLog") == "1":
        del c["SilentLog"]
    td = t.get("ThunksDB")
    if isinstance(td, dict) and set(td) <= {"GL", "Vulkan"} and all(v in ("0", "1") for v in td.values()):
        del t["ThunksDB"]
    return t


def tpl_patch(t):
    t = json.loads(json.dumps(t))
    c = t.setdefault("Config", {})
    c["ServerSocketPath"] = "/run/user/%s/steam-arm-fexserver.sock" % os.getuid()
    # FEX logging off: fewer steamwebhelper crashes under emulation.
    c["SilentLog"] = "1"
    td = t.setdefault("ThunksDB", {})
    if not isinstance(td, dict):
        raise ValueError("unknown layout")
    td["GL"] = td["Vulkan"] = "1"
    return t


def tpl_stock(t):
    return not re.fullmatch(SOCK_RE, str(t.get("Config", {}).get("ServerSocketPath", "")))


def tpl_dump(t):
    return json.dumps(t, indent=4).encode()


# --- ThunksDB.json ---
def db_parse(raw):
    db = json.loads(raw.decode("utf-8"))
    if not isinstance(db, dict) or not isinstance(db.get("DB"), dict):
        raise ValueError("unknown layout")
    return db


def db_strip(db):
    db = json.loads(json.dumps(db))
    for lib, ns in NAMES.items():
        e = db["DB"].get(lib)
        ov = e.get("Overlay") if isinstance(e, dict) else None
        if isinstance(ov, list):
            ours = set(overlay_paths(ns))
            keep = [p for p in ov if p not in ours]
            if len(keep) != len(ov):
                if keep:
                    e["Overlay"] = keep
                else:
                    del e["Overlay"]
    return db


def db_patch(db):
    db = json.loads(json.dumps(db))
    for lib, ns in NAMES.items():
        e = db["DB"].get(lib)
        if not isinstance(e, dict):
            continue
        ov = e.setdefault("Overlay", [])
        if not isinstance(ov, list):
            raise ValueError("unknown layout")
        for p in overlay_paths(ns):
            if p not in ov:
                ov.append(p)
    return db


def db_dump(db):
    return json.dumps(db, indent=2).encode()


FILES = {db_p: (db_parse, db_patch, db_strip, lambda db: True, db_dump),
         tpl_p: (tpl_parse, tpl_patch, tpl_strip, tpl_stock, tpl_dump),
         ct_p: (ct_parse, ct_patch, ct_strip, ct_stock, ct_dump)}


def saved(p, parse):
    # Saved original of p, parsed; None when absent or unreadable.
    try:
        raw = open(p + ORIG, "rb").read()
        return raw, parse(raw)
    except (OSError, ValueError):
        return None, None


def fail(what, code=3):
    # Plain line for the launcher log; games still start with Valve's settings.
    print("steam-arm-fexpatch: %s" % what, file=sys.stderr)
    sys.exit(code)


def settle(wait=True):
    # True once the three files are unchanged for 2 s (at most 30 s of waiting); wait=False: True only
    # when none was written in the last 2 s, no sleep. A future mtime (clock stepped back) counts as now.
    if not wait:
        now = time.time()
        newest = min(max([s[2] / 1e9 for s in (fstat(p) for p in FILES) if s] or [0]), now)
        return now - newest >= 2.0
    end = time.monotonic() + 30
    while time.monotonic() + 2.0 <= end:
        s0 = [fstat(p) for p in FILES]
        time.sleep(2.0)
        if [fstat(p) for p in FILES] == s0:
            return True
    return False


def written_here(p, raw):
    # True/False: raw is/is not what this tool last wrote; None without a record (setup from before the record)
    try:
        return open(p + SHA).read().strip() == hashlib.sha256(raw).hexdigest()
    except OSError:
        return None


def same_base(p, orig, cur, keep=False):
    # True when cur is the saved original plus (some of) the edits of this tool; for files without a record
    parse, patch, strip, stock, dump = FILES[p]
    if patch(orig) == cur:
        return True
    if p == ct_p:
        return strip(orig, keep) == strip(cur, keep)
    return strip(orig) == strip(cur)


def apply(p):
    parse, patch, strip, stock, dump = FILES[p]
    raw = read(p)
    cur = parse(raw)
    new = patch(cur)
    if new is None:
        return None
    if new == cur:
        return False
    oraw, orig = saved(p, parse)
    # file written here before (saved original stays), else Valve's: saved as original unless another tool edited it
    w = written_here(p, raw)
    if not (w if w is not None else orig is not None and same_base(p, orig, cur)):
        if stock(cur):
            write_atomic(p + ORIG, raw, check=False)
        elif os.path.exists(p + ORIG):
            os.remove(p + ORIG)
    data = dump(new)
    write_atomic(p, data)
    write_atomic(p + SHA, hashlib.sha256(data).hexdigest() + "\n", check=False)
    return True


def unpatch_one(p, skip):
    parse, patch, strip, stock, dump = FILES[p]
    try:
        if skip or not os.path.isfile(p):
            return
        raw = read(p)
        cur = parse(raw)
        keep = os.path.exists("/etc/h96/steam-arm.conf")
        cleaned = strip(cur, keep) if p == ct_p else strip(cur)
        oraw, orig = saved(p, parse)
        w = written_here(p, raw)
        if orig is not None and (w if w is not None else same_base(p, orig, cur, keep)):
            if oraw != raw:
                write_atomic(p, oraw)
        elif cleaned != cur:
            write_atomic(p, dump(cleaned))
    except (OSError, ValueError, SyntaxError, Changed) as e:
        print("steam-arm-fexpatch: %s left as it is (%s)" % (os.path.basename(p), e), file=sys.stderr)
    finally:
        for x in (p + ORIG, p + SHA):
            if os.path.exists(x):
                os.remove(x)


if UNPATCH:
    if os.path.isdir(F):
        # 2609+ lists the overlay paths itself; its file was never edited here
        for p in FILES:
            unpatch_one(p, p == db_p and fex_yymm() >= 2609)
    sys.exit(0)
if not settle(not NOWAIT):
    fail("the emulation tool is still being updated; changes apply once Steam has finished", 75)
try:
    for p in (([] if fex_yymm() >= 2609 else [db_p]) + [tpl_p]):
        apply(p)
    if not os.path.isfile(ct_p):
        sys.exit(0)
    r = apply(ct_p)
except Changed:
    fail("the emulation tool changed while it was being patched; changes apply at the next look", 75)
except OSError as e:
    fail("could not read or write the emulation tool's settings (%s); games start with Valve's own settings" % e)
except ValueError as e:
    fail("could not read the emulation tool's settings (%s); games start with Valve's own settings" % e)
except SyntaxError:
    fail("the emulation tool's settings have a layout this version does not know; games start with Valve's own settings")
if r is None and any(k in open(ct_p).read() for k in ("LD_PRELOAD", MARK)):
    fail("Valve changed the text of fex-compat-tool, so the launch handler is not connected: overlay, MangoHud "
         "and per-title fixes are off until a newer Steam ARM supports it; games still start")
FEXPY
chmod 755 /usr/local/lib/steam-arm-fexpatch.py
# PhysX install-step skip for Proton titles, run by the launcher.
cat > /usr/local/lib/steam-arm-physx.py <<'PHYSXPY'
#!/usr/bin/env python3
"""steam-arm-physx: PhysX install step of Proton titles, which hangs under emulation.

1. Registry: installed title with a Proton prefix whose install script has a "Run Process" section
   naming PhysX gets that section's has-run value in pfx/system.reg, max(1, MinimumHasRunValue),
   so Steam skips the step. Written only while no wineserver runs on the prefix (it would overwrite
   the file); an equal or higher value stays.
2. Fallback (prefix not there yet on first start): a PhysX installer (or msiexec with a PhysX package) under Steam's reaper for over
   60 s gets SIGTERM, never SIGKILL; Steam then continues to the title.
Usage: steam-arm-physx.py watch <Steam dir> <log>  |  steam-arm-physx.py once <Steam dir>"""
import glob
import os
import re
import signal
import sys
import time

HANG_S = 60
NOTED = set()


def logger(path):
    def log(msg):
        line = "%s physx: %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
        if not path:
            sys.stdout.write(line)
            return
        try:
            with open(path, "a") as f:
                f.write(line)
        except OSError:
            pass
    return log


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read().lstrip("\ufeff")


def vdf_parse(text):
    """Text KeyValues to nested dicts; keys keep their case, get() matches without it."""
    root = {}
    stack = [root]
    key = None
    for m in re.finditer(r'"((?:\\.|[^"\\])*)"|([{}])|//[^\n]*|([^\s{}"]+)', text):
        q, brace, bare = m.groups()
        if brace == "{":
            d = {}
            stack[-1][key if key is not None else ""] = d
            stack.append(d)
            key = None
        elif brace == "}":
            if len(stack) > 1:
                stack.pop()
            key = None
        elif q is not None or bare is not None:
            v = q.replace("\\\\", "\\").replace('\\"', '"') if q is not None else bare
            if key is None:
                key = v
            else:
                stack[-1][key] = v
                key = None
    return root


def get(d, name):
    if isinstance(d, dict):
        for k, v in d.items():
            if k.lower() == name.lower():
                return v
    return None


def libraries(steam):
    libs = [os.path.join(steam, "steamapps")]
    try:
        lf = get(vdf_parse(read(os.path.join(steam, "steamapps", "libraryfolders.vdf"))), "libraryfolders")
    except OSError:
        lf = None
    for v in (lf or {}).values():
        p = get(v, "path")
        if isinstance(p, str):
            sa = os.path.join(p, "steamapps")
            if os.path.realpath(sa) not in [os.path.realpath(x) for x in libs]:
                libs.append(sa)
    return libs


def titles(steam):
    """(appid, library, install dir) of fully installed titles (StateFlags bit 4)."""
    for lib in libraries(steam):
        for acf in glob.glob(os.path.join(lib, "appmanifest_*.acf")):
            try:
                st = get(vdf_parse(read(acf)), "AppState")
                flags = int(get(st, "StateFlags") or 0)
            except (OSError, ValueError):
                continue
            appid, inst = get(st, "appid"), get(st, "installdir")
            if isinstance(appid, str) and appid.isdigit() and flags & 4 and isinstance(inst, str) and inst:
                yield appid, lib, os.path.join(lib, "common", inst)


def install_scripts(gamedir):
    """installscript*.vdf files in the install dir, two levels down at most."""
    found = []
    base = gamedir.rstrip("/").count("/")
    for d, dirs, files in os.walk(gamedir):
        if d.count("/") - base >= 2:
            dirs[:] = []
        found += [os.path.join(d, f) for f in files if f.lower().startswith("installscript") and f.lower().endswith(".vdf")]
    return found


def run_process_sections(d):
    for k, v in d.items():
        if isinstance(v, dict):
            if k.lower() == "run process":
                yield v
            else:
                yield from run_process_sections(v)


def reg_key(hasrunkey, appid):
    """Registry key path under HKLM for system.reg; Steam's install step is 32-bit, so Software maps to Wow6432Node."""
    k = hasrunkey if isinstance(hasrunkey, str) and hasrunkey else "HKEY_LOCAL_MACHINE\\Software\\Valve\\Steam\\Apps\\" + appid
    parts = [x for x in k.replace("/", "\\").split("\\") if x]
    if not parts or parts[0].upper() not in ("HKEY_LOCAL_MACHINE", "HKLM"):
        return None
    rest = parts[1:]
    if rest and rest[0].lower() == "software" and (len(rest) < 2 or rest[1].lower() != "wow6432node"):
        rest = [rest[0], "Wow6432Node"] + rest[1:]
    return "\\".join(rest) if rest else None


def physx_rules(appid, scripts, log):
    """{(key, value name): dword} for Run Process sections whose process/command names PhysX."""
    rules = {}
    for p in scripts:
        try:
            kv = vdf_parse(read(p))
        except OSError:
            continue
        for rp in run_process_sections(kv):
            for name, sec in rp.items():
                if not isinstance(sec, dict) or not any(
                        isinstance(v, str) and "physx" in v.lower()
                        for k, v in sec.items() if re.match(r"(process|command)\s*\d*$", k, re.I)):
                    continue
                key = reg_key(get(sec, "HasRunKey"), appid)
                if not key:
                    msg = "%s: section %s has a non-HKLM HasRunKey, left to the installer" % (appid, name)
                    if msg not in NOTED:
                        NOTED.add(msg)
                        log(msg)
                    continue
                try:
                    mn = int(str(get(sec, "MinimumHasRunValue") or "0").strip())
                except ValueError:
                    mn = 0
                val = min(max(1, mn), 0xFFFFFFFF)
                rules[(key, name)] = max(val, rules.get((key, name), 0))
    return rules


def reg_set(path, key, name, value):
    """Set dword `name` under `key` in a Wine registry file unless an equal or higher dword is there."""
    with open(path, encoding="latin-1", newline="") as f:
        lines = f.read().split("\n")
    esc = key.replace("\\", "\\\\").lower()
    line = '"%s"=dword:%08x' % (name.replace("\\", "\\\\").replace('"', '\\"'), value)
    start = end = None
    for i, l in enumerate(lines):
        if not l.startswith("["):
            continue
        if start is not None:
            end = i
            break
        m = re.match(r"\[(.*)\](?: \d+)?\s*$", l)
        if m and m.group(1).lower() == esc:
            start = i
    if start is None:
        now = int(time.time())
        while lines and lines[-1] == "":
            lines.pop()
        lines += ["", "[%s] %d" % (key.replace("\\", "\\\\"), now),
                  "#time=%x" % ((now + 11644473600) * 10000000), line, ""]
    else:
        end = len(lines) if end is None else end
        at = None
        for i in range(start + 1, end):
            m = re.match(r'"((?:\\.|[^"\\])*)"=(.*)$', lines[i])
            if m and m.group(1).replace('\\"', '"').replace("\\\\", "\\").lower() == name.lower():
                at = i
                v = m.group(2).strip()
                if v.startswith("dword:"):
                    try:
                        if int(v[6:], 16) >= value:
                            return False
                    except ValueError:
                        pass
                break
        if at is not None:
            lines[at] = line
        else:
            i = start + 1
            while i < end and lines[i].startswith("#"):
                i += 1
            lines.insert(i, line)
    tmp = path + ".steam-arm.tmp"
    with open(tmp, "w", encoding="latin-1", newline="") as f:
        f.write("\n".join(lines))
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
    return True


def proc_stat(pid):
    """(comm, ppid, start time in clock ticks) from /proc/<pid>/stat."""
    st = open("/proc/%s/stat" % pid).read()
    rest = st[st.rindex(")") + 2:].split()
    return st[st.index("(") + 1:st.rindex(")")], rest[1], int(rest[19])


def prefix_busy(pfx, uid):
    """True while a wineserver of this user serves the prefix (by WINEPREFIX or its server dir name)."""
    rp = os.path.realpath(pfx)
    try:
        st = os.stat(pfx)
        sdir = "server-%x-%x" % (st.st_dev, st.st_ino)
    except OSError:
        sdir = None
    for p in glob.glob("/proc/[0-9]*"):
        try:
            if os.stat(p).st_uid != uid or open(p + "/comm").read().strip() != "wineserver":
                continue
        except OSError:
            continue
        try:
            if sdir and os.path.basename(os.readlink(p + "/cwd")) == sdir:
                return True
        except OSError:
            pass
        try:
            env = open(p + "/environ", "rb").read().split(b"\0")
        except OSError:
            return True
        for e in env:
            if e.startswith(b"WINEPREFIX=") and os.path.realpath(e[11:].decode("utf-8", "replace")) == rp:
                return True
    return False


def scan(steam, log, done, cache, waiting):
    uid = os.getuid()
    evdirs = [os.path.join(steam, "legacycompat"), os.path.join(steam, "steamrtarm64", "legacycompat")]
    for appid, lib, gamedir in titles(steam):
        if appid in done:
            continue
        pfx = None
        for l in (lib, os.path.join(steam, "steamapps")):
            c = os.path.join(l, "compatdata", appid, "pfx")
            if os.path.isfile(os.path.join(c, "system.reg")):
                pfx = c
                break
        if not pfx:
            continue
        if appid not in cache:
            cache[appid] = physx_rules(appid, install_scripts(gamedir), log)
        # Evaluator script is written per launch, so it is read again each pass.
        ev = [p for p in (os.path.join(d, "evaluatorscript_%s.vdf" % appid) for d in evdirs) if os.path.isfile(p)]
        rules = dict(cache[appid])
        for k, v in physx_rules(appid, ev, log).items():
            rules[k] = max(v, rules.get(k, 0))
        if not rules:
            continue
        if prefix_busy(pfx, uid):
            if appid not in waiting:
                waiting.add(appid)
                log("%s: prefix in use, PhysX value written once the title has ended" % appid)
            continue
        for (key, name), val in sorted(rules.items()):
            try:
                if reg_set(os.path.join(pfx, "system.reg"), key, name, val):
                    log("%s: [%s] \"%s\"=dword:%08x written, PhysX install step skipped from next start" % (appid, key, name, val))
            except OSError as e:
                log("%s: could not write system.reg: %s" % (appid, e))
                break
        else:
            done.add(appid)


def physx_procs(uid):
    for p in glob.glob("/proc/[0-9]*"):
        try:
            if os.stat(p).st_uid != uid:
                continue
            args = open(p + "/cmdline", "rb").read().split(b"\0")
            comm = open(p + "/comm").read().strip()
        except OSError:
            continue
        base = re.split(r"[\\/]", args[0].decode("utf-8", "replace"))[-1]
        if base.lower().startswith("physx") or comm.lower().startswith("physx"):
            yield int(p[6:]), base or comm
        # msiexec running a PhysX .msi package
        elif base.lower() == "msiexec.exe" and b"physx" in b" ".join(args[1:]).lower():
            yield int(p[6:]), base


def under_reaper(pid):
    p = str(pid)
    for _ in range(64):
        try:
            comm, ppid, _t = proc_stat(p)
        except (OSError, ValueError, IndexError):
            return False
        if comm == "reaper":
            return True
        if ppid in ("0", "1"):
            return False
        p = ppid
    return False


def stop_stuck(uid, log, termed):
    try:
        up = float(open("/proc/uptime").read().split()[0])
    except (OSError, ValueError):
        return
    hz = os.sysconf("SC_CLK_TCK")
    for pid, name in physx_procs(uid):
        if pid in termed:
            continue
        try:
            age = up - proc_stat(pid)[2] / hz
        except (OSError, ValueError, IndexError):
            continue
        if age > HANG_S and under_reaper(pid):
            try:
                os.kill(pid, signal.SIGTERM)
                log("%s (pid %d) running %d s without finishing: sent SIGTERM, Steam continues to the title" % (name, pid, age))
            except OSError:
                pass
            termed.add(pid)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("watch", "once"):
        sys.exit(__doc__.rsplit("Usage: ", 1)[1])
    steam = sys.argv[2]
    log = logger(sys.argv[3] if sys.argv[1] == "watch" and len(sys.argv) > 3 else None)
    done, cache, waiting, termed = set(), {}, set(), set()
    if sys.argv[1] == "once":
        scan(steam, log, done, cache, waiting)
        return
    uid, parent, last = os.getuid(), os.getppid(), 0.0
    while os.getppid() == parent:
        stop_stuck(uid, log, termed)
        if time.time() - last >= 10:
            last = time.time()
            scan(steam, log, done, cache, waiting)
        time.sleep(2)


if __name__ == "__main__":
    main()
PHYSXPY
chmod 755 /usr/local/lib/steam-arm-physx.py
cat > /usr/local/bin/steam-arm <<'LAUNCHER'
#!/bin/sh
# steam-arm: launches Steam client (native ARM64, or x86 through FEX on CPUs without Armv8.1 atomics); runs as desktop user.
# Help prints usage (any account, root too); it never starts a client (Steam itself has no --help).
case "${1:-}" in
  -h|--help|help)
    printf '%s\n' "Usage: steam-arm [Steam client options]" \
      "  steam-arm               start Steam client" \
      "  steam-arm --bigpicture  start client in Big Picture (restarts running client in it)" \
      "  steam-arm --desktop     start client in desktop interface (restarts running client in it)" \
      "  steam-arm --shutdown    stop running client (asks it to exit, SIGTERM after 20 s, x86 client 45 s)" \
      "  steam-arm --open URL    pass steam:// link to running client (never starts one)" \
      "  steam-arm --help        show this text" \
      "Run as account Steam ARM is set up for, not as root." \
      "Other options pass to Steam client unchanged. Settings: sudo steam-arm-config"
    exit 0;;
esac
if [ "$(id -u)" = 0 ]; then
  echo "steam-arm: run this as the desktop account that plays games, not as root" >&2; exit 1
fi
REALHOME="$HOME"
ARMHOME_DIR=.local/share/steam-arm            # relative to the user's home
[ -r /etc/steam-arm/steam-arm.conf ] && . /etc/steam-arm/steam-arm.conf
ARMHOME="${STEAM_ARM_HOME:-$REALHOME/$ARMHOME_DIR}"
S="$ARMHOME/.local/share/Steam"; D="$S/steamrtarm64"; F="$S/steamapps/common/FEX-Emu"
# Client type from setup (CLIENT in the settings file); anything else is the native client.
case "${CLIENT:-}" in x86) ;; *) CLIENT=arm64;; esac
NOPKG=/usr/local/lib/steam-arm-nopkg
# Stop: message on stderr, plus a dialog when started from a menu (display, no terminal).
stop(){
  echo "steam-arm: $1" >&2
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ ! -t 2 ] && command -v zenity >/dev/null 2>&1; then
    zenity --error --title="Steam ARM" --width=480 --text="$(printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')" 2>/dev/null
  fi
  exit 1
}
if command -v steam-arm-setup >/dev/null 2>&1; then SETUP=steam-arm-setup
elif [ -f /usr/local/share/steam-arm/steam-arm-install.sh ]; then SETUP="bash /usr/local/share/steam-arm/steam-arm-install.sh"
else SETUP="bash steam-arm-install.sh"; fi
# Client lives in the setup account's home; another account would find no client.
ME=$(id -un); SA_USER=$(sed -n 's/^GAMEUSER=//p' /etc/steam-arm/steam-arm.conf 2>/dev/null | tail -1)
if [ -z "${STEAM_ARM_HOME:-}" ] && [ -n "$SA_USER" ] && [ "$SA_USER" != "$ME" ]; then
  stop "Steam ARM is set up for account $SA_USER. Log in as $SA_USER to play, or set it up for this account: sudo steam-arm-config, then Install / Setup, then pick $ME. Or: sudo env GAMEUSER=$ME $SETUP --keep"
fi
export HOME="$ARMHOME"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export STEAM_COMPAT_GRAPHICS_PROVIDER=/opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json
export STEAMOS=1
# x86 client: runtime containers through host bubblewrap (pv-bwrap), no native graphics provider.
if [ "$CLIENT" = x86 ]; then
  unset STEAM_COMPAT_GRAPHICS_PROVIDER
  export PRESSURE_VESSEL_BWRAP=/usr/local/lib/steam-arm-pv-bwrap
fi
LOG="$ARMHOME/steam-arm.log"
# Log cap: over 1 MiB at start, current log becomes steam-arm.log.1 (one old copy kept).
[ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ] && mv -f "$LOG" "$LOG.1" 2>/dev/null
lwarn(){ echo "steam-arm: $*" >&2; printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }
# notice ID SUMMARY BODY TIMEOUT_MS: send (ID 0) or replace a desktop notification; prints its id.
notice(){
  if command -v gdbus >/dev/null 2>&1; then
    gdbus call --session --timeout 5 --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.Notify "Steam ARM" "$1" steam-arm "$2" "$3" '[]' '{}' "$4" 2>/dev/null \
      | sed -n 's/.*uint32 \([0-9]*\).*/\1/p'
  elif command -v notify-send >/dev/null 2>&1; then
    # no -p (libnotify before 0.7.9): one notice without updates
    notify-send -p -r "$1" -a "Steam ARM" -i steam-arm -t "$4" "$2" "$3" 2>/dev/null \
      || { [ "$1" = 0 ] && notify-send -a "Steam ARM" -i steam-arm -t 15000 "$2" "$3" 2>/dev/null; }
  fi
}
notice_close(){ command -v gdbus >/dev/null 2>&1 && gdbus call --session --timeout 5 --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.CloseNotification "$1" >/dev/null 2>&1; }
# Actionable warning: logged, plus a desktop notification when started from a menu; same text once per login session.
lnote(){
  lwarn "$1"
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ ! -t 2 ] || return 0
  seen="$XDG_RUNTIME_DIR/steam-arm-warned"
  grep -Fxq -- "$1" "$seen" 2>/dev/null && return 0
  printf '%s\n' "$1" >> "$seen" 2>/dev/null
  ( notice 0 "${2:-Steam ARM: warning}" "$1" 20000 ) </dev/null >/dev/null 2>&1 &
}
# Stop path: steam -shutdown, then SIGTERM after 20 s, 45 s for x86 client (a client can stop acting on forwarded command
# lines, for example after a second client ran with another HOME on the same account). Never SIGKILL.
client_running(){ pgrep -u "$(id -u)" -x steam >/dev/null 2>&1; }
client_wait(){ n=0; while client_running; do sleep 1; n=$((n + 1)); [ "$n" -ge "$1" ] && return 1; done; return 0; }
# x86 client: Valve's steam.sh under x86 bash from the RootFS (FEX); package tools refused first in PATH;
# private libX11 copy (X errors not fatal, from steam-arm-x86client.py prepare) first in host library path.
XLIB="$ARMHOME/.fex-emu/hostlib"
client_x86(){ ( cd "$S" && { [ ! -f "$XLIB/libX11.so.6" ] || export LD_LIBRARY_PATH="$XLIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; } \
  && PATH="$NOPKG:$PATH" exec FEX /usr/bin/bash "$S/steam.sh" "$@" ); }
stop_client(){
  local w=20
  client_running || return 0
  # x86 client shuts down through emulation: over 20 s on RK3588
  [ "${CLIENT:-}" = x86 ] && w=45
  if [ "${CLIENT:-}" = x86 ]; then client_x86 -shutdown >/dev/null 2>&1; else ( cd "$D" && ./steam -shutdown >/dev/null 2>&1 ); fi
  client_wait "$w" && return 0
  lwarn "client did not act on -shutdown within $w s; stopping it with SIGTERM"
  pkill -TERM -u "$(id -u)" -x steam 2>/dev/null
  client_wait 30 && return 0
  lwarn "client still running 30 s after SIGTERM; close it from its menu"; return 1
}
# Client start lock (guard below); held: first start or start in progress. Read from /proc/locks, never taken here.
STARTLOCK="$XDG_RUNTIME_DIR/steam-arm-start.lock"
{ [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; } || STARTLOCK="$ARMHOME/.steam-arm-start.lock"
STARTST="$STARTLOCK.state"
start_locked(){
  k=$(stat -c '%d %i' "$STARTLOCK" 2>/dev/null) || return 1
  set -- $k
  k=$(printf '%02x:%02x:%s' $((($1 >> 8) & 4095)) $((($1 & 255) | (($1 >> 12) & 1048320))) "$2")
  awk -v k="$k" '{ sub(/->/, "") } $2 == "FLOCK" && $6 == k { f = 1 } END { exit !f }' /proc/locks 2>/dev/null
}
# --open steam://...: link to running client only (tray Steam pages); never starts, stops or restarts a client.
open_link(){
  case "$1" in steam://*) ;; *) echo "steam-arm: --open needs steam:// link" >&2; return 2;; esac
  client_running || { echo "steam-arm: Steam is not running; start Steam ARM first" >&2; return 1; }
  start_locked && { echo "steam-arm: Steam ARM is starting; Steam pages open once Steam is up" >&2; return 1; }
  if [ "${CLIENT:-}" = x86 ]; then client_x86 "$1" >/dev/null 2>&1; else ( cd "$D" && ./steam "$1" >/dev/null 2>&1 ); fi
}
# --shutdown, --open: client type from this client folder (client-type record, else client files), not settings file.
if [ "${1:-}" = --shutdown ] || [ "${1:-}" = --open ]; then
  r=$(head -n 1 "$ARMHOME/.config/steam-arm/client-type" 2>/dev/null)
  case $r in arm64|x86) CLIENT=$r;; *) if [ -x "$D/steam" ]; then CLIENT=arm64; elif [ -x "$S/ubuntu12_32/steam" ]; then CLIENT=x86; fi;; esac
fi
case "${1:-}" in
  --shutdown) stop_client; exit $?;;
  --open) open_link "${2:-}"; exit $?;;
esac
# Installed client check (after --shutdown: stopping needs no client files).
if [ "$CLIENT" = x86 ]; then
  { [ -f "$S/steam.sh" ] && [ -x "$S/ubuntu12_32/steam" ]; } || stop "x86 Steam client not installed in $S. Setup did not finish; run it again: sudo steam-arm-config (Maintenance > Update / Repair) or sudo $SETUP --keep."
  # runtime tar (setup step 9) or its unpacked folder; without both steam.sh stops at "Couldn't set up the Steam Runtime"
  RTM="x86 Steam client runtime missing ($S/ubuntu12_32/steam-runtime.tar.xz). Run setup again to fetch it: sudo steam-arm-config (Maintenance > Update / Repair) or sudo $SETUP --keep."
  [ -f "$S/ubuntu12_32/steam-runtime.tar.xz.checksum" ] || [ -x "$S/ubuntu12_32/steam-runtime/setup.sh" ] || stop "$RTM"
elif [ ! -x "$D/steam" ]; then
  stop "Steam client not installed in $S. Setup did not finish; run it again: sudo steam-arm-config (Maintenance > Update / Repair) or sudo $SETUP --keep. On Raspberry Pi 5, reboot first if setup switched to 4K page kernel."
fi
# Client needs Armv8.1 atomics (LSE); STEAM_ARM_ALLOW_ARMV80=1 skips the check.
# Native client only: x86 client runs on Armv8.0; native client chosen by hand (CLIENT_SET=user) or passing setup's
# check on this CPU (CLIENT_PROBE VER:ok, setup's switch back from x86 client) is not stopped.
CPUF=$(grep -m1 '^Features' /proc/cpuinfo 2>/dev/null)
if [ "${CLIENT:-arm64}" != x86 ] && [ "${CLIENT_SET:-}" != user ] && [ -n "$CPUF" ] && [ "${STEAM_ARM_ALLOW_ARMV80:-0}" != 1 ] \
   && case "${CLIENT_PROBE:-}" in *:ok) false;; *) true;; esac; then
  case " ${CPUF#*:} " in *" atomics "*) ;; *)
    LSE="This CPU has no Armv8.1 atomics (LSE). Native ARM64 client needs Armv8.1 or newer; builds newer than 15 April 2026 stop at start with SIGILL on Armv8.0 cores (Cortex-A53, A57, A72: Raspberry Pi 4 and 3). Client issue: https://github.com/ValveSoftware/steam-for-linux/issues/13288. Run setup again (sudo steam-arm-config, Maintenance > Update / Repair): it installs x86 client through emulation on this CPU. STEAM_ARM_ALLOW_ARMV80=1 skips this check."
    lwarn "$LSE" 2>/dev/null; stop "$LSE";;
  esac
fi
# Emulation needs 4K pages; STEAM_ARM_IGNORE_PAGESIZE=1 skips it (x86 side in a separate 4K guest).
PGSZ=$(getconf PAGESIZE 2>/dev/null || echo 4096)
if [ "$PGSZ" != 4096 ] && [ "${STEAM_ARM_IGNORE_PAGESIZE:-0}" != 1 ]; then
  PSM="Kernel page size is $PGSZ bytes; emulation of x86 games needs 4096 (4K). Raspberry Pi 5: sudo steam-arm-config, Components, select page-size (or add kernel=kernel8.img to firmware config.txt), then reboot. Other systems: boot a 4K page kernel (on most distributions a separate kernel package). STEAM_ARM_IGNORE_PAGESIZE=1 (environment, or a line in /etc/steam-arm/steam-arm.conf) skips this check."
  lwarn "$PSM" 2>/dev/null; stop "$PSM"
fi
# GPU access: test -r/-w follow ACLs, so seat (uaccess) grants count.
RNODE=; RGRP=
for r in /dev/dri/renderD*; do
  [ -e "$r" ] || continue
  [ -r "$r" ] && [ -w "$r" ] && { RNODE=$r; break; }
  RGRP=$(stat -c %G "$r" 2>/dev/null)
done
if [ -z "$RNODE" ]; then
  if [ -n "$RGRP" ] && [ "$RGRP" != root ]; then
    lnote "No GPU render node (/dev/dri/renderD*) readable and writable by account $(id -un); games draw on CPU. Fix: sudo usermod -aG $RGRP $(id -un), then log out and back in."
  elif [ -n "$RGRP" ]; then
    lnote "No GPU render node (/dev/dri/renderD*) readable and writable by account $(id -un); games draw on CPU. Check permissions of /dev/dri/renderD* (udev rules of GPU driver)."
  elif [ -e /dev/mali0 ]; then
    lnote "No GPU render node (/dev/dri/renderD*) found: closed Mali driver (mali_kbase) in use; games draw on CPU. Fix: kernel with Mesa's panfrost or panthor GPU driver."
  else
    lnote "No GPU render node (/dev/dri/renderD*) found; games draw on CPU. Check that kernel GPU driver is loaded."
  fi
fi
# Component chosen at install (COMPONENTS_ON in the settings file; all count as chosen when the file has no list).
comp_on(){ [ -z "${COMPONENTS_ON+x}" ] && return 0; case ",$COMPONENTS_ON," in *",$1,"*) return 0;; esac; return 1; }
# Graphics route is picked per title by the launch handler; here only a note when its second tree is gone.
comp_on gpu-in-emulation && [ -n "${COMPONENTS_ON+x}" ] && [ ! -f /opt/fex-rootfs/Ubuntu_24_04-mali/.steam-arm-mali ] \
  && lnote "Mali drivers inside the emulation missing, titles that need them use forwarding; run the installer again to restore them"
# kde-input-prompt: KDE's input permission for X11 programs, set (component on) or put back (off) in this session.
KDEIN=/usr/local/lib/steam-arm-kde-input; KDEM="$REALHOME/.config/steam-arm/kde-input-prompt"
if [ -x "$KDEIN" ]; then
  if [ -n "${COMPONENTS_ON+x}" ] && comp_on kde-input-prompt && [ ! -f "$KDEM" ]; then
    case "${XDG_CURRENT_DESKTOP:-}" in *KDE*) HOME="$REALHOME" "$KDEIN" on >/dev/null 2>&1 \
      || lwarn "kde-input-prompt could not be applied; KDE may ask before controller sends input";; esac
  elif ! comp_on kde-input-prompt && [ -f "$KDEM" ]; then
    HOME="$REALHOME" "$KDEIN" off >/dev/null 2>&1 || lwarn "kde-input-prompt could not be reversed; next start tries again"
  fi
fi
# Private GLX copy only when chosen and loadable; otherwise system Mesa GLX.
LAX=/usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0; LAX_BAD=0
if comp_on glx-lax; then
  if [ ! -f "$LAX" ]; then
    LAX_BAD=1; lnote "private GLX copy missing, using system Mesa GLX; run the installer again to rebuild it"
  elif ! out=$(ldd "$LAX" 2>&1) || printf '%s\n' "$out" | grep -q 'not found'; then
    LAX_BAD=1; lnote "private GLX copy cannot load its libraries, using system Mesa GLX; run: sudo steam-arm-glx-lax"
  else
    export __GLX_VENDOR_LIBRARY_NAME=steamarmlax
  fi
fi
# shader-cache (listed by name only): pre-caching on; this key turns off Steam's arm64, x86_64 and i386 fossilize layers (arm64 one crashes Proton titles in vkCreateDevice).
NOSHADERS=-noshaders
if [ -n "${COMPONENTS_ON+x}" ] && comp_on shader-cache; then
  NOSHADERS=; export DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1
fi
# Proton titles use host Vulkan.
comp_on vk-spoof && [ -f /usr/share/vulkan/implicit_layer.d/VkLayer_steam_arm_spoof.json ] && export STEAM_ARM_VK_SPOOF=1
# PROTON_DXVK_D3D8=1: use DXVK's d3d8 (wined3d's GL path misrenders on Mali); launch option can override.
export PROTON_DXVK_D3D8="${PROTON_DXVK_D3D8:-1}"

BOOTLOG="$S/logs/bootstrap_log.txt"
FIRST_MSG="Downloading client files, this takes a few minutes. Steam opens when done."
[ "$CLIENT" = x86 ] && FIRST_MSG="Downloading x86 client files, this takes several minutes. Steam opens when done."
# First start: the client's bootstrap downloads its files (about 650 MB) with no window; a desktop
# notification, updated in place from the bootstrap log, reports it. Never on later starts.
# Last bootstrap phase after byte $1 of the log: download (10 % steps), unpack, install, "done", or empty.
boot_phase(){
  tail -c +"$(($1 + 1))" "$BOOTLOG" 2>/dev/null | awk '
    /\] Downloading update \(/ { s = $0; sub(/.*\(/, "", s); sub(/ KB\).*/, "", s); gsub(/,/, "", s); split(s, a, " of ")
      if (a[2] > 0) m = sprintf("Downloading client files: %d%% of %d MB", int(a[1] * 10 / a[2]) * 10, a[2] / 1024) }
    /\] Extracting package/ { m = "Unpacking client files" }
    /\] Installing update/ { m = "Installing client files" }
    /\] Update complete/ { m = "done" }
    END { print m }'
}
# Runs beside the bootstrap: a notice at once, phases as they change, "done" or a vanished client ends it.
first_start_notice(){
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 0
  off=$(stat -c %s "$BOOTLOG" 2>/dev/null || echo 0)
  id=$(notice 0 "Steam ARM: first start" "$FIRST_MSG" 0)
  case "$id" in ''|0) return 0;; esac
  trap 'notice_close "$id"; exit 143' TERM
  last=; n=0
  while [ "$n" -lt 1800 ]; do
    sleep 5; n=$((n + 5))
    m=$(boot_phase "$off")
    if [ "$m" = done ]; then notice "$id" "Steam ARM" "Client files installed. Steam opens now." 10000 >/dev/null; return 0; fi
    [ "$n" -ge 10 ] && ! client_running && break
    [ -n "$m" ] && [ "$m" != "$last" ] && { notice "$id" "Steam ARM: first start" "$m" 0 >/dev/null; last=$m; }
  done
  notice_close "$id"
}
# One client start at once: lock held through first start, update restarts and normal start until client window
# runs; another launch meanwhile (repeated clicks) shows progress and exits, never stops or restarts client.
start_state(){ [ -e "$STARTST" ] && printf '%s\n' "$1" > "$STARTST"; }
# State "first OFFSET" (bootstrap log byte at first start): phase text; else client starting.
start_msg(){
  st=$(head -n 1 "$STARTST" 2>/dev/null)
  case $st in
    "first "*)
      m=$(boot_phase "${st#first }")
      case $m in
        Downloading*) m="downloading client files (${m#*: })";;
        Unpacking*) m="unpacking client files";;
        Installing*) m="installing client files";;
        done) m="starting client";;
        *) m="downloading client files";;
      esac
      echo "Steam ARM is still setting up: $m. Steam opens by itself when done.";;
    *) echo "Steam ARM is starting. Steam opens by itself when ready.";;
  esac
}
# Second launch: stderr and log; from a menu one notice replaced in place per click, dialog when no notice service.
start_busy(){
  msg=$(start_msg)
  echo "steam-arm: $msg" >&2
  printf '%s %s\n' "$(date '+%F %T')" "start while client starts: not started again ($msg)" >> "$LOG" 2>/dev/null
  { [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ ! -t 2 ]; } || return 0
  nid=$(head -n 1 "$STARTLOCK.note" 2>/dev/null); case $nid in ''|*[!0-9]*) nid=0;; esac
  nid=$(notice "$nid" "Steam ARM" "$msg" 10000)
  case $nid in
    ''|0) command -v zenity >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 \
            && ( flock -n 8 || exit 0; zenity --info --title="Steam ARM" --width=420 --text="$msg" 2>/dev/null ) 8>"$STARTLOCK.dialog";;
    *) printf '%s\n' "$nid" > "$STARTLOCK.note" 2>/dev/null;;
  esac
  return 0
}
# Holder of the lock: ends with launcher, or after normal start began once client window process runs (cap 180 s).
start_hold(){
  n=0
  while kill -0 "$1" 2>/dev/null; do
    if [ "$(head -n 1 "$STARTST" 2>/dev/null)" = start ]; then
      n=$((n + 1))
      [ "$n" -ge 180 ] && break
      [ "$n" -ge 3 ] && pgrep -u "$(id -u)" -f steamwebhelper >/dev/null 2>&1 && break
    fi
    sleep 1
  done
  rm -f "$STARTST"
}
if command -v flock >/dev/null 2>&1 && ( : >> "$STARTLOCK" ) 2>/dev/null; then
  exec 7>>"$STARTLOCK"
  flock -n 7 || { start_busy; exit 0; }
  echo init > "$STARTST"
  # lock fd only in holder: client and helpers started later never keep it
  start_hold $$ </dev/null >/dev/null 2>&1 &
  exec 7>&-
fi

# Pause steam-arm-pad-xbox while this client runs (its own Steam Input re-IDs pads; the service would starve direct pad reads); resume on exit.
PADSVC=0
if [ -f /etc/systemd/system/steam-arm-pad-xbox.service ] && systemctl is-active --quiet steam-arm-pad-xbox 2>/dev/null; then
  PADSVC=1; sudo -n systemctl stop steam-arm-pad-xbox 2>/dev/null || systemctl stop steam-arm-pad-xbox 2>/dev/null
fi
restore_pad(){ [ "$PADSVC" = 1 ] && { sudo -n systemctl start steam-arm-pad-xbox 2>/dev/null || systemctl start steam-arm-pad-xbox 2>/dev/null; }; }
# Display mode (X11): a title that switches mode and quits, crashes or is stopped can leave it set.
# Modes are saved when a title starts and put back once no title runs, and when Steam closes.
MODEF="$XDG_RUNTIME_DIR/steam-arm-display-mode"
game_up(){ pgrep -u "$(id -u)" -f 'reaper SteamLaunch' >/dev/null 2>&1; }
mode_ok(){ [ -n "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${STEAM_ARM_MODE_RESTORE:-1}" != 0 ] && command -v xrandr >/dev/null 2>&1; }
# One line per active output: name, mode id, geometry (WxH+X+Y).
mode_get(){ xrandr --verbose 2>/dev/null | awk '/^[^ \t].* connected/ { for (i = 3; i < NF; i++) if ($i ~ /^[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+$/ && $(i + 1) ~ /^\(0x[0-9a-f]+\)$/) { m = $(i + 1); gsub(/[()]/, "", m); print $1, m, $i } }'; }
mode_restore(){
  [ -s "$MODEF" ] || return 0
  now=$(mode_get); [ -n "$now" ] || return 0
  [ "$now" = "$(cat "$MODEF")" ] && return 0
  fb=$(awk '{ split($3, g, /[x+]/); w = g[1] + g[3]; h = g[2] + g[4]; if (w > W) W = w; if (h > H) H = h } END { if (W) print W "x" H }' "$MODEF")
  set --
  while read -r o m g; do
    p=${g#*+}; set -- "$@" --output "$o" --mode "$m" --pos "${p%%+*}x${p#*+}"
  done < "$MODEF"
  if xrandr ${fb:+--fb "$fb"} "$@" 2>/dev/null; then lwarn "display mode put back after game: $(paste -sd ' ' "$MODEF")"
  else lnote "display mode could not be put back ($(paste -sd ' ' "$MODEF")); set it in display settings"; fi
}
# Called every second by the watcher: save before a title switches, restore 2 s after the last one ends.
mode_watch(){
  mode_ok || return 0
  if game_up; then
    [ -s "$MODEF" ] || mode_get > "$MODEF"
  elif [ -s "$MODEF" ]; then
    sleep 2; game_up && return 0
    mode_restore; rm -f "$MODEF"
  fi
}
# Bluetooth: SteamOS mode sets adapter power from saved System/Bluetooth/Enabled (unset = off); host state is saved there first.
BTPOW=; BTSEED=
bt_powered(){ command -v bluetoothctl >/dev/null 2>&1 && timeout 5 bluetoothctl show 2>/dev/null | awk '$1 == "Powered:" { print $2; exit }'; }
# $1 0/1: write value (Steam closed); no $1: print saved value.
bt_saved(){ python3 - "$S/config/config.vdf" "${1:-}" <<'BTPY'
import os, re, sys, tempfile
p, want = sys.argv[1], sys.argv[2]
try:
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
except FileNotFoundError:
    s = None


def block(s, name, ind, lo, hi):
    m = re.compile(r'\n%s"%s"\n%s\{\n' % (ind, name, ind)).search(s, lo, hi)
    if not m:
        return None
    e = s.find("\n%s}" % ind, m.end() - 1, hi)
    return (m.end(), e + 1) if e >= 0 else None


sysb = block(s, "System", "\t", 0, len(s)) if s else None
btb = block(s, "Bluetooth", "\t\t", sysb[0] - 1, sysb[1]) if sysb else None
en = re.compile(r'^\t\t\t"Enabled"\t\t"([^"]*)"\n', re.M).search(s, btb[0], btb[1]) if btb else None
if not want:
    print(en.group(1) if en else "")
    sys.exit(0)
line = '\t\t\t"Enabled"\t\t"%s"\n' % want
if s is None:
    os.makedirs(os.path.dirname(p), exist_ok=True)
    s = '"InstallConfigStore"\n{\n\t"System"\n\t{\n\t\t"Bluetooth"\n\t\t{\n%s\t\t}\n\t}\n}\n' % line
elif en:
    if en.group(1) == want:
        sys.exit(0)
    s = s[:en.start()] + line + s[en.end():]
elif btb:
    s = s[:btb[0]] + line + s[btb[0]:]
elif sysb:
    s = s[:sysb[0]] + '\t\t"Bluetooth"\n\t\t{\n%s\t\t}\n' % line + s[sysb[0]:]
else:
    i = s.rstrip().rfind("}")
    if not s.startswith('"InstallConfigStore"') or i < 0:
        sys.exit("config.vdf: InstallConfigStore block not found")
    s = s[:i] + '\t"System"\n\t{\n\t\t"Bluetooth"\n\t\t{\n%s\t\t}\n\t}\n' % line + s[i:]
mode = os.stat(p).st_mode & 0o7777 if os.path.exists(p) else 0o644
fd, t = tempfile.mkstemp(prefix=".steam-arm-", dir=os.path.dirname(p))
with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(s)
os.chmod(t, mode)
os.replace(t, p)
BTPY
}
# Exit: adapter powered before start and off now, not switched off in Steam's settings: power it on again.
bt_restore(){
  [ "$BTSEED" = 1 ] && [ "$BTPOW" = yes ] && ! client_running || return 0
  [ "$(bt_powered)" = no ] || return 0
  [ "$(bt_saved 2>/dev/null)" = 0 ] && return 0
  if timeout 10 bluetoothctl power on >/dev/null 2>&1; then lwarn "Bluetooth adapter left off by client; powered on again"
  else lnote "Bluetooth adapter left off by client and could not be powered on; turn it on in system settings"; fi
}
FEXWATCH=; PHYSXWATCH=; NOTEWATCH=
# Single exit path: stop the watchers, put back a display mode a title left, restore the pad service and Bluetooth power.
on_exit(){ [ -n "$FEXWATCH" ] && kill "$FEXWATCH" 2>/dev/null; [ -n "$PHYSXWATCH" ] && kill "$PHYSXWATCH" 2>/dev/null
  [ -n "$NOTEWATCH" ] && kill "$NOTEWATCH" 2>/dev/null
  mode_ok && ! game_up && { mode_restore; rm -f "$MODEF"; }; restore_pad; bt_restore; }
trap on_exit EXIT
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
# Another x86 Steam client (not from this client folder) running.
if pgrep -af 'ubuntu12_32/steam ' 2>/dev/null | awk -v s="$S/" 'index($0, s) == 0 { f = 1 } END { exit !f }'; then
  command -v zenity >/dev/null 2>&1 && zenity --warning --text="The x86 Steam client is running. Close it first; two clients fight over the controller and steam:// links." 2>/dev/null
fi
printf '%s client: %s\n' "$(date '+%F %T')" "$([ "$CLIENT" = x86 ] && echo 'x86 through emulation' || echo 'native ARM64')" >> "$LOG" 2>/dev/null

# --- client-side links (normally made by x86 steam.sh) ---
mkdir -p "$ARMHOME/.steam"
ln -sfn "$S" "$ARMHOME/.steam/steam"; ln -sfn "$S" "$ARMHOME/.steam/root"
ln -sfn "$S/linux32" "$ARMHOME/.steam/sdk32"; ln -sfn "$S/linux64" "$ARMHOME/.steam/sdk64"
ln -sfn "$S/linuxarm64" "$ARMHOME/.steam/sdkarm64"   # sdk dir: steamclient.so for games and Proton, steam-launch-wrapper
ln -sfn "$S/ubuntu12_32" "$ARMHOME/.steam/bin32"; ln -sfn "$S/ubuntu12_64" "$ARMHOME/.steam/bin64"

if [ "$CLIENT" = arm64 ]; then
# --- launch wrapper stand-in (only if package copy missing) ---
if [ ! -x "$S/linuxarm64/steam-launch-wrapper" ] && [ ! -x "$D/steam-launch-wrapper" ]; then
cat > "$D/steam-launch-wrapper" <<'SH'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in
  --oom-score-adjust) [ -n "$2" ] && echo "$2" > /proc/self/oom_score_adj 2>/dev/null; shift 2;;
  --oom-score-adjust=*) echo "${1#*=}" > /proc/self/oom_score_adj 2>/dev/null; shift;;
  --) shift; break;; *) shift;; esac; done
exec "$@"
SH
chmod 755 "$D/steam-launch-wrapper"
fi

# --- Remote Play: ARM client's V4L2 path fails (steam-for-linux #13428); run x86-64 client under FEX (software decode, strip --openvr) ---
if [ -f "$D/streaming_client" ] && [ "$(head -c 4 "$D/streaming_client" | tr -d '\177')" = "ELF" ]; then
  mv -f "$D/streaming_client" "$D/streaming_client.real"      # only the real binary is ever moved aside
fi
# stand-in rewritten whenever its body differs (older releases' stand-ins included)
cat > "$D/streaming_client.new" <<'SH'
#!/bin/sh
# Stand-in: run the x86-64 streaming client from this package under FEX (see steam-arm).
here="$(dirname "$0")"; S="$(dirname "$here")"
for a in "$@"; do shift; [ "$a" = "--openvr" ] || set -- "$@" "$a"; done
export LD_LIBRARY_PATH="$S/linux64:$S/ubuntu12_64:$S/ubuntu12_32${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
unset __GLX_VENDOR_LIBRARY_NAME
export SDL_VIDEO_X11_FORCE_EGL=0
F=$(command -v FEX) || F=/usr/bin/FEX
cd "$S" && exec "$F" "$S/ubuntu12_64/streaming_client" "$@"
SH
if [ -x "$D/streaming_client" ] && cmp -s "$D/streaming_client.new" "$D/streaming_client"; then rm -f "$D/streaming_client.new"
else chmod 755 "$D/streaming_client.new" && mv -f "$D/streaming_client.new" "$D/streaming_client"; fi
else
# --- x86 client: webhelper flag, launch wrapper stand-in, FEX app settings, native update channel aside (each start) ---
xo=$(python3 /usr/local/lib/steam-arm-x86client.py prepare "$S" "$ARMHOME" 2>&1); xrc=$?
[ -n "$xo" ] && printf '%s\n' "$xo" | while IFS= read -r l; do printf '%s %s\n' "$(date '+%F %T')" "$l" >> "$LOG" 2>/dev/null; done
[ "$xrc" = 0 ] || lnote "$(printf '%s\n' "$xo" | tail -1 | sed 's/^warning: //')"
fi
# system FEX config for the x86 streaming client (same rootfs, thunks and host settings as the x86 stack)
mkdir -p "$ARMHOME/.fex-emu"; [ -f "$ARMHOME/.fex-emu/Config.json" ] || cp -f "$REALHOME/.fex-emu/Config.json" "$ARMHOME/.fex-emu/Config.json" 2>/dev/null
# Unusable GLX copy: drop its HostEnv entry from this copy; put it back once the copy works again.
FEXCFG="$ARMHOME/.fex-emu/Config.json"
if [ "$LAX_BAD" = 1 ] && grep -q steamarmlax "$FEXCFG" 2>/dev/null; then
  python3 -c 'import sys; p = sys.argv[1]; s = open(p).read(); open(p, "w").write(s.replace(",\n  \"HostEnv\":\"__GLX_VENDOR_LIBRARY_NAME=steamarmlax\"", ""))' "$FEXCFG"
elif [ -n "${__GLX_VENDOR_LIBRARY_NAME:-}" ] && ! grep -q steamarmlax "$FEXCFG" 2>/dev/null \
     && grep -q steamarmlax "$REALHOME/.fex-emu/Config.json" 2>/dev/null; then
  cp -f "$REALHOME/.fex-emu/Config.json" "$FEXCFG"
fi

# --- Valve's FEX compat tool: patch thunk paths/socket so GL/Vulkan aren't CPU (llvmpipe); a watcher re-applies it on change ---
FEXPATCH=/usr/local/lib/steam-arm-fexpatch.py
# FEX 2609+ lists the container thunk paths itself; same VERSIONS.txt parse as steam-arm-fexpatch.py.
fex_new(){ v=$(grep -o 'FEX-[0-9]\{4\}' "$F/VERSIONS.txt" 2>/dev/null | head -1 | cut -c5-8); [ -n "$v" ] && [ "$v" -ge 2609 ]; }
# Thunks "1" in the template (per-title off goes through FEX_APP_CONFIG); same rule as steam-arm-fexpatch.py.
fex_ok(){ { fex_new || grep -q '/run/gfx/main/' "$F/usr/share/fex-emu/ThunksDB.json" 2>/dev/null; } \
  && grep -q '"GL": "1"' "$F/ConfigTemplate.json" 2>/dev/null && grep -q '"Vulkan": "1"' "$F/ConfigTemplate.json" 2>/dev/null \
  && grep -Eq '"SilentLog" *: *"1"' "$F/ConfigTemplate.json" 2>/dev/null \
  && grep -q "\"/run/user/$(id -u)/steam-arm-fexserver.sock\"" "$F/ConfigTemplate.json" 2>/dev/null \
  && { grep -q '/usr/local/lib/steam-arm-handler.py' "$F/fex-compat-tool" 2>/dev/null || ! grep -q "LD_PRELOAD" "$F/fex-compat-tool" 2>/dev/null; }; }
# Patch only when one of the three files changed since the last look (size, time, inode); a failure is logged once.
FEXST=; FEXMSG=
fex_stamp(){ stat -c '%s %Y %i' "$F/ConfigTemplate.json" "$F/fex-compat-tool" "$F/usr/share/fex-emu/ThunksDB.json" 2>/dev/null | tr '\n' ' '; }
# $1 --no-wait: start-up call, never delays Steam (the watcher waits for a tool update to finish).
fex_check(){
  [ "$CLIENT" = arm64 ] && [ -d "$F" ] || return 0
  st=$(fex_stamp); [ "$st" = "$FEXST" ] && return 0
  if ! fex_ok; then
    msg=$(python3 "$FEXPATCH" ${1:+"$1"} "$F" 2>&1); rc=$?
    # 75: Steam is still writing the tool; next look tries again
    [ "$rc" = 75 ] && return 0
    if [ "$rc" != 0 ]; then
      msg=$(printf '%s\n' "$msg" | tail -1)
      [ "$msg" = "$FEXMSG" ] || lwarn "${msg:-steam-arm-fexpatch failed}"
      FEXMSG=$msg
    fi
  fi
  FEXST=$(fex_stamp)
}
fex_check --no-wait
# Steam overlay/FEX leak /dev/shm segments (fills half of RAM -> SIGBUS); sweep unused ones at start and every minute.
shm_sweep(){ python3 - "$(id -u)" 2>/dev/null <<'SHMPY'
import ctypes, glob, os, sys, time
uid = int(sys.argv[1]); now = time.time(); used = set(); mappers = {}; game = False
for p in glob.glob("/proc/[0-9]*"):
    try:
        comm = open(p + "/comm").read().strip()
        if os.stat(p).st_uid == uid and b"SteamLaunch" in open(p + "/cmdline", "rb").read():
            game = True
        for line in open(p + "/maps"):
            i = line.find("/dev/shm/")
            if i >= 0:
                used.add(line[i:].split()[0])
                mappers.setdefault(line[i:].split()[0], set()).add(comm)
    except OSError:
        pass
    try:
        for fd in os.listdir(p + "/fd"):
            try:
                t = os.readlink(p + "/fd/" + fd)
            except OSError:
                continue
            if t.startswith("/dev/shm/"):
                used.add(t.split()[0])
    except OSError:
        pass
for f in glob.glob("/dev/shm/u%d-Shm_*" % uid):
    try:
        if f not in used and now - os.stat(f).st_mtime > 60:
            os.unlink(f)
    except OSError:
        pass
# Overlay frame buffers of ended sessions stay mapped by steamwebhelper (25 MB each); with no game
# running, punch them (FALLOC_FL_PUNCH_HOLE|KEEP_SIZE): pages freed, size and mappings kept.
if not game:
    libc = ctypes.CDLL(None, use_errno=True)
    for f in glob.glob("/dev/shm/u%d-Shm_*" % uid):
        try:
            st = os.stat(f)
            if mappers.get(f) == {"steamwebhelper"} and st.st_blocks and st.st_size >= 8 << 20 \
                    and now - st.st_mtime > 60:
                fd = os.open(f, os.O_RDWR)
                try:
                    libc.fallocate(fd, 3, ctypes.c_long(0), ctypes.c_long(st.st_size))
                finally:
                    os.close(fd)
        except OSError:
            pass
for f in glob.glob("/dev/shm/fex-*-stats"):
    pid = f[len("/dev/shm/fex-"):-len("-stats")]
    try:
        if pid.isdigit() and os.stat(f).st_uid == uid and not os.path.exists("/proc/" + pid):
            os.unlink(f)
    except OSError:
        pass
SHMPY
}
shm_sweep
( n=0; while sleep 1; do fex_check; mode_watch; n=$((n + 1)); [ $((n % 60)) -eq 0 ] && shm_sweep; done ) &
FEXWATCH=$!
# physx-skip (listed by name; old settings file = on): PhysX install step of Proton titles hangs, mark it done in the prefix, else SIGTERM it after 60 s.
# STEAM_ARM_PHYSX_SKIP=0 or =1 overrides it for this session.
PHYSX=1
case ",${COMPONENTS_ON:-}," in *,physx-skip,*) ;; *) case ",${COMPONENTS_OFF:-}," in *,physx-skip,*) PHYSX=0;; esac;; esac
case "${STEAM_ARM_PHYSX_SKIP:-}" in 0) PHYSX=0;; 1) PHYSX=1;; esac
if [ "$PHYSX" = 1 ] && [ -f /usr/local/lib/steam-arm-physx.py ]; then
  python3 /usr/local/lib/steam-arm-physx.py watch "$S" "$LOG" </dev/null >/dev/null 2>&1 &
  PHYSXWATCH=$!
fi

# --- Remote Play settings: pin hardware decode + HEVC off before start (client rewrites the file on exit) ---
if command -v steam-arm-remoteplay >/dev/null 2>&1 && ! client_running; then
  steam-arm-remoteplay >/dev/null 2>&1
fi

# --- interface: Deck (gamepadui) by default; -gamepadui off shows the client's own tray icon via xembedsniproxy ---
GPUI=-gamepadui
[ "$STEAM_ARM_UI" = desktop ] && GPUI=
SWITCH=
case "$1" in
  --desktop) GPUI=; SWITCH=1; shift;;
  --bigpicture) GPUI=-gamepadui; SWITCH=1; shift;;
esac
# Switching interface: stop the running client, then restart in the requested mode.
if [ -n "$SWITCH" ] && client_running; then
  stop_client || exit 1
fi

# Menu icon comes from the client's own icon file, absent until its first start (setup draws a plain
# disc meanwhile). Wait for it in the background (poll every 5 s, up to 15 min) so start is never
# delayed; flock keyed by uid stops a second concurrent start from waiting twice. Drawn once the file
# keeps its size over one poll (client unpacks it); KDE programs reload icons on KIconLoader's signal.
UICON="$REALHOME/.local/share/icons/hicolor"
if command -v steam-arm-icon >/dev/null 2>&1 \
   && { [ ! -f "$UICON/256x256/apps/steam-arm.png" ] || [ -e "$UICON/.steam-arm-placeholder" ]; } \
   && { [ ! -f /usr/share/icons/hicolor/256x256/apps/steam-arm.png ] || [ -e /usr/local/share/steam-arm/icon-placeholder ]; }; then
  ICONLOCK="${XDG_RUNTIME_DIR:-/tmp}/steam-arm-icon-wait-$(id -u).lock"
  ( flock -n 9 || exit 0
    STEP=5; n=0; last=
    while :; do
      sz=$(stat -c %s "$S/public/steam_tray.ico" 2>/dev/null)
      [ -n "$sz" ] && [ "$sz" -gt 0 ] && [ "$sz" = "$last" ] && break
      last=$sz; n=$((n + STEP)); [ "$n" -ge 900 ] && exit 0
      sleep "$STEP"
    done
    steam-arm-icon "$S" "$UICON" || exit 0
    if command -v kbuildsycoca6 >/dev/null 2>&1; then HOME="$REALHOME" kbuildsycoca6
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then HOME="$REALHOME" kbuildsycoca5
    fi
    # icon groups 0-5, as KDE's icon settings page sends on theme change
    for g in 0 1 2 3 4 5; do
      if command -v gdbus >/dev/null 2>&1; then
        gdbus emit --session --object-path /KIconLoader --signal org.kde.KIconLoader.iconChanged "$g"
      elif command -v dbus-send >/dev/null 2>&1; then
        dbus-send --session --type=signal /KIconLoader org.kde.KIconLoader.iconChanged "int32:$g"
      fi
    done
    for d in "$REALHOME/Desktop/Steam ARM.desktop" "$REALHOME/Desktop/Steam ARM (Desktop mode).desktop"; do
      [ -f "$d" ] && touch "$d"
    done
  ) >/dev/null 2>&1 9>"$ICONLOCK" &
fi

# Client build has no tray icon; steam-arm-tray supplies one (locked single instance, user's own HOME).
if command -v steam-arm-tray >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  HOME="$REALHOME" setsid steam-arm-tray </dev/null >/dev/null 2>&1 &
fi

# Register the client's arm64 overlay Vulkan layer, gated by STEAM_ARM_VK_OVERLAY (handler sets it for overlay=vulkan titles only; always-on crashes Proton ARM64).
VKL="$ARMHOME/.local/share/vulkan/implicit_layer.d"
if [ "$CLIENT" = arm64 ] && [ -f "$D/steamoverlayvulkanlayer.so" ]; then
  mkdir -p "$VKL"; rm -f "$VKL/steamoverlay_arm64.json" "$VKL/steamoverlay_arm64.json.off"
  # a second registration of this layer (other installer flavour) hangs Vulkan titles at start
  for j in "$VKL"/*.json; do
    [ "$j" = "$VKL/steamoverlay_arm64_steamarm.json" ] && continue
    grep -qs 'steamrtarm64/steamoverlayvulkanlayer.so' "$j" && rm -f "$j"
  done
  cat > "$VKL/steamoverlay_arm64_steamarm.json" <<VKJSON
{
  "file_format_version": "1.0.0",
  "layer": {
    "name": "VK_LAYER_VALVE_steam_overlay_arm64_steamarm",
    "type": "GLOBAL",
    "library_path": "$D/steamoverlayvulkanlayer.so",
    "api_version": "1.3.207",
    "implementation_version": "1",
    "description": "Steam overlay layer (arm64), registered by steam-arm for profiled Vulkan titles",
    "disable_environment": { "DISABLE_VK_LAYER_VALVE_steam_overlay_1": "1" },
    "enable_environment": { "STEAM_ARM_VK_OVERLAY": "1" }
  }
}
VKJSON
fi

# gameoverlayui crashes without the client dir on LD_LIBRARY_PATH; the client doesn't add it, so the launcher does.
[ "$CLIENT" = x86 ] || export LD_LIBRARY_PATH="$D${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Client keeps host Bluetooth power as found (client rewrites config.vdf on exit, so only while closed).
if ! client_running; then
  BTPOW=$(bt_powered)
  case "$BTPOW" in
    yes|no) if bt_saved "$([ "$BTPOW" = yes ] && echo 1 || echo 0)" 2>>"$LOG"; then BTSEED=1
            else lwarn "Bluetooth setting could not be saved for client; client may switch adapter off"; fi;;
  esac
fi

# Automatic Windows build (steam-arm-autobuild.py): client closed only (it rewrites config.vdf on exit); never blocks start.
AB=/usr/local/lib/steam-arm-autobuild.py
if [ -f "$AB" ] && ! client_running; then
  abo=$(timeout 30 python3 "$AB" apply "$S" 2>>"$LOG" </dev/null)
  if [ -n "$abo" ]; then
    printf '%s\n' "$abo" | while IFS= read -r l; do printf '%s %s\n' "$(date '+%F %T')" "$l" >> "$LOG" 2>/dev/null; done
    n=$(printf '%s\n' "$abo" | grep -c '^auto-build: app [0-9]*: Windows build (Proton ARM64) set;')
    [ "$n" -gt 0 ] && lnote "Windows build (Proton ARM64) set for $n game(s) whose Linux build fails under emulation. Steam downloads it in background once client is up. Change: Steam ARM Settings > Graphics > Route per game." "Steam ARM: Windows build set"
  fi
fi

if [ "$CLIENT" = x86 ]; then cd "$S" || exit 1; else cd "$D" || exit 1; fi
# Client exit after applying its own update: status 42 (restart request), or bootstrap log whose last
# start ends in "Update complete, launching" with no client left running. Started again, at most twice.
# Status 0 when the log, from byte $1 on, ends with an applied update and no new start after it.
updated_exit(){
  sz=$(stat -c %s "$BOOTLOG" 2>/dev/null) || return 1
  [ "$sz" -ge "$1" ] || set -- 0
  tail -c +"$(($1 + 1))" "$BOOTLOG" | awk '/\] Startup - /{u=0} /\] Update complete, launching/{u=1} END{exit !u}'
}
# x86 client: own start passes (no ARM update channel, client window on CPU); same first-start and restart rules.
if [ "$CLIENT" = x86 ]; then
  XFLAGS="-steamos3 -cef-disable-gpu -cef-disable-gpu-compositing"
  # Deck interface without account runs SteamOS setup, whose update step needs steamos-update (absent): desktop sign-in first.
  if [ -n "$GPUI" ] && ! grep -qs '"AccountName"' "$S/config/loginusers.vdf"; then
    GPUI=
    lnote "No account signed in yet: x86 client opens desktop sign-in window. Deck interface from next start after sign-in."
  fi
  # one FEX server for emulated client processes and containers (exits 60 s after the last one)
  ( FEXServer -p 60 </dev/null >/dev/null 2>&1 & )
  READY="$S/ubuntu12_64/steamwebhelper"
  # x86 files checked once (marker): a native package leaves files of the same names in the folder
  XOK="$ARMHOME/.config/steam-arm/x86-verified"
  x86_ok(){ mkdir -p "${XOK%/*}" && : > "$XOK" && lwarn "x86 client files checked; later starts skip file check"; }
  if [ ! -f "$READY" ] || [ ! -f "$XOK" ]; then
    first_start_notice </dev/null >/dev/null 2>&1 &
    NOTEWATCH=$!
    start_state "first $(stat -c %s "$BOOTLOG" 2>/dev/null || echo 0)"
    ftry=0
    while :; do
      off=$(stat -c %s "$BOOTLOG" 2>/dev/null || echo 0)
      # x86 bootstrap keeps its client running after the download: stopped once files are in, normal start below
      client_x86 $XFLAGS ${GPUI:+"$GPUI"} "$@" &
      XPID=$!; fdone=0
      while kill -0 "$XPID" 2>/dev/null; do
        if [ -f "$READY" ] && [ "$(boot_phase "$off")" = done ] && client_running; then fdone=1; stop_client || fdone=2; break; fi
        sleep 2
      done
      wait "$XPID"; rc=$?
      [ "$fdone" = 2 ] && exit 1
      [ "$fdone" = 1 ] || [ "$rc" = 0 ] || [ "$rc" = 42 ] \
        || lnote "x86 Steam client stopped during first start (status $rc). Start Steam ARM again; details: $S/logs/stderr.txt and $BOOTLOG"
      if [ "$fdone" = 1 ]; then
        x86_ok
        # webhelper script exists now: its transport flag goes in before the normal start
        xo=$(python3 /usr/local/lib/steam-arm-x86client.py prepare "$S" "$ARMHOME" 2>&1) \
          || lnote "$(printf '%s\n' "$xo" | tail -1 | sed 's/^warning: //')"
        break
      fi
      # client closed by its user (or Stop) with files in place: no new start; checked when its log says so
      if [ -f "$READY" ]; then
        tail -c +"$((off + 1))" "$BOOTLOG" 2>/dev/null | grep -Eq '\] (Verification|Update) complete' && x86_ok
        exit $rc
      fi
      if [ "$rc" = 42 ] || updated_exit "$off"; then
        n=0; while [ $n -lt 5 ] && ! client_running; do sleep 1; n=$((n + 1)); done
        if client_running; then
          while client_running; do sleep 2; done
          [ -f "$READY" ] && exit 0
        elif [ "$ftry" = 0 ]; then
          ftry=1; lwarn "client exited after applying its update during first start; starting it again"
          kill -0 "$NOTEWATCH" 2>/dev/null || { first_start_notice </dev/null >/dev/null 2>&1 & NOTEWATCH=$!; }
          continue
        fi
      fi
      FSM="x86 Steam client did not finish its first start: client files incomplete ($READY missing). Start Steam ARM again to finish download. Details: $BOOTLOG"
      [ -x "$S/ubuntu12_32/steam-runtime/setup.sh" ] || FSM="x86 Steam client did not finish its first start: runtime not unpacked ($S/ubuntu12_32/steam-runtime). Run setup again to fetch it: sudo steam-arm-config (Maintenance > Update / Repair) or sudo $SETUP --keep. Details: $S/logs/stderr.txt"
      lwarn "$FSM" 2>/dev/null; stop "$FSM"
    done
  fi
  start_state start
  tries=0
  while :; do
    off=$(stat -c %s "$BOOTLOG" 2>/dev/null || echo 0)
    client_x86 $XFLAGS ${GPUI:+"$GPUI"} -noverifyfiles -norepairfiles ${NOSHADERS:+"$NOSHADERS"} "$@"
    rc=$?
    [ "$rc" -lt 128 ] || lwarn "x86 client ended by signal $((rc - 128)) (status $rc); details: $S/logs/stderr.txt"
    [ "$tries" -lt 2 ] || exit $rc
    if [ "$rc" != 42 ]; then
      updated_exit "$off" || exit $rc
      n=0; while [ $n -lt 5 ] && ! client_running; do sleep 1; n=$((n + 1)); done
      if client_running; then while client_running; do sleep 2; done; exit 0; fi
    fi
    tries=$((tries + 1))
    lwarn "client exited after applying its update; starting it again"
  done
fi
# Client window process (steamwebhelper) missing host library: warning names library and its package.
WHLOG="$S/logs/steamwebhelper.log"
wh_libhint(){
  l=$(grep -ao 'error while loading shared libraries: [^:]*' "$WHLOG" 2>/dev/null | tail -n 1 | sed 's/.*: //')
  [ -n "$l" ] || return 0
  PATH="$PATH:/usr/sbin:/sbin" ldconfig -p 2>/dev/null | grep -q "[[:space:]]$l (" && return 0
  case $l in
    libibus-1.0.so.5) p=libibus-1.0-5;; libnm.so.0) p=libnm0;; libpipewire-0.3.so.0) p=libpipewire-0.3-0t64;;
    libXtst.so.6) p=libxtst6;; libnss3.so|libnssutil3.so|libsmime3.so) p=libnss3;; libcups.so.2) p=libcups2t64;; *) p=;;
  esac
  if [ -n "$p" ]; then f="Fix: sudo apt install $p, then start Steam ARM again."
  else f="Install distribution package that provides $l, then start Steam ARM again."; fi
  lnote "Steam window stays empty: steamwebhelper cannot load $l. $f" "Steam ARM: library missing"
}
# Log of this start: checked while client starts (90 s).
wh_watch(){
  t0=$(date +%s); n=0
  while [ "$n" -lt 90 ]; do
    sleep 3; n=$((n + 3))
    [ "$(stat -c %Y "$WHLOG" 2>/dev/null || echo 0)" -ge "$t0" ] && grep -aq 'error while loading shared libraries' "$WHLOG" 2>/dev/null \
      && { wh_libhint; return 0; }
  done
}
wh_libhint
wh_watch </dev/null >/dev/null &
# First start must verify files (downloads the rest of the package, SDK dir appears) then exits; start again skipping verification.
# Bootstrap restart after its own update: started once more; files still missing: stop with a message.
# Switch back from x86 client (marker from setup): one start with file check, as a first start.
NVER="$ARMHOME/.config/steam-arm/native-verify"
if [ ! -f "$S/linuxarm64/steamclient.so" ] || [ -f "$NVER" ]; then
  first_start_notice </dev/null >/dev/null 2>&1 &
  NOTEWATCH=$!
  start_state "first $(stat -c %s "$BOOTLOG" 2>/dev/null || echo 0)"
  ftry=0
  while :; do
    off=$(stat -c %s "$BOOTLOG" 2>/dev/null || echo 0)
    ./steam -deckard -steamos3 ${GPUI:+"$GPUI"} "$@"
    rc=$?
    if [ -f "$S/linuxarm64/steamclient.so" ]; then
      # file check after switch done: client closed without own update -> no new start
      if [ -f "$NVER" ]; then rm -f "$NVER"; [ "$rc" = 42 ] || updated_exit "$off" || exit $rc; fi
      break
    fi
    if [ "$rc" = 42 ] || updated_exit "$off"; then
      # a client that starts itself again is left to run, on every pass
      n=0; while [ $n -lt 5 ] && ! client_running; do sleep 1; n=$((n + 1)); done
      if client_running; then
        while client_running; do sleep 2; done
        [ -f "$S/linuxarm64/steamclient.so" ] && exit 0
      elif [ "$ftry" = 0 ]; then
        ftry=1; lwarn "client exited after applying its update during first start; starting it again"
        kill -0 "$NOTEWATCH" 2>/dev/null || { first_start_notice </dev/null >/dev/null 2>&1 & NOTEWATCH=$!; }
        continue
      fi
    fi
    FSM="Steam client did not finish its first start: client files incomplete ($S/linuxarm64/steamclient.so missing). Start Steam ARM again to finish download. Details: $BOOTLOG"
    lwarn "$FSM" 2>/dev/null; stop "$FSM"
  done
  ln -sfn "$S/linuxarm64" "$ARMHOME/.steam/sdkarm64"
fi
start_state start
tries=0
while :; do
  off=$(stat -c %s "$BOOTLOG" 2>/dev/null || echo 0)
  ./steam -deckard -steamos3 ${GPUI:+"$GPUI"} -noverifyfiles -norepairfiles ${NOSHADERS:+"$NOSHADERS"} "$@"
  rc=$?
  [ "$rc" -lt 128 ] || lwarn "client ended by signal $((rc - 128)) (status $rc); start Steam ARM again"
  [ "$tries" -lt 2 ] || exit $rc
  if [ "$rc" != 42 ]; then
    updated_exit "$off" || exit $rc
    # a client that starts itself again is left to run; watchers stay until it exits
    n=0; while [ $n -lt 5 ] && ! client_running; do sleep 1; n=$((n + 1)); done
    if client_running; then while client_running; do sleep 2; done; exit 0; fi
  fi
  tries=$((tries + 1))
  lwarn "client exited after applying its update; starting it again"
done
LAUNCHER
chmod 755 /usr/local/bin/steam-arm
# Power menu calls steamos-session-select; here it just restarts the client in the matching interface (plain env restored first).
cat > /usr/local/bin/steamos-session-select <<'SESSEL'
#!/bin/sh
# steamos-session-select for steam-arm: restart the client in the interface the power menu chose.
case "${1:-}" in
  plasma|plasma-x11|plasma-wayland|plasma-x11-persistent|plasma-wayland-persistent|desktop) m=--desktop;;
  *) m=--bigpicture;;
esac
u=$(id -un); h=$(getent passwd "$(id -u)" | cut -d: -f6)
setsid env -i HOME="$h" USER="$u" LOGNAME="$u" PATH=/usr/local/bin:/usr/bin:/bin \
  DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-$h/.Xauthority}" LANG="${LANG:-C.UTF-8}" \
  XDG_RUNTIME_DIR="/run/user/$(id -u)" XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-}" \
  XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
  /usr/local/bin/steam-arm "$m" </dev/null >/dev/null 2>&1 &
exit 0
SESSEL
chmod 755 /usr/local/bin/steamos-session-select
# Pin Remote Play settings (hardware decode + HEVC off); launcher runs this before each start; --check only reports.
cat > /usr/local/bin/steam-arm-remoteplay <<'RPPY'
#!/usr/bin/env python3
"""Pin the Remote Play client settings the native ARM64 Steam client needs on this system.

The client stores its Remote Play settings as a serialized protobuf (CStreamingClientConfig
from steammessages_remoteplay.proto), hex-encoded under "ClientConfig" in the account's
localconfig.vdf. Two of its fields default to values this system cannot honour:

  enable_hardware_decoding (field 7) defaults to true. The x86-64 streaming client running
  under FEX reaches no host video decoder, so it advertises
  a decoder it does not have and the session never leaves negotiation. Titles with a light
  stream can still come up; heavier ones sit on the launch screen.
  enable_video_hevc (field 13) defaults to false, and is pinned false so the host keeps to
  H.264, which the software decoder handles.

This tool inserts both fields, set to false, when they are absent, and leaves every other
byte of the message untouched. A signed-in account that has not streamed yet has no
"ClientConfig" entry at all (the client writes one after its first session); the tool then
creates the entry, inside the existing "streaming_v2" block or in a new one, so the first
stream already runs with the pinned values. It refuses to run while the client is up,
because the client writes its own copy of the file back on exit. Run without arguments to
apply; --check only reports. Exit status 0 when the settings are in place, 1 when they
could not be applied.
"""
import glob
import os
import pwd
import re
import sys

USAGE = """Usage: steam-arm-remoteplay [--check]

Pins Remote Play settings of native ARM64 client in each localconfig.vdf of client
home: hardware decoding off, HEVC off. Launcher runs it before each client start.

  (none)       apply; refuses while client runs
  --check      report only, change nothing
  -h, --help   print this text and exit

Client home, resolved as launcher does: STEAM_ARM_HOME, else ARMHOME_DIR from
/etc/steam-arm/steam-arm.conf under account home (default .local/share/steam-arm).
Exit status 0 when settings are in place, 1 otherwise."""
CONF_PATH = "/etc/steam-arm/steam-arm.conf"
ARMHOME_DIR = ".local/share/steam-arm"
HOME_VAR = "STEAM_ARM_HOME"

# Field numbers are from the schema embedded in the client; wire type 0 (varint) for bool.
FIELD_HW_DECODE = 7
FIELD_HEVC = 13
KEY_RE = re.compile(r'("ClientConfig"\t\t")([0-9a-f]*)(")')
# streaming_v2 block: closing brace is the first "\t}" line after the opening "\t{".
BLOCK_RE = re.compile(r'\n\t"streaming_v2"\n\t\{\n(?:.*\n)*?\t\}\n')
ROOT_RE = re.compile(r'\A"UserLocalConfigStore"\n\{\n')
ENABLE_RE = re.compile(r'\n\t\t"EnableStreaming"\t\t"')


def read_varint(b, i):
    val, shift = 0, 0
    while True:
        c = b[i]
        val |= (c & 0x7F) << shift
        i += 1
        if not c & 0x80:
            return val, i
        shift += 7


def split_fields(b):
    """Yield (field_number, raw_bytes_of_tag_and_value) for a wire-format message."""
    i = 0
    while i < len(b):
        start = i
        tag, i = read_varint(b, i)
        num, wt = tag >> 3, tag & 7
        if wt == 0:
            _, i = read_varint(b, i)
        elif wt == 1:
            i += 8
        elif wt == 2:
            ln, i = read_varint(b, i)
            i += ln
        elif wt == 5:
            i += 4
        else:
            raise ValueError("unsupported wire type %d at byte %d" % (wt, start))
        yield num, b[start:i]


def pinned(blob):
    """Return the message with both fields present as false, in ascending field order."""
    fields = list(split_fields(blob))
    present = {n for n, _ in fields}
    for num in (FIELD_HW_DECODE, FIELD_HEVC):
        if num not in present:
            fields.append((num, bytes([num << 3, 0])))
    fields.sort(key=lambda f: f[0])
    return b"".join(raw for _, raw in fields)


def with_entry(text):
    """The file text with a "ClientConfig" entry holding only the two pinned fields: added
    to the streaming_v2 block when the block exists, otherwise in a new block right after
    the root object opens. The entry goes first in the block, ahead of "EnableStreaming" "1",
    which is the layout the client itself writes; the EnableStreaming key is added after the
    entry when it is missing. Returns None when the file is not laid out as expected."""
    line = '\t\t"ClientConfig"\t\t"%s"\n' % pinned(b"").hex()
    enable = '\t\t"EnableStreaming"\t\t"1"\n'
    m = BLOCK_RE.search(text)
    if m:
        block = m.group(0)
        head = '\n\t"streaming_v2"\n\t{\n'
        assert block.startswith(head)
        add = line + ("" if ENABLE_RE.search(block) else enable)
        return text[:m.start()] + head + add + block[len(head):] + text[m.end():]
    m = ROOT_RE.match(text)
    if not m:
        return None
    return text[:m.end()] + '\t"streaming_v2"\n\t{\n' + line + enable + "\t}\n" + text[m.end():]


def client_running():
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                with open("/proc/%s/comm" % pid) as fh:
                    if fh.read().strip() == "steam":
                        return True
            except OSError:
                pass
    return False


def write_back(path, text):
    tmp = path + ".steam-arm-tmp"
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(text)
    os.replace(tmp, path)


def client_home():
    """Client home as launcher resolves it: STEAM_ARM_HOME (settings file over environment), else
    ARMHOME_DIR under account home. Account home comes from password database, because
    launcher runs this tool with HOME already set to client home."""
    conf = {}
    try:
        with open(CONF_PATH) as fh:
            for line in fh:
                key, sep, value = line.strip().partition("=")
                if sep and not key.startswith("#"):
                    conf[key.strip()] = value.strip().strip('"').strip("'")
    except OSError:
        pass
    override = conf.get(HOME_VAR) or os.environ.get(HOME_VAR)
    if override:
        return override
    return os.path.join(pwd.getpwuid(os.getuid()).pw_dir, conf.get("ARMHOME_DIR") or ARMHOME_DIR)


def main():
    if "-h" in sys.argv[1:] or "--help" in sys.argv[1:]:
        print(USAGE)
        return 0
    check = "--check" in sys.argv[1:]
    steam = os.path.join(client_home(), ".local/share/Steam")
    files = glob.glob(os.path.join(steam, "userdata/*/config/localconfig.vdf"))
    if not files:
        print("steam-arm-remoteplay: no localconfig.vdf under %s yet; sign in to client once first" % steam)
        return 1
    status = 0
    for path in files:
        text = open(path, encoding="utf-8", errors="surrogateescape").read()
        m = KEY_RE.search(text)
        if not m:
            new_text = with_entry(text)
            if new_text is None:
                print("%s: no ClientConfig entry and no place to add one (unexpected layout)" % path)
                status = 1
                continue
            if check:
                print("%s: not pinned (would create the ClientConfig entry)" % path)
                status = 1
                continue
            if client_running():
                print("steam-arm-remoteplay: the client is running; close it first, it rewrites this file on exit")
                return 1
            # Verify before writing: exactly one entry with the pinned message, and every original line intact.
            found = KEY_RE.findall(new_text)
            assert len(found) == 1 and bytes.fromhex(found[0][1]) == pinned(b"")
            assert all(l in new_text.splitlines() for l in text.splitlines())
            assert len(ENABLE_RE.findall(new_text)) == 1
            write_back(path, new_text)
            print("%s: ClientConfig entry created, pinned (hardware decoding off, HEVC off)" % path)
            continue
        old = bytes.fromhex(m.group(2))
        new = pinned(old)
        if new == old:
            print("%s: already pinned" % path)
            continue
        if check:
            print("%s: not pinned (would insert fields 7 and 13)" % path)
            status = 1
            continue
        if client_running():
            print("steam-arm-remoteplay: the client is running; close it first, it rewrites this file on exit")
            return 1
        # prove the edit before writing it: parsing the result must give the same fields plus two
        assert dict(split_fields(new)).keys() == dict(split_fields(old)).keys() | {FIELD_HW_DECODE, FIELD_HEVC}
        write_back(path, text[:m.start(2)] + new.hex() + text[m.end(2):])
        print("%s: pinned (hardware decoding off, HEVC off)" % path)
    return status


if __name__ == "__main__":
    sys.exit(main())
RPPY
chmod 755 /usr/local/bin/steam-arm-remoteplay
chmod 755 /usr/local/bin/steam-arm
# Launcher pauses the pad-xbox service while it runs; the sudo rule exists only with that component.
if opt pad-xbox; then
# Checked with visudo before it goes live (a bad line would stop every sudo); a dotted name is skipped by sudo meanwhile.
SUDOSKIP="sudo rule for the pad service skipped; the launcher cannot pause pad-xbox while the client runs. If pads act twice in games, stop it by hand: sudo systemctl stop steam-arm-pad-xbox"
if [ -d /etc/sudoers.d ] && command -v visudo >/dev/null 2>&1 && T=$(mktemp /etc/sudoers.d/.steam-arm.XXXXXX); then
  CLEANUP+=("$T")
  printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl start steam-arm-pad-xbox, /usr/bin/systemctl stop steam-arm-pad-xbox\n' "$GAMEUSER" > "$T"
  if visudo -cqf "$T" >/dev/null 2>&1 && chmod 440 "$T" && mv -f "$T" /etc/sudoers.d/steam-arm; then :
  else rm -f "$T" /etc/sudoers.d/steam-arm; warn "sudo did not accept a rule for account '$GAMEUSER': $SUDOSKIP"; fi
else
  warn "sudo is not set up on this system: $SUDOSKIP"
fi
else
rm -f /etc/sudoers.d/steam-arm
fi
# compat tool mapping helper (titles with a Linux build on record but Windows files installed)
cat > /usr/local/lib/steam-arm-compatmap.py <<'PYEOF'
#!/usr/bin/env python3
# Insert, replace or remove a CompatToolMapping entry in Steam's config.vdf (run with Steam closed).
# usage: steam-arm-compatmap.py <config.vdf> <appid> <tool name, e.g. proton_11 | --remove>
import glob, os, re, sys, tempfile
if len(sys.argv) != 4:
    sys.exit("usage: steam-arm-compatmap <appid> <tool> | <appid> --remove")
path, appid, tool = sys.argv[1], sys.argv[2], sys.argv[3]
remove = tool == "--remove"
if not re.fullmatch(r"[0-9]{1,10}", appid):
    sys.exit("steam-arm-compatmap: app id must be a number, got %r" % appid)
if not remove and not re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", tool):
    sys.exit("steam-arm-compatmap: tool name may hold letters, digits, '_', '.' and '-' only, got %r" % tool)


def steam_up():
    # the client writes config.vdf back on exit, so a change made now would be lost
    for p in glob.glob("/proc/[0-9]*"):
        try:
            if os.stat(p).st_uid == os.getuid() and open(p + "/comm").read().strip() == "steam":
                return True
        except OSError:
            pass
    return False


if steam_up():
    sys.exit("steam-arm-compatmap: Steam ARM is running. Close it first (exit from its menu, Stop Steam in the tray, or steam-arm --shutdown), then run this again.")
try:
    raw = open(path, "rb").read()
except OSError as e:
    sys.exit("steam-arm-compatmap: could not read %s (%s). Start Steam ARM once and sign in, then run this again." % (path, e.strerror))
s = raw.decode("utf-8", "surrogateescape")


def body(ind):
    return ('{i}\t"{a}"\n{i}\t{{\n{i}\t\t"name"\t\t"{t}"\n{i}\t\t"config"\t\t""\n'
            '{i}\t\t"priority"\t\t"250"\n{i}\t}}\n').format(i=ind, a=appid, t=tool)


def balanced(t):
    # braces outside quoted strings close in order
    d = 0
    for tok in re.finditer(r'"(?:[^"\\\n]|\\.)*"|[{}]', t):
        d += {"{": 1, "}": -1}.get(tok.group(0), 0)
        if d < 0:
            return False
    return d == 0


m = re.search(r'\n(\t+)"CompatToolMapping"\n\1\{\n', s)
if remove and not m:
    print("CompatToolMapping has no entry for app %s; file left unchanged" % appid); sys.exit(0)
if not m:
    sm = re.search(r'\n(\t+)"Steam"\n\1\{\n', s)
    if not sm:
        sys.exit("steam-arm-compatmap: Software/Valve/Steam block not found in %s; file left unchanged" % path)
    ind = sm.group(1) + "\t"
    ins = '%s"CompatToolMapping"\n%s{\n%s%s}\n' % (ind, ind, body(ind), ind)
    s = s[:sm.end()] + ins + s[sm.end():]; action = "block created"
else:
    ind = m.group(1); start = m.end(); close = s.find("\n" + ind + "}", start - 1)
    if close < 0:
        sys.exit("steam-arm-compatmap: CompatToolMapping block in %s has no closing brace; file left unchanged" % path)
    end = close + 1   # keep the final newline
    block = s[start:end]
    am = re.search(r'^\t+"%s"\n\t+\{\n(?:.*\n)*?\t+\}\n' % re.escape(appid), block, re.M)
    if remove and not am:
        print("CompatToolMapping has no entry for app %s; file left unchanged" % appid); sys.exit(0)
    if remove:
        block = block[:am.start()] + block[am.end():]; action = "removed"
    elif am:
        block = block[:am.start()] + body(ind) + block[am.end():]; action = "replaced"
    else:
        block = body(ind) + block; action = "inserted"
    s = s[:start] + block + s[end:]


def write_atomic(p, data, mode):
    fd, t = tempfile.mkstemp(prefix=".steam-arm-", dir=os.path.dirname(os.path.abspath(p)))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(t, mode)
        os.replace(t, p)
    except BaseException:
        try:
            os.unlink(t)
        except OSError:
            pass
        raise


if not balanced(s):
    sys.exit("steam-arm-compatmap: %s would not keep balanced braces; file left unchanged" % path)
mode = os.stat(path).st_mode & 0o7777
# first original kept; later runs never overwrite it
bak = path + ".bak-steam-arm"
if not os.path.lexists(bak):
    write_atomic(bak, raw, mode)
write_atomic(path, s.encode("utf-8", "surrogateescape"), mode)
print("CompatToolMapping %s for app %s" % (action, appid) + ("" if remove else " -> " + tool))
PYEOF
QU=$(printf '%q' "$GAMEUSER"); QC=$(printf '%q' "$ARMHOME/.local/share/Steam/config/config.vdf")
cat > /usr/local/bin/steam-arm-compatmap <<CM
#!/bin/sh
# usage: steam-arm-compatmap <appid> <tool>   (tool: proton_11-arm64, proton-experimental-arm64, proton_11, proton_experimental, steamlinuxruntime for Linux build; --remove drops the entry; Steam ARM closed)
[ \$# -eq 2 ] || { echo "usage: steam-arm-compatmap <appid> <tool> | <appid> --remove" >&2; exit 2; }
U=$QU; C=$QC
# root runs it as the game account, so config.vdf and its backup stay that account's files
[ "\$(id -u)" = 0 ] && exec runuser -u "\$U" -- python3 /usr/local/lib/steam-arm-compatmap.py "\$C" "\$1" "\$2"
exec python3 /usr/local/lib/steam-arm-compatmap.py "\$C" "\$1" "\$2"
CM
chmod 755 /usr/local/bin/steam-arm-compatmap
# Automatic Windows build rules: launcher sets them before client start, handler checks them at title start.
cat > /usr/local/lib/steam-arm-autobuild.py <<'ABPY'
#!/usr/bin/env python3
"""steam-arm-autobuild: Windows build (Proton ARM64) for titles whose Linux build fails under emulation.

  apply STEAMDIR        sets compatibility tool of matching titles (Steam closed); one log line per decision
  list STEAMDIR         tab-separated: "auto-build on|off", "rule ...", "gate <rule> <reason or ->",
                        "app <appid> auto|pending|suggest|kept <rule> <reason>", "record <appid> <rule> <tool> <date>"
  drop STEAMDIR APPID   forgets record of one title, so rule may apply again

Applies once per title (record file <client folder>/.config/steam-arm/auto-build.conf), only with no tool
chosen for the title, on GPU families and FEX tool versions in rule table; elsewhere: suggestion only.
Launch handler loads this file with runpy and calls launch_verdict()."""
import glob
import os
import re
import subprocess
import sys
import tempfile
import time

CONF = "/etc/steam-arm/steam-arm.conf"
COMPATMAP = "/usr/local/lib/steam-arm-compatmap.py"
# families: GPU families where Windows build was run; fex_max: newest FEX tool YYMM where Linux build failure was seen;
# skip_launch: handler skips a start that launcher has not switched yet (hung title may ignore SIGTERM);
# needs: components Windows build needs (DXVK rejects Mali without vk-spoof); tool: name Steam lists in Compatibility
RULES = [{"id": "source32", "tool": "proton_11-arm64", "families": ("mali-csf-v10",), "fex_max": 2609,
          "skip_launch": True, "needs": ("vk-spoof",), "what": "32-bit Source engine",
          "why": "32-bit Source engine Linux build stops at loading screen under emulation"}]
SCAN_CAP = 10
UNDO = "Undo: steam-arm-config, Graphics > Route per game"


def conf(key):
    try:
        v = [l[len(key) + 1:] for l in open(CONF).read().splitlines() if l.startswith(key + "=")]
    except OSError:
        return ""
    return v[-1].strip().strip("'\"") if v else ""


def auto_on():
    return conf("AUTO_BUILD") != "off"


def client_type():
    return "x86" if conf("CLIENT") == "x86" else "arm64"


def comp_on(name):
    """Component chosen at setup; settings file without COMPONENTS_ON counts all as chosen (launcher rule)."""
    try:
        lines = [l for l in open(CONF).read().splitlines() if l.startswith("COMPONENTS_ON=")]
    except OSError:
        return True
    return not lines or name in conf("COMPONENTS_ON").split(",")


def fex_yymm(steam):
    """First FEX-YYMM in Valve's FEX tool VERSIONS.txt; 0 when unknown."""
    try:
        m = re.search(r"FEX-([0-9]{4})", open(os.path.join(steam, "steamapps/common/FEX-Emu/VERSIONS.txt")).read())
    except OSError:
        return 0
    return int(m.group(1)) if m else 0


def gate(rule, family, yymm, client, on):
    """None when rule may switch title by itself, else reason for suggestion only."""
    if not on:
        return "AUTO_BUILD=off"
    if client != "arm64":
        return "x86 client"
    if family not in rule["families"]:
        return "GPU family %s not tested" % (family or "unknown")
    for c in rule.get("needs", ()):
        if not comp_on(c):
            return "component %s off" % c
    if not yymm:
        return "FEX tool version unknown"
    if yymm > rule["fex_max"]:
        return "FEX tool %d newer than tested" % yymm
    return None


def elf_kind(p):
    """(EI_CLASS, e_machine) of an ELF file, else None."""
    try:
        with open(p, "rb") as f:
            h = f.read(20)
    except OSError:
        return None
    if len(h) < 20 or h[:4] != b"\x7fELF":
        return None
    return h[4], int.from_bytes(h[18:20], "little" if h[5] == 1 else "big")


def script_has_64(d):
    """True when a start script in d names a 64-bit ELF in d (that build runs, not the 32-bit one)."""
    for sh in glob.glob(os.path.join(glob.escape(d), "*.sh")):
        try:
            text = open(sh, "rb").read(1 << 16).decode("utf-8", "replace")
        except OSError:
            continue
        for tok in set(re.findall(r"[\w./+-]+", text)):
            tok = tok.lstrip("/")
            tok = tok[2:] if tok.startswith("./") else tok
            if not tok or ".." in tok.split("/"):
                continue
            k = elf_kind(os.path.join(d, tok))
            if k and k[0] == 2:
                return True
    return False


def source32_dir(d):
    """Installed title: 32-bit i386 hl2_linux, no 64-bit binary named by start script, mod folder with gameinfo.txt."""
    return elf_kind(os.path.join(d, "hl2_linux")) == (1, 3) and not script_has_64(d) \
        and bool(glob.glob(os.path.join(glob.escape(d), "*", "gameinfo.txt")))


def source32_argv(exe, bits, argv):
    """Started title: hl2_linux, 32-bit, with -game."""
    return bool(exe) and os.path.basename(exe) == "hl2_linux" and bits == 32 and "-game" in argv


DIR_MARK = {"source32": source32_dir}
ARGV_MARK = {"source32": source32_argv}


def state_path(steam):
    steam = steam.rstrip("/")
    tail = "/.local/share/Steam"
    home = steam[:-len(tail)] if steam.endswith(tail) else os.path.dirname(steam)
    return os.path.join(home, ".config/steam-arm/auto-build.conf")


def records(path):
    """appid -> [rule, tool, date]."""
    out = {}
    try:
        lines = open(path).read().splitlines()
    except OSError:
        return out
    for l in lines:
        w = l.split("#", 1)[0].split()
        if len(w) >= 3 and w[0].isdigit():
            out[w[0]] = w[1:4]
    return out


def write_records(path, recs):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, t = tempfile.mkstemp(prefix=".auto-build-", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            f.write("# Steam ARM automatic Windows build, one title per line: <appid> <rule> <tool> <date>\n")
            for a in sorted(recs, key=int):
                f.write(" ".join([a] + recs[a]) + "\n")
        os.chmod(t, 0o644)
        os.replace(t, path)
    except BaseException:
        try:
            os.unlink(t)
        except OSError:
            pass
        raise


def mapping(steam):
    """CompatToolMapping of config.vdf: appid -> tool name."""
    try:
        s = open(os.path.join(steam, "config/config.vdf"), encoding="utf-8", errors="surrogateescape").read()
    except OSError:
        return {}
    out = {}
    m = re.search(r'\n(\t+)"CompatToolMapping"\n\1\{\n', s)
    if m:
        e = s.find("\n" + m.group(1) + "}", m.end() - 1)
        for a in re.finditer(r'^\t+"([0-9]{1,10})"\n\t+\{\n((?:.*\n)*?)\t+\}\n', s[m.end():e + 1], re.M):
            n = re.search(r'^\t+"name"\t+"([^"]*)"', a.group(2), re.M)
            if n and n.group(1):
                out[a.group(1)] = n.group(1)
    return out


def libraries(steam):
    libs = [steam]
    try:
        s = open(os.path.join(steam, "steamapps/libraryfolders.vdf"), encoding="utf-8", errors="replace").read()
    except OSError:
        s = ""
    for p in re.findall(r'^\s*"path"\s*"(.*)"\s*$', s, re.M):
        if p not in libs:
            libs.append(p)
    return libs


def manifests(steam):
    """(appid, install folder, Windows build installed) per installed title."""
    seen = set()
    for lib in libraries(steam):
        for acf in sorted(glob.glob(os.path.join(glob.escape(lib), "steamapps", "appmanifest_*.acf"))):
            try:
                s = open(acf, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            kv = {}
            for k, v in re.findall(r'^\s*"(appid|installdir|platform_override_source|LastOwner)"\s*"([^"]*)"', s, re.M):
                kv.setdefault(k, v)
            a = kv.get("appid", "")
            if not a.isdigit() or a in seen or not kv.get("installdir") or "/" in kv["installdir"]:
                continue
            # LastOwner 0: shared content Steam keeps for another title (same folder), not an owned game
            if kv.get("LastOwner") == "0":
                continue
            seen.add(a)
            yield a, os.path.join(lib, "steamapps", "common", kv["installdir"]), \
                kv.get("platform_override_source", "").lower() == "windows"


def family():
    return conf("GPU_FAMILY") or "unknown"


def scan(steam):
    """([(appid, verdict, rule, reason)], gates, partial). Verdicts: auto (set by rule, record matches mapping),
    pending (applies at next apply), suggest, kept (other build chosen, record undone, Windows build installed)."""
    t0 = time.monotonic()
    maps, recs = mapping(steam), records(state_path(steam))
    yymm, client, on, fam = fex_yymm(steam), client_type(), auto_on(), family()
    gates = {r["id"]: gate(r, fam, yymm, client, on) for r in RULES}
    out, partial = [], False
    for appid, d, win in manifests(steam):
        if time.monotonic() - t0 > SCAN_CAP:
            partial = True
            break
        rec = recs.get(appid)
        for r in RULES:
            # title set by rule: Steam swaps in Windows files, so its record decides, not the Linux files
            if not (rec and rec[0] == r["id"]) and not DIR_MARK[r["id"]](d):
                continue
            if rec and maps.get(appid) == rec[1]:
                v = ("auto", r["why"])
            elif appid in maps:
                v = ("kept", "build chosen in Steam or settings menu (%s)" % maps[appid])
            elif win:
                v = ("kept", "Windows build installed")
            elif rec:
                v = ("kept", "automatic choice undone")
            elif gates[r["id"]]:
                v = ("suggest", gates[r["id"]])
            else:
                v = ("pending", r["why"])
            out.append((appid, v[0], r, v[1]))
            break
    return out, gates, partial


def apply(steam):
    res, _, partial = scan(steam)
    path = state_path(steam)
    for appid, v, r, why in res:
        if v == "suggest":
            print("auto-build: app %s: Windows build suggested (%s)" % (appid, why))
        if v != "pending":
            continue
        try:
            p = subprocess.run([sys.executable, COMPATMAP, os.path.join(steam, "config/config.vdf"), appid, r["tool"]],
                               stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
            err = (p.stderr or p.stdout).strip().splitlines()[-1:] if p.returncode else None
        except (OSError, subprocess.TimeoutExpired) as e:
            err = [str(e)]
        if err is not None:
            print("auto-build: app %s: Windows build not set: %s" % (appid, err[0] if err else "steam-arm-compatmap failed"))
            continue
        recs = records(path)
        recs[appid] = [r["id"], r["tool"], time.strftime("%Y-%m-%d")]
        try:
            write_records(path, recs)
        except OSError as e:
            print("auto-build: app %s: record not written (%s); rule may set it again" % (appid, e))
        print("auto-build: app %s: Windows build (Proton ARM64) set; %s. %s" % (appid, why, UNDO))
    if partial:
        print("auto-build: library scan stopped after %d s; other titles checked at next start" % SCAN_CAP)


def show(steam):
    res, gates, partial = scan(steam)
    print("auto-build\t%s" % ("on" if auto_on() else "off"))
    for r in RULES:
        print("rule\t%s\t%s\t%s\t%s\t%s" % (r["id"], r["tool"], ",".join(r["families"]), r["fex_max"], r["what"]))
        print("gate\t%s\t%s" % (r["id"], gates[r["id"]] or "-"))
    for appid, v, r, why in res:
        print("app\t%s\t%s\t%s\t%s" % (appid, v, r["id"], why))
    for appid, rec in sorted(records(state_path(steam)).items(), key=lambda x: int(x[0])):
        print("record\t%s\t%s" % (appid, "\t".join(rec)))
    if partial:
        print("partial\t%d" % SCAN_CAP)


def drop(steam, appid):
    path = state_path(steam)
    recs = records(path)
    if appid not in recs:
        print("auto-build: no record for app %s" % appid)
        return
    del recs[appid]
    write_records(path, recs)
    print("auto-build: record of app %s removed; rule may apply again at next start of Steam ARM" % appid)


def launch_verdict(appid, exe, bits, argv, tool, fam, yymm, steam):
    """(action, text) for a title start, None when no rule matches; action: start, notice (start), skip."""
    for r in RULES:
        if not ARGV_MARK[r["id"]](exe, bits, argv):
            continue
        rid = r["id"]
        if os.environ.get("STEAM_ARM_AUTO_BUILD") == "0":
            return "start", "launch option kept: STEAM_ARM_AUTO_BUILD=0 (%s: Linux build)" % rid
        if tool:
            return "start", "%s: Linux build kept (forced build)" % rid
        if appid in records(state_path(steam)):
            return "start", "%s: Linux build kept (automatic choice undone)" % rid
        g = gate(r, fam, yymm, client_type(), auto_on())
        if g:
            return "start", ("%s: %s; Windows build suggested (%s): steam-arm-config, Graphics > Route per game > windows"
                             % (rid, r["why"], g))
        if r["skip_launch"]:
            return "skip", ("%s: %s; Windows build set at next start of Steam ARM; launch skipped "
                            "(launch option STEAM_ARM_AUTO_BUILD=0 starts Linux build)" % (rid, r["why"]))
        return "notice", ("%s: %s; Windows build set at next start of Steam ARM "
                          "(launch option STEAM_ARM_AUTO_BUILD=0 starts Linux build)" % (rid, r["why"]))
    return None


def main(a):
    if len(a) == 2 and a[0] == "apply":
        apply(a[1])
    elif len(a) == 2 and a[0] == "list":
        show(a[1])
    elif len(a) == 3 and a[0] == "drop" and re.fullmatch(r"[0-9]{1,10}", a[2]):
        drop(a[1], a[2])
    else:
        sys.exit("usage: steam-arm-autobuild.py apply|list STEAMDIR | drop STEAMDIR APPID")


if __name__ == "__main__":
    main(sys.argv[1:])
ABPY
chmod 644 /usr/local/lib/steam-arm-autobuild.py
# Steam Deck category of a title for the settings menu Games screen (read only).
cat > /usr/local/lib/steam-arm-appinfo.py <<'AIPY'
#!/usr/bin/env python3
"""steam-arm-appinfo APPINFO.VDF APPID...: Steam Deck category and runtime of titles from client's appinfo cache.

Prints "<appid>\t<deck>\t<frame>\t<runtime>" per requested title; deck: Verified, Playable, Unsupported or unknown;
runtime: Steam Deck recommended_runtime (native, proton-...) or unknown. Frame: unknown until its key is known.
Read only; any read or format problem gives unknown, exit status 0."""
import os
import struct
import sys
import time

MAGIC = {0x07564428: 40, 0x07564429: 41}
CATEGORY = {1: "Unsupported", 2: "Playable", 3: "Verified"}
# appinfo key of Steam Frame rating; None until confirmed, Frame then stays unknown
FRAME_KEY = None
MAX_SIZE = 512 << 20
MAX_TIME = 2.0
FIXED = 60


class Bad(Exception):
    pass


def cstr(b, i):
    j = b.index(b"\0", i)
    return b[i:j].decode("utf-8", "replace"), j + 1


def kv(b, i, keys, depth=0):
    """Binary KeyValues section at b[i:]: (dict, end); keys = string table (v41) or None (inline keys)."""
    if depth > 32:
        raise Bad("nesting")
    out = {}
    while True:
        if i >= len(b):
            raise Bad("truncated")
        t = b[i]
        i += 1
        if t in (0x08, 0x0B):
            return out, i
        if keys is None:
            k, i = cstr(b, i)
        else:
            (n,) = struct.unpack_from("<i", b, i)
            i += 4
            if not 0 <= n < len(keys):
                raise Bad("key index")
            k = keys[n]
        if t == 0x00:
            out[k], i = kv(b, i, keys, depth + 1)
        elif t == 0x01:
            out[k], i = cstr(b, i)
        elif t in (0x02, 0x04, 0x06):
            (out[k],) = struct.unpack_from("<i", b, i)
            i += 4
        elif t == 0x03:
            (out[k],) = struct.unpack_from("<f", b, i)
            i += 4
        elif t == 0x07:
            (out[k],) = struct.unpack_from("<Q", b, i)
            i += 8
        elif t == 0x0A:
            (out[k],) = struct.unpack_from("<q", b, i)
            i += 8
        else:
            raise Bad("type %d" % t)


def read_exact(f, n):
    b = f.read(n)
    if len(b) != n:
        raise Bad("truncated")
    return b


def lookup(path, want):
    """appid -> parsed appinfo section, for requested appids found in file."""
    t0 = time.monotonic()
    found = {}
    with open(path, "rb") as f:
        if os.fstat(f.fileno()).st_size > MAX_SIZE:
            raise Bad("size")
        magic, _uni = struct.unpack("<II", read_exact(f, 8))
        ver = MAGIC.get(magic)
        if ver is None:
            raise Bad("magic")
        keys = None
        if ver == 41:
            (off,) = struct.unpack("<q", read_exact(f, 8))
            pos = f.tell()
            f.seek(off)
            (count,) = struct.unpack("<I", read_exact(f, 4))
            raw = f.read()
            keys, i = [], 0
            for _ in range(count):
                s, i = cstr(raw, i)
                keys.append(s)
            f.seek(pos)
        while len(found) < len(want):
            if time.monotonic() - t0 > MAX_TIME:
                raise Bad("time")
            (appid,) = struct.unpack("<I", read_exact(f, 4))
            if appid == 0:
                break
            (size,) = struct.unpack("<I", read_exact(f, 4))
            if str(appid) not in want:
                f.seek(size, 1)
                continue
            body = read_exact(f, size)
            try:
                found[str(appid)], _ = kv(body, FIXED, keys)
            except (Bad, struct.error, ValueError, IndexError):
                found[str(appid)] = {}
    return found


def hint(sec):
    root = sec.get("appinfo") if isinstance(sec.get("appinfo"), dict) else sec
    common = root.get("common") if isinstance(root.get("common"), dict) else {}
    deck = common.get("steam_deck_compatibility")
    cat, rt, frame = "unknown", "unknown", "unknown"
    if isinstance(deck, dict):
        c = deck.get("category")
        cat = CATEGORY.get(c, "unknown") if isinstance(c, int) else "unknown"
        cfg = deck.get("configuration")
        r = cfg.get("recommended_runtime") if isinstance(cfg, dict) else None
        if isinstance(r, str) and r and r.replace("-", "").replace("_", "").replace(".", "").isalnum():
            rt = r
    if FRAME_KEY and isinstance(common.get(FRAME_KEY), dict):
        c = common[FRAME_KEY].get("category")
        frame = CATEGORY.get(c, "unknown") if isinstance(c, int) else "unknown"
    return cat, frame, rt


def main(a):
    if len(a) < 2:
        print("usage: steam-arm-appinfo APPINFO.VDF APPID...", file=sys.stderr)
        return
    want = [x for x in a[1:] if x.isdigit()]
    try:
        found = lookup(a[0], set(want))
    except (OSError, Bad, struct.error, ValueError, IndexError, MemoryError):
        found = {}
    for appid in want:
        print("%s\t%s\t%s\t%s" % ((appid,) + hint(found.get(appid, {}))))


if __name__ == "__main__":
    main(sys.argv[1:])
AIPY
chmod 644 /usr/local/lib/steam-arm-appinfo.py
# Optional GE-Proton ARM64 builds: menu action only, nothing runs at setup or launch.
cat > /usr/local/lib/steam-arm-geproton.py <<'GEPY'
#!/usr/bin/env python3
"""steam-arm-geproton: optional GE-Proton ARM64 builds in the client's compatibilitytools.d.

usage: steam-arm-geproton.py list [--sizes] STEAMDIR | check STEAMDIR
       | install [TAG] [--file FILE.tar.gz] [--move] STEAMDIR | remove TAG [--to TAG|default] STEAMDIR
       | remove-all STEAMDIR
Runs as game account. Touches only folders holding marker .steam-arm-ge; other copies are listed, never changed.
Exit: 0 done or current, 1 refused, 2 network or check failure.
"""
import fcntl
import hashlib
import json
import os
import posixpath
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time

API = "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=30"
DL = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/"
CONF = "/etc/steam-arm/steam-arm.conf"
COMPATMAP = "/usr/local/lib/steam-arm-compatmap.py"
MARK = ".steam-arm-ge"
LOCK = ".steam-arm-ge.lock"
TMPP = ".steam-arm-ge-"
SLR_APPID = "4185400"
TAG_RE = re.compile(r"GE-Proton[0-9]{1,3}-[0-9]{1,4}")
MAX_MEMBERS = 50000
MAX_BYTES = 6 << 30
SPACE_FACTOR = 5
# unpacked size per compressed byte (measured on 11-7: 2.16 GB / 0.65 GB)
UNPACK_RATIO = 3.35
USAGE = ("usage: steam-arm-geproton.py list [--sizes]|check|install [TAG] [--file FILE] [--move]"
         "|remove TAG [--to TAG|default]|remove-all STEAMDIR")


class Refused(Exception):
    """Status 1: refused, message for person."""


class Failed(Exception):
    """Status 2: network or check failure."""


def say(msg):
    print(msg, flush=True)


def gb(n):
    return "%.1f GB" % (n / 1e9) if n >= 1e9 else "%d MB" % round(n / 1e6)


def n_games(n):
    return "1 game" if n == 1 else "%d games" % n


def vkey(tag):
    m = re.match(r"GE-Proton([0-9]+)-([0-9]+)", tag)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def conf_get(key):
    try:
        for ln in open(CONF, encoding="utf-8", errors="replace"):
            if ln.startswith(key + "="):
                return ln.split("=", 1)[1].strip().strip("\"'")
    except OSError:
        pass
    return ""


def page_size():
    return os.sysconf("SC_PAGE_SIZE")


def refusal():
    if conf_get("CLIENT") == "x86":
        return ("GE-Proton ARM64 runs with native ARM64 client only. This system runs x86 client through "
                "emulation; Windows games use x86 Proton there.")
    ps = page_size()
    if ps != 4096:
        return "GE-Proton ARM64 needs 4K memory pages (this system: %dK)." % (ps // 1024)
    return None


def steam_up():
    # client writes config.vdf and tool list while running
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            if os.stat("/proc/" + p).st_uid == os.getuid() and open("/proc/%s/comm" % p).read().strip() == "steam":
                return True
        except OSError:
            pass
    return False


# --- release pick ---------------------------------------------------------------------------------------------
def pick(releases, tag=None):
    """Newest non-draft, non-prerelease release with <tag>-aarch64.tar.gz and .sha512sum from GE repo."""
    if tag is not None and not TAG_RE.fullmatch(tag):
        return None
    for r in releases if isinstance(releases, list) else []:
        if not isinstance(r, dict) or r.get("draft") or r.get("prerelease"):
            continue
        t = r.get("tag_name")
        if not isinstance(t, str) or not TAG_RE.fullmatch(t) or (tag and t != tag):
            continue
        assets = {a.get("name"): a for a in r.get("assets") or [] if isinstance(a, dict)}
        tar, summ = assets.get(t + "-aarch64.tar.gz"), assets.get(t + "-aarch64.sha512sum")
        if not tar or not summ:
            continue
        pre = DL + t + "/"
        if not all(isinstance(a.get("browser_download_url"), str) and a["browser_download_url"] == pre + a["name"]
                   for a in (tar, summ)):
            continue
        size = tar.get("size")
        if not isinstance(size, int) or size <= 0:
            continue
        d = tar.get("digest")
        sha256 = d[7:] if isinstance(d, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", d) else None
        return {"tag": t, "top": t + "-aarch64", "url": tar["browser_download_url"],
                "sum_url": summ["browser_download_url"], "size": size, "sha256": sha256,
                "date": str(r.get("published_at") or "")[:10]}
    return None


def read_sum(text, asset):
    """sha512 from .sha512sum text: exactly one line '<128 hex>  [*]<asset>'."""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) != 1:
        return None
    m = re.fullmatch(r"([0-9a-f]{128})  \*?(.+)", lines[0].rstrip("\r"))
    return m.group(1) if m and m.group(2) == asset else None


def curl():
    c = shutil.which("curl")
    if not c:
        raise Refused("curl is not installed; install it (apt install curl), then try again.")
    return c


def http_get(url, dest):
    """Small download; returns HTTP status text ('000' offline) and curl status."""
    r = subprocess.run([curl(), "-sSL", "--max-time", "20", "-o", dest, "-w", "%{http_code}",
                        "-H", "Accept: application/vnd.github+json", url],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    return (r.stdout or "").strip() or "000", r.returncode


def api_releases(tmp):
    f = os.path.join(tmp, "releases.json")
    code, rc = http_get(API, f)
    msg = {"403": "GitHub refused the request (request limit for this address). Try again in an hour.",
           "429": "GitHub refused the request (request limit for this address). Try again in an hour.",
           "404": "GE-Proton release list not found on GitHub.",
           "000": "GitHub could not be reached (offline, or address blocked)."}
    if code != "200":
        raise Failed(msg.get(code, "GitHub answered with HTTP %s." % code))
    if rc:
        raise Failed("GitHub release list download interrupted (curl status %d); try again." % rc)
    try:
        return json.load(open(f, encoding="utf-8"))
    except (OSError, ValueError):
        raise Failed("GitHub answer not understood.")


def fetch_sum(rel, tmp):
    f = os.path.join(tmp, rel["top"] + ".sha512sum")
    code, rc = http_get(rel["sum_url"], f)
    if code != "200":
        raise Failed("Checksum file could not be downloaded (HTTP %s)." % code)
    if rc:
        raise Failed("Checksum file download interrupted (curl status %d); try again." % rc)
    s = read_sum(open(f, encoding="utf-8", errors="replace").read(), rel["top"] + ".tar.gz")
    if not s:
        raise Failed("Checksum file not understood; nothing installed.")
    return s


def download(url, dest):
    say("Downloading %s" % url.rsplit("/", 1)[-1])
    r = subprocess.run([curl(), "-fL", "--progress-bar", "--max-time", "3600", "-o", dest, url])
    if r.returncode:
        raise Failed("Download failed (curl status %d); nothing installed." % r.returncode)


def hashes(path):
    h5, h2 = hashlib.sha512(), hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h5.update(b)
            h2.update(b)
    return h5.hexdigest(), h2.hexdigest()


# --- unpack ---------------------------------------------------------------------------------------------------
def _inside(path, root):
    return path == root or path.startswith(root + "/")


def unpack(tar, stage, top):
    """Stream-unpack tar into stage; every member under top, no special files, links stay inside top."""
    n = size = 0
    links = []
    rstage = os.path.realpath(stage)
    with tarfile.open(tar, mode="r|gz") as t:
        for m in t:
            n += 1
            if n > MAX_MEMBERS:
                raise Failed("Archive holds more than %d members; nothing installed." % MAX_MEMBERS)
            name = m.name
            if len(name) > 4096 or name.startswith("/") or ".." in name.split("/"):
                raise Failed("Archive member %r leaves tool folder; nothing installed." % name[:200])
            name = posixpath.normpath(name)
            if not _inside(name, top):
                raise Failed("Archive member %r is outside %s; nothing installed." % (name[:200], top))
            dest = os.path.join(stage, name)
            parent = os.path.dirname(dest)
            # nothing written through a link
            if os.path.realpath(parent) != os.path.join(rstage, os.path.dirname(name)).rstrip("/"):
                raise Failed("Archive member %r is written through a link; nothing installed." % name[:200])
            if m.isdir():
                if os.path.lexists(dest) and (os.path.islink(dest) or not os.path.isdir(dest)):
                    raise Failed("Archive member %r repeats a name; nothing installed." % name[:200])
                os.makedirs(dest, 0o755, exist_ok=True)
                os.chmod(dest, 0o755)
            elif m.isreg():
                size += m.size
                if size > MAX_BYTES:
                    raise Failed("Archive unpacks to more than %s; nothing installed." % gb(MAX_BYTES))
                os.makedirs(parent, 0o755, exist_ok=True)
                fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, "wb") as out:
                    shutil.copyfileobj(t.extractfile(m), out, 1 << 20)
                # no setuid/setgid/sticky, no group or other write
                os.chmod(dest, m.mode & 0o755)
                os.utime(dest, (m.mtime, m.mtime))
            elif m.issym():
                tg = m.linkname
                if not tg or tg.startswith("/") or not _inside(posixpath.normpath(posixpath.join(posixpath.dirname(name), tg)), top):
                    raise Failed("Archive link %r points outside tool folder; nothing installed." % name[:200])
                os.makedirs(parent, 0o755, exist_ok=True)
                os.symlink(tg, dest)
                links.append(dest)
            else:
                raise Failed("Archive member %r is a hard link or special file; nothing installed." % name[:200])
            if n % 1000 == 0:
                say("Unpacking: %d files" % n)
    rtop = os.path.join(rstage, top)
    for ln in links:
        if not _inside(os.path.realpath(ln), rtop):
            raise Failed("Archive link %r resolves outside tool folder; nothing installed." % ln[len(stage) + 1:][:200])
    if not os.path.isdir(os.path.join(stage, top)) or os.path.islink(os.path.join(stage, top)):
        raise Failed("Archive has no %s folder; nothing installed." % top)
    say("Unpacking: %d files, done" % n)
    return n


def vdf_value(text, key):
    m = re.search(r'"%s"\s+"([^"]*)"' % re.escape(key), text)
    return m.group(1) if m else None


def verify_tool(d, top):
    """compatibilitytool.vdf names top with install_path '.', toolmanifest runs /proton, proton present."""
    try:
        c = open(os.path.join(d, "compatibilitytool.vdf"), encoding="utf-8", errors="replace").read()
        tm = open(os.path.join(d, "toolmanifest.vdf"), encoding="utf-8", errors="replace").read()
    except OSError:
        raise Failed("Tool files compatibilitytool.vdf / toolmanifest.vdf missing; nothing installed.")
    m = re.search(r'"compat_tools"\s*\{\s*"([^"]+)"', c)
    if not m or m.group(1) != top or vdf_value(c, "install_path") != ".":
        raise Failed("compatibilitytool.vdf does not name %s; nothing installed." % top)
    if "/proton" not in (vdf_value(tm, "commandline") or "") or not os.path.isfile(os.path.join(d, "proton")):
        raise Failed("Tool has no proton script; nothing installed.")
    return vdf_value(tm, "require_tool_appid") or ""


def tree_bytes(d):
    total = 0
    for root, dirs, files in os.walk(d):
        for f in dirs + files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return total


# --- state ----------------------------------------------------------------------------------------------------
def marker(d):
    """Marker keys of folder d, or None when folder is not ours (no marker, or a link)."""
    if os.path.islink(d) or not os.path.isdir(d):
        return None
    try:
        txt = open(os.path.join(d, MARK), encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    k = {}
    for ln in txt.splitlines():
        if "=" in ln:
            a, b = ln.split("=", 1)
            k[a.strip()] = b.strip()
    return k


def write_marker(d, keys):
    with open(os.path.join(d, MARK), "w", encoding="utf-8") as f:
        for a in ("TAG", "SHA512", "SOURCE", "URL", "DATE", "BYTES"):
            f.write("%s=%s\n" % (a, keys.get(a, "")))


def mapped(sdir):
    """CompatToolMapping of config.vdf: {appid: tool}."""
    try:
        s = open(os.path.join(sdir, "config", "config.vdf"), "rb").read().decode("utf-8", "surrogateescape")
    except OSError:
        return {}
    out = {}
    m = re.search(r'\n(\t+)"CompatToolMapping"\n\1\{\n', s)
    if m:
        e = s.find("\n" + m.group(1) + "}", m.end() - 1)
        for a in re.finditer(r'^\t+"([0-9]{1,10})"\n\t+\{\n((?:.*\n)*?)\t+\}\n', s[m.end():e + 1], re.M):
            n = re.search(r'^\t+"name"\t+"([^"]*)"', a.group(2), re.M)
            if n and re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", n.group(1)):
                out[a.group(1)] = n.group(1)
    return out


def remap(sdir, appid, tool):
    r = subprocess.run([sys.executable, COMPATMAP, os.path.join(sdir, "config", "config.vdf"), appid, tool],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode:
        raise Refused((r.stdout or "").strip() or "steam-arm-compatmap failed")


def tools(sdir, sizes=False):
    """GE builds in compatibilitytools.d, newest first: dicts tag, dir, marked, bytes, games."""
    cdir = os.path.join(sdir, "compatibilitytools.d")
    maps = mapped(sdir)
    out = []
    try:
        names = os.listdir(cdir)
    except OSError:
        names = []
    for n in names:
        d = os.path.join(cdir, n)
        if not n.startswith("GE-Proton") or not os.path.isfile(os.path.join(d, "compatibilitytool.vdf")):
            continue
        k = marker(d)
        b = (k or {}).get("BYTES", "")
        if not b.isdigit():
            b = str(tree_bytes(d)) if sizes or k is not None else "?"
        tag = (k or {}).get("TAG") or (n[:-8] if n.endswith("-aarch64") else n)
        out.append({"tag": tag, "dir": n, "marked": k is not None, "bytes": b,
                    "games": sorted(a for a, t in maps.items() if t == n)})
    out.sort(key=lambda x: (vkey(x["dir"]), x["dir"]), reverse=True)
    return out


def libraries(sdir):
    libs = [sdir]
    try:
        s = open(os.path.join(sdir, "steamapps", "libraryfolders.vdf"), encoding="utf-8", errors="replace").read()
        libs += [p.replace("\\\\", "\\") for p in re.findall(r'"path"\s+"([^"]+)"', s)]
    except OSError:
        pass
    return libs


def slr4(sdir):
    return any(os.path.isfile(os.path.join(lb, "steamapps", "appmanifest_%s.acf" % SLR_APPID)) for lb in libraries(sdir))


# --- actions --------------------------------------------------------------------------------------------------
class Lock:
    """Non-blocking lock on compatibilitytools.d; stale temp folders go under it."""

    def __init__(self, cdir):
        self.cdir = cdir

    def __enter__(self):
        os.makedirs(self.cdir, 0o755, exist_ok=True)
        self.path = os.path.join(self.cdir, LOCK)
        self.f = open(self.path, "a")
        try:
            fcntl.flock(self.f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # file unlinked by a run that just ended: lock taken on a stale file
            a, b = os.fstat(self.f.fileno()), os.stat(self.path)
            if (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):
                raise OSError
        except OSError:
            self.f.close()
            raise Refused("Another GE-Proton action runs; try again when it ends.")
        for n in os.listdir(self.cdir):
            p = os.path.join(self.cdir, n)
            if n.startswith(TMPP) and os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p, ignore_errors=True)
        return self

    def __exit__(self, *a):
        # unlinked while still held, so no lock file stays behind
        try:
            os.unlink(self.path)
        except OSError:
            pass
        self.f.close()


def on_signal(sig, _frame):
    raise SystemExit(128 + sig)


def place(stage_top, target, sha):
    """Move unpacked tool into place; old marked copy replaced, unmarked copy refused."""
    if os.path.lexists(target):
        k = marker(target)
        if k is None:
            raise Refused("Copy of %s not installed by Steam ARM is present; left unchanged." % os.path.basename(target))
        old = tempfile.mkdtemp(prefix=TMPP + "old-", dir=os.path.dirname(target))
        os.rename(target, os.path.join(old, "t"))
        os.rename(stage_top, target)
        shutil.rmtree(old, ignore_errors=True)
    else:
        os.rename(stage_top, target)


def move_games(sdir, frm, to):
    """Mappings naming folder frm -> folder to (or removed when to is None); returns count."""
    n = 0
    for appid, t in sorted(mapped(sdir).items()):
        if t == frm:
            remap(sdir, appid, to or "--remove")
            n += 1
    return n


def cmd_install(sdir, tag=None, file=None, move=False):
    why = refusal()
    if why:
        raise Refused(why)
    if not os.path.isdir(sdir):
        raise Refused("Start Steam ARM and sign in once, then try again.")
    cdir = os.path.join(sdir, "compatibilitytools.d")
    if file:
        base = os.path.basename(file)
        m = re.fullmatch(r"(GE-Proton[0-9]{1,3}-[0-9]{1,4})-aarch64\.tar\.gz", base)
        if not m or (tag and tag != m.group(1)):
            raise Refused("File name must be GE-Proton<version>-aarch64.tar.gz, as published.")
        if not os.path.isfile(file):
            raise Refused("%s is not a readable file." % file)
        sumf = file[:-len(".tar.gz")] + ".sha512sum"
        if not os.path.isfile(sumf):
            raise Refused("Checksum file %s not found beside it. Download both files from GE-Proton's release page."
                          % os.path.basename(sumf))
        rel = {"tag": m.group(1), "top": m.group(1) + "-aarch64", "url": "file", "size": os.path.getsize(file),
               "sha256": None}
        want = read_sum(open(sumf, encoding="utf-8", errors="replace").read(), base)
        if not want:
            raise Failed("Checksum file not understood; nothing installed.")
    with Lock(cdir):
        stage = tempfile.mkdtemp(prefix=TMPP, dir=cdir)
        try:
            if not file:
                rel = pick(api_releases(stage), tag)
                if not rel:
                    raise Failed("No GE-Proton release with ARM64 build found%s." % (" for " + tag if tag else ""))
                want = fetch_sum(rel, stage)
            target = os.path.join(cdir, rel["top"])
            k = marker(target) if os.path.lexists(target) else {}
            if k is None:
                raise Refused("Copy of %s not installed by Steam ARM is present; left unchanged." % rel["top"])
            if k.get("SHA512") == want:
                say("%s is installed and current." % rel["tag"])
                return 0
            need = rel["size"] * SPACE_FACTOR
            free = shutil.disk_usage(cdir).free
            if free < need:
                raise Refused("Needs about %s free in %s; %s free." % (gb(need), sdir, gb(free)))
            tar = file
            if not file:
                tar = os.path.join(stage, rel["top"] + ".tar.gz")
                download(rel["url"], tar)
            say("Checking sha512...")
            h5, h2 = hashes(tar)
            if h5 != want:
                raise Failed("sha512 does not match published sum; nothing installed.")
            if rel.get("sha256") and h2 != rel["sha256"]:
                raise Failed("sha256 does not match GitHub's record of file; nothing installed.")
            unpack(tar, stage, rel["top"])
            st = os.path.join(stage, rel["top"])
            req = verify_tool(st, rel["top"])
            write_marker(st, {"TAG": rel["tag"], "SHA512": want, "SOURCE": "file" if file else "github",
                              "URL": rel["url"], "DATE": time.strftime("%Y-%m-%d"), "BYTES": str(tree_bytes(st))})
            place(st, target, want)
        finally:
            shutil.rmtree(stage, ignore_errors=True)
        say("%s installed in %s." % (rel["tag"], target))
        if req == SLR_APPID and not slr4(sdir):
            say("Steam Linux Runtime 4.0 (Arm64): absent; Steam downloads it at first start of game set to this build.")
        if move:
            older = [t for t in tools(sdir) if t["marked"] and t["dir"] != rel["top"] and vkey(t["dir"]) < vkey(rel["top"])]
            if older and steam_up():
                say("Steam ARM is running: games not moved. Close Steam ARM, then use Remove version to move games.")
            for t in [] if steam_up() else older:
                n = move_games(sdir, t["dir"], rel["top"])
                shutil.rmtree(os.path.join(cdir, t["dir"]))
                say("%s removed; %s moved to %s." % (t["tag"], n_games(n), rel["tag"]))
    return 0


def find(sdir, tag, marked_only=True):
    for t in tools(sdir):
        if tag in (t["tag"], t["dir"]) and (t["marked"] or not marked_only):
            return t
    return None


def cmd_remove(sdir, tag, to="default"):
    cdir = os.path.join(sdir, "compatibilitytools.d")
    t = find(sdir, tag)
    if not t:
        raise Refused("%s is not installed by this menu; copies installed by hand are left alone." % tag)
    dest = None
    if to != "default":
        d = find(sdir, to, marked_only=False)
        if not d or d["dir"] == t["dir"]:
            raise Refused("Target %s is not another installed GE-Proton build." % to)
        dest = d["dir"]
    if steam_up():
        raise Refused("Steam ARM is running; close it first (it holds tool list while it runs).")
    with Lock(cdir):
        n = move_games(sdir, t["dir"], dest)
        shutil.rmtree(os.path.join(cdir, t["dir"]))
    say("%s removed; %s %s." % (t["tag"], n_games(n), ("moved to " + d["tag"]) if dest else
                                     "back to Steam's choice (Linux build where game has one, else default Proton)"))
    return 0


def cmd_remove_all(sdir):
    cdir = os.path.join(sdir, "compatibilitytools.d")
    if not os.path.isdir(cdir):
        return 0
    gone, bad = [], 0
    with Lock(cdir):
        for t in tools(sdir):
            if not t["marked"]:
                continue
            try:
                move_games(sdir, t["dir"], None)
                shutil.rmtree(os.path.join(cdir, t["dir"]))
                gone.append(t["tag"])
            except (OSError, Refused) as e:
                bad = 1
                print("steam-arm-geproton: %s: %s" % (t["tag"], e), file=sys.stderr)
    print(", ".join(gone))
    return bad


def cmd_list(sdir, sizes=False):
    for t in tools(sdir, sizes):
        print("\t".join((t["tag"], t["dir"], "1" if t["marked"] else "0", t["bytes"], str(len(t["games"])))))
    print("slr4\t" + ("installed" if slr4(sdir) else "absent"))
    return 0


def cmd_check(sdir):
    cdir = os.path.join(sdir, "compatibilitytools.d")
    tmp = tempfile.mkdtemp(prefix="steam-arm-ge-check-")
    try:
        rel = pick(api_releases(tmp))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if not rel:
        raise Failed("No GE-Proton release with ARM64 build found.")
    k = marker(os.path.join(cdir, rel["top"])) or {}
    try:
        free = shutil.disk_usage(cdir if os.path.isdir(cdir) else sdir).free
    except OSError:
        free = 0
    print("\t".join(("release", rel["tag"], rel["date"] or "-", str(rel["size"]), str(int(rel["size"] * UNPACK_RATIO)),
                     str(free), "current" if k.get("TAG") == rel["tag"] else "new")))
    return 0


def main(argv):
    if os.getuid() == 0:
        raise Refused("run as game account")
    if len(argv) < 2:
        raise Refused(USAGE)
    act, sdir, rest = argv[0], argv[-1], argv[1:-1]
    if act == "list" and rest in ([], ["--sizes"]):
        return cmd_list(sdir, bool(rest))
    if act == "check" and not rest:
        return cmd_check(sdir)
    if act == "remove-all" and not rest:
        return cmd_remove_all(sdir)
    if act == "remove" and (len(rest) == 1 or (len(rest) == 3 and rest[1] == "--to")):
        return cmd_remove(sdir, rest[0], rest[2] if len(rest) == 3 else "default")
    if act == "install":
        tag = file = None
        move = False
        i = 0
        while i < len(rest):
            a = rest[i]
            if a == "--move":
                move = True
            elif a == "--file" and i + 1 < len(rest) and not file:
                file = rest[i + 1]
                i += 1
            elif TAG_RE.fullmatch(a) and not tag:
                tag = a
            else:
                raise Refused("install: unknown argument %r" % a)
            i += 1
        return cmd_install(sdir, tag, file, move)
    raise Refused(USAGE)


def run(argv):
    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)
    try:
        return main(argv)
    except Refused as e:
        print("steam-arm-geproton: %s" % e, file=sys.stderr)
        return 1
    except Failed as e:
        print("steam-arm-geproton: %s" % e, file=sys.stderr)
        return 2
    except OSError as e:
        print("steam-arm-geproton: %s" % e, file=sys.stderr)
        return 2
    except (tarfile.TarError, EOFError) as e:
        print("steam-arm-geproton: archive not readable (%s); nothing installed." % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
GEPY
chmod 644 /usr/local/lib/steam-arm-geproton.py


# Generated menu icons (chartreuse=Big Picture, bone=desktop) distinguish this client from x86 Steam; drawn from the client's steam_tray.ico, so re-run once it exists after first start.
steam_arm_icon(){
  cat > /usr/local/bin/steam-arm-icon <<'ICONPY'
#!/usr/bin/env python3
"""steam-arm-icon STEAMDIR HICOLORDIR: write steam-arm.png and steam-arm-desktop.png.

Steam's round icon redrawn on a dark, grainy green disc with a few small squares of vivid
colour, generated from fixed seeds so every install draws the same icons. The logo tells the
entries apart: chartreuse for Big Picture (steam-arm), bone for desktop mode
(steam-arm-desktop). The logo shape comes from the client's own steam_tray.ico, where it is
white with graded transparency over a blue disc; whiteness picks the logo, and the disc is
made opaque. Before the client's first start there is no logo source: disc alone is drawn and
HICOLORDIR/.steam-arm-placeholder marks it, so the launcher redraws it once the client is in.
Nothing is bundled with the package."""
import math, os, subprocess, sys
from PIL import Image
steam, dest = sys.argv[1], sys.argv[2]
src = None
for c in (os.path.join(steam, "public/steam_tray.ico"),
          "/opt/fex-rootfs/Ubuntu_24_04/usr/share/icons/hicolor/256x256/apps/steam.png"):
    if os.path.isfile(c):
        src = c; break
if src:
    im = Image.open(src)
    if src.endswith(".ico"):
        im.size = max(im.info.get("sizes", {im.size}))
    im = im.convert("RGBA").resize((256, 256), Image.LANCZOS)
else:
    im = Image.new("RGBA", (256, 256))
p = im.load(); W, H = im.size; CX = CY = 127.5; R = 126.5

def h(x, y, seed):
    v = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0

def vnoise(x, y, cell, seed):
    gx, gy = x / cell, y / cell; x0, y0 = int(gx), int(gy); fx, fy = gx - x0, gy - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = h(x0, y0, seed), h(x0 + 1, y0, seed); c, d = h(x0, y0 + 1, seed), h(x0 + 1, y0 + 1, seed)
    top = a + (b - a) * fx
    return top + ((c + (d - c) * fx) - top) * fy

DARK, MID, LIGHT = (14, 24, 12), (30, 48, 24), (58, 82, 40)
POPS = ((0, 229, 255), (234, 255, 0), (255, 106, 0), (180, 92, 255))

def disc(x, y, seed):
    g = 0.55 * vnoise(x, y, 40, seed) + 0.30 * vnoise(x, y, 11, seed + 1) + 0.15 * h(x, y, seed + 2)
    col = [DARK[i] + (MID[i] - DARK[i]) * min(1, g * 1.4) for i in range(3)]
    s = h(x // 3, y // 3, seed + 3)
    if s > 0.93:
        col = [LIGHT[i] * (0.7 + 0.3 * h(x, y, 9)) for i in range(3)]
    elif s < 0.05:
        col = [c * 0.45 for c in col]
    cx, cy = x // 9, y // 9
    if h(cx, cy, seed + 4) > 0.975 and 1 <= x % 9 <= 6 and 1 <= y % 9 <= 6:
        col = list(POPS[int(h(cx, cy, seed + 5) * len(POPS)) % len(POPS)])
    return col

def draw(logo, seed):
    out = Image.new("RGBA", im.size); o = out.load()
    for y in range(H):
        for x in range(W):
            r_, g_, b_, a = p[x, y]
            t = min(1.0, max(0.0, (min(r_, g_, b_) - 120) / 135)); t = t * t * (3 - 2 * t)
            if math.hypot(x + .5 - CX, y + .5 - CY) < R - 1.5:
                a = 255
            bk = disc(x, y, seed)
            o[x, y] = tuple(int(bk[i] + (logo[i] - bk[i]) * t) for i in range(3)) + (a,)
    return out

for name, img in (("steam-arm", draw((156, 200, 101), 11)), ("steam-arm-desktop", draw((196, 186, 160), 23))):
    for sz in (16, 32, 48, 64, 128, 256):
        d = os.path.join(dest, "%dx%d" % (sz, sz), "apps"); os.makedirs(d, exist_ok=True)
        img.resize((sz, sz), Image.LANCZOS).save(os.path.join(d, name + ".png"))
mark = os.path.join(dest, ".steam-arm-placeholder")
if src:
    if os.path.lexists(mark):
        os.remove(mark)
else:
    open(mark, "w").close()
if os.path.isfile(os.path.join(dest, "index.theme")):
    subprocess.run(["gtk-update-icon-cache", "-q", "-f", "-t", dest], stderr=subprocess.DEVNULL)
ICONPY
  chmod 755 /usr/local/bin/steam-arm-icon
  rm -f /usr/share/icons/hicolor/*/apps/steam-arm.png /usr/share/icons/hicolor/*/apps/steam-arm-desktop.png
  if ! icon_system; then
    say "     menu icons could not be made; launcher makes them at first start"
  elif [ -e "$ICON_MARK" ]; then
    say "     menu icons: plain disc until first start, then redrawn from client's own icon"
  else
    say "     menu icons made from client's own icon"
  fi
}
# Game user draws the icons into a root-made folder; root locks it, then copies plain files only.
ICON_MARK=/usr/local/share/steam-arm/icon-placeholder
icon_system(){
  local t sz n f ok=1
  t=$(mktemp -d /var/tmp/steam-arm-icon.XXXXXX) || return 1
  CLEANUP+=("$t")
  chown "$GAMEUSER" "$t" || return 1
  (cd / && as_user /usr/local/bin/steam-arm-icon "$S" "$t") || return 1
  chown root:root "$t" && chmod 700 "$t" || return 1
  [ -z "$(find "$t" -mindepth 1 \( -type l -o \( -type f -links +1 \) \) -print -quit)" ] || return 1
  chown -R root:root "$t" || return 1
  for sz in 16 32 48 64 128 256; do for n in steam-arm steam-arm-desktop; do
    f="$t/${sz}x$sz/apps/$n.png"
    if [ -L "$t/${sz}x$sz" ] || [ -L "$t/${sz}x$sz/apps" ] || [ -L "$f" ] || [ ! -f "$f" ] || [ "$(stat -c %h "$f")" != 1 ]; then ok=0; continue; fi
    install -D -m 644 -o root -g root "$f" "/usr/share/icons/hicolor/${sz}x$sz/apps/$n.png" || ok=0
  done; done
  [ $ok = 1 ] || rm -f /usr/share/icons/hicolor/*/apps/steam-arm.png /usr/share/icons/hicolor/*/apps/steam-arm-desktop.png
  rm -f "$ICON_MARK"
  if [ $ok = 1 ] && [ -f "$t/.steam-arm-placeholder" ]; then mkdir -p "${ICON_MARK%/*}" && : > "$ICON_MARK"; fi
  [ -f /usr/share/icons/hicolor/index.theme ] && gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor 2>/dev/null
  [ $ok = 1 ]
}

# Same two entries serve the app menu and the desktop icons; one function each.
bp_entry(){ cat <<'DESK'
[Desktop Entry]
Type=Application
Name=Steam ARM
GenericName=Steam client, native ARM64
Comment=Native ARM64 Steam client; x86 games run through the client's emulation tool
Exec=/usr/local/bin/steam-arm %U
Icon=steam-arm
Terminal=false
Categories=Game;
MimeType=x-scheme-handler/steam;
Keywords=steam;arm;native;big picture;
StartupNotify=false
Actions=desktop;bigpicture;

[Desktop Action desktop]
Name=Open in desktop mode
Exec=/usr/local/bin/steam-arm --desktop

[Desktop Action bigpicture]
Name=Open in Big Picture
Exec=/usr/local/bin/steam-arm --bigpicture
DESK
}
dm_entry(){ cat <<'DMDESK'
[Desktop Entry]
Type=Application
Name=Steam ARM (Desktop mode)
GenericName=Steam client, native ARM64, desktop interface
Comment=Opens native ARM64 Steam client in its desktop interface; restarts it there if it runs in Big Picture
Exec=/usr/local/bin/steam-arm --desktop
Icon=steam-arm-desktop
Terminal=false
Categories=Game;
Keywords=steam;arm;desktop;desktop mode;sign in;login;
StartupNotify=false
DMDESK
}
# desktop icon: entry written to the game user's Desktop, executable, owned by that user
desk_icon(){ if ! { as_user mkdir -p "$UHOME/Desktop" && "$1" | user_write "$2" 755; }; then warn "desktop icon $2 could not be written"; fi; }
BP_ICON="$UHOME/Desktop/Steam ARM.desktop"; DM_ICON="$UHOME/Desktop/Steam ARM (Desktop mode).desktop"

if want_icons; then
  steam_arm_icon
else
  rm -f /usr/share/icons/hicolor/*/apps/steam-arm.png /usr/share/icons/hicolor/*/apps/steam-arm-desktop.png \
        /usr/local/bin/steam-arm-icon "$ICON_MARK"
  for n in steam-arm steam-arm-desktop; do as_user rm -f "$UHOME"/.local/share/icons/hicolor/*/apps/"$n".png; done
fi

# "Steam ARM" menu entry, and the window frame rule for the desktop interface
if opt desktop; then
  bp_entry > /usr/share/applications/steam-arm.desktop
  # Client's own drawn frame doesn't move on drag; a KWin rule gives normal windows the WM frame instead (Big Picture, fullscreen, is unaffected).
  RID=steam-arm-frame
  kw() { login_sh "kwriteconfig$KV --file kwinrulesrc --group $1 --key $2 '$3'" 2>/dev/null; }
  if KV=$(kcfg_ver); then
    login_sh '[ -e "$HOME/.config/kwinrulesrc" ]' 2>/dev/null || { mkdir -p "${KWIN_MADE%/*}" && printf '%s\n' "$GAMEUSER" > "$KWIN_MADE"; }
    kw "$RID" Description "Steam ARM: window manager frame"
    kw "$RID" wmclass steam; kw "$RID" wmclassmatch 1; kw "$RID" wmclasscomplete false
    kw "$RID" types 1; kw "$RID" noborder false; kw "$RID" noborderrule 2
    cur=$(login_sh "kreadconfig$KV --file kwinrulesrc --group General --key rules" 2>/dev/null)
    case ",$cur," in *",$RID,"*) new="$cur";; *) new="${cur:+$cur,}$RID";; esac
    kw General rules "$new"; kw General count "$(printf '%s' "$new" | awk -F, '{print NF}')"
    kwin_reload
  elif command -v kwin_x11 >/dev/null 2>&1 || command -v kwin_wayland >/dev/null 2>&1 || command -v plasmashell >/dev/null 2>&1; then
    say "     KDE window rule skipped: kwriteconfig6 / kwriteconfig5 not found (needed on KDE Plasma only)"
  fi
else
  rm -f /usr/share/applications/steam-arm.desktop
  kwin_rule_remove
fi

# Desktop mode entry restarts a Big-Picture-running client into the desktop interface.
if opt desktop-mode; then dm_entry > /usr/share/applications/steam-arm-desktop.desktop
else rm -f /usr/share/applications/steam-arm-desktop.desktop; fi
# steam:// links (MimeType in menu entry) reach launcher once handler cache is rebuilt
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications 2>/dev/null

# desktop icons, each on its own
if opt icon-bigpicture; then desk_icon bp_entry "$BP_ICON"; else as_user rm -f "$BP_ICON"; fi
if opt icon-desktop; then desk_icon dm_entry "$DM_ICON"; else as_user rm -f "$DM_ICON"; fi

# panel tray icon
if opt tray; then
# Deck build has no tray item; this helper supplies one (open, stop, settings, log), autostarted per session.
cat > /usr/local/bin/steam-arm-tray <<'TRAYPY'
#!/usr/bin/env python3
"""Panel tray icon (StatusNotifier) for the native ARM64 Steam client.

Valve's Deck build of Steam (the aarch64 client used here) registers
no status-notifier item of its own, so the panel's tray never shows it. This
script supplies that item: a Steam icon, a menu to open the client in either
interface, stop it, open settings or the launcher log, and a title that reports
whether it is running.
"""

import fcntl
import os
import shutil
import signal
import subprocess
import sys
import threading
import time

try:
    import gi

    gi.require_version("AyatanaAppIndicator3", "0.1")
    gi.require_version("Gtk", "3.0")
    from gi.repository import AyatanaAppIndicator3, Gio, GLib, Gtk
except (ImportError, ValueError):
    print("steam-arm-tray: install gir1.2-ayatanaappindicator3-0.1", file=sys.stderr)
    sys.exit(1)

STEAM_ARM_BIN = "/usr/local/bin/steam-arm"
CONFIG_BIN = "/usr/local/bin/steam-arm-config"
CONFIG_DESKTOP = "steam-arm-config.desktop"
CONF_PATH = "/etc/steam-arm/steam-arm.conf"
ARMHOME_DIR = ".local/share/steam-arm"
# Terminal fallbacks when the desktop does not launch the settings entry: (program, option before command).
TERMINALS = (
    ("x-terminal-emulator", "-e"), ("konsole", "-e"), ("gnome-terminal", "--"), ("xfce4-terminal", "-x"),
    ("lxterminal", "-e"), ("mate-terminal", "-x"), ("foot", None), ("alacritty", "-e"), ("xterm", "-e"),
)


def load_conf(path):
    """Parse simple KEY=VALUE shell-style lines, ignoring comments and blanks."""
    values = {}
    try:
        with open(path, "r") as handle:
            lines = handle.readlines()
    except OSError:
        return values
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def resolve_armhome():
    """Mirror the launcher's ARMHOME resolution so the tray finds the same install.

    The config file lets a site override where the ARM Steam install lives
    without editing this script or the launcher; the environment variable
    lets a single session override it without touching the config file.
    """
    armhome_dir = ARMHOME_DIR
    armhome_override = None
    conf = load_conf(CONF_PATH)
    if "ARMHOME_DIR" in conf:
        armhome_dir = conf["ARMHOME_DIR"]
    if "STEAM_ARM_HOME" in conf:
        armhome_override = conf["STEAM_ARM_HOME"]
    if os.environ.get("STEAM_ARM_HOME"):
        armhome_override = os.environ["STEAM_ARM_HOME"]
    return armhome_override or os.path.join(os.path.expanduser("~"), armhome_dir)


def proc_uid(pid):
    """Real uid from /proc/<pid>/status (the folder owner is root for non-dumpable processes)."""
    with open("/proc/%s/status" % pid, "r") as handle:
        for line in handle:
            if line.startswith("Uid:"):
                return int(line.split()[1])
    return -1


def comm_matches(pid, name):
    """True for a process of this account with that name (other accounts' Steam is not ours)."""
    try:
        if proc_uid(pid) != os.getuid():
            return False
        with open("/proc/%s/comm" % pid, "r") as handle:
            return handle.read().strip() == name
    except OSError:
        return False


def pids_by_comm(name):
    """Read /proc/*/comm directly instead of shelling out to pgrep."""
    return [
        int(entry) for entry in os.listdir("/proc")
        if entry.isdigit() and comm_matches(entry, name)
    ]


def steam_running():
    return len(pids_by_comm("steam")) > 0


def game_running():
    """A title of this account runs (Steam's "reaper SteamLaunch" wrapper), as the settings menu checks."""
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if proc_uid(entry) != os.getuid():
                continue
            with open("/proc/%s/cmdline" % entry, "rb") as handle:
                if b"reaper SteamLaunch" in handle.read().replace(b"\0", b" "):
                    return True
        except (OSError, ValueError):
            continue
    return False


def start_locked(armhome):
    """Launcher's client start lock held (first start or start in progress); read from /proc/locks, never taken."""
    runtime_dir = "/run/user/%d" % os.getuid()
    if os.path.isdir(runtime_dir) and os.access(runtime_dir, os.W_OK):
        path = os.path.join(runtime_dir, "steam-arm-start.lock")
    else:
        path = os.path.join(armhome, ".steam-arm-start.lock")
    try:
        st = os.stat(path)
        with open("/proc/locks") as handle:
            locks = handle.read().split("\n")
    except OSError:
        return False
    key = "%02x:%02x:%d" % (os.major(st.st_dev), os.minor(st.st_dev), st.st_ino)
    for line in locks:
        f = line.replace("->", "").split()
        if len(f) > 5 and f[1] == "FLOCK" and f[5] == key:
            return True
    return False


def spawn(argv):
    """Detached child, reaped by a waiting thread when it ends (no zombie); False when the program cannot start."""
    try:
        p = subprocess.Popen(
            argv,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return False
    threading.Thread(target=p.wait, daemon=True).start()
    return True


def launch(args):
    spawn([STEAM_ARM_BIN] + args)


def in_terminal(argv):
    """Command in the first terminal found; False when none starts."""
    for program, option in TERMINALS:
        path = shutil.which(program)
        if path and spawn([path] + ([option] if option else []) + argv):
            return True
    return False


def open_settings():
    """Settings menu in a terminal: desktop entry through GIO (its terminal choice), else first terminal found."""
    try:
        info = Gio.DesktopAppInfo.new(CONFIG_DESKTOP)
        if info is not None and info.launch([], None):
            return
    except GLib.Error:
        pass
    in_terminal([CONFIG_BIN])


def log_has_text(path):
    try:
        return os.path.isfile(path) and os.path.getsize(path) > 0
    except OSError:
        return False


def open_log(path):
    """Log as text in less at its end (newest lines); desktop default program without less or a terminal."""
    if not log_has_text(path):
        return
    pager = shutil.which("less")
    if not (pager and in_terminal([pager, "+G", path])):
        spawn(["xdg-open", path])


def acquire_single_instance_lock():
    """Hold an flock for the process lifetime so a second tray exits quietly
    instead of showing a duplicate icon."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    lock_file = open(os.path.join(runtime_dir, "steam-arm-tray.lock"), "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(0)
    return lock_file  # kept alive on the caller's stack for the lock's duration


def contrast_icon(src, runtime_dir):
    """Copy of the white mono icon with a dark outline (readable on light panels) in runtime_dir; None to keep mono."""
    if not runtime_dir or not os.path.isdir(runtime_dir):
        return None
    try:
        gi.require_version("GdkPixbuf", "2.0")
        from gi.repository import GdkPixbuf

        pb = GdkPixbuf.Pixbuf.new_from_file(src).add_alpha(False, 0, 0, 0)
        w, h, rs = pb.get_width(), pb.get_height(), pb.get_rowstride()
        px = bytearray(pb.get_pixels())
        solid = [[px[y * rs + x * 4 + 3] >= 128 for x in range(w)] for y in range(h)]
        for y in range(h):
            for x in range(w):
                if solid[y][x]:
                    continue
                if any(solid[j][i] for j in range(max(y - 1, 0), min(y + 2, h)) for i in range(max(x - 1, 0), min(x + 2, w))):
                    px[y * rs + x * 4:y * rs + x * 4 + 4] = b"\x20\x20\x20\xff"
        out = GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(bytes(px)), GdkPixbuf.Colorspace.RGB, True, 8, w, h, rs)
        d = os.path.join(runtime_dir, "steam-arm-tray")
        os.makedirs(d, mode=0o700, exist_ok=True)
        p = os.path.join(d, "steam_tray_hc.png")
        out.savev(p, "png", [], [])
        return p
    except Exception:
        return None


class SteamTray:
    def __init__(self):
        armhome = resolve_armhome()
        self.armhome = armhome
        # Indicator API wants an icon name in a theme dir, not a path; point the theme dir at the client's icon folder.
        self.icon_dir = os.path.join(armhome, ".local/share/Steam/public")
        self.icon_set = False
        self.log_path = os.path.join(armhome, "steam-arm.log")
        self.stopping = False
        self.indicator = AyatanaAppIndicator3.Indicator.new(
            "steam-arm", "input-gaming-symbolic",
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)

        self.menu = Gtk.Menu()
        client_item = Gtk.MenuItem(label="")
        client_item.set_sensitive(False)
        self.client_item = client_item
        self.x86 = None
        self.update_client()
        self.open_item = Gtk.MenuItem(label="Open Steam")
        self.open_item.connect("activate", lambda *_: launch([]))
        self.bigpicture_item = Gtk.MenuItem(label="Open in Big Picture")
        self.bigpicture_item.connect("activate", lambda *_: launch(["--bigpicture"]))
        self.desktop_item = Gtk.MenuItem(label="Open in desktop mode")
        self.desktop_item.connect("activate", lambda *_: launch(["--desktop"]))
        # Steam's own tray pages, forwarded to running client (steam-arm --open)
        self.page_items = []
        for label, url in (("Store", "steam://store"), ("Library", "steam://open/games"),
                           ("Friends", "steam://open/friends"), ("Downloads", "steam://open/downloads"),
                           ("Screenshots", "steam://open/screenshots"), ("Steam Settings", "steam://open/settings")):
            item = Gtk.MenuItem(label=label)
            item.connect("activate", lambda _w, u=url: launch(["--open", u]))
            self.page_items.append(item)
        self.stop_item = Gtk.MenuItem(label="Stop Steam")
        self.stop_item.connect("activate", self.on_stop)
        settings_item = Gtk.MenuItem(label="Steam ARM Settings")
        settings_item.connect("activate", lambda *_: open_settings())
        self.log_item = Gtk.MenuItem(label="View log")
        self.log_item.connect("activate", lambda *_: open_log(self.log_path))
        quit_item = Gtk.MenuItem(label="Quit tray")
        quit_item.connect("activate", lambda *_: Gtk.main_quit())
        for item in (client_item, Gtk.SeparatorMenuItem(), self.open_item, self.bigpicture_item, self.desktop_item, Gtk.SeparatorMenuItem(),
                     *self.page_items, Gtk.SeparatorMenuItem(), self.stop_item, Gtk.SeparatorMenuItem(), settings_item, self.log_item,
                     Gtk.SeparatorMenuItem(), quit_item):
            self.menu.append(item)
        self.menu.show_all()
        self.indicator.set_menu(self.menu)

        self.update_state()
        GLib.timeout_add_seconds(3, self.on_poll)

    def on_stop(self, *_):
        # Launcher's graceful stop (client -shutdown, SIGTERM after 20 s); never SIGKILL.
        self.stopping = time.monotonic()
        self.stop_item.set_sensitive(False)
        launch(["--shutdown"])

    def on_poll(self):
        self.update_state()
        return True

    def update_icon(self):
        # Client unpacks public/ at its first start; switch from the generic icon once its file exists.
        src = os.path.join(self.icon_dir, "steam_tray_mono.png")
        if self.icon_set or not os.path.isfile(src):
            return
        hc = contrast_icon(src, os.environ.get("XDG_RUNTIME_DIR"))
        if hc:
            self.indicator.set_icon_theme_path(os.path.dirname(hc))
            self.indicator.set_icon_full("steam_tray_hc", "Steam")
        else:
            self.indicator.set_icon_theme_path(self.icon_dir)
            self.indicator.set_icon_full("steam_tray_mono", "Steam")
        self.icon_set = True

    def update_client(self):
        # Maintenance > Client type can switch the client while the tray runs
        x86 = load_conf(CONF_PATH).get("CLIENT") == "x86"
        if x86 == self.x86:
            return
        self.x86 = x86
        self.title = "Steam (x86 client)" if x86 else "Steam"
        self.indicator.set_title(self.title)
        self.client_item.set_label("Client: x86 through emulation" if x86 else "Client: native ARM64")

    def update_state(self):
        self.update_client()
        running = steam_running()
        # launcher gives up 50 s after asking; Stop is offered again after that
        if not running or (self.stopping and time.monotonic() - self.stopping > 60):
            self.stopping = False
        self.update_icon()
        # first start or start in progress: launcher would only show its progress notice
        starting = start_locked(self.armhome)
        self.open_item.set_sensitive(not running and not starting)
        # a running title is closed from the game first (killed fullscreen titles can leave the display mode changed)
        game = running and game_running()
        # the launcher restarts a running client
        self.bigpicture_item.set_sensitive(not self.stopping and not game and not starting)
        self.desktop_item.set_sensitive(not self.stopping and not game and not starting)
        for item in self.page_items:
            item.set_sensitive(running and not self.stopping and not starting)
        self.stop_item.set_sensitive(running and not self.stopping and not game)
        # empty file: desktop opens it as inode/x-empty (often a blank browser page)
        self.log_item.set_sensitive(log_has_text(self.log_path))
        self.indicator.set_title("Steam (starting)" if starting else
                                 self.title[:-1] + ", running)" if running and self.x86 else
                                 "Steam (running)" if running else self.title)


def main():
    lock_file = acquire_single_instance_lock()  # noqa: F841
    SteamTray()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: Gtk.main_quit())
    Gtk.main()


if __name__ == "__main__":
    main()
TRAYPY
chmod 755 /usr/local/bin/steam-arm-tray
as_user mkdir -p "$UHOME/.config/autostart"
user_write "$UHOME/.config/autostart/steam-arm-tray.desktop" <<'TRAYDESK' || warn "tray autostart entry could not be written"
[Desktop Entry]
Type=Application
Name=Steam tray
Comment=Steam icon in the system tray for the ARM64 client
Exec=/usr/local/bin/steam-arm-tray
Icon=input-gaming-symbolic
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
TRAYDESK
if tray_restart; then
  say "     tray helper installed; running tray restarted (new version)"
else
  say "     tray helper installed; it appears in the panel at next login and whenever Steam ARM starts"
fi
else
  rm -f /usr/local/bin/steam-arm-tray; as_user rm -f "$UHOME/.config/autostart/steam-arm-tray.desktop"
  pkill -TERM -u "$GAMEUSER" -f /usr/local/bin/steam-arm-tray 2>/dev/null || true
fi

# kde-input-prompt (opt-in): helper always installed; the launcher applies or reverses it inside the desktop session.
cat > /usr/local/lib/steam-arm-kde-input <<'KDEIN'
#!/bin/sh
# steam-arm-kde-input on|off|status: KDE Plasma (Wayland) pre-authorisation of input emulation by X11 programs,
# which have no app id; "on" saves the value it replaces, "off" restores it. Runs as the desktop account.
T=kde-authorized; ID=remote-desktop
M="$HOME/.config/steam-arm/kde-input-prompt"
ps_call(){ busctl --user --json=short call org.freedesktop.impl.portal.PermissionStore \
  /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore "$@"; }
reach(){ command -v busctl >/dev/null 2>&1 && busctl --user introspect org.freedesktop.impl.portal.PermissionStore \
  /org/freedesktop/impl/portal/PermissionStore >/dev/null 2>&1; }
# value for programs without app id: yes, no or none
cur(){ ps_call Lookup ss "$T" "$ID" 2>/dev/null | python3 -c 'import json, sys
try:
    d = json.load(sys.stdin)["data"][0]
except Exception:
    d = {}
v = d.get("") if isinstance(d, dict) else None
print(v[0] if v else "none")'; }
case "${1:-}" in
  on)
    [ -f "$M" ] && exit 0
    reach || { echo "steam-arm-kde-input: KDE permission store not reachable (no desktop session)" >&2; exit 75; }
    c=$(cur)
    mkdir -p "${M%/*}" && printf '%s\n' "$c" > "$M" || exit 1
    if ! ps_call SetPermission sbssas "$T" true "$ID" "" 1 yes >/dev/null; then
      rm -f "$M"; echo "steam-arm-kde-input: could not set permission" >&2; exit 1
    fi
    echo "KDE input prompt off: X11 programs may send input without asking (value before: $c)";;
  off)
    [ -f "$M" ] || exit 0
    reach || { echo "steam-arm-kde-input: KDE permission store not reachable (no desktop session)" >&2; exit 75; }
    c=$(head -1 "$M")
    case "$c" in
      none) ps_call DeletePermission sss "$T" "$ID" "" >/dev/null 2>&1 || [ "$(cur)" = none ];;
      yes)  true;;
      *)    ps_call SetPermission sbssas "$T" true "$ID" "" 1 "$c" >/dev/null;;
    esac || { echo "steam-arm-kde-input: could not restore permission" >&2; exit 1; }
    rm -f "$M"; echo "KDE input prompt restored (value: $c)";;
  status)
    if reach; then echo "permission for X11 programs: $(cur)"; else echo "permission store not reachable"; fi
    if [ -f "$M" ]; then echo "set by Steam ARM (value before: $(head -1 "$M"))"; else echo "not set by Steam ARM"; fi;;
  *) echo "usage: steam-arm-kde-input on|off|status" >&2; exit 2;;
esac
KDEIN
chmod 755 /usr/local/lib/steam-arm-kde-input
if opt kde-input-prompt; then
  kde_input on; rc=$?
  case "$rc" in 0) ;; 75) say "     kde-input-prompt: applies at next start of Steam ARM in KDE Plasma session";;
    *) warn "kde-input-prompt could not be applied now; Steam ARM tries again at its next start";; esac
elif [ -f "$UHOME/$KDE_MARK" ]; then
  kde_input off; rc=$?
  case "$rc" in 0) ;; 75) say "     kde-input-prompt off: KDE prompt comes back at next start of Steam ARM";;
    *) warn "kde-input-prompt could not be reversed now; Steam ARM tries again at its next start";; esac
fi

# Settings menu, and a copy of this installer for it (Update / Repair, Components, Uninstall).
if ! { T=$(mktemp /usr/local/bin/.steam-arm-config.XXXXXX) && CLEANUP+=("$T") && menu_app > "$T" && chmod 755 "$T" \
         && mv -f "$T" /usr/local/bin/steam-arm-config; }; then
  warn "settings menu /usr/local/bin/steam-arm-config could not be written"
fi
SELF=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)
SHARE=/usr/local/share/steam-arm/steam-arm-install.sh
if [ -f "$SELF" ] && [ "$SELF" != "$SHARE" ]; then
  # new file renamed into place: a copy that is running right now keeps reading its old one
  if ! { mkdir -p /usr/local/share/steam-arm && T=$(mktemp "$SHARE.XXXXXX") && CLEANUP+=("$T") && cp "$SELF" "$T" \
         && chmod 755 "$T" && mv -f "$T" "$SHARE"; }; then
    warn "installer copy $SHARE could not be written; the settings menu then needs this script beside it"
  fi
fi
# Settings menu in application menu; desktop opens it in a terminal (sudo asks there).
cat > /usr/share/applications/steam-arm-config.desktop <<'CFGDESK' || warn "settings menu entry could not be written"
[Desktop Entry]
Type=Application
Name=Steam ARM Settings
GenericName=Settings for Steam ARM
Comment=Components, graphics routes, game profiles, controllers, maintenance; opens in a terminal
Exec=/usr/local/bin/steam-arm-config
TryExec=/usr/local/bin/steam-arm-config
Icon=steam-arm
Terminal=true
Categories=Game;
Keywords=steam;arm;settings;config;setup;
StartupNotify=false
CFGDESK
want_icons || sed -i 's/^Icon=steam-arm$/Icon=preferences-system/' /usr/share/applications/steam-arm-config.desktop 2>/dev/null
say "     settings menu: steam-arm-config (menu entry \"Steam ARM Settings\")"

# ---------------------------------------------------------------------------
say "11/11  done"
if [ "$CLIENT" = x86 ]; then
  SUM_GAMES="x86 Linux titles run through emulation; Windows titles through x86 Proton the client
                 downloads. Client: Valve's x86 client through emulation ($(x86_why);
                 settings menu: Maintenance > Client type)"
  SUM_FIRST="downloads the client files and restarts itself; first sign-in in desktop window,
                 Deck interface from next start after sign-in."
else
  SUM_GAMES="x86 Linux titles run through the client's emulation tool; Windows titles through
                 the ARM64 Proton build the client downloads. Titles whose Linux build fails under
                 emulation get Windows build at start (settings menu: Graphics > Automatic Windows build)"
  SUM_FIRST="downloads the client package and restarts itself; sign in from Big Picture,
                 or from \"Steam ARM (Desktop mode)\"."
fi
cat <<EOM
  Client home:   $ARMHOME   (library under .local/share/Steam/steamapps)
  Games kept:    installed games, sign-in and settings were not touched
  Launch:        steam-arm   as $GAMEUSER, or the "Steam ARM" menu entry
  First start:   $SUM_FIRST
  Games:         $SUM_GAMES
  Optional:     $(for c in $COMPONENTS; do opt "$c" && printf ' %s' "$c" || printf ' [no %s]' "$c"; done)
EOM
# Command line hints only outside the settings menu (it sets STEAM_ARM_FROM_MENU=1).
[ "${STEAM_ARM_FROM_MENU:-0}" = 1 ] || cat <<EOM
  (re-run with --select or --skip to change; see --help)
  Settings:      steam-arm-config   (menu: components, graphics, games, controllers, uninstall)
  Uninstall:     sudo bash steam-arm-install.sh --remove   (package: sudo steam-arm-setup --remove);
                 installed games are kept unless asked
EOM
# Desktop account (graphical session, else sudo caller) other than GAMEUSER finds no client in its home.
DESK_USER=""
if command -v loginctl >/dev/null 2>&1; then
  while read -r ds_s _; do
    ds_n=""; ds_t=""; ds_c=""
    while IFS='=' read -r ds_k ds_v; do
      case "$ds_k" in Name) ds_n=$ds_v;; Type) ds_t=$ds_v;; Class) ds_c=$ds_v;; esac
    done < <(loginctl show-session "$ds_s" -p Name -p Type -p Class 2>/dev/null </dev/null)
    case "$ds_t" in x11|wayland|mir) [ "$ds_c" = user ] && [ -n "$ds_n" ] && { DESK_USER=$ds_n; break; };; esac
  done < <(loginctl list-sessions --no-legend 2>/dev/null </dev/null)
fi
[ -n "$DESK_USER" ] || DESK_USER=${SUDO_USER:-}
if [ -n "$DESK_USER" ] && [ "$DESK_USER" != root ] && [ "$DESK_USER" != "$GAMEUSER" ]; then
  warn "Play as $GAMEUSER: steam-arm uses that account's home."
fi
if [ -n "$NEWGROUPS" ]; then
  warn "before first start: log out and log back in (or restart), so '$GAMEUSER' gets groups:$NEWGROUPS"
fi
