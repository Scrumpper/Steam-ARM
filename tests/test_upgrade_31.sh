#!/bin/bash
# 3.1 upgrade, snapshots, rollback, pruning, downgrade protection. Settings menu sourced by tests/upgrade/uh.sh with every
# system path under a fake root; GitHub API and asset downloads served by tests/upgrade/mockgh.py on 127.0.0.1; setup
# stand-ins from tests/upgrade/mkrel.sh (3.0 style and 3.1 style, which calls --setup-begin/--setup-end). Installer side
# checked by extracted blocks. No root, no network beyond 127.0.0.1. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
U=$SARM_TESTS/upgrade
T=$(mktemp -d /tmp/sarm31-up.XXXXXX)
MP=""
trap '[ -n "$MP" ] && kill "$MP" 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
has(){ grep -qF -- "$1" <<<"$OUT"; }
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }
export UHR=$T/r UH=$U/uh.sh UH_FIX=$U/mkrel.sh SARM_CFG UH_SRC=$CFG
. "$U/mkrel.sh"
R=$UHR M=$T/m
mkdir -p "$M/assets"
python3 "$U/mockgh.py" "$M" & MP=$!
for _ in $(seq 1 50); do [ -f "$M/port" ] && break; sleep 0.1; done
export UH_PORT; UH_PORT=$(cat "$M/port" 2>/dev/null)
check "mock GitHub server up" "[ -n '$UH_PORT' ]"
uh(){ OUT=$(PATH="$R/pbin:$PATH" bash "$UH" "$@" 2>&1); RC=$?; }
ue(){ OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$1" bash "$UH" 2>&1); RC=$?; }
mode(){ echo "$1" > "$M/mode"; }
reqs(){ wc -l < "$M/requests" 2>/dev/null || echo 0; }
# fresh fake root with version $1 installed by its setup stand-in (PROTO $2)
fresh(){
  rm -rf "$R"; mkdir -p "$R/etc/steam-arm" "$R/bin" "$R/share" "$R/home/tester/.fex-emu" "$R/pbin" "$R/pkg" "$R/run"
  printf 'GAMEUSER=tester\nARMHOME_DIR=.local/share/steam-arm\nCOMPONENTS_ON=desktop,tray\nGFX_DEFAULT=auto\nVERSION=\n' > "$R/etc/steam-arm/steam-arm.conf"
  echo '400 gfx=a' > "$R/etc/steam-arm/titles.conf"
  printf '#!/bin/sh\necho launcher\n' > "$R/bin/steam-arm"; chmod 755 "$R/bin/steam-arm"
  echo '{"Config":{}}' > "$R/home/tester/.fex-emu/Config.json"
  fx_setup "$1" "$2" "$T/setup-$1.sh"; bash "$T/setup-$1.sh" --keep >/dev/null
  rm -f "$R/setup.log"
}
rel(){ rm -f "$M/assets/"*; fx_zip "$1" "$2" "$M/assets"; fx_release "$1" "$M" "$UH_PORT" "${3:-}"; mode ok; }
snaps(){ find "$R/lib/snapshots" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | wc -l; }
cv(){ sed -n 's/^VERSION=//p' "$R/etc/steam-arm/steam-arm.conf"; }

# ---------- U1 check ----------
fresh 3.0 0; rel 3.1 1
uh upgrade --check
check "U1 newer release: rc 0, version, upgrade command named" "[ $RC = 0 ] && has 'Newer release: Steam ARM 3.1 (installed: 3.0).' && has 'sudo steam-arm-config upgrade' && ! has 'steam-arm-install.sh --keep'"
check "U1 result stored (release-check: TAG, VERSION, SIZE, DIGEST, CHECKED)" "f=\$(ls $R/ucache/release-check $R/lib/release-check 2>/dev/null | head -1); grep -q '^TAG=steam-arm-v3.1\$' \"\$f\" && grep -q '^VERSION=3.1\$' \"\$f\" && grep -qE '^SIZE=[1-9]' \"\$f\" && grep -qE '^DIGEST=[0-9a-f]{64}\$' \"\$f\" && grep -qE '^CHECKED=[0-9]+\$' \"\$f\""
check "U1 check downloads nothing" "! grep -q '^/dl/' $M/requests"
rel 3.0 0; uh upgrade --check
check "U1 same version: rc 1, newest" "[ $RC = 1 ] && has 'Steam ARM 3.0 is the newest release.'"
rel 2.9 0; uh upgrade --check
check "U1 older release: rc 1, installed is newer" "[ $RC = 1 ] && has 'Steam ARM 3.0 is newer than the newest release (2.9).'"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["tag_name"]="steam-arm-v3.0-hotfix"; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
uh upgrade --check
check "U1 hotfix tag of same version: newer, full tag" "[ $RC = 0 ] && has 'Newer release: Steam ARM 3.0-hotfix (installed: 3.0).'"
for c in 403 429; do mode $c; uh upgrade --check
  check "U1 HTTP $c: rc 2, request limit" "[ $RC = 2 ] && has 'request limit'"; done
mode 404; uh upgrade --check; check "U1 HTTP 404: rc 2, no published release" "[ $RC = 2 ] && has 'No published release'"
mode 500; uh upgrade --check; check "U1 HTTP 500: rc 2, status named" "[ $RC = 2 ] && has 'HTTP 500'"
mode badjson; uh upgrade --check; check "U1 bad JSON: rc 2, not understood" "[ $RC = 2 ] && has 'not understood'"
OUT=$(PATH="$R/pbin:$PATH" UH_PORT=1 bash "$UH" upgrade --check 2>&1); RC=$?
check "U1 offline (code 000): rc 2, could not be reached, --file named" "[ $RC = 2 ] && has 'could not be reached' && has 'upgrade --file ZIP'"
mode 403; uh update-check; check "U1 update-check alias keeps 2.x exit status (failure -> 1)" "[ $RC = 1 ] && has 'request limit'"

# ---------- U2 notice, no network at menu start ----------
fresh 3.0 0; rel 3.1 1; uh upgrade --check
ue 'up_notice'
check "U2 main screen line from stored check" "has 'Steam ARM 3.1 available (checked ' && has 'Maintenance > Upgrade to newest release.'"
ue 'ui_menu(){ printf "MENU %s\n" "$*" >&2; return 1; }; menu_maintenance'
check "U2 Maintenance item 13 names newer release; 14, 16, 17 shown; 15 hidden without snapshot" "has '13 Upgrade to newest release (3.1)' && has '14 Show what is new' && has '16 Previous versions kept (now: 2)' && has '17 Check for new release when this menu opens (now: off)' && ! has '15 Go back'"
check "U2 items 1 to 12 keep their tags and order" "grep -q '7 Check for new version 8 Caches (sizes, clear FEX code caches) 9 GE-Proton' <<<\"\$OUT\" && grep -q '11 Report how last game ran 12 Run history (now: off) 13 ' <<<\"\$OUT\""
sed -i 's/^VERSION=.*/VERSION=3.1/' "$R/etc/steam-arm/steam-arm.conf"; ue 'up_notice'
check "U2 line hidden once installed version reaches stored one" "[ -z \"\$OUT\" ]"
sed -i 's/^VERSION=.*/VERSION=3.0/' "$R/etc/steam-arm/steam-arm.conf"
n0=$(reqs); ue 'up_check_open'
check "U2 setting off (default): no request at menu start" "[ \$(reqs) = $n0 ]"
echo UPDATE_CHECK_ON_OPEN=on >> "$R/etc/steam-arm/steam-arm.conf"
n0=$(reqs); ue 'up_check_open'
check "U2 setting on, last check under 24 h: no request" "[ \$(reqs) = $n0 ]"
for f in "$R"/ucache/release-check "$R"/lib/release-check; do [ -f "$f" ] && sed -i 's/^CHECKED=.*/CHECKED=1000/' "$f"; done
n0=$(reqs); ue 'up_check_open'
check "U2 setting on, check older than 24 h: one request, result stored" "[ \$(reqs) = \$(( $n0 + 1 )) ] && ! grep -qs '^CHECKED=1000\$' $R/ucache/release-check $R/lib/release-check"
check "U2 menu start runs only stored-result check (up_check_open), at most once" "fn menu_main '$CFG' | grep -q '^  up_check_open\$' && [ \$(grep -c 'up_check_open' '$CFG') = 2 ]"
check "U2 open check: 8 s limit, 24 h spacing" "fn up_check_open '$CFG' | grep -q 'update_check 8' && fn up_check_open '$CFG' | grep -q 86400"
uh update-check-on-open off; check "U2 update-check-on-open off written" "grep -q '^UPDATE_CHECK_ON_OPEN=off\$' $R/etc/steam-arm/steam-arm.conf"
uh update-check-on-open bogus; check "U2 update-check-on-open refuses other values" "[ $RC = 2 ]"

# ---------- U3 download and checks ----------
fresh 3.0 0; rel 3.1 1; mode truncate
uh upgrade --yes
check "U3 transfer cut short: rc 2, incomplete, nothing installed, staging gone" "[ $RC = 2 ] && has 'Download incomplete' && [ \"\$(cv)\" = 3.0 ] && [ -z \"\$(ls -A $R/cache/upgrade 2>/dev/null)\" ] && [ ! -f $R/setup.log ]"
rel 3.1 1; echo "$(printf '0%.0s' $(seq 1 64))  Steam.ARM.3.1.zip" > "$M/assets/Steam.ARM.3.1.zip.sha256"; fx_release 3.1 "$M" "$UH_PORT" none
uh upgrade --yes
check "U3 sidecar hash wrong: rc 2, checksum text, nothing installed" "[ $RC = 2 ] && has 'Checksum of Steam.ARM.3.1.zip does not match its .sha256 file. Nothing was installed.' && [ \"\$(cv)\" = 3.0 ]"
rel 3.1 1; sed -i 's/Steam.ARM.3.1.zip$/other.zip/' "$M/assets/Steam.ARM.3.1.zip.sha256"; fx_release 3.1 "$M" "$UH_PORT"
uh upgrade --yes
check "U3 sidecar names other file: rc 2, form text" "[ $RC = 2 ] && has 'not in the expected form' && [ \"\$(cv)\" = 3.0 ]"
rel 3.1 1 "sha256:$(printf 'a%.0s' $(seq 1 64))"
uh upgrade --yes
check "U3 GitHub digest differs from sidecar and zip: rc 2" "[ $RC = 2 ] && has 'does not match' && [ \"\$(cv)\" = 3.0 ]"
rel 3.1 1; mode dl404; uh upgrade --yes
check "U3 asset 404: rc 2, release has no installer zip" "[ $RC = 2 ] && has 'Release 3.1 has no installer zip'"
rel 3.1 1; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["assets"]=[]; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
uh upgrade --yes; check "U3 release without zip asset: rc 2" "[ $RC = 2 ] && has 'has no installer zip'"
rel 3.1 1; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["assets"][0]["browser_download_url"]="https://evil.example/Steam.ARM.3.1.zip"; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
uh upgrade --yes; check "U3 download address outside release downloads refused" "[ $RC = 2 ] && has 'has no installer zip' && ! grep -q evil $M/requests"
check "U3 curl: HTTPS only (proto and redirects), 32 MB cap, retries, time limit" "grep -q '^SA_CURL_PROTO=(--proto \"=https\" --proto-redir \"=https\")\$' '$CFG' && fn up_get '$CFG' | grep -q -- '--max-filesize \"\$SA_ZIP_MAX\" --retry 2 --max-time 300' && grep -q '^SA_ZIP_MAX=33554432\$' '$CFG'"
check "U3 release downloads only below project's release path" "grep -q '^SA_DL_PREFIX=https://github.com/Scrumpper/Steam-ARM/releases/download/\$' '$CFG'"
# low disk: free space function reports 1 MB
rel 3.1 1; ue 'free_mb(){ echo 1; }; up_run 1 "" 0'
check "U3 low disk: rc 2, path and both numbers named, nothing downloaded" "[ $RC = 2 ] && has 'Not enough free space: $R/cache has 1 MB, upgrade needs' && ! grep -q '/dl/.*zip\$' <(tail -3 $M/requests)"
# ---------- U4 unpack rules ----------
Z=$T/z; mkdir -p "$Z"
mkz(){ python3 -I - "$Z/$1.zip" "$2" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w"); kind = sys.argv[2]; top = "Steam ARM 3.1/"
ok = "#!/bin/bash\nSA_VERSION=3.1\nSA_VERSION=3.1\n"
if kind == "dotdot": z.writestr(top + "../evil", "x")
elif kind == "abs": z.writestr("/etc/evil", "x")
elif kind == "link":
    i = zipfile.ZipInfo(top + "steam-arm-install.sh"); i.external_attr = (0o120777 << 16); z.writestr(i, "/etc/passwd")
elif kind == "noinst": z.writestr(top + "README.md", "x")
elif kind == "wrongver": z.writestr(top + "steam-arm-install.sh", ok.replace("3.1", "3.0"))
elif kind == "syntax": z.writestr(top + "steam-arm-install.sh", ok + "if then fi (\n")
elif kind == "many":
    z.writestr(top + "steam-arm-install.sh", ok)
    for n in range(70): z.writestr(top + "f%d" % n, "x")
elif kind == "outside": z.writestr("Other/steam-arm-install.sh", ok)
elif kind == "good": z.writestr(top + "steam-arm-install.sh", ok)
PY
}
for k in dotdot abs link noinst wrongver syntax many outside good; do
  mkz "$k" "$k"; rm -rf "$Z/x-$k"; ue "up_extract '$Z/$k.zip' '$Z/x-$k' 3.1"; eval "R_$k=\$RC O_$k=\$OUT"
done
check "U4 member with .. refused" "[ \$R_dotdot = 2 ] && grep -q 'could not be unpacked completely' <<<\"\$O_dotdot\" && [ ! -e '$Z/evil' ]"
check "U4 absolute member refused" "[ \$R_abs = 2 ]"
check "U4 link member refused" "[ \$R_link = 2 ] && [ ! -L '$Z/x-link/Steam ARM 3.1/steam-arm-install.sh' ]"
check "U4 missing installer refused" "[ \$R_noinst = 2 ] && grep -q '(steam-arm-install.sh)' <<<\"\$O_noinst\""
check "U4 wrong SA_VERSION refused" "[ \$R_wrongver = 2 ] && grep -q 'SA_VERSION of steam-arm-install.sh is not 3.1' <<<\"\$O_wrongver\""
check "U4 installer that does not parse refused" "[ \$R_syntax = 2 ] && grep -q 'does not parse' <<<\"\$O_syntax\""
check "U4 more than 64 members refused" "[ \$R_many = 2 ]"
check "U4 member outside top folder refused" "[ \$R_outside = 2 ]"
check "U4 good zip unpacked" "[ \$R_good = 0 ] && [ -f '$Z/x-good/Steam ARM 3.1/steam-arm-install.sh' ]"

# ---------- U5 upgrade 3.0 -> 3.1 ----------
fresh 3.0 0; echo SNAPSHOT_KEEP=3 >> "$R/etc/steam-arm/steam-arm.conf"; rel 3.1 1
uh upgrade
check "U5 without --yes and without terminal: asks for --yes, nothing changed" "[ $RC = 1 ] && has 'add --yes' && [ \"\$(cv)\" = 3.0 ]"
touch "$R/steam-running"; uh upgrade --yes
check "U5 Steam running: rc 3, refused before download" "[ $RC = 3 ] && has 'Steam ARM is running' && [ \"\$(cv)\" = 3.0 ]"; rm -f "$R/steam-running"
mkdir -p "$R/run"; ( flock "$R/run/steam-arm-setup.lock" sleep 3 ) & LP=$!; sleep 0.3
uh upgrade --yes; wait "$LP"
check "U5 setup running (lock held): rc 3" "[ $RC = 3 ] && has 'Another setup run is in progress.'"
uh upgrade --yes
check "U5 upgrade: rc 0, installed message names previous version" "[ $RC = 0 ] && has 'Steam ARM 3.1 installed. Previous version 3.0 kept (Maintenance > Go back to previous version).'"
check "U5 VERSION 3.1, installed copy and menu of 3.1" "[ \"\$(cv)\" = 3.1 ] && grep -qx 'SA_VERSION=3.1' $R/share/steam-arm-install.sh && grep -qx 'SA_VERSION=3.1' $R/bin/steam-arm-config"
check "U5 setup of new version got --keep only" "grep -qx 'setup 3.1 --keep' $R/setup.log"
S30=$(ls "$R/lib/snapshots" | head -1)
ue 'snap_rows'
check "U5 one snapshot of 3.0, verified, reason names upgrade" "[ \$(snaps) = 1 ] && grep -qP '^3\\.0-[0-9]{8}T[0-9]{6}Z\\t3\\.0\\t[0-9-]{10}\\tupgrade 3\\.1\\t[0-9.]+ MB\\tverified\$' <<<\"\$OUT\""
D30=$R/lib/snapshots/$S30
check "U5 snapshot members: installer, menu, etc, files, paths, settings, MANIFEST and its sha" "for m in installer.sh config.sh etc.tar.gz files.tar.gz paths.txt settings.tar.gz MANIFEST MANIFEST.sha256; do [ -f '$D30/'\$m ] || exit 1; done"
check "U5 snapshot installer is 3.0 copy, settings by 3.0 menu" "grep -qx 'SA_VERSION=3.0' $D30/installer.sh && grep -qx SETTINGS=yes $D30/MANIFEST && zcat $D30/settings.tar.gz | grep -qx 'settings of 3.0'"
check "U5 paths.txt: present lines with mode and sha256 (space in name, link, glob), absent line, home file" "grep -qE '^present [0-7]{3} [0-9a-f]{64} $R/sys/rules/with space.rules\$' $D30/paths.txt && grep -q '^present 777 [0-9a-f]* $R/sys/nopkg/apt-get\$' $D30/paths.txt && grep -q 'icons/64x64/apps/steam-arm.png\$' $D30/paths.txt && grep -qx 'absent $R/sys/absent.rules' $D30/paths.txt && grep -q '/home/tester/.fex-emu/Config.json\$' $D30/paths.txt"
check "U5 menu and installer copy not duplicated in files.tar.gz" "! tar -tzf $D30/files.tar.gz | grep -q 'bin/steam-arm-config\$\\|share/steam-arm-install.sh\$'"
check "U5 snapshot folder root-only mode 700, snapshots folder 755" "[ \$(stat -c %a $D30) = 700 ] && [ \$(stat -c %a $R/lib/snapshots) = 755 ]"
check "U5 state removed, staging removed, history line" "[ ! -f $R/lib/upgrade.state ] && [ -z \"\$(ls -A $R/cache/upgrade 2>/dev/null)\" ] && grep -qE ' 3\\.0 3\\.1 upgrade ok $S30\$' $R/lib/history.log"
check "U5 3.1-only file written, 3.0-only file gone" "[ -f $R/sys/new31 ] && [ ! -e $R/sys/old30 ]"
ue 'installer_cmd'
check "U5 Update / Repair now runs installed 3.1 copy" "[ \"\$(printf '%s' \"\$OUT\" | tail -1)\" = '$R/share/steam-arm-install.sh' ]"
check "U5 SNAPSHOT_KEEP of earlier settings file kept" "grep -qx SNAPSHOT_KEEP=3 $R/etc/steam-arm/steam-arm.conf"
check "U5 upgrade log written" "ls $R/ucache/upgrade-*.log >/dev/null 2>&1 && grep -q 'Newest release: steam-arm-v3.1' $R/ucache/upgrade-*.log && grep -q '^sha256 ' $R/ucache/upgrade-*.log"
rel 3.1 1; uh upgrade --yes
check "U5 again: newest release already installed, rc 1, no new snapshot" "[ $RC = 1 ] && has 'already installed' && [ \$(snaps) = 1 ]"

# ---------- U8 rollback 3.1 -> 3.0 ----------
cp -a "$R/etc/steam-arm" "$T/etc31"
echo "changed in 3.1" >> "$R/sys/lib/helper.py"
FX_NOWRITE=1 uh upgrade --rollback --yes
check "U8 rollback: rc 0, restored message" "[ $RC = 0 ] && has 'Steam ARM 3.0 restored.'"
check "U8 VERSION 3.0, installed copy and menu of 3.0" "[ \"\$(cv)\" = 3.0 ] && grep -qx 'SA_VERSION=3.0' $R/share/steam-arm-install.sh && grep -qx 'SA_VERSION=3.0' $R/bin/steam-arm-config"
ok=1; while read -r k m h p; do [ "$k" = present ] || continue
  if [ -L "$p" ]; then [ "$(readlink "$p" | sha256sum | cut -c1-64)" = "$h" ] || ok=0
  else [ "$(sha256sum < "$p" | cut -c1-64)" = "$h" ] && [ "$(stat -c %a "$p")" = "$m" ] || ok=0; fi
done < "$D30/paths.txt"
check "U8 every present file byte-equal to 3.0 snapshot (sha256, mode)" "[ $ok = 1 ]"
check "U8 3.1-only file deleted, 3.0-only file back, absent path absent" "[ ! -e $R/sys/new31 ] && [ -f $R/sys/old30 ] && [ ! -e $R/sys/absent.rules ]"
check "U8b rollback strips client window keys older versions do not know (strip-optin as game account, before snapshot restore)" \
  "grep -q '^  rb_strip_client$' '$INST' && [ \$(grep -n '^  rb_strip_client$' '$INST' | cut -d: -f1) -lt \$(grep -n '^  snap_restore \"\$n\" || ' '$INST' | cut -d: -f1) ] && grep -q 'runuser -u \"\$(game_user)\" -- python3 /usr/local/lib/steam-arm-x86client.py strip-optin \"\$sd\" \"\$(arm_home)\"' '$INST'"
check "U8 /etc/steam-arm equals snapshot (3.0 VERSION, titles)" "mkdir -p $T/e && tar -xzf $D30/etc.tar.gz -C $T/e && diff -r $T/e${R}/etc/steam-arm $R/etc/steam-arm >/dev/null"
check "U8 snapshot of 3.1 made first (reason rollback 3.0)" "[ \$(snaps) = 2 ] && grep -qx 'REASON=rollback 3.0' $R/lib/snapshots/3.1-*/MANIFEST"
check "U8 restored 3.0 setup got --keep, no --allow-older" "[ \"\$(tail -1 $R/setup.log)\" = 'setup 3.0 --keep' ]"
check "U8 state cleared, history names rollback" "[ ! -f $R/lib/upgrade.state ] && grep -qE ' 3\\.1 3\\.0 rollback ok $S30\$' $R/lib/history.log"
ue 'ui_menu(){ printf "MENU %s\n" "$*" >&2; return 1; }; menu_maintenance'
check "U8 Maintenance item 15 Go back shown once snapshot exists" "has '15 Go back to previous version'"
uh upgrade --list
check "U8 --list: both snapshots, verified, reasons, history" "has 'before upgrade to 3.1' && has 'before going back to 3.0' && [ \$(grep -c verified <<<\"\$OUT\") = 2 ] && has 'Version changes:'"
# upgrade again: 3.1 snapshot of before rollback and new one of 3.0
rel 3.1 1; uh upgrade --yes
check "U16 upgrade after rollback: 3.1 again, earlier 3.0 snapshot replaced by newer one (one per version)" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.1 ] && [ ! -d $D30 ] && [ \$(ls -d $R/lib/snapshots/3.0-* | wc -l) = 1 ]"

