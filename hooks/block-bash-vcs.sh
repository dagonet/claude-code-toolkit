#!/usr/bin/env bash
# DEPRECATED in v2.0 — native git CLI is allowed; kept as a no-op for one release, removed in v2.1.
#
# This hook used to force every `git`/`gh` invocation through the git-tools MCP.
# In 6 weeks of transcripts it blocked 1,240 turns. v2.0 replaces the blanket ban
# with targeted gates that parse tool_input.command:
#   hooks/pre-commit-test.sh   — tests must pass before `git commit`
#   hooks/no-push-main.sh      — no `git push` to main/master
#   hooks/gate-before-merge.sh — fresh gate artifact before `gh pr merge`
#
# The file is retained (non-empty, exit 0) so downstream projects whose
# settings.json still references it do not fail closed on a 127.

exit 0
