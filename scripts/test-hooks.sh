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
#
# Reproducing a WARN case by hand: give each invocation its own TMPDIR.
# json_warn_once writes ${TMPDIR:-/tmp}/claude-hook-warn-<hook>[-<session>] and
# stays quiet while that marker exists (per session, else for an hour), so a
# second run at the prompt prints nothing and looks like a regression.
# check_env below rebuilds $WARNTMP for exactly this reason.

set -u
pass=0
fail=0
# Assertions not run because the backend they exercise is absent on this host
# (python3-only / jq-only / node-only cases). Reported, never a failure.
skipped=0

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
  # v2.1.5: real projects gitignore the gate artifact (every templates/*/gitignore
  # and the toolkit's own .gitignore do). run-gate.sh keys the artifact on a
  # temp-index `add -A` of the working tree, which honours .gitignore -- without
  # this the artifact it just wrote would perturb the NEXT run's tree.
  printf '.gate/\n' > "$d/.gitignore"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -q -m seed >/dev/null 2>&1
  # normalise the initial branch name across git versions
  git -C "$d" branch -M main >/dev/null 2>&1
  if [ "$2" != "main" ]; then
    git -C "$d" checkout -q -b "$2" >/dev/null 2>&1
  fi
  printf '%s\n' "$d"
}

# --- payload construction, without an interpreter ---------------------------
#
# v2.2.1: every builder below was a `node -e` one-liner. On a node-less host
# node printed nothing, so EVERY payload was the empty string, every hook read
# an empty stdin and exited 0, and the suite reported 128 FAILURES that were
# all the harness -- the same silent-no-parser bug v2.2.0 fixed in the hooks,
# sitting in the fixture that guards them. Reported 2026-08-29 (WSL field run).
#
# The payloads are fixed shapes with a handful of interpolated values, so they
# are built with printf plus a sed-based string escaper: no interpreter at all,
# not even the node/python3/jq trio hooks/lib/json.sh chooses from. That is
# deliberate. Reading a hook's JSON *output* does go through json.sh (jfield,
# below) -- but a BUILDER sharing the reader's backend could let a broken lib
# make the git-gate fixtures pass vacuously, which is the one failure mode this
# suite must never have.
#
# Out of fixture scope, and asserted nowhere: control characters other than
# newline, and lone surrogates. No fixture contains one.
jesc() { # <string> -> the string as a JSON string BODY (no surrounding quotes)
  # The trailing '.' is a sentinel: `$(...)` strips trailing newlines, so a
  # value ending in one would silently round-trip a byte short without it.
  je=$(printf '%s.' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g')
  printf '%s' "${je%.}"
}

# Claude Code hands a hook the NATIVE spelling of a path. The old `node -e`
# builders normalised a Git Bash /tmp path to a Windows one for free on the way
# in; printf does not, and the embedded node program inside read-size-gate /
# retro-ledger cannot stat `/tmp/...` on Windows. So the conversion the builders
# used to get by accident is explicit now. A no-op off Windows.
natpath() { # <path> -> the same path as the platform spells it
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

nchars() { # <count> <char> -- <count> copies of <char> (replaces "X".repeat(n))
  [ "${1:-0}" -gt 0 ] || return 0
  printf '%*s' "$1" '' | tr ' ' "$2"
}

mkjson() { # <tool_name> <command> <cwd>
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"},"cwd":"%s"}\n' \
    "$(jesc "$1")" "$(jesc "$2")" "$(jesc "$3")"
}

mkjson_mcp() { # <tool_name> <cwd> -- MCP payload carries no tool_input.command
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"owner":"o","repo":"r","pullNumber":1},"cwd":"%s"}\n' \
    "$(jesc "$1")" "$(jesc "$2")"
}

mkjson_nocmd() { # <tool_name> <cwd> -- a payload whose command we cannot read
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{},"cwd":"%s"}\n' \
    "$(jesc "$1")" "$(jesc "$2")"
}

mkspawn() { # <subagent_type> <prompt>
  printf '{"subagent_type":"%s","prompt":"%s"}\n' "$(jesc "$1")" "$(jesc "$2")"
}

mkread() { # <file_path> [limit|-] [offset|-] -- '-' means "field absent"
  mr='"file_path":"'"$(jesc "$(natpath "$1")")"'"'
  [ "${2:--}" = "-" ] || mr="$mr,\"limit\":$2"
  [ "${3:--}" = "-" ] || mr="$mr,\"offset\":$3"
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{%s},"cwd":"%s"}\n' \
    "$mr" "$(jesc "$ROOT")"
}

mkpost() { # <stdout_length> [stderr_length] -- a PostToolUse Bash result
  printf '{"session_id":"guardsess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"%s","tool_response":{"stdout":"%s","stderr":"%s","interrupted":false,"isImage":false,"noOutputExpected":false},"tool_use_id":"toolu_x","duration_ms":5}\n' \
    "$(jesc "$ROOT")" "$(nchars "$1" A)" "$(nchars "${2:-0}" B)"
}

mkstop() { # <cwd> <agent_type> <agent_id> <transcript_path>
  # cwd is asserted verbatim (the slug rule is exercised with both spellings),
  # so only the transcript path -- which the hook must actually open -- is
  # converted to the native form.
  # v2.2.2: BOTH transcript fields, as the live payload carries them. With only
  # agent_transcript_path set, a hook that reads transcript_path gets an empty
  # value and fails OPEN -- so every want-0 assertion would pass vacuously,
  # against a hook that never opened a transcript at all.
  printf '{"session_id":"t","hook_event_name":"SubagentStop","cwd":"%s","agent_type":"%s","agent_id":"%s","agent_transcript_path":"%s","transcript_path":"%s","last_assistant_message":"done"}\n' \
    "$(jesc "$1")" "$(jesc "$2")" "$(jesc "$3")" \
    "$(jesc "$(natpath "$4")")" "$(jesc "$(natpath "$4")")"
}

mkstart() { # <cwd>
  printf '{"session_id":"t","hook_event_name":"SessionStart","source":"startup","cwd":"%s"}\n' "$(jesc "$1")"
}

# --- subagent transcript rows (JSONL), for the retro-ledger fixtures --------
trow_err() { # <content> -> an is_error tool_result row
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","is_error":true,"content":"%s"}]}}\n' "$(jesc "$1")"
}
trow_ok() { # <content> -> a SUCCESSFUL tool_result row (no is_error)
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"%s"}]}}\n' "$(jesc "$1")"
}
trow_text() { # <text> -> an assistant prose row
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$(jesc "$1")"
}

# v2.2.2: the SAME assistant turn as trow_text, in the OTHER wire shape. A
# text-only assistant turn -- which every compliant final report is -- serializes
# message.content as a plain STRING, not an array of blocks. A reader that only
# handles the array shape silently skips it; that was the enforce-agent-contract
# defect, and it is why both shapes are fixtured from here on.
trow_str() { # <text> -> an assistant prose row with STRING content
  printf '{"type":"assistant","message":{"role":"assistant","content":"%s"}}\n' "$(jesc "$1")"
}

# An assistant turn that is tool_use ONLY: array content, no text block. The
# agent stopped mid-tool-call, so there is no report -- non-compliant by design.
trow_tool() { # -> an assistant tool_use-only row
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{}}]}}\n'
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
  # Fresh TMPDIR per case. json_warn_once stays silent while its marker exists,
  # and a SESSION-keyed marker never expires — a shared TMPDIR would make any
  # WARN assertion pass on the first run of the suite and fail on every later
  # one, on the same machine, for no reason visible in the diff.
  cmtmp="$TMPROOT/check_msg.tmp"; rm -rf "$cmtmp"; mkdir -p "$cmtmp"
  printf '%s' "$json" | TMPDIR="$cmtmp" bash "$hookp" >/dev/null 2>"$errf"
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

# A block whose backend is absent on this host SKIPs: reported, never a
# failure, and the tally counts ASSERTIONS (not blocks) so the totals still
# add up to the same suite size on every host.
skip() { # <label> <reason> [assertion-count]
  skipped=$((skipped + ${3:-1}))
  printf 'SKIP  %-42s (%s, %s assertion(s))\n' "$1" "$2" "${3:-1}"
}

# Probed here, not further down, because the first block that needs them is
# read-size-gate's -- six hooks (read-size-gate, bash-output-guard,
# enforce-delegation, retro-ledger, retro-brief, enforce-agent-contract's
# transcript scan) are embedded node PROGRAMS, not field reads: json.sh's
# json_require_node makes them warn and pass with no node. Their fixtures
# assert enforcement, so on a node-less host they must SKIP, not fail.
HAVE_NODE=1; command -v node    >/dev/null 2>&1 || HAVE_NODE=""
HAVE_PY=1;   command -v python3 >/dev/null 2>&1 || HAVE_PY=""
HAVE_JQ=1;   command -v jq      >/dev/null 2>&1 || HAVE_JQ=""

# The JSON READER the assertions use is the hooks' own lib -- so the suite is
# self-testing for the mechanism it guards. Safe here precisely because the
# builders above share none of its backends.
. "$ROOT/hooks/lib/json.sh"
jfield() { # <json> <dotted.path> -> value, or '' when absent/unparseable
  json_get "$1" "$2"
}

# ===========================================================================
# payload builder self-check -- FIRST, before any fixture depends on it.
#
# A wrong escape would not fail loudly: it would hand every hook a payload that
# parses to the wrong value, or to nothing at all, and the failures would
# surface 800 lines away as "the hook is broken". Every value class the
# fixtures actually use is round-tripped builder -> reader here.
# ===========================================================================
echo "=== payload builders (jesc round-trip) ==="
RT_EM='git push origin main # rationale — see PR'
RT_BS='G:\git\retroproj'
RT_DQ='git -C "/tmp/a b" push'
RT_ML='Do the thing.

## Required Skills
- karpathy-guidelines'
expect "jesc: em dash round-trips"      "$RT_EM" "$(jfield "$(mkjson Bash "$RT_EM" /x)" tool_input.command)"
expect "jesc: backslashes round-trip"   "$RT_BS" "$(jfield "$(mkjson Bash "$RT_BS" /x)" tool_input.command)"
expect "jesc: double quotes round-trip" "$RT_DQ" "$(jfield "$(mkjson Bash "$RT_DQ" /x)" tool_input.command)"
# CR is stripped on the way back: jq's stdout is in TEXT mode on Windows, so it
# turns some of the LFs it writes into CRLF. That is the reader's platform, not
# the builder's escaping, and MSYS grep's `$` tolerates the stray CR (asserted
# for real by "jq: skills block present passes" further down).
expect "jesc: newlines round-trip"      "$RT_ML" \
  "$(jfield "$(mkspawn coder "$RT_ML")" prompt | tr -d '\r')"
