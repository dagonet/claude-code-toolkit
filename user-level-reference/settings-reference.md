# Settings Reference (`~/.claude/settings.json`)

This document explains each section and setting in the user-level Claude Code settings file.

## Full Settings JSON

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_SHELL": "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
    "CLAUDE_CODE_DISABLE_1M_CONTEXT": "false",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000"
  },
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read",
      "Edit",
      "Write",
      "NotebookEdit",
      "WebSearch",
      "WebFetch(*)",
      "mcp__git-tools__*",
      "mcp__github-tools__*",
      "mcp__MCP_DOCKER__*",
      "mcp__ollama-tools__*",
      "mcp__plugin_playwright_playwright__*",
      "mcp__plugin_context7_context7__*",
      "mcp__searxng__*",
      "mcp__open-brain__*",
      "mcp__template-sync-tools__*",
      "mcp__plugin_context-mode_context-mode__*"
    ],
    "deny": [
      "Read(.env*)"
    ],
    "ask": [
      "Bash(npm publish*)"
    ],
    "defaultMode": "dontAsk"
  },
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<USERNAME>\\.claude\\statusline.ps1\""
  },
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "feature-dev@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "csharp-lsp@claude-plugins-official": true,
    "ralph-loop@claude-plugins-official": true,
    "playwright@claude-plugins-official": true,
    "claude-code-setup@claude-plugins-official": true,
    "rust-analyzer-lsp@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true,
    "context-mode@context-mode": true
  },
  "extraKnownMarketplaces": {
    "context-mode": {
      "source": {
        "source": "github",
        "repo": "mksglu/context-mode"
      }
    }
  },
  "alwaysThinkingEnabled": true,
  "enableAllProjectMcpServers": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/block-bash-vcs.sh; c=$?; if [ \"$c\" = \"127\" ]; then echo 'HOOK SCRIPT MISSING: ~/.claude/hooks/block-bash-vcs.sh -- enforcement offline.' >&2; exit 2; fi; exit $c"
          }
        ]
      }
    ]
  },
  "contextCompactionThreshold": 70
}
```

## Section-by-Section Explanation

### `env` -- Environment Variables

```json
"env": {
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
  "CLAUDE_CODE_SHELL": "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
  "CLAUDE_CODE_DISABLE_1M_CONTEXT": "false",
  "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000"
}
```

| Variable | Value | Purpose |
|----------|-------|---------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `"1"` | Enables the experimental Agent Teams feature, allowing multi-agent orchestration where specialized agents (architect, coder, tester, etc.) can collaborate on tasks. |
| `CLAUDE_CODE_SHELL` | Path to bash.exe | Overrides the default shell used by Claude Code's Bash tool. Points to Git Bash so Unix-style commands work on Windows. |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | `"false"` | Enables the 1M token context window on Opus 4.6/4.7 (claude.ai MAX plan). Must be a **string** (`"false"`), not JSON boolean. On Sonnet this has no effect — Sonnet caps at 200k on MAX. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `"1000000"` | Sets the **context window size** (not the compaction trigger). Must match the model's max context, otherwise it clamps `/context` to this value. For Opus 4.7 with 1M context, keep at `"1000000"`. Setting it lower (e.g. `"700000"`) collapses `/context` back to 200k — a misleading symptom. Use `contextCompactionThreshold` to control *when* compaction triggers. |

### `permissions` -- Tool Permission Rules

Controls which tools Claude Code can use without asking for confirmation.

#### `allow` -- Auto-approved tools

```json
"allow": [
  "Bash(*)",           // All Bash commands (unrestricted shell access)
  "Read",              // Read any file
  "Edit",              // Edit any file
  "Write",             // Write/create any file
  "NotebookEdit",      // Edit Jupyter notebooks
  "WebSearch",         // Search the web
  "WebFetch(*)",       // Fetch any URL
  "mcp__git-tools__*",                    // All git MCP tools (status, add, commit, diff, etc.)
  "mcp__github-tools__*",                 // GitHub helper tools (repo info, workflow list)
  "mcp__MCP_DOCKER__*",         // Full GitHub MCP (issues, PRs, reviews, etc.) — official plugin
  "mcp__ollama-tools__*",                 // Local LLM tools via Ollama (first-pass, JSON extract)
  "mcp__plugin_playwright_playwright__*", // Playwright browser automation (plugin)
  "mcp__plugin_context7_context7__*",     // Context7 documentation lookup (plugin)
  "mcp__searxng__*",                      // SearXNG web search
  "mcp__open-brain__*",                   // Open Brain persistent memory
  "mcp__template-sync-tools__*",          // Template sync MCP tools
  "mcp__plugin_context-mode_context-mode__*" // Context Mode plugin
]
```

**Note:** Language/framework-specific MCP servers (`dotnet-tools`, `rust-tools`, `sqlite`, `windows-mcp`, `godot-tools`) are **not** registered at user level. They belong to project-level `.claude/.mcp.json` files, generated by `setup-project.sh`/`setup-project.ps1` per variant. This keeps the user-level context minimal and loads language tools only in repos that actually need them. See `docs/architecture.md` → "MCP Layering" and `mcp-servers/HOWTO.md` → "Project-Level Servers".

#### `deny` -- Blocked tools

```json
"deny": [
  "Read(.env*)"  // Prevents Claude from reading .env files (which may contain secrets)
]
```

#### `ask` -- Require confirmation

```json
"ask": [
  "Bash(npm publish*)"  // Require explicit approval before publishing npm packages
]
```

#### `defaultMode`

```json
"defaultMode": "dontAsk"
```

When a tool is not listed in `allow`, `deny`, or `ask`, the default behavior is `dontAsk` -- meaning tools are auto-approved unless explicitly denied. This creates a permissive environment suited for trusted development workflows.

### `statusLine` -- Custom Status Bar

```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<USERNAME>\\.claude\\statusline.ps1\""
}
```

Runs a custom PowerShell script to display contextual information in the Claude Code status bar. The script can show git branch, project info, resource usage, or other dynamic context. The `-NoProfile` flag ensures fast execution by skipping the PowerShell profile.

### `enabledPlugins` -- Active Plugins

```json
"enabledPlugins": {
  "frontend-design@claude-plugins-official": true,
  "context7@claude-plugins-official": true,
  "code-review@claude-plugins-official": true,
  "feature-dev@claude-plugins-official": true,
  "code-simplifier@claude-plugins-official": true,
  "superpowers@claude-plugins-official": true,
  "claude-md-management@claude-plugins-official": true,
  "csharp-lsp@claude-plugins-official": true,
  "ralph-loop@claude-plugins-official": true,
  "playwright@claude-plugins-official": true,
  "claude-code-setup@claude-plugins-official": true
}
```

| Plugin | Purpose |
|--------|---------|
| `frontend-design` | Assists with frontend/UI design tasks |
| `context7` | Provides up-to-date library documentation lookup via Context7 |
| `code-review` | Enhanced code review capabilities |
| `feature-dev` | Feature development workflow support |
| `code-simplifier` | Suggests code simplifications and cleanup |
| `superpowers` | Extended Claude Code capabilities |
| `claude-md-management` | Manages CLAUDE.md project instruction files |
| `csharp-lsp` | C# Language Server Protocol integration for IntelliSense-like features |
| `ralph-loop` | Agentic loop for iterative development |
| `playwright` | Browser automation via Playwright MCP |
| `claude-code-setup` | Claude Code project setup assistance |
| `rust-analyzer-lsp` | Rust Language Server Protocol integration |
| `skill-creator` | Create, modify, and evaluate custom skills |
| `context-mode` | Offloads large tool outputs to sandbox, keeps context clean |

### `alwaysThinkingEnabled`

```json
"alwaysThinkingEnabled": true
```

Forces Claude to use extended thinking (chain-of-thought reasoning) on every request, even when not explicitly triggered. This produces more thorough and considered responses at the cost of slightly higher latency and token usage.

### `enableAllProjectMcpServers`

```json
"enableAllProjectMcpServers": true
```

Automatically enables all MCP servers defined in project-level `.mcp.json` files without requiring individual approval. This is convenient for repos that define their own MCP tooling.

### `contextCompactionThreshold`

```json
"contextCompactionThreshold": 70
```

Controls **when** auto-compact triggers — expressed as a percentage of the current context window. `70` fires compaction at 70% fill (e.g. 140k on a 200k window, 700k on a 1M window). Lower values compact earlier (preserve quality, more frequent summary loss); higher values preserve more history (risk of degradation near ceiling).

**Interaction with `CLAUDE_CODE_AUTO_COMPACT_WINDOW`:**
- `AUTO_COMPACT_WINDOW` sets the *window size* — must match the model's max context.
- `contextCompactionThreshold` sets the *trigger point* as a percentage of that window.
- To get 1M context with compaction at 700k: `AUTO_COMPACT_WINDOW="1000000"` + `contextCompactionThreshold: 70`.
- Do NOT try to tune behavior by lowering `AUTO_COMPACT_WINDOW` — that clamps the usable window (e.g. drops `/context` to 200k on Opus 4.7).

**Context rot tuning (1M context):** Opus 4.x retrieval accuracy visibly degrades past ~800k. `70` is the recommended balance. `50` (aggressive) for quality-first sessions; `83+` to ride closer to the ceiling at the cost of recall quality.

### `hooks` -- Workflow Automation Hooks

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "if": "Bash(git *)",
          "command": "echo 'BLOCKED: Use MCP git-tools instead of Bash git commands.' >&2; exit 2"
        }
      ]
    }
  ]
}
```

