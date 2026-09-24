# Architecture

[Back to README](../README.md)

The toolkit is a template repository: it ships a Claude Code configuration (agents, skills, hooks, rules, MCP permissions) that `setup-project` copies into a project and `/sync-template` keeps current, and no application code. This document describes how those pieces fit together — the configuration layers, the agent team, the hooks, and the repository layout.

## Layered Configuration

Claude Code supports layered configuration: **project-level `.claude/` overrides user-level `~/.claude/`** for same-named items.

- **User-level agents** (`~/.claude/agents/`): 6 generic agents -- Explore, architect, code-reviewer, coder, ops, tester.
- **Template agents** override user-level when working in that project. Generic agents in general/rust-tauri templates are identical to user-level. Dotnet/MAUI templates specialize architect, code-reviewer, and tester for their tech stack.
- **Domain-specific coders** (`dotnet-coder`, `rust-coder`, `java-coder`, `python-coder`) live at project-level only -- they have no user-level counterpart.

## AGENT_TEAM.md v2.0 -- Dual-Mode Workflow

The v2.0 workflow separates **project-specific config** (`PROJECT_CONTEXT.md`) from the **shared workflow definition** (`AGENT_TEAM.md`). AGENT_TEAM.md is identical across all six template variants -- only PROJECT_CONTEXT.md varies.

### Key Files

| File | Purpose | Varies per template? |
|------|---------|---------------------|
| `PROJECT_CONTEXT.md` | Tech stack, commands, paths, task source mode | Yes |
| `AGENT_TEAM.md` | Roles, tiers, mode table, worktrees, merge, rules | No (identical) |
| `PROJECT_STATE.md` | Sprint state tracking (github-issues mode) | No |

### Task Source Modes

Each project chooses ONE mode via the `task-source` field in `PROJECT_CONTEXT.md`:

| Mode | Task Definition | Branch Naming | Commit Convention |
|------|----------------|---------------|-------------------|
| `github-issues` | GitHub Issues with AC | `feature/issue-{number}` | `issue-{number}: description` |
| `plan-files` | `docs/plans/sprint-N-*.md` | PO specifies per task | `feat:` / `fix:` / `chore:` prefixes |

The **Mode Behavior Table** in AGENT_TEAM.md maps 12 workflow actions (task definition, architect guidance, review findings, closing tasks, etc.) to mode-specific targets.

## Tiered Sprint Model

| Tier | Scope | Agents | Testing |
|------|-------|--------|--------|
| T1 Trivial | < 10 lines, config/style | 1 coder (solo, uniform PR pipeline) | Coder runs gate (build + existing suite) |
| T2 Simple | 1-2 files, < 50 lines | coder + code-reviewer | Tests if logic changes; coder runs gate |
| T3 Standard | Multi-file, < 200 lines | coder + reviewer + tester | TDD required, >= 80% coverage |
| T4 Complex | Architectural, > 200 lines | architect + coder(s) + reviewer + tester | Full BDD/TDD, >= 80% coverage |

