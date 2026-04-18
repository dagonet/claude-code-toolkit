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
# 3. New Solo PO matrix header present in every CLAUDE.md
# ---------------------------------------------------------------------------
for v in $VARIANTS; do
  if grep -q "^## Superpowers Skills — When to Invoke$" "templates/$v/CLAUDE.md"; then
    ok "templates/$v/CLAUDE.md: Solo PO matrix header present"
  else
    ko "templates/$v/CLAUDE.md: Solo PO matrix header missing"
  fi
done
if grep -q "^## Superpowers Skills — When to Invoke$" user-level-reference/CLAUDE.md; then
  ok "user-level-reference/CLAUDE.md: Solo PO matrix header present"
else
  ko "user-level-reference/CLAUDE.md: Solo PO matrix header missing"
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
echo
if [ "$fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "ONE OR MORE CHECKS FAILED"
  exit 1
fi
