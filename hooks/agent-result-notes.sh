#!/usr/bin/env bash
# agent-result-notes.sh -- PostToolUse(Agent): one advisory note beside a returned Agent result.
# Model ladder, v7.0.0: when a pipeline coder's report shows a failure, tell the parent which rung to
# start the same job on next (haiku < sonnet < opus < fable) -- the "Step-up:" note, rule anr_step_up.
#
# Payload (user-level-reference/settings-reference.md, "PostToolUse Agent payload"): the report is
# tool_response.content, an array of text blocks (a plain-string tool_response is accepted too);
# tool_response.status is "async_launched" for a background spawn (no report yet: silent);
# tool_response.resolvedModel is the model that ran.
#
# Failure means, in the report of an agent whose frontmatter carries `pipeline: true`:
#   - a line `- [fail] <n>.` (a contract line; the text "[fail]" inside a sentence is not one), or
#   - a line starting `Gate:` that contains `GATE FAILED` (what hooks/run-gate.sh prints).
# Reviewers, tester and architect also carry `pipeline: true` but get no step-up note (controller
# ruling); Explore, general-purpose and every agent without the key have no pipeline key at all.
#
# ADVISORY: class project, polarity open, no onFailure, no state file. Any doubt -> exit 0, no output.
# STDOUT is the whole contract: exactly one
#   {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<note>"}}
# or nothing. Two rules share the payload parse and each prints its note text; the notes are joined by one space.
#
# Backlog discipline, v6.3: rule anr_followups -- a reviewer/tester report (cct:code-reviewer, code-reviewer,
# cct:tester, tester) holding a `Follow-ups:` line followed by at least one `- ` line gets the note
# "Add these follow-ups to the backlog as untriaged items." The item text is never quoted. Foreground spawns
# only: a background spawn fires at launch with no report. The rules are disjoint by type (step-up excludes
# code-reviewer and tester), so the join is not reachable today.
lib="$(dirname "$0")/lib/json.sh"
[ -f "$lib" ] || exit 0
# shellcheck source=lib/json.sh
. "$lib"
amlib="$(dirname "$0")/lib/agent-model.sh"
[ -f "$amlib" ] || exit 0
# shellcheck source=lib/agent-model.sh
. "$amlib"

# anr_text -- the report text of $ANR_JSON on stdout: every text block of tool_response.content,
# newline-joined (or the plain string). Empty when there is none. The payload goes in on stdin.
anr_text() {
  case "$JSON_PARSER" in
    node)
      printf '%s' "$ANR_JSON" | node -e '
        var p = JSON.parse(require("fs").readFileSync(0, "utf8")), r = p.tool_response, t = "";
        if (typeof r === "string") t = r;
        else if (r && typeof r === "object") {
          var c = r.content;
          if (typeof c === "string") t = c;
          else if (Array.isArray(c)) t = c.map(function (b) { return b && b.type === "text" && typeof b.text === "string" ? b.text : ""; }).join("\n");
        }
        process.stdout.write(t);
      ' 2>/dev/null ;;
    python3)
      printf '%s' "$ANR_JSON" | python3 -c '
import json, sys
p = json.loads(sys.stdin.buffer.read().decode("utf-8-sig", "replace"))
r = p.get("tool_response") if isinstance(p, dict) else None
t = ""
if isinstance(r, str):
    t = r
elif isinstance(r, dict):
    c = r.get("content")
    if isinstance(c, str):
        t = c
    elif isinstance(c, list):
        t = "\n".join(b["text"] for b in c if isinstance(b, dict) and b.get("type") == "text" and isinstance(b.get("text"), str))
sys.stdout.buffer.write(t.encode("utf-8", "replace"))
' 2>/dev/null ;;
    jq)
      printf '%s' "$ANR_JSON" | jq -j '
        .tool_response
        | if type == "string" then .
          elif type == "object" then
            (.content | if type == "string" then .
                        elif type == "array" then [.[] | select(type == "object" and .type == "text") | .text | strings] | join("\n")
                        else "" end)
          else "" end
      ' 2>/dev/null ;;
  esac
}

