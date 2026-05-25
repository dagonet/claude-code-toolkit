#!/usr/bin/env bash
# PreToolUse hook: block direct `git` / `gh` CLI use via Bash, routing to MCP.
#
# Matcher: Bash
#
# The MCP usage rules (CLAUDE.local.md) require all git operations to go through
# the git-tools MCP and all GitHub operations through the github-tools / GitHub
# MCP. This hook is the defense-in-depth Bash block for that rule.
#
# It fires ONLY when the first token of a sub-command is exactly `git` or `gh`.
# Sub-commands are split on ; && || | & and newlines. This avoids the substring
# false-positives of the old `if: "Bash(gh *)"` glob, which blocked any command
# merely CONTAINING "git"/"gh" — e.g. `npx playwright test` (playwri-GH-t),
# `npm run lint`, or any `*git*`/`*gh*`-named tool.
#
# Limitation (matches the "first token is exactly git/gh" spec): prefix wrappers
# such as `sudo git`, `env X=Y git`, `\git`, and `(git ...)` are NOT caught. This
# is a soft guardrail, not a security control — the MCP tools remain the only
# blessed path. Mirrors the JSON-via-`node -e` parsing pattern used by
# no-push-main.sh, tier-before-coder.sh, and require-skills-block.sh.

TOOL_INPUT=$(cat)
COMMAND=$(node -e "const j=JSON.parse(process.argv[1]);console.log((j.tool_input&&j.tool_input.command)||j.command||'')" "$TOOL_INPUT" 2>/dev/null || echo '')

# No command to inspect (empty or unparseable input) -> allow.
[ -z "$COMMAND" ] && exit 0

# Split into sub-commands: turn &&, ||, ;, &, | and newlines into newlines.
# The alternation lists the two-char operators before the single-char class so
# `&&`/`||` are not consumed half at a time.
normalized=$(printf '%s' "$COMMAND" | sed -E 's/&&|\|\||[;&|]/\n/g')

# Inspect the first token of each sub-command. Use a here-string (NOT a pipe into
# `while read`) so the `blocked` assignment survives in the current shell.
blocked=""
while IFS= read -r seg; do
  first=$(printf '%s' "$seg" | awk '{print $1}')
  case "$first" in
    git) blocked="git" ;;
    gh)  blocked="gh" ;;
  esac
done <<< "$normalized"

case "$blocked" in
  git)
    echo "BLOCKED: Use MCP git-tools instead of Bash git commands. See CLAUDE.local.md." >&2
    exit 2
    ;;
  gh)
    echo "BLOCKED: Use MCP github-tools instead of Bash gh CLI. See CLAUDE.local.md." >&2
    exit 2
    ;;
esac

exit 0