# ---------- U6 more versions, prune keeps 2 ----------
rel 3.2 1; uh upgrade --yes
check "U6 3.1 -> 3.2: snapshots of 3.0 and 3.1 kept" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.2 ] && ls -d $R/lib/snapshots/3.0-* $R/lib/snapshots/3.1-* >/dev/null 2>&1"
rel 3.3 1; uh upgrade --yes
check "U6 3.2 -> 3.3 with keep 3 (from settings file): 3.0, 3.1, 3.2 kept" "[ $RC = 0 ] && [ \$(snaps) = 3 ]"
sed -i '/^SNAPSHOT_KEEP=/d' "$R/etc/steam-arm/steam-arm.conf"; rel 3.4 1; uh upgrade --yes
check "U6 3.3 -> 3.4 with keep 2: 3.3 and 3.2 kept, older deleted, deletion lines and freed space printed" "[ $RC = 0 ] && [ \$(snaps) = 2 ] && ls -d $R/lib/snapshots/3.3-* $R/lib/snapshots/3.2-* >/dev/null && has 'Deleted snapshot 3.0 (' && has 'Deleted snapshot 3.1 (' && has 'Freed '"

# ---------- U7 prune rules on synthetic snapshots ----------
fresh 3.0 0
mk(){ # snapshot of version $1 with stamp $2
  sed -i "s/^VERSION=.*/VERSION=$1/" "$R/etc/steam-arm/steam-arm.conf"
  fx_setup "$1" 0 "$R/share/steam-arm-install.sh"
  ue 'snap_make manual && echo "$SNAP_NAME"'; mv "$R/lib/snapshots/$(tail -1 <<<"$OUT")" "$R/lib/snapshots/$1-$2"
}
mk 2.1 20260101T000000Z; mk 2.2 20260201T000000Z; mk 2.3 20260301T000000Z; mk 2.3.1 20260401T000000Z
mk 3.0 20260501T000000Z; mk 3.0 20260502T000000Z
sed -i "s/^VERSION=.*/VERSION=3.1/" "$R/etc/steam-arm/steam-arm.conf"; fx_setup 3.1 1 "$R/share/steam-arm-install.sh"
cp -a "$R/lib/snapshots" "$T/snaps0"
setk(){ rm -rf "$R/lib/snapshots"; cp -a "$T/snaps0" "$R/lib/snapshots"; sed -i '/^SNAPSHOT_KEEP=/d' "$R/etc/steam-arm/steam-arm.conf"; [ -n "$1" ] && echo "SNAPSHOT_KEEP=$1" >> "$R/etc/steam-arm/steam-arm.conf"; }
left(){ ls "$R/lib/snapshots" | LC_ALL=C sort | paste -sd' ' -; }
setk 1; ue 'snap_prune'
check "U7 keep 1: newest 3.0 only" "[ \"\$(left)\" = '3.0-20260502T000000Z' ]"
setk 2; b=$(du -sb "$R/lib/snapshots/3.0-20260501T000000Z" "$R/lib/snapshots/2.3-20260301T000000Z" "$R/lib/snapshots/2.2-20260201T000000Z" "$R/lib/snapshots/2.1-20260101T000000Z" | awk '{s+=$1} END {printf "%.1f MB", s/1048576}')
ue 'snap_prune'
check "U7 keep 2 (default): newest 3.0 and 2.3.1; older copy of 3.0 deleted" "[ \"\$(left)\" = '2.3.1-20260401T000000Z 3.0-20260502T000000Z' ] && has 'older copy of 3.0' && has 'beyond 2 earlier versions'"
check "U7 freed space equals sum of deleted snapshot sizes ($b)" "has 'Freed $b.'"
setk 5; ue 'snap_prune'
check "U7 keep 5: one per version, five versions" "[ \"\$(left)\" = '2.1-20260101T000000Z 2.2-20260201T000000Z 2.3-20260301T000000Z 2.3.1-20260401T000000Z 3.0-20260502T000000Z' ]"
setk 9; ue 'snap_keep'; check "U7 keep outside 1..5 reads as 2" "[ \"\$OUT\" = 2 ]"
setk 2; echo x >> "$R/lib/snapshots/2.3.1-20260401T000000Z/files.tar.gz"; mkdir "$R/lib/snapshots/.tmp-20260601T000000Z-abc"
mkdir -p "$R/cache/upgrade/3.2.part"
ue 'snap_prune'
check "U7 damaged snapshot deleted, next version takes its place" "[ \"\$(left)\" = '2.3-20260301T000000Z 3.0-20260502T000000Z' ] && has 'Deleted snapshot 2.3.1 (2026-' && has 'damaged)'"
check "U7 half-written .tmp-* and download .part leftovers removed" "[ ! -e $R/lib/snapshots/.tmp-20260601T000000Z-abc ] && [ ! -e $R/cache/upgrade/3.2.part ]"
setk 1; echo x >> "$R/lib/snapshots/2.3-20260301T000000Z/installer.sh"
printf 'FROM=2.3\nTO=3.1\nKIND=upgrade\nSNAPSHOT=2.3-20260301T000000Z\n' > "$R/lib/upgrade.state"
ue 'snap_prune --in-setup'
check "U7 snapshot of unfinished change never deleted, even damaged" "[ -d $R/lib/snapshots/2.3-20260301T000000Z ] && [ -d $R/lib/snapshots/3.0-20260502T000000Z ]"
uh upgrade --rollback 2.3 --yes
check "U7 damaged snapshot: going back refused" "[ $RC != 0 ] && has 'damaged'"
rm -f "$R/lib/upgrade.state"
setk 1; echo x >> "$R/lib/snapshots/3.0-20260502T000000Z/etc.tar.gz"; ue 'snap_protected'; P=$OUT
check "U7 newest snapshot of earlier version (rollback target) is protected" "grep -qx '3.0-20260501T000000Z' <<<\"\$P\""
( flock "$R/run/steam-arm-setup.lock" sleep 2 ) & LP=$!; sleep 0.3; setk 1; ue 'snap_prune'; wait "$LP"
check "U7 pruning refused while setup runs (outside setup)" "has 'Another setup run is in progress' && [ \"\$(left)\" = \"\$(ls $T/snaps0 | LC_ALL=C sort | paste -sd' ' -)\" ]"
setk 2; uh snapshot-keep 1
check "U7 snapshot-keep 1: written, prunes at once, reports" "grep -qx SNAPSHOT_KEEP=1 $R/etc/steam-arm/steam-arm.conf && has 'Kept: installed version plus 1 earlier versions.' && has 'Deleted snapshot' && [ \"\$(left)\" = '3.0-20260502T000000Z' ]"
uh snapshot-keep 7; check "U7 snapshot-keep refuses 7" "[ $RC = 2 ]"
check "U7 pruning only after success paths and setting change (no background runner)" "[ \$(grep -c '\\bsnap_prune\\b' '$CFG') = 5 ]"