# `$(...)` eats trailing newlines, so the round-trip above cannot see one. The
# sentinel in jesc is what keeps it; asserted on the raw payload instead.
RT_TRAIL='a
'
expect "jesc: trailing newline survives" 1 \
  "$(printf '%s' "$(mkspawn coder "$RT_TRAIL")" | grep -c '"prompt":"a\\n"')"

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
check "malformed JSON payload"           "$H" 2 '{not json'
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
# v2.2.1: the success path DELETES its captured output, so "I saw no test
# output" is not evidence the suite did not run -- the elapsed seconds are the
# only external discriminator between a real run and a hook that fell through
# its own guards. Asserted on the shape, not the number, which is a real clock.
check_msg "success names the elapsed seconds" "$ROOT/$H" 0 \
  "$(mkjson Bash 'git commit -m "x"' "$OKREPO")" "passed. ("
# v2.1.3 fix round 2 item 5: a Test-path commit (the common case -- 5 of 6
# templates ship a **Test** line) never touches run-gate.sh or its artifact.
# gate-before-merge.sh still needs a separate `bash hooks/run-gate.sh` before
# merging a Test-path repo.
expect "(R2-5) Test-path commit leaves no gate artifact" "0" \
  "$([ -f "$OKREPO/.gate/last-pass.json" ] && echo 1 || echo 0)"
check "commit with failing tests"        "$H" 2 "$(mkjson Bash 'git commit -m "x"' "$BADREPO")"
check "commit with no PROJECT_CONTEXT"   "$H" 0 "$(mkjson Bash 'git commit -m "x"' "$BARE")"
check "non-commit git command"           "$H" 0 "$(mkjson Bash 'git status --short' "$BADREPO")"
check "git add is not a commit"          "$H" 0 "$(mkjson Bash 'git add -A' "$BADREPO")"
check "git -c ... commit"                "$H" 2 "$(mkjson Bash 'git -c user.name=x commit -m y' "$BADREPO")"
check "commit wrapped in bash -c"        "$H" 2 "$(mkjson Bash 'bash -c "git commit -m x"' "$BADREPO")"
check "git -C <bad> commit from ok cwd"  "$H" 2 "$(mkjson Bash "git -C $BADREPO commit -m y" "$OKREPO")"
check "PowerShell commit, failing tests" "$H" 2 "$(mkjson PowerShell 'git commit -m "x"' "$BADREPO")"
check "malformed JSON payload"           "$H" 2 '{not json'
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
# v2.1.3 fix round 1 (precedence ruling): **Test** wins when present -- cheap
# commit path, unchanged behaviour. run-gate.sh is only consulted when there is
# no Test line. BOTHFIELDS declares Test: true, Gate: false -- Test must win
# (exit 0), even though the Gate command alone would fail.
check "Test wins over Gate when both"    "$H" 0 "$(mkjson Bash 'git commit -m x' "$BOTHFIELDS")"
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
ARTTREE=$(sed -n 's/.*"tree":"\([^"]*\)".*/\1/p' "$GATEONLYOK/.gate/last-pass.json" 2>/dev/null)
# v2.1.5: the recorded tree is the WORKING tree at gate time (PROJECT_CONTEXT.md
# was still untracked when the hook fired). Committing exactly what was gated --
# `git add -A && git commit` -- reproduces it as HEAD^{tree}.
git -C "$GATEONLYOK" add -A >/dev/null 2>&1
git -C "$GATEONLYOK" commit -q -m "gated commit" >/dev/null 2>&1
RUNGATETREE=$(git -C "$GATEONLYOK" rev-parse 'HEAD^{tree}')
expect "(a) run-gate.sh path: artifact tree matches committed tree" "$RUNGATETREE" "$ARTTREE"

# --- v2.1.5 (consumer feedback, Yutraffic PR #223): the artifact keys on the
# WORKING TREE, not the index. v2.1.3 recorded no tree at all when the working
# tree had unstaged changes -- but that is the ordinary agent shape (the
# PreToolUse hook fires before a chained `git add && git commit` stages
# anything), so the artifact matched nothing and the single-run merge path never
# fired. The positive form: unstaged change at gate time, `git commit -a`
# after -> the recorded tree IS the committed tree.
DIRTYGATE=$(mkrepo commitdirtygate main)
printf '# ctx\n\n- **Gate**: `true`\n' > "$DIRTYGATE/PROJECT_CONTEXT.md"
git -C "$DIRTYGATE" add PROJECT_CONTEXT.md >/dev/null 2>&1
git -C "$DIRTYGATE" commit -q -m "add gate" >/dev/null 2>&1
echo unstaged >> "$DIRTYGATE/seed.txt"   # unstaged change, not added to the index
printf '%s' "$(mkjson Bash 'git commit -a -m x' "$DIRTYGATE")" \
  | bash "$ROOT/hooks/pre-commit-test.sh" >/dev/null 2>&1
expect "(R2-5) dirty working tree: exit 0 on pass" "0" "$?"
DIRTYTREE=$(sed -n 's/.*"tree":"\([^"]*\)".*/\1/p' "$DIRTYGATE/.gate/last-pass.json" 2>/dev/null)
git -C "$DIRTYGATE" commit -aq -m x >/dev/null 2>&1
expect "(R2-5) commit -a: recorded tree == committed tree" \
  "$(git -C "$DIRTYGATE" rev-parse 'HEAD^{tree}')" "$DIRTYTREE"

check_msg "(b) run-gate.sh path: block names run-gate.sh" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$GATEONLYBAD")" \
  "BLOCKED: 'run-gate.sh' failed"

# --- v2.1.3 fix round 1 (Critical 1): a still-unfilled {{...}} Gate placeholder
# must never route into run-gate.sh (which itself no-ops on a placeholder and
# would return a false green with nothing verified).
PLACEHOLDERTEST=$(mkrepo commitplaceholdertest main)
printf '# ctx\n\n- **Test**: `true`\n- **Gate**: `{{GATE_COMMAND}}`\n' > "$PLACEHOLDERTEST/PROJECT_CONTEXT.md"
check "Test:true + Gate:placeholder -- Test wins, run-gate NOT invoked" \
  "$H" 0 "$(mkjson Bash 'git commit -m x' "$PLACEHOLDERTEST")"

PLACEHOLDERONLY=$(mkrepo commitplaceholderonly main)
printf '# ctx\n\n- **Gate**: `{{GATE_COMMAND}}`\n' > "$PLACEHOLDERONLY/PROJECT_CONTEXT.md"
check_msg "Gate:placeholder alone -- WARN path, no false green" \
  "$ROOT/hooks/pre-commit-test.sh" 0 \
  "$(mkjson Bash 'git commit -m x' "$PLACEHOLDERONLY")" \
  "WARN: pre-commit-test: no Test/Gate command in PROJECT_CONTEXT.md"

# --- v2.1.3 fix round 2 item 1: the reverse shape -- a still-unfilled {{...}}
# Test placeholder alongside a REAL Gate command (dotnet/dotnet-maui ship
# exactly this). Precedence must fall through to the real Gate/run-gate.sh,
# not silently exit 0 because a "Test" field merely exists.
TESTPLACEHOLDER_REALGATE=$(mkrepo committestplaceholder main)
printf '# ctx\n\n- **Test**: `{{TEST_COMMAND}}`\n- **Gate**: `true`\n' > "$TESTPLACEHOLDER_REALGATE/PROJECT_CONTEXT.md"
rm -f "$TESTPLACEHOLDER_REALGATE/.gate/last-pass.json"
check "Test:placeholder + Gate:real -- falls through to run-gate.sh" \
  "$H" 0 "$(mkjson Bash 'git commit -m x' "$TESTPLACEHOLDER_REALGATE")"
expect "Test:placeholder + Gate:real -- run-gate.sh actually ran (artifact written)" \
  "1" "$([ -f "$TESTPLACEHOLDER_REALGATE/.gate/last-pass.json" ] && echo 1 || echo 0)"

BOTHPLACEHOLDER=$(mkrepo commitbothplaceholder main)
printf '# ctx\n\n- **Test**: `{{TEST_COMMAND}}`\n- **Gate**: `{{GATE_COMMAND}}`\n' > "$BOTHPLACEHOLDER/PROJECT_CONTEXT.md"
check_msg "Test:placeholder + Gate:placeholder -- WARN path" \
  "$ROOT/hooks/pre-commit-test.sh" 0 \
  "$(mkjson Bash 'git commit -m x' "$BOTHPLACEHOLDER")" \
  "WARN: pre-commit-test: no Test/Gate command in PROJECT_CONTEXT.md"

# --- v2.1.3 fix round 2 item 3: RUN_GATE must be absolutized before any `cd`.
# Invoke the hook via a RELATIVE $0 (as the real harness does: `bash
# hooks/pre-commit-test.sh`) with cwd = the toolkit root, while the commit
# targets a DIFFERENT repo via `git -C <repo>`. Before the fix, the stale
# relative RUN_GATE would resolve against the -C target (no hooks/ there) and
# silently fall back to the legacy eval path instead of running run-gate.sh.
RELCHECK=$(mkrepo relcheck main)
printf '# ctx\n\n- **Gate**: `true`\n' > "$RELCHECK/PROJECT_CONTEXT.md"
rm -f "$RELCHECK/.gate/last-pass.json"
relrc=$(cd "$ROOT" && printf '%s' "$(mkjson Bash "git -C \"$RELCHECK\" commit -m x" "$ROOT")" | bash hooks/pre-commit-test.sh >/dev/null 2>&1; echo $?)
expect "(R2-3) relative \$0, -C to another repo: exit 0" "0" "$relrc"
expect "(R2-3) relative \$0: run-gate.sh actually ran (artifact written)" \
  "1" "$([ -f "$RELCHECK/.gate/last-pass.json" ] && echo 1 || echo 0)"

# (c) no run-gate.sh next to the hook: existing Gate/Test eval path unchanged
NORUNGATE="$TMPROOT/norungate"
mkdir -p "$NORUNGATE/lib"
cp "$ROOT/hooks/pre-commit-test.sh" "$NORUNGATE/"
cp "$ROOT/hooks/lib/git-cmd.sh" "$ROOT/hooks/lib/json.sh" "$NORUNGATE/lib/"
check_msg "(c) no run-gate.sh: Gate command evaluated directly" "$NORUNGATE/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$GATEONLYBAD")" \
  "BLOCKED: 'false' failed"
