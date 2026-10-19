#!/bin/bash
# Fixture releases for the upgrade suite. Functions (sourced):
#   fx_setup V PROTO FILE   setup stand-in of version V: writes owned files under $UHR/sys, VERSION, installer copy,
#                           settings menu stand-in; PROTO=1 behaves as setup 3.1+ (downgrade check, --setup-begin/--setup-end
#                           through $UH); PROTO=0 (setup before 3.1) stops at any option but --keep. Env at run time:
#                           FX_FAIL=1 (exit 1 after VERSION written), FX_KILL=1 (SIGTERM
#                           itself after --setup-begin); every call logged to $UHR/setup.log.
#   fx_menu FILE            settings menu stand-in of an earlier version: backup DIR [--account U] writes a settings file
#   fx_zip V PROTO DIR      DIR/Steam.ARM.V.zip with "Steam ARM V/steam-arm-install.sh" and README.md, plus .sha256
#   fx_deb V DIR [CTL]      DIR/steam-arm-setup_V_arm64.deb stand-in (apt-get and dpkg-deb stubs read version; CTL line
#                           such as ctl-package=x or ctl-arch=x changes control field dpkg-deb stub reports) plus .sha256
#   fx_release V DIR PORT [DIGEST]  DIR/release.json naming zip assets, and package assets when DIR/assets holds them
#                           (digest: GitHub sha256 field, "none" leaves it out; package digest from FX_DEB_DIGEST likewise)
#   fx_apt                  dpkg-deb -f stand-in and apt-get stand-in in $UHR/pbin; apt-get: logs call, snapshot count, lock and state to $UHR/apt.log;
#                           $UHR/apt-fail makes it fail; else package setup of that version goes to $UHR/pkg/install.sh
fx_menu(){ cat > "$1" <<'EOF'
#!/bin/bash
# settings menu stand-in of an earlier release
case "$1" in
  backup) f="$2/steam-arm-settings-fixture.tar.gz"; printf 'settings of %s\n' "$(sed -n 's/^VERSION=//p' "$UHR/etc/steam-arm/steam-arm.conf")" | gzip > "$f"; echo "Saved to $f";;
  *) exit 2;;
esac
EOF
chmod 755 "$1"; }
fx_setup(){
  local v=$1 proto=$2 f=$3
  { echo '#!/bin/bash'
    echo "# setup stand-in"
    echo "SA_VERSION=$v"
    echo "SA_VERSION=$v"
    echo "PROTO=$proto"
    cat <<'EOF'
R=$UHR
echo "setup $SA_VERSION $*" >> "$R/setup.log"
# one setup run at a time, as installer does
mkdir -p "$R/run"; exec 8>"$R/run/steam-arm-setup.lock"; flock -n 8 || { echo "another steam-arm-setup run is in progress"; exit 1; }
# setups before 3.1 stop at options they do not know
if [ "$PROTO" != 1 ]; then for a in "$@"; do case "$a" in --keep) ;; *) echo "error: unknown option: $a (see --help)"; exit 1;; esac; done; fi
older=0; for a in "$@"; do [ "$a" = --allow-older ] && older=1; done
cur=$(sed -n 's/^VERSION=//p' "$R/etc/steam-arm/steam-arm.conf" | tail -1)
gt(){ [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }
if [ "$PROTO" = 1 ]; then
  if [ -n "$cur" ] && gt "$cur" "$SA_VERSION" && [ "$older" = 0 ]; then
    echo "Steam ARM $cur is installed; this installer is $SA_VERSION. To go back use Maintenance > Go back to previous version, or run again with --allow-older."; exit 1
  fi
  if [ -n "$cur" ] && [ "$cur" != "$SA_VERSION" ] || [ -f "$R/lib/upgrade.state" ]; then
    bash "$UH" upgrade --setup-begin "$SA_VERSION" || exit 1
  fi
  [ "${FX_KILL:-0}" = 1 ] && kill -TERM $$
fi
echo "==> 1/11  host packages"
sed -i "s/^VERSION=.*/VERSION=$SA_VERSION/" "$R/etc/steam-arm/steam-arm.conf"
[ "${FX_FAIL:-0}" = 1 ] && { echo "==> 5/11  failed on purpose"; exit 1; }
if [ "${FX_NOWRITE:-0}" != 1 ]; then
  mkdir -p "$R/sys/bin" "$R/sys/lib" "$R/sys/nopkg" "$R/sys/rules" "$R/sys/icons/64x64/apps" "$R/share" "$R/bin"
  echo "launcher $SA_VERSION" > "$R/sys/bin/steam-arm"; chmod 755 "$R/sys/bin/steam-arm"
  echo "helper $SA_VERSION" > "$R/sys/lib/helper.py"; chmod 644 "$R/sys/lib/helper.py"
  echo "guard $SA_VERSION" > "$R/sys/nopkg/apt"; ln -sfn apt "$R/sys/nopkg/apt-get"
  echo "rule $SA_VERSION" > "$R/sys/rules/with space.rules"
  echo "icon $SA_VERSION" > "$R/sys/icons/64x64/apps/steam-arm.png"
  case "$SA_VERSION" in 3.0|2.*) echo "only in 3.0" > "$R/sys/old30"; rm -f "$R/sys/new31";;
    *) echo "new in $SA_VERSION" > "$R/sys/new31"; rm -f "$R/sys/old30";; esac
