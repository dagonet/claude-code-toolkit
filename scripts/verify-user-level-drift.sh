#!/usr/bin/env bash
# verify-user-level-drift.sh
#
# Diff user-level-reference/CLAUDE.md against the live ~/.claude/CLAUDE.md.
# Documents the manual-sync expectation from the wire-superpowers-skills
# Deliverable 3: the repo file is a reference copy of the live user-level file.
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
  echo "--- diff (reference -> live) ---"
  diff -u "$REF" "$LIVE" || true
  exit 1
fi