# ---------- U9 interrupted upgrade, U10 failed setup ----------
fresh 3.0 0; rel 3.1 1
FX_KILL=1 uh upgrade --yes
check "U9 setup stopped by SIGTERM after state written: restore offered, staging kept" "[ $RC != 0 ] && has 'Restore 3.0: sudo steam-arm-config upgrade --rollback' && [ -f '$R/cache/upgrade/3.1/x/Steam ARM 3.1/steam-arm-install.sh' ] && grep -qx TO=3.1 $R/lib/upgrade.state"
ue 'up_notice'; check "U9 main screen names unfinished change" "has 'Upgrade from 3.0 to 3.1 did not finish (started '"
ue 'ui_menu(){ printf "MENU %s|%s\n" "$1" "$*" >&2; return 1; }; ui_info(){ :; }; status_line(){ :; }; menu_main'
check "U9 next menu start offers Restore 3.0 / Run 3.1 setup again / Later (nothing restored)" "grep -q '^MENU Unfinished change|' <<<\"\$OUT\" && has 'restore Restore 3.0' && has 'again Run 3.1 setup again' && has 'later Later' && [ -f $R/lib/upgrade.state ]"
uh upgrade --yes; check "U9 new upgrade refused while change unfinished (rc 3)" "[ $RC = 3 ] && has 'did not finish'"
n=$(snaps); uh upgrade --rollback --yes
check "U9 --rollback restores 3.0 without new snapshot, state cleared, history restore" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.0 ] && [ \$(snaps) = $n ] && [ ! -f $R/lib/upgrade.state ] && grep -qE ' 3\\.0 3\\.0 restore ok ' $R/lib/history.log && [ -f $R/sys/old30 ]"
rel 3.1 1; FX_FAIL=1 uh upgrade --yes
check "U10 setup fails after VERSION written: status kept, restore and rerun named" "[ $RC = 1 ] && has 'Setup of 3.1 stopped (status 1). Restore 3.0' && has 'Run 3.1 setup again' && grep -qx 'VERSION=3.1' $R/etc/steam-arm/steam-arm.conf"
uh upgrade --rollback --yes
check "U10 restore after failure: 3.0 back" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.0 ] && [ ! -f $R/lib/upgrade.state ]"
# setup run again after failure continues same change without second snapshot
rel 3.1 1; FX_FAIL=1 uh upgrade --yes; SN=$(sed -n 's/^SNAPSHOT=//p' "$R/lib/upgrade.state")
bash "$R/cache/upgrade/3.1/x/Steam ARM 3.1/steam-arm-install.sh" --keep > "$T/o" 2>&1; OUT=$(cat "$T/o")
check "U10 Run 3.1 setup again: continues change, no second snapshot, its snapshot kept, state cleared on success" "has 'unfinished change to 3.1: continuing (snapshot $SN kept)' && ! has 'previous version 3.0 saved' && [ -d '$R/lib/snapshots/$SN' ] && [ ! -f $R/lib/upgrade.state ] && [ \"\$(cv)\" = 3.1 ]"
# snapshot cannot be written: setup stops before change
fresh 3.0 0; rel 3.1 1; mkdir -p "$R/lib"; ln -s /nonexistent "$R/lib/snapshots"
uh upgrade --yes
check "U10 snapshot not writable: setup stops before change, message, VERSION stays" "[ $RC != 0 ] && has 'Snapshot of 3.0 could not be written (' && has 'nothing changed' && [ \"\$(cv)\" = 3.0 ] && [ ! -f $R/lib/upgrade.state ]"
rm -f "$R/lib/snapshots"
ue 'up_setup_begin 3.1 1; cat "$(state_file)"'
check "U10 --no-snapshot: change recorded without snapshot" "has 'no snapshot of 3.0 (--no-snapshot)' && has 'SNAPSHOT=' && [ \$(snaps) = 0 ]"
rm -f "$R/lib/upgrade.state"
ue 'up_setup_begin 3.0 0; echo rc=$?'
check "U10 same version (Update / Repair): no snapshot, no state" "has 'rc=0' && [ \$(snaps) = 0 ] && [ ! -f $R/lib/upgrade.state ]"
sed -i 's/^VERSION=.*/VERSION=/' "$R/etc/steam-arm/steam-arm.conf"; ue 'up_setup_begin 3.1 0; echo rc=$?'
check "U10 fresh install (no VERSION): no snapshot" "has 'rc=0' && [ \$(snaps) = 0 ]"

