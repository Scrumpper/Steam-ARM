#!/bin/bash
# 2.3 x86 client fallback, setup side: client_pick table, core names, memory gate, warning texts, --detect and
# option lines, client_dl against a stand-in curl, --client-check results, native package unpack unchanged from
# 2.2, RootFS bwrap aside and back, step 1 bwrap check, pv-bwrap and package-tool stubs, earlier client folder.
# Blocks from the installer copy in ~/.cache/sarm<NN>-work (SARM_INST picks another file); fake /proc files. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
OLD=$(sarm_old 2.2)
T=$(mktemp -d /tmp/sarm232-cx86.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -6; fail=$((fail + 1)); fi; }
block(){ A=$1 B=$2 awk '!f && $0 ~ ENVIRON["A"] {f=1; print; next} f {print} f && $0 ~ ENVIRON["B"] {exit}' "${3:-$INST}"; }
OUT=""
check "X1 installer parses (bash -n)" "bash -n '$INST'"

# ---------- CPU helpers and client choice ----------
H=$T/helpers.sh
awk '/^cpu_features\(\)/{f=1} /^# curl progress bar/{exit} f' "$INST" > "$H"
check "X2 helpers extracted (cpu_lse, cpu_label, client_pick, mem_gate)" "grep -q '^cpu_lse()' $H && grep -q '^cpu_label()' $H && grep -q '^client_pick()' $H && grep -q '^mem_gate()' $H"
cpu(){ # name, then "part:features" per core
  local f=$T/cpu-$1 n=0 c; shift; : > "$f"
  for c in "$@"; do printf 'processor\t: %d\nBogoMIPS\t: 48.00\nFeatures\t: %s\nCPU implementer\t: 0x41\nCPU part\t: %s\n\n' "$n" "${c#*:}" "${c%%:*}" >> "$f"; n=$((n + 1)); done
}
V80="fp asimd evtstrm crc32 cpuid"; V82="fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp"
cpu a72 0xd08:"$V80" 0xd08:"$V80" 0xd08:"$V80" 0xd08:"$V80"
cpu rk3588 0xd05:"$V82" 0xd05:"$V82" 0xd05:"$V82" 0xd05:"$V82" 0xd0b:"$V82" 0xd0b:"$V82" 0xd0b:"$V82" 0xd0b:"$V82"
cpu odd 0xABC:"$V82" 0xabc:"$V82"
printf 'processor\t: 0\nBogoMIPS\t: 48.00\n' > "$T/cpu-none"
mem(){ printf 'MemTotal:       %s kB\nMemFree:          1000 kB\n' "$2" > "$T/mem-$1"; }
mem 1g 999424; mem 2g 1887436; mem 4g 3884000
# crun CPU MEM CONF 'commands' [env...]: helpers with /proc files pointed at fixtures, die/warn/conf_get stubbed
crun(){
  local c=$1 m=$2 conf=$3 cmd=$4; shift 4
  printf '%s\n' "$conf" > "$T/conf"
  sed "s#/proc/cpuinfo#$T/cpu-$c#g; s#/proc/meminfo#$T/mem-$m#g" "$H" > "$T/h-run.sh"
  printf 'die(){ echo "DIE $*"; exit 1; }\nwarn(){ echo "WARN $*"; }\nconf_get(){ sed -n "s/^$1=//p" %s | tail -1; }\n. %s\n%s\n' "$T/conf" "$T/h-run.sh" "$cmd" > "$T/c.sh"
  env -u STEAM_ARM_ALLOW_ARMV80 "$@" bash "$T/c.sh" 2>&1
}
pick(){ crun "$1" 4g "$2" "OPT_CLIENT='$3'; client_pick; echo \"\$CLIENT \$CLIENT_SET\"" "${@:4}"; }
OUT=$(pick a72 "" ""); check "C1 Cortex-A72 (no atomics), nothing saved -> x86, auto" "[ \"\$OUT\" = 'x86 auto' ]"
OUT=$(pick rk3588 "" ""); check "C2 RK3588 (atomics) -> arm64, auto (2.2 path)" "[ \"\$OUT\" = 'arm64 auto' ]"
OUT=$(pick none "" ""); check "C3 no Features line (container) -> arm64" "[ \"\$OUT\" = 'arm64 auto' ]"
OUT=$(pick a72 "" "" STEAM_ARM_ALLOW_ARMV80=1); check "C4 Armv8.0 + STEAM_ARM_ALLOW_ARMV80=1 -> arm64, saved as hand choice" "[ \"\$OUT\" = 'arm64 user' ]"
OUT=$(pick rk3588 "" "" STEAM_ARM_ALLOW_ARMV80=1); check "C5 Armv8.1 + STEAM_ARM_ALLOW_ARMV80=1 -> arm64 auto (variable matters on Armv8.0 only)" "[ \"\$OUT\" = 'arm64 auto' ]"
OUT=$(pick rk3588 "" x86); check "C6 --client=x86 on Armv8.1 -> x86, user" "[ \"\$OUT\" = 'x86 user' ]"
OUT=$(pick a72 "" arm64); check "C7 --client=arm64 on Armv8.0 -> arm64, user" "[ \"\$OUT\" = 'arm64 user' ]"
OUT=$(pick a72 $'CLIENT=arm64\nCLIENT_SET=user' ""); check "C8 saved hand choice kept on --keep / menu run (arm64 on Armv8.0)" "[ \"\$OUT\" = 'arm64 user' ]"
OUT=$(pick rk3588 $'CLIENT=x86\nCLIENT_SET=user' ""); check "C9 saved hand choice kept (x86 on Armv8.1)" "[ \"\$OUT\" = 'x86 user' ]"
OUT=$(pick a72 $'CLIENT=arm64\nCLIENT_SET=user' auto); check "C10 --client=auto drops hand choice -> CPU rule (x86 on Armv8.0)" "[ \"\$OUT\" = 'x86 auto' ]"
OUT=$(pick rk3588 $'CLIENT=x86\nCLIENT_SET=auto' ""); check "C11 saved x86 by CPU rule on Armv8.1 board (moved disk) -> arm64 by CPU" "[ \"\$OUT\" = 'arm64 auto' ]"
OUT=$(pick rk3588 $'CLIENT=ppc\nCLIENT_SET=user' ""); check "C12 saved unknown value -> CPU rule" "[ \"\$OUT\" = 'arm64 auto' ]"
OUT=$(pick a72 "" auto STEAM_ARM_ALLOW_ARMV80=1); check "C13 --client=auto wins over STEAM_ARM_ALLOW_ARMV80=1" "[ \"\$OUT\" = 'x86 auto' ]"

OUT=$(crun a72 4g "" 'cpu_label; cpu_line'); check "L1 Cortex-A72 x4, Armv8.0 line" "[ \"\$OUT\" = \$'Cortex-A72 x4\nCortex-A72 x4, Armv8.0 (no LSE atomics)' ]"
OUT=$(crun rk3588 4g "" 'cpu_label; cpu_line'); check "L2 big.LITTLE counted in listed order, Armv8.1 line" "[ \"\$OUT\" = \$'Cortex-A55 x4, Cortex-A76 x4\nCortex-A55 x4, Cortex-A76 x4, Armv8.1 or newer (LSE atomics)' ]"
OUT=$(crun odd 4g "" 'cpu_label'); check "L3 unknown part named by number, case folded" "[ \"\$OUT\" = 'part 0xabc x2' ]"
OUT=$(crun none 4g "" 'cpu_line'); check "L4 no CPU part lines -> cores not listed" "[ \"\$OUT\" = 'cores not listed, Armv8.1 or newer (LSE atomics)' ]"

