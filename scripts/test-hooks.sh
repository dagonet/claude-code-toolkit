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

# Message assertion: exit code AND an ASCII substring of the hook's stderr.
# Takes an ABSOLUTE hook path, so a copy under $TMPROOT can be exercised too.
check_msg() { # <label> <hook_abs_path> <expected_exit> <json> <needle>
  label="$1"; hookp="$2"; want="$3"; json="$4"; needle="$5"
  errf="$TMPROOT/check_msg.err"
  printf '%s' "$json" | bash "$hookp" >/dev/null 2>"$errf"
  got=$?
  if [ "$got" = "$want" ] && grep -qF "$needle" "$errf"; then
    printf 'PASS  %-42s (exit %s)\n' "$label" "$got"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s + "%s", got %s: %s)\n' \
      "$label" "$want" "$needle" "$got" "$(head -1 "$errf")"
    fail=$((fail + 1))
  fi
}

# Value assertion, for hooks whose contract is their STDOUT (updatedInput /
# updatedToolOutput) rather than their exit code.
expect() { # <label> <want> <got>
  if [ "$2" = "$3" ]; then
    printf 'PASS  %-42s (%s)\n' "$1" "$3"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s, got %s)\n' "$1" "$2" "$3"
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

# --- v2.1.1 (consumer feedback): a PROJECT_CONTEXT.md that only declares a
# **Gate** command used to make this hook a silent no-op. Fall back to Gate, and
# when neither field exists say so on stderr instead of passing in silence.
GATEONLYOK=$(mkrepo commitgateok main)
GATEONLYBAD=$(mkrepo commitgatebad main)
BOTHFIELDS=$(mkrepo commitboth main)
NOFIELDS=$(mkrepo commitnofields main)
printf '# ctx\n\n- **Gate**: `true`\n'  > "$GATEONLYOK/PROJECT_CONTEXT.md"
printf '# ctx\n\n- **Gate**: `false`\n' > "$GATEONLYBAD/PROJECT_CONTEXT.md"
printf '# ctx\n\n- **Test**: `true`\n- **Gate**: `false`\n' > "$BOTHFIELDS/PROJECT_CONTEXT.md"
printf '# ctx\n\nno commands here\n' > "$NOFIELDS/PROJECT_CONTEXT.md"

check "Gate-only context, gate passes"   "$H" 0 "$(mkjson Bash 'git commit -m x' "$GATEONLYOK")"
check "Gate-only context, gate fails"    "$H" 2 "$(mkjson Bash 'git commit -m x' "$GATEONLYBAD")"
# v2.1.3: with hooks/run-gate.sh present, a **Gate** field now takes priority
# over **Test** (run-gate.sh runs the full gate, a superset of Test alone) --
# was "Test wins over Gate when both" before run-gate.sh existed.
check "Gate (via run-gate.sh) wins over Test when both" "$H" 2 "$(mkjson Bash 'git commit -m x' "$BOTHFIELDS")"
check_msg "no Test/Gate warns, allows"   "$ROOT/hooks/pre-commit-test.sh" 0 \
  "$(mkjson Bash 'git commit -m x' "$NOFIELDS")" \
  "WARN: pre-commit-test: no Test/Gate command in PROJECT_CONTEXT.md"
check_msg "no PROJECT_CONTEXT warns too" "$ROOT/hooks/pre-commit-test.sh" 0 \
  "$(mkjson Bash 'git commit -m x' "$BARE")" \
  "WARN: pre-commit-test: no Test/Gate command in PROJECT_CONTEXT.md"

# --- v2.1.1 round 1: the block message names the command that failed (with the
# Gate fallback it is often not a test runner), and the command's own output is
# kept — swallowing it left "Fix test failures" with nothing to act on.
check_msg "block names the failed command"  "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$BADREPO")" \
  "BLOCKED: 'false' failed — re-run it and fix the failures before committing"
check_msg "gate-only block names the gate"  "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$GATEONLYBAD")" \
  "BLOCKED: 'run-gate.sh' failed"

TAILREPO=$(mkrepo committail main)
printf '# ctx\n\n- **Test**: `seq 1 40 | sed s/^/LINE/; false`\n' > "$TAILREPO/PROJECT_CONTEXT.md"
tailerr="$TMPROOT/committail.err"
printf '%s' "$(mkjson Bash 'git commit -m x' "$TAILREPO")" \
  | bash "$ROOT/hooks/pre-commit-test.sh" >/dev/null 2>"$tailerr"
expect "failure output reaches stderr"   "1" "$(grep -cx 'LINE40' "$tailerr")"
expect "failure output is tailed to 20"  "0" "$(grep -cx 'LINE1' "$tailerr")"

