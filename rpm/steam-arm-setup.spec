Name:           steam-arm-setup
Version:        3.1
Release:        1
Summary:        Install Valve's native ARM64 Steam client
License:        MIT
URL:            https://github.com/Scrumpper/Steam-ARM
BuildArch:      aarch64
Requires:       bash >= 5.0, python3 >= 3.8, curl, ca-certificates, xz
Suggests:       newt

%define debug_package %{nil}
# keep packaged scripts byte-identical to the source files (same payload as the .deb)
%undefine __brp_mangle_shebangs
%{!?payload:%error spec needs %%payload from build-rpm.sh; run ./build-rpm.sh}

%description
Installs Valve's native ARM64 Steam client and supporting pieces:
FEX-Emu, x86-64 Ubuntu 24.04 RootFS with Mesa for Valve's emulation
tool (graphics provider), launcher, and optional components such as a
Vulkan compatibility layer, joystick and controller access rules, and a
desktop menu entry.

Nothing is downloaded during package installation. All downloads happen
when the steam-arm-setup command is run.

Requires an ARM64 Fedora-family system with a working Vulkan driver.

%install
mkdir -p %{buildroot}
cp -a %{payload}/. %{buildroot}/

%files
/usr/bin/steam-arm-setup
/usr/share/steam-arm-setup/
/usr/share/applications/steam-arm-setup.desktop
/usr/share/doc/steam-arm-setup/
/usr/share/licenses/steam-arm-setup/

%post
new=$(sed -n 's/^SA_VERSION=//p' /usr/share/steam-arm-setup/install.sh 2>/dev/null | head -n 1) || new=""
old=$(sed -n 's/^VERSION=//p' /etc/steam-arm/steam-arm.conf 2>/dev/null | tail -n 1) || old=""
echo ""
# client set up earlier (package, zip or script): programs setup wrote stay old until setup runs again
if [ -n "$old" ] && [ "$old" != "$new" ]; then
    echo "steam-arm-setup $new installed; Steam ARM programs on this system are from $old"
    echo "(launcher, launch handler, settings menu). To apply $new, run:"
    echo "  sudo steam-arm-setup --keep"
    echo "or Maintenance > Update / Repair in steam-arm-config."
elif [ -n "$old" ]; then
    echo "steam-arm-setup $new installed; Steam ARM $old is set up on this system."
    echo "Update / Repair: sudo steam-arm-setup --keep"
else
    echo "steam-arm-setup installed."
    echo "To install the native ARM64 Steam client, run:"
    echo "  sudo steam-arm-setup"
    echo "or open \"Steam ARM Setup\" from the application menu."
fi
echo ""

# Package removal leaves Steam ARM (package or script install) in place; say how to remove it.
%preun
if [ "$1" -eq 0 ] && [ -f /etc/steam-arm/steam-arm.conf ]; then
    echo ""
    echo "steam-arm-setup: Steam ARM client and its files stay on this system."
    echo "To remove Steam ARM too (installed games are kept unless you ask), run:"
    if [ -f /usr/local/share/steam-arm/steam-arm-install.sh ]; then
        echo "  sudo bash /usr/local/share/steam-arm/steam-arm-install.sh --remove"
    else
        echo "  sudo steam-arm-setup --remove   (before removing this package)"
    fi
    echo "or use Uninstall in the settings menu: steam-arm-config"
    echo ""
fi