# v2.1.3 fix round 2 item 4: the fallback WARNs (never a silent no-op, never a
# 127) when run-gate.sh is absent next to the hook -- the state a user-level
# mirror is in if it predates the run-gate.sh mirroring change.
check_msg "(c) no run-gate.sh: WARN names the fallback" "$NORUNGATE/pre-commit-test.sh" 0 \
  "$(mkjson Bash 'git commit -m x' "$GATEONLYOK")" \
  "WARN: pre-commit-test: run-gate.sh not found next to this hook"

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
check "malformed JSON payload"           "$H" 2 '{not json'
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
# v2.1.3 fix round 1 (Critical 2 / penumbra #2c): a real end-to-end chain --
# pre-commit-test.sh runs run-gate.sh against the INDEX, the real `git commit`
# follows, and gate-before-merge.sh must accept the resulting artifact via its
# tree match even though the artifact's sha is the PARENT commit's.
# ===========================================================================
echo
echo "=== R3 chain: commit-time run-gate.sh satisfies merge-time gate ==="
CHAINREPO=$(mkrepo gatechain main)
printf '# ctx\n\n- **Gate**: `true`\n' > "$CHAINREPO/PROJECT_CONTEXT.md"
git -C "$CHAINREPO" add PROJECT_CONTEXT.md >/dev/null 2>&1
git -C "$CHAINREPO" commit -q -m "add gate" >/dev/null 2>&1
echo change1 > "$CHAINREPO/file.txt"
git -C "$CHAINREPO" add file.txt >/dev/null 2>&1

# PreToolUse intercepts the `git commit` Bash call BEFORE it runs -- this is
# pre-commit-test.sh routing into run-gate.sh (Gate-only, no Test field).
printf '%s' "$(mkjson Bash 'git commit -m "add file"' "$CHAINREPO")" \
  | bash "$ROOT/hooks/pre-commit-test.sh" >/dev/null 2>&1
expect "(R3) chain: pre-commit-test.sh allows the commit" "0" "$?"

# The real commit now runs (as the harness would do after the hook allows it).
git -C "$CHAINREPO" commit -q -m "add file" >/dev/null 2>&1

check "(R3) chain: gate-before-merge accepts the tree-matched artifact" \
  "hooks/gate-before-merge.sh" 0 "$(mkjson Bash 'gh pr merge 1 --squash' "$CHAINREPO")"

# Negative: a further commit moves both HEAD and the tree past what the
# artifact recorded -- gate-before-merge must fall back to stale/blocked.
echo change2 >> "$CHAINREPO/file.txt"
git -C "$CHAINREPO" add file.txt >/dev/null 2>&1
git -C "$CHAINREPO" commit -q -m "second change" >/dev/null 2>&1
check "(R3) chain negative: stale artifact after a further commit" \
  "hooks/gate-before-merge.sh" 2 "$(mkjson Bash 'gh pr merge 1 --squash' "$CHAINREPO")"

# ===========================================================================
# v2.1.5 (consumer feedback, Yutraffic PR #223 e59e6fd vs 567f0d1): the agent
# shape. Agents chain `git add <paths> && git commit`; the PreToolUse hook fires
# BEFORE anything is staged, so an index-keyed artifact recorded the PARENT tree
# (or, after the v2.1.3 round-2 dirty guard, no tree at all) and the merge gate
# always demanded a second gate run. Keying on the WORKING tree fixes it.
# ===========================================================================
echo
echo "=== R4 working-tree gate key (v2.1.5) ==="

# (a) chained `git add <paths> && git commit` -> commit-time gate satisfies the
#     merge gate in ONE run.
CHAINADD=$(mkrepo gatechainadd main)
printf '# ctx\n\n- **Gate**: `true`\n' > "$CHAINADD/PROJECT_CONTEXT.md"
git -C "$CHAINADD" add PROJECT_CONTEXT.md >/dev/null 2>&1
git -C "$CHAINADD" commit -q -m "add gate" >/dev/null 2>&1
echo one > "$CHAINADD/a.txt"
echo two > "$CHAINADD/b.txt"          # BOTH files unstaged when the hook fires
printf '%s' "$(mkjson Bash 'git add a.txt b.txt && git commit -m "both"' "$CHAINADD")" \
  | bash "$ROOT/hooks/pre-commit-test.sh" >/dev/null 2>&1
expect "(R4a) chained add+commit: hook allows" "0" "$?"
git -C "$CHAINADD" add a.txt b.txt >/dev/null 2>&1
git -C "$CHAINADD" commit -q -m both >/dev/null 2>&1
check "(R4a) chained add+commit: merge gate accepts one run" \
  "hooks/gate-before-merge.sh" 0 "$(mkjson Bash 'gh pr merge 1 --squash' "$CHAINADD")"

# (b) PARTIAL add: the gate hashed both files, the commit contains one. The
#     committed tree is not what was gated -> stale by design.
PARTADD=$(mkrepo gatepartialadd main)
printf '# ctx\n\n- **Gate**: `true`\n' > "$PARTADD/PROJECT_CONTEXT.md"
git -C "$PARTADD" add PROJECT_CONTEXT.md >/dev/null 2>&1
git -C "$PARTADD" commit -q -m "add gate" >/dev/null 2>&1
echo one > "$PARTADD/a.txt"
echo two > "$PARTADD/b.txt"
printf '%s' "$(mkjson Bash 'git add a.txt && git commit -m "partial"' "$PARTADD")" \
  | bash "$ROOT/hooks/pre-commit-test.sh" >/dev/null 2>&1
expect "(R4b) partial add: hook allows the commit" "0" "$?"
git -C "$PARTADD" add a.txt >/dev/null 2>&1
git -C "$PARTADD" commit -q -m partial >/dev/null 2>&1
check "(R4b) partial add: merge gate reports stale" \
  "hooks/gate-before-merge.sh" 2 "$(mkjson Bash 'gh pr merge 1 --squash' "$PARTADD")"

# (c) an ignored file and the artifact directory itself must not move the tree.
IGNTREE=$(mkrepo gateignoredtree main)
printf '# ctx\n\n- **Gate**: `true`\n' > "$IGNTREE/PROJECT_CONTEXT.md"
printf '.gate/\nbuild/\n' > "$IGNTREE/.gitignore"
git -C "$IGNTREE" add -A >/dev/null 2>&1
git -C "$IGNTREE" commit -q -m "add gate" >/dev/null 2>&1
( cd "$IGNTREE" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>&1 )
IGNTREE1=$(sed -n 's/.*"tree":"\([^"]*\)".*/\1/p' "$IGNTREE/.gate/last-pass.json" 2>/dev/null)
expect "(R4c) clean tree: recorded tree == HEAD^{tree}" \
  "$(git -C "$IGNTREE" rev-parse 'HEAD^{tree}')" "$IGNTREE1"
mkdir -p "$IGNTREE/build" && echo junk > "$IGNTREE/build/out.o"
( cd "$IGNTREE" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>&1 )
IGNTREE2=$(sed -n 's/.*"tree":"\([^"]*\)".*/\1/p' "$IGNTREE/.gate/last-pass.json" 2>/dev/null)
expect "(R4c) ignored file + .gate/ do not change the tree" "$IGNTREE1" "$IGNTREE2"
# and the REAL index is untouched by the temp-index hash
expect "(R4c) real index untouched by the gate" "" \
  "$(git -C "$IGNTREE" diff --cached --name-only)"

# (d) LINKED WORKTREE — the production path. coder/tester run under
#     `isolation: worktree`, where the index is NOT $GIT_DIR/index but
#     .git/worktrees/<name>/index; only `rev-parse --git-path index` resolves
#     it. A hardcoded path would hash the MAIN checkout's index instead.
WTMAIN=$(mkrepo gateworktreemain main)
printf '# ctx\n\n- **Gate**: `true`\n' > "$WTMAIN/PROJECT_CONTEXT.md"
git -C "$WTMAIN" add -A >/dev/null 2>&1
git -C "$WTMAIN" commit -q -m "add gate" >/dev/null 2>&1
WTLINK="$TMPROOT/gateworktree-linked"
git -C "$WTMAIN" worktree add -q -b wt-feature "$WTLINK" >/dev/null 2>&1
WTIDX=$(git -C "$WTLINK" rev-parse --git-path index)
WTIDXBEFORE=$(md5sum "$WTIDX" 2>/dev/null | cut -d' ' -f1)
( cd "$WTLINK" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>&1 )
WTTREE=$(sed -n 's/.*"tree":"\([^"]*\)".*/\1/p' "$WTLINK/.gate/last-pass.json" 2>/dev/null)
expect "(R4d) linked worktree: tree == its own HEAD^{tree}" \
  "$(git -C "$WTLINK" rev-parse 'HEAD^{tree}')" "$WTTREE"
expect "(R4d) linked worktree: its index file is byte-unchanged" \
  "$WTIDXBEFORE" "$(md5sum "$WTIDX" 2>/dev/null | cut -d' ' -f1)"

