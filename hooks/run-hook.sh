#!/usr/bin/env bash
# cct plugin hook wrapper (v5.0 spec §3.1, §3.2, §3.5). hooks/hooks.json registers every
# toolkit hook as:  bash "${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.sh" <name>
# Order: class + polarity -> toolkit-project signal (project-only hooks) -> step-aside -> exec.
# The hook is exec'd (not sourced), so its $0 and "$(dirname "$0")/lib" resolve exactly as before.
# stdin is never read here; the hook receives the payload untouched.
name="${1:-}"
here="$(cd "$(dirname "$0")" && pwd)" || exit 2
# class: machine = acts in every project (spec §3.1); project = only in a toolkit project.
# polarity on a missing script, copied from the v4.6.1 template wrappers: closed=exit 2, warn=stderr+0, open=0.
case "$name" in
  no-push-main|deny-secret-reads)                              cls=machine; pol=closed ;;
  deny-hang-shapes|model-floor|bash-output-guard|verify-hooks) cls=machine; pol=open ;;
  pre-commit-test|gate-before-merge|deny-claude-md-writes)     cls=project; pol=closed ;;
  read-size-gate|enforce-delegation|agent-budget-warn)         cls=project; pol=warn ;;
  post-edit-build|enforce-agent-contract|retro-ledger|retro-brief|now-brief) cls=project; pol=open ;;
  *) echo "HOOK BLOCKED: run-hook.sh: unknown hook name '$name' -- the plugin's hooks.json and run-hook.sh disagree" >&2; exit 2 ;;
esac
proj="${CLAUDE_PROJECT_DIR:-.}"
if [ "$cls" = project ] && [ ! -f "$proj/.claude/template-manifest.json" ]; then exit 0; fi
# step-aside (spec §3.2): the same literal substring tests as v4's user-level registrations.
s=""; [ -r "$proj/.claude/settings.json" ] && IFS= read -r -d '' s < "$proj/.claude/settings.json"
case $s in *'}/hooks/'"$name"'.sh\"'*) exit 0 ;; esac
u=""; [ -r "$HOME/.claude/settings.json" ] && IFS= read -r -d '' u < "$HOME/.claude/settings.json"
case $u in *'/hooks/'"$name"'.sh"'*) exit 0 ;; esac
f="$here/$name.sh"
if [ ! -r "$f" ]; then
  case $pol in
    closed) echo "HOOK SCRIPT MISSING: $f -- enforcement offline. Reinstall the cct plugin (/plugin install cct@dagonet)." >&2; exit 2 ;;
    warn)   echo "WARN: $f missing -- $name offline. Reinstall the cct plugin." >&2; exit 0 ;;
    *)      exit 0 ;;
  esac
fi
exec bash "$f"