# --- v2.1.3 (consumer feedback, Yutraffic): run-gate.sh takes over commit-time
# gating when it exists alongside a **Gate** field. A green run must write
# .gate/last-pass.json as a side effect (so gate-before-merge is satisfied
# without a second gate run), and a red run must exit 2 naming run-gate.sh.
rm -f "$GATEONLYOK/.gate/last-pass.json"
RUNGATESHA=$(git -C "$GATEONLYOK" rev-parse HEAD)
printf '%s' "$(mkjson Bash 'git commit -m x' "$GATEONLYOK")" \
  | bash "$ROOT/hooks/pre-commit-test.sh" >/dev/null 2>&1
expect "(a) run-gate.sh path: exit 0 on pass" "0" "$?"
expect "(a) run-gate.sh path: artifact written" "1" \
  "$([ -f "$GATEONLYOK/.gate/last-pass.json" ] && echo 1 || echo 0)"
ARTSHA=$(sed -n 's/.*"sha":"\([^"]*\)".*/\1/p' "$GATEONLYOK/.gate/last-pass.json" 2>/dev/null)
expect "(a) run-gate.sh path: artifact sha matches HEAD" "$RUNGATESHA" "$ARTSHA"

check_msg "(b) run-gate.sh path: block names run-gate.sh" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$GATEONLYBAD")" \
  "BLOCKED: 'run-gate.sh' failed"

# (c) no run-gate.sh next to the hook: existing Gate/Test eval path unchanged
NORUNGATE="$TMPROOT/norungate"
mkdir -p "$NORUNGATE/lib"
cp "$ROOT/hooks/pre-commit-test.sh" "$NORUNGATE/"
cp "$ROOT/hooks/lib/git-cmd.sh" "$NORUNGATE/lib/"
check_msg "(c) no run-gate.sh: Gate command evaluated directly" "$NORUNGATE/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$GATEONLYBAD")" \
  "BLOCKED: 'false' failed"

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
# git gates: fail-closed contracts (v2.1.1, consumer sync feedback #2c/#3)
#
# Two ways a synced-but-not-restarted project turns all three gates OFF:
#   a) hooks/lib/git-cmd.sh was never materialised (sync step 6b missed the
#      sourced lib) -- every gc_* helper is undefined, GC_CMD is empty, and the
#      gates exit 0 on everything.
#   b) the running session still holds a pre-v2 settings.json that registers the
#      gates on mcp__git-tools__git_push / _commit. The v2 gates find no
#      tool_input.command and exit 0.
# Both must fail CLOSED (exit 2) with an actionable message.
# ===========================================================================
echo
echo "=== git gates: fail-closed contracts ==="

# --- a) the sourced lib is missing: copy each gate somewhere with no lib/ ----
NOLIB="$TMPROOT/nolib"
mkdir -p "$NOLIB"
cp "$ROOT/hooks/no-push-main.sh" "$ROOT/hooks/pre-commit-test.sh" \
   "$ROOT/hooks/gate-before-merge.sh" "$NOLIB/"
LIBNEEDLE='run /sync-template step 6b'

check_msg "no-push-main without lib/"     "$NOLIB/no-push-main.sh"     2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")"      "$LIBNEEDLE"
check_msg "pre-commit-test without lib/"  "$NOLIB/pre-commit-test.sh"  2 \
  "$(mkjson Bash 'git commit -m x' "$BADREPO")"            "$LIBNEEDLE"
check_msg "gate-before-merge without lib/" "$NOLIB/gate-before-merge.sh" 2 \
  "$(mkjson Bash 'gh pr merge 5 --squash' "$GATEREPO")"    "$LIBNEEDLE"

# --- b) a pre-v2 settings.json matcher reaches a v2 gate --------------------
MCPNEEDLE='settings.json predates this hook'

check_msg "no-push-main via mcp git_push"   "$ROOT/hooks/no-push-main.sh"    2 \
  "$(mkjson_mcp mcp__git-tools__git_push "$MAINREPO")"     "$MCPNEEDLE"
check_msg "no-push-main via mcp git_commit" "$ROOT/hooks/no-push-main.sh"    2 \
  "$(mkjson_mcp mcp__git-tools__git_commit "$MAINREPO")"   "$MCPNEEDLE"
check_msg "pre-commit via mcp git_commit"   "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson_mcp mcp__git-tools__git_commit "$OKREPO")"     "$MCPNEEDLE"
check_msg "pre-commit via mcp git_push"     "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson_mcp mcp__git-tools__git_push "$OKREPO")"       "$MCPNEEDLE"

# An unrelated MCP tool is not evidence of a stale settings.json -- fail open.
check "no-push-main: unrelated MCP tool"  hooks/no-push-main.sh    0 \
  "$(mkjson_mcp mcp__MCP_DOCKER__merge_pull_request "$MAINREPO")"
check "pre-commit: unrelated MCP tool"    hooks/pre-commit-test.sh 0 \
  "$(mkjson_mcp mcp__MCP_DOCKER__merge_pull_request "$BADREPO")"