OUT=$(crun a72 1g "" 'mem_gate; echo GO'); check "M1 1 GB board -> stop naming 2 GB" "printf '%s\n' \"\$OUT\" | grep -q '^DIE x86 client needs 2 GB of memory or more; this system has 976 MiB' && ! printf '%s\n' \"\$OUT\" | grep -q GO"
OUT=$(crun a72 2g "" 'mem_gate; echo GO'); check "M2 2 GB board (MemTotal 1.8 GiB) -> warning, continues" "printf '%s\n' \"\$OUT\" | grep -q '^WARN x86 client and game share 1843 MiB' && printf '%s\n' \"\$OUT\" | grep -qx GO"
OUT=$(crun a72 4g "" 'mem_gate; echo GO'); check "M3 4 GB board -> no message" "[ \"\$OUT\" = GO ]"
OUT=$(crun a72 none "" 'mem_gate; echo GO'); check "M4 no meminfo -> no message" "[ \"\$OUT\" = GO ]"

OUT=$(crun a72 4g "" 'x86_warn'); XW=$OUT
check "W1 x86 warning: core names, issue 13288, x86 Proton, way back, keep-native option" "grep -q 'Cortex-A72 x4' <<<\"\$XW\" && grep -q 'steam-for-linux #13288' <<<\"\$XW\" && grep -q 'x86 Proton' <<<\"\$XW\" && grep -q 'moves to native client by itself' <<<\"\$XW\" && grep -q -- '--client=arm64' <<<\"\$XW\""
check "W2 x86 warning: no size claim, no em-dash" "! grep -q 'MB' <<<\"\$XW\" && ! grep -q \$'\\u2014' <<<\"\$XW\""
OUT=$(crun a72 4g "" 'echo "$ARMV80_NATIVE_WARN"')
check "W3 native-on-Armv8.0 warning names issue link and --client=auto" "grep -q 'issues/13288' <<<\"\$OUT\" && grep -q -- '--client=auto' <<<\"\$OUT\""

# ---------- options, --detect, --help (whole installer, no root needed) ----------
OUT=$(bash "$INST" --client=ppc --detect 2>&1); rc=$?
check "O1 --client=ppc -> stop, rc 1, valid values named" "[ $rc = 1 ] && grep -q -- '--client takes auto, arm64 or x86' <<<\"\$OUT\""
OUT=$(bash "$INST" --detect 2>/dev/null)
l_da=$(grep -n '^driver archive: ' <<<"$OUT" | cut -d: -f1); l_cpu=$(grep -n '^cpu: ' <<<"$OUT" | cut -d: -f1)
l_cl=$(grep -n '^client: ' <<<"$OUT" | cut -d: -f1); l_ps=$(grep -n '^page size: ' <<<"$OUT" | cut -d: -f1)
check "O2 --detect: cpu and client lines after driver archive, before page size" "[ -n '$l_cpu' ] && [ -n '$l_cl' ] && [ ${l_da:-0} -lt ${l_cpu:-0} ] && [ ${l_cpu:-0} -lt ${l_cl:-0} ] && [ ${l_cl:-0} -lt ${l_ps:-0} ]"
OUT=$(bash "$INST" --client x86 --detect 2>/dev/null | grep '^client: ')
check "O3 --client x86 (space form) --detect -> client: x86 (chosen by hand)" "[ \"\$OUT\" = 'client: x86 (chosen by hand)' ]"
OUT=$(bash "$INST" --help 2>/dev/null)
check "O4 --help: --client and --client-check options, x86 client paragraph" "grep -q '^  --client=auto|arm64|x86' <<<\"\$OUT\" && grep -q '^  --client-check ' <<<\"\$OUT\" && grep -q '^x86 client (CPU without Armv8.1 atomics)' <<<\"\$OUT\""
check "O5 --help: STEAM_ARM_ALLOW_ARMV80 keeps native client in place of x86 client" "grep -q '^  STEAM_ARM_ALLOW_ARMV80=1     native ARM64 client on Armv8.0 CPU in place of x86 client' <<<\"\$OUT\""

# ---------- client_dl with stand-in curl ----------
mkdir -p "$T/srv" "$T/bin"
printf 'zip-steamrt\n' > "$T/srv/steam_steamrt_ubuntu12.zip.1111"; printf 'zip-boot\n' > "$T/srv/steam_ubuntu12.zip.2222"
printf 'zip-arm\n' > "$T/srv/bins_linuxarm64_linuxarm64.zip.3333"
s1=$(sha256sum < "$T/srv/steam_steamrt_ubuntu12.zip.1111" | cut -c1-64); s2=$(sha256sum < "$T/srv/steam_ubuntu12.zip.2222" | cut -c1-64)
s3=$(sha256sum < "$T/srv/bins_linuxarm64_linuxarm64.zip.3333" | cut -c1-64)
printf '"ubuntu12"\n{\n\t"version"\t\t"1788652215"\n\t"steam_steamrt_ubuntu12"\n\t{\n\t\t"file"\t\t"steam_steamrt_ubuntu12.zip.1111"\n\t\t"sha2"\t\t"%s"\n\t}\n\t"xsteam_ubuntu12"\n\t{\n\t\t"file"\t\t"xsteam_ubuntu12.zip.0000"\n\t}\n\t"steam_ubuntu12"\n\t{\n\t\t"file"\t\t"steam_ubuntu12.zip.2222"\n\t\t"size"\t\t"9"\n\t\t"sha2"\t\t"%s"\n\t}\n}\n' "$s1" "$s2" > "$T/srv/steam_client_ubuntu12"
printf '"linuxarm64"\n{\n\t"version"\t\t"1788652216"\n\t"bins_linuxarm64_linuxarm64"\n\t{\n\t\t"file"\t\t"bins_linuxarm64_linuxarm64.zip.3333"\n\t\t"sha2"\t\t"%s"\n\t}\n}\n' "$s3" > "$T/srv/steam_client_linuxarm64"
cat > "$T/bin/curl" <<'EOF'
#!/bin/sh
o=; u=
while [ $# -gt 0 ]; do case "$1" in -o) o=$2; shift;; -*) ;; *) u=$1;; esac; shift; done
echo "$u" >> "$SRV/../curl.log"
[ -n "$CURL_FAIL" ] && case "$u" in *$CURL_FAIL*) exit 22;; esac
cp "$SRV/${u##*/}" "$o" 2>/dev/null || exit 22
EOF
chmod 755 "$T/bin/curl"
DL=$T/dl.sh
{ echo 'CURL_SHOW=(-sS); CURL_ENV=(); CLEANUP=(); NETHINT=net; CDN=https://cdn.test'
  awk '/^client_dl\(\)/{f=1} f{print} /^(client_pkg|native_probe)\(\)/{g=1} g && /^}$/{exit}' "$INST"; } > "$DL"
check "D0 client_dl, client_manifest, client_pkg extracted" "grep -q '^client_dl()' $DL && grep -q '^client_manifest()' $DL && grep -q '^client_pkg()' $DL && [ \$(grep -c 'CURL_SHOW\[@\]' $DL) = 1 ]"
dl(){ ( export SRV=$T/srv CURL_FAIL="${CURL_FAIL:-}"; PATH=$T/bin:$PATH; . "$DL"
        mktemp(){ command mktemp -d "$T/stage.XXXXXX"; }
        client_dl "$1" "$2"; rc=$?; echo "rc=$rc ver=$PKG_VER entry=$ENTRY err=$DL_ERR"
        [ "$rc" = 0 ] && echo "zip=$(cat "$STAGE/client.zip") mode=$(stat -c %a "$STAGE/client.zip") stage=$(stat -c %a "$STAGE")" ) 2>&1; }
