# Settings Reference (`~/.claude/settings.json`)

This document explains each section and setting in the user-level Claude Code settings file.

## Full Settings JSON

Verbatim copy of `user-level-reference/settings.json` in this repo (v2.0). Personal additions are deliberately excluded: no `statusLine`, no third-party marketplaces or their plugins, no project-specific permission entries.

```json
{
  "env": {
    "CLAUDE_CODE_SHELL": "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
    "CLAUDE_CODE_DISABLE_1M_CONTEXT": "false",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000",
    "ENABLE_PROMPT_CACHING_1H": "1",
    "CLAUDE_CODE_USE_POWERSHELL_TOOL": "1"
  },
  "permissions": {
    "allow": [
      "Bash(bash hooks/run-gate.sh*)",
      "Read",
      "Edit",
      "Write",
      "NotebookEdit",
      "WebSearch",
      "mcp__github-tools__*",
      "mcp__github__*",
      "mcp__MCP_DOCKER__*",
      "mcp__ollama-tools__*",
      "mcp__open-brain__*",
      "mcp__template-sync-tools__*",
      "mcp__searxng__*",
      "mcp__dotnet-tools__*",
      "mcp__rust-tools__*",
      "mcp__sqlite__*",
      "mcp__windows-mcp__*",
      "mcp__godot-tools__*",
      "mcp__plugin_context7_context7__*",
      "mcp__plugin_playwright_playwright__*",
      "mcp__plugin_context-mode_context-mode__*"
    ],
    "deny": [
      "mcp__git-tools__git_push",
      "mcp__git-tools__git_commit",
      "mcp__git-tools__git_revert",
      "mcp__git-tools__git_merge",
      "mcp__git-tools__git_rebase",
      "mcp__git-tools__git_reset",
      "mcp__git-tools__git_push_tags"
    ],
    "ask": [
      "Bash(npm publish*)"
    ],
    "defaultMode": "auto"
  },
  "autoMode": {
    "environment": [
      "$defaults",
      "**Primary use**: software development in private repos under G:/git; PO/subagent workflow with hook-enforced gates",
      "**Trusted repos**: the working directory's repo and its `origin` remote only",
      "**Sensitive remote targets**: any name carrying `prod`/`production` as a whole word or segment"
    ]
  },
  "enableAllProjectMcpServers": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/no-push-main.sh; c=$?; if [ \"$c\" = \"127\" ]; then echo 'HOOK SCRIPT MISSING: ~/.claude/hooks/no-push-main.sh -- enforcement offline.' >&2; exit 2; fi; exit $c"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/bash-output-guard.sh"
          }
        ]
      }
    ]
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "frontend-design@claude-plugins-official": false,
    "feature-dev@claude-plugins-official": false,
    "code-simplifier@claude-plugins-official": false,
    "claude-md-management@claude-plugins-official": false,
    "ralph-loop@claude-plugins-official": false,
    "claude-code-setup@claude-plugins-official": false,
    "skill-creator@claude-plugins-official": true,
    "chrome-devtools-mcp@claude-plugins-official": false
  },
  "alwaysThinkingEnabled": true,
  "advisorModel": "opus",
  "autoCompactEnabled": true,
  "contextCompactionThreshold": 70
}
```

## Section-by-Section Explanation

### `env` -- Environment Variables

> **Removed in v2.0:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Agent teams are experimental and off by default; every measured stall in six weeks of transcripts came from a named teammate, while Agent-tool spawns never stalled. Parallelism now comes from parallel Agent calls, so the flag is gone — delete it from your own `~/.claude/settings.json` too.

> **Kept deliberately in v2.0:** `CLAUDE_CODE_DISABLE_1M_CONTEXT` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. They are *not* redundant on the MAX plan — without both, `/context` clamps back to 200k on a 1M-capable model. Leave them set.