# ===========================================================================
# v2.1.3 fix round 1 (R5): a **Gate** command that shells out to run-gate.sh
# itself must not recurse. RUN_GATE_ACTIVE is exported before the gate command
# runs and checked on entry -- simulate that directly.
# ===========================================================================
echo
echo "=== R5: run-gate.sh recursion guard ==="
RECURSEREPO=$(mkrepo gaterecurse main)
printf '# ctx\n\n- **Gate**: `bash hooks/run-gate.sh`\n' > "$RECURSEREPO/PROJECT_CONTEXT.md"
recurseerr="$TMPROOT/recurse.err"
( cd "$RECURSEREPO" && RUN_GATE_ACTIVE=1 bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$recurseerr" )
expect "(R5) recursion guard: exit 2"  "2" "$?"
expect "(R5) recursion guard: message" "1" \
  "$(grep -cF 'BLOCKED: **Gate** must not invoke run-gate.sh itself' "$recurseerr")"

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
readout() { # <json> -> the hook's stdout
  printf '%s' "$1" | bash "$ROOT/$H" 2>/dev/null
}
SMALL="$TMPROOT/small.txt"; : > "$SMALL"; for i in $(seq 1 20); do echo "line $i" >> "$SMALL"; done
HUNDRED="$TMPROOT/hundred.txt"; : > "$HUNDRED"; for i in $(seq 1 100); do echo "line $i" >> "$HUNDRED"; done
BIG="$TMPROOT/big.txt";     : > "$BIG";   for i in $(seq 1 600); do echo "line $i" >> "$BIG"; done
HUGE="$TMPROOT/huge.txt";   : > "$HUGE";  for i in $(seq 1 900); do echo "line $i" >> "$HUGE"; done
BIGPNG="$TMPROOT/big.png";  cp "$BIG" "$BIGPNG"

# read-size-gate rewrites the tool_input with an embedded node program, so with
# no node it warns once and passes everything through -- correct behaviour, but
# it cannot be told apart from a broken cap here. Asserted where it belongs
# instead: "python3: read-size-gate names node" and the warn-once block below.
if [ -n "$HAVE_NODE" ]; then
check "small file passes"                "$H" 0 "$(mkread "$SMALL")"
check "big file is allowed, not blocked" "$H" 0 "$(mkread "$BIG")"
check "big file with a small limit"      "$H" 0 "$(mkread "$BIG" 100)"
check "missing file is not blocked"      "$H" 0 "$(mkread "$TMPROOT/does-not-exist.txt")"
check "non-Read payload passes through"  "$H" 0 "$(mkjson Bash 'echo hi' "$MAINREPO")"

# --- an unbounded Read of a 600-line file is capped, and every original field
# survives the updatedInput replacement. file_path is still compared against the
# payload's own copy rather than $BIG: the assertion is "the hook echoed back
# what it was given", which must hold whatever spelling the path arrives in.
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
  dd if=/dev/zero of="$GIANT" bs=1048576 count=12 >/dev/null 2>&1
fi
GIANTOUT=$(readout "$(mkread "$GIANT")")
expect "giant file: limit is 500" "500" "$(jfield "$GIANTOUT" hookSpecificOutput.updatedInput.limit)"
expect "giant file: context reports the size, not a line count" 1 \
  "$(printf '%s' "$GIANTOUT" | grep -c 'File is 12 MB; capped at 500 lines')"
expect "giant file: no line count is claimed" 0 \
  "$(printf '%s' "$GIANTOUT" | grep -c 'of 0 lines')"
else
skip "read-size-gate cap cases" "no node on this host" 21
fi

# --- the ctx-tool advice the blocking version printed is gone for good.
# A source grep, so it holds with or without node.
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

runguard() { # <json> -> hook stdout
  printf '%s' "$1" | TMPDIR="$GUARDTMP" bash "$ROOT/$GUARD" 2>/dev/null
}

# The guard rewrites tool_response with an embedded node program; with no node
# it warns once and passes the output through untouched. Nothing below can tell
# that apart from a broken truncator, so it SKIPs rather than fails.
if [ -n "$HAVE_NODE" ]; then
BIGOUT=$(runguard "$(mkpost 20000)")
expect "guard: emits updatedToolOutput" "PostToolUse" \
  "$(jfield "$BIGOUT" hookSpecificOutput.hookEventName)"
expect "guard: truncation marker names the log" 1 \
  "$(printf '%s' "$BIGOUT" | grep -c 'chars truncated — full output:')"
expect "guard: sibling fields survive" "false" \
  "$(jfield "$BIGOUT" hookSpecificOutput.updatedToolOutput.interrupted)"
GUARDSTD=$(jfield "$BIGOUT" hookSpecificOutput.updatedToolOutput.stdout)
GUARDLEN=${#GUARDSTD}
expect "guard: 20 000 chars are cut down" 1 \
  "$( [ "$GUARDLEN" -gt 8000 ] && [ "$GUARDLEN" -lt 9000 ] && echo 1 || echo 0 )"
guard_head=0
[ "${GUARDSTD:0:4000}" = "$(nchars 4000 A)" ] && [ "${GUARDSTD: -4000}" = "$(nchars 4000 A)" ] && guard_head=1
expect "guard: head is preserved" 1 "$guard_head"
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
HUGESTD=$(jfield "$HUGEOUT" hookSpecificOutput.updatedToolOutput.stdout)
expect "guard: 200 KB payload still truncates" "500" \
  "$( [ -n "$HUGESTD" ] && [ "${#HUGESTD}" -lt 10000 ] && echo 500 || echo 0 )"
expect "guard: 200 KB full output is on disk" 200000 \
  "$(wc -c < "$(find "$GUARDTMP/claude-bash-out" -name 'guardsess-*.log' -size +100k 2>/dev/null | head -1)" | tr -d ' ')"

# --- fix round 1: stderr is an output stream too. A 20 KB stderr with a tiny
# stdout was passed through whole.
ERROUT=$(runguard "$(mkpost 100 20000)")
ERRSTDERR=$(jfield "$ERROUT" hookSpecificOutput.updatedToolOutput.stderr)
err_trunc=0
case "$ERRSTDERR" in *'chars truncated'*)
  [ "${#ERRSTDERR}" -lt 10000 ] && [ "${ERRSTDERR:0:4000}" = "$(nchars 4000 B)" ] && err_trunc=1 ;;
esac
expect "guard: stderr is truncated too" 1 "$err_trunc"
ERRSTD=$(jfield "$ERROUT" hookSpecificOutput.updatedToolOutput.stdout)
expect "guard: small stdout survives untouched" 100 "${#ERRSTD}"
expect "guard: stderr gets its own log file" 1 \
  "$(find "$GUARDTMP/claude-bash-out" -name '*-stderr.log' 2>/dev/null | wc -l | tr -d ' ')"
printf '%s' "$(mkpost 20000)" | TMPDIR="$GUARDTMP" bash "$ROOT/$GUARD" >/dev/null 2>&1
expect "guard: always exits 0" 0 $?
else
skip "bash-output-guard cases" "no node on this host" 15
fi

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

# A subagent transcript with (a) a dead-tool tool_result and (b) a hook block.
# Wording copied verbatim from a real transcript:
#   ~/.claude/projects/G--git-claude-code-toolkit/<session>/subagents/
#   agent-a003c937d78f9f557.jsonl
mktranscript() { # <path>
  {
    trow_err "<tool_use_error>Error: No such tool available: mcp__x__y. mcp__x__y is disabled for this session, in subagents as well as here.</tool_use_error>"
    trow_err "PreToolUse:Bash hook error: [bash 'hooks/enforce-delegation.sh']: DELEGATE: the PO does not do hands-on work."
    trow_text "No such tool available in prose must not count"
  } > "$1"
}

# Both hooks scan the JSONL transcript with an embedded node program, so with no
# node they warn once and write nothing at all. Every assertion below reads what
# they wrote, so the block SKIPs rather than calling that absence a regression.
if [ -n "$HAVE_NODE" ]; then
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
FP_QUOTED="1: echo 'BLOCKED: use the MCP tool'
2: BLOCKED: another quoted line
"
{
  trow_ok "$FP_QUOTED"
  trow_ok "file listing mentioning hooks/no-push-main.sh and DELEGATE: in prose"
} > "$TMPROOT/agent-falsepos.jsonl"
FPHOME="$TMPROOT/retrohome-fp"
mkdir -p "$FPHOME"
mkstop "$PROJCWD" coder agent-fp "$TMPROOT/agent-falsepos.jsonl" \
  | HOME="$FPHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
expect "successful output is not a failure" 0 \
  "$(find "$FPHOME" -name retro.md 2>/dev/null | wc -l | tr -d ' ')"

# ... but a real hook block still counts even without is_error, and its script
# name comes from the bracketed hook command, not from any .sh token in the text.
{
  trow_ok "PreToolUse:Bash hook error: [bash 'hooks/no-push-main.sh']: BLOCKED: push to main."
  trow_err "<tool_use_error>Error: No such tool available: mcp__x__y. Mentions scripts/test-hooks.sh in prose.</tool_use_error>"
} > "$TMPROOT/agent-block.jsonl"
BKHOME="$TMPROOT/retrohome-block"
mkdir -p "$BKHOME"
mkstop "$PROJCWD" coder agent-bk "$TMPROOT/agent-block.jsonl" \
  | HOME="$BKHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
BKLEDGER="$BKHOME/.claude/projects/G--git-retroproj/memory/retro.md"
expect "hook block counts without is_error" 1 \
  "$(grep -c 'errors=2' "$BKLEDGER" 2>/dev/null)"
expect "block name comes from the hook command" 1 \
  "$(grep -c 'blocks=\[no-push-main.sh\]' "$BKLEDGER" 2>/dev/null)"

# --- 8a2. v2.1.4: a hooks/agent-budget-warn.sh block is tallied separately as
# budget=<n>, not folded into blocks=[...] -- budget ceilings are an expected
# liveness control, not a failure to investigate.
{
  trow_ok "PreToolUse:Bash hook error: [bash 'hooks/agent-budget-warn.sh']: BUDGET: this spawn has made 120 tool calls (median is 15; 120 is the first ceiling)."
  trow_ok "PreToolUse:Bash hook error: [bash 'hooks/no-push-main.sh']: BLOCKED: push to main."
} > "$TMPROOT/agent-budget.jsonl"
BUHOME="$TMPROOT/retrohome-budget"
mkdir -p "$BUHOME"
mkstop "$PROJCWD" coder agent-bu "$TMPROOT/agent-budget.jsonl" \
  | HOME="$BUHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
BULEDGER="$BUHOME/.claude/projects/G--git-retroproj/memory/retro.md"
expect "budget block tallies as budget=1" 1 \
  "$(grep -c 'budget=1' "$BULEDGER" 2>/dev/null)"
expect "budget block does not land in blocks=[...]" 1 \
  "$(grep -c 'blocks=\[no-push-main.sh\]' "$BULEDGER" 2>/dev/null)"

# --- 8b. review round 1: the ledger line is bounded. 12 distinct dead tools must
# render as 5 names + a "+7 more" marker, not a 12-entry line.
{
  many_i=1
  while [ "$many_i" -le 12 ]; do
    trow_err "$(printf '<tool_use_error>Error: No such tool available: mcp__t%02d__x.</tool_use_error>' "$many_i")"
    many_i=$((many_i + 1))
  done
} > "$TMPROOT/agent-many.jsonl"
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
{ nchars 500 X; echo; } > "$LONGDIR/retro.md"
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
else
skip "retro-ledger + retro-brief cases" "no node on this host" 32
fi

# ===========================================================================
# hooks/enforce-agent-contract.sh — verdict + loop guard (v2.2.2, consumer
# feedback: Motorsport-Manager-AI-Agent field report)
#
# Until v2.2.2 this hook had NO behavioural fixture at all — only degraded-path
# cases (`no lib:` / `no parser:`), which pass whatever the verdict logic does.
# Two defects lived in that gap:
#   A. the transcript scan read message.content only when it was an ARRAY, so a
#      text-only compliant final report was never seen and `txt` kept an earlier
#      mid-run turn: the contract could not be satisfied, ever;
#   B. the loop-guard marker was deleted on the let-through path, so enforcement
#      alternated block/pass forever instead of prodding exactly once.
# Also fixed here: the hook read `transcript_path` (the SESSION's JSONL) rather
# than `agent_transcript_path` (the subagent's own) — mkstop only ever sets the
# latter, so every assertion below would fail against the pre-v2.2.2 field read.
# ===========================================================================
echo
echo "=== hooks/enforce-agent-contract.sh (verdict + loop guard) ==="

if [ -n "$HAVE_NODE" ]; then

CONTRACT_OK='All done.

## Gate Results
GATE PASS abc1234

## Spec Compliance
1. DONE'

# <label> <tmpdir> <agent_type> <agent_id> <transcript> <want_exit> <needle|"">
# The TMPDIR is a PARAMETER, deliberately unlike check_msg's fresh-per-case
# idiom: the loop-guard sequence below is only meaningful when three consecutive
# stops share one marker directory, which is exactly what a real session does.
ctr() {
  ctr_label="$1"; ctr_tmp="$2"; ctr_type="$3"; ctr_id="$4"
  ctr_tr="$5"; ctr_want="$6"; ctr_needle="${7:-}"
  ctr_err="$TMPROOT/contract.err"
  mkdir -p "$ctr_tmp"
  printf '%s' "$(mkstop "$PROJCWD" "$ctr_type" "$ctr_id" "$ctr_tr")" \
    | TMPDIR="$ctr_tmp" bash "$ROOT/hooks/enforce-agent-contract.sh" \
      >/dev/null 2>"$ctr_err"
  ctr_got=$?
  if [ "$ctr_got" = "$ctr_want" ] &&
     { [ -z "$ctr_needle" ] || grep -qF "$ctr_needle" "$ctr_err"; }; then
    printf 'PASS  %-42s (exit %s)\n' "$ctr_label" "$ctr_got"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s%s, got %s: %s)\n' "$ctr_label" "$ctr_want" \
      "${ctr_needle:+ + \"$ctr_needle\"}" "$ctr_got" "$(head -1 "$ctr_err")"
    fail=$((fail + 1))
  fi
}

# --- 1. both wire shapes of a compliant final report are accepted -----------
CT_ARR="$TMPROOT/contract-array.jsonl"
trow_text "$CONTRACT_OK" > "$CT_ARR"
ctr "coder: array-shaped report passes" "$TMPROOT/ct1" coder a-arr "$CT_ARR" 0

CT_STR="$TMPROOT/contract-string.jsonl"
trow_str "$CONTRACT_OK" > "$CT_STR"
ctr "coder: STRING-shaped report passes" "$TMPROOT/ct2" coder a-str "$CT_STR" 0

# --- 2. the reported shape: a non-compliant ARRAY turn earlier in the run,
# then a compliant STRING final report. The array-only reader kept the stale
# earlier turn and blocked; the last turn is what counts.
CT_MIX="$TMPROOT/contract-mixed.jsonl"
trow_text 'Working on it — reading the spec now.' > "$CT_MIX"
trow_str "$CONTRACT_OK" >> "$CT_MIX"
ctr "STRING report after array mid-run turn" "$TMPROOT/ct3" coder a-mix "$CT_MIX" 0

# --- 3. preserved semantics: a tool_use-only final turn is NO report ---------
CT_TOOL="$TMPROOT/contract-tool.jsonl"
trow_str "$CONTRACT_OK" > "$CT_TOOL"
trow_tool >> "$CT_TOOL"
ctr "tool_use-only final turn blocks" "$TMPROOT/ct4" coder a-tool "$CT_TOOL" 2 \
  "CONTRACT VIOLATION"

# --- 4. code-reviewer verdicts read the string shape too --------------------
CT_CLEAN="$TMPROOT/contract-clean.jsonl"
trow_str 'clean' > "$CT_CLEAN"
ctr "reviewer: STRING 'clean' passes" "$TMPROOT/ct5" code-reviewer a-cl "$CT_CLEAN" 0

CT_CHAT="$TMPROOT/contract-chat.jsonl"
trow_str 'Looks fine to me, nothing to flag.' > "$CT_CHAT"
ctr "reviewer: STRING prose blocks" "$TMPROOT/ct6" code-reviewer a-ch "$CT_CHAT" 2 \
  "CONTRACT VIOLATION"

# --- 5. the loop guard bounds at ONE prod, over a SHARED marker dir ----------
# Pre-v2.2.2 this sequence measured 2 / 0 / 2: the let-through path deleted the
# marker, so stop 3 started fresh and prodded again — an unbounded alternation.
CT_LOOP="$TMPROOT/contract-loop.jsonl"
trow_str 'Done, I think that covers it.' > "$CT_LOOP"
LOOPTMP="$TMPROOT/ct-loop"
ctr "loop guard: stop 1 blocks"        "$LOOPTMP" coder a-loop "$CT_LOOP" 2 \
  "CONTRACT VIOLATION"
ctr "loop guard: stop 2 passes"        "$LOOPTMP" coder a-loop "$CT_LOOP" 0 \
  "CONTRACT-ENFORCER"
ctr "loop guard: stop 3 still passes"  "$LOOPTMP" coder a-loop "$CT_LOOP" 0 \
  "CONTRACT-ENFORCER"
# A DIFFERENT agent in the SAME session keeps its own single prod: the marker is
# keyed on session+agent, not session.
ctr "loop guard: other agent still prodded" "$LOOPTMP" coder a-loop2 "$CT_LOOP" 2 \
  "CONTRACT VIOLATION"
# ...and having complied once does not re-arm the prod for an agent that yields
# again without a report.
ctr "compliant stop does not re-arm"   "$LOOPTMP" coder a-loop "$CT_ARR" 0
ctr "then a later bare stop still passes" "$LOOPTMP" coder a-loop "$CT_LOOP" 0 \
  "CONTRACT-ENFORCER"

else
skip "enforce-agent-contract verdict + loop guard" "no node on this host" 12
fi

# ===========================================================================
# hooks/enforce-delegation.sh — Bash matcher (v2.1.5, consumer feedback:
# Yutraffic PR #223, panoscribe PR #123)
#
# The deny used to match the whole command STRING, so `git add hooks/run-gate.sh`
# and `git commit -m "run pytest before merge"` were denied — blocking the PO's
# own sync commit that the sync-template skill prescribes. git/gh I/O is the PO's
# documented role (AGENT_TEAM.md), so a segment whose first token is git or gh
# passes; every other segment keeps the existing deny logic.
#
# NOTE: this hook denies by printing a permissionDecision on STDOUT and exiting
# 0 — check()/check_msg() cannot tell PASS from DENY here.
# ===========================================================================
echo
echo "=== hooks/enforce-delegation.sh (Bash: git/gh exemption) ==="
DELEGREPO=$(mkrepo delegation main)

check_delegation() { # <label> <pass|deny> <command>
  label="$1"; want="$2"
  out=$(printf '%s' "$(mkjson Bash "$3" "$DELEGREPO")" \
    | bash "$ROOT/hooks/enforce-delegation.sh" 2>/dev/null)
  case "$out" in
    *'"permissionDecision":"deny"'*) got=deny ;;
    *) got=pass ;;
  esac
  if [ "$got" = "$want" ]; then
    printf 'PASS  %-42s (%s)\n' "$label" "$got"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s, got %s)\n' "$label" "$want" "$got"
    fail=$((fail + 1))
  fi
}

