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
# 1. (removed in v2.1 PR7) The "# Plan Challenge Protocol heading is gone from
#    CLAUDE.md" assertion is strictly subsumed by check 6, which now asserts the
#    absence of the whole plan-gate vocabulary in CLAUDE.md and AGENT_TEAM.md.
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
# 6. The plan gate is gone (v2.1 PR7). Boris Cherny, Jun 2026: "I don't use plan
#    mode anymore … it just doesn't need it." Plans are optional artifacts now
#    and every spawn carries its brief instead, so no workflow doc may
#    reintroduce the mandate or name the deleted hook. One alternation per file
#    so a partial revival fails on the file it lives in.
# ---------------------------------------------------------------------------
GATE_LITERALS='Plan Challenge Protocol|EnterPlanMode|Challenge 1|Challenge 2|tier-before-coder'
for v in $VARIANTS; do
  for f in "templates/$v/AGENT_TEAM.md" "templates/$v/CLAUDE.md"; do
    # An absence grep passes vacuously on a missing file — guard first.
    [ -f "$f" ] || { ko "$f: missing"; continue; }
    if grep -qE "$GATE_LITERALS" "$f"; then
      ko "$f: plan-gate mandate is back — $(grep -oE "$GATE_LITERALS" "$f" | sort -u | tr '\n' ' ')"
    else
      ok "$f: carries no plan-gate mandate"
    fi
  done
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
# ⚠ R3 IS DELIBERATELY REVERSED IN v3.0.0 (item B2), AND THE POLARITY OF THIS
# ASSERTION IS FLIPPED TO SAY SO OUT LOUD. R3 dropped `brainstorming` from the
# architect row, and that was correct while a SEPARATE `requirements-engineer`
# owned requirements exploration. v3.0.0 absorbed that agent INTO `architect`,
# so the same agent now does both jobs and needs the skill R3 removed. The
# assertion is re-pointed rather than deleted: an absence whose reason has
# expired must not be allowed to outlive it silently, and a deleted check would
# have let the skill drift back out with nothing noticing.
arch_row=$(grep -A0 "^| \`architect\`" templates/general/AGENT_TEAM.md | head -1)
if echo "$arch_row" | grep -q "brainstorming"; then
  ok "templates/general/AGENT_TEAM.md: architect row carries 'brainstorming' (v3.0.0 absorbed requirements-engineer; R3 reversed on purpose)"
else
  ko "templates/general/AGENT_TEAM.md: architect row is missing 'brainstorming' — it absorbed requirements-engineer in v3.0.0 and must carry that agent's skill, or the absorption dropped a capability"
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
  # v3.0.0 (item B2): these two pairs used to be keyed on `test-writer` and
  # `requirements-engineer`. Both names were ABSORBED — into `tester` and
  # `architect` respectively — so the pairs are RE-KEYED onto the survivors
  # rather than deleted. Deleting them would have been the quiet failure:
  # check_pair prints NOTHING when a skill is absent from BOTH sides, so a pair
  # left naming a retired agent goes vacuous, reporting neither PASS nor FAIL.
  # Re-keying keeps the assertion doing work against the agent that now owns the
  # skill. `test-driven-development` in particular would otherwise have kept
  # passing off `coder`'s row — a pass for the wrong reason.
  check_pair "tester" "test-driven-development"
  check_pair "architect" "writing-plans"
  check_pair "architect" "brainstorming"

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

# Expected counts are computed by glob, not hard-coded, so adding an agent type
# does not silently invalidate the assertion.
#   report agents = every template agent file EXCEPT the coders (coder.md and the
#   language variants); the coders carry the Deliverable Contract instead.
report_agents=$(ls templates/*/.claude/agents/*.md 2>/dev/null | grep -vE 'coder\.md$' | wc -l)
mandate_count=$(grep -l "Subagent reporting" templates/*/.claude/agents/*.md 2>/dev/null | wc -l)
if [ "$mandate_count" = "$report_agents" ]; then
  ok "Subagent reporting mandate present in all $report_agents non-coder agent files"
else
  ko "Subagent reporting mandate present in only $mandate_count/$report_agents non-coder agent files"
fi

# Liveness & Scope block: every template + user-level-reference agent file.
# Guards the final-message reporting contract and the scope-abort clause.
all_agents=$(ls templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | wc -l)
liveness_count=$(grep -lF "## Liveness & Scope (HARD REQUIREMENT)" templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | wc -l)
if [ "$liveness_count" = "$all_agents" ]; then
  ok "Liveness & Scope block present in all $all_agents agent files"
else
  ko "Liveness & Scope block present in only $liveness_count/$all_agents agent files"
fi

scope_abort=$(grep -lF "Scope abort:" templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | wc -l)
if [ "$scope_abort" = "$all_agents" ]; then
  ok "Scope-abort clause present in all $all_agents agent files"
else
  ko "Scope-abort clause present in only $scope_abort/$all_agents agent files"
fi

# v2.0: subagents report in their FINAL MESSAGE. SendMessage was the named-teammate
# channel and must not creep back into an agent definition — a partial sweep of the
# 61 files would otherwise pass every assertion above.
sendmsg=$(grep -lF "SendMessage" templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | wc -l)
if [ "$sendmsg" = "0" ]; then
  ok "No agent definition instructs SendMessage reporting (agent teams retired)"
else
  ko "SendMessage reporting survives in $sendmsg agent files:"
  grep -lF "SendMessage" templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null
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
#     v2.1.2: hook commands now invoke "${CLAUDE_PROJECT_DIR:-.}/hooks/<name>.sh",
#     so the extraction anchors on the command: line and pulls the hooks/ path
#     out of it — that accepts both the old cwd-relative and the new absolute
#     form, and still excludes the permissions allow pattern (no `command:`).
extracted=$(
  {
    grep -h '"command":' templates/*/.claude/settings.json 2>/dev/null
    # frontmatter command: lines only (execution refs), not prose
    grep -h 'command:' templates/*/.claude/agents/*.md 2>/dev/null
  } | grep -o 'hooks/[A-Za-z0-9_-]*\.sh' | sort -u
)
# The vacuity check runs on the EXTRACTION only. run-gate.sh is added afterwards,
# so a broken grep can never be masked by the unconditional entry.
if [ -z "$extracted" ]; then
  ko "hook-ref invariant: extraction returned NO references (extraction broken?)"
fi
# run-gate.sh is named only by the `Bash(bash hooks/run-gate.sh*)` PERMISSIONS
# pattern and by prose, never by a `command:` line, so the anchored extraction
# above cannot see it. It is the most load-bearing script in the repo (the Gate
# mechanism, gate-before-merge.sh's dependency, every coder's deliverable
# contract), so assert it explicitly rather than let it fall out of coverage.
hook_refs=$(printf '%s\nhooks/run-gate.sh\n' "$extracted" | grep -v '^$' | sort -u)
for h in $hook_refs; do
  if [ -s "$h" ]; then
    ok "hook-ref: $h exists and is non-empty at repo root"
  else
    ko "hook-ref: $h referenced by a variant but MISSING/empty at repo root (fails open downstream)"
  fi
done

# ---------------------------------------------------------------------------
# 14. v1.2 liveness sizing invariants.
#     These encode decisions that were reverted-into-existence by production
#     data; a future edit that reintroduces them should fail loudly here.
# ---------------------------------------------------------------------------
echo
# v2.0: the TeammateIdle gate is retired (agent teams are gone), so the
# MAX_BLOCKS assertion moved to the hook that still throttles: agent-budget-warn.
# The history it encodes — a session-wide cap exhausts itself and leaves the rest
# of a long session ungated — applies to any future cap, so keep asserting it.
if grep -v '^[[:space:]]*#' hooks/agent-budget-warn.sh 2>/dev/null | grep -q 'MAX_BLOCKS'; then
  ko "liveness: a MAX_BLOCKS session cap is back — it exhausted itself in 21 h on real data (3 blocks vs 41)"
else
  ok "liveness: no session-wide block cap (per-agent thresholds are the only throttle)"
fi

# v2.1: the deprecated TeammateIdle stub is deleted (it was kept non-empty for
# exactly one release so a downstream settings.json naming it would not fail
# closed on a 127). Its two assertions are gone with it.

# The retro ledger pair (v2.0 PR2) must exist and stay fail-open: both are
# registered UNWRAPPED, so a non-zero exit would break every stop / session start.
for f in hooks/retro-ledger.sh hooks/retro-brief.sh; do
  if [ -s "$f" ]; then
    ok "retro: $f present"
  else
    ko "retro: $f MISSING — the subagent-failure ledger is not shipped"
  fi
done
if printf '%s' '{not json' | bash hooks/retro-ledger.sh >/dev/null 2>&1; then
  ok "retro-ledger.sh exits 0 on an unusable payload"
else
  ko "retro-ledger.sh exits non-zero on an unusable payload — it would block subagent stops"
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

for f in hooks/agent-budget-warn.sh; do
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
# 15b. A copyable user-level settings.json ships, and carries no machine paths.
#      Hook commands must use ~ (verified to expand inside a hook command
#      string), never an absolute /Users/<name> or C:/Users/<name> path.
# ---------------------------------------------------------------------------
ULS=user-level-reference/settings.json
if [ ! -s "$ULS" ]; then
  ko "$ULS missing — the reference cannot be copied to ~/.claude/settings.json"
else
  if command -v node >/dev/null 2>&1 && node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$ULS" 2>/dev/null; then
    ok "$ULS is valid JSON"
  else
    ko "$ULS is not valid JSON"
  fi
  if grep -qiE '"command":[^"]*"[^"]*(C:/Users/|C:\\\\+Users\\\\+|/home/[a-z]|/Users/[a-z])' "$ULS"; then
    ko "$ULS hook command uses an absolute home path — use ~/.claude/hooks/… instead"
  else
    ok "$ULS hook commands use ~ rather than an absolute home path"
  fi
fi

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
# 17. Tool-allowlist invariant (v2.0 PR3).
#     ~400 tool calls in the mined sessions hit tools the calling agent did not
#     have — dotnet-tools failed 87 of 87 times because the body told the agent
#     to use it and `tools:` did not list it. Rule: every mcp__server__tool
#     named in an agent BODY must appear in that agent's `tools:` line. A file
#     with no `tools:` line inherits everything and is exempt.
#     Frontmatter is excluded on purpose: a `hooks:` matcher legitimately names
#     tools the agent itself cannot call. The token class is case-SENSITIVE but
#     includes upper case — a lower-case-only pattern is blind to
#     mcp__MCP_DOCKER__*, the most-used server, and would pass vacuously.
# ---------------------------------------------------------------------------
echo
allow_fail=0
for f in templates/*/.claude/agents/*.md user-level-reference/agents/*.md; do
  [ -f "$f" ] || continue
  tools_line=$(awk 'NR==1&&/^---/{inb=1;next} inb&&/^---/{exit} inb&&/^tools:/{print}' "$f")
  [ -z "$tools_line" ] && continue
  body=$(awk 'NR==1&&/^---/{inb=1;next} inb&&/^---/{inb=0;body=1;next} body{print}' "$f")
  for t in $(printf '%s' "$body" | grep -oE 'mcp__[a-zA-Z0-9_-]+__[a-zA-Z0-9_]+' | sort -u); do
    case "$tools_line" in
      *"$t"*) ;;
      *) ko "allowlist: $f body uses $t, which is not in its tools: line"; allow_fail=1 ;;
    esac
  done
done
[ "$allow_fail" -eq 0 ] && ok "every mcp__ tool named in an agent body is in that agent's tools: allowlist"

# ---------------------------------------------------------------------------
# 18. Model / effort routing (v2.0 PR3).
#     Aliases only: the user reroutes `sonnet` to a cheaper provider through a
#     proxy, so a pinned claude-* id silently bypasses that routing. `mode:` is
#     not a documented subagent field and was ignored wherever it appeared.
#     The custom Explore agent must ship in every variant, or the built-in one
#     inherits the session model (219 exploration spawns at Opus cost).
# ---------------------------------------------------------------------------
echo
explore_files=$(ls templates/*/.claude/agents/Explore.md user-level-reference/agents/Explore.md 2>/dev/null | wc -l)
if [ "$explore_files" = "7" ]; then
  ok "custom Explore agent present in all 6 variants + user-level"
else
  ko "custom Explore agent present in only $explore_files/7 locations (built-in Explore inherits the session model)"
fi

