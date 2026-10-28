#!/usr/bin/env bash
# cct plugin session hook (v5.0 spec §3.3). Two registrations, one script:
#   SessionStart (no argument): marks this session as having the plugin loaded.
#   SessionEnd ("end"): removes this session's marker, so a --resume/--continue WITHOUT the plugin
#     (same session id) does not find a stale marker and make model-floor step aside for a router that is not there.
# The project's inline PreToolUse guard refuses every tool when the marker is missing.
# SessionStart runs on every source (startup, resume, clear, compact). Never blocks: always exits 0.
case "${1:-}" in ''|end) ;; *) exit 0 ;; esac   # any other argument does nothing: a typo can never re-create the marker at SessionEnd (check 74 pins the registrations)
# v5.2.1: bash builtins only up to the rm: SessionEnd hooks share a 1.5 s budget (raised by the 5 s `timeout` in
# hooks.json), and every program started here costs a spawn, seconds each on a loaded machine. $UID == `id -u`.
IFS= read -r -d '' j || :
sid=; re='"session_id" *: *"([^"]*)"'; [[ $j =~ $re ]] && sid=${BASH_REMATCH[1]}
case $sid in ''|*[!A-Za-z0-9-]*) exit 0 ;; esac
d="${TMPDIR:-/tmp}/cct-$UID"
if [ "${1:-}" = end ]; then rm -f "$d/$sid" 2>/dev/null; exit 0; fi
mkdir -p "$d" 2>/dev/null
# A dir this user does not own is not a marker dir (the guard and am_plugin_loaded refuse it too): write nothing.
# Git Bash/Cygwin skip the -O test: their /tmp is per-user, and -O there risks a Windows-wide lockout.
case $(uname -s) in MINGW*|MSYS*|CYGWIN*) ;; *) [ -O "$d" ] || exit 0 ;; esac
chmod 700 "$d" 2>/dev/null
: > "$d/$sid" 2>/dev/null
find "$d" -type f -mtime +30 -delete 2>/dev/null
exit 0
