# Settings Reference (`~/.claude/settings.json`)

This document explains each section and setting in the user-level Claude Code settings file.

## Full Settings JSON

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_SHELL": "C:\\Program Files\\Git\\usr\\bin\\bash.exe"
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
      "mcp__github__*",
      "mcp__dotnet-tools__*",
      "mcp__ollama-tools__*",
      "mcp__plugin_playwright_playwright__*",
      "mcp__plugin_context7_context7__*",
      "mcp__godot-tools__*",
      "mcp__windows-mcp__*",
      "mcp__sqlite__*"
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
    "claude-code-setup@claude-plugins-official": true
  },
  "alwaysThinkingEnabled": true,
  "enableAllProjectMcpServers": true,
  "contextCompactionThreshold": 40
}
```

## Section-by-Section Explanation

### `env` -- Environment Variables

```json
"env": {
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
  "CLAUDE_CODE_SHELL": "C:\\Program Files\\Git\\usr\\bin\\bash.exe"
}
```

| Variable | Value | Purpose |
|----------|-------|---------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `"1"` | Enables the experimental Agent Teams feature, allowing multi-agent orchestration where specialized agents (architect, coder, tester, etc.) can collaborate on tasks. |
| `CLAUDE_CODE_SHELL` | Path to bash.exe | Overrides the default shell used by Claude Code's Bash tool. Points to Git Bash so Unix-style commands work on Windows. |

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
  "mcp__github__*",                       // Full GitHub MCP (issues, PRs, reviews, etc.)
  "mcp__dotnet-tools__*",                 // .NET MCP tools (build, test, analyze, EF, NuGet)
  "mcp__ollama-tools__*",                 // Local LLM tools via Ollama (first-pass, JSON extract)
  "mcp__plugin_playwright_playwright__*", // Playwright browser automation
  "mcp__plugin_context7_context7__*",     // Context7 documentation lookup
  "mcp__godot-tools__*",                  // Godot game engine tools
  "mcp__windows-mcp__*",                  // Windows system tools
  "mcp__sqlite__*"                        // SQLite database query tools
]
```

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
"contextCompactionThreshold": 40
```

Controls when Claude Code compacts (summarizes) the conversation context to stay within the context window. A value of `40` means compaction triggers when the conversation reaches approximately 40% of the context window. Lower values compact earlier (saving tokens but losing detail); higher values preserve more history.
