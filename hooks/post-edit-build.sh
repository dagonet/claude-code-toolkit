#!/usr/bin/env bash
# post-edit-build.sh — PostToolUse Edit|Write. Runs the per-project post-edit build
# declared in PROJECT_CONTEXT.md (`- **Post-edit build**: <cmd>`); `none` or an
# unfilled placeholder is a no-op (the placeholder is reported). Never blocks.
set -u
. "$(dirname "$0")/lib/git-cmd.sh"
PC="${CLAUDE_PROJECT_DIR:-.}/PROJECT_CONTEXT.md"
[ -f "$PC" ] || exit 0
raw=$(grep -E -m1 "${GC_KEY_PRE}\*\*Post-edit build\*\*:" "$PC" | sed -E "s/${GC_KEY_PRE}\*\*Post-edit build\*\*:[[:space:]]*//; s/^\`//; s/\`\$//")
case "$raw" in
  ""|none) exit 0 ;;
  *'{{'*) echo "post-edit-build: unfilled placeholder in **Post-edit build** — fill it or set none" >&2; exit 0 ;;
esac
out=$(cd "${CLAUDE_PROJECT_DIR:-.}" && bash -c "$raw" 2>&1 | tail -20)
printf '%s\n' "$out" >&2
exit 0