# The Bash branch is untouched by either guard.
check "Bash push still blocked on main"   hooks/no-push-main.sh    2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")"
check "Bash commit still runs tests"      hooks/pre-commit-test.sh 2 \
  "$(mkjson Bash 'git commit -m x' "$BADREPO")"

# ===========================================================================
# require-skills-block.sh — v2.1.1: a project that adds its own language coder
# (cpp-coder, go-coder, …) must not fall through the binding table. The bound
# list is now "coder or <lang>-coder", not an enumeration the template owns.
# ===========================================================================
echo
echo "=== hooks/require-skills-block.sh ==="
H=hooks/require-skills-block.sh

mkspawn() { # <subagent_type> <prompt>
  node -e 'console.log(JSON.stringify({subagent_type:process.argv[1],prompt:process.argv[2]}))' "$1" "$2"
}
WITHBLOCK='Do the thing.

## Required Skills
- karpathy-guidelines
'

check "cpp-coder without skills block"   "$H" 2 "$(mkspawn cpp-coder 'Do the thing.')"
check "go-coder without skills block"    "$H" 2 "$(mkspawn go-coder 'Do the thing.')"
check "cpp-coder with skills block"      "$H" 0 "$(mkspawn cpp-coder "$WITHBLOCK")"
check "coder without skills block"       "$H" 2 "$(mkspawn coder 'Do the thing.')"
check "rust-coder without skills block"  "$H" 2 "$(mkspawn rust-coder 'Do the thing.')"
check "tester without skills block"      "$H" 2 "$(mkspawn tester 'Do the thing.')"
check "code-reviewer is unbound"         "$H" 0 "$(mkspawn code-reviewer 'Do the thing.')"
# The suffix rule must not over-match: 'coder-helper' is not a coder.
check "coder-helper is not a coder"      "$H" 0 "$(mkspawn coder-helper 'Do the thing.')"
check "unknown subagent_type passes"     "$H" 0 "$(mkspawn Explore 'Do the thing.')"

# ===========================================================================
# read-size-gate.sh — v2.0 PR3 turns the blocking gate into a CAPPING gate: an
# unbounded Read is rewritten to limit=500 via hookSpecificOutput.updatedInput
# (which REPLACES the whole tool_input, so every original field must survive).
# The hook never exits 2 any more; a regression here silently drops fields off
# every Read in the session, so the field-level assertions matter more than the
# exit code.
# ===========================================================================
echo
echo "=== hooks/read-size-gate.sh (Read cap via updatedInput) ==="
H=hooks/read-size-gate.sh
# '-' means "field absent". An EMPTY argv slot is unusable here: Git Bash drops
# it before native node sees it, which silently shifts offset into limit.
mkread() { # <file_path> [limit|-] [offset|-]
  node -e 'const ti={file_path:process.argv[1]};
if(process.argv[2]!=="-")ti.limit=Number(process.argv[2]);
if(process.argv[3]!=="-")ti.offset=Number(process.argv[3]);
console.log(JSON.stringify({session_id:"t",hook_event_name:"PreToolUse",tool_name:"Read",tool_input:ti,cwd:process.argv[4]}))' \
    "$1" "${2:--}" "${3:--}" "$ROOT"
}
readout() { # <json> -> the hook's stdout
  printf '%s' "$1" | bash "$ROOT/$H" 2>/dev/null
}
jfield() { # <json> <dotted.path> -> value, or '' when absent/unparseable
  node -e 'try{let o=JSON.parse(process.argv[1]);
for (const k of process.argv[2].split(".")) { if (o==null) break; o=o[k]; }
console.log(o===undefined||o===null?"":String(o))}catch(e){console.log("")}' "$1" "$2"
}
SMALL="$TMPROOT/small.txt"; : > "$SMALL"; for i in $(seq 1 20); do echo "line $i" >> "$SMALL"; done
HUNDRED="$TMPROOT/hundred.txt"; : > "$HUNDRED"; for i in $(seq 1 100); do echo "line $i" >> "$HUNDRED"; done
BIG="$TMPROOT/big.txt";     : > "$BIG";   for i in $(seq 1 600); do echo "line $i" >> "$BIG"; done
HUGE="$TMPROOT/huge.txt";   : > "$HUGE";  for i in $(seq 1 900); do echo "line $i" >> "$HUGE"; done
BIGPNG="$TMPROOT/big.png";  cp "$BIG" "$BIGPNG"

check "small file passes"                "$H" 0 "$(mkread "$SMALL")"
check "big file is allowed, not blocked" "$H" 0 "$(mkread "$BIG")"
check "big file with a small limit"      "$H" 0 "$(mkread "$BIG" 100)"
check "missing file is not blocked"      "$H" 0 "$(mkread "$TMPROOT/does-not-exist.txt")"
check "non-Read payload passes through"  "$H" 0 "$(mkjson Bash 'echo hi' "$MAINREPO")"

