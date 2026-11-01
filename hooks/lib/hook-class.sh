#!/usr/bin/env bash
# Hook class, polarity and step-aside decision (v5.0 spec §3.1, §3.2, §3.5; v6.0 moved it out of run-hook.sh so the
# dispatcher decides the same way). Sourced; builtins only (no subshell, no external program).

# hc_class <name>: sets HC_CLS (machine|project) and HC_POL (closed|warn|open); returns 1 for an unknown name.
# class: machine = acts in every project (spec §3.1); project = only in a toolkit project.
# polarity on a missing script, copied from the v4.6.1 template wrappers: closed=exit 2, warn=stderr+0, open=0.
hc_class() {
  local cls pol
  case "$1" in
    no-push-main|deny-secret-reads)                              cls=machine; pol=closed ;;
    deny-hang-shapes|model-floor|bash-output-guard|verify-hooks) cls=machine; pol=open ;;
    jev-route|jev-notice)                                        cls=machine; pol=open ;;
    pre-commit-test|gate-before-merge|deny-claude-md-writes)     cls=project; pol=closed ;;
    read-size-gate|enforce-delegation|agent-budget-warn)         cls=project; pol=warn ;;
    post-edit-build|enforce-agent-contract|retro-ledger|retro-brief|now-brief) cls=project; pol=open ;;
    *) return 1 ;;
  esac
  HC_CLS=$cls; HC_POL=$pol
}

# hc_skip <name> <proj> <proj_settings_text> <user_settings_text>: returns 0 when the plugin's hook must not run
# (a project-only hook outside a toolkit project, or a project/user registration that already runs it), else 1.
# The caller reads the two settings files (empty text when unreadable); this function reads none.
hc_skip() {
  local name=$1 proj=$2 s=$3 u=$4
  hc_class "$name" || return 1
  if [ "$HC_CLS" = project ] && [ ! -f "$proj/.claude/template-manifest.json" ]; then return 0; fi
  # step-aside (spec §3.2): the same literal substring tests as v4's user-level registrations.
  # Like v4's wrappers, step aside only when the project's own copy is there to run: a registration
  # whose script is missing would otherwise leave NO hook running.
  case $s in *'}/hooks/'"$name"'.sh\"'*) [ -f "$proj/hooks/$name.sh" ] && return 0 ;; esac
  case $u in *'/hooks/'"$name"'.sh"'*) return 0 ;; esac
  return 1
}
