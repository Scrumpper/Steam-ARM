#!/bin/bash
# Distro matrix (internal test tooling, never shipped): installer run as root in rootless chroots of container images;
# whole tree before setup and after --remove --purge compared (keep reasons from check-removal.py). PASS/FAIL/SKIP lines.
#
# distro-matrix.sh [--backend sim|qemu] [--cached-only] [--fast] [--keep] [ROW ...]
# distro-matrix.sh --list | --prepare ROW... | --update-lock | --clean
#   sim   rootfs of the host architecture; non-arm64 host: arm64 package side through apt simulation (real arm64 indexes),
#         dpkg/uname answer arm64; package install simulated, FEX and client downloads replaced by stand-ins
#   qemu  arm64 rootfs, real package install (qemu-aarch64 binfmt with F flag; native on arm64 hosts)
#   --cached-only  rows without a cached image SKIP (no download); --fast  gate and preflight rows only
# Hardware facts are stand-ins: arm64 cpuinfo, device-tree model and compatible (Pi rows), v3d render node (Pi rows); no GPU elsewhere. Images pinned in distro-matrix.lock,
# cached in SARM_MATRIX_CACHE (default ~/.cache/sarm-matrix). SARM_INST picks the installer.
set -u
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)
LOCK=$HERE/distro-matrix.lock TREE=$HERE/distro-matrix-tree.py FETCH=$HERE/fetch-image.py REMOVAL=$HERE/check-removal.py
CACHE=${SARM_MATRIX_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/sarm-matrix}
PREP_VER=7
GAMEUSER=gamer
# row|kind|image (amd64,arm64 when they differ)|label; kind: install, preflight (stops at host packages), pagesize
# (16K page kernel: setup switches the Pi kernel and stops), gate, x86
ROWS="ubuntu-26.04|install|ubuntu:26.04|Ubuntu 26.04 LTS
ubuntu-25.10|install|ubuntu:25.10|Ubuntu 25.10
ubuntu-24.04|preflight|ubuntu:24.04|Ubuntu 24.04 LTS
debian-13|install|debian:trixie-slim|Debian 13 trixie
debian-14|install|debian:forky-slim|Debian 14 forky (testing)
debian-12|preflight|debian:bookworm-slim|Debian 12 bookworm
raspios|install|debian:trixie-slim|Raspberry Pi OS trixie (Debian 13 + Pi archive, Pi 5 model)
raspios-16k|pagesize|debian:trixie-slim|Raspberry Pi OS trixie, Pi 5 on its 16K page kernel
raspios-pi4|install|debian:trixie-slim|Raspberry Pi OS trixie, Pi 4 model (Cortex-A72 without LSE, VideoCore VI, x86 client)
fedora-44|gate|fedora:44|Fedora 44
arch|gate|archlinux:latest,menci/archlinuxarm:latest|Arch Linux (ARM on arm64)
opensuse|gate|opensuse/tumbleweed:latest|openSUSE Tumbleweed
x86_64|x86|debian:trixie-slim|Debian 13 on x86_64 (no arm64 stand-ins)"

BACKEND=sim CACHED=0 FAST=0 KEEP=0 ACTION=run SEL=()
while [ $# -gt 0 ]; do
  case $1 in
    --backend) BACKEND=${2:-}; shift;;
    --backend=*) BACKEND=${1#*=};;
    --cached-only) CACHED=1;;
    --fast) FAST=1;;
    --keep) KEEP=1;;
    --list) ACTION=list;;
    --prepare) ACTION=prepare;;
    --update-lock) ACTION=lock;;
    --clean) ACTION=clean;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*) echo "distro-matrix: unknown option $1" >&2; exit 2;;
    *) SEL+=("$1");;
  esac; shift
done
case $BACKEND in sim|qemu) ;; *) echo "distro-matrix: backend sim or qemu" >&2; exit 2;; esac
if [ -z "${SARM_INST:-}" ]; then
  # repo checkout: tools/gates/ below the source root; project folder: newest <V>-work beside tools/
  if [ "${HERE##*/}" = gates ]; then SARM_INST=$(dirname "$(dirname "$HERE")")/steam-arm-install.sh
  else SARM_INST=$(ls -d "$HERE"/../[0-9]*-work 2>/dev/null | sort -V | tail -n 1)/steam-arm-install.sh; fi
fi
INST=$SARM_INST

host_arch(){ case $(uname -m) in x86_64) echo amd64;; aarch64|arm64) echo arm64;; *) uname -m;; esac; }
HOSTARCH=$(host_arch)
field(){ printf '%s\n' "$ROWS" | awk -F'|' -v r="$1" -v f="$2" '$1 == r {print $f}'; }
row_arch(){ if [ "$(field "$1" 2)" = x86 ]; then echo amd64; elif [ $BACKEND = qemu ]; then echo arm64; else echo "$HOSTARCH"; fi; }
row_image(){ local i a; i=$(field "$1" 3); a=$(row_arch "$1")
  case $i in *,*) if [ "$a" = amd64 ]; then echo "${i%%,*}"; else echo "${i#*,}"; fi;; *) echo "$i";; esac; }
lock_digest(){ awk -v i="$1" -v a="$2" '$1 == i && $2 == a {print $3}' "$LOCK"; }
# rootfs of architecture $1 runs here: same as host, or qemu binfmt with F flag (interpreter opened at registration)
can_exec(){
  local q
  [ "$1" = "$HOSTARCH" ] && return 0
  case $1 in amd64) q=qemu-x86_64;; arm64) q=qemu-aarch64;; *) return 1;; esac
  grep -qx enabled "/proc/sys/fs/binfmt_misc/$q" 2>/dev/null && grep -q '^flags:.*F' "/proc/sys/fs/binfmt_misc/$q"
}
exec_why(){ case $1 in arm64) echo "no qemu-aarch64 binfmt (F flag) on this $HOSTARCH host";; *) echo "no qemu-x86_64 binfmt (F flag) on this $HOSTARCH host";; esac; }
# package names per distro; Ubuntu 26.04 renamed qemu-user-static and binfmt-support to qemu-user and qemu-user-binfmt
EXEC_HINT="qemu user emulation with binfmt registration (Arch: sudo pacman -S qemu-user-static qemu-user-static-binfmt; Debian, Ubuntu to 25.10: sudo apt install qemu-user-static binfmt-support; Ubuntu 26.04: sudo apt install qemu-user qemu-user-binfmt)"
# rootless namespace: root mapped to the caller, plus subordinate ids (game account, apt sandbox user)
NSX=(unshare --map-auto --map-root-user)
if ! "${NSX[@]}" true 2>/dev/null; then NSX=(unshare --map-root-user); MAPAUTO=0; else MAPAUTO=1; fi
ns(){ "${NSX[@]}" "$@"; }
nsrm(){ [ -e "$1" ] && ns rm -rf "$1"; }

