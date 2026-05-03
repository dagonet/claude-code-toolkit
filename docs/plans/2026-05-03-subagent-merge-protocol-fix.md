# Sub-Agent Merge Protocol — Documentation Reconciliation Plan (consolidated)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile claude-code-toolkit's docs and agent definitions with the empirically confirmed Claude Code dispatch rule: sub-agents declared with explicit `tools:` lists have `mcp__*` and `ToolSearch` stripped at runtime; only `tools: *` (e.g. `general-purpose`) gets the full deferred MCP catalog.

**Architecture:** Documentation-only edits, no code. Three classes of changes: (1) AGENT_TEAM.md / CLAUDE.md merge protocol acknowledges the PO must perform git+GitHub I/O on behalf of specialized sub-agents; (2) tester.md / code-reviewer.md drop the `ToolSearch` reference and the "use ToolSearch to call MCP" instructions, since the runtime strips both; (3) one-shot probe to confirm whether plugin sub-agents (feature-dev:*, superpowers:*) behave the same way.

**Tech Stack:** Markdown + YAML frontmatter only. Verified via `mcp__git-tools__git_diff_summary` after each task and via grep verification steps inside each task.

**Tier:** **T3 Standard** — multi-file documentation edits, mechanical, no architectural impact. Roughly 110 line replacements across ~30 files.

**Plan history:** consolidated from v1 (original repo plan) + v2 (delta after architect R1) + R2 fixes (architect R2) + R3 fixes (architect R3). All architect findings incorporated.

---

## Context

OmniScribe Sprint 8.1 (2026-05-03) confirmed empirically that Claude Code strips `mcp__*` and `ToolSearch` from sub-agent runtimes when the agent definition uses an explicit `tools:` list. Only `tools: *` (`general-purpose`) gets the full deferred MCP catalog. `advisor` is added session-wide.

Verified probe matrix:

| Sub-agent | tools: advertises | Runtime received | MCP / ToolSearch |
|---|---|---|---|
| python-coder | Read, Edit, Grep, Glob, Bash | Read, Edit, Grep, Glob, Bash, advisor | neither |
| code-reviewer | Read, Grep, Glob, ToolSearch | Read, Grep, Glob, advisor | ToolSearch stripped |
| tester | Read, Write, Edit, Grep, Glob, Bash, ToolSearch | Read, Write, Edit, Grep, Glob, Bash, advisor | ToolSearch stripped |
| general-purpose | * | Full deferred catalog | both |

Implication: claude-code-toolkit's `AGENT_TEAM.md` Merge Protocol ("the developer owns the merge") and `CLAUDE.md` Workflow TL;DR ("Developer -> Code Reviewer -> Tester -> Developer merges PR") are valid only for `general-purpose` developer sub-agents. With domain-specialized devs (`coder`, `python-coder`, `dotnet-coder`, `rust-coder`, `java-coder`, `code-reviewer`, `tester`, `test-writer`), those agents physically cannot commit, push, open PRs, post comments, or merge. The PO must do this I/O on their behalf.

`tester.md` and `code-reviewer.md` advertise `ToolSearch` in `tools:` and instruct "use `ToolSearch` to load MCP GitHub tools" in the body — both are misleading because runtime strips `ToolSearch`. Cleanup needed for declarative honesty.

Beyond the Merge Protocol section, AGENT_TEAM.md has 8 stale "Developer merges/owns/etc." references that contradict the new ownership rule. Verified line numbers in `templates/general/AGENT_TEAM.md`: 212, 383, 481, 483, 552, 592, 593, 610.

The user-level installs at `C:\Users\DarkNite\.claude\agents\` mirror `user-level-reference/agents/`. After the repo update lands and PR merges, propagate to user-level.

---

## File Structure

| File | Variants | Change kind |
|---|---|---|
| `AGENT_TEAM.md` | 6 (byte-identical) | Replace Merge Protocol section + 7 sub-edits at lines 212/383/481/483/552/592-593/610 |
| `CLAUDE.md` | 6 (consistent for these sections) | Replace Workflow TL;DR pipeline line, append Spawn-Prompt Binding Table footnote, replace Commit Workflow merge-ownership paragraph |
| `CLAUDE.local.md` | 6 (divergent overall, but anchor lines consistent) | Add sidebars under both HARD REQUIREMENT sections |
| `.claude/agents/tester.md` | 6 + user-level-reference (byte-identical) | Drop `ToolSearch` from `tools:`; rewrite Findings Format intro and Rules bullet to route output via PO |
| `.claude/agents/code-reviewer.md` | 6 + user-level-reference (byte-identical) | Drop `ToolSearch` from `tools:`; replace "Posting Reviews to GitHub" with "Returning Reviews to the PO" |
| `~/.claude/agents/{tester,code-reviewer}.md` | 1 install (this machine) | Mirror user-level-reference (after PR merges) |
| `docs/workflow-audit.md` (and any other README/docs hits) | 1 file confirmed via R3 grep | Patch stale "developer merges/owns" references |

`test-writer.md` does not advertise `ToolSearch` — no change needed. `architect.md`, `requirements-engineer.md`, `doc-generator.md` are unaffected. `user-level-reference/CLAUDE.md` does not contain Workflow TL;DR / Spawn-Prompt / Merge ownership sections (verified) — excluded from CLAUDE.md edits.

**Commit message convention:** all commits below use multiline messages. Pass via `mcp__git-tools__git_commit` with the message as a JSON string with real newlines — the MCP layer handles escaping. Do NOT paste literal `\n` characters into a single quoted string.

---

## Tasks

### Task 1: Probe plugin sub-agent dispatch behavior

**Files:** none (read-only probe).

- [ ] **Step 1: Spawn one feature-dev:code-architect sub-agent with a tooling probe.**

Prompt:
```
DO NOT WRITE ANY CODE. This is a tooling probe.

