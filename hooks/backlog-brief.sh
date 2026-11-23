#!/usr/bin/env bash
# backlog-brief.sh -- SessionStart (every source: startup, resume, clear, compact): one line of backlog debt
# (v6.3, backlog discipline; design 2026-11-22 section 10a D). SessionStart stdout reaches the model.
# ADVISORY, class project, polarity open: every path exits 0, no onFailure, no JSON parser, no network in file mode.
# now-brief.sh is separate and untouched (it re-shows ## Now after a compaction only).
#
# MODE is `Task source` in the repo root's PROJECT_CONTEXT.md, read exactly as backlog-item-check.sh reads it (bic_mode
# below is a byte-for-byte copy; consistency check 86 pins the two together). The root is the repo's top level (as the guard finds it), else CLAUDE_PROJECT_DIR, else `.`.
#   file mode   (`plan-files`):    PROJECT_STATE.md, under `## Backlog`:
#       `backlog: <u> untriaged, <p> in progress, top: B-<n> <title>`  (`top: none` when Ranked holds no item)
#       <u> = B-<n> lines under ### Untriaged; <p> = B-<n> lines tagged `[in progress]` under ### Ranked; the top
#       item is the first B-<n> line under ### Ranked, shown without its tag, control characters removed, capped at 80 characters
#       (ending in `...`) because stdout reaches the model. A line is `- B-<n> [in progress] <title>`.
#       Any of the three subsections missing: the hint line instead.
#   issue mode  (`github-issues`): `backlog: <u> untriaged, <o> open` from `gh issue list --state open --json labels
#       --limit 200` under `timeout 3` (<u> = open issues with no priority:1/2/3 label; the list is capped at 200, so
#       a larger backlog counts its first 200). Silent when timeout or gh is missing, or the call fails.
# No PROJECT_STATE.md (file mode), no Task source or an unknown value: silent.

[ -t 0 ] || cat >/dev/null 2>&1

# GC_BOM / GC_KEY_PRE: the same text as hooks/lib/git-cmd.sh (the definition census, check 21c-2, pins the copies).
GC_BOM=$(printf '\357\273\277')
GC_KEY_PRE="^(${GC_BOM})?[-*[:space:]]*"

# bic_mode: prints file, issue or nothing (missing file, missing field or an unknown value). Reads the repo root's
# PROJECT_CONTEXT.md (BIC_TOP, set by the caller); backticks and surrounding spaces are trimmed.
bic_mode() {
  local line v
  line=$(grep -E "${GC_KEY_PRE}\*\*Task source\*\*:" "$BIC_TOP/PROJECT_CONTEXT.md" 2>/dev/null | head -1)
  v=$(printf '%s\n' "$line" | sed -E "s/${GC_KEY_PRE}\\*\\*Task source\\*\\*:[[:space:]\`]*//;s/[[:space:]\`]+\$//")
  case "$v" in
    plan-files) printf 'file' ;;
    github-issues) printf 'issue' ;;
  esac
  return 0
}

BIC_TOP=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2>/dev/null) || BIC_TOP=${CLAUDE_PROJECT_DIR:-.}
mode=$(bic_mode)

case "$mode" in
  file)
    f="$BIC_TOP/PROJECT_STATE.md"
    [ -f "$f" ] || exit 0
    tr -d '\r' < "$f" | awk '
      /^## / { inb = ($0 ~ /^## Backlog[[:space:]]*$/); sec = ""; next }
      inb && /^### / { s = $0; sub(/^### /, "", s); sub(/[[:space:]]+$/, "", s); sec = s; seen[s] = 1; next }
      inb && /^[[:space:]]*[-*][[:space:]]+B-[0-9]+([^0-9]|$)/ {
        if (sec == "Untriaged") u++
        else if (sec == "Ranked") {
          if ($0 ~ /^[[:space:]]*[-*][[:space:]]+B-[0-9]+[[:space:]]+\[in progress\]/) p++
          if (top == "") {
            l = $0; sub(/^[[:space:]]*[-*][[:space:]]+B-/, "", l)
            n = l; sub(/[^0-9].*$/, "", n)
            t = substr(l, length(n) + 1)
            gsub(/[\001-\037\177]/, "", t)
            sub(/^[[:space:]]+\[in progress\]/, "", t); sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
            if (length(t) > 80) t = substr(t, 1, 77) "..."
            top = "B-" n (t == "" ? "" : " " t)
          }
        }
      }
      END {
        if (!(seen["Untriaged"] && seen["Ranked"] && seen["Done"])) {
          print "backlog: PROJECT_STATE.md has no ### Untriaged/### Ranked/### Done -- see AGENT_TEAM.md § Backlog"
          exit
        }
        printf "backlog: %d untriaged, %d in progress, top: %s\n", u, p, (top == "" ? "none" : top)
      }'
    ;;
  issue)
    command -v timeout >/dev/null 2>&1 && command -v gh >/dev/null 2>&1 || exit 0
    json=$(cd "$BIC_TOP" 2>/dev/null && GH_PROMPT_DISABLED=1 timeout 3 gh issue list --state open --json labels --limit 200 </dev/null 2>/dev/null) || exit 0
    case "$json" in '['*) ;; *) exit 0 ;; esac
    printf '%s' "$json" | tr -d '\n' | sed 's/"labels"[[:space:]]*:/\
&/g' | awk '
      /^"labels"/ { o++; if ($0 ~ /"name"[[:space:]]*:[[:space:]]*"priority:[123]"/) r++ }
      END { printf "backlog: %d untriaged, %d open\n", o - r, o }'
    ;;
esac
exit 0
