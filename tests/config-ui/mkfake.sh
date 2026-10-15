#!/bin/bash
# Build fake install tree for steam-arm-config tests.
set -e
R=${SARM_UI_FAKE:-$(cd "$(dirname "$0")" && pwd)/fake}
rm -rf "$R"; mkdir -p "$R"
H="$R/home/tester"; A="$H/.local/share/steam-arm"; S="$A/.local/share/Steam"
mkdir -p "$R/etc/steam-arm" "$R/share" "$R/bin" "$R/tmp" "$S/steamapps/common/FEX-Emu" "$S/package" "$S/config" "$A/.config/steam-arm"
cat > "$R/etc/steam-arm/steam-arm.conf" <<EOF
ARMHOME_DIR=.local/share/steam-arm
GAMEUSER=tester
COMPONENTS_ON=glx-lax,vk-spoof,gpu-in-emulation,map-count,xpad-dedup,pad-hidraw,desktop,desktop-mode,tray,page-size
COMPONENTS_OFF=pad-xbox,icon-bigpicture,icon-desktop
GFX_DEFAULT=auto
VERSION=1.3
EOF
cat > "$R/share/titles.conf" <<'EOF'
# Included title profiles
620 overlay=off
EOF
cat > "$R/etc/steam-arm/titles.conf" <<'EOF'
# Local title profiles; one line per title
#   overlay=x86|vulkan|off  mangohud=on|off
219150 gfx=b mangohud=on   # Hotline Miami 2 test
312520 overlay=vulkan
312520 env=A=1;B=2
EOF
cat > "$A/.config/steam-arm/titles.conf" <<'EOF'
400 gfx=a
EOF
printf '#!/bin/sh\necho launcher\n' > "$R/bin/steam-arm"; chmod 755 "$R/bin/steam-arm"
printf '#!/bin/sh\necho "compatmap $*"\n' > "$R/bin/steam-arm-compatmap"; chmod 755 "$R/bin/steam-arm-compatmap"
cat > "$R/bin/steam-arm-remoteplay" <<EOF
#!/bin/sh
echo "$S/userdata/123/config/localconfig.vdf: already pinned"
EOF
chmod 755 "$R/bin/steam-arm-remoteplay"
echo "FEX-2609.1 (2026-08-13)" > "$S/steamapps/common/FEX-Emu/VERSIONS.txt"
echo "steamdeck_publicbeta" > "$S/package/beta"
L2="$R/media/Game Drive/SteamLibrary"; mkdir -p "$L2/steamapps"
cat > "$S/steamapps/libraryfolders.vdf" <<EOF
"libraryfolders"
{
	"0"
	{
		"path"		"$S"
	}
	"1"
	{
		"path"		"$L2"
	}
}
EOF
acf(){ cat > "$1/steamapps/appmanifest_$2.acf" <<EOF
"AppState"
{
	"appid"		"$2"
	"name"		"$3"
	"installdir"		"$4"
}
EOF
}
acf "$S" 219150 "Hotline Miami 2: Wrong Number" "Hotline Miami 2"
acf "$S" 312520 "Rain World" "Rain World"
acf "$S" 400 "Portal" "Portal"
acf "$S" 1493710 "Proton Experimental" "Proton - Experimental"
acf "$S" 1628350 "Steam Linux Runtime 3.0 (sniper)" "SteamLinuxRuntime_sniper"
acf "$S" 228980 "Steamworks Common Redistributables" "Steamworks Shared"
acf "$S" 3483740 "FEX-Emu" "FEX-Emu"
acf "$L2" 1036240 "Jelly Brawl" "Jelly Brawl"
cat > "$R/tmp/fex-compat-tool-1234.log" <<EOF
cmd: SteamLaunch AppId=312520 -- $S/steamapps/common/Rain World/RainWorld
steam-arm: profile for 312520 {'overlay': 'vulkan', 'env': 'A=1;B=2'}
steam-arm: engine: unity, 64-bit
steam-arm: overlay: vulkan
steam-arm: graphics: forwarding
EOF
# fake sys/proc
P="$R/proc"; Y="$R/sys"
mkdir -p "$P/device-tree" "$P/bus/input" "$Y/class/drm/card1/device" "$Y/class/drm/renderD128/device" "$Y/bus/platform/drivers/panthor" "$Y/bus/platform/drivers/rockchip-drm"
printf 'Test Board RK3588 Max\0' > "$P/device-tree/model"
printf 'test,board\0rockchip,rk3588\0' > "$P/device-tree/compatible"
ln -s ../../../../bus/platform/drivers/rockchip-drm "$Y/class/drm/card1/device/driver"
ln -s ../../../../bus/platform/drivers/panthor "$Y/class/drm/renderD128/device/driver"
printf 'MemTotal:       16303836 kB\n' > "$P/meminfo"
cat > "$P/bus/input/devices" <<'EOF'
I: Bus=0003 Vendor=045e Product=028e Version=0114
N: Name="Microsoft X-Box 360 pad"
H: Handlers=event5 js0

