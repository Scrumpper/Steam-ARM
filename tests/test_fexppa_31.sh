#!/bin/bash
# 3.1 FEX PPA series gap: setup step 1 warns when apt's candidate of the chosen fex-emu package (YYMM) is below
# FEX_PPA_CURRENT (Launchpad publishes per Ubuntu series; Ubuntu 25.10 lags). Step 1 block extracted from the installer
# under test (SARM_INST picks another); apt-cache, apt-get, FEX stubbed; no network, no root. Internal.
. "$(dirname "$0")/paths.sh"; INST=$SARM_INST
T=$(mktemp -d /tmp/sarm31-fexppa.XXXXXX); trap 'rm -rf "$T"' EXIT
S=$T/stub; mkdir -p "$S"
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
block(){ A=$1 B=$2 awk '!f && $0 ~ ENVIRON["A"] {f=1; print; next} f {print} f && $0 ~ ENVIRON["B"] {exit}' "$INST"; }

# ---------- extraction ----------
{ echo 'set -u; say(){ printf "==> %s\n" "$*"; }; warn(){ printf "[warn] %s\n" "$*"; }; die(){ printf "[fail] %s\n" "$*"; exit 1; }'
  echo 'wait_apt(){ :; }; NETHINT="(nethint)"; cpu_features(){ echo "fp asimd atomics crc32 asimdrdm dcpop"; }'
  grep '^FEX_PPA_CURRENT=' "$INST"
  block '^# Packages among \$@ that apt offers' '^}$'
  block '^fex_arch\(\)\{' '^}$'
  block '^fex_pkg\(\)\{' '^}$'
  echo 'step1(){'
  block '^if \[ "\$FEX_OTHER" = 1 \]; then$' '^command -v FEX >/dev/null \|\| die'
  echo '}'
} > "$T/funcs.sh"
check "F0 extract: constant, pkg_missing, fex_pkg, step 1 block with candidate check" \
  "bash -n $T/funcs.sh && grep -q '^FEX_PPA_CURRENT=2610' $T/funcs.sh && grep -q '^pkg_missing()' $T/funcs.sh && grep -q '^fex_pkg()' $T/funcs.sh && grep -q '^  FEX_CAND=' $T/funcs.sh && grep -q 'apt-get install -y \$FEXPKGS' $T/funcs.sh"
check "F0b constant defined once, before FEXSRC" "[ \$(grep -c '^FEX_PPA_CURRENT=' '$INST') = 1 ] && [ \$(grep -n -m1 '^FEX_PPA_CURRENT=' '$INST' | cut -d: -f1) -lt \$(grep -n -m1 '^FEXSRC=' '$INST' | cut -d: -f1) ]"

# stubs: apt-cache policy answers Candidate $CAND for fex-emu-armv8.2 (the CPU's build), 2610-1 for binfmt packages,
# nothing for others; calls logged. apt-get logs. FEX stand-in on PATH.
cat > "$S/apt-cache" <<'STUB'
#!/bin/bash
echo "apt-cache $*" >> "$LOGF"
[ "$1" = policy ] || exit 0; shift
for p; do case $p in
  fex-emu-armv8.2) printf '%s:\n  Installed: (none)\n  Candidate: %s\n  Version table:\n' "$p" "$CAND";;
  fex-emu-binfmt32|fex-emu-binfmt64) printf '%s:\n  Installed: (none)\n  Candidate: 2610-1\n  Version table:\n' "$p";;
