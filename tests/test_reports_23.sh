#!/bin/bash
# 2.3 reports group: vk-spoof feature report of --detect (gpu_vk_features with a vulkaninfo stand-in), its place in
# gpu_report, probe only in --detect; launcher uses one client check (client_running). Functions extracted from
# ~/.cache/sarm<NN>-work (SARM_INST picks another installer). Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm232-rep.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }

check "installer bash -n" "bash -n '$INST'"
# vulkaninfo stand-in: full text output of $VI_FILE, environment written to $VI_ENV
mkdir -p "$T/bin" "$T/nobin"
cat > "$T/bin/vulkaninfo" <<'EOF'
#!/bin/sh
env > "$VI_ENV"
[ "$1" = --summary ] && { echo summary-called >> "$VI_ENV"; exit 0; }
cat "$VI_FILE"
EOF
chmod 755 "$T/bin/vulkaninfo"
for x in env timeout awk cat sh; do ln -s "$(command -v "$x")" "$T/nobin/$x"; ln -sf "$(command -v "$x")" "$T/bin/$x" 2>/dev/null; done
# two devices: llvmpipe first (all features), Mali second (three missing, Robustness2 struct absent)
cat > "$T/two.txt" <<'EOF'
==========
VULKANINFO
==========
Presentable Surfaces:
=====================
GPU id : 0 (llvmpipe (LLVM 19.1.7, 128 bits))
GPU id : 1 (Mali-G610 (Panfrost))

Device Properties and Extensions:
=================================
GPU0:
VkPhysicalDeviceProperties:
---------------------------
	apiVersion        = 1.4.305 (4210993)
	vendorID          = 0x10005
	deviceName        = llvmpipe (LLVM 19.1.7, 128 bits)
VkPhysicalDeviceFeatures:
-------------------------
	fillModeNonSolid                        = true
	geometryShader                          = true
	multiViewport                           = true
	shaderClipDistance                      = true
	shaderCullDistance                      = true
VkPhysicalDeviceRobustness2FeaturesEXT:
---------------------------------------
	robustBufferAccess2 = true
	robustImageAccess2  = true

GPU1:
VkPhysicalDeviceProperties:
---------------------------
	apiVersion        = 1.4.305 (4210993)
	vendorID          = 0x13b5
	deviceName        = Mali-G610 (Panfrost)
VkPhysicalDeviceFeatures:
-------------------------
	robustBufferAccess                      = true
	fillModeNonSolid                        = false
	geometryShader                          = false
	multiViewport                           = true
	shaderClipDistance                      = true
	shaderCullDistance                      = false
EOF
sed -e 's/fillModeNonSolid                        = false/fillModeNonSolid = true/' -e 's/geometryShader                          = false/geometryShader = true/' \
    -e 's/shaderCullDistance                      = false/shaderCullDistance = true/' "$T/two.txt" > "$T/all.txt"