# --- an unbounded Read of a 600-line file is capped, and every original field
# survives the updatedInput replacement. file_path is compared against the
# payload's own copy: node normalises the POSIX temp path to a Windows one on
# the way in, so $BIG is not the string the hook receives.
CAPIN=$(mkread "$BIG")
CAPOUT=$(readout "$CAPIN")
expect "cap: decision is allow" "allow" "$(jfield "$CAPOUT" hookSpecificOutput.permissionDecision)"
expect "cap: limit is 500" "500" "$(jfield "$CAPOUT" hookSpecificOutput.updatedInput.limit)"
expect "cap: file_path is preserved" "$(jfield "$CAPIN" tool_input.file_path)" \
  "$(jfield "$CAPOUT" hookSpecificOutput.updatedInput.file_path)"
expect "cap: no offset key is invented" "" "$(jfield "$CAPOUT" hookSpecificOutput.updatedInput.offset)"
expect "cap: additionalContext names the next offset" 1 \
  "$(printf '%s' "$CAPOUT" | grep -c 'pass offset=500 to continue')"

# --- offset must be honoured, not ignored (the pre-PR3 bug), and preserved.
# 900 - 200 = 700 remaining lines, so this one still gets capped.
OFFOUT=$(readout "$(mkread "$HUGE" - 200)")
expect "offset: limit is 500" "500" "$(jfield "$OFFOUT" hookSpecificOutput.updatedInput.limit)"
expect "offset: offset is preserved" "200" "$(jfield "$OFFOUT" hookSpecificOutput.updatedInput.offset)"
expect "offset: next offset is 700" 1 \
  "$(printf '%s' "$OFFOUT" | grep -c 'pass offset=700 to continue')"
# 600 - 400 = 200 remaining lines: under the cap. The pre-PR3 script ignored
# offset and would have judged this by the file's full length.
expect "offset near EOF is left alone" "" "$(readout "$(mkread "$BIG" - 400)")"

# --- the caller already bounded the read, the file is small, or the payload is
# not a text file: the hook stays silent.
expect "explicit limit is left alone" "" "$(readout "$(mkread "$BIG" 50)")"
expect "100-line file is left alone" "" "$(readout "$(mkread "$HUNDRED")")"
expect "image extension is skipped" "" "$(readout "$(mkread "$BIGPNG")")"
expect "missing file emits nothing" "" "$(readout "$(mkread "$TMPROOT/does-not-exist.txt")")"

# --- fix round 1: a very large file must be capped WITHOUT counting its lines
# first. `wc -l` scans the whole file before the decision, on a hook that runs
# on every Read. Over 10 MB the size alone decides.
GIANT="$TMPROOT/giant.txt"
if command -v truncate >/dev/null 2>&1; then
  truncate -s 12M "$GIANT" 2>/dev/null
else
  node -e 'const fs=require("fs");const fd=fs.openSync(process.argv[1],"w");fs.ftruncateSync(fd,12*1024*1024);fs.closeSync(fd)' "$GIANT"
fi
GIANTOUT=$(readout "$(mkread "$GIANT")")
expect "giant file: limit is 500" "500" "$(jfield "$GIANTOUT" hookSpecificOutput.updatedInput.limit)"
expect "giant file: context reports the size, not a line count" 1 \
  "$(printf '%s' "$GIANTOUT" | grep -c 'File is 12 MB; capped at 500 lines')"
expect "giant file: no line count is claimed" 0 \
  "$(printf '%s' "$GIANTOUT" | grep -c 'of 0 lines')"

# --- the ctx-tool advice the blocking version printed is gone for good.
expect "no context-mode advice in the hook" 0 \
  "$(grep -c 'ctx_execute_file' "$ROOT/hooks/read-size-gate.sh")"

# ===========================================================================
# bash-output-guard.sh (PostToolUse on Bash|PowerShell) — v2.0 PR3.
# The payload shape below was observed from a real PostToolUse Bash event:
# tool_response = {stdout, stderr, interrupted, isImage, noOutputExpected}.
# updatedToolOutput must keep that shape — a wrong shape corrupts every Bash
# result downstream, so the sibling fields are asserted, not just stdout.
# ===========================================================================
echo
echo "=== hooks/bash-output-guard.sh (PostToolUse output cap) ==="
GUARD=hooks/bash-output-guard.sh
GUARDTMP="$TMPROOT/guardtmp"
mkdir -p "$GUARDTMP"