# anr_step_up -- prints the note JSON or nothing. Reads ANR_TYPE, ANR_MODEL (the first non-empty of
# resolvedModel and tool_input.model, else empty), ANR_CWD and, through anr_text, the payload.
anr_step_up() {
  local t=${ANR_TYPE#cct:} file fam next why txt note
  case "$t" in architect|code-reviewer|tester) return 0 ;; esac
  am_file=""
  am_resolve "$ANR_TYPE" "$ANR_CWD"
  case "$AM_KIND" in own|floor) ;; *) return 0 ;; esac
  file=$am_file
  [ -f "$file" ] && [ "$(am_fm "$file" pipeline)" = true ] || return 0
  # which model ran: resolvedModel, else the spawn's model, else what its agent file resolves to
  fam=${ANR_MODEL:-$AM_MODEL}
  case "$fam" in
    *haiku*)  fam=haiku;  next=sonnet ;;
    *sonnet*) fam=sonnet; next=opus ;;
    *opus*)   fam=opus;   next=fable ;;
    *fable*)  fam=fable;  next="" ;;
    *) return 0 ;;
  esac
  txt=$(anr_text | tr -d '\r')
  [ -n "$txt" ] || return 0
  why=$(printf '%s\n' "$txt" | grep -m1 -E '^[[:space:]]*- \[fail\] [0-9]+\.' | sed -E 's/^[[:space:]]*- \[fail\] ([0-9]+)\..*/brief item \1 failed/')
  if [ -z "$why" ]; then
    printf '%s\n' "$txt" | grep -qE '^[[:space:]]*Gate:.*GATE FAILED' && why="gate failed"
  fi
  [ -n "$why" ] || return 0
  if [ -n "$next" ]; then note="Step-up: $ANR_TYPE failed on $fam ($why). Start the same job again on $next."
  else note="Step-up: $ANR_TYPE failed on $fam ($why). Report this to the user instead of retrying."; fi
  printf '%s' "$note"
}

# anr_followups -- prints the note text or nothing. A reviewer or tester report that holds a block
# (a line exactly `Follow-ups:` followed at once by a `- ` line) gets one fixed note; the item text is
# never quoted. The types come from tool_input.subagent_type, with or without the `cct:` prefix.
anr_followups() {
  local txt
  case "$ANR_TYPE" in cct:code-reviewer|code-reviewer|cct:tester|tester) ;; *) return 0 ;; esac
  txt=$(anr_text | tr -d '\r')
  [ -n "$txt" ] || return 0
  printf '%s\n' "$txt" | awk '/^Follow-ups:$/ { h = 1; next } h && /^- / { f = 1; exit } { h = 0 } END { exit !f }' || return 0
  printf '%s' "Add these follow-ups to the backlog as untriaged items."
}

ANR_JSON=$(cat)
case "$ANR_JSON" in "$JSON_BOM"*) ANR_JSON=${ANR_JSON#"$JSON_BOM"} ;; esac
json_fields "$ANR_JSON" tool_name tool_input.subagent_type tool_response.status tool_response.resolvedModel tool_input.model cwd || exit 0
[ "${JF[0]}" = Agent ] || exit 0
[ "${JF[2]}" = async_launched ] && exit 0
ANR_TYPE=${JF[1]}
[ -n "$ANR_TYPE" ] || exit 0
ANR_MODEL=${JF[3]:-${JF[4]}}
ANR_CWD=${JF[5]:-.}
# One JSON object per call: each rule prints its note text; the notes are joined by one space.
ANR_NOTE=$(anr_step_up)
ANR_FU=$(anr_followups)
[ -n "$ANR_FU" ] && ANR_NOTE="${ANR_NOTE:+$ANR_NOTE }$ANR_FU"
[ -n "$ANR_NOTE" ] && printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$ANR_NOTE"
exit 0
