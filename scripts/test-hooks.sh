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

# must NOT block (exit 0)
check "push origin feature/x"            "$H" 0 "$(mkjson Bash 'git push origin feature/x' "$MAINREPO")"
check "push --force-with-lease feature"  "$H" 0 "$(mkjson Bash 'git push --force-with-lease origin feature/x' "$MAINREPO")"
check "push --tags while on main"        "$H" 0 "$(mkjson Bash 'git push --tags' "$MAINREPO")"
check "push origin :feature/x"           "$H" 0 "$(mkjson Bash 'git push origin :feature/x' "$MAINREPO")"
check "push -u origin feature/x"         "$H" 0 "$(mkjson Bash 'git push -u origin feature/x' "$MAINREPO")"
check "bare push while on feature"       "$H" 0 "$(mkjson Bash 'git push' "$FEATREPO")"
check "non-push git command"             "$H" 0 "$(mkjson Bash 'git status --short' "$MAINREPO")"
check "git -C <feat> push from main cwd" "$H" 0 "$(mkjson Bash "git -C $FEATREPO push" "$MAINREPO")"

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
