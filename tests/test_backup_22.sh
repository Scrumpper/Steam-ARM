#!/bin/bash
# Settings backup format (outline 2a item 23): archives written by the 2.0, 2.1 and 2.2 menu apps (their own bk_make, in a
# fake tree) and hand-made format-1 archives restore with 2.3 (rs_open, rs_plan, rs_apply); hostile archives refused.
# Menu apps sourced as harness.sh does (sed copy, /proc and /sys to fake tree, last main line dropped). Internal.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$(dirname "$0")/paths.sh"
CFG=$SARM_CFG
INST=$SARM_INST
# menu apps of releases 2.0, 2.1, 2.2 (run-all.sh SARM_OLD)
APP20=$(sarm_old 2.0 steam-arm-config); APP21=$(sarm_old 2.1 steam-arm-config); APP22=$(sarm_old 2.2 steam-arm-config)
[ -n "$APP20" ] && [ -n "$APP21" ] && [ -n "$APP22" ] || { echo "SKIP backup suite: 2.0, 2.1, 2.2 releases not available (run through run-all.sh)"; exit 0; }
T=$(mktemp -d /tmp/sarm232-backup.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -n 6; fail=$((fail + 1)); fi; }
grep -q '^SA_VERSION=2.0$' "$APP20" && grep -q '^SA_VERSION=2.1$' "$APP21" && grep -q '^SA_VERSION=2.2$' "$APP22" || { echo "FAIL 2.0 / 2.1 / 2.2 menu apps not found"; exit 1; }

# fake tree from mkfake.sh, rooted in $T
R=$T/fake
sed "s#^R=.*#R=$R#" "$HERE/config-ui/mkfake.sh" > "$T/mkfake.sh"; bash "$T/mkfake.sh" >/dev/null
A=$R/home/tester/.local/share/steam-arm
mkdir -p "$A/.fex-emu/AppConfig" "$A/.config/MangoHud" "$A/.local/share/Steam/config"
printf '{"Config": {"Multiblock": "0"}}\n' > "$A/.fex-emu/AppConfig/hl2_linux.json"
printf '{"Config": {"TSOEnabled": "1"}}\n' > "$A/.fex-emu/AppConfig/Game-x86_64.json"
printf 'fps\nposition=top-right\n' > "$A/.config/MangoHud/MangoHud.conf"
printf '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n\t\t\t\t\t"400"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"proton_experimental"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n\t\t\t\t\t"219150"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"proton-stable-arm64"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n' > "$A/.local/share/Steam/config/config.vdf"
printf 'COMPONENTS_USER_SET=1\nGFX_DEFAULT=b\nGPU_FAMILY_SET=user\nGPU_FAMILY=mali-csf-v10\n' >> "$R/etc/steam-arm/steam-arm.conf"
# 2.3 machine key: path of local driver archive copy (archives from 2.2 menu carry it too: whole settings file)
printf 'PROVIDER_LOCAL_FILE=/srv/backup-machine/steam-arm-fex-mesa.tar.zst\n' >> "$R/etc/steam-arm/steam-arm.conf"
# 2.3 profile key diskcache (copied as text by every menu version)
printf '100 diskcache=on multiblock=on\n' >> "$R/etc/steam-arm/titles.conf"
awk "/^cat > \/usr\/local\/lib\/steam-arm-compatmap.py <<'PYEOF'\$/{f=1;next} /^PYEOF\$/{f=0} f" "$INST" > "$T/compatmap.py"

