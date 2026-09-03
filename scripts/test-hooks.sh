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

# Environment leak, found the first time this repo ran its own **Gate** (v2.2.5).
# run-gate.sh exports RUN_GATE_ACTIVE=1 before running the gate command, so
# every fixture below that nests run-gate.sh in a throwaway repo inherits it
# and trips the recursion guard: 342/0 standalone, 323/19 under run-gate.sh.
# A suite that answers differently depending on who invoked it is the bug, and
# this is the same class as the per-case PATH and TMPDIR masking further down.
# The one case that TESTS the guard sets the variable itself (search
# RUN_GATE_ACTIVE=1 below) — an explicit per-case set survives this unset.
#
# RUN_GATE_TERMINAL leaks the same way and in the WORSE direction (v2.2.5 round
# 4). Under self-gating, R5's `RUN_GATE_ACTIVE=1` case trips the inner recursion
# guard, which touches the marker at the path the REAL OUTER run belongs to.
# run-gate.sh's clamp then sees that marker and does not fire, so a genuinely
# retryable 78 would read as terminal — inverted advice, produced by the suite
# on the toolkit's own gate. Latent only because the chain must also exit
# exactly 78.
unset RUN_GATE_ACTIVE
unset RUN_GATE_TERMINAL

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

mkjson_nocmd() { # <tool_name> <cwd> -- a payload with NO command key at all
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{},"cwd":"%s"}\n' \
    "$(jesc "$1")" "$(jesc "$2")"
}

# v2.2.6 round 2 -- THE 14th FAIL-OPEN. A payload that PARSES and carries a
# `command` key whose read yields nothing. This is the state, not the cause: the
# traced live case was a transient empty read on a real `git commit`, which
# cannot be fabricated deterministically and does not need to be -- an empty
# string, a non-scalar value and a transient interpreter failure are the same
# cannot-determine and warrant the same refusal. Distinct from mkjson_nocmd
# above, whose key is ABSENT and which must still be ALLOWED.
mkjson_emptycmd() { # <tool_name> <cwd>
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":""},"cwd":"%s"}\n' \
    "$(jesc "$1")" "$(jesc "$2")"
}

# The same state with the tool_name ALSO unread -- the neighbouring door. The
# gates are registered on Bash|PowerShell, so an empty tool_name on a live
# invocation is the identical cannot-determine one field over.
mkjson_emptycmd_notool() { # <cwd>
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"","tool_input":{"command":""},"cwd":"%s"}\n' \
    "$(jesc "$1")"
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

# The negative of check_msg: exit code AND the ABSENCE of a stderr substring.
# Needed where the exit code alone does not discriminate -- pre-commit-test's
# fail-open arm (no field found) also exits 0, so only the missing WARN says
# the field was actually read.
check_nomsg() { # <label> <hook_abs_path> <expected_exit> <json> <forbidden-needle>
  label="$1"; hookp="$2"; want="$3"; json="$4"; needle="$5"
  errf="$TMPROOT/check_nomsg.err"
  cntmp="$TMPROOT/check_nomsg.tmp"; rm -rf "$cntmp"; mkdir -p "$cntmp"
  printf '%s' "$json" | TMPDIR="$cntmp" bash "$hookp" >/dev/null 2>"$errf"
  got=$?
  if [ "$got" = "$want" ] && ! grep -qF "$needle" "$errf"; then
    printf 'PASS  %-42s (exit %s)\n' "$label" "$got"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s WITHOUT "%s", got %s: %s)\n' \
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
# The JSON READER the assertions use is the hooks' own lib -- so the suite is
# self-testing for the mechanism it guards. Safe here precisely because the
# builders above share none of its backends. Sourced BEFORE the HAVE_* probes
# because those need json_probe_ok; see immediately below.
. "$ROOT/hooks/lib/json.sh"

# `command -v` is NOT enough, and this harness had exactly the bug v2.2.1 fixed
# inside json_require_node. Windows ships a non-interpreter App-Installer STUB at
# %LOCALAPPDATA%/Microsoft/WindowsApps/python3 that is on PATH by default: it
# satisfies `command -v python3` and prints "Python was not found" when run. So
# on a host with no real python3, HAVE_PY was TRUE, the python3-only blocks ran,
# mkpathdir copied the stub into the python3-only PATH, and eight cases failed
# with no indication that the cause was a fake interpreter rather than a hook.
# The hooks decide with `command -v` AND json_probe_ok; the suite that tests
# them must use the same definition of "present", or it measures a different
# machine than the one the hooks see.
have_backend() { # <backend>
  command -v "$1" >/dev/null 2>&1 && json_probe_ok "$1"
}
HAVE_NODE=1; have_backend node    || HAVE_NODE=""
HAVE_PY=1;   have_backend python3 || HAVE_PY=""
HAVE_JQ=1;   have_backend jq      || HAVE_JQ=""
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
# v2.3.0: the ACCEPTED FALSE POSITIVE, asserted POSITIVELY. This gate is
# fail-CLOSED and scans the whole command string, which is what makes the
# `bash -c "…"` wrapper above unevadable; the price is that `echo "git push
# origin main"` blocks too, and that price is deliberate (docs/verification.md).
# v2.3.0 taught hooks/enforce-delegation.sh to strip heredoc bodies, so the
# obvious next "improvement" is to strip quoted literals HERE as well — which
# would reopen every wrapper form not on an allowlist. This line turns red on
# that change, so it has to be argued rather than slipped in.
check "echo of a push string still blocks" "$H" 2 "$(mkjson Bash 'echo "git push origin main"' "$FEATREPO")"
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

# --- v2.2.6 round 2: THE 14th FAIL-OPEN. A parsed payload that HAS a command
# key we could not read is a gate that cannot do its job, and must refuse. The
# line above is the control that keeps the refusal NARROW: an ABSENT key still
# allows, because making that refuse would hard-block every Bash call.
check_msg "empty command key refuses" "$ROOT/$H" 2 "$(mkjson_emptycmd Bash "$MAINREPO")" "could not read"
check "empty command + empty tool"       "$H" 2 "$(mkjson_emptycmd_notool "$MAINREPO")"
check "other tool with a command key"    "$H" 0 "$(mkjson_emptycmd SomeOtherTool "$MAINREPO")"

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

# --- v2.2.6 round 2: THE 14th FAIL-OPEN, the hook it was traced in. A parsed
# payload carrying an unreadable command key exited 0 here, and the commit
# completed in ~1s against an 87s **Test**. The line above is the control that
# keeps the refusal narrow: an ABSENT key still allows.
check_msg "empty command key refuses" "$ROOT/$H" 2 "$(mkjson_emptycmd Bash "$BADREPO")" "could not read"
check "empty command + empty tool"       "$H" 2 "$(mkjson_emptycmd_notool "$BADREPO")"
check "other tool with a command key"    "$H" 0 "$(mkjson_emptycmd SomeOtherTool "$BADREPO")"
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

# --- v2.2.4 (consumer feedback, Yutraffic-Challenge): a UTF-8 BOM defeats every
# `**Key**:` extractor. The server strips the BOM for hashing and the hooks did
# not for grepping, so the same file was two different files depending on which
# subsystem looked. The BOM sits at byte 0, INSIDE line 1, so `^` stopped
# abutting the key -- and "no field found" is this hook's fail-OPEN arm (warn
# and allow), i.e. a silently ungated commit rather than a parse error.
#
# The arms are a PAIR by position (key on line 1, key on line 2) crossed with a
# PAIR by polarity, and both pairs are load-bearing:
#   * line 2 is the shape every consumer file actually has (BOM at byte 0, key
#     further down) and it passed BEFORE the fix -- the regression being guarded
#     is "someone moved the key up", not "someone added a BOM". A line-1-only
#     fixture would also pass a partial fix that only strips a BOM immediately
#     followed by the key.
#   * the `false`/exit-2 arms alone cannot discriminate: with a partial fix that
#     matches but leaves the BOM glued to the value, `bash -c '<BOM>false'` is
#     command-not-found, also nonzero, also a block. The `true` arms carry the
#     discrimination, and their exit 0 is shared with the pre-fix fail-open --
#     so the ABSENCE of the WARN is the assertion that means "field was read".
BOM=$(printf '\357\273\277')
NOFIELD_WARN="WARN: pre-commit-test: no Test/Gate command in PROJECT_CONTEXT.md"
BOM_L1_OK=$(mkrepo bom-l1-ok main)
BOM_L2_OK=$(mkrepo bom-l2-ok main)
BOM_L1_BAD=$(mkrepo bom-l1-bad main)
BOM_L2_BAD=$(mkrepo bom-l2-bad main)
printf '%s- **Test**: `true`\n'          "$BOM" > "$BOM_L1_OK/PROJECT_CONTEXT.md"
printf '%s# ctx\n- **Test**: `true`\n'   "$BOM" > "$BOM_L2_OK/PROJECT_CONTEXT.md"
printf '%s- **Test**: `false`\n'         "$BOM" > "$BOM_L1_BAD/PROJECT_CONTEXT.md"
printf '%s# ctx\n- **Test**: `false`\n'  "$BOM" > "$BOM_L2_BAD/PROJECT_CONTEXT.md"
check_nomsg "BOM + Test on line 1 is read" "$ROOT/hooks/pre-commit-test.sh" 0 \
  "$(mkjson Bash 'git commit -m x' "$BOM_L1_OK")" "$NOFIELD_WARN"
check_nomsg "BOM + Test on line 2 is read" "$ROOT/hooks/pre-commit-test.sh" 0 \
  "$(mkjson Bash 'git commit -m x' "$BOM_L2_OK")" "$NOFIELD_WARN"
check "BOM + failing Test on line 1"     "$H" 2 "$(mkjson Bash 'git commit -m x' "$BOM_L1_BAD")"
check "BOM + failing Test on line 2"     "$H" 2 "$(mkjson Bash 'git commit -m x' "$BOM_L2_BAD")"

# The same pair through the **Gate** path, which reaches run-gate.sh -- that
# script is standalone (no lib), so it repeats the GC_KEY_PRE literal and needs
# its own behavioural arm, not only the census assertion in
# verify-template-consistency.sh.
BOM_G1_OK=$(mkrepo bom-g1-ok main)
BOM_G1_BAD=$(mkrepo bom-g1-bad main)
printf '%s- **Gate**: `true`\n'  "$BOM" > "$BOM_G1_OK/PROJECT_CONTEXT.md"
printf '%s- **Gate**: `false`\n' "$BOM" > "$BOM_G1_BAD/PROJECT_CONTEXT.md"
check_nomsg "BOM + Gate on line 1 is read" "$ROOT/hooks/pre-commit-test.sh" 0 \
  "$(mkjson Bash 'git commit -m x' "$BOM_G1_OK")" "$NOFIELD_WARN"
check "BOM + failing Gate on line 1"     "$H" 2 "$(mkjson Bash 'git commit -m x' "$BOM_G1_BAD")"

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

# --- v2.2.6 round 2: THE 14th FAIL-OPEN, third instance. The refusal is checked
# BEFORE this hook's tool case, because that case's `*)` arm is the door an
# unreadable tool_name walks through — hence the empty-tool arm below.
check_msg "empty command key refuses" "$ROOT/$H" 2 "$(mkjson_emptycmd Bash "$GATEREPO")" "could not read"
check "empty command + empty tool"       "$H" 2 "$(mkjson_emptycmd_notool "$GATEREPO")"
check "other tool with a command key"    "$H" 0 "$(mkjson_emptycmd SomeOtherTool "$GATEREPO")"

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

# ---------------------------------------------------------------------------
# v2.4.0 (A6): merging FROM a protected branch is refused before the artifact
# is read. THE CONTROL IS TWO-SIDED AND THE POSITIVE ARM IS THE LOAD-BEARING
# ONE: the protected repo below is given a PERFECTLY FRESH, sha-matching
# artifact, so without the guard this call exits 0. That is the exact live
# defect — a green artifact for `main`, permitting a merge of the PR branch's
# entirely different content. Delete the gc_on_main block in
# gate-before-merge.sh and this fixture flips 2 -> 0 while every other
# gate-before-merge fixture stays green; that is what makes it a control and
# not decoration. The negative arm (feature branch, same fresh artifact, 0)
# is what proves the guard is not simply blocking everything.
# ---------------------------------------------------------------------------
GATEREPOSHA=$(git -C "$GATEREPO" rev-parse HEAD)
writeartifact "$GATEREPO" "$GATEREPOSHA"
check_msg "(A6) merge from a protected branch refuses despite a fresh artifact" \
  "$ROOT/$H" 2 "$(mkjson_mcp mcp__MCP_DOCKER__merge_pull_request "$GATEREPO")" \
  "refuses this operation on a protected branch"
check_msg "(A6) protected-branch refusal names the head to gate instead" \
  "$ROOT/$H" 2 "$(mkjson Bash 'gh pr merge 12 --squash' "$GATEREPO")" \
  "check out the merge target"
# Negative arm: the SAME merge shape on a feature branch, with a fresh
# artifact, is allowed — HEAD is the merge content there, so the comparison is
# meaningful and the guard must stay out of the way.
check "(A6) same merge on a feature branch is still allowed" \
  "$H" 0 "$(mkjson Bash 'gh pr merge 12 --squash' "$GATEFEAT")"
# `**Protected branches**: none` is the one deliberate way to protect nothing;
# the A6 refusal must honour it rather than keying on the branch NAME.
GATENONE=$(mkrepo gateprotnone main)
printf '# ctx\n\n- **Gate**: `bash hooks/run-gate.sh`\n- **Protected branches**: none\n' > "$GATENONE/PROJECT_CONTEXT.md"
writeartifact "$GATENONE" "$(git -C "$GATENONE" rev-parse HEAD)"
check "(A6) 'Protected branches: none' is honoured, merge on main allowed" \
  "$H" 0 "$(mkjson Bash 'gh pr merge 12 --squash' "$GATENONE")"