**Model & effort policy:** the orchestrator model is a per-session `/model` choice — `fable` for T3/T4 (multi-file or architectural) sessions, `opus` for T1/T2. Fable 5 needs fewer prompts and steers and sustains longer, higher-autonomy sessions, at roughly 2× Opus price. Session effort ships **unset** (the model's own default); effort is raised per role in the agent frontmatter — `architect` and `code-reviewer` at `xhigh`, workers at `medium`, `Explore` at `low`. Full rule set: `AGENT_TEAM.md` → *Model & Effort Policy*.

**Delegate-everything model:** the PO never does hands-on work at any tier — coding, reviewing, testing, builds, env setup (`ops` agent), and exploration (`Explore` agent) are all sub-agent work, enforced by `hooks/enforce-delegation.sh`. The PO's write surface is limited to orchestration files — enumerated once, in the `enforce-delegation.sh` row of the hook table below.

## Context Budget

Anthropic's [context-engineering guidance for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models) favours progressive disclosure and mechanical enforcement over long prescriptive prompts. Measured state of this repo (general variant; the version columns are historical `wc -c` figures, the last column is `wc -c` at v4.1.2, 2026-09-24):

| | Baseline (v1.3) | v1.5 | v2.0 | v2.1 | v3.1 (v3.1.0) | v4.0.3 | v4.1.0 | v4.1.1 | **v4.1.2** | Loaded |
|---|---|---|---|---|---|---|---|---|---|---|
| `templates/general/CLAUDE.md` | 17,871 | 13,735 | 10,362 | 10,560 | 6,143 | 6,143 | 6,114 | 6,114 | **6,114** | every session |
| `templates/general/CLAUDE.local.md` | 13,845 | 9,352 | 9,417 | 9,417 | 8,655 | — (retired v4.0.1) | — | — | **—** | — |
| user-level `CLAUDE.md` | 8,505 | 8,505 | 5,089 | 5,076 | 5,076 | 5,453 | 5,453 | 5,453 | **6,622** | every session |
| `.claude/rules/project.md` (unscoped, `once`) | — | — | — | — | 634 | 707 | 742 | 742 | **742** | every session (measured v4.0.1: an unscoped rules file loads at session start) |
| `.claude/project-instructions.md` (once, seed only) | — | — | — | — | — | — | 823 | 823 | **823** | every session (v4.1.0: `CLAUDE.md`'s last line imports it, `@.claude/project-instructions.md`; the byte count is the SEED's — a consumer's own content lives in this file and is theirs, never counted here) |
| **harness-injected at session start** | **40,221** | 31,592 | 24,868 | 25,053 | 19,874 | 12,303 | 13,132 | 13,132 | **14,301** | unconditional |
| `PROJECT_CONTEXT.md` | 946 | 946 | 946 | 946 | 3,170 | 3,422 | 3,422 | 3,422 | **3,569** | read on instruction (bootstrap step 3) as a tool result; hooks read it too, but a PreToolUse hook's bytes never reach the model |
| **at the end of bootstrap** | **41,167** | 32,538 | 25,814 | 25,999 | 23,044 | 15,725 | 16,554 | 16,554 | **17,870** | |
| `AGENT_TEAM.md` | 47,968 | 49,724 | 49,724 | 53,288 | 20,472 | 20,467 | 20,467 | 20,467 | **20,442** | **on demand only** |
| `VERIFICATION_PLAYBOOK.md` | 2,519 | 2,519 | 2,519 | 2,519 | 2,519 | 2,519 | 2,519 | 2,519 | **2,519** | on demand |
| skills | 11 | 12 | 7 | 8 | 8 | 8 | 8 | 8 | **8** | on trigger |

**v4.1.1's column is unchanged from v4.1.0's, byte for byte — re-measured with `wc -c`, not carried forward.** The patch touched the server, the hooks, the consistency script, and the sync-template skill; no task changed a `CLAUDE.md`, a `.claude/rules/project.md`, a `.claude/project-instructions.md` seed, the user-level `CLAUDE.md`, or a `PROJECT_CONTEXT.md` in any variant, so the file set feeding both subtotals is identical to v4.1.0's. **v4.1.2 moves three files, and only three**, each re-measured with `wc -c` at this release's own tip rather than carried forward: the reference user-level `CLAUDE.md` gains a "Git Worktrees — declared location" section (**5,453 → 6,622 B, +1,169 B**), every variant's `PROJECT_CONTEXT.md` gains one byte-identical clause naming `EnterWorktree`'s fixed, unconfigurable location (general **3,422 → 3,569 B, +147 B**, the same +147 B on all six variants), and the on-demand `AGENT_TEAM.md` gains one new orphan-job-liveness paragraph but nets **20,454 → 20,442 B, −12 B** per variant once a later trim pass removes prose that restated a rule stated elsewhere in the same file — a net decrease despite the addition, because the trim removed more than the paragraph added. (This table's own v4.1.0/v4.1.1 `AGENT_TEAM.md` figure of 20,467 does not match either release tag's actual `wc -c` — both `v4.1.0` and `v4.1.1` measure 20,454 B for `templates/general/AGENT_TEAM.md`; that 13 B discrepancy predates this release and is left as-is here rather than silently corrected, since fixing a historical column is outside this release's own scope — the v4.1.2 figure above is this release's own fresh measurement, not derived from the questionable prior column.) General's harness-injected/bootstrap subtotals move **13,132 → 14,301 (+1,169 B)** and **16,554 → 17,870 (+1,316 B = 1,169 + 147)**; `CLAUDE.md` and `.claude/rules/project.md` are untouched. Per-variant harness-injected at v4.1.2 (variant `CLAUDE.md` + `project.md` + the user-level `CLAUDE.md` + the `project-instructions.md` seed, all measured `wc -c`): general **14,301** · java 14,293 · dotnet-maui 14,297 · python 14,297 · dotnet 14,298 · rust-tauri 14,299; at the end of bootstrap (+ `PROJECT_CONTEXT.md`): general **17,870** · python 17,999 · java 18,020 · dotnet 18,046 · rust-tauri 18,218 · dotnet-maui 18,397 — each variant's delta from its own v4.1.1 figure is uniformly +1,169 B (injected) / +1,316 B (bootstrap), since the two files that moved (user-level `CLAUDE.md`, `PROJECT_CONTEXT.md`'s new clause) both move by the same byte count in every variant.

Column file sets (each reproducible from its release tag): Baseline through v3.1 injected = `CLAUDE.md` + `CLAUDE.local.md` + user-level `CLAUDE.md`; v4.0.3 injected = `CLAUDE.md` + `project.md` + user-level `CLAUDE.md`; **v4.1.0 injected = `CLAUDE.md` + `project.md` + user-level `CLAUDE.md` + the `.claude/project-instructions.md` seed** (once-class; v4.1.0 makes it always-imported); "end of bootstrap" adds `PROJECT_CONTEXT.md` in every column. The v3.1 total counted `CLAUDE.local.md`, which v4.0.1 retired, and did not yet count `project.md`, which v4.0.1 measured as loading at every session start — the v4.0.3 column counted what loaded then, in two subtotals because they are two quantities (reviewer, #145): the harness-injected set changes by editing files and is unconditional; the `PROJECT_CONTEXT.md` read changes by changing an instruction, happens only if the model follows step 3, and may not recur after `/clear` or `/compact`. **v4.1.0 is the first release where the injected subtotal GROWS**, general 12,303 → 13,132 (+829 B), because the new project-instructions.md seed (823 B, always imported as of this release) outweighs the −29 B `CLAUDE.md` trim (Task 3, option B) and the +35 B `project.md` reword (R-G) landing in the same release; the seed row reports only its own bytes, never a consumer's added content. Per variant at v4.1.0 — harness-injected (variant `CLAUDE.md` + `project.md` + the user-level `CLAUDE.md` + the `project-instructions.md` seed): general **13,132** · java 13,124 · dotnet-maui 13,128 · python 13,128 · dotnet 13,129 · rust-tauri 13,130; at the end of bootstrap (+ `PROJECT_CONTEXT.md`): general **16,554** · python 16,683 · java 16,704 · dotnet 16,730 · rust-tauri 16,902 · dotnet-maui 17,081. The non-`general` variants defer their language conventions into `paths:`-scoped `.claude/rules/` files that arrive only on a matching file touch (all rules per variant, `project.md` included: dotnet 2,576 · dotnet-maui 2,992 · python 3,120 · java 3,301 · rust-tauri 4,132 B — each +35 B over v4.0.3's figures, R-G's `project.md` reword), and no project ever receives more than its own variant's set.

Two v3.1 movements are worth reading rather than skimming. **`AGENT_TEAM.md` fell 53,288 → 20,472 B** (20,467 at v4.0.3) — the largest single cut in the toolkit's history, and it is enforced rather than intended: consistency check 35 caps it at 20,480 B and `CLAUDE.md` at 6,144 B per variant, so neither can grow back without the check going red and someone deciding it should. **`PROJECT_CONTEXT.md` grew 946 → 3,170 B on purpose** (3,422 at v4.0.3, as declared keys were added), because that is where the declared keys live; every byte added there removes prose that a hook would otherwise have to trust an agent to remember.

Every **v2.0** figure is `wc -c` on the shipped file, not an arithmetic carry-forward — which is what the separate **pre-PR4** column is for: PR1–PR3 moved `CLAUDE.md` (13,735 → 13,892) and `CLAUDE.local.md` (9,352 → 9,413) for reasons unrelated to the trim, so those deltas must not be attributed to PR4. The user-level row's drop is PR5 deleting the context-mode routing block.

The largest single document in the repo is deliberately *not* in the always-loaded set. The three passes used different mechanisms:

- **v1.4 moved** — ten MCP procedures into the `mcp-usage` skill, the per-agent Open Brain tables into `AGENT_TEAM.md`. The on-demand side growing while the always-loaded side shrinks is the intended direction.
- **v1.5 deleted** — *Working Preferences* 18 bullets → 11, because five were already enforced by a hook or by the harness itself and two carried no behavioural content. Deleting prose that a mechanism enforces is safe in a way that deleting an unenforced rule is not; the section now names the enforcing hooks instead of restating their rules.
- **v2.0-pr4 scoped** — language conventions (*Code Style (MANDATORY)*, *Enforcement Notes*, the per-variant *Project Conventions*) moved verbatim into `.claude/rules/*.md`, each with a `paths:` frontmatter glob list. A scoped rule loads only when Claude reads or edits a matching file, absent from a subagent's context at spawn even when scoped. **Corrected in v3.1, on measurement, then corrected again in v4.0.1 (item 14) because the v3.1 correction overshot:** v3.1 said a rule **without** `paths:` "is delivered to nobody" — false. An unscoped rule file loads at **every session start**, at `CLAUDE.md` priority; a missing `paths:` key means "always", not "never". Scoped rules stay the toolkit's default for language conventions because those apply to a subset of files, not because unscoped delivery is broken. The practical consequence: safety rules, prohibitions and always-on project conventions CAN live in an unscoped rules file (`.claude/rules/project.md` is exactly that, by design) — writing the same rule there AND in `CLAUDE.md`'s PROJECT-CUSTOM region is what actually goes wrong, because then it exists twice and drifts. The always-loaded CLAUDE.md now differs between variants by a single pointer line.
- **v2.0-pr4 round 2 routed by audience** — two more sections left the always-loaded set once it was clear *who* each one binds. *Open Brain Context for Agents* said nothing `AGENT_TEAM.md` → *Open Brain Context for Agents* did not already say in more detail, so CLAUDE.md keeps a pointer and the tables stay on-demand. *Working Preferences* binds **developer agents**, not the PO, and all 12 coders preload `karpathy-guidelines` (`skills:`, PR3) — so its 11 bullets moved into that skill and reach the agents that act on them at spawn, at zero always-loaded cost. The hook-enforcement line stayed behind because it is PO-relevant. The routing question is not "is this important?" but "who needs it, and when?". Moving prose out of the always-loaded set removes the check that used to guard it implicitly, so check 20 pins the skill's heading and its bullet count — a floor of 11, the v1.5 post-trim set, parsed from the section rather than hard-coded to the file's current length.

**CLAUDE.md is facts, not procedure.** The per-line test is "would removing this cause Claude to make a mistake?". Procedures belong in skills, "every time X do Y" belongs in a hook, "never X" belongs in a deterministic guardrail, and anything that only applies to a subset of files belongs in `.claude/rules/`. Emphasis is rationed: at most one `MUST`/`MANDATORY`-style line per CLAUDE.md (the Superpowers header, which hooks and the verify script both pin).

Every literal a hook greps is pinned by `scripts/verify-template-consistency.sh`, so a cut cannot silently disable enforcement — notably the exact `## Superpowers Skills — MUST Invoke Before Responding` header and the `superpowers:` token that checks 2 and 3 require, both of which survived the Superpowers-block reduction. Check 19 (added in PR4) asserts that every non-`general` variant ships at least one `.claude/rules/*.md`, that every rules file carries a `paths:` glob list, and that each variant's CLAUDE.md still points at its rules — all counted by glob, never hard-coded. Check 20 does the same job for the preferences that moved into the `karpathy-guidelines` skill.

## Session Bootstrap

CLAUDE.md enforces a lightweight bootstrap sequence at the start of every session. `AGENT_TEAM.md` is **not** read up front -- CLAUDE.md carries a one-line pointer to its Spawn-Prompt Binding Table, and the PO loads the full file when it first spawns agents. The binding itself is enforced by `require-skills-block.sh`, not by the prose, so duplicating the table into CLAUDE.md bought nothing (v2.0 PR4 removed it).

1. Assume the PO role. Load `AGENT_TEAM.md` on-demand when first spawning agents in a sprint, writing a spawn brief, or answering questions about merge/escalation rules
2. Pick the session model -- T3/T4 session (multi-file or architectural): `/model fable`; otherwise Opus
3. Read `PROJECT_CONTEXT.md` -- load build commands and workflow config
4. Check Open Brain (`thoughts_search` / `thoughts_recent`) for project context. For synthesis-style questions on a known topic, prefer `wiki_get` first; fall back to `thoughts_search` if the response is marked stale (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days)
5. Present current state (from MEMORY.md) and ask what to work on. Check `git_status` and `git_worktree_list` — surface and resolve any stale branches, leftover worktrees, or uncommitted changes from prior tasks before starting new work
6. Act on the RETRO brief, if one was printed (`hooks/retro-brief.sh`) -- fix the cause of each entry (the agent's `tools:` allowlist, the spawn prompt, the hook) or delegate the fix, before starting new work
7. Write the task brief (goal, constraints, acceptance criteria, files in scope, definition of done) and spawn

### Agent Type Selection

Each CLAUDE.md and AGENT_TEAM.md includes a variant-specific table mapping task domains to `subagent_type`:

| Variant | Task Domain | Agent |
|---------|-------------|-------|
| General | Any code task | `coder` |
| Dotnet | .NET backend | `dotnet-coder` |
| Dotnet-MAUI | .NET backend / MAUI UI | `dotnet-coder` |
| Rust-Tauri | Rust/Tauri backend | `rust-coder` |
| Java | Java/Spring backend | `java-coder` |
| Python | Python backend | `python-coder` |
| All | Frontend / docs / other | `coder` |

## MCP Permissions & Hooks

All templates grant permissions for **all** known MCP servers (git, github, ollama, dotnet-tools, rust-tools, windows-mcp, sqlite, searxng, playwright, context7, open-brain, template-sync-tools). If a server is not registered in the active scope, the permission is a harmless no-op.

`CLAUDE.local.md` (retired v4.0.1: no longer offered by the template) held MCP usage rules (e.g., "prefer `cargo_build` over Bash `cargo build`"), gitignored because it referenced machine-specific paths. A project that already has one keeps it; the file is never touched by a sync.

### MCP Layering

MCP servers are registered at two scopes, chosen to keep the user-level context minimal and load language-specific tooling only where it's needed:

| Scope | Where | Servers | When loaded |
|-------|-------|---------|-------------|
| **User-level** | **`~/.claude.json`** (top-level `mcpServers`) | Universal: `github-tools`, `MCP_DOCKER`, `ollama-tools`, `template-sync-tools`, `searxng`, `open-brain` (+ plugins: `context7`, `playwright`, `context-mode`) | Every session, every repo |
| **Project-level** | **`<project-root>/.mcp.json`** | Language/framework: `dotnet-tools`, `rust-tools`, `windows-mcp`, `sqlite`, `godot-tools` | Only in repos that register them |

> **Path correctness (2026-07-29).** These are the only two files Claude Code reads for MCP servers. `~/.claude/.mcp.json` does **not** exist as a concept — `claude mcp add --scope user` writes `~/.claude.json`. An `mcpServers` key inside any `settings.json` is silently ignored. `<project>/.claude/.mcp.json` is an open upstream feature request, not current behaviour.
>
> **Migration (projects set up before 2026-07-29).** Earlier setup scripts wrote `<target>/.claude/.mcp.json`, which is never loaded. For `dotnet`, `dotnet-maui`, and `rust-tauri` that file was the sole registration of `dotnet-tools` / `rust-tools` / `windows-mcp`, so **those servers were never active** in affected projects. Fix by moving it to the repo root:
>
> ```bash
> git mv .claude/.mcp.json .mcp.json     # or merge into an existing root .mcp.json
> ```
>
> `scripts/check-activation.sh` reports this, and the setup scripts now warn when they find the legacy file. `enableAllProjectMcpServers` does not help — it governs auto-approval, not file discovery.

The project-level file is **generated by `setup-project.{sh,ps1}`** per variant at setup time. Variants that need `mcp-dev-servers` (dotnet, dotnet-maui, rust-tauri) accept `--mcp-dev-servers-path`; `--sqlite-db-path` is available for any variant. See `docs/templates.md` for the per-variant matrix and `mcp-servers/HOWTO.md` for server details.

The universal-permissions model still holds: `settings.json` permission entries for project-level servers are no-ops in repos that don't register them, and become active when they do — no per-project permission edits required.

### Hooks

**Hook scripts are root-tracked**: they live once at the toolkit ROOT `hooks/` — variants do NOT ship a `hooks/` directory. Setup scripts copy from the root; the sync server resolves manifest `hooks/` paths against the root; consistency §13 asserts every referenced script exists there. See `docs/template-sync.md` → "Hooks Are Root-Tracked".

All templates include hooks in `.claude/settings.json` that enforce workflow rules mechanistically. Read the table as *what each hook does*, never as *what it is for* — a hook's reach is exactly the payload it inspects, and an intent-shaped reading credits it with more.

> **The criterion that decides whether a gate is sound: a gate that reads its arguments is safe; a gate that reads mutable ambient state is racy against the command it gates.** `PreToolUse` hooks run **before** the command, so any premise the command itself can change was read one moment too early. v3.0.1 audited all of them: `gate-before-merge.sh` and `no-push-main.sh` both resolved the current branch with `git branch --show-current`, and both were bypassed by `git checkout main && git merge feature/x` / `&& git push` — the guard read a precondition the command then changed. `pre-commit-test.sh` is **safe by shape**, not by luck: a commit's target is the index it was handed, while the merge and push gates ask git where they are. `run-gate.sh` reads ambient state too and has no race, because it is a runner with no pending command. Both bugs are fixed in v3.0.1 by keying on the checkout's **target** — an argument in the payload. Verdict tables and the fix's exact shape: `docs/verification.md`.
>
> **Interim rule for a project still on v2.4.0 or v3.0.0** — those are unpatched until they sync. **No branch change may PRECEDE a gated operation in the same call.** This is not "do not chain": `gh pr merge ; git checkout main ; git pull --ff-only` is safe, because the gated operation runs first and is evaluated on the branch the hook can see. Order is what matters. An explicit refspec — `git push origin <branch>` — is immune by construction, because it never consults ambient state at all.

| Hook Event | What it does | Templates |
|------------|--------------|-----------|
| **PreToolUse** on `Bash\|PowerShell` | The three git gates — `hooks/pre-commit-test.sh`, `hooks/no-push-main.sh`, `hooks/gate-before-merge.sh` — read `tool_input.command`, split it into clauses, unwrap `bash -c "…"`-style payloads, and refuse anything they cannot parse. `git -C <path>` retargets the repo; `<cwd>/.claude/git-guard-off` disables all three. **Which command forms are gated is not derivable from this row and is deliberately not listed here** — `merge` is gated unless it is a pure catch-up to the branch's own configured upstream, `pull` is gated by form (only the refspec-free `--ff-only` is allowed), `--abort`/`--continue`/`--quit` are always allowed. The verdict table is in `docs/verification.md`, and the contract itself is the header comment of `hooks/gate-before-merge.sh`, which is the copy that syncs to consumers. Superseded the v2.0 blanket Bash-git block, which banned the git CLI outright and blocked 1,240 turns in 6 weeks (deleted in v2.1) | All |
| **PreToolUse** on `Edit\|Write\|NotebookEdit` + `Bash` | `hooks/enforce-delegation.sh` — main-thread (PO) discrimination via the `agent_id` stdin field (present only inside subagents): denies PO edits outside the orchestration write surface, which is: `docs/plans/`, `PROJECT_STATE.md`, `PROJECT_CONTEXT.md`, `.claude/`, `CLAUDE.md` (pre-v4 manifests only; under manifest v4 write `.claude/project-instructions.md` — `deny-claude-md-writes.sh` enforces it), `CLAUDE.local.md`, `AGENT_TEAM.md`, **and any path outside the repo root** (scratchpad, `~/.claude`). Stated here because a PO otherwise learns the boundary by being blocked; note the hook's own DENY string omits `CLAUDE.local.md` and the outside-the-repo clause, so it under-reports what it allows. Also denies PO build/test-runner Bash (incl. `run-gate.sh` — the PO verifies via the gate artifact). Subagent calls always pass. Deliberately fail-open with a WARN-wrapper (a 127-wrap would paralyze subagent edits when the script is missing); kill-switch `.claude/delegation-off` | All |
| **PreToolUse** on `Edit\|Write\|MultiEdit\|NotebookEdit` | `hooks/deny-claude-md-writes.sh` (v4.1.0, spec §6) — refuses (exit 2) an editing-tool write to `<project root>/CLAUDE.md` when a manifest v4 exists at that root (`.claude/template-manifest.json`, `manifest_version == 4`); allows on no manifest, on manifest v3, and on any other path. Cannot-determine refuses (no JSON parser, unparsable stdin, an unreadable manifest). **Project scope only — unmirrored**: registered in every variant's `settings.json`, never at user level and never mirrored into `user-level-reference/hooks/` (`HOOKS_NO_MIRROR`) — a user-level copy would refuse `CLAUDE.md` writes in every non-consumer repo on the machine, including this toolkit's own checkout. Scope is the editing tools only; a Bash write (`sed -i`, `>>`, a heredoc) bypasses it by design — a guardrail, not a boundary (Non-goal) | All |
| **PreToolUse** on `Read` | `hooks/read-size-gate.sh` — rewrites an unbounded `Read` to `limit: 500` via `updatedInput` and tells the caller which offset to pass next; it never refuses a call. Wired **fail-open** (127 → exit 0) | All |
| **PreToolUse** on `Read\|Bash` | `hooks/deny-secret-reads.sh` — refuses (exit 2) a `Read` of a secret-shaped path (`.env`, `.env.<anything>`, not `.env.example`) and a Bash clause whose reader verb names one; fail-closed on an unparsable payload or a missing JSON parser. Registered at user level too (the one deny hook that is), because the hazard is the same in every repo | All |
| **PreToolUse** on `mcp__MCP_DOCKER__merge_pull_request\|mcp__github-tools__github_pr_auto_merge` | `hooks/gate-before-merge.sh` — the MCP half of the merge gate; hard-blocks PR merge/auto-merge unless a `<common git dir>/gate/last-pass.<sha>.json` artifact (v4.0.1, item 17 — shared across every worktree of the repo) is younger than `GC_GATE_TTL_S` (3600s = 60 minutes) **and** its `sha` equals HEAD **or** its `tree` equals `HEAD^{tree}` — the tree half has been there since v2.1.5 and is the half that survives a squash, so "SHA-matching" understates it; since v4.0.3 (item 13) an artifact past the TTL is still accepted for up to 24 h when its `tree` equals `HEAD^{tree}` **and** its `env` fingerprint (venv config, installed dist-info, python/node versions) matches, and the allow message says so (written by the non-hook runner `hooks/run-gate.sh` from the `**Gate**:` command in PROJECT_CONTEXT.md; no-op while Gate is unset). Also duplicated inline in merge-owning coder agents' frontmatter, whose matcher additionally covers `Bash` (`gh pr merge`) | All |
| **PreToolUse** on `Agent` | One spawn gate, 127-wrapped fail-closed: `hooks/require-skills-block.sh` — a spawn prompt for an agent that the `AGENT_TEAM.md` *Spawn-Prompt Binding Table* binds to a skill must carry a `## Required Skills` block naming it; the hook reads the table's own row set, which is why `verify-template-consistency.sh` diffs script against table | All |
| **PreToolUse** on `mcp__windows-mcp__Click\|Type` | Blocks Click/Type for test automation (use FlaUI) | dotnet-maui |
| **PostToolUse** on `Edit\|Write` | `hooks/post-edit-build.sh` — runs the command declared as `**Post-edit build**:` in `PROJECT_CONTEXT.md` after an edit for immediate feedback; a no-op when the key is absent; always exits 0 (a post-edit check must never block). Registered in every variant since v3.1; only variants that declare the key run anything | All (key-driven) |
| **PostToolUse** on `Bash\|PowerShell` | `hooks/bash-output-guard.sh` — `tool_response.stdout` and `stderr` over 12,000 chars are each written whole to `$TMPDIR/claude-bash-out/<session>-<epoch>[-stderr].log` and replaced in the transcript by head 4,000 + a marker naming the log + tail 4,000, via `hookSpecificOutput.updatedToolOutput` (same shape as `tool_response`, sibling fields copied). Payload reaches `node` on stdin, never argv — a 200 KB log exceeds the platform argument caps. Always exits 0, registered **unwrapped** — it can only ever pass output through | All |
| **SubagentStop** | Two hooks fire: a pipeline echo nudging the PO to advance the workstream when an agent finishes, and `hooks/enforce-agent-contract.sh` — a stop-gate that exit-2 blocks a coder from ending without `## Gate Results` + `## Spec Compliance` and a reviewer from ending without findings or the literal word `clean`. A marker file bounds it to one forced continuation; a second non-compliant stop passes with a `CONTRACT-ENFORCER:` stderr signal to the PO. Deliberately fail-open when broken and **never** 127-wrapped (a missing stop-gate must not trap agents in an unstoppable loop). Its verdict and loop-guard behaviour are covered by a behavioural fixture in `scripts/test-hooks.sh` (12 assertions, added v2.2.2 after a field report) — until then it had only degraded-path cases, which pass whatever the verdict logic does, and two defects lived in that gap | All |
| **SubagentStop** (no matcher) | `hooks/retro-ledger.sh` — parses the finished subagent's own transcript (`agent_transcript_path`), counts `tool_result` blocks matching `No such tool available\|BLOCKED:\|DELEGATE:\|CONTRACT VIOLATION\|hook error`, and appends one line per failing run to the project's auto-memory `memory/retro.md` (dead tools, blocking hook basenames, error count). Fail-open by construction and registered **unwrapped** — it cannot block, so a 127 wrapper would only invent a failure mode | All |
| **SessionStart** (no matcher) | `hooks/retro-brief.sh` — the **view** over `retro.md`, not the record: v3.0.1 drops budget-only rows and dedupes by agent id (last row wins) *before* tailing to 10, so the brief is one row per agent. Both transforms are measured fixes — a consumer's brief was 30 rows of nothing but budget warnings, and elsewhere one long-running agent held 11 of 30 rows and hid three of the four agents behind the tail. A row carrying `dead=` is never dropped: a missing tool grant is not a failure the agent reports, it just silently delivers something weaker. SessionStart stdout is injected as session context, so the PO fixes the cause (agent `tools:` allowlist, prompt, hook) before re-dispatching into the same wall. Unwrapped, fail-open | All |
| **PreToolUse** (no matcher) | `hooks/agent-budget-warn.sh` — per-`agent_id` tool-call budget: WARN once at 60, then **block on every threshold crossing** — 120, 180, 240, … Bounds the runaway single spawn (measured: median 15 calls, 35 of 150 agents over 60, 19 over 120, worst 417 — a single block does not stop a runaway). Every test is `-eq`, never `-ge`, so calls between thresholds pass and a blocked agent can still report. **`SendMessage` is exempt since v3.0.0 — neither counted nor blocked**; exempting only the block would let a `SendMessage` land on call 120 and consume the one crossing that would have stopped the runaway. Pure-shell hot path, threshold events only in `.claude/liveness.log`; WARN-on-127 | All |
| **PreCompact** | Snapshots worktree and branch state before context compaction | All |

Additionally, the 11 merge-owning coder agents carry the merge gate inline in their `.md` frontmatter as a belt-and-suspenders measure, since subagent hook inheritance from `settings.json` is not documented. The v1.x `Bash(git *)` / `Bash(gh *)` frontmatter blocks are gone — developer agents drive git through the CLI now.

## Repository Structure

```
claude-code-toolkit/
├── README.md · AGENTS.md · CHANGELOG.md · VERSION · CLAUDE.md   # CLAUDE.md = this repo's own project instructions
├── setup-project.sh / setup-project.ps1   # Bootstrap a project from a variant (Linux/macOS · Windows)
├── hooks/                                 # Root-tracked enforcement hooks (14 scripts) + hooks/lib/; copied whole into projects
├── scripts/                               # verify-template-consistency.sh, test-hooks.sh, test-server.sh, verify-consumers.sh, propagation tooling
├── server/                                # The template-sync MCP server (Python package template_sync; install.sh / install.ps1; tests/)
├── docs/
│   ├── getting-started.md                 # Prerequisites, adoption tiers, MCP servers
│   ├── setup.md                           # Setup walkthrough (Windows + Linux/macOS)
│   ├── templates.md                       # Variant comparison, placeholders, manifest
│   ├── architecture.md                    # This file
│   ├── design-rationale.md                # Why the template files say what they say (byte budgets, cuts)
│   ├── verification.md                    # Verification playbook: gates, hooks, verdict table
│   ├── template-sync.md                   # Keeping projects in sync with templates
│   ├── template-sync-migration-contract.md# Manifest format contract the server implements
│   └── plans/                             # Committed design specs and implementation plans, dated
├── templates/
│   ├── ownership.json                     # File classes (template / once), tracked paths, declared keys, skill floor
│   ├── general/                           # Any project, any language
│   │   ├── .claude/
│   │   │   ├── settings.json              # Permissions + hook registration (identical across variants)
│   │   │   ├── agents/                    # 6 agents: Explore, architect, code-reviewer, coder, ops, tester
│   │   │   └── rules/project.md           # once-class project rules seed
│   │   ├── CLAUDE.md · AGENT_TEAM.md · PROJECT_CONTEXT.md · PROJECT_STATE.md · VERIFICATION_PLAYBOOK.md · gitignore
│   ├── dotnet/                            # + dotnet-coder, rules/csharp.md, .editorconfig
│   ├── dotnet-maui/                       # + dotnet-coder, rules/csharp.md + xaml.md, .editorconfig
│   ├── rust-tauri/                        # + rust-coder, rules/rust.md + frontend.md, rustfmt.toml, .prettierrc
│   ├── java/                              # + java-coder, rules/java.md, .editorconfig
│   └── python/                            # + python-coder, rules/python.md, .editorconfig
├── mcp-servers/
│   └── HOWTO.md                           # MCP server installation guide
└── user-level-reference/                  # ~/.claude/ reference for new machines
    ├── CLAUDE.md · settings.json          # user-level instructions and settings
    ├── agents/                            # 6 generic agent definitions (incl. Explore)
    ├── skills/                            # 8 skills (commands were merged into skills)
    ├── hooks/                             # byte-identical mirror of the root hooks/ subset used at user level (10 of 14)
    ├── .mcp.json.template                 # MCP server config template
    └── settings-reference.md              # Annotated settings reference
```

`AGENT_TEAM.md`, the generic agents and the hook scripts are byte-identical across the six variants; `scripts/verify-template-consistency.sh` asserts it.
