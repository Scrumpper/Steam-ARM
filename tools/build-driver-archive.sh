#!/bin/bash
# build-driver-archive.sh: builds the x86-64 + i386 Mesa driver archive that gpu-in-emulation unpacks into its
# second RootFS tree (steam-arm-fex-mesa-<version>-x86_64-i386.tar.zst plus .sha256).
# Builds inside two Ubuntu 24.04 roots (amd64, i386) on an x86-64 PC; root, or unprivileged through user namespaces.
set -euo pipefail

usage(){ cat <<'EOF'
Usage: build-driver-archive.sh [options]

Builds the x86-64 and i386 Mesa driver archive for gpu-in-emulation on an x86-64 Linux PC.
Defaults reproduce the published archive (Mesa 26.1.8, panfrost and panvk, CPU fallbacks).

Options
  --mesa VERSION       Mesa release from archive.mesa3d.org (default 26.1.8)
  --mesa-sha256 SHA    sha256 of that release tarball (known for 26.1.8 and 26.2.3)
  --mesa-ref REF       Mesa git tag, branch or commit from gitlab.freedesktop.org in
                       place of a release
  --gallium LIST       Gallium drivers, comma separated
                       (default panfrost,llvmpipe,softpipe,zink)
  --vulkan LIST        Vulkan drivers, comma separated (default panfrost,swrast)
  --no-patches         build without the two Steam ARM Mesa patches (GL context
                       bound from several threads; panvk features DXVK asks for);
                       patch sets exist for Mesa 26.1 and 26.2, others try 26.2
  --snapshot STAMP     Ubuntu package snapshot for build dependencies
                       (default 20260929T000000Z)
  --work DIR           build folder (default ./driver-build; about 25 GB)
  --out DIR            output folder (default ./driver-out)
  --jobs N             parallel compile jobs (default: all processors)
  --clean              delete build and output folders first
  --dry-run            check options and host tools, print the plan, build nothing
  -h, --help           this text

Use the result on the ARM64 system (custom driver archive, checked by its sha256):
  sudo env STEAM_ARM_PROVIDER_TARBALL=/path/to/<archive>.tar.zst \
       STEAM_ARM_PROVIDER_SHA256=<sha256> bash steam-arm-install.sh --keep
Back to the published drivers:  sudo bash steam-arm-install.sh --keep --provider-default

Host tools: bash, curl, tar, xz, patch, sha256sum, unshare (util-linux), git
(--mesa-ref only). Needs network.
EOF
}

MESA_VER=26.1.8
MESA_SHA=b320f65874fd9653ac6c0bd1616605387344e1247411a50c797b5f3fb9dc0b55
MESA_REF=""
SHA_SET=0
GALLIUM=panfrost,llvmpipe,softpipe,zink
VULKAN=panfrost,swrast
PATCHES=1
SNAPSHOT=20260929T000000Z
WORK=$PWD/driver-build
OUT=$PWD/driver-out
JOBS=$(nproc 2>/dev/null || echo 4)
CLEAN=0
DRY=0
BASE_TAR=ubuntu-base-24.04.3-base-amd64.tar.gz
BASE_SHA=6bc2cde3930ad088b3bb46fa45279e96d25bc3810f209850ecbe4722711874f9
BASE_URL=https://cdimage.ubuntu.com/ubuntu-base/releases/24.04.3/release/$BASE_TAR
MESA_GIT=https://gitlab.freedesktop.org/mesa/mesa.git

die(){ echo "build-driver-archive: $*" >&2; exit 1; }
log(){ printf '\n== %s\n' "$*"; }
need(){ [ $# -ge 2 ] && [ -n "$2" ] || die "$1 needs a value (see --help)"; }

while [ $# -gt 0 ]; do
  case $1 in
    --mesa) need "$@"; MESA_VER=$2; [ "$SHA_SET" = 1 ] || MESA_SHA=""; shift;;
    --mesa-sha256) need "$@"; MESA_SHA=$2; SHA_SET=1; shift;;
    --mesa-ref) need "$@"; MESA_REF=$2; shift;;
    --gallium) need "$@"; GALLIUM=$2; shift;;
    --vulkan) need "$@"; VULKAN=$2; shift;;
    --no-patches) PATCHES=0;;
    --snapshot) need "$@"; SNAPSHOT=$2; shift;;
    --work) need "$@"; WORK=$(realpath -m -- "$2"); shift;;
    --out) need "$@"; OUT=$(realpath -m -- "$2"); shift;;
    --jobs) need "$@"; JOBS=$2; shift;;
    --clean) CLEAN=1;;
    --dry-run) DRY=1;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1 (see --help)";;
  esac
  shift
done
# known release tarballs
known_sha(){
  case $1 in
    26.1.8) echo b320f65874fd9653ac6c0bd1616605387344e1247411a50c797b5f3fb9dc0b55;;
    26.2.3) echo 1628058a8d2c0615975de5a15ab7bbb9638c50000b5bed9456ff423ea034a81f;;
  esac
}
[ "$SHA_SET" = 1 ] || MESA_SHA=$(known_sha "$MESA_VER")

