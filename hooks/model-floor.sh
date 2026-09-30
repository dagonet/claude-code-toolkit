#!/usr/bin/env bash
# model-floor.sh -- PreToolUse(Agent): a spawn with no explicit model whose type
# has no model of its own (general-purpose, other built-ins, `model: inherit`)
# runs on the project default instead of the orchestrator's model (v4.3.0, spec
# Part C). Never touches an explicit model or a typed agent's own model. Steps
# aside while Jev routing is on (it applies the same floor). ADVISORY: any doubt
# -> exit 0, no output (the spawn inherits, as before v4.3.0).
#
# The output is `updatedInput` ONLY -- deliberately no `permissionDecision`. A
# hook that answers "allow" skips the user's permission prompt; an advisory
# model floor must never grant permission. STDOUT is the whole contract: exactly
# one JSON object on success, nothing otherwise; the one diagnostic line goes to
# STDERR.
lib="$(dirname "$0")/lib/json.sh"
[ -f "$lib" ] || exit 0
# shellcheck source=lib/json.sh
. "$lib"
MF_JSON=$(cat)
case "$MF_JSON" in "$JSON_BOM"*) MF_JSON=${MF_JSON#"$JSON_BOM"} ;; esac
json_have || exit 0
json_valid "$MF_JSON" || exit 0
[ "$(json_get "$MF_JSON" tool_name)" = "Agent" ] || exit 0
[ -n "$(json_get "$MF_JSON" tool_input.model)" ] && exit 0
MF_TYPE=$(json_get "$MF_JSON" tool_input.subagent_type)
[ -n "$MF_TYPE" ] || MF_TYPE=general-purpose
case "$MF_TYPE" in *[!A-Za-z0-9_.-]*|.*) exit 0 ;; esac
# Types that carry a model of their own (statusline-setup: sonnet,
# claude-code-guide: haiku) or ignore a model override (fork): step aside.
case "$MF_TYPE" in statusline-setup|claude-code-guide|fork) exit 0 ;; esac
MF_CWD=$(json_get "$MF_JSON" cwd); [ -n "$MF_CWD" ] || MF_CWD=.
MF_ROOT=$(git -C "$MF_CWD" rev-parse --show-toplevel 2>/dev/null) || MF_ROOT="$MF_CWD"
# The `model:` value of an agent file's frontmatter, unquoted, no whitespace.
mf_model() { awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&/^model:/{sub(/^model:[[:space:]]*/,"");print;exit}' "$1" 2>/dev/null | tr -d '\r"'"'"'[:space:]'; }
for mf_f in "$MF_ROOT/.claude/agents/$MF_TYPE.md" "$HOME/.claude/agents/$MF_TYPE.md"; do
  [ -f "$mf_f" ] || continue
  # Any model of its own -- an alias or a full id -- is the agent's choice;
  # only `inherit` (or none) falls through to the floor.
  case "$(mf_model "$mf_f")" in ""|inherit) ;; *) exit 0 ;; esac
  break
done
MF_GD=$(git -C "$MF_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -n "$MF_GD" ] && grep -Eq '"route"[[:space:]]*:[[:space:]]*true' "$MF_GD/jev/config.json" 2>/dev/null && exit 0
# GC_KEY_PRE, defined locally (same text as hooks/lib/git-cmd.sh and run-gate.sh;
# sourcing git-cmd.sh here would cost ~57 ms per Agent spawn): a BOM on line 1
# must not hide the key. Check 21c-2 requires every PROJECT_CONTEXT.md anchor to use it.
GC_BOM=$(printf '\357\273\277')
GC_KEY_PRE="^(${GC_BOM})?[-*[:space:]]*"
MF_DEF=$(grep -E "${GC_KEY_PRE}\*\*Subagent default model\*\*:" "$MF_ROOT/PROJECT_CONTEXT.md" 2>/dev/null | head -1 | sed -E 's/.*\*\*Subagent default model\*\*:[[:space:]]*//; s/[`[:space:]]//g')
case "$MF_DEF" in haiku|sonnet|opus|fable) ;; *) MF_DEF=sonnet ;; esac
# Emit with the backend json.sh selected. The payload goes in on stdin and the
# model as an argument -- never interpolated into program text. tool_input is
# copied whole (updatedInput REPLACES it), so unknown keys survive.
case "$JSON_PARSER" in
  node)
    MF_OUT=$(printf '%s' "$MF_JSON" | node -e '
      var p = JSON.parse(require("fs").readFileSync(0, "utf8").replace(/^\uFEFF/, ""));
      var ti = p.tool_input;
      if (ti === null || typeof ti !== "object" || Array.isArray(ti)) process.exit(1);
      process.stdout.write(JSON.stringify({ hookSpecificOutput: {
        hookEventName: "PreToolUse",
        updatedInput: Object.assign({}, ti, { model: process.argv[1] }) } }));
    ' "$MF_DEF" 2>/dev/null) || exit 0 ;;
  python3)
    MF_OUT=$(printf '%s' "$MF_JSON" | python3 -c '
import json, sys
p = json.loads(sys.stdin.buffer.read().decode("utf-8-sig", "replace"))
ti = p.get("tool_input")
if not isinstance(ti, dict):
    sys.exit(1)
ti = dict(ti)
ti["model"] = sys.argv[1]
sys.stdout.buffer.write(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": ti}}, ensure_ascii=False).encode("utf-8"))
' "$MF_DEF" 2>/dev/null) || exit 0 ;;
  jq)
    MF_OUT=$(printf '%s' "$MF_JSON" | jq -jc --arg m "$MF_DEF" '
      if (.tool_input | type) != "object" then error("no tool_input")
      else {hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input + {model: $m})}} end
    ' 2>/dev/null) || exit 0 ;;
  *) exit 0 ;;
esac
[ -n "$MF_OUT" ] || exit 0
MF_OUT=${MF_OUT%$'\r'}
printf '%s' "$MF_OUT"
echo "model-floor: $MF_TYPE had no model -> $MF_DEF" >&2
exit 0