# --- chroot run inside a new mount and pid namespace: proc, stand-in cpuinfo, minimal /dev, tmpfs /run /tmp ---
inner(){
  local R=$1 d; shift
  if [ -d "$R/sim/realproc" ]; then
    # device-tree model wanted on a host without one: /proc of links into real proc, plus device-tree and cpuinfo
    mount -t proc proc "$R/sim/realproc" || exit 90
    mount -t tmpfs -o mode=555 tmpfs "$R/proc"
    for d in "$R/sim/realproc"/*; do ln -s "/sim/realproc/${d##*/}" "$R/proc/${d##*/}"; done
    rm -f "$R/proc/cpuinfo" "$R/proc/device-tree"; cp "$R/sim/cpuinfo" "$R/proc/cpuinfo"
    ln -s /sys/firmware/devicetree/base "$R/proc/device-tree"
  else
    mount -t proc proc "$R/proc" || exit 90
    [ -f "$R/sim/cpuinfo" ] && mount --bind "$R/sim/cpuinfo" "$R/proc/cpuinfo"
  fi
  mount -t tmpfs -o mode=755 tmpfs "$R/dev"
  for d in null zero full random urandom tty; do : > "$R/dev/$d"; mount --bind "/dev/$d" "$R/dev/$d"; done
  mkdir -p "$R/dev/pts" "$R/dev/shm"; mount -t tmpfs -o mode=1777 tmpfs "$R/dev/shm"
  mount -t devpts -o newinstance,ptmxmode=0666 devpts "$R/dev/pts" 2>/dev/null && ln -s pts/ptmx "$R/dev/ptmx"
  ln -s /proc/self/fd "$R/dev/fd"
  mount -t tmpfs -o mode=755 tmpfs "$R/run"; mount -t tmpfs -o mode=1777 tmpfs "$R/tmp"
  [ -e "$R/etc/resolv.conf" ] && [ ! -L "$R/etc/resolv.conf" ] && mount --bind /etc/resolv.conf "$R/etc/resolv.conf" 2>/dev/null
  exec chroot "$R" /usr/bin/env -i HOME=/root LANG=C.UTF-8 TERM=dumb PATH="${SIMPATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}" "$@"
}
in_root(){ "${NSX[@]}" --mount --pid --fork --kill-child env SIMPATH="${SIMPATH:-}" bash -c "$(declare -f inner); inner \"\$@\"" _ "$@"; }

# --- images ---
base_dir(){ local i=$1 a=$2 d; d=$(lock_digest "$i" "$a"); echo "$CACHE/base/$(printf '%s' "$i" | tr '/:' '__')-$a-${d#sha256:}" | cut -c1-200; }
fetch_base(){
  local i=$1 a=$2 d b
  d=$(lock_digest "$i" "$a"); [ -n "$d" ] || { echo "no $i $a digest in $LOCK"; return 1; }
  b=$(base_dir "$i" "$a"); [ -f "$b.ok" ] && return 0
  [ "$CACHED" = 1 ] && return 2
  echo "  fetching $i ($a) ${d:0:19}" >&2
  nsrm "$b"; mkdir -p "$CACHE/base"
  python3 -I "$FETCH" fetch "${i%:*}@$d" "$b" >&2 || { nsrm "$b"; return 1; }
  : > "$b.ok"
}
is_pi_row(){ case $1 in raspios*) return 0;; esac; return 1; }
# Pi rows share one prepared tree
prep_dir(){ local k=$1; is_pi_row "$k" && k=raspios; echo "$CACHE/prep/$k-$BACKEND-$(row_arch "$1")"; }
prep_stamp(){ echo "$(lock_digest "$(row_image "$1")" "$(row_arch "$1")") prep $PREP_VER"; }

# sim on a non-arm64 rootfs: arm64 apt config, sources synced from /etc/apt at every call
SIM_APT_CONF='APT::Architecture "arm64";
APT::Architectures { "arm64"; };
Dir::State "/sim/apt/state/";
Dir::State::status "/sim/apt/status";
Dir::Cache "/sim/apt/cache/";
Dir::Log "/sim/apt/log/";
Dir::Etc::SourceList "/sim/apt/sources.list";
Dir::Etc::SourceParts "/sim/apt/sources.list.d/";
Acquire::Languages "none";
Acquire::GzipIndexes "true";
Acquire::CompressionTypes::Order { "gz"; };
Debug::NoLocking "true";
APT::Get::List-Cleanup "false";'