# --- option checks ---
[[ "$MESA_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] || die "--mesa: release number such as 26.1.8"
[ -z "$MESA_SHA" ] || [[ "$MESA_SHA" =~ ^[0-9a-f]{64}$ ]] || die "--mesa-sha256: 64 hex characters"
[ -z "$MESA_REF" ] || [[ "$MESA_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || die "--mesa-ref: tag, branch or commit"
[[ "$GALLIUM" =~ ^[a-z0-9_]+(,[a-z0-9_]+)*$ ]] || die "--gallium: comma separated driver names"
[[ "$VULKAN" =~ ^[a-z0-9_]+(,[a-z0-9_]+)*$ ]] || die "--vulkan: comma separated driver names"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs: a number"
[[ "$SNAPSHOT" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "--snapshot: form 20260929T000000Z"
case ",$GALLIUM,$VULKAN," in *,panfrost,*) ;; *) echo "note: no panfrost driver selected; Mali GPUs get no driver from this archive" >&2;; esac
[ "$(uname -m)" = x86_64 ] || die "builds run on an x86-64 PC (this is $(uname -m))"
if [ -n "$MESA_REF" ]; then
  VER=git-$(printf '%s' "$MESA_REF" | tr '/' '-')
  SRC_DESC="Mesa git $MESA_REF ($MESA_GIT)"
else
  VER=$MESA_VER
  SRC_DESC="Mesa $MESA_VER (archive.mesa3d.org, sha256 ${MESA_SHA:-not pinned})"
fi
NAME=steam-arm-fex-mesa-$VER-x86_64-i386
# patch set by Mesa major.minor; other versions try the newest
PSETS="26.1 26.2"
pset_for(){ case $1 in 26.1|26.1.*) echo 26.1;; *) echo 26.2;; esac; }

# --- host tools ---
miss=""
for t in curl tar xz patch sha256sum unshare realpath; do command -v "$t" >/dev/null 2>&1 || miss="$miss $t"; done
[ -z "$MESA_REF" ] || command -v git >/dev/null 2>&1 || miss="$miss git"
[ -z "$miss" ] || die "missing host tools:$miss (install them with the package manager)"
if [ "$(id -u)" != 0 ] && ! unshare --map-auto --map-root-user true 2>/dev/null; then
  die "unprivileged user namespaces are off or /etc/subuid has no range for this account; run as root, or enable them"
fi

if [ -n "$MESA_REF" ]; then PLAN_SET="from source VERSION"; else PLAN_SET=$(pset_for "$MESA_VER"); fi
cat <<EOF
Plan
  source     $SRC_DESC
  patches    $([ "$PATCHES" = 1 ] && echo "glx cross-thread current, panvk DXVK features (set $PLAN_SET)" || echo none)
  gallium    $GALLIUM
  vulkan     $VULKAN
  snapshot   Ubuntu 24.04 packages of $SNAPSHOT
  work       $WORK
  output     $OUT/$NAME.tar.zst (+ .sha256)
  jobs       $JOBS
EOF
[ "$DRY" = 1 ] && { echo "dry run: options and host tools OK, nothing built"; exit 0; }

[ "$CLEAN" = 1 ] && rm -rf "$WORK" "$OUT"
R=$WORK/recipe
mkdir -p "$WORK/dl" "$WORK/share" "$OUT" "$R/inner" "$R/patches" "$R/files"

# --- recipe files: run inside the build roots, mounted at /recipe ---
cat > "$R/files/graphics_provider.json" <<'EOF'
{
  "graphics_provider_v0": {
    "root": "./",
    "locales": false,
    "va_api": false,
    "vdpau": false,
    "architectures": {
      "x86_64-linux-gnu": {
        "dri": "/usr/lib/x86_64-linux-gnu/dri",
        "fallback_library_paths": ["/usr/lib/x86_64-linux-gnu"],
        "gconv": "/usr/lib/x86_64-linux-gnu/gconv"
      },
      "i386-linux-gnu": {
        "dri": "/usr/lib/i386-linux-gnu/dri",
        "fallback_library_paths": ["/usr/lib/i386-linux-gnu"],
        "gconv": "/usr/lib/i386-linux-gnu/gconv"
      }
    }
  }
}
EOF

rm -rf "$R/patches" "$R/patchsets"
mkdir -p "$R/patches"
if [ "$PATCHES" = 1 ]; then
for v in $PSETS; do mkdir -p "$R/patchsets/$v"; done
# Mesa 26.1
cat > "$R/patchsets/26.1/0001-glx-allow-cross-thread-current.patch" <<'EOF'
--- a/src/glx/glxcurrent.c
+++ b/src/glx/glxcurrent.c
@@ -15,6 +15,15 @@
 #include "glxclient.h"
 #include "glapi.h"
 #include "glx_error.h"
+#include "util/u_debug.h"
+
+/* Build default for LIBGL_ALLOW_CROSS_THREAD_CURRENT; env var overrides. */
+#ifndef GLX_CROSS_THREAD_CURRENT_DEFAULT
+#define GLX_CROSS_THREAD_CURRENT_DEFAULT false
+#endif
+DEBUG_GET_ONCE_BOOL_OPTION(glx_cross_thread_current,
+                           "LIBGL_ALLOW_CROSS_THREAD_CURRENT",
+                           GLX_CROSS_THREAD_CURRENT_DEFAULT)
 
 /*
 ** We setup some dummy structures here so that the API can be used
@@ -141,7 +150,8 @@
       /* GLX spec 3.3: If ctx is current to some other thread, then
        * glXMakeContextCurrent will generate a BadAccess error
        */
-      if (gc->currentDpy)
+      /* Some games bind one context on two threads; allow it when enabled. */
+      if (gc->currentDpy && !debug_get_option_glx_cross_thread_current())
       {
          __glXUnlock();
          __glXSendError(dpy, BadAccess, None, opcode, True);
EOF
cat > "$R/patchsets/26.1/0002-panvk-fake-dxvk-features.patch" <<'EOF'
--- a/src/panfrost/vulkan/panvk_instance.c
+++ b/src/panfrost/vulkan/panvk_instance.c
@@ -208,6 +208,7 @@
       DRI_CONF_PAN_FRAGMENT_CORE_MASK(~0ull)
       DRI_CONF_PAN_ENABLE_VERTEX_PIPELINE_STORES_ATOMICS(false)
       DRI_CONF_PAN_FORCE_ENABLE_SHADER_ATOMICS(false)
+      DRI_CONF_PAN_FAKE_DXVK_FEATURES(false)
    DRI_CONF_SECTION_END
 };
 
@@ -226,6 +227,8 @@
       &instance->dri_options, "pan_enable_vertex_pipeline_stores_atomics");
    instance->force_enable_shader_atomics = driQueryOptionb(
       &instance->dri_options, "pan_force_enable_shader_atomics");
+   instance->fake_dxvk_features = driQueryOptionb(
+      &instance->dri_options, "pan_fake_dxvk_features");
 }
 
 VKAPI_ATTR VkResult VKAPI_CALL