esac; done
STUB
printf '#!/bin/bash\necho "apt-get $*" >> "$LOGF"; exit 0\n' > "$S/apt-get"
printf '#!/bin/sh\necho "FEX $*"\n' > "$S/FEX"
chmod 755 "$S"/*
export LOGF=$T/log CAND
run(){ : > "$LOGF"; OUT=$(PATH="$S:/usr/bin:/bin" bash -c ". $T/funcs.sh; FEX_OTHER=${2:-0}; HOSTPKGS='bubblewrap curl'; step1" 2>&1); RC=$?; }
W1="FEX package source offers FEX 2607-1 for this distribution release; FEX 2610 builds exist there for other Ubuntu releases."
W2="Host FEX serves Remote Play and thunk libraries; titles use Valve's FEX tool from Steam and are unaffected."

CAND=2607-1; run
check "F1 candidate 2607-1 (Ubuntu 25.10 pocket): one warning line, both sentences, after the build line" \
  "[ $RC = 0 ] && [ \$(grep -c '^\\[warn\\]' <<<\"\$OUT\") = 1 ] && grep -qF \"[warn] $W1 $W2\" <<<\"\$OUT\" && [ \$(grep -n 'FEX build for this CPU' <<<\"\$OUT\" | cut -d: -f1) -lt \$(grep -n '^\\[warn\\]' <<<\"\$OUT\" | cut -d: -f1) ]"
check "F1b package selection and install line unchanged by the warning" \
  "grep -q '^apt-get install -y fex-emu-armv8.2 fex-emu-binfmt32 fex-emu-binfmt64 bubblewrap curl\$' $LOGF && grep -q 'FEX build for this CPU (ARMv8.2 features): fex-emu-armv8.2' <<<\"\$OUT\""
CAND=2610-1; run
check "F2 candidate 2610-1 (jammy, noble, resolute pockets, Debian path): no warning, install proceeds" \
  "[ $RC = 0 ] && ! grep -q '^\\[warn\\]' <<<\"\$OUT\" && grep -q '^apt-get install -y fex-emu-armv8.2 ' $LOGF"
CAND=2611-1; run
check "F2b candidate newer than the constant: no warning" "[ $RC = 0 ] && ! grep -q 'warn' <<<\"\$OUT\""
CAND=1:2607-1; run
check "F3 epoch in candidate (1:2607-1): YYMM read behind the epoch, warning names apt's candidate" \
  "[ $RC = 0 ] && grep -qF '[warn] FEX package source offers FEX 1:2607-1 for this distribution release;' <<<\"\$OUT\""
for c in 1.0-1 26071 260-1 2.607-1 0.2607; do
  CAND=$c; run
  check "F4 unparsable candidate '$c': no warning, no error, install proceeds" \
    "[ $RC = 0 ] && ! grep -q 'warn' <<<\"\$OUT\" && ! grep -qi 'not found\\|unary\\|integer expression\\|unbound' <<<\"\$OUT\" && grep -q '^apt-get install -y fex-emu-armv8.2 ' $LOGF"
done
CAND=2607-1; run "" 1
check "F5 FEX from another source: no candidate query, no warning" \
  "[ $RC = 0 ] && ! grep -q 'warn' <<<\"\$OUT\" && ! grep -q 'apt-cache policy fex-emu-armv8.2' $LOGF && grep -q 'FEX packages skipped' <<<\"\$OUT\""
check "F6 check is series-blind (same code on Ubuntu family and Debian: no os_ubuntu, VERSION_ID or codename test in the hunk)" \
  "h=\$(sed -n '/^  # candidate behind PPA/,/^fi\$/p' '$INST'); [ -n \"\$h\" ] && ! grep -q 'os_ubuntu\\|VERSION_ID\\|questing\\|CODENAME' <<<\"\$h\" && grep -q 'apt-get install -y \$FEXPKGS' <<<\"\$(sed -n '/^fi\$/,/apt-get install/p' <<<\"\$(sed -n '/^  # candidate behind PPA/,/apt-get install -y \$FEXPKGS/p' '$INST')\")\""
check "F7 warning text clinical: no articles, no em dash, no we/our" \
  "! grep -Eq ' (a|an|the) |—| we | our ' <<<\"$W1 $W2\""
check "F8 --detect prints no PPA candidate line (no network, source absent before setup)" "! grep -q 'FEX_PPA_CURRENT\\|FEX_CAND' <<<\"\$(sed -n '/^gpu_report(){/,/^}/p' '$INST')\""

echo "fexppa 3.1: $pass pass, $fail fail"
[ "$fail" = 0 ]
