#!/usr/bin/env bash
# plant.sh <target-tree> -- plant REAL PROJECT-CUSTOM region content.
#
# WHY THIS EXISTS. A region guard validated against FOUND content proves
# nothing: a census across three consumer repos found ZERO real region content
# (11, 10 and 1 region-bearing files, all placeholder-only), so the guard
# CANNOT FAIL on any of them and a green run there is not evidence. Every
# region guard is validated against PLANTED content instead, and this is the
# planting.
#
# `TEMPLATE_DELETED × region-bearing` has never run anywhere.
#
# PROVENANCE: authored by the open-brain consumer and handed over on 2026-09-02
# when the branch that held it was deleted. It is the only known source of real
# region content anywhere, which is why it is committed here rather than left
# as a branch someone has to keep alive.
#
# BASE-AGNOSTIC, SO THE FIXTURE IS A PARAMETER AND NOT A MAINTAINED BRANCH. All
# region-bearing files ship an identical placeholder block, so planting is one
# exact string replacement per file against ANY base tag — `git checkout
# v2.2.4` plus this script covers the standing wide-jump migration requirement
# for free.
#
# ⚠ DO NOT "TIDY" THE BEGIN MARKER. It carries an EM-DASH and TRAILING PROSE
# after it, and that is precisely what breaks a naive `BEGIN\s*-->` extractor —
# the defect region.sh must not have. Only the MIDDLE line is replaced; both
# marker lines are kept verbatim. A generator that normalises the marker
# destroys the property the fixture tests.
#
# ⚠ SIZE IS LOAD-BEARING. The three regions are 767 B, 965 B and 929 B of real
# project knowledge, not filler. A 40-byte region and a 900-byte region are not
# equally good at catching a truncating preserve; if you add fixtures, stay in
# the 750–1000 B range.
#
# The three files span shapes the machinery treats differently:
#   .claude/agents/coder.md  the modal TEMPLATE_DELETED case
#   AGENT_TEAM.md            target of the later ~97% shrink — preservation
#                            must survive a near-total template-part deletion
#   CLAUDE.md                deviates OUTSIDE its region too, so it exercises
#                            deviation and preservation together
#
# Usage: bash plant.sh <target-tree>
#   Plants into <target-tree>/{.claude/agents/coder.md,AGENT_TEAM.md,CLAUDE.md}
#   wherever the shipped placeholder block is present. Prints one line per
#   file: PLANTED <path> <bytes>, or SKIP <path> <reason>.
# Exit 0 only when every file that exists was planted.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TARGET="${1:-}"
[ -n "$TARGET" ] && [ -d "$TARGET" ] || {
  echo "usage: plant.sh <target-tree>" >&2
  exit 1
}

PLACEHOLDER='<!-- Project-specific rules, routing blocks, and extensions go here. -->'

plant() { # <relative path> <region file>
  p="$TARGET/$1"
  r="$HERE/$2"
  if [ ! -f "$p" ]; then
    echo "SKIP $1 (not present in target)"
    return 0
  fi
  if ! grep -qF "$PLACEHOLDER" "$p"; then
    echo "SKIP $1 (no shipped placeholder line — already planted, or the block changed)"
    return 1
  fi
  # awk, so the replacement is an exact whole-line swap and nothing in the
  # region body is ever interpreted as a pattern or a backreference. A sed
  # `s@@@` here would mangle the `$$`, `$func$` and `&` the content contains.
  awk -v ph="$PLACEHOLDER" -v rf="$r" '
    index($0, ph) > 0 && !done {
      while ((getline line < rf) > 0) print line
      close(rf); done = 1; next
    }
    { print }
  ' "$p" > "$p.planted" && mv "$p.planted" "$p"
  echo "PLANTED $1 $(wc -c < "$r" | tr -d ' ')"
  return 0
}

rc=0
plant ".claude/agents/coder.md" "coder.md.region" || rc=1
plant "AGENT_TEAM.md"           "AGENT_TEAM.md.region" || rc=1
plant "CLAUDE.md"               "CLAUDE.md.region" || rc=1
exit "$rc"