# Defect 1: the staleness message must name BOTH keys, not just the sha — the
# tree key is the half that survives a squash.
writeartifact "$GATEFEAT" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
check_msg "(A6) staleness message reports the tree key too" \
  "$ROOT/$H" 2 "$(mkjson Bash 'gh pr merge 5 --squash' "$GATEFEAT")" \
  "artifact tree:"
check_msg "(A6) staleness message names WHICH head to gate" \
  "$ROOT/$H" 2 "$(mkjson Bash 'gh pr merge 5 --squash' "$GATEFEAT")" \
  "head that is actually being MERGED"
writeartifact "$GATEFEAT" "$FEATSHA"

# ===========================================================================
# v3.0.1 — THE A6 FIX. Fixtures first.
#
# NONE of the repos below is ever given a gate artifact, deliberately. Every
# want-0 row therefore proves the operation was not gated AT ALL, and every
# want-2 row in the SAME repo proves the **Gate** field is configured and the
# hook reached the A6 decision — the pairing is what keeps a want-0 row from
# passing vacuously on the "no Gate command configured" exit above.
#
# `mkrepo` builds no remote, and half of A6 is about a branch's UPSTREAM, so
# the provenance fixtures are real clones: origin advances, the clone fetches,
# and the clone's `main` is then behind `origin/main` — the exact routine state
# the ancestry rule would have blocked.
# ===========================================================================
A6CTX='# ctx\n\n- **Gate**: `bash hooks/run-gate.sh`\n'
A6MAIN=$(mkrepo a6main main)
printf '%b' "$A6CTX" > "$A6MAIN/PROJECT_CONTEXT.md"
git -C "$A6MAIN" branch feature/x >/dev/null 2>&1

A6ORIGIN=$(mkrepo a6origin main)
a6clone() { # <name> -> a clone of A6ORIGIN with a **Gate** field
  git clone -q "$A6ORIGIN" "$TMPROOT/$1" >/dev/null 2>&1
  git -C "$TMPROOT/$1" config user.email t@t.t
  git -C "$TMPROOT/$1" config user.name t
  git -C "$TMPROOT/$1" config commit.gpgsign false
  printf '%b' "$A6CTX" > "$TMPROOT/$1/PROJECT_CONTEXT.md"
  printf '%s\n' "$TMPROOT/$1"
}
A6CLONE=$(a6clone a6clone)
echo more > "$A6ORIGIN/next.txt"
git -C "$A6ORIGIN" add next.txt >/dev/null 2>&1
git -C "$A6ORIGIN" commit -q -m next >/dev/null 2>&1
git -C "$A6CLONE" fetch -q origin >/dev/null 2>&1
git -C "$A6CLONE" branch feature/x >/dev/null 2>&1
# The diverged twin: a local commit on `main` that the upstream does not have,
# so the same `git merge origin/main` would create a merge commit.
A6DIV=$(a6clone a6div)
git -C "$A6DIV" reset -q --hard HEAD~1 >/dev/null 2>&1
echo local > "$A6DIV/local.txt"
git -C "$A6DIV" add local.txt >/dev/null 2>&1
git -C "$A6DIV" commit -q -m local >/dev/null 2>&1
# The negative arm for every A6 rule: the same shapes on a feature branch.
A6FEATCO=$(a6clone a6featco)
git -C "$A6FEATCO" checkout -q -b feature/co >/dev/null 2>&1
# v3.0.2 (finding 54): the two dishonest-upstream twins. The gate reads CONFIG,
# not the ref, so `branch.main.merge` pointing at a branch that does not exist
# locally is exactly the state being modelled — a re-pointed upstream.
A6ROGUEUP=$(a6clone a6rogueup)
git -C "$A6ROGUEUP" config branch.main.merge refs/heads/rogue
A6NOUP=$(a6clone a6noup)
git -C "$A6NOUP" config --unset branch.main.remote >/dev/null 2>&1
git -C "$A6NOUP" config --unset branch.main.merge >/dev/null 2>&1

# ---------------------------------------------------------------------------
# v3.0.1 item 1 — `git merge --abort|--continue|--quit` are EXEMPT.
#
# Measured on `main` before the fix: all three exited 2. A consumer in a
# conflicted merge on a protected branch could not get out except through
# `.claude/git-guard-off`. Delete the a6_merge_exempt call in
# gate-before-merge.sh and the first four rows flip 0 -> 2.
#
# The fifth row is the control on the exemption itself: gc_segments strips
# quotes, so a `-m` message body carrying the word `--abort` must NOT buy a
# real merge the exemption. It flips 2 -> 0 if the non-flag-token requirement
# is dropped from a6_merge_exempt.
# ---------------------------------------------------------------------------
check "(A6.1) merge --abort on a protected branch"     "$H" 0 "$(mkjson Bash 'git merge --abort' "$A6MAIN")"
check "(A6.1) merge --continue on a protected branch"  "$H" 0 "$(mkjson Bash 'git merge --continue' "$A6MAIN")"
check "(A6.1) merge --quit on a protected branch"      "$H" 0 "$(mkjson Bash 'git merge --quit' "$A6MAIN")"
check "(A6.1) -C target on main, --abort exempt"       "$H" 0 "$(mkjson Bash "git -C $A6MAIN merge --abort" "$A6CLONE")"
check "(A6.1) --abort inside -m does NOT exempt"       "$H" 2 "$(mkjson Bash 'git merge -m "retry after --abort" feature/x' "$A6MAIN")"

# ---------------------------------------------------------------------------
# v3.0.2 item 1 — THE CATCH-UP EXEMPTION IS GONE. `git merge` on a protected
# branch is gated unconditionally, `--abort/--continue/--quit` excepted.
#
# v3.0.1 allowed `git merge --ff-only <this branch's upstream>` when HEAD was
# already an ancestor of it. The exemption resolved the ref by NAME and trusted
# its VALUE, and the value is writable by any local command:
#
#   git update-ref refs/remotes/origin/main <sha>   verdict 0  UNGATED
#   git merge --ff-only origin/main                 verdict 0  ALLOWED
#     -> EXECUTED, landed "rogue: never gated, never reviewed" on main, with
#        branch config untouched and main@{upstream} still reading origin/main.
#
# ROWS 1-2 ARE THE FLIPPED ONES (0 -> 2 in v3.0.2). Restore the a6_merge_catchup
# call and they flip back — that is the delete-the-guard control for item 1.
# Row 3 is the same defect spelled out as a chain. The remaining rows were
# already gated and stay gated; they now pass through the SAME arm, so they no
# longer discriminate anything about the upstream comparison, which is the point
# of deleting it.
#
# The catch-up capability is not lost: `git pull --ff-only` (A6.3) fetches
# first, so it re-reads the tracking ref instead of trusting it.
# ---------------------------------------------------------------------------
check "(A6.2) catch-up merge of own upstream GATED"    "$H" 2 "$(mkjson Bash 'git merge --ff-only origin/main' "$A6CLONE")"
check "(A6.2) bare-named catch-up GATED"               "$H" 2 "$(mkjson Bash 'git merge origin/main' "$A6CLONE")"
check "(A6.2) poisoned-ref chain: update-ref + merge"  "$H" 2 "$(mkjson Bash 'git update-ref refs/remotes/origin/main HEAD && git merge --ff-only origin/main' "$A6CLONE")"
check "(A6.2) --no-ff of the upstream is gated"        "$H" 2 "$(mkjson Bash 'git merge --no-ff origin/main' "$A6CLONE")"
check "(A6.2) --squash of the upstream is gated"       "$H" 2 "$(mkjson Bash 'git merge --squash origin/main' "$A6CLONE")"
check "(A6.2) a ref the upstream lacks is gated"       "$H" 2 "$(mkjson Bash 'git merge feature/x' "$A6CLONE")"
check "(A6.2) diverged local: upstream merge gated"    "$H" 2 "$(mkjson Bash 'git merge origin/main' "$A6DIV")"
check "(A6.2) no upstream configured: merge gated"     "$H" 2 "$(mkjson Bash 'git merge feature/x' "$A6MAIN")"
check "(A6.2) unresolvable target is gated"            "$H" 2 "$(mkjson Bash 'git merge origin/zz-nope' "$A6CLONE")"
check "(A6.2) catch-up on a FEATURE branch allowed"    "$H" 0 "$(mkjson Bash 'git merge origin/main' "$A6FEATCO")"

# ---------------------------------------------------------------------------
# v3.0.1 item 3 — `git pull` on a protected branch, gated by FORM.
#
# A pull fetches first, so no pre-fetch check can be sound: a STALE
# remote-tracking ref answers "adds nothing" confidently and wrongly about an
# object that is not the one being merged, and `ls-remote` costs ~1.4 s per
# PreToolUse call and fails offline. Only the refspec-free `--ff-only` form is
# provably safe before the fetch. `git pull` was not gated at all before
# v3.0.1, so rows 1, 3 and 4 flip 2 -> 0 when the pull arm is deleted.
# ---------------------------------------------------------------------------
check "(A6.3) bare pull on a protected branch gated"   "$H" 2 "$(mkjson Bash 'git pull' "$A6CLONE")"
check "(A6.3) pull --ff-only, honest upstream, allowed" "$H" 0 "$(mkjson Bash 'git pull --ff-only' "$A6CLONE")"
check "(A6.3) pull --rebase is gated"                  "$H" 2 "$(mkjson Bash 'git pull --rebase' "$A6CLONE")"
check "(A6.3) pull on a feature branch is untouched"   "$H" 0 "$(mkjson Bash 'git pull' "$A6FEATCO")"

# ---------------------------------------------------------------------------
# v3.0.2 item 2 — the pull arm compares NAMES.
#
# "Refspec-free means the target is the configured upstream BY CONSTRUCTION"
# was the stated reason the form was safe, and it was false. `branch.<cur>.merge`
# is re-pointable and re-pointing is ungated on both gates:
#
#   git branch -u origin/rogue main   verdict 0   (ungated)
#   git pull --ff-only                verdict 0   -> HEAD MOVED, rogue landed
#
# So the refspec-free form now requires this branch's own config to name itself,
# and `--ff-only <remote> <cur>` — reported as a FALSE POSITIVE by a consumer,
# and the more provably safe of the two, because it NAMES what it lands — is
# allowed. Delete the a6_pull_catchup call (restore the old
# "count==0 && --ff-only" test) and rows 1, 3 and 5 flip: 1 and 3 go 2 -> 0
# (the bypass reopens) and 5 goes 0 -> 2 (the false positive returns).
#
# EVERY want-0 IS PAIRED IN ITS OWN REPO: A6ROGUEUP and A6NOUP each carry a
# want-2 refspec-free row and a want-0 two-operand row, so neither can be
# passing vacuously through the "no **Gate** configured" exit.
# ---------------------------------------------------------------------------
check "(A6.3) re-pointed upstream: --ff-only GATED"    "$H" 2 "$(mkjson Bash 'git pull --ff-only' "$A6ROGUEUP")"
check "(A6.3) re-pointed upstream: named form allowed" "$H" 0 "$(mkjson Bash 'git pull --ff-only origin main' "$A6ROGUEUP")"
check "(A6.3) no upstream configured: --ff-only GATED" "$H" 2 "$(mkjson Bash 'git pull --ff-only' "$A6NOUP")"
check "(A6.3) no upstream: the named form still ok"    "$H" 0 "$(mkjson Bash 'git pull --ff-only origin main' "$A6NOUP")"
check "(A6.3) --ff-only origin main allowed"           "$H" 0 "$(mkjson Bash 'git pull --ff-only origin main' "$A6CLONE")"
check "(A6.3) --ff-only origin feature/x gated"        "$H" 2 "$(mkjson Bash 'git pull --ff-only origin feature/x' "$A6CLONE")"
check "(A6.3) --ff-only origin main:main gated"        "$H" 2 "$(mkjson Bash 'git pull --ff-only origin main:main' "$A6CLONE")"
check "(A6.3) --ff-only origin main HEAD gated"        "$H" 2 "$(mkjson Bash 'git pull --ff-only origin main HEAD' "$A6CLONE")"
check "(A6.3) named form without --ff-only gated"      "$H" 2 "$(mkjson Bash 'git pull origin main' "$A6CLONE")"
# THE ROW WHERE ITEM 2 AND THE v3.0.2 REDIRECT STRIP MEET: the operand count
# that decides the two-operand form is a6_nonflag, which strips redirections
# first. Count `2>&1` as an operand and this is a three-operand pull -> gated.
check "(A6.3) --ff-only origin main 2>&1 allowed"      "$H" 0 "$(mkjson Bash 'git pull --ff-only origin main 2>&1' "$A6CLONE")"