| Variable | Value | Purpose |
|----------|-------|---------|
| `CLAUDE_CODE_SHELL` | Path to bash.exe | Overrides the default shell used by Claude Code's Bash tool. Points to Git Bash so Unix-style commands work on Windows. |
| `ENABLE_PROMPT_CACHING_1H` | `"1"` | Extends prompt-cache TTL to one hour — worth it for long orchestrator sessions that re-send a large stable prefix. |
| `CLAUDE_CODE_USE_POWERSHELL_TOOL` | `"1"` | Exposes the dedicated `PowerShell` tool alongside `Bash` on Windows. Hook matchers in this file use `Bash\|PowerShell` so both are covered. |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | `"false"` | Enables the 1M token context window on Opus 4.6/4.7 (claude.ai MAX plan). Must be a **string** (`"false"`), not JSON boolean. On Sonnet this has no effect — Sonnet caps at 200k on MAX. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `"1000000"` | Sets the **context window size** (not the compaction trigger). Must match the model's max context, otherwise it clamps `/context` to this value. For Opus 4.7 with 1M context, keep at `"1000000"`. Setting it lower (e.g. `"700000"`) collapses `/context` back to 200k — a misleading symptom. Use `contextCompactionThreshold` to control *when* compaction triggers. |

### `permissions` -- Tool Permission Rules

Controls which tools Claude Code can use without asking for confirmation.

#### `allow` -- Auto-approved tools

See the *Full Settings JSON* block above for the current list. Three entries were **removed in v2.0 PR1** and must not come back:

| Removed | Why |
|---|---|
| `Bash(*)` | Blanket shell approval defeated every gate. The only Bash entry left is `Bash(bash hooks/run-gate.sh*)`; everything else goes through `defaultMode: auto` plus the guard hooks, which *gate* the git/`gh` CLI rather than ban it. |
| `WebFetch(*)` | Unbounded fetch is the largest single context-flood vector. Use `WebSearch`, or an explicit approval. |
| `mcp__git-tools__*` | The MCP-git mandate is gone; native `git` is the supported path and is gated by `no-push-main.sh` + `gate-before-merge.sh`. |

**Note:** Language/framework-specific MCP servers (`dotnet-tools`, `rust-tools`, `sqlite`, `windows-mcp`, `godot-tools`) are **not** registered at user level. They belong to project-level `.mcp.json` (repo root) files, generated by `setup-project.sh`/`setup-project.ps1` per variant. This keeps the user-level context minimal and loads language tools only in repos that actually need them. See `docs/architecture.md` → "MCP Layering" and `mcp-servers/HOWTO.md` → "Project-Level Servers".

#### `deny` -- Blocked tools

```json
"deny": [
  // v3.0.3: NO `Read(...)` entries. The six `Read(.env…)` names that used to
  // live here were replaced by `hooks/deny-secret-reads.sh` on PreToolUse
  // `Read|Bash`. Deny rules are evaluated BEFORE the classifier, and a
  // read-only command with a RELATIVE path after a `cd` cannot be statically
  // proven not to hit one — so the harness prompted on ordinary reads and auto
  // mode could not approve. A hook deny answers per call and does not trigger
  // that static check. The MCP entries below have no such problem: a tool name
  // is exact, so nothing has to be proven about a path.
  "mcp__git-tools__git_push", "mcp__git-tools__git_commit",
  "mcp__git-tools__git_revert", "mcp__git-tools__git_merge",
  "mcp__git-tools__git_rebase", "mcp__git-tools__git_reset",
  "mcp__git-tools__git_push_tags"
]
```

#### `ask` -- Require confirmation

```json
"ask": [
  "Bash(npm publish*)"  // Require explicit approval before publishing npm packages
]
```

#### `defaultMode` (inside `permissions`) and `autoMode` (top level)

`defaultMode` lives inside `permissions`. **`autoMode` does not — it is a top-level key**, a sibling of `permissions`, with `environment`, `allow`, `soft_deny`, and `hard_deny` members. Nesting it under `permissions` silently does nothing.

```json
"permissions": { "…": "…", "defaultMode": "auto" },
"autoMode": {
  "environment": [
    "$defaults",
    "**Primary use**: software development in private repos under G:/git; PO/subagent workflow with hook-enforced gates",
    "**Trusted repos**: the working directory's repo and its `origin` remote only",
    "**Sensitive remote targets**: any name carrying `prod`/`production` as a whole word or segment"
  ]
}
```

