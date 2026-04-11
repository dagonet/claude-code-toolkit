#!/usr/bin/env bash
# PreToolUse hook: require tier declaration + challenge evidence before spawning coder agents
# Matcher: Agent
#
# Only blocks coder types (coder, dotnet-coder, java-coder, python-coder, rust-coder).
# All other agent types pass through without checks.
# Requires the plan file to contain both a tier declaration (Tier: T1-T4)
# and evidence of architect challenge (word "challenge" or "architect").

TOOL_INPUT=$(cat)
SUBAGENT_TYPE=$(node -e "console.log(JSON.parse(process.argv[1]).subagent_type||'')" "$TOOL_INPUT" 2>/dev/null)

# Only block coder types — everything else passes through
case "$SUBAGENT_TYPE" in
  coder|dotnet-coder|java-coder|python-coder|rust-coder)
    ;;
  *)
    exit 0
    ;;
esac

# Check for plan file with tier declaration AND challenge evidence
check_plans() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  # Find plan files with a tier declaration
  local tier_file
  tier_file=$(find "$dir" -maxdepth 1 -name '*.md' -exec grep -l 'Tier:.*T[1-4]' {} + 2>/dev/null | head -1)
  [ -n "$tier_file" ] || return 1
  # Verify the same file has challenge/architect evidence
  if grep -qi 'challenge\|architect' "$tier_file" 2>/dev/null; then
    return 0
  fi
  # Tier found but no challenge evidence
  echo "BLOCKED: Plan has a tier declaration but no evidence of architect challenge. Run a plan challenge before spawning coder agents." >&2
  exit 2
}

check_plans "docs/plans" && exit 0
check_plans "$HOME/.claude/plans" && exit 0

echo "BLOCKED: No plan with tier declaration found. Declare a tier (T1-T4) in a plan file before spawning coder agents." >&2
exit 2