Hooks are shell commands that execute in response to Claude Code events. They enforce workflow rules mechanistically rather than relying on prompt instructions alone.

#### Hook Events

Events used by this toolkit:

| Event | When It Fires | Can Block? |
|-------|--------------|-----------|
| `PreToolUse` | Before a tool executes | Yes (exit code 2) |
| `PostToolUse` | After a tool succeeds | No (informational) |
| `SubagentStop` | When a subagent finishes | **Yes (exit code 2)** — `hooks/enforce-agent-contract.sh` relies on this to force one continuation when a coder stops without `## Gate Results` |
| `PreCompact` | Before context compaction | No (informational) |

**Agent-team lifecycle events — all available, none currently bound by this toolkit:**

| Event | When It Fires | Can Block? | Why it matters |
|-------|--------------|-----------|----------------|
| `Stop` | Main thread finishes its response | Yes | Fires even when a teammate merely idles — the only lead-side gate available. Stdin carries `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `stop_hook_active`. |
| `TeammateIdle` | A teammate is about to go idle | Yes | Fires at the exact moment a teammate would go silent without reporting. No documented loop-guard field — a hook here must carry its own. |
| `TaskCreated` / `TaskCompleted` | Task created / marked complete | Yes | `TaskCompleted` stdin carries `task_id`, `task_subject`, `task_description`, `teammate_name` — but **not** the task result, so it cannot judge report substance without reading the transcript itself. |
| `SubagentStart` | A subagent is spawned | — | Counterpart to `SubagentStop`. |

The authoritative list is the settings schema, not the docs — a bad event name fails validation and prints the full enum. Other available events: `PostToolUseFailure`, `PostToolBatch`, `Notification`, `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, `SessionEnd`, `StopFailure`, `PostCompact`, `PermissionRequest`, `PermissionDenied`, `Setup`, `Elicitation`, `ElicitationResult`, `ConfigChange`, `WorktreeCreate`, `WorktreeRemove`, `InstructionsLoaded`, `CwdChanged`, `FileChanged`, `DirectoryAdded`, `MessageDisplay`. There is no `TeammateStart`.

