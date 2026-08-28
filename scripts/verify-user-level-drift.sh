#!/usr/bin/env bash
# verify-user-level-drift.sh
#
# Diff user-level-reference/CLAUDE.md against the live ~/.claude/CLAUDE.md.
#
# Direction of truth: **the reference leads, the live copy follows.** The repo
# file is edited first; ~/.claude/CLAUDE.md is updated by the reader per the
# CHANGELOG's "Downstream migration" section. So a DRIFT result in the same
# session that changed the reference is expected, not a regression — it means
# the migration step has not been run on this machine yet.
#
# Run ad-hoc; not wired into any hook.
set -u
REF="user-level-reference/CLAUDE.md"
LIVE="$HOME/.claude/CLAUDE.md"

if [ ! -f "$REF" ]; then
  echo "ERROR: $REF not found — run from repo root"
  exit 2
fi
if [ ! -f "$LIVE" ]; then
  echo "ERROR: $LIVE not found — no live user-level CLAUDE.md to compare"
  exit 2
fi

if diff -q "$REF" "$LIVE" >/dev/null; then
  echo "in sync: $REF == $LIVE"
  exit 0
else
  echo "DRIFT: $LIVE differs from $REF"
  echo "The reference leads. Apply CHANGELOG.md -> latest 'Downstream migration' to resync."
  echo "--- diff (reference -> live) ---"
  diff -u "$REF" "$LIVE" || true
  exit 1
fi
