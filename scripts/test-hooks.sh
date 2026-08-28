#!/usr/bin/env bash
# test-hooks.sh
#
# Stdin fixtures for the git-native PreToolUse gates introduced in v2.0:
#   hooks/pre-commit-test.sh, hooks/no-push-main.sh, hooks/gate-before-merge.sh
#
# Each case feeds a realistic hook JSON payload on stdin and asserts the exit
# code (0 = allow, 2 = deny). Throwaway git repos are built under mktemp.
#
# Run from repo root: bash scripts/test-hooks.sh
# Exit 0 = all cases pass. Exit 1 = at least one FAIL.

set -u
pass=0
fail=0

ROOT=$(pwd)
TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t hooktest)
trap 'rm -rf "$TMPROOT"' EXIT

# --- fixture builders -------------------------------------------------------

mkrepo() { # <name> <branch> -> prints path
  d="$TMPROOT/$1"
  mkdir -p "$d/sub"
  git -C "$d" init -q >/dev/null 2>&1
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  echo seed > "$d/seed.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -q -m seed >/dev/null 2>&1
  # normalise the initial branch name across git versions
  git -C "$d" branch -M main >/dev/null 2>&1
  if [ "$2" != "main" ]; then
    git -C "$d" checkout -q -b "$2" >/dev/null 2>&1
  fi
  printf '%s\n' "$d"
}

mkjson() { # <tool_name> <command> <cwd>
  node -e 'console.log(JSON.stringify({session_id:"t",hook_event_name:"PreToolUse",tool_name:process.argv[1],tool_input:{command:process.argv[2]},cwd:process.argv[3]}))' "$1" "$2" "$3"
}

mkjson_mcp() { # <tool_name> <cwd> -- MCP payload carries no tool_input.command
  node -e 'console.log(JSON.stringify({session_id:"t",hook_event_name:"PreToolUse",tool_name:process.argv[1],tool_input:{owner:"o",repo:"r",pullNumber:1},cwd:process.argv[2]}))' "$1" "$2"
}

mkjson_nocmd() { # <tool_name> <cwd> -- a payload whose command we cannot read
  node -e 'console.log(JSON.stringify({session_id:"t",hook_event_name:"PreToolUse",tool_name:process.argv[1],tool_input:{},cwd:process.argv[2]}))' "$1" "$2"
}

# --- assertion --------------------------------------------------------------

check() { # <label> <hook> <expected_exit> <json>
  label="$1"; hook="$2"; want="$3"; json="$4"
  printf '%s' "$json" | bash "$ROOT/$hook" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    printf 'PASS  %-42s (exit %s)\n' "$label" "$got"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s, got %s)\n' "$label" "$want" "$got"
    fail=$((fail + 1))
  fi
}

# ===========================================================================
# no-push-main.sh
# ===========================================================================
echo "=== hooks/no-push-main.sh ==="
MAINREPO=$(mkrepo pushmain main)
FEATREPO=$(mkrepo pushfeat feature/x)
# A repo whose path contains a space: the segment splitter strips quotes, so
# `git -C "…/a b" push` must still be recognised (fail closed), not slip through.
SPACEREPO=$(mkrepo 'push main repo' main)
SPACEFEAT=$(mkrepo 'push feat repo' feature/x)
H=hooks/no-push-main.sh

