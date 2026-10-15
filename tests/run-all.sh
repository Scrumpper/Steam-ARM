#!/bin/bash
# Runs every suite; prints pass, fail and skip counts. Layouts: repo checkout (tests/ under source root, earlier releases
# from git history) or project folder (<V>-tests beside <V>-work, earlier releases from <V>-work folders).
# Links source, tests and earlier releases into a run folder without spaces; exports SARM_INST, SARM_CFG, SARM_TESTS,
# SARM_OLD (<version>/ tree per release), SARM_PREV, SARM_VERSION, SARM_GATES. Caller's SARM_INST / SARM_CFG kept.
# Suite fails on any FAIL line, nonzero status, or neither PASS nor SKIP line; skipped suite = SKIP lines only.
# Run fails when ~/.config/kwinrulesrc (guarded only when present) changed. SARM_REQUIRE_ALL=1 fails a suite with any SKIP.
# SARM_LOGDIR=DIR keeps each suite's output. Usage: run-all.sh [suite-name-substring ...]
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)
UP=$(dirname "$HERE")
if [ -f "$UP/steam-arm-install.sh" ]; then SRC=$UP MODE=repo
else SRC=$UP/$(basename "$HERE" | sed 's/-tests$/-work/') MODE=project; fi
VER=$(sed -n 's/^SA_VERSION=//p' "$SRC/steam-arm-install.sh" 2>/dev/null | head -n 1)
[ -n "$VER" ] || { echo "run-all: no SA_VERSION in $SRC/steam-arm-install.sh" >&2; exit 2; }
RUN=$(mktemp -d "${TMPDIR:-/tmp}/sarm-run.XXXXXX") || exit 2
trap 'rm -rf "$RUN"' EXIT
case $RUN in *[[:space:]]*) echo "run-all: run folder path has spaces: $RUN" >&2; exit 2 ;; esac
# embedded settings menu of an installer, byte for byte
menu_of(){ awk "/^menu_app\\(\\)\\{ cat <<'STEAMARMCONFIG'\$/{f=1;next} /^STEAMARMCONFIG\$/{f=0} f" "$1" > "$2"; chmod 755 "$2"; }
ln -s "$HERE" "$RUN/tests"
if [ -f "$SRC/steam-arm-config" ]; then ln -s "$SRC" "$RUN/work"
else
  # copy, not links: suites edit copies of work files and must never reach the checkout
  mkdir "$RUN/work"
  for f in "$SRC"/* "$SRC"/.github "$SRC"/.gitignore; do
    [ -e "$f" ] && [ "$f" != "$HERE" ] && cp -a "$f" "$RUN/work/"
  done
  menu_of "$SRC/steam-arm-install.sh" "$RUN/work/steam-arm-config"
fi
# releases by SA_VERSION: newest commit or work folder per version
mkdir "$RUN/old"; ln -s "$RUN/work" "$RUN/old/$VER"
if [ $MODE = repo ] && git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  for c in $(git -C "$SRC" log --format=%H -- steam-arm-install.sh); do
    v=$(git -C "$SRC" show "$c:steam-arm-install.sh" 2>/dev/null | sed -n 's/^SA_VERSION=//p' | head -n 1)
    [ -n "$v" ] && [ ! -e "$RUN/old/$v" ] || continue
    mkdir "$RUN/old/$v"; git -C "$SRC" archive "$c" | tar -x -C "$RUN/old/$v"
    [ -f "$RUN/old/$v/steam-arm-config" ] || menu_of "$RUN/old/$v/steam-arm-install.sh" "$RUN/old/$v/steam-arm-config"
  done
elif [ $MODE = project ]; then
  for d in "$UP"/[0-9]*-work; do
    v=$(sed -n 's/^SA_VERSION=//p' "$d/steam-arm-install.sh" 2>/dev/null | head -n 1)
    [ -n "$v" ] && [ ! -e "$RUN/old/$v" ] && ln -s "$d" "$RUN/old/$v"
  done
fi
PREV=$(ls "$RUN/old" | sort -V | awk -v v="$VER" '$0 == v {print p} {p = $0}')
if [ $MODE = repo ]; then GATES=$SRC/tools/gates; else GATES=$UP/tools; fi
export SARM_TESTS=$RUN/tests SARM_OLD=$RUN/old SARM_PREV=$PREV SARM_VERSION=$VER SARM_GATES=$GATES PYTHONDONTWRITEBYTECODE=1
: "${SARM_INST:=$RUN/work/steam-arm-install.sh}"; : "${SARM_CFG:=$(dirname "$SARM_INST")/steam-arm-config}"
export SARM_INST SARM_CFG
echo "run-all: version $VER ($MODE layout); releases available: $(ls "$RUN/old" | sort -V | paste -sd' ' -)"
T=$SARM_TESTS
# menu suites first; each builds its own fake tree
SUITES="config-ui/tests.sh config-ui/tests21.sh config-ui/tests21b.sh config-ui/tests23.sh"
for f in "$T"/test_*.sh "$T"/test_*.py; do [ -e "$f" ] && SUITES="$SUITES ${f#"$T"/}"; done
total_p=0 total_f=0 total_s=0 bad=""
# host KDE rules file, when present: no suite may change it (a stray kwriteconfig writes the real one)
KW=$HOME/.config/kwinrulesrc KW0=
if [ -e "$KW" ]; then KW0=$(sha256sum < "$KW"); else echo "run-all: kwinrulesrc guard off (no $KW)"; fi
for s in $SUITES; do
  if [ $# -gt 0 ]; then m=0; for a in "$@"; do case $s in *"$a"*) m=1 ;; esac; done; [ $m = 1 ] || continue; fi
  log=$(mktemp)
  case $s in *.py) python3 "$T/$s" >"$log" 2>&1 ;; *) bash "$T/$s" >"$log" 2>&1 ;; esac
  rc=$?
  p=$(grep -c '^PASS' "$log"); f=$(grep -c '^FAIL' "$log"); k=$(grep -c '^SKIP' "$log")
  printf '%-28s %4d pass %3d fail  rc %d' "$s" "$p" "$f" "$rc"; [ "$k" = 0 ] && echo || echo "  $k skip"
  [ "$p" = 0 ] && [ "$k" = 0 ] && echo "    no checks ran"
  grep '^SKIP' "$log" | head -n 10 | sed 's/^/    /'
  ok=1; [ "$p" -gt 0 ] || [ "$k" -gt 0 ] || ok=0; [ "$f" = 0 ] && [ "$rc" = 0 ] || ok=0
  [ "${SARM_REQUIRE_ALL:-0}" = 1 ] && [ "$k" != 0 ] && ok=0
  if [ $ok = 0 ]; then
    bad="$bad $s"; grep '^FAIL' "$log" | head -n 10 | sed 's/^/    /'
    [ "$f" = 0 ] && tail -n 5 "$log" | sed 's/^/    | /'
  fi
  if [ -n "${SARM_LOGDIR:-}" ]; then mkdir -p "$SARM_LOGDIR"; cp "$log" "$SARM_LOGDIR/$(printf '%s' "$s" | tr / _).log"; fi
  total_p=$((total_p + p)); total_f=$((total_f + f)); total_s=$((total_s + k)); rm -f "$log"
done
if [ -n "$KW0" ] && [ "$( { sha256sum < "$KW"; } 2>/dev/null)" != "$KW0" ]; then
  echo "run-all: $KW changed or removed during tests"; bad="$bad kwinrulesrc"
fi
echo "version $VER: $total_p pass, $total_f fail$([ "$total_s" = 0 ] || echo ", $total_s skip")${bad:+; failing:$bad}"
[ -z "$bad" ]
