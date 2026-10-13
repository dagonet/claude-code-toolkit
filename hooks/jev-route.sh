#!/usr/bin/env bash
# cct plugin: Jev routing (PreToolUse Agent). Active only when <git common dir>/jev/config.json says route:true.
# Steps aside for a v4 registration still in .claude/settings.local.json, so routing never runs twice.
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/agent-model.sh"
root="${CLAUDE_PROJECT_DIR:-.}"
am_jev_routing "$root" || exit 0
l=""; [ -r "$root/.claude/settings.local.json" ] && IFS= read -r -d '' l < "$root/.claude/settings.local.json"
case $l in *'skills/jev/jev_route.py'*) exit 0 ;; esac
r="$here/../skills/jev/jev_route.py"
[ -f "$r" ] || exit 0
exec python3 "$r"
