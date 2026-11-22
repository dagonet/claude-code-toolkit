# Slim Core Plugin Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `cct` keeps only the PO/T1-T4 workflow, safety and their plumbing. Everything else moves, with unchanged behaviour, into four optional plugins (`cct-jev`, `cct-learning`, `cct-guards`, `cct-helpers`) and into the language plugins.

**Architecture:**
- Each optional plugin is a folder under `plugins/` with its own manifest and, if it has hooks, its own `hooks/hooks.json`.
- A plugin with hooks carries pinned copies of `run-hook.sh` and the `hooks/lib/` files it uses. A plugin's own `hook-class.sh` differs only in its `case … esac` table.
- The core resolves toolkit and language-plugin agent types from one fixed table, which copies use too.
- The challenge command becomes a core T3/T4 step.

**Tech Stack:** bash hooks, JSON manifests, Markdown, Python (Jev and its tests), the existing test scripts.

**Spec:** `docs/plans/2026-11-22-slim-core-plugin-split-design.md`, approved 2026-11-22 19:24. §10 is binding. This plan was revised after the architect's challenge of 2026-11-22; the challenge's rulings are listed at the end.

## Global Constraints

- **Branch and version:** branch `feat/v6.3`, worktree `~/git/.worktrees/claude-code-toolkit/v6.3`. The plan ships inside **v7.0.0** and is built after the backlog-discipline plan. Every plugin's `version` equals `VERSION`.
- **Nothing is deleted.** Moved files keep their behaviour, and their tests move with them and stay green.
- **Each move task leaves the per-commit Test green.** Every consistency check a move touches is updated in the **same** commit. These are the known ones (line numbers are as of `ab5e6da`; locate them by content):
  - **72:** the hard-coded plugin list (`:4991`).
  - **80:** restrict it to plugin folders that hold a `.mcp.json`, and pick its control from those (`:5131-5169`).
  - **71:**
    - compare the **union** of `hooks/` and `plugins/*/hooks/` against the frozen set plus `C71_PLUGIN_ONLY` (`:4739-4773`);
    - the root form-U row accepts `${CLAUDE_PROJECT_DIR:-.}/plugins/<p>/hooks/<n>.sh` (`:959-967`).
  - **74:** per plugin, including the `cct-jev` marker's SessionEnd and timeout.
  - **76:** update every `cct:<x>` mention in the same commit as its move: `README.md`, `AGENTS.md`, `user-level-reference/{CLAUDE.md,README.md}`, templates, skills and agents. The sync-template old-name warning gets an explicit exemption.
  - **65:** Jev paths (`:3706-3709`).
  - **35:** caps are only ever lowered. Re-measure in every task that adds "if installed" wording, including `project-instructions.md` (cap 960). Never raise a cap.
  - **Census checks that glob only `hooks/*.sh`** widen to `plugins/*/hooks/*.sh`: 21c-2 (`:679`), 21c-2e (`:1179`), `:1493`, and the 71 trap/return audits (`:4798`).
- **What moves (exact):**

  | Plugin | Hooks | Skills | Agents |
  |---|---|---|---|
  | `cct-jev` | `jev-route`, `jev-notice` | `jev` (with `.py` files and `tests/`) | — |
  | `cct-learning` | `retro-ledger`, `retro-brief` | `retro-review` | — |
  | `cct-guards` | `read-size-gate`, `bash-output-guard`, `agent-budget-warn`, `post-edit-build` | — | — |
  | `cct-helpers` | — | `commit`, `contribute-upstream`, `karpathy-guidelines`, `mcp-usage` | — |
  | `dotnet-tools` / `python-tools` / `rust-tools` | — | — | `<lang>-coder` |
  | `java-tools` (new, no `.mcp.json`) | — | — | `java-coder` |

  **Stays in `cct`:**
  - agents `coder`, `code-reviewer`, `tester`, `architect`, `Explore`, `ops`;
  - skills `sprint`, `challenge`, `sync-template`;
  - every other hook, including `agent-result-notes`, `backlog-item-check` and `backlog-brief`;
  - `hooks/lib/`, `output-styles/`, templates, server and scripts.