1. Try calling `ToolSearch` with `query: "select:mcp__git-tools__git_status"`, `max_results: 1`. Report the response or exact error.
2. Without ToolSearch, try a direct call to `mcp__git-tools__git_status` with `repo_path: "G:\\git\\claude-code-toolkit"`. Report the exact error verbatim.

Concluding line: PLUGIN-AGENT MCP STRIPPED or PLUGIN-AGENT MCP AVAILABLE. Under 100 words.
```

- [ ] **Step 2: Decide.**

If MCP STRIPPED → continue with the plan as written. The plan does not need to mention plugin sub-agents because they're already covered by the same "PO does the I/O" rule. Capture the result via `mcp__open-brain__thoughts_capture` (one line: "Plugin sub-agent dispatch confirmed STRIPPED — same rule as project sub-agents (R3 probe).").

If MCP AVAILABLE → pause and flag to PO. Plan needs an additional task to mention plugin sub-agents are an exception in AGENT_TEAM.md.

---

### Task 2: Update AGENT_TEAM.md Merge Protocol + 7 stale-reference fixes

**Files:**
- `templates/general/AGENT_TEAM.md`
- `templates/dotnet/AGENT_TEAM.md`
- `templates/dotnet-maui/AGENT_TEAM.md`
- `templates/rust-tauri/AGENT_TEAM.md`
- `templates/java/AGENT_TEAM.md`
- `templates/python/AGENT_TEAM.md`

The 6 files are byte-identical for these sections; identical edits apply to all.

- [ ] **Step 0: Pre-flight stale-reference scan.**

Run `Grep tool` with `pattern: "Developer\\s+(merges|owns|pushes|commits)"`, `path: "G:\\git\\claude-code-toolkit\\templates"`, `output_mode: "files_with_matches"` (case-sensitive `Developer`). Expected hits: only the 6 AGENT_TEAM.md files. Any additional file (PROJECT_CONTEXT.md, PROJECT_STATE.md, other AGENT_TEAM.md sections beyond the listed lines) requires either an explicit doc edit added to the plan OR an explicit rationale for skipping. Do NOT proceed until every hit is accounted for.

- [ ] **Step 1: Replace the Merge Protocol section.**

In each of the 6 AGENT_TEAM.md files, find this exact block (it begins at `## Merge Protocol` and ends at the closing line of "## Merge Ordering"):

````markdown
## Merge Protocol

After code review and testing pass, the **developer** is responsible for merging their PR to main.

### Steps

**Note:** The steps below are logical operations. Agents must use MCP git tools (per `CLAUDE.local.md`), not shell `git` commands.

```
1. Pull latest main into the worktree (git_pull or equivalent MCP tools)

2. If conflicts exist:
   a. Resolve conflicts (prefer preserving both changes when possible)
   b. Run format commands from PROJECT_CONTEXT.md
   c. Rebuild and verify (must be 0 errors)
   d. Rerun tests (must be 0 new failures)
   e. Commit the rebase resolution
   f. Force-push the branch

   2b. If conflicts are complex (>10 conflicting files OR >100 conflict lines):
       - Developer messages PO: conflict summary, affected files, estimated effort
       - PO decides: (a) developer resolves with guidance, (b) defer merge until other workstreams complete, or (c) re-spawn architect for conflict resolution strategy
       - Developer does NOT attempt complex conflict resolution autonomously

3. Verify CI passes:
   a. Check CI workflow status via gh_workflow_list after push
   b. If CI fails, fix before merging

4. Squash-merge:
   a. Squash-merge the PR via GitHub MCP (merge_pull_request, method: squash)
   b. Verify merge succeeded

5. Cleanup:
   a. Remove the worktree
   b. Delete the local and remote feature branch
   c. Notify the PO that merge is complete
```

### Merge Ordering

When multiple workstreams finish around the same time, merges happen on a **first-ready, first-merge** basis. Each subsequent merge must rebase onto the updated main before merging.

The PO coordinates merge ordering by sending merge-go-ahead messages to developers in sequence. Developers **must not** merge without PO confirmation.
````