fi
self=$(readlink -f "$0"); [ "$self" = "$(readlink -f "$R/share/steam-arm-install.sh")" ] || cp "$self" "$R/share/steam-arm-install.sh"
. "$UH_FIX"; fx_menu "$R/bin/steam-arm-config"; echo "SA_VERSION=$SA_VERSION" >> "$R/bin/steam-arm-config"
echo "==> 11/11  done"
[ "$PROTO" = 1 ] && [ -f "$R/lib/upgrade.state" ] && bash "$UH" upgrade --setup-end "$SA_VERSION"
exit 0
EOF
  } > "$f"; chmod 755 "$f"
}
fx_zip(){
  local v=$1 proto=$2 d=$3 w; w=$(mktemp -d)
  mkdir -p "$w/Steam ARM $v" "$d"
  fx_setup "$v" "$proto" "$w/Steam ARM $v/steam-arm-install.sh"
  echo "# Steam ARM $v" > "$w/Steam ARM $v/README.md"
  rm -f "$d/Steam.ARM.$v.zip"
  (cd "$w" && python3 -I -c 'import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
for n in sys.argv[2:]: z.write(n)' "$d/Steam.ARM.$v.zip" "Steam ARM $v/steam-arm-install.sh" "Steam ARM $v/README.md")
  (cd "$d" && sha256sum "Steam.ARM.$v.zip" > "Steam.ARM.$v.zip.sha256")
  rm -rf "$w"
}
fx_deb(){
  mkdir -p "$2"
  printf 'fake package steam-arm-setup %s\n%s\n%s\n' "$1" "$RANDOM$RANDOM" "${3:-}" > "$2/steam-arm-setup_$1_arm64.deb"
  (cd "$2" && sha256sum "steam-arm-setup_$1_arm64.deb" > "steam-arm-setup_$1_arm64.deb.sha256")
}
fx_apt(){ cat > "$UHR/pbin/apt-get" <<'EOF'
#!/bin/bash
R=$UHR
echo "apt-get $*" >> "$R/apt.log"
n=$(find "$R/lib/snapshots" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | wc -l)
if ( exec 7<"$R/run/steam-arm-setup.lock" && flock -n 7 ) 2>/dev/null; then l=free; else l=held; fi
echo "snapshots=$n lock=$l state=$([ -f "$R/lib/upgrade.state" ] && echo yes || echo no) frontend=${DEBIAN_FRONTEND:-}" >> "$R/apt.log"
[ -f "$R/apt-fail" ] && { echo "E: stub failure"; exit 100; }
f=${!#}
v=$(sed -n 's/^fake package steam-arm-setup //p' "$f")
[ -n "$v" ] || { echo "E: not a package"; exit 100; }
. "$UH_FIX"; fx_setup "$v" 1 "$R/pkg/install.sh"
printf '#!/bin/sh\nexec bash %s "$@"\n' "$R/pkg/install.sh" > "$R/pbin/steam-arm-setup"; chmod 755 "$R/pbin/steam-arm-setup"
echo "$R/pkg/install.sh" > "$R/dpkg-owned"; echo "$v" > "$R/dpkg-ver"
EOF
chmod 755 "$UHR/pbin/apt-get"
cat > "$UHR/pbin/dpkg-deb" <<'EOF'
#!/bin/sh
[ "$1" = -f ] || exit 2
f=$2
case "$3" in
  Package) sed -n 's/^ctl-package=//p' "$f" | grep . || echo steam-arm-setup;;
  Version) sed -n 's/^fake package steam-arm-setup //p' "$f";;
  Architecture) sed -n 's/^ctl-arch=//p' "$f" | grep . || echo arm64;;
esac
EOF
chmod 755 "$UHR/pbin/dpkg-deb"; }
fx_release(){
  local v=$1 d=$2 port=$3 dg=${4:-} z
  z="$d/assets/Steam.ARM.$v.zip"
  [ -n "$dg" ] || dg=sha256:$(sha256sum < "$z" | cut -c1-64)
  python3 -I -c 'import hashlib, json, os, sys
v, d, port, dg = sys.argv[1:5]
a = os.path.join(d, "assets")
u = "http://127.0.0.1:%s/dl/steam-arm-v%s/" % (port, v)
z = {"name": "Steam.ARM.%s.zip" % v, "size": os.path.getsize(os.path.join(a, "Steam.ARM.%s.zip" % v)),
     "browser_download_url": u + "Steam.ARM.%s.zip" % v}
if dg != "none": z["digest"] = dg
s = {"name": "Steam.ARM.%s.zip.sha256" % v, "size": os.path.getsize(os.path.join(a, "Steam.ARM.%s.zip.sha256" % v)),
     "browser_download_url": u + "Steam.ARM.%s.zip.sha256" % v}
al = [z, s]
k = "steam-arm-setup_%s_arm64.deb" % v
if os.path.isfile(os.path.join(a, k)):
    kb = open(os.path.join(a, k), "rb").read()
    e = {"name": k, "size": len(kb), "browser_download_url": u + k}
    kd = os.environ.get("FX_DEB_DIGEST") or "sha256:" + hashlib.sha256(kb).hexdigest()
    if kd != "none": e["digest"] = kd
    al += [e, {"name": k + ".sha256", "size": os.path.getsize(os.path.join(a, k + ".sha256")), "browser_download_url": u + k + ".sha256"}]
json.dump({"tag_name": "steam-arm-v%s" % v, "html_url": "https://github.com/Scrumpper/Steam-ARM/releases/tag/steam-arm-v%s" % v,
           "body": "## Steam ARM %s\n\n- notes line\n" % v, "assets": al}, open(os.path.join(d, "release.json"), "w"))' "$v" "$d" "$port" "$dg"
}
