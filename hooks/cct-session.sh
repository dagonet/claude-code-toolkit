#!/usr/bin/env bash
# cct plugin session hook (v5.0 spec §3.3). Two registrations, one script:
#   SessionStart (no argument): marks this session as having the plugin loaded.
#   SessionEnd ("end"): removes this session's marker, so a --resume/--continue WITHOUT the plugin
#     (same session id) does not find a stale marker and make model-floor step aside for a router that is not there.
# The project's inline PreToolUse guard refuses every tool when the marker is missing.
# SessionStart runs on every source (startup, resume, clear, compact). Never blocks: always exits 0.
case "${1:-}" in ''|end) ;; *) exit 0 ;; esac   # any other argument does nothing: a typo can never re-create the marker at SessionEnd (check 74 pins the registrations)
sid=$(cat | grep -o '"session_id" *: *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
case $sid in ''|*[!A-Za-z0-9-]*) exit 0 ;; esac
d="${TMPDIR:-/tmp}/cct-$(id -u)"
if [ "${1:-}" = end ]; then rm -f "$d/$sid" 2>/dev/null; exit 0; fi
mkdir -p "$d" 2>/dev/null && chmod 700 "$d" 2>/dev/null
: > "$d/$sid" 2>/dev/null
find "$d" -type f -mtime +7 -delete 2>/dev/null
exit 0