- **Pinned copies:** each optional plugin's `hooks/run-hook.sh` and `hooks/lib/*.sh` are byte-identical to `cct`'s. `hook-class.sh` copies are identical **outside** their `case … esac` table; each table lists only that plugin's hooks, each line copied verbatim from `cct`'s table. `run-hook.sh`'s "Reinstall the cct plugin" text becomes plugin-neutral before it is copied.
- **Agent type table** (in `hooks/lib/agent-model.sh`, consulted before the `CLAUDE_PLUGIN_ROOT/agents/` lookup): `cct:coder`, `cct:code-reviewer`, `cct:tester`, `cct:architect`, `cct:Explore`, `cct:ops`, `dotnet-tools:dotnet-coder`, `python-tools:python-coder`, `rust-tools:rust-coder` and `java-tools:java-coder`. Each maps to `model`, `effort` and `pipeline`. A consistency check pins every row against the agent file's frontmatter, two-sided.
- **`cct-jev` marker:**
  - its own folder, not `${TMPDIR}/cct-$(id -u)/`, so it can never satisfy the template guard;
  - it keeps the MINGW `-O` skip;
  - `model-floor` steps aside only when the switch says `"route": true` **and** this session has the `cct-jev` marker;
  - calls without a session id (`jev-route.sh`, `jev-notice.sh`, executed mode) keep today's check that the plugin's own `skills/jev/jev_route.py` exists.
- **Wording:** every mention of a moved part says "if `<plugin>` is installed", in all six variants where the file is per variant.
- **Experiments:** `claude plugin` and installer experiments run only with `HOME=$(mktemp -d)` and `env -u CLAUDE_CONFIG_DIR`. Never copy credentials, and never touch the live `~/.claude`.
- **Files:** LF only. `AGENT_TEAM.md` and `.claude/settings.json` stay byte-identical across the six variants. Move files with `git mv`.
- **KISS.**

## Review Focus

1. **The template guard with only the `cct-jev` marker present (the `cct` marker absent) still refuses.** Task 5.
2. **A `cct:coder` spawn routed by Jev from inside `cct-jev`** resolves to `own sonnet`, not `none`. Task 1 (table), Task 5 (row through the copy).
3. **A failing `dotnet-tools:dotnet-coder` report gives the step-up note naming `opus`** (the table feeds `agent-result-notes`). Task 1.
4. **`cct-guards` hooks run from their own copies with the same verdicts as before**, and `cct`'s `hooks.json` no longer names them. Task 3.
5. **A kept project file naming `cct:dotnet-coder`:** `sync-template` warns with the new name. Task 7.

---

### Task 1: Agent type table, and language coders into the language plugins

**Files:**
- **`git mv`:** `agents/{dotnet,python,rust,java}-coder.md` → `plugins/<lang>-tools/agents/`.
- **Create:** `plugins/java-tools/.claude-plugin/plugin.json` and its marketplace entry, a description starting "Optional:".
- **Modify:**
  - `hooks/lib/agent-model.sh` (the table, used by `am_resolve`);
  - `hooks/enforce-agent-contract.sh` (pipeline flag from the table for plugin types);
  - `templates/<six>/CLAUDE.md` team tables: `cct:<lang>-coder` becomes `cct:coder`, plus "prefer `<lang>-tools:<lang>-coder` if installed";
  - the `.claude/rules/*.md` of dotnet, dotnet-maui, java, python and rust-tauri: replace "Do NOT substitute `coder` for `<lang>-coder`" with the new default;
  - `templates/general/AGENT_TEAM.md` (then `cp`);
  - `setup-project.sh`/`.ps1`: the dotnet, dotnet-maui and rust-tauri default **Gate** gains the format check (`dotnet format --verify-no-changes`, `cargo fmt --check`); python and java already have one;
  - checks 72, 76 and 80, plus check 75 extended to `plugins/*/agents`;
  - the new `agent type table` check;
  - `scripts/test-hooks.sh`, `scripts/test-setup-project.sh` fixtures.
- **Not touched:** `hooks/enforce-delegation.sh` keys on `agent_id` and names only core types.