# prepared rootfs: tools setup runs on this host (python3, curl, gpg, compiler), game account, arm64 package lists
prep_script(){ cat <<'PREP'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
P="passwd systemd udev python3 curl ca-certificates file gpg zstd xz-utils procps psmisc patchelf gcc libc6-dev libvulkan-dev python3-pil bsdutils util-linux"
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in *" ubuntu "*) P="$P software-properties-common";; esac
apt-get install -y -qq --no-install-recommends $P >/dev/null
G=$(for g in video render input audio; do getent group "$g" >/dev/null && printf '%s,' "$g"; done)
id "$GU" >/dev/null 2>&1 || useradd -m -s /bin/bash ${G:+-G "${G%,}"} "$GU"
# folders a desktop session leaves in an account that has logged in once
su -s /bin/sh -c 'mkdir -p ~/.config ~/.local/share ~/.cache ~/Desktop' "$GU"
# no init system in the chroot: maintainer scripts' service restarts succeed as on a booted system, daemons stay down
mkdir -p /usr/local/sbin
printf '#!/bin/sh\necho "matrix stand-in: service $*" >&2\nexit 0\n' > /usr/local/sbin/service
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/local/sbin/service /usr/sbin/policy-rc.d
# apt runs maintainer scripts with DPkg::Path, default without /usr/local/sbin
echo 'DPkg::Path "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";' > /etc/apt/apt.conf.d/00matrix-dpkg-path
mkdir -p /etc/udev/rules.d
apt-get clean
PREP
}
pi_script(){ cat <<'PI'
set -e
# keyring package as on Pi OS (the old .gpg.key binding is SHA-1, refused by sqv)
k=raspberrypi-archive-keyring_2025.1+rpt1_all.deb
curl -fsSL -o /tmp/$k https://archive.raspberrypi.com/debian/pool/main/r/raspberrypi-archive-keyring/$k
echo "2e727149d7acb8cc7f604e66d0049161039c8aa1eaf1175e54f9e69d963d60e4  /tmp/$k" | sha256sum -c --quiet
dpkg -i /tmp/$k >/dev/null; rm -f /tmp/$k
printf 'Types: deb\nURIs: http://archive.raspberrypi.com/debian/\nSuites: trixie\nComponents: main\nArchitectures: arm64\nSigned-By: /usr/share/keyrings/raspberrypi-archive-keyring.gpg\n' > /etc/apt/sources.list.d/raspi.sources
echo 'Raspberry Pi reference 2026-10-06' > /etc/rpi-issue
mkdir -p /boot/firmware
printf '# For more options and information see\n# http://rptl.io/configtxt\ndtparam=audio=on\ncamera_auto_detect=1\ndisplay_auto_detect=1\nauto_initramfs=1\ndtoverlay=vc4-kms-v3d\nmax_framebuffers=2\ndisable_fw_kms_setup=1\narm_64bit=1\ndisable_overscan=1\narm_boost=1\n\n[cm5]\ndtoverlay=dwc2,dr_mode=host\n\n[all]\n' > /boot/firmware/config.txt
: > /boot/firmware/kernel8.img; : > /boot/firmware/kernel_2712.img
PI
}
# sources for the arm64 view: Ubuntu archive hosts point at ports; architecture lines dropped in .list files
sim_sources_script(){ cat <<'SRC'
#!/bin/sh
# matrix stand-in: arm64 view of /etc/apt sources (Ubuntu ports host for arm64)
d=/sim/apt/sources.list.d; mkdir -p "$d"; rm -f "$d"/*
rw(){ sed -e 's#http://archive.ubuntu.com/ubuntu/\{0,1\}#http://ports.ubuntu.com/ubuntu-ports/#g' \
          -e 's#http://security.ubuntu.com/ubuntu/\{0,1\}#http://ports.ubuntu.com/ubuntu-ports/#g' \
          -e 's#\[arch=[^]]*\] ##' "$1"; }
[ -f /etc/apt/sources.list ] && rw /etc/apt/sources.list > /sim/apt/sources.list || : > /sim/apt/sources.list
for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do [ -f "$f" ] && rw "$f" > "$d/${f##*/}"; done
exit 0
SRC
}

prepare(){
  local r=$1 i a b p kind; kind=$(field "$r" 2); i=$(row_image "$r"); a=$(row_arch "$r")
  fetch_base "$i" "$a"; case $? in 0) ;; 2) return 2;; *) return 1;; esac
  case $kind in gate|x86) return 0;; esac
  p=$(prep_dir "$r"); b=$(base_dir "$i" "$a")
  [ -f "$p.ok" ] && [ "$(cat "$p.ok")" = "$(prep_stamp "$r")" ] && return 0
  [ "$CACHED" = 1 ] && return 2
  [ "$MAPAUTO" = 1 ] || { echo "no subordinate id range (unshare --map-auto)"; return 1; }
  echo "  preparing $r ($a): host tools, account $GAMEUSER, package lists" >&2
  nsrm "$p"; rm -f "$p.ok"; mkdir -p "$CACHE/prep"
  ns cp -a "$b" "$p" || return 1
  ns mkdir -p "$p/sim/apt/state/lists/partial" "$p/sim/apt/cache/archives/partial" "$p/sim/bin" "$p/sim/log"
  ns touch "$p/etc/resolv.conf"
  ns sh -c 'cat > "$1/sim/prep.sh"' _ "$p" < <(prep_script)
  ns sh -c 'cat > "$1/sim/pi.sh"' _ "$p" < <(pi_script)
  ns sh -c 'cat > "$1/sim/bin/sim-sources"; chmod 755 "$1/sim/bin/sim-sources"' _ "$p" < <(sim_sources_script)
  in_root "$p" env GU=$GAMEUSER sh /sim/prep.sh >&2 || { echo "prep failed (host tools)"; return 1; }
  is_pi_row "$r" && { in_root "$p" sh /sim/pi.sh >&2 || { echo "prep failed (Pi archive)"; return 1; }; }
  if [ "$a" != arm64 ]; then
    printf '%s\n' "$SIM_APT_CONF" | ns sh -c 'cat > "$1/sim/apt/apt.conf"' _ "$p"
    ns sh -c 'sed "s/^Architecture: amd64$/Architecture: arm64/" "$1/var/lib/dpkg/status" > "$1/sim/apt/status"' _ "$p"
    in_root "$p" sh -c '/sim/bin/sim-sources && apt-get -c /sim/apt/apt.conf update -qq' >&2 \
      || { echo "prep failed (arm64 package lists)"; return 1; }
  elif is_pi_row "$r"; then
    in_root "$p" apt-get update -qq >&2 || { echo "prep failed (package lists)"; return 1; }
  fi
  ns rm -f "$p/sim/prep.sh" "$p/sim/pi.sh"
  prep_stamp "$r" > "$p.ok"
}

