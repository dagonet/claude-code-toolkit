#!/usr/bin/env bash
# allow-ctx-plan.sh — PreToolUse hook: auto-approve context-mode sandbox tools
# in every permission mode, including plan mode.
#
# Why: plan mode overrides permissions.allow rules for tools it does not
# classify as read-only, so ctx_* MCP tools prompt on every call even when
# "mcp__plugin_context-mode_context-mode__*" is allow-listed. PreToolUse hooks
# run BEFORE the permission system; permissionDecision "allow" bypasses the
# prompt. Register this under a matcher listing the ctx_* tool names.
#
# Failure polarity: if this script is missing, the hook exits 127 and Claude
# Code fails OPEN — the permission prompts simply return. Deliberately NOT
# 127-wrapped (wrapping an allow-hook would convert absence into a block).
#
# Fallback: if a Claude Code update stops PreToolUse allow from piercing plan
# mode, re-register the same command under the "PermissionRequest" event and
# pass EVENT=permission-request; see user-level-reference/settings-reference.md.

if [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
Usage: registered as a Claude Code PreToolUse hook (settings.json), matcher:
  mcp__plugin_context-mode_context-mode__ctx_batch_execute|mcp__plugin_context-mode_context-mode__ctx_execute|...
Emits a permissionDecision "allow" JSON so ctx_* tools never prompt (incl. plan mode).
With EVENT=permission-request emits the PermissionRequest-shaped decision instead.
EOF
  exit 0
fi

if [ "${EVENT:-}" = "permission-request" ]; then
  # PermissionRequest event shape (fallback path).
  printf '{"decision":{"behavior":"allow"}}\n'
else
  # PreToolUse event shape (primary path).
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"context-mode sandbox tool pre-approved (allow-ctx-plan)"}}\n'
fi
exit 0