- [ ] **Step 1: Failing rows.**
  - `am_resolve dotnet-tools:dotnet-coder` gives `own sonnet <effort>`.
  - `agent-result-notes` on a failing `dotnet-tools:dotnet-coder` report gives the `opus` step-up note (Review Focus 3).
  - `enforce-agent-contract` on its report without contract lines refuses.
  - An unknown `foo-tools:foo-coder` gives no change.
  - The table check, with a control that edits one frontmatter value.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement and move.**
- [ ] **Step 4: Run** the full `test-hooks.sh`, the consistency script and `test-setup-project.sh` (foreground). Expected: 0 FAIL, PASS, PASS.
- [ ] **Step 5: Commit** `feat!: language coders move into the language plugins; one agent type table in the core`.

### Task 2: `cct-guards` (first optional plugin, with the pinned-copy check)

**Files:**
- **Create:**
  - `plugins/cct-guards/.claude-plugin/plugin.json` and its marketplace entry;
  - `git mv` of the four hooks;
  - copies of `run-hook.sh` (made plugin-neutral first) and the libs they need;
  - a `hook-class.sh` copy with the four table lines;
  - `plugins/cct-guards/hooks/hooks.json` with the four registrations exactly as today.
- **Modify:**
  - `hooks/hooks.json` and `hooks/lib/hook-class.sh` (remove the four);
  - the root `.claude/settings.json` `post-edit-build` path → `${CLAUDE_PROJECT_DIR:-.}/plugins/cct-guards/hooks/post-edit-build.sh`;
  - checks 71, 72 and 74, plus the census globs;
  - the new `pinned plugin copies` check (two-sided: a copy with one changed byte, and a `hook-class.sh` copy with a changed `hc_skip` line, are flagged);
  - `scripts/test-hooks.sh` paths;
  - "if installed" wording: `user-level-reference/CLAUDE.md` Read & Search, the agents' `agent-budget-warn` mentions, the six `PROJECT_CONTEXT.md` `Post-edit build` lines, `templates/ownership.json:31-32` effect text, `skills/sync-template/SKILL.md`;
  - check 35 re-measured.

- [ ] **Step 1:** Failing rows: each moved hook runs via `plugins/cct-guards/hooks/run-hook.sh <name>` with today's verdicts (Review Focus 4). Plus the copy check.
- [ ] **Step 2:** Move and implement. Run the full `test-hooks.sh` and the consistency script. Expected: 0 FAIL, PASS.
- [ ] **Step 3: Commit** `feat!: cost and context guards move to the optional cct-guards plugin`.

### Task 3: `cct-learning`

Same shape as Task 2:
- `retro-ledger`, `retro-brief` and `skills/retro-review`;
- the `AGENT_TEAM.md` retro-ledger line becomes "if `cct-learning` is installed";
- `scripts/plugin-smoke.sh` row 5 gains `--plugin-dir plugins/cct-learning`.

Commit `feat!: the learning loop moves to the optional cct-learning plugin`.

### Task 4: `cct-helpers`

- `git mv` the four skills.
- "If installed" wording in:
  - the user-level karpathy line;
  - the six `PROJECT_CONTEXT.md` and six `.claude/project-instructions.md` (`mcp-usage`);
  - the agents' `## Skills` tables;
  - other skills' `commit` mentions.
- Checks 76 and 35.

Commit `feat!: small helper skills move to the optional cct-helpers plugin`.

### Task 5: `cct-jev`