> **Hook config hot-reloads.** Editing a `hooks` block takes effect without restarting the session — verified by binding a new hook mid-session and seeing it fire on the next event.

**Measured stdin fields** (captured from a live log-only probe, since the docs are incomplete):

| Event | Fields beyond `session_id` / `transcript_path` / `cwd` / `hook_event_name` / `prompt_id` / `permission_mode` |
|-------|---|
| `Stop` | `stop_hook_active`, `effort`, `session_crons`, `last_assistant_message` (full final message text), `background_tasks` (`[{id, type, status, description}]`) |
| `TeammateIdle` | `teammate_name`, `team_name`. **No loop-guard field** — it fires again seconds later, so a blocking hook MUST keep its own ledger. `transcript_path` is the **lead's** transcript, which is where teammate messages land. `exit 2` blocks the idle and the stderr text is delivered **to the teammate**. |
| `TaskCreated` / `TaskCompleted` | `task_id`, `task_subject`, `task_description`. No `teammate_name`, no task result — cannot attribute a completion to a teammate or inspect its output. |
| `PreToolUse` | `tool_name`, `tool_input`, `tool_use_id`, `effort`, and — inside a subagent **or a named teammate** — `agent_id` and `agent_type`. Main-thread calls carry neither, which makes `agent_id` a sound main-vs-agent discriminator. |