OUT=$(dl https://cdn.test/steam_client_ubuntu12 steam_ubuntu12)
check "D1 x86 bootstrap entry picked over steam_steamrt_ubuntu12 and xsteam_ubuntu12 (name ending alike), version read, sha256 checked" "grep -q 'rc=0 ver=1788652215 entry=steam_ubuntu12.zip.2222 err=\$' <<<\"\$OUT\" && grep -q 'zip=zip-boot mode=644 stage=711' <<<\"\$OUT\""
OUT=$(dl https://cdn.test/steam_client_linuxarm64 bins_linuxarm64_linuxarm64)
check "D2 native package entry, as 2.2" "grep -q 'rc=0 ver=1788652216 entry=bins_linuxarm64_linuxarm64.zip.3333' <<<\"\$OUT\" && grep -q 'zip=zip-arm' <<<\"\$OUT\""
printf 'zip-boot-damaged\n' > "$T/srv/steam_ubuntu12.zip.2222"
OUT=$(dl https://cdn.test/steam_client_ubuntu12 steam_ubuntu12)
check "D3 checksum mismatch -> status 1 with reason, no stop" "grep -q '^rc=1 .*err=client package does not match the checksum' <<<\"\$OUT\""
OUT=$(dl https://cdn.test/steam_client_ubuntu12 bins_nothere)
check "D4 entry missing -> status 1 naming it" "grep -q \"^rc=1 .*err=Valve's client manifest has no bins_nothere package entry\" <<<\"\$OUT\""
OUT=$(CURL_FAIL=steam_client dl https://cdn.test/steam_client_ubuntu12 steam_ubuntu12)
check "D5 manifest download fails -> status 1, network hint" "grep -q '^rc=1 .*err=client manifest download failed (https://cdn.test/steam_client_ubuntu12). net' <<<\"\$OUT\""

# ---------- native package unpack unchanged from 2.2 ----------
unp(){ block '^  NEW=\$\(as_user mktemp -d "\$S/.steamrtarm64-new.XXXXXX"\)' '^    \|\| die "could not put the new client folder in place at \$D' "$1"; }
if [ -n "$OLD" ]; then
  check "U1 native client unpack (python unzip, modes, swap) byte-identical to 2.2" "[ -n \"\$(unp '$INST')\" ] && [ \"\$(unp '$INST')\" = \"\$(unp '$OLD')\" ]"
else echo "SKIP U1 unpack vs 2.2: 2.2 release not available (SARM_OLD)"; fi
check "U2 native client present-check unchanged" "grep -q '^if \[ -x \"\$D/steam\" \] && file -b \"\$D/steam\" | grep -q aarch64; then\$' '$INST'"

# ---------- --client-check ----------
CC=$T/cc.sh
{ block '^native_probe\(\)' '^}$'; grep '^probe_save()' "$INST"; block '^client_check\(\)' '^}$'; } > "$CC"
cat > "$T/probe.py" <<'EOF'
import os, sys
open(os.environ["T"] + "/probe.args", "w").write(" ".join(sys.argv[1:]))
print(os.environ.get("PROBE_OUT", "lse"))
EOF
cc(){ ( export T; sed "s#/proc/cpuinfo#$T/cpu-$1#g" "$H" > "$T/h2.sh"; . "$T/h2.sh"; . "$CC"; X86PY=${XP:-$T/probe.py}; GAMEUSER=nobody-here
        client_manifest(){ [ -z "${DLFAIL:-}" ] || { DL_ERR=$DLFAIL; return 1; }; PKG_VER=123; STAGE=$T; }; client_pkg(){ :; }
        client_check; echo "rc=$?" ) 2>&1; }
OUT=$(cc a72)
check "K1 still affected -> 'still needs Armv8.1 (client N, steam-for-linux #13288)', status 1" "[ \"\$OUT\" = \$'native client: still needs Armv8.1 (client 123, steam-for-linux #13288)\nrc=1' ]"
check "K2 Armv8.0 CPU: probe also starts client (--run)" "[ \"\$(cat $T/probe.args)\" = 'probe $T/client.zip --run' ]"
OUT=$(PROBE_OUT=ok cc rk3588)
rm -f "$T/probe.args"; OUT=$(PROBE_OUT=ok cc rk3588)
check "K3 runs -> 'runs on this CPU', status 0; Armv8.1: manifest only, no package scan" "[ \"\$OUT\" = \$'native client: runs on this CPU (client 123)\nrc=0' ] && [ ! -f $T/probe.args ]"
rm -f "$T/probe.args"; OUT=$(PROBE_OUT=lse cc rk3588)
check "K13 Armv8.1 CPU, build with Armv8.1 atomics: runs, status 0 (box bug 11)" "[ \"\$OUT\" = \$'native client: runs on this CPU (client 123)\nrc=0' ] && [ ! -f $T/probe.args ]"
OUT=$(DLFAIL='manifest down' cc rk3588)
check "K14 Armv8.1 CPU, manifest download failure: check failed, status 2" "[ \"\$OUT\" = \$'native client: check failed (manifest down)\nrc=2' ]"
# result recorded for menu "Native client last checked" (box re-test B10)
{ grep '^conf_get()' "$INST"; block '^conf_set\(\)' '^}$'; } > "$T/cs.sh"
ccs(){ printf 'GAMEUSER=g\nCLIENT_PROBE=1:lse\n' > "$T/cc.conf"; ( CONF=$T/cc.conf; die(){ echo "DIE $*"; exit 1; }; . "$T/cs.sh"; cc "$1" ) >/dev/null 2>&1; cat "$T/cc.conf"; }
OUT=$(ccs rk3588)
check "K15 Armv8.1 CPU: check writes CLIENT_PROBE=<client>:ok, other keys kept (box re-test B10)" "grep -qx 'CLIENT_PROBE=123:ok' <<<\"\$OUT\" && grep -qx 'GAMEUSER=g' <<<\"\$OUT\" && [ \$(grep -c '^CLIENT_PROBE=' <<<\"\$OUT\") = 1 ]"
OUT=$(PROBE_OUT=lse ccs a72)
check "K16 Armv8.0 CPU: probe result recorded (CLIENT_PROBE=<client>:lse)" "grep -qx 'CLIENT_PROBE=123:lse' <<<\"\$OUT\""
OUT=$(DLFAIL='manifest down' ccs rk3588)
check "K17 check failed: CLIENT_PROBE unchanged" "grep -qx 'CLIENT_PROBE=1:lse' <<<\"\$OUT\""
OUT=$(printf 'X=1\n' > "$T/ro.conf"; chmod 444 "$T/ro.conf"; ( export T; CONF=$T/ro.conf; sed "s#/proc/cpuinfo#$T/cpu-rk3588#g" "$H" > "$T/h2.sh"; . "$T/h2.sh"; . "$CC"; . "$T/cs.sh"; die(){ echo "DIE $*"; exit 1; }
  client_manifest(){ PKG_VER=123; STAGE=$T; }; client_check; echo "rc=$?" ) 2>&1; cat "$T/ro.conf")
check "K18 settings file not writable (check without root): result printed, nothing written, no stop" "[ \"\$OUT\" = \$'native client: runs on this CPU (client 123)\nrc=0\nX=1' ]"
OUT=$(PROBE_OUT='err client could not load its libraries' cc a72)
check "K4 probe error -> 'check failed (reason)', status 2" "[ \"\$OUT\" = \$'native client: check failed (err client could not load its libraries)\nrc=2' ]"
OUT=$(DLFAIL='manifest down' cc a72)
check "K5 download failure -> check failed, status 2" "[ \"\$OUT\" = \$'native client: check failed (manifest down)\nrc=2' ]"
# saved result of same build: no package download, no client start (setup runs; --client-check passes none)
np(){ ( export T; rm -f "$T/pkg.log" "$T/probe.args"; sed "s#/proc/cpuinfo#$T/cpu-a72#g" "$H" > "$T/h2.sh"; . "$T/h2.sh"; . "$CC"; X86PY=$T/probe.py; GAMEUSER=nobody-here
        client_manifest(){ PKG_VER=123; STAGE=$T; }; client_pkg(){ echo PKG >> "$T/pkg.log"; }
        native_probe "$1"; echo "rc=$? probe=$PROBE old=$PROBE_OLD pkg=$([ -f "$T/pkg.log" ] && echo yes || echo no)" ) 2>&1; }
OUT=$(np 123:lse); check "K8 same build checked before (lse): result kept, no package download, no client start" "[ \"\$OUT\" = 'rc=0 probe=lse old=1 pkg=no' ] && [ ! -f $T/probe.args ]"
OUT=$(np 122:lse); check "K9 new build in manifest: package downloaded and checked" "[ \"\$OUT\" = 'rc=0 probe=lse old=0 pkg=yes' ]"
OUT=$(np 123:err); check "K10 last check failed: checked again" "[ \"\$OUT\" = 'rc=0 probe=lse old=0 pkg=yes' ]"
OUT=$(np 123:ok); check "K11 same build ran before (ok): result kept, no download" "[ \"\$OUT\" = 'rc=0 probe=ok old=1 pkg=no' ]"
OUT=$(np ""); check "K12 nothing saved: package downloaded and checked" "[ \"\$OUT\" = 'rc=0 probe=lse old=0 pkg=yes' ]"
OUT=$(XP=$T/none.py cc a72)
check "K6 helper missing (setup not run) -> check failed naming it, status 2" "grep -q 'check failed (.*none.py missing (run setup first))' <<<\"\$OUT\" && grep -q 'rc=2' <<<\"\$OUT\""
l_cc=$(grep -n '^\[ "\$CLIENT_CHECK" = 1 \] && { client_check; exit \$?; }$' "$INST" | cut -d: -f1); l_det=$(grep -n '^\[ "\$MODE" = detect \] && { gpu_report; exit 0; }$' "$INST" | cut -d: -f1)
l_lock=$(grep -n 'exec 8>/run/steam-arm-setup.lock' "$INST" | cut -d: -f1)
check "K7 --client-check runs before lock and any package change (after --detect)" "[ -n '$l_cc' ] && [ $l_det -lt $l_cc ] && [ $l_cc -lt $l_lock ]"

# ---------- step 9 rules (static) ----------
S9=$(block '^# x86 client by CPU rule: native client checked' '^say "10/11 ')
check "S1 native check only for x86 chosen by CPU rule (not by hand)" "grep -q '^if \[ \"\$CLIENT\" = x86 \] && \[ \"\$CLIENT_SET\" = auto \]; then\$' <<<\"\$S9\""
check "S2 check result ok switches to native client in same run, else x86 stays" "grep -q '      CLIENT=arm64\$' <<<\"\$S9\" && grep -q 'still needs Armv8.1\$po (steam-for-linux #13288); x86 client stays' <<<\"\$S9\""
check "S6 step 9 hands saved CLIENT_PROBE to the check (same build: no download)" "grep -q '^  if native_probe \"\$CLIENT_PROBE\"; then\$' <<<\"\$S9\""
check "S7 automatic switch to native client puts bwrap back in RootFS and Mali tree" "grep -A2 '^      CLIENT=arm64\$' <<<\"\$S9\" | grep -q 'for t in \"\$RFS\" \"\$MALI\"; do rfs_bwrap_on \"\$t\"'"
check "S3 x86 edits put back only when switching from x86 client" "grep -q '^if \[ \"\$FOLDER_PREV\" = x86 \]; then\$' <<<\"\$S9\" && grep -q 'python3 \"\$X86PY\" restore \"\$S\" \"\$ARMHOME\"' <<<\"\$S9\""
check "S4 x86 bootstrap only when no x86 client present; Steam running stops it first" "grep -q \"file -b \\\"\\\$S/ubuntu12_32/steam\\\" | grep -qE 'Intel (80386|i386)'\" <<<\"\$S9\" && grep -q 'client_dl \"\$MANIFEST_X86\" steam_ubuntu12 || die \"\$DL_ERR\"' <<<\"\$S9\" && grep -q 'steam_up && steam_up_die' <<<\"\$S9\""
check "S8 switch x86 -> native: package records dropped, native file check at next start (box bug 10)" "grep -A3 '^if \[ \"\$FOLDER_PREV\" = x86 \]; then\$' <<<\"\$S9\" | grep -q 'python3 \"\$X86PY\" reset \"\$S\" \"\$ARMHOME\" arm64'"
check "S9 switch native -> x86 (or first x86 setup): x86 file check marker dropped (box bug 9)" "grep -q '^if \[ \"\$FOLDER_PREV\" != x86 \]; then as_user python3 \"\$X86PY\" reset \"\$S\" \"\$ARMHOME\" x86' <<<\"\$S9\""
# ---------- client type per client home (round 4: setup for another account) ----------
check "S10 step 9 decides switch by client type of this client home, not settings file alone" "grep -B3 '^# x86 client by CPU rule: native client checked' '$INST' | grep -qxF 'FOLDER_PREV=\$(folder_client)' && ! grep -q 'if \[ \"\$CLIENT_PREV\" [!=]*= x86 \]' <<<\"\$S9\""
check "S11 step 9 writes client type record into client home as game account" "grep -qF 'printf '\\''%s\\n'\\'' \"\$CLIENT\" | user_write \"\$ARMHOME/\$CLIENT_REC\"' <<<\"\$S9\""
# ---------- step 9 run (executed, stubbed tools; box bugs 9 and 10, automatic switch back) ----------
S9R=$T/s9run.sh
awk '/^CLIENT_PREV=\$\(conf_get CLIENT\)$/{f=1} f && /^as_user mkdir -p "\$ARMHOME\/\$\{CLIENT_REC%\/\*\}"/{exit} f' "$INST" > "$S9R"
check "SR0 step 9 block extracted (probe, x86 and native branches)" "grep -q '^FOLDER_PREV=\$(folder_client)\$' $S9R && grep -q 'restore \"\$S\" \"\$ARMHOME\"' $S9R && [ \"\$(tail -n 1 $S9R)\" = fi ] && bash -n $S9R"
# s9 FOLDER CLIENT CLIENT_SET [probe result ok|lse|fail] [saved CLIENT_PROBE]: calls to $T/s9.log, final state on stdout
s9(){
  local h=$T/s9h; rm -rf "$h" "$T/s9.log"; mkdir -p "$h/S/ubuntu12_32" "$h/S/steamrtarm64"
  : > "$h/S/steam.sh"; : > "$h/S/ubuntu12_32/steam-runtime.tar.xz"; : > "$h/S/ubuntu12_32/steam-runtime.tar.xz.checksum"
  printf '#!/bin/sh\n' > "$h/S/ubuntu12_32/steam"; printf '#!/bin/sh\n' > "$h/S/steamrtarm64/steam"; chmod 755 "$h/S/ubuntu12_32/steam" "$h/S/steamrtarm64/steam"
  ( L=$T/s9.log FOLDER=$1 CLIENT=$2 CLIENT_SET=$3 NP=${4:-ok} SAVED=${5:-}
    S=$h/S D=$h/S/steamrtarm64 ARMHOME=$h X86PY=/x/x86.py RFS=/rfs MALI=/mali MANIFEST=m MANIFEST_X86=mx
    conf_get(){ case $1 in CLIENT) echo "$2";; CLIENT_PROBE) echo "$SAVED";; esac; }
    folder_client(){ echo "$FOLDER"; }
    say(){ :; }; warn(){ echo "WARN $*" >> "$L"; }; die(){ echo "DIE $*" >> "$L"; exit 1; }
    native_probe(){ echo "PROBE $1" >> "$L"; PKG_VER=200; PROBE_OLD=0; [ "$NP" = fail ] && { DL_ERR=net; return 1; }; PROBE=$NP; }
    as_user(){ echo "AS_USER $*" >> "$L"; cat >/dev/null; return 0; }
    rfs_bwrap_on(){ echo "BWRAP_ON $1" >> "$L"; }
    client_dl(){ echo "DL $*" >> "$L"; return 1; }
    steam_up(){ return 1; }
    file(){ case $2 in *ubuntu12_32/steam) echo "ELF 32-bit LSB executable, Intel i386";; *) echo "ELF 64-bit LSB executable, ARM aarch64";; esac; }
    . "$S9R" </dev/null >/dev/null
    echo "CLIENT=$CLIENT CLIENT_PROBE=${CLIENT_PROBE:-}" ) 2>&1; }
has(){ grep -q -- "$1" "$T/s9.log" 2>/dev/null; }
OUT=$(s9 x86 arm64 user)
check "SR1 x86 home -> native by hand: x86 edits restored, reset arm64, no reset x86, no check" \
  "has 'python3 /x/x86.py restore $T/s9h/S $T/s9h\$' && has 'python3 /x/x86.py reset $T/s9h/S $T/s9h arm64' && ! has ' x86\$' && ! has '^PROBE' && ! has '^DL\|^DIE' && [ \"\$OUT\" = 'CLIENT=arm64 CLIENT_PROBE=' ]"
OUT=$(s9 arm64 x86 user)
check "SR2 native home -> x86 by hand: reset x86 only, no restore, no check" \
  "has 'python3 /x/x86.py reset $T/s9h/S $T/s9h x86' && ! has ' restore ' && ! has ' arm64\$' && ! has '^PROBE' && ! has '^DL\|^DIE' && [ \"\$OUT\" = 'CLIENT=x86 CLIENT_PROBE=' ]"
OUT=$(s9 x86 x86 auto lse 199:lse)
check "SR3 x86 by CPU rule, native still lse: check gets saved result, x86 stays, no reset, result recorded" \
  "has '^PROBE 199:lse\$' && ! has 'x86.py reset' && ! has ' restore ' && ! has BWRAP_ON && [ \"\$OUT\" = 'CLIENT=x86 CLIENT_PROBE=200:lse' ]"
OUT=$(s9 x86 x86 auto ok)
check "SR4 x86 by CPU rule, native check ok: switch to native in same run, bwrap back in RootFS and Mali tree, restore + reset arm64" \
  "has '^BWRAP_ON /rfs\$' && has '^BWRAP_ON /mali\$' && has 'x86.py restore ' && has 'x86.py reset $T/s9h/S $T/s9h arm64' && ! has 'reset .* x86\$' && [ \"\$OUT\" = 'CLIENT=arm64 CLIENT_PROBE=200:ok' ]"
OUT=$(s9 x86 x86 auto fail)
check "SR5 native check failed: warning, x86 stays, result err" "has '^WARN native client check failed (net); x86 client stays' && ! has 'x86.py reset' && [ \"\$OUT\" = 'CLIENT=x86 CLIENT_PROBE=200:err' ]"
OUT=$(s9 arm64 arm64 auto)
check "SR6 native home stays native: no reset, no restore, no check" "! has 'x86.py' && ! has '^PROBE' && [ \"\$OUT\" = 'CLIENT=arm64 CLIENT_PROBE=' ]"
OUT=$(s9 x86 x86 user)
check "SR7 x86 home stays x86 by hand: no reset, no check" "! has 'x86.py' && ! has '^PROBE' && [ \"\$OUT\" = 'CLIENT=x86 CLIENT_PROBE=' ]"
FC=$T/fc.sh
{ grep -m1 '^CLIENT_REC=' "$INST"; block '^folder_client\(\)' '^}$'; } > "$FC"
# fc CONF ARMHOME_DIR GAMEUSER CLIENT_PREV [setup...]: folder_client on fake home
fc(){
  local h=$T/fch; rm -rf "$h"; mkdir -p "$h/a/.local/share/Steam/ubuntu12_32" "$h/a/.local/share/Steam/ubuntu12_64" "$h/a/.config/steam-arm"
  printf '%s\n' "$1" > "$T/fc.conf"
  ( cd "$h/a"; eval "${5:-:}" )
  ( conf_get(){ sed -n "s/^$1=//p" "$T/fc.conf" | tail -1; }
    ARMHOME=$h/a; S=$h/a/.local/share/Steam; ARMHOME_DIR=$2; GAMEUSER=$3; CLIENT_PREV=$4
    . "$FC"; folder_client ) 2>&1
}
SAME=$'GAMEUSER=u1\nARMHOME_DIR=.local/share/steam-arm'
OUT=$(fc "$SAME" .local/share/steam-arm u1 x86); check "FC1 no record, settings file names this home: its CLIENT (x86)" "[ \"\$OUT\" = x86 ]"
OUT=$(fc "$SAME" .local/share/steam-arm u1 ""); check "FC2 no record, same home, no CLIENT (2.2 install): arm64" "[ \"\$OUT\" = arm64 ]"
OUT=$(fc "$SAME" .local/share/steam-arm u2 x86); check "FC3 setup moved to account u2 whose home x86 client never used: arm64 (no reset of native folder)" "[ \"\$OUT\" = arm64 ]"
OUT=$(fc "$SAME" .local/share/steam-arm u2 arm64 'touch .local/share/Steam/ubuntu12_32/steam-launch-wrapper.real'); check "FC4 other account, no record, launch wrapper copy of x86 client: x86" "[ \"\$OUT\" = x86 ]"
OUT=$(fc "$SAME" .local/share/steam-arm u2 arm64 'touch .local/share/Steam/ubuntu12_64/steamwebhelper.sh.steam-arm-sha'); check "FC5 other account, no record, webhelper edit record: x86" "[ \"\$OUT\" = x86 ]"
OUT=$(fc "$SAME" .local/share/steam-arm u2 arm64 'touch .config/steam-arm/x86-verified'); check "FC6 other account, no record, x86-verified marker: x86" "[ \"\$OUT\" = x86 ]"
OUT=$(fc "$SAME" .local/share/steam-arm u2 x86 'echo arm64 > .config/steam-arm/client-type'); check "FC7 record arm64 wins over CLIENT=x86 of previous account (box round 3 note)" "[ \"\$OUT\" = arm64 ]"
OUT=$(fc "$SAME" .local/share/steam-arm u1 arm64 'echo x86 > .config/steam-arm/client-type'); check "FC8 record x86 wins over settings file CLIENT=arm64" "[ \"\$OUT\" = x86 ]"
OUT=$(fc "$SAME" other/dir u1 x86); check "FC9 same account, other client folder (ARMHOME_DIR changed), no record: arm64" "[ \"\$OUT\" = arm64 ]"
OUT=$(fc "$SAME" .local/share/steam-arm u1 x86 'echo junk > .config/steam-arm/client-type'); check "FC10 unknown record value ignored: settings file decides" "[ \"\$OUT\" = x86 ]"
check "S5 settings file gets CLIENT, CLIENT_SET, CLIENT_PROBE" "grep -q '^conf_set CLIENT \"\$CLIENT\"\$' '$INST' && grep -q '^conf_set CLIENT_SET \"\$CLIENT_SET\"\$' '$INST' && grep -q 'conf_set CLIENT_PROBE \"\$CLIENT_PROBE\"' '$INST'"

# ---------- reason text for x86 client: hand choice or CPU rule (box bug 13) ----------
grep '^x86_why()' "$INST" > "$T/xw.sh"
OUT=$( (CLIENT_SET=user; . "$T/xw.sh"; x86_why) 2>&1)
check "W6 x86 chosen by hand: reason 'chosen by hand'" "[ \"\$OUT\" = 'chosen by hand' ]"
OUT=$( (CLIENT_SET=auto; . "$T/xw.sh"; x86_why) 2>&1)
check "W7 x86 by CPU rule: reason names missing Armv8.1 atomics" "[ \"\$OUT\" = 'CPU without Armv8.1 atomics' ]"
check "W8 banner and final summary take reason from x86_why (no fixed atomics text)" "[ \$(grep -c 'through FEX (\$(x86_why))\|through emulation (\$(x86_why);' '$INST') = 2 ]"

# ---------- RootFS bwrap aside and back ----------
RB=$T/rb.sh
{ grep -m1 '^GUARD_MARK=' "$INST"; block '^rfs_unguard\(\)' '^}$'; block '^rfs_bwrap_on\(\)' '^}$'; block '^rfs_bwrap_off\(\)' '^}$'; } > "$RB"
elfh(){ python3 -c "import struct,sys; sys.stdout.buffer.write(b'\x7fELF\x02\x01\x01' + b'\0'*9 + struct.pack('<HHI', 2, $2, 1) + b'\0'*100)" > "$1"; chmod 755 "$1"; }
mkdir -p "$T/rfs/usr/bin"; elfh "$T/rfs/usr/bin/bwrap" 62
OUT=$( (RFS=$T/rfs; . "$RB"; rfs_bwrap_off "$T/rfs"; echo "rc=$?") 2>&1)
check "F1 x86 bwrap in RootFS set aside" "[ ! -e $T/rfs/usr/bin/bwrap ] && [ -f $T/rfs/usr/bin/bwrap.steam-arm-real ] && grep -q 'rc=0' <<<\"\$OUT\""
OUT=$( (. "$RB"; rfs_unguard "$T/rfs"; echo "rc=$?") 2>&1)
check "F2 rfs_unguard puts it back (removal path), status 0" "[ -f $T/rfs/usr/bin/bwrap ] && [ ! -e $T/rfs/usr/bin/bwrap.steam-arm-real ] && grep -q 'rc=0' <<<\"\$OUT\""
rm -f "$T/rfs/usr/bin/bwrap"; elfh "$T/rfs/usr/bin/bwrap" 183
( . "$RB"; rfs_bwrap_off "$T/rfs" )
check "F3 aarch64 bwrap (native, placed by hand) untouched" "[ -f $T/rfs/usr/bin/bwrap ] && [ ! -e $T/rfs/usr/bin/bwrap.steam-arm-real ]"
elfh "$T/rfs/usr/bin/bwrap.steam-arm-real" 62
OUT=$( (. "$RB"; rfs_unguard "$T/rfs"; echo "rc=$?") 2>&1)
check "F4 bwrap present and set-aside copy too: both left, status 1" "[ -f $T/rfs/usr/bin/bwrap.steam-arm-real ] && grep -q 'rc=1' <<<\"\$OUT\""
rm -rf "$T/rfs"; mkdir -p "$T/rfs/usr/bin"
OUT=$( (. "$RB"; rfs_bwrap_off "$T/rfs"; echo "rc=$?") 2>&1)
check "F5 RootFS without bwrap (FEX image today): no-op, status 0" "[ \"\$OUT\" = rc=0 ] && [ -z \"\$(ls $T/rfs/usr/bin)\" ]"
check "F6 step 3 sets RootFS bwrap aside for x86 client only, after package tool guard" "grep -A1 '^rfs_guard \"\$RFS\" ||' '$INST' | grep -q '^\[ \"\$CLIENT\" = x86 \] && { rfs_bwrap_off \"\$RFS\"'"
B3=$T/b3.sh; block '^\[ "\$CLIENT" = x86 \] && \{ rfs_bwrap_off' '^fi$' > "$B3"
b3(){ ( RFS=$T/rfs MALI=$T/mali CLIENT=$1; warn(){ echo "WARN $*"; }; . "$RB"; . "$B3" ) 2>&1; }
rm -rf "$T/rfs" "$T/mali"; mkdir -p "$T/rfs/usr/bin" "$T/mali/usr/bin"; elfh "$T/rfs/usr/bin/bwrap.steam-arm-real" 62; elfh "$T/mali/usr/bin/bwrap.steam-arm-real" 62
OUT=$(b3 arm64)
check "F7 native client run: bwrap set aside by x86 period put back in RootFS and Mali tree" "[ -f $T/rfs/usr/bin/bwrap ] && [ ! -e $T/rfs/usr/bin/bwrap.steam-arm-real ] && [ -f $T/mali/usr/bin/bwrap ] && [ ! -e $T/mali/usr/bin/bwrap.steam-arm-real ] && grep -q 'x86 bwrap in $T/rfs put back (native client)' <<<\"\$OUT\""
OUT=$(b3 x86)
check "F8 x86 client run after that: RootFS bwrap set aside again" "[ ! -e $T/rfs/usr/bin/bwrap ] && [ -f $T/rfs/usr/bin/bwrap.steam-arm-real ]"
OUT=$(b3 arm64; b3 arm64)
check "F9 native client run without set-aside copy: nothing moved, no message" "[ -f $T/rfs/usr/bin/bwrap ] && [ \$(grep -c 'put back' <<<\"\$OUT\") = 1 ]"

# ---------- step 1: host bubblewrap must be native for x86 client ----------
B1=$T/b1.sh
block '^if \[ "\$CLIENT" = x86 \] && ! file -b "\$\(command -v bwrap' '^fi$' > "$B1"
mkdir -p "$T/bw-x86" "$T/bw-arm"; elfh "$T/bw-x86/bwrap" 62; elfh "$T/bw-arm/bwrap" 183
b1(){ ( CLIENT=$1; PATH=$2:/usr/bin:/bin; die(){ echo "DIE $*"; exit 1; }; . "$B1"; echo GO ) 2>&1; }
OUT=$(b1 x86 "$T/bw-arm"); check "N1 x86 client + native bwrap -> continues" "[ \"\$OUT\" = GO ]"
OUT=$(b1 x86 "$T/bw-x86"); check "N2 x86 client + x86 bwrap -> stop naming bubblewrap" "grep -q '^DIE native bubblewrap needed for x86 client' <<<\"\$OUT\""
OUT=$(b1 arm64 "$T/bw-x86"); check "N3 native client: no bwrap check" "[ \"\$OUT\" = GO ]"

# ---------- pv-bwrap and package-tool stubs written by setup ----------
PV=$T/pv.sh
block '^PVB_BINDS=""$' '^done$' | sed "s#/usr/local/lib/steam-arm-pv-bwrap#$T/pv-bwrap#g" > "$PV"
OUT=$( (NOPKG=$T/nopkg; fex_thunk_paths(){ echo "/usr/lib/fex-emu/HostThunks/ /usr/share/fex-emu/GuestThunks/ /usr/share/fex-emu/ThunksDB.json"; }; . "$PV") 2>&1)
check "V1 pv-bwrap written, parses (sh -n), mode 755" "[ -f $T/pv-bwrap ] && sh -n $T/pv-bwrap && [ \$(stat -c %a $T/pv-bwrap) = 755 ]"
sed "s#/usr/bin/bwrap#$T/fake-bwrap#" "$T/pv-bwrap" > "$T/pv-run"; printf '#!/bin/sh\nfor a; do echo "$a"; done\n' > "$T/fake-bwrap"; chmod 755 "$T/fake-bwrap"
OUT=$(sh "$T/pv-run" --args 27 -- /bin/true)
check "V2 pv-bwrap: host libraries, thunk folders, FEXServer socket, FEX_ROOTFS /, then caller's arguments unchanged" \
  "[ \"\$(printf '%s\n' \"\$OUT\" | tr '\n' ' ')\" = \"--ro-bind /usr/lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu --ro-bind-try /usr/lib/fex-emu/HostThunks /usr/lib/fex-emu/HostThunks --ro-bind-try /usr/share/fex-emu/GuestThunks /usr/share/fex-emu/GuestThunks --ro-bind-try /usr/share/fex-emu /usr/share/fex-emu --ro-bind-try /run/user/\$(id -u)/0.FEXServer.Socket /run/user/\$(id -u)/0.FEXServer.Socket --setenv FEX_ROOTFS / --args 27 -- /bin/true \" ]"
mkdir -p "$T/pvh/.fex-emu/hostlib"; : > "$T/pvh/.fex-emu/hostlib/libX11.so.6"; : > "$T/hostX11"
sed "s#/usr/lib/aarch64-linux-gnu/libX11.so.6#$T/hostX11#" "$T/pv-run" > "$T/pv-run2"
OUT=$(HOME=$T/pvh sh "$T/pv-run2" --args 27 -- /bin/true)
check "V5 private libX11 copy in client home: bound over host libX11 after host library folder, before caller's arguments (box bug 9)" \
  "[ \"\$(printf '%s\n' \"\$OUT\" | tr '\n' ' ')\" = \"--ro-bind /usr/lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu --ro-bind-try /usr/lib/fex-emu/HostThunks /usr/lib/fex-emu/HostThunks --ro-bind-try /usr/share/fex-emu/GuestThunks /usr/share/fex-emu/GuestThunks --ro-bind-try /usr/share/fex-emu /usr/share/fex-emu --ro-bind-try /run/user/\$(id -u)/0.FEXServer.Socket /run/user/\$(id -u)/0.FEXServer.Socket --setenv FEX_ROOTFS / --ro-bind $T/pvh/.fex-emu/hostlib/libX11.so.6 $T/hostX11 --args 27 -- /bin/true \" ]"
OUT=$(HOME=$T/none sh "$T/pv-run2" --args 27 -- /bin/true)
check "V6 no private copy: no extra bind" "! grep -q hostlib <<<\"\$OUT\""
check "V3 pv-bwrap closes no file descriptor (pressure-vessel passes --args FD)" "! grep -qE '[0-9]?<&-|[0-9]>&-|exec [0-9]' $T/pv-bwrap"
ok=1; for t in apt apt-get dpkg pkexec sudo steamdeps; do
  o=$("$T/nopkg/$t" install x 2>&1); [ $? = 1 ] && grep -q "^$t: package changes from the x86 client are off" <<<"$o" || ok=0; done
check "V4 package tools for x86 client (apt, apt-get, dpkg, pkexec, sudo, steamdeps): refusal, status 1" "[ $ok = 1 ]"

# ---------- earlier client folder of an x86 install is no foreign folder ----------
EC=$T/ec.sh
block '^ARMHOME_MARK=1; ARMHOME_FOREIGN=0$' '^fi$' > "$EC"
ec(){ ( GAMEUSER=gu; ARMHOME_DIR=games/steam; getent(){ echo "gu:x:1000:1000::$T/home:/bin/sh"; }
        conf_get(){ case "$1" in ARMHOME_DIR) echo games/steam;; GAMEUSER) echo gu;; ARMHOME_FOREIGN) echo 0;; esac; }
        die(){ echo "DIE $*"; exit 1; }; . "$EC"; echo "mark=$ARMHOME_MARK foreign=$ARMHOME_FOREIGN" ) 2>&1; }
