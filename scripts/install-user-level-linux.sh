#!/usr/bin/env bash
# scripts/install-user-level-linux.sh -- install the user-level setup (~/.claude) on a Linux host
# from this checkout. Since v5.0 the agents, skills, output style and hooks come from the cct
# plugin; the user level is only CLAUDE.md and settings.json.
#
# Never touches ~/.claude.json (MCP servers are registered separately with `claude mcp add`).
# Every file it overwrites is backed up first as <file>.bak-<UTC>. Re-running it is safe.
# A failure in steps 1-3 restores settings.json byte for byte (the plugin CLI edits it).
#
# The order is safety-critical: the plugin is installed and checked BEFORE anything is removed,
# so a failed install (network, a bad tag) leaves the old user-level copies in place and a NEW
# session never has no hooks, agents or skills. Sessions already running lose the toolkit hooks
# when step 3 rewrites settings.json (settings hot-reload, plugins load at session start): restart
# them.
#
#   1. plugins        cct@dagonet (marketplace: $CCT_MARKETPLACE, default this release's tag on
#                     GitHub), then superpowers, skill-creator, frontend-design from
#                     claude-plugins-official. Runs `plugin update` after `plugin install` (install
#                     does not upgrade). Stops non-zero unless `claude plugin list --json` shows
#                     cct@dagonet enabled at this checkout's VERSION.
#   2. CLAUDE.md      the reference, with its Windows "Platform" section replaced by
#                     scripts/linux/CLAUDE-platform-linux.md and G:/git/ paths written as ~/git/
#   3. settings.json  the existing file with the reference merged in, minus the Windows-only entries
#                     (CLAUDE_CODE_SHELL, CLAUDE_CODE_USE_POWERSHELL_TOOL, windows-mcp).
#                     permissions.allow/deny/ask: the union of both. Every other key keeps the user's
#                     value; the reference only adds missing keys. The toolkit owns outputStyle,
#                     enabledPlugins["cct@dagonet"], autoMode.environment and the hooks: hook entries
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

plugins_started=""   # set when step 1 starts: the CLI then edits settings.json, so a failure restores the backup
die() {
  echo "install-user-level-linux: $*" >&2
  if [ -n "$plugins_started" ]; then
    if [ -e "$L/settings.json.bak-$TS" ]; then cp -p "$L/settings.json.bak-$TS" "$L/settings.json"; else rm -f "$L/settings.json"; fi
    echo "install-user-level-linux: settings.json restored to its state before this run" >&2
  fi
  exit 1
}
[ "$(uname -s)" = Linux ] || die "Linux only (on Windows follow docs/plugin-migration-windows.md)"
for t in bash git jq claude; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t (claude: log in with a login shell, bash -lc)"; done
[ -f "$REF/CLAUDE.md" ] && [ -f "$REF/settings.json" ] && [ -f "$PLAT" ] && [ -f "$LEFTOVERS" ] && [ -f "$ROOT/VERSION" ] \
  || die "run from a claude-code-toolkit checkout"
