#!/bin/bash
# Gate tools in tools/gates (project: tools/): check-version, check-removal, check-heredocs, scan-testtools, privacy,
# docs style, alliteration, on copies of installer and settings menu in a temp folder. SARM_GATES picks another tools copy.
. "$(dirname "$0")/paths.sh"; WORK=$(dirname "$SARM_INST"); CFG=$SARM_CFG
G=$SARM_GATES V=$SARM_VERSION
T=$(mktemp -d /tmp/sarm-gates.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | grep -v '^ok ' | tail -n 8; fail=$((fail + 1)); fi; }
# work copy: installer, settings menu, package files (check-version reads control, changelogs, build-deb.sh)
mkdir -p "$T/w"; cp "$SARM_INST" "$T/w/steam-arm-install.sh"; cp "$CFG" "$T/w/steam-arm-config"
for f in build-deb.sh CHANGELOG.md debian doc; do cp -rL "$WORK/$f" "$T/w/"; done

# ---------- version gate ----------
# menu fallback constants must follow installer PROVIDER_SHA256 (2.3 DA5)
sed -i "s/^SA_PROVIDER_SHA=.*/SA_PROVIDER_SHA=$(printf '0%.0s' $(seq 64))/" "$T/w/steam-arm-config"
OUT=$(python3 "$G/check-version.py" --work "$T/w" "$V" 2>&1); rc=$?
cp "$CFG" "$T/w/steam-arm-config"
check "check-version: menu SA_PROVIDER_SHA differing from installer PROVIDER_SHA256 caught" "[ $rc != 0 ] && grep -q '^FAIL settings menu SA_PROVIDER_SHA = installer PROVIDER_SHA256' <<<\"\$OUT\""
OUT=$(python3 "$G/check-version.py" --work "$T/w" "$V" 2>&1)
check "check-version: menu driver archive constants match installer" "grep -q '^ok   settings menu SA_PROVIDER_SHA = installer PROVIDER_SHA256' <<<\"\$OUT\" && grep -q '^ok   settings menu SA_PROVIDER_FILE = installer PROVIDER_URL' <<<\"\$OUT\""


# ---------- removal gate (Q-3) ----------
OUT=$(python3 "$G/check-removal.py" --work "$T/w" "$V" 2>&1); rc=$?
check "removal gate: current installer covered" "[ $rc = 0 ]"
cat >> "$T/w/steam-arm-install.sh" <<'EOF'
mkdir -p /etc/steam-arm-extra
touch /usr/local/lib/steam-arm-new.so
echo x | tee /usr/local/bin/steam-arm-new
curl -fsSL -o /usr/local/bin/steam-arm-dl https://example.invalid/x
dd if=/dev/zero of=/usr/local/lib/steam-arm-dd.img bs=1 count=1
install -d -m 755 /usr/local/share/steam-arm-dir
printf x > /usr/local/bin/steam-arm-con
printf x > /usr/local/lib/steam-arm
EOF
OUT=$(python3 "$G/check-removal.py" --work "$T/w" "$V" 2>&1); rc=$?
for t in /etc/steam-arm-extra /usr/local/lib/steam-arm-new.so /usr/local/bin/steam-arm-new /usr/local/bin/steam-arm-dl \
         /usr/local/lib/steam-arm-dd.img /usr/local/share/steam-arm-dir /usr/local/bin/steam-arm-con /usr/local/lib/steam-arm; do
  check "removal gate flags $t" "[ $rc != 0 ] && grep -q '^FAIL .* $t  (' <<<\"\$OUT\""
