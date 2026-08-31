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

Since v2.2.5 this repo has a root `PROJECT_CONTEXT.md`, so it gates ITSELF: `**Test**` (the consistency script alone, ~20s) runs on every commit via `hooks/pre-commit-test.sh`, and `**Gate**` (consistency + `test-hooks.sh`, ~600s) is what `hooks/run-gate.sh` runs to write `.gate/last-pass.json` for `hooks/gate-before-merge.sh`. The split is deliberate — one command for both would put ten minutes on every commit.

**Self-reference risk, and the escape hatch.** The gates now enforce against the repository that defines them, so a bug in `hooks/pre-commit-test.sh` can block the very commit that fixes `hooks/pre-commit-test.sh`, and the same holds for `hooks/lib/json.sh`, `hooks/lib/git-cmd.sh` and `scripts/verify-template-consistency.sh`. **Read the block message first** — it is far more often a real red gate than a broken hook. When it genuinely is the hook, the documented escape is the pre-existing kill switch: create `.claude/git-guard-off` under the process cwd, make the one fix, delete it again. Never leave it in place, and never commit it.

## Invariants

- Several files are **byte-identical across all six variants** (`AGENT_TEAM.md`, generic agents, hook scripts). `verify-template-consistency.sh` asserts this — edit `templates/general/` first, then `cp` to the other variants.
- User-level agents must not carry project-only frontmatter `hooks:` — they fail closed in repos without a `hooks/` directory.
- Every file is **LF**. `scripts/template_propagate_to_variants` can emit CRLF — normalize afterwards.
- Never rewrite a file containing non-ASCII through PowerShell `Get-Content`/`WriteAllText` (PS 5.1 mojibakes UTF-8). Use Bash or the Edit tool.