# ---------- U11, U12 packages ----------
fresh 3.0 0; rel 3.1 1; echo INSTALLED_FROM=package >> "$R/etc/steam-arm/steam-arm.conf"
fx_setup 3.0 0 "$R/pkg/install.sh"; s0=$(find "$R/pkg" -type f -exec sha256sum {} + | sort | sha256sum)
uh upgrade --yes
check "U11 package install: rc 3, package steps, no download" "[ $RC = 3 ] && has 'Installed through package steam-arm-setup 3.0. Newest release: 3.1.' && has 'sudo apt install ./steam-arm-setup_3.1_arm64.deb' && has 'sudo steam-arm-setup --keep' && [ ! -d $R/cache/upgrade ]"
check "U11 package files untouched" "[ \"\$(find $R/pkg -type f -exec sha256sum {} + | sort | sha256sum)\" = '$s0' ]"
uh upgrade --check; check "U11 check names package steps in place of upgrade command" "has 'Package update: build steam-arm-setup_3.1_arm64.deb' && ! has 'sudo steam-arm-config upgrade'"
rm -f "$R/share/steam-arm-install.sh"; fx_setup 3.1 1 "$T/pkg31.sh"; bash "$T/pkg31.sh" --keep >/dev/null 2>&1
check "U11 setup from package snapshots package copy of installed version" "[ \$(snaps) = 1 ] && grep -qx 'SA_VERSION=3.0' $R/lib/snapshots/3.0-*/installer.sh && [ \"\$(find $R/pkg -type f -exec sha256sum {} + | sort | sha256sum)\" = '$s0' ]"
printf '#!/bin/sh\nexec bash %s "$@"\n' "$R/pkg/install.sh" > "$R/pbin/steam-arm-setup"; chmod 755 "$R/pbin/steam-arm-setup"
ue 'find_installer'
check "U12 old package (3.0) next to newer zip install (3.1): installed 3.1 copy runs" "[ \"\$OUT\" = '$R/share/steam-arm-install.sh' ]"
sed -i 's/^VERSION=.*/VERSION=3.0/' "$R/etc/steam-arm/steam-arm.conf"; ue 'find_installer'
check "U12 installed version 3.0 (after rollback): package command of same version" "[ \"\$OUT\" = '$R/pbin/steam-arm-setup' ]"
sed -i 's/^VERSION=.*/VERSION=9.9/' "$R/etc/steam-arm/steam-arm.conf"; ue 'find_installer'
check "U12 no candidate matches: newest of them" "[ \"\$OUT\" = '$R/share/steam-arm-install.sh' ]"
OUT=$(STEAM_ARM_INSTALLER=$R/pkg/install.sh UH_EVAL='find_installer' bash "$UH"); check "U12 STEAM_ARM_INSTALLER still wins" "[ \"\$OUT\" = '$R/pkg/install.sh' ]"

# ---------- U13 downgrade protection ----------
fresh 3.0 0; rel 2.9 0
uh upgrade --yes
check "U13 older newest release: rc 1, nothing to do, no download" "[ $RC = 1 ] && has 'Installed 3.0 is newer than newest release (2.9). Nothing to do.' && [ ! -d $R/cache/upgrade/2.9 ]"
uh upgrade --yes --allow-older
check "U13 --allow-older: warning, setup of 2.9 runs" "[ $RC = 0 ] && has 'Warning: 2.9 is older than installed 3.0' && [ \"\$(cv)\" = 2.9 ]"
fresh 3.0 0; mkdir -p "$T/dl"; fx_zip 2.9 0 "$T/dl"
uh upgrade --file "$T/dl/Steam.ARM.2.9.zip" --yes
check "U13 --file with older zip: rc 3 refused" "[ $RC = 3 ] && has 'newer than this file (2.9)'"
fx_zip 3.1 1 "$T/dl"; uh upgrade --file "$T/dl/Steam.ARM.3.1.zip" --yes
check "U13 --file with newer zip: offline upgrade, no network request" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.1 ] && [ \$(snaps) = 1 ]"
rm "$T/dl/Steam.ARM.2.9.zip.sha256"; fresh 3.0 0; uh upgrade --file "$T/dl/Steam.ARM.2.9.zip" --yes --allow-older
check "U13 --file without .sha256 beside it: rc 2" "[ $RC = 2 ] && has '.sha256 file beside it'"
# installer block, extracted: 3.1 over installed 3.2
DG=$T/dg.sh
{ fn sa_ver_gt "$INST"; echo 'die(){ echo "DIE $*"; exit 1; }; warn(){ echo "WARN $*"; }; conf_get(){ echo "$IV_SET"; }'
  awk '/^# Older installer over newer install/{f=1} f{print} f && /^fi$/{exit}' "$INST"; echo 'echo CONTINUE'; } > "$DG"
dg(){ OUT=$(IV_SET=$1 SA_VERSION=$2 HELP=0 MODE=keep CLIENT_CHECK=0 ALLOW_OLDER=$3 bash -c "$(sed 's#/usr/local/bin/steam-arm#'"$R"'/bin/steam-arm#' "$DG")" 2>&1); }
dg 3.2 3.1 0; check "U13 installer 3.1 over 3.2: stops before change, names way back and --allow-older" "has 'DIE Steam ARM 3.2 is installed; this installer is 3.1. To go back use Maintenance > Go back to previous version, or run again with --allow-older.' && ! has CONTINUE"
dg 3.2 3.1 1; check "U13 installer 3.1 over 3.2 with --allow-older: warns, continues" "has 'WARN Steam ARM 3.2 is installed; installing older 3.1' && has CONTINUE"
dg 3.0 3.1 0; check "U13 installer 3.1 over 3.0: continues" "has CONTINUE && ! has DIE"
dg 3.1.0 3.1 0; check "U13 3.1.0 installed, installer 3.1: same version" "has CONTINUE && ! has DIE"
dg "" 3.1 0; check "U13 no VERSION: continues" "has CONTINUE"
check "U13 downgrade check after terminal menu branch, before GPU detection" "a=\$(grep -n '^# Older installer over newer install' '$INST' | cut -d: -f1); b=\$(grep -n 'STEAM_ARM_INSTALLER=\$SELF bash \"\$MENU\"' '$INST' | cut -d: -f1); c=\$(grep -n '^\\[ \"\$MODE\" = remove \\] || gpu_pick' '$INST' | cut -d: -f1); [ \$b -lt \$a ] && [ \$a -lt \$c ]"
check "U13 options parsed: --allow-older, --no-snapshot, --snapshot; listed in --help" "grep -q '^    --allow-older) ALLOW_OLDER=1;;' '$INST' && grep -q '^    --no-snapshot) NO_SNAPSHOT=1;;' '$INST' && grep -q '^    --snapshot) MODE=snapshot;;' '$INST' && grep -q '^  --allow-older ' '$INST' && grep -q '^  --no-snapshot ' '$INST' && grep -q '^  --snapshot ' '$INST'"

# ---------- installer hooks (static) ----------
l_root=$(grep -n '^\[ "\$(id -u)" = 0 \] || die "run as root"$' "$INST" | tail -1 | cut -d: -f1)
l_begin=$(grep -n 'sa_menu_call upgrade --setup-begin' "$INST" | cut -d: -f1)
l_s1=$(grep -n '^say "1/11  host packages"' "$INST" | cut -d: -f1)
l_retire=$(grep -n '^\[ "\$RETIRE_OTHER" = 1 \] && retire_other$' "$INST" | tail -1 | cut -d: -f1)
l_done=$(grep -n '^say "11/11  done"' "$INST" | cut -d: -f1)
l_end=$(grep -n 'sa_menu_call upgrade --setup-end' "$INST" | cut -d: -f1)
check "I1 snapshot step after root check, before retire_other and step 1" "[ -n '$l_begin' ] && [ $l_root -lt $l_begin ] && [ $l_begin -lt $l_retire ] && [ $l_begin -lt $l_s1 ]"
check "I2 finish step right after done line" "[ \$(( l_end - l_done )) -le 3 ] && [ $l_end -gt $l_done ]"
BLK=$(sed -n "$l_begin,$((l_begin + 2))p" "$INST")
check "I3 failed snapshot stops setup (die), --no-snapshot passed on" "grep -q -- '--no-snapshot' <<<\"\$BLK\" && grep -q 'die \"installed version not saved; nothing changed' <<<\"\$BLK\""
check "I4 setup records INSTALLED_FROM package only for package script path owned by dpkg" "grep -q 'conf_set INSTALLED_FROM package' '$INST' && grep -q \"dpkg-query -S /usr/share/steam-arm-setup/install.sh 2>/dev/null | grep -q '^steam-arm-setup:'\" '$INST'"
check "I5 unfinished change of another version named at setup start" "grep -q 'did not finish; restore: sudo steam-arm-config upgrade --rollback' '$INST'"
check "I6 menu helper runs embedded menu from temporary copy (snapshot code of this version)" "fn sa_menu_call '$INST' | grep -q 'menu_app > \"\$t\" && bash \"\$t\" \"\$@\"'"
check "U15 --remove deletes /var/lib/steam-arm and /var/cache/steam-arm" "fn remove_all '$INST' | grep -qx '  rm -rf /var/lib/steam-arm /var/cache/steam-arm'"
check "U15 removal gate requires both menu folders" "grep -q 'MENU_DIRS = (\"/var/lib/steam-arm\", \"/var/cache/steam-arm\")' '$SARM_GATES/check-removal.py'"
# owned path list covers removal list
RM=$(fn remove_all "$INST" | awk '/^  rm -f \/usr\/local\/bin\/steam-arm /{f=1} f{print} f && !/\\$/{exit}' | tr ' \\' '\n\n' | grep '^/' | sort -u)
OWN=$(UHR=$R bash -c ". '$CFG' >/dev/null 2>&1 --help; game_home(){ echo /home/u; }; sa_owned_paths" 2>/dev/null; sed -n '/^sa_owned_paths(){/,/^}/p' "$CFG")
miss=""; for p in $RM; do grep -qF -- "$p" <<<"$OWN" || miss="$miss $p"; done
check "U15 owned path list holds every path of removal rm -f list (missing:$miss)" "[ -z \"\$miss\" ] && grep -q '/etc/apt/apt.conf.d/80steam-arm-glx-lax' <<<\"\$OWN\""
check "U15 owned list: units, sysctl, conditional files by setup's mark" "for p in steam-arm-pad-xbox.service steam-arm-fex-binfmt.service zz-steam-arm.conf 60-steam-input.rules steamos-session-select '# steam-arm-setup mangohud shim'; do grep -qF -- \"\$p\" <<<\"\$OWN\" || exit 1; done"

# ---------- U14 front ends ----------
fresh 3.0 0
DRV="UH_EVAL='DIALOG=builtin; menu_maintenance; echo MENU-DONE' bash $UH"
OUT=$(python3 "$SARM_TESTS/config-ui/ptydrive.py" "$DRV" '16' '\r' @1.5 '\x1b' @1 '\x1b' @1 2>&1)
check "U14 built-in screens: item 16 opens Previous versions kept, Back twice leaves" "has 'Previous versions kept (now: 2)' && has 'Snapshots kept besides installed version' && has 'MENU-DONE'"
OUT=$(python3 "$SARM_TESTS/config-ui/ptydrive.py" "UH_EVAL='DIALOG=; menu_maintenance; echo MENU-DONE' bash $UH" '14\r' '0\r' '0\r' 2>&1)
check "U14 plain prompts: Previous versions kept listed and opens, Back leaves" "has '== Previous versions kept ==' && has '2 earlier versions (default)' && has 'MENU-DONE'"
for d in whiptail dialog; do
  mkdir -p "$T/fe-$d"; printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> %s/args\nexit 1\n' "$T/fe-$d" > "$T/fe-$d/$d"; chmod 755 "$T/fe-$d/$d"
  PATH="$T/fe-$d:$PATH" UH_EVAL="DIALOG=$d; ui_size(){ UH=20; UW=70; UL=11; }; menu_maintenance" bash "$UH" >/dev/null 2>&1
  OUT=$(cat "$T/fe-$d/args" 2>/dev/null)
  check "U14 $d: items 14, 16, 17 passed with labels" "grep -qx 'Previous versions kept (now: 2)' <<<\"\$OUT\" && grep -qx 'Show what is new' <<<\"\$OUT\" && grep -qx 'Check for new release when this menu opens (now: off)' <<<\"\$OUT\""