# --- stand-ins written into each run copy ---
# run copy's /sim and /sys belong to the caller (mapped root): written directly
stub(){ cat > "$1/sim/bin/$2" && chmod 755 "$1/sim/bin/$2"; }
standins(){
  local R=$1 simapt=$2 mode=$3 r=$4
  ns mkdir -p "$R/sim/bin" "$R/sim/log" "$R/sim/fex/usr/bin" "$R/sim/www"
  chmod 1777 "$R/sim/log"
  printf 'SIM_APT=%s\nSIM_MODE=%s\n' "$simapt" "$mode" > "$R/sim/env"
  # arm64 CPU with LSE atomics (Cortex-A76 class); Pi 4 row: Cortex-A72 without LSE (x86 client path)
  local feat="fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp" part=0xd0b
  [ "$r" = raspios-pi4 ] && { feat="fp asimd evtstrm crc32 cpuid"; part=0xd08; : > "$R/sim/nolse"; }
  for c in 0 1 2 3; do printf 'processor\t: %s\nBogoMIPS\t: 108.00\nFeatures\t: %s\nCPU implementer\t: 0x41\nCPU architecture: 8\nCPU variant\t: 0x4\nCPU part\t: %s\nCPU revision\t: 1\n\n' "$c" "$feat" "$part"; done > "$R/sim/cpuinfo"
  if is_pi_row "$r"; then
    # device tree (model, compatible) and the v3d render node of that board
    mkdir -p "$R/sys/firmware/devicetree/base" "$R/sys/class/drm/renderD128/device/of_node" "$R/sys/bus/platform/drivers/v3d"
    if [ "$r" = raspios-pi4 ]; then
      printf 'Raspberry Pi 4 Model B Rev 1.4\0' > "$R/sys/firmware/devicetree/base/model"
      printf 'raspberrypi,4-model-b\0brcm,bcm2711\0' > "$R/sys/firmware/devicetree/base/compatible"
      printf 'brcm,2711-v3d\0' > "$R/sys/class/drm/renderD128/device/of_node/compatible"
    else
      printf 'Raspberry Pi 5 Model B Rev 1.0\0' > "$R/sys/firmware/devicetree/base/model"
      printf 'raspberrypi,5-model-b\0brcm,bcm2712\0' > "$R/sys/firmware/devicetree/base/compatible"
      printf 'brcm,2712-v3d\0' > "$R/sys/class/drm/renderD128/device/of_node/compatible"
    fi
    ln -sfn ../../../../bus/platform/drivers/v3d "$R/sys/class/drm/renderD128/device/driver"
    [ -e /proc/device-tree/model ] || mkdir -p "$R/sim/realproc"
  fi
  stub "$R" log <<'EOF'
#!/bin/sh
echo "$*" >> /sim/log/calls
EOF
  stub "$R" apt-get <<'EOF'
#!/bin/bash
# matrix stand-in: arm64 package side through /sim/apt (sim on non-arm64 rootfs); install simulated in sim mode
. /sim/env; /sim/bin/log "apt-get $*"
c=(); [ "$SIM_APT" = 1 ] && { /sim/bin/sim-sources; c=(-c /sim/apt/apt.conf); }
[ "$SIM_MODE" = real ] && exec /usr/bin/apt-get "${c[@]}" "$@"
case " $* " in
  *" install "*)
    out=$(/usr/bin/apt-get "${c[@]}" -s "$@" 2>&1); rc=$?
    printf '%s\n' "$out" >> /sim/log/apt-sim.log
    [ $rc = 0 ] || { printf '%s\n' "$out" | tail -n 8 >&2; exit $rc; }
    printf '%s\n' "$out" | awk '/^Inst /{v=$3; if (v ~ /^\[/) v=$4; gsub(/[()]/, "", v); print $2, v}' >> /sim/installed
    echo "  [sim] $(printf '%s\n' "$out" | grep -c '^Inst ') packages resolved (simulated install)"
    case " $* " in *" fex-emu-armv"*) /sim/bin/sim-fex;; esac
    exit 0;;
esac
exec /usr/bin/apt-get "${c[@]}" "$@"
EOF
  stub "$R" apt-cache <<'EOF'
#!/bin/bash
. /sim/env
c=(); [ "$SIM_APT" = 1 ] && { /sim/bin/sim-sources; c=(-c /sim/apt/apt.conf); }
exec /usr/bin/apt-cache "${c[@]}" "$@"
EOF
  stub "$R" sim-sources < <(sim_sources_script)
  stub "$R" dpkg <<'EOF'