# harness for menu app $1 as $2 (sourced: no main call)
mkh(){
  sed -e "s#\"/proc/#\"$R/proc/#g" -e "s#/sys/class#$R/sys/class#g" -e '$d' "$1" > "$T/app-$2.sh"
  cat > "$T/h-$2.sh" <<EOF
. "$T/app-$2.sh"
R=$R
SA_CONF=\$R/etc/steam-arm/steam-arm.conf; SA_TITLES_SHARE=\$R/share/titles.conf; SA_TITLES_ETC=\$R/etc/steam-arm/titles.conf
SA_LAUNCHER=\$R/bin/steam-arm; SA_COMPATMAP=\$R/bin/steam-arm-compatmap; SA_COMPATMAP_PY=$T/compatmap.py; SA_TMP=$T/tmp
game_home(){ echo \$R/home/tester; }; game_user(){ echo tester; }
acct_home(){ echo \$R/home/\$1; }; acct_run(){ shift; "\$@"; }; owner_user(){ echo tester; }; owner_home(){ echo \$R/home/tester; }
as_owner(){ "\$@"; }; as_root(){ "\$@"; }; need_root(){ return 0; }; steam_running(){ return 1; }
EOF
}
mkdir -p "$T/tmp"
mkh "$APP20" 20; mkh "$APP21" 21; mkh "$APP22" 22; mkh "$CFG" 23
ALL=setup,system-profiles,personal-profiles,compat-tools,fex,mangohud
# keep copies of the state the backups hold
mkdir -p "$T/orig"; cp "$R/etc/steam-arm/titles.conf" "$A/.config/steam-arm/titles.conf" "$A/.config/MangoHud/MangoHud.conf" "$T/orig/" 2>/dev/null
cp "$R/etc/steam-arm/titles.conf" "$T/orig/system-titles.conf"; cp "$A/.config/steam-arm/titles.conf" "$T/orig/personal-titles.conf"
cp -a "$A/.fex-emu/AppConfig" "$T/orig/fex"

for v in 20 21 22 23; do
  mkdir -p "$T/out$v"
  sed -i "s/^VERSION=.*/VERSION=${v:0:1}.${v:1}/" "$R/etc/steam-arm/steam-arm.conf"
  OUT=$(bash -c ". $T/h-$v.sh; bk_make $T/out$v $ALL tester; echo \"rc=\$? path=\$BK_PATH err=\$BK_ERR note=\$BK_NOTE\"" 2>&1)
  eval "B$v=\$(ls $T/out$v/*.tar.gz 2>/dev/null)"
  check "${v:0:1}.${v:1} bk_make: archive written" "grep -q 'rc=0' <<<\"\$OUT\" && [ -f \"\$B$v\" ]"
done
OUT=$(tar -tzf "$B20" | sort | paste -sd' ')
check "2.0 archive layout: manifest + 7 members under steam-arm-settings/, no directory entries" \
  "[ \"\$OUT\" = 'steam-arm-settings/manifest steam-arm-settings/personal/compattools.txt steam-arm-settings/personal/fex-appconfig/Game-x86_64.json steam-arm-settings/personal/fex-appconfig/hl2_linux.json steam-arm-settings/personal/mangohud/MangoHud.conf steam-arm-settings/personal/titles.conf steam-arm-settings/system/steam-arm.conf steam-arm-settings/system/titles.conf' ]"
OUT=$(tar -xOzf "$B20" steam-arm-settings/manifest)
check "2.0 manifest: FORMAT=1, VERSION=2.0, all parts" "grep -qx FORMAT=1 <<<\"\$OUT\" && grep -qx VERSION=2.0 <<<\"\$OUT\" && grep -qx 'PARTS=$ALL' <<<\"\$OUT\""
OUT=$(tar -tvzf "$B21" | awk '{print $2}' | sort -u)
check "2.1 archive: numeric owner 0/0 only" "[ \"\$OUT\" = 0/0 ]"

