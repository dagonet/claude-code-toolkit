#!/usr/bin/env bash
# scripts/install-user-level-linux.sh -- install the user-level setup (~/.claude) on a Linux host
# from this checkout. A STOPGAP until the v5.0 plugin release, which replaces it.
#
# Writes: ~/.claude/{CLAUDE.md, agents/, skills/, hooks/, output-styles/, settings.json}.
# Never touches ~/.claude.json (MCP servers are registered separately with `claude mcp add`).
# Every file it overwrites is backed up first as <file>.bak-<UTC>. Re-running it is safe.
#
#   CLAUDE.md      the reference, with its Windows "Platform" section replaced by
#                  scripts/linux/CLAUDE-platform-linux.md and G:/git/ paths written as ~/git/
#   settings.json  the reference merged over the existing file, minus the Windows-only entries
#                  (CLAUDE_CODE_SHELL, CLAUDE_CODE_USE_POWERSHELL_TOOL, windows-mcp); its hooks
#                  block is rendered by scripts/render-user-hooks.sh --write
#   plugins        superpowers, skill-creator, frontend-design from claude-plugins-official
#
# Usage: bash scripts/install-user-level-linux.sh [--no-plugins]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REF=$ROOT/user-level-reference
PLAT=$ROOT/scripts/linux/CLAUDE-platform-linux.md
. "$ROOT/scripts/linux/linux-render.sh"   # the Linux rewrites, shared with verify-user-level-drift.sh
L=$HOME/.claude
TS=$(date -u +%Y%m%dT%H%M%SZ)
PLUGINS="superpowers skill-creator frontend-design"
MARKET=claude-plugins-official
DO_PLUGINS=1; [ "${1:-}" = "--no-plugins" ] && DO_PLUGINS=""

die() { echo "install-user-level-linux: $*" >&2; exit 1; }
[ "$(uname -s)" = Linux ] || die "Linux only (on Windows the user level is installed by hand, see user-level-reference/README.md)"
for t in bash git jq node; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done
[ -f "$REF/CLAUDE.md" ] && [ -f "$REF/settings.json" ] && [ -f "$PLAT" ] || die "run from a claude-code-toolkit checkout"
backup() { [ -e "$1" ] && cp -p "$1" "$1.bak-$TS" && echo "  backup: $1.bak-$TS" || true; }

mkdir -p "$L/agents" "$L/skills" "$L/hooks" "$L/output-styles"

echo "1. CLAUDE.md (Linux platform section)"
backup "$L/CLAUDE.md"
linux_render_claude_md "$REF/CLAUDE.md" "$PLAT" > "$L/CLAUDE.md.new"
chk=$(linux_check_rendered "$L/CLAUDE.md.new") || die "$chk"
mv "$L/CLAUDE.md.new" "$L/CLAUDE.md"

echo "2. agents, skills, hooks, output styles"
cp "$REF"/agents/*.md "$L/agents/"
cp -R "$ROOT"/skills/. "$L/skills/"
cp -R "$REF"/hooks/. "$L/hooks/"
cp "$ROOT"/output-styles/*.md "$L/output-styles/"
chmod +x "$L"/hooks/*.sh

echo "3. settings.json (reference minus Windows-only entries; hooks rendered)"
[ -s "$L/settings.json" ] || echo '{}' > "$L/settings.json"
backup "$L/settings.json"
plugins_json=$(for p in $PLUGINS; do printf '"%s@%s":true\n' "$p" "$MARKET"; done | paste -sd, -)
jq -s --arg pf "$LINUX_PATH_FROM" --arg pt "$LINUX_PATH_TO" --argjson ep "{$plugins_json}" '
  .[0] * (.[1]
    | del(.hooks)
    | del(.env.CLAUDE_CODE_SHELL, .env.CLAUDE_CODE_USE_POWERSHELL_TOOL)
    | .permissions.allow |= map(select(test("windows-mcp") | not))
    | .autoMode.environment |= map(gsub($pf; $pt))
    | .enabledPlugins = $ep)' "$L/settings.json" "$REF/settings.json" > "$L/settings.json.new"
mv "$L/settings.json.new" "$L/settings.json"
bash "$ROOT/scripts/render-user-hooks.sh" --write

if [ -n "$DO_PLUGINS" ]; then
  echo "4. plugins ($PLUGINS)"
  command -v claude >/dev/null 2>&1 || die "claude CLI not on PATH (log in with a login shell: bash -lc)"
  claude plugin marketplace list 2>/dev/null | grep -q "$MARKET" || claude plugin marketplace add anthropics/claude-plugins-official
  for p in $PLUGINS; do claude plugin install "$p@$MARKET"; done
fi

echo "done. Check: bash $ROOT/scripts/verify-user-level-drift.sh (on Linux it compares the Linux-rendered CLAUDE.md and autoMode.environment)"