done
mkdir -p "$T/fe-y"; printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> %s/args\ncase " $* " in *" --menu "*) echo 16 >&2;; esac\nexit 0\n' "$T/fe-y" > "$T/fe-y/whiptail"; chmod 755 "$T/fe-y/whiptail"
OUT=$(PATH="$T/fe-y:$PATH" UH_EVAL='DIALOG=whiptail; ui_size(){ UH=20; UW=70; UL=11; }; c=$(ui_menu t x 16 a); echo "PICK $c"' bash "$UH" 2>&1)
check "U14 whiptail: tag 16 returned" "has 'PICK 16'"
# menu screens with stubbed screens: Upgrade, Go back
fresh 3.0 0; rel 3.1 1
ST='ui_info(){ :; }; status_line(){ :; }; close_steam(){ return 0; }; pre_fold(){ cat; }; ui_yesno(){ echo "YESNO $1|$2|$3"; [ "${ANS:-yes}" = yes ]; }; ui_msg(){ echo "MSG $1|$2"; }; ui_textstr(){ echo "TEXT $1|$2"; }; ui_run(){ local l=$2; shift 2; "$@" >> "$l" 2>&1; }; up_self(){ ui_run "$1" "$2" bash "$UH" "${@:3}"; }; snap_rows_root(){ snap_rows; }; rb_text_root(){ rb_text "$1"; }; ui_menu(){ echo "MENU $1|$*" >&2; echo "${PICK:-}"; [ -n "${PICK:-}" ]; }'
OUT=$(ANS=no UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "U14 Upgrade screen: plan names version, size, check, saved copy; Back changes nothing" "has 'YESNO Upgrade to newest release|Steam ARM 3.1 (installed: 3.0)' && has 'saves 3.0 (Maintenance > Go back to previous version)' && [ \"\$(cv)\" = 3.0 ]"
OUT=$(UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "U14 Upgrade screen: Upgrade runs, done screen with log lines" "has 'TEXT Upgrade to newest release: done|' && has 'Steam ARM 3.1 installed.' && [ \"\$(cv)\" = 3.1 ]"
OUT=$(UH_EVAL="$ST; maint_whatsnew" bash "$UH" 2>&1)
check "U14 Show what is new: release notes of last check" "has 'TEXT Show what is new: steam-arm-v3.1|## Steam ARM 3.1'"
S=$(ls "$R/lib/snapshots" | head -1)
OUT=$(PICK=$S FX_NOWRITE=1 UH_EVAL="$ST; maint_rollback" bash "$UH" 2>&1)
check "U14 Go back screen: snapshot listed with reason, confirm names client stays, restore done" "has \"$S 3.0  \" && has 'before upgrade to 3.1' && has 'YESNO Go back to previous version|Programs, rules and system settings return to 3.0 as of' && has 'Client, games, sign-in and x86 RootFS stay.' && has 'TEXT Go back to previous version: done|' && [ \"\$(cv)\" = 3.0 ]"
echo x >> "$R/lib/snapshots/$(ls "$R/lib/snapshots" | grep '^3.1-')/paths.txt"
OUT=$(UH_EVAL="$ST; maint_rollback" bash "$UH" 2>&1)
check "U14 Go back screen: damaged snapshot shown as damaged, delete offered, not selectable as restore" "has 'del:3.1-' && has 'damaged (' && has 'Delete damaged snapshot'"

# ---------- U16 settings ----------
OLD30=$(sarm_old 3.0)
if [ -n "$OLD30" ]; then
  printf 'VERSION=3.0\nSNAPSHOT_KEEP=4\nUPDATE_CHECK_ON_OPEN=on\n' > "$T/c.conf"
  OUT=$( { fn conf_set "$OLD30"; echo 'die(){ exit 1; }'; echo "CONF=$T/c.conf; conf_set VERSION 3.0; conf_set GFX_DEFAULT a"; } | bash 2>&1; cat "$T/c.conf")
  check "U16 3.0 setup keeps 3.1 keys in settings file (conf_set)" "has SNAPSHOT_KEEP=4 && has UPDATE_CHECK_ON_OPEN=on && has GFX_DEFAULT=a"
  # 3.1 backup of setup part, restored by 3.0 menu (fake tree of config-ui harness)
  F=$T/fk; export SARM_UI_FAKE=$F SARM_UI_COPY=$T/fk-copy.sh
  bash "$SARM_TESTS/config-ui/mkfake.sh" >/dev/null
  printf 'SNAPSHOT_KEEP=4\nUPDATE_CHECK_ON_OPEN=on\n' >> "$F/etc/steam-arm/steam-arm.conf"
  mkdir -p "$T/bk"; OUT=$(bash "$SARM_TESTS/config-ui/harness.sh" backup "$T/bk" --parts setup 2>&1); B=$(sed -n 's/^Saved to //p' <<<"$OUT")
  check "U16 3.1 backup holds SNAPSHOT_KEEP and UPDATE_CHECK_ON_OPEN" "[ -f \"\$B\" ] && tar -xzOf \"\$B\" steam-arm-settings/system/steam-arm.conf | grep -qx SNAPSHOT_KEEP=4"
  sed -i '/^SNAPSHOT_KEEP=/d; /^UPDATE_CHECK_ON_OPEN=/d' "$F/etc/steam-arm/steam-arm.conf"
  mkdir -p "$T/m30"; awk "/^menu_app\\(\\)\\{ cat <<'STEAMARMCONFIG'\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f" "$OLD30" > "$T/m30/steam-arm-config"
  OUT=$(SARM_CFG=$T/m30/steam-arm-config SARM_UI_COPY=$T/fk-copy30.sh bash "$SARM_TESTS/config-ui/harness.sh" restore "$B" --yes 2>&1); RC=$?
  check "U16 3.0 menu restores 3.1 backup (new keys skipped)" "[ $RC = 0 ] && has 'Settings restored.' && ! grep -q '^SNAPSHOT_KEEP=' $F/etc/steam-arm/steam-arm.conf"
  OUT=$(bash "$SARM_TESTS/config-ui/harness.sh" restore "$B" --yes 2>&1); RC=$?
  check "U16 3.1 menu restores both keys" "[ $RC = 0 ] && grep -qx SNAPSHOT_KEEP=4 $F/etc/steam-arm/steam-arm.conf && grep -qx UPDATE_CHECK_ON_OPEN=on $F/etc/steam-arm/steam-arm.conf"
  # snapshot settings through real menus of earlier releases (fake tree paths)
  for ov in 2.3.1 3.0; do
    o=$(sarm_old "$ov"); [ -n "$o" ] || { echo "SKIP U16 settings backup by $ov menu: release not available"; continue; }
    awk "/^menu_app\\(\\)\\{ cat <<'STEAMARMCONFIG'\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f" "$o" > "$T/m-$ov"
    printf '#!/bin/bash\nSARM_CFG=%s SARM_UI_FAKE=%s SARM_UI_COPY=%s exec bash %s "$@"\n' "$T/m-$ov" "$F" "$T/fk-copy-$ov.sh" "$SARM_TESTS/config-ui/harness.sh" > "$T/w-$ov"
    rm -rf "$T/sd-$ov"; mkdir -p "$T/sd-$ov"
    ue "snap_settings '$T/w-$ov' '$T/sd-$ov' '' && echo SETTINGS-OK"
    check "U16 snapshot settings backup made by $ov menu (backup DIR --account)" "has SETTINGS-OK && tar -xzOf '$T/sd-$ov/settings.tar.gz' steam-arm-settings/manifest | grep -q '^FORMAT=1\$'"
  done
  unset SARM_UI_FAKE SARM_UI_COPY
else
  echo "SKIP U16 cross-version settings: release 3.0 not available"
fi
echo "T12 not applicable: 3.1 adds no title profile keys"

# ---------- client channel label ----------
ue 'for c in "" stable steamdeck_stable linux_arm64_beta_861407927dc8efb407da7cf publicbeta steamdeck_publicbeta my_beta_x odd; do printf "%s=%s\n" "$c" "$(client_channel_label "$c")"; done'
check "C1 channel labels: stable, Valve ARM channel, beta, raw" "has '=stable' && has 'stable=stable' && has 'steamdeck_stable=stable' && has 'linux_arm64_beta_861407927dc8efb407da7cf=Valve ARM channel (set by Steam Frame mode)' && has 'publicbeta=beta (Steam Beta Participation)' && has 'steamdeck_publicbeta=beta (Steam Beta Participation)' && has 'my_beta_x=beta (Steam Beta Participation)' && has 'odd=odd'"
ue 'client_channel(){ echo linux_arm64_beta_861407927dc8efb407da7cf; }; client_channel_full'
check "C2 report form keeps raw name in brackets" "[ \"\$OUT\" = 'Valve ARM channel (linux_arm64_beta_861407927dc8efb407da7cf)' ]"
ue 'client_channel(){ echo steamdeck_stable; }; client_channel_full'
check "C2 stable channel: plain stable" "[ \"\$OUT\" = stable ]"
check "C3 info row and report use labels" "grep -q '^Client channel \$(client_channel_label)\$' '$CFG' && fn rr_upstream '$CFG' | grep -q 'client_channel_full'"

# ---------- A audit fixes ----------
# dpkg-query stand-in: -S answers for paths listed in $R/dpkg-owned; -W reports package installed (version $R/dpkg-ver) while that file exists
dpkg_stub(){
  cat > "$R/pbin/dpkg-query" <<'EOF'
#!/bin/sh
case "$1" in
  -S) shift; for p in "$@"; do grep -qxF -- "$p" "$UHR/dpkg-owned" 2>/dev/null && echo "steam-arm-setup: $p"; done; exit 0;;
  -W) [ -f "$UHR/dpkg-owned" ] || exit 1
      case "$2" in *Status*) printf 'install ok installed';; *Version*) cat "$UHR/dpkg-ver" 2>/dev/null || echo 3.1;; esac; exit 0;;
esac
exit 1
EOF
  chmod 755 "$R/pbin/dpkg-query"
}
dl(){ grep -c '^/dl/' "$M/requests" 2>/dev/null || echo 0; }
# A1 package install: versions compared before package steps
fresh 3.1 1; dpkg_stub; echo INSTALLED_FROM=package >> "$R/etc/steam-arm/steam-arm.conf"; rel 3.0 0; d0=$(dl)
uh upgrade --yes
check "A1 package 3.1, newest release 3.0: rc 1, installed is newer, no package steps" "[ $RC = 1 ] && has 'Installed 3.1 is newer than newest release (3.0). Nothing to do.' && ! has 'Package update' && ! has 'apt install' && [ \$(dl) = $d0 ]"
uh upgrade --check
check "A1 package 3.1, check against 3.0: newer than newest, no package steps" "[ $RC = 1 ] && has 'Steam ARM 3.1 is newer than the newest release (3.0).' && ! has 'Package update'"
OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "A1 menu Upgrade, package 3.1 vs release 3.0: newer message, Go back named, no package text" "has 'MSG Upgrade to newest release|Installed 3.1 is newer than newest release 3.0. Nothing to do.' && has 'Go back to previous version' && ! has 'Installed through package'"
rel 3.1 1; uh upgrade --yes
check "A1 package, same version: rc 1, already installed, no package steps" "[ $RC = 1 ] && has 'already installed' && ! has 'Package update'"
OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "A1 menu Upgrade, package same version: already installed" "has 'MSG Upgrade to newest release|Steam ARM 3.1, newest release, is already installed.' && ! has 'Installed through package'"
rel 3.2 1; d0=$(dl); uh upgrade --yes
check "A1 package, newer release 3.2: rc 3, package steps for 3.2, nothing downloaded" "[ $RC = 3 ] && has 'Installed through package steam-arm-setup 3.1. Newest release: 3.2.' && has '  sudo apt install ./steam-arm-setup_3.2_arm64.deb' && has '  sudo steam-arm-setup --keep' && [ \$(dl) = $d0 ] && [ ! -d $R/cache/upgrade ]"
check "A1 package text: no line over 80 columns, no line opening with bracket" "sed -n '/^Installed through package/,/--keep\$/p' <<<\"\$OUT\" | grep -q . && ! sed -n '/^Installed through package/,/--keep\$/p' <<<\"\$OUT\" | awk 'length > 80 || /^\\(/' | grep -q ."
OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "A1 menu Upgrade, package, newer release: package steps screen" "has 'TEXT Upgrade to newest release|Installed through package steam-arm-setup 3.1. Newest release: 3.2.'"
rel 3.0 0; uh upgrade --yes --allow-older
check "A1 package, --allow-older to 3.0: rc 3, downgrade steps, no --allow-older for 3.0 setup" "[ $RC = 3 ] && has 'Release 3.0 is older.' && has '  sudo apt install --allow-downgrades ./steam-arm-setup_3.0_arm64.deb' && grep -qx '  sudo steam-arm-setup --keep' <<<\"\$OUT\" && [ \"\$(cv)\" = 3.1 ]"
sed -i 's/^VERSION=.*/VERSION=3.2/' "$R/etc/steam-arm/steam-arm.conf"; rel 3.1 1; uh upgrade --yes --allow-older
check "A1 package 3.2, --allow-older to 3.1: setup step carries --allow-older" "[ $RC = 3 ] && grep -qx '  sudo steam-arm-setup --keep --allow-older' <<<\"\$OUT\""
OUT=$(PATH="$R/pbin:$PATH" UH_PORT=1 bash "$UH" upgrade --yes 2>&1); RC=$?
check "A1 package, GitHub unreachable: rc 2, no package file named newest" "[ $RC = 2 ] && has 'could not be reached' && ! has 'newest_arm64' && ! has 'Package update'"
check "A1 no newest placeholder in package steps" "! grep -q 'newest}' '$CFG'"
uh upgrade --file "$T/none/Steam.ARM.3.3.zip" --yes
check "A1 package, --file names newer version: package steps for it, file not needed" "[ $RC = 3 ] && has 'steam-arm-setup_3.3_arm64.deb'"