--- a/src/panfrost/vulkan/panvk_instance.h
+++ b/src/panfrost/vulkan/panvk_instance.h
@@ -58,6 +58,7 @@
 
    bool enable_vertex_pipeline_stores_atomics;
    bool force_enable_shader_atomics;
+   bool fake_dxvk_features;
 
    struct {
       struct pan_kmod_allocator allocator;
--- a/src/panfrost/vulkan/panvk_physical_device.c
+++ b/src/panfrost/vulkan/panvk_physical_device.c
@@ -476,6 +476,17 @@
    panvk_arch_dispatch(arch, get_physical_device_features, instance,
                        device, &supported_features);
 
+   memset(&device->faked_features, 0, sizeof(device->faked_features));
+   if (instance->fake_dxvk_features) {
+#define PANVK_FAKE(f)                                                          \
+   if (!supported_features.f) {                                                \
+      supported_features.f = true;                                             \
+      device->faked_features.f = true;                                         \
+   }
+      PANVK_FAKE_DXVK_FEATURES(PANVK_FAKE)
+#undef PANVK_FAKE
+   }
+
    struct vk_physical_device_dispatch_table dispatch_table;
    vk_physical_device_dispatch_table_from_entrypoints(
       &dispatch_table, &panvk_physical_device_entrypoints, true);
--- a/src/panfrost/vulkan/panvk_physical_device.h
+++ b/src/panfrost/vulkan/panvk_physical_device.h
@@ -57,6 +57,9 @@
    char name[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];
    uint8_t cache_uuid[VK_UUID_SIZE];
 
+   /* Features reported only because of pan_fake_dxvk_features. */
+   struct vk_features faked_features;
+
    struct {
       VkMemoryHeap heaps[1];
       uint32_t heap_count;
@@ -117,4 +120,25 @@
    struct vk_properties *properties);
 #endif
 
+/* Features pan_fake_dxvk_features reports; DXVK/vkd3d refuse the device without them. */
+#define PANVK_FAKE_DXVK_FEATURES(X)                                            \
+   X(geometryShader)                                                           \
+   X(fillModeNonSolid)                                                         \
+   X(multiViewport)                                                            \
+   X(shaderClipDistance)                                                       \
+   X(shaderCullDistance)                                                       \
+   X(robustBufferAccess2)
+
+/* Clear faked features from a device's enabled set so driver paths never see them. */
+static inline void
+panvk_strip_faked_features(const struct panvk_physical_device *pdev,
+                           struct vk_features *enabled)
+{
+#define PANVK_STRIP_FAKED(f)                                                   \
+   if (pdev->faked_features.f)                                                 \
+      enabled->f = false;
+   PANVK_FAKE_DXVK_FEATURES(PANVK_STRIP_FAKED)
+#undef PANVK_STRIP_FAKED
+}
+
 #endif
--- a/src/panfrost/vulkan/panvk_vX_device.c
+++ b/src/panfrost/vulkan/panvk_vX_device.c
@@ -380,6 +380,8 @@
    if (result != VK_SUCCESS)
       goto err_free_dev;
 
+   panvk_strip_faked_features(physical_device, &device->vk.enabled_features);
+
    /* Must be done after vk_device_init() because this function memset(0) the
     * whole struct.
     */
--- a/src/util/00-mesa-defaults.conf
+++ b/src/util/00-mesa-defaults.conf
@@ -1574,6 +1574,13 @@
                -->
             <option name="pan_enable_vertex_pipeline_stores_atomics" value="true" />
         </engine>
+        <!-- DXVK and vkd3d-proton reject the device without these features. -->
+        <engine engine_name_match="DXVK">
+            <option name="pan_fake_dxvk_features" value="true" />
+        </engine>
+        <engine engine_name_match="vkd3d">
+            <option name="pan_fake_dxvk_features" value="true" />
+        </engine>
     </device>
     <device driver="panfrost">
         <application name="all-default">
--- a/src/util/driconf.h
+++ b/src/util/driconf.h
@@ -664,6 +664,10 @@
    DRI_CONF_OPT_B(pan_force_enable_shader_atomics, def, \
                   "Enable fragmentStoresAndAtomics and vertexPipelineStoresAndAtomics on any architecture. (This may not work reliably and is for debug purposes only!)")
 
+#define DRI_CONF_PAN_FAKE_DXVK_FEATURES(def) \
+   DRI_CONF_OPT_B(pan_fake_dxvk_features, def, \
+                  "Report geometryShader, fillModeNonSolid, multiViewport, shaderClipDistance, shaderCullDistance and robustBufferAccess2 as supported so DXVK/vkd3d accept the device; they stay disabled in the driver.")
+
 /**
  * \brief Turnip specific configuration options
  */
EOF
# Mesa 26.2: fake_dxvk_features declared in panvk_drirc_gen.py, DXVK/vkd3d entries in 00-panvk-defaults.conf
cat > "$R/patchsets/26.2/0001-glx-allow-cross-thread-current.patch" <<'EOF'
--- a/src/glx/glxcurrent.c
+++ b/src/glx/glxcurrent.c
@@ -15,6 +15,15 @@
 #include "glxclient.h"
 #include "glapi.h"
 #include "glx_error.h"
+#include "util/u_debug.h"
+
+/* Build default for LIBGL_ALLOW_CROSS_THREAD_CURRENT; env var overrides. */
+#ifndef GLX_CROSS_THREAD_CURRENT_DEFAULT
+#define GLX_CROSS_THREAD_CURRENT_DEFAULT false
+#endif
+DEBUG_GET_ONCE_BOOL_OPTION(glx_cross_thread_current,
+                           "LIBGL_ALLOW_CROSS_THREAD_CURRENT",
+                           GLX_CROSS_THREAD_CURRENT_DEFAULT)
 
 /*
 ** We setup some dummy structures here so that the API can be used
@@ -149,7 +158,8 @@
       /* GLX spec 3.3: If ctx is current to some other thread, then
        * glXMakeContextCurrent will generate a BadAccess error
        */
-      if (gc->currentDpy)
+      /* Some games bind one context on two threads; allow it when enabled. */
+      if (gc->currentDpy && !debug_get_option_glx_cross_thread_current())
       {
          __glXUnlock();
          __glXSendError(dpy, BadAccess, None, opcode, True);
EOF
cat > "$R/patchsets/26.2/0002-panvk-fake-dxvk-features.patch" <<'EOF'
--- a/src/panfrost/vulkan/00-panvk-defaults.conf
+++ b/src/panfrost/vulkan/00-panvk-defaults.conf
@@ -10,5 +10,12 @@
                -->
             <option name="pan_enable_vertex_pipeline_stores_atomics" value="true" />
         </engine>
+        <!-- DXVK and vkd3d-proton reject the device without these features. -->
+        <engine engine_name_match="DXVK">
+            <option name="pan_fake_dxvk_features" value="true" />
+        </engine>
+        <engine engine_name_match="vkd3d">
+            <option name="pan_fake_dxvk_features" value="true" />
+        </engine>
     </device>
 </driconf>
--- a/src/panfrost/vulkan/panvk_drirc_gen.py
+++ b/src/panfrost/vulkan/panvk_drirc_gen.py
@@ -36,6 +36,11 @@
           "Enable fragmentStoresAndAtomics and vertexPipelineStoresAndAtomics on any "
           "architecture. (This may not work reliably and is for debug purposes only!)",
           c_name="force_enable_shader_atomics"),
+        B("pan_fake_dxvk_features", False,
+          "Report geometryShader, fillModeNonSolid, multiViewport, shaderClipDistance, "
+          "shaderCullDistance and robustBufferAccess2 as supported so DXVK/vkd3d accept "
+          "the device; they stay disabled in the driver.",
+          c_name="fake_dxvk_features"),
     ]
 
     debug_options = []