explore_haiku=$(grep -l "^model: haiku$" templates/*/.claude/agents/Explore.md user-level-reference/agents/Explore.md 2>/dev/null | wc -l)
if [ "$explore_haiku" = "7" ]; then
  ok "Explore pinned to haiku in all 7 copies"
else
  ko "Explore pinned to haiku in only $explore_haiku/7 copies"
fi

pinned_ids=$(grep -l "^model: claude-" templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | wc -l)
if [ "$pinned_ids" = "0" ]; then
  ok "no agent pins a full claude-* model id (aliases only — a proxy may reroute them)"
else
  ko "$pinned_ids agent files pin a full claude-* model id instead of an alias"
  grep -l "^model: claude-" templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null
fi

# The CLI does not validate `effort:`/`model:` — a v2.1 PR8 probe ran an agent
# carrying `effort: banana` with no warning and `claude plugin validate` passed.
# So a typo ships silently unless something here pins the documented value lists.
# Count the raw lines first: with no `effort:` anywhere, "0 offenders" is a
# vacuous pass and the whole check silently stops meaning anything.
all_effort=$(grep -h "^effort: " templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | grep -c .)
[ "$all_effort" -gt 0 ] || ko "no agent file carries an 'effort:' line — the level-list check would pass vacuously"
bad_effort=$(grep -h "^effort: " templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | grep -vcE "^effort: (low|medium|high|xhigh)$")
if [ "$bad_effort" = "0" ]; then
  ok "every agent 'effort:' value is one of low/medium/high/xhigh"
else
  ko "$bad_effort agent 'effort:' values are outside low/medium/high/xhigh (the CLI does not validate this field)"
  grep -n "^effort: " templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | grep -vE "effort: (low|medium|high|xhigh)$"
fi

all_model=$(grep -h "^model: " templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | grep -c .)
[ "$all_model" -gt 0 ] || ko "no agent file carries a 'model:' line — the alias-list check would pass vacuously"
bad_model=$(grep -h "^model: " templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | grep -vcE "^model: (sonnet|opus|haiku|fable|inherit)$")
if [ "$bad_model" = "0" ]; then
  ok "every agent 'model:' value is one of sonnet/opus/haiku/fable/inherit"
else
  ko "$bad_model agent 'model:' values are outside the alias list (the CLI does not validate this field)"
  grep -n "^model: " templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | grep -vE "model: (sonnet|opus|haiku|fable|inherit)$"
fi

mode_field=$(grep -l "^mode: " templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | wc -l)
if [ "$mode_field" = "0" ]; then
  ok "no agent carries the undocumented 'mode:' frontmatter field"
else
  ko "$mode_field agent files still carry 'mode:' (not a documented subagent field)"
fi

# Agents that are told to invoke skills need the Skill tool: a subagent whose
# tools: omits it cannot run the `## Required Skills` block the PO injects.
# Counted over the SAME file list, so adding Skill to one of the excluded
# agents later is a passing change, not a spurious count mismatch.
skill_list=$(ls templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | grep -vE '(Explore)\.md$')
skill_users=$(printf '%s\n' "$skill_list" | grep -c .)
skill_tool=$(printf '%s\n' "$skill_list" | xargs grep -lE "^tools:.*(^|[ ,])Skill([,]|$)" 2>/dev/null | wc -l)
if [ "$skill_tool" = "$skill_users" ]; then
  ok "Skill tool present in all $skill_users agent files that are told to invoke skills"
else
  ko "Skill tool present in only $skill_tool/$skill_users skill-invoking agent files"
fi

# All 12 coders (11 template + user-level) preload karpathy-guidelines, so the
# house style is in context from turn one rather than one Skill call later.
coder_skills=$(grep -l "karpathy-guidelines" templates/*/.claude/agents/coder.md templates/*/.claude/agents/*-coder.md user-level-reference/agents/coder.md 2>/dev/null | wc -l)
if [ "$coder_skills" = "12" ]; then
  ok "karpathy-guidelines preloaded via skills: in all 12 coder files"
else
  ko "karpathy-guidelines preloaded in only $coder_skills/12 coder files"
fi

# A coder that cannot create a file is not a coder: 44 Write calls died on the
# tool allowlist in the mined sessions.
coder_write=$(grep -lE "^tools:.*(^|[ ,])Write([,]|$)" templates/*/.claude/agents/coder.md templates/*/.claude/agents/*-coder.md user-level-reference/agents/coder.md 2>/dev/null | wc -l)
if [ "$coder_write" = "12" ]; then
  ok "Write tool present in all 12 coder files"
else
  ko "Write tool present in only $coder_write/12 coder files"
fi

# ---------------------------------------------------------------------------
# 19. Path-scoped rules (v2.0 PR4).
#     Language conventions moved out of the always-loaded CLAUDE.md into
#     .claude/rules/*.md. A rule WITHOUT a `paths:` frontmatter list loads at
#     launch at CLAUDE.md cost, which defeats the whole point of the move — so
#     every shipped rule must be path-scoped. `general` has no language of its
#     own and is expected to ship no rules; every other variant ships >= 1.
#     Counts are derived from the variant list, not hard-coded, so adding a
#     seventh variant does not silently pass with zero rules.
# ---------------------------------------------------------------------------
echo
rules_expected=0
rules_present=0
for v in $VARIANTS; do
  [ "$v" = "general" ] && continue
  rules_expected=$((rules_expected + 1))
  n=$(ls "templates/$v/.claude/rules/"*.md 2>/dev/null | wc -l)
  if [ "$n" -ge 1 ]; then
    rules_present=$((rules_present + 1))
    ok "templates/$v: $n path-scoped rule file(s) in .claude/rules/"
  else
    ko "templates/$v: no .claude/rules/*.md — language conventions have nowhere to live"
  fi
done
if [ "$rules_present" = "$rules_expected" ]; then
  ok "all $rules_expected non-general variants ship at least one rules file"
fi

# Every rule that ships MUST carry a `paths:` frontmatter list. An unconditional
# rule is always-loaded context wearing a rules/ filename.
rules_files=$(ls templates/*/.claude/rules/*.md 2>/dev/null | wc -l)
scoped=0
for f in templates/*/.claude/rules/*.md; do
  [ -f "$f" ] || continue
  fm=$(awk 'NR==1&&/^---/{inb=1;next} inb&&/^---/{exit} inb{print}' "$f")
  if printf '%s\n' "$fm" | grep -q '^paths:' && printf '%s\n' "$fm" | grep -qE '^[[:space:]]+- '; then
    scoped=$((scoped + 1))
  else
    ko "rules: $f has no 'paths:' glob list in its frontmatter (it would load at launch, at CLAUDE.md cost)"
  fi
done
if [ "$rules_files" -gt 0 ] && [ "$scoped" = "$rules_files" ]; then
  ok "all $rules_files rules files are paths-scoped"
elif [ "$rules_files" -eq 0 ]; then
  ko "rules: no .claude/rules/*.md found anywhere (extraction broken?)"
fi

# The CLAUDE.md diet is only safe if the moved text is still reachable: each
# variant that ships rules must point at them from CLAUDE.md.
for v in $VARIANTS; do
  [ "$v" = "general" ] && continue
  if grep -q '\.claude/rules/' "templates/$v/CLAUDE.md"; then
    ok "templates/$v/CLAUDE.md: points at .claude/rules/"
  else
    ko "templates/$v/CLAUDE.md: no pointer to .claude/rules/ — the moved conventions are orphaned"
  fi
done

# ---------------------------------------------------------------------------
# 20. Working-preferences custody (v2.0 PR4 round 2).
#     The 11 developer-agent preferences left every CLAUDE.md and now live ONLY
#     in the karpathy-guidelines skill, which all 12 coders preload via
#     `skills:`. Nothing else references them, so a careless edit to that one
#     file silently deletes behaviour from every coder in every variant with no
#     other check going red. Guard the heading and the bullet count.
#
#     The floor is the v1.5 post-trim count (18 bullets -> 11), which is the
#     set this PR relocated -- NOT the current length of the file. Adding a
#     preference is therefore a passing change; losing one is not. The count is
#     parsed from the section itself (heading to next `## ` or EOF), so no line
#     number and no bullet's literal text is baked into the assertion.
# ---------------------------------------------------------------------------
echo
KG=user-level-reference/skills/karpathy-guidelines/SKILL.md
WP_HEADING='## Toolkit working preferences'
WP_MIN=11
if [ ! -s "$KG" ]; then
  ko "prefs: $KG missing — the developer-agent preferences have no home (CLAUDE.md no longer carries them)"
elif ! grep -qF "$WP_HEADING" "$KG"; then
  ko "prefs: $KG has no '$WP_HEADING' section — the preferences moved out of CLAUDE.md and must land here"
else
  ok "prefs: $KG carries the '$WP_HEADING' section"
  wp_bullets=$(
    awk -v h="$WP_HEADING" '
      index($0, h) == 1 { inb = 1; next }
      inb && /^## / { exit }
      inb && /^- / { n++ }
      END { print n + 0 }
    ' "$KG"
  )
  if [ "$wp_bullets" -ge "$WP_MIN" ]; then
    ok "prefs: $wp_bullets preference bullets present (>= $WP_MIN, the v1.5 post-trim set this PR relocated)"
  else
    ko "prefs: only $wp_bullets preference bullets in $KG (expected >= $WP_MIN) — preferences were lost in the move, and no other check would notice"
  fi
fi

# The pointer left behind in CLAUDE.md has to resolve. `## Required Skills` was
# the original target and it no longer exists in CLAUDE.md (PR4 cut the table
# that defined it), so pin the skill name instead of the stale anchor.
for v in $VARIANTS; do
  if grep -q 'karpathy-guidelines' "templates/$v/CLAUDE.md"; then
    ok "templates/$v/CLAUDE.md: points at the karpathy-guidelines skill for developer preferences"
  else
    ko "templates/$v/CLAUDE.md: no pointer to karpathy-guidelines — the moved preferences are orphaned"
  fi
done

# ---------------------------------------------------------------------------
# 21. user-level hook mirror is byte-identical to the repo-root originals.
#
#     `user-level-reference/hooks/` is a copy source for `~/.claude/hooks/`, so
#     every file under it must be the same bytes as `hooks/<same relative path>`.
#     A drifted copy is worse than a missing one: the user-level gate would
#     silently enforce an older contract than the project-level gate.
#
#     Glob-derived, not a hard-coded list — mirroring one more hook needs no
#     edit here, and deleting a root hook while leaving its mirror fails.
#     `lib/` is included, which is why the walk is `find`-based and compares
#     relative paths rather than basenames.
#
#     Direction, deliberately: this walks the MIRROR, not the root. It cannot
#     catch a *new* root hook that nobody mirrored — that is not a drift, it is
#     a judgement call about which hooks belong at user level. run-gate.sh IS
#     mirrored (v2.1.3): the user-level pre-commit-test.sh shells into it, same
#     as the project-level one. retro-ledger.sh mirrors too (v2.1.4), so the
#     budget=<n> field lands the same way at user level; retro-brief.sh and
#     enforce-delegation.sh still deliberately do not mirror. What this check
#     guarantees is that nothing already in the mirror is stale or orphaned.
# ---------------------------------------------------------------------------
echo
ULH=user-level-reference/hooks
if [ ! -d "$ULH" ]; then
  ko "hook mirror: $ULH missing — the user-level copy step in the README has nothing to copy"
else
  mirror_count=0
  while IFS= read -r -d '' mf; do
    mirror_count=$((mirror_count + 1))
    rel="${mf#"$ULH"/}"
    root="hooks/$rel"
    if [ ! -f "$root" ]; then
      ko "hook mirror: $mf has no root original at $root — a mirror of a deleted hook"
    elif cmp -s "$root" "$mf"; then
      ok "hook mirror: $rel is byte-identical to $root"
    else
      ko "hook mirror: $rel differs from $root — run: cp $root $mf"
    fi
  done < <(find "$ULH" -type f -print0 | sort -z)
  [ "$mirror_count" -eq 0 ] && ko "hook mirror: $ULH is empty"
fi

# 21b. hooks/lib/json.sh must EXIST on both sides (v2.2.0).
#
#      The walk above starts from the mirror, so a lib file missing from BOTH
#      trees is invisible to it. Every git gate refuses to run without
#      hooks/lib/json.sh (fail closed), and the fail-open hooks disable
#      themselves — so its absence is a silent enforcement outage, not a
#      cosmetic drift.
for f in hooks/lib/json.sh "$ULH/lib/json.sh"; do
  if [ -f "$f" ]; then
    ok "$f present (the shared node/python3/jq reader)"
  else
    ko "$f MISSING — the git gates fail closed and the fail-open hooks disable themselves without it"
  fi
done
if grep -q 'lib/json\.sh' hooks/lib/git-cmd.sh; then
  ok "hooks/lib/git-cmd.sh sources lib/json.sh"
else
  ko "hooks/lib/git-cmd.sh no longer sources lib/json.sh — the gates are back to node-only"
fi

# ===========================================================================
# THE 21c-* CENSUS FAMILY — WHAT THESE CHECKS CAN AND CANNOT SEE.
#
#   A CENSUS OVER SOURCE TEXT CANNOT SEE BEHAVIOUR THAT ARRIVES THROUGH DATA.
#
# Every check below reads FILES IN THIS REPOSITORY and asserts a property of
# their text. That is the whole point of the family — a structural property
# holds for every future edit, where a fixture only holds for the inputs someone
# thought to write. But it fixes the surface: a hook's control flow has a SECOND
# source that no grep over this repo can reach, namely every config value the
# hook `eval`s. Those values are CONSUMER-authored, they do not exist here, and
# a census over source text is green for all of them.
#
# 21c-2f is the worked example and it is not a curiosity. It asserts "no
# `exit 1` in a registered hook" and was green at 9baa446 while
# pre-commit-test.sh exited 1 in practice, because the `exit 1` arrived as a
# consumer's `**Test**` value and was eval'd in the hook's own shell. The claim
# was true of the text and false of the process. Round 6 then found the same
# eval is reached by a SECOND key (`**Gate**`, via the mirror-fallback path at
# pre-commit-test.sh:175) — one statement, two value sources, and the census
# saw neither.
#
# pre-commit-test.sh will not be the last hook to eval a consumer-authored
# string, and this family will be green for every one of them. So:
#
#   - The question that finds this class: WHAT WOULD HAVE TO BE TRUE FOR THIS
#     NUMBER TO BE GREEN WHILE THE THING I CARE ABOUT IS BROKEN?
#   - An eval boundary needs a BEHAVIOURAL counterpart in scripts/test-hooks.sh
#     driving real config values, and that counterpart must cover EVERY key
#     that reaches the eval, not just the obvious one.
#   - Neither kind subsumes the other. Do not delete a census because its
#     behavioural partner is green, or the reverse.
# ===========================================================================

# 21c. EVERY hooks/lib/* must be mirrored (v2.2.1).
#
#      Check 21 walks the MIRROR, so it cannot see a root file nobody mirrored.
#      For top-level hooks that is deliberate — whether a hook belongs at user
#      level is a judgement call. For `lib/` it is not: the mirrored gates
#      SOURCE these files and fail closed without them, so a new root lib with
#      no mirror is a user-level enforcement outage the moment a mirrored gate
#      starts requiring it. This is the direction check 21 leaves open, closed
#      for the one subtree where it is never a judgement call.
for lf in hooks/lib/*; do
  [ -f "$lf" ] || continue
  lrel="${lf#hooks/}"
  if [ -f "$ULH/$lrel" ]; then
    ok "hook mirror: $lf is mirrored at $ULH/$lrel"
  else
    ko "hook mirror: $lf has NO mirror — run: cp $lf $ULH/$lrel (the mirrored gates source it and fail closed)"
  fi
done

# 21c-2. Every PROJECT_CONTEXT.md field anchor is BOM-tolerant (v2.2.4).
#
#      A UTF-8 BOM sits at byte 0, INSIDE line 1, so a `^`-anchored `**Key**:`
#      grep silently finds nothing when a key sits at the top of the file — and
#      "no field found" is the fail-OPEN arm in pre-commit-test.sh. This bug
#      class has been patched one instance at a time three times in this repo;
#      the census is what makes the NEXT anchor fail loudly instead. Every
#      `grep -E` over PROJECT_CONTEXT.md must go through GC_KEY_PRE.
bom_anchors=$(grep -n 'PROJECT_CONTEXT\.md' hooks/*.sh hooks/lib/*.sh 2>/dev/null | grep 'grep -E')
bom_total=$(printf '%s\n' "$bom_anchors" | grep -c .)
bom_bad=$(printf '%s\n' "$bom_anchors" | grep -v 'GC_KEY_PRE' | grep -c .)
if [ "$bom_total" -eq 0 ]; then
  ko "BOM census matched NO field anchors (glob or grep broken?) — passing vacuously"
elif [ "$bom_bad" -eq 0 ]; then
  ok "BOM census: all $bom_total PROJECT_CONTEXT.md field anchors use GC_KEY_PRE"
else
  ko "BOM census: $bom_bad of $bom_total field anchors bypass GC_KEY_PRE (a BOM hides a key on line 1)"
  printf '%s\n' "$bom_anchors" | grep -v 'GC_KEY_PRE' | sed 's/^/      /'
fi
# run-gate.sh is standalone (it must run with no JSON parser on PATH, which
# sourcing git-cmd.sh forbids), so it REPEATS the definition. Assert the two
# copies are the same literal — a duplicated constant that drifts is how the
# fixed instance and the unfixed one end up in the same release.
GC_KEY_PRE_DEF='GC_KEY_PRE="^(${GC_BOM})?[-*[:space:]]*"'
gkp_have=0
for gkf in hooks/lib/git-cmd.sh hooks/run-gate.sh; do
  grep -qF "$GC_KEY_PRE_DEF" "$gkf" && gkp_have=$((gkp_have + 1))
done
if [ "$gkp_have" -eq 2 ]; then
  ok "GC_KEY_PRE defined identically in git-cmd.sh and the standalone run-gate.sh"
else
  ko "GC_KEY_PRE definition drifted: found in $gkp_have of 2 files (git-cmd.sh, run-gate.sh)"
fi

# 21c-2b. GC_TERMINAL_RC, same census for the same reason (v2.2.5).
#
#      run-gate.sh EXITS this code and pre-commit-test.sh TESTS for it, from two
#      independent definitions. If they ever drift, the terminal failure quietly
#      becomes an ordinary one again and the circular "re-run it" advice is back
#      — with nothing red to show for it. That is the whole failure mode this
#      constant exists to prevent, so it is asserted rather than trusted.
GC_TERMINAL_RC_DEF='GC_TERMINAL_RC=78'
gtr_have=0
for gtf in hooks/lib/git-cmd.sh hooks/run-gate.sh; do
  grep -qF "$GC_TERMINAL_RC_DEF" "$gtf" && gtr_have=$((gtr_have + 1))
done
if [ "$gtr_have" -eq 2 ]; then
  ok "GC_TERMINAL_RC defined identically in git-cmd.sh and the standalone run-gate.sh"
else
  ko "GC_TERMINAL_RC definition drifted: found in $gtr_have of 2 files (git-cmd.sh, run-gate.sh)"
fi

# 21c-2c. The placeholder sweep passes its OPTIONS BEFORE its PATHS (v2.2.5).
#
#      `grep -rn -- '…' .claude hooks --include='*.sh'` parses the --include as
#      another PATH: the *.sh restriction never applies, the sweep recurses
#      markdown and JSON too, and its shell-comment filter then silently eats a
#      genuine markdown placeholder (`# {{FOO}}` reads as a comment). Measured
#      on GNU grep 3.0 and reproduced independently by a consumer. This is the
#      only part of that fix with any executable surface in this repo, so the
#      ordering is pinned here — prose alone would drift back.
sweepf="user-level-reference/skills/sync-template/SKILL.md"
if [ ! -f "$sweepf" ]; then
  ko "sweep ordering: $sweepf is missing"
else
  # Only the runnable sweep lines (a fenced command starts the line); prose
  # ABOUT the broken ordering deliberately quotes it and must not be flagged.
  sweep_cmds=$(grep -n '^grep -rn ' "$sweepf" | grep -F -- '--include')
  sweep_total=$(printf '%s\n' "$sweep_cmds" | grep -c .)
  sweep_bad=$(printf '%s\n' "$sweep_cmds" | grep -cv '^[0-9]*:grep -rn --include=')
  if [ "$sweep_total" -eq 0 ]; then
    ko "sweep ordering: no --include sweep command found in $sweepf (arm 2 lost its file filter?)"
  elif [ "$sweep_bad" -eq 0 ]; then
    ok "sweep ordering: all $sweep_total --include sweep commands pass options before paths"
  else
    ko "sweep ordering: $sweep_bad of $sweep_total sweep commands put --include AFTER the paths (the filter is then inert)"
    printf '%s\n' "$sweep_cmds" | grep -v '^[0-9]*:grep -rn --include=' | sed 's/^/      /'
  fi
fi

# 21c-3. The toolkit gates ITSELF (v2.2.5).
#
#      Without a root PROJECT_CONTEXT.md, pre-commit-test.sh and
#      gate-before-merge.sh no-op in this repository — which is how every
#      toolkit PR up to v2.2.4 merged through the artifact path as a silent
#      no-op. Deleting the file would restore that silence with no other
#      symptom, so it is asserted here. The Test/Gate SPLIT is asserted too:
#      Test runs on every commit and must stay fast, so the ~600s test-hooks.sh
#      belongs in Gate only.
rpc="PROJECT_CONTEXT.md"
if [ ! -f "$rpc" ]; then
  ko "self-gating: root PROJECT_CONTEXT.md is MISSING — the commit and merge gates no-op in this repo"
elif grep -q '{{[A-Z_]\{2,\}}}' "$rpc"; then
  ko "self-gating: root PROJECT_CONTEXT.md still carries an unfilled {{PLACEHOLDER}}"
else
  ok "self-gating: root PROJECT_CONTEXT.md present and placeholder-free"
fi
rpc_test=$(grep -E "^[-*[:space:]]*\*\*Test\*\*:" "$rpc" 2>/dev/null | head -1)
rpc_gate=$(grep -E "^[-*[:space:]]*\*\*Gate\*\*:" "$rpc" 2>/dev/null | head -1)
case "$rpc_test" in
  *verify-template-consistency.sh*) tsplit=1 ;;
  *) tsplit=0 ;;
esac
case "$rpc_test" in *test-hooks.sh*) tsplit=0 ;; esac
if [ "$tsplit" -eq 1 ]; then
  ok "self-gating: **Test** is the ~20s consistency script only (test-hooks.sh stays out of the per-commit path)"
else
  ko "self-gating: **Test** must be verify-template-consistency.sh WITHOUT test-hooks.sh — got: ${rpc_test:-<none>}"
fi
case "$rpc_gate" in
  *verify-template-consistency.sh*test-hooks.sh*) ok "self-gating: **Gate** runs the full pair (consistency + test-hooks)" ;;
  *) ko "self-gating: **Gate** must run both scripts — got: ${rpc_gate:-<none>}" ;;
esac
# Self-gating makes test-hooks.sh a CHILD of run-gate.sh, which exports
# RUN_GATE_ACTIVE=1 — inherited, it trips the recursion guard in every fixture
# that nests run-gate.sh, which then skip instead of running. The suite must not
# answer differently depending on who invoked it. (v2.2.5 round 6: the standalone
# and under-the-gate counts that used to sit here were stale two releases running
# — the CHANGELOG is the one place that carries them.)
if grep -q '^unset RUN_GATE_ACTIVE' scripts/test-hooks.sh; then
  ok "self-gating: test-hooks.sh unsets inherited RUN_GATE_ACTIVE (it runs as a child of run-gate.sh)"
else
  ko "self-gating: test-hooks.sh must 'unset RUN_GATE_ACTIVE' at the top — inherited, it fails 19 nested-gate fixtures"
fi
# Companion pin (v2.2.5 round 4). RUN_GATE_TERMINAL leaks by the same route and
# in the worse direction: an inherited marker path points at the REAL outer run's
# marker, a fixture's nested recursion guard touches it, and the outer clamp then
# reads a retryable 78 as terminal. Same class, opposite polarity, so it gets its
# own assertion rather than riding on the one above.
if grep -q '^unset RUN_GATE_TERMINAL' scripts/test-hooks.sh; then
  ok "self-gating: test-hooks.sh unsets inherited RUN_GATE_TERMINAL (a fixture must not touch the outer run's marker)"
else
  ko "self-gating: test-hooks.sh must 'unset RUN_GATE_TERMINAL' at the top — inherited, a fixture's nested guard marks the OUTER run terminal"
fi

# 21c-3e. The gates are REGISTERED, not merely configured (v2.2.6).
#
#      v2.2.5 shipped the file the gates READ (root PROJECT_CONTEXT.md, asserted
#      above) and called the toolkit self-gating. It was one-third true. There
#      was no project `.claude/settings.json` at all, and user-level wires only
#      no-push-main.sh — so pre-commit-test.sh and gate-before-merge.sh were
#      registered NOWHERE and `git commit` completed in 0s against a 58-117s
#      **Test** command. Every assertion above was green throughout: a census
#      over CONFIG cannot see whether the config is REGISTERED.
#
#      So this asserts the wiring, in the file that does the wiring, and it
#      asserts the fail-CLOSED wrapper too — a git gate registered with the
#      exit-0 WARN wrapper is a gate that waves through its own absence.
rsettings=".claude/settings.json"
if [ ! -f "$rsettings" ]; then
  ko "self-gating: root $rsettings is MISSING — pre-commit-test.sh and gate-before-merge.sh are registered nowhere (commits complete in 0s)"
else
  wired_bad=0
  for gh in pre-commit-test no-push-main gate-before-merge; do
    ghline=$(grep -c "hooks/$gh\.sh" "$rsettings")
    if [ "$ghline" -eq 0 ]; then
      ko "self-gating: hooks/$gh.sh is not registered in $rsettings — it never RUNS in this repo"
      wired_bad=1
    elif [ "$(grep -c "hooks/$gh\.sh.*HOOK SCRIPT MISSING.*exit 2" "$rsettings")" -eq 0 ]; then
      ko "self-gating: hooks/$gh.sh in $rsettings lacks the fail-CLOSED 127 wrapper (must echo 'HOOK SCRIPT MISSING' and exit 2)"
      wired_bad=1
    fi
  done
  [ "$wired_bad" -eq 0 ] && ok "self-gating: all three git gates registered in $rsettings with the fail-closed 127 wrapper"
  # And the file has to be TRACKABLE — the root .gitignore excluded /.claude/
  # wholesale until v2.2.6, and git never descends into an excluded DIRECTORY,
  # so a re-include under `/.claude/` is unreachable and the wiring would be
  # present on the author's disk and absent from every clone.
  if git check-ignore -q "$rsettings" 2>/dev/null; then
    ko "self-gating: $rsettings is GITIGNORED — the wiring exists locally and ships to nobody (use '/.claude/*' + '!/.claude/settings.json')"
  else
    ok "self-gating: $rsettings is trackable (root .gitignore re-includes it)"
  fi
fi

# 21c-3f. CONTROL for the sync skill's hook-reference collector (v2.2.6).
#
#      Step 6b is the ONLY check a consumer runs to confirm their hooks are
#      wired. Until v2.2.6 it said to collect the reference "on a `command:`
#      line" — but the hook path sits AFTER an escaped quote inside that value,
#      so the obvious implementation truncates at the escape and recovered ZERO
#      from settings.json. A consumer printed `Hooks verified: 5 referenced,
#      5 present` with seven hooks unchecked; their 5 came entirely from the
#      step's two UNANCHORED greps. A PARTIAL result is what let it survive a
#      release — a zero would have looked broken.
#
#      This runs the pattern AS WRITTEN IN SKILL.md (not a copy of it) against a
#      real shipped settings.json, and compares the result against an
#      INDEPENDENTLY SOURCED set: the hook paths named in the 127-wrapper's
#      error MESSAGES, a different region of the same file that the truncating
#      anchor also loses. Re-anchoring the skill turns this red.
skf="user-level-reference/skills/sync-template/SKILL.md"
sksettings="templates/general/.claude/settings.json"
if [ ! -f "$skf" ] || [ ! -f "$sksettings" ]; then
  ko "6b collector control: $skf or $sksettings missing"
else
  sk_pat=$(grep -o "grep -o 'hooks/[^']*'" "$skf" | head -1 | sed "s/^grep -o '//; s/'$//")
  if [ -z "$sk_pat" ]; then
    ko "6b collector control: no \`grep -o 'hooks/...'\` collector found in $skf step 6b — the step lost its path-shaped extractor"
  else
    sk_got=$(grep -o "$sk_pat" "$sksettings" | sort -u)
    sk_exp=$(grep -o "\(HOOK SCRIPT MISSING\|WARN\): [^ ]*hooks/[A-Za-z0-9_.-]*\.sh" "$sksettings" | sed 's|.*/hooks/|hooks/|' | sort -u)
    sk_missing=$(printf '%s\n' "$sk_exp" | grep -Fxv -f <(printf '%s\n' "$sk_got") 2>/dev/null)
    sk_n=$(printf '%s\n' "$sk_got" | grep -c .)
    sk_m=$(printf '%s\n' "$sk_exp" | grep -c .)
    if [ -n "$sk_missing" ]; then
      ko "6b collector control: the skill's collector recovered $sk_n path(s) but MISSED $(printf '%s\n' "$sk_missing" | grep -c .) of the $sk_m independently-sourced ones — it is anchoring and under-collecting"
      printf '%s\n' "$sk_missing" | sed 's/^/      /'
    elif [ "$sk_n" -lt "$sk_m" ]; then
      ko "6b collector control: collector returned $sk_n < $sk_m independently-sourced references"
    else
      ok "6b collector control: the skill's own collector recovers $sk_n reference(s), covering all $sk_m independently sourced from the 127-wrapper messages"
    fi
  fi
fi

# 21c-2f. NO `exit 1` IN A REGISTERED HOOK — it is warn-and-ALLOW (v2.2.5 r4).
#
#         The harness treats every non-zero, non-2 PreToolUse exit as a
#         NON-BLOCKING error and lets the tool call proceed. So `|| exit 1` in a
#         GATE reads as "could not determine, carry on" — cannot-determine
#         permits, the shape this release keeps closing. pre-commit-test.sh had
#         two (`cd "$REPO_PATH" || exit 1`); a failing cd let the commit through
#         ungated.
#
#         Reaching those sites needs the directory to vanish between the
#         PROJECT_CONTEXT.md grep and the cd — a race no fixture can honestly
#         drive — so the property is asserted structurally here instead.
#         run-gate.sh is excluded on purpose: it is a RUNNER, not a registered
#         hook, and its `cd "$REPO_TOP" || exit 1` is documented to stay 1.
hook_exit1=$(grep -nE 'exit 1( |;|$)' hooks/pre-commit-test.sh hooks/gate-before-merge.sh hooks/no-push-main.sh 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
if [ -z "$hook_exit1" ]; then
  ok "no 'exit 1' in the registered git gates — a non-2 PreToolUse exit is warn-and-allow"
else
  ko "warn-and-allow: 'exit 1' in a registered hook lets the tool call PROCEED — use exit 2: $(printf '%s' "$hook_exit1" | head -3 | tr '\n' ' ')"
fi
#
#         THIS CENSUS READS SOURCE AND CANNOT REACH CONFIG DATA (v2.2.5 round 5).
#         It was green at 9baa446 while pre-commit-test.sh exited 1 in practice:
#         the `exit 1` arrived as a consumer's `**Test**` VALUE and was eval'd in
#         the hook's own shell. "This hook never exits anything but 0 or 2" was
#         true of the text and false of the process. A source census cannot
#         enumerate what a consumer may write, so the behavioural counterpart is
#         R5g in scripts/test-hooks.sh — it drives the hook with `exit`- and
#         `exec`-bearing **Test** values. Neither one subsumes the other; do not
#         delete either on the strength of the other being green.

# 21c-2h. THE `eval "$TEST_CMD"` BOUNDARY HAS NO TERMINAL ARM (v2.2.5 round 5).
#
#         Round 4 declined to clamp 78 at that boundary and the reasoning stands:
#         with no terminal arm there, a clamp assignment is UNOBSERVABLE — delete
#         it and every assertion stays green, which is the decorative-guard shape
#         this release forbids. But what makes the absence safe is a fact about
#         TODAY, and a comment defends against a reader, not against a refactor.
#         The person who adds a terminal arm is exactly the person not reading the
#         note about hypothetical terminal arms.
#
#         So the ABSENCE is asserted mechanically, and this census guards a
#         NEGATIVE: it is green while nothing keys on the terminal code below the
#         eval, and red the day someone adds one. The failure message names the
#         prerequisite rather than the symptom — a terminal arm there needs a
#         provenance channel FIRST, because a 78 arriving from an arbitrary
#         consumer command is a child's number with nothing behind it.
#
#         Positional by necessity, like 21c-2d: the same test on line ~153 is the
#         run-gate.sh branch and is LEGITIMATE (run-gate.sh clamps its own 78
#         keyed on the marker it created, so a 78 emerging from it carries
#         provenance). Whole-file grepping would be red on day one. Comment lines
#         are excluded — the prose below the eval discusses 78 at length.
#
#         Not the same guard as R5f/R5g in test-hooks.sh: this file is the
#         toolkit's own per-commit `**Test**`, test-hooks.sh is not (it runs only
#         under the full `**Gate**`). Same property, two cadences.
PCT_HOOK="hooks/pre-commit-test.sh"
pct_eval_ln=$(grep -n 'eval "\$TEST_CMD"' "$PCT_HOOK" | head -1 | cut -d: -f1)
if [ -z "$pct_eval_ln" ]; then
  ko "eval-boundary census: cannot locate 'eval \"\$TEST_CMD\"' in $PCT_HOOK — the boundary moved or was renamed; re-point this census before trusting it"
else
  pct_term=$(tail -n +"$pct_eval_ln" "$PCT_HOOK" \
    | grep -nE 'GC_TERMINAL_RC|-(eq|ne)[[:space:]]+78' \
    | grep -vE '^[0-9]+:[[:space:]]*#' || true)
  if [ -z "$pct_term" ]; then
    ok "$PCT_HOOK: no terminal arm below the eval boundary (line $pct_eval_ln) — a child's 78 has no provenance and must stay retryable"
  else
    ko "$PCT_HOOK: a TERMINAL ARM appeared below the eval boundary (line $pct_eval_ln). \$TEST_CMD is an arbitrary consumer command, so a 78 there is a CHILD's number with no provenance — branching on it hands a plain test failure the 'cannot succeed as configured' remedy, which is inverted advice. PREREQUISITE: give this boundary a provenance channel (as run-gate.sh has, keyed on the marker it writes) BEFORE adding the arm; the number alone cannot earn it. Offending line(s), offset from $pct_eval_ln: $(printf '%s' "$pct_term" | head -3 | tr '\n' ' ')"
  fi
fi

# 21c-2d. The RUN_GATE_ACTIVE test must PRECEDE the not-a-git-repository guard
#         in hooks/run-gate.sh (v2.2.5 round 4).
#
#         The second terminal guard (`:74`) does NOT touch the provenance marker,
#         which is safe ONLY because a nested invocation always exits at the
#         recursion guard first and can never reach it. That makes `:74`
#         top-level-only, where no outer clamp exists to mislead. Reorder the two
#         and a nested run-gate.sh in a non-repo cwd starts exiting 78 with no
#         marker — clamped to 1, the self-reference diagnosis lost.
#
#         A COMMENT CANNOT ENFORCE AN ORDERING; this can, and it fails on the
#         edit that breaks it. It is honest about being positional: the safety
#         here genuinely IS positional, so a positional assertion is not a proxy
#         for the property — it is the property. The comment in run-gate.sh stays
#         too: it carries the WHY, which a line-number census cannot. Same
#         pairing as GC_KEY_PRE.
rg_active_ln=$(grep -n 'RUN_GATE_ACTIVE:-' hooks/run-gate.sh | head -1 | cut -d: -f1)
rg_norepo_ln=$(grep -n 'not inside a git repository' hooks/run-gate.sh | head -1 | cut -d: -f1)
if [ -z "$rg_active_ln" ] || [ -z "$rg_norepo_ln" ]; then
  ko "run-gate.sh guard ordering: could not locate both guards (RUN_GATE_ACTIVE=${rg_active_ln:-<none>}, not-a-repo=${rg_norepo_ln:-<none>})"
elif [ "$rg_active_ln" -lt "$rg_norepo_ln" ]; then
  ok "run-gate.sh: the RUN_GATE_ACTIVE guard precedes the not-a-git-repository guard (line $rg_active_ln < $rg_norepo_ln)"
else
  ko "run-gate.sh guard ordering INVERTED: RUN_GATE_ACTIVE at line $rg_active_ln must come BEFORE the not-a-git-repository guard at line $rg_norepo_ln — otherwise a nested run exits 78 without the provenance marker and the outer clamp swallows it"
fi

# 21c-2e. NO BARE `78` in hooks/ (v2.2.5 round 4).
#
#         GC_TERMINAL_RC has a drift census (21c-2b) but nothing asserted that a
#         THIRD site could not appear spelled as a literal, bypassing the
#         constant entirely and drifting silently the next time the value moves.
#         None exists today; this keeps it that way. The target is the literal
#         USED as the value — `exit 78`, `-eq 78`, `-ne 78`, `<VAR>=78` — so the
#         constant's own two definitions and the prose that explains the number
#         (comments, the --help text) are not matched. A doc string cannot make
#         a caller test the wrong code; a bare literal can.
bare78=$(grep -nE '(exit[[:space:]]+78|-(eq|ne)[[:space:]]+78|[A-Za-z_][A-Za-z0-9_]*=78)([^0-9]|$)' hooks/*.sh hooks/lib/*.sh 2>/dev/null \
  | grep -v 'GC_TERMINAL_RC=78' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
if [ -z "$bare78" ]; then
  ok "no bare 78 in hooks/ — the terminal code is only ever GC_TERMINAL_RC"
else
  ko "bare 78 literal in hooks/ (use GC_TERMINAL_RC): $(printf '%s' "$bare78" | head -3 | tr '\n' ' ')"
fi

# 21c-2f. RUN_GATE_TERMINAL is exported BEFORE the gate command runs (v2.3.0).
#
#         v2.3.0 documented the terminal contract for consumer `**Gate**`
#         commands (docs/verification.md): print the remedy, touch
#         $RUN_GATE_TERMINAL, exit 78. That promotes the variable from an
#         internal provenance detail to a PUBLIC NAME. A refactor that moved the
#         export below `bash -c "$GATE_CMD"` — or dropped the `export` and left
#         a plain assignment — would leave every consumer preflight seeing an
#         empty value, skipping the touch, and having its 78 clamped to 1: the
#         exact silent failure the contract exists to prevent, and green
#         everywhere because the fallback IS the pre-contract behaviour.
#
#         Positional by necessity and by nature, like 21c-2d: "before the gate
#         runs" IS an ordering property, so a line-number comparison is not a
#         proxy for it. The R5h fixture in test-hooks.sh catches the same
#         reorder at RUNTIME; this file is the toolkit's own per-commit
#         `**Test**` and test-hooks.sh is not — same property, two cadences.
rgt_exp_ln=$(grep -n '^export RUN_GATE_TERMINAL$' hooks/run-gate.sh | head -1 | cut -d: -f1)
rgt_cmd_ln=$(grep -n 'bash -c "\$GATE_CMD"' hooks/run-gate.sh | head -1 | cut -d: -f1)
if [ -z "$rgt_exp_ln" ] || [ -z "$rgt_cmd_ln" ]; then
  ko "run-gate.sh terminal contract: could not locate both anchors (export RUN_GATE_TERMINAL=${rgt_exp_ln:-<none>}, bash -c \"\$GATE_CMD\"=${rgt_cmd_ln:-<none>}) — the PUBLIC contract in docs/verification.md tells consumers to touch \$RUN_GATE_TERMINAL, so re-point this assertion before trusting it"
elif [ "$rgt_exp_ln" -lt "$rgt_cmd_ln" ]; then
  ok "run-gate.sh: RUN_GATE_TERMINAL is exported before the gate command runs (line $rgt_exp_ln < $rgt_cmd_ln)"
else
  ko "run-gate.sh: RUN_GATE_TERMINAL is exported at line $rgt_exp_ln, AFTER the gate command at line $rgt_cmd_ln — a consumer preflight following the documented contract (docs/verification.md) would see an empty value, skip the touch, and have its terminal 78 clamped to 1. Silent, and green"
fi

# 21c-2g. The sync-template SKILL body carries a version marker, and it matches
#         VERSION (v2.2.5 round 4).
#
#         A running session obeys the body it LOADED, not the file on disk —
#         measured: an installed SKILL.md identical to the release while live
#         sessions still executed the previous version's steps, with the drift
#         check reporting clean throughout. The marker is what lets step 1 catch
#         that on the NEXT invocation and lets a session state which body it is
#         running. A marker that silently stops tracking VERSION is worse than
#         none: it would assert equality between two stale strings.
SKILL_MD="user-level-reference/skills/sync-template/SKILL.md"
want_marker="v$(head -1 VERSION 2>/dev/null | tr -d '\r')"
got_marker=$(grep -m1 -o 'SYNC-TEMPLATE-SKILL-VERSION: [^ ]*' "$SKILL_MD" 2>/dev/null | sed 's/.*: //')
if [ "$got_marker" = "$want_marker" ]; then
  ok "sync-template SKILL.md carries the body version marker ($got_marker, matches VERSION)"
else
  ko "sync-template SKILL.md marker '${got_marker:-<none>}' does not match VERSION '$want_marker' — a stale session could not be detected"
fi
# ...and step 1 must actually CHECK it. A marker nothing reads is decoration.
if [ "$(grep -c 'SYNC-TEMPLATE-SKILL-VERSION' "$SKILL_MD" 2>/dev/null)" -ge 2 ]; then
  ok "sync-template SKILL.md step 1 asserts the marker against the installed file"
else
  ko "sync-template SKILL.md defines the version marker but nothing reads it — step 1 must grep the installed file and compare"
fi

# 21c-3. The sync-template placeholder sweep is BOM-tolerant too (v2.2.4).
#
#        Same class as 21c-2, one layer out: the sweep is the skill's own
#        detector for unfilled placeholders and it runs on CONSUMER files, where
#        BOMs actually occur. Arm 1 (`^`-anchored markdown) fails CLEAN — a
#        placeholder on line 1 behind a BOM is missed silently; arm 2's comment
#        filter fails NOISY — a BOM'd comment stops reading as a comment. Both
#        arms carry `\(${BOM}\)\?`; this asserts neither loses it. The JSON arm
#        added in round 7 is deliberately NOT counted here — it has neither a
#        `^` anchor nor a comment filter, which are the only two things a BOM
#        breaks, so BOM tolerance is not a property it can have or lose.
SWEEP_SKILL="user-level-reference/skills/sync-template/SKILL.md"
sweep_arms=$(grep -c '{{\[A-Z_\]\\{2,\\}}}' "$SWEEP_SKILL" 2>/dev/null)
sweep_bom=$(grep -c 'BOM}\\)\\?' "$SWEEP_SKILL" 2>/dev/null)
if [ ! -f "$SWEEP_SKILL" ]; then
  ko "$SWEEP_SKILL missing — the placeholder sweep census cannot run"
elif [ "$sweep_bom" -ge 2 ]; then
  ok "placeholder sweep: the markdown and shell arms in $SWEEP_SKILL are BOM-tolerant"
else
  ko "placeholder sweep: only $sweep_bom of the markdown+shell arms in $SWEEP_SKILL carry the optional BOM prefix (the markdown arm would fail CLEAN, the shell arm noisy) — $sweep_arms sweep lines seen"
fi

# 21c-3b. NO PLACEHOLDER IN AN EXECUTABLE POSITION under user-level-reference/
#         (v2.2.5 round 5). THE HOOKS' CORRECTNESS — not the drift check's.
#
#         The user-level install is VERBATIM: nothing substitutes `{{...}}` at
#         user level, unlike the project bootstrap. That property is what makes
#         verify-user-level-drift.sh's blob-versus-tag comparison a legitimate
#         baseline, and it is asserted over there. It says NOTHING about whether
#         the files WORK, and the two come apart exactly where it matters:
#
#           A placeholder added in a shell VALUE position keeps verbatim-install
#           true, keeps the blob comparison green, and makes the hook execute a
#           literal `{{...}}`. Drift reports 0 and the hook is broken.
#
#         That is v2.2.0's `- **Protected branches**: {{DEFAULT_BRANCH}}` — a
#         config value read as data — one directory over. Only this assertion
#         catches the failure worth catching.
#
#         USE THE REFINED SWEEP ARMS, NOT A PLAIN GREP. A naive
#         `grep -rn '{{[A-Z_]\{2,\}}}' user-level-reference` returns 29 hits, not
#         one of them actionable: .mcp.json.template 12 (a never-installed
#         template whose placeholders are SUPPOSED to be unfilled), README.md 8,
#         SKILL.md 6 and git-cmd.sh 2 + pre-commit-test.sh 1 (comments) — and the
#         SKILL.md set includes the passage documenting this exact false
#         positive. Shipped that way the assertion is red on day one,
#         permanently, and gets disabled by someone whose reasoning looks sound.
#         Measured with the refined arms: shell 0, markdown 0 — the number pinned
#         below. Prose ABOUT a placeholder is not a placeholder.
#
#         SCANNED SURFACE, STATED BECAUSE 0 IS OTHERWISE OVERREAD: `*.sh` and
#         `*.md` ONLY. JSON is NOT scanned here — it is scanned by 21c-3c
#         immediately below, which closed round 6's residual. Do not widen these
#         two arms to `*.json`: their refinements (comment-line exclusion, the
#         `- **Key**: value` shape) exist because shell and markdown carry prose
#         that legitimately mentions placeholders, and JSON needs none of it.
#
#         BORN WITH ITS CONTROL, IN BAND. A sweep that matches nothing also
#         reports 0, so before trusting the number the detector is driven against
#         a planted fixture every run: a placeholder in a shell VALUE line must
#         be found, and the same placeholder in a BOM'd comment must not. If
#         either self-test fails, the 0 below means the detector is inert and is
#         reported as such rather than as a pass.
ULR_BOM=$(printf '\357\273\277')
ulr_sweep_sh() {   # <dir> -> executable-position placeholder hits in *.sh
  grep -rn --include='*.sh' -- '{{[A-Z_]\{2,\}}}' "$1" 2>/dev/null \
    | grep -v ":[0-9]*:\(${ULR_BOM}\)\?[[:space:]]*#"
}
ulr_sweep_md() {   # <dir> -> placeholders on a `- **Key**: value` config line
  grep -rn --include='*.md' -- \
    "^\(${ULR_BOM}\)\?[-*[:space:]]*\*\*[^*]\+\*\*:.*{{[A-Z_]\{2,\}}}" "$1" 2>/dev/null
}
ULRFIX=$(mktemp -d)
# The planted placeholder is ASSEMBLED, never spelled literally in an executable
# line of this file: a fixture that trips a future sweep pointed at scripts/ is
# how a detector acquires its first false positive.
ULR_PH=$(printf '{{%s}}' TEST_COMMAND)
printf 'TEST_CMD="%s"\n'              "$ULR_PH"             > "$ULRFIX/value.sh"
printf '%s# note: %s goes here\n'     "$ULR_BOM" "$ULR_PH"  > "$ULRFIX/comment.sh"
printf -- '- **Test**: %s\n'          "$ULR_PH"             > "$ULRFIX/value.md"
printf 'Prose mentioning %s inline.\n' "$ULR_PH"            > "$ULRFIX/prose.md"
ulr_pos_sh=$(ulr_sweep_sh "$ULRFIX" | grep -c 'value\.sh')
ulr_neg_sh=$(ulr_sweep_sh "$ULRFIX" | grep -c 'comment\.sh')
ulr_pos_md=$(ulr_sweep_md "$ULRFIX" | grep -c 'value\.md')
ulr_neg_md=$(ulr_sweep_md "$ULRFIX" | grep -c 'prose\.md')
if [ "$ulr_pos_sh" -eq 1 ] && [ "$ulr_neg_sh" -eq 0 ] && [ "$ulr_pos_md" -eq 1 ] && [ "$ulr_neg_md" -eq 0 ]; then
  ok "executable-position sweep: detector verified live (shell value hit / BOM'd comment ignored, md value hit / prose ignored)"
  ulr_hits=$( { ulr_sweep_sh user-level-reference; ulr_sweep_md user-level-reference; } | grep -c . )
  if [ "$ulr_hits" -eq 0 ]; then
    ok "user-level-reference/ (*.sh + *.md only): 0 placeholders in an EXECUTABLE position (a hook would run a literal {{...}})"
  else
    ko "user-level-reference/ (*.sh + *.md only): $ulr_hits placeholder(s) in an EXECUTABLE position — the user-level install substitutes NOTHING, so a shipped hook will run the literal {{...}}: $( { ulr_sweep_sh user-level-reference; ulr_sweep_md user-level-reference; } | head -3 | tr '\n' ' ')"
  fi
else
  ko "executable-position sweep is INERT — its own self-test failed (shell hit=$ulr_pos_sh want 1, shell comment=$ulr_neg_sh want 0, md hit=$ulr_pos_md want 1, md prose=$ulr_neg_md want 0). A detector that matches nothing also reports 0; do NOT read the count below as a pass."
fi
rm -rf "$ULRFIX"

# 21c-3c. NO PLACEHOLDER IN A SHIPPED *.json (v2.2.5 round 7). Closes the
#         residual 21c-3b recorded in round 6 rather than re-dating it.
#
#         WHY JSON IS THE CHEAPEST ARM, NOT THE MOST EXPENSIVE. The `*.sh` and
#         `*.md` arms above needed careful refinement — comment-line exclusion,
#         the `- **Key**: value` shape — precisely because those formats carry
#         prose and comments that LEGITIMATELY mention placeholders (which is
#         why a plain grep flags the skill passage documenting that fact).
#         JSON has no comments. Any `{{...}}` in a .json file is in a VALUE by
#         construction, so this is a bare grep: no exclusions, no shape
#         requirement, no false-positive class to tune. The excluded surface was
#         the one needing the least work to include, which inverts the usual
#         reason for excluding something and is probably why nobody noticed.
#
#         AND IT IS THIS RELEASE'S OWN CLASS. A `.claude/settings.json` hook
#         `command` is an EXECUTABLE position: a literal `{{...}}` there is a
#         path that does not resolve -> 127 -> fail-open. Measured on
#         templates/general/.claude/settings.json and reproduced byte-identical
#         on a live consumer: 30 `command` strings, 9 of them mentioning a 127
#         guard. Not a claim of 21 live holes — it depends which hook each wires
#         — but the ratio is the point: the surface no sweep covered is the
#         surface where a missing path fails open BY DEFAULT, and the 127
#         wrapper is the exception rather than the rule.
#
#         SCOPE BY OWNERSHIP, NEVER A FILESYSTEM WALK. JSON needs no
#         content-shape tuning; it DOES need scope discipline — two different
#         things, and conflating them is what makes a JSON arm look naive.
#         Measured on a real machine: `find ~/.claude -name '*.json'` is 3430
#         files with ONE hit, in a dated backup nothing reads, carrying
#         `{{GUIDE_TEMPLATE}}`/`{{USAGE_DATA}}`/`{{WINDOW_DAYS}}` — ANOTHER
#         TOOL's keys. Red on its first run for a benign reason: the exact
#         "reports a problem forever, gets disabled within a week by someone
#         whose reasoning looks sound" failure, reappearing inside the arm
#         designed from the argument against it. So this census scopes to the
#         two trees we OWN and never touches $HOME. And do NOT scope by
#         filtering on known toolkit key names: that rots the first time a key
#         is added, and it would hide a genuine unfilled placeholder under the
#         new one. Scope is the right axis; the key set is not.
#
#         WHY user-level-reference/ RATHER THAN THE LIVE ~/.claude TREE, AND THE
#         DEPENDENCY THAT MAKES THAT SUFFICIENT — READ BOTH HALVES. The only
#         user-level JSON the toolkit ships is user-level-reference/settings.json
#         (ONE file, versus 3430 in a walk), and verify-user-level-drift.sh
#         deliberately excludes settings.json as USER-OWNED — so a live-tree
#         check would be inspecting the user's own file. Our obligation is that
#         what we SHIP carries no unfilled placeholder in an executable
#         position. That repo-side census is SUFFICIENT for the user-level tree
#         ONLY BECAUSE THE USER-LEVEL INSTALL IS VERBATIM: reference clean +
#         verbatim install => live copy clean, by construction. That verbatim
#         property is asserted separately, in verify-user-level-drift.sh's
#         header (round 5). **These two look like independent checks and are one
#         argument with two halves** — if the verbatim-install assertion ever
#         goes red, this census stops implying anything at all about installed
#         copies. Do not let a cleanup drop either one as overlapping with the
#         other.
#
#         AND FOR THE PROJECT TREE THIS CENSUS IS NECESSARY BUT NOT SUFFICIENT,
#         WHICH CUTS THE OPPOSITE WAY. The project install is NOT verbatim: it
#         substitutes, and per sync-template SKILL.md `template_apply_file`
#         substitutes only placeholders present in THE PROJECT's manifest, so a
#         key the manifest predates lands as a literal in the consumer's file
#         while the template it came from is clean. That is the v2.2.0 chain
#         exactly — template correct -> substitution incomplete -> consumer
#         carries `- **Protected branches**: {{DEFAULT_BRANCH}}` -> trunk
#         silently unprotected — with a template-side census GREEN THROUGHOUT.
#         An install defect, not a shipping defect. The skill's consumer-side
#         JSON arm is the only detector for that class; this census cannot see
#         it. The two are asymmetric in construction (that arm can use
#         `git ls-files`, this one cannot for its user-level half) though
#         symmetric in intent — do not harmonise them into one walk.
#
#         BORN WITH ITS CONTROLS, IN BAND, AND THE NEGATIVE IS THE POINT. A
#         sweep that matches nothing also reports 0, so the detector is driven
#         against planted fixtures every run. The POSITIVE (in-scope value ->
#         found) proves it detects; the NEGATIVE (same placeholder OUTSIDE the
#         scoped set -> not found) is what makes the SCOPING testable — without
#         it the next person widens this back to a filesystem walk and nothing
#         goes red. The second negative pins the `--include='*.json'` extension
#         carve-out for `.mcp.json.template`, which is never installed and whose
#         placeholders are SUPPOSED to be unfilled.
JSONFIX=$(mktemp -d)
# Assembled, never spelled literally in an executable line — a fixture that
# trips a future sweep pointed at scripts/ is how a detector acquires its first
# false positive.
JSON_PH=$(printf '{{%s}}' GATE_COMMAND)
json_census() {   # <root>... -> placeholder hits in *.json under those roots
  grep -rn --include='*.json' -- '{{[A-Z_]\{2,\}}}' "$@" 2>/dev/null
}
mkdir -p "$JSONFIX/scoped" "$JSONFIX/unscoped"
printf '{ "command": "%s" }\n' "$JSON_PH" > "$JSONFIX/scoped/in.json"
printf '{ "command": "%s" }\n' "$JSON_PH" > "$JSONFIX/unscoped/out.json"
printf '{ "command": "%s" }\n' "$JSON_PH" > "$JSONFIX/scoped/mcp.json.template"
json_pos=$(json_census "$JSONFIX/scoped" | grep -c 'in\.json')
json_neg_scope=$(json_census "$JSONFIX/scoped" | grep -c 'out\.json')
json_neg_ext=$(json_census "$JSONFIX/scoped" | grep -c 'json\.template')
if [ "$json_pos" -eq 1 ] && [ "$json_neg_scope" -eq 0 ] && [ "$json_neg_ext" -eq 0 ]; then
  ok "JSON placeholder census: detector verified live (in-scope value hit / out-of-scope ignored / *.json.template ignored)"
  json_hits=$(json_census templates user-level-reference | grep -c .)
  if [ "$json_hits" -eq 0 ]; then
    ok "templates/ + user-level-reference/ (*.json): 0 placeholders — a settings.json hook command is an executable position, so a literal {{...}} there is a 127 fail-open"
  else
    ko "templates/ + user-level-reference/ (*.json): $json_hits placeholder(s) in a shipped JSON file — JSON has no comments, so every one of these is in a VALUE: $(json_census templates user-level-reference | head -3 | tr '\n' ' ')"
  fi
else
  ko "JSON placeholder census is INERT — its own self-test failed (in-scope hit=$json_pos want 1, out-of-scope=$json_neg_scope want 0, *.json.template=$json_neg_ext want 0). A detector that matches nothing also reports 0; do NOT read the count below as a pass."
fi
rm -rf "$JSONFIX"

# 21c-3d. The skill's CONSUMER-SIDE json arm still exists (v2.2.5 round 7).
#
#         Same house rule as 21c-2c: prose alone would drift back. 21c-3c above
#         covers what we SHIP; it is blind to the install-introduced class,
#         because the project bootstrap substitutes and a key the consumer's
#         manifest predates lands as a literal in THEIR file with our template
#         clean. The skill's json arm is the only detector for that, and it is
#         exactly the arm a tidy-up deletes as "redundant with the census".
#         Pinned on `git grep` specifically: a `git ls-files … | xargs grep`
#         rewrite would map both the clean case and a malformed one to xargs'
#         123, collapsing the two states the exit contract exists to separate.
if [ ! -f "$SWEEP_SKILL" ]; then
  ko "$SWEEP_SKILL missing — the consumer-side json arm census cannot run"
elif grep -q "^git grep .* -- '\*\.json'" "$SWEEP_SKILL"; then
  ok "placeholder sweep: the consumer-side json arm is present in $SWEEP_SKILL (git grep, tracked-files scope)"
else
  ko "placeholder sweep: $SWEEP_SKILL has NO runnable json arm — .claude/settings.json is then undetected at the consumer end, which is the only end that sees the install-introduced class (v2.2.0's {{DEFAULT_BRANCH}} chain)"
fi

# 21d. Every shipped shell script PARSES (v2.2.1).
#
#      Not hypothetical: `enforce-delegation.sh`, `read-size-gate.sh` and the
#      other node-program hooks embed their engine as a SINGLE-QUOTED shell
#      argument (`node -e '…'`). One apostrophe in that body — in a comment, in
#      prose, in "the PO's own command" — ends the shell string early, and the
#      whole hook stops working. `bash -n` catches it in one pass; nothing else
#      in this suite would, and on a node-less host the fixtures that noticed it
#      are skipped. Parser-free, so it runs everywhere.
for sf in hooks/*.sh hooks/lib/*.sh "$ULH"/*.sh "$ULH"/lib/*.sh scripts/*.sh; do
  [ -f "$sf" ] || continue
  if bash -n "$sf" 2>/dev/null; then
    ok "$sf parses"
  else
    ko "$sf has a SYNTAX ERROR — run: bash -n $sf (an apostrophe inside a node -e '…' body does this)"
  fi
done

# ---------------------------------------------------------------------------
# 22. The git-tools MCP write ops are denied (v2.1.1, consumer feedback).
#
#     v2.0 moved the git gates onto Bash|PowerShell. The git-tools MCP server is
#     registered at USER level, so it stays reachable in every project — and
#     under "defaultMode": "auto" an MCP git_push to main runs with no hook on
#     it. The deny list is what keeps the gates from being bypassable.
#     Denying a tool the server does not expose is a harmless no-op.
# ---------------------------------------------------------------------------
echo
GIT_MCP_DENY="git_push git_commit git_revert git_merge git_rebase git_reset git_push_tags"
GIT_MCP_DENY_N=7
for v in $VARIANTS; do
  s="templates/$v/.claude/settings.json"
  missing=""
  for t in $GIT_MCP_DENY; do
    grep -q "\"mcp__git-tools__$t\"" "$s" || missing="$missing $t"
  done
  if [ -z "$missing" ]; then
    ok "$s: denies all $GIT_MCP_DENY_N git-tools write ops"
  else
    ko "$s: git-tools deny list missing:$missing"
  fi
  # The deny list is a scalpel, not a ban: the read ops must stay reachable, and
  # the gate's own preflight command must survive every settings.json rewrite.
  if grep -q '"mcp__git-tools__\*"' "$s"; then
    ok "$s: mcp__git-tools__* still allowed (read ops reachable)"
  else
    ko "$s: mcp__git-tools__* missing from allow — the read ops were banned too"
  fi
  if grep -qF '"Bash(bash hooks/run-gate.sh*)"' "$s"; then
    ok "$s: Bash(bash hooks/run-gate.sh*) survives in allow"
  else
    ko "$s: Bash(bash hooks/run-gate.sh*) dropped from allow — the gate needs a prompt"
  fi
done
missing=""
for t in $GIT_MCP_DENY; do
  grep -q "\"mcp__git-tools__$t\"" user-level-reference/settings.json || missing="$missing $t"
done
if [ -z "$missing" ]; then
  ok "user-level-reference/settings.json: denies all $GIT_MCP_DENY_N git-tools write ops"
else
  ko "user-level-reference/settings.json: git-tools deny list missing:$missing"
fi
if grep -q '"mcp__git-tools__\*"' user-level-reference/settings.json; then
  ok "user-level-reference/settings.json: mcp__git-tools__* still allowed"
else
  ko "user-level-reference/settings.json: mcp__git-tools__* missing from allow"
fi

# ---------------------------------------------------------------------------
# 22b. The .env protection is a HOOK, not a deny rule (v3.0.3, queue item 28;
#      supersedes v2.2.0's BUG-6 enumeration, which this check used to assert).
#
#      The six `Read(.env…)` deny rules protected the right files and cost every
#      consumer their auto mode: Claude Code evaluates deny rules BEFORE the
#      classifier, and a read-only command with a RELATIVE path after a `cd`
#      cannot be statically proven not to hit one — so the harness prompted, and
#      auto mode could not approve. Subagents in worktrees do that on nearly
#      every read. The polarity of this check is therefore INVERTED on purpose:
#      the rules must be ABSENT and `hooks/deny-secret-reads.sh` must be
#      registered. Asserting only the absence would be half a check — that state
#      is also what "somebody deleted the protection" looks like.
# ---------------------------------------------------------------------------
echo
ENV_DENY='Read(.env) Read(.env.local) Read(.env.*.local) Read(.env.production) Read(.env.staging) Read(.env.development)'
for s in $(for v in $VARIANTS; do echo "templates/$v/.claude/settings.json"; done) user-level-reference/settings.json; do
  present=""
  for t in $ENV_DENY; do
    grep -qF "\"$t\"" "$s" && present="$present $t"
  done
  if [ -z "$present" ]; then
    ok "$s: no Read(.env…) deny rules (they prompted on every relative-path read)"
  else
    ko "$s: Read(.env…) deny rule(s) back:$present — they cost auto mode; the hook is the replacement"
  fi
  # Any Read() glob has the same static-path problem, so it must not return by
  # another spelling either.
  if grep -qE '"Read\([^"]*\)"' "$s"; then
    ko "$s: a Read(...) deny rule is present — every one of them triggers the static path check"
  else
    ok "$s: no Read(...) deny rule of any spelling"
  fi
  if grep -qF 'hooks/deny-secret-reads.sh' "$s"; then
    ok "$s: registers hooks/deny-secret-reads.sh (the protection that replaced the rules)"
  else
    ko "$s: hooks/deny-secret-reads.sh NOT registered — the .env files are unprotected, not merely un-prompted"
  fi
done
if [ -s hooks/deny-secret-reads.sh ]; then
  ok "hooks/deny-secret-reads.sh exists at the repo root"
else
  ko "hooks/deny-secret-reads.sh missing/empty — every settings.json above references a hook that is not there"
fi

# ---------------------------------------------------------------------------
# 23. SubagentStop matchers cover project-added language coders (v2.1.1).
#
#     An enumerated matcher ("^(coder|code-reviewer|tester|architect)$") reverts
#     a project's own `cpp-coder` wiring on every accept-template. The regex
#     below owns the shape instead of the list, so the template never has to
#     know a project's coder names.
# ---------------------------------------------------------------------------
echo
CODER_RE='"matcher": "^([a-z0-9]+-)?coder$'
for v in $VARIANTS; do
  s="templates/$v/.claude/settings.json"
  n=$(grep -cF "$CODER_RE" "$s")
  if [ "$n" -eq 2 ]; then
    ok "$s: both SubagentStop matchers accept <lang>-coder"
  else
    ko "$s: expected 2 <lang>-coder-shaped SubagentStop matchers, found $n"
  fi
  if grep -q '"matcher": "coder|dotnet-coder' "$s"; then
    ko "$s: still carries the enumerated coder matcher"
  else
    ok "$s: no enumerated coder matcher left"
  fi
done
if grep -q 'coder|\*-coder)' hooks/require-skills-block.sh; then
  ok "hooks/require-skills-block.sh: binds any <lang>-coder, not an enumeration"
else
  ko "hooks/require-skills-block.sh: coder binding is still an enumeration"
fi

# ---------------------------------------------------------------------------
# 24. Hook commands are cwd-independent (v2.1.2, consumer report #3).
#
#     `bash hooks/x.sh` resolves against the SHELL's cwd, not the project root.
#     A `cd` inside any earlier Bash call persists for the rest of the session,
#     so every later hook exits 127 and the 127-wrapper reports HOOK SCRIPT
#     MISSING for a file that is right there. The documented fix is the
#     `$CLAUDE_PROJECT_DIR` placeholder, which command hooks always get. It is
#     spelled `${CLAUDE_PROJECT_DIR:-.}` so a host that does not export the
#     variable degrades to the old cwd-relative behaviour rather than hard-
#     blocking every tool call on a 127.
#     NB: the permissions entry "Bash(bash hooks/run-gate.sh*)" is a prompt
#     pattern, not a hook command, and must survive — hence the command:-anchor.
# ---------------------------------------------------------------------------
echo
relhook=$(
  {
    grep -h '"command": "bash hooks/' templates/*/.claude/settings.json 2>/dev/null
    grep -h 'command: "bash hooks/' templates/*/.claude/agents/*.md 2>/dev/null
  } | grep -c .
)
if [ "$relhook" -eq 0 ]; then
  ok "no hook command uses the cwd-relative 'bash hooks/' form"
else
  ko "$relhook hook command(s) still cwd-relative ('bash hooks/...') — they 127 after any cd"
  grep -n '"command": "bash hooks/' templates/*/.claude/settings.json 2>/dev/null
  grep -n 'command: "bash hooks/' templates/*/.claude/agents/*.md 2>/dev/null
fi
ABS_FORM='bash \"${CLAUDE_PROJECT_DIR:-.}/hooks/'
abshook=$(
  {
    grep -hF "$ABS_FORM" templates/*/.claude/settings.json 2>/dev/null
    grep -hF "$ABS_FORM" templates/*/.claude/agents/*.md 2>/dev/null
  } | grep -c .
)
#     `abshook > 0` alone is a coverage hole: a subset reverted to the
#     intermediate no-fallback form `bash "$CLAUDE_PROJECT_DIR/hooks/` is neither
#     cwd-relative nor fallback-safe, so relhook and abshook would both still be
#     happy. Reject that form by name, and require abshook to equal the TOTAL
#     number of hook command lines that name a hooks/ script — derived from the
#     same two greps check 13 uses, so the two cannot drift apart.
NOFALLBACK_FORM='bash \"$CLAUDE_PROJECT_DIR/hooks/'
nofallback=$(
  {
    grep -hF "$NOFALLBACK_FORM" templates/*/.claude/settings.json 2>/dev/null
    grep -hF "$NOFALLBACK_FORM" templates/*/.claude/agents/*.md 2>/dev/null
  } | grep -c .
)
if [ "$nofallback" -eq 0 ]; then
  ok "no hook command uses the no-fallback \$CLAUDE_PROJECT_DIR form"
else
  ko "$nofallback hook command(s) use \$CLAUDE_PROJECT_DIR without the :-. default — they hard-block if the host does not export it"
  grep -nF "$NOFALLBACK_FORM" templates/*/.claude/settings.json 2>/dev/null
  grep -nF "$NOFALLBACK_FORM" templates/*/.claude/agents/*.md 2>/dev/null
fi
hookcmd_total=$(
  {
    grep -h '"command":' templates/*/.claude/settings.json 2>/dev/null
    grep -h 'command:' templates/*/.claude/agents/*.md 2>/dev/null
  } | grep -c 'hooks/'
)
if [ "$hookcmd_total" -eq 0 ]; then
  ko "hook command census matched NO lines (glob or grep broken?) — passing vacuously"
elif [ "$abshook" -eq "$hookcmd_total" ]; then
  ok "all $hookcmd_total hook command(s) use the \${CLAUDE_PROJECT_DIR:-.} form"
else
  ko "only $abshook of $hookcmd_total hook command(s) use \${CLAUDE_PROJECT_DIR:-.} — $((hookcmd_total - abshook)) in some other form"
fi

# ---------------------------------------------------------------------------
# 25. PROJECT-CUSTOM region in agent definitions and AGENT_TEAM.md (v2.1.2,
#     consumer report #5). Mature downstreams accumulate hard-won lines in
#     their agent files; accept-template deleted them because only CLAUDE.md
#     carried the markers. The server's region split is file-agnostic, so
#     shipping the marker pair is the whole fix.
# ---------------------------------------------------------------------------
echo
region_files=$(ls templates/*/.claude/agents/*.md templates/*/AGENT_TEAM.md 2>/dev/null)
region_total=$(printf '%s\n' "$region_files" | grep -c .)
region_missing=""
for f in $region_files; do
  if [ "$(tail -n 1 "$f")" = "<!-- PROJECT-CUSTOM:END -->" ] \
     && grep -qF "<!-- PROJECT-CUSTOM:BEGIN" "$f"; then
    :
  else
    region_missing="$region_missing $f"
  fi
done
if [ "$region_total" -eq 0 ]; then
  ko "PROJECT-CUSTOM region check matched NO files (glob broken?) — passing vacuously"
elif [ -z "$region_missing" ]; then
  ok "all $region_total template agent files + AGENT_TEAM.md end with a PROJECT-CUSTOM region"
else
  ko "PROJECT-CUSTOM region missing/not-last in:$region_missing"
fi

# ---------------------------------------------------------------------------
# 26. templates/*/CLAUDE.md context-mode sentinel (v2.1.3 fix round 2, derived
#     over variants). The line immediately ABOVE `PROJECT-CUSTOM:BEGIN` in
#     every variant CLAUDE.md must name `context-mode`, so a consumer syncing
#     the region sees where a plugin routing block belongs before it re-lands
#     inside the preserved region.
# ---------------------------------------------------------------------------
echo
sentinel_missing=""
for v in $VARIANTS; do
  f="templates/$v/CLAUDE.md"
  [ -f "$f" ] || { sentinel_missing="$sentinel_missing $f(missing)"; continue; }
  line=$(grep -n -F '<!-- PROJECT-CUSTOM:BEGIN' "$f" | head -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    sentinel_missing="$sentinel_missing $f(no-marker)"
    continue
  fi
  prev=$((line - 1))
  prevline=$(sed -n "${prev}p" "$f")
  case "$prevline" in
    *context-mode*) : ;;
    *) sentinel_missing="$sentinel_missing $f(line-$prev)" ;;
  esac
done
if [ -z "$sentinel_missing" ]; then
  ok "all $(printf '%s\n' "$VARIANTS" | wc -w) variant CLAUDE.md files carry the context-mode sentinel line above PROJECT-CUSTOM:BEGIN"
else
  ko "CLAUDE.md context-mode sentinel missing/wrong line in:$sentinel_missing"
fi

# ---------------------------------------------------------------------------
# 26b. The WORKTREE_BASE default is ignored by every variant (v2.2.6).
#
#      `{{WORKTREE_BASE}}` used to default to empty, so only a consumer who
#      passed --worktree-base under `.claude/` was exposed. Giving it a default
#      makes the gap universal: every bootstrapped repo places agent worktrees
#      there, `coder`/`tester` both run `isolation: worktree`, and
#      a full repo checkout then shows as untracked files that `git add -A`
#      would stage. This repo cannot reproduce it — its own .gitignore
#      blanket-ignores `/.claude/`, while the SHIPPED gitignore is deliberately
#      selective (settings.json and agents/ stay tracked). So the defect is
#      invisible in the one place it would be noticed, and is asserted here.
#
#      ONE authoritative value: setup-project.sh. The .ps1 default and all six
#      gitignores are checked AGAINST it rather than against a second copy of
#      the literal — three independent copies is how they drift apart. If the
#      value cannot be determined the check REFUSES; an empty needle would make
#      every arm below vacuously green.
# ---------------------------------------------------------------------------
echo
wtb=$(grep -E '^WORKTREE_BASE="' setup-project.sh 2>/dev/null | head -1 | sed 's/^WORKTREE_BASE="//; s/".*$//')
case "$wtb" in
  ''|*'{{'*)
    ko "WORKTREE_BASE default: cannot determine it from setup-project.sh (got '$wtb') — every arm below would pass vacuously"
    ;;
  *)
    ok "WORKTREE_BASE default: setup-project.sh is authoritative at '$wtb'"

    wtb_ps_want="[string]\$WorktreeBase = \"$wtb\""
    if grep -qF -- "$wtb_ps_want" setup-project.ps1 2>/dev/null; then
      ok "WORKTREE_BASE default: setup-project.ps1 agrees ($wtb_ps_want)"
    else
      ko "WORKTREE_BASE default: setup-project.ps1 does not carry '$wtb_ps_want' — the two bootstrappers place worktrees differently"
    fi

    # docs/templates.md states the default in prose. A stated default that
    # drifts is worse than no statement, so it is checked from the same value.
    if grep -qF -- "defaults to \`$wtb\`" docs/templates.md 2>/dev/null; then
      ok "WORKTREE_BASE default: docs/templates.md states '$wtb'"
    else
      ko "WORKTREE_BASE default: docs/templates.md does not state 'defaults to \`$wtb\`'"
    fi

    for v in general dotnet dotnet-maui rust-tauri java python; do
      # Exact line: a substring match is satisfied by the `.claude/` comment
      # header already at the top of every one of these files.
      if grep -qxF -- "$wtb/" "templates/$v/gitignore" 2>/dev/null; then
        ok "templates/$v/gitignore: ignores $wtb/"
      else
        ko "templates/$v/gitignore: missing '$wtb/' — the default worktree base would show as untracked files"
      fi
    done
    ;;