mkpost() { # <stdout_length> [stderr_length]
  node -e 'console.log(JSON.stringify({session_id:"guardsess",hook_event_name:"PostToolUse",
tool_name:"Bash",tool_input:{command:"echo hi"},cwd:process.argv[3],
tool_response:{stdout:"A".repeat(Number(process.argv[1])),stderr:"B".repeat(Number(process.argv[2])),
interrupted:false,isImage:false,noOutputExpected:false},
tool_use_id:"toolu_x",duration_ms:5}))' "$1" "${2:-0}" "$ROOT"
}
runguard() { # <json> -> hook stdout
  printf '%s' "$1" | TMPDIR="$GUARDTMP" bash "$ROOT/$GUARD" 2>/dev/null
}

BIGOUT=$(runguard "$(mkpost 20000)")
expect "guard: emits updatedToolOutput" "PostToolUse" \
  "$(jfield "$BIGOUT" hookSpecificOutput.hookEventName)"
expect "guard: truncation marker names the log" 1 \
  "$(printf '%s' "$BIGOUT" | grep -c 'chars truncated — full output:')"
expect "guard: sibling fields survive" "false" \
  "$(jfield "$BIGOUT" hookSpecificOutput.updatedToolOutput.interrupted)"
GUARDLEN=$(node -e 'try{let o=JSON.parse(process.argv[1]);console.log(o.hookSpecificOutput.updatedToolOutput.stdout.length)}catch(e){console.log(-1)}' "$BIGOUT")
expect "guard: 20 000 chars are cut down" 1 \
  "$( [ "$GUARDLEN" -gt 8000 ] && [ "$GUARDLEN" -lt 9000 ] && echo 1 || echo 0 )"
expect "guard: head is preserved" 1 \
  "$(node -e 'try{let o=JSON.parse(process.argv[1]);let s=o.hookSpecificOutput.updatedToolOutput.stdout;
console.log(s.slice(0,4000)==="A".repeat(4000)&&s.slice(-4000)==="A".repeat(4000)?1:0)}catch(e){console.log(0)}' "$BIGOUT")"
expect "guard: full output is on disk" 1 \
  "$(find "$GUARDTMP/claude-bash-out" -name 'guardsess-*.log' 2>/dev/null | wc -l | tr -d ' ')"
expect "guard: the log holds all 20 000 chars" 20000 \
  "$(wc -c < "$(find "$GUARDTMP/claude-bash-out" -name 'guardsess-*.log' 2>/dev/null | head -1)" | tr -d ' ')"

expect "guard: 5 000 chars pass through" "" "$(runguard "$(mkpost 5000)")"
expect "guard: malformed payload is silent" "" "$(runguard '{not json')"

# --- fix round 1: the payload must reach node on STDIN, not in argv. Linux caps
# a single argument at 128 KiB and Windows CreateProcess caps the whole command
# line at 32,767 chars, so an argv-passed 200 KB build log — exactly the case
# this hook exists for — fails to exec and passes through untruncated.
HUGEOUT=$(runguard "$(mkpost 200000)")
expect "guard: 200 KB payload still truncates" "500" \
  "$(node -e 'try{let o=JSON.parse(process.argv[1]);console.log(o.hookSpecificOutput.updatedToolOutput.stdout.length<10000?500:0)}catch(e){console.log(-1)}' "$HUGEOUT")"
expect "guard: 200 KB full output is on disk" 200000 \
  "$(wc -c < "$(find "$GUARDTMP/claude-bash-out" -name 'guardsess-*.log' -size +100k 2>/dev/null | head -1)" | tr -d ' ')"

# --- fix round 1: stderr is an output stream too. A 20 KB stderr with a tiny
# stdout was passed through whole.
ERROUT=$(runguard "$(mkpost 100 20000)")
expect "guard: stderr is truncated too" 1 \
  "$(node -e 'try{let s=JSON.parse(process.argv[1]).hookSpecificOutput.updatedToolOutput.stderr;
console.log(s.length<10000&&s.slice(0,4000)==="B".repeat(4000)&&s.indexOf("chars truncated")>0?1:0)}catch(e){console.log(0)}' "$ERROUT")"
expect "guard: small stdout survives untouched" 100 \
  "$(node -e 'try{console.log(JSON.parse(process.argv[1]).hookSpecificOutput.updatedToolOutput.stdout.length)}catch(e){console.log(-1)}' "$ERROUT")"
expect "guard: stderr gets its own log file" 1 \
  "$(find "$GUARDTMP/claude-bash-out" -name '*-stderr.log' 2>/dev/null | wc -l | tr -d ' ')"
printf '%s' "$(mkpost 20000)" | TMPDIR="$GUARDTMP" bash "$ROOT/$GUARD" >/dev/null 2>&1
expect "guard: always exits 0" 0 $?

# ===========================================================================
# retro-ledger.sh (SubagentStop) + retro-brief.sh (SessionStart) — v2.0 PR2.
# The ledger records subagent failures (dead tools, hook blocks) under the
# project's auto-memory dir; the brief replays the last 10 at session start.
# Both are fail-open by construction: they must NEVER exit non-zero.
# ===========================================================================
echo
echo "=== hooks/retro-ledger.sh + hooks/retro-brief.sh ==="