`auto` replaces the old `dontAsk`. Instead of blanket-approving everything not explicitly denied, a classifier model decides per call whether the action is safe *in this environment*. `autoMode.environment` is the prose it reasons over — plain sentences, not a rule grammar. `$defaults` keeps the built-in entries and your lines are appended, so you describe only what is specific to your machine.

Three things about `autoMode` that are easy to get wrong:

- **Scope is User/managed only.** A project `.claude/settings.json` cannot ship an `autoMode` block; it is ignored there. Trust boundaries belong to the operator, not to a checked-in repo — which is exactly the right polarity, since a hostile repo could otherwise widen its own trust.
- **Do not route the classifier through a model proxy.** It needs the real model. Running it through `cc-proxy` (or any alias-rewriting proxy) produced **83 classifier outages** in the measured window, each degrading auto mode to prompting. If you run a proxy, exempt the classifier — the same exemption `advisorModel` needs.
- **Prose quality is the control surface.** Vague lines ("be careful with prod") classify worse than the concrete phrasing above. Say which repos are trusted and what a sensitive target looks like.

- **Auto mode PAUSES on a counter, and that reads exactly like a config problem (v3.0.3).** From the docs, verbatim: *"if the classifier blocks an action 3 times in a row or 20 times total, auto mode pauses and Claude Code resumes prompting. Approving the prompted action resumes auto mode. These thresholds are not configurable."* A session that hit a bad `environment` therefore keeps prompting **after** the environment is fixed, until one prompt is approved — and re-pauses within three blocks if it is still holding the old environment in memory. Restart the session; do not re-edit the settings.

`deny` still wins over everything. Since v3.0.3 the `.env` protection is **not** a deny rule but `hooks/deny-secret-reads.sh` — see the `deny` section above for why a `Read(...)` rule cost auto mode on every relative-path read.

### `statusLine` -- Custom Status Bar

**Not shipped in this reference.** `statusLine` is a per-machine cosmetic setting (it usually points at an absolute path to a local script), so it is deliberately excluded here. If you want one, add it to your own `~/.claude/settings.json`; a `type: "command"` entry runs a script whose stdout becomes the status bar, and `-NoProfile` keeps a PowerShell one fast.

### `enabledPlugins` -- Active Plugins

See the *Full Settings JSON* block above for the shipped values. Only four are on; every plugin costs context at session start whether or not it is used, so the default is `false`.

| Plugin | Shipped | Purpose |
|--------|---------|---------|
| `superpowers` | on | The skill set the toolkit actually binds — `brainstorming`, `systematic-debugging`, `verification-before-completion`, `writing-plans`, `test-driven-development`, `requesting`/`receiving-code-review`. All 493 measured skill invocations were these plus `karpathy-guidelines`. |
| `code-review` | on | Provides `/code-review`, the replacement for the toolkit's deleted `code-review` and `security-audit` skills. |
| `context7` | on | Up-to-date library documentation lookup. |
| `skill-creator` | on | **Enabled in v2.0 PR5.** Ships skill scaffolding, `evals/evals.json` authoring, LLM grading, and benchmarking — the replacement for the toolkit's deleted `/skill-eval` and `/skill-improve` commands and its hand-rolled eval convention. |
| `frontend-design`, `feature-dev`, `code-simplifier`, `claude-md-management`, `ralph-loop`, `claude-code-setup`, `chrome-devtools-mcp` | off | Unused in six weeks of measured sessions. Turn one on when you have a reason, not by default. |
| `context-mode` (third-party) | not shipped | Optional. It lives on a non-official marketplace, so neither it nor its `extraKnownMarketplaces` entry is part of this reference. `permissions.allow` still carries its tool prefix, which is a harmless no-op when the plugin is absent. |

### `alwaysThinkingEnabled`

```json
"alwaysThinkingEnabled": true
```

Forces extended thinking on every request. **No effect on Fable 5 / Claude 5 generation models** — they reason by default and decide per step how hard to think; the effort level is the dial that matters. Kept because it still applies when the session runs an older model; harmless otherwise.

