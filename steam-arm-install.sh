#!/bin/bash
# steam-arm-setup: install the native ARM64 Steam client on an ARM64 system with a
# working Vulkan driver. The client runs on the GPU as an ARM program; x86 games run through the
# emulation tool the client downloads, against the x86-64 RootFS this installer prepares, with
# OpenGL and Vulkan forwarded to the native drivers. Windows titles run through the ARM64
# Proton build the client downloads. Remote Play runs the package's x86-64 streaming client
# under the system emulator with software decoding.
#
# Run as root:  sudo steam-arm-setup
# Then launch:  steam-arm   (as the desktop user, from the menu entry or a terminal)
# The first start downloads the client package and restarts itself; sign in from Big Picture.
#
# The core is always installed: host packages, RootFS and graphics provider, client package,
# launcher. Optional components (all on by default):
#   glx-lax     private Mesa GLX copy for titles that bind one GL context from several threads
#   vk-spoof    host Vulkan layer that reports features DXVK requires but the driver lacks
#   map-count   raise vm.max_map_count to the SteamOS value
#   xpad-dedup  udev rule that drops the duplicate joystick some third-party Xbox pads expose
#   pad-hidraw  hidraw access for game controllers, so the client can read a pad directly
#   pad-xbox    present XInput pads from other makers as Xbox 360 pads (off: the client does it)
#   desktop     application menu entry and desktop icon for the game user
# Options: --defaults | --select a,b,c | --skip a,b | --list | --help (same meaning as in
# steam-arm-install.sh). A component deselected on a re-run is removed again.
#
# Coexists with the x86 client installed by steam-arm-install.sh: the ARM client keeps its
# own home directory (ARMHOME_DIR in /etc/steam-arm/steam-arm.conf, default .local/share/steam-arm
# under the game user's home) and its own library. Idempotent; re-running refreshes every file.
# Experimental: not part of the shipped image.
set -u
# Header. Self-contained on purpose: this script also ships on its own, where the board's
# banner helper does not exist, and the header should not name a board either way. TTY gated,
# NO_COLOR honoured, because the same script runs from units where escape codes are noise.
steam_banner() {
    [ -t 1 ] || return 0
    local C=$'\033[96m' D=$'\033[2m' B=$'\033[1m' X=$'\033[0m'
    [ -n "${NO_COLOR:-}" ] && { C=; D=; B=; X=; }
    local line; line=$(printf '\u2500%.0s' $(seq 1 62))
    printf '\n%s  %s%s\n' "$D" "$line" "$X"
    printf '%s   %s%s\n' "${C}${B}" "$1" "$X"
    printf '%s   %s%s\n' "$D" "$2" "$X"
    printf '%s  %s%s\n\n' "$D" "$line" "$X"
}

# The account the client installs into. Default: the desktop account already on the box,
# which is the first regular login (uid 1000) on an image whose desktop was added on demand.
# Set GAMEUSER to choose another. Only when no regular account exists at all is one created,
# and then its password is generated and printed rather than being a value published in this
# script for every box that runs it.
GAMEUSER="${GAMEUSER:-$(getent passwd 1000 2>/dev/null | cut -d: -f1)}"
GAMEUSER="${GAMEUSER:-steamarm}"
GAMEPASS="${GAMEPASS:-}"
# The client's own Steam Input re-identifies pads here, so the uinput service is off unless asked
# for; the launcher pauses it while the client runs in case another route enabled it.
DEFAULT_OFF="${DEFAULT_OFF:-pad-xbox}"
ARMHOME_DIR="${ARMHOME_DIR:-.local/share/steam-arm}"
RFS=/opt/fex-rootfs/Ubuntu_24_04
FEXPPA="ppa:fex-emu/fex"
MANIFEST=https://client-update.fastly.steamstatic.com/steam_client_publicbeta_linuxarm64
CDN=https://client-update.steamstatic.com
say(){ printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[fail]\033[0m %s\n' "$*"; exit 1; }
# ---------------------------------------------------------------------------
COMPONENTS="glx-lax vk-spoof map-count xpad-dedup pad-hidraw pad-xbox desktop"
desc_of(){ case "$1" in
  glx-lax)    echo "Private Mesa GLX copy: GL context bound from several threads (Hotline Miami 2)";;
  vk-spoof)   echo "Vulkan feature layer: DXVK device on the Mali driver (Proton titles)";;
  map-count)  echo "vm.max_map_count raised to the SteamOS value (Proton warns below it)";;
  xpad-dedup) echo "Drop the duplicate joystick node of third-party Xbox 360 style pads";;
  pad-hidraw) echo "Let the client read pads directly, for rumble and battery level";;
  pad-xbox)   echo "Present XInput pads from other makers as Xbox 360 pads (the client does this itself)";;
  desktop)    echo "Application menu entry and desktop icon for the game user";;
esac; }
var_of(){ echo "OPT_$(echo "$1" | tr 'a-z-' 'A-Z_')"; }
for c in $COMPONENTS; do eval "$(var_of "$c")=1"; done
# Components that are off unless asked for. The pad re-identification service grabs the
# physical pad, which starves a title that opens the pad itself, so it is opt-in.
for c in ${DEFAULT_OFF:-}; do eval "$(var_of "$c")=0"; done
MODE=ask
while [ $# -gt 0 ]; do
  case "$1" in
    --defaults) MODE=defaults;;
    --select)   MODE=select; SEL="${2:-}"; shift;;
    --select=*) MODE=select; SEL="${1#*=}";;
    --skip)     MODE=skip; SEL="${2:-}"; shift;;
    --skip=*)   MODE=skip; SEL="${1#*=}";;
    --list)     for c in $COMPONENTS; do printf '  %-11s %s\n' "$c" "$(desc_of "$c")"; done; exit 0;;
    -h|--help)  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "unknown option: $1 (see --help)";;
  esac; shift
done
known(){ for c in $COMPONENTS; do [ "$c" = "$1" ] && return 0; done; return 1; }
case "$MODE" in
  select) for c in $COMPONENTS; do eval "$(var_of "$c")=0"; done
          for c in $(echo "$SEL" | tr ',' ' '); do known "$c" || die "unknown component: $c"; eval "$(var_of "$c")=1"; done;;
  skip)   for c in $(echo "$SEL" | tr ',' ' '); do known "$c" || die "unknown component: $c"; eval "$(var_of "$c")=0"; done;;
  ask)    if [ -t 0 ] && [ -t 1 ]; then
            # The picker is keyboard driven: whiptail draws the buttons, it does not take a
            # mouse. Say so, and name the flags that skip the picker for anyone who would
            # rather not meet it at all.
            printf '\n  Components: --defaults takes the recommended set, --select a,b takes exactly\n'
            printf '  those, --skip a,b takes the defaults without them, --list prints them all.\n\n'
            if command -v whiptail >/dev/null 2>&1; then
              args=(); for c in $COMPONENTS; do
                args+=("$c" "$(desc_of "$c")" "$(eval "[ \"\$$(var_of "$c")\" = 1 ]" && echo ON || echo OFF)")
              done
              chosen=$(whiptail --title "Native ARM64 Steam" --checklist "Optional components.\n\nSPACE toggles the item under the cursor.  TAB moves to the buttons.  ENTER confirms.\nThis list is keyboard driven; a mouse click does nothing." 22 92 6 "${args[@]}" 3>&1 1>&2 2>&3) || die "cancelled"
              for c in $COMPONENTS; do eval "$(var_of "$c")=0"; done
              for c in $chosen; do c=${c//\"/}; eval "$(var_of "$c")=1"; done
            else
              for c in $COMPONENTS; do
                if eval "[ \"\$$(var_of "$c")\" = 1 ]"; then
                  printf '  %-11s %s [Y/n] ' "$c" "$(desc_of "$c")"; read -r a
                  case "$a" in n|N) eval "$(var_of "$c")=0";; esac
                else
                  printf '  %-11s %s [y/N] ' "$c" "$(desc_of "$c")"; read -r a
                  case "$a" in y|Y) eval "$(var_of "$c")=1";; esac
                fi
              done
            fi
          fi;;
