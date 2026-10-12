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
