#!/bin/bash
# 3.0 E4: Raspberry Pi OS host Mesa 26.2.2 (+rpt, newer than driver archive 26.1.8). legacy_mesa_restore on a fake
# x86-64 RootFS in the pre-release layout puts distro Mesa back and leaves the host's Pi archive Mesa alone; settings
# menu mesa_ver and handler mesa_version read the +rpt version. Fixtures in fixtures/pios-mesa-rpt. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST CFG=$SARM_CFG
FX=$(cd "$(dirname "$0")" && pwd)/fixtures/pios-mesa-rpt
T=$(mktemp -d /tmp/sarm30-mesa.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 ~ /}$/ && $0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }
has(){ grep -qF -- "$1" <<<"$OUT"; }
for f in warn gp_list_json gp_list_write legacy_mesa_restore parent_in unlink_in paths_inside; do fn "$f" "$INST"; done > "$T/funcs.sh"
check "functions extracted, parse" "[ \$(grep -c '^[a-z_]*(){' '$T/funcs.sh') = 7 ] && bash -n '$T/funcs.sh'"

# host: Pi archive Mesa; RootFS: archive 26.1.8 laid over it, distro Mesa saved in PSTATE (pre-release layout)
H=$T/root RFS=$T/root/opt/fex-rootfs/Ubuntu_24_04; PSTATE=$RFS/.steam-arm-fex-mesa
mk(){ mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" > "$1"; }
while read -r p; do mk "$H/$p" "pios 26.2.2-1~bpo13+0~rpt1 $p"; done < "$FX/host-mesa.files"
mkdir -p "$T/distro"; while read -r p; do mk "$T/distro/$p" "ubuntu distro mesa $p"; done < "$FX/rfs-distro-mesa.list"
mkdir -p "$PSTATE"; tar -cf "$PSTATE/distro-mesa.tar" -C "$T/distro" $(cat "$FX/rfs-distro-mesa.list")
while read -r p; do mk "$RFS/$p" "archive 26.1.8 $p"; done < "$FX/rfs-archive-26.1.8.list"
cp "$FX/rfs-archive-26.1.8.list" "$PSTATE/installed.list"
# escape attempt in the saved list: host Pi Mesa must stay
echo "../../../usr/lib/aarch64-linux-gnu/libgallium-26.2.2-1~bpo13+0~rpt1.so" >> "$PSTATE/installed.list"
echo '{"graphics_provider_v0": {"path": "pre-release"}}' > "$RFS/graphics_provider.json"
host_sum(){ (cd "$H" && find . -path ./opt -prune -o -type f -print0 | sort -z | xargs -0 sha256sum); }
host_sum > "$T/host.before"
OUT=$(RFS=$RFS PSTATE=$PSTATE; . "$T/funcs.sh"; legacy_mesa_restore 2>&1; echo "rc=$?")
check "M1 restore: rc 0, reported" "has rc=0 && has 'distro Mesa restored in the x86-64 root filesystem'"
miss=; while read -r p; do grep -qxF "$p" "$FX/rfs-distro-mesa.list" || { [ -e "$RFS/$p" ] && miss="$miss $p"; }; done < "$FX/rfs-archive-26.1.8.list"
OUT=$miss; check "M2 archive 26.1.8 files gone from RootFS" "[ -z \"\$miss\" ]"
bad=; while read -r p; do grep -qxF "ubuntu distro mesa $p" "$RFS/$p" 2>/dev/null || bad="$bad $p"; done < "$FX/rfs-distro-mesa.list"
OUT=$bad; check "M3 distro Mesa back, files shared with archive (libdril_dri.so) hold distro content" "[ -z \"\$bad\" ]"
OUT=$(cat "$RFS/graphics_provider.json" 2>&1)
check "M4 graphics_provider.json list form" "[ \"\$OUT\" = \"\$(. '$T/funcs.sh'; gp_list_json)\" ]"
check "M5 pre-release state folder removed" "[ ! -e '$PSTATE' ]"
OUT=$(diff "$T/host.before" <(host_sum)); check "M6 host Pi archive Mesa 26.2.2 files unchanged (escape in saved list refused)" "[ -z \"\$OUT\" ] && [ -f '$H/usr/lib/aarch64-linux-gnu/libgallium-26.2.2-1~bpo13+0~rpt1.so' ]"
OUT=$(RFS=$RFS PSTATE=$PSTATE; . "$T/funcs.sh"; legacy_mesa_restore 2>&1; echo "rc=$?")
check "M7 second run: nothing to do, rc 0" "[ \"\$OUT\" = rc=0 ]"

# settings menu report: package version of host Mesa (no glxinfo answer)
mkdir -p "$T/stub"
printf '#!/bin/sh\nexit 1\n' > "$T/stub/glxinfo"
cat > "$T/stub/dpkg-query" <<'EOF'
#!/bin/sh
# answers -W -f='${Version}\n' PKG... from the fixture status
shift 2
for p; do awk -v p="$p" -v RS= '$0 ~ "(^|\n)Package: " p "\n" { if (match($0, /Version: [^\n]*/)) print substr($0, RSTART + 9, RLENGTH - 9) }' "$FXS"; done
EOF
chmod 755 "$T/stub/"*
{ fn have "$CFG"; fn pkg_ver "$CFG"; fn mesa_ver "$CFG"; } > "$T/menu.sh"
OUT=$(FXS=$FX/host-mesa.status PATH="$T/stub:$PATH" bash -c ". '$T/menu.sh'; mesa_ver" 2>&1)
check "M8 settings menu mesa_ver: 26.2.2-1~bpo13+0~rpt1 from package database" "[ \"\$OUT\" = '26.2.2-1~bpo13+0~rpt1' ]"

# handler run record: Mesa version from libgallium file name; host (forwarding) vs second tree (archive)
mkdir -p "$T/mali/usr/lib/x86_64-linux-gnu"; : > "$T/mali/usr/lib/x86_64-linux-gnu/libgallium-26.1.8.so"
OUT=$(python3 - "$INST" "$H" "$T/mali" "$T/none" <<'PY' 2>&1
import glob, os, re, sys
src = open(sys.argv[1]).read()
m = re.search(r"^def mesa_version\(root=\"\"\):\n(?:    .*\n|\n)+", src, re.M)
ns = {"glob": glob, "os": os, "re": re}
exec(m.group(0), ns)
print(" ".join(ns["mesa_version"](r) for r in sys.argv[2:]))
PY
)
check "M9 handler mesa_version: Pi host 26.2.2, second tree 26.1.8, none unknown" "[ \"\$OUT\" = '26.2.2 26.1.8 unknown' ]"
echo "mesa rpt 3.0: $pass pass, $fail fail"
[ "$fail" = 0 ]