esac
opt(){ eval "[ \"\$$(var_of "$1")\" = 1 ]"; }
[ "$(id -u)" = 0 ] || die "run as root"

# wait for any boot-time apt/dpkg (unattended-upgrades, armbian online-extras) to release the lock
wait_apt(){
  local n=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
    [ $n = 0 ] && warn "another apt/dpkg is running; waiting for the lock..."
    sleep 5; n=$((n+5)); [ $n -ge 600 ] && die "dpkg lock still held after 10 min"
  done
}

# ---------------------------------------------------------------------------
steam_banner "Native ARM64 Steam client setup" \
             "Valve's ARM Linux client, x86 titles through the emulation tool it downloads"
printf 'Optional components:'; for c in $COMPONENTS; do opt "$c" && printf ' %s' "$c" || printf ' [no %s]' "$c"; done; echo
say "1/11  host packages"
export DEBIAN_FRONTEND=noninteractive
wait_apt
# The system emulator (FEX) serves Remote Play (x86-64 streaming client) and the thunk
# libraries the RootFS configuration points at; the client's own emulation tool ships its own.
if ! command -v FEX >/dev/null 2>&1; then
  command -v add-apt-repository >/dev/null || apt-get install -y software-properties-common
  grep -rq "fex-emu/fex" /etc/apt/sources.list.d/ 2>/dev/null || add-apt-repository -y "$FEXPPA"
fi
wait_apt; apt-get update -y
BUILDPKGS=""; opt vk-spoof && BUILDPKGS="gcc libc6-dev libvulkan-dev"
opt glx-lax && BUILDPKGS="$BUILDPKGS patchelf"
opt desktop && BUILDPKGS="$BUILDPKGS python3-pil gir1.2-ayatanaappindicator3-0.1"   # inverted menu icon; tray helper binding
wait_apt; apt-get install -y fex-emu-armv8.2 fex-emu-binfmt32 fex-emu-binfmt64 bubblewrap dbus-daemon xz-utils \
  libsdl3-0 libsdl3-image0 libsdl3-ttf0 libgtk2.0-0t64 libopenal1 zenity xdotool curl python3 file $BUILDPKGS
command -v FEX >/dev/null || die "FEX did not install"
for l in libSDL3.so.0 libopenal.so.1 libgtk-x11-2.0.so.0; do ldconfig -p | grep -q "$l" || die "$l missing after install"; done
# FEX owns x86 execution (box64/box32 binfmt off), persistent
echo 0 > /proc/sys/fs/binfmt_misc/box64 2>/dev/null || true
echo 0 > /proc/sys/fs/binfmt_misc/box32 2>/dev/null || true
if [ ! -f /etc/systemd/system/steam-arm-fex-binfmt.service ]; then
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
fi

# ---------------------------------------------------------------------------
say "2/11  game user '$GAMEUSER', /dev/shm, kernel limits"
if ! id "$GAMEUSER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G video,render,input,audio "$GAMEUSER"
  if [ -z "$GAMEPASS" ]; then
    GAMEPASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 14)
    say "     created account '$GAMEUSER' with password: $GAMEPASS"
    say "     write it down now; change it with: passwd $GAMEUSER"
  fi
  echo "$GAMEUSER:$GAMEPASS" | chpasswd
fi
for g in video render input audio; do usermod -aG "$g" "$GAMEUSER" 2>/dev/null; done
loginctl enable-linger "$GAMEUSER" >/dev/null 2>&1 || true
UID_N=$(id -u "$GAMEUSER"); UHOME=$(getent passwd "$GAMEUSER" | cut -d: -f6)
ARMHOME="$UHOME/$ARMHOME_DIR"
if ! mountpoint -q /dev/shm || [ "$(stat -c %a /dev/shm)" != 1777 ]; then
  mountpoint -q /dev/shm && umount /dev/shm 2>/dev/null
  mount -t tmpfs -o rw,nosuid,nodev,mode=1777 tmpfs /dev/shm; chmod 1777 /dev/shm
fi
grep -q '[[:space:]]/dev/shm[[:space:]]' /etc/fstab || echo 'tmpfs /dev/shm tmpfs rw,nosuid,nodev,mode=1777 0 0' >> /etc/fstab
# The file is named zz- for the same reason zz-steam-arm-tune.conf is: systemd-sysctl applies
# /etc/sysctl.d in filename order and /etc/sysctl.conf is linked in as 99-sysctl.conf, so a
# 99- drop-in is read first and the 262144 in /etc/sysctl.conf wins at every boot.
if opt map-count; then
  rm -f /etc/sysctl.d/99-steam-arm.conf
  printf 'vm.max_map_count = 2147483642\n' > /etc/sysctl.d/zz-steam-arm.conf
  sysctl -q -p /etc/sysctl.d/zz-steam-arm.conf 2>/dev/null || true
else
  rm -f /etc/sysctl.d/99-steam-arm.conf /etc/sysctl.d/zz-steam-arm.conf
  sysctl -q -w vm.max_map_count=65530 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
say "3/11  x86-64 RootFS (graphics provider) + emulator configuration"
# The client's emulation tool needs an x86-64 root with Mesa in it (the "graphics provider");
# the same Ubuntu 24.04 RootFS the x86 client installer uses, fetched with FEXRootFSFetcher.
if [ ! -d "$RFS" ]; then
  SRC=$(find /root/.fex-emu/RootFS /root/.local/share/fex-emu/RootFS -maxdepth 1 -name Ubuntu_24_04 -type d 2>/dev/null | head -1)
  if [ -z "$SRC" ]; then
    ( cd /opt 2>/dev/null; env -u DISPLAY FEXRootFSFetcher -y -x --force-ui=tty --distro-name=ubuntu --distro-version=24.04 )
    SRC=$(find /root/.fex-emu/RootFS /root/.local/share/fex-emu/RootFS -maxdepth 1 -name Ubuntu_24_04 -type d 2>/dev/null | head -1)
  fi
  [ -n "$SRC" ] || die "RootFS fetch failed"
  mkdir -p /opt/fex-rootfs && mv "$SRC" "$RFS"