# must BLOCK (exit 2)
check "push origin main"                 "$H" 2 "$(mkjson Bash 'git push origin main' "$MAINREPO")"
check "push origin HEAD:main"            "$H" 2 "$(mkjson Bash 'git push origin HEAD:main' "$MAINREPO")"
check "push -u origin main"              "$H" 2 "$(mkjson Bash 'git push -u origin main' "$MAINREPO")"
check "push --force origin master"       "$H" 2 "$(mkjson Bash 'git push --force origin master' "$MAINREPO")"
check "push origin HEAD:refs/heads/main" "$H" 2 "$(mkjson Bash 'git push origin HEAD:refs/heads/main' "$MAINREPO")"
check "git -c x=y push origin main"      "$H" 2 "$(mkjson Bash 'git -c x=y push origin main' "$MAINREPO")"
check "wrapped in bash -c"               "$H" 2 "$(mkjson Bash 'bash -c "git push origin main"' "$FEATREPO")"
check "cd sub then bare push (on main)"  "$H" 2 "$(mkjson Bash 'cd sub && git push' "$MAINREPO")"
check "bare push while on main"          "$H" 2 "$(mkjson Bash 'git push' "$MAINREPO")"
check "PowerShell push origin main"      "$H" 2 "$(mkjson PowerShell 'git push origin main' "$FEATREPO")"
check "push after a ; separator"         "$H" 2 "$(mkjson Bash 'echo hi; git push origin main' "$FEATREPO")"
# review round 1: whole-repo pushes carry main even from a feature checkout
check "push --mirror from a feature"     "$H" 2 "$(mkjson Bash 'git push --mirror origin' "$FEATREPO")"
check "push --all from a feature"        "$H" 2 "$(mkjson Bash 'git push --all origin' "$FEATREPO")"
# review round 1: a bare HEAD destination is not a refspec -- it follows the checkout
check "push origin HEAD while on main"   "$H" 2 "$(mkjson Bash 'git push origin HEAD' "$MAINREPO")"
# review round 1: a quoted -C path with a space must not slip the gate
check "quoted -C path with a space"      "$H" 2 "$(mkjson Bash "git -C \"$SPACEREPO\" push origin main" "$FEATREPO")"
# review round 2: the implicit branch check must run against the -C target, not
# the payload cwd -- a spaced -C path must resolve, not silently fall back.
check "spaced -C on main, cwd on feature" "$H" 2 "$(mkjson Bash "git -C \"$SPACEREPO\" push origin" "$FEATREPO")"

# must NOT block (exit 0)
check "push origin feature/x"            "$H" 0 "$(mkjson Bash 'git push origin feature/x' "$MAINREPO")"
check "push --force-with-lease feature"  "$H" 0 "$(mkjson Bash 'git push --force-with-lease origin feature/x' "$MAINREPO")"
check "push --tags while on main"        "$H" 0 "$(mkjson Bash 'git push --tags' "$MAINREPO")"
check "push origin :feature/x"           "$H" 0 "$(mkjson Bash 'git push origin :feature/x' "$MAINREPO")"
check "push -u origin feature/x"         "$H" 0 "$(mkjson Bash 'git push -u origin feature/x' "$MAINREPO")"
check "bare push while on feature"       "$H" 0 "$(mkjson Bash 'git push' "$FEATREPO")"
check "non-push git command"             "$H" 0 "$(mkjson Bash 'git status --short' "$MAINREPO")"
check "git -C <feat> push from main cwd" "$H" 0 "$(mkjson Bash "git -C $FEATREPO push" "$MAINREPO")"
check "push origin HEAD on a feature"    "$H" 0 "$(mkjson Bash 'git push origin HEAD' "$FEATREPO")"
check "spaced -C on feature, cwd on main" "$H" 0 "$(mkjson Bash "git -C \"$SPACEFEAT\" push origin" "$MAINREPO")"
check "malformed JSON payload"           "$H" 0 '{not json'
check "Bash payload with no command"     "$H" 0 "$(mkjson_nocmd Bash "$MAINREPO")"

# kill switch
mkdir -p "$MAINREPO/.claude" && : > "$MAINREPO/.claude/git-guard-off"
check "kill switch disables the gate"    "$H" 0 "$(mkjson Bash 'git push origin main' "$MAINREPO")"
rm -f "$MAINREPO/.claude/git-guard-off"

# ===========================================================================
# pre-commit-test.sh
# ===========================================================================
echo
echo "=== hooks/pre-commit-test.sh ==="
OKREPO=$(mkrepo commitok main)
BADREPO=$(mkrepo commitbad main)
BARE=$(mkrepo commitbare main)
printf '# ctx\n\n- **Test**: `true`\n' > "$OKREPO/PROJECT_CONTEXT.md"
printf '# ctx\n\n- **Test**: `false`\n' > "$BADREPO/PROJECT_CONTEXT.md"
H=hooks/pre-commit-test.sh