# ---------------------------------------------------------------------------
# v3.0.2 item 3 — NOTHING MAY MOVE WHAT A GATED CLAUSE RESOLVES TO.
#
# Item 2 reads mutable config, so a same-call re-point defeats it. v3.0.1's
# ordering rule does not reach these: that rule is keyed on CHECKOUT TARGETS,
# and `git branch -u` is not a checkout. Two shapes:
#
#   PRECEDING CLAUSE  git branch -u origin/rogue main && git pull --ff-only
#                     -> ungated before this item, HEAD moved, rogue landed
#   SAME CLAUSE       git -c remote.evil.url=<other> -c branch.main.remote=evil
#                        pull --ff-only
#                     -> rc=0, fast-forward, foreign content, while
#                        branch.main.merge on disk still read refs/heads/main
#
# The second is ONE clause, so no rule about what may PRECEDE a gated clause can
# see it — hence the separate inline-config test on the invocation's own argv,
# written broadly (`-c`, `--config-env`, `GIT_CONFIG_*`) rather than as a list
# of keys, so a new key cannot silently join it.
#
# `--config-env` also exposed a second defect, and the row for it is the last
# one below: the lib's GC_GIT_PRE allows `-C` and `-c` between `git` and the
# subcommand and NOTHING ELSE, so that clause did not match as a `pull` AT ALL
# and fell through ungated for a reason unrelated to this item. a6_is_git_sub
# compensates in the hook; delete it and that row flips 2 -> 0 while the
# `-c` rows stay green, which is what makes the two causes separable.
#
# Delete the mutated/a6_inline_config arms in the pull path and rows 1-8 flip
# 2 -> 0. The want-0 pairs live in the SAME repos: A6CLONE's honest
# `git pull --ff-only` above, and the two feature-branch rows here.
# ---------------------------------------------------------------------------
check "(A6.8) branch -u then pull is gated"            "$H" 2 "$(mkjson Bash 'git branch -u origin/rogue main && git pull --ff-only' "$A6CLONE")"
check "(A6.8) config branch.* then pull is gated"      "$H" 2 "$(mkjson Bash 'git config branch.main.merge refs/heads/rogue && git pull --ff-only' "$A6CLONE")"
check "(A6.8) remote set-url then pull is gated"       "$H" 2 "$(mkjson Bash 'git remote set-url origin /nope && git pull --ff-only' "$A6CLONE")"
check "(A6.8) fetch with a dest refspec then pull"     "$H" 2 "$(mkjson Bash 'git fetch /nope +refs/heads/main:refs/remotes/origin/main && git pull --ff-only' "$A6CLONE")"
check "(A6.8) update-ref then pull is gated"           "$H" 2 "$(mkjson Bash 'git update-ref refs/remotes/origin/main HEAD && git pull --ff-only' "$A6CLONE")"
check "(A6.8) -c branch.*.remote pull is gated"        "$H" 2 "$(mkjson Bash 'git -c remote.evil.url=/nope -c branch.main.remote=evil pull --ff-only' "$A6CLONE")"
check "(A6.8) -c branch.*.merge pull is gated"         "$H" 2 "$(mkjson Bash 'git -c branch.main.merge=refs/heads/rogue pull --ff-only' "$A6CLONE")"
check "(A6.8) GIT_CONFIG_* env prefix is gated"        "$H" 2 "$(mkjson Bash 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=branch.main.remote GIT_CONFIG_VALUE_0=evil git pull --ff-only' "$A6CLONE")"
check "(A6.8) --config-env pull is gated"              "$H" 2 "$(mkjson Bash 'git --config-env=branch.main.remote=X pull --ff-only' "$A6CLONE")"
# A benign `-c` on a gated invocation is refused too. That is the honest cost of
# writing the rule broadly, and the DENY message says to re-run without it.
check "(A6.8) a benign -c on a protected pull is gated" "$H" 2 "$(mkjson Bash 'git -c core.pager=cat pull --ff-only' "$A6CLONE")"
# THE REGRESSION GUARD for the over-correction: pulls on a feature branch stay
# untouched, mutation or not, and the v3.0.1 checkout-target rule is unchanged.
check "(A6.8) mutation + pull on a feature branch ok"  "$H" 0 "$(mkjson Bash 'git branch -u origin/rogue main && git pull --ff-only' "$A6FEATCO")"
check "(A6.8) -c pull on a feature branch is ok"       "$H" 0 "$(mkjson Bash 'git -c core.pager=cat pull --ff-only' "$A6FEATCO")"
check "(A6.8) checkout feature/z && merge still ok"    "$H" 0 "$(mkjson Bash 'git checkout feature/z && git merge feature/y' "$A6FEATCO")"
check_msg "(A6.8) the -c refusal says to drop the -c" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git -c core.pager=cat pull --ff-only' "$A6CLONE")" "WITHOUT the '-c'"
check_msg "(A6.8) the chained refusal quotes the clause" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git branch -u origin/rogue main && git pull --ff-only' "$A6CLONE")" "earlier clause:"

# ---------------------------------------------------------------------------
# v3.0.2 — SHELL REDIRECTIONS ARE NOT OPERANDS.
#
# NP is set here rather than further down: this section is the first to feed the
# push gate, and both gates share the defect.
#
# Measured on `main` right after v3.0.1 shipped: `git pull --ff-only 2>&1` was
# BLOCKED, and the block message reported `refspec/remote named: present
# (2>&1 )`. `2>&1` is not a refspec; it is a token the operand counter had no
# reason to see. Two halves, opposite polarity:
#
#   FALSE POSITIVE — an ordinary scripted `git pull --ff-only 2>&1` and the
#   `git merge --abort 2>&1` escape from a conflicted merge on a protected
#   branch were refused. The --abort one is the worse of the two: v3.0.1 exists
#   because that escape was blocked, and a redirection put it back.
#   FAIL-OPEN — `git push origin 2>&1` on a protected branch counted TWO
#   non-flag tokens, so gc_has_refspec read "destination named", the
#   current-branch check was skipped, and neither gate blocked the push.
#
# THE OVER-GREEDY STRIP IS THE REAL HAZARD, so the want-2 rows below are the
# load-bearing ones. A strip that drops anything after a `>`, or any token
# containing one, turns a REAL refspec into no-refspec and reopens exactly the
# hole A6 closed. Both arms were run, and both are reported because one alone
# proves nothing:
#   REMOVE the a6_strip_redir / np_strip_redir calls -> 6 rows flip
#     (1, 2, 5, 9 go 0 -> 2; 6 and 8 go 2 -> 0, the fail-open half).
#   REPLACE them with a naive "drop any token containing > or <" -> only row 9
#     flips (0 -> 2). Rows 1-8 all put the redirect LAST, where that variant
#     happens to be right — which is exactly why row 9 and row 10 exist.
# Row 10 is the one that catches the two genuinely greedy shapes, both measured
# against it: "eat everything after a redirect" and "always skip the token
# after a redirect" each leave `git push origin 2>&1 main` with no protected
# destination and flip it 2 -> 0.
# ---------------------------------------------------------------------------
NP=hooks/no-push-main.sh
check "(A6.7) pull --ff-only 2>&1 allowed"             "$H" 0 "$(mkjson Bash 'git pull --ff-only 2>&1' "$A6CLONE")"
check "(A6.7) merge --abort 2>&1 stays exempt"         "$H" 0 "$(mkjson Bash 'git merge --abort 2>&1' "$A6MAIN")"
check "(A6.7) pull with a refspec AND 2>&1 gated"      "$H" 2 "$(mkjson Bash 'git pull origin feature/x 2>&1' "$A6CLONE")"
check "(A6.7) 2>&1 inside -m does NOT exempt"          "$H" 2 "$(mkjson Bash 'git merge -m "note 2>&1" --abort' "$A6MAIN")"
check "(A6.7) pull --ff-only >/dev/null 2>&1 allowed"  "$H" 0 "$(mkjson Bash 'git pull --ff-only >/dev/null 2>&1' "$A6CLONE")"
check "(A6.7) redirect-only push still branch-checked" "$NP" 2 "$(mkjson Bash 'git push origin 2>&1' "$A6CLONE")"
check "(A6.7) named destination survives the strip"    "$NP" 0 "$(mkjson Bash 'git push origin feature/x 2>&1' "$A6CLONE")"
check "(A6.7) merge gate sees the same push"           "$H" 2 "$(mkjson Bash 'git push origin 2>&1' "$A6CLONE")"
check "(A6.7) separated redirect target not an operand" "$H" 0 "$(mkjson Bash 'git pull --ff-only > /dev/null' "$A6CLONE")"
# THE ROW THAT DISCRIMINATES A WORKING STRIP FROM A GREEDY ONE. The redirect
# sits BETWEEN the remote and the ref, on a FEATURE branch — so the only thing
# that can block it is the explicit `main` destination surviving the strip.
# "Drop everything after the first `>`" leaves `origin 2` and it flips 2 -> 0;
# "always skip the token after a redirect" eats `main` and it flips 2 -> 0.
# The rows above cannot tell either of those from a correct strip, because in
# them the redirect is the LAST token.
check "(A6.7) refspec AFTER a redirect survives"       "$NP" 2 "$(mkjson Bash 'git push origin 2>&1 main' "$A6FEATCO")"

# ---------------------------------------------------------------------------
# v3.0.1 (consumer report) — THE BRANCH-CHANGE-FIRST BYPASS, in BOTH gates.
#
# Every payload below is fed to the hook; NOTHING is executed. Running
# `git checkout main && git push` to test this would risk a real unguarded push.
#
# The premise these gates read (the current branch) is one the command they gate
# can change, and they are PreToolUse hooks — they run first. So
# `git checkout main && git merge feature/x` was evaluated on the feature
# branch. Worse than a skip: gate-before-merge FELL THROUGH to the artifact
# comparison and ran it under the feature-branch premise, so a fresh artifact
# made it PASS — a green receipt for a merge it never checked.
#
# THE TWO ARMS MUST DIVERGE, and before the fix they were both `exit 0` for
# opposite reasons:
#   chained,   cwd on a feature branch  -> must GATE
#   unchained, cwd on a feature branch  -> must still PASS
# The second is the toolkit's own merge protocol — an agent merging its own PR
# from its worktree is on a feature branch. A fix that gated it would block every
# worktree-isolated merge while reading as "the fix works".
#
# KEYED ON THE CHECKOUT'S TARGET, not its presence: `git checkout feature/z &&
# git merge feature/y` lands nothing near a protected branch and must stay
# allowed. A target-blind refusal is the over-correction wearing a plausible
# face. ORDER matters too — a gated clause placed BEFORE the checkout is the
# recommended flow and stays allowed.
# ---------------------------------------------------------------------------
# A PERFECTLY FRESH, sha-matching artifact, so the `gh pr merge` row below is a
# real control rather than one that exits 2 because no artifact exists. Without
# the fix that row takes the feature-branch path, the artifact comparison
# PASSES, and the merge proceeds with a green receipt — the false green this
# whole section is about. It must be the refusal that stops it, not an absence.
writeartifact "$A6FEATCO" "$(git -C "$A6FEATCO" rev-parse HEAD)"
check "(A6.6) checkout main && merge is refused"      "$H" 2 "$(mkjson Bash 'git checkout main && git merge feature/co' "$A6FEATCO")"
check "(A6.6) switch main && merge is refused"        "$H" 2 "$(mkjson Bash 'git switch main && git merge feature/co' "$A6FEATCO")"
check "(A6.6) checkout main && gh pr merge refused"   "$H" 2 "$(mkjson Bash 'git checkout main && gh pr merge 3' "$A6FEATCO")"
check "(A6.6) checkout main && bare pull refused"     "$H" 2 "$(mkjson Bash 'git checkout main && git pull' "$A6FEATCO")"
check "(A6.6) checkout main && bare push refused"     "$NP" 2 "$(mkjson Bash 'git checkout main && git push' "$A6FEATCO")"
check "(A6.6) UNCHAINED merge on a feature branch"    "$H" 0 "$(mkjson Bash 'git merge feature/x' "$A6FEATCO")"
check "(A6.6) UNCHAINED bare push on a feature br."   "$NP" 0 "$(mkjson Bash 'git push' "$A6FEATCO")"
check "(A6.6) gated clause BEFORE the checkout is ok" "$H" 0 "$(mkjson Bash 'git merge feature/x ; git checkout main' "$A6FEATCO")"
check "(A6.6) push then checkout is ok"               "$NP" 0 "$(mkjson Bash 'git push origin feature/co ; git checkout main' "$A6FEATCO")"
check "(A6.6) checkout then merge --abort allowed"    "$H" 0 "$(mkjson Bash 'git checkout main && git merge --abort' "$A6FEATCO")"
check "(A6.6) checkout then pull --ff-only allowed"   "$H" 0 "$(mkjson Bash 'git checkout main && git pull --ff-only' "$A6FEATCO")"
check "(A6.6) checkout then NAMED push allowed"       "$NP" 0 "$(mkjson Bash 'git checkout main && git push origin feature/co' "$A6FEATCO")"
check "(A6.6) checkout feature/z && merge allowed"    "$H" 0 "$(mkjson Bash 'git checkout feature/z && git merge feature/y' "$A6FEATCO")"
check "(A6.6) checkout -b new && merge allowed"       "$H" 0 "$(mkjson Bash 'git checkout -b feature/new && git merge feature/y' "$A6FEATCO")"
check "(A6.6) checkout feature/z && push allowed"     "$NP" 0 "$(mkjson Bash 'git checkout feature/z && git push' "$A6FEATCO")"
check "(A6.6) checkout - is unresolvable, refused"    "$H" 2 "$(mkjson Bash 'git checkout - && git merge feature/y' "$A6FEATCO")"
check "(A6.6) checkout \$VAR is unresolvable"         "$H" 2 "$(mkjson Bash 'git checkout $BR && git merge feature/y' "$A6FEATCO")"
check "(A6.6) last checkout wins: back to a feature"  "$H" 0 "$(mkjson Bash 'git checkout main && git checkout feature/z && git merge feature/y' "$A6FEATCO")"
check "(A6.6) checkout -- file is not a branch move"  "$H" 0 "$(mkjson Bash 'git checkout -- seed.txt && git merge feature/x' "$A6FEATCO")"
check_msg "(A6.6) refusal names the branch change" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git checkout main && git merge feature/co' "$A6FEATCO")" "branch change:"
check_msg "(A6.6) refusal names the green-receipt risk" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git checkout main && git merge feature/co' "$A6FEATCO")" "green receipt"
# The two refusal reasons must READ differently: "moves onto a protected
# branch" is a finding, "target unresolvable" is a cannot-determine. Without
# this, the exit code is asserted and the message that explains it is not.
check_msg "(A6.6) unresolvable target reads as cannot-determine" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git checkout - && git merge feature/y' "$A6FEATCO")" "cannot determine which branch"

