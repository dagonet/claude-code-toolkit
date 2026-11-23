#!/usr/bin/env bash
# PreToolUse hook: refuse a pull request that names no backlog item (v6.3, backlog discipline).
# Matcher: mcp__MCP_DOCKER__create_pull_request (PR creation) and the three MCP merge tools
# mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge|mcp__plugin_github-tools_github-tools__github_pr_auto_merge
# (the merge second line). The `gh pr create` / `gh pr merge` shapes arrive with the dispatcher tables.
#
# Fail CLOSED, class project, independent of `**Gate**:` (no Gate line still means the check runs).
# Escape hatch: <cwd>/.claude/git-guard-off, as for every git guard. No network, no state files.
#
# MODE is `Task source` in the repo root's PROJECT_CONTEXT.md (backticks and spaces trimmed):
#   exactly `plan-files` = file mode, exactly `github-issues` = issue mode, anything else or missing = refuse.
# ISSUE MODE (create only): the PR body holds a closing keyword plus `#<n>` (close/closes/closed,
#   fix/fixes/fixed, resolve/resolves/resolved; a cross-repo owner/repo#n does not count), or a line that is
#   exactly `Item: none`. Issue mode has no local view of a PR body at merge time, so a MERGE passes in issue
#   mode: the merge second line covers file mode only (documented, not a gap to fix here).
# FILE MODE (create and merge): the checkout's HEAD against refs/remotes/origin/<base>, in this order:
#   1. the diff touches only PROJECT_STATE.md (grooming): allowed;
#   2. a commit in <base>..HEAD carries the trailer `Item: none`: allowed;
#   3. the base's PROJECT_STATE.md lacks `## Backlog` with ### Untriaged / ### Ranked / ### Done: refuse (first PR
#      after the update adds the headings and carries the trailer);
#   4. a B-<n> is in the base's Untriaged or Ranked, not in the base's Done, in HEAD's Done and not in HEAD's
#      Untriaged or Ranked: allowed (a move);
#   5. otherwise refuse. An id that appears only in HEAD's Done, sits in the base's Done too, or stays open in HEAD
#      is not a move.
# BASE is tool_input.base, else the local refs/remotes/origin/HEAD, else refuse "pass --base"; `main` is never
#   assumed. A missing refs/remotes/origin/<base> refuses "fetch first".
# HEAD is tool_input.head (an `owner:` prefix stripped), else the checkout's current branch. A checkout on any
#   other branch refuses "run from the PR's own checkout"; HEAD not equal to refs/remotes/origin/<head> refuses
#   "push first".
#   Base and head must be plain branch names (git check-ref-format --branch, no `@{`), else refuse.
# MERGE LIMIT: an MCP merge carries only the PR number, with no network there is no mapping to the PR's branch, so
#   the merge line checks the cwd checkout's branch; merge from the PR's own checkout.
#
# bic_* functions (mode, refs, file check, body check) are written for reuse by the gh pr create/merge shapes.

trap '[ "$?" = 127 ] && exit 2' EXIT   # the registration wrapper's 127->2, in-hook (same as gate-before-merge.sh)