RETROHOME="$TMPROOT/retrohome"
PROJCWD="G:/git/retroproj"
SLUGDIR="$RETROHOME/.claude/projects/G--git-retroproj/memory"

mkstop() { # <cwd> <agent_type> <agent_id> <transcript_path>
  node -e 'console.log(JSON.stringify({session_id:"t",hook_event_name:"SubagentStop",cwd:process.argv[1],agent_type:process.argv[2],agent_id:process.argv[3],agent_transcript_path:process.argv[4],last_assistant_message:"done"}))' \
    "$1" "$2" "$3" "$4"
}

mkstart() { # <cwd>
  node -e 'console.log(JSON.stringify({session_id:"t",hook_event_name:"SessionStart",source:"startup",cwd:process.argv[1]}))' "$1"
}

# A subagent transcript with (a) a dead-tool tool_result and (b) a hook block.
# Wording copied verbatim from a real transcript:
#   ~/.claude/projects/G--git-claude-code-toolkit/<session>/subagents/
#   agent-a003c937d78f9f557.jsonl
mktranscript() { # <path>
  node -e '
const fs=require("fs");
const rows=[
 {type:"user",message:{role:"user",content:[{type:"tool_result",is_error:true,
   content:"<tool_use_error>Error: No such tool available: mcp__x__y. mcp__x__y is disabled for this session, in subagents as well as here.</tool_use_error>"}]}},
 {type:"user",message:{role:"user",content:[{type:"tool_result",is_error:true,
   content:"PreToolUse:Bash hook error: [bash \u0027hooks/enforce-delegation.sh\u0027]: DELEGATE: the PO does not do hands-on work."}]}},
 {type:"assistant",message:{role:"assistant",content:[{type:"text",text:"No such tool available in prose must not count"}]}}
];
fs.writeFileSync(process.argv[1], rows.map(r=>JSON.stringify(r)).join("\n")+"\n");
' "$1"
}

# --- 1. a transcript with failures appends exactly one ledger line
mkdir -p "$RETROHOME"
TRANSCRIPT="$TMPROOT/agent-fixture.jsonl"
mktranscript "$TRANSCRIPT"
mkstop "$PROJCWD" coder agent-abc123 "$TRANSCRIPT" \
  | HOME="$RETROHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "retro-ledger exits 0" 0 $?
expect "ledger writes to the slug path" 1 "$( [ -f "$SLUGDIR/retro.md" ] && echo 1 || echo 0 )"
expect "ledger appends exactly one line" 1 "$(wc -l < "$SLUGDIR/retro.md" 2>/dev/null | tr -d ' ')"
expect "ledger records the dead tool" 1 \
  "$(grep -c 'dead=\[mcp__x__y\]' "$SLUGDIR/retro.md" 2>/dev/null)"
expect "ledger records the hook basename" 1 \
  "$(grep -c 'blocks=\[enforce-delegation.sh\]' "$SLUGDIR/retro.md" 2>/dev/null)"
expect "ledger counts both failures" 1 \
  "$(grep -c 'errors=2' "$SLUGDIR/retro.md" 2>/dev/null)"
expect "ledger records agent type + id" 1 \
  "$(grep -c '| coder | agent-abc123 |' "$SLUGDIR/retro.md" 2>/dev/null)"

# --- 2. a missing transcript is silent: exit 0, nothing written
CLEANHOME="$TMPROOT/retrohome-clean"
mkdir -p "$CLEANHOME"
mkstop "$PROJCWD" tester agent-none "$TMPROOT/does-not-exist.jsonl" \
  | HOME="$CLEANHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "missing transcript exits 0" 0 $?
expect "missing transcript writes nothing" 0 \
  "$(find "$CLEANHOME" -name retro.md 2>/dev/null | wc -l | tr -d ' ')"

# --- 3. a clean transcript (no failures) writes nothing
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"all good"}]}}' \
  > "$TMPROOT/agent-clean.jsonl"
mkstop "$PROJCWD" coder agent-clean "$TMPROOT/agent-clean.jsonl" \
  | HOME="$CLEANHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "clean transcript exits 0" 0 $?
expect "clean transcript writes nothing" 0 \
  "$(find "$CLEANHOME" -name retro.md 2>/dev/null | wc -l | tr -d ' ')"

# --- 4. malformed stdin must never break a SubagentStop
printf '%s' '{not json' | HOME="$CLEANHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "malformed payload exits 0" 0 $?

# --- 5. the slug rule is Claude Code's auto-memory rule, measured against
# ~/.claude/projects: every one of : \ / . _ becomes '-'. Both the Windows and
# the forward-slash spelling of the same cwd must land in the SAME directory.
BSHOME="$TMPROOT/retrohome-bs"
mkdir -p "$BSHOME"
mkstop 'G:\git\retroproj' coder agent-bs "$TRANSCRIPT" \
  | HOME="$BSHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "backslash cwd slugs identically" 1 \
  "$( [ -f "$BSHOME/.claude/projects/G--git-retroproj/memory/retro.md" ] && echo 1 || echo 0 )"

