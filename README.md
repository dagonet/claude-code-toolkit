# Claude Code Toolkit

Reusable templates for bootstrapping projects with a production-ready [Claude Code](https://docs.anthropic.com/en/docs/claude-code) setup. Six template variants ship 8 agents, 10 skills, 21 commands, and pre-wired MCP server permissions -- pick a variant, run the setup script, and start coding with a full AI-assisted workflow.

## Template Variants

Pick the variant that matches your project. All share the same dual-mode workflow (GitHub Issues or plan files) and tiered sprint model (T1--T4).

| Feature | General | .NET | .NET MAUI | Rust/Tauri | Java | Python |
|---------|---------|------|-----------|------------|------|--------|
| Language/Framework | Any | C#/.NET | .NET MAUI Desktop | Rust + TypeScript (Tauri v2) | Java (Spring Boot) | Python |
| Agents | 7 | 8 (+dotnet-coder) | 8 (+dotnet-coder) | 8 (+rust-coder) | 8 (+java-coder) | 8 (+python-coder) |
| Code Style Tooling | -- | .editorconfig | .editorconfig | rustfmt.toml + .prettierrc | .editorconfig | .editorconfig |
| Build/Test Integration | Generic | dotnet build/test | + publish, FlaUI | cargo + npm | Maven or Gradle | pytest + ruff |
| Post-Edit Build Hook | No | `dotnet build` | `dotnet build` | No | No | No |
| Desktop Automation | No | No | Windows-MCP | Windows-MCP | No | No |
| Database Tools | SQLite MCP | SQLite MCP (optional) | SQLite MCP (optional) | SQLite MCP (optional) | SQLite MCP (optional) | SQLite MCP (optional) |

## Get Started

| Topic | Doc |
|-------|-----|
| Prerequisites, adoption tiers, MCP servers | [`docs/getting-started.md`](docs/getting-started.md) |
| Setup on Windows (PowerShell) | [`docs/setup-windows.md`](docs/setup-windows.md) |
| Setup on Linux / macOS (Bash) | [`docs/setup-linux-macos.md`](docs/setup-linux-macos.md) |
| Template details, placeholders, manual setup | [`docs/templates.md`](docs/templates.md) |

## Learn More

| Topic | Doc |
|-------|-----|
| Architecture -- layered config, AGENT_TEAM, session bootstrap | [`docs/architecture.md`](docs/architecture.md) |
| Post-setup verification checklist | [`docs/verification.md`](docs/verification.md) |
| Template sync and contributing upstream | [`docs/template-sync.md`](docs/template-sync.md) |
| MCP server installation | [`mcp-servers/HOWTO.md`](mcp-servers/HOWTO.md) |
| User-level config reference (agents, commands, skills) | [`user-level-reference/README.md`](user-level-reference/README.md) |

## Repository Structure

```
claude-code-toolkit/
├── README.md
├── setup-project.ps1          # Automated setup (Windows)
├── setup-project.sh           # Automated setup (Linux/macOS)
├── docs/
│   ├── getting-started.md     # Prerequisites, adoption tiers, MCP servers
│   ├── setup-windows.md       # Windows setup walkthrough
│   ├── setup-linux-macos.md   # Linux/macOS setup walkthrough
│   ├── templates.md           # Template details and placeholder reference
│   ├── architecture.md        # Layered config, workflow, session bootstrap
│   ├── verification.md        # Post-setup verification checklist
│   └── template-sync.md       # Keeping projects in sync with templates
├── templates/
│   ├── general/               # Any language
│   ├── dotnet/                # C#/.NET
│   ├── dotnet-maui/           # .NET MAUI desktop
│   ├── rust-tauri/            # Rust + Tauri v2 desktop
│   ├── java/                  # Java (Spring Boot)
│   └── python/                # Python
├── mcp-servers/
│   └── HOWTO.md               # MCP server installation guide
└── user-level-reference/      # ~/.claude/ reference for new machines
    ├── agents/                # 7 generic agent definitions
    ├── commands/              # 21 slash commands
    └── skills/                # 10 auto-invoked skills
```

## License

MIT