#!/bin/bash
# matrix stand-in: arm64 package architecture (sim on non-arm64 rootfs); FEX stand-ins owned by a fex-emu package
. /sim/env
case "${1:-}" in
  --print-architecture) [ "$SIM_APT" = 1 ] && { echo arm64; exit 0; };;
  --print-foreign-architectures) [ "$SIM_APT" = 1 ] && exit 0;;
  -S|--search) case "${2:-}" in /sim/fex/*) echo "fex-emu-armv8.2: ${2#/sim/fex}"; exit 0;; esac;;
esac
exec /usr/bin/dpkg "$@"
EOF
  stub "$R" dpkg-query <<'EOF'
#!/bin/bash
# matrix stand-in: packages of the simulated install answer as installed
. /sim/env
if [ "$SIM_MODE" = sim ] && [ "${1:-}" = -W ] && [ -s /sim/installed ]; then
  shift; fmt='${Package}\t${Version}\n'; names=()
  while [ $# -gt 0 ]; do case $1 in -f|--showformat) fmt=$2; shift;; -f=*|--showformat=*) fmt=${1#*=};; *) names+=("$1");; esac; shift; done
  rc=0
  for n in "${names[@]}"; do
    hit=0
    while read -r p v; do
      case $p in $n) hit=1; f=${fmt//'${Package}'/$p}; f=${f//'${Version}'/$v}; f=${f//'${Status}'/install ok installed}
        printf '%b' "$f";; esac
    done < /sim/installed
    [ $hit = 1 ] || /usr/bin/dpkg-query -W -f="$fmt" "$n" || rc=1
  done
  exit $rc
fi
exec /usr/bin/dpkg-query "$@"
EOF
  stub "$R" ldconfig <<'EOF'
#!/bin/bash
# matrix stand-in: libraries of the simulated install listed
. /sim/env
if [ "$SIM_MODE" = sim ] && [ "${1:-}" = -p ]; then
  /sbin/ldconfig -p 2>/dev/null || /usr/sbin/ldconfig -p
  for l in libSDL3.so.0 libopenal.so.1 libgtk-x11-2.0.so.0 libibus-1.0.so.5; do
    printf '\t%s (libc6,AArch64) => /usr/lib/aarch64-linux-gnu/%s\n' "$l" "$l"; done
  exit 0
fi
[ -x /sbin/ldconfig ] && exec /sbin/ldconfig "$@"; exec /usr/sbin/ldconfig "$@"
EOF
  [ "$simapt" = 1 ] && stub "$R" uname <<'EOF'
#!/bin/bash
# matrix stand-in: arm64 machine name
/usr/bin/uname "$@" | sed 's/x86_64/aarch64/g'
EOF
  # sim on a non-arm64 rootfs: host programs read as arm64 builds; bubblewrap of the simulated install (x86 client path)
  [ "$simapt" = 1 ] && { stub "$R" file <<'EOF'
#!/bin/bash
# matrix stand-in: file reports host programs as arm64 builds
/usr/bin/file "$@" | sed 's/x86-64/aarch64/g; s/x86_64/aarch64/g'
EOF
    cp /bin/true "$R/sim/bin/bwrap"; }
  # FEX package stand-ins, made when the (simulated) install names a fex-emu build
  stub "$R" sim-fex <<'EOF'
#!/bin/sh
f=/sim/fex/usr
mkdir -p $f/bin $f/share/fex-emu/GuestThunks $f/lib/aarch64-linux-gnu/fex-emu/HostThunks
echo '{"DB":{}}' > $f/share/fex-emu/ThunksDB.json
for b in FEX FEXServer FEXBash FEXGetConfig FEXRootFSFetcher; do
  printf '#!/bin/sh\nexec /sim/bin/fex-standin %s "$@"\n' "$b" > $f/bin/$b; chmod 755 $f/bin/$b; ln -sf $f/bin/$b /sim/bin/$b
done
EOF
  stub "$R" fex-standin <<'EOF'
#!/bin/bash
# matrix stand-in for FEX programs; the fetcher leaves a minimal x86-64 RootFS where FEXRootFSFetcher puts it
b=$1; shift; /sim/bin/log "$b $*"
case $b in
  FEXGetConfig) [ "${1:-}" = --version ] && echo 2609.1;;
  FEXRootFSFetcher)
    d=$HOME/.fex-emu/RootFS; t=$d/Ubuntu_24_04; mkdir -p "$t/usr/lib/x86_64-linux-gnu" "$t/usr/lib/i386-linux-gnu" "$t/usr/bin" "$t/var/lib/dpkg/info"
    : > "$d/Ubuntu_24_04.sqsh"
    for f in usr/lib/x86_64-linux-gnu/libc.so.6 usr/lib/i386-linux-gnu/libc.so.6 usr/lib/x86_64-linux-gnu/libGL.so.1; do echo stand-in > "$t/$f"; done
    for f in bash apt apt-get dpkg bwrap; do printf '#!/bin/sh\n' > "$t/usr/bin/$f"; chmod 755 "$t/usr/bin/$f"; done
    chown -R 1000:1000 "$t" 2>/dev/null;;
esac
exit 0
EOF
  # real install: packaged FEX stays, its RootFS download (about 525 MB) is the stand-in
  [ "$mode" = real ] && stub "$R" FEXRootFSFetcher <<'EOF'
#!/bin/sh
exec /sim/bin/fex-standin FEXRootFSFetcher "$@"
EOF
  # 16K page kernel (Pi 5 default) when /sim/pagesize names it
  stub "$R" getconf <<'EOF'
#!/bin/sh
[ "${1:-}" = PAGESIZE ] && [ -s /sim/pagesize ] && { cat /sim/pagesize; exit 0; }
exec /usr/bin/getconf "$@"
EOF
  # Valve client download: stand-in manifests and packages served for the client URLs, real curl otherwise;
  # native client stand-in stops with SIGILL when /sim/nolse is there (CPU without LSE: setup keeps the x86 client)
  python3 -I - "$R/sim/www" <<'PY'
import hashlib, io, os, sys, zipfile
w = sys.argv[1]


def zipped(members):
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z:
        for n, body in members:
            i = zipfile.ZipInfo(n)
            i.external_attr = 0o755 << 16
            z.writestr(i, body)
    return b.getvalue()


def entry(name, data):
    return ('\t"%s"\n\t{\n\t\t"file"\t\t"%s.zip.%s"\n\t\t"sha2"\t\t"%s"\n\t}\n'
            % (name, name, hashlib.sha1(data).hexdigest(), hashlib.sha256(data).hexdigest()))


data = zipped((("steamrtarm64\\steam", "#!/bin/sh\n[ -e /sim/nolse ] && kill -ILL $$\necho stand-in client\n"),
               ("steamrtarm64\\builddate.txt", "stand-in\n")))
open(os.path.join(w, "client.zip"), "wb").write(data)
open(os.path.join(w, "manifest"), "w").write('"linuxarm64"\n{\n\t"version"\t\t"1790000000"\n' + entry("bins_linuxarm64_linuxarm64", data) + "}\n")
boot = zipped((("steam.sh", "#!/bin/sh\necho stand-in x86 client\n"), ("ubuntu12_32/steam", b"\x7fELF\x01\x01\x01" + b"\0" * 57),
               ("ubuntu12_64/steamwebhelper.sh", "#!/bin/bash\nexec \\\n  \"${DIR}/steamwebhelper_sniper_wrap.sh\" \"$@\"\n")))
rt = zipped((("ubuntu12_32/steam-runtime.tar.xz", b"stand-in runtime"), ("ubuntu12_32/steam-runtime.tar.xz.checksum", "0  steam-runtime.tar.xz\n")))
open(os.path.join(w, "x86boot.zip"), "wb").write(boot)
open(os.path.join(w, "x86rt.zip"), "wb").write(rt)
open(os.path.join(w, "manifest-x86"), "w").write('"ubuntu12"\n{\n\t"version"\t\t"1790000001"\n' + entry("steam_ubuntu12", boot) + entry("runtime_scout_ubuntu12", rt) + "}\n")
PY
  stub "$R" curl <<'EOF'
#!/bin/bash
# matrix stand-in: Valve client manifest and package from /sim/www; every other address through real curl
/sim/bin/log "curl $*"
u=; o=; a=("$@")
while [ $# -gt 0 ]; do case $1 in -o|--output) o=$2; shift;; https://*|http://*) u=$1;; esac; shift; done
case $u in
  https://client-update.steamstatic.com/steam_client_ubuntu12) cp /sim/www/manifest-x86 "$o"; exit 0;;
  https://client-update.steamstatic.com/steam_ubuntu12.zip.*) cp /sim/www/x86boot.zip "$o"; exit 0;;
  https://client-update.steamstatic.com/runtime_scout_ubuntu12.zip.*) cp /sim/www/x86rt.zip "$o"; exit 0;;
  https://client-update.steamstatic.com/steam_client_*) cp /sim/www/manifest "$o"; exit 0;;
  https://client-update.steamstatic.com/bins_*|https://client-update.steamstatic.com/*.zip.*) cp /sim/www/client.zip "$o"; exit 0;;
esac
exec /usr/bin/curl "${a[@]}"
EOF
}

# --- one row ---
OUTP=0 OUTF=0 OUTS=0
res(){ local k=$1; shift; echo "$k distro-matrix $BACKEND $*"; case $k in PASS) OUTP=$((OUTP+1));; FAIL) OUTF=$((OUTF+1));; SKIP) OUTS=$((OUTS+1));; esac; }
snap(){ ns python3 -I "$TREE" snap "$1" "$2"; }
# install.sh run as root in the chroot, stdin from $3 (file) or a terminal fed $3 (string, through script)
run_inst(){
  local R=$1 log=$2 tty=$3; shift 3
  if [ -n "$tty" ]; then
    in_root "$R" bash -c 'printf "%s\n" "$1" | script -qec "$2" /dev/null' _ "$tty" "GAMEUSER=$GAMEUSER bash /sim/install.sh $*" > "$log" 2>&1
  else
    in_root "$R" env GAMEUSER=$GAMEUSER bash /sim/install.sh "$@" < /dev/null > "$log" 2>&1
  fi
}
row(){
  local r=$1 kind label a i R L rc d why simapt=0 mode=sim
  kind=$(field "$r" 2); label=$(field "$r" 4); a=$(row_arch "$r"); i=$(row_image "$r")
  [ -n "$kind" ] || { res FAIL "$r: unknown row"; return; }
  if [ "$FAST" = 1 ] && case $kind in install|pagesize) true;; *) false;; esac; then res SKIP "$r ($label): full install row (left out by --fast)"; return; fi
  # x86 row belongs to the sim backend only
  [ "$kind" = x86 ] && [ "$BACKEND" = qemu ] && return
  can_exec "$a" || { res SKIP "$r ($label): $(exec_why "$a")"; return; }
  case $kind in install|pagesize) [ "$MAPAUTO" = 0 ];; *) false;; esac && { res SKIP "$r ($label): no subordinate id range for the game account (unshare --map-auto)"; return; }
  [ -n "$(lock_digest "$i" "$a")" ] || { res SKIP "$r ($label): no $a image of $i in distro-matrix.lock"; return; }
  why=$(prepare "$r"); rc=$?
  [ $rc = 2 ] && { res SKIP "$r ($label): image not cached (distro-matrix.sh --backend $BACKEND --prepare $r fetches it)"; return; }
  [ $rc = 0 ] || { res FAIL "$r ($label): image or preparation failed: ${why:-see output}"; return; }
  L=$CACHE/logs/$r-$BACKEND; rm -rf "$L"; mkdir -p "$L"
  mkdir -p "$CACHE/run"; R=$(mktemp -d "$CACHE/run/$r.XXXXXX"); rmdir "$R"
  case $kind in gate|x86) ns cp -a "$(base_dir "$i" "$a")" "$R";; *) ns cp -a "$(prep_dir "$r")" "$R";; esac
  ns mkdir -p "$R/sim"; ns cp "$INST" "$R/sim/install.sh"
  [ "$BACKEND" = qemu ] && mode=real
  [ "$a" != arm64 ] && [ "$kind" != x86 ] && simapt=1
  case $kind in gate|x86) SIMPATH=;; *) standins "$R" $simapt $mode "$r"; SIMPATH=/sim/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;; esac
  export SIMPATH
  [ $mode = real ] && in_root "$R" dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | sort > "$L/pkgver-before.txt" \
    && cut -d' ' -f1 "$L/pkgver-before.txt" > "$L/pkgs-before.txt"
  snap "$R" "$L/before.tsv"
  case $kind in
    gate|x86)
      run_inst "$R" "$L/install.log" "" --defaults; rc=$?
      if [ $rc = 1 ] && grep -q 'needs a Debian or Ubuntu family distribution on 64-bit ARM' "$L/install.log" && grep -q 'No change made' "$L/install.log"; then
        res PASS "$r ($label): --defaults stops at platform gate ($(grep -o "[^,]*\. No change made" "$L/install.log" | head -n 1 | sed "s/^ //"))"
      else res FAIL "$r ($label): --defaults did not stop at platform gate (rc $rc): $(tail -n 2 "$L/install.log" | tr '\n' ' ')"; fi
      run_inst "$R" "$L/remove.log" "" --remove --purge; rc=$?
      if [ $rc = 1 ] && grep -q 'No change made' "$L/remove.log"; then res PASS "$r ($label): --remove --purge stops at platform gate"
      else res FAIL "$r ($label): --remove --purge did not stop at platform gate (rc $rc)"; fi
      snap "$R" "$L/after.tsv"
      d=$(python3 -I "$TREE" diff "$L/before.tsv" "$L/after.tsv" --strict --count 2>&1); rc=$?
      printf '%s\n' "$d" > "$L/diff.txt"
      if [ $rc = 0 ]; then res PASS "$r ($label): whole tree unchanged"
      else res FAIL "$r ($label): tree changed: $(printf '%s\n' "$d" | sed -n '2,6p' | tr '\n' ';')"; fi;;
    preflight)
      run_inst "$R" "$L/install.log" "" --defaults; rc=$?
      if [ $rc = 1 ] && grep -q "package sources lack host packages setup needs" "$L/install.log"; then
        res PASS "$r ($label): stops at host package preflight, missing: $(sed -n 's/.*setup needs: //p' "$L/install.log" | head -n 1)"
      else res FAIL "$r ($label): no preflight stop (rc $rc): $(grep -m1 -E '^\S*\[fail\]' "$L/install.log" | cut -c1-160)"; fi
      snap "$R" "$L/after.tsv"
      d=$(python3 -I "$TREE" diff "$L/before.tsv" "$L/after.tsv" --keep '^/var/lib/apt/lists/=package index refresh (apt-get update)' --count 2>&1); rc=$?
      printf '%s\n' "$d" > "$L/diff.txt"
      # preflight keeps nothing but package indexes
      if [ $rc = 0 ] && ! printf '%s\n' "$d" | grep -v '/var/lib/apt/lists/' | grep -q '^\(added\|removed\|changed\)'; then
        res PASS "$r ($label): tree unchanged (package indexes aside)"
      else res FAIL "$r ($label): tree changed: $(printf '%s\n' "$d" | grep -v '/var/lib/apt/lists/' | sed -n '2,6p' | tr '\n' ';')"; fi;;
    install)
      row_install "$r" "$label" "$R" "$L";;
    pagesize)
      # 16K kernel: setup only adds the 4K kernel line and asks for a reboot; after it (4K) the full install
      echo 16384 > "$R/sim/pagesize"
      run_inst "$R" "$L/switch.log" "" --defaults; rc=$?
      if [ $rc = 0 ] && grep -q 'now selects 4K page kernel (kernel8.img)' "$L/switch.log" \
         && grep -qx 'kernel=kernel8.img' "$R/boot/firmware/config.txt" && [ -f "$R/boot/firmware/config.txt.steam-arm.bak" ]; then
        res PASS "$r ($label): 16K page size: kernel8.img line added to config.txt, backup kept, setup stops for reboot"
      else res FAIL "$r ($label): 16K page size: no kernel switch (rc $rc): $(grep -m1 '\[fail\]' "$L/switch.log" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-200)"; fi
      : > "$R/sim/pagesize"
      row_install "$r" "$label" "$R" "$L"
      if [ -f "$R/boot/firmware/config.txt" ] && ! grep -q 'steam-arm' "$R/boot/firmware/config.txt"; then
        res PASS "$r ($label): config.txt without the kernel line after --remove --purge"
      else res FAIL "$r ($label): config.txt still names setup's kernel line after --remove --purge"; fi;;
  esac
  [ "$KEEP" = 1 ] && echo "  run tree kept: $R" || nsrm "$R"
}
row_install(){
  local r=$1 label=$2 R=$3 L=$4 rc d n keeps=()
  if [ "$r" = raspios ]; then
    d=$(in_root "$R" apt-cache policy libgl1-mesa-dri 2>/dev/null | sed -n 's/^  Candidate: //p')
    case $d in *rpt*) res PASS "$r ($label): host Mesa candidate from Pi archive: $d (driver archive Mesa 26.1.8)";;
      *) res FAIL "$r ($label): host Mesa candidate not from Pi archive: ${d:-none}";; esac
  fi
  run_inst "$R" "$L/install.log" "" --defaults; rc=$?
  n=$(grep -o '\[sim\] [0-9]* packages resolved' "$L/install.log" | grep -o '[0-9]*' | head -n 1)
  if [ $rc = 0 ] && grep -q '11/11  done' "$L/install.log"; then
    res PASS "$r ($label): setup --defaults completed${n:+ ($n arm64 packages resolved)}"
  else
    res FAIL "$r ($label): setup --defaults rc $rc: $(grep -m1 '\[fail\]' "$L/install.log" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-200)"
  fi
  grep -q '\[warn\]' "$L/install.log" && sed 's/\x1b\[[0-9;]*m//g' "$L/install.log" | grep '^\[warn\]' > "$L/warnings.txt"
  snap "$R" "$L/installed.tsv"
  python3 -I "$TREE" diff "$L/before.tsv" "$L/installed.tsv" --strict > "$L/install-diff.txt" 2>&1
  n=$(grep -c '^added' "$L/install-diff.txt")
  if grep -q '^added  */usr/local/bin/steam-arm$' "$L/install-diff.txt" && grep -q '^added  */etc/steam-arm/steam-arm.conf$' "$L/install-diff.txt"; then
    res PASS "$r ($label): setup wrote launcher and settings ($n paths added)"
  else res FAIL "$r ($label): launcher or settings file missing after setup"; fi
  if [ "$r" = raspios-pi4 ]; then
    # Pi 4 facts: x86 client by CPU rule, platform pi4, VideoCore VI family, FEX build for Armv8.0, host Mesa from Pi archive
    d=$(grep -E '^(CLIENT|CLIENT_SET|PLATFORM|CPU_LSE|GPU_FAMILY)=' "$R/etc/steam-arm/steam-arm.conf" 2>/dev/null | sort | paste -sd' ' -)
    if [ "$d" = "CLIENT=x86 CLIENT_SET=auto CPU_LSE=0 GPU_FAMILY=broadcom-v3d42 PLATFORM=pi4" ]; then res PASS "$r ($label): settings CLIENT=x86 (auto), PLATFORM=pi4, CPU_LSE=0, GPU_FAMILY=broadcom-v3d42"
    else res FAIL "$r ($label): settings for Pi 4 wrong: ${d:-none}"; fi
    if grep -q 'FEX build for this CPU (ARMv8.0 features): fex-emu-armv8.0' "$L/install.log" && grep -q '^MESA_HOST=.*rpt' "$R/etc/steam-arm/steam-arm.conf"; then
      res PASS "$r ($label): FEX package fex-emu-armv8.0 picked, MESA_HOST from Pi archive ($(sed -n 's/^MESA_HOST=//p' "$R/etc/steam-arm/steam-arm.conf"))"
    else res FAIL "$r ($label): FEX build line or MESA_HOST missing: $(grep -o 'FEX build for this CPU[^$]*' "$L/install.log" | head -n 1) $(grep '^MESA_HOST=' "$R/etc/steam-arm/steam-arm.conf")"; fi
    # game account's files belong to a subordinate id: read through the namespace; FEX stand-in carries thunk folders
    d=$(ns sh -c 'test -f "$1" && echo client; tr -d " \n" < "$2" 2>/dev/null | grep -o "\"ThunksDB\":{\"GL\":[01],\"Vulkan\":[01]}"' _ \
        "$R/home/$GAMEUSER/.local/share/steam-arm/.local/share/Steam/ubuntu12_32/steam" "$R/home/$GAMEUSER/.fex-emu/Config.json" 2>/dev/null | paste -sd' ' -)
    if [ "$d" = 'client "ThunksDB":{"GL":1,"Vulkan":1}' ]; then res PASS "$r ($label): x86 client files in place; thunks on in Config.json (FEX stand-in has thunk folders)"
    else res FAIL "$r ($label): x86 client files or Config.json thunk state wrong: ${d:-nothing readable}"; fi
    # the arm64 FEX package of the PPA lists the five thunk files setup searches for
    d=$(in_root "$R" sh -c 'cd /tmp && rm -f fex-emu-armv8.0_*.deb && apt-get download fex-emu-armv8.0 >/dev/null 2>&1 && dpkg-deb -c fex-emu-armv8.0_*.deb' 2>/dev/null \
        | awk '{print $6}' | grep -E '^\./usr/(lib/aarch64-linux-gnu/fex-emu/HostThunks/lib(GL|vulkan)-host\.so|share/fex-emu/GuestThunks/lib(GL|vulkan)-guest\.so|share/fex-emu/ThunksDB\.json)$' | sort | paste -sd' ' -)
    if [ "$(wc -w <<<"$d")" = 5 ]; then res PASS "$r ($label): PPA package fex-emu-armv8.0 lists the five thunk files at the searched paths"
    else res FAIL "$r ($label): PPA package thunk files not confirmed (${d:-download or listing failed})"; fi
  fi
  run_inst "$R" "$L/remove.log" DELETE --remove --purge; rc=$?
  if [ $rc = 0 ] && grep -q 'done: Steam ARM removed' "$L/remove.log"; then res PASS "$r ($label): --remove --purge completed"
  else res FAIL "$r ($label): --remove --purge rc $rc: $(grep -m1 '\[fail\]' "$L/remove.log" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-200)"; fi
  snap "$R" "$L/after.tsv"
  # Ubuntu PPA stays while FEX stays installed; removal names the command
  grep -q 'sudo add-apt-repository --remove ppa:fex-emu/fex' "$L/remove.log" \
    && keeps+=(--keep '^/etc/apt/(sources\.list\.d/fex-emu-ubuntu-fex-|trusted\.gpg\.d/fex-emu-ubuntu-fex|keyrings/fex-emu)=FEX PPA (add-apt-repository); removal prints its remove command')
  grep -q 'FEX package source:  sudo rm ' "$L/remove.log" \
    && keeps+=(--keep '^/etc/apt/(sources\.list\.d/steam-arm-fex\.sources|keyrings/steam-arm-fex\.gpg)$=FEX source kept while FEX stays installed; removal prints its rm command')
  # real install: packages setup installed stay (removal names them), with what their maintainer scripts made
  if [ -f "$L/pkgs-before.txt" ]; then
    : > "$L/pkgfiles.tsv"
    in_root "$R" dpkg-query -W -f='${Package}\n' 2>/dev/null | sort | comm -13 "$L/pkgs-before.txt" - > "$L/pkgs-new.txt"
    [ -s "$L/pkgs-new.txt" ] && in_root "$R" xargs -r dpkg -L < "$L/pkgs-new.txt" 2>/dev/null \
      | awk '/^\//{print $0 "\tdistribution package installed by setup, stays (removal names it)"}' > "$L/pkgfiles.tsv"
    # packages present before whose version changed (dependency upgrades of apt-get install): their files stay too
    in_root "$R" dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | sort | comm -13 "$L/pkgver-before.txt" - | cut -d' ' -f1 | sort \
      | comm -12 - "$L/pkgs-before.txt" > "$L/pkgs-upgraded.txt"
    [ -s "$L/pkgs-upgraded.txt" ] && in_root "$R" xargs -r dpkg -L < "$L/pkgs-upgraded.txt" 2>/dev/null \
      | awk '/^\//{print $0 "\tdistribution package upgraded by setup'"'"'s apt-get install, stays"}' >> "$L/pkgfiles.tsv"
    keeps+=(--keep-list "$L/pkgfiles.tsv"
      --keep '__pycache__(/|$)|^/etc/alternatives/|^/var/lib/|^/etc/(passwd|group|shadow|gshadow|subuid|subgid)-?$|^/etc/ssl/certs/|^/usr/share/mime/|^/usr/.*\.cache$|gschemas\.compiled$|^/etc/systemd/(?!.*steam-arm)|^/etc/dbus-1/|^/etc/rc[0-6S]\.d/|^/etc/fonts/conf\.d/|^/var/cache/fontconfig(/|$)|^/usr/local/share/fonts$|^/usr/share/icons/default/index\.theme$|^/etc/(nsswitch\.conf|pam\.d/common-)|^/usr/lib/udev/hwdb\.bin$|^/usr/bin/pinentry$=written by maintainer scripts and triggers of installed packages (init links, fontconfig, pam-auth-update, nss, hwdb, alternatives)'
      --keep '^/root/\.launchpadlib(/|$)=add-apt-repository cache; removal names it')
  fi
  d=$(python3 -I "$TREE" diff "$L/before.tsv" "$L/after.tsv" --purge --removal "$REMOVAL" --home "/home/$GAMEUSER" "${keeps[@]}" --count -v 2>&1); rc=$?
  printf '%s\n' "$d" > "$L/diff.txt"
  if [ $rc = 0 ]; then res PASS "$r ($label): tree after --remove --purge = before ($(printf '%s\n' "$d" | grep -c '\[kept:') kept by reason)"
  else res FAIL "$r ($label): left after --remove --purge: $(printf '%s\n' "$d" | grep -v '\[kept:' | sed -n '2,8p' | sed 's/  */ /g' | tr '\n' ';')"; fi
}