check "commit with passing tests"        "$H" 0 "$(mkjson Bash 'git commit -m "x"' "$OKREPO")"
check "commit with failing tests"        "$H" 2 "$(mkjson Bash 'git commit -m "x"' "$BADREPO")"
check "commit with no PROJECT_CONTEXT"   "$H" 0 "$(mkjson Bash 'git commit -m "x"' "$BARE")"
check "non-commit git command"           "$H" 0 "$(mkjson Bash 'git status --short' "$BADREPO")"
check "git add is not a commit"          "$H" 0 "$(mkjson Bash 'git add -A' "$BADREPO")"
check "git -c ... commit"                "$H" 2 "$(mkjson Bash 'git -c user.name=x commit -m y' "$BADREPO")"
check "commit wrapped in bash -c"        "$H" 2 "$(mkjson Bash 'bash -c "git commit -m x"' "$BADREPO")"
check "git -C <bad> commit from ok cwd"  "$H" 2 "$(mkjson Bash "git -C $BADREPO commit -m y" "$OKREPO")"
check "PowerShell commit, failing tests" "$H" 2 "$(mkjson PowerShell 'git commit -m "x"' "$BADREPO")"
check "malformed JSON payload"           "$H" 0 '{not json'
check "Bash payload with no command"     "$H" 0 "$(mkjson_nocmd Bash "$BADREPO")"
# review round 2: a spaced -C path must resolve to that repo, so the gate command
# that runs is the TARGET's, not the payload cwd's.
SPACEBAD=$(mkrepo 'commit bad repo' main)
SPACEOK=$(mkrepo 'commit ok repo' main)
printf '# ctx\n\n- **Test**: `false`\n' > "$SPACEBAD/PROJECT_CONTEXT.md"
printf '# ctx\n\n- **Test**: `true`\n'  > "$SPACEOK/PROJECT_CONTEXT.md"
check "spaced -C, target tests fail"     "$H" 2 "$(mkjson Bash "git -C \"$SPACEBAD\" commit -m y" "$OKREPO")"
check "spaced -C, target tests pass"     "$H" 0 "$(mkjson Bash "git -C \"$SPACEOK\" commit -m y" "$BADREPO")"

mkdir -p "$BADREPO/.claude" && : > "$BADREPO/.claude/git-guard-off"
check "kill switch disables the gate"    "$H" 0 "$(mkjson Bash 'git commit -m "x"' "$BADREPO")"
rm -f "$BADREPO/.claude/git-guard-off"

# ===========================================================================
# gate-before-merge.sh
# ===========================================================================
echo
echo "=== hooks/gate-before-merge.sh ==="
GATEREPO=$(mkrepo gatemain main)
GATEFEAT=$(mkrepo gatefeat feature/y)
for d in "$GATEREPO" "$GATEFEAT"; do
  printf '# ctx\n\n- **Gate**: `bash hooks/run-gate.sh`\n' > "$d/PROJECT_CONTEXT.md"
done
NOGATE=$(mkrepo gatenone main)
H=hooks/gate-before-merge.sh

writeartifact() { # <repo> <sha>
  mkdir -p "$1/.gate"
  printf '{"sha":"%s"}\n' "$2" > "$1/.gate/last-pass.json"
}

# --- Bash branch: merge-shaped commands need a fresh artifact
check "gh pr merge without artifact"     "$H" 2 "$(mkjson Bash 'gh pr merge 5 --squash --delete-branch' "$GATEFEAT")"
check "git merge on main without art."   "$H" 2 "$(mkjson Bash 'git merge feature/y' "$GATEREPO")"
check "push to main without artifact"    "$H" 2 "$(mkjson Bash 'git push origin main' "$GATEFEAT")"

# --- Bash branch: non-merge commands are never gated
check "git status is not a merge"        "$H" 0 "$(mkjson Bash 'git status --short' "$GATEFEAT")"
check "push to feature is not a merge"   "$H" 0 "$(mkjson Bash 'git push origin feature/y' "$GATEFEAT")"
check "git merge on a feature branch"    "$H" 0 "$(mkjson Bash 'git merge origin/main' "$GATEFEAT")"
check "gh pr view is not a merge"        "$H" 0 "$(mkjson Bash 'gh pr view 5' "$GATEFEAT")"

# --- artifact freshness
FEATSHA=$(git -C "$GATEFEAT" rev-parse HEAD)
writeartifact "$GATEFEAT" "$FEATSHA"
check "gh pr merge with fresh artifact"  "$H" 0 "$(mkjson Bash 'gh pr merge 5 --squash' "$GATEFEAT")"
writeartifact "$GATEFEAT" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
check "gh pr merge with a stale sha"     "$H" 2 "$(mkjson Bash 'gh pr merge 5 --squash' "$GATEFEAT")"
writeartifact "$GATEFEAT" "$FEATSHA"

# --- MCP branch must survive (controller ruling: the GitHub tools stay)
check "MCP merge_pull_request, no art."  "$H" 2 "$(mkjson_mcp mcp__MCP_DOCKER__merge_pull_request "$GATEREPO")"
check "MCP merge_pull_request, fresh"    "$H" 0 "$(mkjson_mcp mcp__MCP_DOCKER__merge_pull_request "$GATEFEAT")"
check "MCP github_pr_auto_merge, no art" "$H" 2 "$(mkjson_mcp mcp__github-tools__github_pr_auto_merge "$GATEREPO")"