--- a/src/panfrost/vulkan/panvk_physical_device.c
+++ b/src/panfrost/vulkan/panvk_physical_device.c
@@ -466,6 +466,17 @@
    panvk_arch_dispatch(arch, get_physical_device_features, instance,
                        device, &supported_features);
 
+   memset(&device->faked_features, 0, sizeof(device->faked_features));
+   if (instance->drirc.misc.fake_dxvk_features) {
+#define PANVK_FAKE(f)                                                          \
+   if (!supported_features.f) {                                                \
+      supported_features.f = true;                                             \
+      device->faked_features.f = true;                                         \
+   }
+      PANVK_FAKE_DXVK_FEATURES(PANVK_FAKE)
+#undef PANVK_FAKE
+   }
+
    struct vk_physical_device_dispatch_table dispatch_table;
    vk_physical_device_dispatch_table_from_entrypoints(
       &dispatch_table, &panvk_physical_device_entrypoints, true);
--- a/src/panfrost/vulkan/panvk_physical_device.h
+++ b/src/panfrost/vulkan/panvk_physical_device.h
@@ -57,6 +57,9 @@
    char name[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];
    uint8_t cache_uuid[VK_UUID_SIZE];
 
+   /* Features reported only because of pan_fake_dxvk_features. */
+   struct vk_features faked_features;
+
    struct {
       VkMemoryHeap heaps[1];
       uint32_t heap_count;
@@ -124,4 +127,25 @@
    struct vk_properties *properties);
 #endif
 