# A2 package install of 3.0 without INSTALLED_FROM
fresh 3.0 0; dpkg_stub; fx_setup 3.0 0 "$R/pkg/install.sh"; rel 3.1 1
ue 'installed_from'; check "A2 key missing, package not owning setup: script" "[ \"\$OUT\" = script ]"
echo "$R/pkg/install.sh" > "$R/dpkg-owned"; ue 'installed_from'
check "A2 key missing, dpkg owns packaged setup script: package" "[ \"\$OUT\" = package ]"
echo "$R/pkg" > "$R/dpkg-owned"; ue 'installed_from'
check "A2 key missing, dpkg owns packaged setup folder: package" "[ \"\$OUT\" = package ]"
echo INSTALLED_FROM=script >> "$R/etc/steam-arm/steam-arm.conf"; ue 'installed_from'
check "A2 key present wins over dpkg" "[ \"\$OUT\" = script ]"
sed -i '/^INSTALLED_FROM=/d' "$R/etc/steam-arm/steam-arm.conf"; d0=$(dl); uh upgrade --yes
check "A2 key missing, package owned: package steps, nothing downloaded" "[ $RC = 3 ] && has 'Installed through package steam-arm-setup 3.0. Newest release: 3.1.' && [ \$(dl) = $d0 ]"
ue 'snap_make manual && cat "$(snap_root)/$SNAP_NAME/MANIFEST"'
check "A2 snapshot of package install without key records INSTALLED_FROM=package" "has 'INSTALLED_FROM=package'"
check "A2 setup writes INSTALLED_FROM on every run (key filled in on next setup)" "grep -A4 '^# Package or script: ' '$INST' | grep -q 'conf_set INSTALLED_FROM package' && grep -A4 '^# Package or script: ' '$INST' | grep -q '^else conf_set INSTALLED_FROM script; fi\$'"

# A3 --allow-older and setups before 3.1
fresh 3.1 1; rel 3.0 0
uh upgrade --yes --allow-older
check "A3 3.1 -> 3.0 with --allow-older: rc 0, 3.0 setup ran with --keep only" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.0 ] && [ \"\$(tail -1 $R/setup.log)\" = 'setup 3.0 --keep' ] && has 'has no --allow-older option'"
check "A3 installed 3.1 saved before setup of 3.0 runs (reason rollback 3.0), history line" "[ \$(snaps) = 1 ] && grep -qx 'REASON=rollback 3.0' $R/lib/snapshots/3.1-*/MANIFEST && grep -qE ' 3\\.1 3\\.0 downgrade ok 3\\.1-' $R/lib/history.log && has 'menu of 3.0 has no Go back item'"
check "A3 staging removed after older setup" "[ -z \"\$(ls -A $R/cache/upgrade 2>/dev/null)\" ]"
fresh 3.1 1; rel 3.0 0; FX_FAIL=1 uh upgrade --yes --allow-older
check "A3 older setup fails: copy of 3.1 named for restore" "[ $RC = 1 ] && has 'Copy of 3.1 saved: sudo steam-arm-config upgrade --rollback 3.1'"
fresh 3.2 1; rel 3.1 1; uh upgrade --yes --allow-older
check "A3 3.2 -> 3.1 with --allow-older: 3.1 setup got --allow-older, its own snapshot step ran" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.1 ] && [ \"\$(tail -1 $R/setup.log)\" = 'setup 3.1 --keep --allow-older' ] && grep -qx 'REASON=upgrade 3.1' $R/lib/snapshots/3.2-*/MANIFEST"
fresh 3.0 0; rel 3.1 1; uh upgrade --yes --allow-older
check "A3 --allow-older with newer release: option not passed on" "[ $RC = 0 ] && [ \"\$(tail -1 $R/setup.log)\" = 'setup 3.1 --keep' ]"
printf 'while [ $# -gt 0 ]; do case "$1" in\n    --allow-older) ALLOW_OLDER=1;;\n  esac; shift; done\n' > "$T/hf.sh"; : > "$T/no.sh"
ue "inst_takes_older '$T/hf.sh' 3.0-hotfix && echo A; inst_takes_older '$T/no.sh' 3.0 || echo B; inst_takes_older '' 3.1 && echo C; inst_takes_older '' 2.3.1 || echo D; inst_takes_older '' 3.1.1 && echo E"
check "A3 option support: parser line or version 3.1 and later" "[ \"\$(echo \$OUT)\" = 'A B C D E' ]"

# A4 unfinished change without snapshot
fresh 3.0 0; ue 'snap_make manual'
sed -i 's/^VERSION=.*/VERSION=3.1/' "$R/etc/steam-arm/steam-arm.conf"
printf 'FROM=3.1\nTO=3.2\nKIND=upgrade\nSNAPSHOT=\nSTARTED=2026-10-18 10:00\n' > "$R/lib/upgrade.state"
ue 'echo "PICK=$(rb_pick)"'; check "A4 rb_pick: no automatic pick without snapshot of unfinished change" "[ \"\$OUT\" = 'PICK=' ]"
uh upgrade --rollback --yes
check "A4 --rollback refused (rc 3), reason, command with VERSION, snapshot of 3.0 listed, nothing changed" "[ $RC = 3 ] && has 'Upgrade from 3.1 to 3.2 did not finish' && has 'no snapshot (--no-snapshot)' && has 'upgrade --rollback VERSION' && has 'Snapshots:' && grep -q '^  3\\.0 ' <<<\"\$OUT\" && [ \"\$(cv)\" = 3.1 ] && [ -f $R/lib/upgrade.state ]"
ue 'ui_menu(){ printf "MENU %s\n" "$*" >&2; return 1; }; up_resolve'
check "A4 menu: no Restore item without snapshot" "! has 'restore Restore' && has 'later Later'"
uh upgrade --rollback 3.0 --yes
check "A4 version named: restore runs, state cleared" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.0 ] && [ ! -f $R/lib/upgrade.state ]"
rm -rf "$R/lib/snapshots"; printf 'FROM=3.0\nTO=3.1\nKIND=upgrade\nSNAPSHOT=\n' > "$R/lib/upgrade.state"
uh upgrade --rollback --yes
check "A4 no snapshot kept at all: refused, says so" "[ $RC = 3 ] && has 'No snapshots kept.'"

# A5 docs match restore of whole /etc/steam-arm
FEAT=$(dirname "$INST")/FEATURES.md
check "A5 FEATURES: no claim of newer keys kept through rollback; whole /etc/steam-arm restored" "! grep -q 'kept through rollback' '$FEAT' && grep -qF \"snapshot's \\\`/etc/steam-arm\\\` in place as whole\" '$FEAT'"

# A6 staging folders cleaned
fresh 3.0 0; rel 3.1 1; FX_KILL=1 uh upgrade --yes
check "A6 interrupted upgrade keeps its staging" "[ -d $R/cache/upgrade/3.1 ]"
mkdir -p "$R/cache/upgrade/2.9"; ue 'snap_prune'
check "A6 prune keeps staging of unfinished upgrade, deletes others" "[ -d $R/cache/upgrade/3.1 ] && [ ! -e $R/cache/upgrade/2.9 ]"
uh upgrade --rollback --yes
check "A6 restore deletes staging of restored change" "[ $RC = 0 ] && [ \"\$(cv)\" = 3.0 ] && [ -z \"\$(ls -A $R/cache/upgrade 2>/dev/null)\" ]"
mkdir -p "$R/cache/upgrade/3.5/x"; ue 'snap_prune --in-setup'
check "A6 prune inside setup leaves staging (setup may run from it)" "[ -d $R/cache/upgrade/3.5 ]"
uh snapshot-keep 2; check "A6 prune outside setup (setting change) deletes leftover staging" "[ ! -e $R/cache/upgrade/3.5 ]"
mkdir -p "$R/cache/release.old1" "$R/cache/release.new1"; touch -d '2 hours ago' "$R/cache/release.old1"; ue 'snap_prune'
check "A6 prune deletes release answer folders older than 1 h only" "[ ! -e $R/cache/release.old1 ] && [ -d $R/cache/release.new1 ]"

# A7 menu deletion of damaged snapshot through CLI guards
fresh 3.0 0; ue 'snap_make manual'; ue 'snap_make manual'
S1=$(ls "$R/lib/snapshots" | LC_ALL=C sort | head -1); S2=$(ls "$R/lib/snapshots" | LC_ALL=C sort | tail -1)
echo x >> "$R/lib/snapshots/$S1/files.tar.gz"
SD="$ST; self_path(){ echo \"\$UH\"; }"
( flock "$R/run/steam-arm-setup.lock" sleep 3 ) & LP=$!; sleep 0.3
OUT=$(PATH="$R/pbin:$PATH" PICK=del:$S1 UH_EVAL="$SD; maint_rollback" bash "$UH" 2>&1); wait "$LP"
check "A7 menu delete while setup runs: refused, snapshot kept" "has 'Another setup run is in progress; nothing deleted.' && [ -d $R/lib/snapshots/$S1 ]"
printf 'FROM=3.0\nTO=3.1\nKIND=upgrade\nSNAPSHOT=%s\n' "$S1" > "$R/lib/upgrade.state"
uh upgrade --delete "$S1"
check "A7 delete of unfinished change's snapshot refused (rc 3), kept" "[ $RC = 3 ] && has 'is kept' && [ -d $R/lib/snapshots/$S1 ]"
rm -f "$R/lib/upgrade.state"
uh upgrade --delete "$S2"; check "A7 delete of verified snapshot refused" "[ $RC = 3 ] && has 'not damaged' && [ -d $R/lib/snapshots/$S2 ]"
uh upgrade --delete ../x; R1=$RC; uh upgrade --delete .tmp-x; check "A7 names with slash or leading dot refused (rc 2)" "[ $R1 = 2 ] && [ $RC = 2 ]"
OUT=$(PATH="$R/pbin:$PATH" PICK=del:$S1 UH_EVAL="$SD; maint_rollback" bash "$UH" 2>&1)
check "A7 menu delete of damaged snapshot: done through CLI, message shown" "has 'MSG Go back to previous version|Deleted damaged snapshot $S1.' && [ ! -e $R/lib/snapshots/$S1 ] && [ -d $R/lib/snapshots/$S2 ]"
check "A7 menu screen has no direct rm" "! fn maint_rollback '$CFG' | grep -q 'rm -rf'"

# A8 release answer in private folder
fresh 3.0 0; rel 3.1 1; mkdir -p "$T/tmpd"; rm -rf "$T/tmpd/"*
for a in "upgrade --check" "upgrade --yes"; do
  OUT=$(PATH="$R/pbin:$PATH" XDG_RUNTIME_DIR='' TMPDIR="$T/tmpd" bash "$UH" $a 2>&1)