# ---------------------------------------------------------------------------
# v3.0.1 item 5 — the block message: diagnosis and fix, not argument.
#
# The LAST assertion is the load-bearing one. The positive condition ("what
# would make it allow") must be printed BEFORE the escape hatch, because
# whichever a consumer reads first is the one they use — and the safe pull form
# is named nowhere else a consumer can reach.
# ---------------------------------------------------------------------------
A6PULL=$(mkjson Bash 'git pull' "$A6CLONE")
check_msg "(A6.5) message names the branch" "$ROOT/$H" 2 "$A6PULL" "branch:"
check_msg "(A6.5) message names the protected set" "$ROOT/$H" 2 "$A6PULL" "protected set:"
check_msg "(A6.5) message quotes the matched segment" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git pull --rebase' "$A6CLONE")" "git pull --rebase"
check_msg "(A6.5) message shows the discriminator inputs" "$ROOT/$H" 2 "$A6PULL" "refspec/remote named:"
check_msg "(A6.5) message names the tracked upstream" "$ROOT/$H" 2 "$A6PULL" "origin/main"
check_msg "(A6.5) message names what it could NOT determine" "$ROOT/$H" 2 "$A6PULL" "before any fetch"
check_msg "(A6.5) message states the ALLOWED pull form" "$ROOT/$H" 2 "$A6PULL" "git pull --ff-only"
# v3.0.2: the merge block's ALLOWED line no longer offers a catch-up MERGE — it
# sends the reader to `git pull --ff-only`, which fetches before it merges. A
# message still naming the deleted exemption would send a blocked consumer to a
# command that is now refused.
check_msg "(A6.5) merge block states the ALLOWED merge form" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git merge feature/x' "$A6CLONE")" "use 'git pull --ff-only'"
A6MSG=$(printf '%s' "$A6PULL" | bash "$ROOT/$H" 2>&1 >/dev/null)
A6POS=$(printf '%s\n' "$A6MSG" | grep -n 'ALLOWED without a gate run' | head -1 | cut -d: -f1)
A6ESC=$(printf '%s\n' "$A6MSG" | grep -n 'git-guard-off' | head -1 | cut -d: -f1)
if [ -n "$A6POS" ] && [ -n "$A6ESC" ] && [ "$A6POS" -lt "$A6ESC" ]; then
  printf 'PASS  %-42s (line %s < %s)\n' "(A6.5) ALLOW precedes the escape hatch" "$A6POS" "$A6ESC"
  pass=$((pass + 1))
else
  printf 'FAIL  %-42s (pos=%s esc=%s)\n' "(A6.5) ALLOW precedes the escape hatch" "${A6POS:-none}" "${A6ESC:-none}"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# v3.0.1 item 4 — scripts/probe-a6.sh asserts its OWN preconditions.
#
# The probe reports on the gate of the repo it is standing in, so each fixture
# below gets a copy of hooks/. THE REFUSAL ARMS ARE THE POINT: three of the four
# vacuous states report every row ALLOWED and one reports every row BLOCKED,
# and the BLOCKED one is the dangerous direction — a probe expecting BLOCKED
# reads all-2 as the gate working perfectly.
#
# Each refusal must exit 9 (NEITHER hook verdict, so a wrapper testing -eq 0 or
# -eq 2 cannot read a refusal as an answer) and must NOT print the table. The
# absent-substring assertions are what make that second half a control: the
# table cannot be printed without its header, so the refusal path is checked
# for what it must NOT emit, not only for its exit code.
# ---------------------------------------------------------------------------
A6P="$ROOT/scripts/probe-a6.sh"
a6probe() { ( cd "$1" && bash "$A6P" 2>&1 ); }
a6probe_rc() { ( cd "$1" >/dev/null 2>&1 && bash "$A6P" >/dev/null 2>&1 ); }
a6expect_rc() { # <label> <dir> <want>
  a6probe_rc "$2"; a6rc=$?
  if [ "$a6rc" = "$3" ]; then
    printf 'PASS  %-42s (exit %s)\n' "$1" "$a6rc"; pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s, got %s)\n' "$1" "$3" "$a6rc"; fail=$((fail + 1))
  fi
}
a6expect_notable() { # <label> <dir> <substring the refusal must name>
  a6out=$(a6probe "$2")
  if printf '%s\n' "$a6out" | grep -qF "$3" &&
     ! printf '%s\n' "$a6out" | grep -qE 'EXPECTED|git merge --abort'; then
    printf 'PASS  %-42s (observed value, no table)\n' "$1"; pass=$((pass + 1))
  else
    printf 'FAIL  %-42s\n' "$1"; fail=$((fail + 1))
  fi
}

cp -r "$ROOT/hooks" "$A6CLONE/hooks"
a6expect_rc "(A6.4) probe runs on a protected branch" "$A6CLONE" 0
# VACUOUS-ALLOWED: not on a protected branch.
A6PFEAT=$(a6clone a6probefeat)
cp -r "$ROOT/hooks" "$A6PFEAT/hooks"
git -C "$A6PFEAT" checkout -q -b feature/probe >/dev/null 2>&1
a6expect_rc "(A6.4) probe refuses off a protected branch" "$A6PFEAT" 9
a6expect_notable "(A6.4) that refusal names the branch, no table" "$A6PFEAT" "branch=feature/probe"
# VACUOUS-BLOCKED, the one that hides in the block direction: no lib, so the
# gate fails closed on every row.
A6PNOLIB=$(a6clone a6probenolib)
mkdir -p "$A6PNOLIB/hooks"
cp "$ROOT/hooks/gate-before-merge.sh" "$A6PNOLIB/hooks/"
a6expect_rc "(A6.4) probe refuses with the lib absent" "$A6PNOLIB" 9
a6expect_notable "(A6.4) that refusal says BLOCK vacuously" "$A6PNOLIB" "BLOCK vacuously"
# VACUOUS-ALLOWED, not in the specified list: with no **Gate** command the hook
# exits 0 before any A6 decision, so every row would be ALLOWED for a reason
# that is not the gate's logic.
A6PNOGATE=$(a6clone a6probenogate)
cp -r "$ROOT/hooks" "$A6PNOGATE/hooks"
rm -f "$A6PNOGATE/PROJECT_CONTEXT.md"
a6expect_rc "(A6.4) probe refuses with no Gate configured" "$A6PNOGATE" 9
a6expect_notable "(A6.4) that refusal names the missing field" "$A6PNOGATE" "no '**Gate**:' line"
# The probe runs `set -u` and SOURCES the libs, which the hooks themselves never
# do under -u. If any lib path touched an unset variable, bash would abort with
# exit 1 — the code this script assigns to "table printed, a row differed", so a
# crash and a real mismatch would be indistinguishable, which is the confusion
# the 9 exists to prevent. A placeholder protected set is the reachable path
# that reaches json_warn_once, and it runs BEFORE precondition 4.
A6PWARN=$(a6clone a6probewarn)
cp -r "$ROOT/hooks" "$A6PWARN/hooks"
printf '# ctx\n\n- **Gate**: `true`\n- **Protected branches**: {{DEFAULT_BRANCH}}\n' > "$A6PWARN/PROJECT_CONTEXT.md"
a6expect_rc "(A6.4) probe survives the lib's WARN path" "$A6PWARN" 0

# ---------------------------------------------------------------------------
# v2.4.0 (A6, consumer report): a PRETTY-PRINTED artifact is valid JSON and a
# consumer's own gate may well emit it — replacing run-gate.sh wholesale is a
# supported configuration, the contract being the **Gate** field plus the
# artifact FORMAT. The reader used to be hardcoded to `"sha":"` and returned
# EMPTY, blocking every merge with `artifact sha: none` on a green gate.
#
# BOTH KEYS, BOTH SPELLINGS, and the sha arm is the one that catches a widened
# grep paired with an unwidened sed: that combination yields a value with a
# LEADING SPACE, which matches nothing and still reports "stale".
# ---------------------------------------------------------------------------
PRETTYGATE=$(mkrepo gateprettyartifact feature/pretty)
printf '# ctx\n\n- **Gate**: `true`\n' > "$PRETTYGATE/PROJECT_CONTEXT.md"
PRETTYSHA=$(git -C "$PRETTYGATE" rev-parse HEAD)
PRETTYTREE=$(git -C "$PRETTYGATE" rev-parse 'HEAD^{tree}')
mkdir -p "$PRETTYGATE/.gate"
printf '{\n  "sha": "%s",\n  "tree": "%s",\n  "branch": "feature/pretty",\n  "status": "pass"\n}\n' \
  "$PRETTYSHA" "$PRETTYTREE" > "$PRETTYGATE/.gate/last-pass.json"
check "(A6) pretty-printed artifact is accepted (sha key)" \
  "$H" 0 "$(mkjson Bash 'gh pr merge 3 --squash' "$PRETTYGATE")"
# tree-only arm: no sha key at all, spaced spelling — must still match by tree.
printf '{\n  "tree": "%s",\n  "sha": "%s",\n  "status": "pass"\n}\n' \
  "$PRETTYTREE" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" \
  > "$PRETTYGATE/.gate/last-pass.json"
check "(A6) pretty-printed artifact is accepted (tree key)" \
  "$H" 0 "$(mkjson Bash 'gh pr merge 3 --squash' "$PRETTYGATE")"
# Negative arm: a spaced spelling carrying values that match NEITHER key must
# still block — the widening must not have turned into "accept anything".
printf '{\n  "sha": "%s",\n  "tree": "%s"\n}\n' \
  "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "cafebabecafebabecafebabecafebabecafebabe" \
  > "$PRETTYGATE/.gate/last-pass.json"
check "(A6) pretty-printed but genuinely stale still blocks" \
  "$H" 2 "$(mkjson Bash 'gh pr merge 3 --squash' "$PRETTYGATE")"

# ===========================================================================
# v2.1.3 fix round 1 (Critical 2 / penumbra #2c): a real end-to-end chain --
# pre-commit-test.sh runs run-gate.sh against the INDEX, the real `git commit`
# follows, and gate-before-merge.sh must accept the resulting artifact via its
# tree match even though the artifact's sha is the PARENT commit's.
# ===========================================================================
echo
echo "=== R3 chain: commit-time run-gate.sh satisfies merge-time gate ==="
# v2.4.0 (A6): these three chain fixtures used to sit on `main`. They model a
# developer agent gating in its worktree and then merging, which is a FEATURE
# branch flow — and it has to be, because A6 now refuses a merge initiated from
# a protected branch before the artifact is read. On `main` they would all
# report 2 for the topology reason and stop testing the artifact chain they
# exist to test. Moving them to a feature branch restores what they measure.
CHAINREPO=$(mkrepo gatechain feature/chain)
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
CHAINADD=$(mkrepo gatechainadd feature/chainadd)
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
PARTADD=$(mkrepo gatepartialadd feature/partadd)
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
# v2.4.0 (A6, second half): THE CHECKOUT CAN MOVE UNDER A RUNNING GATE.
# Observed live during v2.3.0's release — a second gate run was still going
# when the checkout moved from detached c43f51f to `main`, finished green, and
# wrote a sha captured before the move. It described no single state.
#
# The **Gate** command here moves HEAD itself, which is the only way to make
# the race deterministic. Guard: HEAD is re-read after the gate command and
# compared to the sha captured at the start; a move means no artifact.
# CONTROL, BOTH ARMS: (a) a moving checkout writes NO artifact and exits
# nonzero; (b) the identical repo with a non-moving gate command writes one.
# Delete the HEAD_SHA_AFTER block in run-gate.sh and arm (a) flips to a green
# run with an artifact — the exact false receipt.
# ===========================================================================
echo
echo "=== A6: the checkout moving under a running gate ==="
MOVEREPO=$(mkrepo gatemovinghead feature/moving)
printf '# ctx\n\n- **Gate**: `true`\n' > "$MOVEREPO/PROJECT_CONTEXT.md"
git -C "$MOVEREPO" add -A >/dev/null 2>&1
git -C "$MOVEREPO" commit -q -m "gate cfg" >/dev/null 2>&1
echo second > "$MOVEREPO/second.txt"
git -C "$MOVEREPO" add -A >/dev/null 2>&1
git -C "$MOVEREPO" commit -q -m "second commit" >/dev/null 2>&1
# (b) the stable arm first, so a failure in (a) cannot be blamed on the setup.
( cd "$MOVEREPO" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>&1 )
expect "(A6) stable checkout: gate exits 0" "0" "$?"
expect "(A6) stable checkout: artifact written" "1" \
  "$([ -f "$MOVEREPO/.gate/last-pass.json" ] && echo 1 || echo 0)"
