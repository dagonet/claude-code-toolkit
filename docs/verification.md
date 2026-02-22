# Post-Setup Verification

[Back to README](../README.md)

## Verification Steps

After applying a template, walk through this checklist to confirm everything is working:

1. **Open Claude Code** in the project directory

2. **Verify CLAUDE.md is auto-loaded** — project context should be visible in the session

3. **Verify PO session initialization runs** — the bootstrap sequence reads `AGENT_TEAM.md` and `PROJECT_CONTEXT.md`, then presents current state

4. **Verify project-level agents override user-level** — check that `.claude/agents/` in the project takes precedence over `~/.claude/agents/`

5. **Run `/orient`** to confirm skills work

6. **Test `mcp__git-tools__git_status`** to confirm MCP tools are connected

7. **For .NET**: run `/build` to confirm dotnet-tools MCP is operational

8. **For MAUI**: verify SQLite MCP connects to database (configured at user-level in `~/.claude/.mcp.json`)

9. **For Rust/Tauri**: verify `cargo test` and `npm test` both pass

10. **For Python**: verify `pytest` runs and `ruff check` passes

11. **Spawn a test team** to verify `AGENT_TEAM.md` workflow (assign a T1 task and confirm PO role, agent dispatch, and review cycle)

## Troubleshooting

**CLAUDE.md not loaded**
Check that you opened Claude Code in the correct project directory. CLAUDE.md must be at the project root.

**MCP tools fail**
Run `claude mcp list` to confirm registered servers. See [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md) for installation and configuration details.

**Agents not overriding user-level**
Verify that `.claude/agents/` exists in the project directory and contains the expected agent files. Project-level agents replace (not merge with) user-level agents of the same name.