### `enableAllProjectMcpServers`

```json
"enableAllProjectMcpServers": true
```

Automatically enables all MCP servers defined in project-level `.mcp.json` files without requiring individual approval. This is convenient for repos that define their own MCP tooling.

**Why this is safe now: `ENABLE_TOOL_SEARCH`.** Claude Code defers MCP tool definitions by default — the model is given a tool-search facility and pulls a server's schemas only when it needs them, instead of paying for every registered tool in the session prefix. That removes the tool-bloat problem that motivated context-mode's "route everything through the sandbox" mandate, which is why v2.0 demotes context-mode to optional. Enabling a server you rarely use now costs approximately nothing at startup.

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

Hooks are shell commands that execute in response to Claude Code events. They enforce workflow rules mechanistically rather than relying on prompt instructions alone.

**The v2.0 user-level hook set** (see the *Full Settings JSON* block for exact registration):

| Hook | Event / matcher | Polarity | What it does |
|---|---|---|---|
| `no-push-main.sh` | `PreToolUse` on `Bash\|PowerShell` | fail-**closed** (127 → exit 2) | Blocks a push to `main`/`master`, resolving the implicit branch when none is named. v2.0 PR1 moved it onto the Bash matcher because native `git push` is now the supported path. |
| `bash-output-guard.sh` | `PostToolUse` on `Bash\|PowerShell` | unwrapped (cannot block) | Truncates oversized stdout/stderr into a temp log and returns a head/tail excerpt. |
| `read-size-gate.sh` | `PreToolUse` on `Read` | fail-**open** | Caps an unbounded `Read` at 500 lines and tells the model the next offset. Recommended user-level install — see below. |

**Retired in v2.1:** `tier-before-coder.sh`. The plan gate is gone — plans are optional artifacts and every spawn carries its task brief instead. Delete the script from `~/.claude/hooks/` and its `Agent` matcher entry from `~/.claude/settings.json`; left registered, it fails closed on a missing script and blocks every coder spawn.

**Retired at user level in v2.0, deleted in v2.1:** the blanket Bash-git block. PR1 replaced "ban the git CLI" with "gate it" — `no-push-main.sh` and the project-level `gate-before-merge.sh` stop the dangerous operations, and everything else runs natively. If you still have the old blanket-block registered, remove it; it now blocks the supported workflow.

Copy every referenced script into `~/.claude/hooks/` before installing this `settings.json` — the canonical source is the toolkit root `hooks/` directory.

#### Hook Events

Events used by this toolkit:

| Event | When It Fires | Can Block? |
|-------|--------------|-----------|
| `PreToolUse` | Before a tool executes | Yes (exit code 2) |
| `PostToolUse` | After a tool succeeds | No (informational) |
| `SubagentStop` | When a subagent finishes | **Yes (exit code 2)** — `hooks/enforce-agent-contract.sh` relies on this to force one continuation when a coder stops without `## Gate Results` |
| `PreCompact` | Before context compaction | No (informational) |

**Other lifecycle events — available, mostly unbound by this toolkit:**