fi
chmod o+rx /opt /opt/fex-rootfs "$RFS"
[ -f "$RFS/usr/lib/x86_64-linux-gnu/libGL.so.1" ] || warn "RootFS carries no x86-64 libGL; games will not reach the GPU"
# Steam Linux Runtime takes the emulation path only when this manifest exists; its directory
# is the RootFS. The tool's built-in default path is a SteamOS location, provided as a link.
cat > "$RFS/graphics_provider.json" <<'JSON'
{
  "graphics_provider_v0": {
    "architectures": ["x86_64-linux-gnu", "i386-linux-gnu"]
  }
}
JSON
chmod 644 "$RFS/graphics_provider.json"
mkdir -p /usr/share/guestos && ln -sfn "$RFS" /usr/share/guestos/fex-mesa
# System emulator configuration for the game user (Remote Play streaming client). HostEnv is
# applied to the host side of every FEX process only: the first entry selects the GLX copy of
# step 4, the second keeps the host Vulkan loader on the system layer directory inside runtime
# containers (step 5). FEX takes one value per key; repeated keys are accepted, an array is not.
FEXEXTRA=",
  \"Multiblock\":\"1\""
opt glx-lax   && FEXEXTRA="$FEXEXTRA,
  \"HostEnv\":\"__GLX_VENDOR_LIBRARY_NAME=steamarmlax\""
opt vk-spoof  && FEXEXTRA="$FEXEXTRA,
  \"HostEnv\":\"VK_IMPLICIT_LAYER_PATH=/usr/share/vulkan/implicit_layer.d\""
install -d -o "$GAMEUSER" -g "$GAMEUSER" "$UHOME/.fex-emu"
cat > "$UHOME/.fex-emu/Config.json" <<JSON
{ "Config": { "RootFS":"$RFS",
  "ThunkHostLibs":"/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks/",
  "ThunkGuestLibs":"/usr/share/fex-emu/GuestThunks/",
  "ThunkConfig":"/usr/share/fex-emu/ThunksDB.json"$FEXEXTRA },
  "ThunksDB":{"GL":1,"Vulkan":1} }
JSON
chown "$GAMEUSER:$GAMEUSER" "$UHOME/.fex-emu/Config.json"
rm -f "$ARMHOME/.fex-emu/Config.json" 2>/dev/null   # the launcher copies the fresh one