rows_sel(){ if [ ${#SEL[@]} -gt 0 ]; then printf '%s\n' "${SEL[@]}"; else printf '%s\n' "$ROWS" | cut -d'|' -f1; fi; }
case $ACTION in
  list) printf '%s\n' "$ROWS" | awk -F'|' '{printf "%-14s %-10s %s\n", $1, $2, $4}'; exit 0;;
  clean) nsrm "$CACHE/run"; nsrm "$CACHE/prep"; echo "removed run and prepared trees in $CACHE (images kept)"; exit 0;;
  lock)
    t=$(mktemp); { sed -n '1p' "$LOCK"; echo "# resolved $(date -u +%F)"
      awk '!/^#/ && NF == 3 {print $1, $2}' "$LOCK" | while read -r i a; do echo "$i $a $(python3 -I "$FETCH" resolve "$i" "$a")"; done; } > "$t" \
      && mv "$t" "$LOCK" && echo "lock refreshed: $LOCK"; exit $?;;
  prepare) for r in $(rows_sel); do why=$(prepare "$r"); rc=$?; echo "$r: $([ $rc = 0 ] && echo ready || echo "failed ${why:-}")"; done; exit 0;;
esac
[ -f "$INST" ] || { echo "SKIP distro-matrix: installer not found ($INST); set SARM_INST"; exit 0; }
command -v unshare >/dev/null && unshare --map-root-user true 2>/dev/null \
  || { echo "SKIP distro-matrix $BACKEND: unprivileged user namespaces not available here"; exit 0; }
t0=$(date +%s)
[ $BACKEND = qemu ] && ! can_exec arm64 && echo "distro-matrix qemu: arm64 rows need $EXEC_HINT"
for r in $(rows_sel); do row "$r"; done
echo "distro-matrix $BACKEND ($HOSTARCH host): $OUTP pass, $OUTF fail, $OUTS skip, $(( $(date +%s) - t0 )) s; logs in $CACHE/logs"
[ "$OUTF" = 0 ]
