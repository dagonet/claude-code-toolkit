#!/usr/bin/env bash
# old-names.sh [<project-dir>] -- v7.0.0: warn about pre-v7 part names in a project's kept files.
#
# v7.0.0 moved the language coders and some skills out of the cct plugin into optional plugins, which renamed them.
# A kept project file (an agent of its own, project-instructions.md, a PROJECT-CUSTOM region, README.md, CLAUDE.local.md,
# its own skills and commands, settings files)
# may still use the old name. This script only REPORTS: one line per hit, "<file>:<line>: <old> -> <new> (...)". It writes
# nothing, never changes a file, prints nothing when there is nothing to report, and always exits 0 (a sync is never
# failed by it).
#
# The table below is the one place the old names live. It is the only file a check 76 exemption names, because
# check 76 (every cct:<name> a repo file mentions exists) would otherwise flag each old name here.
p=${1:-.}
[ -d "$p" ] || exit 0
cd "$p" 2>/dev/null || exit 0

# <old> <new>
MAP='cct:dotnet-coder dotnet-tools:dotnet-coder
cct:python-coder python-tools:python-coder
cct:rust-coder rust-tools:rust-coder
cct:java-coder java-tools:java-coder
cct:retro-review cct-learning:retro-review
cct:commit cct-helpers:commit
cct:contribute-upstream cct-helpers:contribute-upstream
cct:karpathy-guidelines cct-helpers:karpathy-guidelines
cct:mcp-usage cct-helpers:mcp-usage
cct:jev cct-jev:jev'

# the kept files a sync never rewrites, plus the two it does not read (README.md, CLAUDE.local.md), the project's own
# skills and commands, and the settings files (a Skill(...) permission can name an old skill)
FILES=$({ for f in .claude/agents/*.md .claude/rules/*.md .claude/project-instructions.md .claude/settings*.json CLAUDE.md CLAUDE.local.md \
                   AGENT_TEAM.md PROJECT_CONTEXT.md PROJECT_STATE.md README.md; do [ -f "$f" ] && printf '%s\n' "$f"; done
          find .claude/skills .claude/commands -type f 2>/dev/null | sort; })
[ -n "$FILES" ] || exit 0

printf '%s\n' "$MAP" | while read -r old new; do
  [ -n "$old" ] || continue
  plugin=${new%%:*}
  # a name ends at the first character that cannot be part of a part name: cct:commit-message and cct:jevons are not cct:commit / cct:jev
  printf '%s\n' "$FILES" | while IFS= read -r f; do
    grep -nE "(^|[^A-Za-z0-9_-])$old([^A-Za-z0-9_-]|\$)" "$f" 2>/dev/null | cut -d: -f1 | while read -r n; do
      printf '%s:%s: %s -> %s (if %s is installed; claude plugin install %s@dagonet)\n' "$f" "$n" "$old" "$new" "$plugin" "$plugin"
    done
  done
done
exit 0
