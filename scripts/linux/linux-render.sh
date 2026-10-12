#!/usr/bin/env bash
# scripts/linux/linux-render.sh -- the Linux rewrites of the user-level reference, in ONE place.
# Sourced by scripts/install-user-level-linux.sh (writes them) and scripts/verify-user-level-drift.sh
# (expects them on a Linux host), so the two can never disagree about what a correct install is.

LINUX_PATH_FROM='G:/git'
LINUX_PATH_TO='~/git'

# linux_rewrite_paths: stdin -> stdout, the reference's Windows repo root written as the Linux one.
linux_rewrite_paths() { sed "s#$LINUX_PATH_FROM#$LINUX_PATH_TO#g"; }

# linux_render_claude_md <reference CLAUDE.md> <platform file>: prints the Linux CLAUDE.md --
# the Windows "Platform" section replaced by the platform file, then the path rewrite.
linux_render_claude_md() {
  awk -v plat="$2" '
    /^## Platform: Windows \+ Git Bash/ { while ((getline line < plat) > 0) print line; skip = 1; next }
    skip && /^## / { skip = 0 }
    !skip { print }' "$1" | linux_rewrite_paths
}

# linux_check_rendered <rendered CLAUDE.md>: the two post-checks of a Linux rendering, shared by the
# installer (checks what it is about to write) and the drift script (self-checks its own expectation).
# Silent and 0 when clean; otherwise prints the offending lines and a final message line, returns 1.
linux_check_rendered() {
  local bad=0
  if ! grep -q '^## Platform: Linux' "$1"; then
    echo "platform section not replaced (reference heading changed?)"; bad=1
  fi
  if grep -n 'G:/\|PowerShell 5.1\|Git Bash' "$1"; then
    echo "Windows-only text left in CLAUDE.md (lines above)"; bad=1
  fi
  return $bad
}
