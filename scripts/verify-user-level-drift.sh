#!/usr/bin/env bash
# verify-user-level-drift.sh
#
# Diff user-level-reference/{CLAUDE.md,hooks/**,skills/**,agents/**} against
# the live ~/.claude/ tree.
#
# Direction of truth: **the reference leads, the live copy follows.** The repo
# files are edited first; ~/.claude/ is updated by the reader per the
# CHANGELOG's "Downstream migration" section. So a DRIFT result in the same
# session that changed the reference is expected, not a regression — it means
# the migration step has not been run on this machine yet.
#
# Run ad-hoc; not wired into any hook. Works from any cwd (cd's to repo root).
set -u

cd "$(dirname "$0")/.." || { echo "ERROR: cannot resolve repo root"; exit 2; }

LIVE_ROOT="$HOME/.claude"
if [ ! -d "$LIVE_ROOT" ]; then
  echo "ERROR: $LIVE_ROOT not found — no live user-level tree to compare"
  exit 2
fi

checked=0
in_sync=0
drift=0
drift_list=""

check_file() { # <ref_path> <live_path>
  checked=$((checked + 1))
  if [ ! -f "$2" ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  MISSING live: $2"
    return
  fi
  if diff -q "$1" "$2" >/dev/null 2>&1; then
    in_sync=$((in_sync + 1))
  else
    drift=$((drift + 1))
    drift_list="$drift_list
  DRIFT: $2 differs from $1"
  fi
}

check_file "user-level-reference/CLAUDE.md" "$LIVE_ROOT/CLAUDE.md"

for sub in hooks skills agents; do
  [ -d "user-level-reference/$sub" ] || continue
  while IFS= read -r f; do
    rel="${f#user-level-reference/}"
    check_file "$f" "$LIVE_ROOT/$rel"
  done < <(find "user-level-reference/$sub" -type f)
done

if [ "$drift" -gt 0 ]; then
  echo "DRIFT DETECTED. The reference leads. Apply CHANGELOG.md -> latest 'Downstream migration' to resync."
  printf '%s\n' "$drift_list"
fi

echo "$checked files checked, $in_sync in sync, $drift drift"

[ "$drift" -eq 0 ] && exit 0
exit 1