done
mode 403; OUT=$(PATH="$R/pbin:$PATH" XDG_RUNTIME_DIR='' TMPDIR="$T/tmpd" bash "$UH" upgrade --check 2>&1); mode ok
OUT=$(PATH="$R/pbin:$PATH" XDG_RUNTIME_DIR='' TMPDIR="$T/tmpd" UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "A8 no temporary file or folder left (check, upgrade, refused request, menu)" "[ -z \"\$(ls -A $T/tmpd)\" ]"
ue 'id(){ [ "$*" = -u ] && echo 0 || command id "$@"; }; rel_fetch; echo "TMP=$REL_TMP"; stat -c "MODE=%a" "$REL_TMP"; ls "$REL_TMP"; rel_done; ls -A "$SA_UPCACHE"'
check "A8 as root: answer in mode 700 folder under cache, notes inside, folder gone after" "grep -q \"^TMP=$R/cache/release\\.\" <<<\"\$OUT\" && has 'MODE=700' && has 'notes.md' && ! grep -q '^release\\.' <<<\"\$OUT\""
rm -rf "$R/cache"; mkdir -p "$T/elsewhere"; ln -s "$T/elsewhere" "$R/cache"
ue 'id(){ [ "$*" = -u ] && echo 0 || command id "$@"; }; rel_fetch; echo "rc=$? $REL_ERR"'
check "A8 as root, cache folder is a link: refused, nothing written through it" "has 'rc=2 No private temporary folder' && [ -z \"\$(ls -A $T/elsewhere)\" ]"
rm -f "$R/cache"
check "A8 notes file created new, never through a link (O_EXCL, O_NOFOLLOW); no name beside temp file" "fn rel_fetch '$CFG' | grep -q 'O_EXCL | os.O_NOFOLLOW' && ! grep -q 'REL_NOTES=\"\$f.notes\"' '$CFG'"
mkdir -p "$R/ucache"; rm -f "$R/ucache/release-notes.md"; ln -s "$T/elsewhere/target" "$R/ucache/release-notes.md"
uh upgrade --check
check "A8 stored notes replace planted link by rename, link target untouched" "[ ! -L $R/ucache/release-notes.md ] && [ -f $R/ucache/release-notes.md ] && [ ! -e $T/elsewhere/target ]"

# A9 package system: going back names package command of menus before 3.1
fresh 3.0 0; dpkg_stub; ue 'snap_make manual'; S=$(ls "$R/lib/snapshots" | head -1)
fx_setup 3.1 1 "$R/pkg/install.sh"; echo "$R/pkg/install.sh" > "$R/dpkg-owned"
ue "rb_text '$S'"
check "A9 confirm text names package 3.1 that Update / Repair of 3.0 runs" "has 'Package steam-arm-setup 3.1 stays installed: Update / Repair in 3.0 runs it and installs 3.1 again.'"
rm -f "$R/dpkg-owned"; ue "rb_text '$S'"; check "A9 no package: no package sentence" "! has 'Package steam-arm-setup'"

# A10 page-size block removal after snapshot step
check "A10 Pi page-size block removed only after snapshot step" "a=\$(grep -n 'sa_menu_call upgrade --setup-begin' '$INST' | cut -d: -f1); b=\$(grep -n '^  ps_remove || die' '$INST' | cut -d: -f1); [ -n \"\$b\" ] && [ \$(grep -c '^  ps_remove || die' '$INST') = 1 ] && [ \$a -lt \$b ]"

# ---------- P package asset: apt install from menu ----------
# release with zip and package assets; package install of version $1 (setup stand-in at packaged path, dpkg owns it)
relp(){ rm -f "$M/assets/"*; fx_zip "$1" 1 "$M/assets"; fx_deb "$1" "$M/assets"; fx_release "$1" "$M" "$UH_PORT"; mode ok; }
pkgfresh(){
  fresh "$1" "$2"; dpkg_stub; fx_apt; echo INSTALLED_FROM=package >> "$R/etc/steam-arm/steam-arm.conf"
  fx_setup "$1" "$2" "$R/pkg/install.sh"; echo "$R/pkg/install.sh" > "$R/dpkg-owned"; echo "$1" > "$R/dpkg-ver"
  printf '#!/bin/sh\nexec bash %s "$@"\n' "$R/pkg/install.sh" > "$R/pbin/steam-arm-setup"; chmod 755 "$R/pbin/steam-arm-setup"
  rm -f "$R/apt.log" "$R/apt-fail"
}
pkgfresh 3.0 0; relp 3.1
uh upgrade --check
check "P1 check, package install, release with package asset: upgrade command, no build steps" "[ $RC = 0 ] && has 'Package steam-arm-setup_3.1_arm64.deb attached to release.' && has 'sudo steam-arm-config upgrade' && ! has 'Package update: build' && grep -qs '^DEB=yes\$' $R/ucache/release-check $R/lib/release-check"
d0=$(dl); uh upgrade --yes
check "P1 package upgrade: rc 0, installed message names package and previous version" "[ $RC = 0 ] && has 'Steam ARM 3.1 installed (package steam-arm-setup 3.1). Previous version 3.0 kept (Maintenance > Go back to previous version).'"
check "P1 package and sidecar downloaded (2 requests), zip not" "[ \$(dl) = \$(( d0 + 2 )) ] && tail -2 $M/requests | grep -q 'steam-arm-setup_3.1_arm64.deb\$' && tail -2 $M/requests | grep -q 'steam-arm-setup_3.1_arm64.deb.sha256\$' && ! tail -2 $M/requests | grep -q 'zip'"
check "P1 plan shown before install (snapshot, apt-get, setup)" "has 'Plan: 1. save 3.0' && has '2. apt-get install steam-arm-setup_3.1_arm64.deb' && has '3. steam-arm-setup --keep'"
check "P1 apt-get: install -y, noninteractive, conffiles kept local, lock timeout, staged file path, no downgrade flag" "grep -q '^apt-get install -y -o DPkg::Lock::Timeout=120 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold $R/cache/upgrade/3.1/steam-arm-setup_3.1_arm64.deb\$' $R/apt.log && grep -q 'frontend=noninteractive' $R/apt.log && ! grep -q allow-downgrades $R/apt.log"
check "P1 snapshot of 3.0 made and setup lock held before apt-get runs; state file written" "grep -qx 'snapshots=1 lock=held state=yes frontend=noninteractive' $R/apt.log && grep -qx 'REASON=upgrade 3.1' $R/lib/snapshots/3.0-*/MANIFEST && grep -qx 'INSTALLED_FROM=package' $R/lib/snapshots/3.0-*/MANIFEST"
check "P1 steam-arm-setup --keep ran after apt (packaged 3.1 setup), VERSION 3.1" "[ \"\$(tail -1 $R/setup.log)\" = 'setup 3.1 --keep' ] && [ \"\$(cv)\" = 3.1 ] && grep -qx 'SA_VERSION=3.1' $R/pkg/install.sh"
check "P1 one snapshot (setup continued state, no second one), state cleared, history, staging gone" "[ \$(snaps) = 1 ] && [ ! -f $R/lib/upgrade.state ] && grep -qE ' 3\\.0 3\\.1 upgrade ok 3\\.0-' $R/lib/history.log && [ -z \"\$(ls -A $R/cache/upgrade 2>/dev/null)\" ]"
check "P1 upgrade log names package asset and sha256" "grep -q 'Package asset: steam-arm-setup_3.1_arm64.deb' $R/ucache/upgrade-*.log && grep -q '^sha256 [0-9a-f]\\{64\\}  steam-arm-setup_3.1_arm64.deb\$' $R/ucache/upgrade-*.log"

pkgfresh 3.0 0; relp 3.1; echo "$(printf '0%.0s' $(seq 1 64))  steam-arm-setup_3.1_arm64.deb" > "$M/assets/steam-arm-setup_3.1_arm64.deb.sha256"; fx_release 3.1 "$M" "$UH_PORT"
uh upgrade --yes
check "P2 sidecar hash wrong: rc 2, checksum text, apt not run, no snapshot, staging gone" "[ $RC = 2 ] && has 'Checksum of steam-arm-setup_3.1_arm64.deb does not match its .sha256 file. Nothing was installed.' && [ ! -f $R/apt.log ] && [ \$(snaps) = 0 ] && [ \"\$(cv)\" = 3.0 ] && [ -z \"\$(ls -A $R/cache/upgrade 2>/dev/null)\" ]"
relp 3.1; sed -i 's/_arm64.deb$/_arm64.deb.other/' "$M/assets/steam-arm-setup_3.1_arm64.deb.sha256"; fx_release 3.1 "$M" "$UH_PORT"
uh upgrade --yes; check "P2 sidecar names other file: rc 2, form text, apt not run" "[ $RC = 2 ] && has 'not in the expected form' && [ ! -f $R/apt.log ]"
rm -f "$M/assets/"*; fx_zip 3.1 1 "$M/assets"; fx_deb 3.1 "$M/assets"; FX_DEB_DIGEST="sha256:$(printf 'a%.0s' $(seq 1 64))" fx_release 3.1 "$M" "$UH_PORT"
uh upgrade --yes
check "P3 GitHub digest differs: rc 2, digest text, apt not run, no snapshot" "[ $RC = 2 ] && has \"does not match GitHub's digest\" && [ ! -f $R/apt.log ] && [ \$(snaps) = 0 ] && [ \"\$(cv)\" = 3.0 ]"
rm -f "$M/assets/"*; fx_zip 3.1 1 "$M/assets"; fx_deb 3.1 "$M/assets"; FX_DEB_DIGEST=none fx_release 3.1 "$M" "$UH_PORT"
d0=$(dl); uh upgrade --yes
check "P3 package asset without GitHub digest: rc 2, nothing downloaded or installed" "[ $RC = 2 ] && has 'lists no GitHub digest' && [ \$(dl) = $d0 ] && [ ! -f $R/apt.log ]"
relp 3.1; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [a.update(size=a["size"]+5) for a in d["assets"] if a["name"].endswith(".deb")]; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
uh upgrade --yes; check "P3 package size differs from API size: rc 2, incomplete, apt not run" "[ $RC = 2 ] && has 'Download incomplete' && [ ! -f $R/apt.log ]"

relp 3.1; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["assets"]=[a for a in d["assets"] if not a["name"].startswith("steam-arm-setup")]; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
d0=$(dl); uh upgrade --yes
check "P4 release without package asset: rc 3, build-from-tag steps, nothing downloaded, apt not run" "[ $RC = 3 ] && has 'Package update: build steam-arm-setup_3.1_arm64.deb (build-deb.sh).' && [ \$(dl) = $d0 ] && [ ! -f $R/apt.log ]"
uh upgrade --check; check "P4 check without package asset: build steps, DEB=no stored" "has 'Package update: build' && grep -qs '^DEB=no\$' $R/ucache/release-check $R/lib/release-check"
relp 3.1; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [a.update(browser_download_url=a["browser_download_url"].replace("/steam-arm-setup_", "/x/../steam-arm-setup_")) for a in d["assets"] if a["name"].endswith(".deb")]; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
d0=$(dl); uh upgrade --yes
check "P4 package address not exactly <downloads>/<tag>/<name>: package asset ignored, nothing downloaded" "[ $RC = 3 ] && has 'Package update: build' && [ \$(dl) = $d0 ]"
relp 3.1; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [a.update(name=a["name"].replace("3.1", "3.1;id")) for a in d["assets"] if a["name"].startswith("steam-arm-setup")]; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
uh upgrade --yes; check "P4 asset name not matching release version: ignored (no command from asset names)" "[ $RC = 3 ] && has 'Package update: build' && [ ! -f $R/apt.log ]"

pkgfresh 3.0 0; mkdir -p "$T/pdl"; rm -f "$T/pdl/"*; fx_deb 3.1 "$T/pdl"; n0=$(reqs)
uh upgrade --file "$T/pdl/steam-arm-setup_3.1_arm64.deb" --yes
check "P5 --file package: rc 0, no network, apt got staged copy, setup ran" "[ $RC = 0 ] && [ \$(reqs) = $n0 ] && grep -q \"$R/cache/upgrade/3.1/steam-arm-setup_3.1_arm64.deb\\\$\" $R/apt.log && [ \"\$(cv)\" = 3.1 ]"
pkgfresh 3.0 0; rm "$T/pdl/steam-arm-setup_3.1_arm64.deb.sha256"
uh upgrade --file "$T/pdl/steam-arm-setup_3.1_arm64.deb" --yes
check "P5 --file package without .sha256: rc 2, apt not run" "[ $RC = 2 ] && has '.sha256 file beside it needed' && [ ! -f $R/apt.log ]"
fx_deb 3.1 "$T/pdl"; fresh 3.0 0; fx_apt; rm -f "$R/apt.log"
uh upgrade --file "$T/pdl/steam-arm-setup_3.1_arm64.deb" --yes
check "P5 --file package on zip install: rc 3, refused, apt not run" "[ $RC = 3 ] && has 'upgrade with that zip' && [ ! -f $R/apt.log ] && [ \"\$(cv)\" = 3.0 ]"
cp "$T/pdl/steam-arm-setup_3.1_arm64.deb" "$T/pdl/steam-arm-setup_3.1\$(id)_arm64.deb"; pkgfresh 3.0 0
uh upgrade --file "$T/pdl/steam-arm-setup_3.1\$(id)_arm64.deb" --yes
check "P5 --file package name with shell characters: rc 2, refused" "[ $RC = 2 ] && has 'File name is not steam-arm-setup_<version>_arm64.deb' && [ ! -f $R/apt.log ]"

rm -f "$M/assets/"*; fx_zip 3.1 1 "$M/assets"; fx_deb 3.1 "$M/assets"; FX_DEB_DIGEST="sha256:XYZ" fx_release 3.1 "$M" "$UH_PORT"
d0=$(dl); uh upgrade --yes
check "P3 malformed GitHub digest: treated as missing, refused, nothing downloaded" "[ $RC = 2 ] && has 'lists no GitHub digest' && [ \$(dl) = $d0 ] && [ ! -f $R/apt.log ]"
relp 3.1; s1=$(cat "$M/assets/steam-arm-setup_3.1_arm64.deb.sha256"); printf '%s\n%s\n' "$s1" "$s1" > "$M/assets/steam-arm-setup_3.1_arm64.deb.sha256"; fx_release 3.1 "$M" "$UH_PORT"
uh upgrade --yes; check "P2 sidecar with two lines: rc 2, form text, apt not run" "[ $RC = 2 ] && has 'not in the expected form' && [ ! -f $R/apt.log ]"
relp 3.1; rm "$M/assets/steam-arm-setup_3.1_arm64.deb.sha256"; fx_deb 3.1 "$M/assets"; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["assets"]=[a for a in d["assets"] if not a["name"].endswith(".deb.sha256")]; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
d0=$(dl); uh upgrade --yes
check "P4 package asset without its .sha256 asset: ignored, build steps, nothing downloaded" "[ $RC = 3 ] && has 'Package update: build' && [ \$(dl) = $d0 ]"
pkgfresh 3.0 0; mkdir -p "$T/pdl2"; rm -f "$T/pdl2/"*; fx_deb 3.1 "$T/pdl2" ctl-package=other-tool
uh upgrade --file "$T/pdl2/steam-arm-setup_3.1_arm64.deb" --yes
check "P5 --file package whose control names other package: rc 2, refused before lock, apt not run, no snapshot" "[ $RC = 2 ] && has 'is not package steam-arm-setup 3.1 for arm64 (control: other-tool/3.1/arm64)' && [ ! -f $R/apt.log ] && [ \$(snaps) = 0 ]"
rm -f "$T/pdl2/"*; fx_deb 3.1 "$T/pdl2" ctl-arch=amd64; uh upgrade --file "$T/pdl2/steam-arm-setup_3.1_arm64.deb" --yes
check "P5 --file package for other architecture: rc 2, apt not run" "[ $RC = 2 ] && has 'control: steam-arm-setup/3.1/amd64' && [ ! -f $R/apt.log ]"
pkgfresh 3.2 1; rm -f "$T/pdl2/"*; fx_deb 3.1 "$T/pdl2"
uh upgrade --file "$T/pdl2/steam-arm-setup_3.1_arm64.deb" --yes
check "P6 --file older package without --allow-older: rc 3, apt not run" "[ $RC = 3 ] && has 'newer than this file (3.1)' && [ ! -f $R/apt.log ]"
uh upgrade --file "$T/pdl2/steam-arm-setup_3.1_arm64.deb" --yes --allow-older
check "P6 --file older package with --allow-older: apt --allow-downgrades, VERSION 3.1" "[ $RC = 0 ] && grep -q -- '--allow-downgrades' $R/apt.log && [ \"\$(cv)\" = 3.1 ]"
check "P1b lock released before steam-arm-setup (setup stand-in takes lock as installer does) and apt runs without fd 9" "fn up_deb '$CFG' | grep -q '</dev/null 9>&- 2>&1' && grep -q 'flock -n 8' '$UH_FIX'"
pkgfresh 3.0 0; relp 3.1; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["assets"]=[a for a in d["assets"] if not a["name"].startswith("steam-arm-setup")]; json.dump(d,open(sys.argv[1],"w"))' "$M/release.json"
OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$ST; maint_update_check" bash "$UH" 2>&1)
check "P9 menu Check for new version, package without asset: message only, no Upgrade now" "has 'MSG Check for new version|' && has 'Package update: build' && ! has 'Upgrade now'"
pkgfresh 3.0 0; relp 3.1; n0=$(reqs); ue 'up_check_open'
check "P9 menu start with default settings: no request" "[ \$(reqs) = $n0 ]"

pkgfresh 3.2 1; relp 3.1
uh upgrade --yes
check "P6 package 3.2, newest release 3.1: rc 1, nothing to do, apt not run" "[ $RC = 1 ] && has 'Installed 3.2 is newer than newest release (3.1). Nothing to do.' && [ ! -f $R/apt.log ]"
uh upgrade --yes --allow-older
check "P6 --allow-older: rc 0, apt-get --allow-downgrades, setup --keep --allow-older, VERSION 3.1" "[ $RC = 0 ] && grep -q '^apt-get install -y .* --allow-downgrades $R/cache/upgrade/3.1/steam-arm-setup_3.1_arm64.deb\$' $R/apt.log && [ \"\$(tail -1 $R/setup.log)\" = 'setup 3.1 --keep --allow-older' ] && [ \"\$(cv)\" = 3.1 ] && grep -qx 'REASON=upgrade 3.1' $R/lib/snapshots/3.2-*/MANIFEST"

pkgfresh 3.0 0; relp 3.1; touch "$R/apt-fail"
uh upgrade --yes; P7=$RC
check "P7 apt-get fails: non-zero, restore named, snapshot kept, state left (TO 3.1), setup not run" "[ $P7 != 0 ] && has 'apt-get could not install steam-arm-setup_3.1_arm64.deb' && has 'Restore 3.0: sudo steam-arm-config upgrade --rollback' && [ \$(snaps) = 1 ] && grep -qx 'TO=3.1' $R/lib/upgrade.state && ! grep -qs 'setup 3.1' $R/setup.log && [ \"\$(cv)\" = 3.0 ]"
OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "P7 menu Upgrade after failed apt: restore offered (Unfinished change, Restore 3.0)" "has 'MENU Unfinished change|' && has 'Restore 3.0' && ! has 'Run 3.1 setup again'"
rm -f "$R/apt-fail"; uh upgrade --rollback --yes
check "P7 restore after failed apt: 3.0 restored, state cleared, package files untouched by restore" "[ $RC = 0 ] && has 'Steam ARM 3.0 restored.' && [ ! -f $R/lib/upgrade.state ] && grep -qx 'SA_VERSION=3.0' $R/pkg/install.sh"
pkgfresh 3.0 0; relp 3.1; FX_FAIL=1 uh upgrade --yes
check "P7 packaged setup fails after apt: restore and setup-again named" "[ $RC != 0 ] && has 'Setup of 3.1 stopped' && has 'Run 3.1 setup again: sudo steam-arm-setup --keep'"
OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "P7 menu after failed packaged setup: Restore 3.0 and Run 3.1 setup again" "has 'Restore 3.0' && has 'Run 3.1 setup again'"

pkgfresh 3.0 0; relp 3.1; d0=$(dl)
( flock "$R/run/steam-arm-setup.lock" sleep 3 ) & LP=$!; sleep 0.3
uh upgrade --yes; wait "$LP"
check "P8 setup lock held: rc 3, nothing downloaded, apt not run" "[ $RC = 3 ] && has 'Another setup run is in progress.' && [ \$(dl) = $d0 ] && [ ! -f $R/apt.log ]"
touch "$R/steam-running"; uh upgrade --yes; rm -f "$R/steam-running"
check "P8 Steam running: rc 3, apt not run" "[ $RC = 3 ] && has 'Steam ARM is running' && [ ! -f $R/apt.log ]"
uh upgrade; check "P8 without --yes and without terminal: asks for --yes, nothing downloaded" "[ $RC = 1 ] && has 'add --yes' && [ \$(dl) = $d0 ]"

pkgfresh 3.0 0; relp 3.1
OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$ST; maint_upgrade" bash "$UH" 2>&1)
check "P9 menu Upgrade, package with asset: confirm names package file, apt and setup; done screen" "has 'YESNO Upgrade to newest release|Steam ARM 3.1 (installed: 3.0, package steam-arm-setup)' && has 'steam-arm-setup_3.1_arm64.deb and its .sha256 file' && has 'steam-arm-setup --keep' && has 'TEXT Upgrade to newest release: done|' && [ \"\$(cv)\" = 3.1 ]"
pkgfresh 3.0 0; relp 3.1
OUT=$(PATH="$R/pbin:$PATH" UH_EVAL="$ST; maint_update_check" bash "$UH" 2>&1)
check "P9 menu Check for new version, package with asset: Upgrade now offered" "has 'Upgrade now'"
check "P9 no automatic network use: menu start calls only up_check_open (default off)" "[ \$(grep -c 'up_check_open' '$CFG') = 2 ] && fn check_on_open '$CFG' | grep -q 'echo off'"
check "P10 zip path never writes package files: no apt-get outside up_deb, snap_restore refuses package paths" "[ \$(grep -c 'apt-get install -y' '$CFG') = 1 ] && fn up_deb '$CFG' | grep -q 'apt-get install -y' && fn snap_restore '$CFG' | grep -q 'usr/share/steam-arm-setup/'"
check "P10 order in up_deb: verify before lock, lock before snapshot, snapshot before apt-get" "f=\$(fn up_deb '$CFG'); a=\$(grep -n 'up_verify ' <<<\"\$f\" | cut -d: -f1); b=\$(grep -n 'flock -n 9' <<<\"\$f\" | cut -d: -f1); c=\$(grep -n 'snap_make ' <<<\"\$f\" | cut -d: -f1); d=\$(grep -n 'apt-get install -y' <<<\"\$f\" | cut -d: -f1); [ \$a -lt \$b ] && [ \$b -lt \$c ] && [ \$c -lt \$d ]"

# ---------- misc ----------
check "M1 shipped menu has no test hooks (fake root only through harness overrides)" "! grep -qE 'UHR|UH_|SA_TEST|mockgh' '$CFG'"
check "M2 --help lists upgrade options" "bash '$CFG' --help | grep -q 'upgrade --rollback \\[VER\\]' && bash '$CFG' --help | grep -q 'snapshot-keep \\[1-5\\]'"
uh upgrade --bogus; check "M3 unknown upgrade option: rc 2" "[ $RC = 2 ]"
echo "upgrade 3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
