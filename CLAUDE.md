# claude-code-toolkit

Template repo for bootstrapping projects with Claude Code config. It ships no application code — the deliverable is the config itself.

## Layout

- `templates/<variant>/` — six variants: `general`, `dotnet`, `dotnet-maui`, `rust-tauri`, `java`, `python`. Each carries `CLAUDE.md`, `CLAUDE.local.md`, `AGENT_TEAM.md`, `PROJECT_CONTEXT.md`, `PROJECT_STATE.md`, `gitignore`, `.claude/{settings.json,agents/,rules/}`.
- `user-level-reference/` — the copyable source for `~/.claude/` (CLAUDE.md, settings.json, agents, skills, hooks).
- `hooks/` — the canonical enforcement hooks, referenced by both template settings and agent frontmatter.
- `scripts/` — verification and propagation tooling. `setup-project.sh` / `.ps1` bootstrap a project.
- `docs/plans/` — plans are committed markdown here, not ephemeral plan-mode files.

## Gate

`bash scripts/verify-template-consistency.sh` and `bash scripts/test-hooks.sh` are the gate. Both must be green before a commit is claimed done. The gate command list stays two: `scripts/test-setup-project.sh` (bootstrap fixtures — the `setup-project.{sh,ps1}` dry-run/real-run paths must agree) is **invoked from** `verify-template-consistency.sh` as check 27, so a new fixture file never needs consumer, doc, routine or CI wiring to be executed. `scripts/verify-user-level-drift.sh` compares `user-level-reference/{CLAUDE.md,hooks/**,skills/**,agents/**}` against the live `~/.claude/` tree; the reference leads, the live copy follows per the CHANGELOG's downstream-migration section.

## Invariants

- Several files are **byte-identical across all six variants** (`AGENT_TEAM.md`, generic agents, hook scripts). `verify-template-consistency.sh` asserts this — edit `templates/general/` first, then `cp` to the other variants.
- User-level agents must not carry project-only frontmatter `hooks:` — they fail closed in repos without a `hooks/` directory.
- Every file is **LF**. `scripts/template_propagate_to_variants` can emit CRLF — normalize afterwards.
- Never rewrite a file containing non-ASCII through PowerShell `Get-Content`/`WriteAllText` (PS 5.1 mojibakes UTF-8). Use Bash or the Edit tool.
