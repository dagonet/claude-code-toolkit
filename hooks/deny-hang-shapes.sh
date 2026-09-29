#!/usr/bin/env bash
# deny-hang-shapes.sh -- PreToolUse(Bash): refuse three command shapes that
# hung unattended agents (v4.3.0, spec Part B): a heredoc written into a file,
# a sleep wait loop, and a leading `cd` followed by two or more commands (R-B).
# ADVISORY: a missing lib, no JSON parser, an unreadable payload or any doubt
# lets the call through (exit 0). Honours .claude/git-guard-off.
lib="$(dirname "$0")/lib/json.sh"
[ -f "$lib" ] || exit 0
# shellcheck source=lib/json.sh
. "$lib"
DH_JSON=$(cat)
json_have || exit 0
json_valid "$DH_JSON" || exit 0
DH_CWD=$(json_get "$DH_JSON" cwd)
[ -n "$DH_CWD" ] && [ -f "$DH_CWD/.claude/git-guard-off" ] && exit 0
DH_CMD=$(json_get "$DH_JSON" tool_input.command)
[ -n "$DH_CMD" ] || exit 0
_j=$(printf '%s' "$DH_CMD" | cmd_join_continuations) && [ -n "$_j" ] && DH_CMD="$_j"
dh_refuse() { echo "BLOCKED: deny-hang-shapes: $1" >&2; exit 2; }

# DH_HERE matches a heredoc operator (not a `<<<` here-string) that opens a
# delimiter word. Shapes 2 and 3 read only the text BEFORE the first heredoc
# operator: what follows is data (a commit message, a script body), not commands.
DH_Q="'"
DH_HERE="(^|[^<])<<-?[[:space:]]*[\"$DH_Q]?[A-Za-z_]"

# 1. A heredoc into a file: the FIRST line holds both the << and a file target.
case "$DH_CMD" in
  *'<<'*)
    DH_FIRST=$(printf '%s\n' "$DH_CMD" | head -1)
    if printf '%s' "$DH_FIRST" | grep -Eq "$DH_HERE"; then
      DH_T=$(printf '%s' "$DH_FIRST" | sed -E 's#[0-9]*>&[0-9]+##g; s#>+[[:space:]]*/dev/null##g')
      if printf '%s' "$DH_T" | grep -Eq '(^|[;&|[:space:]])cat[[:space:]][^|;&]*>{1,2}[[:space:]]*[^&[:space:]]' \
         || printf '%s' "$DH_T" | grep -Eq '(^|[;&|[:space:]])tee([[:space:]]+-[a-z]+)*[[:space:]]+[^-|;&[:space:]]'; then
        dh_refuse "a heredoc written into a file can hang an unattended agent -- write files with the Write tool."
      fi
    fi
    ;;
esac

# The command text up to (not including) the first heredoc operator.
DH_HEAD="$DH_CMD"
case "$DH_CMD" in
  *'<<'*)
    DH_HEAD=$(printf '%s\n' "$DH_CMD" | awk -v re="$DH_HERE" '
      match($0, re) { p = RSTART + (substr($0, RSTART, 1) == "<" ? 0 : 1); print substr($0, 1, p - 1); exit }
      { print }')
    ;;
esac

# 2. A wait loop. A word boundary here includes a quote, so `bash -c 'while ...'` counts.
DH_B="(^|[;&|({\"$DH_Q[:space:]])"
case "$DH_HEAD" in
  *sleep*)
    if printf '%s' "$DH_HEAD" | grep -Eq "${DH_B}(while|until)[[:space:]]" \
       && printf '%s' "$DH_HEAD" | grep -Eq "${DH_B}sleep[[:space:]]" \
       && printf '%s' "$DH_HEAD" | grep -Eq "${DH_B}done([;&|)}\"$DH_Q[:space:]]|\$)"; then
      dh_refuse "end your turn instead of waiting in a loop -- you are re-invoked when the background job finishes."
    fi
    ;;
esac

# 3. A leading cd followed by two or more commands (R-B): `cd <dir> && <one
# command>` stays allowed. Commands are counted, not lines or operators: quoted
# strings collapse to one word, a redirect (`> log 2>&1`) is part of its command,
# and a trailing separator or blank line is not a command.
DH_TRIM="${DH_HEAD#"${DH_HEAD%%[![:space:]]*}"}"
case "$DH_TRIM" in
  cd[[:space:]]*)
    DH_SEP=$(printf '\001'); DH_NL2=$(printf '\002')
    DH_N=$(printf '%s' "$DH_TRIM" | tr '\n' "$DH_NL2" \
      | sed -E "s/\"[^\"]*\"|'[^']*'/Q/g; s/\\\\;/ /g; s/&&|\\|\\||;|${DH_NL2}/${DH_SEP}/g" \
      | tr "$DH_SEP" '\n' | grep -c '[^[:space:]]')
    if [ "${DH_N:-0}" -ge 3 ]; then
      dh_refuse "use absolute paths, git -C <dir>, or env -C <dir> <cmd> instead of a leading cd before several commands."
    fi
    ;;
esac
exit 0