mkdir -p "$T/home/games/steam/.local/share/Steam/ubuntu12_32"; : > "$T/home/games/steam/.local/share/Steam/steam.sh"; : > "$T/home/games/steam/.local/share/Steam/ubuntu12_32/steam"
OUT=$(ec); check "E1 folder of x86 client install (steam.sh + ubuntu12_32/steam, own folder name) -> not foreign" "[ \"\$OUT\" = 'mark=1 foreign=0' ]"
rm "$T/home/games/steam/.local/share/Steam/steam.sh"
OUT=$(ec); check "E2 ubuntu12_32/steam alone (other files) -> foreign, as 2.2" "[ \"\$OUT\" = 'mark=0 foreign=1' ]"

# ---------- x86 runtime package at setup, launcher check (box re-check B14) ----------
# manifest fixture as Valve's: runtime_scout_ubuntu12 between steam_ubuntu12 and runtime_steamrt_ubuntu12
mkdir -p "$T/srv2"
python3 - "$T/srv2" <<'EOF'
import sys, zipfile
d = sys.argv[1]
def mk(name, members):
    with zipfile.ZipFile(d + "/" + name, "w") as z:
        for n, b in members:
            z.writestr(n, b)
mk("runtime_scout_ubuntu12.zip.4444", [("ubuntu12_32/steam-runtime.tar.xz", "tar"),
   ("ubuntu12_32/steam-runtime.tar.xz.checksum", "abc  steam-runtime.tar.xz\n"), ("ubuntu12_32/steam-runtime-scout.version.txt", "v\n")])
