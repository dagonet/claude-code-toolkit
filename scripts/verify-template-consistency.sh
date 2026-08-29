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
skill_list=$(ls templates/*/.claude/agents/*.md user-level-reference/agents/*.md 2>/dev/null | grep -vE '(Explore|doc-generator)\.md$')
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
# 22b. The .env deny list is precise (v2.2.0, consumer feedback BUG 6).
#
#     `Read(.env*)` also denied `.env.example` — a TRACKED file most repos ship
#     as the documented list of required variables. The secret-bearing names are
#     enumerated instead, so the example file stays readable.
# ---------------------------------------------------------------------------
echo
ENV_DENY='Read(.env) Read(.env.local) Read(.env.*.local) Read(.env.production) Read(.env.staging) Read(.env.development)'
for s in $(for v in $VARIANTS; do echo "templates/$v/.claude/settings.json"; done) user-level-reference/settings.json; do
  missing=""
  for t in $ENV_DENY; do
    grep -qF "\"$t\"" "$s" || missing="$missing $t"
  done
  if [ -z "$missing" ]; then
    ok "$s: denies all 6 secret-bearing .env names"
  else
    ko "$s: .env deny list missing:$missing"
  fi
  # The glob must be gone, or .env.example is denied again.
  if grep -qF '"Read(.env*)"' "$s"; then
    ko "$s: Read(.env*) is back — it also denies the tracked .env.example"
  else
    ok "$s: no Read(.env*) glob (.env.example stays readable)"
  fi
done

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
echo
if [ "$fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "ONE OR MORE CHECKS FAILED"
  exit 1
fi
