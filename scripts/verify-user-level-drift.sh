#!/usr/bin/env bash
# verify-user-level-drift.sh [--worktree | <git-ref>]
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
# THE REFERENCE IS A RELEASED TAG, NOT THE WORKING TREE (v2.2.5 round 4).
# Measured: a live ~/.claude/ copy byte-identical to an UNMERGED branch made this
# script report 0 drift — so the delivery probe certified that an unreviewed,
# ship-blocked revision had reached a user's machine. Green meant the opposite of
# what the check exists to establish. Comparing against the last released tag
# makes "0 drift" mean "the live tree matches something that shipped", which is
# the only claim worth making. In-flight reference edits on a branch then read as
# UNRELEASED and are listed, not silently blessed.
#
# `--worktree` restores the old behaviour for pre-release inspection. It prints a
# banner and is never a release check.
#
# Run ad-hoc; not wired into any hook. Works from any cwd (cd's to repo root).
set -u

cd "$(dirname "$0")/.." || { echo "ERROR: cannot resolve repo root"; exit 2; }

MODE="tag"
REF=""
case "${1:-}" in
  --worktree) MODE="worktree" ;;
  "") ;;
  *) REF="$1" ;;
esac

LIVE_ROOT="$HOME/.claude"
if [ ! -d "$LIVE_ROOT" ]; then
  echo "ERROR: $LIVE_ROOT not found — no live user-level tree to compare"
  exit 2
fi

if [ "$MODE" = "tag" ]; then
  if [ -z "$REF" ]; then
    REF=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null)
  fi
  # Cannot-determine REFUSES. A silent fallback to the working tree is exactly
  # the failure this mode was added to close.
  if [ -z "$REF" ] || ! git rev-parse --verify "$REF^{commit}" >/dev/null 2>&1; then
    echo "ERROR: cannot resolve a released reference (no v* tag reachable from HEAD)."
    echo "  Pass an explicit <git-ref>, or --worktree to compare against the working tree (NOT a release check)."
    exit 2
  fi
  echo "REFERENCE: $REF ($(git rev-parse --short "$REF^{commit}")) — released tree"
else
  echo "REFERENCE: WORKING TREE — this is NOT a release check. A live copy matching"
  echo "  an unshipped branch will report 0 drift, which certifies nothing."
fi

checked=0
in_sync=0
drift=0
unreleased=0
drift_list=""
unreleased_list=""

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# Materialise the reference copy of <repo-path>; prints the path, or nothing
# when the file does not exist at that reference.
ref_copy() { # <repo-relative path>
  if [ "$MODE" = "worktree" ]; then
    [ -f "$1" ] && printf '%s' "$1"
    return
  fi
  out="$TMPD/$(printf '%s' "$1" | tr '/' '_')"
  if git show "$REF:$1" > "$out" 2>/dev/null; then
    printf '%s' "$out"
  fi
}

check_file() { # <repo-relative ref path> <live_path>
  src=$(ref_copy "$1")
  if [ -z "$src" ]; then
    # Present on this branch, absent from the released reference.
    unreleased=$((unreleased + 1))
    unreleased_list="$unreleased_list
  UNRELEASED (not in $REF, not compared): $1"
    return
  fi
  checked=$((checked + 1))
  if [ ! -f "$2" ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  MISSING live: $2"
    return
  fi
  if diff -q "$src" "$2" >/dev/null 2>&1; then
    in_sync=$((in_sync + 1))
  else
    drift=$((drift + 1))
    drift_list="$drift_list
  DRIFT: $2 differs from $1@${REF:-worktree}"
  fi
}

check_file "user-level-reference/CLAUDE.md" "$LIVE_ROOT/CLAUDE.md"

# The file SET comes from the reference too, not from the working tree: a file
# added on a branch must not enlarge a released-tree comparison.
for sub in hooks skills agents; do
  if [ "$MODE" = "worktree" ]; then
    [ -d "user-level-reference/$sub" ] || continue
    files=$(find "user-level-reference/$sub" -type f)
  else
    files=$(git ls-tree -r --name-only "$REF" -- "user-level-reference/$sub" 2>/dev/null)
  fi
  [ -n "$files" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#user-level-reference/}"
    check_file "$f" "$LIVE_ROOT/$rel"
  done <<EOF
$files
EOF
done

# Files on this branch that the released reference does not carry. Reported so
# an in-flight addition is visible rather than invisible; never a failure.
if [ "$MODE" = "tag" ]; then
  for sub in hooks skills agents; do
    [ -d "user-level-reference/$sub" ] || continue
    while IFS= read -r f; do
      git cat-file -e "$REF:$f" 2>/dev/null && continue
      unreleased=$((unreleased + 1))
      unreleased_list="$unreleased_list
  UNRELEASED (not in $REF, not compared): $f"
    done < <(find "user-level-reference/$sub" -type f)
  done
fi

if [ "$drift" -gt 0 ]; then
  echo "DRIFT DETECTED. The reference leads. Apply CHANGELOG.md -> latest 'Downstream migration' to resync."
  printf '%s\n' "$drift_list"
fi
if [ "$unreleased" -gt 0 ]; then
  echo "UNRELEASED reference files (expected on a feature branch; they ship with the release):"
  printf '%s\n' "$unreleased_list"
fi

echo "$checked files checked against ${REF:-working tree}, $in_sync in sync, $drift drift, $unreleased unreleased"

[ "$drift" -eq 0 ] && exit 0
exit 1