mk("runtime_steamrt_ubuntu12.zip.5555", [("ubuntu12_64/steam-runtime-steamrt.tar.xz", "rt")])
mk("bad_scout.zip", [("ubuntu12_32/steam-runtime.tar.xz", "tar")])
EOF
r4=$(sha256sum < "$T/srv2/runtime_scout_ubuntu12.zip.4444" | cut -c1-64); r5=$(sha256sum < "$T/srv2/runtime_steamrt_ubuntu12.zip.5555" | cut -c1-64)
mkman(){ printf '"ubuntu12"\n{\n\t"version"\t\t"1788652215"\n\t"steam_ubuntu12"\n\t{\n\t\t"file"\t\t"steam_ubuntu12.zip.2222"\n\t\t"sha2"\t\t"%s"\n\t\t"IsBootstrapperPackage"\t\t"1"\n\t}\n\t"runtime_scout_ubuntu12"\n\t{\n\t\t"file"\t\t"runtime_scout_ubuntu12.zip.4444"\n\t\t"size"\t\t"63540407"\n\t\t"sha2"\t\t"%s"\n\t}\n\t"runtime_steamrt_ubuntu12"\n\t{\n\t\t"file"\t\t"runtime_steamrt_ubuntu12.zip.5555"\n\t\t"sha2"\t\t"%s"\n\t\t"zipvz"\t\t"runtime_steamrt_ubuntu12.zip.vz.6666_1"\n\t}\n}\n' "$s2" "$1" "$r5" > "$T/srv2/steam_client_ubuntu12"; }
mkman "$r4"
awk "/^cat > \/usr\/local\/lib\/steam-arm-x86client.py <<'X86PY'\$/{f=1;next} /^X86PY\$/{f=0} f" "$INST" > "$T/x86client.py"
RTB=$(block '^# steam.sh unpacks ubuntu12_32/steam-runtime.tar.xz at start; bootstrap package lacks it.$' '^fi$')
printf '%s\n' "$RTB" > "$T/rt.sh"
rt(){ ( export SRV=$T/srv2 CURL_FAIL=; PATH=$T/bin:$PATH; . "$DL"; mktemp(){ command mktemp -d "$T/stage.XXXXXX"; }
        X86PY=$T/x86client.py MANIFEST_X86=https://cdn.test/steam_client_ubuntu12 S=$1
        as_user(){ "$@"; }; steam_up(){ false; }; die(){ echo "DIE $*"; exit 1; }; . "$T/rt.sh"; echo "rc=0" ) 2>&1; }