printf 'VkPhysicalDeviceRobustness2FeaturesKHR:\n---\n\trobustBufferAccess2 = true\n' >> "$T/all.txt"
VF=$T/vf.sh
{ grep '^VK_SPOOF_FEATURES=' "$INST"; fn gpu_vendor_id "$INST"; fn gpu_vk_features "$INST"; } > "$VF"
vf(){ OUT=$( (export VI_FILE="$2" VI_ENV=$T/env PATH="$1" GPU_DETECTED="${3:-mali-csf-v10}" GPU_VK="${4-panvk 26.1.8}" STEAM_ARM_VK_SPOOF=1; . "$VF"; gpu_vk_features) 2>&1); }
vf "$T/bin" "$T/two.txt"
check "V1 Mali device picked over llvmpipe: native and missing lists in layer's order" "[ \"\$OUT\" = \$'vulkan features native: multiViewport shaderClipDistance\nvulkan features missing: fillModeNonSolid geometryShader shaderCullDistance robustBufferAccess2' ]"
check "V2 probe runs with layer off: STEAM_ARM_VK_SPOOF unset, STEAM_ARM_VK_SPOOF_DISABLE=1, full output (no --summary)" "! grep -q '^STEAM_ARM_VK_SPOOF=' $T/env && grep -qx STEAM_ARM_VK_SPOOF_DISABLE=1 $T/env && ! grep -q summary-called $T/env"
vf "$T/bin" "$T/all.txt"
check "V3 every feature native (KHR Robustness2 struct name): missing none" "[ \"\$OUT\" = \$'vulkan features native: fillModeNonSolid geometryShader multiViewport shaderClipDistance shaderCullDistance robustBufferAccess2\nvulkan features missing: none' ]"
vf "$T/nobin" "$T/two.txt"
check "V4 no vulkaninfo: unknown line" "[ \"\$OUT\" = 'vulkan features: unknown (vulkaninfo not installed)' ]"
vf "$T/bin" "$T/two.txt" mali-csf-v10 ""
check "V5 no Vulkan driver for GPU (GPU_VK empty): unknown line, no probe" "[ \"\$OUT\" = 'vulkan features: unknown (no Vulkan driver for this GPU)' ]"
vf "$T/bin" "$T/two.txt" unknown-family
check "V5 family without vendor id: unknown line" "[ \"\$OUT\" = 'vulkan features: unknown (no Vulkan driver for this GPU)' ]"
vf "$T/bin" "$T/two.txt" adreno-a7xx "turnip 25"
check "V6 vendor not in output: unknown line" "[ \"\$OUT\" = 'vulkan features: unknown (vulkaninfo listed no features for this GPU)' ]"
mkdir -p "$T/posix"; for x in "$T"/bin/*; do ln -s "$(readlink -f "$x")" "$T/posix/${x##*/}"; done
rm -f "$T/posix/awk"; printf '#!/bin/sh\nexec %s --posix "$@"\n' "$(command -v gawk || command -v awk)" > "$T/posix/awk"; chmod 755 "$T/posix/awk"
vf "$T/posix" "$T/two.txt"
check "V11 POSIX awk (mawk/busybox class): same lists" "[ \"\$OUT\" = \$'vulkan features native: multiViewport shaderClipDistance\nvulkan features missing: fillModeNonSolid geometryShader shaderCullDistance robustBufferAccess2' ]"
check "V7 feature list equals layer's spoofed set" "grep -q '^VK_SPOOF_FEATURES=\"fillModeNonSolid geometryShader multiViewport shaderClipDistance shaderCullDistance robustBufferAccess2\"\$' '$INST' && grep -q 'Reports fillModeNonSolid, geometryShader, multiViewport, shaderClipDistance, shaderCullDistance and robustBufferAccess2' '$INST'"
OUT=$(fn gpu_report "$INST")
check "V8 gpu_report order: vulkan:, features, driver archive:" "printf '%s\n' \"\$OUT\" | grep -n 'echo \"vulkan: \|gpu_vk_features\|driver archive:' | cut -d: -f1 | paste -sd' ' | awk '{ exit !(\$1 < \$2 && \$2 < \$3) }'"
check "V9 full probe only in --detect (one call, inside gpu_report)" "[ \$(grep -c 'gpu_vk_features\$\|gpu_vk_features;' '$INST') = 1 ] && printf '%s\n' \"\$OUT\" | grep -qx '  gpu_vk_features'"
check "V10 gpu_vulkan reads vendor id from gpu_vendor_id (one table)" "fn gpu_vulkan '$INST' | grep -q 'want=\$(gpu_vendor_id) || return 0' && [ \$(grep -c 'mali-\*) echo 0x13b5' '$INST') = 1 ]"

# launcher: one client check
L=$T/launcher
awk "/^cat > \\/usr\\/local\\/bin\\/steam-arm <<'LAUNCHER'\$/{f=1;next} /^LAUNCHER\$/{f=0} f" "$INST" > "$L"
check "L1 launcher: client_up gone, client_running defined once and used by first-start loop" "! grep -q client_up '$L' && [ \$(grep -c '^client_running()' '$L') = 1 ] && grep -q 'if client_running; then while client_running; do sleep 2; done; exit 0; fi' '$L'"
check "L1 launcher sh -n" "bash -n '$L'"

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