# ---------------------------------------------------------------------------
if opt glx-lax; then
say "4/11  GL context binding across threads (private Mesa GLX copy)"
# Some Linux game ports bind one GL context from the main thread, then from a loader thread,
# then from a render thread, and never release it in between (Hotline Miami 2 does this).
# Mesa's GLX client refuses a context that is current in another thread with BadAccess, the
# bind fails, the game draws with no context and crashes (a blank window for a moment, then
# exit). The thunk hands glXMakeCurrent to the native Mesa, so the check runs on the host.
# Fix: a private copy of the native libGLX_mesa with that one branch replaced by a no-op,
# installed under the glvnd vendor name "steamarmlax". The FEX HostEnv setting in step 4 selects it
# for the host side of FEX processes only. System Mesa and every native program are untouched.
# The helper rebuilds the copy when the system library changes (package update) and falls
# back to an unpatched copy if the instruction pattern is not found, so the vendor name
# always resolves.
cat > /usr/local/lib/steam-arm-glx-lax-patch.py <<'PYEOF'
#!/usr/bin/env python3
# Build a copy of the Mesa GLX client library in which MakeContextCurrent no longer refuses a
# context that is current in another thread. Usage: steam-arm-glx-lax-patch.py <libGLX_mesa.so.0> <out>
# The check compiles (aarch64) to:  ldr xA, [xG, #256]   ; gc->currentDpy
#                                   cbnz xA, <send BadAccess>
#                                   ldr xB, [xG, #40]    ; gc->vtable
# The cbnz becomes nop. Exactly one match is required; otherwise nothing is written (exit 1).
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
# Keep /usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0 in step with the system Mesa GLX library.
# Rebuilds only when the system library's checksum changes. Run by the installer and by steam-fex / steam-arm.
SRC=$(realpath /usr/lib/aarch64-linux-gnu/libGLX_mesa.so.0 2>/dev/null) || exit 0
[ -f "$SRC" ] || exit 0
OUT=/usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0
STAMP=/usr/local/lib/steam-arm-glx-lax.src
SUM=$(sha256sum "$SRC" | cut -c1-64)
[ -f "$OUT" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$SUM" ] && [ "$(patchelf --print-soname "$OUT" 2>/dev/null)" = libGLX_steamarmlax.so.0 ] && exit 0
T=$(mktemp "$OUT.XXXXXX") || exit 1
if python3 /usr/local/lib/steam-arm-glx-lax-patch.py "$SRC" "$T" >/dev/null 2>&1; then
  echo "steam-arm-glx-lax: patched copy built from $(basename "$SRC")"
else
  cp -f "$SRC" "$T"
  echo "steam-arm-glx-lax: pattern not found in $(basename "$SRC"); vendor library is an unpatched copy" >&2
fi
# Own SONAME and a loader cache entry: the Steam Linux Runtime container copies host GLX vendor
# libraries by SONAME pattern, so the copy reaches games run through the native Steam client too.
command -v patchelf >/dev/null && patchelf --set-soname libGLX_steamarmlax.so.0 "$T"
chmod 644 "$T" && mv -f "$T" "$OUT" && echo "$SUM" > "$STAMP" && ldconfig
GLX
chmod 755 /usr/local/sbin/steam-arm-glx-lax
/usr/local/sbin/steam-arm-glx-lax
[ -f /usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0 ] && echo "  libGLX_steamarmlax.so.0 ready" || echo "  [warn] no native libGLX_mesa found; lax GLX copy skipped"
else
say "4/11  private Mesa GLX copy: not selected"
rm -f /usr/lib/aarch64-linux-gnu/libGLX_steamarmlax.so.0 /usr/local/sbin/steam-arm-glx-lax /usr/local/lib/steam-arm-glx-lax-patch.py /usr/local/lib/steam-arm-glx-lax.src
fi

# ---------------------------------------------------------------------------
if opt vk-spoof; then
say "5/11  Vulkan feature layer for Proton titles (DXVK on the Mali driver)"
# Windows titles run through Proton, whose Direct3D layer (DXVK) lists Vulkan device features
# as mandatory that the Mali driver (panvk) does not expose: fillModeNonSolid, geometryShader,
# multiViewport, shaderClipDistance, shaderCullDistance, robustBufferAccess2. DXVK then finds no
# adapter and the title exits. This host-side implicit layer reports those six as supported and
# removes them again from vkCreateDevice, so the driver never sees them enabled. Titles that use
# none of them (2D and simple 3D) run; a title that does use one misrenders or fails pipeline
# creation instead of failing at start. Enabled by STEAM_ARM_VK_SPOOF=1 (set by the launcher); a
# title can opt out with STEAM_ARM_VK_SPOOF_DISABLE=1 in its launch options. The layer reaches the
# thunk's host Vulkan loader inside Steam runtime containers through the HostEnv entry in step 3; pressure-vessel imports host implicit layers into runtime containers by itself.
cat > /usr/local/lib/steam-arm-vk-spoof.c <<'CEOF'
/* VK_LAYER_STEAM_ARM_feature_spoof: report a fixed set of VkPhysicalDeviceFeatures as supported and strip
 * them again from vkCreateDevice so the driver never sees them enabled. */
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
typedef struct { void *key; PFN_vkGetDeviceProcAddr gdpa; PFN_vkDestroyDevice destroy; } dev_t_;
static inst_t insts[MAX_INST]; static dev_t_ devs[MAX_DEV]; static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int dbg;

static void *key_of(const void *h) { return *(void **)h; }
static inst_t *inst_find(const void *h) { void *k = key_of(h); for (int i = 0; i < MAX_INST; i++) if (insts[i].key == k) return &insts[i]; return NULL; }
static dev_t_ *dev_find(const void *h) { void *k = key_of(h); for (int i = 0; i < MAX_DEV; i++) if (devs[i].key == k) return &devs[i]; return NULL; }

static void spoof_features(VkPhysicalDeviceFeatures *f) {
  f->fillModeNonSolid = VK_TRUE; f->geometryShader = VK_TRUE; f->multiViewport = VK_TRUE;
  f->shaderClipDistance = VK_TRUE; f->shaderCullDistance = VK_TRUE;
}
static void unspoof_features(VkPhysicalDeviceFeatures *f, const VkPhysicalDeviceFeatures *real) {
  f->fillModeNonSolid = real->fillModeNonSolid; f->geometryShader = real->geometryShader; f->multiViewport = real->multiViewport;
  f->shaderClipDistance = real->shaderClipDistance; f->shaderCullDistance = real->shaderCullDistance;
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
      r2 = *(VkPhysicalDeviceRobustness2FeaturesEXT *)p; r2.robustBufferAccess2 = VK_FALSE; prev->pNext = (VkBaseOutStructure *)&r2; prev = (VkBaseOutStructure *)&r2; have_r2 = 1;
    } else prev = p;
  }
  ci2.pNext = head.pNext;
  VkResult r = in->create_device(pd, &ci2, ac, dev);
  if (dbg) fprintf(stderr, "[steam-arm-vk-spoof] vkCreateDevice -> %d (features2 %d, robustness2 %d)\n", r, have_f2, have_r2);
  if (r != VK_SUCCESS) return r;
  pthread_mutex_lock(&lock);
  for (int i = 0; i < MAX_DEV; i++) if (!devs[i].key) { devs[i].key = key_of(*dev); devs[i].gdpa = gdpa; devs[i].destroy = (PFN_vkDestroyDevice)gdpa(*dev, "vkDestroyDevice"); break; }
  pthread_mutex_unlock(&lock);
  return VK_SUCCESS;
}
static VKAPI_ATTR void VKAPI_CALL layer_DestroyDevice(VkDevice dev, const VkAllocationCallbacks *ac) {
  dev_t_ *d = dev_find(dev); PFN_vkDestroyDevice f = d->destroy;
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
    "description": "Reports fillModeNonSolid, geometryShader, multiViewport, shaderClipDistance, shaderCullDistance and robustBufferAccess2 as supported and strips them from device creation",
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
# Some third-party Xbox 360 style pads expose a headset interface (vendor class ff/5d,
# protocol 3) that the xpad driver also binds, so one pad appears as two identical
# joysticks and a two-player game hands player 2 a copy of player 1. The rule unbinds
# xpad from that interface on plug-in; the script does the same for pads already up.
cat > /usr/local/sbin/steam-arm-xpad-dedup <<'DEDUP'
#!/bin/sh
# Some third-party Xbox 360 style pads expose their headset interface (vendor class ff/5d,
# protocol 3) in a way the xpad driver also binds, so one pad appears as two identical joysticks
# and games hand player 2 a copy of player 1. Unbind xpad from every such interface. Idempotent;
# run by udev on plug-in and at boot, safe to run by hand.
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
# Third-party Xbox 360 style pads: drop the second xpad binding on the headset interface (see steam-arm-xpad-dedup).
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
# The client runs as the desktop user and reads a pad over /dev/hidraw*, which the kernel
# creates as root only. The rules that hand those nodes to the logged-in user ship in Valve's
# steam-devices package and list the pads Valve wrote drivers for: a pad from any other maker
# stays unreadable, the client's HID path fails to open it and logs a read failure, and the
# pad is left on the generic event device with no rumble and no battery level.
#
# These ids come from xpad_device[] in the kernel source, so they are the pads this kernel
# binds as Xbox compatible. Each is matched on vendor AND product, because several makers in
# that table also make keyboards and mice and a vendor-wide rule would hand the user raw HID
# access to those too. Regenerate with gen-gamepad-hidraw-rules.py.
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
2563:058d 2dc8:2000 2dc8:310a 2e24:0652 31e3:1100 31e3:1200 31e3:1210
31e3:1220 31e3:1300 31e3:1310 3285:0607 3767:0101
"
{
  echo "# Hand the logged-in user the hidraw node of a game controller."
  echo "# Written by the Steam installer. uaccess grants the access to whoever holds the"
  echo "# active local seat, the same way it is granted for a keyboard or a sound card."
  for id in $PAD_IDS; do
    v=${id%:*}; p=${id#*:}
    u=$(printf '%s:%s' "$v" "$p" | tr 'a-f' 'A-F')
    echo "KERNEL==\"hidraw*\", ATTRS{idVendor}==\"$v\", ATTRS{idProduct}==\"$p\", MODE=\"0660\", TAG+=\"uaccess\""
    echo "KERNEL==\"hidraw*\", KERNELS==\"*$u*\", MODE=\"0660\", TAG+=\"uaccess\""
  done
  echo "# Pads that speak HID rather than going through xpad"
  for v in 054c 057e 28de; do
    u=$(printf '%s' "$v" | tr 'a-f' 'A-F')
    echo "KERNEL==\"hidraw*\", ATTRS{idVendor}==\"$v\", MODE=\"0660\", TAG+=\"uaccess\""
    echo "KERNEL==\"hidraw*\", KERNELS==\"*$u:*\", MODE=\"0660\", TAG+=\"uaccess\""
  done
  echo "# The client also creates its virtual controller through /dev/uinput."
  echo "KERNEL==\"uinput\", SUBSYSTEM==\"misc\", MODE=\"0660\", TAG+=\"uaccess\", OPTIONS+=\"static_node=uinput\""
} > /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules
chmod 644 /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules
udevadm control --reload 2>/dev/null
udevadm trigger --subsystem-match=hidraw --subsystem-match=misc 2>/dev/null
udevadm settle 2>/dev/null
n=$(grep -c '^KERNEL=="hidraw\*", ATTRS' /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules)
say "     $n pads covered"
else
say "7/11  controller access: not selected"
rm -f /etc/udev/rules.d/60-steam-arm-gamepad-hidraw.rules; udevadm control --reload 2>/dev/null
fi

# ---------------------------------------------------------------------------
if opt pad-xbox; then
say "8/11  pads from other makers presented as Xbox 360 pads"
# Engines that identify a controller by its USB vendor and product ID (Rewired, InControl,
# older SDL, Wine's XInput) ignore a pad whose IDs they carry no profile for, even when the
# kernel drives it as an Xbox pad. This service re-emits every non-Microsoft xpad device
# through uinput with the Xbox 360 pad IDs. The physical node is grabbed so nothing sees the
# pad twice, which also means a title that opens the pad node itself gets nothing: leave this
# off for those, or stop the service while they run.
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
say "9/11  client package (publicbeta, linuxarm64) into $ARMHOME"
S="$ARMHOME/.local/share/Steam"; D="$S/steamrtarm64"
install -d -o "$GAMEUSER" -g "$GAMEUSER" "$ARMHOME" "$ARMHOME/.local" "$ARMHOME/.local/share" "$S"
if [ -x "$D/steam" ] && file -b "$D/steam" | grep -q aarch64; then
  echo "  client present ($(cat "$D/builddate.txt" 2>/dev/null | head -1)); keeping it (the client updates itself)"
else
  TMPZ=$(mktemp /tmp/steam-arm64.XXXXXX.zip)
  curl -fsSL -o "$TMPZ.manifest" "$MANIFEST" || die "client manifest download failed"
  ENTRY=$(strings "$TMPZ.manifest" | grep -oE 'bins_linuxarm64_linuxarm64\.zip\.[0-9a-f]+' | grep -v '\.vz\.' | head -1)
  [ -n "$ENTRY" ] || die "no linuxarm64 package entry in the client manifest"
  echo "  package $ENTRY"
  curl -fL --progress-bar -o "$TMPZ" "$CDN/$ENTRY" || die "client package download failed"
  rm -rf "$D"
  # the archive carries the steamrtarm64/ prefix and uses backslash separators; unzip would
  # create literal backslash names
  python3 - "$TMPZ" "$S" <<'PY'
import os, sys, zipfile
zpath, root = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(zpath); n = 0
for i in z.infolist():
    name = i.filename.replace("\\", "/")
    if name.endswith("/") or ".." in name.split("/"): continue
    dst = os.path.join(root, name); os.makedirs(os.path.dirname(dst), exist_ok=True)
    with z.open(i) as src, open(dst, "wb") as out: out.write(src.read())
    mode = i.external_attr >> 16
    if mode: os.chmod(dst, mode)
    n += 1
print("  extracted %d files" % n)
PY
  rm -f "$TMPZ" "$TMPZ.manifest"
  # the archive carries no unix modes; mark programs and scripts executable
  find "$D" -type f | while read -r f; do file -b "$f" | grep -qE 'executable|shell script' && chmod 755 "$f"; done
  chown -R "$GAMEUSER:$GAMEUSER" "$D"
  [ -x "$D/steam" ] || die "client binary missing after extraction"
fi
# package channel at the data directory level (a copy under steamrtarm64 selects the generic client)
install -d -o "$GAMEUSER" -g "$GAMEUSER" "$S/package"; echo publicbeta > "$S/package/beta"
# the -deckard client reads a VR runtime registry; an empty one keeps it quiet
install -d -o "$GAMEUSER" -g "$GAMEUSER" "$ARMHOME/.config" "$ARMHOME/.config/openvr"
[ -f "$ARMHOME/.config/openvr/openvrpaths.vrpath" ] || cat > "$ARMHOME/.config/openvr/openvrpaths.vrpath" <<'JSON'
{
  "config": [],
  "external_drivers": null,
  "jsonid": "vrpathreg",
  "log": [],
  "runtime": [],
  "version": 1
}
JSON
chown -R "$GAMEUSER:$GAMEUSER" "$ARMHOME"

# ---------------------------------------------------------------------------
say "10/11  launcher, configuration, menu entry"
mkdir -p /etc/steam-arm
printf 'ARMHOME_DIR=%s\n' "$ARMHOME_DIR" > /etc/steam-arm/steam-arm.conf
cat > /usr/local/bin/steam-arm <<'LAUNCHER'
#!/bin/sh
# steam-arm: start the native ARM64 Steam client (Big Picture). Installed by
# steam-arm-install.sh; /etc/steam-arm/steam-arm.conf can set ARMHOME_DIR.
# Runs as the desktop user, no root needed. The client lives in its own home so the x86 install is
# untouched. Games run through Valve's FEX compatibility tool (downloaded by the client) against the
# x86-64 RootFS this build ships; graphics reach the Mali through the FEX GL and Vulkan thunks.
# Everything the client package lacks on a non-SteamOS, non-VR box is re-applied at each start,
# because the client re-verifies its files on update.
REALHOME="$HOME"
ARMHOME_DIR=.local/share/steam-arm            # relative to the user's home
[ -r /etc/steam-arm/steam-arm.conf ] && . /etc/steam-arm/steam-arm.conf
ARMHOME="${STEAM_ARM_HOME:-$REALHOME/$ARMHOME_DIR}"
export HOME="$ARMHOME"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export STEAM_COMPAT_GRAPHICS_PROVIDER=/opt/fex-rootfs/Ubuntu_24_04/graphics_provider.json
export __GLX_VENDOR_LIBRARY_NAME=steamarmlax
export STEAMOS=1
export STEAM_ARM_VK_SPOOF=1
S="$ARMHOME/.local/share/Steam"; D="$S/steamrtarm64"; F="$S/steamapps/common/FEX-Emu"

# The pad re-identification service (steam-arm-pad-xbox) serves the emulated client, where Steam Input's
# virtual pad is silent. It grabs the physical pad, which starves titles that open the pad
# themselves under this client, and Steam Input here re-identifies pads on its own: pause it
# while this client runs and start it again on exit.
PADSVC=0
if systemctl is-active --quiet steam-arm-pad-xbox 2>/dev/null; then
  PADSVC=1; sudo -n systemctl stop steam-arm-pad-xbox 2>/dev/null || systemctl stop steam-arm-pad-xbox 2>/dev/null
fi
restore_pad(){ [ "$PADSVC" = 1 ] && { sudo -n systemctl start steam-arm-pad-xbox 2>/dev/null || systemctl start steam-arm-pad-xbox 2>/dev/null; }; }
trap restore_pad EXIT
if pgrep -f 'ubuntu12_32/steam ' >/dev/null 2>&1; then
  command -v zenity >/dev/null 2>&1 && zenity --warning --text="The x86 Steam client is running. Close it first; two clients fight over the controller and steam:// links." 2>/dev/null
fi

# --- client-side links the x86 steam.sh would normally create ---------------------------------
mkdir -p "$ARMHOME/.steam"
ln -sfn "$S" "$ARMHOME/.steam/steam"; ln -sfn "$S" "$ARMHOME/.steam/root"
ln -sfn "$S/linux32" "$ARMHOME/.steam/sdk32"; ln -sfn "$S/linux64" "$ARMHOME/.steam/sdk64"
ln -sfn "$S/linuxarm64" "$ARMHOME/.steam/sdkarm64"   # sdk dir: steamclient.so for games and Proton, steam-launch-wrapper
ln -sfn "$S/ubuntu12_32" "$ARMHOME/.steam/bin32"; ln -sfn "$S/ubuntu12_64" "$ARMHOME/.steam/bin64"
mkdir -p "$S/package"; [ -f "$S/package/beta" ] || echo publicbeta > "$S/package/beta"

# --- launch wrapper stand-in, used only if the package copy in linuxarm64 is missing --------------
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

# --- Remote Play: the ARM streaming_client decodes only through a V4L2 hardware decoder feeding
# Vulkan, which this kernel does not expose; the x86-64 streaming client from the same package runs
# under FEX with software decoding instead. The -deckard client adds --openvr (segfault with no VR
# runtime); the host-only GLX vendor override must not reach the emulated process. -------------
if [ -f "$D/streaming_client" ] && [ "$(head -c 4 "$D/streaming_client" | tr -d '\177')" = "ELF" ]; then
  mv -f "$D/streaming_client" "$D/streaming_client.real"      # only the real binary is ever moved aside
fi
if [ ! -x "$D/streaming_client" ] || ! grep -q 'x86-64 streaming client' "$D/streaming_client" 2>/dev/null; then
cat > "$D/streaming_client" <<'SH'
#!/bin/sh
# Stand-in: run the x86-64 streaming client from this package under FEX (see steam-arm).
here="$(dirname "$0")"; S="$(dirname "$here")"
set -- $(for a in "$@"; do [ "$a" = "--openvr" ] || printf '%s\n' "$a"; done)
export LD_LIBRARY_PATH="$S/linux64:$S/ubuntu12_64:$S/ubuntu12_32${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
unset __GLX_VENDOR_LIBRARY_NAME
export SDL_VIDEO_X11_FORCE_EGL=0
cd "$S" && exec /usr/bin/FEX "$S/ubuntu12_64/streaming_client" "$@"
SH
chmod 755 "$D/streaming_client"
fi
# system FEX config for the x86 streaming client (same rootfs, thunks and host settings as the x86 stack)
mkdir -p "$ARMHOME/.fex-emu"; [ -f "$ARMHOME/.fex-emu/Config.json" ] || cp -f "$REALHOME/.fex-emu/Config.json" "$ARMHOME/.fex-emu/Config.json" 2>/dev/null

# --- Valve's FEX compatibility tool: rootfs default, thunk overlay paths, socket path, thunks on --
if [ -d "$F" ]; then
  # inside the runtime container the guest opens libGL/libvulkan through pressure-vessel's overrides
  # directory; FEX matches overlay paths on the exact string opened, so those paths must be listed.
  python3 - "$F/usr/share/fex-emu/ThunksDB.json" "$F/ConfigTemplate.json" <<'PY' 2>/dev/null
import json, os, sys
db_p, tpl_p = sys.argv[1], sys.argv[2]
db = json.load(open(db_p)); changed = False
names = {"GL": ["libGL.so", "libGL.so.1", "libGL.so.1.7.0", "libGL.so.1.2.0"], "Vulkan": ["libvulkan.so", "libvulkan.so.1"], "EGL": ["libEGL.so", "libEGL.so.1"]}
for lib, ns in names.items():
    if lib not in db["DB"]: continue
    ov = db["DB"][lib].setdefault("Overlay", [])
    for arch in ("i386-linux-gnu", "x86_64-linux-gnu"):
        for sub in ("", "/aliases"):
            for n in ns:
                p = "/usr/lib/pressure-vessel/overrides/lib/%s%s/%s" % (arch, sub, n)
                if p not in ov: ov.append(p); changed = True
if changed: json.dump(db, open(db_p, "w"), indent=2)
t = json.load(open(tpl_p)); c = t.setdefault("Config", {}); tc = False
sock = "/run/user/%s/steam-arm-fexserver.sock" % os.getuid()
if c.get("ServerSocketPath") != sock: c["ServerSocketPath"] = sock; tc = True
td = t.setdefault("ThunksDB", {})
for k in ("GL", "Vulkan"):
    if td.get(k) != "1": td[k] = "1"; tc = True
if tc: json.dump(t, open(tpl_p, "w"), indent=4)
PY
fi

# --- Remote Play client settings this box requires (see steam-arm-remoteplay) -----------------
# Hardware decoding off and HEVC off, pinned in the account's stored client configuration. The
# streaming client has no hardware decode path here, and advertising one leaves a session on
# the launch screen. Applied before the client starts, since the client rewrites the file on
# exit, and skipped when a client is already up.
if command -v steam-arm-remoteplay >/dev/null 2>&1 && ! pgrep -x steam >/dev/null 2>&1; then
  steam-arm-remoteplay >/dev/null 2>&1
fi

# --- interface: Deck by default, desktop on request ------------------------------------------
# The Deck interface registers no status-notifier item, so the client cannot show an icon in the
# panel tray. Started without -gamepadui the client uses its own status icon, which Plasma picks
# up through xembedsniproxy. Big Picture is still reachable from inside the client.
GPUI=-gamepadui
[ "$STEAM_ARM_UI" = desktop ] && GPUI=
case "$1" in
  --desktop) GPUI=; shift;;
  --bigpicture) GPUI=-gamepadui; shift;;
