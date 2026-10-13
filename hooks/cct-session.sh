#!/usr/bin/env bash
# cct plugin SessionStart hook (v5.0 spec §3.3): marks this session as having the plugin loaded.
# The project's inline PreToolUse guard refuses every tool when this marker is missing.
# Runs on every source (startup, resume, clear, compact). Never blocks: always exits 0.
sid=$(cat | grep -o '"session_id" *: *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
case $sid in ''|*[!A-Za-z0-9-]*) exit 0 ;; esac
d="${TMPDIR:-/tmp}/cct-$(id -u)"
mkdir -p "$d" 2>/dev/null && chmod 700 "$d" 2>/dev/null
: > "$d/$sid" 2>/dev/null
find "$d" -type f -mtime +7 -delete 2>/dev/null
exit 0
