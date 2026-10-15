#!/bin/bash
# run-all.sh itself, on copies (HOME in temp dir): project layout with spaces in path, repo layout with git history,
# counts, suite with no checks fails, SKIP-only suite, kwinrulesrc guard when present, paths handed to suites.
RUNNER=${SARM_RUNNER:-$(cd "$(dirname "$0")" && pwd)/run-all.sh}
PATHS=$(dirname "$RUNNER")/paths.sh
# outer gate run may export these; checks below set them themselves
unset SARM_REQUIRE_ALL SARM_INST SARM_CFG SARM_TESTS SARM_OLD SARM_PREV SARM_VERSION SARM_GATES SARM_LOGDIR
T=$(mktemp -d /tmp/sarm232-runner.XXXXXX); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check(){ if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; printf '     %s\n' "$OUT" | tail -8; fail=$((fail + 1)); fi; }
has(){ printf '%s\n' "$OUT" | grep -q -- "$1"; }
menu(){ printf 'menu_app(){ cat <<'"'"'STEAMARMCONFIG'"'"'\n#!/bin/bash\nSA_VERSION=%s\nSTEAMARMCONFIG\n}\nSA_VERSION=%s\n' "$1" "$1"; }

# ---------- project layout: <V>-tests beside <V>-work, earlier work folders ----------
P="$T/proj dir"; mkdir -p "$P/9.8-work" "$P/9.9-work" "$P/9.9-tests/config-ui" "$T/home"
echo 'SA_VERSION=9.9' > "$P/9.9-work/steam-arm-install.sh"; echo 'SA_VERSION=9.8' > "$P/9.8-work/steam-arm-install.sh"
cp "$RUNNER" "$PATHS" "$P/9.9-tests/"
for s in tests tests21 tests21b tests23; do echo 'echo PASS x' > "$P/9.9-tests/config-ui/$s.sh"; done
echo 'echo PASS a; echo PASS b' > "$P/9.9-tests/test_ok.sh"
run(){ OUT=$(env HOME=$T/home "$@" bash "$P/9.9-tests/run-all.sh" 2>&1); rc=$?; }
run
check "all suites with checks: rc 0, totals" "[ $rc = 0 ] && has '^version 9.9: 6 pass, 0 fail\$'"
check "project layout named, earlier release listed" "has 'version 9.9 (project layout); releases available: 9.8 9.9'"
check "nothing left in HOME (no cache links)" "[ -z \"\$(ls -A '$T/home')\" ]"
echo 'echo nothing here' > "$P/9.9-tests/test_empty.sh"; run
check "suite with no PASS or SKIP line, rc 0: counted as failing" "[ $rc != 0 ] && has 'failing: test_empty.sh'"
check "no checks ran: named" "has 'no checks ran'"
rm "$P/9.9-tests/test_empty.sh"; echo 'echo PASS a; echo FAIL b' > "$P/9.9-tests/test_bad.sh"; run
check "FAIL line: failing" "[ $rc != 0 ] && has 'failing: test_bad.sh'"
echo 'echo PASS a; exit 3' > "$P/9.9-tests/test_bad.sh"; run
check "nonzero status without FAIL line: failing, output tail shown" "[ $rc != 0 ] && has 'failing: test_bad.sh' && has 'rc 3'"
rm "$P/9.9-tests/test_bad.sh"
# ---------- kwinrulesrc guard: only when file present ----------
echo 'mkdir -p "$HOME/.config"; echo "[General]" > "$HOME/.config/kwinrulesrc"; echo PASS a' > "$P/9.9-tests/test_kw.sh"; run
check "no kwinrulesrc at start: guard off and named, rc 0" "[ $rc = 0 ] && has 'kwinrulesrc guard off'"
echo 'echo PASS a' > "$P/9.9-tests/test_kw.sh"; run
check "file present before, unchanged: rc 0, no guard-off line" "[ $rc = 0 ] && ! has 'guard off'"
echo 'echo "count=0" >> "$HOME/.config/kwinrulesrc"; echo PASS a' > "$P/9.9-tests/test_kw.sh"; run
check "suite changes existing kwinrulesrc: run fails, named" "[ $rc != 0 ] && has 'kwinrulesrc changed or removed during tests' && has 'failing: kwinrulesrc'"
echo 'rm "$HOME/.config/kwinrulesrc"; echo PASS a' > "$P/9.9-tests/test_kw.sh"; run
check "suite removes existing kwinrulesrc: run fails" "[ $rc != 0 ] && has 'failing: kwinrulesrc'"
# ---------- SKIP lines ----------
echo 'echo PASS a; echo SKIP b not here' > "$P/9.9-tests/test_kw.sh"; run
check "SKIP line: counted per suite and in total, rc 0" "[ $rc = 0 ] && has 'test_kw.sh .*  1 skip\$' && has '^version 9.9: 7 pass, 0 fail, 1 skip\$' && has '    SKIP b not here'"
run SARM_REQUIRE_ALL=1
check "SARM_REQUIRE_ALL=1: suite with SKIP fails the run" "[ $rc != 0 ] && has 'failing: test_kw.sh'"
echo 'echo SKIP whole suite: not here' > "$P/9.9-tests/test_kw.sh"; run
check "SKIP-only suite: skipped, not failing" "[ $rc = 0 ] && ! has 'no checks ran' && has '^version 9.9: 6 pass, 0 fail, 1 skip\$'"
run SARM_LOGDIR=$T/logs
check "SARM_LOGDIR: one log per suite" "[ -f '$T/logs/test_kw.sh.log' ] && [ -f '$T/logs/config-ui_tests.sh.log' ] && grep -q 'whole suite' '$T/logs/test_kw.sh.log'"
# ---------- paths handed to suites ----------
cat > "$P/9.9-tests/test_kw.sh" <<'EOF'
. "$(dirname "$0")/paths.sh"
case $SARM_INST in *' '*) echo FAIL space in SARM_INST;; esac
[ "$(cat "$SARM_INST")" = SA_VERSION=9.9 ] && [ "$SARM_CFG" = "$(dirname "$SARM_INST")/steam-arm-config" ] && echo PASS inst
[ -f "$SARM_TESTS/run-all.sh" ] && [ "$SARM_VERSION" = 9.9 ] && [ "$SARM_PREV" = 9.8 ] && echo PASS tests
[ "$(cat "$(sarm_old 9.8)")" = SA_VERSION=9.8 ] && [ -z "$(sarm_old 1.0)" ] && echo PASS old
[ "$(cat "$SARM_INST")" = SA_VERSION=9.9 ] && [ -f "$SARM_CFG" ] && echo PASS found
EOF
run
check "suites get paths without spaces, version, previous release, sarm_old" "[ $rc = 0 ] && has 'test_kw.sh  *4 pass   0 fail'"
OUT=$(cd "$T" && HOME=$T/home bash "$P/9.9-tests/test_kw.sh" 2>&1)
check "suite run alone: own folders, no earlier releases" "has '^PASS found' && ! has '^PASS old'"