# --- 6. retro-brief prints exactly the last 10 lines of a 12-line ledger
BRIEFHOME="$TMPROOT/retrohome-brief"
BRIEFDIR="$BRIEFHOME/.claude/projects/G--git-retroproj/memory"
mkdir -p "$BRIEFDIR"
: > "$BRIEFDIR/retro.md"
i=1; while [ "$i" -le 12 ]; do echo "entry-$i" >> "$BRIEFDIR/retro.md"; i=$((i + 1)); done
BRIEFOUT="$TMPROOT/brief.out"
mkstart "$PROJCWD" | HOME="$BRIEFHOME" bash "$ROOT/hooks/retro-brief.sh" > "$BRIEFOUT" 2>/dev/null
expect "retro-brief exits 0" 0 $?
expect "brief prints the RETRO header" 1 "$(grep -c '^RETRO ' "$BRIEFOUT")"
expect "brief prints 10 entries" 10 "$(grep -c '^entry-' "$BRIEFOUT")"
expect "brief starts at entry-3" 1 "$(grep -c '^entry-3$' "$BRIEFOUT")"
expect "brief drops entry-2" 0 "$(grep -c '^entry-2$' "$BRIEFOUT")"

# --- 7. no ledger for this project: the brief is silent and still exits 0
mkstart 'G:/git/no-such-project' | HOME="$BRIEFHOME" bash "$ROOT/hooks/retro-brief.sh" > "$BRIEFOUT" 2>/dev/null
expect "brief with no ledger exits 0" 0 $?
expect "brief with no ledger prints nothing" 0 "$(wc -c < "$BRIEFOUT" | tr -d ' ')"

# --- 8a. review round 1: a SUCCESSFUL tool_result whose output merely CONTAINS
# "BLOCKED:" (reading hooks/*.sh, grepping this very file) is not a failure. Only
# is_error results, or text that is itself a hook-block message, count.
node -e '
const fs=require("fs");
const rows=[
 {type:"user",message:{role:"user",content:[{type:"tool_result",
   content:"1: echo \u0027BLOCKED: use the MCP tool\u0027\n2: BLOCKED: another quoted line\n"}]}},
 {type:"user",message:{role:"user",content:[{type:"tool_result",
   content:"file listing mentioning hooks/no-push-main.sh and DELEGATE: in prose"}]}}
];
fs.writeFileSync(process.argv[1], rows.map(r=>JSON.stringify(r)).join("\n")+"\n");
' "$TMPROOT/agent-falsepos.jsonl"
FPHOME="$TMPROOT/retrohome-fp"
mkdir -p "$FPHOME"
mkstop "$PROJCWD" coder agent-fp "$TMPROOT/agent-falsepos.jsonl" \
  | HOME="$FPHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "successful output is not a failure" 0 \
  "$(find "$FPHOME" -name retro.md 2>/dev/null | wc -l | tr -d ' ')"

# ... but a real hook block still counts even without is_error, and its script
# name comes from the bracketed hook command, not from any .sh token in the text.
node -e '
const fs=require("fs");
const rows=[
 {type:"user",message:{role:"user",content:[{type:"tool_result",
   content:"PreToolUse:Bash hook error: [bash \u0027hooks/no-push-main.sh\u0027]: BLOCKED: push to main."}]}},
 {type:"user",message:{role:"user",content:[{type:"tool_result",is_error:true,
   content:"<tool_use_error>Error: No such tool available: mcp__x__y. Mentions scripts/test-hooks.sh in prose.</tool_use_error>"}]}}
];
fs.writeFileSync(process.argv[1], rows.map(r=>JSON.stringify(r)).join("\n")+"\n");
' "$TMPROOT/agent-block.jsonl"
BKHOME="$TMPROOT/retrohome-block"
mkdir -p "$BKHOME"
mkstop "$PROJCWD" coder agent-bk "$TMPROOT/agent-block.jsonl" \
  | HOME="$BKHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
BKLEDGER="$BKHOME/.claude/projects/G--git-retroproj/memory/retro.md"
expect "hook block counts without is_error" 1 \
  "$(grep -c 'errors=2' "$BKLEDGER" 2>/dev/null)"
expect "block name comes from the hook command" 1 \
  "$(grep -c 'blocks=\[no-push-main.sh\]' "$BKLEDGER" 2>/dev/null)"