: > "$T/srv2/../curl.log"; mkdir -p "$T/S-rt/ubuntu12_32"; : > "$T/S-rt/steam.sh"
OUT=$(rt "$T/S-rt"); CL=$(cat "$T/curl.log")
check "RT1 fresh x86 folder: runtime_scout_ubuntu12 fetched from x86 manifest (not runtime_steamrt), sha256 checked, unpacked" \
  "[ -n \"\$RTB\" ] && grep -q 'package runtime_scout_ubuntu12.zip.4444' <<<\"\$OUT\" && grep -q 'x86 client runtime: 3 files' <<<\"\$OUT\" && grep -qx rc=0 <<<\"\$OUT\" && [ -f $T/S-rt/ubuntu12_32/steam-runtime.tar.xz ] && [ -f $T/S-rt/ubuntu12_32/steam-runtime.tar.xz.checksum ] && grep -qx https://cdn.test/runtime_scout_ubuntu12.zip.4444 <<<\"\$CL\" && ! grep -q steamrt <<<\"\$CL\""
: > "$T/curl.log"; OUT=$(rt "$T/S-rt")
check "RT2 runtime in place: kept, nothing downloaded" "grep -qx '  x86 client runtime present' <<<\"\$OUT\" && [ ! -s $T/curl.log ]"
mkdir -p "$T/S-rt3/ubuntu12_32"; mkman 0000000000000000000000000000000000000000000000000000000000000000
OUT=$(rt "$T/S-rt3")
check "RT3 runtime package damaged: setup stops with checksum reason, nothing unpacked" "grep -q '^DIE client package does not match the checksum' <<<\"\$OUT\" && [ ! -e $T/S-rt3/ubuntu12_32/steam-runtime.tar.xz ]"
cp "$T/srv2/bad_scout.zip" "$T/srv2/runtime_scout_ubuntu12.zip.4444"; mkman "$(sha256sum < "$T/srv2/bad_scout.zip" | cut -c1-64)"
OUT=$(rt "$T/S-rt3")
check "RT4 runtime package without checksum file: setup stops (layout changed)" "grep -q '^DIE x86 client runtime could not be unpacked' <<<\"\$OUT\" && grep -q 'lacks ubuntu12_32/steam-runtime.tar.xz or its checksum' <<<\"\$OUT\""
l_bs=$(grep -n 'python3 "$X86PY" bootstrap "$STAGE/client.zip" "$S"' "$INST" | cut -d: -f1); l_rt=$(grep -n '^# steam.sh unpacks ubuntu12_32/steam-runtime.tar.xz at start' "$INST" | cut -d: -f1)
l_else=$(grep -n '^say "9/11  client package (linuxarm64)' "$INST" | cut -d: -f1)
check "RT5 runtime step after bootstrap, inside x86 branch of step 9 (also for x86 client already present)" "[ -n '$l_rt' ] && [ ${l_bs:-0} -lt ${l_rt:-0} ] && [ ${l_rt:-0} -lt ${l_else:-0} ]"
# launcher: runtime check before first start
LRT=$T/lrt.sh; grep -E '^  (RTM=|\[ -f "\$S/ubuntu12_32/steam-runtime.tar.xz.checksum" \])' "$INST" > "$LRT"
lr(){ ( S=$1 SETUP=/usr/local/sbin/steam-arm-setup; stop(){ echo "STOP $*"; exit 1; }; . "$LRT"; echo started ) 2>&1; }
mkdir -p "$T/L1/ubuntu12_32"; OUT=$(lr "$T/L1")
check "RT6 launcher, runtime missing: stop before client start, names runtime file and Update / Repair (not 'finish download')" "[ \$(wc -l < $LRT) = 2 ] && grep -q '^STOP x86 Steam client runtime missing ($T/L1/ubuntu12_32/steam-runtime.tar.xz). Run setup again to fetch it: sudo steam-arm-config (Maintenance > Update / Repair)' <<<\"\$OUT\" && ! grep -q 'finish download' <<<\"\$OUT\" && ! grep -q started <<<\"\$OUT\""
: > "$T/L1/ubuntu12_32/steam-runtime.tar.xz.checksum"; OUT=$(lr "$T/L1")
check "RT7 launcher, runtime tar checksum present: client starts" "[ \"\$OUT\" = started ]"
mkdir -p "$T/L2/ubuntu12_32/steam-runtime"; printf '#!/bin/sh\n' > "$T/L2/ubuntu12_32/steam-runtime/setup.sh"; chmod 755 "$T/L2/ubuntu12_32/steam-runtime/setup.sh"
OUT=$(lr "$T/L2")
check "RT8 launcher, runtime unpacked (tar gone): client starts" "[ \"\$OUT\" = started ]"
FS=$(grep -A1 '^      FSM="x86 Steam client did not finish its first start: client files incomplete' "$INST" | sed -n 2p)
check "RT9 x86 first start failed without unpacked runtime: message names runtime and setup, not download" "grep -q '^      \[ -x \"\$S/ubuntu12_32/steam-runtime/setup.sh\" \] || FSM=\"x86 Steam client did not finish its first start: runtime not unpacked' <<<\"\$FS\" && grep -q 'Update / Repair' <<<\"\$FS\""

