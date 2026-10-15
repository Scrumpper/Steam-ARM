#!/bin/bash
# 2.3.1 hardware report scrubbing: sanitize() and its python scrubber extracted from the settings menu (SARM_CFG picks
# another menu) and run on synthetic report lines; account, host, home, Steam client folder and python3 stubbed. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST; CFG=$SARM_CFG
T=$(mktemp -d /tmp/sarm232-san.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
fn(){ N=$1 awk '!f && index($0, ENVIRON["N"] "(){") == 1 { f = 1; print; if ($0 !~ /\{$/) exit; next } f { print } f && /^}$/ { exit }' "$2"; }
has(){ grep -qF -- "$1" <<<"$OUT"; }

check "installer and menu parse (bash -n)" "bash -n '$INST' && bash -n '$CFG'"
check "embedded menu equals steam-arm-config file" "awk '/^menu_app\\(\\)\\{ cat <<.STEAMARMCONFIG.\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f' '$INST' | cmp -s - '$CFG'"
S=$T/san.sh
{ sed -n '/^san_py(){/,/^}$/p' "$CFG"; fn sanitize "$CFG"; fn have "$CFG"
  cat <<'EOF'
game_user(){ echo "$GU"; }
game_home(){ echo "${GH:-/home/$GU}"; }
hostname(){ echo "$HN"; }
id(){ [ "$1" = -un ] && { echo "$GU"; return; }; command id "$@"; }
getent(){ [ "$1" = passwd ] && [ "$2" = "$GU" ] && { echo "$GU:x:1000:1000:$GECOS:/home/$GU:/bin/bash"; return; }; command getent "$@"; }
steam_dir(){ echo "$SD"; }
EOF
} > "$S"
check "sanitize and scrubber extracted" "grep -q '^sanitize()' $S && grep -q '^san_py()' $S"
mkdir -p "$T/sd/config"
# run(account, host, text[, vdf]): OUT = scrubbed text
run(){ if [ -n "${4:-}" ]; then printf '%s\n' "$4" > "$T/sd/config/loginusers.vdf"; else rm -f "$T/sd/config/loginusers.vdf"; fi
  OUT=$(GU=$1 HN=$2 SD=$T/sd SUDO_USER= bash -c ". '$S'; sanitize" <<<"$3" 2>&1); }

# ---------- account named with a common word ----------
run steam box $'steam-arm-config 2.3 ran by steam, Steam ARM, /home/steam/.local/share/Steam\nsteam-arm: renderer: Mali\n/media/steam/USB/SteamLibrary\nGAMEUSER=steam'
check "S1 account 'steam': steam-arm-config, steam-arm: lines and Steam paths kept" "has 'steam-arm-config 2.3 ran by' && has 'steam-arm: renderer: Mali' && has '~/.local/share/Steam' && ! has '<user>-arm'"
check "S2 account 'steam': path and assignment context replaced" "has '/media/<user>/USB' && has 'GAMEUSER=<user>' && ! has '/home/steam'"
# ---------- regex characters in names ----------
run john.doe johns-laptop $'user johnXdoe and john.doe on johns-laptop'
check "S3 account with dot: literal match only (johnXdoe kept)" "has 'user johnXdoe and <user> on <host>'"
# ---------- host before account ----------
run alice alice-pi $'LOCAL_HOSTNAME=alice-pi&LANGUAGE\nhost alice-pi.local up'
check "S4 host holding account name: whole host replaced" "has 'LOCAL_HOSTNAME=<host>&LANGUAGE' && has 'host <host>.local up' && ! has alice"
# ---------- Steam IDs ----------
run alice box $'[U:1:123456789] -steamid=76561198012345678 userdata/123456789/config\nSTEAM_0:1:61728394 steamid: 76561198012345678'
check "S5 SteamID64, SteamID3, SteamID2, -steamid=, userdata/<id> removed" "has '<steamid> -steamid=<steamid> userdata/<steamid>/config' && has '<steamid> steamid: <steamid>'"
check "S6 SteamID forms leave no number" "! grep -qE '[0-9]{8,}' <<<\"\$OUT\""
# ---------- Steam login and persona names (loginusers.vdf) ----------
VDF=$'"users"\n{\n\t"76561198012345678"\n\t{\n\t\t"AccountName"\t\t"alicegamer"\n\t\t"PersonaName"\t\t"Big Al Smith"\n\t\t"RememberPassword"\t\t"1"\n\t}\n}'
run alice box $'SteamUser=alicegamer SteamAppUser=alicegamer\nfriends: Big Al Smith online\nlogin AliceGamer ok\nid 52079950 here' "$VDF"
check "S7 login name (any case) and persona name removed" "! grep -qi alicegamer <<<\"\$OUT\" && ! has 'Big Al Smith' && has 'SteamUser=<login>' && has 'friends: <login> online'"
check "S8 account ID derived from SteamID64 key removed" "has 'id <steamid> here'"
run alice box $'SteamUser=someone SteamAppUser=other'
check "S9 SteamUser / SteamAppUser values removed without loginusers.vdf" "has 'SteamUser=<login> SteamAppUser=<login>'"
run alice box "$VDF"
check "S10 loginusers.vdf lines in report: names and SteamID removed" "! grep -qi alicegamer <<<\"\$OUT\" && ! has 'Big Al' && ! has 76561198012345678"
# ---------- addresses ----------
run alice box $'local address (10.20.30.129:10269) public 203.0.113.7 v6 2001:db8:1234::5 fe80::1c2b:3cff:fe4d:5e6f%eth0\nfull 2001:0db8:0000:0000:0000:ff00:0042:8329 loop ::1 any ::\nmac aa:bb:cc:dd:ee:ff altname enx22e02036b7e4 wlx70f754b83dd7'
check "S11 private and public IPv4 removed" "has 'local address (<ip>:10269) public <ip> v6'"
check "S12 IPv6 (compressed, link-local with zone, full) removed; ::1 and :: kept" "has 'v6 <ip6> <ip6>' && has 'full <ip6> loop ::1 any ::' && ! has 2001: && ! has fe80"
check "S13 MAC and interface names built from MAC removed" "has 'mac <mac> altname enx<mac> wlx<mac>'"
run alice box $'2026-10-09 10:00:01 start\nstd::string vk::Device a::b\nversion 1.2.3.4 of something, v1.2.3.4, conformanceVersion = 1.4.0.0\napi 1.3.275 panvk 26.1.4 kernel 6.1.172-x\n127.0.0.1 and 0.0.0.0'
check "S14 times, C++ names, version numbers and loopback kept" "has '10:00:01 start' && has 'std::string vk::Device a::b' && has 'version 1.2.3.4 of' && has 'v1.2.3.4' && has '= 1.4.0.0' && has 'api 1.3.275 panvk 26.1.4 kernel 6.1.172-x' && has '127.0.0.1 and 0.0.0.0'"
# ---------- e-mail, tokens, Wine paths ----------
run alice box $'mail alice@example.com and bob.smith@mail.example.org\nhttps://store.example/x?token=abc123&ok=1 password=hunter2\nZ:\\home\\alice\\Games\\x.exe  Z:\\\\home\\\\alice\\\\Games  /run/media/alice/Disk'
check "S15 e-mail addresses removed (domain too)" "has 'mail <email> and <email>' && ! has example.com"
check "S16 token and password values removed" "has 'token=<removed>&ok=1 password=<removed>'"
check "S17 Wine home paths and /run/media account removed" "! has alice && has 'Z:\\~\\Games'"
# ---------- self-check ----------
run alice box $'path xalicegamerx/cache\nother line' "$VDF"
check "S18 login name left inside a longer word: whole line removed" "has '(line removed: personal data)' && has 'other line' && ! grep -qi alicegamer <<<\"\$OUT\""
# ---------- home outside /home, full name ----------
OUT=$(GU=zed GH=/srv/games/zed HN=box GECOS='Zed Example,,,' SD=$T/sd SUDO_USER= bash -c ". '$S'; sanitize" <<<$'dir /srv/games/zed/.local/share/steam-arm\nowner Zed Example' 2>&1)
check "S19 game home outside /home and full name removed" "has 'dir ~/.local/share/steam-arm' && has 'owner <user>'"
# ---------- no python3: nothing passes ----------
mkdir -p "$T/nopy"; for x in bash cat awk; do ln -s "$(command -v $x)" "$T/nopy/$x"; done
OUT=$(GU=alice HN=box SD=$T/sd PATH=$T/nopy bash -c ". '$S'; sanitize" <<<'secret alice line' 2>&1); RC=$?
check "S20 python3 missing: report text left out, status 1" "[ $RC = 1 ] && ! has alice && has 'python3 is missing'"
# ---------- menu text ----------
check "S21 menu names removed categories" "fn maint_report '$CFG' | grep -q 'Steam sign-in names, Steam IDs'"
echo "sanitize 2.3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