# (a) now a gate command that moves HEAD out from under itself.
printf '# ctx\n\n- **Gate**: `git checkout -q --detach HEAD~1`\n' > "$MOVEREPO/PROJECT_CONTEXT.md"
moveerr=$(mktemp)
( cd "$MOVEREPO" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$moveerr" )
expect "(A6) moving checkout: gate exits nonzero" "1" "$?"
expect "(A6) moving checkout: NO artifact is left behind" "0" \
  "$([ -f "$MOVEREPO/.gate/last-pass.json" ] && echo 1 || echo 0)"
expect "(A6) moving checkout: the reason is named" "1" \
  "$(grep -cF 'the checkout moved while the gate was running' "$moveerr")"

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
expect "(R5) recursion guard: exit 78 (terminal)"  "78" "$?"
expect "(R5) recursion guard: message" "1" \
  "$(grep -cF 'BLOCKED: **Gate** must not invoke run-gate.sh itself' "$recurseerr")"
# v2.2.5: the guard's accurate diagnosis used to be buried under generic
# "re-run it" advice from both outer layers. The specific remedy is now the LAST
# line the guard prints, and it names the field to edit.
expect "(R5) recursion guard: remedy is the last line" "1" \
  "$(tail -1 "$recurseerr" | grep -cF "Edit '**Gate**:' in PROJECT_CONTEXT.md")"

# --- R5b: terminal vs retryable must be distinguishable by the CALLER --------
# Both arms, because a one-armed fixture cannot catch a suppression that fires
# on everything. Arm 1: a terminal gate (rc=78) suppresses the retry advice and
# still BLOCKS. Arm 2: an ordinary red gate still prints it.
echo
echo "=== R5b: terminal (78) vs retryable gate failure ==="

# Arm 1 -- the real self-reference chain, driven end to end: **Gate** invokes
# run-gate.sh, so the OUTER run-gate.sh runs the INNER one, which exits 78.
termrepo=$(mkrepo gateterminal main)
printf '# ctx\n\n- **Gate**: `bash %s/hooks/run-gate.sh`\n' "$ROOT" > "$termrepo/PROJECT_CONTEXT.md"
termerr="$TMPROOT/terminal.err"
( cd "$termrepo" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$termerr" )
expect "(R5b) terminal gate: run-gate.sh propagates 78" "78" "$?"
expect "(R5b) terminal gate: NO generic re-run advice" "0" \
  "$(grep -c 'Fix the failures and re-run' "$termerr")"
expect "(R5b) terminal gate: remedy still last" "1" \
  "$(tail -1 "$termerr" | grep -cF "Edit '**Gate**:' in PROJECT_CONTEXT.md")"

# Arm 1b -- pre-commit-test.sh over the same repo: it must still BLOCK, with
# exit 2 and never 78 (the PreToolUse contract with the harness is 0/2, so the
# terminal code is consumed here, not propagated), and it must not tell the user
# to re-run the thing that cannot succeed.
check_nomsg "(R5b) terminal: no retry advice" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$termrepo")" "re-run it and fix the failures"
check_msg "(R5b) terminal: names configuration" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$termrepo")" "cannot succeed as configured"
check_msg "(R5b) terminal: remedy reaches the user" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$termrepo")" "Edit '**Gate**:' in PROJECT_CONTEXT.md"

# Arm 2 -- an ORDINARY red gate must be unaffected: rc=1 from run-gate.sh, the
# retry advice present, and pre-commit-test.sh's retry advice present too.
redrepo=$(mkrepo gatered main)
printf '# ctx\n\n- **Gate**: `false`\n' > "$redrepo/PROJECT_CONTEXT.md"
rederr="$TMPROOT/red.err"
( cd "$redrepo" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$rederr" )
expect "(R5b) ordinary red gate: run-gate.sh exits 1" "1" "$?"
expect "(R5b) ordinary red gate: retry advice PRESENT" "1" \
  "$(grep -c 'Fix the failures and re-run' "$rederr")"
check_msg "(R5b) red: retry advice PRESENT" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$redrepo")" "re-run it and fix the failures"

# --- R5c: THE CLAMP CONTROL (v2.2.5 round 3) --------------------------------
# 78 is EX_CONFIG and real programs emit it, so an arbitrary consumer gate
# command CAN exit 78 for its own reasons. It must be clamped to an ordinary
# red gate, or a plain test failure inherits the terminal remedy "edit your
# **Gate** value" -- INVERTED advice, worse than the generic retry line.
#
# This is the CONTROL for the clamp in run-gate.sh, and it is honest by
# construction: delete the clamp and the 78 propagates, the terminal branch
# fires, "Fix the failures and re-run" disappears and both assertions below flip.
# Its opposite arm is R5b arm 1 (a NESTED run-gate.sh leaves the provenance
# marker and its 78 must survive) -- the pair is what distinguishes a working
# clamp from one that swallows every 78, which is the failure mode that would
# silently undo item K.
#
# The Gate command must NOT mention run-gate.sh: the whole point is a gate that
# exits 78 for an UNRELATED reason.
clamprepo=$(mkrepo gateclamp main)
printf 'exit 78\n' > "$clamprepo/exits78.sh"
printf '# ctx\n\n- **Gate**: `bash exits78.sh`\n' > "$clamprepo/PROJECT_CONTEXT.md"
clamperr="$TMPROOT/clamp.err"
( cd "$clamprepo" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$clamperr" )
expect "(R5c) unrelated gate rc=78 is CLAMPED to 1" "1" "$?"
expect "(R5c) clamped gate: retry advice PRESENT (not the terminal text)" "1" \
  "$(grep -c 'Fix the failures and re-run' "$clamperr")"
check_msg "(R5c) clamped: pre-commit prints retry advice" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$clamprepo")" "re-run it and fix the failures"
check_nomsg "(R5c) clamped: NOT reported as a configuration failure" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$clamprepo")" "cannot succeed as configured"

# --- R5d: the SECOND terminal guard (v2.2.5 round 3) ------------------------
# "not inside a git repository" is terminal by the same definition -- re-running
# from the same cwd cannot make that directory a repository -- and it exited 1
# until this release, so pre-commit-test appended "re-run it and fix the
# failures". That is item K's circular advice in a guard that already existed.
# The paired opposite arm is R5b arm 2: an ordinary red gate still exits 1.
# NOTE the guard's sibling `cd "$REPO_TOP" || exit 1` deliberately stays 1 --
# a cd failing on a path git just resolved is a transient environment fault.
nonrepo="$TMPROOT/not-a-repo"
mkdir -p "$nonrepo"
nonrepoerr="$TMPROOT/nonrepo.err"
( cd "$nonrepo" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$nonrepoerr" )
expect "(R5d) not a git repository: exit 78 (terminal, was 1)" "78" "$?"
expect "(R5d) not a git repository: remedy names the fix" "1" \
  "$(tail -1 "$nonrepoerr" | grep -c 'from inside the checkout')"

# --- R5e: THE MARKER NESTS THROUGH A WRAPPER (v2.2.5 round 4) ---------------
# R5b arm 1 is single-level: **Gate** invokes run-gate.sh directly. A marker
# written to a SELF-CREATED temp dir would pass that test and fail here, because
# only the value INHERITED from the outer run points at the file the outer tests.
# Correct by construction today, unproven by execution until this arm — and this
# is the arm that catches a future refactor moving the marker's creation above
# the recursion guard.
wraprepo=$(mkrepo gatewrapper main)
printf '#!/usr/bin/env bash\nexec bash "%s/hooks/run-gate.sh"\n' "$ROOT" > "$wraprepo/wrapper.sh"
printf '# ctx\n\n- **Gate**: `bash wrapper.sh`\n' > "$wraprepo/PROJECT_CONTEXT.md"
wraperr="$TMPROOT/wrapper.err"
( cd "$wraprepo" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$wraperr" )
expect "(R5e) wrapper-nested terminal: 78 survives the clamp" "78" "$?"
expect "(R5e) wrapper-nested: NO generic re-run advice" "0" \
  "$(grep -c 'Fix the failures and re-run' "$wraperr")"
expect "(R5e) wrapper-nested: remedy still last" "1" \
  "$(tail -1 "$wraperr" | grep -cF "Edit '**Gate**:' in PROJECT_CONTEXT.md")"

# --- R5h: THE PUBLIC TERMINAL CONTRACT FOR **Gate** COMMANDS (v2.3.0) --------
# R5b/R5e prove the marker works when run-gate.sh writes it to itself. This
# proves the CONSUMER-FACING half documented in docs/verification.md: a chained
# preflight (`**Gate**: bash preflight.sh && <real gate>`) that hits a terminal
# condition prints its remedy, touches $RUN_GATE_TERMINAL, and exits 78 -- and
# the clamp lets that 78 through instead of collapsing it to 1.
#
# BOTH ARMS, and the difference between them is ONE LINE of the preflight, so
# neither can pass for the other's reason. Arm 1 is the contract; arm 2 is the
# clamp still doing its job for a gate that exits 78 without claiming
# provenance. The delete-the-guard control for arm 1 is removing
# `[ ! -f "$RUN_GATE_TERMINAL" ]` from the clamp (arm 2 flips); for arm 2 it is
# deleting the clamp `if` entirely (arm 2 flips, arm 1 does not).
#
# This is what makes RUN_GATE_TERMINAL a PUBLIC name: 21c-2f in
# verify-template-consistency.sh pins its export ABOVE the gate invocation,
# because a reorder would break consumers silently and green.
echo
echo "=== R5h: consumer **Gate** terminal contract (RUN_GATE_TERMINAL) ==="

# Arm 1 -- preflight signals terminal: remedy on stderr, marker touched, 78.
pfrepo=$(mkrepo gatepreflight main)
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "GATE ERROR: node_modules is absent" >&2\n'
  printf 'echo "run: npm ci" >&2\n'
  printf '[ -n "${RUN_GATE_TERMINAL:-}" ] && : > "$RUN_GATE_TERMINAL"\n'
  printf 'exit 78\n'
} > "$pfrepo/preflight.sh"
printf '# ctx\n\n- **Gate**: `bash preflight.sh && true`\n' > "$pfrepo/PROJECT_CONTEXT.md"
pferr="$TMPROOT/preflight.err"
( cd "$pfrepo" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$pferr" )
expect "(R5h) preflight touched marker: 78 survives the clamp" "78" "$?"
expect "(R5h) preflight terminal: NO generic re-run advice" "0" \
  "$(grep -c 'Fix the failures and re-run' "$pferr")"
expect "(R5h) preflight terminal: consumer remedy is LAST" "1" \
  "$(tail -1 "$pferr" | grep -c '^run: npm ci$')"

# Arm 2 -- byte-for-byte the same script MINUS the touch: no provenance claimed,
# so the 78 is a child's number and must clamp to an ordinary red gate.
nopfrepo=$(mkrepo gatepreflight_nomarker main)
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "GATE ERROR: node_modules is absent" >&2\n'
  printf 'echo "run: npm ci" >&2\n'
  printf 'exit 78\n'
} > "$nopfrepo/preflight.sh"
printf '# ctx\n\n- **Gate**: `bash preflight.sh && true`\n' > "$nopfrepo/PROJECT_CONTEXT.md"
nopferr="$TMPROOT/preflight-nomarker.err"
( cd "$nopfrepo" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>"$nopferr" )
expect "(R5h) no marker: 78 is CLAMPED to 1" "1" "$?"
expect "(R5h) no marker: retry advice PRESENT" "1" \
  "$(grep -c 'Fix the failures and re-run' "$nopferr")"

# Arm 3 -- THE MARKER IS ABSENT WHEN THE GATE COMMAND STARTS, and the variable
# names a real path. `rm -f "$RUN_GATE_TERMINAL"` is as load-bearing as the
# export and was covered by nothing: a marker SURVIVING into the gate makes
# EVERY 78 pass the clamp, which is a fail-open on the clamp itself -- the thing
# deciding whether a consumer's remedy survives at all. Harmless today only
# because TMPD is a fresh `mktemp -d` per run; a reused or fixed TMPD is all it
# would take.
#
# RUNTIME, not a static assertion beside 21c-2f, and the reason is the opposite
# of 21c-2f's: "exported before the gate runs" IS an ordering, so a line-number
# comparison is the property. "The file does not exist when the gate starts" is
# a STATE. A grep for `rm -f` between the two lines would be a proxy for it --
# it cannot see a TMPD that stopped being fresh. The gate command below observes
# the state directly, from exactly where a consumer preflight stands.
mkabsrepo=$(mkrepo gatemarkerabsent main)
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [ -z "${RUN_GATE_TERMINAL:-}" ]; then echo VAR_UNSET > state.txt; exit 1; fi\n'
  printf 'if [ -f "$RUN_GATE_TERMINAL" ]; then echo MARKER_PRESENT > state.txt; exit 1; fi\n'
  printf 'echo VAR_SET_MARKER_ABSENT > state.txt\n'
} > "$mkabsrepo/checkmarker.sh"
printf '# ctx\n\n- **Gate**: `bash checkmarker.sh`\n' > "$mkabsrepo/PROJECT_CONTEXT.md"
( cd "$mkabsrepo" && bash "$ROOT/hooks/run-gate.sh" >/dev/null 2>&1 )
expect "(R5h) gate starts with the marker ABSENT" "0" "$?"
expect "(R5h) ...and \$RUN_GATE_TERMINAL names a path" "VAR_SET_MARKER_ABSENT" \
  "$(tr -d '\r\n' < "$mkabsrepo/state.txt" 2>/dev/null)"

# --- R5f: the OTHER TWO 78-bearing paths into pre-commit-test.sh -------------
# (v2.2.5 round 4.) R5c covers one of three. Both arms below reach the same
# `eval "$TEST_CMD"` boundary, where nothing decided the number for us — so both
# must produce the RETRYABLE message, and neither the terminal one.
#
# CONTROL FOR THE CLAMP AT THAT BOUNDARY, honest by construction: delete the
# clamp and 78 reaches the terminal arm, "re-run it and fix the failures"
# disappears and every assertion in this block flips.

# Arm 1 -- a **Test** value that exits 78. **Test** always wins, so this never
# touches run-gate.sh at all.
t78repo=$(mkrepo test78 main)
printf 'exit 78\n' > "$t78repo/exits78.sh"
printf '# ctx\n\n- **Test**: `bash exits78.sh`\n' > "$t78repo/PROJECT_CONTEXT.md"
check_msg "(R5f) **Test** rc=78: retry advice PRESENT" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$t78repo")" "re-run it and fix the failures"
check_nomsg "(R5f) **Test** rc=78: NOT a configuration failure" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$t78repo")" "cannot succeed as configured"

# Arm 2 -- **Gate** present but run-gate.sh ABSENT beside the hook, so the hook
# eval's the Gate value itself. Identical gate command, identical exit code, and
# before round 4 it got the OPPOSITE remediation from arm 1 of R5c purely
# because of where the hook happened to be installed.
g78hooks="$TMPROOT/hooks-no-rungate"
mkdir -p "$g78hooks/lib"
cp "$ROOT/hooks/pre-commit-test.sh" "$g78hooks/"
cp "$ROOT/hooks/lib/git-cmd.sh" "$ROOT/hooks/lib/json.sh" "$g78hooks/lib/"
g78repo=$(mkrepo gate78norungate main)
printf 'exit 78\n' > "$g78repo/exits78.sh"
printf '# ctx\n\n- **Gate**: `bash exits78.sh`\n' > "$g78repo/PROJECT_CONTEXT.md"
check_msg "(R5f) Gate eval'd, no run-gate.sh, rc=78: WARN names the fallback" "$g78hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$g78repo")" "run-gate.sh not found next to this hook"
check_msg "(R5f) Gate eval'd, no run-gate.sh, rc=78: retry advice PRESENT" "$g78hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$g78repo")" "re-run it and fix the failures"
check_nomsg "(R5f) Gate eval'd, no run-gate.sh, rc=78: NOT a configuration failure" "$g78hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$g78repo")" "cannot succeed as configured"

# --- R5g: THE EVAL BOUNDARY RUNS CONSUMER TEXT IN THE HOOK'S OWN SHELL --------
# (v2.2.5 round 5, independent QA at 9baa446. Pre-existing since v2.1.x.)
#
# THIS BLOCK EXISTS BECAUSE A SOURCE CENSUS CANNOT REACH THIS CLASS. Census
# 21c-2f in verify-template-consistency.sh asserts "no `exit 1` in a registered
# hook" by grepping the hook's SOURCE. It was green here — and the hook exited 1
# anyway, because the `exit 1` arrived as CONFIG DATA through `**Test**` and was
# eval'd. "pre-commit-test.sh never exits anything but 0 or 2" was true of the
# text and false of the process. The question that finds this class: what would
# have to be true for this census to be green while the property is broken?
#
# Bare `eval "$TEST_CMD"` runs in the CURRENT shell, so a value reaching `exit`
# or `exec` at top level terminated the hook and skipped the if/else. Measured
# before the fix / after:
#
#   **Test**: exit 1                  rc 1  -> 2, BLOCKED lines 0 -> 1
#   **Test**: exec bash -c "exit 1"   rc 1  -> 2, BLOCKED lines 0 -> 1
#   **Test**: exec bash -c "exit 78"  rc 78 -> 2, BLOCKED lines 0 -> 1
#   **Gate**: exec bash -c "exit 1"   rc 1  -> 2, BLOCKED lines 0 -> 1
#     (round 6; run-gate.sh absent beside the hook, so :175 assigns the Gate
#      value into $TEST_CMD and it reaches the SAME eval — see the block below)
#
# Every pre-fix row is warn-and-ALLOW: the commit proceeded UNGATED and SILENTLY.
# CONTROL: drop the `( )` around the eval in hooks/pre-commit-test.sh and 9 of
# the 10 assertions below flip (measured 2026-08-31); the tenth is the passing-
# command control at the end, which correctly holds either way, so the block is
# not one that fires on everything.
#
# `exec` is this codebase's own idiom — the R5e wrapper above uses it.
#
# NOT `$H`: it is positional state and by this point in the file it names
# hooks/gate-before-merge.sh, which exits 0 on a commit payload — every arm
# below would have passed vacuously. Spell the hook out, as R5f does.
r5g_probe() { # <label> <index> <Test value> ; asserts exit 2 + a BLOCKED line
  d=$(mkrepo "evalesc$2" main)
  printf '# ctx\n\n- **Test**: %s\n' "$3" > "$d/PROJECT_CONTEXT.md"
  check "(R5g) $1: still exit 2 (was warn-and-ALLOW)" hooks/pre-commit-test.sh 2 \
    "$(mkjson Bash 'git commit -m x' "$d")"
  check_msg "(R5g) $1: BLOCKED line present" "$ROOT/hooks/pre-commit-test.sh" 2 \
    "$(mkjson Bash 'git commit -m x' "$d")" "re-run it and fix the failures"
}
r5g_probe "bare exit"      1 'exit 1'
r5g_probe "exec + exit 1"  2 'exec bash -c "exit 1"'
r5g_probe "exec + exit 78" 3 'exec bash -c "exit 78"'

# THERE IS ONE `eval` BUT TWO CONFIG KEYS REACH IT (v2.2.5 round 6, consumer-
# reported). The three arms above drive `**Test**`. But pre-commit-test.sh:175,
# on the mirror-fallback path (`run-gate.sh not found next to this hook`),
# assigns the **GATE** value into $TEST_CMD and falls through to that same single
# eval. So the fail-open is reachable through **Test** AND through **Gate**, and
# the second is not a variant — it is the identical statement with a different
# value source. Driving only **Test** would be a correct behavioural test of one
# of the two ways in, which is this finding's own shape one level up.
#
# THE GATE PATH IS THE LESS VISIBLE OF THE TWO, and that is why it gets its own
# arm rather than a comment. It prints `WARN: ... evaluating the Gate command
# directly instead` BY DESIGN — so a fail-open here arrives wearing a warning
# that looks like the known degradation. A consumer who sees that line has been
# told to expect a LESSER path, not a BYPASSED one, and has no way to tell from
# the transcript which of the two they got.
#
# Shape copied from R5f arm 2, for its non-vacuity properties: both libs are
# copied in (a missing lib fails the hook closed at exit 2 and the arm would
# pass for the wrong reason), and the WARN string is asserted so that "the
# fallback path was actually taken" is proved rather than assumed.
r5ghooks="$TMPROOT/hooks-no-rungate-exec"
mkdir -p "$r5ghooks/lib"
cp "$ROOT/hooks/pre-commit-test.sh" "$r5ghooks/"
cp "$ROOT/hooks/lib/git-cmd.sh" "$ROOT/hooks/lib/json.sh" "$r5ghooks/lib/"
r5grepo=$(mkrepo evalescgate main)
printf '# ctx\n\n- **Gate**: exec bash -c "exit 1"\n' > "$r5grepo/PROJECT_CONTEXT.md"
check_msg "(R5g) Gate exec, no run-gate.sh: the mirror-fallback path was taken" "$r5ghooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$r5grepo")" "run-gate.sh not found next to this hook"
check_msg "(R5g) Gate exec, no run-gate.sh: still exit 2 + BLOCKED (was warn-and-ALLOW)" "$r5ghooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$r5grepo")" "re-run it and fix the failures"

