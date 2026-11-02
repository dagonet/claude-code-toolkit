#!/usr/bin/env bash
# cct hook dispatcher (v6.0 design D1-D6). hooks/hooks.json registers one dispatcher per tool:
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/dispatch.sh" bash|powershell
# One process runs the tool's guards in a fixed order: all closed guards first (cheapest first, pre-commit-test
# last among them), then the open and warn guards. Each guard is SOURCED in a subshell with stdin on /dev/null, so
# it costs one fork: no exec, no bash start. The payload is read once here and handed over in CCTD_MEMO (json.sh).
#   rc 2      the guard denied: stop, exit 2 (its stderr has already gone out)
#   other rc  the guard's own non-blocking error: continue, as Claude Code treats it for a single hook
#   rc 0      keep its stdout; it is printed only if the run ends with exit 0 and exactly one guard answered
# A dispatcher error of its own (unknown table, missing or corrupt lib) exits 2: the open guards fail closed too.
# Rules that keep a guard's world the same as under `bash <guard>.sh`: never `set -e` or `set -u` (a nounset abort
# exits 1, which is non-blocking), never export, every variable starts with cctd_ (internal) or CCTD_ (handed to
# guards), and the shell's directory never changes (the guards rely on it).
# Sourced (Task 6's replay) only the functions and the libs load; the run starts when the file is executed.

# --- the libs, at top level, so a sourced use has them too. Any problem leaves cctd_ok=0, and every function refuses.
cctd_ok=0
cctd_dir=${BASH_SOURCE[0]%/*}
if [ "$cctd_dir" = "${BASH_SOURCE[0]}" ]; then cctd_dir=.; fi
cctd_dir=$(cd "${cctd_dir:-/}" && pwd)
if [ -n "$cctd_dir" ] && [ -r "$cctd_dir/lib/json.sh" ] && [ -r "$cctd_dir/lib/hook-class.sh" ]; then
  . "$cctd_dir/lib/json.sh"
  . "$cctd_dir/lib/hook-class.sh"
  # a lib that is present but corrupt defines fewer functions: refuse then, never run a guard
  if declare -F json_memo_set json_fields hc_class hc_skip >/dev/null 2>&1; then cctd_ok=1; fi
fi

cctd_libs_ok() {
  [ "$cctd_ok" = 1 ] && return 0
  echo "HOOK BLOCKED: dispatch.sh: hooks/lib/json.sh or hooks/lib/hook-class.sh missing or corrupt -- reinstall the cct plugin (claude plugin uninstall cct@dagonet, then claude plugin install cct@dagonet)" >&2
  return 1
}

# cctd_prepare -- read the payload and the two settings files once, parse the payload once (json_memo_set).
# json_memo_set's own rc is not acted on: the memo carries it to each guard, which decides as it does today.
# A NUL byte makes `read -d ''` stop early, which would hand the guards a truncated payload: refuse that.
cctd_prepare() {
  SECONDS=0   # the dispatcher's start IS the hook start: pre-commit-test's hook-wide ceiling counts from here (it runs after three other guards)
  cctd_libs_ok || return 2
  # every guard runs on </dev/null; if that cannot be opened the `.` never runs (rc 1) and every guard would be skipped
  : </dev/null 2>/dev/null || { echo "BLOCKED: dispatch.sh: /dev/null unreadable -- cannot determine" >&2; return 2; }
  unset CCTD_MEMO
  cctd_outs=()
  cctd_payload=
  if IFS= read -r -d '' cctd_payload; then
    echo "BLOCKED: dispatch.sh: the payload holds a NUL byte -- cannot determine" >&2
    return 2
  fi
  json_memo_set "$cctd_payload" tool_name cwd tool_input.command tool_input.file_path
  cctd_proj=${CLAUDE_PROJECT_DIR:-.}
  cctd_s=; [ -r "$cctd_proj/.claude/settings.json" ] && IFS= read -r -d '' cctd_s < "$cctd_proj/.claude/settings.json"
  cctd_u=; [ -r "$HOME/.claude/settings.json" ] && IFS= read -r -d '' cctd_u < "$HOME/.claude/settings.json"
  return 0
}

# cctd_source_guard <name> -- the runner, no selection. Returns the guard's rc. The guard's stdout joins cctd_outs
# only when its rc is 0 (design D4.3): Claude Code ignores the stdout of a hook that exits non-zero.
# The file name is taken BEFORE `set --`, which clears the positional parameters the name came from.
cctd_source_guard() {
  cctd_libs_ok || return 2
  cctd_file="$cctd_dir/$1.sh"
  cctd_o=$( set --; . "$cctd_file" </dev/null )
  cctd_rc=$?
  if [ "$cctd_rc" = 0 ] && [ -n "$cctd_o" ]; then cctd_outs[${#cctd_outs[@]}]=$cctd_o; fi
  return "$cctd_rc"
}

# cctd_run_guard <name> -- selection (class, step-aside, a missing script's polarity), then the runner.
# An unknown name is a dispatcher error: the class left over from the previous guard must never be read.
cctd_run_guard() {
  cctd_libs_ok || return 2
  if ! hc_class "$1"; then
    echo "HOOK BLOCKED: dispatch.sh: unknown guard '$1' in the table -- hooks/dispatch.sh and hooks/lib/hook-class.sh disagree" >&2
    return 2
  fi
  cctd_pol=$HC_POL
  hc_skip "$1" "$cctd_proj" "$cctd_s" "$cctd_u" && return 0
  cctd_file="$cctd_dir/$1.sh"
  if [ ! -r "$cctd_file" ]; then
    case $cctd_pol in
      closed) echo "HOOK SCRIPT MISSING: $cctd_file -- enforcement offline. Reinstall the cct plugin (claude plugin uninstall cct@dagonet, then claude plugin install cct@dagonet)." >&2; return 2 ;;
      warn)   echo "WARN: $cctd_file missing -- $1 offline. Reinstall the cct plugin (claude plugin uninstall cct@dagonet, then claude plugin install cct@dagonet)." >&2; return 0 ;;
      *)      return 0 ;;
    esac
  fi
  cctd_source_guard "$1"
}

# cctd_main <table> -- the run. The tables are one line each (a consistency check reads them).
cctd_main() {
  case ${1-} in
    bash)       cctd_tab='no-push-main deny-secret-reads gate-before-merge pre-commit-test deny-hang-shapes enforce-delegation' ;;
    powershell) cctd_tab='no-push-main gate-before-merge pre-commit-test' ;;
    *) echo "HOOK BLOCKED: dispatch.sh: unknown table '${1-}' -- the plugin's hooks.json and dispatch.sh disagree" >&2; return 2 ;;
  esac
  [ -n "$cctd_tab" ] || { echo "HOOK BLOCKED: dispatch.sh: empty table '${1-}'" >&2; return 2; }
  cctd_prepare || return 2
  for cctd_g in $cctd_tab; do
    cctd_run_guard "$cctd_g"
    if [ $? = 2 ]; then return 2; fi
  done
  if [ "${#cctd_outs[@]}" -gt 1 ]; then
    echo "BLOCKED: dispatch.sh: two guards answered on stdout -- cannot determine" >&2
    return 2
  fi
  if [ "${#cctd_outs[@]}" = 1 ]; then printf '%s\n' "${cctd_outs[0]}"; fi
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cctd_main "$@"
  exit $?
fi