esac

cd "$D" || exit 1
# The installed archive is the bootstrap subset. On the first start the client must verify its
# files so it downloads the rest of the package set (the SDK directory appears then); it exits
# afterwards, so it is started once more with the flags that skip the verification.
if [ ! -f "$S/linuxarm64/steamclient.so" ]; then
  ./steam -deckard -steamos3 ${GPUI:+"$GPUI"} "$@"
  [ -f "$S/linuxarm64/steamclient.so" ] || exit 1
  ln -sfn "$S/linuxarm64" "$ARMHOME/.steam/sdkarm64"
fi
./steam -deckard -steamos3 ${GPUI:+"$GPUI"} -noverifyfiles -norepairfiles -noshaders "$@"
LAUNCHER
chmod 755 /usr/local/bin/steam-arm
# Remote Play: the client's stored settings default to hardware decoding, which the streaming
# client cannot do on this box. This helper pins hardware decoding off and HEVC off; the
# launcher runs it before each start, and it takes --check to report without changing anything.
cat > /usr/local/bin/steam-arm-remoteplay <<'RPPY'
#!/usr/bin/env python3
"""Pin the Remote Play client settings the native ARM64 Steam client needs on this box.

The client stores its Remote Play settings as a serialized protobuf (CStreamingClientConfig
from steammessages_remoteplay.proto), hex-encoded under "ClientConfig" in the account's
localconfig.vdf. Two of its fields default to values this box cannot honour:

  enable_hardware_decoding (field 7) defaults to true. The streaming client decodes through
  Vulkan Video, which the Mali driver on this box does not provide, so the client advertises
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
import re
import sys

# Field numbers are from the schema embedded in the client; wire type 0 (varint) for bool.
FIELD_HW_DECODE = 7
FIELD_HEVC = 13
KEY_RE = re.compile(r'("ClientConfig"\t\t")([0-9a-f]*)(")')
# The block the client keeps the entry in, one level below the root object. Its closing
# brace is the first "\t}" line after the opening "\t{".
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


def main():
    check = "--check" in sys.argv[1:]
    home = os.environ.get("HOME", os.path.expanduser("~"))
    files = glob.glob(os.path.join(home, ".local/share/Steam/userdata/*/config/localconfig.vdf"))
    if not files:
        print("steam-arm-remoteplay: no localconfig.vdf yet; log the client in once first")
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
            # prove the edit before writing it: the new text must carry exactly one entry, the
            # pinned message, and every original line
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
# the launcher pauses the pad re-identification service (emulated-client component) while it runs
cat > /etc/sudoers.d/steam-arm <<SUDO
$GAMEUSER ALL=(root) NOPASSWD: /usr/bin/systemctl start steam-arm-pad-xbox, /usr/bin/systemctl stop steam-arm-pad-xbox
SUDO
chmod 440 /etc/sudoers.d/steam-arm
# compat tool mapping helper (titles with a Linux build on record but Windows files installed)
cat > /usr/local/lib/steam-arm-compatmap.py <<'PYEOF'
#!/usr/bin/env python3
# Insert or replace a CompatToolMapping entry in Steam's config.vdf (run with Steam closed).
# usage: steam-arm-compatmap.py <config.vdf> <appid> <tool name, e.g. proton_11>
import re, sys, shutil
path, appid, tool = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding="utf-8", errors="surrogateescape").read()

def body(ind):
    return ('{i}\t"{a}"\n{i}\t{{\n{i}\t\t"name"\t\t"{t}"\n{i}\t\t"config"\t\t""\n'
            '{i}\t\t"priority"\t\t"250"\n{i}\t}}\n').format(i=ind, a=appid, t=tool)

m = re.search(r'\n(\t+)"CompatToolMapping"\n\1\{\n', s)
if not m:
    sm = re.search(r'\n(\t+)"Steam"\n\1\{\n', s)
    if not sm:
        print("Software/Valve/Steam block not found", file=sys.stderr); sys.exit(1)
    ind = sm.group(1) + "\t"
    ins = '%s"CompatToolMapping"\n%s{\n%s%s}\n' % (ind, ind, body(ind), ind)
    s = s[:sm.end()] + ins + s[sm.end():]; action = "block created"
else:
    ind = m.group(1); start = m.end(); end = s.find("\n" + ind + "}", start) + 1   # keep the final newline
    block = s[start:end]
    am = re.search(r'^\t+"%s"\n\t+\{\n(?:.*\n)*?\t+\}\n' % re.escape(appid), block, re.M)
    if am:
        block = block[:am.start()] + body(ind) + block[am.end():]; action = "replaced"
    else:
        block = body(ind) + block; action = "inserted"
    s = s[:start] + block + s[end:]
shutil.copy(path, path + ".bak-steam-arm")
open(path, "w", encoding="utf-8", errors="surrogateescape").write(s)
print("CompatToolMapping %s for app %s -> %s" % (action, appid, tool))
PYEOF
cat > /usr/local/bin/steam-arm-compatmap <<CM
#!/bin/sh
# usage: steam-arm-compatmap <appid> <tool>   (tool: proton-stable-arm64, proton_11, proton_experimental; Steam ARM closed)
[ \$# -eq 2 ] || { echo "usage: steam-arm-compatmap <appid> <tool>" >&2; exit 2; }
C=$ARMHOME/.local/share/Steam/config/config.vdf
python3 /usr/local/lib/steam-arm-compatmap.py "\$C" "\$1" "\$2" && chown $GAMEUSER:$GAMEUSER "\$C"
CM
chmod 755 /usr/local/bin/steam-arm-compatmap


if opt desktop; then
cat > /usr/share/applications/steam-arm.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Steam ARM
GenericName=Steam client, native ARM64 (Big Picture)
Comment=Native ARM64 Steam client; games run through the client's emulation tool on the Mali GPU
Exec=/usr/local/bin/steam-arm
Icon=steam-arm
Terminal=false
Categories=Game;
Keywords=steam;arm;native;big picture;
StartupNotify=false
DESK
# icon: the client's own icon with inverted colours, so the two clients are told apart
for sz in 16 32 48 256; do
  SRCI=""; for c in "$D/steam_tray_mono.png" "$RFS/usr/share/icons/hicolor/${sz}x${sz}/apps/steam.png" "$S/tenfoot/resource/images/steam_logo.png"; do [ -f "$c" ] && { SRCI="$c"; break; }; done
  [ -n "$SRCI" ] || continue
  DSTI="/usr/share/icons/hicolor/${sz}x${sz}/apps/steam-arm.png"; mkdir -p "$(dirname "$DSTI")"
  if [ ! -f "$DSTI" ]; then
    if command -v convert >/dev/null 2>&1; then convert "$SRCI" -resize "${sz}x${sz}" -channel RGB -negate "$DSTI" 2>/dev/null || cp -f "$SRCI" "$DSTI"
    else python3 - "$SRCI" "$DSTI" "$sz" <<'PY' 2>/dev/null || cp -f "$SRCI" "$DSTI"
import sys
from PIL import Image, ImageOps
im = Image.open(sys.argv[1]).convert("RGBA"); a = im.getchannel("A")
inv = ImageOps.invert(im.convert("RGB")); inv.putalpha(a)
inv.resize((int(sys.argv[3]),) * 2).save(sys.argv[2])
PY
    fi
  fi
done
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
install -d -o "$GAMEUSER" -g "$GAMEUSER" "$UHOME/Desktop"
cp -f /usr/share/applications/steam-arm.desktop "$UHOME/Desktop/Steam ARM.desktop"; chmod 755 "$UHOME/Desktop/Steam ARM.desktop"; chown "$GAMEUSER:$GAMEUSER" "$UHOME/Desktop/Steam ARM.desktop"
# The Deck build of the client registers no status-notifier item, so it cannot appear in the
# panel tray on its own. This helper puts a Steam icon there with Open, Open in desktop mode,
# Stop and Quit, and starts with the session through an autostart entry in the game user's home.
cat > /usr/local/bin/steam-arm-tray <<'TRAYPY'
#!/usr/bin/env python3
"""Plasma system tray icon for the native ARM64 Steam client.