esac

# 27. The bootstrap fixtures (v2.2.1).
#
#     scripts/test-setup-project.sh runs setup-project.{sh,ps1} in BOTH modes
#     and asserts the dry run and the real run agree. It is invoked from here,
#     not left as a third gate command, so that the documented gate
#     (verify-template-consistency.sh + test-hooks.sh) executes it without any
#     consumer, doc, routine or CI wiring having to learn a new name — a test
#     nothing runs is worth exactly as much as the comment it replaced.
#
#     Folded in as ONE assertion; its own per-case output is printed above the
#     verdict so a failure is diagnosable from this script's log alone.
# ---------------------------------------------------------------------------
echo
if [ -f scripts/test-setup-project.sh ]; then
  setup_out=$(bash scripts/test-setup-project.sh 2>&1)
  if [ $? -eq 0 ]; then
    ok "bootstrap fixtures: $(printf '%s' "$setup_out" | grep -E '^test-setup-project' | head -1)"
  else
    printf '%s\n' "$setup_out" | sed 's/^/    /'
    ko "bootstrap fixtures FAILED — run: bash scripts/test-setup-project.sh"
  fi
else
  ko "scripts/test-setup-project.sh missing — the dry-run/real-run divergence is unguarded"
fi

# ---------------------------------------------------------------------------
# 28. The PROJECT-CUSTOM region EXTRACTOR ships, and answers both arms (v2.4.0,
#     item A1).
#
#     Step 4's accept-template disqualifier and step 6's deletion precondition
#     both turn on "is this file's region empty?", and TWO independent
#     consumers implemented that from prose and both got the REASSURING answer
#     wrongly: `PROJECT-CUSTOM:BEGIN\s*-->` matches nothing (the shipped marker
#     carries trailing prose), and a language-level `glob('**/*.md')` does not
#     descend into dot-directories, so it skips all of `.claude/`. One measured
#     "zero regions" across a repo with ELEVEN, at which point accept-template
#     or `git rm` destroys the region with the disqualifier cleared.
#
#     So the extractor is SHIPPED CODE, not a paragraph, and this is its
#     control. BOTH ARMS ARE REQUIRED and neither is decorative:
#       * a planted region WITH CONTENT, inside a dot-directory, must be found
#         and reported CONTENT — this arm goes red if the regex is narrowed to
#         the naive `\s*-->` form, or if the walk stops at dot-directories;
#       * a placeholder-only region must NOT be reported as content — this arm
#         goes red if the extractor is widened to "any body is content", which
#         would make the guard fire on all eleven shipped files and be turned
#         off within a release.
#     Deleting region.sh turns the whole check red.
#
#     VALIDATED AGAINST PLANTED CONTENT, NEVER FOUND CONTENT: a census across
#     three consumer repos found ZERO real region content (11, 10 and 1
#     region-bearing files, all placeholder-only). A green run on found content
#     proves nothing, because the guard cannot fail there.
# ---------------------------------------------------------------------------
echo
REGION_SH="user-level-reference/skills/sync-template/region.sh"
if [ ! -f "$REGION_SH" ]; then
  ko "$REGION_SH missing — step 4's disqualifier and step 6's precondition have no extractor, and prose is what both consumers got wrong"