Replace with:

````markdown
## Merge Protocol

After code review and testing pass, the merge owner depends on the developer sub-agent type. Claude Code's sub-agent dispatch strips `mcp__*` tools and `ToolSearch` from any sub-agent with an explicit `tools:` list — only sub-agents declared with `tools: *` (the `general-purpose` agent type) receive the full deferred MCP catalog. Specialized sub-agents (`coder`, `python-coder`, `dotnet-coder`, `rust-coder`, `java-coder`, `test-writer`, `tester`, `code-reviewer`) cannot perform git or GitHub operations themselves.

| Developer sub-agent type | Merge owner |
|---|---|
| `general-purpose` (declared with `tools: *`) | Developer (uses `mcp__git-tools__*` and `mcp__MCP_DOCKER__*` directly) |
| `coder`, `python-coder`, `dotnet-coder`, `rust-coder`, `java-coder` | **PO** (developer cannot call MCP tools) |
| `test-writer`, `tester`, `code-reviewer` | **PO** (same constraint) |

For any specialized sub-agent: when implementation, review, and verification complete, the sub-agent returns the work product (changed files, review findings, verification report) to the PO. The PO performs all git and GitHub I/O on the sub-agent's behalf.

### Steps (PO-executed unless dev is `general-purpose`)

```
1. Pull latest main into the worktree (git_pull or equivalent MCP tools).

2. If conflicts exist:
   a. Resolve conflicts (prefer preserving both changes when possible).
   b. Run format commands from PROJECT_CONTEXT.md.
   c. Rebuild and verify (must be 0 errors).
   d. Rerun tests (must be 0 new failures).
   e. Commit the rebase resolution.
   f. Force-push the branch.

   2b. If conflicts are complex (>10 conflicting files OR >100 conflict lines):
       - PO decides: (a) resolve with guidance from developer, (b) defer merge until other workstreams complete, or (c) re-spawn architect for conflict resolution strategy.
       - Specialized sub-agents do NOT attempt complex conflict resolution autonomously.

3. Verify CI passes:
   a. Check CI workflow status via gh_workflow_list after push.
   b. If CI fails, fix before merging.

4. Squash-merge:
   a. Squash-merge the PR via GitHub MCP (merge_pull_request, method: squash).
   b. Verify merge succeeded.

5. Cleanup:
   a. Remove the worktree.
   b. Delete the local and remote feature branch.
   c. (general-purpose dev only) Notify the PO that merge is complete.
```

### Merge Ordering

When multiple workstreams finish around the same time, merges happen on a **first-ready, first-merge** basis. Each subsequent merge must rebase onto the updated main before merging.

The PO coordinates merge ordering. For `general-purpose` developers, the PO sends merge-go-ahead messages and the developer merges. For specialized developers, the PO performs the merge directly after the per-workstream pipeline completes.
````

- [ ] **Step 2: Sub-edit at L212 (Workflow Diagram).**

Find:
```
Developer --> Code Reviewer --> Tester --> Developer merges PR
```

Replace with:
```
Developer --> Code Reviewer --> Tester --> PO merges PR (specialized) | Developer merges PR (general-purpose only)
```

- [ ] **Step 3: Sub-edit at L383 (handoff bullet).**

Find:
```
- On completion (PR merged), developer removes worktree and deletes branch.
```

Replace with:
```
- On completion (PR merged), the merge owner (PO for specialized devs, developer for general-purpose) removes the worktree and deletes the branch.
```

- [ ] **Step 4: Sub-edit #3a — replace L481 single-line.**

L482 is `       |` (ASCII flow connector); MUST do as two single-line edits.

Find (single line):
```
5. PO sends merge-go-ahead to Developer
```

Replace with:
```
5. PO sends merge-go-ahead. For specialized sub-agents the PO executes the merge directly; for general-purpose developers the PO signals and the developer executes.
```

- [ ] **Step 5: Sub-edit #3b — replace L483 single-line.**

Find (single line):
```
6. Developer executes Merge Protocol
```

Replace with:
```
6. Merge Protocol runs (per merge-owner table in Merge Protocol section).
```

- [ ] **Step 6: Sub-edit at L552 (handoff bullet).**

Find (single line):
```
- Developer -> PO: "Merge complete, cleanup done" (PO closes task)
```

Replace with:
```
- For general-purpose developers only: Developer -> PO: "Merge complete, cleanup done" (PO closes task). For specialized sub-agents the PO performs the merge and closes the task itself.
```

- [ ] **Step 7: Sub-edit at L592-L593 (Working Norms rules 5+6).**

Find (two adjacent lines):
```
5. **Developer owns the merge** — after review + test pass, dev rebases and merges.
6. **PO sequences merges** — developers wait for merge-go-ahead.
```

Replace with:
```
5. **Merge ownership depends on sub-agent type** — `general-purpose` developers (declared with `tools: *`) own the merge; for specialized sub-agents (`coder`, `*-coder`, `test-writer`, `tester`, `code-reviewer`) the PO performs the merge. See Merge Protocol section.
6. **PO sequences merges** — for general-purpose devs, developers wait for merge-go-ahead; for specialized devs, the PO merges directly per the sequence.
```