> `background_tasks` reports `status: "running"` for a teammate that has already gone idle, and carries no `teammate_name`. Do not use `Stop` for idle detection — use `TeammateIdle`.

#### Key Fields

| Field | Description |
|-------|-------------|
| `matcher` | Tool name filter. Pipe-separated exact list (`Edit\|Write`) or regex (`mcp__.*`). Valid on **every** event, not just tool events. **To match all tools, omit `matcher` entirely** (or use `".*"`) — `"*"` is malformed regex, not a wildcard, despite being widely repeated as one. |
| `async` / `asyncRewake` | Run the hook in the background. `asyncRewake` additionally wakes the model when the hook exits 2 — a way to report a slow check without blocking the turn. |
| `if` | Permission rule syntax filter on tool arguments (`Bash(git *)`, `Edit(*.cs)`). Requires v2.1.85+. |
| `type` | Always `"command"` for shell hooks. |
| `command` | Shell command to execute. |
| `timeout` | Seconds before canceling (default: 600). |

#### Blocking Behavior

- **Exit code 0**: Hook ran successfully, tool proceeds. Stdout goes to debug log.
- **Exit code 2**: Tool call is **blocked**. Stderr is fed to Claude as an error message.
- **Other exit codes**: Non-blocking error. First line of stderr shown in transcript.

Hooks fire even when agents use `mode: bypassPermissions` — they enforce policy that cannot be bypassed.

#### User-Level vs Project-Level Hooks

- **User-level** (`~/.claude/settings.json`): Apply to all projects. Good for personal workflow enforcement (e.g., block `Bash(git *)` everywhere).
- **Project-level** (`.claude/settings.json`): Apply to one project. Good for language-specific gates (e.g., pre-commit format checks).

The example above shows the user-level Bash guard: it runs `hooks/block-bash-vcs.sh`, which blocks a command only when a sub-command's FIRST TOKEN is exactly `git` or `gh` and names the exact MCP replacement tool in the block message. Do NOT use the older inline `if: "Bash(git *)"` glob style at user level — its matcher is conservative on complex multi-line commands and fail-closes on false positives (observed blocking legitimate non-git commands). Install: copy `hooks/block-bash-vcs.sh` from the toolkit repo to `~/.claude/hooks/` and register it as shown.

**Exit-code semantics (important):** a hook command exiting with anything other than 0 or 2 — including **127 when the script file is missing** — is FAIL-OPEN: the tool call proceeds and only a non-blocking error is logged. That is why the example wraps the script call and converts 127 to exit 2 with a `HOOK SCRIPT MISSING` diagnostic; the project templates apply the same wrapper to every PreToolUse script hook. The one deliberate exception: the SubagentStop contract enforcer is NOT wrapped — a missing stop-gate must fail open, or a broken installation would block agents from ever stopping.

Project-level templates add additional hooks for format gates, build checks, pipeline tracking, and compaction snapshots. See `docs/templates.md` for per-template hook details.