done
# run-time writer (GE-Proton helper): setup writes it, removal must call its remove-all
cp "$WORK/steam-arm-install.sh" "$T/w/steam-arm-install.sh"
OUT=$(python3 "$G/check-removal.py" --work "$T/w" "$V" 2>&1); rc=$?
check "removal gate: GE-Proton helper with remove-all call passes" "[ $rc = 0 ] && grep -q '^cat > /usr/local/lib/steam-arm-geproton.py <<' '$T/w/steam-arm-install.sh'"
sed -i 's#as_user python3 /usr/local/lib/steam-arm-geproton.py remove-all#as_user true#' "$T/w/steam-arm-install.sh"
OUT=$(python3 "$G/check-removal.py" --work "$T/w" "$V" 2>&1); rc=$?
check "removal gate flags GE-Proton helper without remove-all call" "[ $rc != 0 ] && grep -q '^FAIL runtime writes of /usr/local/lib/steam-arm-geproton.py not removed' <<<\"\$OUT\""
# x86 client helper edits Valve's files in the client folder at each start: removal must call its restore
cp "$WORK/steam-arm-install.sh" "$T/w/steam-arm-install.sh"
sed -i 's#as_user python3 /usr/local/lib/steam-arm-x86client.py restore#as_user true#' "$T/w/steam-arm-install.sh"
OUT=$(python3 "$G/check-removal.py" --work "$T/w" "$V" 2>&1); rc=$?
check "removal gate flags x86 client helper without restore call in removal" "grep -q '^cat > /usr/local/lib/steam-arm-x86client.py <<' '$T/w/steam-arm-install.sh' && [ $rc != 0 ] && grep -q '^FAIL runtime writes of /usr/local/lib/steam-arm-x86client.py not removed' <<<\"\$OUT\""
# ---------- heredoc gate (Q5, Q-6) ----------
H=$T/h; mkdir -p "$H"; cp "$SARM_INST" "$H/steam-arm-install.sh"; cp "$CFG" "$H/steam-arm-config"
for d in bin debian doc tools; do cp -rL "$WORK/$d" "$H/"; done; cp "$WORK/build-deb.sh" "$H/"
OUT=$(python3 "$G/check-heredocs.py" --work "$H" 2.3 -v 2>&1); rc=$?
check "heredoc gate: current files pass" "[ $rc = 0 ]"
check "heredoc gate: settings menu heredocs counted once when embed identical" "grep -q 'embedded copy identical' <<<\"\$OUT\" && ! grep -q '^ok   steam-arm-config:' <<<\"\$OUT\""
check "heredoc gate: unquoted MHSHIM, FEX JSON, VKJSON, CM checked; APTHOOK as apt.conf" "grep -q 'MHSHIM (sh, unquoted)' <<<\"\$OUT\" && grep -q 'JSON (json, unquoted)' <<<\"\$OUT\" && grep -q 'VKJSON (json, unquoted)' <<<\"\$OUT\" && grep -q 'CM (sh, unquoted)' <<<\"\$OUT\" && grep -q 'APTHOOK (aptconf)' <<<\"\$OUT\""
hbreak(){ cp "$WORK/steam-arm-install.sh" "$H/steam-arm-install.sh"; python3 -c '
import sys
p, old, new = sys.argv[1:4]; s = open(p).read(); assert s.count(old) == 1, old; open(p, "w").write(s.replace(old, new))' "$H/steam-arm-install.sh" "$1" "$2"
  OUT=$(python3 "$G/check-heredocs.py" --work "$H" 2.3 2>&1); RC=$?; }
hbreak '    "enable_environment": { "STEAM_ARM_VK_OVERLAY": "1" }
  }' '    "enable_environment": { "STEAM_ARM_VK_OVERLAY": "1" }'
check "heredoc gate: broken VKJSON caught" "[ $RC != 0 ] && grep -q '^FAIL .*VKJSON' <<<\"\$OUT\""
hbreak '"ThunksDB":{"GL":$FEXTH' '"ThunksDB"{"GL":$FEXTH'
check "heredoc gate: broken FEX Config.json caught" "[ $RC != 0 ] && grep -q '^FAIL .*:[0-9]* JSON (json, unquoted)' <<<\"\$OUT\""
hbreak '[ \$# -eq 2 ] || { echo "usage: steam-arm-compatmap' '[ \$# -eq 2 ] || ( echo "usage: steam-arm-compatmap'
check "heredoc gate: broken compatmap wrapper (CM) caught" "[ $RC != 0 ] && grep -q '^FAIL .* CM (sh, unquoted)' <<<\"\$OUT\""
hbreak '[ -x /usr/bin/mangohud ] && exec /usr/bin/mangohud "\$@"' '[ -x /usr/bin/mangohud ] && { exec /usr/bin/mangohud "\$@"'
check "heredoc gate: broken MangoHud shim (MHSHIM) caught" "[ $RC != 0 ] && grep -q '^FAIL .* MHSHIM (sh, unquoted)' <<<\"\$OUT\""
hbreak 'steam-arm-glx-lax || true; fi"; };' 'steam-arm-glx-lax || true; fi"; }'
check "heredoc gate: apt hook without ending ; caught" "[ $RC != 0 ] && grep -q '^FAIL .* APTHOOK (aptconf)' <<<\"\$OUT\""

# ---------- test hook scan ----------
mkdir -p "$T/s"; cp "$SARM_INST" "$T/s/steam-arm-install.sh"; cp "$CFG" "$T/s/steam-arm-config"; mkdir -p "$T/s/tools"; cp "$WORK/tools/build-driver-archive.sh" "$T/s/tools/"
OUT=$(python3 "$G/scan-testtools.py" --work "$T/s" "$V" 2>&1); rc=$?
check "scan-testtools: installer, menu, recipe pass" "[ $rc = 0 ] && grep -q 'unexpected env reads / alternate roots / hook text in work files: 0' <<<\"\$OUT\""
printf 'x=${STEAM_ARM_NEWKNOB:-1}\ny=${STEAM_ARM_FOO_TEST:-}\n# zqxprivword here\n' >> "$T/s/steam-arm-config"
printf 'zqxprivword\n' > "$T/words"
OUT=$(SARM_PRIVATE_WORDS=$T/words python3 "$G/scan-testtools.py" --work "$T/s" "$V" 2>&1); rc=$?
check "scan-testtools: new env knob, test hook and private word in menu flagged" "[ $rc != 0 ] && grep -q 'env read \${STEAM_ARM_NEWKNOB:-' <<<\"\$OUT\" && grep -q 'test hook text' <<<\"\$OUT\" && grep -q 'private word (local)' <<<\"\$OUT\""

