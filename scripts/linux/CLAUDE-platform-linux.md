## Platform: Linux + bash

This machine is a Linux agent server (Ubuntu) with bash as the shell; sessions are opened over SSH + tmux.

- Paths are POSIX; repos live under `~/git/`. There is no PowerShell tool and no MSYS path conversion here.
- Avoid `grep -r` in Bash — pick the search tool from the Read & Search Tool Selection table below
- **PO / main thread only** (subagents do not have MCP servers — never route these to a spawn): read release notes via the MCP GitHub tools, and cut GitHub releases with them rather than `gh release create`
- Multi-line/compound Bash commands can be conservatively blocked by guard hooks (unparseable → fail-closed). Write the logic to a script file -- with the Write tool, never a heredoc -- and run `bash <path>` — the guard hooks read the script's first 16 KB, so a `git commit`/`merge`/`push` inside it is gated exactly as if typed (a script that calls another script is not followed)
- This host has no Docker, no browser and no Ollama. The MCP servers available are the ones `claude mcp list` shows; tools that only exist on the Windows PC (MCP_DOCKER, chrome-devtools, ollama-tools, searxng) are absent here.
- `sudo` needs a password: hand anything that needs root to the user as a command to run.