# Round 4's clamp reasoning must survive the subshell: a child's 78 still has no
# provenance, so it takes the RETRYABLE message, never the terminal framing.
# (R5f arm 1 asserts the same for a non-exec child; this is the exec path.)
r5gx=$(mkrepo evalesc78frame main)
printf '# ctx\n\n- **Test**: exec bash -c "exit 78"\n' > "$r5gx/PROJECT_CONTEXT.md"
check_nomsg "(R5g) exec rc=78: NOT a configuration failure" "$ROOT/hooks/pre-commit-test.sh" 2 \
  "$(mkjson Bash 'git commit -m x' "$r5gx")" "cannot succeed as configured"

# Two-sided: a passing consumer command must still pass, or "exit 2 everywhere"
# would satisfy every assertion above.
r5ggreen=$(mkrepo evalescgreen main)
printf '# ctx\n\n- **Test**: `true`\n' > "$r5ggreen/PROJECT_CONTEXT.md"
check "(R5g) control: a passing Test still exits 0" hooks/pre-commit-test.sh 0 \
  "$(mkjson Bash 'git commit -m x' "$r5ggreen")"

# NOTE on the `cd "$REPO_PATH" || exit 2` sites (v2.2.5 round 4): they are NOT
# driven by a fixture here, and deliberately so. Reaching either one with a
# failing cd requires the directory to disappear BETWEEN the PROJECT_CONTEXT.md
# grep and the cd — a genuine race, and any fixture claiming to reproduce it
# would in fact be testing a mutated copy of the hook. The property that the
# code cannot exit 1 there is asserted structurally instead, as a census in
# scripts/verify-template-consistency.sh (search: warn-and-allow).

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

# --- THE HARNESS'S REAL PAYLOAD SHAPE (v3.0.0) ------------------------------
#
# ⚠ EVERY FIXTURE ABOVE USES `mkspawn`, WHICH BUILDS A **FLAT** PAYLOAD, AND THE
# HARNESS DOES NOT SEND THAT SHAPE. It nests under `tool_input`, exactly as
# `mkjson`/`mkread` already do for every other hook. Until v3.0.0 the hook read
# `$.subagent_type` at the top level, so against a real spawn `SUBAGENT_TYPE`
# was always empty, every spawn fell to the `*)` default arm, and THE HOOK
# EXITED 0 ON EVERY SPAWN EVER MADE — confirmed on the real harness by spawning
# a bound `architect` with no skills block and watching it launch.
#
# The fixtures above all passed throughout, because they exercised a shape
# nothing sends. THIS is the control that would have caught it, and it is why
# the block matters more than the fix: a fixture that agrees with the code about
# an input the world never produces is a fixture that cannot fail.
#
# `mkspawn` is deliberately LEFT flat rather than converted, so both shapes stay
# covered — the live Agent payload cannot be observed from inside the suite, and
# a hook that reads only one shape is how this defect happened in the first
# place.
#
# ⚠ THE NEGATIVE ARM IS THE ONE THAT MATTERS, AND THE `WITH block` ROWS PROVE
# ALMOST NOTHING ON THEIR OWN — they passed throughout the entire period the
# hook was inert. On a disciplined repo every spawn carries the block, so the
# hook's only observable behaviour is SILENCE, and silence is also exactly what
# a dead guard produces. Pass and absence are indistinguishable from where a
# compliant consumer stands. That is the vacuous-fixture shape scaled up to an
# entire enforcement layer, and it is why the four `without skills block` rows
# below are the assertion and the rest is corroboration.
mkspawn_nested() { # <subagent_type> <prompt> -- the shape the harness sends
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"%s","prompt":"%s"},"cwd":"%s"}\n' \
    "$(jesc "$1")" "$(jesc "$2")" "$(jesc "$ROOT")"
}

check "NESTED: coder without skills block"      "$H" 2 "$(mkspawn_nested coder 'Do the thing.')"
check "NESTED: architect without skills block"  "$H" 2 "$(mkspawn_nested architect 'Do the thing.')"
check "NESTED: tester without skills block"     "$H" 2 "$(mkspawn_nested tester 'Do the thing.')"
check "NESTED: rust-coder without skills block" "$H" 2 "$(mkspawn_nested rust-coder 'Do the thing.')"
check "NESTED: coder WITH skills block"         "$H" 0 "$(mkspawn_nested coder "$WITHBLOCK")"
check "NESTED: architect WITH skills block"     "$H" 0 "$(mkspawn_nested architect "$WITHBLOCK")"
check "NESTED: code-reviewer is unbound"        "$H" 0 "$(mkspawn_nested code-reviewer 'Do the thing.')"
check "NESTED: unknown type passes"             "$H" 0 "$(mkspawn_nested game-tester 'Do the thing.')"

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
# `seq` is NOT a shell builtin and is not in the stub PATH list below; a host
# without it produced `seq: command not found` here and unexplained downstream
# failures. A while-loop has no such dependency.
nlines() { # <file> <count>
  : > "$1"; i=1
  while [ "$i" -le "$2" ]; do echo "line $i" >> "$1"; i=$((i + 1)); done
}
SMALL="$TMPROOT/small.txt";     nlines "$SMALL" 20
HUNDRED="$TMPROOT/hundred.txt"; nlines "$HUNDRED" 100
BIG="$TMPROOT/big.txt";         nlines "$BIG" 600
HUGE="$TMPROOT/huge.txt";       nlines "$HUGE" 900
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
# v3.0.1: and it does not inflate errors= either. The budget block used to be
# counted as an error one line BEFORE the budget/blocks split, so a ceiling
# tripping as designed was indistinguishable from a real failure in the headline.
expect "budget block does not inflate errors=" 1 \
  "$(grep -c 'errors=1' "$BULEDGER" 2>/dev/null)"

# --- 8a3. v3.0.1: THE LEDGER IS THE RECORD, THE BRIEF IS THE VIEW.
# A budget-only spawn STILL gets a ledger row — suppressing it would make an
# agent's rows disappear from retro.md, and disappearing rows read as "clean",
# not as "changed" (a silent negative). The filtering happens in retro-brief.sh.
#
# Two-sided IN ONE RUN, deliberately: retro-brief is fail-open, so an awk syntax
# error empties its output entirely and a lone "budget-only agent is absent"
# assertion would pass on that. The real-failure agent must be PRESENT in the
# same output for the absence to mean anything.
BOHOME="$TMPROOT/retrohome-budgetonly"
mkdir -p "$BOHOME"
{
  trow_ok "PreToolUse:Bash hook error: [bash 'hooks/agent-budget-warn.sh']: BUDGET: this spawn has made 120 tool calls (median is 15; 120 is the first ceiling)."
  trow_ok "PreToolUse:Bash hook error: [bash 'hooks/agent-budget-warn.sh']: BUDGET: this spawn has made 240 tool calls (median is 15; 120 is the first ceiling)."
} > "$TMPROOT/agent-budgetonly.jsonl"
mkstop "$PROJCWD" coder agent-bo77 "$TMPROOT/agent-budgetonly.jsonl" \
  | HOME="$BOHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
BOLEDGER="$BOHOME/.claude/projects/G--git-retroproj/memory/retro.md"
expect "budget-only spawn STILL writes a ledger row" 1 \
  "$(grep -c 'agent-bo77' "$BOLEDGER" 2>/dev/null)"
expect "budget-only row is budget=2 | errors=0" 1 \
  "$(grep -c 'budget=2 | errors=0' "$BOLEDGER" 2>/dev/null)"
mkstop "$PROJCWD" tester agent-real77 "$TMPROOT/agent-block.jsonl" \
  | HOME="$BOHOME" bash "$ROOT/hooks/retro-ledger.sh" >/dev/null 2>&1
mkstart "$PROJCWD" | HOME="$BOHOME" bash "$ROOT/hooks/retro-brief.sh" > "$TMPROOT/bo.out" 2>/dev/null
expect "brief over a filtered ledger exits 0" 0 $?
expect "brief HIDES the budget-only agent" 0 "$(grep -c 'agent-bo77' "$TMPROOT/bo.out")"
expect "brief SHOWS the real-failure agent" 1 "$(grep -c 'agent-real77' "$TMPROOT/bo.out")"

# --- 8a3b. v3.0.1: dead=[...] is surfaced ON ITS OWN MERITS and is NEVER
# filtered out. A grant gap is not a failure — the agent completes and silently
# delivers something weaker — and a measured row `dead=[Bash,Edit] | budget=0 |
# errors=2` is the one that produced two real defect reports. A filter keyed on
# errors= or budget= alone would have dropped precisely that row.
DEADHOME="$TMPROOT/retrohome-deadonly"
DEADDIR="$DEADHOME/.claude/projects/G--git-retroproj/memory"
mkdir -p "$DEADDIR"
printf '%s\n' '2026-09-02 10:00 | coder | agent-dead77 | dead=[Bash,Edit] | blocks=[] | budget=4 | errors=0' \
  > "$DEADDIR/retro.md"
mkstart "$PROJCWD" | HOME="$DEADHOME" bash "$ROOT/hooks/retro-brief.sh" > "$TMPROOT/dead.out" 2>/dev/null
expect "a dead= row survives the brief filter even with budget>0, errors=0" 1 \
  "$(grep -c 'agent-dead77' "$TMPROOT/dead.out")"