# ---------- privacy gate ----------
mkdir -p "$T/p/doc" "$T/p/research"; printf 'clean text\nmail noreply@example.com\n' > "$T/p/README.md"
OUT=$(SARM_PRIVATE_WORDS=$T/words python3 "$G/check-private.py" "$T/p" 2>&1); rc=$?
check "privacy: clean tree passes" "[ $rc = 0 ] && grep -q 'privacy: 1 files, 0 hits' <<<\"\$OUT\""
# fixture text assembled here: the repository privacy gate scans this file too
printf 'a\nhost ZqxPrivWord\nlan %s.168.7.9\nmail someone%smailhost.com\n' 192 @ > "$T/p/doc/notes.md"
printf 'at /home/someuser/%s/x and .%s/jobs/x\n' Desktop claude > "$T/p/x.sh"
printf 'zqxprivword\n' > "$T/p/CHANGES.md"; printf 'zqxprivword\n' > "$T/p/research/r.md"
OUT=$(SARM_PRIVATE_WORDS=$T/words python3 "$G/check-private.py" "$T/p" 2>&1); rc=$?
check "privacy: private word (any case), LAN address, e-mail flagged by file:line and tag" "[ $rc != 0 ] && grep -qx 'FAIL doc/notes.md:2 local' <<<\"\$OUT\" && grep -qx 'FAIL doc/notes.md:3 lan address' <<<\"\$OUT\" && grep -qx 'FAIL doc/notes.md:4 e-mail' <<<\"\$OUT\""
check "privacy: home folder and agent job path flagged" "grep -qx 'FAIL x.sh:1 agent path' <<<\"\$OUT\" && grep -qx 'FAIL x.sh:1 home folder' <<<\"\$OUT\""
check "privacy: word itself not printed; internal files (CHANGES.md, research/) left out" "! grep -qi zqxprivword <<<\"\$OUT\" && ! grep -q 'CHANGES.md\|research/' <<<\"\$OUT\""
printf 'zqxprivword\n' > "$T/words2"; printf 'zqxprivword\n' > "$T/p2.sh"
OUT=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import privacy; privacy.ALLOW.add(("x.sh", "local")); print(privacy.hits("zqxprivword", "x.sh"), privacy.hits("zqxprivword", "y.sh"))' "$G" 2>&1)
OUT2=$(SARM_PRIVATE_WORDS=$T/words2 python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import privacy; privacy.ALLOW.add(("x.sh", "local")); print(privacy.hits("a ZQXPRIVWORD b", "x.sh"), privacy.hits("a ZQXPRIVWORD b", "y.sh"))' "$G" 2>&1)
check "privacy: allow-list by file name and tag" "[ \"\$OUT2\" = \"[] [('zqxprivword', 'local')]\" ]"
OUT=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import privacy; print(len(privacy.HASHES) > 0, all(len(h) == 64 for h in privacy.HASHES))' "$G" 2>&1)
check "privacy: hashed word list loaded" "[ \"\$OUT\" = 'True True' ]"

# ---------- docs gate ----------
mkdir -p "$T/d"
printf '# Title\n\nFormat follows [Keep a Changelog](https://keepachangelog.com/).\nRoute A (forwarding), gfx=a|b, A/B run.\nSee [part](#title).\n\n```\nthe code keeps articles\n```\n' > "$T/d/README.md"
OUT=$(python3 "$G/check-docs.py" "$T/d" 2>&1); rc=$?
check "docs: clinical text passes (Keep a Changelog, route A, a|b, code fence)" "[ $rc = 0 ]"
printf '# T\n\nThe setup runs. Setup ships x. We test it. It is very fast. Use an option \xe2\x80\x94 or a flag.\nSee [x](#missing).\n```\nopen fence\n' > "$T/d/README.md"
OUT=$(python3 "$G/check-docs.py" "$T/d" 2>&1); rc=$?
check "docs: article, ship, first person plural, filler, dash, dangling link, open fence flagged" "[ $rc != 0 ] && grep -q 'article: The setup' <<<\"\$OUT\" && grep -q ' ship: ' <<<\"\$OUT\" && grep -q 'first person plural' <<<\"\$OUT\" && grep -q 'filler word' <<<\"\$OUT\" && grep -q ' dash: ' <<<\"\$OUT\" && grep -q 'dangling in-page link: #missing' <<<\"\$OUT\" && grep -q 'unbalanced code fences' <<<\"\$OUT\""
printf 'x\n' > "$T/d/CHANGES.md"; printf 'The note.\n' > "$T/d/CHANGES.md"; printf '# T\n' > "$T/d/README.md"
OUT=$(python3 "$G/check-docs.py" "$T/d" 2>&1); rc=$?
check "docs: internal CHANGES.md not checked" "[ $rc = 0 ] && ! grep -q CHANGES <<<\"\$OUT\""

# ---------- alliteration gate ----------
printf '# Title\n\nSetup stores values in `/etc/steam-arm`; menu reads them.\nPanfrost and PanVK on Panthor drive it.\n\n```\nsame sentence sits still\n```\n' > "$T/d/README.md"
OUT=$(python3 "$G/check-alliteration.py" "$T/d" 2>&1); rc=$?
check "alliteration: pairs, allow-listed names, code fence pass" "[ $rc = 0 ] && grep -q 'alliteration: 1 files, 0 hits' <<<\"\$OUT\""
printf '# T\n\nSetup saves several settings at start.\n| same sentence sits | still |\n' > "$T/d/README.md"
OUT=$(python3 "$G/check-alliteration.py" "$T/d" 2>&1); rc=$?
check "alliteration: three same-initial words in four flagged by file:line; table row ignored" "[ $rc != 0 ] && grep -q 'README.md:3 ' <<<\"\$OUT\" && ! grep -q 'README.md:4' <<<\"\$OUT\""
# openers (3.1 round 2): repeated first word on bullets, sentences, determiner clauses; slogan phrases
printf '# T\n\n- Tray icon shows state.\n- Tray menu opens pages.\n\nSetup stores values. Setup reads them back.\nOff unless set, never global, never per client.\nOne script, readable before running; nothing bundled, nothing installed.\n' > "$T/d/README.md"
OUT=$(python3 "$G/check-alliteration.py" "$T/d" 2>&1); rc=$?
check "openers: bullet, sentence, clause and phrase hits flagged by kind and line" "[ $rc != 0 ] && grep -q \"README.md:4 bullet opener 'tray'\" <<<\"\$OUT\" && grep -q \"README.md:6 sentence opener 'setup'\" <<<\"\$OUT\" && grep -q \"README.md:7 clause opener 'never'\" <<<\"\$OUT\" && grep -q \"README.md:8 phrase 'One script'\" <<<\"\$OUT\" && grep -q \"README.md:8 clause opener 'nothing'\" <<<\"\$OUT\" && grep -q \"README.md:8 phrase 'nothing bundled'\" <<<\"\$OUT\" && grep -q 'hits (0 windows, 7 openers)' <<<\"\$OUT\""
printf '# T\n\n- \x60steam-arm\x60 starts client.\n- \x60steam-arm-config\x60 opens menu.\n- [Install](#t)\n- [Install notes](#t)\n\n1. Debian 12\n2. Debian 11\n\n| one script | one file |\n\n- Setup stores values.\n\n- Setup reads them.\n- Run \x60one script\x60 then stop.\n- If x, if y.\n' > "$T/d/README.md"
OUT=$(python3 "$G/check-alliteration.py" "$T/d" 2>&1); rc=$?
check "openers: code-span and link bullets, numbered list, table row, code span phrase, blank-line break, function words pass" "[ $rc = 0 ] && grep -q 'alliteration: 1 files, 0 hits' <<<\"\$OUT\""
printf '# T\n\n- Debian 12: ok.\n- Debian 11: halts.\n' > "$T/d/README.md"
mkdir -p "$T/g"; cp "$G"/*.py "$G"/*.txt "$T/g/" 2>/dev/null; cp "$G"/*.sha256 "$T/g/" 2>/dev/null
printf 'README.md:Debian   # requirement list per release\n' >> "$T/g/openers-allow.txt"
OUT=$(python3 "$T/g/check-alliteration.py" "$T/d" 2>&1); rc=$?
check "openers: allow-list entry scoped to file with reason passes" "[ $rc = 0 ]"
printf 'Debian\n' > "$T/g/openers-allow.txt"; printf '# T\n\n- Debian 12: ok.\n- Debian 11: halts.\n' > "$T/d/CHANGELOG.md"
OUT=$(python3 "$T/g/check-alliteration.py" "$T/d" 2>&1); rc=$?
check "openers: unscoped allow-list entry covers every file" "[ $rc = 0 ] && grep -q 'alliteration: 2 files, 0 hits' <<<\"\$OUT\""
rm -f "$T/d/CHANGELOG.md"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
