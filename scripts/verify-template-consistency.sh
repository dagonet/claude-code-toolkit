#!/usr/bin/env bash
# verify-template-consistency.sh
#
# Cross-variant verification suite for the wire-superpowers-skills change set.
# Runs greps from docs/plans/2026-04-12-wire-superpowers-skills.md §Verification
# plus drift checks added by the 2026-04-15 revival plan.
#
# Exit 0 = all checks pass. Exit 1 = at least one check failed.
# Run from repo root: bash scripts/verify-template-consistency.sh

set -u
fail=0
note() { printf "  %s\n" "$*"; }
ok() { printf "PASS  %s\n" "$*"; }
ko() { printf "FAIL  %s\n" "$*"; fail=1; }

VARIANTS="general dotnet dotnet-maui rust-tauri java python"

# ---------------------------------------------------------------------------
# 1. Plan Challenge Protocol pointer removed from every templates/*/CLAUDE.md
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  if grep -q "^# Plan Challenge Protocol$" "templates/$v/CLAUDE.md"; then
    ko "templates/$v/CLAUDE.md still has '# Plan Challenge Protocol' section"
  else
    ok "templates/$v/CLAUDE.md: Plan Challenge Protocol section removed"
  fi
done

# ---------------------------------------------------------------------------
# 2. Skill references present in every variant CLAUDE.md and AGENT_TEAM.md
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  if grep -q "superpowers:" "templates/$v/CLAUDE.md"; then
    ok "templates/$v/CLAUDE.md: contains superpowers references"
  else
    ko "templates/$v/CLAUDE.md: missing superpowers references"
  fi
  if grep -q "superpowers:" "templates/$v/AGENT_TEAM.md"; then
    ok "templates/$v/AGENT_TEAM.md: contains superpowers references"
  else
    ko "templates/$v/AGENT_TEAM.md: missing superpowers references"
  fi
done
if grep -q "superpowers:" user-level-reference/CLAUDE.md; then
  ok "user-level-reference/CLAUDE.md: contains superpowers references"
else
  ko "user-level-reference/CLAUDE.md: missing superpowers references"
fi

# ---------------------------------------------------------------------------
# 3. New Superpowers-skills header present in every CLAUDE.md
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  if grep -q "^## Superpowers Skills — MUST Invoke Before Responding$" "templates/$v/CLAUDE.md"; then
    ok "templates/$v/CLAUDE.md: Superpowers-skills header present"
  else
    ko "templates/$v/CLAUDE.md: Superpowers-skills header missing"
  fi
done
if grep -q "^## Superpowers Skills — MUST Invoke Before Responding$" user-level-reference/CLAUDE.md; then
  ok "user-level-reference/CLAUDE.md: Superpowers-skills header present"
else
  ko "user-level-reference/CLAUDE.md: Superpowers-skills header missing"
fi

# ---------------------------------------------------------------------------
# 4. Spawn-Prompt Binding Table present in every AGENT_TEAM.md
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  if grep -q "^### Spawn-Prompt Binding Table$" "templates/$v/AGENT_TEAM.md"; then
    ok "templates/$v/AGENT_TEAM.md: Spawn-Prompt Binding Table present"
  else
    ko "templates/$v/AGENT_TEAM.md: Spawn-Prompt Binding Table missing"
  fi
done

# ---------------------------------------------------------------------------
# 5. PO responsibility bullet present in every AGENT_TEAM.md
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  if grep -q "Spawn-prompt skill injection" "templates/$v/AGENT_TEAM.md"; then
    ok "templates/$v/AGENT_TEAM.md: PO 'Spawn-prompt skill injection' bullet present"
  else
    ko "templates/$v/AGENT_TEAM.md: PO 'Spawn-prompt skill injection' bullet missing"
  fi
done