#### Workflow Enforcement Hooks (Project-Level)

Templates include the following workflow enforcement hooks (via external scripts in `hooks/`):

**Gate before merge** (`hooks/gate-before-merge.sh`):
- Matcher: `mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge`
- Hard-blocks PR merges (and enabling auto-merge) unless a fresh gate artifact exists: `.gate/last-pass.json` must exist at the repo toplevel of the merging session's cwd (worktree-aware — developer agents self-merge from worktrees), its `sha` must equal the current HEAD, and the file must be younger than 60 minutes.
- No-op when PROJECT_CONTEXT.md has no `**Gate**:` / `**Gate Command**:` value or the value is still a `{{...}}` placeholder — same graceful degradation as `pre-commit-test.sh`.
- Also registered inline in the frontmatter of all merge-owning agents (`coder` + variant coders) as belt-and-suspenders, since subagent hook inheritance from `settings.json` is undocumented.
- Block message: "Run 'bash hooks/run-gate.sh' on the PR branch head."

**Run gate** (`hooks/run-gate.sh`) — companion runner, NOT registered as a hook:
- Invoked by developers/PO as `bash hooks/run-gate.sh`.
- Reads the Gate command from PROJECT_CONTEXT.md (tolerates `- ` list markers, the `**Gate Command**:` label style, and backtick-wrapped commands), runs it, and on success writes `.gate/last-pass.json` (`{"sha","branch","ts","status":"pass"}`) and prints `GATE PASS <sha>`. On failure it deletes the artifact and exits nonzero.
- `.gate/` is gitignored by all templates.

**No push to main** (`hooks/no-push-main.sh`):
- Matcher: `mcp__git-tools__git_push`
- Blocks pushes to `main` or `master` branches. Resolves implicit branch via `git branch --show-current` when the `branch` parameter is omitted.
- Message: "Use a feature branch and create a PR."

**Tier before coder** (`hooks/tier-before-coder.sh`):
- Matcher: `Agent`
- Only blocks coder types (`coder`, `dotnet-coder`, `java-coder`, `python-coder`, `rust-coder`). All other agent types pass through.
- Requires a plan file (in `docs/plans/` or `~/.claude/plans/`) containing both a tier declaration (`Tier: T[1-4]`) and evidence of architect challenge (word "challenge" or "architect").
- Two distinct block messages: "No plan with tier declaration found" vs "Plan has tier but no evidence of architect challenge."

**Require skills block** (`hooks/require-skills-block.sh`):
- Matcher: `Agent`
- Enforces the AGENT_TEAM.md *Spawn-Prompt Binding Table* — when the PO spawns a `Task` whose `subagent_type` is bound (`coder` and variants, `tester`, `test-writer`, `architect`, `requirements-engineer`), the prompt body must contain a literal `## Required Skills` line listing the skills that subagent must invoke before task work.
- Pass-through types: `code-reviewer`, `doc-generator` (no required skills), and any `subagent_type` not in the binding table (e.g. `general-purpose`, `Explore`, `Plan`).
- Block diagnostic prints the expected skill list plus a copy-pasteable `## Required Skills` block for the PO to drop into the prompt.
- DRIFT WARNING: the hook's case statement duplicates the AGENT_TEAM.md table. `scripts/verify-template-consistency.sh` diffs the two and fails CI if they diverge — keep them in sync.

All of these hooks use `node -e` for JSON parsing (no `jq` dependency) and are copied to target projects by the setup script. Hook stdin nests tool arguments under `.tool_input`; the scripts read `.tool_input.<field>` with a top-level fallback for older harnesses. See `docs/hook-enforcement-ideas.md` for the full evaluation of which workflow rules are enforceable via hooks.

#### Optional User-Level Install for `require-skills-block.sh`