+/* Features pan_fake_dxvk_features reports; DXVK/vkd3d refuse the device without them. */
+#define PANVK_FAKE_DXVK_FEATURES(X)                                            \
+   X(geometryShader)                                                           \
+   X(fillModeNonSolid)                                                         \
+   X(multiViewport)                                                            \
+   X(shaderClipDistance)                                                       \
+   X(shaderCullDistance)                                                       \
+   X(robustBufferAccess2)
+
+/* Clear faked features from a device's enabled set so driver paths never see them. */
+static inline void
+panvk_strip_faked_features(const struct panvk_physical_device *pdev,
+                           struct vk_features *enabled)
+{
+#define PANVK_STRIP_FAKED(f)                                                   \
+   if (pdev->faked_features.f)                                                 \
+      enabled->f = false;
+   PANVK_FAKE_DXVK_FEATURES(PANVK_STRIP_FAKED)
+#undef PANVK_STRIP_FAKED
+}
+
 #endif
--- a/src/panfrost/vulkan/panvk_vX_device.c
+++ b/src/panfrost/vulkan/panvk_vX_device.c
@@ -378,6 +378,8 @@
    if (result != VK_SUCCESS)
       goto err_free_dev;
 
+   panvk_strip_faked_features(physical_device, &device->vk.enabled_features);
+
    /* Must be done after vk_device_init() because this function memset(0) the
     * whole struct.
     */
EOF
fi

# Build dependencies inside a root; $1 amd64 (tools, LLVM, 64-bit libraries) or i386 (32-bit libraries).
cat > "$R/inner/deps.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
ARCH=$1
# dependency versions from one Ubuntu snapshot
sed -i -E "s#^URIs: http://(archive|security)\.ubuntu\.com/ubuntu/?#URIs: https://snapshot.ubuntu.com/ubuntu/$SNAPSHOT/#" \
  /etc/apt/sources.list.d/ubuntu.sources
# ca-certificates from the same snapshot; package integrity comes from the signed InRelease
if ! [ -e /etc/ssl/certs/ca-certificates.crt ]; then
  apt-get -o Acquire::https::Verify-Peer=false update -qq
  apt-get -o Acquire::https::Verify-Peer=false install -y -qq --no-install-recommends ca-certificates >/dev/null
fi
[ "$ARCH" = i386 ] && dpkg --add-architecture i386
apt-get update -qq
TOOLS="build-essential pkg-config python3 python3-pip python3-mako python3-yaml python3-ply python3-packaging
  bison flex glslang-tools ninja-build patch xz-utils zstd file"
LIBS="libdrm-dev libx11-dev libxext-dev libxfixes-dev libxcb-glx0-dev libxcb-shm0-dev libx11-xcb-dev
  libxcb-dri2-0-dev libxcb-dri3-dev libxcb-present-dev libxcb-randr0-dev libxcb-sync-dev libxcb-xfixes0-dev
  libxshmfence-dev libxxf86vm-dev libxrandr-dev libexpat1-dev zlib1g-dev libzstd-dev libglvnd-dev libvulkan-dev"
if [ "$ARCH" = amd64 ]; then
  PKGS="$TOOLS $LIBS llvm-18-dev libclang-18-dev libclang-cpp18-dev libclc-18-dev llvm-spirv-18
    libllvmspirvlib-18-dev spirv-tools libpolly-18-dev"
else
  PKGS="$TOOLS gcc-multilib g++-multilib"
  for p in $LIBS libxml2-dev libncurses-dev libstdc++-13-dev; do PKGS="$PKGS $p:i386"; done
  # amd64 runtime of the compilers built in the amd64 root (mesa_clc, panfrost_compile)
  PKGS="$PKGS libllvm18:amd64 libclang-cpp18:amd64 libllvmspirvlib18.1:amd64 libclang-common-18-dev:amd64 libclc-18"
fi
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $PKGS >/tmp/apt.log 2>&1 || { tail -40 /tmp/apt.log; exit 1; }
# Mesa 26.1 needs a newer meson than Ubuntu 24.04 has
pip3 install -q --break-system-packages meson==1.12.1
# i386 LLVM conflicts with the amd64 compiler runtime above: unpacked outside dpkg into /opt/llvm32
if [ "$ARCH" = i386 ] && [ ! -x /opt/llvm32/usr/lib/llvm-18/bin/llvm-config ]; then
  mkdir -p /tmp/llvm32 /opt/llvm32 && cd /tmp/llvm32
  apt-get download -qq llvm-18-dev:i386 llvm-18:i386 libllvm18:i386 libpolly-18-dev:i386
  for d in *.deb; do dpkg-deb -x "$d" /opt/llvm32; done
fi
meson --version
EOF

# Configure, build and install one flavour: tools | x86_64 | i386. Source /work/mesa, output /work/inst-<flavour>.
cat > "$R/inner/build.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
T=$1
SRC=/work/mesa
BLD=/work/build-$T
cd "$SRC"
COMMON=(--buildtype=release -Db_ndebug=true -Dbuild-tests=false -Dvalgrind=disabled
  -Dlibunwind=disabled -Dlmsensors=disabled -Dvideo-codecs= -Dgallium-va=disabled -Dgallium-rusticl=false)