- [ ] **Step 8: Sub-edit at L610 (Escalation bullet).**

Find:
```
- **Merge conflicts too complex**: Developer messages PO with details. PO may sequence the merge after other workstreams complete.
```

Replace with:
```
- **Merge conflicts too complex**: For general-purpose devs, the developer messages PO with details. For specialized devs, the PO encounters the conflict during merge and decides per the Merge Protocol fallback (defer, re-spawn architect, etc.).
```

- [ ] **Step 9: Verify all 8 edits landed in all 6 files.**

Use `mcp__plugin_context-mode_context-mode__ctx_execute` (shell):

```bash
for f in templates/general templates/dotnet templates/dotnet-maui templates/rust-tauri templates/java templates/python; do
  echo "=== $f ==="
  grep -c "the merge owner depends on the developer sub-agent type" "$f/AGENT_TEAM.md"   # expect 1 (Step 1)
  grep -c "PO merges PR (specialized)"                                "$f/AGENT_TEAM.md" # expect 1 (Step 2)
  grep -c "the merge owner (PO for specialized devs"                  "$f/AGENT_TEAM.md" # expect 1 (Step 3)
  grep -c "PO sends merge-go-ahead. For specialized"                  "$f/AGENT_TEAM.md" # expect 1 (Step 4)
  grep -c "Merge Protocol runs (per merge-owner table"                "$f/AGENT_TEAM.md" # expect 1 (Step 5)
  grep -c "For general-purpose developers only:"                      "$f/AGENT_TEAM.md" # expect 1 (Step 6)
  grep -c "Merge ownership depends on sub-agent type"                 "$f/AGENT_TEAM.md" # expect 1 (Step 7)
  grep -c "For general-purpose devs, the developer messages PO"       "$f/AGENT_TEAM.md" # expect 1 (Step 8)
done
```

All 48 grep counts must print `1`. Any `0` = failed replacement; re-edit before commit.

- [ ] **Step 10: Commit.**

```
mcp__git-tools__git_add(repo_path="G:/git/claude-code-toolkit", paths=["templates/general/AGENT_TEAM.md", "templates/dotnet/AGENT_TEAM.md", "templates/dotnet-maui/AGENT_TEAM.md", "templates/rust-tauri/AGENT_TEAM.md", "templates/java/AGENT_TEAM.md", "templates/python/AGENT_TEAM.md"])
mcp__git-tools__git_commit(repo_path="G:/git/claude-code-toolkit", message="docs(agent-team): split merge protocol by subagent type\n\nClaude Code dispatch strips mcp__* and ToolSearch from sub-agents with\nexplicit tools: lists. Only general-purpose agents get the full MCP\ncatalog. Update Merge Protocol + 7 stale-reference fixes (L212, L383,\nL481, L483, L552, L592-593, L610) to make the PO the merge owner for\nspecialized sub-agent types.")
```

(Pass the `\n` as real newlines via the MCP JSON string — do not paste literal `\n`.)

---

### Task 3: Update CLAUDE.md Workflow TL;DR pipeline

**Files:** 6 templates (`templates/{general,dotnet,dotnet-maui,rust-tauri,java,python}/CLAUDE.md`). `user-level-reference/CLAUDE.md` does NOT contain this section (verified) — excluded.

- [ ] **Step 1: Replace the per-workstream pipeline line.**

In each of the 6 CLAUDE.md files, find:

```markdown
**Per-workstream pipeline:** Developer -> Code Reviewer -> Tester -> Developer merges PR
```

Replace with:

```markdown
**Per-workstream pipeline:** Developer -> Code Reviewer -> Tester -> **PO merges PR** (PO performs the merge for specialized sub-agents — `coder`, `*-coder`, `tester`, `code-reviewer`, `test-writer` — because Claude Code strips `mcp__*` from agents with explicit `tools:` lists. For `general-purpose` developers declared with `tools: *`, the developer merges. See `AGENT_TEAM.md` → Merge Protocol.)
```

- [ ] **Step 2: Verify.**

```bash
for f in templates/general templates/dotnet templates/dotnet-maui templates/rust-tauri templates/java templates/python; do
  grep -c "PO merges PR" "$f/CLAUDE.md"   # expect 1
done
```

---

### Task 4: Update CLAUDE.md Spawn-Prompt Binding Table footnote

**Files:** same 6 as Task 3.

- [ ] **Step 1: Append a footnote after the binding table.**

In each file, find this exact line (last row of the table):

```markdown
| `code-reviewer` / `doc-generator` | *(none — omit the block; hook passes them through)* |
```

After this line, before the next heading or paragraph, insert (preserving a blank line above and below):