Valve's Deck build of Steam (the aarch64 client used on this box) registers
no status-notifier item of its own, so the panel's tray never shows it. This
script supplies that item: a Steam icon, a menu to open the client in either
interface or stop it, and a title that reports whether it is running.
"""

import fcntl
import os
import signal
import subprocess
import sys

try:
    import gi

    gi.require_version("AyatanaAppIndicator3", "0.1")
    gi.require_version("Gtk", "3.0")
    from gi.repository import AyatanaAppIndicator3, GLib, Gtk
except (ImportError, ValueError):
    print("steam-arm-tray: install gir1.2-ayatanaappindicator3-0.1", file=sys.stderr)
    sys.exit(1)

STEAM_ARM_BIN = "/usr/local/bin/steam-arm"
CONF_PATH = "/etc/steam-arm/steam-arm.conf"
ARMHOME_DIR = ".local/share/steam-arm"


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


def comm_matches(pid, name):
    try:
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


def signal_processes(name, sig):
    for pid in pids_by_comm(name):
        try:
            os.kill(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass


def launch(args):
    subprocess.Popen(
        [STEAM_ARM_BIN] + args,
        start_new_session=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


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


class SteamTray:
    def __init__(self):
        armhome = resolve_armhome()
        # The indicator API takes an icon name looked up in a theme directory, not a
        # file path, so the client's own tray icon is used by pointing the theme path
        # at the directory it lives in. The theme icon stays as the fallback.
        icon_dir = os.path.join(armhome, ".local/share/Steam/public")
        self.indicator = AyatanaAppIndicator3.Indicator.new(
            "steam-arm", "input-gaming-symbolic",
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        if os.path.isfile(os.path.join(icon_dir, "steam_tray_mono.png")):
            self.indicator.set_icon_theme_path(icon_dir)
            self.indicator.set_icon_full("steam_tray_mono", "Steam")
        self.indicator.set_title("Steam")
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)

        self.menu = Gtk.Menu()
        self.open_item = Gtk.MenuItem(label="Open Steam")
        self.open_item.connect("activate", lambda *_: launch([]))
        self.desktop_item = Gtk.MenuItem(label="Open in desktop mode")
        self.desktop_item.connect("activate", lambda *_: launch(["--desktop"]))
        self.stop_item = Gtk.MenuItem(label="Stop Steam")
        self.stop_item.connect("activate", self.on_stop)
        quit_item = Gtk.MenuItem(label="Quit tray")
        quit_item.connect("activate", lambda *_: Gtk.main_quit())
        for item in (self.open_item, self.desktop_item, Gtk.SeparatorMenuItem(),
                     self.stop_item, Gtk.SeparatorMenuItem(), quit_item):
            self.menu.append(item)
        self.menu.show_all()
        self.indicator.set_menu(self.menu)

        self.update_state()
        GLib.timeout_add_seconds(3, self.on_poll)

    def on_stop(self, *_):
        # SIGTERM only: Steam and its child processes save state and tear
        # down cleanly on SIGTERM. A SIGKILL from here would leave the box
        # in the misplaced-window/wrong-resolution state seen with other
        # fullscreen titles, so it is never used.
        signal_processes("steam", signal.SIGTERM)
        signal_processes("steamwebhelper", signal.SIGTERM)

    def on_poll(self):
        self.update_state()
        return True

    def update_state(self):
        running = steam_running()
        self.open_item.set_sensitive(not running)
        self.desktop_item.set_sensitive(not running)
        self.stop_item.set_sensitive(running)
        self.indicator.set_title("Steam (running)" if running else "Steam")


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
install -d -o "$GAMEUSER" -g "$GAMEUSER" "$UHOME/.config/autostart"
cat > "$UHOME/.config/autostart/steam-arm-tray.desktop" <<'TRAYDESK'
[Desktop Entry]
Type=Application
Name=Steam tray
Comment=Steam icon in the system tray for the ARM64 client
Exec=/usr/local/bin/steam-arm-tray
Icon=input-gaming-symbolic
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
OnlyShowIn=KDE;GNOME;XFCE;
TRAYDESK
chown "$GAMEUSER:$GAMEUSER" "$UHOME/.config/autostart/steam-arm-tray.desktop"
say "     tray helper installed; it appears in the panel at the next login"
# The client draws its own window frame and asks the window manager for none, and this build
# does not move the window when that frame is dragged. A window rule gives the client's normal
# windows the window manager's frame instead, so they move and resize like any other window.
# Big Picture is a fullscreen window, on which a frame is not drawn, so it is unaffected.
RID=steam-arm-frame
kw() { su - "$GAMEUSER" -c "kwriteconfig6 --file kwinrulesrc --group $1 --key $2 '$3'" 2>/dev/null; }
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kw "$RID" Description "Steam ARM: window manager frame"
  kw "$RID" wmclass steam; kw "$RID" wmclassmatch 1; kw "$RID" wmclasscomplete false
  kw "$RID" types 1; kw "$RID" noborder false; kw "$RID" noborderrule 2
  cur=$(su - "$GAMEUSER" -c "kreadconfig6 --file kwinrulesrc --group General --key rules" 2>/dev/null)
  case ",$cur," in *",$RID,"*) new="$cur";; *) new="${cur:+$cur,}$RID";; esac
  kw General rules "$new"; kw General count "$(printf '%s' "$new" | awk -F, '{print NF}')"
fi
else
rm -f /usr/share/applications/steam-arm.desktop "$UHOME/Desktop/Steam ARM.desktop" /usr/share/icons/hicolor/*/apps/steam-arm.png \
      /usr/local/bin/steam-arm-tray "$UHOME/.config/autostart/steam-arm-tray.desktop"
if command -v kwriteconfig6 >/dev/null 2>&1; then
  cur=$(su - "$GAMEUSER" -c "kreadconfig6 --file kwinrulesrc --group General --key rules" 2>/dev/null)
  new=$(printf '%s' "$cur" | tr ',' '\n' | grep -vx steam-arm-frame | paste -sd, -)
  n=$(printf '%s' "$new" | awk -F, 'NF{print NF} !NF{print 0}')
  su - "$GAMEUSER" -c "kwriteconfig6 --file kwinrulesrc --group General --key rules '$new'; kwriteconfig6 --file kwinrulesrc --group General --key count $n; kwriteconfig6 --file kwinrulesrc --group steam-arm-frame --key Description --delete" 2>/dev/null
fi
fi

# ---------------------------------------------------------------------------
say "11/11  done"
cat <<EOM
  Client home:   $ARMHOME   (library under .local/share/Steam/steamapps)
  Launch:        steam-arm   as $GAMEUSER, or the "Steam ARM" menu entry
  First start:   downloads the client package and restarts itself; sign in from Big Picture.
  Games:         x86 Linux titles run through the client's emulation tool; Windows titles through
                 the ARM64 Proton build the client downloads. A title with a Linux build on
                 record but Windows files installed needs: steam-arm-compatmap <appid> proton-stable-arm64
  Optional:     $(for c in $COMPONENTS; do opt "$c" && printf ' %s' "$c" || printf ' [no %s]' "$c"; done)
  (re-run with --select or --skip to change; see --help)
EOM