SF=$(grep -A1 '^  SUM_FIRST=' "$INST")
check "RT10 setup summary: x86 first sign-in in desktop window, native text unchanged (box re-check B15)" "grep -q 'first sign-in in desktop window' <<<\"\$SF\" && grep -q 'sign in from Big Picture' <<<\"\$SF\" && grep -q '^  First start:   \$SUM_FIRST\$' '$INST'"
# box re-check B17: file 5.4x names 32-bit x86 programs "Intel i386" (older: "Intel 80386")
PC=$(grep -m1 'file -b "$S/ubuntu12_32/steam" | grep' "$INST" | sed 's/^if //; s/; then$//')
mkdir -p "$T/fb" "$T/P/ubuntu12_32"; : > "$T/P/steam.sh"; printf '#!/bin/sh\n' > "$T/P/ubuntu12_32/steam"; chmod 755 "$T/P/ubuntu12_32/steam"
pc(){ printf '#!/bin/sh\necho "%s"\n' "$1" > "$T/fb/file"; chmod 755 "$T/fb/file"; ( S=$T/P PATH=$T/fb:$PATH; eval "$PC" && echo kept || echo bootstrap ); }
OUT="$(pc 'ELF 32-bit LSB pie executable, Intel i386, version 1 (SYSV)') $(pc 'ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV)') $(pc 'ELF 64-bit LSB pie executable, ARM aarch64')"
check "RT11 x86 client present: kept for file 5.4x (Intel i386) and older (Intel 80386), aarch64 client replaced" "[ -n \"\$PC\" ] && [ \"\$OUT\" = 'kept kept bootstrap' ]"
BO=$T/bo.sh; { echo 'RFS=/rfs'; block '^rfs_bwrap_off\(\)' '^}$'; } > "$BO"
bo(){ printf '#!/bin/sh\necho "%s"\n' "$1" > "$T/fb/file"; chmod 755 "$T/fb/file"; rm -rf "$T/BR"; mkdir -p "$T/BR/usr/bin"; : > "$T/BR/usr/bin/bwrap"
      ( PATH=$T/fb:$PATH; . "$BO"; rfs_bwrap_off "$T/BR" >/dev/null ); [ -e "$T/BR/usr/bin/bwrap.steam-arm-real" ] && echo aside || echo kept; }
OUT="$(bo 'ELF 32-bit LSB pie executable, Intel i386') $(bo 'ELF 64-bit LSB pie executable, x86-64') $(bo 'ELF 64-bit LSB pie executable, ARM aarch64')"
check "RT12 RootFS bwrap set aside for i386 (file 5.4x) and x86-64 builds, aarch64 kept" "[ \"\$OUT\" = 'aside aside kept' ]"
echo "client x86 2.3: $pass pass, $fail fail"
[ "$fail" = 0 ]
