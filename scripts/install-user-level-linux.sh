#!/usr/bin/env bash
# scripts/install-user-level-linux.sh -- install the user-level setup (~/.claude) on a Linux host
# from this checkout. Since v5.0 the agents, skills, output style and hooks come from the cct
# plugin; the user level is only CLAUDE.md and settings.json.
#
# Never touches ~/.claude.json (MCP servers are registered separately with `claude mcp add`).
# Every file it overwrites is backed up first as <file>.bak-<UTC>. Re-running it is safe.
#
# The order is safety-critical: the plugin is installed and checked BEFORE anything is removed,
# so a failed install (network, a bad tag) leaves the old user-level copies in place and the
# machine never has no hooks, agents or skills.
#
#   1. CLAUDE.md      the reference, with its Windows "Platform" section replaced by
#                     scripts/linux/CLAUDE-platform-linux.md and G:/git/ paths written as ~/git/
#   2. plugins        cct@dagonet (marketplace: $CCT_MARKETPLACE, default this release's tag on
#                     GitHub), then superpowers, skill-creator, frontend-design from
#                     claude-plugins-official. Stops non-zero unless `claude plugin list` shows
#                     cct@dagonet.
#   3. settings.json  the reference merged over the existing file, minus the Windows-only entries
#                     (CLAUDE_CODE_SHELL, CLAUDE_CODE_USE_POWERSHELL_TOOL, windows-mcp); hook entries
#                     naming /.claude/hooks/<toolkit hook>.sh (v4.x registrations) are dropped,
#                     every other hook is kept, the reference's hooks are added once
#   4. leftovers      every path in scripts/lib/v4-user-leftovers.txt that exists is moved to
#                     ~/.claude/v4-leftovers.bak-<UTC>/ (outside agents/ and skills/, where a
#                     backup copy would still load)
#
# Usage: bash scripts/install-user-level-linux.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REF=$ROOT/user-level-reference
PLAT=$ROOT/scripts/linux/CLAUDE-platform-linux.md
LEFTOVERS=$ROOT/scripts/lib/v4-user-leftovers.txt
. "$ROOT/scripts/linux/linux-render.sh"   # the Linux rewrites, shared with verify-user-level-drift.sh
L=$HOME/.claude
TS=$(date -u +%Y%m%dT%H%M%SZ)
PLUGINS="superpowers skill-creator frontend-design"
MARKET=claude-plugins-official

die() { echo "install-user-level-linux: $*" >&2; exit 1; }
[ "$(uname -s)" = Linux ] || die "Linux only (on Windows follow docs/plugin-migration-windows.md)"
for t in bash git jq claude; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t (claude: log in with a login shell, bash -lc)"; done
[ -f "$REF/CLAUDE.md" ] && [ -f "$REF/settings.json" ] && [ -f "$PLAT" ] && [ -f "$LEFTOVERS" ] && [ -f "$ROOT/VERSION" ] \
  || die "run from a claude-code-toolkit checkout"
CCT_SRC=${CCT_MARKETPLACE:-dagonet/claude-code-toolkit#v$(head -1 "$ROOT/VERSION")}
backup() { [ -e "$1" ] && cp -p "$1" "$1.bak-$TS" && echo "  backup: $1.bak-$TS" || true; }

mkdir -p "$L"

echo "1. CLAUDE.md (Linux platform section)"
backup "$L/CLAUDE.md"
linux_render_claude_md "$REF/CLAUDE.md" "$PLAT" > "$L/CLAUDE.md.new"
chk=$(linux_check_rendered "$L/CLAUDE.md.new") || die "$chk"
mv "$L/CLAUDE.md.new" "$L/CLAUDE.md"

echo "2. plugins (cct@dagonet from $CCT_SRC; $PLUGINS)"
claude plugin marketplace add "$CCT_SRC" || die "cannot add the cct marketplace $CCT_SRC: nothing was removed"
claude plugin install cct@dagonet || die "cannot install cct@dagonet: nothing was removed"
claude plugin marketplace list 2>/dev/null | grep -q "$MARKET" || claude plugin marketplace add anthropics/claude-plugins-official
for p in $PLUGINS; do claude plugin install "$p@$MARKET"; done
claude plugin list 2>/dev/null | grep -q 'cct@dagonet' \
  || die "claude plugin list does not show cct@dagonet: nothing was removed, the v4 user-level copies stay"

echo "3. settings.json (reference minus Windows-only entries; v4 toolkit hook entries dropped)"
[ -s "$L/settings.json" ] || echo '{}' > "$L/settings.json"
backup "$L/settings.json"
plugins_json=$(for p in $PLUGINS; do printf '"%s@%s":true\n' "$p" "$MARKET"; done | paste -sd, -)
# the toolkit hook names: the leftovers' hooks/<name>.sh lines outside lib/
own_re="/\\.claude/hooks/($(sed -n 's#^hooks/\([A-Za-z0-9_-]*\)\.sh$#\1#p' "$LEFTOVERS" | paste -sd'|' -))\\.sh([^A-Za-z0-9_.-]|\$)"
jq -s --arg pf "$LINUX_PATH_FROM" --arg pt "$LINUX_PATH_TO" --argjson ep "{$plugins_json}" --arg own "$own_re" '
  def disp: ([(.command // "") | tostring] + ((.args // []) | map(tostring)) | join(" "));
  (.[1].hooks // {}) as $rh
  | (.[0].hooks // {}) as $lh
  | ($lh | with_entries(.key as $ev | [($rh[$ev] // [])[].hooks[] | disp] as $rd
      | .value |= (map(.hooks |= map(disp as $d | select((($d | test($own)) or any($rd[]; . == $d)) | not)))
                   | map(select(.hooks | length > 0))))) as $kept
  | (reduce ($rh | keys_unsorted[]) as $ev ($kept; .[$ev] = $rh[$ev] + (.[$ev] // []))
     | with_entries(select(.value | length > 0))) as $hooks
  | .[0] * (.[1]
    | del(.hooks)
    | del(.env.CLAUDE_CODE_SHELL, .env.CLAUDE_CODE_USE_POWERSHELL_TOOL)
    | .permissions.allow |= map(select(test("windows-mcp") | not))
    | .autoMode.environment |= map(gsub($pf; $pt))
    | .enabledPlugins = $ep)
  | .hooks = $hooks' "$L/settings.json" "$REF/settings.json" > "$L/settings.json.new"
mv "$L/settings.json.new" "$L/settings.json"

echo "4. v4 user-level leftovers (moved to $L/v4-leftovers.bak-$TS/)"
while IFS= read -r rel; do
  [ -n "$rel" ] && [ -e "$L/$rel" ] || continue
  mkdir -p "$(dirname "$L/v4-leftovers.bak-$TS/$rel")"
  mv "$L/$rel" "$L/v4-leftovers.bak-$TS/$rel"
  echo "  moved: $rel"
done < "$LEFTOVERS"
rmdir "$L/hooks/lib" "$L/hooks" 2>/dev/null || true

echo "done. Check: bash $ROOT/scripts/verify-user-level-drift.sh --worktree (0 drift = rendered CLAUDE.md, cct@dagonet at VERSION, no leftover)"