# layout as Ubuntu's Mesa packages; GL contexts may be bound from several threads by default (patch 0001)
TARGET=(-Dgallium-drivers="$GALLIUM" -Dvulkan-drivers="$VULKAN"
  -Dvulkan-layers=device-select,vram-report-limit -Dplatforms=x11
  -Dglx=dri -Degl=enabled -Dgbm=enabled -Dglvnd=enabled -Dgles1=disabled -Dgles2=enabled
  -Dllvm=enabled -Dshared-llvm=disabled -Dxmlconfig=enabled -Dzstd=enabled
  -Dgallium-extra-hud=true
  -Dc_args=-DGLX_CROSS_THREAD_CURRENT_DEFAULT=true)
case $T in
tools)
  # compilers the target builds run on the build machine; not in the archive
  [ -f "$BLD/build.ninja" ] || meson setup "$BLD" "${COMMON[@]}" --prefix=/usr/local \
    -Dgallium-drivers=panfrost -Dvulkan-drivers= -Dplatforms= -Dglx=disabled -Degl=disabled -Dgbm=disabled \
    -Dllvm=enabled -Dmesa-clc=enabled -Dprecomp-compiler=enabled -Dinstall-mesa-clc=true \
    -Dinstall-precomp-compiler=true -Dtools=
  ninja -C "$BLD" -j"$JOBS" src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2 src/panfrost/clc/panfrost_compile
  mkdir -p /work/tools-bin
  cp "$BLD/src/compiler/clc/mesa_clc" "$BLD/src/compiler/spirv/vtn_bindgen2" "$BLD/src/panfrost/clc/panfrost_compile" /work/tools-bin/
  exit 0;;
x86_64)
  LIBDIR=lib/x86_64-linux-gnu
  export PATH=/work/tools-bin:$PATH
  EXTRA=(-Dtools= -Dmesa-clc=system -Dprecomp-compiler=system -Dspirv-tools=disabled);;
i386)
  LIBDIR=lib/i386-linux-gnu
  # native -m32 build against the unpacked i386 LLVM; CLC compilers from the amd64 root
  cat > /work/i386.native <<'NATIVE'
[binaries]
c = ['gcc', '-m32']
cpp = ['g++', '-m32']
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'
llvm-config = '/opt/llvm32/usr/lib/llvm-18/bin/llvm-config'
[properties]
pkg_config_libdir = '/usr/lib/i386-linux-gnu/pkgconfig:/usr/share/pkgconfig'
NATIVE
  export PKG_CONFIG_LIBDIR=/usr/lib/i386-linux-gnu/pkgconfig:/usr/share/pkgconfig
  export PATH=/work/tools-bin:$PATH
  EXTRA=(--native-file /work/i386.native -Dtools= -Dmesa-clc=system -Dprecomp-compiler=system -Dspirv-tools=disabled);;
*) echo "unknown flavour $T" >&2; exit 2;;
esac
[ -f "$BLD/build.ninja" ] || meson setup "$BLD" "${EXTRA[@]}" "${COMMON[@]}" --prefix=/usr --libdir="$LIBDIR" "${TARGET[@]}"
ninja -C "$BLD" -j"$JOBS"
rm -rf "/work/inst-$T"
DESTDIR="/work/inst-$T" ninja -C "$BLD" install >/dev/null
EOF

