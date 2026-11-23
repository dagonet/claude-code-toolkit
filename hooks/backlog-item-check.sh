#!/usr/bin/env bash
# PreToolUse hook: refuse a pull request that names no backlog item (v6.3, backlog discipline).
# Matcher: mcp__MCP_DOCKER__create_pull_request (PR creation) and the three MCP merge tools
# mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge|mcp__plugin_github-tools_github-tools__github_pr_auto_merge
# (the merge second line), and `gh pr create` / `gh pr merge` in a Bash or PowerShell command (the dispatcher's
# bash and powershell tables, before pre-commit-test; the root .claude/settings.json registers it on Bash|PowerShell).
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
# THE gh SHAPES (Bash/PowerShell).
#   STRICT: a shape this hook cannot judge is refused with ONE fix text, never parsed.
#   Every Bash call runs this guard, so it copies gate-before-merge's early exit (no git/gh/sh/source/ps1 word, no
#   backslash, `$`, backtick, glob or `(` in the quote-stripped text: exit 0 before git-cmd.sh is sourced).
#   gc_dir_rule (as in gate-before-merge) allows ONE leading `cd <abs dir> &&`, judges in that directory (GC_CWD_E) and
#   reads script bodies into the command text.
#   STEP A, detection: the typed text plus the script bodies, normalized (quotes, backslashes and backticks removed,
#   newlines to spaces, lowercase). It must hold the word gh, later the word pr, later one of the words create, new
#   (gh's alias for create) or merge. No match: exit 0, so everyday text ("Fix PR template", `gh pr view`,
#   `for pr in $(gh pr list)`) stays free.
#   STEP B, a match must be the ONE plain shape in the typed command: a single segment (pipes, ;, &&, ||, &, newlines
#   count; the one leading cd && does not), the literal words `gh pr`, optionally -R/--repo <v>, then create, new or
#   merge as a plain unquoted word, then flags; no `&`, `$(`, backtick or process substitution in it. Anything else
#   (a chain, env/sudo/bash -c, a quoted or $ word, a script body that matched) is refused without analysis.
#   KNOWN LIMITS. Accepted: a `git commit -m` or echo whose text holds the words gh, pr and create/new/merge is refused
#   too (move that text into a file). Unseen: xargs, running ./x.sh directly, PowerShell `& x.ps1`, nested scripts, and
#   interpreters (python, make); `gh alias`; a command word or verb built so that neither the words gh, pr and a verb
#   nor a `$` next to pr appear (`$G pr create` with G set elsewhere is caught only because a verb follows a `$` word).
#   Only these flags are read, from the plain segment: --base/-B and --head/-H (create), --body-file/-F (create); a
#   value flag given twice, or a --title/-t value holding a flag-shaped word, is refused.
#   BASE: --base/-B, else refs/remotes/origin/HEAD, else refuse. HEAD: --head/-H, else the checkout's branch. A merge
#   has neither flag: the checkout's branch and origin/HEAD, as for the MCP merge tools.
#   BODY (create only, BOTH modes): read ONLY from --body-file/-F, by this hook. --body, -b, --fill, --fill-first,
#   --fill-verbose, --template, --editor, --web, or no body file at all: refused, "use --body-file"; the file must
#   exist and be readable. The quote-stripping segment split cannot read a literal body safely. The file's CONTENT is
#   judged in issue mode only; file mode judges the diff.
#   Issue-mode `gh pr merge` passes, as the MCP merge does.

trap '[ "$?" = 127 ] && exit 2' EXIT   # the registration wrapper's 127->2, in-hook (same as gate-before-merge.sh)