The hook is wired into all 6 project templates by default. To also enforce it at the user level (so it covers projects that don't use these templates), copy the script and add the matcher group:

1. Copy `hooks/require-skills-block.sh` from this repo to `~/.claude/hooks/require-skills-block.sh` and `chmod +x` it.
2. Append the stanza below to the existing `hooks.PreToolUse` array in `~/.claude/settings.json` (do not replace the whole `hooks` block).
3. Start a new Claude Code session.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/require-skills-block.sh"
          }
        ]
      }
    ]
  }
}
```

**Rollback:** remove the matcher group and start a new session. **Caveat:** if a project's binding table differs from the user-level hook's hardcoded one, the user-level hook may either over-block (blocks valid project spawns) or under-block (passes prompts the project considers invalid). Project-level installation is the safer default.

### Read Size Gate (PreToolUse, User-Level Recommended)

**Read size gate** (`hooks/read-size-gate.sh`):
- Matcher: `Read`
- Blocks `Read` calls whose **effective line count** exceeds a threshold (default `500`). `effective_lines = min(file_line_count, limit or file_line_count)`, so `Read(big.py, limit=100)` allows and `Read(big.py, limit=750)` blocks.
- Missing/unreadable files pass through — the hook does not police file existence.
- Rationale: the Read tool accounts for ~22% of session context per `docs/plans/2026-04-14-context-baseline.md` — the single largest actionable bucket. The CLAUDE.md "Read tool discipline" bullet asks agents to prefer `ctx_execute_file` / Explore subagents for analysis; this hook enforces it mechanically.
- Block diagnostic directs the agent to (1) `mcp__plugin_context-mode_context-mode__ctx_execute_file` for analysis, (2) Explore subagent for compressed summaries, or (3) range-targeted `Read(path, offset, limit<=500)` for Edit workflows.
- No bypass flag. If the hook misfires on legitimate work, the fix is to raise the threshold or comment out the stanza in `~/.claude/settings.json`.
- Appends tab-separated decisions to `~/.claude/state/read-size-gate.log` (BLOCK always; ALLOW only when `file_line_count > 250`). Log append is best-effort — write failures never mask the block/allow decision.
- Uses `node -e` for JSON parsing (no `jq` dependency). Style-matches `tier-before-coder.sh`.

**Recommended install scope: user-level** (`~/.claude/settings.json`). The 22% Read-tool share is paid in target-project sessions, not in `claude-code-toolkit` self-maintenance. Installing at user level covers every project the user opens.

**Install steps:**

1. Copy script to `~/.claude/hooks/read-size-gate.sh` (create the directory if needed) and `chmod +x` it. The canonical source is `hooks/read-size-gate.sh` in this repo; the `user-level-reference/hooks/read-size-gate.sh` mirror is the "paste from here" copy.
2. Merge the stanza below into `~/.claude/settings.json`. If a `hooks.PreToolUse` array already exists, append this matcher group to it; do **not** replace the whole `hooks` block.
3. Start a new Claude Code session — settings reload is session-scoped.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/read-size-gate.sh"
          }
        ]
      }
    ]
  }
}
```

**Rollback:** comment out or remove the matcher group from `~/.claude/settings.json` and start a new session.

**Threshold tuning:** the script hard-codes `THRESHOLD=500` near the top. Edit the value directly. The log at `~/.claude/state/read-size-gate.log` provides per-decision data for post-sprint histogramming if you want to calibrate the threshold from real use rather than a gut number.

### Plan-Mode Allow Hook for context-mode Tools (PreToolUse, User-Level)

**Problem:** plan mode overrides `permissions.allow` rules for tools it does not classify as read-only. `mcp__plugin_context-mode_context-mode__*` in the allow list does NOT stop plan mode from prompting on every `ctx_*` call (same mechanism that keeps `Edit` blocked in plan mode despite an `Edit` allow rule). The docs are silent on this precedence — verified empirically 2026-07-09.

**Fix:** PreToolUse hooks run BEFORE the permission system; a hook emitting `permissionDecision: "allow"` bypasses the prompt in every mode, including plan mode.

