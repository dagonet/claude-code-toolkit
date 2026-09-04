#!/usr/bin/env bash
# PreToolUse hook: refuse to read a secret-bearing .env file.
#
# Matcher: Read|Bash
#
# WHY A HOOK AND NOT A DENY RULE (v3.0.3, queue item 28, measured from a
# consumer screenshot 2026-09-04). Six `Read(.env…)` entries used to sit in
# `permissions.deny` of every template `.claude/settings.json`. Claude Code
# evaluates deny rules BEFORE the auto-mode classifier, and a read-only command
# whose path is RELATIVE after a `cd` cannot be statically proven not to be a
# denied path — so the harness prompts ("a Read() deny rule is configured; only
# you can approve running it anyway") and auto mode cannot approve it. Subagents
# working in worktrees run `cd <worktree> && grep …` on nearly every read, so
# every "auto mode is prompting" report this cycle traced back to those six
# lines. A HOOK deny does not trigger the static path check: the hook sees the
# resolved call and answers per call. The protection is kept; the prompt is not.
#
# DECISION RULE
#   Read  : tool_input.file_path matches the secret shape          -> exit 2
#   Bash  : the command contains a READER VERB *and* a token that
#           matches the secret shape                               -> exit 2
#   anything else                                                  -> exit 0
#
# Secret shape: `(^|/)\.env(\.<suffix>)?$`, except a basename of exactly
# `.env.example` — that file is the documented placeholder list most repos
# track, and denying it was v2.2.0's BUG 6 (check 22b in
# verify-template-consistency.sh has guarded it ever since).
#
# WHY THE BASH ARM NEEDS A READER VERB, stated because the two obvious rules
# disagree: "any argv token that looks like a .env path" makes `echo .env` a
# denial, and `echo .env` is not a read — it is a literal, and the plan's own
# fixture list wants it allowed. Keying on the verb resolves that in the
# direction the fixtures state, and it keeps `git show HEAD:.env` out of this
# hook's jurisdiction for the right reason rather than by accident of the
# regex.
#
# THE VERB LIST IS AN ALLOWLIST AND IS THEREFORE KNOWN-INCOMPLETE — SAID HERE
# rather than discovered later, the same way v3.0.2's clause blocklist declared
# its own incompleteness. A reader that is not in the list below passes: today
# that is anything from `perl -ne`, `busybox cat` under another name, or a
# consumer's own script. Adding verbs is cheap and safe; the inverse rule ("deny
# any matching token unless the verb is provably inert") was considered and
# REJECTED, because it denies `cp .env.example .env`, `git add .env` and
# `rm .env`, none of which are reads. A missed read is a gap; a denied write is
# a guard people switch off.
#
# STATED BLIND SPOT. This hook sees a command's ARGUMENTS, not what an
# interpreter opens. `python -c "open('.env')"`, `node -e "fs.readFileSync…"`
# and `git show HEAD:.env` are NOT denied here — they are judged by the
# auto-mode classifier's own credential rules. Two fixtures assert exactly that
# (want 0) so the boundary is a decision on the record, not an oversight.
#
# FAILS CLOSED on an unparseable payload or with no JSON parser on PATH, the
# same posture as the three git gates that already share this matcher: a hook
# that cannot see the call cannot clear it.

lib="$(dirname "$0")/lib/json.sh"
[ -f "$lib" ] || { echo "BLOCKED: $lib missing — run /sync-template step 6b (hooks/lib/json.sh)" >&2; exit 2; }
# shellcheck source=lib/json.sh
. "$lib"

DSR_JSON=$(cat)

json_have || {
  echo "BLOCKED: deny-secret-reads: no JSON parser (node, python3 or jq) on PATH — this hook cannot inspect the call, and a call it cannot inspect is not one it can clear. Install one of the three." >&2
  exit 2
}
json_valid "$DSR_JSON" || {
  echo "BLOCKED: deny-secret-reads: hook payload did not parse — this hook cannot inspect the call. Report the payload; do not work around it." >&2
  exit 2
}

DSR_TOOL=$(json_get "$DSR_JSON" tool_name)

# The secret shape, as one place. Anchored at a path separator or the start, so
# `.environment` and `HEAD:.env` do not match, and `./.env` and `/x/.env.staging`
# do.
DSR_SECRET_RE='(^|/)\.env(\.[A-Za-z0-9_-][A-Za-z0-9_.-]*)?$'

dsr_is_secret() { # <path> -> 0 when it is a secret-bearing .env name
  case "${1##*/}" in
    .env.example) return 1 ;;
  esac
  printf '%s' "$1" | grep -qE "$DSR_SECRET_RE"
}

dsr_deny() { # <path>
  {
    echo "BLOCKED: reading '$1' — secrets files are not read by agents."
    echo "  Could not determine: this hook sees the command's arguments, not what an interpreter opens; 'python -c open(...)' and 'git show HEAD:.env' are judged by the auto-mode classifier, not here."
    echo "  If you need a variable's NAME, read '.env.example' — it is allowed on purpose."
  } >&2
  exit 2
}

case "$DSR_TOOL" in
  Read)
    DSR_PATH=$(json_get "$DSR_JSON" tool_input.file_path)
    [ -n "$DSR_PATH" ] || exit 0
    dsr_is_secret "$DSR_PATH" && dsr_deny "$DSR_PATH"
    ;;
  Bash|PowerShell)
    DSR_CMD=$(json_get "$DSR_JSON" tool_input.command)
    [ -n "$DSR_CMD" ] || exit 0
    # Split on whitespace and on the shell operators that begin a new command,
    # then judge tokens. Quotes are stripped so `grep KEY "$PWD/.env.local"`
    # presents the same token shape as the unquoted form.
    DSR_TOKENS=$(printf '%s' "$DSR_CMD" | tr '|;&()<>' '\n' | tr -s '[:space:]' '\n' | tr -d '"'"'")
    DSR_READER=0
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      case "${tok##*/}" in
        cat|bat|head|tail|less|more|nl|od|xxd|hexdump|strings|sed|awk|gawk|grep|egrep|fgrep|rg|ag|cut|tr|sort|uniq|wc|tee|dd|base64|jq|yq|diff|cmp|envsubst|readarray|mapfile|source|.)
          DSR_READER=1 ;;
      esac
    done <<DSR_TOK
$DSR_TOKENS
DSR_TOK
    [ "$DSR_READER" -eq 1 ] || exit 0
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      if dsr_is_secret "$tok"; then dsr_deny "$tok"; fi
    done <<DSR_TOK2
$DSR_TOKENS
DSR_TOK2
    ;;
esac

exit 0