CCT_SRC=${CCT_MARKETPLACE:-dagonet/claude-code-toolkit#v$(head -1 "$ROOT/VERSION")}
backup() { [ -e "$1" ] && cp -p "$1" "$1.bak-$TS" && echo "  backup: $1.bak-$TS" || true; }

mkdir -p "$L"

# `claude plugin install` switches a plugin on in settings.json even when the user had it off:
# back settings.json up and remember its enabledPlugins BEFORE the CLI touches it (step 3 puts them
# back; a failure in step 1 restores the backup byte for byte)
backup "$L/settings.json"
pre_ep='{}'
[ -s "$L/settings.json" ] && pre_ep=$(jq -c '.enabledPlugins // {}' "$L/settings.json")
plugins_started=1

echo "1. plugins (cct@dagonet from $CCT_SRC; $PLUGINS)"
claude plugin marketplace add "$CCT_SRC" || die "cannot add the cct marketplace $CCT_SRC: nothing was removed"
claude plugin install cct@dagonet || die "cannot install cct@dagonet: nothing was removed"
# install does not upgrade an installed plugin; update is rc 0 when it is already the latest
claude plugin update cct@dagonet || die "cannot update cct@dagonet: nothing was removed"
claude plugin marketplace list 2>/dev/null | grep -q "$MARKET" || claude plugin marketplace add anthropics/claude-plugins-official || die "cannot add $MARKET: nothing was removed"
for p in $PLUGINS; do claude plugin install "$p@$MARKET" || die "cannot install $p@$MARKET: nothing was removed"; done
want_ver=$(head -1 "$ROOT/VERSION" | tr -d '\r')
claude plugin list --json 2>/dev/null | jq -e --arg v "$want_ver" 'any(.[]; .id == "cct@dagonet" and .scope == "user" and .enabled == true and .version == $v)' >/dev/null \
  || die "claude plugin list does not show cct@dagonet (user scope) enabled at $want_ver: nothing was removed, the v4 user-level copies stay"

echo "2. CLAUDE.md (Linux platform section)"
backup "$L/CLAUDE.md"
linux_render_claude_md "$REF/CLAUDE.md" "$PLAT" > "$L/CLAUDE.md.new"
chk=$(linux_check_rendered "$L/CLAUDE.md.new") || { rm -f "$L/CLAUDE.md.new"; die "$chk"; }
mv "$L/CLAUDE.md.new" "$L/CLAUDE.md"

echo "3. settings.json (reference minus Windows-only entries; v4 toolkit hook entries dropped)"
[ -s "$L/settings.json" ] || echo '{}' > "$L/settings.json"
plugins_json=$(for p in $PLUGINS; do printf '"%s@%s":true\n' "$p" "$MARKET"; done | paste -sd, -)
# the toolkit hook names: the leftovers' hooks/<name>.sh lines outside lib/
own_re="(/\\.claude/hooks|@HOOKS@)/($(sed -n 's#^hooks/\([A-Za-z0-9_-]*\)\.sh$#\1#p' "$LEFTOVERS" | paste -sd'|' -))\\.sh([^A-Za-z0-9_.-]|\$)"
# Merge rules (the user's file is theirs): permissions.allow/deny/ask = union of live and reference;
# every other key keeps the LIVE value and the reference only adds missing keys; the toolkit owns
# outputStyle, enabledPlugins["cct@dagonet"], autoMode.environment and the hooks (its entries replaced,
# every other entry kept).
jq -s --arg pf "$LINUX_PATH_FROM" --arg pt "$LINUX_PATH_TO" --argjson ep "{$plugins_json}" --argjson pre "$pre_ep" --arg own "$own_re" '
  def disp: ([(.command // "") | tostring] + ((.args // []) | map(tostring)) | join(" "));
  def union($a; $b): reduce (($a // []) + ($b // []))[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
  (.[1].hooks // {}) as $rh
  | .[0] as $l
  | ($l.hooks // {}) as $lh
  | ($lh | with_entries(.key as $ev | [($rh[$ev] // [])[].hooks[] | disp] as $rd
      | .value |= (map(.hooks |= map(disp as $d | select((($d | test($own)) or any($rd[]; . == $d)) | not)))
                   | map(select(.hooks | length > 0))))) as $kept
  | (reduce ($rh | keys_unsorted[]) as $ev ($kept; .[$ev] = $rh[$ev] + (.[$ev] // []))
     | with_entries(select(.value | length > 0))) as $hooks
  | (.[1]
    | del(.hooks)
    | del(.env.CLAUDE_CODE_SHELL, .env.CLAUDE_CODE_USE_POWERSHELL_TOOL)
    | .permissions.allow |= map(select(test("windows-mcp") | not))
    | .autoMode.environment |= map(gsub($pf; $pt))
    | .enabledPlugins = $ep) as $r
  | ($r * $l)
  | reduce ("allow", "deny", "ask") as $k (.; .permissions[$k] = union($l.permissions[$k]; $r.permissions[$k]))
  | if $r.outputStyle then .outputStyle = $r.outputStyle else . end
  | .enabledPlugins += $pre
  | .enabledPlugins["cct@dagonet"] = true
  | .autoMode.environment = $r.autoMode.environment
  | .hooks = $hooks' "$L/settings.json" "$REF/settings.json" > "$L/settings.json.new" \
  || { rm -f "$L/settings.json.new"; die "the settings.json merge failed"; }
mv "$L/settings.json.new" "$L/settings.json"
plugins_started=""

echo "4. v4 user-level leftovers (moved to $L/v4-leftovers.bak-$TS/)"
while IFS= read -r rel; do
  [ -n "$rel" ] && [ -e "$L/$rel" ] || continue
  mkdir -p "$(dirname "$L/v4-leftovers.bak-$TS/$rel")"
  mv "$L/$rel" "$L/v4-leftovers.bak-$TS/$rel"
  echo "  moved: $rel"
done < "$LEFTOVERS"
rmdir "$L/hooks/lib" "$L/hooks" 2>/dev/null || true

echo "done. Restart every running Claude session (they lost the toolkit hooks; plugins load at session start)."
echo "In each checkout where Jev is on, run /cct:jev off, then /cct:jev on."
echo "Check: bash $ROOT/scripts/verify-user-level-drift.sh --worktree (0 drift = rendered CLAUDE.md, cct@dagonet at VERSION and enabled, no leftover, no stale hook registration, autoMode.environment as the reference)"
