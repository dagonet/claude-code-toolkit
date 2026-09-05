# Project Context

## Project

- **Name**: example-project
- **Tech stack**: Tauri 2 (Rust shell), TypeScript, Vite, HTML5 Canvas 2D (no UI framework), Vitest, Playwright, npm
- **Repository**: (repository URL redacted - not load-bearing for this fixture)
- **Branch strategy**: feature branches per task, PR into the trunk — the branch named on the `**Protected branches**:` line directly below (see AGENT_TEAM.md Mode Behavior Table for naming convention). Prose for humans — **no hook reads this line**, and it is deliberately placeholder-free: nothing fills a placeholder here on a sync, so one would report unresolved on every apply, forever, on a value that is supposed to be there.
<!-- THE line the protection hooks read; space- or comma-separated names.
     EDIT THIS if your trunk is not main/master — nothing fills it in for you,
     and a trunk that is not named here is NOT protected.
     Absent, empty, or an unfilled {{...}} all fall back to `main master`;
     `none` protects nothing (branch rules only; a PR merge stays gated). -->
- **Protected branches**: main

## Commands

- **Build (desktop)**: `npm run tauri build`
- **Build (web only)**: `npm run build`
- **Dev server**: `npm run dev` (Vite, port 5173)
- **Dev (desktop)**: `npm run tauri dev`
- **Test (frontend unit)**: `npm test` (Vitest)
- **Test (frontend e2e)**: `npx playwright test` (Playwright, headless Chromium)
- **Test (backend)**: `cargo test --manifest-path src-tauri/Cargo.toml`
- **Format (frontend)**: `npm run format` (Prettier)
- **Format (backend)**: `cargo fmt --manifest-path src-tauri/Cargo.toml`
- **Lint (frontend)**: `npm run lint` (ESLint + `tsc --noEmit`)
- **Lint (backend)**: `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings`
- **Gate**: npm run gate

## Signal Plans

This section is project-added: it exists in the project file and in the
merge output, and NOT in the template. That is what makes it available as
a wrong landing site for a block the template anchored elsewhere.

The placeholder line.
<!-- Declaring BOTH means the Test runs on commit and the Gate does not, so no artifact is minted and every merge needs a separate `bash hooks/run-gate.sh`. Worth it only above roughly gate_seconds / (gate_seconds - test_seconds) commits per PR — measure yours. Below that, declare the Gate alone and leave the Test field empty (a literal `none` is NOT an opt-out here: it is eval'd as a command and blocks every commit — measured 2026-09-03). -->

## Paths

- **Worktree base**: `/srv/worktrees/example-project`
- **Architecture docs**: `README.md`, `docs/`, plan file at `docs/plans/example-plan.md`
- **Log location**: `logs/` (file-based) and browser devtools console; Tauri shell uses `log` crate to stdout

## Workflow Configuration

- **Task source**: `plan-files`
- **Max parallel workstreams**: 5
- **Commit convention**: `feat:`, `fix:`, `chore:`, `test:`, `docs:` prefixes
- **Issue labels** (github-issues mode only): `feature`, `bug`, `tech-debt`

## Preprocessing

- **Ollama**: available (MCP: `ollama-tools`) -- see CLAUDE.local.md for usage rules
- **Context7**: available (MCP: `context7`)
