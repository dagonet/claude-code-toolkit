#!/usr/bin/env bash
# cct-jev plugin session hook (slim-core design section 10 item 2). Two registrations, one script:
#   SessionStart (no argument): marks this session as having the cct-jev plugin loaded.
#   SessionEnd ("end"): removes this session's marker, so a --resume/--continue WITHOUT the plugin (same session id)
#     does not find a stale marker and make model-floor step aside for a router that is not there.
# The marker lives in its OWN folder, ${TMPDIR:-/tmp}/cct-jev-<uid>/, never in cct-<uid>/: the project template's inline guard reads
# cct-<uid>/ only, so this marker can never satisfy it (and cct's cct-session marker can never switch the floor off).
# model-floor (am_jev_routing in hooks/lib/agent-model.sh) steps aside only when the clone's Jev switch says route:true AND
# this file exists for the session.
# Never blocks: always exits 0. Same shape as hooks/cct-session.sh (builtins only up to the rm; SessionEnd has a short budget).
case "${1:-}" in ''|end) ;; *) exit 0 ;; esac   # any other argument does nothing: a typo can never re-create the marker at SessionEnd (check 74 pins the registrations)
IFS= read -r -d '' j || :
sid=; re='"session_id" *: *"([^"]*)"'; [[ $j =~ $re ]] && sid=${BASH_REMATCH[1]}
case $sid in ''|*[!A-Za-z0-9-]*) exit 0 ;; esac
d="${TMPDIR:-/tmp}/cct-jev-$UID"
if [ "${1:-}" = end ]; then rm -f "$d/$sid" 2>/dev/null; exit 0; fi
mkdir -p "$d" 2>/dev/null
# A dir this user does not own is not a marker dir (am_jev_loaded refuses it too): write nothing.
# Git Bash/Cygwin skip the -O test: their /tmp is per-user, and -O there risks a Windows-wide lockout.
case $(uname -s) in MINGW*|MSYS*|CYGWIN*) ;; *) [ -O "$d" ] || exit 0 ;; esac
chmod 700 "$d" 2>/dev/null
: > "$d/$sid" 2>/dev/null
find "$d" -type f -mtime +30 -delete 2>/dev/null
exit 0