# Read and parse the payload BEFORE sourcing git-cmd.sh (1800 lines), so a call that cannot hold a refusal exits
# without loading it. ONE parse: gc_read_stdin --preparsed takes the result over.
case ${BASH_SOURCE[0]} in */*) cctg_dir=${BASH_SOURCE[0]%/*} ;; *) cctg_dir=. ;; esac
jlib="$cctg_dir/lib/json.sh"
[ -f "$jlib" ] || { echo "BLOCKED: backlog-item-check: $jlib missing -- run /cct:sync-template step 6b (hooks/lib/json.sh)" >&2; exit 2; }
. "$jlib"
if [ "${CCTD_MEMO[1]+set}" = set ]; then GC_PRE_JSON=${CCTD_MEMO[1]}; else GC_PRE_JSON=$(cat); fi
json_payload "$GC_PRE_JSON"; GC_PREPARSED=$?
if [ "$GC_PREPARSED" = 0 ]; then
  case "$JP_TOOL" in
    # Not this hook's tools: the Bash/PowerShell shapes are not registered here (a stray call never reaches git-cmd.sh).
    Bash|PowerShell) exit 0 ;;
  esac
fi

lib="$cctg_dir/lib/git-cmd.sh"
[ -f "$lib" ] || { echo "BLOCKED: backlog-item-check: $lib missing -- run /cct:sync-template step 6b (hooks/lib/git-cmd.sh)" >&2; exit 2; }
_np_jp=$JSON_PARSER   # git-cmd.sh re-sources json.sh, which resets the parser memo
. "$lib"
JSON_PARSER=$_np_jp
command -v gc_current_branch >/dev/null 2>&1 || { echo "BLOCKED: backlog-item-check: $lib is present but corrupt (gc_current_branch undefined) -- refusing" >&2; exit 2; }

gc_read_stdin --preparsed
gc_guard_off && exit 0

CWD="$GC_CWD"

# bic_refuse <text>: the one refusal shape. exit 2, stderr starts with the hook name, the text names the fix.
bic_refuse() {
  printf 'BLOCKED: backlog-item-check: %s\n' "$1" >&2
  exit 2
}

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

# bic_branch_name <name>: 0 when <name> is a plain branch name. `~1`, `^`, `@{0}` and `@{-1}` would widen what
# rev-parse resolves, so `@{` is refused outright on top of git check-ref-format --branch.
bic_branch_name() {
  case "$1" in *'@{'*) return 1 ;; esac
  git check-ref-format --branch "$1" >/dev/null 2>&1
}

# bic_refs <base> <head>: sets BIC_BASE_REF (refs/remotes/origin/<base>) and BIC_HEAD, or refuses. Empty arguments
# mean "not given": the base falls back to the local origin/HEAD, the head to the checkout's current branch.
bic_refs() {
  local base=$1 head=$2 cur sym bsha hsha
  if [ -z "$base" ]; then
    sym=$(git -C "$CWD" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)
    base=${sym#refs/remotes/origin/}
    [ -n "$sym" ] && [ "$base" != "$sym" ] && [ -n "$base" ] ||
      bic_refuse "no base branch given and refs/remotes/origin/HEAD is not set: pass --base <branch> (MCP: the base argument), or run \`git remote set-head origin -a\`."
  fi
  bic_branch_name "$base" || bic_refuse "base '$base' is not a branch name (no revision expressions such as ~ or @{}): pass --base <branch>."
  BIC_BASE_REF="refs/remotes/origin/$base"
  bsha=$(git -C "$CWD" rev-parse --verify -q "$BIC_BASE_REF^{commit}" 2>/dev/null)
  [ -n "$bsha" ] || bic_refuse "$BIC_BASE_REF does not exist locally: fetch first (\`git fetch origin $base\`), this check uses no network."
  cur=$(gc_current_branch "$CWD")
  head=${head#*:}   # an owner:branch prefix
  if [ -z "$head" ]; then
    [ -n "$cur" ] || bic_refuse "the checkout is on a detached HEAD and no head branch was given: run from the PR's own checkout, on the PR's branch."
    head=$cur
  fi
  bic_branch_name "$head" || bic_refuse "head '$head' is not a branch name (no revision expressions such as ~ or @{}): run from the PR's own checkout."
  BIC_HEAD=$head
  [ "$cur" = "$head" ] || bic_refuse "this checkout is on '${cur:-detached HEAD}', the PR's head is '$head': run from the PR's own checkout."
  hsha=$(git -C "$CWD" rev-parse --verify -q "HEAD^{commit}" 2>/dev/null)
  [ -n "$hsha" ] && [ "$hsha" = "$(git -C "$CWD" rev-parse --verify -q "refs/remotes/origin/$head^{commit}" 2>/dev/null)" ] ||
    bic_refuse "HEAD is not equal to refs/remotes/origin/$head: push first (\`git push -u origin $head\`), this check uses no network."
  return 0
}

# bic_ids <ref> <state-regex>: B-<n> numbers listed under the `### <state>` subsections of `## Backlog` in
# <ref>:PROJECT_STATE.md, one per line. state-regex is an awk regex over the subsection name (Untriaged|Ranked, Done).
bic_ids() {
  git -C "$CWD" show "$1:PROJECT_STATE.md" 2>/dev/null | awk -v want="$2" '
    /^## / { inb = ($0 ~ /^## Backlog[[:space:]]*$/); sec = ""; next }
    inb && /^### / { s = $0; sub(/^### /, "", s); sub(/[[:space:]]+$/, "", s); sec = s; next }
    inb && sec != "" && sec ~ ("^(" want ")$") && /^[[:space:]]*[-*][[:space:]]+B-[0-9]+([^0-9]|$)/ {
      l = $0; sub(/^[[:space:]]*[-*][[:space:]]+B-/, "", l); sub(/[^0-9].*$/, "", l); print l }'
}

# bic_has_shape <ref>: 0 when <ref>:PROJECT_STATE.md holds `## Backlog` with the three subsections.
bic_has_shape() {
  local n
  n=$(git -C "$CWD" show "$1:PROJECT_STATE.md" 2>/dev/null | awk '
    /^## / { inb = ($0 ~ /^## Backlog[[:space:]]*$/); next }
    inb && /^### Untriaged[[:space:]]*$/ { u = 1 }
    inb && /^### Ranked[[:space:]]*$/ { r = 1 }
    inb && /^### Done[[:space:]]*$/ { d = 1 }
    END { print u + r + d }')
  [ "$n" = 3 ]
}

# bic_file_ok: file mode, after bic_refs. Returns 0 on an exempt diff, an `Item: none` trailer or a move. Otherwise
# returns 1 and sets BIC_MSG to the refusal text. Order: exempt, trailer, base shape, move, refuse.
bic_file_ok() {
  local names trailers moved bdone hopen id
  if ! names=$(git -C "$CWD" diff --no-renames --name-only "$BIC_BASE_REF...HEAD" 2>/dev/null); then
    BIC_MSG="cannot read the diff of HEAD against $BIC_BASE_REF: run from the PR's own checkout."; return 1
  fi
  [ "$names" = PROJECT_STATE.md ] && return 0
  if ! trailers=$(git -C "$CWD" log --format='%(trailers:key=Item,valueonly)' "$BIC_BASE_REF..HEAD" 2>/dev/null); then
    BIC_MSG="cannot read the commits of $BIC_BASE_REF..HEAD: run from the PR's own checkout."; return 1
  fi
  printf '%s\n' "$trailers" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' | grep -qx 'none' && return 0
  if ! bic_has_shape "$BIC_BASE_REF"; then
    BIC_MSG="$BIC_BASE_REF has no \`## Backlog\` with the subsections ### Untriaged, ### Ranked and ### Done in PROJECT_STATE.md: add the three headings in this PR and commit with trailer \`Item: none\`."
    return 1
  fi
  # A move: open in the base (Untriaged or Ranked, and not already in the base's Done), in HEAD's Done, and no longer
  # open in HEAD. An id in both lists of the base is stale state, never a move; an id left open in HEAD was copied.
  moved=$(bic_ids "$BIC_BASE_REF" 'Untriaged|Ranked')
  bdone=$(bic_ids "$BIC_BASE_REF" 'Done')
  hopen=$(bic_ids HEAD 'Untriaged|Ranked')
  for id in $(bic_ids HEAD 'Done'); do
    printf '%s\n' "$moved" | grep -qx "$id" || continue
    printf '%s\n' "$bdone" | grep -qx "$id" && continue
    printf '%s\n' "$hopen" | grep -qx "$id" && continue
    return 0
  done
  BIC_MSG="this PR moves no backlog item out of Untriaged/Ranked into \`### Done\` (an id only in HEAD's Done, already in the base's Done, or still open in HEAD is not a move): move the item into \`### Done\` in this PR, or commit with trailer \`Item: none\` (T1 only). The trailer must sit in the last paragraph of the commit message."
  return 1
}

# bic_body_ok <body>: issue mode. Returns 0 on a closing keyword plus #<n> (same repo) or a line that is exactly
# `Item: none`; otherwise returns 1 and sets BIC_MSG. Explicit character classes, not -i: no locale folding.
bic_body_ok() {
  local kw='([Cc][Ll][Oo][Ss][Ee][SsDd]?|[Ff][Ii][Xx]([Ee][SsDd])?|[Rr][Ee][Ss][Oo][Ll][Vv][Ee][SsDd]?)'
  local body
  body=$(printf '%s\n' "$1" | tr -d '\r')
  printf '%s\n' "$body" | grep -Eq "(^|[^[:alnum:]_])${kw}[[:space:]]+#[0-9]+([^[:alnum:]_]|\$)" && return 0
  printf '%s\n' "$body" | grep -qx 'Item: none' && return 0
  BIC_MSG="the PR body names no item: put a closing keyword and the issue in the body (\`Closes #<n>\`, \`Fixes #<n>\` or \`Resolves #<n>\`; a cross-repo owner/repo#<n> does not count), or a line that is exactly \`Item: none\` (T1 only)."
  return 1
}

# ---- the MCP shapes --------------------------------------------------------
case "$GC_TOOL" in
  mcp__MCP_DOCKER__create_pull_request) bic_op=create ;;
  mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge|mcp__plugin_github-tools_github-tools__github_pr_auto_merge) bic_op=merge ;;
  *) bic_refuse "tool '${GC_TOOL:-<none>}' is not one this guard knows (create_pull_request or an MCP merge): refusing, since it cannot judge the call." ;;
esac

BIC_TOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
[ -n "$BIC_TOP" ] || bic_refuse "$CWD is not inside a git checkout: run from the PR's own checkout."

json_fields "$GC_JSON" tool_input.head tool_input.base tool_input.body
[ "$?" = 0 ] || bic_refuse "the tool input did not parse: cannot read the PR's head, base and body."
bic_in_head=${JF[0]}; bic_in_base=${JF[1]}; bic_in_body=${JF[2]}

BIC_MODE=$(bic_mode)
case "$BIC_MODE" in
  file|issue) ;;
  *) bic_refuse "PROJECT_CONTEXT.md has no usable \`Task source\` (needs exactly \`plan-files\` or \`github-issues\`): set \`- **Task source**: \`plan-files\`\` (or github-issues) in $BIC_TOP/PROJECT_CONTEXT.md." ;;
esac

if [ "$BIC_MODE" = issue ]; then
  [ "$bic_op" = merge ] && exit 0   # issue mode: no local view of the PR body at merge time (documented)
  bic_body_ok "$bic_in_body" || bic_refuse "$BIC_MSG"
  exit 0
fi

bic_refs "$bic_in_base" "$bic_in_head"
bic_file_ok || bic_refuse "$BIC_MSG"
exit 0
