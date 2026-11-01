#!/usr/bin/env bash
# cct plugin hook wrapper (v5.0 spec §3.1, §3.2, §3.5). hooks/hooks.json registers every
# toolkit hook as:  bash "${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.sh" <name>
# Order: class + polarity -> toolkit-project signal (project-only hooks) -> step-aside -> exec.
# The hook is exec'd (not sourced), so its $0 and "$(dirname "$0")/lib" resolve exactly as before.
# stdin is never read here; the hook receives the payload untouched.
name="${1:-}"
here="$(cd "$(dirname "$0")" && pwd)" || exit 2
# The class/polarity table and the step-aside decision live in lib/hook-class.sh (shared with the v6 dispatcher).
lib="$here/lib/hook-class.sh"
[ -r "$lib" ] || { echo "HOOK BLOCKED: run-hook.sh: hooks/lib/hook-class.sh missing -- reinstall the cct plugin" >&2; exit 2; }
. "$lib"
hc_class "$name" || { echo "HOOK BLOCKED: run-hook.sh: unknown hook name '$name' -- the plugin's hooks.json and run-hook.sh disagree" >&2; exit 2; }
pol=$HC_POL
proj="${CLAUDE_PROJECT_DIR:-.}"
s=""; [ -r "$proj/.claude/settings.json" ] && IFS= read -r -d '' s < "$proj/.claude/settings.json"
u=""; [ -r "$HOME/.claude/settings.json" ] && IFS= read -r -d '' u < "$HOME/.claude/settings.json"
hc_skip "$name" "$proj" "$s" "$u" && exit 0
f="$here/$name.sh"
if [ ! -r "$f" ]; then
  case $pol in
    closed) echo "HOOK SCRIPT MISSING: $f -- enforcement offline. Reinstall the cct plugin (claude plugin uninstall cct@dagonet, then claude plugin install cct@dagonet)." >&2; exit 2 ;;
    warn)   echo "WARN: $f missing -- $name offline. Reinstall the cct plugin (claude plugin uninstall cct@dagonet, then claude plugin install cct@dagonet)." >&2; exit 0 ;;
    *)      exit 0 ;;
  esac
fi
exec bash "$f"