# ---------- repo layout: tests/ under source root, releases from git history ----------
command -v git >/dev/null || { echo "SKIP repo layout cases: git not installed"; echo "passed $pass, failed $fail"; [ "$fail" = 0 ]; exit; }
G=$T/repo; mkdir -p "$G/tests/config-ui"; cp "$RUNNER" "$PATHS" "$G/tests/"
for s in tests tests21 tests21b tests23; do echo 'echo PASS x' > "$G/tests/config-ui/$s.sh"; done
gc(){ git -C "$G" -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1; }
gc init -q; menu 9.7 > "$G/steam-arm-install.sh"; gc add -A; gc commit -qm a
menu 9.8 > "$G/steam-arm-install.sh"; gc commit -qam b
echo x >> "$G/steam-arm-install.sh"; gc commit -qam c
menu 9.9 > "$G/steam-arm-install.sh"; echo doc > "$G/README.md"
cat > "$G/tests/test_kw.sh" <<'EOF'
. "$(dirname "$0")/paths.sh"
[ "$SARM_VERSION" = 9.9 ] && [ "$SARM_PREV" = 9.8 ] && echo PASS versions
grep -qx x "$(sarm_old 9.8)" && echo PASS newest commit of 9.8
grep -qx SA_VERSION=9.7 "$(sarm_old 9.7 steam-arm-config)" && echo PASS menu extracted from 9.7 installer
grep -qx SA_VERSION=9.9 "$SARM_CFG" && [ -f "$(dirname "$SARM_INST")/README.md" ] && echo PASS work tree with extracted menu
[ ! -e "$(dirname "$SARM_INST")/tests" ] && echo PASS tests folder not in work tree
EOF
OUT=$(HOME=$T/home bash "$G/tests/run-all.sh" 2>&1); rc=$?
check "repo layout: uncommitted 9.9 under test, 9.7 and 9.8 from history" "[ $rc = 0 ] && has 'version 9.9 (repo layout); releases available: 9.7 9.8 9.9' && has 'test_kw.sh  *5 pass   0 fail'"
check "repo layout: no menu file left in source root" "[ ! -e '$G/steam-arm-config' ]"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
