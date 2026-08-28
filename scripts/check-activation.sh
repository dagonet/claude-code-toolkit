#!/usr/bin/env bash
# Answer "are the toolkit's enforcement hooks actually ON in this project, and are
# they firing?" for a consuming repo.
#
# Why this exists: v1.1 shipped the agent-liveness hooks to templates/, but a
# template is a source, not a shipment. Determining whether one project had them
# active — and whether they had ever run — took a multi-hour transcript
# investigation. This script answers it in one command.
#
# Usage: bash scripts/check-activation.sh [path-to-project]   (default: cwd)

set -u

PROJ="${1:-$(pwd)}"
PROJ=$(printf '%s' "$PROJ" | tr '\\' '/')
SETTINGS="$PROJ/.claude/settings.json"
LOG="$PROJ/.claude/liveness.log"

RED=""; GRN=""; YLW=""; RST=""
if [ -t 1 ]; then RED=$(printf '\033[31m'); GRN=$(printf '\033[32m'); YLW=$(printf '\033[33m'); RST=$(printf '\033[0m'); fi
yes_() { printf '  %sOK%s   %s\n' "$GRN" "$RST" "$1"; }
no_()  { printf '  %sNO%s   %s\n' "$RED" "$RST" "$1"; }
warn_(){ printf '  %s!!%s   %s\n' "$YLW" "$RST" "$1"; }

printf 'Activation report for: %s\n\n' "$PROJ"

if [ ! -d "$PROJ" ]; then
  no_ "directory does not exist"
  exit 1
fi

# --- 1. settings.json bindings ---------------------------------------------
printf 'settings.json bindings\n'
if [ ! -f "$SETTINGS" ]; then
  no_ ".claude/settings.json missing — no hooks are bound. Run /sync-template."
else
  if command -v node >/dev/null 2>&1; then
    EVENTS=$(node -e 'try{const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(Object.keys(j.hooks||{}).join(" "))}catch(e){console.log("PARSE-ERROR")}' "$SETTINGS" 2>/dev/null)
    case "$EVENTS" in
      PARSE-ERROR|"") no_ "settings.json is not valid JSON — every hook is offline" ;;
      *)              yes_ "valid JSON; hook events: $EVENTS" ;;
    esac
  fi
  for pair in \
    "agent-budget-warn.sh:tool-call budget" \
    "enforce-delegation.sh:delegation guard" \
    "enforce-agent-contract.sh:agent contract stop-gate" \
    "pre-commit-test.sh:pre-commit test gate" \
    "no-push-main.sh:push-to-main guard" \
    "read-size-gate.sh:Read size gate" \
    "gate-before-merge.sh:merge gate" \
    "retro-ledger.sh:subagent-failure ledger" \
    "retro-brief.sh:session-start retro brief"
  do
    key=${pair%%:*}; label=${pair#*:}
    if grep -q -- "$key" "$SETTINGS" 2>/dev/null; then yes_ "$label ($key)"
    else no_ "$label ($key) NOT bound"; fi
  done
fi

# --- 2. hook scripts on disk ------------------------------------------------
printf '\nhook scripts present\n'
MISSING=0
for h in agent-budget-warn.sh enforce-delegation.sh \
         enforce-agent-contract.sh no-push-main.sh read-size-gate.sh \
         tier-before-coder.sh require-skills-block.sh run-gate.sh \
         gate-before-merge.sh pre-commit-test.sh \
         retro-ledger.sh retro-brief.sh
do
  if [ -s "$PROJ/hooks/$h" ]; then yes_ "hooks/$h"
  else no_ "hooks/$h missing or empty"; MISSING=$((MISSING+1)); fi
done
[ "$MISSING" -gt 0 ] && warn_ "$MISSING script(s) missing — run /sync-template in this project"

# --- 3. kill switches -------------------------------------------------------
printf '\nkill switches\n'
for k in liveness-off delegation-off; do
  if [ -f "$PROJ/.claude/$k" ]; then warn_ ".claude/$k PRESENT — that enforcement is disabled"
  else yes_ ".claude/$k absent (enforcement enabled)"; fi
done

# --- 3b. project MCP wiring -------------------------------------------------
# Claude Code reads project-scope servers ONLY from <project-root>/.mcp.json.
# Setup scripts before 2026-07-29 wrote <project>/.claude/.mcp.json, which is
# never loaded — so a project can look configured and have zero servers active.
printf '\nproject MCP wiring\n'
ROOT_MCP="$PROJ/.mcp.json"
LEGACY_MCP="$PROJ/.claude/.mcp.json"
srv() { # list server names from an MCP json
  [ -f "$1" ] || return 0
  if command -v node >/dev/null 2>&1; then
    node -e 'try{const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(Object.keys(j.mcpServers||{}).join(", "))}catch(e){console.log("(unparseable)")}' "$1" 2>/dev/null
  fi
}
if [ -f "$ROOT_MCP" ]; then yes_ ".mcp.json at repo root — servers: $(srv "$ROOT_MCP")"
else warn_ "no .mcp.json at repo root (fine if this variant needs no project servers)"; fi

if [ -f "$LEGACY_MCP" ]; then
  no_ ".claude/.mcp.json present — THIS PATH IS NEVER READ. Servers: $(srv "$LEGACY_MCP")"
  if [ -f "$ROOT_MCP" ]; then
    warn_ "  merge any missing entries into .mcp.json, then delete the .claude/ copy"
  else
    warn_ "  move it: mv .claude/.mcp.json .mcp.json"
  fi
else
  yes_ "no stale .claude/.mcp.json"
fi

# --- 4. evidence of firing --------------------------------------------------
printf '\nevidence of firing\n'
if [ -f "$LOG" ]; then
  n=$(grep -c . "$LOG" 2>/dev/null || echo 0)
  b=$(grep -c 'action=block' "$LOG" 2>/dev/null || echo 0)
  w=$(grep -c 'action=warn'  "$LOG" 2>/dev/null || echo 0)
  yes_ ".claude/liveness.log: $n events ($b block, $w warn)"
  printf '\n  last 20 events:\n'
  tail -20 "$LOG" 2>/dev/null | sed 's/^/    /'
else
  warn_ ".claude/liveness.log absent — hooks have not blocked or warned yet (or predate v1.2)"
fi

# Ledger dirs are written on every run, so they prove execution even with no
# threshold events. They live in TMPDIR, keyed by session id.
printf '\n  ledger dirs (written on every hook run):\n'
found=0
for base in "${TMPDIR:-}" /tmp; do
  [ -z "$base" ] && continue
  for d in claude-agent-budget; do
    if [ -d "$base/$d" ]; then
      c=$(find "$base/$d" -type f 2>/dev/null | wc -l | tr -d ' ')
      printf '    %s: %s files\n' "$base/$d" "$c"
      found=1
    fi
  done
done
[ "$found" = "0" ] && printf '    none found — the hooks have never executed on this machine\n'

printf '\nIf anything above says NO: run /sync-template in this project, which\n'
printf 'installs both the hooks/ scripts and the .claude/settings.json bindings.\n'