# --- 8a3c. v3.0.1: the brief DEDUPES by agent id (last row wins) BEFORE tailing.
# Measured: one long-running agent occupied 11 of 30 cumulative rows and hid
# three of the four agents behind `tail -n 10`, under a heading promising the
# last 10 SUBAGENT entries.
DDHOME="$TMPROOT/retrohome-dedupe"
DDDIR="$DDHOME/.claude/projects/G--git-retroproj/memory"
mkdir -p "$DDDIR"
printf '%s\n' '2026-09-02 09:00 | tester | agent-quiet77 | dead=[] | blocks=[y.sh] | budget=0 | errors=1' \
  > "$DDDIR/retro.md"
dd_i=1
while [ "$dd_i" -le 11 ]; do
  printf '2026-09-02 10:00 | coder | agent-loud77 | dead=[] | blocks=[x.sh] | budget=0 | errors=%s\n' \
    "$dd_i" >> "$DDDIR/retro.md"
  dd_i=$((dd_i + 1))
done
mkstart "$PROJCWD" | HOME="$DDHOME" bash "$ROOT/hooks/retro-brief.sh" > "$TMPROOT/dd.out" 2>/dev/null
expect "brief keeps exactly one row per agent id" 1 "$(grep -c 'agent-loud77' "$TMPROOT/dd.out")"
expect "brief keeps that agent's LAST row" 1 "$(grep -c 'errors=11' "$TMPROOT/dd.out")"
expect "dedupe stops one agent hiding another" 1 "$(grep -c 'agent-quiet77' "$TMPROOT/dd.out")"

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
# hooks/agent-budget-warn.sh — SendMessage is EXEMPT (v3.0.0, item B3)
#
# Until v3.0.0 this hook had NO behavioural fixture at all: the only assertion
# naming it was a retro-ledger transcript row that merely quoted its message.
# The defect that lived in that gap was measured in the field — the budget block
# stopped FIVE agent reports, i.e. it stopped agents FILING THEIR WORK, which is
# the precise failure the liveness effort exists to prevent. The block message
# tells the agent to "report your partial result plus the blocker", and the tool
# that does that is the one it was blocking: a guard denying its own remedy.
#
# THE CEILING IS UNCHANGED — spawns hit 417, 420 and 480 calls, so the escalating
# block is doing real work. What changed is WHICH calls it applies to.
#
# ⚠ THE EXEMPTION MUST NOT COUNT, NOT MERELY NOT BLOCK, and case 4 is the arm
# that tells those apart. `-eq` fires once per exact value, so a SendMessage that
# consumed call 120 would SILENTLY SKIP the ceiling and defer the next block to
# 180. An exemption implemented as "block unless SendMessage" passes cases 1-3
# and fails case 4 — which is the only reason case 4 exists.
#
# The counter file is seeded directly rather than driven 119 times. That is
# white-box coupling to a path this hook's own header documents, accepted so the
# suite does not pay 240 process spawns for one property.
# ===========================================================================
echo
echo "=== hooks/agent-budget-warn.sh (SendMessage exemption) ==="

BUDCWD="$TMPROOT/budgetcwd"
mkdir -p "$BUDCWD"

mkbudget() { # <tool_name> <agent_id> <session_id>
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"echo hi"},"cwd":"%s","agent_id":"%s"}\n' \
    "$(jesc "$3")" "$(jesc "$1")" "$(jesc "$BUDCWD")" "$(jesc "$2")"
}

# <label> <tmpdir> <tool_name> <agent_id> <session> <want_exit> [needle]
bud() {
  bud_label="$1"; bud_tmp="$2"; bud_tool="$3"; bud_id="$4"
  bud_sess="$5"; bud_want="$6"; bud_needle="${7:-}"
  bud_err="$TMPROOT/budget.err"
  mkdir -p "$bud_tmp"
  printf '%s' "$(mkbudget "$bud_tool" "$bud_id" "$bud_sess")" \
    | TMPDIR="$bud_tmp" bash "$ROOT/hooks/agent-budget-warn.sh" \
      >/dev/null 2>"$bud_err"
  bud_got=$?
  if [ "$bud_got" = "$bud_want" ] &&
     { [ -z "$bud_needle" ] || grep -qF "$bud_needle" "$bud_err"; }; then
    printf 'PASS  %-42s (exit %s)\n' "$bud_label" "$bud_got"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-42s (want %s%s, got %s: %s)\n' "$bud_label" "$bud_want" \
      "${bud_needle:+ + \"$bud_needle\"}" "$bud_got" "$(head -1 "$bud_err")"
    fail=$((fail + 1))
  fi
}

bud_seed() { # <tmpdir> <session> <agent_id> <n>
  mkdir -p "$1/claude-agent-budget/$2"
  printf '%s' "$4" > "$1/claude-agent-budget/$2/$3"
}
bud_count() { # <tmpdir> <session> <agent_id>
  cat "$1/claude-agent-budget/$2/$3" 2>/dev/null || echo MISSING
}

# --- 1. the main thread carries no agent_id and is never this hook's business
bud "main thread (no agent_id) passes" "$TMPROOT/bud1" Bash "" mainsess 0

# --- 2. the ceiling still blocks. If this ever goes green-by-passing, the
# exemption has been widened into a disabling.
bud_seed "$TMPROOT/bud2" budsess a-ceil 119
bud "call 120 (Bash) still blocks" "$TMPROOT/bud2" Bash a-ceil budsess 2 \
  "BUDGET: this spawn has made 120 tool calls"

# --- 3. THE FIX: the same call number, as a SendMessage, is not blocked.
bud_seed "$TMPROOT/bud3" budsess a-send 119
bud "SendMessage at the ceiling passes" "$TMPROOT/bud3" SendMessage a-send budsess 0

# --- 4. ...and it did not CONSUME the threshold: the counter is untouched, so
# the next working call still lands on 120 and still blocks. This is the arm
# that distinguishes "exempt from counting" from "exempt from blocking".
if [ "$(bud_count "$TMPROOT/bud3" budsess a-send)" = "119" ]; then
  printf 'PASS  %-42s (counter 119)\n' "SendMessage does not spend budget"
  pass=$((pass + 1))
else
  printf 'FAIL  %-42s (counter %s, want 119)\n' "SendMessage does not spend budget" \
    "$(bud_count "$TMPROOT/bud3" budsess a-send)"
  fail=$((fail + 1))
fi
bud "next Bash call still hits the ceiling" "$TMPROOT/bud3" Bash a-send budsess 2 \
  "BUDGET: this spawn has made 120 tool calls"

# --- 5. a NON-threshold SendMessage is equally uncounted, so a long reporting
# burst cannot inflate an agent past its ceiling without doing any work.
bud_seed "$TMPROOT/bud5" budsess a-many 10
bud "SendMessage below the ceiling passes" "$TMPROOT/bud5" SendMessage a-many budsess 0
bud "SendMessage below the ceiling, again" "$TMPROOT/bud5" SendMessage a-many budsess 0
if [ "$(bud_count "$TMPROOT/bud5" budsess a-many)" = "10" ]; then
  printf 'PASS  %-42s (counter 10)\n' "repeated SendMessage leaves count at 10"
  pass=$((pass + 1))
else
  printf 'FAIL  %-42s (counter %s, want 10)\n' "repeated SendMessage leaves count at 10" \
    "$(bud_count "$TMPROOT/bud5" budsess a-many)"
  fail=$((fail + 1))
fi

# --- 6. NEGATIVE CONTROL: a tool whose name merely CONTAINS the exempt name is
# not exempt. Without this, an exemption written as a substring match would pass
# every case above while quietly exempting anything.
bud_seed "$TMPROOT/bud6" budsess a-near 119
bud "SendMessageToTeam is NOT exempt" "$TMPROOT/bud6" SendMessageToTeam a-near budsess 2 \
  "BUDGET: this spawn has made 120 tool calls"

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
# v2.3.0: HEREDOC BODIES ARE DATA. Authoring a plan/doc that CONTAINS a runner
# line is the whole of this hook's measured false-deny traffic, and a heredoc is
# the one quoting form with an explicit terminator, so its body can be removed
# without guessing. Arm 2 is the control that keeps the strip narrow: the
# terminator ends it, and a real runner AFTER it is still the PO running a test.
# Arm 3 is the accepted, deliberate NON-fix: quoted literals stay judged as
# written, because separating `bash -c "npm test"` from `echo "npm test"` needs
# a wrapper allowlist whose every gap is an evasion channel.
check_delegation "heredoc body naming a runner"   pass 'cat > plan.md <<EOF
pytest -q
npm test
EOF'
check_delegation "runner AFTER the terminator"    deny 'cat > plan.md <<EOF
npm test
EOF
pytest -q'
check_delegation "quoted-literal runner unchanged" pass 'echo "npm test"'
# quoted and tab-suppressed heredoc openers are the same construct
check_delegation "quoted heredoc delimiter"       pass 'cat > plan.md <<"EOF"
dotnet build
EOF'
# `<<-` with an UNINDENTED terminator: legal, and it keeps the payload free of a
# literal TAB. A raw tab inside a JSON string is an invalid control character,
# so a tab-indented terminator would make the payload unparseable and this
# fail-OPEN hook would pass it for the wrong reason — a vacuously green arm.
# (Measured while writing this fixture, not reasoned about.)
check_delegation "<<- opener is a heredoc too"    pass 'cat > plan.md <<-END
mvn verify
END'
# an UNTERMINATED heredoc has no end to trust: nothing is stripped, judged as before
check_delegation "unterminated heredoc unchanged" deny 'cat > plan.md <<EOF
pytest -q'
# `<<<` is a here-STRING, not a heredoc: it has no body and no terminator, so
# mistaking it for an opener would swallow the REAL commands that follow. The
# arm is shaped so that mistake shows up as a wrongly-allowed runner, not as a
# cosmetic difference -- `echo hi <<<EOF` would have passed either way.
check_delegation "here-string is not an opener"   deny 'cat f.md <<<EOF
pytest -q
EOF'
# subagent calls always pass, exemption or not
subout=$(printf '{"session_id":"t","agent_id":"a1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"pytest"},"cwd":"%s"}' "$(jesc "$DELEGREPO")" \
  | bash "$ROOT/hooks/enforce-delegation.sh" 2>/dev/null)
expect "subagent pytest still passes" "0" \
  "$(printf '%s' "$subout" | grep -c '"deny"')"
else
skip "enforce-delegation git/gh exemption cases" "no node on this host" 27
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