**Hook** (`hooks/allow-ctx-plan.sh`): stateless — prints the allow JSON and exits 0. Deliberately NOT 127-wrapped: if the script is missing, the hook fails open and the prompts simply return (wrapping an *allow* hook would convert absence into a block — wrong polarity).

**Install:** copy `hooks/allow-ctx-plan.sh` to `~/.claude/hooks/`, then append this matcher group to `hooks.PreToolUse` in `~/.claude/settings.json`:

```json
{
  "matcher": "mcp__plugin_context-mode_context-mode__ctx_batch_execute|mcp__plugin_context-mode_context-mode__ctx_execute|mcp__plugin_context-mode_context-mode__ctx_execute_file|mcp__plugin_context-mode_context-mode__ctx_search|mcp__plugin_context-mode_context-mode__ctx_fetch_and_index|mcp__plugin_context-mode_context-mode__ctx_index|mcp__plugin_context-mode_context-mode__ctx_stats|mcp__plugin_context-mode_context-mode__ctx_doctor|mcp__plugin_context-mode_context-mode__ctx_upgrade",
  "hooks": [
    { "type": "command", "command": "bash 'C:/Users/DarkNite/.claude/hooks/allow-ctx-plan.sh'" }
  ]
}
```

**Caveats:** (1) `ctx_execute`/`ctx_batch_execute` run sandbox shell code that CAN write files — auto-approving them weakens plan mode's no-writes guarantee. Accepted trade-off: the user approved every one of these prompts manually anyway. (2) Three tools (`ctx_execute`, `ctx_execute_file`, `ctx_batch_execute`) also match the context-mode plugin's own tip-injection PreToolUse group — both hooks fire; the allow decision answers the permission question, the tip context still injects.

**Fallback:** if a Claude Code update stops PreToolUse `allow` from piercing plan mode, re-register the same script under the `PermissionRequest` event with `"command": "EVENT=permission-request bash '...allow-ctx-plan.sh'"` — the script then emits `{"decision":{"behavior":"allow"}}`, the PermissionRequest-shaped decision.

**Rollback:** remove the matcher group and start a new session.

### Delegation Enforcement (PreToolUse, Project-Level — templates)

**`hooks/enforce-delegation.sh`** — the PO (main thread) never does hands-on work; sub-agents do all coding/building/testing. Registered in every template `settings.json` under TWO PreToolUse matcher groups: `Edit|Write|NotebookEdit` and `Bash`.

- **Discriminator:** the hook stdin contains `agent_id` ONLY when the call originates inside a subagent — subagent calls always pass; main-thread calls are checked.
- **Main-thread edits** are allowed only on the PO write surface (`docs/plans/`, `PROJECT_STATE.md`, `PROJECT_CONTEXT.md`, `.claude/`, `CLAUDE.md`, `CLAUDE.local.md`, `AGENT_TEAM.md`, paths outside the repo). Everything else denies with a model-visible DELEGATE message naming the right agent. Handles `notebook_path` (NotebookEdit) and backslash Windows paths.
- **Main-thread Bash** denies build/test-runner commands (`npm test`, `npm run test|build|e2e|coverage`, `npx vitest|jest|playwright`, `pytest`, `cargo test|build|run`, `dotnet build|test|run`, `mvn`, `gradlew`, `go test`) AND `hooks/run-gate.sh` — the PO verifies via the `.gate/last-pass.json` artifact, never by running the suite.
- **Kill-switch:** create `.claude/delegation-off` at the repo root to disable (also the recovery if a pre-`agent_id` CLI ever denies subagent calls).
- **Failure polarity — deliberately fail-OPEN:** never apply the exit-2 127-wrapper (a missing script would block ALL edits including subagents' — total paralysis, same class as the SubagentStop stop-gate). Registration uses a **WARN-wrapper** instead: on 127 it prints `WARN: ... delegation enforcement offline. Run /sync-template.` to stderr and exits 0 — visible, never blocking. Internal parse failures pass through. Note: main-thread Bash-git stays guarded regardless — `block-bash-vcs.sh` (fail-closed) fires on the same Bash matcher.
