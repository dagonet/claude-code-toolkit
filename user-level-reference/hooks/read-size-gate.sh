#!/usr/bin/env bash
# PreToolUse hook: cap unbounded Read calls instead of blocking them.
#
# Matcher: Read
# Intent: Read results averaged 6 K chars with no `limit` on 5,032 of 10,336
# measured calls (docs/plans/2026-04-14-context-baseline.md). Blocking the call
# cost a round trip and taught the caller nothing; rewriting it is invisible and
# always makes progress.
#
# Decision rule (offset defaults to 0):
#   tool_input.limit present         -> silent pass (the caller bounded it)
#   file_lines - offset <= THRESHOLD -> silent pass
#   otherwise -> stdout a hookSpecificOutput with permissionDecision "allow",
#     updatedInput = the ORIGINAL tool_input plus limit=THRESHOLD, and an
#     additionalContext naming the offset to pass next. Exit 0.
#
# updatedInput REPLACES the whole input object, so tool_input is copied
# wholesale (Object.assign) — `pages` and any field a future Claude Code
# version adds survive untouched.
#
# Binary-ish extensions (images, PDFs, notebooks) are skipped: their Read
# result is not line-addressable and a limit would corrupt it.
#
# The hook never exits non-zero. Missing files, unreadable paths and malformed
# payloads are silent passes; Read will produce its own error. Log append to
# ~/.claude/state/read-size-gate.log is best-effort and never masks the
# decision.

THRESHOLD=500
LOG_FILE="$HOME/.claude/state/read-size-gate.log"

TOOL_INPUT=$(cat)

# Extract tool_name, file_path, offset, limit from JSON stdin.
# Matches tier-before-coder.sh style (node -e inline parse).
TOOL_NAME=$(node -e "try{console.log(JSON.parse(process.argv[1]).tool_name||'')}catch(e){}" "$TOOL_INPUT" 2>/dev/null || echo '')
if [ "$TOOL_NAME" != "Read" ]; then
  exit 0
fi

FILE_PATH=$(node -e "try{console.log(JSON.parse(process.argv[1]).tool_input?.file_path||'')}catch(e){}" "$TOOL_INPUT" 2>/dev/null || echo '')
OFFSET=$(node -e "try{var v=JSON.parse(process.argv[1]).tool_input?.offset;console.log(v==null?'':v)}catch(e){}" "$TOOL_INPUT" 2>/dev/null || echo '')
LIMIT=$(node -e "try{var v=JSON.parse(process.argv[1]).tool_input?.limit;console.log(v==null?'':v)}catch(e){}" "$TOOL_INPUT" 2>/dev/null || echo '')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# The caller already bounded the read — nothing to do.
if [ -n "$LIMIT" ]; then
  exit 0
fi

# Not line-addressable: Read renders these as images, pages or notebook cells.
case "$(printf '%s' "$FILE_PATH" | tr '[:upper:]' '[:lower:]')" in
  *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.ipynb) exit 0 ;;
esac

# Normalize to absolute path. realpath is present in Git Bash (GNU coreutils)
# and on Linux/macOS. If the file doesn't exist yet, let Read handle it.
ABS_PATH=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
if [ ! -f "$ABS_PATH" ] || [ ! -r "$ABS_PATH" ]; then
  exit 0
fi

FILE_LINES=$(wc -l < "$ABS_PATH" 2>/dev/null | tr -d ' ')
if [ -z "$FILE_LINES" ] || ! [ "$FILE_LINES" -ge 0 ] 2>/dev/null; then
  exit 0
fi

# offset defaults to 0. A non-numeric offset is treated as absent rather than
# guessed at. The pre-PR3 script ignored offset entirely, so a Read already
# near EOF was judged by the whole file's length.
if [ -z "$OFFSET" ] || ! [ "$OFFSET" -ge 0 ] 2>/dev/null; then
  OFFSET=0
fi

REMAINING=$((FILE_LINES - OFFSET))
if [ "$REMAINING" -le "$THRESHOLD" ]; then
  exit 0
fi

# Best-effort log append. Failures never mask the decision.
log_cap() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  # Subshell wraps the redirection so both printf stderr and the shell's
  # own "permission denied" from a failed >> open are swallowed.
  ( printf "%s\t%s\t%s\t%s\t%s\n" \
      "$ts" "CAP" "$THRESHOLD" "$FILE_LINES" "$ABS_PATH" \
      >> "$LOG_FILE" ) 2>/dev/null || true
}
log_cap

node -e '
try {
  var payload = JSON.parse(process.argv[1]);
  var input = payload.tool_input || {};
  var lines = Number(process.argv[2]);
  var offset = Number(process.argv[3]);
  var cap = Number(process.argv[4]);
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: Object.assign({}, input, { limit: cap }),
      additionalContext: "Read capped at " + cap + " of " + lines +
        " lines starting at offset " + offset + "; pass offset=" +
        (offset + cap) + " to continue."
    }
  }));
} catch (e) {}
' "$TOOL_INPUT" "$FILE_LINES" "$OFFSET" "$THRESHOLD" 2>/dev/null

exit 0