```markdown

> **Spawn-prompt rule for specialized sub-agents:** Do NOT include commit, push, PR-creation, PR-merge, or comment-posting instructions in spawn prompts for any sub-agent type listed in this table. Claude Code's dispatch strips `mcp__*` tools and `ToolSearch` from agents with explicit `tools:` lists, so the agent will fail any such call with "No such tool available". Have the agent return its work product (files written, review findings, verification report) and let the PO perform the git + GitHub I/O. Only `general-purpose` (declared with `tools: *`) is exempt.
```

- [ ] **Step 2: Verify.**

```bash
for f in templates/general templates/dotnet templates/dotnet-maui templates/rust-tauri templates/java templates/python; do
  grep -c "Spawn-prompt rule for specialized sub-agents" "$f/CLAUDE.md"   # expect 1
done
```

---

### Task 5: Update CLAUDE.md Commit Workflow → Merge ownership paragraph

**Files:** same 6 as Task 3.

- [ ] **Step 1: Replace the merge-ownership paragraph.**

In each file, find:

```markdown
**Merge ownership:** the developer who implemented the task owns the merge — rebase, CI-check, and squash-merge are the developer's job, not the PO's. The PO sequences merges across workstreams but does not merge on behalf of coders. See `AGENT_TEAM.md` → Merge Protocol.
```

Replace with:

```markdown
**Merge ownership:** depends on developer sub-agent type. For `general-purpose` developers (declared with `tools: *`), the developer owns the merge — rebase, CI-check, and squash-merge are the developer's job. For specialized sub-agents (`coder`, `*-coder`, `test-writer`, `tester`, `code-reviewer`), the **PO performs the merge** because Claude Code strips `mcp__*` and `ToolSearch` from agents with explicit `tools:` lists and the agent cannot call git or GitHub MCP tools. The PO sequences merges across workstreams. See `AGENT_TEAM.md` → Merge Protocol for the full table.
```

- [ ] **Step 2: Verify.**

```bash
for f in templates/general templates/dotnet templates/dotnet-maui templates/rust-tauri templates/java templates/python; do
  grep -c "PO performs the merge" "$f/CLAUDE.md"   # expect 1
done
```

- [ ] **Step 3: Commit Tasks 3+4+5 together.**

```
mcp__git-tools__git_add(repo_path="G:/git/claude-code-toolkit", paths=["templates/general/CLAUDE.md", "templates/dotnet/CLAUDE.md", "templates/dotnet-maui/CLAUDE.md", "templates/rust-tauri/CLAUDE.md", "templates/java/CLAUDE.md", "templates/python/CLAUDE.md"])
mcp__git-tools__git_commit(repo_path="G:/git/claude-code-toolkit", message="docs(claude-md): reflect merge ownership split for specialized subagents\n\nUpdate Workflow TL;DR pipeline, Spawn-Prompt Binding Table footnote, and\nCommit Workflow merge-ownership paragraph to make the PO the merge owner\nfor specialized sub-agents. See AGENT_TEAM.md → Merge Protocol.")
```

---

### Task 6: Update CLAUDE.local.md HARD REQUIREMENT sidebars

**Files:** 6 templates (`templates/{general,dotnet,dotnet-maui,rust-tauri,java,python}/CLAUDE.local.md`).

The 6 files diverge overall but the two anchor lines below are consistent (verified for general; pre-flight checks the rest).

- [ ] **Step 0: Pre-flight verify the anchor text is present in all 6 variants.**

```bash
for f in templates/general templates/dotnet templates/dotnet-maui templates/rust-tauri templates/java templates/python; do
  grep -c "For \\*\\*ANY git operation\\*\\*" "$f/CLAUDE.local.md"     # expect 1
  grep -c "For \\*\\*ANY GitHub operation\\*\\*" "$f/CLAUDE.local.md"  # expect 1
done
```

If any prints `0`, that variant has rewritten the section header — pause and report; the find-string needs a per-variant adjustment.

- [ ] **Step 1: Insert sidebar after the git-operations intro.**

In each file, find (the two-line intro):

```markdown
For **ANY git operation**, Claude MUST use MCP git tools
and MUST NOT use Bash git commands.
```

Replace with:

```markdown
For **ANY git operation**, Claude MUST use MCP git tools
and MUST NOT use Bash git commands.

> **Scope:** this rule binds the **PO main session**. Claude Code strips `mcp__*` from sub-agents with explicit `tools:` lists, so specialized sub-agents (`coder`, `*-coder`, `test-writer`, `tester`, `code-reviewer`) physically cannot call MCP git tools. They return their work to the PO; the PO performs the git operation. The Bash-git block hook in their definitions is intentional — there is no escape hatch by design.
```

- [ ] **Step 2: Insert sidebar after the GitHub-operations intro.**

In each file, find:

```markdown
For **ANY GitHub operation**, Claude MUST use MCP GitHub tools
and MUST NOT use shell commands (`gh`, `curl`) or direct HTTP calls.
```

Replace with:

```markdown
For **ANY GitHub operation**, Claude MUST use MCP GitHub tools
and MUST NOT use shell commands (`gh`, `curl`) or direct HTTP calls.

> **Scope:** this rule binds the **PO main session**. Specialized sub-agents cannot call `mcp__MCP_DOCKER__*` (dispatch strips it). They return findings/review/verification text to the PO; the PO posts the comment, opens the PR, or merges.
```

- [ ] **Step 3: Verify.**

```bash
for f in templates/general templates/dotnet templates/dotnet-maui templates/rust-tauri templates/java templates/python; do
  grep -c "Specialized sub-agents cannot call" "$f/CLAUDE.local.md"   # expect 1
  grep -c "Scope:.*this rule binds the.*PO main session" "$f/CLAUDE.local.md"   # expect 2 (one per sidebar)
done
```

- [ ] **Step 4: Commit.**

```
mcp__git-tools__git_commit(message="docs(claude-local): scope MCP git/GitHub rules to PO main session\n\nAdd sidebars under both HARD REQUIREMENT sections clarifying that the\nrule binds the PO. Specialized sub-agents have mcp__* stripped at\ndispatch and cannot call them; they return work to the PO.")
```

---

### Task 7: Clean up tester.md (drop ToolSearch and rewrite findings/rules)

**Files:**
- `templates/{general,dotnet,dotnet-maui,rust-tauri,java,python}/.claude/agents/tester.md`
- `user-level-reference/agents/tester.md`

7 byte-identical files; identical edits apply to all.

- [ ] **Step 1: Drop `ToolSearch` from the `tools:` line.**

Find:
```yaml
tools: Read, Write, Edit, Grep, Glob, Bash, ToolSearch
```

Replace with:
```yaml
tools: Read, Write, Edit, Grep, Glob, Bash
```

- [ ] **Step 2: Replace the Findings Format intro.**

Find:
```markdown
## Findings Format

Post findings directly to GitHub using `ToolSearch` to load `mcp__MCP_DOCKER__add_issue_comment`:
```

Replace with:
```markdown
## Findings Format

Return findings text to the PO. The PO posts the comment via `mcp__MCP_DOCKER__add_issue_comment` on your behalf. Format the report exactly as below so the PO can paste verbatim:
```

- [ ] **Step 3: Replace the Rules bullet (positive instructions only — no mention of stripped tools).**

Find:
```markdown
- Use `ToolSearch` to discover and use MCP GitHub tools for issue comments
- Use MCP git tools for git operations (never bash `git` commands)
```

Replace with:
```markdown
- Return findings text to the PO. The PO posts the comment via MCP on your behalf.
- Do not attempt git or GitHub operations directly — return what you observed in your final response and the PO will act on it.
```

- [ ] **Step 4: Verify.**

```bash
for f in templates/general/.claude/agents/tester.md templates/dotnet/.claude/agents/tester.md templates/dotnet-maui/.claude/agents/tester.md templates/rust-tauri/.claude/agents/tester.md templates/java/.claude/agents/tester.md templates/python/.claude/agents/tester.md user-level-reference/agents/tester.md; do
  echo "=== $f ==="
  grep -c "ToolSearch" "$f"                              # expect 0 (Step 1 dropped frontmatter; Steps 2/3 replaced both body refs)
  grep -c "Return findings text to the PO" "$f"          # expect 2 (Step 2 intro + Step 3 bullet — both contain the phrase)
done
```

Note: 2 (not 1) for "Return findings text to the PO" — both Step 2's intro replacement and Step 3's bullet replacement begin with that phrase. Verified by reading the actual replacement strings above.

---

### Task 8: Clean up code-reviewer.md (drop ToolSearch and rewrite "Posting Reviews")

**Files:**
- `templates/{general,dotnet,dotnet-maui,rust-tauri,java,python}/.claude/agents/code-reviewer.md`
- `user-level-reference/agents/code-reviewer.md`

7 byte-identical files.

- [ ] **Step 1: Drop `ToolSearch` from the `tools:` line.**

Find:
```yaml
tools: Read, Grep, Glob, ToolSearch
```

Replace with:
```yaml
tools: Read, Grep, Glob
```

- [ ] **Step 2: Replace the "Posting Reviews to GitHub" section (positive instructions only).**

Find:
```markdown
## Posting Reviews to GitHub

After completing your review, post it directly to GitHub:

1. Use `ToolSearch` to load `mcp__MCP_DOCKER__pull_request_review_write`
2. Create a review with method `create`, event `COMMENT`, and your full review body
3. If the MCP tool is unavailable, send your review findings to the team lead via message as a fallback
```

Replace with:
```markdown
## Returning Reviews to the PO

After completing your review, return your full review body in your final response. The PO posts the review to GitHub via `mcp__MCP_DOCKER__pull_request_review_write` (event `COMMENT`) on your behalf. Format the body so the PO can paste it verbatim — markdown, with explicit severity tags on each finding.
```

- [ ] **Step 3: Verify.**

