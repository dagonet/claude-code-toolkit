#!/usr/bin/env bash
# PostToolUse hook: truncate oversized Bash/PowerShell output before it lands
# in the transcript, keeping the full text on disk.
#
# Matcher: Bash|PowerShell
#
# Measured payload shape (Claude Code 2.1.250, observed via a temporary logging
# hook on 2026-08-28):
#   { session_id, transcript_path, cwd, prompt_id, permission_mode, agent_id,
#     agent_type, effort:{level}, hook_event_name:"PostToolUse", tool_name,
#     tool_input:{command,...}, tool_use_id, duration_ms,
#     tool_response: { stdout, stderr, interrupted, isImage,
#                      noOutputExpected } }
# `stdout` is the output string field. updatedToolOutput must keep the same
# shape, so the whole tool_response object is copied and only stdout replaced.
#
# Behaviour: stdout <= THRESHOLD chars -> no output, the result is untouched.
# Longer -> the full stdout is written to $TMPDIR/claude-bash-out/, and the
# transcript gets head + a truncation marker naming the log file + tail.
#
# Always exits 0. A PostToolUse hook that fails must never disturb the tool
# result, so every error path is a silent pass-through.

THRESHOLD=12000
KEEP=4000

TOOL_INPUT=$(cat)

OUTDIR="${TMPDIR:-/tmp}/claude-bash-out"
mkdir -p "$OUTDIR" 2>/dev/null || exit 0

node -e '
try {
  var fs = require("fs");
  var path = require("path");
  var payload = JSON.parse(process.argv[1]);
  var outDir = process.argv[2];
  var threshold = Number(process.argv[3]);
  var keep = Number(process.argv[4]);

  var resp = payload.tool_response;
  if (!resp || typeof resp !== "object") process.exit(0);
  var out = resp.stdout;
  if (typeof out !== "string" || out.length <= threshold) process.exit(0);

  var name = (payload.session_id || "nosession") + "-" + Date.now() + ".log";
  var logPath = path.join(outDir, name);
  fs.writeFileSync(logPath, out);

  var dropped = out.length - keep * 2;
  var trimmed = out.slice(0, keep) +
    "\n…[" + dropped + " chars truncated — full output: " + logPath + "]…\n" +
    out.slice(out.length - keep);

  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      updatedToolOutput: Object.assign({}, resp, { stdout: trimmed })
    }
  }));
} catch (e) {}
' "$TOOL_INPUT" "$OUTDIR" "$THRESHOLD" "$KEEP" 2>/dev/null

exit 0
