# Project Context

This is the toolkit's OWN context file, not a template artifact. It exists so the
toolkit is gated by the same three git hooks it ships: `hooks/pre-commit-test.sh`,
`hooks/no-push-main.sh` and `hooks/gate-before-merge.sh` all read this file, and
without it they no-op in this repository — which is how every toolkit PR up to
v2.2.4 merged through the artifact path as a silent no-op.

The template copies live at `templates/<variant>/PROJECT_CONTEXT.md` and are
placeholder-bearing; this one is filled in, because it describes a real project.

## Project

- **Name**: claude-code-toolkit
- **Tech stack**: Bash (hooks, verification scripts), Markdown (templates, docs), PowerShell (setup script)
- **Repository**: https://github.com/dagonet/claude-code-toolkit
- **Branch strategy**: feature branches per task, PR into the trunk — the branch named on the `**Protected branches**:` line directly below. Prose for humans — no hook reads this line.
<!-- THE line the protection hooks read; space- or comma-separated names. -->
- **Protected branches**: main

## Commands

The Test/Gate split is the point of this file. **Test** runs on EVERY commit, so it
has to stay fast; **Gate** is the merge-only artifact command and runs the full
pair. Measured on the release host across several runs: Test **58-117s**, Gate
**512-619s** — the difference is `test-hooks.sh`, which builds a throwaway git
repo per fixture. Collapsing them into one command would put ten minutes on every
commit in this repo, which is the exact trap a consumer is living in. The spread
inside each range is filesystem-cache and concurrency noise on Windows, so treat
the absolute numbers as host-local; the ~10x ratio is the part that travels.

- **Build**: `bash scripts/verify-template-consistency.sh`
- **Test**: `bash scripts/verify-template-consistency.sh`
- **Format**: none — every file is LF-only Markdown or shell; `verify-template-consistency.sh` asserts the line endings
- **Lint**: none — see Build
- **Gate**: `bash scripts/verify-template-consistency.sh && bash scripts/test-hooks.sh`
<!-- Join Gate command steps with `&&`, never `;` — `;` discards an earlier step's failure status, so `<real gate> ; <anything>` exits 0 and the gate mints a pass artifact on a failing suite. -->

## Paths

- **Worktree base**: `.claude/worktrees`
- **Architecture docs**: `README.md`, `CLAUDE.md`, `docs/`
- **Log location**: none — the scripts print to stdout

## Workflow Configuration

- **Task source**: `plan-files`
- **Max parallel workstreams**: 5
- **Commit convention**: `feat:`, `fix:`, `chore:`, `test:`, `docs:`, `release:` prefixes