# The MINIMUM tool set a stub PATH must carry. It was under-specified in the
# silent direction: a tool `command -v` could not find was skipped, the stub was
# built anyway, and every case running under it failed for a reason nothing
# printed. A missing `stat` alone flips two warn-once fixtures from 1 WARN to 2
# -- json_warn_once's no-session branch reads the marker's mtime, and with no
# `stat` the mtime reads 0, so an unexpired marker looks expired and the hook
# warns twice. Diagnosed by removing exactly one tool at a time. A harness that
# builds an incomplete environment and reports the result as a test failure is
# the same "fails by reporting something other than the failure" shape this
# release exists to stop, so the gap is now LOUD.
PATHDIR_TOOLS="sh bash git grep sed tr head tail cut cat wc stat date mktemp
dirname basename sort uniq mkdir rm ls awk env find touch cp expr"
mkpathdir() { # <name> [extra-tool ...] -> prints dir
  pd="$TMPROOT/path-$1"; shift
  mkdir -p "$pd"
  mpd_missing=""
  for t in $PATHDIR_TOOLS "$@"; do
    r=$(command -v "$t" 2>/dev/null) || r=""
    if [ -z "$r" ]; then mpd_missing="$mpd_missing $t"; continue; fi
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$r" > "$pd/$t"
    chmod +x "$pd/$t"
  done
  # mkpathdir runs inside `$(...)`, so a counter bumped here dies with the
  # subshell. The marker is read back in the main shell below.
  [ -n "$mpd_missing" ] && printf '%s\n' "$mpd_missing" >> "$TMPROOT/pathdir-missing"
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
# BUILD THE OPTIONAL-PARSER STUB DIRS ONLY WHERE THAT PARSER EXISTS (v2.2.5
# round 3). mkpathdir's missing-tool report is a LOUD guard, and correctly so —
# for CORE tools, whose absence silently corrupts every case run under the stub.
# `python3` and `jq` are not core: they are the thing being VARIED, and their
# absence is already handled by the HAVE_* skips below. Building a stub dir for
# an absent optional parser reported `FAIL stub PATH minimum tool set (missing:
# python3)` and turned the whole suite RED in a configuration that was skipping
# correctly — the harness failing for a harness reason and reporting it as a
# hook result. Measured under the jq configuration of
# scripts/test-hooks-parser-matrix.sh, where python3 is genuinely off PATH.
# The variables stay defined-but-empty; every case using them is inside a
# HAVE_PY / HAVE_JQ block.
PYONLY=""
if [ -n "$HAVE_PY" ]; then PYONLY=$(mkpathdir pyonly python3); fi
JQONLY=""
if [ -n "$HAVE_JQ" ]; then JQONLY=$(mkpathdir jqonly jq); fi

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
# Same rule as PYONLY/JQONLY above: these two carry a REAL optional parser as
# the working backend behind the broken stub, so they are built only where that
# parser exists. Their cases are already inside HAVE_JQ / HAVE_PY blocks.
STUB_JQ=""
if [ -n "$HAVE_JQ" ]; then STUB_JQ=$(mkstubpath stub-jq python3 'exit 3' jq); fi
# A broken NODE is the case json_require_node exists for -- the six node-program
# hooks never call json_parser, so the probe has to run on that path too.
STUB_NODE=$(mkstubpath stub-node node 'exit 3')
STUB_NODE_PY=""
if [ -n "$HAVE_PY" ]; then STUB_NODE_PY=$(mkstubpath stub-node-py node 'exit 3' python3); fi

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
# v2.2.3: the exposure v2.2.1 LEFT. Its fallback is `main master`, which does not
# contain `develop` -- so a develop-trunk repo carrying the placeholder was
# warned at and its trunk was still pushable. Warning is not protecting, and the
# warn is one stderr line per session. The resolver now reads the remote's own
# default branch and adds it to the fallback. `refs/remotes/origin/HEAD` is set
# here WITHOUT a real remote on purpose: symbolic-ref just writes the ref, which
# is all the resolver reads -- a local read that cannot hang in a hook.
PB_PLACE_DEV=$(pbrepo pb-placeholder-dev develop '- **Protected branches**: {{DEFAULT_BRANCH}}')
git -C "$PB_PLACE_DEV" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop >/dev/null 2>&1
# The resolved trunk is added to `main master`, never substituted for it: a repo
# with both must not LOSE main's protection to a fix for develop's. And when the
# resolved trunk is main, the set must not grow a duplicate.
PB_PLACE_MAIN=$(pbrepo pb-placeholder-main main '- **Protected branches**: {{DEFAULT_BRANCH}}')
git -C "$PB_PLACE_MAIN" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main >/dev/null 2>&1
# v2.2.3 round 2: the ABSENT line is the same hole and the LARGER population --
# it predates v2.2.0 (it is the original `main|master` hardcode's own blind
# spot), it affects every repo that never configured the field rather than only
# those that took the v2.2.0 template, and unlike the placeholder it was SILENT.
# The full {absent, placeholder} x {main trunk, develop trunk} matrix, so a
# future edit to one arm cannot quietly diverge from the other.
PB_ABS_MAIN=$(pbrepo pb-absent-main main -)
git -C "$PB_ABS_MAIN" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main >/dev/null 2>&1
PB_ABS_DEV=$(pbrepo pb-absent-dev develop -)
git -C "$PB_ABS_DEV" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop >/dev/null 2>&1
# The empty arm folds in on the same helper: it warns about the typo AND
# protects the trunk while it does so.
PB_EMPTY_DEV=$(pbrepo pb-empty-dev develop '- **Protected branches**:')
git -C "$PB_EMPTY_DEV" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop >/dev/null 2>&1
# `origin/HEAD` is unset on any clone that never ran `git remote set-head`, and
# then the trunk is UNKNOWABLE. We fail OPEN there -- an unknown is not a
# violation, and blocking pushes over a missing local ref would be a worse bug
# than the one being fixed. But a repo with no local main AND no local master
# provably has nothing in the fallback set, so that one case is said out loud.
PB_NOHEAD_DEV=$(pbrepo pb-nohead-dev develop -)
git -C "$PB_NOHEAD_DEV" branch -D main >/dev/null 2>&1

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
# v2.2.3: the row that was exit=0 before this release.
check "placeholder on a develop trunk: develop blocked" "$H" 2 \
  "$(mkjson Bash 'git push' "$PB_PLACE_DEV")"
check "placeholder on a develop trunk: refspec blocked" "$H" 2 \
  "$(mkjson Bash 'git push origin develop' "$PB_PLACE_DEV")"
check_msg "resolved trunk JOINS the default, it does not replace it" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push origin main' "$PB_PLACE_DEV")" "protected branch (main master develop)"
check_msg "a resolved trunk of main does not duplicate" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push origin main' "$PB_PLACE_MAIN")" "protected branch (main master)"
# no origin remote at all -> the resolver returns nothing and the historical
# default stands. Never empty, never the literal.
check_msg "unresolvable trunk keeps the historical default" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push origin main' "$PB_PLACE")" "protected branch (main master)"
# the four-way matrix: {absent, placeholder} x {main trunk, develop trunk}
check "absent + main trunk: main blocked"      "$H" 2 "$(mkjson Bash 'git push' "$PB_ABS_MAIN")"
check "absent + develop trunk: develop blocked" "$H" 2 "$(mkjson Bash 'git push' "$PB_ABS_DEV")"
check_msg "absent + develop trunk names the union" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push origin develop' "$PB_ABS_DEV")" "protected branch (main master develop)"
# (the absent arm deliberately does NOT warn — nothing there is misconfigured,
# the repo simply never said. The union message above is what the arm is
# contracted to produce; v2.2.4 added check_nomsg for the BOM arms, so a direct
# negative assertion here is now possible but has not been retrofitted.)
check "empty + develop trunk: develop blocked" "$H" 2 "$(mkjson Bash 'git push' "$PB_EMPTY_DEV")"
# fail OPEN on an unknowable trunk, and say so
check "unknowable trunk: push is NOT blocked"  "$H" 0 "$(mkjson Bash 'git push' "$PB_NOHEAD_DEV")"
check_msg "unknowable trunk warns and names the remedy" "$ROOT/$H" 0 \
  "$(mkjson Bash 'git push' "$PB_NOHEAD_DEV")" "git remote set-head origin -a"
check "empty value: main still blocked"    "$H" 2 "$(mkjson Bash 'git push' "$PB_EMPTY")"
check_msg "empty value warns about the typo" "$ROOT/$H" 2 \
  "$(mkjson Bash 'git push' "$PB_EMPTY")" "**Protected branches**: is empty"
# v2.2.4: the BOM pair for THIS extractor. Hiding the field fails safe for
# `none` (the fallback protects more), so the arm that matters is a field
# naming a NON-default trunk: unread, `develop` falls back to `main master`
# and the develop trunk is pushable -- exit 0 before the fix.
PB_BOM_L1=$(mkrepo pb-bom-l1 develop)
PB_BOM_L2=$(mkrepo pb-bom-l2 develop)
printf '%s- **Protected branches**: develop\n' "$BOM" > "$PB_BOM_L1/PROJECT_CONTEXT.md"
printf '%s# ctx\n- **Protected branches**: develop\n' "$BOM" > "$PB_BOM_L2/PROJECT_CONTEXT.md"
check "BOM + Protected branches line 1"    "$H" 2 "$(mkjson Bash 'git push' "$PB_BOM_L1")"
check "BOM + Protected branches line 2"    "$H" 2 "$(mkjson Bash 'git push' "$PB_BOM_L2")"
# `none` is untouched by the two arms above: it remains the explicit opt-out.
check "none is still an opt-out"           "$H" 0 "$(mkjson Bash 'git push origin main' "$PB_NONE")"

# the merge gate reads the same field
GB=hooks/gate-before-merge.sh
check "merge on develop is gated"          "$GB" 2 "$(mkjson Bash 'git merge feature/x' "$PB_DEV")"
check "merge on unprotected main is not"   "$GB" 0 "$(mkjson Bash 'git merge feature/x' "$PB_DEVMAIN")"
# `none` unprotects the BRANCH rules only: a PR merge is a merge on any branch.
check "none: gh pr merge still gated"      "$GB" 2 "$(mkjson Bash 'gh pr merge 1 --squash' "$PB_NONE")"
check "placeholder develop trunk: merge gated" "$GB" 2 \
  "$(mkjson Bash 'git merge feature/x' "$PB_PLACE_DEV")"

# ===========================================================================
# --- v3.0.3 Task 4: pre-commit-test terminal contract ---
#
# Three concerns in one block, from queue items 4/5/6 and finding 59:
#   (1) the three Test rows (exit 0 / 1 / 78) panoscribe measured, each with
#       the fixture's OWN exit asserted first — finding 59's consumer produced
#       a probe that could not fail by mis-quoting exactly this script;
#   (2) the `.gate/last-precommit.json` DIAGNOSTIC (Task 3½): a PreToolUse hook
#       completes before the tool runs and the harness drops non-blocking hook
#       stderr, so this file is the only side effect that outlives the hook and
#       can place it relative to the command it gates;
#   (3) the "Could not determine" blind-spot paragraph in both gates, and the
#       property that nothing the HOOK writes lands after the tail header —
#       what run-gate.sh:258's deliberate silence actually guarantees.
#
# NOT HERE, and why: the TERMINAL WORDING rows for the exit-78 case. The Test
# path's eval boundary is forbidden a terminal arm by three shipped guards —
# verify-template-consistency.sh census 21c-2h, and R5f/R5g above, which assert
# the retryable wording on exactly this rc. Adding the wording rows would put
# this block in direct contradiction with them. See the v3.0.3 report: the
# prerequisite those guards name (a provenance channel at the eval boundary) is
# unbuilt, so the 78 row below asserts today's contract, not finding 59's.
PCTREPO=$(mkrepo pct-terminal main)
PCT=hooks/pre-commit-test.sh
for rc in 0 1 78; do
  printf '#!/usr/bin/env bash\necho "GATE ERROR: pytest-cov missing" >&2\necho "run: uv sync --extra dev" >&2\nexit %s\n' "$rc" > "$PCTREPO/tc$rc.sh"
done
# The fixture must be shown to carry the property BEFORE it is measured with.
for rc in 0 1 78; do
  bash "$PCTREPO/tc$rc.sh" >/dev/null 2>&1
  expect "(PCT) tc$rc.sh exits $rc" "$rc" "$?"
done
pct_ctx() { # <test-script> -- Gate declared too, so no want-0 row is vacuous
  printf '# ctx\n\n- **Test**: `bash %s`\n- **Gate**: `bash %s`\n' "$1" "$1" > "$PCTREPO/PROJECT_CONTEXT.md"
}
PCTART="$PCTREPO/.gate/last-precommit.json"
pct_field() { # <file> <key> -> value (string or number), no jq dependency
  sed -n 's/.*"'"$2"'":"\([^"]*\)".*/\1/p;s/.*"'"$2"'":\(-\{0,1\}[0-9]\{1,\}\).*/\1/p' "$1" 2>/dev/null | head -1
}
for rc in 0 1 78; do
  want=2; [ "$rc" -eq 0 ] && want=0
  pct_ctx "tc$rc.sh"
  rm -f "$PCTART"
  check "(PCT) Test exit $rc -> hook exit $want" "$PCT" "$want" "$(mkjson Bash 'git commit -m x' "$PCTREPO")"
  # (2) the artifact outlives the hook, on the path it actually took
  if [ -f "$PCTART" ]; then
    expect "(PCT) artifact path=test for tc$rc" "test" "$(pct_field "$PCTART" path)"
    expect "(PCT) artifact rc=$rc for tc$rc"    "$rc"   "$(pct_field "$PCTART" rc)"
  else
    printf 'FAIL  %-42s (no %s)\n' "(PCT) artifact written for tc$rc" ".gate/last-precommit.json"
    fail=$((fail + 2))
  fi
done
# A payload with no commit segment still leaves the artifact — that is the read
# that answers "did this hook run at all", which stderr cannot.
rm -f "$PCTART"
check "(PCT) non-commit payload allowed" "$PCT" 0 "$(mkjson Bash 'ls -la' "$PCTREPO")"
expect "(PCT) artifact path=no-commit-segment" "no-commit-segment" "$(pct_field "$PCTART" path)"
# (1) the ordinary-failure path keeps its advice and its escape hatch
pct_ctx tc1.sh
check_msg "(PCT) ordinary failure keeps the re-run advice" "$ROOT/$PCT" 2 \
  "$(mkjson Bash 'git commit -m x' "$PCTREPO")" "re-run it and fix"
# (3) the blind-spot paragraph, on the BLOCKED path
check_msg "(PCT) BLOCKED names what it could not determine" "$ROOT/$PCT" 2 \
  "$(mkjson Bash 'git commit -m x' "$PCTREPO")" "Could not determine"
# (3) property (b), as the guarantee actually is: nothing the HOOK wrote appears
# after the tail header. Assert it structurally — every line after the header is
# a line of the command's OWN output — rather than by pinning the last line,
# which would pass for a hook that printed its own trailer above the remedy.
pctErr="$TMPROOT/pct-tail.err"
pcttmp="$TMPROOT/pct-tail.tmp"; rm -rf "$pcttmp"; mkdir -p "$pcttmp"
printf '%s' "$(mkjson Bash 'git commit -m x' "$PCTREPO")" | TMPDIR="$pcttmp" bash "$ROOT/$PCT" >/dev/null 2>"$pctErr"
pctAfter=$(sed -n '/--- last 20 lines ---/,$p' "$pctErr" | tail -n +2)
pctStray=$(printf '%s\n' "$pctAfter" | grep -v '^GATE ERROR: pytest-cov missing$' | grep -v '^run: uv sync --extra dev$' | grep -v '^$' || true)
if [ -z "$pctStray" ] && [ -n "$pctAfter" ]; then
  printf 'PASS  %-42s (%s)\n' "(PCT) nothing hook-written after the tail" "remedy is last"
  pass=$((pass + 1))
else
  printf 'FAIL  %-42s (stray: %s)\n' "(PCT) nothing hook-written after the tail" \
    "$(printf '%s' "$pctStray" | head -1)"
  fail=$((fail + 1))
fi
# (3) the same paragraph in no-push-main.sh, on its no-refspec path
PCTPUSH=$(mkrepo pct-push main)
check_msg "(PCT) no-push-main names what it could not determine" "$ROOT/hooks/no-push-main.sh" 2 \
  "$(mkjson Bash 'git push' "$PCTPUSH")" "Could not determine"

# ===========================================================================
# Read back the stub-PATH completeness marker (see mkpathdir): a stub built
# without its minimum tool set makes every case running under it meaningless,
# and it used to do that in silence.
echo
if [ -f "$TMPROOT/pathdir-missing" ]; then
  printf 'FAIL  %-42s (missing:%s)\n' "stub PATH minimum tool set" \
    "$(tr '\n' ' ' < "$TMPROOT/pathdir-missing" | tr -s ' ')"
  fail=$((fail + 1))
else
  printf 'PASS  %-42s (%s)\n' "stub PATH minimum tool set" "all present"
  pass=$((pass + 1))
fi

echo "----------------------------------------------------------------"
# The total is printed so a wrong `skip <n>` count is visible immediately: it
# is host-INDEPENDENT, while the three tallies are not.
echo "test-hooks.sh: $pass passed, $fail failed, $skipped skipped ($((pass + fail + skipped)) assertions)"
[ "$fail" -eq 0 ] || exit 1
echo "ALL HOOK FIXTURES PASSED"
exit 0