elif ! bash -n "$REGION_SH" 2>/dev/null; then
  ko "$REGION_SH does not parse"
else
  ok "$REGION_SH: present and parses"

  r28=$(mktemp -d)
  mkdir -p "$r28/.claude/agents"
  {
    printf '# planted\n'
    printf '<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->\n'
    printf 'REGION-SENTINEL-CONTENT: project routing that must survive.\n'
    printf '<!-- PROJECT-CUSTOM:END -->\n'
  } > "$r28/.claude/agents/planted.md"
  {
    printf '# placeholder\n'
    printf '<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->\n'
    printf '<!-- Project-specific rules, routing blocks, and extensions go here. -->\n'
    printf '<!-- PROJECT-CUSTOM:END -->\n'
  } > "$r28/.claude/agents/placeholder.md"
  printf '# plain\n' > "$r28/.claude/agents/plain.md"

  # Arm 1 (positive): content in a DOT-DIRECTORY is found and named CONTENT.
  r28_scan=$(bash "$REGION_SH" --scan "$r28" 2>/dev/null)
  if printf '%s\n' "$r28_scan" | grep -q "^CONTENT	.*\.claude/agents/planted\.md$"; then
    ok "region extractor: planted content inside a dot-directory is found (CONTENT)"
  else
    note "scan output was: $(printf '%s' "$r28_scan" | tr '\n' '|')"
    ko "region extractor: planted content inside .claude/ NOT reported as CONTENT — the false clean that destroys regions"
  fi

  # Arm 2 (negative): the shipped placeholder is NOT content.
  if printf '%s\n' "$r28_scan" | grep -q "^EMPTY	.*placeholder\.md$"; then
    ok "region extractor: a placeholder-only region is EMPTY, not content"
  else
    ko "region extractor: placeholder-only region misreported — a guard that fires on all eleven shipped files gets switched off"
  fi

  # Arm 3: a file with no markers is neither of the above.
  if printf '%s\n' "$r28_scan" | grep -q "plain\.md"; then
    ko "region extractor: a marker-less file appeared in --scan output"
  else
    ok "region extractor: a marker-less file is not enumerated"
  fi

  # Arm 4: --body is byte-exact. Step 6's post-relocate byte-compare is what
  # makes "the content is provably elsewhere" mechanical rather than asserted,
  # and it is only as good as this.
  r28_body=$(bash "$REGION_SH" --body "$r28/.claude/agents/planted.md" 2>/dev/null)
  if [ "$r28_body" = "REGION-SENTINEL-CONTENT: project routing that must survive." ]; then
    ok "region extractor: --body returns the region verbatim"
  else
    note "--body returned: [$r28_body]"
    ko "region extractor: --body did not return the region verbatim — the post-relocate byte-compare cannot work"
  fi

  # Arm 5: the SHIPPED files. Every agent file in templates/general carries a
  # region (check 25 asserts that separately); the extractor must SEE all of
  # them through the dot-directory, which is the exact walk that returned zero.
  r28_agents=$(ls templates/general/.claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
  r28_seen=$(bash "$REGION_SH" --scan templates/general/.claude/agents 2>/dev/null | wc -l | tr -d ' ')
  if [ "$r28_agents" = "$r28_seen" ] && [ "$r28_agents" != "0" ]; then
    ok "region extractor: all $r28_agents shipped agent regions are enumerated"
  else
    ko "region extractor: $r28_seen of $r28_agents shipped agent regions enumerated — the 'zero regions across eleven' reading"
  fi

  # Arm 6: MATCH THE MARKER'S SHAPE, NOT ITS NAME — six rows, asserted BY
  # CLASSIFICATION STRING (v3.0.0).
  #
  # v2.4.0's matcher was a bare substring while this file's documented
  # specification anchors on the comment opener, so PROSE ABOUT THE MARKERS
  # matched. Both false shapes were measured on live consumer repos, and they
  # fail in OPPOSITE directions:
  #
  #   row 1 (BEGIN named in prose)  -> was UNCLOSED : DEADLOCK. Step 6a offers
  #         only "relocate the region" or "defer" for CONTENT/UNCLOSED, and a
  #         false positive has NO region to relocate, so the prescribed remedy
  #         is unreachable — and A2 is built so no acknowledgement overrides it.
  #   row 2 (BOTH named in prose)   -> was EMPTY    : THE DANGEROUS ONE. Step 6a
  #         reaches the ORDINARY deletion flow for EMPTY, so a documentation
  #         file sails through the precondition into the delete prompt. A2's
  #         premise is that the prompt never SHOWED what was being destroyed;
  #         here the guard affirmatively CERTIFIES the file as empty. `--body`
  #         shares it, so 6a's post-relocate byte-compare compares two empty
  #         bodies, they match, and the mechanical proof passes for a
  #         relocation that never happened.
  #
  # ROWS 1, 2 AND 6 MUST ALL LAND ON NOMARKERS, and rows 1 and 5 must be
  # DISTINGUISHABLE — a documentation file and a genuinely broken region printed
  # the same verdict, so an operator could not tell them apart without opening
  # the file.
  #
  # RESIDUAL, STATED RATHER THAN HIDDEN: a file that quotes the FULL marker
  # comment verbatim (`<!-- PROJECT-CUSTOM:BEGIN ... -->`) is still classified as
  # carrying a marker, and by construction must be — it contains bytes
  # indistinguishable from a real marker. That fails toward PRESERVATION, which
  # is the safe direction, and it is why no `^` line-anchor was added: a
  # blockquoted or list-indented real marker would then be MISSED, and a missed
  # region is the destructive reading.
  r28b=$(mktemp -d)
  printf 'The region sits between `PROJECT-CUSTOM:BEGIN` markers.\n' > "$r28b/r1.md"
  printf 'It sits between `PROJECT-CUSTOM:BEGIN` and `PROJECT-CUSTOM:END` markers.\n' > "$r28b/r2.md"
  printf '<!-- PROJECT-CUSTOM:BEGIN — x -->\nreal content\n<!-- PROJECT-CUSTOM:END -->\n' > "$r28b/r3.md"
  printf '<!-- PROJECT-CUSTOM:BEGIN — x -->\n<!-- Project-specific rules, routing blocks, and extensions go here. -->\n<!-- PROJECT-CUSTOM:END -->\n' > "$r28b/r4.md"
  printf '<!-- PROJECT-CUSTOM:BEGIN — x -->\nreal content, no end marker\n' > "$r28b/r5.md"
  printf 'nothing to see here\n' > "$r28b/r6.md"
  # Row 7: REVERSED-ORDER PROSE — the END marker named BEFORE the BEGIN marker.
  # Taken from a real consumer file (`PROJECT_STATE.md:276-277`), where it
  # classified EMPTY with a 0-byte body under the v2.4.0 substring matcher.
  # It is here because A NAIVE REPAIR WOULD STILL GET IT WRONG: "find BEGIN,
  # then find END" reads correctly and fails this row. The shape matcher is
  # order-independent — neither prose mention carries the `<!--` opener, so
  # neither is a marker at all — and this row is what stops a future
  # order-based rewrite from regressing it silently.
  printf 'Status notes.\n\nThe `PROJECT-CUSTOM:END` marker closes what `PROJECT-CUSTOM:BEGIN` opens.\n' > "$r28b/r7.md"
  r28b_bad=""
  r28b_row() { # <file> <expected>
    r28br=$(bash "$REGION_SH" "$r28b/$1" 2>/dev/null | cut -f1)
    [ "$r28br" = "$2" ] || r28b_bad="$r28b_bad $1(got=$r28br want=$2)"
  }
  r28b_row r1.md NOMARKERS
  r28b_row r2.md NOMARKERS
  r28b_row r3.md CONTENT
  r28b_row r4.md EMPTY
  r28b_row r5.md UNCLOSED
  r28b_row r6.md NOMARKERS
  r28b_row r7.md NOMARKERS
  if [ -z "$r28b_bad" ]; then
    ok "region extractor: all seven marker-shape rows classify correctly (prose about the markers is NOMARKERS — in either order — not EMPTY and not UNCLOSED)"
  else
    ko "region extractor: marker-shape row(s) misclassified —$r28b_bad. EMPTY on prose UNLOCKS the delete path; UNCLOSED on prose DEADLOCKS step 6a with no region to relocate."
  fi

  # Arm 6b: --body must share the classifier's matcher. Two matchers is how the
  # scan path and the body path came to disagree with the spec in DIFFERENT
  # ways, and 6a's byte-compare rides on --body.
  if [ -z "$(bash "$REGION_SH" --body "$r28b/r2.md" 2>/dev/null)" ] &&
     [ "$(bash "$REGION_SH" --body "$r28b/r3.md" 2>/dev/null)" = "real content" ]; then
    ok "region extractor: --body and the classifier share one matcher (prose yields nothing, a real region yields its body)"
  else
    ko "region extractor: --body disagrees with the classifier — 6a's post-relocate byte-compare inherits the disagreement"
  fi

  # Arm 6c: --scan must PRUNE vendor/build trees. Measured: 40,445 files on a
  # node repo (killed after two minutes) and 10,246 of 10,524 in `.venv` on a
  # python repo (~15 minutes). SKILL.md documents --scan as THE enumeration and
  # warns against hand-rolling a walker, so a scan that appears to hang leaves a
  # consumer with no sanctioned alternative — and the hand-rolled walker is the
  # failure this file exists to prevent. Pruned by DIRECTORY NAME, never by
  # git's tracked-file list: `git ls-files` would skip untracked files, and the
  # untracked hand-authored agent is exactly what A3 protects.
  mkdir -p "$r28b/tree/node_modules/deep" "$r28b/tree/.venv/lib" "$r28b/tree/.claude"
  i=0; while [ "$i" -lt 40 ]; do echo x > "$r28b/tree/node_modules/deep/f$i"; i=$((i+1)); done
  i=0; while [ "$i" -lt 40 ]; do echo x > "$r28b/tree/.venv/lib/f$i"; i=$((i+1)); done
  cp "$r28b/r3.md" "$r28b/tree/.claude/agent.md"
  r28b_scanned=$(bash "$REGION_SH" --scan "$r28b/tree" 2>&1 >/dev/null | sed -n 's/.*scanned \([0-9]*\) files under.*/\1/p')
  r28b_found=$(bash "$REGION_SH" --scan "$r28b/tree" 2>/dev/null | grep -c '^CONTENT')
  if [ "${r28b_scanned:-0}" -le 5 ] && [ "$r28b_found" = "1" ]; then
    ok "region extractor: --scan prunes vendor/build trees (visited ${r28b_scanned:-?} of 81 files) and still finds the region in .claude/"
  else
    ko "region extractor: --scan visited ${r28b_scanned:-?} files of 81 and found $r28b_found region(s) — either the prune list is gone (the only sanctioned enumeration is unusable on a real tree) or it pruned the dot-directory it exists to walk"
  fi
  rm -rf "$r28b"

  rm -rf "$r28"

  # Arm 5b: THE REAL PLANTED FIXTURE. Arms 1–4 use a one-line synthetic region,
  # which is enough to catch the naive regex and the dot-directory walk but NOT
  # enough to catch a TRUNCATING preserve — a 40-byte region and a 900-byte one
  # are not equally good at that. scripts/fixtures/project-custom-regions/
  # holds three regions of real consumer project knowledge (767 B, 965 B,
  # 929 B), the only known source of real region content anywhere: a census of
  # three consumer repos found ZERO, so a guard validated on found content
  # cannot fail and proves nothing.
  #
  # Planted into a COPY of templates/general, against the shipped placeholder
  # block, with both marker lines left verbatim — the BEGIN marker's em-dash
  # and trailing prose are exactly what a naive `BEGIN\s*-->` extractor chokes
  # on, so normalising them would destroy the property under test.
  r28f="scripts/fixtures/project-custom-regions"
  if [ ! -f "$r28f/plant.sh" ]; then
    ko "$r28f/plant.sh missing — the region guards have no planted fixture, and found content cannot fail them"
  else
    r28p=$(mktemp -d)
    cp -r templates/general/. "$r28p/" 2>/dev/null
    if bash "$r28f/plant.sh" "$r28p" >/dev/null 2>&1; then
      r28pscan=$(bash "$REGION_SH" --scan "$r28p" 2>/dev/null)
      r28pc=$(printf '%s\n' "$r28pscan" | grep -c '^CONTENT	')
      if [ "$r28pc" = "3" ]; then
        ok "region extractor: all 3 planted real regions are reported CONTENT"
      else
        ko "region extractor: $r28pc of 3 planted real regions reported CONTENT — the false clean that destroys regions"
      fi
      # The other eight regions in the same tree are still placeholder-only and
      # must stay EMPTY. A guard that fires on all eleven gets switched off.
      r28pe=$(printf '%s\n' "$r28pscan" | grep -c '^EMPTY	')
      if [ "$r28pe" -ge 1 ]; then
        ok "region extractor: $r28pe untouched regions in the same tree remain EMPTY"
      else
        ko "region extractor: planting turned every region in the tree into CONTENT"
      fi
      # TRUNCATING-PRESERVE ARM: --body must return the planted region BYTE FOR
      # BYTE. This is the arm the one-line synthetic fixture cannot provide.
      if bash "$REGION_SH" --body "$r28p/.claude/agents/coder.md" 2>/dev/null \
           | cmp -s - "$r28f/coder.md.region"; then
        ok "region extractor: --body returns the $(wc -c < "$r28f/coder.md.region" | tr -d ' ') B planted region byte-for-byte"
      else
        ko "region extractor: --body did not round-trip the planted region byte-for-byte — a truncating preserve would go unnoticed"
      fi
    else
      ko "$r28f/plant.sh failed against a copy of templates/general — the placeholder block it keys on has changed"
    fi
    rm -rf "$r28p"
  fi

  # Arm 6: the extractor must be WIRED INTO the instructions. An extractor no
  # step names is prose with extra steps — the failure A1 exists to prevent.
  if grep -q 'region\.sh' user-level-reference/skills/sync-template/SKILL.md; then
    ok "sync-template SKILL.md: references region.sh"
  else
    ko "sync-template SKILL.md: never names region.sh — the extractor ships but no step uses it"
  fi
fi

# ---------------------------------------------------------------------------
# 29. "Deliberately exempt" must be distinguishable from "silently fell out"
#     (v2.4.0, item A5).
#
#     In hooks/require-skills-block.sh the exempt arm and the `*)` default arm
#     are BYTE-IDENTICAL IN EFFECT — both `exit 0`. An agent exempted on
#     purpose and an agent whose name silently fell out of the enumeration
#     produce the same result, with no signal at runtime or afterwards. That is
#     precisely why a consumer could not tell whether their own `game-tester`
#     was unbound deliberately.
#
#     THE RUNTIME FIX IS UNAVAILABLE. Making `*)` warn before exiting 0 sends
#     the warning down a channel measured, earlier in this programme, not to
#     reach the lead. A warning nobody receives is the same silence with more
#     code, and it reads as fixed. So the check is STATIC and lives here, where
#     output demonstrably reaches someone, and it fires at BUILD time — which
#     is also what makes it catch a consolidation's own damage: delete or
#     rename an agent without updating the case arm and the gate is red before
#     the release ships, rather than silent after.
#
#     ⚠ EVALUATE EACH PATTERN IN ITS OWN LANGUAGE. NEVER STRING-COMPARE ARM
#     LABELS TO FILENAMES. `coder|*-coder)` is a GLOB, not a name:
#     `dotnet-coder`, `java-coder`, `python-coder` and `rust-coder` all ship as
#     agent files and appear NOWHERE as literals in any arm — they are covered
#     only by the glob. A set-equality check against the labels goes red on day
#     one against the exact generalisation that makes the hook correct. The
#     same trap sits in the settings.json matcher `^([a-z0-9]+-)?coder$`. Arm C
#     below asserts that trap is not re-entered.
#
#     SCOPED TO THE TOOLKIT'S OWN SHIPPED AGENT SET, deliberately. A consumer's
#     project-owned agent must remain legitimately unbound with no gate failure
#     in THEIR repo — a gate that goes red on a consumer's own file is the
#     cries-wolf failure this release exists to reduce.
# ---------------------------------------------------------------------------
echo
A5_HOOK="hooks/require-skills-block.sh"
if [ ! -f "$A5_HOOK" ]; then
  ko "$A5_HOOK missing — the skills binding is unenumerated"
else
  # Arm labels, taken from the case statement and used AS PATTERNS. `*)` is
  # excluded on purpose: it matches everything, so including it would make this
  # whole check vacuously true — which is the failure it exists to detect.
  a5_arms=$(sed -n '/case "\$SUBAGENT_TYPE" in/,/^esac$/p' "$A5_HOOK" \
    | grep -E '^[[:space:]]+[A-Za-z0-9_|*?.-]+\)[[:space:]]*$' \
    | sed 's/^[[:space:]]*//;s/)[[:space:]]*$//' \
    | grep -vx '\*')

  if [ -z "$a5_arms" ]; then
    ko "check 29: no case arms parsed out of $A5_HOOK — the check would pass vacuously, so it fails instead"
  else
    ok "check 29: parsed $(printf '%s\n' "$a5_arms" | wc -l | tr -d ' ') case arms from $A5_HOOK"

    # a5_matches <name> -- does any arm match, EVALUATED AS A SHELL GLOB?
    #
    # THE `|` MUST BE SPLIT BEFORE THE `case`, and this is not a nicety: in a
    # case arm `|` is SYNTAX, not data, so `case $n in $arm)` with
    # $arm='coder|*-coder' tests the single literal pattern "coder|*-coder" and
    # matches nothing. The first version of this check did exactly that and
    # reported all nine shipped names unbound — a check failing loudly, which
    # is the good direction, but it is the same "evaluate the pattern in its
    # own language" trap the check exists to enforce, sprung on the check
    # itself. Split on `|`, then glob each alternative.
    a5_matches() {
      a5m_name="$1"
      while IFS= read -r a5m_arm; do
        [ -n "$a5m_arm" ] || continue
        a5m_old_ifs=$IFS
        IFS='|'
        for a5m_alt in $a5m_arm; do
          IFS=$a5m_old_ifs
          [ -n "$a5m_alt" ] || continue
          case "$a5m_name" in
            $a5m_alt) return 0 ;;
          esac
          IFS='|'
        done
        IFS=$a5m_old_ifs
      done <<A5_ARMS
$a5_arms
A5_ARMS
      return 1
    }

    # The shipped agent set: every variant plus the user-level reference copies.
    a5_names=$( { ls templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null; } \
      | sed 's@.*/@@;s@\.md$@@' | sort -u )
    a5_unmatched=""
    for a5n in $a5_names; do
      a5_matches "$a5n" || a5_unmatched="$a5_unmatched $a5n"
    done
    if [ -z "$a5_unmatched" ]; then
      ok "check 29 (arm A): every shipped agent name matches a case arm or the explicit exempt list ($(printf '%s\n' $a5_names | wc -l | tr -d ' ') names)"
    else
      ko "check 29 (arm A): shipped agent(s) match NO case arm —$a5_unmatched. Either bind them in $A5_HOOK or add them to the explicit exempt arm; falling through to \`*)\` is indistinguishable from having silently fallen out."
    fi

    # Arm B (NEGATIVE SELF-TEST): a name the toolkit does not ship must NOT
    # match. Without this, an arm-parsing bug that yielded `*` — or a
    # `a5_matches` that always returned 0 — would make arm A green for the
    # wrong reason. A check that cannot report a miss has not reported a hit.
    if a5_matches "zz-unbound-probe"; then
      ko "check 29 (arm B): the synthetic name 'zz-unbound-probe' matched an arm — the arm set is over-broad and arm A is passing vacuously"
    else
      ok "check 29 (arm B): a non-shipped name correctly matches no arm"
    fi

    # Arm C: THE TWO-PATTERN-LANGUAGES INVARIANT. The same intent is written as
    # a shell glob in the hook (`coder|*-coder`) and as a regex in
    # settings.json (`^([a-z0-9]+-)?coder$`), and both generalise over the whole
    # <lang>-coder family. A fix applied to one is NOT applied to the other by
    # any grep keyed on a single syntax, so consolidating or renaming `coder`
    # breaks every variant coder in both places at once — silently, because
    # both forms fail OPEN when a name stops matching. Rather than a
    # hand-maintained expected set (which drifts), assert the two languages
    # agree on the shipped names.
    a5_regex=$(grep -o '"matcher": "[^"]*coder[^"]*"' templates/general/.claude/settings.json \
      | sed 's/.*"matcher": "//;s/"$//' | head -1)
    if [ -z "$a5_regex" ]; then
      ko "check 29 (arm C): no agent matcher regex found in templates/general/.claude/settings.json"
    else
      # ONE DIRECTION ONLY, and the asymmetry is deliberate. The matcher is
      # legitimately BROADER than the coder family — it also names
      # `code-reviewer`, `tester`, `architect` — so equality is the wrong
      # relation and the first version of this arm went red on all three of
      # them for saying so. The property that actually breaks under a
      # consolidation is the COVERAGE one: every name the hook's coder glob
      # binds must also be reached by the settings matcher. A `<lang>-coder`
      # added to one language and not the other is silently unhooked, and both
      # forms fail OPEN, so nothing else reports it.
      a5_disagree=""
      for a5n in $a5_names; do
        case "$a5n" in
          coder|*-coder)
            printf '%s\n' "$a5n" | grep -qE "$a5_regex" \
              || a5_disagree="$a5_disagree $a5n"
            ;;
        esac
      done
      if [ -z "$a5_disagree" ]; then
        ok "check 29 (arm C): every name the hook's coder glob binds is also reached by the settings.json matcher"
      else
        ko "check 29 (arm C): bound by the shell glob but NOT by the settings.json matcher —$a5_disagree. The two pattern languages have drifted; both fail OPEN and silently."
      fi

      # Arm D: the trap itself. The domain coders must be covered BY THE GLOB
      # while existing as no literal in any arm. If someone "fixes" check 29 by
      # enumerating them, this arm says so — the enumeration is exactly what
      # silently unbinds the next variant coder a project adds.
      a5_literal=""
      for a5n in $a5_names; do
        case "$a5n" in
          *-coder)
            if printf '%s\n' "$a5_arms" | grep -qx "$a5n"; then a5_literal="$a5_literal $a5n"; fi
            ;;
        esac
      done
      if [ -z "$a5_literal" ]; then
        ok "check 29 (arm D): domain coders are covered by the glob, not enumerated as literals"
      else
        ko "check 29 (arm D): domain coder(s) enumerated as literal arms —$a5_literal. The glob exists so a project's own <lang>-coder is bound too; enumerating defeats it."
      fi

      # Arm E: EXISTENCE PROVES NOTHING — MATCHING IS THE PROPERTY (v3.0.0,
      # item B2).
      #
      # A control that asserts an agent FILE exists does not detect the failure
      # a consolidation can cause. The dangerous case is a RENAME breaking the
      # skills `case` arm, `enforce-agent-contract.sh`'s SubagentStop matcher
      # and both `settings.json` matcher regexes AT THE SAME SILENT MOMENT:
      # nothing errors, every file is present, and the enforcement layer is
      # simply gone. Arms A-D cover the shell-glob language and the coder
      # family; this arm covers the OTHER pattern language — the regexes — for
      # every name the enforcement layer names, and it evaluates them AS
      # REGEXES rather than comparing label text.
      #
      # This is why v3.0.0 ABSORBS rather than renames: the survivors keep the
      # names these three patterns already match, so the patterns are untouched.
      # Arm E is what turns that from a stated intention into a checked one.
      #
      # ⚠ THE EXPECTATIONS BELOW ARE FIXED, AND THE MATCHERS ARE KEYED BY THE
      # HOOK THEY RUN, NEVER BY THEIR OWN TEXT. The first version of this arm
      # selected matchers by grepping them for the very names it then tested,
      # so deleting `^tester$` from a matcher made the arm skip that matcher and
      # report green — a check keyed on the thing under test. It was caught by
      # deleting the guard (drop `^tester$`; the arm did not flip, and only the
      # cross-variant byte-identity check noticed, which would NOT have noticed
      # had all six variants been edited together). Keyed on the command, the
      # matcher cannot hide by changing.
      a5_pairs=$(awk '
        /"matcher":/ { m=$0; sub(/.*"matcher": "/,"",m); sub(/",?[[:space:]]*$/,"",m); next }
        /"command":/ { c=$0; sub(/.*"command": "/,"",c); sub(/",?[[:space:]]*$/,"",c);
                       if (m != "") print m "\t" c }
      ' templates/general/.claude/settings.json)
      a5_pipeline=$(printf '%s\n' "$a5_pairs" | grep -F 'PIPELINE:' | head -1 | cut -f1)
      a5_contract=$(printf '%s\n' "$a5_pairs" | grep -F 'enforce-agent-contract.sh' | head -1 | cut -f1)

      # a5_expect <label> <regex> <must-match names> -- <must-NOT-match names>
      a5_e_bad=""
      a5_expect() {
        a5x_label="$1"; a5x_re="$2"; shift 2
        a5x_side=in
        for a5x_n in "$@"; do
          if [ "$a5x_n" = "--" ]; then a5x_side=out; continue; fi
          if printf '%s\n' "$a5x_n" | grep -qE "$a5x_re"; then
            [ "$a5x_side" = out ] && a5_e_bad="$a5_e_bad ${a5x_label}:${a5x_n}-MATCHES-but-must-not"
          else
            [ "$a5x_side" = in ] && a5_e_bad="$a5_e_bad ${a5x_label}:${a5x_n}-NO-MATCH"
          fi
        done
      }

      # 1. the shell-glob language — the skills hook's case arms.
      for a5n in coder dotnet-coder rust-coder java-coder python-coder tester architect; do
        a5_matches "$a5n" || a5_e_bad="$a5_e_bad case-arm:$a5n"
      done

      # 2. the regex language — the two SubagentStop matchers, both directions.
      if [ -z "$a5_pipeline" ] || [ -z "$a5_contract" ]; then
        ko "check 29 (arm E): could not locate the SubagentStop pipeline/contract matchers by the hook they run — the sweep would pass vacuously"
      else
        a5_expect pipeline "$a5_pipeline" \
          coder dotnet-coder rust-coder java-coder python-coder code-reviewer tester architect \
          -- ops Explore zz-unbound-probe
        a5_expect contract "$a5_contract" \
          coder dotnet-coder rust-coder java-coder python-coder code-reviewer \
          -- tester architect ops Explore zz-unbound-probe
        if [ -z "$a5_e_bad" ]; then
          ok "check 29 (arm E): every survivor name MATCHES its binding sites in BOTH pattern languages, and every non-bound name still misses them"
        else
          ko "check 29 (arm E): binding-site mismatch —$a5_e_bad. Existence proves nothing here; a name that stops matching fails OPEN and SILENT — the hook is simply never invoked, with no block, no warning and every file present."
        fi
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 30. CITED HEADINGS MUST RESOLVE, AND THE REPORT MUST SELF-DIAGNOSE (v3.0.0,
#     item B1).
#
#     THIS IS A STRING CHECK, NOT A LINK CHECK, AND THAT IS THE WHOLE POINT.
#     Two consumers independently censused it and it was verified in source:
#     there is not ONE `AGENT_TEAM.md#anchor` fragment link in this repo. Zero.
#     Every cross-reference is prose, in several syntaxes. A link checker finds
#     none of them, which is why nothing detected the defect below for the
#     entire life of the file.
#
#     ⚠ RESOLVE REPO-WIDE BEFORE REPORTING — "dangling" INVITES THE WRONG FIX.
#     Measured, not hypothesised: the consumer who FOUND the defect this check
#     debuts against proposed two remedies and BOTH were wrong — "add the
#     heading to CLAUDE.md" would have duplicated a section already present 916
#     lines down the same file, and "drop the citation" would have deleted a
#     pointer to real, reachable guidance. Their detection was right; their
#     prescription was not, and the cause is the CHECK'S SHAPE, not their
#     judgement. A check asking only "does the cited heading exist in the cited
#     FILE?" returns a true answer that cannot separate two cases with OPPOSITE
#     remedies:
#
#       CITED <file> "<heading>" -> not in <file>; FOUND in <other> : wrong
#                                   filename — a one-word edit
#       CITED <file> "<heading>" -> not found anywhere              : missing
#                                   section — write it, or drop the citation
#
#     One extra lookup buys a self-diagnosing failure, the same property that
#     makes a retired-subagent_type error useful. This arrives load-bearing
#     rather than theoretical: THE FIRST DEFECT IT CAUGHT WAS A WRONG-FILENAME
#     ONE, shipped in all six variants — `AGENT_TEAM.md:76` cited
#     `CLAUDE.md "Open Brain Context for Agents"` while the heading sat at
#     `AGENT_TEAM.md:992`. The failure mode B1 exists to prevent had ALREADY
#     OCCURRED, in the opposite direction, with no shrink involved. So this is
#     a STANDING gate assertion, not a shrink-only acceptance criterion.
#
#     THE COLLECTOR IS WHERE A CHECK LIKE THIS DIES QUIETLY. A regex keyed on
#     one citation syntax finds a subset and reports green, which is the
#     `command:`-anchored collector's failure one noun over. So: four shapes are
#     collected, arm C asserts a FLOOR on the count, and the shapes are
#     DELIMITED on purpose. The bare `-> Heading` shape terminates at the first
#     punctuation, so a citation trailing into prose ("-> MCP Layering for the
#     one-line migration") over-captures and goes RED as a missing section
#     rather than silently passing. That is fail-closed in the right direction:
#     the remedy is to delimit the citation (`-> *MCP Layering*`), and the check
#     teaches the canonical syntax by going red.
#
#     SCOPE. CHANGELOG.md is excluded — it is an append-only historical record
#     whose prose deliberately quotes headings as they were at the time. And a
#     citation whose FILE does not resolve inside this repo is skipped, not
#     failed: `~/.claude/CLAUDE.md` is a prose reference across the repo
#     boundary into user-level config that no repo-scoped check can verify and
#     no project sync touches. Do not gate it; do not add more of them.
# ---------------------------------------------------------------------------
echo
b1_files=$( { ls ./*.md 2>/dev/null
              ls docs/*.md 2>/dev/null
              find templates user-level-reference -name '*.md' 2>/dev/null
              ls hooks/*.sh 2>/dev/null
            } | sed 's@^\./@@' | grep -v '^CHANGELOG\.md$' | sort -u )

b1_FILEPAT='`?[A-Za-z0-9_.-]+\.md`?'
b1_ARROW='[[:space:]]*(->|→)[[:space:]]*'
b1_SEC='[[:space:]]*§[[:space:]]*'
b1_WORDS="[A-Z][A-Za-z0-9 &'/-]*"

b1_tmp=$(mktemp -d)

# Heading index, one `basename|heading` per line. Indexed by BASENAME because a
# citation names a file, not a path, and the same basename legitimately exists
# once per variant.
for b1_f in $b1_files; do
  case "$b1_f" in *.md) ;; *) continue ;; esac
  sed -n 's/^#\{1,6\}[[:space:]]\{1,\}\(.*\)$/\1/p' "$b1_f" \
    | sed 's/[[:space:]]*#*[[:space:]]*$//' \
    | sed "s@^@${b1_f##*/}|@" >> "$b1_tmp/headings"
done
sort -u -o "$b1_tmp/headings" "$b1_tmp/headings"

{ grep -rnoE "${b1_FILEPAT}${b1_ARROW}\*[^*]+\*"  $b1_files 2>/dev/null
  grep -rnoE "${b1_FILEPAT}${b1_ARROW}\"[^\"]+\"" $b1_files 2>/dev/null
  grep -rnoE "${b1_FILEPAT}${b1_ARROW}${b1_WORDS}" $b1_files 2>/dev/null
  grep -rnoE "${b1_FILEPAT}${b1_SEC}${b1_WORDS}"   $b1_files 2>/dev/null
  grep -rnoE "${b1_FILEPAT}[[:space:]]+\"[^\"]+\"" \
    $(printf '%s\n' $b1_files | grep '\.md$') 2>/dev/null
} | sort -u > "$b1_tmp/raw"

b1_total=$(grep -c . "$b1_tmp/raw" 2>/dev/null || echo 0)

# b1_resolve — prints nothing and returns 0 when the citation resolves;
# otherwise prints the SELF-DIAGNOSING line and returns 1.
b1_resolve() {
  b1r_where="$1"; b1r_cf="$2"; b1r_hd="$3"
  if grep -qxF "${b1r_cf}|${b1r_hd}" "$b1_tmp/headings"; then
    return 0
  fi
  b1r_other=$(awk -v h="$b1r_hd" \
    '{i=index($0,"|"); if (i>0 && substr($0,i+1)==h) print substr($0,1,i-1)}' \
    "$b1_tmp/headings" | sort -u | tr '\n' ' ')
  if [ -n "$b1r_other" ]; then
    printf '  %s  CITED %s "%s" -> not in %s; FOUND in %s: WRONG FILENAME (one-word edit)\n' \
      "$b1r_where" "$b1r_cf" "$b1r_hd" "$b1r_cf" "${b1r_other% }"
  else
    printf '  %s  CITED %s "%s" -> not found anywhere: MISSING SECTION (write it, drop the citation, or delimit it as -> *Heading*)\n' \
      "$b1r_where" "$b1r_cf" "$b1r_hd"
  fi
  return 1
}

b1_bad=0
b1_ok=0
while IFS= read -r b1_rec; do
  [ -n "$b1_rec" ] || continue
  b1_where=${b1_rec%%:*}; b1_rest=${b1_rec#*:}
  b1_lineno=${b1_rest%%:*}; b1_cite=${b1_rest#*:}
  b1_cf=$(printf '%s' "$b1_cite" | sed -E 's/^`?([A-Za-z0-9_.-]+\.md).*/\1/')
  b1_hd=$(printf '%s' "$b1_cite" \
    | sed -E 's@^`?[A-Za-z0-9_.-]+\.md`?@@' \
    | sed -E 's/^[[:space:]]*(->|→|§)?[[:space:]]*//' \
    | sed -E 's/^\*(.*)\*$/\1/; s/^"(.*)"$/\1/' \
    | sed -E 's/[[:space:]]+$//')
  [ -n "$b1_hd" ] || continue
  # Out of scope by design: a cited file that does not exist in this repo is a
  # cross-boundary reference (`~/.claude/CLAUDE.md`), unverifiable here.
  printf '%s\n' $b1_files \
    | grep -q "\(^\|/\)$(printf '%s' "$b1_cf" | sed 's/\./\\./g')$" || continue
  if b1_resolve "$b1_where:$b1_lineno" "$b1_cf" "$b1_hd"; then
    b1_ok=$((b1_ok + 1))
  else
    b1_bad=$((b1_bad + 1))
  fi
done < "$b1_tmp/raw"

if [ "$b1_bad" -eq 0 ]; then
  ok "check 30 (arm A): all $b1_ok in-repo cited headings resolve to a live heading"
else
  ko "check 30 (arm A): $b1_bad cited heading(s) do not resolve — see the self-diagnosing lines above; wrong-filename and missing-section have OPPOSITE remedies"
fi

# Arm B (NEGATIVE SELF-TEST): a heading nobody wrote must be reported. Without
# it, a resolver that always returned 0 — or a heading index that accidentally
# matched everything — would make arm A green for the wrong reason. A check that
# cannot report a miss has not reported a hit.
if b1_resolve "synthetic" "AGENT_TEAM.md" "zz-nonexistent-heading-probe" >/dev/null; then
  ko "check 30 (arm B): a synthetic non-existent heading RESOLVED — arm A is passing vacuously"
else
  ok "check 30 (arm B): a synthetic non-existent heading is correctly reported unresolved"
fi

# Arm C (COLLECTOR FLOOR): the way this check dies quietly is a collector that
# stops matching and reports zero unresolved out of zero collected. 62 citations
# were collected when this shipped; the floor is set well below that so ordinary
# prose edits do not trip it, and well above zero so a broken collector does.
if [ "$b1_total" -ge 40 ]; then
  ok "check 30 (arm C): collector recovered $b1_total citations (floor 40)"
else
  ko "check 30 (arm C): collector recovered only $b1_total citations (floor 40) — the citation syntax has drifted away from the collected shapes, or the collector is broken. A zero here would otherwise report as ZERO UNRESOLVED."
fi

rm -rf "$b1_tmp"

# ---------------------------------------------------------------------------
# 31. REGION PRESERVATION MUST SURVIVE A NEAR-TOTAL DELETION OF THE TEMPLATE
#     PART (v3.0.0, item B1).
#
#     v3.0.0 shrinks AGENT_TEAM.md from 1026 lines to 556 — a 46% deletion of
#     the template part, far outside anything the region machinery has ever been
#     exercised against. This check runs the property at ~97%, which is stricter
#     than what ships, because the property is supposed to be independent of how
#     much was deleted and a fixture pinned to today's figure stops testing that
#     the moment the figure changes.
#
#     ⚠ PLANTED CONTENT, NEVER FOUND CONTENT. A census across three consumer
#     repos found ZERO real PROJECT-CUSTOM content (11, 10 and 1 region-bearing
#     files, all placeholder-only), so a green run on any of them proves
#     nothing — the guard CANNOT FAIL there. The content comes from the
#     committed fixture at scripts/fixtures/project-custom-regions/, which is
#     the only known source of real region content anywhere.
#
#     BOTH ARMS. A planted region must be classified CONTENT and must survive
#     the splice BYTE-EXACTLY; a placeholder-only region must be classified
#     EMPTY. A check that only ever asserts the reassuring answer is the
#     extractor defect this whole programme exists to stop.
# ---------------------------------------------------------------------------
echo
B1_REGION_SH="user-level-reference/skills/sync-template/region.sh"
B1_PLANT="scripts/fixtures/project-custom-regions/plant.sh"
if [ ! -f "$B1_REGION_SH" ] || [ ! -f "$B1_PLANT" ]; then
  ko "check 31: $B1_REGION_SH or $B1_PLANT missing — region preservation is unexercised"
else
  b2_tmp=$(mktemp -d)
  mkdir -p "$b2_tmp/consumer/.claude/agents"
  cp templates/general/AGENT_TEAM.md templates/general/CLAUDE.md "$b2_tmp/consumer/"
  cp templates/general/.claude/agents/coder.md "$b2_tmp/consumer/.claude/agents/"

  # Arm A (BOTH-ARMS PRECONDITION): before planting, every one of the three must
  # classify EMPTY. If they did not, arm B's CONTENT result would prove nothing
  # about the planting.
  b2_pre=$(bash "$B1_REGION_SH" "$b2_tmp/consumer/AGENT_TEAM.md" \
    "$b2_tmp/consumer/CLAUDE.md" "$b2_tmp/consumer/.claude/agents/coder.md" \
    2>/dev/null | cut -f1 | sort -u | tr '\n' ' ')
  if [ "$b2_pre" = "EMPTY " ]; then
    ok "check 31 (arm A): the three shipped region-bearing files classify EMPTY before planting"
  else
    ko "check 31 (arm A): expected all three shipped files to classify EMPTY before planting, got: $b2_pre"
  fi

  if ! bash "$B1_PLANT" "$b2_tmp/consumer" >/dev/null 2>&1; then
    ko "check 31: plant.sh failed against a freshly copied template tree — the shipped placeholder block has changed shape"
  else
    b2_post=$(bash "$B1_REGION_SH" "$b2_tmp/consumer/AGENT_TEAM.md" \
      "$b2_tmp/consumer/CLAUDE.md" "$b2_tmp/consumer/.claude/agents/coder.md" \
      2>/dev/null | cut -f1 | sort -u | tr '\n' ' ')
    if [ "$b2_post" = "CONTENT " ]; then
      ok "check 31 (arm B): all three classify CONTENT once real region content is planted"
    else
      ko "check 31 (arm B): expected all three to classify CONTENT after planting, got: $b2_post"
    fi

    # Arm C: THE SHRINK ITSELF. Build a new template part that is a ~97%
    # deletion — the first 12 lines and nothing else — then splice the
    # consumer's extracted region onto it, exactly as a sync preserves.
    b2_keep=12
    b2_body_lines=$(wc -l < "$b2_tmp/consumer/AGENT_TEAM.md")
    head -n "$b2_keep" templates/general/AGENT_TEAM.md > "$b2_tmp/shrunk.md"
    tail -n 3 templates/general/AGENT_TEAM.md >> "$b2_tmp/shrunk.md"
    b2_pct=$(( 100 - (b2_keep + 3) * 100 / b2_body_lines ))

    bash "$B1_REGION_SH" --body "$b2_tmp/consumer/AGENT_TEAM.md" > "$b2_tmp/planted.body" 2>/dev/null
    # Splice: replace the shrunk file's placeholder body with the planted body.
    awk -v ph='<!-- Project-specific rules, routing blocks, and extensions go here. -->' \
        -v rf="$b2_tmp/planted.body" '
      index($0, ph) > 0 && !done {
        while ((getline line < rf) > 0) print line
        close(rf); done = 1; next
      }
      { print }
    ' "$b2_tmp/shrunk.md" > "$b2_tmp/spliced.md"

    bash "$B1_REGION_SH" --body "$b2_tmp/spliced.md" > "$b2_tmp/spliced.body" 2>/dev/null
    b2_class=$(bash "$B1_REGION_SH" "$b2_tmp/spliced.md" 2>/dev/null | cut -f1)
    if cmp -s "$b2_tmp/planted.body" "$b2_tmp/spliced.body" && [ "$b2_class" = "CONTENT" ]; then
      ok "check 31 (arm C): a planted region ($(wc -c < "$b2_tmp/planted.body" | tr -d ' ') B) survives a ${b2_pct}% deletion of the template part BYTE-EXACTLY, and still classifies CONTENT"
    else
      ko "check 31 (arm C): the planted region did NOT survive a ${b2_pct}% deletion byte-exactly (classified '$b2_class') — region preservation breaks at shrink magnitudes v3.0.0 actually performs"
    fi

    # Arm D (NEGATIVE CONTROL): splice the PLACEHOLDER instead of the planted
    # body. It must classify EMPTY. Without this, an extractor that returned
    # CONTENT unconditionally would make arms B and C green for the wrong
    # reason — the exact false-clean this programme was bitten by, inverted.
    b2_ph_class=$(bash "$B1_REGION_SH" "$b2_tmp/shrunk.md" 2>/dev/null | cut -f1)
    if [ "$b2_ph_class" = "EMPTY" ]; then
      ok "check 31 (arm D): the same shrunk file with only the placeholder classifies EMPTY — the CONTENT result in arm C is discriminating, not unconditional"
    else
      ko "check 31 (arm D): a placeholder-only region classified '$b2_ph_class', not EMPTY — arms B and C are passing vacuously"
    fi
  fi
  rm -rf "$b2_tmp"
fi

# ===========================================================================
# 32. NO LIVE DOC NAMES A RETIRED AGENT (v3.0.1)
#
#     THIS IS 6d POINTED AT THE REPOSITORY THAT SHIPS 6d.
#
#     Every stale reference v3.0.1 found is 6d's own FORM 3 — prose naming an
#     agent that no longer exists — one tree over. 6d scopes to a CONSUMER's
#     project tree; nothing scoped to the toolkit's own `docs/`, which is why
#     three of them shipped in v3.0.0 and were found by a reader, not a check.
#
#     ⚠ POLARITY IS DELIBERATE: THIS CHECK FAILS TOWARD FLAGGING.
#     A false positive costs a human one look. A false clean ships a document
#     that routes someone to a deleted agent. If this check gets noisy, the fix
#     is to add a retirement marker to the offending line — NOT to loosen the
#     matcher. Loosening it is how a guard becomes decorative.
#
#     ⚠ AND IT IS NOT A BARE-NAME SCAN. `AGENT_TEAM.md`, the CHANGELOG and the
#     sync skill all name retired agents LEGITIMATELY, to document the
#     retirement. A bare-name scan flags every one of them and reproduces the
#     28:1 noise that killed the bare-name approach in 6d — a check consumers
#     learn to ignore is worse than no check. So: a line naming a retired agent
#     PASSES when it also carries a retirement MARKER (`retired`, `absorbed`,
#     `formerly`, or a version string), and is flagged otherwise.
#
#     THE RETIRED SET IS EXPLICIT AND MAINTAINED HERE, never inferred from a
#     git diff. An inferred set is a second thing that can silently go empty,
#     and an empty retired set makes every row pass — the check reports green
#     having measured nothing. Arm D asserts it is non-empty for that reason.
#
#     SCOPE is `docs/**.md` AND `user-level-reference/**.md`, minus the DATED
#     HISTORICAL RECORDS: `docs/plans/**` and `docs/<YYYY-MM-DD>-*.md`. Both are
#     records of what was true on a date; rewriting them falsifies the history,
#     so they are excluded BY SHAPE rather than by a list that rots. Excluded by
#     path, not by content, so a new dated record needs no edit here.
#
#     ⚠ `user-level-reference/` IS IN SCOPE BECAUSE THAT IS WHERE THE MOTIVATING
#     CASE LIVED. The reference that proved this gap existed was step 9 of
#     `skills/sync-template/SKILL.md`, which shipped v3.0.0 still naming
#     `test-writer`. A check scoped so it cannot see its own motivating case is
#     the "adjacent question" defect one more time — so the scope is the tree
#     the instance was found in, not the tree that was convenient.
#
#     FENCED CODE BLOCKS ARE EXCLUDED, and on their own merits rather than as a
#     workaround. A line inside ``` or ~~~ is a sample, a transcript, or a
#     MEASUREMENT — never live routing prose. This skill's own noise census
#     (`doc-generator 10 | test-writer 4`) is a recorded measurement inside a
#     fence: flagging it would demand falsifying a number that was true when
#     measured. Prose one line outside the fence is still flagged.
#
#     ⚠ FENCE TRACKING FAILS THE WRONG WAY IF IT DESYNCS. An odd number of
#     delimiters leaves the tail of a file permanently "inside a fence", which
#     silently swallows live prose and returns the CLEAN answer. Arm F asserts
#     the delimiter count is even in every scanned file, so the desync cannot
#     happen quietly. Arm E is the two-sided control on the extractor itself.
# ===========================================================================
echo
b3_retired="test-writer requirements-engineer doc-generator"
# A line naming a retired agent is legitimate when it says so. Version strings
# count because "absorbed into `tester` (v3.0.0)" is the shape migration notes
# actually use.
b3_marker='retired|absorbed|formerly|v[0-9]+\.[0-9]+\.[0-9]+'
b3_re=$(printf '%s' "$b3_retired" | tr ' ' '|')

# The matcher, as ONE function, so the two control arms below exercise the same
# code the real scan does rather than a re-typed approximation of it.
# Returns 0 (true) when the line SHOULD be flagged.
b3_should_flag() {
  case "$1" in
    *test-writer*|*requirements-engineer*|*doc-generator*)
      printf '%s' "$1" | grep -qiE "$b3_marker" && return 1
      return 0 ;;
  esac
  return 1
}

# Candidate extractor: `<lineno>:<text>` for every line matching a retired name
# OUTSIDE a fenced code block. ONE function, so arm E exercises the code the
# real scan runs rather than a re-typed approximation of it.
b3_extract() { # <file>
  awk -v re="$b3_re" '
    /^[[:space:]]*(```|~~~)/ { fence = 1 - fence; next }
    !fence && $0 ~ re { print NR ":" $0 }
  ' "$1" 2>/dev/null
}

b3_bad=0
b3_scanned=0
b3_oddfence=0
while IFS= read -r b3_f; do
  [ -n "$b3_f" ] || continue
  case "$b3_f" in
    docs/plans/*) continue ;;
    docs/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) continue ;;
  esac
  b3_scanned=$((b3_scanned + 1))
  # Arm F input: an odd delimiter count means fence state desyncs and the tail
  # of the file is treated as fenced — a silent CLEAN on live prose.
  # `grep -c` PRINTS 0 and EXITS 1 on no match, so a `|| echo 0` fallback
  # appends a SECOND line and the arithmetic below dies on "0\n0". The count is
  # always printed; there is nothing to fall back to.
  b3_fc=$(grep -cE '^[[:space:]]*(```|~~~)' "$b3_f" 2>/dev/null)
  if [ $(( ${b3_fc:-0} % 2 )) -ne 0 ]; then
    echo "    $b3_f has $b3_fc fence delimiters (odd) — fence state desyncs and the tail of the file would be scanned as if fenced"
    b3_oddfence=$((b3_oddfence + 1))
  fi
  while IFS= read -r b3_hit; do
    [ -n "$b3_hit" ] || continue
    b3_lno=${b3_hit%%:*}
    b3_txt=${b3_hit#*:}
    if b3_should_flag "$b3_txt"; then
      echo "    $b3_f:$b3_lno NAMES A RETIRED AGENT with no retirement marker"
      echo "      ${b3_txt}" | cut -c1-160
      b3_bad=$((b3_bad + 1))
    fi
  done < <(b3_extract "$b3_f")
done < <(git ls-files -- 'docs/*.md' 'docs/*/*.md' 'user-level-reference/*.md' 'user-level-reference/*/*.md' 'user-level-reference/*/*/*.md' 2>/dev/null)

# Arm A — the assertion itself.
if [ "$b3_bad" -eq 0 ]; then
  ok "check 32 (arm A): no live doc names a retired agent without a retirement marker ($b3_scanned docs scanned)"
else
  ko "check 32 (arm A): $b3_bad line(s) name a RETIRED agent as if it were live — see above. Fix by naming the survivor (test-writer -> tester, requirements-engineer -> architect, doc-generator -> coder), or, if the line is a record of what was true then, ANNOTATE it with the retirement rather than rewriting it"
fi

# Arm B (POSITIVE CONTROL) — a synthetic unmarked line MUST be flagged. Without
# this, a matcher that never fires makes arm A green having measured nothing.
if b3_should_flag "spawn a doc-generator to write the release notes"; then
  ok "check 32 (arm B): a synthetic unmarked retired-agent line IS flagged — arm A is not passing vacuously"
else
  ko "check 32 (arm B): a synthetic unmarked retired-agent line was NOT flagged — the matcher is dead and arm A means nothing"
fi

# Arm C (NEGATIVE CONTROL) — the SAME name WITH a marker must NOT be flagged.
# Positives alone cannot distinguish a working guard from one that fires on
# everything, and a guard that fires on everything is the one that gets deleted.
if b3_should_flag "tester absorbed test-writer in v3.0.0"; then
  ko "check 32 (arm C): a properly MARKED retirement note was flagged — this check fires on everything, including the migration notes that document the retirement"
else
  ok "check 32 (arm C): a properly marked retirement note is NOT flagged — arm B is discriminating, not unconditional"
fi

# Arm D — the retired set and the scope must both be non-empty. An empty
# retired list makes every line pass; an empty file list makes every file pass.
# Either one reports green having measured nothing.
b3_n=0
for b3_name in $b3_retired; do b3_n=$((b3_n + 1)); done
if [ "$b3_n" -ge 1 ] && [ "$b3_scanned" -ge 10 ]; then
  ok "check 32 (arm D): $b3_n retired name(s) checked against $b3_scanned live docs — neither input is empty"
else
  ko "check 32 (arm D): retired names=$b3_n, docs scanned=$b3_scanned (floor 10) — an empty input makes arm A green having measured NOTHING"
fi

# Arm E (TWO-SIDED CONTROL on the FENCE EXTRACTOR). A fence-aware scan can fail
# in two opposite directions and only one of them is loud: extracting nothing at
# all is the CLEAN answer. So assert both sides against one synthetic file —
# the fenced hit must be invisible, the prose hit one line later must not be.
b3_tmp=$(mktemp -d 2>/dev/null || echo "/tmp/b3-$$")
mkdir -p "$b3_tmp"
{
  printf '%s\n' 'intro prose with no names'
  printf '%s\n' '```'
  printf '%s\n' 'doc-generator 10 | test-writer 4'
  printf '%s\n' '```'
  printf '%s\n' 'spawn a doc-generator to write the release notes'
} > "$b3_tmp/fence.md"
b3_got=$(b3_extract "$b3_tmp/fence.md")
if printf '%s' "$b3_got" | grep -q '^5:' && ! printf '%s' "$b3_got" | grep -q '^3:'; then
  ok "check 32 (arm E): the fence extractor skips a FENCED retired-name line and still returns the PROSE one — exclusion is discriminating, not blanket"
else
  ko "check 32 (arm E): fence extractor returned [$b3_got]; expected line 5 (prose) and NOT line 3 (fenced). Returning neither is the CLEAN-looking failure — arm A would be green having extracted nothing"
fi
rm -rf "$b3_tmp"

# NOTE: check 33 (EOL) is appended after arm F below — it is a file-level census
# with no relation to the retired-name scan and simply lands at the end.

# Arm F — fence delimiters must be balanced in every scanned file. An odd count
# leaves the tail of a file permanently "inside a fence", so live prose after it
# is never scanned and arm A returns clean. This is the one way the exclusion
# above can turn into a silent false negative.
if [ "$b3_oddfence" -eq 0 ]; then
  ok "check 32 (arm F): fence delimiters are balanced in all $b3_scanned scanned docs — fence state cannot desync and swallow live prose"
else
  ko "check 32 (arm F): $b3_oddfence scanned doc(s) have an ODD fence-delimiter count — see above. Everything after the unmatched delimiter is scanned as if fenced, so arm A is clean for that region whatever it contains"
fi

# ---------------------------------------------------------------------------
# 33. NO TRACKED FILE CARRIES A CARRIAGE RETURN (v3.0.3).
#
#     "Every file is LF" has been an invariant since v1 and nothing executed it.
#     `scripts/template_propagate_to_variants` can emit CRLF, and a census that
#     cannot see line endings is the same class of blind spot as one that cannot
#     see whether a hook is REGISTERED.
#
#     READ THE BLOBS, NOT THE WORKING TREE. On a consumer checkout with
#     `core.autocrlf=true` every text file in the working tree has CRLF by
#     design, and a working-tree scan would go red on a repository that is
#     perfectly clean. `git show :<path>` reads the staged/committed bytes,
#     which are what other consumers receive.
#
#     Binary files are skipped by the same extension list `.gitattributes`
#     marks binary; a CR inside one of those is content, not an EOL.
# ---------------------------------------------------------------------------
echo
eol_bad=0
eol_scanned=0
eol_names=""
# NUL-delimited: a `for f in $(git ls-files)` word-splits on a filename with a
# space in it and silently under-scans, which is the same clean-looking failure
# the scanned-count floor below exists to catch.
eol_cr=$(printf '\r')
while IFS= read -r -d '' f; do
  case "$f" in
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.icns|*.webp|*.woff|*.woff2|*.ttf|*.otf|*.eot|*.gz|*.zip|*.pdf|*.jar|*.class|*.dll|*.exe) continue ;;
  esac
  eol_scanned=$((eol_scanned + 1))
  if git show ":$f" 2>/dev/null | grep -qU "$eol_cr"; then
    eol_bad=$((eol_bad + 1))
    eol_names="$eol_names $f"
  fi
done < <(git ls-files -z 2>/dev/null)
if [ "$eol_scanned" -lt 50 ]; then
  # A census that scanned almost nothing reports clean for the wrong reason.
  ko "check 33: only $eol_scanned tracked text files enumerated — the file list is broken, not the repository clean"
elif [ "$eol_bad" -eq 0 ]; then
  ok "check 33: all $eol_scanned tracked text blobs are LF-only (no CR)"
else
  ko "check 33: $eol_bad tracked blob(s) contain CR:$eol_names — normalize to LF (sed -i 's/\r\$//', never PowerShell) and re-add"
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