# restore each into a changed state with 2.3: replace mode, every part
restore(){ # $1 archive -> prints RS_PARTS / RS_SUM / rc of apply
  bash -c ". $T/h-23.sh
    rs_open '$1' || { echo \"OPEN-ERR \$RS_ERR\"; exit 1; }
    echo \"PARTS=\$RS_PARTS\"
    rs_plan \"\$RS_PARTS\" tester replace replace all all
    echo \"\$RS_SUM\"
    rs_apply; echo \"apply=\$?\"; rs_close" 2>&1
}
mutate(){
  printf '999 overlay=off\n' > "$R/etc/steam-arm/titles.conf"
  rm -f "$A/.config/steam-arm/titles.conf" "$A/.config/MangoHud/MangoHud.conf" "$A/.fex-emu/AppConfig/hl2_linux.json"
  sed -i 's/^GFX_DEFAULT=.*/GFX_DEFAULT=a/' "$R/etc/steam-arm/steam-arm.conf"
  sed -i 's#^PROVIDER_LOCAL_FILE=.*#PROVIDER_LOCAL_FILE=/srv/this-machine/archive.tar.zst#' "$R/etc/steam-arm/steam-arm.conf"
  python3 - "$A/.local/share/Steam/config/config.vdf" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
i = s.index('\t\t\t\t\t"400"'); j = s.index('\t\t\t\t\t"219150"')
open(p, "w").write(s[:i] + s[j:])
EOF
}
for v in 20 21 22 23; do
  mutate
  eval "B=\$B$v"
  OUT=$(restore "$B")
  n="${v:0:1}.${v:1}"
  check "$n archive: 2.3 opens it, all 6 parts" "grep -qx 'PARTS=$ALL' <<<\"\$OUT\""
  check "$n archive: apply rc 0" "grep -qx apply=0 <<<\"\$OUT\""
  check "$n archive: summary names backup version" "grep -q 'Steam ARM $n, GPU mali-csf-v10' <<<\"\$OUT\""
  check "$n archive: system and personal profiles back" "cmp -s $R/etc/steam-arm/titles.conf $T/orig/system-titles.conf && cmp -s $A/.config/steam-arm/titles.conf $T/orig/personal-titles.conf"
  check "$n archive: FEX and MangoHud files back" "cmp -s $A/.fex-emu/AppConfig/hl2_linux.json $T/orig/fex/hl2_linux.json && cmp -s $A/.config/MangoHud/MangoHud.conf $T/orig/MangoHud.conf"
  check "$n archive: GFX_DEFAULT back to b, machine keys not restored" "grep -qx GFX_DEFAULT=b $R/etc/steam-arm/steam-arm.conf && grep -q 'Not restored (state of this machine)' <<<\"\$OUT\""
  check "$n archive: PROVIDER_LOCAL_FILE of this machine kept, listed as not restored" "grep -qx 'PROVIDER_LOCAL_FILE=/srv/this-machine/archive.tar.zst' $R/etc/steam-arm/steam-arm.conf && sed -n '/Not restored (state of this machine)/,/^  [A-Z]/p' <<<\"\$OUT\" | grep -q PROVIDER_LOCAL_FILE"
  check "$n archive: compat tool for app 400 set again" "grep -q 'app 400 *-> proton_experimental' <<<\"\$OUT\" && grep -A2 '\"400\"' $A/.local/share/Steam/config/config.vdf | grep -q proton_experimental"
done

OUT=$(tar -xOzf "$B23" steam-arm-settings/manifest; tar -xOzf "$B23" steam-arm-settings/system/titles.conf)
check "2.3 archive: FORMAT=1, system profiles carry diskcache line" "grep -qx FORMAT=1 <<<\"\$OUT\" && grep -qx '100 diskcache=on multiblock=on' <<<\"\$OUT\""
for v in 20 21 22 23; do
  mutate; eval "B=\$B$v"; restore "$B" >/dev/null
  check "${v:0:1}.${v:1} archive: diskcache line restored into system profiles" "grep -qx '100 diskcache=on multiblock=on' $R/etc/steam-arm/titles.conf"
done

# AUTO_BUILD (2.3 setup key, in SA_BK_KEYS): 2.3 archive round-trips it; archives without it leave current value;
# 2.2 menu restoring a 2.3 archive leaves it out
setab(){ sed -i '/^AUTO_BUILD=/d' "$R/etc/steam-arm/steam-arm.conf"; [ -n "$1" ] && echo "AUTO_BUILD=$1" >> "$R/etc/steam-arm/steam-arm.conf"; }
abv(){ sed -n 's/^AUTO_BUILD=//p' "$R/etc/steam-arm/steam-arm.conf"; }
setab off; mkdir -p "$T/outab"
OUT=$(bash -c ". $T/h-23.sh; bk_make $T/outab $ALL tester; echo rc=\$?" 2>&1); BAB=$(ls "$T"/outab/*.tar.gz 2>/dev/null)
OUT="$OUT $(tar -xOzf "$BAB" steam-arm-settings/system/steam-arm.conf 2>&1)"
check "2.3 archive: carries AUTO_BUILD=off" "grep -qx AUTO_BUILD=off <<<\"\$OUT\""
for v in 20 21 22; do
  setab on; eval "B=\$B$v"; OUT=$(restore "$B")
  check "${v:0:1}.${v:1} archive (no AUTO_BUILD): current value on kept" "[ \"\$(abv)\" = on ] && grep -qx apply=0 <<<\"\$OUT\" && ! grep -q AUTO_BUILD <<<\"\$OUT\""
done
setab on; OUT=$(restore "$BAB")
check "2.3 archive restored by 2.3: AUTO_BUILD on -> off" "[ \"\$(abv)\" = off ] && grep -q 'AUTO_BUILD *on -> off' <<<\"\$OUT\""
setab ""; OUT=$(restore "$BAB")
check "2.3 archive restored by 2.3, key absent here: AUTO_BUILD=off written" "[ \"\$(abv)\" = off ]"
setab on
OUT=$(bash -c ". $T/h-22.sh
  rs_open '$BAB' || { echo \"OPEN-ERR \$RS_ERR\"; exit 1; }
  rs_plan \"\$RS_PARTS\" tester replace replace all all; echo \"\$RS_SUM\"; rs_apply; echo \"apply=\$?\"; rs_close" 2>&1)
check "2.3 archive restored by 2.2 menu: AUTO_BUILD left out (listed as not restored)" "[ \"\$(abv)\" = on ] && grep -qx apply=0 <<<\"\$OUT\" && sed -n '/Not restored/,\$p' <<<\"\$OUT\" | grep -q AUTO_BUILD"
setab ""

# CPU_NOTICE (2.3 setup key, in SA_BK_KEYS, absent = off): same rules as AUTO_BUILD
setcn(){ sed -i '/^CPU_NOTICE=/d' "$R/etc/steam-arm/steam-arm.conf"; [ -n "$1" ] && echo "CPU_NOTICE=$1" >> "$R/etc/steam-arm/steam-arm.conf"; }
cnv(){ sed -n 's/^CPU_NOTICE=//p' "$R/etc/steam-arm/steam-arm.conf"; }
setcn on; mkdir -p "$T/outcn"
OUT=$(bash -c ". $T/h-23.sh; bk_make $T/outcn $ALL tester; echo rc=\$?" 2>&1); BCN=$(ls "$T"/outcn/*.tar.gz 2>/dev/null)
OUT="$OUT $(tar -xOzf "$BCN" steam-arm-settings/system/steam-arm.conf 2>&1)"
check "2.3 archive: carries CPU_NOTICE=on" "grep -qx CPU_NOTICE=on <<<\"\$OUT\""
for v in 20 21 22; do
  setcn off; eval "B=\$B$v"; OUT=$(restore "$B")
  check "${v:0:1}.${v:1} archive (no CPU_NOTICE): current value off kept" "[ \"\$(cnv)\" = off ] && grep -qx apply=0 <<<\"\$OUT\" && ! grep -q CPU_NOTICE <<<\"\$OUT\""
done
setcn off; OUT=$(restore "$BCN")
check "2.3 archive restored by 2.3: CPU_NOTICE off -> on" "[ \"\$(cnv)\" = on ] && grep -q 'CPU_NOTICE *off -> on' <<<\"\$OUT\""
setcn ""; OUT=$(restore "$BCN")
check "2.3 archive restored by 2.3, key absent here: CPU_NOTICE=on written" "[ \"\$(cnv)\" = on ]"
setcn off
OUT=$(bash -c ". $T/h-22.sh
  rs_open '$BCN' || { echo \"OPEN-ERR \$RS_ERR\"; exit 1; }
  rs_plan \"\$RS_PARTS\" tester replace replace all all; echo \"\$RS_SUM\"; rs_apply; echo \"apply=\$?\"; rs_close" 2>&1)
check "2.3 archive restored by 2.2 menu: CPU_NOTICE left out (listed as not restored)" "[ \"\$(cnv)\" = off ] && grep -qx apply=0 <<<\"\$OUT\" && sed -n '/Not restored/,\$p' <<<\"\$OUT\" | grep -q CPU_NOTICE"
setcn ""

# CLIENT, CLIENT_SET, CLIENT_PROBE (2.3 machine state: CPU-bound client type, not in SA_BK_KEYS): never restored
SC=$R/etc/steam-arm/steam-arm.conf
setcl(){ sed -i '/^CLIENT=/d; /^CLIENT_SET=/d; /^CLIENT_PROBE=/d' "$SC"; [ -n "$1" ] && printf 'CLIENT=%s\nCLIENT_SET=%s\nCLIENT_PROBE=%s\n' "$1" "$2" "$3" >> "$SC"; }
clv(){ printf '%s,%s,%s' "$(sed -n 's/^CLIENT=//p' "$SC")" "$(sed -n 's/^CLIENT_SET=//p' "$SC")" "$(sed -n 's/^CLIENT_PROBE=//p' "$SC")"; }
setcl x86 auto 1788652215:lse; mkdir -p "$T/outcl"
OUT=$(bash -c ". $T/h-23.sh; bk_make $T/outcl $ALL tester; echo rc=\$?" 2>&1); BCL=$(ls "$T"/outcl/*.tar.gz 2>/dev/null)
OUT="$OUT $(tar -xOzf "$BCL" steam-arm-settings/system/steam-arm.conf 2>&1)"
check "2.3 archive of x86 client machine: settings file copy holds CLIENT keys, format unchanged" "grep -qx CLIENT=x86 <<<\"\$OUT\" && grep -qx CLIENT_SET=auto <<<\"\$OUT\" && [ \"\$(tar -xOzf '$BCL' steam-arm-settings/manifest | sed -n 's/^FORMAT=//p')\" = 1 ]"
setcl arm64 auto ""; OUT=$(restore "$BCL")
check "2.3 x86 archive restored on native machine: CLIENT keys untouched, listed as not restored" "[ \"\$(clv)\" = 'arm64,auto,' ] && grep -qx apply=0 <<<\"\$OUT\" && sed -n '/Not restored (state of this machine)/,/^  [A-Z]/p' <<<\"\$OUT\" | grep -q 'CLIENT'"
setcl ""; OUT=$(restore "$BCL")
check "2.3 x86 archive restored where keys are absent: none written" "[ \"\$(clv)\" = ',,' ] && grep -qx apply=0 <<<\"\$OUT\""
for v in 20 21 22; do
  setcl x86 user ""; eval "B=\$B$v"; OUT=$(restore "$B")
  check "${v:0:1}.${v:1} archive on x86 client machine: CLIENT keys kept" "[ \"\$(clv)\" = 'x86,user,' ] && grep -qx apply=0 <<<\"\$OUT\""
done
setcl arm64 auto ""
OUT=$(bash -c ". $T/h-22.sh
  rs_open '$BCL' || { echo \"OPEN-ERR \$RS_ERR\"; exit 1; }
  rs_plan \"\$RS_PARTS\" tester replace replace all all; echo \"\$RS_SUM\"; rs_apply; echo \"apply=\$?\"; rs_close" 2>&1)
check "2.3 x86 archive restored by 2.2 menu: CLIENT keys untouched" "[ \"\$(clv)\" = 'arm64,auto,' ] && grep -qx apply=0 <<<\"\$OUT\""
setcl ""

# GE-Proton mapping (2.3 optional tool in compatibilitytools.d): same archive format, hint when build is not installed
V=$A/.local/share/Steam/config/config.vdf; GD=$A/.local/share/Steam/compatibilitytools.d/GE-Proton11-7-aarch64
cp "$V" "$T/vdf.orig"
sed -i 's/\t\t\t\t\t"219150"/\t\t\t\t\t"500"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"GE-Proton11-7-aarch64"\n\t\t\t\t\t}\n&/' "$V"
mkdir -p "$T/outge"
OUT=$(bash -c ". $T/h-23.sh; bk_make $T/outge compat-tools tester; echo rc=\$?" 2>&1); BGE=$(ls "$T"/outge/*.tar.gz 2>/dev/null)
OUT="$OUT $(tar -xOzf "$BGE" steam-arm-settings/personal/compattools.txt 2>&1)"
check "2.3 archive: GE-Proton mapping stored as appid tool line" "grep -qx '500 GE-Proton11-7-aarch64' <<<\"\$OUT\""
cp "$T/vdf.orig" "$V"
OUT=$(restore "$BGE")
check "GE-Proton build not installed: mapping left out, hint names Maintenance > GE-Proton (ARM64)" "grep -q 'Tool not installed, left out' <<<\"\$OUT\" && grep -q '500:GE-Proton11-7-aarch64' <<<\"\$OUT\" && grep -q 'GE-Proton builds: install from Maintenance > GE-Proton (ARM64), then restore again.' <<<\"\$OUT\" && ! grep -q '\"500\"' '$V'"
mkdir -p "$GD"; printf '"compatibilitytools"\n{\n  "compat_tools"\n  {\n    "GE-Proton11-7-aarch64"\n    {\n    }\n  }\n}\n' > "$GD/compatibilitytool.vdf"
OUT=$(restore "$BGE")
check "GE-Proton build installed: mapping set, no hint" "grep -q 'app 500 *-> GE-Proton11-7-aarch64' <<<\"\$OUT\" && ! grep -q 'GE-Proton builds: install' <<<\"\$OUT\" && grep -A2 '\"500\"' '$V' | grep -q GE-Proton11-7-aarch64"
rm -rf "$A/.local/share/Steam/compatibilitytools.d"; cp "$T/vdf.orig" "$V"
OUT=$(bash -c ". $T/h-22.sh
  rs_open '$BGE' || { echo \"OPEN-ERR \$RS_ERR\"; exit 1; }
  rs_plan \"\$RS_PARTS\" tester replace replace all all; echo \"\$RS_SUM\"; rs_close" 2>&1)
check "2.3 archive with GE mapping read by 2.2 menu: same format, mapping left out as not installed" "grep -q '500:GE-Proton11-7-aarch64' <<<\"\$OUT\" && ! grep -q OPEN-ERR <<<\"\$OUT\""
for v in 20 21 22; do
  eval "B=\$B$v"; OUT=$(restore "$B"); cp "$T/vdf.orig" "$V"
  check "${v:0:1}.${v:1} archive: no GE-Proton hint" "grep -qx apply=0 <<<\"\$OUT\" && ! grep -q 'GE-Proton' <<<\"\$OUT\""
done

# hand-made format-1 archives (python tarfile), and hostile ones
python3 - "$T/arc" <<'EOF'
import io, os, sys, tarfile
d = sys.argv[1]; os.makedirs(d)
TOP = "steam-arm-settings/"
MAN = b"FORMAT=1\nVERSION=2.0\nDATE=2026-09-30T10:00:00Z\nGPU_FAMILY=mali-csf-v10\nPARTS=system-profiles,personal-profiles\n"
def mk(name, members, fmt=tarfile.GNU_FORMAT):
    with tarfile.open(os.path.join(d, name + ".tar.gz"), "w:gz", format=fmt) as t:
        for m in members:
            n, data, kind = (m + (None,))[:3] if len(m) == 2 else m
            ti = tarfile.TarInfo(n); ti.mtime = 1759226400; ti.mode = 0o644
            if kind == "dir": ti.type = tarfile.DIRTYPE; ti.mode = 0o755; t.addfile(ti); continue
            if kind == "sym": ti.type = tarfile.SYMTYPE; ti.linkname = data; t.addfile(ti); continue
            if kind == "hard": ti.type = tarfile.LNKTYPE; ti.linkname = data; t.addfile(ti); continue
            if kind == "fifo": ti.type = tarfile.FIFOTYPE; t.addfile(ti); continue
            ti.size = len(data); t.addfile(ti, io.BytesIO(data))
ok = [(TOP + "manifest", MAN), (TOP + "system/titles.conf", b"100 overlay=off\n"), (TOP + "personal/titles.conf", b"200 gfx=a\n")]
mk("good", ok)
mk("good-dirs", [(TOP, None, "dir"), (TOP + "system/", None, "dir"), (TOP + "personal/", None, "dir")] + ok)
mk("good-pax", ok, tarfile.PAX_FORMAT)
mk("badjson", ok[:2] + [(TOP + "personal/fex-appconfig/a.json", b"{not json"), (TOP + "personal/fex-appconfig/b.json", b"{}")])
mk("dotdot", ok + [(TOP + "../evil", b"x")])
mk("dotdot2", ok + [(TOP + "system/../../evil.conf", b"x")])
mk("absolute", ok + [("/tmp/evil", b"x")])
mk("symlink", ok + [(TOP + "personal/mangohud/MangoHud.conf", "/etc/passwd", "sym")])
mk("hardlink", ok + [(TOP + "personal/mangohud/MangoHud.conf", "/etc/passwd", "hard")])
mk("fifo", ok + [(TOP + "personal/mangohud/MangoHud.conf", None, "fifo")])
mk("duplicate", ok + [(TOP + "system/titles.conf", b"666 overlay=off\n")])
mk("oversize", ok + [(TOP + "personal/mangohud/big.conf", b"\0" * (1048576 + 1))])
mk("total", ok + [(TOP + "personal/mangohud/m%d.conf" % i, b"a" * 1048576) for i in range(9)])
mk("count", ok + [(TOP + "personal/mangohud/m%d.conf" % i, b"fps\n") for i in range(400)])
mk("nomanifest", ok[1:])
mk("format2", [(TOP + "manifest", MAN.replace(b"FORMAT=1", b"FORMAT=2"))] + ok[1:])
mk("noformat", [(TOP + "manifest", MAN.replace(b"FORMAT=1\n", b""))] + ok[1:])
mk("otherdir", ok + [("other/manifest", MAN)])
mk("badname", ok + [(TOP + "personal/fex-appconfig/.hidden.json", b"{}")])
mk("unknown", ok + [(TOP + "system/passwd", b"x")])
mk("noparts", [(TOP + "manifest", MAN.replace(b"PARTS=system-profiles,personal-profiles", b"PARTS="))] + ok[1:])
with open(os.path.join(d, "notgz.tar.gz"), "wb") as f: f.write(b"plain text, no archive\n")
with open(os.path.join(d, "huge.tar.gz"), "wb") as f: f.write(os.urandom(1048577))
EOF
ro(){ bash -c ". $T/h-23.sh; if rs_open '$T/arc/$1.tar.gz'; then echo \"OPEN parts=\$RS_PARTS note=\$RS_NOTE\"; ls -A \"\$RS_D\" | head -n 3; rs_close; else echo \"REFUSED \$RS_ERR\"; fi" 2>&1; }
OUT=$(ro good); check "hand-made 2.0-style archive opens (system + personal profiles)" "grep -q 'OPEN parts=system-profiles,personal-profiles' <<<\"\$OUT\""
OUT=$(ro good-dirs); check "archive with directory entries opens" "grep -q 'OPEN parts=system-profiles,personal-profiles' <<<\"\$OUT\""
OUT=$(ro good-pax); check "PAX-format archive opens" "grep -q '^OPEN' <<<\"\$OUT\""
OUT=$(ro badjson); check "invalid FEX JSON dropped with note, rest kept" "grep -q 'OPEN parts=system-profiles' <<<\"\$OUT\" && grep -q 'note= a.json' <<<\"\$OUT\""
for c in "dotdot:unexpected member" "dotdot2:unexpected member" "absolute:unexpected member" "symlink:link or special file" \
         "hardlink:link or special file" "fifo:link or special file" "duplicate:appears twice" "oversize:too large" \
         "total:holds too much" "count:holds too much" "nomanifest:no manifest" "format2:format 2 is newer" \
         "noformat:no format version" "otherdir:unexpected member" "badname:unexpected member" "unknown:unexpected member" \
         "noparts:holds no usable part" "notgz:not a readable .tar.gz" "huge:too large for a settings backup"; do
  OUT=$(ro "${c%%:*}")
  check "hostile ${c%%:*}: refused (${c#*:})" "grep -q '^REFUSED.*${c#*:}' <<<\"\$OUT\""
done
check "nothing escaped the unpack folder" "[ ! -e $T/evil ] && [ ! -e /tmp/evil ] && [ ! -e $T/tmp/evil.conf ]"
check "temporary folders cleaned after refusals" "[ -z \"\$(ls -A $T/tmp)\" ]"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