# Archive tree /work/stage from both installs, Ubuntu multiarch layout.
cat > "$R/inner/stage.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
S=/work/stage
rm -rf "$S"; mkdir -p "$S"
for T in x86_64 i386; do
  I=/work/inst-$T
  L=usr/lib/$T-linux-gnu
  mkdir -p "$S/$L"
  # runtime files only: vendor libraries, drivers, gbm backend; no headers, pkgconfig or dev links
  (cd "$I" && find "$L" \( -type f -o -type l \) ! -path "*/pkgconfig/*" \
     ! -name libGLX_mesa.so ! -name libEGL_mesa.so ! -name libgbm.so -print0 | xargs -0 cp -a --parents -t "$S")
  if [ -d "$I/usr/share/vulkan/icd.d" ]; then
    mkdir -p "$S/usr/share/vulkan/icd.d"
    for j in "$I"/usr/share/vulkan/icd.d/*.json; do
      b=$(basename "$j")
      # i386 manifests named .x86.json, as Valve's graphics provider expects
      cp "$j" "$S/usr/share/vulkan/icd.d/${b/.i686.json/.x86.json}"
    done
  fi
done
# architecture-neutral data, identical in both installs
for d in usr/share/glvnd usr/share/drirc.d usr/share/vulkan/implicit_layer.d usr/share/vulkan/explicit_layer.d; do
  [ -d "/work/inst-x86_64/$d" ] || continue
  diff -r "/work/inst-x86_64/$d" "/work/inst-i386/$d" >/dev/null || { echo "stage: $d differs between arches" >&2; exit 1; }
  mkdir -p "$S/$(dirname "$d")"; cp -a "/work/inst-x86_64/$d" "$S/$d"
done
find "$S/usr/lib" -type f -name "*.so*" -exec strip --strip-unneeded {} +
cp /recipe/files/graphics_provider.json "$S/graphics_provider.json"
D=$S/usr/share/doc/steam-arm-fex-mesa
mkdir -p "$D/patches"
cp /work/mesa/docs/license.rst "$D/LICENSE.mesa.rst"
cp /usr/share/doc/llvm-18/copyright "$D/LICENSE.llvm" 2>/dev/null || cp /usr/share/doc/libllvm18/copyright "$D/LICENSE.llvm"
cp /recipe/patches/*.patch "$D/patches/" 2>/dev/null || true
{
  echo "mesa $MESA_VER"
  echo "built in ubuntu 24.04 (snapshot $SNAPSHOT), llvm $(llvm-config-18 --version) static"
  echo "patches: $(cd /recipe/patches && ls -- *.patch 2>/dev/null | tr '\n' ' ')"
} > "$D/BUILDINFO"
du -sh "$S"
EOF

# Libraries of one architecture resolve, LLVM linked in; llvmpipe GL context as a smoke check.
cat > "$R/inner/verify.sh" <<'EOF'
#!/bin/bash
set -uo pipefail
T=$1
S=/work/stage
L=$S/usr/lib/$T-linux-gnu
FAIL=0
check(){ local name=$1; shift; if "$@"; then echo "PASS $name"; else echo "FAIL $name"; FAIL=1; fi; }
missing=0 seen=0
while IFS= read -r f; do
  seen=$((seen + 1))
  out=$(LD_LIBRARY_PATH=$L ldd "$f" 2>&1)
  if grep -q "not found" <<<"$out"; then echo "unresolved in $f:"; grep "not found" <<<"$out"; missing=1; fi
done < <(find "$L" -type f -name "*.so*")
# no library read (file list unreadable) counts as failure, not as pass
check "$T: libraries found to check ($seen)" test "$seen" -gt 0
check "$T: all NEEDED libraries resolve" test $missing = 0
echo "$T: libraries the drivers load from the RootFS:"
find "$L" -type f -name "*.so*" -exec readelf -d {} + 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u |
  while read -r n; do [ -e "$L/$n" ] || echo "  $n"; done
check "$T: LLVM linked in (no libLLVM NEEDED)" bash -c "! find '$L' -type f -name '*.so*' -exec readelf -d {} + | grep -q libLLVM"
case ",$GALLIUM," in
  *,llvmpipe,*)
    cat > /tmp/egl_surfaceless.c <<'CSRC'
/* EGL surfaceless context; prints the GL renderer. */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <stdio.h>
int main(void)
{
   PFNEGLGETPLATFORMDISPLAYEXTPROC gpd =
      (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
   EGLDisplay d = gpd(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
   if (!eglInitialize(d, NULL, NULL)) { puts("eglInitialize failed"); return 1; }
   eglBindAPI(EGL_OPENGL_API);
   EGLContext c = eglCreateContext(d, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, NULL);
   if (!c || !eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, c)) { puts("context failed"); return 1; }
   printf("GL %s | %s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));
   return 0;
}
CSRC
    CC="gcc"; [ "$T" = i386 ] && CC="gcc -m32"
    $CC -O1 -o /tmp/egl_surfaceless /tmp/egl_surfaceless.c -lEGL -lGL
    export LD_LIBRARY_PATH=$L __GLX_VENDOR_LIBRARY_NAME=mesa LIBGL_DRIVERS_PATH=$L/dri GBM_BACKENDS_PATH=$L/gbm \
      __EGL_VENDOR_LIBRARY_DIRS=$S/usr/share/glvnd/egl_vendor.d DRIRC_CONFIGDIR=$S/usr/share/drirc.d
    check "$T: llvmpipe GL context" bash -c "/tmp/egl_surfaceless | tee /dev/stderr | grep -q llvmpipe";;
esac
echo "== $T: $([ $FAIL = 0 ] && echo all checks passed || echo checks failed)"
exit $FAIL
EOF
# Reproducible archive of /work/stage: fixed tar format, order, owners and mtime; zstd of the build root, one thread.
cat > "$R/inner/archive.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
NAME=$1 MTIME=$2
zstd --version
tar --format=gnu --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$MTIME" \
  -C /work/stage -cf - . | zstd -19 -T1 -q -f -o "/work/$NAME.tar.zst"
EOF
chmod 755 "$R"/inner/*.sh

# --- helpers on the build machine ---
fetch(){ # url sha dest; empty sha: not pinned, sha printed
  if [ -f "$3" ] && { [ -z "$2" ] || echo "$2  $3" | sha256sum -c --quiet 2>/dev/null; }; then return 0; fi
  curl -fL --proto =https --proto-redir =https --retry 3 -o "$3.part" "$1" && mv "$3.part" "$3"
  if [ -n "$2" ]; then echo "$2  $3" | sha256sum -c --quiet || die "checksum mismatch: $3"
  else echo "  not pinned: sha256 $(sha256sum "$3" | cut -c1-64)"; fi
}
# Run a command inside root $1 with $WORK/share at /work and the recipe at /recipe.
inroot(){
  local root=$1; shift
  # shellcheck disable=SC2016
  local setup='
    set -e
    R=$1; W=$2; H=$3; shift 3
    for d in null zero random urandom tty full; do [ -e $R/dev/$d ] || touch $R/dev/$d; mount --bind /dev/$d $R/dev/$d; done
    mount -t proc proc $R/proc
    # process substitution in the inner scripts needs /dev/fd
    [ -e $R/dev/fd ] || ln -s /proc/self/fd $R/dev/fd
    touch $R/etc/resolv.conf; mount --bind /etc/resolv.conf $R/etc/resolv.conf
    mount -t tmpfs tmpfs $R/tmp
    mkdir -p $R/work $R/recipe
    mount --bind $W $R/work; mount --bind $H $R/recipe
    exec chroot $R /usr/bin/env -i PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
      DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 JOBS='"$JOBS"' MESA_VER='"$VER"' SNAPSHOT='"$SNAPSHOT"' \
      GALLIUM='"$GALLIUM"' VULKAN='"$VULKAN"' /bin/bash "$@"'
  if [ "$(id -u)" = 0 ]; then
    unshare --mount --fork --pid bash -c "$setup" _ "$root" "$WORK/share" "$R" "$@"
  else
    unshare --map-auto --map-root-user --mount --fork --pid bash -c "$setup" _ "$root" "$WORK/share" "$R" "$@"
  fi
}
extract_base(){ # dest
  rm -rf "$1"; mkdir -p "$1"
  if [ "$(id -u)" = 0 ]; then tar -xzf "$WORK/dl/$BASE_TAR" -C "$1"
  else unshare --map-auto --map-root-user tar -xzf "$WORK/dl/$BASE_TAR" -C "$1"; fi
}

log "sources"
fetch "$BASE_URL" "$BASE_SHA" "$WORK/dl/$BASE_TAR"
STAMP="$VER $([ "$PATCHES" = 1 ] && echo patched || echo plain)"
if [ "$(cat "$WORK/share/.src" 2>/dev/null)" != "$STAMP" ]; then
  rm -rf "$WORK/share/mesa" "$WORK/share/.src" "$WORK"/share/build-* "$WORK"/share/inst-* "$WORK/share/tools-bin"
  if [ -n "$MESA_REF" ]; then
    git clone --quiet "$MESA_GIT" "$WORK/share/mesa"
    git -C "$WORK/share/mesa" checkout --quiet "$MESA_REF"
  else
    fetch "https://archive.mesa3d.org/mesa-$MESA_VER.tar.xz" "$MESA_SHA" "$WORK/dl/mesa-$MESA_VER.tar.xz"
    mkdir -p "$WORK/share/mesa"
    tar -xJf "$WORK/dl/mesa-$MESA_VER.tar.xz" -C "$WORK/share/mesa" --strip-components=1
  fi
  FRESH=1
fi
if [ "$PATCHES" = 1 ]; then
  SRCVER=$(cat "$WORK/share/mesa/VERSION" 2>/dev/null || echo "$MESA_VER")
  PSET=$(pset_for "$SRCVER")
  echo "  Mesa $SRCVER: patch set $PSET"
  cp "$R/patchsets/$PSET"/*.patch "$R/patches/"
fi
if [ "${FRESH:-0}" = 1 ]; then
  for p in "$R"/patches/*.patch; do
    [ -f "$p" ] || continue
    echo "  patch $(basename "$p")"
    patch -d "$WORK/share/mesa" -p1 --forward --quiet < "$p" \
      || die "$(basename "$p") does not apply to this Mesa source; try --no-patches, or a Mesa 26.1 or 26.2 release"
  done
  echo "$STAMP" > "$WORK/share/.src"
fi

log "build roots"
for a in amd64 i386; do
  d=$WORK/root-$a
  if [ "$(cat "$d/.deps" 2>/dev/null)" != "$SNAPSHOT" ]; then
    extract_base "$d"
    inroot "$d" /recipe/inner/deps.sh "$a"
    echo "$SNAPSHOT" > "$d/.deps"
  fi
done

log "build"
inroot "$WORK/root-amd64" /recipe/inner/build.sh tools
inroot "$WORK/root-amd64" /recipe/inner/build.sh x86_64
inroot "$WORK/root-i386" /recipe/inner/build.sh i386

log "stage and check"
inroot "$WORK/root-amd64" /recipe/inner/stage.sh
inroot "$WORK/root-i386" /recipe/inner/verify.sh i386 2>&1 | tee "$OUT/verify-i386.log" || true
inroot "$WORK/root-amd64" /recipe/inner/verify.sh x86_64 2>&1 | tee "$OUT/verify-x86_64.log" || true
for a in i386 x86_64; do
  grep -q "== $a: all checks passed" "$OUT/verify-$a.log" || die "checks failed for $a (log: $OUT/verify-$a.log)"
done

log "archive"
rm -rf "${OUT:?}/$NAME" && cp -a "$WORK/share/stage" "$OUT/$NAME"
rm -f "$WORK/share/$NAME.tar.zst"
inroot "$WORK/root-amd64" /recipe/inner/archive.sh "$NAME" "$(date -u -d "${SNAPSHOT%%T*}" +%s)"
mv -f "$WORK/share/$NAME.tar.zst" "$OUT/$NAME.tar.zst"
(cd "$OUT" && sha256sum "$NAME.tar.zst" > "$NAME.tar.zst.sha256")
du -sh "$OUT/$NAME" "$OUT/$NAME.tar.zst"
cat "$OUT/$NAME.tar.zst.sha256"