| Event | When It Fires | Can Block? | Why it matters |
|-------|--------------|-----------|----------------|
| `Stop` | Main thread finishes its response | Yes | The only lead-side gate available. Stdin carries `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `stop_hook_active`. |
| `SessionStart` | A session begins | — | **Bound in v2.0** to `hooks/retro-brief.sh`; stdout is injected into the session context. |
| `TaskCreated` / `TaskCompleted` | Task created / marked complete | Yes | `TaskCompleted` stdin carries `task_id`, `task_subject`, `task_description` — but **not** the task result, so it cannot judge report substance without reading the transcript itself. |
| `SubagentStart` | A subagent is spawned | — | Counterpart to `SubagentStop`. |

The authoritative list is the settings schema, not the docs — a bad event name fails validation and prints the full enum. Other available events: `PostToolUseFailure`, `PostToolBatch`, `Notification`, `UserPromptSubmit`, `UserPromptExpansion`, `SessionEnd`, `StopFailure`, `PostCompact`, `PermissionRequest`, `PermissionDenied`, `Setup`, `Elicitation`, `ElicitationResult`, `ConfigChange`, `WorktreeCreate`, `WorktreeRemove`, `InstructionsLoaded`, `CwdChanged`, `FileChanged`, `DirectoryAdded`, `MessageDisplay`.

> **Hook config hot-reloads.** Editing a `hooks` block takes effect without restarting the session — verified by binding a new hook mid-session and seeing it fire on the next event.

**Measured stdin fields** (captured from a live log-only probe, since the docs are incomplete):

| Event | Fields beyond `session_id` / `transcript_path` / `cwd` / `hook_event_name` / `prompt_id` / `permission_mode` |
|-------|---|
| `Stop` | `stop_hook_active`, `effort`, `session_crons`, `last_assistant_message` (full final message text), `background_tasks` (`[{id, type, status, description}]`) |
| `TaskCreated` / `TaskCompleted` | `task_id`, `task_subject`, `task_description`. No task result — cannot inspect a completion's output without reading the transcript. |
| `SubagentStop` | `agent_id`, `agent_type`, `agent_transcript_path` (the SUBAGENT's own JSONL, not the session's), `last_assistant_message`. This is what `hooks/retro-ledger.sh` reads. |
| `PreToolUse` | `tool_name`, `tool_input`, `tool_use_id`, `effort`, and — inside a subagent — `agent_id` and `agent_type`. Main-thread calls carry neither, which makes `agent_id` a sound main-vs-agent discriminator. |

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

- **User-level** (`~/.claude/settings.json`): Apply to all projects. Good for personal workflow enforcement that is true everywhere (never push to main, cap oversized reads).
- **Project-level** (`.claude/settings.json`): Apply to one project. Good for language-specific gates (e.g., pre-commit format checks) and for anything that references a repo-relative path such as `hooks/run-gate.sh`.

A user-level hook may only reference scripts and paths that exist in *every* repo — a fail-closed hook pointing at a repo-scoped script turns every unrelated project into a paralysed session. Do NOT use the inline `if: "Bash(git *)"` glob style at user level: its matcher is conservative on complex multi-line commands and fail-closes on false positives (observed blocking legitimate non-git commands). Prefer a script that parses the command itself.

**Exit-code semantics (important):** a hook command exiting with anything other than 0 or 2 — including **127 when the script file is missing** — is FAIL-OPEN: the tool call proceeds and only a non-blocking error is logged. That is why the example wraps the script call and converts 127 to exit 2 with a `HOOK SCRIPT MISSING` diagnostic; the project templates apply the same wrapper to every PreToolUse script hook. The one deliberate exception: the SubagentStop contract enforcer is NOT wrapped — a missing stop-gate must fail open, or a broken installation would block agents from ever stopping.

Project-level templates add additional hooks for format gates, build checks, pipeline tracking, and compaction snapshots. See `docs/templates.md` for per-template hook details.

#### Workflow Enforcement Hooks (Project-Level)

Templates include the following workflow enforcement hooks (via external scripts in `hooks/`):

**Gate before merge** (`hooks/gate-before-merge.sh`):
- Matcher: `mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge`
- Hard-blocks PR merges (and enabling auto-merge) unless a fresh gate artifact exists: `.gate/last-pass.json` must exist at the repo toplevel of the merging session's cwd (worktree-aware — developer agents self-merge from worktrees), and the file must be younger than 60 minutes. Accepted if either its `sha` equals the current HEAD, or its `tree` equals `HEAD^{tree}` (the commit-time `run-gate.sh` chain: the gate ran against the index just before the commit, so its `sha` is the parent commit but its `tree` is already the new commit's).
- No-op when PROJECT_CONTEXT.md has no `**Gate**:` / `**Gate Command**:` value or the value is still a `{{...}}` placeholder — same graceful degradation as `pre-commit-test.sh`.
- Also registered inline in the frontmatter of all merge-owning agents (`coder` + variant coders) as belt-and-suspenders, since subagent hook inheritance from `settings.json` is undocumented.
- Block message: "Run 'bash hooks/run-gate.sh' on the PR branch head."

**Run gate** (`hooks/run-gate.sh`) — companion runner, NOT registered as a hook:
- Invoked by developers/PO as `bash hooks/run-gate.sh`.
- Reads the Gate command from PROJECT_CONTEXT.md (tolerates `- ` list markers, the `**Gate Command**:` label style, and backtick-wrapped commands), runs it, and on success writes `.gate/last-pass.json` (`{"sha","tree","branch","ts","status":"pass"}`) and prints `GATE PASS <sha>`. `tree` is `git write-tree` (the index tree) — recorded only when the working tree matches the index (`git diff --quiet`); otherwise `tree` is `""` and only the sha match applies. On failure it deletes the artifact and exits nonzero. Refuses to run (exit 2) if `RUN_GATE_ACTIVE=1` is already set — guards against a `**Gate**` command that shells back into `run-gate.sh` itself.
- `.gate/` is gitignored by all templates.

**No push to main** (`hooks/no-push-main.sh`):
- Matcher: `mcp__git-tools__git_push`
- Blocks pushes to `main` or `master` branches. Resolves implicit branch via `git branch --show-current` when the `branch` parameter is omitted.
- Message: "Use a feature branch and create a PR."

**Require skills block** (`hooks/require-skills-block.sh`):
- Matcher: `Agent`
- Enforces the AGENT_TEAM.md *Spawn-Prompt Binding Table* — when the PO spawns a `Task` whose `subagent_type` is bound (`coder` and variants, `tester`, `architect`), the prompt body must contain a literal `## Required Skills` line listing the skills that subagent must invoke before task work.
- Pass-through types: `code-reviewer` (no required skills), and any `subagent_type` not in the binding table (e.g. `general-purpose`, `Explore`, `Plan`).
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
- **Caps** rather than blocks (v2.0 PR3). An unbounded `Read` whose remaining length (`file_lines - offset`) exceeds the threshold (default `500`) is rewritten via `hookSpecificOutput.updatedInput` to carry `limit: 500`, plus an `additionalContext` naming the offset to pass next. The call proceeds; nothing is refused.
- `updatedInput` **replaces the whole input object**, so the hook copies the original `tool_input` wholesale (`Object.assign`) — `pages` and any future field survive.
- Silent pass when: `limit` is already set, the file is short, the path is missing/unreadable, or the extension is `png|jpg|jpeg|gif|pdf|ipynb` (not line-addressable).
- Over 10 MB the cap is decided from `stat` alone (`File is N MB; capped at 500 lines…`): no offset can bring the remainder under the cap, and counting lines would mean scanning every byte on a hook that fires on every Read. One node process per call, payload on stdin.
- Rationale: the Read tool accounts for ~22% of session context per `docs/plans/2026-04-14-context-baseline.md`, and 5,032 of 10,336 measured Read calls passed no `limit`. Blocking cost a round trip per call and taught nothing; rewriting is invisible and always makes progress.
- Never exits non-zero, so it is registered with a fail-open (`exit 0` on 127) wrapper.
- Appends tab-separated CAP decisions to `~/.claude/state/read-size-gate.log`. Log append is best-effort — write failures never mask the decision.
- Uses `node -e` for JSON parsing (no `jq` dependency). Style-matches `no-push-main.sh`.

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