# enforce-delegation classifies the command with an embedded node program, so
# with no node it warns once and lets everything pass -- the deny cases below
# cannot be told apart from a broken classifier. The degraded path has its own
# fixture ("no parser: enforce-delegation warns").
if [ -n "$HAVE_NODE" ]; then
check_delegation "git add of a hook file"        pass 'git add hooks/run-gate.sh'
check_delegation "commit message naming a runner" pass 'git commit -m "run pytest before merge"'
check_delegation "gh pr create with npm in body"  pass 'gh pr create --body "npm test"'
check_delegation "git chained with a gate run"    deny 'git add x && bash hooks/run-gate.sh'
check_delegation "bare pytest"                    deny 'pytest'
check_delegation "cd prefix before git push"      pass 'cd sub && git push -u origin feature'
# regressions the exemption must not open
check_delegation "VAR= prefix before a runner"    deny 'CI=1 pytest -q'
check_delegation "runner after a git segment"     deny 'git status; npm test'
check_delegation "dotnet build stays denied"      deny 'dotnet build --no-restore'
# Known limitation, pinned deliberately: the split is quote-blind, so a separator
# INSIDE a quoted commit message still splits and the tail is judged on its own.
# This is parity with pre-v2.1.5 (the whole-string match denied it too) and errs
# closed; workaround is a message without an embedded `;` / `&&`.
check_delegation "separator inside a quoted message" deny 'git commit -m "a; pytest -q"'
# v2.2.1 (P): every runner pattern was anchored to command position except one —
# `/hooks\/run-gate\.sh/` matched the STRING anywhere. /sync-template step 7
# assembles an applied_files payload that necessarily NAMES that file, so the
# more faithfully the skill was followed, the more certainly the PO's own
# command was denied. The sibling paths were never affected, which is why the
# reporter's "trigger words in data" hypothesis over-generalised.
check_delegation "gate path as data: run-gate.sh"  pass 'echo {"file_path":"hooks/run-gate.sh"} > /tmp/a.json'
check_delegation "gate path as data: pre-commit"   pass 'echo {"file_path":"hooks/pre-commit-test.sh"} > /tmp/a.json'
check_delegation "gate path as data: merge gate"   pass 'echo {"file_path":"hooks/gate-before-merge.sh"} > /tmp/a.json'
check_delegation "applied_files array as data"     pass 'echo [{"path":"hooks/run-gate.sh","hash":"ab"},{"path":"hooks/no-push-main.sh","hash":"cd"}] > /tmp/applied.json'
check_delegation "validator run on a scratch file" pass 'python3 /tmp/validator.py /tmp/applied.json'
check_delegation "trigger words in a quoted string" pass 'echo "test gate coverage build"'
# The anchor's leading class is PATH characters, not \S*: a pretty-printed JSON
# line whose first token merely ENDS in the path is still data, not a command.
check_delegation "pretty-printed JSON line as data" pass 'echo "path": "hooks/run-gate.sh", >> /tmp/applied.json'
# ... and the anchor must not open the hole it closed: an actual invocation,
# bare or via bash/sh, is still the PO doing hands-on work.
check_delegation "bare run-gate.sh is still denied" deny 'hooks/run-gate.sh'
check_delegation "bash ./hooks/run-gate.sh denied"  deny 'bash ./hooks/run-gate.sh'
# subagent calls always pass, exemption or not
subout=$(printf '{"session_id":"t","agent_id":"a1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"pytest"},"cwd":"%s"}' "$(jesc "$DELEGREPO")" \
  | bash "$ROOT/hooks/enforce-delegation.sh" 2>/dev/null)