```bash
for f in templates/general/.claude/agents/code-reviewer.md templates/dotnet/.claude/agents/code-reviewer.md templates/dotnet-maui/.claude/agents/code-reviewer.md templates/rust-tauri/.claude/agents/code-reviewer.md templates/java/.claude/agents/code-reviewer.md templates/python/.claude/agents/code-reviewer.md user-level-reference/agents/code-reviewer.md; do
  echo "=== $f ==="
  grep -c "ToolSearch" "$f"                       # expect 0
  grep -c "Returning Reviews to the PO" "$f"      # expect 1
done
```

- [ ] **Step 4: Commit Tasks 7+8 together.**

```
mcp__git-tools__git_commit(message="docs(agents): drop ToolSearch from tester/code-reviewer; route output via PO\n\nClaude Code strips ToolSearch from sub-agents with explicit tools: lists.\nAdvertising it was misleading. Body sections rewritten to instruct the\nagent to return findings/review text to the PO, who posts via MCP.")
```

---

### Task 9: Open PR and request user review

**Files:** none.

- [ ] **Step 1: Push the branch.**

```
mcp__git-tools__git_push(repo_path="G:/git/claude-code-toolkit", remote="origin", branch="<feature-branch>")
```

- [ ] **Step 2: Open the PR.**

```
mcp__MCP_DOCKER__create_pull_request(
  owner="dagonet",
  repo="claude-code-toolkit",
  title="docs: subagent merge-protocol fix (PO owns merge for specialized agents)",
  head="<feature-branch>",
  base="main",
  body=<see body below>
)
```

PR body:
```markdown
## Summary

Reconciles claude-code-toolkit docs and agent definitions with the empirically confirmed Claude Code dispatch rule: sub-agents with explicit `tools:` lists have `mcp__*` and `ToolSearch` stripped at runtime. Only `tools: *` (general-purpose) gets the full deferred MCP catalog.

Verified empirically in OmniScribe Sprint 8.1 (2026-05-03) with four probe sub-agents.

## Changes

- AGENT_TEAM.md (×6): Merge Protocol replaced + 7 stale-reference fixes (L212, L383, L481, L483, L552, L592-593, L610)
- CLAUDE.md (×6): Workflow TL;DR pipeline, Spawn-Prompt Binding Table footnote, Commit Workflow merge-ownership paragraph
- CLAUDE.local.md (×6): scope-clarifying sidebars under both HARD REQUIREMENT sections
- tester.md (×7): drop `ToolSearch` from `tools:`, rewrite Findings Format intro and Rules bullet to route output via PO
- code-reviewer.md (×7): drop `ToolSearch` from `tools:`, replace "Posting Reviews to GitHub" → "Returning Reviews to the PO"
- docs/workflow-audit.md (if Task 11 fires): patch any stale "developer merges/owns" references

## Out of scope

- No code changes
- No `settings.json` changes
- `test-writer.md`, `architect.md`, `requirements-engineer.md`, `doc-generator.md` — unaffected
- The `Bash(git *)` / `Bash(gh *)` PreToolUse hooks stay (correctly block the only remaining git/gh path for specialized sub-agents)

## Test plan

- [ ] Plugin sub-agent dispatch probe (Task 1) confirms `feature-dev:*` follows the same strip rule
- [ ] All `grep` verifications in Tasks 2–8 pass
- [ ] Task 11 conditional patch landed (or skipped with zero hits)
- [ ] OmniScribe Sprint 8.2 (or any subsequent T3 sprint) — PO performs git/GitHub I/O for specialized devs without surprise
```

- [ ] **Step 3: Wait for user review and merge approval.** Do not auto-merge.

---

### Task 10: After PR merges, sync user-level installs on this machine

**Files:**
- `C:\Users\DarkNite\.claude\agents\tester.md`
- `C:\Users\DarkNite\.claude\agents\code-reviewer.md`

- [ ] **Step 0: Confirm the PR has merged.**

```
mcp__git-tools__git_log(repo_path="G:/git/claude-code-toolkit", branch="main", max_count=5)
```

Look for the squash-merge commit message ("docs: subagent merge-protocol fix..."). Do not proceed if the PR has not merged.

- [ ] **Step 1: Pull main and confirm user-level-reference is updated.**

```
mcp__git-tools__git_checkout(repo_path="G:/git/claude-code-toolkit", branch="main")
mcp__git-tools__git_pull(repo_path="G:/git/claude-code-toolkit")
```

Verify via `mcp__plugin_context-mode_context-mode__ctx_execute`:
```bash
grep -c "Returning Reviews to the PO" G:/git/claude-code-toolkit/user-level-reference/agents/code-reviewer.md   # expect 1
```

- [ ] **Step 2: Diff the live install against user-level-reference.**

```bash
diff -q "C:/Users/DarkNite/.claude/agents/tester.md" "G:/git/claude-code-toolkit/user-level-reference/agents/tester.md"
diff -q "C:/Users/DarkNite/.claude/agents/code-reviewer.md" "G:/git/claude-code-toolkit/user-level-reference/agents/code-reviewer.md"
```