# --- graceful degradation + kill switch
check "no Gate command configured"       "$H" 0 "$(mkjson Bash 'gh pr merge 5 --squash' "$NOGATE")"
mkdir -p "$GATEREPO/.claude" && : > "$GATEREPO/.claude/git-guard-off"
check "kill switch disables the gate"    "$H" 0 "$(mkjson Bash 'gh pr merge 5' "$GATEREPO")"
rm -f "$GATEREPO/.claude/git-guard-off"

# --- review round 1: fail-open contract on an unusable payload.
# This hook is registered on Bash|PowerShell, so a Bash call whose command we
# cannot read must NOT fall through to the artifact check -- that would block
# every Bash call in the session with "No gate artifact found".
check "Bash payload with no command"     "$H" 0 "$(mkjson_nocmd Bash "$GATEREPO")"
check "malformed JSON payload"           "$H" 0 '{not json'
check "unknown tool passes through"      "$H" 0 "$(mkjson_nocmd SomeOtherTool "$GATEREPO")"

# --- review round 1: a whole-repo push is a merge-by-push even from a feature
GATEFEAT2=$(mkrepo gatefeat2 feature/z)
printf '# ctx\n\n- **Gate**: `bash hooks/run-gate.sh`\n' > "$GATEFEAT2/PROJECT_CONTEXT.md"
check "push --mirror is a merge by push" "$H" 2 "$(mkjson Bash 'git push --mirror origin' "$GATEFEAT2")"
check "push --all is a merge by push"    "$H" 2 "$(mkjson Bash 'git push --all origin' "$GATEFEAT2")"

# --- review round 2: `git merge` while the -C TARGET is on main, cwd on feature
SPACEGATE=$(mkrepo 'gate main repo' main)
printf '# ctx\n\n- **Gate**: `bash hooks/run-gate.sh`\n' > "$SPACEGATE/PROJECT_CONTEXT.md"
check "spaced -C merge, target on main"  "$H" 2 "$(mkjson Bash "git -C \"$SPACEGATE\" merge feature" "$GATEFEAT2")"
check "gh pr merge still gated"          "$H" 2 "$(mkjson Bash 'gh pr merge 12' "$GATEREPO")"

# ===========================================================================
# block-bash-vcs.sh must be an inert no-op stub
# ===========================================================================
echo
echo "=== hooks/block-bash-vcs.sh (deprecated stub) ==="
H=hooks/block-bash-vcs.sh
check "stub allows a push to main"       "$H" 0 "$(mkjson Bash 'git push origin main' "$MAINREPO")"
check "stub allows gh pr merge"          "$H" 0 "$(mkjson Bash 'gh pr merge 5' "$MAINREPO")"

# ===========================================================================
# read-size-gate.sh — newly REGISTERED in settings.json by v2.0 (PreToolUse on
# Read). Its payload carries tool_input.file_path, not tool_input.command, so a
# regression here would misfire on every Read downstream.
# ===========================================================================
echo
echo "=== hooks/read-size-gate.sh (newly registered on Read) ==="
H=hooks/read-size-gate.sh
mkread() { # <file_path> [limit]
  node -e 'const ti={file_path:process.argv[1]}; if(process.argv[2])ti.limit=Number(process.argv[2]);
console.log(JSON.stringify({session_id:"t",hook_event_name:"PreToolUse",tool_name:"Read",tool_input:ti,cwd:process.argv[3]}))' \
    "$1" "${2:-}" "$ROOT"
}
SMALL="$TMPROOT/small.txt"; : > "$SMALL"; for i in $(seq 1 20); do echo "line $i" >> "$SMALL"; done
BIG="$TMPROOT/big.txt";     : > "$BIG";   for i in $(seq 1 900); do echo "line $i" >> "$BIG"; done

check "small file passes"                "$H" 0 "$(mkread "$SMALL")"
check "big file is blocked"              "$H" 2 "$(mkread "$BIG")"
check "big file with a small limit"      "$H" 0 "$(mkread "$BIG" 100)"
check "missing file is not blocked"      "$H" 0 "$(mkread "$TMPROOT/does-not-exist.txt")"
check "non-Read payload passes through"  "$H" 0 "$(mkjson Bash 'echo hi' "$MAINREPO")"

# ===========================================================================
echo
echo "----------------------------------------------------------------"
echo "test-hooks.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "ALL HOOK FIXTURES PASSED"
exit 0