expect "subagent pytest still passes" "0" \
  "$(printf '%s' "$subout" | grep -c '"deny"')"
else
skip "enforce-delegation git/gh exemption cases" "no node on this host" 20
fi

# ===========================================================================
# v2.2.0 PR15 (A): the hooks must not depend on `node` specifically.
#
# Native Claude Code installs ship no node, and every gate keyed on
# `node -e` silently exited 0 there. hooks/lib/json.sh now tries node,
# then python3, then jq; the three git gates fail CLOSED when none is
# present, the fail-open hooks warn once and pass.
#
# The fixture PATH is a directory of one-line `exec` wrapper scripts for the
# tools the hooks actually call. Wrappers are text files, so no binary/DLL
# copying is involved on Windows, and `command -v node` genuinely fails inside
# them -- asserted below before any hook is exercised.
# ===========================================================================
echo
echo "=== no-JSON-parser fixtures (hooks/lib/json.sh) ==="

BASHABS=$(command -v bash)

mkpathdir() { # <name> [extra-tool ...] -> prints dir
  pd="$TMPROOT/path-$1"; shift
  mkdir -p "$pd"
  for t in sh bash git grep sed tr head tail cut cat wc stat date mktemp \
           dirname basename sort uniq mkdir rm ls awk env find touch cp expr "$@"; do
    r=$(command -v "$t" 2>/dev/null) || continue
    [ -n "$r" ] || continue
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$r" > "$pd/$t"
    chmod +x "$pd/$t"
  done
  printf '%s\n' "$pd"
}

# A hook that cannot enforce warns only ONCE per hook per TMPDIR (see
# json_warn_once), so every case gets a fresh TMPDIR — otherwise the second
# assertion on the same hook would see no WARN and the suite would depend on
# case order.
WARNTMP="$TMPROOT/warntmp"

# <label> <pathdir> <hook-rel-path> <want-exit> <json> [stderr-needle]
check_env() {
  label="$1"; pd="$2"; hook="$3"; want="$4"; json="$5"; needle="${6:-}"
  errf="$TMPROOT/check_env.err"
  rm -rf "$WARNTMP"; mkdir -p "$WARNTMP"
  printf '%s' "$json" | PATH="$pd" TMPDIR="$WARNTMP" "$BASHABS" "$ROOT/$hook" >/dev/null 2>"$errf"
  got=$?
  okc=1
  [ "$got" = "$want" ] || okc=0
  if [ -n "$needle" ] && ! grep -qF "$needle" "$errf"; then okc=0; fi
  # An undefined helper (lib not sourced) is never an acceptable degradation.
  if grep -qF "command not found" "$errf"; then okc=0; fi
  if [ "$okc" = "1" ]; then
    printf 'PASS  %-42s (exit %s)\n' "$label" "$got"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s%s, got %s: %s)\n' \
      "$label" "$want" "${needle:+ + \"$needle\"}" "$got" "$(head -1 "$errf" 2>/dev/null)"
    fail=$((fail + 1))
  fi
}

NOPARSER=$(mkpathdir noparser)
PYONLY=$(mkpathdir pyonly python3)
JQONLY=$(mkpathdir jqonly jq)

# Self-check FIRST: a fixture that still sees node would pass green and prove
# nothing. Prints 1 when the parser is invisible on that PATH.
seen() { # <pathdir> <tool>
  PATH="$1" "$BASHABS" -c "command -v $2 >/dev/null 2>&1" && echo 0 || echo 1
}
expect "fixture PATH hides node"         1 "$(seen "$NOPARSER" node)"
expect "fixture PATH hides python3"      1 "$(seen "$NOPARSER" python3)"
expect "fixture PATH hides jq"           1 "$(seen "$NOPARSER" jq)"

# The python3-only / jq-only backends can only be exercised where that
# interpreter exists. On a node-only box those cases SKIP (reported, not
# counted) instead of turning the whole suite red. `skip` and the three HAVE_*
# probes are defined once, near the assertion helpers at the top -- the
# node-only fixture blocks above need them long before this point.

if [ -n "$HAVE_PY" ]; then
  expect "python3-only PATH hides node"    1 "$(seen "$PYONLY" node)"
  expect "python3-only PATH keeps python3" 0 "$(seen "$PYONLY" python3)"
else
  skip "python3-only PATH self-check" "no python3 on this host" 2
fi
if [ -n "$HAVE_JQ" ]; then
  expect "jq-only PATH hides node"         1 "$(seen "$JQONLY" node)"
  expect "jq-only PATH keeps jq"           0 "$(seen "$JQONLY" jq)"
else
  skip "jq-only PATH self-check" "no jq on this host" 2
fi

NEEDLE_BLOCK="no JSON parser (node, python3 or jq) on PATH"
NEEDLE_WARN="no JSON parser on PATH"

# --- the three git gates fail CLOSED with no parser -------------------------
check_env "no parser: push origin main"     "$NOPARSER" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")" "$NEEDLE_BLOCK"
check_env "no parser: push feature branch"  "$NOPARSER" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push -u origin feature/x' "$FEATREPO")" "$NEEDLE_BLOCK"
check_env "no parser: gh pr merge"          "$NOPARSER" hooks/gate-before-merge.sh 2 \
  "$(mkjson Bash 'gh pr merge 1 --squash' "$GATEREPO")" "$NEEDLE_BLOCK"
check_env "no parser: git commit"           "$NOPARSER" hooks/pre-commit-test.sh 2 \
  "$(mkjson Bash 'git commit -m x' "$MAINREPO")" "$NEEDLE_BLOCK"
# The documented escape hatch still wins over the missing parser. Without a
# parser the payload cwd is unreadable, so the gate falls back to the process
# cwd -- which is what Claude Code sets to the project dir. Run it from there.
mkdir -p "$FEATREPO/.claude"; : > "$FEATREPO/.claude/git-guard-off"
printf '%s' "$(mkjson Bash 'git push origin main' "$FEATREPO")" \
  | ( cd "$FEATREPO" && PATH="$NOPARSER" "$BASHABS" "$ROOT/hooks/no-push-main.sh" ) >/dev/null 2>&1
expect "no parser: guard-off still opens" 0 "$?"
rm -f "$FEATREPO/.claude/git-guard-off"

# A mirror that copied git-cmd.sh but not the new json.sh must fail closed too,
# not fall back to an undefined reader.
NOJSONLIB="$TMPROOT/nojsonlib"
mkdir -p "$NOJSONLIB/lib"
cp "$ROOT/hooks/no-push-main.sh" "$NOJSONLIB/"
cp "$ROOT/hooks/lib/git-cmd.sh" "$NOJSONLIB/lib/"
check_msg "lib/json.sh missing: gate fails closed" "$NOJSONLIB/no-push-main.sh" 2 \
  "$(mkjson Bash 'git push -u origin feature/x' "$FEATREPO")" "hooks/lib/json.sh"

# A hook that calls json_get without the lib sourced would print
# `json_get: command not found` and enforce nothing. Both hooks that read fields
# through the lib must say so and pass instead. (check_env fails any case whose
# stderr contains "command not found", so the whole block is guarded too.)
NOLIB="$TMPROOT/nolib"
mkdir -p "$NOLIB"
cp "$ROOT/hooks/require-skills-block.sh" "$ROOT/hooks/enforce-agent-contract.sh" "$NOLIB/"
check_msg "no lib: require-skills warns, passes" "$NOLIB/require-skills-block.sh" 0 \
  "$(mkspawn coder 'Do the thing.')" "hooks/lib/json.sh missing"
check_msg "no lib: agent-contract warns, passes" "$NOLIB/enforce-agent-contract.sh" 0 \
  "$(mkstop "$ROOT" coder a1 /nonexistent)" "hooks/lib/json.sh missing"
nolib_err="$TMPROOT/nolib.err"
printf '%s' "$(mkstop "$ROOT" coder a1 /nonexistent)" \
  | bash "$NOLIB/enforce-agent-contract.sh" >/dev/null 2>"$nolib_err"
expect "no lib: no 'command not found' noise" "0" "$(grep -c 'command not found' "$nolib_err")"

# --- python3 only: the git gates behave exactly as with node ----------------
if [ -n "$HAVE_PY" ]; then
check_env "python3: push origin main blocked"  "$PYONLY" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")"
check_env "python3: feature push allowed"      "$PYONLY" hooks/no-push-main.sh 0 \
  "$(mkjson Bash 'git push -u origin feature/x' "$FEATREPO")"
check_env "python3: quoted -C space repo"      "$PYONLY" hooks/no-push-main.sh 2 \
  "$(mkjson Bash "git -C \"$SPACEREPO\" push" "$FEATREPO")"
check_env "python3: gh pr merge needs artifact" "$PYONLY" hooks/gate-before-merge.sh 2 \
  "$(mkjson Bash 'gh pr merge 1 --squash' "$GATEREPO")"
# A node-only hook on a python3 box names the parser it actually needs.
check_env "python3: read-size-gate names node" "$PYONLY" hooks/read-size-gate.sh 0 \
  "$(mkread "$ROOT/README.md" - -)" "node not usable (found python3)"
else
skip "python3 git-gate cases" "no python3 on this host" 5
fi

# --- jq only: same ----------------------------------------------------------
if [ -n "$HAVE_JQ" ]; then
check_env "jq: push origin main blocked"       "$JQONLY" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")"
check_env "jq: feature push allowed"           "$JQONLY" hooks/no-push-main.sh 0 \
  "$(mkjson Bash 'git push -u origin feature/x' "$FEATREPO")"