Expected: BOTH report a difference (the live install is stale until Step 3 copies). If either reports identical, the user has either pre-applied the change manually or the user-level-reference file did not update — pause and investigate.

- [ ] **Step 3: Copy user-level-reference over the live install.**

```bash
cp G:/git/claude-code-toolkit/user-level-reference/agents/tester.md C:/Users/DarkNite/.claude/agents/tester.md
cp G:/git/claude-code-toolkit/user-level-reference/agents/code-reviewer.md C:/Users/DarkNite/.claude/agents/code-reviewer.md
```

- [ ] **Step 4: Verify the live install carries the new text.**

```bash
grep -c "Return findings text to the PO" C:/Users/DarkNite/.claude/agents/tester.md         # expect 2
grep -c "Returning Reviews to the PO" C:/Users/DarkNite/.claude/agents/code-reviewer.md     # expect 1
```

---

### Task 11: Conditional README/docs patch (run after Task 8, before Task 9)

**Files:** zero or more — determined by the grep below.

- [ ] **Step 1: Grep for remaining stale references outside templates and historical plans.**

Use `Grep tool` with:
- `pattern: "developer\\s+(owns|merges|pushes)"`
- `path: "G:\\git\\claude-code-toolkit"`
- `glob: "**/*.md"`
- `output_mode: "files_with_matches"`

Filter out hits already covered: `templates/`, `docs/plans/`, this plan file itself.

Known target from R3 architect grep: **`G:\git\claude-code-toolkit\docs\workflow-audit.md`** is expected to match.

- [ ] **Step 2: Decide.**

If zero remaining hits → Task 11 is a no-op; mark completed and skip.
If ≥1 remaining hits → enumerate each, propose a replacement consistent with the merge-ownership-by-subagent-type framing, and execute as a sub-step. Patch each hit, then commit:

```
mcp__git-tools__git_commit(message="docs: align workflow-audit.md (and other docs) with merge-ownership split\n\nFollow-up to subagent merge-protocol fix; ensures non-template docs\ncarry the consistent framing.")
```

---

## Self-Review

**1. Spec coverage.** User asked for: (a) AGENT_TEAM.md merge protocol split — Task 2 ✓; (b) CLAUDE.md TL;DR pipeline change — Task 3 ✓; (c) Spawn-Prompt Binding Table footnote — Task 4 ✓; (d) drop ToolSearch from code-reviewer/tester — Tasks 7+8 ✓; (open question) plugin sub-agent probe — Task 1 ✓.

Bonus tasks justified: Task 5 (CLAUDE.md Commit Workflow paragraph — needed for Task 2 consistency), Task 6 (CLAUDE.local.md sidebars — prevents reader misinterpretation of the rule), Task 10 (user-level install sync — this machine carries stale text otherwise), Task 11 (conditional doc-wide consistency — fires only if grep finds hits).

**2. Placeholder scan.** Searched plan for "TBD", "TODO", "fill in", "appropriate". Found one `<feature-branch>` in Task 9 — that's the executor's PR-time choice, not a plan failure. All other steps contain exact text.

**3. Phrase consistency.** "Specialized sub-agents", "PO main session", "strips `mcp__*` and `ToolSearch`" used canonically across all touched files. Verified.

**4. Bug check (R3 finding).** Task 7 Step 4 grep count for "Return findings text to the PO" is **2** (Step 2 intro + Step 3 bullet both begin with that phrase). Confirmed by reading the replacement strings above.

---

## Out of scope (explicit)

- No code changes.
- No `settings.json` changes (universal MCP allowlist already correct).
- No `setup-project.ps1` / `setup-project.sh` changes (audited prior — they pass `tools:` through unchanged; no manifest hashing of frontmatter content).
- No changes to `Bash(git *)` / `Bash(gh *)` PreToolUse hooks (correctly block the only remaining git/gh path for specialized sub-agents).
- `architect.md`, `requirements-engineer.md`, `doc-generator.md`, `test-writer.md` — unaffected.
- `user-level-reference/CLAUDE.md` — verified to not contain the targeted sections; excluded from CLAUDE.md edits.
- Historical plans under `docs/plans/2026-04-*.md` — do not edit.

## Critical files

- `G:\git\claude-code-toolkit\docs\plans\2026-05-03-subagent-merge-protocol-fix.md` — the v1 plan; this consolidated v3 will overwrite it on approval.
- `templates/general/AGENT_TEAM.md` — exemplar with all 8 stale references (lines 212, 383, 481, 483, 552, 592, 593, 610).
- `templates/general/CLAUDE.md` and `templates/general/CLAUDE.local.md` — exemplars for the consistent CLAUDE.* edits.
- `templates/general/.claude/agents/tester.md` and `templates/general/.claude/agents/code-reviewer.md` — exemplars for the agent-file cleanups.
- `G:\git\claude-code-toolkit\docs\workflow-audit.md` — confirmed Task 11 target.