### Bash Output Guard (PostToolUse, User-Level Recommended)

**Hook** (`hooks/bash-output-guard.sh`), matcher `Bash|PowerShell`:
- Reads `tool_response` from stdin. Observed shape (2.1.250): `{stdout, stderr, interrupted, isImage, noOutputExpected}`.
- `stdout` and `stderr` are checked independently. A stream over 12,000 chars is written to `$TMPDIR/claude-bash-out/<session_id>-<epoch>[-stderr].log` and the transcript gets first 4,000 chars + `…[N chars truncated — full output|stderr: <path>]…` + last 4,000, returned as `hookSpecificOutput.updatedToolOutput`. The object keeps the original shape (sibling fields copied) — a mismatched shape corrupts the tool result.
- The payload is piped to `node` on stdin, not passed in argv: a 200 KB build log exceeds the platform argument limits, and an exec failure here would silently pass the untruncated output through.
- Both streams short, a missing `tool_response`, or an unparseable payload → no output at all, the result passes through untouched.
- Always exits 0 and is registered **unwrapped**: it cannot block, so a 127 wrapper would only invent a failure mode.
- Rollback: remove the matcher group. Old log files are never pruned — clear `$TMPDIR/claude-bash-out/` yourself if it grows.

### Model & Effort (session settings)