check_env "jq: quoted -C space repo"           "$JQONLY" hooks/no-push-main.sh 2 \
  "$(mkjson Bash "git -C \"$SPACEREPO\" push" "$FEATREPO")"
else
skip "jq git-gate cases" "no jq on this host" 3
fi

# require-skills-block is the one BLOCKING hook whose verdict now flows through
# json_get, and it matches on a multi-line field (prompt) — a backend that
# mangled the newlines would turn `^## Required Skills$` from a match into a
# miss and the gate would stop blocking. Exercised on both non-node backends.
if [ -n "$HAVE_PY" ]; then
check_env "python3: skills block present passes" "$PYONLY" hooks/require-skills-block.sh 0 \
  "$(mkspawn coder "$WITHBLOCK")"
check_env "python3: missing skills block blocks"  "$PYONLY" hooks/require-skills-block.sh 2 \
  "$(mkspawn coder 'Do the thing.')"
else
skip "python3 require-skills cases" "no python3 on this host" 2
fi
if [ -n "$HAVE_JQ" ]; then
check_env "jq: skills block present passes"       "$JQONLY" hooks/require-skills-block.sh 0 \
  "$(mkspawn coder "$WITHBLOCK")"
check_env "jq: missing skills block blocks"       "$JQONLY" hooks/require-skills-block.sh 2 \
  "$(mkspawn coder 'Do the thing.')"
else
skip "jq require-skills cases" "no jq on this host" 2
fi

# --- encoding: every backend must return the SAME bytes ---------------------
#
# `json.load(sys.stdin)` decoded in the LOCALE encoding, so an em dash in a
# command raised UnicodeDecodeError on a Windows/`LC_ALL=C` box -> empty field
# -> gate exits 0 silently. A UTF-8 BOM broke all three backends. Compared
# across backends rather than against a hardcoded string.
jget() { # <pathdir> <json> <dotted.path>
  PATH="$1" "$BASHABS" -c '. "$0"/hooks/lib/json.sh; json_get "$1" "$2"' \
    "$ROOT" "$2" "$3" 2>/dev/null
}
EMCMD='git push origin main # rationale — see PR'
EMJSON=$(mkjson Bash "$EMCMD" "$MAINREPO")
BOMJSON=$(printf '\357\273\277%s' "$EMJSON")
if [ -n "$HAVE_NODE" ]; then
  # A node-ONLY PATH, not the ambient one: on a node-less host the ambient PATH
  # would silently exercise python3 or jq and report it as the node backend.
  NODEONLY=$(mkpathdir nodeonly node)
  expect "node-only PATH keeps node" 0 "$(seen "$NODEONLY" node)"
  expect "node: em dash survives"  "$EMCMD" "$(jget "$NODEONLY" "$EMJSON" tool_input.command)"
  expect "node: BOM tolerated"     "$EMCMD" "$(jget "$NODEONLY" "$BOMJSON" tool_input.command)"
else
  skip "node encoding cases" "no node on this host" 3
fi
if [ -n "$HAVE_PY" ]; then
  expect "python3: em dash survives" "$EMCMD" "$(jget "$PYONLY" "$EMJSON" tool_input.command)"
  expect "python3: BOM tolerated"    "$EMCMD" "$(jget "$PYONLY" "$BOMJSON" tool_input.command)"
  # The locale that used to break it, both directions.
  pyloc=$(PATH="$PYONLY" LC_ALL=C PYTHONIOENCODING=cp1252 "$BASHABS" -c \
    '. "$0"/hooks/lib/json.sh; json_get "$1" "$2"' "$ROOT" "$EMJSON" tool_input.command 2>/dev/null)
  expect "python3 under LC_ALL=C parses"  "$EMCMD" "$pyloc"
  printf '%s' "$EMJSON" | PATH="$PYONLY" LC_ALL=C "$BASHABS" "$ROOT/hooks/no-push-main.sh" >/dev/null 2>&1
  expect "python3 under LC_ALL=C blocks"  2 "$?"
else
  skip "python3 encoding cases" "no python3 on this host" 4
fi
if [ -n "$HAVE_JQ" ]; then
  expect "jq: em dash survives"      "$EMCMD" "$(jget "$JQONLY" "$EMJSON" tool_input.command)"
  expect "jq: BOM tolerated"         "$EMCMD" "$(jget "$JQONLY" "$BOMJSON" tool_input.command)"
else
  skip "jq encoding cases" "no jq on this host" 2
fi

# --- the fail-open hooks stay open, but say so once -------------------------
check_env "no parser: read-size-gate warns"    "$NOPARSER" hooks/read-size-gate.sh 0 \
  "$(mkread "$ROOT/README.md" - -)" "$NEEDLE_WARN"
check_env "no parser: require-skills warns"    "$NOPARSER" hooks/require-skills-block.sh 0 \
  "$(mkspawn coder 'no skills block here')" "$NEEDLE_WARN"
check_env "no parser: enforce-delegation warns" "$NOPARSER" hooks/enforce-delegation.sh 0 \
  "$(mkjson Bash 'pytest' "$DELEGREPO")" "$NEEDLE_WARN"
check_env "no parser: bash-output-guard warns" "$NOPARSER" hooks/bash-output-guard.sh 0 \
  "$(mkpost 40000)" "$NEEDLE_WARN"
check_env "no parser: agent-contract warns"    "$NOPARSER" hooks/enforce-agent-contract.sh 0 \
  "$(mkstop "$ROOT" coder a1 /nonexistent)" "$NEEDLE_WARN"

# ... but only ONCE per hook PER SESSION. A PreToolUse hook fires on every tool
# call, so warning every time is thousands of identical stderr lines; a marker
# with no session in it is the opposite failure — with a host-global TMPDIR the
# hook would warn once ever and every later outage would be silent.
#
# These payloads are built with printf, NOT the node-backed mkjson/mkread
# helpers: this block is precisely the coverage a node-less host needs, and a
# `node -e` builder there returns "" for every payload, collapsing the two
# session ids into one and FAILING the "two sessions" case instead of skipping
# it. The shapes are fixed strings, so no JSON encoder is needed.
mkread_s() { # <session_id> <file_path>
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"%s"}}\n' "$1" "$2"
}
ONCETMP="$TMPROOT/oncetmp"
warnruns() { # <session-json> [<session-json> ...] -> WARN line count
  rm -f "$TMPROOT/once.err"; : > "$TMPROOT/once.err"
  for wj in "$@"; do
    printf '%s' "$wj" | PATH="$NOPARSER" TMPDIR="$ONCETMP" \
      "$BASHABS" "$ROOT/hooks/read-size-gate.sh" >/dev/null 2>>"$TMPROOT/once.err"
  done
  grep -c 'enforcement inactive' "$TMPROOT/once.err"
}
S1=$(mkread_s sess-one "$ROOT/README.md")
S2=$(mkread_s sess-two "$ROOT/README.md")
# mkread carries a session_id; this one deliberately does not.
NOSESS=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"%s"}}\n' "$ROOT/README.md")

rm -rf "$ONCETMP"; mkdir -p "$ONCETMP"
expect "same session: WARN printed once"   "1" "$(warnruns "$S1" "$S1" "$S1")"
rm -rf "$ONCETMP"; mkdir -p "$ONCETMP"
expect "two sessions: two WARNs"           "2" "$(warnruns "$S1" "$S2")"
rm -rf "$ONCETMP"; mkdir -p "$ONCETMP"
expect "no session id: WARN printed once"  "1" "$(warnruns "$NOSESS" "$NOSESS")"
# ... and the session-less marker expires, so a later outage is not silent.
if touch -d '2 hours ago' "$ONCETMP/claude-hook-warn-read-size-gate" 2>/dev/null; then
  expect "stale session-less marker re-warns" "1" "$(warnruns "$NOSESS")"
else
  skip "session-less marker expiry" "touch -d unsupported here"
fi
# The session id lands in a FILENAME, so a value carrying a path separator or
# `..` must not steer the marker out of the warn directory. Such a value is
# treated as no session at all (the TTL path), which still warns exactly once.
rm -rf "$ONCETMP"; mkdir -p "$ONCETMP"
EVILSESS=$(mkread_s '../../evil' "$ROOT/README.md")
expect "traversal session id: one WARN"    "1" "$(warnruns "$EVILSESS" "$EVILSESS")"
expect "traversal session id: no escape"   "0" \
  "$(find "$TMPROOT" -maxdepth 1 -name 'claude-hook-warn*' 2>/dev/null | grep -c .)"
expect "traversal session id: marker is plain" "1" \
  "$(find "$ONCETMP" -maxdepth 1 -name 'claude-hook-warn-read-size-gate' 2>/dev/null | grep -c .)"

# ===========================================================================
# v2.2.1 (K): an UNPARSEABLE payload fails CLOSED.
#
# Third path to the same place as PR15's missing parser and v2.2.1's broken one:
# here the parser is present AND works, but the INPUT does not parse. json_get
# returned "" for that exactly as it does for a genuinely absent field, and the
# gates read "" as "nothing to inspect, allow" — so malformed JSON, a truncated
# payload and empty stdin all exited 0 in silence, indistinguishable from a
# legitimate allow. That ambiguity is also why the first report of this read as
# a false alarm, so the message is deliberately its own.
#
# The three rows below fail in gc_read_stdin, BEFORE any Gate or branch lookup,
# so they discriminate on all three gates without a configured Gate. The
# "parsed, and legitimately allowed" rows that complete the table live in each
# gate's own section above, against repos that do have one.
# ===========================================================================
echo
echo "=== git gates: unparseable payload fails CLOSED (v2.2.1) ==="
KREPO=$(mkrepo kparse main)
KTRUNC='{"tool_name":"Bash","tool_input":{"command":"git push origin ma'
KNEEDLE="hook payload did not parse"

