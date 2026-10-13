#!/usr/bin/env bash
# cct plugin: the Jev session notice (SessionStart; stdout reaches the new session's context, user ruling U-1).
# Active only when <git common dir>/jev/config.json says route:true; silent for a v4 registration, which prints its own.
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/agent-model.sh"
root="${CLAUDE_PROJECT_DIR:-.}"
am_jev_routing "$root" || exit 0
l=""; [ -r "$root/.claude/settings.local.json" ] && IFS= read -r -d '' l < "$root/.claude/settings.local.json"
case $l in *'skills/jev/jev_route.py'*) exit 0 ;; esac
echo "Jev routing is ON in this repo (/cct:jev on): omit model on Agent spawns -- Jev picks one per launch (user ruling U-1; an explicit model is never changed). /cct:jev off restores naming it."