# Read and parse the payload BEFORE sourcing git-cmd.sh (1800 lines), so a call that cannot hold a refusal exits
# without loading it. ONE parse: gc_read_stdin --preparsed takes the result over.
case ${BASH_SOURCE[0]} in */*) cctg_dir=${BASH_SOURCE[0]%/*} ;; *) cctg_dir=. ;; esac
jlib="$cctg_dir/lib/json.sh"
[ -f "$jlib" ] || { echo "BLOCKED: backlog-item-check: $jlib missing -- run /cct:sync-template step 6b (hooks/lib/json.sh)" >&2; exit 2; }
. "$jlib"
if [ "${CCTD_MEMO[1]+set}" = set ]; then GC_PRE_JSON=${CCTD_MEMO[1]}; else GC_PRE_JSON=$(cat); fi
json_payload "$GC_PRE_JSON"; GC_PREPARSED=$?
if [ "$GC_PREPARSED" = 0 ] && [ -n "$JP_CMD" ]; then
  case "$JP_TOOL" in
    Bash|PowerShell)
      # gate-before-merge's early exit, verbatim in effect (see its comment): a word that could be gh, git or a shell,
      # or a character that can build one, keeps the call; everything else exits before git-cmd.sh (1800 lines) is
      # sourced. An unparseable payload, an empty command and every other tool fall through to the checks below.
      _np_q=${JP_CMD//[\"\']/}
      _np_dot='\.([[:space:]]|$)'
      if [[ $_np_q == *[Gg][Ii][Tt]* || $_np_q == *[Gg][Hh]* || $_np_q == *[Ss][Hh]* ||
            $_np_q == *[Ss][Oo][Uu][Rr][Cc][Ee]* || $_np_q == *[Pp][Ss]1* ||
            $_np_q == *'\'* || $_np_q == *'$'* || $_np_q == *'`'* || $_np_q == *[*?[]* ||
            $_np_q == *'('* || $_np_q =~ $_np_dot ]]; then
        :
      else
        exit 0
      fi ;;
  esac
fi

lib="$cctg_dir/lib/git-cmd.sh"
[ -f "$lib" ] || { echo "BLOCKED: backlog-item-check: $lib missing -- run /cct:sync-template step 6b (hooks/lib/git-cmd.sh)" >&2; exit 2; }
_np_jp=$JSON_PARSER   # git-cmd.sh re-sources json.sh, which resets the parser memo
. "$lib"
JSON_PARSER=$_np_jp
command -v gc_current_branch >/dev/null 2>&1 || { echo "BLOCKED: backlog-item-check: $lib is present but corrupt (gc_current_branch undefined) -- refusing" >&2; exit 2; }

# bic_refuse <text>: the one refusal shape. exit 2, stderr starts with the hook name, the text names the fix.
bic_refuse() {
  printf 'BLOCKED: backlog-item-check: %s\n' "$1" >&2
  exit 2
}

# A payload that did not parse (or no JSON parser) is refused here, with this hook's own prefix, before gc_read_stdin
# would refuse it under the generic one. The kill switch is read from the process cwd, as gc_read_stdin does.
if [ "$GC_PREPARSED" != 0 ]; then
  GC_CWD=$(pwd)
  gc_guard_off && exit 0
  bic_refuse "the hook payload did not parse, or no JSON parser (node, python3 or jq) is on PATH, so this check cannot judge the call: re-run it, or install a parser."
fi
gc_read_stdin --preparsed
gc_guard_off && exit 0

CWD="$GC_CWD"

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


# bic_judge <create|merge> <base> <head> <body>: the verdict for one PR operation (BIC_MODE and BIC_TOP are set).
# Issue mode: a create needs the body to name an item, a merge passes (no local view of the PR body at merge time,
# documented). File mode: the diff check; <body> is not read.
bic_judge() {
  if [ "$BIC_MODE" = issue ]; then
    [ "$1" = merge ] && return 0
    bic_body_ok "$4" || bic_refuse "$BIC_MSG"
    return 0
  fi
  bic_refs "$2" "$3"
  bic_file_ok || bic_refuse "$BIC_MSG"
}

# bic_plain <segments>: Step B. Succeeds only for the ONE plain shape: exactly one segment, the literal words
# `gh pr`, optionally `-R <v>`, `-R<v>`, `--repo <v>` or `--repo=<v>`, then create, new (gh's alias) or merge as a plain
# unquoted word, then flags. Sets BIC_OP and BIC_ARGS (the words after the verb). Anything else fails: no analysis.
bic_plain() {
  local s=$1
  [ "$(printf '%s\n' "$s" | grep -c .)" = 1 ] || return 1
  s=${s%"${s##*[![:space:]]}"}   # trailing blanks off, then exactly one trailing `2>&1` token is allowed
  case $s in *[[:space:]]2'>&'1) s=${s%2'>&'1} ;; esac
  case $s in *'&'*|*'$('*|*\`*|*'<('*|*'>('*) return 1 ;; esac
  set -f   # word splitting without pathname expansion
  # shellcheck disable=SC2086
  set -- $s
  set +f
  case ${1-} in gh|gh.exe) ;; *) return 1 ;; esac
  [ "${2-}" = pr ] || return 1
  shift 2
  case ${1-} in
    -R|--repo) shift 2 ;;
    -R?*|--repo=*) shift ;;
  esac
  case ${1-} in
    create|new) BIC_OP=create ;;
    merge) BIC_OP=merge ;;
    *) return 1 ;;
  esac
  shift
  BIC_ARGS=("$@")
}

# bic_create_args <raw segment>: reads BIC_ARGS of a create. Sets BIC_BASE, BIC_HEAD and BIC_BFILE, or refuses. Only
# --base/-B, --head/-H, --body-file/-F and --title/-t take a value here; any other body form is refused, and so is a
# value flag given twice or a --title/-t value that holds a flag-shaped word (it would be read as a flag).
bic_create_args() {
  local t fam val other=0 nb=0 nh=0 nf=0 nt=0
  BIC_BASE=""; BIC_HEAD=""; BIC_BFILE=""
  # a quoted title with a word that starts with a dash, or an unquoted title that does: flag-shaped
  if printf '%s\n' "$1" | grep -qE "(^|[[:space:]])(--title|-t)[[:space:]=]+([\"'][^\"']*[[:space:]]-|[\"']?-)"; then
    bic_refuse "the title holds a flag-shaped word (a word that starts with -): reword the title."
  fi
  set -- "${BIC_ARGS[@]}"
  while [ $# -gt 0 ]; do
    t=${1//[\"\']/}; fam=""; val=""
    case $t in
      --base|-B)      fam=base; val=${2-}; shift ;;
      --base=*)       fam=base; val=${t#--base=} ;;
      -B?*)           fam=base; val=${t#-B} ;;
      --head|-H)      fam=head; val=${2-}; shift ;;
      --head=*)       fam=head; val=${t#--head=} ;;
      -H?*)           fam=head; val=${t#-H} ;;
      --body-file|-F) fam=file; val=${2-}; shift ;;
      --body-file=*)  fam=file; val=${t#--body-file=} ;;
      -F?*)           fam=file; val=${t#-F} ;;
      --title|-t)     fam=title; val=${2-}; shift ;;
      --title=*)      fam=title; val=${t#--title=} ;;
      -t?*)           fam=title; val=${t#-t} ;;
      --body|--body=*|-b|-b?*|--fill|-f|--fill-first|--fill-verbose|--template|--template=*|-T|-T?*|--editor|-e|--web|-w) other=1 ;;
    esac
    if [ -n "$fam" ]; then
      val=${val//[\"\']/}
      [ -n "$val" ] || bic_refuse "$t has no value: pass --base <branch>, --head <branch>, use --body-file <file>, or --title <words>."
      case $fam in
        base) nb=$((nb + 1)); BIC_BASE=$val ;;
        head) nh=$((nh + 1)); BIC_HEAD=$val ;;
        file) nf=$((nf + 1)); BIC_BFILE=$val ;;
        title) nt=$((nt + 1)) ;;
      esac
    fi
    [ $# -gt 0 ] && shift
  done
  [ "$nb" -le 1 ] && [ "$nh" -le 1 ] && [ "$nf" -le 1 ] && [ "$nt" -le 1 ] ||
    bic_refuse "a value flag (--base, --head, --body-file, --title) is given more than once, so this check cannot tell which value counts: give each once."
  [ "$other" = 0 ] && [ -n "$BIC_BFILE" ] ||
    bic_refuse "the body of this gh pr create cannot be read from the command (--body, -b, --fill, --fill-first, --fill-verbose, --template, --editor, --web, or no body file): use --body-file <file> (issue mode: with a closing keyword and #<n> in the file, \`Closes #<n>\`, or a line that is exactly \`Item: none\`, T1 only). If the words gh pr create sit in another command's text or in a title, move that text into a file."
}

# ---- the tool shapes -------------------------------------------------------
# THE 14th FAIL-OPEN (as in the other git gates): a command key that is present but unreadable cannot be ruled out.
if gc_cmd_unreadable; then
  bic_refuse "the payload carries a command this guard could not read, so it cannot rule out a gh pr create or gh pr merge: re-run the command."
fi

case "$GC_TOOL" in
  Bash|PowerShell) bic_op=shell ;;
  mcp__MCP_DOCKER__create_pull_request) bic_op=create ;;
  mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge|mcp__plugin_github-tools_github-tools__github_pr_auto_merge) bic_op=merge ;;
  *) bic_refuse "tool '${GC_TOOL:-<none>}' is not one this guard knows (a Bash or PowerShell command, create_pull_request or an MCP merge): refusing, since it cannot judge the call." ;;
esac

# Step A (words, lowercase, on normalized text) and the one refusal text of Step B. Three alternatives: the words gh,
# pr and a verb in order; the word right after `gh pr` holding a `$` (a built verb); a `$` word right before the word
# `pr` with a verb after it (a built command word).
BIC_A_RE='(^|[^a-z0-9_-])gh(\.exe)?([^a-z0-9_-].*)?[^a-z0-9_-]pr([^a-z0-9_-].*)?[^a-z0-9_-](create|new|merge)([^a-z0-9_-]|$)'
BIC_A_RE_V='(^|[^a-z0-9_-])gh(\.exe)?[[:space:]]+pr[[:space:]]+[^[:space:]]*\$'
BIC_A_RE_W='\$[^[:space:]]*[[:space:]]+pr([^a-z0-9_-].*)?[^a-z0-9_-](create|new|merge)([^a-z0-9_-]|$)'
BIC_FIX="this command mentions gh pr together with create/new/merge; run gh pr create/merge alone as one plain command (gh pr create --body-file F ...), and split any other part or move text holding these words into a file; use --body-file for the PR body."

if [ "$bic_op" = shell ]; then
  [ -n "$GC_CMD" ] || exit 0   # a payload with no command at all: nothing to inspect
  bic_typed=$GC_CMD
  # gate-before-merge's rule: ONE leading `cd <abs dir> &&` is allowed and sets GC_CWD_E; script bodies are read into
  # GC_CMD (after the typed text); another directory change next to a gated verb is refused there.
  gc_dir_rule backlog-item-check "$CWD" || exit 2
  # STEP A, detection: the typed text plus the script bodies, normalized (quotes and backticks removed, newlines to
  # spaces, lowercase; `$` kept). Two texts, any match counts: backslashes deleted (`g\h`) or turned into spaces (a
  # Windows path `cli\gh.exe`). Each holds the typed text then the bodies, then the bodies then the typed text (a wrapper
  # script `gh "$@"` run as `bash s.sh pr merge 5`). No match: not this hook's shape, exit 0 (everyday text such as
  # "Fix PR template" or `gh pr view` never reaches Step B).
  bic_bodies=${GC_CMD#"$bic_typed"}
  bic_x="$GC_CMD $bic_bodies $bic_typed"   # typed then bodies, then bodies then typed, as one text
  bic_n1=$(printf '%s' "$bic_x" | tr -d "\"'\\\\\`" | LC_ALL=C tr 'A-Z\n' 'a-z ')
  bic_n2=$(printf '%s' "$bic_x" | tr -d "\"'\`" | LC_ALL=C tr 'A-Z\n\\' 'a-z  ')
  printf '%s\n%s\n' "$bic_n1" "$bic_n2" | LC_ALL=C grep -qE -e "$BIC_A_RE" -e "$BIC_A_RE_V" -e "$BIC_A_RE_W" || exit 0
  # STEP B: a match must be the one plain shape, in the typed command. Everything else is refused without analysis.
  bic_segs=$(printf '%s\n' "$bic_typed" | gc_split_ops | grep -v '^[[:space:]]*$')
  if [ "$GC_CWD_E" != "$CWD" ]; then bic_segs=$(printf '%s\n' "$bic_segs" | sed 1d); CWD=$GC_CWD_E; fi
  bic_plain "$bic_segs" || bic_refuse "$BIC_FIX"
  bic_gop=$BIC_OP; bic_gseg=$bic_segs
fi

BIC_TOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
[ -n "$BIC_TOP" ] || bic_refuse "$CWD is not inside a git checkout: run from the PR's own checkout."

BIC_MODE=$(bic_mode)
case "$BIC_MODE" in
  file|issue) ;;
  *) bic_refuse "PROJECT_CONTEXT.md has no usable \`Task source\` (needs exactly \`plan-files\` or \`github-issues\`): set \`- **Task source**: \`plan-files\`\` (or github-issues) in $BIC_TOP/PROJECT_CONTEXT.md." ;;
esac

if [ "$bic_op" = shell ]; then
  bic_body=""
  if [ "$bic_gop" = create ]; then
    bic_create_args "$bic_gseg"
    bic_bfile=$BIC_BFILE
    case $bic_bfile in *[\$\`\*\?\[]*|\~*) bic_refuse "the body file '$bic_bfile' holds a \$, a backtick, a glob character or a leading ~, so this check cannot tell which file it is: use --body-file <plain path>." ;; esac
    case $bic_bfile in /*|[A-Za-z]:[/\\]*) ;; *) bic_bfile="$CWD/$bic_bfile" ;; esac
    [ -f "$bic_bfile" ] && [ -r "$bic_bfile" ] || bic_refuse "cannot read the body file '$bic_bfile': write the PR body to a file and pass its path to --body-file."
    [ "$BIC_MODE" = issue ] && bic_body=$(head -c 65536 "$bic_bfile")
  fi
  bic_judge "$bic_gop" "$BIC_BASE" "$BIC_HEAD" "$bic_body"
  exit 0
fi

json_fields "$GC_JSON" tool_input.head tool_input.base tool_input.body
[ "$?" = 0 ] || bic_refuse "the tool input did not parse: cannot read the PR's head, base and body."
bic_judge "$bic_op" "${JF[1]}" "${JF[0]}" "${JF[2]}"
exit 0