check "parse: no-push-main, truncated"    hooks/no-push-main.sh 2 "$KTRUNC"
check "parse: no-push-main, empty stdin"  hooks/no-push-main.sh 2 ''
check_msg "parse: no-push-main names the cause" "$ROOT/hooks/no-push-main.sh" 2 "$KTRUNC" "$KNEEDLE"
check "parse: pre-commit-test, truncated"   hooks/pre-commit-test.sh 2 "$KTRUNC"
check "parse: pre-commit-test, empty stdin" hooks/pre-commit-test.sh 2 ''
check_msg "parse: pre-commit-test names the cause" "$ROOT/hooks/pre-commit-test.sh" 2 "$KTRUNC" "$KNEEDLE"
check "parse: gate-before-merge, truncated"   hooks/gate-before-merge.sh 2 "$KTRUNC"
check "parse: gate-before-merge, empty stdin" hooks/gate-before-merge.sh 2 ''
check_msg "parse: gate-before-merge names the cause" "$ROOT/hooks/gate-before-merge.sh" 2 "$KTRUNC" "$KNEEDLE"
# The contrast that makes the rule a rule: a payload that PARSES and simply is
# not a git command is still a legitimate allow. Only "could not determine"
# refuses.
check "parse: valid non-git command allowed" hooks/no-push-main.sh 0 \
  "$(mkjson Bash 'ls -la' "$KREPO")"
# The escape hatch outranks the block, as it does on the no-parser path.
mkdir -p "$KREPO/.claude"; : > "$KREPO/.claude/git-guard-off"
printf '%s' "$KTRUNC" | ( cd "$KREPO" && bash "$ROOT/hooks/no-push-main.sh" ) >/dev/null 2>&1
expect "parse: guard-off still opens" 0 "$?"
rm -f "$KREPO/.claude/git-guard-off"

# ===========================================================================
# v2.2.1 (S): a parser that EXISTS but does not WORK is treated as ABSENT.
#
# `command -v python3` succeeds for the Windows App-Installer stub that ships on
# PATH by default (and for a conda/pyenv shim pointing at a removed env). The
# stub is not an interpreter: json_get returned "" for every field, the gates
# read an empty command, and they exited 0 — the fail-OPEN outcome PR15's
# fail-closed design exists to prevent, on the platform most users are on. A
# missing parser was detected; a broken one was not.
#
# The fixture PATH must hide node too, or node answers first and the stub is
# never reached.
# ===========================================================================
echo
echo "=== broken-parser fixtures (json_probe_ok) ==="

mkstubpath() { # <name> <tool> <stub-body-line> [extra-tool ...] -> prints dir
  msp_name="$1"; msp_tool="$2"; msp_body="$3"; shift 3
  msp=$(mkpathdir "$msp_name" "$@")
  printf '#!/bin/sh\n%s\n' "$msp_body" > "$msp/$msp_tool"
  chmod +x "$msp/$msp_tool"
  printf '%s\n' "$msp"
}
STUB_RC=$(mkstubpath stub-rc python3 'exit 3')
STUB_GARBAGE=$(mkstubpath stub-garbage python3 'echo not-json-at-all')
STUB_JQ=$(mkstubpath stub-jq python3 'exit 3' jq)
# A broken NODE is the case json_require_node exists for -- the six node-program
# hooks never call json_parser, so the probe has to run on that path too.
STUB_NODE=$(mkstubpath stub-node node 'exit 3')
STUB_NODE_PY=$(mkstubpath stub-node-py node 'exit 3' python3)

# Self-check FIRST: a fixture whose stub is invisible would prove nothing.
expect "stub PATH still shows python3" 0 "$(seen "$STUB_RC" python3)"
expect "stub PATH hides node"          1 "$(seen "$STUB_RC" node)"

check_env "broken python3 (rc!=0): gate blocks" "$STUB_RC" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")" "$NEEDLE_BLOCK"
check_env "broken python3 (garbage): gate blocks" "$STUB_GARBAGE" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")" "$NEEDLE_BLOCK"
# A WORKING backend behind a broken one is still used — the probe falls through,
# it does not give up. The feature-branch row is the discriminating one: a gate
# that had fallen back to fail-closed would block this too.
if [ -n "$HAVE_JQ" ]; then
check_env "broken python3 + jq: still enforces" "$STUB_JQ" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")"
check_env "broken python3 + jq: feature allowed" "$STUB_JQ" hooks/no-push-main.sh 0 \
  "$(mkjson Bash 'git push -u origin feature/x' "$FEATREPO")"
else
skip "broken python3 + jq fallthrough" "no jq on this host" 2
fi

# --- a broken NODE, the json_require_node entry point ------------------------
expect "stub PATH still shows node" 0 "$(seen "$STUB_NODE" node)"
check_env "broken node alone: gate blocks" "$STUB_NODE" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")" "$NEEDLE_BLOCK"
if [ -n "$HAVE_PY" ]; then
check_env "broken node + python3: gate enforces" "$STUB_NODE_PY" hooks/no-push-main.sh 2 \
  "$(mkjson Bash 'git push origin main' "$MAINREPO")"
check_env "broken node + python3: feature allowed" "$STUB_NODE_PY" hooks/no-push-main.sh 0 \
  "$(mkjson Bash 'git push -u origin feature/x' "$FEATREPO")"
# json_require_node's own path: `command -v node` SUCCEEDS here, so without the
# probe this hook would run the stub, get nothing, and fail open in silence.
check_env "broken node: require_node names the fallback" "$STUB_NODE_PY" hooks/read-size-gate.sh 0 \
  "$(mkread "$ROOT/README.md" - -)" "node not usable (found python3)"
else
skip "broken node + python3 cases" "no python3 on this host" 3
fi

# ===========================================================================
# v2.2.0 PR15 (B): the optional **Protected branches**: PROJECT_CONTEXT.md field
# ===========================================================================
echo
echo "=== **Protected branches**: field ==="

pbrepo() { # <name> <branch> <field-line|-> -> prints path
  d=$(mkrepo "$1" "$2")
  {
    echo "# PROJECT_CONTEXT"
    echo "- **Gate**: true"
    [ "$3" = "-" ] || echo "$3"
  } > "$d/PROJECT_CONTEXT.md"
  printf '%s\n' "$d"
}

PB_ABSENT=$(pbrepo pb-absent main -)
PB_DEV=$(pbrepo pb-dev develop '- **Protected branches**: develop release')
PB_DEVMAIN=$(pbrepo pb-devmain main '- **Protected branches**: develop release')
PB_NONE=$(pbrepo pb-none main '- **Protected branches**: none')
PB_COMMA=$(pbrepo pb-comma develop '**Protected branches**: `develop, release`')
# v2.2.1 (J): v2.2.0 shipped this line with a `{{DEFAULT_BRANCH}}` placeholder in
# all six templates, and no existing consumer manifest carries a DEFAULT_BRANCH
# key -- so the literal was written verbatim on sync. The resolver had no arm for
# it, returned it as a branch NAME, `main` never matched `{{DEFAULT_BRANCH}}`,
# and a push to main was ALLOWED. Reproduced in an isolated repo against
# unmodified v2.2.0 hooks: with the line present exit=0 and no output; with the
# line deleted exit=2. An unreplaced placeholder must never widen access.
PB_PLACE=$(pbrepo pb-placeholder main '- **Protected branches**: {{DEFAULT_BRANCH}}')
# ... and an EMPTY value is a typo or a truncated sync, not an opt-out. v2.2.0
# treated it exactly like `none`, which is a silent unprotect. `none` stays the
# one deliberate way to protect nothing.
PB_EMPTY=$(pbrepo pb-empty main '- **Protected branches**:')
# Half-filled, the shape a hand-edit leaves behind. A WHOLE-string placeholder
# match read this as two literal branch NAMES, neither of which is a branch --
# the unsafe direction. Substring match, so it falls back to the default.
PB_HALF=$(pbrepo pb-half main '- **Protected branches**: {{DEFAULT_BRANCH}} develop')

H=hooks/no-push-main.sh
check "field absent: main still blocked"   "$H" 2 "$(mkjson Bash 'git push' "$PB_ABSENT")"
check "develop listed: develop blocked"    "$H" 2 "$(mkjson Bash 'git push' "$PB_DEV")"
check "develop listed: main allowed"       "$H" 0 "$(mkjson Bash 'git push' "$PB_DEVMAIN")"
check "develop listed: main refspec ok"    "$H" 0 "$(mkjson Bash 'git push origin main' "$PB_DEVMAIN")"
check "develop listed: develop refspec no" "$H" 2 "$(mkjson Bash 'git push origin develop' "$PB_DEVMAIN")"
check "none: main allowed"                 "$H" 0 "$(mkjson Bash 'git push' "$PB_NONE")"
check "none: explicit main allowed"        "$H" 0 "$(mkjson Bash 'git push origin main' "$PB_NONE")"
check "comma+backticks are tolerated"      "$H" 2 "$(mkjson Bash 'git push' "$PB_COMMA")"
# the three cases that must stay distinct
check "placeholder value: main blocked"    "$H" 2 "$(mkjson Bash 'git push' "$PB_PLACE")"
# An explicit refspec takes the path whose message names the set it read —
# consumers use that line as the cheapest proof the config path works.
check_msg "placeholder falls back to the default" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push origin main' "$PB_PLACE")" "protected branch (main master)"
check_msg "placeholder WARNs, it does not go quiet" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push' "$PB_PLACE")" "still an unfilled placeholder"
check "half-filled placeholder: main blocked" "$H" 2 "$(mkjson Bash 'git push' "$PB_HALF")"
check_msg "half-filled falls back, not to literals" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push origin main' "$PB_HALF")" "protected branch (main master)"
check "empty value: main still blocked"    "$H" 2 "$(mkjson Bash 'git push' "$PB_EMPTY")"
check_msg "empty value warns about the typo" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push' "$PB_EMPTY")" "**Protected branches**: is empty"
# `none` is untouched by the two arms above: it remains the explicit opt-out.
check "none is still an opt-out"           "$H" 0 "$(mkjson Bash 'git push origin main' "$PB_NONE")"

# the merge gate reads the same field
GB=hooks/gate-before-merge.sh
check "merge on develop is gated"          "$GB" 2 "$(mkjson Bash 'git merge feature/x' "$PB_DEV")"
check "merge on unprotected main is not"   "$GB" 0 "$(mkjson Bash 'git merge feature/x' "$PB_DEVMAIN")"
# `none` unprotects the BRANCH rules only: a PR merge is a merge on any branch.
check "none: gh pr merge still gated"      "$GB" 2 "$(mkjson Bash 'gh pr merge 1 --squash' "$PB_NONE")"

# ===========================================================================
echo
echo "----------------------------------------------------------------"
# The total is printed so a wrong `skip <n>` count is visible immediately: it
# is host-INDEPENDENT, while the three tallies are not.
echo "test-hooks.sh: $pass passed, $fail failed, $skipped skipped ($((pass + fail + skipped)) assertions)"
[ "$fail" -eq 0 ] || exit 1
echo "ALL HOOK FIXTURES PASSED"
exit 0