# --- 8b. review round 1: the ledger line is bounded. 12 distinct dead tools must
# render as 5 names + a "+7 more" marker, not a 12-entry line.
node -e '
const fs=require("fs");
const rows=[];
for (let i=1;i<=12;i++){
  rows.push({type:"user",message:{role:"user",content:[{type:"tool_result",is_error:true,
    content:"<tool_use_error>Error: No such tool available: mcp__t"+String(i).padStart(2,"0")+"__x.</tool_use_error>"}]}});
}
fs.writeFileSync(process.argv[1], rows.map(r=>JSON.stringify(r)).join("\n")+"\n");
' "$TMPROOT/agent-many.jsonl"
MANYHOME="$TMPROOT/retrohome-many"
mkdir -p "$MANYHOME"
mkstop "$PROJCWD" coder agent-many "$TMPROOT/agent-many.jsonl" \
  | HOME="$MANYHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
MANYLEDGER="$MANYHOME/.claude/projects/G--git-retroproj/memory/retro.md"
expect "dead list is capped at 5 names" 1 \
  "$(grep -c 'dead=\[mcp__t01__x,mcp__t02__x,mcp__t03__x,mcp__t04__x,mcp__t05__x,+7 more\]' "$MANYLEDGER" 2>/dev/null)"
expect "capped line stays short" 1 \
  "$( [ "$(wc -c < "$MANYLEDGER" 2>/dev/null | tr -d ' ')" -lt 200 ] && echo 1 || echo 0 )"

# --- 8c. review round 1: retro-brief truncates each entry, so one pathological
# ledger line cannot flood the session context it is injected into.
LONGHOME="$TMPROOT/retrohome-long"
LONGDIR="$LONGHOME/.claude/projects/G--git-retroproj/memory"
mkdir -p "$LONGDIR"
node -e 'require("fs").writeFileSync(process.argv[1],"X".repeat(500)+"\n")' "$LONGDIR/retro.md"
mkstart "$PROJCWD" | HOME="$LONGHOME" bash "$ROOT/hooks/retro-brief.sh" > "$TMPROOT/long.out" 2>/dev/null
expect "brief truncates a 500-char entry" 1 \
  "$( [ "$(awk 'NR==2{print length($0)}' "$TMPROOT/long.out")" -le 200 ] && echo 1 || echo 0 )"

# --- 8d. review round 1: a POSIX-style HOME (/c/tmp/...) must not be resolved
# drive-relative by Windows node — that would silently write the ledger outside
# the auto-memory tree. The round-trip fixture cannot catch this: both hooks
# would share the bug. Asserted with the same spelling bash uses, so the case
# holds on Windows (where /c/x is C:\x) and on POSIX alike.
POSIXHOME="/c/tmp/claude-retro-fixture"
rm -rf "$POSIXHOME"
mkstop "$PROJCWD" coder agent-posix "$TRANSCRIPT" \
  | HOME="$POSIXHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "POSIX-style HOME resolves correctly" 1 \
  "$( [ -f "$POSIXHOME/.claude/projects/G--git-retroproj/memory/retro.md" ] && echo 1 || echo 0 )"
rm -rf "$POSIXHOME"

# CLAUDE_MEMORY_HOME overrides HOME for both hooks (the shared base-dir helper).
OVERHOME="$TMPROOT/retrohome-override"
mkdir -p "$OVERHOME"
mkstop "$PROJCWD" coder agent-over "$TRANSCRIPT" \
  | HOME="$TMPROOT/retrohome-ignored" CLAUDE_MEMORY_HOME="$OVERHOME" \
    bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "CLAUDE_MEMORY_HOME wins over HOME" 1 \
  "$( [ -f "$OVERHOME/.claude/projects/G--git-retroproj/memory/retro.md" ] && echo 1 || echo 0 )"
mkstart "$PROJCWD" | HOME="$TMPROOT/retrohome-ignored" CLAUDE_MEMORY_HOME="$OVERHOME" \
  bash "$ROOT/hooks/retro-brief.sh" > "$TMPROOT/over.out" 2>/dev/null
expect "brief honours CLAUDE_MEMORY_HOME too" 1 "$(grep -c 'agent-over' "$TMPROOT/over.out")"

# --- 8. round trip: the two hooks must agree on the slug, or the feature is a
# silent no-op in production. Ledger writes, brief reads, same cwd, same HOME.
RTHOME="$TMPROOT/retrohome-rt"
mkdir -p "$RTHOME"
mkstop "$PROJCWD" code-reviewer agent-rt99 "$TRANSCRIPT" \
  | HOME="$RTHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
mkstart "$PROJCWD" | HOME="$RTHOME" bash "$ROOT/hooks/retro-brief.sh" > "$BRIEFOUT" 2>/dev/null
expect "round trip: brief replays the entry" 1 "$(grep -c 'agent-rt99' "$BRIEFOUT")"

# ===========================================================================
echo
echo "----------------------------------------------------------------"
echo "test-hooks.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "ALL HOOK FIXTURES PASSED"
exit 0