**Files:**
- **`git mv`:** `skills/jev` and `hooks/{jev-route,jev-notice}.sh` → `plugins/cct-jev/`.
- **Copies** of the libs, including `agent-model.sh`.
- **The `cct-jev` session-marker hook,** in its own folder, with SessionStart and SessionEnd registrations (check 74 per plugin).
- **Modify:**
  - `hooks/lib/agent-model.sh` `am_jev_routing`: the session-id branch requires the `cct-jev` marker; the no-session-id branch keeps the plugin-file check;
  - the `/cct:jev` texts in `jev-notice.sh`, `jev_ctl.py`, `test_ctl.py`;
  - the J-PY path in `scripts/test-hooks.sh` (drop `JEV_REPO_ROOT`, so `jevtest.py` uses `cct-jev`'s copy);
  - the I2/V5J fixtures;
  - check 65;
  - `skills/jev/SKILL.md` command paths;
  - `user-level-reference/CLAUDE.md` (no `/cct:jev` left: the model-ladder plan already removed the exception);
  - `user-level-reference/README.md`.

- [ ] **Step 1: Failing rows.**
  - switch on, `cct-jev` marker present: the floor steps aside;
  - switch on, no marker: the floor applies;
  - only the `cct-jev` marker present, `cct` marker absent: the template guard refuses (Review Focus 1);
  - `cct-jev`'s copy resolves `cct:coder` to `own sonnet` (Review Focus 2);
  - the Jev Python tests pass from the new path.
- [ ] **Step 2:** Implement. Run the full `test-hooks.sh`, the Jev tests and the consistency script. Expected: all green.
- [ ] **Step 3: Commit** `feat!: Jev moves to the optional cct-jev plugin; the floor steps aside only when cct-jev is loaded`.

### Task 6: The challenge becomes a core T3/T4 step

**Files:**
- `skills/challenge/SKILL.md`:
  - remove `disable-model-invocation: true`;
  - add "If you are the architect, run both passes yourself" beside the delegation lines (`:24`, `:56`).
- `templates/general/AGENT_TEAM.md` (then `cp`):
  - "T3 and T4: the plan is challenged (`challenge` skill) before coding starts; at T4 the architect runs it as part of its design review.";
  - a checkpoint row `Plan challenged | — | — | Yes | Yes`.
- `skills/sprint/SKILL.md`: T3/T4 tasks are challenged before dispatch.
- Check 6's rationale comment, updated (`:63-80`), plus an assertion for the new row.

Commit `feat: the plan challenge is a required T3/T4 step`.

### Task 7: Installer, delivery check, sync warning, docs, smoke

**Files:**
- `scripts/install-user-level-linux.sh`: `--with <plugin,...>` for the first v7 run. It already reinstalls previously installed `@dagonet` sub-plugins (`:122`, `:152`).
- `scripts/verify-user-level-drift.sh`:
  - an informational list of the optional plugins;
  - drift only when `enabledPlugins` names one not installed at `VERSION`.
- `skills/sync-template/SKILL.md`: a step that warns, and does not edit, on old names in kept project files, naming the new one (check 76 exemption).
- **Docs:**
  - `docs/architecture.md`, `README.md`, `AGENTS.md`, `docs/verification.md`;
  - `docs/plugin-migration-windows.md` (the PC install lines), `docs/getting-started.md`, `docs/templates.md`, `docs/template-sync.md`;
  - `CHANGELOG.md` v7.0.0: the name map, one install line per plugin, the plain-update warning.
- **Smoke:** `scripts/plugin-smoke.sh` gains a row that runs `claude -p --plugin-dir <cct root>` with `cct` alone. Assert that no registered command path names a moved script. Run it at release, not per commit.

- [ ] **Step 1:** Test rows for `--with` parsing and the drift rule. The sync warning gets a fixture.
- [ ] **Step 2:** Implement and write the docs.
- [ ] **Step 3:** Run the full gate `bash hooks/run-gate.sh` (foreground). Expected: GATE PASS.
- [ ] **Step 4: Commit** `feat: installer --with, drift reads enabledPlugins, sync warns on old names; v7 docs`.

## Release

This plan folds into the single v7.0.0 release task.
- The user's choice for both machines: `cct-guards`, `cct-learning` and `cct-helpers`; not `cct-jev`; language plugins only where used.
- The live update is attended.

## Challenge rulings (2026-11-22)

- **Cut:**
  - the `enforce-delegation` change (it keys on `agent_id`);
  - the empty-skeleton task (each move creates its own plugin);
  - the per-commit install test, replaced by static checks (71 union) plus a release-time smoke row. *(User nod pending.)*
- **Added:**
  - the per-commit check updates (72, 80, 71, 74, 76, 65, 35, census globs);
  - the agent type table extended to `cct:*`, which fixes Jev routing from inside `cct-jev`;
  - the `cct-jev` marker kept out of the template guard's folder;
  - a `hook-class.sh` identity check outside the table;
  - the Jev test paths;
  - the missing per-variant and doc files;
  - the challenge skill's architect line;
  - format checks in Gate for three variants only.
