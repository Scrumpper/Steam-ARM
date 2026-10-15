#!/bin/bash
# release-gates.sh [--release] [--with-tests]: source gates for this checkout. Script syntax, version consistency,
# heredoc syntax, removal drift, test hooks and env reads, privacy, docs style, package build. Settings menu checked as
# embedded in installer. --release: changelog entries dated, test suites with no SKIP; --with-tests: run tests/run-all.sh.
# Exit 1 when any gate fails.
G=$(cd "$(dirname "$0")/gates" && pwd)
ROOT=$(dirname "$(dirname "$G")")
REL="" TESTS=0
for a in "$@"; do
  case $a in --release) REL=--release; TESTS=1 ;; --with-tests) TESTS=1 ;; *) echo "usage: $0 [--release] [--with-tests]" >&2; exit 2 ;; esac
done
V=$(sed -n 's/^SA_VERSION=//p' "$ROOT/steam-arm-install.sh" | head -n 1)
[ -n "$V" ] || { echo "release-gates: no SA_VERSION in installer" >&2; exit 2; }
# work copy: checkout files plus settings menu extracted from installer
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
for f in "$ROOT"/* "$ROOT"/.github; do [ -e "$f" ] && [ "${f##*/}" != tests ] && cp -a "$f" "$W/"; done
awk "/^menu_app\\(\\)\\{ cat <<'STEAMARMCONFIG'\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f" "$ROOT/steam-arm-install.sh" > "$W/steam-arm-config"
fails=()
gate(){ local name=$1; shift; echo "=== $name"; if "$@"; then echo "--- $name: ok"; else echo "--- $name: FAILED"; fails+=("$name"); fi; }
gate "bash -n installer, settings menu, launcher, recipe" bash -c "for f in '$ROOT/steam-arm-install.sh' '$W/steam-arm-config' '$ROOT/bin/steam-arm-setup' '$ROOT/tools/build-driver-archive.sh'; do bash -n \"\$f\" || exit 1; done"
gate "sh -n package scripts and build-deb.sh" sh -c "sh -n '$ROOT/debian/postinst' && sh -n '$ROOT/debian/prerm' && sh -n '$ROOT/build-deb.sh'"
gate "version consistency" python3 "$G/check-version.py" --work "$W" "$V" $REL
gate "heredoc syntax" python3 "$G/check-heredocs.py" --work "$W" "$V"
gate "removal drift" python3 "$G/check-removal.py" --work "$W" "$V"
gate "test hooks, env reads, private words in installer and menu" python3 "$G/scan-testtools.py" --work "$W" "$V"
gate "privacy (every file)" python3 "$G/check-private.py" "$ROOT"
gate "docs style" python3 "$G/check-docs.py" "$ROOT"
gate "package: reproducible, contents" bash "$G/deb-check.sh" "$ROOT"
if [ $TESTS = 1 ]; then
  if [ -n "$REL" ]; then gate "test suites (no SKIP)" env SARM_REQUIRE_ALL=1 bash "$ROOT/tests/run-all.sh"
  else gate "test suites" bash "$ROOT/tests/run-all.sh"; fi
fi
echo
if [ ${#fails[@]} -eq 0 ]; then echo "release-gates $V${REL:+ $REL}: all gates passed"; exit 0; fi
printf 'release-gates %s: FAILED: %s\n' "$V${REL:+ $REL}" "$(IFS=,; echo "${fails[*]}")"
exit 1