I: Bus=0003 Vendor=046d Product=c52b Version=0111
N: Name="Logitech USB Receiver"
H: Handlers=sysrq kbd event3
EOF
mkdir -p "$Y/class/hidraw/hidraw0/device"
printf 'HID_ID=0003:0000045E:0000028E\nHID_NAME=Microsoft X-Box 360 pad\n' > "$Y/class/hidraw/hidraw0/device/uevent"
mkdir -p "$R/rules"; : > "$R/rules/60-steam-arm-gamepad-hidraw.rules"; : > "$R/rules/71-steam-arm-xpad-dedup.rules"
mkdir -p "$R/opt/Ubuntu_24_04/a" "$R/opt/Ubuntu_24_04-mali"; head -c 2000000 /dev/zero > "$R/opt/Ubuntu_24_04/a/big"
: > "$R/opt/Ubuntu_24_04-mali/.steam-arm-mali"; head -c 500000 /dev/zero > "$R/opt/Ubuntu_24_04-mali/extra"
# fake installer
cat > "$R/bin/fake-installer.sh" <<'EOF'
#!/bin/bash
echo "ARGS: $* GPU_FAMILY=${GPU_FAMILY:-} GAMEUSER=${GAMEUSER:-}" >> "${FAKE_INST_LOG:-/dev/null}"
case "${1:-}" in
  --detect)
    if [ "${FAKE_DETECT_FMT:-}" = old ]; then cat <<'D'
GPU family: mali
Kernel driver: panthor
Vulkan: Mali-G610 MC4, PanVK Mesa 26.1.4, API 1.4.318
Page size: 4096
Defaults: glx-lax,vk-spoof,gpu-in-emulation,map-count,xpad-dedup,pad-hidraw,desktop,desktop-mode,icon-bigpicture,icon-desktop,tray,page-size
Notes:
  Mali-G610 on Panthor: main tested setup.
  Windows titles with Direct3D 12 need features PanVK lacks.
D
    else
      f=${GPU_FAMILY:-mali-csf-v10}; [ "$f" = auto ] && f=mali-csf-v10
      echo "GPU: Mali-G610 (panthor, Vulkan: panvk 26.1.4)"
      [ -n "${GPU_FAMILY:-}" ] && [ "$GPU_FAMILY" != auto ] && echo "family: $f (set by user)" || echo "family: $f"
      echo "detected family: mali-csf-v10"; echo "gpu: Mali-G610"; echo "kernel driver: panthor"
      echo "vulkan: panvk 26.1.4"; echo "page size: 4096"; echo "distro: Test OS"
      for c in glx-lax vk-spoof gpu-in-emulation map-count xpad-dedup pad-hidraw pad-xbox desktop desktop-mode icon-bigpicture icon-desktop tray page-size; do
        v=on; [ "$c" = pad-xbox ] && v=off
        case "$f/$c" in mali-csf-v10/*) ;; */vk-spoof|*/gpu-in-emulation) v=off;; esac
        echo "component $c: $v"
      done
      echo "note: Mali-G610 on Panthor: main tested setup"
    fi;;
  --list) for c in glx-lax vk-spoof gpu-in-emulation map-count xpad-dedup pad-hidraw pad-xbox desktop desktop-mode icon-bigpicture icon-desktop tray page-size; do printf '  %-16s %s\n' "$c" "desc of $c"; done;;
  --select*|--keep)
    for i in $(seq 1 11); do printf '\n\033[1;36m==>\033[0m %s/11  step %s text\n' "$i" "$i"; echo "detail line $i"; sleep "${FAKE_SLEEP:-0.05}"; done;;
  --remove) echo "removing (fake)";;
esac
EOF
chmod 755 "$R/bin/fake-installer.sh"
echo "$R"