`model` picks the orchestrator's model; the session effort level picks how hard it works on each turn. **No session effort key is shipped** — unset means the model's own default (Opus 5 / Fable 5 decide per step, and Fable 5 ignores thinking toggles entirely). Raise it per role instead, with `effort:` in the agent file (`low` / `medium` / `high` / `xhigh`), or `/effort` for one session. They are different dials for different failures: a wrong answer *despite* full context calls for a bigger model, while skipped files or tests that never ran call for more effort. Subagent `model:` / `effort:` in the agent file override the session values for that spawn — see `AGENT_TEAM.md` → *Model & Effort Policy*.

Use **aliases** (`opus`, `sonnet`, `haiku`, `fable`, `inherit`), never a full `claude-*` id: a model proxy reroutes aliases, and a pinned id bypasses it. If you run such a proxy, keep the auto-mode classifier and `advisorModel` off it — both need the real model.

`advisorModel` is shipped as `"opus"` (top level). It picks the model behind the `advisor` reviewer tool, which is a different dial from `model` and the effort level: the advisor sees the full transcript and is worth spending on even when the session itself runs cheaper.

> The plan-mode allow hook for context-mode tools (`hooks/allow-ctx-plan.sh`) was removed in v2.0 PR3 along with the mandatory context-mode routing. The plugin is optional now; if you still run it and want the plan-mode prompts suppressed, re-add an `allow` PreToolUse hook for the `ctx_*` matchers — the mechanism (PreToolUse runs before the permission system, so `permissionDecision: "allow"` pierces plan mode) is unchanged.

### Delegation Enforcement (PreToolUse, Project-Level — templates)

**`hooks/enforce-delegation.sh`** — the PO (main thread) never does hands-on work; sub-agents do all coding/building/testing. Registered in every template `settings.json` under TWO PreToolUse matcher groups: `Edit|Write|NotebookEdit` and `Bash`.

- **Discriminator:** the hook stdin contains `agent_id` ONLY when the call originates inside a subagent — subagent calls always pass; main-thread calls are checked.
- **Main-thread edits** are allowed only on the PO write surface (`docs/plans/`, `PROJECT_STATE.md`, `PROJECT_CONTEXT.md`, `.claude/`, `CLAUDE.md`, `CLAUDE.local.md`, `AGENT_TEAM.md`, paths outside the repo). Everything else denies with a model-visible DELEGATE message naming the right agent. Handles `notebook_path` (NotebookEdit) and backslash Windows paths.
- **Main-thread Bash** denies build/test-runner commands (`npm test`, `npm run test|build|e2e|coverage`, `npx vitest|jest|playwright`, `pytest`, `cargo test|build|run`, `dotnet build|test|run`, `mvn`, `gradlew`, `go test`) AND `hooks/run-gate.sh` — the PO verifies via the `.gate/last-pass.json` artifact, never by running the suite.
- **Kill-switch:** create `.claude/delegation-off` at the repo root to disable (also the recovery if a pre-`agent_id` CLI ever denies subagent calls).
- **Failure polarity — deliberately fail-OPEN:** never apply the exit-2 127-wrapper (a missing script would block ALL edits including subagents' — total paralysis, same class as the SubagentStop stop-gate). Registration uses a **WARN-wrapper** instead: on 127 it prints `WARN: ... delegation enforcement offline. Run /sync-template.` to stderr and exits 0 — visible, never blocking. Internal parse failures pass through. Note: main-thread Bash-git stays guarded regardless — the three git gates (fail-closed) fire on the same Bash matcher.