# ---------------------------------------------------------------------------
# 6. Plan Challenge Protocol substance still in each AGENT_TEAM.md
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  if grep -q "Plan Challenge Protocol" "templates/$v/AGENT_TEAM.md"; then
    ok "templates/$v/AGENT_TEAM.md: Plan Challenge Protocol substance retained"
  else
    ko "templates/$v/AGENT_TEAM.md: Plan Challenge Protocol substance missing"
  fi
done

# ---------------------------------------------------------------------------
# 7. R4 byte-identity: all 6 AGENT_TEAM.md files identical
# ---------------------------------------------------------------------------
agent_team_hashes=$(md5sum templates/*/AGENT_TEAM.md | awk '{print $1}' | sort -u | wc -l)
if [ "$agent_team_hashes" = "1" ]; then
  ok "AGENT_TEAM.md byte-identical across all 6 variants"
else
  ko "AGENT_TEAM.md drift detected — variants are NOT byte-identical"
  md5sum templates/*/AGENT_TEAM.md
fi

# ---------------------------------------------------------------------------
# 8. R5 copy-paste snippets present (≥ 5 ## Required Skills blocks in general AGENT_TEAM.md)
# ---------------------------------------------------------------------------
required_blocks=$(grep -c "^## Required Skills$" templates/general/AGENT_TEAM.md)
if [ "$required_blocks" -ge 5 ]; then
  ok "templates/general/AGENT_TEAM.md: $required_blocks copy-paste '## Required Skills' blocks present (≥ 5)"
else
  ko "templates/general/AGENT_TEAM.md: only $required_blocks '## Required Skills' blocks (expected ≥ 5)"
fi

# ---------------------------------------------------------------------------
# 9. R2/R3 binding-table edits applied
# ---------------------------------------------------------------------------
coder_row=$(grep -A0 "^| \`coder\`" templates/general/AGENT_TEAM.md | head -1)
if echo "$coder_row" | grep -q "requesting-code-review"; then
  ko "templates/general/AGENT_TEAM.md: coder row still contains 'requesting-code-review' (R2 not applied)"
else
  ok "templates/general/AGENT_TEAM.md: coder row no longer contains 'requesting-code-review' (R2)"
fi
arch_row=$(grep -A0 "^| \`architect\`" templates/general/AGENT_TEAM.md | head -1)
if echo "$arch_row" | grep -q "brainstorming"; then
  ko "templates/general/AGENT_TEAM.md: architect row still contains 'brainstorming' (R3 not applied)"
else
  ok "templates/general/AGENT_TEAM.md: architect row no longer contains 'brainstorming' (R3)"
fi

# ---------------------------------------------------------------------------
# 10. Hook ↔ binding-table drift check (only runs if hook exists)
# ---------------------------------------------------------------------------
HOOK="hooks/require-skills-block.sh"
if [ -f "$HOOK" ]; then
  TABLE="templates/general/AGENT_TEAM.md"

  check_pair() {
    local subagent="$1"
    local skill="$2"
    if grep -q "$skill" "$HOOK" && grep -q "$skill" "$TABLE"; then
      ok "drift: $subagent → $skill present in both hook and binding table"
    elif grep -q "$skill" "$HOOK" && ! grep -q "$skill" "$TABLE"; then
      ko "drift: $skill in $HOOK but missing from $TABLE"
    elif ! grep -q "$skill" "$HOOK" && grep -q "$skill" "$TABLE"; then
      ko "drift: $skill in $TABLE but missing from $HOOK"
    fi
  }

  check_pair "coder" "karpathy-guidelines"
  check_pair "coder" "test-driven-development"
  check_pair "coder" "verification-before-completion"
  check_pair "coder" "receiving-code-review"
  check_pair "tester" "systematic-debugging"
  check_pair "test-writer" "test-driven-development"
  check_pair "architect" "writing-plans"
  check_pair "requirements-engineer" "brainstorming"

  # R2: coder row must NOT contain requesting-code-review in EITHER place
  if grep -q "requesting-code-review" "$HOOK"; then
    ko "drift: $HOOK contains 'requesting-code-review' (R2 says drop it from coder row)"
  else
    ok "drift: $HOOK does not contain 'requesting-code-review' (R2)"
  fi
else
  note "hooks/require-skills-block.sh not present yet — drift check skipped (will run after Chunk B)"
fi

# ---------------------------------------------------------------------------
# 11. Gate + contract lock-in (PR #38 / session-mining round 2)
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  s="templates/$v/.claude/settings.json"
  grep -q "gate-before-merge" "$s" \
    && ok "$s: gate-before-merge registered" \
    || ko "$s: gate-before-merge NOT registered"
  grep -q "enforce-agent-contract" "$s" \
    && ok "$s: enforce-agent-contract (SubagentStop) registered" \
    || ko "$s: enforce-agent-contract NOT registered"
done

settings_hashes=$(md5sum templates/*/.claude/settings.json | awk '{print $1}' | sort -u | wc -l)
if [ "$settings_hashes" = "1" ]; then
  ok "settings.json byte-identical across all 6 variants"
else
  ko "settings.json drift detected — variants are NOT byte-identical"
  md5sum templates/*/.claude/settings.json
fi

coder_contract=$(grep -l "## Deliverable Contract" templates/*/.claude/agents/coder.md templates/*/.claude/agents/*-coder.md 2>/dev/null | wc -l)
if [ "$coder_contract" = "11" ]; then
  ok "Deliverable Contract present in all 11 template coder files"
else
  ko "Deliverable Contract present in only $coder_contract/11 template coder files"
fi

coder_update_pr=$(grep -l "mcp__MCP_DOCKER__update_pull_request" templates/*/.claude/agents/coder.md templates/*/.claude/agents/*-coder.md 2>/dev/null | wc -l)
if [ "$coder_update_pr" = "11" ]; then
  ok "update_pull_request tool present in all 11 template coder files"
else
  ko "update_pull_request tool present in only $coder_update_pr/11 template coder files"
fi

reviewer_opus=$(grep -l "^model: opus$" templates/*/.claude/agents/code-reviewer.md 2>/dev/null | wc -l)
if [ "$reviewer_opus" = "6" ]; then
  ok "code-reviewer pinned to opus in all 6 variants"
else
  ko "code-reviewer opus pin present in only $reviewer_opus/6 variants"
fi

# ---------------------------------------------------------------------------
# 12. Delegate-everything lock-in (round 4)
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  s="templates/$v/.claude/settings.json"
  grep -q "enforce-delegation" "$s" \
    && ok "$s: enforce-delegation registered" \
    || ko "$s: enforce-delegation NOT registered"
  [ -f "templates/$v/.claude/agents/ops.md" ] \
    && ok "templates/$v: ops.md present" \
    || ko "templates/$v: ops.md MISSING"
done

ops_hashes=$(md5sum templates/*/.claude/agents/ops.md 2>/dev/null | awk '{print $1}' | sort -u | wc -l)
if [ "$ops_hashes" = "1" ]; then
  ok "ops.md byte-identical across all 6 variants"
else
  ko "ops.md drift detected — variants are NOT byte-identical"
fi

mandate_count=$(grep -l "Team-mode reporting" templates/*/.claude/agents/*.md 2>/dev/null | wc -l)
if [ "$mandate_count" = "42" ]; then
  ok "Team-mode reporting mandate present in 42 agent files (7 report agents x 6 variants)"
else
  ko "Team-mode reporting mandate present in only $mandate_count/42 agent files"
fi

# Liveness & Scope block: 53 template agent files + 8 user-level-reference = 61.
# Guards the progress-ping cadence and the scope-abort clause against drift.
liveness_count=$(grep -lF "## Liveness & Scope (HARD REQUIREMENT)" templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | wc -l)
if [ "$liveness_count" = "61" ]; then
  ok "Liveness & Scope block present in all 61 agent files (53 template + 8 user-level-reference)"
else
  ko "Liveness & Scope block present in only $liveness_count/61 agent files"
fi

scope_abort=$(grep -lF "Scope abort:" templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | wc -l)
if [ "$scope_abort" = "61" ]; then
  ok "Scope-abort clause present in all 61 agent files"
else
  ko "Scope-abort clause present in only $scope_abort/61 agent files"
fi

banned='fixes code directly|PO only|PO fixes directly|PO reviews directly|PO verifies directly|may be committed directly'
banned_hits=$(grep -rEl "$banned" templates/*/AGENT_TEAM.md templates/*/CLAUDE.md 2>/dev/null | wc -l)
if [ "$banned_hits" = "0" ]; then
  ok "No PO-inline-work phrases remain in any AGENT_TEAM.md/CLAUDE.md"
else
  ko "PO-inline-work phrases still present in $banned_hits files:"
  grep -rEln "$banned" templates/*/AGENT_TEAM.md templates/*/CLAUDE.md
fi

# ---------------------------------------------------------------------------
# 13. Hook-ref invariant (downstream sync findings 2026-07-19, finding #1)
#     Every hooks/<name>.sh referenced by any variant settings.json or by an
#     agent's YAML frontmatter hooks: block (command: lines) MUST exist and be
#     non-empty at the toolkit ROOT hooks/ (root-tracked design — variants do
#     NOT ship hooks/). Prose mentions are excluded (execution refs only).
# ---------------------------------------------------------------------------
hook_refs=$(
  {
    grep -ho 'bash hooks/[a-z-]*\.sh' templates/*/.claude/settings.json 2>/dev/null
    # frontmatter command: lines only (execution refs), not prose
    grep -h 'command:' templates/*/.claude/agents/*.md 2>/dev/null | grep -o 'bash hooks/[a-z-]*\.sh'
  } | sed 's|bash ||' | sort -u
)
if [ -z "$hook_refs" ]; then
  ko "hook-ref invariant: extraction returned NO references (extraction broken?)"
else
  for h in $hook_refs; do
    if [ -s "$h" ]; then
      ok "hook-ref: $h exists and is non-empty at repo root"
    else
      ko "hook-ref: $h referenced by a variant but MISSING/empty at repo root (fails open downstream)"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 14. v1.2 liveness sizing invariants.
#     These encode decisions that were reverted-into-existence by production
#     data; a future edit that reintroduces them should fail loudly here.
# ---------------------------------------------------------------------------
echo
# Strip comments first: the header deliberately explains why MAX_BLOCKS was
# removed, and that prose must not trip the assertion.
if grep -v '^[[:space:]]*#' hooks/require-teammate-report.sh 2>/dev/null | grep -q 'MAX_BLOCKS'; then
  ko "liveness: MAX_BLOCKS session cap is back — it exhausted itself in 21 h on real data (3 blocks vs 41)"
else
  ok "liveness: no session-wide block cap (per-teammate marker is the only throttle)"
fi

if grep -qE '\-ge +"?\$(BLOCK_AT|WARN_AT)' hooks/agent-budget-warn.sh 2>/dev/null; then
  ko "budget: a threshold uses -ge — that re-blocks every call past the threshold and traps the agent"
else
  ok "budget: thresholds are crossing-only (-eq), so blocked agents can still report"
fi

if grep -q 'BLOCK_EVERY' hooks/agent-budget-warn.sh 2>/dev/null; then
  ok "budget: blocks escalate past BLOCK_AT"
else
  ko "budget: BLOCK_EVERY missing — a single block does not stop a runaway (worst measured: 417 calls)"
fi

for f in hooks/require-teammate-report.sh hooks/agent-budget-warn.sh; do
  if grep -q 'liveness.log' "$f" 2>/dev/null; then
    ok "audit trail: $f writes .claude/liveness.log"
  else
    ko "audit trail: $f does not log — activation becomes unverifiable"
  fi
done

for v in general dotnet dotnet-maui rust-tauri java python; do
  if grep -q '^\.claude/liveness\.log$' "templates/$v/gitignore" 2>/dev/null; then
    ok "templates/$v/gitignore: ignores .claude/liveness.log"
  else
    ko "templates/$v/gitignore: missing .claude/liveness.log"
  fi
done

if [ -s scripts/check-activation.sh ]; then
  ok "scripts/check-activation.sh present"
else
  ko "scripts/check-activation.sh missing — no one-command activation answer"
fi

# ---------------------------------------------------------------------------
# 15. User-level agents must not carry project-only hooks.
#     A user-level agent applies in EVERY repo and its frontmatter `hooks:`
#     fire unconditionally, so referencing a project-only script fails closed
#     (127 -> exit 2). Measured: 11 of 20 local repos fall back to user-level
#     agents and 10 of those have no hooks/ dir -- the template coder's
#     gate-before-merge hooks would have made PR merges impossible there.
#     Body PROSE may reference hooks/ (it is conditional; the agent skips when
#     the script is absent), so this checks the frontmatter block only.
# ---------------------------------------------------------------------------
echo
ul_fail=0
for f in user-level-reference/agents/*.md; do
  [ -f "$f" ] || continue
  fm=$(awk 'NR==1&&/^---/{inb=1;next} inb&&/^---/{exit} inb{print}' "$f")
  if printf '%s\n' "$fm" | grep -q 'hooks/[a-z-]*\.sh'; then
    ko "user-level agent $(basename "$f") references a project-only script in its frontmatter (fails closed in repos without hooks/)"
    ul_fail=1
  fi
done
[ "$ul_fail" -eq 0 ] && ok "user-level agents carry no project-only frontmatter hooks"

# ---------------------------------------------------------------------------
# 16. Project MCP goes to the REPO ROOT.
#     Claude Code reads project-scope servers only from <project-root>/.mcp.json.
#     Setup scripts wrote <project>/.claude/.mcp.json until 2026-07-29, so those
#     servers never loaded. Guard both the write path and the gitignore.
# ---------------------------------------------------------------------------
for s in setup-project.sh setup-project.ps1; do
  [ -f "$s" ] || continue
  # Match the WRITE path only. The legacy-detection lines (legacy_mcp_path /
  # $legacyMcpPath) also name .claude/.mcp.json and must not trip this.
  bad=$(grep -c 'mcp_json_path="\$TARGET_DIR/\.claude/\.mcp\.json"\|\$mcpJsonPath = Join-Path (Join-Path \$TargetDir "\.claude")' "$s" 2>/dev/null || true)
  case "$bad" in ''|*[!0-9]*) bad=0 ;; esac
  if [ "$bad" -eq 0 ]; then
    ok "$s writes project MCP to the repo root"
  else
    ko "$s still writes <target>/.claude/.mcp.json — those servers will never load"
  fi
  if grep -q 'legacy_mcp\|legacyMcpPath' "$s" 2>/dev/null; then
    ok "$s warns about a legacy .claude/.mcp.json"
  else
    ko "$s does not warn about a legacy .claude/.mcp.json"
  fi
done

for v in general dotnet dotnet-maui rust-tauri java python; do
  if grep -q '^/\.mcp\.json' "templates/$v/gitignore" 2>/dev/null; then
    ok "templates/$v/gitignore: ignores root /.mcp.json"
  else
    ko "templates/$v/gitignore: missing /.mcp.json (generated file carries machine-specific paths)"
  fi
done

# The template copies MUST keep the merge gate -- this is the other half of the
# same invariant: the rule is scope-dependent, not a blanket removal.
for v in general dotnet dotnet-maui rust-tauri java python; do
  c="templates/$v/.claude/agents/coder.md"
  [ -f "$c" ] || continue
  if awk 'NR==1&&/^---/{inb=1;next} inb&&/^---/{exit} inb{print}' "$c" | grep -q 'gate-before-merge'; then
    ok "templates/$v coder keeps the merge gate in frontmatter"
  else
    ko "templates/$v coder LOST its gate-before-merge frontmatter hook"
  fi
done

# ---------------------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "ONE OR MORE CHECKS FAILED"
  exit 1
fi
